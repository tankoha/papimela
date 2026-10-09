{
  test_drop — ドラッグ＆ドロップの公開側（イベントの順序と URI の変換）を検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    TPMLDropState（Ctx.Events.Drop）の約束: 落とし始めの DropBegin は最初の 1 回だけ、
    位置は最後の DropPosition のものが載る、DropComplete で戻る、ウィンドウごとに独立、
    無効にした種類は DropBegin も積まない。PMLURIToLocalPath と PMLURIListToLocalPaths
    の変換表（SDL_URIToLocal の約束と、papimela が足した「注釈と相対は捨てる」）。

  WHY:
    実際のドラッグ＆ドロップは人の操作が要る（demo_drop で見る）。順序と変換は
    表示サーバ無しで固めておく。

  実行前提: 無し。
}
program test_drop;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, Unix,
  PaPiMeLa.Events,
  PaPiMeLa.Events.Drop,
  PaPiMeLa.Core;

var
  Failures: Integer = 0;
  Ctx: TPMLContext;

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

{ 積まれたドロップのイベントを「種類(窓,x,y)[文字列]」の並びにする。
  B = Begin、F = File、T = Text、P = Position、C = Complete。 }
function Take: String;
var
  Ev: TPMLEvent;
  K: String;
begin
  Result := '';
  while Ctx.Events.Poll(Ev) do
  begin
    case Ev.Kind of
      TPMLEventKind.DropBegin:    K := 'B';
      TPMLEventKind.DropFile:     K := 'F';
      TPMLEventKind.DropText:     K := 'T';
      TPMLEventKind.DropPosition: K := 'P';
      TPMLEventKind.DropComplete: K := 'C';
    else
      Continue;
    end;
    Result := Result + Format('%s%d', [K, Ev.WindowID]);
    if K <> 'B' then
      Result := Result + Format('(%g,%g)', [Ev.Drop.X, Ev.Drop.Y]);
    if Ev.Text <> '' then
      Result := Result + '[' + Ev.Text + ']';
    Result := Result + ' ';
  end;
  Result := Trim(Result);
end;

procedure TestOrder;
var
  D: TPMLDropState;
  S: String;
begin
  WriteLn('1. イベントの順序');
  D := Ctx.Events.Drop;
  Check(not D.IsDropping(1), '最初は落とし中でない');
  D.SendPosition(1, 10, 20);
  S := Take;
  Check(S = 'B1 P1(10,20)', '最初の位置の前に DropBegin（' + S + '）');
  Check(D.IsDropping(1), '落とし中になる');
  D.SendPosition(1, 15, 25);
  D.SendFile(1, '/tmp/a.txt');
  D.SendFile(1, '/tmp/b c.png');
  S := Take;
  Check(S = 'P1(15,25) F1(15,25)[/tmp/a.txt] F1(15,25)[/tmp/b c.png]',
    'DropBegin は 1 回だけ、ファイルには最後の位置が載る（' + S + '）');
  D.SendComplete(1);
  S := Take;
  Check((S = 'C1(15,25)') and not D.IsDropping(1), 'DropComplete で落とし中が戻る（' + S + '）');

  D.SendText(1, 'hello');
  D.SendComplete(1);
  S := Take;
  Check(S = 'B1 T1(0,0)[hello] C1(0,0)', '次の落とし始めはまた DropBegin、位置は 0 に戻っている（' + S + '）');

  WriteLn;
  WriteLn('2. ウィンドウごと');
  D.SendPosition(1, 1, 1);
  D.SendPosition(2, 2, 2);
  D.SendFile(2, '/x');
  D.SendComplete(1);
  D.SendFile(1, '/y');
  S := Take;
  Check(S = 'B1 P1(1,1) B2 P2(2,2) F2(2,2)[/x] C1(1,1) B1 F1(0,0)[/y]',
    'ウィンドウごとに DropBegin と位置を持つ（' + S + '）');
  D.SendComplete(1);
  D.SendComplete(2);
  Take;

  WriteLn;
  WriteLn('3. 無効にした種類');
  Ctx.Events.SetEnabled(TPMLEventKind.DropFile, False);
  D.SendFile(3, '/z');
  S := Take;
  Check((S = '') and not D.IsDropping(3), '無効な種類は DropBegin も積まない（' + S + '）');
  Ctx.Events.SetEnabled(TPMLEventKind.DropFile, True);
  D.SendFile(3, '/z');
  D.SendComplete(3);
  S := Take;
  Check(S = 'B3 F3(0,0)[/z] C3(0,0)', '有効に戻せば積む（' + S + '）');
  WriteLn;
end;

procedure CheckURI(const AURI: String; AExpectOk: Boolean; const AExpectPath: String);
var
  P: String;
  Ok: Boolean;
begin
  Ok := PMLURIToLocalPath(AURI, P);
  if AExpectOk then
    Check(Ok and (P = AExpectPath), Format('"%s" → "%s"（%s "%s"）', [AURI, AExpectPath, BoolToStr(Ok, 'True', 'False'), P]))
  else
    Check(not Ok, Format('"%s" はローカルでない（%s）', [AURI, BoolToStr(Ok, 'True', 'False')]));
end;

procedure TestURI;
var
  Host: String;
  L: TStringArray;
begin
  WriteLn('4. URI → ローカルのパス');
  CheckURI('file:///tmp/a.txt', True, '/tmp/a.txt');
  CheckURI('file:/tmp/a.txt', True, '/tmp/a.txt');
  CheckURI('file://localhost/tmp/a.txt', True, '/tmp/a.txt');
  CheckURI('file://LocalHost/tmp/a.txt', True, '/tmp/a.txt');
  Host := GetHostName;
  if Host <> '' then
  begin
    CheckURI('file://' + Host + '/tmp/h.txt', True, '/tmp/h.txt');
    CheckURI('file://' + UpperCase(Host) + '/tmp/h.txt', True, '/tmp/h.txt');
  end;
  CheckURI('file://otherhost.invalid/tmp/a.txt', False, '');
  CheckURI('http://example.com/a.txt', False, '');
  CheckURI('smb://server/share', False, '');
  CheckURI('file:///tmp/a%20b.txt', True, '/tmp/a b.txt');
  CheckURI('file:///tmp/%E3%81%82.txt', True, '/tmp/あ.txt');
  CheckURI('file:///tmp/100%25', True, '/tmp/100%');
  CheckURI('file:///tmp/bad%zzescape', True, '/tmp/bad%zzescape');
  CheckURI('file:///tmp/trailing%4', True, '/tmp/trailing%4');
  // papimela が足した: スキームの無い文字列は捨てる（SDL は相対のとき先頭より前を読む）。
  CheckURI('tmp/relative', False, '');
  CheckURI('/tmp/absolute-without-scheme', False, '');
  CheckURI('', False, '');

  WriteLn;
  WriteLn('5. text/uri-list');
  L := PMLURIListToLocalPaths('file:///tmp/a%20b' + #13#10 + 'file:///tmp/c' + #13#10 +
    '# comment' + #13#10 + #13#10 + 'http://x/y' + #10 + 'file://otherhost.invalid/z' + #10 +
    'file:///tmp/last');
  Check((Length(L) = 3) and (L[0] = '/tmp/a b') and (L[1] = '/tmp/c') and (L[2] = '/tmp/last'),
    Format('ローカルのファイルだけが順に 3 つ（%d: %s）', [Length(L), String.Join(' | ', L)]));
  L := PMLURIListToLocalPaths('');
  Check(Length(L) = 0, '空なら何も無い');
  L := PMLURIListToLocalPaths('file:///only' + #13#10);
  Check((Length(L) = 1) and (L[0] = '/only'), '最後の改行はあっても無くてもよい');
  WriteLn;
end;

begin
  WriteLn('test_drop — ドラッグ＆ドロップの公開側');
  WriteLn;
  Ctx := TPMLContext.Create([]);
  try
    TestOrder;
    TestURI;
  finally
    Ctx.Free;
  end;
  if Failures = 0 then
    WriteLn('=== 結論: ドロップのイベントの順序と URI の変換が約束どおり ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
