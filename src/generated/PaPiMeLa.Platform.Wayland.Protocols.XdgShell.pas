{
  PaPiMeLa.Platform.Wayland.Protocols.XdgShell

  自動生成ファイル。手で編集しないこと。
  生成元: xdg_shell.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright � 2008-2013 Kristian H�gsberg
      Copyright � 2013      Rafael Antognolli
      Copyright � 2013      Jasper St. Pierre
      Copyright � 2010-2013 Intel Corporation
      Copyright � 2015-2017 Samsung Electronics Co., Ltd
      Copyright � 2015-2017 Red Hat Inc.
  
      Permission is hereby granted, free of charge, to any person obtaining a
      copy of this software and associated documentation files (the "Software"),
      to deal in the Software without restriction, including without limitation
      the rights to use, copy, modify, merge, publish, distribute, sublicense,
      and/or sell copies of the Software, and to permit persons to whom the
      Software is furnished to do so, subject to the following conditions:
  
      The above copyright notice and this permission notice (including the next
      paragraph) shall be included in all copies or substantial portions of the
      Software.
  
      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
      IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
      FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
      THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
      LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
      FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
      DEALINGS IN THE SOFTWARE.

}
unit PaPiMeLa.Platform.Wayland.Protocols.XdgShell;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  Txdg_wm_base_opaque = record end;
  Pxdg_wm_base = ^Txdg_wm_base_opaque;
  Txdg_positioner_opaque = record end;
  Pxdg_positioner = ^Txdg_positioner_opaque;
  Txdg_surface_opaque = record end;
  Pxdg_surface = ^Txdg_surface_opaque;
  Txdg_toplevel_opaque = record end;
  Pxdg_toplevel = ^Txdg_toplevel_opaque;
  Txdg_popup_opaque = record end;
  Pxdg_popup = ^Txdg_popup_opaque;

const
  // xdg_wm_base (version 7)
  XDG_WM_BASE_DESTROY_OPCODE = 0;
  XDG_WM_BASE_CREATE_POSITIONER_OPCODE = 1;
  XDG_WM_BASE_GET_XDG_SURFACE_OPCODE = 2;
  XDG_WM_BASE_PONG_OPCODE = 3;
  XDG_WM_BASE_DESTROY_SINCE_VERSION = 1;
  XDG_WM_BASE_CREATE_POSITIONER_SINCE_VERSION = 1;
  XDG_WM_BASE_GET_XDG_SURFACE_SINCE_VERSION = 1;
  XDG_WM_BASE_PONG_SINCE_VERSION = 1;
  XDG_WM_BASE_PING_SINCE_VERSION = 1;
  XDG_WM_BASE_ERROR_ROLE = 0;
  XDG_WM_BASE_ERROR_DEFUNCT_SURFACES = 1;
  XDG_WM_BASE_ERROR_NOT_THE_TOPMOST_POPUP = 2;
  XDG_WM_BASE_ERROR_INVALID_POPUP_PARENT = 3;
  XDG_WM_BASE_ERROR_INVALID_SURFACE_STATE = 4;
  XDG_WM_BASE_ERROR_INVALID_POSITIONER = 5;
  XDG_WM_BASE_ERROR_UNRESPONSIVE = 6;

  // xdg_positioner (version 7)
  XDG_POSITIONER_DESTROY_OPCODE = 0;
  XDG_POSITIONER_SET_SIZE_OPCODE = 1;
  XDG_POSITIONER_SET_ANCHOR_RECT_OPCODE = 2;
  XDG_POSITIONER_SET_ANCHOR_OPCODE = 3;
  XDG_POSITIONER_SET_GRAVITY_OPCODE = 4;
  XDG_POSITIONER_SET_CONSTRAINT_ADJUSTMENT_OPCODE = 5;
  XDG_POSITIONER_SET_OFFSET_OPCODE = 6;
  XDG_POSITIONER_SET_REACTIVE_OPCODE = 7;
  XDG_POSITIONER_SET_PARENT_SIZE_OPCODE = 8;
  XDG_POSITIONER_SET_PARENT_CONFIGURE_OPCODE = 9;
  XDG_POSITIONER_DESTROY_SINCE_VERSION = 1;
  XDG_POSITIONER_SET_SIZE_SINCE_VERSION = 1;
  XDG_POSITIONER_SET_ANCHOR_RECT_SINCE_VERSION = 1;
  XDG_POSITIONER_SET_ANCHOR_SINCE_VERSION = 1;
  XDG_POSITIONER_SET_GRAVITY_SINCE_VERSION = 1;
  XDG_POSITIONER_SET_CONSTRAINT_ADJUSTMENT_SINCE_VERSION = 1;
  XDG_POSITIONER_SET_OFFSET_SINCE_VERSION = 1;
  XDG_POSITIONER_SET_REACTIVE_SINCE_VERSION = 3;
  XDG_POSITIONER_SET_PARENT_SIZE_SINCE_VERSION = 3;
  XDG_POSITIONER_SET_PARENT_CONFIGURE_SINCE_VERSION = 3;
  XDG_POSITIONER_ERROR_INVALID_INPUT = 0;
  XDG_POSITIONER_ANCHOR_NONE = 0;
  XDG_POSITIONER_ANCHOR_TOP = 1;
  XDG_POSITIONER_ANCHOR_BOTTOM = 2;
  XDG_POSITIONER_ANCHOR_LEFT = 3;
  XDG_POSITIONER_ANCHOR_RIGHT = 4;
  XDG_POSITIONER_ANCHOR_TOP_LEFT = 5;
  XDG_POSITIONER_ANCHOR_BOTTOM_LEFT = 6;
  XDG_POSITIONER_ANCHOR_TOP_RIGHT = 7;
  XDG_POSITIONER_ANCHOR_BOTTOM_RIGHT = 8;
  XDG_POSITIONER_GRAVITY_NONE = 0;
  XDG_POSITIONER_GRAVITY_TOP = 1;
  XDG_POSITIONER_GRAVITY_BOTTOM = 2;
  XDG_POSITIONER_GRAVITY_LEFT = 3;
  XDG_POSITIONER_GRAVITY_RIGHT = 4;
  XDG_POSITIONER_GRAVITY_TOP_LEFT = 5;
  XDG_POSITIONER_GRAVITY_BOTTOM_LEFT = 6;
  XDG_POSITIONER_GRAVITY_TOP_RIGHT = 7;
  XDG_POSITIONER_GRAVITY_BOTTOM_RIGHT = 8;
  XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_NONE = 0;
  XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X = 1;
  XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y = 2;
  XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_X = 4;
  XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_Y = 8;
  XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_RESIZE_X = 16;
  XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_RESIZE_Y = 32;

  // xdg_surface (version 7)
  XDG_SURFACE_DESTROY_OPCODE = 0;
  XDG_SURFACE_GET_TOPLEVEL_OPCODE = 1;
  XDG_SURFACE_GET_POPUP_OPCODE = 2;
  XDG_SURFACE_SET_WINDOW_GEOMETRY_OPCODE = 3;
  XDG_SURFACE_ACK_CONFIGURE_OPCODE = 4;
  XDG_SURFACE_DESTROY_SINCE_VERSION = 1;
  XDG_SURFACE_GET_TOPLEVEL_SINCE_VERSION = 1;
  XDG_SURFACE_GET_POPUP_SINCE_VERSION = 1;
  XDG_SURFACE_SET_WINDOW_GEOMETRY_SINCE_VERSION = 1;
  XDG_SURFACE_ACK_CONFIGURE_SINCE_VERSION = 1;
  XDG_SURFACE_CONFIGURE_SINCE_VERSION = 1;
  XDG_SURFACE_ERROR_NOT_CONSTRUCTED = 1;
  XDG_SURFACE_ERROR_ALREADY_CONSTRUCTED = 2;
  XDG_SURFACE_ERROR_UNCONFIGURED_BUFFER = 3;
  XDG_SURFACE_ERROR_INVALID_SERIAL = 4;
  XDG_SURFACE_ERROR_INVALID_SIZE = 5;
  XDG_SURFACE_ERROR_DEFUNCT_ROLE_OBJECT = 6;

  // xdg_toplevel (version 7)
  XDG_TOPLEVEL_DESTROY_OPCODE = 0;
  XDG_TOPLEVEL_SET_PARENT_OPCODE = 1;
  XDG_TOPLEVEL_SET_TITLE_OPCODE = 2;
  XDG_TOPLEVEL_SET_APP_ID_OPCODE = 3;
  XDG_TOPLEVEL_SHOW_WINDOW_MENU_OPCODE = 4;
  XDG_TOPLEVEL_MOVE_OPCODE = 5;
  XDG_TOPLEVEL_RESIZE_OPCODE = 6;
  XDG_TOPLEVEL_SET_MAX_SIZE_OPCODE = 7;
  XDG_TOPLEVEL_SET_MIN_SIZE_OPCODE = 8;
  XDG_TOPLEVEL_SET_MAXIMIZED_OPCODE = 9;
  XDG_TOPLEVEL_UNSET_MAXIMIZED_OPCODE = 10;
  XDG_TOPLEVEL_SET_FULLSCREEN_OPCODE = 11;
  XDG_TOPLEVEL_UNSET_FULLSCREEN_OPCODE = 12;
  XDG_TOPLEVEL_SET_MINIMIZED_OPCODE = 13;
  XDG_TOPLEVEL_DESTROY_SINCE_VERSION = 1;
  XDG_TOPLEVEL_SET_PARENT_SINCE_VERSION = 1;
  XDG_TOPLEVEL_SET_TITLE_SINCE_VERSION = 1;
  XDG_TOPLEVEL_SET_APP_ID_SINCE_VERSION = 1;
  XDG_TOPLEVEL_SHOW_WINDOW_MENU_SINCE_VERSION = 1;
  XDG_TOPLEVEL_MOVE_SINCE_VERSION = 1;
  XDG_TOPLEVEL_RESIZE_SINCE_VERSION = 1;
  XDG_TOPLEVEL_SET_MAX_SIZE_SINCE_VERSION = 1;
  XDG_TOPLEVEL_SET_MIN_SIZE_SINCE_VERSION = 1;
  XDG_TOPLEVEL_SET_MAXIMIZED_SINCE_VERSION = 1;
  XDG_TOPLEVEL_UNSET_MAXIMIZED_SINCE_VERSION = 1;
  XDG_TOPLEVEL_SET_FULLSCREEN_SINCE_VERSION = 1;
  XDG_TOPLEVEL_UNSET_FULLSCREEN_SINCE_VERSION = 1;
  XDG_TOPLEVEL_SET_MINIMIZED_SINCE_VERSION = 1;
  XDG_TOPLEVEL_CONFIGURE_SINCE_VERSION = 1;
  XDG_TOPLEVEL_CLOSE_SINCE_VERSION = 1;
  XDG_TOPLEVEL_CONFIGURE_BOUNDS_SINCE_VERSION = 4;
  XDG_TOPLEVEL_WM_CAPABILITIES_SINCE_VERSION = 5;
  XDG_TOPLEVEL_ERROR_INVALID_RESIZE_EDGE = 0;
  XDG_TOPLEVEL_ERROR_INVALID_PARENT = 1;
  XDG_TOPLEVEL_ERROR_INVALID_SIZE = 2;
  XDG_TOPLEVEL_RESIZE_EDGE_NONE = 0;
  XDG_TOPLEVEL_RESIZE_EDGE_TOP = 1;
  XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM = 2;
  XDG_TOPLEVEL_RESIZE_EDGE_LEFT = 4;
  XDG_TOPLEVEL_RESIZE_EDGE_TOP_LEFT = 5;
  XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_LEFT = 6;
  XDG_TOPLEVEL_RESIZE_EDGE_RIGHT = 8;
  XDG_TOPLEVEL_RESIZE_EDGE_TOP_RIGHT = 9;
  XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_RIGHT = 10;
  XDG_TOPLEVEL_STATE_MAXIMIZED = 1;
  XDG_TOPLEVEL_STATE_FULLSCREEN = 2;
  XDG_TOPLEVEL_STATE_RESIZING = 3;
  XDG_TOPLEVEL_STATE_ACTIVATED = 4;
  XDG_TOPLEVEL_STATE_TILED_LEFT = 5;
  XDG_TOPLEVEL_STATE_TILED_RIGHT = 6;
  XDG_TOPLEVEL_STATE_TILED_TOP = 7;
  XDG_TOPLEVEL_STATE_TILED_BOTTOM = 8;
  XDG_TOPLEVEL_STATE_SUSPENDED = 9;
  XDG_TOPLEVEL_STATE_CONSTRAINED_LEFT = 10;
  XDG_TOPLEVEL_STATE_CONSTRAINED_RIGHT = 11;
  XDG_TOPLEVEL_STATE_CONSTRAINED_TOP = 12;
  XDG_TOPLEVEL_STATE_CONSTRAINED_BOTTOM = 13;
  XDG_TOPLEVEL_WM_CAPABILITIES_WINDOW_MENU = 1;
  XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE = 2;
  XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN = 3;
  XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE = 4;

  // xdg_popup (version 7)
  XDG_POPUP_DESTROY_OPCODE = 0;
  XDG_POPUP_GRAB_OPCODE = 1;
  XDG_POPUP_REPOSITION_OPCODE = 2;
  XDG_POPUP_DESTROY_SINCE_VERSION = 1;
  XDG_POPUP_GRAB_SINCE_VERSION = 1;
  XDG_POPUP_REPOSITION_SINCE_VERSION = 3;
  XDG_POPUP_CONFIGURE_SINCE_VERSION = 1;
  XDG_POPUP_POPUP_DONE_SINCE_VERSION = 1;
  XDG_POPUP_REPOSITIONED_SINCE_VERSION = 3;
  XDG_POPUP_ERROR_INVALID_GRAB = 0;

var
  xdg_wm_base_interface: Pwl_interface = nil;
  xdg_positioner_interface: Pwl_interface = nil;
  xdg_surface_interface: Pwl_interface = nil;
  xdg_toplevel_interface: Pwl_interface = nil;
  xdg_popup_interface: Pwl_interface = nil;

type
  Txdg_wm_base_listener = class abstract(TObject)
  public
    procedure ping(AProxy: Pxdg_wm_base; serial: LongWord); virtual;
  end;

  Txdg_wm_base_listener_rec = record
    ping: procedure(data: Pointer; AProxy: Pxdg_wm_base; serial: LongWord); cdecl;
  end;

  Txdg_surface_listener = class abstract(TObject)
  public
    procedure configure(AProxy: Pxdg_surface; serial: LongWord); virtual;
  end;

  Txdg_surface_listener_rec = record
    configure: procedure(data: Pointer; AProxy: Pxdg_surface; serial: LongWord); cdecl;
  end;

  Txdg_toplevel_listener = class abstract(TObject)
  public
    procedure configure(AProxy: Pxdg_toplevel; width: LongInt; height: LongInt; states: Pwl_array); virtual;
    procedure close(AProxy: Pxdg_toplevel); virtual;
    procedure configure_bounds(AProxy: Pxdg_toplevel; width: LongInt; height: LongInt); virtual;
    procedure wm_capabilities(AProxy: Pxdg_toplevel; capabilities: Pwl_array); virtual;
  end;

  Txdg_toplevel_listener_rec = record
    configure: procedure(data: Pointer; AProxy: Pxdg_toplevel; width: LongInt; height: LongInt; states: Pwl_array); cdecl;
    close: procedure(data: Pointer; AProxy: Pxdg_toplevel); cdecl;
    configure_bounds: procedure(data: Pointer; AProxy: Pxdg_toplevel; width: LongInt; height: LongInt); cdecl;
    wm_capabilities: procedure(data: Pointer; AProxy: Pxdg_toplevel; capabilities: Pwl_array); cdecl;
  end;

  Txdg_popup_listener = class abstract(TObject)
  public
    procedure configure(AProxy: Pxdg_popup; x: LongInt; y: LongInt; width: LongInt; height: LongInt); virtual;
    procedure popup_done(AProxy: Pxdg_popup); virtual;
    procedure repositioned(AProxy: Pxdg_popup; token: LongWord); virtual;
  end;

  Txdg_popup_listener_rec = record
    configure: procedure(data: Pointer; AProxy: Pxdg_popup; x: LongInt; y: LongInt; width: LongInt; height: LongInt); cdecl;
    popup_done: procedure(data: Pointer; AProxy: Pxdg_popup); cdecl;
    repositioned: procedure(data: Pointer; AProxy: Pxdg_popup; token: LongWord); cdecl;
  end;

function xdg_wm_base_add_listener_object(AProxy: Pxdg_wm_base; AListener: Txdg_wm_base_listener): LongInt;
procedure xdg_wm_base_destroy(AProxy: Pxdg_wm_base);
function xdg_wm_base_create_positioner(AProxy: Pxdg_wm_base): Pxdg_positioner;
function xdg_wm_base_get_xdg_surface(AProxy: Pxdg_wm_base; surface: Pwl_surface): Pxdg_surface;
procedure xdg_wm_base_pong(AProxy: Pxdg_wm_base; serial: LongWord);

procedure xdg_positioner_destroy(AProxy: Pxdg_positioner);
procedure xdg_positioner_set_size(AProxy: Pxdg_positioner; width: LongInt; height: LongInt);
procedure xdg_positioner_set_anchor_rect(AProxy: Pxdg_positioner; x: LongInt; y: LongInt; width: LongInt; height: LongInt);
procedure xdg_positioner_set_anchor(AProxy: Pxdg_positioner; anchor: LongWord);
procedure xdg_positioner_set_gravity(AProxy: Pxdg_positioner; gravity: LongWord);
procedure xdg_positioner_set_constraint_adjustment(AProxy: Pxdg_positioner; constraint_adjustment: LongWord);
procedure xdg_positioner_set_offset(AProxy: Pxdg_positioner; x: LongInt; y: LongInt);
procedure xdg_positioner_set_reactive(AProxy: Pxdg_positioner);
procedure xdg_positioner_set_parent_size(AProxy: Pxdg_positioner; parent_width: LongInt; parent_height: LongInt);
procedure xdg_positioner_set_parent_configure(AProxy: Pxdg_positioner; serial: LongWord);

function xdg_surface_add_listener_object(AProxy: Pxdg_surface; AListener: Txdg_surface_listener): LongInt;
procedure xdg_surface_destroy(AProxy: Pxdg_surface);
function xdg_surface_get_toplevel(AProxy: Pxdg_surface): Pxdg_toplevel;
function xdg_surface_get_popup(AProxy: Pxdg_surface; parent: Pxdg_surface; positioner: Pxdg_positioner): Pxdg_popup;
procedure xdg_surface_set_window_geometry(AProxy: Pxdg_surface; x: LongInt; y: LongInt; width: LongInt; height: LongInt);
procedure xdg_surface_ack_configure(AProxy: Pxdg_surface; serial: LongWord);

function xdg_toplevel_add_listener_object(AProxy: Pxdg_toplevel; AListener: Txdg_toplevel_listener): LongInt;
procedure xdg_toplevel_destroy(AProxy: Pxdg_toplevel);
procedure xdg_toplevel_set_parent(AProxy: Pxdg_toplevel; parent: Pxdg_toplevel);
procedure xdg_toplevel_set_title(AProxy: Pxdg_toplevel; title: PAnsiChar);
procedure xdg_toplevel_set_app_id(AProxy: Pxdg_toplevel; app_id: PAnsiChar);
procedure xdg_toplevel_show_window_menu(AProxy: Pxdg_toplevel; seat: Pwl_seat; serial: LongWord; x: LongInt; y: LongInt);
procedure xdg_toplevel_move(AProxy: Pxdg_toplevel; seat: Pwl_seat; serial: LongWord);
procedure xdg_toplevel_resize(AProxy: Pxdg_toplevel; seat: Pwl_seat; serial: LongWord; edges: LongWord);
procedure xdg_toplevel_set_max_size(AProxy: Pxdg_toplevel; width: LongInt; height: LongInt);
procedure xdg_toplevel_set_min_size(AProxy: Pxdg_toplevel; width: LongInt; height: LongInt);
procedure xdg_toplevel_set_maximized(AProxy: Pxdg_toplevel);
procedure xdg_toplevel_unset_maximized(AProxy: Pxdg_toplevel);
procedure xdg_toplevel_set_fullscreen(AProxy: Pxdg_toplevel; output: Pwl_output);
procedure xdg_toplevel_unset_fullscreen(AProxy: Pxdg_toplevel);
procedure xdg_toplevel_set_minimized(AProxy: Pxdg_toplevel);

function xdg_popup_add_listener_object(AProxy: Pxdg_popup; AListener: Txdg_popup_listener): LongInt;
procedure xdg_popup_destroy(AProxy: Pxdg_popup);
procedure xdg_popup_grab(AProxy: Pxdg_popup; seat: Pwl_seat; serial: LongWord);
procedure xdg_popup_reposition(AProxy: Pxdg_popup; positioner: Pxdg_positioner; token: LongWord);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..25] of Pwl_interface;
  GReq_xdg_wm_base: array[0..3] of Twl_message;
  GEvt_xdg_wm_base: array[0..0] of Twl_message;
  GIface_xdg_wm_base: Twl_interface;
  GReq_xdg_positioner: array[0..9] of Twl_message;
  GIface_xdg_positioner: Twl_interface;
  GReq_xdg_surface: array[0..4] of Twl_message;
  GEvt_xdg_surface: array[0..0] of Twl_message;
  GIface_xdg_surface: Twl_interface;
  GReq_xdg_toplevel: array[0..13] of Twl_message;
  GEvt_xdg_toplevel: array[0..3] of Twl_message;
  GIface_xdg_toplevel: Twl_interface;
  GReq_xdg_popup: array[0..2] of Twl_message;
  GEvt_xdg_popup: array[0..2] of Twl_message;
  GIface_xdg_popup: Twl_interface;

var
  GInitialized: Boolean = False;
  GThunks_xdg_wm_base: Txdg_wm_base_listener_rec;
  GThunks_xdg_surface: Txdg_surface_listener_rec;
  GThunks_xdg_toplevel: Txdg_toplevel_listener_rec;
  GThunks_xdg_popup: Txdg_popup_listener_rec;

procedure Txdg_wm_base_listener.ping(AProxy: Pxdg_wm_base; serial: LongWord);
begin
end;

procedure Txdg_surface_listener.configure(AProxy: Pxdg_surface; serial: LongWord);
begin
end;

procedure Txdg_toplevel_listener.configure(AProxy: Pxdg_toplevel; width: LongInt; height: LongInt; states: Pwl_array);
begin
end;

procedure Txdg_toplevel_listener.close(AProxy: Pxdg_toplevel);
begin
end;

procedure Txdg_toplevel_listener.configure_bounds(AProxy: Pxdg_toplevel; width: LongInt; height: LongInt);
begin
end;

procedure Txdg_toplevel_listener.wm_capabilities(AProxy: Pxdg_toplevel; capabilities: Pwl_array);
begin
end;

procedure Txdg_popup_listener.configure(AProxy: Pxdg_popup; x: LongInt; y: LongInt; width: LongInt; height: LongInt);
begin
end;

procedure Txdg_popup_listener.popup_done(AProxy: Pxdg_popup);
begin
end;

procedure Txdg_popup_listener.repositioned(AProxy: Pxdg_popup; token: LongWord);
begin
end;

procedure Thunk_xdg_wm_base_ping(data: Pointer; AProxy: Pxdg_wm_base; serial: LongWord); cdecl;
begin
  if data <> nil then
    Txdg_wm_base_listener(data).ping(AProxy, serial);
end;

procedure Thunk_xdg_surface_configure(data: Pointer; AProxy: Pxdg_surface; serial: LongWord); cdecl;
begin
  if data <> nil then
    Txdg_surface_listener(data).configure(AProxy, serial);
end;

procedure Thunk_xdg_toplevel_configure(data: Pointer; AProxy: Pxdg_toplevel; width: LongInt; height: LongInt; states: Pwl_array); cdecl;
begin
  if data <> nil then
    Txdg_toplevel_listener(data).configure(AProxy, width, height, states);
end;

procedure Thunk_xdg_toplevel_close(data: Pointer; AProxy: Pxdg_toplevel); cdecl;
begin
  if data <> nil then
    Txdg_toplevel_listener(data).close(AProxy);
end;

procedure Thunk_xdg_toplevel_configure_bounds(data: Pointer; AProxy: Pxdg_toplevel; width: LongInt; height: LongInt); cdecl;
begin
  if data <> nil then
    Txdg_toplevel_listener(data).configure_bounds(AProxy, width, height);
end;

procedure Thunk_xdg_toplevel_wm_capabilities(data: Pointer; AProxy: Pxdg_toplevel; capabilities: Pwl_array); cdecl;
begin
  if data <> nil then
    Txdg_toplevel_listener(data).wm_capabilities(AProxy, capabilities);
end;

procedure Thunk_xdg_popup_configure(data: Pointer; AProxy: Pxdg_popup; x: LongInt; y: LongInt; width: LongInt; height: LongInt); cdecl;
begin
  if data <> nil then
    Txdg_popup_listener(data).configure(AProxy, x, y, width, height);
end;

procedure Thunk_xdg_popup_popup_done(data: Pointer; AProxy: Pxdg_popup); cdecl;
begin
  if data <> nil then
    Txdg_popup_listener(data).popup_done(AProxy);
end;

procedure Thunk_xdg_popup_repositioned(data: Pointer; AProxy: Pxdg_popup; token: LongWord); cdecl;
begin
  if data <> nil then
    Txdg_popup_listener(data).repositioned(AProxy, token);
end;

function xdg_wm_base_add_listener_object(AProxy: Pxdg_wm_base; AListener: Txdg_wm_base_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_xdg_wm_base, AListener);
end;

function xdg_surface_add_listener_object(AProxy: Pxdg_surface; AListener: Txdg_surface_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_xdg_surface, AListener);
end;

function xdg_toplevel_add_listener_object(AProxy: Pxdg_toplevel; AListener: Txdg_toplevel_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_xdg_toplevel, AListener);
end;

function xdg_popup_add_listener_object(AProxy: Pxdg_popup; AListener: Txdg_popup_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_xdg_popup, AListener);
end;

procedure xdg_wm_base_destroy(AProxy: Pxdg_wm_base);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_WM_BASE_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function xdg_wm_base_create_positioner(AProxy: Pxdg_wm_base): Pxdg_positioner;
begin
  EnsureProtocolInitialized;
  Result := Pxdg_positioner(wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_WM_BASE_CREATE_POSITIONER_OPCODE, xdg_positioner_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function xdg_wm_base_get_xdg_surface(AProxy: Pxdg_wm_base; surface: Pwl_surface): Pxdg_surface;
begin
  EnsureProtocolInitialized;
  Result := Pxdg_surface(wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_WM_BASE_GET_XDG_SURFACE_OPCODE, xdg_surface_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), surface));
end;

procedure xdg_wm_base_pong(AProxy: Pxdg_wm_base; serial: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_WM_BASE_PONG_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, serial);
end;

procedure xdg_positioner_destroy(AProxy: Pxdg_positioner);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_POSITIONER_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure xdg_positioner_set_size(AProxy: Pxdg_positioner; width: LongInt; height: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_POSITIONER_SET_SIZE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, width, height);
end;

procedure xdg_positioner_set_anchor_rect(AProxy: Pxdg_positioner; x: LongInt; y: LongInt; width: LongInt; height: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_POSITIONER_SET_ANCHOR_RECT_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, x, y, width, height);
end;

procedure xdg_positioner_set_anchor(AProxy: Pxdg_positioner; anchor: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_POSITIONER_SET_ANCHOR_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, anchor);
end;

procedure xdg_positioner_set_gravity(AProxy: Pxdg_positioner; gravity: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_POSITIONER_SET_GRAVITY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, gravity);
end;

procedure xdg_positioner_set_constraint_adjustment(AProxy: Pxdg_positioner; constraint_adjustment: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_POSITIONER_SET_CONSTRAINT_ADJUSTMENT_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, constraint_adjustment);
end;

procedure xdg_positioner_set_offset(AProxy: Pxdg_positioner; x: LongInt; y: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_POSITIONER_SET_OFFSET_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, x, y);
end;

procedure xdg_positioner_set_reactive(AProxy: Pxdg_positioner);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_POSITIONER_SET_REACTIVE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure xdg_positioner_set_parent_size(AProxy: Pxdg_positioner; parent_width: LongInt; parent_height: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_POSITIONER_SET_PARENT_SIZE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, parent_width, parent_height);
end;

procedure xdg_positioner_set_parent_configure(AProxy: Pxdg_positioner; serial: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_POSITIONER_SET_PARENT_CONFIGURE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, serial);
end;

procedure xdg_surface_destroy(AProxy: Pxdg_surface);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_SURFACE_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function xdg_surface_get_toplevel(AProxy: Pxdg_surface): Pxdg_toplevel;
begin
  EnsureProtocolInitialized;
  Result := Pxdg_toplevel(wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_SURFACE_GET_TOPLEVEL_OPCODE, xdg_toplevel_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function xdg_surface_get_popup(AProxy: Pxdg_surface; parent: Pxdg_surface; positioner: Pxdg_positioner): Pxdg_popup;
begin
  EnsureProtocolInitialized;
  Result := Pxdg_popup(wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_SURFACE_GET_POPUP_OPCODE, xdg_popup_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), parent, positioner));
end;

procedure xdg_surface_set_window_geometry(AProxy: Pxdg_surface; x: LongInt; y: LongInt; width: LongInt; height: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_SURFACE_SET_WINDOW_GEOMETRY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, x, y, width, height);
end;

procedure xdg_surface_ack_configure(AProxy: Pxdg_surface; serial: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_SURFACE_ACK_CONFIGURE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, serial);
end;

procedure xdg_toplevel_destroy(AProxy: Pxdg_toplevel);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure xdg_toplevel_set_parent(AProxy: Pxdg_toplevel; parent: Pxdg_toplevel);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_SET_PARENT_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, parent);
end;

procedure xdg_toplevel_set_title(AProxy: Pxdg_toplevel; title: PAnsiChar);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_SET_TITLE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, title);
end;

procedure xdg_toplevel_set_app_id(AProxy: Pxdg_toplevel; app_id: PAnsiChar);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_SET_APP_ID_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, app_id);
end;

procedure xdg_toplevel_show_window_menu(AProxy: Pxdg_toplevel; seat: Pwl_seat; serial: LongWord; x: LongInt; y: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_SHOW_WINDOW_MENU_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, seat, serial, x, y);
end;

procedure xdg_toplevel_move(AProxy: Pxdg_toplevel; seat: Pwl_seat; serial: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_MOVE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, seat, serial);
end;

procedure xdg_toplevel_resize(AProxy: Pxdg_toplevel; seat: Pwl_seat; serial: LongWord; edges: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_RESIZE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, seat, serial, edges);
end;

procedure xdg_toplevel_set_max_size(AProxy: Pxdg_toplevel; width: LongInt; height: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_SET_MAX_SIZE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, width, height);
end;

procedure xdg_toplevel_set_min_size(AProxy: Pxdg_toplevel; width: LongInt; height: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_SET_MIN_SIZE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, width, height);
end;

procedure xdg_toplevel_set_maximized(AProxy: Pxdg_toplevel);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_SET_MAXIMIZED_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure xdg_toplevel_unset_maximized(AProxy: Pxdg_toplevel);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_UNSET_MAXIMIZED_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure xdg_toplevel_set_fullscreen(AProxy: Pxdg_toplevel; output: Pwl_output);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_SET_FULLSCREEN_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, output);
end;

procedure xdg_toplevel_unset_fullscreen(AProxy: Pxdg_toplevel);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_UNSET_FULLSCREEN_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure xdg_toplevel_set_minimized(AProxy: Pxdg_toplevel);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_SET_MINIMIZED_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure xdg_popup_destroy(AProxy: Pxdg_popup);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_POPUP_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure xdg_popup_grab(AProxy: Pxdg_popup; seat: Pwl_seat; serial: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_POPUP_GRAB_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, seat, serial);
end;

procedure xdg_popup_reposition(AProxy: Pxdg_popup; positioner: Pxdg_positioner; token: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_POPUP_REPOSITION_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, positioner, token);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;

  xdg_wm_base_interface := @GIface_xdg_wm_base;
  xdg_positioner_interface := @GIface_xdg_positioner;
  xdg_surface_interface := @GIface_xdg_surface;
  xdg_toplevel_interface := @GIface_xdg_toplevel;
  xdg_popup_interface := @GIface_xdg_popup;
  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[4] := xdg_positioner_interface;
  GTypes[5] := xdg_surface_interface;
  GTypes[6] := wl_surface_interface;
  GTypes[7] := xdg_toplevel_interface;
  GTypes[8] := xdg_popup_interface;
  GTypes[9] := xdg_surface_interface;
  GTypes[10] := xdg_positioner_interface;
  GTypes[11] := xdg_toplevel_interface;
  GTypes[12] := wl_seat_interface;
  GTypes[16] := wl_seat_interface;
  GTypes[18] := wl_seat_interface;
  GTypes[21] := wl_output_interface;
  GTypes[22] := wl_seat_interface;
  GTypes[24] := xdg_positioner_interface;

  GReq_xdg_wm_base[0].name := 'destroy';
  GReq_xdg_wm_base[0].signature := '';
  GReq_xdg_wm_base[0].types := @GTypes[0];
  GReq_xdg_wm_base[1].name := 'create_positioner';
  GReq_xdg_wm_base[1].signature := 'n';
  GReq_xdg_wm_base[1].types := @GTypes[4];
  GReq_xdg_wm_base[2].name := 'get_xdg_surface';
  GReq_xdg_wm_base[2].signature := 'no';
  GReq_xdg_wm_base[2].types := @GTypes[5];
  GReq_xdg_wm_base[3].name := 'pong';
  GReq_xdg_wm_base[3].signature := 'u';
  GReq_xdg_wm_base[3].types := @GTypes[0];
  GEvt_xdg_wm_base[0].name := 'ping';
  GEvt_xdg_wm_base[0].signature := 'u';
  GEvt_xdg_wm_base[0].types := @GTypes[0];
  GIface_xdg_wm_base.name := 'xdg_wm_base';
  GIface_xdg_wm_base.version := 7;
  GIface_xdg_wm_base.method_count := 4;
  GIface_xdg_wm_base.methods := @GReq_xdg_wm_base[0];
  GIface_xdg_wm_base.event_count := 1;
  GIface_xdg_wm_base.events := @GEvt_xdg_wm_base[0];

  GReq_xdg_positioner[0].name := 'destroy';
  GReq_xdg_positioner[0].signature := '';
  GReq_xdg_positioner[0].types := @GTypes[0];
  GReq_xdg_positioner[1].name := 'set_size';
  GReq_xdg_positioner[1].signature := 'ii';
  GReq_xdg_positioner[1].types := @GTypes[0];
  GReq_xdg_positioner[2].name := 'set_anchor_rect';
  GReq_xdg_positioner[2].signature := 'iiii';
  GReq_xdg_positioner[2].types := @GTypes[0];
  GReq_xdg_positioner[3].name := 'set_anchor';
  GReq_xdg_positioner[3].signature := 'u';
  GReq_xdg_positioner[3].types := @GTypes[0];
  GReq_xdg_positioner[4].name := 'set_gravity';
  GReq_xdg_positioner[4].signature := 'u';
  GReq_xdg_positioner[4].types := @GTypes[0];
  GReq_xdg_positioner[5].name := 'set_constraint_adjustment';
  GReq_xdg_positioner[5].signature := 'u';
  GReq_xdg_positioner[5].types := @GTypes[0];
  GReq_xdg_positioner[6].name := 'set_offset';
  GReq_xdg_positioner[6].signature := 'ii';
  GReq_xdg_positioner[6].types := @GTypes[0];
  GReq_xdg_positioner[7].name := 'set_reactive';
  GReq_xdg_positioner[7].signature := '3';
  GReq_xdg_positioner[7].types := @GTypes[0];
  GReq_xdg_positioner[8].name := 'set_parent_size';
  GReq_xdg_positioner[8].signature := '3ii';
  GReq_xdg_positioner[8].types := @GTypes[0];
  GReq_xdg_positioner[9].name := 'set_parent_configure';
  GReq_xdg_positioner[9].signature := '3u';
  GReq_xdg_positioner[9].types := @GTypes[0];
  GIface_xdg_positioner.name := 'xdg_positioner';
  GIface_xdg_positioner.version := 7;
  GIface_xdg_positioner.method_count := 10;
  GIface_xdg_positioner.methods := @GReq_xdg_positioner[0];
  GIface_xdg_positioner.event_count := 0;
  GIface_xdg_positioner.events := nil;

  GReq_xdg_surface[0].name := 'destroy';
  GReq_xdg_surface[0].signature := '';
  GReq_xdg_surface[0].types := @GTypes[0];
  GReq_xdg_surface[1].name := 'get_toplevel';
  GReq_xdg_surface[1].signature := 'n';
  GReq_xdg_surface[1].types := @GTypes[7];
  GReq_xdg_surface[2].name := 'get_popup';
  GReq_xdg_surface[2].signature := 'n?oo';
  GReq_xdg_surface[2].types := @GTypes[8];
  GReq_xdg_surface[3].name := 'set_window_geometry';
  GReq_xdg_surface[3].signature := 'iiii';
  GReq_xdg_surface[3].types := @GTypes[0];
  GReq_xdg_surface[4].name := 'ack_configure';
  GReq_xdg_surface[4].signature := 'u';
  GReq_xdg_surface[4].types := @GTypes[0];
  GEvt_xdg_surface[0].name := 'configure';
  GEvt_xdg_surface[0].signature := 'u';
  GEvt_xdg_surface[0].types := @GTypes[0];
  GIface_xdg_surface.name := 'xdg_surface';
  GIface_xdg_surface.version := 7;
  GIface_xdg_surface.method_count := 5;
  GIface_xdg_surface.methods := @GReq_xdg_surface[0];
  GIface_xdg_surface.event_count := 1;
  GIface_xdg_surface.events := @GEvt_xdg_surface[0];

  GReq_xdg_toplevel[0].name := 'destroy';
  GReq_xdg_toplevel[0].signature := '';
  GReq_xdg_toplevel[0].types := @GTypes[0];
  GReq_xdg_toplevel[1].name := 'set_parent';
  GReq_xdg_toplevel[1].signature := '?o';
  GReq_xdg_toplevel[1].types := @GTypes[11];
  GReq_xdg_toplevel[2].name := 'set_title';
  GReq_xdg_toplevel[2].signature := 's';
  GReq_xdg_toplevel[2].types := @GTypes[0];
  GReq_xdg_toplevel[3].name := 'set_app_id';
  GReq_xdg_toplevel[3].signature := 's';
  GReq_xdg_toplevel[3].types := @GTypes[0];
  GReq_xdg_toplevel[4].name := 'show_window_menu';
  GReq_xdg_toplevel[4].signature := 'ouii';
  GReq_xdg_toplevel[4].types := @GTypes[12];
  GReq_xdg_toplevel[5].name := 'move';
  GReq_xdg_toplevel[5].signature := 'ou';
  GReq_xdg_toplevel[5].types := @GTypes[16];
  GReq_xdg_toplevel[6].name := 'resize';
  GReq_xdg_toplevel[6].signature := 'ouu';
  GReq_xdg_toplevel[6].types := @GTypes[18];
  GReq_xdg_toplevel[7].name := 'set_max_size';
  GReq_xdg_toplevel[7].signature := 'ii';
  GReq_xdg_toplevel[7].types := @GTypes[0];
  GReq_xdg_toplevel[8].name := 'set_min_size';
  GReq_xdg_toplevel[8].signature := 'ii';
  GReq_xdg_toplevel[8].types := @GTypes[0];
  GReq_xdg_toplevel[9].name := 'set_maximized';
  GReq_xdg_toplevel[9].signature := '';
  GReq_xdg_toplevel[9].types := @GTypes[0];
  GReq_xdg_toplevel[10].name := 'unset_maximized';
  GReq_xdg_toplevel[10].signature := '';
  GReq_xdg_toplevel[10].types := @GTypes[0];
  GReq_xdg_toplevel[11].name := 'set_fullscreen';
  GReq_xdg_toplevel[11].signature := '?o';
  GReq_xdg_toplevel[11].types := @GTypes[21];
  GReq_xdg_toplevel[12].name := 'unset_fullscreen';
  GReq_xdg_toplevel[12].signature := '';
  GReq_xdg_toplevel[12].types := @GTypes[0];
  GReq_xdg_toplevel[13].name := 'set_minimized';
  GReq_xdg_toplevel[13].signature := '';
  GReq_xdg_toplevel[13].types := @GTypes[0];
  GEvt_xdg_toplevel[0].name := 'configure';
  GEvt_xdg_toplevel[0].signature := 'iia';
  GEvt_xdg_toplevel[0].types := @GTypes[0];
  GEvt_xdg_toplevel[1].name := 'close';
  GEvt_xdg_toplevel[1].signature := '';
  GEvt_xdg_toplevel[1].types := @GTypes[0];
  GEvt_xdg_toplevel[2].name := 'configure_bounds';
  GEvt_xdg_toplevel[2].signature := '4ii';
  GEvt_xdg_toplevel[2].types := @GTypes[0];
  GEvt_xdg_toplevel[3].name := 'wm_capabilities';
  GEvt_xdg_toplevel[3].signature := '5a';
  GEvt_xdg_toplevel[3].types := @GTypes[0];
  GIface_xdg_toplevel.name := 'xdg_toplevel';
  GIface_xdg_toplevel.version := 7;
  GIface_xdg_toplevel.method_count := 14;
  GIface_xdg_toplevel.methods := @GReq_xdg_toplevel[0];
  GIface_xdg_toplevel.event_count := 4;
  GIface_xdg_toplevel.events := @GEvt_xdg_toplevel[0];

  GReq_xdg_popup[0].name := 'destroy';
  GReq_xdg_popup[0].signature := '';
  GReq_xdg_popup[0].types := @GTypes[0];
  GReq_xdg_popup[1].name := 'grab';
  GReq_xdg_popup[1].signature := 'ou';
  GReq_xdg_popup[1].types := @GTypes[22];
  GReq_xdg_popup[2].name := 'reposition';
  GReq_xdg_popup[2].signature := '3ou';
  GReq_xdg_popup[2].types := @GTypes[24];
  GEvt_xdg_popup[0].name := 'configure';
  GEvt_xdg_popup[0].signature := 'iiii';
  GEvt_xdg_popup[0].types := @GTypes[0];
  GEvt_xdg_popup[1].name := 'popup_done';
  GEvt_xdg_popup[1].signature := '';
  GEvt_xdg_popup[1].types := @GTypes[0];
  GEvt_xdg_popup[2].name := 'repositioned';
  GEvt_xdg_popup[2].signature := '3u';
  GEvt_xdg_popup[2].types := @GTypes[0];
  GIface_xdg_popup.name := 'xdg_popup';
  GIface_xdg_popup.version := 7;
  GIface_xdg_popup.method_count := 3;
  GIface_xdg_popup.methods := @GReq_xdg_popup[0];
  GIface_xdg_popup.event_count := 3;
  GIface_xdg_popup.events := @GEvt_xdg_popup[0];

  GThunks_xdg_wm_base.ping := @Thunk_xdg_wm_base_ping;
  GThunks_xdg_surface.configure := @Thunk_xdg_surface_configure;
  GThunks_xdg_toplevel.configure := @Thunk_xdg_toplevel_configure;
  GThunks_xdg_toplevel.close := @Thunk_xdg_toplevel_close;
  GThunks_xdg_toplevel.configure_bounds := @Thunk_xdg_toplevel_configure_bounds;
  GThunks_xdg_toplevel.wm_capabilities := @Thunk_xdg_toplevel_wm_capabilities;
  GThunks_xdg_popup.configure := @Thunk_xdg_popup_configure;
  GThunks_xdg_popup.popup_done := @Thunk_xdg_popup_popup_done;
  GThunks_xdg_popup.repositioned := @Thunk_xdg_popup_repositioned;
end;

end.
