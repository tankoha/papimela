{
  PaPiMeLa.Render — レンダラの抽象と公開 API

  Origin : ported from SDL (src/render/SDL_render.c, src/render/SDL_sysrender.h)
           Scope: 描画をコマンドとして積んで Present / Flush でまとめて実行する構造、
           状態コマンド（ビューポート・クリップ）を変化したときだけ積む規則、
           同じ状態の描画を 1 つのコマンドにまとめる規則、矩形・線・点・
           テクスチャ転送を三角形に落とす変換、拡大率と論理解像度
           （UpdateLogicalPresentation、倍率のかかった点と線の描き方、
           ウィンドウ座標との変換）、DebugText（文字の表の配置と字形の引き方）。
           字形の表は src/generated/debug_font.inc（tools/gendebugfont.bb が
           SDL_render_debug_font.h から生成。字形そのものは Public Domain）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.3、§11 #41

  WHAT:
    TPMLRenderer（公開 API）、TPMLTexture、TPMLRenderDriver（ドライバの抽象）、
    TPMLRenderQueue（コマンドと頂点の置き場）。

  WHY:
    SDL_Renderer は 35 個の関数ポインタを持つドライバを従えている。そのうち
    QueueFillRects / QueueDrawLines / QueueCopy は **NULL でもよく**、NULL なら
    SDL_render.c が三角形に変換して QueueGeometry へ回す（SDL_render.c 986〜989 行の
    表明と、呼び出し箇所ごとの `if (!renderer->QueueFillRects)`）。
    これは既定の実装を持つ仮想メソッドを手で書いたものである。
    papimela では TPMLRenderDriver の仮想メソッドが既定で三角形を出す。
    新しいドライバは QueueGeometry を実装すれば矩形も線も転送も描け、
    速い経路を持つドライバだけが上書きする。呼び出し箇所の NULL 判定は消える。

  RESOLVED:
    - コマンドは配列に積む。SDL の連結リストは C に伸びる配列が無いため
    - 積み荷は 2 本の配列に分ける。三角形の頂点（Vertices）と、速い経路用の
      矩形（Rects）。SDL は型の無い 1 本のバイト列に詰めるが、型を分ければ
      「このコマンドの積み荷をどう読むか」を取り違えようがない
    - 既定の変換は protected の QueueXxxAsGeometry に置く。仮想メソッドの既定は
      それを呼ぶだけ。ドライバは条件つきで既定へ戻すときにこれを直接呼べる
    - 直前のコマンドと種類と状態が同じで、積み荷が末尾で連続していれば、
      新しいコマンドを作らず直前のものを伸ばす（SDL のバッチと同じ）
    - ウィンドウへ描くレンダラは CreateForWindow で作る。設計（§4.3）では
      TPMLWindow.CreateRenderer だったが、それだと PaPiMeLa.Video が
      PaPiMeLa.Render に依存し、描画を使わないアプリにもレンダラが付いてくる。
      依存の向きを Render → Video の一方向に保つため、レンダラ側に置いた
    - ウィンドウへ描くレンダラの所有者はウィンドウ。ウィンドウが先に消えると
      IPMLWindowDependent 経由でレンダラも消える（テクスチャも一緒に消える）

  NOT RESOLVED:
    - 描画先テクスチャ（SetRenderTarget）、回転（RenderTextureRotated）、
      9-grid / タイルは未実装（VSync、論理解像度、DebugText は実装済み）
    - 線の描き方の切り替え（SDL_HINT_RENDER_LINE_METHOD）は無い。論理解像度では
      三角形、倍率だけなら矩形の並び、どちらも無ければドライバの線（SDL の既定の
      振り分けのうち、ソフトウェアのレンダラと同じもの）
    - DebugText の文字の表は拡大を Nearest で行う（SDL は PIXELART）。整数倍では
      同じ絵、小数倍では字形の画素の位置が 1 画素ずれることがある（SDL と実測で比べた）
    - パレットと YUV のテクスチャは未実装
    - GPU のドライバは OpenGL ES 2.0（#43）だけ。デスクトップ GL（#44）は未着手

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Render;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Video;

type
  TPMLRenderer = class;
  TPMLTexture = class;
  TPMLRenderQueue = class;

  { 三角形の頂点。色は 0..1、テクスチャ座標は 0..1（テクスチャの幅・高さで正規化）。 }
  TPMLVertex = record
    Position: TPMLFPoint;
    Color   : TPMLFColor;
    TexCoord: TPMLFPoint;
  end;
  TPMLVertices = array of TPMLVertex;
  TPMLIndices = array of Integer;

  TPMLRenderCommandKind = (
    NoOp, SetViewport, SetClipRect, Clear,
    DrawPoints, DrawLines, FillRects, Copy, Geometry
  );

  { 1 つのコマンド。積み荷の場所は First / Count で示す。

    どの配列を指すかは Kind で決まる:
      Geometry            → Queue.Vertices（3 頂点で 1 三角形）
      FillRects           → Queue.Rects（1 矩形 = 1 要素）
      Copy                → Queue.Rects（転送元・転送先の 2 要素で 1 回）
      DrawPoints / Lines  → Queue.Rects（点は X / Y、線は 2 点を X,Y と W,H に） }
  TPMLRenderCommand = record
    Kind     : TPMLRenderCommandKind;
    Rect     : TPMLRect;          // SetViewport / SetClipRect
    Enabled  : Boolean;           // SetClipRect
    First    : Integer;
    Count    : Integer;
    Color    : TPMLFColor;        // Clear と単色の描画
    Blend    : TPMLBlendMode;
    Texture  : TPMLTexture;
    ScaleMode: TPMLScaleMode;
  end;
  TPMLRenderCommands = array of TPMLRenderCommand;

  { コマンドと積み荷の置き場。レンダラが所有し、Flush のたびに空にする。 }
  TPMLRenderQueue = class
  strict private
    FCommands   : TPMLRenderCommands;
    FCommandCount: Integer;
    FVertices   : TPMLVertices;
    FVertexCount: Integer;
    FRects      : TPMLFRects;
    FRectCount  : Integer;
    function GetCommand(AIndex: Integer): TPMLRenderCommand;
  public
    procedure Reset;
    // 積み荷を足して、その開始位置を返す。
    function  AddVertices(const AVertices: array of TPMLVertex): Integer;
    function  AddRects(const ARects: array of TPMLFRect): Integer;
    // コマンドを足す。直前と結合できれば結合して False を返す。
    function  Push(const ACmd: TPMLRenderCommand): Boolean;
    function  Vertex(AIndex: Integer): TPMLVertex; inline;
    function  RectAt(AIndex: Integer): TPMLFRect; inline;
    property  CommandCount: Integer read FCommandCount;
    property  Commands[AIndex: Integer]: TPMLRenderCommand read GetCommand;
    property  VertexCount: Integer read FVertexCount;
    property  RectCount: Integer read FRectCount;
  end;

  { ドライバの抽象。SDL_Renderer の関数ポインタ群を置き換える。

    必須は QueueGeometry と RunCommandQueue とテクスチャの 3 つと出力まわり。
    点・線・矩形・転送は既定で三角形へ落とすので、上書きは任意。 }
  TPMLRenderDriver = class abstract(TPMLSystemObject)
  protected
    { 既定の変換。仮想メソッドの既定実装はこれを呼ぶ。ACmd.Kind を Geometry に
      書き換え、頂点を積む。ドライバが条件つきで既定へ戻すときに直接呼んでよい。 }
    procedure QueueFillRectsAsGeometry(AQueue: TPMLRenderQueue;
      var ACmd: TPMLRenderCommand; const ARects: array of TPMLFRect);
    procedure QueueCopyAsGeometry(AQueue: TPMLRenderQueue;
      var ACmd: TPMLRenderCommand; ATexture: TPMLTexture;
      const ASrc, ADst: TPMLFRect);
    procedure QueueDrawPointsAsGeometry(AQueue: TPMLRenderQueue;
      var ACmd: TPMLRenderCommand; const APoints: array of TPMLFPoint);
    procedure QueueDrawLinesAsGeometry(AQueue: TPMLRenderQueue;
      var ACmd: TPMLRenderCommand; const APoints: array of TPMLFPoint);
  public
    function  Name: String; virtual; abstract;
    function  GetOutputSize(out AWidth, AHeight: Integer): Boolean; virtual; abstract;
    function  SupportsBlendMode(AMode: TPMLBlendMode): Boolean; virtual;
    // このドライバがテクスチャとして直接持てる形式か。既定は True。
    // False の形式は、CreateTextureFromSurface が ARGB8888 へ変換してから渡す。
    // ARGB8888 はどのドライバも持てなければならない。
    function  SupportsTextureFormat(AFormat: TPMLPixelFormat): Boolean; virtual;

    function  CreateTexture(ATexture: TPMLTexture): Boolean; virtual; abstract;
    function  UpdateTexture(ATexture: TPMLTexture; const ARect: TPMLRect;
      APixels: Pointer; APitch: Integer): Boolean; virtual; abstract;
    procedure DestroyTexture(ATexture: TPMLTexture); virtual; abstract;

    // 必須。頂点を積み、ACmd.Kind = Geometry のまま積み荷の位置を埋める。
    procedure QueueGeometry(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const AVertices: array of TPMLVertex); virtual; abstract;

    // 任意。既定は三角形へ落とす。
    procedure QueueFillRects(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const ARects: array of TPMLFRect); virtual;
    procedure QueueCopy(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      ATexture: TPMLTexture; const ASrc, ADst: TPMLFRect); virtual;
    procedure QueueDrawPoints(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const APoints: array of TPMLFPoint); virtual;
    procedure QueueDrawLines(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const APoints: array of TPMLFPoint); virtual;

    // 積んだコマンドを実行する。
    procedure RunCommandQueue(AQueue: TPMLRenderQueue); virtual; abstract;
    // 描画先の画素を読む。呼び出し側が Free する。
    function  ReadPixels(const ARect: TPMLRect): TPMLSurface; virtual; abstract;
    procedure Present; virtual; abstract;
    // Present を画面の更新に合わせるか。既定は 0（合わせない）だけを受け付ける。
    function  SetVSync(AInterval: Integer): Boolean; virtual;
  end;

  TPMLTextureAccess = (Static, Streaming);

  { 論理解像度の当てはめ方（SDL_RendererLogicalPresentation と同じ 5 つ）。
      Disabled     : 論理解像度を使わない
      Stretch      : 出力全体へ引き伸ばす（縦横比は保たない）
      Letterbox    : 縦横比を保って収め、余りは帯にする
      Overscan     : 縦横比を保って出力を覆い、はみ出た分は切れる
      IntegerScale : 整数倍だけで収める（最低 1 倍）。余りは帯 }
  TPMLLogicalPresentation = (Disabled, Stretch, Letterbox, Overscan, IntegerScale);

  { テクスチャ。レンダラが所有する。中身の持ち方はドライバが決め、
    DriverData に置く（ソフトウェアドライバは TPMLSurface）。 }
  TPMLTexture = class(TPMLOwnedObject)
  strict private
    FRenderer : TPMLRenderer;
    FFormat   : TPMLPixelFormat;
    FAccess   : TPMLTextureAccess;
    FWidth    : Integer;
    FHeight   : Integer;
    FBlendMode: TPMLBlendMode;
    FColorMod : TPMLColor;
    FAlphaMod : Byte;
    FScaleMode: TPMLScaleMode;
  protected
    procedure OwnerDestroying; override;
  public
    // ドライバが所有する中身。ドライバの CreateTexture / DestroyTexture が作り、消す。
    DriverData: TObject;

    constructor Create(ARenderer: TPMLRenderer; AFormat: TPMLPixelFormat;
      AAccess: TPMLTextureAccess; AWidth, AHeight: Integer);
    destructor Destroy; override;

    // ARect が空ならテクスチャ全体。
    procedure Update(const ARect: TPMLRect; APixels: Pointer; APitch: Integer);

    property Renderer : TPMLRenderer read FRenderer;
    property Format   : TPMLPixelFormat read FFormat;
    property Access   : TPMLTextureAccess read FAccess;
    property Width    : Integer read FWidth;
    property Height   : Integer read FHeight;
    property BlendMode: TPMLBlendMode read FBlendMode write FBlendMode;
    property ColorMod : TPMLColor read FColorMod write FColorMod;
    property AlphaMod : Byte read FAlphaMod write FAlphaMod;
    property ScaleMode: TPMLScaleMode read FScaleMode write FScaleMode;
  end;
  TPMLTextures = array of TPMLTexture;

  { レンダラの公開 API。

    描画の呼び出しはその場では描かず、コマンドとして積む。Present / Flush /
    ReadPixels のときにドライバがまとめて実行する。 }
  TPMLRenderer = class(TPMLOwnedObject, IPMLWindowDependent)
  strict private
    FDriver     : TPMLRenderDriver;
    FWindow     : TPMLWindow;         // 描画先のウィンドウ（所有者）。無ければ nil
    FVSync      : Integer;
    FQueue      : TPMLRenderQueue;
    FTextures   : TPMLTextures;
    FDrawColor  : TPMLFColor;
    FBlendMode  : TPMLBlendMode;
    FViewport   : TPMLRect;
    FClipRect   : TPMLRect;
    FClipEnabled: Boolean;
    // 最後に積んだ状態。変化したときだけ状態コマンドを積む（SDL と同じ）。
    FQueuedViewport: TPMLRect;
    FQueuedClip    : TPMLRect;
    FQueuedClipOn  : Boolean;
    FStateQueued   : Boolean;
    // 拡大率と論理解像度（SDL_RenderViewState の main_view にあたる）。
    FScale         : TPMLFPoint;      // アプリが決める倍率
    FLogicalW      : Integer;
    FLogicalH      : Integer;
    FLogicalMode   : TPMLLogicalPresentation;
    FLogicalDst    : TPMLFRect;       // 論理画面を置く出力上の矩形
    FLogicalScale  : TPMLFPoint;
    FCurrentScale  : TPMLFPoint;      // FScale x FLogicalScale。描画の座標に掛ける
    FPixelW        : Integer;         // 論理画面の出力上の大きさ（画素）
    FPixelH        : Integer;
    FDebugFont     : TPMLTexture;     // DebugText の文字の表。初めて使うときに作る

    function  GetDrawColor: TPMLColor;
    procedure SetDrawColor(const AValue: TPMLColor);
    procedure SetViewport(const AValue: TPMLRect);
    procedure SetClipRect(const AValue: TPMLRect);
    function  GetDriverName: String;
    procedure QueueStateIfChanged;
    function  NewDrawCommand(AKind: TPMLRenderCommandKind): TPMLRenderCommand;
    procedure SetVSync(AValue: Integer);
    procedure SetScale(const AValue: TPMLFPoint);
    procedure UpdateView;
    function  PixelViewport: TPMLRect;
    function  PixelClipRect: TPMLRect;
    function  ViewportSize: TPMLFRect;
    function  IsScaled: Boolean; inline;
    procedure QueueFillRectsRaw(const ARects: array of TPMLFRect);
    procedure DrawPointsAsRects(const APoints: array of TPMLFPoint);
    procedure DrawLinesAsGeometry(const APoints: array of TPMLFPoint);
    procedure DrawLinesAsRects(const APoints: array of TPMLFPoint);
    procedure DrawLineBresenham(AX1, AY1, AX2, AY2: Integer; ADrawLast: Boolean);
    procedure CreateDebugFont;
  private
    procedure RemoveTexture(ATexture: TPMLTexture);
  protected
    procedure DetachFromOwner; override;
    // IPMLWindowDependent。ウィンドウが消える直前に呼ばれ、自分を Free する。
    procedure WindowDestroying(AWindow: TPMLWindow);
  public
    { ドライバを受け取って所有する。 }
    constructor Create(ADriver: TPMLRenderDriver);
    { サーフェスを描画先にするソフトウェアレンダラを作る。
      サーフェスは借りるだけで、所有しない。 }
    class function CreateSoftware(ATarget: TPMLSurface): TPMLRenderer;
    { ウィンドウへ描くレンダラを作る。所有者はウィンドウ。
      ADriverName が空ならドライバを選ぶ。今あるのは 'software' だけで、
      ウィンドウの SoftwareFramebuffer 能力が要る。 }
    constructor CreateForWindow(AWindow: TPMLWindow; const ADriverName: String = '');
    destructor Destroy; override;

    function  CreateTexture(AFormat: TPMLPixelFormat; AAccess: TPMLTextureAccess;
      AWidth, AHeight: Integer): TPMLTexture;
    function  CreateTextureFromSurface(ASurface: TPMLSurface): TPMLTexture;

    // 描画先全体を DrawColor で塗る。クリップ矩形は無視する（SDL と同じ）。
    procedure Clear;
    procedure DrawPoint(AX, AY: Single);
    procedure DrawPoints(const APoints: array of TPMLFPoint);
    procedure DrawLine(AX1, AY1, AX2, AY2: Single);
    // 折れ線。隣り合う 2 点ずつを結ぶ。
    procedure DrawLines(const APoints: array of TPMLFPoint);
    procedure DrawRect(const ARect: TPMLFRect);
    procedure FillRect(const ARect: TPMLFRect);
    procedure FillRects(const ARects: array of TPMLFRect);
    // ASrc が空ならテクスチャ全体、ADst が空なら描画先全体。
    procedure RenderTexture(ATexture: TPMLTexture; const ASrc, ADst: TPMLFRect);
    // 3 頂点ずつ三角形。AIndices が空なら AVertices をそのまま使う。
    procedure RenderGeometry(ATexture: TPMLTexture;
      const AVertices: array of TPMLVertex; const AIndices: array of Integer);

    // 積んだコマンドを実行して空にする。
    procedure Flush;
    procedure Present;
    // 描画先の画素を読む。先に Flush する。呼び出し側が Free する。
    function  ReadPixels(const ARect: TPMLRect): TPMLSurface;
    function  GetOutputSize(out AWidth, AHeight: Integer): Boolean;

    { 論理解像度。以後の描画の座標は AW x AH の論理画面の上の座標になり、
      出力へは AMode に従って当てはめる。出力（ウィンドウ）の大きさが変わると
      次の描画で当てはめ直す。Disabled なら AW / AH は無視して 0 にする。
      Clear は帯の部分まで出力全体を塗る（SDL と同じ）。 }
    procedure SetLogicalPresentation(AW, AH: Integer; AMode: TPMLLogicalPresentation);
    procedure GetLogicalPresentation(out AW, AH: Integer;
      out AMode: TPMLLogicalPresentation);
    // 論理画面を置いた出力上の矩形（画素）。Disabled なら出力全体。
    function  LogicalPresentationRect: TPMLFRect;
    { ウィンドウの座標（マウスの位置など）と描画の座標の変換。拡大率・
      論理解像度・ビューポートの原点を考える。ウィンドウへ描くレンダラでは
      ウィンドウの座標と画素の比（高密度表示）も考える。 }
    function  RenderCoordinatesFromWindow(AWindowX, AWindowY: Single): TPMLFPoint;
    function  RenderCoordinatesToWindow(AX, AY: Single): TPMLFPoint;

    { 8x8 の組み込みの文字で文字列を描く（SDL_RenderDebugText）。色は DrawColor。
      1 文字の幅は PML_DEBUG_TEXT_FONT_CHARACTER_SIZE。AText は UTF-8。
      字形が無い文字は「?」の箱で描く。改行などの制御文字は空白として進む。 }
    procedure DebugText(AX, AY: Single; const AText: String);
    procedure DebugTextFormat(AX, AY: Single; const AFormat: String;
      const AArgs: array of const);

    property DrawColor  : TPMLColor read GetDrawColor write SetDrawColor;
    property DrawColorF : TPMLFColor read FDrawColor write FDrawColor;
    property BlendMode  : TPMLBlendMode read FBlendMode write FBlendMode;
    // 空の矩形 = 出力全体。
    property Viewport   : TPMLRect read FViewport write SetViewport;
    property ClipRect   : TPMLRect read FClipRect write SetClipRect;
    property ClipEnabled: Boolean read FClipEnabled write FClipEnabled;
    // 描画の座標に掛ける倍率。既定は (1, 1)。論理解像度の倍率とは別に掛かる。
    property Scale      : TPMLFPoint read FScale write SetScale;
    property Driver     : TPMLRenderDriver read FDriver;
    property Window     : TPMLWindow read FWindow;
    // 0 = Present は待たない、1 = 画面の更新を待つ。ドライバが受け付けなければ
    // EPMLUnsupported。
    property VSync      : Integer read FVSync write SetVSync;
    property DriverName : String read GetDriverName;
    property Queue      : TPMLRenderQueue read FQueue;
    property Textures   : TPMLTextures read FTextures;
  end;

const
  // DebugText の 1 文字の幅と高さ（SDL_DEBUG_TEXT_FONT_CHARACTER_SIZE）。
  PML_DEBUG_TEXT_FONT_CHARACTER_SIZE = 8;

// ドライバの実装が使う。色と状態を比べ、同じなら結合してよいかを返す。
function PMLSameDrawState(const A, B: TPMLRenderCommand): Boolean;

type
  // ウィンドウへ描くドライバを作る。
  TPMLRenderDriverFactory = function(AWindow: TPMLWindow): TPMLRenderDriver;
  // 名前を指定されなかったとき、このウィンドウにこのドライバを選ぶか
  // （GLES2 なら OpenGL の能力で作ったウィンドウ）。
  TPMLRenderDriverPrefers = function(AWindow: TPMLWindow): Boolean;

{ ---- 登録（#45） ----

  ウィンドウへ描くドライバの登録。ソフトウェアのドライバ（'software'）は
  登録しない。どのアプリでも使えるよう、この公開層が直接持ち、どの登録
  ドライバも選ばれなかったときの最後の候補になる。

  CreateForWindow の選び方:
    名前が空   登録順（優先度の大きい順）に APrefers を聞き、最初に True を
               返したもの。どれも無ければ 'software'
    名前あり   'software' か、登録された名前。どちらでもなければ
               EPMLUnsupported（登録済みの名前を添える）

  名前の比べ方と 2 度目の登録は、ビデオのバックエンドの登録と同じ。 }
procedure PMLRegisterRenderDriver(const AName: String; APriority: Integer;
  APrefers: TPMLRenderDriverPrefers; AFactory: TPMLRenderDriverFactory);
// 登録済みの名前を試す順に返し、最後に 'software' を付ける。
function  PMLRenderDriverNames: TStringArray;

implementation

uses
  Math,
  PaPiMeLa.Render.Software,
  PaPiMeLa.Video.Backend;

{ ---- 登録（#45） ---- }

type
  TRenderDriverRegistration = record
    Name    : String;
    Priority: Integer;
    Prefers : TPMLRenderDriverPrefers;
    Factory : TPMLRenderDriverFactory;
  end;

var
  // 試す順（優先度の大きい順、同じなら登録順）に並べて持つ。
  RenderDriverRegistry: array of TRenderDriverRegistration;

function FindRenderDriverIndex(const AName: String): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(RenderDriverRegistry) do
    if SameText(RenderDriverRegistry[I].Name, AName) then
      Exit(I);
end;

procedure PMLRegisterRenderDriver(const AName: String; APriority: Integer;
  APrefers: TPMLRenderDriverPrefers; AFactory: TPMLRenderDriverFactory);
var
  At, I: Integer;
begin
  if AName = '' then
    raise EPMLArgument.Create('render driver name is empty');
  if SameText(AName, 'software') then
    raise EPMLArgument.Create('render driver "software" is built in');
  if (not Assigned(APrefers)) or (not Assigned(AFactory)) then
    raise EPMLArgument.Create('render driver needs Prefers and Factory');
  if FindRenderDriverIndex(AName) >= 0 then
    raise EPMLArgument.CreateFmt('render driver "%s" is already registered', [AName]);
  // 自分より優先度の小さい最初の位置へ入れる（同じ優先度は後ろへ回る）。
  At := Length(RenderDriverRegistry);
  for I := 0 to High(RenderDriverRegistry) do
    if RenderDriverRegistry[I].Priority < APriority then
    begin
      At := I;
      Break;
    end;
  SetLength(RenderDriverRegistry, Length(RenderDriverRegistry) + 1);
  for I := High(RenderDriverRegistry) downto At + 1 do
    RenderDriverRegistry[I] := RenderDriverRegistry[I - 1];
  RenderDriverRegistry[At].Name := AName;
  RenderDriverRegistry[At].Priority := APriority;
  RenderDriverRegistry[At].Prefers := APrefers;
  RenderDriverRegistry[At].Factory := AFactory;
end;

function PMLRenderDriverNames: TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(RenderDriverRegistry) + 1);
  for I := 0 to High(RenderDriverRegistry) do
    Result[I] := RenderDriverRegistry[I].Name;
  Result[High(Result)] := 'software';
end;

{ ---- 補助 ---- }

function SameFColor(const A, B: TPMLFColor): Boolean; inline;
begin
  Result := (A.R = B.R) and (A.G = B.G) and (A.B = B.B) and (A.A = B.A);
end;

function PMLSameDrawState(const A, B: TPMLRenderCommand): Boolean;
begin
  Result := (A.Kind = B.Kind)
        and SameFColor(A.Color, B.Color)
        and (A.Blend = B.Blend)
        and (A.Texture = B.Texture)
        and (A.ScaleMode = B.ScaleMode);
end;

function MakeVertex(AX, AY: Single; const AColor: TPMLFColor;
  AU, AV: Single): TPMLVertex; inline;
begin
  Result.Position.X := AX;
  Result.Position.Y := AY;
  Result.Color := AColor;
  Result.TexCoord.X := AU;
  Result.TexCoord.Y := AV;
end;

{ TPMLRenderQueue }

procedure TPMLRenderQueue.Reset;
begin
  // 配列は縮めない。次のフレームでまた同じくらい使うため。
  FCommandCount := 0;
  FVertexCount := 0;
  FRectCount := 0;
end;

function TPMLRenderQueue.GetCommand(AIndex: Integer): TPMLRenderCommand;
begin
  Result := FCommands[AIndex];
end;

function TPMLRenderQueue.Vertex(AIndex: Integer): TPMLVertex;
begin
  Result := FVertices[AIndex];
end;

function TPMLRenderQueue.RectAt(AIndex: Integer): TPMLFRect;
begin
  Result := FRects[AIndex];
end;

function TPMLRenderQueue.AddVertices(const AVertices: array of TPMLVertex): Integer;
var
  I: Integer;
begin
  Result := FVertexCount;
  if FVertexCount + Length(AVertices) > Length(FVertices) then
    SetLength(FVertices, (FVertexCount + Length(AVertices)) * 2 + 64);
  for I := 0 to High(AVertices) do
    FVertices[FVertexCount + I] := AVertices[I];
  Inc(FVertexCount, Length(AVertices));
end;

function TPMLRenderQueue.AddRects(const ARects: array of TPMLFRect): Integer;
var
  I: Integer;
begin
  Result := FRectCount;
  if FRectCount + Length(ARects) > Length(FRects) then
    SetLength(FRects, (FRectCount + Length(ARects)) * 2 + 32);
  for I := 0 to High(ARects) do
    FRects[FRectCount + I] := ARects[I];
  Inc(FRectCount, Length(ARects));
end;

{ 直前と結合できれば結合する。

  結合してよいのは、種類と状態が同じで、直前の積み荷がちょうど今足した分の
  手前で終わっているとき。積み荷の配列は種類で決まるので、同じ種類なら
  同じ配列を指している。状態コマンド（Viewport / Clip / Clear）は結合しない。 }
function TPMLRenderQueue.Push(const ACmd: TPMLRenderCommand): Boolean;
var
  Last: Integer;
begin
  Last := FCommandCount - 1;
  if (Last >= 0)
  and (ACmd.Kind in [TPMLRenderCommandKind.Geometry, TPMLRenderCommandKind.FillRects,
                     TPMLRenderCommandKind.DrawPoints, TPMLRenderCommandKind.DrawLines])
  and PMLSameDrawState(FCommands[Last], ACmd)
  and (FCommands[Last].First + FCommands[Last].Count = ACmd.First) then
  begin
    Inc(FCommands[Last].Count, ACmd.Count);
    Exit(False);
  end;

  if FCommandCount >= Length(FCommands) then
    SetLength(FCommands, FCommandCount * 2 + 16);
  FCommands[FCommandCount] := ACmd;
  Inc(FCommandCount);
  Result := True;
end;

{ TPMLRenderDriver }

function TPMLRenderDriver.SupportsBlendMode(AMode: TPMLBlendMode): Boolean;
begin
  Result := True;
end;

function TPMLRenderDriver.SetVSync(AInterval: Integer): Boolean;
begin
  Result := AInterval = 0;
end;

function TPMLRenderDriver.SupportsTextureFormat(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := True;
end;

{ 矩形 1 つを三角形 2 枚にする。

  頂点の並びは左上・右上・右下 と 左上・右下・左下。対角線を共有するので、
  ラスタライザの top-left 規則が正しければ、対角線上の画素は 2 枚のどちらか
  一方だけに属する（二重にも欠けにもならない）。 }
procedure TPMLRenderDriver.QueueFillRectsAsGeometry(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const ARects: array of TPMLFRect);
var
  V: TPMLVertices;
  I: Integer;
  R: TPMLFRect;
  C: TPMLFColor;
begin
  C := ACmd.Color;
  SetLength(V, Length(ARects) * 6);
  for I := 0 to High(ARects) do
  begin
    R := ARects[I];
    V[I * 6 + 0] := MakeVertex(R.X,       R.Y,       C, 0, 0);
    V[I * 6 + 1] := MakeVertex(R.X + R.W, R.Y,       C, 0, 0);
    V[I * 6 + 2] := MakeVertex(R.X + R.W, R.Y + R.H, C, 0, 0);
    V[I * 6 + 3] := MakeVertex(R.X,       R.Y,       C, 0, 0);
    V[I * 6 + 4] := MakeVertex(R.X + R.W, R.Y + R.H, C, 0, 0);
    V[I * 6 + 5] := MakeVertex(R.X,       R.Y + R.H, C, 0, 0);
  end;
  ACmd.Kind := TPMLRenderCommandKind.Geometry;
  ACmd.Texture := nil;
  QueueGeometry(AQueue, ACmd, V);
end;

{ テクスチャ転送を、テクスチャ座標つきの三角形 2 枚にする。 }
procedure TPMLRenderDriver.QueueCopyAsGeometry(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; ATexture: TPMLTexture;
  const ASrc, ADst: TPMLFRect);
var
  V: array[0..5] of TPMLVertex;
  U0, V0, U1, V1: Single;
  C: TPMLFColor;
begin
  U0 := ASrc.X / ATexture.Width;
  V0 := ASrc.Y / ATexture.Height;
  U1 := (ASrc.X + ASrc.W) / ATexture.Width;
  V1 := (ASrc.Y + ASrc.H) / ATexture.Height;
  // 転送は変調色を頂点色として持たせる。白 x 変調 = 変調そのもの。
  C.R := ATexture.ColorMod.R / 255;
  C.G := ATexture.ColorMod.G / 255;
  C.B := ATexture.ColorMod.B / 255;
  C.A := ATexture.AlphaMod / 255;
  V[0] := MakeVertex(ADst.X,          ADst.Y,          C, U0, V0);
  V[1] := MakeVertex(ADst.X + ADst.W, ADst.Y,          C, U1, V0);
  V[2] := MakeVertex(ADst.X + ADst.W, ADst.Y + ADst.H, C, U1, V1);
  V[3] := MakeVertex(ADst.X,          ADst.Y,          C, U0, V0);
  V[4] := MakeVertex(ADst.X + ADst.W, ADst.Y + ADst.H, C, U1, V1);
  V[5] := MakeVertex(ADst.X,          ADst.Y + ADst.H, C, U0, V1);
  ACmd.Kind := TPMLRenderCommandKind.Geometry;
  ACmd.Texture := ATexture;
  QueueGeometry(AQueue, ACmd, V);
end;

{ 点を 1x1 の矩形にする。点 (x, y) は画素 (floor x, floor y) を塗る。 }
procedure TPMLRenderDriver.QueueDrawPointsAsGeometry(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const APoints: array of TPMLFPoint);
var
  R: TPMLFRects;
  I: Integer;
begin
  SetLength(R, Length(APoints));
  for I := 0 to High(APoints) do
    R[I] := TPMLFRect.Make(Trunc(APoints[I].X), Trunc(APoints[I].Y), 1, 1);
  QueueFillRectsAsGeometry(AQueue, ACmd, R);
end;

{ 折れ線を、1 画素幅の矩形の並びにする。

  水平・垂直の線は正確に 1 画素幅になる。斜めの線は矩形を並べた近似で、
  ブレゼンハムの線とは一致しない。線を正確に描きたいドライバは
  QueueDrawLines を上書きする（ソフトウェアドライバはそうしている）。 }
procedure TPMLRenderDriver.QueueDrawLinesAsGeometry(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const APoints: array of TPMLFPoint);
var
  R: TPMLFRects;
  I, N: Integer;
  X1, Y1, X2, Y2: Single;
begin
  if Length(APoints) < 2 then
    Exit;
  SetLength(R, Length(APoints) - 1);
  N := 0;
  for I := 0 to High(APoints) - 1 do
  begin
    X1 := Trunc(APoints[I].X);
    Y1 := Trunc(APoints[I].Y);
    X2 := Trunc(APoints[I + 1].X);
    Y2 := Trunc(APoints[I + 1].Y);
    if X1 > X2 then begin R[N].X := X2; R[N].W := X1 - X2 + 1; end
    else begin R[N].X := X1; R[N].W := X2 - X1 + 1; end;
    if Y1 > Y2 then begin R[N].Y := Y2; R[N].H := Y1 - Y2 + 1; end
    else begin R[N].Y := Y1; R[N].H := Y2 - Y1 + 1; end;
    Inc(N);
  end;
  QueueFillRectsAsGeometry(AQueue, ACmd, R);
end;

procedure TPMLRenderDriver.QueueFillRects(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const ARects: array of TPMLFRect);
begin
  QueueFillRectsAsGeometry(AQueue, ACmd, ARects);
end;

procedure TPMLRenderDriver.QueueCopy(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; ATexture: TPMLTexture;
  const ASrc, ADst: TPMLFRect);
begin
  QueueCopyAsGeometry(AQueue, ACmd, ATexture, ASrc, ADst);
end;

procedure TPMLRenderDriver.QueueDrawPoints(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const APoints: array of TPMLFPoint);
begin
  QueueDrawPointsAsGeometry(AQueue, ACmd, APoints);
end;

procedure TPMLRenderDriver.QueueDrawLines(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const APoints: array of TPMLFPoint);
begin
  QueueDrawLinesAsGeometry(AQueue, ACmd, APoints);
end;

{ TPMLTexture }

constructor TPMLTexture.Create(ARenderer: TPMLRenderer; AFormat: TPMLPixelFormat;
  AAccess: TPMLTextureAccess; AWidth, AHeight: Integer);
begin
  inherited Create(nil, ARenderer);
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EPMLArgument.CreateFmt('texture size must be positive (%d x %d)',
      [AWidth, AHeight]);
  FRenderer := ARenderer;
  FFormat := AFormat;
  FAccess := AAccess;
  FWidth := AWidth;
  FHeight := AHeight;
  FBlendMode := TPMLBlendMode.None;
  FColorMod := TPMLColor.White;
  FAlphaMod := 255;
  FScaleMode := TPMLScaleMode.Nearest;
end;

destructor TPMLTexture.Destroy;
begin
  if FRenderer <> nil then
  begin
    // 積んだ描画がこのテクスチャを指しているかもしれない。消す前に吐き出す
    // （SDL_DestroyTexture の FlushRenderCommandsIfTextureNeeded。D-39）。
    // 吐き出さないと、Present のときに解放済みのテクスチャを読む。
    FRenderer.Flush;
    FRenderer.Driver.DestroyTexture(Self);
    FRenderer.RemoveTexture(Self);
  end;
  FreeAndNil(DriverData);
  inherited Destroy;
end;

{ レンダラが先に消える。ドライバはもう使えないので、中身だけ畳んで自分も消える。 }
procedure TPMLTexture.OwnerDestroying;
begin
  if FRenderer <> nil then
    FRenderer.Driver.DestroyTexture(Self);
  FRenderer := nil;
  inherited OwnerDestroying;
end;

procedure TPMLTexture.Update(const ARect: TPMLRect; APixels: Pointer;
  APitch: Integer);
var
  R: TPMLRect;
begin
  if FRenderer = nil then
    raise EPMLRenderError.Create('texture has no renderer');
  if ARect.IsEmpty then
    R := TPMLRect.Make(0, 0, FWidth, FHeight)
  else
    R := ARect;
  // 積んだ描画がこのテクスチャの古い中身を読むかもしれない。先に吐き出す。
  FRenderer.Flush;
  if not FRenderer.Driver.UpdateTexture(Self, R, APixels, APitch) then
    raise EPMLRenderError.Create('texture update failed');
end;

{ TPMLRenderer }

constructor TPMLRenderer.Create(ADriver: TPMLRenderDriver);
begin
  inherited Create(nil, nil);
  if ADriver = nil then
    raise EPMLArgument.Create('renderer needs a driver');
  FDriver := ADriver;
  FQueue := TPMLRenderQueue.Create;
  FDrawColor := TPMLFColor.Make(0, 0, 0, 1);
  FBlendMode := TPMLBlendMode.None;
  FScale := TPMLFPoint.Make(1, 1);
  FLogicalScale := TPMLFPoint.Make(1, 1);
  FCurrentScale := FScale;
end;

constructor TPMLRenderer.CreateForWindow(AWindow: TPMLWindow;
  const ADriverName: String);
var
  Index, I: Integer;
begin
  if AWindow = nil then
    raise EPMLArgument.Create('CreateForWindow needs a window');
  // 名前の解決はドライバを作る前に済ませる（未登録なら何も作らずに断る）。
  Index := -1;
  if ADriverName <> '' then
  begin
    if not SameText(ADriverName, 'software') then
    begin
      Index := FindRenderDriverIndex(ADriverName);
      if Index < 0 then
        raise EPMLUnsupported.CreateNative(
          Format('render driver "%s" is not available (available: %s); '
            + 'add PaPiMeLa.Backends (or PaPiMeLa) to uses to link the built-in drivers',
            [ADriverName, String.Join(', ', PMLRenderDriverNames)]), 0, 'render');
    end;
  end
  else
    for I := 0 to High(RenderDriverRegistry) do
      if RenderDriverRegistry[I].Prefers(AWindow) then
      begin
        Index := I;
        Break;
      end;
  inherited Create(AWindow.ContextRef, AWindow);
  FQueue := TPMLRenderQueue.Create;
  FDrawColor := TPMLFColor.Make(0, 0, 0, 1);
  FBlendMode := TPMLBlendMode.None;
  FScale := TPMLFPoint.Make(1, 1);
  FLogicalScale := TPMLFPoint.Make(1, 1);
  FCurrentScale := FScale;
  // 名前が無ければ、登録されたドライバのうち選ぶと答えた最初のもの。GL で作った
  // ウィンドウには GPU のドライバを選ぶ（SDL も既定では GPU を優先する）。
  if Index >= 0 then
    FDriver := RenderDriverRegistry[Index].Factory(AWindow)
  else
    FDriver := TPMLWindowSoftwareRenderDriver.Create(AWindow);
  // 登録は最後。ここまでで例外が出たら Destroy が走るが、まだ登録していない。
  FWindow := AWindow;
  AWindow.AddDependent(Self);
end;

class function TPMLRenderer.CreateSoftware(ATarget: TPMLSurface): TPMLRenderer;
begin
  if ATarget = nil then
    raise EPMLArgument.Create('software renderer needs a target surface');
  Result := TPMLRenderer.Create(TPMLSoftwareRenderDriver.Create(ATarget));
end;

destructor TPMLRenderer.Destroy;
var
  I: Integer;
begin
  // テクスチャはドライバが中身を持っているので、ドライバより先に畳む。
  for I := High(FTextures) downto 0 do
    if FTextures[I] <> nil then
      FTextures[I].OwnerDestroying;
  SetLength(FTextures, 0);
  FreeAndNil(FQueue);
  FreeAndNil(FDriver);
  inherited Destroy;
end;

procedure TPMLRenderer.DetachFromOwner;
begin
  // アプリが先に Free した。ウィンドウの一覧から外れる。
  if FWindow <> nil then
    FWindow.RemoveDependent(Self);
  FWindow := nil;
  inherited DetachFromOwner;
end;

procedure TPMLRenderer.WindowDestroying(AWindow: TPMLWindow);
begin
  // ウィンドウは一覧から外してから呼んでいる。
  FWindow := nil;
  OwnerDestroying;
end;

procedure TPMLRenderer.SetVSync(AValue: Integer);
begin
  if AValue = FVSync then
    Exit;
  if not FDriver.SetVSync(AValue) then
    raise EPMLUnsupported.CreateNative(
      Format('driver %s does not support VSync %d', [FDriver.Name, AValue]), 0, 'render');
  FVSync := AValue;
end;

procedure TPMLRenderer.RemoveTexture(ATexture: TPMLTexture);
var
  I, J: Integer;
begin
  // 文字の表も Textures に載るので、アプリが解放することがある。次の DebugText で作り直す。
  if ATexture = FDebugFont then
    FDebugFont := nil;
  for I := 0 to High(FTextures) do
    if FTextures[I] = ATexture then
    begin
      for J := I to High(FTextures) - 1 do
        FTextures[J] := FTextures[J + 1];
      SetLength(FTextures, Length(FTextures) - 1);
      Exit;
    end;
end;

function TPMLRenderer.GetDrawColor: TPMLColor;
begin
  Result := FDrawColor.ToColor;
end;

procedure TPMLRenderer.SetDrawColor(const AValue: TPMLColor);
begin
  FDrawColor := TPMLFColor.FromColor(AValue);
end;

procedure TPMLRenderer.SetViewport(const AValue: TPMLRect);
begin
  if (not AValue.IsEmpty) and ((AValue.W < 0) or (AValue.H < 0)) then
    raise EPMLArgument.Create('viewport has a negative size');
  FViewport := AValue;
end;

procedure TPMLRenderer.SetClipRect(const AValue: TPMLRect);
begin
  FClipRect := AValue;
  FClipEnabled := not AValue.IsEmpty;
end;

function TPMLRenderer.GetDriverName: String;
begin
  Result := FDriver.Name;
end;

function TPMLRenderer.GetOutputSize(out AWidth, AHeight: Integer): Boolean;
begin
  Result := FDriver.GetOutputSize(AWidth, AHeight);
end;

{ 状態が最後に積んだものと違うときだけ状態コマンドを積む。

  PORT-NOTE: SDL_render.c の QueueCmdSetViewport / QueueCmdSetClipRect と同じ。
  描画のたびに状態コマンドを積むと、ドライバが毎回状態を設定し直すことになる。 }
procedure TPMLRenderer.QueueStateIfChanged;
var
  Cmd: TPMLRenderCommand;
  VP, Clip: TPMLRect;
begin
  // 出力の大きさが変わっていれば当てはめ直す。ビューポートとクリップは画素の
  // 矩形にしてから比べる（倍率や論理解像度が変われば、同じ設定でも画素は変わる）。
  UpdateView;
  VP := PixelViewport;
  Clip := PixelClipRect;

  if (not FStateQueued)
  or (VP.X <> FQueuedViewport.X) or (VP.Y <> FQueuedViewport.Y)
  or (VP.W <> FQueuedViewport.W) or (VP.H <> FQueuedViewport.H) then
  begin
    FillChar(Cmd, SizeOf(Cmd), 0);
    Cmd.Kind := TPMLRenderCommandKind.SetViewport;
    Cmd.Rect := VP;
    FQueue.Push(Cmd);
    FQueuedViewport := VP;
  end;

  if (not FStateQueued) or (FClipEnabled <> FQueuedClipOn)
  or (FClipEnabled and ((Clip.X <> FQueuedClip.X) or (Clip.Y <> FQueuedClip.Y)
      or (Clip.W <> FQueuedClip.W) or (Clip.H <> FQueuedClip.H))) then
  begin
    FillChar(Cmd, SizeOf(Cmd), 0);
    Cmd.Kind := TPMLRenderCommandKind.SetClipRect;
    Cmd.Rect := Clip;
    Cmd.Enabled := FClipEnabled;
    FQueue.Push(Cmd);
    FQueuedClip := Clip;
    FQueuedClipOn := FClipEnabled;
  end;

  FStateQueued := True;
end;

function TPMLRenderer.NewDrawCommand(AKind: TPMLRenderCommandKind): TPMLRenderCommand;
begin
  QueueStateIfChanged;
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := AKind;
  Result.Color := FDrawColor;
  Result.Blend := FBlendMode;
  Result.ScaleMode := TPMLScaleMode.Nearest;
end;

procedure TPMLRenderer.Clear;
var
  Cmd: TPMLRenderCommand;
begin
  Cmd := NewDrawCommand(TPMLRenderCommandKind.Clear);
  FQueue.Push(Cmd);
end;

procedure TPMLRenderer.DrawPoint(AX, AY: Single);
begin
  DrawPoints([TPMLFPoint.Make(AX, AY)]);
end;

procedure TPMLRenderer.DrawPoints(const APoints: array of TPMLFPoint);
var
  Cmd: TPMLRenderCommand;
begin
  if Length(APoints) = 0 then
    Exit;
  UpdateView;
  if IsScaled then
  begin
    DrawPointsAsRects(APoints);
    Exit;
  end;
  Cmd := NewDrawCommand(TPMLRenderCommandKind.DrawPoints);
  FDriver.QueueDrawPoints(FQueue, Cmd, APoints);
  FQueue.Push(Cmd);
end;

procedure TPMLRenderer.DrawLine(AX1, AY1, AX2, AY2: Single);
begin
  DrawLines([TPMLFPoint.Make(AX1, AY1), TPMLFPoint.Make(AX2, AY2)]);
end;

procedure TPMLRenderer.DrawLines(const APoints: array of TPMLFPoint);
var
  Cmd: TPMLRenderCommand;
begin
  if Length(APoints) < 2 then
    Exit;
  // SDL_RenderLines と同じ振り分け。論理解像度では三角形、倍率だけなら矩形の
  // 並び、どちらも無ければドライバの線。
  UpdateView;
  if FLogicalMode <> TPMLLogicalPresentation.Disabled then
  begin
    DrawLinesAsGeometry(APoints);
    Exit;
  end;
  if IsScaled then
  begin
    DrawLinesAsRects(APoints);
    Exit;
  end;
  Cmd := NewDrawCommand(TPMLRenderCommandKind.DrawLines);
  FDriver.QueueDrawLines(FQueue, Cmd, APoints);
  FQueue.Push(Cmd);
end;

{ 枠線。4 辺を折れ線として描き、始点へ戻る。 }
procedure TPMLRenderer.DrawRect(const ARect: TPMLFRect);
var
  X2, Y2: Single;
begin
  if ARect.IsEmpty then
    Exit;
  X2 := ARect.X + ARect.W - 1;
  Y2 := ARect.Y + ARect.H - 1;
  DrawLines([TPMLFPoint.Make(ARect.X, ARect.Y), TPMLFPoint.Make(X2, ARect.Y),
             TPMLFPoint.Make(X2, Y2), TPMLFPoint.Make(ARect.X, Y2),
             TPMLFPoint.Make(ARect.X, ARect.Y)]);
end;

procedure TPMLRenderer.FillRect(const ARect: TPMLFRect);
begin
  FillRects([ARect]);
end;

procedure TPMLRenderer.FillRects(const ARects: array of TPMLFRect);
var
  R: TPMLFRects;
  I: Integer;
begin
  if Length(ARects) = 0 then
    Exit;
  UpdateView;
  SetLength(R, Length(ARects));
  for I := 0 to High(ARects) do
    R[I] := TPMLFRect.Make(ARects[I].X * FCurrentScale.X, ARects[I].Y * FCurrentScale.Y,
      ARects[I].W * FCurrentScale.X, ARects[I].H * FCurrentScale.Y);
  QueueFillRectsRaw(R);
end;

procedure TPMLRenderer.RenderTexture(ATexture: TPMLTexture;
  const ASrc, ADst: TPMLFRect);
var
  Cmd: TPMLRenderCommand;
  S, D: TPMLFRect;
begin
  if ATexture = nil then
    Exit;
  if ATexture.Renderer <> Self then
    raise EPMLArgument.Create('texture belongs to another renderer');
  if ASrc.IsEmpty then
    S := TPMLFRect.Make(0, 0, ATexture.Width, ATexture.Height)
  else
    S := ASrc;
  // 空の転送先はビューポート全体（アプリの座標。論理解像度なら論理画面）。
  UpdateView;
  if ADst.IsEmpty then
    D := ViewportSize
  else
    D := ADst;
  D := TPMLFRect.Make(D.X * FCurrentScale.X, D.Y * FCurrentScale.Y,
    D.W * FCurrentScale.X, D.H * FCurrentScale.Y);

  Cmd := NewDrawCommand(TPMLRenderCommandKind.Copy);
  Cmd.Texture := ATexture;
  // 変調色と合成は積んだときの値を持たせる（SDL の PrepQueueCmdDraw と同じ。D-43）。
  Cmd.Color := TPMLFColor.FromColor(TPMLColor.Make(ATexture.ColorMod.R,
    ATexture.ColorMod.G, ATexture.ColorMod.B, ATexture.AlphaMod));
  Cmd.Blend := ATexture.BlendMode;
  Cmd.ScaleMode := ATexture.ScaleMode;
  FDriver.QueueCopy(FQueue, Cmd, ATexture, S, D);
  FQueue.Push(Cmd);
end;

procedure TPMLRenderer.RenderGeometry(ATexture: TPMLTexture;
  const AVertices: array of TPMLVertex; const AIndices: array of Integer);
var
  Cmd: TPMLRenderCommand;
  V: TPMLVertices;
  I: Integer;
begin
  if Length(AIndices) > 0 then
  begin
    SetLength(V, Length(AIndices));
    for I := 0 to High(AIndices) do
    begin
      if (AIndices[I] < 0) or (AIndices[I] > High(AVertices)) then
        raise EPMLArgument.CreateFmt('geometry index %d out of range', [AIndices[I]]);
      V[I] := AVertices[AIndices[I]];
    end;
  end
  else
  begin
    SetLength(V, Length(AVertices));
    for I := 0 to High(AVertices) do
      V[I] := AVertices[I];
  end;
  if (Length(V) < 3) or (Length(V) mod 3 <> 0) then
    raise EPMLArgument.CreateFmt('geometry needs a multiple of 3 vertices, got %d',
      [Length(V)]);
  UpdateView;
  for I := 0 to High(V) do
  begin
    V[I].Position.X := V[I].Position.X * FCurrentScale.X;
    V[I].Position.Y := V[I].Position.Y * FCurrentScale.Y;
  end;

  Cmd := NewDrawCommand(TPMLRenderCommandKind.Geometry);
  Cmd.Texture := ATexture;
  if ATexture <> nil then
  begin
    Cmd.Blend := ATexture.BlendMode;
    Cmd.ScaleMode := ATexture.ScaleMode;
  end;
  FDriver.QueueGeometry(FQueue, Cmd, V);
  FQueue.Push(Cmd);
end;

procedure TPMLRenderer.Flush;
begin
  if FQueue.CommandCount = 0 then
    Exit;
  FDriver.RunCommandQueue(FQueue);
  FQueue.Reset;
  // 次の描画では状態コマンドを積み直す。ドライバが状態を持ち越す保証はない。
  FStateQueued := False;
end;

procedure TPMLRenderer.Present;
begin
  Flush;
  FDriver.Present;
end;

function TPMLRenderer.ReadPixels(const ARect: TPMLRect): TPMLSurface;
var
  R: TPMLRect;
  W, H: Integer;
begin
  Flush;
  if ARect.IsEmpty then
  begin
    if not FDriver.GetOutputSize(W, H) then
      raise EPMLRenderError.Create('output size unknown');
    R := TPMLRect.Make(0, 0, W, H);
  end
  else
    R := ARect;
  Result := FDriver.ReadPixels(R);
end;

function TPMLRenderer.CreateTexture(AFormat: TPMLPixelFormat;
  AAccess: TPMLTextureAccess; AWidth, AHeight: Integer): TPMLTexture;
begin
  Result := TPMLTexture.Create(Self, AFormat, AAccess, AWidth, AHeight);
  try
    if not FDriver.CreateTexture(Result) then
      raise EPMLRenderError.CreateFmt('driver %s could not create a %s texture',
        [FDriver.Name, PMLPixelFormatName(AFormat)]);
  except
    // ドライバが作れなかったので、レンダラの一覧へ載せる前に捨てる。
    Result.Free;
    raise;
  end;
  SetLength(FTextures, Length(FTextures) + 1);
  FTextures[High(FTextures)] := Result;
end;

function TPMLRenderer.CreateTextureFromSurface(ASurface: TPMLSurface): TPMLTexture;
var
  Src: TPMLSurface;
begin
  if ASurface = nil then
    raise EPMLArgument.Create('CreateTextureFromSurface needs a surface');
  // ドライバが直接持てない形式は ARGB8888 に変換する（SDL も対応形式へ変換する）。
  if FDriver.SupportsTextureFormat(ASurface.Format) then
    Src := ASurface
  else
    Src := ASurface.Convert(PML_PIXELFORMAT_ARGB8888);
  try
    Result := CreateTexture(Src.Format, TPMLTextureAccess.Static, Src.Width, Src.Height);
    Result.Update(TPMLRect.Make(0, 0, 0, 0), Src.Pixels, Src.Pitch);
  finally
    if Src <> ASurface then
      Src.Free;
  end;
  // SDL と同じく、アルファを持つサーフェスから作ったテクスチャは Blend にする。
  if ASurface.Details.HasAlpha then
    Result.BlendMode := TPMLBlendMode.Blend;
end;

{ ---- 拡大率と論理解像度 ----

  PORT-NOTE: SDL_render.c の SDL_RenderViewState（main_view）を、レンダラの
  フィールドに直接持つ。描画先テクスチャ（SetRenderTarget）が入れば、
  テクスチャごとの view が要るので、そのとき record にまとめる。

  座標の流れは SDL と同じ:
    アプリの座標 x  →  x * FCurrentScale（積むときに掛ける）
    ビューポートの原点 →  floor(vp.x * FCurrentScale + 論理画面の左上)（状態コマンド）
  ドライバは画素の座標だけを見る。 }

procedure TPMLRenderer.SetScale(const AValue: TPMLFPoint);
begin
  FScale := AValue;
  // 倍率はビューポートとクリップの画素の位置も変える。積み直しは次の描画の
  // QueueStateIfChanged が、画素の矩形を比べて決める。
  UpdateView;
end;

{ 論理画面の当てはめを出力の今の大きさで計算し直す。

  PORT-NOTE: SDL は UpdateLogicalPresentation をウィンドウの大きさが変わった
  イベントで呼ぶ。papimela のレンダラはウィンドウのイベントを受けないので、
  描画を積むたびと、当てはめを問い合わせるたびに出力の大きさから計算し直す。
  計算は四則演算だけで、GetOutputSize はドライバが持っている値を返すだけ。 }
procedure TPMLRenderer.UpdateView;
var
  IW, IH: Integer;
  OW, OH, LW, LH, WantAspect, RealAspect, S: Single;
begin
  if not FDriver.GetOutputSize(IW, IH) then
  begin
    IW := 0;
    IH := 0;
  end;
  LW := FLogicalW;
  LH := FLogicalH;

  if FLogicalMode = TPMLLogicalPresentation.Disabled then
  begin
    FLogicalDst := TPMLFRect.Make(0, 0, IW, IH);
    FLogicalScale := TPMLFPoint.Make(1, 1);
    FCurrentScale := FScale;
  end
  else
  begin
    OW := IW;
    OH := IH;
    if (LW <= 0) or (LH <= 0) or (OW <= 0) or (OH <= 0) then
      FLogicalDst := TPMLFRect.Make(0, 0, OW, OH)
    else
    begin
      WantAspect := LW / LH;
      RealAspect := OW / OH;
      if FLogicalMode = TPMLLogicalPresentation.IntegerScale then
      begin
        // 整数の割り算（SDL と同じく、切り捨ててから 1 倍未満を 1 倍にする）。
        if WantAspect > RealAspect then
          S := IW div FLogicalW
        else
          S := IH div FLogicalH;
        if S < 1 then
          S := 1;
        FLogicalDst.W := Floor(LW * S);
        FLogicalDst.X := (OW - FLogicalDst.W) / 2;
        FLogicalDst.H := Floor(LH * S);
        FLogicalDst.Y := (OH - FLogicalDst.H) / 2;
      end
      else if (FLogicalMode = TPMLLogicalPresentation.Stretch)
           or (Abs(WantAspect - RealAspect) < 0.0001) then
        FLogicalDst := TPMLFRect.Make(0, 0, OW, OH)
      else if WantAspect > RealAspect then
      begin
        if FLogicalMode = TPMLLogicalPresentation.Letterbox then
        begin
          // 論理画面のほうが横長。幅を合わせ、上下に帯。
          S := OW / LW;
          FLogicalDst.X := 0;
          FLogicalDst.W := OW;
          FLogicalDst.H := Floor(LH * S);
          FLogicalDst.Y := (OH - FLogicalDst.H) / 2;
        end
        else
        begin
          // Overscan: 高さを合わせ、左右がはみ出る。
          S := OH / LH;
          FLogicalDst.Y := 0;
          FLogicalDst.H := OH;
          FLogicalDst.W := Floor(LW * S);
          FLogicalDst.X := (OW - FLogicalDst.W) / 2;
        end;
      end
      else
      begin
        if FLogicalMode = TPMLLogicalPresentation.Letterbox then
        begin
          // 論理画面のほうが縦長。高さを合わせ、左右に帯。
          S := OH / LH;
          FLogicalDst.Y := 0;
          FLogicalDst.H := OH;
          FLogicalDst.W := Floor(LW * S);
          FLogicalDst.X := (OW - FLogicalDst.W) / 2;
        end
        else
        begin
          // Overscan: 幅を合わせ、上下がはみ出る。
          S := OW / LW;
          FLogicalDst.X := 0;
          FLogicalDst.W := OW;
          FLogicalDst.H := Floor(LH * S);
          FLogicalDst.Y := (OH - FLogicalDst.H) / 2;
        end;
      end;
    end;

    if LW > 0 then FLogicalScale.X := FLogicalDst.W / LW else FLogicalScale.X := 0;
    if LH > 0 then FLogicalScale.Y := FLogicalDst.H / LH else FLogicalScale.Y := 0;
    FCurrentScale.X := FScale.X * FLogicalScale.X;
    FCurrentScale.Y := FScale.Y * FLogicalScale.Y;
  end;

  FPixelW := Trunc(FLogicalDst.W);
  FPixelH := Trunc(FLogicalDst.H);
end;

{ ビューポートの画素の矩形（SDL の UpdatePixelViewport）。空のビューポート
  （設定なし）は論理画面の全体。 }
function TPMLRenderer.PixelViewport: TPMLRect;
begin
  Result.X := Floor(FViewport.X * FCurrentScale.X + FLogicalDst.X);
  Result.Y := Floor(FViewport.Y * FCurrentScale.Y + FLogicalDst.Y);
  if FViewport.IsEmpty then
  begin
    Result.W := FPixelW;
    Result.H := FPixelH;
  end
  else
  begin
    Result.W := Ceil(FViewport.W * FCurrentScale.X);
    Result.H := Ceil(FViewport.H * FCurrentScale.Y);
  end;
end;

// クリップ矩形の画素の矩形。ビューポートの原点からの位置（SDL の UpdatePixelClipRect）。
function TPMLRenderer.PixelClipRect: TPMLRect;
begin
  Result.X := Floor(FClipRect.X * FCurrentScale.X);
  Result.Y := Floor(FClipRect.Y * FCurrentScale.Y);
  Result.W := Ceil(FClipRect.W * FCurrentScale.X);
  Result.H := Ceil(FClipRect.H * FCurrentScale.Y);
end;

// ビューポートの大きさ（アプリの座標）。原点は 0（SDL の GetRenderViewportSize）。
function TPMLRenderer.ViewportSize: TPMLFRect;
begin
  Result.X := 0;
  Result.Y := 0;
  if FViewport.IsEmpty then
  begin
    if FCurrentScale.X <> 0 then Result.W := FPixelW / FCurrentScale.X else Result.W := 0;
    if FCurrentScale.Y <> 0 then Result.H := FPixelH / FCurrentScale.Y else Result.H := 0;
  end
  else
  begin
    Result.W := FViewport.W;
    Result.H := FViewport.H;
  end;
end;

function TPMLRenderer.IsScaled: Boolean;
begin
  Result := (FCurrentScale.X <> 1) or (FCurrentScale.Y <> 1);
end;

// 画素の座標になった矩形を積む。倍率は掛けない。
procedure TPMLRenderer.QueueFillRectsRaw(const ARects: array of TPMLFRect);
var
  Cmd: TPMLRenderCommand;
begin
  if Length(ARects) = 0 then
    Exit;
  Cmd := NewDrawCommand(TPMLRenderCommandKind.FillRects);
  FDriver.QueueFillRects(FQueue, Cmd, ARects);
  FQueue.Push(Cmd);
end;

{ 倍率がかかった点は、倍率の大きさの矩形（SDL の RenderPointsWithRects）。 }
procedure TPMLRenderer.DrawPointsAsRects(const APoints: array of TPMLFPoint);
var
  R: TPMLFRects;
  I: Integer;
begin
  SetLength(R, Length(APoints));
  for I := 0 to High(APoints) do
    R[I] := TPMLFRect.Make(APoints[I].X * FCurrentScale.X, APoints[I].Y * FCurrentScale.Y,
      FCurrentScale.X, FCurrentScale.Y);
  QueueFillRectsRaw(R);
end;

{ 論理解像度のもとの折れ線（SDL_RenderLines の geometry の経路）。

  各点を倍率の大きさの四角（頂点 4 つ）にし、隣り合う四角を三角形で
  つなぐ。四角の頂点の番号は、前の点 p が 0..3、今の点 q が 4..7:

        p            q
        0----1------ 4----5
        | \  |``\    | \  |
        |  \ |   ` `\|  \ |
        3----2-------7----6

  閉じた折れ線（始点 = 終点）は、始点の四角を 2 回塗らないよう最初の
  四角を省く。 }
procedure TPMLRenderer.DrawLinesAsGeometry(const APoints: array of TPMLFPoint);
var
  XY: array of TPMLFPoint;
  Idx: TPMLIndices;
  NIdx, Cur, I: Integer;
  SX, SY: Single;
  P, Q: TPMLFPoint;
  Looping: Boolean;
  V: TPMLVertices;
  Cmd: TPMLRenderCommand;

  procedure Tri(A, B, C: Integer);
  begin
    Idx[NIdx] := Cur + A;
    Idx[NIdx + 1] := Cur + B;
    Idx[NIdx + 2] := Cur + C;
    Inc(NIdx, 3);
  end;

begin
  SX := FCurrentScale.X;
  SY := FCurrentScale.Y;
  SetLength(XY, 4 * Length(APoints));
  // 線分 1 本あたり最大 4 枚、点 1 つあたり 2 枚。
  SetLength(Idx, 4 * 3 * (Length(APoints) - 1) + 2 * 3 * Length(APoints));
  NIdx := 0;
  Cur := -4;
  Looping := (APoints[0].X = APoints[High(APoints)].X)
         and (APoints[0].Y = APoints[High(APoints)].Y);
  P := TPMLFPoint.Make(0, 0);
  for I := 0 to High(APoints) do
  begin
    Q := TPMLFPoint.Make(APoints[I].X * SX, APoints[I].Y * SY);
    XY[I * 4 + 0] := Q;
    XY[I * 4 + 1] := TPMLFPoint.Make(Q.X + SX, Q.Y);
    XY[I * 4 + 2] := TPMLFPoint.Make(Q.X + SX, Q.Y + SY);
    XY[I * 4 + 3] := TPMLFPoint.Make(Q.X, Q.Y + SY);

    if (I > 0) or not Looping then
    begin
      Tri(4, 5, 6);
      Tri(4, 6, 7);
    end;

    if I = 0 then
    begin
      P := Q;
      Inc(Cur, 4);
      Continue;
    end;

    if P.Y = Q.Y then
    begin
      if P.X < Q.X then begin Tri(1, 4, 7); Tri(1, 7, 2); end
      else begin Tri(5, 0, 3); Tri(5, 3, 6); end;
    end
    else if P.X = Q.X then
    begin
      if P.Y < Q.Y then begin Tri(2, 5, 4); Tri(2, 4, 3); end
      else begin Tri(6, 1, 0); Tri(6, 0, 7); end;
    end
    else if P.Y < Q.Y then
    begin
      if P.X < Q.X then
      begin
        Tri(1, 5, 4); Tri(1, 4, 2); Tri(2, 4, 7); Tri(2, 7, 3);
      end
      else
      begin
        Tri(4, 0, 5); Tri(5, 0, 3); Tri(5, 3, 6); Tri(6, 3, 2);
      end;
    end
    else
    begin
      if P.X < Q.X then
      begin
        Tri(0, 4, 7); Tri(0, 7, 1); Tri(1, 7, 6); Tri(1, 6, 2);
      end
      else
      begin
        Tri(6, 5, 1); Tri(6, 1, 0); Tri(7, 6, 0); Tri(7, 0, 3);
      end;
    end;

    P := Q;
    Inc(Cur, 4);
  end;

  if NIdx = 0 then
    Exit;
  SetLength(V, NIdx);
  for I := 0 to NIdx - 1 do
  begin
    V[I].Position := XY[Idx[I]];
    V[I].Color := FDrawColor;
    V[I].TexCoord := TPMLFPoint.Make(0, 0);
  end;
  Cmd := NewDrawCommand(TPMLRenderCommandKind.Geometry);
  FDriver.QueueGeometry(FQueue, Cmd, V);
  FQueue.Push(Cmd);
end;

{ 倍率だけがかかった折れ線（SDL の RenderLinesWithRectsF）。

  水平・垂直の線分は 1 本の矩形、斜めはブレゼンハムの点を倍率の大きさの
  矩形で。線分の終点は次の線分の始点なので描かない。最後の線分だけは
  終点も描く。ただし閉じた折れ線なら、終点は最初の線分の始点として
  もう描いてあるので描かない。 }
procedure TPMLRenderer.DrawLinesAsRects(const APoints: array of TPMLFPoint);
var
  R: TPMLFRects;
  N, I, Last: Integer;
  SameX, SameY, DrewLine, DrawLast: Boolean;
  MinV, MaxV: Single;
begin
  SetLength(R, Length(APoints) - 1);
  N := 0;
  DrewLine := False;
  DrawLast := False;
  for I := 0 to High(APoints) - 1 do
  begin
    SameX := APoints[I].X = APoints[I + 1].X;
    SameY := APoints[I].Y = APoints[I + 1].Y;

    if I = High(APoints) - 1 then
    begin
      if (not DrewLine) or (APoints[I + 1].X <> APoints[0].X)
      or (APoints[I + 1].Y <> APoints[0].Y) then
        DrawLast := True;
    end
    else if SameX and SameY then
      Continue;

    // DrawLast は 0 か 1 として長さに足す（SDL の bool の足し算）。
    Last := Ord(DrawLast);
    if SameX then
    begin
      MinV := Min(APoints[I].Y, APoints[I + 1].Y);
      MaxV := Max(APoints[I].Y, APoints[I + 1].Y);
      R[N].X := APoints[I].X * FCurrentScale.X;
      R[N].Y := MinV * FCurrentScale.Y;
      R[N].W := FCurrentScale.X;
      R[N].H := (MaxV - MinV + Last) * FCurrentScale.Y;
      // 上向きの線分は、描かない終点が上端にあるので 1 つ下げる。
      if (not DrawLast) and (APoints[I + 1].Y < APoints[I].Y) then
        R[N].Y := R[N].Y + FCurrentScale.Y;
      Inc(N);
    end
    else if SameY then
    begin
      MinV := Min(APoints[I].X, APoints[I + 1].X);
      MaxV := Max(APoints[I].X, APoints[I + 1].X);
      R[N].X := MinV * FCurrentScale.X;
      R[N].Y := APoints[I].Y * FCurrentScale.Y;
      R[N].W := (MaxV - MinV + Last) * FCurrentScale.X;
      R[N].H := FCurrentScale.Y;
      if (not DrawLast) and (APoints[I + 1].X < APoints[I].X) then
        R[N].X := R[N].X + FCurrentScale.X;
      Inc(N);
    end
    else
      DrawLineBresenham(Round(APoints[I].X), Round(APoints[I].Y),
        Round(APoints[I + 1].X), Round(APoints[I + 1].Y), DrawLast);
    DrewLine := True;
  end;

  if N > 0 then
  begin
    SetLength(R, N);
    QueueFillRectsRaw(R);
  end;
end;

const
  // Cohen-Sutherland の領域の符号（SDL_rect_impl.h の CODE_*）。
  CodeBottom = 1;
  CodeTop    = 2;
  CodeLeft   = 4;
  CodeRight  = 8;

// AX2 / AY2 は矩形の右端・下端の画素（含む）。
function OutCode(AX1, AY1, AX2, AY2, AX, AY: Integer): Integer;
begin
  Result := 0;
  if AY < AY1 then
    Result := Result or CodeTop
  else if AY > AY2 then
    Result := Result or CodeBottom;
  if AX < AX1 then
    Result := Result or CodeLeft
  else if AX > AX2 then
    Result := Result or CodeRight;
end;

{ 線分を [0, AW) x [0, AH) の矩形で切る（SDL_GetRectAndLineIntersection の整数版）。
  矩形と交わらなければ False。 }
function ClipLineToRect(AW, AH: Integer; var AX1, AY1, AX2, AY2: Integer): Boolean;
var
  RX2, RY2, X1, Y1, X2, Y2, X, Y, C1, C2: Integer;
begin
  if (AW <= 0) or (AH <= 0) then
    Exit(False);
  RX2 := AW - 1;
  RY2 := AH - 1;
  X1 := AX1; Y1 := AY1; X2 := AX2; Y2 := AY2;

  if (X1 >= 0) and (X1 <= RX2) and (X2 >= 0) and (X2 <= RX2)
  and (Y1 >= 0) and (Y1 <= RY2) and (Y2 >= 0) and (Y2 <= RY2) then
    Exit(True);

  if ((X1 < 0) and (X2 < 0)) or ((X1 > RX2) and (X2 > RX2))
  or ((Y1 < 0) and (Y2 < 0)) or ((Y1 > RY2) and (Y2 > RY2)) then
    Exit(False);

  if Y1 = Y2 then
  begin
    AX1 := EnsureRange(X1, 0, RX2);
    AX2 := EnsureRange(X2, 0, RX2);
    Exit(True);
  end;
  if X1 = X2 then
  begin
    AY1 := EnsureRange(Y1, 0, RY2);
    AY2 := EnsureRange(Y2, 0, RY2);
    Exit(True);
  end;

  X := 0;
  Y := 0;
  C1 := OutCode(0, 0, RX2, RY2, X1, Y1);
  C2 := OutCode(0, 0, RX2, RY2, X2, Y2);
  while (C1 <> 0) or (C2 <> 0) do
  begin
    if (C1 and C2) <> 0 then
      Exit(False);
    // 交点の計算は 64 ビットで（SDL の BIGSCALARTYPE）。div は 0 へ向けて切り捨て、C と同じ。
    if C1 <> 0 then
    begin
      if (C1 and CodeTop) <> 0 then
      begin
        Y := 0;
        X := X1 + Integer((Int64(X2 - X1) * (Y - Y1)) div (Y2 - Y1));
      end
      else if (C1 and CodeBottom) <> 0 then
      begin
        Y := RY2;
        X := X1 + Integer((Int64(X2 - X1) * (Y - Y1)) div (Y2 - Y1));
      end
      else if (C1 and CodeLeft) <> 0 then
      begin
        X := 0;
        Y := Y1 + Integer((Int64(Y2 - Y1) * (X - X1)) div (X2 - X1));
      end
      else if (C1 and CodeRight) <> 0 then
      begin
        X := RX2;
        Y := Y1 + Integer((Int64(Y2 - Y1) * (X - X1)) div (X2 - X1));
      end;
      X1 := X;
      Y1 := Y;
      C1 := OutCode(0, 0, RX2, RY2, X, Y);
    end
    else
    begin
      if (C2 and CodeTop) <> 0 then
      begin
        Y := 0;
        X := X1 + Integer((Int64(X2 - X1) * (Y - Y1)) div (Y2 - Y1));
      end
      else if (C2 and CodeBottom) <> 0 then
      begin
        Y := RY2;
        X := X1 + Integer((Int64(X2 - X1) * (Y - Y1)) div (Y2 - Y1));
      end
      else if (C2 and CodeLeft) <> 0 then
      begin
        X := 0;
        Y := Y1 + Integer((Int64(Y2 - Y1) * (X - X1)) div (X2 - X1));
      end
      else if (C2 and CodeRight) <> 0 then
      begin
        X := RX2;
        Y := Y1 + Integer((Int64(Y2 - Y1) * (X - X1)) div (X2 - X1));
      end;
      X2 := X;
      Y2 := Y;
      C2 := OutCode(0, 0, RX2, RY2, X, Y);
    end;
  end;
  AX1 := X1; AY1 := Y1; AX2 := X2; AY2 := Y2;
  Result := True;
end;

{ 斜めの線分をブレゼンハムの点にして描く（SDL の RenderLineBresenham）。
  座標はアプリの座標（倍率を掛ける前）。

  PORT-NOTE: SDL は長すぎる線（ビューポートの画素の大きさの 4 倍を超える点）を
  エラーにする。papimela は先にビューポートで切るので、そこまで長くなる線は
  無い。上限の検査は写さない。 }
procedure TPMLRenderer.DrawLineBresenham(AX1, AY1, AX2, AY2: Integer;
  ADrawLast: Boolean);
var
  VP: TPMLRect;
  I, DeltaX, DeltaY, NumPixels, D, DInc1, DInc2: Integer;
  X, XInc1, XInc2, Y, YInc1, YInc2: Integer;
  Pts: array of TPMLFPoint;
begin
  // SDL と同じく、ビューポートの画素の大きさで（倍率を掛ける前の座標を）切る。
  // 描きすぎを防ぐ安全柵で、正確な切り取りはドライバがする。
  VP := PixelViewport;
  if not ClipLineToRect(VP.W, VP.H, AX1, AY1, AX2, AY2) then
    Exit;

  DeltaX := Abs(AX2 - AX1);
  DeltaY := Abs(AY2 - AY1);
  if DeltaX >= DeltaY then
  begin
    NumPixels := DeltaX + 1;
    D := (2 * DeltaY) - DeltaX;
    DInc1 := DeltaY * 2;
    DInc2 := (DeltaY - DeltaX) * 2;
    XInc1 := 1; XInc2 := 1;
    YInc1 := 0; YInc2 := 1;
  end
  else
  begin
    NumPixels := DeltaY + 1;
    D := (2 * DeltaX) - DeltaY;
    DInc1 := DeltaX * 2;
    DInc2 := (DeltaX - DeltaY) * 2;
    XInc1 := 0; XInc2 := 1;
    YInc1 := 1; YInc2 := 1;
  end;
  if AX1 > AX2 then
  begin
    XInc1 := -XInc1;
    XInc2 := -XInc2;
  end;
  if AY1 > AY2 then
  begin
    YInc1 := -YInc1;
    YInc2 := -YInc2;
  end;

  X := AX1;
  Y := AY1;
  if not ADrawLast then
    Dec(NumPixels);
  if NumPixels <= 0 then
    Exit;

  SetLength(Pts, NumPixels);
  for I := 0 to NumPixels - 1 do
  begin
    Pts[I] := TPMLFPoint.Make(X, Y);
    if D < 0 then
    begin
      Inc(D, DInc1);
      Inc(X, XInc1);
      Inc(Y, YInc1);
    end
    else
    begin
      Inc(D, DInc2);
      Inc(X, XInc2);
      Inc(Y, YInc2);
    end;
  end;

  if IsScaled then
    DrawPointsAsRects(Pts)
  else
    DrawPoints(Pts);
end;

procedure TPMLRenderer.SetLogicalPresentation(AW, AH: Integer;
  AMode: TPMLLogicalPresentation);
begin
  if AMode = TPMLLogicalPresentation.Disabled then
  begin
    FLogicalW := 0;
    FLogicalH := 0;
  end
  else
  begin
    FLogicalW := AW;
    FLogicalH := AH;
  end;
  FLogicalMode := AMode;
  UpdateView;
end;

procedure TPMLRenderer.GetLogicalPresentation(out AW, AH: Integer;
  out AMode: TPMLLogicalPresentation);
begin
  AW := FLogicalW;
  AH := FLogicalH;
  AMode := FLogicalMode;
end;

function TPMLRenderer.LogicalPresentationRect: TPMLFRect;
begin
  UpdateView;
  Result := FLogicalDst;
end;

{ ウィンドウの座標と画素の比（SDL の dpi_scale）。ウィンドウが無ければ 1。 }
function WindowPixelRatio(AWindow: TPMLWindow; AOutW, AOutH: Integer): TPMLFPoint;
begin
  Result := TPMLFPoint.Make(1, 1);
  if (AWindow <> nil) and (AWindow.Width > 0) and (AWindow.Height > 0)
  and (AOutW > 0) and (AOutH > 0) then
    Result := TPMLFPoint.Make(AOutW / AWindow.Width, AOutH / AWindow.Height);
end;

function TPMLRenderer.RenderCoordinatesFromWindow(AWindowX, AWindowY: Single): TPMLFPoint;
var
  OW, OH: Integer;
  Ratio: TPMLFPoint;
  X, Y: Single;
begin
  UpdateView;
  if not FDriver.GetOutputSize(OW, OH) then
  begin
    OW := 0;
    OH := 0;
  end;
  Ratio := WindowPixelRatio(FWindow, OW, OH);
  X := AWindowX * Ratio.X;
  Y := AWindowY * Ratio.Y;
  if (FLogicalMode <> TPMLLogicalPresentation.Disabled)
  and (FLogicalDst.W <> 0) and (FLogicalDst.H <> 0) then
  begin
    X := ((X - FLogicalDst.X) * FLogicalW) / FLogicalDst.W;
    Y := ((Y - FLogicalDst.Y) * FLogicalH) / FLogicalDst.H;
  end;
  // 倍率 0 は割らない。FPC は 0 除算を例外にする（C の SDL なら無限大になる）。
  if FScale.X <> 0 then X := X / FScale.X;
  if FScale.Y <> 0 then Y := Y / FScale.Y;
  Result.X := X - FViewport.X;
  Result.Y := Y - FViewport.Y;
end;

function TPMLRenderer.RenderCoordinatesToWindow(AX, AY: Single): TPMLFPoint;
var
  OW, OH: Integer;
  Ratio: TPMLFPoint;
  X, Y: Single;
begin
  UpdateView;
  if not FDriver.GetOutputSize(OW, OH) then
  begin
    OW := 0;
    OH := 0;
  end;
  Ratio := WindowPixelRatio(FWindow, OW, OH);
  X := (FViewport.X + AX) * FScale.X;
  Y := (FViewport.Y + AY) * FScale.Y;
  if (FLogicalMode <> TPMLLogicalPresentation.Disabled)
  and (FLogicalW <> 0) and (FLogicalH <> 0) then
  begin
    X := FLogicalDst.X + ((X * FLogicalDst.W) / FLogicalW);
    Y := FLogicalDst.Y + ((Y * FLogicalDst.H) / FLogicalH);
  end;
  Result.X := X / Ratio.X;
  Result.Y := Y / Ratio.Y;
end;

{ ---- DebugText ---- }

const
  {$I generated/debug_font.inc}

  // 文字の表の 1 行に並べる字形の数（SDL_DEBUG_FONT_GLYPHS_PER_ROW）。
  DebugFontGlyphsPerRow = 14;

{ 文字の表のテクスチャを作る。字形の周りに 1 画素の余白を空け、拡大したときに
  隣の字形がにじまないようにする（SDL と同じ配置）。

  PORT-NOTE: SDL は INDEX8 のサーフェス（パレット 2 色）から作るが、papimela の
  テクスチャはパレットをまだ持たない。白で、字形の画素だけアルファ 255 の
  ARGB8888 で直接作る。描いた結果は同じ（白 x 変調色）。
  拡大の方式は SDL の PIXELART ではなく Nearest。papimela に PIXELART が無いため。
  整数倍では同じ絵になる。 }
procedure TPMLRenderer.CreateDebugFont;
const
  CharW = PML_DEBUG_TEXT_FONT_CHARACTER_SIZE;
  CharH = PML_DEBUG_TEXT_FONT_CHARACTER_SIZE;
var
  Rows, Glyph, Col, Row, IX, IY, BX, BY: Integer;
  Atlas: TPMLSurface;
  Bits: Byte;
begin
  Rows := (PML_DEBUG_FONT_NUM_GLYPHS div DebugFontGlyphsPerRow) + 1;
  Atlas := TPMLSurface.Create((CharW + 2) * DebugFontGlyphsPerRow, Rows * (CharH + 2),
    PML_PIXELFORMAT_ARGB8888);
  try
    Atlas.Fill(TPMLColor.Make(255, 255, 255, 0));
    Col := 0;
    Row := 0;
    for Glyph := 0 to PML_DEBUG_FONT_NUM_GLYPHS - 1 do
    begin
      BX := Col * (CharW + 2) + 1;
      BY := Row * (CharH + 2) + 1;
      for IY := 0 to CharH - 1 do
      begin
        Bits := PMLDebugFontData[Glyph * 8 + IY];
        for IX := 0 to CharW - 1 do
          if ((Bits shr IX) and 1) <> 0 then
            Atlas.WritePixel(BX + IX, BY + IY, TPMLColor.Make(255, 255, 255, 255));
      end;
      Inc(Col);
      if Col >= DebugFontGlyphsPerRow then
      begin
        Inc(Row);
        Col := 0;
      end;
    end;
    FDebugFont := CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Static,
      Atlas.Width, Atlas.Height);
    FDebugFont.Update(TPMLRect.Make(0, 0, 0, 0), Atlas.Pixels, Atlas.Pitch);
  finally
    Atlas.Free;
  end;
  FDebugFont.ScaleMode := TPMLScaleMode.Nearest;
  FDebugFont.BlendMode := TPMLBlendMode.Blend;
end;

{ UTF-8 の次の 1 文字を読み、AIndex を進める。壊れていれば U+FFFD を返して
  1 バイト進む（SDL_StepUTF8 と同じく、字形の無い文字の印になる）。 }
function NextCodePoint(const AText: String; var AIndex: Integer): LongWord;
var
  B: Byte;
  N, I: Integer;
  MinCP: LongWord;
begin
  B := Ord(AText[AIndex]);
  if B < $80 then
  begin
    Inc(AIndex);
    Exit(B);
  end;
  if (B and $E0) = $C0 then
  begin
    N := 1; Result := B and $1F; MinCP := $80;
  end
  else if (B and $F0) = $E0 then
  begin
    N := 2; Result := B and $0F; MinCP := $800;
  end
  else if (B and $F8) = $F0 then
  begin
    N := 3; Result := B and $07; MinCP := $10000;
  end
  else
  begin
    Inc(AIndex);
    Exit($FFFD);
  end;
  if AIndex + N > Length(AText) then
  begin
    Inc(AIndex);
    Exit($FFFD);
  end;
  for I := 1 to N do
  begin
    B := Ord(AText[AIndex + I]);
    if (B and $C0) <> $80 then
    begin
      Inc(AIndex);
      Exit($FFFD);
    end;
    Result := (Result shl 6) or (B and $3F);
  end;
  // 冗長な表現、サロゲート、範囲外は壊れているものとして扱う。
  if (Result < MinCP) or ((Result >= $D800) and (Result <= $DFFF)) or (Result > $10FFFF) then
  begin
    Inc(AIndex);
    Exit($FFFD);
  end;
  Inc(AIndex, N + 1);
end;

{ コード点から字形の番号を求める。描かない文字は -1。

  PORT-NOTE(bug): SDL の DrawDebugCharacter は「字形が無いか」を
  `ci >= SDL_DEBUG_FONT_NUM_GLYPHS`（= 190）で判定する。字形の数とコード点を
  比べているので、字形のある U+00BE〜U+00FF（¾、À〜ÿ）が字形の無い文字の印に
  なる（D-42。SDL で実際に描いて確かめた）。papimela は 255 を超えるものだけを
  印にする。 }
function DebugGlyphIndex(ACode: LongWord): Integer;
begin
  if (ACode <= 32) or ((ACode >= 127) and (ACode <= 160)) then
    Result := -1                                  // 空白と制御文字
  else if ACode > 255 then
    Result := PML_DEBUG_FONT_NUM_GLYPHS - 1       // 字形の無い文字の印
  else if ACode < 127 then
    Result := ACode - 33                          // 先頭の 33 文字は表に無い
  else
    Result := ACode - 67;                         // さらに 127..160 の 34 文字も無い
end;

procedure TPMLRenderer.DebugText(AX, AY: Single; const AText: String);
const
  CharSize = PML_DEBUG_TEXT_FONT_CHARACTER_SIZE;
var
  I, Glyph: Integer;
  CurX: Single;
  C: TPMLColor;
begin
  if AText = '' then
    Exit;
  if FDebugFont = nil then
    CreateDebugFont;
  C := DrawColor;
  FDebugFont.ColorMod := TPMLColor.Make(C.R, C.G, C.B);
  FDebugFont.AlphaMod := C.A;

  CurX := AX;
  I := 1;
  while I <= Length(AText) do
  begin
    Glyph := DebugGlyphIndex(NextCodePoint(AText, I));
    if Glyph >= 0 then
      RenderTexture(FDebugFont,
        TPMLFRect.Make((Glyph mod DebugFontGlyphsPerRow) * (CharSize + 2) + 1,
                       (Glyph div DebugFontGlyphsPerRow) * (CharSize + 2) + 1,
                       CharSize, CharSize),
        TPMLFRect.Make(CurX, AY, CharSize, CharSize));
    CurX := CurX + CharSize;
  end;
end;

procedure TPMLRenderer.DebugTextFormat(AX, AY: Single; const AFormat: String;
  const AArgs: array of const);
begin
  DebugText(AX, AY, Format(AFormat, AArgs));
end;

end.
