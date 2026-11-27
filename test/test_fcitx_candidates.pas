{
  test_fcitx_candidates — fcitx5 の埋め込み候補（UpdateClientSideUI）を TextEditingCandidates にする規則

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 能力: ヒント PAPIMELA_IME_IMPLEMENTED_UI に candidates があれば、fcitx5 の SetCapability に
       ClientSideUI（1 shl 39）を足す。実測（spikes の fcitx5 + mozc）: このビットを立てると
       UpdateClientSideUI(a(si) preedit, i cursor, a(si) auxUp, a(si) auxDown, a(ss) candidates,
       i candidateIndex, i layoutHint, b hasPrev, b hasNext) が届き、立てなければ届かない
    2. 追跡（TPMLFcitxCandidateTracker）: fcitx5 は入力のたびに同じ候補欄を何度も送るので、前に出したものと
       比べて、変わったときだけイベントを出す。空のままなら出さない。空でなかったものが空になったら
       空の一覧を出す（SDL の Windows 版が候補を消すときに送る NULL・0・-1 に当たる）。選択の番号は
       範囲の外なら -1。配置は CandidateLayoutHint が 2（横）のときだけ横

  WHY:
    SDL は Linux では TextEditingCandidates を出さない（Windows だけ）。papimela はアプリが自分で候補の窓を描ける
    ように、fcitx5 の候補欄を渡す（SDL にない拡張）。D-Bus の読み取りの部分は薄い接着で、実機の fcitx5 で
    確かめる（test_fcitx_textinput の候補の節。手元専用）。ここは表示サーバも D-Bus も要らない。
}
program test_fcitx_candidates;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Events,
  PaPiMeLa.TextInput.Backend,
  PaPiMeLa.TextInput.Fcitx;

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

procedure TestCapabilities;
const
  C = TPMLImeUIElement.Composition;
  D = TPMLImeUIElement.Candidates;
  CSUI = QWord(1) shl 39;
begin
  WriteLn('1 能力');
  Check(PMLFcitxCapabilities([]) = 64, 'どちらも無ければ周辺テキストの 64 だけ');
  Check(PMLFcitxCapabilities([C]) = 82, 'composition は 82（今まで送っていた値。変えない）');
  Check(PMLFcitxCapabilities([D]) = 64 + CSUI, 'candidates は ClientSideUI（1 shl 39）を足す');
  Check(PMLFcitxCapabilities([C, D]) = 82 + CSUI, '両方なら 82 に ClientSideUI');
  Check(CSUI = QWord($8000000000), 'ClientSideUI は 39 ビット目（実測）');
end;

procedure TestTracker;
var
  T: TPMLFcitxCandidateTracker;
  Sel: Integer;
  Hor: Boolean;
begin
  WriteLn('2 追跡');
  T := TPMLFcitxCandidateTracker.Create;
  try
    Check(not T.HasCandidates, '最初は候補が無い');
    Check(not T.Update(L([]), -1, 0, Sel, Hor), '最初の空の欄は出さない');
    Check(not T.Update(L([]), 3, 2, Sel, Hor), '空のままなら、番号や配置が変わっても出さない');
    Check(not T.Clear, '最初の Clear は出さない（まだ何も出していない）');

    Check(T.Update(L(['私の', '渡しの']), 0, 1, Sel, Hor), '候補が来たら出す');
    Check((Sel = 0) and not Hor, '選択は 0、配置は縦（hint 1）');
    Check(T.HasCandidates, '候補がある');
    Check(not T.Update(L(['私の', '渡しの']), 0, 1, Sel, Hor), '同じ内容は出さない');
    Check(not T.Update(L(['私の', '渡しの']), 0, 1, Sel, Hor), '何度来ても出さない');

    Check(T.Update(L(['私の', '渡しの']), 1, 1, Sel, Hor) and (Sel = 1), '選択の番号が変わったら出す');
    Check(T.Update(L(['私の', '渡しの']), 1, 2, Sel, Hor) and Hor, '配置が横（hint 2）に変わったら出す');
    Check(not T.Update(L(['私の', '渡しの']), 1, 2, Sel, Hor), '横のままなら出さない');
    Check(T.Update(L(['私の', '渡しの', '私に']), 1, 2, Sel, Hor), '候補の数が変わったら出す');
    Check(T.Update(L(['私の', '渡しの', '私は']), 1, 2, Sel, Hor), '候補の文字列が変わったら出す（同じ数でも）');
    Check(T.Update(L(['私の', '渡しの', '私は']), 1, 0, Sel, Hor) and not Hor, '配置が未指定（hint 0）なら縦で、変わったら出す');
    Check(T.Update(L(['私の', '渡しの', '私は']), 1, 7, Sel, Hor) = False, 'hint 0 と 7 はどちらも縦なので出さない');
    Check(T.Update(L(['私の', '渡しの', '私は']), -1, 1, Sel, Hor) and (Sel = -1), '選択が無い（-1）に変わったら出す');
    Check(T.Update(L(['私の', '渡しの', '私は']), 3, 1, Sel, Hor) = False, '範囲の外の番号（3）は -1 と同じなので出さない');
    Check(T.Update(L(['私の', '渡しの', '私は']), 99, 1, Sel, Hor) = False, '範囲の外の番号（99）も同じ');
    Check(T.Update(L(['私の', '渡しの', '私は']), 2, 1, Sel, Hor) and (Sel = 2), '最後の番号（2）は範囲の内');
    Check(T.Update(L(['私の', '渡しの', '私は']), -5, 1, Sel, Hor) and (Sel = -1), '負の番号は -1');

    Check(T.Update(L([]), -1, 1, Sel, Hor), '候補が消えたら（空の欄）出す');
    Check((Sel = -1) and not Hor, '空の一覧は選択 -1、配置は縦');
    Check(not T.HasCandidates, '消えた');
    Check(not T.Update(L([]), -1, 1, Sel, Hor), '消えた後の空の欄は出さない');
  finally
    T.Free;
  end;
end;

procedure TestClear;
var
  T: TPMLFcitxCandidateTracker;
  Sel: Integer;
  Hor: Boolean;
begin
  WriteLn('3 Clear');
  T := TPMLFcitxCandidateTracker.Create;
  try
    T.Update(L(['あ']), 0, 1, Sel, Hor);
    Check(T.Clear, '候補があれば Clear は出す（空の一覧）');
    Check(not T.HasCandidates, 'Clear の後は候補が無い');
    Check(not T.Clear, '2 度目の Clear は出さない');
    Check(T.Update(L(['あ']), 0, 1, Sel, Hor), 'Clear の後、同じ候補が来たらまた出す（忘れている）');
    Check(not T.Update(L(['あ']), 0, 1, Sel, Hor), 'その後の同じ内容は出さない');
    // 横の候補を出した後の Clear の後は、配置も忘れる
    T.Update(L(['あ']), 0, 2, Sel, Hor);
    T.Clear;
    Check(T.Update(L(['あ']), 0, 2, Sel, Hor) and Hor, 'Clear の後は配置も忘れる');
  finally
    T.Free;
  end;
end;

begin
  WriteLn('=== test_fcitx_candidates ===');
  TestCapabilities;
  TestTracker;
  TestClear;
  WriteLn;
  if Failures = 0 then
    WriteLn('ALL PASSED')
  else
    WriteLn('FAILED: ', Failures);
  if Failures <> 0 then
    Halt(1);
end.
