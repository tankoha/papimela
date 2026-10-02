{
  PaPiMeLa.Render.GLES2 — OpenGL ES 2.0 で描くレンダラドライバ

  Origin : ported from SDL (src/render/opengles2/SDL_render_gles2.c,
           src/render/opengles2/SDL_shaders_gles2.c)
           Scope: 頂点シェーダと単色・テクスチャ（ARGB / ABGR / XRGB / XBGR）の
           フラグメントシェーダ、合成モードから glBlendFunc への対応、
           ビューポートとクリップ矩形の GL への写し方（ウィンドウは上下反転）、
           点と線の +0.5 画素補正と線分の端を延ばす細工（延ばす量は SDL の
           1/4 画素でなく 0.75 画素。RESOLVED を参照）、
           テクスチャの作成・部分更新・破棄、画素の読み戻し。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.3、§11 #43

  WHAT:
    TPMLRenderDriver の GPU 版。ウィンドウ（EGL の面）か、窓の無い GL
    （Mesa の surfaceless）のオフスクリーンに描く。

  WHY:
    ソフトウェアのドライバは 640x400 で約 160 fps が上限だった（T-18）。同じ場面を
    このドライバで描くと約 21,800 fps（VSync なし、Radeon RX 9070）。

  RESOLVED:
    - 矩形の塗り（QueueFillRects）とテクスチャの転送（QueueCopy）は上書きしない。
      SDL の GLES2 レンダラもこの 2 つを NULL にしていて、三角形へ落とす既定の
      経路を使う。papimela では「仮想メソッドを上書きしない」だけで同じになる
    - 描画先は 2 通り。ウィンドウは GL のコンテキストを TPMLWindow.CreateGLContext
      で作り、既定のフレームバッファ（原点が左下）へ描く。オフスクリーンは
      EGL の surfaceless でコンテキストを作り、RGBA8 のテクスチャを付けた FBO へ描く。
      FBO は SDL の「描画先テクスチャ」と同じく上下を反転させない（メモリの 1 行目が
      画像の上）。読み戻しの向きはどちらも「1 行目が上」に揃える
    - 積み荷はすべて TPMLVertex（32 バイト）で積む。点と線も頂点にして、色を頂点ごとに
      持たせる。実行の頭で全頂点を 1 本の VBO に上げ、コマンドは glDrawArrays の
      first / count で参照する（SDL は VBO を使わずクライアント配列を使う）
    - どの操作も先頭でこのドライバのコンテキストを現在にする。アプリが別の
      コンテキストを現在にしていても、描画と破棄が他人の GL を壊さない
    - 点と線の座標は整数に切り捨ててから +0.5 する。ソフトウェアのドライバが
      Trunc するのと同じ画素になる（SDL は小数のまま +0.5）
    - 線分の終点は向きに沿って 0.75 画素延ばす。SDL の 1/4 画素では、Mesa（radeonsi）で
      軸に平行な線の最後の画素が落ちた（PORT-NOTE(bug) を QueueDrawLines に書いた）
    - 最近傍の標本で、画素の中心がテクセルの境目に来るときは、上のテクセルを選ぶ
      （ソフトウェアのラスタライザと同じ向き。頂点シェーダの 1/10000 テクセルの補正）
    - オフスクリーンの EGL ディスプレイは全ドライバで 1 つを数えて共有する。
      eglTerminate は参照を数えないので、ドライバごとに終了すると、ほかのドライバの
      コンテキストが巻き添えになる（実測: EGL_BAD_DISPLAY）

  NOT RESOLVED:
    - YUV・パレット（INDEX8）・外部テクスチャ（OES）・描画先テクスチャ・
      線形補間でないスケールモード（PIXELART）は未実装
    - コンテキスト喪失（GL_CONTEXT_LOST）への対応
    - 斜めの線は GL の線の規則（菱形の出口規則）で決まる。ブレゼンハムとは
      数画素ずれる

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Render.GLES2;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Render,
  PaPiMeLa.Platform.GLES2,
  PaPiMeLa.Platform.EGL;

type
  { フラグメントシェーダの種類。テクスチャの形式ごとに 1 つ（SDL の
    GLES2_IMAGESOURCE_xxx のうち、papimela が持つものだけ）。

      Solid: 頂点色そのもの
      ABGR : メモリ上の並びが R,G,B,A のテクスチャ（そのまま）
      ARGB : 並びが B,G,R,A（R と B を入れ替える）
      RGB  : 並びが B,G,R,X（R と B を入れ替え、A を 1 にする）
      BGR  : 並びが R,G,B,X（A を 1 にする） }
  TPMLGLES2Shader = (Solid, ABGR, ARGB, RGB, BGR);

  { リンク済みのプログラム。 }
  TPMLGLES2Program = record
    Id        : GLuint;
    Projection: GLint;      // u_projection の位置
    ProjGen   : Integer;    // 最後に送った射影行列の世代
    TexelSize : GLint;      // u_texel_size の位置
    TexelOwner: GLuint;     // u_texel_size を最後に設定したテクスチャ（0 = 未設定）
  end;

  TPMLGLES2RenderDriver = class(TPMLRenderDriver)
  strict private
    FGL        : TPMLGLES2Functions;
    // ウィンドウへ描くとき。FContext はウィンドウが所有するが、このドライバが作って
    // このドライバが壊す。オフスクリーンのときは両方 nil。
    FWindow    : TPMLWindow;
    FContext   : TPMLGLContext;
    // オフスクリーン（EGL の surfaceless）
    FEGLLoaded : Boolean;
    FDisplayHeld: Boolean;       // surfaceless のディスプレイを借りている
    FDisplay   : EGLDisplay;
    FEGLContext: EGLContext;
    FWidth     : Integer;
    FHeight    : Integer;
    FFBO       : GLuint;
    FTargetTex : GLuint;

    FPrograms  : array[TPMLGLES2Shader] of TPMLGLES2Program;
    FVBO       : GLuint;
    FVertexBuf : TPMLVertices;
    FMaxTexture: Integer;
    FLastNonFatalError: String;

    // 実行中の状態。RunCommandQueue の頭で作り直す。
    FDrawableW : Integer;
    FDrawableH : Integer;
    FViewport  : TPMLRect;
    FClip      : TPMLRect;
    FClipOn    : Boolean;
    FViewportDirty: Boolean;
    FClipDirty : Boolean;
    FScissorOn : Boolean;
    FProjection: array[0..15] of Single;
    FProjGen   : Integer;
    FShaderValid: Boolean;
    FCurShader : TPMLGLES2Shader;
    FBlendValid: Boolean;
    FCurBlend  : TPMLBlendMode;
    FBoundTexture: GLuint;

    procedure LoadFunctions(AGetProc: TPMLGLGetProc);
    procedure CreateSurfacelessContext;
    procedure CreateTargetFBO;
    procedure CreateResources;
    procedure ReleaseResources;
    function  CompileShader(AKind: GLenum; const ASource: String): GLuint;
    procedure BuildProgram(AShader: TPMLGLES2Shader; const AFragment: String;
      AVertexShader: GLuint);
    procedure EnsureCurrent;
    procedure ReadOutputSize(out AWidth, AHeight: Integer);
    procedure CheckGLErrors(const AWhere: String);
    procedure BeginRun(AQueue: TPMLRenderQueue);
    procedure ApplyViewport;
    procedure ApplyScissor;
    procedure ApplyBlend(ABlend: TPMLBlendMode);
    procedure UseShader(AShader: TPMLGLES2Shader);
    procedure ExecClear(const ACmd: TPMLRenderCommand);
    procedure ExecDraw(AMode: GLenum; const ACmd: TPMLRenderCommand);
  public
    { ウィンドウに描く。ウィンドウは TPMLWindowOptions.OpenGL で作ってあること
      （でなければ EPMLUnsupported）。GL のコンテキストはこのドライバが作って持つ。 }
    constructor CreateForWindow(AWindow: TPMLWindow);
    { 窓の無い GL（Mesa の EGL_PLATFORM_SURFACELESS_MESA）で、AWidth x AHeight の
      オフスクリーンに描く。検査用。使えない環境では EPMLUnsupported。
      Present は何もしない。 }
    constructor CreateOffscreen(AWidth, AHeight: Integer);
    destructor Destroy; override;

    function  Name: String; override;                 // 'gles2'
    function  GetOutputSize(out AWidth, AHeight: Integer): Boolean; override;
    function  SupportsBlendMode(AMode: TPMLBlendMode): Boolean; override;
    function  SupportsTextureFormat(AFormat: TPMLPixelFormat): Boolean; override;

    function  CreateTexture(ATexture: TPMLTexture): Boolean; override;
    function  UpdateTexture(ATexture: TPMLTexture; const ARect: TPMLRect;
      APixels: Pointer; APitch: Integer): Boolean; override;
    procedure DestroyTexture(ATexture: TPMLTexture); override;

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
  end;

implementation

uses
  Math;

const
  // Mesa の surfaceless プラットフォーム（EGL_MESA_platform_surfaceless）。
  // egl.h ではなく eglext.h の定数なので、生成した定数表には無い。
  EGL_PLATFORM_SURFACELESS_MESA = $31DD;

  // 頂点の属性の位置。シェーダのリンク前に glBindAttribLocation で固定する。
  ATTR_POSITION = 0;
  ATTR_COLOR    = 1;
  ATTR_TEXCOORD = 2;

  // 線分の終点を向きに沿って延ばす長さ（画素）。QueueDrawLines を参照。
  LINE_EXTEND = 0.75;

  LF = #10;

{ ---- シェーダのソース（SDL_shaders_gles2.c の GLSL ES をそのまま） ----

  PORT-NOTE: SDL の GLES2_Fragment_Include_Best_Texture_Precision に当たる前置きと、
  頂点シェーダ、単色、テクスチャ 4 種（RGB / BGR / ARGB / ABGR）だけを写した。
  ピクセルアート・パレット・YUV は持たない。精度を決めるマクロの名前だけ
  SDL_TEXCOORD_PRECISION から PML_TEXCOORD_PRECISION に変えた。

  PORT-NOTE: 頂点シェーダでテクスチャ座標に 1/10000 テクセルを足す（uniform
  u_texel_size = 1/幅, 1/高さ, 幅, 高さ。名前と並びは SDL のピクセルアート用の
  uniform と同じ）。画素の中心がちょうどテクセルの境目に来るとき（2.5 倍の拡大など）、
  GPU が補間した座標は境目の上下どちらにも転ぶ。ソフトウェアのラスタライザは
  Floor(u * 幅 + 1e-4) で境目を上のテクセルに寄せているので、GPU も同じ向きに
  寄せて、ドライバ間で同じ絵になるようにする。補間の誤差（約 1e-6 テクセル）より
  十分大きく、最近傍でも線形でも見た目を変えない大きさ。単色のプログラムでは
  uniform が 0 のままで、足されない。 }

  VertexSource =
    'uniform mat4 u_projection;' + LF +
    'uniform vec4 u_texel_size;' + LF +
    'attribute vec2 a_position;' + LF +
    'attribute vec4 a_color;' + LF +
    'attribute vec2 a_texCoord;' + LF +
    'varying vec2 v_texCoord;' + LF +
    'varying vec4 v_color;' + LF +
    LF +
    'void main()' + LF +
    '{' + LF +
    '    v_texCoord = a_texCoord + u_texel_size.xy * 0.0001;' + LF +
    '    gl_Position = u_projection * vec4(a_position, 0.0, 1.0);' + LF +
    '    gl_PointSize = 1.0;' + LF +
    '    v_color = a_color;' + LF +
    '}' + LF;

  FragmentPrecision =
    '#ifdef GL_FRAGMENT_PRECISION_HIGH' + LF +
    '#define PML_TEXCOORD_PRECISION highp' + LF +
    '#else' + LF +
    '#define PML_TEXCOORD_PRECISION mediump' + LF +
    '#endif' + LF +
    LF +
    'precision mediump float;' + LF +
    LF;

  TexturePrologue =
    'uniform sampler2D u_texture;' + LF +
    'varying mediump vec4 v_color;' + LF +
    'varying PML_TEXCOORD_PRECISION vec2 v_texCoord;' + LF +
    LF;

  FragmentSolid =
    'varying mediump vec4 v_color;' + LF +
    LF +
    'void main()' + LF +
    '{' + LF +
    '    gl_FragColor = v_color;' + LF +
    '}' + LF;

  // ABGR（メモリ上 R,G,B,A）はそのまま
  FragmentABGR =
    'void main()' + LF +
    '{' + LF +
    '    mediump vec4 color = texture2D(u_texture, v_texCoord);' + LF +
    '    gl_FragColor = color;' + LF +
    '    gl_FragColor *= v_color;' + LF +
    '}' + LF;

  // ARGB（メモリ上 B,G,R,A）→ ABGR
  FragmentARGB =
    'void main()' + LF +
    '{' + LF +
    '    mediump vec4 color = texture2D(u_texture, v_texCoord);' + LF +
    '    gl_FragColor = vec4(color.b, color.g, color.r, color.a);' + LF +
    '    gl_FragColor *= v_color;' + LF +
    '}' + LF;

  // RGB（メモリ上 B,G,R,X）→ ABGR。アルファは 1
  FragmentRGB =
    'void main()' + LF +
    '{' + LF +
    '    mediump vec4 color = texture2D(u_texture, v_texCoord);' + LF +
    '    gl_FragColor = vec4(color.b, color.g, color.r, 1.0);' + LF +
    '    gl_FragColor *= v_color;' + LF +
    '}' + LF;

  // BGR（メモリ上 R,G,B,X）→ ABGR。アルファは 1
  FragmentBGR =
    'void main()' + LF +
    '{' + LF +
    '    mediump vec4 color = texture2D(u_texture, v_texCoord);' + LF +
    '    gl_FragColor = vec4(color.r, color.g, color.b, 1.0);' + LF +
    '    gl_FragColor *= v_color;' + LF +
    '}' + LF;

type
  { テクスチャの中身（TPMLTexture.DriverData）。 }
  TPMLGLES2Texture = class
  public
    Id    : GLuint;
    Shader: TPMLGLES2Shader;
    Filter: TPMLScaleMode;     // GL に設定してある補間
    Width : Integer;
    Height: Integer;
  end;

var
  // PMLLoadGLES2Functions に渡す取得関数は C の関数ポインタ（cdecl）で、
  // 文脈を持てない。読み込みの間だけ、対象のコンテキストをここに置く。
  GLoaderContext: TPMLGLContext = nil;
  // surfaceless のディスプレイ（全ドライバで 1 つ）と、それを借りている数。
  GSurfacelessDisplay: EGLDisplay = nil;
  GSurfacelessRefs: Integer = 0;

function LoaderProc(AName: PAnsiChar): Pointer; cdecl;
begin
  if GLoaderContext = nil then
    Result := nil
  else
    Result := GLoaderContext.GetProcAddress(String(AName));
end;

// 空白区切りの拡張名の一覧に AExt が語として含まれるか。
function HasExtension(const AList, AExt: String): Boolean;
begin
  Result := Pos(' ' + AExt + ' ', ' ' + AList + ' ') > 0;
end;

{ surfaceless のディスプレイを 1 つ借りる。最初の 1 人が初期化する。

  Mesa は同じプラットフォームなら、何度 eglGetPlatformDisplay を呼んでも同じ
  EGLDisplay を返す。eglTerminate は参照を数えないので、ドライバごとに初期化と
  終了をすると、先に消えたドライバがほかのドライバのコンテキストを巻き添えにする
  （実測: EGL_BAD_DISPLAY）。このため、借りている数を自分で数え、最後の 1 人が
  返すときに終了する。足りないものがあれば、何が足りないかを文面にする。 }
function AcquireSurfacelessDisplay: EGLDisplay;
var
  Ext: PAnsiChar;
  Display: EGLDisplay;
  Major, Minor, Err: EGLint;
begin
  if GSurfacelessRefs > 0 then
  begin
    Inc(GSurfacelessRefs);
    Exit(GSurfacelessDisplay);
  end;

  Ext := eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
  if (Ext = nil) or not HasExtension(String(Ext), 'EGL_MESA_platform_surfaceless') then
    raise EPMLUnsupported.Create(
      'offscreen GLES2: the client extension EGL_MESA_platform_surfaceless is missing');

  Display := EGL_NO_DISPLAY;
  if Assigned(eglGetPlatformDisplayEXT) then
    Display := eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, nil, nil);
  if (Display = EGL_NO_DISPLAY) and Assigned(eglGetPlatformDisplay) then
    Display := eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, nil, nil);
  if Display = EGL_NO_DISPLAY then
    raise EPMLUnsupported.Create(
      'offscreen GLES2: could not get an EGL display for the surfaceless platform');

  Major := 0;
  Minor := 0;
  if eglInitialize(Display, @Major, @Minor) = EGL_FALSE then
  begin
    Err := eglGetError();
    raise EPMLUnsupported.CreateFmt('offscreen GLES2: eglInitialize failed (%s)',
      [PMLEGLErrorName(Err)]);
  end;

  Ext := eglQueryString(Display, EGL_EXTENSIONS);
  if (Ext = nil) or not HasExtension(String(Ext), 'EGL_KHR_surfaceless_context') then
  begin
    eglTerminate(Display);
    raise EPMLUnsupported.Create(
      'offscreen GLES2: the display extension EGL_KHR_surfaceless_context is missing');
  end;

  GSurfacelessDisplay := Display;
  GSurfacelessRefs := 1;
  Result := Display;
end;

procedure ReleaseSurfacelessDisplay;
begin
  if GSurfacelessRefs = 0 then
    Exit;
  Dec(GSurfacelessRefs);
  if GSurfacelessRefs = 0 then
  begin
    eglTerminate(GSurfacelessDisplay);
    GSurfacelessDisplay := EGL_NO_DISPLAY;
  end;
end;

function MakeVertex(AX, AY: Single; const AColor: TPMLFColor): TPMLVertex; inline;
begin
  Result.Position.X := AX;
  Result.Position.Y := AY;
  Result.Color := AColor;
  Result.TexCoord.X := 0;
  Result.TexCoord.Y := 0;
end;

{ テクスチャの形式からシェーダを決める。SDL の SetCopyState の「描画先が
  ウィンドウのとき」の分岐（形式 → 画像の出どころ）と同じ対応。
  BGRA32 などはバイト並びの名前なので、エンディアンに依らず正しい。 }
function ShaderForFormat(AFormat: TPMLPixelFormat;
  out AShader: TPMLGLES2Shader): Boolean;
begin
  Result := True;
  if AFormat = PML_PIXELFORMAT_BGRA32 then
    AShader := TPMLGLES2Shader.ARGB
  else if AFormat = PML_PIXELFORMAT_RGBA32 then
    AShader := TPMLGLES2Shader.ABGR
  else if AFormat = PML_PIXELFORMAT_BGRX32 then
    AShader := TPMLGLES2Shader.RGB
  else if AFormat = PML_PIXELFORMAT_RGBX32 then
    AShader := TPMLGLES2Shader.BGR
  else
  begin
    AShader := TPMLGLES2Shader.Solid;
    Result := False;
  end;
end;

function TextureData(ATexture: TPMLTexture): TPMLGLES2Texture; inline;
begin
  if (ATexture = nil) or not (ATexture.DriverData is TPMLGLES2Texture) then
    Result := nil
  else
    Result := TPMLGLES2Texture(ATexture.DriverData);
end;

{ ---- 作成と破棄 ---- }

constructor TPMLGLES2RenderDriver.CreateForWindow(AWindow: TPMLWindow);
begin
  inherited Create(nil, nil);
  FillChar(FGL, SizeOf(FGL), 0);
  if AWindow = nil then
    raise EPMLArgument.Create('the GLES2 render driver needs a window');
  if not (TPMLWindowFlag.OpenGL in AWindow.Flags) then
    raise EPMLUnsupported.Create(
      'the GLES2 render driver needs a window created with TPMLWindowOptions.OpenGL');
  FWindow := AWindow;
  FContext := AWindow.CreateGLContext;
  LoadFunctions(@LoaderProc);
  CreateResources;
end;

constructor TPMLGLES2RenderDriver.CreateOffscreen(AWidth, AHeight: Integer);
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
  LoadFunctions(eglGetProcAddress);
  CreateResources;
  CreateTargetFBO;
end;

destructor TPMLGLES2RenderDriver.Destroy;
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
      FLastNonFatalError := 'GLES2 cleanup failed: ' + E.Message;
  end;
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
      ReleaseSurfacelessDisplay;
    end;
    PMLEGLUnload;
  end;
  FContext := nil;
  FEGLContext := EGL_NO_CONTEXT;
  FDisplay := EGL_NO_DISPLAY;
  FEGLLoaded := False;
  FDisplayHeld := False;
  inherited Destroy;
end;

procedure TPMLGLES2RenderDriver.LoadFunctions(AGetProc: TPMLGLGetProc);
var
  Missing: String;
begin
  GLoaderContext := FContext;
  try
    Missing := PMLLoadGLES2Functions(AGetProc, FGL);
  finally
    GLoaderContext := nil;
  end;
  if Missing <> '' then
    raise EPMLUnsupported.Create('the GL implementation lacks GLES2 functions: ' + Missing);
end;

{ Mesa の surfaceless で ES 2.0 のコンテキストを作り、現在にする。

  WHAT:
    EGL_MESA_platform_surfaceless のディスプレイを借り、面を持たない
    （EGL_NO_SURFACE）コンテキストを作る。描く先は後で作る FBO。

  WHY:
    ウィンドウ（Wayland）が無い環境でも GPU のドライバを検査できる。
    足りないものがあれば、何が足りないかを EPMLUnsupported の文面にする。 }
procedure TPMLGLES2RenderDriver.CreateSurfacelessContext;
var
  Config: EGLConfig;
  Found, Err: EGLint;
  ConfigAttribs: array[0..4] of EGLint;
  ContextAttribs: array[0..2] of EGLint;
begin
  if not PMLEGLLoad then
    raise EPMLUnsupported.Create('offscreen GLES2: libEGL could not be loaded');
  FEGLLoaded := True;

  FDisplay := AcquireSurfacelessDisplay;
  FDisplayHeld := True;

  if eglBindAPI(EGL_OPENGL_ES_API) = EGL_FALSE then
  begin
    Err := eglGetError();
    raise EPMLUnsupported.CreateFmt('offscreen GLES2: eglBindAPI(OpenGL ES) failed (%s)',
      [PMLEGLErrorName(Err)]);
  end;

  // 面を作らないので、要るのは ES 2.0 の描画に対応することだけ。
  // EGL_SURFACE_TYPE の既定は WINDOW_BIT だが、surfaceless の設定は持たない。0 で
  // 「面の種類は問わない」にする。
  ConfigAttribs[0] := EGL_RENDERABLE_TYPE;
  ConfigAttribs[1] := EGL_OPENGL_ES2_BIT;
  ConfigAttribs[2] := EGL_SURFACE_TYPE;
  ConfigAttribs[3] := 0;
  ConfigAttribs[4] := EGL_NONE;
  Config := nil;
  Found := 0;
  if (eglChooseConfig(FDisplay, @ConfigAttribs[0], @Config, 1, @Found) = EGL_FALSE)
    or (Found = 0) then
  begin
    Err := eglGetError();
    raise EPMLUnsupported.CreateFmt(
      'offscreen GLES2: no EGL config for OpenGL ES 2.0 (found %d, %s)',
      [Found, PMLEGLErrorName(Err)]);
  end;

  ContextAttribs[0] := EGL_CONTEXT_CLIENT_VERSION;
  ContextAttribs[1] := 2;
  ContextAttribs[2] := EGL_NONE;
  FEGLContext := eglCreateContext(FDisplay, Config, EGL_NO_CONTEXT, @ContextAttribs[0]);
  if FEGLContext = EGL_NO_CONTEXT then
  begin
    Err := eglGetError();
    raise EPMLUnsupported.CreateFmt('offscreen GLES2: eglCreateContext failed (%s)',
      [PMLEGLErrorName(Err)]);
  end;

  if eglMakeCurrent(FDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, FEGLContext) = EGL_FALSE then
  begin
    Err := eglGetError();
    raise EPMLUnsupported.CreateFmt(
      'offscreen GLES2: eglMakeCurrent without a surface failed (%s)',
      [PMLEGLErrorName(Err)]);
  end;
end;

{ オフスクリーンの描画先。RGBA8 のテクスチャを付けた FBO。 }
procedure TPMLGLES2RenderDriver.CreateTargetFBO;
var
  Status: GLenum;
begin
  FGL.glGenTextures(1, @FTargetTex);
  FGL.glBindTexture(GL_TEXTURE_2D, FTargetTex);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  FGL.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, FWidth, FHeight, 0, GL_RGBA,
    GL_UNSIGNED_BYTE, nil);
  FGL.glGenFramebuffers(1, @FFBO);
  FGL.glBindFramebuffer(GL_FRAMEBUFFER, FFBO);
  FGL.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
    FTargetTex, 0);
  Status := FGL.glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if Status <> GL_FRAMEBUFFER_COMPLETE then
    raise EPMLUnsupported.CreateFmt(
      'offscreen GLES2: the framebuffer is incomplete (status 0x%x, %d x %d)',
      [Status, FWidth, FHeight]);
  // 中身を決めておく（透明な黒）。
  FGL.glClearColor(0, 0, 0, 0);
  FGL.glClear(GL_COLOR_BUFFER_BIT);
end;

function TPMLGLES2RenderDriver.CompileShader(AKind: GLenum;
  const ASource: String): GLuint;
var
  Src: PGLchar;
  Status, LogLen: GLint;
  Log: String;
begin
  Result := FGL.glCreateShader(AKind);
  Src := PGLchar(PAnsiChar(ASource));
  FGL.glShaderSource(Result, 1, @Src, nil);
  FGL.glCompileShader(Result);
  Status := 0;
  FGL.glGetShaderiv(Result, GL_COMPILE_STATUS, @Status);
  if Status = 0 then
  begin
    LogLen := 0;
    FGL.glGetShaderiv(Result, GL_INFO_LOG_LENGTH, @LogLen);
    Log := '';
    if LogLen > 1 then
    begin
      SetLength(Log, LogLen);
      FGL.glGetShaderInfoLog(Result, LogLen, @LogLen, PGLchar(Log));
      SetLength(Log, Length(PAnsiChar(Log)));
    end;
    FGL.glDeleteShader(Result);
    raise EPMLRenderError.CreateFmt('failed to compile a GLES2 shader: %s', [Log]);
  end;
end;

procedure TPMLGLES2RenderDriver.BuildProgram(AShader: TPMLGLES2Shader;
  const AFragment: String; AVertexShader: GLuint);
var
  Frag, Id: GLuint;
  Status, LogLen: GLint;
  Log: String;
begin
  Frag := CompileShader(GL_FRAGMENT_SHADER, AFragment);
  Id := FGL.glCreateProgram();
  FGL.glAttachShader(Id, AVertexShader);
  FGL.glAttachShader(Id, Frag);
  FGL.glBindAttribLocation(Id, ATTR_POSITION, 'a_position');
  FGL.glBindAttribLocation(Id, ATTR_COLOR, 'a_color');
  FGL.glBindAttribLocation(Id, ATTR_TEXCOORD, 'a_texCoord');
  FGL.glLinkProgram(Id);
  Status := 0;
  FGL.glGetProgramiv(Id, GL_LINK_STATUS, @Status);
  // シェーダオブジェクトはプログラムが持つので、ここで削除の印を付けてよい。
  FGL.glDeleteShader(Frag);
  if Status = 0 then
  begin
    LogLen := 0;
    FGL.glGetProgramiv(Id, GL_INFO_LOG_LENGTH, @LogLen);
    Log := '';
    if LogLen > 1 then
    begin
      SetLength(Log, LogLen);
      FGL.glGetProgramInfoLog(Id, LogLen, @LogLen, PGLchar(Log));
      SetLength(Log, Length(PAnsiChar(Log)));
    end;
    FGL.glDeleteProgram(Id);
    raise EPMLRenderError.CreateFmt('failed to link a GLES2 program: %s', [Log]);
  end;
  FPrograms[AShader].Id := Id;
  FPrograms[AShader].Projection := FGL.glGetUniformLocation(Id, 'u_projection');
  FPrograms[AShader].ProjGen := -1;
  FPrograms[AShader].TexelSize := FGL.glGetUniformLocation(Id, 'u_texel_size');
  FPrograms[AShader].TexelOwner := 0;
  // テクスチャは常にユニット 0。
  FGL.glUseProgram(Id);
  if AShader <> TPMLGLES2Shader.Solid then
    FGL.glUniform1i(FGL.glGetUniformLocation(Id, 'u_texture'), 0);
end;

{ プログラム、VBO、GL の固定の状態。コンテキストが現在であること。 }
procedure TPMLGLES2RenderDriver.CreateResources;
var
  Vertex: GLuint;
  Value: GLint;
begin
  FGL.glGetError();     // コンテキストを作るまでに溜まった誤りを捨てる

  Vertex := CompileShader(GL_VERTEX_SHADER, VertexSource);
  try
    BuildProgram(TPMLGLES2Shader.Solid, FragmentPrecision + FragmentSolid, Vertex);
    BuildProgram(TPMLGLES2Shader.ABGR, FragmentPrecision + TexturePrologue + FragmentABGR, Vertex);
    BuildProgram(TPMLGLES2Shader.ARGB, FragmentPrecision + TexturePrologue + FragmentARGB, Vertex);
    BuildProgram(TPMLGLES2Shader.RGB, FragmentPrecision + TexturePrologue + FragmentRGB, Vertex);
    BuildProgram(TPMLGLES2Shader.BGR, FragmentPrecision + TexturePrologue + FragmentBGR, Vertex);
  finally
    FGL.glDeleteShader(Vertex);
  end;

  Value := 0;
  FGL.glGetIntegerv(GL_MAX_TEXTURE_SIZE, @Value);
  FMaxTexture := Value;

  FGL.glGenBuffers(1, @FVBO);

  // 固定の状態。深度・カリング・ディザは使わない（ディザは 8 ビットの出力でも
  // 画素が動くことがあるので、検査の厳密な一致のために切る）。
  FGL.glDisable(GL_DEPTH_TEST);
  FGL.glDisable(GL_CULL_FACE);
  FGL.glDisable(GL_DITHER);
  FGL.glActiveTexture(GL_TEXTURE0);
  FGL.glPixelStorei(GL_PACK_ALIGNMENT, 1);
  FGL.glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  FGL.glEnableVertexAttribArray(ATTR_POSITION);
  FGL.glEnableVertexAttribArray(ATTR_COLOR);
  FGL.glEnableVertexAttribArray(ATTR_TEXCOORD);
  FGL.glClearColor(1, 1, 1, 1);

  FProjGen := 0;
  CheckGLErrors('initialization');
end;

{ GL の物を全部捨てる。テクスチャは TPMLTexture が先に捨てている。 }
procedure TPMLGLES2RenderDriver.ReleaseResources;
var
  S: TPMLGLES2Shader;
begin
  for S := Low(TPMLGLES2Shader) to High(TPMLGLES2Shader) do
    if FPrograms[S].Id <> 0 then
    begin
      FGL.glDeleteProgram(FPrograms[S].Id);
      FPrograms[S].Id := 0;
    end;
  if FVBO <> 0 then
    FGL.glDeleteBuffers(1, @FVBO);
  FVBO := 0;
  if FFBO <> 0 then
  begin
    FGL.glBindFramebuffer(GL_FRAMEBUFFER, 0);
    FGL.glDeleteFramebuffers(1, @FFBO);
  end;
  FFBO := 0;
  if FTargetTex <> 0 then
    FGL.glDeleteTextures(1, @FTargetTex);
  FTargetTex := 0;
end;

{ このドライバのコンテキストを現在にする。すでに現在なら何もしない。

  PORT-NOTE: SDL の GLES2_ActivateRenderer にあたる。SDL は SDL_GL_GetCurrentContext
  と比べるが、ここは EGL の現在のコンテキストと比べる（ウィンドウのときも
  PaPiMeLa.Video.EGL が同じ EGL を使っている）。MakeCurrent は Wayland では
  スワップ間隔の打ち消しと wl_display の flush を伴うので、現在なら省く。 }
procedure TPMLGLES2RenderDriver.EnsureCurrent;
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
    eglBindAPI(EGL_OPENGL_ES_API);
    if eglMakeCurrent(FDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, FEGLContext) = EGL_FALSE then
    begin
      Err := eglGetError();
      raise EPMLRenderError.CreateFmt('failed to make the GLES2 context current (%s)',
        [PMLEGLErrorName(Err)]);
    end;
  end;
end;

procedure TPMLGLES2RenderDriver.ReadOutputSize(out AWidth, AHeight: Integer);
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

{ GL の誤りを読んで捨てる。デバッグビルド（PAPIMELA_DEBUG）では例外にする。

  glGetError は誤りが溜まっている間は 1 回の呼び出しで 1 つずつ返すので、
  0 になるまで読む。 }
procedure TPMLGLES2RenderDriver.CheckGLErrors(const AWhere: String);
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
    raise EPMLRenderError.CreateFmt('GLES2 error after %s:%s', [AWhere, Codes]);
end;
{$else}
begin
end;
{$endif}

{ ---- 出力 ---- }

function TPMLGLES2RenderDriver.Name: String;
begin
  Result := 'gles2';
end;

function TPMLGLES2RenderDriver.GetOutputSize(out AWidth, AHeight: Integer): Boolean;
begin
  ReadOutputSize(AWidth, AHeight);
  Result := True;
end;

{ すべての合成モードを持つ。

  PORT-NOTE: SDL の GLES2_SupportsBlendMode は、任意の組み合わせ（SDL_ComposeCustomBlendMode）
  の係数と演算が GL に対応しているかを調べる。papimela の合成モードは 5 つの固定値で、
  どれも GLES2 の核だけで表せる（GL_EXT_blend_minmax は要らない）ので常に True。 }
function TPMLGLES2RenderDriver.SupportsBlendMode(AMode: TPMLBlendMode): Boolean;
begin
  Result := True;
end;

function TPMLGLES2RenderDriver.SupportsTextureFormat(AFormat: TPMLPixelFormat): Boolean;
var
  S: TPMLGLES2Shader;
begin
  Result := ShaderForFormat(AFormat, S);
end;

{ ---- テクスチャ ---- }

{ 形式に合ったテクスチャを作る。中身はすべて 0（透明な黒）にしておく。

  PORT-NOTE: SDL は中身を未定義のまま作る（glTexImage2D の画素が NULL）。ソフトウェアの
  ドライバは 0 で始まるので、GPU でも同じにして、未更新のテクスチャを描いたときの
  結果をそろえる。 }
function TPMLGLES2RenderDriver.CreateTexture(ATexture: TPMLTexture): Boolean;
var
  Data: TPMLGLES2Texture;
  Shader: TPMLGLES2Shader;
  Zero: Pointer;
  Size: PtrUInt;
  Err: GLenum;
begin
  Result := False;
  if not ShaderForFormat(ATexture.Format, Shader) then
    Exit;
  if (ATexture.Width > FMaxTexture) or (ATexture.Height > FMaxTexture) then
    Exit;
  EnsureCurrent;
  FGL.glGetError();
  Data := TPMLGLES2Texture.Create;
  Data.Shader := Shader;
  Data.Filter := TPMLScaleMode.Nearest;
  Data.Width := ATexture.Width;
  Data.Height := ATexture.Height;
  FGL.glGenTextures(1, @Data.Id);
  FGL.glBindTexture(GL_TEXTURE_2D, Data.Id);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  Size := PtrUInt(ATexture.Width) * PtrUInt(ATexture.Height) * 4;
  Zero := GetMem(Size);
  try
    FillChar(Zero^, Size, 0);
    FGL.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, ATexture.Width, ATexture.Height, 0,
      GL_RGBA, GL_UNSIGNED_BYTE, Zero);
  finally
    FreeMem(Zero);
  end;
  Err := FGL.glGetError();
  if Err <> GL_NO_ERROR then
  begin
    FGL.glDeleteTextures(1, @Data.Id);
    Data.Free;
    Exit;
  end;
  ATexture.DriverData := Data;
  Result := True;
end;

{ 矩形の部分を更新する。GLES2 の核には UNPACK_ROW_LENGTH が無いので、行の幅が
  詰まっていなければ詰め直した複製を作って 1 回で上げる（SDL の GLES2_TexSubImage2D と同じ）。 }
function TPMLGLES2RenderDriver.UpdateTexture(ATexture: TPMLTexture;
  const ARect: TPMLRect; APixels: Pointer; APitch: Integer): Boolean;
var
  Data: TPMLGLES2Texture;
  Blob: PByte;
  RowBytes: PtrUInt;
  Y: Integer;
begin
  Result := False;
  Data := TextureData(ATexture);
  if (Data = nil) or (APixels = nil) then
    Exit;
  if (ARect.X < 0) or (ARect.Y < 0) or (ARect.W <= 0) or (ARect.H <= 0)
  or (ARect.X + ARect.W > ATexture.Width) or (ARect.Y + ARect.H > ATexture.Height) then
    Exit;
  EnsureCurrent;
  FGL.glBindTexture(GL_TEXTURE_2D, Data.Id);
  RowBytes := PtrUInt(ARect.W) * 4;
  if PtrUInt(APitch) = RowBytes then
    FGL.glTexSubImage2D(GL_TEXTURE_2D, 0, ARect.X, ARect.Y, ARect.W, ARect.H,
      GL_RGBA, GL_UNSIGNED_BYTE, APixels)
  else
  begin
    Blob := GetMem(RowBytes * PtrUInt(ARect.H));
    try
      for Y := 0 to ARect.H - 1 do
        Move((PByte(APixels) + PtrUInt(Y) * PtrUInt(APitch))^,
          (Blob + PtrUInt(Y) * RowBytes)^, RowBytes);
      FGL.glTexSubImage2D(GL_TEXTURE_2D, 0, ARect.X, ARect.Y, ARect.W, ARect.H,
        GL_RGBA, GL_UNSIGNED_BYTE, Blob);
    finally
      FreeMem(Blob);
    end;
  end;
  // 次の実行は束縛を作り直す（BeginRun）ので、ここで元に戻さなくてよい。
  Result := True;
end;

procedure TPMLGLES2RenderDriver.DestroyTexture(ATexture: TPMLTexture);
var
  Data: TPMLGLES2Texture;
begin
  Data := TextureData(ATexture);
  if Data = nil then
    Exit;
  try
    EnsureCurrent;
    FGL.glDeleteTextures(1, @Data.Id);
  except
    on E: EPMLError do
      FLastNonFatalError := 'GLES2 texture cleanup failed: ' + E.Message;
  end;
  FreeAndNil(ATexture.DriverData);
end;

{ ---- 積み込み ---- }

procedure TPMLGLES2RenderDriver.QueueGeometry(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const AVertices: array of TPMLVertex);
begin
  ACmd.First := AQueue.AddVertices(AVertices);
  ACmd.Count := Length(AVertices);
end;

{ 点を 1 頂点にする。画素の中心に当てるため +0.5 する（SDL の GLES2_QueueDrawPoints）。

  PORT-NOTE: SDL は座標をそのまま +0.5 する。ソフトウェアのドライバは点を Trunc して
  画素に置くので、ここも切り捨ててから +0.5 し、小数の座標でも同じ画素を塗る。 }
procedure TPMLGLES2RenderDriver.QueueDrawPoints(AQueue: TPMLRenderQueue;
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

{ 折れ線を、線分ごとに 2 頂点（GL_LINES）にする。

  WHAT:
    始点は画素の中心（+0.5）。終点は中心から線の向きへ LINE_EXTEND 画素延ばす。

  WHY:
    終点を中心ちょうどに置くと、GL の線の規則（菱形の出口規則）で最後の画素が
    落ちる。SDL のコメントによれば、途中の画素が落ちることもある。

  PORT-NOTE(bug): SDL は 1/4 画素だけ延ばす。菱形の出口規則では、終点の画素の菱形
  （中心から |dx| + |dy| <= 0.5）の外へ線が出なければその画素は塗られないので、
  1/4 では足りない。水平・垂直の線では 0.5 を超える必要があり、実測（Mesa radeonsi）でも
  1/4 だと軸に平行な線の最後の画素が落ちた（0.4 でも落ちる）。0.5 を超え 1.0 未満
  （1.0 を超えると四角形で線を塗る実装が次の画素まで塗る）の中ほどとして 0.75 にする。
  延ばした先はまだ次の画素の菱形の中なので、塗る画素は増えない。

  PORT-NOTE: SDL は折れ線を 1 本の GL_LINE_STRIP にして、途中の頂点も延ばした位置を
  次の線分の始点にする（2 点だけの線は GL_LINES にまとめる）。ここは線分ごとに独立の
  2 頂点にする。キューが同じ状態の DrawLines を結合するので、折れ線の境目が
  分からなくなるため。継ぎ目の画素は線分ごとに塗られ、ソフトウェアのドライバ
  （両端を含むブレゼンハム）と同じく 2 回塗られる。座標は点と同じく切り捨てる。 }
procedure TPMLGLES2RenderDriver.QueueDrawLines(AQueue: TPMLRenderQueue;
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

{ 実行の頭。描画先を束縛し、状態をすべて未確定にして、頂点を VBO に上げる。

  Flush のたびにレンダラが状態コマンド（ビューポートとクリップ）を積み直すので、
  前の実行の状態を引き継がない。SDL の GLES2_InvalidateCachedState にあたる。 }
procedure TPMLGLES2RenderDriver.BeginRun(AQueue: TPMLRenderQueue);
var
  I: Integer;
  S: TPMLGLES2Shader;
begin
  EnsureCurrent;
  ReadOutputSize(FDrawableW, FDrawableH);

  if FWindow <> nil then
    FGL.glBindFramebuffer(GL_FRAMEBUFFER, 0)
  else
    FGL.glBindFramebuffer(GL_FRAMEBUFFER, FFBO);

  FViewport := TPMLRect.Make(0, 0, FDrawableW, FDrawableH);
  FClipOn := False;
  FViewportDirty := True;
  FClipDirty := True;
  FGL.glDisable(GL_SCISSOR_TEST);
  FScissorOn := False;
  FGL.glDisable(GL_BLEND);
  FBlendValid := False;
  FShaderValid := False;
  FBoundTexture := 0;
  // テクスチャの id は破棄のあとで使い回されるので、大きさの設定は持ち越さない。
  for S := Low(TPMLGLES2Shader) to High(TPMLGLES2Shader) do
    FPrograms[S].TexelOwner := 0;

  if AQueue.VertexCount > 0 then
  begin
    if Length(FVertexBuf) < AQueue.VertexCount then
      SetLength(FVertexBuf, AQueue.VertexCount * 2);
    for I := 0 to AQueue.VertexCount - 1 do
      FVertexBuf[I] := AQueue.Vertex(I);
    FGL.glBindBuffer(GL_ARRAY_BUFFER, FVBO);
    // 毎回作り直す。前の実行のデータを GPU が読み終わるのを待たせない。
    FGL.glBufferData(GL_ARRAY_BUFFER, AQueue.VertexCount * SizeOf(TPMLVertex),
      @FVertexBuf[0], GL_STREAM_DRAW);
    FGL.glVertexAttribPointer(ATTR_POSITION, 2, GL_FLOAT, GL_FALSE, SizeOf(TPMLVertex),
      Pointer(PtrUInt(0)));
    FGL.glVertexAttribPointer(ATTR_COLOR, 4, GL_FLOAT, GL_FALSE, SizeOf(TPMLVertex),
      Pointer(PtrUInt(SizeOf(TPMLFPoint))));
    FGL.glVertexAttribPointer(ATTR_TEXCOORD, 2, GL_FLOAT, GL_FALSE, SizeOf(TPMLVertex),
      Pointer(PtrUInt(SizeOf(TPMLFPoint) + SizeOf(TPMLFColor))));
  end;
end;

{ ビューポートと射影行列。

  ビューポートの中の座標は、ビューポートの左上を原点とする画素。
  ウィンドウの既定のフレームバッファは原点が左下なので、上下を反転する
  （glViewport の y を下から数え直し、射影行列の y の符号を逆にする）。
  FBO は反転させない。SDL の SetDrawState と同じ。 }
procedure TPMLGLES2RenderDriver.ApplyViewport;
var
  Y, W, H: Integer;
  Sign: Single;
begin
  if not FViewportDirty then
    Exit;
  W := Max(FViewport.W, 0);
  H := Max(FViewport.H, 0);
  if FWindow <> nil then
    Y := FDrawableH - FViewport.Y - H
  else
    Y := FViewport.Y;
  FGL.glViewport(FViewport.X, Y, W, H);
  if (W > 0) and (H > 0) then
  begin
    if FWindow <> nil then
      Sign := -1
    else
      Sign := 1;
    FillChar(FProjection, SizeOf(FProjection), 0);
    FProjection[0] := 2.0 / W;
    FProjection[5] := Sign * 2.0 / H;
    FProjection[12] := -1.0;
    FProjection[13] := -Sign;
    FProjection[15] := 1.0;
    Inc(FProjGen);
  end;
  FViewportDirty := False;
end;

{ クリップ矩形（ビューポートの原点からの相対）をシザーにする。
  実際に塗る範囲は「ビューポート ∩ クリップ」で、ビューポートの外は GL のクリップが
  切るので、シザーはクリップ矩形を平行移動しただけでよい。 }
procedure TPMLGLES2RenderDriver.ApplyScissor;
var
  X, Y, W, H: Integer;
begin
  if not FClipOn then
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
    W := Max(FClip.W, 0);
    H := Max(FClip.H, 0);
    X := FViewport.X + FClip.X;
    if FWindow <> nil then
      Y := FDrawableH - FViewport.Y - FClip.Y - H
    else
      Y := FViewport.Y + FClip.Y;
    FGL.glScissor(X, Y, W, H);
    FClipDirty := False;
  end;
end;

{ 合成モード → glBlendFuncSeparate / glBlendEquationSeparate。

  PORT-NOTE: SDL の GetBlendFunc / GetBlendEquation は SDL_BlendFactor / SDL_BlendOperation を
  GL の列挙子に写す。papimela の合成モードは 5 つの固定値なので、対応表を直接持つ。
  係数は SDL_render.h の定義（SDL_BLENDMODE_xxx の式）と同じ。
  アルファの係数は、式の「dstA」の欄に合わせる（Blend は srcA + dstA * (1 - srcA)、
  ほかは dstA のまま）。 }
procedure TPMLGLES2RenderDriver.ApplyBlend(ABlend: TPMLBlendMode);
begin
  if FBlendValid and (FCurBlend = ABlend) then
    Exit;
  case ABlend of
    TPMLBlendMode.None:
      FGL.glDisable(GL_BLEND);
    TPMLBlendMode.Blend:
      begin
        FGL.glEnable(GL_BLEND);
        FGL.glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA,
          GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
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
    FGL.glBlendEquationSeparate(GL_FUNC_ADD, GL_FUNC_ADD);
  FCurBlend := ABlend;
  FBlendValid := True;
end;

procedure TPMLGLES2RenderDriver.UseShader(AShader: TPMLGLES2Shader);
begin
  if (not FShaderValid) or (FCurShader <> AShader) then
  begin
    FGL.glUseProgram(FPrograms[AShader].Id);
    FCurShader := AShader;
    FShaderValid := True;
  end;
  if FPrograms[AShader].ProjGen <> FProjGen then
  begin
    if FPrograms[AShader].Projection <> -1 then
      FGL.glUniformMatrix4fv(FPrograms[AShader].Projection, 1, GL_FALSE, @FProjection[0]);
    FPrograms[AShader].ProjGen := FProjGen;
  end;
end;

{ 描画先全体を塗る。ビューポートもクリップも無視する。
  glClear はビューポートに従わないが、シザーには従うので、先に切る。 }
procedure TPMLGLES2RenderDriver.ExecClear(const ACmd: TPMLRenderCommand);
begin
  FGL.glClearColor(ACmd.Color.R, ACmd.Color.G, ACmd.Color.B, ACmd.Color.A);
  if FScissorOn then
  begin
    FGL.glDisable(GL_SCISSOR_TEST);
    FScissorOn := False;
  end;
  FGL.glClear(GL_COLOR_BUFFER_BIT);
end;

{ 積み荷 [First, First + Count) を AMode で描く。キューが同じ状態の描画を
  すでに 1 つのコマンドにまとめているので、1 コマンド = 1 回の glDrawArrays。 }
procedure TPMLGLES2RenderDriver.ExecDraw(AMode: GLenum; const ACmd: TPMLRenderCommand);
var
  Data: TPMLGLES2Texture;
  Shader: TPMLGLES2Shader;
  Filter: GLint;
begin
  Data := nil;
  Shader := TPMLGLES2Shader.Solid;
  if ACmd.Texture <> nil then
  begin
    Data := TextureData(ACmd.Texture);
    if Data = nil then
      Exit;       // 破棄されたテクスチャ。描くものが無い
    Shader := Data.Shader;
  end;
  if ACmd.Count <= 0 then
    Exit;

  ApplyViewport;
  ApplyScissor;
  UseShader(Shader);
  ApplyBlend(ACmd.Blend);

  if Data <> nil then
  begin
    if FBoundTexture <> Data.Id then
    begin
      FGL.glBindTexture(GL_TEXTURE_2D, Data.Id);
      FBoundTexture := Data.Id;
    end;
    if (FPrograms[Shader].TexelOwner <> Data.Id) and (FPrograms[Shader].TexelSize <> -1) then
    begin
      FGL.glUniform4f(FPrograms[Shader].TexelSize, 1.0 / Data.Width, 1.0 / Data.Height,
        Data.Width, Data.Height);
      FPrograms[Shader].TexelOwner := Data.Id;
    end;
    if Data.Filter <> ACmd.ScaleMode then
    begin
      if ACmd.ScaleMode = TPMLScaleMode.Linear then
        Filter := GL_LINEAR
      else
        Filter := GL_NEAREST;
      FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, Filter);
      FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, Filter);
      Data.Filter := ACmd.ScaleMode;
    end;
  end;

  FGL.glDrawArrays(AMode, ACmd.First, ACmd.Count);
end;

procedure TPMLGLES2RenderDriver.RunCommandQueue(AQueue: TPMLRenderQueue);
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
  CheckGLErrors('RunCommandQueue');
end;

{ ---- 読み戻しと表示 ---- }

{ 描画先の矩形を読む。結果の 1 行目が上。

  ウィンドウの既定のフレームバッファは下から数えるので、読む y を換算して、
  読んだ行を上下逆にする（SDL の GLES2_RenderReadPixels）。FBO は反転させて
  いないので、そのまま読める。

  PORT-NOTE: 矩形が描画先からはみ出す部分は、SDL では GL が何を返すか未定義。
  ここは描画先と重なる部分だけを読み、はみ出す部分は 0（透明な黒）のままにする。 }
function TPMLGLES2RenderDriver.ReadPixels(const ARect: TPMLRect): TPMLSurface;
var
  OutW, OutH, X1, Y1, X2, Y2, W, H, Row, GLY: Integer;
  Buf: PByte;
  RowBytes: PtrUInt;
begin
  Result := TPMLSurface.Create(ARect.W, ARect.H, PML_PIXELFORMAT_RGBA32);
  try
    EnsureCurrent;
    ReadOutputSize(OutW, OutH);
    X1 := Max(ARect.X, 0);
    Y1 := Max(ARect.Y, 0);
    X2 := Min(ARect.X + ARect.W, OutW);
    Y2 := Min(ARect.Y + ARect.H, OutH);
    W := X2 - X1;
    H := Y2 - Y1;
    if (W <= 0) or (H <= 0) then
      Exit;

    if FWindow <> nil then
    begin
      FGL.glBindFramebuffer(GL_FRAMEBUFFER, 0);
      GLY := OutH - Y1 - H;
    end
    else
    begin
      FGL.glBindFramebuffer(GL_FRAMEBUFFER, FFBO);
      GLY := Y1;
    end;

    RowBytes := PtrUInt(W) * 4;
    Buf := GetMem(RowBytes * PtrUInt(H));
    try
      FGL.glReadPixels(X1, GLY, W, H, GL_RGBA, GL_UNSIGNED_BYTE, Buf);
      for Row := 0 to H - 1 do
      begin
        // 結果の行 (Y1 - ARect.Y + Row) に、読んだ上から Row 行目を置く。
        if FWindow <> nil then
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

procedure TPMLGLES2RenderDriver.Present;
begin
  // オフスクリーンは見せる先が無い。
  if FWindow = nil then
    Exit;
  EnsureCurrent;
  FWindow.SwapGL;
end;

{ 0（待たない）と 1（画面の更新を待つ）を受け付ける。ウィンドウのバックエンドが
  受け付ければ -1（適応）も通る。オフスクリーンは 0 だけ。

  PORT-NOTE: SDL は SDL_GL_SetSwapInterval のあと SDL_GL_GetSwapInterval で読み直し、
  一致しなければ Unsupported を返す。TPMLGLContext.SwapInterval の設定は、受け付けない
  値なら EPMLUnsupported を投げるので、それを False に換える。 }
function TPMLGLES2RenderDriver.SetVSync(AInterval: Integer): Boolean;
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
      FLastNonFatalError := 'GLES2 swap interval: ' + E.Message;
  end;
end;

{ ---- 登録 ---- }

function GLES2DriverPrefers(AWindow: TPMLWindow): Boolean;
begin
  Result := TPMLWindowFlag.OpenGL in AWindow.Flags;
end;

function CreateGLES2Driver(AWindow: TPMLWindow): TPMLRenderDriver;
begin
  Result := TPMLGLES2RenderDriver.CreateForWindow(AWindow);
end;

initialization
  PMLRegisterRenderDriver('gles2', 100, @GLES2DriverPrefers, @CreateGLES2Driver);

end.
