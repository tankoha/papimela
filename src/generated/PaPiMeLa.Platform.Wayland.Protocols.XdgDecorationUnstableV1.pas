{
  PaPiMeLa.Platform.Wayland.Protocols.XdgDecorationUnstableV1

  自動生成ファイル。手で編集しないこと。
  生成元: xdg_decoration_unstable_v1.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright � 2018 Simon Ser
  
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
unit PaPiMeLa.Platform.Wayland.Protocols.XdgDecorationUnstableV1;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.XdgShell;

type
  Tzxdg_decoration_manager_v1_opaque = record end;
  Pzxdg_decoration_manager_v1 = ^Tzxdg_decoration_manager_v1_opaque;
  Tzxdg_toplevel_decoration_v1_opaque = record end;
  Pzxdg_toplevel_decoration_v1 = ^Tzxdg_toplevel_decoration_v1_opaque;

const
  // zxdg_decoration_manager_v1 (version 2)
  ZXDG_DECORATION_MANAGER_V1_DESTROY_OPCODE = 0;
  ZXDG_DECORATION_MANAGER_V1_GET_TOPLEVEL_DECORATION_OPCODE = 1;
  ZXDG_DECORATION_MANAGER_V1_DESTROY_SINCE_VERSION = 1;
  ZXDG_DECORATION_MANAGER_V1_GET_TOPLEVEL_DECORATION_SINCE_VERSION = 1;

  // zxdg_toplevel_decoration_v1 (version 2)
  ZXDG_TOPLEVEL_DECORATION_V1_DESTROY_OPCODE = 0;
  ZXDG_TOPLEVEL_DECORATION_V1_SET_MODE_OPCODE = 1;
  ZXDG_TOPLEVEL_DECORATION_V1_UNSET_MODE_OPCODE = 2;
  ZXDG_TOPLEVEL_DECORATION_V1_DESTROY_SINCE_VERSION = 1;
  ZXDG_TOPLEVEL_DECORATION_V1_SET_MODE_SINCE_VERSION = 1;
  ZXDG_TOPLEVEL_DECORATION_V1_UNSET_MODE_SINCE_VERSION = 1;
  ZXDG_TOPLEVEL_DECORATION_V1_CONFIGURE_SINCE_VERSION = 1;
  ZXDG_TOPLEVEL_DECORATION_V1_ERROR_UNCONFIGURED_BUFFER = 0;
  ZXDG_TOPLEVEL_DECORATION_V1_ERROR_ALREADY_CONSTRUCTED = 1;
  ZXDG_TOPLEVEL_DECORATION_V1_ERROR_ORPHANED = 2;
  ZXDG_TOPLEVEL_DECORATION_V1_ERROR_INVALID_MODE = 3;
  ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE = 1;
  ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE = 2;

var
  zxdg_decoration_manager_v1_interface: Pwl_interface = nil;
  zxdg_toplevel_decoration_v1_interface: Pwl_interface = nil;

type
  Tzxdg_toplevel_decoration_v1_listener = class abstract(TObject)
  public
    procedure configure(AProxy: Pzxdg_toplevel_decoration_v1; mode: LongWord); virtual;
  end;

  Tzxdg_toplevel_decoration_v1_listener_rec = record
    configure: procedure(data: Pointer; AProxy: Pzxdg_toplevel_decoration_v1; mode: LongWord); cdecl;
  end;

procedure zxdg_decoration_manager_v1_destroy(AProxy: Pzxdg_decoration_manager_v1);
function zxdg_decoration_manager_v1_get_toplevel_decoration(AProxy: Pzxdg_decoration_manager_v1; toplevel: Pxdg_toplevel): Pzxdg_toplevel_decoration_v1;

function zxdg_toplevel_decoration_v1_add_listener_object(AProxy: Pzxdg_toplevel_decoration_v1; AListener: Tzxdg_toplevel_decoration_v1_listener): LongInt;
procedure zxdg_toplevel_decoration_v1_destroy(AProxy: Pzxdg_toplevel_decoration_v1);
procedure zxdg_toplevel_decoration_v1_set_mode(AProxy: Pzxdg_toplevel_decoration_v1; mode: LongWord);
procedure zxdg_toplevel_decoration_v1_unset_mode(AProxy: Pzxdg_toplevel_decoration_v1);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..2] of Pwl_interface;
  GReq_zxdg_decoration_manager_v1: array[0..1] of Twl_message;
  GIface_zxdg_decoration_manager_v1: Twl_interface;
  GReq_zxdg_toplevel_decoration_v1: array[0..2] of Twl_message;
  GEvt_zxdg_toplevel_decoration_v1: array[0..0] of Twl_message;
  GIface_zxdg_toplevel_decoration_v1: Twl_interface;

var
  GInitialized: Boolean = False;
  GThunks_zxdg_toplevel_decoration_v1: Tzxdg_toplevel_decoration_v1_listener_rec;

procedure Tzxdg_toplevel_decoration_v1_listener.configure(AProxy: Pzxdg_toplevel_decoration_v1; mode: LongWord);
begin
end;

procedure Thunk_zxdg_toplevel_decoration_v1_configure(data: Pointer; AProxy: Pzxdg_toplevel_decoration_v1; mode: LongWord); cdecl;
begin
  if data <> nil then
    Tzxdg_toplevel_decoration_v1_listener(data).configure(AProxy, mode);
end;

function zxdg_toplevel_decoration_v1_add_listener_object(AProxy: Pzxdg_toplevel_decoration_v1; AListener: Tzxdg_toplevel_decoration_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zxdg_toplevel_decoration_v1, AListener);
end;

procedure zxdg_decoration_manager_v1_destroy(AProxy: Pzxdg_decoration_manager_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZXDG_DECORATION_MANAGER_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function zxdg_decoration_manager_v1_get_toplevel_decoration(AProxy: Pzxdg_decoration_manager_v1; toplevel: Pxdg_toplevel): Pzxdg_toplevel_decoration_v1;
begin
  EnsureProtocolInitialized;
  Result := Pzxdg_toplevel_decoration_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZXDG_DECORATION_MANAGER_V1_GET_TOPLEVEL_DECORATION_OPCODE, zxdg_toplevel_decoration_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), toplevel));
end;

procedure zxdg_toplevel_decoration_v1_destroy(AProxy: Pzxdg_toplevel_decoration_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZXDG_TOPLEVEL_DECORATION_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure zxdg_toplevel_decoration_v1_set_mode(AProxy: Pzxdg_toplevel_decoration_v1; mode: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZXDG_TOPLEVEL_DECORATION_V1_SET_MODE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, mode);
end;

procedure zxdg_toplevel_decoration_v1_unset_mode(AProxy: Pzxdg_toplevel_decoration_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZXDG_TOPLEVEL_DECORATION_V1_UNSET_MODE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.XdgShell.EnsureProtocolInitialized;

  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[1] := zxdg_toplevel_decoration_v1_interface;
  GTypes[2] := xdg_toplevel_interface;

  GReq_zxdg_decoration_manager_v1[0].name := 'destroy';
  GReq_zxdg_decoration_manager_v1[0].signature := '';
  GReq_zxdg_decoration_manager_v1[0].types := @GTypes[0];
  GReq_zxdg_decoration_manager_v1[1].name := 'get_toplevel_decoration';
  GReq_zxdg_decoration_manager_v1[1].signature := 'no';
  GReq_zxdg_decoration_manager_v1[1].types := @GTypes[1];
  GIface_zxdg_decoration_manager_v1.name := 'zxdg_decoration_manager_v1';
  GIface_zxdg_decoration_manager_v1.version := 2;
  GIface_zxdg_decoration_manager_v1.method_count := 2;
  GIface_zxdg_decoration_manager_v1.methods := @GReq_zxdg_decoration_manager_v1[0];
  GIface_zxdg_decoration_manager_v1.event_count := 0;
  GIface_zxdg_decoration_manager_v1.events := nil;
  zxdg_decoration_manager_v1_interface := @GIface_zxdg_decoration_manager_v1;

  GReq_zxdg_toplevel_decoration_v1[0].name := 'destroy';
  GReq_zxdg_toplevel_decoration_v1[0].signature := '';
  GReq_zxdg_toplevel_decoration_v1[0].types := @GTypes[0];
  GReq_zxdg_toplevel_decoration_v1[1].name := 'set_mode';
  GReq_zxdg_toplevel_decoration_v1[1].signature := 'u';
  GReq_zxdg_toplevel_decoration_v1[1].types := @GTypes[0];
  GReq_zxdg_toplevel_decoration_v1[2].name := 'unset_mode';
  GReq_zxdg_toplevel_decoration_v1[2].signature := '';
  GReq_zxdg_toplevel_decoration_v1[2].types := @GTypes[0];
  GEvt_zxdg_toplevel_decoration_v1[0].name := 'configure';
  GEvt_zxdg_toplevel_decoration_v1[0].signature := 'u';
  GEvt_zxdg_toplevel_decoration_v1[0].types := @GTypes[0];
  GIface_zxdg_toplevel_decoration_v1.name := 'zxdg_toplevel_decoration_v1';
  GIface_zxdg_toplevel_decoration_v1.version := 2;
  GIface_zxdg_toplevel_decoration_v1.method_count := 3;
  GIface_zxdg_toplevel_decoration_v1.methods := @GReq_zxdg_toplevel_decoration_v1[0];
  GIface_zxdg_toplevel_decoration_v1.event_count := 1;
  GIface_zxdg_toplevel_decoration_v1.events := @GEvt_zxdg_toplevel_decoration_v1[0];
  zxdg_toplevel_decoration_v1_interface := @GIface_zxdg_toplevel_decoration_v1;

  GThunks_zxdg_toplevel_decoration_v1.configure := @Thunk_zxdg_toplevel_decoration_v1_configure;
end;

end.
