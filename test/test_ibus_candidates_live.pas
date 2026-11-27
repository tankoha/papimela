{
  test_ibus_candidates_live — IBus の埋め込み候補（UpdateLookupTable）が TextEditingCandidates で届く（ibus-mozc）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    ヒント PAPIMELA_IME_IMPLEMENTED_UI を "composition,candidates" にして Context を作り、ローマ字で
    「わたしのなまえは」を入力してスペースで変換し、ibus-mozc の UpdateLookupTable が
    TextEditingCandidates になって届くかを確かめる:
    1. 候補が 1 つ以上ある TextEditingCandidates が届く（Strings に候補、Edit.FocusedSegment に選択の番号）
    2. 同じ内容は重ねて届かない（連続する 2 つのイベントは内容が違う）
    3. Enter で確定すると、空の一覧（候補が消えた）が最後に届く
    4. ヒントが既定（composition だけ）のときは、同じ操作で TextEditingCandidates が届かない

  WHY:
    SDL は Linux では TextEditingCandidates を出さない。papimela はアプリが自分で候補の窓を描けるように
    IBus の候補の表を渡す。test_ibus_candidates は規則（表の読み取り・ページ分け）だけを見るので、
    本物のデーモンが送る UpdateLookupTable の形と順序との接着をここで見る。

  実行前提: ibus-session の中（ibus-daemon と ibus-mozc が動いている）。CI ではランナーの上で直接
            （.github/workflows/lint.yml）、手元では tools/ibus-sandbox/run.sh。fcitx5 が IBus を装っている
            手元のデスクトップでは失敗する（それで正しい）。
}
program test_ibus_candidates_live;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Properties,
  PaPiMeLa.Events,
  PaPiMeLa.Events.Keymap,
  PaPiMeLa.TextInput,
  PaPiMeLa.Core,
  PaPiMeLa.Backends;

type
  TFakeEditor = class(TObject, IPMLTextInputClient)
  public
    function GetSurroundingText(out AText: String;
      out ACursorByte, AAnchorByte: Integer): Boolean;
    function GetCursorRect: TPMLRect;
  end;

function TFakeEditor.GetSurroundingText(out AText: String;
  out ACursorByte, AAnchorByte: Integer): Boolean;
begin
  AText := '';
  ACursorByte := 0;
  AAnchorByte := 0;
  Result := True;
end;

function TFakeEditor.GetCursorRect: TPMLRect;
begin
  Result := TPMLRect.Make(100, 200, 2, 18);
end;

var
  Failures: Integer = 0;
  Ctx: TPMLContext;
  Editor: TFakeEditor;
  Got: array of TPMLEvent;       // 届いた TextEditingCandidates

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

procedure Drain;
var
  Ev: TPMLEvent;
  I: Integer;
  S: String;
begin
  while Ctx.Events.Poll(Ev) do
    if Ev.Kind = TPMLEventKind.TextEditingCandidates then
    begin
      SetLength(Got, Length(Got) + 1);
      Got[High(Got)] := Ev;
      S := '';
      for I := 0 to High(Ev.Strings) do
        S := S + ' [' + Ev.Strings[I] + ']';
      WriteLn(Format('    TextEditingCandidates 選択=%d%s', [Ev.Edit.FocusedSegment, S]));
    end;
end;

{ 返信が全部届くまで回す（最大 AMs ミリ秒）。 }
procedure Settle(AMs: Integer = 1500);
var
  Start: QWord;
begin
  Start := GetTickCount64;
  repeat
    Ctx.Events.Pump(10);
    Drain;
  until ((Ctx.Events.Keyboard.DeferredCount = 0) and (GetTickCount64 - Start >= 150))
    or (GetTickCount64 - Start >= QWord(AMs));
  Ctx.Events.Pump(50);
  Drain;
end;

procedure Tap(AKeysym, AEvdev: LongWord; const AText: String = '');
var
  K: TPMLKeyEventData;
begin
  FillChar(K, SizeOf(K), 0);
  K.Keysym := AKeysym;
  K.Raw := AEvdev + 8;
  K.Scancode := PMLScancodeFromEvdev(AEvdev);
  Ctx.Events.Keyboard.SendKey(1, K, True, AText);
  Ctx.Events.Keyboard.SendKey(1, K, False, '');
end;

const
  EVDEV: array['a'..'z'] of LongWord = (
    30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50,
    49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44);

procedure TypeRomaji(const S: String);
var
  C: Char;
begin
  for C in S do
    Tap(Ord(C), EVDEV[C], C);
  Settle;
end;

function SameCandidates(const A, B: TPMLEvent): Boolean;
var
  I: Integer;
begin
  Result := (Length(A.Strings) = Length(B.Strings)) and (A.Edit.FocusedSegment = B.Edit.FocusedSegment);
  if Result then
    for I := 0 to High(A.Strings) do
      if A.Strings[I] <> B.Strings[I] then
        Exit(False);
end;

function NewContext(const AUI: String): TPMLContext;
var
  Opts: TPMLContextOptions;
begin
  Opts := TPMLContextOptions.Default;
  Opts.PreferredTextInput := 'ibus';
  if AUI <> '' then
    Opts.Hints.Add(PML_HINT_IME_IMPLEMENTED_UI, AUI);
  Result := TPMLContext.Create([TPMLSubsystem.TextInput], Opts);
end;

procedure RunOnce(const AUI: String; AExpectCandidates: Boolean);
var
  Session: TPMLTextInputSession;
  I, NonEmpty, Dups, Tries: Integer;
  LastWasEmpty: Boolean;
begin
  Got := nil;
  WriteLn;
  WriteLn('-- IME_IMPLEMENTED_UI = "', AUI, '"');
  try
    Ctx := NewContext(AUI);
  except
    on E: EPMLError do
    begin
      WriteLn('  [FAIL] Context を作れない: ', E.Message, '（IBus の隔離環境の中で動かすこと）');
      Inc(Failures);
      Exit;
    end;
  end;
  try
    Check(Ctx.TextInput.BackendName = 'ibus', Format('バックエンドは ibus（%s）', [Ctx.TextInput.BackendName]));
    Session := Ctx.TextInput.Start(nil, Editor as IPMLTextInputClient);
    Session.NotifyCursorRectChanged;
    Settle(300);
    TypeRomaji('watashinonamaeha');
    // 変換の候補の窓は 2 度目のスペースで出ることが多い。出るまで（3 回まで）押す
    Tries := 0;
    repeat
      Tap($20, 57);
      Settle;
      Inc(Tries);
    until (Length(Got) > 0) or (Tries >= 3) or not AExpectCandidates;
    NonEmpty := 0;
    Dups := 0;
    for I := 0 to High(Got) do
    begin
      if Length(Got[I].Strings) > 0 then
        Inc(NonEmpty);
      if (I > 0) and SameCandidates(Got[I], Got[I - 1]) then
        Inc(Dups);
    end;
    if AExpectCandidates then
    begin
      Check(Dups = 0, Format('連続する 2 つのイベントは内容が違う（%d 組が同じだった）', [Dups]));
      Check(NonEmpty >= 1, Format('候補つきの TextEditingCandidates が届く（%d 件）', [NonEmpty]));
      Got := nil;
      Tap($FF0D, 28);
      Settle;
      LastWasEmpty := (Length(Got) > 0) and (Length(Got[High(Got)].Strings) = 0);
      Check(LastWasEmpty, 'Enter で確定すると、空の一覧（候補が消えた）が最後に届く');
    end
    else
      Check(Length(Got) = 0, Format('既定（composition だけ）では TextEditingCandidates が届かない（%d 件）', [Length(Got)]));
    Session.ResetComposition;
    Settle(300);
  finally
    FreeAndNil(Ctx);
  end;
end;

begin
  WriteLn('=== test_ibus_candidates_live ===');
  Editor := TFakeEditor.Create;
  try
    RunOnce('composition,candidates', True);
    RunOnce('', False);
  finally
    FreeAndNil(Editor);
  end;
  WriteLn;
  if Failures = 0 then
    WriteLn('ALL PASSED')
  else
    WriteLn('FAILED: ', Failures);
  if Failures <> 0 then
    Halt(1);
end.
