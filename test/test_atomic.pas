{
  test_atomic — 不可分操作・スピンロック・一度だけの初期化を検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    TPMLAtomicInt / TPMLAtomicU32 / TPMLAtomicPointer の戻り値の約束（SDL と同じ:
    Exchange と Add は前の値、DecRef は 0 になったら True、U32 は回る）、
    複数のスレッドでの取り合い（4 スレッド × 10 万回で数が合う、ポインタの CAS で
    積んだものが失われない、DecRef の True がちょうど 1 回）、スピンロックの排他と待ち、
    TPMLInitState（同時に呼んでも初期化するのは 1 スレッドだけで、他は済むまで待つ。
    失敗すれば次の呼び出しがやり直す）。

  WHY:
    不可分でない実装も 1 スレッドでは正しく見える。取り合いの回数を十分に増やして、
    失われた更新を数で捕まえる。

  実行前提: cthreads（uses の先頭）。止まったら見張りが 60 秒で失敗として終わらせる。
}
program test_atomic;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils, Classes, BaseUnix,
  PaPiMeLa.Atomic,
  PaPiMeLa.Threading,
  PaPiMeLa.Core;

const
  THREADS = 4;
  LOOPS   = 100000;

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

{ ---- 取り合いに使う共有の値（大域変数なので 0 で始まる） ---- }

type
  PNode = ^TNode;
  TNode = record
    Next: PNode;
  end;

var
  GInt      : TPMLAtomicInt;
  GU32      : TPMLAtomicU32;
  GPtr      : TPMLAtomicPointer;
  GSpin     : TPMLSpinLock;
  GPlain    : Integer;
  GRef      : TPMLAtomicInt;
  GZeroHits : TPMLAtomicInt;
  GStart    : TPMLAtomicInt;   // 全員がそろってから一斉に始める
  GInit     : TPMLInitState;
  GInitCount: TPMLAtomicInt;
  GInitData : Integer;
  GSawData  : TPMLAtomicInt;
  GQuitCount: TPMLAtomicInt;

type
  TWorkKind = (AddInt, CasU32, Spin, PushPtr, DecRef, InitOnce, QuitOnce);

  TWorker = class(TPMLThread)
  public
    Kind: TWorkKind;
    Nodes: array of TNode;
  protected
    function Run: Integer; override;
  end;

function TWorker.Run: Integer;
var
  I: Integer;
  Old: LongWord;
  Head: Pointer;
begin
  GStart.IncRef;
  while GStart.Load < THREADS do
    PMLCPUPause;
  case Kind of
    TWorkKind.AddInt:
      for I := 1 to LOOPS do
        GInt.Add(1);
    TWorkKind.CasU32:
      for I := 1 to LOOPS do
        repeat
          Old := GU32.Load;
        until GU32.CompareAndSwap(Old, Old + 1);
    TWorkKind.Spin:
      for I := 1 to LOOPS do
      begin
        GSpin.Lock;
        GPlain := GPlain + 1;   // 不可分でない更新。スピンロックだけが守る
        GSpin.Unlock;
      end;
    TWorkKind.PushPtr:
      begin
        SetLength(Nodes, LOOPS div 10);
        for I := 0 to High(Nodes) do
          repeat
            Head := GPtr.Load;
            Nodes[I].Next := Head;
          until GPtr.CompareAndSwap(Head, @Nodes[I]);
      end;
    TWorkKind.DecRef:
      for I := 1 to LOOPS do
        if GRef.DecRef then
          GZeroHits.IncRef;
    TWorkKind.InitOnce:
      if GInit.ShouldInit then
      begin
        GInitCount.IncRef;
        Sleep(50);              // 他のスレッドはこの間、待っていなければならない
        GInitData := 42;
        GInit.SetInitialized(True);
      end
      else if GInitData = 42 then
        GSawData.IncRef;        // 戻ったときには初期化が済んでいる
    TWorkKind.QuitOnce:
      if GInit.ShouldQuit then
      begin
        GQuitCount.IncRef;
        Sleep(20);
        GInit.SetInitialized(False);
      end;
  end;
  Result := 0;
end;

{ 同じ仕事を THREADS 本のスレッドで一斉に走らせる。走らせたスレッドは返す（Nodes を読むため）。 }
procedure RunAll(AKind: TWorkKind; out AWorkers: array of TWorker);
var
  I: Integer;
begin
  GStart.Exchange(0);
  for I := 0 to THREADS - 1 do
  begin
    AWorkers[I] := TWorker.Create('worker', True);
    AWorkers[I].Kind := AKind;
  end;
  for I := 0 to THREADS - 1 do
    AWorkers[I].Start;
  for I := 0 to THREADS - 1 do
    AWorkers[I].WaitFor;
end;

procedure FreeAll(var AWorkers: array of TWorker);
var
  I: Integer;
begin
  for I := 0 to High(AWorkers) do
    FreeAndNil(AWorkers[I]);
end;

procedure TestSingleThread;
var
  A: TPMLAtomicInt;
  U: TPMLAtomicU32;
  P: TPMLAtomicPointer;
  S: TPMLSpinLock;
  X, Y: Integer;
begin
  WriteLn('1. 1 スレッドでの戻り値の約束');
  A := Default(TPMLAtomicInt);
  Check(A.Load = 0, '0 で始まる');
  Check(A.Exchange(5) = 0, 'Exchange は前の値（0）を返す');
  Check(A.Load = 5, 'Exchange で 5 になる');
  Check(A.Add(3) = 5, 'Add は前の値（5）を返す');
  Check(A.Load = 8, 'Add で 8 になる');
  Check(A.Add(-10) = 8, '負の Add も前の値を返す');
  Check(A.Load = -2, '負にもなる（-2）');
  Check(not A.CompareAndSwap(0, 9) and (A.Load = -2), '今の値と違う CompareAndSwap は何もしない');
  Check(A.CompareAndSwap(-2, 1) and (A.Load = 1), '今の値と同じなら置き換えて True');
  Check(A.IncRef = 1, 'IncRef は前の値（1）を返す');
  Check(not A.DecRef, '2 → 1 の DecRef は False');
  Check(A.DecRef and (A.Load = 0), '1 → 0 の DecRef は True');
  Check(not A.DecRef and (A.Load = -1), '0 → -1 の DecRef は False（0 になったときだけ True）');

  U := Default(TPMLAtomicU32);
  Check(U.Exchange($FFFFFFFF) = 0, 'U32 の Exchange');
  Check((U.Add(1) = $FFFFFFFF) and (U.Load = 0), 'U32 は 2^32 で回る（最大 + 1 = 0）');
  Check((U.Add(-1) = 0) and (U.Load = $FFFFFFFF), 'U32 に負の Add（0 - 1 = 最大）');
  Check(U.CompareAndSwap($FFFFFFFF, 7) and (U.Load = 7), 'U32 の CompareAndSwap');

  P := Default(TPMLAtomicPointer);
  Check(P.Load = nil, 'ポインタは nil で始まる');
  Check(P.Exchange(@X) = nil, 'ポインタの Exchange は前の値');
  Check(not P.CompareAndSwap(@Y, nil) and (P.Load = @X), '違うポインタとの CompareAndSwap は何もしない');
  Check(P.CompareAndSwap(@X, @Y) and (P.Load = @Y), '同じなら置き換える');

  S := Default(TPMLSpinLock);
  Check(S.TryLock, '外れていれば TryLock は True');
  Check(not S.TryLock, '取っている間は TryLock は False（再帰しない）');
  S.Unlock;
  Check(S.TryLock, 'Unlock の後はまた取れる');
  S.Unlock;
  PMLCPUPause;
  PMLMemoryBarrierRelease;
  PMLMemoryBarrierAcquire;
  Check(True, 'PMLCPUPause とメモリバリアを呼べる');
  WriteLn;
end;

procedure TestContention;
var
  W: array[0..THREADS - 1] of TWorker;
  I, N: Integer;
  Node: PNode;
begin
  WriteLn(Format('2. 取り合い（%d スレッド × %d 回）', [THREADS, LOOPS]));
  RunAll(TWorkKind.AddInt, W);
  FreeAll(W);
  Check(GInt.Load = THREADS * LOOPS, Format('Add で数が合う（%d）', [GInt.Load]));

  RunAll(TWorkKind.CasU32, W);
  FreeAll(W);
  Check(GU32.Load = THREADS * LOOPS, Format('CompareAndSwap の繰り返しで数が合う（%d）', [GU32.Load]));

  RunAll(TWorkKind.Spin, W);
  FreeAll(W);
  Check(GPlain = THREADS * LOOPS, Format('スピンロックが守る普通の変数の数が合う（%d）', [GPlain]));

  RunAll(TWorkKind.PushPtr, W);
  N := 0;
  Node := GPtr.Load;
  while (Node <> nil) and (N <= THREADS * LOOPS) do
  begin
    Inc(N);
    Node := Node^.Next;
  end;
  Check(N = THREADS * (LOOPS div 10), Format('ポインタの CompareAndSwap で積んだものが失われない（%d 個）', [N]));
  FreeAll(W);

  GRef.Exchange(THREADS * LOOPS);
  RunAll(TWorkKind.DecRef, W);
  FreeAll(W);
  Check((GRef.Load = 0) and (GZeroHits.Load = 1),
    Format('DecRef の True は全スレッドを通してちょうど 1 回（%d 回）', [GZeroHits.Load]));
  for I := 0 to High(W) do
    W[I] := nil;
  WriteLn;
end;

type
  THolder = class(TPMLThread)
  public
    HoldMs: Integer;
    Got: TPMLAtomicInt;
  protected
    function Run: Integer; override;
  end;

function THolder.Run: Integer;
begin
  GSpin.Lock;
  Got.Exchange(1);
  Sleep(HoldMs);
  GSpin.Unlock;
  Result := 0;
end;

procedure TestSpinWait;
var
  H: THolder;
  T0, Dt: Int64;
begin
  WriteLn('3. スピンロックの待ち');
  H := THolder.Create('holder', True);
  H.HoldMs := 100;
  H.Start;
  while H.Got.Load = 0 do
    PMLCPUPause;
  Check(not GSpin.TryLock, '他のスレッドが持っている間は TryLock は False');
  T0 := NowMs;
  GSpin.Lock;
  Dt := NowMs - T0;
  GSpin.Unlock;
  H.WaitFor;
  H.Free;
  Check((Dt >= 80) and (Dt < 2000), Format('Lock は持っているスレッドが外すまで待つ（%d ms）', [Dt]));
  WriteLn;
end;

procedure TestInitState;
var
  W: array[0..THREADS - 1] of TWorker;
begin
  WriteLn('4. 一度だけの初期化（TPMLInitState）');
  Check(GInit.Status = TPMLInitStatus.Uninitialized, '0 で始まる状態は未初期化');
  RunAll(TWorkKind.InitOnce, W);
  FreeAll(W);
  Check(GInitCount.Load = 1, Format('同時に呼んでも初期化するのは 1 スレッドだけ（%d）', [GInitCount.Load]));
  Check(GSawData.Load = THREADS - 1,
    Format('他のスレッドは初期化が済むまで待ち、戻ったときには結果が見える（%d / %d）', [GSawData.Load, THREADS - 1]));
  Check(GInit.Status = TPMLInitStatus.Initialized, '済んだら Initialized');
  Check(not GInit.ShouldInit, '済んだ後の ShouldInit は False');

  RunAll(TWorkKind.QuitOnce, W);
  FreeAll(W);
  Check(GQuitCount.Load = 1, Format('同時に呼んでも後始末をするのは 1 スレッドだけ（%d）', [GQuitCount.Load]));
  Check(GInit.Status = TPMLInitStatus.Uninitialized, '後始末が済んだら Uninitialized');
  Check(not GInit.ShouldQuit, '未初期化の ShouldQuit は False');

  Check(GInit.ShouldInit and (GInit.Status = TPMLInitStatus.Initializing), '未初期化なら ShouldInit は True（Initializing へ）');
  GInit.SetInitialized(False);
  Check(GInit.Status = TPMLInitStatus.Uninitialized, '初期化に失敗したら（SetInitialized(False)）未初期化に戻る');
  Check(GInit.ShouldInit, '失敗の後は次の ShouldInit がやり直す');
  GInit.SetInitialized(True);
  Check(GInit.Status = TPMLInitStatus.Initialized, 'やり直して済む');
  WriteLn;
end;

var
  Dog: TWatchdog;
begin
  WriteLn('test_atomic — 不可分操作・スピンロック・一度だけの初期化');
  WriteLn;
  Dog := TWatchdog.Create('watchdog', True);
  Dog.LimitMs := 60000;
  Dog.Start;
  TestSingleThread;
  TestContention;
  TestSpinWait;
  TestInitState;
  Dog.Terminate;
  Dog.WaitFor;
  Dog.Free;
  if Failures = 0 then
    WriteLn('=== 結論: 不可分操作・スピンロック・一度だけの初期化が SDL の約束どおりに動く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
