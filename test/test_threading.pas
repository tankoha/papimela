{
  test_threading — スレッドと同期の部品を、実際にスレッドを走らせて検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    再帰ミューテックスの排他と TryLock、読み書きロックの共有と排他、セマフォと条件変数の
    起こし方と時間切れ（時計で測る）、ロックガードがスコープ・例外・コピーで釣り合うこと、
    スレッドの名前・戻り値・シグナルのマスク、優先度（下げる、RealtimeKit で上げる）。

  WHY:
    同期の誤りは 1 回走らせただけでは出ないことが多い。取り合いは回数を増やし、
    時間切れは実際の経過時間を測る。「待たないはずが待つ」「釣り合わずに残る」は、
    別のスレッドから TryLock して確かめる。

  実行前提: cthreads（uses の先頭）。優先度を上げる検査は RealtimeKit（rtkit-daemon）が
            要る。無い環境（CI）では PAPIMELA_RTKIT_OPTIONAL=1 のときだけ飛ばす。
}
program test_threading;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils, Classes, BaseUnix,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Core,
  PaPiMeLa.Threading;

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

function NowMs: Int64;
begin
  Result := Int64(TPMLTimerService.TicksNS div 1000000);
end;

{ ---- 見張り ----
  同期の誤りは「失敗する」より「止まる」ことが多い。止まったら検査の失敗として
  プロセスごと終わらせる（CI で 60 分待たないように）。 }

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
    // FpExit は Pascal の出力の溜まりを書き出さない（実測: 上の行が消えた）。先に書き出す。
    Flush(Output);
    FpExit(3);
  end;
  Result := 0;
end;

{ ---- 別のスレッドから TryLock して、取れるかを見る ---- }

type
  TProbeKind = (Mutex, Read, Write);

  TProbe = class(TPMLThread)
  public
    Kind : TProbeKind;
    M    : TPMLMutex;
    L    : TPMLRWLock;
    Got  : Boolean;
  protected
    function Run: Integer; override;
  end;

function TProbe.Run: Integer;
begin
  case Kind of
    TProbeKind.Mutex:
      begin
        Got := M.TryLock;
        if Got then
          M.Unlock;
      end;
    TProbeKind.Read:
      begin
        Got := L.TryLockForReading;
        if Got then
          L.Unlock;
      end;
    TProbeKind.Write:
      begin
        Got := L.TryLockForWriting;
        if Got then
          L.Unlock;
      end;
  end;
  Result := 0;
end;

function OtherCanLock(M: TPMLMutex): Boolean;
var
  P: TProbe;
begin
  P := TProbe.Create('probe', True);
  P.Kind := TProbeKind.Mutex;
  P.M := M;
  P.Start;
  P.WaitFor;
  Result := P.Got;
  P.Free;
end;

function OtherCanLockRW(L: TPMLRWLock; AWrite: Boolean): Boolean;
var
  P: TProbe;
begin
  P := TProbe.Create('probe', True);
  if AWrite then
    P.Kind := TProbeKind.Write
  else
    P.Kind := TProbeKind.Read;
  P.L := L;
  P.Start;
  P.WaitFor;
  Result := P.Got;
  P.Free;
end;

{ ---- 取り合い ---- }

type
  TCounter = class(TPMLThread)
  public
    M: TPMLMutex;
    Shared: PInteger;
    Loops: Integer;
  protected
    function Run: Integer; override;
  end;

function TCounter.Run: Integer;
var
  I, V: Integer;
begin
  for I := 1 to Loops do
  begin
    M.Lock;
    // 読んで、少し間を置いて、書く。排他が効いていなければ数が減る。
    V := Shared^;
    if I mod 64 = 0 then
      ThreadSwitch;
    Shared^ := V + 1;
    M.Unlock;
  end;
  Result := Loops;
end;

procedure TestMutex;
var
  M: TPMLMutex;
  T: array[0..3] of TCounter;
  Shared, I, Sum: Integer;
begin
  WriteLn('1. ミューテックス');
  M := TPMLMutex.Create;
  try
    M.Lock;
    M.Lock;
    Check(not OtherCanLock(M), '2 回 Lock すると他のスレッドは取れない');
    M.Unlock;
    Check(not OtherCanLock(M), '1 回 Unlock してもまだ取れない（再帰）');
    M.Unlock;
    Check(OtherCanLock(M), '2 回目の Unlock で取れる');
    Check(M.TryLock, '空いていれば TryLock は True');
    M.Unlock;

    Shared := 0;
    for I := 0 to High(T) do
    begin
      T[I] := TCounter.Create('counter', True);
      T[I].M := M;
      T[I].Shared := @Shared;
      T[I].Loops := 50000;
    end;
    for I := 0 to High(T) do
      T[I].Start;
    Sum := 0;
    for I := 0 to High(T) do
    begin
      Inc(Sum, T[I].WaitFor);
      T[I].Free;
    end;
    Check((Shared = 200000) and (Sum = 200000),
      Format('4 スレッドで 5 万回ずつ数えて 20 万（%d）', [Shared]));
  finally
    M.Free;
  end;
  WriteLn;
end;

procedure TestRWLock;
var
  L: TPMLRWLock;
begin
  WriteLn('2. 読み書きロック');
  L := TPMLRWLock.Create;
  try
    L.LockForReading;
    Check(OtherCanLockRW(L, False), '読んでいる間も他のスレッドは読める');
    Check(not OtherCanLockRW(L, True), '読んでいる間は書けない');
    L.Unlock;
    L.LockForWriting;
    Check(not OtherCanLockRW(L, False), '書いている間は読めない');
    Check(not OtherCanLockRW(L, True), '書いている間は書けない');
    L.Unlock;
    Check(OtherCanLockRW(L, True), '外せば書ける');
    Check(L.TryLockForWriting, 'TryLockForWriting');
    Check(not L.TryLockForReading, '書いている間は自分も TryLockForReading できない');
    L.Unlock;
  finally
    L.Free;
  end;
  WriteLn;
end;

{ ---- セマフォ ---- }

type
  TSignaller = class(TPMLThread)
  public
    S: TPMLSemaphore;
    C: TPMLCondition;
    M: TPMLMutex;
    Flag: PInteger;
    DelayMs: Integer;
  protected
    function Run: Integer; override;
  end;

function TSignaller.Run: Integer;
begin
  Sleep(DelayMs);
  if Assigned(S) then
    S.Signal;
  if Assigned(C) then
  begin
    M.Lock;
    Flag^ := 1;
    C.Signal;
    M.Unlock;
  end;
  Result := 0;
end;

procedure TestSemaphore;
var
  S: TPMLSemaphore;
  T0, Dt: Int64;
  Sig: TSignaller;
  Ok: Boolean;
begin
  WriteLn('3. セマフォ');
  S := TPMLSemaphore.Create(2);
  try
    Check(S.Value = 2, '初期値 2');
    Check(S.TryWait and S.TryWait, '2 回減らせる');
    Check(not S.TryWait and (S.Value = 0), '3 回目は減らせない');
    T0 := NowMs;
    Ok := S.WaitTimeout(100);
    Dt := NowMs - T0;
    Check(not Ok and (Dt >= 100) and (Dt < 1000), Format('WaitTimeout(100) は時間切れ（%d ms）', [Dt]));
    Check(not S.WaitTimeoutNS(0), 'WaitTimeoutNS(0) は TryWait');

    Sig := TSignaller.Create('signaller', True);
    Sig.S := S;
    Sig.DelayMs := 50;
    T0 := NowMs;
    Sig.Start;
    S.Wait;
    Dt := NowMs - T0;
    Sig.WaitFor;
    Sig.Free;
    Check((Dt >= 40) and (Dt < 1000), Format('別のスレッドの Signal で Wait が起きる（%d ms）', [Dt]));
    S.Signal;
    Check(S.WaitTimeout(10) and (S.Value = 0), '数があれば時間切れ付きの Wait もすぐ減らす');
  finally
    S.Free;
  end;
  WriteLn;
end;

{ ---- 条件変数 ---- }

type
  TWaiter = class(TPMLThread)
  public
    C: TPMLCondition;
    M: TPMLMutex;
    Go: PInteger;
    Woke: PInteger;
  protected
    function Run: Integer; override;
  end;

function TWaiter.Run: Integer;
begin
  M.Lock;
  while Go^ = 0 do
    C.Wait(M);
  Inc(Woke^);
  M.Unlock;
  Result := 0;
end;

procedure TestCondition;
var
  C: TPMLCondition;
  M: TPMLMutex;
  Flag, Go, Woke, I: Integer;
  T0, Dt: Int64;
  Ok: Boolean;
  Sig: TSignaller;
  W: array[0..3] of TWaiter;
begin
  WriteLn('4. 条件変数');
  C := TPMLCondition.Create;
  M := TPMLMutex.Create;
  try
    M.Lock;
    T0 := NowMs;
    Ok := C.WaitTimeout(M, 100);
    Dt := NowMs - T0;
    Check(not Ok and (Dt >= 100) and (Dt < 1000), Format('WaitTimeout(100) は時間切れ（%d ms）', [Dt]));
    Check(not OtherCanLock(M), '時間切れで戻ったときミューテックスは取り直してある');
    M.Unlock;

    Flag := 0;
    Sig := TSignaller.Create('signaller', True);
    Sig.C := C;
    Sig.M := M;
    Sig.Flag := @Flag;
    Sig.DelayMs := 50;
    M.Lock;
    Sig.Start;
    Ok := True;
    while (Flag = 0) and Ok do
      Ok := C.WaitTimeout(M, 2000);
    M.Unlock;
    Sig.WaitFor;
    Sig.Free;
    Check(Ok and (Flag = 1), 'Signal で起きて条件が成り立っている');

    Go := 0;
    Woke := 0;
    for I := 0 to High(W) do
    begin
      W[I] := TWaiter.Create('waiter', True);
      W[I].C := C;
      W[I].M := M;
      W[I].Go := @Go;
      W[I].Woke := @Woke;
      W[I].Start;
    end;
    Sleep(100);
    M.Lock;
    Go := 1;
    C.Broadcast;
    M.Unlock;
    for I := 0 to High(W) do
    begin
      W[I].WaitFor;
      W[I].Free;
    end;
    Check(Woke = 4, Format('Broadcast で待っていた 4 つが全部起きる（%d）', [Woke]));
  finally
    M.Free;
    C.Free;
  end;
  WriteLn;
end;

{ ---- ロックガード ---- }

procedure GuardedScope(M: TPMLMutex; out AHeldInside: Boolean);
var
  G: TPMLLockGuard;
begin
  G := TPMLLockGuard.Lock(M);
  AHeldInside := not OtherCanLock(M);
end;

procedure GuardedRaise(M: TPMLMutex);
var
  G: TPMLLockGuard;
begin
  G := TPMLLockGuard.Lock(M);
  raise EPMLArgument.Create('inside guard');
end;

procedure GuardedCopy(M: TPMLMutex; out AHeldAfterRelease: Boolean);
var
  G, H: TPMLLockGuard;
begin
  G := TPMLLockGuard.Lock(M);
  H := G;
  G.Release;
  AHeldAfterRelease := not OtherCanLock(M);
end;

procedure TestGuard;
var
  M: TPMLMutex;
  Held: Boolean;
  Raised: Boolean;
  G: TPMLLockGuard;
begin
  WriteLn('5. ロックガード');
  M := TPMLMutex.Create;
  try
    GuardedScope(M, Held);
    Check(Held, 'スコープの中では取れている');
    Check(OtherCanLock(M), 'スコープを出たら外れている');

    Raised := False;
    try
      GuardedRaise(M);
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    Check(Raised and OtherCanLock(M), '例外で抜けても外れている');

    GuardedCopy(M, Held);
    Check(Held, 'コピーした片方を Release しても、もう片方が持っている');
    Check(OtherCanLock(M), '両方の寿命が終われば外れている（釣り合う）');

    G := TPMLLockGuard.Lock(M);
    G.Release;
    Check(OtherCanLock(M), 'Release で早めに外せる');
    G.Release;
    Check(OtherCanLock(M), '2 度 Release しても外し過ぎない');
  finally
    M.Free;
  end;
  WriteLn;
end;

{ ---- スレッド ---- }

type
  TNamed = class(TPMLThread)
  public
    SeenName: String;
    SigintBlocked, SigpipeBlocked, SigsegvBlocked: Boolean;
  protected
    function Run: Integer; override;
  end;

function TNamed.Run: Integer;
var
  Cur: TSigSet;
begin
  SeenName := TPMLThread.CurrentName;
  fpsigemptyset(Cur);
  fpsigprocmask(SIG_BLOCK, nil, @Cur);
  SigintBlocked := fpsigismember(Cur, SIGINT) = 1;
  SigpipeBlocked := fpsigismember(Cur, SIGPIPE) = 1;
  SigsegvBlocked := fpsigismember(Cur, SIGSEGV) = 1;
  Result := 42;
end;

function AddOne(AData: Pointer): Integer;
begin
  Result := PInteger(AData)^ + 1;
end;

type
  TPriority = class(TPMLThread)
  public
    Want: TPMLThreadPriority;
    Ok: Boolean;
    Nice: Integer;
  protected
    function Run: Integer; override;
  end;

function TPriority.Run: Integer;
begin
  Ok := TPMLThread.SetCurrentPriority(Want);
  Nice := TPMLThread.CurrentNiceValue;
  Result := 0;
end;

function RunPriority(APriority: TPMLThreadPriority; out ANice: Integer): Boolean;
var
  T: TPriority;
begin
  T := TPriority.Create('prio', True);
  T.Want := APriority;
  T.Start;
  T.WaitFor;
  Result := T.Ok;
  ANice := T.Nice;
  T.Free;
end;

procedure TestThread;
var
  T: TNamed;
  F: TPMLThread;
  V, Nice, MainNice: Integer;
  Ok: Boolean;
begin
  WriteLn('6. スレッド');
  Check(TPMLThread.Available, 'cthreads があればスレッドを作れる');
  T := TNamed.Create('papimela-worker-long-name', True);
  T.Start;
  Check(T.WaitFor = 42, 'WaitFor は Run の戻り値');
  Check(T.SeenName = 'papimela-worker', 'OS 上の名前は 15 バイトで切られる: "' + T.SeenName + '"');
  Check(T.SigintBlocked and T.SigpipeBlocked, '子スレッドでは SIGINT / SIGPIPE を止める');
  Check(not T.SigsegvBlocked, '同期のシグナル（SIGSEGV）は止めない');
  T.Free;

  V := 41;
  F := TPMLThread.CreateFunc('func', @AddOne, @V);
  Check(F.WaitFor = 42, 'CreateFunc の関数の戻り値');
  F.Free;

  WriteLn;
  WriteLn('7. 優先度（子スレッドだけを変える）');
  MainNice := TPMLThread.CurrentNiceValue;
  Ok := RunPriority(TPMLThreadPriority.Low, Nice);
  Check(Ok and (Nice = 19), Format('Low は nice 19（%d）', [Nice]));
  Check(TPMLThread.CurrentNiceValue = MainNice, '主スレッドの nice は変わらない（スレッドごと）');
  Ok := RunPriority(TPMLThreadPriority.High, Nice);
  if Ok then
    Check((Nice < 0) and (Nice >= -10), Format('High で nice が負になる（%d。権限が無ければ RealtimeKit の下限まで）', [Nice]))
  else if GetEnvironmentVariable('PAPIMELA_RTKIT_OPTIONAL') = '1' then
    WriteLn('  [SKIP] High に上げられなかった（RealtimeKit が無い環境。PAPIMELA_RTKIT_OPTIONAL=1）')
  else
    Check(False, 'High に上げられる（権限か RealtimeKit が要る。無い環境では PAPIMELA_RTKIT_OPTIONAL=1）');
  WriteLn;
end;

{ ---- RunOnMainThread ---- }

type
  TMainProbe = class
  public
    RanOn  : TThreadID;
    Runs   : Integer;
    procedure Mark;
    procedure Boom;
  end;

  TCaller = class(TPMLThread)
  public
    Ctx   : TPMLContext;
    Probe : TMainProbe;
    Wait  : Boolean;
    Fail  : Boolean;
    Got   : Boolean;
    Pushed: Boolean;
    Kind  : TPMLEventKind;
  protected
    function Run: Integer; override;
  end;

procedure TMainProbe.Mark;
begin
  RanOn := GetCurrentThreadID;
  Inc(Runs);
end;

procedure TMainProbe.Boom;
begin
  Inc(Runs);
  raise EPMLArgument.Create('boom');
end;

function TCaller.Run: Integer;
begin
  if Pushed then
  begin
    Ctx.Events.PushSimple(Kind, 0);
    Exit(0);
  end;
  if Fail then
    Got := Ctx.RunOnMainThread(@Probe.Boom, Wait)
  else
    Got := Ctx.RunOnMainThread(@Probe.Mark, Wait);
  Result := 0;
end;

function NewCaller(ACtx: TPMLContext; AProbe: TMainProbe; AWait: Boolean): TCaller;
begin
  Result := TCaller.Create('caller', True);
  Result.Ctx := ACtx;
  Result.Probe := AProbe;
  Result.Wait := AWait;
end;

{ AThread が終わるまで、メインスレッドでイベントを回す。 }
procedure PumpUntilDone(ACtx: TPMLContext; AThread: TThread);
var
  Ev: TPMLEvent;
  Deadline: Int64;
begin
  Deadline := NowMs + 3000;
  while not AThread.Finished and (NowMs < Deadline) do
    ACtx.Events.WaitTimeout(Ev, 20);
end;

procedure TestRunOnMainThread;
var
  Ctx: TPMLContext;
  P: TMainProbe;
  C, C2: TCaller;
  Raised: Boolean;
  Ev: TPMLEvent;
  Kind: TPMLEventKind;
  Got: Boolean;
begin
  WriteLn('8. RunOnMainThread');
  P := TMainProbe.Create;
  Ctx := TPMLContext.Create([]);
  try
    Check(Ctx.RunOnMainThread(@P.Mark, True) and (P.Runs = 1) and (P.RanOn = GetCurrentThreadID),
      'メインスレッドから呼べばその場で動く');

    P.Runs := 0;
    C := NewCaller(Ctx, P, True);
    C.Start;
    Sleep(100);
    Check((P.Runs = 0) and not C.Finished, 'Pump するまでは動かず、呼んだ側は待っている');
    PumpUntilDone(Ctx, C);
    C.WaitFor;
    Check(C.Got and (P.Runs = 1) and (P.RanOn = GetCurrentThreadID),
      'Wait の中の Pump でメインスレッドで動き、呼んだ側に True が返る');
    C.Free;

    P.Runs := 0;
    C := NewCaller(Ctx, P, False);
    C.Start;
    C.WaitFor;
    Check(C.Got and (P.Runs = 0), '待たない呼び出しはすぐ戻り、まだ動いていない');
    Ctx.Events.Pump(0);
    Check(P.Runs = 1, '次の Pump で動く');
    C.Free;

    P.Runs := 0;
    C := NewCaller(Ctx, P, True);
    C.Fail := True;
    C2 := NewCaller(Ctx, P, True);
    C.Start;
    Sleep(100);
    C2.Start;
    Sleep(100);
    Raised := False;
    try
      Ctx.Events.Pump(0);
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    C.WaitFor;
    Check(Raised and not C.Got, '手続きの例外は Pump から出て、待つ側には False');
    Check(not C2.Finished and (P.Runs = 1), '後ろに積まれていた呼び出しは捨てられず、まだ待っている');
    PumpUntilDone(Ctx, C2);
    C2.WaitFor;
    Check(C2.Got and (P.Runs = 2), '次の Pump で後ろの呼び出しが動く');
    C.Free;
    C2.Free;

    Kind := Ctx.Events.RegisterUserEvents(1);
    C := NewCaller(Ctx, P, False);
    C.Pushed := True;
    C.Kind := Kind;
    C.Start;
    Got := Ctx.Events.WaitTimeout(Ev, 2000) and (Ev.Kind = Kind);
    C.WaitFor;
    C.Free;
    Check(Got, '他のスレッドが積んだイベントを Wait で受け取る');

    P.Runs := 0;
    C := NewCaller(Ctx, P, True);
    C.Start;
    Sleep(100);
  finally
    Ctx.Free;
  end;
  C.WaitFor;
  Check(not C.Got and (P.Runs = 0), 'Context が先に壊れたら動かさず、待つ側には False');
  C.Free;
  P.Free;
  WriteLn;
end;

var
  Dog: TWatchdog;
begin
  WriteLn('test_threading — スレッドと同期の部品');
  WriteLn;
  Dog := TWatchdog.Create('watchdog', True);
  Dog.LimitMs := 60000;
  Dog.Start;
  TestMutex;
  TestRWLock;
  TestSemaphore;
  TestCondition;
  TestGuard;
  TestThread;
  TestRunOnMainThread;
  Dog.Terminate;
  Dog.WaitFor;
  Dog.Free;
  if Failures = 0 then
    WriteLn('=== 結論: スレッドと同期の部品が SDL の約束どおりに動く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
