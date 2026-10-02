{
  PaPiMeLa.Time — 待つ（Delay / DelayNS / DelayPrecise）

  Origin : ported from SDL (src/timer/SDL_timer.c, src/timer/unix/SDL_systimer.c)
           Scope: SDL_Delay / SDL_DelayNS / SDL_DelayPrecise と、その下の
           SDL_SYS_DelayNS（nanosleep を割り込まれたら残りを寝直す）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4（TPMLTimerService の行）、§11 #9

  WHAT:
    今のスレッドを指定した時間だけ止める。
      PMLDelay        ミリ秒
      PMLDelayNS      ナノ秒。精度は OS の眠りの精度（Linux ではふつう 0.1 ms 未満の遅れ）
      PMLDelayPrecise ナノ秒。1 ms ずつ眠って遅れの最大を測り、残りを短く眠ってから
                      最後の端数だけ空回りで待つ。早く戻らず、遅れも小さい

  WHY:
    VSync が効かない環境で、アプリのループが CPU を使い切らないように（F-6）。
    Context は要らない（SDL_Delay も初期化なしで呼べる）。Context.Timer からも
    同じものを呼べる（TPMLTimerService.Delay など）。

    DelayPrecise の手順は、時計と眠りと空回りを引数で受け取る
    PMLDelayPreciseWith に置く。本物の時計では手順の正しさを決定的に検査
    できないので、検査は偽の時計を渡して眠りの列を比べる。

  NOT RESOLVED:
    - タイマー（AddTimer / RemoveTimer）とタイマースレッドは #8 Threading の後
    - 時計は PaPiMeLa.Events の PMLNowNS（CLOCK_MONOTONIC）をそのまま使う。
      SDL_GetTicksNS は初期化からの経過時間だが、papimela の TicksNS は
      単調時計の生の値（既存の契約のまま）

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

implementation

uses
  BaseUnix, UnixType,
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

end.
