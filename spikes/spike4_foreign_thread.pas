{
  spike4_foreign_thread — C が作ったスレッドから FPC のコードを呼ぶ（PipeWire の呼び出しと同じ形）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    pthread_create で直に作ったスレッド（FPC の TThread を通らない）で、
    1. 入口の浮動小数点の例外の設定を読み、文字列・例外・threadvar を使った後にもう一度読む
    2. 入口で例外を止めてから同じことをし、溢れが例外にならないか
    を確かめる。結果は spikes/RESULTS.md のスパイク 4。

  WHY:
    PipeWire は自分のスレッド（pw_thread_loop、実時間のデータのスレッド）から呼び出しを返す。
    C のスレッドは作ったスレッドの浮動小数点の設定を受け継ぐ。PipeWire のスレッドは papimela の
    メインスレッド（FPC。例外が有効）から pw_thread_loop_start で作られるので、例外が有効なまま
    PipeWire の中を走る（C は無効が前提）。PipeWire のバックエンドの入口の決まりを決めるための実測。
}
program spike4_foreign_thread;

{$mode objfpc}{$H+}

uses
  cthreads, SysUtils, Math, ctypes;

type
  TStart = function(Arg: Pointer): Pointer; cdecl;

function pthread_create(AThread: Pointer; AAttr: Pointer; AStart: TStart; AArg: Pointer): cint; cdecl;
  external 'c';
function pthread_join(AThread: PtrUInt; ARet: Pointer): cint; cdecl; external 'c';

threadvar
  Counter: Integer;

var
  Report: String;

function MaskText: String;
begin
  Result := IntToStr(Integer(LongWord(GetExceptionMask)));
end;

// 文字列・例外・threadvar を使い、最後に溢れる計算をする。
procedure Work(const ALabel: String);
var
  S: String;
  X, Y: Double;
begin
  Inc(Counter);
  try
    S := Format('%d-%s', [Counter, StringOfChar('x', 100)]);
    raise Exception.Create('boom');
  except
    on E: Exception do
      Report := Report + Format('%s: 捕まえた %s（%d 文字）、', [ALabel, E.Message, Length(S)]);
  end;
  Report := Report + ALabel + ': 使った後の例外の設定 ' + MaskText + '、';
  X := 1e308;
  try
    Y := X * 10;
    Report := Report + ALabel + ': 溢れは ' + FloatToStr(Y) + LineEnding;
  except
    on E: Exception do
      Report := Report + ALabel + ': 溢れが例外になった（' + E.ClassName + '）' + LineEnding;
  end;
end;

function Plain(AArg: Pointer): Pointer; cdecl;
begin
  Report := Report + '入口の例外の設定 ' + MaskText + '、';
  Work('そのまま');
  Result := nil;
end;

function Masked(AArg: Pointer): Pointer; cdecl;
begin
  // PipeWire のバックエンドの入口（PMLPipeWireCallbackEnter）と同じ。
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  Work('入口で止めた');
  Work('入口で止めた（2 回目）');
  Result := nil;
end;

var
  T: PtrUInt;
begin
  WriteLn('メインスレッドの例外の設定: ', MaskText, '（63 = 全部止めている）');
  Report := '';
  if pthread_create(@T, nil, @Plain, nil) = 0 then
    pthread_join(T, nil);
  if pthread_create(@T, nil, @Masked, nil) = 0 then
    pthread_join(T, nil);
  Write(Report);
end.
