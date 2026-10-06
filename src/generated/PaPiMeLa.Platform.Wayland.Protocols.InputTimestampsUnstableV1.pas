{
  PaPiMeLa.Platform.Wayland.Protocols.InputTimestampsUnstableV1

  自動生成ファイル。手で編集しないこと。
  生成元: input_timestamps_unstable_v1.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright � 2017 Collabora, Ltd.
  
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
unit PaPiMeLa.Platform.Wayland.Protocols.InputTimestampsUnstableV1;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  Tzwp_input_timestamps_manager_v1_opaque = record end;
  Pzwp_input_timestamps_manager_v1 = ^Tzwp_input_timestamps_manager_v1_opaque;
  Tzwp_input_timestamps_v1_opaque = record end;
  Pzwp_input_timestamps_v1 = ^Tzwp_input_timestamps_v1_opaque;

const
  // zwp_input_timestamps_manager_v1 (version 1)
  ZWP_INPUT_TIMESTAMPS_MANAGER_V1_DESTROY_OPCODE = 0;
  ZWP_INPUT_TIMESTAMPS_MANAGER_V1_GET_KEYBOARD_TIMESTAMPS_OPCODE = 1;
  ZWP_INPUT_TIMESTAMPS_MANAGER_V1_GET_POINTER_TIMESTAMPS_OPCODE = 2;
  ZWP_INPUT_TIMESTAMPS_MANAGER_V1_GET_TOUCH_TIMESTAMPS_OPCODE = 3;
  ZWP_INPUT_TIMESTAMPS_MANAGER_V1_DESTROY_SINCE_VERSION = 1;
  ZWP_INPUT_TIMESTAMPS_MANAGER_V1_GET_KEYBOARD_TIMESTAMPS_SINCE_VERSION = 1;
  ZWP_INPUT_TIMESTAMPS_MANAGER_V1_GET_POINTER_TIMESTAMPS_SINCE_VERSION = 1;
  ZWP_INPUT_TIMESTAMPS_MANAGER_V1_GET_TOUCH_TIMESTAMPS_SINCE_VERSION = 1;

  // zwp_input_timestamps_v1 (version 1)
  ZWP_INPUT_TIMESTAMPS_V1_DESTROY_OPCODE = 0;
  ZWP_INPUT_TIMESTAMPS_V1_DESTROY_SINCE_VERSION = 1;
  ZWP_INPUT_TIMESTAMPS_V1_TIMESTAMP_SINCE_VERSION = 1;

var
  zwp_input_timestamps_manager_v1_interface: Pwl_interface = nil;
  zwp_input_timestamps_v1_interface: Pwl_interface = nil;

type
  Tzwp_input_timestamps_v1_listener = class abstract(TObject)
  public
    procedure timestamp(AProxy: Pzwp_input_timestamps_v1; tv_sec_hi: LongWord; tv_sec_lo: LongWord; tv_nsec: LongWord); virtual;
  end;

  Tzwp_input_timestamps_v1_listener_rec = record
    timestamp: procedure(data: Pointer; AProxy: Pzwp_input_timestamps_v1; tv_sec_hi: LongWord; tv_sec_lo: LongWord; tv_nsec: LongWord); cdecl;
  end;

procedure zwp_input_timestamps_manager_v1_destroy(AProxy: Pzwp_input_timestamps_manager_v1);
function zwp_input_timestamps_manager_v1_get_keyboard_timestamps(AProxy: Pzwp_input_timestamps_manager_v1; keyboard: Pwl_keyboard): Pzwp_input_timestamps_v1;
function zwp_input_timestamps_manager_v1_get_pointer_timestamps(AProxy: Pzwp_input_timestamps_manager_v1; pointer_: Pwl_pointer): Pzwp_input_timestamps_v1;
function zwp_input_timestamps_manager_v1_get_touch_timestamps(AProxy: Pzwp_input_timestamps_manager_v1; touch: Pwl_touch): Pzwp_input_timestamps_v1;

function zwp_input_timestamps_v1_add_listener_object(AProxy: Pzwp_input_timestamps_v1; AListener: Tzwp_input_timestamps_v1_listener): LongInt;
procedure zwp_input_timestamps_v1_destroy(AProxy: Pzwp_input_timestamps_v1);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..8] of Pwl_interface;
  GReq_zwp_input_timestamps_manager_v1: array[0..3] of Twl_message;
  GIface_zwp_input_timestamps_manager_v1: Twl_interface;
  GReq_zwp_input_timestamps_v1: array[0..0] of Twl_message;
  GEvt_zwp_input_timestamps_v1: array[0..0] of Twl_message;
  GIface_zwp_input_timestamps_v1: Twl_interface;

var
  GInitialized: Boolean = False;
  GThunks_zwp_input_timestamps_v1: Tzwp_input_timestamps_v1_listener_rec;

procedure Tzwp_input_timestamps_v1_listener.timestamp(AProxy: Pzwp_input_timestamps_v1; tv_sec_hi: LongWord; tv_sec_lo: LongWord; tv_nsec: LongWord);
begin
end;

procedure Thunk_zwp_input_timestamps_v1_timestamp(data: Pointer; AProxy: Pzwp_input_timestamps_v1; tv_sec_hi: LongWord; tv_sec_lo: LongWord; tv_nsec: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_input_timestamps_v1_listener(data).timestamp(AProxy, tv_sec_hi, tv_sec_lo, tv_nsec);
end;

function zwp_input_timestamps_v1_add_listener_object(AProxy: Pzwp_input_timestamps_v1; AListener: Tzwp_input_timestamps_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_input_timestamps_v1, AListener);
end;

procedure zwp_input_timestamps_manager_v1_destroy(AProxy: Pzwp_input_timestamps_manager_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_INPUT_TIMESTAMPS_MANAGER_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function zwp_input_timestamps_manager_v1_get_keyboard_timestamps(AProxy: Pzwp_input_timestamps_manager_v1; keyboard: Pwl_keyboard): Pzwp_input_timestamps_v1;
begin
  EnsureProtocolInitialized;
  Result := Pzwp_input_timestamps_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_INPUT_TIMESTAMPS_MANAGER_V1_GET_KEYBOARD_TIMESTAMPS_OPCODE, zwp_input_timestamps_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), keyboard));
end;

function zwp_input_timestamps_manager_v1_get_pointer_timestamps(AProxy: Pzwp_input_timestamps_manager_v1; pointer_: Pwl_pointer): Pzwp_input_timestamps_v1;
begin
  EnsureProtocolInitialized;
  Result := Pzwp_input_timestamps_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_INPUT_TIMESTAMPS_MANAGER_V1_GET_POINTER_TIMESTAMPS_OPCODE, zwp_input_timestamps_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), pointer_));
end;

function zwp_input_timestamps_manager_v1_get_touch_timestamps(AProxy: Pzwp_input_timestamps_manager_v1; touch: Pwl_touch): Pzwp_input_timestamps_v1;
begin
  EnsureProtocolInitialized;
  Result := Pzwp_input_timestamps_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_INPUT_TIMESTAMPS_MANAGER_V1_GET_TOUCH_TIMESTAMPS_OPCODE, zwp_input_timestamps_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), touch));
end;

procedure zwp_input_timestamps_v1_destroy(AProxy: Pzwp_input_timestamps_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_INPUT_TIMESTAMPS_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;

  zwp_input_timestamps_manager_v1_interface := @GIface_zwp_input_timestamps_manager_v1;
  zwp_input_timestamps_v1_interface := @GIface_zwp_input_timestamps_v1;
  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[3] := zwp_input_timestamps_v1_interface;
  GTypes[4] := wl_keyboard_interface;
  GTypes[5] := zwp_input_timestamps_v1_interface;
  GTypes[6] := wl_pointer_interface;
  GTypes[7] := zwp_input_timestamps_v1_interface;
  GTypes[8] := wl_touch_interface;

  GReq_zwp_input_timestamps_manager_v1[0].name := 'destroy';
  GReq_zwp_input_timestamps_manager_v1[0].signature := '';
  GReq_zwp_input_timestamps_manager_v1[0].types := @GTypes[0];
  GReq_zwp_input_timestamps_manager_v1[1].name := 'get_keyboard_timestamps';
  GReq_zwp_input_timestamps_manager_v1[1].signature := 'no';
  GReq_zwp_input_timestamps_manager_v1[1].types := @GTypes[3];
  GReq_zwp_input_timestamps_manager_v1[2].name := 'get_pointer_timestamps';
  GReq_zwp_input_timestamps_manager_v1[2].signature := 'no';
  GReq_zwp_input_timestamps_manager_v1[2].types := @GTypes[5];
  GReq_zwp_input_timestamps_manager_v1[3].name := 'get_touch_timestamps';
  GReq_zwp_input_timestamps_manager_v1[3].signature := 'no';
  GReq_zwp_input_timestamps_manager_v1[3].types := @GTypes[7];
  GIface_zwp_input_timestamps_manager_v1.name := 'zwp_input_timestamps_manager_v1';
  GIface_zwp_input_timestamps_manager_v1.version := 1;
  GIface_zwp_input_timestamps_manager_v1.method_count := 4;
  GIface_zwp_input_timestamps_manager_v1.methods := @GReq_zwp_input_timestamps_manager_v1[0];
  GIface_zwp_input_timestamps_manager_v1.event_count := 0;
  GIface_zwp_input_timestamps_manager_v1.events := nil;

  GReq_zwp_input_timestamps_v1[0].name := 'destroy';
  GReq_zwp_input_timestamps_v1[0].signature := '';
  GReq_zwp_input_timestamps_v1[0].types := @GTypes[0];
  GEvt_zwp_input_timestamps_v1[0].name := 'timestamp';
  GEvt_zwp_input_timestamps_v1[0].signature := 'uuu';
  GEvt_zwp_input_timestamps_v1[0].types := @GTypes[0];
  GIface_zwp_input_timestamps_v1.name := 'zwp_input_timestamps_v1';
  GIface_zwp_input_timestamps_v1.version := 1;
  GIface_zwp_input_timestamps_v1.method_count := 1;
  GIface_zwp_input_timestamps_v1.methods := @GReq_zwp_input_timestamps_v1[0];
  GIface_zwp_input_timestamps_v1.event_count := 1;
  GIface_zwp_input_timestamps_v1.events := @GEvt_zwp_input_timestamps_v1[0];

  GThunks_zwp_input_timestamps_v1.timestamp := @Thunk_zwp_input_timestamps_v1_timestamp;
end;

end.
