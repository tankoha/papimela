{
  test_render_gles2 — GPU（OpenGL ES 2.0）のドライバをソフトウェアのドライバと比べる

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. オフスクリーン（窓の無い GL）で、同じ場面を GLES2 のドライバとソフトウェアの
       ドライバの両方で描き、画素ごとに比べる。場面ごとに許す差（1 成分あたり）と、
       それを超えてよい画素の数を決めてある
    2. ウィンドウ（実機のコンポジタがあるときだけ）: ドライバの選び方、読み戻しの
       向き、VSync、大きさの変更、破棄の順序

  WHY:
    #43 の受け入れ検査。実装（Sonnet）より先に書いた。ソフトウェアのドライバは
    T-16 で「矩形と三角形の経路が完全一致する」ところまで確かめてあるので、
    それを正解として GPU の結果を測る。

    許す差の考え方:
    - 塗り・転送（最近傍）・ビューポート・クリップは位置も色も完全一致（差 0）
    - 合成は GPU と整数計算の丸めが違うので 1 成分 2 まで
    - 頂点色の補間は GPU の補間精度があるので 1 成分 2 まで
    - 斜めの線だけは GL の線の規則（菱形の出口規則）がブレゼンハムと違うので、
      何画素かずれることを許す

  実行前提: 1 は EGL と Mesa の surfaceless があれば行う（使えなければ失敗。GL の無い環境で
            飛ばすには PAPIMELA_GL_OPTIONAL=1）。
            2 は Wayland セッションがあれば行う。
}
program test_render_gles2;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Render,
  PaPiMeLa.Render.GLES2,
  PaPiMeLa.Core;

const
  W = 64;
  H = 64;

type
  TScene = procedure(R: TPMLRenderer);

var
  Failures: Integer = 0;
  Checker, Gradient: TPMLSurface;   // 場面で使うテクスチャの元

procedure Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
    WriteLn('  [PASS] ', ALabel)
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(Failures);
  end;
  // パイプへの出力は FPC がためるので、止まったときに場所が分かるよう毎回吐き出す。
  Flush(Output);
end;

function FR(AX, AY, AW, AH: Single): TPMLFRect; inline;
begin
  Result := TPMLFRect.Make(AX, AY, AW, AH);
end;

function V(AX, AY: Single; AR, AG, AB, AA: Single; AU: Single = 0; AV: Single = 0): TPMLVertex;
begin
  Result.Position := TPMLFPoint.Make(AX, AY);
  Result.Color := TPMLFColor.Make(AR, AG, AB, AA);
  Result.TexCoord := TPMLFPoint.Make(AU, AV);
end;

procedure Background(R: TPMLRenderer);
begin
  R.BlendMode := TPMLBlendMode.None;
  R.DrawColor := TPMLColor.Make(10, 20, 30, 255);
  R.Clear;
end;

{ ---- 場面 ---- }

procedure SceneClear(R: TPMLRenderer);
begin
  Background(R);
end;

procedure SceneRects(R: TPMLRenderer);
begin
  Background(R);
  R.DrawColor := TPMLColor.Make(255, 0, 0, 255);
  R.FillRect(FR(4, 4, 20, 12));
  R.DrawColor := TPMLColor.Make(0, 255, 0, 255);
  R.FillRects([FR(20, 10, 30, 30), FR(50, 50, 30, 30), FR(-5, 40, 12, 12)]);
  // 小数の座標。塗るのは中心が入る画素（ソフトウェアのドライバの規則）
  R.DrawColor := TPMLColor.Make(0, 0, 255, 255);
  R.FillRect(FR(30.3, 2.6, 7.4, 5.2));
end;

procedure SceneBlend(R: TPMLRenderer);
begin
  Background(R);
  R.DrawColor := TPMLColor.Make(200, 100, 50, 255);
  R.FillRect(FR(0, 0, 40, 64));
  R.BlendMode := TPMLBlendMode.Blend;
  R.DrawColor := TPMLColor.Make(30, 220, 255, 128);
  R.FillRect(FR(20, 8, 40, 40));
end;

procedure SceneBlendModes(R: TPMLRenderer);
const
  Modes: array[0..3] of TPMLBlendMode = (TPMLBlendMode.Blend, TPMLBlendMode.Add,
    TPMLBlendMode.Modulate, TPMLBlendMode.Multiply);
var
  I: Integer;
begin
  Background(R);
  R.DrawColor := TPMLColor.Make(120, 160, 200, 255);
  R.FillRect(FR(0, 0, 64, 32));
  for I := 0 to 3 do
  begin
    R.BlendMode := Modes[I];
    R.DrawColor := TPMLColor.Make(200, 90, 40, 160);
    R.FillRect(FR(I * 16, 16, 16, 32));
  end;
end;

procedure SceneFan(R: TPMLRenderer);
const
  N = 12;
var
  Vs: array of TPMLVertex;
  I: Integer;
  A0, A1: Single;
begin
  Background(R);
  // 加算で薄く重ねる。二重に塗った画素・塗り残した画素はソフトウェアと色が違う。
  R.BlendMode := TPMLBlendMode.Add;
  SetLength(Vs, N * 3);
  for I := 0 to N - 1 do
  begin
    A0 := I * 2 * Pi / N;
    A1 := (I + 1) * 2 * Pi / N;
    Vs[I * 3]     := V(32, 32, 0.2, 0.2, 0.2, 1);
    Vs[I * 3 + 1] := V(32 + 28 * Cos(A0), 32 + 28 * Sin(A0), 0.2, 0.2, 0.2, 1);
    Vs[I * 3 + 2] := V(32 + 28 * Cos(A1), 32 + 28 * Sin(A1), 0.2, 0.2, 0.2, 1);
  end;
  R.RenderGeometry(nil, Vs, []);
end;

procedure SceneGradient(R: TPMLRenderer);
begin
  Background(R);
  R.RenderGeometry(nil, [V(4, 4, 1, 0, 0, 1), V(60, 10, 0, 1, 0, 1), V(20, 60, 0, 0, 1, 1)], []);
end;

procedure SceneCopy(R: TPMLRenderer);
var
  T: TPMLTexture;
begin
  Background(R);
  T := R.CreateTextureFromSurface(Checker);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(5, 7, 16, 16));             // 等倍
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(24, 4, 32, 32));            // 2 倍
  R.RenderTexture(T, FR(4, 4, 8, 8), FR(8, 40, 16, 16));            // 一部を 2 倍
end;

procedure SceneTextureMod(R: TPMLRenderer);
var
  T: TPMLTexture;
begin
  Background(R);
  R.DrawColor := TPMLColor.Make(200, 200, 200, 255);
  R.FillRect(FR(0, 32, 64, 32));
  T := R.CreateTextureFromSurface(Gradient);   // アルファ付き → Blend
  T.ColorMod := TPMLColor.Make(128, 255, 64, 255);
  T.AlphaMod := 200;
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(8, 16, 48, 40));
end;

procedure SceneFormats(R: TPMLRenderer);
var
  S: TPMLSurface;
  T: TPMLTexture;
  Fmt: array[0..3] of TPMLPixelFormat;
  I, X, Y: Integer;
begin
  Background(R);
  Fmt[0] := PML_PIXELFORMAT_ARGB8888;
  Fmt[1] := PML_PIXELFORMAT_ABGR8888;
  Fmt[2] := PML_PIXELFORMAT_XRGB8888;
  Fmt[3] := PML_PIXELFORMAT_RGB24;       // 直接持てなければ変換される
  for I := 0 to 3 do
  begin
    S := TPMLSurface.Create(8, 8, Fmt[I]);
    try
      for Y := 0 to 7 do
        for X := 0 to 7 do
          S.WritePixel(X, Y, TPMLColor.Make(X * 32, Y * 32, 40 * I + 20, 255));
      T := R.CreateTextureFromSurface(S);
      R.RenderTexture(T, FR(0, 0, 0, 0), FR(4 + I * 15, 20, 8, 8));
    finally
      S.Free;
    end;
  end;
end;

procedure SceneTextureUpdate(R: TPMLRenderer);
var
  T: TPMLTexture;
  Patch: array[0..3 * 4 - 1] of LongWord;
  I: Integer;
begin
  Background(R);
  T := R.CreateTextureFromSurface(Checker);
  for I := 0 to High(Patch) do
    Patch[I] := $FF00FF00 or LongWord(I * 20);   // ARGB8888
  T.Update(TPMLRect.Make(2, 3, 4, 3), @Patch[0], 4 * 4);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(8, 8, 32, 32));
end;

procedure SceneViewportClip(R: TPMLRenderer);
begin
  Background(R);
  R.Viewport := TPMLRect.Make(8, 8, 40, 40);
  R.DrawColor := TPMLColor.Make(255, 255, 0, 255);
  R.FillRect(FR(-4, -4, 20, 20));                  // ビューポートの外へはみ出す
  R.ClipRect := TPMLRect.Make(20, 20, 10, 10);
  R.DrawColor := TPMLColor.Make(0, 255, 255, 255);
  R.FillRect(FR(0, 0, 40, 40));                    // クリップの中だけ
  R.ClipRect := TPMLRect.Make(0, 0, 0, 0);
  R.Viewport := TPMLRect.Make(0, 0, 0, 0);
end;

procedure ScenePoints(R: TPMLRenderer);
var
  P: array of TPMLFPoint;
  I: Integer;
begin
  Background(R);
  R.DrawColor := TPMLColor.Make(255, 255, 255, 255);
  SetLength(P, 20);
  for I := 0 to High(P) do
    P[I] := TPMLFPoint.Make((I * 7) mod 64, (I * 13) mod 64);
  R.DrawPoints(P);
end;

procedure SceneAxisLines(R: TPMLRenderer);
begin
  Background(R);
  R.DrawColor := TPMLColor.Make(255, 128, 0, 255);
  R.DrawLine(3, 5, 60, 5);
  R.DrawLine(10, 8, 10, 58);
  R.DrawLines([TPMLFPoint.Make(20, 20), TPMLFPoint.Make(50, 20), TPMLFPoint.Make(50, 50)]);
  R.DrawColor := TPMLColor.Make(0, 200, 255, 255);
  R.DrawRect(FR(30, 30, 20, 12));
end;

procedure SceneDiagonalLines(R: TPMLRenderer);
begin
  Background(R);
  R.DrawColor := TPMLColor.Make(255, 255, 255, 255);
  R.DrawLine(2, 2, 60, 40);
  R.DrawLine(60, 2, 5, 61);
end;

{ 論理解像度 32x24 を 64x64 へ（Letterbox。2 倍で、上下に 8 画素の帯）。 }
procedure SceneLogical(R: TPMLRenderer);
var
  T: TPMLTexture;
begin
  Background(R);
  R.SetLogicalPresentation(32, 24, TPMLLogicalPresentation.Letterbox);
  R.DrawColor := TPMLColor.Make(30, 30, 30, 255);
  R.Clear;                                          // 帯まで塗る
  T := R.CreateTextureFromSurface(Checker);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(0, 0, 0, 0)); // 論理画面の全体
  R.DrawColor := TPMLColor.Make(255, 0, 0, 255);
  R.FillRect(FR(2, 3, 5, 4));
  R.DrawPoints([TPMLFPoint.Make(20, 2), TPMLFPoint.Make(31, 23)]);
  R.DrawColor := TPMLColor.Make(0, 255, 0, 255);
  R.DrawLine(1, 20, 30, 20);
  R.DrawLine(28, 1, 28, 22);
  R.Viewport := TPMLRect.Make(10, 10, 8, 8);
  R.DrawColor := TPMLColor.Make(255, 255, 0, 255);
  R.FillRect(FR(-2, -2, 6, 6));
  R.Viewport := TPMLRect.Make(0, 0, 0, 0);
  R.SetLogicalPresentation(0, 0, TPMLLogicalPresentation.Disabled);
end;

{ 論理解像度の線は三角形で描く。斜めの線も、閉じた半透明の折れ線も。 }
procedure SceneLogicalLines(R: TPMLRenderer);
begin
  Background(R);
  R.SetLogicalPresentation(32, 24, TPMLLogicalPresentation.Letterbox);
  R.DrawColor := TPMLColor.Make(255, 255, 255, 255);
  R.DrawLine(1, 1, 20, 9);
  R.DrawLine(30, 2, 12, 22);
  R.BlendMode := TPMLBlendMode.Blend;
  R.DrawColor := TPMLColor.Make(255, 128, 0, 128);
  R.DrawLines([TPMLFPoint.Make(3, 12), TPMLFPoint.Make(15, 14), TPMLFPoint.Make(9, 22),
               TPMLFPoint.Make(3, 12)]);
  R.DrawRect(FR(18, 12, 10, 8));
  R.BlendMode := TPMLBlendMode.None;
  R.SetLogicalPresentation(0, 0, TPMLLogicalPresentation.Disabled);
end;

{ 倍率だけ（論理解像度なし）。線は矩形の並びとブレゼンハムの点で描く。 }
procedure SceneScaleLines(R: TPMLRenderer);
begin
  Background(R);
  R.Scale := TPMLFPoint.Make(3, 2);
  R.DrawColor := TPMLColor.Make(255, 255, 255, 255);
  R.DrawLine(1, 1, 18, 9);
  R.DrawLine(2, 30, 19, 12);
  R.DrawRect(FR(4, 14, 12, 10));
  R.FillRect(FR(1, 26, 3, 2));
  R.Scale := TPMLFPoint.Make(1, 1);
end;

{ DebugText。等倍と、論理解像度で 2 倍。1 フレームの中で色を変える（D-43）。 }
procedure SceneDebugText(R: TPMLRenderer);
begin
  Background(R);
  R.DrawColor := TPMLColor.Make(255, 255, 255, 255);
  R.DebugText(1, 1, 'Hi! @#');
  R.DrawColor := TPMLColor.Make(255, 80, 0, 255);
  R.DebugText(1, 10, 'é?あ');
  R.SetLogicalPresentation(32, 24, TPMLLogicalPresentation.Letterbox);
  R.DrawColor := TPMLColor.Make(0, 255, 128, 255);
  R.DebugText(0, 12, 'OK');
  R.DrawColor := TPMLColor.Make(255, 255, 0, 160);
  R.DebugText(16, 12, '42');
  R.SetLogicalPresentation(0, 0, TPMLLogicalPresentation.Disabled);
end;

{ ---- 比較 ---- }

function NewGPU: TPMLRenderer;
begin
  Result := TPMLRenderer.Create(TPMLGLES2RenderDriver.CreateOffscreen(W, H));
end;

function ChannelDiff(const A, B: TPMLColor): Integer;
begin
  Result := Max(Max(Abs(A.R - B.R), Abs(A.G - B.G)), Max(Abs(A.B - B.B), Abs(A.A - B.A)));
end;

{ 回す・写す（#41）。90 度刻みと反転は辺が画素にそろう。30 度と平行四辺形は辺の画素で
  GL とソフトウェアのラスタライズの規則の差が出うる。 }
procedure SceneRotated(R: TPMLRenderer);
var
  T: TPMLTexture;
begin
  Background(R);
  T := R.CreateTextureFromSurface(Checker);
  R.RenderTextureRotated(T, FR(0, 0, 0, 0), FR(4, 4, 16, 16), 90);
  R.RenderTextureRotated(T, FR(0, 0, 0, 0), FR(24, 4, 16, 16), 180, [TPMLFlip.Horizontal]);
  R.RenderTextureRotated(T, FR(4, 4, 8, 8), FR(44, 4, 16, 16), 0, [TPMLFlip.Vertical]);
  R.RenderTextureRotated(T, FR(0, 0, 0, 0), FR(8, 30, 24, 24), 30);
  R.RenderTextureAffine(T, FR(0, 0, 0, 0), TPMLFPoint.Make(36, 30), TPMLFPoint.Make(60, 36),
    TPMLFPoint.Make(34, 58));
end;

{ 敷き詰める・9 つに分ける（#41）。どちらも RenderTexture を並べるだけなので、差は出ない。 }
procedure SceneTiled9Grid(R: TPMLRenderer);
var
  T: TPMLTexture;
begin
  Background(R);
  T := R.CreateTextureFromSurface(Checker);
  R.RenderTextureTiled(T, FR(2, 2, 8, 8), 1, FR(2, 2, 28, 20));
  R.RenderTexture9Grid(T, FR(0, 0, 0, 0), 4, 4, 4, 4, 1, FR(34, 2, 28, 26));
  R.RenderTexture9GridTiled(T, FR(0, 0, 0, 0), 4, 4, 4, 4, 1, FR(2, 30, 40, 30), 1);
end;

{ 描画先のテクスチャ（#41）。4 つの形式の描画先へ、塗り・アルファ付きと X の形式の
  テクスチャ・ビューポートとクリップで描き、描画先どうしでも写し合ってから、出力へ
  拡大して並べる。GPU では FBO のメモリが描画先の形式の並びになっていないと、
  あとで写したときに R と B が入れ替わる。 }
procedure SceneRenderTargets(R: TPMLRenderer);
var
  Fmt: array[0..3] of TPMLPixelFormat;
  T: array[0..3] of TPMLTexture;
  Src, Grad: TPMLTexture;
  XS: TPMLSurface;
  XT: TPMLTexture;
  I, X, Y: Integer;
begin
  Fmt[0] := PML_PIXELFORMAT_ARGB8888;
  Fmt[1] := PML_PIXELFORMAT_ABGR8888;
  Fmt[2] := PML_PIXELFORMAT_XRGB8888;
  Fmt[3] := PML_PIXELFORMAT_XBGR8888;
  Src := R.CreateTextureFromSurface(Checker);
  Grad := R.CreateTextureFromSurface(Gradient);
  XS := TPMLSurface.Create(6, 6, PML_PIXELFORMAT_XRGB8888);
  try
    for Y := 0 to 5 do
      for X := 0 to 5 do
        XS.WritePixel(X, Y, TPMLColor.Make(250 - X * 40, 30 + Y * 40, 90, 255));
    XT := R.CreateTextureFromSurface(XS);
  finally
    XS.Free;
  end;

  for I := 0 to 3 do
  begin
    T[I] := R.CreateTexture(Fmt[I], TPMLTextureAccess.Target, 14, 14);
    R.RenderTarget := T[I];
    R.BlendMode := TPMLBlendMode.None;
    R.DrawColor := TPMLColor.Make(200, 60, 20, 255);    // R と B を見分けられる色
    R.Clear;
    R.DrawColor := TPMLColor.Make(20, 180, 250, 255);
    R.FillRect(FR(1, 1, 5, 3));
    R.RenderTexture(Src, FR(0, 0, 8, 8), FR(7, 1, 6, 6));
    R.RenderTexture(Grad, FR(0, 0, 0, 0), FR(1, 7, 12, 6));   // アルファで合成
    R.Viewport := TPMLRect.Make(2, 4, 8, 8);
    R.ClipRect := TPMLRect.Make(1, 1, 4, 4);
    R.RenderTexture(XT, FR(0, 0, 0, 0), FR(0, 0, 6, 6));     // X の形式。クリップで切る
    R.ClipRect := TPMLRect.Make(0, 0, 0, 0);
    R.Viewport := TPMLRect.Make(0, 0, 0, 0);
  end;
  // 描画先から描画先へ（形式の組で色の写し方が変わる）。
  R.RenderTarget := T[1];
  R.RenderTexture(T[0], FR(0, 0, 0, 0), FR(8, 8, 6, 6));
  R.RenderTarget := T[2];
  R.RenderTexture(T[3], FR(0, 0, 0, 0), FR(0, 8, 6, 6));
  R.RenderTarget := T[3];
  R.RenderTexture(T[1], FR(0, 0, 7, 7), FR(7, 0, 7, 7));

  R.RenderTarget := nil;
  Background(R);
  for I := 0 to 3 do
    R.RenderTexture(T[I], FR(0, 0, 0, 0), FR(2 + (I mod 2) * 31, 2 + (I div 2) * 31, 28, 28));
end;

procedure Compare(const AName: String; AScene: TScene; ATolerance: Integer;
  AMaxBad: Integer = 0);
var
  G, C: TPMLRenderer;
  Target, GS, CS: TPMLSurface;
  X, Y, D, MaxD, Bad, FirstX, FirstY: Integer;
begin
  WriteLn('  ... ', AName);
  Flush(Output);
  Target := TPMLSurface.Create(W, H, PML_PIXELFORMAT_ARGB8888);
  C := TPMLRenderer.CreateSoftware(Target);
  G := NewGPU;
  GS := nil;
  CS := nil;
  try
    AScene(C);
    AScene(G);
    CS := C.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    GS := G.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    MaxD := 0;
    Bad := 0;
    FirstX := -1;
    FirstY := -1;
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
      begin
        D := ChannelDiff(GS.ReadPixel(X, Y), CS.ReadPixel(X, Y));
        if D > MaxD then
          MaxD := D;
        if D > ATolerance then
        begin
          if Bad = 0 then
          begin
            FirstX := X;
            FirstY := Y;
          end;
          Inc(Bad);
        end;
      end;
    if (Bad > AMaxBad) and (FirstX >= 0) then
      WriteLn(Format('  [INFO] %s: 最初の不一致 (%d,%d) GPU=%s CPU=%s', [AName, FirstX, FirstY,
        IntToHex(LongWord(GS.ReadPixel(FirstX, FirstY)), 8),
        IntToHex(LongWord(CS.ReadPixel(FirstX, FirstY)), 8)]));
    Check(Bad <= AMaxBad, Format('%s（最大差 %d、差 %d を超えた画素 %d／許容 %d）',
      [AName, MaxD, ATolerance, Bad, AMaxBad]));
  finally
    GS.Free;
    CS.Free;
    G.Free;
    C.Free;
    Target.Free;
  end;
end;

procedure MakeSources;
var
  X, Y: Integer;
begin
  Checker := TPMLSurface.Create(16, 16, PML_PIXELFORMAT_ARGB8888);
  for Y := 0 to 15 do
    for X := 0 to 15 do
      if ((X div 4) + (Y div 4)) mod 2 = 0 then
        Checker.WritePixel(X, Y, TPMLColor.Make(240, 240, 240, 255))
      else
        Checker.WritePixel(X, Y, TPMLColor.Make(40, 90, 200, 255));
  Gradient := TPMLSurface.Create(16, 16, PML_PIXELFORMAT_ARGB8888);
  for Y := 0 to 15 do
    for X := 0 to 15 do
      Gradient.WritePixel(X, Y, TPMLColor.Make(X * 16, Y * 16, 255 - X * 16, 64 + Y * 12));
end;

procedure OffscreenSection;
var
  G: TPMLRenderer;
  Full, Part: TPMLSurface;
  T: TPMLTexture;
  Ok: Boolean;
  X, Y, OW, OH: Integer;
  M: TPMLBlendMode;
begin
  WriteLn('1. オフスクリーン（ソフトウェアのドライバと比べる）');
  Flush(Output);
  try
    G := NewGPU;
  except
    on E: EPMLUnsupported do
    begin
      // 飛ばしてよいのは、GL の無い環境だと明示されたときだけ。既定では失敗にする
      // （空の実装が「飛ばした」ことで通ってしまわないように）。
      if GetEnvironmentVariable('PAPIMELA_GL_OPTIONAL') = '1' then
        WriteLn('  [SKIP] 窓の無い GL が使えない: ', E.Message)
      else
        Check(False, '窓の無い GL で GLES2 のドライバを作れる（' + E.Message + '）');
      Exit;
    end;
  end;
  try
    Check(G.DriverName = 'gles2', 'ドライバの名前は gles2');
    Check(G.GetOutputSize(OW, OH) and (OW = W) and (OH = H), '出力の大きさ');
    Ok := True;
    for M := Low(TPMLBlendMode) to High(TPMLBlendMode) do
      if not G.Driver.SupportsBlendMode(M) then
        Ok := False;
    Check(Ok, 'すべての合成モードに対応する');
    Check(G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_ARGB8888), 'ARGB8888 のテクスチャを持てる');

    // 部分の読み戻しは、全体の同じ場所と一致する（上下の向き）
    Background(G);
    G.DrawColor := TPMLColor.Make(255, 0, 0, 255);
    G.FillRect(FR(10, 5, 8, 4));
    G.DrawColor := TPMLColor.Make(0, 0, 255, 255);
    G.FillRect(FR(0, 0, 1, 1));
    Full := G.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    Part := G.ReadPixels(TPMLRect.Make(8, 3, 12, 8));
    try
      Check(Full.ReadPixel(0, 0).Equals(TPMLColor.Make(0, 0, 255, 255)),
        '左上の画素は左上に描いたもの（上下が逆になっていない）');
      Ok := (Part.Width = 12) and (Part.Height = 8);
      if Ok then
        for Y := 0 to 7 do
          for X := 0 to 11 do
            if not Part.ReadPixel(X, Y).Equals(Full.ReadPixel(8 + X, 3 + Y)) then
              Ok := False;
      Check(Ok, '部分の読み戻しが全体の同じ場所と一致する');
    finally
      Part.Free;
      Full.Free;
    end;

    // 描画先のテクスチャの読み戻し（#41）。BGRA の並びの描画先でも色が入れ替わらない。
    // 描画先は出力（W x H）より大きくして、読む範囲が描画先の大きさで決まることも見る。
    Check(G.Driver.SupportsRenderTargets, '描画先のテクスチャを持てる');
    T := G.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Target, W + 16, H + 6);
    G.RenderTarget := T;
    G.DrawColor := TPMLColor.Make(200, 60, 20, 255);
    G.Clear;
    G.DrawColor := TPMLColor.Make(10, 20, 250, 255);
    G.FillRect(FR(0, H + 5, 1, 1));
    Part := G.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    try
      Check((Part.Width = W + 16) and (Part.Height = H + 6)
        and Part.ReadPixel(W + 15, 0).Equals(TPMLColor.Make(200, 60, 20, 255))
        and Part.ReadPixel(W + 15, H + 5).Equals(TPMLColor.Make(200, 60, 20, 255))
        and Part.ReadPixel(0, H + 5).Equals(TPMLColor.Make(10, 20, 250, 255)),
        Format('描画先の読み戻しは描画先の大きさ（出力より大きい）で、色と上下がそのまま（%s %s）',
          [IntToHex(LongWord(Part.ReadPixel(W + 15, 0)), 8), IntToHex(LongWord(Part.ReadPixel(0, H + 5)), 8)]));
    finally
      Part.Free;
    end;
    G.RenderTarget := nil;
    Check(G.GetOutputSize(OW, OH) and (OW = W) and (OH = H), '描画先を戻すと出力の大きさに戻る');
  finally
    G.Free;
  end;

  Compare('Clear', @SceneClear, 0);
  Compare('矩形の塗り（整数・小数・はみ出し）', @SceneRects, 0);
  Compare('半透明の合成', @SceneBlend, 2);
  Compare('合成モード 4 種', @SceneBlendModes, 2);
  Compare('12 枚の三角形の扇（二重塗り・塗り残し）', @SceneFan, 1);
  Compare('頂点色の補間', @SceneGradient, 2);
  Compare('テクスチャの転送（等倍・2 倍・一部）', @SceneCopy, 0);
  Compare('テクスチャの色とアルファの変調', @SceneTextureMod, 2);
  Compare('テクスチャの形式（ARGB / ABGR / XRGB / RGB24）', @SceneFormats, 0);
  Compare('テクスチャの一部更新', @SceneTextureUpdate, 0);
  Compare('ビューポートとクリップ', @SceneViewportClip, 0);
  Compare('点', @ScenePoints, 0);
  Compare('水平・垂直の線と枠', @SceneAxisLines, 0);
  Compare('斜めの線（GL の線の規則はブレゼンハムと違う）', @SceneDiagonalLines, 0, 12);
  Compare('論理解像度（塗り・点・軸の線・転送・ビューポート）', @SceneLogical, 0);
  Compare('論理解像度の線（三角形。斜め・閉じた半透明）', @SceneLogicalLines, 2);
  Compare('倍率だけの線（矩形の並びとブレゼンハム）', @SceneScaleLines, 0);
  Compare('DebugText（等倍・2 倍・色の切り替え）', @SceneDebugText, 2);
  Compare('回す（90 度・反転・30 度）と平行四辺形', @SceneRotated, 0, 40);
  Compare('敷き詰めと 9 つ分け（9GridTiled を含む）', @SceneTiled9Grid, 0);
  Compare('描画先のテクスチャ（4 形式・合成・クリップ・描画先どうし）', @SceneRenderTargets, 2);
end;

{ ---- ウィンドウ ---- }

procedure WindowSection;
var
  SizeOk: Boolean;
  Ctx: TPMLContext;
  VB: TPMLWaylandVideoBackend;
  Win, Plain: TPMLWindow;
  R, Soft: TPMLRenderer;
  Raised: Boolean;
  S: TPMLSurface;
  T0, T: UInt64;
  N, OW, OH: Integer;
  Refresh, Fps1, Fps0: Double;
  Ev: TPMLEvent;
  Tgt: TPMLTexture;

  procedure Pump(AMs: Integer);
  var
    Start: UInt64;
  begin
    Start := Ctx.Timer.TicksNS;
    repeat
      Ctx.Events.Pump(10);
      while Ctx.Events.Poll(Ev) do ;
    until Ctx.Timer.TicksNS - Start >= UInt64(AMs) * 1000000;
  end;

  function Fps(AMs: Integer): Double;
  begin
    N := 0;
    T0 := Ctx.Timer.TicksNS;
    repeat
      R.DrawColor := TPMLColor.Make(N mod 256, 60, 90, 255);
      R.Clear;
      R.Present;
      Inc(N);
      Ctx.Events.Pump(0);
      while Ctx.Events.Poll(Ev) do ;
      T := Ctx.Timer.TicksNS;
    until T - T0 >= UInt64(AMs) * 1000000;
    Result := N / ((T - T0) / 1e9);
  end;

begin
  WriteLn;
  WriteLn('2. ウィンドウ');
  if GetEnvironmentVariable('WAYLAND_DISPLAY') = '' then
  begin
    WriteLn('  [SKIP] Wayland セッションが無い');
    Exit;
  end;
  Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
  try
    if not (Ctx.Video.Backend is TPMLWaylandVideoBackend) then
    begin
      WriteLn('  [SKIP] Wayland でない');
      Exit;
    end;
    VB := TPMLWaylandVideoBackend(Ctx.Video.Backend);
    Refresh := Ctx.Video.PrimaryDisplay.DesktopMode.RefreshRate;

    Plain := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('plain', 120, 80));
    Soft := TPMLRenderer.CreateForWindow(Plain);
    Check(Soft.DriverName = 'software', 'GL でないウィンドウの既定はソフトウェア');
    Raised := False;
    try
      TPMLRenderer.CreateForWindow(Plain, 'gles2');
    except
      on E: EPMLUnsupported do
        Raised := True;
    end;
    Check(Raised, 'GL でないウィンドウに gles2 を頼むと EPMLUnsupported');
    Plain.Free;

    Win := Ctx.Video.CreateWindow(
      TPMLWindowOptions.Make('papimela gles2', 320, 200).Resizable.OpenGL);
    R := TPMLRenderer.CreateForWindow(Win);
    Check(R.DriverName = 'gles2', 'GL のウィンドウの既定は gles2');
    Pump(300);
    Check(R.GetOutputSize(OW, OH) and (OW = 320) and (OH = 200), '出力の大きさはウィンドウと同じ');

    Background(R);
    R.DrawColor := TPMLColor.Make(255, 0, 0, 255);
    R.FillRect(FR(0, 0, 2, 2));
    R.DrawColor := TPMLColor.Make(0, 255, 0, 255);
    R.FillRect(FR(318, 198, 2, 2));
    S := R.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    try
      Check(S.ReadPixel(0, 0).Equals(TPMLColor.Make(255, 0, 0, 255)),
        'ウィンドウの左上に描いたものが左上に読める');
      Check(S.ReadPixel(319, 199).Equals(TPMLColor.Make(0, 255, 0, 255)),
        '右下に描いたものが右下に読める');
    finally
      S.Free;
    end;

    // ウィンドウのレンダラでも、描画先のテクスチャ（FBO）は上下を反転させない。
    // 上の行に赤、下の行に緑を描いた描画先を、ウィンドウの左上へ写して読む。
    Tgt := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Target, 4, 6);
    R.RenderTarget := Tgt;
    R.DrawColor := TPMLColor.Make(0, 0, 255, 255);
    R.Clear;
    R.DrawColor := TPMLColor.Make(255, 0, 0, 255);
    R.FillRect(FR(0, 0, 4, 1));
    R.DrawColor := TPMLColor.Make(0, 255, 0, 255);
    R.FillRect(FR(0, 5, 4, 1));
    S := R.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    try
      Check((S.Width = 4) and S.ReadPixel(0, 0).Equals(TPMLColor.Make(255, 0, 0, 255))
        and S.ReadPixel(3, 5).Equals(TPMLColor.Make(0, 255, 0, 255)),
        'ウィンドウのレンダラの描画先は、上に描いたものが上に読める');
    finally
      S.Free;
    end;
    R.RenderTarget := nil;
    Background(R);
    R.RenderTexture(Tgt, FR(0, 0, 0, 0), FR(0, 0, 4, 6));
    S := R.ReadPixels(TPMLRect.Make(0, 0, 8, 8));
    try
      Check(S.ReadPixel(1, 0).Equals(TPMLColor.Make(255, 0, 0, 255))
        and S.ReadPixel(1, 5).Equals(TPMLColor.Make(0, 255, 0, 255))
        and S.ReadPixel(1, 2).Equals(TPMLColor.Make(0, 0, 255, 255)),
        '描画先をウィンドウへ写しても上下がそのまま');
    finally
      S.Free;
    end;
    Tgt.Free;
    R.Present;

    R.VSync := 1;
    Fps1 := Fps(1500);
    R.VSync := 0;
    Fps0 := Fps(1500);
    WriteLn(Format('  [INFO] 画面 %.1f Hz、VSync 1: %.1f fps、0: %.1f fps', [Refresh, Fps1, Fps0]));
    Check((Fps1 > Refresh * 0.8) and (Fps1 < Refresh * 1.1), 'VSync 1 は画面のリフレッシュに揃う');
    Check(Fps0 > Refresh * 1.5, 'VSync 0 はそれより速い');
    R.VSync := 1;

    Win.Maximize;
    Pump(500);
    R.Present;
    // Format は Check より先に評価されるので、大きさは先に取っておく。
    SizeOk := R.GetOutputSize(OW, OH);
    Check(SizeOk and (OW > 320) and (OH > 200),
      Format('最大化すると出力が大きくなる（%dx%d）', [OW, OH]));
    Background(R);
    R.DrawColor := TPMLColor.Make(0, 0, 255, 255);
    R.FillRect(FR(OW - 3, OH - 3, 3, 3));
    S := R.ReadPixels(TPMLRect.Make(OW - 1, OH - 1, 1, 1));
    try
      Check(S.ReadPixel(0, 0).Equals(TPMLColor.Make(0, 0, 255, 255)), '新しい右下の隅まで描ける');
    finally
      S.Free;
    end;
    R.Present;

    Win.Free;   // レンダラも GL のコンテキストも一緒に消える
    Pump(100);
    Check(wl_display_get_error(VB.Connection.Display) = 0, 'プロトコル違反が無い');
  finally
    Ctx.Free;
  end;
end;

begin
  WriteLn('test_render_gles2 — GPU のドライバをソフトウェアのドライバと比べる');
  WriteLn;
  MakeSources;
  try
    OffscreenSection;
    WindowSection;
  finally
    Checker.Free;
    Gradient.Free;
  end;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: GPU のドライバがソフトウェアのドライバと同じ絵を描く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
