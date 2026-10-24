{
  test_render_gl — デスクトップ GL（互換プロファイル 2.1）のドライバをソフトウェアのドライバと比べる

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    オフスクリーン（窓の無い GL。EGL_OPENGL_API の surfaceless）で、同じ場面を GL のドライバとソフトウェアの
    ドライバの両方で描き、画素ごとに比べる（場面と比べ方は test/render_scenes.inc。GLES2 の test_render_gles2 と共有）。
    加えて、GL のドライバだけの確かめ（SDL の render/opengl の振る舞い）:
      - INDEX8 と YUV（YV12 / IYUV / I444 / NV12 / NV21）を直接持てる（共有の確かめ）
      - BGRA32 / RGBA32 / RGBX32 / BGRX32 のテクスチャを直接持てる（SDL の GL は BGRA 拡張とシェーダで足す）
      - P010 / YUY2 / UYVY / YVYU / I0FL / I4FL は持たない（SDL の GL が足すのは macOS の UYVY だけ）
      - 描画先のテクスチャ（FBO のリスト）、読み戻しの向き

  WHY:
    #44 の受け入れ検査。実装より先に書いた（空の実装の骨組みで落ちることを確かめてから実装に渡す）。
    許す差の考え方は GLES2 と同じ（共有の場面の許容）。GL の線と点は GL の規則（GL_LINES と GL_POINTS。
    GLES2 は三角形に直している）で描かれるので、線と点の場面の許容は実測してから AdjustTolerance に書く。

  実行前提: EGL と Mesa の surfaceless と libGL がある（使えなければ失敗。GL の無い環境で飛ばすには
            PAPIMELA_GL_OPTIONAL=1）。
}
program test_render_gl;

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
  PaPiMeLa.Surface.YUV,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Render,
  PaPiMeLa.Render.GL,
  PaPiMeLa.Render.GLES2,
  PaPiMeLa.Platform.GL,
  PaPiMeLa.Core;

{$I render_scenes.inc}

function NewGPU: TPMLRenderer;
begin
  Result := TPMLRenderer.Create(TPMLGLRenderDriver.CreateOffscreen(W, H));
end;

// GL の線と点は GL の規則で描かれる。許容は実測してここに書く（理由を添える）
procedure AdjustTolerance(const AName: String; var ATolerance, AMaxBad: Integer);
begin
end;

{ ---- GL だけの確かめ ---- }

procedure CheckGLFormats;
var
  G: TPMLRenderer;
begin
  G := NewGPU;
  try
    Check(G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_ARGB8888)
      and G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_ABGR8888),
      'ARGB8888（BGRA32）/ ABGR8888（RGBA32）のテクスチャを直接持てる（BGRA の拡張がある）');
    Check(G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_XRGB8888)
      and G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_XBGR8888),
      'XRGB8888（BGRX32）/ XBGR8888（RGBX32）のテクスチャを直接持てる（RGB のシェーダがある）');
    Check(not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_UYVY)
      and not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_YVYU)
      and not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_I0FL)
      and not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_I4FL),
      'UYVY / YVYU / I0FL / I4FL は持たない（SDL の GL が足すのは macOS の UYVY だけ）');
  finally
    G.Free;
  end;
end;

function ShotScaled(AMode: TPMLScaleMode; ADW, ADH: Integer): TPMLSurface;
var
  G: TPMLRenderer;
  T: TPMLTexture;
begin
  G := NewGPU;
  try
    Background(G);
    T := G.CreateTextureFromSurface(Checker);
    T.ScaleMode := AMode;
    G.RenderTexture(T, FR(0, 0, 0, 0), FR(3, 3, ADW, ADH));
    Result := G.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
  finally
    G.Free;
  end;
end;

function DiffCount(A, B: TPMLSurface): Integer;
var
  X, Y: Integer;
begin
  Result := 0;
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
      if A.ReadRaw(X, Y) <> B.ReadRaw(X, Y) then
        Inc(Result);
end;

{ ピクセルアートの拡大。SDL の GL は PIXELART のシェーダ（線形で標本し、画素の境目だけをぼかす）を持つ。
  整数倍では Nearest と同じ絵、整数倍でなければ Nearest とも Linear とも違う絵になる。 }
procedure CheckPixelArt;
var
  G: TPMLRenderer;
  N, P, L, N2, P2: TPMLSurface;
begin
  G := NewGPU;
  try
    Check(TPMLGLRenderDriver(G.Driver).PixelArtSupported, 'ピクセルアートのシェーダが使える');
  finally
    G.Free;
  end;
  N := ShotScaled(TPMLScaleMode.Nearest, 37, 41);
  P := ShotScaled(TPMLScaleMode.PixelArt, 37, 41);
  L := ShotScaled(TPMLScaleMode.Linear, 37, 41);
  N2 := ShotScaled(TPMLScaleMode.Nearest, 32, 32);
  P2 := ShotScaled(TPMLScaleMode.PixelArt, 32, 32);
  try
    Check(DiffCount(P2, N2) = 0, 'PixelArt は整数倍（2 倍）では Nearest と同じ絵');
    Check(DiffCount(P, N) > 0, 'PixelArt は整数倍でなければ Nearest と違う絵（シェーダが効いている）');
    Check(DiffCount(P, L) > 0, 'PixelArt は Linear とも違う絵');
    Check(DiffCount(L, N) > 0, '（確かめ）Linear は Nearest と違う絵');
  finally
    N.Free;
    P.Free;
    L.Free;
    N2.Free;
    P2.Free;
  end;
end;

{ 幅か高さが奇数の YUV（NPOT）で、輝度の面を偶数に切り上げて持つ余白に、端の画素を複製してあること。
  全面が同じ色の IYUV（7x5）を Linear で拡大して描き、端の画素まで同じ色になる。余白が 0 のままだと、右端と下端が
  暗くなる（補間が余白を読む）。 }
procedure CheckYUVPadEdge;
var
  G: TPMLRenderer;
  T: TPMLTexture;
  S: TPMLSurface;
  Y: array[0..34] of Byte;
  U: array[0..11] of Byte;
  V: array[0..11] of Byte;
  I, X, Yp, Bad: Integer;
  Center, C: TPMLColor;
begin
  G := NewGPU;
  try
    Background(G);
    T := G.CreateTexture(PML_PIXELFORMAT_IYUV, TPMLTextureAccess.Static, 7, 5);
    FillChar(Y, SizeOf(Y), 200);
    FillChar(U, SizeOf(U), 128);
    FillChar(V, SizeOf(V), 128);
    T.UpdateYUV(TPMLRect.Make(0, 0, 0, 0), @Y[0], 7, @U[0], 4, @V[0], 4);
    T.ScaleMode := TPMLScaleMode.Linear;
    G.RenderTexture(T, FR(0, 0, 0, 0), FR(2, 2, 28, 20));
    S := G.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    try
      Center := S.ReadPixel(16, 12);
      Bad := 0;
      for Yp := 2 to 21 do
        for X := 2 to 29 do
        begin
          C := S.ReadPixel(X, Yp);
          if ChannelDiff(C, Center) > 2 then
            Inc(Bad);
        end;
      I := Bad;
      Check(I = 0, Format('全面が同じ色の奇数の大きさの YUV は、Linear で拡大しても端まで同じ色（ずれた画素 %d）', [I]));
    finally
      S.Free;
    end;
  finally
    G.Free;
  end;
end;

{ 行の長さの設定（GL_UNPACK_ROW_LENGTH / GL_PACK_ROW_LENGTH）を、使ったあとに 0 へ戻していること。SDL は戻さない。 }
procedure CheckRowLength;
var
  G: TPMLRenderer;
  T: TPMLTexture;
  S: TPMLSurface;
  D: TPMLGLRenderDriver;
begin
  G := NewGPU;
  try
    D := TPMLGLRenderDriver(G.Driver);
    T := G.CreateTextureFromSurface(Checker);
    T.Update(TPMLRect.Make(2, 2, 5, 5), Checker.Pixels, Checker.Pitch);
    G.RenderTexture(T, FR(0, 0, 0, 0), FR(0, 0, 16, 16));
    S := G.ReadPixels(TPMLRect.Make(1, 1, 20, 20));
    S.Free;
    Check(D.QueryInteger(GL_UNPACK_ROW_LENGTH) = 0, 'テクスチャの更新のあと GL_UNPACK_ROW_LENGTH は 0 に戻っている');
    Check(D.QueryInteger(GL_PACK_ROW_LENGTH) = 0, '読み戻しのあと GL_PACK_ROW_LENGTH は 0 のまま');
  finally
    G.Free;
  end;
end;

{ SDL の GL が持つ 3 つのテクスチャの種類（NPOT・矩形・2 の冪乗）と、シェーダが無い GL の道を、強制して通す。 }
procedure RunMode(const ALabel: String; AMode: TPMLGLTextureMode; ANoShaders: Boolean);
var
  G: TPMLRenderer;
begin
  WriteLn('  --- ', ALabel);
  Flush(Output);
  PMLGLRenderTextureMode := AMode;
  PMLGLRenderDisableShaders := ANoShaders;
  try
    G := NewGPU;
    try
      Check(TPMLGLRenderDriver(G.Driver).TextureMode = AMode, 'ドライバのテクスチャの種類は強制のとおり');
      Check(TPMLGLRenderDriver(G.Driver).ShadersEnabled = not ANoShaders, 'シェーダの有無は強制のとおり');
      if ANoShaders then
      begin
        // SDL: シェーダが無ければ RGBA32 / BGRA32 だけ
        Check(G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_ABGR8888)
          and G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_ARGB8888)
          and not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_XRGB8888)
          and not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_XBGR8888)
          and not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_INDEX8)
          and not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_IYUV)
          and not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_NV12),
          'シェーダが無ければ RGBA32 / BGRA32 だけを持つ（SDL と同じ）');
      end;
    finally
      G.Free;
    end;
    RunCommonScenes;
  finally
    PMLGLRenderTextureMode := TPMLGLTextureMode.Auto;
    PMLGLRenderDisableShaders := False;
  end;
end;

procedure OffscreenSection;
var
  G: TPMLRenderer;
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
        Check(False, '窓の無い GL で GL のドライバを作れる（' + E.Message + '）');
      Exit;
    end;
  end;
  try
    OffscreenChecks(G, 'opengl');
  finally
    G.Free;
  end;
  CheckGLFormats;
  RunCommonScenes;
  RunNativeChecks;
  CheckPixelArt;
  CheckRowLength;
  CheckYUVPadEdge;
  RunMode('1a. 矩形テクスチャ（GL_TEXTURE_RECTANGLE。NPOT が無い GL の道）', TPMLGLTextureMode.Rectangle, False);
  RunMode('1b. 2 の冪乗への切り上げ（矩形も NPOT も無い GL の道）', TPMLGLTextureMode.PowerOfTwo, False);
  RunMode('1c. シェーダが無い GL（固定機能だけ）', TPMLGLTextureMode.Auto, True);
end;

{ ---- ウィンドウ（実機のコンポジタがあるときだけ。手元専用） ---- }

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
  FallbackWin: TPMLWindow;
  Fb: TPMLRenderer;

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
      TPMLRenderer.CreateForWindow(Plain, 'opengl');
    except
      on E: EPMLUnsupported do
        Raised := True;
    end;
    Check(Raised, 'GL でないウィンドウに opengl を頼むと EPMLUnsupported');
    Plain.Free;

    Win := Ctx.Video.CreateWindow(
      TPMLWindowOptions.Make('papimela opengl', 320, 200).Resizable.OpenGL);
    R := TPMLRenderer.CreateForWindow(Win);
    Check(R.DriverName = 'opengl', 'GL のウィンドウの既定は opengl（GLES2 より先）');
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

    // ウィンドウ（原点が左下の既定のフレームバッファ）でのビューポートとクリップ。向きを逆に持つと、描く位置が上下に
    // 反転する。ビューポート (8, 8, 40, 40) の左上の隅に赤、クリップ (20, 20, 10, 10) の中に緑を描く。
    Background(R);
    R.Viewport := TPMLRect.Make(8, 8, 40, 40);
    R.DrawColor := TPMLColor.Make(255, 0, 0, 255);
    R.FillRect(FR(0, 0, 4, 4));
    R.ClipRect := TPMLRect.Make(20, 20, 10, 10);
    R.DrawColor := TPMLColor.Make(0, 255, 0, 255);
    R.FillRect(FR(0, 0, 40, 40));
    R.ClipRect := TPMLRect.Make(0, 0, 0, 0);
    R.Viewport := TPMLRect.Make(0, 0, 0, 0);
    S := R.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    try
      Check(S.ReadPixel(8, 8).Equals(TPMLColor.Make(255, 0, 0, 255))
        and S.ReadPixel(11, 11).Equals(TPMLColor.Make(255, 0, 0, 255))
        and not S.ReadPixel(7, 8).Equals(TPMLColor.Make(255, 0, 0, 255))
        and not S.ReadPixel(8, 12).Equals(TPMLColor.Make(255, 0, 0, 255)),
        'ウィンドウのビューポートの左上に描いたものが、画面のその位置に出る');
      Check(S.ReadPixel(28, 28).Equals(TPMLColor.Make(0, 255, 0, 255))
        and S.ReadPixel(37, 37).Equals(TPMLColor.Make(0, 255, 0, 255))
        and not S.ReadPixel(27, 28).Equals(TPMLColor.Make(0, 255, 0, 255))
        and not S.ReadPixel(38, 37).Equals(TPMLColor.Make(0, 255, 0, 255))
        and not S.ReadPixel(28, 27).Equals(TPMLColor.Make(0, 255, 0, 255))
        and not S.ReadPixel(37, 38).Equals(TPMLColor.Make(0, 255, 0, 255)),
        'ウィンドウのクリップ矩形の範囲だけが塗れる（ビューポートの原点からの相対）');
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
    Check(Fps1 < Fps0 * 0.5, 'VSync 1 は待つので、VSync 0 より遅い');
    Check(Fps1 < Refresh * 1.1, 'VSync 1 は画面のリフレッシュを超えない');
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

    // 自動選択のフォールバック: opengl が作れなければ gles2 へ進み、窓はそのまま使える
    FallbackWin := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('fallback', 160, 100).OpenGL);
    PMLGLRenderFailCreate := True;
    try
      Fb := TPMLRenderer.CreateForWindow(FallbackWin);
    finally
      PMLGLRenderFailCreate := False;
    end;
    Check(Fb.DriverName = 'gles2', 'opengl が作れなければ、自動選択は gles2 へ進む');
    Background(Fb);
    Fb.DrawColor := TPMLColor.Make(255, 0, 0, 255);
    Fb.FillRect(FR(0, 0, 2, 2));
    S := Fb.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    try
      Check(S.ReadPixel(0, 0).Equals(TPMLColor.Make(255, 0, 0, 255)), 'フォールバックした gles2 で描いて読める');
    finally
      S.Free;
    end;
    Fb.Present;
    Check(wl_display_get_error(VB.Connection.Display) = 0, 'フォールバックでプロトコル違反が無い');
    FallbackWin.Free;
    // 名前を指定したときは、作れなければ作れなかった例外のまま（SDL と同じ）
    FallbackWin := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('named', 160, 100).OpenGL);
    PMLGLRenderFailCreate := True;
    Raised := False;
    try
      try
        TPMLRenderer.CreateForWindow(FallbackWin, 'opengl');
      except
        on E: EPMLUnsupported do
          Raised := True;
      end;
    finally
      PMLGLRenderFailCreate := False;
    end;
    Check(Raised, '名前で opengl だけを頼み、作れなければ EPMLUnsupported');
    FallbackWin.Free;

    Win.Free;   // レンダラも GL のコンテキストも一緒に消える
    Pump(100);
    Check(wl_display_get_error(VB.Connection.Display) = 0, 'プロトコル違反が無い');
  finally
    Ctx.Free;
  end;
end;

begin
  WriteLn('test_render_gl — デスクトップ GL のドライバをソフトウェアのドライバと比べる');
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
    WriteLn('=== 結論: GL のドライバがソフトウェアのドライバと同じ絵を描く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
