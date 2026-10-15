{
  PaPiMeLa.Audio.Alsa — ALSA のオーディオのバックエンド

  Origin : ported from SDL (src/audio/alsa/SDL_alsa_audio.c, SDL_alsa_audio.h)
           Scope: SDL_alsa_audio.c の全体（デバイス名の接頭辞の推測、カードと PCM の列挙、走査による
           hotplug、PCM を開いてハードウェアとソフトウェアのパラメータを決める道、チャンネルの並びの
           交渉と入れ替え、待つ・鳴らす・録る・回復、閉じる）。udev による hotplug は、SDL が持つ
           別の部品（core/linux/SDL_udev.c）を使うので移植せず、SDL の udev 無しの道（走査のスレッド）だけ。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §9.4、§11 #58

  WHAT:
    ALSA の PCM を直接開いて再生と録音をする。デバイスは、すべてのカードの PCM を
    「カード名:PCM 名」の名前で足し、既定の再生と録音（ALSA の default）を 1 台ずつ足す。
    ハードウェアの許す範囲で、近い形式・チャンネル数・周波数を選び、チャンネルの並びが SDL の並びと
    違えば入れ替えの表を作る（SDL の ChannelMap）。デバイススレッドは中核が作る。

  WHY:
    PipeWire も PulseAudio も無い環境で、カーネルのドライバへ直接つなぐため。優先度は PulseAudio の次。

  RESOLVED:
    - SDL の静的な変数（接頭辞、デバイスの連なり）は、バックエンドのフィールドに置く
    - SDL の ALSA_Device の連なり（hotplug_devices）は、ハンドルの配列で持つ。ハンドルは中核が
      デバイスを捨てるとき FreeDeviceHandle で解放する（SDL は切断の知らせの直後に解放し、デバイスが
      まだ指していた）
    - snd_pcm_hw_params_alloca は xxx_sizeof() の大きさの領域を確保して 0 で埋める

  PORT-NOTE(bug):
    SDL の alsa_chmap_cfg_ordered_fixed_or_paired は、`sdl_chmap[i] == alsa_chmap[i]` を調べてから
    `i == chans_n` を見るので、全部一致した後にもう 1 つ先（配列の外）を読む。外の値が偶然 0 でなければ
    一致と見なさずに先へ進み、次の経路（unordered）が同じ並びを入れる。papimela は chans_n 個が一致した
    時点で入れる（結果の並びは同じ。入れ替えの表は恒等なので作らない）。
    SDL の成功した道は snd_pcm_query_chmaps の結果を解放しない（小さな漏れ）。papimela は解放する。
    SDL の失敗の道（ALSA_HotplugIteration の failed）は、閉じ済みの ctl をもう一度閉じることがある。
    papimela は閉じたら nil にする。

  NOT RESOLVED:
    - 録音は手元の実機で通していない（録音の装置を勝手に開かない）。SDL のとおりに写した
    - udev の hotplug（SDL の ALSA_udev_callback）は無い。走査の間隔は 5 秒（ヒントで変えられる）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Audio.Alsa;

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
  PaPiMeLa.Platform.Alsa,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Backend;

type
  TPMLAlsaAudioBackend = class;

  { ALSA_Device。物理デバイスの Handle（このオブジェクトのポインタ）。 }
  TAlsaDeviceHandle = class
  public
    Id         : String;     // 空なら「ALSA の既定」
    DeviceIndex: Integer;
    Name       : String;
    Recording  : Boolean;
    IsStatic   : Boolean;    // 既定の 2 つ。バックエンドが持つ（FreeDeviceHandle で解放しない）
  end;

  { SDL_PrivateAudioData。 }
  TAlsaDeviceData = class
  public
    Pcm   : PSndPcm;
    MixBuf: PByte;
    destructor Destroy; override;
  end;

  TPMLAlsaAudioBackend = class(TPMLAudioBackend)
  strict private
    FAllHandles: TList;                // ここまでに作ったハンドル全部。バックエンドが壊れるまで残す
  private
    FAlsa: TPMLAlsa;
    FPrefix: String;                   // ALSA_device_prefix
    FDefaultPlayback: TAlsaDeviceHandle;
    FDefaultRecording: TAlsaDeviceHandle;
    FDevices: array of TAlsaDeviceHandle;   // hotplug_devices（見えているもの）
    FDevicesLock: TPMLMutex;
    FHotplugThread: TPMLThread;
    FHotplugShutdown: TPMLAtomicInt;
    FHotplugIntervalMs: Integer;
    FLastError: String;
    procedure NoteError(E: Exception; const AWhere: String);
    procedure GuessDevicePrefix;
    function  GetPcmStr(AHandle: TAlsaDeviceHandle): String;
    function  Recover(APcm: PSndPcm; AErr: Integer): Integer;
    function  HotplugDeviceProcess(ACtl: PSndCtl; ACardInfo: PSndCtlCardInfo; ADevIdx: Integer;
      ADirection: Integer; var AUnseen, ASeen: TList): Integer;
    procedure DisconnectHandle(AHandle: TAlsaDeviceHandle);
    procedure HotplugIteration(out AHasDefaultPlayback, AHasDefaultRecording: Boolean);
  public
    constructor Create(ACore: TPMLAudioCore); override;
    destructor Destroy; override;
    function  Name: String; override;
    procedure DetectDevices(out ADefaultPlayback, ADefaultRecording: TPMLAudioDevice); override;
    function  OpenDevice(ADevice: TPMLAudioDevice): Boolean; override;
    procedure ThreadInit(ADevice: TPMLAudioDevice); override;
    function  WaitDevice(ADevice: TPMLAudioDevice): Boolean; override;
    function  PlayDevice(ADevice: TPMLAudioDevice; ABuffer: PByte; ALen: Integer): Boolean; override;
    function  GetDeviceBuf(ADevice: TPMLAudioDevice; var ASize: Integer): PByte; override;
    function  WaitRecordingDevice(ADevice: TPMLAudioDevice): Boolean; override;
    function  RecordDevice(ADevice: TPMLAudioDevice; ABuffer: Pointer; ALen: Integer): Integer; override;
    procedure FlushRecording(ADevice: TPMLAudioDevice); override;
    procedure CloseDevice(ADevice: TPMLAudioDevice); override;
    procedure FreeDeviceHandle(ADevice: TPMLAudioDevice); override;
    procedure DeinitializeStart; override;
    procedure Deinitialize; override;
    // 検査用: 走査を 1 回、今すぐ行う（hotplug のスレッドと同じ処理）。
    procedure ScanNow;
    // 検査用: 推測した接頭辞（"hw:" など）。
    property  DevicePrefix: String read FPrefix;
    property  LastError: String read FLastError;
  end;

type
  { SDL のチャンネルの並びの交渉の結果。 }
  TPMLAlsaChmapOutcome = (Installed, NextChannelCount);
  TPMLAlsaPositions = array[0..8] of cuint;   // 余分の 1 つは SDL が先を読む分（0 のまま）

{ SDL の alsa_chmap_cfg。開いた PCM（hw_params を入れた後）に、AChannels チャンネルの SDL の並びに合う
  ALSA の並びを探して入れる。入れた並びを AInstalled に、入れ替えが要れば ASwizzle（SDL の並びの
  i 番目が入れた並びの何番目か）を返す。合う並びが無ければ NextChannelCount（呼び出し側が
  チャンネル数を変えて試し直す）。ALSA に並びを入れられなければ EPMLAudioError。
  並びが聞けない PCM（snd_pcm_query_chmaps が nil）は、入れ替え無しの Installed。
  単体で試せるよう、関数の表と PCM を引数にした（test_audio_alsa）。 }
function PMLAlsaNegotiateChannelMap(const AAPI: TPMLAlsaAPI; APcm: PSndPcm; AChannels: Integer;
  out ASwizzle: TPMLChannelMap; out AInstalled: TPMLAlsaPositions): TPMLAlsaChmapOutcome;

implementation

procedure c_free(P: Pointer); cdecl; external 'c' name 'free';

destructor TAlsaDeviceData.Destroy;
begin
  if MixBuf <> nil then
    FreeMem(MixBuf);
  inherited Destroy;
end;

const
  ChmapChansNMax = 8;   // SDL_AUDIO_ALSA__CHMAP_CHANS_N_MAX

type
  TChmapPos = array[0..ChmapChansNMax] of cuint;   // 余分の 1 つは SDL が先を読む分

const
  // SDL の並び（SDL_audio.h）。6 チャンネルは「後ろ」か「横」かが決まる前の集合（SND_CHMAP_UNKNOWN の 2 つ）。
  SdlChannelMaps: array[0..ChmapChansNMax, 0..ChmapChansNMax - 1] of cuint = (
    (0, 0, 0, 0, 0, 0, 0, 0),
    (SND_CHMAP_MONO, 0, 0, 0, 0, 0, 0, 0),
    (SND_CHMAP_FL, SND_CHMAP_FR, 0, 0, 0, 0, 0, 0),
    (SND_CHMAP_FL, SND_CHMAP_FR, SND_CHMAP_LFE, 0, 0, 0, 0, 0),
    (SND_CHMAP_FL, SND_CHMAP_FR, SND_CHMAP_RL, SND_CHMAP_RR, 0, 0, 0, 0),
    (SND_CHMAP_FL, SND_CHMAP_FR, SND_CHMAP_LFE, SND_CHMAP_RL, SND_CHMAP_RR, 0, 0, 0),
    (SND_CHMAP_FL, SND_CHMAP_FR, SND_CHMAP_FC, SND_CHMAP_LFE, SND_CHMAP_UNKNOWN, SND_CHMAP_UNKNOWN, 0, 0),
    (SND_CHMAP_FL, SND_CHMAP_FR, SND_CHMAP_FC, SND_CHMAP_LFE, SND_CHMAP_RC, SND_CHMAP_SL, SND_CHMAP_SR, 0),
    (SND_CHMAP_FL, SND_CHMAP_FR, SND_CHMAP_FC, SND_CHMAP_LFE, SND_CHMAP_RL, SND_CHMAP_RR, SND_CHMAP_SL,
     SND_CHMAP_SR));

  // ALSA_pcm_cfg_hw_chans_n_scan の結果
  ChansNConfigured    = 0;
  ChansNNotConfigured = 1;
  // alsa_chmap_cfg の結果
  ChmapInstalled = 0;
  ChansNNext     = 1;
  ChmapNotFound  = 2;

type
  { ALSA_pcm_cfg_ctx。パラメータを決める間の入れ物。 }
  TPcmCfgCtx = record
    Device           : TPMLAudioDevice;
    Data             : TAlsaDeviceData;
    HwParams         : PSndPcmHwParams;
    SwParams         : PSndPcmSwParams;
    MatchedFormat    : TPMLAudioFormat;
    ChansN           : cuint;
    Rate             : cuint;
    PerSize          : culong;
    SdlChmap         : TChmapPos;
    AlsaChmapInstalled: TChmapPos;
    Swizzle          : TPMLChannelMap;
    Periods          : cuint;
    Api              : ^TPMLAlsaAPI;
    Pcm              : PSndPcm;
  end;

procedure TPMLAlsaAudioBackend.NoteError(E: Exception; const AWhere: String);
begin
  FLastError := AWhere + ': ' + E.ClassName + ': ' + E.Message;
  if (ContextServices <> nil) and (ContextServices.Log <> nil) then
    ContextServices.Log.Error(PML_LOG_CATEGORY_AUDIO, 'alsa: ' + FLastError);
end;

constructor TPMLAlsaAudioBackend.Create(ACore: TPMLAudioCore);
var
  Interval: Integer;
begin
  inherited Create(ACore);
  FDevicesLock := TPMLMutex.Create;
  FAllHandles := TList.Create;
  FAlsa := TPMLAlsa.Create;   // 無ければ EPMLPlatformLibrary（次のバックエンドへ）
  FCapabilities := [TPMLAudioBackendCapability.HasRecordingSupport];
  FHotplugIntervalMs := 5000;
  Interval := StrToIntDef(Trim(FCore.Hint(PML_HINT_AUDIO_ALSA_HOTPLUG_INTERVAL)), 0);
  if Interval > 0 then
    FHotplugIntervalMs := Interval;
  FDefaultPlayback := TAlsaDeviceHandle.Create;
  FDefaultPlayback.Id := '';
  FDefaultPlayback.Name := 'default';
  FDefaultPlayback.IsStatic := True;
  FDefaultRecording := TAlsaDeviceHandle.Create;
  FDefaultRecording.Id := '';
  FDefaultRecording.Name := 'default';
  FDefaultRecording.Recording := True;
  FDefaultRecording.IsStatic := True;
  FAllHandles.Add(FDefaultPlayback);
  FAllHandles.Add(FDefaultRecording);
end;

destructor TPMLAlsaAudioBackend.Destroy;
var
  I: Integer;
begin
  if FHotplugThread <> nil then
    DeinitializeStart;
  FAlsa.Free;
  if FAllHandles <> nil then
    for I := 0 to FAllHandles.Count - 1 do
      TAlsaDeviceHandle(FAllHandles[I]).Free;
  FAllHandles.Free;
  FDevicesLock.Free;
  inherited Destroy;
end;

function TPMLAlsaAudioBackend.Name: String;
begin
  Result := 'alsa';
end;

{ ALSA_guess_device_prefix。ALSA は実際のハードウェアの名前の前に "hw:" "sysdefault:" "default:" などを
  付ける。名前の一覧の中で最初に見つかった接頭辞を、この機械のものとする。 }
procedure TPMLAlsaAudioBackend.GuessDevicePrefix;
const
  Prefixes: array[0..2] of String = ('hw:', 'sysdefault:', 'default:');
var
  Hints: PPointer;
  I, J: Integer;
  HintName: PChar;
  NameStr: String;
begin
  if FPrefix <> '' then
    Exit;
  Hints := nil;
  if FAlsa.API.device_name_hint(-1, 'pcm', Hints) = 0 then
  begin
    I := 0;
    while (Hints[I] <> nil) and (FPrefix = '') do
    begin
      HintName := FAlsa.API.device_name_get_hint(Hints[I], 'NAME');
      if HintName <> nil then
      begin
        NameStr := StrPas(HintName);
        for J := 0 to High(Prefixes) do
          if Copy(NameStr, 1, Length(Prefixes[J])) = Prefixes[J] then
          begin
            FPrefix := Prefixes[J];
            Break;
          end;
        c_free(HintName);   // SDL_free ではなく free
      end;
      Inc(I);
    end;
    FAlsa.API.device_name_free_hint(Hints);
  end;
  if FPrefix = '' then
    FPrefix := Prefixes[0];   // しかたない
end;

{ get_pcm_str。PCM を開く名前。 }
function TPMLAlsaAudioBackend.GetPcmStr(AHandle: TAlsaDeviceHandle): String;
var
  DevName: String;
begin
  if AHandle.Id = '' then
  begin
    { 既定の PCM を通りたくない人のために、環境のヒントで自分の PCM を指せる。SDL の制約に合うもの。 }
    if AHandle.Recording then
      DevName := FCore.Hint(PML_HINT_AUDIO_ALSA_DEFAULT_RECORDING_DEVICE)
    else
      DevName := FCore.Hint(PML_HINT_AUDIO_ALSA_DEFAULT_PLAYBACK_DEVICE);
    if DevName = '' then
      DevName := FCore.Hint(PML_HINT_AUDIO_ALSA_DEFAULT_DEVICE);
    if DevName = '' then
      DevName := 'default';
    Result := DevName;
  end
  else
    Result := Format('%sCARD=%s,DEV=%d', [FPrefix, AHandle.Id, AHandle.DeviceIndex]);
end;

{ RecoverALSADevice。 }
function TPMLAlsaAudioBackend.Recover(APcm: PSndPcm; AErr: Integer): Integer;
var
  Pre, Post: cint;
begin
  Pre := FAlsa.API.pcm_state(APcm);
  Result := FAlsa.API.pcm_recover(APcm, AErr, 0);
  if Result = 0 then
  begin
    Post := FAlsa.API.pcm_state(APcm);
    // 溢れ・足りなさで止まったデバイスを再び動かす
    if (Pre = SND_PCM_STATE_XRUN) and (Post = SND_PCM_STATE_PREPARED) then
      FAlsa.API.pcm_start(APcm);
  end;
end;

{ ---- 再生・録音 ---- }

{ 1 回分を書けるまで待つ。SDL は 1〜5 ミリ秒ごとに調べる。 }
function TPMLAlsaAudioBackend.WaitDevice(ADevice: TPMLAudioDevice): Boolean;
var
  D: TAlsaDeviceData;
  SampleFrames, FullDelay, Delay, Rc, Status: Integer;
begin
  D := TAlsaDeviceData(ADevice.Hidden);
  SampleFrames := ADevice.SampleFrames;
  FullDelay := Integer((Int64(SampleFrames) * 1000) div ADevice.Spec.Freq);
  Delay := FullDelay;
  if Delay < 1 then
    Delay := 1
  else if Delay > 5 then
    Delay := 5;

  while ADevice.ShutdownFlag.Load = 0 do
  begin
    Rc := FAlsa.API.pcm_avail(D.Pcm);
    if Rc < 0 then
    begin
      Status := Recover(D.Pcm, Rc);
      if Status < 0 then
      begin
        // どうしようもない。あきらめる
        if (ContextServices <> nil) and (ContextServices.Log <> nil) then
          ContextServices.Log.Error(PML_LOG_CATEGORY_AUDIO,
            'ALSA wait failed (unrecoverable): ' + StrPas(FAlsa.API.strerror(Rc)));
        Exit(False);
      end;
    end;
    if Rc >= SampleFrames then
      Break;
    Sleep(Delay);
  end;
  Result := True;
end;

function TPMLAlsaAudioBackend.PlayDevice(ADevice: TPMLAudioDevice; ABuffer: PByte; ALen: Integer): Boolean;
var
  D: TAlsaDeviceData;
  FrameSize, Status: Integer;
  Rc: clong;
  FramesLeft: culong;
  SampleBuf: PByte;
begin
  D := TAlsaDeviceData(ADevice.Hidden);
  SampleBuf := ABuffer;
  FrameSize := ADevice.Spec.FrameSize;
  FramesLeft := culong(ALen div FrameSize);

  while (FramesLeft > 0) and (ADevice.ShutdownFlag.Load = 0) do
  begin
    Rc := FAlsa.API.pcm_writei(D.Pcm, SampleBuf, FramesLeft);
    if Rc < 0 then
    begin
      Status := Recover(D.Pcm, Integer(Rc));
      if Status < 0 then
      begin
        if (ContextServices <> nil) and (ContextServices.Log <> nil) then
          ContextServices.Log.Error(PML_LOG_CATEGORY_AUDIO,
            'ALSA write failed (unrecoverable): ' + StrPas(FAlsa.API.strerror(Integer(Rc))));
        Exit(False);
      end;
      Continue;
    end;
    Inc(SampleBuf, Rc * FrameSize);
    Dec(FramesLeft, culong(Rc));
  end;
  Result := True;
end;

function TPMLAlsaAudioBackend.GetDeviceBuf(ADevice: TPMLAudioDevice; var ASize: Integer): PByte;
var
  D: TAlsaDeviceData;
  Rc: clong;
  RequestedFrames: Integer;
begin
  D := TAlsaDeviceData(ADevice.Hidden);
  Rc := FAlsa.API.pcm_avail(D.Pcm);
  if Rc <= 0 then
  begin
    // 少し待ってもう一度。ハードウェアがまだ用意できていないのかもしれない
    Sleep(1);
    Rc := FAlsa.API.pcm_avail(D.Pcm);
    if Rc <= 0 then
    begin
      // 次の回に任せる
      ASize := 0;
      Exit(nil);
    end;
  end;
  if Rc < ADevice.SampleFrames then
    RequestedFrames := Integer(Rc)
  else
    RequestedFrames := ADevice.SampleFrames;
  ASize := RequestedFrames * ADevice.Spec.FrameSize;
  Result := D.MixBuf;
end;

function TPMLAlsaAudioBackend.WaitRecordingDevice(ADevice: TPMLAudioDevice): Boolean;
begin
  Result := WaitDevice(ADevice);
end;

function TPMLAlsaAudioBackend.RecordDevice(ADevice: TPMLAudioDevice; ABuffer: Pointer; ALen: Integer): Integer;
var
  D: TAlsaDeviceData;
  FrameSize, TotalFrames, Status: Integer;
  TotalAvailable: clong;
  Rc: clong;
begin
  D := TAlsaDeviceData(ADevice.Hidden);
  FrameSize := ADevice.Spec.FrameSize;
  TotalAvailable := FAlsa.API.pcm_avail(D.Pcm);
  if TotalAvailable = 0 then
    Exit(0);   // WaitDevice に戻ってもう一度

  TotalFrames := ALen div FrameSize;
  if TotalAvailable < TotalFrames then
    TotalFrames := Integer(TotalAvailable);
  Rc := FAlsa.API.pcm_readi(D.Pcm, ABuffer, culong(TotalFrames));

  if Rc < 0 then
  begin
    Status := Recover(D.Pcm, Integer(Rc));
    if Status < 0 then
    begin
      if (ContextServices <> nil) and (ContextServices.Log <> nil) then
        ContextServices.Log.Error(PML_LOG_CATEGORY_AUDIO,
          'ALSA read failed (unrecoverable): ' + StrPas(FAlsa.API.strerror(Integer(Rc))));
      Exit(-1);
    end;
    Exit(0);   // WaitDevice に戻ってもう一度
  end;
  Result := Integer(Rc) * FrameSize;
end;

procedure TPMLAlsaAudioBackend.FlushRecording(ADevice: TPMLAudioDevice);
begin
  FAlsa.API.pcm_reset(TAlsaDeviceData(ADevice.Hidden).Pcm);
end;

procedure TPMLAlsaAudioBackend.CloseDevice(ADevice: TPMLAudioDevice);
var
  D: TAlsaDeviceData;
begin
  D := TAlsaDeviceData(ADevice.Hidden);
  if D = nil then
    Exit;
  if D.Pcm <> nil then
    FAlsa.API.pcm_close(D.Pcm);
  D.Free;
  ADevice.Hidden := nil;
end;

{ ThreadInit。優先度を上げ、最初の PlayDevice のできるだけ近くで snd_pcm_start（始めの足りなさを避ける）。 }
procedure TPMLAlsaAudioBackend.ThreadInit(ADevice: TPMLAudioDevice);
begin
  inherited ThreadInit(ADevice);
  FAlsa.API.pcm_start(TAlsaDeviceData(ADevice.Hidden).Pcm);
end;

{ ---- チャンネルの並びの交渉（SDL の alsa_chmap_* と swizzle_map_*） ---- }

{ has_pos。ALSA の 6 チャンネルの並びに pos があるか。 }
function HasPos(AChmap: PCUInt; APos: cuint): Boolean;
var
  I: Integer;
begin
  for I := 0 to 5 do
    if AChmap[I] = APos then
      Exit(True);
  Result := False;
end;

{ sdl_6chans_set_rear_or_side_channels_from_alsa_6chans。6 チャンネルの SDL の並びの後ろ 2 つを、
  ALSA の並びが「後ろ」か「横」かで決める（両方・どちらも無ければ「不明」）。 }
procedure Sdl6ChansSetRearOrSide(var ASdl6: TChmapPos; AAlsa6: PCUInt);
const
  HaveNone = 0;
  HaveRear = 1;
  HaveSide = 2;
  HaveBoth = 3;
var
  State, I: Integer;
begin
  if not HasPos(AAlsa6, SND_CHMAP_FL) or not HasPos(AAlsa6, SND_CHMAP_FR)
    or not HasPos(AAlsa6, SND_CHMAP_FC) or not HasPos(AAlsa6, SND_CHMAP_LFE) then
  begin
    ASdl6[4] := SND_CHMAP_UNKNOWN;
    ASdl6[5] := SND_CHMAP_UNKNOWN;
    Exit;
  end;

  State := HaveNone;
  for I := 0 to 5 do
  begin
    if (AAlsa6[I] = SND_CHMAP_SL) or (AAlsa6[I] = SND_CHMAP_SR) then
    begin
      if State = HaveNone then
        State := HaveSide
      else if State = HaveRear then
      begin
        State := HaveBoth;
        Break;
      end;
    end
    else if (AAlsa6[I] = SND_CHMAP_RL) or (AAlsa6[I] = SND_CHMAP_RR) then
    begin
      if State = HaveNone then
        State := HaveRear
      else if State = HaveSide then
      begin
        State := HaveBoth;
        Break;
      end;
    end;
  end;

  if (State = HaveBoth) or (State = HaveNone) then
  begin
    ASdl6[4] := SND_CHMAP_UNKNOWN;
    ASdl6[5] := SND_CHMAP_UNKNOWN;
  end
  else if State = HaveRear then
  begin
    ASdl6[4] := SND_CHMAP_RL;
    ASdl6[5] := SND_CHMAP_RR;
  end
  else
  begin
    ASdl6[4] := SND_CHMAP_SL;
    ASdl6[5] := SND_CHMAP_SR;
  end;
end;

{ swizzle_map_compute。SDL の並びの i 番目が、入れた ALSA の並びの何番目にあるか（無ければ -1）。
  戻り値は、どれかの位置が違うか（入れ替えが要るか）。 }
function SwizzleMapCompute(const ACtx: TPcmCfgCtx; var AMap: TPMLChannelMap): Boolean;
var
  SdlIdx, AlsaIdx: Integer;
begin
  Result := False;
  SetLength(AMap, ACtx.ChansN);
  for SdlIdx := 0 to Integer(ACtx.ChansN) - 1 do
  begin
    AMap[SdlIdx] := -1;
    for AlsaIdx := 0 to Integer(ACtx.ChansN) - 1 do
      if ACtx.AlsaChmapInstalled[AlsaIdx] = ACtx.SdlChmap[SdlIdx] then
      begin
        AMap[SdlIdx] := AlsaIdx;
        Break;
      end;
    if AMap[SdlIdx] <> SdlIdx then
      Result := True;
  end;
end;

{ alsa_chmap_install。ALSA に並びを入れる。失敗は EPMLAudioError。 }
function ChmapInstall(var ACtx: TPcmCfgCtx; AChmap: PCUInt): Integer;
var
  ToInstall: PSndPcmChmap;
  I, Status: Integer;
begin
  ToInstall := PSndPcmChmap(GetMem((1 + Integer(ACtx.ChansN)) * SizeOf(cuint)));
  try
    ToInstall^.Channels := ACtx.ChansN;
    for I := 0 to Integer(ACtx.ChansN) - 1 do
      PMLAlsaChmapSetPos(ToInstall, I, AChmap[I]);
    Status := ACtx.Api^.pcm_set_chmap(ACtx.Pcm, ToInstall);
    if Status < 0 then
      raise EPMLAudioError.Create('ALSA: failed to install channel map: ' +
        StrPas(ACtx.Api^.strerror(Status)));
    for I := 0 to Integer(ACtx.ChansN) - 1 do
      ACtx.AlsaChmapInstalled[I] := AChmap[I];
  finally
    FreeMem(ToInstall);
  end;
  Result := ChmapInstalled;
end;

{ alsa_chmap_has_duplicate_position。 }
function ChmapHasDuplicate(const ACtx: TPcmCfgCtx; APos: PCUInt): Boolean;
var
  ChanIdx, SeenIdx: Integer;
begin
  if ACtx.ChansN < 2 then
    Exit(False);   // 2 つは要る
  for ChanIdx := 1 to Integer(ACtx.ChansN) - 1 do
    for SeenIdx := 0 to ChanIdx - 1 do
      if APos[SeenIdx] = APos[ChanIdx] then
        Exit(True);
  Result := False;
end;

{ SDL の並びを ctx へ。 }
procedure LoadSdlChmap(var ACtx: TPcmCfgCtx; AAlsaPos: PCUInt);
var
  I: Integer;
begin
  for I := 0 to Integer(ACtx.ChansN) - 1 do
    ACtx.SdlChmap[I] := SdlChannelMaps[ACtx.ChansN][I];
  if ACtx.ChansN = 6 then
    Sdl6ChansSetRearOrSide(ACtx.SdlChmap, AAlsaPos);
end;

{ 並びの位置の集合として、SDL の並びが ALSA の並びと同じか（順番は問わない）。 }
function SameAsSet(const ACtx: TPcmCfgCtx; AAlsaPos: PCUInt): Boolean;
var
  ChanIdx, Sub, Matches: Integer;
begin
  Matches := 0;
  for ChanIdx := 0 to Integer(ACtx.ChansN) - 1 do
    for Sub := 0 to Integer(ACtx.ChansN) - 1 do
      if ACtx.SdlChmap[ChanIdx] = AAlsaPos[Sub] then
      begin
        Inc(Matches);
        Break;
      end;
  Result := Matches = Integer(ACtx.ChansN);
end;

{ alsa_chmap_cfg_ordered_fixed_or_paired。ALSA の固定か対の並びで、SDL の並びと順番まで同じものを入れる。 }
function ChmapCfgOrderedFixedOrPaired(var ACtx: TPcmCfgCtx; AQueries: PPSndPcmChmapQuery): Integer;
var
  I, ChanIdx: Integer;
  Q: PSndPcmChmapQuery;
  AlsaChmap: PCUInt;
  AllEqual: Boolean;
begin
  I := 0;
  while AQueries[I] <> nil do
  begin
    Q := AQueries[I];
    Inc(I);
    if (Q^.Map.Channels <> ACtx.ChansN) or
      ((Q^.ChmapType <> SND_CHMAP_TYPE_FIXED) and (Q^.ChmapType <> SND_CHMAP_TYPE_PAIRED)) then
      Continue;
    AlsaChmap := PCUInt(PtrUInt(@Q^.Map) + SizeOf(TSndPcmChmap));
    LoadSdlChmap(ACtx, AlsaChmap);
    if ChmapHasDuplicate(ACtx, AlsaChmap) then
      Continue;
    // 最初の ChansN 個が全部同じなら入れる（ファイルの先頭の PORT-NOTE）
    AllEqual := True;
    for ChanIdx := 0 to Integer(ACtx.ChansN) - 1 do
      if ACtx.SdlChmap[ChanIdx] <> AlsaChmap[ChanIdx] then
      begin
        AllEqual := False;
        Break;
      end;
    if AllEqual then
      Exit(ChmapInstall(ACtx, AlsaChmap));
  end;
  Result := ChmapNotFound;
end;

{ alsa_chmap_cfg_ordered_var。HDMI のように、ALSA の枠の中の位置を自由に決められる並び。
  集合が同じなら、SDL の並びをそのまま入れる。 }
function ChmapCfgOrderedVar(var ACtx: TPcmCfgCtx; AQueries: PPSndPcmChmapQuery): Integer;
var
  I: Integer;
  Q: PSndPcmChmapQuery;
  AlsaChmap: PCUInt;
begin
  I := 0;
  while AQueries[I] <> nil do
  begin
    Q := AQueries[I];
    Inc(I);
    if (Q^.Map.Channels <> ACtx.ChansN) or (Q^.ChmapType <> SND_CHMAP_TYPE_VAR) then
      Continue;
    AlsaChmap := PCUInt(PtrUInt(@Q^.Map) + SizeOf(TSndPcmChmap));
    LoadSdlChmap(ACtx, AlsaChmap);
    if ChmapHasDuplicate(ACtx, AlsaChmap) then
      Continue;
    if SameAsSet(ACtx, AlsaChmap) then
      Exit(ChmapInstall(ACtx, @ACtx.SdlChmap[0]));   // SDL の並びを入れる
  end;
  Result := ChmapNotFound;
end;

function ChmapCfgOrdered(var ACtx: TPcmCfgCtx; AQueries: PPSndPcmChmapQuery): Integer;
begin
  Result := ChmapCfgOrderedFixedOrPaired(ACtx, AQueries);
  if Result = ChmapNotFound then
    Result := ChmapCfgOrderedVar(ACtx, AQueries);
end;

{ alsa_chmap_cfg_unordered。位置の集合が同じ並びを入れる（あとで入れ替える）。 }
function ChmapCfgUnordered(var ACtx: TPcmCfgCtx; AQueries: PPSndPcmChmapQuery): Integer;
var
  I: Integer;
  Q: PSndPcmChmapQuery;
  AlsaChmap: PCUInt;
begin
  I := 0;
  while AQueries[I] <> nil do
  begin
    Q := AQueries[I];
    Inc(I);
    if (Q^.Map.Channels <> ACtx.ChansN) or
      ((Q^.ChmapType <> SND_CHMAP_TYPE_FIXED) and (Q^.ChmapType <> SND_CHMAP_TYPE_PAIRED)) then
      Continue;
    AlsaChmap := PCUInt(PtrUInt(@Q^.Map) + SizeOf(TSndPcmChmap));
    LoadSdlChmap(ACtx, AlsaChmap);
    if ChmapHasDuplicate(ACtx, AlsaChmap) then
      Continue;
    if SameAsSet(ACtx, AlsaChmap) then
      Exit(ChmapInstall(ACtx, AlsaChmap));
  end;
  Result := ChmapNotFound;
end;

{ alsa_chmap_cfg。入れられたら ChmapInstalled、次のチャンネル数を試すなら ChansNNext。失敗は例外。 }
function ChmapCfg(var ACtx: TPcmCfgCtx): Integer;
var
  Queries: PPSndPcmChmapQuery;
  Swizzle: TPMLChannelMap;
begin
  Queries := ACtx.Api^.pcm_query_chmaps(ACtx.Pcm);
  if Queries = nil then
    Exit(ChmapInstalled);   // 並びが聞けない。入れ替えは要らないと見なす
  try
    // 入れ替えの要らない並びを先に探す
    Result := ChmapCfgOrdered(ACtx, Queries);
    if Result = ChmapInstalled then
      Exit;
    // 入れ替えが要る並び
    Result := ChmapCfgUnordered(ACtx, Queries);
    if Result = ChmapInstalled then
    begin
      Swizzle := nil;
      if SwizzleMapCompute(ACtx, Swizzle) then
        // 入れ替えは SDL の入れ替え（デバイスの ChannelMap）に任せる
        ACtx.Swizzle := Swizzle;
    end;
    if Result = ChmapNotFound then
      Result := ChansNNext;
  finally
    // SDL は成功した道で解放しない（小さな漏れ）。papimela は必ず解放する
    ACtx.Api^.pcm_free_chmaps(Queries);
  end;
end;

function PMLAlsaNegotiateChannelMap(const AAPI: TPMLAlsaAPI; APcm: PSndPcm; AChannels: Integer;
  out ASwizzle: TPMLChannelMap; out AInstalled: TPMLAlsaPositions): TPMLAlsaChmapOutcome;
var
  Ctx: TPcmCfgCtx;
  Status: Integer;
begin
  FillChar(Ctx, SizeOf(Ctx), 0);
  Ctx.Api := @AAPI;
  Ctx.Pcm := APcm;
  Ctx.ChansN := cuint(AChannels);
  Ctx.Swizzle := nil;
  Status := ChmapCfg(Ctx);
  if Status = ChmapInstalled then
    Result := TPMLAlsaChmapOutcome.Installed
  else
    Result := TPMLAlsaChmapOutcome.NextChannelCount;
  ASwizzle := Ctx.Swizzle;
  FillChar(AInstalled, SizeOf(AInstalled), 0);
  Move(Ctx.AlsaChmapInstalled, AInstalled, SizeOf(AInstalled));
end;

{ ---- パラメータを決める ---- }

{ ALSA_pcm_cfg_hw_chans_n_scan。モード 0 は求めたチャンネル数かそれより多い方へ、1 は少ない方へ。 }
function PcmCfgHwScan(var ACtx: TPcmCfgCtx; AMode: Integer): Integer;
var
  TargetChansN: cuint;
  Status: Integer;
  Formats: TPMLAudioFormats;
  I: Integer;
  AlsaFormat: cint;
  Api: ^TPMLAlsaAPI;
  Pcm: PSndPcm;
  Matched: Boolean;
begin
  Api := ACtx.Api;
  Pcm := ACtx.Pcm;
  TargetChansN := cuint(ACtx.Device.Spec.Channels);   // 求められた数から始める
  if AMode = 1 then
    Dec(TargetChansN);
  while True do
  begin
    if AMode = 0 then
    begin
      if TargetChansN > ChmapChansNMax then
        Exit(ChansNNotConfigured);
    end
    else if TargetChansN = 0 then
      Exit(ChansNNotConfigured);

    Status := Api^.pcm_hw_params_any(Pcm, ACtx.HwParams);
    if Status < 0 then
      raise EPMLAudioError.Create('ALSA: Couldn''t get hardware config: ' + StrPas(Api^.strerror(Status)));
    // SDL は交互に並べた出力だけを使う
    Status := Api^.pcm_hw_params_set_access(Pcm, ACtx.HwParams, SND_PCM_ACCESS_RW_INTERLEAVED);
    if Status < 0 then
      raise EPMLAudioError.Create('ALSA: Couldn''t set interleaved access: ' + StrPas(Api^.strerror(Status)));
    // 近い形式を選ぶ。バイト順は SDL の置き場と同じにする（読み書きで入れ替えない）
    Matched := False;
    ACtx.MatchedFormat := PML_AUDIO_UNKNOWN;
    Formats := PMLClosestAudioFormats(ACtx.Device.Spec.Format);
    for I := 0 to High(Formats) do
    begin
      case Formats[I] of
        PML_AUDIO_U8: AlsaFormat := SND_PCM_FORMAT_U8;
        PML_AUDIO_S8: AlsaFormat := SND_PCM_FORMAT_S8;
        PML_AUDIO_S16LE: AlsaFormat := SND_PCM_FORMAT_S16_LE;
        PML_AUDIO_S16BE: AlsaFormat := SND_PCM_FORMAT_S16_BE;
        PML_AUDIO_S32LE: AlsaFormat := SND_PCM_FORMAT_S32_LE;
        PML_AUDIO_S32BE: AlsaFormat := SND_PCM_FORMAT_S32_BE;
        PML_AUDIO_F32LE: AlsaFormat := SND_PCM_FORMAT_FLOAT_LE;
        PML_AUDIO_F32BE: AlsaFormat := SND_PCM_FORMAT_FLOAT_BE;
      else
        Continue;
      end;
      if Api^.pcm_hw_params_set_format(Pcm, ACtx.HwParams, AlsaFormat) >= 0 then
      begin
        ACtx.MatchedFormat := Formats[I];
        Matched := True;
        Break;
      end;
    end;
    if not Matched then
      raise EPMLAudioError.Create('ALSA: Unsupported audio format');
    // チャンネル数は ALSA に近い値にしてもらう
    ACtx.ChansN := TargetChansN;
    Status := Api^.pcm_hw_params_set_channels_near(Pcm, ACtx.HwParams, ACtx.ChansN);
    if Status < 0 then
      raise EPMLAudioError.Create('ALSA: Couldn''t set audio channels: ' + StrPas(Api^.strerror(Status)));
    // 周波数も
    ACtx.Rate := cuint(ACtx.Device.Spec.Freq);
    Status := Api^.pcm_hw_params_set_rate_near(Pcm, ACtx.HwParams, ACtx.Rate, nil);
    if Status < 0 then
      raise EPMLAudioError.Create('ALSA: Couldn''t set audio frequency: ' + StrPas(Api^.strerror(Status)));
    // ピリオドの大きさを、求められたバッファの大きさに近づける
    ACtx.PerSize := culong(ACtx.Device.SampleFrames);
    Status := Api^.pcm_hw_params_set_period_size_near(Pcm, ACtx.HwParams, ACtx.PerSize, nil);
    if Status < 0 then
      raise EPMLAudioError.Create('ALSA: Couldn''t set the period size: ' + StrPas(Api^.strerror(Status)));
    // バッファあたりのピリオド数の最小（二重バッファを狙う）
    ACtx.Periods := 2;
    Status := Api^.pcm_hw_params_set_periods_min(Pcm, ACtx.HwParams, ACtx.Periods, nil);
    if Status < 0 then
      raise EPMLAudioError.Create('ALSA: Couldn''t set the minimum number of periods per buffer: ' +
        StrPas(Api^.strerror(Status)));
    // 上で近づけた最小の近くに絞る
    Status := Api^.pcm_hw_params_set_periods_first(Pcm, ACtx.HwParams, ACtx.Periods, nil);
    if Status < 0 then
      raise EPMLAudioError.Create('ALSA: Couldn''t set the number of periods per buffer: ' +
        StrPas(Api^.strerror(Status)));
    // ハードウェアのパラメータを入れる
    Status := Api^.pcm_hw_params(Pcm, ACtx.HwParams);
    if Status < 0 then
      raise EPMLAudioError.Create('ALSA: installation of hardware parameter failed: ' +
        StrPas(Api^.strerror(Status)));

    { ここで PCM は PREPARED。SDL のチャンネルの並びに合う ALSA の並びを探す。
      チャンネル数を変えて試し直すこともある。 }
    Status := ChmapCfg(ACtx);
    if Status = ChmapInstalled then
    begin
      ACtx.Device.ChannelMap := ACtx.Swizzle;
      Exit(ChansNConfigured);
    end;

    // 次のチャンネル数
    Api^.pcm_hw_free(Pcm);   // 入れたパラメータを外す
    if AMode = 0 then
      Inc(TargetChansN)
    else
      Dec(TargetChansN);
  end;
end;

{ ALSA_pcm_cfg_hw。 }
procedure PcmCfgHw(var ACtx: TPcmCfgCtx);
begin
  if PcmCfgHwScan(ACtx, 0) = ChansNConfigured then
    Exit;
  if PcmCfgHwScan(ACtx, 1) = ChansNConfigured then
    Exit;
  raise EPMLAudioError.Create('ALSA: Couldn''t configure targeting any SDL supported channel number');
end;

{ ALSA_pcm_cfg_sw。 }
procedure PcmCfgSw(var ACtx: TPcmCfgCtx);
var
  Api: ^TPMLAlsaAPI;
  Pcm: PSndPcm;
  Status: Integer;
begin
  Api := ACtx.Api;
  Pcm := ACtx.Pcm;
  Status := Api^.pcm_sw_params_current(Pcm, ACtx.SwParams);
  if Status < 0 then
    raise EPMLAudioError.Create('ALSA: Couldn''t get software config: ' + StrPas(Api^.strerror(Status)));
  // 成功すれば device.sample_frames になる
  Status := Api^.pcm_sw_params_set_avail_min(Pcm, ACtx.SwParams, ACtx.PerSize);
  if Status < 0 then
    raise EPMLAudioError.Create('Couldn''t set minimum available samples: ' + StrPas(Api^.strerror(Status)));
  Status := Api^.pcm_sw_params_set_start_threshold(Pcm, ACtx.SwParams, 1);
  if Status < 0 then
    raise EPMLAudioError.Create('ALSA: Couldn''t set start threshold: ' + StrPas(Api^.strerror(Status)));
  Status := Api^.pcm_sw_params(Pcm, ACtx.SwParams);
  if Status < 0 then
    raise EPMLAudioError.Create('Couldn''t set software audio parameters: ' + StrPas(Api^.strerror(Status)));
end;

function TPMLAlsaAudioBackend.OpenDevice(ADevice: TPMLAudioDevice): Boolean;
var
  Ctx: TPcmCfgCtx;
  Recording: Boolean;
  Data: TAlsaDeviceData;
  PcmStr: String;
  Status: Integer;
begin
  Recording := ADevice.Recording;
  // SDL の入れ替え（swizzle）は、並びが違うときだけ ChansN の後ろで決まる
  ADevice.ChannelMap := nil;

  FillChar(Ctx, SizeOf(Ctx), 0);
  Ctx.Device := ADevice;
  Ctx.Api := @FAlsa.API;
  Data := TAlsaDeviceData.Create;
  ADevice.Hidden := Data;
  Ctx.Data := Data;

  // デバイスを開く
  PcmStr := GetPcmStr(TAlsaDeviceHandle(ADevice.Handle));
  if Recording then
    Status := FAlsa.API.pcm_open(Data.Pcm, PChar(PcmStr), SND_PCM_STREAM_CAPTURE, SND_PCM_NONBLOCK)
  else
    Status := FAlsa.API.pcm_open(Data.Pcm, PChar(PcmStr), SND_PCM_STREAM_PLAYBACK, SND_PCM_NONBLOCK);
  if Status < 0 then
  begin
    Data.Pcm := nil;
    raise EPMLAudioError.Create('ALSA: Couldn''t open audio device: ' + StrPas(FAlsa.API.strerror(Status)));
  end;

  Ctx.Pcm := Data.Pcm;
  // 開いた PCM を、求めたものになるべく近く、扱える範囲で設定する
  Ctx.HwParams := PSndPcmHwParams(AllocMem(FAlsa.API.pcm_hw_params_sizeof()));
  Ctx.SwParams := PSndPcmSwParams(AllocMem(FAlsa.API.pcm_sw_params_sizeof()));
  try
    PcmCfgHw(Ctx);   // PCM の「ハードウェア」の部分
    PcmCfgSw(Ctx);   // 「ソフトウェア」の部分
  finally
    FreeMem(Ctx.HwParams);
    FreeMem(Ctx.SwParams);
  end;

  // 仕様に決まったものを反映する
  ADevice.Spec.Format := Ctx.MatchedFormat;
  ADevice.Spec.Channels := Integer(Ctx.ChansN);
  ADevice.Spec.Freq := Integer(Ctx.Rate);
  ADevice.SampleFrames := Integer(Ctx.PerSize);
  FCore.UpdatedDeviceFormat(ADevice);

  // 混ぜる置き場
  if not Recording then
  begin
    Data.MixBuf := GetMem(ADevice.BufferSize);
    FillChar(Data.MixBuf^, ADevice.BufferSize, ADevice.SilenceValue);
    // 再生は、PCM を開くときは待たない道で開き、設定が済んだら待つ道にする
    FAlsa.API.pcm_nonblock(Data.Pcm, 0);
  end;
  Result := True;
end;

{ ---- 列挙と hotplug ---- }

{ hotplug_device_process。1 つの PCM の（再生か録音の）サブデバイスを見る。見えたものを ASeen に、
  前から見えていたもの（AUnseen）を移す。新しく見えたものは中核へ足す。失敗は -1。 }
function TPMLAlsaAudioBackend.HotplugDeviceProcess(ACtl: PSndCtl; ACardInfo: PSndCtlCardInfo;
  ADevIdx: Integer; ADirection: Integer; var AUnseen, ASeen: TList): Integer;
var
  SubdevsN, SubdevIdx: Cardinal;
  Recording: Boolean;
  PcmInfo: PSndPcmInfo;
  R, I: Integer;
  CardId: String;
  H: TAlsaDeviceHandle;
  Found: TAlsaDeviceHandle;
  PcmName: String;
begin
  SubdevsN := 1;   // 少なくとも 1 つはある
  SubdevIdx := 0;
  Recording := ADirection = SND_PCM_STREAM_CAPTURE;
  PcmInfo := PSndPcmInfo(AllocMem(FAlsa.API.pcm_info_sizeof()));
  try
    while True do
    begin
      FAlsa.API.pcm_info_set_stream(PcmInfo, ADirection);
      FAlsa.API.pcm_info_set_device(PcmInfo, cuint(ADevIdx));
      FAlsa.API.pcm_info_set_subdevice(PcmInfo, SubdevIdx);   // 少なくとも番号 0 はある

      R := FAlsa.API.ctl_pcm_info(ACtl, PcmInfo);
      if R < 0 then
      begin
        // 最初の問い合わせで ENOENT なら、この向きはこのデバイスに無い
        if (SubdevIdx = 0) and (R = -ENOENT) then
          Exit(0);
        Exit(-1);
      end;

      if SubdevIdx = 0 then
        SubdevsN := FAlsa.API.pcm_info_get_subdevices_count(PcmInfo);

      // 見えていなかったものの表から、(id, device_index, recording) が同じものを探す
      CardId := StrPas(FAlsa.API.ctl_card_info_get_id(ACardInfo));
      Found := nil;
      for I := 0 to AUnseen.Count - 1 do
      begin
        H := TAlsaDeviceHandle(AUnseen[I]);
        if (H.Id = CardId) and (H.DeviceIndex = ADevIdx) and (H.Recording = Recording) then
        begin
          Found := H;
          AUnseen.Delete(I);
          ASeen.Add(H);
          Break;
        end;
      end;

      if Found = nil then
      begin
        // 新しく見えた
        PcmName := StrPas(FAlsa.API.ctl_card_info_get_name(ACardInfo)) + ':' + StrPas(FAlsa.API.pcm_info_get_name(PcmInfo));
        H := TAlsaDeviceHandle.Create;
        H.Id := CardId;
        H.DeviceIndex := ADevIdx;
        H.Name := PcmName;
        H.Recording := Recording;
        FAllHandles.Add(H);
        if FCore.AddDevice(Recording, PcmName, '', TPMLAudioSpec.Make(0, 0, 0), H) = nil then
        begin
          FAllHandles.Remove(H);
          H.Free;
          Exit(-1);
        end;
        ASeen.Add(H);
      end;

      Inc(SubdevIdx);
      if SubdevIdx = SubdevsN then
        Exit(0);
      FillChar(PcmInfo^, FAlsa.API.pcm_info_sizeof(), 0);
    end;
  finally
    FreeMem(PcmInfo);
  end;
end;

procedure TPMLAlsaAudioBackend.DisconnectHandle(AHandle: TAlsaDeviceHandle);
begin
  FCore.DeviceDisconnected(FCore.FindDeviceByHandle(AHandle));
end;

{ ALSA_HotplugIteration。全部のカードの PCM を見て、前と比べて、足されたものを足し、無くなったものを
  切り離す。 }
procedure TPMLAlsaAudioBackend.HotplugIteration(out AHasDefaultPlayback, AHasDefaultRecording: Boolean);
var
  CardInfo: PSndCtlCardInfo;
  Ctl: PSndCtl;
  Unseen, Seen: TList;
  CardIdx, DevIdx, R, I: Integer;
  CtlName: String;
  Failed: Boolean;
begin
  AHasDefaultPlayback := True;
  AHasDefaultRecording := True;

  CardInfo := PSndCtlCardInfo(AllocMem(FAlsa.API.ctl_card_info_sizeof()));
  Unseen := TList.Create;
  Seen := TList.Create;
  FDevicesLock.Lock;
  try
    for I := 0 to High(FDevices) do
      Unseen.Add(FDevices[I]);
    Ctl := nil;
    Failed := False;
    CardIdx := -1;
    while True do
    begin
      R := FAlsa.API.card_next(CardIdx);
      if R < 0 then
      begin
        Failed := True;
        Break;
      end
      else if CardIdx = -1 then
        Break;

      CtlName := FPrefix + IntToStr(CardIdx);   // card_idx >= 0
      R := FAlsa.API.ctl_open(Ctl, PChar(CtlName), 0);
      if R < 0 then
      begin
        Ctl := nil;
        Continue;
      end;

      R := FAlsa.API.ctl_card_info(Ctl, CardInfo);
      if R < 0 then
      begin
        Failed := True;
        Break;
      end;

      DevIdx := -1;
      while True do
      begin
        R := FAlsa.API.ctl_pcm_next_device(Ctl, DevIdx);
        if R < 0 then
        begin
          Failed := True;
          Break;
        end
        else if DevIdx = -1 then
          Break;

        R := HotplugDeviceProcess(Ctl, CardInfo, DevIdx, SND_PCM_STREAM_PLAYBACK, Unseen, Seen);
        if R < 0 then
        begin
          Failed := True;
          Break;
        end;
        R := HotplugDeviceProcess(Ctl, CardInfo, DevIdx, SND_PCM_STREAM_CAPTURE, Unseen, Seen);
        if R < 0 then
        begin
          Failed := True;
          Break;
        end;
      end;
      if Failed then
        Break;
      FAlsa.API.ctl_close(Ctl);
      Ctl := nil;   // もう一度閉じないように（ファイルの先頭の PORT-NOTE）
      FAlsa.API.ctl_card_info_clear(CardInfo);
    end;

    if Ctl <> nil then
      FAlsa.API.ctl_close(Ctl);

    // 見えなくなったものを切り離す
    for I := 0 to Unseen.Count - 1 do
      DisconnectHandle(TAlsaDeviceHandle(Unseen[I]));

    if Failed then
    begin
      // 失敗したときは、見えているものも全部切り離す（SDL と同じ）
      for I := 0 to Seen.Count - 1 do
        DisconnectHandle(TAlsaDeviceHandle(Seen[I]));
      FDevices := nil;
    end
    else
    begin
      // 見えているものを、次の回の「前」にする
      SetLength(FDevices, Seen.Count);
      for I := 0 to Seen.Count - 1 do
        FDevices[I] := TAlsaDeviceHandle(Seen[I]);
    end;
  finally
    FDevicesLock.Unlock;
    Seen.Free;
    Unseen.Free;
    FreeMem(CardInfo);
  end;
end;

procedure TPMLAlsaAudioBackend.ScanNow;
var
  A, B: Boolean;
begin
  HotplugIteration(A, B);
end;

type
  // 走査のスレッド（SDL の ALSA_HotplugThread）。
  TAlsaHotplugThread = class(TPMLThread)
  private
    FBackend: TPMLAlsaAudioBackend;
  protected
    function Run: Integer; override;
  public
    constructor Create(ABackend: TPMLAlsaAudioBackend);
  end;

constructor TAlsaHotplugThread.Create(ABackend: TPMLAlsaAudioBackend);
begin
  inherited Create('SDLHotplugALSA', True);
  FBackend := ABackend;
end;

function TAlsaHotplugThread.Run: Integer;
var
  Ticks, Now: QWord;
  HasPlayback, HasRecording: Boolean;
begin
  FBackend.FCore.SetCurrentThreadPriority(TPMLThreadPriority.Low);
  while FBackend.FHotplugShutdown.Load = 0 do
  begin
    // 次の走査まで待つ。止められたらすぐ抜ける
    Ticks := GetTickCount64 + QWord(FBackend.FHotplugIntervalMs);
    Now := GetTickCount64;
    while (FBackend.FHotplugShutdown.Load = 0) and (Now < Ticks) do
    begin
      Sleep(20);
      Now := GetTickCount64;
    end;
    if FBackend.FHotplugShutdown.Load <> 0 then
      Break;
    try
      FBackend.HotplugIteration(HasPlayback, HasRecording);
    except
      on E: Exception do
        FBackend.NoteError(E, 'hotplug');
    end;
  end;
  Result := 0;
end;

procedure TPMLAlsaAudioBackend.DetectDevices(out ADefaultPlayback, ADefaultRecording: TPMLAudioDevice);
var
  HasPlayback, HasRecording: Boolean;
  Thr: TAlsaHotplugThread;
begin
  GuessDevicePrefix;

  { ALSA には変えられる既定の概念は無いので（SDL のコメント）、ここでは 1 つずつの一般的な
    既定を足す。最善のもの。 }
  ADefaultPlayback := nil;
  ADefaultRecording := nil;
  HotplugIteration(HasPlayback, HasRecording);   // スレッドの前に 1 度走らせる
  if HasPlayback then
    ADefaultPlayback := FCore.AddDevice(False, 'ALSA default playback device', '',
      TPMLAudioSpec.Make(0, 0, 0), FDefaultPlayback);
  if HasRecording then
    ADefaultRecording := FCore.AddDevice(True, 'ALSA default recording device', '',
      TPMLAudioSpec.Make(0, 0, 0), FDefaultRecording);

  // udev は使わない（SDL の udev 無しの道）。スレッドが起きなければ、それ以後の hotplug は無い
  FHotplugShutdown.Exchange(0);
  try
    Thr := TAlsaHotplugThread.Create(Self);
    FHotplugThread := Thr;
    Thr.Start;
  except
    on E: Exception do
    begin
      NoteError(E, 'hotplug thread');
      FHotplugThread := nil;
    end;
  end;
end;

procedure TPMLAlsaAudioBackend.FreeDeviceHandle(ADevice: TPMLAudioDevice);
begin
  // ハンドルはバックエンドが持つ（FAllHandles）。デバイスが無くなってもスレッドが指していることがあるので、
  // ここでは解放しない。バックエンドを壊すときにまとめて解放する
end;

procedure TPMLAlsaAudioBackend.DeinitializeStart;
var
  Thr: TPMLThread;
begin
  Thr := FHotplugThread;
  if Thr <> nil then
  begin
    FHotplugThread := nil;
    FHotplugShutdown.Exchange(1);
    Thr.WaitFor;
    Thr.Free;
  end;
  // 集めたものを片付ける（ハンドルはバックエンドが壊れるまで残す）
  FDevicesLock.Lock;
  try
    FDevices := nil;
  finally
    FDevicesLock.Unlock;
  end;
end;

procedure TPMLAlsaAudioBackend.Deinitialize;
begin
end;

function CreateAlsaBackend(ACore: TPMLAudioCore): TPMLAudioBackend;
begin
  Result := TPMLAlsaAudioBackend.Create(ACore);
end;

initialization
  // PulseAudio（90）の次。
  PMLRegisterAudioBackend('alsa', 80, @CreateAlsaBackend);

end.
