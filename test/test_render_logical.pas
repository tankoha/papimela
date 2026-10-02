{
  test_render_logical — 拡大率・論理解像度・DebugText

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    TPMLRenderer の Scale、SetLogicalPresentation（5 つの当てはめ方）、
    ウィンドウ座標との変換、DebugText を、ソフトウェアのドライバで描いた
    画素で確かめる。

  WHY:
    論理解像度は Pong を書いて足りなかった F-4、文字は F-5。どちらもアプリが
    自分で計算していた変換を肩代わりするので、**変換の結果を画素の集合で
    丸ごと比べる**。期待する絵はテスト側で別に組み立てる（矩形を塗る、
    字形のビットを置く）。角の数画素だけ見る検査は、ずれた実装を通す。

    当てはめの矩形は SDL_render.c の UpdateLogicalPresentation の式から手で
    求めた値と比べる。floor が効く値（7x3 を 80x40 へ）と、整数倍が 1 倍未満に
    なる値（100x100 を 80x40 へ）を入れてある。

    線は、論理解像度のもとでは三角形（SDL の geometry の線）、拡大率だけなら
    矩形の並び（SDL の RenderLinesWithRectsF）で描く。どちらも閉じた折れ線の
    始点を二重に塗らない工夫がある。**半透明で描き、全画素が同じ色に
    なること**でそれを見る（二重に塗った画素だけ濃くなる）。

    DebugText の字形は SDL_render_debug_font.h のコメントの絵から書き写した
    ものと比べる（生成器が写した表とは別の道筋）。161 以上の文字は
    SDL と違う（D-42）。

  実行前提: 無し。ウィンドウの大きさの追従はダミーのビデオで見る。
}
program test_render_logical;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Video,
  PaPiMeLa.Render,
  PaPiMeLa.Core;

const
  OutW = 80;
  OutH = 40;

var
  Failures: Integer = 0;
  BG, FG  : TPMLColor;

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

function SameColor(const A, B: TPMLColor): Boolean;
begin
  Result := (A.R = B.R) and (A.G = B.G) and (A.B = B.B) and (A.A = B.A);
end;

function SameF(A, B: Single): Boolean;
begin
  Result := Abs(A - B) < 0.001;
end;

function SameFRect(const A: TPMLFRect; AX, AY, AW, AH: Single): Boolean;
begin
  Result := SameF(A.X, AX) and SameF(A.Y, AY) and SameF(A.W, AW) and SameF(A.H, AH);
end;

function FRectStr(const A: TPMLFRect): String;
begin
  Result := Format('(%g, %g, %g, %g)', [A.X, A.Y, A.W, A.H]);
end;

{ ---- 期待する絵 ---- }

function NewExpected: TPMLSurface;
begin
  Result := TPMLSurface.Create(OutW, OutH, PML_PIXELFORMAT_ARGB8888);
  Result.Fill(BG);
end;

// [X1, X2) x [Y1, Y2) を AColor で塗る。出力の外は捨てる。
procedure Paint(AWant: TPMLSurface; AX1, AY1, AX2, AY2: Integer; const AColor: TPMLColor);
var
  X, Y: Integer;
begin
  for Y := AY1 to AY2 - 1 do
    for X := AX1 to AX2 - 1 do
      AWant.WritePixel(X, Y, AColor);
end;

{ 実際と期待を全画素で比べる。違えば最初の 1 画素を見せる。 }
procedure Compare(AGot, AWant: TPMLSurface; const ALabel: String);
var
  X, Y, N, FX, FY: Integer;
  G, W: TPMLColor;
begin
  N := 0;
  FX := -1;
  FY := -1;
  for Y := 0 to AWant.Height - 1 do
    for X := 0 to AWant.Width - 1 do
      if not SameColor(AGot.ReadPixel(X, Y), AWant.ReadPixel(X, Y)) then
      begin
        if N = 0 then
        begin
          FX := X;
          FY := Y;
        end;
        Inc(N);
      end;
  if N = 0 then
    Check(True, ALabel)
  else
  begin
    G := AGot.ReadPixel(FX, FY);
    W := AWant.ReadPixel(FX, FY);
    Check(False, Format('%s（%d 画素違う。最初は (%d, %d) が %d,%d,%d で、期待は %d,%d,%d）',
      [ALabel, N, FX, FY, G.R, G.G, G.B, W.R, W.G, W.B]));
  end;
end;

{ ---- 字形（SDL_render_debug_font.h のコメントの絵を書き写したもの） ----

  1 行 8 文字、'1' が塗る画素。左から右へ。 }
type
  TGlyphRows = array[0..7] of String;

const
  GlyphA: TGlyphRows = (
    '00110000', '01111000', '11001100', '11001100',
    '11111100', '11001100', '11001100', '00000000');
  GlyphQuestion: TGlyphRows = (
    '01111000', '11001100', '00001100', '00011000',
    '00110000', '00000000', '00110000', '00000000');
  GlyphAt: TGlyphRows = (
    '01111100', '11000110', '11011110', '11011110',
    '11011110', '11000000', '01111000', '00000000');
  GlyphEAcute: TGlyphRows = (
    '00011100', '00000000', '01111000', '11001100',
    '11111100', '11000000', '01111000', '00000000');
  // 字形の無い文字の印。ヘッダのコメントの絵はこれだけ左右逆に書かれているので、
  // SDL で実際に描いた絵から写した（1 行目の左端が塗られる）。
  GlyphMissing: TGlyphRows = (
    '10101010', '01010101', '10101010', '01010101',
    '10101010', '01010101', '10101010', '01010101');

// 字形を (AX, AY) に、1 ビットを AScale 画素四方で置く。
procedure PaintGlyph(AWant: TPMLSurface; const AGlyph: TGlyphRows;
  AX, AY, AScale: Integer; const AColor: TPMLColor);
var
  Row, Col: Integer;
begin
  for Row := 0 to 7 do
    for Col := 0 to 7 do
      if AGlyph[Row][Col + 1] = '1' then
        Paint(AWant, AX + Col * AScale, AY + Row * AScale,
          AX + (Col + 1) * AScale, AY + (Row + 1) * AScale, AColor);
end;

{ ---- 場面 ---- }

var
  Target, Want: TPMLSurface;
  R: TPMLRenderer;

procedure Start;
begin
  R.SetLogicalPresentation(0, 0, TPMLLogicalPresentation.Disabled);
  R.Scale := TPMLFPoint.Make(1, 1);
  R.Viewport := TPMLRect.Make(0, 0, 0, 0);
  R.ClipRect := TPMLRect.Make(0, 0, 0, 0);
  R.BlendMode := TPMLBlendMode.None;
  R.DrawColor := BG;
  R.Clear;
  R.DrawColor := FG;
  FreeAndNil(Want);
  Want := NewExpected;
end;

procedure Finish(const ALabel: String);
begin
  R.Flush;
  Compare(Target, Want, ALabel);
end;

procedure TestFitRects;
var
  W, H: Integer;
  M: TPMLLogicalPresentation;
  Rc: TPMLFRect;

  procedure Fit(ALW, ALH: Integer; AMode: TPMLLogicalPresentation;
    AX, AY, AW, AH: Single; const ALabel: String);
  begin
    R.SetLogicalPresentation(ALW, ALH, AMode);
    Rc := R.LogicalPresentationRect;
    Check(SameFRect(Rc, AX, AY, AW, AH),
      Format('%s: %s（期待 (%g, %g, %g, %g)）', [ALabel, FRectStr(Rc), AX, AY, AW, AH]));
  end;

begin
  WriteLn('1. 当てはめの矩形（出力 80x40）');
  Start;
  Rc := R.LogicalPresentationRect;
  Check(SameFRect(Rc, 0, 0, OutW, OutH), 'Disabled は出力全体: ' + FRectStr(Rc));
  Fit(20, 20, TPMLLogicalPresentation.Letterbox, 20, 0, 40, 40, 'Letterbox 20x20 は左右に帯');
  Fit(40, 10, TPMLLogicalPresentation.Letterbox, 0, 10, 80, 20, 'Letterbox 40x10 は上下に帯');
  Fit(7, 3, TPMLLogicalPresentation.Letterbox, 0, 3, 80, 34, 'Letterbox 7x3 は高さを floor する');
  Fit(20, 20, TPMLLogicalPresentation.Overscan, 0, -20, 80, 80, 'Overscan 20x20 は上下がはみ出る');
  Fit(40, 10, TPMLLogicalPresentation.Overscan, -40, 0, 160, 40, 'Overscan 40x10 は左右がはみ出る');
  Fit(20, 20, TPMLLogicalPresentation.Stretch, 0, 0, 80, 40, 'Stretch は出力全体');
  Fit(30, 15, TPMLLogicalPresentation.IntegerScale, 10, 5, 60, 30, 'IntegerScale 30x15 は 2 倍');
  Fit(13, 10, TPMLLogicalPresentation.IntegerScale, 14, 0, 52, 40, 'IntegerScale 13x10 は 4 倍');
  Fit(100, 100, TPMLLogicalPresentation.IntegerScale, -10, -30, 100, 100,
    'IntegerScale は 1 倍未満にしない');
  Fit(40, 20, TPMLLogicalPresentation.Letterbox, 0, 0, 80, 40, '縦横比が同じなら帯は無い');

  R.SetLogicalPresentation(20, 30, TPMLLogicalPresentation.Overscan);
  R.GetLogicalPresentation(W, H, M);
  Check((W = 20) and (H = 30) and (M = TPMLLogicalPresentation.Overscan),
    'GetLogicalPresentation は設定を返す');
  R.SetLogicalPresentation(20, 30, TPMLLogicalPresentation.Disabled);
  R.GetLogicalPresentation(W, H, M);
  Check((W = 0) and (H = 0) and (M = TPMLLogicalPresentation.Disabled),
    'Disabled にすると大きさは 0 に戻る（SDL と同じ）');
end;

procedure TestFill;
begin
  WriteLn;
  WriteLn('2. 塗りの変換');

  Start;
  R.SetLogicalPresentation(20, 20, TPMLLogicalPresentation.Letterbox);
  R.FillRect(TPMLFRect.Make(1, 2, 3, 4));
  Paint(Want, 22, 4, 28, 12, FG);
  Finish('Letterbox: 論理 (1,2,3,4) → 画素 [22,28) x [4,12)。帯は Clear の色');

  Start;
  R.SetLogicalPresentation(20, 20, TPMLLogicalPresentation.Overscan);
  R.FillRect(TPMLFRect.Make(0, 5, 2, 2));
  R.FillRect(TPMLFRect.Make(0, 0, 1, 1));   // 出力の上へはみ出て見えない
  Paint(Want, 0, 0, 8, 8, FG);
  Finish('Overscan: 論理 y=5 が出力の y=0 に来る');

  Start;
  R.SetLogicalPresentation(20, 20, TPMLLogicalPresentation.Stretch);
  R.FillRect(TPMLFRect.Make(1, 1, 2, 2));
  Paint(Want, 4, 2, 12, 6, FG);
  Finish('Stretch: 横 4 倍、縦 2 倍');

  Start;
  R.Scale := TPMLFPoint.Make(2, 3);
  R.FillRect(TPMLFRect.Make(1, 1, 2, 2));
  Paint(Want, 2, 3, 6, 9, FG);
  Finish('Scale (2, 3) だけ');

  Start;
  R.SetLogicalPresentation(20, 20, TPMLLogicalPresentation.Letterbox);
  R.Scale := TPMLFPoint.Make(2, 2);
  R.FillRect(TPMLFRect.Make(1, 1, 1, 1));
  Paint(Want, 24, 4, 28, 8, FG);
  Finish('Scale と論理解像度は掛け合わさる');

  Start;
  R.SetLogicalPresentation(20, 20, TPMLLogicalPresentation.Letterbox);
  R.Viewport := TPMLRect.Make(2, 3, 5, 5);
  R.FillRect(TPMLFRect.Make(0, 0, 1, 1));
  R.FillRect(TPMLFRect.Make(3, 3, 100, 100));
  Paint(Want, 24, 6, 26, 8, FG);
  Paint(Want, 30, 12, 34, 16, FG);
  Finish('ビューポートは論理座標。原点も大きさも倍率が掛かり、その外は切れる');

  Start;
  R.SetLogicalPresentation(20, 20, TPMLLogicalPresentation.Letterbox);
  R.ClipRect := TPMLRect.Make(1, 1, 2, 2);
  R.FillRect(TPMLFRect.Make(0, 0, 20, 20));
  Paint(Want, 22, 2, 26, 6, FG);
  Finish('クリップ矩形も論理座標');
end;

procedure TestTexture;
var
  Src: TPMLSurface;
  Tex: TPMLTexture;
begin
  WriteLn;
  WriteLn('3. テクスチャ');
  Start;
  R.SetLogicalPresentation(20, 20, TPMLLogicalPresentation.Letterbox);
  Src := TPMLSurface.Create(2, 2, PML_PIXELFORMAT_ARGB8888);
  try
    Src.Fill(FG);
    Tex := R.CreateTextureFromSurface(Src);
  finally
    Src.Free;
  end;
  try
    R.RenderTexture(Tex, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 0, 0));
    Paint(Want, 20, 0, 60, 40, FG);
    Finish('転送先が空なら論理画面の全体（帯には描かない）');

    Start;
    R.SetLogicalPresentation(20, 20, TPMLLogicalPresentation.Letterbox);
    R.RenderTexture(Tex, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(5, 5, 2, 1));
    Paint(Want, 30, 10, 34, 12, FG);
    Finish('転送先の矩形にも倍率が掛かる');
  finally
    Tex.Free;
  end;
end;

procedure TestPointsLines;
var
  Half: TPMLColor;
begin
  WriteLn;
  WriteLn('4. 点と線');

  Start;
  R.SetLogicalPresentation(20, 20, TPMLLogicalPresentation.Letterbox);
  R.DrawPoint(3, 4);
  Paint(Want, 26, 8, 28, 10, FG);
  Finish('論理解像度の点は倍率の大きさの矩形');

  Start;
  R.SetLogicalPresentation(20, 20, TPMLLogicalPresentation.Letterbox);
  R.DrawLine(1, 1, 4, 1);
  R.DrawLine(6, 2, 6, 5);
  Paint(Want, 22, 2, 30, 4, FG);
  Paint(Want, 32, 4, 34, 12, FG);
  Finish('論理解像度の水平・垂直の線（三角形で描く）');

  // 半透明で閉じた枠を描く。二重に塗った画素は濃くなる。
  Half := TPMLColor.Make(FG.R, FG.G, FG.B, 128);
  Start;
  R.SetLogicalPresentation(20, 20, TPMLLogicalPresentation.Letterbox);
  R.BlendMode := TPMLBlendMode.Blend;
  R.DrawColor := Half;
  R.DrawRect(TPMLFRect.Make(1, 1, 4, 3));
  R.Flush;
  // 期待の色は、同じ合成で 1 回だけ塗ったもの。左上の角の画素から取る。
  Paint(Want, 22, 2, 30, 4, Target.ReadPixel(22, 2));
  Paint(Want, 22, 6, 30, 8, Target.ReadPixel(22, 2));
  Paint(Want, 22, 2, 24, 8, Target.ReadPixel(22, 2));
  Paint(Want, 28, 2, 30, 8, Target.ReadPixel(22, 2));
  Check(not SameColor(Target.ReadPixel(22, 2), BG) and not SameColor(Target.ReadPixel(22, 2), FG),
    '枠の色は背景とも塗りの色とも違う（半透明が効いている）');
  Finish('論理解像度の閉じた枠は、始点も含めてどの画素も 1 回だけ塗る');

  Start;
  R.Scale := TPMLFPoint.Make(2, 2);
  R.BlendMode := TPMLBlendMode.Blend;
  R.DrawColor := Half;
  R.DrawRect(TPMLFRect.Make(1, 1, 4, 3));
  R.Flush;
  Paint(Want, 2, 2, 10, 4, Target.ReadPixel(2, 2));
  Paint(Want, 2, 6, 10, 8, Target.ReadPixel(2, 2));
  Paint(Want, 2, 2, 4, 8, Target.ReadPixel(2, 2));
  Paint(Want, 8, 2, 10, 8, Target.ReadPixel(2, 2));
  Check(not SameColor(Target.ReadPixel(2, 2), BG) and not SameColor(Target.ReadPixel(2, 2), FG),
    '枠の色は半透明');
  Finish('Scale だけの閉じた枠も、どの画素も 1 回だけ塗る（矩形の並び）');

  // 開いた折れ線は終点まで描く。途中の点は次の線分の始点として 1 回だけ。
  Start;
  R.Scale := TPMLFPoint.Make(2, 2);
  R.DrawLines([TPMLFPoint.Make(1, 1), TPMLFPoint.Make(4, 1), TPMLFPoint.Make(4, 3)]);
  Paint(Want, 2, 2, 10, 4, FG);
  Paint(Want, 8, 4, 10, 8, FG);
  Finish('Scale だけの開いた折れ線は終点 (4, 3) まで描く');

  Start;
  R.Scale := TPMLFPoint.Make(2, 2);
  R.DrawLine(0, 0, 3, 3);
  Paint(Want, 0, 0, 2, 2, FG);
  Paint(Want, 2, 2, 4, 4, FG);
  Paint(Want, 4, 4, 6, 6, FG);
  Paint(Want, 6, 6, 8, 8, FG);
  Finish('Scale だけの斜めの線は、ブレゼンハムの点を倍率の大きさで');

  Start;
  R.Scale := TPMLFPoint.Make(3, 2);
  R.DrawLine(0, 0, 4, 2);
  // SDL の RenderLineBresenham を手で辿る。d = 2*2 - 4 = 0 から始まり、d >= 0 なら
  // 斜め、d < 0 なら横に進む: (0,0) (1,1) (2,1) (3,2) (4,2)。
  Paint(Want, 0, 0, 3, 2, FG);
  Paint(Want, 3, 2, 6, 4, FG);
  Paint(Want, 6, 2, 9, 4, FG);
  Paint(Want, 9, 4, 12, 6, FG);
  Paint(Want, 12, 4, 15, 6, FG);
  Finish('Scale (3, 2) の斜めの線');
end;

procedure TestCoordinates;
var
  P: TPMLFPoint;
begin
  WriteLn;
  WriteLn('5. ウィンドウ座標との変換');
  Start;
  R.SetLogicalPresentation(20, 20, TPMLLogicalPresentation.Letterbox);
  P := R.RenderCoordinatesFromWindow(30, 10);
  Check(SameF(P.X, 5) and SameF(P.Y, 5),
    Format('Letterbox: ウィンドウ (30, 10) → 描画 (5, 5)。得たのは (%g, %g)', [P.X, P.Y]));
  P := R.RenderCoordinatesToWindow(5, 5);
  Check(SameF(P.X, 30) and SameF(P.Y, 10),
    Format('逆向き: 描画 (5, 5) → ウィンドウ (30, 10)。得たのは (%g, %g)', [P.X, P.Y]));
  P := R.RenderCoordinatesFromWindow(10, 10);
  Check(SameF(P.X, -5) and SameF(P.Y, 5),
    Format('帯の上は論理画面の外（負）: (%g, %g)', [P.X, P.Y]));
  R.Viewport := TPMLRect.Make(2, 3, 5, 5);
  P := R.RenderCoordinatesFromWindow(30, 10);
  Check(SameF(P.X, 3) and SameF(P.Y, 2),
    Format('ビューポートの原点を引く: (%g, %g)', [P.X, P.Y]));
  P := R.RenderCoordinatesToWindow(3, 2);
  Check(SameF(P.X, 30) and SameF(P.Y, 10),
    Format('逆向きはビューポートの原点を足す: (%g, %g)', [P.X, P.Y]));

  Start;
  R.Scale := TPMLFPoint.Make(2, 4);
  P := R.RenderCoordinatesFromWindow(10, 8);
  Check(SameF(P.X, 5) and SameF(P.Y, 2),
    Format('Scale (2, 4): ウィンドウ (10, 8) → 描画 (5, 2)。得たのは (%g, %g)', [P.X, P.Y]));
  R.Scale := TPMLFPoint.Make(0, 0);
  P := R.RenderCoordinatesFromWindow(10, 8);
  Check(SameF(P.X, 10) and SameF(P.Y, 8), '倍率 0 でも例外にならない（割らずに返す）');
end;

procedure TestDebugText;
var
  Red: TPMLColor;
begin
  WriteLn;
  WriteLn('6. DebugText');
  Check(PML_DEBUG_TEXT_FONT_CHARACTER_SIZE = 8, '1 文字は 8 画素');

  Red := TPMLColor.Make(255, 0, 0);
  Start;
  R.DrawColor := Red;
  R.DebugText(1, 2, 'A?@');
  PaintGlyph(Want, GlyphA, 1, 2, 1, Red);
  PaintGlyph(Want, GlyphQuestion, 9, 2, 1, Red);
  PaintGlyph(Want, GlyphAt, 17, 2, 1, Red);
  Finish('字形は DrawColor で描き、字形の外は背景のまま（8 画素ずつ進む）');

  Start;
  R.DrawColor := Red;
  R.DebugText(0, 0, 'A A'#10'A');
  PaintGlyph(Want, GlyphA, 0, 0, 1, Red);
  PaintGlyph(Want, GlyphA, 16, 0, 1, Red);
  PaintGlyph(Want, GlyphA, 32, 0, 1, Red);
  Finish('空白と制御文字は描かずに 1 文字ぶん進む（改行もしない。SDL と同じ）');

  Start;
  R.DrawColor := Red;
  R.DebugText(0, 0, 'é' + 'あ' + #$FF);
  PaintGlyph(Want, GlyphEAcute, 0, 0, 1, Red);
  PaintGlyph(Want, GlyphMissing, 8, 0, 1, Red);
  PaintGlyph(Want, GlyphMissing, 16, 0, 1, Red);
  Finish('é は字形があり、字形の無い文字と壊れた UTF-8 は「無い」印（D-42）');

  // 色を変えて 2 回描き、まとめて Flush する。同じ文字の表のテクスチャを
  // 変調色を変えて 2 回転送するので、色は積んだときの値でなければならない（D-43）。
  Start;
  R.DrawColor := Red;
  R.DebugText(0, 0, 'A');
  R.DrawColor := FG;
  R.DebugText(8, 0, 'A');
  PaintGlyph(Want, GlyphA, 0, 0, 1, Red);
  PaintGlyph(Want, GlyphA, 8, 0, 1, FG);
  Finish('1 フレームの中で色を変えても、それぞれの色で描く（D-43）');

  // 文字の表は Textures に載る。アプリが解放しても、次の DebugText が作り直す。
  Start;
  R.Textures[High(R.Textures)].Free;
  R.DrawColor := Red;
  R.DebugText(0, 0, 'A');
  PaintGlyph(Want, GlyphA, 0, 0, 1, Red);
  Finish('文字の表を解放されても、次の DebugText で作り直して描く');

  Start;
  R.SetLogicalPresentation(20, 20, TPMLLogicalPresentation.Letterbox);
  R.DrawColor := Red;
  R.DebugText(1, 1, 'A');
  PaintGlyph(Want, GlyphA, 22, 2, 2, Red);
  Finish('論理解像度では文字も拡大される');
end;

procedure TestWindowResize;
var
  Ctx : TPMLContext;
  Opts: TPMLContextOptions;
  Win : TPMLWindow;
  WR  : TPMLRenderer;
  Rc  : TPMLFRect;
  Got : TPMLSurface;
begin
  WriteLn;
  WriteLn('7. ウィンドウの大きさの追従');
  Opts := TPMLContextOptions.Default;
  Opts.PreferredVideo := 'dummy';
  Ctx := TPMLContext.Create([TPMLSubsystem.Video], Opts);
  try
    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('logical', 80, 40).Resizable);
    WR := TPMLRenderer.CreateForWindow(Win);
    WR.SetLogicalPresentation(20, 20, TPMLLogicalPresentation.Letterbox);
    Rc := WR.LogicalPresentationRect;
    Check(SameFRect(Rc, 20, 0, 40, 40), '80x40 では左右に帯: ' + FRectStr(Rc));

    Win.SetSize(40, 80);
    Rc := WR.LogicalPresentationRect;
    Check(SameFRect(Rc, 0, 20, 40, 40), '40x80 にすると上下に帯: ' + FRectStr(Rc));

    WR.DrawColor := BG;
    WR.Clear;
    WR.DrawColor := FG;
    WR.FillRect(TPMLFRect.Make(0, 0, 20, 20));
    Got := WR.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    try
      Check((Got.Width = 40) and (Got.Height = 80), '出力は 40x80');
      Check(SameColor(Got.ReadPixel(0, 19), BG) and SameColor(Got.ReadPixel(0, 20), FG)
        and SameColor(Got.ReadPixel(39, 59), FG) and SameColor(Got.ReadPixel(39, 60), BG),
        '大きさが変わった後の描画は新しい当てはめで描く');
    finally
      Got.Free;
    end;
  finally
    Ctx.Free;
  end;
end;

begin
  WriteLn('test_render_logical — 拡大率・論理解像度・DebugText');
  WriteLn;
  BG := TPMLColor.Make(0, 0, 64);
  FG := TPMLColor.Make(255, 255, 255);
  Want := nil;
  Target := TPMLSurface.Create(OutW, OutH, PML_PIXELFORMAT_ARGB8888);
  R := TPMLRenderer.CreateSoftware(Target);
  try
    TestFitRects;
    TestFill;
    TestTexture;
    TestPointsLines;
    TestCoordinates;
    TestDebugText;
  finally
    R.Free;
    Target.Free;
    Want.Free;
  end;
  TestWindowResize;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: 拡大率・論理解像度・DebugText が SDL と同じ規則で描く ===')
  else
  begin
    WriteLn(Format('=== 結論: %d 件失敗 ===', [Failures]));
    Halt(1);
  end;
end.
