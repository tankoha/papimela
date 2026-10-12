{
  test_thread_realtime — 実時間スケジューリング（PAPIMELA_THREAD_PRIORITY_POLICY）を実機で確かめる

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    RealtimeKit（xdg-desktop-portal の Realtime か、システムの RealtimeKit1）に実時間を頼み、
    スレッドの方針と優先度を sched_getscheduler / sched_getparam で読む。
    1. "rr" で High を 3 つのスレッドで順に頼み、どれも上限の 3/4（SDL は最初の 1 本だけ
       上限になる: D-58）
    2. "rr" で Low は 1、TimeCritical は上限
    3. "fifo" で Normal は上限の半分。方針は RR（RealtimeKit は RR しか渡さない。SDL も同じ: D-59）
    4. FORCE_REALTIME_TIME_CRITICAL=1 なら、方針のヒントが無くても TimeCritical は RR、
       High は Other のまま
    5. RLIMIT_RTTIME が RealtimeKit の RTTimeUSecMax 以下に置かれている

  WHY:
    §3 の 1 の B1 の受け入れ検査。RealtimeKit が要るので手元専用（CI では走らない）。
    RealtimeKit に届かなければ失敗にする（飛ばしてよいときは PAPIMELA_RTKIT_OPTIONAL=1）。

  実行前提: cthreads（uses の先頭）、RealtimeKit（rtkit-daemon）。
}
program test_thread_realtime;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils, BaseUnix, UnixType,
  PaPiMeLa;

const
  RLIMIT_RTTIME = 15;

type
  TRLimit = record
    rlim_cur, rlim_max: QWord;
  end;

function getrlimit(AResource: cint; ALimit: Pointer): cint; cdecl; external 'c';

var
  Failures: Integer = 0;
  Ctx: TPMLContext;

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
  TPrioWorker = class(TPMLThread)
  public
    Want: TPMLThreadPriority;
    Ok: Boolean;
    Policy: TPMLSchedPolicy;
    Prio: Integer;
  protected
    function Run: Integer; override;
  end;

function TPrioWorker.Run: Integer;
begin
  Ok := Ctx.SetCurrentThreadPriority(Want);
  Policy := TPMLThread.CurrentSchedPolicy;
  Prio := TPMLThread.CurrentRealtimePriority;
  Result := 0;
end;

function RunOne(AWant: TPMLThreadPriority; out APolicy: TPMLSchedPolicy; out APrio: Integer): Boolean;
var
  W: TPrioWorker;
begin
  W := TPrioWorker.Create('rtprio', True);
  try
    W.Want := AWant;
    W.Start;
    W.WaitFor;
    Result := W.Ok;
    APolicy := W.Policy;
    APrio := W.Prio;
  finally
    W.Free;
  end;
end;

function MakeContext(const APolicy, AForce: String): TPMLContext;
var
  Opts: TPMLContextOptions;
begin
  Opts := TPMLContextOptions.Default;
  Opts.PreferredVideo := 'dummy';
  if APolicy <> '' then
    Opts.Hints.Add(PML_HINT_THREAD_PRIORITY_POLICY, APolicy);
  if AForce <> '' then
    Opts.Hints.Add(PML_HINT_THREAD_FORCE_REALTIME_TIME_CRITICAL, AForce);
  Result := TPMLContext.Create([], Opts);
end;

var
  MaxRT, I, P: Integer;
  Pol: TPMLSchedPolicy;
  Ok: Boolean;
  Lim: TRLimit;
begin
  WriteLn('test_thread_realtime — 実時間スケジューリング');
  WriteLn;
  MaxRT := PMLRealtimeKitMaxPriority;
  WriteLn('  [INFO] RealtimeKit の MaxRealtimePriority = ', MaxRT);
  if MaxRT <= 0 then
  begin
    if GetEnvironmentVariable('PAPIMELA_RTKIT_OPTIONAL') = '1' then
    begin
      WriteLn('=== RealtimeKit に届かないので飛ばした（PAPIMELA_RTKIT_OPTIONAL=1） ===');
      Exit;
    end;
    Check(False, 'RealtimeKit に届く');
  end
  else
  begin
    WriteLn('1. "rr" で High を 3 回');
    Ctx := MakeContext('rr', '');
    try
      for I := 1 to 3 do
      begin
        Ok := RunOne(TPMLThreadPriority.High, Pol, P);
        Check(Ok and (Pol = TPMLSchedPolicy.RR) and (P = PMLRealtimePriority(TPMLThreadPriority.High, MaxRT)),
          Format('%d 本目: RR・優先度 %d（上限 %d の 3/4。SDL は 1 本目だけ上限: D-58）', [I, P, MaxRT]));
      end;
      WriteLn;
      WriteLn('2. "rr" で Low と TimeCritical');
      Ok := RunOne(TPMLThreadPriority.Low, Pol, P);
      Check(Ok and (Pol = TPMLSchedPolicy.RR) and (P = 1), Format('Low は RR・1（%d）', [P]));
      Ok := RunOne(TPMLThreadPriority.TimeCritical, Pol, P);
      Check(Ok and (Pol = TPMLSchedPolicy.RR) and (P = MaxRT), Format('TimeCritical は RR・上限（%d）', [P]));
    finally
      Ctx.Free;
    end;

    WriteLn;
    WriteLn('3. "fifo" で Normal');
    Ctx := MakeContext('fifo', '');
    try
      Ok := RunOne(TPMLThreadPriority.Normal, Pol, P);
      // RealtimeKit は RR しか渡さない。SDL も "fifo" で RR になる（D-59。SDL の実物で確かめた）
      Check(Ok and (Pol = TPMLSchedPolicy.RR) and (P = MaxRT div 2),
        Format('Normal は上限の半分（%d）。方針は RealtimeKit が決める RR（SDL も同じ: D-59）', [P]));
    finally
      Ctx.Free;
    end;

    WriteLn;
    WriteLn('4. FORCE_REALTIME_TIME_CRITICAL=1');
    Ctx := MakeContext('', '1');
    try
      Ok := RunOne(TPMLThreadPriority.TimeCritical, Pol, P);
      Check(Ok and (Pol = TPMLSchedPolicy.RR) and (P = MaxRT), Format('TimeCritical は RR・上限（%d）', [P]));
      RunOne(TPMLThreadPriority.High, Pol, P);
      Check((Pol = TPMLSchedPolicy.Other) and (P = 0), 'High は Other のまま');
    finally
      Ctx.Free;
    end;

    WriteLn;
    WriteLn('5. RLIMIT_RTTIME');
    FillChar(Lim, SizeOf(Lim), 0);
    // 先に読む（Format の引数は Check より前に評価される）
    Ok := getrlimit(RLIMIT_RTTIME, @Lim) = 0;
    Check(Ok and (Lim.rlim_max > 0) and (Lim.rlim_max <= 200000)
      and (Lim.rlim_cur <= Lim.rlim_max),
      Format('実時間を頼む前に RLIMIT_RTTIME を置く（cur %d、max %d）', [Lim.rlim_cur, Lim.rlim_max]));
  end;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: 実時間スケジューリングが SDL の約束どおりに（D-58 を直して）効く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
