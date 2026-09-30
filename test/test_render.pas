{
  test_render — レンダラの抽象とソフトウェアドライバ

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    コマンドキュー（積み方・結合・状態の重複排除）、ソフトウェアドライバの描画、
    三角形のラスタライザを検査する。

  WHY:
    TPMLRenderDriver は矩形・転送を既定で三角形へ落とし、ソフトウェアドライバは
    それを上書きして速い経路を持つ。**同じ絵を 2 つの経路で描いて、画素が完全に
    一致すること**を見るのが中心の検査である。

    一致を見るときは半透明の合成で描く。対角線を共有する三角形 2 枚が同じ画素を
    二重に塗れば、その画素だけ濃くなる。塗り残せば元の色のまま残る。
    どちらも「完全一致」を崩すので、top-left 規則の誤りは必ず表に出る。

    三角形のラスタライザには、テスト側に浮動小数点で書いた別の判定を当てる。
    斜めの辺を共有する三角形の扇を Add で描き、全画素がちょうど 1 回だけ
    塗られることも確かめる。

  実行前提: 無し。
}
program test_render;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.Blit,
  PaPiMeLa.Surface.BMP,
  PaPiMeLa.Render,
  PaPiMeLa.Render.Software,
  PaPiMeLa.Render.Software.Raster;

type
  { 速い経路を持たないソフトウェアドライバ。矩形と転送を必ず三角形で描く。

    既定の変換（QueueXxxAsGeometry）は protected なので、派生すれば呼べる。
    本物のソフトウェアドライバと同じ絵を描けるかで、既定の変換とラスタライザを
    同時に検査する。 }
  TGeometryOnlyDriver = class(TPMLSoftwareRenderDriver)
  public
    procedure QueueFillRects(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const ARects: array of TPMLFRect); override;
    procedure QueueCopy(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      ATexture: TPMLTexture; const ASrc, ADst: TPMLFRect); override;
  end;

procedure TGeometryOnlyDriver.QueueFillRects(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const ARects: array of TPMLFRect);
begin
  QueueFillRectsAsGeometry(AQueue, ACmd, ARects);
end;

procedure TGeometryOnlyDriver.QueueCopy(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; ATexture: TPMLTexture; const ASrc, ADst: TPMLFRect);
begin
  QueueCopyAsGeometry(AQueue, ACmd, ATexture, ASrc, ADst);
end;

var
  Failures: Integer = 0;
  OutDir  : String;

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

procedure Note(const AText: String);
begin
  WriteLn('  [観測] ', AText);
end;

function SameColor(const A, B: TPMLColor): Boolean;
begin
  Result := (A.R = B.R) and (A.G = B.G) and (A.B = B.B) and (A.A = B.A);
end;

// 2 枚のサーフェスで異なる画素の数。0 なら完全一致。
function CountDiff(A, B: TPMLSurface; out AFirstX, AFirstY: Integer): Integer;
var
  X, Y: Integer;
begin
  Result := 0;
  AFirstX := -1;
  AFirstY := -1;
  for Y := 0 to A.Height - 1 do
    for X := 0 to A.Width - 1 do
      if not SameColor(A.ReadPixel(X, Y), B.ReadPixel(X, Y)) then
      begin
        if Result = 0 then
        begin
          AFirstX := X;
          AFirstY := Y;
        end;
        Inc(Result);
      end;
end;

function V(AX, AY: Single; AR, AG, AB, AA: Single): TPMLVertex;
begin
  Result.Position := TPMLFPoint.Make(AX, AY);
  Result.Color := TPMLFColor.Make(AR, AG, AB, AA);
  Result.TexCoord := TPMLFPoint.Make(0, 0);
end;

function VT(AX, AY, AU, AV: Single): TPMLVertex;
begin
  Result.Position := TPMLFPoint.Make(AX, AY);
  Result.Color := TPMLFColor.Make(1, 1, 1, 1);
  Result.TexCoord := TPMLFPoint.Make(AU, AV);
end;

{ ---- テスト側の三角形判定（浮動小数点。実装とは別の道筋） ----

  画素 (px, py) の中心 (px + 0.5, py + 0.5) が三角形の内側か。
  辺の上にちょうど乗ったら、その辺が上辺か左辺のときだけ内側とする。 }
function EdgeF(AX0, AY0, AX1, AY1, APX, APY: Double): Double;
begin
  Result := (AX1 - AX0) * (APY - AY0) - (AY1 - AY0) * (APX - AX0);
end;

// 時計回り（画面座標で y が下向き）に揃えた辺が、上辺か左辺か。
function IsTopLeftF(AX0, AY0, AX1, AY1: Double): Boolean;
begin
  // 上辺: 水平で、右へ向かう。左辺: 上へ向かう（y が減る）。
  Result := ((AY0 = AY1) and (AX1 > AX0)) or (AY1 < AY0);
end;

function RefCovers(const A, B, C: TPMLFPoint; APX, APY: Integer): Boolean;

  // 実装は 1/256 画素の精度で座標を持つと仕様で決めている。参照も同じ格子に
  // 丸めてから計算する。丸めないと、辺のごく近くの画素で「仕様より良い精度」の
  // 参照と食い違い、実装の誤りではない失敗が出る。
  function Q(AValue: Single): Double;
  begin
    Result := Round(AValue * 256) / 256;
  end;

var
  X0, Y0, X1, Y1, X2, Y2, PX, PY, Area, W0, W1, W2: Double;
  T: Double;
begin
  X0 := Q(A.X); Y0 := Q(A.Y); X1 := Q(B.X); Y1 := Q(B.Y); X2 := Q(C.X); Y2 := Q(C.Y);
  Area := EdgeF(X0, Y0, X1, Y1, X2, Y2);
  if Area = 0 then
    Exit(False);
  // 画面座標で Area > 0 が時計回り。反時計回りなら 2 点を入れ替えて揃える。
  if Area < 0 then
  begin
    T := X1; X1 := X2; X2 := T;
    T := Y1; Y1 := Y2; Y2 := T;
  end;
  PX := APX + 0.5;
  PY := APY + 0.5;
  W0 := EdgeF(X1, Y1, X2, Y2, PX, PY);
  W1 := EdgeF(X2, Y2, X0, Y0, PX, PY);
  W2 := EdgeF(X0, Y0, X1, Y1, PX, PY);
  Result := ((W0 > 0) or ((W0 = 0) and IsTopLeftF(X1, Y1, X2, Y2)))
        and ((W1 > 0) or ((W1 = 0) and IsTopLeftF(X2, Y2, X0, Y0)))
        and ((W2 > 0) or ((W2 = 0) and IsTopLeftF(X0, Y0, X1, Y1)));
end;

{ 1 枚の三角形を実装で塗り、参照判定と画素ごとに比べる。 }
function TriangleMatchesRef(const A, B, C: TPMLFPoint; out ADiff: Integer): Boolean;
var
  S: TPMLSurface;
  X, Y: Integer;
  Painted, Expected: Boolean;
begin
  S := TPMLSurface.Create(24, 24, PML_PIXELFORMAT_ARGB8888);
  try
    S.Fill(TPMLColor.Black);
    PMLRasterTriangle(S, V(A.X, A.Y, 1, 1, 1, 1), V(B.X, B.Y, 1, 1, 1, 1),
      V(C.X, C.Y, 1, 1, 1, 1), nil, TPMLBlendMode.None, 0, 0);
    ADiff := 0;
    for Y := 0 to S.Height - 1 do
      for X := 0 to S.Width - 1 do
      begin
        Painted := S.ReadPixel(X, Y).R = 255;
        Expected := RefCovers(A, B, C, X, Y);
        if Painted <> Expected then
          Inc(ADiff);
      end;
    Result := ADiff = 0;
  finally
    S.Free;
  end;
end;

{ 同じ場面を描く。速い経路のドライバと三角形だけのドライバの両方で呼ぶ。

  半透明の Blend で描くのが要点。二重塗りや塗り残しが色の違いとして出る。 }
procedure DrawScene(R: TPMLRenderer);
begin
  R.DrawColor := TPMLColor.Make(20, 30, 40, 255);
  R.BlendMode := TPMLBlendMode.None;
  R.Clear;

  R.BlendMode := TPMLBlendMode.Blend;
  R.DrawColor := TPMLColor.Make(255, 60, 0, 128);
  R.FillRect(TPMLFRect.Make(2, 2, 17, 11));          // 奇数の幅と高さ
  R.DrawColor := TPMLColor.Make(0, 200, 255, 100);
  R.FillRect(TPMLFRect.Make(10, 6, 13, 9));          // 前の矩形と重なる
  R.DrawColor := TPMLColor.Make(255, 255, 0, 160);
  R.FillRect(TPMLFRect.Make(30, 3, 1, 1));           // 1x1
  R.FillRect(TPMLFRect.Make(33, 3, 1, 12));          // 幅 1
  R.FillRect(TPMLFRect.Make(36, 3, 9, 1));           // 高さ 1
  R.DrawColor := TPMLColor.Make(120, 255, 120, 90);
  R.FillRect(TPMLFRect.Make(3.5, 18.5, 10, 6));      // 画素の中心に端が乗る
  R.FillRect(TPMLFRect.Make(20.25, 18.75, 7.5, 5.5)); // 端が中心に乗らない
  R.DrawColor := TPMLColor.Make(255, 255, 255, 60);
  R.FillRect(TPMLFRect.Make(-4, 26, 14, 8));         // 画面の外へはみ出す
  R.FillRect(TPMLFRect.Make(40, 26, 20, 20));
end;

var
  Target, Target2, Ref, Img, Shot: TPMLSurface;
  R, R2       : TPMLRenderer;
  Tex, Tex2   : TPMLTexture;
  I, J, X, Y  : Integer;
  DX, DY, Diff: Integer;
  OK          : Boolean;
  Pts         : array of TPMLFPoint;
  Verts       : array of TPMLVertex;
  C           : TPMLColor;
  Cx, Cy      : Single;
  Ang0, Ang1  : Double;
  Bad, Total  : Integer;
begin
  WriteLn('test_render — レンダラとソフトウェアドライバ');
  WriteLn;
  OutDir := GetTempDir(False);

  WriteLn('1. 三角形のラスタライザ（テスト側の参照判定と突き合わせる）');
  // 時計回り・反時計回り、細い三角形、辺が画素の中心に乗るもの。
  OK := TriangleMatchesRef(TPMLFPoint.Make(2, 2), TPMLFPoint.Make(18, 4),
    TPMLFPoint.Make(6, 20), Diff);
  Check(OK, Format('時計回りの三角形が参照と一致する（不一致 %d 画素）', [Diff]));
  OK := TriangleMatchesRef(TPMLFPoint.Make(2, 2), TPMLFPoint.Make(6, 20),
    TPMLFPoint.Make(18, 4), Diff);
  Check(OK, Format('反時計回りでも一致する（不一致 %d 画素）', [Diff]));
  OK := TriangleMatchesRef(TPMLFPoint.Make(1, 1), TPMLFPoint.Make(22, 3),
    TPMLFPoint.Make(2, 2.5), Diff);
  Check(OK, Format('細長い三角形でも一致する（不一致 %d 画素）', [Diff]));
  OK := TriangleMatchesRef(TPMLFPoint.Make(3.5, 3.5), TPMLFPoint.Make(15.5, 3.5),
    TPMLFPoint.Make(3.5, 15.5), Diff);
  Check(OK, Format('辺が画素の中心に乗る三角形でも一致する（不一致 %d 画素）', [Diff]));
  OK := TriangleMatchesRef(TPMLFPoint.Make(5.3, 2.7), TPMLFPoint.Make(19.9, 11.2),
    TPMLFPoint.Make(8.1, 21.6), Diff);
  Check(OK, Format('端数のある頂点でも一致する（不一致 %d 画素）', [Diff]));

  // 面積 0 は何も塗らない。
  Img := TPMLSurface.Create(8, 8, PML_PIXELFORMAT_ARGB8888);
  try
    Img.Fill(TPMLColor.Black);
    PMLRasterTriangle(Img, V(1, 1, 1, 1, 1, 1), V(5, 5, 1, 1, 1, 1),
      V(3, 3, 1, 1, 1, 1), nil, TPMLBlendMode.None, 0, 0);
    OK := True;
    for Y := 0 to 7 do
      for X := 0 to 7 do
        if Img.ReadPixel(X, Y).R <> 0 then
          OK := False;
    Check(OK, '面積 0 の三角形は何も塗らない');
  finally
    Img.Free;
  end;

  WriteLn;
  WriteLn('2. 辺を共有する三角形の扇（全画素がちょうど 1 回塗られるか）');
  // 中心から 12 本の放射線で円を 12 枚に分ける。共有する辺はすべて斜め。
  // Add で 20 ずつ足すので、二重に塗られた画素は 40、塗り残しは 0 になる。
  Img := TPMLSurface.Create(40, 40, PML_PIXELFORMAT_ARGB8888);
  try
    Img.Fill(TPMLColor.Make(0, 0, 0, 255));
    Cx := 20.3;
    Cy := 19.7;
    for I := 0 to 11 do
    begin
      Ang0 := I * 2 * Pi / 12;
      Ang1 := (I + 1) * 2 * Pi / 12;
      PMLRasterTriangle(Img,
        V(Cx, Cy, 20 / 255, 0, 0, 1),
        V(Cx + 16 * Cos(Ang0), Cy + 16 * Sin(Ang0), 20 / 255, 0, 0, 1),
        V(Cx + 16 * Cos(Ang1), Cy + 16 * Sin(Ang1), 20 / 255, 0, 0, 1),
        nil, TPMLBlendMode.Add, 0, 0);
    end;
    Bad := 0;
    Total := 0;
    for Y := 0 to 39 do
      for X := 0 to 39 do
      begin
        C := Img.ReadPixel(X, Y);
        if C.R <> 0 then
        begin
          Inc(Total);
          if C.R <> 20 then
            Inc(Bad);
        end;
      end;
    Check(Bad = 0, Format('12 枚の扇で二重塗りも塗り残しも無い（異常 %d / 塗った %d 画素）',
      [Bad, Total]));
    // 何も塗らなければ「異常 0」で素通りしてしまう。半径 16 の正 12 角形の面積は
    // 約 768 画素なので、それに近い数を塗っていることも確かめる。
    Check(Total > 700, Format('扇が面積どおりに塗られている（%d 画素、約 768 の見込み）',
      [Total]));
    // 中心付近に穴が開いていないこと（全三角形が接する点）。
    Check(Img.ReadPixel(20, 19).R = 20, '全ての三角形が接する中心にも穴が無い');
    PMLSaveBMPFile(OutDir + 'papimela-render-fan.bmp', Img);
  finally
    Img.Free;
  end;

  WriteLn;
  WriteLn('3. 頂点色の補間');
  Img := TPMLSurface.Create(64, 64, PML_PIXELFORMAT_ARGB8888);
  try
    Img.Fill(TPMLColor.Black);
    PMLRasterTriangle(Img, V(2, 2, 1, 0, 0, 1), V(62, 2, 0, 1, 0, 1),
      V(2, 62, 0, 0, 1, 1), nil, TPMLBlendMode.None, 0, 0);
    C := Img.ReadPixel(3, 3);
    Check((C.R > 230) and (C.G < 20) and (C.B < 20),
      Format('赤の頂点の近くは赤（R=%d G=%d B=%d）', [C.R, C.G, C.B]));
    C := Img.ReadPixel(59, 3);
    Check((C.G > 210) and (C.R < 30),
      Format('緑の頂点の近くは緑（R=%d G=%d B=%d）', [C.R, C.G, C.B]));
    C := Img.ReadPixel(3, 59);
    Check((C.B > 210) and (C.R < 30),
      Format('青の頂点の近くは青（R=%d G=%d B=%d）', [C.R, C.G, C.B]));
    // 重心 (22, 22) では 3 色がほぼ等分になる。
    C := Img.ReadPixel(21, 21);
    Check((Abs(C.R - 85) < 12) and (Abs(C.G - 85) < 12) and (Abs(C.B - 85) < 12),
      Format('重心では 3 色がほぼ等分（R=%d G=%d B=%d）', [C.R, C.G, C.B]));
    PMLSaveBMPFile(OutDir + 'papimela-render-gradient.bmp', Img);
  finally
    Img.Free;
  end;

  // テクスチャに掛ける頂点色は補間した値でなければならない。頂点 0 の色だけを
  // 掛けると、下の三角形は一様な色になる（qwen の生成物にあった誤り。D-33）。
  // 他の検査は頂点色が一様な場合しか通らないので、ここで別に押さえる。
  Img := TPMLSurface.Create(32, 32, PML_PIXELFORMAT_ARGB8888);
  Ref := TPMLSurface.Create(2, 2, PML_PIXELFORMAT_ARGB8888);
  try
    Ref.Fill(TPMLColor.White);
    Img.Fill(TPMLColor.Black);
    Verts := nil;
    SetLength(Verts, 3);
    Verts[0] := VT(0, 0, 0, 0);    Verts[0].Color := TPMLFColor.Make(1, 1, 1, 1);
    Verts[1] := VT(32, 0, 1, 0);   Verts[1].Color := TPMLFColor.Make(0, 0, 0, 1);
    Verts[2] := VT(0, 32, 0, 1);   Verts[2].Color := TPMLFColor.Make(0, 0, 0, 1);
    PMLRasterTriangle(Img, Verts[0], Verts[1], Verts[2], Ref,
      TPMLBlendMode.None, 0, 0);
    Check(Img.ReadPixel(1, 1).R > 200,
      Format('白い頂点の近くは明るい（R=%d）', [Img.ReadPixel(1, 1).R]));
    Check(Img.ReadPixel(28, 1).R < 40,
      Format('黒い頂点の近くは暗い（R=%d）。頂点 0 の色だけを掛けると明るいまま',
        [Img.ReadPixel(28, 1).R]));
  finally
    Img.Free;
    Ref.Free;
  end;

  WriteLn;
  WriteLn('4. 速い経路と三角形の経路が同じ絵を描くか（中心の検査）');
  Target := TPMLSurface.Create(48, 36, PML_PIXELFORMAT_ARGB8888);
  Target2 := TPMLSurface.Create(48, 36, PML_PIXELFORMAT_ARGB8888);
  R := TPMLRenderer.CreateSoftware(Target);
  R2 := TPMLRenderer.Create(TGeometryOnlyDriver.Create(Target2));
  try
    DrawScene(R);
    DrawScene(R2);
    R.Present;
    R2.Present;
    Diff := CountDiff(Target, Target2, DX, DY);
    Check(Diff = 0, Format('半透明の矩形 9 枚が完全に一致する（不一致 %d 画素、最初 (%d,%d)）',
      [Diff, DX, DY]));
    PMLSaveBMPFile(OutDir + 'papimela-render-rects.bmp', Target);
  finally
    R.Free;
    R2.Free;
    Target.Free;
    Target2.Free;
  end;

  // テクスチャ転送も同じ。等倍と 2 倍と縮小で、ブリットと三角形が一致するか。
  Img := TPMLSurface.Create(8, 6, PML_PIXELFORMAT_ARGB8888);
  Target := TPMLSurface.Create(40, 30, PML_PIXELFORMAT_ARGB8888);
  Target2 := TPMLSurface.Create(40, 30, PML_PIXELFORMAT_ARGB8888);
  try
    for Y := 0 to 5 do
      for X := 0 to 7 do
        Img.WritePixel(X, Y, TPMLColor.Make(Byte(X * 30), Byte(Y * 40), 128, 255));
    R := TPMLRenderer.CreateSoftware(Target);
    R2 := TPMLRenderer.Create(TGeometryOnlyDriver.Create(Target2));
    try
      Tex := R.CreateTextureFromSurface(Img);
      Tex2 := R2.CreateTextureFromSurface(Img);
      R.DrawColor := TPMLColor.Black;  R.Clear;
      R2.DrawColor := TPMLColor.Black; R2.Clear;
      R.RenderTexture(Tex, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(1, 1, 8, 6));
      R2.RenderTexture(Tex2, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(1, 1, 8, 6));
      R.RenderTexture(Tex, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(12, 1, 16, 12));
      R2.RenderTexture(Tex2, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(12, 1, 16, 12));
      R.RenderTexture(Tex, TPMLFRect.Make(2, 1, 4, 4), TPMLFRect.Make(30, 1, 2, 2));
      R2.RenderTexture(Tex2, TPMLFRect.Make(2, 1, 4, 4), TPMLFRect.Make(30, 1, 2, 2));
      R.Present;
      R2.Present;
      Diff := CountDiff(Target, Target2, DX, DY);
      Check(Diff = 0, Format('テクスチャ転送（等倍・2 倍・縮小）が一致する（不一致 %d 画素、最初 (%d,%d)）',
        [Diff, DX, DY]));
    finally
      R.Free;
      R2.Free;
    end;
  finally
    Img.Free;
    Target.Free;
    Target2.Free;
  end;

  WriteLn;
  WriteLn('5. コマンドキュー');
  Target := TPMLSurface.Create(32, 32, PML_PIXELFORMAT_ARGB8888);
  R := TPMLRenderer.CreateSoftware(Target);
  try
    R.DrawColor := TPMLColor.Make(255, 0, 0, 255);
    R.FillRect(TPMLFRect.Make(0, 0, 4, 4));
    R.FillRect(TPMLFRect.Make(5, 0, 4, 4));
    R.FillRect(TPMLFRect.Make(10, 0, 4, 4));
    // 状態コマンド 2 つ（Viewport と Clip）と、結合された描画 1 つ。
    Check(R.Queue.CommandCount = 3,
      Format('同じ状態の描画 3 回は 1 つのコマンドに結合される（コマンド %d）',
        [R.Queue.CommandCount]));
    Check(R.Queue.Commands[2].Count = 3, '結合されたコマンドが 3 矩形を持つ');
    R.DrawColor := TPMLColor.Make(0, 255, 0, 255);
    R.FillRect(TPMLFRect.Make(15, 0, 4, 4));
    Check(R.Queue.CommandCount = 4, '色が変わると新しいコマンドになる');
    Check(Target.ReadPixel(1, 1).R = 0, 'Present 前は描画先に何も書かれていない');
    R.Present;
    Check(R.Queue.CommandCount = 0, 'Present でキューが空になる');
    Check(SameColor(Target.ReadPixel(1, 1), TPMLColor.Make(255, 0, 0, 255)),
      'Present 後は描かれている');
    Check(SameColor(Target.ReadPixel(16, 1), TPMLColor.Make(0, 255, 0, 255)),
      '色の違う描画も描かれている');
  finally
    R.Free;
    Target.Free;
  end;

  WriteLn;
  WriteLn('6. ビューポートとクリップ');
  Target := TPMLSurface.Create(32, 32, PML_PIXELFORMAT_ARGB8888);
  R := TPMLRenderer.CreateSoftware(Target);
  try
    R.DrawColor := TPMLColor.Black;
    R.Clear;
    R.Viewport := TPMLRect.Make(10, 10, 12, 12);
    R.DrawColor := TPMLColor.White;
    R.FillRect(TPMLFRect.Make(0, 0, 4, 4));      // ビューポートの原点からの相対
    R.Present;
    Check(SameColor(Target.ReadPixel(10, 10), TPMLColor.White),
      'ビューポートの原点へ描かれる');
    Check(SameColor(Target.ReadPixel(0, 0), TPMLColor.Black),
      '描画先の原点には描かれない');

    R.FillRect(TPMLFRect.Make(-5, -5, 40, 40));   // ビューポートの外へはみ出す
    R.Present;
    Check(SameColor(Target.ReadPixel(9, 9), TPMLColor.Black),
      'ビューポートの外は塗られない');
    Check(SameColor(Target.ReadPixel(21, 21), TPMLColor.White),
      'ビューポートの右下端は塗られる');
    Check(SameColor(Target.ReadPixel(22, 22), TPMLColor.Black),
      'ビューポートの 1 つ外は塗られない');

    // Clear はビューポートもクリップも無視して描画先の全体を塗る
    // （SDL_RenderClear の契約。D-35）。
    R.ClipRect := TPMLRect.Make(2, 2, 3, 3);
    R.DrawColor := TPMLColor.Make(0, 0, 255, 255);
    R.Clear;
    R.Present;
    Check(SameColor(Target.ReadPixel(10, 10), TPMLColor.Make(0, 0, 255, 255)),
      'Clear はクリップ矩形を無視する');
    Check(SameColor(Target.ReadPixel(0, 0), TPMLColor.Make(0, 0, 255, 255))
      and SameColor(Target.ReadPixel(31, 31), TPMLColor.Make(0, 0, 255, 255)),
      'Clear はビューポートも無視して全体を塗る');

    R.DrawColor := TPMLColor.Make(255, 0, 0, 255);
    R.FillRect(TPMLFRect.Make(0, 0, 12, 12));
    R.Present;
    Check(SameColor(Target.ReadPixel(12, 12), TPMLColor.Make(255, 0, 0, 255)),
      'クリップ矩形の中は塗られる（ビューポートからの相対）');
    Check(SameColor(Target.ReadPixel(10, 10), TPMLColor.Make(0, 0, 255, 255)),
      'クリップ矩形の外は塗られない');
  finally
    R.Free;
    Target.Free;
  end;

  WriteLn;
  WriteLn('7. 線と点');
  Target := TPMLSurface.Create(20, 20, PML_PIXELFORMAT_ARGB8888);
  R := TPMLRenderer.CreateSoftware(Target);
  try
    R.DrawColor := TPMLColor.Black;
    R.Clear;
    R.DrawColor := TPMLColor.White;
    R.DrawLine(2, 2, 12, 2);
    R.DrawLine(2, 5, 2, 15);
    R.DrawLine(5, 5, 15, 15);
    R.DrawPoint(18, 18);
    R.Present;
    OK := True;
    for X := 2 to 12 do
      if not SameColor(Target.ReadPixel(X, 2), TPMLColor.White) then
        OK := False;
    Check(OK, '水平線が両端を含めて引かれる');
    Check(SameColor(Target.ReadPixel(2, 15), TPMLColor.White), '垂直線の終端が塗られる');
    OK := True;
    for I := 5 to 15 do
      if not SameColor(Target.ReadPixel(I, I), TPMLColor.White) then
        OK := False;
    Check(OK, '45 度の線が対角の画素を通る');
    Check(SameColor(Target.ReadPixel(18, 18), TPMLColor.White), '点が塗られる');
    Check(SameColor(Target.ReadPixel(13, 2), TPMLColor.Black), '線の終端の先は塗られない');

    // 枠線。4 隅が塗られ、中は塗られない。
    R.DrawColor := TPMLColor.Black;
    R.Clear;
    R.DrawColor := TPMLColor.White;
    R.DrawRect(TPMLFRect.Make(3, 3, 10, 8));
    R.Present;
    Check(SameColor(Target.ReadPixel(3, 3), TPMLColor.White)
      and SameColor(Target.ReadPixel(12, 3), TPMLColor.White)
      and SameColor(Target.ReadPixel(12, 10), TPMLColor.White)
      and SameColor(Target.ReadPixel(3, 10), TPMLColor.White),
      '枠線の 4 隅が塗られる');
    Check(SameColor(Target.ReadPixel(7, 6), TPMLColor.Black), '枠線の内側は塗られない');
  finally
    R.Free;
    Target.Free;
  end;

  WriteLn;
  WriteLn('8. テクスチャの寿命と読み出し');
  Target := TPMLSurface.Create(16, 16, PML_PIXELFORMAT_ARGB8888);
  R := TPMLRenderer.CreateSoftware(Target);
  try
    Tex := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Static, 4, 4);
    Check(Length(R.Textures) = 1, 'テクスチャがレンダラの一覧に載る');
    Check(Tex.DriverData is TPMLSurface, 'ソフトウェアドライバの中身はサーフェス');
    Tex.Free;
    Check(Length(R.Textures) = 0, 'テクスチャを先に解放すると一覧から消える');

    // テクスチャを残したままレンダラを解放しても落ちないこと（下の R.Free で確かめる）。
    R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Static, 4, 4);
    R.CreateTexture(PML_PIXELFORMAT_ABGR8888, TPMLTextureAccess.Static, 2, 2);

    R.DrawColor := TPMLColor.Make(10, 20, 30, 255);
    R.Clear;
    R.DrawColor := TPMLColor.Make(200, 100, 50, 255);
    R.FillRect(TPMLFRect.Make(4, 4, 4, 4));
    // ReadPixels は積んだ描画を先に吐き出す。
    Shot := R.ReadPixels(TPMLRect.Make(3, 3, 6, 6));
    try
      Check((Shot.Width = 6) and (Shot.Height = 6), '読み出した大きさが合う');
      Check(SameColor(Shot.ReadPixel(0, 0), TPMLColor.Make(10, 20, 30, 255)),
        '読み出した左上は背景');
      Check(SameColor(Shot.ReadPixel(1, 1), TPMLColor.Make(200, 100, 50, 255)),
        '読み出した中は描いた色（Present 前でも Flush される）');
    finally
      Shot.Free;
    end;
  finally
    R.Free;
    Target.Free;
  end;
  Check(True, 'テクスチャを残したままレンダラを解放しても落ちない');

  WriteLn;
  WriteLn('9. 見本の画像');
  Note('描いた画像を ' + OutDir + ' に保存した:');
  Note('  papimela-render-fan.bmp      三角形 12 枚の扇');
  Note('  papimela-render-gradient.bmp 頂点色の補間');
  Note('  papimela-render-rects.bmp    半透明の矩形の重ね合わせ');

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn('=== 結論: レンダラが設計どおりに描く ===');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('=== 失敗 %d 件 ===', [Failures]));
    ExitCode := 1;
  end;
end.
