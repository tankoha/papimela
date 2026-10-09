{
  test_render_transform — 回す・写す・敷き詰める・9 つに分けて描く（#41）を検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    RenderTextureRotated（90 度刻み・反転・中心の指定・任意の角度）、RenderTextureAffine、
    RenderTextureTiled、RenderTexture9Grid、RenderTexture9GridTiled を、ソフトウェアの
    ドライバでサーフェスへ描き、期待の絵と画素で比べる。

  WHY:
    期待の絵は実装とは別の道で作る。
      - 回す・写すは、画素の中心を逆に写してテクセルを引く参照（ここに書いた式）。
        90 度刻みは四角形の辺が画素の境目にそろうので全画素を比べ、任意の角度と
        アフィンは辺から 1 画素以上内側で、テクセルの境目からも離れた画素だけを比べる
      - 敷き詰めと 9 つに分けるのは、区画の分け方を確かめたいので、RenderTexture を
        手で並べた絵と全画素で比べる（転送そのものは T-16 が見ている）
    枠の幅 0 の 9 つ分けは、RenderTexture の「空の矩形は全体」の約束に落ちて画面全体を
    塗ってしまわないことを、転送先をビューポートより小さくして確かめる。

  実行前提: 無し（ソフトウェアのドライバでサーフェスへ描く）。
}
program test_render_transform;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Render;

const
  W = 48;
  H = 40;

var
  Failures: Integer = 0;
  BG: TPMLColor;

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
  Result := (A.R = B.R) and (A.G = B.G) and (A.B = B.B);
end;

{ 1 テクセルずつ違う色のテクスチャ（AW x AH）。 }
function MakeTexColors(AW, AH: Integer): TPMLSurface;
var
  X, Y: Integer;
begin
  Result := TPMLSurface.Create(AW, AH, PML_PIXELFORMAT_ARGB8888);
  for Y := 0 to AH - 1 do
    for X := 0 to AW - 1 do
      Result.WritePixel(X, Y, TPMLColor.Make(20 + X * 37 mod 230, 30 + Y * 53 mod 220,
        (X * 11 + Y * 7) * 13 mod 256, 255));
end;

function NewTarget: TPMLSurface;
begin
  Result := TPMLSurface.Create(W, H, PML_PIXELFORMAT_XRGB8888);
  Result.FillRect(TPMLRect.Make(0, 0, W, H), BG);
end;

procedure ClearTo(R: TPMLRenderer);
begin
  R.DrawColor := BG;
  R.Clear;
end;

{ AGot と AWant を、AMask が True の画素だけ比べる（AMask = nil なら全画素）。 }
procedure Compare(AGot, AWant: TPMLSurface; const AMask: array of Boolean; const ALabel: String);
var
  X, Y, N, Seen, FX, FY: Integer;
  G, Wt: TPMLColor;
begin
  N := 0; Seen := 0; FX := -1; FY := -1;
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
    begin
      if (Length(AMask) > 0) and not AMask[Y * W + X] then
        Continue;
      Inc(Seen);
      if not SameColor(AGot.ReadPixel(X, Y), AWant.ReadPixel(X, Y)) then
      begin
        if N = 0 then begin FX := X; FY := Y; end;
        Inc(N);
      end;
    end;
  if N = 0 then
    Check(Seen > 0, Format('%s（%d 画素を比べた）', [ALabel, Seen]))
  else
  begin
    G := AGot.ReadPixel(FX, FY);
    Wt := AWant.ReadPixel(FX, FY);
    Check(False, Format('%s（%d / %d 画素違う。最初は (%d, %d) が %d,%d,%d で、期待は %d,%d,%d）',
      [ALabel, N, Seen, FX, FY, G.R, G.G, G.B, Wt.R, Wt.G, Wt.B]));
  end;
end;

{ ---- 回す・写すの参照 ----
  四角形の角は、転送先の左上（テクスチャの (0,0)）を O、右上を Rt、左下を Dn として
  O + u (Rt - O) + v (Dn - O)（u, v は 0〜1）。画素の中心 Q から u, v を解き、
  テクセル floor(u * TW), floor(v * TH) を引く。辺とテクセルの境目からの余裕も返す。 }
function Solve(const O, Rt, Dn: TPMLFPoint; QX, QY: Double; out U, V: Double): Boolean;
var
  AX, AY, BX, BY, Det, PX, PY: Double;
begin
  AX := Rt.X - O.X; AY := Rt.Y - O.Y;
  BX := Dn.X - O.X; BY := Dn.Y - O.Y;
  Det := AX * BY - AY * BX;
  Result := Abs(Det) > 1e-9;
  if not Result then Exit;
  PX := QX - O.X; PY := QY - O.Y;
  U := (PX * BY - PY * BX) / Det;
  V := (AX * PY - AY * PX) / Det;
end;

{ 参照の絵を作る。AExact なら全画素、そうでなければ辺から AMargin 画素以上内側で、
  テクセルの境目から 0.05 以上離れた画素だけを AMask に立てる。 }
procedure Reference(ATex: TPMLSurface; const O, Rt, Dn: TPMLFPoint; AWant: TPMLSurface;
  AExact: Boolean; var AMask: array of Boolean);
var
  X, Y, TX, TY: Integer;
  U, V, EdgeU, EdgeV, LenU, LenV, FU, FV: Double;
  Inside: Boolean;
begin
  LenU := Hypot(Rt.X - O.X, Rt.Y - O.Y);
  LenV := Hypot(Dn.X - O.X, Dn.Y - O.Y);
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
    begin
      AMask[Y * W + X] := AExact;
      if not Solve(O, Rt, Dn, X + 0.5, Y + 0.5, U, V) then
        Continue;
      Inside := (U >= 0) and (U < 1) and (V >= 0) and (V < 1);
      if Inside then
      begin
        TX := Floor(U * ATex.Width);
        TY := Floor(V * ATex.Height);
        AWant.WritePixel(X, Y, ATex.ReadPixel(TX, TY));
      end;
      if not AExact then
      begin
        // 辺までの距離（画素）と、テクセルの境目までの距離（テクセルの割合）
        EdgeU := Min(U, 1 - U) * LenU;
        EdgeV := Min(V, 1 - V) * LenV;
        FU := Frac(U * ATex.Width);
        FV := Frac(V * ATex.Height);
        AMask[Y * W + X] := Inside and (EdgeU >= 1.0) and (EdgeV >= 1.0)
          and (FU > 0.05) and (FU < 0.95) and (FV > 0.05) and (FV < 0.95);
      end;
    end;
end;

function Rot(const P, C: TPMLFPoint; ADeg: Double): TPMLFPoint;
var
  S, Co: Double;
begin
  S := Sin(ADeg * Pi / 180);
  Co := Cos(ADeg * Pi / 180);
  Result := TPMLFPoint.Make(Co * (P.X - C.X) - S * (P.Y - C.Y) + C.X,
                            S * (P.X - C.X) + Co * (P.Y - C.Y) + C.Y);
end;

{ 回したときの角（テクスチャの (0,0) / (1,0) / (0,1) が行く先）。反転は回す前。 }
procedure RotatedCorners(const D: TPMLFRect; const C: TPMLFPoint; ADeg: Double; AFlip: TPMLFlips;
  out O, Rt, Dn: TPMLFPoint);
var
  X0, X1, Y0, Y1: Single;
  Abs_: TPMLFPoint;
begin
  X0 := D.X; X1 := D.X + D.W; Y0 := D.Y; Y1 := D.Y + D.H;
  if TPMLFlip.Horizontal in AFlip then begin X0 := D.X + D.W; X1 := D.X; end;
  if TPMLFlip.Vertical in AFlip then begin Y0 := D.Y + D.H; Y1 := D.Y; end;
  Abs_ := TPMLFPoint.Make(C.X + D.X, C.Y + D.Y);
  O  := Rot(TPMLFPoint.Make(X0, Y0), Abs_, ADeg);
  Rt := Rot(TPMLFPoint.Make(X1, Y0), Abs_, ADeg);
  Dn := Rot(TPMLFPoint.Make(X0, Y1), Abs_, ADeg);
end;

procedure TestRotated;
var
  Tex: TPMLSurface;
  Target, Want: TPMLSurface;
  R: TPMLRenderer;
  T: TPMLTexture;
  Mask: array of Boolean;
  O, Rt, Dn: TPMLFPoint;
  D: TPMLFRect;
  C: TPMLFPoint;

  procedure Case_(ADeg: Double; AFlip: TPMLFlips; AExact: Boolean; const ALabel: String;
    AUseCenter: Boolean = False);
  begin
    ClearTo(R);
    if AUseCenter then
      R.RenderTextureRotated(T, TPMLFRect.Make(0, 0, 0, 0), D, ADeg, C, AFlip)
    else
      R.RenderTextureRotated(T, TPMLFRect.Make(0, 0, 0, 0), D, ADeg, AFlip);
    R.Present;
    Want.FillRect(TPMLRect.Make(0, 0, W, H), BG);
    if AUseCenter then
      RotatedCorners(D, C, ADeg, AFlip, O, Rt, Dn)
    else
      RotatedCorners(D, TPMLFPoint.Make(D.W / 2, D.H / 2), ADeg, AFlip, O, Rt, Dn);
    Reference(Tex, O, Rt, Dn, Want, AExact, Mask);
    Compare(Target, Want, Mask, ALabel);
  end;

begin
  WriteLn('1. 回す（RenderTextureRotated）');
  Tex := MakeTexColors(4, 3);
  Target := NewTarget;
  Want := NewTarget;
  SetLength(Mask, W * H);
  R := TPMLRenderer.CreateSoftware(Target);
  try
    T := R.CreateTextureFromSurface(Tex);
    T.ScaleMode := TPMLScaleMode.Nearest;
    D := TPMLFRect.Make(12, 14, 16, 12);   // 4x3 を 4 倍。中心 (20, 20)
    Case_(0, [TPMLFlip.Horizontal], True, '反転だけ（左右）');
    Case_(0, [TPMLFlip.Vertical], True, '反転だけ（上下）');
    Case_(0, [TPMLFlip.Horizontal, TPMLFlip.Vertical], True, '反転だけ（両方）');
    Case_(90, [], True, '90 度');
    Case_(180, [], True, '180 度');
    Case_(270, [], True, '270 度');
    Case_(-90, [], True, '-90 度（270 度と同じ絵）');
    Case_(90, [TPMLFlip.Horizontal], True, '左右反転してから 90 度');
    C := TPMLFPoint.Make(0, 0);
    Case_(90, [], True, '中心を転送先の左上にして 90 度', True);
    C := TPMLFPoint.Make(4, 8);
    Case_(180, [TPMLFlip.Vertical], True, '中心 (4, 8) で上下反転して 180 度', True);
    Case_(30, [], False, '30 度（内側の画素）');
    Case_(-45, [TPMLFlip.Horizontal], False, '左右反転して -45 度（内側の画素）');
    Case_(360, [], True, '360 度は回さない（RenderTexture と同じ）');

    // 変調色は回しても効く（頂点の色として渡る）
    T.ColorMod := TPMLColor.Make(255, 0, 0);
    ClearTo(R);
    R.RenderTextureRotated(T, TPMLFRect.Make(0, 0, 0, 0), D, 90);
    R.Present;
    Check((Target.ReadPixel(20, 20).G = 0) and (Target.ReadPixel(20, 20).B = 0)
      and (Target.ReadPixel(20, 20).R > 0), '変調色（赤だけ）が回した絵にも効く');
    T.ColorMod := TPMLColor.Make(255, 255, 255);

    // 拡大率は回した絵にも効く
    R.Scale := TPMLFPoint.Make(2, 2);
    ClearTo(R);
    R.RenderTextureRotated(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(6, 7, 8, 6), 90);
    R.Present;
    R.Scale := TPMLFPoint.Make(1, 1);
    Want.FillRect(TPMLRect.Make(0, 0, W, H), BG);
    RotatedCorners(D, TPMLFPoint.Make(D.W / 2, D.H / 2), 90, [], O, Rt, Dn);
    Reference(Tex, O, Rt, Dn, Want, True, Mask);
    Compare(Target, Want, Mask, '拡大率 2 で (6, 7, 8, 6) を 90 度 = 拡大率 1 で (12, 14, 16, 12) を 90 度');
  finally
    R.Free;
    Target.Free;
    Want.Free;
    Tex.Free;
  end;
  WriteLn;
end;

procedure TestAffine;
var
  Tex, Target, Want: TPMLSurface;
  R: TPMLRenderer;
  T: TPMLTexture;
  Mask: array of Boolean;
  O, Rt, Dn: TPMLFPoint;
begin
  WriteLn('2. 平行四辺形へ写す（RenderTextureAffine）');
  Tex := MakeTexColors(5, 4);
  Target := NewTarget;
  Want := NewTarget;
  SetLength(Mask, W * H);
  R := TPMLRenderer.CreateSoftware(Target);
  try
    T := R.CreateTextureFromSurface(Tex);
    T.ScaleMode := TPMLScaleMode.Nearest;
    O := TPMLFPoint.Make(8, 6);
    Rt := TPMLFPoint.Make(38, 12);
    Dn := TPMLFPoint.Make(4, 30);
    ClearTo(R);
    R.RenderTextureAffine(T, TPMLFRect.Make(0, 0, 0, 0), O, Rt, Dn);
    R.Present;
    Reference(Tex, O, Rt, Dn, Want, False, Mask);
    Compare(Target, Want, Mask, 'せん断した平行四辺形（内側の画素）');

    // 転送元の一部（右下 3x2）だけ
    ClearTo(R);
    R.RenderTextureAffine(T, TPMLFRect.Make(2, 2, 3, 2), TPMLFPoint.Make(6, 6),
      TPMLFPoint.Make(36, 6), TPMLFPoint.Make(6, 26));
    R.Present;
    Check(SameColor(Target.ReadPixel(10, 10), Tex.ReadPixel(2, 2))
      and SameColor(Target.ReadPixel(33, 23), Tex.ReadPixel(4, 3)),
      '転送元の一部を写す（左上と右下のテクセル）');
  finally
    R.Free;
    Target.Free;
    Want.Free;
    Tex.Free;
  end;
  WriteLn;
end;

{ ---- 敷き詰める・9 つに分ける: RenderTexture を手で並べた絵と比べる ---- }

procedure TestTiledAnd9Grid;
var
  Tex, Target, Want: TPMLSurface;
  R, RW: TPMLRenderer;
  T, TW: TPMLTexture;
  Raised: Boolean;
  None: array of Boolean;

  procedure Both;
  begin
    ClearTo(R);
    ClearTo(RW);
  end;

  procedure Show(const ALabel: String);
  begin
    R.Present;
    RW.Present;
    Compare(Target, Want, None, ALabel);
  end;

begin
  WriteLn('3. 敷き詰める（RenderTextureTiled）と 9 つに分ける（RenderTexture9Grid）');
  Tex := MakeTexColors(6, 6);
  Target := NewTarget;
  Want := NewTarget;
  SetLength(None, 0);
  R := TPMLRenderer.CreateSoftware(Target);
  RW := TPMLRenderer.CreateSoftware(Want);
  try
    T := R.CreateTextureFromSurface(Tex);
    T.ScaleMode := TPMLScaleMode.Nearest;
    TW := RW.CreateTextureFromSurface(Tex);
    TW.ScaleMode := TPMLScaleMode.Nearest;

    // 6x6 を 2 倍（12x12）で (2,3)-(30x27) に敷く: 2 列 + 6 画素、2 行 + 3 画素。
    // 端数は 2 進でちょうど表せる値にする（30/12 の端数 0.5、27/12 の端数 0.25）。31 のように
    // 割り切れない幅だと、端数の転送元が 3.4999998 のようになり、テクセルの境目ちょうどの
    // 画素で隣を引く（実装も SDL も float で同じ計算をする。期待の絵の側の丸めの問題）。
    Both;
    R.RenderTextureTiled(T, TPMLFRect.Make(0, 0, 0, 0), 2, TPMLFRect.Make(2, 3, 30, 27));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 0, 6, 6), TPMLFRect.Make(2, 3, 12, 12));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 0, 6, 6), TPMLFRect.Make(14, 3, 12, 12));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 0, 3, 6), TPMLFRect.Make(26, 3, 6, 12));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 0, 6, 6), TPMLFRect.Make(2, 15, 12, 12));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 0, 6, 6), TPMLFRect.Make(14, 15, 12, 12));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 0, 3, 6), TPMLFRect.Make(26, 15, 6, 12));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 0, 6, 1.5), TPMLFRect.Make(2, 27, 12, 3));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 0, 6, 1.5), TPMLFRect.Make(14, 27, 12, 3));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 0, 3, 1.5), TPMLFRect.Make(26, 27, 6, 3));
    Show('2 倍で敷き詰め、右端と下端の端数は転送元も同じ割合で切る');

    // 転送元の一部（2x2 の中央 (2,2)）を 1 倍で
    Both;
    R.RenderTextureTiled(T, TPMLFRect.Make(2, 2, 2, 2), 1, TPMLFRect.Make(5, 5, 5, 3));
    RW.RenderTexture(TW, TPMLFRect.Make(2, 2, 2, 2), TPMLFRect.Make(5, 5, 2, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(2, 2, 2, 2), TPMLFRect.Make(7, 5, 2, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(2, 2, 1, 2), TPMLFRect.Make(9, 5, 1, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(2, 2, 2, 1), TPMLFRect.Make(5, 7, 2, 1));
    RW.RenderTexture(TW, TPMLFRect.Make(2, 2, 2, 1), TPMLFRect.Make(7, 7, 2, 1));
    RW.RenderTexture(TW, TPMLFRect.Make(2, 2, 1, 1), TPMLFRect.Make(9, 7, 1, 1));
    Show('転送元の一部を敷き詰める');

    Raised := False;
    try
      R.RenderTextureTiled(T, TPMLFRect.Make(0, 0, 0, 0), 0, TPMLFRect.Make(0, 0, 4, 4));
    except
      on E: EPMLArgument do Raised := True;
    end;
    Check(Raised, '敷き詰めの倍率 0 は EPMLArgument');

    // 9 つに分ける: 6x6 を枠 2（四隅は 2x2）で (4,4)-(20x14) に。中央と辺は伸びる
    Both;
    R.RenderTexture9Grid(T, TPMLFRect.Make(0, 0, 0, 0), 2, 2, 2, 2, 1, TPMLFRect.Make(4, 4, 20, 14));
    RW.RenderTexture(TW, TPMLFRect.Make(2, 2, 2, 2), TPMLFRect.Make(6, 6, 16, 10));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 0, 2, 2), TPMLFRect.Make(4, 4, 2, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(4, 0, 2, 2), TPMLFRect.Make(22, 4, 2, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(4, 4, 2, 2), TPMLFRect.Make(22, 16, 2, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 4, 2, 2), TPMLFRect.Make(4, 16, 2, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 2, 2, 2), TPMLFRect.Make(4, 6, 2, 10));
    RW.RenderTexture(TW, TPMLFRect.Make(4, 2, 2, 2), TPMLFRect.Make(22, 6, 2, 10));
    RW.RenderTexture(TW, TPMLFRect.Make(2, 0, 2, 2), TPMLFRect.Make(6, 4, 16, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(2, 4, 2, 2), TPMLFRect.Make(6, 16, 16, 2));
    Show('9 つに分ける（枠 2、倍率 1）');

    // 倍率 2: 左の枠 1.25 は 2 倍で 2.5 になり、切り上げて 3。他の枠は 2 倍でちょうど整数
    // （切り上げが効くのは左だけ。全部が整数だと切り上げを外しても絵が変わらない）。
    Both;
    R.RenderTexture9Grid(T, TPMLFRect.Make(0, 0, 0, 0), 1.25, 1, 2, 1, 2, TPMLFRect.Make(3, 2, 30, 20));
    // DL = 3, DR = 2, DT = 4, DB = 2
    RW.RenderTexture(TW, TPMLFRect.Make(1.25, 2, 3.75, 3), TPMLFRect.Make(6, 6, 25, 14));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 0, 1.25, 2), TPMLFRect.Make(3, 2, 3, 4));
    RW.RenderTexture(TW, TPMLFRect.Make(5, 0, 1, 2), TPMLFRect.Make(31, 2, 2, 4));
    RW.RenderTexture(TW, TPMLFRect.Make(5, 5, 1, 1), TPMLFRect.Make(31, 20, 2, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 5, 1.25, 1), TPMLFRect.Make(3, 20, 3, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 2, 1.25, 3), TPMLFRect.Make(3, 6, 3, 14));
    RW.RenderTexture(TW, TPMLFRect.Make(5, 2, 1, 3), TPMLFRect.Make(31, 6, 2, 14));
    RW.RenderTexture(TW, TPMLFRect.Make(1.25, 0, 3.75, 2), TPMLFRect.Make(6, 2, 25, 4));
    RW.RenderTexture(TW, TPMLFRect.Make(1.25, 5, 3.75, 1), TPMLFRect.Make(6, 20, 25, 2));
    Show('9 つに分ける（枠 1.25 / 1 / 2 / 1、倍率 2 で四隅は切り上げ）');

    // 倍率 1 でも枠の端数は切り上げる（1.5 → 2）
    Both;
    R.RenderTexture9Grid(T, TPMLFRect.Make(0, 0, 0, 0), 1.5, 1.5, 1.5, 1.5, 1, TPMLFRect.Make(4, 4, 20, 14));
    RW.RenderTexture(TW, TPMLFRect.Make(1.5, 1.5, 3, 3), TPMLFRect.Make(6, 6, 16, 10));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 0, 1.5, 1.5), TPMLFRect.Make(4, 4, 2, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(4.5, 0, 1.5, 1.5), TPMLFRect.Make(22, 4, 2, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(4.5, 4.5, 1.5, 1.5), TPMLFRect.Make(22, 16, 2, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 4.5, 1.5, 1.5), TPMLFRect.Make(4, 16, 2, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 1.5, 1.5, 3), TPMLFRect.Make(4, 6, 2, 10));
    RW.RenderTexture(TW, TPMLFRect.Make(4.5, 1.5, 1.5, 3), TPMLFRect.Make(22, 6, 2, 10));
    RW.RenderTexture(TW, TPMLFRect.Make(1.5, 0, 3, 1.5), TPMLFRect.Make(6, 4, 16, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(1.5, 4.5, 3, 1.5), TPMLFRect.Make(6, 16, 16, 2));
    Show('9 つに分ける（枠 1.5、倍率 1 でも切り上げて 2）');

    // 枠がすべて 0: 中央だけが転送先いっぱいに伸びる。画面全体を塗らない
    Both;
    R.RenderTexture9Grid(T, TPMLFRect.Make(0, 0, 0, 0), 0, 0, 0, 0, 1, TPMLFRect.Make(10, 10, 12, 8));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 0, 6, 6), TPMLFRect.Make(10, 10, 12, 8));
    Show('枠がすべて 0 なら中央だけ（幅 0 の区画で画面全体を塗らない）');

    // 9GridTiled: 中央と辺は 1 倍で敷き詰める
    Both;
    R.RenderTexture9GridTiled(T, TPMLFRect.Make(0, 0, 0, 0), 2, 2, 2, 2, 1,
      TPMLFRect.Make(4, 4, 11, 9), 1);
    RW.RenderTextureTiled(TW, TPMLFRect.Make(2, 2, 2, 2), 1, TPMLFRect.Make(6, 6, 7, 5));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 0, 2, 2), TPMLFRect.Make(4, 4, 2, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(4, 0, 2, 2), TPMLFRect.Make(13, 4, 2, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(4, 4, 2, 2), TPMLFRect.Make(13, 11, 2, 2));
    RW.RenderTexture(TW, TPMLFRect.Make(0, 4, 2, 2), TPMLFRect.Make(4, 11, 2, 2));
    RW.RenderTextureTiled(TW, TPMLFRect.Make(0, 2, 2, 2), 1, TPMLFRect.Make(4, 6, 2, 5));
    RW.RenderTextureTiled(TW, TPMLFRect.Make(4, 2, 2, 2), 1, TPMLFRect.Make(13, 6, 2, 5));
    RW.RenderTextureTiled(TW, TPMLFRect.Make(2, 0, 2, 2), 1, TPMLFRect.Make(6, 4, 7, 2));
    RW.RenderTextureTiled(TW, TPMLFRect.Make(2, 4, 2, 2), 1, TPMLFRect.Make(6, 11, 7, 2));
    Show('9GridTiled（中央と辺は敷き詰める）');

    Raised := False;
    try
      R.RenderTexture9GridTiled(T, TPMLFRect.Make(0, 0, 0, 0), 2, 2, 2, 2, 1,
        TPMLFRect.Make(4, 4, 11, 9), 0);
    except
      on E: EPMLArgument do Raised := True;
    end;
    Check(Raised, '9GridTiled の敷き詰めの倍率 0 は EPMLArgument（SDL も失敗する）');
  finally
    R.Free;
    RW.Free;
    Target.Free;
    Want.Free;
    Tex.Free;
  end;
  WriteLn;
end;

begin
  WriteLn('test_render_transform — 回す・写す・敷き詰める・9 つに分ける');
  WriteLn;
  BG := TPMLColor.Make(9, 9, 9);
  TestRotated;
  TestAffine;
  TestTiledAnd9Grid;
  if Failures = 0 then
    WriteLn('=== 結論: 回す・写す・敷き詰める・9 つに分けるが期待の絵と一致する ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
