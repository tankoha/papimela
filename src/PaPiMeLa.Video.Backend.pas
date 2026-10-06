{
  PaPiMeLa.Video.Backend — ビデオ軸の抽象クラス群

  Origin : original work (clean-room design; not derived from SDL sources)
           SDL_sysvideo.h の 98 個の関数ポインタを分解した設計だが、コードは
           参照していない。
  Design : docs/DESIGN.md §3.2、§3.3、§11 #31

  WHAT:
    SDL_VideoDevice（単一構造体に 98 個の関数ポインタ）を、デバイス単位・
    ディスプレイ単位・ウィンドウ単位の 3 つの抽象クラスと、任意搭載の部品
    （GL / Vulkan / Clipboard / Cursors ...）に分解したもの。

  WHY:
    SDL の god object では、バックエンドが対応しない操作を「関数ポインタが nil」
    で表しており、呼び出し側が毎回 nil 検査する必要があった。papimela は
    能力集合（Capabilities）で先に判断し、バックエンドの実装は「呼ばれたら
    必ずできる」前提で書ける。

  RESOLVED:
    - 未搭載の部品はプロパティが nil。判定は Capabilities で行う
    - バックエンド → 公開層の通知は IPMLVideoSink（ウィンドウ ID で識別）。
      これによりバックエンドは公開層のクラスを知らない
    - Wayland は拡張の有無で能力が変わるため Capabilities は Connect 後に確定する

  NOT RESOLVED:
    - 部品のうち実装済みは Cursors（#37）と GL（#33、#39）。Vulkan / Clipboard /
      ScreenSaver / MessageBox / SystemMenu / ScreenKeyboard は未実装（#38、#40、#67 など）

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Backend;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Pixels,
  PaPiMeLa.Events;

type
  TPMLVideoCapability = (
    OpenGL, OpenGLES, Vulkan,
    Clipboard, PrimarySelection, DragAndDrop,
    WindowPositioning,        // Wayland は False（xdg-shell はウィンドウ位置を持たない）
    ServerSideDecoration,
    FractionalScale, HighDPI,
    RelativeMouse, MouseConfine, MouseWarp,
    KeyboardGrab, SystemMenu, IdleInhibit, WindowActivation,
    SetIcon,
    Touch, Tablet, MessageBox, ScreenKeyboard,
    SoftwareFramebuffer,      // papimela 追加: wl_shm 等でピクセルを直接置ける
    CursorShape               // papimela 追加: システムカーソルを選べる（cursor-shape-v1）
  );
  TPMLVideoCapabilities = set of TPMLVideoCapability;

  TPMLWindowFlag = (
    Fullscreen, OpenGL, Occluded, Hidden, Borderless, Resizable,
    Minimized, Maximized, MouseGrabbed, InputFocus, MouseFocus,
    HighPixelDensity, MouseCapture, AlwaysOnTop, Utility, Tooltip,
    PopupMenu, KeyboardGrabbed, Vulkan, Transparent, NotFocusable
  );
  TPMLWindowFlags = set of TPMLWindowFlag;

  TPMLDisplayOrientation = (Unknown, Landscape, LandscapeFlipped,
    Portrait, PortraitFlipped);

  TPMLDisplayMode = record
    Width, Height    : Integer;
    PixelDensity     : Single;
    RefreshRate      : Single;
    RefreshNumerator : Integer;
    RefreshDenominator: Integer;
  end;
  TPMLDisplayModes = array of TPMLDisplayMode;

  { ネイティブハンドル。型は Pointer で、名前付きフィールドとして公開する。
    X11 を追加したら Display / Window フィールドが増える。 }
  TPMLNativeWindowHandles = record
    WaylandDisplay  : Pointer;   // wl_display
    WaylandSurface  : Pointer;   // wl_surface
    WaylandXdgSurface: Pointer;  // xdg_surface
    WaylandXdgToplevel: Pointer; // xdg_toplevel
    WaylandEGLWindow: Pointer;   // wl_egl_window
  end;

  { バックエンド → 公開層の通知。公開層（TPMLVideoSystem）が実装する。

    ウィンドウはバックエンドではなく ID で識別する。これによりバックエンドは
    公開層のクラス（TPMLWindow）を知らずに済む。 }
  IPMLVideoSink = interface
    ['{5C2A9E74-3B18-4D06-9F8A-71E4B0D39C62}']
    procedure WindowResized(AWindowID: TPMLWindowID; AWidth, AHeight: Integer);
    procedure WindowPixelSizeChanged(AWindowID: TPMLWindowID; AWidth, AHeight: Integer);
    procedure WindowStateChanged(AWindowID: TPMLWindowID; AFlags: TPMLWindowFlags);
    procedure WindowCloseRequested(AWindowID: TPMLWindowID);
    procedure WindowExposed(AWindowID: TPMLWindowID);
    procedure WindowDisplayScaleChanged(AWindowID: TPMLWindowID; AScale: Single);
    procedure DisplaysChanged;
    procedure BackendLost(const AReason: String);
  end;

  { ウィンドウ単位。SDL の 44 個のウィンドウ操作をここに集約する。

    NOT RESOLVED:
      設計 §3.2 が挙げる操作のうち、初回スコープで実装するのは
      SetTitle / SetSize / Show / Hide / Maximize / Minimize / Restore /
      SetBordered / SetResizable / SetMinimumSize / SetMaximumSize /
      GetSizeInPixels / Sync と、ソフトウェアフレームバッファのみ。
      残り（アイコン、不透明度、形状、グラブ、ヒットテスト、フルスクリーン）は
      対応する能力と一緒に追加する。 }
  TPMLWindowBackend = class abstract(TPMLSystemObject)
  strict protected
    FWindowID: TPMLWindowID;
  public
    procedure SetTitle(const ATitle: String); virtual; abstract;
    procedure SetSize(AWidth, AHeight: Integer); virtual; abstract;
    procedure SetMinimumSize(AWidth, AHeight: Integer); virtual;
    procedure SetMaximumSize(AWidth, AHeight: Integer); virtual;
    procedure SetBordered(ABordered: Boolean); virtual;
    procedure SetResizable(AResizable: Boolean); virtual;
    procedure Show; virtual; abstract;
    procedure Hide; virtual; abstract;
    procedure RaiseWindow; virtual;
    procedure Maximize; virtual;
    procedure Minimize; virtual;
    procedure Restore; virtual;
    procedure Sync; virtual;

    // 入力の拘束（§3.2 の「入力」）。能力 MouseConfine / RelativeMouse で呼ばれるかが決まる。
    procedure SetMouseGrab(AGrabbed: Boolean); virtual;
    procedure SetMouseRect(const ARect: TPMLRect); virtual;
    procedure SetRelativeMouseMode(AEnabled: Boolean); virtual;
    procedure GetSizeInPixels(out AWidth, AHeight: Integer); virtual; abstract;
    function  GetDisplayScale: Single; virtual;

    // ソフトウェアフレームバッファ。SoftwareFramebuffer 能力があるときだけ呼ばれる。
    // 同じ大きさのあいだは同じ APixels を返す。大きさが変わったら作り直してよい。
    // UpdateFramebuffer は中身を画面へ出す。出した後も中身は保たれる。
    function  CreateFramebuffer(out APixels: Pointer; out APitch: Integer;
      out AFormat: TPMLPixelFormat): Boolean; virtual;
    procedure UpdateFramebuffer; virtual;
    procedure DestroyFramebuffer; virtual;
    // UpdateFramebuffer を画面の更新に合わせるか。0 = 合わせない、1 = 毎回待つ。
    // 対応しない値なら False を返し、設定は変えない。
    function  SetFramebufferVSync(AInterval: Integer): Boolean; virtual;

    function  NativeHandles: TPMLNativeWindowHandles; virtual;

    property WindowID: TPMLWindowID read FWindowID;
  end;


  { システムカーソルの種類。

    cursor-shape-v1 の shape 列挙のうち、アプリが実際に使うものだけを並べた。
    名前は Wayland の綴りではなく papimela の綴りにしてある（`Default` や
    `Pointer` は Pascal の文脈で紛らわしいため Arrow / Hand とした）。 }
  TPMLSystemCursor = (
    Arrow, Text, Wait, Crosshair, Progress, Hand, Move, NotAllowed,
    ResizeNWSE, ResizeNESW, ResizeEW, ResizeNS,
    ResizeN, ResizeE, ResizeS, ResizeW,
    ResizeNE, ResizeNW, ResizeSE, ResizeSW
  );

  { カーソル部品。TPMLVideoBackend.Cursors が nil でなければ使える。

    WHAT:
      システムカーソルの選択と、カーソルの表示 / 非表示。

    NOT RESOLVED:
      任意のピクセルからカーソルを作る経路（設計 4.2 の
      `Cursors.Create(Surface, HotX, HotY)`）は未実装。wl_shm のバッファ
      （PaPiMeLa.Video.Wayland.Shm）はあるので、それを使って足せる。 }
  TPMLCursorBackend = class abstract(TPMLSystemObject)
  public
    procedure SetSystemCursor(AKind: TPMLSystemCursor); virtual; abstract;
    procedure SetVisible(AVisible: Boolean); virtual; abstract;
  end;

  { どちらの選択か。Clipboard はコピー＆ペースト、Primary は選んだだけで入り中クリックで
    貼る方（X11 由来。Wayland では primary-selection-unstable-v1）。 }
  TPMLClipboardSelection = (Clipboard, Primary);

  { アプリが置いたデータを、求められたときに渡す（SDL_ClipboardDataCallback と
    SDL_ClipboardCleanupCallback に当たる）。CORBA。寿命はアプリが持つ。

    GetClipboardData は、SetData で並べた MIME タイプのどれかについてだけ呼ばれる。
    渡せなければ False。他のアプリが貼り付けるたびに呼ばれうる（Wayland では
    Pump の中から）。
    ClipboardDataCancelled は、別のデータに置き換えられた・消された・他のアプリが
    選択を取った・終了した、のどれかで、もうこのデータを求めないときに 1 回だけ呼ぶ。 }
  IPMLClipboardDataProvider = interface
    ['{5E0A7C21-8B4F-4D93-A6E2-1F07C39B84D6}']
    function  GetClipboardData(const AMimeType: String; out AData: TBytes): Boolean;
    procedure ClipboardDataCancelled;
  end;

  { クリップボードの部品から公開層（TPMLClipboard）への知らせ。 }
  IPMLClipboardSink = interface
    ['{B7D24E90-3C1A-4F68-9E05-6A81D2C4F37B}']
    // こちらが置いたデータを、もう配らない（他のアプリが選択を取った）。
    procedure ClipboardOwnershipLost(ASelection: TPMLClipboardSelection);
    // 他のアプリの選択が見えるようになった。AMimeTypes が空なら選択が無くなった。
    // こちらが置いたデータの折り返しは知らせない（部品が見分ける）。
    procedure ClipboardOffered(ASelection: TPMLClipboardSelection;
      const AMimeTypes: TStringArray);
  end;

  { クリップボードの部品。TPMLVideoBackend.Clipboard が nil でなければ使える
    （能力 Clipboard / PrimarySelection）。nil なら公開層がプロセスの中だけで持つ。

    SDL_VideoDevice のクリップボード 5 個とプライマリ選択 5 個に当たる。
    データそのものは持たない。持ち主のときは公開層から借りた AProvider から、
    他のアプリのときは相手から読む。例外は投げず、失敗は False。 }
  TPMLClipboardBackend = class abstract(TPMLSystemObject)
  strict protected
    FSink: IPMLClipboardSink;
  public
    // 公開層が自分を登録する。nil で外す。
    procedure Attach(ASink: IPMLClipboardSink);
    function  SupportsSelection(ASelection: TPMLClipboardSelection): Boolean; virtual; abstract;
    // 選択を取って AMimeTypes を配る。AProvider が nil（AMimeTypes は空）なら手放す。
    // AProvider は次の SetSelection か Attach(nil) まで借りる。
    function  SetSelection(ASelection: TPMLClipboardSelection; const AMimeTypes: TStringArray;
      AProvider: IPMLClipboardDataProvider): Boolean; virtual; abstract;
    // 他のアプリが配っている MIME タイプ（無ければ空）。
    function  OfferedMimeTypes(ASelection: TPMLClipboardSelection): TStringArray; virtual; abstract;
    // 他のアプリから AMimeType のデータを受け取る（待つことがある）。持ち主が
    // こちらのときは呼ばれない。
    function  ReceiveOffer(ASelection: TPMLClipboardSelection; const AMimeType: String;
      out AData: TBytes): Boolean; virtual; abstract;
    // 文字列として配る・探す MIME タイプ（優先する順）。既定は UTF-8 の text/plain だけ。
    function  TextMimeTypes: TStringArray; virtual;
  end;

  TPMLGLProfile = (ES, Core, Compatibility);

  { GL のコンテキストと描画先に求める性質。SDL_GL_SetAttribute の値をまとめたもの。

    WHY:
      SDL は属性を大域の gl_config に置き、ウィンドウの生成時とコンテキストの
      生成時にそれを読む。papimela は値として CreateGLContext に渡す。大域の状態が
      無いので、ウィンドウごとに違う属性を使える。 }
  TPMLGLAttributes = record
    RedSize, GreenSize, BlueSize, AlphaSize: Integer;
    DepthSize, StencilSize: Integer;
    MajorVersion, MinorVersion: Integer;
    Profile: TPMLGLProfile;
    Debug  : Boolean;
    { SDL_GL_ResetAttributes の値（RGBA 各 8 ビット、深度 16 ビット）で、
      OpenGL ES 2.0。 }
    class function Default: TPMLGLAttributes; static;
  end;

  { コンテキストの識別子。中身はバックエンドが決める（EGL では EGLContext）。 }
  TPMLGLContextHandle = Pointer;

  { GL の部品。TPMLVideoBackend.GL が nil でなければ使える（能力 OpenGLES）。

    SDL_VideoDevice の GL 11 個に対応する。ウィンドウに描くための面（EGL の
    サーフェス）は部品がウィンドウごとに持ち、最初の CreateContext で作る。
    面の属性（色の深さなど）はそのときの AAttrs で決まり、そのウィンドウでは
    以後変わらない。

    RESOLVED:
      - 面はウィンドウより先に畳む。TPMLWindow は自分のバックエンドを壊す前に
        ReleaseWindow を呼ぶ
      - 例外は投げず、失敗は False / nil と LastError で返す。公開層が
        EPMLVideoError に変える }
  TPMLGLBackend = class abstract(TPMLSystemObject)
  strict protected
    FLastError: String;
  public
    { AName の関数の番地。見つからなければ nil。 }
    function  GetProcAddress(const AName: String): Pointer; virtual; abstract;
    { AWindow に描くコンテキストを作る。AWindow の面がまだ無ければ AAttrs で作る。
      作ったコンテキストを AWindow に対して現在のコンテキストにして返す。 }
    function  CreateContext(AWindow: TPMLWindowBackend;
      const AAttrs: TPMLGLAttributes): TPMLGLContextHandle; virtual; abstract;
    { AWindow と AContext を現在のものにする。両方 nil なら何も現在でなくする。 }
    function  MakeCurrent(AWindow: TPMLWindowBackend;
      AContext: TPMLGLContextHandle): Boolean; virtual; abstract;
    procedure DestroyContext(AContext: TPMLGLContextHandle); virtual; abstract;
    { 描いた絵を画面へ出す（SDL_GL_SwapWindow）。面の無いウィンドウでは False。 }
    function  SwapWindow(AWindow: TPMLWindowBackend): Boolean; virtual; abstract;
    { 0 = 待たない、1 = 画面の更新を待つ、-1 = 適応（間に合わなければ待たない）。
      受け付けない値なら False。 }
    function  SetSwapInterval(AInterval: Integer): Boolean; virtual; abstract;
    function  GetSwapInterval: Integer; virtual; abstract;
    { AWindow の面を畳む。面が無ければ何もしない。ウィンドウのバックエンドを
      壊す前に必ず呼ばれる。 }
    procedure ReleaseWindow(AWindow: TPMLWindowBackend); virtual; abstract;
    { 直近の失敗の説明。 }
    property  LastError: String read FLastError;
  end;

  TPMLDisplayBackend = class abstract(TPMLSystemObject)
  public
    function  GetName: String; virtual; abstract;
    function  GetBounds: TPMLRect; virtual; abstract;
    function  GetUsableBounds: TPMLRect; virtual;
    function  GetContentScale: Single; virtual;
    function  GetOrientation: TPMLDisplayOrientation; virtual;
    function  GetDesktopMode: TPMLDisplayMode; virtual; abstract;
    function  EnumerateModes: TPMLDisplayModes; virtual;
  end;
  TPMLDisplayBackends = array of TPMLDisplayBackend;

  { デバイス単位。1 Context に 1 つ。 }
  TPMLVideoBackend = class abstract(TPMLSystemObject)
  strict protected
    FSink        : IPMLVideoSink;
    FCapabilities: TPMLVideoCapabilities;
    FCursors     : TPMLCursorBackend;
    FGL          : TPMLGLBackend;
    FClipboard   : TPMLClipboardBackend;
  public
    function  BackendName: String; virtual; abstract;
    function  Connect(ASink: IPMLVideoSink): Boolean; virtual; abstract;
    procedure Disconnect; virtual;

    // Connect 後に呼ばれる。所有権は呼び出し側（TPMLVideoSystem）へ渡す。
    function  EnumerateDisplays: TPMLDisplayBackends; virtual; abstract;
    function  CreateWindowBackend(AWindowID: TPMLWindowID; const ATitle: String;
      AWidth, AHeight: Integer; AFlags: TPMLWindowFlags): TPMLWindowBackend;
      virtual; abstract;

    procedure PumpEvents; virtual; abstract;
    procedure WaitEvents(ATimeoutMs: Integer); virtual;
    procedure WakeEventLoop; virtual;

    // 部品（nil = 未搭載。能力で判定する）。所有はバックエンド。
    property Cursors     : TPMLCursorBackend read FCursors;
    property GL          : TPMLGLBackend read FGL;
    property Clipboard   : TPMLClipboardBackend read FClipboard;
    property Capabilities: TPMLVideoCapabilities read FCapabilities;
  end;

  { 生成だけをする関数。Connect は呼び出し側（TPMLVideoSystem）が行う。 }
  TPMLVideoBackendFactory = function(AContextRef: TObject; AOwner: TPMLObject;
    AQueue: TPMLEventQueue): TPMLVideoBackend;

{ ---- 登録（#45） ----

  具象バックエンドは、自分のユニットの initialization で自分を登録する。
  公開層（PaPiMeLa.Video）は具象バックエンドを uses しない（設計 §2.1）。どれを
  リンクするかはアプリの uses で決まる: PaPiMeLa.Backends（またはアンブレラの
  PaPiMeLa）を uses すれば全部、個別のユニットを uses すればそれだけ。

  名前は大文字小文字を区別せずに比べる。同じ名前を 2 度登録すると
  EPMLArgument。試す順は優先度の大きい順、同じなら登録した順。 }
procedure PMLRegisterVideoBackend(const AName: String; APriority: Integer;
  AFactory: TPMLVideoBackendFactory);
// 登録済みの名前を試す順に返す。
function  PMLVideoBackendNames: TStringArray;
// 名前の工場。登録されていなければ nil。
function  PMLFindVideoBackend(const AName: String): TPMLVideoBackendFactory;

implementation

{ TPMLWindowBackend — 既定は「何もしない」。能力集合で呼ばれるかが決まる。 }

procedure TPMLWindowBackend.SetMinimumSize(AWidth, AHeight: Integer);
begin
end;

procedure TPMLWindowBackend.SetMaximumSize(AWidth, AHeight: Integer);
begin
end;

procedure TPMLWindowBackend.SetBordered(ABordered: Boolean);
begin
end;

procedure TPMLWindowBackend.SetResizable(AResizable: Boolean);
begin
end;

procedure TPMLWindowBackend.RaiseWindow;
begin
end;

procedure TPMLWindowBackend.Maximize;
begin
end;

procedure TPMLWindowBackend.Minimize;
begin
end;

procedure TPMLWindowBackend.Restore;
begin
end;

procedure TPMLWindowBackend.Sync;
begin
end;

procedure TPMLWindowBackend.SetMouseGrab(AGrabbed: Boolean);
begin
end;

procedure TPMLWindowBackend.SetMouseRect(const ARect: TPMLRect);
begin
end;

procedure TPMLWindowBackend.SetRelativeMouseMode(AEnabled: Boolean);
begin
end;

function TPMLWindowBackend.GetDisplayScale: Single;
begin
  Result := 1.0;
end;

function TPMLWindowBackend.CreateFramebuffer(out APixels: Pointer;
  out APitch: Integer; out AFormat: TPMLPixelFormat): Boolean;
begin
  APixels := nil;
  APitch := 0;
  AFormat := PML_PIXELFORMAT_UNKNOWN;
  Result := False;
end;

procedure TPMLWindowBackend.UpdateFramebuffer;
begin
end;

procedure TPMLWindowBackend.DestroyFramebuffer;
begin
end;

function TPMLWindowBackend.SetFramebufferVSync(AInterval: Integer): Boolean;
begin
  Result := AInterval = 0;
end;

{ TPMLGLAttributes }

class function TPMLGLAttributes.Default: TPMLGLAttributes;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.RedSize := 8;
  Result.GreenSize := 8;
  Result.BlueSize := 8;
  Result.AlphaSize := 8;
  Result.DepthSize := 16;
  Result.MajorVersion := 2;
  Result.MinorVersion := 0;
  Result.Profile := TPMLGLProfile.ES;
end;

function TPMLWindowBackend.NativeHandles: TPMLNativeWindowHandles;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

{ TPMLDisplayBackend }

{ TPMLClipboardBackend }

procedure TPMLClipboardBackend.Attach(ASink: IPMLClipboardSink);
begin
  FSink := ASink;
end;

function TPMLClipboardBackend.TextMimeTypes: TStringArray;
begin
  Result := ['text/plain;charset=utf-8'];
end;

function TPMLDisplayBackend.GetUsableBounds: TPMLRect;
begin
  Result := GetBounds;
end;

function TPMLDisplayBackend.GetContentScale: Single;
begin
  Result := 1.0;
end;

function TPMLDisplayBackend.GetOrientation: TPMLDisplayOrientation;
begin
  Result := TPMLDisplayOrientation.Unknown;
end;

function TPMLDisplayBackend.EnumerateModes: TPMLDisplayModes;
begin
  SetLength(Result, 1);
  Result[0] := GetDesktopMode;
end;

{ TPMLVideoBackend }

procedure TPMLVideoBackend.Disconnect;
begin
  FSink := nil;
end;

procedure TPMLVideoBackend.WaitEvents(ATimeoutMs: Integer);
begin
  PumpEvents;
end;

procedure TPMLVideoBackend.WakeEventLoop;
begin
end;

{ ---- 登録（#45） ---- }

type
  TVideoRegistration = record
    Name    : String;
    Priority: Integer;
    Factory : TPMLVideoBackendFactory;
  end;

var
  // 試す順（優先度の大きい順、同じなら登録順）に並べて持つ。
  VideoRegistry: array of TVideoRegistration;

function FindVideoIndex(const AName: String): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(VideoRegistry) do
    if SameText(VideoRegistry[I].Name, AName) then
      Exit(I);
end;

procedure PMLRegisterVideoBackend(const AName: String; APriority: Integer;
  AFactory: TPMLVideoBackendFactory);
var
  At, I: Integer;
begin
  if AName = '' then
    raise EPMLArgument.Create('video backend name is empty');
  if not Assigned(AFactory) then
    raise EPMLArgument.Create('video backend factory is nil');
  if FindVideoIndex(AName) >= 0 then
    raise EPMLArgument.CreateFmt('video backend "%s" is already registered', [AName]);
  // 自分より優先度の小さい最初の位置へ入れる（同じ優先度は後ろへ回る）。
  At := Length(VideoRegistry);
  for I := 0 to High(VideoRegistry) do
    if VideoRegistry[I].Priority < APriority then
    begin
      At := I;
      Break;
    end;
  SetLength(VideoRegistry, Length(VideoRegistry) + 1);
  for I := High(VideoRegistry) downto At + 1 do
    VideoRegistry[I] := VideoRegistry[I - 1];
  VideoRegistry[At].Name := AName;
  VideoRegistry[At].Priority := APriority;
  VideoRegistry[At].Factory := AFactory;
end;

function PMLVideoBackendNames: TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(VideoRegistry));
  for I := 0 to High(VideoRegistry) do
    Result[I] := VideoRegistry[I].Name;
end;

function PMLFindVideoBackend(const AName: String): TPMLVideoBackendFactory;
var
  I: Integer;
begin
  I := FindVideoIndex(AName);
  if I >= 0 then
    Result := VideoRegistry[I].Factory
  else
    Result := nil;
end;

end.
