{
  test_fcitx_textinput — Fcitx5 バックエンドの結合テスト

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    TPMLContext とイベントキューだけを使い、IME の文節情報がイベントとして
    アプリに届くかを確認する。メソッドポインタのコールバックは使わない。

  WHY:
    spikes/spike2_fcitx.pas は「プラットフォームができるか」を示した。
    このテストは「papimela の抽象化とイベントキューを通しても情報が失われないか」
    を示す。設計 §7.9 のアプリ側実装パターンをそのまま書いてある。

  実行前提:
    Wayland セッション、fcitx5 稼働、日本語エンジン（mozc）が利用可能。
}
program test_fcitx_textinput;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.TextInput,
  PaPiMeLa.Core;

type
  { アプリ役。テキストバッファを持ち、周辺テキストを供給する（§7.9）。 }
  TFakeEditor = class(TObject, IPMLTextInputClient)
  strict private
    FBuffer    : String;
    FCursorByte: Integer;
  public
    constructor Create(const AInitial: String);
    function GetSurroundingText(out AText: String;
      out ACursorByte, AAnchorByte: Integer): Boolean;
    function GetCursorRect: TPMLRect;
    procedure InsertAtCursor(const AText: String);
    procedure DeleteAround(ABeforeBytes, AAfterBytes: Integer);
    property Buffer: String read FBuffer;
  end;

constructor TFakeEditor.Create(const AInitial: String);
begin
  inherited Create;
  FBuffer := AInitial;
  FCursorByte := Length(AInitial);
end;

function TFakeEditor.GetSurroundingText(out AText: String;
  out ACursorByte, AAnchorByte: Integer): Boolean;
begin
  AText := FBuffer;
  ACursorByte := FCursorByte;
  AAnchorByte := FCursorByte;
  Result := True;
end;

function TFakeEditor.GetCursorRect: TPMLRect;
begin
  Result := TPMLRect.Make(100, 200, 2, 18);
end;

procedure TFakeEditor.InsertAtCursor(const AText: String);
begin
  Insert(AText, FBuffer, FCursorByte + 1);
  Inc(FCursorByte, Length(AText));
end;

procedure TFakeEditor.DeleteAround(ABeforeBytes, AAfterBytes: Integer);
begin
  if ABeforeBytes > 0 then
  begin
    Delete(FBuffer, FCursorByte - ABeforeBytes + 1, ABeforeBytes);
    Dec(FCursorByte, ABeforeBytes);
  end;
  if AAfterBytes > 0 then
    Delete(FBuffer, FCursorByte + 1, AAfterBytes);
end;

var
  Ctx      : TPMLContext;
  Editor   : TFakeEditor;
  Session  : TPMLTextInputSession;
  Failures : Integer = 0;
  Updates  : Integer = 0;
  MaxSegs  : Integer = 0;
  SawFocus : Boolean = False;
  Verbose  : Boolean = True;

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

procedure ReportComposition(const AEv: TPMLEvent);
var
  I: Integer;
  StateName: String;
begin
  Inc(Updates);
  if Length(AEv.Segments) > MaxSegs then
    MaxSegs := Length(AEv.Segments);
  if AEv.Edit.FocusedSegment >= 0 then
    SawFocus := True;
  if not Verbose then
    Exit;

  WriteLn(Format('    TextEditing "%s" 文節数=%d cursor=(byte %d/char %d) focused=%d 単一範囲=[%d,+%d)',
    [AEv.Text, Length(AEv.Segments), AEv.Edit.CursorByte, AEv.Edit.CursorChar,
     AEv.Edit.FocusedSegment, AEv.Edit.SelectionStartChar,
     AEv.Edit.SelectionLengthChars]));
  for I := 0 to High(AEv.Segments) do
  begin
    case AEv.Segments[I].State of
      TPMLSegmentState.Unconverted: StateName := '未変換';
      TPMLSegmentState.Converted  : StateName := '変換済';
      TPMLSegmentState.Focused    : StateName := '注目';
    end;
    WriteLn(Format('      [%d] "%s" %s  byte[%d,%d) char[%d,%d)',
      [I, AEv.Segments[I].TextOf(AEv.Text), StateName,
       AEv.Segments[I].StartByte, AEv.Segments[I].EndByte,
       AEv.Segments[I].StartChar, AEv.Segments[I].EndChar]));
  end;
end;

// §7.9 のイベントループ。
procedure DrainEvents;
var
  Ev: TPMLEvent;
begin
  while Ctx.Events.Poll(Ev) do
    case Ev.Kind of
      TPMLEventKind.TextEditing:
        ReportComposition(Ev);
      TPMLEventKind.TextInput:
        begin
          Editor.InsertAtCursor(Ev.Text);
          WriteLn(Format('    TextInput "%s" → バッファ="%s"', [Ev.Text, Editor.Buffer]));
        end;
      TPMLEventKind.TextInputDeleteSurrounding:
        begin
          WriteLn(Format('    周辺削除 前%dバイト(%d文字) 後%dバイト(%d文字)',
            [Ev.DeleteSurrounding.BeforeBytes, Ev.DeleteSurrounding.BeforeChars,
             Ev.DeleteSurrounding.AfterBytes, Ev.DeleteSurrounding.AfterChars]));
          Editor.DeleteAround(Ev.DeleteSurrounding.BeforeBytes,
            Ev.DeleteSurrounding.AfterBytes);
        end;
      TPMLEventKind.BackendLost:
        WriteLn('    [WARN] BackendLost');
    end;
end;

procedure SendKey(AKeysym, AKeycode: LongWord);
var
  K: TPMLKeyEventData;
begin
  FillChar(K, SizeOf(K), 0);
  K.Keysym := AKeysym;
  K.Keycode := AKeycode;
  K.Modifiers := [];
  // IME が消費したキーは KeyDown / KeyUp を積まない（§7.9）。
  Ctx.TextInput.FilterKey(K, False);
  Ctx.TextInput.FilterKey(K, True);
  DrainEvents;
end;

const
  // "わたしのなまえ" のローマ字。keycode は evdev+8。
  Keys: array[0..13] of array[0..1] of LongWord = (
    ($77, 25), ($61, 38), ($74, 28), ($61, 38), ($73, 39), ($68, 43), ($69, 31),
    ($6E, 57), ($6F, 32), ($6E, 57), ($61, 38), ($6D, 58), ($61, 38), ($65, 26)
  );
  SPACE_SYM  = $20;
  SPACE_CODE = 65;

var
  I: Integer;
  Ev: TPMLEvent;
begin
  WriteLn('test_fcitx_textinput — TPMLContext とイベントキュー経由で文節が届くか');
  WriteLn;

  Editor := TFakeEditor.Create('これは周辺テキストです');
  try
    WriteLn('1. Context 生成（TextInput サブシステムのみ）');
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
      Check(Ctx.Events <> nil, 'Context.Events が存在する');
      Check(Ctx.Timer <> nil, 'Context.Timer が存在する');
      Check(Ctx.TextInput <> nil, 'Context.TextInput が存在する');
      Check(Ctx.TextInput.BackendName = 'fcitx',
        Format('選ばれたバックエンド = "%s"', [Ctx.TextInput.BackendName]));
      Check(Ctx.Timer.TicksNS > 0, 'Timer.TicksNS が単調時刻を返す');
      // 設計 §10 項目 9 が求めていた実測値。
      WriteLn(Format('  [INFO] SizeOf(TPMLEvent) = %d バイト（管理型 3 個を含む）',
        [SizeOf(TPMLEvent)]));

      WriteLn;
      WriteLn('2. セッション開始（周辺テキストの供給を含む）');
      Session := Ctx.TextInput.Start(nil, Editor as IPMLTextInputClient);
      Check(Session <> nil, 'Start がセッションを返した');
      Session.NotifyCursorRectChanged;
      DrainEvents;

      WriteLn;
      WriteLn('3. ローマ字で「わたしのなまえ」を入力');
      Verbose := False;   // 14 回分は要約する
      for I := Low(Keys) to High(Keys) do
        SendKey(Keys[I][0], Keys[I][1]);
      Verbose := True;
      Check(Updates = 14, Format('TextEditing が %d 回届いた（キー数と一致）', [Updates]));
      Check(MaxSegs = 1, '変換前は 1 文節');
      Check(not SawFocus, '変換前は注目文節なし（全て未変換）');

      WriteLn;
      WriteLn('4. スペースで変換');
      SendKey(SPACE_SYM, SPACE_CODE);
      Ctx.Events.Pump(400);
      DrainEvents;

      WriteLn;
      WriteLn('5. 検証');
      Check(MaxSegs >= 2, Format('文節が %d 個に分かれた', [MaxSegs]));
      Check(SawFocus, '注目文節が Edit.FocusedSegment で判別できた');
      Check(Session.Composing, 'Session.Composing が変換中を示している');
      Check(Ctx.Events.DroppedCount = 0, 'イベントの取りこぼしなし');

      WriteLn;
      WriteLn('6. キューの操作');
      Ctx.Events.PushSimple(TPMLEventKind.Quit);
      Check(Ctx.Events.Peek(TPMLEventKind.Quit), 'Peek が Quit を見つけた');
      Ctx.Events.Flush([TPMLEventKind.Quit]);
      Check(not Ctx.Events.Peek(TPMLEventKind.Quit), 'Flush が Quit を捨てた');
      Ctx.Events.Enabled[TPMLEventKind.Quit] := False;
      Ctx.Events.PushSimple(TPMLEventKind.Quit);
      Check(not Ctx.Events.Peek(TPMLEventKind.Quit), 'Enabled=False で Push が無効化された');
      Ctx.Events.Enabled[TPMLEventKind.Quit] := True;

      WriteLn;
      WriteLn('7. WaitTimeout');
      Ctx.Events.FlushAll;
      Check(not Ctx.Events.WaitTimeout(Ev, 120),
        'イベントが無いとき WaitTimeout が False を返す');

      WriteLn;
      WriteLn('8. 後始末');
      Session.ResetComposition;
      Ctx.Events.Pump(100);
      DrainEvents;
    finally
      FreeAndNil(Ctx);   // §2.4 の逆順破棄
    end;
    WriteLn('  [PASS] Context 破棄');
  finally
    FreeAndNil(Editor);
  end;

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn('=== 結論: イベントキュー経由でも文節情報が失われない ===');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('=== 失敗 %d 件 ===', [Failures]));
    ExitCode := 1;
  end;
end.
