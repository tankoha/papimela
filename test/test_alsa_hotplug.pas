{
  test_alsa_hotplug — ALSA の hotplug の切り替え（udev の知らせで走査する。TPMLAlsaHotplugDriver）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    SDL の ALSA_start_udev / ALSA_udev_callback / ALSA_stop_udev の振る舞いを、偽の udev の窓口
    （IPMLAlsaHotplugSource）で確かめる。libasound も udev も要らない:
    1. 始める: udev が使えれば UsingUdev（以後スレッドを使わない）、使えなければ False（呼び出し側が走査の
       スレッドを持つ）。2 度目の Start は何もしない
    2. 知らせ: 追加でも取り外しでも走査する（SDL は種類を見ない）。devpath が空の知らせは捨てる
    3. Poll: 使っているとき窓口の Poll を呼ぶ。使っていなければ何もしない。窓口が溜めた知らせは Poll の中で
       呼び出しスレッドへ届く
    4. 止める: 窓口を止める。止めた後は Poll しない・知らせても走査しない。何度止めてもよい。壊すときも止める
    5. 走査が例外を投げても Poll は外へ出さず、LastError に残す
    6. 本物の窓口（libudev）: 使える環境なら、Start と Poll と Stop が例外を出さない（飛ばしてよい環境もある）

  WHY:
    SDL の ALSA は udev が使えれば、5 秒ごとの走査でなく、抜き差しの知らせですぐ走査する。
    papimela は走査のスレッドだけだったので、USB の声卓などを抜き差ししても最大 5 秒遅れた。
    実機の確認は test_audio_alsa_hotplug（手元専用。snd-dummy を modprobe して見る）。
}
program test_alsa_hotplug;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes,
  PaPiMeLa.Errors,
  PaPiMeLa.Audio.Alsa;

type
  TPending = record
    Added: Boolean;
    Path: String;
  end;
  TPendingArray = array of TPending;

  TFakeSource = class(TInterfacedObject, IPMLAlsaHotplugSource)
  public
    Callback: TPMLAlsaHotplugCallback;
    StartResult: Boolean;
    RaiseOnStart: Boolean;
    Started, Stopped: Boolean;
    StartCount, PollCount, StopCount: Integer;
    // Poll で届ける知らせ
    Pending: TPendingArray;
    constructor Create(AStartResult: Boolean);
    function  Start(ACallback: TPMLAlsaHotplugCallback): Boolean;
    procedure Poll;
    procedure Stop;
    procedure Queue(AAdded: Boolean; const APath: String);
  end;

  TScanner = class
  public
    Count: Integer;
    FailNext: Boolean;
    procedure Scan;
  end;

var
  Failures: Integer = 0;
  Fake: TFakeSource = nil;       // 直近に作った偽物（解放は参照の側）
  FakeRef: IPMLAlsaHotplugSource = nil;
  FakeStartResult: Boolean = True;
  RaiseNext: Boolean = False;
  FactoryCalls: Integer = 0;

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

constructor TFakeSource.Create(AStartResult: Boolean);
begin
  inherited Create;
  StartResult := AStartResult;
end;

function TFakeSource.Start(ACallback: TPMLAlsaHotplugCallback): Boolean;
begin
  Inc(StartCount);
  if RaiseOnStart then
    raise Exception.Create('cannot open udev');
  Result := StartResult;
  if Result then
  begin
    Callback := ACallback;
    Started := True;
  end;
end;

procedure TFakeSource.Poll;
var
  I: Integer;
  Local: TPendingArray;
begin
  Inc(PollCount);
  if not Started then
    Exit;
  Local := Pending;
  Pending := nil;
  for I := 0 to High(Local) do
    if Assigned(Callback) then
      Callback(Local[I].Added, Local[I].Path);
end;

procedure TFakeSource.Stop;
begin
  Inc(StopCount);
  Stopped := True;
  Started := False;
  Callback := nil;
end;

procedure TFakeSource.Queue(AAdded: Boolean; const APath: String);
begin
  SetLength(Pending, Length(Pending) + 1);
  Pending[High(Pending)].Added := AAdded;
  Pending[High(Pending)].Path := APath;
end;

procedure TScanner.Scan;
begin
  Inc(Count);
  if FailNext then
  begin
    FailNext := False;
    raise Exception.Create('scan failed');
  end;
end;

var
  DummyFake: TFakeSource = nil;

// 偽物がまだ作られていなければ（実装が窓口を作らないとき）、数が 0 の見本を返す。検査が落ちるだけで止まらないように
function FK: TFakeSource;
begin
  if Fake <> nil then
    Result := Fake
  else
  begin
    if DummyFake = nil then
      DummyFake := TFakeSource.Create(False);
    Result := DummyFake;
  end;
end;

function MakeFake: IPMLAlsaHotplugSource;
begin
  Inc(FactoryCalls);
  Fake := TFakeSource.Create(FakeStartResult);
  Fake.RaiseOnStart := RaiseNext;
  FakeRef := Fake;
  Result := Fake;
end;

procedure NewDriver(out ADriver: TPMLAlsaHotplugDriver; AScanner: TScanner; AStartResult: Boolean);
begin
  FactoryCalls := 0;
  FakeStartResult := AStartResult;
  Fake := nil;
  FakeRef := nil;
  PMLAlsaHotplugSourceFactory := @MakeFake;
  ADriver := TPMLAlsaHotplugDriver.Create(@AScanner.Scan);
end;

procedure TestStart;
var
  D: TPMLAlsaHotplugDriver;
  S: TScanner;
begin
  WriteLn('1 始める');
  S := TScanner.Create;
  NewDriver(D, S, True);
  try
    Check(not D.UsingUdev, '作っただけでは udev を使わない');
    Check(D.StartUdev, 'udev が使えれば StartUdev は True');
    Check(D.UsingUdev, 'UsingUdev');
    Check((Fake <> nil) and (FK.StartCount = 1) and FK.Started, '窓口の Start が呼ばれ、コールバックが登録された');
    Check(D.StartUdev, '2 度目の StartUdev も True');
    Check((FactoryCalls = 1) and (FK.StartCount = 1), '2 度目は窓口を作り直さない・Start し直さない');
    Check(S.Count = 0, 'Start だけでは走査しない（最初の走査は呼び出し側が先に行う）');
  finally
    D.Free;
    FakeRef := nil;
    S.Free;
  end;
  S := TScanner.Create;
  NewDriver(D, S, False);
  try
    Check(not D.StartUdev, 'udev が使えなければ StartUdev は False');
    Check(not D.UsingUdev, 'UsingUdev は False');
    D.Poll;
    Check((Fake <> nil) and (FK.PollCount = 0), '使っていなければ Poll は窓口を呼ばない');
    Check(S.Count = 0, 'スレッドの道は走査を呼ばない（呼び出し側のスレッドの仕事）');
    D.Stop;
    Check(True, '使っていなくても Stop は安全');
  finally
    D.Free;
    FakeRef := nil;
    S.Free;
  end;
end;

procedure TestStartRaises;
var
  D: TPMLAlsaHotplugDriver;
  S: TScanner;
  Raised: Boolean;
  Got: Boolean;
begin
  WriteLn('1b 窓口の Start が例外を投げたとき');
  S := TScanner.Create;
  RaiseNext := True;
  NewDriver(D, S, True);
  Raised := False;
  Got := True;
  try
    try
      Got := D.StartUdev;
    except
      on E: Exception do
        Raised := True;
    end;
    RaiseNext := False;
    Check(not Raised, 'StartUdev は窓口の例外を外へ出さない');
    Check(not Got and not D.UsingUdev, '例外なら False（スレッドの道へ譲る）');
    Check(D.LastError <> '', 'LastError に残る: ' + D.LastError);
  finally
    D.Free;
    FakeRef := nil;
    S.Free;
  end;
end;

procedure TestEvents;
var
  D: TPMLAlsaHotplugDriver;
  S: TScanner;
begin
  WriteLn('2 知らせと Poll');
  S := TScanner.Create;
  NewDriver(D, S, True);
  try
    D.StartUdev;
    FK.Queue(True, '/devices/platform/soc/sound/card1');
    Check(S.Count = 0, 'Poll の前は走査しない（知らせは窓口に溜まっている）');
    D.Poll;
    Check(FK.PollCount = 1, 'Poll は窓口の Poll を呼ぶ');
    Check(S.Count = 1, '追加の知らせで 1 回走査する');
    FK.Queue(False, '/devices/platform/soc/sound/card1');
    D.Poll;
    Check(S.Count = 2, '取り外しの知らせでも 1 回走査する（SDL は種類を見ない）');
    FK.Queue(True, '');
    D.Poll;
    Check(S.Count = 2, 'devpath が空の知らせは捨てる');
    FK.Queue(True, '/devices/virtual/input/input5');
    FK.Queue(False, '/devices/virtual/input/input5');
    D.Poll;
    Check(S.Count = 4, '知らせの種類（sound か input か）で絞らない（SDL は devpath があれば走査する）');
    D.Poll;
    D.Poll;
    Check(FK.PollCount = 6, 'Poll のたびに窓口の Poll を呼ぶ（この節で 6 回呼んだ）');
    Check(S.Count = 4, '知らせが無ければ走査しない');
  finally
    D.Free;
    FakeRef := nil;
    S.Free;
  end;
end;

procedure TestStop;
var
  D: TPMLAlsaHotplugDriver;
  S: TScanner;
  F: TFakeSource;
begin
  WriteLn('3 止める');
  S := TScanner.Create;
  NewDriver(D, S, True);
  try
    D.StartUdev;
    F := FK;
    D.Stop;
    Check(F.Stopped and (F.StopCount = 1), 'Stop は窓口を止める');
    Check(not D.UsingUdev, '止めたら UsingUdev は False');
    D.Poll;
    Check(F.PollCount = 0, '止めた後の Poll は窓口を呼ばない');
    D.Stop;
    Check(F.StopCount = 1, '2 度目の Stop は何もしない');
  finally
    D.Free;
    FakeRef := nil;
    S.Free;
  end;
  // 壊すときも止める
  S := TScanner.Create;
  NewDriver(D, S, True);
  D.StartUdev;
  F := FK;
  D.Free;
  Check(F.Stopped, '壊すときに窓口を止める');
  FakeRef := nil;
  S.Free;
end;

procedure TestScanFailure;
var
  D: TPMLAlsaHotplugDriver;
  S: TScanner;
  Raised: Boolean;
begin
  WriteLn('4 走査が失敗したとき');
  S := TScanner.Create;
  NewDriver(D, S, True);
  try
    D.StartUdev;
    S.FailNext := True;
    FK.Queue(True, '/devices/x/sound/card2');
    FK.Queue(True, '/devices/x/sound/card3');
    Raised := False;
    try
      D.Poll;
    except
      on E: Exception do
        Raised := True;
    end;
    Check(not Raised, 'Poll は走査の例外を外へ出さない');
    Check(D.LastError <> '', 'LastError に残る: ' + D.LastError);
    Check(S.Count = 2, '失敗しても、次の知らせは走査する');
  finally
    D.Free;
    FakeRef := nil;
    S.Free;
  end;
end;

procedure TestReal;
var
  D: TPMLAlsaHotplugDriver;
  S: TScanner;
  Raised: Boolean;
  Started: Boolean;
begin
  WriteLn('5 本物の窓口（libudev）');
  PMLAlsaHotplugSourceFactory := nil;
  S := TScanner.Create;
  D := TPMLAlsaHotplugDriver.Create(@S.Scan);
  Raised := False;
  Started := False;
  try
    try
      Started := D.StartUdev;
      D.Poll;
      D.Poll;
      D.Stop;
    except
      on E: Exception do
      begin
        Raised := True;
        WriteLn('    ', E.ClassName, ': ', E.Message);
      end;
    end;
    Check(not Raised, 'Start / Poll / Stop が例外を出さない');
    WriteLn('  [INFO] 本物の udev: ', BoolToStr(Started, '使えた', '使えなかった（libudev が無い・netlink が使えない環境）'));
    Check(S.Count >= 0, '走査の数は不定（実機の udev が知らせを出すかによる）');
  finally
    D.Free;
    S.Free;
  end;
end;

begin
  WriteLn('=== test_alsa_hotplug ===');
  TestStart;
  TestStartRaises;
  TestEvents;
  TestStop;
  TestScanFailure;
  TestReal;
  PMLAlsaHotplugSourceFactory := nil;
  WriteLn;
  if Failures = 0 then
    WriteLn('ALL PASSED')
  else
    WriteLn('FAILED: ', Failures);
  if Failures <> 0 then
    Halt(1);
end.
