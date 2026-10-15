{
  PaPiMeLa.Render.GLES2 — OpenGL ES 2.0 で描くレンダラドライバ

  Origin : ported from SDL (src/render/opengles2/SDL_render_gles2.c,
           src/render/opengles2/SDL_shaders_gles2.c)
           Scope: 頂点シェーダと単色・テクスチャ（ARGB / ABGR / XRGB / XBGR）の
           フラグメントシェーダ、パレット（INDEX8）のフラグメントシェーダ
           （最近傍と線形、BGRA / BGRX の描画先向けの R と B の入れ替え付き）、
           パレットの写し（256x1 のテクスチャ）の作成・更新・破棄、
           YUV（YV12 / IYUV / NV12 / NV21）のテクスチャの作成・更新（詰めた画素と平面ごと）・
           破棄と、変換のフラグメントシェーダ（R と B の入れ替え付き）、
           合成モードから glBlendFunc への対応、
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
    - INDEX8 のテクスチャは GL_LUMINANCE の 1 バイト 1 画素で持つ。色はパレットの写し
      （256x1 の RGBA テクスチャ。ユニット 1）をシェーダで引く。写しは白の不透明で
      始めるので、アプリのパレットの外の添字は白で描かれる（ソフトウェアのドライバと同じ）。
      線形補間はシェーダで 4 つの添字の色を混ぜる。添字のテクスチャの補間は常に最近傍
    - 描画先のテクスチャ（SetRenderTarget）は、テクスチャごとに自分を付けた FBO を持つ。
      FBO のメモリはテクスチャの形式の並びで書く（BGRA32 / BGRX32 の描画先には色の R と B を
      入れ替えて渡す）ので、あとでそのテクスチャを描くときも、形式どおりに読める。
      描画元と描画先の形式の組で選ぶシェーダは CopyShader の PORT-NOTE を参照

    - YV12 / IYUV / NV12 / NV21 は、平面ごとの GL テクスチャで持ち、変換はシェーダで行う
      （SupportsTextureFormat が True を返すので、レンダラの ARGB8888 の肩代わりを通らない）。
      Y はユニット 0、U（NV は UV）はユニット 1、V はユニット 2。色差は縦横とも半分の
      大きさ（奇数は切り上げ）。NV の UV は GL_LUMINANCE_ALPHA（SDL の既定の RA 版）。
      色空間ごとの行列は SDL の SDL_GetYCbCRtoRGBConversionMatrix の値のまま。補間
      （Linear）は全部の平面に掛ける。YUY2 / UYVY / YVYU / P010 / I444 は持たない
      （レンダラの肩代わりか、作成の拒否）
    - 変換の結果は 0..1 に挟んでから頂点の色を掛ける（SDL は挟まない。
      ソフトウェアのドライバは先に ARGB8888 へ直して挟むので、それに合わせる）
    - 補間なし（Nearest / PixelArt）の YUV は、色差のテクセルをシェーダで「輝度のテクセル
      n の n div 2 番」に決める。SDL のように輝度と同じ正規化した座標で読むと、幅か高さが
      奇数のとき、ソフトウェアのドライバ（n div 2）と違う色差を引く（幅 7 で n = 5 は
      2 番でなく 3 番）。詳しくは YUVPrologue の PORT-NOTE
    - SDL の YUV のシェーダには colorswap が無い。BGRA32 / BGRX32 の描画先に R と B を
      入れ替えて書くので、YUV にも入れ替え版（YUVSwap / NV12Swap / NV21Swap）を持つ

  NOT RESOLVED:
    - 外部テクスチャ（OES）は未実装。PIXELART は最近傍と同じ
    - 補間あり（Linear）の YUV は SDL と同じく、色差を輝度と同じ正規化した座標で読む。
      幅か高さが奇数のときの色差の位置は、色差のテクスチャが (n + 1) div 2 の大きさの
      ぶん、半画素に満たない程度ずれる。ソフトウェアのドライバの Linear は Nearest なので、
      比べる相手がない
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
  PaPiMeLa.Surface.YUV,
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
      BGR  : 並びが R,G,B,X（A を 1 にする）
      PalNearest    : INDEX8。パレットの色をそのまま（最近傍）
      PalLinear     : INDEX8。4 つの添字の色を混ぜる（線形）
      PalNearestSwap: PalNearest の R と B を入れ替える（BGRA32 / BGRX32 の描画先）
      PalLinearSwap : PalLinear の R と B を入れ替える
      YUV      : YV12 / IYUV。Y・U・V の 3 平面を変換する
      NV12     : Y と、U,V の順に詰めた UV の平面を変換する
      NV21     : Y と、V,U の順に詰めた平面を変換する
      YUVSwap, NV12Swap, NV21Swap: それぞれの R と B を入れ替える

    並びの注意: YUV 系はパレット系より前に置く（IsPaletteShader が順序で判定する）。 }
  TPMLGLES2Shader = (Solid, ABGR, ARGB, RGB, BGR,
    YUV, NV12, NV21, YUVSwap, NV12Swap, NV21Swap,
    PalNearest, PalLinear, PalNearestSwap, PalLinearSwap);

  { リンク済みのプログラム。 }
  TPMLGLES2Program = record
    Id        : GLuint;
    Projection: GLint;      // u_projection の位置
    ProjGen   : Integer;    // 最後に送った射影行列の世代
    TexelSize : GLint;      // u_texel_size の位置
    TexelOwner: GLuint;     // u_texel_size を最後に設定したテクスチャ（0 = 未設定）
    // YUV 系だけ。変換のパラメータ（u_offset, u_rcoeff, u_gcoeff, u_bcoeff）の位置と、
    // 最後に設定した変換の種類（TPMLYCbCrType の序数。-1 = 未設定）
    YUVOffset : GLint;
    YUVRCoeff : GLint;
    YUVGCoeff : GLint;
    YUVBCoeff : GLint;
    YUVKind   : Integer;
    // 色差の座標を輝度のテクセルの 2x2 の区画に寄せるか（u_chroma_snap）の位置と、
    // 最後に設定した値（0 / 1。-1 = 未設定）
    YUVSnap   : GLint;
    YUVSnapState: Integer;
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
    FBoundTexture: GLuint;     // ユニット 0 に束縛したテクスチャ（0 = 未設定）
    // ユニット 1 に束縛したもの（0 = 未設定）。パレットの写し、または YUV の U（NV は UV）の平面。
    // GL のテクスチャの id は生きている間は重ならないので、1 つの変数で見分けられる
    FBoundUnit1: GLuint;
    FBoundUnit2: GLuint;       // ユニット 2 に束縛した YUV の V の平面（0 = 未設定）
    // 描画先のテクスチャ（SetRenderTarget）。nil はウィンドウかオフスクリーンの FBO。
    FTarget    : TObject;

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
    procedure ReadDrawableSize(out AWidth, AHeight: Integer);
    function  FlipsOutput: Boolean;
    function  TargetSwapsRB: Boolean;
    procedure BindDrawFramebuffer;
    procedure CheckGLErrors(const AWhere: String);
    procedure BeginRun(AQueue: TPMLRenderQueue);
    procedure ApplyViewport;
    procedure ApplyScissor;
    procedure ApplyBlend(ABlend: TPMLBlendMode);
    procedure UseShader(AShader: TPMLGLES2Shader);
    function  CreatePlane(AWidth, AHeight: Integer; AGLFormat: GLenum;
      ABytesPerTexel: PtrUInt; out AId: GLuint): Boolean;
    procedure UploadPlane(AId: GLuint; AX, AY, AWidth, AHeight: Integer;
      AGLFormat: GLenum; APixels: Pointer; APitch: Integer; ABytesPerTexel: PtrUInt);
    procedure BindUnit(AUnit: GLenum; AId: GLuint);
    procedure SetPlaneFilter(AFilter: GLint);
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
  頂点シェーダ、単色、テクスチャ 4 種（RGB / BGR / ARGB / ABGR）、パレット 4 種
  （最近傍 / 線形 と、それぞれの colorswap）、YUV 3 種（YUV / NV12_RA / NV21_RA と、
  それぞれの colorswap）だけを写した。
  ピクセルアート・NV12 の RG 版は持たない。精度を決めるマクロの名前だけ
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

  { パレット（INDEX8）のシェーダ。SDL の PALETTE_SHADER_PROLOGUE と PALETTE_SHADER_FUNCTIONS、
    GLES2_Fragment_TexturePalette_Nearest / Linear（と _Colorswap）。

    PORT-NOTE: u_texel_size の精度を、SDL の mediump でなく
    PML_TEXCOORD_PRECISION（highp が使えれば highp）にした。papimela の頂点シェーダも
    この uniform を宣言していて（精度の指定なし = highp）、頂点と断片で精度が
    食い違うと、リンクを通さない実装があるため。 }
  PalettePrologue =
    'uniform sampler2D u_texture;' + LF +
    'uniform sampler2D u_palette;' + LF +
    'uniform PML_TEXCOORD_PRECISION vec4 u_texel_size;' + LF +
    'varying mediump vec4 v_color;' + LF +
    'varying PML_TEXCOORD_PRECISION vec2 v_texCoord;' + LF +
    LF;

  PaletteFunctions =
    'mediump vec4 SamplePaletteNearest(PML_TEXCOORD_PRECISION vec2 uv)' + LF +
    '{' + LF +
    '    mediump float index = texture2D(u_texture, uv).r * 255.0;' + LF +
    '    return texture2D(u_palette, vec2((index + 0.5) / 256.0, 0.5));' + LF +
    '}' + LF +
    LF +
    'mediump vec4 SamplePaletteLinear(PML_TEXCOORD_PRECISION vec2 uv)' + LF +
    '{' + LF +
    '    // scale & offset uvs to integer values at texel centers' + LF +
    '    PML_TEXCOORD_PRECISION vec2 uv_texels = uv * u_texel_size.zw + 0.5;' + LF +
    LF +
    '    // get uvs for the center of the 4 surrounding texels by flooring' + LF +
    '    PML_TEXCOORD_PRECISION vec4 uv_min_max = vec4((floor(uv_texels) - 0.5) * u_texel_size.xy, (floor(uv_texels) + 0.5) * u_texel_size.xy);' + LF +
    LF +
    '    // blend factor' + LF +
    '    PML_TEXCOORD_PRECISION vec2 uv_frac = fract(uv_texels);' + LF +
    LF +
    '    // sample all 4 texels' + LF +
    '    mediump vec4 texelA = SamplePaletteNearest(uv_min_max.xy);' + LF +
    '    mediump vec4 texelB = SamplePaletteNearest(uv_min_max.xw);' + LF +
    '    mediump vec4 texelC = SamplePaletteNearest(uv_min_max.zy);' + LF +
    '    mediump vec4 texelD = SamplePaletteNearest(uv_min_max.zw);' + LF +
    LF +
    '    // bilinear interpolation' + LF +
    '    return mix(mix(texelA, texelB, uv_frac.y), mix(texelC, texelD, uv_frac.y), uv_frac.x);' + LF +
    '}' + LF +
    LF;

  FragmentPalNearest =
    LF +
    'void main()' + LF +
    '{' + LF +
    '    mediump vec4 color = SamplePaletteNearest(v_texCoord);' + LF +
    '    gl_FragColor = color;' + LF +
    '    gl_FragColor *= v_color;' + LF +
    '}' + LF;

  FragmentPalNearestSwap =
    LF +
    'void main()' + LF +
    '{' + LF +
    '    mediump vec4 color = SamplePaletteNearest(v_texCoord);' + LF +
    '    gl_FragColor = vec4(color.b, color.g, color.r, color.a);' + LF +
    '    gl_FragColor *= v_color;' + LF +
    '}' + LF;

  FragmentPalLinear =
    LF +
    'void main()' + LF +
    '{' + LF +
    '    mediump vec4 color = SamplePaletteLinear(v_texCoord);' + LF +
    '    gl_FragColor = color;' + LF +
    '    gl_FragColor *= v_color;' + LF +
    '}' + LF;

  FragmentPalLinearSwap =
    LF +
    'void main()' + LF +
    '{' + LF +
    '    mediump vec4 color = SamplePaletteLinear(v_texCoord);' + LF +
    '    gl_FragColor = vec4(color.b, color.g, color.r, color.a);' + LF +
    '    gl_FragColor *= v_color;' + LF +
    '}' + LF;

  { YUV のシェーダ。SDL の YUV_SHADER_PROLOGUE と YUV_SHADER_BODY、NV12_RA_SHADER_BODY、
    NV21_RA_SHADER_BODY（GLES2_Fragment_TextureYUV / NV12_RA / NV21_RA）。
    本体は「平面を読む」「変換する」「出力する（colorswap の有無）」の 3 つの断片を
    つなげて作る。

    PORT-NOTE: SDL の u_matrix（mat3）の代わりに、行ごとの vec3 を 3 つ（u_rcoeff,
    u_gcoeff, u_bcoeff）持つ。SDL は rgb = yuv * u_matrix（行列の列 = 各係数の行）なので、
    rgb.r = dot(yuv, u_rcoeff) と同じ計算。SDL の変換の結果は lowp の vec3 で、挟まずに
    頂点の色を掛ける。ここは mediump で受けて 0..1 に挟んでから掛ける。ソフトウェアの
    ドライバは先に ARGB8888 に直す（挟まれる）ので、色の変調や合成の結果をそろえるため。

    PORT-NOTE: 補間なし（最近傍と PixelArt）のとき、色差は u_texel_size を使って座標を
    自分で決める。輝度のテクセルの番号 n に対し、色差は n div 2 番のテクセルの中心。
    SDL は輝度と同じ正規化した座標で色差を読むので、幅か高さが奇数のとき、色差の
    テクスチャが (n + 1) div 2 の大きさであるぶん、選ぶテクセルが n div 2 からずれる
    （幅 7 で n = 5 は、2 番でなく 3 番を引く）。ソフトウェアのドライバ（SDL_SW_YUVTexture と
    同じ n div 2）と同じ絵にするための変更。偶数の大きさでは SDL と同じテクセルを選ぶ。
    Linear は SDL どおり輝度と同じ座標（GL が混ぜる）。切り替えは u_chroma_snap。

    PORT-NOTE: SDL の YUV のシェーダには colorswap が無い。papimela は BGRA32 / BGRX32 の
    描画先に R と B を入れ替えて書くので（TargetSwapsRB）、YUV にも入れ替え版を持つ。 }
  YUVPrologue =
    'uniform sampler2D u_texture;' + LF +
    'uniform sampler2D u_texture_u;' + LF +
    'uniform sampler2D u_texture_v;' + LF +
    'uniform vec3 u_offset;' + LF +
    'uniform vec3 u_rcoeff;' + LF +
    'uniform vec3 u_gcoeff;' + LF +
    'uniform vec3 u_bcoeff;' + LF +
    'uniform PML_TEXCOORD_PRECISION vec4 u_texel_size;' + LF +
    'uniform int u_chroma_snap;' + LF +
    'varying mediump vec4 v_color;' + LF +
    'varying PML_TEXCOORD_PRECISION vec2 v_texCoord;' + LF +
    LF +
    'void main()' + LF +
    '{' + LF +
    '    mediump vec3 yuv;' + LF +
    '    mediump vec3 rgb;' + LF +
    LF +
    '    // Chroma coordinate. Nearest: the 2x2 block of the luma texel (x div 2),' + LF +
    '    // as the software converter does. Linear: the same coordinate as luma.' + LF +
    '    PML_TEXCOORD_PRECISION vec2 uv_c = v_texCoord;' + LF +
    '    if (u_chroma_snap != 0) {' + LF +
    '        PML_TEXCOORD_PRECISION vec2 luma = floor(v_texCoord * u_texel_size.zw);' + LF +
    '        uv_c = (floor(luma * 0.5) + 0.5) / floor((u_texel_size.zw + 1.0) * 0.5);' + LF +
    '    }' + LF +
    LF +
    '    // Get the YUV values' + LF;

  YUVSamplePlanar =
    '    yuv.x = texture2D(u_texture,   v_texCoord).r;' + LF +
    '    yuv.y = texture2D(u_texture_u, uv_c).r;' + LF +
    '    yuv.z = texture2D(u_texture_v, uv_c).r;' + LF;

  YUVSampleNV12 =
    '    yuv.x = texture2D(u_texture,   v_texCoord).r;' + LF +
    '    yuv.yz = texture2D(u_texture_u, uv_c).ra;' + LF;

  YUVSampleNV21 =
    '    yuv.x = texture2D(u_texture,   v_texCoord).r;' + LF +
    '    yuv.yz = texture2D(u_texture_u, uv_c).ar;' + LF;

  YUVTransform =
    LF +
    '    // Do the color transform' + LF +
    '    yuv += u_offset;' + LF +
    '    rgb = clamp(vec3(dot(yuv, u_rcoeff), dot(yuv, u_gcoeff), dot(yuv, u_bcoeff)), 0.0, 1.0);' + LF +
    LF;

  YUVOutput =
    '    gl_FragColor = vec4(rgb, 1.0);' + LF +
    '    gl_FragColor *= v_color;' + LF +
    '}' + LF;

  YUVOutputSwap =
    '    gl_FragColor = vec4(rgb.b, rgb.g, rgb.r, 1.0);' + LF +
    '    gl_FragColor *= v_color;' + LF +
    '}' + LF;

type
  { テクスチャの中身（TPMLTexture.DriverData）。 }
  TPMLGLES2Texture = class
  public
    Id    : GLuint;
    FBO   : GLuint;            // 描画先にできるテクスチャ（Access = Target）だけ。ほかは 0
    Filter: TPMLScaleMode;     // GL に設定してある補間
    Width : Integer;
    Height: Integer;
    Format: TPMLPixelFormat;
    // メモリ上の並びが B,G,R の順（BGRA32 / BGRX32）か。GL の RGBA とは R と B が逆
    BFirst  : Boolean;
    // アルファを持つ（BGRA32 / RGBA32）か。X の形式は A を 1 として読む
    HasAlpha: Boolean;
    // INDEX8（GL_LUMINANCE の 1 バイト 1 画素）か。BFirst と HasAlpha は意味を持たない。
    // 補間は作成時から GL_NEAREST のまま変えない（線形はシェーダで混ぜる）
    Indexed : Boolean;
    // YV12 / IYUV（3 平面）か、NV12 / NV21（Y と UV の 2 平面）か。どちらも Format で決まる。
    // 補間は平面ごとのテクスチャすべてに同じ値を掛ける
    Planar  : Boolean;
    NV      : Boolean;
    // 色差の平面。Planar は IdU に U、IdV に V（メモリの並びが YV12 の V,U でも、
    // 中身で決める）。NV は IdU に UV（GL_LUMINANCE_ALPHA）。ほかは 0
    IdU     : GLuint;
    IdV     : GLuint;
    // 変換の種類（行列の表の添字）。YUV のときだけ意味を持つ
    YCbCr   : TPMLYCbCrType;
    { Lock の置き場（SDL の pixel_data）。Streaming のテクスチャだけが持ち、0 で始まる。Update は
      ここへ書かない（SDL と同じ）ので、Lock した置き場の中身は Update した絵とは限らない。
      Unlock が全体をここから GPU へ上げる。YUV は Y の平面のあとに色差の平面が続く。 }
    PixelData : TBytes;
    PixelPitch: Integer;
  end;

  { パレットの写し（TPMLTexturePalette.DriverData）。256x1 の RGBA テクスチャ。 }
  TPMLGLES2Palette = class
  public
    Id: GLuint;
  end;

const
  { YUV → RGB の係数。SDL_pixels.c の mat_BT601_Full_8bit などの値のまま（各行の 4 つ目の
    0.0f は使わないので省いた）。1 種類 12 個: オフセット(Y, U, V)、R の係数、G の係数、
    B の係数。並びは TPMLYCbCrType と同じ。

    PORT-NOTE: SDL の BT.2020 の全範囲の行列は 10 ビット用（オフセットが -0.500488759）。
    SDL は 8 ビットの形式にも同じ表を使うので、ここも同じ値を使う。限定範囲の BT.2020 は
    PMLYCbCrTypeOf が受け付けないので持たない。 }
  YUVMatrix: array[TPMLYCbCrType] of array[0..11] of Single = (
    // BT601Full
    (0.0, -0.501960814, -0.501960814,
     1.0000, 0.0000, 1.4075,
     1.0000, -0.3455, -0.7169,
     1.0000, 1.7790, 0.0000),
    // BT601Limited
    (-0.0627451017, -0.501960814, -0.501960814,
     1.1644, 0.0000, 1.5960,
     1.1644, -0.3918, -0.8130,
     1.1644, 2.0172, 0.0000),
    // BT709Full
    (0.0, -0.501960814, -0.501960814,
     1.0000, 0.0000, 1.5810,
     1.0000, -0.1881, -0.4700,
     1.0000, 1.8629, 0.0000),
    // BT709Limited
    (-0.0627451017, -0.501960814, -0.501960814,
     1.1644, 0.0000, 1.7927,
     1.1644, -0.2132, -0.5329,
     1.1644, 2.1124, 0.0000),
    // BT2020Full
    (0.0, -0.500488759, -0.500488759,
     1.0000, 0.0000, 1.4760,
     1.0000, -0.1647, -0.5719,
     1.0000, 1.8832, 0.0000));

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

{ テクスチャの形式のメモリ上の並び。持てない形式なら False。
  BGRA32 などはバイト並びの名前なので、エンディアンに依らず正しい。 }
function LayoutOfFormat(AFormat: TPMLPixelFormat; out ABFirst, AHasAlpha: Boolean): Boolean;
begin
  Result := True;
  ABFirst := (AFormat = PML_PIXELFORMAT_BGRA32) or (AFormat = PML_PIXELFORMAT_BGRX32);
  AHasAlpha := (AFormat = PML_PIXELFORMAT_BGRA32) or (AFormat = PML_PIXELFORMAT_RGBA32);
  if not (ABFirst or AHasAlpha or (AFormat = PML_PIXELFORMAT_RGBX32)) then
    Result := False;
end;

{ テクスチャを描くシェーダ。

  WHAT:
    テクスチャのメモリの並びを、描画先のメモリの並びへ写す。R と B の位置が
    違えば入れ替え、テクスチャにアルファが無ければ 1 にする。描画先が
    ウィンドウかオフスクリーンの FBO なら、並びは GL の R,G,B,A（ATargetBFirst = False）。

  PORT-NOTE: SDL の SetCopyState は、描画先がテクスチャのとき（形式の組 → 画像の出どころ）
  の表を持つ。papimela は上の 2 つの規則から算出する。結果は SDL の表と、X の形式の
  テクスチャを X の形式の描画先（と BGRX32 を RGBA32）へ描く組でだけ違う。SDL はそこで
  X のバイトをアルファとして読む（ARGB / ABGR の出どころ）。papimela は A を 1 にして、
  ソフトウェアのドライバ（X の形式は不透明）と同じ絵にする。 }
function CopyShader(ATexBFirst, ATexHasAlpha, ATargetBFirst: Boolean): TPMLGLES2Shader;
begin
  if ATexBFirst <> ATargetBFirst then
  begin
    if ATexHasAlpha then
      Result := TPMLGLES2Shader.ARGB
    else
      Result := TPMLGLES2Shader.RGB;
  end
  else if ATexHasAlpha then
    Result := TPMLGLES2Shader.ABGR
  else
    Result := TPMLGLES2Shader.BGR;
end;

{ このドライバが平面で持つ YUV の形式（平面ごとに分かれる 4 つ）か。 }
function IsPlanarYUVFormat(AFormat: TPMLPixelFormat): Boolean; inline;
begin
  Result := (AFormat = PML_PIXELFORMAT_YV12) or (AFormat = PML_PIXELFORMAT_IYUV)
    or (AFormat = PML_PIXELFORMAT_NV12) or (AFormat = PML_PIXELFORMAT_NV21);
end;

{ 形式の主な平面（YUV は Y）の 1 画素のバイト数（INDEX8 と YUV は 1、ほかは RGBA の 4）。 }
function BytesPerTexel(AFormat: TPMLPixelFormat): PtrUInt; inline;
begin
  if (AFormat = PML_PIXELFORMAT_INDEX8) or IsPlanarYUVFormat(AFormat) then
    Result := 1
  else
    Result := 4;
end;

function IsPaletteShader(AShader: TPMLGLES2Shader): Boolean; inline;
begin
  Result := AShader >= TPMLGLES2Shader.PalNearest;
end;

function IsYUVShader(AShader: TPMLGLES2Shader): Boolean; inline;
begin
  Result := (AShader >= TPMLGLES2Shader.YUV) and (AShader < TPMLGLES2Shader.PalNearest);
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
  FPrograms[AShader].YUVOffset := -1;
  FPrograms[AShader].YUVRCoeff := -1;
  FPrograms[AShader].YUVGCoeff := -1;
  FPrograms[AShader].YUVBCoeff := -1;
  FPrograms[AShader].YUVKind := -1;
  FPrograms[AShader].YUVSnap := -1;
  FPrograms[AShader].YUVSnapState := -1;
  // テクスチャは常にユニット 0、パレットの写しと YUV の U（NV は UV）はユニット 1、
  // YUV の V はユニット 2。
  FGL.glUseProgram(Id);
  if AShader <> TPMLGLES2Shader.Solid then
    FGL.glUniform1i(FGL.glGetUniformLocation(Id, 'u_texture'), 0);
  if IsPaletteShader(AShader) then
    FGL.glUniform1i(FGL.glGetUniformLocation(Id, 'u_palette'), 1);
  if IsYUVShader(AShader) then
  begin
    FGL.glUniform1i(FGL.glGetUniformLocation(Id, 'u_texture_u'), 1);
    // NV12 / NV21 のシェーダは u_texture_v を使わない（位置は -1 で、設定は無視される）
    FGL.glUniform1i(FGL.glGetUniformLocation(Id, 'u_texture_v'), 2);
    FPrograms[AShader].YUVOffset := FGL.glGetUniformLocation(Id, 'u_offset');
    FPrograms[AShader].YUVRCoeff := FGL.glGetUniformLocation(Id, 'u_rcoeff');
    FPrograms[AShader].YUVGCoeff := FGL.glGetUniformLocation(Id, 'u_gcoeff');
    FPrograms[AShader].YUVBCoeff := FGL.glGetUniformLocation(Id, 'u_bcoeff');
    FPrograms[AShader].YUVSnap := FGL.glGetUniformLocation(Id, 'u_chroma_snap');
  end;
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
    BuildProgram(TPMLGLES2Shader.YUV,
      FragmentPrecision + YUVPrologue + YUVSamplePlanar + YUVTransform + YUVOutput, Vertex);
    BuildProgram(TPMLGLES2Shader.NV12,
      FragmentPrecision + YUVPrologue + YUVSampleNV12 + YUVTransform + YUVOutput, Vertex);
    BuildProgram(TPMLGLES2Shader.NV21,
      FragmentPrecision + YUVPrologue + YUVSampleNV21 + YUVTransform + YUVOutput, Vertex);
    BuildProgram(TPMLGLES2Shader.YUVSwap,
      FragmentPrecision + YUVPrologue + YUVSamplePlanar + YUVTransform + YUVOutputSwap, Vertex);
    BuildProgram(TPMLGLES2Shader.NV12Swap,
      FragmentPrecision + YUVPrologue + YUVSampleNV12 + YUVTransform + YUVOutputSwap, Vertex);
    BuildProgram(TPMLGLES2Shader.NV21Swap,
      FragmentPrecision + YUVPrologue + YUVSampleNV21 + YUVTransform + YUVOutputSwap, Vertex);
    BuildProgram(TPMLGLES2Shader.PalNearest,
      FragmentPrecision + PalettePrologue + PaletteFunctions + FragmentPalNearest, Vertex);
    BuildProgram(TPMLGLES2Shader.PalLinear,
      FragmentPrecision + PalettePrologue + PaletteFunctions + FragmentPalLinear, Vertex);
    BuildProgram(TPMLGLES2Shader.PalNearestSwap,
      FragmentPrecision + PalettePrologue + PaletteFunctions + FragmentPalNearestSwap, Vertex);
    BuildProgram(TPMLGLES2Shader.PalLinearSwap,
      FragmentPrecision + PalettePrologue + PaletteFunctions + FragmentPalLinearSwap, Vertex);
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

{ いま描いている先の大きさ。描画先のテクスチャがあればその大きさ。 }
procedure TPMLGLES2RenderDriver.ReadDrawableSize(out AWidth, AHeight: Integer);
begin
  if FTarget <> nil then
  begin
    AWidth := TPMLGLES2Texture(FTarget).Width;
    AHeight := TPMLGLES2Texture(FTarget).Height;
  end
  else
    ReadOutputSize(AWidth, AHeight);
end;

{ いま描いている先が、原点が左下のウィンドウの既定のフレームバッファか。
  FBO（オフスクリーンと描画先のテクスチャ）は上下を反転させない。 }
function TPMLGLES2RenderDriver.FlipsOutput: Boolean;
begin
  Result := (FWindow <> nil) and (FTarget = nil);
end;

{ いま描いている先のメモリの並びが B,G,R（描画先が BGRA32 / BGRX32 のテクスチャ）か。
  GL は R,G,B,A の順に書くので、頂点の色と塗りの色の R と B を入れ替えて渡す
  （SDL の colorswap）。 }
function TPMLGLES2RenderDriver.TargetSwapsRB: Boolean;
begin
  Result := (FTarget <> nil) and TPMLGLES2Texture(FTarget).BFirst;
end;

procedure TPMLGLES2RenderDriver.BindDrawFramebuffer;
begin
  if FTarget <> nil then
    FGL.glBindFramebuffer(GL_FRAMEBUFFER, TPMLGLES2Texture(FTarget).FBO)
  else if FWindow <> nil then
    FGL.glBindFramebuffer(GL_FRAMEBUFFER, 0)
  else
    FGL.glBindFramebuffer(GL_FRAMEBUFFER, FFBO);
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

{ YV12 / IYUV / NV12 / NV21 は平面ごとのテクスチャで持つ（SDL の GLES2 も同じ 4 つに
  I444 を加えて持つ）。YUY2 / UYVY / YVYU / P010 / I444 は持たない。 }
function TPMLGLES2RenderDriver.SupportsTextureFormat(AFormat: TPMLPixelFormat): Boolean;
var
  BFirst, HasAlpha: Boolean;
begin
  Result := (AFormat = PML_PIXELFORMAT_INDEX8)
    or IsPlanarYUVFormat(AFormat)
    or LayoutOfFormat(AFormat, BFirst, HasAlpha);
end;

{ ---- テクスチャ ---- }

{ 1 枚の平面のテクスチャを、ユニット 0 に束縛して作る。補間は最近傍、端は CLAMP_TO_EDGE、
  中身はすべて 0。AId は失敗しても（作れた分は）返すので、呼び出し側が消す。
  GL の誤りがなければ True。 }
function TPMLGLES2RenderDriver.CreatePlane(AWidth, AHeight: Integer; AGLFormat: GLenum;
  ABytesPerTexel: PtrUInt; out AId: GLuint): Boolean;
var
  Zero: Pointer;
  Size: PtrUInt;
begin
  AId := 0;
  FGL.glGenTextures(1, @AId);
  FGL.glBindTexture(GL_TEXTURE_2D, AId);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  Size := PtrUInt(AWidth) * PtrUInt(AHeight) * ABytesPerTexel;
  Zero := GetMem(Size);
  try
    FillChar(Zero^, Size, 0);
    FGL.glTexImage2D(GL_TEXTURE_2D, 0, AGLFormat, AWidth, AHeight, 0,
      AGLFormat, GL_UNSIGNED_BYTE, Zero);
  finally
    FreeMem(Zero);
  end;
  Result := FGL.glGetError() = GL_NO_ERROR;
end;

{ 平面 AId の矩形 (AX, AY, AWidth, AHeight) を更新する。いまのユニットに束縛する。
  GLES2 の核には UNPACK_ROW_LENGTH が無いので、行の幅が詰まっていなければ詰め直した複製を
  作って 1 回で上げる（SDL の GLES2_TexSubImage2D と同じ）。ABytesPerTexel は 1 画素のバイト数
  （LUMINANCE は 1、LUMINANCE_ALPHA は 2、RGBA は 4）。 }
procedure TPMLGLES2RenderDriver.UploadPlane(AId: GLuint; AX, AY, AWidth, AHeight: Integer;
  AGLFormat: GLenum; APixels: Pointer; APitch: Integer; ABytesPerTexel: PtrUInt);
var
  Blob: PByte;
  RowBytes: PtrUInt;
  Y: Integer;
begin
  FGL.glBindTexture(GL_TEXTURE_2D, AId);
  RowBytes := PtrUInt(AWidth) * ABytesPerTexel;
  if PtrUInt(APitch) = RowBytes then
    FGL.glTexSubImage2D(GL_TEXTURE_2D, 0, AX, AY, AWidth, AHeight,
      AGLFormat, GL_UNSIGNED_BYTE, APixels)
  else
  begin
    Blob := GetMem(RowBytes * PtrUInt(AHeight));
    try
      for Y := 0 to AHeight - 1 do
        Move((PByte(APixels) + PtrUInt(Y) * PtrUInt(APitch))^,
          (Blob + PtrUInt(Y) * RowBytes)^, RowBytes);
      FGL.glTexSubImage2D(GL_TEXTURE_2D, 0, AX, AY, AWidth, AHeight,
        AGLFormat, GL_UNSIGNED_BYTE, Blob);
    finally
      FreeMem(Blob);
    end;
  end;
end;

{ ユニット AUnit に AId を束縛して、ユニット 0 に戻す。 }
procedure TPMLGLES2RenderDriver.BindUnit(AUnit: GLenum; AId: GLuint);
begin
  FGL.glActiveTexture(AUnit);
  FGL.glBindTexture(GL_TEXTURE_2D, AId);
  FGL.glActiveTexture(GL_TEXTURE0);
end;

{ いまのユニットに束縛してあるテクスチャの補間を設定する。 }
procedure TPMLGLES2RenderDriver.SetPlaneFilter(AFilter: GLint);
begin
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, AFilter);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, AFilter);
end;

{ 形式に合ったテクスチャを作る。中身はすべて 0（透明な黒）にしておく。

  YV12 / IYUV は Y・U・V の 3 枚（GL_LUMINANCE。U と V は縦横とも (n + 1) div 2）、
  NV12 / NV21 は Y（GL_LUMINANCE）と UV（GL_LUMINANCE_ALPHA、同じ半分の大きさ）の 2 枚
  （SDL の GLES2_CreateTexture）。色空間は作るときに変換の種類へ決める。

  PORT-NOTE: SDL は中身を未定義のまま作る（glTexImage2D の画素が NULL）。ソフトウェアの
  ドライバは 0 で始まるので、GPU でも同じにして、未更新のテクスチャを描いたときの
  結果をそろえる。 }
function TPMLGLES2RenderDriver.CreateTexture(ATexture: TPMLTexture): Boolean;
var
  Data: TPMLGLES2Texture;
  BFirst, HasAlpha, Indexed, Planar, NV, Created: Boolean;
  YCbCr: TPMLYCbCrType;
  CW, CH: Integer;
  GLFormat: GLenum;
  Size: PtrUInt;
begin
  Result := False;
  Indexed := ATexture.Format = PML_PIXELFORMAT_INDEX8;
  Planar := (ATexture.Format = PML_PIXELFORMAT_YV12) or (ATexture.Format = PML_PIXELFORMAT_IYUV);
  NV := (ATexture.Format = PML_PIXELFORMAT_NV12) or (ATexture.Format = PML_PIXELFORMAT_NV21);
  YCbCr := TPMLYCbCrType.BT601Limited;
  if Indexed then
  begin
    BFirst := False;
    HasAlpha := False;
  end
  else if Planar or NV then
  begin
    BFirst := False;
    HasAlpha := False;
    // YUV は描画先にできない。色空間に変換の行列が無ければ作らない
    if ATexture.Access = TPMLTextureAccess.Target then
      Exit;
    if not PMLYCbCrTypeOf(ATexture.Colorspace, YCbCr) then
      Exit;
  end
  else if not LayoutOfFormat(ATexture.Format, BFirst, HasAlpha) then
    Exit;
  if (ATexture.Width > FMaxTexture) or (ATexture.Height > FMaxTexture) then
    Exit;
  EnsureCurrent;
  FGL.glGetError();
  Data := TPMLGLES2Texture.Create;
  Data.Format := ATexture.Format;
  Data.BFirst := BFirst;
  Data.HasAlpha := HasAlpha;
  Data.Indexed := Indexed;
  Data.Planar := Planar;
  Data.NV := NV;
  Data.YCbCr := YCbCr;
  Data.Filter := TPMLScaleMode.Nearest;
  Data.Width := ATexture.Width;
  Data.Height := ATexture.Height;
  // INDEX8 と YUV の Y は GL_LUMINANCE（SDL の GLES2_CreateTexture と同じ）。1 バイトが R に読める
  if Indexed or Planar or NV then
    GLFormat := GL_LUMINANCE
  else
    GLFormat := GL_RGBA;
  Created := CreatePlane(ATexture.Width, ATexture.Height, GLFormat,
    BytesPerTexel(ATexture.Format), Data.Id);
  if Planar or NV then
  begin
    CW := (ATexture.Width + 1) div 2;
    CH := (ATexture.Height + 1) div 2;
    if Planar then
    begin
      Created := CreatePlane(CW, CH, GL_LUMINANCE, 1, Data.IdU) and Created;
      Created := CreatePlane(CW, CH, GL_LUMINANCE, 1, Data.IdV) and Created;
    end
    else
      Created := CreatePlane(CW, CH, GL_LUMINANCE_ALPHA, 2, Data.IdU) and Created;
  end;
  if Created and (ATexture.Access = TPMLTextureAccess.Target) then
  begin
    // 描画先にできるテクスチャは、自分を付けた FBO を持つ（SDL の GLES2_CreateTexture）。
    FGL.glGenFramebuffers(1, @Data.FBO);
    FGL.glBindFramebuffer(GL_FRAMEBUFFER, Data.FBO);
    FGL.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, Data.Id, 0);
    if FGL.glCheckFramebufferStatus(GL_FRAMEBUFFER) <> GL_FRAMEBUFFER_COMPLETE then
      Created := False;
    BindDrawFramebuffer;
  end;
  if not Created then
  begin
    if Data.FBO <> 0 then
      FGL.glDeleteFramebuffers(1, @Data.FBO);
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
    Data.PixelPitch := ATexture.Width * Integer(BytesPerTexel(ATexture.Format));
    Size := PtrUInt(ATexture.Height) * PtrUInt(Data.PixelPitch);
    if Planar or NV then
      // Y の平面のあとに色差の平面が続く大きさ（Update が読む並びと同じ。SDL の計算と同じ値）
      PMLCalculateYUVSize(ATexture.Format, ATexture.Width, ATexture.Height, Size, Data.PixelPitch);
    SetLength(Data.PixelData, Size);
    FillChar(Data.PixelData[0], Size, 0);
  end;
  ATexture.DriverData := Data;
  Result := True;
end;

{ Lock の置き場を渡す（SDL の GLES2_LockTexture）。 }
function TPMLGLES2RenderDriver.LockTexture(ATexture: TPMLTexture; const ARect: TPMLRect;
  out APixels: Pointer; out APitch: Integer): Boolean;
var
  Data: TPMLGLES2Texture;
begin
  APixels := nil;
  APitch := 0;
  Data := TextureData(ATexture);
  Result := (Data <> nil) and (Length(Data.PixelData) > 0);
  if not Result then
    Exit;
  APitch := Data.PixelPitch;
  APixels := @Data.PixelData[0] + PtrUInt(ARect.Y) * PtrUInt(Data.PixelPitch)
    + PtrUInt(ARect.X) * BytesPerTexel(ATexture.Format);
end;

{ 置き場の全体を GPU へ上げる（SDL の GLES2_UnlockTexture。「全体を更新する。今のところ」）。 }
procedure TPMLGLES2RenderDriver.UnlockTexture(ATexture: TPMLTexture);
var
  Data: TPMLGLES2Texture;
begin
  Data := TextureData(ATexture);
  if (Data = nil) or (Length(Data.PixelData) = 0) then
    Exit;
  UpdateTexture(ATexture, TPMLRect.Make(0, 0, ATexture.Width, ATexture.Height),
    @Data.PixelData[0], Data.PixelPitch);
end;

{ 矩形の部分を更新する。行の幅が詰まっていないときの詰め直しは UploadPlane。

  YUV（YV12 / IYUV / NV12 / NV21）は詰めた画素で来る（PMLCalculateYUVSize と同じ並び）。
  ARect の Y が ARect.H 行、続いて色差の平面が、行の幅 (APitch + 1) div 2（NV は
  UV を交互に詰めた 2 * ((APitch + 1) div 2)）で ((ARect.H + 1) div 2) 行ずつ。
  YV12 は V、U の順、IYUV は U、V の順（SDL の GLES2_UpdateTexture）。 }
function TPMLGLES2RenderDriver.UpdateTexture(ATexture: TPMLTexture;
  const ARect: TPMLRect; APixels: Pointer; APitch: Integer): Boolean;
var
  Data: TPMLGLES2Texture;
  GLFormat: GLenum;
  Src: PByte;
  ChromaPitch, CX, CY, CW, CH: Integer;
  First, Second: GLuint;
begin
  Result := False;
  Data := TextureData(ATexture);
  if (Data = nil) or (APixels = nil) then
    Exit;
  if (ARect.X < 0) or (ARect.Y < 0) or (ARect.W <= 0) or (ARect.H <= 0)
  or (ARect.X + ARect.W > ATexture.Width) or (ARect.Y + ARect.H > ATexture.Height) then
    Exit;
  EnsureCurrent;
  if Data.Planar or Data.NV then
  begin
    FGL.glGetError();
    UploadPlane(Data.Id, ARect.X, ARect.Y, ARect.W, ARect.H, GL_LUMINANCE, APixels, APitch, 1);
    CX := ARect.X div 2;
    CY := ARect.Y div 2;
    CW := (ARect.W + 1) div 2;
    CH := (ARect.H + 1) div 2;
    ChromaPitch := (APitch + 1) div 2;
    // 色差の平面は、Y の ARect.H 行のあと
    Src := PByte(APixels) + PtrInt(ARect.H) * PtrInt(APitch);
    if Data.Planar then
    begin
      if Data.Format = PML_PIXELFORMAT_YV12 then
      begin
        First := Data.IdV;
        Second := Data.IdU;
      end
      else
      begin
        First := Data.IdU;
        Second := Data.IdV;
      end;
      UploadPlane(First, CX, CY, CW, CH, GL_LUMINANCE, Src, ChromaPitch, 1);
      Src := Src + PtrInt(CH) * PtrInt(ChromaPitch);
      UploadPlane(Second, CX, CY, CW, CH, GL_LUMINANCE, Src, ChromaPitch, 1);
    end
    else
      UploadPlane(Data.IdU, CX, CY, CW, CH, GL_LUMINANCE_ALPHA, Src, 2 * ChromaPitch, 2);
    Result := FGL.glGetError() = GL_NO_ERROR;
    Exit;
  end;
  if Data.Indexed then
    GLFormat := GL_LUMINANCE
  else
    GLFormat := GL_RGBA;
  UploadPlane(Data.Id, ARect.X, ARect.Y, ARect.W, ARect.H, GLFormat, APixels, APitch,
    BytesPerTexel(ATexture.Format));
  // 次の実行は束縛を作り直す（BeginRun）ので、ここで元に戻さなくてよい。
  Result := True;
end;

{ 平面ごとの更新（SDL の GLES2_UpdateTextureYUV）。YV12 / IYUV。 }
function TPMLGLES2RenderDriver.UpdateTextureYUV(ATexture: TPMLTexture; const ARect: TPMLRect;
  AY: Pointer; AYPitch: Integer; AU: Pointer; AUPitch: Integer;
  AV: Pointer; AVPitch: Integer): Boolean;
var
  Data: TPMLGLES2Texture;
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
  UploadPlane(Data.IdV, ARect.X div 2, ARect.Y div 2, (ARect.W + 1) div 2, (ARect.H + 1) div 2,
    GL_LUMINANCE, AV, AVPitch, 1);
  UploadPlane(Data.IdU, ARect.X div 2, ARect.Y div 2, (ARect.W + 1) div 2, (ARect.H + 1) div 2,
    GL_LUMINANCE, AU, AUPitch, 1);
  UploadPlane(Data.Id, ARect.X, ARect.Y, ARect.W, ARect.H, GL_LUMINANCE, AY, AYPitch, 1);
  Result := FGL.glGetError() = GL_NO_ERROR;
end;

{ Y と、U・V を交互に詰めた平面での更新（SDL の GLES2_UpdateTextureNV）。NV12 / NV21。
  UV の平面は 1 画素 2 バイトの GL_LUMINANCE_ALPHA で、AUVPitch はバイト数。 }
function TPMLGLES2RenderDriver.UpdateTextureNV(ATexture: TPMLTexture; const ARect: TPMLRect;
  AY: Pointer; AYPitch: Integer; AUV: Pointer; AUVPitch: Integer): Boolean;
var
  Data: TPMLGLES2Texture;
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
  UploadPlane(Data.IdU, ARect.X div 2, ARect.Y div 2, (ARect.W + 1) div 2, (ARect.H + 1) div 2,
    GL_LUMINANCE_ALPHA, AUV, AUVPitch, 2);
  UploadPlane(Data.Id, ARect.X, ARect.Y, ARect.W, ARect.H, GL_LUMINANCE, AY, AYPitch, 1);
  Result := FGL.glGetError() = GL_NO_ERROR;
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
    if FTarget = Data then
    begin
      // 描画先のまま消された。描画先を元へ戻す（レンダラは先に戻している）。
      FTarget := nil;
      BindDrawFramebuffer;
    end;
    if Data.FBO <> 0 then
      FGL.glDeleteFramebuffers(1, @Data.FBO);
    FGL.glDeleteTextures(1, @Data.Id);
    if Data.IdU <> 0 then
      FGL.glDeleteTextures(1, @Data.IdU);
    if Data.IdV <> 0 then
      FGL.glDeleteTextures(1, @Data.IdV);
  except
    on E: EPMLError do
      FLastNonFatalError := 'GLES2 texture cleanup failed: ' + E.Message;
  end;
  FreeAndNil(ATexture.DriverData);
end;

{ ---- パレット（SDL の GLES2_CreatePalette / UpdatePalette / DestroyPalette） ---- }

{ 256x1 の RGBA テクスチャを作る。補間は最近傍、端は CLAMP_TO_EDGE。

  PORT-NOTE: SDL は中身を未定義のまま作る（glTexImage2D の画素が NULL）。papimela は 256 色すべてを
  白の不透明で始める。アプリのパレットが 256 色に満たないとき、表の外の添字が白で描かれ、
  ソフトウェアのドライバ（256 色の写しが白で始まる。実測）と同じ絵になる。 }
function TPMLGLES2RenderDriver.CreatePalette(APalette: TPMLTexturePalette): Boolean;
var
  Data: TPMLGLES2Palette;
  White: array[0..255] of TPMLColor;
  I: Integer;
begin
  Result := False;
  EnsureCurrent;
  FGL.glGetError();
  for I := 0 to 255 do
    White[I] := TPMLColor.White;
  Data := TPMLGLES2Palette.Create;
  FGL.glGenTextures(1, @Data.Id);
  FGL.glBindTexture(GL_TEXTURE_2D, Data.Id);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  FGL.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  FGL.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 256, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, @White[0]);
  if FGL.glGetError() <> GL_NO_ERROR then
  begin
    FGL.glDeleteTextures(1, @Data.Id);
    Data.Free;
    Exit;
  end;
  APalette.DriverData := Data;
  Result := True;
end;

{ 先頭の AColors の個数ぶんの色を写す。TPMLColor は R,G,B,A の順の 4 バイトなので、
  GL_RGBA / GL_UNSIGNED_BYTE でそのまま渡せる。残りの色は前のまま。 }
function TPMLGLES2RenderDriver.UpdatePalette(APalette: TPMLTexturePalette;
  const AColors: array of TPMLColor): Boolean;
var
  Data: TPMLGLES2Palette;
  Count: Integer;
begin
  Result := False;
  if not (APalette.DriverData is TPMLGLES2Palette) then
    Exit;
  Data := TPMLGLES2Palette(APalette.DriverData);
  Count := Min(Length(AColors), 256);
  if Count <= 0 then
    Exit(True);
  EnsureCurrent;
  FGL.glGetError();
  FGL.glBindTexture(GL_TEXTURE_2D, Data.Id);
  FGL.glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, Count, 1, GL_RGBA, GL_UNSIGNED_BYTE, @AColors[0]);
  Result := FGL.glGetError() = GL_NO_ERROR;
end;

procedure TPMLGLES2RenderDriver.DestroyPalette(APalette: TPMLTexturePalette);
var
  Data: TPMLGLES2Palette;
begin
  if APalette.DriverData is TPMLGLES2Palette then
  begin
    Data := TPMLGLES2Palette(APalette.DriverData);
    try
      EnsureCurrent;
      FGL.glDeleteTextures(1, @Data.Id);
    except
      on E: EPMLError do
        FLastNonFatalError := 'GLES2 palette cleanup failed: ' + E.Message;
    end;
  end;
  FreeAndNil(APalette.DriverData);
end;

{ 何もしない。描くときに ACmd.Texture.DriverPalette を読んで束縛する（ExecDraw）。 }
procedure TPMLGLES2RenderDriver.ChangeTexturePalette(ATexture: TPMLTexture);
begin
end;

function TPMLGLES2RenderDriver.SupportsRenderTargets: Boolean;
begin
  Result := True;
end;

{ 描画先を切り替える（SDL の GLES2_SetRenderTarget）。束縛は次の実行の頭
  （BeginRun）と読み戻しでも張り直す。 }
function TPMLGLES2RenderDriver.SetRenderTarget(ATexture: TPMLTexture): Boolean;
var
  Data: TPMLGLES2Texture;
begin
  Result := False;
  Data := nil;
  if ATexture <> nil then
  begin
    Data := TextureData(ATexture);
    if (Data = nil) or (Data.FBO = 0) then
      Exit;
  end;
  EnsureCurrent;
  FTarget := Data;
  BindDrawFramebuffer;
  Result := True;
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
  C: Single;
  S: TPMLGLES2Shader;
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
  FBoundTexture := 0;
  FBoundUnit1 := 0;
  FBoundUnit2 := 0;
  // 実行の前の呼び出し（テクスチャの更新など）が束縛を動かしても、ユニット 0 に戻す。
  FGL.glActiveTexture(GL_TEXTURE0);
  // テクスチャの id は破棄のあとで使い回されるので、大きさの設定は持ち越さない。
  for S := Low(TPMLGLES2Shader) to High(TPMLGLES2Shader) do
    FPrograms[S].TexelOwner := 0;

  if AQueue.VertexCount > 0 then
  begin
    if Length(FVertexBuf) < AQueue.VertexCount then
      SetLength(FVertexBuf, AQueue.VertexCount * 2);
    for I := 0 to AQueue.VertexCount - 1 do
      FVertexBuf[I] := AQueue.Vertex(I);
    // 1 回の実行は 1 つの描画先へ描く（レンダラが切り替えの前に描き切る）ので、
    // 入れ替えは全頂点にまとめて掛けてよい。
    if TargetSwapsRB then
      for I := 0 to AQueue.VertexCount - 1 do
      begin
        C := FVertexBuf[I].Color.R;
        FVertexBuf[I].Color.R := FVertexBuf[I].Color.B;
        FVertexBuf[I].Color.B := C;
      end;
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
  if FlipsOutput then
    Y := FDrawableH - FViewport.Y - H
  else
    Y := FViewport.Y;
  FGL.glViewport(FViewport.X, Y, W, H);
  if (W > 0) and (H > 0) then
  begin
    if FlipsOutput then
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
    if FlipsOutput then
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
  if TargetSwapsRB then
    FGL.glClearColor(ACmd.Color.B, ACmd.Color.G, ACmd.Color.R, ACmd.Color.A)
  else
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
  Pal: TPMLGLES2Palette;
  Shader: TPMLGLES2Shader;
  Filter: GLint;
  Snap: Integer;
begin
  Data := nil;
  Pal := nil;
  Shader := TPMLGLES2Shader.Solid;
  if ACmd.Texture <> nil then
  begin
    Data := TextureData(ACmd.Texture);
    if Data = nil then
      Exit;       // 破棄されたテクスチャ。描くものが無い
    if Data.Indexed then
    begin
      // パレットの写しは実行のときに読む。写しの中身は、積む前に UpdatePalette が
      // 流してある（レンダラが、版が変わったら先に吐き出す）
      if (ACmd.Texture.DriverPalette = nil)
      or not (ACmd.Texture.DriverPalette.DriverData is TPMLGLES2Palette) then
        Exit;     // 破棄されたパレット。描くものが無い
      Pal := TPMLGLES2Palette(ACmd.Texture.DriverPalette.DriverData);
      // PixelArt は Nearest と同じ（下の PORT-NOTE）
      if ACmd.ScaleMode = TPMLScaleMode.Linear then
      begin
        if TargetSwapsRB then
          Shader := TPMLGLES2Shader.PalLinearSwap
        else
          Shader := TPMLGLES2Shader.PalLinear;
      end
      else if TargetSwapsRB then
        Shader := TPMLGLES2Shader.PalNearestSwap
      else
        Shader := TPMLGLES2Shader.PalNearest;
    end
    else if Data.Planar then
    begin
      // YUV は変換のシェーダ。描画先の並びが B,G,R なら R と B を入れ替える版
      if TargetSwapsRB then
        Shader := TPMLGLES2Shader.YUVSwap
      else
        Shader := TPMLGLES2Shader.YUV;
    end
    else if Data.NV then
    begin
      if Data.Format = PML_PIXELFORMAT_NV12 then
      begin
        if TargetSwapsRB then
          Shader := TPMLGLES2Shader.NV12Swap
        else
          Shader := TPMLGLES2Shader.NV12;
      end
      else if TargetSwapsRB then
        Shader := TPMLGLES2Shader.NV21Swap
      else
        Shader := TPMLGLES2Shader.NV21;
    end
    else
      Shader := CopyShader(Data.BFirst, Data.HasAlpha, TargetSwapsRB);
  end;
  if ACmd.Count <= 0 then
    Exit;

  ApplyViewport;
  ApplyScissor;
  UseShader(Shader);
  ApplyBlend(ACmd.Blend);

  if Data <> nil then
  begin
    if (Pal <> nil) and (FBoundUnit1 <> Pal.Id) then
    begin
      // パレットの写しはユニット 1。ユニット 0 に戻してから先へ進む
      BindUnit(GL_TEXTURE1, Pal.Id);
      FBoundUnit1 := Pal.Id;
    end;
    if Data.IdU <> 0 then
    begin
      // YUV の U（NV は UV）はユニット 1、V はユニット 2。Y はこのあとユニット 0
      if FBoundUnit1 <> Data.IdU then
      begin
        BindUnit(GL_TEXTURE1, Data.IdU);
        FBoundUnit1 := Data.IdU;
      end;
      if (Data.IdV <> 0) and (FBoundUnit2 <> Data.IdV) then
      begin
        BindUnit(GL_TEXTURE2, Data.IdV);
        FBoundUnit2 := Data.IdV;
      end;
    end;
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
    if IsYUVShader(Shader) and (FPrograms[Shader].YUVKind <> Ord(Data.YCbCr)) then
    begin
      // 変換のパラメータ（オフセットと、R・G・B の係数）。色空間ごとに 1 組
      with FPrograms[Shader] do
      begin
        if YUVOffset <> -1 then
          FGL.glUniform3f(YUVOffset, YUVMatrix[Data.YCbCr][0], YUVMatrix[Data.YCbCr][1],
            YUVMatrix[Data.YCbCr][2]);
        if YUVRCoeff <> -1 then
          FGL.glUniform3f(YUVRCoeff, YUVMatrix[Data.YCbCr][3], YUVMatrix[Data.YCbCr][4],
            YUVMatrix[Data.YCbCr][5]);
        if YUVGCoeff <> -1 then
          FGL.glUniform3f(YUVGCoeff, YUVMatrix[Data.YCbCr][6], YUVMatrix[Data.YCbCr][7],
            YUVMatrix[Data.YCbCr][8]);
        if YUVBCoeff <> -1 then
          FGL.glUniform3f(YUVBCoeff, YUVMatrix[Data.YCbCr][9], YUVMatrix[Data.YCbCr][10],
            YUVMatrix[Data.YCbCr][11]);
        YUVKind := Ord(Data.YCbCr);
      end;
    end;
    if IsYUVShader(Shader) then
    begin
      // 補間なしのときだけ、色差の座標を 2x2 の区画に寄せる（シェーダの PORT-NOTE）
      if ACmd.ScaleMode = TPMLScaleMode.Linear then
        Snap := 0
      else
        Snap := 1;
      if (FPrograms[Shader].YUVSnapState <> Snap) and (FPrograms[Shader].YUVSnap <> -1) then
      begin
        FGL.glUniform1i(FPrograms[Shader].YUVSnap, Snap);
        FPrograms[Shader].YUVSnapState := Snap;
      end;
    end;
    // INDEX8 の添字のテクスチャは補間しない（Data.Filter は Nearest のまま）。
    // 線形は PalLinear が 4 つの添字の色を混ぜる（SDL の SetTextureScaleMode と同じ）
    if (not Data.Indexed) and (Data.Filter <> ACmd.ScaleMode) then
    begin
      // PORT-NOTE: PixelArt は Nearest と同じ。SDL の GLES2 は本物の PIXELART のシェーダを
      // OPENGLES_300 のときだけ使うが、それはどこにも定義されていない（GL_NEAREST と texture2D に戻る）。
      if ACmd.ScaleMode = TPMLScaleMode.Linear then
        Filter := GL_LINEAR
      else
        Filter := GL_NEAREST;
      SetPlaneFilter(Filter);
      if Data.IdU <> 0 then
      begin
        // YUV は全部の平面に同じ補間を掛ける（SDL の SetCopyState と同じ）。
        // 平面はこの直前に、U（NV は UV）がユニット 1、V がユニット 2 に束縛してある
        FGL.glActiveTexture(GL_TEXTURE1);
        SetPlaneFilter(Filter);
        if Data.IdV <> 0 then
        begin
          FGL.glActiveTexture(GL_TEXTURE2);
          SetPlaneFilter(Filter);
        end;
        FGL.glActiveTexture(GL_TEXTURE0);
      end;
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
  描画先のテクスチャを読むときは、結果の形式をそのテクスチャの形式にする。FBO の
  メモリはテクスチャの並びで書いてあるので（TargetSwapsRB）、GL_RGBA で読んだバイトが
  そのままその形式になる（SDL も描画先の形式で返す）。

  PORT-NOTE: 矩形が描画先からはみ出す部分は、SDL では GL が何を返すか未定義。
  ここは描画先と重なる部分だけを読み、はみ出す部分は 0（透明な黒）のままにする。 }
function TPMLGLES2RenderDriver.ReadPixels(const ARect: TPMLRect): TPMLSurface;
var
  OutW, OutH, X1, Y1, X2, Y2, W, H, Row, GLY: Integer;
  Buf: PByte;
  RowBytes: PtrUInt;
  Fmt: TPMLPixelFormat;
begin
  if FTarget <> nil then
    Fmt := TPMLGLES2Texture(FTarget).Format
  else
    Fmt := PML_PIXELFORMAT_RGBA32;
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
      FGL.glReadPixels(X1, GLY, W, H, GL_RGBA, GL_UNSIGNED_BYTE, Buf);
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
