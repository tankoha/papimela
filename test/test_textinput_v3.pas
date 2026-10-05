{
  test_textinput_v3 — text-input-v3 の受信側の状態を表示サーバ無しで検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    TPMLTextInputV3State にプロトコルのイベント列を与え、Sink に届く通知の
    順序と中身を見る。done までの保留、done で届かなかった値の初期化、
    周辺削除 → 確定 → 変換中テキストの順序、cursor_begin / cursor_end からの
    注目範囲、周辺テキストの 4000 バイトの切り詰め、周辺削除の文字数への換算、
    入力の種類の写し方。

  WHY:
    実機のコンポジタと IME の組み合わせでは、この順序や初期化の誤りが
    「たまに 1 文字消える」「変換中テキストが残る」としてしか見えない。
    プロトコルの記述を 1 つずつ検査に置き換えておく。
    実機の通し確認は PAPIMELA_IME=wayland ./test/demo_japanese_input（手元）。

  実行前提: 無し。
}
program test_textinput_v3;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Events,
  PaPiMeLa.Core,
  PaPiMeLa.TextInput,
  PaPiMeLa.TextInput.Backend,
  PaPiMeLa.Platform.Wayland.Protocols.TextInputUnstableV3,
  PaPiMeLa.TextInput.WaylandTI;

type
  { 届いた通知を 1 行ずつ記録する。 }
  TRecordingSink = class(TObject, IPMLTextInputSink)
  public
    Log: String;
    LastComp: TPMLComposition;
    LastDelete: TPMLDeleteSurroundingData;
    procedure CompositionChanged(const AComposition: TPMLComposition);
    procedure TextCommitted(const AText: String);
    procedure DeleteSurroundingRequested(const AData: TPMLDeleteSurroundingData);
    procedure CandidatesChanged(const ACandidates: TPMLStringArray;
      ASelected: Integer; AHorizontal: Boolean);
    procedure BackendLost(const AReason: String);
  end;

  { 周辺テキストを送り直す時機を見るためのバックエンド。Pump で 1 回だけ確定を流す。 }
  TScriptBackend = class(TPMLNullTextInputBackend)
  public
    Received: String;
    CommitOnPump: String;
    function  BackendName: String; override;
    function  Capabilities: TPMLTextInputCapabilities; override;
    procedure UpdateSurroundingText(const AText: String; ACursorByte, AAnchorByte: Integer); override;
    procedure Pump(ATimeoutMs: Integer); override;
  end;

  { アプリの編集欄。確定を受けたら末尾に足す。 }
  TEditor = class(TObject, IPMLTextInputClient)
  public
    Buffer: String;
    function GetSurroundingText(out AText: String;
      out ACursorByte, AAnchorByte: Integer): Boolean;
    function GetCursorRect: TPMLRect;
  end;

var
  Failures: Integer = 0;
  Script: TScriptBackend = nil;

procedure TRecordingSink.CompositionChanged(const AComposition: TPMLComposition);
begin
  LastComp := AComposition;
  Log := Log + 'P[' + AComposition.Text + ']';
end;

procedure TRecordingSink.TextCommitted(const AText: String);
begin
  Log := Log + 'C[' + AText + ']';
end;

procedure TRecordingSink.DeleteSurroundingRequested(const AData: TPMLDeleteSurroundingData);
begin
  LastDelete := AData;
  Log := Log + Format('D[%d,%d]', [AData.BeforeBytes, AData.AfterBytes]);
end;

procedure TRecordingSink.CandidatesChanged(const ACandidates: TPMLStringArray;
  ASelected: Integer; AHorizontal: Boolean);
begin
  Log := Log + 'K';
end;

procedure TRecordingSink.BackendLost(const AReason: String);
begin
  Log := Log + 'L';
end;

function TScriptBackend.BackendName: String;
begin
  Result := 'script';
end;

function TScriptBackend.Capabilities: TPMLTextInputCapabilities;
begin
  Result := [TPMLTextInputCapability.SurroundingText];
end;

procedure TScriptBackend.UpdateSurroundingText(const AText: String;
  ACursorByte, AAnchorByte: Integer);
begin
  Received := Received + '[' + AText + ']';
end;

procedure TScriptBackend.Pump(ATimeoutMs: Integer);
begin
  if CommitOnPump <> '' then
  begin
    FSink.TextCommitted(CommitOnPump);
    CommitOnPump := '';
  end;
end;

function MakeScript: TPMLTextInputBackend;
begin
  Script := TScriptBackend.Create;
  Result := Script;
end;

function TEditor.GetSurroundingText(out AText: String;
  out ACursorByte, AAnchorByte: Integer): Boolean;
begin
  AText := Buffer;
  ACursorByte := Length(Buffer);
  AAnchorByte := ACursorByte;
  Result := True;
end;

function TEditor.GetCursorRect: TPMLRect;
begin
  Result := TPMLRect.Make(0, 0, 2, 18);
end;

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

function SegDesc(const C: TPMLComposition): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(C.Segments) do
    Result := Result + Format('%d-%d:%d/%d-%d ', [C.Segments[I].StartByte,
      C.Segments[I].EndByte, Ord(C.Segments[I].State),
      C.Segments[I].StartChar, C.Segments[I].EndChar]);
  Result := Trim(Result);
end;

const
  // 「かんじ」= 3 文字 × 3 バイト
  KANJI = 'かんじ';

var
  St  : TPMLTextInputV3State;
  Sink: TRecordingSink;
  C   : TPMLComposition;
  S, Big: String;
  Cur, Anc, I: Integer;
  Hint, Purpose: LongWord;
  Ctx : TPMLContext;
  Opts: TPMLContextOptions;
  Ed  : TEditor;
  Ev  : TPMLEvent;
begin
  WriteLn('test_textinput_v3 — text-input-v3 の受信側の状態');
  WriteLn;
  Sink := TRecordingSink.Create;
  St := TPMLTextInputV3State.Create;
  try
    WriteLn('1. done まで保留する');
    St.Preedit(KANJI, 9, 9);
    Check(Sink.Log = '', 'preedit_string だけでは何も通知しない');
    St.Done(Sink);
    Check(Sink.Log = 'P[' + KANJI + ']', 'done で変換中テキストが届く');
    Check((Sink.LastComp.CursorByte = 9) and (Sink.LastComp.CursorChar = 3),
      'カーソルはバイト 9 / 文字 3（begin = end は線のカーソル）');
    Check(not Sink.LastComp.SegmentsReliable, 'SegmentsReliable は False');
    Check(SegDesc(Sink.LastComp) = '0-9:0/0-3', '全体が 1 つの未変換文節');
    Check(Sink.LastComp.FocusedSegment = -1, '注目文節は無い');

    WriteLn;
    WriteLn('2. 確定。done に preedit が無ければ変換中テキストは空に戻る');
    Sink.Log := '';
    St.CommitString('漢字');
    St.Done(Sink);
    Check(Sink.Log = 'C[漢字]P[]', '確定 → 空の変換中テキストの順');
    Check(St.Composition.IsEmpty, '状態の変換中テキストも空');

    Sink.Log := '';
    St.Done(Sink);
    Check(Sink.Log = '', '何も無い done は何も通知しない（空を重ねて送らない）');

    WriteLn;
    WriteLn('3. 周辺削除 → 確定 → 変換中テキスト の順（受け取った順に依らない）');
    St.PrepareSurrounding('あいう', 6, 6, S, Cur, Anc);
    Sink.Log := '';
    St.Preedit('え', 3, 3);
    St.CommitString('X');
    St.DeleteSurrounding(3, 0);
    St.Done(Sink);
    Check(Sink.Log = 'D[3,0]C[X]P[え]', 'D → C → P');
    Check((Sink.LastDelete.BeforeChars = 1) and (Sink.LastDelete.AfterChars = 0),
      '3 バイトは「い」1 文字');

    WriteLn;
    WriteLn('4. done の後は保留が初期値に戻る');
    Sink.Log := '';
    St.Done(Sink);
    Check(Sink.Log = 'P[]', '次の done では確定も削除も繰り返さず、変換中テキストは空');

    WriteLn;
    WriteLn('5. cursor_begin <> cursor_end は注目範囲');
    C := TPMLTextInputV3State.BuildComposition('わたしはね', 9, 12);
    Check(SegDesc(C) = '0-9:0/0-3 9-12:2/3-4 12-15:0/4-5',
      '前・注目・後の 3 つ（' + SegDesc(C) + '）');
    Check(C.FocusedSegment = 1, '注目文節は 2 つ目');
    Check(C.CursorByte = -1, '範囲のときは線のカーソルを描かない');
    C := TPMLTextInputV3State.BuildComposition(KANJI, 0, 9);
    Check((SegDesc(C) = '0-9:2/0-3') and (C.FocusedSegment = 0), '全体が注目なら 1 つ');
    C := TPMLTextInputV3State.BuildComposition(KANJI, -1, -1);
    Check((C.CursorByte = -1) and (SegDesc(C) = '0-9:0/0-3'), '-1, -1 はカーソル非表示');
    C := TPMLTextInputV3State.BuildComposition(KANJI, 4, 4);
    Check(C.CursorByte = 3, '文字の途中を指すカーソルは文字の先頭へ寄せる');
    C := TPMLTextInputV3State.BuildComposition(KANJI, 50, 50);
    Check(C.CursorByte = 9, '範囲外のカーソルは末尾へ');
    C := TPMLTextInputV3State.BuildComposition('', 0, 0);
    Check(C.IsEmpty and (Length(C.Segments) = 0), '空文字列は空の変換中テキスト');

    WriteLn;
    WriteLn('6. フォーカスが外れたら保留を捨てて変換中テキストを消す');
    St.Preedit('あ', 3, 3);
    St.Done(Sink);
    Sink.Log := '';
    St.CommitString('捨てる');
    St.Leave(Sink);
    Check(Sink.Log = 'P[]', 'leave で空の変換中テキスト（確定は届かない）');
    Sink.Log := '';
    St.Done(Sink);
    Check(Sink.Log = '', 'leave の前の保留は次の done に持ち越さない');
    St.Leave(Sink);
    Check(Sink.Log = '', '変換中テキストが無ければ leave は何も通知しない');

    WriteLn;
    WriteLn('7. 周辺テキストの切り詰め（4000 バイト）');
    TPMLTextInputV3State.TruncateSurrounding('abc', 1, 2, 4000, S, Cur, Anc);
    Check((S = 'abc') and (Cur = 1) and (Anc = 2), '上限以内はそのまま');
    Big := '';
    // 9000 バイト。どこを切り出したかが中身で分かるよう、全部違う文字にする
    // （U+4E00 から 3000 字。どれも 3 バイト）。
    for I := 0 to 2999 do
      Big := Big + UTF8Encode(UnicodeString(WideChar($4E00 + I)));
    TPMLTextInputV3State.TruncateSurrounding(Big, 4500, 4500, 4000, S, Cur, Anc);
    Check(Length(S) <= 4000, Format('4000 バイト以内（%d）', [Length(S)]));
    Check(Length(S) mod 3 = 0, '文字の途中で切らない');
    Check((Cur = Anc) and (Cur > 1500) and (Cur < 2500), Format('カーソルは中央付近（%d）', [Cur]));
    Check(Copy(Big, 4500 - Cur + 1, Length(S)) = S, '元のテキストのカーソルの周りが残る');
    TPMLTextInputV3State.TruncateSurrounding(Big, 0, 0, 4000, S, Cur, Anc);
    Check((Cur = 0) and (Length(S) > 3990), '先頭のカーソルなら先頭から');
    TPMLTextInputV3State.TruncateSurrounding(Big, 9000, 9000, 4000, S, Cur, Anc);
    Check((Cur = Length(S)) and (Length(S) > 3990), '末尾のカーソルなら末尾まで');
    TPMLTextInputV3State.TruncateSurrounding(Big, 3000, 3600, 4000, S, Cur, Anc);
    Check(Anc - Cur = 600, '選択が入るなら選択ごと残る');
    TPMLTextInputV3State.TruncateSurrounding(Big, 1998, 5400, 4000, S, Cur, Anc);
    Check(Anc - Cur = 3402, '選択が入るなら、カーソルが端に寄っていても選択ごと残る');
    TPMLTextInputV3State.TruncateSurrounding(Big, 0, 9000, 4000, S, Cur, Anc);
    Check((Cur = 0) and (Anc = Length(S)), '選択が入らなければカーソル側を残し、アンカーは端へ');
    TPMLTextInputV3State.TruncateSurrounding(Big, 9000, 0, 4000, S, Cur, Anc);
    Check((Cur = Length(S)) and (Anc = 0) and (Copy(Big, 9000 - Length(S) + 1, Length(S)) = S),
      '選択が入らないとき、残るのはカーソルの周り（選択の中央ではない）');

    WriteLn;
    WriteLn('8. 周辺削除の換算は送った（切り詰めた）テキストの上で行う');
    St.PrepareSurrounding(Big, 4500, 4500, S, Cur, Anc);
    Sink.Log := '';
    St.DeleteSurrounding(6, 3);
    St.Done(Sink);
    Check((Sink.LastDelete.BeforeBytes = 6) and (Sink.LastDelete.AfterBytes = 3)
      and (Sink.LastDelete.BeforeChars = 2) and (Sink.LastDelete.AfterChars = 1),
      '前 6 バイト = 2 文字、後 3 バイト = 1 文字');
    St.PrepareSurrounding('aあb', 4, 4, S, Cur, Anc);
    St.DeleteSurrounding(2, 0);
    St.Done(Sink);
    Check((Sink.LastDelete.BeforeBytes = 0) and (Sink.LastDelete.BeforeChars = 0),
      '文字の途中までの削除は、その文字を消さない');
    St.DeleteSurrounding(100, 100);
    St.Done(Sink);
    Check((Sink.LastDelete.BeforeBytes = 4) and (Sink.LastDelete.AfterBytes = 1)
      and (Sink.LastDelete.BeforeChars = 2) and (Sink.LastDelete.AfterChars = 1),
      '送ったテキストの外へはみ出す分は切り捨てる');
  finally
    St.Free;
  end;

  St := TPMLTextInputV3State.Create;
  try
    Sink.Log := '';
    St.DeleteSurrounding(3, 0);
    St.Done(Sink);
    Check((Sink.Log = 'D[0,0]') or (Sink.Log = ''),
      '周辺テキストを送っていなければ何も消さない');
  finally
    St.Free;
  end;

  WriteLn;
  WriteLn('9. 変更の理由（確定・削除の直後の周辺テキストは input_method）');
  St := TPMLTextInputV3State.Create;
  try
    Check(not St.TakeEditedByIME, '最初は other');
    St.CommitString('x');
    St.Done(Sink);
    Check(St.TakeEditedByIME, '確定の後は input_method');
    Check(not St.TakeEditedByIME, '1 回読むと other に戻る');
    St.Preedit('y', 1, 1);
    St.Done(Sink);
    Check(not St.TakeEditedByIME, '変換中テキストだけなら other');
  finally
    St.Free;
  end;

  WriteLn;
  WriteLn('10. 入力の種類');
  TPMLTextInputV3State.ContentType(TPMLTextInputType.Text, [], Hint, Purpose);
  Check((Hint = ZWP_TEXT_INPUT_V3_CONTENT_HINT_NONE)
    and (Purpose = ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_NORMAL), 'Text は normal / none');
  TPMLTextInputV3State.ContentType(TPMLTextInputType.Password, [], Hint, Purpose);
  Check((Purpose = ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_PASSWORD)
    and ((Hint and ZWP_TEXT_INPUT_V3_CONTENT_HINT_HIDDEN_TEXT) <> 0)
    and ((Hint and ZWP_TEXT_INPUT_V3_CONTENT_HINT_SENSITIVE_DATA) <> 0),
    'Password は password / hidden_text + sensitive_data');
  TPMLTextInputV3State.ContentType(TPMLTextInputType.Email,
    [TPMLTextInputHint.Multiline, TPMLTextInputHint.AutoCapitalize], Hint, Purpose);
  Check((Purpose = ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_EMAIL)
    and (Hint = ZWP_TEXT_INPUT_V3_CONTENT_HINT_MULTILINE
                or ZWP_TEXT_INPUT_V3_CONTENT_HINT_AUTO_CAPITALIZATION),
    'Email + Multiline + AutoCapitalize');
  TPMLTextInputV3State.ContentType(TPMLTextInputType.Number, [], Hint, Purpose);
  Check(Purpose = ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_NUMBER, 'Number は number');

  WriteLn;
  WriteLn('11. 確定の後の周辺テキストは、アプリが確定を取り込んでから送り直す');
  // v3 の done も Fcitx の CommitString も Pump の中で届く。同じ Pump の中で
  // 周辺テキストを取り直すと、アプリはまだ確定を取り込んでいないので古い
  // テキストを IME へ送ってしまう。
  PMLRegisterTextInputBackend('script', 1, @MakeScript);
  Opts := TPMLContextOptions.Default;
  Opts.PreferredTextInput := 'script';
  Ctx := TPMLContext.Create([TPMLSubsystem.TextInput], Opts);
  Ed := TEditor.Create;
  try
    Ed.Buffer := 'ab';
    Ctx.TextInput.Start(nil, Ed);
    Check(Script.Received = '[ab]', '開始で周辺テキストを送る（' + Script.Received + '）');
    Script.Received := '';
    Script.CommitOnPump := 'X';
    Ctx.Events.Pump(0);
    Check(Script.Received = '', '確定を流した Pump の中では送り直さない（' + Script.Received + '）');
    while Ctx.Events.Poll(Ev) do
      if Ev.Kind = TPMLEventKind.TextInput then
        Ed.Buffer := Ed.Buffer + Ev.Text;
    Ctx.Events.Pump(0);
    Check(Script.Received = '[abX]', '次の Pump で、確定を取り込んだテキストを送る（' + Script.Received + '）');
    Script.Received := '';
    Ctx.Events.Pump(0);
    Check(Script.Received = '', '送り直すのは 1 回だけ');
  finally
    Ctx.Free;
    Ed.Free;
  end;

  Sink.Free;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: text-input-v3 の受信側がプロトコルの記述どおりに動く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
