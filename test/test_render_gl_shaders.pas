{
  test_render_gl_shaders — デスクトップ GL のシェーダ（TPMLGLShaderContext）の確かめ

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    窓の無い GL（EGL の surfaceless、互換プロファイル 2.1）のコンテキストで、次を確かめる。
      1. TryCreate が非 nil
      2. None 以外の 13 本がすべて Supports（None は False）
      3. 各シェーダを Select して glGetError = GL_NO_ERROR
      4. 同じ AParams での再 Select は uniform を設定し直さず、違う値なら設定し直す
         （取得関数を差し替えて glUniform*ARB の呼び出しを数える）
      5. 画素の確かめ: 4x4 の FBO に各シェーダで 1 枚の矩形を描き、中央の画素が期待の色になる
         （tex0〜tex2 のユニット、uniform の名前と並び、パレット、YUV / NV12 / NV21 の並べ替え）
      6. 矩形テクスチャのモード（拡張の文字列を偽って GL_ARB_texture_non_power_of_two を外し、
         GL_ARB_texture_rectangle を入れる）で、sampler2DRect の前置きが効いて矩形テクスチャが引ける
      7. 拡張が欠けた文字列（語の完全一致を含む）で TryCreate が nil
      8. 関数が欠ける場合（glUniform4fARB だけ nil を返す取得関数）で nil

  WHY:
    #44 の Render.GL.Shaders の受け入れ検査。実装より先に書いた（骨組みの空の実装で落ちることを確かめた）。
    GLSL のソースの文字列は SDL の C と機械的に突き合わせてあるが、ここでは「その文字列が実際に
    コンパイルされ、期待の色を出す」ことを GPU（実行環境は Mesa の llvmpipe でもよい）で確かめる。

  実行前提: EGL と Mesa の surfaceless と libGL がある。使えなければ失敗。GL の無い環境で飛ばすには
            PAPIMELA_GL_OPTIONAL=1。そのとき、#version 130 を受け付けない環境の PIXELART の 3 本も
            飛ばせる（既定では失敗）。CI は
              env -u WAYLAND_DISPLAY LIBGL_ALWAYS_SOFTWARE=1 ./test/test_render_gl_shaders
}
program test_render_gl_shaders;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Platform.EGL,
  PaPiMeLa.Platform.EGL.Surfaceless,
  PaPiMeLa.Platform.GL,
  PaPiMeLa.Render.GL.Shaders;

const
  GL_EXTENSIONS_ = $1F03;
  RT_SIZE = 4;
  TOLERANCE = 2;
  // SDL の render/opengl が要求する 4 つの拡張（シェーダの判定）
  BASE_EXTS = 'GL_ARB_shader_objects GL_ARB_shading_language_100 GL_ARB_vertex_shader GL_ARB_fragment_shader';
  BaseExtNames: array[0..3] of String = ('GL_ARB_shader_objects', 'GL_ARB_shading_language_100',
    'GL_ARB_vertex_shader', 'GL_ARB_fragment_shader');

type
  TUniform1f = procedure(ALocation: GLint; A2: GLfloat); cdecl;
  TUniform3f = procedure(ALocation: GLint; A2, A3, A4: GLfloat); cdecl;
  TUniform4f = procedure(ALocation: GLint; A2, A3, A4, A5: GLfloat); cdecl;
  TRGBA = array[0..3] of Byte;

var
  Failures: Integer = 0;
  Display: EGLDisplay = nil;
  GLib: TPMLDynLib = nil;
  G: TPMLGLFunctions;
  // uniform の呼び出しを数える偽物（取得関数が返す）
  CountU1f, CountU3f, CountU4f: Integer;
  RealU1f: TUniform1f;
  RealU3f: TUniform3f;
  RealU4f: TUniform4f;

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

function Optional: Boolean;
begin
  Result := GetEnvironmentVariable('PAPIMELA_GL_OPTIONAL') = '1';
end;

{ ---- 取得関数（libGL の dlsym。eglGetProcAddress は存在しない名前にも非 nil を返すので使わない） ---- }

function RealProc(AName: PAnsiChar): Pointer; cdecl;
begin
  Result := GLib.TryResolve(String(AName));
end;

procedure TrampU1f(ALocation: GLint; A2: GLfloat); cdecl;
begin
  Inc(CountU1f);
  RealU1f(ALocation, A2);
end;

procedure TrampU3f(ALocation: GLint; A2, A3, A4: GLfloat); cdecl;
begin
  Inc(CountU3f);
  RealU3f(ALocation, A2, A3, A4);
end;

procedure TrampU4f(ALocation: GLint; A2, A3, A4, A5: GLfloat); cdecl;
begin
  Inc(CountU4f);
  RealU4f(ALocation, A2, A3, A4, A5);
end;

{ glUniform1f / 3f / 4f を数える偽物に差し替える取得関数 }
function CountingProc(AName: PAnsiChar): Pointer; cdecl;
begin
  Result := RealProc(AName);
  if Result = nil then
    Exit;
  if String(AName) = 'glUniform1fARB' then
  begin
    RealU1f := TUniform1f(Result);
    Result := @TrampU1f;
  end
  else if String(AName) = 'glUniform3fARB' then
  begin
    RealU3f := TUniform3f(Result);
    Result := @TrampU3f;
  end
  else if String(AName) = 'glUniform4fARB' then
  begin
    RealU4f := TUniform4f(Result);
    Result := @TrampU4f;
  end;
end;

{ glUniform4fARB だけ nil を返す取得関数 }
function MissingU4Proc(AName: PAnsiChar): Pointer; cdecl;
begin
  if String(AName) = 'glUniform4fARB' then
    Result := nil
  else
    Result := RealProc(AName);
end;

{ ---- 窓なしのデスクトップ GL（互換 2.1） ---- }

function ChooseConfig: EGLConfig;
var
  Attribs: array[0..4] of EGLint;
  Found: EGLint;
begin
  Attribs[0] := EGL_RENDERABLE_TYPE;
  Attribs[1] := EGL_OPENGL_BIT;
  Attribs[2] := EGL_SURFACE_TYPE;
  Attribs[3] := 0;
  Attribs[4] := EGL_NONE;
  Result := nil;
  Found := 0;
  if (eglChooseConfig(Display, @Attribs[0], @Result, 1, @Found) = EGL_FALSE) or (Found = 0) then
    Result := nil;
end;

function MakeDesktopContext: EGLContext;
var
  Config: EGLConfig;
  Attribs: array[0..6] of EGLint;
begin
  Result := EGL_NO_CONTEXT;
  if eglBindAPI(EGL_OPENGL_API) = EGL_FALSE then
    raise EPMLUnsupported.Create('eglBindAPI(OpenGL): ' + PMLEGLErrorName(eglGetError()));
  Config := ChooseConfig;
  if Config = nil then
    raise EPMLUnsupported.Create('no EGL config for EGL_OPENGL_BIT');
  Attribs[0] := EGL_CONTEXT_MAJOR_VERSION_KHR;
  Attribs[1] := 2;
  Attribs[2] := EGL_CONTEXT_MINOR_VERSION_KHR;
  Attribs[3] := 1;
  Attribs[4] := EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR;
  Attribs[5] := EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT_KHR;
  Attribs[6] := EGL_NONE;
  Result := eglCreateContext(Display, Config, EGL_NO_CONTEXT, @Attribs[0]);
  if Result = EGL_NO_CONTEXT then
    raise EPMLUnsupported.Create('eglCreateContext: ' + PMLEGLErrorName(eglGetError()));
end;

{ ---- 描いて中央の画素を読む ---- }

var
  GFBO, GRT: GLuint;
  GTextures: array of GLuint;

procedure SetupRenderTarget;
begin
  G.glGenTextures(1, @GRT);
  G.glBindTexture(GL_TEXTURE_2D, GRT);
  G.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  G.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  G.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, RT_SIZE, RT_SIZE, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil);
  G.glGenFramebuffersEXT(1, @GFBO);
  G.glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, GFBO);
  G.glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_2D, GRT, 0);
  if G.glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT) <> GL_FRAMEBUFFER_COMPLETE_EXT then
    raise EPMLUnsupported.Create('the offscreen FBO is not complete');
end;

{ ユニット AUnit に RGBA8 のテクスチャ（AWidth x AHeight）を置く。次の ClearTextures で消える。 }
procedure PutTexture(AUnit: Integer; ATarget: GLenum; AWidth, AHeight: Integer; const APixels: array of Byte);
var
  Tex: GLuint;
begin
  G.glActiveTextureARB(GL_TEXTURE0_ARB + GLenum(AUnit));
  G.glGenTextures(1, @Tex);
  G.glBindTexture(ATarget, Tex);
  G.glTexParameteri(ATarget, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  G.glTexParameteri(ATarget, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  G.glTexParameteri(ATarget, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  G.glTexParameteri(ATarget, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  G.glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  G.glTexImage2D(ATarget, 0, GL_RGBA8, AWidth, AHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, @APixels[0]);
  SetLength(GTextures, Length(GTextures) + 1);
  GTextures[High(GTextures)] := Tex;
end;

procedure ClearTextures;
begin
  if Length(GTextures) > 0 then
    G.glDeleteTextures(Length(GTextures), @GTextures[0]);
  SetLength(GTextures, 0);
  G.glActiveTextureARB(GL_TEXTURE0_ARB);
end;

{ AShader で、色 (AR, AG, AB, AA) とテクスチャ座標 (ATC, ATC) の矩形を全面に描き、画素 (1, 1) を返す }
function DrawPixel(AContext: TPMLGLShaderContext; AShader: TPMLGLShader; AParams: PSingle;
  ATC: Single; AR, AG, AB, AA: Single): TRGBA;
begin
  G.glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, GFBO);
  G.glViewport(0, 0, RT_SIZE, RT_SIZE);
  G.glClearColor(0, 0, 0, 0);
  G.glClear(GL_COLOR_BUFFER_BIT);
  AContext.Select(AShader, AParams);
  G.glTexCoord2f(ATC, ATC);
  G.glColor4f(AR, AG, AB, AA);
  G.glRectf(-1, -1, 1, 1);
  AContext.Select(TPMLGLShader.None, nil);
  FillChar(Result, SizeOf(Result), 0);
  G.glReadPixels(1, 1, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, @Result[0]);
end;

function Near(const AActual: TRGBA; R, G_, B, A: Integer): Boolean;
begin
  Result := (Abs(Integer(AActual[0]) - R) <= TOLERANCE) and (Abs(Integer(AActual[1]) - G_) <= TOLERANCE) and
    (Abs(Integer(AActual[2]) - B) <= TOLERANCE) and (Abs(Integer(AActual[3]) - A) <= TOLERANCE);
end;

function Fmt(const AValue: TRGBA): String;
begin
  Result := Format('(%d,%d,%d,%d)', [AValue[0], AValue[1], AValue[2], AValue[3]]);
end;

procedure CheckPixel(AContext: TPMLGLShaderContext; AShader: TPMLGLShader; AParams: PSingle;
  ATC: Single; const ALabel: String; R, G_, B, A: Integer);
var
  Pixel: TRGBA;
begin
  Pixel := DrawPixel(AContext, AShader, AParams, ATC, 1, 1, 1, 1);
  Check(Near(Pixel, R, G_, B, A), Format('%s: %s（期待 (%d,%d,%d,%d)）', [ALabel, Fmt(Pixel), R, G_, B, A]));
end;

{ ---- 検査の本体 ---- }

function IsPixelArt(AShader: TPMLGLShader): Boolean;
begin
  Result := AShader in [TPMLGLShader.PalettePixelArt, TPMLGLShader.RGBPixelArt, TPMLGLShader.RGBAPixelArt];
end;

function ShaderName(AShader: TPMLGLShader): String;
begin
  case AShader of
    TPMLGLShader.None:            Result := 'None';
    TPMLGLShader.Solid:           Result := 'Solid';
    TPMLGLShader.PaletteNearest:  Result := 'PaletteNearest';
    TPMLGLShader.PaletteLinear:   Result := 'PaletteLinear';
    TPMLGLShader.PalettePixelArt: Result := 'PalettePixelArt';
    TPMLGLShader.RGB:             Result := 'RGB';
    TPMLGLShader.RGBPixelArt:     Result := 'RGBPixelArt';
    TPMLGLShader.RGBA:            Result := 'RGBA';
    TPMLGLShader.RGBAPixelArt:    Result := 'RGBAPixelArt';
    TPMLGLShader.YUV:             Result := 'YUV';
    TPMLGLShader.NV12_RA:         Result := 'NV12_RA';
    TPMLGLShader.NV12_RG:         Result := 'NV12_RG';
    TPMLGLShader.NV21_RA:         Result := 'NV21_RA';
    TPMLGLShader.NV21_RG:         Result := 'NV21_RG';
  end;
end;

{ パラメータの長さ（SDL の GL_SelectShader の分け方）。 }
function ParamLen(AShader: TPMLGLShader): Integer;
begin
  if AShader in [TPMLGLShader.PaletteLinear, TPMLGLShader.PalettePixelArt,
    TPMLGLShader.RGBPixelArt, TPMLGLShader.RGBAPixelArt] then
    Result := 4
  else if Ord(AShader) >= Ord(TPMLGLShader.YUV) then
    Result := 16
  else
    Result := 0;
end;

var
  ParamsBuf: array[0..15] of Single;

{ YUV 系の AParams: R = V、G = U、B = Y になる行列（Yoffset は 0）。並び: Yoffset, 0, Rcoeff, 0, Gcoeff, 0, Bcoeff, 0 }
procedure FillYUVParams;
begin
  FillChar(ParamsBuf, SizeOf(ParamsBuf), 0);
  // Rcoeff = (0, 0, 1)、Gcoeff = (0, 1, 0)、Bcoeff = (1, 0, 0)。yuv = (Y, U, V)
  ParamsBuf[6] := 1;
  ParamsBuf[9] := 1;
  ParamsBuf[12] := 1;
end;

procedure CheckAllSupported(AContext: TPMLGLShaderContext);
var
  S: TPMLGLShader;
begin
  Check(not AContext.Supports(TPMLGLShader.None), 'Supports(None) は False（SDL は program = 0）');
  for S := Succ(TPMLGLShader.None) to High(TPMLGLShader) do
    if AContext.Supports(S) then
      Check(True, 'Supports(' + ShaderName(S) + ')')
    else if IsPixelArt(S) and Optional then
      WriteLn('  [SKIP] Supports(', ShaderName(S), ') が False（#version 130 を受け付けない環境。PAPIMELA_GL_OPTIONAL=1）')
    else
      Check(False, 'Supports(' + ShaderName(S) + ')');
end;

procedure CheckSelectNoError(AContext: TPMLGLShaderContext);
var
  S: TPMLGLShader;
  Err: GLenum;
  P: PSingle;
begin
  FillYUVParams;
  ParamsBuf[0] := 1;
  while G.glGetError() <> GL_NO_ERROR do;
  for S := Low(TPMLGLShader) to High(TPMLGLShader) do
    if (S = TPMLGLShader.None) or AContext.Supports(S) then
    begin
      if ParamLen(S) > 0 then
        P := @ParamsBuf[0]
      else
        P := nil;
      AContext.Select(S, P);
      Err := G.glGetError();
      Check(Err = GL_NO_ERROR, Format('Select(%s) の後の glGetError = %d', [ShaderName(S), Err]));
    end;
  AContext.Select(TPMLGLShader.None, nil);
end;

{ 同じ値の再 Select は uniform を設定し直さず、違う値なら設定し直す }
procedure CheckParamCache(const AExts: String);
var
  Ctx: TPMLGLShaderContext;
  A: array[0..3] of Single;
  B: array[0..15] of Single;
begin
  CountU1f := 0;
  CountU3f := 0;
  CountU4f := 0;
  Ctx := TPMLGLShaderContext.TryCreate(@CountingProc, AExts, G);
  Check(Ctx <> nil, '数える取得関数でも TryCreate できる');
  if Ctx = nil then
    Exit;
  try
    CountU1f := 0;
    CountU3f := 0;
    CountU4f := 0;

    // PaletteLinear: texel_size（4 個）。配列の長さは 4 個ちょうど（長さを超えて読まない）
    A[0] := 0.25; A[1] := 0.5; A[2] := 4; A[3] := 2;
    Ctx.Select(TPMLGLShader.PaletteLinear, @A[0]);
    Check(CountU4f = 1, Format('初回の Select は texel_size を設定する（glUniform4f %d 回）', [CountU4f]));
    Ctx.Select(TPMLGLShader.PaletteLinear, @A[0]);
    Check(CountU4f = 1, Format('同じ値の再 Select は設定し直さない（%d 回）', [CountU4f]));
    A[3] := 3;
    Ctx.Select(TPMLGLShader.PaletteLinear, @A[0]);
    Check(CountU4f = 2, Format('違う値なら設定し直す（%d 回）', [CountU4f]));
    Ctx.Select(TPMLGLShader.PaletteLinear, @A[0]);
    Check(CountU4f = 2, Format('その値でもう一度は設定し直さない（%d 回）', [CountU4f]));
    Ctx.Select(TPMLGLShader.PaletteLinear, nil);
    Check(CountU4f = 2, 'AParams = nil は uniform に触らない');
    Ctx.Select(TPMLGLShader.PaletteLinear, @A[0]);
    Check(CountU4f = 2, 'nil で選んだ後も、値の記憶は残る');

    // YUV: 16 個。Yoffset / Rcoeff / Gcoeff / Bcoeff の 4 回の glUniform3f
    FillChar(B, SizeOf(B), 0);
    B[0] := 0.1;
    Ctx.Select(TPMLGLShader.YUV, @B[0]);
    Check(CountU3f = 4, Format('YUV の初回は glUniform3f を 4 回（%d 回）', [CountU3f]));
    Ctx.Select(TPMLGLShader.YUV, @B[0]);
    Check(CountU3f = 4, Format('YUV の同じ値は設定し直さない（%d 回）', [CountU3f]));
    B[15] := 1;
    Ctx.Select(TPMLGLShader.YUV, @B[0]);
    Check(CountU3f = 8, Format('16 個全部を比べる（最後の 1 個の違いでも設定し直す。%d 回）', [CountU3f]));
    B[0] := 0.2;
    Ctx.Select(TPMLGLShader.YUV, @B[0]);
    Check(CountU3f = 12, Format('先頭の違いでも設定し直す（%d 回）', [CountU3f]));
    // 記憶はシェーダごと: NV12_RA は別
    Ctx.Select(TPMLGLShader.NV12_RA, @B[0]);
    Check(CountU3f = 16, Format('記憶はシェーダごと（NV12_RA の初回は設定する。%d 回）', [CountU3f]));
    Check(CountU1f = 0, 'glUniform1f は呼ばれない');
    Ctx.Select(TPMLGLShader.None, nil);
  finally
    Ctx.Free;
  end;
end;

{ 通常のモード（sampler2D）の画素 }
procedure CheckPixelsPlain(AContext: TPMLGLShaderContext);
var
  Palette: array[0..256 * 4 - 1] of Byte;
  I: Integer;
begin
  // Solid: 頂点の色だけ（0.25, 0.5, 0.75, 1.0 → 64, 128, 191, 255）
  Check(Near(DrawPixel(AContext, TPMLGLShader.Solid, nil, 0.5, 0.25, 0.5, 0.75, 1),
    64, 128, 191, 255), 'Solid: 頂点の色');

  // RGBA / RGB
  PutTexture(0, GL_TEXTURE_2D, 1, 1, [10, 20, 30, 40]);
  CheckPixel(AContext, TPMLGLShader.RGBA, nil, 0.5, 'RGBA: テクスチャの色', 10, 20, 30, 40);
  CheckPixel(AContext, TPMLGLShader.RGB, nil, 0.5, 'RGB: アルファは 1', 10, 20, 30, 255);
  // 頂点の色が掛かる
  Check(Near(DrawPixel(AContext, TPMLGLShader.RGBA, nil, 0.5, 0.5, 1, 0, 1), 5, 20, 0, 40),
    'RGBA: 頂点の色を掛ける');
  ClearTextures;

  // パレット: tex0 = 添字（R = 3）、tex1 = 256x1 のパレット（添字 3 だけ違う色）
  for I := 0 to 255 do
  begin
    Palette[I * 4] := 99;
    Palette[I * 4 + 1] := 99;
    Palette[I * 4 + 2] := 99;
    Palette[I * 4 + 3] := 99;
  end;
  Palette[3 * 4] := 11;
  Palette[3 * 4 + 1] := 22;
  Palette[3 * 4 + 2] := 33;
  Palette[3 * 4 + 3] := 44;
  PutTexture(0, GL_TEXTURE_2D, 1, 1, [3, 0, 0, 255]);
  PutTexture(1, GL_TEXTURE_2D, 256, 1, Palette);
  CheckPixel(AContext, TPMLGLShader.PaletteNearest, nil, 0.5, 'PaletteNearest: tex0 の添字で tex1 を引く', 11, 22, 33, 44);
  ParamsBuf[0] := 1; ParamsBuf[1] := 1; ParamsBuf[2] := 1; ParamsBuf[3] := 1;
  CheckPixel(AContext, TPMLGLShader.PaletteLinear, @ParamsBuf[0], 0.5, 'PaletteLinear', 11, 22, 33, 44);
  if AContext.Supports(TPMLGLShader.PalettePixelArt) then
    CheckPixel(AContext, TPMLGLShader.PalettePixelArt, @ParamsBuf[0], 0.5, 'PalettePixelArt', 11, 22, 33, 44);
  ClearTextures;

  // ピクセルアート（RGB / RGBA）
  PutTexture(0, GL_TEXTURE_2D, 1, 1, [10, 20, 30, 40]);
  if AContext.Supports(TPMLGLShader.RGBAPixelArt) then
    CheckPixel(AContext, TPMLGLShader.RGBAPixelArt, @ParamsBuf[0], 0.5, 'RGBAPixelArt', 10, 20, 30, 40);
  if AContext.Supports(TPMLGLShader.RGBPixelArt) then
    CheckPixel(AContext, TPMLGLShader.RGBPixelArt, @ParamsBuf[0], 0.5, 'RGBPixelArt', 10, 20, 30, 255);
  ClearTextures;

  // YUV: tex0 = Y（R）、tex1 = U、tex2 = V。行列で R = V、G = U、B = Y にする
  FillYUVParams;
  PutTexture(0, GL_TEXTURE_2D, 1, 1, [64, 0, 0, 255]);
  PutTexture(1, GL_TEXTURE_2D, 1, 1, [120, 0, 0, 255]);
  PutTexture(2, GL_TEXTURE_2D, 1, 1, [200, 0, 0, 255]);
  CheckPixel(AContext, TPMLGLShader.YUV, @ParamsBuf[0], 0.5, 'YUV: tex0 = Y、tex1 = U、tex2 = V', 200, 120, 64, 255);
  ClearTextures;

  // NV12 / NV21: tex1 の RGBA = (r, g, 0, a) = (40, 120, 0, 200)。
  //   RA は .ra、RG は .rg、NV21 は反対の並び（.ar / .gr）。(U, V) → (R, G, B) = (V, U, Y)
  PutTexture(0, GL_TEXTURE_2D, 1, 1, [64, 0, 0, 255]);
  PutTexture(1, GL_TEXTURE_2D, 1, 1, [40, 120, 0, 200]);
  CheckPixel(AContext, TPMLGLShader.NV12_RA, @ParamsBuf[0], 0.5, 'NV12_RA: (U, V) = (r, a)', 200, 40, 64, 255);
  CheckPixel(AContext, TPMLGLShader.NV12_RG, @ParamsBuf[0], 0.5, 'NV12_RG: (U, V) = (r, g)', 120, 40, 64, 255);
  CheckPixel(AContext, TPMLGLShader.NV21_RA, @ParamsBuf[0], 0.5, 'NV21_RA: (U, V) = (a, r)', 40, 200, 64, 255);
  CheckPixel(AContext, TPMLGLShader.NV21_RG, @ParamsBuf[0], 0.5, 'NV21_RG: (U, V) = (g, r)', 40, 120, 64, 255);
  ClearTextures;
end;

{ 矩形テクスチャのモードの画素（tex は GL_TEXTURE_RECTANGLE_ARB、座標は画素単位） }
procedure CheckPixelsRect(AContext: TPMLGLShaderContext);
begin
  // RGBA: 通常のソース（sampler2D）のままなら、ユニット 0 の TEXTURE_2D は空で黒になる
  PutTexture(0, GL_TEXTURE_RECTANGLE_ARB, 1, 1, [10, 20, 30, 40]);
  CheckPixel(AContext, TPMLGLShader.RGBA, nil, 0.5, '矩形 RGBA: sampler2DRect で引ける', 10, 20, 30, 40);
  ClearTextures;

  // YUV: 色差の座標は輝度の座標の 0.5 倍（UVCoordScale 0.5）。座標 (1, 1) → 輝度は画素 (1, 1)、色差は画素 (0, 0)
  FillYUVParams;
  PutTexture(0, GL_TEXTURE_RECTANGLE_ARB, 2, 2, [64, 0, 0, 255, 64, 0, 0, 255, 64, 0, 0, 255, 64, 0, 0, 255]);
  PutTexture(1, GL_TEXTURE_RECTANGLE_ARB, 2, 2, [120, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255]);
  PutTexture(2, GL_TEXTURE_RECTANGLE_ARB, 2, 2, [200, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255]);
  CheckPixel(AContext, TPMLGLShader.YUV, @ParamsBuf[0], 1.0, '矩形 YUV: 色差の座標は 0.5 倍', 200, 120, 64, 255);
  ClearTextures;
end;

procedure RunChecks;
var
  Ctx: EGLContext;
  Exts, Fake, Missing: String;
  Shaders: TPMLGLShaderContext;
  Name: String;
begin
  Missing := PMLLoadGLFunctions(@RealProc, G);
  if Missing <> '' then
    raise EPMLUnsupported.Create('libGL lacks core functions: ' + Missing);
  Missing := PMLLoadGLExtFunctions(@RealProc, G, TPMLGLExtGroup.FBO);
  if Missing <> '' then
    raise EPMLUnsupported.Create('libGL lacks FBO functions: ' + Missing);
  Missing := PMLLoadGLExtFunctions(@RealProc, G, TPMLGLExtGroup.Multitexture);
  if Missing <> '' then
    raise EPMLUnsupported.Create('libGL lacks multitexture functions: ' + Missing);

  Ctx := MakeDesktopContext;
  try
    if eglMakeCurrent(Display, EGL_NO_SURFACE, EGL_NO_SURFACE, Ctx) = EGL_FALSE then
      raise EPMLUnsupported.Create('eglMakeCurrent: ' + PMLEGLErrorName(eglGetError()));
    Exts := String(PAnsiChar(G.glGetString(GL_EXTENSIONS_)));
    WriteLn('  GL_RENDERER: ', String(PAnsiChar(G.glGetString($1F01))));
    SetupRenderTarget;

    WriteLn('1. 作る');
    Shaders := TPMLGLShaderContext.TryCreate(@RealProc, Exts, G);
    Check(Shaders <> nil, 'TryCreate が非 nil（実機の拡張の文字列）');
    if Shaders = nil then
      Exit;
    try
      WriteLn('2. Supports');
      CheckAllSupported(Shaders);
      WriteLn('3. Select');
      CheckSelectNoError(Shaders);
      WriteLn('5. 画素（通常のモード）');
      CheckPixelsPlain(Shaders);
    finally
      Shaders.Free;
    end;
    Check(G.glGetError() = GL_NO_ERROR, '破棄の後も glGetError = GL_NO_ERROR');

    WriteLn('4. uniform の記憶');
    CheckParamCache(Exts);

    WriteLn('6. 矩形テクスチャのモード（拡張の文字列を偽る）');
    Fake := BASE_EXTS + ' GL_ARB_texture_rectangle';
    Shaders := TPMLGLShaderContext.TryCreate(@RealProc, Fake, G);
    Check(Shaders <> nil, '矩形のモードで TryCreate が非 nil');
    if Shaders <> nil then
    try
      CheckAllSupported(Shaders);
      CheckPixelsRect(Shaders);
    finally
      Shaders.Free;
    end;

    WriteLn('7. 拡張が欠ける');
    for Name in BaseExtNames do
    begin
      Fake := StringReplace(BASE_EXTS, Name, '', []);
      Shaders := TPMLGLShaderContext.TryCreate(@RealProc, Fake, G);
      Check(Shaders = nil, Name + ' なしで nil');
      Shaders.Free;
    end;
    Fake := StringReplace(BASE_EXTS, 'GL_ARB_fragment_shader', 'GL_ARB_fragment_shader_x', []);
    Shaders := TPMLGLShaderContext.TryCreate(@RealProc, Fake, G);
    Check(Shaders = nil, '語の完全一致（GL_ARB_fragment_shader_x は GL_ARB_fragment_shader ではない）');
    Shaders.Free;
    Shaders := TPMLGLShaderContext.TryCreate(@RealProc, '', G);
    Check(Shaders = nil, '拡張の文字列が空で nil');
    Shaders.Free;

    WriteLn('8. 関数が欠ける');
    Shaders := TPMLGLShaderContext.TryCreate(@MissingU4Proc, Exts, G);
    Check(Shaders = nil, 'glUniform4fARB だけ無くても nil（SDL は検査から漏らしている）');
    Shaders.Free;
  finally
    eglMakeCurrent(Display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(Display, Ctx);
  end;
end;

var
  SetupError: String;
begin
  SetupError := '';
  try
    if not PMLEGLLoad then
      raise EPMLUnsupported.Create('libEGL could not be loaded');
    Display := PMLAcquireSurfacelessDisplay('test_render_gl_shaders');
    GLib := TPMLDynLib.Create(['libGL.so.1', 'libOpenGL.so.0', 'libGL.so']);
    WriteLn('=== test_render_gl_shaders ===');
    RunChecks;
  except
    on E: EPMLUnsupported do
      SetupError := E.Message;
  end;
  if SetupError <> '' then
  begin
    if Optional then
      WriteLn('  [SKIP] デスクトップ GL が使えない: ', SetupError)
    else
      Check(False, 'デスクトップ GL が使える（' + SetupError + '）');
  end;
  if Display <> nil then
    PMLReleaseSurfacelessDisplay;
  GLib.Free;
  PMLEGLUnload;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 全部 OK ===')
  else
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
  if Failures <> 0 then
    Halt(1);
end.
