{
  PaPiMeLa.Render — レンダラの抽象と公開 API

  Origin : ported from SDL (src/render/SDL_render.c, src/render/SDL_sysrender.h)
           Scope: 描画をコマンドとして積んで Present / Flush でまとめて実行する構造、
           状態コマンド（ビューポート・クリップ）を変化したときだけ積む規則、
           同じ状態の描画を 1 つのコマンドにまとめる規則、矩形・線・点・
           テクスチャ転送を三角形に落とす変換。
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
    - 論理解像度（LogicalPresentation）、描画先テクスチャ（SetRenderTarget）、
      回転（RenderTextureRotated）、9-grid / タイル、DebugText、VSync は未実装
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

    function  GetDrawColor: TPMLColor;
    procedure SetDrawColor(const AValue: TPMLColor);
    procedure SetViewport(const AValue: TPMLRect);
    procedure SetClipRect(const AValue: TPMLRect);
    function  GetDriverName: String;
    procedure QueueStateIfChanged;
    function  NewDrawCommand(AKind: TPMLRenderCommandKind): TPMLRenderCommand;
    procedure SetVSync(AValue: Integer);
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

    property DrawColor  : TPMLColor read GetDrawColor write SetDrawColor;
    property DrawColorF : TPMLFColor read FDrawColor write FDrawColor;
    property BlendMode  : TPMLBlendMode read FBlendMode write FBlendMode;
    // 空の矩形 = 出力全体。
    property Viewport   : TPMLRect read FViewport write SetViewport;
    property ClipRect   : TPMLRect read FClipRect write SetClipRect;
    property ClipEnabled: Boolean read FClipEnabled write FClipEnabled;
    property Driver     : TPMLRenderDriver read FDriver;
    property Window     : TPMLWindow read FWindow;
    // 0 = Present は待たない、1 = 画面の更新を待つ。ドライバが受け付けなければ
    // EPMLUnsupported。
    property VSync      : Integer read FVSync write SetVSync;
    property DriverName : String read GetDriverName;
    property Queue      : TPMLRenderQueue read FQueue;
    property Textures   : TPMLTextures read FTextures;
  end;

// ドライバの実装が使う。色と状態を比べ、同じなら結合してよいかを返す。
function PMLSameDrawState(const A, B: TPMLRenderCommand): Boolean;

implementation

uses
  PaPiMeLa.Render.Software,
  PaPiMeLa.Render.GLES2,
  PaPiMeLa.Video.Backend;

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
end;

constructor TPMLRenderer.CreateForWindow(AWindow: TPMLWindow;
  const ADriverName: String);
begin
  if AWindow = nil then
    raise EPMLArgument.Create('CreateForWindow needs a window');
  if (ADriverName <> '') and not SameText(ADriverName, 'software')
    and not SameText(ADriverName, 'gles2') then
    raise EPMLUnsupported.CreateNative(
      Format('render driver "%s" is not available', [ADriverName]), 0, 'render');
  inherited Create(AWindow.ContextRef, AWindow);
  FQueue := TPMLRenderQueue.Create;
  FDrawColor := TPMLFColor.Make(0, 0, 0, 1);
  FBlendMode := TPMLBlendMode.None;
  // 名前が無ければ、GL で作ったウィンドウには GPU のドライバを選ぶ（SDL も
  // 既定では GPU のレンダラを優先する）。
  if SameText(ADriverName, 'gles2')
    or ((ADriverName = '') and (TPMLWindowFlag.OpenGL in AWindow.Flags)) then
    FDriver := TPMLGLES2RenderDriver.CreateForWindow(AWindow)
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
  W, H: Integer;
  VP: TPMLRect;
begin
  VP := FViewport;
  if VP.IsEmpty and FDriver.GetOutputSize(W, H) then
    VP := TPMLRect.Make(0, 0, W, H);

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
  or (FClipEnabled and ((FClipRect.X <> FQueuedClip.X) or (FClipRect.Y <> FQueuedClip.Y)
      or (FClipRect.W <> FQueuedClip.W) or (FClipRect.H <> FQueuedClip.H))) then
  begin
    FillChar(Cmd, SizeOf(Cmd), 0);
    Cmd.Kind := TPMLRenderCommandKind.SetClipRect;
    Cmd.Rect := FClipRect;
    Cmd.Enabled := FClipEnabled;
    FQueue.Push(Cmd);
    FQueuedClip := FClipRect;
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
  Cmd: TPMLRenderCommand;
begin
  if Length(ARects) = 0 then
    Exit;
  Cmd := NewDrawCommand(TPMLRenderCommandKind.FillRects);
  FDriver.QueueFillRects(FQueue, Cmd, ARects);
  FQueue.Push(Cmd);
end;

procedure TPMLRenderer.RenderTexture(ATexture: TPMLTexture;
  const ASrc, ADst: TPMLFRect);
var
  Cmd: TPMLRenderCommand;
  S, D: TPMLFRect;
  W, H: Integer;
begin
  if ATexture = nil then
    Exit;
  if ATexture.Renderer <> Self then
    raise EPMLArgument.Create('texture belongs to another renderer');
  if ASrc.IsEmpty then
    S := TPMLFRect.Make(0, 0, ATexture.Width, ATexture.Height)
  else
    S := ASrc;
  if ADst.IsEmpty then
  begin
    if not FDriver.GetOutputSize(W, H) then
      Exit;
    D := TPMLFRect.Make(0, 0, W, H);
  end
  else
    D := ADst;

  Cmd := NewDrawCommand(TPMLRenderCommandKind.Copy);
  Cmd.Texture := ATexture;
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

end.
