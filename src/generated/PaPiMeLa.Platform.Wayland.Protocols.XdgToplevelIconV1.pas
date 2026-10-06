{
  PaPiMeLa.Platform.Wayland.Protocols.XdgToplevelIconV1

  自動生成ファイル。手で編集しないこと。
  生成元: xdg_toplevel_icon_v1.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright � 2023-2024 Matthias Klumpp
      Copyright �      2024 David Edmundson
  
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
unit PaPiMeLa.Platform.Wayland.Protocols.XdgToplevelIconV1;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.XdgShell,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  Txdg_toplevel_icon_manager_v1_opaque = record end;
  Pxdg_toplevel_icon_manager_v1 = ^Txdg_toplevel_icon_manager_v1_opaque;
  Txdg_toplevel_icon_v1_opaque = record end;
  Pxdg_toplevel_icon_v1 = ^Txdg_toplevel_icon_v1_opaque;

const
  // xdg_toplevel_icon_manager_v1 (version 1)
  XDG_TOPLEVEL_ICON_MANAGER_V1_DESTROY_OPCODE = 0;
  XDG_TOPLEVEL_ICON_MANAGER_V1_CREATE_ICON_OPCODE = 1;
  XDG_TOPLEVEL_ICON_MANAGER_V1_SET_ICON_OPCODE = 2;
  XDG_TOPLEVEL_ICON_MANAGER_V1_DESTROY_SINCE_VERSION = 1;
  XDG_TOPLEVEL_ICON_MANAGER_V1_CREATE_ICON_SINCE_VERSION = 1;
  XDG_TOPLEVEL_ICON_MANAGER_V1_SET_ICON_SINCE_VERSION = 1;
  XDG_TOPLEVEL_ICON_MANAGER_V1_ICON_SIZE_SINCE_VERSION = 1;
  XDG_TOPLEVEL_ICON_MANAGER_V1_DONE_SINCE_VERSION = 1;

  // xdg_toplevel_icon_v1 (version 1)
  XDG_TOPLEVEL_ICON_V1_DESTROY_OPCODE = 0;
  XDG_TOPLEVEL_ICON_V1_SET_NAME_OPCODE = 1;
  XDG_TOPLEVEL_ICON_V1_ADD_BUFFER_OPCODE = 2;
  XDG_TOPLEVEL_ICON_V1_DESTROY_SINCE_VERSION = 1;
  XDG_TOPLEVEL_ICON_V1_SET_NAME_SINCE_VERSION = 1;
  XDG_TOPLEVEL_ICON_V1_ADD_BUFFER_SINCE_VERSION = 1;
  XDG_TOPLEVEL_ICON_V1_ERROR_INVALID_BUFFER = 1;
  XDG_TOPLEVEL_ICON_V1_ERROR_IMMUTABLE = 2;
  XDG_TOPLEVEL_ICON_V1_ERROR_NO_BUFFER = 3;

var
  xdg_toplevel_icon_manager_v1_interface: Pwl_interface = nil;
  xdg_toplevel_icon_v1_interface: Pwl_interface = nil;

type
  Txdg_toplevel_icon_manager_v1_listener = class abstract(TObject)
  public
    procedure icon_size(AProxy: Pxdg_toplevel_icon_manager_v1; size: LongInt); virtual;
    procedure done(AProxy: Pxdg_toplevel_icon_manager_v1); virtual;
  end;

  Txdg_toplevel_icon_manager_v1_listener_rec = record
    icon_size: procedure(data: Pointer; AProxy: Pxdg_toplevel_icon_manager_v1; size: LongInt); cdecl;
    done: procedure(data: Pointer; AProxy: Pxdg_toplevel_icon_manager_v1); cdecl;
  end;

function xdg_toplevel_icon_manager_v1_add_listener_object(AProxy: Pxdg_toplevel_icon_manager_v1; AListener: Txdg_toplevel_icon_manager_v1_listener): LongInt;
procedure xdg_toplevel_icon_manager_v1_destroy(AProxy: Pxdg_toplevel_icon_manager_v1);
function xdg_toplevel_icon_manager_v1_create_icon(AProxy: Pxdg_toplevel_icon_manager_v1): Pxdg_toplevel_icon_v1;
procedure xdg_toplevel_icon_manager_v1_set_icon(AProxy: Pxdg_toplevel_icon_manager_v1; toplevel: Pxdg_toplevel; icon: Pxdg_toplevel_icon_v1);

procedure xdg_toplevel_icon_v1_destroy(AProxy: Pxdg_toplevel_icon_v1);
procedure xdg_toplevel_icon_v1_set_name(AProxy: Pxdg_toplevel_icon_v1; icon_name: PAnsiChar);
procedure xdg_toplevel_icon_v1_add_buffer(AProxy: Pxdg_toplevel_icon_v1; buffer: Pwl_buffer; scale: LongInt);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..5] of Pwl_interface;
  GReq_xdg_toplevel_icon_manager_v1: array[0..2] of Twl_message;
  GEvt_xdg_toplevel_icon_manager_v1: array[0..1] of Twl_message;
  GIface_xdg_toplevel_icon_manager_v1: Twl_interface;
  GReq_xdg_toplevel_icon_v1: array[0..2] of Twl_message;
  GIface_xdg_toplevel_icon_v1: Twl_interface;

var
  GInitialized: Boolean = False;
  GThunks_xdg_toplevel_icon_manager_v1: Txdg_toplevel_icon_manager_v1_listener_rec;

procedure Txdg_toplevel_icon_manager_v1_listener.icon_size(AProxy: Pxdg_toplevel_icon_manager_v1; size: LongInt);
begin
end;

procedure Txdg_toplevel_icon_manager_v1_listener.done(AProxy: Pxdg_toplevel_icon_manager_v1);
begin
end;

procedure Thunk_xdg_toplevel_icon_manager_v1_icon_size(data: Pointer; AProxy: Pxdg_toplevel_icon_manager_v1; size: LongInt); cdecl;
begin
  if data <> nil then
    Txdg_toplevel_icon_manager_v1_listener(data).icon_size(AProxy, size);
end;

procedure Thunk_xdg_toplevel_icon_manager_v1_done(data: Pointer; AProxy: Pxdg_toplevel_icon_manager_v1); cdecl;
begin
  if data <> nil then
    Txdg_toplevel_icon_manager_v1_listener(data).done(AProxy);
end;

function xdg_toplevel_icon_manager_v1_add_listener_object(AProxy: Pxdg_toplevel_icon_manager_v1; AListener: Txdg_toplevel_icon_manager_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_xdg_toplevel_icon_manager_v1, AListener);
end;

procedure xdg_toplevel_icon_manager_v1_destroy(AProxy: Pxdg_toplevel_icon_manager_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_ICON_MANAGER_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function xdg_toplevel_icon_manager_v1_create_icon(AProxy: Pxdg_toplevel_icon_manager_v1): Pxdg_toplevel_icon_v1;
begin
  EnsureProtocolInitialized;
  Result := Pxdg_toplevel_icon_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_ICON_MANAGER_V1_CREATE_ICON_OPCODE, xdg_toplevel_icon_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

procedure xdg_toplevel_icon_manager_v1_set_icon(AProxy: Pxdg_toplevel_icon_manager_v1; toplevel: Pxdg_toplevel; icon: Pxdg_toplevel_icon_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_ICON_MANAGER_V1_SET_ICON_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, toplevel, icon);
end;

procedure xdg_toplevel_icon_v1_destroy(AProxy: Pxdg_toplevel_icon_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_ICON_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure xdg_toplevel_icon_v1_set_name(AProxy: Pxdg_toplevel_icon_v1; icon_name: PAnsiChar);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_ICON_V1_SET_NAME_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, icon_name);
end;

procedure xdg_toplevel_icon_v1_add_buffer(AProxy: Pxdg_toplevel_icon_v1; buffer: Pwl_buffer; scale: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_TOPLEVEL_ICON_V1_ADD_BUFFER_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, buffer, scale);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.XdgShell.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;

  xdg_toplevel_icon_manager_v1_interface := @GIface_xdg_toplevel_icon_manager_v1;
  xdg_toplevel_icon_v1_interface := @GIface_xdg_toplevel_icon_v1;
  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[1] := xdg_toplevel_icon_v1_interface;
  GTypes[2] := xdg_toplevel_interface;
  GTypes[3] := xdg_toplevel_icon_v1_interface;
  GTypes[4] := wl_buffer_interface;

  GReq_xdg_toplevel_icon_manager_v1[0].name := 'destroy';
  GReq_xdg_toplevel_icon_manager_v1[0].signature := '';
  GReq_xdg_toplevel_icon_manager_v1[0].types := @GTypes[0];
  GReq_xdg_toplevel_icon_manager_v1[1].name := 'create_icon';
  GReq_xdg_toplevel_icon_manager_v1[1].signature := 'n';
  GReq_xdg_toplevel_icon_manager_v1[1].types := @GTypes[1];
  GReq_xdg_toplevel_icon_manager_v1[2].name := 'set_icon';
  GReq_xdg_toplevel_icon_manager_v1[2].signature := 'o?o';
  GReq_xdg_toplevel_icon_manager_v1[2].types := @GTypes[2];
  GEvt_xdg_toplevel_icon_manager_v1[0].name := 'icon_size';
  GEvt_xdg_toplevel_icon_manager_v1[0].signature := 'i';
  GEvt_xdg_toplevel_icon_manager_v1[0].types := @GTypes[0];
  GEvt_xdg_toplevel_icon_manager_v1[1].name := 'done';
  GEvt_xdg_toplevel_icon_manager_v1[1].signature := '';
  GEvt_xdg_toplevel_icon_manager_v1[1].types := @GTypes[0];
  GIface_xdg_toplevel_icon_manager_v1.name := 'xdg_toplevel_icon_manager_v1';
  GIface_xdg_toplevel_icon_manager_v1.version := 1;
  GIface_xdg_toplevel_icon_manager_v1.method_count := 3;
  GIface_xdg_toplevel_icon_manager_v1.methods := @GReq_xdg_toplevel_icon_manager_v1[0];
  GIface_xdg_toplevel_icon_manager_v1.event_count := 2;
  GIface_xdg_toplevel_icon_manager_v1.events := @GEvt_xdg_toplevel_icon_manager_v1[0];

  GReq_xdg_toplevel_icon_v1[0].name := 'destroy';
  GReq_xdg_toplevel_icon_v1[0].signature := '';
  GReq_xdg_toplevel_icon_v1[0].types := @GTypes[0];
  GReq_xdg_toplevel_icon_v1[1].name := 'set_name';
  GReq_xdg_toplevel_icon_v1[1].signature := 's';
  GReq_xdg_toplevel_icon_v1[1].types := @GTypes[0];
  GReq_xdg_toplevel_icon_v1[2].name := 'add_buffer';
  GReq_xdg_toplevel_icon_v1[2].signature := 'oi';
  GReq_xdg_toplevel_icon_v1[2].types := @GTypes[4];
  GIface_xdg_toplevel_icon_v1.name := 'xdg_toplevel_icon_v1';
  GIface_xdg_toplevel_icon_v1.version := 1;
  GIface_xdg_toplevel_icon_v1.method_count := 3;
  GIface_xdg_toplevel_icon_v1.methods := @GReq_xdg_toplevel_icon_v1[0];
  GIface_xdg_toplevel_icon_v1.event_count := 0;
  GIface_xdg_toplevel_icon_v1.events := nil;

  GThunks_xdg_toplevel_icon_manager_v1.icon_size := @Thunk_xdg_toplevel_icon_manager_v1_icon_size;
  GThunks_xdg_toplevel_icon_manager_v1.done := @Thunk_xdg_toplevel_icon_manager_v1_done;
end;

end.
