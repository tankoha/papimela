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
      RealtimeKit（システムバス）の MakeThreadHighPriority に頼む。RealtimeKit の下限
      （MinNiceLevel）より上げることは頼まない

  NOT RESOLVED:
    - 実時間スケジューリング（SCHED_RR / SCHED_FIFO と RealtimeKit の MakeThreadRealtime）は
      SDL ではヒントで選ぶ経路。ヒント（#6 Properties）が無いので入れていない
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
    class function SetCurrentPriority(APriority: TPMLThreadPriority): Boolean; static;
    // 呼んだスレッドの nice 値（-20〜19）。読めなければ 0。
    class function CurrentNiceValue: Integer; static;
    // 呼んだスレッドの OS 上の名前。
    class function CurrentName: String; static;
    // TThread を作れるか（cthreads が uses にあるか）。
    class function Available: Boolean; static;
  end;

implementation

uses
  BaseUnix, Unix, UnixType,
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

{ RealtimeKit に、このスレッドの nice 値を上げてもらう（権限の無いプロセス向け）。
  MinNiceLevel より上げる値は頼まない（頼むと断られる）。 }
function RealtimeKitNice(ATid: cint; ANice: Integer): Boolean;
const
  SERVICE = 'org.freedesktop.RealtimeKit1';
  PATH    = '/org/freedesktop/RealtimeKit1';
  IFACE   = 'org.freedesktop.RealtimeKit1';
var
  Conn: TPMLDBusConnection;
  Msg, Reply: PDBusMessage;
  W: TPMLDBusWriter;
  R: TPMLDBusReader;
  MinNice: Integer;
begin
  Result := False;
  try
    Conn := TPMLDBusConnection.Create(DBUS_BUS_SYSTEM);
    try
      MinNice := -15;
      // Properties.Get(s interface, s name) → v(i)
      Msg := Conn.BeginCall(SERVICE, PATH, 'org.freedesktop.DBus.Properties', 'Get');
      Reply := nil;
      try
        W := Conn.Writer(Msg);
        W.AddString(IFACE);
        W.AddString('MinNiceLevel');
        Reply := Conn.Send(Msg, 1000);
        R := Conn.Reader(Reply);
        if R.ArgType = DBUS_TYPE_VARIANT then
        begin
          R := R.Recurse;
          if R.ArgType = DBUS_TYPE_INT32 then
            MinNice := R.AsInt32;
        end;
      finally
        Conn.Unref(Reply);
        Conn.Unref(Msg);
      end;
      if ANice < MinNice then
        ANice := MinNice;
      Msg := Conn.BeginCall(SERVICE, PATH, IFACE, 'MakeThreadHighPriority');
      Reply := nil;
      try
        W := Conn.Writer(Msg);
        W.AddUInt64(QWord(ATid));
        W.AddInt32(ANice);
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
    // システムバスが無い・RealtimeKit が居ない・断られた。優先度は変えられなかったとして返す。
    on E: EPMLError do
      Result := False;
  end;
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

end.
