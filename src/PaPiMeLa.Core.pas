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
    - 破棄順序は TextInput → Joystick → Audio → Video → Timer → Events
    - finalization 節では何もしない。破棄はアプリの Context.Free に委ねる
    - Context を生成したスレッドがメインスレッド。子はそれを継承する

  NOT RESOLVED:
    - Audio / Joysticks は未実装のため常に nil。要求されたら EPMLUnsupported を投げる
    - TPMLTimerService は TicksNS のみ。タイマースレッドと Timer.AddTimer は
      PaPiMeLa.Threading（#8）の後
    - TPMLHints / TPMLLog は未実装。Log は当面 Context.LogInfo で標準出力へ
    - RunOnMainThread は Threading 着手時

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
  PaPiMeLa.Events,
  PaPiMeLa.Video,
  PaPiMeLa.TextInput;

type
  TPMLSubsystem  = (Video, Audio, Joystick, Gamepad, Haptic, TextInput);
  TPMLSubsystems = set of TPMLSubsystem;

  TPMLLogLevel = (Verbose, Debug, Info, Warn, Error_);

  { 単調増加時刻の提供。 }
  TPMLTimerService = class sealed(TPMLSystemObject)
  public
    function TicksNS: UInt64;
    function TicksMS: UInt64;
  end;

  TPMLContextOptions = class
  public
    // 使用する IME バックエンドを明示指定する（'fcitx' / 'ibus' / 'wayland' / 'none'）。
    // 空なら PAPIMELA_IME 環境変数、それも無ければ自動選択。
    PreferredTextInput: String;
    // 使用するビデオバックエンドを明示指定する（'wayland'）。空なら PAPIMELA_VIDEO。
    PreferredVideo    : String;
    // イベントキューの容量（イベント数）。
    EventQueueCapacity: Integer;
    MinimumLogLevel   : TPMLLogLevel;
    constructor Create;
  end;

  TPMLContext = class sealed(TPMLObject)
  strict private
    FEvents    : TPMLEventQueue;
    FTimer     : TPMLTimerService;
    FVideo     : TPMLVideoSystem;
    FTextInput : TPMLTextInputSystem;
    FSubsystems: TPMLSubsystems;
    FMinLevel  : TPMLLogLevel;
  public
    constructor Create(ASubsystems: TPMLSubsystems; AOptions: TPMLContextOptions = nil);
    destructor Destroy; override;

    procedure Log(ALevel: TPMLLogLevel; const AMsg: String);
    procedure LogFmt(ALevel: TPMLLogLevel; const AFmt: String; const AArgs: array of const);

    property Events    : TPMLEventQueue      read FEvents;
    property Timer     : TPMLTimerService    read FTimer;
    property Video     : TPMLVideoSystem     read FVideo;
    property TextInput : TPMLTextInputSystem read FTextInput;
    property Subsystems: TPMLSubsystems      read FSubsystems;
  end;

implementation

constructor TPMLContextOptions.Create;
begin
  inherited Create;
  PreferredTextInput := '';
  PreferredVideo := '';
  EventQueueCapacity := 256;
  MinimumLogLevel := TPMLLogLevel.Info;
end;

function TPMLTimerService.TicksNS: UInt64;
begin
  Result := PMLNowNS;
end;

function TPMLTimerService.TicksMS: UInt64;
begin
  Result := PMLNowNS div 1000000;
end;

constructor TPMLContext.Create(ASubsystems: TPMLSubsystems; AOptions: TPMLContextOptions);
var
  Opts    : TPMLContextOptions;
  OwnsOpts: Boolean;
begin
  // Context 自身はルートなので ContextRef は nil。生成スレッドがメインになる。
  inherited Create(nil);
  FSubsystems := ASubsystems;

  OwnsOpts := AOptions = nil;
  if OwnsOpts then
    Opts := TPMLContextOptions.Create
  else
    Opts := AOptions;
  try
    FMinLevel := Opts.MinimumLogLevel;

    // 生成順 = 破棄の逆順。Events と Timer は常に存在する。
    FEvents := TPMLEventQueue.Create(Self, Self, Opts.EventQueueCapacity);
    FTimer := TPMLTimerService.Create(Self, Self);

    if TPMLSubsystem.Video in ASubsystems then
    begin
      FVideo := TPMLVideoSystem.Create(Self, Self, FEvents, Opts.PreferredVideo);
      LogFmt(TPMLLogLevel.Info, 'video backend: %s', [FVideo.BackendName]);
    end;
    if TPMLSubsystem.Audio in ASubsystems then
      raise EPMLUnsupported.Create('the Audio subsystem is not implemented yet');
    if (TPMLSubsystem.Joystick in ASubsystems)
      or (TPMLSubsystem.Gamepad in ASubsystems)
      or (TPMLSubsystem.Haptic in ASubsystems) then
      raise EPMLUnsupported.Create('the input subsystems are not implemented yet');

    if TPMLSubsystem.TextInput in ASubsystems then
    begin
      FTextInput := TPMLTextInputSystem.Create(Self, Self, FEvents,
        Opts.PreferredTextInput);
      FEvents.KeyFilter := FTextInput as IPMLKeyFilter;
      LogFmt(TPMLLogLevel.Info, 'text input backend: %s', [FTextInput.BackendName]);
    end;
  finally
    if OwnsOpts then
      Opts.Free;
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
  inherited Destroy;
end;

procedure TPMLContext.Log(ALevel: TPMLLogLevel; const AMsg: String);
const
  Names: array[TPMLLogLevel] of String = ('VERBOSE', 'DEBUG', 'INFO', 'WARN', 'ERROR');
begin
  if ALevel < FMinLevel then
    Exit;
  // TPMLLog（#11 章の Log ユニット）ができたらそちらへ委譲する。
  WriteLn(ErrOutput, Format('[papimela/%s] %s', [Names[ALevel], AMsg]));
end;

procedure TPMLContext.LogFmt(ALevel: TPMLLogLevel; const AFmt: String;
  const AArgs: array of const);
begin
  Log(ALevel, Format(AFmt, AArgs));
end;

end.
