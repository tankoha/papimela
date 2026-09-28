{
  PaPiMeLa.Platform.Wayland.Protocols.CursorShapeV1

  自動生成ファイル。手で編集しないこと。
  生成元: cursor_shape_v1.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright 2018 The Chromium Authors
      Copyright 2023 Simon Ser
  
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
      FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
      THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
      LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
      FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
      DEALINGS IN THE SOFTWARE.

}
unit PaPiMeLa.Platform.Wayland.Protocols.CursorShapeV1;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland,
  PaPiMeLa.Platform.Wayland.Protocols.TabletV2;

type
  Twp_cursor_shape_manager_v1_opaque = record end;
  Pwp_cursor_shape_manager_v1 = ^Twp_cursor_shape_manager_v1_opaque;
  Twp_cursor_shape_device_v1_opaque = record end;
  Pwp_cursor_shape_device_v1 = ^Twp_cursor_shape_device_v1_opaque;

const
  // wp_cursor_shape_manager_v1 (version 2)
  WP_CURSOR_SHAPE_MANAGER_V1_DESTROY_OPCODE = 0;
  WP_CURSOR_SHAPE_MANAGER_V1_GET_POINTER_OPCODE = 1;
  WP_CURSOR_SHAPE_MANAGER_V1_GET_TABLET_TOOL_V2_OPCODE = 2;
  WP_CURSOR_SHAPE_MANAGER_V1_DESTROY_SINCE_VERSION = 1;
  WP_CURSOR_SHAPE_MANAGER_V1_GET_POINTER_SINCE_VERSION = 1;
  WP_CURSOR_SHAPE_MANAGER_V1_GET_TABLET_TOOL_V2_SINCE_VERSION = 1;

  // wp_cursor_shape_device_v1 (version 2)
  WP_CURSOR_SHAPE_DEVICE_V1_DESTROY_OPCODE = 0;
  WP_CURSOR_SHAPE_DEVICE_V1_SET_SHAPE_OPCODE = 1;
  WP_CURSOR_SHAPE_DEVICE_V1_DESTROY_SINCE_VERSION = 1;
  WP_CURSOR_SHAPE_DEVICE_V1_SET_SHAPE_SINCE_VERSION = 1;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_DEFAULT = 1;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_CONTEXT_MENU = 2;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_HELP = 3;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER = 4;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_PROGRESS = 5;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_WAIT = 6;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_CELL = 7;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_CROSSHAIR = 8;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_TEXT = 9;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_VERTICAL_TEXT = 10;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_ALIAS = 11;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_COPY = 12;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_MOVE = 13;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NO_DROP = 14;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NOT_ALLOWED = 15;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_GRAB = 16;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_GRABBING = 17;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_E_RESIZE = 18;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_N_RESIZE = 19;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NE_RESIZE = 20;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NW_RESIZE = 21;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_S_RESIZE = 22;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_SE_RESIZE = 23;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_SW_RESIZE = 24;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_W_RESIZE = 25;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_EW_RESIZE = 26;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NS_RESIZE = 27;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NESW_RESIZE = 28;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NWSE_RESIZE = 29;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_COL_RESIZE = 30;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_ROW_RESIZE = 31;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_ALL_SCROLL = 32;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_ZOOM_IN = 33;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_ZOOM_OUT = 34;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_DND_ASK = 35;
  WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_ALL_RESIZE = 36;
  WP_CURSOR_SHAPE_DEVICE_V1_ERROR_INVALID_SHAPE = 1;

var
  wp_cursor_shape_manager_v1_interface: Pwl_interface = nil;
  wp_cursor_shape_device_v1_interface: Pwl_interface = nil;

procedure wp_cursor_shape_manager_v1_destroy(AProxy: Pwp_cursor_shape_manager_v1);
function wp_cursor_shape_manager_v1_get_pointer(AProxy: Pwp_cursor_shape_manager_v1; pointer_: Pwl_pointer): Pwp_cursor_shape_device_v1;
function wp_cursor_shape_manager_v1_get_tablet_tool_v2(AProxy: Pwp_cursor_shape_manager_v1; tablet_tool: Pzwp_tablet_tool_v2): Pwp_cursor_shape_device_v1;

procedure wp_cursor_shape_device_v1_destroy(AProxy: Pwp_cursor_shape_device_v1);
procedure wp_cursor_shape_device_v1_set_shape(AProxy: Pwp_cursor_shape_device_v1; serial: LongWord; shape: LongWord);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..5] of Pwl_interface;
  GReq_wp_cursor_shape_manager_v1: array[0..2] of Twl_message;
  GIface_wp_cursor_shape_manager_v1: Twl_interface;
  GReq_wp_cursor_shape_device_v1: array[0..1] of Twl_message;
  GIface_wp_cursor_shape_device_v1: Twl_interface;

var
  GInitialized: Boolean = False;

procedure wp_cursor_shape_manager_v1_destroy(AProxy: Pwp_cursor_shape_manager_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_CURSOR_SHAPE_MANAGER_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function wp_cursor_shape_manager_v1_get_pointer(AProxy: Pwp_cursor_shape_manager_v1; pointer_: Pwl_pointer): Pwp_cursor_shape_device_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_cursor_shape_device_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_CURSOR_SHAPE_MANAGER_V1_GET_POINTER_OPCODE, wp_cursor_shape_device_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), pointer_));
end;

function wp_cursor_shape_manager_v1_get_tablet_tool_v2(AProxy: Pwp_cursor_shape_manager_v1; tablet_tool: Pzwp_tablet_tool_v2): Pwp_cursor_shape_device_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_cursor_shape_device_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_CURSOR_SHAPE_MANAGER_V1_GET_TABLET_TOOL_V2_OPCODE, wp_cursor_shape_device_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), tablet_tool));
end;

procedure wp_cursor_shape_device_v1_destroy(AProxy: Pwp_cursor_shape_device_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_CURSOR_SHAPE_DEVICE_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wp_cursor_shape_device_v1_set_shape(AProxy: Pwp_cursor_shape_device_v1; serial: LongWord; shape: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_CURSOR_SHAPE_DEVICE_V1_SET_SHAPE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, serial, shape);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.TabletV2.EnsureProtocolInitialized;

  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[2] := wp_cursor_shape_device_v1_interface;
  GTypes[3] := wl_pointer_interface;
  GTypes[4] := wp_cursor_shape_device_v1_interface;
  GTypes[5] := zwp_tablet_tool_v2_interface;

  GReq_wp_cursor_shape_manager_v1[0].name := 'destroy';
  GReq_wp_cursor_shape_manager_v1[0].signature := '';
  GReq_wp_cursor_shape_manager_v1[0].types := @GTypes[0];
  GReq_wp_cursor_shape_manager_v1[1].name := 'get_pointer';
  GReq_wp_cursor_shape_manager_v1[1].signature := 'no';
  GReq_wp_cursor_shape_manager_v1[1].types := @GTypes[2];
  GReq_wp_cursor_shape_manager_v1[2].name := 'get_tablet_tool_v2';
  GReq_wp_cursor_shape_manager_v1[2].signature := 'no';
  GReq_wp_cursor_shape_manager_v1[2].types := @GTypes[4];
  GIface_wp_cursor_shape_manager_v1.name := 'wp_cursor_shape_manager_v1';
  GIface_wp_cursor_shape_manager_v1.version := 2;
  GIface_wp_cursor_shape_manager_v1.method_count := 3;
  GIface_wp_cursor_shape_manager_v1.methods := @GReq_wp_cursor_shape_manager_v1[0];
  GIface_wp_cursor_shape_manager_v1.event_count := 0;
  GIface_wp_cursor_shape_manager_v1.events := nil;
  wp_cursor_shape_manager_v1_interface := @GIface_wp_cursor_shape_manager_v1;

  GReq_wp_cursor_shape_device_v1[0].name := 'destroy';
  GReq_wp_cursor_shape_device_v1[0].signature := '';
  GReq_wp_cursor_shape_device_v1[0].types := @GTypes[0];
  GReq_wp_cursor_shape_device_v1[1].name := 'set_shape';
  GReq_wp_cursor_shape_device_v1[1].signature := 'uu';
  GReq_wp_cursor_shape_device_v1[1].types := @GTypes[0];
  GIface_wp_cursor_shape_device_v1.name := 'wp_cursor_shape_device_v1';
  GIface_wp_cursor_shape_device_v1.version := 2;
  GIface_wp_cursor_shape_device_v1.method_count := 2;
  GIface_wp_cursor_shape_device_v1.methods := @GReq_wp_cursor_shape_device_v1[0];
  GIface_wp_cursor_shape_device_v1.event_count := 0;
  GIface_wp_cursor_shape_device_v1.events := nil;
  wp_cursor_shape_device_v1_interface := @GIface_wp_cursor_shape_device_v1;

end;

end.
