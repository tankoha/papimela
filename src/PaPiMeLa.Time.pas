{
  PaPiMeLa.Time — 待つ（Delay / DelayNS / DelayPrecise）とタイマー（AddTimer / RemoveTimer）

  Origin : ported from SDL (src/timer/SDL_timer.c, src/timer/unix/SDL_systimer.c)
           Scope: SDL_Delay / SDL_DelayNS / SDL_DelayPrecise と、その下の
           SDL_SYS_DelayNS（nanosleep を割り込まれたら残りを寝直す）。
           SDL_AddTimer / SDL_AddTimerNS / SDL_RemoveTimer と、期限順の列を 1 本の
           スレッドで回す SDL_TimerThread（Emscripten の枝は移植しない）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4（TPMLTimerService の行）、§11 #9

  WHAT:
    今のスレッドを指定した時間だけ止める。
      PMLDelay        ミリ秒
      PMLDelayNS      ナノ秒。精度は OS の眠りの精度（Linux ではふつう 0.1 ms 未満の遅れ）
      PMLDelayPrecise ナノ秒。1 ms ずつ眠って遅れの最大を測り、残りを短く眠ってから
                      最後の端数だけ空回りで待つ。早く戻らず、遅れも小さい

    タイマー（TPMLTimerQueue）。スレッド 1 本（papimela-timer）が、期限の順に並べた列から
    期限の来たタイマーのコールバックを呼ぶ。次の期限まで、または新しいタイマーが来るまで
    セマフォで待つ。約束は TPMLTimerQueue の説明を参照。

  WHY:
    VSync が効かない環境で、アプリのループが CPU を使い切らないように（F-6）。
    Context は要らない（SDL_Delay も初期化なしで呼べる）。Context.Timer からも
    同じものを呼べる（TPMLTimerService.Delay など）。

    DelayPrecise の手順は、時計と眠りと空回りを引数で受け取る
    PMLDelayPreciseWith に置く。本物の時計では手順の正しさを決定的に検査
    できないので、検査は偽の時計を渡して眠りの列を比べる。

  RESOLVED:
    - SDL_InitTimers / SDL_QuitTimers は、最初の Add でスレッドを立てること・
      TPMLTimerQueue の破棄に対応する
    - コールバックの中からの Add / Remove、Remove と呼び出しの競合、破棄と実行中の
      コールバックの競合の扱いは、実装側の TPMLTimerCore の説明にある

  NOT RESOLVED:
    - 時計は PaPiMeLa.Events の PMLNowNS（CLOCK_MONOTONIC）をそのまま使う。
      SDL_GetTicksNS は初期化からの経過時間だが、papimela の TicksNS は
      単調時計の生の値（既存の契約のまま）
    - コールバックの中から、そのタイマーを持つ Context を Free することはできない
      （EPMLThreadError。タイマーのスレッドが自分自身を待つことになるため）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Time;

{$I papimela.inc}

interface

const
  PML_NS_PER_MS     = UInt64(1000000);
  PML_NS_PER_SECOND = UInt64(1000000000);

type
  // 今の時刻（ナノ秒、単調増加）。
  TPMLNowFunc   = function: UInt64;
  // 少なくとも ANs ナノ秒眠る。
  TPMLSleepProc = procedure(ANs: UInt64);
  // 空回り 1 回ぶんの待ち（CPU に「待っている」と知らせる命令）。
  TPMLPauseProc = procedure;

procedure PMLDelay(AMs: LongWord);
procedure PMLDelayNS(ANs: UInt64);
procedure PMLDelayPrecise(ANs: UInt64);

{ DelayPrecise の手順そのもの。PMLDelayPrecise は本物の時計
  （PMLNowNS）と PMLDelayNS と空回りの命令を渡してこれを呼ぶ。
  検査が偽の時計を渡すために公開している。 }
procedure PMLDelayPreciseWith(ANs: UInt64; ANow: TPMLNowFunc;
  ASleep: TPMLSleepProc; APause: TPMLPauseProc);

type
  // タイマーの番号。0 は「無い」。
  TPMLTimerID = type LongWord;

  { タイマーが来たときに呼ばれる（SDL_TimerCallback / SDL_NSTimerCallback）。
    **タイマーのスレッドで呼ばれる**（メインスレッドではない）。戻り値が次の間隔で、
    0 を返すとそのタイマーは止まる。AInterval は今の間隔。 }
  TPMLTimerCallback   = function(ATimerID: TPMLTimerID; AIntervalMs: LongWord): LongWord of object;
  TPMLTimerCallbackNS = function(ATimerID: TPMLTimerID; AIntervalNS: UInt64): UInt64 of object;

  { タイマーの列と、それを回すスレッド 1 本（SDL_timer.c の移植）。

    約束（SDL と同じところ）:
      - スレッドは最初の Add で立てる。どのスレッドから Add / Remove してもよい
        （コールバックの中からでも）
      - コールバックは 1 本のスレッドで順に呼ぶ。長いコールバックは他を遅らせる
      - 次の予定は「そのタイマーを処理し始めた時刻 + 戻り値」（遅れは持ち越す）
      - Remove は印を付けるだけ。印の付いたタイマーはもう呼ばない（呼んでいる最中なら、
        その呼び出しは最後まで走る）。見つからない・もう止まっている番号なら False
    約束（papimela が足したところ）:
      - コールバックが例外を出したら、そのタイマーは止める（0 を返したのと同じ）。
        スレッドは止めず、例外の数と最後の文言を残す（CallbackErrors / LastCallbackError）
      - Free（Context の破棄）は、呼んでいる最中のコールバックが終わるのを待ってから
        スレッドを止める。その後はどのコールバックも呼ばない
      - スレッドを立てられない（cthreads が無い）なら Add が EPMLThreadError
      - コールバックが nil なら Add が EPMLArgument }
  TPMLTimerQueue = class
  strict private
    FImpl: TObject;   // 中身は implementation 側
    function GetCallbackErrors: Integer;
    function GetThreadStarted: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function  Add(AIntervalMs: LongWord; ACallback: TPMLTimerCallback): TPMLTimerID;
    function  AddNS(AIntervalNS: UInt64; ACallback: TPMLTimerCallbackNS): TPMLTimerID;
    function  Remove(AID: TPMLTimerID): Boolean;
    function  LastCallbackError: String;
    property  CallbackErrors: Integer read GetCallbackErrors;
    // タイマーのスレッドを立てたか（最初の Add まで False）。
    property  ThreadStarted: Boolean read GetThreadStarted;
  end;

implementation

uses
  SysUtils, Classes, BaseUnix, UnixType,
  PaPiMeLa.Errors,
  PaPiMeLa.Threading,
  PaPiMeLa.Events;

{ PORT-NOTE: SDL_SYS_DelayNS（unix、HAVE_NANOSLEEP の枝）。nanosleep を呼び、
  シグナルで割り込まれたら（EINTR）残りを寝直す。EINTR 以外の失敗では止める。
  FpNanoSleep は生のシステムコールで、失敗は -1 とエラー番号（fpgeterrno）で返る。 }
procedure PMLDelayNS(ANs: UInt64);
var
  Req, Rem: TTimeSpec;
  Failed: LongInt;
begin
  Rem.tv_sec := TTime(ANs div PML_NS_PER_SECOND);
  Rem.tv_nsec := clong(ANs mod PML_NS_PER_SECOND);
  repeat
    Req.tv_sec := Rem.tv_sec;
    Req.tv_nsec := Rem.tv_nsec;
    Failed := FpNanoSleep(@Req, @Rem);
  until (Failed = 0) or (fpgeterrno <> ESysEINTR);
end;

{ PORT-NOTE: SDL_Delay。ms から ns への換算は UInt64 で行い、大きな値でも溢れない。 }
procedure PMLDelay(AMs: LongWord);
begin
  PMLDelayNS(UInt64(AMs) * PML_NS_PER_MS);
end;

{ PORT-NOTE: SDL_CPUPauseInstruction は x86 の pause 命令（空回りの間、CPU に
  「待っている」と知らせて電力と相方のハイパースレッドへの負担を減らす）。
  x86 以外の CPU では何もしない（SDL は ARM では yield 等を使うが、初回の
  対象は x86_64 のみ）。FPC のアセンブラは mnemonic `pause` を受け付ける（`db` は不可）。 }
procedure PMLCpuPause;
begin
{$IF DEFINED(CPUX86_64) OR DEFINED(CPUI386)}
  asm
    pause
  end;
{$ENDIF}
end;

procedure PMLDelayPrecise(ANs: UInt64);
begin
  PMLDelayPreciseWith(ANs, @PMLNowNS, @PMLDelayNS, @PMLCpuPause);
end;

{ PORT-NOTE: SDL_DelayPrecise。時計・眠り・空回りを引数で受ける以外は同じ手順。
  符号なしの引き算が負にならないよう、SDL の条件の順序と守りをそのまま残す。 }
procedure PMLDelayPreciseWith(ANs: UInt64; ANow: TPMLNowFunc;
  ASleep: TPMLSleepProc; APause: TPMLPauseProc);
const
  // 実際に眠ることが全プラットフォームで保証される最小の長さとして 1 ms を使う。
  SHORT_SLEEP_NS = PML_NS_PER_MS;
var
  CurrentValue, TargetValue, MaxSleepNS, Now_, NextSleepNS, DelayNS: UInt64;
begin
  CurrentValue := ANow();
  TargetValue := CurrentValue + ANs;

  // まず 1 ms ずつ眠って目標の手前まで進む。眠りが 1 ms より短くても
  // 後ろの処理で吸収できる（実際にはそうならない）。
  // MaxSleepNS は観測した 1 回の眠りの最大の長さ（常に 1 ms 以上）。
  MaxSleepNS := SHORT_SLEEP_NS;
  while ((CurrentValue + MaxSleepNS) < TargetValue) do
  begin
    ASleep(SHORT_SLEEP_NS);
    Now_ := ANow();
    NextSleepNS := Now_ - CurrentValue;
    if (NextSleepNS > MaxSleepNS) then
      MaxSleepNS := NextSleepNS;
    CurrentValue := Now_;
  end;

  // 残りから「1 ms の眠りで遅れた最大量」を引いた長さを、もう一度眠る。
  // MaxSleepNS は 1 ms 以上なので 1 ms を引けば遅れた量になる（遅れが無ければ 0）。
  // 最大の遅れを引くので、ここで目標を越えにくい。
  // 少なくとも 1 回は眠るので、精度の下限は PMLDelayNS の精度になる。
  if (CurrentValue < TargetValue) and
     ((TargetValue - CurrentValue) > (MaxSleepNS - SHORT_SLEEP_NS)) then
  begin
    DelayNS := (TargetValue - CurrentValue) - (MaxSleepNS - SHORT_SLEEP_NS);
    ASleep(DelayNS);
    CurrentValue := ANow();
  end;

  // ここでは目標に少し届いていないはずだが、数 ms 足りないこともある
  // （上の眠りが飛ばされた、または短く眠った場合）。その分を空回りすると
  // CPU を使いすぎるので、目標を越える恐れを受け入れて 1 ms ずつ眠る。
  while ((CurrentValue + SHORT_SLEEP_NS) < TargetValue) do
  begin
    ASleep(SHORT_SLEEP_NS);
    CurrentValue := ANow();
  end;

  // 残りの端数は空回りで待つ。
  while (CurrentValue < TargetValue) do
  begin
    APause();
    CurrentValue := ANow();
  end;
end;

{ ---- タイマー（SDL_timer.c の非 Emscripten の枝）---- }

var
  // タイマーの番号の次の値（プロセスに 1 つ。SDL_GetNextObjectID の相当）。
  GTimerNextID: LongInt = 0;

{ PORT-NOTE: SDL_GetNextObjectID。0 は「無い」なので飛ばす。番号は 2^32 回目で一周する
  （SDL と同じ。それまで再利用しない）。 }
function NextTimerID: TPMLTimerID;
begin
  repeat
    Result := TPMLTimerID(LongWord(InterLockedIncrement(GTimerNextID)));
  until Result <> 0;
end;

{ 足し算が UInt64 を溢れたら最大値で止める。 }
function SaturatedAdd(A, B: UInt64): UInt64;
begin
  if B > High(UInt64) - A then
    Result := High(UInt64)
  else
    Result := A + B;
end;

type
  { SDL_Timer。次の予定（Scheduled）と今の間隔は、タイマーのスレッドだけが書く。
    Cancelled は TPMLTimerCore の FLock の下で読み書きする。
    PORT-NOTE: SDL は SDL_TimerMap（番号から引く表）を別に持ち、止まったタイマーの
    表の項目は RemoveTimer が呼ばれるまで残る。ここでは全タイマーの 1 本の列（FAll）に
    まとめ、止まったらスレッドが列から外して解放する（RemoveTimer を呼ばなくても漏れない）。 }
  TPMLTimerEntry = class
  public
    ID         : TPMLTimerID;
    CallbackMS : TPMLTimerCallback;
    CallbackNS : TPMLTimerCallbackNS;
    IntervalNS : UInt64;
    Scheduled  : UInt64;
    Cancelled  : Boolean;
  end;

  TPMLTimerCore = class;

  TPMLTimerThread = class(TPMLThread)
  strict private
    FCore: TPMLTimerCore;
  protected
    function Run: Integer; override;
  public
    constructor CreateFor(ACore: TPMLTimerCore);
  end;

  { TPMLTimerQueue の中身（SDL_TimerData）。

    WHAT:
      1 本のスレッドが期限順の列（FSorted。このスレッドだけが触る）から期限の来た
      タイマーを呼ぶ。他のスレッドは Add で FPending に積み、セマフォで起こす。
      スレッドは回るたびに FPending を FSorted へ並べ入れる。

    WHY:
      コールバックを呼ぶ間は FLock を持たない。持ったままだと、コールバックの中からの
      Add / Remove（タイマーのスレッド自身）が止まり、長いコールバックの間は他のスレッドの
      Add / Remove も止まる。

    RESOLVED:
      - コールバックの中からの Add / Remove: FLock は呼ぶ前に外してあり、ミューテックスは
        再帰もできる。Add はセマフォを足すだけ、Remove は印を付けるだけなので待たない
      - Remove と呼び出しの競合: 呼ぶかどうかの決定（印と FStopping を読む）は FLock の下で、
        呼んだ後にも印を読み直す。Remove が True を返したあとに「新しく」始まる呼び出しは
        無い。ただし、決定が済んで呼び出しが始まるまでの間に Remove が割り込むと、その
        1 回は走る（SDL も同じ。呼んでいる最中の呼び出しは最後まで走る約束と同じ扱い）
      - 破棄と実行中のコールバック: 破棄は FStopping を立ててから、スレッドを待つ（WaitFor）。
        スレッドは次の呼び出しの決定で FStopping を見て抜けるので、走っている 1 回が
        終わったあとはもう呼ばない
      - 項目の解放はタイマーのスレッドだけが行う（FAll から外してから）。Remove は
        FLock の下で FAll を探すので、解放済みの項目には触れない }
  TPMLTimerCore = class
  strict private
    FLock     : TPMLMutex;
    FSem      : TPMLSemaphore;
    FThread   : TPMLTimerThread;
    FAll      : TFPList;      // 生きているタイマー全部（FLock の下）
    FPending  : TFPList;      // Add されて、まだ列に入っていないもの（FLock の下）
    FSorted   : TFPList;      // 期限順の列（タイマーのスレッドだけ）
    FStopping : Boolean;      // FLock の下
    FErrors   : Integer;      // FLock の下
    FLastError: String;       // FLock の下
    procedure InsertSorted(AEntry: TPMLTimerEntry);
    function  InvokeCallback(AEntry: TPMLTimerEntry): UInt64;
    procedure Retire(AEntry: TPMLTimerEntry);
    procedure RecordError(AObject: TObject);
    function  CreateTimer(AIntervalNS: UInt64; AMS: TPMLTimerCallback;
      ANS: TPMLTimerCallbackNS): TPMLTimerID;
  public
    constructor Create;
    destructor Destroy; override;
    function  AddMS(AIntervalMs: LongWord; ACallback: TPMLTimerCallback): TPMLTimerID;
    function  AddNS(AIntervalNS: UInt64; ACallback: TPMLTimerCallbackNS): TPMLTimerID;
    function  Remove(AID: TPMLTimerID): Boolean;
    function  LastError: String;
    function  ErrorCount: Integer;
    function  ThreadStarted: Boolean;
    // タイマーのスレッドの本体（SDL_TimerThread）。
    procedure RunLoop;
  end;

constructor TPMLTimerThread.CreateFor(ACore: TPMLTimerCore);
begin
  FCore := ACore;
  inherited Create('papimela-timer');
end;

function TPMLTimerThread.Run: Integer;
begin
  FCore.RunLoop;
  Result := 0;
end;

constructor TPMLTimerCore.Create;
begin
  inherited Create;
  FLock := TPMLMutex.Create;
  FSem := TPMLSemaphore.Create(0);
  FAll := TFPList.Create;
  FPending := TFPList.Create;
  FSorted := TFPList.Create;
end;

{ PORT-NOTE: SDL_QuitTimers。active を落とし、セマフォで起こして、スレッドを待つ。
  papimela の足した約束: 待つ間に走っているコールバックは最後まで走り、その後は
  どのコールバックも呼ばれない（呼ぶかどうかの決定が FStopping を見る）。
  コールバックの中（タイマーのスレッド自身）からは待てないので、何も壊さずに
  EPMLThreadError を返す。 }
destructor TPMLTimerCore.Destroy;
var
  I: Integer;
begin
  if Assigned(FThread) then
  begin
    if GetCurrentThreadID = FThread.ThreadID then
      raise EPMLThreadError.Create(
        'a timer queue cannot be freed from inside one of its own callbacks');
    FLock.Lock;
    try
      FStopping := True;
    finally
      FLock.Unlock;
    end;
    FSem.Signal;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  // スレッドは終わっているので、残った項目は全部ここで解放する。
  for I := 0 to FAll.Count - 1 do
    TPMLTimerEntry(FAll[I]).Free;
  FreeAndNil(FAll);
  FreeAndNil(FPending);
  FreeAndNil(FSorted);
  FreeAndNil(FSem);
  FreeAndNil(FLock);
  inherited Destroy;
end;

{ PORT-NOTE: SDL_AddTimerInternal。同じ予定の時刻なら後から来たものを後ろに置く。 }
procedure TPMLTimerCore.InsertSorted(AEntry: TPMLTimerEntry);
var
  I: Integer;
begin
  I := 0;
  while (I < FSorted.Count) and
        (TPMLTimerEntry(FSorted[I]).Scheduled <= AEntry.Scheduled) do
    Inc(I);
  FSorted.Insert(I, AEntry);
end;

{ PORT-NOTE: SDL_CreateTimer。SDL は止まった項目の使い回し（freelist）をするが、
  使い回しのための SDL_RemoveTimer の呼び出しごと移植しない（項目は毎回作って捨てる）。
  papimela の足した約束: コールバックが nil なら EPMLArgument（SDL は SDL_InvalidParamError
  で 0 を返す）。スレッドを立てられなければ EPMLThreadError。 }
function TPMLTimerCore.CreateTimer(AIntervalNS: UInt64; AMS: TPMLTimerCallback;
  ANS: TPMLTimerCallbackNS): TPMLTimerID;
var
  Entry: TPMLTimerEntry;
begin
  if not (Assigned(AMS) or Assigned(ANS)) then
    raise EPMLArgument.Create('timer callback must not be nil');
  Entry := TPMLTimerEntry.Create;
  try
    Entry.ID := NextTimerID;
    Entry.CallbackMS := AMS;
    Entry.CallbackNS := ANS;
    Entry.IntervalNS := AIntervalNS;
    // PORT-NOTE: 予定の時刻が UInt64 を溢れるほど長い間隔は、SDL では溢れて「すぐ」
    // になる。ここでは最大値で止め、事実上いつまでも来ない（スレッドはそれを待たない）。
    Entry.Scheduled := SaturatedAdd(PMLNowNS, AIntervalNS);
    Result := Entry.ID;
    FLock.Lock;
    try
      // SDL_InitTimers の相当: 最初の Add でスレッドを立てる。失敗は例外で、
      // 項目はまだ列に入っていないので何も残らない。
      if not Assigned(FThread) then
        FThread := TPMLTimerThread.CreateFor(Self);
      FAll.Add(Entry);
      FPending.Add(Entry);
      Entry := nil;   // 持ち主は列に移った
    finally
      FLock.Unlock;
    end;
  finally
    Entry.Free;
  end;
  FSem.Signal;
end;

function TPMLTimerCore.AddMS(AIntervalMs: LongWord; ACallback: TPMLTimerCallback): TPMLTimerID;
begin
  Result := CreateTimer(UInt64(AIntervalMs) * PML_NS_PER_MS, ACallback, nil);
end;

function TPMLTimerCore.AddNS(AIntervalNS: UInt64; ACallback: TPMLTimerCallbackNS): TPMLTimerID;
begin
  Result := CreateTimer(AIntervalNS, nil, ACallback);
end;

{ PORT-NOTE: SDL_RemoveTimer。印を付けるだけ。印が付いたタイマーは、もう呼ばれない
  （呼んでいる最中の 1 回を除く）。SDL は止まったタイマーの項目を RemoveTimer まで
  残すが、ここでは止まった時点で消えるので、止まったタイマーは「見つからない」になる
  （SDL でも False）。 }
function TPMLTimerCore.Remove(AID: TPMLTimerID): Boolean;
var
  I: Integer;
  Entry: TPMLTimerEntry;
begin
  Result := False;
  if AID = 0 then
    Exit;
  FLock.Lock;
  try
    for I := 0 to FAll.Count - 1 do
    begin
      Entry := TPMLTimerEntry(FAll[I]);
      if Entry.ID = AID then
      begin
        if not Entry.Cancelled then
        begin
          Entry.Cancelled := True;
          Result := True;
        end;
        Break;
      end;
    end;
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLTimerCore.RecordError(AObject: TObject);
var
  Msg: String;
begin
  if AObject is Exception then
    Msg := Exception(AObject).ClassName + ': ' + Exception(AObject).Message
  else
    Msg := AObject.ClassName;
  FLock.Lock;
  try
    Inc(FErrors);
    FLastError := Msg;
  finally
    FLock.Unlock;
  end;
end;

function TPMLTimerCore.LastError: String;
begin
  FLock.Lock;
  try
    Result := FLastError;
  finally
    FLock.Unlock;
  end;
end;

function TPMLTimerCore.ErrorCount: Integer;
begin
  FLock.Lock;
  try
    Result := FErrors;
  finally
    FLock.Unlock;
  end;
end;

function TPMLTimerCore.ThreadStarted: Boolean;
begin
  FLock.Lock;
  try
    Result := Assigned(FThread);
  finally
    FLock.Unlock;
  end;
end;

{ コールバックを呼んで、次の間隔（ナノ秒。0 なら止める）を返す。
  papimela の足した約束: 例外を出したら 0 を返したのと同じに扱い、数と文言を残す
  （スレッドは止めない）。FLock は持っていない。 }
function TPMLTimerCore.InvokeCallback(AEntry: TPMLTimerEntry): UInt64;
begin
  try
    if Assigned(AEntry.CallbackMS) then
      // SDL: SDL_MS_TO_NS(callback_ms(..., (Uint32)SDL_NS_TO_MS(interval)))
      Result := UInt64(AEntry.CallbackMS(AEntry.ID,
        LongWord(AEntry.IntervalNS div PML_NS_PER_MS))) * PML_NS_PER_MS
    else
      Result := AEntry.CallbackNS(AEntry.ID, AEntry.IntervalNS);
  except
    on E: TObject do
    begin
      Result := 0;
      RecordError(E);
    end;
  end;
end;

procedure TPMLTimerCore.Retire(AEntry: TPMLTimerEntry);
begin
  FLock.Lock;
  try
    FAll.Remove(AEntry);
  finally
    FLock.Unlock;
  end;
  AEntry.Free;
end;

{ PORT-NOTE: SDL_TimerThread。手順は SDL と同じ
    1. 他のスレッドが足したタイマーを列に並べ入れる
    2. 期限の来たものを呼ぶ
    3. 次の期限か、新しいタイマーが来るまで待つ
  差分:
    - SDL はスピンロック 1 つで pending / freelist を守る。ここは TPMLMutex
    - active の確認は pending の取り込みのときに加えて、呼ぶかどうかの決定のたびに行う
      （破棄の後にコールバックを呼ばないため）
    - 呼んだ直後にも印を見て、Remove された（コールバックの中からを含む）タイマーは
      次の期限を待たずにその場で捨てる（SDL は戻り値の間隔で入れ直し、次に取り出した
      ときに捨てる。観測できる違いは、解放の早さだけ）
  次の予定は「この周回で時刻を読んだとき（tick）+ 戻り値」で、SDL と同じ。 }
procedure TPMLTimerCore.RunLoop;
var
  I: Integer;
  Entry: TPMLTimerEntry;
  Tick, Now_, Delay, Interval: UInt64;
  Stop, Skip: Boolean;
  WaitNS: Int64;
begin
  repeat
    // 1. 他のスレッドが足したタイマーを列に並べ入れる（FStopping もここで読む）
    FLock.Lock;
    try
      for I := 0 to FPending.Count - 1 do
        InsertSorted(TPMLTimerEntry(FPending[I]));
      FPending.Clear;
      Stop := FStopping;
    finally
      FLock.Unlock;
    end;
    if Stop then
      Exit;

    // タイマーが無ければ、いつまでも待つ。
    Delay := High(UInt64);
    Tick := PMLNowNS;

    // 2. この周回で期限の来たものを呼ぶ
    while FSorted.Count > 0 do
    begin
      Entry := TPMLTimerEntry(FSorted[0]);
      if Tick < Entry.Scheduled then
      begin
        // 先の予定。待つ長さを決めて抜ける。
        Delay := Entry.Scheduled - Tick;
        Break;
      end;

      // 呼ぶかどうかの決定。破棄が始まっていたら、ここで抜ける（以後は呼ばない）。
      FLock.Lock;
      try
        Stop := FStopping;
        Skip := Entry.Cancelled;
      finally
        FLock.Unlock;
      end;
      if Stop then
        Exit;

      FSorted.Delete(0);
      if Skip then
        Interval := 0
      else
        Interval := InvokeCallback(Entry);

      if Interval > 0 then
      begin
        // 呼んでいる間に Remove されたら（自分自身を含む）、入れ直さずに捨てる。
        FLock.Lock;
        try
          if Entry.Cancelled then
            Interval := 0;
        finally
          FLock.Unlock;
        end;
      end;

      if Interval > 0 then
      begin
        Entry.IntervalNS := Interval;
        Entry.Scheduled := SaturatedAdd(Tick, Interval);
        InsertSorted(Entry);
      end
      else
        Retire(Entry);
    end;

    // 3. 次の期限まで、または新しいタイマーが来るまで待つ。処理に使った時間は引く。
    Now_ := PMLNowNS;
    if Delay <> High(UInt64) then
    begin
      if (Now_ - Tick) > Delay then
        Delay := 0
      else
        Delay := Delay - (Now_ - Tick);
    end;
    // Int64 に入らない長さは「いつまでも」（負の値）として渡す。
    if Delay >= UInt64(High(Int64)) then
      WaitNS := -1
    else
      WaitNS := Int64(Delay);
    // Add のたびにセマフォが足されるので、すぐ戻って余分に 1 周するだけで害は無い。
    FSem.WaitTimeoutNS(WaitNS);
  until False;
end;

{ ---- TPMLTimerQueue（公開の面。中身は TPMLTimerCore） ---- }

constructor TPMLTimerQueue.Create;
begin
  inherited Create;
  FImpl := TPMLTimerCore.Create;
end;

destructor TPMLTimerQueue.Destroy;
begin
  // FreeAndNil は先に nil にするので使わない。コールバックの中から呼ばれて中身の破棄が
  // 断られたとき（EPMLThreadError）、FImpl は生きたまま残す。
  FImpl.Free;
  FImpl := nil;
  inherited Destroy;
end;

function TPMLTimerQueue.Add(AIntervalMs: LongWord; ACallback: TPMLTimerCallback): TPMLTimerID;
begin
  Result := TPMLTimerCore(FImpl).AddMS(AIntervalMs, ACallback);
end;

function TPMLTimerQueue.AddNS(AIntervalNS: UInt64; ACallback: TPMLTimerCallbackNS): TPMLTimerID;
begin
  Result := TPMLTimerCore(FImpl).AddNS(AIntervalNS, ACallback);
end;

function TPMLTimerQueue.Remove(AID: TPMLTimerID): Boolean;
begin
  Result := TPMLTimerCore(FImpl).Remove(AID);
end;

function TPMLTimerQueue.LastCallbackError: String;
begin
  Result := TPMLTimerCore(FImpl).LastError;
end;

function TPMLTimerQueue.GetCallbackErrors: Integer;
begin
  Result := TPMLTimerCore(FImpl).ErrorCount;
end;

function TPMLTimerQueue.GetThreadStarted: Boolean;
begin
  Result := TPMLTimerCore(FImpl).ThreadStarted;
end;

end.
