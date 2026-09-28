{
  PaPiMeLa.Platform.Wayland.Protocols.XdgDialogV1

  自動生成ファイル。手で編集しないこと。
  生成元: xdg_dialog_v1.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright � 2023 Carlos Garnacho
  
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
unit PaPiMeLa.Platform.Wayland.Protocols.XdgDialogV1;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.XdgShell;

type
  Txdg_wm_dialog_v1_opaque = record end;
  Pxdg_wm_dialog_v1 = ^Txdg_wm_dialog_v1_opaque;
  Txdg_dialog_v1_opaque = record end;
  Pxdg_dialog_v1 = ^Txdg_dialog_v1_opaque;

const
  // xdg_wm_dialog_v1 (version 1)
  XDG_WM_DIALOG_V1_DESTROY_OPCODE = 0;
  XDG_WM_DIALOG_V1_GET_XDG_DIALOG_OPCODE = 1;
  XDG_WM_DIALOG_V1_DESTROY_SINCE_VERSION = 1;
  XDG_WM_DIALOG_V1_GET_XDG_DIALOG_SINCE_VERSION = 1;
  XDG_WM_DIALOG_V1_ERROR_ALREADY_USED = 0;

  // xdg_dialog_v1 (version 1)
  XDG_DIALOG_V1_DESTROY_OPCODE = 0;
  XDG_DIALOG_V1_SET_MODAL_OPCODE = 1;
  XDG_DIALOG_V1_UNSET_MODAL_OPCODE = 2;
  XDG_DIALOG_V1_DESTROY_SINCE_VERSION = 1;
  XDG_DIALOG_V1_SET_MODAL_SINCE_VERSION = 1;
  XDG_DIALOG_V1_UNSET_MODAL_SINCE_VERSION = 1;

var
  xdg_wm_dialog_v1_interface: Pwl_interface = nil;
  xdg_dialog_v1_interface: Pwl_interface = nil;

procedure xdg_wm_dialog_v1_destroy(AProxy: Pxdg_wm_dialog_v1);
function xdg_wm_dialog_v1_get_xdg_dialog(AProxy: Pxdg_wm_dialog_v1; toplevel: Pxdg_toplevel): Pxdg_dialog_v1;

procedure xdg_dialog_v1_destroy(AProxy: Pxdg_dialog_v1);
procedure xdg_dialog_v1_set_modal(AProxy: Pxdg_dialog_v1);
procedure xdg_dialog_v1_unset_modal(AProxy: Pxdg_dialog_v1);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..1] of Pwl_interface;
  GReq_xdg_wm_dialog_v1: array[0..1] of Twl_message;
  GIface_xdg_wm_dialog_v1: Twl_interface;
  GReq_xdg_dialog_v1: array[0..2] of Twl_message;
  GIface_xdg_dialog_v1: Twl_interface;

var
  GInitialized: Boolean = False;

procedure xdg_wm_dialog_v1_destroy(AProxy: Pxdg_wm_dialog_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_WM_DIALOG_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function xdg_wm_dialog_v1_get_xdg_dialog(AProxy: Pxdg_wm_dialog_v1; toplevel: Pxdg_toplevel): Pxdg_dialog_v1;
begin
  EnsureProtocolInitialized;
  Result := Pxdg_dialog_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_WM_DIALOG_V1_GET_XDG_DIALOG_OPCODE, xdg_dialog_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), toplevel));
end;

procedure xdg_dialog_v1_destroy(AProxy: Pxdg_dialog_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_DIALOG_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure xdg_dialog_v1_set_modal(AProxy: Pxdg_dialog_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_DIALOG_V1_SET_MODAL_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure xdg_dialog_v1_unset_modal(AProxy: Pxdg_dialog_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_DIALOG_V1_UNSET_MODAL_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.XdgShell.EnsureProtocolInitialized;

  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[0] := xdg_dialog_v1_interface;
  GTypes[1] := xdg_toplevel_interface;

  GReq_xdg_wm_dialog_v1[0].name := 'destroy';
  GReq_xdg_wm_dialog_v1[0].signature := '';
  GReq_xdg_wm_dialog_v1[0].types := @GTypes[0];
  GReq_xdg_wm_dialog_v1[1].name := 'get_xdg_dialog';
  GReq_xdg_wm_dialog_v1[1].signature := 'no';
  GReq_xdg_wm_dialog_v1[1].types := @GTypes[0];
  GIface_xdg_wm_dialog_v1.name := 'xdg_wm_dialog_v1';
  GIface_xdg_wm_dialog_v1.version := 1;
  GIface_xdg_wm_dialog_v1.method_count := 2;
  GIface_xdg_wm_dialog_v1.methods := @GReq_xdg_wm_dialog_v1[0];
  GIface_xdg_wm_dialog_v1.event_count := 0;
  GIface_xdg_wm_dialog_v1.events := nil;
  xdg_wm_dialog_v1_interface := @GIface_xdg_wm_dialog_v1;

  GReq_xdg_dialog_v1[0].name := 'destroy';
  GReq_xdg_dialog_v1[0].signature := '';
  GReq_xdg_dialog_v1[0].types := @GTypes[0];
  GReq_xdg_dialog_v1[1].name := 'set_modal';
  GReq_xdg_dialog_v1[1].signature := '';
  GReq_xdg_dialog_v1[1].types := @GTypes[0];
  GReq_xdg_dialog_v1[2].name := 'unset_modal';
  GReq_xdg_dialog_v1[2].signature := '';
  GReq_xdg_dialog_v1[2].types := @GTypes[0];
  GIface_xdg_dialog_v1.name := 'xdg_dialog_v1';
  GIface_xdg_dialog_v1.version := 1;
  GIface_xdg_dialog_v1.method_count := 3;
  GIface_xdg_dialog_v1.methods := @GReq_xdg_dialog_v1[0];
  GIface_xdg_dialog_v1.event_count := 0;
  GIface_xdg_dialog_v1.events := nil;
  xdg_dialog_v1_interface := @GIface_xdg_dialog_v1;

end;

end.
