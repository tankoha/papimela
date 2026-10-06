{
  PaPiMeLa.Platform.Wayland.Protocols.Viewporter

  自動生成ファイル。手で編集しないこと。
  生成元: viewporter.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright � 2013-2016 Collabora, Ltd.
  
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
unit PaPiMeLa.Platform.Wayland.Protocols.Viewporter;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  Twp_viewporter_opaque = record end;
  Pwp_viewporter = ^Twp_viewporter_opaque;
  Twp_viewport_opaque = record end;
  Pwp_viewport = ^Twp_viewport_opaque;

const
  // wp_viewporter (version 1)
  WP_VIEWPORTER_DESTROY_OPCODE = 0;
  WP_VIEWPORTER_GET_VIEWPORT_OPCODE = 1;
  WP_VIEWPORTER_DESTROY_SINCE_VERSION = 1;
  WP_VIEWPORTER_GET_VIEWPORT_SINCE_VERSION = 1;
  WP_VIEWPORTER_ERROR_VIEWPORT_EXISTS = 0;

  // wp_viewport (version 1)
  WP_VIEWPORT_DESTROY_OPCODE = 0;
  WP_VIEWPORT_SET_SOURCE_OPCODE = 1;
  WP_VIEWPORT_SET_DESTINATION_OPCODE = 2;
  WP_VIEWPORT_DESTROY_SINCE_VERSION = 1;
  WP_VIEWPORT_SET_SOURCE_SINCE_VERSION = 1;
  WP_VIEWPORT_SET_DESTINATION_SINCE_VERSION = 1;
  WP_VIEWPORT_ERROR_BAD_VALUE = 0;
  WP_VIEWPORT_ERROR_BAD_SIZE = 1;
  WP_VIEWPORT_ERROR_OUT_OF_BUFFER = 2;
  WP_VIEWPORT_ERROR_NO_SURFACE = 3;

var
  wp_viewporter_interface: Pwl_interface = nil;
  wp_viewport_interface: Pwl_interface = nil;

procedure wp_viewporter_destroy(AProxy: Pwp_viewporter);
function wp_viewporter_get_viewport(AProxy: Pwp_viewporter; surface: Pwl_surface): Pwp_viewport;

procedure wp_viewport_destroy(AProxy: Pwp_viewport);
procedure wp_viewport_set_source(AProxy: Pwp_viewport; x: wl_fixed_t; y: wl_fixed_t; width: wl_fixed_t; height: wl_fixed_t);
procedure wp_viewport_set_destination(AProxy: Pwp_viewport; width: LongInt; height: LongInt);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..5] of Pwl_interface;
  GReq_wp_viewporter: array[0..1] of Twl_message;
  GIface_wp_viewporter: Twl_interface;
  GReq_wp_viewport: array[0..2] of Twl_message;
  GIface_wp_viewport: Twl_interface;

var
  GInitialized: Boolean = False;

procedure wp_viewporter_destroy(AProxy: Pwp_viewporter);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_VIEWPORTER_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function wp_viewporter_get_viewport(AProxy: Pwp_viewporter; surface: Pwl_surface): Pwp_viewport;
begin
  EnsureProtocolInitialized;
  Result := Pwp_viewport(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_VIEWPORTER_GET_VIEWPORT_OPCODE, wp_viewport_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), surface));
end;

procedure wp_viewport_destroy(AProxy: Pwp_viewport);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_VIEWPORT_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wp_viewport_set_source(AProxy: Pwp_viewport; x: wl_fixed_t; y: wl_fixed_t; width: wl_fixed_t; height: wl_fixed_t);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_VIEWPORT_SET_SOURCE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, x, y, width, height);
end;

procedure wp_viewport_set_destination(AProxy: Pwp_viewport; width: LongInt; height: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_VIEWPORT_SET_DESTINATION_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, width, height);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;

  wp_viewporter_interface := @GIface_wp_viewporter;
  wp_viewport_interface := @GIface_wp_viewport;
  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[4] := wp_viewport_interface;
  GTypes[5] := wl_surface_interface;

  GReq_wp_viewporter[0].name := 'destroy';
  GReq_wp_viewporter[0].signature := '';
  GReq_wp_viewporter[0].types := @GTypes[0];
  GReq_wp_viewporter[1].name := 'get_viewport';
  GReq_wp_viewporter[1].signature := 'no';
  GReq_wp_viewporter[1].types := @GTypes[4];
  GIface_wp_viewporter.name := 'wp_viewporter';
  GIface_wp_viewporter.version := 1;
  GIface_wp_viewporter.method_count := 2;
  GIface_wp_viewporter.methods := @GReq_wp_viewporter[0];
  GIface_wp_viewporter.event_count := 0;
  GIface_wp_viewporter.events := nil;

  GReq_wp_viewport[0].name := 'destroy';
  GReq_wp_viewport[0].signature := '';
  GReq_wp_viewport[0].types := @GTypes[0];
  GReq_wp_viewport[1].name := 'set_source';
  GReq_wp_viewport[1].signature := 'ffff';
  GReq_wp_viewport[1].types := @GTypes[0];
  GReq_wp_viewport[2].name := 'set_destination';
  GReq_wp_viewport[2].signature := 'ii';
  GReq_wp_viewport[2].types := @GTypes[0];
  GIface_wp_viewport.name := 'wp_viewport';
  GIface_wp_viewport.version := 1;
  GIface_wp_viewport.method_count := 3;
  GIface_wp_viewport.methods := @GReq_wp_viewport[0];
  GIface_wp_viewport.event_count := 0;
  GIface_wp_viewport.events := nil;

end;

end.
