{
  test_wayland_textinput — text-input-v3 のバックエンドを実機のコンポジタで確かめる

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    PAPIMELA_IME を使わずオプションで 'wayland' を選び、ウィンドウにフォーカスが
    来たら enter を受け、セッションを始めると enable を送り、止めると disable を
    送ることを見る。キーを打たないので IME の変換そのものは見ない
    （それは demo_japanese_input を PAPIMELA_IME=wayland で動かして見る）。

  WHY:
    受信側の状態（done の適用順など）は test_textinput_v3 が表示サーバ無しで
    見ている。ここで見るのは、コンポジタとの手順（get_text_input、enter の
    待ち合わせ、enable / disable の時機）が実機で噛み合うこと。

  実行前提: Wayland セッション（text-input-v3 を広告するコンポジタ。labwc で確認）。
            ウィンドウにキーボードのフォーカスが来ること（作ったウィンドウに
            フォーカスを移すコンポジタ）。
}
program test_wayland_textinput;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Time,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland,
  PaPiMeLa.TextInput,
  PaPiMeLa.TextInput.WaylandTI,
  PaPiMeLa.Core;

type
  TEditor = class(TObject, IPMLTextInputClient)
  public
    function GetSurroundingText(out AText: String;
      out ACursorByte, AAnchorByte: Integer): Boolean;
    function GetCursorRect: TPMLRect;
  end;

function TEditor.GetSurroundingText(out AText: String;
  out ACursorByte, AAnchorByte: Integer): Boolean;
begin
  AText := 'これは周辺テキストです';
  ACursorByte := Length(AText);
  AAnchorByte := ACursorByte;
  Result := True;
end;

function TEditor.GetCursorRect: TPMLRect;
begin
  Result := TPMLRect.Make(20, 20, 2, 18);
end;

var
  Failures: Integer = 0;
  Ctx     : TPMLContext;
  Focused : Boolean = False;

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

{ AMs ミリ秒の間イベントを回し、フォーカスの変化を拾う。 }
procedure PumpFor(AMs: Integer);
var
  Ev: TPMLEvent;
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + QWord(AMs);
  repeat
    Ctx.Events.Pump(20);
    while Ctx.Events.Poll(Ev) do
      case Ev.Kind of
        TPMLEventKind.WindowFocusGained: Focused := True;
        TPMLEventKind.WindowFocusLost:   Focused := False;
      end;
  until GetTickCount64 >= Deadline;
end;

var
  Opts: TPMLContextOptions;
  Win : TPMLWindow;
  TI  : TPMLWaylandTextInputBackend;
  Ed  : TEditor;
  I   : Integer;
begin
  WriteLn('test_wayland_textinput — text-input-v3 を実機で');
  WriteLn;
  Opts := TPMLContextOptions.Default;
  Opts.PreferredVideo := 'wayland';
  Opts.PreferredTextInput := 'wayland';
  Ed := TEditor.Create;
  try
    Ctx := TPMLContext.Create([TPMLSubsystem.Video, TPMLSubsystem.TextInput], Opts);
  except
    on E: EPMLError do
    begin
      WriteLn('  [FAIL] ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
  try
    WriteLn('1. 選択');
    Check(Ctx.TextInput.BackendName = 'wayland', 'IME は wayland（text-input-v3）');
    TI := Ctx.TextInput.BackendInstance as TPMLWaylandTextInputBackend;
    Check(not TI.Entered and not TI.Enabled, 'ウィンドウが無い間は enter も enable も無い');

    WriteLn;
    WriteLn('2. ウィンドウにフォーカスが来たら enter を受ける');
    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('text-input-v3', 320, 120));
    for I := 1 to 100 do
    begin
      PumpFor(20);
      if Focused and TI.Entered then
        Break;
    end;
    Check(Focused, 'ウィンドウにフォーカスが来た');
    Check(TI.Entered, 'text-input-v3 の enter を受けた');
    Check(not TI.Enabled, 'セッションを始めるまでは enable しない');

    WriteLn;
    WriteLn('3. セッションを始めると enable、止めると disable');
    Ctx.TextInput.Start(Win, Ed);
    PumpFor(100);
    Check(TI.Enabled, 'Start の後の Pump で enable を送った');
    Ctx.TextInput.Session.NotifyCursorRectChanged;
    PumpFor(100);
    Check(TI.Enabled and TI.Entered, '状態の送り直しで有効のまま（プロトコル違反で切られない）');
    Ctx.TextInput.Stop;
    PumpFor(100);
    Check(not TI.Enabled, 'Stop の後の Pump で disable を送った');
    Check(TI.Entered, 'disable しても enter は残る（フォーカスはそのまま）');

    WriteLn;
    WriteLn('4. もう一度始められる');
    Ctx.TextInput.Start(Win, Ed);
    PumpFor(100);
    Check(TI.Enabled, '2 回目の Start でも enable');
    Ctx.TextInput.Stop;
    PumpFor(50);

    Win.Free;
    PumpFor(100);
    Check(not TI.Entered, 'ウィンドウを消すと leave を受ける');
    Check(Ctx.Events.DroppedCount = 0, 'イベントの取りこぼしなし');
  finally
    Ctx.Free;
    Ed.Free;
  end;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: text-input-v3 の手順が実機のコンポジタと噛み合う ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
