{
  test_audio_alsa — ALSA のオーディオバックエンド（手元の ALSA で動かす）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 'alsa' を選べる。再生と録音のデバイスに「ALSA default ...」の既定が 1 台ずつある。名前は
       「カード名:PCM 名」。接頭辞が hw: / sysdefault: / default: のどれか
    2. 生きた SDL（システムの libSDL3 の ALSA ドライバ。tools/alsa-parity/sdl_alsa_probe.c を検査の中で
       gcc で作る）と同じ機械で突き合わせる: 再生のデバイスの名前の並びが同じ。各デバイスを 5 通りの仕様
       （F32 2ch 48000、S16 2ch 44100、S16 6ch 48000、F32 8ch 48000、S32 2ch 96000）で開いた結果
       （決まった形式・チャンネル数・周波数・1 回分のフレーム数・並び、または ALSA のエラーの文面）が同じ。
       使用中（busy）のデバイスは、その時の状態で変わるので飛ばす
    3. ヒント DEFAULT_PLAYBACK_DEVICE=null（ALSA の null PCM は何でも受けて捨てる）で既定の再生を開く:
       求めたとおりの形式で開く、OnGet が来る。存在しない PCM の名前なら ALSA のエラーで開けない
    4. 既定の PCM（PulseAudio のプラグイン）を、環境変数 PULSE_SINK で一時の無音のシンクへ向けて
       440 Hz の正弦波（F32 2ch 48000）を鳴らし、parec でそのシンクのモニターを録って、振幅と周波数が合う
    5. 録音: 既定の PCM を PULSE_SOURCE で一時のシンクのモニターに向けて開き、データが入る
    6. hotplug の走査のスレッド（間隔のヒントを 150 ミリ秒に）: 1 秒半の間、追加も削除もイベントが出ない
    7. ストリームを開いたまま Context を壊せる

  WHY:
    オーディオの残りの #58（Audio.Alsa）の受け入れ検査。チャンネルの並びの交渉は test_alsa_chmap。
    音は、利用者のスピーカーには流さない（一時の無音のシンクと null PCM だけ）。再生のデバイスを開く
    ときに SDL も papimela も無音を流すが、HDMI や USB は開けない状態だった。

  実行前提: ALSA（libasound）がある、gcc と reference/SDL/include と libSDL3.so.0（2 のため。無ければ 2 を飛ばす）、
  PulseAudio のサーバと pactl・parec（4 と 5 のため。無ければ飛ばす）、cthreads。手元専用。
  止まったら見張りが 120 秒で失敗として終わらせる。
}
program test_audio_alsa;

{$mode objfpc}{$H+}
{$scopedenums on}
{$modeswitch nestedprocvars}

uses
  cthreads,
  SysUtils, Classes, BaseUnix, Process, Math,
  PaPiMeLa.Threading,
  PaPiMeLa.Properties,
  PaPiMeLa.Log,
  PaPiMeLa.Events,
  PaPiMeLa.Core,
  PaPiMeLa.Errors,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Stream,
  PaPiMeLa.Audio.Backend,
  PaPiMeLa.Audio,
  PaPiMeLa.Platform.Alsa,
  PaPiMeLa.Audio.Alsa;

const
  AppName = 'PmlAlsaTest';
  TestSinkName = 'pml-alsa-test-sink';
  TestSinkDescription = 'PMLAlsaTestSink';

function c_setenv(AName, AValue: PChar; AOverwrite: Integer): Integer; cdecl; external 'c' name 'setenv';
function c_unsetenv(AName: PChar): Integer; cdecl; external 'c' name 'unsetenv';

var
  Failures: Integer = 0;

procedure Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
    WriteLn('  [PASS] ', ALabel)
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(Failures);
  end;
  Flush(System.Output);
end;

procedure Skip(const AWhy: String);
begin
  WriteLn('  [SKIP] ', AWhy);
  Flush(System.Output);
end;

{ ---- 見張りと pactl ---- }

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
    Flush(System.Output);
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

{ ---- イベントと待つ部品 ---- }

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

type
  { 正弦波を送る（OnGet）と、録音を数える（OnPut）。 }
  TSine = class
  public
    Calls: LongInt;
    Bytes: Int64;
    Phase: Double;
    Freq: Double;
    Amp: Single;
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
    Buf[I * 2] := Amp * Sin(Phase);
    Buf[I * 2 + 1] := Buf[I * 2];
    Phase := Phase + 2 * Pi * Freq / 48000;
    if Phase > 2 * Pi then
      Phase := Phase - 2 * Pi;
  end;
  AStream.PutData(@Buf[0], Frames * 8);
  Inc(Bytes, Frames * 8);
end;

procedure TSine.OnPut(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
begin
  InterLockedIncrement(Calls);
  Inc(Bytes, AAdditional);
end;

function SpecText(const A: TPMLAudioSpec): String;
begin
  Result := Format('%s %dch %d', [PMLAudioFormatName(A.Format), A.Channels, A.Freq]);
end;

function MakeOptions(const AHints: array of String): TPMLContextOptions;
var
  I: Integer;
begin
  Result := TPMLContextOptions.Default;
  Result.PreferredAudio := 'alsa';
  Result.MinimumLogLevel := TPMLLogPriority.Critical;
  Result.Hints.Add(PML_HINT_APP_NAME, AppName);
  I := 0;
  while I < High(AHints) do
  begin
    Result.Hints.Add(AHints[I], AHints[I + 1]);
    Inc(I, 2);
  end;
end;

{ ---- 1. バックエンドとデバイス ---- }

procedure TestBackend;
var
  Ctx: TPMLContext;
  IDs: TPMLAudioDeviceIDs;
  I: Integer;
  HavePlayDefault, HaveRecDefault, AllNamed: Boolean;
  N: String;
begin
  WriteLn('-- バックエンドとデバイス');
  Ctx := TPMLContext.Create([TPMLSubsystem.Audio], MakeOptions([]));
  try
    Check(Ctx.Audio.BackendName = 'alsa', 'alsa を選べる（' + Ctx.Audio.BackendName + '）');
    IDs := Ctx.Audio.PlaybackDevices;
    HavePlayDefault := False;
    AllNamed := True;
    for I := 0 to High(IDs) do
    begin
      N := Ctx.Audio.DeviceName(IDs[I]);
      if N = 'ALSA default playback device' then
        HavePlayDefault := True
      else if Pos(':', N) = 0 then
        AllNamed := False;
    end;
    Check(HavePlayDefault, '再生に ALSA default playback device がある（' + IntToStr(Length(IDs)) + ' 個）');
    Check(AllNamed, '既定以外の再生のデバイスは「カード名:PCM 名」');
    IDs := Ctx.Audio.RecordingDevices;
    HaveRecDefault := False;
    for I := 0 to High(IDs) do
      if Ctx.Audio.DeviceName(IDs[I]) = 'ALSA default recording device' then
        HaveRecDefault := True;
    Check(HaveRecDefault, '録音に ALSA default recording device がある');
    Check(Ctx.Audio.DeviceName(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK) = 'ALSA default playback device',
      '既定の再生は ALSA default playback device');
    Check(Ctx.Audio.DeviceName(PML_AUDIO_DEVICE_DEFAULT_RECORDING) = 'ALSA default recording device',
      '既定の録音は ALSA default recording device');
  finally
    Ctx.Free;
  end;
end;

{ ---- 2. 生きた SDL との突き合わせ ---- }

type
  TW = record
    F: TPMLAudioFormat;
    Ch, Freq: Integer;
  end;

const
  // 突き合わせる要求。U8・S8・22050・32000 は、中核が渡す仕様が SDL 3.4.2 と違う（バックエンドの外）ので除く
  Wants: array[0..4] of TW = (
    (F: PML_AUDIO_F32LE; Ch: 2; Freq: 48000), (F: PML_AUDIO_S16LE; Ch: 2; Freq: 44100),
    (F: PML_AUDIO_S16LE; Ch: 6; Freq: 48000), (F: PML_AUDIO_F32LE; Ch: 8; Freq: 48000),
    (F: PML_AUDIO_S32LE; Ch: 2; Freq: 96000));

{ SDL の行の「ALSA: ...」から先だけ。SDL の文面の ": Success"（SDL の誤り）は除く。 }
function NormalizeError(const S: String): String;
var
  P: Integer;
begin
  Result := S;
  P := Pos('ALSA:', Result);
  if P > 0 then
    Result := Copy(Result, P, MaxInt);
  if (Length(Result) > 9) and (Copy(Result, Length(Result) - 8, 9) = ': Success') then
    SetLength(Result, Length(Result) - 9);
end;

function OurLine(ACtx: TPMLContext; AID: TPMLAudioDeviceID; const AWant: TW): String;
var
  L: TPMLLogicalAudioDevice;
  S: TPMLAudioSpec;
  Map: TPMLChannelMap;
  K: Integer;
begin
  Result := Format('O P %s %s,%d,%d -> ', [ACtx.Audio.DeviceName(AID), PMLAudioFormatName(AWant.F), AWant.Ch, AWant.Freq]);
  try
    L := ACtx.Audio.OpenDevice(AID, TPMLAudioSpec.Make(AWant.F, AWant.Ch, AWant.Freq));
    try
      S := L.Format;
      Map := ACtx.Audio.DeviceChannelMap(AID);
      Result := Result + Format('%s %d %d %d ', [PMLAudioFormatName(S.Format), S.Channels, S.Freq, L.SampleFrames]);
      if Length(Map) = 0 then
        Result := Result + '-'
      else
        for K := 0 to High(Map) do
        begin
          if K > 0 then
            Result := Result + ',';
          Result := Result + IntToStr(Map[K]);
        end;
    finally
      L.Free;
    end;
  except
    on E: Exception do
      Result := Result + 'ERR ' + NormalizeError(E.Message);
  end;
end;

procedure TestSdlParity;
var
  Probe, Output, Line: String;
  Dir: String;
  SdlLines, SdlDevices: TStringList;
  Ctx: TPMLContext;
  IDs: TPMLAudioDeviceIDs;
  I, J, Compared, Skipped: Integer;
  Names: TStringList;
  Ours, Theirs, Key: String;
  Mismatches: Integer;
begin
  WriteLn('-- 生きた SDL（システムの libSDL3 の ALSA ドライバ）との突き合わせ');
  if not FileExists('reference/SDL/include/SDL3/SDL.h') then
  begin
    Skip('reference/SDL/include が無い（docs/ORIGIN.md）');
    Exit;
  end;
  Dir := GetTempDir + 'papimela_alsa_probe_' + IntToStr(GetProcessID);
  ForceDirectories(Dir);
  Probe := Dir + '/sdl_alsa_probe';
  try
    if not RunCommand('gcc', ['-O1', '-w', '-Ireference/SDL/include', 'tools/alsa-parity/sdl_alsa_probe.c', '-o', Probe,
      '-l:libSDL3.so.0'], Output, [poNoConsole]) then
    begin
      Skip('SDL のプローブを gcc で作れない（gcc と libSDL3.so.0 が要る）: ' + Copy(Output, 1, 80));
      Exit;
    end;
    Output := '';
    if not RunCommand(Probe, [], Output, [poNoConsole]) then
    begin
      Skip('SDL のプローブが動かない');
      Exit;
    end;
    if Pos('INIT-ERR', Output) > 0 then
    begin
      Skip('SDL の ALSA ドライバが使えない: ' + Trim(Copy(Output, 1, 100)));
      Exit;
    end;
    SdlLines := TStringList.Create;
    SdlDevices := TStringList.Create;
    Names := TStringList.Create;
    try
      SdlLines.Text := Output;
      for I := 0 to SdlLines.Count - 1 do
        if Copy(SdlLines[I], 1, 4) = 'D P ' then
          SdlDevices.Add(Copy(SdlLines[I], 5, MaxInt));

      Ctx := TPMLContext.Create([TPMLSubsystem.Audio], MakeOptions([]));
      try
        IDs := Ctx.Audio.PlaybackDevices;
        for I := 0 to High(IDs) do
          Names.Add(Ctx.Audio.DeviceName(IDs[I]));
        SdlDevices.Sort;
        Names.Sort;
        Check(Names.Text = SdlDevices.Text, Format('再生のデバイスの名前の並びが SDL と同じ（%d 個: %s）',
          [Names.Count, StringReplace(Trim(Names.Text), LineEnding, ' / ', [rfReplaceAll])]));

        Compared := 0;
        Skipped := 0;
        Mismatches := 0;
        for I := 0 to High(IDs) do
          for J := 0 to High(Wants) do
          begin
            Ours := OurLine(Ctx, IDs[I], Wants[J]);
            Key := Copy(Ours, 1, Pos(' -> ', Ours) + 3);
            Theirs := '';
            for Line in SdlLines do
              if Copy(Line, 1, Length(Key)) = Key then
                Theirs := Line;
            if Theirs = '' then
            begin
              Check(False, '(SDL に行が無い) ' + Key);
              Continue;
            end;
            Theirs := Copy(Theirs, Length(Key) + 1, MaxInt);
            if Copy(Theirs, 1, 4) = 'ERR ' then
              Theirs := Key + 'ERR ' + NormalizeError(Copy(Theirs, 5, MaxInt))
            else
              Theirs := Key + Theirs;
            // 使用中は、その時の状態で変わる
            if (Pos('busy', Ours) > 0) or (Pos('busy', Theirs) > 0) then
            begin
              Inc(Skipped);
              Continue;
            end;
            Inc(Compared);
            if Ours <> Theirs then
            begin
              Inc(Mismatches);
              WriteLn('    papimela: ', Ours);
              WriteLn('    SDL     : ', Theirs);
            end;
          end;
        Check((Mismatches = 0) and (Compared > 0),
          Format('開いた結果が SDL と同じ（%d 通り比べた、使用中で %d 通り飛ばした、違い %d）',
            [Compared, Skipped, Mismatches]));
      finally
        Ctx.Free;
      end;
    finally
      SdlLines.Free;
      SdlDevices.Free;
      Names.Free;
    end;
  finally
    DeleteFile(Probe);
    RemoveDir(Dir);
  end;
end;

{ ---- 3. null PCM ---- }

procedure TestNullPcm;
var
  Ctx: TPMLContext;
  Sine: TSine;
  Stream: TPMLAudioStream;
  L: TPMLLogicalAudioDevice;
  Msg: String;
  Raised: Boolean;

  function Fed: Boolean;
  begin
    Result := Sine.Calls >= 10;
  end;

begin
  WriteLn('-- null PCM（何でも受けて捨てる）');
  Ctx := TPMLContext.Create([TPMLSubsystem.Audio],
    MakeOptions([PML_HINT_AUDIO_ALSA_DEFAULT_PLAYBACK_DEVICE, 'null']));
  Sine := TSine.Create;
  Sine.Freq := 440;
  Sine.Amp := 0.1;
  try
    L := Ctx.Audio.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK, TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000));
    try
      Check((L.Format.Format = PML_AUDIO_F32LE) and (L.Format.Channels = 2) and (L.Format.Freq = 48000),
        '求めた F32 2ch 48000 のまま開く: ' + SpecText(L.Format));
      Stream := TPMLAudioStream.Create(TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000),
        TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000));
      try
        Stream.OnGet := @Sine.OnGet;
        L.BindStream(Stream);
        Check(WaitFor(@Fed, 3000), 'OnGet が 10 回以上来る');
        Check(Sine.Bytes > 0, Format('データを送れた（%d バイト）', [Sine.Bytes]));
      finally
        Stream.Free;
      end;
    finally
      L.Free;
    end;
  finally
    Sine.Free;
    Ctx.Free;
  end;

  // 存在しない PCM の名前
  Ctx := TPMLContext.Create([TPMLSubsystem.Audio],
    MakeOptions([PML_HINT_AUDIO_ALSA_DEFAULT_PLAYBACK_DEVICE, 'no_such_pcm_papimela']));
  try
    Raised := False;
    Msg := '';
    try
      Ctx.Audio.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK).Free;
    except
      on E: Exception do
      begin
        Raised := True;
        Msg := E.Message;
      end;
    end;
    Check(Raised and (Pos('ALSA: Couldn''t open audio device: ', Msg) > 0),
      '存在しない PCM の名前は ALSA のエラーで開けない: ' + Copy(Msg, 1, 100));
  finally
    Ctx.Free;
  end;
end;

{ ---- 4, 5. 既定の PCM（PulseAudio のプラグイン）で、一時のシンクへ往復 ---- }

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

{ 一時のシンクのモニターを録りながら、AFormat で開いた既定の PCM に 440 Hz の正弦波を送り、
  振幅と周波数を確かめる。形式の取り違え（バイト順など）は、報告される形式には出ず、音に出る。
  ARecord が真なら、続けて録音の PCM（PULSE_SOURCE がモニター）も開く。 }
procedure PlayAndCapture(ACtx: TPMLContext; AFormat: TPMLAudioFormat; ARecord: Boolean);
var
  CapPath: String;
  Sine: TSine;
  Stream, RecStream: TPMLAudioStream;
  L: TPMLLogicalAudioDevice;
  Cap: TProcess;
  Frames, Crossings: Integer;
  Peak: Single;
  Tag: String;

  function Fed: Boolean;
  begin
    Result := Sine.Calls >= 10;
  end;

  function RecFed: Boolean;
  begin
    Result := RecStream.Available > 0;
  end;

begin
  Tag := PMLAudioFormatName(AFormat);
  CapPath := GetTempDir + 'papimela_alsa_cap_' + IntToStr(GetProcessID) + '.raw';
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
    // 送る側は F32。結び付けると、デバイスの形式へ変えて送る
    Stream := TPMLAudioStream.Create(TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000),
      TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000));
    Stream.OnGet := @Sine.OnGet;
    L := ACtx.Audio.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK, TPMLAudioSpec.Make(AFormat, 2, 48000));
    try
      Check((L.Format.Format = AFormat) and (L.Format.Channels = 2) and (L.Format.Freq = 48000),
        Tag + ' 2ch 48000 で開く: ' + SpecText(L.Format));
      L.BindStream(Stream);
      Check(WaitFor(@Fed, 3000), Tag + ': OnGet が 10 回以上来る');
      Sleep(1500);

      if ARecord then
      begin
        // 録音: 同じ PCM を PULSE_SOURCE で一時のシンクのモニターに向けて
        RecStream := ACtx.Audio.OpenDeviceStream(PML_AUDIO_DEVICE_DEFAULT_RECORDING,
          TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000));
        try
          ACtx.Audio.ResumeStreamDevice(RecStream);
          Check(WaitFor(@RecFed, 3000), '録音のデータが入る');
        finally
          RecStream.Free;
        end;
      end;
    finally
      L.Free;
      Stream.Free;
    end;
    Cap.WaitOnExit;
    AnalyzeCapture(CapPath, Frames, Peak, Crossings);
    Check(Frames >= 48000 * 2, Format('%s: モニターを %d フレーム録れた', [Tag, Frames]));
    Check((Peak >= 0.4) and (Peak <= 0.6), Format('%s: 最大の振幅が約 0.5（%.3f）', [Tag, Peak]));
    Check((Crossings > 440) and (Crossings < 440 * 4),
      Format('%s: 正の向きの零交差が 440 Hz の音の分ある（%d 回）', [Tag, Crossings]));
    Sine.Free;
  finally
    Cap.Free;
    DeleteFile(CapPath);
  end;
end;

procedure TestPulsePlugin;
var
  Ctx: TPMLContext;
  Output: String;
begin
  WriteLn('-- 既定の PCM（PulseAudio のプラグイン）から一時のシンクへ');
  if not Pactl(['info'], Output) then
  begin
    Skip('PulseAudio のサーバに繋がらない');
    Exit;
  end;
  RemoveTestSink;
  if not Pactl(['load-module', 'module-null-sink', 'sink_name=' + TestSinkName,
    'sink_properties=device.description=' + TestSinkDescription, 'rate=48000', 'channels=2'], Output) then
  begin
    Check(False, '一時のシンクを作れる');
    Exit;
  end;
  // ALSA の pulse プラグインは、PULSE_SINK / PULSE_SOURCE を読んでつなぐ先を決める
  c_setenv('PULSE_SINK', PChar(TestSinkName), 1);
  c_setenv('PULSE_SOURCE', PChar(TestSinkName + '.monitor'), 1);
  Ctx := TPMLContext.Create([TPMLSubsystem.Audio], MakeOptions([]));
  try
    try
      PlayAndCapture(Ctx, PML_AUDIO_F32, True);
      PlayAndCapture(Ctx, PML_AUDIO_S16, False);
      PlayAndCapture(Ctx, PML_AUDIO_S32, False);
    finally
      Ctx.Free;
    end;
  finally
    c_unsetenv('PULSE_SINK');
    c_unsetenv('PULSE_SOURCE');
    RemoveTestSink;
  end;
end;

{ ---- 6. hotplug の走査 ---- }

procedure TestHotplugStable;
var
  Ctx: TPMLContext;
  Evs: TEventList;
  I, Adds, Removes: Integer;
  Waited: Integer;
begin
  WriteLn('-- hotplug の走査（間隔 150 ミリ秒）');
  Ctx := TPMLContext.Create([TPMLSubsystem.Audio], MakeOptions([PML_HINT_AUDIO_ALSA_HOTPLUG_INTERVAL, '150']));
  try
    Evs := nil;
    Collect(Ctx, Evs);   // 最初の追加を捨てる
    Evs := nil;
    Waited := 0;
    while Waited < 1500 do
    begin
      Sleep(50);
      Inc(Waited, 50);
      Collect(Ctx, Evs);
    end;
    Adds := 0;
    Removes := 0;
    for I := 0 to High(Evs) do
      case Evs[I].Kind of
        TPMLEventKind.AudioDeviceAdded: Inc(Adds);
        TPMLEventKind.AudioDeviceRemoved: Inc(Removes);
      end;
    Check((Adds = 0) and (Removes = 0),
      Format('走査が 10 回ほど走っても、追加 %d・削除 %d のイベントが出ない', [Adds, Removes]));
  finally
    Ctx.Free;
  end;
end;

{ ---- 7. 開いたまま壊す ---- }

procedure TestDestroyOpen;
var
  Ctx: TPMLContext;
  Sine: TSine;
  Stream: TPMLAudioStream;
begin
  WriteLn('-- 開いたまま壊す');
  Ctx := TPMLContext.Create([TPMLSubsystem.Audio],
    MakeOptions([PML_HINT_AUDIO_ALSA_DEFAULT_PLAYBACK_DEVICE, 'null']));
  Sine := TSine.Create;
  Sine.Freq := 440;
  Sine.Amp := 0.1;
  try
    Stream := Ctx.Audio.OpenDeviceStream(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK,
      TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000), @Sine.OnGet);
    Ctx.Audio.ResumeStreamDevice(Stream);
    Sleep(300);
  finally
    Ctx.Free;
  end;
  Check(Stream.Binding.Device = nil, 'Context を壊すと結び付けが外れる');
  Stream.Free;
  Sine.Free;
end;

var
  Dog: TWatchdog;
begin
  WriteLn('=== test_audio_alsa ===');
  if not TPMLAlsa.IsAvailable then
  begin
    if GetEnvironmentVariable('PAPIMELA_ALSA_OPTIONAL') = '1' then
    begin
      WriteLn('  [SKIP] libasound が無い（PAPIMELA_ALSA_OPTIONAL=1）');
      Halt(0);
    end;
    WriteLn('  [FAIL] libasound.so.2 が無い（無い環境では PAPIMELA_ALSA_OPTIONAL=1）');
    Halt(1);
  end;
  Dog := TWatchdog.Create('watchdog', True);
  Dog.LimitMs := 120000;
  Dog.Start;
  try
    TestBackend;
    TestSdlParity;
    TestNullPcm;
    TestPulsePlugin;
    TestHotplugStable;
    TestDestroyOpen;
  except
    on E: Exception do
    begin
      WriteLn('  [FAIL] 例外: ', E.ClassName, ': ', E.Message);
      Inc(Failures);
    end;
  end;
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
