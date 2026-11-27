{
  test_fcitx_candidates_live — fcitx5 の埋め込み候補が TextEditingCandidates で届く（実機。手元専用）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    ヒント PAPIMELA_IME_IMPLEMENTED_UI を "composition,candidates" にして Context を作り、ローマ字で
    「わたしのなまえ」を入力してスペースで変換し、fcitx5（mozc）の UpdateClientSideUI が
    TextEditingCandidates になって届くかを確かめる:
    1. 候補が 1 つ以上ある TextEditingCandidates が届く（Strings に候補、Edit.FocusedSegment に選択の番号）
    2. 同じ内容は重ねて届かない（連続する 2 つのイベントは内容が違う）
    3. Enter で確定すると、空の一覧（候補が消えた）が最後に届く（Escape は未変換へ戻るだけで、mozc は予測の候補を出し続ける）
    4. ヒントが既定（composition だけ）のときは、同じ操作で TextEditingCandidates が届かない

  WHY:
    SDL は Linux では TextEditingCandidates を出さない。papimela はアプリが自分で候補の窓を描けるように
    fcitx5 の候補欄を渡す。CI の test_fcitx_candidates は規則（追跡）だけを見るので、D-Bus の読み取りの
    接着を実機の fcitx5 で確かめる。

  実行前提: fcitx5 稼働、日本語エンジン（mozc）。手元専用。環境が無ければ PAPIMELA_FCITX_OPTIONAL=1 で飛ばす（既定では失敗）。
}
program test_fcitx_candidates_live;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Properties,
  PaPiMeLa.Events,
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

procedure SendKey(AKeysym, AKeycode: LongWord);
var
  K: TPMLKeyEventData;
begin
  FillChar(K, SizeOf(K), 0);
  K.Keysym := AKeysym;
  K.Raw := AKeycode;
  K.Modifiers := [];
  Ctx.TextInput.FilterKey(K, False, 0);
  Ctx.TextInput.FilterKey(K, True, 0);
  Ctx.Events.Pump(30);
  Drain;
end;

const
  Keys: array[0..13] of array[0..1] of LongWord = (
    ($77, 25), ($61, 38), ($74, 28), ($61, 38), ($73, 39), ($68, 43), ($69, 31),
    ($6E, 57), ($6F, 32), ($6E, 57), ($61, 38), ($6D, 58), ($61, 38), ($65, 26)
  );
  SPACE_SYM = $20;
  SPACE_CODE = 65;
  ENTER_SYM = $FF0D;
  ENTER_CODE = 36;

function NewContext(const AUI: String): TPMLContext;
var
  Opts: TPMLContextOptions;
begin
  Opts := TPMLContextOptions.Default;
  if AUI <> '' then
    Opts.Hints.Add(PML_HINT_IME_IMPLEMENTED_UI, AUI);
  Result := TPMLContext.Create([TPMLSubsystem.TextInput], Opts);
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

procedure TypeAndConvert;
var
  I: Integer;
begin
  for I := Low(Keys) to High(Keys) do
    SendKey(Keys[I][0], Keys[I][1]);
  SendKey(SPACE_SYM, SPACE_CODE);
  Ctx.Events.Pump(400);
  Drain;
  SendKey(SPACE_SYM, SPACE_CODE);   // 2 度目のスペースで候補の窓が出る
  Ctx.Events.Pump(400);
  Drain;
end;

procedure RunOnce(const AUI: String; AExpectCandidates: Boolean);
var
  Session: TPMLTextInputSession;
  I, NonEmpty, Dups: Integer;
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
      WriteLn('  Context を作れない: ', E.Message);
      if GetEnvironmentVariable('PAPIMELA_FCITX_OPTIONAL') = '1' then
      begin
        WriteLn('  飛ばす（PAPIMELA_FCITX_OPTIONAL=1）');
        Halt(0);
      end;
      Inc(Failures);
      Exit;
    end;
  end;
  try
    Check(Ctx.TextInput.BackendName = 'fcitx', Format('バックエンドは fcitx（%s）', [Ctx.TextInput.BackendName]));
    Session := Ctx.TextInput.Start(nil, Editor as IPMLTextInputClient);
    Session.NotifyCursorRectChanged;
    Ctx.Events.Pump(100);
    Drain;
    TypeAndConvert;
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
      Check(Dups = 0, Format('連続する 2 つのイベントは内容が違う（同じ内容が重ねて届かない。%d 組が同じだった）', [Dups]));
      Check(NonEmpty >= 1, Format('候補つきの TextEditingCandidates が届く（%d 件）', [NonEmpty]));
      // Escape は変換を未変換へ戻すだけで、mozc は予測の候補を出し続ける（実測）。候補が消えるのは確定のとき
      Got := nil;
      SendKey(ENTER_SYM, ENTER_CODE);
      Ctx.Events.Pump(300);
      Drain;
      LastWasEmpty := (Length(Got) > 0) and (Length(Got[High(Got)].Strings) = 0);
      Check(LastWasEmpty, 'Enter で確定すると、空の一覧（候補が消えた）が最後に届く');
    end
    else
      Check(Length(Got) = 0, Format('既定（composition だけ）では TextEditingCandidates が届かない（%d 件）', [Length(Got)]));
    Session.ResetComposition;
    Ctx.Events.Pump(100);
    Drain;
  finally
    FreeAndNil(Ctx);
  end;
end;

begin
  WriteLn('=== test_fcitx_candidates_live ===');
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
