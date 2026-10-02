{
  test_time — 待つ API（Delay / DelayNS / DelayPrecise）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. DelayPrecise の手順を偽の時計で動かし、眠りの列と空回りの回数が
       SDL_DelayPrecise と同じになることを見る（決定的）
    2. 本物の時計で、早く戻らないこと、遅れが小さいこと
    3. 待っている間 CPU を使わないこと（プロセスの CPU 時間で測る）
    4. 眠りがシグナルで割り込まれても、残りを寝直すこと（EINTR）
    5. TPMLTimerService から Context 無しで呼べること

  WHY:
    #9 の受け入れ検査。実装より先に書いた。

    本物の時計だけで検査すると、「ずっと空回りする」実装も「1 回眠って
    終わる」実装も通ってしまう。前者は 3 の CPU 時間で、後者は 4 の
    割り込みで落とす。DelayPrecise の手順（1 ms ずつ眠って遅れの最大を測り、
    残りを短く眠り、端数だけ空回り）は、本物の時計では揺れて比べられないので、
    偽の時計で眠りの列を比べる。期待する列は SDL_timer.c の SDL_DelayPrecise を
    手で辿って求めた（場面ごとのコメント）。

    時間の上限は CI の共有の機械でも通るよう緩くしてある（下限は厳密）。

  実行前提: 無し。
}
program test_time;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, BaseUnix, UnixType,
  PaPiMeLa.Events,
  PaPiMeLa.Time,
  PaPiMeLa.Core;

const
  MS = UInt64(1000000);

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

function MsStr(ANs: UInt64): String;
begin
  Result := FormatFloat('0.000', ANs / MS) + ' ms';
end;

{ ---- 偽の時計 ---- }

var
  FakeNow      : UInt64;
  Sleeps       : array of UInt64;
  Pauses       : Integer;
  // 眠りは「頼んだ長さ x SleepNum / SleepDen + SleepExtra」だけ時計を進める。
  SleepNum, SleepDen: UInt64;
  SleepExtra   : UInt64;
  FirstExtra   : UInt64;      // 最初の眠りだけに足す遅れ
  PauseStep    : UInt64;

function FakeNowFunc: UInt64;
begin
  Result := FakeNow;
end;

procedure FakeSleep(ANs: UInt64);
begin
  SetLength(Sleeps, Length(Sleeps) + 1);
  Sleeps[High(Sleeps)] := ANs;
  FakeNow := FakeNow + ANs * SleepNum div SleepDen + SleepExtra;
  if Length(Sleeps) = 1 then
    FakeNow := FakeNow + FirstExtra;
end;

procedure FakePause;
begin
  Inc(Pauses);
  FakeNow := FakeNow + PauseStep;
end;

procedure ResetFake(ANum, ADen, AExtra, AFirstExtra, APause: UInt64);
begin
  FakeNow := 0;
  SetLength(Sleeps, 0);
  Pauses := 0;
  SleepNum := ANum;
  SleepDen := ADen;
  SleepExtra := AExtra;
  FirstExtra := AFirstExtra;
  PauseStep := APause;
end;

function SleepsStr: String;
var
  I: Integer;
begin
  Result := '[';
  for I := 0 to High(Sleeps) do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + IntToStr(Sleeps[I]);
  end;
  Result := Result + ']';
end;

function SameSleeps(const AWant: array of UInt64): Boolean;
var
  I: Integer;
begin
  Result := Length(Sleeps) = Length(AWant);
  if Result then
    for I := 0 to High(AWant) do
      if Sleeps[I] <> AWant[I] then
        Exit(False);
end;

procedure Scenario(const ALabel: String; ATarget: UInt64;
  const AWantSleeps: array of UInt64; AWantPauses: Integer; AWantEnd: UInt64);
begin
  PMLDelayPreciseWith(ATarget, @FakeNowFunc, @FakeSleep, @FakePause);
  Check(SameSleeps(AWantSleeps) and (Pauses = AWantPauses) and (FakeNow = AWantEnd),
    Format('%s（眠り %s、空回り %d 回、終わり %d）', [ALabel, SleepsStr, Pauses, FakeNow]));
end;

procedure TestPreciseSteps;
begin
  WriteLn('1. DelayPrecise の手順（偽の時計）');

  // 眠りが毎回 0.3 ms 遅れる。目標 5 ms:
  //   1 ms ずつ: 0 → 1.3 → 2.6 → 3.9（遅れの最大 1.3。3.9 + 1.3 >= 5 で止める）
  //   短い眠り: 残り 1.1 から遅れの分 0.3 を引いて 0.8 → 5.0。空回りなし
  ResetFake(1, 1, 300000, 0, 1000);
  Scenario('毎回 0.3 ms 遅れる眠りで 5 ms', 5 * MS, [MS, MS, MS, 800000], 0, 5 * MS);

  // 眠りが正確。目標 3.5 ms: 1 ms を 3 回、残り 0.5 ms を 1 回
  ResetFake(1, 1, 0, 0, 1000);
  Scenario('正確な眠りで 3.5 ms', 3500000, [MS, MS, MS, 500000], 0, 3500000);

  // 眠りが頼んだ長さの 9 割しか眠らない。目標 2 ms:
  //   1 ms ずつ: 0 → 0.9 → 1.8（遅れの最大は 1 ms のまま）
  //   短い眠り: 残り 0.2 → 0.18 しか進まず 1.98
  //   空回り: 5 us ずつ 4 回で 2.0
  ResetFake(9, 10, 0, 0, 5000);
  Scenario('短く眠る OS で 2 ms（最後は空回り）', 2 * MS, [MS, MS, 200000], 4, 2 * MS);

  // 最初の眠りだけ 2 ms 遅れる。目標 10 ms:
  //   1 ms ずつ: 0 → 3（遅れの最大 3）→ 4 → 5 → 6 → 7（7 + 3 >= 10 で止める）
  //   短い眠り: 残り 3 から (3 - 1) を引いて 1 ms → 8
  //   2 つめの 1 ms ずつ: 8 → 9（9 + 1 >= 10 で止める）
  //   空回り: 0.25 ms ずつ 4 回で 10
  // 1 ms の眠りは 5 回 + 短い眠り 1 回 + 2 つめの 1 ms ずつ 1 回 = 7 回（最初は 8 回と
  // 書き誤っていた。実装した Sonnet が指摘し、手で辿り直して確かめた）。
  ResetFake(1, 1, 0, 2 * MS, 250000);
  Scenario('最初の眠りだけ大きく遅れる 10 ms', 10 * MS,
    [MS, MS, MS, MS, MS, MS, MS], 4, 10 * MS);

  ResetFake(1, 1, 0, 0, 1000);
  Scenario('0 ns は眠らない', 0, [], 0, 0);
  WriteLn;
end;

{ ---- 本物の時計 ---- }

const
  CLOCK_PROCESS_CPUTIME_ID = 2;

function clock_gettime(clk_id: LongInt; tp: PTimeSpec): LongInt; cdecl;
  external 'c' name 'clock_gettime';

function CpuNS: UInt64;
var
  TS: TTimeSpec;
begin
  if clock_gettime(CLOCK_PROCESS_CPUTIME_ID, @TS) = 0 then
    Result := UInt64(TS.tv_sec) * 1000000000 + UInt64(TS.tv_nsec)
  else
    Result := 0;
end;

procedure TestRealDelays;
var
  T0, Took: UInt64;
  I, Early: Integer;
  Over: array[0..19] of UInt64;
  Tmp: UInt64;
  J: Integer;
begin
  WriteLn('2. 本物の時計');
  T0 := PMLNowNS;
  PMLDelay(0);
  Took := PMLNowNS - T0;
  Check(Took < 5 * MS, 'Delay(0) はすぐ戻る（' + MsStr(Took) + '）');

  T0 := PMLNowNS;
  PMLDelay(20);
  Took := PMLNowNS - T0;
  Check((Took >= 20 * MS) and (Took < 200 * MS), 'Delay(20) は 20 ms 以上（' + MsStr(Took) + '）');

  T0 := PMLNowNS;
  PMLDelayNS(5 * MS);
  Took := PMLNowNS - T0;
  Check((Took >= 5 * MS) and (Took < 150 * MS), 'DelayNS(5 ms) は 5 ms 以上（' + MsStr(Took) + '）');

  T0 := PMLNowNS;
  PMLDelayNS(0);
  Took := PMLNowNS - T0;
  Check(Took < 5 * MS, 'DelayNS(0) はすぐ戻る（' + MsStr(Took) + '）');

  Early := 0;
  for I := 0 to High(Over) do
  begin
    T0 := PMLNowNS;
    PMLDelayPrecise(3 * MS);
    Took := PMLNowNS - T0;
    if Took < 3 * MS then
    begin
      Inc(Early);
      Over[I] := 0;
    end
    else
      Over[I] := Took - 3 * MS;
  end;
  // 中央値（20 個を並べて 10 番目）
  for I := 0 to High(Over) do
    for J := I + 1 to High(Over) do
      if Over[J] < Over[I] then
      begin
        Tmp := Over[I];
        Over[I] := Over[J];
        Over[J] := Tmp;
      end;
  Check(Early = 0, Format('DelayPrecise(3 ms) は 20 回とも早く戻らない（早かった回数 %d）', [Early]));
  Check(Over[10] < MS, 'DelayPrecise(3 ms) の遅れの中央値は 1 ms 未満（' + MsStr(Over[10]) + '）');
  WriteLn('  [観測] DelayPrecise の遅れ: 最小 ', MsStr(Over[0]), '、中央値 ', MsStr(Over[10]),
    '、最大 ', MsStr(Over[19]));
  WriteLn;
end;

procedure TestCpu;
var
  C0, Used: UInt64;
begin
  WriteLn('3. 待っている間の CPU');
  C0 := CpuNS;
  PMLDelay(100);
  Used := CpuNS - C0;
  Check(Used < 20 * MS, 'Delay(100) の CPU 時間は 20 ms 未満（' + MsStr(Used) + '）');

  C0 := CpuNS;
  PMLDelayPrecise(100 * MS);
  Used := CpuNS - C0;
  Check(Used < 50 * MS,
    'DelayPrecise(100 ms) の CPU 時間は 50 ms 未満（空回りは端数だけ。' + MsStr(Used) + '）');
  WriteLn;
end;

{ ---- シグナルで眠りを割り込む ---- }

type
  TITimerVal = record
    it_interval: TTimeVal;
    it_value   : TTimeVal;
  end;
  PITimerVal = ^TITimerVal;

const
  ITIMER_REAL = 0;

// 構造体は番地で渡す。`const ANew: TITimerVal` と書くと FPC は cdecl で値渡しにし、
// C の側には NULL が届いてタイマーが動かなかった（strace で確かめた）。
function setitimer(AWhich: LongInt; ANew: PITimerVal; AOld: Pointer): LongInt; cdecl;
  external 'c' name 'setitimer';

var
  Alarms: Integer = 0;

procedure OnAlarm(ASig: cint); cdecl;
begin
  Inc(Alarms);
end;

procedure TestInterrupted;
var
  Act, OldAct: SigActionRec;
  T: TITimerVal;
  T0, Took: UInt64;
begin
  WriteLn('4. シグナルで割り込まれる眠り（EINTR）');
  FillChar(Act, SizeOf(Act), 0);
  Act.sa_handler := SigActionHandler(@OnAlarm);
  // SA_RESTART を付けない。付けても nanosleep は再開されないが、意図を明確にする。
  Act.sa_flags := 0;
  fpSigEmptySet(Act.sa_mask);
  if fpSigAction(SIGALRM, @Act, @OldAct) <> 0 then
  begin
    Check(False, 'SIGALRM の受け手を付けられる');
    Exit;
  end;
  FillChar(T, SizeOf(T), 0);
  T.it_interval.tv_usec := 1000;   // 1 ms ごと
  T.it_value.tv_usec := 1000;
  setitimer(ITIMER_REAL, @T, nil);
  try
    T0 := PMLNowNS;
    PMLDelay(30);
    Took := PMLNowNS - T0;
  finally
    FillChar(T, SizeOf(T), 0);
    setitimer(ITIMER_REAL, @T, nil);
    fpSigAction(SIGALRM, @OldAct, nil);
  end;
  Check(Alarms >= 5, Format('眠っている間にシグナルが届いた（%d 回）', [Alarms]));
  Check(Took >= 30 * MS, '割り込まれても 30 ms 眠り切る（' + MsStr(Took) + '）');
  WriteLn;
end;

procedure TestTimerService;
var
  T0, Took: UInt64;
begin
  WriteLn('5. TPMLTimerService（Context 無し）');
  T0 := TPMLTimerService.TicksNS;
  TPMLTimerService.DelayNS(2 * MS);
  Took := TPMLTimerService.TicksNS - T0;
  Check(Took >= 2 * MS, 'TPMLTimerService.DelayNS(2 ms)（' + MsStr(Took) + '）');
  T0 := TPMLTimerService.TicksNS;
  TPMLTimerService.Delay(3);
  Took := TPMLTimerService.TicksNS - T0;
  Check(Took >= 3 * MS, 'TPMLTimerService.Delay(3)（' + MsStr(Took) + '）');
  T0 := TPMLTimerService.TicksNS;
  TPMLTimerService.DelayPrecise(2 * MS);
  Took := TPMLTimerService.TicksNS - T0;
  Check(Took >= 2 * MS, 'TPMLTimerService.DelayPrecise(2 ms)（' + MsStr(Took) + '）');
  WriteLn;
end;

begin
  WriteLn('test_time — 待つ API');
  WriteLn;
  TestPreciseSteps;
  TestRealDelays;
  TestCpu;
  TestInterrupted;
  TestTimerService;
  if Failures = 0 then
    WriteLn('=== 結論: 待つ API が SDL と同じ手順で、早く戻らず、CPU を使わずに待つ ===')
  else
  begin
    WriteLn(Format('=== 結論: %d 件失敗 ===', [Failures]));
    Halt(1);
  end;
end.
