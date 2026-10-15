{
  test_audio_pulse — PulseAudio のオーディオバックエンド（手元の PulseAudio のサーバで動かす）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 'pulseaudio' を選べる
    2. 再生・録音のデバイスの名前の並びが、pactl のシンク・ソース（description）と同じ（モニターは
       入れない）。形式・チャンネル数・周波数が sample_specification と同じ（扱えない形式は S16）。
       既定の再生・録音が pactl の default_sink_name / default_source_name と同じ。ヒント
       INCLUDE_MONITORS を立てると、モニターも録音のデバイスに入る
    3. 最初の Poll で、どのデバイスにも追加のイベント
    4. hotplug: 一時の無音のシンク（pactl で作る。既定は奪わない）が足されると追加のイベント、
       名指しで開いて 440 Hz の正弦波（F32 2ch 48000）を鳴らし、parec でそのシンクのモニターを
       録って、振幅と周波数が合う。開いている間のシンクの入力（pactl）: アプリ名・アイコン・
       つなぎ先・ストリーム名のヒント。消すと削除のイベント（物理と論理）、失われても進み続ける
    5. 扱えない形式（S8）で開くと近い形式（F32）になる
    6. モニターを録音のデバイスとして開いて、データが入る
    7. ストリームを開いたまま Context を壊せる
    8. PulseAudio のスレッドが、浮動小数点の例外を止めた設定で来る

  WHY:
    オーディオの残りの #57（Audio.Pulse）の受け入れ検査。期待値は pactl と parec。音は、利用者の
    スピーカーには流さない（一時の無音のシンクだけを鳴らす）。

  実行前提: PulseAudio のサーバ（pipewire-pulse でもよい）が動いている、pactl と parec がある、cthreads。
  手元専用。サーバが無い環境では PAPIMELA_PULSE_OPTIONAL=1 で全部飛ばす（既定では失敗にする）。
  hotplug の場面は一時のシンク pml-test-sink を足して消す。止まったら見張りが 90 秒で失敗として終わらせる。
}
program test_audio_pulse;

{$mode objfpc}{$H+}
{$scopedenums on}
{$modeswitch nestedprocvars}

uses
  cthreads,
  SysUtils, Classes, BaseUnix, Process, Math, fpjson, jsonparser,
  PaPiMeLa.Threading,
  PaPiMeLa.Properties,
  PaPiMeLa.Log,
  PaPiMeLa.Events,
  PaPiMeLa.Core,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Stream,
  PaPiMeLa.Audio.Backend,
  PaPiMeLa.Audio,
  PaPiMeLa.Platform.Pulse,
  PaPiMeLa.Audio.Pulse;

const
  AppName = 'PmlPulseTest';
  TestSinkName = 'pml-test-sink';
  TestSinkDescription = 'PMLTestSink';

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
  Flush(Output);
end;

{ ---- pactl ---- }

type
  TWatchdog = class(TPMLThread)
  public
    LimitMs: Integer;
  protected
    function Run: Integer; override;
  end;

procedure RemoveTestSink; forward;

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
    RemoveTestSink;
    FpExit(3);
  end;
  Result := 0;
end;

function Pactl(const AArgs: array of String; out AOutput: String): Boolean;
begin
  AOutput := '';
  Result := RunCommand('pactl', AArgs, AOutput, [poNoConsole]);
end;

function PactlJson(const AWhat: String): TJSONData;
var
  Output: String;
  Ok: Boolean;
begin
  Result := nil;
  if AWhat = 'info' then
    Ok := Pactl(['--format=json', 'info'], Output)
  else
    Ok := Pactl(['--format=json', 'list', AWhat], Output);
  if not Ok then
    Exit;
  try
    Result := GetJSON(Output);
  except
    on E: Exception do
      SkippedError := 'pactl ' + AWhat + ': ' + E.Message;
  end;
end;

function Str(AObj: TJSONObject; const AKey: String): String;
begin
  Result := AObj.Get(AKey, '');
end;

{ "float32le 2ch 48000Hz" を PML の形式に。扱えない形式は 0。 }
procedure ParseSpec(const AText: String; out AFormat: TPMLAudioFormat; out AChannels, AFreq: Integer);
var
  Parts: TStringList;
  F: String;
begin
  AFormat := PML_AUDIO_UNKNOWN;
  AChannels := 0;
  AFreq := 0;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := AText;
    if Parts.Count <> 3 then
      Exit;
    F := Parts[0];
    if F = 'u8' then AFormat := PML_AUDIO_U8
    else if F = 's16le' then AFormat := PML_AUDIO_S16LE
    else if F = 's16be' then AFormat := PML_AUDIO_S16BE
    else if F = 's32le' then AFormat := PML_AUDIO_S32LE
    else if F = 's32be' then AFormat := PML_AUDIO_S32BE
    else if F = 'float32le' then AFormat := PML_AUDIO_F32LE
    else if F = 'float32be' then AFormat := PML_AUDIO_F32BE;
    AChannels := StrToIntDef(Copy(Parts[1], 1, Length(Parts[1]) - 2), 0);
    AFreq := StrToIntDef(Copy(Parts[2], 1, Length(Parts[2]) - 2), 0);
  finally
    Parts.Free;
  end;
end;

function IsMonitor(AObj: TJSONObject): Boolean;
var
  N: String;
begin
  N := Str(AObj, 'name');
  Result := (Length(N) > 8) and (Copy(N, Length(N) - 7, 8) = '.monitor');
end;

function SinkIndexByName(const AName: String): Integer;
var
  Data: TJSONData;
  I: Integer;
begin
  Result := -1;
  Data := PactlJson('sinks');
  if not (Data is TJSONArray) then
  begin
    Data.Free;
    Exit;
  end;
  try
    for I := 0 to TJSONArray(Data).Count - 1 do
      if Str(TJSONObject(TJSONArray(Data)[I]), 'name') = AName then
        Exit(TJSONObject(TJSONArray(Data)[I]).Get('index', -1));
  finally
    Data.Free;
  end;
end;

procedure RemoveTestSink;
var
  Output, Line: String;
  Lines: TStringList;
  I, P: Integer;
  Dummy: String;
begin
  if not Pactl(['list', 'short', 'modules'], Output) then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Lines[I];
      if Pos('sink_name=' + TestSinkName, Line) > 0 then
      begin
        P := Pos(#9, Line);
        if P > 1 then
          Pactl(['unload-module', Copy(Line, 1, P - 1)], Dummy);
      end;
    end;
  finally
    Lines.Free;
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
  { 正弦波を送る（OnGet）。 }
  TSine = class
  public
    Calls: LongInt;
    Phase: Double;
    Freq: Double;
    Amp: Single;
    Silent: Boolean;
    procedure OnGet(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
    procedure OnPut(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
  end;

procedure TSine.OnGet(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
var
  Buf: array of Single;
  Frames, I: Integer;
begin
  InterLockedIncrement(Calls);
  Frames := AAdditional div 8;   // F32 2ch
  if Frames <= 0 then
    Exit;
  Buf := nil;
  SetLength(Buf, Frames * 2);
  for I := 0 to Frames - 1 do
  begin
    if Silent then
      Buf[I * 2] := 0
    else
      Buf[I * 2] := Amp * Sin(Phase);
    Buf[I * 2 + 1] := Buf[I * 2];
    Phase := Phase + 2 * Pi * Freq / 48000;
    if Phase > 2 * Pi then
      Phase := Phase - 2 * Pi;
  end;
  AStream.PutData(@Buf[0], Frames * 8);
end;

procedure TSine.OnPut(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
begin
  InterLockedIncrement(Calls);
end;

function SpecText(const A: TPMLAudioSpec): String;
begin
  Result := Format('%s %dch %d', [PMLAudioFormatName(A.Format), A.Channels, A.Freq]);
end;

{ ---- 本体 ---- }

procedure TestDevices(ACtx: TPMLContext; ARecording, AMonitors: Boolean);
var
  Data: TJSONData;
  Arr: TJSONArray;
  IDs: TPMLAudioDeviceIDs;
  Names, Expected: TStringList;
  I, J, Frames, Ch, Freq: Integer;
  Spec: TPMLAudioSpec;
  O: TJSONObject;
  What, Want: String;
  Fmt: TPMLAudioFormat;
  AllOk: Boolean;
begin
  if ARecording then
  begin
    What := '録音';
    IDs := ACtx.Audio.RecordingDevices;
    Want := 'sources';
  end
  else
  begin
    What := '再生';
    IDs := ACtx.Audio.PlaybackDevices;
    Want := 'sinks';
  end;
  if AMonitors then
    What := What + '（モニター入り）';
  Data := PactlJson(Want);
  Check(Data is TJSONArray, 'pactl --format=json list ' + Want + ' が読める');
  if not (Data is TJSONArray) then
  begin
    Data.Free;
    Exit;
  end;
  Arr := TJSONArray(Data);
  Names := TStringList.Create;
  Expected := TStringList.Create;
  try
    for I := 0 to High(IDs) do
      Names.Add(ACtx.Audio.DeviceName(IDs[I]));
    for I := 0 to Arr.Count - 1 do
    begin
      O := TJSONObject(Arr[I]);
      if ARecording and (not AMonitors) and IsMonitor(O) then
        Continue;
      Expected.Add(Str(O, 'description'));
    end;
    Names.Sort;
    Expected.Sort;
    Check(Names.Text = Expected.Text, Format('%sのデバイスの名前が pactl と同じ（%d 個: %s）',
      [What, Names.Count, StringReplace(Trim(Names.Text), LineEnding, ' / ', [rfReplaceAll])]));

    // 形式・チャンネル数・周波数は sample_specification。扱えない形式は S16（既定）
    AllOk := True;
    for I := 0 to High(IDs) do
    begin
      O := nil;
      for J := 0 to Arr.Count - 1 do
        if Str(TJSONObject(Arr[J]), 'description') = ACtx.Audio.DeviceName(IDs[I]) then
          O := TJSONObject(Arr[J]);
      if O = nil then
      begin
        AllOk := False;
        Continue;
      end;
      ParseSpec(Str(O, 'sample_specification'), Fmt, Ch, Freq);
      if Fmt = PML_AUDIO_UNKNOWN then
        Fmt := PML_AUDIO_S16;
      Spec := ACtx.Audio.DeviceFormat(IDs[I], Frames);
      if not ((Spec.Format = Fmt) and (Spec.Channels = Ch) and (Spec.Freq = Freq)) then
      begin
        AllOk := False;
        WriteLn('    ', ACtx.Audio.DeviceName(IDs[I]), ': ', SpecText(Spec), '（期待 ',
          PMLAudioFormatName(Fmt), ' ', Ch, 'ch ', Freq, '）');
      end;
    end;
    Check(AllOk, What + 'のデバイスの形式が sample_specification と同じ');
  finally
    Names.Free;
    Expected.Free;
    Data.Free;
  end;
end;

{ 名前（description）が AName の sink-input の中のプロパティ。無ければ nil（呼び出し側が Free）。 }
function FindSinkInput: TJSONObject;
var
  Data: TJSONData;
  I: Integer;
  O: TJSONObject;
  P: TJSONData;
begin
  Result := nil;
  Data := PactlJson('sink-inputs');
  if not (Data is TJSONArray) then
  begin
    Data.Free;
    Exit;
  end;
  try
    for I := 0 to TJSONArray(Data).Count - 1 do
    begin
      O := TJSONObject(TJSONArray(Data)[I]);
      P := O.Find('properties');
      if (P is TJSONObject) and (TJSONObject(P).Get('application.name', '') = AppName) then
        Exit(TJSONObject(O.Clone));
    end;
  finally
    Data.Free;
  end;
end;

function InputProp(AInput: TJSONObject; const AKey: String): String;
var
  P: TJSONData;
begin
  Result := '';
  P := AInput.Find('properties');
  if P is TJSONObject then
    Result := TJSONObject(P).Get(AKey, '');
end;

{ parec の出力（float32le 2ch）で、左チャンネルの最大の絶対値と、正の向きの零交差の数。 }
procedure AnalyzeCapture(const APath: String; out AFrames: Integer; out APeak: Single;
  out ACrossings: Integer);
var
  F: TFileStream;
  Buf: array of Single;
  N, I: Integer;
  Prev: Single;
begin
  AFrames := 0;
  APeak := 0;
  ACrossings := 0;
  if not FileExists(APath) then
    Exit;
  F := TFileStream.Create(APath, fmOpenRead);
  try
    N := F.Size div 8;
    if N <= 0 then
      Exit;
    Buf := nil;
    SetLength(Buf, N * 2);
    F.ReadBuffer(Buf[0], N * 8);
  finally
    F.Free;
  end;
  AFrames := N;
  Prev := 0;
  for I := 0 to N - 1 do
  begin
    if Abs(Buf[I * 2]) > APeak then
      APeak := Abs(Buf[I * 2]);
    if (Prev < 0) and (Buf[I * 2] >= 0) then
      Inc(ACrossings);
    Prev := Buf[I * 2];
  end;
end;

procedure TestMain;
var
  Opts: TPMLContextOptions;
  Ctx: TPMLContext;
  Evs: TEventList;
  IDs: TPMLAudioDeviceIDs;
  I: Integer;
  AllAdded: Boolean;
  InfoData: TJSONData;
  DefSinkName, DefSinkDesc, DefSourceName, DefSourceDesc, Output, CapPath: String;
  Sine: TSine;
  L: TPMLLogicalAudioDevice;
  SinkID, LogID, MonID: TPMLAudioDeviceID;
  Stream: TPMLAudioStream;
  Input: TJSONObject;
  Cap: TProcess;
  Frames, Crossings, SinkIdx: Integer;
  Peak: Single;
  Sinks, Sources: TJSONData;

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

  function SinkInputGone: Boolean;
  var
    O: TJSONObject;
  begin
    O := FindSinkInput;
    Result := O = nil;
    O.Free;
  end;

  function Fed: Boolean;
  begin
    Result := Sine.Calls >= 10;
  end;

  function StreamDrained: Boolean;
  begin
    Result := Stream.Queued = 0;
  end;

  function RecFed: Boolean;
  begin
    Result := Stream.Available > 0;
  end;

begin
  Opts := TPMLContextOptions.Default;
  Opts.PreferredAudio := 'pulseaudio';
  Opts.MinimumLogLevel := TPMLLogPriority.Critical;
  Opts.Hints.Add(PML_HINT_APP_NAME, AppName);
  WriteLn('-- バックエンド');
  Ctx := TPMLContext.Create([TPMLSubsystem.Audio], Opts);
  try
    Check(Ctx.Audio.BackendName = 'pulseaudio', 'pulseaudio を選べる（' + Ctx.Audio.BackendName + '）');

    WriteLn('-- デバイス');
    TestDevices(Ctx, False, False);
    TestDevices(Ctx, True, False);
    InfoData := PactlJson('info');
    Check(InfoData is TJSONObject, 'pactl info が読める');
    DefSinkName := '';
    DefSourceName := '';
    if InfoData is TJSONObject then
    begin
      DefSinkName := Str(TJSONObject(InfoData), 'default_sink_name');
      DefSourceName := Str(TJSONObject(InfoData), 'default_source_name');
    end;
    InfoData.Free;
    DefSinkDesc := '';
    DefSourceDesc := '';
    Sinks := PactlJson('sinks');
    Sources := PactlJson('sources');
    try
      if Sinks is TJSONArray then
        for I := 0 to TJSONArray(Sinks).Count - 1 do
          if Str(TJSONObject(TJSONArray(Sinks)[I]), 'name') = DefSinkName then
            DefSinkDesc := Str(TJSONObject(TJSONArray(Sinks)[I]), 'description');
      if Sources is TJSONArray then
        for I := 0 to TJSONArray(Sources).Count - 1 do
          if Str(TJSONObject(TJSONArray(Sources)[I]), 'name') = DefSourceName then
            DefSourceDesc := Str(TJSONObject(TJSONArray(Sources)[I]), 'description');
    finally
      Sinks.Free;
      Sources.Free;
    end;
    Check((DefSinkDesc <> '') and (Ctx.Audio.DeviceName(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK) = DefSinkDesc),
      '既定の再生が pactl の default_sink_name と同じ（' + DefSinkDesc + '）');
    if Length(Ctx.Audio.RecordingDevices) > 0 then
      Check((DefSourceDesc <> '') and (Ctx.Audio.DeviceName(PML_AUDIO_DEVICE_DEFAULT_RECORDING) = DefSourceDesc),
        '既定の録音が pactl の default_source_name と同じ（' + DefSourceDesc + '）');

    Evs := nil;
    Collect(Ctx, Evs);
    IDs := Ctx.Audio.PlaybackDevices;
    AllAdded := Length(IDs) > 0;
    for I := 0 to High(IDs) do
      if not HasEvent(Evs, TPMLEventKind.AudioDeviceAdded, IDs[I]) then
        AllAdded := False;
    Check(AllAdded, '最初の Poll で、再生のデバイスごとに追加のイベント');

    WriteLn('-- hotplug と再生（一時の無音のシンク）');
    RemoveTestSink;
    Evs := nil;
    Collect(Ctx, Evs);
    Evs := nil;
    SinkID := 0;
    LogID := 0;
    CapPath := GetTempDir + 'papimela_pulse_cap_' + IntToStr(GetProcessID) + '.raw';
    if not Pactl(['load-module', 'module-null-sink', 'sink_name=' + TestSinkName,
      'sink_properties=device.description=' + TestSinkDescription, 'rate=48000', 'channels=2'], Output) then
    begin
      Check(False, '一時のシンクを作れる');
      Exit;
    end;
    try
      Check(WaitFor(@SinkAdded, 3000), '足されたシンクの追加のイベント');
      if SinkID <> 0 then
      begin
        Check(Ctx.Audio.DeviceName(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK) = DefSinkDesc, '既定は変わらない');
        Check(SpecText(Ctx.Audio.DeviceFormat(SinkID)) = 'F32LE 2ch 48000',
          '足されたシンク（module-null-sink の既定は float32le）の形式は pactl の値（' +
          SpecText(Ctx.Audio.DeviceFormat(SinkID)) + '）');

        // そのシンクのモニターを録って、鳴らした音を確かめる
        Cap := TProcess.Create(nil);
        try
          Cap.Executable := 'timeout';
          Cap.Parameters.AddStrings(['4', 'parec', '-d', TestSinkName + '.monitor', '--format=float32le',
            '--rate=48000', '--channels=2', '--raw', '--file-format=raw', CapPath]);
          Cap.Options := [poNoConsole];
          Cap.Execute;
          Sleep(300);

          Sine := TSine.Create;
          Sine.Freq := 440;
          Sine.Amp := 0.5;
          Stream := TPMLAudioStream.Create(TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000),
            TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000));
          Stream.OnGet := @Sine.OnGet;
          L := Ctx.Audio.OpenDevice(SinkID, TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000));
          LogID := L.ID;
          Check((L.Format.Format = PML_AUDIO_F32) and (L.Format.Channels = 2) and (L.Format.Freq = 48000),
            '求めた F32 2ch 48000 で開く: ' + SpecText(L.Format));
          L.BindStream(Stream);
          Check(WaitFor(@Fed, 3000), 'OnGet が 10 回以上来る');
          Sleep(500);

          Input := FindSinkInput;
          Check(Input <> nil, 'シンクの入力（ストリーム）がある');
          if Input <> nil then
          begin
            SinkIdx := SinkIndexByName(TestSinkName);
            Check(Input.Get('sink', -2) = SinkIdx, '名指しで開くと、つなぎ先がそのシンク');
            Check(InputProp(Input, 'application.icon_name') = 'applications-games', 'application.icon_name');
            Check(InputProp(Input, 'media.name') = 'Audio Stream', 'media.name は既定の Audio Stream: ' +
              InputProp(Input, 'media.name'));
            Check(InputProp(Input, 'application.name') = AppName, 'application.name');
            Input.Free;
          end;

          Cap.WaitOnExit;
          AnalyzeCapture(CapPath, Frames, Peak, Crossings);
          Check(Frames >= 48000 * 2, Format('モニターを %d フレーム録れた', [Frames]));
          // 鳴らし始めの前後の無音が混ざるので、振幅は最大で、周波数は零交差の数で見る
          Check((Peak >= 0.4) and (Peak <= 0.6), Format('最大の振幅が約 0.5（%.3f）', [Peak]));
          // 鳴らした時間 ≒ 録った時間の中の鳴っている部分。1 秒あたり 440 回に近い（無音の部分で減る）
          Check((Crossings > 440 * 1) and (Crossings < 440 * 4),
            Format('正の向きの零交差が 440 Hz の音の分ある（%d 回）', [Crossings]));
        finally
          Cap.Free;
          DeleteFile(CapPath);
        end;

        // 消す
        RemoveTestSink;
        Check(WaitFor(@SinkRemoved, 3000), '消すと、物理と論理の削除のイベント');
        IDs := Ctx.Audio.PlaybackDevices;
        AllAdded := True;
        for I := 0 to High(IDs) do
          if IDs[I] = SinkID then
            AllAdded := False;
        Check(AllAdded, '一覧から消える');
        Sine.Silent := True;
        Check(WaitFor(@StreamDrained, 4000) or (Stream.Queued < 8 * 48000), '失われた論理デバイスも進み続ける（無音として）');
        L.Free;
        Stream.Free;
        Sine.Free;
      end;
    finally
      RemoveTestSink;
    end;
    Check(WaitFor(@SinkInputGone, 2000), '閉じるとシンクの入力が消える');
  finally
    Ctx.Free;
  end;
end;

procedure TestFormatsAndRecording;
var
  Opts: TPMLContextOptions;
  Ctx: TPMLContext;
  Evs: TEventList;
  IDs: TPMLAudioDeviceIDs;
  I: Integer;
  Output: String;
  SinkID, MonID: TPMLAudioDeviceID;
  L: TPMLLogicalAudioDevice;
  Stream: TPMLAudioStream;
  Sine: TSine;
  Found: Boolean;
  Input: TJSONObject;

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
        on E: Exception do
          SkippedError := E.Message;
      end;
  end;

  function RecFed: Boolean;
  begin
    Result := Stream.Available > 0;
  end;

  function BothRemoved: Boolean;
  begin
    Collect(Ctx, Evs);
    Result := HasEvent(Evs, TPMLEventKind.AudioDeviceRemoved, SinkID)
      and HasEvent(Evs, TPMLEventKind.AudioDeviceRemoved, MonID);
  end;

begin
  Opts := TPMLContextOptions.Default;
  Opts.PreferredAudio := 'pulseaudio';
  Opts.MinimumLogLevel := TPMLLogPriority.Critical;
  Opts.Hints.Add(PML_HINT_APP_NAME, AppName);
  Opts.Hints.Add(PML_HINT_AUDIO_INCLUDE_MONITORS, '1');
  WriteLn('-- モニターを録音のデバイスに入れる（ヒント INCLUDE_MONITORS）');
  RemoveTestSink;
  if not Pactl(['load-module', 'module-null-sink', 'sink_name=' + TestSinkName,
    'sink_properties=device.description=' + TestSinkDescription, 'rate=48000', 'channels=2'], Output) then
  begin
    Check(False, '一時のシンクを作れる');
    Exit;
  end;
  Ctx := TPMLContext.Create([TPMLSubsystem.Audio], Opts);
  try
    TestDevices(Ctx, True, True);
    Evs := nil;
    Collect(Ctx, Evs);
    IDs := Ctx.Audio.RecordingDevices;
    MonID := 0;
    for I := 0 to High(IDs) do
      if Ctx.Audio.DeviceName(IDs[I]) = 'Monitor of ' + TestSinkDescription then
        MonID := IDs[I];
    Check(MonID <> 0, 'モニターが録音のデバイスに入る');
    SinkID := 0;
    for I := 0 to High(Ctx.Audio.PlaybackDevices) do
      if Ctx.Audio.DeviceName(Ctx.Audio.PlaybackDevices[I]) = TestSinkDescription then
        SinkID := Ctx.Audio.PlaybackDevices[I];
    Check(SinkID <> 0, '一時のシンクが再生のデバイスにある');

    WriteLn('-- 扱えない形式（S8）で開くと近い形式になる');
    if SinkID <> 0 then
    begin
      // 開くとき、ストリームの名前のヒントを読む（メディアの名前になる）
      Ctx.Hints.SetHint(PML_HINT_AUDIO_DEVICE_STREAM_NAME, 'Music Track');
      L := Ctx.Audio.OpenDevice(SinkID, TPMLAudioSpec.Make(PML_AUDIO_S8, 2, 48000));
      try
        Check(L.Format.Format = PML_AUDIO_F32LE, 'S8 を求めると F32LE で開く（SDL の近い形式の順）: ' +
          SpecText(L.Format));
        Input := FindSinkInput;
        Check((Input <> nil) and (InputProp(Input, 'media.name') = 'Music Track'),
          'ヒント STREAM_NAME が media.name になる（開くときに読む）');
        Input.Free;
      finally
        L.Free;
      end;
    end;

    WriteLn('-- 録音（モニター）');
    if MonID <> 0 then
    begin
      Sine := TSine.Create;
      Stream := Ctx.Audio.OpenDeviceStream(MonID, TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000), @Sine.OnPut);
      try
        Ctx.Audio.ResumeStreamDevice(Stream);
        Check(WaitFor(@RecFed, 3000), 'モニターのデータが入る');
        Found := Stream.Available > 0;
        Check(Found, '入ったデータがある（' + IntToStr(Stream.Available) + ' バイト）');
      finally
        Stream.Free;
        Sine.Free;
      end;
    end;

    { シンクとそのモニターは、PipeWire の PulseAudio のサーバでは同じ番号になる。消えた知らせは
      番号と向きで探す（SDL は番号だけで探すので、モニターの方に知らせが来ない。D-74）。 }
    WriteLn('-- シンクを消すと、同じ番号のモニターも消える');
    Evs := nil;
    Collect(Ctx, Evs);
    Evs := nil;
    RemoveTestSink;
    Check(WaitFor(@BothRemoved, 3000), 'シンクとモニターの両方に削除のイベント');
    IDs := Ctx.Audio.RecordingDevices;
    Found := False;
    for I := 0 to High(IDs) do
      if IDs[I] = MonID then
        Found := True;
    Check(not Found, 'モニターが録音の一覧から消える');
  finally
    Ctx.Free;
    RemoveTestSink;
  end;
end;

procedure TestDestroyOpen;
var
  Opts: TPMLContextOptions;
  Ctx: TPMLContext;
  Sine: TSine;
  Stream: TPMLAudioStream;
  Output: String;
  Id: TPMLAudioDeviceID;
  I: Integer;
begin
  WriteLn('-- 開いたまま壊す');
  Opts := TPMLContextOptions.Default;
  Opts.PreferredAudio := 'pulseaudio';
  Opts.MinimumLogLevel := TPMLLogPriority.Critical;
  Opts.Hints.Add(PML_HINT_APP_NAME, AppName);
  RemoveTestSink;
  if not Pactl(['load-module', 'module-null-sink', 'sink_name=' + TestSinkName,
    'sink_properties=device.description=' + TestSinkDescription, 'rate=48000', 'channels=2'], Output) then
  begin
    Check(False, '一時のシンクを作れる');
    Exit;
  end;
  Ctx := TPMLContext.Create([TPMLSubsystem.Audio], Opts);
  Sine := TSine.Create;
  Sine.Freq := 440;
  Sine.Amp := 0.1;
  Id := 0;
  try
    for I := 0 to High(Ctx.Audio.PlaybackDevices) do
      if Ctx.Audio.DeviceName(Ctx.Audio.PlaybackDevices[I]) = TestSinkDescription then
        Id := Ctx.Audio.PlaybackDevices[I];
    if Id = 0 then
    begin
      Check(False, '一時のシンクがある');
      Exit;
    end;
    Stream := Ctx.Audio.OpenDeviceStream(Id, TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000), @Sine.OnGet);
    Ctx.Audio.ResumeStreamDevice(Stream);
    Sleep(300);
  finally
    Ctx.Free;
    RemoveTestSink;
  end;
  Check(Stream.Binding.Device = nil, 'Context を壊すと結び付けが外れる');
  Stream.Free;
  Sine.Free;
end;

var
  Dog: TWatchdog;
  Output: String;
begin
  WriteLn('=== test_audio_pulse ===');
  if not Pactl(['info'], Output) then
  begin
    if GetEnvironmentVariable('PAPIMELA_PULSE_OPTIONAL') = '1' then
    begin
      WriteLn('  [SKIP] PulseAudio のサーバに繋がらない（PAPIMELA_PULSE_OPTIONAL=1）');
      Halt(0);
    end;
    WriteLn('  [FAIL] PulseAudio のサーバに繋がらない（pactl info。無い環境では PAPIMELA_PULSE_OPTIONAL=1）');
    Halt(1);
  end;
  Dog := TWatchdog.Create('watchdog', True);
  Dog.LimitMs := 90000;
  Dog.Start;
  try
    TestMain;
    TestFormatsAndRecording;
    TestDestroyOpen;
  except
    on E: Exception do
    begin
      WriteLn('  [FAIL] 例外: ', E.ClassName, ': ', E.Message);
      Inc(Failures);
    end;
  end;
  { PulseAudio のスレッドが、例外を止めた設定を受け継いでいる（入口で有効だったことが無い）。
    x86 だけで意味がある: aarch64（Raspberry Pi 5、Linux）では C が作ったスレッドは親の設定を引き継がず、
    FPC の既定に戻る（実測）。この機械の浮動小数点は例外で止まらないので、C 側の計算は止まらない。 }
  {$IF defined(CPUX86_64) or defined(CPUI386)}
  Check(PMLPulseUnmaskedEntries = 0, Format('PulseAudio の呼び出しの入口で、浮動小数点の例外が有効だった回数が 0（%d）',
    [PMLPulseUnmaskedEntries]));
  {$ELSE}
  WriteLn('  [SKIP] 入口の浮動小数点の例外の検査は x86 だけ（この機械では ', PMLPulseUnmaskedEntries,
    ' 回。C のスレッドは親の設定を引き継がない）');
  {$ENDIF}
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
