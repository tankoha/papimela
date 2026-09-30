{
  test_gl_window — Wayland のウィンドウに OpenGL ES で描く

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    TPMLWindow.CreateGLContext / SwapGL / TPMLGLContext を実機のコンポジタで動かす。
    1. 前提（能力、OpenGL で作っていないウィンドウは断る）
    2. コンテキストと関数の取得（GLES 2.0 以上、57 関数がそろう）
    3. 塗った色が読み戻せる（面の大きさがウィンドウと同じ）
    4. VSync（SwapInterval 1 は画面のリフレッシュ、0 はそれより速い）
    5. 大きさの変更（最大化すると面も大きくなる）
    6. 最小化・非表示でも止まらない
    7. 破棄の順序（ウィンドウが先でもコンテキストが先でも落ちない）とプロトコル違反

  WHY:
    #33 / #39（EGL と Wayland の EGL）の受け入れ検査。実装より先に書いた。
    GL はコンポジタと GPU が相手なので CI では走らない（T-18 と同じく手元専用）。

  実行前提: Wayland セッションと EGL（Mesa など）。
}
program test_gl_window;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.GLES2,
  PaPiMeLa.Core;

var
  Failures: Integer = 0;
  Ctx: TPMLContext;
  GL : TPMLGLES2Functions;

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

// TPMLGLGetProc の形で公開 API の GLGetProcAddress を呼ぶ。
function GetProc(AName: PAnsiChar): Pointer; cdecl;
begin
  Result := Ctx.Video.GLGetProcAddress(String(AName));
end;

procedure Pump(AMs: Integer);
var
  T0: UInt64;
  Ev: TPMLEvent;
begin
  T0 := Ctx.Timer.TicksNS;
  repeat
    Ctx.Events.Pump(10);
    while Ctx.Events.Poll(Ev) do ;
  until Ctx.Timer.TicksNS - T0 >= UInt64(AMs) * 1000000;
end;

{ 塗って出すのを AMs ミリ秒続け、1 秒あたりの回数を返す。 }
function MeasureFps(AWin: TPMLWindow; AMs: Integer): Double;
var
  T0, T: UInt64;
  N: Integer;
  Ev: TPMLEvent;
begin
  N := 0;
  T0 := Ctx.Timer.TicksNS;
  repeat
    GL.glClearColor((N mod 60) / 60, 0.2, 0.4, 1);
    GL.glClear(GL_COLOR_BUFFER_BIT);
    AWin.SwapGL;
    Inc(N);
    Ctx.Events.Pump(0);
    while Ctx.Events.Poll(Ev) do ;
    T := Ctx.Timer.TicksNS;
  until T - T0 >= UInt64(AMs) * 1000000;
  Result := N / ((T - T0) / 1e9);
end;

function ReadPixel(AX, AY: Integer): LongWord;
var
  Px: array[0..3] of Byte;
begin
  FillChar(Px, SizeOf(Px), 0);
  GL.glReadPixels(AX, AY, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, @Px[0]);
  Result := (LongWord(Px[0]) shl 24) or (LongWord(Px[1]) shl 16)
          or (LongWord(Px[2]) shl 8) or Px[3];
end;

function Near(AGot, AWant: LongWord): Boolean;
var
  I: Integer;
begin
  for I := 0 to 3 do
    if Abs(Integer((AGot shr (I * 8)) and $FF) - Integer((AWant shr (I * 8)) and $FF)) > 1 then
      Exit(False);
  Result := True;
end;

var
  VB     : TPMLWaylandVideoBackend;
  Plain, Win, Win2: TPMLWindow;
  C, C2  : TPMLGLContext;
  Raised : Boolean;
  Missing: String;
  Version: String;
  VP     : array[0..3] of GLint;
  Refresh, Fps0, Fps1, FpsMin, FpsHidden: Double;
  R      : TPMLRect;
begin
  WriteLn('test_gl_window — Wayland のウィンドウに OpenGL ES で描く');
  WriteLn;

  Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
  try
    if not (Ctx.Video.Backend is TPMLWaylandVideoBackend) then
    begin
      WriteLn('  Wayland セッションで実行してください');
      Halt(1);
    end;
    VB := TPMLWaylandVideoBackend(Ctx.Video.Backend);
    Refresh := Ctx.Video.PrimaryDisplay.DesktopMode.RefreshRate;

    WriteLn('1. 前提');
    Check(TPMLVideoCapability.OpenGLES in Ctx.Video.Capabilities, '能力 OpenGLES がある');
    Check(Ctx.Video.Backend.GL <> nil, 'GL の部品がある');
    Plain := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('plain', 160, 100));
    Raised := False;
    try
      Plain.CreateGLContext;
    except
      on E: EPMLUnsupported do
        Raised := True;
    end;
    Check(Raised, 'OpenGL で作っていないウィンドウでは EPMLUnsupported');
    Plain.Free;

    WriteLn;
    WriteLn('2. コンテキスト');
    Win := Ctx.Video.CreateWindow(
      TPMLWindowOptions.Make('papimela GL', 320, 200).Resizable.OpenGL);
    C := Win.CreateGLContext;
    Check(C.Handle <> nil, 'コンテキストができる');
    Check(Win.DependentCount = 1, 'ウィンドウに登録される');
    Check(Ctx.Video.GLGetProcAddress('glClear') <> nil, 'glClear の番地が取れる');
    Check(Ctx.Video.GLGetProcAddress('glNoSuchFunction') = nil, '無い関数は nil');
    Missing := PMLLoadGLES2Functions(@GetProc, GL);
    if Missing <> '' then
      WriteLn('  [INFO] 無い関数: ', Missing);
    Check(Missing = '', 'GLES 2.0 の 57 関数がそろう');
    Version := String(PAnsiChar(GL.glGetString(GL_VERSION)));
    WriteLn('  [INFO] GL_VERSION = ', Version);
    WriteLn('  [INFO] GL_RENDERER = ', String(PAnsiChar(GL.glGetString(GL_RENDERER))));
    Check(Copy(Version, 1, 9) = 'OpenGL ES', 'OpenGL ES のコンテキスト');

    WriteLn;
    WriteLn('3. 塗って読み戻す');
    Pump(300);   // configure を受ける
    GL.glGetIntegerv(GL_VIEWPORT, @VP[0]);
    Check((VP[2] = 320) and (VP[3] = 200),
      Format('面の大きさはウィンドウと同じ（viewport %dx%d）', [VP[2], VP[3]]));
    GL.glClearColor(0.25, 0.5, 0.75, 1);
    GL.glClear(GL_COLOR_BUFFER_BIT);
    Check(Near(ReadPixel(0, 0), $4080BFFF), Format('左下の画素（%s）', [IntToHex(ReadPixel(0, 0), 8)]));
    Check(Near(ReadPixel(319, 199), $4080BFFF), '右上の画素');
    Check(GL.glGetError() = GL_NO_ERROR, 'GL のエラーが無い');
    Win.SwapGL;

    WriteLn;
    WriteLn('4. VSync');
    C.SwapInterval := 1;
    Check(C.SwapInterval = 1, 'SwapInterval 1');
    Fps1 := MeasureFps(Win, 1500);
    C.SwapInterval := 0;
    Fps0 := MeasureFps(Win, 1500);
    WriteLn(Format('  [INFO] 画面 %.1f Hz、SwapInterval 1: %.1f fps、0: %.1f fps', [Refresh, Fps1, Fps0]));
    Check((Fps1 > Refresh * 0.8) and (Fps1 < Refresh * 1.1), 'SwapInterval 1 は画面のリフレッシュに揃う');
    Check(Fps0 > Refresh * 1.5, 'SwapInterval 0 はそれより速い');
    C.SwapInterval := 5;
    Check(C.SwapInterval = 1, '2 以上は 1 に丸める（SDL の Wayland_GLES_SetSwapInterval と同じ）');
    C.SwapInterval := 1;

    WriteLn;
    WriteLn('5. 大きさの変更');
    Win.Maximize;
    Pump(500);
    R := Win.SizeInPixels;
    Win.SwapGL;   // 新しい大きさの面は次の絵から
    GL.glViewport(0, 0, R.W, R.H);
    GL.glClearColor(1, 0, 0, 1);
    GL.glClear(GL_COLOR_BUFFER_BIT);
    WriteLn(Format('  [INFO] 最大化後 %dx%d', [R.W, R.H]));
    Check((R.W > 320) and (R.H > 200), 'ウィンドウが大きくなった');
    Check(Near(ReadPixel(R.W - 1, R.H - 1), $FF0000FF), '新しい右上の隅まで塗れる（面が大きくなった）');
    Win.SwapGL;
    Win.Restore;
    Pump(500);

    WriteLn;
    WriteLn('6. 最小化・非表示');
    Win.Minimize;
    Pump(300);
    FpsMin := MeasureFps(Win, 1000);
    WriteLn(Format('  [INFO] 最小化中 %.1f fps', [FpsMin]));
    Check((FpsMin > 10) and (FpsMin < Refresh * 1.1), '最小化しても止まらない（合図が来なければ打ち切る）');
    Win.Restore;
    Win.Hide;
    Pump(200);
    FpsHidden := MeasureFps(Win, 500);
    WriteLn(Format('  [INFO] 非表示中 %.1f fps', [FpsHidden]));
    Check(FpsHidden > 10, '非表示でも SwapGL が止まらない');
    Win.Show;
    Pump(300);
    Win.SwapGL;

    WriteLn;
    WriteLn('7. 破棄の順序');
    Win2 := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('second', 200, 120).OpenGL);
    C2 := Win2.CreateGLContext;
    Pump(200);
    GL.glClearColor(0, 1, 0, 1);
    GL.glClear(GL_COLOR_BUFFER_BIT);
    Win2.SwapGL;
    C2.Free;
    Check(Win2.DependentCount = 0, 'コンテキストを先に Free するとウィンドウの一覧から外れる');
    Win2.Free;
    C.MakeCurrent;
    Win.SwapGL;
    Check(True, '別のウィンドウを壊しても最初のコンテキストは使える');
    Win.Free;     // コンテキスト C も一緒に消える
    Pump(100);
    Check(wl_display_get_error(VB.Connection.Display) = 0, 'プロトコル違反が無い');

    // 最後に、コンテキストを残したまま Context を畳む
    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('left alive', 120, 80).OpenGL);
    Win.CreateGLContext;
    Pump(100);
  finally
    Ctx.Free;
  end;
  Check(True, 'コンテキストを残したまま Context を畳んでも落ちない');

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: Wayland のウィンドウに OpenGL ES で描ける ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
