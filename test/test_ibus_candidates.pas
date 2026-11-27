{
  test_ibus_candidates — IBus の候補一覧（UpdateLookupTable）を TextEditingCandidates にする規則

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    IBusLookupTable の読み取りと書き込みの往復、1 ページ分の候補・選択・配置への換算、
    IBus の能力値（候補を受けるときの IBUS_CAP_LOOKUP_TABLE）、候補の追跡（変わったときだけ出す）との
    組み合わせを、作った値で見る。

  WHY:
    IBusLookupTable は (s a{sv} u page_size, u cursor_pos, b cursor_visible, b round,
    i orientation, av candidates, av labels)（libibus 1.5.34 で ibus_serializable_serialize_object
    の出力を採った）。IBus は全候補を 1 つの表にして、ページの大きさとカーソルの位置（全体の中の番号）を
    添える。ibus-mozc のように 1 ページ分しか送らない IME もあるので、候補が page_size 以下ならそのまま
    1 ページとして扱う。本物のデーモンとの接着は test_ibus_candidates_live が見る。
    CI でも走る（libdbus はメッセージの組み立てと読み取りにだけ使い、どこにも繋がない）。

  実行前提: libdbus-1。
}
program test_ibus_candidates;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Platform.DBus,
  PaPiMeLa.TextInput.Backend,
  PaPiMeLa.TextInput.Fcitx,
  PaPiMeLa.TextInput.IBus;

var
  Failures: Integer = 0;

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

function L(const AItems: array of String): TPMLStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AItems));
  for I := 0 to High(AItems) do
    Result[I] := AItems[I];
end;

function Same(const A, B: TPMLStringArray): Boolean;
var
  I: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for I := 0 to High(A) do
      if A[I] <> B[I] then
        Exit(False);
end;

function MakeTable(APage, ACursor: LongWord; AVisible: Boolean; AOrientation: LongInt;
  const ACandidates: array of String): TPMLIBusLookupTable;
begin
  Result.PageSize := APage;
  Result.CursorPos := ACursor;
  Result.CursorVisible := AVisible;
  Result.Round := True;
  Result.Orientation := AOrientation;
  Result.Candidates := L(ACandidates);
end;

{ ページ分けの結果を 1 つの文字列にする（比べやすいように）。 }
function Page(const ATable: TPMLIBusLookupTable): String;
var
  Texts: TPMLStringArray;
  Index, Hint, I: Integer;
begin
  PMLIBusLookupPage(ATable, Texts, Index, Hint);
  Result := '';
  for I := 0 to High(Texts) do
    Result := Result + Texts[I] + ',';
  Result := Result + '|' + IntToStr(Index) + '|' + IntToStr(Hint);
end;

procedure TestRoundTrip;
var
  Conn: TPMLDBusConnection;
  Msg: PDBusMessage;
  W: TPMLDBusWriter;
  T, Back: TPMLIBusLookupTable;
  TX: TPMLIBusText;
begin
  WriteLn('1. IBusLookupTable の往復');
  Conn := TPMLDBusConnection.CreateOffline;
  try
    T := MakeTable(9, 4, True, 1, ['私', '渡し', '綿', '亘']);
    T.Round := False;
    Msg := Conn.BeginCall('a.b', '/a', 'a.b', 'M');
    try
      W := Conn.Writer(Msg);
      PMLWriteIBusLookupTable(W, T);
      W.AddBoolean(True);
      Check(PMLReadIBusLookupTable(Conn.Reader(Msg), Back), '書いたものを読める');
      Check((Back.PageSize = 9) and (Back.CursorPos = 4) and Back.CursorVisible
        and (not Back.Round) and (Back.Orientation = 1), '数・真偽・向きが戻る');
      Check(Same(Back.Candidates, T.Candidates), '候補の文字列が順に戻る');
    finally
      Conn.Unref(Msg);
    end;

    T := MakeTable(5, 0, False, 0, []);
    Msg := Conn.BeginCall('a.b', '/a', 'a.b', 'M');
    try
      W := Conn.Writer(Msg);
      PMLWriteIBusLookupTable(W, T);
      Check(PMLReadIBusLookupTable(Conn.Reader(Msg), Back) and (Length(Back.Candidates) = 0)
        and (not Back.CursorVisible) and (Back.Orientation = 0), '候補が空の表も往復する');
    finally
      Conn.Unref(Msg);
    end;

    // IBusText の variant や、型名の違う variant は読まない。
    Msg := Conn.BeginCall('a.b', '/a', 'a.b', 'M');
    try
      W := Conn.Writer(Msg);
      TX.Text := 'x';
      TX.Attributes := nil;
      PMLWriteIBusText(W, TX);
      Check(not PMLReadIBusLookupTable(Conn.Reader(Msg), Back), 'IBusText は IBusLookupTable として読まない');
    finally
      Conn.Unref(Msg);
    end;
    Msg := Conn.BeginCall('a.b', '/a', 'a.b', 'M');
    try
      W := Conn.Writer(Msg);
      W.AddUInt32(3);
      Check(not PMLReadIBusLookupTable(Conn.Reader(Msg), Back), 'variant でなければ断る');
    finally
      Conn.Unref(Msg);
    end;
  finally
    Conn.Free;
  end;
end;

procedure TestPage;
var
  Many: array of String;
  I: Integer;
begin
  WriteLn;
  WriteLn('2. 1 ページ分への換算');
  Check(Page(MakeTable(9, 1, True, 1, ['a', 'b', 'c'])) = 'a,b,c,|1|1',
    '1 ページに収まる表はそのまま。縦（orientation 1）は fcitx5 の縦（hint 1）');
  Check(Page(MakeTable(9, 0, True, 0, ['a', 'b'])) = 'a,b,|0|2', '横（orientation 0）は fcitx5 の横（hint 2）');
  Check(Page(MakeTable(9, 0, True, 2, ['a', 'b'])) = 'a,b,|0|0', 'システム（orientation 2）は未指定（hint 0）');
  Check(Page(MakeTable(9, 1, False, 1, ['a', 'b', 'c'])) = 'a,b,c,|-1|1', 'cursor_visible が偽なら選択なし（-1）');
  Check(Page(MakeTable(9, 7, True, 1, ['a', 'b'])) = 'a,b,|-1|1', '範囲の外のカーソルは選択なし');

  // 全体を 1 つの表にして送る IME: ページの大きさごとに切る。
  SetLength(Many, 12);
  for I := 0 to 11 do
    Many[I] := Chr(Ord('a') + I);
  Check(Page(MakeTable(5, 0, True, 1, Many)) = 'a,b,c,d,e,|0|1', '12 個・5 個ずつ: 先頭ページ');
  Check(Page(MakeTable(5, 4, True, 1, Many)) = 'a,b,c,d,e,|4|1', '先頭ページの末尾（4）');
  Check(Page(MakeTable(5, 5, True, 1, Many)) = 'f,g,h,i,j,|0|1', '5 番はつぎのページの先頭（0）');
  Check(Page(MakeTable(5, 8, True, 1, Many)) = 'f,g,h,i,j,|3|1', '8 番はつぎのページの 3');
  Check(Page(MakeTable(5, 11, True, 1, Many)) = 'k,l,|1|1', '最後のページは端数だけ（11 番は 1）');
  Check(Page(MakeTable(5, 12, True, 1, Many)) = 'a,b,c,d,e,|-1|1', '範囲の外のカーソルは先頭ページで選択なし');
  Check(Page(MakeTable(0, 3, True, 1, Many)) = 'a,b,c,d,e,f,g,h,i,j,k,l,|3|1', 'page_size が 0 なら切らない');
end;

procedure TestCapabilities;
const
  C = TPMLImeUIElement.Composition;
  D = TPMLImeUIElement.Candidates;
begin
  WriteLn;
  WriteLn('3. IBus の能力値');
  Check((PMLIBusCapabilities([C]) = 41) and (PMLIBusCapabilities([]) = 40),
    'candidates が無ければ今までの値（41 / 40）');
  Check((PMLIBusCapabilities([D]) = 44) and (PMLIBusCapabilities([C, D]) = 45),
    'candidates は LOOKUP_TABLE（1 shl 2）を足す（44 / 45）');
end;

procedure TestTracker;
var
  Tr: TPMLFcitxCandidateTracker;
  Texts: TPMLStringArray;
  Index, Hint, Sel: Integer;
  Hor: Boolean;
  T: TPMLIBusLookupTable;
begin
  WriteLn;
  WriteLn('4. 追跡と組み合わせる（同じ表は重ねて出さない）');
  Tr := TPMLFcitxCandidateTracker.Create;
  try
    T := MakeTable(9, 0, True, 0, ['a', 'b', 'c']);
    PMLIBusLookupPage(T, Texts, Index, Hint);
    Check(Tr.Update(Texts, Index, Hint, Sel, Hor) and (Sel = 0) and Hor, '最初は出す（選択 0・横）');
    PMLIBusLookupPage(T, Texts, Index, Hint);
    Check(not Tr.Update(Texts, Index, Hint, Sel, Hor), '同じ表は出さない');
    T.CursorPos := 2;
    PMLIBusLookupPage(T, Texts, Index, Hint);
    Check(Tr.Update(Texts, Index, Hint, Sel, Hor) and (Sel = 2), '選択が動いたら出す');
    T.Candidates := nil;
    PMLIBusLookupPage(T, Texts, Index, Hint);
    Check(Tr.Update(Texts, Index, Hint, Sel, Hor) and (Length(Texts) = 0), '空になったら空を出す');
  finally
    Tr.Free;
  end;
end;

begin
  WriteLn('test_ibus_candidates — IBus の候補一覧');
  WriteLn;
  TestRoundTrip;
  TestPage;
  TestCapabilities;
  TestTracker;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: IBus の候補一覧を 1 ページ分の候補・選択・配置にできる ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
