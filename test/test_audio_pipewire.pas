{
  test_audio_pipewire — PipeWire のオーディオバックエンド（手元の PipeWire で動かす）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 'pipewire' を選べる
    2. 再生・録音のデバイスの名前の並びが、pw-dump のシンク・ソース（node.description）と同じ。
       既定のデバイスが pw-dump のメタデータ default.audio.sink と同じ。形式は S16（SDL と同じく
       形式は読まない）、チャンネル数と周波数は pw-dump のノードの値、1 回分のフレーム数は周波数から
    3. 最初の Poll で、どのデバイスにも追加のイベント
    4. 既定の再生を F32 2ch 48000 で開く（簡易パス）: F32 で開く（D-66）、OnGet が来る、最初の量は
       8192 バイト（SDL と同じ）
    5. 開いている間のストリームのノード（pw-dump）: アプリ名・アイコン・役割・種類・遅延・周波数・
       つなぎ先・ループの名前が SDL の作るものと同じ形。ヒント STREAM_NAME を変えると media.name が変わる
    6. 閉じるとノードが消える
    7. hotplug: 一時の無音のシンク（pw-cli で作る。既定は奪わない）が足されると追加のイベント、
       名指しで開いてつなぎ先がそのシンクになる、消すと削除のイベント（物理と論理）、失われても進み続ける
    8. 録音のデバイスがあれば、開いてデータが入る（無ければ飛ばす）
    9. ストリームを開いたまま Context を壊せる
    10. PipeWire のスレッドが、浮動小数点の例外を止めた設定で来る（スパイク 4）

  WHY:
    オーディオの 3 段目（#56）の受け入れ検査。期待値は pw-dump と、SDL（main・PipeWire 付き）を
    同じ機械で動かした実測（docs/TEST-LOG.md の使い捨て検証）。音は無音しか流さない。

  実行前提: PipeWire（pipewire と wireplumber）が動いている、pw-dump と pw-cli がある、cthreads。
  手元専用。PipeWire が無い環境では PAPIMELA_PIPEWIRE_OPTIONAL=1 で全部飛ばす（既定では失敗にする）。
  hotplug の場面は一時のシンク pml-test-sink を足して消す（object.linger、priority.session=0）。
  止まったら見張りが 90 秒で失敗として終わらせる。
}
program test_audio_pipewire;

{$mode objfpc}{$H+}
{$scopedenums on}
{$modeswitch nestedprocvars}

uses
  cthreads,
  SysUtils, Classes, BaseUnix, Process, fpjson, jsonparser,
  PaPiMeLa.Threading,
  PaPiMeLa.Properties,
  PaPiMeLa.Log,
  PaPiMeLa.Events,
  PaPiMeLa.Core,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Stream,
  PaPiMeLa.Audio.Backend,
  PaPiMeLa.Audio,
  PaPiMeLa.Platform.PipeWire,
  PaPiMeLa.Audio.PipeWire;

const
  AppName = 'PmlPipeWireTest';
  TestSinkName = 'pml-test-sink';
  TestSinkDescription = 'PML Test Sink';

var
  Failures: Integer = 0;
  SkippedError: String = '';   // 飛ばした例外の最後のもの（調べるとき用）

procedure Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
    WriteLn('  [PASS] ', ALabel)
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(Failures);
  end;
end;

type
  TWatchdog = class(TPMLThread)
  public
    LimitMs: Integer;
  protected
    function Run: Integer; override;
  end;

function TWatchdog.Run: Integer;
var
  Waited: Integer;
begin
  Waited := 0;
  while (Waited < LimitMs) and not Terminated do
  begin
    Sleep(50);
    Inc(Waited, 50);
  end;
  if not Terminated then
  begin
    WriteLn('  [FAIL] ', LimitMs div 1000, ' 秒たっても終わらない（どこかで止まっている）');
    WriteLn('=== 止まった ===');
    Flush(Output);
    // 一時のシンクを残さない
    ExecuteProcess('/bin/sh', ['-c', 'for i in $(pw-dump | grep -B30 ''"node.name": "' + TestSinkName +
      '"'' | grep ''"id"'' | grep -o ''[0-9]*''); do pw-cli destroy $i; done'], []);
    FpExit(3);
  end;
  Result := 0;
end;

{ ---- pw-dump ---- }

{ pw-dump は、ストリームのタグが付いたシンクの Tag パラメータで "info": [...] を 2 度出す
  （PipeWire 1.6.2 で実測。fpjson は同じ鍵を受け付けず、FPC 3.2.2 の joIgnoreDuplicates は
  値が配列のときに読み誤る）。配列の値の "info" だけ、通し番号を付けた鍵に書き換えてから読む。 }
function RenameArrayInfo(const AText: String): String;
const
  Needle = '"info": [';
var
  P, N: SizeInt;
  Rest: String;
begin
  Result := '';
  Rest := AText;
  N := 0;
  P := Pos(Needle, Rest);
  while P > 0 do
  begin
    Inc(N);
    Result := Result + Copy(Rest, 1, P - 1) + '"info#' + IntToStr(N) + '": [';
    Delete(Rest, 1, P - 1 + Length(Needle));
    P := Pos(Needle, Rest);
  end;
  Result := Result + Rest;
end;

{ 取り出しの最中にオブジェクトが変わって読めないことがあれば、5 回まで取り直す。 }
function PwDump: TJSONArray;
var
  Output: String;
  Data: TJSONData;
  Attempt: Integer;
begin
  Result := nil;
  for Attempt := 1 to 5 do
  begin
    Output := '';
    if not RunCommand('pw-dump', [], Output, [poNoConsole]) then
      Exit;
    Output := RenameArrayInfo(Output);
    try
      Data := GetJSON(Output);
    except
      on E: Exception do
      begin
        SkippedError := 'pw-dump: ' + E.Message;
        Sleep(100);
        Continue;
      end;
    end;
    if Data is TJSONArray then
      Exit(TJSONArray(Data));
    Data.Free;
  end;
end;

function Props(AObj: TJSONObject): TJSONObject;
var
  Info: TJSONData;
begin
  Result := nil;
  Info := AObj.Find('info');
  if (Info is TJSONObject) and (TJSONObject(Info).Find('props') is TJSONObject) then
    Result := TJSONObject(TJSONObject(Info).Find('props'));
end;

function PropStr(AObj: TJSONObject; const AKey: String): String;
var
  P: TJSONObject;
  D: TJSONData;
begin
  Result := '';
  P := Props(AObj);
  if P = nil then
    Exit;
  D := P.Find(AKey);
  if D <> nil then
    Result := D.AsString;
end;

function IsNode(AObj: TJSONObject): Boolean;
begin
  Result := AObj.Get('type', '') = 'PipeWire:Interface:Node';
end;

{ ノードのはじめの EnumFormat の値（AKey）。範囲なら既定の値。無ければ 0。 }
function EnumFormatInt(AObj: TJSONObject; const AKey: String; out AIsRange: Boolean): Integer;
var
  Info, Params, EF, V: TJSONData;
begin
  Result := 0;
  AIsRange := False;
  Info := AObj.Find('info');
  if not (Info is TJSONObject) then
    Exit;
  Params := TJSONObject(Info).Find('params');
  if not (Params is TJSONObject) then
    Exit;
  EF := TJSONObject(Params).Find('EnumFormat');
  if not ((EF is TJSONArray) and (TJSONArray(EF).Count > 0) and (TJSONArray(EF)[0] is TJSONObject)) then
    Exit;
  V := TJSONObject(TJSONArray(EF)[0]).Find(AKey);
  if V is TJSONNumber then
    Result := V.AsInteger
  else if (V is TJSONObject) and (TJSONObject(V).Find('default') is TJSONNumber)
    and (TJSONObject(V).Find('min') <> nil) then
  begin
    Result := TJSONObject(V).Find('default').AsInteger;
    AIsRange := True;
  end;
end;

{ メタデータ default の AKey（default.audio.sink など）の name。 }
function DefaultNodeName(ADump: TJSONArray; const AKey: String): String;
var
  I, J: Integer;
  O: TJSONObject;
  Md: TJSONData;
  E: TJSONObject;
begin
  Result := '';
  for I := 0 to ADump.Count - 1 do
  begin
    if not (ADump[I] is TJSONObject) then
      Continue;
    O := TJSONObject(ADump[I]);
    if (O.Get('type', '') <> 'PipeWire:Interface:Metadata') or not (O.Find('props') is TJSONObject)
      or (TJSONObject(O.Find('props')).Get('metadata.name', '') <> 'default') then
      Continue;
    Md := O.Find('metadata');
    if not (Md is TJSONArray) then
      Continue;
    for J := 0 to TJSONArray(Md).Count - 1 do
      if TJSONArray(Md)[J] is TJSONObject then
      begin
        E := TJSONObject(TJSONArray(Md)[J]);
        if (E.Get('key', '') = AKey) and (E.Find('value') is TJSONObject) then
          Result := TJSONObject(E.Find('value')).Get('name', '');
      end;
  end;
end;

{ SDL と同じく、クラスが合い、description と name のあるノード。 }
function DeviceNodes(ADump: TJSONArray; ARecording: Boolean): TJSONArray;
var
  I: Integer;
  O: TJSONObject;
  C: String;
  Wanted: Boolean;
begin
  Result := TJSONArray.Create;
  for I := 0 to ADump.Count - 1 do
  begin
    if not ((ADump[I] is TJSONObject) and IsNode(TJSONObject(ADump[I]))) then
      Continue;
    O := TJSONObject(ADump[I]);
    C := LowerCase(PropStr(O, 'media.class'));
    if ARecording then
      Wanted := (C = 'audio/source') or (C = 'audio/source/virtual')
    else
      Wanted := C = 'audio/sink';
    if Wanted and (PropStr(O, 'node.description') <> '') and (PropStr(O, 'node.name') <> '') then
      Result.Add(O.Clone);
  end;
end;

function FindStreamNode(ADump: TJSONArray; const AClass: String): TJSONObject;
var
  I: Integer;
  O: TJSONObject;
begin
  Result := nil;
  for I := 0 to ADump.Count - 1 do
    if (ADump[I] is TJSONObject) and IsNode(TJSONObject(ADump[I])) then
    begin
      O := TJSONObject(ADump[I]);
      if (PropStr(O, 'application.name') = AppName) and (PropStr(O, 'media.class') = AClass) then
        Exit(O);
    end;
end;

function NodeIdByName(const AName: String): Integer;
var
  Dump: TJSONArray;
  I: Integer;
begin
  Result := -1;
  Dump := PwDump;
  if Dump = nil then
    Exit;
  try
    for I := 0 to Dump.Count - 1 do
      if (Dump[I] is TJSONObject) and IsNode(TJSONObject(Dump[I]))
        and (PropStr(TJSONObject(Dump[I]), 'node.name') = AName) then
        Exit(TJSONObject(Dump[I]).Get('id', -1));
  finally
    Dump.Free;
  end;
end;

procedure RemoveTestSink;
var
  Id: Integer;
  Output: String;
begin
  Id := NodeIdByName(TestSinkName);
  while Id >= 0 do
  begin
    RunCommand('pw-cli', ['destroy', IntToStr(Id)], Output, [poNoConsole]);
    Sleep(200);
    Id := NodeIdByName(TestSinkName);
  end;
end;

{ ---- イベント ---- }

type
  TEventList = array of TPMLEvent;
  TCondFunc = function: Boolean is nested;

function WaitFor(ACond: TCondFunc; AMs: Integer): Boolean;
var
  Waited: Integer;
begin
  Waited := 0;
  while not ACond() do
  begin
    if Waited >= AMs then
      Exit(False);
    Sleep(10);
    Inc(Waited, 10);
  end;
  Result := True;
end;

procedure Collect(ACtx: TPMLContext; var AList: TEventList);
var
  Ev: TPMLEvent;
begin
  while ACtx.Events.Poll(Ev) do
  begin
    SetLength(AList, Length(AList) + 1);
    AList[High(AList)] := Ev;
  end;
end;

function HasEvent(const AList: TEventList; AKind: TPMLEventKind; AID: LongWord): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(AList) do
    if (AList[I].Kind = AKind) and (AList[I].AudioDevice.Which = AID) then
      Exit(True);
  Result := False;
end;

type
  TFeeder = class
  public
    Calls: LongInt;
    FirstAdd, FirstTotal: Integer;
    procedure OnGet(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
    procedure OnPut(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
  end;

procedure TFeeder.OnGet(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
var
  Zeros: array of Byte;
begin
  if InterLockedIncrement(Calls) = 1 then
  begin
    FirstAdd := AAdditional;
    FirstTotal := ATotal;
  end;
  if AAdditional > 0 then
  begin
    Zeros := nil;
    SetLength(Zeros, AAdditional);
    AStream.PutData(@Zeros[0], AAdditional);
  end;
end;

procedure TFeeder.OnPut(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
begin
  InterLockedIncrement(Calls);
end;

function SameSpec(const A: TPMLAudioSpec; AFormat: TPMLAudioFormat; AChannels, AFreq: Integer): Boolean;
begin
  Result := (A.Format = AFormat) and (A.Channels = AChannels) and (A.Freq = AFreq);
end;

function SpecText(const A: TPMLAudioSpec): String;
begin
  Result := Format('%s %dch %d', [PMLAudioFormatName(A.Format), A.Channels, A.Freq]);
end;

function FramesFor(AFreq: Integer): Integer;
begin
  if AFreq <= 22050 then
    Result := 512
  else if AFreq <= 48000 then
    Result := 1024
  else if AFreq <= 96000 then
    Result := 2048
  else
    Result := 4096;
end;

{ ---- 本体 ---- }

procedure TestDevices(ACtx: TPMLContext; ADump: TJSONArray; ARecording: Boolean);
var
  Nodes: TJSONArray;
  IDs: TPMLAudioDeviceIDs;
  Names, Expected: TStringList;
  I, J, Frames, Ch, Freq: Integer;
  IsRange: Boolean;
  Spec: TPMLAudioSpec;
  O: TJSONObject;
  What: String;
  AllOk: Boolean;
begin
  if ARecording then
  begin
    What := '録音';
    IDs := ACtx.Audio.RecordingDevices;
  end
  else
  begin
    What := '再生';
    IDs := ACtx.Audio.PlaybackDevices;
  end;
  Nodes := DeviceNodes(ADump, ARecording);
  Names := TStringList.Create;
  Expected := TStringList.Create;
  try
    for I := 0 to High(IDs) do
      Names.Add(ACtx.Audio.DeviceName(IDs[I]));
    for I := 0 to Nodes.Count - 1 do
      Expected.Add(PropStr(TJSONObject(Nodes[I]), 'node.description'));
    Names.Sort;
    Expected.Sort;
    Check(Names.Text = Expected.Text, Format('%sのデバイスの名前が pw-dump と同じ（%d 個: %s）',
      [What, Names.Count, StringReplace(Trim(Names.Text), LineEnding, ' / ', [rfReplaceAll])]));

    // 形式: SDL は形式を読まない（S16）。チャンネル数はノードの audio.channels か EnumFormat、
    // 周波数は EnumFormat の範囲の既定（範囲でなければ読まないので 44100 / 録音も 44100）。
    AllOk := True;
    for I := 0 to High(IDs) do
    begin
      // 名前でノードを引く
      O := nil;
      for J := 0 to Nodes.Count - 1 do
        if PropStr(TJSONObject(Nodes[J]), 'node.description') = ACtx.Audio.DeviceName(IDs[I]) then
          O := TJSONObject(Nodes[J]);
      if O = nil then
      begin
        AllOk := False;
        Continue;
      end;
      Ch := StrToIntDef(PropStr(O, 'audio.channels'), 0);
      if Ch = 0 then
        Ch := EnumFormatInt(O, 'channels', IsRange);
      if Ch = 0 then
        if ARecording then
          Ch := 1
        else
          Ch := 2;
      Freq := EnumFormatInt(O, 'rate', IsRange);
      if not IsRange then
        Freq := 44100;
      Spec := ACtx.Audio.DeviceFormat(IDs[I], Frames);
      if not (SameSpec(Spec, PML_AUDIO_S16, Ch, Freq) and (Frames = FramesFor(Freq))) then
      begin
        AllOk := False;
        WriteLn('    ', ACtx.Audio.DeviceName(IDs[I]), ': ', SpecText(Spec), ' ', Frames,
          '（期待 S16 ', Ch, 'ch ', Freq, ' ', FramesFor(Freq), '）');
      end;
    end;
    Check(AllOk, What + 'のデバイスの形式が pw-dump のノードの値と同じ（形式は S16、フレーム数は周波数から）');
  finally
    Names.Free;
    Expected.Free;
    Nodes.Free;
  end;
end;

procedure TestMain;
var
  Opts: TPMLContextOptions;
  Ctx: TPMLContext;
  Dump: TJSONArray;
  Evs: TEventList;
  IDs: TPMLAudioDeviceIDs;
  I, Frames: Integer;
  AllAdded: Boolean;
  DefSink, DefSinkDesc, Output: String;
  Feeder, RecFeeder: TPMLAudioStream;
  F, RF: TFeeder;
  L: TPMLLogicalAudioDevice;
  Node: TJSONObject;
  PhysID, SinkID, LogID: TPMLAudioDeviceID;
  SinkStream: TPMLAudioStream;
  Buf: array of Byte;

  function FedTen: Boolean;
  begin
    Result := F.Calls >= 10;
  end;

  function RecFed: Boolean;
  begin
    Result := RecFeeder.Available > 0;
  end;

  function SinkAdded: Boolean;
  var
    J: Integer;
  begin
    Collect(Ctx, Evs);
    Result := False;
    for J := 0 to High(Evs) do
      if (Evs[J].Kind = TPMLEventKind.AudioDeviceAdded)
        and TPMLAudioSystem.IsPhysicalDevice(Evs[J].AudioDevice.Which) then
      try
        if Ctx.Audio.DeviceName(Evs[J].AudioDevice.Which) = TestSinkDescription then
        begin
          SinkID := Evs[J].AudioDevice.Which;
          Exit(True);
        end;
      except
        // 消えた ID は飛ばす（何が起きたかだけ残す）
        on E: Exception do
          SkippedError := E.Message;
      end;
  end;

  function SinkRemoved: Boolean;
  begin
    Collect(Ctx, Evs);
    Result := HasEvent(Evs, TPMLEventKind.AudioDeviceRemoved, SinkID)
      and HasEvent(Evs, TPMLEventKind.AudioDeviceRemoved, LogID);
  end;

  function StreamNodeGone: Boolean;
  var
    D: TJSONArray;
  begin
    D := PwDump;
    try
      Result := (D <> nil) and (FindStreamNode(D, 'Stream/Output/Audio') = nil);
    finally
      D.Free;
    end;
  end;

  function SinkDrained: Boolean;
  begin
    Result := SinkStream.Queued = 0;
  end;

begin
  Opts := TPMLContextOptions.Default;
  Opts.PreferredAudio := 'pipewire';
  Opts.MinimumLogLevel := TPMLLogPriority.Critical;
  Opts.Hints.Add(PML_HINT_APP_NAME, AppName);
  WriteLn('-- バックエンド');
  Ctx := TPMLContext.Create([TPMLSubsystem.Audio], Opts);
  try
    Check(Ctx.Audio.BackendName = 'pipewire', 'pipewire を選べる（' + Ctx.Audio.BackendName + '）');

    WriteLn('-- デバイス');
    Dump := PwDump;
    Check(Dump <> nil, 'pw-dump が読める');
    if Dump = nil then
      Exit;
    try
      TestDevices(Ctx, Dump, False);
      TestDevices(Ctx, Dump, True);
      DefSink := DefaultNodeName(Dump, 'default.audio.sink');
      DefSinkDesc := '';
      Node := nil;
      for I := 0 to Dump.Count - 1 do
        if (Dump[I] is TJSONObject) and IsNode(TJSONObject(Dump[I]))
          and (PropStr(TJSONObject(Dump[I]), 'node.name') = DefSink) then
          DefSinkDesc := PropStr(TJSONObject(Dump[I]), 'node.description');
      Check((DefSinkDesc <> '') and (Ctx.Audio.DeviceName(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK) = DefSinkDesc),
        '既定の再生が pw-dump の default.audio.sink と同じ（' + DefSinkDesc + '）');
    finally
      Dump.Free;
    end;

    Evs := nil;
    Collect(Ctx, Evs);
    IDs := Ctx.Audio.PlaybackDevices;
    AllAdded := Length(IDs) > 0;
    for I := 0 to High(IDs) do
      if not HasEvent(Evs, TPMLEventKind.AudioDeviceAdded, IDs[I]) then
        AllAdded := False;
    Check(AllAdded, '最初の Poll で、再生のデバイスごとに追加のイベント');

    WriteLn('-- 再生（簡易パス）');
    F := TFeeder.Create;
    Feeder := Ctx.Audio.OpenDeviceStream(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK,
      TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000), @F.OnGet);
    L := Ctx.Audio.StreamDevice(Feeder);
    PhysID := 0;
    for I := 0 to High(IDs) do
      if Ctx.Audio.DeviceName(IDs[I]) = DefSinkDesc then
        PhysID := IDs[I];
    Check(SameSpec(L.Format, PML_AUDIO_F32, 2, 48000) and (L.SampleFrames = 1024),
      '求めた F32 2ch 48000 で開く（D-66。SDL の main は S16）: ' + SpecText(L.Format));
    Check(Ctx.Audio.StreamDevicePaused(Feeder), '一時停止で始まる');
    Ctx.Audio.ResumeStreamDevice(Feeder);
    Check(WaitFor(@FedTen, 3000), 'OnGet が 10 回以上来る');
    Check((F.FirstAdd = 8192) and (F.FirstTotal = 8192),
      Format('最初の OnGet の量は 8192 / 8192（SDL と同じ: %d / %d）', [F.FirstAdd, F.FirstTotal]));

    Dump := PwDump;
    try
      Node := FindStreamNode(Dump, 'Stream/Output/Audio');
      Check(Node <> nil, 'ストリームのノードがある');
      if Node <> nil then
      begin
        Check(PropStr(Node, 'application.icon-name') = 'applications-games', 'application.icon-name');
        Check((PropStr(Node, 'media.role') = 'Game') and (PropStr(Node, 'media.category') = 'Playback')
          and (PropStr(Node, 'media.type') = 'Audio'), 'media.role / category / type');
        Check((PropStr(Node, 'node.name') = AppName) and (PropStr(Node, 'node.description') = AppName)
          and (PropStr(Node, 'media.name') = AppName), 'node.name / description / media.name はアプリ名');
        Check((PropStr(Node, 'node.latency') = '1024/48000') and (PropStr(Node, 'node.rate') = '1/48000'),
          'node.latency / node.rate: ' + PropStr(Node, 'node.latency') + ' ' + PropStr(Node, 'node.rate'));
        // pw-dump はこの値を JSON の真偽値で出す（AsString は True）。
        Check(LowerCase(PropStr(Node, 'node.always-process')) = 'true', 'node.always-process');
        Check(PropStr(Node, 'target.object') = DefSink, 'target.object は既定のシンク');
        Check(PropStr(Node, 'node.loop.name') = 'PMLAudioP' + IntToStr(PhysID),
          'node.loop.name はデバイスのスレッドの名前: ' + PropStr(Node, 'node.loop.name'));
      end;
    finally
      Dump.Free;
    end;

    Ctx.Hints.SetHint(PML_HINT_AUDIO_DEVICE_STREAM_NAME, 'Music Track');
    Sleep(300);
    Dump := PwDump;
    try
      Node := FindStreamNode(Dump, 'Stream/Output/Audio');
      Check((Node <> nil) and (PropStr(Node, 'media.name') = 'Music Track'),
        'ヒント STREAM_NAME を変えると media.name が変わる');
    finally
      Dump.Free;
    end;

    Feeder.Free;
    Check(WaitFor(@StreamNodeGone, 2000), '閉じるとストリームのノードが消える');
    F.Free;

    WriteLn('-- hotplug（一時の無音のシンク）');
    RemoveTestSink;
    Evs := nil;
    Collect(Ctx, Evs);
    Evs := nil;
    SinkID := 0;
    LogID := 0;
    RunCommand('pw-cli', ['create-node', 'adapter', '{ factory.name=support.null-audio-sink node.name=' +
      TestSinkName + ' node.description="' + TestSinkDescription + '" media.class=Audio/Sink ' +
      'audio.position=[FL FR] object.linger=true priority.session=0 priority.driver=0 }'], Output, [poNoConsole]);
    try
      Check(WaitFor(@SinkAdded, 3000), '足されたシンクの追加のイベント');
      if SinkID <> 0 then
      begin
        Check(Ctx.Audio.DeviceName(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK) = DefSinkDesc, '既定は変わらない');
        L := Ctx.Audio.OpenDevice(SinkID, TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000));
        LogID := L.ID;
        SinkStream := TPMLAudioStream.Create(TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000),
          TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000));
        Buf := nil;
        SetLength(Buf, 48000 * 8);
        SinkStream.PutData(@Buf[0], Length(Buf));
        L.BindStream(SinkStream);
        Sleep(300);
        Dump := PwDump;
        try
          Node := FindStreamNode(Dump, 'Stream/Output/Audio');
          Check((Node <> nil) and (PropStr(Node, 'target.object') = TestSinkName),
            '名指しで開くと target.object がそのシンク');
        finally
          Dump.Free;
        end;
        RemoveTestSink;
        Check(WaitFor(@SinkRemoved, 3000), '消すと、物理と論理の削除のイベント');
        IDs := Ctx.Audio.PlaybackDevices;
        AllAdded := True;
        for I := 0 to High(IDs) do
          if IDs[I] = SinkID then
            AllAdded := False;
        Check(AllAdded, '一覧から消える');
        Check(WaitFor(@SinkDrained, 3000), '失われた論理デバイスも進み続ける（無音として）');
        L.Free;
        SinkStream.Free;
      end;
    finally
      RemoveTestSink;
    end;

    WriteLn('-- 録音');
    if Length(Ctx.Audio.RecordingDevices) = 0 then
      WriteLn('  [SKIP] 録音のデバイスが無い')
    else
    begin
      RF := TFeeder.Create;
      RecFeeder := Ctx.Audio.OpenDeviceStream(PML_AUDIO_DEVICE_DEFAULT_RECORDING,
        TPMLAudioSpec.Make(PML_AUDIO_S16, 1, 48000), @RF.OnPut);
      Ctx.Audio.ResumeStreamDevice(RecFeeder);
      Check(WaitFor(@RecFed, 3000), '録音のデータが入る');
      RecFeeder.Free;
      RF.Free;
    end;

    WriteLn('-- 開いたまま壊す');
    F := TFeeder.Create;
    Feeder := Ctx.Audio.OpenDeviceStream(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK,
      TPMLAudioSpec.Make(PML_AUDIO_S16, 2, 44100), @F.OnGet);
    Ctx.Audio.ResumeStreamDevice(Feeder);
    WaitFor(@FedTen, 3000);
  finally
    Ctx.Free;
  end;
  Check(Feeder.Binding.Device = nil, 'Context を壊すと結び付けが外れる');
  Feeder.Free;
  F.Free;
end;

var
  Dog: TWatchdog;
  Output: String;
begin
  WriteLn('=== test_audio_pipewire ===');
  if not RunCommand('pw-cli', ['info', '0'], Output, [poNoConsole]) then
  begin
    if GetEnvironmentVariable('PAPIMELA_PIPEWIRE_OPTIONAL') = '1' then
    begin
      WriteLn('  [SKIP] PipeWire が動いていない（PAPIMELA_PIPEWIRE_OPTIONAL=1）');
      Halt(0);
    end;
    WriteLn('  [FAIL] PipeWire に繋がらない（pw-cli info 0。無い環境では PAPIMELA_PIPEWIRE_OPTIONAL=1）');
    Halt(1);
  end;
  Dog := TWatchdog.Create('watchdog', True);
  Dog.LimitMs := 90000;
  Dog.Start;
  try
    TestMain;
  except
    on E: Exception do
    begin
      WriteLn('  [FAIL] 例外: ', E.ClassName, ': ', E.Message);
      Inc(Failures);
    end;
  end;
  // PipeWire のスレッドが、例外を止めた設定を受け継いでいる（入口で有効だったことが無い）。
  Check(PMLPipeWireUnmaskedEntries = 0, Format('PipeWire の呼び出しの入口で、浮動小数点の例外が有効だった回数が 0（%d）',
    [PMLPipeWireUnmaskedEntries]));
  RemoveTestSink;
  Dog.Terminate;
  Dog.WaitFor;
  Dog.Free;
  if Failures = 0 then
    WriteLn('=== 全部通った ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
