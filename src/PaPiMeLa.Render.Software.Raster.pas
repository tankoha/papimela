{
  PaPiMeLa.Render.Software.Raster — 三角形のラスタライザ

  Origin : ported from SDL (src/render/software/SDL_triangle.c)
           Scope: 辺関数（外積）による内外判定、画素の中心で標本すること、
           top-left 規則で辺上の画素の帰属を決めること。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.3、§11 #42

  WHAT:
    三角形 1 枚を描画先サーフェスへ塗る。頂点色の補間、テクスチャの標本、
    合成モードを扱う。

  WHY:
    ソフトウェアレンダラの RenderGeometry は全部ここを通る。矩形・線・転送を
    三角形へ落とす既定の経路もここを通るので、辺の扱いを間違えると
    対角線を共有する 2 枚の三角形の間に隙間か二重塗りが出る。

  RESOLVED:
    - 副画素の精度は 8 ビット（1/256 画素）。SDL は 1 ビット（半画素）で、
      外接矩形の幅を切り捨てるため最後の列を落とすことがある
    - 標本点は画素の中心（x + 0.5, y + 0.5）
    - top-left 規則: 辺の上にちょうど乗った画素は、その辺が上辺か左辺の
      ときだけ塗る。2 枚の三角形が辺を共有すると、共有辺上の画素は
      必ずどちらか一方だけに属する

  NOT RESOLVED:
    - テクスチャの標本は最近傍のみ。線形補間は未実装
    - 遠近補正は無い。2D の描画だけを想定している

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Render.Software.Raster;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.Blit,
  PaPiMeLa.Render;

{ 三角形を 1 枚塗る。

  頂点座標に AOffsetX / AOffsetY を足した位置へ塗る（ビューポートの原点）。
  塗るのは ADst.ClipRect の内側だけ。面積 0 の三角形は何もしない。
  頂点の回り順（時計回り・反時計回り）はどちらでもよい。

  ATexture が nil なら、頂点色を重心座標で補間した色で塗る。
  nil でなければ、テクスチャ座標を重心座標で補間して ATexture を最近傍で
  標本し、その色に補間した頂点色を掛ける。

  合成は ABlend に従う（PMLBlendColor と同じ式）。 }
procedure PMLRasterTriangle(ADst: TPMLSurface; const AV0, AV1, AV2: TPMLVertex;
  ATexture: TPMLSurface; ABlend: TPMLBlendMode; AOffsetX, AOffsetY: Single);

implementation

uses Math;

// qwen2.5-coder が生成。仕様どおりで、そのまま採用した。
function Edge(AX0, AY0, AX1, AY1, APX, APY: Int64): Int64;
begin
  Result := (AX1 - AX0) * (APY - AY0) - (AY1 - AY0) * (APX - AX0);
end;

// qwen2.5-coder が生成。仕様どおりで、そのまま採用した。
function IsTopLeft(AX0, AY0, AX1, AY1: Int64): Boolean;
begin
  Result := ((AY0 = AY1) and (AX1 > AX0)) or (AY1 < AY0);
end;

// qwen2.5-coder が生成。仕様どおりで、そのまま採用した。
function ToByte(AValue: Double): Byte;
begin
  if AValue <= 0 then Result := 0
  else if AValue >= 1 then Result := 255
  else Result := Byte(Round(AValue * 255));
end;

function SameFColor(const A, B: TPMLFColor): Boolean; inline;
begin
  Result := (A.R = B.R) and (A.G = B.G) and (A.B = B.B) and (A.A = B.A);
end;

{ 三角形を塗る。

  PORT-NOTE: 骨格は qwen2.5-coder の生成物だが、本体はほぼ書き直した（D-33）。
  生成物には次の誤りがあった:
    - 回り順を揃える入れ替えが頂点 0 を壊し、色とテクスチャ座標を入れ替えていない
    - 内外判定が `A or B and C or ...` で、and が or より先に結合するため半平面を塗る
    - `MinX >= MaxX or ...` で or が >= より先に結合する（コンパイル不可）
    - 画素位置 px と標本点 PX が大文字小文字の違いだけで同じ識別子（コンパイル不可）。
      これは仕様側（こちら）が px / PX と書き分けたのが原因
    - テクスチャに掛ける頂点色が補間値でなく頂点 0 の色
  変数名は画素位置を Col / Row、標本点を SampleX / SampleY として分けてある。 }
procedure PMLRasterTriangle(ADst: TPMLSurface; const AV0, AV1, AV2: TPMLVertex;
  ATexture: TPMLSurface; ABlend: TPMLBlendMode; AOffsetX, AOffsetY: Single);
var
  A0, A1, A2, Tmp: TPMLVertex;
  X0, Y0, X1, Y1, X2, Y2: Int64;
  Area, W0, W1, W2: Int64;
  SampleX, SampleY: Int64;
  MinX, MaxX, MinY, MaxY, Col, Row: Integer;
  TL0, TL1, TL2: Boolean;
  Uniform, White: Boolean;
  L0, L1, L2: Double;
  CR, CG, CB, CA: Double;
  U, V: Double;
  TX, TY: Integer;
  Texel, C: TPMLColor;
begin
  A0 := AV0;
  A1 := AV1;
  A2 := AV2;
  X0 := Round((A0.Position.X + AOffsetX) * 256);
  Y0 := Round((A0.Position.Y + AOffsetY) * 256);
  X1 := Round((A1.Position.X + AOffsetX) * 256);
  Y1 := Round((A1.Position.Y + AOffsetY) * 256);
  X2 := Round((A2.Position.X + AOffsetX) * 256);
  Y2 := Round((A2.Position.Y + AOffsetY) * 256);

  Area := Edge(X0, Y0, X1, Y1, X2, Y2);
  if Area = 0 then
    Exit;

  // 反時計回りなら頂点 1 と 2 を丸ごと入れ替える。座標だけ入れ替えると
  // 色とテクスチャ座標が別の頂点のものになる。
  if Area < 0 then
  begin
    Tmp := A1;
    A1 := A2;
    A2 := Tmp;
    SampleX := X1; X1 := X2; X2 := SampleX;
    SampleY := Y1; Y1 := Y2; Y2 := SampleY;
    Area := -Area;
  end;

  MinX := Floor(Min(Min(X0, X1), X2) / 256);
  MaxX := Ceil(Max(Max(X0, X1), X2) / 256);
  MinY := Floor(Min(Min(Y0, Y1), Y2) / 256);
  MaxY := Ceil(Max(Max(Y0, Y1), Y2) / 256);
  MinX := Max(MinX, ADst.ClipRect.X);
  MinY := Max(MinY, ADst.ClipRect.Y);
  MaxX := Min(MaxX, ADst.ClipRect.X + ADst.ClipRect.W);
  MaxY := Min(MaxY, ADst.ClipRect.Y + ADst.ClipRect.H);
  if (MinX >= MaxX) or (MinY >= MaxY) then
    Exit;

  // 辺ごとの top-left は画素に依らないので先に求める。
  TL0 := IsTopLeft(X1, Y1, X2, Y2);
  TL1 := IsTopLeft(X2, Y2, X0, Y0);
  TL2 := IsTopLeft(X0, Y0, X1, Y1);

  // 3 頂点が同じ色なら補間しない。矩形の塗りが速い経路と完全に一致する。
  Uniform := SameFColor(A0.Color, A1.Color) and SameFColor(A1.Color, A2.Color);
  White := Uniform and (A0.Color.R = 1) and (A0.Color.G = 1)
       and (A0.Color.B = 1) and (A0.Color.A = 1);

  for Row := MinY to MaxY - 1 do
    for Col := MinX to MaxX - 1 do
    begin
      SampleX := Int64(Col) * 256 + 128;
      SampleY := Int64(Row) * 256 + 128;
      W0 := Edge(X1, Y1, X2, Y2, SampleX, SampleY);
      W1 := Edge(X2, Y2, X0, Y0, SampleX, SampleY);
      W2 := Edge(X0, Y0, X1, Y1, SampleX, SampleY);
      // 各辺の条件を必ず括弧で閉じる。and は or より先に結合する。
      if not (((W0 > 0) or ((W0 = 0) and TL0))
          and ((W1 > 0) or ((W1 = 0) and TL1))
          and ((W2 > 0) or ((W2 = 0) and TL2))) then
        Continue;

      L0 := W0 / Area;
      L1 := W1 / Area;
      L2 := W2 / Area;

      if Uniform then
      begin
        CR := A0.Color.R; CG := A0.Color.G; CB := A0.Color.B; CA := A0.Color.A;
      end
      else
      begin
        CR := L0 * A0.Color.R + L1 * A1.Color.R + L2 * A2.Color.R;
        CG := L0 * A0.Color.G + L1 * A1.Color.G + L2 * A2.Color.G;
        CB := L0 * A0.Color.B + L1 * A1.Color.B + L2 * A2.Color.B;
        CA := L0 * A0.Color.A + L1 * A1.Color.A + L2 * A2.Color.A;
      end;

      if ATexture <> nil then
      begin
        U := L0 * A0.TexCoord.X + L1 * A1.TexCoord.X + L2 * A2.TexCoord.X;
        V := L0 * A0.TexCoord.Y + L1 * A1.TexCoord.Y + L2 * A2.TexCoord.Y;
        // 1e-4 は、ちょうど整数になるはずの値が誤差で下に落ちるのを防ぐ。
        TX := Floor(U * ATexture.Width + 1e-4);
        TY := Floor(V * ATexture.Height + 1e-4);
        TX := Max(0, Min(TX, ATexture.Width - 1));
        TY := Max(0, Min(TY, ATexture.Height - 1));
        Texel := ATexture.ReadPixel(TX, TY);
        if White then
          C := Texel
        else
          // 掛けるのは補間した頂点色。頂点 0 の色ではない。
          C := TPMLColor.Make(ToByte(Texel.R / 255 * CR), ToByte(Texel.G / 255 * CG),
                              ToByte(Texel.B / 255 * CB), ToByte(Texel.A / 255 * CA));
      end
      else
        C := TPMLColor.Make(ToByte(CR), ToByte(CG), ToByte(CB), ToByte(CA));

      if ABlend = TPMLBlendMode.None then
        ADst.WritePixel(Col, Row, C)
      else
        ADst.WritePixel(Col, Row, PMLBlendColor(C, ADst.ReadPixel(Col, Row), ABlend));
    end;
end;

end.
