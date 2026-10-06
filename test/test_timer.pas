{
  test_timer — タイマー（AddTimer / AddTimerNS / RemoveTimer）を検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    PaPiMeLa.Time の TPMLTimerQueue（Ctx.Timer.AddTimer など）の約束を、実際に時間を
    経過させて見る。回数と間隔、戻り値による間隔の変更と停止、RemoveTimer の戻り値、
    コールバックが受け取る番号と間隔、呼ばれるスレッド、複数のタイマーの順序、
    コールバックの中からの追加と削除、例外を出したタイマーだけが止まること、
    破棄が呼んでいる最中のコールバックを待つこと、スレッドを最初の Add まで立てないこと。

  WHY:
    タイマーは別のスレッドで呼ばれるので、誤りは「たまに数が合わない」「終了時に落ちる」
    として出る。回数や時刻の許容幅は CI の遅いマシンでも通るように広めに取る。

  実行前提: cthreads（uses の先頭）。止まったら見張りが 60 秒で失敗として終わらせる。
}
program test_timer;

{$mode objfpc}{$H+}

uses
  cthreads,
  SysUtils, Classes, BaseUnix,
  PaPiMeLa.Errors,
  PaPiMeLa.Threading,
  PaPiMeLa.Time,
  PaPiMeLa.Core;

var
  Failures: Integer = 0;
  Ctx     : TPMLContext;
  MainID  : TThreadID;

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

{ コールバックの持ち主。数はタイマーのスレッドが書き、メインスレッドが読むので
  InterLocked で触る。 }
type
  TTarget = class
  public
    Count     : LongInt;
    Mode      : Integer;
    Interval  : LongWord;
    SeenID    : TPMLTimerID;
    SeenInt   : LongWord;
    SeenIntNS : UInt64;
    OnMain    : LongInt;
    Times     : array[0..15] of Int64;
    Order     : String;
    Tag       : Char;
    Lock      : TPMLMutex;
    Child     : TTarget;
    Gate      : TPMLSemaphore;
    Finished  : LongInt;
    constructor Create;
    destructor Destroy; override;
    function Tick(ATimerID: TPMLTimerID; AIntervalMs: LongWord): LongWord;
    function TickNS(ATimerID: TPMLTimerID; AIntervalNS: UInt64): UInt64;
  end;

  TOrderTarget = class
  public
    Shared: TTarget;
    Tag   : Char;
    function Tick(ATimerID: TPMLTimerID; AIntervalMs: LongWord): LongWord;
  end;

constructor TTarget.Create;
begin
  inherited Create;
  Lock := TPMLMutex.Create;
end;

destructor TTarget.Destroy;
begin
  Lock.Free;
  inherited Destroy;
end;

const
  MODE_REPEAT   = 0;   // 同じ間隔で続ける
  MODE_ONCE     = 1;   // 1 回で止める
  MODE_CHANGE   = 2;   // 1 回目の後は 100 ms に変える
  MODE_REMOVE   = 3;   // 自分を RemoveTimer してから同じ間隔を返す
  MODE_ADDCHILD = 4;   // 1 回目に子のタイマー（1 回だけ）を足す
  MODE_RAISE    = 5;   // 例外を出す
  MODE_SLOW     = 6;   // 300 ms かかる
  MODE_GATE     = 7;   // Gate が開くまで（最大 2 秒）待って止める

function TTarget.Tick(ATimerID: TPMLTimerID; AIntervalMs: LongWord): LongWord;
var
  N: LongInt;
  Sub: TTarget;
begin
  N := InterLockedIncrement(Count);
  if N - 1 <= High(Times) then
    Times[N - 1] := NowMs;
  SeenID := ATimerID;
  SeenInt := AIntervalMs;
  if GetCurrentThreadID = MainID then
    InterLockedIncrement(OnMain);
  Result := AIntervalMs;
  case Mode of
    MODE_ONCE: Result := 0;
    MODE_CHANGE: Result := 100;
    MODE_REMOVE: Ctx.Timer.RemoveTimer(ATimerID);
    MODE_ADDCHILD:
      if N = 1 then
      begin
        Sub := Child;
        Sub.Mode := MODE_ONCE;
        Ctx.Timer.AddTimer(10, @Sub.Tick);
        Result := 0;
      end;
    MODE_RAISE: raise EPMLArgument.Create('timer callback failed');
    MODE_SLOW:
      begin
        Sleep(300);
        InterLockedIncrement(Finished);
        Result := 0;
      end;
    MODE_GATE:
      begin
        Gate.WaitTimeout(2000);
        Result := 0;
      end;
  end;
end;

function TTarget.TickNS(ATimerID: TPMLTimerID; AIntervalNS: UInt64): UInt64;
begin
  InterLockedIncrement(Count);
  SeenID := ATimerID;
  SeenIntNS := AIntervalNS;
  if Count >= 3 then
    Result := 0
  else
    Result := AIntervalNS;
end;

function TOrderTarget.Tick(ATimerID: TPMLTimerID; AIntervalMs: LongWord): LongWord;
begin
  Shared.Lock.Lock;
  Shared.Order := Shared.Order + Tag;
  Shared.Lock.Unlock;
  Result := 0;
end;

function TaskCount: Integer;
var
  SR: TSearchRec;
begin
  Result := 0;
  if FindFirst('/proc/self/task/*', faDirectory, SR) = 0 then
  begin
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then
        Inc(Result);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
end;

procedure TestBasics;
var
  T, U: TTarget;
  ID, ID2: TPMLTimerID;
  T0, Dt: Int64;
  Tasks0: Integer;
  Raised: Boolean;
begin
  WriteLn('1. 立ち上げと繰り返し');
  Tasks0 := TaskCount;
  Check(not Ctx.Timer.Queue.ThreadStarted, '最初の AddTimer まではスレッドを立てない');

  Raised := False;
  try
    Ctx.Timer.AddTimer(10, nil);
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'コールバックが nil なら EPMLArgument');

  T := TTarget.Create;
  T.Mode := MODE_REPEAT;
  T0 := NowMs;
  ID := Ctx.Timer.AddTimer(50, @T.Tick);
  Check(ID <> 0, 'タイマーの番号は 0 でない');
  Check(Ctx.Timer.Queue.ThreadStarted and (TaskCount = Tasks0 + 1),
    Format('最初の AddTimer でスレッドが 1 本増える（%d → %d）', [Tasks0, TaskCount]));
  Sleep(530);
  Check(Ctx.Timer.RemoveTimer(ID), 'RemoveTimer は True');
  Dt := NowMs - T0;
  Check((T.Count >= 7) and (T.Count <= 11),
    Format('50 ms のタイマーが %d ms で %d 回（7〜11 回なら可）', [Dt, T.Count]));
  Check((T.Times[0] - T0 >= 49) and (T.Times[0] - T0 < 200),
    Format('最初の呼び出しは 50 ms 後（%d ms）', [T.Times[0] - T0]));
  Check(T.OnMain = 0, 'コールバックはメインスレッドで呼ばれない');
  Check((T.SeenID = ID) and (T.SeenInt = 50), 'コールバックは自分の番号と今の間隔を受け取る');
  Sleep(150);
  Check((T.Count <= 11) and not Ctx.Timer.RemoveTimer(ID),
    'RemoveTimer の後は呼ばれず、2 度目の RemoveTimer は False');
  Check(not Ctx.Timer.RemoveTimer(TPMLTimerID(123456789)), '知らない番号の RemoveTimer は False');
  T.Free;

  WriteLn;
  WriteLn('2. 戻り値で止める・間隔を変える');
  T := TTarget.Create;
  T.Mode := MODE_ONCE;
  ID := Ctx.Timer.AddTimer(20, @T.Tick);
  Sleep(200);
  Check(T.Count = 1, Format('0 を返せば 1 回で止まる（%d 回）', [T.Count]));
  Check(not Ctx.Timer.RemoveTimer(ID), '止まったタイマーの RemoveTimer は False');
  T.Free;

  T := TTarget.Create;
  T.Mode := MODE_CHANGE;
  T0 := NowMs;
  ID := Ctx.Timer.AddTimer(20, @T.Tick);
  Sleep(400);
  Ctx.Timer.RemoveTimer(ID);
  Check((T.Count >= 3) and (T.Count <= 5), Format('20 ms の後 100 ms に変えて 400 ms で %d 回（3〜5）', [T.Count]));
  if T.Count >= 3 then
    Check((T.Times[2] - T.Times[1] >= 95) and (T.Times[2] - T.Times[1] < 250) and (T.SeenInt = 100),
      Format('2 回目から 3 回目の間は約 100 ms（%d ms）、受け取る間隔も 100', [T.Times[2] - T.Times[1]]));
  T.Free;

  WriteLn;
  WriteLn('3. ナノ秒のタイマー');
  T := TTarget.Create;
  ID := Ctx.Timer.AddTimerNS(5000000, @T.TickNS);
  Sleep(200);
  Check((T.Count = 3) and (T.SeenID = ID) and (T.SeenIntNS = 5000000),
    Format('5 ms（ナノ秒で指定）で 3 回目に 0 を返して止まる（%d 回）', [T.Count]));
  T.Free;

  WriteLn;
  WriteLn('4. 番号と順序');
  T := TTarget.Create;
  try
    U := TTarget.Create;
    try
      ID := Ctx.Timer.AddTimer(1000, @T.Tick);
      ID2 := Ctx.Timer.AddTimer(1000, @U.Tick);
      Check((ID <> ID2) and (ID <> 0) and (ID2 <> 0), '番号は重ならない');
      Ctx.Timer.RemoveTimer(ID);
      Ctx.Timer.RemoveTimer(ID2);
    finally
      U.Free;
    end;
  finally
    T.Free;
  end;
  WriteLn;
end;

procedure TestOrder;
var
  S: TTarget;
  A, B, C: TOrderTarget;
begin
  WriteLn('5. 期限の早い順に呼ぶ');
  S := TTarget.Create;
  A := nil; B := nil; C := nil;
  try
    A := TOrderTarget.Create; A.Shared := S; A.Tag := 'a';
    B := TOrderTarget.Create; B.Shared := S; B.Tag := 'b';
    C := TOrderTarget.Create; C.Shared := S; C.Tag := 'c';
    Ctx.Timer.AddTimer(90, @A.Tick);
    Ctx.Timer.AddTimer(30, @B.Tick);
    Ctx.Timer.AddTimer(60, @C.Tick);
    Sleep(250);
    Check(S.Order = 'bca', '足した順ではなく期限の順（' + S.Order + '）');
  finally
    C.Free; B.Free; A.Free; S.Free;
  end;
  WriteLn;
end;

procedure TestInsideCallback;
var
  T, Child: TTarget;
begin
  WriteLn('6. コールバックの中から');
  T := TTarget.Create;
  T.Mode := MODE_REMOVE;
  Ctx.Timer.AddTimer(20, @T.Tick);
  Sleep(200);
  Check(T.Count = 1, Format('自分を RemoveTimer すれば、間隔を返しても次は呼ばれない（%d 回）', [T.Count]));
  T.Free;

  T := TTarget.Create;
  Child := TTarget.Create;
  T.Mode := MODE_ADDCHILD;
  T.Child := Child;
  Ctx.Timer.AddTimer(20, @T.Tick);
  Sleep(200);
  Check((T.Count = 1) and (Child.Count = 1), 'コールバックの中から足したタイマーも呼ばれる');
  Check(Child.OnMain = 0, '足されたタイマーもタイマーのスレッドで呼ばれる');
  T.Free;
  Child.Free;
  WriteLn;
end;

procedure TestErrors;
var
  Bad, Good: TTarget;
  ID: TPMLTimerID;
begin
  WriteLn('7. 例外を出したコールバック');
  Bad := TTarget.Create;
  Good := nil;
  try
    Bad.Mode := MODE_RAISE;
    Good := TTarget.Create;
    Good.Mode := MODE_REPEAT;
    ID := Ctx.Timer.AddTimer(20, @Bad.Tick);
    Ctx.Timer.AddTimer(20, @Good.Tick);
    Sleep(200);
    Check(Bad.Count = 1, Format('例外を出したタイマーは止まる（%d 回）', [Bad.Count]));
    Check(Good.Count >= 5, Format('他のタイマーは動き続ける（%d 回）', [Good.Count]));
    Check(Ctx.Timer.Queue.CallbackErrors = 1, Format('例外の数（%d）', [Ctx.Timer.Queue.CallbackErrors]));
    Check(Pos('timer callback failed', Ctx.Timer.Queue.LastCallbackError) > 0,
      '最後の例外の文言: ' + Ctx.Timer.Queue.LastCallbackError);
    Check(not Ctx.Timer.RemoveTimer(ID), '例外で止まったタイマーの RemoveTimer は False');
    Ctx.Timer.RemoveTimer(Good.SeenID);
    Sleep(50);
  finally
    Good.Free;
    Bad.Free;
  end;
  WriteLn;
end;

procedure TestShutdown;
var
  Slow, Rep, Late, Gate: TTarget;
  T0, Dt: Int64;
  CountAtFree: LongInt;
begin
  WriteLn('8. 破棄');
  Slow := TTarget.Create;
  Rep := nil;
  Late := nil;
  Gate := nil;
  try
    Slow.Mode := MODE_SLOW;
    Rep := TTarget.Create;
    Rep.Mode := MODE_REPEAT;
    Late := TTarget.Create;
    Late.Mode := MODE_ONCE;
    Gate := TTarget.Create;
    Gate.Mode := MODE_GATE;
    Gate.Gate := TPMLSemaphore.Create(0);
    // タイマーのスレッドを門で止めている間に Slow と Late を足す。門が開くと、次の周回で
    // 両方とも期限が来ている。Slow（先）が走っている間に破棄を始めれば、同じ周回で
    // Late を呼ぶかどうかの決定が破棄の後に来る。
    Ctx.Timer.AddTimer(1, @Gate.Tick);
    Sleep(30);
    Ctx.Timer.AddTimer(1, @Slow.Tick);
    Ctx.Timer.AddTimer(2, @Late.Tick);
    Ctx.Timer.AddTimer(5, @Rep.Tick);
    Sleep(20);
    Gate.Gate.Signal;
    Sleep(60);        // Slow のコールバックが走っている最中
    // Slow が走っている間は（スレッドは 1 本なので）他は呼ばれない。ここで数えた値が
    // 破棄の後も変わらなければ、破棄が始まってから呼び始めたものが無い。
    CountAtFree := Rep.Count + Late.Count;
    T0 := NowMs;
    FreeAndNil(Ctx);
    Dt := NowMs - T0;
    Check(Slow.Finished = 1, Format('呼んでいる最中のコールバックが終わるのを待つ（%d ms 待った）', [Dt]));
    Sleep(100);
    Check(Late.Count = 0, '同じ周回で期限の来ていたタイマーも、破棄が始まった後は呼ばない');
    Check(Rep.Count + Late.Count = CountAtFree, '破棄が始まってからは、どのコールバックも呼び始めない');
  finally
    // Context（とタイマー）を先に壊してから捨てる。逆だと解放済みのものが呼ばれうる。
    FreeAndNil(Ctx);
    if Assigned(Gate) then
      Gate.Gate.Free;
    Gate.Free;
    Late.Free;
    Rep.Free;
    Slow.Free;
  end;
  WriteLn;
end;

var
  Dog: TWatchdog;
begin
  WriteLn('test_timer — タイマー');
  WriteLn;
  Dog := TWatchdog.Create('watchdog', True);
  Dog.LimitMs := 60000;
  Dog.Start;
  MainID := GetCurrentThreadID;
  Ctx := TPMLContext.Create([]);
  TestBasics;
  TestOrder;
  TestInsideCallback;
  TestErrors;
  TestShutdown;
  Dog.Terminate;
  Dog.WaitFor;
  Dog.Free;
  if Failures = 0 then
    WriteLn('=== 結論: タイマーが SDL の約束と papimela の足した約束どおりに動く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
