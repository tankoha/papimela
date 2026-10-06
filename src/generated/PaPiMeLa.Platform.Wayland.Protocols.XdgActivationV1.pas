{
  PaPiMeLa.Platform.Wayland.Protocols.XdgActivationV1

  自動生成ファイル。手で編集しないこと。
  生成元: xdg_activation_v1.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright � 2020 Aleix Pol Gonzalez <aleixpol@kde.org>
      Copyright � 2020 Carlos Garnacho <carlosg@gnome.org>
  
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
unit PaPiMeLa.Platform.Wayland.Protocols.XdgActivationV1;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  Txdg_activation_v1_opaque = record end;
  Pxdg_activation_v1 = ^Txdg_activation_v1_opaque;
  Txdg_activation_token_v1_opaque = record end;
  Pxdg_activation_token_v1 = ^Txdg_activation_token_v1_opaque;

const
  // xdg_activation_v1 (version 1)
  XDG_ACTIVATION_V1_DESTROY_OPCODE = 0;
  XDG_ACTIVATION_V1_GET_ACTIVATION_TOKEN_OPCODE = 1;
  XDG_ACTIVATION_V1_ACTIVATE_OPCODE = 2;
  XDG_ACTIVATION_V1_DESTROY_SINCE_VERSION = 1;
  XDG_ACTIVATION_V1_GET_ACTIVATION_TOKEN_SINCE_VERSION = 1;
  XDG_ACTIVATION_V1_ACTIVATE_SINCE_VERSION = 1;

  // xdg_activation_token_v1 (version 1)
  XDG_ACTIVATION_TOKEN_V1_SET_SERIAL_OPCODE = 0;
  XDG_ACTIVATION_TOKEN_V1_SET_APP_ID_OPCODE = 1;
  XDG_ACTIVATION_TOKEN_V1_SET_SURFACE_OPCODE = 2;
  XDG_ACTIVATION_TOKEN_V1_COMMIT_OPCODE = 3;
  XDG_ACTIVATION_TOKEN_V1_DESTROY_OPCODE = 4;
  XDG_ACTIVATION_TOKEN_V1_SET_SERIAL_SINCE_VERSION = 1;
  XDG_ACTIVATION_TOKEN_V1_SET_APP_ID_SINCE_VERSION = 1;
  XDG_ACTIVATION_TOKEN_V1_SET_SURFACE_SINCE_VERSION = 1;
  XDG_ACTIVATION_TOKEN_V1_COMMIT_SINCE_VERSION = 1;
  XDG_ACTIVATION_TOKEN_V1_DESTROY_SINCE_VERSION = 1;
  XDG_ACTIVATION_TOKEN_V1_DONE_SINCE_VERSION = 1;
  XDG_ACTIVATION_TOKEN_V1_ERROR_ALREADY_USED = 0;

var
  xdg_activation_v1_interface: Pwl_interface = nil;
  xdg_activation_token_v1_interface: Pwl_interface = nil;

type
  Txdg_activation_token_v1_listener = class abstract(TObject)
  public
    procedure done(AProxy: Pxdg_activation_token_v1; token: PAnsiChar); virtual;
  end;

  Txdg_activation_token_v1_listener_rec = record
    done: procedure(data: Pointer; AProxy: Pxdg_activation_token_v1; token: PAnsiChar); cdecl;
  end;

procedure xdg_activation_v1_destroy(AProxy: Pxdg_activation_v1);
function xdg_activation_v1_get_activation_token(AProxy: Pxdg_activation_v1): Pxdg_activation_token_v1;
procedure xdg_activation_v1_activate(AProxy: Pxdg_activation_v1; token: PAnsiChar; surface: Pwl_surface);

function xdg_activation_token_v1_add_listener_object(AProxy: Pxdg_activation_token_v1; AListener: Txdg_activation_token_v1_listener): LongInt;
procedure xdg_activation_token_v1_set_serial(AProxy: Pxdg_activation_token_v1; serial: LongWord; seat: Pwl_seat);
procedure xdg_activation_token_v1_set_app_id(AProxy: Pxdg_activation_token_v1; app_id: PAnsiChar);
procedure xdg_activation_token_v1_set_surface(AProxy: Pxdg_activation_token_v1; surface: Pwl_surface);
procedure xdg_activation_token_v1_commit(AProxy: Pxdg_activation_token_v1);
procedure xdg_activation_token_v1_destroy(AProxy: Pxdg_activation_token_v1);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..6] of Pwl_interface;
  GReq_xdg_activation_v1: array[0..2] of Twl_message;
  GIface_xdg_activation_v1: Twl_interface;
  GReq_xdg_activation_token_v1: array[0..4] of Twl_message;
  GEvt_xdg_activation_token_v1: array[0..0] of Twl_message;
  GIface_xdg_activation_token_v1: Twl_interface;

var
  GInitialized: Boolean = False;
  GThunks_xdg_activation_token_v1: Txdg_activation_token_v1_listener_rec;

procedure Txdg_activation_token_v1_listener.done(AProxy: Pxdg_activation_token_v1; token: PAnsiChar);
begin
end;

procedure Thunk_xdg_activation_token_v1_done(data: Pointer; AProxy: Pxdg_activation_token_v1; token: PAnsiChar); cdecl;
begin
  if data <> nil then
    Txdg_activation_token_v1_listener(data).done(AProxy, token);
end;

function xdg_activation_token_v1_add_listener_object(AProxy: Pxdg_activation_token_v1; AListener: Txdg_activation_token_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_xdg_activation_token_v1, AListener);
end;

procedure xdg_activation_v1_destroy(AProxy: Pxdg_activation_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_ACTIVATION_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function xdg_activation_v1_get_activation_token(AProxy: Pxdg_activation_v1): Pxdg_activation_token_v1;
begin
  EnsureProtocolInitialized;
  Result := Pxdg_activation_token_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_ACTIVATION_V1_GET_ACTIVATION_TOKEN_OPCODE, xdg_activation_token_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

procedure xdg_activation_v1_activate(AProxy: Pxdg_activation_v1; token: PAnsiChar; surface: Pwl_surface);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_ACTIVATION_V1_ACTIVATE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, token, surface);
end;

procedure xdg_activation_token_v1_set_serial(AProxy: Pxdg_activation_token_v1; serial: LongWord; seat: Pwl_seat);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_ACTIVATION_TOKEN_V1_SET_SERIAL_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, serial, seat);
end;

procedure xdg_activation_token_v1_set_app_id(AProxy: Pxdg_activation_token_v1; app_id: PAnsiChar);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_ACTIVATION_TOKEN_V1_SET_APP_ID_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, app_id);
end;

procedure xdg_activation_token_v1_set_surface(AProxy: Pxdg_activation_token_v1; surface: Pwl_surface);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_ACTIVATION_TOKEN_V1_SET_SURFACE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, surface);
end;

procedure xdg_activation_token_v1_commit(AProxy: Pxdg_activation_token_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_ACTIVATION_TOKEN_V1_COMMIT_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure xdg_activation_token_v1_destroy(AProxy: Pxdg_activation_token_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), XDG_ACTIVATION_TOKEN_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;

  xdg_activation_v1_interface := @GIface_xdg_activation_v1;
  xdg_activation_token_v1_interface := @GIface_xdg_activation_token_v1;
  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[1] := xdg_activation_token_v1_interface;
  GTypes[3] := wl_surface_interface;
  GTypes[5] := wl_seat_interface;
  GTypes[6] := wl_surface_interface;

  GReq_xdg_activation_v1[0].name := 'destroy';
  GReq_xdg_activation_v1[0].signature := '';
  GReq_xdg_activation_v1[0].types := @GTypes[0];
  GReq_xdg_activation_v1[1].name := 'get_activation_token';
  GReq_xdg_activation_v1[1].signature := 'n';
  GReq_xdg_activation_v1[1].types := @GTypes[1];
  GReq_xdg_activation_v1[2].name := 'activate';
  GReq_xdg_activation_v1[2].signature := 'so';
  GReq_xdg_activation_v1[2].types := @GTypes[2];
  GIface_xdg_activation_v1.name := 'xdg_activation_v1';
  GIface_xdg_activation_v1.version := 1;
  GIface_xdg_activation_v1.method_count := 3;
  GIface_xdg_activation_v1.methods := @GReq_xdg_activation_v1[0];
  GIface_xdg_activation_v1.event_count := 0;
  GIface_xdg_activation_v1.events := nil;

  GReq_xdg_activation_token_v1[0].name := 'set_serial';
  GReq_xdg_activation_token_v1[0].signature := 'uo';
  GReq_xdg_activation_token_v1[0].types := @GTypes[4];
  GReq_xdg_activation_token_v1[1].name := 'set_app_id';
  GReq_xdg_activation_token_v1[1].signature := 's';
  GReq_xdg_activation_token_v1[1].types := @GTypes[0];
  GReq_xdg_activation_token_v1[2].name := 'set_surface';
  GReq_xdg_activation_token_v1[2].signature := 'o';
  GReq_xdg_activation_token_v1[2].types := @GTypes[6];
  GReq_xdg_activation_token_v1[3].name := 'commit';
  GReq_xdg_activation_token_v1[3].signature := '';
  GReq_xdg_activation_token_v1[3].types := @GTypes[0];
  GReq_xdg_activation_token_v1[4].name := 'destroy';
  GReq_xdg_activation_token_v1[4].signature := '';
  GReq_xdg_activation_token_v1[4].types := @GTypes[0];
  GEvt_xdg_activation_token_v1[0].name := 'done';
  GEvt_xdg_activation_token_v1[0].signature := 's';
  GEvt_xdg_activation_token_v1[0].types := @GTypes[0];
  GIface_xdg_activation_token_v1.name := 'xdg_activation_token_v1';
  GIface_xdg_activation_token_v1.version := 1;
  GIface_xdg_activation_token_v1.method_count := 5;
  GIface_xdg_activation_token_v1.methods := @GReq_xdg_activation_token_v1[0];
  GIface_xdg_activation_token_v1.event_count := 1;
  GIface_xdg_activation_token_v1.events := @GEvt_xdg_activation_token_v1[0];

  GThunks_xdg_activation_token_v1.done := @Thunk_xdg_activation_token_v1_done;
end;

end.
