{ test/render_scenes.inc — レンダラのドライバの比べる場面（test_render_gles2 と test_render_gl が共有）。
  ソフトウェアのドライバ（T-16 で矩形と三角形が完全一致するところまで確かめてある）を正解として、GPU のドライバが
  同じ絵を描くかを、場面ごとに許す差で測る。使う側が NewGPU（オフスクリーンのドライバ）と AdjustTolerance を定義する。 }

function NewGPU: TPMLRenderer; forward;

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

{ ---- パレット（§3 の 3b） ----

  INDEX8 のテクスチャ。GLES2 のドライバは添字を 1 成分のテクスチャ、パレットを 256x1 の
  テクスチャにしてシェーダで引く（SDL_shaders_gles2.c の PALETTE_SHADER_FUNCTIONS）。
  場面は幅 7（4 の倍数でない行）で、パレットの外の添字（白で描く）、拡大、合成、変調、回転、
  積んだ後の色の変更、部分更新、BGRA32 の描画先（R と B を入れ替えるシェーダ）を含む。 }

function NewTestPalette: TPMLPalette;
begin
  Result := TPMLPalette.Create(nil, nil, 5);
  Result[0] := TPMLColor.Make(255, 0, 0, 255);
  Result[1] := TPMLColor.Make(0, 255, 0, 255);
  Result[2] := TPMLColor.Make(0, 0, 255, 128);
  Result[3] := TPMLColor.Make(255, 255, 0, 0);
  Result[4] := TPMLColor.Make(30, 160, 90, 255);
end;

function NewPaletteTexture(R: TPMLRenderer; AW, AH: Integer): TPMLTexture;
var
  Idx: array of Byte;
  I: Integer;
begin
  SetLength(Idx, AW * AH);
  for I := 0 to High(Idx) do
    if I mod 7 = 6 then
      Idx[I] := 200        // パレットの外
    else
      Idx[I] := (I * 3 + I div AW) mod 5;
  Result := R.CreateTexture(PML_PIXELFORMAT_INDEX8, TPMLTextureAccess.Static, AW, AH);
  Result.Update(TPMLRect.Make(0, 0, 0, 0), @Idx[0], AW);
  Result.SetPalette(NewTestPalette, True);
end;

procedure ScenePalette(R: TPMLRenderer);
var
  T, Tgt: TPMLTexture;
  Part: array[0..2] of Byte;
begin
  Background(R);
  T := NewPaletteTexture(R, 7, 5);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(1, 1, 7, 5));
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(10, 1, 14, 10));
  T.BlendMode := TPMLBlendMode.Blend;
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(26, 1, 21, 15));
  T.ColorMod := TPMLColor.Make(200, 128, 255);
  T.AlphaMod := 180;
  R.RenderTexture(T, FR(1, 1, 5, 3), FR(48, 1, 15, 9));
  T.ColorMod := TPMLColor.White;
  T.AlphaMod := 255;
  R.RenderTextureRotated(T, FR(0, 0, 0, 0), FR(2, 20, 14, 10), 90);
  // 積んだ後に色を変える。前に積んだ描画は前の色のまま
  T.Palette[4] := TPMLColor.Make(250, 100, 10, 255);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(20, 20, 14, 10));
  Part[0] := 4;
  Part[1] := 4;
  Part[2] := 4;
  T.Update(TPMLRect.Make(1, 2, 3, 1), @Part[0], 3);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(36, 20, 14, 10));
  // BGRA32 の描画先へ描いてから、それを出力へ
  Tgt := R.CreateTexture(PML_PIXELFORMAT_BGRA32, TPMLTextureAccess.Target, 16, 12);
  R.RenderTarget := Tgt;
  R.DrawColor := TPMLColor.Make(20, 40, 60, 255);
  R.Clear;
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(1, 1, 14, 10));
  R.RenderTarget := nil;
  R.RenderTexture(Tgt, FR(0, 0, 0, 0), FR(2, 40, 16, 12));
end;

{ ---- YUV（§3 の 3c） ----

  GLES2 のドライバは YV12 / IYUV / I444 / NV12 / NV21 を平面のテクスチャで持ち、シェーダで色に直す
  （SDL_shaders_gles2.c の YUV と NV12 のシェーダ）。YUY2 / UYVY / YVYU はレンダラの肩代わり。
  ソフトウェアのドライバは整数の表で直すので、GPU の浮動小数の行列とは 1 成分あたり数だけ違いうる。 }

var
  YuvLcg: LongWord;

function YuvByte: Byte;
begin
  YuvLcg := YuvLcg * 1103515245 + 12345;
  Result := Byte(YuvLcg shr 16);
end;

{ 偽の乱数の YUV（詰めた画素）を入れたテクスチャ。 }
function NewYUVTexture(R: TPMLRenderer; AFormat: TPMLPixelFormat; AColorspace: TPMLColorspace;
  AW, AH: Integer; ASeed: LongWord): TPMLTexture;
var
  Buf: TBytes;
  Size: PtrUInt;
  Pitch, I: Integer;
begin
  PMLCalculateYUVSize(AFormat, AW, AH, Size, Pitch);
  SetLength(Buf, Size);
  YuvLcg := ASeed;
  for I := 0 to High(Buf) do
    Buf[I] := YuvByte;
  Result := R.CreateTexture(AFormat, TPMLTextureAccess.Static, AW, AH, AColorspace);
  Result.Update(TPMLRect.Make(0, 0, 0, 0), @Buf[0], Pitch);
end;

procedure SceneYUV(R: TPMLRenderer);
const
  Fmts: array[0..6] of TPMLPixelFormat = (PML_PIXELFORMAT_IYUV, PML_PIXELFORMAT_YV12,
    PML_PIXELFORMAT_NV12, PML_PIXELFORMAT_NV21, PML_PIXELFORMAT_YUY2, PML_PIXELFORMAT_UYVY,
    PML_PIXELFORMAT_YVYU);
var
  Spaces: array[0..4] of TPMLColorspace;
  T: TPMLTexture;
  Tgt: TPMLTexture;
  I: Integer;
  Y, U, V: array[0..63] of Byte;
  UV: array[0..31] of Byte;
begin
  Background(R);
  Spaces[0] := PML_COLORSPACE_BT601_LIMITED;
  Spaces[1] := PML_COLORSPACE_JPEG;
  Spaces[2] := PML_COLORSPACE_BT709_LIMITED;
  Spaces[3] := PML_COLORSPACE_BT709_FULL;
  Spaces[4] := PML_COLORSPACE_BT2020_FULL;
  // 7 形式 x 1:1（8x6）
  for I := 0 to 6 do
  begin
    T := NewYUVTexture(R, Fmts[I], PML_COLORSPACE_BT709_LIMITED, 8, 6, 100 + I);
    R.RenderTexture(T, FR(0, 0, 0, 0), FR(1 + I * 9, 1, 8, 6));
  end;
  // 5 つの色空間（IYUV と NV12）
  for I := 0 to 4 do
  begin
    T := NewYUVTexture(R, PML_PIXELFORMAT_IYUV, Spaces[I], 6, 4, 200 + I);
    R.RenderTexture(T, FR(0, 0, 0, 0), FR(1 + I * 7, 9, 6, 4));
    T := NewYUVTexture(R, PML_PIXELFORMAT_NV12, Spaces[I], 6, 4, 300 + I);
    R.RenderTexture(T, FR(0, 0, 0, 0), FR(1 + I * 7, 14, 6, 4));
  end;
  // 奇数の大きさ（7x5）、2 倍、変調と Blend、回転
  T := NewYUVTexture(R, PML_PIXELFORMAT_YV12, PML_COLORSPACE_YUV_DEFAULT, 7, 5, 400);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(1, 20, 7, 5));
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(10, 20, 14, 10));
  T := NewYUVTexture(R, PML_PIXELFORMAT_NV21, PML_COLORSPACE_YUV_DEFAULT, 8, 6, 401);
  T.ColorMod := TPMLColor.Make(200, 255, 120);
  T.AlphaMod := 160;
  T.BlendMode := TPMLBlendMode.Blend;
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(26, 20, 16, 12));
  T := NewYUVTexture(R, PML_PIXELFORMAT_UYVY, PML_COLORSPACE_YUV_DEFAULT, 8, 6, 402);
  R.RenderTextureRotated(T, FR(0, 0, 0, 0), FR(44, 20, 16, 12), 90);
  // 平面ごとの更新（UpdateYUV と UpdateNV。部分も）
  YuvLcg := 500;
  for I := 0 to 63 do
  begin
    Y[I] := YuvByte;
    U[I] := YuvByte;
    V[I] := YuvByte;
  end;
  for I := 0 to 31 do
    UV[I] := YuvByte;
  T := NewYUVTexture(R, PML_PIXELFORMAT_IYUV, PML_COLORSPACE_YUV_DEFAULT, 8, 6, 501);
  T.UpdateYUV(TPMLRect.Make(2, 2, 4, 2), @Y[0], 4, @U[0], 2, @V[0], 2);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(1, 34, 8, 6));
  T := NewYUVTexture(R, PML_PIXELFORMAT_YV12, PML_COLORSPACE_YUV_DEFAULT, 8, 6, 502);
  T.UpdateYUV(TPMLRect.Make(0, 0, 0, 0), @Y[0], 8, @U[0], 4, @V[0], 4);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(10, 34, 8, 6));
  T := NewYUVTexture(R, PML_PIXELFORMAT_NV12, PML_COLORSPACE_YUV_DEFAULT, 8, 6, 503);
  T.UpdateNV(TPMLRect.Make(2, 2, 4, 2), @Y[0], 4, @UV[0], 4);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(19, 34, 8, 6));
  T := NewYUVTexture(R, PML_PIXELFORMAT_NV21, PML_COLORSPACE_YUV_DEFAULT, 8, 6, 504);
  T.UpdateNV(TPMLRect.Make(0, 0, 0, 0), @Y[0], 8, @UV[0], 8);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(28, 34, 8, 6));
  // 詰めた画素の部分の更新
  T := NewYUVTexture(R, PML_PIXELFORMAT_NV12, PML_COLORSPACE_YUV_DEFAULT, 8, 6, 505);
  T.Update(TPMLRect.Make(2, 2, 4, 2), @Y[0], 4);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(37, 34, 8, 6));
  T := NewYUVTexture(R, PML_PIXELFORMAT_IYUV, PML_COLORSPACE_YUV_DEFAULT, 8, 6, 506);
  T.Update(TPMLRect.Make(2, 2, 4, 2), @Y[0], 4);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(46, 34, 8, 6));
  // BGRA32 の描画先へ（R と B を入れ替えるシェーダ）
  Tgt := R.CreateTexture(PML_PIXELFORMAT_BGRA32, TPMLTextureAccess.Target, 20, 8);
  R.RenderTarget := Tgt;
  R.DrawColor := TPMLColor.Make(20, 40, 60, 255);
  R.Clear;
  R.RenderTexture(NewYUVTexture(R, PML_PIXELFORMAT_IYUV, PML_COLORSPACE_BT709_FULL, 8, 6, 600),
    FR(0, 0, 0, 0), FR(1, 1, 8, 6));
  R.RenderTexture(NewYUVTexture(R, PML_PIXELFORMAT_NV21, PML_COLORSPACE_JPEG, 8, 6, 601),
    FR(0, 0, 0, 0), FR(10, 1, 8, 6));
  R.RenderTarget := nil;
  R.RenderTexture(Tgt, FR(0, 0, 0, 0), FR(1, 44, 20, 8));
end;

{ I444（色差が輝度と同じ大きさ）。GPU は 3 平面のテクスチャで持ち、ソフトウェアのドライバは肩代わり。
  色差を 2x2 の区画に寄せる処理は I444 では効かせない（寄せると隣の画素の色差を引く）。 }
procedure SceneYUV444(R: TPMLRenderer);
var
  Spaces: array[0..4] of TPMLColorspace;
  T, Tgt: TPMLTexture;
  I: Integer;
  Y, U, V: array[0..63] of Byte;
begin
  Background(R);
  Spaces[0] := PML_COLORSPACE_BT601_LIMITED;
  Spaces[1] := PML_COLORSPACE_JPEG;
  Spaces[2] := PML_COLORSPACE_BT709_LIMITED;
  Spaces[3] := PML_COLORSPACE_BT709_FULL;
  Spaces[4] := PML_COLORSPACE_BT2020_FULL;
  // 5 つの色空間 x 1:1
  for I := 0 to 4 do
  begin
    T := NewYUVTexture(R, PML_PIXELFORMAT_I444, Spaces[I], 8, 6, 700 + I);
    R.RenderTexture(T, FR(0, 0, 0, 0), FR(1 + I * 9, 1, 8, 6));
  end;
  // 奇数の大きさ（7x5）の 1:1 と 2 倍（Nearest。ソフトウェアのドライバの Linear は Nearest のままなので、補間は比べない）
  T := NewYUVTexture(R, PML_PIXELFORMAT_I444, PML_COLORSPACE_BT709_LIMITED, 7, 5, 710);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(1, 9, 7, 5));
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(10, 9, 14, 10));
  // 変調と Blend、回転
  T := NewYUVTexture(R, PML_PIXELFORMAT_I444, PML_COLORSPACE_YUV_DEFAULT, 8, 6, 711);
  T.ColorMod := TPMLColor.Make(200, 255, 120);
  T.AlphaMod := 160;
  T.BlendMode := TPMLBlendMode.Blend;
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(42, 9, 16, 12));
  T := NewYUVTexture(R, PML_PIXELFORMAT_I444, PML_COLORSPACE_YUV_DEFAULT, 8, 6, 712);
  R.RenderTextureRotated(T, FR(0, 0, 0, 0), FR(1, 22, 16, 12), 90);
  // 平面ごとの更新（全体と部分）と、詰めた画素の部分の更新
  YuvLcg := 800;
  for I := 0 to 63 do
  begin
    Y[I] := YuvByte;
    U[I] := YuvByte;
    V[I] := YuvByte;
  end;
  T := NewYUVTexture(R, PML_PIXELFORMAT_I444, PML_COLORSPACE_YUV_DEFAULT, 8, 6, 713);
  T.UpdateYUV(TPMLRect.Make(0, 0, 0, 0), @Y[0], 8, @U[0], 8, @V[0], 8);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(20, 22, 8, 6));
  T := NewYUVTexture(R, PML_PIXELFORMAT_I444, PML_COLORSPACE_YUV_DEFAULT, 8, 6, 714);
  T.UpdateYUV(TPMLRect.Make(2, 1, 5, 3), @Y[0], 5, @U[0], 5, @V[0], 5);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(29, 22, 8, 6));
  T := NewYUVTexture(R, PML_PIXELFORMAT_I444, PML_COLORSPACE_YUV_DEFAULT, 8, 6, 715);
  T.Update(TPMLRect.Make(2, 1, 5, 3), @Y[0], 5);
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(38, 22, 8, 6));
  // BGRA32 の描画先へ（R と B を入れ替えるシェーダ）
  Tgt := R.CreateTexture(PML_PIXELFORMAT_BGRA32, TPMLTextureAccess.Target, 10, 8);
  R.RenderTarget := Tgt;
  R.DrawColor := TPMLColor.Make(20, 40, 60, 255);
  R.Clear;
  R.RenderTexture(NewYUVTexture(R, PML_PIXELFORMAT_I444, PML_COLORSPACE_BT709_FULL, 8, 6, 716),
    FR(0, 0, 0, 0), FR(1, 1, 8, 6));
  R.RenderTarget := nil;
  R.RenderTexture(Tgt, FR(0, 0, 0, 0), FR(1, 36, 10, 8));
end;

{ Lock / Unlock / LockToSurface（#41 の残り）。GPU のドライバは Lock の置き場（SDL の pixel_data）に書いた
  全体を Unlock で上げる。ソフトウェアのドライバはテクスチャの画素そのもの。最初に全体を書いてから使う
  （GPU の置き場は Update した絵を持たない）ので、どちらも同じ絵になる。 }
var
  LockLcg: LongWord;

procedure LockFill(P: PByte; APitch, ARowBytes, ARows: Integer; ASeed: LongWord; AYUV: Boolean);
var
  X, Y: Integer;
begin
  LockLcg := ASeed;
  for Y := 0 to ARows - 1 do
    for X := 0 to ARowBytes - 1 do
    begin
      LockLcg := LockLcg * 1103515245 + 12345;
      if AYUV then
        P[Y * APitch + X] := 96 + Byte((LockLcg shr 16) and 63)
      else
        P[Y * APitch + X] := Byte(LockLcg shr 16);
    end;
end;

procedure SceneLock(R: TPMLRenderer);
var
  T: TPMLTexture;
  P: PByte;
  Pitch: Integer;
  S: TPMLSurface;
  Pal: TPMLPalette;
  Y: Integer;
begin
  Background(R);
  // ARGB8888: 全体、続けて部分
  T := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Streaming, 8, 6);
  T.BlendMode := TPMLBlendMode.None;
  P := T.Lock(TPMLRect.Make(0, 0, 0, 0), Pitch);
  LockFill(P, Pitch, 8 * 4, 6, 7, False);
  T.Unlock;
  P := T.Lock(TPMLRect.Make(2, 1, 3, 3), Pitch);
  LockFill(P, Pitch, 3 * 4, 3, 99, False);
  T.Unlock;
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(2, 2, 24, 18));
  // INDEX8
  T := R.CreateTexture(PML_PIXELFORMAT_INDEX8, TPMLTextureAccess.Streaming, 8, 6);
  Pal := NewTestPalette;
  T.SetPalette(Pal, True);
  P := T.Lock(TPMLRect.Make(0, 0, 0, 0), Pitch);
  LockFill(P, Pitch, 8, 6, 5, False);
  T.Unlock;
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(32, 2, 24, 18));
  // 平面の YUV と NV
  T := R.CreateTexture(PML_PIXELFORMAT_IYUV, TPMLTextureAccess.Streaming, 8, 6);
  P := T.Lock(TPMLRect.Make(0, 0, 0, 0), Pitch);
  LockFill(P, 0, 8 * 6 + 2 * 3 * 4, 1, 21, True);
  T.Unlock;
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(2, 22, 24, 18));
  T := R.CreateTexture(PML_PIXELFORMAT_NV12, TPMLTextureAccess.Streaming, 8, 6);
  P := T.Lock(TPMLRect.Make(0, 0, 0, 0), Pitch);
  LockFill(P, 0, 8 * 6 + 2 * 3 * 4, 1, 22, True);
  T.Unlock;
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(32, 22, 24, 18));
  // パックされた YUV の部分の Lock
  T := R.CreateTexture(PML_PIXELFORMAT_YUY2, TPMLTextureAccess.Streaming, 8, 6);
  P := T.Lock(TPMLRect.Make(0, 0, 0, 0), Pitch);
  LockFill(P, Pitch, 8 * 2, 6, 31, True);
  T.Unlock;
  P := T.Lock(TPMLRect.Make(2, 1, 4, 3), Pitch);
  LockFill(P, Pitch, 4 * 2, 3, 32, True);
  T.Unlock;
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(2, 42, 24, 18));
  // LockToSurface: サーフェスに塗る
  T := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Streaming, 8, 6);
  T.BlendMode := TPMLBlendMode.None;
  P := T.Lock(TPMLRect.Make(0, 0, 0, 0), Pitch);
  LockFill(P, Pitch, 8 * 4, 6, 3, False);
  T.Unlock;
  S := T.LockToSurface(TPMLRect.Make(1, 1, 5, 3));
  for Y := 0 to S.Height - 1 do
    FillChar((PByte(S.Pixels) + Y * S.Pitch)^, S.Width * 4, $7F);
  T.Unlock;
  R.RenderTexture(T, FR(0, 0, 0, 0), FR(32, 42, 24, 18));
end;

{ ---- ドライバが INDEX8 と YUV を自分で持つこと（GLES2 と GL で共通） ---- }

{ GPU だけの確かめ。ドライバが INDEX8 を自分で持つこと（レンダラの肩代わりでないこと）と、
  Linear の補間（シェーダで 4 つの添字の色を混ぜる）が、同じ色の ARGB8888 のテクスチャを
  GL の補間で描いた絵とほぼ同じになること。ソフトウェアのドライバの Linear は Nearest
  （§3 の 4）なので、ここは GPU 同士で比べる。 }
procedure CheckPaletteNative;
var
  G: TPMLRenderer;
  T, A: TPMLTexture;
  S, Shot: TPMLSurface;
  X, Y, D, MaxD, Bad: Integer;
  C: TPMLColor;
  P: TPMLPalette;
begin
  G := NewGPU;
  S := nil;
  Shot := nil;
  try
    Check(G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_INDEX8),
      'INDEX8 のテクスチャを直接持てる（パレットはシェーダで引く）');
    T := NewPaletteTexture(G, 7, 5);
    Check(T.DriverPalette <> nil, 'パレットはドライバの写し（256x1 のテクスチャ）で持つ');
    // 比べる相手: 同じ添字をパレットで色に直した ARGB8888
    P := T.Palette;
    S := TPMLSurface.Create(7, 5, PML_PIXELFORMAT_ARGB8888);
    for Y := 0 to 4 do
      for X := 0 to 6 do
      begin
        if (Y * 7 + X) mod 7 = 6 then
          C := TPMLColor.White
        else
          C := P[((Y * 7 + X) * 3 + Y) mod 5];
        S.WritePixel(X, Y, C);
      end;
    A := G.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Static, 7, 5);
    A.Update(TPMLRect.Make(0, 0, 0, 0), S.Pixels, S.Pitch);
    T.ScaleMode := TPMLScaleMode.Linear;
    A.ScaleMode := TPMLScaleMode.Linear;
    T.BlendMode := TPMLBlendMode.None;
    A.BlendMode := TPMLBlendMode.None;
    G.DrawColor := TPMLColor.Make(0, 0, 0, 255);
    G.Clear;
    G.RenderTexture(T, FR(0, 0, 0, 0), FR(0, 0, 31, 23));
    G.RenderTexture(A, FR(0, 0, 0, 0), FR(32, 0, 31, 23));
    G.RenderTexture(T, FR(0, 0, 0, 0), FR(0, 30, 13, 9));
    G.RenderTexture(A, FR(0, 0, 0, 0), FR(32, 30, 13, 9));
    Shot := G.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    MaxD := 0;
    Bad := 0;
    for Y := 0 to 40 do
      for X := 0 to 31 do
      begin
        D := ChannelDiff(Shot.ReadPixel(X, Y), Shot.ReadPixel(X + 32, Y));
        if D > MaxD then
          MaxD := D;
        if D > 3 then
          Inc(Bad);
      end;
    Check(Bad = 0, Format('Linear のパレットは ARGB8888 の Linear とほぼ同じ絵（最大差 %d、差 3 を超えた画素 %d）',
      [MaxD, Bad]));
  finally
    Shot.Free;
    S.Free;
    G.Free;
  end;
end;

{ GPU だけの確かめ。平面の 5 形式（YV12 / IYUV / I444 / NV12 / NV21）はドライバが自分で持つ（肩代わりでない）。 }
procedure CheckYUVNative;
var
  G: TPMLRenderer;
begin
  G := NewGPU;
  try
    Check(G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_IYUV)
      and G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_YV12)
      and G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_NV12)
      and G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_NV21)
      and G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_I444),
      'YV12 / IYUV / I444 / NV12 / NV21 のテクスチャを直接持てる（SDL の GLES2 と同じ）');
    Check(not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_P010),
      'P010 は持たない（SDL の GLES2 も持たない）');
    Check(not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_YUY2),
      'YUY2 は持たない（レンダラの肩代わりで描く。SDL の GLES2 と同じ）');
  finally
    G.Free;
  end;
end;

{ ---- ドライバが変わっても同じ確かめ ---- }

// 場面ごとの許容の調整。ドライバごとのテストが、名前で許容を変える（既定のままなら何もしない）。
procedure AdjustTolerance(const AName: String; var ATolerance, AMaxBad: Integer); forward;

procedure CompareA(const AName: String; AScene: TScene; ATolerance: Integer; AMaxBad: Integer = 0);
begin
  AdjustTolerance(AName, ATolerance, AMaxBad);
  Compare(AName, AScene, ATolerance, AMaxBad);
end;

{ ドライバ G の、ソフトウェアのドライバと比べなくても分かる性質（出力の大きさ・合成モード・読み戻しの向き・描画先）。
  AName はドライバの名前。 }
procedure OffscreenChecks(G: TPMLRenderer; const AName: String);
var
  Full, Part: TPMLSurface;
  T: TPMLTexture;
  Ok: Boolean;
  X, Y, OW, OH: Integer;
  M: TPMLBlendMode;
begin
  Check(G.DriverName = AName, 'ドライバの名前は ' + AName);
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
end;

{ INDEX8 と YUV を自分で持つことの確かめ。GLES2 と GL で共通。 }
procedure RunNativeChecks;
begin
  CheckPaletteNative;
  CheckYUVNative;
end;

{ ソフトウェアのドライバと比べる場面。GLES2 と GL で共通。 }
procedure RunCommonScenes;
begin
  CompareA('Clear', @SceneClear, 0);
  CompareA('矩形の塗り（整数・小数・はみ出し）', @SceneRects, 0);
  CompareA('半透明の合成', @SceneBlend, 2);
  CompareA('合成モード 4 種', @SceneBlendModes, 2);
  CompareA('12 枚の三角形の扇（二重塗り・塗り残し）', @SceneFan, 1);
  CompareA('頂点色の補間', @SceneGradient, 2);
  CompareA('テクスチャの転送（等倍・2 倍・一部）', @SceneCopy, 0);
  CompareA('テクスチャの色とアルファの変調', @SceneTextureMod, 2);
  CompareA('テクスチャの形式（ARGB / ABGR / XRGB / RGB24）', @SceneFormats, 0);
  CompareA('テクスチャの一部更新', @SceneTextureUpdate, 0);
  CompareA('ビューポートとクリップ', @SceneViewportClip, 0);
  CompareA('点', @ScenePoints, 0);
  CompareA('水平・垂直の線と枠', @SceneAxisLines, 0);
  CompareA('斜めの線（GL の線の規則はブレゼンハムと違う）', @SceneDiagonalLines, 0, 12);
  CompareA('論理解像度（塗り・点・軸の線・転送・ビューポート）', @SceneLogical, 0);
  CompareA('論理解像度の線（三角形。斜め・閉じた半透明）', @SceneLogicalLines, 2);
  CompareA('倍率だけの線（矩形の並びとブレゼンハム）', @SceneScaleLines, 0);
  CompareA('DebugText（等倍・2 倍・色の切り替え）', @SceneDebugText, 2);
  CompareA('回す（90 度・反転・30 度）と平行四辺形', @SceneRotated, 0, 40);
  CompareA('敷き詰めと 9 つ分け（9GridTiled を含む）', @SceneTiled9Grid, 0);
  CompareA('描画先のテクスチャ（4 形式・合成・クリップ・描画先どうし）', @SceneRenderTargets, 2);
  CompareA('パレット（INDEX8。拡大・合成・変調・回転・色の変更・部分更新・BGRA32 の描画先）', @ScenePalette, 2);
  CompareA('YUV（7 形式・5 つの色空間・奇数・拡大・変調・回転・平面ごとと部分の更新）', @SceneYUV, 3);
  CompareA('YUV の I444（5 つの色空間・奇数・拡大・変調・回転・平面ごとと部分の更新・BGRA の描画先）', @SceneYUV444, 3);
  CompareA('Lock / Unlock / LockToSurface（ARGB・INDEX8・IYUV・NV12・YUY2・サーフェス。全体と部分）', @SceneLock, 2);
end;
