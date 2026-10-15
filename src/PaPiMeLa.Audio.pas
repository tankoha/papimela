{
  PaPiMeLa.Audio — オーディオのサブシステム（デバイス・デバイスのスレッド・ストリームの結び付け）

  Origin : ported from SDL (src/audio/SDL_audio.c, src/audio/SDL_mixer.c)
           Scope: SDL_audio.c の全体（バックエンドの選び方、物理デバイスの参照の数え方と
           追加・切断・既定の変更・形式の変更、論理デバイスの開け閉め、デバイスのスレッドの
           再生と録音、ストリームの結び付けと外し、簡易パス、待っているイベント）と、
           SDL_mixer.c の SDL_MixAudio の F32 の分（デバイスの中で混ぜるところ）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.5、§11 #51

  WHAT:
    TPMLAudioSystem（Context が作る）と、アプリが開く TPMLLogicalAudioDevice。物理デバイスは
    ID（TPMLAudioDeviceID）で指す。

  WHY:
    物理デバイスはバックエンドの hotplug で別のスレッドから消える。オブジェクトを渡すと
    アプリの手に宙に浮いた参照が残るので、SDL と同じく ID で指す（持ち主の判断、2026-10-14）。
    開いた論理デバイスはアプリが Free するまで生きる（失われても無音を流し続ける）ので、
    オブジェクトにする。

  RESOLVED:
    - ロックの順番は SDL と同じ: 物理デバイスのロック → 系の読み書きロック、
      物理デバイスのロック → ストリームのロック。系の読み書きロックを持ったまま
      デバイスのロックを取らない
    - 切断の後始末はメインスレッドで行う（SDL_RunOnMainThread の代わりに、メインスレッドから
      呼ばれればその場で、そうでなければ次の Pump で）
    - アプリの呼び出し（OnGet・OnPut・後置き処理）がデバイスのスレッドで例外を投げたら、
      ログに残し、その論理デバイスを一時停止する（DESIGN §5.5）。その回はデータが無いものとする

  PORT-NOTE:
    - SDL の bool の失敗は例外にした。ID の誤りと引数の誤りは EPMLArgument、開けないなどは
      EPMLAudioError
    - デバイスの ID の並び（PlaybackDevices など）は ID の小さい順（SDL はハッシュ表の順）
    - OpenDevice は形式を確かめる（0 は既定の意味。SDL は確かめない）
    - BindStreams に同じストリームが 2 度あれば EPMLArgument（SDL は連なりが輪になって
      戻らなくなる。D-68）
    - 最初に開くとき、求めた形式でデバイスを開く（SDL の main は求めた形式をデバイスに入れず、
      いつも既定の形式で開く。D-66。3.4.2 は入れていた）
    - 並びの入れ替え（デバイスの並びとストリームの並びが違うとき）は、置き場の本当の形式で行う
      （SDL は浮動小数の置き場をデバイスの形式として扱う。D-67）。録音では、デバイスの並びを
      外すだけにする（SDL はストリームの並びを当て、ストリームも当てるので 2 度になる。SDL の
      説明の「変えた後にデバイスから入るデータは新しい並びになる」に合わせた。D-67）
    - 録音で、後置き処理か音量のある論理デバイスの後に続く論理デバイスにも、読んだままの
      バイト数を渡す（SDL は書き換えたバイト数を次へ持ち越す。D-69）
    - 録音のデバイスは、後置き処理の置き場と混ぜる置き場をいつも持つ（SDL は後置き処理を
      置いたときと F32 でないときにしか作らず、音量だけを変えたときと、F32 のデバイスで並びを
      入れ替えるときに無い置き場へ書く。D-70、D-71）
    - 簡易パスのストリームを UnbindStreams に渡しても、結び付けは何も変えない（SDL は
      結び付けの印だけを消し、壊してもデバイスが閉じずに壊れたストリームを読む。D-72）
    - SDL_QuitAudio は残っているストリームを壊すが、papimela はストリームを壊さない
      （アプリのもの。結び付けが外れるだけ）
    - デバイスのプロパティ（SDL_GetAudioDeviceProperties）は DeviceUniqueID だけにした
    - 混ぜるのは SDL_MixAudio の F32LE（音量 1）と同じ計算。SDL_MixAudio の他の形式は未移植

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Audio;

{$I papimela.inc}

interface

uses
  Classes, SysUtils, Math, StrUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Atomic,
  PaPiMeLa.Threading,
  PaPiMeLa.Properties,
  PaPiMeLa.Log,
  PaPiMeLa.Time,
  PaPiMeLa.Events,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Stream,
  PaPiMeLa.Audio.Wave,
  PaPiMeLa.Audio.Backend;

type
  TPMLAudioSystem = class;
  TPMLLogicalAudioDevice = class;

  { 混ぜた後の呼び出し（SDL_AudioPostmixCallback）。デバイスのスレッドから、デバイスの
    ロックを持ったまま来る。ABuffer は F32 で ASpec のチャンネルを交互に並べたもの、
    ALen はバイト数。書き換えてよい。再生では混ぜた後、録音では読んだ直後に来る。 }
  TPMLAudioPostmixCallback = procedure(ADevice: TPMLLogicalAudioDevice; const ASpec: TPMLAudioSpec;
    ABuffer: PSingle; ALen: Integer) of object;

  { 開いた論理デバイス（SDL_LogicalAudioDevice）。TPMLAudioSystem.OpenDevice が作り、アプリが
    Free する（SDL_CloseAudioDevice）。系が先に壊れたら系が Free する。

    物理デバイスが失われても生きている（無音を流し続ける。既定として開いたものは新しい既定に
    移る）。失われたことは AudioDeviceRemoved（Which = ID）で分かる。 }
  TPMLLogicalAudioDevice = class sealed(TPMLOwnedObject)
  strict private
    function  GetGain: Single;
    procedure SetGain(AValue: Single);
    function  GetRecording: Boolean;
  private
    // SDL_LogicalAudioDevice の中身。FPhysical は系の書きロックと物理デバイスのロックの
    // 両方を持って書き、どちらかを持って読む（SDL の atomic pointer）。
    FSystem         : TPMLAudioSystem;     // nil = 系が先に壊れた
    FID             : TPMLAudioDeviceID;
    FPhysical       : TPMLAudioDevice;
    FPaused         : TPMLAtomicInt;
    FGain           : Single;
    FPostmix        : TPMLAudioPostmixCallback;
    FOpenedAsDefault: Boolean;
    FSimplified     : Boolean;
    FBoundStreams   : TPMLAudioStream;
    FNext, FPrev    : TPMLLogicalAudioDevice;
  public
    // SDL_CloseAudioDevice。結び付いたストリームは外れる（壊れない）。
    destructor Destroy; override;
    // SDL_PauseAudioDevice / ResumeAudioDevice / AudioDevicePaused。
    procedure Pause;
    procedure Resume;
    function  Paused: Boolean;
    { 後置き処理（SDL_SetAudioPostmixCallback）。nil で外す。 }
    procedure SetPostmixCallback(ACallback: TPMLAudioPostmixCallback);
    { ストリームを結び付ける（SDL_BindAudioStream(s)）。全部か、何もしないか。
      nil・もう結び付いている・OpenDeviceStream で作った・同じものが 2 度、のどれかなら
      EPMLArgument。OpenDeviceStream で開いたデバイスには結び付けられない（EPMLArgument）。 }
    procedure BindStream(AStream: TPMLAudioStream);
    procedure BindStreams(const AStreams: array of TPMLAudioStream);
    // 物理デバイスの今の形式と 1 回分のフレーム数（SDL_GetAudioDeviceFormat）。
    function  Format: TPMLAudioSpec;
    function  SampleFrames: Integer;
    // 物理デバイスの名前（SDL_GetAudioDeviceName）。
    function  Name: String;
    property  ID: TPMLAudioDeviceID read FID;
    property  Recording: Boolean read GetRecording;
    // 音量（SDL_Get/SetAudioDeviceGain）。負なら EPMLArgument。
    property  Gain: Single read GetGain write SetGain;
    property  AudioSystem: TPMLAudioSystem read FSystem;
  end;

  { オーディオのサブシステム（SDL_InitAudio から SDL_QuitAudio まで）。Context が作って壊す。

    ID を取るメソッドは、物理デバイスの ID、論理デバイスの ID、既定の印
    （PML_AUDIO_DEVICE_DEFAULT_PLAYBACK / RECORDING）のどれでもよい（SDL と同じ）。
    知らない ID なら EPMLArgument。 }
  TPMLAudioSystem = class sealed(TPMLAudioCore, IPMLEventPumpSource)
  private
  type
    TPendingEvent = record
      Kind: TPMLEventKind;
      ID  : TPMLAudioDeviceID;
    end;
    TPendingEvents = array of TPendingEvent;
  var
    FQueue          : TPMLEventQueue;
    FBackend        : TPMLAudioBackend;
    FBackendName    : String;
    // subsystem_rwlock。以下の 6 つを守る。
    FLock           : TPMLRWLock;
    FDevices        : array of TPMLAudioDevice;          // device_hash_physical（ID の小さい順）
    FLogical        : array of TPMLLogicalAudioDevice;   // device_hash_logical
    FDefaultPlaybackID : TPMLAudioDeviceID;
    FDefaultRecordingID: TPMLAudioDeviceID;
    FPending        : TPendingEvents;                    // pending_events
    FPendingDisconnects: array of TPMLAudioDeviceID;     // メインスレッドで後始末する切断
    FShuttingDown   : TPMLAtomicInt;

    procedure SelectBackend(const APreferred: String);
    function  TryBackend(const AName: String): Boolean;
    procedure LogDebug(const AMessage: String);
    procedure ReportCallbackException(E: Exception; ALogical: TPMLLogicalAudioDevice;
      const AWhere: String);
    procedure QueueEvents(const AEvents: TPendingEvents);
    procedure FlushPendingEvents;
    procedure ProcessPendingDisconnects;
    procedure DisconnectedOnMainThread(AID: TPMLAudioDeviceID);
    function  FindDeviceLocked(AID: TPMLAudioDeviceID): TPMLAudioDevice;
    function  FindLogicalLocked(AID: TPMLAudioDeviceID): TPMLLogicalAudioDevice;
    function  FirstAddedDevice(ARecording: Boolean): TPMLAudioDevice;
    procedure RemoveLogicalFromTable(ALogical: TPMLLogicalAudioDevice);
    function  ObtainLogicalByID(AID: TPMLAudioDeviceID; out ADevice: TPMLAudioDevice): TPMLLogicalAudioDevice;
    function  ObtainPhysicalByID(AID: TPMLAudioDeviceID): TPMLAudioDevice;
    function  ObtainPhysicalDefaultAllowed(AID: TPMLAudioDeviceID): TPMLAudioDevice;
    procedure ObtainDeviceObj(ADevice: TPMLAudioDevice);
    procedure ReleaseDevice(ADevice: TPMLAudioDevice);
    procedure DestroyPhysical(ADevice: TPMLAudioDevice);
    procedure SerializeClose(ADevice: TPMLAudioDevice);
    procedure ClosePhysical(ADevice: TPMLAudioDevice);
    function  OpenPhysical(ADevice: TPMLAudioDevice; AHasSpec: Boolean; const ASpec: TPMLAudioSpec;
      out AError: String): Boolean;
    procedure PrepareAudioFormat(ARecording: Boolean; var ASpec: TPMLAudioSpec);
    function  OpenLogical(AID: TPMLAudioDeviceID; AHasSpec: Boolean;
      const ASpec: TPMLAudioSpec): TPMLLogicalAudioDevice;
    function  OpenStream(AID: TPMLAudioDeviceID; AHasSpec: Boolean; const ASpec: TPMLAudioSpec;
      ACallback: TPMLAudioStreamCallback): TPMLAudioStream;
    function  DeviceList(ARecording: Boolean): TPMLAudioDeviceIDs;
    // デバイスのスレッドの 1 回分の部品（SDL の device->WaitDevice などと、そのゾンビ版）。
    function  DevWait(ADevice: TPMLAudioDevice): Boolean;
    function  DevWaitRecording(ADevice: TPMLAudioDevice): Boolean;
    function  DevGetBuf(ADevice: TPMLAudioDevice; var ASize: Integer): PByte;
    function  DevPlay(ADevice: TPMLAudioDevice; ABuffer: PByte; ALen: Integer): Boolean;
    function  DevRecord(ADevice: TPMLAudioDevice; ABuffer: Pointer; ALen: Integer): Integer;
    procedure DevFlush(ADevice: TPMLAudioDevice);
    procedure ZombieWait(ADevice: TPMLAudioDevice);
    function  SafeGetData(ALogical: TPMLLogicalAudioDevice; AStream: TPMLAudioStream;
      ABuffer: Pointer; ALen: Integer): Integer;
    procedure SafePutData(ALogical: TPMLLogicalAudioDevice; AStream: TPMLAudioStream;
      ABuffer: Pointer; ALen: Integer);
    procedure SafePostmix(ALogical: TPMLLogicalAudioDevice; const ASpec: TPMLAudioSpec;
      ABuffer: PSingle; ALen: Integer);
    // TPMLLogicalAudioDevice とストリームの破棄から呼ぶ。
    function  ObtainLogical(ALogical: TPMLLogicalAudioDevice): TPMLAudioDevice;
    procedure CloseLogical(ALogical: TPMLLogicalAudioDevice);
    procedure DestroyLogical(ALogical: TPMLLogicalAudioDevice);
    procedure SetPostmixLocked(ALogical: TPMLLogicalAudioDevice; ADevice: TPMLAudioDevice;
      ACallback: TPMLAudioPostmixCallback);
  public
    { SDL_InitAudio。APreferred（ヒント PML_HINT_AUDIO_DRIVER）が空でなければ、カンマで区切った
      名前を順に試す。空なら、登録された順に「求められたときだけ」のもの（dummy）を除いて試す。
      どれも作れなければ EPMLAudioError（名前を指定してどれも登録されていなければ
      EPMLUnsupported）。 }
    constructor Create(AContextRef: TObject; AOwner: TPMLObject; AQueue: TPMLEventQueue;
      const APreferred: String = '');
    // SDL_QuitAudio。開いている論理デバイスを全部 Free する。
    destructor Destroy; override;

    // 物理デバイスの ID（SDL_GetAudioPlaybackDevices / RecordingDevices）。失われたものは除く。
    function  PlaybackDevices: TPMLAudioDeviceIDs;
    function  RecordingDevices: TPMLAudioDeviceIDs;
    // SDL_GetAudioDeviceName。論理デバイスなら、その物理デバイスの名前。
    function  DeviceName(AID: TPMLAudioDeviceID): String;
    // SDL_GetAudioDeviceFormat。
    function  DeviceFormat(AID: TPMLAudioDeviceID): TPMLAudioSpec; overload;
    function  DeviceFormat(AID: TPMLAudioDeviceID; out ASampleFrames: Integer): TPMLAudioSpec; overload;
    // SDL_GetAudioDeviceChannelMap。既定の並びなら空。
    function  DeviceChannelMap(AID: TPMLAudioDeviceID): TPMLChannelMap;
    // SDL_PROP_AUDIO_DEVICE_UNIQUE_ID_STRING。バックエンドが分からなければ空。
    function  DeviceUniqueID(AID: TPMLAudioDeviceID): String;
    // SDL_IsAudioDevicePhysical / SDL_IsAudioDevicePlayback（ID のビットを見るだけ）。
    class function IsPhysicalDevice(AID: TPMLAudioDeviceID): Boolean; static;
    class function IsPlaybackDevice(AID: TPMLAudioDeviceID): Boolean; static;

    { 論理デバイスを開く（SDL_OpenAudioDevice）。ASpec の 0 の欄は既定（ヒントか CD の音質）。
      物理デバイスがもっと低い形式で開いていれば、高い方で開き直す。論理デバイスの ID を渡すと、
      同じ物理デバイスにもう 1 つ開く。失われた物理デバイスを名指しすると EPMLAudioError。 }
    function  OpenDevice(AID: TPMLAudioDeviceID): TPMLLogicalAudioDevice; overload;
    function  OpenDevice(AID: TPMLAudioDeviceID; const ASpec: TPMLAudioSpec): TPMLLogicalAudioDevice; overload;
    { 簡易パス（SDL_OpenAudioDeviceStream）。論理デバイスを開き、ストリームを 1 本結び付けて
      返す。デバイスは一時停止で始まる（ResumeStreamDevice で鳴る）。ストリームの、デバイスで
      ない側の形式は ASpec（無ければデバイスの形式）。ACallback は再生なら OnGet、録音なら OnPut。
      ストリームを Free するとデバイスも閉じる。 }
    function  OpenDeviceStream(AID: TPMLAudioDeviceID;
      ACallback: TPMLAudioStreamCallback = nil): TPMLAudioStream; overload;
    function  OpenDeviceStream(AID: TPMLAudioDeviceID; const ASpec: TPMLAudioSpec;
      ACallback: TPMLAudioStreamCallback = nil): TPMLAudioStream; overload;

    { WAVE ファイルを読む（SDL_LoadWAV_IO / SDL_LoadWAV）。ヒント PML_HINT_WAVE_* の値で
      読み方が変わる（PaPiMeLa.Audio.Wave の TPMLWaveOptions）。標本のバイト列を返し、形式を
      ASpec に置く。読めなければ EPMLAudioError。 }
    function  LoadWAV(AStream: TStream; out ASpec: TPMLAudioSpec): TBytes;
    function  LoadWAVFile(const APath: String; out ASpec: TPMLAudioSpec): TBytes;

    { ストリームを外す（SDL_UnbindAudioStream(s)）。結び付いていない・nil は何もしない。
      OpenDeviceStream で作ったものは外れない（何もしない）。 }
    procedure UnbindStream(AStream: TPMLAudioStream);
    procedure UnbindStreams(const AStreams: array of TPMLAudioStream);
    // 結び付いた論理デバイス（SDL_GetAudioStreamDevice）。結び付いていなければ nil。
    function  StreamDevice(AStream: TPMLAudioStream): TPMLLogicalAudioDevice;
    { 結び付いた論理デバイスを止める・動かす（SDL_PauseAudioStreamDevice など）。
      結び付いていなければ EPMLArgument。Paused は結び付いていなければ False。 }
    procedure PauseStreamDevice(AStream: TPMLAudioStream);
    procedure ResumeStreamDevice(AStream: TPMLAudioStream);
    function  StreamDevicePaused(AStream: TPMLAudioStream): Boolean;

    // IPMLEventPumpSource（SDL_UpdateAudio と、メインスレッドでの切断の後始末）。
    function  PumpSourceName: String;
    procedure PumpEvents(ATimeoutMs: Integer);

    // TPMLAudioCore（バックエンドが呼ぶ）。
    function  AddDevice(ARecording: Boolean; const AName, AUniqueID: String;
      const ASpec: TPMLAudioSpec; AHandle: Pointer): TPMLAudioDevice; override;
    procedure DeviceDisconnected(ADevice: TPMLAudioDevice); override;
    procedure DefaultDeviceChanged(ANewDefault: TPMLAudioDevice); override;
    function  DeviceFormatChanged(ADevice: TPMLAudioDevice; const ASpec: TPMLAudioSpec;
      ASampleFrames: Integer): Boolean; override;
    function  DeviceFormatChangedAlreadyLocked(ADevice: TPMLAudioDevice; const ASpec: TPMLAudioSpec;
      ASampleFrames: Integer): Boolean; override;
    function  FindDeviceByHandle(AHandle: Pointer): TPMLAudioDevice; override;
    procedure UpdatedDeviceFormat(ADevice: TPMLAudioDevice); override;
    function  DefaultSampleFramesFromFreq(AFreq: Integer): Integer; override;
    function  ThreadName(ADevice: TPMLAudioDevice): String; override;
    procedure RefDevice(ADevice: TPMLAudioDevice); override;
    procedure UnrefDevice(ADevice: TPMLAudioDevice); override;
    procedure PlaybackThreadSetup(ADevice: TPMLAudioDevice); override;
    function  PlaybackThreadIterate(ADevice: TPMLAudioDevice): Boolean; override;
    procedure PlaybackThreadShutdown(ADevice: TPMLAudioDevice); override;
    procedure RecordingThreadSetup(ADevice: TPMLAudioDevice); override;
    function  RecordingThreadIterate(ADevice: TPMLAudioDevice): Boolean; override;
    procedure RecordingThreadShutdown(ADevice: TPMLAudioDevice); override;
    function  Hint(const AName: String): String; override;
    procedure SetCurrentThreadPriority(APriority: TPMLThreadPriority); override;

    property  BackendName: String read FBackendName;
    property  Backend: TPMLAudioBackend read FBackend;
  end;

{ 混ぜる（SDL_MixAudio の F32LE で音量 1）。ADst に ASrc を足し、-1..1 に挟む。ALen はバイト数。 }
procedure PMLMixFloat32Audio(ADst, ASrc: PSingle; ALen: Integer);

implementation

var
  // last_device_instance_id。系を作り直しても戻さない（古い ID を持っているアプリのため）。
  LastInstanceID: TPMLAtomicInt;

const
  IDBitPlayback = 1;   // ビット 0: 再生
  IDBitPhysical = 2;   // ビット 1: 物理

{ AssignAudioDeviceInstanceId。2 から数え始め、下の 2 ビットに印を置く。 }
function AssignInstanceID(ARecording, ALogical: Boolean): TPMLAudioDeviceID;
var
  Flags: LongWord;
begin
  Flags := 0;
  if not ARecording then
    Flags := Flags or IDBitPlayback;
  if not ALogical then
    Flags := Flags or IDBitPhysical;
  Result := TPMLAudioDeviceID((LongWord(LastInstanceID.IncRef + 1) shl 2) or Flags);
end;

function IsRecordingID(AID: TPMLAudioDeviceID): Boolean; inline;
begin
  Result := (AID and IDBitPlayback) = 0;
end;

function IsLogicalID(AID: TPMLAudioDeviceID): Boolean; inline;
begin
  Result := (AID and IDBitPhysical) = 0;
end;

{ デバイスのスレッドでは浮動小数点の例外を止める（C と同じ。音量で溢れても止まらない）。 }
procedure MaskFloatExceptions;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
end;

procedure PMLMixFloat32Audio(ADst, ASrc: PSingle; ALen: Integer);
var
  I: Integer;
  V: Single;
begin
  for I := 0 to (ALen div 4) - 1 do
  begin
    V := ASrc[I] + ADst[I];
    if V > 1.0 then
      V := 1.0
    else if V < -1.0 then
      V := -1.0;
    ADst[I] := V;
  end;
end;

{ 混ぜる置き場が要るか。再生は F32 でないとき（混ぜた F32 を置く）、録音はいつも
  （並びを入れ替える先。D-71）。 }
function NeedsMixBuffer(ADevice: TPMLAudioDevice): Boolean;
begin
  Result := ADevice.Recording or (ADevice.Spec.Format <> PML_AUDIO_F32);
end;

{ ParseAudioFormatString。 }
function ParseAudioFormatString(const AText: String): TPMLAudioFormat;
begin
  case AText of
    'U8': Result := PML_AUDIO_U8;
    'S8': Result := PML_AUDIO_S8;
    'S16LE', 'S16': Result := PML_AUDIO_S16LE;
    'S16BE': Result := PML_AUDIO_S16BE;
    'S32LE', 'S32': Result := PML_AUDIO_S32LE;
    'S32BE': Result := PML_AUDIO_S32BE;
    'F32LE', 'F32': Result := PML_AUDIO_F32LE;
    'F32BE': Result := PML_AUDIO_F32BE;
  else
    Result := PML_AUDIO_UNKNOWN;
  end;
end;

{ ---- 物理デバイスのストリームの形式 ---- }

{ AudioDeviceCanUseSimpleCopy。デバイスのロックを持って呼ぶ。 }
function CanUseSimpleCopy(ADevice: TPMLAudioDevice): Boolean;
var
  L: TPMLLogicalAudioDevice;
begin
  L := TPMLLogicalAudioDevice(ADevice.LogicalDevices);
  Result := (L <> nil) and (L.FNext = nil) and not Assigned(L.FPostmix)
    and (L.FBoundStreams <> nil) and (L.FBoundStreams.Binding.Next = nil);
end;

{ UpdateAudioStreamFormatsPhysical。デバイスのロックを持って呼ぶ。 }
procedure UpdateStreamFormats(ADevice: TPMLAudioDevice);
var
  Spec: TPMLAudioSpec;
  DevFormat: TPMLAudioFormat;
  L: TPMLLogicalAudioDevice;
  S: TPMLAudioStream;
begin
  if ADevice = nil then
    Exit;
  Spec := ADevice.Spec;
  DevFormat := Spec.Format;
  if not ADevice.Recording then
  begin
    ADevice.SimpleCopy := CanUseSimpleCopy(ADevice);
    // 混ぜるのも後置き処理も F32 で行う。
    if not ADevice.SimpleCopy then
      Spec.Format := PML_AUDIO_F32;
  end;
  L := TPMLLogicalAudioDevice(ADevice.LogicalDevices);
  while L <> nil do
  begin
    if ADevice.Recording then
    begin
      if Assigned(L.FPostmix) or (L.FGain <> 1.0) then
        Spec.Format := PML_AUDIO_F32
      else
        Spec.Format := DevFormat;
    end;
    S := L.FBoundStreams;
    while S <> nil do
    begin
      S.SetDeviceSideFormat(Spec, ADevice.ChannelMap);
      S := S.Binding.Next;
    end;
    L := L.FNext;
  end;
end;

{ SDL_UnbindAudioStreams。系に依らない（ストリームの破棄からも呼ぶ）。 }
procedure UnbindStreamsImpl(const AStreams: array of TPMLAudioStream);
var
  I: Integer;
  S: TPMLAudioStream;
  Bound, L: TPMLLogicalAudioDevice;
begin
  if Length(AStreams) = 0 then
    Exit;
  // デバイス → ストリームの順にロックする。ストリームの結び付けは、見てからデバイスを
  // ロックするまでの間に変わりうるので、確かめ直す。
  for I := 0 to High(AStreams) do
  begin
    S := AStreams[I];
    if S = nil then
      Continue;
    while True do
    begin
      S.Lock;
      Bound := TPMLLogicalAudioDevice(S.Binding.Device);
      S.Unlock;
      if Bound <> nil then
        Bound.FPhysical.Lock.Lock;  // 同じデバイスを何度もロックしうる（再入できるロック）
      S.Lock;
      if Bound = TPMLLogicalAudioDevice(S.Binding.Device) then
        Break;
      S.Unlock;
      if Bound <> nil then
        Bound.FPhysical.Lock.Unlock;
    end;
  end;

  // 全部ロックしたので外す。簡易パスのデバイスからは外さない。
  for I := 0 to High(AStreams) do
  begin
    S := AStreams[I];
    if S = nil then
      Continue;
    L := TPMLLogicalAudioDevice(S.Binding.Device);
    if (L <> nil) and not L.FSimplified then
    begin
      if L.FBoundStreams = S then
        L.FBoundStreams := S.Binding.Next;
      if S.Binding.Prev <> nil then
        S.Binding.Prev.Binding.Next := S.Binding.Next;
      if S.Binding.Next <> nil then
        S.Binding.Next.Binding.Prev := S.Binding.Prev;
      S.Binding.Prev := nil;
      S.Binding.Next := nil;
    end;
  end;

  // 仕上げてロックを外す。
  for I := 0 to High(AStreams) do
  begin
    S := AStreams[I];
    if S = nil then
      Continue;
    L := TPMLLogicalAudioDevice(S.Binding.Device);
    // D-72: SDL は簡易パスのストリームでも bound_device を消す（連なりには残る）。壊しても
    // デバイスが閉じず、壊れたストリームを読み続ける。簡易パスなら消さない。
    if (L <> nil) and not L.FSimplified then
      S.Binding.Device := nil;
    S.Unlock;
    if L <> nil then
    begin
      UpdateStreamFormats(L.FPhysical);
      L.FPhysical.Lock.Unlock;
    end;
  end;
end;

{ ストリームの破棄（SDL_DestroyAudioStream の中のデバイスの部分）。 }
procedure AudioStreamDestroying(AStream: TPMLAudioStream);
var
  L: TPMLLogicalAudioDevice;
begin
  if AStream.Binding.Simplified then
  begin
    AStream.Lock;
    L := TPMLLogicalAudioDevice(AStream.Binding.Device);
    AStream.Unlock;
    // デバイスを閉じると結び付けも外れる。
    if L <> nil then
      L.Free;
  end
  else
    UnbindStreamsImpl([AStream]);
end;

{ ---- 論理デバイス ---- }

destructor TPMLLogicalAudioDevice.Destroy;
begin
  if FSystem <> nil then
    FSystem.CloseLogical(Self);
  FSystem := nil;
  inherited Destroy;
end;

function TPMLLogicalAudioDevice.GetRecording: Boolean;
begin
  Result := IsRecordingID(FID);
end;

procedure TPMLLogicalAudioDevice.Pause;
begin
  FPaused.Exchange(1);
end;

procedure TPMLLogicalAudioDevice.Resume;
begin
  FPaused.Exchange(0);
end;

function TPMLLogicalAudioDevice.Paused: Boolean;
begin
  Result := FPaused.Load <> 0;
end;

function TPMLLogicalAudioDevice.GetGain: Single;
var
  Dev: TPMLAudioDevice;
begin
  if FSystem = nil then
    Exit(FGain);
  Dev := FSystem.ObtainLogical(Self);
  try
    Result := FGain;
  finally
    FSystem.ReleaseDevice(Dev);
  end;
end;

procedure TPMLLogicalAudioDevice.SetGain(AValue: Single);
var
  Dev: TPMLAudioDevice;
begin
  // NaN も通さない（SDL の gain < 0.0f は NaN を通すが、混ぜた値が NaN になる）。
  if not (AValue >= 0) then
    raise EPMLArgument.Create('Parameter ''Gain'' is invalid');
  if FSystem = nil then
  begin
    FGain := AValue;
    Exit;
  end;
  Dev := FSystem.ObtainLogical(Self);
  try
    FGain := AValue;
    UpdateStreamFormats(Dev);
  finally
    FSystem.ReleaseDevice(Dev);
  end;
end;

procedure TPMLLogicalAudioDevice.SetPostmixCallback(ACallback: TPMLAudioPostmixCallback);
var
  Dev: TPMLAudioDevice;
begin
  if FSystem = nil then
  begin
    FPostmix := ACallback;
    Exit;
  end;
  Dev := FSystem.ObtainLogical(Self);
  try
    FSystem.SetPostmixLocked(Self, Dev, ACallback);
  finally
    FSystem.ReleaseDevice(Dev);
  end;
end;

procedure TPMLLogicalAudioDevice.BindStream(AStream: TPMLAudioStream);
begin
  BindStreams([AStream]);
end;

{ SDL_BindAudioStreams。 }
procedure TPMLLogicalAudioDevice.BindStreams(const AStreams: array of TPMLAudioStream);
var
  Dev: TPMLAudioDevice;
  I, J, Locked: Integer;
  S: TPMLAudioStream;
  Err: String;
begin
  if Length(AStreams) = 0 then
    Exit;
  if FSystem = nil then
    raise EPMLAudioError.Create('Audio subsystem is not initialized');
  Dev := FSystem.ObtainLogical(Self);
  try
    if FSimplified then
      raise EPMLArgument.Create('Cannot change stream bindings on device opened with OpenDeviceStream');

    // 全部を先にロックし、どこにも結び付いていないことを確かめてから、まとめて足す。
    Err := '';
    Locked := 0;
    for I := 0 to High(AStreams) do
    begin
      S := AStreams[I];
      if S = nil then
        Err := SysUtils.Format('Stream #%d is nil', [I])
      else
      begin
        for J := 0 to I - 1 do
          if AStreams[J] = S then
            Err := SysUtils.Format('Stream #%d is given twice', [I]);
        S.Lock;
        Inc(Locked);
        if Err <> '' then
          // 上で見つけた誤りを優先する
        else if S.Binding.Device <> nil then
          Err := SysUtils.Format('Stream #%d is already bound to a device', [I])
        else if S.Binding.Simplified then
          Err := 'Cannot change binding on a stream created with OpenDeviceStream';
      end;
      if Err <> '' then
        Break;
    end;
    if Err <> '' then
    begin
      for I := 0 to Locked - 1 do
        AStreams[I].Unlock;
      raise EPMLArgument.Create(Err);
    end;

    for I := 0 to High(AStreams) do
    begin
      S := AStreams[I];
      // ストリームは両方の形式を必ず持つので、SDL の「形式が未設定なら合わせる」は要らない。
      S.Binding.Device := Self;
      S.Binding.Recording := Dev.Recording;
      S.Binding.Prev := nil;
      S.Binding.Next := FBoundStreams;
      if FBoundStreams <> nil then
        FBoundStreams.Binding.Prev := S;
      FBoundStreams := S;
      S.Unlock;
    end;
    UpdateStreamFormats(Dev);
  finally
    FSystem.ReleaseDevice(Dev);
  end;
end;

function TPMLLogicalAudioDevice.Format: TPMLAudioSpec;
begin
  if FSystem = nil then
    raise EPMLAudioError.Create('Audio subsystem is not initialized');
  Result := FSystem.DeviceFormat(FID);
end;

function TPMLLogicalAudioDevice.SampleFrames: Integer;
begin
  if FSystem = nil then
    raise EPMLAudioError.Create('Audio subsystem is not initialized');
  FSystem.DeviceFormat(FID, Result);
end;

function TPMLLogicalAudioDevice.Name: String;
begin
  if FSystem = nil then
    raise EPMLAudioError.Create('Audio subsystem is not initialized');
  Result := FSystem.DeviceName(FID);
end;

{ ---- スレッドの入り口 ---- }

{ PlaybackAudioThread。 }
function PlaybackThreadFunc(AData: Pointer): Integer;
var
  Dev: TPMLAudioDevice;
  Sys: TPMLAudioSystem;
begin
  MaskFloatExceptions;
  Dev := TPMLAudioDevice(AData);
  Sys := TPMLAudioSystem(Dev.Core);
  Sys.PlaybackThreadSetup(Dev);
  while Sys.PlaybackThreadIterate(Dev) do
    if not Sys.DevWait(Dev) then
      Sys.DeviceDisconnected(Dev);  // 抜けずにゾンビとして続ける
  Sys.PlaybackThreadShutdown(Dev);
  Result := 0;
end;

{ RecordingAudioThread。 }
function RecordingThreadFunc(AData: Pointer): Integer;
var
  Dev: TPMLAudioDevice;
  Sys: TPMLAudioSystem;
begin
  MaskFloatExceptions;
  Dev := TPMLAudioDevice(AData);
  Sys := TPMLAudioSystem(Dev.Core);
  Sys.RecordingThreadSetup(Dev);
  repeat
    if not Sys.DevWaitRecording(Dev) then
      Sys.DeviceDisconnected(Dev);
  until not Sys.RecordingThreadIterate(Dev);
  Sys.RecordingThreadShutdown(Dev);
  Result := 0;
end;

{ ---- 系: 作る・壊す ---- }

constructor TPMLAudioSystem.Create(AContextRef: TObject; AOwner: TPMLObject;
  AQueue: TPMLEventQueue; const APreferred: String);
var
  DefPlayback, DefRecording: TPMLAudioDevice;
begin
  inherited Create(AContextRef, AOwner);
  FQueue := AQueue;
  FLock := TPMLRWLock.Create;
  // ID は 2 から（SDL2 の頃の 1 を避ける）。作り直しても戻さない。
  LastInstanceID.CompareAndSwap(0, 2);

  SelectBackend(APreferred);
  LogDebug('audio backend: ' + FBackendName);

  // 始めにデバイスの一覧を作る。
  DefPlayback := nil;
  DefRecording := nil;
  FBackend.DetectDevices(DefPlayback, DefRecording);
  // 既定を言わなかったら、最初に足されたもの。
  if DefPlayback = nil then
    DefPlayback := FirstAddedDevice(False);
  if DefRecording = nil then
    DefRecording := FirstAddedDevice(True);
  // 既定のデバイスには参照を 1 つ足す（新しい既定が来るまで生かす）。
  if DefPlayback <> nil then
  begin
    FDefaultPlaybackID := DefPlayback.InstanceID;
    RefDevice(DefPlayback);
  end;
  if DefRecording <> nil then
  begin
    FDefaultRecordingID := DefRecording.InstanceID;
    RefDevice(DefRecording);
  end;

  if FQueue <> nil then
    FQueue.RegisterPumpSource(Self as IPMLEventPumpSource);
end;

function TPMLAudioSystem.TryBackend(const AName: String): Boolean;
var
  Factory: TPMLAudioBackendFactory;
  B: TPMLAudioBackend;
begin
  Result := False;
  Factory := PMLFindAudioBackend(AName);
  if not Assigned(Factory) then
    Exit;
  try
    B := Factory(Self);
  except
    on E: Exception do
    begin
      LogDebug(Format('audio backend "%s" failed: %s', [AName, E.Message]));
      Exit;
    end;
  end;
  if B = nil then
    Exit;
  FBackend := B;
  FBackendName := B.Name;
  Result := True;
end;

procedure TPMLAudioSystem.SelectBackend(const APreferred: String);
var
  Names, Wanted: TStringArray;
  I: Integer;
  Tried: Boolean;
  W: String;
begin
  Names := PMLAudioBackendNames;
  if Trim(APreferred) <> '' then
  begin
    // カンマで区切った名前を順に試す。
    Tried := False;
    Wanted := APreferred.Split([',']);
    for I := 0 to High(Wanted) do
    begin
      W := Trim(Wanted[I]);
      // SDL の別名（pulse → pulseaudio）。
      if W = 'pulse' then
        W := 'pulseaudio';
      if W = '' then
        Continue;
      if Assigned(PMLFindAudioBackend(W)) then
        Tried := True;
      if TryBackend(W) then
        Exit;
    end;
    if not Tried then
      raise EPMLUnsupported.CreateFmt(
        'audio backend "%s" is not available (registered: %s); '
        + 'add PaPiMeLa.Backends (or PaPiMeLa) to uses to link the built-in backends',
        [APreferred, String.Join(', ', Names)]);
    raise EPMLAudioError.CreateFmt('audio backend "%s" could not be initialized', [APreferred]);
  end;

  if Length(Names) = 0 then
    raise EPMLAudioError.Create('no audio backend is registered; add PaPiMeLa.Backends (or PaPiMeLa) to uses');
  for I := 0 to High(Names) do
    if not PMLAudioBackendIsDemandOnly(Names[I]) and TryBackend(Names[I]) then
      Exit;
  raise EPMLAudioError.CreateFmt('No available audio device (tried: %s)', [String.Join(', ', Names)]);
end;

{ SDL_QuitAudio。 }
destructor TPMLAudioSystem.Destroy;
var
  Devs: array of TPMLAudioDevice;
  I: Integer;
begin
  if FQueue <> nil then
    FQueue.UnregisterPumpSource(Self as IPMLEventPumpSource);
  if FBackend <> nil then
  begin
    FBackend.DeinitializeStart;

    FLock.LockForWriting;
    FShuttingDown.Exchange(1);
    Devs := FDevices;
    FDevices := nil;
    FLogical := nil;
    FPending := nil;
    FPendingDisconnects := nil;
    FLock.Unlock;

    for I := 0 to High(Devs) do
      DestroyPhysical(Devs[I]);

    FBackend.Deinitialize;
    FreeAndNil(FBackend);
  end;
  FreeAndNil(FLock);
  inherited Destroy;
end;

procedure TPMLAudioSystem.LogDebug(const AMessage: String);
begin
  if (ContextServices <> nil) and (ContextServices.Log <> nil) then
    ContextServices.Log.Debug(PML_LOG_CATEGORY_AUDIO, AMessage);
end;

procedure TPMLAudioSystem.ReportCallbackException(E: Exception;
  ALogical: TPMLLogicalAudioDevice; const AWhere: String);
begin
  // §5.5: アプリの例外は内部を通さない。記録して、その論理デバイスを止める。
  ALogical.FPaused.Exchange(1);
  if (ContextServices <> nil) and (ContextServices.Log <> nil) then
    ContextServices.Log.Error(PML_LOG_CATEGORY_AUDIO,
      Format('audio device %d: %s raised %s: %s; the device is paused',
        [ALogical.FID, AWhere, E.ClassName, E.Message]));
end;

function TPMLAudioSystem.LoadWAV(AStream: TStream; out ASpec: TPMLAudioSpec): TBytes;
begin
  Result := PMLLoadWAV(AStream, TPMLWaveOptions.FromHints(Hint(PML_HINT_WAVE_RIFF_CHUNK_SIZE),
    Hint(PML_HINT_WAVE_TRUNCATION), Hint(PML_HINT_WAVE_FACT_CHUNK), Hint(PML_HINT_WAVE_CHUNK_LIMIT)), ASpec);
end;

function TPMLAudioSystem.LoadWAVFile(const APath: String; out ASpec: TPMLAudioSpec): TBytes;
begin
  Result := PMLLoadWAVFile(APath, TPMLWaveOptions.FromHints(Hint(PML_HINT_WAVE_RIFF_CHUNK_SIZE),
    Hint(PML_HINT_WAVE_TRUNCATION), Hint(PML_HINT_WAVE_FACT_CHUNK), Hint(PML_HINT_WAVE_CHUNK_LIMIT)), ASpec);
end;

function TPMLAudioSystem.Hint(const AName: String): String;
begin
  Result := '';
  if (ContextServices <> nil) and (ContextServices.Hints <> nil) then
    Result := ContextServices.Hints.GetHint(AName);
end;

procedure TPMLAudioSystem.SetCurrentThreadPriority(APriority: TPMLThreadPriority);
begin
  if ContextServices <> nil then
    ContextServices.SetCurrentThreadPriority(APriority)
  else
    TPMLThread.SetCurrentPriority(APriority);
end;

{ ---- 待っているイベント ---- }

procedure TPMLAudioSystem.QueueEvents(const AEvents: TPendingEvents);
var
  I, N: Integer;
begin
  if Length(AEvents) = 0 then
    Exit;
  FLock.LockForWriting;
  try
    N := Length(FPending);
    SetLength(FPending, N + Length(AEvents));
    for I := 0 to High(AEvents) do
      FPending[N + I] := AEvents[I];
  finally
    FLock.Unlock;
  end;
end;

{ SDL_UpdateAudio。 }
procedure TPMLAudioSystem.FlushPendingEvents;
var
  Taken: TPendingEvents;
  I: Integer;
  Ev: TPMLEvent;
begin
  FLock.LockForWriting;
  try
    Taken := FPending;
    FPending := nil;
  finally
    FLock.Unlock;
  end;
  if FQueue = nil then
    Exit;
  for I := 0 to High(Taken) do
  begin
    Ev := Default(TPMLEvent);
    Ev.Kind := Taken[I].Kind;
    Ev.Timestamp := PMLNowNS;
    Ev.AudioDevice.Which := Taken[I].ID;
    Ev.AudioDevice.Recording := IsRecordingID(Taken[I].ID);
    FQueue.Push(Ev);
  end;
end;

function TPMLAudioSystem.PumpSourceName: String;
begin
  Result := 'audio:' + FBackendName;
end;

procedure TPMLAudioSystem.PumpEvents(ATimeoutMs: Integer);
begin
  ProcessPendingDisconnects;
  FlushPendingEvents;
end;

{ ---- 表を引く（系の読み書きロックを持って呼ぶ） ---- }

function TPMLAudioSystem.FindDeviceLocked(AID: TPMLAudioDeviceID): TPMLAudioDevice;
var
  I: Integer;
begin
  for I := 0 to High(FDevices) do
    if FDevices[I].InstanceID = AID then
      Exit(FDevices[I]);
  Result := nil;
end;

function TPMLAudioSystem.FindLogicalLocked(AID: TPMLAudioDeviceID): TPMLLogicalAudioDevice;
var
  I: Integer;
begin
  for I := 0 to High(FLogical) do
    if FLogical[I].FID = AID then
      Exit(FLogical[I]);
  Result := nil;
end;

{ GetFirstAddedAudioDevice。ID は足した順に大きくなる。 }
function TPMLAudioSystem.FirstAddedDevice(ARecording: Boolean): TPMLAudioDevice;
var
  I: Integer;
begin
  Result := nil;
  FLock.LockForReading;
  try
    for I := 0 to High(FDevices) do
      if (FDevices[I].Recording = ARecording)
        and ((Result = nil) or (FDevices[I].InstanceID < Result.InstanceID)) then
        Result := FDevices[I];
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLAudioSystem.RemoveLogicalFromTable(ALogical: TPMLLogicalAudioDevice);
var
  I, J: Integer;
begin
  FLock.LockForWriting;
  try
    for I := 0 to High(FLogical) do
      if FLogical[I] = ALogical then
      begin
        for J := I to High(FLogical) - 1 do
          FLogical[J] := FLogical[J + 1];
        SetLength(FLogical, Length(FLogical) - 1);
        Break;
      end;
  finally
    FLock.Unlock;
  end;
end;

{ ---- 参照とロック ---- }

procedure TPMLAudioSystem.RefDevice(ADevice: TPMLAudioDevice);
begin
  ADevice.RefCount.IncRef;
end;

{ UnrefPhysicalAudioDevice。デバイスのロックを持たずに呼ぶ（壊すかもしれない）。 }
procedure TPMLAudioSystem.UnrefDevice(ADevice: TPMLAudioDevice);
var
  I, J: Integer;
begin
  if ADevice.RefCount.DecRef then
  begin
    FLock.LockForWriting;
    try
      for I := 0 to High(FDevices) do
        if FDevices[I] = ADevice then
        begin
          for J := I to High(FDevices) - 1 do
            FDevices[J] := FDevices[J + 1];
          SetLength(FDevices, Length(FDevices) - 1);
          Break;
        end;
    finally
      FLock.Unlock;
    end;
    DestroyPhysical(ADevice);
  end;
end;

procedure TPMLAudioSystem.ObtainDeviceObj(ADevice: TPMLAudioDevice);
begin
  if ADevice <> nil then
  begin
    RefDevice(ADevice);
    ADevice.Lock.Lock;
  end;
end;

procedure TPMLAudioSystem.ReleaseDevice(ADevice: TPMLAudioDevice);
begin
  if ADevice <> nil then
  begin
    ADevice.Lock.Unlock;
    UnrefDevice(ADevice);
  end;
end;

{ ObtainLogicalAudioDevice の後半。論理デバイスの物理デバイスに参照を足してロックする。
  既定が移る途中かもしれないので、ロックしてから確かめ直す。 }
function TPMLAudioSystem.ObtainLogical(ALogical: TPMLLogicalAudioDevice): TPMLAudioDevice;
var
  Recheck: TPMLAudioDevice;
begin
  FLock.LockForReading;
  try
    Result := ALogical.FPhysical;
    RefDevice(Result);
  finally
    FLock.Unlock;
  end;
  while True do
  begin
    Result.Lock.Lock;
    PMLMemoryBarrierAcquire;
    Recheck := ALogical.FPhysical;
    if Recheck = Result then
      Break;
    RefDevice(Recheck);
    Result.Lock.Unlock;
    UnrefDevice(Result);
    Result := Recheck;
  end;
end;

function TPMLAudioSystem.ObtainLogicalByID(AID: TPMLAudioDeviceID;
  out ADevice: TPMLAudioDevice): TPMLLogicalAudioDevice;
begin
  ADevice := nil;
  Result := nil;
  if not IsLogicalID(AID) then
    Exit;
  FLock.LockForReading;
  try
    Result := FindLogicalLocked(AID);
  finally
    FLock.Unlock;
  end;
  if Result <> nil then
    ADevice := ObtainLogical(Result);
end;

{ ObtainPhysicalAudioDevice。論理デバイスの ID ならその物理デバイス。 }
function TPMLAudioSystem.ObtainPhysicalByID(AID: TPMLAudioDeviceID): TPMLAudioDevice;
begin
  Result := nil;
  if IsLogicalID(AID) then
    ObtainLogicalByID(AID, Result)
  else
  begin
    FLock.LockForReading;
    try
      Result := FindDeviceLocked(AID);
      // 表から消える前に参照を足す（SDL はロックの外で足す。表を引いた直後に最後の参照が
      // 外れると壊れたものを掴む）。
      if Result <> nil then
        RefDevice(Result);
    finally
      FLock.Unlock;
    end;
    if Result <> nil then
      Result.Lock.Lock;
  end;
end;

{ ObtainPhysicalAudioDeviceDefaultAllowed。 }
function TPMLAudioSystem.ObtainPhysicalDefaultAllowed(AID: TPMLAudioDeviceID): TPMLAudioDevice;
var
  ID: TPMLAudioDeviceID;
  GotIt: Boolean;
begin
  if (AID <> PML_AUDIO_DEVICE_DEFAULT_PLAYBACK) and (AID <> PML_AUDIO_DEVICE_DEFAULT_RECORDING) then
    Exit(ObtainPhysicalByID(AID));
  while True do
  begin
    FLock.LockForReading;
    if AID = PML_AUDIO_DEVICE_DEFAULT_PLAYBACK then
      ID := FDefaultPlaybackID
    else
      ID := FDefaultRecordingID;
    FLock.Unlock;
    if ID = 0 then
      Exit(nil);
    Result := ObtainPhysicalByID(ID);
    if Result = nil then
      Exit;
    // ロックを待つ間に既定が変わっていないか。
    FLock.LockForReading;
    if AID = PML_AUDIO_DEVICE_DEFAULT_PLAYBACK then
      GotIt := ID = FDefaultPlaybackID
    else
      GotIt := ID = FDefaultRecordingID;
    FLock.Unlock;
    if GotIt then
      Exit;
    ReleaseDevice(Result);
  end;
end;

{ ---- 論理デバイスの破棄 ---- }

{ DestroyLogicalAudioDevice。物理デバイスのロックを持って呼ぶ。オブジェクトは Free しない。 }
procedure TPMLAudioSystem.DestroyLogical(ALogical: TPMLLogicalAudioDevice);
var
  Dev: TPMLAudioDevice;
  S, Next: TPMLAudioStream;
begin
  // 表から外す（終わりかけなら表はもう無い）。
  RemoveLogicalFromTable(ALogical);
  Dev := ALogical.FPhysical;
  if ALogical.FNext <> nil then
    ALogical.FNext.FPrev := ALogical.FPrev;
  if ALogical.FPrev <> nil then
    ALogical.FPrev.FNext := ALogical.FNext;
  if TPMLLogicalAudioDevice(Dev.LogicalDevices) = ALogical then
    Dev.LogicalDevices := ALogical.FNext;
  ALogical.FNext := nil;
  ALogical.FPrev := nil;

  // 結び付いたストリームを外す。
  S := ALogical.FBoundStreams;
  while S <> nil do
  begin
    S.Lock;
    Next := S.Binding.Next;
    S.Binding.Next := nil;
    S.Binding.Prev := nil;
    S.Binding.Device := nil;
    S.Unlock;
    S := Next;
  end;
  ALogical.FBoundStreams := nil;

  UpdateStreamFormats(Dev);
end;

{ SDL_CloseAudioDevice。 }
procedure TPMLAudioSystem.CloseLogical(ALogical: TPMLLogicalAudioDevice);
var
  Dev: TPMLAudioDevice;
begin
  Dev := ObtainLogical(ALogical);
  try
    DestroyLogical(ALogical);
    // 論理デバイスが残っていなければ、物理デバイスも閉じる。
    if Dev.LogicalDevices = nil then
      ClosePhysical(Dev);
    UnrefDevice(Dev);  // 論理デバイスごとの参照
  finally
    ReleaseDevice(Dev);
  end;
end;

{ DestroyPhysicalAudioDevice。表から外してから呼ぶ。スレッドは止めてから。 }
procedure TPMLAudioSystem.DestroyPhysical(ADevice: TPMLAudioDevice);
var
  L: TPMLLogicalAudioDevice;
begin
  if ADevice = nil then
    Exit;
  // 参照の数を変えないよう、ObtainDeviceObj は使わない。
  ADevice.Lock.Lock;
  try
    while ADevice.LogicalDevices <> nil do
    begin
      L := TPMLLogicalAudioDevice(ADevice.LogicalDevices);
      DestroyLogical(L);
      // 系が壊すので、論理デバイスの Destroy は閉じに来ない。
      L.FSystem := nil;
      L.Free;
    end;
    ClosePhysical(ADevice);
    FBackend.FreeDeviceHandle(ADevice);
  finally
    ADevice.Lock.Unlock;
  end;
  ADevice.Free;
end;

{ ---- 開く・閉じる ---- }

{ SerializePhysicalDeviceClose。ロックを持って呼ぶ。閉じている最中なら待つ。 }
procedure TPMLAudioSystem.SerializeClose(ADevice: TPMLAudioDevice);
begin
  while ADevice.ShutdownFlag.Load <> 0 do
    ADevice.CloseCond.Wait(ADevice.Lock);
end;

{ ClosePhysicalAudioDevice。ロックを持って呼ぶ。スレッドを待つ間はロックを外す。 }
procedure TPMLAudioSystem.ClosePhysical(ADevice: TPMLAudioDevice);
begin
  SerializeClose(ADevice);
  if ADevice.CurrentlyOpened then
    LogDebug(Format('AUDIO: closing %s device ''%s''',
      [IfThen(ADevice.Recording, 'recording', 'playback'), ADevice.Name]));

  ADevice.ShutdownFlag.Exchange(1);
  // スレッドが終われるようにロックを外す。この間の出入りは SerializeClose で守る。
  ADevice.Lock.Unlock;
  if ADevice.CurrentlyOpened then
    FBackend.InterruptDevice(ADevice);   // バックエンドの中で待っているスレッドを起こす
  if ADevice.Thread <> nil then
  begin
    ADevice.Thread.WaitFor;
    FreeAndNil(ADevice.Thread);
  end;
  if ADevice.CurrentlyOpened then
  begin
    // 自分でスレッドを持つバックエンドは、ここでスレッドを待ってから戻る。
    FBackend.CloseDevice(ADevice);
    ADevice.CurrentlyOpened := False;
    ADevice.Hidden := nil;
  end;
  ADevice.Lock.Lock;
  ADevice.ShutdownFlag.Exchange(0);
  ADevice.CloseCond.Broadcast;

  if ADevice.WorkBuffer <> nil then
    FreeMem(ADevice.WorkBuffer);
  ADevice.WorkBuffer := nil;
  if ADevice.MixBuffer <> nil then
    FreeMem(ADevice.MixBuffer);
  ADevice.MixBuffer := nil;
  if ADevice.PostmixBuffer <> nil then
    FreeMem(ADevice.PostmixBuffer);
  ADevice.PostmixBuffer := nil;

  ADevice.Spec := ADevice.DefaultSpec;
  ADevice.SampleFrames := 0;
  ADevice.SilenceValue := PMLAudioSilenceValue(ADevice.Spec.Format);
end;

procedure TPMLAudioSystem.PrepareAudioFormat(ARecording: Boolean; var ASpec: TPMLAudioSpec);
var
  V: Integer;
  F: TPMLAudioFormat;
begin
  if ASpec.Freq = 0 then
  begin
    if ARecording then
      ASpec.Freq := PML_DEFAULT_AUDIO_RECORDING_FREQUENCY
    else
      ASpec.Freq := PML_DEFAULT_AUDIO_PLAYBACK_FREQUENCY;
    V := StrToIntDef(Trim(Hint(PML_HINT_AUDIO_FREQUENCY)), 0);
    if V > 0 then
      ASpec.Freq := V;
  end;
  if ASpec.Channels = 0 then
  begin
    if ARecording then
      ASpec.Channels := PML_DEFAULT_AUDIO_RECORDING_CHANNELS
    else
      ASpec.Channels := PML_DEFAULT_AUDIO_PLAYBACK_CHANNELS;
    V := StrToIntDef(Trim(Hint(PML_HINT_AUDIO_CHANNELS)), 0);
    if V > 0 then
      ASpec.Channels := V;
  end;
  if ASpec.Format = 0 then
  begin
    F := ParseAudioFormatString(Hint(PML_HINT_AUDIO_FORMAT));
    if F <> PML_AUDIO_UNKNOWN then
      ASpec.Format := F
    else if ARecording then
      ASpec.Format := PML_DEFAULT_AUDIO_RECORDING_FORMAT
    else
      ASpec.Format := PML_DEFAULT_AUDIO_PLAYBACK_FORMAT;
  end;
end;

{ OpenPhysicalAudioDevice。ロックを持って呼ぶ。 }
function TPMLAudioSystem.OpenPhysical(ADevice: TPMLAudioDevice; AHasSpec: Boolean;
  const ASpec: TPMLAudioSpec; out AError: String): Boolean;
var
  Spec, Current: TPMLAudioSpec;
  DevType: String;
  Opened: Boolean;
  Err2: String;
begin
  AError := '';
  // 別のスレッドが閉じる途中でロックを外していることがある。
  SerializeClose(ADevice);

  // 失われたデバイスは開いたふりをする。既定として開いたものは、既定が正式に変わったら移る。
  if ADevice.Zombie.Load <> 0 then
    Exit(True);

  DevType := IfThen(ADevice.Recording, 'recording', 'playback');
  if AHasSpec then
    Spec := ASpec
  else
    Spec := ADevice.DefaultSpec;
  PrepareAudioFormat(ADevice.Recording, Spec);

  if ADevice.CurrentlyOpened then
  begin
    Current := ADevice.Spec;
    // もっと低い形式で開いていなければ、そのまま使う。
    if (PMLAudioBitSize(Spec.Format) <= PMLAudioBitSize(Current.Format))
      and (Spec.Channels <= Current.Channels) and (Spec.Freq <= Current.Freq) then
      Exit(True);
    // 開き直す。欄ごとに良い方を取る。
    if PMLAudioBitSize(Spec.Format) <= PMLAudioBitSize(Current.Format) then
      Spec.Format := Current.Format;
    Spec.Channels := Max(Spec.Channels, Current.Channels);
    Spec.Freq := Max(Spec.Freq, Current.Freq);
    LogDebug(Format('AUDIO: attempt to reopen %s device ''%s'' at higher spec! (%s,%d,%d => %s,%d,%d)',
      [DevType, ADevice.Name, PMLAudioFormatName(Current.Format), Current.Channels, Current.Freq,
       PMLAudioFormatName(Spec.Format), Spec.Channels, Spec.Freq]));
    ClosePhysical(ADevice);
    if not OpenPhysical(ADevice, True, Spec, AError) then
    begin
      // 元の形式に戻してみる。
      if not OpenPhysical(ADevice, True, Current, Err2) then
      begin
        // 開いていた論理デバイスが全部壊れた。切断として扱う。
        DeviceDisconnected(ADevice);
        Exit(False);
      end;
    end;
    // 結び付いたストリームを新しい形式に合わせ、形式の変更を知らせる。
    Spec := ADevice.Spec;
    ADevice.Spec := Current;  // 次の呼び出しがすぐ戻らないよう戻す。次で正しく入る
    DeviceFormatChangedAlreadyLocked(ADevice, Spec, ADevice.SampleFrames);
    LogDebug(Format('AUDIO: %s device ''%s'' is now at spec (%s,%d,%d)',
      [DevType, ADevice.Name, PMLAudioFormatName(ADevice.Spec.Format), ADevice.Spec.Channels,
       ADevice.Spec.Freq]));
    AError := '';
    Exit(True);
  end;

  // 始めはバックエンドの実装を使う。失われたら差し替える。
  ADevice.ZombieFunctions := False;
  // D-66: SDL の main はここで求めた形式をデバイスに入れない（いつも既定の形式で開く）。
  ADevice.Spec := Spec;
  ADevice.SampleFrames := DefaultSampleFramesFromFreq(ADevice.Spec.Freq);
  UpdatedDeviceFormat(ADevice);

  LogDebug(Format('AUDIO: attempt to open %s device ''%s'' at spec (%s,%d,%d)',
    [DevType, ADevice.Name, PMLAudioFormatName(Spec.Format), Spec.Channels, Spec.Freq]));

  // バックエンドが失敗しても後始末できるよう、先に印を付ける。
  ADevice.CurrentlyOpened := True;
  Opened := False;
  try
    Opened := FBackend.OpenDevice(ADevice);
    if not Opened then
      AError := 'the backend could not open the device';
  except
    on E: Exception do
      AError := E.Message;
  end;
  if not Opened then
  begin
    LogDebug(Format('AUDIO: open of %s device ''%s'' failed: %s', [DevType, ADevice.Name, AError]));
    ClosePhysical(ADevice);
    Exit(False);
  end;

  // バックエンドが形式を変えて呼び忘れたときのため。
  UpdatedDeviceFormat(ADevice);

  ADevice.WorkBuffer := AllocMem(ADevice.WorkBufferSize);
  if NeedsMixBuffer(ADevice) then
    ADevice.MixBuffer := AllocMem(ADevice.WorkBufferSize);
  // D-70: 録音は音量だけでも F32 の置き場を使う。
  if ADevice.Recording then
    ADevice.PostmixBuffer := AllocMem(ADevice.WorkBufferSize);

  // スレッドを始める（バックエンドが自分で持たなければ）。
  if not (TPMLAudioBackendCapability.ProvidesOwnCallbackThread in FBackend.Capabilities) then
  begin
    try
      if ADevice.Recording then
        ADevice.Thread := TPMLThread.CreateFunc(ThreadName(ADevice), @RecordingThreadFunc, ADevice)
      else
        ADevice.Thread := TPMLThread.CreateFunc(ThreadName(ADevice), @PlaybackThreadFunc, ADevice);
    except
      on E: Exception do
      begin
        AError := 'Couldn''t create audio thread: ' + E.Message;
        ADevice.Thread := nil;
        ClosePhysical(ADevice);
        Exit(False);
      end;
    end;
  end;

  LogDebug(Format('AUDIO: attempt to open %s device ''%s'' succeeded! Opened at spec (%s,%d,%d)',
    [DevType, ADevice.Name, PMLAudioFormatName(ADevice.Spec.Format), ADevice.Spec.Channels,
     ADevice.Spec.Freq]));
  Result := True;
end;

{ SDL_OpenAudioDevice。 }
function TPMLAudioSystem.OpenLogical(AID: TPMLAudioDeviceID; AHasSpec: Boolean;
  const ASpec: TPMLAudioSpec): TPMLLogicalAudioDevice;
var
  WantsDefault: Boolean;
  Dev: TPMLAudioDevice;
  Existing: TPMLLogicalAudioDevice;
  Err: String;
begin
  if AHasSpec then
  begin
    if (ASpec.Format <> 0) and not PMLIsSupportedAudioFormat(ASpec.Format) then
      raise EPMLArgument.Create('Parameter ''ASpec.Format'' is invalid');
    if (ASpec.Channels <> 0) and not PMLIsSupportedChannelCount(ASpec.Channels) then
      raise EPMLArgument.Create('Parameter ''ASpec.Channels'' is invalid');
    if ASpec.Freq < 0 then
      raise EPMLArgument.Create('Parameter ''ASpec.Freq'' is invalid');
  end;

  WantsDefault := (AID = PML_AUDIO_DEVICE_DEFAULT_PLAYBACK) or (AID = PML_AUDIO_DEVICE_DEFAULT_RECORDING);
  // 論理デバイスの ID なら、同じ物理デバイスにもう 1 つ開く。
  if WantsDefault or IsPhysicalDevice(AID) then
    Dev := ObtainPhysicalDefaultAllowed(AID)
  else
  begin
    Existing := ObtainLogicalByID(AID, Dev);
    if Existing <> nil then
      WantsDefault := Existing.FOpenedAsDefault;
  end;
  if Dev = nil then
  begin
    if (AID = PML_AUDIO_DEVICE_DEFAULT_PLAYBACK) or (AID = PML_AUDIO_DEVICE_DEFAULT_RECORDING) then
      raise EPMLAudioError.Create('No default audio device available');
    raise EPMLArgument.Create('Invalid audio device instance ID');
  end;

  Result := nil;
  try
    if (not WantsDefault) and (Dev.Zombie.Load <> 0) then
      raise EPMLAudioError.Create('Device was already lost and can''t accept new opens');
    if not OpenPhysical(Dev, AHasSpec, ASpec, Err) then
      raise EPMLAudioError.CreateFmt('Couldn''t open audio device ''%s'': %s', [Dev.Name, Err]);
    RefDevice(Dev);  // CloseLogical で外す
    Result := TPMLLogicalAudioDevice.Create(ContextRef, Self);
    Result.FSystem := Self;
    Result.FID := AssignInstanceID(Dev.Recording, True);
    Result.FPhysical := Dev;
    Result.FGain := 1.0;
    Result.FOpenedAsDefault := WantsDefault;
    Result.FNext := TPMLLogicalAudioDevice(Dev.LogicalDevices);
    if Dev.LogicalDevices <> nil then
      TPMLLogicalAudioDevice(Dev.LogicalDevices).FPrev := Result;
    Dev.LogicalDevices := Result;
    UpdateStreamFormats(Dev);
  finally
    ReleaseDevice(Dev);
  end;

  FLock.LockForWriting;
  try
    SetLength(FLogical, Length(FLogical) + 1);
    FLogical[High(FLogical)] := Result;
  finally
    FLock.Unlock;
  end;
end;

function TPMLAudioSystem.OpenDevice(AID: TPMLAudioDeviceID): TPMLLogicalAudioDevice;
begin
  Result := OpenLogical(AID, False, TPMLAudioSpec.Make(0, 0, 0));
end;

function TPMLAudioSystem.OpenDevice(AID: TPMLAudioDeviceID;
  const ASpec: TPMLAudioSpec): TPMLLogicalAudioDevice;
begin
  Result := OpenLogical(AID, True, ASpec);
end;

{ SDL_OpenAudioDeviceStream。 }
function TPMLAudioSystem.OpenStream(AID: TPMLAudioDeviceID; AHasSpec: Boolean;
  const ASpec: TPMLAudioSpec; ACallback: TPMLAudioStreamCallback): TPMLAudioStream;
var
  L: TPMLLogicalAudioDevice;
  Dev: TPMLAudioDevice;
  Spec: TPMLAudioSpec;
begin
  L := OpenLogical(AID, AHasSpec, ASpec);
  Result := nil;
  try
    Dev := ObtainLogical(L);
    try
      // SDL2 に合わせ、止まった状態で始める。
      L.FPaused.Exchange(1);
      // 形式を求めなかったら、変換しないストリーム。
      if AHasSpec then
        Spec := ASpec
      else
        Spec := Dev.Spec;
      if Dev.Recording then
        Result := TPMLAudioStream.Create(Dev.Spec, Spec)
      else
        Result := TPMLAudioStream.Create(Spec, Dev.Spec);
      // BindStreams の確かめとロックは要らない（誰も知らないストリーム）。
      L.FBoundStreams := Result;
      L.FSimplified := True;
      Result.Binding.Device := L;
      Result.Binding.Recording := Dev.Recording;
      Result.Binding.Simplified := True;
      UpdateStreamFormats(Dev);
      if Assigned(ACallback) then
      begin
        if Dev.Recording then
          Result.OnPut := ACallback
        else
          Result.OnGet := ACallback;
      end;
    finally
      ReleaseDevice(Dev);
    end;
  except
    // ストリームを作れなかった（形式の誤り）。結び付いていればデバイスごと閉じる。
    if Result <> nil then
      Result.Free
    else
      L.Free;
    raise;
  end;
end;

function TPMLAudioSystem.OpenDeviceStream(AID: TPMLAudioDeviceID;
  ACallback: TPMLAudioStreamCallback): TPMLAudioStream;
begin
  Result := OpenStream(AID, False, TPMLAudioSpec.Make(0, 0, 0), ACallback);
end;

function TPMLAudioSystem.OpenDeviceStream(AID: TPMLAudioDeviceID; const ASpec: TPMLAudioSpec;
  ACallback: TPMLAudioStreamCallback): TPMLAudioStream;
begin
  Result := OpenStream(AID, True, ASpec, ACallback);
end;

{ ---- 後置き処理 ---- }

{ SDL_SetAudioPostmixCallback の中身。物理デバイスのロックを持って呼ぶ。 }
procedure TPMLAudioSystem.SetPostmixLocked(ALogical: TPMLLogicalAudioDevice;
  ADevice: TPMLAudioDevice; ACallback: TPMLAudioPostmixCallback);
begin
  if Assigned(ACallback) and (ADevice.PostmixBuffer = nil) and (ADevice.WorkBufferSize > 0) then
    ADevice.PostmixBuffer := AllocMem(ADevice.WorkBufferSize);
  ALogical.FPostmix := ACallback;
  UpdateStreamFormats(ADevice);
end;

{ ---- 一覧と問い合わせ ---- }

function TPMLAudioSystem.DeviceList(ARecording: Boolean): TPMLAudioDeviceIDs;
var
  I, N: Integer;
begin
  Result := nil;
  FLock.LockForReading;
  try
    SetLength(Result, Length(FDevices));
    N := 0;
    for I := 0 to High(FDevices) do
      if (FDevices[I].Recording = ARecording) and (FDevices[I].Zombie.Load = 0) then
      begin
        Result[N] := FDevices[I].InstanceID;
        Inc(N);
      end;
    SetLength(Result, N);
  finally
    FLock.Unlock;
  end;
end;

function TPMLAudioSystem.PlaybackDevices: TPMLAudioDeviceIDs;
begin
  Result := DeviceList(False);
end;

function TPMLAudioSystem.RecordingDevices: TPMLAudioDeviceIDs;
begin
  Result := DeviceList(True);
end;

{ SDL_GetAudioDeviceName。名前は変わらないので、デバイスはロックしない（系の読みロックだけ）。 }
function TPMLAudioSystem.DeviceName(AID: TPMLAudioDeviceID): String;
var
  ID: TPMLAudioDeviceID;
  Dev: TPMLAudioDevice;
  L: TPMLLogicalAudioDevice;
  Found: Boolean;
begin
  Result := '';
  Found := False;
  FLock.LockForReading;
  try
    ID := AID;
    if ID = PML_AUDIO_DEVICE_DEFAULT_PLAYBACK then
      ID := FDefaultPlaybackID
    else if ID = PML_AUDIO_DEVICE_DEFAULT_RECORDING then
      ID := FDefaultRecordingID;
    if IsLogicalID(ID) then
    begin
      L := FindLogicalLocked(ID);
      if L <> nil then
      begin
        Result := L.FPhysical.Name;
        Found := True;
      end;
    end
    else
    begin
      Dev := FindDeviceLocked(ID);
      if Dev <> nil then
      begin
        Result := Dev.Name;
        Found := True;
      end;
    end;
  finally
    FLock.Unlock;
  end;
  if not Found then
    raise EPMLArgument.Create('Invalid audio device instance ID');
end;

function TPMLAudioSystem.DeviceFormat(AID: TPMLAudioDeviceID): TPMLAudioSpec;
var
  Frames: Integer;
begin
  Result := DeviceFormat(AID, Frames);
end;

function TPMLAudioSystem.DeviceFormat(AID: TPMLAudioDeviceID;
  out ASampleFrames: Integer): TPMLAudioSpec;
var
  Dev: TPMLAudioDevice;
begin
  Dev := ObtainPhysicalDefaultAllowed(AID);
  if Dev = nil then
    raise EPMLArgument.Create('Invalid audio device instance ID');
  try
    Result := Dev.Spec;
    ASampleFrames := Dev.SampleFrames;
  finally
    ReleaseDevice(Dev);
  end;
end;

function TPMLAudioSystem.DeviceChannelMap(AID: TPMLAudioDeviceID): TPMLChannelMap;
var
  Dev: TPMLAudioDevice;
begin
  Dev := ObtainPhysicalDefaultAllowed(AID);
  if Dev = nil then
    raise EPMLArgument.Create('Invalid audio device instance ID');
  try
    Result := Copy(Dev.ChannelMap, 0, Length(Dev.ChannelMap));
  finally
    ReleaseDevice(Dev);
  end;
end;

function TPMLAudioSystem.DeviceUniqueID(AID: TPMLAudioDeviceID): String;
var
  Dev: TPMLAudioDevice;
begin
  // SDL_GetAudioDeviceProperties は既定の印を受け付けない。
  Dev := ObtainPhysicalByID(AID);
  if Dev = nil then
    raise EPMLArgument.Create('Invalid audio device instance ID');
  try
    Result := Dev.UniqueID;
  finally
    ReleaseDevice(Dev);
  end;
end;

class function TPMLAudioSystem.IsPhysicalDevice(AID: TPMLAudioDeviceID): Boolean;
begin
  Result := (AID and IDBitPhysical) <> 0;
end;

class function TPMLAudioSystem.IsPlaybackDevice(AID: TPMLAudioDeviceID): Boolean;
begin
  Result := (AID and IDBitPlayback) <> 0;
end;

{ ---- ストリームの側から ---- }

procedure TPMLAudioSystem.UnbindStream(AStream: TPMLAudioStream);
begin
  UnbindStreamsImpl([AStream]);
end;

procedure TPMLAudioSystem.UnbindStreams(const AStreams: array of TPMLAudioStream);
begin
  UnbindStreamsImpl(AStreams);
end;

function TPMLAudioSystem.StreamDevice(AStream: TPMLAudioStream): TPMLLogicalAudioDevice;
begin
  if AStream = nil then
    raise EPMLArgument.Create('Parameter ''AStream'' is invalid');
  AStream.Lock;
  try
    Result := TPMLLogicalAudioDevice(AStream.Binding.Device);
  finally
    AStream.Unlock;
  end;
end;

procedure TPMLAudioSystem.PauseStreamDevice(AStream: TPMLAudioStream);
var
  L: TPMLLogicalAudioDevice;
begin
  L := StreamDevice(AStream);
  if L = nil then
    raise EPMLArgument.Create('Audio stream not bound to an audio device');
  L.Pause;
end;

procedure TPMLAudioSystem.ResumeStreamDevice(AStream: TPMLAudioStream);
var
  L: TPMLLogicalAudioDevice;
begin
  L := StreamDevice(AStream);
  if L = nil then
    raise EPMLArgument.Create('Audio stream not bound to an audio device');
  L.Resume;
end;

function TPMLAudioSystem.StreamDevicePaused(AStream: TPMLAudioStream): Boolean;
var
  L: TPMLLogicalAudioDevice;
begin
  L := StreamDevice(AStream);
  Result := (L <> nil) and L.Paused;
end;

{ ---- バックエンドから ---- }

{ SDL_AddAudioDevice と CreatePhysicalAudioDevice。 }
function TPMLAudioSystem.AddDevice(ARecording: Boolean; const AName, AUniqueID: String;
  const ASpec: TPMLAudioSpec; AHandle: Pointer): TPMLAudioDevice;
var
  Spec: TPMLAudioSpec;
  Ev: TPendingEvents;
begin
  if ARecording and not (TPMLAudioBackendCapability.HasRecordingSupport in FBackend.Capabilities) then
    raise EPMLArgument.Create('AddDevice: the backend has no recording support');
  // 終わりかけなら足さない（最後の瞬間の hotplug）。
  FLock.LockForReading;
  try
    if FShuttingDown.Load <> 0 then
      Exit(nil);
  finally
    FLock.Unlock;
  end;

  if ARecording then
    Spec := TPMLAudioSpec.Make(PML_DEFAULT_AUDIO_RECORDING_FORMAT,
      PML_DEFAULT_AUDIO_RECORDING_CHANNELS, PML_DEFAULT_AUDIO_RECORDING_FREQUENCY)
  else
    Spec := TPMLAudioSpec.Make(PML_DEFAULT_AUDIO_PLAYBACK_FORMAT,
      PML_DEFAULT_AUDIO_PLAYBACK_CHANNELS, PML_DEFAULT_AUDIO_PLAYBACK_FREQUENCY);
  if ASpec.Format <> 0 then
    Spec.Format := ASpec.Format;
  if ASpec.Channels <> 0 then
    Spec.Channels := ASpec.Channels;
  if ASpec.Freq <> 0 then
    Spec.Freq := ASpec.Freq;

  Result := TPMLAudioDevice.Create;
  Result.Core := Self;
  Result.Name := AName;
  Result.UniqueID := AUniqueID;
  Result.Recording := ARecording;
  Result.Spec := Spec;
  Result.DefaultSpec := Spec;
  Result.SampleFrames := DefaultSampleFramesFromFreq(Spec.Freq);
  Result.SilenceValue := PMLAudioSilenceValue(Spec.Format);
  Result.Handle := AHandle;
  Result.InstanceID := AssignInstanceID(ARecording, False);
  RefDevice(Result);  // 切断で外す

  FLock.LockForWriting;
  try
    SetLength(FDevices, Length(FDevices) + 1);
    FDevices[High(FDevices)] := Result;
  finally
    FLock.Unlock;
  end;

  // 追加のイベントは、次の Pump で（内部のスレッドから離れて）出す。
  SetLength(Ev, 1);
  Ev[0].Kind := TPMLEventKind.AudioDeviceAdded;
  Ev[0].ID := Result.InstanceID;
  QueueEvents(Ev);
end;

{ SDL_AudioDeviceDisconnected。どのスレッドからでも。後始末はメインスレッドで。 }
procedure TPMLAudioSystem.DeviceDisconnected(ADevice: TPMLAudioDevice);
begin
  if ADevice = nil then
    Exit;
  RefDevice(ADevice);  // 後始末で外す
  // 失われた印だけ付ける。知らせはメインスレッドで。
  ADevice.Zombie.CompareAndSwap(0, 1);
  if GetCurrentThreadID = MainThreadID then
    DisconnectedOnMainThread(ADevice.InstanceID)
  else
  begin
    FLock.LockForWriting;
    try
      SetLength(FPendingDisconnects, Length(FPendingDisconnects) + 1);
      FPendingDisconnects[High(FPendingDisconnects)] := ADevice.InstanceID;
    finally
      FLock.Unlock;
    end;
    if FQueue <> nil then
      FQueue.WakeUp;
  end;
end;

procedure TPMLAudioSystem.ProcessPendingDisconnects;
var
  IDs: array of TPMLAudioDeviceID;
  I: Integer;
begin
  FLock.LockForWriting;
  try
    IDs := FPendingDisconnects;
    FPendingDisconnects := nil;
  finally
    FLock.Unlock;
  end;
  for I := 0 to High(IDs) do
    DisconnectedOnMainThread(IDs[I]);
end;

{ SDL_AudioDeviceDisconnected_OnMainThread。 }
procedure TPMLAudioSystem.DisconnectedOnMainThread(AID: TPMLAudioDeviceID);
var
  Dev: TPMLAudioDevice;
  IsDefault, FirstDisconnect: Boolean;
  Ev: TPendingEvents;
  L: TPMLLogicalAudioDevice;
begin
  Dev := ObtainPhysicalByID(AID);
  if Dev = nil then
    Exit;  // もう消えた
  Ev := nil;
  FLock.LockForReading;
  IsDefault := (AID = FDefaultPlaybackID) or (AID = FDefaultRecordingID);
  FLock.Unlock;

  // Zombie: 0 = 生きている、1 = 失われた印だけ、2 = 知らせ済み。
  FirstDisconnect := Dev.Zombie.CompareAndSwap(0, 2) or Dev.Zombie.CompareAndSwap(1, 2);
  if FirstDisconnect then
  begin
    Dev.ZombieFunctions := True;
    // 既定のデバイスなら、名指しで開いた論理デバイスだけに知らせる（既定として開いたものは
    // 後で移る）。既定でなければ全部に。知らせた後も、閉じられるまで無音を流し続ける。
    L := TPMLLogicalAudioDevice(Dev.LogicalDevices);
    while L <> nil do
    begin
      if (not IsDefault) or (not L.FOpenedAsDefault) then
      begin
        SetLength(Ev, Length(Ev) + 1);
        Ev[High(Ev)].Kind := TPMLEventKind.AudioDeviceRemoved;
        Ev[High(Ev)].ID := L.FID;
      end;
      L := L.FNext;
    end;
    SetLength(Ev, Length(Ev) + 1);
    Ev[High(Ev)].Kind := TPMLEventKind.AudioDeviceRemoved;
    Ev[High(Ev)].ID := Dev.InstanceID;
  end;

  ReleaseDevice(Dev);

  if FirstDisconnect then
  begin
    QueueEvents(Ev);
    UnrefDevice(Dev);  // AddDevice で足した参照
  end;
  // DeviceDisconnected で足した参照。
  UnrefDevice(Dev);
end;

{ SDL_DefaultAudioDeviceChanged。 }
procedure TPMLAudioSystem.DefaultDeviceChanged(ANewDefault: TPMLAudioDevice);
var
  Recording, IsAlreadyDefault, NeedsMigration, SpecChanged: Boolean;
  CurrentID: TPMLAudioDeviceID;
  CurrentDev: TPMLAudioDevice;
  Spec: TPMLAudioSpec;
  L, Next: TPMLLogicalAudioDevice;
  S: TPMLAudioStream;
  SS: TPMLAudioSpec;
  Ev: TPendingEvents;
  Err: String;
begin
  if ANewDefault = nil then
    Exit;
  Recording := ANewDefault.Recording;

  // 新しい開き方がすぐ新しい既定へ行くよう、先に切り替える。
  FLock.LockForWriting;
  if Recording then
    CurrentID := FDefaultRecordingID
  else
    CurrentID := FDefaultPlaybackID;
  IsAlreadyDefault := ANewDefault.InstanceID = CurrentID;
  if not IsAlreadyDefault then
  begin
    if Recording then
      FDefaultRecordingID := ANewDefault.InstanceID
    else
      FDefaultPlaybackID := ANewDefault.InstanceID;
  end;
  FLock.Unlock;
  if IsAlreadyDefault then
    Exit;

  Ev := nil;
  // 既定のデバイスには参照を 1 つ足す。
  RefDevice(ANewDefault);
  ObtainDeviceObj(ANewDefault);
  CurrentDev := ObtainPhysicalByID(CurrentID);
  if CurrentDev <> nil then
  begin
    // 既定として開いた論理デバイスを移す。新しいデバイスを開く形式は、結び付いたストリームの
    // アプリ側の形式の、欄ごとの最大。
    Spec := TPMLAudioSpec.Make(0, 0, 0);
    NeedsMigration := False;
    L := TPMLLogicalAudioDevice(CurrentDev.LogicalDevices);
    while L <> nil do
    begin
      if L.FOpenedAsDefault then
      begin
        NeedsMigration := True;
        S := L.FBoundStreams;
        while S <> nil do
        begin
          if Recording then
            SS := S.DstSpec
          else
            SS := S.SrcSpec;
          if PMLAudioBitSize(SS.Format) > PMLAudioBitSize(Spec.Format) then
            Spec.Format := SS.Format;
          if SS.Channels > Spec.Channels then
            Spec.Channels := SS.Channels;
          if SS.Freq > Spec.Freq then
            Spec.Freq := SS.Freq;
          S := S.Binding.Next;
        end;
      end;
      L := L.FNext;
    end;

    if NeedsMigration then
      // 開けなければ、全部を古い既定に残す。
      NeedsMigration := OpenPhysical(ANewDefault, True, Spec, Err);

    if NeedsMigration then
    begin
      // 並びの変化はまだ知らせない（SDL と同じ）。
      SpecChanged := (CurrentDev.Spec.Format <> ANewDefault.Spec.Format)
        or (CurrentDev.Spec.Channels <> ANewDefault.Spec.Channels)
        or (CurrentDev.Spec.Freq <> ANewDefault.Spec.Freq);
      L := TPMLLogicalAudioDevice(CurrentDev.LogicalDevices);
      while L <> nil do
      begin
        Next := L.FNext;
        if L.FOpenedAsDefault then
        begin
          // 系の書きロックの下で移す（ObtainLogical が途中のものを掴まないよう）。
          FLock.LockForWriting;
          if L.FNext <> nil then
            L.FNext.FPrev := L.FPrev;
          if L.FPrev <> nil then
            L.FPrev.FNext := L.FNext;
          if TPMLLogicalAudioDevice(CurrentDev.LogicalDevices) = L then
            CurrentDev.LogicalDevices := L.FNext;
          L.FPhysical := ANewDefault;
          L.FPrev := nil;
          L.FNext := TPMLLogicalAudioDevice(ANewDefault.LogicalDevices);
          if ANewDefault.LogicalDevices <> nil then
            TPMLLogicalAudioDevice(ANewDefault.LogicalDevices).FPrev := L;
          ANewDefault.LogicalDevices := L;
          FLock.Unlock;

          RefDevice(ANewDefault);
          UnrefDevice(CurrentDev);
          // 後置き処理の置き場を新しいデバイスに用意する。
          SetPostmixLocked(L, ANewDefault, L.FPostmix);

          if SpecChanged then
          begin
            SetLength(Ev, Length(Ev) + 1);
            Ev[High(Ev)].Kind := TPMLEventKind.AudioDeviceFormatChanged;
            Ev[High(Ev)].ID := L.FID;
          end;
        end;
        L := Next;
      end;

      UpdateStreamFormats(CurrentDev);
      UpdateStreamFormats(ANewDefault);
      // 古いデバイスに何も残らなければ閉じる。
      if CurrentDev.LogicalDevices = nil then
        ClosePhysical(CurrentDev);
    end;
    ReleaseDevice(CurrentDev);
  end;
  ReleaseDevice(ANewDefault);

  // 古い既定に足していた参照を外す。
  if CurrentDev <> nil then
    UnrefDevice(CurrentDev);
  QueueEvents(Ev);
end;

{ SDL_AudioDeviceFormatChangedAlreadyLocked。 }
function TPMLAudioSystem.DeviceFormatChangedAlreadyLocked(ADevice: TPMLAudioDevice;
  const ASpec: TPMLAudioSpec; ASampleFrames: Integer): Boolean;
var
  OrigWorkBufferSize: Integer;
  Ev: TPendingEvents;
  L: TPMLLogicalAudioDevice;
begin
  OrigWorkBufferSize := ADevice.WorkBufferSize;
  // 並びの変化はまだ見ない（SDL と同じ）。
  if (ADevice.Spec.Format = ASpec.Format) and (ADevice.Spec.Channels = ASpec.Channels)
    and (ADevice.Spec.Freq = ASpec.Freq) and (ASampleFrames = ADevice.SampleFrames) then
    Exit(True);

  ADevice.Spec := ASpec;
  UpdateStreamFormats(ADevice);
  ADevice.SampleFrames := ASampleFrames;
  UpdatedDeviceFormat(ADevice);
  if (ADevice.WorkBuffer <> nil) and (ADevice.WorkBufferSize > OrigWorkBufferSize) then
  begin
    FreeMem(ADevice.WorkBuffer);
    ADevice.WorkBuffer := AllocMem(ADevice.WorkBufferSize);
    if ADevice.PostmixBuffer <> nil then
    begin
      FreeMem(ADevice.PostmixBuffer);
      ADevice.PostmixBuffer := AllocMem(ADevice.WorkBufferSize);
    end;
    if ADevice.MixBuffer <> nil then
      FreeMem(ADevice.MixBuffer);
    ADevice.MixBuffer := nil;
    if NeedsMixBuffer(ADevice) then
      ADevice.MixBuffer := AllocMem(ADevice.WorkBufferSize);
  end;
  // SDL は、F32 から変わったのに置き場が大きくならなければ、混ぜる置き場を作らない。
  if (ADevice.WorkBuffer <> nil) and (ADevice.MixBuffer = nil) and NeedsMixBuffer(ADevice) then
    ADevice.MixBuffer := AllocMem(ADevice.WorkBufferSize);

  // 物理デバイスと、その上の論理デバイスごとに知らせる。
  Ev := nil;
  SetLength(Ev, 1);
  Ev[0].Kind := TPMLEventKind.AudioDeviceFormatChanged;
  Ev[0].ID := ADevice.InstanceID;
  L := TPMLLogicalAudioDevice(ADevice.LogicalDevices);
  while L <> nil do
  begin
    SetLength(Ev, Length(Ev) + 1);
    Ev[High(Ev)].Kind := TPMLEventKind.AudioDeviceFormatChanged;
    Ev[High(Ev)].ID := L.FID;
    L := L.FNext;
  end;
  QueueEvents(Ev);
  Result := True;
end;

function TPMLAudioSystem.DeviceFormatChanged(ADevice: TPMLAudioDevice;
  const ASpec: TPMLAudioSpec; ASampleFrames: Integer): Boolean;
begin
  ObtainDeviceObj(ADevice);
  try
    Result := DeviceFormatChangedAlreadyLocked(ADevice, ASpec, ASampleFrames);
  finally
    ReleaseDevice(ADevice);
  end;
end;

{ SDL_FindPhysicalAudioDeviceByHandle。 }
function TPMLAudioSystem.FindDeviceByHandle(AHandle: Pointer): TPMLAudioDevice;
var
  I: Integer;
begin
  Result := nil;
  FLock.LockForReading;
  try
    for I := 0 to High(FDevices) do
      if FDevices[I].Handle = AHandle then
        Exit(FDevices[I]);
  finally
    FLock.Unlock;
  end;
end;

{ SDL_UpdatedAudioDeviceFormat。 }
procedure TPMLAudioSystem.UpdatedDeviceFormat(ADevice: TPMLAudioDevice);
begin
  ADevice.SilenceValue := PMLAudioSilenceValue(ADevice.Spec.Format);
  ADevice.BufferSize := ADevice.SampleFrames * ADevice.Spec.FrameSize;
  ADevice.WorkBufferSize := ADevice.SampleFrames * SizeOf(Single) * ADevice.Spec.Channels;
  ADevice.WorkBufferSize := Max(ADevice.BufferSize, ADevice.WorkBufferSize);
end;

{ SDL_GetDefaultSampleFramesFromFreq。 }
function TPMLAudioSystem.DefaultSampleFramesFromFreq(AFreq: Integer): Integer;
var
  V: Integer;
begin
  V := StrToIntDef(Trim(Hint(PML_HINT_AUDIO_DEVICE_SAMPLE_FRAMES)), 0);
  if V > 0 then
    Exit(V);
  if AFreq <= 22050 then
    Result := 512
  else if AFreq <= 48000 then
    Result := 1024
  else if AFreq <= 96000 then
    Result := 2048
  else
    Result := 4096;
end;

{ SDL_GetAudioThreadName（SDLAudioP15 の代わりに PMLAudioP15。C は録音）。 }
function TPMLAudioSystem.ThreadName(ADevice: TPMLAudioDevice): String;
begin
  Result := 'PMLAudio' + IfThen(ADevice.Recording, 'C', 'P') + IntToStr(ADevice.InstanceID);
end;

{ ---- デバイスのスレッドの部品 ---- }

{ ZombieWaitDevice: 失われたデバイスでも、本物と同じ速さで進む。 }
procedure TPMLAudioSystem.ZombieWait(ADevice: TPMLAudioDevice);
var
  Frames: Integer;
begin
  if ADevice.ShutdownFlag.Load = 0 then
  begin
    Frames := ADevice.BufferSize div ADevice.Spec.FrameSize;
    PMLDelay(LongWord((Frames * 1000) div ADevice.Spec.Freq));
  end;
end;

function TPMLAudioSystem.DevWait(ADevice: TPMLAudioDevice): Boolean;
begin
  if ADevice.ZombieFunctions then
  begin
    ZombieWait(ADevice);
    Exit(True);
  end;
  try
    Result := FBackend.WaitDevice(ADevice);
  except
    on E: Exception do
    begin
      LogDebug('AUDIO: WaitDevice failed: ' + E.Message);
      Result := False;
    end;
  end;
end;

function TPMLAudioSystem.DevWaitRecording(ADevice: TPMLAudioDevice): Boolean;
begin
  if ADevice.ZombieFunctions then
  begin
    ZombieWait(ADevice);
    Exit(True);
  end;
  try
    Result := FBackend.WaitRecordingDevice(ADevice);
  except
    on E: Exception do
    begin
      LogDebug('AUDIO: WaitRecordingDevice failed: ' + E.Message);
      Result := False;
    end;
  end;
end;

function TPMLAudioSystem.DevGetBuf(ADevice: TPMLAudioDevice; var ASize: Integer): PByte;
begin
  if ADevice.ZombieFunctions then
    Exit(ADevice.WorkBuffer);
  Result := FBackend.GetDeviceBuf(ADevice, ASize);
end;

function TPMLAudioSystem.DevPlay(ADevice: TPMLAudioDevice; ABuffer: PByte; ALen: Integer): Boolean;
begin
  if ADevice.ZombieFunctions then
    Exit(True);  // 捨てる
  Result := FBackend.PlayDevice(ADevice, ABuffer, ALen);
end;

function TPMLAudioSystem.DevRecord(ADevice: TPMLAudioDevice; ABuffer: Pointer; ALen: Integer): Integer;
begin
  if ADevice.ZombieFunctions then
  begin
    // いつも無音で満たす。
    FillChar(ABuffer^, ALen, ADevice.SilenceValue);
    Exit(ALen);
  end;
  Result := FBackend.RecordDevice(ADevice, ABuffer, ALen);
end;

procedure TPMLAudioSystem.DevFlush(ADevice: TPMLAudioDevice);
begin
  if not ADevice.ZombieFunctions then
    FBackend.FlushRecording(ADevice);
end;

function TPMLAudioSystem.SafeGetData(ALogical: TPMLLogicalAudioDevice; AStream: TPMLAudioStream;
  ABuffer: Pointer; ALen: Integer): Integer;
begin
  try
    Result := AStream.GetDataAdjustGain(ABuffer, ALen, ALogical.FGain);
  except
    on E: Exception do
    begin
      ReportCallbackException(E, ALogical, 'getting stream data');
      Result := 0;
    end;
  end;
end;

procedure TPMLAudioSystem.SafePutData(ALogical: TPMLLogicalAudioDevice; AStream: TPMLAudioStream;
  ABuffer: Pointer; ALen: Integer);
begin
  try
    AStream.PutData(ABuffer, ALen);
  except
    on E: Exception do
      ReportCallbackException(E, ALogical, 'putting stream data');
  end;
end;

procedure TPMLAudioSystem.SafePostmix(ALogical: TPMLLogicalAudioDevice; const ASpec: TPMLAudioSpec;
  ABuffer: PSingle; ALen: Integer);
begin
  try
    ALogical.FPostmix(ALogical, ASpec, ABuffer, ALen);
  except
    on E: Exception do
      ReportCallbackException(E, ALogical, 'the postmix callback');
  end;
end;

{ ---- デバイスのスレッド（再生） ---- }

procedure TPMLAudioSystem.PlaybackThreadSetup(ADevice: TPMLAudioDevice);
begin
  FBackend.ThreadInit(ADevice);
end;

{ SDL_PlaybackAudioThreadIterate。 }
function TPMLAudioSystem.PlaybackThreadIterate(ADevice: TPMLAudioDevice): Boolean;
var
  Failed: Boolean;
  BufferSize, Br, NeededSamples, WorkBufferSize, Channels: Integer;
  DeviceBuffer: PByte;
  FinalMix, MixBuf: PSingle;
  L: TPMLLogicalAudioDevice;
  S: TPMLAudioStream;
  OutSpec: TPMLAudioSpec;
  Fmt: TPMLAudioFormat;
begin
  Failed := False;
  ADevice.Lock.Lock;
  try
    if ADevice.ShutdownFlag.Load <> 0 then
      Exit(False);  // 終わり
    // 失われた印が付いたが、まだ後始末されていない。本物のバックエンドとは話さない。
    if ADevice.Zombie.Load = 1 then
      ADevice.ZombieFunctions := True;

    BufferSize := ADevice.BufferSize;
    DeviceBuffer := DevGetBuf(ADevice, BufferSize);
    Fmt := ADevice.Spec.Format;
    Channels := ADevice.Spec.Channels;
    if BufferSize = 0 then
      // 「今回は飛ばして次に」の意味（WASAPI など）。
    else if DeviceBuffer = nil then
      Failed := True
    else
    begin
      if ADevice.SimpleCopy then
      begin
        // 混ぜずに写すだけでよい（いちばんよくある場合）。
        L := TPMLLogicalAudioDevice(ADevice.LogicalDevices);
        S := L.FBoundStreams;
        if L.FPaused.Load <> 0 then
          Br := 0
        else
          Br := SafeGetData(L, S, DeviceBuffer, BufferSize);
        if Br < BufferSize then
          FillChar(DeviceBuffer[Br], BufferSize - Br, ADevice.SilenceValue);
        // ストリームの出力の並びを変えてあれば、最後にデバイスの並びへ。
        if (Br > 0) and not PMLChannelMapsEqual(Channels, S.OutputChannelMap, ADevice.ChannelMap) then
          PMLConvertAudio(Br div ADevice.Spec.FrameSize, DeviceBuffer, Fmt, Channels, nil,
            DeviceBuffer, Fmt, Channels, ADevice.ChannelMap, nil, Single(1.0));
      end
      else
      begin
        // 混ぜる（か、無音にする）。
        if Fmt = PML_AUDIO_F32 then
          FinalMix := PSingle(DeviceBuffer)
        else
          FinalMix := PSingle(ADevice.MixBuffer);
        NeededSamples := BufferSize div PMLAudioByteSize(Fmt);
        WorkBufferSize := NeededSamples * SizeOf(Single);
        OutSpec := ADevice.Spec;
        OutSpec.Format := PML_AUDIO_F32;
        FillChar(FinalMix^, WorkBufferSize, 0);

        L := TPMLLogicalAudioDevice(ADevice.LogicalDevices);
        while L <> nil do
        begin
          if L.FPaused.Load = 0 then
          begin
            MixBuf := FinalMix;
            if Assigned(L.FPostmix) then
            begin
              MixBuf := ADevice.PostmixBuffer;
              FillChar(MixBuf^, WorkBufferSize, 0);
            end;
            S := L.FBoundStreams;
            while S <> nil do
            begin
              // 結び付けの連なりはデバイスのロックの下でしか変わらない。
              Br := SafeGetData(L, S, ADevice.WorkBuffer, WorkBufferSize);
              if Br > 0 then
              begin
                // D-67: 置き場は F32。SDL はデバイスの形式として並びを入れ替える。
                if not PMLChannelMapsEqual(Channels, S.OutputChannelMap, ADevice.ChannelMap) then
                  PMLConvertAudio(Br div OutSpec.FrameSize, ADevice.WorkBuffer, PML_AUDIO_F32, Channels,
                    nil, ADevice.WorkBuffer, PML_AUDIO_F32, Channels, ADevice.ChannelMap, nil, Single(1.0));
                PMLMixFloat32Audio(MixBuf, PSingle(ADevice.WorkBuffer), Br);
              end;
              S := S.Binding.Next;
            end;
            if Assigned(L.FPostmix) then
            begin
              SafePostmix(L, OutSpec, MixBuf, WorkBufferSize);
              PMLMixFloat32Audio(FinalMix, MixBuf, WorkBufferSize);
            end;
          end;
          L := L.FNext;
        end;

        if PByte(FinalMix) <> DeviceBuffer then
        begin
          // デバイスの置き場が SIMD に合わせて並んでいるとは限らないので、作業の置き場で変換する。
          PMLConvertAudio(NeededSamples div Channels, FinalMix, PML_AUDIO_F32, Channels, nil,
            ADevice.WorkBuffer, Fmt, Channels, nil, nil, Single(1.0));
          Move(ADevice.WorkBuffer^, DeviceBuffer^, BufferSize);
        end;
      end;

      // PlayDevice は待たない（ロックを持っている）。待つのは WaitDevice。
      if not DevPlay(ADevice, DeviceBuffer, BufferSize) then
        Failed := True;
    end;
  finally
    ADevice.Lock.Unlock;
  end;
  if Failed then
    DeviceDisconnected(ADevice);
  Result := True;  // 失敗しても、終わりでなければ続ける
end;

{ SDL_PlaybackAudioThreadShutdown。 }
procedure TPMLAudioSystem.PlaybackThreadShutdown(ADevice: TPMLAudioDevice);
var
  Frames, Delay: Integer;
begin
  Frames := ADevice.BufferSize div ADevice.Spec.FrameSize;
  // 失われていなければ、鳴り終わるのを少し待つ。
  if ADevice.Zombie.Load = 0 then
  begin
    Delay := ((Frames * 1000) div ADevice.Spec.Freq) * 2;
    if Delay > 100 then
      Delay := 100;
    PMLDelay(LongWord(Delay));
  end;
  FBackend.ThreadDeinit(ADevice);
end;

{ ---- デバイスのスレッド（録音） ---- }

procedure TPMLAudioSystem.RecordingThreadSetup(ADevice: TPMLAudioDevice);
begin
  FBackend.ThreadInit(ADevice);
end;

{ SDL_RecordingAudioThreadIterate。 }
function TPMLAudioSystem.RecordingThreadIterate(ADevice: TPMLAudioDevice): Boolean;
var
  Failed: Boolean;
  Br, OutBr, Frames, Channels: Integer;
  L: TPMLLogicalAudioDevice;
  S: TPMLAudioStream;
  OutSpec: TPMLAudioSpec;
  OutBuf, FinalBuf: Pointer;
  OutFormat: TPMLAudioFormat;
  SrcMap: TPMLChannelMap;
begin
  Failed := False;
  ADevice.Lock.Lock;
  try
    if ADevice.ShutdownFlag.Load <> 0 then
      Exit(False);
    if ADevice.Zombie.Load = 1 then
      ADevice.ZombieFunctions := True;

    Channels := ADevice.Spec.Channels;
    if ADevice.LogicalDevices = nil then
      DevFlush(ADevice)  // 誰も欲しがらない。溜まっている分は捨てる
    else
    begin
      // 待たない（ロックを持っている）。待つのは WaitRecordingDevice。
      Br := DevRecord(ADevice, ADevice.WorkBuffer, ADevice.BufferSize);
      if Br < 0 then
        Failed := True
      else if Br > 0 then
      begin
        L := TPMLLogicalAudioDevice(ADevice.LogicalDevices);
        while L <> nil do
        begin
          if L.FPaused.Load = 0 then
          begin
            OutBuf := ADevice.WorkBuffer;
            OutFormat := ADevice.Spec.Format;
            // D-69: 論理デバイスごとのバイト数。SDL は書き換えた br を次の論理デバイスへ持ち越す。
            OutBr := Br;
            if Assigned(L.FPostmix) or (L.FGain <> 1.0) then
            begin
              // F32 にする。
              OutSpec := ADevice.Spec;
              OutSpec.Format := PML_AUDIO_F32;
              OutBuf := ADevice.PostmixBuffer;
              OutFormat := PML_AUDIO_F32;
              Frames := Br div ADevice.Spec.FrameSize;
              OutBr := Frames * OutSpec.FrameSize;
              PMLConvertAudio(Frames, ADevice.WorkBuffer, ADevice.Spec.Format, Channels, nil,
                ADevice.PostmixBuffer, PML_AUDIO_F32, Channels, nil, nil, L.FGain);
              if Assigned(L.FPostmix) then
                SafePostmix(L, OutSpec, ADevice.PostmixBuffer, OutBr);
            end;

            S := L.FBoundStreams;
            while S <> nil do
            begin
              FinalBuf := OutBuf;
              { ストリームの入力の並びを変えてあれば（ふつうはデバイスの並びと同じ）、デバイスの
                並びを外して SDL の決まった並びにしてから渡す。ストリームの並びはストリームが当てる。
                D-67: SDL はここでストリームの並びを当て（ストリームも当てるので 2 度になる）、
                置き場をいつもデバイスの形式として扱う（F32 の置き場の値が壊れる）。 }
              SrcMap := S.InputChannelMap;
              if (Length(ADevice.ChannelMap) > 0)
                and not PMLChannelMapsEqual(Channels, SrcMap, ADevice.ChannelMap) then
              begin
                // 録音では混ぜる置き場を使わないので、ここで借りる。
                FinalBuf := ADevice.MixBuffer;
                PMLConvertAudio(OutBr div (PMLAudioByteSize(OutFormat) * Channels), OutBuf, OutFormat,
                  Channels, ADevice.ChannelMap, FinalBuf, OutFormat, Channels, nil, nil, Single(1.0));
              end;
              SafePutData(L, S, FinalBuf, OutBr);
              S := S.Binding.Next;
            end;
          end;
          L := L.FNext;
        end;
      end;
    end;
  finally
    ADevice.Lock.Unlock;
  end;
  if Failed then
    DeviceDisconnected(ADevice);
  Result := True;
end;

{ SDL_RecordingAudioThreadShutdown。 }
procedure TPMLAudioSystem.RecordingThreadShutdown(ADevice: TPMLAudioDevice);
begin
  DevFlush(ADevice);
  FBackend.ThreadDeinit(ADevice);
end;

initialization
  PMLRegisterAudioStreamDestroyHook(@AudioStreamDestroying);

end.
