{
  PaPiMeLa.Render.GL — デスクトップ OpenGL（1.x〜2.1 の互換プロファイル）で描くレンダラドライバ

  Origin : ported from SDL (src/render/opengl/SDL_render_gl.c, src/render/opengl/SDL_shaders_gl.c)
           Scope: GL_CreateRenderer の初期化（バージョンの読み取り、NPOT・矩形テクスチャ・マルチテクスチャ・
           BGRA・FBO の判定、シェーダの有無）、convert_format（形式から GL の形式）、SetTextureScaleMode、
           パレット（256x1 のテクスチャ）、GL_CreateTexture / UpdateTexture / UpdateTextureYUV / UpdateTextureNV /
           Lock / Unlock / DestroyTexture（YV12・IYUV・I444・NV12・NV21・INDEX8・2 の冪乗への切り上げ・矩形テクスチャ）、
           サイズごとの FBO の一覧（GL_GetFBO）と GL_SetRenderTarget、SetDrawState / SetCopyState（固定機能の行列・
           ビューポート・シザー・合成・シェーダの選び方・クライアント配列）、GL_RunCommandQueue、
           GL_RenderReadPixels、GL_RenderPresent、GL_SetVSync。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.3、§11 #44

  WHAT:
    TPMLRenderDriver のデスクトップ GL 版。ウィンドウ（EGL の面。GL 2.1 の互換プロファイルのコンテキスト）か、
    窓の無い GL（Mesa の surfaceless。検査用）に描く。固定機能のパイプラインに ARB のシェーダ
    （PaPiMeLa.Render.GL.Shaders）を足して描く。

  WHY:
    SDL は GL 2.1 の互換プロファイルを使い、コアプロファイルを要求しない（SDL_render_gl.c の
    RENDERER_CONTEXT_MAJOR / MINOR）。papimela も同じにする（実機 V3D では GL 3.1 まで、コア 3.3 は作れない。
    スパイク 5）。

  RESOLVED:
    - 頂点はすべて TPMLVertex（32 バイト。位置・色・テクスチャ座標）で積み、実行の頭でクライアント配列の
      ポインタを 1 度だけ設定する（SDL は点と線は位置だけ、図形は位置と色と座標を別の並びで積む）。
      色は頂点ごとに持つので、現在の色（glColor4f）は使わない
    - 描画先がウィンドウのとき、原点は左下なので上下を反転する（glViewport と glOrtho）。FBO（オフスクリーンと
      描画先のテクスチャ）は反転しない（メモリの 1 行目が画像の上）。読み戻しの向きは「1 行目が上」に揃える
    - 描画先のテクスチャはサイズごとの FBO を共有し、描画先を切り替えるたびに色の付け先を付け直す
      （SDL の GL_GetFBO / GL_SetRenderTarget と同じ）。BGRA32 / BGRX32 は GL_BGRA で持つので、GLES2 のような
      R と B の入れ替えは要らない
    - どの操作も先頭でこのドライバのコンテキストを現在にする。アプリが別のコンテキストを現在にしていても、
      描画と破棄が他人の GL を壊さない
    - 点と線の座標は整数に切り捨ててから +0.5 する（ソフトウェアのドライバと同じ画素を塗る）。線は線分ごとに独立の
      2 頂点（GL_LINES）にする。キューが同じ状態の DrawLines を結合するので、折れ線の境目が分からなくなるため
    - 画素の読み出しと書き込みで、行の長さ（GL_PACK_ROW_LENGTH / GL_UNPACK_ROW_LENGTH）を触ったら元に戻す。
      SDL は戻さず、アプリ自身の GL に影響が残る（疑い）
    - 作った直後のテクスチャは 0（透明な黒）で埋める。SDL は未定義のまま（画素が NULL）
    - シェーダが使えない GL では、SDL と同じに RGBA32 / BGRA32 だけを持つ（INDEX8・YUV・RGBX は持てない）。
      FBO が無い GL では、SDL と同じにドライバを作れない

  NOT RESOLVED:
    - GL_ARB_debug_output は使わない（SDL は debug のコンテキストのときだけ使う。papimela の既定は debug 無し）
    - 外部のテクスチャの取り込み、macOS の UYVY、SDL のヒント（SDL_RENDER_OPENGL_NV12_RG_SHADER、
      GL_EXT_bgra、GL_ARB_texture_non_power_of_two）は持たない
    - コンテキスト喪失への対応（SDL もデバイスのリセットを出さない）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Render.GL;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.YUV,
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Platform.EGL,
  PaPiMeLa.Platform.EGL.Surfaceless,
  PaPiMeLa.Platform.GL,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Render,
  PaPiMeLa.Render.GL.Shaders;

type
  { テクスチャの種類を、GL が持っていても強制する（検査用）。SDL は NPOT が使えれば NPOT、無ければ矩形、
    それも無ければ 2 の冪乗に切り上げる。この 3 通りのうち、実機では NPOT しか通らないので、
    矩形と 2 の冪乗の道を検査が通れるようにする。 }
  TPMLGLTextureMode = (Auto, Rectangle, PowerOfTwo);

  TPMLGLFBO = record
    Width, Height: Integer;
    Id: GLuint;
  end;

  { テクスチャ 1 枚（TPMLTexture.DriverData）。SDL の GL_TextureData。 }
  TPMLGLTexture = class
  public
    Id, IdU, IdV: GLuint;
    // テクスチャ座標に掛ける値（SDL の texw / texh）。NPOT は 1、矩形は大きさ、2 の冪乗は 大きさ / 切り上げた大きさ
    TexW, TexH: Single;
    // GL のデータ形式（GL_RGBA / GL_BGRA / GL_LUMINANCE）
    DataFormat: GLenum;
    PixelFormat: TPMLPixelFormat;
    Width, Height: Integer;
    Shader: TPMLGLShader;
    // texel_size（1/幅、1/高さ、幅、高さ）と、YUV の変換の 16 個（Yoffset・Rcoeff・Gcoeff・Bcoeff を 4 個ずつ）
    TexelSize: array[0..3] of Single;
    YUVParams: array[0..15] of Single;
    HasAlpha, Indexed, Planar, NV: Boolean;
    // 輝度の面を偶数の大きさに切り上げて持っているか（NPOT で幅か高さが奇数の YUV。UpdateLuma の PORT-NOTE）
    PadX, PadY: Boolean;
    YCbCr: TPMLYCbCrType;
    // 今 GL に設定してある補間（SDL の texture_scale_mode）
    Filter: TPMLScaleMode;
    // 描画先のとき、サイズごとの FBO の一覧の添字（-1 = 描画先でない）
    FBOIndex: Integer;
    PixelData: TBytes;
    PixelPitch: Integer;
  end;

  { パレットの写し（TPMLTexturePalette.DriverData）。256x1 の RGBA テクスチャ。 }
  TPMLGLPalette = class
  public
    Id: GLuint;
  end;

  TPMLGLRenderDriver = class(TPMLRenderDriver)
  strict private
    FGL        : TPMLGLFunctions;
    FWindow    : TPMLWindow;
    FContext   : TPMLGLContext;
    // オフスクリーン（EGL の surfaceless）
    FEGLLoaded : Boolean;
    FDisplayHeld: Boolean;
    FDisplay   : EGLDisplay;
    FEGLContext: EGLContext;
    FDesktopLib: TPMLDynLib;
    FWidth     : Integer;
    FHeight    : Integer;
    FFBO       : GLuint;
    FTargetTex : GLuint;

    FExtensions: String;
    FShaders   : TPMLGLShaderContext;
    FTexType   : GLenum;
    FNPOT, FRect, FMultitexture, FBGRA, FPixelArt: Boolean;
    FNumTextureUnits: GLint;
    FMaxTexture: Integer;
    FFBOs      : array of TPMLGLFBO;
    FLastNonFatalError: String;

    // 実行中の状態。RunCommandQueue の頭で作り直す。
    FDrawableW, FDrawableH: Integer;
    FViewport  : TPMLRect;
    FClip      : TPMLRect;
    FClipOn    : Boolean;
    FViewportDirty, FClipDirty, FScissorOn: Boolean;
    FBlendValid: Boolean;
    FCurBlend  : TPMLBlendMode;
    FShaderValid: Boolean;
    FCurShader : TPMLGLShader;
    FCurParams : PSingle;
    FTexturing : Boolean;
    FTexturingValid: Boolean;
    FTexCoordArray: Boolean;
    FBoundTexture, FBoundUnit1, FBoundUnit2: GLuint;
    FVertexBuf : TPMLVertices;
    FTarget    : TPMLGLTexture;

    procedure LoadFunctions;
    procedure CreateSurfacelessContext;
    procedure CreateTargetFBO;
    procedure CreateResources;
    procedure ReleaseResources;
    procedure EnsureCurrent;
    procedure ReadOutputSize(out AWidth, AHeight: Integer);
    procedure ReadDrawableSize(out AWidth, AHeight: Integer);
    function  FlipsOutput: Boolean;
    procedure BindDrawFramebuffer;
    procedure CheckGLErrors(const AWhere: String);
    function  GetFBO(AWidth, AHeight: Integer): Integer;
    function  Supports(AShader: TPMLGLShader): Boolean;
    procedure SetScaleMode(AFormatIndexed: Boolean; AMode: TPMLScaleMode);
    procedure UploadPlane(AId: GLuint; AX, AY, AWidth, AHeight: Integer; AGLFormat: GLenum;
      APixels: Pointer; ARowLength: Integer);
    procedure CreatePlane(AId: GLuint; AWidth, AHeight: Integer; AInternal: GLint;
      AGLFormat: GLenum; ABytesPerTexel: Integer);
    procedure BindUnit(AUnit: GLenum; AId: GLuint);
    procedure ReplicateLumaEdges(AData: TPMLGLTexture; const ARect: TPMLRect; APixels: Pointer; APitch: Integer);
    procedure ActivateUnit(AUnit: GLenum);
    procedure BeginRun(AQueue: TPMLRenderQueue);
    procedure EndRun;
    procedure ApplyViewport;
    procedure ApplyScissor;
    procedure ApplyBlend(ABlend: TPMLBlendMode);
    procedure SetDrawState(const ACmd: TPMLRenderCommand; AShader: TPMLGLShader; AParams: PSingle);
    procedure ExecClear(const ACmd: TPMLRenderCommand);
    procedure ExecDraw(AMode: GLenum; const ACmd: TPMLRenderCommand);
  public
    { ウィンドウに描く。ウィンドウは TPMLWindowOptions.OpenGL で作ってあること。 }
    constructor CreateForWindow(AWindow: TPMLWindow);
    { 窓の無い GL（Mesa の surfaceless）で、AWidth x AHeight のオフスクリーンに描く。検査用。
      使えない環境では EPMLUnsupported。 }
    constructor CreateOffscreen(AWidth, AHeight: Integer);
    destructor Destroy; override;

    function  Name: String; override;                 // 'opengl'
    function  GetOutputSize(out AWidth, AHeight: Integer): Boolean; override;
    function  SupportsBlendMode(AMode: TPMLBlendMode): Boolean; override;
    function  SupportsTextureFormat(AFormat: TPMLPixelFormat): Boolean; override;
    function  CreateTexture(ATexture: TPMLTexture): Boolean; override;
    function  UpdateTexture(ATexture: TPMLTexture; const ARect: TPMLRect;
      APixels: Pointer; APitch: Integer): Boolean; override;
    function  UpdateTextureYUV(ATexture: TPMLTexture; const ARect: TPMLRect;
      AY: Pointer; AYPitch: Integer; AU: Pointer; AUPitch: Integer;
      AV: Pointer; AVPitch: Integer): Boolean; override;
    function  UpdateTextureNV(ATexture: TPMLTexture; const ARect: TPMLRect;
      AY: Pointer; AYPitch: Integer; AUV: Pointer; AUVPitch: Integer): Boolean; override;
    function  LockTexture(ATexture: TPMLTexture; const ARect: TPMLRect;
      out APixels: Pointer; out APitch: Integer): Boolean; override;
    procedure UnlockTexture(ATexture: TPMLTexture); override;
    procedure DestroyTexture(ATexture: TPMLTexture); override;
    function  CreatePalette(APalette: TPMLTexturePalette): Boolean; override;
    function  UpdatePalette(APalette: TPMLTexturePalette;
      const AColors: array of TPMLColor): Boolean; override;
    procedure DestroyPalette(APalette: TPMLTexturePalette); override;
    procedure ChangeTexturePalette(ATexture: TPMLTexture); override;
    function  SupportsRenderTargets: Boolean; override;
    function  SetRenderTarget(ATexture: TPMLTexture): Boolean; override;
    procedure QueueGeometry(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const AVertices: array of TPMLVertex); override;
    procedure QueueDrawPoints(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const APoints: array of TPMLFPoint); override;
    procedure QueueDrawLines(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const APoints: array of TPMLFPoint); override;
    procedure RunCommandQueue(AQueue: TPMLRenderQueue); override;
    { 描画先の画素を読む。上下は画面と同じ向き（1 行目が上）に揃えて返す。 }
    function  ReadPixels(const ARect: TPMLRect): TPMLSurface; override;
    procedure Present; override;
    function  SetVSync(AInterval: Integer): Boolean; override;

    // 検査用: 作った後に分かる、このドライバが選んだテクスチャの種類と、シェーダが使えるか
    function  TextureMode: TPMLGLTextureMode;
    function  ShadersEnabled: Boolean;
    function  PixelArtSupported: Boolean;
    // 検査用: GL の整数の状態を読む（GL_UNPACK_ROW_LENGTH など。コンテキストを現在にして読む）
    function  QueryInteger(AName: GLenum): GLint;
  end;

var
  { 検査用。次に作るドライバのテクスチャの種類を強制する（既定は Auto）。作ったドライバには効き続ける。 }
  PMLGLRenderTextureMode: TPMLGLTextureMode = TPMLGLTextureMode.Auto;
  { 検査用。True の間に作るドライバは、GL がシェーダを持っていても使わない（SDL のシェーダが使えない GL の道）。 }
  PMLGLRenderDisableShaders: Boolean = False;
  { 検査用。True の間、ウィンドウへ描くドライバの作成が EPMLUnsupported で失敗する（自動選択のフォールバックの検査）。 }
  PMLGLRenderFailCreate: Boolean = False;

implementation

uses
  Math;

const
  // 線分の終点を向きに沿って延ばす長さ（画素）。QueueDrawLines を参照。
  LINE_EXTEND = 0.75;

  // 最近傍の標本で、画素の中心がテクセルの境目に来るとき、上のテクセルを選ぶ向きに寄せる量（テクセル）。
  // ソフトウェアのラスタライザは Floor(u * 幅 + 1e-4) で境目を上のテクセルに寄せる（Render.GLES2 の頂点シェーダの
  // 1/10000 テクセルの補正と同じ。SDL の GL にはこの補正が無い）
  TIE_BIAS = 0.0001;

var
  // PMLLoadGLFunctions に渡す取得関数は C の関数ポインタ（cdecl）で、文脈を持てない。
  // 読み込みの間だけ、対象のコンテキスト（ウィンドウ）か libGL（オフスクリーン）をここに置く。
  GLoaderContext: TPMLGLContext = nil;
  GLoaderLib: TPMLDynLib = nil;

function LoaderProc(AName: PAnsiChar): Pointer; cdecl;
begin
  if GLoaderContext <> nil then
    Result := GLoaderContext.GetProcAddress(String(AName))
  else if GLoaderLib <> nil then
    Result := GLoaderLib.TryResolve(String(AName))
  else
    Result := nil;
end;

function MakeVertex(AX, AY: Single; const AColor: TPMLFColor): TPMLVertex; inline;
begin
  Result.Position.X := AX;
  Result.Position.Y := AY;
  Result.Color := AColor;
  Result.TexCoord.X := 0;
  Result.TexCoord.Y := 0;
end;

function IsPlanarYUVFormat(AFormat: TPMLPixelFormat): Boolean; inline;
begin
  Result := (AFormat = PML_PIXELFORMAT_YV12) or (AFormat = PML_PIXELFORMAT_IYUV)
    or (AFormat = PML_PIXELFORMAT_I444);
end;

function IsNVFormat(AFormat: TPMLPixelFormat): Boolean; inline;
begin
  Result := (AFormat = PML_PIXELFORMAT_NV12) or (AFormat = PML_PIXELFORMAT_NV21);
end;

{ SDL の convert_format。持てない形式なら False。BGRA32 などはバイト並びの名前なので、エンディアンに依らず正しい。 }
function ConvertFormat(AFormat: TPMLPixelFormat; out AInternal: GLint; out ADataFormat: GLenum;
  out AHasAlpha: Boolean): Boolean;
begin
  Result := True;
  AInternal := GL_RGBA8;
  AHasAlpha := (AFormat = PML_PIXELFORMAT_BGRA32) or (AFormat = PML_PIXELFORMAT_RGBA32);
  if (AFormat = PML_PIXELFORMAT_BGRA32) or (AFormat = PML_PIXELFORMAT_BGRX32) then
    ADataFormat := GL_BGRA
  else if (AFormat = PML_PIXELFORMAT_RGBA32) or (AFormat = PML_PIXELFORMAT_RGBX32) then
    ADataFormat := GL_RGBA
  else if (AFormat = PML_PIXELFORMAT_INDEX8) or IsPlanarYUVFormat(AFormat) or IsNVFormat(AFormat) then
  begin
    AInternal := GL_LUMINANCE;
    ADataFormat := GL_LUMINANCE;
    AHasAlpha := False;
  end
  else
    Result := False;
end;

{ 形式の主な平面（YUV は Y）の 1 画素のバイト数（INDEX8 と YUV は 1、ほかは RGBA の 4）。 }
function BytesPerTexel(AFormat: TPMLPixelFormat): Integer; inline;
begin
  if (AFormat = PML_PIXELFORMAT_INDEX8) or IsPlanarYUVFormat(AFormat) or IsNVFormat(AFormat) then
    Result := 1
  else
    Result := 4;
end;

function TextureData(ATexture: TPMLTexture): TPMLGLTexture; inline;
begin
  if (ATexture = nil) or not (ATexture.DriverData is TPMLGLTexture) then
    Result := nil
  else
    Result := TPMLGLTexture(ATexture.DriverData);
end;

{ 空白区切りの拡張名の一覧から、語 AWord を除く。 }
function StripExtension(const AList, AWord: String): String;
var
  P: Integer;
begin
  Result := ' ' + AList + ' ';
  repeat
    P := Pos(' ' + AWord + ' ', Result);
    if P > 0 then
      Delete(Result, P, Length(AWord) + 1);
  until P = 0;
  Result := Trim(Result);
end;

function PowerOfTwo(AValue: Integer): Integer;
begin
  Result := 1;
  while Result < AValue do
    Result := Result shl 1;
end;

const
  { YUV → RGB の係数。SDL_pixels.c の mat_BT601_Full_8bit などの値のまま。1 種類 12 個: オフセット(Y, U, V)、
    R の係数、G の係数、B の係数。並びは TPMLYCbCrType と同じ。BT.2020 の全範囲は 10 ビット用の行列を
    SDL が 8 ビットにも使うので、ここも同じ値（Render.GLES2 の YUVMatrix と同じ表）。 }
  YUVMatrix: array[TPMLYCbCrType] of array[0..11] of Single = (
    (0.0, -0.501960814, -0.501960814,
     1.0000, 0.0000, 1.4075,
     1.0000, -0.3455, -0.7169,
     1.0000, 1.7790, 0.0000),
    (-0.0627451017, -0.501960814, -0.501960814,
     1.1644, 0.0000, 1.5960,
     1.1644, -0.3918, -0.8130,
     1.1644, 2.0172, 0.0000),
    (0.0, -0.501960814, -0.501960814,
     1.0000, 0.0000, 1.5810,
     1.0000, -0.1881, -0.4700,
     1.0000, 1.8629, 0.0000),
    (-0.0627451017, -0.501960814, -0.501960814,
     1.1644, 0.0000, 1.7927,
     1.1644, -0.2132, -0.5329,
     1.1644, 2.1124, 0.0000),
    (0.0, -0.500488759, -0.500488759,
     1.0000, 0.0000, 1.4760,
     1.0000, -0.1647, -0.5719,
     1.0000, 1.8832, 0.0000));

{ ---- 作成と破棄 ---- }

constructor TPMLGLRenderDriver.CreateForWindow(AWindow: TPMLWindow);
var
  Attrs: TPMLGLAttributes;
begin
  inherited Create(nil, nil);
  FillChar(FGL, SizeOf(FGL), 0);
  if PMLGLRenderFailCreate then
    raise EPMLUnsupported.Create('the OpenGL render driver was told to fail (test hook)');
  if AWindow = nil then
    raise EPMLArgument.Create('the OpenGL render driver needs a window');
  if not (TPMLWindowFlag.OpenGL in AWindow.Flags) then
    raise EPMLUnsupported.Create(
      'the OpenGL render driver needs a window created with TPMLWindowOptions.OpenGL');
  FWindow := AWindow;
  // SDL の RENDERER_CONTEXT_MAJOR / MINOR と同じ GL 2.1、互換プロファイル
  Attrs := TPMLGLAttributes.Default;
  Attrs.Profile := TPMLGLProfile.Compatibility;
  Attrs.MajorVersion := 2;
  Attrs.MinorVersion := 1;
  FContext := AWindow.CreateGLContext(Attrs);
  LoadFunctions;
  CreateResources;
end;

constructor TPMLGLRenderDriver.CreateOffscreen(AWidth, AHeight: Integer);
begin
  inherited Create(nil, nil);
  FillChar(FGL, SizeOf(FGL), 0);
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EPMLArgument.CreateFmt('the offscreen size must be positive (%d x %d)',
      [AWidth, AHeight]);
  FWidth := AWidth;
  FHeight := AHeight;
  FDisplay := EGL_NO_DISPLAY;
  FEGLContext := EGL_NO_CONTEXT;
  CreateSurfacelessContext;
  LoadFunctions;
  CreateResources;
  CreateTargetFBO;
end;

destructor TPMLGLRenderDriver.Destroy;
begin
  // コンストラクタが途中で例外を出しても呼ばれるので、作った分だけ畳む。
  try
    if Assigned(FGL.glDeleteTextures) and ((FContext <> nil) or (FEGLContext <> nil)) then
    begin
      EnsureCurrent;
      ReleaseResources;
    end;
  except
    on E: EPMLError do
      FLastNonFatalError := 'GL cleanup failed: ' + E.Message;
  end;
  FreeAndNil(FShaders);
  if FContext <> nil then
    FreeAndNil(FContext)
  else if FEGLLoaded then
  begin
    if FDisplayHeld then
    begin
      // 現在のコンテキストが自分のときだけ外す（アプリの別のコンテキストは触らない）。
      if (FEGLContext <> EGL_NO_CONTEXT) and (eglGetCurrentContext() = FEGLContext) then
        eglMakeCurrent(FDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
      if FEGLContext <> EGL_NO_CONTEXT then
        eglDestroyContext(FDisplay, FEGLContext);
      PMLReleaseSurfacelessDisplay;
    end;
    PMLEGLUnload;
  end;
  FreeAndNil(FDesktopLib);
  FContext := nil;
  FEGLContext := EGL_NO_CONTEXT;
  FDisplay := EGL_NO_DISPLAY;
  FEGLLoaded := False;
  FDisplayHeld := False;
  inherited Destroy;
end;

procedure TPMLGLRenderDriver.LoadFunctions;
var
  Missing: String;
begin
  GLoaderContext := FContext;
  GLoaderLib := FDesktopLib;
  try
    Missing := PMLLoadGLFunctions(@LoaderProc, FGL);
  finally
    GLoaderContext := nil;
    GLoaderLib := nil;
  end;
  if Missing <> '' then
    raise EPMLUnsupported.Create('the GL implementation lacks functions: ' + Missing);
end;

{ Mesa の surfaceless でデスクトップ GL（互換プロファイル 2.1）のコンテキストを作り、現在にする。

  WHAT:
    EGL_MESA_platform_surfaceless のディスプレイを借り、面を持たない（EGL_NO_SURFACE）コンテキストを作る。
    描く先は後で作る FBO。関数は libGL の dlsym で引く（eglGetProcAddress は存在しない名前にも非 nil を返す）。 }
procedure TPMLGLRenderDriver.CreateSurfacelessContext;
var
  Config: EGLConfig;
  Found, Err: EGLint;
  ConfigAttribs: array[0..4] of EGLint;
  ContextAttribs: array[0..6] of EGLint;
begin
  if not PMLEGLLoad then
    raise EPMLUnsupported.Create('offscreen GL: libEGL could not be loaded');
  FEGLLoaded := True;
  try
    FDesktopLib := TPMLDynLib.Create(['libGL.so.1', 'libOpenGL.so.0', 'libGL.so']);
  except
    on E: EPMLError do
      raise EPMLUnsupported.Create('offscreen GL: libGL could not be loaded (' + E.Message + ')');
  end;

  FDisplay := PMLAcquireSurfacelessDisplay('offscreen GL');
  FDisplayHeld := True;

  if eglBindAPI(EGL_OPENGL_API) = EGL_FALSE then
  begin
    Err := eglGetError();
    raise EPMLUnsupported.CreateFmt('offscreen GL: eglBindAPI(OpenGL) failed (%s)',
      [PMLEGLErrorName(Err)]);
  end;

  ConfigAttribs[0] := EGL_RENDERABLE_TYPE;
  ConfigAttribs[1] := EGL_OPENGL_BIT;
  ConfigAttribs[2] := EGL_SURFACE_TYPE;
  ConfigAttribs[3] := 0;
  ConfigAttribs[4] := EGL_NONE;
  Config := nil;
  Found := 0;
  if (eglChooseConfig(FDisplay, @ConfigAttribs[0], @Config, 1, @Found) = EGL_FALSE)
    or (Found = 0) then
  begin
    Err := eglGetError();
    raise EPMLUnsupported.CreateFmt('offscreen GL: no EGL config for OpenGL (found %d, %s)',
      [Found, PMLEGLErrorName(Err)]);
  end;

  ContextAttribs[0] := EGL_CONTEXT_MAJOR_VERSION_KHR;
  ContextAttribs[1] := 2;
  ContextAttribs[2] := EGL_CONTEXT_MINOR_VERSION_KHR;
  ContextAttribs[3] := 1;
  ContextAttribs[4] := EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR;
  ContextAttribs[5] := EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT_KHR;
  ContextAttribs[6] := EGL_NONE;
  FEGLContext := eglCreateContext(FDisplay, Config, EGL_NO_CONTEXT, @ContextAttribs[0]);
  if FEGLContext = EGL_NO_CONTEXT then
  begin
    Err := eglGetError();
    raise EPMLUnsupported.CreateFmt('offscreen GL: eglCreateContext failed (%s)',
      [PMLEGLErrorName(Err)]);
  end;

  if eglMakeCurrent(FDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, FEGLContext) = EGL_FALSE then
  begin
    Err := eglGetError();
    raise EPMLUnsupported.CreateFmt('offscreen GL: eglMakeCurrent without a surface failed (%s)',
      [PMLEGLErrorName(Err)]);
  end;
end;

{ SDL の GL_CreateRenderer の、バージョンと拡張の判定からシェーダの用意まで。 }
procedure TPMLGLRenderDriver.CreateResources;
var
  Ver: String;
  P, Major, Minor, Value: Integer;
  Missing: String;
  Units: GLint;
  ShaderExts: String;
begin
  GLoaderContext := FContext;
  GLoaderLib := FDesktopLib;
  try
    FExtensions := String(PAnsiChar(FGL.glGetString(GL_EXTENSIONS)));
    Ver := Copy(String(PAnsiChar(FGL.glGetString(GL_VERSION))), 1, 15);
    Major := 0;
    Minor := 0;
    P := Pos('.', Ver);
    if P > 0 then
    begin
      Minor := StrToIntDef(Copy(Ver, P + 1, MaxInt), 0);
      Major := StrToIntDef(Copy(Ver, 1, P - 1), 0);
    end;

    // テクスチャの種類（SDL: NPOT があれば NPOT、無ければ矩形、それも無ければ 2 の冪乗）
    FTexType := GL_TEXTURE_2D;
    FNPOT := (Major >= 2) or PMLEGLHasExtension(FExtensions, 'GL_ARB_texture_non_power_of_two');
    case PMLGLRenderTextureMode of
      TPMLGLTextureMode.Rectangle, TPMLGLTextureMode.PowerOfTwo:
        FNPOT := False;
    end;
    if FNPOT then
      FGL.glGetIntegerv(GL_MAX_TEXTURE_SIZE, @Value)
    else if (PMLGLRenderTextureMode <> TPMLGLTextureMode.PowerOfTwo)
      and (PMLEGLHasExtension(FExtensions, 'GL_ARB_texture_rectangle')
        or PMLEGLHasExtension(FExtensions, 'GL_EXT_texture_rectangle')) then
    begin
      FRect := True;
      FTexType := GL_TEXTURE_RECTANGLE_ARB;
      FGL.glGetIntegerv(GL_MAX_RECTANGLE_TEXTURE_SIZE_ARB, @Value);
    end
    else
      FGL.glGetIntegerv(GL_MAX_TEXTURE_SIZE, @Value);
    FMaxTexture := Value;

    // マルチテクスチャ
    if PMLEGLHasExtension(FExtensions, 'GL_ARB_multitexture')
      and (PMLLoadGLExtFunctions(@LoaderProc, FGL, TPMLGLExtGroup.Multitexture) = '') then
    begin
      FMultitexture := True;
      Units := 0;
      FGL.glGetIntegerv(GL_MAX_TEXTURE_UNITS_ARB, @Units);
      FNumTextureUnits := Units;
    end;

    // BGRA（GL 1.2 以上か拡張）
    FBGRA := (Major > 1) or ((Major = 1) and (Minor >= 2)) or PMLEGLHasExtension(FExtensions, 'GL_EXT_bgra');

    // シェーダ（使えなければ nil。固定機能だけで描く）
    // シェーダの文脈は、テクスチャの種類を拡張の文字列から決める。強制した種類（検査用）と食い違わないよう、
    // 強制のときは該当する拡張を文字列から外して渡す
    ShaderExts := FExtensions;
    if PMLGLRenderTextureMode <> TPMLGLTextureMode.Auto then
      ShaderExts := StripExtension(ShaderExts, 'GL_ARB_texture_non_power_of_two');
    if PMLGLRenderTextureMode = TPMLGLTextureMode.PowerOfTwo then
    begin
      ShaderExts := StripExtension(ShaderExts, 'GL_ARB_texture_rectangle');
      ShaderExts := StripExtension(ShaderExts, 'GL_EXT_texture_rectangle');
    end;
    if not PMLGLRenderDisableShaders then
      FShaders := TPMLGLShaderContext.TryCreate(@LoaderProc, ShaderExts, FGL);
    // PORT-NOTE(bug): SDL のピクセルアートのシェーダは、座標が正規化されている前提で texel_size を掛ける。矩形（画素の座標）と
    // 2 の冪乗への切り上げ（texw で縮めた座標）では合わないので、NPOT のときだけ使う（そうでなければ PixelArt は Nearest と同じ）
    FPixelArt := FNPOT and Supports(TPMLGLShader.RGBPixelArt) and Supports(TPMLGLShader.RGBAPixelArt);

    // 描画先のテクスチャ（FBO）が無ければ、SDL はレンダラを作らない
    if PMLEGLHasExtension(FExtensions, 'GL_EXT_framebuffer_object') then
      Missing := PMLLoadGLExtFunctions(@LoaderProc, FGL, TPMLGLExtGroup.FBO)
    else
      Missing := 'GL_EXT_framebuffer_object';
    if Missing <> '' then
      raise EPMLUnsupported.Create('can''t create render targets, GL_EXT_framebuffer_object is not available (' + Missing + ')');
  finally
    GLoaderContext := nil;
    GLoaderLib := nil;
  end;

  if (Major >= 3) or PMLEGLHasExtension(FExtensions, 'GL_EXT_framebuffer_sRGB')
    or PMLEGLHasExtension(FExtensions, 'GL_ARB_framebuffer_sRGB') then
    FGL.glDisable(GL_FRAMEBUFFER_SRGB);

  // 描くための固定の状態
  FGL.glMatrixMode(GL_MODELVIEW);
  FGL.glLoadIdentity();
  FGL.glDisable(GL_DEPTH_TEST);
  FGL.glDisable(GL_CULL_FACE);
  FGL.glDisable(GL_SCISSOR_TEST);
  FGL.glDisable(FTexType);
  FGL.glClearColor(1.0, 1.0, 1.0, 1.0);
  FGL.glColor4f(1.0, 1.0, 1.0, 1.0);
  FTarget := nil;
end;

procedure TPMLGLRenderDriver.ReleaseResources;
var
  I: Integer;
begin
  FGL.glGetError();
  for I := 0 to High(FFBOs) do
    FGL.glDeleteFramebuffersEXT(1, @FFBOs[I].Id);
  FFBOs := nil;
  if FFBO <> 0 then
    FGL.glDeleteFramebuffersEXT(1, @FFBO);
  if FTargetTex <> 0 then
    FGL.glDeleteTextures(1, @FTargetTex);
  FFBO := 0;
  FTargetTex := 0;
  FGL.glGetError();
end;

{ オフスクリーンの描画先。RGBA8 のテクスチャを付けた FBO。 }
procedure TPMLGLRenderDriver.CreateTargetFBO;
var
  Status: GLenum;
begin
  FGL.glGenTextures(1, @FTargetTex);
  FGL.glBindTexture(GL_TEXTURE_2D, FTargetTex);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  FGL.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, FWidth, FHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil);
  FGL.glGenFramebuffersEXT(1, @FFBO);
  FGL.glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, FFBO);
  FGL.glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_2D, FTargetTex, 0);
  Status := FGL.glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);
  if Status <> GL_FRAMEBUFFER_COMPLETE_EXT then
    raise EPMLUnsupported.CreateFmt('offscreen GL: the framebuffer is incomplete (status 0x%x, %d x %d)',
      [Status, FWidth, FHeight]);
  // 中身を決めておく（透明な黒）。
  FGL.glClearColor(0, 0, 0, 0);
  FGL.glClear(GL_COLOR_BUFFER_BIT);
  FGL.glClearColor(1.0, 1.0, 1.0, 1.0);
end;

procedure TPMLGLRenderDriver.EnsureCurrent;
var
  Err: EGLint;
begin
  if FContext <> nil then
  begin
    if Assigned(eglGetCurrentContext) and (eglGetCurrentContext() = FContext.Handle) then
      Exit;
    FContext.MakeCurrent;
  end
  else if FEGLContext <> EGL_NO_CONTEXT then
  begin
    if eglGetCurrentContext() = FEGLContext then
      Exit;
    eglBindAPI(EGL_OPENGL_API);
    if eglMakeCurrent(FDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, FEGLContext) = EGL_FALSE then
    begin
      Err := eglGetError();
      raise EPMLRenderError.CreateFmt('failed to make the GL context current (%s)',
        [PMLEGLErrorName(Err)]);
    end;
  end;
end;

procedure TPMLGLRenderDriver.ReadOutputSize(out AWidth, AHeight: Integer);
var
  R: TPMLRect;
begin
  if FWindow <> nil then
  begin
    R := FWindow.SizeInPixels;
    AWidth := R.W;
    AHeight := R.H;
  end
  else
  begin
    AWidth := FWidth;
    AHeight := FHeight;
  end;
end;

{ いま描いている先の大きさ。描画先のテクスチャがあればその大きさ。 }
procedure TPMLGLRenderDriver.ReadDrawableSize(out AWidth, AHeight: Integer);
begin
  if FTarget <> nil then
  begin
    AWidth := FTarget.Width;
    AHeight := FTarget.Height;
  end
  else
    ReadOutputSize(AWidth, AHeight);
end;

{ いま描いている先が、原点が左下のウィンドウの既定のフレームバッファか。FBO は上下を反転させない。 }
function TPMLGLRenderDriver.FlipsOutput: Boolean;
begin
  Result := (FWindow <> nil) and (FTarget = nil);
end;

{ 描画先の FBO を束縛する。描画先のテクスチャは、サイズごとの FBO を共有しているので、色の付け先を付け直す
  （SDL の GL_SetRenderTarget）。 }
procedure TPMLGLRenderDriver.BindDrawFramebuffer;
begin
  if FTarget <> nil then
  begin
    FGL.glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, FFBOs[FTarget.FBOIndex].Id);
    FGL.glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, FTexType, FTarget.Id, 0);
  end
  else if FWindow <> nil then
    FGL.glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0)
  else
    FGL.glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, FFBO);
end;

{ GL の誤りを読んで捨てる。デバッグビルド（PAPIMELA_DEBUG）では例外にする。 }
procedure TPMLGLRenderDriver.CheckGLErrors(const AWhere: String);
{$ifdef PAPIMELA_DEBUG}
var
  Code: GLenum;
  Codes: String;
begin
  Codes := '';
  repeat
    Code := FGL.glGetError();
    if Code <> GL_NO_ERROR then
      Codes := Codes + Format(' 0x%x', [Code]);
  until Code = GL_NO_ERROR;
  if Codes <> '' then
    raise EPMLRenderError.CreateFmt('GL error after %s:%s', [AWhere, Codes]);
end;
{$else}
begin
end;
{$endif}

{ サイズごとの FBO（SDL の GL_GetFBO）。無ければ作る。一覧の添字を返す。 }
function TPMLGLRenderDriver.GetFBO(AWidth, AHeight: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FFBOs) do
    if (FFBOs[I].Width = AWidth) and (FFBOs[I].Height = AHeight) then
      Exit(I);
  SetLength(FFBOs, Length(FFBOs) + 1);
  Result := High(FFBOs);
  FFBOs[Result].Width := AWidth;
  FFBOs[Result].Height := AHeight;
  FFBOs[Result].Id := 0;
  FGL.glGenFramebuffersEXT(1, @FFBOs[Result].Id);
end;

function TPMLGLRenderDriver.Supports(AShader: TPMLGLShader): Boolean;
begin
  Result := (FShaders <> nil) and FShaders.Supports(AShader);
end;

function TPMLGLRenderDriver.TextureMode: TPMLGLTextureMode;
begin
  if FNPOT then
    Result := TPMLGLTextureMode.Auto
  else if FRect then
    Result := TPMLGLTextureMode.Rectangle
  else
    Result := TPMLGLTextureMode.PowerOfTwo;
end;

function TPMLGLRenderDriver.ShadersEnabled: Boolean;
begin
  Result := FShaders <> nil;
end;

function TPMLGLRenderDriver.PixelArtSupported: Boolean;
begin
  Result := FPixelArt;
end;

function TPMLGLRenderDriver.QueryInteger(AName: GLenum): GLint;
begin
  EnsureCurrent;
  Result := 0;
  FGL.glGetIntegerv(AName, @Result);
end;

{ ---- 出力 ---- }

function TPMLGLRenderDriver.Name: String;
begin
  Result := 'opengl';
end;

function TPMLGLRenderDriver.GetOutputSize(out AWidth, AHeight: Integer): Boolean;
begin
  ReadOutputSize(AWidth, AHeight);
  Result := True;
end;

{ すべての合成モードを持つ（papimela の合成モードは 5 つの固定値で、どれも GL の本体で表せる。
  SDL の GL_SupportsBlendMode は任意の組み合わせの係数と演算が GL に対応するかを調べる）。 }
function TPMLGLRenderDriver.SupportsBlendMode(AMode: TPMLBlendMode): Boolean;
begin
  Result := True;
end;

{ SDL の GL_CreateRenderer の「テクスチャの形式」の判定。

  PORT-NOTE(bug): SDL のシェーダは、NPOT でないテクスチャ（矩形か 2 の冪乗への切り上げ）で、INDEX8 と I444 を正しく
  描けない。パレットの検索は座標を 256 で割った正規化のまま引き（矩形は画素の座標が要る）、線形は texel_size を
  論理の大きさで持つので 2 の冪乗に切り上げた座標と合わない。I444 は矩形のとき色差を輝度の半分の大きさで読む
  （UVCoordScale 0.5）が、I444 の色差は輝度と同じ大きさ。実機の GL（2.0 以上）は NPOT を持つのでこの道は通らない。
  papimela は NPOT でないとき、この 2 形式を持たないことにして、レンダラの ARGB8888 への肩代わりに任せる。 }
function TPMLGLRenderDriver.SupportsTextureFormat(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := False;
  if AFormat = PML_PIXELFORMAT_RGBA32 then
    Result := True
  else if AFormat = PML_PIXELFORMAT_BGRA32 then
    Result := FBGRA
  else if AFormat = PML_PIXELFORMAT_RGBX32 then
    Result := Supports(TPMLGLShader.RGB)
  else if AFormat = PML_PIXELFORMAT_BGRX32 then
    Result := FBGRA and Supports(TPMLGLShader.RGB)
  else if AFormat = PML_PIXELFORMAT_INDEX8 then
    Result := FNPOT and Supports(TPMLGLShader.PaletteNearest) and Supports(TPMLGLShader.PaletteLinear)
      and ((not FPixelArt) or Supports(TPMLGLShader.PalettePixelArt)) and (FNumTextureUnits >= 2)
  else if IsPlanarYUVFormat(AFormat) then
    Result := Supports(TPMLGLShader.YUV) and (FNumTextureUnits >= 3)
      and (FNPOT or (AFormat <> PML_PIXELFORMAT_I444))
  else if IsNVFormat(AFormat) then
    Result := Supports(TPMLGLShader.NV12_RA) and Supports(TPMLGLShader.NV12_RG)
      and Supports(TPMLGLShader.NV21_RA) and Supports(TPMLGLShader.NV21_RG)
      and (FNumTextureUnits >= 2);
end;

{ ---- テクスチャ ---- }

{ ユニット AUnit を有効にする。マルチテクスチャが無いときは何もしない（ユニット 0 しか無い）。 }
procedure TPMLGLRenderDriver.ActivateUnit(AUnit: GLenum);
begin
  if FMultitexture then
    FGL.glActiveTextureARB(AUnit);
end;

{ 輝度の面を偶数に切り上げて持っているテクスチャ（NPOT の奇数の大きさの YUV）で、更新した矩形が右端か下端に
  届いたら、余白の列と行へ、端の画素を複製する。

  PORT-NOTE: SDL の GL は、輝度と色差を同じ正規化した座標で読むので、幅か高さが奇数のとき、色差の位置が
  輝度のテクセル n の n div 2 番からずれる（Render.GLES2 の YUV の PORT-NOTE と同じ。ソフトウェアのドライバは
  n div 2）。papimela は NPOT のとき輝度の面を偶数に切り上げ、座標を元の大きさに縮めて、位置を揃える。余白は
  補間（Linear）が端を読んでも、端の画素と同じ色になるよう、端の複製にする。 }
procedure TPMLGLRenderDriver.ReplicateLumaEdges(AData: TPMLGLTexture; const ARect: TPMLRect;
  APixels: Pointer; APitch: Integer);
var
  Col: TBytes;
  Y: Integer;
  Src, LastRow: PByte;
  AtRight: Boolean;
begin
  if not (AData.PadX or AData.PadY) then
    Exit;
  Src := PByte(APixels);
  AtRight := AData.PadX and (ARect.X + ARect.W = AData.Width);
  FGL.glBindTexture(FTexType, AData.Id);
  FGL.glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  FGL.glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  if AtRight then
  begin
    SetLength(Col, ARect.H);
    for Y := 0 to ARect.H - 1 do
      Col[Y] := (Src + PtrInt(Y) * PtrInt(APitch))[ARect.W - 1];
    FGL.glTexSubImage2D(FTexType, 0, AData.Width, ARect.Y, 1, ARect.H, AData.DataFormat,
      GL_UNSIGNED_BYTE, @Col[0]);
  end;
  if AData.PadY and (ARect.Y + ARect.H = AData.Height) then
  begin
    LastRow := Src + PtrInt(ARect.H - 1) * PtrInt(APitch);
    FGL.glTexSubImage2D(FTexType, 0, ARect.X, AData.Height, ARect.W, 1, AData.DataFormat,
      GL_UNSIGNED_BYTE, LastRow);
    if AtRight then
      FGL.glTexSubImage2D(FTexType, 0, AData.Width, AData.Height, 1, 1, AData.DataFormat,
        GL_UNSIGNED_BYTE, LastRow + (ARect.W - 1));
  end;
end;

{ ユニット AUnit に AId を束縛して、ユニット 0 に戻す。 }
procedure TPMLGLRenderDriver.BindUnit(AUnit: GLenum; AId: GLuint);
begin
  ActivateUnit(AUnit);
  FGL.glBindTexture(FTexType, AId);
  ActivateUnit(GL_TEXTURE0_ARB);
end;

{ いまのユニットに束縛してあるテクスチャの補間と端の扱いを設定する（SDL の SetTextureScaleMode と
  SetTextureAddressMode）。INDEX8 の線形は、シェーダで混ぜるので GL の補間は最近傍のまま。
  PixelArt は、ピクセルアート用のシェーダが使えれば線形で標本する。 }
procedure TPMLGLRenderDriver.SetScaleMode(AFormatIndexed: Boolean; AMode: TPMLScaleMode);
var
  Filter: GLint;
begin
  case AMode of
    TPMLScaleMode.Nearest:
      Filter := GL_NEAREST;
    TPMLScaleMode.PixelArt:
      if not FPixelArt then
        Filter := GL_NEAREST
      else if AFormatIndexed then
        Filter := GL_NEAREST
      else
        Filter := GL_LINEAR;
  else
    // Linear
    if AFormatIndexed then
      Filter := GL_NEAREST
    else
      Filter := GL_LINEAR;
  end;
  FGL.glTexParameteri(FTexType, GL_TEXTURE_MIN_FILTER, Filter);
  FGL.glTexParameteri(FTexType, GL_TEXTURE_MAG_FILTER, Filter);
  FGL.glTexParameteri(FTexType, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  FGL.glTexParameteri(FTexType, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
end;

{ 1 枚の平面（束縛したテクスチャ）を、AWidth x AHeight で 0 のまま作る。ユニット 0 に束縛しておくこと。 }
procedure TPMLGLRenderDriver.CreatePlane(AId: GLuint; AWidth, AHeight: Integer; AInternal: GLint;
  AGLFormat: GLenum; ABytesPerTexel: Integer);
var
  Zero: Pointer;
  Size: PtrUInt;
begin
  FGL.glBindTexture(FTexType, AId);
  Size := PtrUInt(AWidth) * PtrUInt(AHeight) * PtrUInt(ABytesPerTexel);
  Zero := GetMem(Size);
  try
    FillChar(Zero^, Size, 0);
    FGL.glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    FGL.glTexImage2D(FTexType, 0, AInternal, AWidth, AHeight, 0, AGLFormat, GL_UNSIGNED_BYTE, Zero);
  finally
    FreeMem(Zero);
  end;
end;

{ 平面 AId の矩形 (AX, AY, AWidth, AHeight) を更新する。いまのユニットに束縛する。ARowLength は行の長さ
  （テクセル数。GL_UNPACK_ROW_LENGTH）。終わったら行の長さを 0 に戻す。 }
procedure TPMLGLRenderDriver.UploadPlane(AId: GLuint; AX, AY, AWidth, AHeight: Integer;
  AGLFormat: GLenum; APixels: Pointer; ARowLength: Integer);
begin
  FGL.glBindTexture(FTexType, AId);
  FGL.glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  FGL.glPixelStorei(GL_UNPACK_ROW_LENGTH, ARowLength);
  FGL.glTexSubImage2D(FTexType, 0, AX, AY, AWidth, AHeight, AGLFormat, GL_UNSIGNED_BYTE, APixels);
  FGL.glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
end;

{ SDL の GL_CreateTexture。中身はすべて 0 で作る。 }
function TPMLGLRenderDriver.CreateTexture(ATexture: TPMLTexture): Boolean;
var
  Data: TPMLGLTexture;
  Internal: GLint;
  DataFormat: GLenum;
  HasAlpha, Indexed, Planar, NV, Created: Boolean;
  YCbCr: TPMLYCbCrType;
  TW, TH, CW, CH, I: Integer;
  Size: PtrUInt;
begin
  Result := False;
  if not ConvertFormat(ATexture.Format, Internal, DataFormat, HasAlpha) then
    Exit;
  Indexed := ATexture.Format = PML_PIXELFORMAT_INDEX8;
  Planar := IsPlanarYUVFormat(ATexture.Format);
  NV := IsNVFormat(ATexture.Format);
  YCbCr := TPMLYCbCrType.BT601Limited;
  if Planar or NV then
  begin
    // YUV は描画先にできない。色空間に変換の行列が無ければ作らない
    if ATexture.Access = TPMLTextureAccess.Target then
      Exit;
    if not PMLYCbCrTypeOf(ATexture.Colorspace, YCbCr) then
      Exit;
  end;
  if (ATexture.Width > FMaxTexture) or (ATexture.Height > FMaxTexture) then
    Exit;
  EnsureCurrent;
  FGL.glGetError();
  Data := TPMLGLTexture.Create;
  Data.PixelFormat := ATexture.Format;
  Data.Width := ATexture.Width;
  Data.Height := ATexture.Height;
  Data.DataFormat := DataFormat;
  Data.HasAlpha := HasAlpha;
  Data.Indexed := Indexed;
  Data.Planar := Planar;
  Data.NV := NV;
  Data.YCbCr := YCbCr;
  Data.Filter := TPMLScaleMode.Nearest;
  Data.FBOIndex := -1;
  // 大きさ（SDL: NPOT はそのまま、矩形は大きさのまま texw = 大きさ、それ以外は 2 の冪乗に切り上げ）
  if FNPOT then
  begin
    TW := ATexture.Width;
    TH := ATexture.Height;
    Data.TexW := 1.0;
    Data.TexH := 1.0;
    if Planar and (ATexture.Format <> PML_PIXELFORMAT_I444) or NV then
    begin
      // 色差は (n + 1) div 2 で、輝度と同じ正規化した座標で読む。輝度の大きさが奇数だと色差の位置が
      // 「輝度のテクセル n の n div 2 番」からずれるので、偶数に切り上げて、座標を元の大きさに縮める
      Data.PadX := Odd(TW);
      Data.PadY := Odd(TH);
      if Data.PadX then
        Inc(TW);
      if Data.PadY then
        Inc(TH);
      Data.TexW := ATexture.Width / TW;
      Data.TexH := ATexture.Height / TH;
    end;
  end
  else if FRect then
  begin
    TW := ATexture.Width;
    TH := ATexture.Height;
    Data.TexW := TW;
    Data.TexH := TH;
  end
  else
  begin
    TW := PowerOfTwo(ATexture.Width);
    TH := PowerOfTwo(ATexture.Height);
    Data.TexW := ATexture.Width / TW;
    Data.TexH := ATexture.Height / TH;
  end;
  Data.TexelSize[0] := 1.0 / ATexture.Width;
  Data.TexelSize[1] := 1.0 / ATexture.Height;
  Data.TexelSize[2] := ATexture.Width;
  Data.TexelSize[3] := ATexture.Height;

  FGL.glGenTextures(1, @Data.Id);
  FGL.glEnable(FTexType);
  CreatePlane(Data.Id, TW, TH, Internal, DataFormat, BytesPerTexel(ATexture.Format));
  SetScaleMode(Indexed, TPMLScaleMode.Nearest);

  if Planar or NV then
  begin
    // 色差の平面。I444 は輝度と同じ大きさ、ほかは (n + 1) div 2
    if ATexture.Format = PML_PIXELFORMAT_I444 then
    begin
      CW := TW;
      CH := TH;
    end
    else
    begin
      CW := (TW + 1) div 2;
      CH := (TH + 1) div 2;
    end;
    if Planar then
    begin
      FGL.glGenTextures(1, @Data.IdU);
      FGL.glGenTextures(1, @Data.IdV);
      CreatePlane(Data.IdU, CW, CH, Internal, DataFormat, 1);
      SetScaleMode(False, TPMLScaleMode.Nearest);
      CreatePlane(Data.IdV, CW, CH, Internal, DataFormat, 1);
      SetScaleMode(False, TPMLScaleMode.Nearest);
    end
    else
    begin
      FGL.glGenTextures(1, @Data.IdU);
      CreatePlane(Data.IdU, CW, CH, GL_LUMINANCE_ALPHA, GL_LUMINANCE_ALPHA, 2);
      SetScaleMode(False, TPMLScaleMode.Nearest);
    end;
    FGL.glBindTexture(FTexType, 0);
  end;

  // シェーダの選び方（SDL の GL_CreateTexture の終わり）
  if Indexed then
    Data.Shader := TPMLGLShader.PaletteNearest
  else if (ATexture.Format = PML_PIXELFORMAT_RGBA32) or (ATexture.Format = PML_PIXELFORMAT_BGRA32) then
    Data.Shader := TPMLGLShader.RGBA
  else
    Data.Shader := TPMLGLShader.RGB;
  if Planar then
    Data.Shader := TPMLGLShader.YUV
  else if ATexture.Format = PML_PIXELFORMAT_NV12 then
    Data.Shader := TPMLGLShader.NV12_RA
  else if ATexture.Format = PML_PIXELFORMAT_NV21 then
    Data.Shader := TPMLGLShader.NV21_RA;
  if Planar or NV then
  begin
    // SDL の shader_params: Yoffset(3) 0、Rcoeff(3) 0、Gcoeff(3) 0、Bcoeff(3) 0
    FillChar(Data.YUVParams, SizeOf(Data.YUVParams), 0);
    for I := 0 to 2 do
    begin
      Data.YUVParams[I] := YUVMatrix[YCbCr][I];
      Data.YUVParams[4 + I] := YUVMatrix[YCbCr][3 + I];
      Data.YUVParams[8 + I] := YUVMatrix[YCbCr][6 + I];
      Data.YUVParams[12 + I] := YUVMatrix[YCbCr][9 + I];
    end;
  end;
  FGL.glBindTexture(FTexType, 0);
  FGL.glDisable(FTexType);

  Created := FGL.glGetError() = GL_NO_ERROR;
  if Created and (ATexture.Access = TPMLTextureAccess.Target) then
    Data.FBOIndex := GetFBO(ATexture.Width, ATexture.Height);
  if not Created then
  begin
    FGL.glDeleteTextures(1, @Data.Id);
    if Data.IdU <> 0 then
      FGL.glDeleteTextures(1, @Data.IdU);
    if Data.IdV <> 0 then
      FGL.glDeleteTextures(1, @Data.IdV);
    Data.Free;
    Exit;
  end;
  if ATexture.Access = TPMLTextureAccess.Streaming then
  begin
    // Lock の置き場。SDL と同じ大きさ（YUV は色差の平面の分も）で、0 で埋める
    Data.PixelPitch := ATexture.Width * BytesPerTexel(ATexture.Format);
    Size := PtrUInt(ATexture.Height) * PtrUInt(Data.PixelPitch);
    if Planar or NV then
      PMLCalculateYUVSize(ATexture.Format, ATexture.Width, ATexture.Height, Size, Data.PixelPitch);
    SetLength(Data.PixelData, Size);
    FillChar(Data.PixelData[0], Size, 0);
  end;
  ATexture.DriverData := Data;
  Result := True;
end;

function TPMLGLRenderDriver.LockTexture(ATexture: TPMLTexture; const ARect: TPMLRect;
  out APixels: Pointer; out APitch: Integer): Boolean;
var
  Data: TPMLGLTexture;
begin
  APixels := nil;
  APitch := 0;
  Data := TextureData(ATexture);
  Result := (Data <> nil) and (Length(Data.PixelData) > 0);
  if not Result then
    Exit;
  APitch := Data.PixelPitch;
  APixels := @Data.PixelData[0] + PtrUInt(ARect.Y) * PtrUInt(Data.PixelPitch)
    + PtrUInt(ARect.X) * PtrUInt(BytesPerTexel(ATexture.Format));
end;

{ 置き場の全体を GPU へ上げる（SDL の GL_UnlockTexture は、Lock した矩形を上げる。papimela の
  置き場は全体を持つので、ここも全体）。 }
procedure TPMLGLRenderDriver.UnlockTexture(ATexture: TPMLTexture);
var
  Data: TPMLGLTexture;
begin
  Data := TextureData(ATexture);
  if (Data = nil) or (Length(Data.PixelData) = 0) then
    Exit;
  UpdateTexture(ATexture, TPMLRect.Make(0, 0, ATexture.Width, ATexture.Height),
    @Data.PixelData[0], Data.PixelPitch);
end;

{ SDL の GL_UpdateTexture。YUV は詰めた画素で来る（PMLCalculateYUVSize と同じ並び）。 }
function TPMLGLRenderDriver.UpdateTexture(ATexture: TPMLTexture; const ARect: TPMLRect;
  APixels: Pointer; APitch: Integer): Boolean;
var
  Data: TPMLGLTexture;
  Src: PByte;
  Bpt, CPitch: Integer;
begin
  Result := False;
  Data := TextureData(ATexture);
  if (Data = nil) or (APixels = nil) then
    Exit;
  if (ARect.X < 0) or (ARect.Y < 0) or (ARect.W <= 0) or (ARect.H <= 0)
  or (ARect.X + ARect.W > ATexture.Width) or (ARect.Y + ARect.H > ATexture.Height) then
    Exit;
  EnsureCurrent;
  FGL.glGetError();
  Bpt := BytesPerTexel(ATexture.Format);
  UploadPlane(Data.Id, ARect.X, ARect.Y, ARect.W, ARect.H, Data.DataFormat, APixels, APitch div Bpt);
  ReplicateLumaEdges(Data, ARect, APixels, APitch);
  if Data.Planar then
  begin
    if ATexture.Format = PML_PIXELFORMAT_I444 then
    begin
      // 色差も輝度と同じ大きさ（行の幅も Y と同じ）
      Src := PByte(APixels) + PtrInt(ARect.H) * PtrInt(APitch);
      UploadPlane(Data.IdU, ARect.X, ARect.Y, ARect.W, ARect.H, Data.DataFormat, Src, APitch);
      Src := Src + PtrInt(ARect.H) * PtrInt(APitch);
      UploadPlane(Data.IdV, ARect.X, ARect.Y, ARect.W, ARect.H, Data.DataFormat, Src, APitch);
    end
    else
    begin
      CPitch := (APitch + 1) div 2;
      Src := PByte(APixels) + PtrInt(ARect.H) * PtrInt(APitch);
      // YV12 は V、U の順、IYUV は U、V の順
      if ATexture.Format = PML_PIXELFORMAT_YV12 then
        UploadPlane(Data.IdV, ARect.X div 2, ARect.Y div 2, (ARect.W + 1) div 2, (ARect.H + 1) div 2,
          Data.DataFormat, Src, CPitch)
      else
        UploadPlane(Data.IdU, ARect.X div 2, ARect.Y div 2, (ARect.W + 1) div 2, (ARect.H + 1) div 2,
          Data.DataFormat, Src, CPitch);
      Src := Src + PtrInt((ARect.H + 1) div 2) * PtrInt(CPitch);
      if ATexture.Format = PML_PIXELFORMAT_YV12 then
        UploadPlane(Data.IdU, ARect.X div 2, ARect.Y div 2, (ARect.W + 1) div 2, (ARect.H + 1) div 2,
          Data.DataFormat, Src, CPitch)
      else
        UploadPlane(Data.IdV, ARect.X div 2, ARect.Y div 2, (ARect.W + 1) div 2, (ARect.H + 1) div 2,
          Data.DataFormat, Src, CPitch);
    end;
  end;
  if Data.NV then
  begin
    CPitch := (APitch + 1) div 2;
    Src := PByte(APixels) + PtrInt(ARect.H) * PtrInt(APitch);
    UploadPlane(Data.IdU, ARect.X div 2, ARect.Y div 2, (ARect.W + 1) div 2, (ARect.H + 1) div 2,
      GL_LUMINANCE_ALPHA, Src, CPitch);
  end;
  FGL.glBindTexture(FTexType, 0);
  Result := FGL.glGetError() = GL_NO_ERROR;
end;

{ 平面ごとの更新（SDL の GL_UpdateTextureYUV）。YV12 / IYUV / I444。 }
function TPMLGLRenderDriver.UpdateTextureYUV(ATexture: TPMLTexture; const ARect: TPMLRect;
  AY: Pointer; AYPitch: Integer; AU: Pointer; AUPitch: Integer;
  AV: Pointer; AVPitch: Integer): Boolean;
var
  Data: TPMLGLTexture;
begin
  Result := False;
  Data := TextureData(ATexture);
  if (Data = nil) or not Data.Planar or (AY = nil) or (AU = nil) or (AV = nil) then
    Exit;
  if (ARect.X < 0) or (ARect.Y < 0) or (ARect.W <= 0) or (ARect.H <= 0)
  or (ARect.X + ARect.W > ATexture.Width) or (ARect.Y + ARect.H > ATexture.Height) then
    Exit;
  EnsureCurrent;
  FGL.glGetError();
  UploadPlane(Data.Id, ARect.X, ARect.Y, ARect.W, ARect.H, Data.DataFormat, AY, AYPitch);
  ReplicateLumaEdges(Data, ARect, AY, AYPitch);
  if ATexture.Format = PML_PIXELFORMAT_I444 then
  begin
    UploadPlane(Data.IdU, ARect.X, ARect.Y, ARect.W, ARect.H, Data.DataFormat, AU, AUPitch);
    UploadPlane(Data.IdV, ARect.X, ARect.Y, ARect.W, ARect.H, Data.DataFormat, AV, AVPitch);
  end
  else
  begin
    UploadPlane(Data.IdU, ARect.X div 2, ARect.Y div 2, (ARect.W + 1) div 2, (ARect.H + 1) div 2,
      Data.DataFormat, AU, AUPitch);
    UploadPlane(Data.IdV, ARect.X div 2, ARect.Y div 2, (ARect.W + 1) div 2, (ARect.H + 1) div 2,
      Data.DataFormat, AV, AVPitch);
  end;
  FGL.glBindTexture(FTexType, 0);
  Result := FGL.glGetError() = GL_NO_ERROR;
end;

{ Y と、U・V を交互に詰めた平面での更新（SDL の GL_UpdateTextureNV）。UV の行の長さはテクセル数 AUVPitch div 2。 }
function TPMLGLRenderDriver.UpdateTextureNV(ATexture: TPMLTexture; const ARect: TPMLRect;
  AY: Pointer; AYPitch: Integer; AUV: Pointer; AUVPitch: Integer): Boolean;
var
  Data: TPMLGLTexture;
begin
  Result := False;
  Data := TextureData(ATexture);
  if (Data = nil) or not Data.NV or (AY = nil) or (AUV = nil) then
    Exit;
  if (ARect.X < 0) or (ARect.Y < 0) or (ARect.W <= 0) or (ARect.H <= 0)
  or (ARect.X + ARect.W > ATexture.Width) or (ARect.Y + ARect.H > ATexture.Height) then
    Exit;
  EnsureCurrent;
  FGL.glGetError();
  UploadPlane(Data.Id, ARect.X, ARect.Y, ARect.W, ARect.H, Data.DataFormat, AY, AYPitch);
  ReplicateLumaEdges(Data, ARect, AY, AYPitch);
  UploadPlane(Data.IdU, ARect.X div 2, ARect.Y div 2, (ARect.W + 1) div 2, (ARect.H + 1) div 2,
    GL_LUMINANCE_ALPHA, AUV, AUVPitch div 2);
  FGL.glBindTexture(FTexType, 0);
  Result := FGL.glGetError() = GL_NO_ERROR;
end;

procedure TPMLGLRenderDriver.DestroyTexture(ATexture: TPMLTexture);
var
  Data: TPMLGLTexture;
begin
  Data := TextureData(ATexture);
  if Data = nil then
    Exit;
  try
    EnsureCurrent;
    if FTarget = Data then
    begin
      // 描画先のまま消された。描画先を元へ戻す（レンダラは先に戻している）。
      FTarget := nil;
      BindDrawFramebuffer;
    end;
    FGL.glDeleteTextures(1, @Data.Id);
    if Data.IdU <> 0 then
      FGL.glDeleteTextures(1, @Data.IdU);
    if Data.IdV <> 0 then
      FGL.glDeleteTextures(1, @Data.IdV);
  except
    on E: EPMLError do
      FLastNonFatalError := 'GL texture cleanup failed: ' + E.Message;
  end;
  FreeAndNil(ATexture.DriverData);
end;

{ ---- パレット（SDL の GL_CreatePalette / UpdatePalette / DestroyPalette） ---- }

{ 256x1 の RGBA8 のテクスチャを作る。補間は最近傍、端は CLAMP_TO_EDGE。

  PORT-NOTE: SDL は中身を未定義のまま作る。papimela は 256 色すべてを白の不透明で始める。アプリのパレットが
  256 色に満たないとき、表の外の添字が白で描かれ、ソフトウェアのドライバと同じ絵になる。 }
function TPMLGLRenderDriver.CreatePalette(APalette: TPMLTexturePalette): Boolean;
var
  Data: TPMLGLPalette;
  White: array[0..255] of TPMLColor;
  I: Integer;
begin
  Result := False;
  EnsureCurrent;
  FGL.glGetError();
  for I := 0 to 255 do
    White[I] := TPMLColor.White;
  Data := TPMLGLPalette.Create;
  FGL.glGenTextures(1, @Data.Id);
  FGL.glBindTexture(FTexType, Data.Id);
  FGL.glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  FGL.glTexImage2D(FTexType, 0, GL_RGBA8, 256, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, @White[0]);
  SetScaleMode(False, TPMLScaleMode.Nearest);
  FGL.glBindTexture(FTexType, 0);
  if FGL.glGetError() <> GL_NO_ERROR then
  begin
    FGL.glDeleteTextures(1, @Data.Id);
    Data.Free;
    Exit;
  end;
  APalette.DriverData := Data;
  Result := True;
end;

{ 先頭の AColors の個数ぶんの色を写す。TPMLColor は R,G,B,A の順の 4 バイト。残りの色は前のまま。 }
function TPMLGLRenderDriver.UpdatePalette(APalette: TPMLTexturePalette;
  const AColors: array of TPMLColor): Boolean;
var
  Data: TPMLGLPalette;
  Count: Integer;
begin
  Result := False;
  if not (APalette.DriverData is TPMLGLPalette) then
    Exit;
  Data := TPMLGLPalette(APalette.DriverData);
  Count := Min(Length(AColors), 256);
  if Count <= 0 then
    Exit(True);
  EnsureCurrent;
  FGL.glGetError();
  FGL.glBindTexture(FTexType, Data.Id);
  FGL.glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  FGL.glPixelStorei(GL_UNPACK_ROW_LENGTH, Count);
  FGL.glTexSubImage2D(FTexType, 0, 0, 0, Count, 1, GL_RGBA, GL_UNSIGNED_BYTE, @AColors[0]);
  FGL.glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  FGL.glBindTexture(FTexType, 0);
  Result := FGL.glGetError() = GL_NO_ERROR;
end;

procedure TPMLGLRenderDriver.DestroyPalette(APalette: TPMLTexturePalette);
var
  Data: TPMLGLPalette;
begin
  if APalette.DriverData is TPMLGLPalette then
  begin
    Data := TPMLGLPalette(APalette.DriverData);
    try
      EnsureCurrent;
      FGL.glDeleteTextures(1, @Data.Id);
    except
      on E: EPMLError do
        FLastNonFatalError := 'GL palette cleanup failed: ' + E.Message;
    end;
  end;
  FreeAndNil(APalette.DriverData);
end;

{ 何もしない。描くときに ACmd.Texture.DriverPalette を読んで束縛する（ExecDraw）。 }
procedure TPMLGLRenderDriver.ChangeTexturePalette(ATexture: TPMLTexture);
begin
end;

function TPMLGLRenderDriver.SupportsRenderTargets: Boolean;
begin
  Result := True;
end;

{ 描画先を切り替える（SDL の GL_SetRenderTarget）。束縛は次の実行の頭（BeginRun）と読み戻しでも張り直す。 }
function TPMLGLRenderDriver.SetRenderTarget(ATexture: TPMLTexture): Boolean;
var
  Data: TPMLGLTexture;
begin
  Result := False;
  Data := nil;
  if ATexture <> nil then
  begin
    Data := TextureData(ATexture);
    if (Data = nil) or (Data.FBOIndex < 0) then
      Exit;
  end;
  EnsureCurrent;
  FTarget := Data;
  BindDrawFramebuffer;
  if FTarget <> nil then
    Result := FGL.glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT) = GL_FRAMEBUFFER_COMPLETE_EXT
  else
    Result := True;
end;

{ ---- 積み込み ---- }

{ 図形を積む。テクスチャ座標に texw / texh を掛ける（SDL の GL_QueueGeometry）。

  PORT-NOTE: 掛けたあとに、最近傍の境目の補正（TIE_BIAS）を足す。SDL にはこの補正が無い。 }
procedure TPMLGLRenderDriver.QueueGeometry(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const AVertices: array of TPMLVertex);
var
  Data: TPMLGLTexture;
  V: TPMLVertices;
  I: Integer;
begin
  Data := nil;
  if ACmd.Texture <> nil then
    Data := TextureData(ACmd.Texture);
  if Data <> nil then
  begin
    SetLength(V, Length(AVertices));
    for I := 0 to High(AVertices) do
    begin
      V[I] := AVertices[I];
      V[I].TexCoord.X := V[I].TexCoord.X * Data.TexW + TIE_BIAS * Data.TexW / Data.Width;
      V[I].TexCoord.Y := V[I].TexCoord.Y * Data.TexH + TIE_BIAS * Data.TexH / Data.Height;
    end;
    ACmd.First := AQueue.AddVertices(V);
  end
  else
    ACmd.First := AQueue.AddVertices(AVertices);
  ACmd.Count := Length(AVertices);
end;

{ 点を 1 頂点にする。画素の中心に当てるため +0.5 する（SDL の GL_QueueDrawPoints）。

  PORT-NOTE: SDL は座標をそのまま +0.5 する。ソフトウェアのドライバは点を Trunc して画素に置くので、
  ここも切り捨ててから +0.5 し、小数の座標でも同じ画素を塗る。 }
procedure TPMLGLRenderDriver.QueueDrawPoints(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const APoints: array of TPMLFPoint);
var
  V: TPMLVertices;
  I: Integer;
begin
  SetLength(V, Length(APoints));
  for I := 0 to High(APoints) do
    V[I] := MakeVertex(Int(APoints[I].X) + 0.5, Int(APoints[I].Y) + 0.5, ACmd.Color);
  ACmd.First := AQueue.AddVertices(V);
  ACmd.Count := Length(V);
end;

{ 折れ線を、線分ごとに 2 頂点（GL_LINES）にする。始点は画素の中心（+0.5）。終点は中心から線の向きへ
  LINE_EXTEND 画素延ばして、GL の線の規則（菱形の出口規則）で最後の画素が落ちないようにする。

  PORT-NOTE: SDL は 1/4 画素延ばす。GLES2 のドライバでは、Mesa（radeonsi）で 1/4 だと軸に平行な線の最後の画素が
  落ちたので 0.75 にした（Render.GLES2 の QueueDrawLines の PORT-NOTE(bug)）。ここも同じにして、検査で確かめる。 }
procedure TPMLGLRenderDriver.QueueDrawLines(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const APoints: array of TPMLFPoint);
var
  V: TPMLVertices;
  I: Integer;
  X0, Y0, X1, Y1, Angle: Single;
begin
  if Length(APoints) < 2 then
    Exit;
  SetLength(V, (Length(APoints) - 1) * 2);
  for I := 0 to High(APoints) - 1 do
  begin
    X0 := Int(APoints[I].X) + 0.5;
    Y0 := Int(APoints[I].Y) + 0.5;
    X1 := Int(APoints[I + 1].X) + 0.5;
    Y1 := Int(APoints[I + 1].Y) + 0.5;
    Angle := ArcTan2(Y1 - Y0, X1 - X0);
    V[I * 2] := MakeVertex(X0, Y0, ACmd.Color);
    V[I * 2 + 1] := MakeVertex(X1 + Cos(Angle) * LINE_EXTEND, Y1 + Sin(Angle) * LINE_EXTEND, ACmd.Color);
  end;
  ACmd.First := AQueue.AddVertices(V);
  ACmd.Count := Length(V);
end;

{ ---- 実行 ---- }

{ 実行の頭。描画先を束縛し、状態をすべて未確定にして、頂点を配列にしてクライアント配列の
  ポインタを設定する（SDL の GL_InvalidateCachedState と、SetDrawState の glXxxPointer）。 }
procedure TPMLGLRenderDriver.BeginRun(AQueue: TPMLRenderQueue);
var
  I: Integer;
begin
  EnsureCurrent;
  ReadDrawableSize(FDrawableW, FDrawableH);
  BindDrawFramebuffer;

  FViewport := TPMLRect.Make(0, 0, FDrawableW, FDrawableH);
  FClipOn := False;
  FViewportDirty := True;
  FClipDirty := True;
  FGL.glDisable(GL_SCISSOR_TEST);
  FScissorOn := False;
  FGL.glDisable(GL_BLEND);
  FBlendValid := False;
  FShaderValid := False;
  FCurParams := nil;
  FTexturingValid := False;
  FTexCoordArray := False;
  FBoundTexture := 0;
  FBoundUnit1 := 0;
  FBoundUnit2 := 0;
  // 実行の前の呼び出し（テクスチャの更新など）が束縛を動かしても、ユニット 0 に戻す。
  ActivateUnit(GL_TEXTURE0_ARB);

  if AQueue.VertexCount > 0 then
  begin
    if Length(FVertexBuf) < AQueue.VertexCount then
      SetLength(FVertexBuf, AQueue.VertexCount * 2);
    for I := 0 to AQueue.VertexCount - 1 do
      FVertexBuf[I] := AQueue.Vertex(I);
    FGL.glEnableClientState(GL_VERTEX_ARRAY);
    FGL.glEnableClientState(GL_COLOR_ARRAY);
    FGL.glVertexPointer(2, GL_FLOAT, SizeOf(TPMLVertex), @FVertexBuf[0].Position);
    FGL.glColorPointer(4, GL_FLOAT, SizeOf(TPMLVertex), @FVertexBuf[0].Color);
    FGL.glTexCoordPointer(2, GL_FLOAT, SizeOf(TPMLVertex), @FVertexBuf[0].TexCoord);
  end;
end;

{ 実行の終わり。外のコードが配列の状態に頼らないよう、全部切る（SDL の GL_RunCommandQueue の終わり）。 }
procedure TPMLGLRenderDriver.EndRun;
begin
  FGL.glDisableClientState(GL_VERTEX_ARRAY);
  FGL.glDisableClientState(GL_COLOR_ARRAY);
  if FTexCoordArray then
  begin
    FGL.glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    FTexCoordArray := False;
  end;
end;

{ ビューポートと射影行列（SDL の SetDrawState の最初）。

  ビューポートの中の座標は、ビューポートの左上を原点とする画素。ウィンドウの既定のフレームバッファは
  原点が左下なので、上下を反転する（glViewport の y を下から数え直し、glOrtho の上下を逆にする）。FBO は反転させない。 }
procedure TPMLGLRenderDriver.ApplyViewport;
var
  Y, W, H: Integer;
begin
  if not FViewportDirty then
    Exit;
  W := Max(FViewport.W, 0);
  H := Max(FViewport.H, 0);
  FGL.glMatrixMode(GL_PROJECTION);
  FGL.glLoadIdentity();
  if FlipsOutput then
    Y := FDrawableH - FViewport.Y - H
  else
    Y := FViewport.Y;
  FGL.glViewport(FViewport.X, Y, W, H);
  if (W > 0) and (H > 0) then
  begin
    if FlipsOutput then
      FGL.glOrtho(0, W, H, 0, 0.0, 1.0)
    else
      FGL.glOrtho(0, W, 0, H, 0.0, 1.0);
  end;
  FGL.glMatrixMode(GL_MODELVIEW);
  FViewportDirty := False;
end;

{ シザー。実際に塗る範囲は「ビューポート ∩ クリップ矩形」（クリップ矩形はビューポートの原点からの相対）。

  PORT-NOTE: SDL は、ビューポートの外の図形を GL のクリップに任せ、シザーはクリップ矩形だけに使う。Mesa は
  ビューポートの外で、ガードバンドの内側の図形を切らずに描くことがあった（実測: llvmpipe で、ビューポートを
  絞って外へはみ出す矩形がはみ出して描かれた。GLES2 の同じ場面では切れた）ので、ビューポートが描画先全体より
  小さいときは、クリップ矩形が無くても、ビューポートでシザーする。 }
procedure TPMLGLRenderDriver.ApplyScissor;
var
  X, Y, W, H, X2, Y2, VX2, VY2: Integer;
  Needed: Boolean;
begin
  Needed := FClipOn or (FViewport.X > 0) or (FViewport.Y > 0)
    or (FViewport.X + FViewport.W < FDrawableW) or (FViewport.Y + FViewport.H < FDrawableH);
  if not Needed then
  begin
    if FScissorOn then
    begin
      FGL.glDisable(GL_SCISSOR_TEST);
      FScissorOn := False;
    end;
    Exit;
  end;
  if not FScissorOn then
  begin
    FGL.glEnable(GL_SCISSOR_TEST);
    FScissorOn := True;
  end;
  if FClipDirty then
  begin
    // 上が原点の座標で、ビューポートとクリップ矩形の共通部分を求める
    X := FViewport.X;
    Y := FViewport.Y;
    X2 := FViewport.X + Max(FViewport.W, 0);
    Y2 := FViewport.Y + Max(FViewport.H, 0);
    if FClipOn then
    begin
      VX2 := FViewport.X + FClip.X + Max(FClip.W, 0);
      VY2 := FViewport.Y + FClip.Y + Max(FClip.H, 0);
      X := Max(X, FViewport.X + FClip.X);
      Y := Max(Y, FViewport.Y + FClip.Y);
      X2 := Min(X2, VX2);
      Y2 := Min(Y2, VY2);
    end;
    W := Max(X2 - X, 0);
    H := Max(Y2 - Y, 0);
    if FlipsOutput then
      Y := FDrawableH - Y - H;
    FGL.glScissor(X, Y, W, H);
    FClipDirty := False;
  end;
end;

{ 合成モード → glBlendFuncSeparate / glBlendEquation（SDL の GetBlendFunc / GetBlendEquation。papimela の合成モードは
  5 つの固定値なので、係数の表を直接持つ。係数は SDL_render.h の定義と同じ）。 }
procedure TPMLGLRenderDriver.ApplyBlend(ABlend: TPMLBlendMode);
begin
  if FBlendValid and (FCurBlend = ABlend) then
    Exit;
  case ABlend of
    TPMLBlendMode.None:
      FGL.glDisable(GL_BLEND);
    TPMLBlendMode.Blend:
      begin
        FGL.glEnable(GL_BLEND);
        FGL.glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
      end;
    TPMLBlendMode.Add:
      begin
        FGL.glEnable(GL_BLEND);
        FGL.glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE, GL_ZERO, GL_ONE);
      end;
    TPMLBlendMode.Modulate:
      begin
        FGL.glEnable(GL_BLEND);
        FGL.glBlendFuncSeparate(GL_DST_COLOR, GL_ZERO, GL_ZERO, GL_ONE);
      end;
    TPMLBlendMode.Multiply:
      begin
        FGL.glEnable(GL_BLEND);
        FGL.glBlendFuncSeparate(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA, GL_ZERO, GL_ONE);
      end;
  end;
  if ABlend <> TPMLBlendMode.None then
    FGL.glBlendEquation(GL_FUNC_ADD);
  FCurBlend := ABlend;
  FBlendValid := True;
end;

{ SDL の SetDrawState の、ビューポート以外の部分: シザー、合成、シェーダ、テクスチャ有効、配列。 }
procedure TPMLGLRenderDriver.SetDrawState(const ACmd: TPMLRenderCommand; AShader: TPMLGLShader;
  AParams: PSingle);
var
  Textured: Boolean;
begin
  ApplyViewport;
  ApplyScissor;
  ApplyBlend(ACmd.Blend);
  if (FShaders <> nil) and ((not FShaderValid) or (AShader <> FCurShader) or (AParams <> FCurParams)) then
  begin
    FShaders.Select(AShader, AParams);
    FCurShader := AShader;
    FCurParams := AParams;
    FShaderValid := True;
  end;
  Textured := ACmd.Texture <> nil;
  if (not FTexturingValid) or (Textured <> FTexturing) then
  begin
    if Textured then
      FGL.glEnable(FTexType)
    else
      FGL.glDisable(FTexType);
    FTexturing := Textured;
    FTexturingValid := True;
  end;
  if Textured <> FTexCoordArray then
  begin
    if Textured then
      FGL.glEnableClientState(GL_TEXTURE_COORD_ARRAY)
    else
      FGL.glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    FTexCoordArray := Textured;
  end;
end;

{ 描画先全体を塗る。ビューポートもクリップも無視する。glClear はビューポートに従わないが、シザーには従うので、先に切る。 }
procedure TPMLGLRenderDriver.ExecClear(const ACmd: TPMLRenderCommand);
begin
  FGL.glClearColor(ACmd.Color.R, ACmd.Color.G, ACmd.Color.B, ACmd.Color.A);
  if FScissorOn then
  begin
    FGL.glDisable(GL_SCISSOR_TEST);
    FScissorOn := False;
  end;
  FGL.glClear(GL_COLOR_BUFFER_BIT);
end;

{ 積み荷 [First, First + Count) を AMode で描く（SDL の SetCopyState と SDL_RENDERCMD_GEOMETRY / DRAW_POINTS）。
  キューが同じ状態の描画をすでに 1 つのコマンドにまとめているので、1 コマンド = 1 回の glDrawArrays。 }
procedure TPMLGLRenderDriver.ExecDraw(AMode: GLenum; const ACmd: TPMLRenderCommand);
var
  Data: TPMLGLTexture;
  Pal: TPMLGLPalette;
  Shader: TPMLGLShader;
  Params: PSingle;
begin
  Data := nil;
  Pal := nil;
  Shader := TPMLGLShader.Solid;
  Params := nil;
  if ACmd.Texture <> nil then
  begin
    Data := TextureData(ACmd.Texture);
    if Data = nil then
      Exit;       // 破棄されたテクスチャ。描くものが無い
    Shader := Data.Shader;
    Params := @Data.YUVParams[0];
    if not (Data.Planar or Data.NV) then
      Params := nil;
    if Data.Indexed then
    begin
      // パレットの写しは実行のときに読む（レンダラが、版が変わったら先に吐き出す）
      if (ACmd.Texture.DriverPalette = nil)
      or not (ACmd.Texture.DriverPalette.DriverData is TPMLGLPalette) then
        Exit;     // 破棄されたパレット。描くものが無い
      Pal := TPMLGLPalette(ACmd.Texture.DriverPalette.DriverData);
      if ACmd.ScaleMode = TPMLScaleMode.Linear then
      begin
        Shader := TPMLGLShader.PaletteLinear;
        Params := @Data.TexelSize[0];
      end
      else if (ACmd.ScaleMode = TPMLScaleMode.PixelArt) and FPixelArt then
      begin
        Shader := TPMLGLShader.PalettePixelArt;
        Params := @Data.TexelSize[0];
      end;
    end
    else if Data.Shader = TPMLGLShader.RGB then
    begin
      if (ACmd.ScaleMode = TPMLScaleMode.PixelArt) and FPixelArt then
      begin
        Shader := TPMLGLShader.RGBPixelArt;
        Params := @Data.TexelSize[0];
      end;
    end
    else if Data.Shader = TPMLGLShader.RGBA then
    begin
      if (ACmd.ScaleMode = TPMLScaleMode.PixelArt) and FPixelArt then
      begin
        Shader := TPMLGLShader.RGBAPixelArt;
        Params := @Data.TexelSize[0];
      end;
    end;
  end;
  if ACmd.Count <= 0 then
    Exit;

  SetDrawState(ACmd, Shader, Params);

  if Data <> nil then
  begin
    if Pal <> nil then
    begin
      // パレットの写しはユニット 1
      if FBoundUnit1 <> Pal.Id then
      begin
        BindUnit(GL_TEXTURE1_ARB, Pal.Id);
        FBoundUnit1 := Pal.Id;
      end;
    end;
    if Data.IdU <> 0 then
    begin
      // YUV の U（NV は UV）はユニット 1、V はユニット 2。Y はこのあとユニット 0
      if FBoundUnit1 <> Data.IdU then
      begin
        BindUnit(GL_TEXTURE1_ARB, Data.IdU);
        FBoundUnit1 := Data.IdU;
      end;
      if (Data.IdV <> 0) and (FBoundUnit2 <> Data.IdV) then
      begin
        BindUnit(GL_TEXTURE2_ARB, Data.IdV);
        FBoundUnit2 := Data.IdV;
      end;
    end;
    if FBoundTexture <> Data.Id then
    begin
      FGL.glBindTexture(FTexType, Data.Id);
      FBoundTexture := Data.Id;
    end;
    // 補間。INDEX8 の添字のテクスチャは補間しない（線形はシェーダで混ぜる）ので、Filter は Nearest のまま
    if ACmd.ScaleMode <> Data.Filter then
    begin
      if Data.Planar then
      begin
        // YUV は全部の平面に同じ補間を掛ける
        ActivateUnit(GL_TEXTURE2_ARB);
        SetScaleMode(False, ACmd.ScaleMode);
        ActivateUnit(GL_TEXTURE1_ARB);
        SetScaleMode(False, ACmd.ScaleMode);
        ActivateUnit(GL_TEXTURE0_ARB);
      end
      else if Data.NV then
      begin
        ActivateUnit(GL_TEXTURE1_ARB);
        SetScaleMode(False, ACmd.ScaleMode);
        ActivateUnit(GL_TEXTURE0_ARB);
      end;
      SetScaleMode(Data.Indexed, ACmd.ScaleMode);
      Data.Filter := ACmd.ScaleMode;
    end;
  end;

  FGL.glDrawArrays(AMode, ACmd.First, ACmd.Count);
end;

procedure TPMLGLRenderDriver.RunCommandQueue(AQueue: TPMLRenderQueue);
var
  I: Integer;
  Cmd: TPMLRenderCommand;
begin
  BeginRun(AQueue);
  for I := 0 to AQueue.CommandCount - 1 do
  begin
    Cmd := AQueue.Commands[I];
    case Cmd.Kind of
      TPMLRenderCommandKind.SetViewport:
        begin
          FViewport := Cmd.Rect;
          FViewportDirty := True;
          FClipDirty := True;
        end;
      TPMLRenderCommandKind.SetClipRect:
        begin
          FClipOn := Cmd.Enabled;
          FClip := Cmd.Rect;
          FClipDirty := True;
        end;
      TPMLRenderCommandKind.Clear     : ExecClear(Cmd);
      TPMLRenderCommandKind.DrawPoints: ExecDraw(GL_POINTS, Cmd);
      TPMLRenderCommandKind.DrawLines : ExecDraw(GL_LINES, Cmd);
      TPMLRenderCommandKind.Geometry  : ExecDraw(GL_TRIANGLES, Cmd);
    else
      // NoOp / FillRects / Copy。FillRects と Copy はこのドライバが上書きしないので、
      // 三角形（Geometry）に書き換わってから来る。
    end;
  end;
  EndRun;
  CheckGLErrors('RunCommandQueue');
end;

{ ---- 読み戻しと表示 ---- }

{ 描画先の矩形を読む。結果の 1 行目が上。

  ウィンドウの既定のフレームバッファは下から数えるので、読む y を換算して、読んだ行を上下逆にする
  （SDL の GL_RenderReadPixels）。FBO は反転させていないので、そのまま読める。描画先のテクスチャを読むときは、
  結果の形式をそのテクスチャの形式にする（BGRA32 は GL_BGRA で読む）。

  PORT-NOTE: SDL は GL_PACK_ROW_LENGTH を設定して戻さない。ここは詰めた置き場に読んで行ごとに写すので、
  行の長さを触らない。矩形が描画先からはみ出す部分は、SDL では GL が何を返すか未定義。描画先と重なる部分だけを
  読み、はみ出す部分は 0（透明な黒）のままにする。 }
function TPMLGLRenderDriver.ReadPixels(const ARect: TPMLRect): TPMLSurface;
var
  OutW, OutH, X1, Y1, X2, Y2, W, H, Row, GLY: Integer;
  Buf: PByte;
  RowBytes: PtrUInt;
  Fmt: TPMLPixelFormat;
  ReadFormat: GLenum;
begin
  if FTarget <> nil then
    Fmt := FTarget.PixelFormat
  else
    Fmt := PML_PIXELFORMAT_RGBA32;
  if (Fmt = PML_PIXELFORMAT_BGRA32) or (Fmt = PML_PIXELFORMAT_BGRX32) then
    ReadFormat := GL_BGRA
  else
    ReadFormat := GL_RGBA;
  Result := TPMLSurface.Create(ARect.W, ARect.H, Fmt);
  try
    EnsureCurrent;
    ReadDrawableSize(OutW, OutH);
    X1 := Max(ARect.X, 0);
    Y1 := Max(ARect.Y, 0);
    X2 := Min(ARect.X + ARect.W, OutW);
    Y2 := Min(ARect.Y + ARect.H, OutH);
    W := X2 - X1;
    H := Y2 - Y1;
    if (W <= 0) or (H <= 0) then
      Exit;

    BindDrawFramebuffer;
    if FlipsOutput then
      GLY := OutH - Y1 - H
    else
      GLY := Y1;

    RowBytes := PtrUInt(W) * 4;
    Buf := GetMem(RowBytes * PtrUInt(H));
    try
      FGL.glPixelStorei(GL_PACK_ALIGNMENT, 1);
      FGL.glReadPixels(X1, GLY, W, H, ReadFormat, GL_UNSIGNED_BYTE, Buf);
      for Row := 0 to H - 1 do
      begin
        // 結果の行 (Y1 - ARect.Y + Row) に、読んだ上から Row 行目を置く。
        if FlipsOutput then
          Move((Buf + PtrUInt(H - 1 - Row) * RowBytes)^,
            (PByte(Result.Pixels) + PtrUInt(Y1 - ARect.Y + Row) * PtrUInt(Result.Pitch)
              + PtrUInt(X1 - ARect.X) * 4)^, RowBytes)
        else
          Move((Buf + PtrUInt(Row) * RowBytes)^,
            (PByte(Result.Pixels) + PtrUInt(Y1 - ARect.Y + Row) * PtrUInt(Result.Pitch)
              + PtrUInt(X1 - ARect.X) * 4)^, RowBytes);
      end;
    finally
      FreeMem(Buf);
    end;
    CheckGLErrors('ReadPixels');
  except
    Result.Free;
    raise;
  end;
end;

procedure TPMLGLRenderDriver.Present;
begin
  // オフスクリーンは見せる先が無い。
  if FWindow = nil then
    Exit;
  EnsureCurrent;
  FWindow.SwapGL;
end;

{ 0（待たない）と 1（画面の更新を待つ）を受け付ける。ウィンドウのバックエンドが受け付ければ -1（適応）も通る。
  オフスクリーンは 0 だけ。SDL は SDL_GL_SetSwapInterval のあと GetSwapInterval で読み直し、一致しなければ
  Unsupported を返す。 }
function TPMLGLRenderDriver.SetVSync(AInterval: Integer): Boolean;
begin
  if FContext = nil then
    Exit(AInterval = 0);
  Result := False;
  if (AInterval < -1) or (AInterval > 1) then
    Exit;
  EnsureCurrent;
  try
    FContext.SwapInterval := AInterval;
    Result := FContext.SwapInterval = AInterval;
  except
    on E: EPMLUnsupported do
      FLastNonFatalError := 'GL swap interval: ' + E.Message;
  end;
end;

{ ---- 登録 ---- }

{ GL で作ったウィンドウには、このドライバを GLES2 より先に選ぶ（SDL の render_drivers の並びは opengl が opengles2 より先）。
  作れなかったら、次のドライバ（GLES2、ソフトウェア）へ進む（CreateWindowDriver）。 }
function GLDriverPrefers(AWindow: TPMLWindow): Boolean;
begin
  Result := TPMLWindowFlag.OpenGL in AWindow.Flags;
end;

function CreateGLDriver(AWindow: TPMLWindow): TPMLRenderDriver;
begin
  Result := TPMLGLRenderDriver.CreateForWindow(AWindow);
end;

initialization
  PMLRegisterRenderDriver('opengl', 200, @GLDriverPrefers, @CreateGLDriver);

end.
