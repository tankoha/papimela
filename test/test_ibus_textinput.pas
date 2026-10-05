{
  test_ibus_textinput — IBus のバックエンドを本物の ibus-mozc で通しで確かめる

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    公開 API（TPMLContext とイベントキュー）から、キーを TPMLKeyboardState に流し、
    ibus-mozc で ローマ字 → 変換 → 文節の移動 → 確定 → 再変換 を行う。文節が
    属性どおりに届くこと、消費されたキーが KeyDown / KeyUp にならないこと、返信を
    待つ間もキーの順序が保たれること、周辺テキストを送ること、ibus-daemon を
    立て直しても繋ぎ直すことを見る。

  WHY:
    test_ibus_model は IBus の部品を作った値で見る。ここは本物のデーモンとの
    手順（非同期の返信、通知と返信の順序、RequireSurroundingText の頻度）が
    噛み合うかを見る。

  実行前提: ibus-session の中（ibus-daemon と ibus-mozc が動いている）。手元では
            tools/ibus-sandbox/run.sh で、CI ではランナーの上で直接（.github/workflows/lint.yml）。
            手元のデスクトップでは fcitx5 が IBus を装っているので、この検査は
            IBus の無い所で走らせても失敗する（それで正しい）。
}
program test_ibus_textinput;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Process,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Events.Keymap,
  PaPiMeLa.TextInput,
  PaPiMeLa.TextInput.IBus,
  PaPiMeLa.Core;

type
  { 編集欄。確定・周辺削除をバッファへ適用する（アプリがすることと同じ）。 }
  TEditor = class(TObject, IPMLTextInputClient)
  public
    Buffer: String;
    Cursor, Anchor: Integer;   // バイト位置
    Asked: Integer;
    function GetSurroundingText(out AText: String;
      out ACursorByte, AAnchorByte: Integer): Boolean;
    function GetCursorRect: TPMLRect;
  end;

function TEditor.GetSurroundingText(out AText: String;
  out ACursorByte, AAnchorByte: Integer): Boolean;
begin
  Inc(Asked);
  AText := Buffer;
  ACursorByte := Cursor;
  AAnchorByte := Anchor;
  Result := True;
end;

function TEditor.GetCursorRect: TPMLRect;
begin
  Result := TPMLRect.Make(10, 10, 2, 18);
end;

var
  Ctx     : TPMLContext;
  Ed      : TEditor;
  Failures: Integer = 0;
  KeyDowns, KeyUps, Commits, Deletes: Integer;
  LastComp: TPMLEvent;
  HaveComp: Boolean;
  Order   : String;

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

procedure ResetCounts;
begin
  KeyDowns := 0; KeyUps := 0; Commits := 0; Deletes := 0;
  HaveComp := False;
  Order := '';
end;

procedure Drain;
var
  Ev: TPMLEvent;
begin
  while Ctx.Events.Poll(Ev) do
    case Ev.Kind of
      TPMLEventKind.KeyDown:
        begin
          Inc(KeyDowns);
          Order := Order + 'D' + Chr(Ev.Key.Key and $7F);
        end;
      TPMLEventKind.KeyUp: Inc(KeyUps);
      TPMLEventKind.TextEditing:
        begin
          LastComp := Ev;
          HaveComp := True;
        end;
      TPMLEventKind.TextInput:
        begin
          Inc(Commits);
          Order := Order + '[' + Ev.Text + ']';
          // 確定はカーソルの位置へ入れる。
          Insert(Ev.Text, Ed.Buffer, Ed.Cursor + 1);
          Inc(Ed.Cursor, Length(Ev.Text));
          Ed.Anchor := Ed.Cursor;
        end;
      TPMLEventKind.TextInputDeleteSurrounding:
        begin
          Inc(Deletes);
          Order := Order + Format('<%d,%d>', [Ev.DeleteSurrounding.BeforeBytes,
            Ev.DeleteSurrounding.AfterBytes]);
          Delete(Ed.Buffer, Ed.Cursor - Ev.DeleteSurrounding.BeforeBytes + 1,
            Ev.DeleteSurrounding.BeforeBytes + Ev.DeleteSurrounding.AfterBytes);
          Dec(Ed.Cursor, Ev.DeleteSurrounding.BeforeBytes);
          Ed.Anchor := Ed.Cursor;
        end;
    end;
end;

{ 返信が全部届くまで回す（最大 AMs ミリ秒）。 }
procedure Settle(AMs: Integer = 1500);
var
  Deadline, Start: QWord;
begin
  // 返信が全部届き、かつ 150 ms 経つまで（返信の後に来る通知も拾うため）。
  Start := GetTickCount64;
  Deadline := Start + QWord(AMs);
  repeat
    Ctx.Events.Pump(10);
    Drain;
  until ((Ctx.Events.Keyboard.DeferredCount = 0) and (GetTickCount64 - Start >= 150))
    or (GetTickCount64 >= Deadline);
  // 返信の後に来る通知も拾う。
  Ctx.Events.Pump(50);
  Drain;
end;

procedure SendKey(AKeysym, AEvdev: LongWord; ADown: Boolean; const AText: String);
var
  K: TPMLKeyEventData;
begin
  FillChar(K, SizeOf(K), 0);
  K.Keysym := AKeysym;
  K.Raw := AEvdev + 8;
  K.Scancode := PMLScancodeFromEvdev(AEvdev);
  Ctx.Events.Keyboard.SendKey(1, K, ADown, AText);
end;

procedure Tap(AKeysym, AEvdev: LongWord; const AText: String = '');
begin
  SendKey(AKeysym, AEvdev, True, AText);
  SendKey(AKeysym, AEvdev, False, '');
end;

const
  EVDEV: array['a'..'z'] of LongWord = (
    30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50,
    49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44);

procedure TypeRomaji(const S: String);
var
  C: Char;
begin
  // 返信を待たずに続けて流す（非同期の待ち行列の順序を試す）。
  for C in S do
    Tap(Ord(C), EVDEV[C], C);
  Settle;
end;

function SegDesc(const Ev: TPMLEvent): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Ev.Segments) do
    Result := Result + Ev.Segments[I].TextOf(Ev.Text) + ':' +
      IntToStr(Ord(Ev.Segments[I].State)) + ' ';
  Result := Trim(Result);
end;

procedure RestartDaemon;
var
  Out: String;
begin
  // ibus-session と同じ設定で立て直す。親（この sh）がすぐ終わるので --daemonize で
  // 切り離す（付けないと ibus-daemon は親が死んだのを見て終わる。実測）。
  RunCommand('/bin/sh', ['-c', 'ibus exit; sleep 0.5; ibus-daemon --daemonize --single --panel=disable ' +
    '--emoji-extension=disable --config=disable --cache=refresh; ' +
    'i=0; until { ibus engine mozc-jp >/dev/null 2>&1 || true; [ "$(ibus engine 2>/dev/null)" = mozc-jp ]; }; ' +
    'do i=$((i+1)); [ $i -lt 100 ] || exit 1; sleep 0.1; done'], Out);
end;

var
  Opts: TPMLContextOptions;
  IB  : TPMLIBusTextInputBackend;
  T0  : QWord;
  SawLost: Boolean = False;
begin
  WriteLn('test_ibus_textinput — 本物の ibus-mozc で通しで');
  WriteLn;
  Opts := TPMLContextOptions.Default;
  Opts.PreferredTextInput := 'ibus';
  Ed := TEditor.Create;
  try
    Ctx := TPMLContext.Create([TPMLSubsystem.TextInput], Opts);
  except
    on E: EPMLError do
    begin
      WriteLn('  [FAIL] ', E.ClassName, ': ', E.Message, '（IBus の隔離環境の中で動かすこと）');
      Halt(1);
    end;
  end;
  try
    WriteLn('1. 接続');
    Check(Ctx.TextInput.BackendName = 'ibus', 'IME は ibus');
    IB := Ctx.TextInput.BackendInstance as TPMLIBusTextInputBackend;
    Check(IB.InputContextPath <> '', '入力コンテキストができた: ' + IB.InputContextPath);
    Ed.Buffer := 'これは';
    Ed.Cursor := Length(Ed.Buffer);
    Ed.Anchor := Ed.Cursor;
    Ctx.TextInput.Start(nil, Ed);
    Ctx.TextInput.Session.NotifyCursorRectChanged;
    Settle(300);
    Check(Ed.Asked >= 1, '開始で周辺テキストを取りに来る');

    WriteLn;
    WriteLn('2. ローマ字（返信を待たずに 5 キー続けて）');
    ResetCounts;
    TypeRomaji('kanji');
    Check(HaveComp and (LastComp.Text = 'かんじ'), '変換中テキスト「' + LastComp.Text + '」');
    Check(SegDesc(LastComp) = 'かんじ:0', '全体が 1 つの未変換文節（' + SegDesc(LastComp) + '）');
    Check(LastComp.Edit.SegmentsReliable and (LastComp.Edit.CursorChar = 3), '文節は信頼でき、カーソルは末尾');
    Check((KeyDowns = 0) and (KeyUps = 0) and (Commits = 0),
      Format('消費されたキーは KeyDown も KeyUp も文字も出さない（%d / %d / %d）', [KeyDowns, KeyUps, Commits]));
    Check(Ctx.Events.Keyboard.DeferredCount = 0, '返信は全部届いた');

    WriteLn;
    WriteLn('3. 変換と文節');
    ResetCounts;
    Tap($20, 57);
    Settle;
    Check(HaveComp and (LastComp.Text = '感じ') and (SegDesc(LastComp) = '感じ:2'),
      'スペースで「感じ」が 1 つの注目文節（' + SegDesc(LastComp) + '）');
    Tap($FF0D, 28);
    Settle;
    Check((Commits = 1) and (Ed.Buffer = 'これは感じ'), '確定でバッファへ入る: ' + Ed.Buffer);
    Check(HaveComp and (LastComp.Text = ''), '確定の後は変換中テキストが空になる（HidePreeditText）');
    Check(KeyDowns + KeyUps = 0, 'スペースと Enter も消費された');

    ResetCounts;
    TypeRomaji('watashinonamaeha');
    Tap($20, 57);
    Settle;
    Check(SegDesc(LastComp) = '私の:2 名前は:1',
      '「私の|名前は」: 注目と変換済み（' + SegDesc(LastComp) + '）');
    Check(LastComp.Edit.FocusedSegment = 0, '注目文節は 0 番');
    Tap($FF53, 106);
    Settle;
    Check(SegDesc(LastComp) = '私の:1 名前は:2', '→ で注目が後ろへ（' + SegDesc(LastComp) + '）');
    Tap($FF1B, 1);
    Tap($FF1B, 1);
    Settle;
    Check(HaveComp and (LastComp.Text = ''), 'Escape 2 回で変換中テキストが消える');
    Check(Commits = 0, '何も確定しない');

    WriteLn;
    WriteLn('4. 消費されないキーの順序');
    ResetCounts;
    Tap($FF08, 14);   // 変換中テキストが無いときの BackSpace は素通し
    Settle;
    Check((KeyDowns = 1) and (KeyUps = 1), Format('BackSpace は KeyDown / KeyUp になる（%d / %d）', [KeyDowns, KeyUps]));

    WriteLn;
    WriteLn('5. 再変換（周辺テキスト → 周辺削除 → 変換中テキスト）');
    // 「これは感じ」の「感じ」を選ぶ（カーソルは末尾、アンカーは「感じ」の前）。
    ResetCounts;
    Ed.Cursor := Length(Ed.Buffer);
    Ed.Anchor := Length('これは');
    Ctx.TextInput.Session.NotifyTextChanged;
    Settle(300);
    Tap($FF23, 92);   // 変換キー
    Settle;
    Check(Deletes = 1, Format('周辺削除が 1 回（%d）。順序: %s', [Deletes, Order]));
    Check(Ed.Buffer = 'これは', '選んだ「感じ」がバッファから消えた: ' + Ed.Buffer);
    Check(HaveComp and (LastComp.Text = '感じ'), '再変換の変換中テキスト「' + LastComp.Text + '」');
    Tap($20, 57);
    Tap($FF0D, 28);
    Settle;
    Check(Ed.Buffer = 'これは漢字', '次の候補で確定: ' + Ed.Buffer);

    WriteLn;
    WriteLn('6. ibus-daemon を立て直しても繋ぎ直す');
    RestartDaemon;
    // 切れたことに気づくまで待ち、それから繋ぎ直すまで待つ（再試行は 1 秒ごと。最大 5 秒）。
    T0 := GetTickCount64;
    repeat
      Ctx.Events.Pump(20);
      Drain;
      Sleep(20);
      if IB.LastNonFatalError = 'IBus connection lost' then
        SawLost := True;
    until (SawLost and (IB.InputContextPath <> '')) or (GetTickCount64 - T0 > 5000);
    Check(SawLost, '切れたことに気づいた');
    Check(IB.InputContextPath <> '', '繋ぎ直した: ' + IB.InputContextPath + ' / ' + IB.LastNonFatalError);
    ResetCounts;
    TypeRomaji('a');
    Check(HaveComp and (LastComp.Text = 'あ'), '繋ぎ直した後も変換できる「' + LastComp.Text + '」');
    Tap($FF1B, 1);
    Settle;

    Ctx.TextInput.Stop;
    Settle(200);
    Check(Ctx.Events.DroppedCount = 0, 'イベントの取りこぼしなし');
    Check(IB.ForwardedKeyCount = 0, 'ForwardKeyEvent は来なかった');
  finally
    Ctx.Free;
    Ed.Free;
  end;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: IBus のバックエンドが本物の ibus-mozc と噛み合う ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
