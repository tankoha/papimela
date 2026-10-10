{
  PaPiMeLa.Video.Wayland.Window — xdg-shell によるウィンドウと wl_shm バッファ

  Origin : partially ported from SDL (src/video/wayland/SDL_waylandwindow.c,
           src/video/wayland/SDL_waylandopengles.c)
           Scope: configure / ack_configure の順序制約、最初の configure より前に
           バッファを attach してはならないという規約、フレームコールバックを
           専用のイベントキューで待つ手順と、その待ちの上限（1/20 秒）。
           構造とクラス分割は本設計に従う。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.2、§11 #36、#39

  WHAT:
    wl_surface + xdg_surface + xdg_toplevel の状態機械と、wl_shm による
    ソフトウェアフレームバッファ（VSync つき）。

  WHY:
    ウィンドウが可視になるには、最初の xdg_surface.configure に ack_configure で
    応答し、その後でバッファを attach して commit する必要がある。この順序を
    守らないとコンポジタはサーフェスを表示しない。

  RESOLVED:
    - 生成したリスナーは抽象クラスなので、1 クラスで xdg_surface と xdg_toplevel の
      両方を継承できない。転送用の内部クラスを 2 つ置いて実体へ委譲する
    - サイズは xdg_toplevel.configure が 0x0 を送ることがある（コンポジタが
      アプリに任せる意味）。その場合は要求サイズを維持する
    - フレームバッファは 2 段にする。アプリが描くのはただのメモリ（FBacking）で、
      UpdateFramebuffer が「コンポジタが読んでいない」shm バッファへ写して出す。
      shm バッファへ直接描かせると、コンポジタが読んでいる最中に次の絵を
      書き込むことになる。写す分の手間（1920x1080 で 8 MB）と引き換えに、
      アプリから見た領域は大きさが変わるまで同じで、出した後も中身が残る
    - shm バッファは最大 3 枚まで使い回す。release が来ていないものは使わない
    - VSync は SDL の GLES 経路と同じく、前のフレームのフレームコールバックを
      専用のイベントキューで待ってから次を出す。待つのは最大 1/20 秒。
      隠れたウィンドウにはコールバックが来ないので、上限が無いと止まる
    - 専用のキューを使うのは、待っている間に入力イベントを配送しないため。
      読み出した入力イベントは既定のキューに残り、次の PumpEvents で配られる
    - GL（TPMLWindowFlag.OpenGL）のウィンドウは最初の 1 枚を出さない。EGL の
      最初の eglSwapBuffers がサーフェスをマップする。フレームコールバックの
      待ちと頼み（WaitForFrame / RequestFrame）は TPMLWaylandEGL が使う
    - Hide はアンマップなので、xdg-shell の規約どおり configure の済んだ状態を
      捨てる（FConfigured := False）。Show がバッファ無しの commit を出し、
      新しい configure を受けてから最初の 1 枚を出す

  NOT RESOLVED:
    - フルスクリーン・最大化の往復、装飾（libdecor）、ヒットテスト、グラブは未実装
    - HiDPI は wl_surface.set_buffer_scale を呼んでいない（scale 1 固定）
    - VSync は 0 と 1 だけ。2 以上（間引き）と -1（適応）は受け付けない

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Wayland.Window;

{$I papimela.inc}

interface

uses
  SysUtils, BaseUnix, Unix,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Pixels,
  PaPiMeLa.Video.Wayland.Types,
  PaPiMeLa.Video.Wayland.Shm,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.EGL,
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

  TPMLFrameCallbackForwarder = class(Twl_callback_listener)
  strict private
    FOwner: TPMLWaylandWindowBackend;
  public
    constructor Create(AOwner: TPMLWaylandWindowBackend);
    procedure done(AProxy: Pwl_callback; callback_data: LongWord); override;
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

    // フレームバッファ。アプリが描くのは FBacking、画面へ出すのは FShmBuffers。
    FBacking   : Pointer;
    FBackW, FBackH: Integer;
    FShmBuffers: array of TPMLWaylandShmBuffer;
    FVSync     : Integer;
    FPresentCount: Integer;
    FBuffersCreated: Integer;
    FFrameTimeouts: Integer;

    // フレームコールバックと release は専用のキューで受ける。
    FQueue         : Pwl_event_queue;
    FSurfaceWrapper: Pointer;         // FSurface を FQueue に向けた代理
    FFrameCallback : Pwl_callback;    // nil = 待っているフレームは無い
    FFrameFwd      : TPMLFrameCallbackForwarder;

    // GL（EGL）で描くウィンドウ。wl_egl_window は TPMLWaylandEGL が作って渡す。
    FIsGL     : Boolean;
    FEGLWindow: Pointer;

    // ポインタ拘束の「要求」。実際に拘束を張るのはシート（TPMLWaylandPointerGrab）。
    FMouseGrabbed : Boolean;
    FRelativeMouse: Boolean;
    FMouseRect    : TPMLRect;

    procedure DestroyBuffers;
    procedure EnsureBacking;
    function  PumpPrivateQueue(ATimeoutMs: Integer): Boolean;
    function  AcquireShmBuffer: TPMLWaylandShmBuffer;
    procedure PresentBacking(AWaitForFrame: Boolean);
    procedure PresentFirstFrame;
  private
    procedure HandleSurfaceConfigure(ASerial: LongWord);
    procedure HandleToplevelConfigure(AWidth, AHeight: Integer; AStates: Pwl_array);
    procedure HandleClose;
    procedure HandleFrameDone(ACallback: Pwl_callback);
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
    procedure SetMouseGrab(AGrabbed: Boolean); override;
    procedure SetMouseRect(const ARect: TPMLRect); override;
    procedure SetRelativeMouseMode(AEnabled: Boolean); override;
    procedure GetSizeInPixels(out AWidth, AHeight: Integer); override;
    function  CreateFramebuffer(out APixels: Pointer; out APitch: Integer;
      out AFormat: TPMLPixelFormat): Boolean; override;
    procedure UpdateFramebuffer; override;
    procedure DestroyFramebuffer; override;
    function  SetFramebufferVSync(AInterval: Integer): Boolean; override;
    function  NativeHandles: TPMLNativeWindowHandles; override;

    // 前のフレームのコールバックを待つ（最大 1/20 秒。来なければ捨てて打ち切る）。
    // ソフトウェアの UpdateFramebuffer と、GL の SwapSurface（TPMLWaylandEGL）が使う。
    procedure WaitForFrame;
    // 次のフレームのコールバックを頼む。まだ前のを待っているなら頼み直さない。
    // 頼みは次の wl_surface.commit で有効になる。GL では eglSwapBuffers の
    // commit が有効にするので、eglSwapBuffers より前に呼ぶ。
    procedure RequestFrame;

    property Configured: Boolean read FConfigured;
    // 表示中か（Show 済みで Hide されていない）。
    property Visible: Boolean read FVisible;
    // wl_egl_window。TPMLWaylandEGL が作って置く。置いてあると、configure で
    // 大きさが変わったときに wl_egl_window_resize を呼ぶ。
    property EGLWindow: Pointer read FEGLWindow write FEGLWindow;

    // 検査・デモ用の数。出した回数、作った shm バッファの累計、VSync の待ちが
    // 上限で打ち切られた回数。
    property PresentCount: Integer read FPresentCount;
    property BuffersCreated: Integer read FBuffersCreated;
    property FrameTimeouts: Integer read FFrameTimeouts;

    // シートが拘束を張るために読む。
    property Surface: Pwl_surface read FSurface;
    property MouseGrabbed: Boolean read FMouseGrabbed;
    property RelativeMouseRequested: Boolean read FRelativeMouse;
    property MouseRect: TPMLRect read FMouseRect;
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

constructor TPMLFrameCallbackForwarder.Create(AOwner: TPMLWaylandWindowBackend);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TPMLFrameCallbackForwarder.done(AProxy: Pwl_callback; callback_data: LongWord);
begin
  FOwner.HandleFrameDone(AProxy);
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
  FIsGL := TPMLWindowFlag.OpenGL in AFlags;
  if FWidth <= 0 then FWidth := 640;
  if FHeight <= 0 then FHeight := 480;

  FSurface := wl_compositor_create_surface(FConn.Compositor);
  if FSurface = nil then
    raise EPMLVideoError.CreateNative('wl_compositor.create_surface failed', 0, 'wayland');

  // Seat がサーフェスからウィンドウを引けるようにする。wl_surface には
  // リスナーを付けていないので user_data は空いている。
  wl_proxy_set_user_data(Pwl_proxy(FSurface), Self);

  // フレームコールバックと release を受ける専用のキュー。wl_surface.frame は
  // この代理から出すので、done は既定のキューではなくここへ届く。
  FQueue := wl_display_create_queue(FConn.Display);
  FSurfaceWrapper := wl_proxy_create_wrapper(FSurface);
  wl_proxy_set_queue(Pwl_proxy(FSurfaceWrapper), FQueue);
  FFrameFwd := TPMLFrameCallbackForwarder.Create(Self);

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
  DestroyFramebuffer;
  if FFrameCallback <> nil then
    wl_proxy_destroy(Pwl_proxy(FFrameCallback));
  FFrameCallback := nil;
  if FSurfaceWrapper <> nil then
    wl_proxy_wrapper_destroy(FSurfaceWrapper);
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
  FreeAndNil(FFrameFwd);
  // キューは、そこへ向いた代理（バッファ・コールバック・代理のサーフェス）を
  // すべて壊してから壊す。
  if FQueue <> nil then
    wl_event_queue_destroy(FQueue);
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
    // GL の面の大きさは wl_egl_window が決める。SDL も configure の中で
    // wl_egl_window_resize を呼ぶ（SDL_waylandwindow.c の幾何の更新）。
    if FEGLWindow <> nil then
      wl_egl_window_resize(FEGLWindow, FWidth, FHeight, 0, 0);
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

{ ---- フレームバッファ ---- }

procedure TPMLWaylandWindowBackend.DestroyBuffers;
var
  I: Integer;
begin
  for I := 0 to High(FShmBuffers) do
    FShmBuffers[I].Free;
  SetLength(FShmBuffers, 0);
end;

procedure TPMLWaylandWindowBackend.EnsureBacking;
var
  Size: PtrUInt;
begin
  if (FBacking <> nil) and (FBackW = FWidth) and (FBackH = FHeight) then
    Exit;
  if FBacking <> nil then
    FreeMem(FBacking);
  FBacking := nil;
  FBackW := 0;
  FBackH := 0;
  Size := PtrUInt(FWidth) * PtrUInt(FHeight) * 4;
  if Size = 0 then
    Exit;
  FBacking := AllocMem(Size);   // 0 で埋まる（XRGB の黒）
  FBackW := FWidth;
  FBackH := FHeight;
end;

{ 専用キューの届いている分を配り、無ければ最大 ATimeoutMs だけ待って読む。
  何か配ったら True。

  PORT-NOTE: SDL の Wayland_GLES_SwapWindow の待ちループの 1 周分。
  prepare_read_queue が 0 以外なら、キューにもう届いているので配るだけでよい。
  0 なら「読む権利」を取ったので、read_events か cancel_read のどちらかを
  必ず呼ぶ。 }
function TPMLWaylandWindowBackend.PumpPrivateQueue(ATimeoutMs: Integer): Boolean;
var
  PFD: TPollFd;
begin
  wl_display_flush(FConn.Display);
  if wl_display_prepare_read_queue(FConn.Display, FQueue) <> 0 then
  begin
    wl_display_dispatch_queue_pending(FConn.Display, FQueue);
    Exit(True);
  end;
  PFD.fd := wl_display_get_fd(FConn.Display);
  PFD.events := POLLIN;
  PFD.revents := 0;
  if (fppoll(@PFD, 1, ATimeoutMs) > 0) and ((PFD.revents and POLLIN) <> 0) then
  begin
    // 他のキュー宛ての分（入力など）も読まれるが、それぞれのキューに残る。
    wl_display_read_events(FConn.Display);
    Result := wl_display_dispatch_queue_pending(FConn.Display, FQueue) > 0;
  end
  else
  begin
    wl_display_cancel_read(FConn.Display);
    Result := False;
  end;
end;

{ 前に出したフレームのコールバックを待つ。最大 1/20 秒。

  PORT-NOTE: 上限は SDL と同じ（「止められても 20Hz では進む」）。打ち切ったら
  待っていたコールバックは捨てる。隠れたウィンドウでは来ないままなので、
  残しておくと次からも毎回上限まで待つことになる。 }
procedure TPMLWaylandWindowBackend.WaitForFrame;
var
  Deadline, Now: QWord;
begin
  if FFrameCallback = nil then
    Exit;
  Deadline := GetTickCount64 + 50;
  while FFrameCallback <> nil do
  begin
    Now := GetTickCount64;
    if Now >= Deadline then
      Break;
    PumpPrivateQueue(Integer(Deadline - Now));
  end;
  if FFrameCallback <> nil then
  begin
    wl_proxy_destroy(Pwl_proxy(FFrameCallback));
    FFrameCallback := nil;
    Inc(FFrameTimeouts);
  end;
end;

{ 次のフレームの合図を頼む。代理は FQueue を向いているので、done は
  専用キューへ届く。まだ前の合図を待っているなら頼み直さない。 }
procedure TPMLWaylandWindowBackend.RequestFrame;
begin
  if FFrameCallback <> nil then
    Exit;
  FFrameCallback := wl_surface_frame(Pwl_surface(FSurfaceWrapper));
  wl_callback_add_listener_object(FFrameCallback, FFrameFwd);
end;

procedure TPMLWaylandWindowBackend.HandleFrameDone(ACallback: Pwl_callback);
begin
  if ACallback <> FFrameCallback then
    Exit;
  wl_proxy_destroy(Pwl_proxy(FFrameCallback));
  FFrameCallback := nil;
end;

{ コンポジタが読んでいない、今の大きさの shm バッファを 1 枚返す。

  使い回すのは最大 3 枚（表示中・次に表示・描き込み中）。全部読まれている
  ときは release を最大 1/20 秒待ち、それでも来なければ 1 枚足す。
  足すのは 6 枚までで、それを超えたら nil（このフレームは出さない）。 }
function TPMLWaylandWindowBackend.AcquireShmBuffer: TPMLWaylandShmBuffer;
const
  PreferredCount = 3;
  MaxCount = 6;
var
  I, J: Integer;
  Deadline, Now: QWord;

  function FindFree: TPMLWaylandShmBuffer;
  var
    K: Integer;
  begin
    for K := 0 to High(FShmBuffers) do
      if not FShmBuffers[K].Busy then
        Exit(FShmBuffers[K]);
    Result := nil;
  end;

  function AddBuffer: TPMLWaylandShmBuffer;
  begin
    Result := TPMLWaylandShmBuffer.Create(FConn.Shm, FBackW, FBackH, FQueue);
    SetLength(FShmBuffers, Length(FShmBuffers) + 1);
    FShmBuffers[High(FShmBuffers)] := Result;
    Inc(FBuffersCreated);
  end;

begin
  // 届いている release を先に配る。
  PumpPrivateQueue(0);

  // 大きさの違うものは、読まれていなければ捨てる。読まれているものは
  // release が来てから捨てる。
  for I := High(FShmBuffers) downto 0 do
    if (not FShmBuffers[I].Busy)
    and ((FShmBuffers[I].Width <> FBackW) or (FShmBuffers[I].Height <> FBackH)) then
    begin
      FShmBuffers[I].Free;
      for J := I to High(FShmBuffers) - 1 do
        FShmBuffers[J] := FShmBuffers[J + 1];
      SetLength(FShmBuffers, Length(FShmBuffers) - 1);
    end;

  Result := FindFree;
  if Result <> nil then
    Exit;
  if Length(FShmBuffers) < PreferredCount then
    Exit(AddBuffer);

  Deadline := GetTickCount64 + 50;
  repeat
    Now := GetTickCount64;
    if Now >= Deadline then
      Break;
    PumpPrivateQueue(Integer(Deadline - Now));
    Result := FindFree;
  until Result <> nil;
  if Result <> nil then
    Exit;
  if Length(FShmBuffers) < MaxCount then
    Exit(AddBuffer);
  Result := nil;
end;

{ FBacking の中身を shm バッファへ写して出す。 }
procedure TPMLWaylandWindowBackend.PresentBacking(AWaitForFrame: Boolean);
var
  Buf: TPMLWaylandShmBuffer;
begin
  if (FBacking = nil) or (FConn.Shm = nil) then
    Exit;
  if AWaitForFrame then
    WaitForFrame;
  Buf := AcquireShmBuffer;
  if Buf = nil then
    Exit;
  // 大きさが同じなので行の幅も同じ。1 回で写せる。
  Move(FBacking^, Buf.Pixels^, PtrUInt(Buf.Stride) * PtrUInt(Buf.Height));
  Buf.MarkBusy;
  wl_surface_attach(FSurface, Buf.Buffer, 0, 0);
  wl_surface_damage_buffer(FSurface, 0, 0, Buf.Width, Buf.Height);
  RequestFrame;
  wl_surface_commit(FSurface);
  wl_display_flush(FConn.Display);
  Inc(FPresentCount);
end;

// 最初の configure に応答した直後に 1 枚出す。これでサーフェスがマップされる。
procedure TPMLWaylandWindowBackend.PresentFirstFrame;
begin
  if not FVisible then
    Exit;
  // GL のウィンドウは、最初の eglSwapBuffers がサーフェスをマップする。
  // ソフトウェアの 1 枚を先に出すと、GL の最初の絵の前に黒が 1 フレーム映る。
  if FIsGL then
    Exit;
  EnsureBacking;
  PresentBacking(False);
end;

function TPMLWaylandWindowBackend.CreateFramebuffer(out APixels: Pointer;
  out APitch: Integer; out AFormat: TPMLPixelFormat): Boolean;
begin
  APixels := nil;
  APitch := 0;
  AFormat := PML_PIXELFORMAT_XRGB8888;
  if FConn.Shm = nil then
    Exit(False);
  EnsureBacking;
  if FBacking = nil then
    Exit(False);
  APixels := FBacking;
  APitch := FBackW * 4;
  Result := True;
end;

procedure TPMLWaylandWindowBackend.UpdateFramebuffer;
begin
  if not (FConfigured and FVisible) then
    Exit;
  PresentBacking(FVSync > 0);
end;

procedure TPMLWaylandWindowBackend.DestroyFramebuffer;
begin
  DestroyBuffers;
  if FBacking <> nil then
    FreeMem(FBacking);
  FBacking := nil;
  FBackW := 0;
  FBackH := 0;
end;

function TPMLWaylandWindowBackend.SetFramebufferVSync(AInterval: Integer): Boolean;
begin
  Result := (AInterval = 0) or (AInterval = 1);
  if Result then
    FVSync := AInterval;
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
  if FEGLWindow <> nil then
    wl_egl_window_resize(FEGLWindow, FWidth, FHeight, 0, 0);
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
  // アンマップしたサーフェスにはフレームコールバックが来ない。待ちを捨てておく。
  if FFrameCallback <> nil then
  begin
    wl_proxy_destroy(Pwl_proxy(FFrameCallback));
    FFrameCallback := nil;
  end;
  // nil バッファを attach するとサーフェスはアンマップされる。xdg-shell では
  // アンマップで configure の済んだ状態も失われ、次に見せるには「バッファ無しの
  // commit → configure → ack_configure」をやり直さなければならない（守らないと
  // コンポジタが "xdg_surface has never been configured" で接続を切る）。
  // Show がその commit を出し、新しい configure が FConfigured を立て直す。
  FConfigured := False;
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

{ xdg-shell には最小化を解く要求が無いので、最大化を解くだけ（SDL も同じ）。 }
procedure TPMLWaylandWindowBackend.Restore;
begin
  xdg_toplevel_unset_maximized(FToplevel);
  wl_display_flush(FConn.Display);
end;


{ ポインタ拘束の要求を記録して、シートへ「張り直せ」と伝える。

  拘束オブジェクトを持つのは wl_pointer なので、ここでは要求を覚えるだけにする
  （Design: docs/DESIGN.md §3.2）。誰が拘束を張るかは接続経由で解決する。 }
procedure TPMLWaylandWindowBackend.SetMouseGrab(AGrabbed: Boolean);
begin
  if FMouseGrabbed = AGrabbed then
    Exit;
  FMouseGrabbed := AGrabbed;
  FConn.NotifyGrabsChanged(WindowID);
end;

procedure TPMLWaylandWindowBackend.SetMouseRect(const ARect: TPMLRect);
begin
  FMouseRect := ARect;
  // 矩形は毎回作り直すので、同じ値でも通知してよい。
  FConn.NotifyGrabsChanged(WindowID);
end;

procedure TPMLWaylandWindowBackend.SetRelativeMouseMode(AEnabled: Boolean);
begin
  if FRelativeMouse = AEnabled then
    Exit;
  FRelativeMouse := AEnabled;
  FConn.NotifyGrabsChanged(WindowID);
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
  Result.WaylandEGLWindow := FEGLWindow;
end;

end.
