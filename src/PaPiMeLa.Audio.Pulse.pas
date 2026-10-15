{
  PaPiMeLa.Audio.Pulse — PulseAudio のオーディオのバックエンド

  Origin : ported from SDL (src/audio/pulseaudio/SDL_pulseaudio.c, SDL_pulseaudio.h)
           Scope: SDL_pulseaudio.c の全体（サーバとの接続、デバイスの列挙、hotplug と既定の変更、
           ストリームを開く・待つ・鳴らす・録る・閉じる、形式の対応、チャンネルの並び）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §9.4、§11 #57

  WHAT:
    PulseAudio（pa_threaded_mainloop）につないで、シンクとソースを物理デバイスとして足し、
    ストリームで再生と録音をする。サーバの変更（追加・削除・既定の変更）はメインループの
    スレッドで知り、hotplug のスレッドが既定の変更を中核へ渡す。デバイススレッドは中核が作る。

  WHY:
    PipeWire が無い環境（PulseAudio のサーバ）で鳴らすため。PipeWire のサーバは pipewire-pulse で
    PulseAudio のサーバとしても動くので、優先度は PipeWire の次。

  RESOLVED:
    - SDL の静的な変数（メインループ、コンテキスト、既定の経路など）は、バックエンドのフィールドに置く
    - SDL_FindPhysicalAudioDeviceByCallback は無いので、バックエンドが自分のハンドルの表を持ち
      （デバイスの番号と向きで引く）、中核の FindDeviceByHandle で本物のデバイスにする。
      ハンドルは FreeDeviceHandle まで生きる
    - コールバックの例外は握りつぶさず、最後の誤りとして覚えてログに残す（C へ例外を戻さない）
    - 浮動小数点の例外: メインループのスレッドを作る間は呼んだスレッドの例外を止める
      （PMLPulseMaskBegin）。コールバックの入口でも止める。hotplug のスレッドも始めに止める

  PORT-NOTE(bug):
    SDL の HotplugCallback は、削除の知らせを「番号だけ」で探す。シンクとソースは番号の空間が別
    （どちらも 0 から数える）なので、番号が重なるとき、別の向きのデバイスを切り離してしまう疑いがある。
    papimela は向き（再生か録音か）も見る。

  NOT RESOLVED:
    - 録音は手元の検査に入れていない（手元の機械に録音の装置が無い）。コードは SDL のとおりに写した

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Audio.Pulse;

{$I papimela.inc}

interface

uses
  SysUtils, Classes, ctypes,
  PaPiMeLa.Errors,
  PaPiMeLa.Atomic,
  PaPiMeLa.Threading,
  PaPiMeLa.Log,
  PaPiMeLa.Properties,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Platform.Pulse,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Backend;

type
  TPMLPulseAudioBackend = class;

  { PulseDeviceHandle。物理デバイスの Handle（このオブジェクトのポインタ）。 }
  TPulseDeviceHandle = class
  public
    DevicePath : String;     // シンク・ソースの名前（接続先）
    DeviceIndex: LongWord;
    Recording  : Boolean;
  end;

  { SDL_PrivateAudioData。 }
  TPulseDeviceData = class
  public
    Backend       : TPMLPulseAudioBackend;
    Stream        : PPAStream;
    MixBuf        : PByte;
    BytesRequested: SizeUInt;
    RecordingBuf  : PByte;      // 読みかけの断片（pa_stream_peek が返したもの）
    RecordingLen  : SizeInt;
    destructor Destroy; override;
  end;

  TPMLPulseAudioBackend = class(TPMLAudioBackend)
  private
    FPulse: TPMLPulse;
    FMainloop: PPAThreadedMainloop;
    FContext: PPAContext;
    FIncludeMonitors: Boolean;
    FHotplugThread: TPMLThread;
    FHotplugActive: TPMLAtomicInt;
    FDefaultSinkPath: String;
    FDefaultSourcePath: String;
    FDefaultSinkChanged: Boolean;
    FDefaultSourceChanged: Boolean;
    FHandleLock: TPMLMutex;
    FHandles: array of TPulseDeviceHandle;
    FLastError: String;
    procedure Lock; inline;
    procedure Unlock; inline;
    procedure WaitLoop; inline;
    procedure WaitForOperation(AOp: PPAOperation);
    procedure Disconnect;
    procedure Connect;
    procedure HandlesAdd(AHandle: TPulseDeviceHandle);
    procedure HandlesRemove(AHandle: TPulseDeviceHandle);
    function  FindByIndex(AIndex: LongWord; ARecording: Boolean): TPMLAudioDevice;
    function  FindByPath(const APath: String; ARecording: Boolean): TPMLAudioDevice;
    function  CheckDefaultDevice(AChanged: Boolean; const APath: String; ARecording: Boolean): Boolean;
    procedure HotplugRun(AReady: TPMLSemaphore);
  public
    constructor Create(ACore: TPMLAudioCore); override;
    destructor Destroy; override;
    function  Name: String; override;
    procedure DetectDevices(out ADefaultPlayback, ADefaultRecording: TPMLAudioDevice); override;
    function  OpenDevice(ADevice: TPMLAudioDevice): Boolean; override;
    function  WaitDevice(ADevice: TPMLAudioDevice): Boolean; override;
    function  PlayDevice(ADevice: TPMLAudioDevice; ABuffer: PByte; ALen: Integer): Boolean; override;
    function  GetDeviceBuf(ADevice: TPMLAudioDevice; var ASize: Integer): PByte; override;
    function  WaitRecordingDevice(ADevice: TPMLAudioDevice): Boolean; override;
    function  RecordDevice(ADevice: TPMLAudioDevice; ABuffer: Pointer; ALen: Integer): Integer; override;
    procedure FlushRecording(ADevice: TPMLAudioDevice); override;
    procedure CloseDevice(ADevice: TPMLAudioDevice); override;
    procedure InterruptDevice(ADevice: TPMLAudioDevice); override;
    procedure FreeDeviceHandle(ADevice: TPMLAudioDevice); override;
    procedure DeinitializeStart; override;
    procedure Deinitialize; override;
    // コールバックの中から呼ぶ（ロックを持っている側）。
    procedure Signal;
    procedure AddPulseDevice(ARecording: Boolean; const ADescription, AName: String;
      AIndex: LongWord; const ASpec: TPASampleSpec);
    procedure NoteError(E: Exception; const AWhere: String);
    procedure ServerInfo(AInfo: PPAServerInfo);
    procedure Hotplug(AEvent: cint; AIndex: LongWord);
    // コールバックで捕まえた最後の誤り（検査用）。
    property  LastError: String read FLastError;
  end;

implementation

type
  // hotplug のスレッド（SDL の HotplugThread）。
  TPulseHotplugThread = class(TPMLThread)
  private
    FBackend: TPMLPulseAudioBackend;
    FReady: TPMLSemaphore;
  protected
    function Run: Integer; override;
  public
    constructor Create(ABackend: TPMLPulseAudioBackend; AReady: TPMLSemaphore);
  end;

destructor TPulseDeviceData.Destroy;
begin
  if MixBuf <> nil then
    FreeMem(MixBuf);
  inherited Destroy;
end;

const
  // SDL のチャンネルの並び（SDL_Audio.h の順）に合わせた PulseAudio の位置。
  PulseMap1: array[0..0] of cint = (PA_CHANNEL_POSITION_MONO);
  PulseMap2: array[0..1] of cint = (PA_CHANNEL_POSITION_FRONT_LEFT, PA_CHANNEL_POSITION_FRONT_RIGHT);
  PulseMap3: array[0..2] of cint = (PA_CHANNEL_POSITION_FRONT_LEFT, PA_CHANNEL_POSITION_FRONT_RIGHT,
    PA_CHANNEL_POSITION_LFE);
  PulseMap4: array[0..3] of cint = (PA_CHANNEL_POSITION_FRONT_LEFT, PA_CHANNEL_POSITION_FRONT_RIGHT,
    PA_CHANNEL_POSITION_REAR_LEFT, PA_CHANNEL_POSITION_REAR_RIGHT);
  PulseMap5: array[0..4] of cint = (PA_CHANNEL_POSITION_FRONT_LEFT, PA_CHANNEL_POSITION_FRONT_RIGHT,
    PA_CHANNEL_POSITION_LFE, PA_CHANNEL_POSITION_REAR_LEFT, PA_CHANNEL_POSITION_REAR_RIGHT);
  PulseMap6: array[0..5] of cint = (PA_CHANNEL_POSITION_FRONT_LEFT, PA_CHANNEL_POSITION_FRONT_RIGHT,
    PA_CHANNEL_POSITION_FRONT_CENTER, PA_CHANNEL_POSITION_LFE, PA_CHANNEL_POSITION_REAR_LEFT,
    PA_CHANNEL_POSITION_REAR_RIGHT);
  PulseMap7: array[0..6] of cint = (PA_CHANNEL_POSITION_FRONT_LEFT, PA_CHANNEL_POSITION_FRONT_RIGHT,
    PA_CHANNEL_POSITION_FRONT_CENTER, PA_CHANNEL_POSITION_LFE, PA_CHANNEL_POSITION_REAR_CENTER,
    PA_CHANNEL_POSITION_SIDE_LEFT, PA_CHANNEL_POSITION_SIDE_RIGHT);
  PulseMap8: array[0..7] of cint = (PA_CHANNEL_POSITION_FRONT_LEFT, PA_CHANNEL_POSITION_FRONT_RIGHT,
    PA_CHANNEL_POSITION_FRONT_CENTER, PA_CHANNEL_POSITION_LFE, PA_CHANNEL_POSITION_REAR_LEFT,
    PA_CHANNEL_POSITION_REAR_RIGHT, PA_CHANNEL_POSITION_SIDE_LEFT, PA_CHANNEL_POSITION_SIDE_RIGHT);

{ PulseCreateChannelMap。 }
procedure PulseCreateChannelMap(var AMap: TPAChannelMap; AChannels: Integer);
begin
  AMap.Channels := cuint8(AChannels);
  case AChannels of
    1: Move(PulseMap1, AMap.Map, SizeOf(PulseMap1));
    2: Move(PulseMap2, AMap.Map, SizeOf(PulseMap2));
    3: Move(PulseMap3, AMap.Map, SizeOf(PulseMap3));
    4: Move(PulseMap4, AMap.Map, SizeOf(PulseMap4));
    5: Move(PulseMap5, AMap.Map, SizeOf(PulseMap5));
    6: Move(PulseMap6, AMap.Map, SizeOf(PulseMap6));
    7: Move(PulseMap7, AMap.Map, SizeOf(PulseMap7));
    8: Move(PulseMap8, AMap.Map, SizeOf(PulseMap8));
  end;
end;

{ PulseFormatToSDLFormat。 }
function PulseFormatToPML(AFormat: cint): TPMLAudioFormat;
begin
  case AFormat of
    PA_SAMPLE_U8: Result := PML_AUDIO_U8;
    PA_SAMPLE_S16LE: Result := PML_AUDIO_S16LE;
    PA_SAMPLE_S16BE: Result := PML_AUDIO_S16BE;
    PA_SAMPLE_S32LE: Result := PML_AUDIO_S32LE;
    PA_SAMPLE_S32BE: Result := PML_AUDIO_S32BE;
    PA_SAMPLE_FLOAT32LE: Result := PML_AUDIO_F32LE;
    PA_SAMPLE_FLOAT32BE: Result := PML_AUDIO_F32BE;
  else
    Result := PML_AUDIO_UNKNOWN;
  end;
end;

{ PML の形式から PulseAudio の形式。扱えなければ PA_SAMPLE_INVALID（S8 など）。 }
function PMLFormatToPulse(AFormat: TPMLAudioFormat): cint;
begin
  case AFormat of
    PML_AUDIO_U8: Result := PA_SAMPLE_U8;
    PML_AUDIO_S16LE: Result := PA_SAMPLE_S16LE;
    PML_AUDIO_S16BE: Result := PA_SAMPLE_S16BE;
    PML_AUDIO_S32LE: Result := PA_SAMPLE_S32LE;
    PML_AUDIO_S32BE: Result := PA_SAMPLE_S32BE;
    PML_AUDIO_F32LE: Result := PA_SAMPLE_FLOAT32LE;
    PML_AUDIO_F32BE: Result := PA_SAMPLE_FLOAT32BE;
  else
    Result := PA_SAMPLE_INVALID;
  end;
end;

{ ---- コールバック（PulseAudio のスレッドから。AUserData は説明のとおり） ---- }

procedure OperationStateChangeCallback(AOp: PPAOperation; AUserData: Pointer); cdecl;
begin
  PMLPulseCallbackEnter;
  // 待っているところに知らせるだけ。詳しくは待つ側が調べる。
  TPMLPulseAudioBackend(AUserData).Signal;
end;

procedure ContextStateChangeCallback(AContext: PPAContext; AUserData: Pointer); cdecl;
begin
  PMLPulseCallbackEnter;
  TPMLPulseAudioBackend(AUserData).Signal;
end;

{ AUserData はバックエンド。デバイスの中身にしてはいけない: pa_stream_disconnect は終わりの返事が
  来るまでストリームを内部で持ち続け、そのとき状態の知らせを出すので、CloseDevice で中身を解放した後に
  呼ばれることがある（SDL は知らせが userdata を使わないので起きない）。 }
procedure StreamStateChangeCallback(AStream: PPAStream; AUserData: Pointer); cdecl;
begin
  PMLPulseCallbackEnter;
  TPMLPulseAudioBackend(AUserData).Signal;
end;

procedure WriteCallback(AStream: PPAStream; ANBytes: csize_t; AUserData: Pointer); cdecl;
var
  D: TPulseDeviceData;
begin
  PMLPulseCallbackEnter;
  D := TPulseDeviceData(AUserData);
  Inc(D.BytesRequested, ANBytes);
  D.Backend.Signal;
end;

procedure ReadCallback(AStream: PPAStream; ANBytes: csize_t; AUserData: Pointer); cdecl;
begin
  PMLPulseCallbackEnter;
  // 録音の側は必要な量を自分で調べる。待っているところに知らせるだけ。
  TPulseDeviceData(AUserData).Backend.Signal;
end;

procedure SinkInfoCallback(AContext: PPAContext; AInfo: PPASinkInfo; AEol: cint; AUserData: Pointer); cdecl;
var
  B: TPMLPulseAudioBackend;
begin
  PMLPulseCallbackEnter;
  B := TPMLPulseAudioBackend(AUserData);
  try
    if AInfo <> nil then
      B.AddPulseDevice(False, StrPas(AInfo^.Description), StrPas(AInfo^.Name), AInfo^.Index, AInfo^.SampleSpec);
  except
    on E: Exception do
      B.NoteError(E, 'sink info');
  end;
  B.Signal;
end;

procedure SourceInfoCallback(AContext: PPAContext; AInfo: PPASourceInfo; AEol: cint; AUserData: Pointer); cdecl;
var
  B: TPMLPulseAudioBackend;
begin
  PMLPulseCallbackEnter;
  B := TPMLPulseAudioBackend(AUserData);
  try
    // 「モニター」のソース（ほかのシンクの出力）は、求められたときだけ入れる。
    if (AInfo <> nil) and (B.FIncludeMonitors or (AInfo^.MonitorOfSink = PA_INVALID_INDEX)) then
      B.AddPulseDevice(True, StrPas(AInfo^.Description), StrPas(AInfo^.Name), AInfo^.Index, AInfo^.SampleSpec);
  except
    on E: Exception do
      B.NoteError(E, 'source info');
  end;
  B.Signal;
end;

procedure ServerInfoCallback(AContext: PPAContext; AInfo: PPAServerInfo; AUserData: Pointer); cdecl;
var
  B: TPMLPulseAudioBackend;
begin
  PMLPulseCallbackEnter;
  B := TPMLPulseAudioBackend(AUserData);
  try
    // SDL は AInfo をそのまま読む。エラーのとき nil で来る可能性があるので守る。
    if AInfo <> nil then
      B.ServerInfo(AInfo);
  except
    on E: Exception do
      B.NoteError(E, 'server info');
  end;
  B.Signal;
end;

procedure HotplugCallback(AContext: PPAContext; AEvent: cint; AIndex: cuint32; AUserData: Pointer); cdecl;
var
  B: TPMLPulseAudioBackend;
begin
  PMLPulseCallbackEnter;
  B := TPMLPulseAudioBackend(AUserData);
  try
    B.Hotplug(AEvent, AIndex);
  except
    on E: Exception do
      B.NoteError(E, 'hotplug');
  end;
  B.Signal;
end;

{ ---- バックエンド ---- }

procedure TPMLPulseAudioBackend.NoteError(E: Exception; const AWhere: String);
begin
  FLastError := AWhere + ': ' + E.ClassName + ': ' + E.Message;
  if (ContextServices <> nil) and (ContextServices.Log <> nil) then
    ContextServices.Log.Error(PML_LOG_CATEGORY_AUDIO, 'pulseaudio: ' + FLastError);
end;

procedure TPMLPulseAudioBackend.Lock;
begin
  FPulse.API.threaded_mainloop_lock(FMainloop);
end;

procedure TPMLPulseAudioBackend.Unlock;
begin
  FPulse.API.threaded_mainloop_unlock(FMainloop);
end;

procedure TPMLPulseAudioBackend.WaitLoop;
begin
  FPulse.API.threaded_mainloop_wait(FMainloop);
end;

procedure TPMLPulseAudioBackend.Signal;
begin
  FPulse.API.threaded_mainloop_signal(FMainloop, 0);
end;

{ WaitForPulseOperation。メインループのロックを持って呼ぶ。操作は中で unref する。 }
procedure TPMLPulseAudioBackend.WaitForOperation(AOp: PPAOperation);
begin
  if AOp = nil then
    Exit;
  // 古い PulseAudio（4.0 より前）には無い。その場合は操作のコールバックが知らせる前提
  if Assigned(FPulse.API.operation_set_state_callback) then
    FPulse.API.operation_set_state_callback(AOp, @OperationStateChangeCallback, Self);
  while FPulse.API.operation_get_state(AOp) = PA_OPERATION_RUNNING do
    WaitLoop;   // ロックを手放して、内部の条件変数で待つ
  FPulse.API.operation_unref(AOp);
end;

{ DisconnectFromPulseServer。 }
procedure TPMLPulseAudioBackend.Disconnect;
begin
  if FMainloop <> nil then
    FPulse.API.threaded_mainloop_stop(FMainloop);
  if FContext <> nil then
  begin
    FPulse.API.context_disconnect(FContext);
    FPulse.API.context_unref(FContext);
    FContext := nil;
  end;
  if FMainloop <> nil then
  begin
    FPulse.API.threaded_mainloop_free(FMainloop);
    FMainloop := nil;
  end;
end;

{ ConnectToPulseServer。失敗は EPMLAudioError。 }
procedure TPMLPulseAudioBackend.Connect;
var
  Api: PPAMainloopAPI;
  Proplist: PPAProplist;
  AppName, IconName, Failure: String;
  State: cint;
  Old: TFPUExceptionMask;
begin
  FMainloop := FPulse.API.threaded_mainloop_new();
  if FMainloop = nil then
    raise EPMLAudioError.Create('pa_threaded_mainloop_new() failed');

  if Assigned(FPulse.API.threaded_mainloop_set_name) then
    FPulse.API.threaded_mainloop_set_name(FMainloop, 'PulseMainloop');

  // ここで作られるメインループのスレッドが、例外を止めた設定を受け継ぐように。
  Old := PMLPulseMaskBegin;
  try
    if FPulse.API.threaded_mainloop_start(FMainloop) < 0 then
    begin
      FPulse.API.threaded_mainloop_free(FMainloop);
      FMainloop := nil;
      raise EPMLAudioError.Create('pa_threaded_mainloop_start() failed');
    end;
  finally
    PMLPulseMaskEnd(Old);
  end;

  Failure := '';
  Proplist := nil;
  Lock;
  try
    Api := FPulse.API.threaded_mainloop_get_api(FMainloop);
    Proplist := FPulse.API.proplist_new();
    if Proplist = nil then
      Failure := 'pa_proplist_new() failed'
    else
    begin
      IconName := FCore.Hint(PML_HINT_AUDIO_DEVICE_APP_ICON_NAME);
      if IconName = '' then
        IconName := 'applications-games';
      FPulse.API.proplist_sets(Proplist, PA_PROP_APPLICATION_ICON_NAME, PChar(IconName));

      AppName := FCore.Hint(PML_HINT_APP_NAME);
      if AppName = '' then
        AppName := ApplicationName;
      if AppName = '' then
        AppName := 'papimela Application';
      FContext := FPulse.API.context_new_with_proplist(Api, PChar(AppName), Proplist);
      if FContext = nil then
        Failure := 'pa_context_new_with_proplist() failed';
    end;
    if Proplist <> nil then
      FPulse.API.proplist_free(Proplist);

    if Failure = '' then
    begin
      FPulse.API.context_set_state_callback(FContext, @ContextStateChangeCallback, Self);
      // サーバにつなぐ
      if FPulse.API.context_connect(FContext, nil, PA_CONTEXT_NOFLAGS, nil) < 0 then
        Failure := 'Could not setup connection to PulseAudio'
      else
      begin
        State := FPulse.API.context_get_state(FContext);
        while PMLPulseContextIsGood(State) and (State <> PA_CONTEXT_READY) do
        begin
          WaitLoop;
          State := FPulse.API.context_get_state(FContext);
        end;
        if State <> PA_CONTEXT_READY then
          Failure := 'Could not connect to PulseAudio';
      end;
    end;
  finally
    Unlock;
  end;

  if Failure <> '' then
  begin
    Disconnect;
    raise EPMLAudioError.Create(Failure);
  end;
end;

constructor TPMLPulseAudioBackend.Create(ACore: TPMLAudioCore);
begin
  inherited Create(ACore);
  FHandleLock := TPMLMutex.Create;
  FPulse := TPMLPulse.Create;   // 無ければ EPMLPlatformLibrary（次のバックエンドへ）
  Connect;
  FIncludeMonitors := PMLStringBoolean(FCore.Hint(PML_HINT_AUDIO_INCLUDE_MONITORS), False);
  FCapabilities := [TPMLAudioBackendCapability.HasRecordingSupport];
end;

destructor TPMLPulseAudioBackend.Destroy;
var
  I: Integer;
begin
  if FHotplugThread <> nil then
    DeinitializeStart;
  if FPulse <> nil then
  begin
    Disconnect;
    FreeAndNil(FPulse);
  end;
  for I := 0 to High(FHandles) do
    FHandles[I].Free;
  FHandles := nil;
  FHandleLock.Free;
  inherited Destroy;
end;

function TPMLPulseAudioBackend.Name: String;
begin
  Result := 'pulseaudio';
end;

{ ---- ハンドルの表 ---- }

procedure TPMLPulseAudioBackend.HandlesAdd(AHandle: TPulseDeviceHandle);
begin
  FHandleLock.Lock;
  try
    SetLength(FHandles, Length(FHandles) + 1);
    FHandles[High(FHandles)] := AHandle;
  finally
    FHandleLock.Unlock;
  end;
end;

procedure TPMLPulseAudioBackend.HandlesRemove(AHandle: TPulseDeviceHandle);
var
  I, J: Integer;
begin
  FHandleLock.Lock;
  try
    for I := 0 to High(FHandles) do
      if FHandles[I] = AHandle then
      begin
        for J := I to High(FHandles) - 1 do
          FHandles[J] := FHandles[J + 1];
        SetLength(FHandles, Length(FHandles) - 1);
        Break;
      end;
  finally
    FHandleLock.Unlock;
  end;
end;

function TPMLPulseAudioBackend.FindByIndex(AIndex: LongWord; ARecording: Boolean): TPMLAudioDevice;
var
  I: Integer;
  H: TPulseDeviceHandle;
begin
  H := nil;
  FHandleLock.Lock;
  try
    for I := 0 to High(FHandles) do
      if (FHandles[I].DeviceIndex = AIndex) and (FHandles[I].Recording = ARecording) then
      begin
        H := FHandles[I];
        Break;
      end;
  finally
    FHandleLock.Unlock;
  end;
  if H = nil then
    Exit(nil);
  Result := FCore.FindDeviceByHandle(H);
end;

function TPMLPulseAudioBackend.FindByPath(const APath: String; ARecording: Boolean): TPMLAudioDevice;
var
  I: Integer;
  H: TPulseDeviceHandle;
begin
  H := nil;
  FHandleLock.Lock;
  try
    for I := 0 to High(FHandles) do
      if (FHandles[I].DevicePath = APath) and (FHandles[I].Recording = ARecording) then
      begin
        H := FHandles[I];
        Break;
      end;
  finally
    FHandleLock.Unlock;
  end;
  if H = nil then
    Exit(nil);
  Result := FCore.FindDeviceByHandle(H);
end;

{ AddPulseAudioDevice。 }
procedure TPMLPulseAudioBackend.AddPulseDevice(ARecording: Boolean; const ADescription, AName: String;
  AIndex: LongWord; const ASpec: TPASampleSpec);
var
  Spec: TPMLAudioSpec;
  H: TPulseDeviceHandle;
begin
  Spec.Format := PulseFormatToPML(ASpec.Format);
  Spec.Channels := ASpec.Channels;
  Spec.Freq := Integer(ASpec.Rate);
  H := TPulseDeviceHandle.Create;
  H.DevicePath := AName;
  H.DeviceIndex := AIndex;
  H.Recording := ARecording;
  HandlesAdd(H);
  // 終わりかけで足せなければ（nil）、ハンドルも捨てる
  if FCore.AddDevice(ARecording, ADescription, '', Spec, H) = nil then
  begin
    HandlesRemove(H);
    H.Free;
  end;
end;

{ ServerInfoCallback の中身。既定のシンクとソースの名前が変わったら覚えて印を付ける。 }
procedure TPMLPulseAudioBackend.ServerInfo(AInfo: PPAServerInfo);
var
  S: String;
begin
  S := StrPas(AInfo^.DefaultSinkName);
  if (FDefaultSinkPath = '') or (FDefaultSinkPath <> S) then
  begin
    FDefaultSinkPath := S;
    FDefaultSinkChanged := True;
  end;
  S := StrPas(AInfo^.DefaultSourceName);
  if (FDefaultSourcePath = '') or (FDefaultSourcePath <> S) then
  begin
    FDefaultSourcePath := S;
    FDefaultSourceChanged := True;
  end;
end;

{ HotplugCallback の中身（追加・削除・変更）。 }
procedure TPMLPulseAudioBackend.Hotplug(AEvent: cint; AIndex: LongWord);
var
  Added, Removed, Changed, Sink, Source: Boolean;
  Dev: TPMLAudioDevice;
begin
  Added := (AEvent and PA_SUBSCRIPTION_EVENT_TYPE_MASK) = PA_SUBSCRIPTION_EVENT_NEW;
  Removed := (AEvent and PA_SUBSCRIPTION_EVENT_TYPE_MASK) = PA_SUBSCRIPTION_EVENT_REMOVE;
  Changed := (AEvent and PA_SUBSCRIPTION_EVENT_TYPE_MASK) = PA_SUBSCRIPTION_EVENT_CHANGE;
  if not (Added or Removed or Changed) then
    Exit;
  Sink := (AEvent and PA_SUBSCRIPTION_EVENT_FACILITY_MASK) = PA_SUBSCRIPTION_EVENT_SINK;
  Source := (AEvent and PA_SUBSCRIPTION_EVENT_FACILITY_MASK) = PA_SUBSCRIPTION_EVENT_SOURCE;

  if Changed then
    FPulse.API.operation_unref(FPulse.API.context_get_server_info(FContext, @ServerInfoCallback, Self));

  { 追加には、サーバからシンクの詳細がいる。また別のコールバック（操作はすぐ unref する。
    待たないし、コールバックが仕事をするので、それが終われば解放される）。 }
  if Added and Sink then
    FPulse.API.operation_unref(FPulse.API.context_get_sink_info_by_index(FContext, AIndex, @SinkInfoCallback, Self))
  else if Added and Source then
    FPulse.API.operation_unref(FPulse.API.context_get_source_info_by_index(FContext, AIndex, @SourceInfoCallback, Self))
  else if Removed and (Sink or Source) then
  begin
    // 削除は番号だけで分かる。向きも見る（ファイルの先頭の PORT-NOTE）
    Dev := FindByIndex(AIndex, Source);
    if Dev <> nil then
      FCore.DeviceDisconnected(Dev);
  end;
end;

{ CheckDefaultDevice。直したら False、まだなら True（あとでもう一度）。 }
function TPMLPulseAudioBackend.CheckDefaultDevice(AChanged: Boolean; const APath: String;
  ARecording: Boolean): Boolean;
var
  Dev: TPMLAudioDevice;
begin
  if not AChanged then
    Exit(False);   // 何も起きていない。印は変わっていないまま
  if APath = '' then
    Exit(True);    // 名前がまだ無い。あとで見る
  Dev := FindByPath(APath, ARecording);
  if Dev <> nil then
  begin
    FCore.DefaultDeviceChanged(Dev);
    Exit(False);
  end;
  // 見つからない。SinkInfoCallback などをまだ待っているのかもしれない。あとでもう一度
  Result := True;
end;

{ ---- hotplug のスレッド ---- }

constructor TPulseHotplugThread.Create(ABackend: TPMLPulseAudioBackend; AReady: TPMLSemaphore);
begin
  inherited Create('PulseHotplug', True);
  FBackend := ABackend;
  FReady := AReady;
end;

function TPulseHotplugThread.Run: Integer;
begin
  FBackend.HotplugRun(FReady);
  Result := 0;
end;

procedure TPMLPulseAudioBackend.HotplugRun(AReady: TPMLSemaphore);
var
  Op: PPAOperation;
  CheckSink, CheckSource: Boolean;
  CurSink, CurSource: String;
begin
  // C のライブラリを呼ぶので、このスレッドの例外も止める
  PMLPulseMaskBegin;
  FCore.SetCurrentThreadPriority(TPMLThreadPriority.Low);
  Lock;
  FPulse.API.context_set_subscribe_callback(FContext, @HotplugCallback, Self);

  { 購読の操作は待たない。終われば hotplug の知らせが届くようになるが、待っても何も変わらない。 }
  Op := FPulse.API.context_subscribe(FContext,
    PA_SUBSCRIPTION_MASK_SINK or PA_SUBSCRIPTION_MASK_SOURCE or PA_SUBSCRIPTION_MASK_SERVER, nil, nil);

  AReady.Signal;

  while FHotplugActive.Load <> 0 do
  begin
    WaitLoop;
    if (Op <> nil) and (FPulse.API.operation_get_state(Op) <> PA_OPERATION_RUNNING) then
    begin
      FPulse.API.operation_unref(Op);
      Op := nil;
    end;

    // 既定の更新。中核を呼ぶ間はメインループのロックを手放す（再生中のデバイスが待つロックと
    // 逆の順に取って、デッドロックしないように）
    CheckSink := FDefaultSinkChanged;
    CheckSource := FDefaultSourceChanged;
    CurSink := '';
    CurSource := '';
    if CheckSink then
      CurSink := FDefaultSinkPath;
    if CheckSource then
      CurSource := FDefaultSourcePath;
    FDefaultSinkChanged := False;
    FDefaultSourceChanged := False;
    Unlock;
    try
      CheckSink := CheckDefaultDevice(CheckSink, CurSink, False);
      CheckSource := CheckDefaultDevice(CheckSource, CurSource, True);
    except
      on E: Exception do
      begin
        NoteError(E, 'default device');
        CheckSink := False;
        CheckSource := False;
      end;
    end;
    Lock;

    // 直せなかった、またはロックを手放している間にまた変わった印は、立てておく
    FDefaultSinkChanged := FDefaultSinkChanged or CheckSink;
    FDefaultSourceChanged := FDefaultSourceChanged or CheckSource;
  end;

  if Op <> nil then
    FPulse.API.operation_unref(Op);
  FPulse.API.context_set_subscribe_callback(FContext, nil, nil);
  Unlock;
end;

procedure TPMLPulseAudioBackend.DetectDevices(out ADefaultPlayback, ADefaultRecording: TPMLAudioDevice);
var
  Ready: TPMLSemaphore;
  Thr: TPulseHotplugThread;
begin
  Ready := TPMLSemaphore.Create(0);
  try
    Lock;
    try
      WaitForOperation(FPulse.API.context_get_server_info(FContext, @ServerInfoCallback, Self));
      WaitForOperation(FPulse.API.context_get_sink_info_list(FContext, @SinkInfoCallback, Self));
      WaitForOperation(FPulse.API.context_get_source_info_list(FContext, @SourceInfoCallback, Self));
    finally
      Unlock;
    end;

    ADefaultPlayback := nil;
    ADefaultRecording := nil;
    if FDefaultSinkPath <> '' then
      ADefaultPlayback := FindByPath(FDefaultSinkPath, False);
    if FDefaultSourcePath <> '' then
      ADefaultRecording := FindByPath(FDefaultSourcePath, True);

    // 一覧ができた。hotplug の通知を始める
    FHotplugActive.Exchange(1);
    Thr := TPulseHotplugThread.Create(Self, Ready);
    FHotplugThread := Thr;
    Thr.Start;
    Ready.Wait;   // スレッドが主のループに入るまで待つ
  finally
    Ready.Free;
  end;
end;

{ ---- デバイスを開く ---- }

{ PULSEAUDIO_OpenDevice。形式は近いものに変えてよい。失敗は EPMLAudioError。 }
function TPMLPulseAudioBackend.OpenDevice(ADevice: TPMLAudioDevice): Boolean;
var
  Recording: Boolean;
  Data: TPulseDeviceData;
  Handle: TPulseDeviceHandle;
  Formats: TPMLAudioFormats;
  I, PAFormat, Rc, State: Integer;
  TestFormat: TPMLAudioFormat;
  PASpec: TPASampleSpec;
  PAAttr: TPABufferAttr;
  PAMap: TPAChannelMap;
  Flags: cint;
  StreamName: String;
  Actual: PPABufferAttr;
  Failure: String;
begin
  Recording := ADevice.Recording;
  Data := TPulseDeviceData.Create;
  Data.Backend := Self;
  ADevice.Hidden := Data;
  Handle := TPulseDeviceHandle(ADevice.Handle);

  // 近い形式から試す
  PAFormat := PA_SAMPLE_INVALID;
  TestFormat := PML_AUDIO_UNKNOWN;
  Formats := PMLClosestAudioFormats(ADevice.Spec.Format);
  for I := 0 to High(Formats) do
  begin
    PAFormat := PMLFormatToPulse(Formats[I]);
    if PAFormat <> PA_SAMPLE_INVALID then
    begin
      TestFormat := Formats[I];
      Break;
    end;
  end;
  if TestFormat = PML_AUDIO_UNKNOWN then
    raise EPMLAudioError.Create('pulseaudio: Unsupported audio format');
  ADevice.Spec.Format := TestFormat;
  PASpec.Format := PAFormat;

  // この仕様の最終的な値（BufferSize など）を決める
  FCore.UpdatedDeviceFormat(ADevice);

  // 混ぜる置き場
  if not Recording then
  begin
    Data.MixBuf := GetMem(ADevice.BufferSize);
    FillChar(Data.MixBuf^, ADevice.BufferSize, ADevice.SilenceValue);
  end;

  PASpec.Channels := cuint8(ADevice.Spec.Channels);
  PASpec.Rate := cuint32(ADevice.Spec.Freq);

  { 先読みを既定より減らす。fragsize は名前に反して録音のデバイスだけが使う（PulseAudio の説明）。
    2 倍なのは、バッファより「多く」サーバから一度に送ってもらうとドライバによっては楽だから。 }
  PAAttr.FragSize := cuint32(ADevice.BufferSize * 2);
  PAAttr.TLength := cuint32(ADevice.BufferSize);
  PAAttr.PreBuf := cuint32(-1);
  PAAttr.MaxLength := cuint32(-1);
  PAAttr.MinReq := cuint32(-1);
  Flags := PA_STREAM_ADJUST_LATENCY;

  FillChar(PAMap, SizeOf(PAMap), 0);
  PulseCreateChannelMap(PAMap, ADevice.Spec.Channels);

  Failure := '';
  Lock;
  try
    StreamName := FCore.Hint(PML_HINT_AUDIO_DEVICE_STREAM_NAME);
    if StreamName = '' then
      StreamName := 'Audio Stream';
    Data.Stream := FPulse.API.stream_new(FContext, PChar(StreamName), @PASpec, @PAMap);
    if Data.Stream = nil then
      Failure := 'Could not set up PulseAudio stream'
    else
    begin
      FPulse.API.stream_set_state_callback(Data.Stream, @StreamStateChangeCallback, Self);

      { SDL はデバイスの移動を自分で管理するので、PulseAudio に勝手に動かさせない（PA_STREAM_DONT_MOVE）
        ことも考えたが、アプリの外の道具（pavucontrol など）で動かしたい人のために付けていない。 }
      if Recording then
      begin
        FPulse.API.stream_set_read_callback(Data.Stream, @ReadCallback, Data);
        Rc := FPulse.API.stream_connect_record(Data.Stream, PChar(Handle.DevicePath), @PAAttr, Flags);
      end
      else
      begin
        FPulse.API.stream_set_write_callback(Data.Stream, @WriteCallback, Data);
        Rc := FPulse.API.stream_connect_playback(Data.Stream, PChar(Handle.DevicePath), @PAAttr, Flags, nil, nil);
      end;

      if Rc < 0 then
        Failure := 'Could not connect PulseAudio stream'
      else
      begin
        State := FPulse.API.stream_get_state(Data.Stream);
        while PMLPulseStreamIsGood(State) and (State <> PA_STREAM_READY) do
        begin
          WaitLoop;
          State := FPulse.API.stream_get_state(Data.Stream);
        end;

        if not PMLPulseStreamIsGood(State) then
          Failure := 'Could not connect PulseAudio stream'
        else
        begin
          Actual := FPulse.API.stream_get_buffer_attr(Data.Stream);
          if Actual = nil then
            Failure := 'Could not determine connected PulseAudio stream''s buffer attributes'
          else
          begin
            if Recording then
              ADevice.BufferSize := Integer(Actual^.FragSize)
            else
              ADevice.BufferSize := Integer(Actual^.TLength);
            ADevice.SampleFrames := ADevice.BufferSize div ADevice.Spec.FrameSize;
          end;
        end;
      end;
    end;
  finally
    Unlock;
  end;

  if Failure <> '' then
    raise EPMLAudioError.Create(Failure);
  Result := True;
end;

{ ---- 再生 ---- }

{ 次の 1 回分を書けるまで待つ。 }
function TPMLPulseAudioBackend.WaitDevice(ADevice: TPMLAudioDevice): Boolean;
var
  H: TPulseDeviceData;
begin
  H := TPulseDeviceData(ADevice.Hidden);
  Result := True;
  Lock;
  try
    { 失われた印も見る。デバイスが失われると、PulseAudio はストリームを別の所へ動かして止めることが
      あり、そのあと書き込みの知らせは二度と来ない。失われた知らせ（Hotplug）が Signal で起こす。 }
    while (ADevice.ShutdownFlag.Load = 0) and (ADevice.Zombie.Load = 0) and (H.BytesRequested = 0) do
    begin
      WaitLoop;
      if (FPulse.API.context_get_state(FContext) <> PA_CONTEXT_READY)
        or (FPulse.API.stream_get_state(H.Stream) <> PA_STREAM_READY) then
      begin
        Result := False;   // デバイスが壊れた
        Break;
      end;
    end;
  finally
    Unlock;
  end;
end;

function TPMLPulseAudioBackend.PlayDevice(ADevice: TPMLAudioDevice; ABuffer: PByte; ALen: Integer): Boolean;
var
  H: TPulseDeviceData;
  Rc: cint;
begin
  H := TPulseDeviceData(ADevice.Hidden);
  Lock;
  try
    Rc := FPulse.API.stream_write(H.Stream, ABuffer, ALen, nil, 0, PA_SEEK_RELATIVE);
  finally
    Unlock;
  end;
  if Rc < 0 then
    Exit(False);
  Dec(H.BytesRequested, SizeUInt(ALen));
  Result := True;
end;

{ サーバのバッファに直接書ける置き場を借りる。借りられなければ自分の置き場。 }
function TPMLPulseAudioBackend.GetDeviceBuf(ADevice: TPMLAudioDevice; var ASize: Integer): PByte;
var
  H: TPulseDeviceData;
  ReqSize, NBytes: SizeUInt;
  Data: Pointer;
begin
  H := TPulseDeviceData(ADevice.Hidden);
  if SizeUInt(ASize) < H.BytesRequested then
    ReqSize := SizeUInt(ASize)
  else
    ReqSize := H.BytesRequested;
  NBytes := ReqSize;
  Data := nil;
  if FPulse.API.stream_begin_write(H.Stream, Data, NBytes) = 0 then
  begin
    ASize := Integer(NBytes);
    Exit(PByte(Data));
  end;
  // なぜ失敗するのか分からないが、念のため戻る道を残す
  ASize := Integer(ReqSize);
  Result := H.MixBuf;
end;

{ ---- 録音 ---- }

function TPMLPulseAudioBackend.WaitRecordingDevice(ADevice: TPMLAudioDevice): Boolean;
var
  H: TPulseDeviceData;
  Data: Pointer;
  NBytes: SizeUInt;
begin
  H := TPulseDeviceData(ADevice.Hidden);
  if H.RecordingBuf <> nil then
    Exit(True);   // まだ読める分がある

  Result := True;
  Lock;
  try
    while (ADevice.ShutdownFlag.Load = 0) and (ADevice.Zombie.Load = 0) do
    begin
      WaitLoop;
      if (FPulse.API.context_get_state(FContext) <> PA_CONTEXT_READY)
        or (FPulse.API.stream_get_state(H.Stream) <> PA_STREAM_READY) then
      begin
        Result := False;
        Break;
      end
      else if FPulse.API.stream_readable_size(H.Stream) > 0 then
      begin
        // 新しい断片がある
        Data := nil;
        NBytes := 0;
        FPulse.API.stream_peek(H.Stream, Data, NBytes);
        if Data = nil then
          // 穴があるときは nil。その断片は捨てる
          FPulse.API.stream_drop(H.Stream)
        else
        begin
          // この断片を RecordDevice のために取っておく
          H.RecordingBuf := PByte(Data);
          H.RecordingLen := SizeInt(NBytes);
          Break;
        end;
      end;
    end;
  finally
    Unlock;
  end;
end;

function TPMLPulseAudioBackend.RecordDevice(ADevice: TPMLAudioDevice; ABuffer: Pointer; ALen: Integer): Integer;
var
  H: TPulseDeviceData;
  Cpy: SizeInt;
begin
  H := TPulseDeviceData(ADevice.Hidden);
  if H.RecordingBuf <> nil then
  begin
    Cpy := ALen;
    if H.RecordingLen < Cpy then
      Cpy := H.RecordingLen;
    if Cpy > 0 then
    begin
      Move(H.RecordingBuf^, ABuffer^, Cpy);
      Inc(H.RecordingBuf, Cpy);
      Dec(H.RecordingLen, Cpy);
    end;
    if H.RecordingLen = 0 then
    begin
      H.RecordingBuf := nil;
      Lock;   // ロックが要るかは分からないが念のため
      try
        FPulse.API.stream_drop(H.Stream);   // この断片は使い終わった
      finally
        Unlock;
      end;
    end;
    Exit(Integer(Cpy));   // 新しい分を返す
  end;
  Result := 0;
end;

procedure TPMLPulseAudioBackend.FlushRecording(ADevice: TPMLAudioDevice);
var
  H: TPulseDeviceData;
  Data: Pointer;
  NBytes, BufLen: SizeUInt;
begin
  H := TPulseDeviceData(ADevice.Hidden);
  Data := nil;
  NBytes := 0;
  Lock;
  try
    if H.RecordingBuf <> nil then
    begin
      FPulse.API.stream_drop(H.Stream);
      H.RecordingBuf := nil;
      H.RecordingLen := 0;
    end;

    BufLen := FPulse.API.stream_readable_size(H.Stream);
    while (ADevice.ShutdownFlag.Load = 0) and (BufLen > 0) do
    begin
      WaitLoop;
      if (FPulse.API.context_get_state(FContext) <> PA_CONTEXT_READY)
        or (FPulse.API.stream_get_state(H.Stream) <> PA_STREAM_READY) then
      begin
        FCore.DeviceDisconnected(ADevice);
        Break;
      end;

      // FlushRecording を呼ぶ前にあった断片はまだ読める。捨てる
      FPulse.API.stream_peek(H.Stream, Data, NBytes);
      FPulse.API.stream_drop(H.Stream);
      // SDL は符号なしで引くので、読み過ぎると巻き戻って終わらなくなる。0 で止める
      if NBytes >= BufLen then
        BufLen := 0
      else
        Dec(BufLen, NBytes);
    end;
  finally
    Unlock;
  end;
end;

{ ---- 閉じる・後始末 ---- }

procedure TPMLPulseAudioBackend.CloseDevice(ADevice: TPMLAudioDevice);
var
  H: TPulseDeviceData;
begin
  H := TPulseDeviceData(ADevice.Hidden);
  if H = nil then
    Exit;
  Lock;
  try
    if H.Stream <> nil then
    begin
      if H.RecordingBuf <> nil then
        FPulse.API.stream_drop(H.Stream);
      // 切り離しの返事が来るまでストリームは生きていて、知らせが届くことがある。先に外す
      FPulse.API.stream_set_state_callback(H.Stream, nil, nil);
      FPulse.API.stream_set_write_callback(H.Stream, nil, nil);
      FPulse.API.stream_set_read_callback(H.Stream, nil, nil);
      FPulse.API.stream_disconnect(H.Stream);
      FPulse.API.stream_unref(H.Stream);
      H.Stream := nil;
    end;
    // デバイスのスレッドがどこかで待っていても、これで外れる
    Signal;
  finally
    Unlock;
  end;
  H.Free;
  ADevice.Hidden := nil;
end;

procedure TPMLPulseAudioBackend.InterruptDevice(ADevice: TPMLAudioDevice);
begin
  // 待っているスレッドを起こす。ロックを持って知らせれば、待つ前の確かめとすれ違わない
  if FMainloop = nil then
    Exit;
  Lock;
  try
    Signal;
  finally
    Unlock;
  end;
end;

procedure TPMLPulseAudioBackend.FreeDeviceHandle(ADevice: TPMLAudioDevice);
var
  H: TPulseDeviceHandle;
begin
  H := TPulseDeviceHandle(ADevice.Handle);
  if H = nil then
    Exit;
  HandlesRemove(H);
  H.Free;
  ADevice.Handle := nil;
end;

procedure TPMLPulseAudioBackend.DeinitializeStart;
var
  Thr: TPMLThread;
begin
  Thr := FHotplugThread;
  if Thr = nil then
    Exit;
  FHotplugThread := nil;
  Lock;
  try
    FHotplugActive.Exchange(0);
    Signal;
  finally
    Unlock;
  end;
  Thr.WaitFor;
  Thr.Free;
end;

procedure TPMLPulseAudioBackend.Deinitialize;
begin
  if FPulse <> nil then
    Disconnect;
  FDefaultSinkPath := '';
  FDefaultSinkChanged := False;
  FDefaultSourcePath := '';
  FDefaultSourceChanged := False;
end;

function CreatePulseBackend(ACore: TPMLAudioCore): TPMLAudioBackend;
begin
  Result := TPMLPulseAudioBackend.Create(ACore);
end;

initialization
  // PipeWire（100）の次。PipeWire が PulseAudio のサーバとして動いているときも、PipeWire の方を先に使う。
  PMLRegisterAudioBackend('pulseaudio', 90, @CreatePulseBackend);

end.
