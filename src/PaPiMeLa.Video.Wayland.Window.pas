{
  PaPiMeLa.Video.Wayland.Window — xdg-shell によるウィンドウと wl_shm バッファ

  Origin : partially ported from SDL (src/video/wayland/SDL_waylandwindow.c,
           src/video/wayland/SDL_waylandshmbuffer.c)
           Scope: configure / ack_configure の順序制約、最初の configure より前に
           バッファを attach してはならないという規約、shm プールの作り方。
           構造とクラス分割は本設計に従う。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.2、§11 #36、#39

  WHAT:
    wl_surface + xdg_surface + xdg_toplevel の状態機械と、wl_shm による
    ソフトウェアフレームバッファ。

  WHY:
    ウィンドウが可視になるには、最初の xdg_surface.configure に ack_configure で
    応答し、その後でバッファを attach して commit する必要がある。この順序を
    守らないとコンポジタはサーフェスを表示しない。

  RESOLVED:
    - 生成したリスナーは抽象クラスなので、1 クラスで xdg_surface と xdg_toplevel の
      両方を継承できない。転送用の内部クラスを 2 つ置いて実体へ委譲する
    - サイズは xdg_toplevel.configure が 0x0 を送ることがある（コンポジタが
      アプリに任せる意味）。その場合は要求サイズを維持する
    - shm ファイルは XDG_RUNTIME_DIR に作って即 unlink する。fd だけを
      コンポジタへ渡す

  NOT RESOLVED:
    - フルスクリーン・最大化の往復、装飾（libdecor）、ヒットテスト、グラブは未実装
    - HiDPI は wl_surface.set_buffer_scale を呼んでいない（scale 1 固定）
    - フレームコールバック（wl_surface.frame）による描画同期は未実装。
      UpdateFramebuffer は即 commit する

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Wayland.Window;

{$I papimela.inc}

interface

uses
  SysUtils, BaseUnix,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video.Wayland.Types,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland,
  PaPiMeLa.Platform.Wayland.Protocols.XdgShell,
  PaPiMeLa.Platform.Wayland.Protocols.XdgDecorationUnstableV1;

type
  TPMLWaylandWindowBackend = class;

  TPMLXdgSurfaceForwarder = class(Txdg_surface_listener)
  strict private
    FOwner: TPMLWaylandWindowBackend;
  public
    constructor Create(AOwner: TPMLWaylandWindowBackend);
    procedure configure(AProxy: Pxdg_surface; serial: LongWord); override;
  end;

  TPMLXdgToplevelForwarder = class(Txdg_toplevel_listener)
  strict private
    FOwner: TPMLWaylandWindowBackend;
  public
    constructor Create(AOwner: TPMLWaylandWindowBackend);
    procedure configure(AProxy: Pxdg_toplevel; width: LongInt; height: LongInt;
      states: Pwl_array); override;
    procedure close(AProxy: Pxdg_toplevel); override;
  end;

  TPMLWaylandWindowBackend = class(TPMLWindowBackend)
  strict private
    FConn      : TPMLWaylandConnection;
    FSink      : IPMLVideoSink;
    FSurface   : Pwl_surface;
    FXdgSurface: Pxdg_surface;
    FToplevel  : Pxdg_toplevel;
    FDecoration: Pzxdg_toplevel_decoration_v1;
    FXsFwd     : TPMLXdgSurfaceForwarder;
    FTlFwd     : TPMLXdgToplevelForwarder;

    FWidth, FHeight: Integer;
    FConfigured  : Boolean;
    FVisible     : Boolean;
    FStates      : TPMLWindowFlags;

    // shm フレームバッファ
    FShmPool  : Pwl_shm_pool;
    FBuffer   : Pwl_buffer;
    FMap      : Pointer;
    FMapSize  : PtrUInt;
    FBufW, FBufH: Integer;

    procedure DestroyBuffer;
    function  EnsureBuffer: Boolean;
    procedure PresentFirstFrame;
  private
    procedure HandleSurfaceConfigure(ASerial: LongWord);
    procedure HandleToplevelConfigure(AWidth, AHeight: Integer; AStates: Pwl_array);
    procedure HandleClose;
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject;
      AConn: TPMLWaylandConnection; ASink: IPMLVideoSink;
      AWindowID: TPMLWindowID; const ATitle: String;
      AWidth, AHeight: Integer; AFlags: TPMLWindowFlags);
    destructor Destroy; override;

    procedure SetTitle(const ATitle: String); override;
    procedure SetSize(AWidth, AHeight: Integer); override;
    procedure SetMinimumSize(AWidth, AHeight: Integer); override;
    procedure SetMaximumSize(AWidth, AHeight: Integer); override;
    procedure Show; override;
    procedure Hide; override;
    procedure Maximize; override;
    procedure Minimize; override;
    procedure Restore; override;
    procedure GetSizeInPixels(out AWidth, AHeight: Integer); override;
    function  CreateFramebuffer(out APixels: Pointer; out APitch: Integer): Boolean; override;
    procedure UpdateFramebuffer; override;
    procedure DestroyFramebuffer; override;
    function  NativeHandles: TPMLNativeWindowHandles; override;

    property Configured: Boolean read FConfigured;
  end;

implementation

{ 転送クラス }

constructor TPMLXdgSurfaceForwarder.Create(AOwner: TPMLWaylandWindowBackend);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TPMLXdgSurfaceForwarder.configure(AProxy: Pxdg_surface; serial: LongWord);
begin
  FOwner.HandleSurfaceConfigure(serial);
end;

constructor TPMLXdgToplevelForwarder.Create(AOwner: TPMLWaylandWindowBackend);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TPMLXdgToplevelForwarder.configure(AProxy: Pxdg_toplevel;
  width: LongInt; height: LongInt; states: Pwl_array);
begin
  FOwner.HandleToplevelConfigure(width, height, states);
end;

procedure TPMLXdgToplevelForwarder.close(AProxy: Pxdg_toplevel);
begin
  FOwner.HandleClose;
end;

{ TPMLWaylandWindowBackend }

constructor TPMLWaylandWindowBackend.Create(AContextRef: TObject; AOwner: TPMLObject;
  AConn: TPMLWaylandConnection; ASink: IPMLVideoSink; AWindowID: TPMLWindowID;
  const ATitle: String; AWidth, AHeight: Integer; AFlags: TPMLWindowFlags);
begin
  inherited Create(AContextRef, AOwner);
  FConn := AConn;
  FSink := ASink;
  FWindowID := AWindowID;
  FWidth := AWidth;
  FHeight := AHeight;
  if FWidth <= 0 then FWidth := 640;
  if FHeight <= 0 then FHeight := 480;

  FSurface := wl_compositor_create_surface(FConn.Compositor);
  if FSurface = nil then
    raise EPMLVideoError.CreateNative('wl_compositor.create_surface failed', 0, 'wayland');

  // Seat がサーフェスからウィンドウを引けるようにする。wl_surface には
  // リスナーを付けていないので user_data は空いている。
  wl_proxy_set_user_data(Pwl_proxy(FSurface), Self);

  FXdgSurface := xdg_wm_base_get_xdg_surface(FConn.WmBase, FSurface);
  FXsFwd := TPMLXdgSurfaceForwarder.Create(Self);
  xdg_surface_add_listener_object(FXdgSurface, FXsFwd);

  FToplevel := xdg_surface_get_toplevel(FXdgSurface);
  FTlFwd := TPMLXdgToplevelForwarder.Create(Self);
  xdg_toplevel_add_listener_object(FToplevel, FTlFwd);

  xdg_toplevel_set_title(FToplevel, PAnsiChar(ATitle));
  xdg_toplevel_set_app_id(FToplevel, PAnsiChar(ApplicationName));

  // サーバサイド装飾があれば使う（無ければ装飾なしで妥協。libdecor は #69）。
  if FConn.DecorationMgr <> nil then
  begin
    FDecoration := zxdg_decoration_manager_v1_get_toplevel_decoration(
      FConn.DecorationMgr, FToplevel);
    if not (TPMLWindowFlag.Borderless in AFlags) then
      zxdg_toplevel_decoration_v1_set_mode(FDecoration,
        ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
  end;

  if not (TPMLWindowFlag.Resizable in AFlags) then
  begin
    xdg_toplevel_set_min_size(FToplevel, FWidth, FHeight);
    xdg_toplevel_set_max_size(FToplevel, FWidth, FHeight);
  end;

  wl_surface_commit(FSurface);
  wl_display_flush(FConn.Display);
end;

destructor TPMLWaylandWindowBackend.Destroy;
begin
  DestroyBuffer;
  if FDecoration <> nil then
    zxdg_toplevel_decoration_v1_destroy(FDecoration);
  if FToplevel <> nil then
    xdg_toplevel_destroy(FToplevel);
  if FXdgSurface <> nil then
    xdg_surface_destroy(FXdgSurface);
  if FSurface <> nil then
    wl_surface_destroy(FSurface);
  if FConn.Display <> nil then
    wl_display_flush(FConn.Display);
  FreeAndNil(FXsFwd);
  FreeAndNil(FTlFwd);
  FSink := nil;
  inherited Destroy;
end;

procedure TPMLWaylandWindowBackend.HandleSurfaceConfigure(ASerial: LongWord);
var
  First: Boolean;
begin
  First := not FConfigured;
  // ack_configure は configure ごとに必ず返す。
  xdg_surface_ack_configure(FXdgSurface, ASerial);
  FConfigured := True;
  if First then
    PresentFirstFrame;
  if Assigned(FSink) then
    FSink.WindowExposed(FWindowID);
end;

procedure TPMLWaylandWindowBackend.HandleToplevelConfigure(AWidth, AHeight: Integer;
  AStates: Pwl_array);
var
  P: PLongWord;
  I: Integer;
  NewStates: TPMLWindowFlags;
begin
  // 0x0 は「サイズはアプリが決めてよい」の意味なので要求サイズを維持する。
  if (AWidth > 0) and (AHeight > 0)
    and ((AWidth <> FWidth) or (AHeight <> FHeight)) then
  begin
    FWidth := AWidth;
    FHeight := AHeight;
    if Assigned(FSink) then
    begin
      FSink.WindowResized(FWindowID, FWidth, FHeight);
      FSink.WindowPixelSizeChanged(FWindowID, FWidth, FHeight);
    end;
  end;

  NewStates := [];
  if (AStates <> nil) and (AStates^.data <> nil) then
  begin
    P := PLongWord(AStates^.data);
    for I := 0 to (AStates^.size div SizeOf(LongWord)) - 1 do
    begin
      case P[I] of
        XDG_TOPLEVEL_STATE_MAXIMIZED : Include(NewStates, TPMLWindowFlag.Maximized);
        XDG_TOPLEVEL_STATE_FULLSCREEN: Include(NewStates, TPMLWindowFlag.Fullscreen);
        XDG_TOPLEVEL_STATE_ACTIVATED : Include(NewStates, TPMLWindowFlag.InputFocus);
      end;
    end;
  end;
  if NewStates <> FStates then
  begin
    FStates := NewStates;
    if Assigned(FSink) then
      FSink.WindowStateChanged(FWindowID, NewStates);
  end;
end;

procedure TPMLWaylandWindowBackend.HandleClose;
begin
  if Assigned(FSink) then
    FSink.WindowCloseRequested(FWindowID);
end;

{ ---- wl_shm フレームバッファ ---- }

procedure TPMLWaylandWindowBackend.DestroyBuffer;
begin
  if FBuffer <> nil then
  begin
    wl_buffer_destroy(FBuffer);
    FBuffer := nil;
  end;
  if FShmPool <> nil then
  begin
    wl_shm_pool_destroy(FShmPool);
    FShmPool := nil;
  end;
  if (FMap <> nil) and (FMapSize > 0) then
  begin
    Fpmunmap(FMap, FMapSize);
    FMap := nil;
    FMapSize := 0;
  end;
  FBufW := 0;
  FBufH := 0;
end;

function TPMLWaylandWindowBackend.EnsureBuffer: Boolean;
var
  Stride, Size: PtrUInt;
  Dir, Path: String;
  FD: cint;
  Attempt: Integer;
begin
  Result := False;
  if FConn.Shm = nil then
    Exit;
  if (FBuffer <> nil) and (FBufW = FWidth) and (FBufH = FHeight) then
    Exit(True);

  DestroyBuffer;
  Stride := PtrUInt(FWidth) * 4;
  Size := Stride * PtrUInt(FHeight);
  if Size = 0 then
    Exit;

  Dir := GetEnvironmentVariable('XDG_RUNTIME_DIR');
  if Dir = '' then
    Dir := '/tmp';

  // 作って即 unlink し、fd だけをコンポジタへ渡す。
  FD := -1;
  for Attempt := 0 to 15 do
  begin
    Path := Format('%s/papimela-shm-%d-%d', [Dir, FpGetpid, Random(1000000)]);
    FD := FpOpen(PAnsiChar(Path), O_RDWR or O_CREAT or O_EXCL, &600);
    if FD >= 0 then
      Break;
  end;
  if FD < 0 then
    raise EPMLVideoError.CreateNative('failed to create a shm file', FpGetErrno, 'wayland');
  FpUnlink(PAnsiChar(Path));

  if FpFtruncate(FD, Size) <> 0 then
  begin
    FpClose(FD);
    raise EPMLVideoError.CreateNative('ftruncate on the shm file failed',
      FpGetErrno, 'wayland');
  end;

  FMap := Fpmmap(nil, Size, PROT_READ or PROT_WRITE, MAP_SHARED, FD, 0);
  if (FMap = nil) or (FMap = Pointer(-1)) then
  begin
    FMap := nil;
    FpClose(FD);
    raise EPMLVideoError.CreateNative('mmap on the shm file failed',
      FpGetErrno, 'wayland');
  end;
  FMapSize := Size;

  FShmPool := wl_shm_create_pool(FConn.Shm, FD, LongInt(Size));
  FBuffer := wl_shm_pool_create_buffer(FShmPool, 0, FWidth, FHeight,
    LongInt(Stride), WL_SHM_FORMAT_XRGB8888);
  FpClose(FD);   // プールが fd を保持するので閉じてよい

  FBufW := FWidth;
  FBufH := FHeight;
  Result := FBuffer <> nil;
end;

// 最初の configure に応答した直後に 1 枚出す。これでサーフェスがマップされる。
procedure TPMLWaylandWindowBackend.PresentFirstFrame;
begin
  if not FVisible then
    Exit;
  if not EnsureBuffer then
    Exit;
  FillChar(FMap^, FMapSize, 0);
  wl_surface_attach(FSurface, FBuffer, 0, 0);
  wl_surface_damage_buffer(FSurface, 0, 0, FWidth, FHeight);
  wl_surface_commit(FSurface);
  wl_display_flush(FConn.Display);
end;

function TPMLWaylandWindowBackend.CreateFramebuffer(out APixels: Pointer;
  out APitch: Integer): Boolean;
begin
  APixels := nil;
  APitch := 0;
  if not EnsureBuffer then
    Exit(False);
  APixels := FMap;
  APitch := FWidth * 4;
  Result := True;
end;

procedure TPMLWaylandWindowBackend.UpdateFramebuffer;
begin
  if (FBuffer = nil) or not FConfigured then
    Exit;
  wl_surface_attach(FSurface, FBuffer, 0, 0);
  wl_surface_damage_buffer(FSurface, 0, 0, FWidth, FHeight);
  wl_surface_commit(FSurface);
  wl_display_flush(FConn.Display);
end;

procedure TPMLWaylandWindowBackend.DestroyFramebuffer;
begin
  DestroyBuffer;
end;

{ ---- ウィンドウ操作 ---- }

procedure TPMLWaylandWindowBackend.SetTitle(const ATitle: String);
begin
  xdg_toplevel_set_title(FToplevel, PAnsiChar(ATitle));
  wl_display_flush(FConn.Display);
end;

procedure TPMLWaylandWindowBackend.SetSize(AWidth, AHeight: Integer);
begin
  // xdg-shell にはクライアントからサイズを指示する要求が無い。バッファのサイズが
  // ウィンドウのサイズになるので、次の更新で反映される。
  FWidth := AWidth;
  FHeight := AHeight;
  if Assigned(FSink) then
    FSink.WindowResized(FWindowID, FWidth, FHeight);
end;

procedure TPMLWaylandWindowBackend.SetMinimumSize(AWidth, AHeight: Integer);
begin
  xdg_toplevel_set_min_size(FToplevel, AWidth, AHeight);
end;

procedure TPMLWaylandWindowBackend.SetMaximumSize(AWidth, AHeight: Integer);
begin
  xdg_toplevel_set_max_size(FToplevel, AWidth, AHeight);
end;

procedure TPMLWaylandWindowBackend.Show;
begin
  FVisible := True;
  // 既に configure を受けているならこの場で 1 枚出す。まだなら
  // HandleSurfaceConfigure が出す。
  if FConfigured then
    PresentFirstFrame
  else
  begin
    wl_surface_commit(FSurface);
    wl_display_flush(FConn.Display);
  end;
end;

procedure TPMLWaylandWindowBackend.Hide;
begin
  FVisible := False;
  // nil バッファを attach するとサーフェスはアンマップされる。
  wl_surface_attach(FSurface, nil, 0, 0);
  wl_surface_commit(FSurface);
  wl_display_flush(FConn.Display);
end;

procedure TPMLWaylandWindowBackend.Maximize;
begin
  xdg_toplevel_set_maximized(FToplevel);
  wl_display_flush(FConn.Display);
end;

procedure TPMLWaylandWindowBackend.Minimize;
begin
  xdg_toplevel_set_minimized(FToplevel);
  wl_display_flush(FConn.Display);
end;

procedure TPMLWaylandWindowBackend.Restore;
begin
  xdg_toplevel_unset_maximized(FToplevel);
  wl_display_flush(FConn.Display);
end;

procedure TPMLWaylandWindowBackend.GetSizeInPixels(out AWidth, AHeight: Integer);
begin
  AWidth := FWidth;
  AHeight := FHeight;
end;

function TPMLWaylandWindowBackend.NativeHandles: TPMLNativeWindowHandles;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.WaylandDisplay := FConn.Display;
  Result.WaylandSurface := FSurface;
  Result.WaylandXdgSurface := FXdgSurface;
  Result.WaylandXdgToplevel := FToplevel;
end;

end.
