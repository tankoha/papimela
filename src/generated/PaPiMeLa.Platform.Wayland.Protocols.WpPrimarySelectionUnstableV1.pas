{
  PaPiMeLa.Platform.Wayland.Protocols.WpPrimarySelectionUnstableV1

  自動生成ファイル。手で編集しないこと。
  生成元: wp_primary_selection_unstable_v1.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright � 2015, 2016 Red Hat
  
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
unit PaPiMeLa.Platform.Wayland.Protocols.WpPrimarySelectionUnstableV1;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  Tzwp_primary_selection_device_manager_v1_opaque = record end;
  Pzwp_primary_selection_device_manager_v1 = ^Tzwp_primary_selection_device_manager_v1_opaque;
  Tzwp_primary_selection_device_v1_opaque = record end;
  Pzwp_primary_selection_device_v1 = ^Tzwp_primary_selection_device_v1_opaque;
  Tzwp_primary_selection_offer_v1_opaque = record end;
  Pzwp_primary_selection_offer_v1 = ^Tzwp_primary_selection_offer_v1_opaque;
  Tzwp_primary_selection_source_v1_opaque = record end;
  Pzwp_primary_selection_source_v1 = ^Tzwp_primary_selection_source_v1_opaque;

const
  // zwp_primary_selection_device_manager_v1 (version 1)
  ZWP_PRIMARY_SELECTION_DEVICE_MANAGER_V1_CREATE_SOURCE_OPCODE = 0;
  ZWP_PRIMARY_SELECTION_DEVICE_MANAGER_V1_GET_DEVICE_OPCODE = 1;
  ZWP_PRIMARY_SELECTION_DEVICE_MANAGER_V1_DESTROY_OPCODE = 2;
  ZWP_PRIMARY_SELECTION_DEVICE_MANAGER_V1_CREATE_SOURCE_SINCE_VERSION = 1;
  ZWP_PRIMARY_SELECTION_DEVICE_MANAGER_V1_GET_DEVICE_SINCE_VERSION = 1;
  ZWP_PRIMARY_SELECTION_DEVICE_MANAGER_V1_DESTROY_SINCE_VERSION = 1;

  // zwp_primary_selection_device_v1 (version 1)
  ZWP_PRIMARY_SELECTION_DEVICE_V1_SET_SELECTION_OPCODE = 0;
  ZWP_PRIMARY_SELECTION_DEVICE_V1_DESTROY_OPCODE = 1;
  ZWP_PRIMARY_SELECTION_DEVICE_V1_SET_SELECTION_SINCE_VERSION = 1;
  ZWP_PRIMARY_SELECTION_DEVICE_V1_DESTROY_SINCE_VERSION = 1;
  ZWP_PRIMARY_SELECTION_DEVICE_V1_DATA_OFFER_SINCE_VERSION = 1;
  ZWP_PRIMARY_SELECTION_DEVICE_V1_SELECTION_SINCE_VERSION = 1;

  // zwp_primary_selection_offer_v1 (version 1)
  ZWP_PRIMARY_SELECTION_OFFER_V1_RECEIVE_OPCODE = 0;
  ZWP_PRIMARY_SELECTION_OFFER_V1_DESTROY_OPCODE = 1;
  ZWP_PRIMARY_SELECTION_OFFER_V1_RECEIVE_SINCE_VERSION = 1;
  ZWP_PRIMARY_SELECTION_OFFER_V1_DESTROY_SINCE_VERSION = 1;
  ZWP_PRIMARY_SELECTION_OFFER_V1_OFFER_SINCE_VERSION = 1;

  // zwp_primary_selection_source_v1 (version 1)
  ZWP_PRIMARY_SELECTION_SOURCE_V1_OFFER_OPCODE = 0;
  ZWP_PRIMARY_SELECTION_SOURCE_V1_DESTROY_OPCODE = 1;
  ZWP_PRIMARY_SELECTION_SOURCE_V1_OFFER_SINCE_VERSION = 1;
  ZWP_PRIMARY_SELECTION_SOURCE_V1_DESTROY_SINCE_VERSION = 1;
  ZWP_PRIMARY_SELECTION_SOURCE_V1_SEND_SINCE_VERSION = 1;
  ZWP_PRIMARY_SELECTION_SOURCE_V1_CANCELLED_SINCE_VERSION = 1;

var
  zwp_primary_selection_device_manager_v1_interface: Pwl_interface = nil;
  zwp_primary_selection_device_v1_interface: Pwl_interface = nil;
  zwp_primary_selection_offer_v1_interface: Pwl_interface = nil;
  zwp_primary_selection_source_v1_interface: Pwl_interface = nil;

type
  Tzwp_primary_selection_device_v1_listener = class abstract(TObject)
  public
    procedure data_offer(AProxy: Pzwp_primary_selection_device_v1; offer: Pzwp_primary_selection_offer_v1); virtual;
    procedure selection(AProxy: Pzwp_primary_selection_device_v1; id: Pzwp_primary_selection_offer_v1); virtual;
  end;

  Tzwp_primary_selection_device_v1_listener_rec = record
    data_offer: procedure(data: Pointer; AProxy: Pzwp_primary_selection_device_v1; offer: Pzwp_primary_selection_offer_v1); cdecl;
    selection: procedure(data: Pointer; AProxy: Pzwp_primary_selection_device_v1; id: Pzwp_primary_selection_offer_v1); cdecl;
  end;

  Tzwp_primary_selection_offer_v1_listener = class abstract(TObject)
  public
    procedure offer(AProxy: Pzwp_primary_selection_offer_v1; mime_type: PAnsiChar); virtual;
  end;

  Tzwp_primary_selection_offer_v1_listener_rec = record
    offer: procedure(data: Pointer; AProxy: Pzwp_primary_selection_offer_v1; mime_type: PAnsiChar); cdecl;
  end;

  Tzwp_primary_selection_source_v1_listener = class abstract(TObject)
  public
    procedure send(AProxy: Pzwp_primary_selection_source_v1; mime_type: PAnsiChar; fd: LongInt); virtual;
    procedure cancelled(AProxy: Pzwp_primary_selection_source_v1); virtual;
  end;

  Tzwp_primary_selection_source_v1_listener_rec = record
    send: procedure(data: Pointer; AProxy: Pzwp_primary_selection_source_v1; mime_type: PAnsiChar; fd: LongInt); cdecl;
    cancelled: procedure(data: Pointer; AProxy: Pzwp_primary_selection_source_v1); cdecl;
  end;

function zwp_primary_selection_device_manager_v1_create_source(AProxy: Pzwp_primary_selection_device_manager_v1): Pzwp_primary_selection_source_v1;
function zwp_primary_selection_device_manager_v1_get_device(AProxy: Pzwp_primary_selection_device_manager_v1; seat: Pwl_seat): Pzwp_primary_selection_device_v1;
procedure zwp_primary_selection_device_manager_v1_destroy(AProxy: Pzwp_primary_selection_device_manager_v1);

function zwp_primary_selection_device_v1_add_listener_object(AProxy: Pzwp_primary_selection_device_v1; AListener: Tzwp_primary_selection_device_v1_listener): LongInt;
procedure zwp_primary_selection_device_v1_set_selection(AProxy: Pzwp_primary_selection_device_v1; source: Pzwp_primary_selection_source_v1; serial: LongWord);
procedure zwp_primary_selection_device_v1_destroy(AProxy: Pzwp_primary_selection_device_v1);

function zwp_primary_selection_offer_v1_add_listener_object(AProxy: Pzwp_primary_selection_offer_v1; AListener: Tzwp_primary_selection_offer_v1_listener): LongInt;
procedure zwp_primary_selection_offer_v1_receive(AProxy: Pzwp_primary_selection_offer_v1; mime_type: PAnsiChar; fd: LongInt);
procedure zwp_primary_selection_offer_v1_destroy(AProxy: Pzwp_primary_selection_offer_v1);

function zwp_primary_selection_source_v1_add_listener_object(AProxy: Pzwp_primary_selection_source_v1; AListener: Tzwp_primary_selection_source_v1_listener): LongInt;
procedure zwp_primary_selection_source_v1_offer(AProxy: Pzwp_primary_selection_source_v1; mime_type: PAnsiChar);
procedure zwp_primary_selection_source_v1_destroy(AProxy: Pzwp_primary_selection_source_v1);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..8] of Pwl_interface;
  GReq_zwp_primary_selection_device_manager_v1: array[0..2] of Twl_message;
  GIface_zwp_primary_selection_device_manager_v1: Twl_interface;
  GReq_zwp_primary_selection_device_v1: array[0..1] of Twl_message;
  GEvt_zwp_primary_selection_device_v1: array[0..1] of Twl_message;
  GIface_zwp_primary_selection_device_v1: Twl_interface;
  GReq_zwp_primary_selection_offer_v1: array[0..1] of Twl_message;
  GEvt_zwp_primary_selection_offer_v1: array[0..0] of Twl_message;
  GIface_zwp_primary_selection_offer_v1: Twl_interface;
  GReq_zwp_primary_selection_source_v1: array[0..1] of Twl_message;
  GEvt_zwp_primary_selection_source_v1: array[0..1] of Twl_message;
  GIface_zwp_primary_selection_source_v1: Twl_interface;

var
  GInitialized: Boolean = False;
  GThunks_zwp_primary_selection_device_v1: Tzwp_primary_selection_device_v1_listener_rec;
  GThunks_zwp_primary_selection_offer_v1: Tzwp_primary_selection_offer_v1_listener_rec;
  GThunks_zwp_primary_selection_source_v1: Tzwp_primary_selection_source_v1_listener_rec;

procedure Tzwp_primary_selection_device_v1_listener.data_offer(AProxy: Pzwp_primary_selection_device_v1; offer: Pzwp_primary_selection_offer_v1);
begin
end;

procedure Tzwp_primary_selection_device_v1_listener.selection(AProxy: Pzwp_primary_selection_device_v1; id: Pzwp_primary_selection_offer_v1);
begin
end;

procedure Tzwp_primary_selection_offer_v1_listener.offer(AProxy: Pzwp_primary_selection_offer_v1; mime_type: PAnsiChar);
begin
end;

procedure Tzwp_primary_selection_source_v1_listener.send(AProxy: Pzwp_primary_selection_source_v1; mime_type: PAnsiChar; fd: LongInt);
begin
end;

procedure Tzwp_primary_selection_source_v1_listener.cancelled(AProxy: Pzwp_primary_selection_source_v1);
begin
end;

procedure Thunk_zwp_primary_selection_device_v1_data_offer(data: Pointer; AProxy: Pzwp_primary_selection_device_v1; offer: Pzwp_primary_selection_offer_v1); cdecl;
begin
  if data <> nil then
    Tzwp_primary_selection_device_v1_listener(data).data_offer(AProxy, offer);
end;

procedure Thunk_zwp_primary_selection_device_v1_selection(data: Pointer; AProxy: Pzwp_primary_selection_device_v1; id: Pzwp_primary_selection_offer_v1); cdecl;
begin
  if data <> nil then
    Tzwp_primary_selection_device_v1_listener(data).selection(AProxy, id);
end;

procedure Thunk_zwp_primary_selection_offer_v1_offer(data: Pointer; AProxy: Pzwp_primary_selection_offer_v1; mime_type: PAnsiChar); cdecl;
begin
  if data <> nil then
    Tzwp_primary_selection_offer_v1_listener(data).offer(AProxy, mime_type);
end;

procedure Thunk_zwp_primary_selection_source_v1_send(data: Pointer; AProxy: Pzwp_primary_selection_source_v1; mime_type: PAnsiChar; fd: LongInt); cdecl;
begin
  if data <> nil then
    Tzwp_primary_selection_source_v1_listener(data).send(AProxy, mime_type, fd);
end;

procedure Thunk_zwp_primary_selection_source_v1_cancelled(data: Pointer; AProxy: Pzwp_primary_selection_source_v1); cdecl;
begin
  if data <> nil then
    Tzwp_primary_selection_source_v1_listener(data).cancelled(AProxy);
end;

function zwp_primary_selection_device_v1_add_listener_object(AProxy: Pzwp_primary_selection_device_v1; AListener: Tzwp_primary_selection_device_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_primary_selection_device_v1, AListener);
end;

function zwp_primary_selection_offer_v1_add_listener_object(AProxy: Pzwp_primary_selection_offer_v1; AListener: Tzwp_primary_selection_offer_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_primary_selection_offer_v1, AListener);
end;

function zwp_primary_selection_source_v1_add_listener_object(AProxy: Pzwp_primary_selection_source_v1; AListener: Tzwp_primary_selection_source_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_primary_selection_source_v1, AListener);
end;

function zwp_primary_selection_device_manager_v1_create_source(AProxy: Pzwp_primary_selection_device_manager_v1): Pzwp_primary_selection_source_v1;
begin
  EnsureProtocolInitialized;
  Result := Pzwp_primary_selection_source_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_PRIMARY_SELECTION_DEVICE_MANAGER_V1_CREATE_SOURCE_OPCODE, zwp_primary_selection_source_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function zwp_primary_selection_device_manager_v1_get_device(AProxy: Pzwp_primary_selection_device_manager_v1; seat: Pwl_seat): Pzwp_primary_selection_device_v1;
begin
  EnsureProtocolInitialized;
  Result := Pzwp_primary_selection_device_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_PRIMARY_SELECTION_DEVICE_MANAGER_V1_GET_DEVICE_OPCODE, zwp_primary_selection_device_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), seat));
end;

procedure zwp_primary_selection_device_manager_v1_destroy(AProxy: Pzwp_primary_selection_device_manager_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_PRIMARY_SELECTION_DEVICE_MANAGER_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure zwp_primary_selection_device_v1_set_selection(AProxy: Pzwp_primary_selection_device_v1; source: Pzwp_primary_selection_source_v1; serial: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_PRIMARY_SELECTION_DEVICE_V1_SET_SELECTION_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, source, serial);
end;

procedure zwp_primary_selection_device_v1_destroy(AProxy: Pzwp_primary_selection_device_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_PRIMARY_SELECTION_DEVICE_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure zwp_primary_selection_offer_v1_receive(AProxy: Pzwp_primary_selection_offer_v1; mime_type: PAnsiChar; fd: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_PRIMARY_SELECTION_OFFER_V1_RECEIVE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, mime_type, fd);
end;

procedure zwp_primary_selection_offer_v1_destroy(AProxy: Pzwp_primary_selection_offer_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_PRIMARY_SELECTION_OFFER_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure zwp_primary_selection_source_v1_offer(AProxy: Pzwp_primary_selection_source_v1; mime_type: PAnsiChar);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_PRIMARY_SELECTION_SOURCE_V1_OFFER_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, mime_type);
end;

procedure zwp_primary_selection_source_v1_destroy(AProxy: Pzwp_primary_selection_source_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_PRIMARY_SELECTION_SOURCE_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;

  zwp_primary_selection_device_manager_v1_interface := @GIface_zwp_primary_selection_device_manager_v1;
  zwp_primary_selection_device_v1_interface := @GIface_zwp_primary_selection_device_v1;
  zwp_primary_selection_offer_v1_interface := @GIface_zwp_primary_selection_offer_v1;
  zwp_primary_selection_source_v1_interface := @GIface_zwp_primary_selection_source_v1;
  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[2] := zwp_primary_selection_source_v1_interface;
  GTypes[3] := zwp_primary_selection_device_v1_interface;
  GTypes[4] := wl_seat_interface;
  GTypes[5] := zwp_primary_selection_source_v1_interface;
  GTypes[7] := zwp_primary_selection_offer_v1_interface;
  GTypes[8] := zwp_primary_selection_offer_v1_interface;

  GReq_zwp_primary_selection_device_manager_v1[0].name := 'create_source';
  GReq_zwp_primary_selection_device_manager_v1[0].signature := 'n';
  GReq_zwp_primary_selection_device_manager_v1[0].types := @GTypes[2];
  GReq_zwp_primary_selection_device_manager_v1[1].name := 'get_device';
  GReq_zwp_primary_selection_device_manager_v1[1].signature := 'no';
  GReq_zwp_primary_selection_device_manager_v1[1].types := @GTypes[3];
  GReq_zwp_primary_selection_device_manager_v1[2].name := 'destroy';
  GReq_zwp_primary_selection_device_manager_v1[2].signature := '';
  GReq_zwp_primary_selection_device_manager_v1[2].types := @GTypes[0];
  GIface_zwp_primary_selection_device_manager_v1.name := 'zwp_primary_selection_device_manager_v1';
  GIface_zwp_primary_selection_device_manager_v1.version := 1;
  GIface_zwp_primary_selection_device_manager_v1.method_count := 3;
  GIface_zwp_primary_selection_device_manager_v1.methods := @GReq_zwp_primary_selection_device_manager_v1[0];
  GIface_zwp_primary_selection_device_manager_v1.event_count := 0;
  GIface_zwp_primary_selection_device_manager_v1.events := nil;

  GReq_zwp_primary_selection_device_v1[0].name := 'set_selection';
  GReq_zwp_primary_selection_device_v1[0].signature := '?ou';
  GReq_zwp_primary_selection_device_v1[0].types := @GTypes[5];
  GReq_zwp_primary_selection_device_v1[1].name := 'destroy';
  GReq_zwp_primary_selection_device_v1[1].signature := '';
  GReq_zwp_primary_selection_device_v1[1].types := @GTypes[0];
  GEvt_zwp_primary_selection_device_v1[0].name := 'data_offer';
  GEvt_zwp_primary_selection_device_v1[0].signature := 'n';
  GEvt_zwp_primary_selection_device_v1[0].types := @GTypes[7];
  GEvt_zwp_primary_selection_device_v1[1].name := 'selection';
  GEvt_zwp_primary_selection_device_v1[1].signature := '?o';
  GEvt_zwp_primary_selection_device_v1[1].types := @GTypes[8];
  GIface_zwp_primary_selection_device_v1.name := 'zwp_primary_selection_device_v1';
  GIface_zwp_primary_selection_device_v1.version := 1;
  GIface_zwp_primary_selection_device_v1.method_count := 2;
  GIface_zwp_primary_selection_device_v1.methods := @GReq_zwp_primary_selection_device_v1[0];
  GIface_zwp_primary_selection_device_v1.event_count := 2;
  GIface_zwp_primary_selection_device_v1.events := @GEvt_zwp_primary_selection_device_v1[0];

  GReq_zwp_primary_selection_offer_v1[0].name := 'receive';
  GReq_zwp_primary_selection_offer_v1[0].signature := 'sh';
  GReq_zwp_primary_selection_offer_v1[0].types := @GTypes[0];
  GReq_zwp_primary_selection_offer_v1[1].name := 'destroy';
  GReq_zwp_primary_selection_offer_v1[1].signature := '';
  GReq_zwp_primary_selection_offer_v1[1].types := @GTypes[0];
  GEvt_zwp_primary_selection_offer_v1[0].name := 'offer';
  GEvt_zwp_primary_selection_offer_v1[0].signature := 's';
  GEvt_zwp_primary_selection_offer_v1[0].types := @GTypes[0];
  GIface_zwp_primary_selection_offer_v1.name := 'zwp_primary_selection_offer_v1';
  GIface_zwp_primary_selection_offer_v1.version := 1;
  GIface_zwp_primary_selection_offer_v1.method_count := 2;
  GIface_zwp_primary_selection_offer_v1.methods := @GReq_zwp_primary_selection_offer_v1[0];
  GIface_zwp_primary_selection_offer_v1.event_count := 1;
  GIface_zwp_primary_selection_offer_v1.events := @GEvt_zwp_primary_selection_offer_v1[0];

  GReq_zwp_primary_selection_source_v1[0].name := 'offer';
  GReq_zwp_primary_selection_source_v1[0].signature := 's';
  GReq_zwp_primary_selection_source_v1[0].types := @GTypes[0];
  GReq_zwp_primary_selection_source_v1[1].name := 'destroy';
  GReq_zwp_primary_selection_source_v1[1].signature := '';
  GReq_zwp_primary_selection_source_v1[1].types := @GTypes[0];
  GEvt_zwp_primary_selection_source_v1[0].name := 'send';
  GEvt_zwp_primary_selection_source_v1[0].signature := 'sh';
  GEvt_zwp_primary_selection_source_v1[0].types := @GTypes[0];
  GEvt_zwp_primary_selection_source_v1[1].name := 'cancelled';
  GEvt_zwp_primary_selection_source_v1[1].signature := '';
  GEvt_zwp_primary_selection_source_v1[1].types := @GTypes[0];
  GIface_zwp_primary_selection_source_v1.name := 'zwp_primary_selection_source_v1';
  GIface_zwp_primary_selection_source_v1.version := 1;
  GIface_zwp_primary_selection_source_v1.method_count := 2;
  GIface_zwp_primary_selection_source_v1.methods := @GReq_zwp_primary_selection_source_v1[0];
  GIface_zwp_primary_selection_source_v1.event_count := 2;
  GIface_zwp_primary_selection_source_v1.events := @GEvt_zwp_primary_selection_source_v1[0];

  GThunks_zwp_primary_selection_device_v1.data_offer := @Thunk_zwp_primary_selection_device_v1_data_offer;
  GThunks_zwp_primary_selection_device_v1.selection := @Thunk_zwp_primary_selection_device_v1_selection;
  GThunks_zwp_primary_selection_offer_v1.offer := @Thunk_zwp_primary_selection_offer_v1_offer;
  GThunks_zwp_primary_selection_source_v1.send := @Thunk_zwp_primary_selection_source_v1_send;
  GThunks_zwp_primary_selection_source_v1.cancelled := @Thunk_zwp_primary_selection_source_v1_cancelled;
end;

end.
