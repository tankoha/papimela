{
  test_render_vulkan — Vulkan のドライバをソフトウェアのドライバと比べる

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    オフスクリーン（面の無い Vulkan。画像に描いて読み戻す）で、同じ場面を Vulkan のドライバとソフトウェアの
    ドライバの両方で描き、画素ごとに比べる（場面と比べ方は test/render_scenes.inc。GLES2 と GL の検査と共有）。
    加えて、Vulkan のドライバだけの確かめ（SDL の render/vulkan の振る舞い）:
      - 持てる形式は SDL の vk_format_map と INDEX8 と YUV（YV12 / IYUV / I444 / NV12 / NV21）。XRGB8888 / XBGR8888 /
        RGB24 / YUY2 / UYVY / YVYU は持たない（持たない形式は CreateTextureFromSurface が ARGB8888 へ変換する）
      - 16 ビットの形式（RGB565 ほか）は、持てるなら持ったままソフトウェアと同じ絵になる
      - ピクセルアートの拡大（整数倍は Nearest と同じ、整数倍でなければ Nearest とも Linear とも違う）
      - ドライバを作っては壊しても、続けて作れる
    ウィンドウ（Wayland があるときだけ。手元専用）: Vulkan のウィンドウの既定のドライバ、向き、ビューポートと
    クリップ、描画先、VSync、最大化（スワップチェーンの作り直し）、プロトコル違反なし。

  WHY:
    #67 の段 3（受け入れ検査）。実装より先に書いた（骨組みの空の実装で落ちることを確かめてから実装に渡す）。
    許す差の考え方は GLES2 / GL と同じ（共有の場面の許容）。Vulkan の点と線は三角形に直す（既定）ので、
    許容は実測してから AdjustTolerance に書く。

  実行前提: Vulkan のローダと ICD（Mesa の V3DV / lavapipe など）がある（無ければ失敗。飛ばすには
            PAPIMELA_VULKAN_OPTIONAL=1）。物理デバイスを選ぶには PAPIMELA_VULKAN_DEVICE=名前の一部（V3D / llvmpipe）。
}
program test_render_vulkan;

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
  PaPiMeLa.Render.Vulkan,
  PaPiMeLa.Core;

{$I render_scenes.inc}

function NewGPU: TPMLRenderer;
begin
  Result := TPMLRenderer.Create(TPMLVulkanRenderDriver.CreateOffscreen(W, H));
end;

// Vulkan の点と線は三角形に直す（既定）ので、GLES2 と同じ。許容は実測してここに書く（理由を添える）
procedure AdjustTolerance(const AName: String; var ATolerance, AMaxBad: Integer);
begin
end;

{ ---- Vulkan だけの確かめ ---- }

procedure CheckVulkanFormats;
var
  G: TPMLRenderer;
begin
  G := NewGPU;
  try
    Check(G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_ARGB8888)
      and G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_ABGR8888),
      'ARGB8888（BGRA32）/ ABGR8888（RGBA32）のテクスチャを直接持てる（SDL の vk_format_map の先頭の 2 つ）');
    Check(G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_INDEX8), 'INDEX8 を持てる（SDL は R8 の画像とパレットの画像）');
    Check(G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_IYUV)
      and G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_YV12)
      and G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_I444)
      and G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_NV12)
      and G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_NV21),
      'YV12 / IYUV / I444 / NV12 / NV21 を持てる（SDL の yuvFormats。YCbCr 変換のサンプラ）');
    Check(not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_XRGB8888)
      and not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_XBGR8888)
      and not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_RGB24),
      'XRGB8888 / XBGR8888 / RGB24 は持たない（SDL の vk_format_map に無い）');
    Check(not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_YUY2)
      and not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_UYVY)
      and not G.Driver.SupportsTextureFormat(PML_PIXELFORMAT_YVYU),
      'YUY2 / UYVY / YVYU は持たない（SDL の yuvFormats に無い。レンダラの肩代わりで描く）');
  finally
    G.Free;
  end;
end;

{ 16 ビットの形式。持てる形式は持ったまま、持てない形式は ARGB8888 へ変換されて、どちらもソフトウェアと同じ絵になる。 }
procedure SceneSmallFormats(R: TPMLRenderer);
const
  Fmts: array[0..8] of TPMLPixelFormat = (
    PML_PIXELFORMAT_RGB565, PML_PIXELFORMAT_BGR565, PML_PIXELFORMAT_RGBA5551, PML_PIXELFORMAT_BGRA5551,
    PML_PIXELFORMAT_ARGB1555, PML_PIXELFORMAT_RGBA4444, PML_PIXELFORMAT_BGRA4444, PML_PIXELFORMAT_ARGB4444,
    PML_PIXELFORMAT_ABGR4444);
var
  S: TPMLSurface;
  T: TPMLTexture;
  I, X, Y: Integer;
begin
  Background(R);
  for I := 0 to High(Fmts) do
  begin
    S := TPMLSurface.Create(8, 8, Fmts[I]);
    try
      for Y := 0 to 7 do
        for X := 0 to 7 do
          S.WritePixel(X, Y, TPMLColor.Make(X * 36, Y * 36, 60 + I * 20, 255));
      T := R.CreateTextureFromSurface(S);
      T.ScaleMode := TPMLScaleMode.Nearest;
      R.RenderTexture(T, FR(0, 0, 0, 0), FR(2 + (I mod 3) * 20, 2 + (I div 3) * 20, 16, 16));
    finally
      S.Free;
    end;
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

{ ピクセルアートの拡大。SDL の Vulkan は TEXTURETYPE_RGB_PIXELART のシェーダを持つ。 }
procedure CheckPixelArt;
var
  N, P, L, N2, P2: TPMLSurface;
begin
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

{ ドライバを作っては壊しても、続けて作れて、同じ絵を描く（Vulkan のオブジェクトの後始末の漏れ・順序の確かめ）。 }
procedure CheckRecreate;
var
  I: Integer;
  G: TPMLRenderer;
  S: TPMLSurface;
  Ok: Boolean;
begin
  Ok := True;
  for I := 1 to 4 do
  begin
    G := NewGPU;
    try
      Background(G);
      G.DrawColor := TPMLColor.Make(255, 0, 0, 255);
      G.FillRect(FR(1, 1, 3, 3));
      S := G.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
      try
        if not S.ReadPixel(2, 2).Equals(TPMLColor.Make(255, 0, 0, 255)) then
          Ok := False;
      finally
        S.Free;
      end;
    finally
      G.Free;
    end;
  end;
  Check(Ok, 'ドライバを 4 回作っては壊しても、そのたびに描いて読める');
end;

procedure OffscreenSection;
var
  G: TPMLRenderer;
  Filter: String;
begin
  WriteLn('1. オフスクリーン（ソフトウェアのドライバと比べる）');
  Flush(Output);
  Filter := GetEnvironmentVariable('PAPIMELA_VULKAN_DEVICE');
  if Filter <> '' then
    PMLVulkanRenderDeviceFilter := Filter;
  try
    G := NewGPU;
  except
    on E: EPMLUnsupported do
    begin
      // 飛ばしてよいのは、Vulkan の無い環境だと明示されたときだけ。既定では失敗にする
      // （空の実装が「飛ばした」ことで通ってしまわないように）。
      if GetEnvironmentVariable('PAPIMELA_VULKAN_OPTIONAL') = '1' then
        WriteLn('  [SKIP] 面の無い Vulkan が使えない: ', E.Message)
      else
        Check(False, '面の無い Vulkan で Vulkan のドライバを作れる（' + E.Message + '）');
      Exit;
    end;
  end;
  try
    WriteLn('  [INFO] 物理デバイス: ', TPMLVulkanRenderDriver(G.Driver).DeviceName);
    Check(TPMLVulkanRenderDriver(G.Driver).DeviceName <> '', '物理デバイスの名前が分かる');
    OffscreenChecks(G, 'vulkan');
  finally
    G.Free;
  end;
  CheckVulkanFormats;
  RunCommonScenes;
  CompareA('16 ビットの形式（持てれば持ったまま、持てなければ ARGB8888 へ変換）', @SceneSmallFormats, 2);
  CheckPaletteNative;
  CheckPixelArt;
  CheckRecreate;
end;

{ ---- ウィンドウ（実機のコンポジタがあるときだけ。手元専用） ---- }

procedure WindowSection;
var
  SizeOk: Boolean;
  Ctx: TPMLContext;
  VB: TPMLWaylandVideoBackend;
  Win, Plain, FailWin: TPMLWindow;
  R: TPMLRenderer;
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
    Raised := False;
    try
      TPMLRenderer.CreateForWindow(Plain, 'vulkan');
    except
      on E: EPMLUnsupported do
        Raised := True;
    end;
    Check(Raised, 'Vulkan でないウィンドウに vulkan を頼むと EPMLUnsupported');
    Plain.Free;

    Win := Ctx.Video.CreateWindow(
      TPMLWindowOptions.Make('papimela vulkan', 320, 200).Resizable.Vulkan);
    R := TPMLRenderer.CreateForWindow(Win);
    Check(R.DriverName = 'vulkan', 'Vulkan のウィンドウの既定は vulkan');
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

    // ビューポート (8, 8, 40, 40) の左上の隅に赤、クリップ (20, 20, 10, 10) の中に緑を描く（GL の検査と同じ）
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

    // 描画先のテクスチャは上下を反転させない
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

    // 最大化: スワップチェーンの作り直し（VK_ERROR_OUT_OF_DATE_KHR / VK_SUBOPTIMAL_KHR）
    Win.Maximize;
    Pump(500);
    R.Present;
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

    // 作れなかったとき: 名前で頼んでいるので、作れなかった例外のまま
    FailWin := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('named', 160, 100).Vulkan);
    PMLVulkanRenderFailCreate := True;
    Raised := False;
    try
      try
        TPMLRenderer.CreateForWindow(FailWin, 'vulkan');
      except
        on E: EPMLUnsupported do
          Raised := True;
      end;
    finally
      PMLVulkanRenderFailCreate := False;
    end;
    Check(Raised, '名前で vulkan を頼み、作れなければ EPMLUnsupported');
    FailWin.Free;

    Win.Free;   // レンダラもスワップチェーンも一緒に消える
    Pump(100);
    Check(wl_display_get_error(VB.Connection.Display) = 0, 'プロトコル違反が無い');
  finally
    Ctx.Free;
  end;
end;

begin
  WriteLn('test_render_vulkan — Vulkan のドライバをソフトウェアのドライバと比べる');
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
    WriteLn('=== 結論: Vulkan のドライバがソフトウェアのドライバと同じ絵を描く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
