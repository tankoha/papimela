{
  test_fcitx_textinput — Fcitx5 バックエンドの結合テスト

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    papimela の公開 API（TPMLTextInputSystem / IPMLTextInputClient）だけを使い、
    spikes/spike2_fcitx.pas が生の D-Bus で得たのと同じ結果になるかを確認する。

  WHY:
    スパイクは「プラットフォームができるか」を示した。このテストは「papimela の
    抽象化を通しても同じ情報が失われずに届くか」を示す。

  実行前提:
    Wayland セッション、fcitx5 稼働、日本語エンジン（mozc）が利用可能。
}
program test_fcitx_textinput;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.TextInput;

type
  { アプリ役。テキストバッファを持ち、周辺テキストを供給する。 }
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

  TTestRun = class
  strict private
    FSystem   : TPMLTextInputSystem;
    FEditor   : TFakeEditor;
    FSession  : TPMLTextInputSession;
    FUpdates  : Integer;
    FMaxSegs  : Integer;
    FSawFocus : Boolean;
    FFailures : Integer;
    procedure OnComposition(ASession: TPMLTextInputSession;
      const AComposition: TPMLComposition);
    procedure OnCommit(ASession: TPMLTextInputSession; const AText: String);
    procedure OnDeleteSurrounding(ASession: TPMLTextInputSession;
      const AData: TPMLDeleteSurroundingData);
    procedure Check(ACondition: Boolean; const ALabel: String);
    procedure SendKey(AKeysym, AKeycode: LongWord);
  public
    function Run: Integer;
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

procedure TTestRun.Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
    WriteLn('  [PASS] ', ALabel)
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(FFailures);
  end;
end;

procedure TTestRun.OnComposition(ASession: TPMLTextInputSession;
  const AComposition: TPMLComposition);
var
  I: Integer;
  StateName: String;
begin
  Inc(FUpdates);
  if Length(AComposition.Segments) > FMaxSegs then
    FMaxSegs := Length(AComposition.Segments);
  if AComposition.FocusedSegment >= 0 then
    FSawFocus := True;

  WriteLn(Format('    変換中="%s" 文節数=%d cursor=(byte %d / char %d) focused=%d',
    [AComposition.Text, Length(AComposition.Segments),
     AComposition.CursorByte, AComposition.CursorChar,
     AComposition.FocusedSegment]));
  for I := 0 to High(AComposition.Segments) do
  begin
    case AComposition.Segments[I].State of
      TPMLSegmentState.Unconverted: StateName := '未変換';
      TPMLSegmentState.Converted  : StateName := '変換済';
      TPMLSegmentState.Focused    : StateName := '注目';
    end;
    WriteLn(Format('      [%d] "%s" %s  byte[%d,%d) char[%d,%d)',
      [I, AComposition.Segments[I].TextOf(AComposition.Text), StateName,
       AComposition.Segments[I].StartByte, AComposition.Segments[I].EndByte,
       AComposition.Segments[I].StartChar, AComposition.Segments[I].EndChar]));
  end;
end;

procedure TTestRun.OnCommit(ASession: TPMLTextInputSession; const AText: String);
begin
  FEditor.InsertAtCursor(AText);
  WriteLn(Format('    確定="%s" → バッファ="%s"', [AText, FEditor.Buffer]));
end;

procedure TTestRun.OnDeleteSurrounding(ASession: TPMLTextInputSession;
  const AData: TPMLDeleteSurroundingData);
begin
  WriteLn(Format('    周辺削除 前%dバイト(%d文字) 後%dバイト(%d文字)',
    [AData.BeforeBytes, AData.BeforeChars, AData.AfterBytes, AData.AfterChars]));
  FEditor.DeleteAround(AData.BeforeBytes, AData.AfterBytes);
end;

procedure TTestRun.SendKey(AKeysym, AKeycode: LongWord);
var
  K: TPMLKeyEventData;
begin
  K.Keysym := AKeysym;
  K.Keycode := AKeycode;
  K.Modifiers := [];
  K.IsRelease := False;
  FSystem.FilterKey(K);
  K.IsRelease := True;
  FSystem.FilterKey(K);
  FSystem.Pump(30);
end;

function TTestRun.Run: Integer;
const
  // "わたしのなまえ" のローマ字。keycode は evdev+8。
  Keys: array[0..13] of array[0..1] of LongWord = (
    ($77, 25), ($61, 38), ($74, 28), ($61, 38), ($73, 39), ($68, 43), ($69, 31),
    ($6E, 57), ($6F, 32), ($6E, 57), ($61, 38), ($6D, 58), ($61, 38), ($65, 26)
  );
  SPACE_SYM = $20;
  SPACE_CODE = 65;
var
  I: Integer;
begin
  FFailures := 0;
  WriteLn('test_fcitx_textinput — papimela の公開 API 経由で文節が届くか');
  WriteLn;

  FEditor := TFakeEditor.Create('これは周辺テキストです');
  try
    WriteLn('1. バックエンド選択');
    try
      FSystem := TPMLTextInputSystem.Create;
    except
      on E: EPMLError do
      begin
        WriteLn('  [FAIL] ', E.Message);
        Exit(1);
      end;
    end;
    try
      Check(FSystem.BackendName = 'fcitx',
        Format('選ばれたバックエンド = "%s"', [FSystem.BackendName]));
      WriteLn(Format('  [INFO] 能力集合: Segments=%s SurroundingText=%s DeleteSurrounding=%s',
        [BoolToStr(TPMLTextInputCapability.Segments in FSystem.Backend.Capabilities, True),
         BoolToStr(TPMLTextInputCapability.SurroundingText in FSystem.Backend.Capabilities, True),
         BoolToStr(TPMLTextInputCapability.DeleteSurrounding in FSystem.Backend.Capabilities, True)]));

      FSystem.OnComposition := @OnComposition;
      FSystem.OnCommit := @OnCommit;
      FSystem.OnDeleteSurrounding := @OnDeleteSurrounding;

      WriteLn;
      WriteLn('2. セッション開始（周辺テキストの供給を含む）');
      FSession := FSystem.Start(nil, FEditor as IPMLTextInputClient);
      Check(FSession <> nil, 'Start がセッションを返した');
      FSession.NotifyCursorRectChanged;
      FSystem.Pump(100);

      WriteLn;
      WriteLn('3. ローマ字で「わたしのなまえ」を入力');
      for I := Low(Keys) to High(Keys) do
        SendKey(Keys[I][0], Keys[I][1]);
      Check(FUpdates > 0, Format('変換中テキストが %d 回届いた', [FUpdates]));

      WriteLn;
      WriteLn('4. スペースで変換');
      SendKey(SPACE_SYM, SPACE_CODE);
      FSystem.Pump(400);

      WriteLn;
      WriteLn('5. 検証');
      Check(FMaxSegs >= 2, Format('文節が %d 個に分かれた（2 以上なら成功）', [FMaxSegs]));
      Check(FSawFocus, '注目文節が FocusedSegment で判別できた');
      Check(FSession.Composing, 'Session.Composing が変換中を示している');

      WriteLn;
      WriteLn('6. 後始末');
      FSession.ResetComposition;
      FSystem.Pump(100);
      FSystem.Stop;
      WriteLn('  [PASS] セッション停止');
    finally
      FreeAndNil(FSystem);
    end;
  finally
    FreeAndNil(FEditor);
  end;

  WriteLn;
  if FFailures = 0 then
  begin
    WriteLn('=== 結論: papimela の抽象化を通しても文節情報が失われない ===');
    Result := 0;
  end
  else
  begin
    WriteLn(Format('=== 失敗 %d 件 ===', [FFailures]));
    Result := 1;
  end;
end;

var
  Run: TTestRun;
begin
  Run := TTestRun.Create;
  try
    ExitCode := Run.Run;
  finally
    Run.Free;
  end;
end.
