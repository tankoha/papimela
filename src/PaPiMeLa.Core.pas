{
  PaPiMeLa.Core — TPMLContext と所有グラフのルート

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §2.4（所有グラフ）、§11 #2

  WHAT:
    アプリが生成する唯一のルートオブジェクト。要求されたサブシステムを生成し、
    破棄は生成の逆順で行う。SDL の static SDL_VideoDevice *_this のような
    グローバルシングルトンは存在しない。

  WHY:
    SDL は SDL_video.c のファイルスコープ変数 _this を 456 箇所で参照しており、
    複数のビデオデバイスを持てない構造だった。papimela では所有関係を明示した
    オブジェクトグラフにし、同一プロセスに複数の Context を作ることを禁じない。

  RESOLVED:
    - 破棄順序は TextInput → Joystick → Audio → Video → Timer → Events → Log → Properties → Hints
    - finalization 節では何もしない。破棄はアプリの Context.Free に委ねる
    - Context を生成したスレッドがメインスレッド。子はそれを継承する
    - Hints・Properties・Log はサブシステムより先に作り、後に壊す（どのサブシステムも
      作るときからログを書ける）

  NOT RESOLVED:
    - Audio / Joysticks は未実装のため常に nil。要求されたら EPMLUnsupported を投げる

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Core;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Properties,
  PaPiMeLa.Log,
  PaPiMeLa.Events,
  PaPiMeLa.Time,
  PaPiMeLa.Video,
  PaPiMeLa.TextInput;

type
  TPMLSubsystem  = (Video, Audio, Joystick, Gamepad, Haptic, TextInput);
  TPMLSubsystems = set of TPMLSubsystem;

  { 単調増加時刻と、待つこと。どれも Context を要らないので class 関数
    （TPMLTimerService.Delay(16) とも Ctx.Timer.Delay(16) とも書ける）。
    待つ処理は PaPiMeLa.Time にある。 }
  TPMLTimerService = class sealed(TPMLSystemObject)
  strict private
    FQueue: TPMLTimerQueue;
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject);
    destructor Destroy; override;
    // タイマー（SDL_AddTimer / SDL_AddTimerNS / SDL_RemoveTimer）。約束は PaPiMeLa.Time の
    // TPMLTimerQueue。コールバックはタイマーのスレッドで呼ばれる。
    function  AddTimer(AIntervalMs: LongWord; ACallback: TPMLTimerCallback): TPMLTimerID;
    function  AddTimerNS(AIntervalNS: UInt64; ACallback: TPMLTimerCallbackNS): TPMLTimerID;
    function  RemoveTimer(AID: TPMLTimerID): Boolean;
    property  Queue: TPMLTimerQueue read FQueue;
    class function TicksNS: UInt64; static;
    class function TicksMS: UInt64; static;
    class procedure Delay(AMs: LongWord); static;
    class procedure DelayNS(ANs: UInt64); static;
    class procedure DelayPrecise(ANs: UInt64); static;
  end;

  { Context を作るときの選択肢。値型なので解放は要らない（F-7）。

    書き方:
      Opts := TPMLContextOptions.Default;
      Opts.PreferredVideo := 'dummy';
      Ctx := TPMLContext.Create([TPMLSubsystem.Video], Opts);

    Default を通さずに宣言しただけの変数も、Initialize 演算子が既定値で
    埋める（中身が不定にならない）。ただし FPC 3.2 はその変数に「初期化
    されていないようだ」と警告するので、普段は Default から書く。 }
  TPMLContextOptions = record
    // 使用する IME バックエンドを明示指定する（'fcitx' / 'ibus' / 'wayland' / 'none'）。
    // 空なら PAPIMELA_IME 環境変数、それも無ければ自動選択。
    PreferredTextInput: String;
    // 使用するビデオバックエンドを明示指定する（'wayland'）。空なら PAPIMELA_VIDEO。
    PreferredVideo    : String;
    // イベントキューの容量（イベント数）。1 以上。
    EventQueueCapacity: Integer;
    // ヒント PAPIMELA_LOGGING で決まらなかったカテゴリの優先度（TPMLLog.Create の
    // ABaseDefault）。既定は Info で、全部のカテゴリが Info から出る。Invalid なら SDL と
    // 同じ既定（APP は Info、他の多くは Error_）。
    MinimumLogLevel   : TPMLLogPriority;
    class function Default: TPMLContextOptions; static;
    class operator Initialize(var AOptions: TPMLContextOptions);
  private
    class procedure SetDefaults(var AOptions: TPMLContextOptions); static;
  end;

  TPMLContext = class sealed(TPMLObject)
  strict private
    FEvents    : TPMLEventQueue;
    FTimer     : TPMLTimerService;
    FVideo     : TPMLVideoSystem;
    FTextInput : TPMLTextInputSystem;
    FSubsystems: TPMLSubsystems;
    FHints     : TPMLHints;
    FProperties: TPMLProperties;
    FLog       : TPMLLog;
  public
    constructor Create(ASubsystems: TPMLSubsystems); overload;
    constructor Create(ASubsystems: TPMLSubsystems;
      const AOptions: TPMLContextOptions); overload;
    destructor Destroy; override;

    // AProc をメインスレッドで動かす（SDL_RunOnMainThread）。どのスレッドから呼んでもよい。
    // 他のスレッドからなら次の Events.Pump（Poll / Wait の中も）で動く。AWait なら動き終わる
    // まで待ち、動いたら True（Context が先に壊れたら False）。
    function  RunOnMainThread(AProc: TPMLMainThreadProc; AWait: Boolean = False): Boolean;

    // ヒント（SDL_SetHint 系）、大域のプロパティ（SDL_GetGlobalProperties）、ログ（SDL_Log 系）。
    property Hints     : TPMLHints           read FHints;
    property Properties: TPMLProperties      read FProperties;
    property Log       : TPMLLog             read FLog;
    property Events    : TPMLEventQueue      read FEvents;
    property Timer     : TPMLTimerService    read FTimer;
    property Video     : TPMLVideoSystem     read FVideo;
    property TextInput : TPMLTextInputSystem read FTextInput;
    property Subsystems: TPMLSubsystems      read FSubsystems;
  end;

implementation

// 既定値の正本。Default と Initialize 演算子の両方がここを通る。
class procedure TPMLContextOptions.SetDefaults(var AOptions: TPMLContextOptions);
begin
  AOptions.PreferredTextInput := '';
  AOptions.PreferredVideo := '';
  AOptions.EventQueueCapacity := 256;
  AOptions.MinimumLogLevel := TPMLLogPriority.Info;
end;

class operator TPMLContextOptions.Initialize(var AOptions: TPMLContextOptions);
begin
  SetDefaults(AOptions);
end;

class function TPMLContextOptions.Default: TPMLContextOptions;
begin
  // Result は Initialize 演算子で既に埋まっているが、FPC 3.2 はそれを知らずに
  // 「初期化されていない」と警告する。フィールドを 1 つ書いてから渡すと黙る。
  // Initialize 演算子から Default を呼ぶ形にはできない（互いに呼び合って落ちる。実測）。
  Result.PreferredVideo := '';
  SetDefaults(Result);
end;

constructor TPMLTimerService.Create(AContextRef: TObject; AOwner: TPMLObject);
begin
  inherited Create(AContextRef, AOwner);
  FQueue := TPMLTimerQueue.Create;
end;

destructor TPMLTimerService.Destroy;
begin
  FreeAndNil(FQueue);
  inherited Destroy;
end;

function TPMLTimerService.AddTimer(AIntervalMs: LongWord; ACallback: TPMLTimerCallback): TPMLTimerID;
begin
  Result := FQueue.Add(AIntervalMs, ACallback);
end;

function TPMLTimerService.AddTimerNS(AIntervalNS: UInt64; ACallback: TPMLTimerCallbackNS): TPMLTimerID;
begin
  Result := FQueue.AddNS(AIntervalNS, ACallback);
end;

function TPMLTimerService.RemoveTimer(AID: TPMLTimerID): Boolean;
begin
  Result := FQueue.Remove(AID);
end;

class function TPMLTimerService.TicksNS: UInt64;
begin
  Result := PMLNowNS;
end;

class function TPMLTimerService.TicksMS: UInt64;
begin
  Result := PMLNowNS div 1000000;
end;

class procedure TPMLTimerService.Delay(AMs: LongWord);
begin
  PMLDelay(AMs);
end;

class procedure TPMLTimerService.DelayNS(ANs: UInt64);
begin
  PMLDelayNS(ANs);
end;

class procedure TPMLTimerService.DelayPrecise(ANs: UInt64);
begin
  PMLDelayPrecise(ANs);
end;

constructor TPMLContext.Create(ASubsystems: TPMLSubsystems);
begin
  Create(ASubsystems, TPMLContextOptions.Default);
end;

constructor TPMLContext.Create(ASubsystems: TPMLSubsystems;
  const AOptions: TPMLContextOptions);
begin
  // Context 自身はルートなので ContextRef は nil。生成スレッドがメインになる。
  inherited Create(nil);
  FSubsystems := ASubsystems;
  if AOptions.EventQueueCapacity < 1 then
    raise EPMLArgument.CreateFmt('EventQueueCapacity must be at least 1 (got %d)',
      [AOptions.EventQueueCapacity]);
  // AOptions は値で読むだけで、Context は覚えない。
  FHints := TPMLHints.Create;
  FProperties := TPMLProperties.Create;
  FLog := TPMLLog.Create(FHints, AOptions.MinimumLogLevel);

  // 生成順 = 破棄の逆順。Events と Timer は常に存在する。
  FEvents := TPMLEventQueue.Create(Self, Self, AOptions.EventQueueCapacity);
  FTimer := TPMLTimerService.Create(Self, Self);

  if TPMLSubsystem.Video in ASubsystems then
  begin
    FVideo := TPMLVideoSystem.Create(Self, Self, FEvents, AOptions.PreferredVideo);
    FLog.Info(PML_LOG_CATEGORY_VIDEO, 'video backend: ' + FVideo.BackendName);
  end;
  if TPMLSubsystem.Audio in ASubsystems then
    raise EPMLUnsupported.Create('the Audio subsystem is not implemented yet');
  if (TPMLSubsystem.Joystick in ASubsystems)
    or (TPMLSubsystem.Gamepad in ASubsystems)
    or (TPMLSubsystem.Haptic in ASubsystems) then
    raise EPMLUnsupported.Create('the input subsystems are not implemented yet');

  if TPMLSubsystem.TextInput in ASubsystems then
  begin
    // ビデオ（あれば）を渡す。text-input-v3 はウィンドウの接続の上で動く。
    FTextInput := TPMLTextInputSystem.Create(Self, Self, FEvents,
      AOptions.PreferredTextInput, FVideo);
    FEvents.KeyFilter := FTextInput as IPMLKeyFilter;
    FLog.Info(PML_LOG_CATEGORY_INPUT, 'text input backend: ' + FTextInput.BackendName);
  end;
end;

destructor TPMLContext.Destroy;
begin
  // §2.4 の破棄順序: TextInput → Joystick → Audio → Video → Timer → Events
  if Assigned(FEvents) then
    FEvents.KeyFilter := nil;
  FreeAndNil(FTextInput);
  FreeAndNil(FVideo);
  FreeAndNil(FTimer);
  FreeAndNil(FEvents);
  // Log はヒントの呼び出しを外すので、Hints より先に壊す
  FreeAndNil(FLog);
  FreeAndNil(FProperties);
  FreeAndNil(FHints);
  inherited Destroy;
end;

function TPMLContext.RunOnMainThread(AProc: TPMLMainThreadProc; AWait: Boolean): Boolean;
begin
  Result := FEvents.RunOnMainThread(AProc, AWait);
end;

end.
