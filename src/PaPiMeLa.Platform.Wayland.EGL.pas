{
  PaPiMeLa.Platform.Wayland.EGL — libwayland-egl の実行時結合

  Origin : partially ported from SDL (src/video/wayland/SDL_waylandsym.h)
           Scope: 使う関数（wl_egl_window_create / destroy / resize /
           get_attached_size）の一覧と引数の型。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §9、§11 #17

  WHAT:
    wl_surface に EGL のサーフェスを結び付けるための wl_egl_window を作る
    4 つの関数を、libwayland-egl.so.1 から実行時に取る。

  WHY:
    libwayland-egl はリンクしない（§9）。EGL を使わない環境でも papimela は
    起動でき、GL のコンテキストを作るときに初めて要る。

  RESOLVED:
    - wl_egl_window は不透明型なので Pointer で持つ
    - 4 関数のうち 1 つでも無ければ読み込み失敗（何も残さない）
    - 読み込みは参照カウント。PaPiMeLa.Platform.XKB と同じ形

  NOT RESOLVED:
    - wl_egl_window_get_attached_size は宣言だけで、papimela はまだ呼ばない

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.Wayland.EGL;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

var
  { 作った wl_egl_window は AWidth x AHeight のバッファを持つ。失敗したら nil。 }
  wl_egl_window_create: function(ASurface: Pwl_surface;
    AWidth, AHeight: LongInt): Pointer; cdecl = nil;
  wl_egl_window_destroy: procedure(AWindow: Pointer); cdecl = nil;
  { 次の eglSwapBuffers から新しい大きさになる。ADx / ADy はバッファの原点の移動量。 }
  wl_egl_window_resize: procedure(AWindow: Pointer;
    AWidth, AHeight, ADx, ADy: LongInt); cdecl = nil;
  wl_egl_window_get_attached_size: procedure(AWindow: Pointer;
    AWidth, AHeight: PLongInt); cdecl = nil;

{ libwayland-egl を読み込む。既に読み込んでいれば参照カウントを増やすだけ。
  ライブラリが無いか、関数が 1 つでも無ければ False（何も残さない）。 }
function  PMLWaylandEGLLoad: Boolean;
procedure PMLWaylandEGLUnload;
function  PMLWaylandEGLLoaded: Boolean;

implementation

const
  LIBWAYLAND_EGL_NAMES: array[0..1] of String =
    ('libwayland-egl.so.1', 'libwayland-egl.so');

var
  GLib: TPMLDynLib = nil;
  GRefCount: Integer = 0;

procedure ClearAll;
begin
  wl_egl_window_create := nil;
  wl_egl_window_destroy := nil;
  wl_egl_window_resize := nil;
  wl_egl_window_get_attached_size := nil;
end;

function PMLWaylandEGLLoad: Boolean;
begin
  if GRefCount > 0 then
  begin
    Inc(GRefCount);
    Exit(True);
  end;
  try
    GLib := TPMLDynLib.Create(LIBWAYLAND_EGL_NAMES);
  except
    on E: EPMLPlatformLibrary do
    begin
      GLib := nil;
      Exit(False);
    end;
  end;

  try
    Pointer(wl_egl_window_create) := GLib.Resolve('wl_egl_window_create');
    Pointer(wl_egl_window_destroy) := GLib.Resolve('wl_egl_window_destroy');
    Pointer(wl_egl_window_resize) := GLib.Resolve('wl_egl_window_resize');
    Pointer(wl_egl_window_get_attached_size) :=
      GLib.Resolve('wl_egl_window_get_attached_size');
  except
    on E: EPMLPlatformLibrary do
    begin
      ClearAll;
      FreeAndNil(GLib);
      Exit(False);
    end;
  end;

  GRefCount := 1;
  Result := True;
end;

procedure PMLWaylandEGLUnload;
begin
  if GRefCount = 0 then
    Exit;
  Dec(GRefCount);
  if GRefCount > 0 then
    Exit;
  ClearAll;
  FreeAndNil(GLib);
end;

function PMLWaylandEGLLoaded: Boolean;
begin
  Result := GRefCount > 0;
end;

end.
