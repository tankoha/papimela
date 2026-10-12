{
  PaPiMeLa.Events.Quit — Quit を出す規則（シグナル、最後のウィンドウ）とイベントのログの絞り方

  Origin : partially ported from SDL (src/events/SDL_quit.c, src/events/SDL_windowevents.c,
           src/events/SDL_events.c)
           Scope: SIGINT / SIGTERM を Quit にする手順（既定の動作のときだけ手続きを置き、
           手続きの中では印を付けるだけにして、次の Pump で Quit を出す）と、外すときに自分の
           手続きのときだけ戻すこと（SDL_quit.c）。閉じる要求が最後のウィンドウのものか
           の数え方（SDL_windowevents.c）。SDL_HINT_EVENT_LOGGING の値の読み方と、
           動きの多いイベントを 2 未満では出さないこと（SDL_events.c）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #72

  WHAT:
    PaPiMeLa.Events（クリーンルーム）、PaPiMeLa.Video（クリーンルーム）、PaPiMeLa.Core が
    呼ぶ、SDL のソースを読んで写した小さな規則。

  WHY:
    クリーンルームのユニットに SDL から写した部分を混ぜないため、ユニットを分けた
    （PaPiMeLa.Events.Drop と同じ）。

  RESOLVED:
    - シグナルの手続きはプロセスに 1 つ。Context ごとに数え、最後の Context が外すときに
      戻す。手続きは世代の数を 1 つ進めるだけで、各 Context のイベントのキューが自分の
      見た世代と比べて Quit を出す（SDL は Context が 1 つなので印 1 つで足りる）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Events.Quit;

{$I papimela.inc}

interface

uses
  PaPiMeLa.Events;

{ SIGINT と SIGTERM の手続きを置く（SDL_QuitInit_Internal）。今の手続きが既定（SIG_DFL）の
  シグナルにだけ置く（アプリが自分の手続きを置いていれば触らない）。呼んだ回数を数える。 }
procedure PMLInstallQuitSignals;
{ PMLInstallQuitSignals を 1 回取り消す。数が 0 になったら、今の手続きが自分のものである
  シグナルだけ既定に戻す（SDL_QuitQuit_Internal）。 }
procedure PMLRemoveQuitSignals;
{ SIGINT か SIGTERM を受けた回数（世代）。手続きの中で不可分に 1 つ進める。イベントの
  キューは作ったときの値を覚え、Pump のたびに比べて、変わっていれば Quit を出す。 }
function PMLQuitSignalGeneration: LongWord;

{ 閉じる要求が来たとき Quit も出すか（SDL_SendWindowEvent の WINDOW_CLOSE_REQUESTED の節）。
  AVisibleWindows は、隠れていない（Hidden でない）ウィンドウの数。閉じる要求の来た
  ウィンドウも、隠れていなければ数に入れる。1 以下なら最後のウィンドウ。 }
function PMLCloseRequestIsLastWindow(AVisibleWindows: Integer): Boolean;

{ ヒント PAPIMELA_EVENT_LOGGING の値（SDL_EventLoggingChanged）。空なら 0。数字として
  読み（C の atoi）、0..3 に収める。 }
function PMLEventLoggingVerbosity(const AHint: String): Integer;
{ AVerbosity のときにこの種類のイベントをログに出すか（SDL_LogEvent）。0 なら出さない。
  2 未満では、動きの多いもの（マウス・指・ペンの移動、ペンの軸、ピンチの途中、
  ゲームパッド・ジョイスティックの軸と更新の終わり、センサー）を出さない。 }
function PMLEventLogged(AKind: TPMLEventKind; AVerbosity: Integer): Boolean;

implementation

uses
  SysUtils, BaseUnix;

var
  GLock      : TRTLCriticalSection;   // GRefCount の更新を守る（Context はどのスレッドからも作れる）
  GRefCount  : Integer = 0;           // PMLInstallQuitSignals の回数から PMLRemoveQuitSignals の回数を引いたもの
  GGeneration: LongInt = 0;           // 手続きの中で不可分に進める。LongInt なのは InterLockedIncrement の型

{ シグナルの手続き（SDL_HandleSIG）。シグナルの中では確保も鍵も使えないので、
  数を 1 つ進めるだけにする。Quit を積むのは次の Pump（SDL_SendPendingSignalEvents）。 }
procedure HandleQuitSignal(ASig: cint); cdecl;
begin
  InterLockedIncrement(GGeneration);
end;

// 今の手続きを読む。読めなければ nil。
function CurrentHandler(ASig: cint): Pointer;
var
  Act: SigActionRec;
begin
  FillChar(Act, SizeOf(Act), 0);
  if FpSigAction(ASig, nil, @Act) <> 0 then
    Exit(nil);
  Result := Pointer(Act.sa_handler);
end;

// SDL_EventSignal_Init。今の手続きが既定のときだけ置く。
procedure InstallOne(ASig: cint);
var
  Act: SigActionRec;
begin
  if CurrentHandler(ASig) <> Pointer(SIG_DFL) then
    Exit;
  FillChar(Act, SizeOf(Act), 0);
  Act.sa_handler := SigActionHandler(@HandleQuitSignal);
  FpSigAction(ASig, @Act, nil);
end;

// SDL_EventSignal_Quit。今の手続きが自分のものなら既定に戻す。
procedure RemoveOne(ASig: cint);
var
  Act: SigActionRec;
begin
  if CurrentHandler(ASig) <> Pointer(@HandleQuitSignal) then
    Exit;
  FillChar(Act, SizeOf(Act), 0);
  Act.sa_handler := SigActionHandler(SIG_DFL);
  FpSigAction(ASig, @Act, nil);
end;

procedure PMLInstallQuitSignals;
begin
  EnterCriticalSection(GLock);
  try
    // PORT-NOTE(SDL_QuitInit_Internal): SDL は Context が 1 つなので数えない。
    // papimela は Context を複数作れるので、最初の 1 回だけ置く。
    if GRefCount = 0 then
    begin
      InstallOne(SIGINT);
      InstallOne(SIGTERM);
    end;
    Inc(GRefCount);
  finally
    LeaveCriticalSection(GLock);
  end;
end;

procedure PMLRemoveQuitSignals;
begin
  EnterCriticalSection(GLock);
  try
    if GRefCount <= 0 then
      Exit;
    Dec(GRefCount);
    if GRefCount = 0 then
    begin
      RemoveOne(SIGINT);
      RemoveOne(SIGTERM);
    end;
  finally
    LeaveCriticalSection(GLock);
  end;
end;

function PMLQuitSignalGeneration: LongWord;
begin
  Result := LongWord(GGeneration);
end;

function PMLCloseRequestIsLastWindow(AVisibleWindows: Integer): Boolean;
begin
  Result := (AVisibleWindows <= 1);
end;

function PMLEventLoggingVerbosity(const AHint: String): Integer;
var
  I, Sign: Integer;
  V: Int64;
begin
  if AHint = '' then
    Exit(0);
  // SDL_atoi: 先頭の空白を飛ばし、符号があれば読み、数字を読めるだけ読む。
  I := 1;
  while (I <= Length(AHint)) and (AHint[I] in [' ', #9, #10, #11, #12, #13]) do
    Inc(I);
  Sign := 1;
  if (I <= Length(AHint)) and (AHint[I] in ['+', '-']) then
  begin
    if AHint[I] = '-' then
      Sign := -1;
    Inc(I);
  end;
  V := 0;
  while (I <= Length(AHint)) and (AHint[I] in ['0'..'9']) do
  begin
    // 3 を超えれば同じ結果なので、桁あふれしないよう途中で止める。
    if V < 1000 then
      V := V * 10 + (Ord(AHint[I]) - Ord('0'));
    Inc(I);
  end;
  V := V * Sign;
  if V < 0 then
    V := 0
  else if V > 3 then
    V := 3;
  Result := Integer(V);
end;

function PMLEventLogged(AKind: TPMLEventKind; AVerbosity: Integer): Boolean;
begin
  if AVerbosity <= 0 then
    Exit(False);
  // 動きの多いものは 2 以上のときだけ出す。SDL にあって papimela の列挙に無い種類
  // （ペン、ピンチ、ゲームパッドのタッチパッドとセンサー、更新の終わり、センサー）は、
  // 列挙に加えるときにここへも足す。
  if AVerbosity < 2 then
    Result := not (AKind in [
      TPMLEventKind.MouseMotion, TPMLEventKind.FingerMotion,
      TPMLEventKind.GamepadAxisMotion, TPMLEventKind.JoystickAxisMotion])
  else
    Result := True;
end;

initialization
  InitCriticalSection(GLock);

finalization
  DoneCriticalSection(GLock);

end.
