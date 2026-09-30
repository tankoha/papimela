{
  demo_render_window — ウィンドウへ描くレンダラを実機のコンポジタで動かすデモ

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    TPMLRenderer.CreateForWindow でウィンドウに描き、毎フレーム Present する。
    回る三角形の扇（頂点色の補間）、半透明の矩形、拡大したテクスチャ、線を描く。
    終わったら、描いたフレーム数・実際に出した回数・作った shm バッファの数・
    VSync の待ちを打ち切った回数を出し、最後のフレームを BMP に保存する。

  WHY:
    test_render_window はダミーのウィンドウで「描画先が追従する」ことまでを見る。
    shm バッファの使い回し（release）と、フレームコールバックによる VSync は
    コンポジタが相手なので、ここで数字を見て確かめる。
    VSync が効いていれば、フレームレートは画面のリフレッシュレートに揃う。

  使い方:
    ./test/demo_render_window [秒数] [vsync|novsync] [幅x高さ]
      既定は 10 秒、VSync あり、640x400
      VSync を確かめるときは、描画が画面のリフレッシュより速く終わる小さな
      ウィンドウにする。描画が追いつかない大きさでは待つ前に次の合図が来ているので、
      VSync の有無で差が出ない（200Hz の画面で 640x400 は約 157 fps だった）
      V       VSync を切り替え
      Escape  終了（ウィンドウを閉じても終わる）
    ウィンドウの大きさを変えると、描画もそれに合わせて広がる。
}
program demo_render_window;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Platform.XKB,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.BMP,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland.Window,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Video.Wayland,
  PaPiMeLa.Render,
  PaPiMeLa.Core;

var
  Ctx    : TPMLContext;
  Win    : TPMLWindow;
  R      : TPMLRenderer;
  Checker: TPMLTexture;
  Running: Boolean = True;
  Seconds: Integer = 10;
  VSyncOn: Boolean = True;
  Resizes: Integer = 0;

function MakeVertex(AX, AY: Single; const AColor: TPMLFColor): TPMLVertex;
begin
  Result.Position := TPMLFPoint.Make(AX, AY);
  Result.Color := AColor;
  Result.TexCoord := TPMLFPoint.Make(0, 0);
end;

{ 16x16 の市松模様。拡大して最近傍で描くので、升目の縁がそのまま見える。 }
function MakeChecker: TPMLTexture;
var
  S: TPMLSurface;
  X, Y: Integer;
begin
  S := TPMLSurface.Create(16, 16, PML_PIXELFORMAT_ARGB8888);
  try
    for Y := 0 to 15 do
      for X := 0 to 15 do
        if ((X div 4) + (Y div 4)) mod 2 = 0 then
          S.WritePixel(X, Y, TPMLColor.Make(240, 240, 240, 255))
        else
          S.WritePixel(X, Y, TPMLColor.Make(40, 90, 200, 255));
    Result := R.CreateTextureFromSurface(S);
  finally
    S.Free;
  end;
end;

procedure DrawFrame(AT: Double);
const
  N = 12;
var
  W, H, I: Integer;
  CX, CY, Radius, A0, A1: Single;
  V: array of TPMLVertex;
  Center: TPMLFColor;
  Size, X: Single;
begin
  R.GetOutputSize(W, H);

  R.BlendMode := TPMLBlendMode.None;
  R.DrawColor := TPMLColor.Make(24, 26, 32);
  R.Clear;

  // 回る扇。中心は白、外周は色相を回した色。
  CX := W * 0.35;
  CY := H * 0.5;
  Radius := Min(W, H) * 0.4;
  Center := TPMLFColor.Make(1, 1, 1, 1);
  SetLength(V, N * 3);
  for I := 0 to N - 1 do
  begin
    A0 := AT + I * 2 * Pi / N;
    A1 := AT + (I + 1) * 2 * Pi / N;
    V[I * 3]     := MakeVertex(CX, CY, Center);
    V[I * 3 + 1] := MakeVertex(CX + Radius * Cos(A0), CY + Radius * Sin(A0),
      TPMLFColor.Make(0.5 + 0.5 * Cos(A0), 0.5 + 0.5 * Cos(A0 + 2.094),
                      0.5 + 0.5 * Cos(A0 + 4.189), 1));
    V[I * 3 + 2] := MakeVertex(CX + Radius * Cos(A1), CY + Radius * Sin(A1),
      TPMLFColor.Make(0.5 + 0.5 * Cos(A1), 0.5 + 0.5 * Cos(A1 + 2.094),
                      0.5 + 0.5 * Cos(A1 + 4.189), 1));
  end;
  R.RenderGeometry(nil, V, []);

  // 左右に揺れる半透明の矩形 3 枚。重なったところで合成が見える。
  R.BlendMode := TPMLBlendMode.Blend;
  for I := 0 to 2 do
  begin
    X := W * 0.55 + (W * 0.15) * Sin(AT * (1 + I * 0.3) + I);
    case I of
      0: R.DrawColor := TPMLColor.Make(255, 80, 80, 140);
      1: R.DrawColor := TPMLColor.Make(80, 255, 80, 140);
      2: R.DrawColor := TPMLColor.Make(80, 80, 255, 140);
    end;
    R.FillRect(TPMLFRect.Make(X, H * 0.15 + I * H * 0.08, W * 0.25, H * 0.3));
  end;

  // 拡大縮小するテクスチャ。
  Size := Min(W, H) * (0.25 + 0.08 * Sin(AT * 2));
  R.RenderTexture(Checker, TPMLFRect.Make(0, 0, 0, 0),
    TPMLFRect.Make(W * 0.72 - Size / 2, H * 0.72 - Size / 2, Size, Size));

  // 枠と対角線。
  R.BlendMode := TPMLBlendMode.None;
  R.DrawColor := TPMLColor.Make(255, 220, 0);
  R.DrawRect(TPMLFRect.Make(4, 4, W - 8, H - 8));
  R.DrawLine(4, H - 5, W - 5, 4);
end;

procedure HandleEvents;
var
  Ev: TPMLEvent;
begin
  while Ctx.Events.Poll(Ev) do
    case Ev.Kind of
      TPMLEventKind.WindowCloseRequested:
        Running := False;
      TPMLEventKind.WindowResized:
        begin
          Inc(Resizes);
          WriteLn(Format('  大きさ: %dx%d', [Ev.Window.Data1, Ev.Window.Data2]));
        end;
      TPMLEventKind.KeyDown:
        case Ev.Key.Keysym of
          XKB_KEY_Escape: Running := False;
          Ord('v'), Ord('V'):
            begin
              VSyncOn := not VSyncOn;
              R.VSync := Ord(VSyncOn);
              WriteLn('  VSync: ', BoolToStr(VSyncOn, True));
            end;
        end;
    end;
end;

var
  WB       : TPMLWaylandWindowBackend;
  Start, Now, LastReport, Deadline: UInt64;
  Frames, FramesSinceReport: Integer;
  Elapsed  : Double;
  Last     : TPMLSurface;
  OutPath  : String;
  VB       : TPMLWaylandVideoBackend;
  SizeArg  : String;
  Sep      : Integer;
  WinW     : Integer = 640;
  WinH     : Integer = 400;
  Mode     : TPMLDisplayMode;
begin
  if ParamCount >= 1 then
    Seconds := StrToIntDef(ParamStr(1), 10);
  if (ParamCount >= 2) and SameText(ParamStr(2), 'novsync') then
    VSyncOn := False;
  if ParamCount >= 3 then
  begin
    SizeArg := LowerCase(ParamStr(3));
    Sep := Pos('x', SizeArg);
    if Sep > 0 then
    begin
      WinW := StrToIntDef(Copy(SizeArg, 1, Sep - 1), WinW);
      WinH := StrToIntDef(Copy(SizeArg, Sep + 1, MaxInt), WinH);
    end;
  end;

  WriteLn('demo_render_window — ウィンドウへ描くレンダラ');
  WriteLn(Format('  %d 秒で自動終了。V で VSync 切り替え、Escape で終了。', [Seconds]));
  WriteLn;

  Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
  try
    if not (Ctx.Video.Backend is TPMLWaylandVideoBackend) then
    begin
      WriteLn('  Wayland で動かしてください（今のバックエンド: ', Ctx.Video.BackendName, '）');
      Exit;
    end;
    VB := TPMLWaylandVideoBackend(Ctx.Video.Backend);
    Mode := Ctx.Video.PrimaryDisplay.DesktopMode;
    WriteLn(Format('  画面: %dx%d  %.2f Hz', [Mode.Width, Mode.Height, Mode.RefreshRate]));
    Win := Ctx.Video.CreateWindow(
      TPMLWindowOptions.Make('papimela — render window', WinW, WinH).Resizable);
    WB := Win.Backend as TPMLWaylandWindowBackend;
    R := TPMLRenderer.CreateForWindow(Win);
    R.VSync := Ord(VSyncOn);
    Checker := MakeChecker;
    WriteLn(Format('  ドライバ: %s  VSync: %s', [R.DriverName, BoolToStr(VSyncOn, True)]));

    Frames := 0;
    FramesSinceReport := 0;
    Start := Ctx.Timer.TicksNS;
    LastReport := Start;
    Deadline := Start + UInt64(Seconds) * 1000000000;
    Now := Start;
    while Running and (Now < Deadline) do
    begin
      DrawFrame((Now - Start) / 1e9);
      R.Present;
      Inc(Frames);
      Inc(FramesSinceReport);
      Ctx.Events.Pump(0);
      HandleEvents;
      Now := Ctx.Timer.TicksNS;
      if Now - LastReport >= 1000000000 then
      begin
        Win.Title := Format('papimela — render window  %.1f fps',
          [FramesSinceReport / ((Now - LastReport) / 1e9)]);
        WriteLn(Format('  %5.1f fps  出した %d 回  shm バッファ累計 %d 枚  VSync 打ち切り %d 回',
          [FramesSinceReport / ((Now - LastReport) / 1e9), WB.PresentCount,
           WB.BuffersCreated, WB.FrameTimeouts]));
        FramesSinceReport := 0;
        LastReport := Now;
      end;
    end;
    Elapsed := (Now - Start) / 1e9;

    OutPath := IncludeTrailingPathDelimiter(GetTempDir) + 'papimela-render-window.bmp';
    Last := R.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    try
      PMLSaveBMPFile(OutPath, Last);
    finally
      Last.Free;
    end;

    WriteLn;
    WriteLn('=== 結果 ===');
    WriteLn(Format('  描いたフレーム: %d（%.1f 秒、平均 %.1f fps）',
      [Frames, Elapsed, Frames / Max(Elapsed, 0.001)]));
    WriteLn(Format('  画面へ出した回数: %d', [WB.PresentCount]));
    WriteLn(Format('  作った shm バッファ: 累計 %d 枚（リサイズ %d 回）',
      [WB.BuffersCreated, Resizes]));
    WriteLn(Format('  VSync の待ちを打ち切った回数: %d', [WB.FrameTimeouts]));
    WriteLn(Format('  wl_display_get_error: %d（0 ならプロトコル違反なし）',
      [wl_display_get_error(VB.Connection.Display)]));
    WriteLn('  最後のフレーム: ', OutPath);
    // レンダラはウィンドウが持っているので、ウィンドウを消せば一緒に消える。
    Win.Free;
  finally
    FreeAndNil(Ctx);
  end;
end.
