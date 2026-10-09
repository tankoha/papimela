{
  PaPiMeLa.Atomic — 不可分操作・スピンロック・一度だけの初期化

  Origin : ported from SDL (src/atomic/SDL_atomic.c, src/atomic/SDL_spinlock.c,
           src/SDL_utils.c の SDL_ShouldInit / SDL_ShouldQuit / SDL_SetInitialized)
           Scope: 戻り値の約束（Set と Add は前の値、DecRef は 0 になったら True）、
           スピンロックの待ち方（32 回までは CPU の待ち命令、その後は眠って譲る）、
           初期化の状態の移り方。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.7、§11 #7

  WHAT:
    TPMLAtomicInt / TPMLAtomicU32 / TPMLAtomicPointer（不可分に読み書きする値）、
    TPMLSpinLock、TPMLInitState（複数のスレッドから呼ばれても初期化を一度だけにする）、
    メモリバリアと CPU の待ち命令。

  WHY:
    FPC の RTL の InterLocked* はあるが、名前と戻り値の約束が SDL と違う（例えば
    InterLockedIncrement は足した後の値を返す）。SDL の約束のまま使える形に揃える。

  RESOLVED:
    - 全ての不可分操作は SDL と同じく逐次一貫（seq_cst）の強さ。x86_64 は LOCK 付き命令が
      そのまま全バリアになる。それ以外（aarch64 など）は FPC の InterLocked* がバリアを
      持たない（ldxr / stxr だけ）ので、前後に ReadWriteBarrier を挟んで強さを揃えた
    - Load は LOCK CMPXCHG(0, 0) による本物の不可分な読み（Load の注を参照）
    - FPC 3.2.2 の InterLocked* には LongInt / Cardinal / Pointer の過負荷が全部ある。
      キャストは要らない
    - PMLMemoryBarrierAcquire / Release は x86 では lfence / sfence、それ以外は
      ReadWriteBarrier（FPC の WriteBarrier は aarch64 で dmb ishst になり、release に
      必要な「先行する読みも」を順序付けないため使わない）

  NOT RESOLVED:
    - aarch64 の枝（バリアの挿入と asm の yield）は、手元に交差コンパイラも実機も
      無いため未検証。x86_64 だけでコンパイルと実行を確かめた
    - TPMLSpinLock.Lock の「眠って譲る」は SDL と同じ Delay(0)（nanosleep(0)）。
      本当に CPU を譲る保証は無い（SDL 自身が FIXME としている）

  使い方の注意:
    どれも record で、中身が 0 の状態（値 0、ロックは外れている、未初期化）から
    使える。大域変数とクラスのフィールドは 0 で始まるのでそのまま使える。
    ローカル変数は Default(TPMLAtomicInt) などで 0 にしてから使う。
    コピーして使わない（コピーした先は別の値になる）。

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Atomic;

{$I papimela.inc}

interface

type
  { 符号付き 32 ビットの不可分な値（SDL_AtomicInt）。 }
  TPMLAtomicInt = record
  strict private
    FValue: LongInt;
  public
    // 今の値が AOld なら ANew にして True。違えば何もせず False（SDL_CompareAndSwapAtomicInt）。
    function  CompareAndSwap(AOld, ANew: LongInt): Boolean;
    // AValue にして、前の値を返す（SDL_SetAtomicInt）。
    function  Exchange(AValue: LongInt): LongInt;
    // 今の値（SDL_GetAtomicInt）。
    function  Load: LongInt;
    // ADelta を足して、**前の**値を返す（SDL_AddAtomicInt）。
    function  Add(ADelta: LongInt): LongInt;
    // 1 足して前の値を返す（SDL_AtomicIncRef）。
    function  IncRef: LongInt;
    // 1 引いて、0 になったら True（SDL_AtomicDecRef）。
    function  DecRef: Boolean;
  end;

  { 符号無し 32 ビットの不可分な値（SDL_AtomicU32）。桁あふれは 2^32 で回る。 }
  TPMLAtomicU32 = record
  strict private
    FValue: LongWord;
  public
    function  CompareAndSwap(AOld, ANew: LongWord): Boolean;
    function  Exchange(AValue: LongWord): LongWord;
    function  Load: LongWord;
    // ADelta（負でもよい）を足して、前の値を返す（SDL_AddAtomicU32）。
    function  Add(ADelta: LongInt): LongWord;
  end;

  { 不可分なポインタ（SDL の void * への不可分操作）。 }
  TPMLAtomicPointer = record
  strict private
    FValue: Pointer;
  public
    function  CompareAndSwap(AOld, ANew: Pointer): Boolean;
    function  Exchange(AValue: Pointer): Pointer;
    function  Load: Pointer;
  end;

  { スピンロック（SDL_SpinLock）。再帰しない（同じスレッドが重ねて Lock すると止まる）。
    ごく短い区間だけを守る。長く持つなら TPMLMutex（PaPiMeLa.Threading）を使う。 }
  TPMLSpinLock = record
  strict private
    FLock: LongInt;
  public
    // 取れたら True。待たない（SDL_TryLockSpinlock）。
    function  TryLock: Boolean;
    // 取れるまで待つ。32 回までは CPU の待ち命令を挟んで試し、その後は眠って
    // 他のスレッドに譲りながら試す（SDL_LockSpinlock）。
    procedure Lock;
    procedure Unlock;
  end;

  TPMLInitStatus = (Uninitialized, Initializing, Initialized, Uninitializing);

  { 初期化と後始末を一度だけにする（SDL_InitState）。

      if State.ShouldInit then
      begin
        ... 初期化 ...
        State.SetInitialized(Ok);   // 失敗なら False（未初期化に戻る）
      end;

    ShouldInit は、未初期化なら呼んだスレッドに初期化を任せて True。他のスレッドが
    初期化している最中なら、それが終わるまで待つ。済んでいれば False。
    ShouldQuit は後始末について同じことをする。SetInitialized は、ShouldInit /
    ShouldQuit で True を受け取ったスレッドが呼ぶ。 }
  TPMLInitState = record
  strict private
    FStatus: TPMLAtomicInt;
    FThread: TThreadID;
    function GetStatus: TPMLInitStatus;
  public
    function  ShouldInit: Boolean;
    function  ShouldQuit: Boolean;
    procedure SetInitialized(AInitialized: Boolean);
    property  Status: TPMLInitStatus read GetStatus;
  end;

// 書いたものが、この後で他のスレッドが読む前に見えるようにする（SDL_MemoryBarrierRelease）。
procedure PMLMemoryBarrierRelease;
// 他のスレッドが書いたものを、この後で読む前に見えるようにする（SDL_MemoryBarrierAcquire）。
procedure PMLMemoryBarrierAcquire;
// 空回りで待つときの CPU の待ち命令（SDL_CPUPauseInstruction）。
procedure PMLCPUPause;

implementation

uses
  BaseUnix;

{ ---- 内部の道具 ---- }

{ PORT-NOTE: SDL は GCC の __sync_* / __atomic_*（SEQ_CST）か MSVC の Interlocked* を
  使い、どれも全バリアを含む。FPC の InterLocked* は x86_64 / i386 では LOCK 付き命令
  （xchg / lock xadd / lock cmpxchg）なのでそのまま全バリアだが、aarch64 などでは
  ldxr / stxr の組だけでバリアを持たない（FPC 3.2.2 の rtl/aarch64/aarch64.inc で確認）。
  そこで x86 以外では不可分操作の前後にフルバリアを挟み、SDL と同じ強さにする。
  x86 では何も出さない（中身は条件コンパイルの外にコメントだけが残る）。 }
procedure FenceBeforeRMW; inline;
begin
{$IF NOT (DEFINED(CPUX86_64) OR DEFINED(CPUI386))}
  ReadWriteBarrier;
{$ENDIF}
end;

procedure FenceAfterRMW; inline;
begin
{$IF NOT (DEFINED(CPUX86_64) OR DEFINED(CPUI386))}
  ReadWriteBarrier;
{$ENDIF}
end;

{ PORT-NOTE: SDL_Delay 相当（SDL_SYS_DelayNS の nanosleep の枝）。この単位は最下層で
  PaPiMeLa.Time を uses できないため、BaseUnix の fpNanoSleep を直接呼ぶ。EINTR なら
  残りを寝直し、それ以外の失敗では止める（PaPiMeLa.Time の PMLDelayNS と同じ手順）。 }
procedure SleepNS(ANs: Int64);
var
  Req, Rem: TTimeSpec;
  Failed: LongInt;
begin
  Rem.tv_sec := ANs div 1000000000;
  Rem.tv_nsec := ANs mod 1000000000;
  repeat
    Req.tv_sec := Rem.tv_sec;
    Req.tv_nsec := Rem.tv_nsec;
    Failed := fpNanoSleep(@Req, @Rem);
  until (Failed = 0) or (fpgeterrno <> ESysEINTR);
end;

{ ---- TPMLAtomicInt ---- }

{ PORT-NOTE: SDL_CompareAndSwapAtomicInt（__sync_bool_compare_and_swap）。
  InterLockedCompareExchange は前の値を返すので、AOld と等しければ置き換わっている。 }
function TPMLAtomicInt.CompareAndSwap(AOld, ANew: LongInt): Boolean;
begin
  FenceBeforeRMW;
  Result := InterLockedCompareExchange(FValue, ANew, AOld) = AOld;
  FenceAfterRMW;
end;

// PORT-NOTE: SDL_SetAtomicInt。InterLockedExchange（x86 の xchg）は前の値を返す。
function TPMLAtomicInt.Exchange(AValue: LongInt): LongInt;
begin
  FenceBeforeRMW;
  Result := InterLockedExchange(FValue, AValue);
  FenceAfterRMW;
end;

{ WHAT:
    今の値を、取得（acquire）以上の強さで不可分に読む。

  WHY:
    普通の読み（Result := FValue）にしない理由は 2 つある。
      - FPC には volatile が無く、ループの中でレジスタに写されたままになりうる
      - x86 以外では、読みの後ろの命令との順序が付かない
    そこで InterLockedCompareExchange(FValue, 0, 0) を使う。値が 0 なら 0 を書き戻す
    だけ、0 以外なら何も変えずに今の値を返す。どちらも LOCK 付きの 1 命令で、
    全バリアを含み、32 ビットの読みが裂けることもない。SDL の古い GCC 枝の
    __sync_val_compare_and_swap(&v, 0, 0) と同じ手である。

  代償:
    読み専用のメモリには使えない。キャッシュラインを書き込み状態にするので、読むだけの
    スレッドが多いと普通の読みより遅い。 }
function TPMLAtomicInt.Load: LongInt;
begin
  FenceBeforeRMW;
  Result := InterLockedCompareExchange(FValue, 0, 0);
  FenceAfterRMW;
end;

{ PORT-NOTE: SDL_AddAtomicInt（__sync_fetch_and_add）。InterLockedExchangeAdd は
  足す前の値を返す（InterLockedIncrement は足した後の値なので使わない）。 }
function TPMLAtomicInt.Add(ADelta: LongInt): LongInt;
begin
  FenceBeforeRMW;
  Result := InterLockedExchangeAdd(FValue, ADelta);
  FenceAfterRMW;
end;

// PORT-NOTE: SDL_AtomicIncRef は SDL_AddAtomicInt(a, 1) のマクロ。
function TPMLAtomicInt.IncRef: LongInt;
begin
  Result := Add(1);
end;

// PORT-NOTE: SDL_AtomicDecRef は (SDL_AddAtomicInt(a, -1) == 1) のマクロ。
function TPMLAtomicInt.DecRef: Boolean;
begin
  Result := Add(-1) = 1;
end;

{ ---- TPMLAtomicU32 ---- }

{ FPC 3.2.2 の InterLocked* には Cardinal（LongWord と同じ型）の過負荷があるので、
  キャストなしで呼べる（rtl/inc/systemh.inc の「unsigned overloads」）。 }
function TPMLAtomicU32.CompareAndSwap(AOld, ANew: LongWord): Boolean;
begin
  FenceBeforeRMW;
  Result := InterLockedCompareExchange(FValue, ANew, AOld) = AOld;
  FenceAfterRMW;
end;

function TPMLAtomicU32.Exchange(AValue: LongWord): LongWord;
begin
  FenceBeforeRMW;
  Result := InterLockedExchange(FValue, AValue);
  FenceAfterRMW;
end;

// Load の理由は TPMLAtomicInt.Load と同じ。
function TPMLAtomicU32.Load: LongWord;
begin
  FenceBeforeRMW;
  Result := InterLockedCompareExchange(FValue, 0, 0);
  FenceAfterRMW;
end;

{ ADelta は符号付きだが、LongWord への型変換は 2 の補数の並びをそのまま移すだけで、
  足し算は 2^32 で回る。-1 を足せば 1 引くのと同じ。 }
function TPMLAtomicU32.Add(ADelta: LongInt): LongWord;
begin
  FenceBeforeRMW;
  Result := InterLockedExchangeAdd(FValue, LongWord(ADelta));
  FenceAfterRMW;
end;

{ ---- TPMLAtomicPointer ---- }

{ FPC 3.2.2 の InterLocked* には Pointer の過負荷がある（64 ビットでは
  FPC_INTERLOCKED*64 へ、32 ビットでは 32 ビット版へ繋がる）。キャストは要らない。 }
function TPMLAtomicPointer.CompareAndSwap(AOld, ANew: Pointer): Boolean;
begin
  FenceBeforeRMW;
  Result := InterLockedCompareExchange(FValue, ANew, AOld) = AOld;
  FenceAfterRMW;
end;

function TPMLAtomicPointer.Exchange(AValue: Pointer): Pointer;
begin
  FenceBeforeRMW;
  Result := InterLockedExchange(FValue, AValue);
  FenceAfterRMW;
end;

// Load の理由は TPMLAtomicInt.Load と同じ（ポインタ幅の LOCK CMPXCHG）。
function TPMLAtomicPointer.Load: Pointer;
begin
  FenceBeforeRMW;
  Result := InterLockedCompareExchange(FValue, nil, nil);
  FenceAfterRMW;
end;

{ ---- TPMLSpinLock ---- }

{ WHAT:
    ロックを 1 にして、前が 0 なら取れた。

  WHY:
    SDL は __sync_lock_test_and_set（取得だけの強さ）。x86 では LOCK XCHG で、どのみち
    全バリアになる。InterLockedExchange を使い、x86 以外では後ろにバリアを挟んで
    取得の順序を保つ。 }
function TPMLSpinLock.TryLock: Boolean;
begin
  Result := InterLockedExchange(FLock, 1) = 0;
  FenceAfterRMW;
end;

{ PORT-NOTE: SDL_LockSpinlock。32 回までは CPU の待ち命令、その後は SDL_Delay(0)
  （nanosleep の 0 ナノ秒。SDL 自身が「確実に譲るとは限らない」と FIXME している）。
  SDL と同じく、いつまでも取れなくても打ち切らない。 }
procedure TPMLSpinLock.Lock;
var
  Iterations: LongInt;
begin
  Iterations := 0;
  while not TryLock do
  begin
    if Iterations < 32 then
    begin
      Inc(Iterations);
      PMLCPUPause;
    end
    else
      SleepNS(0);
  end;
end;

{ WHAT:
    ロックを 0 に戻す。守っていた区間の読み書きが、0 を書く前に済んでいることを
    保証する（解放の順序）。

  WHY:
    SDL は __sync_lock_release（x86 では普通の mov 0）。FPC には volatile が無く、
    普通の代入ではコンパイラが並べ替えうるので InterLockedExchange(FLock, 0) で書く。
    x86 では LOCK XCHG になり SDL の mov より重いが、全バリアなので必ず正しい。
    x86 以外では前にフルバリアを挟む（dmb ishst では先行する読みを順序付けられない）。 }
procedure TPMLSpinLock.Unlock;
begin
  FenceBeforeRMW;
  InterLockedExchange(FLock, 0);
end;

{ ---- TPMLInitState ---- }

function TPMLInitState.GetStatus: TPMLInitStatus;
begin
  Result := TPMLInitStatus(FStatus.Load);
end;

{ PORT-NOTE: SDL_ShouldInit。済んでいなければ、未初期化 → 初期化中 の CAS に勝った
  スレッドが True を受け取る。負けたスレッド（相手が初期化中、または後始末中）は
  1 ms 眠って見直し、済めば False で戻る。待ち中の値の読みは Load（取得）なので、
  初期化したスレッドの書き込みは、False で戻ったスレッドから見える。 }
function TPMLInitState.ShouldInit: Boolean;
begin
  while FStatus.Load <> LongInt(TPMLInitStatus.Initialized) do
  begin
    if FStatus.CompareAndSwap(LongInt(TPMLInitStatus.Uninitialized),
         LongInt(TPMLInitStatus.Initializing)) then
    begin
      FThread := GetCurrentThreadId;
      Exit(True);
    end;
    // 他のスレッドの移り変わりが終わるのを待つ
    SleepNS(1000000);
  end;
  Result := False;
end;

// PORT-NOTE: SDL_ShouldQuit。ShouldInit の逆向き（初期化済み → 後始末中）。
function TPMLInitState.ShouldQuit: Boolean;
begin
  while FStatus.Load <> LongInt(TPMLInitStatus.Uninitialized) do
  begin
    if FStatus.CompareAndSwap(LongInt(TPMLInitStatus.Initialized),
         LongInt(TPMLInitStatus.Uninitializing)) then
    begin
      FThread := GetCurrentThreadId;
      Exit(True);
    end;
    SleepNS(1000000);
  end;
  Result := False;
end;

{ PORT-NOTE: SDL_SetInitialized。

  WHAT:
    SDL は SDL_assert で「呼ぶのは ShouldInit / ShouldQuit で True を受け取ったスレッド」
    を検査する。同じく Assert で検査する。

  WHY:
    Assert は FPC では -Sa を付けたときだけ有効で、既定（リリース）では消える。SDL の
    SDL_assert がリリースで消えるのと同じ。この単位は例外を投げない方針なので、
    検査を有効にしたときだけ Assert が止める。違反しても状態の更新は SDL と同じで、
    検査を消した版では何も検出されない。

  順序:
    Exchange は全バリアを含むので、初期化で書いたものが、この後 ShouldInit から
    戻るスレッドに見える（解放の順序）。 }
procedure TPMLInitState.SetInitialized(AInitialized: Boolean);
begin
  Assert(FThread = GetCurrentThreadId,
    'TPMLInitState.SetInitialized は ShouldInit / ShouldQuit で True を受け取ったスレッドが呼ぶ');
  if AInitialized then
    FStatus.Exchange(LongInt(TPMLInitStatus.Initialized))
  else
    FStatus.Exchange(LongInt(TPMLInitStatus.Uninitialized));
end;

{ ---- バリアと待ち命令 ---- }

{ PORT-NOTE: SDL_MemoryBarrierRelease は __atomic_thread_fence(__ATOMIC_RELEASE)
  （x86 ではコンパイラの順序付けだけで命令は出ない）。x86 はハードウェアが書きの順序を
  保つので、FPC の WriteBarrier（sfence）で足りる。それ以外は、先行する読みと書きの
  両方を後ろの書きより前に済ませる必要があるので、フルバリア（aarch64 の dmb ish）
  にする。FPC の WriteBarrier は aarch64 で dmb ishst（書きだけ）になり、足りない。
  SDL より強い（遅い）が、正しい。 }
procedure PMLMemoryBarrierRelease;
begin
{$IF DEFINED(CPUX86_64) OR DEFINED(CPUI386)}
  WriteBarrier;
{$ELSE}
  ReadWriteBarrier;
{$ENDIF}
end;

{ PORT-NOTE: SDL_MemoryBarrierAcquire は __atomic_thread_fence(__ATOMIC_ACQUIRE)。
  x86 はハードウェアが読みの順序を保つので ReadBarrier（lfence）で足りる。
  それ以外はフルバリア。 }
procedure PMLMemoryBarrierAcquire;
begin
{$IF DEFINED(CPUX86_64) OR DEFINED(CPUI386)}
  ReadBarrier;
{$ELSE}
  ReadWriteBarrier;
{$ENDIF}
end;

{ PORT-NOTE: SDL_CPUPauseInstruction。x86 は pause、aarch64 は yield、他は何もしない
  （SDL は arm / powerpc などにも専用の命令を持つが、初回の対象外）。aarch64 の
  yield は交差コンパイラが無く未検証。 }
procedure PMLCPUPause;
begin
{$IF DEFINED(CPUX86_64) OR DEFINED(CPUI386)}
  asm
    pause
  end;
{$ELSEIF DEFINED(CPUAARCH64)}
  asm
    yield
  end;
{$ENDIF}
end;

end.
