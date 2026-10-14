{
  test_audio_device — オーディオのデバイス（dummy のバックエンドで、デバイスのスレッドまで本物）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. バックエンドの選び方（名前の誤り、dummy は名前で求めたときだけ、カンマで並べた名前）
    2. 物理デバイスの ID・名前・形式、追加のイベント
    3. 論理デバイスを開く（ID、求めた形式で開く、高い形式で開き直す、引数の誤り）
    4. 混ぜる（2 本のストリーム、音量、足すたびに -1..1 に挟む、後置き処理の形式と長さ）、
       結び付いた側の形式を変えさせない、一時停止、写すだけの道、結び付けの誤り
    5. 簡易パス（一時停止で始まる、最初の OnGet の量、結び付けを変えられない、Free で閉じる）
    6. 録音（無音、後置き処理と入れ替えた並び、音量だけ、F32 のデバイスでの並び、論理デバイスが
       2 つのときのバイト数）
    7. アプリの呼び出しの例外で論理デバイスが止まる
    8. 切断（イベント、名指しでは開けない、無音で進み続ける）、既定の変更（移る、形式の変更の
       イベント）、参照が尽きたら物理デバイスが消える
    9. 系が先に壊れても、ストリームはアプリの手に残る
    10. ヒント（1 回分のフレーム数、既定の形式・チャンネル数・周波数）

  WHY:
    オーディオの 2 段目（#51 の中核、#55 の dummy）の受け入れ検査。音の装置は要らない。
    期待値は SDL 3.4.2 と参照版（main）を dummy で動かして取った（docs/TEST-LOG.md の
    使い捨て検証）: ID（再生 15・録音 18・論理 21・25）、名前、形式、イベントの順、
    求めた形式で開く（3.4.2。main は D-66）、簡易パスの最初の OnGet の量 8192、録音は無音。
    SDL の不具合（D-66〜D-71）の箇所は、papimela の正しい値を期待値にしてある。

  実行前提: cthreads（uses の先頭）。止まったら見張りが 60 秒で失敗として終わらせる。
}
program test_audio_device;

{$mode objfpc}{$H+}
{$scopedenums on}
{$modeswitch nestedprocvars}

uses
  cthreads,
  SysUtils, Classes, BaseUnix,
  PaPiMeLa.Errors,
  PaPiMeLa.Threading,
  PaPiMeLa.Properties,
  PaPiMeLa.Log,
  PaPiMeLa.Events,
  PaPiMeLa.Core,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Stream,
  PaPiMeLa.Audio.Backend,
  PaPiMeLa.Audio,
  PaPiMeLa.Audio.Dummy;

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
    FpExit(3);
  end;
  Result := 0;
end;

function Spec(AFormat: TPMLAudioFormat; AChannels, AFreq: Integer): TPMLAudioSpec;
begin
  Result := TPMLAudioSpec.Make(AFormat, AChannels, AFreq);
end;

function SameSpec(const A: TPMLAudioSpec; AFormat: TPMLAudioFormat; AChannels, AFreq: Integer): Boolean;
begin
  Result := (A.Format = AFormat) and (A.Channels = AChannels) and (A.Freq = AFreq);
end;

function SpecText(const A: TPMLAudioSpec): String;
begin
  Result := Format('%s %dch %d', [PMLAudioFormatName(A.Format), A.Channels, A.Freq]);
end;

function SingleBits(V: Single): LongWord;
begin
  Result := PLongWord(@V)^;
end;

{ 左と右が決まった値の F32 2ch のフレームを AFrames 個入れたストリーム。 }
function PairStream(ALeft, ARight: Single; AFreq, AFrames: Integer): TPMLAudioStream;
var
  Buf: array of Single;
  I: Integer;
begin
  Result := TPMLAudioStream.Create(Spec(PML_AUDIO_F32, 2, AFreq), Spec(PML_AUDIO_F32, 2, AFreq));
  SetLength(Buf, AFrames * 2);
  for I := 0 to AFrames - 1 do
  begin
    Buf[I * 2] := ALeft;
    Buf[I * 2 + 1] := ARight;
  end;
  Result.PutData(@Buf[0], Length(Buf) * 4);
end;

{ 同じ値の F32 のフレームを AFrames 個入れたストリーム。 }
function ConstStream(AValue: Single; AChannels, AFreq, AFrames: Integer): TPMLAudioStream;
var
  Buf: array of Single;
  I: Integer;
begin
  Result := TPMLAudioStream.Create(Spec(PML_AUDIO_F32, AChannels, AFreq), Spec(PML_AUDIO_F32, AChannels, AFreq));
  SetLength(Buf, AFrames * AChannels);
  for I := 0 to High(Buf) do
    Buf[I] := AValue;
  Result.PutData(@Buf[0], Length(Buf) * 4);
end;

type
  TEventList = array of TPMLEvent;

function DrainEvents(ACtx: TPMLContext): TEventList;
var
  Ev: TPMLEvent;
begin
  Result := nil;
  while ACtx.Events.Poll(Ev) do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Ev;
  end;
end;

function HasAudioEvent(const AList: TEventList; AKind: TPMLEventKind; AID: LongWord): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(AList) do
    if (AList[I].Kind = AKind) and (AList[I].AudioDevice.Which = AID) then
      Exit(True);
  Result := False;
end;

function CountKind(const AList: TEventList; AKind: TPMLEventKind): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(AList) do
    if AList[I].Kind = AKind then
      Inc(Result);
end;

type
  { 後置き処理を覚える（再生）。値はデバイスのスレッドが書き、メインスレッドが待ってから読む。 }
  TPostmixRecorder = class
  public
    Calls   : LongInt;
    Last    : Single;     // 最後の呼び出しの最初の標本
    Last1   : Single;     // 同じく 2 つ目の標本
    MaxAbs  : Single;
    LastSpec: TPMLAudioSpec;
    LastLen : Integer;
    procedure Reset;
    procedure OnPostmix(ADevice: TPMLLogicalAudioDevice; const ASpec: TPMLAudioSpec;
      ABuffer: PSingle; ALen: Integer);
  end;

  { 録音の後置き処理で、決まった値を書く（0.25 と -0.5 を交互に）。 }
  TPostmixWriter = class
  public
    Calls: LongInt;
    procedure OnPostmix(ADevice: TPMLLogicalAudioDevice; const ASpec: TPMLAudioSpec;
      ABuffer: PSingle; ALen: Integer);
    procedure OnNothing(ADevice: TPMLLogicalAudioDevice; const ASpec: TPMLAudioSpec;
      ABuffer: PSingle; ALen: Integer);
  end;

  TGetRecorder = class
  public
    Calls      : LongInt;
    FirstAdd   : Integer;
    FirstTotal : Integer;
    procedure OnGet(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
    procedure OnThrow(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
  end;

  TDisconnector = class(TPMLThread)
  public
    Sys: TPMLAudioSystem;
    Dev: TPMLAudioDevice;
  protected
    function Run: Integer; override;
  end;

procedure TPostmixRecorder.Reset;
begin
  InterLockedExchange(Calls, 0);
  MaxAbs := 0;
  Last := 0;
end;

procedure TPostmixRecorder.OnPostmix(ADevice: TPMLLogicalAudioDevice; const ASpec: TPMLAudioSpec;
  ABuffer: PSingle; ALen: Integer);
var
  I: Integer;
begin
  for I := 0 to (ALen div 4) - 1 do
    if Abs(ABuffer[I]) > MaxAbs then
      MaxAbs := Abs(ABuffer[I]);
  Last := ABuffer[0];
  Last1 := ABuffer[1];
  LastSpec := ASpec;
  LastLen := ALen;
  InterLockedIncrement(Calls);
end;

procedure TPostmixWriter.OnPostmix(ADevice: TPMLLogicalAudioDevice; const ASpec: TPMLAudioSpec;
  ABuffer: PSingle; ALen: Integer);
var
  I: Integer;
begin
  for I := 0 to (ALen div 4) - 1 do
    if I mod 2 = 0 then
      ABuffer[I] := 0.25
    else
      ABuffer[I] := -0.5;
  InterLockedIncrement(Calls);
end;

procedure TPostmixWriter.OnNothing(ADevice: TPMLLogicalAudioDevice; const ASpec: TPMLAudioSpec;
  ABuffer: PSingle; ALen: Integer);
begin
end;

procedure TGetRecorder.OnGet(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
begin
  if InterLockedIncrement(Calls) = 1 then
  begin
    FirstAdd := AAdditional;
    FirstTotal := ATotal;
  end;
end;

procedure TGetRecorder.OnThrow(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
begin
  InterLockedIncrement(Calls);
  raise Exception.Create('test: OnGet raised on purpose');
end;

function TDisconnector.Run: Integer;
begin
  Sys.DeviceDisconnected(Dev);
  Result := 0;
end;

{ ACondition が真になるまで（AMs ミリ秒まで）待つ。 }
type
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
    Sleep(5);
    Inc(Waited, 5);
  end;
  Result := True;
end;

function MakeContext(const APreferred: String; const AHints: array of String): TPMLContext;
var
  Opts: TPMLContextOptions;
  I: Integer;
begin
  Opts := TPMLContextOptions.Default;
  Opts.PreferredAudio := APreferred;
  // 検査の出力にログを混ぜない（呼び出しの例外の記録など）。
  Opts.MinimumLogLevel := TPMLLogPriority.Critical;
  I := 0;
  while I < High(AHints) do
  begin
    Opts.Hints.Add(AHints[I], AHints[I + 1]);
    Inc(I, 2);
  end;
  Result := TPMLContext.Create([TPMLSubsystem.Audio], Opts);
end;

{ ---- 1. バックエンドの選び方 ---- }

procedure TestSelection;
var
  Raised: String;
  Ctx: TPMLContext;
begin
  WriteLn('-- バックエンドの選び方');
  Raised := '';
  try
    Ctx := MakeContext('nosuch', []);
    Ctx.Free;
  except
    on E: Exception do
      Raised := E.ClassName;
  end;
  Check(Raised = 'EPMLUnsupported', '登録されていない名前は EPMLUnsupported（' + Raised + '）');

  if GetEnvironmentVariable('PAPIMELA_AUDIO_DRIVER') = '' then
  begin
    Raised := '';
    try
      Ctx := MakeContext('', []);
      Ctx.Free;
    except
      on E: Exception do
        Raised := E.ClassName;
    end;
    Check(Raised = 'EPMLAudioError', 'dummy は名前で求めたときだけ（無指定は EPMLAudioError: ' + Raised + '）');
  end
  else
    WriteLn('  [SKIP] PAPIMELA_AUDIO_DRIVER が置かれているので、無指定の選び方は見ない');
end;

{ ---- 2〜9. 1 つの Context で ---- }

procedure TestMain;
var
  Ctx: TPMLContext;
  Sys: TPMLAudioSystem;
  IDs: TPMLAudioDeviceIDs;
  Evs: TEventList;
  Frames, I, QOld, QNew, FramesOld, FramesNew: Integer;
  L1, L2, LR, LG, LF, LOld, LNew, LE, LD, LTmp: TPMLLogicalAudioDevice;
  A, B, C, D, D2, S, T, T2, T3, SOld, SNew, Z, Y, Q: TPMLAudioStream;
  Rec: TPostmixRecorder;
  W: TPostmixWriter;
  G, Thrower: TGetRecorder;
  Raised: String;
  SID, LEID, LDID: TPMLAudioDeviceID;
  Dev, NewDev, RecDev, PlayDev: TPMLAudioDevice;
  Map: TPMLChannelMap;
  Got: Integer;
  Buf16: array[0..63] of SmallInt;
  BufF: array[0..7] of Single;
  AllZero, Pattern: Boolean;
  Disc: TDisconnector;

  function RecCalls2: Boolean;
  begin
    Result := Rec.Calls >= 3;
  end;

  function CDrained: Boolean;
  begin
    Result := C.Queued = 0;
  end;

  function GCalled: Boolean;
  begin
    Result := G.Calls > 0;
  end;

  function ThrowerPaused: Boolean;
  begin
    Result := Sys.StreamDevicePaused(Q);
  end;

  function QDrained: Boolean;
  begin
    Result := Q.Queued = 0;
  end;

  function RaisesOf(AProc: Integer): String;
  begin
    Result := '';
    try
      case AProc of
        1: Sys.DeviceName(99);
        2: Sys.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK, Spec(PML_AUDIO_F32, 9, 48000)).Free;
        3: Sys.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK, Spec($1234, 2, 48000)).Free;
        4: Sys.OpenDevice(99).Free;
        5: L1.Gain := -1;
        6: L1.BindStreams([D2, nil]);
        7: L1.BindStreams([D2, D2]);
        8: L1.BindStream(D);
        9: Sys.DeviceName(SID);
        10: Sys.StreamDevice(S).BindStream(D2);
        11: Sys.OpenDevice(15).Free;
        12: Sys.DeviceName(15);
        13: Sys.DeviceName(LEID);
      end;
    except
      on E: Exception do
        Result := E.ClassName;
    end;
  end;

begin
  WriteLn('-- デバイスの一覧');
  Ctx := MakeContext('dummy', []);
  Sys := Ctx.Audio;
  Check(Sys <> nil, 'Context.Audio がある');
  Check(Sys.BackendName = 'dummy', 'バックエンドは dummy（' + Sys.BackendName + '）');
  IDs := Sys.PlaybackDevices;
  Check((Length(IDs) = 1) and (IDs[0] = 15), '再生の物理デバイスは ID 15 の 1 台（SDL と同じ）');
  IDs := Sys.RecordingDevices;
  Check((Length(IDs) = 1) and (IDs[0] = 18), '録音の物理デバイスは ID 18 の 1 台');
  Check(Sys.DeviceName(15) = 'System audio playback device', '再生の名前');
  Check(Sys.DeviceName(18) = 'System audio recording device', '録音の名前');
  Check(Sys.DeviceName(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK) = 'System audio playback device', '既定の印でも名前が引ける');
  Check(SameSpec(Sys.DeviceFormat(15, Frames), PML_AUDIO_S16, 2, 44100) and (Frames = 1024),
    '再生の形式は S16 2ch 44100、1024 フレーム（' + SpecText(Sys.DeviceFormat(15)) + '）');
  Check(SameSpec(Sys.DeviceFormat(18, Frames), PML_AUDIO_S16, 1, 44100) and (Frames = 1024),
    '録音の形式は S16 1ch 44100、1024 フレーム');
  Check(SameSpec(Sys.DeviceFormat(PML_AUDIO_DEVICE_DEFAULT_RECORDING), PML_AUDIO_S16, 1, 44100),
    '既定の録音の印でも形式が引ける');
  Check(TPMLAudioSystem.IsPhysicalDevice(15) and TPMLAudioSystem.IsPlaybackDevice(15)
    and not TPMLAudioSystem.IsPlaybackDevice(18), 'ID のビット（物理・再生）');
  Check(Sys.DeviceUniqueID(15) = '', 'dummy は一意の名前を持たない');
  Check(Length(Sys.DeviceChannelMap(15)) = 0, 'dummy の並びは既定（空）');
  Check(RaisesOf(1) = 'EPMLArgument', '知らない ID の名前は EPMLArgument');

  Evs := DrainEvents(Ctx);
  Check((Length(Evs) = 2) and (Evs[0].Kind = TPMLEventKind.AudioDeviceAdded)
    and (Evs[0].AudioDevice.Which = 15) and not Evs[0].AudioDevice.Recording
    and (Evs[1].Kind = TPMLEventKind.AudioDeviceAdded) and (Evs[1].AudioDevice.Which = 18)
    and Evs[1].AudioDevice.Recording,
    '最初の Poll で、追加のイベントが再生 15・録音 18 の順に来る（' + IntToStr(Length(Evs)) + ' 件）');

  WriteLn('-- 論理デバイスを開く');
  L1 := Sys.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK, Spec(PML_AUDIO_F32, 2, 48000));
  Check(L1.ID = 21, '最初の論理デバイスは ID 21（SDL と同じ）');
  Check(not L1.Recording and not L1.Paused and (L1.Gain = 1.0), '再生、止まっていない、音量 1');
  Check(L1.Name = 'System audio playback device', '論理デバイスの名前は物理デバイスの名前');
  Check(SameSpec(L1.Format, PML_AUDIO_F32, 2, 48000) and (L1.SampleFrames = 1024),
    '求めた形式で開く（D-66。SDL 3.4.2 と同じ）: ' + SpecText(L1.Format));
  L2 := Sys.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK);
  Check(L2.ID = 25, '2 つ目は ID 25');
  Check(SameSpec(Sys.DeviceFormat(15), PML_AUDIO_F32, 2, 48000), '低い形式で開いても開き直さない');
  Check(RaisesOf(2) = 'EPMLArgument', 'チャンネル数 9 は EPMLArgument');
  Check(RaisesOf(3) = 'EPMLArgument', '知らない形式は EPMLArgument');
  Check(RaisesOf(4) = 'EPMLArgument', '知らない ID は開けない（EPMLArgument）');
  Check(RaisesOf(5) = 'EPMLArgument', '負の音量は EPMLArgument');

  WriteLn('-- 混ぜる');
  L2.Pause;
  Rec := TPostmixRecorder.Create;
  A := ConstStream(-0.25, 2, 48000, 48000);
  B := ConstStream(0.5, 2, 48000, 48000);
  L1.Gain := 0.5;
  L1.SetPostmixCallback(@Rec.OnPostmix);
  L1.BindStreams([A, B]);
  Check(Sys.StreamDevice(A) = L1, 'StreamDevice は結び付いた論理デバイス');
  Check(SameSpec(A.DstSpec, PML_AUDIO_F32, 2, 48000), '出力の側はデバイスの形式（混ぜるので F32）');
  A.SetDstFormat(Spec(PML_AUDIO_S16, 1, 22050));
  Check(SameSpec(A.DstSpec, PML_AUDIO_F32, 2, 48000), '結び付いた側の形式は黙って変えない');
  Rec.Reset;
  Check(WaitFor(@RecCalls2, 2000), '後置き処理が呼ばれる');
  Check(SingleBits(Rec.Last) = SingleBits(Single(0.125)),
    '0.5 x 0.5 + (-0.25) x 0.5 = 0.125（' + FloatToStr(Rec.Last) + '）');
  Check(SameSpec(Rec.LastSpec, PML_AUDIO_F32, 2, 48000) and (Rec.LastLen = 8192),
    '後置き処理は F32 2ch 48000、8192 バイト');
  L1.Gain := 3;
  Sleep(60);
  Rec.Reset;
  Check(WaitFor(@RecCalls2, 2000), '音量 3 でも呼ばれる');
  // 連なりは後から結んだ B が先。B: 1.5 → 1 に挟む、A: 1 - 0.75 = 0.25。
  // 最後にだけ挟むなら 0.75 になる。
  Check(SingleBits(Rec.Last) = SingleBits(Single(0.25)),
    '足すたびに -1..1 に挟む（0.25: ' + FloatToStr(Rec.Last) + '）');
  Check(Rec.MaxAbs <= 1.0, '1 を超えない');
  L1.SetPostmixCallback(nil);

  WriteLn('-- 一時停止と写すだけの道');
  Sys.UnbindStreams([A, B]);
  Check((Sys.StreamDevice(A) = nil) and (Sys.StreamDevice(B) = nil), '外すと StreamDevice は nil');
  A.Free;
  B.Free;
  L2.Free;
  L1.Gain := 1;
  C := ConstStream(0.1, 2, 48000, 4800);
  QOld := C.Queued;
  L1.Pause;
  L1.BindStream(C);
  Sleep(100);
  Check(C.Queued = QOld, '止まっている間は取り出さない');
  L1.Resume;
  Check(WaitFor(@CDrained, 2000), '動かすと取り出される（写すだけの道）');
  Check(SameSpec(C.DstSpec, PML_AUDIO_F32, 2, 48000), '写すだけの道でも出力の側はデバイスの形式');
  C.Free;  // 結び付いたまま壊す
  D := ConstStream(0.1, 2, 48000, 480);
  D2 := ConstStream(0.1, 2, 48000, 480);
  L1.BindStream(D);
  Check(Sys.StreamDevice(D) = L1, '結び付いたまま壊したストリームの後でも結べる');

  WriteLn('-- 結び付けの誤り');
  Check(RaisesOf(6) = 'EPMLArgument', 'nil があれば EPMLArgument');
  Check(Sys.StreamDevice(D2) = nil, '失敗したら何も結ばない（全部か、何もしないか）');
  Check(RaisesOf(7) = 'EPMLArgument', '同じストリームが 2 度あれば EPMLArgument（D-68。SDL は戻らない）');
  Check(Sys.StreamDevice(D2) = nil, '2 度のときも何も結ばない');
  Check(RaisesOf(8) = 'EPMLArgument', 'もう結び付いていれば EPMLArgument');
  Sys.UnbindStream(D);
  D.Free;

  WriteLn('-- 閉じる');
  L1.Free;
  Check(SameSpec(Sys.DeviceFormat(15, Frames), PML_AUDIO_S16, 2, 44100) and (Frames = 0),
    '最後の論理デバイスを閉じると物理デバイスも閉じ、形式は戻る（フレーム数は 0。SDL と同じ）');
  SID := 21;
  Check(RaisesOf(9) = 'EPMLArgument', '閉じた論理デバイスの ID は引けない');

  WriteLn('-- 再生でデバイスが並びを持つとき');
  // バックエンドの役をして、閉じている再生デバイスに並びを置く。
  PlayDev := Sys.FindDeviceByHandle(Pointer(PtrUInt(1)));
  PlayDev.ChannelMap := [1, 0];
  L1 := Sys.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK, Spec(PML_AUDIO_S16, 2, 48000));
  A := PairStream(0.25, -0.5, 48000, 48000);
  L1.SetPostmixCallback(@Rec.OnPostmix);  // 後置き処理があると混ぜる道を通る
  L1.BindStream(A);
  Map := A.OutputChannelMap;
  Check((Length(Map) = 2) and (Map[0] = 1) and (Map[1] = 0), '結び付けると、出力の並びはデバイスの並び');
  Rec.Reset;
  Check(WaitFor(@RecCalls2, 2000), '後置き処理が呼ばれる');
  Check((Rec.Last = -0.5) and (Rec.Last1 = 0.25),
    Format('ストリームがデバイスの並びにする（%g %g）', [Rec.Last, Rec.Last1]));
  L1.Pause;
  Sleep(60);
  A.SetOutputChannelMap(nil);
  L1.Resume;
  Sleep(60);
  Rec.Reset;
  Check(WaitFor(@RecCalls2, 2000), '後置き処理が呼ばれる（並びを既定に）');
  Check((Rec.Last = -0.5) and (Rec.Last1 = 0.25),
    Format('出力の並びを既定にすると、デバイスのスレッドがデバイスの並びにする（S16 のデバイスで' +
      'F32 の置き場のまま。D-67: %g %g）', [Rec.Last, Rec.Last1]));
  L1.Free;
  A.Free;
  PlayDev.ChannelMap := nil;

  WriteLn('-- 簡易パス');
  G := TGetRecorder.Create;
  S := Sys.OpenDeviceStream(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK, Spec(PML_AUDIO_F32, 2, 48000), @G.OnGet);
  Check(Sys.StreamDevicePaused(S), '一時停止で始まる（SDL2 と同じ）');
  Check(Sys.StreamDevice(S) <> nil, 'StreamDevice がある');
  Sleep(60);
  Check(G.Calls = 0, '止まっている間は OnGet が来ない');
  Sys.ResumeStreamDevice(S);
  Check(WaitFor(@GCalled, 2000), '動かすと OnGet が来る');
  Check((G.FirstAdd = 8192) and (G.FirstTotal = 8192),
    Format('最初の OnGet は 8192 / 8192 バイト（SDL 3.4.2 と同じ: %d / %d）', [G.FirstAdd, G.FirstTotal]));
  Check(RaisesOf(10) = 'EPMLArgument', '簡易パスのデバイスには結べない');
  Sys.UnbindStream(S);
  Check(Sys.StreamDevice(S) <> nil, '簡易パスのストリームは外れない');
  SID := Sys.StreamDevice(S).ID;
  S.Free;
  Check(RaisesOf(9) = 'EPMLArgument', 'ストリームを Free するとデバイスも閉じる');
  Check(Sys.DeviceFormat(15, Frames).Freq = 44100, '物理デバイスも閉じる');
  G.Free;

  WriteLn('-- 録音');
  S := Sys.OpenDeviceStream(PML_AUDIO_DEVICE_DEFAULT_RECORDING, Spec(PML_AUDIO_S16, 1, 44100));
  Sys.ResumeStreamDevice(S);
  Sleep(200);
  FillChar(Buf16, SizeOf(Buf16), $55);
  Got := S.GetData(@Buf16[0], 128);
  AllZero := True;
  for I := 0 to 63 do
    if Buf16[I] <> 0 then
      AllZero := False;
  Check((Got = 128) and AllZero, Format('dummy の録音は無音（%d バイト）', [Got]));
  S.Free;

  // D-67: 後置き処理で値を書き、ストリームの入力の並びを入れ替える。
  W := TPostmixWriter.Create;
  LR := Sys.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_RECORDING, Spec(PML_AUDIO_S16, 2, 44100));
  Check(SameSpec(LR.Format, PML_AUDIO_S16, 2, 44100), '録音も求めた形式で開く（D-66）');
  T := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 2, 44100), Spec(PML_AUDIO_F32, 2, 44100));
  LR.SetPostmixCallback(@W.OnPostmix);
  LR.BindStream(T);
  Check(T.SrcSpec.Format = PML_AUDIO_F32, '後置き処理があると、入力の側は F32');
  Sleep(100);
  Got := T.GetData(@BufF[0], SizeOf(BufF));
  Check((Got = SizeOf(BufF)) and (BufF[0] = 0.25) and (BufF[1] = -0.5) and (BufF[6] = 0.25) and (BufF[7] = -0.5),
    Format('後置き処理の値が入る（%g %g）', [BufF[0], BufF[1]]));
  LR.Pause;
  Sleep(60);
  T.SetInputChannelMap([1, 0]);
  T.Clear;
  LR.Resume;
  Sleep(100);
  Got := T.GetData(@BufF[0], SizeOf(BufF));
  Check((Got = SizeOf(BufF)) and (BufF[0] = -0.5) and (BufF[1] = 0.25) and (BufF[6] = -0.5) and (BufF[7] = 0.25),
    Format('入れ替えた並びで入る（D-67。SDL は値が壊れる: %g %g）', [BufF[0], BufF[1]]));

  // 開き直し: S16 で開いている間に F32 を求める。
  DrainEvents(Ctx);
  LF := Sys.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_RECORDING, Spec(PML_AUDIO_F32, 2, 44100));
  Check(SameSpec(LF.Format, PML_AUDIO_F32, 2, 44100), '高い形式（F32）で開き直す');
  Evs := DrainEvents(Ctx);
  Check(HasAudioEvent(Evs, TPMLEventKind.AudioDeviceFormatChanged, 18)
    and HasAudioEvent(Evs, TPMLEventKind.AudioDeviceFormatChanged, LR.ID)
    and not HasAudioEvent(Evs, TPMLEventKind.AudioDeviceFormatChanged, LF.ID),
    '開き直すと、物理デバイスと、そこにあった論理デバイスに形式の変更が来る');
  Sleep(100);
  Got := T.GetData(@BufF[0], SizeOf(BufF));
  Check((Got = SizeOf(BufF)) and (BufF[0] = -0.5) and (BufF[1] = 0.25),
    Format('開き直した後も後置き処理と並びが効く（%g %g）', [BufF[0], BufF[1]]));
  LF.Free;
  T.Free;
  LR.Free;

  // デバイスが並びを持つとき（バックエンドの役をして、閉じている録音デバイスに置く）。
  // D-71: F32 のデバイスで、デバイスの並びを外す置き場（SDL は作らないので落ちる）。
  RecDev := Sys.FindDeviceByHandle(Pointer(PtrUInt(2)));
  Check((RecDev <> nil) and (RecDev.InstanceID = 18), 'ハンドル 2 は録音の物理デバイス');
  RecDev.ChannelMap := [1, 0];
  LF := Sys.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_RECORDING, Spec(PML_AUDIO_F32, 2, 44100));
  Map := Sys.DeviceChannelMap(LF.ID);
  Check((Length(Map) = 2) and (Map[0] = 1) and (Map[1] = 0), 'デバイスの並び');
  T3 := TPMLAudioStream.Create(Spec(PML_AUDIO_F32, 2, 44100), Spec(PML_AUDIO_F32, 2, 44100));
  LF.SetPostmixCallback(@W.OnPostmix);
  LF.BindStream(T3);
  Map := T3.InputChannelMap;
  Check((Length(Map) = 2) and (Map[0] = 1) and (Map[1] = 0), '結び付けると、入力の並びはデバイスの並び');
  Sleep(100);
  Got := T3.GetData(@BufF[0], SizeOf(BufF));
  Check((Got = SizeOf(BufF)) and (BufF[0] = -0.5) and (BufF[1] = 0.25),
    Format('ストリームがデバイスの並びを外す（%g %g）', [BufF[0], BufF[1]]));
  LF.Pause;
  Sleep(60);
  T3.SetInputChannelMap(nil);
  T3.Clear;
  LF.Resume;
  Sleep(100);
  Got := T3.GetData(@BufF[0], SizeOf(BufF));
  Check((Got = SizeOf(BufF)) and (BufF[0] = -0.5) and (BufF[1] = 0.25),
    Format('入力の並びを既定にすると、デバイスのスレッドがデバイスの並びを外す（D-67、D-71: %g %g）',
      [BufF[0], BufF[1]]));
  T3.Free;
  LF.Free;
  RecDev.ChannelMap := nil;

  // D-70: 音量だけ（後置き処理なし）。
  LG := Sys.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_RECORDING, Spec(PML_AUDIO_S16, 2, 44100));
  T2 := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 2, 44100), Spec(PML_AUDIO_F32, 2, 44100));
  LG.Gain := 0.5;
  LG.BindStream(T2);
  Check(T2.SrcSpec.Format = PML_AUDIO_F32, '音量が 1 でなければ、入力の側は F32');
  Sleep(100);
  Check(T2.Queued > 0, '音量だけでも止まらない（D-70。SDL は落ちる）');
  T2.Free;
  LG.Free;

  // D-69: 論理デバイスが 2 つ。新しい方（連なりの先頭）だけに後置き処理。
  LOld := Sys.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_RECORDING, Spec(PML_AUDIO_S16, 2, 44100));
  LNew := Sys.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_RECORDING, Spec(PML_AUDIO_S16, 2, 44100));
  LOld.Pause;
  LNew.Pause;
  LNew.SetPostmixCallback(@W.OnNothing);
  SOld := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 2, 44100), Spec(PML_AUDIO_F32, 2, 44100));
  SNew := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 2, 44100), Spec(PML_AUDIO_F32, 2, 44100));
  LOld.BindStream(SOld);
  LNew.BindStream(SNew);
  Check((SOld.SrcSpec.Format = PML_AUDIO_S16) and (SNew.SrcSpec.Format = PML_AUDIO_F32),
    '入力の側: 後置き処理の無い方は S16、ある方は F32');
  SOld.Lock;
  SNew.Lock;
  LOld.Resume;
  LNew.Resume;
  SNew.Unlock;
  SOld.Unlock;
  Sleep(150);
  SOld.Lock;
  SNew.Lock;
  LOld.Pause;
  LNew.Pause;
  SNew.Unlock;
  SOld.Unlock;
  Sleep(60);
  QOld := SOld.Queued;
  QNew := SNew.Queued;
  FramesOld := QOld div 4;
  FramesNew := QNew div 8;
  Check((FramesNew >= 2048) and (Abs(FramesOld - FramesNew) <= 1024),
    Format('どちらにも同じフレーム数が入る（D-69。SDL は後の方が 2 倍: %d / %d）', [FramesOld, FramesNew]));
  SOld.Free;
  SNew.Free;
  LNew.Free;
  LOld.Free;
  W.Free;

  WriteLn('-- アプリの呼び出しの例外');
  Thrower := TGetRecorder.Create;
  Q := Sys.OpenDeviceStream(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK, Spec(PML_AUDIO_F32, 2, 48000), @Thrower.OnThrow);
  Sys.ResumeStreamDevice(Q);
  Check(WaitFor(@ThrowerPaused, 2000), 'OnGet が例外を投げると、論理デバイスが止まる（DESIGN §5.5）');
  Check(Thrower.Calls >= 1, 'OnGet は呼ばれた');
  Q.Free;
  Thrower.Free;

  WriteLn('-- 切断と既定の変更');
  DrainEvents(Ctx);
  LE := Sys.OpenDevice(15);
  LD := Sys.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK);
  LEID := LE.ID;
  LDID := LD.ID;
  Dev := Sys.FindDeviceByHandle(Pointer(PtrUInt(1)));
  Check((Dev <> nil) and (Dev.InstanceID = 15), 'ハンドル 1 は再生の物理デバイス');
  Disc := TDisconnector.Create('disconnect', True);
  Disc.Sys := Sys;
  Disc.Dev := Dev;
  Disc.Start;
  Disc.WaitFor;
  Disc.Free;
  Check(Length(Sys.PlaybackDevices) = 0, '失われた印が付くと一覧から消える');
  Evs := DrainEvents(Ctx);
  Check(HasAudioEvent(Evs, TPMLEventKind.AudioDeviceRemoved, 15)
    and HasAudioEvent(Evs, TPMLEventKind.AudioDeviceRemoved, LEID)
    and not HasAudioEvent(Evs, TPMLEventKind.AudioDeviceRemoved, LDID)
    and (CountKind(Evs, TPMLEventKind.AudioDeviceRemoved) = 2),
    '別のスレッドの切断は次の Poll で知らされる: 物理と名指しの論理だけ（既定として開いたものは移るので除く）');
  Check(RaisesOf(11) = 'EPMLAudioError', '失われたデバイスを名指しでは開けない');
  LTmp := Sys.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK);
  Check(LTmp <> nil, '既定としてなら開ける（後で移る）');
  LTmp.Free;
  Q := ConstStream(0.1, 2, 44100, 4410);
  LE.BindStream(Q);
  Check(WaitFor(@QDrained, 2000), '失われたデバイスも無音として進み続ける');
  Sys.UnbindStream(Q);
  Q.Free;

  Z := ConstStream(0.1, 2, 48000, 480);
  Z.SetSrcFormat(Spec(PML_AUDIO_F32, 2, 48000));
  LD.BindStream(Z);
  DrainEvents(Ctx);
  NewDev := Sys.AddDevice(False, 'Second playback', 'uid-2', Spec(PML_AUDIO_S16, 2, 44100), Pointer(PtrUInt(3)));
  Sys.DefaultDeviceChanged(NewDev);
  Check(Sys.DeviceName(LDID) = 'Second playback', '既定として開いた論理デバイスは新しい既定へ移る');
  Check(Sys.DeviceName(LEID) = 'System audio playback device', '名指しで開いたものは残る');
  Check(SameSpec(LD.Format, PML_AUDIO_F32, 2, 48000),
    '新しい既定は、結び付いたストリームの形式で開く（' + SpecText(LD.Format) + '）');
  Check(SameSpec(Z.DstSpec, PML_AUDIO_F32, 2, 48000), '移ったストリームの出力の側は新しいデバイスの形式');
  Check(Sys.DeviceUniqueID(NewDev.InstanceID) = 'uid-2', '一意の名前');
  IDs := Sys.PlaybackDevices;
  Check((Length(IDs) = 1) and (IDs[0] = NewDev.InstanceID), '一覧は新しいデバイスだけ');
  Evs := DrainEvents(Ctx);
  Check(HasAudioEvent(Evs, TPMLEventKind.AudioDeviceAdded, NewDev.InstanceID), '追加のイベント');
  Check(HasAudioEvent(Evs, TPMLEventKind.AudioDeviceFormatChanged, LDID), '形式が変わったので、移った論理デバイスに知らせる');
  Check(Sys.DeviceName(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK) = 'Second playback', '既定の印は新しいデバイス');
  LE.Free;
  Check(RaisesOf(12) = 'EPMLArgument', '参照が尽きると、失われた物理デバイスは消える');
  Check(RaisesOf(13) = 'EPMLArgument', '閉じた論理デバイスも引けない');

  WriteLn('-- 系が先に壊れる');
  Y := Sys.OpenDeviceStream(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK, Spec(PML_AUDIO_F32, 2, 48000));
  Ctx.Free;  // LD は系が Free する
  Check(Z.Binding.Device = nil, '結び付けは外れる');
  Check(Y.Binding.Device = nil, '簡易パスのストリームも外れる');
  Z.PutData(@BufF[0], SizeOf(BufF));
  Check(Z.Available > 0, 'ストリームはそのまま使える');
  Z.Free;
  Y.Free;
  Rec.Free;
  D2.Free;
end;

{ ---- 10. ヒントとカンマの並び ---- }

procedure TestHints;
var
  Ctx: TPMLContext;
  Frames: Integer;
  L: TPMLLogicalAudioDevice;
  P: TPMLAudioDeviceIDs;
begin
  WriteLn('-- ヒント');
  Ctx := MakeContext('nosuch, dummy', [PML_HINT_AUDIO_DEVICE_SAMPLE_FRAMES, '256',
    PML_HINT_AUDIO_FORMAT, 'F32', PML_HINT_AUDIO_CHANNELS, '4', PML_HINT_AUDIO_FREQUENCY, '22050']);
  try
    Check(Ctx.Audio.BackendName = 'dummy', 'カンマで並べた名前を順に試す');
    P := Ctx.Audio.PlaybackDevices;
    Check(Length(P) = 1, '再生のデバイスが 1 台');
    Ctx.Audio.DeviceFormat(P[0], Frames);
    Check(Frames = 256, '1 回分のフレーム数のヒント');
    L := Ctx.Audio.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK, Spec(0, 0, 0));
    Check(SameSpec(L.Format, PML_AUDIO_F32, 4, 22050) and (L.SampleFrames = 256),
      '0 の欄はヒントで埋まる（' + SpecText(L.Format) + '）');
    L.Free;
    L := Ctx.Audio.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK);
    Check(SameSpec(L.Format, PML_AUDIO_S16, 2, 44100), '形式を渡さなければデバイスの既定（ヒントは使わない。SDL と同じ）');
    L.Free;
  finally
    Ctx.Free;
  end;
end;

var
  Dog: TWatchdog;
begin
  WriteLn('=== test_audio_device ===');
  Dog := TWatchdog.Create('watchdog', True);
  Dog.LimitMs := 60000;
  Dog.Start;
  try
    TestSelection;
    TestMain;
    TestHints;
  except
    on E: Exception do
    begin
      WriteLn('  [FAIL] 例外: ', E.ClassName, ': ', E.Message);
      Inc(Failures);
    end;
  end;
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
