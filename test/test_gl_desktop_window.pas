{
  test_gl_desktop_window — Wayland のウィンドウにデスクトップ OpenGL（互換プロファイル 2.1）で描く

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    TPMLWindow.CreateGLContext（互換プロファイル）/ GLGetProcAddress / SwapGL を実機のコンポジタで動かす。
    1. 前提（能力 OpenGL、プロファイルごとに要る能力）
    2. 互換 2.1 のコンテキストと関数の取得（コア 48 関数 + 拡張 4 グループ、デスクトップの本体の関数は libGL から）
    3. 塗った色が読み戻せる、VSync
    4. 自動選択のフォールバックの前提: 同じ窓で、デスクトップ GL の作成に失敗した後に ES が作れるか、
       デスクトップ GL が作れた後の同じ窓で ES / 別の窓で ES が作れるか（窓の面の config は最初の CreateContext で決まる）
    5. ES の窓とデスクトップ GL の窓を行き来しても、それぞれの API で動く
    6. 破棄の順序とプロトコル違反

  WHY:
    Render.GL（#44）の受け入れ検査の足場（段 2）。窓の面の config が最初のコンテキストで決まるので、
    デスクトップ GL が作れなかったときに同じ窓で gles2 へ戻れるか（自動選択のフォールバック）を実測する。
    GL はコンポジタと GPU が相手なので CI では走らない（T-21 と同じく手元専用）。

  実行前提: Wayland セッションと EGL・libGL（Mesa など）。
}
program test_gl_desktop_window;

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
  PaPiMeLa.Platform.GL,
  PaPiMeLa.Core;

var
  Failures: Integer = 0;
  Ctx: TPMLContext;
  GL : TPMLGLFunctions;

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
  until (Ctx.Timer.TicksNS - T0) div 1000000 >= UInt64(AMs);
end;

function CompatAttrs: TPMLGLAttributes;
begin
  Result := TPMLGLAttributes.Default;
  Result.Profile := TPMLGLProfile.Compatibility;
  Result.MajorVersion := 2;
  Result.MinorVersion := 1;
end;

function ReadPixel(AX, AY: Integer): LongWord;
var
  Px: array[0..3] of Byte;
begin
  FillChar(Px, SizeOf(Px), 0);
  GL.glReadPixels(AX, AY, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, @Px[0]);
  Result := (LongWord(Px[0]) shl 24) or (LongWord(Px[1]) shl 16) or (LongWord(Px[2]) shl 8) or Px[3];
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

function Pick(ACond: Boolean; const AYes, ANo: String): String;
begin
  if ACond then
    Result := AYes
  else
    Result := ANo;
end;

function VersionText: String;
begin
  Result := String(PAnsiChar(GL.glGetString(GL_VERSION)));
end;

// コンテキストを作る。作れなければ nil（理由を AMsg へ）
function TryCreate(AWin: TPMLWindow; const AAttrs: TPMLGLAttributes; out AMsg: String): TPMLGLContext;
begin
  AMsg := '';
  Result := nil;
  try
    Result := AWin.CreateGLContext(AAttrs);
  except
    on E: EPMLError do
      AMsg := E.Message;
  end;
end;

var
  VB     : TPMLWaylandVideoBackend;
  Plain, Win, WinA, WinB, WinC: TPMLWindow;
  C, CA, CB, CC: TPMLGLContext;
  Raised : Boolean;
  Missing, Msg: String;
  G      : TPMLGLExtGroup;
  Attrs  : TPMLGLAttributes;
begin
  WriteLn('test_gl_desktop_window — Wayland のウィンドウにデスクトップ OpenGL（互換 2.1）で描く');
  WriteLn;

  Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
  try
    if not (Ctx.Video.Backend is TPMLWaylandVideoBackend) then
    begin
      WriteLn('  Wayland セッションで実行してください');
      Halt(1);
    end;
    VB := TPMLWaylandVideoBackend(Ctx.Video.Backend);

    WriteLn('1. 前提');
    Check(TPMLVideoCapability.OpenGL in Ctx.Video.Capabilities, '能力 OpenGL がある');
    Check(TPMLVideoCapability.OpenGLES in Ctx.Video.Capabilities, '能力 OpenGLES もある');
    Plain := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('plain', 160, 100));
    Raised := False;
    try
      Plain.CreateGLContext(CompatAttrs);
    except
      on E: EPMLUnsupported do
        Raised := True;
    end;
    Check(Raised, 'OpenGL で作っていないウィンドウでは EPMLUnsupported');
    Plain.Free;

    WriteLn;
    WriteLn('2. 互換 2.1 のコンテキストと関数');
    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('papimela desktop GL', 320, 200).Resizable.OpenGL);
    C := Win.CreateGLContext(CompatAttrs);
    Check(C.Handle <> nil, 'コンテキストができる');
    Check(Ctx.Video.GLGetProcAddress('glBegin') <> nil, '本体の関数（glBegin。GLES2 には無い）の番地が取れる');
    Check(Ctx.Video.GLGetProcAddress('glMatrixMode') <> nil, 'glMatrixMode の番地が取れる');
    Check(Ctx.Video.GLGetProcAddress('glNoSuchFunction') = nil, '無い関数は nil');
    Missing := PMLLoadGLFunctions(@GetProc, GL);
    if Missing <> '' then
      WriteLn('  [INFO] 無い関数: ', Missing);
    Check(Missing = '', 'コアの 48 関数がそろう');
    for G := Low(TPMLGLExtGroup) to High(TPMLGLExtGroup) do
    begin
      Missing := PMLLoadGLExtFunctions(@GetProc, GL, G);
      Check(Missing = '', '拡張のグループ ' + IntToStr(Ord(G)) + ' がそろう ' + Missing);
    end;
    WriteLn('  [INFO] GL_VERSION = ', VersionText);
    WriteLn('  [INFO] GL_RENDERER = ', String(PAnsiChar(GL.glGetString($1F01))));
    Check(Copy(VersionText, 1, 9) <> 'OpenGL ES', 'OpenGL ES ではない（デスクトップ GL）');

    WriteLn;
    WriteLn('3. 塗って読み戻す、VSync');
    Pump(300);
    GL.glClearColor(0.25, 0.5, 0.75, 1);
    GL.glClear(GL_COLOR_BUFFER_BIT);
    Check(Near(ReadPixel(0, 0), $4080BFFF), Format('左下の画素（%s）', [IntToHex(ReadPixel(0, 0), 8)]));
    Check(Near(ReadPixel(319, 199), $4080BFFF), '右上の画素');
    Check(GL.glGetError() = GL_NO_ERROR, 'GL のエラーが無い');
    Win.SwapGL;
    C.SwapInterval := 1;
    Check(C.SwapInterval = 1, 'SwapInterval 1');
    C.SwapInterval := 0;
    Check(C.SwapInterval = 0, 'SwapInterval 0');
    Win.SwapGL;

    WriteLn;
    WriteLn('4. 窓の面の config とフォールバックの前提');
    // (a) デスクトップ GL の作成に失敗した（版 9.9）後、同じ窓で ES が作れるか
    WinA := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('fallback A', 160, 100).OpenGL);
    Attrs := CompatAttrs;
    Attrs.MajorVersion := 9;
    Attrs.MinorVersion := 9;
    CA := TryCreate(WinA, Attrs, Msg);
    Check(CA = nil, 'デスクトップ GL 9.9 は断られる: ' + Msg);
    CB := TryCreate(WinA, TPMLGLAttributes.Default, Msg);
    Check(CB <> nil, '(a) 失敗した同じ窓で、続けて ES が作れる ' + Msg);
    if CB <> nil then
    begin
      PMLLoadGLFunctions(@GetProc, GL);
      WriteLn('  [INFO] (a) GL_VERSION = ', VersionText);
    end;

    // (b) デスクトップ GL が作れた窓で、続けて ES を作る
    WinB := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('fallback B', 160, 100).OpenGL);
    CA := TryCreate(WinB, CompatAttrs, Msg);
    Check(CA <> nil, 'デスクトップ GL が作れる ' + Msg);
    CB := TryCreate(WinB, TPMLGLAttributes.Default, Msg);
    WriteLn('  [INFO] (b) デスクトップ GL の窓に ES: ', Pick(CB <> nil, '作れる', '作れない ' + Msg));

    // (c) ES が先の窓で、続けてデスクトップ GL を作る
    WinC := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('fallback C', 160, 100).OpenGL);
    CC := TryCreate(WinC, TPMLGLAttributes.Default, Msg);
    Check(CC <> nil, 'ES が作れる ' + Msg);
    CA := TryCreate(WinC, CompatAttrs, Msg);
    WriteLn('  [INFO] (c) ES の窓にデスクトップ GL: ', Pick(CA <> nil, '作れる', '作れない ' + Msg));

    WriteLn;
    WriteLn('5. ES の窓とデスクトップ GL の窓を行き来する');
    WinA := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('desktop', 160, 100).OpenGL);
    WinB := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('es', 160, 100).OpenGL);
    CA := WinA.CreateGLContext(CompatAttrs);
    CB := WinB.CreateGLContext;
    CA.MakeCurrent;
    PMLLoadGLFunctions(@GetProc, GL);
    Check(Copy(VersionText, 1, 9) <> 'OpenGL ES', 'デスクトップ GL を現在にすると、デスクトップ GL');
    CB.MakeCurrent;
    Check(Ctx.Video.GLGetProcAddress('glClear') <> nil, 'ES を現在にしても glClear が引ける');
    CA.MakeCurrent;
    Check(Ctx.Video.GLGetProcAddress('glBegin') <> nil, '戻すと本体の関数（glBegin）が引ける');
    GL.glClearColor(1, 0, 0, 1);
    GL.glClear(GL_COLOR_BUFFER_BIT);
    Check(GL.glGetError() = GL_NO_ERROR, 'デスクトップ GL に戻して描ける');
    WinA.SwapGL;

    WriteLn;
    Check(wl_display_get_error(VB.Connection.Display) = 0, 'プロトコル違反が無い');

    // 最後に、コンテキストを残したまま Context を畳む
    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('left alive', 120, 80).OpenGL);
    Win.CreateGLContext(CompatAttrs);
    Pump(100);
  finally
    Ctx.Free;
  end;
  Check(True, 'コンテキストを残したまま Context を畳んでも落ちない');

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: Wayland のウィンドウにデスクトップ OpenGL（互換 2.1）で描ける ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
