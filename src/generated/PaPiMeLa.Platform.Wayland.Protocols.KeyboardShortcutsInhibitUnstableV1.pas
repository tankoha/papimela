{
  PaPiMeLa.Platform.Wayland.Protocols.KeyboardShortcutsInhibitUnstableV1

  自動生成ファイル。手で編集しないこと。
  生成元: keyboard_shortcuts_inhibit_unstable_v1.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright � 2017 Red Hat Inc.
  
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
unit PaPiMeLa.Platform.Wayland.Protocols.KeyboardShortcutsInhibitUnstableV1;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  Tzwp_keyboard_shortcuts_inhibit_manager_v1_opaque = record end;
  Pzwp_keyboard_shortcuts_inhibit_manager_v1 = ^Tzwp_keyboard_shortcuts_inhibit_manager_v1_opaque;
  Tzwp_keyboard_shortcuts_inhibitor_v1_opaque = record end;
  Pzwp_keyboard_shortcuts_inhibitor_v1 = ^Tzwp_keyboard_shortcuts_inhibitor_v1_opaque;

const
  // zwp_keyboard_shortcuts_inhibit_manager_v1 (version 1)
  ZWP_KEYBOARD_SHORTCUTS_INHIBIT_MANAGER_V1_DESTROY_OPCODE = 0;
  ZWP_KEYBOARD_SHORTCUTS_INHIBIT_MANAGER_V1_INHIBIT_SHORTCUTS_OPCODE = 1;
  ZWP_KEYBOARD_SHORTCUTS_INHIBIT_MANAGER_V1_DESTROY_SINCE_VERSION = 1;
  ZWP_KEYBOARD_SHORTCUTS_INHIBIT_MANAGER_V1_INHIBIT_SHORTCUTS_SINCE_VERSION = 1;
  ZWP_KEYBOARD_SHORTCUTS_INHIBIT_MANAGER_V1_ERROR_ALREADY_INHIBITED = 0;

  // zwp_keyboard_shortcuts_inhibitor_v1 (version 1)
  ZWP_KEYBOARD_SHORTCUTS_INHIBITOR_V1_DESTROY_OPCODE = 0;
  ZWP_KEYBOARD_SHORTCUTS_INHIBITOR_V1_DESTROY_SINCE_VERSION = 1;
  ZWP_KEYBOARD_SHORTCUTS_INHIBITOR_V1_ACTIVE_SINCE_VERSION = 1;
  ZWP_KEYBOARD_SHORTCUTS_INHIBITOR_V1_INACTIVE_SINCE_VERSION = 1;

var
  zwp_keyboard_shortcuts_inhibit_manager_v1_interface: Pwl_interface = nil;
  zwp_keyboard_shortcuts_inhibitor_v1_interface: Pwl_interface = nil;

type
  Tzwp_keyboard_shortcuts_inhibitor_v1_listener = class abstract(TObject)
  public
    procedure active(AProxy: Pzwp_keyboard_shortcuts_inhibitor_v1); virtual;
    procedure inactive(AProxy: Pzwp_keyboard_shortcuts_inhibitor_v1); virtual;
  end;

  Tzwp_keyboard_shortcuts_inhibitor_v1_listener_rec = record
    active: procedure(data: Pointer; AProxy: Pzwp_keyboard_shortcuts_inhibitor_v1); cdecl;
    inactive: procedure(data: Pointer; AProxy: Pzwp_keyboard_shortcuts_inhibitor_v1); cdecl;
  end;

procedure zwp_keyboard_shortcuts_inhibit_manager_v1_destroy(AProxy: Pzwp_keyboard_shortcuts_inhibit_manager_v1);
function zwp_keyboard_shortcuts_inhibit_manager_v1_inhibit_shortcuts(AProxy: Pzwp_keyboard_shortcuts_inhibit_manager_v1; surface: Pwl_surface; seat: Pwl_seat): Pzwp_keyboard_shortcuts_inhibitor_v1;

function zwp_keyboard_shortcuts_inhibitor_v1_add_listener_object(AProxy: Pzwp_keyboard_shortcuts_inhibitor_v1; AListener: Tzwp_keyboard_shortcuts_inhibitor_v1_listener): LongInt;
procedure zwp_keyboard_shortcuts_inhibitor_v1_destroy(AProxy: Pzwp_keyboard_shortcuts_inhibitor_v1);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..2] of Pwl_interface;
  GReq_zwp_keyboard_shortcuts_inhibit_manager_v1: array[0..1] of Twl_message;
  GIface_zwp_keyboard_shortcuts_inhibit_manager_v1: Twl_interface;
  GReq_zwp_keyboard_shortcuts_inhibitor_v1: array[0..0] of Twl_message;
  GEvt_zwp_keyboard_shortcuts_inhibitor_v1: array[0..1] of Twl_message;
  GIface_zwp_keyboard_shortcuts_inhibitor_v1: Twl_interface;

var
  GInitialized: Boolean = False;
  GThunks_zwp_keyboard_shortcuts_inhibitor_v1: Tzwp_keyboard_shortcuts_inhibitor_v1_listener_rec;

procedure Tzwp_keyboard_shortcuts_inhibitor_v1_listener.active(AProxy: Pzwp_keyboard_shortcuts_inhibitor_v1);
begin
end;

procedure Tzwp_keyboard_shortcuts_inhibitor_v1_listener.inactive(AProxy: Pzwp_keyboard_shortcuts_inhibitor_v1);
begin
end;

procedure Thunk_zwp_keyboard_shortcuts_inhibitor_v1_active(data: Pointer; AProxy: Pzwp_keyboard_shortcuts_inhibitor_v1); cdecl;
begin
  if data <> nil then
    Tzwp_keyboard_shortcuts_inhibitor_v1_listener(data).active(AProxy);
end;

procedure Thunk_zwp_keyboard_shortcuts_inhibitor_v1_inactive(data: Pointer; AProxy: Pzwp_keyboard_shortcuts_inhibitor_v1); cdecl;
begin
  if data <> nil then
    Tzwp_keyboard_shortcuts_inhibitor_v1_listener(data).inactive(AProxy);
end;

function zwp_keyboard_shortcuts_inhibitor_v1_add_listener_object(AProxy: Pzwp_keyboard_shortcuts_inhibitor_v1; AListener: Tzwp_keyboard_shortcuts_inhibitor_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_keyboard_shortcuts_inhibitor_v1, AListener);
end;

procedure zwp_keyboard_shortcuts_inhibit_manager_v1_destroy(AProxy: Pzwp_keyboard_shortcuts_inhibit_manager_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_KEYBOARD_SHORTCUTS_INHIBIT_MANAGER_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function zwp_keyboard_shortcuts_inhibit_manager_v1_inhibit_shortcuts(AProxy: Pzwp_keyboard_shortcuts_inhibit_manager_v1; surface: Pwl_surface; seat: Pwl_seat): Pzwp_keyboard_shortcuts_inhibitor_v1;
begin
  EnsureProtocolInitialized;
  Result := Pzwp_keyboard_shortcuts_inhibitor_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_KEYBOARD_SHORTCUTS_INHIBIT_MANAGER_V1_INHIBIT_SHORTCUTS_OPCODE, zwp_keyboard_shortcuts_inhibitor_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), surface, seat));
end;

procedure zwp_keyboard_shortcuts_inhibitor_v1_destroy(AProxy: Pzwp_keyboard_shortcuts_inhibitor_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_KEYBOARD_SHORTCUTS_INHIBITOR_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;

  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[0] := zwp_keyboard_shortcuts_inhibitor_v1_interface;
  GTypes[1] := wl_surface_interface;
  GTypes[2] := wl_seat_interface;

  GReq_zwp_keyboard_shortcuts_inhibit_manager_v1[0].name := 'destroy';
  GReq_zwp_keyboard_shortcuts_inhibit_manager_v1[0].signature := '';
  GReq_zwp_keyboard_shortcuts_inhibit_manager_v1[0].types := @GTypes[0];
  GReq_zwp_keyboard_shortcuts_inhibit_manager_v1[1].name := 'inhibit_shortcuts';
  GReq_zwp_keyboard_shortcuts_inhibit_manager_v1[1].signature := 'noo';
  GReq_zwp_keyboard_shortcuts_inhibit_manager_v1[1].types := @GTypes[0];
  GIface_zwp_keyboard_shortcuts_inhibit_manager_v1.name := 'zwp_keyboard_shortcuts_inhibit_manager_v1';
  GIface_zwp_keyboard_shortcuts_inhibit_manager_v1.version := 1;
  GIface_zwp_keyboard_shortcuts_inhibit_manager_v1.method_count := 2;
  GIface_zwp_keyboard_shortcuts_inhibit_manager_v1.methods := @GReq_zwp_keyboard_shortcuts_inhibit_manager_v1[0];
  GIface_zwp_keyboard_shortcuts_inhibit_manager_v1.event_count := 0;
  GIface_zwp_keyboard_shortcuts_inhibit_manager_v1.events := nil;
  zwp_keyboard_shortcuts_inhibit_manager_v1_interface := @GIface_zwp_keyboard_shortcuts_inhibit_manager_v1;

  GReq_zwp_keyboard_shortcuts_inhibitor_v1[0].name := 'destroy';
  GReq_zwp_keyboard_shortcuts_inhibitor_v1[0].signature := '';
  GReq_zwp_keyboard_shortcuts_inhibitor_v1[0].types := @GTypes[0];
  GEvt_zwp_keyboard_shortcuts_inhibitor_v1[0].name := 'active';
  GEvt_zwp_keyboard_shortcuts_inhibitor_v1[0].signature := '';
  GEvt_zwp_keyboard_shortcuts_inhibitor_v1[0].types := @GTypes[0];
  GEvt_zwp_keyboard_shortcuts_inhibitor_v1[1].name := 'inactive';
  GEvt_zwp_keyboard_shortcuts_inhibitor_v1[1].signature := '';
  GEvt_zwp_keyboard_shortcuts_inhibitor_v1[1].types := @GTypes[0];
  GIface_zwp_keyboard_shortcuts_inhibitor_v1.name := 'zwp_keyboard_shortcuts_inhibitor_v1';
  GIface_zwp_keyboard_shortcuts_inhibitor_v1.version := 1;
  GIface_zwp_keyboard_shortcuts_inhibitor_v1.method_count := 1;
  GIface_zwp_keyboard_shortcuts_inhibitor_v1.methods := @GReq_zwp_keyboard_shortcuts_inhibitor_v1[0];
  GIface_zwp_keyboard_shortcuts_inhibitor_v1.event_count := 2;
  GIface_zwp_keyboard_shortcuts_inhibitor_v1.events := @GEvt_zwp_keyboard_shortcuts_inhibitor_v1[0];
  zwp_keyboard_shortcuts_inhibitor_v1_interface := @GIface_zwp_keyboard_shortcuts_inhibitor_v1;

  GThunks_zwp_keyboard_shortcuts_inhibitor_v1.active := @Thunk_zwp_keyboard_shortcuts_inhibitor_v1_active;
  GThunks_zwp_keyboard_shortcuts_inhibitor_v1.inactive := @Thunk_zwp_keyboard_shortcuts_inhibitor_v1_inactive;
end;

end.
