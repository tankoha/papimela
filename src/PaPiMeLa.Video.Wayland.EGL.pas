{
  PaPiMeLa.Video.Wayland.EGL — Wayland の GL 部品（EGL の Wayland 派生）

  Origin : partially ported from SDL (src/video/wayland/SDL_waylandopengles.c)
           Scope: スワップ間隔を自前で管理する方針（EGL には常に 0 を渡す）、
           Wayland_GLES_SwapWindow のフレームコールバック待ち（最大 1/20 秒、
           マップされていないウィンドウの swap を飛ばす）、MakeCurrent 直後の
           eglSwapInterval(0)、各操作の後の wl_display_flush。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.4、§11 #39

  WHAT:
    TPMLEGLBackend の Wayland 実装。ネイティブディスプレイは wl_display、
    ネイティブウィンドウは wl_egl_window。画面へ出す手順は、ウィンドウの
    フレームコールバックの仕組み（TPMLWaylandWindowBackend.WaitForFrame /
    RequestFrame）を使って自前でペースを取る。

  WHY:
    スワップ間隔が 0 以外だと Mesa は eglSwapBuffers の中でフレームコールバックを
    待つ。コンポジタは最小化されたウィンドウにコールバックを送らないことがあり、
    その場合アプリが永久に止まる。そこで EGL 自体には常に間隔 0 を渡し、待ちは
    papimela が上限つき（1/20 秒）で行う。上限を過ぎたらフレームを捨てて進む。

  RESOLVED:
    - スワップ間隔は -1 .. 1 に丸めて覚えるだけ。0 でなければ待つ（-1 も 1 と
      同じ扱い。次の垂直同期を待てない以上、Wayland では全部「適応」である）
    - 次のフレームの合図は eglSwapBuffers より前に頼む。Mesa が swap の中で
      行う wl_surface.commit が、その頼みを有効にする
    - まだ configure を受けていない、または表示されていないウィンドウでは
      swap を飛ばして True を返す。マップされていない面への swap は、
      コンポジタが意図的に止めることがある
    - wl_egl_window はウィンドウのバックエンドに登録する。configure で大きさが
      変わると、ウィンドウ側が wl_egl_window_resize を呼ぶ

  NOT RESOLVED:
    - SDL の double_buffer（低遅延モード: 先に swap してからコールバックを待つ）は
      移植していない
    - EGL_WAYLAND_swap_buffers_with_timeout は使っていない（SDL の FIXME）
    - HiDPI（バッファのスケール）は考慮しない。面の大きさは論理サイズのまま

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Wayland.EGL;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Platform.EGL,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.EGL,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video.EGL,
  PaPiMeLa.Video.Wayland.Types,
  PaPiMeLa.Video.Wayland.Window;

type
  TPMLWaylandEGL = class(TPMLEGLBackend)
  strict private
    FConn: TPMLWaylandConnection;
    FWaylandEGLLoaded: Boolean;
    procedure Flush;
  strict protected
    function  GetPlatform: EGLenum; override;
    function  GetNativeDisplay: Pointer; override;
    function  CreateNativeWindow(AWindow: TPMLWindowBackend): EGLNativeWindowType; override;
    procedure DestroyNativeWindow(AWindow: TPMLWindowBackend;
      ANative: EGLNativeWindowType); override;
    function  SwapSurface(AWindow: TPMLWindowBackend;
      ASurface: EGLSurface): Boolean; override;
  public
    // AConn は GL の部品より長生きしなければならない（ディスプレイを借りる）。
    constructor Create(AContextRef: TObject; AOwner: TPMLObject;
      AConn: TPMLWaylandConnection);
    destructor Destroy; override;

    function  CreateContext(AWindow: TPMLWindowBackend;
      const AAttrs: TPMLGLAttributes): TPMLGLContextHandle; override;
    function  MakeCurrent(AWindow: TPMLWindowBackend;
      AContext: TPMLGLContextHandle): Boolean; override;
    procedure DestroyContext(AContext: TPMLGLContextHandle); override;
    function  SetSwapInterval(AInterval: Integer): Boolean; override;
  end;

implementation

constructor TPMLWaylandEGL.Create(AContextRef: TObject; AOwner: TPMLObject;
  AConn: TPMLWaylandConnection);
begin
  inherited Create(AContextRef, AOwner);
  FConn := AConn;
end;

destructor TPMLWaylandEGL.Destroy;
begin
  // wl_egl_window の破棄と eglTerminate は、ライブラリと接続が生きているうちに行う。
  Shutdown;
  if FWaylandEGLLoaded then
  begin
    PMLWaylandEGLUnload;
    FWaylandEGLLoaded := False;
  end;
  inherited Destroy;
end;

procedure TPMLWaylandEGL.Flush;
begin
  if FConn.Display <> nil then
    wl_display_flush(FConn.Display);
end;

function TPMLWaylandEGL.GetPlatform: EGLenum;
begin
  Result := EGL_PLATFORM_WAYLAND_KHR;
end;

function TPMLWaylandEGL.GetNativeDisplay: Pointer;
begin
  Result := FConn.Display;
end;

function TPMLWaylandEGL.CreateNativeWindow(AWindow: TPMLWindowBackend): EGLNativeWindowType;
var
  W: TPMLWaylandWindowBackend;
  Width, Height: Integer;
begin
  Result := nil;
  if not (AWindow is TPMLWaylandWindowBackend) then
  begin
    FLastError := 'the window is not a Wayland window';
    Exit;
  end;
  if not FWaylandEGLLoaded then
  begin
    if not PMLWaylandEGLLoad then
    begin
      FLastError := 'could not load libwayland-egl';
      Exit;
    end;
    FWaylandEGLLoaded := True;
  end;
  W := TPMLWaylandWindowBackend(AWindow);
  W.GetSizeInPixels(Width, Height);
  Result := wl_egl_window_create(W.Surface, Width, Height);
  if Result = nil then
  begin
    FLastError := 'wl_egl_window_create failed';
    Exit;
  end;
  // configure で大きさが変わったら、ウィンドウ側が wl_egl_window_resize を呼ぶ。
  W.EGLWindow := Result;
end;

procedure TPMLWaylandEGL.DestroyNativeWindow(AWindow: TPMLWindowBackend;
  ANative: EGLNativeWindowType);
begin
  if AWindow is TPMLWaylandWindowBackend then
    TPMLWaylandWindowBackend(AWindow).EGLWindow := nil;
  if (ANative <> nil) and FWaylandEGLLoaded then
    wl_egl_window_destroy(ANative);
end;

function TPMLWaylandEGL.CreateContext(AWindow: TPMLWindowBackend;
  const AAttrs: TPMLGLAttributes): TPMLGLContextHandle;
begin
  Result := inherited CreateContext(AWindow, AAttrs);
  Flush;
end;

{ PORT-NOTE: Wayland_GLES_MakeCurrent。MakeCurrent のたびに EGL のスワップ間隔を
  0 へ戻す。eglSwapInterval は現在の描画面に効き、Mesa の既定は 1 なので、
  面が現在になるたびに打ち消さないと EGL の中で待つようになる。 }
function TPMLWaylandEGL.MakeCurrent(AWindow: TPMLWindowBackend;
  AContext: TPMLGLContextHandle): Boolean;
begin
  Result := inherited MakeCurrent(AWindow, AContext);
  Flush;
  if Result and (AWindow <> nil) and (AContext <> nil) then
    eglSwapInterval(EGLDisplayHandle, 0);
end;

procedure TPMLWaylandEGL.DestroyContext(AContext: TPMLGLContextHandle);
begin
  inherited DestroyContext(AContext);
  Flush;
end;

{ PORT-NOTE: Wayland_GLES_SetSwapInterval。値は -1 .. 1 に丸めて覚えるだけで、
  EGL には 0 を渡し続ける（ヘッダの WHY を参照）。SDL は「技術的にはコンテキスト
  ごと」と FIXME を残しているが、ここも SDL と同じく全体で 1 つ。 }
function TPMLWaylandEGL.SetSwapInterval(AInterval: Integer): Boolean;
begin
  if EGLDisplayHandle = EGL_NO_DISPLAY then
  begin
    FLastError := 'EGL not initialized';
    Exit(False);
  end;
  if AInterval > 1 then
    AInterval := 1
  else if AInterval < -1 then
    AInterval := -1;
  StoredSwapInterval := AInterval;
  eglSwapInterval(EGLDisplayHandle, 0);
  Result := True;
end;

{ PORT-NOTE: Wayland_GLES_SwapWindow の、double_buffer でない経路。
  SDL はコールバックの到来を「swap_interval_ready」の旗で見て、到来のたびに
  次のコールバックを頼み直す。papimela は待つ前のコールバックが残っているかで
  見て（WaitForFrame）、swap の直前に頼む。結果は同じで、頼みは swap の
  commit で有効になる。 }
function TPMLWaylandEGL.SwapSurface(AWindow: TPMLWindowBackend;
  ASurface: EGLSurface): Boolean;
var
  W: TPMLWaylandWindowBackend;
begin
  if not (AWindow is TPMLWaylandWindowBackend) then
  begin
    FLastError := 'the window is not a Wayland window';
    Exit(False);
  end;
  W := TPMLWaylandWindowBackend(AWindow);
  // configure 前・非表示のウィンドウは swap しない。マップされていない面への
  // swap は、コンポジタが意図的に止めることがある（SDL のコメントと同じ）。
  if not (W.Configured and W.Visible) then
    Exit(True);

  if StoredSwapInterval <> 0 then
  begin
    W.WaitForFrame;
    W.RequestFrame;
  end;

  Result := inherited SwapSurface(AWindow, ASurface);
  Flush;
end;

end.
