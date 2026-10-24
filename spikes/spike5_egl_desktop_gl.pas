{
  spike5_egl_desktop_gl — EGL でデスクトップ GL（互換プロファイル 2.1）のコンテキストが作れるか

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    窓なし（EGL_MESA_platform_surfaceless）で次を実測する。結果は spikes/RESULTS.md のスパイク 5。
      1. eglBindAPI(EGL_OPENGL_API) + EGL_OPENGL_BIT + 互換プロファイルの 2.1 のコンテキストが作れるか
      2. 作った後、glGetString で版・描画者・拡張を読む。SDL の render/opengl が要求する拡張
         （GL_ARB_shader_objects ほか）と、GL 2.1 の本体の関数が揃っているか
      3. 関数の取り方: libGL.so.1 / libOpenGL.so.0 の dlsym と eglGetProcAddress の違い
         （glvnd の eglGetProcAddress は、存在しない gl* にも非 nil を返す。D-38 の脇）
      4. 作れないコンテキスト（版 9.9）を試した後でも、続けて ES のコンテキストが作れるか
         （自動選択のフォールバックの前提）
      5. 互換プロファイルが取れないとき（コアだけ）の挙動の確認として、コアプロファイル 3.3 も作ってみる

  WHY:
    Render.GL（#44）は SDL に合わせて GL 2.1 互換プロファイルを使う。papimela は EGL 一本なので、
    EGL で取れなければ計画を見直す。
}
program spike5_egl_desktop_gl;

{$mode objfpc}{$H+}

uses
  SysUtils, Math, ctypes, Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Platform.EGL;

type
  TGetString = function(AName: LongWord): PAnsiChar; cdecl;
  TGetProc = function(AName: PAnsiChar): Pointer; cdecl;

const
  GL_VENDOR     = $1F00;
  GL_RENDERER   = $1F01;
  GL_VERSION    = $1F02;
  GL_EXTENSIONS = $1F03;
  EGL_PLATFORM_SURFACELESS_MESA_ = $31DD;

var
  Display: EGLDisplay;
  Failures: Integer = 0;

procedure Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
    WriteLn('  [OK]   ', ALabel)
  else
  begin
    WriteLn('  [NG]   ', ALabel);
    Inc(Failures);
  end;
end;

function HasWord(const AList, AWord: String): Boolean;
begin
  Result := Pos(' ' + AWord + ' ', ' ' + AList + ' ') > 0;
end;

function ChooseConfig(ARenderable: EGLint): EGLConfig;
var
  Attribs: array[0..4] of EGLint;
  Found: EGLint;
begin
  Attribs[0] := EGL_RENDERABLE_TYPE;
  Attribs[1] := ARenderable;
  Attribs[2] := EGL_SURFACE_TYPE;
  Attribs[3] := 0;
  Attribs[4] := EGL_NONE;
  Result := nil;
  Found := 0;
  if (eglChooseConfig(Display, @Attribs[0], @Result, 1, @Found) = EGL_FALSE) or (Found = 0) then
    Result := nil;
end;

// 互換 / コアのデスクトップ GL のコンテキスト。作れなければ EGL_NO_CONTEXT（理由を ALastError へ）
function MakeDesktopContext(AMajor, AMinor, AProfileBit: EGLint; out AErr: String): EGLContext;
var
  Config: EGLConfig;
  Attribs: array[0..8] of EGLint;
begin
  AErr := '';
  Result := EGL_NO_CONTEXT;
  if eglBindAPI(EGL_OPENGL_API) = EGL_FALSE then
  begin
    AErr := 'eglBindAPI(OpenGL): ' + PMLEGLErrorName(eglGetError());
    Exit;
  end;
  Config := ChooseConfig(EGL_OPENGL_BIT);
  if Config = nil then
  begin
    AErr := 'no EGL config for EGL_OPENGL_BIT';
    Exit;
  end;
  Attribs[0] := EGL_CONTEXT_MAJOR_VERSION_KHR;
  Attribs[1] := AMajor;
  Attribs[2] := EGL_CONTEXT_MINOR_VERSION_KHR;
  Attribs[3] := AMinor;
  Attribs[4] := EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR;
  Attribs[5] := AProfileBit;
  Attribs[6] := EGL_NONE;
  Result := eglCreateContext(Display, Config, EGL_NO_CONTEXT, @Attribs[0]);
  if Result = EGL_NO_CONTEXT then
    AErr := 'eglCreateContext: ' + PMLEGLErrorName(eglGetError());
end;

function MakeESContext(out AErr: String): EGLContext;
var
  Config: EGLConfig;
  Attribs: array[0..2] of EGLint;
begin
  AErr := '';
  Result := EGL_NO_CONTEXT;
  if eglBindAPI(EGL_OPENGL_ES_API) = EGL_FALSE then
  begin
    AErr := 'eglBindAPI(ES): ' + PMLEGLErrorName(eglGetError());
    Exit;
  end;
  Config := ChooseConfig(EGL_OPENGL_ES2_BIT);
  if Config = nil then
  begin
    AErr := 'no EGL config for ES2';
    Exit;
  end;
  Attribs[0] := EGL_CONTEXT_CLIENT_VERSION;
  Attribs[1] := 2;
  Attribs[2] := EGL_NONE;
  Result := eglCreateContext(Display, Config, EGL_NO_CONTEXT, @Attribs[0]);
  if Result = EGL_NO_CONTEXT then
    AErr := 'eglCreateContext(ES): ' + PMLEGLErrorName(eglGetError());
end;

var
  Ext, Exts, Err, Ver, Ren: String;
  Major, Minor: EGLint;
  Ctx: EGLContext;
  GL: TPMLDynLib;
  GetStr: TGetString;
  EglProc: Pointer;
  I: Integer;
  Known: Boolean;
begin
  // C のライブラリ（Mesa・LLVM）は浮動小数点の例外を無効にする前提（D-40）。PMLEGLLoad も止める
  if not PMLEGLLoad then
  begin
    WriteLn('libEGL を読み込めない');
    Halt(2);
  end;
  WriteLn('=== spike5: EGL でデスクトップ GL（互換 2.1）===');

  Ext := String(eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS));
  Check(HasWord(StringReplace(Ext, ' ', ' ', []), 'EGL_MESA_platform_surfaceless'),
    'クライアント拡張 EGL_MESA_platform_surfaceless');
  Display := EGL_NO_DISPLAY;
  if Assigned(eglGetPlatformDisplayEXT) then
    Display := eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA_, nil, nil);
  if (Display = EGL_NO_DISPLAY) and Assigned(eglGetPlatformDisplay) then
    Display := eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA_, nil, nil);
  Check(Display <> EGL_NO_DISPLAY, 'surfaceless の EGL ディスプレイ');
  if Display = EGL_NO_DISPLAY then
    Halt(2);
  Major := 0;
  Minor := 0;
  Check(eglInitialize(Display, @Major, @Minor) <> EGL_FALSE, Format('eglInitialize (EGL %d.%d)', [Major, Minor]));
  Exts := String(eglQueryString(Display, EGL_EXTENSIONS));
  Check(HasWord(Exts, 'EGL_KHR_surfaceless_context'), 'ディスプレイ拡張 EGL_KHR_surfaceless_context');
  Check(HasWord(Exts, 'EGL_KHR_create_context') or ((Major > 1) or ((Major = 1) and (Minor >= 5))),
    'コンテキストの版とプロファイルを指定できる（EGL_KHR_create_context か EGL 1.5）');

  WriteLn;
  WriteLn('1. 互換プロファイル 2.1');
  Ctx := MakeDesktopContext(2, 1, EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT_KHR, Err);
  Check(Ctx <> EGL_NO_CONTEXT, '互換プロファイル 2.1 のコンテキストが作れる ' + Err);
  if Ctx <> EGL_NO_CONTEXT then
  begin
    Check(eglMakeCurrent(Display, EGL_NO_SURFACE, EGL_NO_SURFACE, Ctx) <> EGL_FALSE, 'MakeCurrent（面なし）');

    WriteLn;
    WriteLn('3. 関数の取り方');
    GL := TPMLDynLib.Create(['libGL.so.1', 'libOpenGL.so.0', 'libGL.so']);
    try
      WriteLn('  ライブラリ: ', GL.Name);
      Pointer(GetStr) := GL.TryResolve('glGetString');
      Check(Assigned(GetStr), 'libGL の dlsym で glGetString が引ける');
      if Assigned(GetStr) then
      begin
        Ver := String(GetStr(GL_VERSION));
        Ren := String(GetStr(GL_RENDERER));
        WriteLn('  GL_VERSION  : ', Ver);
        WriteLn('  GL_RENDERER : ', Ren);
        Exts := String(GetStr(GL_EXTENSIONS));
        Check(Exts <> '', 'GL_EXTENSIONS が読める（互換プロファイルは文字列の形）');
        for Ext in TStringArray.Create('GL_ARB_shader_objects', 'GL_ARB_shading_language_100', 'GL_ARB_vertex_shader',
          'GL_ARB_fragment_shader', 'GL_EXT_framebuffer_object', 'GL_ARB_multitexture',
          'GL_ARB_texture_non_power_of_two', 'GL_ARB_texture_rectangle', 'GL_EXT_bgra') do
          Check(HasWord(Exts, Ext), '拡張 ' + Ext);
      end;
      // GL 1.x の本体の関数（SDL_glfuncs.h）と、ARB / EXT の名前
      for Ext in TStringArray.Create('glClear', 'glGenTextures', 'glMatrixMode', 'glOrtho', 'glVertexPointer', 'glDrawArrays',
        'glBlendEquation', 'glBlendFuncSeparate', 'glReadPixels', 'glPixelStorei') do
        Check(GL.TryResolve(Ext) <> nil, 'dlsym: ' + Ext);
      for Ext in TStringArray.Create('glCreateShaderObjectARB', 'glUseProgramObjectARB', 'glUniform4fARB', 'glActiveTextureARB',
        'glGenFramebuffersEXT', 'glBindFramebufferEXT', 'glFramebufferTexture2DEXT') do
      begin
        Check(GL.TryResolve(Ext) <> nil, 'dlsym: ' + Ext);
        EglProc := eglGetProcAddress(PAnsiChar(AnsiString(Ext)));
        Check(EglProc <> nil, 'eglGetProcAddress: ' + Ext);
      end;
      // glvnd の癖: 存在しない名前にも非 nil を返すか
      EglProc := eglGetProcAddress('glThisFunctionDoesNotExist');
      WriteLn('  eglGetProcAddress("glThisFunctionDoesNotExist") = ', PtrUInt(EglProc) <> 0,
        '（非 nil なら、存在の確認には使えない）');
      Known := GL.TryResolve('glThisFunctionDoesNotExist') = nil;
      Check(Known, 'dlsym は存在しない名前に nil を返す');
    finally
      GL.Free;
    end;
    eglMakeCurrent(Display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(Display, Ctx);
  end;

  WriteLn;
  WriteLn('4. 作れないコンテキストの後に ES が作れるか');
  Ctx := MakeDesktopContext(9, 9, EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT_KHR, Err);
  Check(Ctx = EGL_NO_CONTEXT, '版 9.9 は断られる: ' + Err);
  Ctx := MakeESContext(Err);
  Check(Ctx <> EGL_NO_CONTEXT, '続けて ES 2.0 のコンテキストが作れる ' + Err);
  if Ctx <> EGL_NO_CONTEXT then
  begin
    Check(eglMakeCurrent(Display, EGL_NO_SURFACE, EGL_NO_SURFACE, Ctx) <> EGL_FALSE, 'ES を MakeCurrent');
    eglMakeCurrent(Display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(Display, Ctx);
  end;
  // もう一度デスクトップ → ES → デスクトップ（API の切り替えが残らないか）
  Ctx := MakeDesktopContext(2, 1, EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT_KHR, Err);
  Check(Ctx <> EGL_NO_CONTEXT, 'ES の後でも互換 2.1 が作れる ' + Err);
  if Ctx <> EGL_NO_CONTEXT then
    eglDestroyContext(Display, Ctx);

  WriteLn;
  WriteLn('5. 参考: コアプロファイル 3.3');
  Ctx := MakeDesktopContext(3, 3, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR, Err);
  if Ctx <> EGL_NO_CONTEXT then WriteLn('  コア 3.3: 作れる') else WriteLn('  コア 3.3: 作れない ', Err);
  if Ctx <> EGL_NO_CONTEXT then
    eglDestroyContext(Display, Ctx);

  eglTerminate(Display);
  PMLEGLUnload;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: EGL でデスクトップ GL（互換 2.1）が使える ===')
  else
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
  if Failures <> 0 then
    Halt(1);
end.
