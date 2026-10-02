{
  demo_japanese_input — 実キーボードで日本語入力を確認する対話デモ

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    ウィンドウを開き、実際の wl_keyboard から届くキーを IME に通して、
    変換中テキストと確定文字列を標準出力へ表示する。

  WHY:
    test_key_routing は合成キーで §7.5 の経路を検証するが、wl_keyboard から
    実際にキーが届くところは検証できない（コンポジタへキーを注入できないため）。
    ここは人が触って確かめる。

  使い方:
    ./test/demo_japanese_input [秒数]        既定は 30 秒

    ウィンドウをクリックしてフォーカスし、日本語を入力する。
    ウィンドウの色は変換中テキストの有無で変わる（フォント描画は未実装のため）。
    Escape で終了。
}
program demo_japanese_input;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Platform.XKB,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.TextInput,
  PaPiMeLa.Core,
  PaPiMeLa.Backends;   // 実機の Wayland と fcitx を使う（#45 からはアプリが選んでリンクする）

type
  { アプリのテキストバッファ。IME へ周辺テキストを供給する。 }
  TEditor = class(TObject, IPMLTextInputClient)
  strict private
    FBuffer: String;
  public
    function GetSurroundingText(out AText: String;
      out ACursorByte, AAnchorByte: Integer): Boolean;
    function GetCursorRect: TPMLRect;
    procedure Insert(const AText: String);
    procedure DeleteAround(ABefore, AAfter: Integer);
    procedure Backspace;
    property Buffer: String read FBuffer;
  end;

function TEditor.GetSurroundingText(out AText: String;
  out ACursorByte, AAnchorByte: Integer): Boolean;
begin
  AText := FBuffer;
  ACursorByte := Length(FBuffer);
  AAnchorByte := ACursorByte;
  Result := True;
end;

function TEditor.GetCursorRect: TPMLRect;
begin
  Result := TPMLRect.Make(20, 40, 2, 20);
end;

procedure TEditor.Insert(const AText: String);
begin
  FBuffer := FBuffer + AText;
end;

procedure TEditor.DeleteAround(ABefore, AAfter: Integer);
begin
  if ABefore > 0 then
    SetLength(FBuffer, Max(0, Length(FBuffer) - ABefore));
end;

procedure TEditor.Backspace;
var
  I: Integer;
begin
  I := Length(FBuffer);
  if I = 0 then
    Exit;
  // UTF-8 の文字境界まで戻る
  Dec(I);
  while (I > 0) and ((Byte(FBuffer[I + 1]) and $C0) = $80) do
    Dec(I);
  SetLength(FBuffer, I);
end;

var
  Ctx     : TPMLContext;
  Win     : TPMLWindow;
  Editor  : TEditor;
  Session : TPMLTextInputSession;
  Running : Boolean = True;
  Composing: Boolean = False;
  Seconds : Integer = 30;
  KeyCount: Integer = 0;
  GotKeymap: Boolean = False;
  GotFocus : Boolean = False;

procedure Paint;
var
  Pixels: Pointer;
  Pitch, X, Y: Integer;
  Row: PLongWord;
  Base: LongWord;
begin
  if not Win.LockFramebuffer(Pixels, Pitch) then
    Exit;
  // 変換中は青、確定後は緑寄りにする（フォント描画が無いための代用）。
  if Composing then
    Base := $203050
  else
    Base := $203020;
  for Y := 0 to Win.Height - 1 do
  begin
    Row := PLongWord(PByte(Pixels) + PtrUInt(Y) * PtrUInt(Pitch));
    for X := 0 to Win.Width - 1 do
      Row[X] := Base + LongWord((X * 64) div Max(1, Win.Width));
  end;
  Win.UpdateFramebuffer;
end;

procedure ReportComposition(const AEv: TPMLEvent);
var
  I: Integer;
  S: String;
begin
  Composing := AEv.Text <> '';
  if not Composing then
  begin
    WriteLn('  変換中: (なし)');
    Exit;
  end;
  S := '';
  for I := 0 to High(AEv.Segments) do
  begin
    case AEv.Segments[I].State of
      TPMLSegmentState.Focused    : S := S + '[' + AEv.Segments[I].TextOf(AEv.Text) + ']';
      TPMLSegmentState.Converted  : S := S + '<' + AEv.Segments[I].TextOf(AEv.Text) + '>';
      TPMLSegmentState.Unconverted: S := S + AEv.Segments[I].TextOf(AEv.Text);
    end;
  end;
  WriteLn(Format('  変換中: %s   （%d 文節、[ ] が注目）', [S, Length(AEv.Segments)]));
end;

procedure HandleEvents;
var
  Ev: TPMLEvent;
begin
  while Ctx.Events.Poll(Ev) do
    case Ev.Kind of
      TPMLEventKind.KeymapChanged:
        begin
          GotKeymap := True;
          WriteLn('  [INFO] キーマップを受信した');
        end;
      TPMLEventKind.WindowFocusGained:
        begin
          GotFocus := True;
          WriteLn('  [INFO] キーボードフォーカスを取得（IME にも FocusIn を送信）');
        end;
      TPMLEventKind.WindowFocusLost:
        WriteLn('  [INFO] キーボードフォーカスを喪失（IME にも FocusOut を送信）');
      TPMLEventKind.TextEditing:
        ReportComposition(Ev);
      TPMLEventKind.TextInput:
        begin
          Editor.Insert(Ev.Text);
          Composing := False;
          WriteLn(Format('  確定: "%s"  → バッファ: %s', [Ev.Text, Editor.Buffer]));
        end;
      TPMLEventKind.TextInputDeleteSurrounding:
        begin
          Editor.DeleteAround(Ev.DeleteSurrounding.BeforeBytes,
            Ev.DeleteSurrounding.AfterBytes);
          WriteLn('  周辺削除を適用');
        end;
      TPMLEventKind.KeyDown:
        begin
          Inc(KeyCount);
          // IME を素通りしたキー。何が素通りしたのか分かるよう keysym を出す。
          WriteLn(Format('  KeyDown 素通り keysym=$%x keycode=%d',
            [Ev.Key.Keysym, Ev.Key.Raw]));
          case Ev.Key.Keysym of
            XKB_KEY_Escape   : Running := False;
            XKB_KEY_BackSpace: begin Editor.Backspace;
                                 WriteLn('  Backspace → バッファ: ' + Editor.Buffer); end;
          end;
        end;
      TPMLEventKind.MouseButtonDown:
        WriteLn(Format('  マウス ボタン%d (%.0f, %.0f)',
          [Ev.Button.Button, Ev.Button.X, Ev.Button.Y]));
      TPMLEventKind.WindowCloseRequested:
        Running := False;
    end;
end;

var
  Opts    : TPMLWindowOptions;
  Deadline: UInt64;
begin
  if ParamCount >= 1 then
    Seconds := StrToIntDef(ParamStr(1), 30);

  WriteLn('demo_japanese_input — 実キーボードで日本語入力を試す');
  WriteLn;
  WriteLn('  ウィンドウをクリックしてフォーカスし、日本語を入力してください。');
  WriteLn('  変換中は [注目文節] <変換済> 未変換 の形で表示します。');
  WriteLn('  ローマ字を打ったあと Space を押すと漢字変換され、複数文節になります。');
  WriteLn('  例: nihongowomusubu → Space → [日本語を]<結ぶ> のように分かれます。');
  WriteLn(Format('  Escape か閉じるボタンで終了。%d 秒で自動終了します。', [Seconds]));
  WriteLn;

  Editor := TEditor.Create;
  try
    Ctx := TPMLContext.Create([TPMLSubsystem.Video, TPMLSubsystem.TextInput]);
    try
      WriteLn(Format('  ビデオ: %s / IME: %s',
        [Ctx.Video.BackendName, Ctx.TextInput.BackendName]));

      Opts := TPMLWindowOptions.Make('papimela — 日本語入力デモ', 720, 200).Resizable;
      Win := Ctx.Video.CreateWindow(Opts);
      Session := Ctx.TextInput.Start(Win, Editor as IPMLTextInputClient);
      Session.NotifyCursorRectChanged;

      Deadline := Ctx.Timer.TicksNS + UInt64(Seconds) * 1000000000;
      while Running and (Ctx.Timer.TicksNS < Deadline) do
      begin
        Paint;
        Ctx.Events.Pump(16);
        HandleEvents;
      end;

      WriteLn;
      WriteLn('=== 結果 ===');
      WriteLn(Format('  キーマップ受信: %s', [BoolToStr(GotKeymap, True)]));
      WriteLn(Format('  フォーカス取得: %s', [BoolToStr(GotFocus, True)]));
      WriteLn(Format('  IME が消費したキー: %d', [Ctx.Events.Keyboard.ConsumedCount]));
      WriteLn(Format('  IME を素通りした KeyDown: %d', [KeyCount]));
      WriteLn(Format('  最終バッファ: %s', [Editor.Buffer]));
      Win.Free;
    finally
      FreeAndNil(Ctx);
    end;
  finally
    FreeAndNil(Editor);
  end;
end.
