{
  PaPiMeLa.Platform.Wayland.Protocols.PointerConstraintsUnstableV1

  自動生成ファイル。手で編集しないこと。
  生成元: pointer_constraints_unstable_v1.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright � 2014      Jonas �dahl
      Copyright � 2015      Red Hat Inc.
  
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
unit PaPiMeLa.Platform.Wayland.Protocols.PointerConstraintsUnstableV1;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  Tzwp_pointer_constraints_v1_opaque = record end;
  Pzwp_pointer_constraints_v1 = ^Tzwp_pointer_constraints_v1_opaque;
  Tzwp_locked_pointer_v1_opaque = record end;
  Pzwp_locked_pointer_v1 = ^Tzwp_locked_pointer_v1_opaque;
  Tzwp_confined_pointer_v1_opaque = record end;
  Pzwp_confined_pointer_v1 = ^Tzwp_confined_pointer_v1_opaque;

const
  // zwp_pointer_constraints_v1 (version 1)
  ZWP_POINTER_CONSTRAINTS_V1_DESTROY_OPCODE = 0;
  ZWP_POINTER_CONSTRAINTS_V1_LOCK_POINTER_OPCODE = 1;
  ZWP_POINTER_CONSTRAINTS_V1_CONFINE_POINTER_OPCODE = 2;
  ZWP_POINTER_CONSTRAINTS_V1_DESTROY_SINCE_VERSION = 1;
  ZWP_POINTER_CONSTRAINTS_V1_LOCK_POINTER_SINCE_VERSION = 1;
  ZWP_POINTER_CONSTRAINTS_V1_CONFINE_POINTER_SINCE_VERSION = 1;
  ZWP_POINTER_CONSTRAINTS_V1_ERROR_ALREADY_CONSTRAINED = 1;
  ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_ONESHOT = 1;
  ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_PERSISTENT = 2;

  // zwp_locked_pointer_v1 (version 1)
  ZWP_LOCKED_POINTER_V1_DESTROY_OPCODE = 0;
  ZWP_LOCKED_POINTER_V1_SET_CURSOR_POSITION_HINT_OPCODE = 1;
  ZWP_LOCKED_POINTER_V1_SET_REGION_OPCODE = 2;
  ZWP_LOCKED_POINTER_V1_DESTROY_SINCE_VERSION = 1;
  ZWP_LOCKED_POINTER_V1_SET_CURSOR_POSITION_HINT_SINCE_VERSION = 1;
  ZWP_LOCKED_POINTER_V1_SET_REGION_SINCE_VERSION = 1;
  ZWP_LOCKED_POINTER_V1_LOCKED_SINCE_VERSION = 1;
  ZWP_LOCKED_POINTER_V1_UNLOCKED_SINCE_VERSION = 1;

  // zwp_confined_pointer_v1 (version 1)
  ZWP_CONFINED_POINTER_V1_DESTROY_OPCODE = 0;
  ZWP_CONFINED_POINTER_V1_SET_REGION_OPCODE = 1;
  ZWP_CONFINED_POINTER_V1_DESTROY_SINCE_VERSION = 1;
  ZWP_CONFINED_POINTER_V1_SET_REGION_SINCE_VERSION = 1;
  ZWP_CONFINED_POINTER_V1_CONFINED_SINCE_VERSION = 1;
  ZWP_CONFINED_POINTER_V1_UNCONFINED_SINCE_VERSION = 1;

var
  zwp_pointer_constraints_v1_interface: Pwl_interface = nil;
  zwp_locked_pointer_v1_interface: Pwl_interface = nil;
  zwp_confined_pointer_v1_interface: Pwl_interface = nil;

type
  Tzwp_locked_pointer_v1_listener = class abstract(TObject)
  public
    procedure locked(AProxy: Pzwp_locked_pointer_v1); virtual;
    procedure unlocked(AProxy: Pzwp_locked_pointer_v1); virtual;
  end;

  Tzwp_locked_pointer_v1_listener_rec = record
    locked: procedure(data: Pointer; AProxy: Pzwp_locked_pointer_v1); cdecl;
    unlocked: procedure(data: Pointer; AProxy: Pzwp_locked_pointer_v1); cdecl;
  end;

  Tzwp_confined_pointer_v1_listener = class abstract(TObject)
  public
    procedure confined(AProxy: Pzwp_confined_pointer_v1); virtual;
    procedure unconfined(AProxy: Pzwp_confined_pointer_v1); virtual;
  end;

  Tzwp_confined_pointer_v1_listener_rec = record
    confined: procedure(data: Pointer; AProxy: Pzwp_confined_pointer_v1); cdecl;
    unconfined: procedure(data: Pointer; AProxy: Pzwp_confined_pointer_v1); cdecl;
  end;

procedure zwp_pointer_constraints_v1_destroy(AProxy: Pzwp_pointer_constraints_v1);
function zwp_pointer_constraints_v1_lock_pointer(AProxy: Pzwp_pointer_constraints_v1; surface: Pwl_surface; pointer_: Pwl_pointer; region: Pwl_region; lifetime: LongWord): Pzwp_locked_pointer_v1;
function zwp_pointer_constraints_v1_confine_pointer(AProxy: Pzwp_pointer_constraints_v1; surface: Pwl_surface; pointer_: Pwl_pointer; region: Pwl_region; lifetime: LongWord): Pzwp_confined_pointer_v1;

function zwp_locked_pointer_v1_add_listener_object(AProxy: Pzwp_locked_pointer_v1; AListener: Tzwp_locked_pointer_v1_listener): LongInt;
procedure zwp_locked_pointer_v1_destroy(AProxy: Pzwp_locked_pointer_v1);
procedure zwp_locked_pointer_v1_set_cursor_position_hint(AProxy: Pzwp_locked_pointer_v1; surface_x: wl_fixed_t; surface_y: wl_fixed_t);
procedure zwp_locked_pointer_v1_set_region(AProxy: Pzwp_locked_pointer_v1; region: Pwl_region);

function zwp_confined_pointer_v1_add_listener_object(AProxy: Pzwp_confined_pointer_v1; AListener: Tzwp_confined_pointer_v1_listener): LongInt;
procedure zwp_confined_pointer_v1_destroy(AProxy: Pzwp_confined_pointer_v1);
procedure zwp_confined_pointer_v1_set_region(AProxy: Pzwp_confined_pointer_v1; region: Pwl_region);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..13] of Pwl_interface;
  GReq_zwp_pointer_constraints_v1: array[0..2] of Twl_message;
  GIface_zwp_pointer_constraints_v1: Twl_interface;
  GReq_zwp_locked_pointer_v1: array[0..2] of Twl_message;
  GEvt_zwp_locked_pointer_v1: array[0..1] of Twl_message;
  GIface_zwp_locked_pointer_v1: Twl_interface;
  GReq_zwp_confined_pointer_v1: array[0..1] of Twl_message;
  GEvt_zwp_confined_pointer_v1: array[0..1] of Twl_message;
  GIface_zwp_confined_pointer_v1: Twl_interface;

var
  GInitialized: Boolean = False;
  GThunks_zwp_locked_pointer_v1: Tzwp_locked_pointer_v1_listener_rec;
  GThunks_zwp_confined_pointer_v1: Tzwp_confined_pointer_v1_listener_rec;

procedure Tzwp_locked_pointer_v1_listener.locked(AProxy: Pzwp_locked_pointer_v1);
begin
end;

procedure Tzwp_locked_pointer_v1_listener.unlocked(AProxy: Pzwp_locked_pointer_v1);
begin
end;

procedure Tzwp_confined_pointer_v1_listener.confined(AProxy: Pzwp_confined_pointer_v1);
begin
end;

procedure Tzwp_confined_pointer_v1_listener.unconfined(AProxy: Pzwp_confined_pointer_v1);
begin
end;

procedure Thunk_zwp_locked_pointer_v1_locked(data: Pointer; AProxy: Pzwp_locked_pointer_v1); cdecl;
begin
  if data <> nil then
    Tzwp_locked_pointer_v1_listener(data).locked(AProxy);
end;

procedure Thunk_zwp_locked_pointer_v1_unlocked(data: Pointer; AProxy: Pzwp_locked_pointer_v1); cdecl;
begin
  if data <> nil then
    Tzwp_locked_pointer_v1_listener(data).unlocked(AProxy);
end;

procedure Thunk_zwp_confined_pointer_v1_confined(data: Pointer; AProxy: Pzwp_confined_pointer_v1); cdecl;
begin
  if data <> nil then
    Tzwp_confined_pointer_v1_listener(data).confined(AProxy);
end;

procedure Thunk_zwp_confined_pointer_v1_unconfined(data: Pointer; AProxy: Pzwp_confined_pointer_v1); cdecl;
begin
  if data <> nil then
    Tzwp_confined_pointer_v1_listener(data).unconfined(AProxy);
end;

function zwp_locked_pointer_v1_add_listener_object(AProxy: Pzwp_locked_pointer_v1; AListener: Tzwp_locked_pointer_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_locked_pointer_v1, AListener);
end;

function zwp_confined_pointer_v1_add_listener_object(AProxy: Pzwp_confined_pointer_v1; AListener: Tzwp_confined_pointer_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_confined_pointer_v1, AListener);
end;

procedure zwp_pointer_constraints_v1_destroy(AProxy: Pzwp_pointer_constraints_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_POINTER_CONSTRAINTS_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function zwp_pointer_constraints_v1_lock_pointer(AProxy: Pzwp_pointer_constraints_v1; surface: Pwl_surface; pointer_: Pwl_pointer; region: Pwl_region; lifetime: LongWord): Pzwp_locked_pointer_v1;
begin
  EnsureProtocolInitialized;
  Result := Pzwp_locked_pointer_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_POINTER_CONSTRAINTS_V1_LOCK_POINTER_OPCODE, zwp_locked_pointer_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), surface, pointer_, region, lifetime));
end;

function zwp_pointer_constraints_v1_confine_pointer(AProxy: Pzwp_pointer_constraints_v1; surface: Pwl_surface; pointer_: Pwl_pointer; region: Pwl_region; lifetime: LongWord): Pzwp_confined_pointer_v1;
begin
  EnsureProtocolInitialized;
  Result := Pzwp_confined_pointer_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_POINTER_CONSTRAINTS_V1_CONFINE_POINTER_OPCODE, zwp_confined_pointer_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), surface, pointer_, region, lifetime));
end;

procedure zwp_locked_pointer_v1_destroy(AProxy: Pzwp_locked_pointer_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_LOCKED_POINTER_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure zwp_locked_pointer_v1_set_cursor_position_hint(AProxy: Pzwp_locked_pointer_v1; surface_x: wl_fixed_t; surface_y: wl_fixed_t);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_LOCKED_POINTER_V1_SET_CURSOR_POSITION_HINT_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, surface_x, surface_y);
end;

procedure zwp_locked_pointer_v1_set_region(AProxy: Pzwp_locked_pointer_v1; region: Pwl_region);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_LOCKED_POINTER_V1_SET_REGION_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, region);
end;

procedure zwp_confined_pointer_v1_destroy(AProxy: Pzwp_confined_pointer_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_CONFINED_POINTER_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure zwp_confined_pointer_v1_set_region(AProxy: Pzwp_confined_pointer_v1; region: Pwl_region);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_CONFINED_POINTER_V1_SET_REGION_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, region);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;

  zwp_pointer_constraints_v1_interface := @GIface_zwp_pointer_constraints_v1;
  zwp_locked_pointer_v1_interface := @GIface_zwp_locked_pointer_v1;
  zwp_confined_pointer_v1_interface := @GIface_zwp_confined_pointer_v1;
  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[2] := zwp_locked_pointer_v1_interface;
  GTypes[3] := wl_surface_interface;
  GTypes[4] := wl_pointer_interface;
  GTypes[5] := wl_region_interface;
  GTypes[7] := zwp_confined_pointer_v1_interface;
  GTypes[8] := wl_surface_interface;
  GTypes[9] := wl_pointer_interface;
  GTypes[10] := wl_region_interface;
  GTypes[12] := wl_region_interface;
  GTypes[13] := wl_region_interface;

  GReq_zwp_pointer_constraints_v1[0].name := 'destroy';
  GReq_zwp_pointer_constraints_v1[0].signature := '';
  GReq_zwp_pointer_constraints_v1[0].types := @GTypes[0];
  GReq_zwp_pointer_constraints_v1[1].name := 'lock_pointer';
  GReq_zwp_pointer_constraints_v1[1].signature := 'noo?ou';
  GReq_zwp_pointer_constraints_v1[1].types := @GTypes[2];
  GReq_zwp_pointer_constraints_v1[2].name := 'confine_pointer';
  GReq_zwp_pointer_constraints_v1[2].signature := 'noo?ou';
  GReq_zwp_pointer_constraints_v1[2].types := @GTypes[7];
  GIface_zwp_pointer_constraints_v1.name := 'zwp_pointer_constraints_v1';
  GIface_zwp_pointer_constraints_v1.version := 1;
  GIface_zwp_pointer_constraints_v1.method_count := 3;
  GIface_zwp_pointer_constraints_v1.methods := @GReq_zwp_pointer_constraints_v1[0];
  GIface_zwp_pointer_constraints_v1.event_count := 0;
  GIface_zwp_pointer_constraints_v1.events := nil;

  GReq_zwp_locked_pointer_v1[0].name := 'destroy';
  GReq_zwp_locked_pointer_v1[0].signature := '';
  GReq_zwp_locked_pointer_v1[0].types := @GTypes[0];
  GReq_zwp_locked_pointer_v1[1].name := 'set_cursor_position_hint';
  GReq_zwp_locked_pointer_v1[1].signature := 'ff';
  GReq_zwp_locked_pointer_v1[1].types := @GTypes[0];
  GReq_zwp_locked_pointer_v1[2].name := 'set_region';
  GReq_zwp_locked_pointer_v1[2].signature := '?o';
  GReq_zwp_locked_pointer_v1[2].types := @GTypes[12];
  GEvt_zwp_locked_pointer_v1[0].name := 'locked';
  GEvt_zwp_locked_pointer_v1[0].signature := '';
  GEvt_zwp_locked_pointer_v1[0].types := @GTypes[0];
  GEvt_zwp_locked_pointer_v1[1].name := 'unlocked';
  GEvt_zwp_locked_pointer_v1[1].signature := '';
  GEvt_zwp_locked_pointer_v1[1].types := @GTypes[0];
  GIface_zwp_locked_pointer_v1.name := 'zwp_locked_pointer_v1';
  GIface_zwp_locked_pointer_v1.version := 1;
  GIface_zwp_locked_pointer_v1.method_count := 3;
  GIface_zwp_locked_pointer_v1.methods := @GReq_zwp_locked_pointer_v1[0];
  GIface_zwp_locked_pointer_v1.event_count := 2;
  GIface_zwp_locked_pointer_v1.events := @GEvt_zwp_locked_pointer_v1[0];

  GReq_zwp_confined_pointer_v1[0].name := 'destroy';
  GReq_zwp_confined_pointer_v1[0].signature := '';
  GReq_zwp_confined_pointer_v1[0].types := @GTypes[0];
  GReq_zwp_confined_pointer_v1[1].name := 'set_region';
  GReq_zwp_confined_pointer_v1[1].signature := '?o';
  GReq_zwp_confined_pointer_v1[1].types := @GTypes[13];
  GEvt_zwp_confined_pointer_v1[0].name := 'confined';
  GEvt_zwp_confined_pointer_v1[0].signature := '';
  GEvt_zwp_confined_pointer_v1[0].types := @GTypes[0];
  GEvt_zwp_confined_pointer_v1[1].name := 'unconfined';
  GEvt_zwp_confined_pointer_v1[1].signature := '';
  GEvt_zwp_confined_pointer_v1[1].types := @GTypes[0];
  GIface_zwp_confined_pointer_v1.name := 'zwp_confined_pointer_v1';
  GIface_zwp_confined_pointer_v1.version := 1;
  GIface_zwp_confined_pointer_v1.method_count := 2;
  GIface_zwp_confined_pointer_v1.methods := @GReq_zwp_confined_pointer_v1[0];
  GIface_zwp_confined_pointer_v1.event_count := 2;
  GIface_zwp_confined_pointer_v1.events := @GEvt_zwp_confined_pointer_v1[0];

  GThunks_zwp_locked_pointer_v1.locked := @Thunk_zwp_locked_pointer_v1_locked;
  GThunks_zwp_locked_pointer_v1.unlocked := @Thunk_zwp_locked_pointer_v1_unlocked;
  GThunks_zwp_confined_pointer_v1.confined := @Thunk_zwp_confined_pointer_v1_confined;
  GThunks_zwp_confined_pointer_v1.unconfined := @Thunk_zwp_confined_pointer_v1_unconfined;
end;

end.
