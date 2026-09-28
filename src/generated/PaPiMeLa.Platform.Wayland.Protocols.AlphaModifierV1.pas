{
  PaPiMeLa.Platform.Wayland.Protocols.AlphaModifierV1

  自動生成ファイル。手で編集しないこと。
  生成元: alpha_modifier_v1.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright � 2024 Xaver Hugl
  
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
unit PaPiMeLa.Platform.Wayland.Protocols.AlphaModifierV1;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  Twp_alpha_modifier_v1_opaque = record end;
  Pwp_alpha_modifier_v1 = ^Twp_alpha_modifier_v1_opaque;
  Twp_alpha_modifier_surface_v1_opaque = record end;
  Pwp_alpha_modifier_surface_v1 = ^Twp_alpha_modifier_surface_v1_opaque;

const
  // wp_alpha_modifier_v1 (version 1)
  WP_ALPHA_MODIFIER_V1_DESTROY_OPCODE = 0;
  WP_ALPHA_MODIFIER_V1_GET_SURFACE_OPCODE = 1;
  WP_ALPHA_MODIFIER_V1_DESTROY_SINCE_VERSION = 1;
  WP_ALPHA_MODIFIER_V1_GET_SURFACE_SINCE_VERSION = 1;
  WP_ALPHA_MODIFIER_V1_ERROR_ALREADY_CONSTRUCTED = 0;

  // wp_alpha_modifier_surface_v1 (version 1)
  WP_ALPHA_MODIFIER_SURFACE_V1_DESTROY_OPCODE = 0;
  WP_ALPHA_MODIFIER_SURFACE_V1_SET_MULTIPLIER_OPCODE = 1;
  WP_ALPHA_MODIFIER_SURFACE_V1_DESTROY_SINCE_VERSION = 1;
  WP_ALPHA_MODIFIER_SURFACE_V1_SET_MULTIPLIER_SINCE_VERSION = 1;
  WP_ALPHA_MODIFIER_SURFACE_V1_ERROR_NO_SURFACE = 0;

var
  wp_alpha_modifier_v1_interface: Pwl_interface = nil;
  wp_alpha_modifier_surface_v1_interface: Pwl_interface = nil;

procedure wp_alpha_modifier_v1_destroy(AProxy: Pwp_alpha_modifier_v1);
function wp_alpha_modifier_v1_get_surface(AProxy: Pwp_alpha_modifier_v1; surface: Pwl_surface): Pwp_alpha_modifier_surface_v1;

procedure wp_alpha_modifier_surface_v1_destroy(AProxy: Pwp_alpha_modifier_surface_v1);
procedure wp_alpha_modifier_surface_v1_set_multiplier(AProxy: Pwp_alpha_modifier_surface_v1; factor: LongWord);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..2] of Pwl_interface;
  GReq_wp_alpha_modifier_v1: array[0..1] of Twl_message;
  GIface_wp_alpha_modifier_v1: Twl_interface;
  GReq_wp_alpha_modifier_surface_v1: array[0..1] of Twl_message;
  GIface_wp_alpha_modifier_surface_v1: Twl_interface;

var
  GInitialized: Boolean = False;

procedure wp_alpha_modifier_v1_destroy(AProxy: Pwp_alpha_modifier_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_ALPHA_MODIFIER_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function wp_alpha_modifier_v1_get_surface(AProxy: Pwp_alpha_modifier_v1; surface: Pwl_surface): Pwp_alpha_modifier_surface_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_alpha_modifier_surface_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_ALPHA_MODIFIER_V1_GET_SURFACE_OPCODE, wp_alpha_modifier_surface_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), surface));
end;

procedure wp_alpha_modifier_surface_v1_destroy(AProxy: Pwp_alpha_modifier_surface_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_ALPHA_MODIFIER_SURFACE_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wp_alpha_modifier_surface_v1_set_multiplier(AProxy: Pwp_alpha_modifier_surface_v1; factor: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_ALPHA_MODIFIER_SURFACE_V1_SET_MULTIPLIER_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, factor);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;

  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[1] := wp_alpha_modifier_surface_v1_interface;
  GTypes[2] := wl_surface_interface;

  GReq_wp_alpha_modifier_v1[0].name := 'destroy';
  GReq_wp_alpha_modifier_v1[0].signature := '';
  GReq_wp_alpha_modifier_v1[0].types := @GTypes[0];
  GReq_wp_alpha_modifier_v1[1].name := 'get_surface';
  GReq_wp_alpha_modifier_v1[1].signature := 'no';
  GReq_wp_alpha_modifier_v1[1].types := @GTypes[1];
  GIface_wp_alpha_modifier_v1.name := 'wp_alpha_modifier_v1';
  GIface_wp_alpha_modifier_v1.version := 1;
  GIface_wp_alpha_modifier_v1.method_count := 2;
  GIface_wp_alpha_modifier_v1.methods := @GReq_wp_alpha_modifier_v1[0];
  GIface_wp_alpha_modifier_v1.event_count := 0;
  GIface_wp_alpha_modifier_v1.events := nil;
  wp_alpha_modifier_v1_interface := @GIface_wp_alpha_modifier_v1;

  GReq_wp_alpha_modifier_surface_v1[0].name := 'destroy';
  GReq_wp_alpha_modifier_surface_v1[0].signature := '';
  GReq_wp_alpha_modifier_surface_v1[0].types := @GTypes[0];
  GReq_wp_alpha_modifier_surface_v1[1].name := 'set_multiplier';
  GReq_wp_alpha_modifier_surface_v1[1].signature := 'u';
  GReq_wp_alpha_modifier_surface_v1[1].types := @GTypes[0];
  GIface_wp_alpha_modifier_surface_v1.name := 'wp_alpha_modifier_surface_v1';
  GIface_wp_alpha_modifier_surface_v1.version := 1;
  GIface_wp_alpha_modifier_surface_v1.method_count := 2;
  GIface_wp_alpha_modifier_surface_v1.methods := @GReq_wp_alpha_modifier_surface_v1[0];
  GIface_wp_alpha_modifier_surface_v1.event_count := 0;
  GIface_wp_alpha_modifier_surface_v1.events := nil;
  wp_alpha_modifier_surface_v1_interface := @GIface_wp_alpha_modifier_surface_v1;

end;

end.
