{
  PaPiMeLa.Audio.Backend — オーディオのバックエンドの抽象と、物理デバイス

  Origin : ported from SDL (src/audio/SDL_sysaudio.h, src/audio/SDL_audio.c)
           Scope: SDL_AudioDriverImpl の 14 個の入り口と 4 つの能力、その既定
           （SDL_AudioXxx_Default と、既定の 2 台だけを持つバックエンドの DetectDevices）、
           SDL_AudioDevice の中身、バックエンドが中核を呼ぶ口（SDL_AddAudioDevice・
           SDL_AudioDeviceDisconnected・SDL_DefaultAudioDeviceChanged・
           SDL_AudioDeviceFormatChanged・SDL_FindPhysicalAudioDeviceByHandle・
           SDL_UpdatedAudioDeviceFormat・SDL_GetDefaultSampleFramesFromFreq・
           SDL_GetAudioThreadName・Ref / UnrefPhysicalAudioDevice・デバイススレッドの 1 回分）、
           既定の値（DEFAULT_AUDIO_xxx と既定のデバイス名）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.5、§4.5、§11 #51

  WHAT:
    具象バックエンド（Dummy、PipeWire など）が派生する TPMLAudioBackend と、中核
    （PaPiMeLa.Audio の TPMLAudioSystem）が実装してバックエンドに渡す TPMLAudioCore、
    両方が触る物理デバイス TPMLAudioDevice。

  WHY:
    SDL のバックエンドは中核の関数（SDL_AddAudioDevice など）を直接呼ぶ。papimela では
    中核が公開層（PaPiMeLa.Audio）にあるので、バックエンドの単位が公開層を uses すると
    循環する。中核の口を抽象クラス TPMLAudioCore にしてここに置き、公開層が実装する。

  RESOLVED:
    - 物理デバイスは公開しない。アプリは ID（TPMLAudioDeviceID。SDL と同じ値の作り方）で
      指す（持ち主の判断、2026-10-14。hotplug で別のスレッドから消えても宙に浮かない）
    - SDL が切断のときに差し替える関数（Zombie*）は、TPMLAudioDevice.ZombieFunctions の
      印にして、中核が呼び分ける

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Audio.Backend;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Atomic,
  PaPiMeLa.Threading,
  PaPiMeLa.Audio.Convert;

type
  { オーディオのデバイスの ID（SDL_AudioDeviceID）。ビット 0 が 1 なら再生、0 なら録音。
    ビット 1 が 1 なら物理、0 なら論理（開いたもの）。0 は「無い」。 }
  TPMLAudioDeviceID = type LongWord;
  TPMLAudioDeviceIDs = array of TPMLAudioDeviceID;

const
  // 既定のデバイスを開くときに使う ID（SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK / RECORDING）。
  PML_AUDIO_DEVICE_DEFAULT_PLAYBACK  = TPMLAudioDeviceID($FFFFFFFF);
  PML_AUDIO_DEVICE_DEFAULT_RECORDING = TPMLAudioDeviceID($FFFFFFFE);

  // よく分からないときの既定（SDL_sysaudio.h の DEFAULT_xxx。CD の音質）。
  PML_DEFAULT_PLAYBACK_DEVNAME  = 'System audio playback device';
  PML_DEFAULT_RECORDING_DEVNAME = 'System audio recording device';
  PML_DEFAULT_AUDIO_PLAYBACK_FORMAT    = PML_AUDIO_S16;
  PML_DEFAULT_AUDIO_PLAYBACK_CHANNELS  = 2;
  PML_DEFAULT_AUDIO_PLAYBACK_FREQUENCY = 44100;
  PML_DEFAULT_AUDIO_RECORDING_FORMAT    = PML_AUDIO_S16;
  PML_DEFAULT_AUDIO_RECORDING_CHANNELS  = 1;
  PML_DEFAULT_AUDIO_RECORDING_FREQUENCY = 44100;

type
  { バックエンドの能力（SDL_AudioDriverImpl の bool の 4 つ）。
      ProvidesOwnCallbackThread    : デバイススレッドを自分で持つ（PipeWire など）。中核はスレッドを作らない
      HasRecordingSupport          : 録音できる
      OnlyHasDefaultPlaybackDevice : 再生は既定の 1 台だけ（DetectDevices の既定がそれを足す）
      OnlyHasDefaultRecordingDevice: 録音は既定の 1 台だけ }
  TPMLAudioBackendCapability = (ProvidesOwnCallbackThread, HasRecordingSupport,
    OnlyHasDefaultPlaybackDevice, OnlyHasDefaultRecordingDevice);
  TPMLAudioBackendCapabilities = set of TPMLAudioBackendCapability;

  TPMLAudioDevice = class;
  TPMLAudioBackend = class;

  { 中核の口（バックエンドが呼ぶ）。PaPiMeLa.Audio の TPMLAudioSystem が実装する。
    どれもどのスレッドから呼んでもよい（SDL と同じ）。 }
  TPMLAudioCore = class abstract(TPMLSystemObject)
  public
    { デバイスを足す（SDL_AddAudioDevice）。ASpec の 0 の欄は既定で埋める。AHandle は
      バックエンドがデバイスを見分ける値（nil でないこと）。追加のイベントは次の Pump で出る。
      終わりかけ（中核の破棄の途中）なら nil。 }
    function  AddDevice(ARecording: Boolean; const AName, AUniqueID: String;
      const ASpec: TPMLAudioSpec; AHandle: Pointer): TPMLAudioDevice; virtual; abstract;
    { デバイスが失われた（SDL_AudioDeviceDisconnected）。デバイスは無音を流す状態になり、
      イベントと後始末はメインスレッドの次の Pump で行う。 }
    procedure DeviceDisconnected(ADevice: TPMLAudioDevice); virtual; abstract;
    // システムの既定が変わった（SDL_DefaultAudioDeviceChanged）。既定として開いたものを移す。
    procedure DefaultDeviceChanged(ANewDefault: TPMLAudioDevice); virtual; abstract;
    // デバイスの形式が変わった（SDL_AudioDeviceFormatChanged）。失敗したら False。
    function  DeviceFormatChanged(ADevice: TPMLAudioDevice; const ASpec: TPMLAudioSpec;
      ASampleFrames: Integer): Boolean; virtual; abstract;
    // 同じ。デバイスのロックを持っているとき（SDL_AudioDeviceFormatChangedAlreadyLocked）。
    function  DeviceFormatChangedAlreadyLocked(ADevice: TPMLAudioDevice; const ASpec: TPMLAudioSpec;
      ASampleFrames: Integer): Boolean; virtual; abstract;
    // AddDevice に渡した AHandle のデバイス（SDL_FindPhysicalAudioDeviceByHandle）。ロックしない。
    function  FindDeviceByHandle(AHandle: Pointer): TPMLAudioDevice; virtual; abstract;
    // Spec か SampleFrames を変えたら呼ぶ（SDL_UpdatedAudioDeviceFormat）。
    procedure UpdatedDeviceFormat(ADevice: TPMLAudioDevice); virtual; abstract;
    // 周波数に合った 1 回分のフレーム数（SDL_GetDefaultSampleFramesFromFreq。ヒントも見る）。
    function  DefaultSampleFramesFromFreq(AFreq: Integer): Integer; virtual; abstract;
    // デバイススレッドの名前（SDL_GetAudioThreadName）。
    function  ThreadName(ADevice: TPMLAudioDevice): String; virtual; abstract;
    procedure RefDevice(ADevice: TPMLAudioDevice); virtual; abstract;
    procedure UnrefDevice(ADevice: TPMLAudioDevice); virtual; abstract;
    { デバイススレッドの中身（SDL_PlaybackAudioThreadSetup / Iterate / Shutdown と Recording の 3 つ）。
      ProvidesOwnCallbackThread のバックエンドが自分のスレッドから呼ぶ。Iterate が False なら終わり。 }
    procedure PlaybackThreadSetup(ADevice: TPMLAudioDevice); virtual; abstract;
    function  PlaybackThreadIterate(ADevice: TPMLAudioDevice): Boolean; virtual; abstract;
    procedure PlaybackThreadShutdown(ADevice: TPMLAudioDevice); virtual; abstract;
    procedure RecordingThreadSetup(ADevice: TPMLAudioDevice); virtual; abstract;
    function  RecordingThreadIterate(ADevice: TPMLAudioDevice): Boolean; virtual; abstract;
    procedure RecordingThreadShutdown(ADevice: TPMLAudioDevice); virtual; abstract;
    // ヒントを読む（バックエンドの設定。PAPIMELA_AUDIO_DUMMY_TIMESCALE など）。
    function  Hint(const AName: String): String; virtual; abstract;
    // 呼んだスレッドの優先度を上げる（スレッドの既定の ThreadInit が使う）。
    procedure SetCurrentThreadPriority(APriority: TPMLThreadPriority); virtual; abstract;
  end;

  { 物理デバイス（SDL_AudioDevice）。中核が作って持つ。アプリには見せない（ID で指す）。

    「バックエンドも触る」欄と「中核だけが触る」欄がある。バックエンドは OpenDevice の中か、
    デバイスのロックを持って（DeviceFormatChanged などを通して）書き換える。 }
  TPMLAudioDevice = class
  public
    // ---- バックエンドも触る
    Name        : String;
    UniqueID    : String;              // 実行をまたいで同じデバイスを指す文字列。分からなければ空
    InstanceID  : TPMLAudioDeviceID;
    Handle      : Pointer;             // バックエンドが開いていないデバイスを見分ける値
    Recording   : Boolean;
    Spec        : TPMLAudioSpec;       // 今の形式
    DefaultSpec : TPMLAudioSpec;       // 足したときの形式。閉じると戻る
    SampleFrames: Integer;             // 1 回分のフレーム数
    BufferSize  : Integer;             // 1 回分のバイト数（SampleFrames x 1 フレーム）
    SilenceValue: Byte;
    ChannelMap  : TPMLChannelMap;      // デバイスのチャンネルの並び。空なら SDL の既定の並び
    Hidden      : TObject;             // バックエンドの中身（SDL の hidden）。CloseDevice で解放する
    Core        : TPMLAudioCore;       // 作った中核（借用）
    // ---- 中核だけが触る
    Lock          : TPMLMutex;         // 再入できる
    CloseCond     : TPMLCondition;
    RefCount      : TPMLAtomicInt;
    ShutdownFlag  : TPMLAtomicInt;     // デバイススレッドに終わりを知らせる
    Zombie        : TPMLAtomicInt;     // 0 = 生きている、1 = 失われた（知らせはまだ）、2 = 知らせ済み
    ZombieFunctions: Boolean;          // 失われた後の動き（無音を流す）に切り替えた
    SimpleCopy    : Boolean;
    WorkBuffer    : PByte;
    MixBuffer     : PByte;
    PostmixBuffer : PSingle;
    WorkBufferSize: Integer;
    Thread        : TPMLThread;
    CurrentlyOpened: Boolean;
    LogicalDevices: TObject;           // 最初の論理デバイス（PaPiMeLa.Audio の型。連結リスト）
    constructor Create;
    destructor Destroy; override;
  end;

  { バックエンドの抽象（SDL_AudioDriverImpl）。どれも既定を持つ（SDL の CompleteAudioEntryPoints）。
    OpenDevice の既定は失敗する。 }
  TPMLAudioBackend = class abstract(TPMLSystemObject)
  protected
    FCore        : TPMLAudioCore;
    FCapabilities: TPMLAudioBackendCapabilities;
  public
    constructor Create(ACore: TPMLAudioCore); virtual;
    function  Name: String; virtual; abstract;
    { 最初の列挙（DetectDevices）。見つけたデバイスを FCore.AddDevice で足し、既定の 2 台を返す
      （分からなければ nil。中核が最初に足したものを既定にする）。既定は、OnlyHasDefault* の
      バックエンド向けに、既定のデバイスを 1 台ずつ足す（SDL_AudioDetectDevices_Default）。 }
    procedure DetectDevices(out ADefaultPlayback, ADefaultRecording: TPMLAudioDevice); virtual;
    // デバイスを開く（OpenDevice）。Spec と SampleFrames を変えてよい。失敗したら False。
    function  OpenDevice(ADevice: TPMLAudioDevice): Boolean; virtual;
    // デバイススレッドの始めと終わり（ThreadInit / ThreadDeinit）。既定の Init は優先度を上げる。
    procedure ThreadInit(ADevice: TPMLAudioDevice); virtual;
    procedure ThreadDeinit(ADevice: TPMLAudioDevice); virtual;
    // 次の 1 回分を書けるまで待つ（WaitDevice）。失敗したら False（デバイスは失われる）。
    function  WaitDevice(ADevice: TPMLAudioDevice): Boolean; virtual;
    // 1 回分を鳴らす（PlayDevice）。ABuffer は GetDeviceBuf が返したもの。
    function  PlayDevice(ADevice: TPMLAudioDevice; ABuffer: PByte; ALen: Integer): Boolean; virtual;
    // 次の 1 回分を書く置き場（GetDeviceBuf）。ASize は BufferSize で来る。減らしてよい。
    function  GetDeviceBuf(ADevice: TPMLAudioDevice; var ASize: Integer): PByte; virtual;
    function  WaitRecordingDevice(ADevice: TPMLAudioDevice): Boolean; virtual;
    // 録音した分を読む（RecordDevice）。読んだバイト数。失敗したら -1。
    function  RecordDevice(ADevice: TPMLAudioDevice; ABuffer: Pointer; ALen: Integer): Integer; virtual;
    procedure FlushRecording(ADevice: TPMLAudioDevice); virtual;
    procedure CloseDevice(ADevice: TPMLAudioDevice); virtual;
    // 中核がデバイスを捨てる（FreeDeviceHandle）。Handle の後始末。
    procedure FreeDeviceHandle(ADevice: TPMLAudioDevice); virtual;
    // 終わりの始め（DeinitializeStart。hotplug を止めるのによい）と終わり（Deinitialize）。
    procedure DeinitializeStart; virtual;
    procedure Deinitialize; virtual;
    property  Capabilities: TPMLAudioBackendCapabilities read FCapabilities;
    property  Core: TPMLAudioCore read FCore;
  end;

  // 作るだけの関数。作れなければ（ライブラリが無いなど）例外を投げる。
  TPMLAudioBackendFactory = function(ACore: TPMLAudioCore): TPMLAudioBackend;

{ ---- 登録 ----

  具象バックエンドは、自分のユニットの initialization で自分を登録する（ビデオと同じ）。
  ADemandOnly のもの（SDL の demand_only。Dummy など）は、名前で求められたときだけ使う。
  名前は大文字小文字を区別せずに比べる。同じ名前を 2 度登録すると EPMLArgument。
  試す順は優先度の大きい順、同じなら登録した順。 }
procedure PMLRegisterAudioBackend(const AName: String; APriority: Integer;
  AFactory: TPMLAudioBackendFactory; ADemandOnly: Boolean = False);
// 登録済みの名前を試す順に返す。
function  PMLAudioBackendNames: TStringArray;
// 名前の工場。登録されていなければ nil。
function  PMLFindAudioBackend(const AName: String): TPMLAudioBackendFactory;
// 名前が「求められたときだけ」のものか。
function  PMLAudioBackendIsDemandOnly(const AName: String): Boolean;

implementation

{ TPMLAudioDevice }

constructor TPMLAudioDevice.Create;
begin
  inherited Create;
  Lock := TPMLMutex.Create;
  CloseCond := TPMLCondition.Create;
  RefCount := Default(TPMLAtomicInt);
  ShutdownFlag := Default(TPMLAtomicInt);
  Zombie := Default(TPMLAtomicInt);
end;

destructor TPMLAudioDevice.Destroy;
begin
  if WorkBuffer <> nil then
    FreeMem(WorkBuffer);
  if MixBuffer <> nil then
    FreeMem(MixBuffer);
  if PostmixBuffer <> nil then
    FreeMem(PostmixBuffer);
  CloseCond.Free;
  Lock.Free;
  inherited Destroy;
end;

{ TPMLAudioBackend — 既定（SDL_AudioXxx_Default） }

constructor TPMLAudioBackend.Create(ACore: TPMLAudioCore);
begin
  inherited Create(ACore.ContextRef, ACore);
  FCore := ACore;
end;

{ SDL_AudioDetectDevices_Default。OnlyHasDefault* のバックエンドだけが使う。 }
procedure TPMLAudioBackend.DetectDevices(out ADefaultPlayback, ADefaultRecording: TPMLAudioDevice);
begin
  ADefaultPlayback := FCore.AddDevice(False, PML_DEFAULT_PLAYBACK_DEVNAME, '',
    TPMLAudioSpec.Make(0, 0, 0), Pointer(PtrUInt(1)));
  ADefaultRecording := nil;
  if TPMLAudioBackendCapability.HasRecordingSupport in FCapabilities then
    ADefaultRecording := FCore.AddDevice(True, PML_DEFAULT_RECORDING_DEVNAME, '',
      TPMLAudioSpec.Make(0, 0, 0), Pointer(PtrUInt(2)));
end;

function TPMLAudioBackend.OpenDevice(ADevice: TPMLAudioDevice): Boolean;
begin
  Result := False;
end;

{ SDL_AudioThreadInit_Default: 録音は High、再生は TimeCritical。 }
procedure TPMLAudioBackend.ThreadInit(ADevice: TPMLAudioDevice);
begin
  if ADevice.Recording then
    FCore.SetCurrentThreadPriority(TPMLThreadPriority.High)
  else
    FCore.SetCurrentThreadPriority(TPMLThreadPriority.TimeCritical);
end;

procedure TPMLAudioBackend.ThreadDeinit(ADevice: TPMLAudioDevice);
begin
end;

function TPMLAudioBackend.WaitDevice(ADevice: TPMLAudioDevice): Boolean;
begin
  Result := True;
end;

function TPMLAudioBackend.PlayDevice(ADevice: TPMLAudioDevice; ABuffer: PByte; ALen: Integer): Boolean;
begin
  Result := True;
end;

function TPMLAudioBackend.GetDeviceBuf(ADevice: TPMLAudioDevice; var ASize: Integer): PByte;
begin
  ASize := 0;
  Result := nil;
end;

function TPMLAudioBackend.WaitRecordingDevice(ADevice: TPMLAudioDevice): Boolean;
begin
  Result := True;
end;

function TPMLAudioBackend.RecordDevice(ADevice: TPMLAudioDevice; ABuffer: Pointer; ALen: Integer): Integer;
begin
  Result := -1;
end;

procedure TPMLAudioBackend.FlushRecording(ADevice: TPMLAudioDevice);
begin
end;

procedure TPMLAudioBackend.CloseDevice(ADevice: TPMLAudioDevice);
begin
end;

procedure TPMLAudioBackend.FreeDeviceHandle(ADevice: TPMLAudioDevice);
begin
end;

procedure TPMLAudioBackend.DeinitializeStart;
begin
end;

procedure TPMLAudioBackend.Deinitialize;
begin
end;

{ ---- 登録 ---- }

type
  TAudioRegistration = record
    Name      : String;
    Priority  : Integer;
    Factory   : TPMLAudioBackendFactory;
    DemandOnly: Boolean;
  end;

var
  // 試す順（優先度の大きい順、同じなら登録順）に並べて持つ。
  AudioRegistry: array of TAudioRegistration;

function FindAudioIndex(const AName: String): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(AudioRegistry) do
    if SameText(AudioRegistry[I].Name, AName) then
      Exit(I);
end;

procedure PMLRegisterAudioBackend(const AName: String; APriority: Integer;
  AFactory: TPMLAudioBackendFactory; ADemandOnly: Boolean);
var
  At, I: Integer;
begin
  if AName = '' then
    raise EPMLArgument.Create('audio backend name is empty');
  if not Assigned(AFactory) then
    raise EPMLArgument.Create('audio backend factory is nil');
  if FindAudioIndex(AName) >= 0 then
    raise EPMLArgument.CreateFmt('audio backend "%s" is already registered', [AName]);
  // 自分より優先度の小さい最初の位置へ入れる（同じ優先度は後ろへ回る）。
  At := Length(AudioRegistry);
  for I := 0 to High(AudioRegistry) do
    if AudioRegistry[I].Priority < APriority then
    begin
      At := I;
      Break;
    end;
  SetLength(AudioRegistry, Length(AudioRegistry) + 1);
  for I := High(AudioRegistry) downto At + 1 do
    AudioRegistry[I] := AudioRegistry[I - 1];
  AudioRegistry[At].Name := AName;
  AudioRegistry[At].Priority := APriority;
  AudioRegistry[At].Factory := AFactory;
  AudioRegistry[At].DemandOnly := ADemandOnly;
end;

function PMLAudioBackendNames: TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AudioRegistry));
  for I := 0 to High(AudioRegistry) do
    Result[I] := AudioRegistry[I].Name;
end;

function PMLFindAudioBackend(const AName: String): TPMLAudioBackendFactory;
var
  I: Integer;
begin
  I := FindAudioIndex(AName);
  if I >= 0 then
    Result := AudioRegistry[I].Factory
  else
    Result := nil;
end;

function PMLAudioBackendIsDemandOnly(const AName: String): Boolean;
var
  I: Integer;
begin
  I := FindAudioIndex(AName);
  Result := (I >= 0) and AudioRegistry[I].DemandOnly;
end;

end.
