{
  PaPiMeLa.Audio.PipeWire — PipeWire のオーディオバックエンド

  Origin : ported from SDL (src/audio/pipewire/SDL_pipewire.c, src/audio/pipewire/SDL_pipewire.h)
           Scope: SDL_pipewire.c の全体（hotplug のスレッドとレジストリ、ノード・メタデータ・
           クライアントの知らせ、既定のデバイスの変更、ストリームを開く・鳴らす・録る・閉じる）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.5、§11 #56

  WHAT:
    PipeWire のシンク・ソースを物理デバイスとして足し、論理デバイスを開くと pw_stream を作って
    PipeWire のスレッドから中核のデバイスのスレッドの 1 回分（PlaybackThreadIterate など）を呼ぶ
    （能力 ProvidesOwnCallbackThread）。

  WHY:
    PipeWire は今の Linux のデスクトップの音の土台。papimela の最初の本物のオーディオバックエンド。

RESOLVED:
    - 名前は 'pipewire'、優先度 100（dummy より先）。SDL の「優先する pipewire」（セッションのサービスに
      audio が無い、デバイスが無いなら PulseAudio に譲る）は、papimela に PulseAudio と ALSA が無いので
      まだ要らない（NOT RESOLVED）。名前で選んだときと同じ PIPEWIRE_Init にあたる
    - SDL の大域の変数（hotplug_*）はバックエンドの欄に、C のつながりの一覧（hotplug_pending_list・
      hotplug_io_list）は Pascal の配列にした。ノードの記録（node_object）は SDL と同じくプロキシの
      利用者の置き場（C の記憶）に置く
    - PipeWire のスレッドから来る呼び出しは、入口で浮動小数点の例外を止め
      （PMLPipeWireCallbackEnter）、例外を C へ通さない。デバイスのスレッドの 1 回分で例外が出たら
      そのデバイスを失われたものとする（DESIGN §5.5）
    - pw_properties_setf は結ばない（値は Pascal で作って pw_properties_set に渡す）

  PORT-NOTE:
    - default.audio.source の変更は録音のデバイスにだけ、default.audio.sink の変更は再生のデバイスに
      だけ当てる（SDL は向きを見ずに名前の合うデバイスを既定にする。source の既定がシンクの名前
      （モニター）だと、再生の既定が変わりうる。確かめていない）
    - メタデータの値が JSON として読めなければ何もしない（SDL は NULL の名前と比べに行く）
    - SDL の node_event_param の形式の分岐（spa_format_audio_raw_parse）は写していない。形式は
      ノードを足すときに S16 にしてあり、その分岐は通らない（SDL も同じ）

  NOT RESOLVED:
    - 「優先する pipewire」の確かめ（上）。PulseAudio（#57）・ALSA（#58）を足すときに
    - 既定の変更（default.audio.sink の変更での移動）は手元の検査で見ていない（利用者の既定を変えるので）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Audio.PipeWire;

{$I papimela.inc}

interface

uses
  SysUtils, Math, ctypes,
  PaPiMeLa.Errors,
  PaPiMeLa.Properties,
  PaPiMeLa.Log,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Backend,
  PaPiMeLa.Platform.PipeWire;

{ ---- SDL_pipewire.c の小さな関数（検査からも呼ぶ） ---- }

{ initialize_spa_info と spa_format_audio_raw_build。ASpec のチャンネル数の SDL の並びと、
  形式の SPA の値（知らない形式なら SPA_AUDIO_FORMAT_UNKNOWN）で pod を作る。 }
function PMLPipeWireBuildFormat(const ASpec: TPMLAudioSpec; AParamId: LongWord): TBytes;
{ get_range_param。AKey の値が 3 つの値の Range なら、既定・最小・最大を入れて True。
  そうでなければ何も変えずに False。 }
function PMLPipeWireGetRangeParam(AParam: PSpaPod; AKey: LongWord;
  var ADef, AMin, AMax: Integer): Boolean;
{ get_int_param。AKey の値が整数なら入れて True。そうでなければ何も変えずに False。 }
function PMLPipeWireGetIntParam(AParam: PSpaPod; AKey: LongWord; var AValue: Integer): Boolean;
// get_name_from_json。オブジェクトの最初の鍵の値（JSON の "name" の値。鍵は 6 バイトまで、値は 255 バイトまで）。
// 取れなければ False。
function PMLPipeWireNameFromJson(AJson: PChar; out AName: String): Boolean;
{ client_info の session.services の読み方。JSON の配列に "audio" があれば True。 }
function PMLPipeWireServicesHaveAudio(AServices: PChar): Boolean;

implementation

const
  // PW_MAX_IDENTIFIER_LENGTH
  MaxIdentifierLength = 256;

  // SDL_Audio.h の並びに合う PipeWire の並び（PIPEWIRE_channel_map_1〜8）。
  ChannelMap1: array[0..0] of LongWord = (SPA_AUDIO_CHANNEL_MONO);
  ChannelMap2: array[0..1] of LongWord = (SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR);
  ChannelMap3: array[0..2] of LongWord = (SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_LFE);
  ChannelMap4: array[0..3] of LongWord = (SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_RL,
    SPA_AUDIO_CHANNEL_RR);
  ChannelMap5: array[0..4] of LongWord = (SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_FC,
    SPA_AUDIO_CHANNEL_RL, SPA_AUDIO_CHANNEL_RR);
  ChannelMap6: array[0..5] of LongWord = (SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_FC,
    SPA_AUDIO_CHANNEL_LFE, SPA_AUDIO_CHANNEL_RL, SPA_AUDIO_CHANNEL_RR);
  ChannelMap7: array[0..6] of LongWord = (SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_FC,
    SPA_AUDIO_CHANNEL_LFE, SPA_AUDIO_CHANNEL_RC, SPA_AUDIO_CHANNEL_RL, SPA_AUDIO_CHANNEL_RR);
  ChannelMap8: array[0..7] of LongWord = (SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_FC,
    SPA_AUDIO_CHANNEL_LFE, SPA_AUDIO_CHANNEL_RL, SPA_AUDIO_CHANNEL_RR, SPA_AUDIO_CHANNEL_SL,
    SPA_AUDIO_CHANNEL_SR);

// C の文字列として扱う（strdup・strcmp は最初の NUL で止まる）。
function CStr(const S: String): String;
var
  P: SizeInt;
begin
  P := Pos(#0, S);
  if P > 0 then
    Result := Copy(S, 1, P - 1)
  else
    Result := S;
end;

{ initialize_spa_info と spa_format_audio_raw_build。 }
function PMLPipeWireBuildFormat(const ASpec: TPMLAudioSpec; AParamId: LongWord): TBytes;
var
  Positions: array of LongWord;
  Format: LongWord;
  I: Integer;
begin
  // spa_audio_info_raw は 0 で始まる。チャンネル数の並びが無ければ 0 のまま（位置は 0 で出る）。
  Positions := nil;
  SetLength(Positions, ASpec.Channels);
  for I := 0 to High(Positions) do
    Positions[I] := 0;
  case ASpec.Channels of
    1: Move(ChannelMap1, Positions[0], SizeOf(ChannelMap1));
    2: Move(ChannelMap2, Positions[0], SizeOf(ChannelMap2));
    3: Move(ChannelMap3, Positions[0], SizeOf(ChannelMap3));
    4: Move(ChannelMap4, Positions[0], SizeOf(ChannelMap4));
    5: Move(ChannelMap5, Positions[0], SizeOf(ChannelMap5));
    6: Move(ChannelMap6, Positions[0], SizeOf(ChannelMap6));
    7: Move(ChannelMap7, Positions[0], SizeOf(ChannelMap7));
    8: Move(ChannelMap8, Positions[0], SizeOf(ChannelMap8));
  end;
  // PipeWire は SDL の形式を全部そのまま持つ。
  case ASpec.Format of
    PML_AUDIO_U8: Format := SPA_AUDIO_FORMAT_U8;
    PML_AUDIO_S8: Format := SPA_AUDIO_FORMAT_S8;
    PML_AUDIO_S16LE: Format := SPA_AUDIO_FORMAT_S16_LE;
    PML_AUDIO_S16BE: Format := SPA_AUDIO_FORMAT_S16_BE;
    PML_AUDIO_S32LE: Format := SPA_AUDIO_FORMAT_S32_LE;
    PML_AUDIO_S32BE: Format := SPA_AUDIO_FORMAT_S32_BE;
    PML_AUDIO_F32LE: Format := SPA_AUDIO_FORMAT_F32_LE;
    PML_AUDIO_F32BE: Format := SPA_AUDIO_FORMAT_F32_BE;
  else
    Format := SPA_AUDIO_FORMAT_UNKNOWN;
  end;
  Result := PMLSpaFormatAudioRawBuild(AParamId, Format, LongWord(ASpec.Freq), LongWord(ASpec.Channels),
    Positions);
end;

function PMLPipeWireGetRangeParam(AParam: PSpaPod; AKey: LongWord;
  var ADef, AMin, AMax: Integer): Boolean;
var
  Prop: PSpaPodProp;
  Value: PSpaPod;
  NValues, Choice: LongWord;
  V: PLongWord;
begin
  Result := False;
  Prop := PMLSpaPodFindProp(AParam, nil, AKey);
  if (Prop <> nil) and (Prop^.Value.PodType = SPA_TYPE_Choice) then
  begin
    Value := PMLSpaPodGetValues(@Prop^.Value, NValues, Choice);
    if (NValues = 3) and (Choice = SPA_CHOICE_Range) then
    begin
      V := PMLSpaPodBody(Value);
      ADef := Integer(V[0]);
      AMin := Integer(V[1]);
      AMax := Integer(V[2]);
      Result := True;
    end;
  end;
end;

function PMLPipeWireGetIntParam(AParam: PSpaPod; AKey: LongWord; var AValue: Integer): Boolean;
var
  Prop: PSpaPodProp;
  V: LongInt;
begin
  Result := False;
  Prop := PMLSpaPodFindProp(AParam, nil, AKey);
  if (Prop <> nil) and (PMLSpaPodGetInt(@Prop^.Value, V) = 0) then
  begin
    AValue := V;
    Result := True;
  end;
end;

function PMLPipeWireNameFromJson(AJson: PChar; out AName: String): Boolean;
var
  Parser: array[0..1] of TSpaJson;
  Key, Value: String;
begin
  AName := '';
  PMLSpaJsonInit(Parser[0], AJson, StrLen(AJson));
  if PMLSpaJsonEnterObject(Parser[0], Parser[1]) <= 0 then
    Exit(False);   // JSON ではない
  // char key[7]（"name"）
  if PMLSpaJsonGetString(Parser[1], Key, 7) <= 0 then
    Exit(False);   // 鍵と値の組ではない
  if PMLSpaJsonGetString(Parser[1], Value, MaxIdentifierLength) <= 0 then
    Exit(False);   // 鍵に値が無い
  AName := CStr(Value);
  Result := True;
end;

function PMLPipeWireServicesHaveAudio(AServices: PChar): Boolean;
var
  Iter: array[0..1] of TSpaJson;
  Element: String;
begin
  Result := False;
  PMLSpaJsonInit(Iter[0], AServices, StrLen(AServices));
  if PMLSpaJsonEnterArray(Iter[0], Iter[1]) > 0 then
    while PMLSpaJsonGetString(Iter[1], Element, MaxIdentifierLength) > 0 do
      if CStr(Element) = 'audio' then
        Exit(True);
end;


{ ---- バックエンド（SDL_pipewire.c） ---- }

const
  // PW_MIN_SAMPLES と PW_BASE_CLOCK_RATE（どちらも PipeWire の自分のモジュールが使う値）
  MinSamples = 32;
  BaseClockRate = 48000;
  // PW_READY_FLAG_*
  ReadyBufferAdded = 1;
  ReadyStreamReady = 2;
  ReadyAllPreopen = 3;
  ReadyOpenComplete = 4;
  ReadyAll = 7;

type
  TPMLPipeWireBackend = class;

  // io_node: シンクかソース。
  TIONode = class
  public
    Id       : LongWord;
    Recording: Boolean;
    Spec     : TPMLAudioSpec;
    Name     : String;   // 見せる名前（node.description）
    Path     : String;   // node.name（ALSA の口など）
  end;

  // node_object: プロキシの利用者の置き場（C の記憶。0 で埋めて使う）に置く。
  PNodeObject = ^TNodeObject;
  TNodeObject = record
    Link        : TSpaList;   // SDL と同じ並び（papimela は使わない）
    Id          : LongWord;
    Seq         : cint;
    Persist     : Boolean;
    UserData    : TIONode;    // nil でなければ、壊すときに Free する
    Proxy       : PPWProxy;
    NodeListener: TSpaHook;
    CoreListener: TSpaHook;
    Backend     : TPMLPipeWireBackend;
  end;

  // SDL_PrivateAudioData。
  TPipeWireDeviceData = class
  public
    Backend         : TPMLPipeWireBackend;
    Device          : TPMLAudioDevice;
    Loop            : PPWThreadLoop;
    Stream          : PPWStream;
    Context         : PPWContext;
    NodeName        : String;
    Stride          : Integer;   // 1 フレームのバイト数
    StreamInitStatus: Integer;
    PwBuf           : PPWBuffer; // GetDeviceBuf で取り、PlayDevice で返す
    HintWatched     : Boolean;
    procedure StreamNameChanged(const AName: String; const AOld, ANew: TPMLHintValue);
  end;

  TPMLPipeWireBackend = class(TPMLAudioBackend)
  private
    FPW: TPMLPipeWire;
    FInitialized: Boolean;   // pw_init を呼んだ
    FHotplugLoop: PPWThreadLoop;
    FHotplugCore: PPWCore;
    FHotplugContext: PPWContext;
    FHotplugRegistry: PPWRegistry;
    FRegistryListener: TSpaHook;
    FCoreListener: TSpaHook;
    FPending: array of PNodeObject;
    FIOList: array of TIONode;
    FInitSeq: cint;
    FInitComplete: Boolean;
    FEventsEnabled: Boolean;
    FHaveSessionServices: Boolean;
    FHaveAudioService: Boolean;
    FVersionMajor, FVersionMinor, FVersionPatch: Integer;
    FDefaultSinkId: String;
    FDefaultSourceId: String;
    FLastError: String;      // PipeWire のスレッドで捕まえた例外（内部の誤り）
    procedure NoteError(E: Exception; const AWhere: String);
    function  IOListCheckAdd(ANode: TIONode): Boolean;
    procedure IOListRemove(AId: LongWord);
    procedure IOListClear;
    function  IOListGetById(AId: LongWord): TIONode;
    procedure NodeObjectDestroy(ANode: PNodeObject);
    procedure PendingListRemove(AId: LongWord);
    procedure PendingListClear;
    function  NodeObjectNew(AId: LongWord; AType: PChar; AVersion: LongWord; AFuncs: Pointer;
      ACoreEvents: PPWCoreEvents): PNodeObject;
    procedure HotplugCoreSync(ANode: PNodeObject);
    procedure ChangeDefaultDevice(const APath: String; ARecording: Boolean);
    function  HotplugLoopInit: Boolean;
    procedure HotplugLoopDestroy;
    function  OpenDeviceMasked(ADevice: TPMLAudioDevice): Boolean;
    procedure CloseDeviceMasked(ADevice: TPMLAudioDevice);
    procedure DeinitializeMasked;
    function  StreamGetDeviceBuf(ADevice: TPMLAudioDevice; var ASize: Integer): PByte;
    function  StreamPlay(ADevice: TPMLAudioDevice; ALen: Integer): Boolean;
    procedure StreamFlush(ADevice: TPMLAudioDevice);
  public
    constructor Create(ACore: TPMLAudioCore); override;
    function  Name: String; override;
    procedure DetectDevices(out ADefaultPlayback, ADefaultRecording: TPMLAudioDevice); override;
    function  OpenDevice(ADevice: TPMLAudioDevice): Boolean; override;
    function  GetDeviceBuf(ADevice: TPMLAudioDevice; var ASize: Integer): PByte; override;
    function  PlayDevice(ADevice: TPMLAudioDevice; ABuffer: PByte; ALen: Integer): Boolean; override;
    function  RecordDevice(ADevice: TPMLAudioDevice; ABuffer: Pointer; ALen: Integer): Integer; override;
    procedure FlushRecording(ADevice: TPMLAudioDevice); override;
    procedure CloseDevice(ADevice: TPMLAudioDevice); override;
    procedure DeinitializeStart; override;
    procedure Deinitialize; override;
  end;

var
  // 知らせの表（C へ番地を渡すので、動かない大域に置く。initialization で埋める）。
  HotplugInitCoreEvents: TPWCoreEvents;
  InterfaceCoreEvents  : TPWCoreEvents;
  GenericCoreEvents    : TPWCoreEvents;
  InterfaceNodeEvents  : TPWNodeEvents;
  MetadataNodeEvents   : TPWMetadataEvents;
  ClientNodeEvents     : TPWClientEvents;
  RegistryEvents       : TPWRegistryEvents;
  StreamOutputEvents   : TPWStreamEvents;
  StreamInputEvents    : TPWStreamEvents;

{ ---- 一覧 ---- }

procedure TPMLPipeWireBackend.NoteError(E: Exception; const AWhere: String);
begin
  FLastError := AWhere + ': ' + E.ClassName + ': ' + E.Message;
  if (ContextServices <> nil) and (ContextServices.Log <> nil) then
    ContextServices.Log.Error(PML_LOG_CATEGORY_AUDIO, 'pipewire: ' + FLastError);
end;

// io_list_check_add。もう有れば False。
function TPMLPipeWireBackend.IOListCheckAdd(ANode: TIONode): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FIOList) do
    if FIOList[I].Id = ANode.Id then
      Exit(False);
  SetLength(FIOList, Length(FIOList) + 1);
  FIOList[High(FIOList)] := ANode;
  if FEventsEnabled then
    FCore.AddDevice(ANode.Recording, ANode.Name, '', ANode.Spec, Pointer(PtrUInt(ANode.Id)));
  Result := True;
end;

procedure TPMLPipeWireBackend.IOListRemove(AId: LongWord);
var
  I, J: Integer;
  N: TIONode;
begin
  for I := 0 to High(FIOList) do
    if FIOList[I].Id = AId then
    begin
      N := FIOList[I];
      for J := I to High(FIOList) - 1 do
        FIOList[J] := FIOList[J + 1];
      SetLength(FIOList, Length(FIOList) - 1);
      if FEventsEnabled then
        FCore.DeviceDisconnected(FCore.FindDeviceByHandle(Pointer(PtrUInt(AId))));
      N.Free;
      Break;
    end;
end;

procedure TPMLPipeWireBackend.IOListClear;
var
  I: Integer;
begin
  for I := 0 to High(FIOList) do
    FIOList[I].Free;
  FIOList := nil;
end;

function TPMLPipeWireBackend.IOListGetById(AId: LongWord): TIONode;
var
  I: Integer;
begin
  for I := 0 to High(FIOList) do
    if FIOList[I].Id = AId then
      Exit(FIOList[I]);
  Result := nil;
end;

procedure TPMLPipeWireBackend.NodeObjectDestroy(ANode: PNodeObject);
var
  I, J: Integer;
begin
  for I := 0 to High(FPending) do
    if FPending[I] = ANode then
    begin
      for J := I to High(FPending) - 1 do
        FPending[J] := FPending[J + 1];
      SetLength(FPending, Length(FPending) - 1);
      Break;
    end;
  PMLSpaHookRemove(@ANode^.NodeListener);
  PMLSpaHookRemove(@ANode^.CoreListener);
  FreeAndNil(ANode^.UserData);
  // プロキシを壊すと、ANode の置き場も無くなる。
  FPW.API.proxy_destroy(ANode^.Proxy);
end;

procedure TPMLPipeWireBackend.PendingListRemove(AId: LongWord);
var
  I: Integer;
begin
  I := High(FPending);
  while I >= 0 do
  begin
    if (I <= High(FPending)) and (FPending[I]^.Id = AId) then
      NodeObjectDestroy(FPending[I]);
    Dec(I);
  end;
end;

procedure TPMLPipeWireBackend.PendingListClear;
begin
  while Length(FPending) > 0 do
    NodeObjectDestroy(FPending[High(FPending)]);
end;

function TPMLPipeWireBackend.NodeObjectNew(AId: LongWord; AType: PChar; AVersion: LongWord;
  AFuncs: Pointer; ACoreEvents: PPWCoreEvents): PNodeObject;
var
  Proxy: PPWProxy;
begin
  Proxy := PMLPWRegistryBind(FHotplugRegistry, AId, AType, AVersion, SizeOf(TNodeObject));
  if Proxy = nil then
    Exit(nil);
  Result := PNodeObject(FPW.API.proxy_get_user_data(Proxy));
  FillChar(Result^, SizeOf(TNodeObject), 0);
  Result^.Id := AId;
  Result^.Proxy := Proxy;
  Result^.Backend := Self;
  PMLPWCoreAddListener(FHotplugCore, @Result^.CoreListener, ACoreEvents, Result);
  FPW.API.proxy_add_object_listener(Proxy, @Result^.NodeListener, AFuncs, Result);
  SetLength(FPending, Length(FPending) + 1);
  FPending[High(FPending)] := Result;
end;

{ hotplug_core_sync。ノードの同期は、全体の初めの同期より先に積む（でないと初めの一覧が欠ける）。 }
procedure TPMLPipeWireBackend.HotplugCoreSync(ANode: PNodeObject);
begin
  if ANode <> nil then
    ANode^.Seq := PMLPWCoreSync(FHotplugCore, PW_ID_CORE, ANode^.Seq);
  if not FInitComplete then
    FInitSeq := PMLPWCoreSync(FHotplugCore, PW_ID_CORE, FInitSeq);
end;

procedure TPMLPipeWireBackend.ChangeDefaultDevice(const APath: String; ARecording: Boolean);
var
  I: Integer;
begin
  if not FEventsEnabled then
    Exit;
  for I := 0 to High(FIOList) do
    // PORT-NOTE: 向きも見る（ヘッダの説明）。
    if (FIOList[I].Path = APath) and (FIOList[I].Recording = ARecording) then
    begin
      FCore.DefaultDeviceChanged(FCore.FindDeviceByHandle(Pointer(PtrUInt(FIOList[I].Id))));
      Exit;
    end;
end;

{ ---- 知らせ（PipeWire の hotplug のスレッドから。ループのロックを持って来る） ---- }

procedure CoreHotplugInitDone(AData: Pointer; AId: LongWord; ASeq: cint); cdecl;
var
  B: TPMLPipeWireBackend;
begin
  PMLPipeWireCallbackEnter;
  B := TPMLPipeWireBackend(AData);
  try
    if (AId = PW_ID_CORE) and (ASeq = B.FInitSeq) then
    begin
      // この知らせはもう要らない。
      PMLSpaHookRemove(@B.FCoreListener);
      // 初めの一覧ができた。
      B.FInitComplete := True;
      B.FPW.API.thread_loop_signal(B.FHotplugLoop, False);
    end;
  except
    on E: Exception do
      B.NoteError(E, 'core done');
  end;
end;

procedure CoreHotplugInfo(AData: Pointer; AInfo: PPWCoreInfo); cdecl;
var
  B: TPMLPipeWireBackend;
  Parts: TStringArray;
begin
  PMLPipeWireCallbackEnter;
  B := TPMLPipeWireBackend(AData);
  try
    // sscanf("%d.%d.%d")。3 つ読めなければ 0.0.0。
    Parts := String(AInfo^.Version).Split(['.']);
    if (Length(Parts) >= 3) and TryStrToInt(Parts[0], B.FVersionMajor) and TryStrToInt(Parts[1], B.FVersionMinor)
      and TryStrToInt(Parts[2], B.FVersionPatch) then
      Exit;
    B.FVersionMajor := 0;
    B.FVersionMinor := 0;
    B.FVersionPatch := 0;
  except
    on E: Exception do
      B.NoteError(E, 'core info');
  end;
end;

procedure CoreInterfaceDone(AData: Pointer; AId: LongWord; ASeq: cint); cdecl;
var
  Node: PNodeObject;
begin
  PMLPipeWireCallbackEnter;
  Node := PNodeObject(AData);
  try
    if (AId = PW_ID_CORE) and (ASeq = Node^.Seq) then
    begin
      // 入出力の一覧へ移す。移せたら一覧が持つ。
      if Node^.Backend.IOListCheckAdd(Node^.UserData) then
        Node^.UserData := nil;
      Node^.Backend.NodeObjectDestroy(Node);
    end;
  except
    on E: Exception do
      Node^.Backend.NoteError(E, 'interface done');
  end;
end;

procedure CoreGenericDone(AData: Pointer; AId: LongWord; ASeq: cint); cdecl;
var
  Node: PNodeObject;
begin
  PMLPipeWireCallbackEnter;
  Node := PNodeObject(AData);
  try
    if (AId = PW_ID_CORE) and (ASeq = Node^.Seq) and not Node^.Persist then
      Node^.Backend.NodeObjectDestroy(Node);
  except
    on E: Exception do
      Node^.Backend.NoteError(E, 'generic done');
  end;
end;

procedure NodeEventInfo(AData: Pointer; AInfo: PPWNodeInfo); cdecl;
var
  Node: PNodeObject;
  Io: TIONode;
  V: PChar;
  I: LongWord;
  P: PSpaParamInfo;
begin
  PMLPipeWireCallbackEnter;
  Node := PNodeObject(AData);
  try
    Io := Node^.UserData;
    if AInfo <> nil then
    begin
      V := PMLSpaDictLookup(AInfo^.Props, PW_KEY_AUDIO_CHANNELS);
      if V <> nil then
        Io.Spec.Channels := Byte(StrToIntDef(StrPas(V), 0));   // SDL_atoi を Uint8 へ
      // 周波数を知るために params を読む。
      P := AInfo^.Params;
      for I := 1 to AInfo^.NParams do
      begin
        PMLPWNodeEnumParams(Node^.Proxy, 0, P^.Id, 0, 0, nil);
        Inc(P);
      end;
      Node^.Backend.HotplugCoreSync(Node);
    end;
  except
    on E: Exception do
      Node^.Backend.NoteError(E, 'node info');
  end;
end;

procedure NodeEventParam(AData: Pointer; ASeq: cint; AId, AIndex, ANext: LongWord; AParam: PSpaPod); cdecl;
var
  Node: PNodeObject;
  Io: TIONode;
  Freq, Channels: Integer;
begin
  PMLPipeWireCallbackEnter;
  Node := PNodeObject(AData);
  try
    Io := Node^.UserData;
    // SDL の形式の分岐（SPA_PARAM_Format で形式が未知なら読む）は、形式を先に S16 にしてあるので通らない。
    // 既定の周波数（get_range_param(param, rate, &freq, NULL, NULL)。最小と最大は捨てる）。
    if Io.Spec.Freq = 0 then
    begin
      Freq := 0;
      Channels := 0;
      if PMLPipeWireGetRangeParam(AParam, SPA_FORMAT_AUDIO_rate, Freq, Channels, Channels) then
        Io.Spec.Freq := Freq;
    end;
    // チャンネル数はノードのプロパティから来るはず。来なかったら params から。
    if Io.Spec.Channels = 0 then
    begin
      Channels := 0;
      if PMLPipeWireGetIntParam(AParam, SPA_FORMAT_AUDIO_channels, Channels) then
        Io.Spec.Channels := Byte(Channels);
    end;
  except
    on E: Exception do
      Node^.Backend.NoteError(E, 'node param');
  end;
end;

function MetadataProperty(AData: Pointer; ASubject: LongWord; AKey, AType, AValue: PChar): cint; cdecl;
var
  Node: PNodeObject;
  B: TPMLPipeWireBackend;
  Name: String;
begin
  PMLPipeWireCallbackEnter;
  Result := 0;
  Node := PNodeObject(AData);
  B := Node^.Backend;
  try
    if (ASubject = PW_ID_CORE) and (AKey <> nil) and (AValue <> nil) then
    begin
      if StrComp(AKey, 'default.audio.sink') = 0 then
      begin
        if not PMLPipeWireNameFromJson(AValue, Name) then
          Name := '';
        B.FDefaultSinkId := Name;
        Node^.Persist := True;
        if Name <> '' then
          B.ChangeDefaultDevice(Name, False);
      end
      else if StrComp(AKey, 'default.audio.source') = 0 then
      begin
        if not PMLPipeWireNameFromJson(AValue, Name) then
          Name := '';
        B.FDefaultSourceId := Name;
        Node^.Persist := True;
        if Name <> '' then
          B.ChangeDefaultDevice(Name, True);
      end;
    end;
  except
    on E: Exception do
      B.NoteError(E, 'metadata property');
  end;
end;

procedure ClientInfo(AData: Pointer; AInfo: PPWClientInfo); cdecl;
var
  Node: PNodeObject;
  Services: PChar;
begin
  PMLPipeWireCallbackEnter;
  Node := PNodeObject(AData);
  try
    // WirePlumber がセッションのサービスを並べていれば、audio があるかを見る。
    Services := PMLSpaDictLookup(AInfo^.Props, 'session.services');
    if Services <> nil then
    begin
      Node^.Backend.FHaveSessionServices := True;
      if PMLPipeWireServicesHaveAudio(Services) then
        Node^.Backend.FHaveAudioService := True;
    end;
  except
    on E: Exception do
      Node^.Backend.NoteError(E, 'client info');
  end;
end;

procedure RegistryGlobal(AData: Pointer; AId, APermissions: LongWord; AType: PChar; AVersion: LongWord;
  AProps: PSpaDict); cdecl;
var
  B: TPMLPipeWireBackend;
  Node: PNodeObject;
  MediaClass, Desc, Path: PChar;
  Recording: Boolean;
  Io: TIONode;
begin
  PMLPipeWireCallbackEnter;
  B := TPMLPipeWireBackend(AData);
  try
    // 欲しいのは入出力のノードとメタデータ（とクライアント）だけ。
    if StrComp(AType, PW_TYPE_INTERFACE_Node) = 0 then
    begin
      MediaClass := PMLSpaDictLookup(AProps, PW_KEY_MEDIA_CLASS);
      if MediaClass = nil then
        Exit;
      // シンクとソースだけ
      if SameText(MediaClass, 'Audio/Sink') then
        Recording := False
      else if SameText(MediaClass, 'Audio/Source') or SameText(MediaClass, 'Audio/Source/Virtual') then
        Recording := True
      else
        Exit;
      Desc := PMLSpaDictLookup(AProps, PW_KEY_NODE_DESCRIPTION);
      Path := PMLSpaDictLookup(AProps, PW_KEY_NODE_NAME);
      if (Desc <> nil) and (Path <> nil) then
      begin
        Node := B.NodeObjectNew(AId, AType, AVersion, @InterfaceNodeEvents, @InterfaceCoreEvents);
        if Node = nil then
          Exit;
        Io := TIONode.Create;
        Node^.UserData := Io;
        Io.Id := AId;
        Io.Recording := Recording;
        // 形式が分からなければ控えめに S16（SDL と同じ。チャンネル数と周波数は後の知らせで）。
        Io.Spec := TPMLAudioSpec.Make(PML_AUDIO_S16, 0, 0);
        Io.Name := StrPas(Desc);
        Io.Path := StrPas(Path);
        B.HotplugCoreSync(Node);
      end;
    end
    else if StrComp(AType, PW_TYPE_INTERFACE_Metadata) = 0 then
    begin
      Node := B.NodeObjectNew(AId, AType, AVersion, @MetadataNodeEvents, @GenericCoreEvents);
      if Node <> nil then
        B.HotplugCoreSync(Node);
    end
    else if StrComp(AType, PW_TYPE_INTERFACE_Client) = 0 then
    begin
      Node := B.NodeObjectNew(AId, AType, AVersion, @ClientNodeEvents, @GenericCoreEvents);
      if Node <> nil then
        B.HotplugCoreSync(Node);
    end;
  except
    on E: Exception do
      B.NoteError(E, 'registry global');
  end;
end;

procedure RegistryGlobalRemove(AData: Pointer; AId: LongWord); cdecl;
var
  B: TPMLPipeWireBackend;
begin
  PMLPipeWireCallbackEnter;
  B := TPMLPipeWireBackend(AData);
  try
    B.IOListRemove(AId);
    B.PendingListRemove(AId);
  except
    on E: Exception do
      B.NoteError(E, 'registry global remove');
  end;
end;

{ ---- hotplug のスレッド ---- }

function TPMLPipeWireBackend.HotplugLoopInit: Boolean;
begin
  Result := False;
  FPending := nil;
  FIOList := nil;
  FHotplugLoop := FPW.API.thread_loop_new('PMLPwAudioPlug', nil);
  if FHotplugLoop = nil then
    raise EPMLAudioError.Create('Pipewire: Failed to create hotplug detection loop');
  FHotplugContext := FPW.API.context_new(FPW.API.thread_loop_get_loop(FHotplugLoop), nil, 0);
  if FHotplugContext = nil then
    raise EPMLAudioError.Create('Pipewire: Failed to create hotplug detection context');
  FHotplugCore := FPW.API.context_connect(FHotplugContext, nil, 0);
  if FHotplugCore = nil then
    raise EPMLAudioError.Create('Pipewire: Failed to connect hotplug detection context');
  FHotplugRegistry := PMLPWCoreGetRegistry(FHotplugCore, PW_VERSION_REGISTRY, 0);
  if FHotplugRegistry = nil then
    raise EPMLAudioError.Create('Pipewire: Failed to acquire hotplug detection registry');
  FillChar(FRegistryListener, SizeOf(FRegistryListener), 0);
  PMLPWRegistryAddListener(FHotplugRegistry, @FRegistryListener, @RegistryEvents, Self);
  FillChar(FCoreListener, SizeOf(FCoreListener), 0);
  PMLPWCoreAddListener(FHotplugCore, @FCoreListener, @HotplugInitCoreEvents, Self);
  FInitSeq := PMLPWCoreSync(FHotplugCore, PW_ID_CORE, 0);
  if FPW.API.thread_loop_start(FHotplugLoop) <> 0 then
    raise EPMLAudioError.Create('Pipewire: Failed to start hotplug detection loop');
  Result := True;
end;

procedure TPMLPipeWireBackend.HotplugLoopDestroy;
begin
  if FHotplugLoop <> nil then
    FPW.API.thread_loop_stop(FHotplugLoop);
  PendingListClear;
  IOListClear;
  FInitComplete := False;
  FEventsEnabled := False;
  FDefaultSinkId := '';
  FDefaultSourceId := '';
  if FHotplugRegistry <> nil then
  begin
    FPW.API.proxy_destroy(PPWProxy(FHotplugRegistry));
    FHotplugRegistry := nil;
  end;
  if FHotplugCore <> nil then
  begin
    FPW.API.core_disconnect(FHotplugCore);
    FHotplugCore := nil;
  end;
  if FHotplugContext <> nil then
  begin
    FPW.API.context_destroy(FHotplugContext);
    FHotplugContext := nil;
  end;
  if FHotplugLoop <> nil then
  begin
    FPW.API.thread_loop_destroy(FHotplugLoop);
    FHotplugLoop := nil;
  end;
end;

{ PipewireInitialize と PIPEWIRE_Init。 }
constructor TPMLPipeWireBackend.Create(ACore: TPMLAudioCore);
var
  Old: TFPUExceptionMask;
begin
  inherited Create(ACore);
  FPW := TPMLPipeWire.Create;   // 無ければ EPMLPlatformLibrary（次のバックエンドへ）
  // ここで作られる PipeWire のスレッドが、例外を止めた設定を受け継ぐように。
  Old := PMLPipeWireMaskBegin;
  try
    FPW.API.init(nil, nil);
    FInitialized := True;
    try
      HotplugLoopInit;
    except
      DeinitializeMasked;
      raise;
    end;
  finally
    PMLPipeWireMaskEnd(Old);
  end;
  FCapabilities := [TPMLAudioBackendCapability.HasRecordingSupport,
    TPMLAudioBackendCapability.ProvidesOwnCallbackThread];
end;

function TPMLPipeWireBackend.Name: String;
begin
  Result := 'pipewire';
end;

procedure TPMLPipeWireBackend.DetectDevices(out ADefaultPlayback, ADefaultRecording: TPMLAudioDevice);
var
  Old: TFPUExceptionMask;
  I: Integer;
  Io: TIONode;
  Dev: TPMLAudioDevice;
begin
  ADefaultPlayback := nil;
  ADefaultRecording := nil;
  Old := PMLPipeWireMaskBegin;
  FPW.API.thread_loop_lock(FHotplugLoop);
  try
    // 初めのレジストリの一覧ができるまで待つ。
    if not FInitComplete then
      FPW.API.thread_loop_wait(FHotplugLoop);
    for I := 0 to High(FIOList) do
    begin
      Io := FIOList[I];
      Dev := FCore.AddDevice(Io.Recording, Io.Name, '', Io.Spec, Pointer(PtrUInt(Io.Id)));
      if (FDefaultSinkId <> '') and (Io.Path = FDefaultSinkId) then
      begin
        if not Io.Recording then
          ADefaultPlayback := Dev;
      end
      else if (FDefaultSourceId <> '') and (Io.Path = FDefaultSourceId) then
      begin
        if Io.Recording then
          ADefaultRecording := Dev;
      end;
    end;
    FEventsEnabled := True;
  finally
    FPW.API.thread_loop_unlock(FHotplugLoop);
    PMLPipeWireMaskEnd(Old);
  end;
end;

{ ---- ストリーム ---- }

function TPMLPipeWireBackend.StreamGetDeviceBuf(ADevice: TPMLAudioDevice; var ASize: Integer): PByte;
var
  D: TPipeWireDeviceData;
  Buf: PPWBuffer;
  Spa: PSpaBuffer;
begin
  // バッファが無ければ ASize を 0 にする（中核はこの回を飛ばして次に試す）。
  D := TPipeWireDeviceData(ADevice.Hidden);
  Buf := FPW.API.stream_dequeue_buffer(D.Stream);
  if Buf = nil then
  begin
    ASize := 0;
    Exit(nil);
  end;
  Spa := Buf^.Buffer;
  if Spa^.Datas^.Data = nil then
  begin
    FPW.API.stream_queue_buffer(D.Stream, Buf);
    ASize := 0;
    Exit(nil);
  end;
  D.PwBuf := Buf;
  Result := PByte(Spa^.Datas^.Data);
end;

function TPMLPipeWireBackend.StreamPlay(ADevice: TPMLAudioDevice; ALen: Integer): Boolean;
var
  D: TPipeWireDeviceData;
  Chunk: PSpaChunk;
begin
  D := TPipeWireDeviceData(ADevice.Hidden);
  Chunk := D.PwBuf^.Buffer^.Datas^.Chunk;
  Chunk^.Offset := 0;
  Chunk^.Stride := D.Stride;
  Chunk^.Size := LongWord(ALen);
  FPW.API.stream_queue_buffer(D.Stream, D.PwBuf);
  D.PwBuf := nil;
  Result := True;
end;

function TPMLPipeWireBackend.GetDeviceBuf(ADevice: TPMLAudioDevice; var ASize: Integer): PByte;
begin
  Result := StreamGetDeviceBuf(ADevice, ASize);
end;

function TPMLPipeWireBackend.PlayDevice(ADevice: TPMLAudioDevice; ABuffer: PByte; ALen: Integer): Boolean;
begin
  Result := StreamPlay(ADevice, ALen);
end;

procedure OutputCallback(AData: Pointer); cdecl;
var
  Dev: TPMLAudioDevice;
  D: TPipeWireDeviceData;
  Size: Integer;
  Buf: PByte;
begin
  PMLPipeWireCallbackEnter;
  Dev := TPMLAudioDevice(AData);
  D := TPipeWireDeviceData(Dev.Hidden);
  try
    // OpenDevice がデバイスのロックを持って準備を待っている間にも来る。そこで中核を呼ぶと
    // 行き詰まるので、無音を書く。
    if D.StreamInitStatus <> ReadyAll then
    begin
      Size := 0;
      Buf := D.Backend.StreamGetDeviceBuf(Dev, Size);
      if (Buf <> nil) and (Size <> 0) then
        FillChar(Buf^, Size, Dev.SilenceValue);
      // SDL は GetDeviceBuf がバッファを返さなくても PlayDevice を呼ぶ（前の回のバッファを返す）。
      if D.PwBuf <> nil then
        D.Backend.StreamPlay(Dev, Size);
      Exit;
    end;
    Dev.Core.PlaybackThreadIterate(Dev);
  except
    on E: Exception do
    begin
      D.Backend.NoteError(E, 'output');
      Dev.Core.DeviceDisconnected(Dev);
    end;
  end;
end;

procedure TPMLPipeWireBackend.StreamFlush(ADevice: TPMLAudioDevice);
var
  D: TPipeWireDeviceData;
  Buf: PPWBuffer;
begin
  D := TPipeWireDeviceData(ADevice.Hidden);
  Buf := FPW.API.stream_dequeue_buffer(D.Stream);
  // 何も考えずに戻す。
  if Buf <> nil then
    FPW.API.stream_queue_buffer(D.Stream, Buf);
end;

procedure TPMLPipeWireBackend.FlushRecording(ADevice: TPMLAudioDevice);
begin
  StreamFlush(ADevice);
end;

function TPMLPipeWireBackend.RecordDevice(ADevice: TPMLAudioDevice; ABuffer: Pointer; ALen: Integer): Integer;
var
  D: TPipeWireDeviceData;
  Buf: PPWBuffer;
  Spa: PSpaBuffer;
  Data: PSpaData;
  Offset, Size: LongWord;
begin
  D := TPipeWireDeviceData(ADevice.Hidden);
  Buf := FPW.API.stream_dequeue_buffer(D.Stream);
  if Buf = nil then
    Exit(0);
  Spa := Buf^.Buffer;
  if Spa = nil then
  begin
    FPW.API.stream_queue_buffer(D.Stream, Buf);
    Exit(0);
  end;
  Data := Spa^.Datas;
  Offset := Data^.Chunk^.Offset;
  if Offset > Data^.MaxSize then
    Offset := Data^.MaxSize;
  Size := Data^.Chunk^.Size;
  if Size > Data^.MaxSize - Offset then
    Size := Data^.MaxSize - Offset;
  if Integer(Size) < ALen then
    Result := Integer(Size)
  else
    Result := ALen;
  Move((PByte(Data^.Data) + Offset)^, ABuffer^, Result);
  FPW.API.stream_queue_buffer(D.Stream, Buf);
end;

procedure InputCallback(AData: Pointer); cdecl;
var
  Dev: TPMLAudioDevice;
  D: TPipeWireDeviceData;
begin
  PMLPipeWireCallbackEnter;
  Dev := TPMLAudioDevice(AData);
  D := TPipeWireDeviceData(Dev.Hidden);
  try
    // 準備の途中（OpenDevice がロックを持って待っている）なら捨てる。
    if D.StreamInitStatus <> ReadyAll then
    begin
      D.Backend.StreamFlush(Dev);
      Exit;
    end;
    Dev.Core.RecordingThreadIterate(Dev);
  except
    on E: Exception do
    begin
      D.Backend.NoteError(E, 'input');
      Dev.Core.DeviceDisconnected(Dev);
    end;
  end;
end;

procedure StreamAddBuffer(AData: Pointer; ABuffer: PPWBuffer); cdecl;
var
  Dev: TPMLAudioDevice;
  D: TPipeWireDeviceData;
  MaxSize: LongWord;
begin
  PMLPipeWireCallbackEnter;
  Dev := TPMLAudioDevice(AData);
  D := TPipeWireDeviceData(Dev.Hidden);
  try
    if not Dev.Recording then
    begin
      // 1 回分を PipeWire のバッファの大きさまでに切り詰める（大きければ二重のバッファになる）。
      MaxSize := ABuffer^.Buffer^.Datas^.MaxSize;
      if LongWord(Dev.BufferSize) > MaxSize then
      begin
        Dev.Lock.Lock;
        try
          Dev.SampleFrames := Integer(MaxSize) div D.Stride;
          Dev.BufferSize := Integer(MaxSize);
        finally
          Dev.Lock.Unlock;
        end;
      end;
    end;
    D.StreamInitStatus := D.StreamInitStatus or ReadyBufferAdded;
    D.Backend.FPW.API.thread_loop_signal(D.Loop, False);
  except
    on E: Exception do
      D.Backend.NoteError(E, 'add buffer');
  end;
end;

procedure StreamStateChanged(AData: Pointer; AOld, AState: cint; AError: PChar); cdecl;
var
  Dev: TPMLAudioDevice;
  D: TPipeWireDeviceData;
begin
  PMLPipeWireCallbackEnter;
  Dev := TPMLAudioDevice(AData);
  D := TPipeWireDeviceData(Dev.Hidden);
  try
    if AState = PW_STREAM_STATE_STREAMING then
      D.StreamInitStatus := D.StreamInitStatus or ReadyStreamReady;
    if (AState = PW_STREAM_STATE_STREAMING) or (AState = PW_STREAM_STATE_ERROR) then
      D.Backend.FPW.API.thread_loop_signal(D.Loop, False);
  except
    on E: Exception do
      D.Backend.NoteError(E, 'state changed');
  end;
end;

{ PIPEWIRE_StreamNameChanged。ヒントを置いたスレッドから来る。 }
procedure TPipeWireDeviceData.StreamNameChanged(const AName: String; const AOld, ANew: TPMLHintValue);
var
  Items: array[0..0] of TSpaDictItem;
  Dict: TSpaDict;
  Value: String;
  Old: TFPUExceptionMask;
begin
  if (Stream = nil) or (Loop = nil) then
    Exit;   // まだ準備ができていない
  // メディアの名前をノードの名前と同じにしない（ノードの名前で足りる）。
  if ANew.IsSet and (ANew.Value = NodeName) then
    Exit;
  Value := ANew.Value;
  Items[0].Key := PW_KEY_MEDIA_NAME;
  if ANew.IsSet then
    Items[0].Value := PChar(Value)
  else
    Items[0].Value := nil;
  Dict.Flags := 0;
  Dict.NItems := 1;
  Dict.Items := @Items[0];
  Old := PMLPipeWireMaskBegin;
  Backend.FPW.API.thread_loop_lock(Loop);
  try
    Backend.FPW.API.stream_update_properties(Stream, @Dict);
  finally
    Backend.FPW.API.thread_loop_unlock(Loop);
    PMLPipeWireMaskEnd(Old);
  end;
end;

function TPMLPipeWireBackend.OpenDevice(ADevice: TPMLAudioDevice): Boolean;
var
  Old: TFPUExceptionMask;
begin
  // デバイスのループのスレッドと、PipeWire の中のスレッドが、例外を止めた設定を受け継ぐように。
  Old := PMLPipeWireMaskBegin;
  try
    Result := OpenDeviceMasked(ADevice);
  finally
    PMLPipeWireMaskEnd(Old);
  end;
end;

procedure TPMLPipeWireBackend.CloseDevice(ADevice: TPMLAudioDevice);
var
  Old: TFPUExceptionMask;
begin
  Old := PMLPipeWireMaskBegin;
  try
    CloseDeviceMasked(ADevice);
  finally
    PMLPipeWireMaskEnd(Old);
  end;
end;

{ PIPEWIRE_OpenDevice。 }
function TPMLPipeWireBackend.OpenDeviceMasked(ADevice: TPMLAudioDevice): Boolean;
const
  // PW_STREAM_FLAG_RT_PROCESS は付けない（呼び出しがアプリの中なので、実時間のスレッドでの
  // 禁止事項（記憶の確保・ロック・ファイル）を守れない）。
  StreamFlags = PW_STREAM_FLAG_AUTOCONNECT or PW_STREAM_FLAG_MAP_BUFFERS;
var
  D: TPipeWireDeviceData;
  Params: TBytes;
  ParamPtr: Pointer;
  Props: PPWProperties;
  AppName, IconName, AppId, StreamName, StreamRole, NodeName: String;
  NodeId: LongWord;
  MinPeriod, Res: Integer;
  TimedOut: Boolean;
  Io: TIONode;
  ErrText: PChar;
begin
  Result := False;
  if ADevice.Handle = nil then
    NodeId := PW_ID_ANY
  else
    NodeId := LongWord(PtrUInt(ADevice.Handle));

  // 1 回分の大きさを、まともな値に挟む。
  if ADevice.Spec.Freq div BaseClockRate > 1 then
    MinPeriod := MinSamples * (ADevice.Spec.Freq div BaseClockRate)
  else
    MinPeriod := MinSamples;

  // アプリの名前・アイコン・ID・ストリームの名前と役割（ヒントから）。
  AppName := FCore.Hint(PML_HINT_APP_NAME);
  if AppName = '' then
    AppName := ApplicationName;   // SDL_GetExeName の代わり
  if AppName = '' then
    AppName := 'papimela Application';
  IconName := FCore.Hint(PML_HINT_AUDIO_DEVICE_APP_ICON_NAME);
  if IconName = '' then
    IconName := 'applications-games';
  AppId := FCore.Hint(PML_HINT_APP_ID);
  StreamName := FCore.Hint(PML_HINT_AUDIO_DEVICE_STREAM_NAME);
  if StreamName = '' then
    StreamName := AppName;
  // PipeWire の中の既定は Music だが、papimela のアプリの多くには Game の方が合う。
  StreamRole := FCore.Hint(PML_HINT_AUDIO_DEVICE_STREAM_ROLE);
  if StreamRole = '' then
    StreamRole := 'Game';

  // SDL の形式から PipeWire の形式の param を作る。
  Params := PMLPipeWireBuildFormat(ADevice.Spec, SPA_PARAM_EnumFormat);
  if Length(Params) = 0 then
    raise EPMLAudioError.Create('Pipewire: Failed to set audio format parameters');

  D := TPipeWireDeviceData.Create;
  D.Backend := Self;
  D.Device := ADevice;
  ADevice.Hidden := D;
  D.Stride := ADevice.Spec.FrameSize;
  if ADevice.SampleFrames < MinPeriod then
    ADevice.SampleFrames := MinPeriod;
  FCore.UpdatedDeviceFormat(ADevice);

  D.Loop := FPW.API.thread_loop_new(PChar(FCore.ThreadName(ADevice)), nil);
  if D.Loop = nil then
    raise EPMLAudioError.Create('Pipewire: Failed to create stream loop');

  // 実時間のモジュールを読み込ませる（PipeWire がループのスレッドの優先度を上げる）。
  Props := FPW.API.properties_new(nil);
  if Props = nil then
    raise EPMLAudioError.Create('Pipewire: Failed to create stream context properties');
  FPW.API.properties_set(Props, PW_KEY_CONFIG_NAME, 'client-rt.conf');
  D.Context := FPW.API.context_new(FPW.API.thread_loop_get_loop(D.Loop), Props, 0);
  if D.Context = nil then
    raise EPMLAudioError.Create('Pipewire: Failed to create stream context');

  Props := FPW.API.properties_new(nil);
  if Props = nil then
    raise EPMLAudioError.Create('Pipewire: Failed to create stream properties');
  FPW.API.properties_set(Props, PW_KEY_MEDIA_TYPE, 'Audio');
  if ADevice.Recording then
    FPW.API.properties_set(Props, PW_KEY_MEDIA_CATEGORY, 'Capture')
  else
    FPW.API.properties_set(Props, PW_KEY_MEDIA_CATEGORY, 'Playback');
  FPW.API.properties_set(Props, PW_KEY_MEDIA_ROLE, PChar(StreamRole));
  FPW.API.properties_set(Props, PW_KEY_APP_NAME, PChar(AppName));
  FPW.API.properties_set(Props, PW_KEY_APP_ICON_NAME, PChar(IconName));
  if AppId <> '' then
    FPW.API.properties_set(Props, PW_KEY_APP_ID, PChar(AppId));
  // ノードの名前と説明はアプリ、メディアの名前は今鳴らしているもの。
  NodeName := AppName;
  D.NodeName := NodeName;
  FPW.API.properties_set(Props, PW_KEY_NODE_NAME, PChar(NodeName));
  FPW.API.properties_set(Props, PW_KEY_NODE_DESCRIPTION, PChar(NodeName));
  FPW.API.properties_set(Props, PW_KEY_NODE_LATENCY,
    PChar(Format('%d/%d', [ADevice.SampleFrames, ADevice.Spec.Freq])));
  FPW.API.properties_set(Props, PW_KEY_NODE_RATE, PChar(Format('1/%d', [ADevice.Spec.Freq])));
  FPW.API.properties_set(Props, PW_KEY_NODE_ALWAYS_PROCESS, 'true');
  // アプリの名前と違うときだけ、ストリームの名前を置く（「X - X」と出ないように）。
  if StreamName <> NodeName then
    FPW.API.properties_set(Props, PW_KEY_MEDIA_NAME, PChar(StreamName));
  // PW_KEY_NODE_DONT_RECONNECT は置かない（利用者が別のデバイスへ移せるように。SDL と同じ）。
  if NodeId <> PW_ID_ANY then
  begin
    FPW.API.thread_loop_lock(FHotplugLoop);
    try
      Io := IOListGetById(NodeId);
      if Io <> nil then
        FPW.API.properties_set(Props, PW_KEY_TARGET_OBJECT, PChar(Io.Path));
    finally
      FPW.API.thread_loop_unlock(FHotplugLoop);
    end;
  end;

  // 早めに足す（最初の呼び出しは準備の前に来て、何もしない）。
  if (ContextServices <> nil) and (ContextServices.Hints <> nil) then
  begin
    ContextServices.Hints.AddCallback(PML_HINT_AUDIO_DEVICE_STREAM_NAME, @D.StreamNameChanged);
    D.HintWatched := True;
  end;

  if ADevice.Recording then
    D.Stream := FPW.API.stream_new_simple(FPW.API.thread_loop_get_loop(D.Loop), PChar(StreamName), Props,
      @StreamInputEvents, ADevice)
  else
    D.Stream := FPW.API.stream_new_simple(FPW.API.thread_loop_get_loop(D.Loop), PChar(StreamName), Props,
      @StreamOutputEvents, ADevice);
  if D.Stream = nil then
    raise EPMLAudioError.Create('Pipewire: Failed to create stream');

  // つなぎ先は PW_KEY_TARGET_OBJECT で渡す。target_id は古い引数で、PW_ID_ANY にする。
  ParamPtr := @Params[0];
  if ADevice.Recording then
    Res := FPW.API.stream_connect(D.Stream, PW_DIRECTION_INPUT, PW_ID_ANY, StreamFlags, @ParamPtr, 1)
  else
    Res := FPW.API.stream_connect(D.Stream, PW_DIRECTION_OUTPUT, PW_ID_ANY, StreamFlags, @ParamPtr, 1);
  if Res <> 0 then
    raise EPMLAudioError.Create('Pipewire: Failed to connect stream');

  if FPW.API.thread_loop_start(D.Loop) <> 0 then
    raise EPMLAudioError.Create('Pipewire: Failed to start stream loop');

  // 時間切れ（デバイスが無い）か、開く前の印が揃うか、ストリームが失敗するまで待つ。
  TimedOut := False;
  FPW.API.thread_loop_lock(D.Loop);
  try
    while (not TimedOut) and (D.StreamInitStatus <> ReadyAllPreopen)
      and (FPW.API.stream_get_state(D.Stream, nil) <> PW_STREAM_STATE_ERROR) do
      TimedOut := FPW.API.thread_loop_timed_wait(D.Loop, 2) = ETIMEDOUT;
    D.StreamInitStatus := D.StreamInitStatus or ReadyOpenComplete;
  finally
    FPW.API.thread_loop_unlock(D.Loop);
  end;

  if TimedOut then
    raise EPMLAudioError.Create('Pipewire: timeout waiting for audio device to be ready');
  ErrText := nil;
  if FPW.API.stream_get_state(D.Stream, @ErrText) = PW_STREAM_STATE_ERROR then
    raise EPMLAudioError.Create('Pipewire: Stream error: ' + StrPas(ErrText));
  Result := True;
end;

procedure TPMLPipeWireBackend.CloseDeviceMasked(ADevice: TPMLAudioDevice);
var
  D: TPipeWireDeviceData;
begin
  D := TPipeWireDeviceData(ADevice.Hidden);
  if D = nil then
    Exit;
  if D.HintWatched and (ContextServices <> nil) and (ContextServices.Hints <> nil) then
    ContextServices.Hints.RemoveCallback(PML_HINT_AUDIO_DEVICE_STREAM_NAME, @D.StreamNameChanged);
  // ループを止めてから壊す（ProvidesOwnCallbackThread: ここでデバイスのスレッドを待つ）。
  if D.Loop <> nil then
    FPW.API.thread_loop_stop(D.Loop);
  if D.Stream <> nil then
    FPW.API.stream_destroy(D.Stream);
  if D.Context <> nil then
    FPW.API.context_destroy(D.Context);
  if D.Loop <> nil then
    FPW.API.thread_loop_destroy(D.Loop);
  D.Free;
  ADevice.Hidden := nil;
end;

procedure TPMLPipeWireBackend.DeinitializeStart;
var
  Old: TFPUExceptionMask;
begin
  if FInitialized then
  begin
    Old := PMLPipeWireMaskBegin;
    try
      HotplugLoopDestroy;
    finally
      PMLPipeWireMaskEnd(Old);
    end;
  end;
end;

procedure TPMLPipeWireBackend.Deinitialize;
var
  Old: TFPUExceptionMask;
begin
  Old := PMLPipeWireMaskBegin;
  try
    DeinitializeMasked;
  finally
    PMLPipeWireMaskEnd(Old);
  end;
end;

procedure TPMLPipeWireBackend.DeinitializeMasked;
begin
  if FInitialized then
  begin
    HotplugLoopDestroy;
    FPW.API.deinit();
    FHaveSessionServices := False;
    FHaveAudioService := False;
    FInitialized := False;
  end;
  FreeAndNil(FPW);
end;

function CreatePipeWireBackend(ACore: TPMLAudioCore): TPMLAudioBackend;
begin
  Result := TPMLPipeWireBackend.Create(ACore);
end;

procedure InitEventTables;
begin
  HotplugInitCoreEvents := Default(TPWCoreEvents);
  HotplugInitCoreEvents.Version := PW_VERSION_CORE_EVENTS;
  HotplugInitCoreEvents.Info := @CoreHotplugInfo;
  HotplugInitCoreEvents.Done := @CoreHotplugInitDone;

  InterfaceCoreEvents := Default(TPWCoreEvents);
  InterfaceCoreEvents.Version := PW_VERSION_CORE_EVENTS;
  InterfaceCoreEvents.Done := @CoreInterfaceDone;

  GenericCoreEvents := Default(TPWCoreEvents);
  GenericCoreEvents.Version := PW_VERSION_CORE_EVENTS;
  GenericCoreEvents.Done := @CoreGenericDone;

  InterfaceNodeEvents := Default(TPWNodeEvents);
  InterfaceNodeEvents.Version := PW_VERSION_NODE_EVENTS;
  InterfaceNodeEvents.Info := @NodeEventInfo;
  InterfaceNodeEvents.Param := @NodeEventParam;

  MetadataNodeEvents := Default(TPWMetadataEvents);
  MetadataNodeEvents.Version := PW_VERSION_METADATA_EVENTS;
  MetadataNodeEvents.Property_ := @MetadataProperty;

  ClientNodeEvents := Default(TPWClientEvents);
  ClientNodeEvents.Version := PW_VERSION_CLIENT_EVENTS;
  ClientNodeEvents.Info := @ClientInfo;

  RegistryEvents := Default(TPWRegistryEvents);
  RegistryEvents.Version := PW_VERSION_REGISTRY_EVENTS;
  RegistryEvents.Global := @RegistryGlobal;
  RegistryEvents.GlobalRemove := @RegistryGlobalRemove;

  StreamOutputEvents := Default(TPWStreamEvents);
  StreamOutputEvents.Version := PW_VERSION_STREAM_EVENTS;
  StreamOutputEvents.StateChanged := @StreamStateChanged;
  StreamOutputEvents.AddBuffer := @StreamAddBuffer;
  StreamOutputEvents.Process := @OutputCallback;

  StreamInputEvents := StreamOutputEvents;
  StreamInputEvents.Process := @InputCallback;
end;

initialization
  InitEventTables;
  PMLRegisterAudioBackend('pipewire', 100, @CreatePipeWireBackend);

end.
