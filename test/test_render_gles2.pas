{
  test_render_gles2 — GPU（OpenGL ES 2.0）のドライバをソフトウェアのドライバと比べる

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. オフスクリーン（窓の無い GL）で、同じ場面を GLES2 のドライバとソフトウェアの
       ドライバの両方で描き、画素ごとに比べる。場面ごとに許す差（1 成分あたり）と、
       それを超えてよい画素の数を決めてある
       パレット（INDEX8）の場面は、GPU がドライバの写しで描くことと、Linear の補間も見る
       YUV の場面は、GPU の浮動小数の行列とソフトウェアの整数の表の差（1 成分 3 まで）を許す
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
  PaPiMeLa.Surface.YUV,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Render,
  PaPiMeLa.Render.GLES2,
  PaPiMeLa.Core;

{$I render_scenes.inc}

function NewGPU: TPMLRenderer;
begin
  Result := TPMLRenderer.Create(TPMLGLES2RenderDriver.CreateOffscreen(W, H));
end;

// GLES2 は既定の許容のまま
procedure AdjustTolerance(const AName: String; var ATolerance, AMaxBad: Integer);
begin
end;

{ ---- GLES2 だけの確かめ（SDL の GLES2 のドライバの振る舞い） ---- }

{ 拡大の方式（§3 の 3a）。SDL の GLES2 のドライバは、PIXELART の本物のシェーダを OPENGLES_300 の
  ときだけ使い、その定義はどこにも無いので、実際は NEAREST と同じ絵になる。papimela も同じ。 }
procedure CheckScaleModes;
var
  Rs: array[0..2] of TPMLRenderer;
  Shots: array[0..2] of TPMLSurface;
  Modes: array[0..2] of TPMLScaleMode;
  T: TPMLTexture;
  I, X, Y, SameNP, DiffNL: Integer;
begin
  Modes[0] := TPMLScaleMode.Nearest;
  Modes[1] := TPMLScaleMode.PixelArt;
  Modes[2] := TPMLScaleMode.Linear;
  for I := 0 to 2 do
  begin
    Rs[I] := NewGPU;
    Background(Rs[I]);
    T := Rs[I].CreateTextureFromSurface(Checker);
    T.ScaleMode := Modes[I];
    Rs[I].RenderTexture(T, FR(0, 0, 0, 0), FR(3, 3, 37, 41));
    Shots[I] := Rs[I].ReadPixels(TPMLRect.Make(0, 0, 0, 0));
  end;
  try
    SameNP := 0;
    DiffNL := 0;
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
      begin
        if Shots[0].ReadRaw(X, Y) = Shots[1].ReadRaw(X, Y) then
          Inc(SameNP);
        if Shots[0].ReadRaw(X, Y) <> Shots[2].ReadRaw(X, Y) then
          Inc(DiffNL);
      end;
    Check(SameNP = W * H, 'GPU でも PixelArt は Nearest と同じ絵（SDL の GLES2 と同じ）');
    Check(DiffNL > 0, '（確かめ）Linear は Nearest と違う絵になる');
  finally
    for I := 0 to 2 do
    begin
      Shots[I].Free;
      Rs[I].Free;
    end;
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
        Check(False, '窓の無い GL で GLES2 のドライバを作れる（' + E.Message + '）');
      Exit;
    end;
  end;
  try
    OffscreenChecks(G, 'gles2');
  finally
    G.Free;
  end;
  RunCommonScenes;
  CheckScaleModes;
  RunNativeChecks;
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