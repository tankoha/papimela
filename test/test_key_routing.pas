{
  test_key_routing — キーイベントの経路と IME フィルタ（設計 §7.5）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    TPMLKeyboardState.SendKey にキーを流し、IME が消費したキーが KeyDown として
    出てこないこと、消費されなかったキーが KeyDown と TextInput になることを
    確認する。

  WHY:
    シート（wl_keyboard）からのキーは必ずこの経路を通る。コンポジタへキーを
    注入する手段が無いので、シートが届けるのと同じ形の合成キーを直接流して
    経路だけを検証する。実際の wl_keyboard 経由の確認は
    test/demo_japanese_input が担当する（対話が必要）。

  実行前提: Wayland セッション、fcitx5 稼働、日本語エンジン（mozc）。
}
program test_key_routing;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Video,
  PaPiMeLa.TextInput,
  PaPiMeLa.Core;

type
  TFakeEditor = class(TObject, IPMLTextInputClient)
  strict private
    FBuffer: String;
  public
    function GetSurroundingText(out AText: String;
      out ACursorByte, AAnchorByte: Integer): Boolean;
    function GetCursorRect: TPMLRect;
    property Buffer: String read FBuffer write FBuffer;
  end;

function TFakeEditor.GetSurroundingText(out AText: String;
  out ACursorByte, AAnchorByte: Integer): Boolean;
begin
  AText := FBuffer;
  ACursorByte := Length(FBuffer);
  AAnchorByte := ACursorByte;
  Result := True;
end;

function TFakeEditor.GetCursorRect: TPMLRect;
begin
  Result := TPMLRect.Make(0, 0, 2, 18);
end;

var
  Ctx      : TPMLContext;
  Editor   : TFakeEditor;
  Failures : Integer = 0;
  KeyDowns : Integer = 0;
  TextInputs: Integer = 0;
  Editings : Integer = 0;
  MaxSegs  : Integer = 0;
  LastCommit: String = '';

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

procedure DrainEvents;
var
  Ev: TPMLEvent;
begin
  while Ctx.Events.Poll(Ev) do
    case Ev.Kind of
      TPMLEventKind.KeyDown:
        Inc(KeyDowns);
      TPMLEventKind.TextEditing:
        begin
          Inc(Editings);
          if Length(Ev.Segments) > MaxSegs then
            MaxSegs := Length(Ev.Segments);
        end;
      TPMLEventKind.TextInput:
        begin
          Inc(TextInputs);
          LastCommit := Ev.Text;
        end;
    end;
end;

// シートが届けるのと同じ形でキーを流す。
procedure SendKey(AKeysym, AEvdevCode: LongWord; const AText: String);
var
  K: TPMLKeyEventData;
begin
  FillChar(K, SizeOf(K), 0);
  K.Keysym := AKeysym;
  K.Raw := AEvdevCode + 8;
  K.Modifiers := [];
  Ctx.Events.Keyboard.SendKey(1, K, True, AText);
  Ctx.Events.Keyboard.SendKey(1, K, False, '');
  Ctx.Events.Pump(30);
  DrainEvents;
end;

const
  // "わたしのなまえ" のローマ字。(keysym, evdev)
  Keys: array[0..13] of array[0..1] of LongWord = (
    ($77, 17), ($61, 30), ($74, 20), ($61, 30), ($73, 31), ($68, 35), ($69, 23),
    ($6E, 49), ($6F, 24), ($6E, 49), ($61, 30), ($6D, 50), ($61, 30), ($65, 18)
  );

var
  I: Integer;
  Session: TPMLTextInputSession;
  ConsumedBefore: Integer;
begin
  WriteLn('test_key_routing — キーの IME 転送経路（設計 §7.5）');
  WriteLn;

  Editor := TFakeEditor.Create;
  Editor.Buffer := 'これは周辺テキストです';
  try
    WriteLn('1. Context 生成（TextInput のみ。ウィンドウは不要）');
    try
      Ctx := TPMLContext.Create([TPMLSubsystem.TextInput]);
    except
      on E: EPMLError do
      begin
        WriteLn('  [FAIL] ', E.Message);
        Halt(1);
      end;
    end;

    try
      Check(Ctx.Events.Keyboard <> nil, 'Events.Keyboard が存在する');
      Check(Ctx.Events.Mouse <> nil, 'Events.Mouse が存在する');
      Check(Ctx.Events.KeyFilter <> nil, 'KeyFilter が差し込まれている');

      WriteLn;
      WriteLn('2. IME セッション開始前はフィルタが働かない');
      Check(not Ctx.Events.KeyFilter.KeyFilterActive,
        'セッション未開始では KeyFilterActive = False');
      SendKey($61, 30, 'a');
      Check(KeyDowns = 1, Format('KeyDown が %d 件（フィルタを通らず素通り）', [KeyDowns]));
      Check(TextInputs = 1, Format('TextInput が %d 件（xkb の文字が使われた）', [TextInputs]));
      Check(LastCommit = 'a', Format('確定文字列 = "%s"', [LastCommit]));

      WriteLn;
      WriteLn('3. IME セッション開始');
      Session := Ctx.TextInput.Start(nil, Editor as IPMLTextInputClient);
      Check(Session <> nil, 'Start がセッションを返した');
      Check(Ctx.Events.KeyFilter.KeyFilterActive, 'KeyFilterActive = True');

      WriteLn;
      WriteLn('4. ローマ字を流す（IME が消費するはず）');
      KeyDowns := 0; TextInputs := 0; Editings := 0;
      ConsumedBefore := Ctx.Events.Keyboard.ConsumedCount;
      for I := Low(Keys) to High(Keys) do
        SendKey(Keys[I][0], Keys[I][1], Chr(Keys[I][0]));
      Ctx.Events.Pump(200);
      DrainEvents;

      WriteLn(Format('  [INFO] KeyDown=%d TextEditing=%d TextInput=%d 消費=%d',
        [KeyDowns, Editings, TextInputs,
         Ctx.Events.Keyboard.ConsumedCount - ConsumedBefore]));
      Check(Ctx.Events.Keyboard.ConsumedCount - ConsumedBefore > 0,
        'IME がキーを消費した');
      Check(KeyDowns = 0, '消費されたキーは KeyDown にならない');
      Check(TextInputs = 0, '消費されたキーは TextInput にならない（変換中なので）');
      Check(Editings > 0, Format('TextEditing が %d 件届いた', [Editings]));

      WriteLn;
      WriteLn('5. スペースで変換（文節が分かれる）');
      SendKey($20, 57, '');
      Ctx.Events.Pump(400);
      DrainEvents;
      Check(MaxSegs >= 2, Format('文節が %d 個に分かれた', [MaxSegs]));

      WriteLn;
      WriteLn('6. 後始末');
      Session.ResetComposition;
      Ctx.Events.Pump(100);
      DrainEvents;
      Check(Ctx.Events.DroppedCount = 0, 'イベントの取りこぼしなし');
    finally
      FreeAndNil(Ctx);
    end;
    WriteLn('  [PASS] Context 破棄');
  finally
    FreeAndNil(Editor);
  end;

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn('=== 結論: §7.5 の経路どおりに動作する ===');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('=== 失敗 %d 件 ===', [Failures]));
    ExitCode := 1;
  end;
end.
