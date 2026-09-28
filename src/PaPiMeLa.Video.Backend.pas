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
    - 部品のうち GL / Vulkan / Clipboard / Cursors / ScreenSaver / MessageBox /
      SystemMenu / ScreenKeyboard は型だけ用意し、実装は各担当ユニットで
      （第 11 章 #33、#38、#39、#40、#67）
    - シート（キーボード / ポインタ / タッチ）は #37。現状イベントは来ない

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
  PaPiMeLa.Core.Base;

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
    SoftwareFramebuffer       // papimela 追加: wl_shm 等でピクセルを直接置ける
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
    procedure GetSizeInPixels(out AWidth, AHeight: Integer); virtual; abstract;
    function  GetDisplayScale: Single; virtual;

    // ソフトウェアフレームバッファ。SoftwareFramebuffer 能力があるときだけ呼ばれる。
    function  CreateFramebuffer(out APixels: Pointer; out APitch: Integer): Boolean; virtual;
    procedure UpdateFramebuffer; virtual;
    procedure DestroyFramebuffer; virtual;

    function  NativeHandles: TPMLNativeWindowHandles; virtual;

    property WindowID: TPMLWindowID read FWindowID;
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

    property Capabilities: TPMLVideoCapabilities read FCapabilities;
  end;

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

function TPMLWindowBackend.GetDisplayScale: Single;
begin
  Result := 1.0;
end;

function TPMLWindowBackend.CreateFramebuffer(out APixels: Pointer;
  out APitch: Integer): Boolean;
begin
  APixels := nil;
  APitch := 0;
  Result := False;
end;

procedure TPMLWindowBackend.UpdateFramebuffer;
begin
end;

procedure TPMLWindowBackend.DestroyFramebuffer;
begin
end;

function TPMLWindowBackend.NativeHandles: TPMLNativeWindowHandles;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

{ TPMLDisplayBackend }

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

end.
