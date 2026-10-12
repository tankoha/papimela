{
  PaPiMeLa.Threading — スレッドと同期の部品（pthread を直接使う）

  Origin : ported from SDL (src/thread/pthread/SDL_sysmutex.c, SDL_sysrwlock.c,
           SDL_syssem.c, SDL_syscond.c, SDL_systhread.c, src/core/linux/SDL_threadprio.c)
           Scope: 再帰ミューテックス、読み書きロック、セマフォ、条件変数の振る舞い（EINTR で
           待ち直す、時間切れの扱い）、子スレッドで非同期シグナルを止める一覧、スレッド名の
           16 バイト制限、優先度（nice 値の対応と RealtimeKit への頼み方）。
           構造は本設計に従う（TThread の派生、管理レコードのロックガード）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.7、§11 #8

  WHAT:
    TPMLMutex / TPMLRWLock / TPMLSemaphore / TPMLCondition、ミューテックスのスコープガード
    TPMLLockGuard、名前と優先度を持つスレッド TPMLThread。

  WHY:
    RTL の TRTLCriticalSection は TryLock と時間切れ付きの待ちを揃えて持たない。pthread を
    直接使えば SDL と同じ約束（TryLock、再帰ロック、時間切れ付きの Wait）をそのまま出せる。
    スレッドは TThread を薄く派生する（独自のスレッドの抽象は作らない。§4.7）。

  RESOLVED:
    - cthreads（FPC のスレッドドライバ）が uses に無いプログラムで TThread を作ると、例外では
      なく実行時エラー 232 でプロセスが終わる（実測）。TPMLThread は作る前に確かめ、
      EPMLThreadError を投げる。同期の部品は pthread を直接呼ぶので cthreads が無くても動く
    - 時間切れは CLOCK_MONOTONIC で測る（条件変数は pthread_condattr_setclock、セマフォは
      sem_clockwait）。PORT-NOTE: SDL は CLOCK_REALTIME の絶対時刻で待つので、待っている間に
      時計を合わせると待ちが伸び縮みする
    - 子スレッドでは SDL と同じ非同期シグナル（SIGHUP、SIGINT、SIGQUIT、SIGPIPE、SIGALRM、
      SIGTERM、SIGWINCH、SIGVTALRM、SIGPROF）を止める。シグナルは主スレッドが受ける
    - PORT-NOTE: SDL が子スレッドで設定する非同期の取り消し（pthread_setcanceltype の
      ASYNCHRONOUS）は移植しない。SDL 自身のコメントが「どのプラットフォームでも使うべきで
      ない」としている。papimela はスレッドを取り消す API を持たない
    - 優先度は SDL の Linux の既定（SCHED_OTHER のまま nice 値を変える。Low = 19、
      Normal = 0、High = -10、TimeCritical = -20）。setpriority が権限で断られたら
      RealtimeKit の MakeThreadHighPriorityWithPID に頼む。RealtimeKit の下限
      （MinNiceLevel）より上げることは頼まない
    - RealtimeKit の相手は SDL と同じ選び方（セッションバスの xdg-desktop-portal の Realtime
      を、RTTimeUSecMax が読めるときだけ先に使い、無ければシステムバスの RealtimeKit1）。
      相手と上限・下限（MinNiceLevel、MaxRealtimePriority、RTTimeUSecMax）はプロセスで
      1 度だけ読む。読めない値は SDL の既定（-20、99、200000）
    - 実時間スケジューリング（SCHED_RR / SCHED_FIFO）は、ヒント
      PAPIMELA_THREAD_PRIORITY_POLICY（current / other / rr / fifo）と
      PAPIMELA_THREAD_FORCE_REALTIME_TIME_CRITICAL で選ぶ（PMLThreadSchedPolicy）。RR / FIFO
      では RLIMIT_RTTIME と SCHED_RESET_ON_FORK を整えてから RealtimeKit の
      MakeThreadRealtimeWithPID に頼む。sched_setscheduler で RR / FIFO にはしない（SDL と同じ）
    - PORT-NOTE(bug): SDL は最初の 1 回だけ、実時間の優先度を RealtimeKit の上限を読む前に
      既定の 99 から計算する（D-58）。ここでは上限を先に読む
    - 方針を "fifo" にしても FIFO にはならない（RealtimeKit は RR しか渡さない。SDL も同じ: D-59）

  NOT RESOLVED:
    - スレッドごとの値（SDL_GetTLS / SDL_SetTLS）は Pascal の threadvar で足りるので持たない

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Threading;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Errors;

type
  // pthread の型は中身を見ない。x86_64 と aarch64 の glibc で足りる大きさを取る
  // （mutex 40 / 48、rwlock 56、cond 48、sem 32 バイト）。8 バイト境界に揃える。
  TPMLPthreadStorage = record
    Data: array[0..7] of QWord;
  end;

  { 再帰ミューテックス（同じスレッドが重ねて Lock できる。Lock した回数だけ Unlock する）。
    Lock / Unlock は失敗しない（失敗は使い方の誤りなので、例外ではなく何もしない）。 }
  TPMLMutex = class sealed
  strict private
    FMutex: TPMLPthreadStorage;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Lock;
    // すぐ取れなければ False（待たない）。
    function  TryLock: Boolean;
    procedure Unlock;
    // TPMLCondition が使う。
    function  Handle: Pointer;
  end;

  { 読み書きロック。読む側は何スレッドでも同時に、書く側は 1 つだけ。
    同じスレッドが書くために重ねて取ると止まる（再帰しない。SDL と同じ）。 }
  TPMLRWLock = class sealed
  strict private
    FLock: TPMLPthreadStorage;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LockForReading;
    procedure LockForWriting;
    function  TryLockForReading: Boolean;
    function  TryLockForWriting: Boolean;
    procedure Unlock;
  end;

  { 数を数えるセマフォ。Wait は数が 1 以上になるまで待って 1 減らす。 }
  TPMLSemaphore = class sealed
  strict private
    FSem: TPMLPthreadStorage;
    function GetValue: LongWord;
  public
    constructor Create(AInitialValue: LongWord);
    destructor Destroy; override;
    procedure Wait;
    // 待たない。減らせたら True。
    function  TryWait: Boolean;
    // ATimeoutNS < 0 は無期限、0 は TryWait。時間切れなら False。
    function  WaitTimeoutNS(ATimeoutNS: Int64): Boolean;
    function  WaitTimeout(ATimeoutMs: Integer): Boolean;
    procedure Signal;
    property  Value: LongWord read GetValue;
  end;

  { 条件変数。Wait は AMutex を Lock した状態で呼ぶ。待つ間は外れ、戻るときに取り直す。
    起こされても条件が成り立っているとは限らない（spurious wakeup）。条件は呼ぶ側が
    ループで確かめる。 }
  TPMLCondition = class sealed
  strict private
    FCond: TPMLPthreadStorage;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Signal;
    procedure Broadcast;
    procedure Wait(AMutex: TPMLMutex);
    // ATimeoutNS < 0 は無期限。時間切れなら False（AMutex は取り直してある）。
    function  WaitTimeoutNS(AMutex: TPMLMutex; ATimeoutNS: Int64): Boolean;
    function  WaitTimeout(AMutex: TPMLMutex; ATimeoutMs: Integer): Boolean;
  end;

  { ミューテックスのスコープガード。変数がスコープを出るとき（例外のときも）Unlock する。

      var G: TPMLLockGuard;
      begin
        G := TPMLLockGuard.Lock(FMutex);
        ...            // ここまで Lock されている
      end;             // ここで Unlock

    コピーするとコピーの分だけ Lock を重ねる（ミューテックスは再帰するので、それぞれの
    寿命の終わりに 1 回ずつ外れて釣り合う）。Release で早めに外せる。 }
  TPMLLockGuard = record
  strict private
    FMutex: TPMLMutex;
  public
    class function Lock(AMutex: TPMLMutex): TPMLLockGuard; static;
    procedure Release;
    class operator Initialize(var AGuard: TPMLLockGuard);
    class operator Finalize(var AGuard: TPMLLockGuard);
    class operator Copy(constref ASource: TPMLLockGuard; var ADest: TPMLLockGuard);
  end;

  TPMLThreadPriority = (Low, Normal, High, TimeCritical);

  // スレッドのスケジューリングの方針（SCHED_OTHER / SCHED_RR / SCHED_FIFO）。
  TPMLSchedPolicy = (Other, RR, FIFO);

  // TPMLThread.CreateFunc で走らせる関数。戻り値はスレッドの終わりの値（WaitFor で受け取る）。
  TPMLThreadFunc = function(AData: Pointer): Integer;

  { 名前付きのスレッド。Run を上書きするか、CreateFunc で関数を渡す。

    TThread との違い: 作る前に cthreads を確かめる、走り出すときにスレッド名と
    シグナルのマスクを設定する、Run の戻り値が WaitFor の値になる。 }
  TPMLThread = class(TThread)
  strict private
    FName : String;
    FFunc : TPMLThreadFunc;
    FData : Pointer;
  protected
    procedure Execute; override;
    // 既定は CreateFunc の関数を呼ぶ。上書きするならそちらを使わない。
    function  Run: Integer; virtual;
  public
    // ACreateSuspended が False ならすぐ走る。名前は 15 バイトまでで切られる（Linux の制限）。
    constructor Create(const AName: String; ACreateSuspended: Boolean = False;
      AStackSize: SizeUInt = DefaultStackSize);
    constructor CreateFunc(const AName: String; AFunc: TPMLThreadFunc; AData: Pointer;
      AStackSize: SizeUInt = DefaultStackSize);
    property Name: String read FName;

    // 呼んだスレッド自身の優先度を変える。できなければ False（例外にしない）。
    class function SetCurrentPriority(APriority: TPMLThreadPriority): Boolean; overload; static;
    { 方針つき（SDL_SYS_SetThreadPriority）。APolicyHint と AForceRealtimeTimeCritical は
      ヒント PAPIMELA_THREAD_PRIORITY_POLICY と PAPIMELA_THREAD_FORCE_REALTIME_TIME_CRITICAL の値
      （TPMLContextBase.SetCurrentThreadPriority が渡す）。方針は PMLThreadSchedPolicy で決め、
      RR / FIFO なら RealtimeKit（xdg-desktop-portal の Realtime を先に、無ければシステムの
      RealtimeKit1）に実時間を頼む。上げられなければ False。 }
    class function SetCurrentPriority(APriority: TPMLThreadPriority; const APolicyHint: String;
      AForceRealtimeTimeCritical: Boolean): Boolean; overload; static;
    // 呼んだスレッドの今の方針と実時間の優先度（SCHED_OTHER なら 0）。
    class function CurrentSchedPolicy: TPMLSchedPolicy; static;
    class function CurrentRealtimePriority: Integer; static;
    // 呼んだスレッドの nice 値（-20〜19）。読めなければ 0。
    class function CurrentNiceValue: Integer; static;
    // 呼んだスレッドの OS 上の名前。
    class function CurrentName: String; static;
    // TThread を作れるか（cthreads が uses にあるか）。
    class function Available: Boolean; static;
  end;

{ スレッドの優先度を上げるときの方針を決める（SDL_SYS_SetThreadPriority の方針の部分）。
  ヒントが無ければ（APolicyHint が空）、Low / Normal / High / TimeCritical はどれも Other。
  AForceRealtimeTimeCritical なら TimeCritical は RR。APolicyHint が 'current' なら ACurrent、
  'other' / 'rr' / 'fifo' ならそれ、それ以外の値なら上の既定。 }
function PMLThreadSchedPolicy(APriority: TPMLThreadPriority; const APolicyHint: String;
  AForceRealtimeTimeCritical: Boolean; ACurrent: TPMLSchedPolicy): TPMLSchedPolicy;
{ RR / FIFO のときの実時間の優先度（SDL_SetLinuxThreadPriorityAndPolicy）。AMaxRealtime は
  RealtimeKit の MaxRealtimePriority。Low は 1、Normal は半分、High は 3/4、TimeCritical は上限。 }
function PMLRealtimePriority(APriority: TPMLThreadPriority; AMaxRealtime: Integer): Integer;
{ RealtimeKit の MaxRealtimePriority（ポータルの Realtime を先に、無ければシステムの RealtimeKit1）。
  どちらにも届かなければ 0。 }
function PMLRealtimeKitMaxPriority: Integer;

implementation

uses
  BaseUnix, Unix, UnixType,
  PaPiMeLa.Atomic,
  PaPiMeLa.Platform.DBus;

const
  libc = 'c';
  PTHREAD_MUTEX_RECURSIVE = 1;
  CLOCK_MONOTONIC = 1;
  PRIO_PROCESS = 0;
  ESYS_ETIMEDOUT = 110;
  ESYS_EINTR     = 4;

type
  TTimeSpec64 = record
    tv_sec : Int64;
    tv_nsec: Int64;
  end;
  PTimeSpec64 = ^TTimeSpec64;

function pthread_mutexattr_init(attr: Pointer): cint; cdecl; external libc;
function pthread_mutexattr_settype(attr: Pointer; kind: cint): cint; cdecl; external libc;
function pthread_mutexattr_destroy(attr: Pointer): cint; cdecl; external libc;
function pthread_mutex_init(m: Pointer; attr: Pointer): cint; cdecl; external libc;
function pthread_mutex_destroy(m: Pointer): cint; cdecl; external libc;
function pthread_mutex_lock(m: Pointer): cint; cdecl; external libc;
function pthread_mutex_trylock(m: Pointer): cint; cdecl; external libc;
function pthread_mutex_unlock(m: Pointer): cint; cdecl; external libc;

function pthread_rwlock_init(l: Pointer; attr: Pointer): cint; cdecl; external libc;
function pthread_rwlock_destroy(l: Pointer): cint; cdecl; external libc;
function pthread_rwlock_rdlock(l: Pointer): cint; cdecl; external libc;
function pthread_rwlock_wrlock(l: Pointer): cint; cdecl; external libc;
function pthread_rwlock_tryrdlock(l: Pointer): cint; cdecl; external libc;
function pthread_rwlock_trywrlock(l: Pointer): cint; cdecl; external libc;
function pthread_rwlock_unlock(l: Pointer): cint; cdecl; external libc;

function pthread_condattr_init(attr: Pointer): cint; cdecl; external libc;
function pthread_condattr_setclock(attr: Pointer; clock: cint): cint; cdecl; external libc;
function pthread_condattr_destroy(attr: Pointer): cint; cdecl; external libc;
function pthread_cond_init(c: Pointer; attr: Pointer): cint; cdecl; external libc;
function pthread_cond_destroy(c: Pointer): cint; cdecl; external libc;
function pthread_cond_signal(c: Pointer): cint; cdecl; external libc;
function pthread_cond_broadcast(c: Pointer): cint; cdecl; external libc;
function pthread_cond_wait(c: Pointer; m: Pointer): cint; cdecl; external libc;
function pthread_cond_timedwait(c: Pointer; m: Pointer; abstime: PTimeSpec64): cint; cdecl; external libc;

function sem_init(s: Pointer; pshared: cint; value: cuint): cint; cdecl; external libc;
function sem_destroy(s: Pointer): cint; cdecl; external libc;
function sem_wait(s: Pointer): cint; cdecl; external libc;
function sem_trywait(s: Pointer): cint; cdecl; external libc;
function sem_clockwait(s: Pointer; clock: cint; abstime: PTimeSpec64): cint; cdecl; external libc;
function sem_post(s: Pointer): cint; cdecl; external libc;
function sem_getvalue(s: Pointer; value: pcint): cint; cdecl; external libc;

function pthread_self: PtrUInt; cdecl; external libc;
function pthread_setname_np(thread: PtrUInt; name: PAnsiChar): cint; cdecl; external libc;
function pthread_getname_np(thread: PtrUInt; name: PAnsiChar; len: csize_t): cint; cdecl; external libc;
function pthread_sigmask(how: cint; newset, oldset: PSigSet): cint; cdecl; external libc;
function clock_gettime(clk: cint; tp: PTimeSpec64): cint; cdecl; external libc;
function gettid: cint; cdecl; external libc;
function setpriority(which: cint; who: cuint; prio: cint): cint; cdecl; external libc;
function getpriority(which: cint; who: cuint): cint; cdecl; external libc;
function __errno_location: pcint; cdecl; external libc;

{ 今から ATimeoutNS 後の CLOCK_MONOTONIC の絶対時刻。 }
function MonotonicDeadline(ATimeoutNS: Int64): TTimeSpec64;
begin
  clock_gettime(CLOCK_MONOTONIC, @Result);
  Inc(Result.tv_sec, ATimeoutNS div 1000000000);
  Inc(Result.tv_nsec, ATimeoutNS mod 1000000000);
  while Result.tv_nsec >= 1000000000 do
  begin
    Inc(Result.tv_sec);
    Dec(Result.tv_nsec, 1000000000);
  end;
end;

{ TPMLMutex }

constructor TPMLMutex.Create;
var
  Attr: TPMLPthreadStorage;
begin
  inherited Create;
  FillChar(Attr, SizeOf(Attr), 0);
  pthread_mutexattr_init(@Attr);
  pthread_mutexattr_settype(@Attr, PTHREAD_MUTEX_RECURSIVE);
  if pthread_mutex_init(@FMutex, @Attr) <> 0 then
  begin
    pthread_mutexattr_destroy(@Attr);
    raise EPMLThreadError.Create('pthread_mutex_init failed');
  end;
  pthread_mutexattr_destroy(@Attr);
end;

destructor TPMLMutex.Destroy;
begin
  pthread_mutex_destroy(@FMutex);
  inherited Destroy;
end;

procedure TPMLMutex.Lock;
begin
  pthread_mutex_lock(@FMutex);
end;

function TPMLMutex.TryLock: Boolean;
begin
  Result := pthread_mutex_trylock(@FMutex) = 0;
end;

procedure TPMLMutex.Unlock;
begin
  pthread_mutex_unlock(@FMutex);
end;

function TPMLMutex.Handle: Pointer;
begin
  Result := @FMutex;
end;

{ TPMLRWLock }

constructor TPMLRWLock.Create;
begin
  inherited Create;
  if pthread_rwlock_init(@FLock, nil) <> 0 then
    raise EPMLThreadError.Create('pthread_rwlock_init failed');
end;

destructor TPMLRWLock.Destroy;
begin
  pthread_rwlock_destroy(@FLock);
  inherited Destroy;
end;

procedure TPMLRWLock.LockForReading;
begin
  pthread_rwlock_rdlock(@FLock);
end;

procedure TPMLRWLock.LockForWriting;
begin
  pthread_rwlock_wrlock(@FLock);
end;

function TPMLRWLock.TryLockForReading: Boolean;
begin
  Result := pthread_rwlock_tryrdlock(@FLock) = 0;
end;

function TPMLRWLock.TryLockForWriting: Boolean;
begin
  Result := pthread_rwlock_trywrlock(@FLock) = 0;
end;

procedure TPMLRWLock.Unlock;
begin
  pthread_rwlock_unlock(@FLock);
end;

{ TPMLSemaphore }

constructor TPMLSemaphore.Create(AInitialValue: LongWord);
begin
  inherited Create;
  if sem_init(@FSem, 0, AInitialValue) <> 0 then
    raise EPMLThreadError.Create('sem_init failed');
end;

destructor TPMLSemaphore.Destroy;
begin
  sem_destroy(@FSem);
  inherited Destroy;
end;

procedure TPMLSemaphore.Wait;
begin
  WaitTimeoutNS(-1);
end;

function TPMLSemaphore.TryWait: Boolean;
begin
  Result := sem_trywait(@FSem) = 0;
end;

function TPMLSemaphore.WaitTimeoutNS(ATimeoutNS: Int64): Boolean;
var
  Deadline: TTimeSpec64;
  R: cint;
begin
  if ATimeoutNS = 0 then
    Exit(TryWait);
  if ATimeoutNS < 0 then
  begin
    repeat
      R := sem_wait(@FSem);
    until (R = 0) or (__errno_location^ <> ESYS_EINTR);
    Exit(R = 0);
  end;
  Deadline := MonotonicDeadline(ATimeoutNS);
  repeat
    R := sem_clockwait(@FSem, CLOCK_MONOTONIC, @Deadline);
  until (R = 0) or (__errno_location^ <> ESYS_EINTR);
  Result := R = 0;
end;

function TPMLSemaphore.WaitTimeout(ATimeoutMs: Integer): Boolean;
begin
  if ATimeoutMs < 0 then
    Result := WaitTimeoutNS(-1)
  else
    Result := WaitTimeoutNS(Int64(ATimeoutMs) * 1000000);
end;

procedure TPMLSemaphore.Signal;
begin
  sem_post(@FSem);
end;

function TPMLSemaphore.GetValue: LongWord;
var
  V: cint;
begin
  V := 0;
  sem_getvalue(@FSem, @V);
  if V < 0 then
    V := 0;
  Result := LongWord(V);
end;

{ TPMLCondition }

constructor TPMLCondition.Create;
var
  Attr: TPMLPthreadStorage;
begin
  inherited Create;
  FillChar(Attr, SizeOf(Attr), 0);
  pthread_condattr_init(@Attr);
  pthread_condattr_setclock(@Attr, CLOCK_MONOTONIC);
  if pthread_cond_init(@FCond, @Attr) <> 0 then
  begin
    pthread_condattr_destroy(@Attr);
    raise EPMLThreadError.Create('pthread_cond_init failed');
  end;
  pthread_condattr_destroy(@Attr);
end;

destructor TPMLCondition.Destroy;
begin
  pthread_cond_destroy(@FCond);
  inherited Destroy;
end;

procedure TPMLCondition.Signal;
begin
  pthread_cond_signal(@FCond);
end;

procedure TPMLCondition.Broadcast;
begin
  pthread_cond_broadcast(@FCond);
end;

procedure TPMLCondition.Wait(AMutex: TPMLMutex);
begin
  pthread_cond_wait(@FCond, AMutex.Handle);
end;

function TPMLCondition.WaitTimeoutNS(AMutex: TPMLMutex; ATimeoutNS: Int64): Boolean;
var
  Deadline: TTimeSpec64;
  R: cint;
begin
  if ATimeoutNS < 0 then
    Exit(pthread_cond_wait(@FCond, AMutex.Handle) = 0);
  Deadline := MonotonicDeadline(ATimeoutNS);
  repeat
    R := pthread_cond_timedwait(@FCond, AMutex.Handle, @Deadline);
  until R <> ESYS_EINTR;
  Result := R <> ESYS_ETIMEDOUT;
end;

function TPMLCondition.WaitTimeout(AMutex: TPMLMutex; ATimeoutMs: Integer): Boolean;
begin
  if ATimeoutMs < 0 then
    Result := WaitTimeoutNS(AMutex, -1)
  else
    Result := WaitTimeoutNS(AMutex, Int64(ATimeoutMs) * 1000000);
end;

{ TPMLLockGuard }

class function TPMLLockGuard.Lock(AMutex: TPMLMutex): TPMLLockGuard;
begin
  // Result は Initialize 済み（FMutex = nil）。ここで取る。
  AMutex.Lock;
  Result.FMutex := AMutex;
end;

procedure TPMLLockGuard.Release;
begin
  if Assigned(FMutex) then
  begin
    FMutex.Unlock;
    FMutex := nil;
  end;
end;

class operator TPMLLockGuard.Initialize(var AGuard: TPMLLockGuard);
begin
  AGuard.FMutex := nil;
end;

class operator TPMLLockGuard.Finalize(var AGuard: TPMLLockGuard);
begin
  AGuard.Release;
end;

class operator TPMLLockGuard.Copy(constref ASource: TPMLLockGuard; var ADest: TPMLLockGuard);
begin
  // 上書きされる側が持っていたロックを先に外し、コピーした分だけ取り直す。
  if ADest.FMutex = ASource.FMutex then
    Exit;
  ADest.Release;
  if Assigned(ASource.FMutex) then
  begin
    ASource.FMutex.Lock;
    ADest.FMutex := ASource.FMutex;
  end;
end;

{ TPMLThread }

class function TPMLThread.Available: Boolean;
var
  M: TThreadManager;
begin
  // cthreads が無いときの既定のスレッドマネージャは InitManager を持たない（実測）。
  GetThreadManager(M);
  Result := Assigned(M.InitManager);
end;

procedure RequireThreadSupport;
begin
  if not TPMLThread.Available then
    raise EPMLThreadError.Create('no thread support: put "cthreads" first in the program''s uses clause');
end;

constructor TPMLThread.Create(const AName: String; ACreateSuspended: Boolean;
  AStackSize: SizeUInt);
begin
  RequireThreadSupport;
  FName := AName;
  FreeOnTerminate := False;
  inherited Create(ACreateSuspended, AStackSize);
end;

constructor TPMLThread.CreateFunc(const AName: String; AFunc: TPMLThreadFunc;
  AData: Pointer; AStackSize: SizeUInt);
begin
  RequireThreadSupport;
  FName := AName;
  FFunc := AFunc;
  FData := AData;
  FreeOnTerminate := False;
  inherited Create(False, AStackSize);
end;

function TPMLThread.Run: Integer;
begin
  if Assigned(FFunc) then
    Result := FFunc(FData)
  else
    Result := 0;
end;

{ 走り出したスレッドの中で、名前とシグナルのマスクを設定してから Run を呼ぶ。 }
procedure TPMLThread.Execute;
var
  Buf: array[0..15] of AnsiChar;
  Mask: TSigSet;
  N: Integer;
begin
  if FName <> '' then
  begin
    // Linux のスレッド名は終端込みで 16 バイト。長ければ切る（SDL と同じ）。
    FillChar(Buf, SizeOf(Buf), 0);
    N := Length(FName);
    if N > 15 then
      N := 15;
    Move(FName[1], Buf[0], N);
    pthread_setname_np(pthread_self, @Buf[0]);
  end;
  fpsigemptyset(Mask);
  fpsigaddset(Mask, SIGHUP);
  fpsigaddset(Mask, SIGINT);
  fpsigaddset(Mask, SIGQUIT);
  fpsigaddset(Mask, SIGPIPE);
  fpsigaddset(Mask, SIGALRM);
  fpsigaddset(Mask, SIGTERM);
  fpsigaddset(Mask, SIGWINCH);
  fpsigaddset(Mask, SIGVTALRM);
  fpsigaddset(Mask, SIGPROF);
  pthread_sigmask(SIG_BLOCK, @Mask, nil);
  ReturnValue := Run;
end;

class function TPMLThread.CurrentNiceValue: Integer;
var
  E: pcint;
  R: cint;
begin
  // getpriority は -1 を正しい値としても返すので、errno を 0 にしてから呼ぶ。
  E := __errno_location;
  E^ := 0;
  R := getpriority(PRIO_PROCESS, cuint(gettid));
  if (R = -1) and (E^ <> 0) then
    Result := 0
  else
    Result := R;
end;

class function TPMLThread.CurrentName: String;
var
  Buf: array[0..63] of AnsiChar;
begin
  FillChar(Buf, SizeOf(Buf), 0);
  if pthread_getname_np(pthread_self, @Buf[0], SizeOf(Buf)) = 0 then
    Result := String(PAnsiChar(@Buf[0]))
  else
    Result := '';
end;

{ ---- RealtimeKit ---- }

const
  RTKIT_NODE   = 'org.freedesktop.RealtimeKit1';
  RTKIT_PATH   = '/org/freedesktop/RealtimeKit1';
  RTKIT_IFACE  = 'org.freedesktop.RealtimeKit1';
  PORTAL_NODE  = 'org.freedesktop.portal.Desktop';
  PORTAL_PATH  = '/org/freedesktop/portal/desktop';
  PORTAL_IFACE = 'org.freedesktop.portal.Realtime';

type
  { RealtimeKit の相手と、その上限・下限。プロセスで 1 度だけ決める（SDL の
    rtkit_initialize_once）。UsePortal は SDL の rtkit_use_session_conn。 }
  TRealtimeKitInfo = record
    Init         : TPMLInitState;
    UsePortal    : Boolean;
    // 相手に届いたか（ポータルが答えた、または MaxRealtimePriority を読めた）。
    Reachable    : Boolean;
    MinNice      : Integer;
    MaxRealtime  : Integer;
    MaxRTTimeUSec: Int64;
  end;

var
  GRealtimeKit: TRealtimeKitInfo;

{ Properties.Get(AIface, AName) で整数の性質を読む。型が AType（int32 か int64）でなければ
  読めなかったことにする（SDL_DBus_QueryPropertyOnConnection と同じ）。 }
function QueryRealtimeKitProperty(AConn: TPMLDBusConnection; const ANode, APath, AIface,
  AName: String; AType: LongInt; out AValue: Int64): Boolean;
var
  Msg, Reply: PDBusMessage;
  W: TPMLDBusWriter;
  R: TPMLDBusReader;
begin
  Result := False;
  AValue := 0;
  try
    Msg := AConn.BeginCall(ANode, APath, 'org.freedesktop.DBus.Properties', 'Get');
    Reply := nil;
    try
      W := AConn.Writer(Msg);
      W.AddString(AIface);
      W.AddString(AName);
      Reply := AConn.Send(Msg, 1000);
      R := AConn.Reader(Reply);
      if R.ArgType = DBUS_TYPE_VARIANT then
      begin
        R := R.Recurse;
        if R.ArgType = AType then
        begin
          if AType = DBUS_TYPE_INT64 then
            AValue := R.AsInt64
          else
            AValue := R.AsInt32;
          Result := True;
        end;
      end;
    finally
      AConn.Unref(Reply);
      AConn.Unref(Msg);
    end;
  except
    // 相手が居ない・性質が無い・断られた。読めなかったとして返す。
    on E: EPMLError do
      Result := False;
  end;
end;

{ 呼び出し先の組（ポータルかシステムの RealtimeKit1）。 }
procedure RealtimeKitTarget(AUsePortal: Boolean; out ANode, APath, AIface: String;
  out ABus: LongInt);
begin
  if AUsePortal then
  begin
    ANode := PORTAL_NODE;
    APath := PORTAL_PATH;
    AIface := PORTAL_IFACE;
    ABus := DBUS_BUS_SESSION;
  end
  else
  begin
    ANode := RTKIT_NODE;
    APath := RTKIT_PATH;
    AIface := RTKIT_IFACE;
    ABus := DBUS_BUS_SYSTEM;
  end;
end;

{ SDL の set_rtkit_interface。xdg-desktop-portal の Realtime は、セッションバスで
  RTTimeUSecMax（int64）が読めるときだけ使う（読めれば、ポータルが居て Realtime を
  持ち、必要な修正が入った版だと分かる）。読めなければシステムの RealtimeKit1。
  繋いだ接続を返す（どちらにも繋げなければ nil）。 }
function OpenRealtimeKitConnection(out AUsePortal: Boolean): TPMLDBusConnection;
var
  V: Int64;
begin
  Result := nil;
  AUsePortal := False;
  try
    Result := TPMLDBusConnection.Create(DBUS_BUS_SESSION);
    AUsePortal := QueryRealtimeKitProperty(Result, PORTAL_NODE, PORTAL_PATH, PORTAL_IFACE,
      'RTTimeUSecMax', DBUS_TYPE_INT64, V);
  except
    // セッションバスに繋げない。システムの RealtimeKit1 へ。
    on E: EPMLError do
      AUsePortal := False;
  end;
  if AUsePortal then
    Exit;
  FreeAndNil(Result);
  try
    Result := TPMLDBusConnection.Create(DBUS_BUS_SYSTEM);
  except
    // システムバスにも繋げない。
    on E: EPMLError do
      Result := nil;
  end;
end;

{ SDL の rtkit_initialize。読めなかった値は SDL の既定（MinNiceLevel -20、
  MaxRealtimePriority 99、RTTimeUSecMax 200000）のまま。 }
procedure InitializeRealtimeKit;
var
  Conn: TPMLDBusConnection;
  Node, Path, Iface: String;
  Bus: LongInt;
  UsePortal: Boolean;
  V: Int64;
begin
  GRealtimeKit.Reachable := False;
  GRealtimeKit.MinNice := -20;
  GRealtimeKit.MaxRealtime := 99;
  GRealtimeKit.MaxRTTimeUSec := 200000;
  Conn := OpenRealtimeKitConnection(UsePortal);
  GRealtimeKit.UsePortal := UsePortal;
  if UsePortal then
    GRealtimeKit.Reachable := True;
  if Conn = nil then
    Exit;
  try
    RealtimeKitTarget(UsePortal, Node, Path, Iface, Bus);
    if QueryRealtimeKitProperty(Conn, Node, Path, Iface, 'MinNiceLevel', DBUS_TYPE_INT32, V) then
      GRealtimeKit.MinNice := Integer(V);
    if QueryRealtimeKitProperty(Conn, Node, Path, Iface, 'MaxRealtimePriority', DBUS_TYPE_INT32, V) then
    begin
      GRealtimeKit.MaxRealtime := Integer(V);
      GRealtimeKit.Reachable := True;
    end;
    if QueryRealtimeKitProperty(Conn, Node, Path, Iface, 'RTTimeUSecMax', DBUS_TYPE_INT64, V) then
      GRealtimeKit.MaxRTTimeUSec := V;
  finally
    Conn.Free;
  end;
end;

{ 1 度だけ InitializeRealtimeKit を走らせる。走っている最中の他のスレッドは終わるまで待つ。 }
procedure EnsureRealtimeKit;
begin
  if GRealtimeKit.Init.ShouldInit then
  begin
    try
      InitializeRealtimeKit;
    finally
      GRealtimeKit.Init.SetInitialized(True);
    end;
  end;
end;

{ RealtimeKit に ATid の優先度を頼む。AIsRealtime なら MakeThreadRealtimeWithPID(pid, tid,
  uint32 優先度)、そうでなければ MakeThreadHighPriorityWithPID(pid, tid, int32 nice)。 }
function RealtimeKitCall(ATid: cint; AIsRealtime: Boolean; AValue: Integer): Boolean;
var
  Conn: TPMLDBusConnection;
  Msg, Reply: PDBusMessage;
  W: TPMLDBusWriter;
  Node, Path, Iface, Method: String;
  Bus: LongInt;
begin
  Result := False;
  RealtimeKitTarget(GRealtimeKit.UsePortal, Node, Path, Iface, Bus);
  if AIsRealtime then
    Method := 'MakeThreadRealtimeWithPID'
  else
    Method := 'MakeThreadHighPriorityWithPID';
  try
    Conn := TPMLDBusConnection.Create(Bus);
    try
      Msg := Conn.BeginCall(Node, Path, Iface, Method);
      Reply := nil;
      try
        W := Conn.Writer(Msg);
        W.AddUInt64(QWord(fpGetPid));
        W.AddUInt64(QWord(ATid));
        if AIsRealtime then
          W.AddUInt32(LongWord(AValue))
        else
          W.AddInt32(AValue);
        Reply := Conn.Send(Msg, 1000);
        Result := True;
      finally
        Conn.Unref(Reply);
        Conn.Unref(Msg);
      end;
    finally
      Conn.Free;
    end;
  except
    // バスが無い・RealtimeKit が居ない・断られた。優先度は変えられなかったとして返す。
    on E: EPMLError do
      Result := False;
  end;
end;

{ RealtimeKit に、このスレッドの nice 値を上げてもらう（権限の無いプロセス向け）。
  MinNiceLevel より上げる値は頼まない（頼むと断られる）。SDL の rtkit_setpriority_nice。 }
function RealtimeKitNice(ATid: cint; ANice: Integer): Boolean;
begin
  EnsureRealtimeKit;
  if ANice < GRealtimeKit.MinNice then
    ANice := GRealtimeKit.MinNice;
  Result := RealtimeKitCall(ATid, False, ANice);
end;

const
  RLIMIT_RTTIME       = 15;
  SCHED_RESET_ON_FORK = $40000000;
  SCHED_FIFO_VALUE    = 1;
  SCHED_RR_VALUE      = 2;

type
  TRLimit = record
    rlim_cur, rlim_max: QWord;
  end;
  // glibc の struct sched_param は int 1 つ。他の libc で大きくても溢れないよう余白を取る。
  TSchedParam = record
    sched_priority: cint;
    Reserved      : array[0..62] of cint;
  end;

function sched_getscheduler(pid: cint): cint; cdecl; external libc;
function sched_setscheduler(pid: cint; policy: cint; param: Pointer): cint; cdecl; external libc;
function sched_getparam(pid: cint; param: Pointer): cint; cdecl; external libc;
function getrlimit(resource: cint; rlim: Pointer): cint; cdecl; external libc;
function setrlimit(resource: cint; rlim: Pointer): cint; cdecl; external libc;

{ SDL の rtkit_initialize_realtime_thread。RealtimeKit が実時間を渡す条件（RLIMIT_RTTIME を
  置く、方針に SCHED_RESET_ON_FORK を足す）を整える。どこかで失敗したらそこで止めるが、
  呼び出し側は結果を見ずに RealtimeKit へ頼む（SDL と同じ。本当に断られるかは RealtimeKit
  に任せる）。呼ぶ前に EnsureRealtimeKit で MaxRTTimeUSec を読んでおくこと。 }
procedure InitializeRealtimeThread;
var
  Lim: TRLimit;
  Param: TSchedParam;
  Policy: cint;
begin
  Policy := sched_getscheduler(0) or SCHED_RESET_ON_FORK;
  FillChar(Param, SizeOf(Param), 0);
  if getrlimit(RLIMIT_RTTIME, @Lim) <> 0 then
    Exit;
  Lim.rlim_max := QWord(GRealtimeKit.MaxRTTimeUSec);
  Lim.rlim_cur := Lim.rlim_max div 2;
  if setrlimit(RLIMIT_RTTIME, @Lim) <> 0 then
    Exit;
  if sched_getparam(0, @Param) <> 0 then
    Exit;
  sched_setscheduler(0, Policy, @Param);
end;

{ SDL の rtkit_setpriority_realtime。上限を超える優先度は上限に丸める。 }
function RealtimeKitRealtime(ATid: cint; APriority: Integer): Boolean;
begin
  EnsureRealtimeKit;
  if APriority > GRealtimeKit.MaxRealtime then
    APriority := GRealtimeKit.MaxRealtime;
  if APriority < 0 then
    APriority := 0;
  InitializeRealtimeThread;
  Result := RealtimeKitCall(ATid, True, APriority);
end;

class function TPMLThread.SetCurrentPriority(APriority: TPMLThreadPriority): Boolean;
var
  Nice: Integer;
  Tid: cint;
begin
  case APriority of
    TPMLThreadPriority.Low:          Nice := 19;
    TPMLThreadPriority.High:         Nice := -10;
    TPMLThreadPriority.TimeCritical: Nice := -20;
  else
    Nice := 0;
  end;
  Tid := gettid;
  if setpriority(PRIO_PROCESS, cuint(Tid), Nice) = 0 then
    Exit(True);
  // 権限が無くて上げられなかった。RealtimeKit に頼む（下げる・戻すのは頼まない）。
  if Nice < CurrentNiceValue then
    Result := RealtimeKitNice(Tid, Nice)
  else
    Result := False;
end;

function PMLThreadSchedPolicy(APriority: TPMLThreadPriority; const APolicyHint: String;
  AForceRealtimeTimeCritical: Boolean; ACurrent: TPMLSchedPolicy): TPMLSchedPolicy;
var
  PriPolicy: TPMLSchedPolicy;
begin
  // Linux の SDL は、どの優先度でも既定は SCHED_OTHER（RR を既定にするのは Apple だけ）。
  PriPolicy := TPMLSchedPolicy.Other;
  if AForceRealtimeTimeCritical and (APriority = TPMLThreadPriority.TimeCritical) then
    PriPolicy := TPMLSchedPolicy.RR;
  // SDL_strcmp と同じく、大文字小文字を区別して完全に一致したときだけ。
  if APolicyHint = 'current' then
    Result := ACurrent
  else if APolicyHint = 'other' then
    Result := TPMLSchedPolicy.Other
  else if APolicyHint = 'rr' then
    Result := TPMLSchedPolicy.RR
  else if APolicyHint = 'fifo' then
    Result := TPMLSchedPolicy.FIFO
  else
    Result := PriPolicy;
end;

function PMLRealtimePriority(APriority: TPMLThreadPriority; AMaxRealtime: Integer): Integer;
begin
  case APriority of
    TPMLThreadPriority.Low:          Result := 1;
    TPMLThreadPriority.High:         Result := AMaxRealtime * 3 div 4;
    TPMLThreadPriority.TimeCritical: Result := AMaxRealtime;
  else
    Result := AMaxRealtime div 2;
  end;
end;

{ SDL_SetLinuxThreadPriorityAndPolicy（方針の決め方は SDL_SYS_SetThreadPriority）。
  Other は nice 値を変える（1 引数版）。RR / FIFO は RealtimeKit に実時間を頼む。
  sched_setscheduler で RR / FIFO にはしない（SDL もしない。RealtimeKit が設定する）。

  PORT-NOTE(bug): SDL は実時間の優先度を rtkit_max_realtime_priority から計算するが、その値を
  RealtimeKit から読む rtkit_initialize は、計算の後の rtkit_setpriority_realtime の中で
  初めて走る。最初の 1 回だけ既定の 99 から計算され、High（3/4）が上限で頭打ちになって
  TimeCritical と同じ優先度になる（docs/DEFECTS.md D-58）。ここでは計算の前に読む。 }
class function TPMLThread.SetCurrentPriority(APriority: TPMLThreadPriority;
  const APolicyHint: String; AForceRealtimeTimeCritical: Boolean): Boolean;
var
  Policy: TPMLSchedPolicy;
  Prio: Integer;
begin
  Policy := PMLThreadSchedPolicy(APriority, APolicyHint, AForceRealtimeTimeCritical,
    CurrentSchedPolicy);
  if Policy = TPMLSchedPolicy.Other then
    Exit(SetCurrentPriority(APriority));
  EnsureRealtimeKit;
  Prio := PMLRealtimePriority(APriority, GRealtimeKit.MaxRealtime);
  Result := RealtimeKitRealtime(gettid, Prio);
end;

class function TPMLThread.CurrentSchedPolicy: TPMLSchedPolicy;
var
  P: cint;
begin
  P := sched_getscheduler(0);
  if P < 0 then
    Exit(TPMLSchedPolicy.Other);
  case (P and not SCHED_RESET_ON_FORK) of
    SCHED_FIFO_VALUE: Result := TPMLSchedPolicy.FIFO;
    SCHED_RR_VALUE:   Result := TPMLSchedPolicy.RR;
  else
    Result := TPMLSchedPolicy.Other;
  end;
end;

class function TPMLThread.CurrentRealtimePriority: Integer;
var
  Param: TSchedParam;
begin
  Result := 0;
  if CurrentSchedPolicy = TPMLSchedPolicy.Other then
    Exit;
  FillChar(Param, SizeOf(Param), 0);
  if sched_getparam(0, @Param) = 0 then
    Result := Param.sched_priority;
end;

function PMLRealtimeKitMaxPriority: Integer;
begin
  EnsureRealtimeKit;
  if GRealtimeKit.Reachable then
    Result := GRealtimeKit.MaxRealtime
  else
    Result := 0;
end;

end.
