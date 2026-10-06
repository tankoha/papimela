{
  PaPiMeLa.Platform.Wayland.Protocols.TabletV2

  自動生成ファイル。手で編集しないこと。
  生成元: tablet_v2.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright 2014 � Stephen "Lyude" Chandler Paul
      Copyright 2015-2016 � Red Hat, Inc.
  
      Permission is hereby granted, free of charge, to any person
      obtaining a copy of this software and associated documentation files
      (the "Software"), to deal in the Software without restriction,
      including without limitation the rights to use, copy, modify, merge,
      publish, distribute, sublicense, and/or sell copies of the Software,
      and to permit persons to whom the Software is furnished to do so,
      subject to the following conditions:
  
      The above copyright notice and this permission notice (including the
      next paragraph) shall be included in all copies or substantial
      portions of the Software.
  
      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
      EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
      MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
      NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
      BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
      ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
      CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
      SOFTWARE.

}
unit PaPiMeLa.Platform.Wayland.Protocols.TabletV2;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  Tzwp_tablet_manager_v2_opaque = record end;
  Pzwp_tablet_manager_v2 = ^Tzwp_tablet_manager_v2_opaque;
  Tzwp_tablet_seat_v2_opaque = record end;
  Pzwp_tablet_seat_v2 = ^Tzwp_tablet_seat_v2_opaque;
  Tzwp_tablet_tool_v2_opaque = record end;
  Pzwp_tablet_tool_v2 = ^Tzwp_tablet_tool_v2_opaque;
  Tzwp_tablet_v2_opaque = record end;
  Pzwp_tablet_v2 = ^Tzwp_tablet_v2_opaque;
  Tzwp_tablet_pad_ring_v2_opaque = record end;
  Pzwp_tablet_pad_ring_v2 = ^Tzwp_tablet_pad_ring_v2_opaque;
  Tzwp_tablet_pad_strip_v2_opaque = record end;
  Pzwp_tablet_pad_strip_v2 = ^Tzwp_tablet_pad_strip_v2_opaque;
  Tzwp_tablet_pad_group_v2_opaque = record end;
  Pzwp_tablet_pad_group_v2 = ^Tzwp_tablet_pad_group_v2_opaque;
  Tzwp_tablet_pad_v2_opaque = record end;
  Pzwp_tablet_pad_v2 = ^Tzwp_tablet_pad_v2_opaque;

const
  // zwp_tablet_manager_v2 (version 1)
  ZWP_TABLET_MANAGER_V2_GET_TABLET_SEAT_OPCODE = 0;
  ZWP_TABLET_MANAGER_V2_DESTROY_OPCODE = 1;
  ZWP_TABLET_MANAGER_V2_GET_TABLET_SEAT_SINCE_VERSION = 1;
  ZWP_TABLET_MANAGER_V2_DESTROY_SINCE_VERSION = 1;

  // zwp_tablet_seat_v2 (version 1)
  ZWP_TABLET_SEAT_V2_DESTROY_OPCODE = 0;
  ZWP_TABLET_SEAT_V2_DESTROY_SINCE_VERSION = 1;
  ZWP_TABLET_SEAT_V2_TABLET_ADDED_SINCE_VERSION = 1;
  ZWP_TABLET_SEAT_V2_TOOL_ADDED_SINCE_VERSION = 1;
  ZWP_TABLET_SEAT_V2_PAD_ADDED_SINCE_VERSION = 1;

  // zwp_tablet_tool_v2 (version 1)
  ZWP_TABLET_TOOL_V2_SET_CURSOR_OPCODE = 0;
  ZWP_TABLET_TOOL_V2_DESTROY_OPCODE = 1;
  ZWP_TABLET_TOOL_V2_SET_CURSOR_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_DESTROY_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_TYPE_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_HARDWARE_SERIAL_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_HARDWARE_ID_WACOM_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_CAPABILITY_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_DONE_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_REMOVED_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_PROXIMITY_IN_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_PROXIMITY_OUT_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_DOWN_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_UP_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_MOTION_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_PRESSURE_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_DISTANCE_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_TILT_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_ROTATION_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_SLIDER_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_WHEEL_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_BUTTON_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_FRAME_SINCE_VERSION = 1;
  ZWP_TABLET_TOOL_V2_TYPE_PEN = $140;
  ZWP_TABLET_TOOL_V2_TYPE_ERASER = $141;
  ZWP_TABLET_TOOL_V2_TYPE_BRUSH = $142;
  ZWP_TABLET_TOOL_V2_TYPE_PENCIL = $143;
  ZWP_TABLET_TOOL_V2_TYPE_AIRBRUSH = $144;
  ZWP_TABLET_TOOL_V2_TYPE_FINGER = $145;
  ZWP_TABLET_TOOL_V2_TYPE_MOUSE = $146;
  ZWP_TABLET_TOOL_V2_TYPE_LENS = $147;
  ZWP_TABLET_TOOL_V2_CAPABILITY_TILT = 1;
  ZWP_TABLET_TOOL_V2_CAPABILITY_PRESSURE = 2;
  ZWP_TABLET_TOOL_V2_CAPABILITY_DISTANCE = 3;
  ZWP_TABLET_TOOL_V2_CAPABILITY_ROTATION = 4;
  ZWP_TABLET_TOOL_V2_CAPABILITY_SLIDER = 5;
  ZWP_TABLET_TOOL_V2_CAPABILITY_WHEEL = 6;
  ZWP_TABLET_TOOL_V2_BUTTON_STATE_RELEASED = 0;
  ZWP_TABLET_TOOL_V2_BUTTON_STATE_PRESSED = 1;
  ZWP_TABLET_TOOL_V2_ERROR_ROLE = 0;

  // zwp_tablet_v2 (version 1)
  ZWP_TABLET_V2_DESTROY_OPCODE = 0;
  ZWP_TABLET_V2_DESTROY_SINCE_VERSION = 1;
  ZWP_TABLET_V2_NAME_SINCE_VERSION = 1;
  ZWP_TABLET_V2_ID_SINCE_VERSION = 1;
  ZWP_TABLET_V2_PATH_SINCE_VERSION = 1;
  ZWP_TABLET_V2_DONE_SINCE_VERSION = 1;
  ZWP_TABLET_V2_REMOVED_SINCE_VERSION = 1;

  // zwp_tablet_pad_ring_v2 (version 1)
  ZWP_TABLET_PAD_RING_V2_SET_FEEDBACK_OPCODE = 0;
  ZWP_TABLET_PAD_RING_V2_DESTROY_OPCODE = 1;
  ZWP_TABLET_PAD_RING_V2_SET_FEEDBACK_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_RING_V2_DESTROY_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_RING_V2_SOURCE_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_RING_V2_ANGLE_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_RING_V2_STOP_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_RING_V2_FRAME_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_RING_V2_SOURCE_FINGER = 1;

  // zwp_tablet_pad_strip_v2 (version 1)
  ZWP_TABLET_PAD_STRIP_V2_SET_FEEDBACK_OPCODE = 0;
  ZWP_TABLET_PAD_STRIP_V2_DESTROY_OPCODE = 1;
  ZWP_TABLET_PAD_STRIP_V2_SET_FEEDBACK_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_STRIP_V2_DESTROY_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_STRIP_V2_SOURCE_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_STRIP_V2_POSITION_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_STRIP_V2_STOP_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_STRIP_V2_FRAME_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_STRIP_V2_SOURCE_FINGER = 1;

  // zwp_tablet_pad_group_v2 (version 1)
  ZWP_TABLET_PAD_GROUP_V2_DESTROY_OPCODE = 0;
  ZWP_TABLET_PAD_GROUP_V2_DESTROY_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_GROUP_V2_BUTTONS_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_GROUP_V2_RING_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_GROUP_V2_STRIP_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_GROUP_V2_MODES_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_GROUP_V2_DONE_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_GROUP_V2_MODE_SWITCH_SINCE_VERSION = 1;

  // zwp_tablet_pad_v2 (version 1)
  ZWP_TABLET_PAD_V2_SET_FEEDBACK_OPCODE = 0;
  ZWP_TABLET_PAD_V2_DESTROY_OPCODE = 1;
  ZWP_TABLET_PAD_V2_SET_FEEDBACK_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_V2_DESTROY_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_V2_GROUP_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_V2_PATH_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_V2_BUTTONS_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_V2_DONE_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_V2_BUTTON_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_V2_ENTER_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_V2_LEAVE_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_V2_REMOVED_SINCE_VERSION = 1;
  ZWP_TABLET_PAD_V2_BUTTON_STATE_RELEASED = 0;
  ZWP_TABLET_PAD_V2_BUTTON_STATE_PRESSED = 1;

var
  zwp_tablet_manager_v2_interface: Pwl_interface = nil;
  zwp_tablet_seat_v2_interface: Pwl_interface = nil;
  zwp_tablet_tool_v2_interface: Pwl_interface = nil;
  zwp_tablet_v2_interface: Pwl_interface = nil;
  zwp_tablet_pad_ring_v2_interface: Pwl_interface = nil;
  zwp_tablet_pad_strip_v2_interface: Pwl_interface = nil;
  zwp_tablet_pad_group_v2_interface: Pwl_interface = nil;
  zwp_tablet_pad_v2_interface: Pwl_interface = nil;

type
  Tzwp_tablet_seat_v2_listener = class abstract(TObject)
  public
    procedure tablet_added(AProxy: Pzwp_tablet_seat_v2; id: Pzwp_tablet_v2); virtual;
    procedure tool_added(AProxy: Pzwp_tablet_seat_v2; id: Pzwp_tablet_tool_v2); virtual;
    procedure pad_added(AProxy: Pzwp_tablet_seat_v2; id: Pzwp_tablet_pad_v2); virtual;
  end;

  Tzwp_tablet_seat_v2_listener_rec = record
    tablet_added: procedure(data: Pointer; AProxy: Pzwp_tablet_seat_v2; id: Pzwp_tablet_v2); cdecl;
    tool_added: procedure(data: Pointer; AProxy: Pzwp_tablet_seat_v2; id: Pzwp_tablet_tool_v2); cdecl;
    pad_added: procedure(data: Pointer; AProxy: Pzwp_tablet_seat_v2; id: Pzwp_tablet_pad_v2); cdecl;
  end;

  Tzwp_tablet_tool_v2_listener = class abstract(TObject)
  public
    procedure type_(AProxy: Pzwp_tablet_tool_v2; tool_type: LongWord); virtual;
    procedure hardware_serial(AProxy: Pzwp_tablet_tool_v2; hardware_serial_hi: LongWord; hardware_serial_lo: LongWord); virtual;
    procedure hardware_id_wacom(AProxy: Pzwp_tablet_tool_v2; hardware_id_hi: LongWord; hardware_id_lo: LongWord); virtual;
    procedure capability(AProxy: Pzwp_tablet_tool_v2; capability_: LongWord); virtual;
    procedure done(AProxy: Pzwp_tablet_tool_v2); virtual;
    procedure removed(AProxy: Pzwp_tablet_tool_v2); virtual;
    procedure proximity_in(AProxy: Pzwp_tablet_tool_v2; serial: LongWord; tablet: Pzwp_tablet_v2; surface: Pwl_surface); virtual;
    procedure proximity_out(AProxy: Pzwp_tablet_tool_v2); virtual;
    procedure down(AProxy: Pzwp_tablet_tool_v2; serial: LongWord); virtual;
    procedure up(AProxy: Pzwp_tablet_tool_v2); virtual;
    procedure motion(AProxy: Pzwp_tablet_tool_v2; x: wl_fixed_t; y: wl_fixed_t); virtual;
    procedure pressure(AProxy: Pzwp_tablet_tool_v2; pressure_: LongWord); virtual;
    procedure distance(AProxy: Pzwp_tablet_tool_v2; distance_: LongWord); virtual;
    procedure tilt(AProxy: Pzwp_tablet_tool_v2; tilt_x: wl_fixed_t; tilt_y: wl_fixed_t); virtual;
    procedure rotation(AProxy: Pzwp_tablet_tool_v2; degrees: wl_fixed_t); virtual;
    procedure slider(AProxy: Pzwp_tablet_tool_v2; position: LongInt); virtual;
    procedure wheel(AProxy: Pzwp_tablet_tool_v2; degrees: wl_fixed_t; clicks: LongInt); virtual;
    procedure button(AProxy: Pzwp_tablet_tool_v2; serial: LongWord; button_: LongWord; state: LongWord); virtual;
    procedure frame(AProxy: Pzwp_tablet_tool_v2; time: LongWord); virtual;
  end;

  Tzwp_tablet_tool_v2_listener_rec = record
    type_: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; tool_type: LongWord); cdecl;
    hardware_serial: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; hardware_serial_hi: LongWord; hardware_serial_lo: LongWord); cdecl;
    hardware_id_wacom: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; hardware_id_hi: LongWord; hardware_id_lo: LongWord); cdecl;
    capability: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; capability_: LongWord); cdecl;
    done: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2); cdecl;
    removed: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2); cdecl;
    proximity_in: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; serial: LongWord; tablet: Pzwp_tablet_v2; surface: Pwl_surface); cdecl;
    proximity_out: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2); cdecl;
    down: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; serial: LongWord); cdecl;
    up: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2); cdecl;
    motion: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; x: wl_fixed_t; y: wl_fixed_t); cdecl;
    pressure: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; pressure_: LongWord); cdecl;
    distance: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; distance_: LongWord); cdecl;
    tilt: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; tilt_x: wl_fixed_t; tilt_y: wl_fixed_t); cdecl;
    rotation: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; degrees: wl_fixed_t); cdecl;
    slider: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; position: LongInt); cdecl;
    wheel: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; degrees: wl_fixed_t; clicks: LongInt); cdecl;
    button: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; serial: LongWord; button_: LongWord; state: LongWord); cdecl;
    frame: procedure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; time: LongWord); cdecl;
  end;

  Tzwp_tablet_v2_listener = class abstract(TObject)
  public
    procedure name(AProxy: Pzwp_tablet_v2; name_: PAnsiChar); virtual;
    procedure id(AProxy: Pzwp_tablet_v2; vid: LongWord; pid: LongWord); virtual;
    procedure path(AProxy: Pzwp_tablet_v2; path_: PAnsiChar); virtual;
    procedure done(AProxy: Pzwp_tablet_v2); virtual;
    procedure removed(AProxy: Pzwp_tablet_v2); virtual;
  end;

  Tzwp_tablet_v2_listener_rec = record
    name: procedure(data: Pointer; AProxy: Pzwp_tablet_v2; name_: PAnsiChar); cdecl;
    id: procedure(data: Pointer; AProxy: Pzwp_tablet_v2; vid: LongWord; pid: LongWord); cdecl;
    path: procedure(data: Pointer; AProxy: Pzwp_tablet_v2; path_: PAnsiChar); cdecl;
    done: procedure(data: Pointer; AProxy: Pzwp_tablet_v2); cdecl;
    removed: procedure(data: Pointer; AProxy: Pzwp_tablet_v2); cdecl;
  end;

  Tzwp_tablet_pad_ring_v2_listener = class abstract(TObject)
  public
    procedure source(AProxy: Pzwp_tablet_pad_ring_v2; source_: LongWord); virtual;
    procedure angle(AProxy: Pzwp_tablet_pad_ring_v2; degrees: wl_fixed_t); virtual;
    procedure stop(AProxy: Pzwp_tablet_pad_ring_v2); virtual;
    procedure frame(AProxy: Pzwp_tablet_pad_ring_v2; time: LongWord); virtual;
  end;

  Tzwp_tablet_pad_ring_v2_listener_rec = record
    source: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_ring_v2; source_: LongWord); cdecl;
    angle: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_ring_v2; degrees: wl_fixed_t); cdecl;
    stop: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_ring_v2); cdecl;
    frame: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_ring_v2; time: LongWord); cdecl;
  end;

  Tzwp_tablet_pad_strip_v2_listener = class abstract(TObject)
  public
    procedure source(AProxy: Pzwp_tablet_pad_strip_v2; source_: LongWord); virtual;
    procedure position(AProxy: Pzwp_tablet_pad_strip_v2; position_: LongWord); virtual;
    procedure stop(AProxy: Pzwp_tablet_pad_strip_v2); virtual;
    procedure frame(AProxy: Pzwp_tablet_pad_strip_v2; time: LongWord); virtual;
  end;

  Tzwp_tablet_pad_strip_v2_listener_rec = record
    source: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_strip_v2; source_: LongWord); cdecl;
    position: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_strip_v2; position_: LongWord); cdecl;
    stop: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_strip_v2); cdecl;
    frame: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_strip_v2; time: LongWord); cdecl;
  end;

  Tzwp_tablet_pad_group_v2_listener = class abstract(TObject)
  public
    procedure buttons(AProxy: Pzwp_tablet_pad_group_v2; buttons_: Pwl_array); virtual;
    procedure ring(AProxy: Pzwp_tablet_pad_group_v2; ring_: Pzwp_tablet_pad_ring_v2); virtual;
    procedure strip(AProxy: Pzwp_tablet_pad_group_v2; strip_: Pzwp_tablet_pad_strip_v2); virtual;
    procedure modes(AProxy: Pzwp_tablet_pad_group_v2; modes_: LongWord); virtual;
    procedure done(AProxy: Pzwp_tablet_pad_group_v2); virtual;
    procedure mode_switch(AProxy: Pzwp_tablet_pad_group_v2; time: LongWord; serial: LongWord; mode: LongWord); virtual;
  end;

  Tzwp_tablet_pad_group_v2_listener_rec = record
    buttons: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_group_v2; buttons_: Pwl_array); cdecl;
    ring: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_group_v2; ring_: Pzwp_tablet_pad_ring_v2); cdecl;
    strip: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_group_v2; strip_: Pzwp_tablet_pad_strip_v2); cdecl;
    modes: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_group_v2; modes_: LongWord); cdecl;
    done: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_group_v2); cdecl;
    mode_switch: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_group_v2; time: LongWord; serial: LongWord; mode: LongWord); cdecl;
  end;

  Tzwp_tablet_pad_v2_listener = class abstract(TObject)
  public
    procedure group(AProxy: Pzwp_tablet_pad_v2; pad_group: Pzwp_tablet_pad_group_v2); virtual;
    procedure path(AProxy: Pzwp_tablet_pad_v2; path_: PAnsiChar); virtual;
    procedure buttons(AProxy: Pzwp_tablet_pad_v2; buttons_: LongWord); virtual;
    procedure done(AProxy: Pzwp_tablet_pad_v2); virtual;
    procedure button(AProxy: Pzwp_tablet_pad_v2; time: LongWord; button_: LongWord; state: LongWord); virtual;
    procedure enter(AProxy: Pzwp_tablet_pad_v2; serial: LongWord; tablet: Pzwp_tablet_v2; surface: Pwl_surface); virtual;
    procedure leave(AProxy: Pzwp_tablet_pad_v2; serial: LongWord; surface: Pwl_surface); virtual;
    procedure removed(AProxy: Pzwp_tablet_pad_v2); virtual;
  end;

  Tzwp_tablet_pad_v2_listener_rec = record
    group: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_v2; pad_group: Pzwp_tablet_pad_group_v2); cdecl;
    path: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_v2; path_: PAnsiChar); cdecl;
    buttons: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_v2; buttons_: LongWord); cdecl;
    done: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_v2); cdecl;
    button: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_v2; time: LongWord; button_: LongWord; state: LongWord); cdecl;
    enter: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_v2; serial: LongWord; tablet: Pzwp_tablet_v2; surface: Pwl_surface); cdecl;
    leave: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_v2; serial: LongWord; surface: Pwl_surface); cdecl;
    removed: procedure(data: Pointer; AProxy: Pzwp_tablet_pad_v2); cdecl;
  end;

function zwp_tablet_manager_v2_get_tablet_seat(AProxy: Pzwp_tablet_manager_v2; seat: Pwl_seat): Pzwp_tablet_seat_v2;
procedure zwp_tablet_manager_v2_destroy(AProxy: Pzwp_tablet_manager_v2);

function zwp_tablet_seat_v2_add_listener_object(AProxy: Pzwp_tablet_seat_v2; AListener: Tzwp_tablet_seat_v2_listener): LongInt;
procedure zwp_tablet_seat_v2_destroy(AProxy: Pzwp_tablet_seat_v2);

function zwp_tablet_tool_v2_add_listener_object(AProxy: Pzwp_tablet_tool_v2; AListener: Tzwp_tablet_tool_v2_listener): LongInt;
procedure zwp_tablet_tool_v2_set_cursor(AProxy: Pzwp_tablet_tool_v2; serial: LongWord; surface: Pwl_surface; hotspot_x: LongInt; hotspot_y: LongInt);
procedure zwp_tablet_tool_v2_destroy(AProxy: Pzwp_tablet_tool_v2);

function zwp_tablet_v2_add_listener_object(AProxy: Pzwp_tablet_v2; AListener: Tzwp_tablet_v2_listener): LongInt;
procedure zwp_tablet_v2_destroy(AProxy: Pzwp_tablet_v2);

function zwp_tablet_pad_ring_v2_add_listener_object(AProxy: Pzwp_tablet_pad_ring_v2; AListener: Tzwp_tablet_pad_ring_v2_listener): LongInt;
procedure zwp_tablet_pad_ring_v2_set_feedback(AProxy: Pzwp_tablet_pad_ring_v2; description: PAnsiChar; serial: LongWord);
procedure zwp_tablet_pad_ring_v2_destroy(AProxy: Pzwp_tablet_pad_ring_v2);

function zwp_tablet_pad_strip_v2_add_listener_object(AProxy: Pzwp_tablet_pad_strip_v2; AListener: Tzwp_tablet_pad_strip_v2_listener): LongInt;
procedure zwp_tablet_pad_strip_v2_set_feedback(AProxy: Pzwp_tablet_pad_strip_v2; description: PAnsiChar; serial: LongWord);
procedure zwp_tablet_pad_strip_v2_destroy(AProxy: Pzwp_tablet_pad_strip_v2);

function zwp_tablet_pad_group_v2_add_listener_object(AProxy: Pzwp_tablet_pad_group_v2; AListener: Tzwp_tablet_pad_group_v2_listener): LongInt;
procedure zwp_tablet_pad_group_v2_destroy(AProxy: Pzwp_tablet_pad_group_v2);

function zwp_tablet_pad_v2_add_listener_object(AProxy: Pzwp_tablet_pad_v2; AListener: Tzwp_tablet_pad_v2_listener): LongInt;
procedure zwp_tablet_pad_v2_set_feedback(AProxy: Pzwp_tablet_pad_v2; button_: LongWord; description: PAnsiChar; serial: LongWord);
procedure zwp_tablet_pad_v2_destroy(AProxy: Pzwp_tablet_pad_v2);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..22] of Pwl_interface;
  GReq_zwp_tablet_manager_v2: array[0..1] of Twl_message;
  GIface_zwp_tablet_manager_v2: Twl_interface;
  GReq_zwp_tablet_seat_v2: array[0..0] of Twl_message;
  GEvt_zwp_tablet_seat_v2: array[0..2] of Twl_message;
  GIface_zwp_tablet_seat_v2: Twl_interface;
  GReq_zwp_tablet_tool_v2: array[0..1] of Twl_message;
  GEvt_zwp_tablet_tool_v2: array[0..18] of Twl_message;
  GIface_zwp_tablet_tool_v2: Twl_interface;
  GReq_zwp_tablet_v2: array[0..0] of Twl_message;
  GEvt_zwp_tablet_v2: array[0..4] of Twl_message;
  GIface_zwp_tablet_v2: Twl_interface;
  GReq_zwp_tablet_pad_ring_v2: array[0..1] of Twl_message;
  GEvt_zwp_tablet_pad_ring_v2: array[0..3] of Twl_message;
  GIface_zwp_tablet_pad_ring_v2: Twl_interface;
  GReq_zwp_tablet_pad_strip_v2: array[0..1] of Twl_message;
  GEvt_zwp_tablet_pad_strip_v2: array[0..3] of Twl_message;
  GIface_zwp_tablet_pad_strip_v2: Twl_interface;
  GReq_zwp_tablet_pad_group_v2: array[0..0] of Twl_message;
  GEvt_zwp_tablet_pad_group_v2: array[0..5] of Twl_message;
  GIface_zwp_tablet_pad_group_v2: Twl_interface;
  GReq_zwp_tablet_pad_v2: array[0..1] of Twl_message;
  GEvt_zwp_tablet_pad_v2: array[0..7] of Twl_message;
  GIface_zwp_tablet_pad_v2: Twl_interface;

var
  GInitialized: Boolean = False;
  GThunks_zwp_tablet_seat_v2: Tzwp_tablet_seat_v2_listener_rec;
  GThunks_zwp_tablet_tool_v2: Tzwp_tablet_tool_v2_listener_rec;
  GThunks_zwp_tablet_v2: Tzwp_tablet_v2_listener_rec;
  GThunks_zwp_tablet_pad_ring_v2: Tzwp_tablet_pad_ring_v2_listener_rec;
  GThunks_zwp_tablet_pad_strip_v2: Tzwp_tablet_pad_strip_v2_listener_rec;
  GThunks_zwp_tablet_pad_group_v2: Tzwp_tablet_pad_group_v2_listener_rec;
  GThunks_zwp_tablet_pad_v2: Tzwp_tablet_pad_v2_listener_rec;

procedure Tzwp_tablet_seat_v2_listener.tablet_added(AProxy: Pzwp_tablet_seat_v2; id: Pzwp_tablet_v2);
begin
end;

procedure Tzwp_tablet_seat_v2_listener.tool_added(AProxy: Pzwp_tablet_seat_v2; id: Pzwp_tablet_tool_v2);
begin
end;

procedure Tzwp_tablet_seat_v2_listener.pad_added(AProxy: Pzwp_tablet_seat_v2; id: Pzwp_tablet_pad_v2);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.type_(AProxy: Pzwp_tablet_tool_v2; tool_type: LongWord);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.hardware_serial(AProxy: Pzwp_tablet_tool_v2; hardware_serial_hi: LongWord; hardware_serial_lo: LongWord);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.hardware_id_wacom(AProxy: Pzwp_tablet_tool_v2; hardware_id_hi: LongWord; hardware_id_lo: LongWord);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.capability(AProxy: Pzwp_tablet_tool_v2; capability_: LongWord);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.done(AProxy: Pzwp_tablet_tool_v2);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.removed(AProxy: Pzwp_tablet_tool_v2);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.proximity_in(AProxy: Pzwp_tablet_tool_v2; serial: LongWord; tablet: Pzwp_tablet_v2; surface: Pwl_surface);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.proximity_out(AProxy: Pzwp_tablet_tool_v2);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.down(AProxy: Pzwp_tablet_tool_v2; serial: LongWord);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.up(AProxy: Pzwp_tablet_tool_v2);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.motion(AProxy: Pzwp_tablet_tool_v2; x: wl_fixed_t; y: wl_fixed_t);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.pressure(AProxy: Pzwp_tablet_tool_v2; pressure_: LongWord);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.distance(AProxy: Pzwp_tablet_tool_v2; distance_: LongWord);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.tilt(AProxy: Pzwp_tablet_tool_v2; tilt_x: wl_fixed_t; tilt_y: wl_fixed_t);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.rotation(AProxy: Pzwp_tablet_tool_v2; degrees: wl_fixed_t);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.slider(AProxy: Pzwp_tablet_tool_v2; position: LongInt);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.wheel(AProxy: Pzwp_tablet_tool_v2; degrees: wl_fixed_t; clicks: LongInt);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.button(AProxy: Pzwp_tablet_tool_v2; serial: LongWord; button_: LongWord; state: LongWord);
begin
end;

procedure Tzwp_tablet_tool_v2_listener.frame(AProxy: Pzwp_tablet_tool_v2; time: LongWord);
begin
end;

procedure Tzwp_tablet_v2_listener.name(AProxy: Pzwp_tablet_v2; name_: PAnsiChar);
begin
end;

procedure Tzwp_tablet_v2_listener.id(AProxy: Pzwp_tablet_v2; vid: LongWord; pid: LongWord);
begin
end;

procedure Tzwp_tablet_v2_listener.path(AProxy: Pzwp_tablet_v2; path_: PAnsiChar);
begin
end;

procedure Tzwp_tablet_v2_listener.done(AProxy: Pzwp_tablet_v2);
begin
end;

procedure Tzwp_tablet_v2_listener.removed(AProxy: Pzwp_tablet_v2);
begin
end;

procedure Tzwp_tablet_pad_ring_v2_listener.source(AProxy: Pzwp_tablet_pad_ring_v2; source_: LongWord);
begin
end;

procedure Tzwp_tablet_pad_ring_v2_listener.angle(AProxy: Pzwp_tablet_pad_ring_v2; degrees: wl_fixed_t);
begin
end;

procedure Tzwp_tablet_pad_ring_v2_listener.stop(AProxy: Pzwp_tablet_pad_ring_v2);
begin
end;

procedure Tzwp_tablet_pad_ring_v2_listener.frame(AProxy: Pzwp_tablet_pad_ring_v2; time: LongWord);
begin
end;

procedure Tzwp_tablet_pad_strip_v2_listener.source(AProxy: Pzwp_tablet_pad_strip_v2; source_: LongWord);
begin
end;

procedure Tzwp_tablet_pad_strip_v2_listener.position(AProxy: Pzwp_tablet_pad_strip_v2; position_: LongWord);
begin
end;

procedure Tzwp_tablet_pad_strip_v2_listener.stop(AProxy: Pzwp_tablet_pad_strip_v2);
begin
end;

procedure Tzwp_tablet_pad_strip_v2_listener.frame(AProxy: Pzwp_tablet_pad_strip_v2; time: LongWord);
begin
end;

procedure Tzwp_tablet_pad_group_v2_listener.buttons(AProxy: Pzwp_tablet_pad_group_v2; buttons_: Pwl_array);
begin
end;

procedure Tzwp_tablet_pad_group_v2_listener.ring(AProxy: Pzwp_tablet_pad_group_v2; ring_: Pzwp_tablet_pad_ring_v2);
begin
end;

procedure Tzwp_tablet_pad_group_v2_listener.strip(AProxy: Pzwp_tablet_pad_group_v2; strip_: Pzwp_tablet_pad_strip_v2);
begin
end;

procedure Tzwp_tablet_pad_group_v2_listener.modes(AProxy: Pzwp_tablet_pad_group_v2; modes_: LongWord);
begin
end;

procedure Tzwp_tablet_pad_group_v2_listener.done(AProxy: Pzwp_tablet_pad_group_v2);
begin
end;

procedure Tzwp_tablet_pad_group_v2_listener.mode_switch(AProxy: Pzwp_tablet_pad_group_v2; time: LongWord; serial: LongWord; mode: LongWord);
begin
end;

procedure Tzwp_tablet_pad_v2_listener.group(AProxy: Pzwp_tablet_pad_v2; pad_group: Pzwp_tablet_pad_group_v2);
begin
end;

procedure Tzwp_tablet_pad_v2_listener.path(AProxy: Pzwp_tablet_pad_v2; path_: PAnsiChar);
begin
end;

procedure Tzwp_tablet_pad_v2_listener.buttons(AProxy: Pzwp_tablet_pad_v2; buttons_: LongWord);
begin
end;

procedure Tzwp_tablet_pad_v2_listener.done(AProxy: Pzwp_tablet_pad_v2);
begin
end;

procedure Tzwp_tablet_pad_v2_listener.button(AProxy: Pzwp_tablet_pad_v2; time: LongWord; button_: LongWord; state: LongWord);
begin
end;

procedure Tzwp_tablet_pad_v2_listener.enter(AProxy: Pzwp_tablet_pad_v2; serial: LongWord; tablet: Pzwp_tablet_v2; surface: Pwl_surface);
begin
end;

procedure Tzwp_tablet_pad_v2_listener.leave(AProxy: Pzwp_tablet_pad_v2; serial: LongWord; surface: Pwl_surface);
begin
end;

procedure Tzwp_tablet_pad_v2_listener.removed(AProxy: Pzwp_tablet_pad_v2);
begin
end;

procedure Thunk_zwp_tablet_seat_v2_tablet_added(data: Pointer; AProxy: Pzwp_tablet_seat_v2; id: Pzwp_tablet_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_seat_v2_listener(data).tablet_added(AProxy, id);
end;

procedure Thunk_zwp_tablet_seat_v2_tool_added(data: Pointer; AProxy: Pzwp_tablet_seat_v2; id: Pzwp_tablet_tool_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_seat_v2_listener(data).tool_added(AProxy, id);
end;

procedure Thunk_zwp_tablet_seat_v2_pad_added(data: Pointer; AProxy: Pzwp_tablet_seat_v2; id: Pzwp_tablet_pad_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_seat_v2_listener(data).pad_added(AProxy, id);
end;

procedure Thunk_zwp_tablet_tool_v2_type_(data: Pointer; AProxy: Pzwp_tablet_tool_v2; tool_type: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).type_(AProxy, tool_type);
end;

procedure Thunk_zwp_tablet_tool_v2_hardware_serial(data: Pointer; AProxy: Pzwp_tablet_tool_v2; hardware_serial_hi: LongWord; hardware_serial_lo: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).hardware_serial(AProxy, hardware_serial_hi, hardware_serial_lo);
end;

procedure Thunk_zwp_tablet_tool_v2_hardware_id_wacom(data: Pointer; AProxy: Pzwp_tablet_tool_v2; hardware_id_hi: LongWord; hardware_id_lo: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).hardware_id_wacom(AProxy, hardware_id_hi, hardware_id_lo);
end;

procedure Thunk_zwp_tablet_tool_v2_capability(data: Pointer; AProxy: Pzwp_tablet_tool_v2; capability_: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).capability(AProxy, capability_);
end;

procedure Thunk_zwp_tablet_tool_v2_done(data: Pointer; AProxy: Pzwp_tablet_tool_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).done(AProxy);
end;

procedure Thunk_zwp_tablet_tool_v2_removed(data: Pointer; AProxy: Pzwp_tablet_tool_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).removed(AProxy);
end;

procedure Thunk_zwp_tablet_tool_v2_proximity_in(data: Pointer; AProxy: Pzwp_tablet_tool_v2; serial: LongWord; tablet: Pzwp_tablet_v2; surface: Pwl_surface); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).proximity_in(AProxy, serial, tablet, surface);
end;

procedure Thunk_zwp_tablet_tool_v2_proximity_out(data: Pointer; AProxy: Pzwp_tablet_tool_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).proximity_out(AProxy);
end;

procedure Thunk_zwp_tablet_tool_v2_down(data: Pointer; AProxy: Pzwp_tablet_tool_v2; serial: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).down(AProxy, serial);
end;

procedure Thunk_zwp_tablet_tool_v2_up(data: Pointer; AProxy: Pzwp_tablet_tool_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).up(AProxy);
end;

procedure Thunk_zwp_tablet_tool_v2_motion(data: Pointer; AProxy: Pzwp_tablet_tool_v2; x: wl_fixed_t; y: wl_fixed_t); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).motion(AProxy, x, y);
end;

procedure Thunk_zwp_tablet_tool_v2_pressure(data: Pointer; AProxy: Pzwp_tablet_tool_v2; pressure_: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).pressure(AProxy, pressure_);
end;

procedure Thunk_zwp_tablet_tool_v2_distance(data: Pointer; AProxy: Pzwp_tablet_tool_v2; distance_: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).distance(AProxy, distance_);
end;

procedure Thunk_zwp_tablet_tool_v2_tilt(data: Pointer; AProxy: Pzwp_tablet_tool_v2; tilt_x: wl_fixed_t; tilt_y: wl_fixed_t); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).tilt(AProxy, tilt_x, tilt_y);
end;

procedure Thunk_zwp_tablet_tool_v2_rotation(data: Pointer; AProxy: Pzwp_tablet_tool_v2; degrees: wl_fixed_t); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).rotation(AProxy, degrees);
end;

procedure Thunk_zwp_tablet_tool_v2_slider(data: Pointer; AProxy: Pzwp_tablet_tool_v2; position: LongInt); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).slider(AProxy, position);
end;

procedure Thunk_zwp_tablet_tool_v2_wheel(data: Pointer; AProxy: Pzwp_tablet_tool_v2; degrees: wl_fixed_t; clicks: LongInt); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).wheel(AProxy, degrees, clicks);
end;

procedure Thunk_zwp_tablet_tool_v2_button(data: Pointer; AProxy: Pzwp_tablet_tool_v2; serial: LongWord; button_: LongWord; state: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).button(AProxy, serial, button_, state);
end;

procedure Thunk_zwp_tablet_tool_v2_frame(data: Pointer; AProxy: Pzwp_tablet_tool_v2; time: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_tool_v2_listener(data).frame(AProxy, time);
end;

procedure Thunk_zwp_tablet_v2_name(data: Pointer; AProxy: Pzwp_tablet_v2; name_: PAnsiChar); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_v2_listener(data).name(AProxy, name_);
end;

procedure Thunk_zwp_tablet_v2_id(data: Pointer; AProxy: Pzwp_tablet_v2; vid: LongWord; pid: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_v2_listener(data).id(AProxy, vid, pid);
end;

procedure Thunk_zwp_tablet_v2_path(data: Pointer; AProxy: Pzwp_tablet_v2; path_: PAnsiChar); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_v2_listener(data).path(AProxy, path_);
end;

procedure Thunk_zwp_tablet_v2_done(data: Pointer; AProxy: Pzwp_tablet_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_v2_listener(data).done(AProxy);
end;

procedure Thunk_zwp_tablet_v2_removed(data: Pointer; AProxy: Pzwp_tablet_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_v2_listener(data).removed(AProxy);
end;

procedure Thunk_zwp_tablet_pad_ring_v2_source(data: Pointer; AProxy: Pzwp_tablet_pad_ring_v2; source_: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_ring_v2_listener(data).source(AProxy, source_);
end;

procedure Thunk_zwp_tablet_pad_ring_v2_angle(data: Pointer; AProxy: Pzwp_tablet_pad_ring_v2; degrees: wl_fixed_t); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_ring_v2_listener(data).angle(AProxy, degrees);
end;

procedure Thunk_zwp_tablet_pad_ring_v2_stop(data: Pointer; AProxy: Pzwp_tablet_pad_ring_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_ring_v2_listener(data).stop(AProxy);
end;

procedure Thunk_zwp_tablet_pad_ring_v2_frame(data: Pointer; AProxy: Pzwp_tablet_pad_ring_v2; time: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_ring_v2_listener(data).frame(AProxy, time);
end;

procedure Thunk_zwp_tablet_pad_strip_v2_source(data: Pointer; AProxy: Pzwp_tablet_pad_strip_v2; source_: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_strip_v2_listener(data).source(AProxy, source_);
end;

procedure Thunk_zwp_tablet_pad_strip_v2_position(data: Pointer; AProxy: Pzwp_tablet_pad_strip_v2; position_: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_strip_v2_listener(data).position(AProxy, position_);
end;

procedure Thunk_zwp_tablet_pad_strip_v2_stop(data: Pointer; AProxy: Pzwp_tablet_pad_strip_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_strip_v2_listener(data).stop(AProxy);
end;

procedure Thunk_zwp_tablet_pad_strip_v2_frame(data: Pointer; AProxy: Pzwp_tablet_pad_strip_v2; time: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_strip_v2_listener(data).frame(AProxy, time);
end;

procedure Thunk_zwp_tablet_pad_group_v2_buttons(data: Pointer; AProxy: Pzwp_tablet_pad_group_v2; buttons_: Pwl_array); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_group_v2_listener(data).buttons(AProxy, buttons_);
end;

procedure Thunk_zwp_tablet_pad_group_v2_ring(data: Pointer; AProxy: Pzwp_tablet_pad_group_v2; ring_: Pzwp_tablet_pad_ring_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_group_v2_listener(data).ring(AProxy, ring_);
end;

procedure Thunk_zwp_tablet_pad_group_v2_strip(data: Pointer; AProxy: Pzwp_tablet_pad_group_v2; strip_: Pzwp_tablet_pad_strip_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_group_v2_listener(data).strip(AProxy, strip_);
end;

procedure Thunk_zwp_tablet_pad_group_v2_modes(data: Pointer; AProxy: Pzwp_tablet_pad_group_v2; modes_: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_group_v2_listener(data).modes(AProxy, modes_);
end;

procedure Thunk_zwp_tablet_pad_group_v2_done(data: Pointer; AProxy: Pzwp_tablet_pad_group_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_group_v2_listener(data).done(AProxy);
end;

procedure Thunk_zwp_tablet_pad_group_v2_mode_switch(data: Pointer; AProxy: Pzwp_tablet_pad_group_v2; time: LongWord; serial: LongWord; mode: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_group_v2_listener(data).mode_switch(AProxy, time, serial, mode);
end;

procedure Thunk_zwp_tablet_pad_v2_group(data: Pointer; AProxy: Pzwp_tablet_pad_v2; pad_group: Pzwp_tablet_pad_group_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_v2_listener(data).group(AProxy, pad_group);
end;

procedure Thunk_zwp_tablet_pad_v2_path(data: Pointer; AProxy: Pzwp_tablet_pad_v2; path_: PAnsiChar); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_v2_listener(data).path(AProxy, path_);
end;

procedure Thunk_zwp_tablet_pad_v2_buttons(data: Pointer; AProxy: Pzwp_tablet_pad_v2; buttons_: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_v2_listener(data).buttons(AProxy, buttons_);
end;

procedure Thunk_zwp_tablet_pad_v2_done(data: Pointer; AProxy: Pzwp_tablet_pad_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_v2_listener(data).done(AProxy);
end;

procedure Thunk_zwp_tablet_pad_v2_button(data: Pointer; AProxy: Pzwp_tablet_pad_v2; time: LongWord; button_: LongWord; state: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_v2_listener(data).button(AProxy, time, button_, state);
end;

procedure Thunk_zwp_tablet_pad_v2_enter(data: Pointer; AProxy: Pzwp_tablet_pad_v2; serial: LongWord; tablet: Pzwp_tablet_v2; surface: Pwl_surface); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_v2_listener(data).enter(AProxy, serial, tablet, surface);
end;

procedure Thunk_zwp_tablet_pad_v2_leave(data: Pointer; AProxy: Pzwp_tablet_pad_v2; serial: LongWord; surface: Pwl_surface); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_v2_listener(data).leave(AProxy, serial, surface);
end;

procedure Thunk_zwp_tablet_pad_v2_removed(data: Pointer; AProxy: Pzwp_tablet_pad_v2); cdecl;
begin
  if data <> nil then
    Tzwp_tablet_pad_v2_listener(data).removed(AProxy);
end;

function zwp_tablet_seat_v2_add_listener_object(AProxy: Pzwp_tablet_seat_v2; AListener: Tzwp_tablet_seat_v2_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_tablet_seat_v2, AListener);
end;

function zwp_tablet_tool_v2_add_listener_object(AProxy: Pzwp_tablet_tool_v2; AListener: Tzwp_tablet_tool_v2_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_tablet_tool_v2, AListener);
end;

function zwp_tablet_v2_add_listener_object(AProxy: Pzwp_tablet_v2; AListener: Tzwp_tablet_v2_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_tablet_v2, AListener);
end;

function zwp_tablet_pad_ring_v2_add_listener_object(AProxy: Pzwp_tablet_pad_ring_v2; AListener: Tzwp_tablet_pad_ring_v2_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_tablet_pad_ring_v2, AListener);
end;

function zwp_tablet_pad_strip_v2_add_listener_object(AProxy: Pzwp_tablet_pad_strip_v2; AListener: Tzwp_tablet_pad_strip_v2_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_tablet_pad_strip_v2, AListener);
end;

function zwp_tablet_pad_group_v2_add_listener_object(AProxy: Pzwp_tablet_pad_group_v2; AListener: Tzwp_tablet_pad_group_v2_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_tablet_pad_group_v2, AListener);
end;

function zwp_tablet_pad_v2_add_listener_object(AProxy: Pzwp_tablet_pad_v2; AListener: Tzwp_tablet_pad_v2_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_tablet_pad_v2, AListener);
end;

function zwp_tablet_manager_v2_get_tablet_seat(AProxy: Pzwp_tablet_manager_v2; seat: Pwl_seat): Pzwp_tablet_seat_v2;
begin
  EnsureProtocolInitialized;
  Result := Pzwp_tablet_seat_v2(wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TABLET_MANAGER_V2_GET_TABLET_SEAT_OPCODE, zwp_tablet_seat_v2_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), seat));
end;

procedure zwp_tablet_manager_v2_destroy(AProxy: Pzwp_tablet_manager_v2);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TABLET_MANAGER_V2_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure zwp_tablet_seat_v2_destroy(AProxy: Pzwp_tablet_seat_v2);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TABLET_SEAT_V2_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure zwp_tablet_tool_v2_set_cursor(AProxy: Pzwp_tablet_tool_v2; serial: LongWord; surface: Pwl_surface; hotspot_x: LongInt; hotspot_y: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TABLET_TOOL_V2_SET_CURSOR_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, serial, surface, hotspot_x, hotspot_y);
end;

procedure zwp_tablet_tool_v2_destroy(AProxy: Pzwp_tablet_tool_v2);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TABLET_TOOL_V2_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure zwp_tablet_v2_destroy(AProxy: Pzwp_tablet_v2);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TABLET_V2_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure zwp_tablet_pad_ring_v2_set_feedback(AProxy: Pzwp_tablet_pad_ring_v2; description: PAnsiChar; serial: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TABLET_PAD_RING_V2_SET_FEEDBACK_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, description, serial);
end;

procedure zwp_tablet_pad_ring_v2_destroy(AProxy: Pzwp_tablet_pad_ring_v2);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TABLET_PAD_RING_V2_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure zwp_tablet_pad_strip_v2_set_feedback(AProxy: Pzwp_tablet_pad_strip_v2; description: PAnsiChar; serial: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TABLET_PAD_STRIP_V2_SET_FEEDBACK_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, description, serial);
end;

procedure zwp_tablet_pad_strip_v2_destroy(AProxy: Pzwp_tablet_pad_strip_v2);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TABLET_PAD_STRIP_V2_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure zwp_tablet_pad_group_v2_destroy(AProxy: Pzwp_tablet_pad_group_v2);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TABLET_PAD_GROUP_V2_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure zwp_tablet_pad_v2_set_feedback(AProxy: Pzwp_tablet_pad_v2; button_: LongWord; description: PAnsiChar; serial: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TABLET_PAD_V2_SET_FEEDBACK_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, button_, description, serial);
end;

procedure zwp_tablet_pad_v2_destroy(AProxy: Pzwp_tablet_pad_v2);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TABLET_PAD_V2_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;

  zwp_tablet_manager_v2_interface := @GIface_zwp_tablet_manager_v2;
  zwp_tablet_seat_v2_interface := @GIface_zwp_tablet_seat_v2;
  zwp_tablet_tool_v2_interface := @GIface_zwp_tablet_tool_v2;
  zwp_tablet_v2_interface := @GIface_zwp_tablet_v2;
  zwp_tablet_pad_ring_v2_interface := @GIface_zwp_tablet_pad_ring_v2;
  zwp_tablet_pad_strip_v2_interface := @GIface_zwp_tablet_pad_strip_v2;
  zwp_tablet_pad_group_v2_interface := @GIface_zwp_tablet_pad_group_v2;
  zwp_tablet_pad_v2_interface := @GIface_zwp_tablet_pad_v2;
  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[3] := zwp_tablet_seat_v2_interface;
  GTypes[4] := wl_seat_interface;
  GTypes[5] := zwp_tablet_v2_interface;
  GTypes[6] := zwp_tablet_tool_v2_interface;
  GTypes[7] := zwp_tablet_pad_v2_interface;
  GTypes[9] := wl_surface_interface;
  GTypes[13] := zwp_tablet_v2_interface;
  GTypes[14] := wl_surface_interface;
  GTypes[15] := zwp_tablet_pad_ring_v2_interface;
  GTypes[16] := zwp_tablet_pad_strip_v2_interface;
  GTypes[17] := zwp_tablet_pad_group_v2_interface;
  GTypes[19] := zwp_tablet_v2_interface;
  GTypes[20] := wl_surface_interface;
  GTypes[22] := wl_surface_interface;

  GReq_zwp_tablet_manager_v2[0].name := 'get_tablet_seat';
  GReq_zwp_tablet_manager_v2[0].signature := 'no';
  GReq_zwp_tablet_manager_v2[0].types := @GTypes[3];
  GReq_zwp_tablet_manager_v2[1].name := 'destroy';
  GReq_zwp_tablet_manager_v2[1].signature := '';
  GReq_zwp_tablet_manager_v2[1].types := @GTypes[0];
  GIface_zwp_tablet_manager_v2.name := 'zwp_tablet_manager_v2';
  GIface_zwp_tablet_manager_v2.version := 1;
  GIface_zwp_tablet_manager_v2.method_count := 2;
  GIface_zwp_tablet_manager_v2.methods := @GReq_zwp_tablet_manager_v2[0];
  GIface_zwp_tablet_manager_v2.event_count := 0;
  GIface_zwp_tablet_manager_v2.events := nil;

  GReq_zwp_tablet_seat_v2[0].name := 'destroy';
  GReq_zwp_tablet_seat_v2[0].signature := '';
  GReq_zwp_tablet_seat_v2[0].types := @GTypes[0];
  GEvt_zwp_tablet_seat_v2[0].name := 'tablet_added';
  GEvt_zwp_tablet_seat_v2[0].signature := 'n';
  GEvt_zwp_tablet_seat_v2[0].types := @GTypes[5];
  GEvt_zwp_tablet_seat_v2[1].name := 'tool_added';
  GEvt_zwp_tablet_seat_v2[1].signature := 'n';
  GEvt_zwp_tablet_seat_v2[1].types := @GTypes[6];
  GEvt_zwp_tablet_seat_v2[2].name := 'pad_added';
  GEvt_zwp_tablet_seat_v2[2].signature := 'n';
  GEvt_zwp_tablet_seat_v2[2].types := @GTypes[7];
  GIface_zwp_tablet_seat_v2.name := 'zwp_tablet_seat_v2';
  GIface_zwp_tablet_seat_v2.version := 1;
  GIface_zwp_tablet_seat_v2.method_count := 1;
  GIface_zwp_tablet_seat_v2.methods := @GReq_zwp_tablet_seat_v2[0];
  GIface_zwp_tablet_seat_v2.event_count := 3;
  GIface_zwp_tablet_seat_v2.events := @GEvt_zwp_tablet_seat_v2[0];

  GReq_zwp_tablet_tool_v2[0].name := 'set_cursor';
  GReq_zwp_tablet_tool_v2[0].signature := 'u?oii';
  GReq_zwp_tablet_tool_v2[0].types := @GTypes[8];
  GReq_zwp_tablet_tool_v2[1].name := 'destroy';
  GReq_zwp_tablet_tool_v2[1].signature := '';
  GReq_zwp_tablet_tool_v2[1].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[0].name := 'type';
  GEvt_zwp_tablet_tool_v2[0].signature := 'u';
  GEvt_zwp_tablet_tool_v2[0].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[1].name := 'hardware_serial';
  GEvt_zwp_tablet_tool_v2[1].signature := 'uu';
  GEvt_zwp_tablet_tool_v2[1].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[2].name := 'hardware_id_wacom';
  GEvt_zwp_tablet_tool_v2[2].signature := 'uu';
  GEvt_zwp_tablet_tool_v2[2].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[3].name := 'capability';
  GEvt_zwp_tablet_tool_v2[3].signature := 'u';
  GEvt_zwp_tablet_tool_v2[3].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[4].name := 'done';
  GEvt_zwp_tablet_tool_v2[4].signature := '';
  GEvt_zwp_tablet_tool_v2[4].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[5].name := 'removed';
  GEvt_zwp_tablet_tool_v2[5].signature := '';
  GEvt_zwp_tablet_tool_v2[5].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[6].name := 'proximity_in';
  GEvt_zwp_tablet_tool_v2[6].signature := 'uoo';
  GEvt_zwp_tablet_tool_v2[6].types := @GTypes[12];
  GEvt_zwp_tablet_tool_v2[7].name := 'proximity_out';
  GEvt_zwp_tablet_tool_v2[7].signature := '';
  GEvt_zwp_tablet_tool_v2[7].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[8].name := 'down';
  GEvt_zwp_tablet_tool_v2[8].signature := 'u';
  GEvt_zwp_tablet_tool_v2[8].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[9].name := 'up';
  GEvt_zwp_tablet_tool_v2[9].signature := '';
  GEvt_zwp_tablet_tool_v2[9].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[10].name := 'motion';
  GEvt_zwp_tablet_tool_v2[10].signature := 'ff';
  GEvt_zwp_tablet_tool_v2[10].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[11].name := 'pressure';
  GEvt_zwp_tablet_tool_v2[11].signature := 'u';
  GEvt_zwp_tablet_tool_v2[11].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[12].name := 'distance';
  GEvt_zwp_tablet_tool_v2[12].signature := 'u';
  GEvt_zwp_tablet_tool_v2[12].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[13].name := 'tilt';
  GEvt_zwp_tablet_tool_v2[13].signature := 'ff';
  GEvt_zwp_tablet_tool_v2[13].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[14].name := 'rotation';
  GEvt_zwp_tablet_tool_v2[14].signature := 'f';
  GEvt_zwp_tablet_tool_v2[14].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[15].name := 'slider';
  GEvt_zwp_tablet_tool_v2[15].signature := 'i';
  GEvt_zwp_tablet_tool_v2[15].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[16].name := 'wheel';
  GEvt_zwp_tablet_tool_v2[16].signature := 'fi';
  GEvt_zwp_tablet_tool_v2[16].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[17].name := 'button';
  GEvt_zwp_tablet_tool_v2[17].signature := 'uuu';
  GEvt_zwp_tablet_tool_v2[17].types := @GTypes[0];
  GEvt_zwp_tablet_tool_v2[18].name := 'frame';
  GEvt_zwp_tablet_tool_v2[18].signature := 'u';
  GEvt_zwp_tablet_tool_v2[18].types := @GTypes[0];
  GIface_zwp_tablet_tool_v2.name := 'zwp_tablet_tool_v2';
  GIface_zwp_tablet_tool_v2.version := 1;
  GIface_zwp_tablet_tool_v2.method_count := 2;
  GIface_zwp_tablet_tool_v2.methods := @GReq_zwp_tablet_tool_v2[0];
  GIface_zwp_tablet_tool_v2.event_count := 19;
  GIface_zwp_tablet_tool_v2.events := @GEvt_zwp_tablet_tool_v2[0];

  GReq_zwp_tablet_v2[0].name := 'destroy';
  GReq_zwp_tablet_v2[0].signature := '';
  GReq_zwp_tablet_v2[0].types := @GTypes[0];
  GEvt_zwp_tablet_v2[0].name := 'name';
  GEvt_zwp_tablet_v2[0].signature := 's';
  GEvt_zwp_tablet_v2[0].types := @GTypes[0];
  GEvt_zwp_tablet_v2[1].name := 'id';
  GEvt_zwp_tablet_v2[1].signature := 'uu';
  GEvt_zwp_tablet_v2[1].types := @GTypes[0];
  GEvt_zwp_tablet_v2[2].name := 'path';
  GEvt_zwp_tablet_v2[2].signature := 's';
  GEvt_zwp_tablet_v2[2].types := @GTypes[0];
  GEvt_zwp_tablet_v2[3].name := 'done';
  GEvt_zwp_tablet_v2[3].signature := '';
  GEvt_zwp_tablet_v2[3].types := @GTypes[0];
  GEvt_zwp_tablet_v2[4].name := 'removed';
  GEvt_zwp_tablet_v2[4].signature := '';
  GEvt_zwp_tablet_v2[4].types := @GTypes[0];
  GIface_zwp_tablet_v2.name := 'zwp_tablet_v2';
  GIface_zwp_tablet_v2.version := 1;
  GIface_zwp_tablet_v2.method_count := 1;
  GIface_zwp_tablet_v2.methods := @GReq_zwp_tablet_v2[0];
  GIface_zwp_tablet_v2.event_count := 5;
  GIface_zwp_tablet_v2.events := @GEvt_zwp_tablet_v2[0];

  GReq_zwp_tablet_pad_ring_v2[0].name := 'set_feedback';
  GReq_zwp_tablet_pad_ring_v2[0].signature := 'su';
  GReq_zwp_tablet_pad_ring_v2[0].types := @GTypes[0];
  GReq_zwp_tablet_pad_ring_v2[1].name := 'destroy';
  GReq_zwp_tablet_pad_ring_v2[1].signature := '';
  GReq_zwp_tablet_pad_ring_v2[1].types := @GTypes[0];
  GEvt_zwp_tablet_pad_ring_v2[0].name := 'source';
  GEvt_zwp_tablet_pad_ring_v2[0].signature := 'u';
  GEvt_zwp_tablet_pad_ring_v2[0].types := @GTypes[0];
  GEvt_zwp_tablet_pad_ring_v2[1].name := 'angle';
  GEvt_zwp_tablet_pad_ring_v2[1].signature := 'f';
  GEvt_zwp_tablet_pad_ring_v2[1].types := @GTypes[0];
  GEvt_zwp_tablet_pad_ring_v2[2].name := 'stop';
  GEvt_zwp_tablet_pad_ring_v2[2].signature := '';
  GEvt_zwp_tablet_pad_ring_v2[2].types := @GTypes[0];
  GEvt_zwp_tablet_pad_ring_v2[3].name := 'frame';
  GEvt_zwp_tablet_pad_ring_v2[3].signature := 'u';
  GEvt_zwp_tablet_pad_ring_v2[3].types := @GTypes[0];
  GIface_zwp_tablet_pad_ring_v2.name := 'zwp_tablet_pad_ring_v2';
  GIface_zwp_tablet_pad_ring_v2.version := 1;
  GIface_zwp_tablet_pad_ring_v2.method_count := 2;
  GIface_zwp_tablet_pad_ring_v2.methods := @GReq_zwp_tablet_pad_ring_v2[0];
  GIface_zwp_tablet_pad_ring_v2.event_count := 4;
  GIface_zwp_tablet_pad_ring_v2.events := @GEvt_zwp_tablet_pad_ring_v2[0];

  GReq_zwp_tablet_pad_strip_v2[0].name := 'set_feedback';
  GReq_zwp_tablet_pad_strip_v2[0].signature := 'su';
  GReq_zwp_tablet_pad_strip_v2[0].types := @GTypes[0];
  GReq_zwp_tablet_pad_strip_v2[1].name := 'destroy';
  GReq_zwp_tablet_pad_strip_v2[1].signature := '';
  GReq_zwp_tablet_pad_strip_v2[1].types := @GTypes[0];
  GEvt_zwp_tablet_pad_strip_v2[0].name := 'source';
  GEvt_zwp_tablet_pad_strip_v2[0].signature := 'u';
  GEvt_zwp_tablet_pad_strip_v2[0].types := @GTypes[0];
  GEvt_zwp_tablet_pad_strip_v2[1].name := 'position';
  GEvt_zwp_tablet_pad_strip_v2[1].signature := 'u';
  GEvt_zwp_tablet_pad_strip_v2[1].types := @GTypes[0];
  GEvt_zwp_tablet_pad_strip_v2[2].name := 'stop';
  GEvt_zwp_tablet_pad_strip_v2[2].signature := '';
  GEvt_zwp_tablet_pad_strip_v2[2].types := @GTypes[0];
  GEvt_zwp_tablet_pad_strip_v2[3].name := 'frame';
  GEvt_zwp_tablet_pad_strip_v2[3].signature := 'u';
  GEvt_zwp_tablet_pad_strip_v2[3].types := @GTypes[0];
  GIface_zwp_tablet_pad_strip_v2.name := 'zwp_tablet_pad_strip_v2';
  GIface_zwp_tablet_pad_strip_v2.version := 1;
  GIface_zwp_tablet_pad_strip_v2.method_count := 2;
  GIface_zwp_tablet_pad_strip_v2.methods := @GReq_zwp_tablet_pad_strip_v2[0];
  GIface_zwp_tablet_pad_strip_v2.event_count := 4;
  GIface_zwp_tablet_pad_strip_v2.events := @GEvt_zwp_tablet_pad_strip_v2[0];

  GReq_zwp_tablet_pad_group_v2[0].name := 'destroy';
  GReq_zwp_tablet_pad_group_v2[0].signature := '';
  GReq_zwp_tablet_pad_group_v2[0].types := @GTypes[0];
  GEvt_zwp_tablet_pad_group_v2[0].name := 'buttons';
  GEvt_zwp_tablet_pad_group_v2[0].signature := 'a';
  GEvt_zwp_tablet_pad_group_v2[0].types := @GTypes[0];
  GEvt_zwp_tablet_pad_group_v2[1].name := 'ring';
  GEvt_zwp_tablet_pad_group_v2[1].signature := 'n';
  GEvt_zwp_tablet_pad_group_v2[1].types := @GTypes[15];
  GEvt_zwp_tablet_pad_group_v2[2].name := 'strip';
  GEvt_zwp_tablet_pad_group_v2[2].signature := 'n';
  GEvt_zwp_tablet_pad_group_v2[2].types := @GTypes[16];
  GEvt_zwp_tablet_pad_group_v2[3].name := 'modes';
  GEvt_zwp_tablet_pad_group_v2[3].signature := 'u';
  GEvt_zwp_tablet_pad_group_v2[3].types := @GTypes[0];
  GEvt_zwp_tablet_pad_group_v2[4].name := 'done';
  GEvt_zwp_tablet_pad_group_v2[4].signature := '';
  GEvt_zwp_tablet_pad_group_v2[4].types := @GTypes[0];
  GEvt_zwp_tablet_pad_group_v2[5].name := 'mode_switch';
  GEvt_zwp_tablet_pad_group_v2[5].signature := 'uuu';
  GEvt_zwp_tablet_pad_group_v2[5].types := @GTypes[0];
  GIface_zwp_tablet_pad_group_v2.name := 'zwp_tablet_pad_group_v2';
  GIface_zwp_tablet_pad_group_v2.version := 1;
  GIface_zwp_tablet_pad_group_v2.method_count := 1;
  GIface_zwp_tablet_pad_group_v2.methods := @GReq_zwp_tablet_pad_group_v2[0];
  GIface_zwp_tablet_pad_group_v2.event_count := 6;
  GIface_zwp_tablet_pad_group_v2.events := @GEvt_zwp_tablet_pad_group_v2[0];

  GReq_zwp_tablet_pad_v2[0].name := 'set_feedback';
  GReq_zwp_tablet_pad_v2[0].signature := 'usu';
  GReq_zwp_tablet_pad_v2[0].types := @GTypes[0];
  GReq_zwp_tablet_pad_v2[1].name := 'destroy';
  GReq_zwp_tablet_pad_v2[1].signature := '';
  GReq_zwp_tablet_pad_v2[1].types := @GTypes[0];
  GEvt_zwp_tablet_pad_v2[0].name := 'group';
  GEvt_zwp_tablet_pad_v2[0].signature := 'n';
  GEvt_zwp_tablet_pad_v2[0].types := @GTypes[17];
  GEvt_zwp_tablet_pad_v2[1].name := 'path';
  GEvt_zwp_tablet_pad_v2[1].signature := 's';
  GEvt_zwp_tablet_pad_v2[1].types := @GTypes[0];
  GEvt_zwp_tablet_pad_v2[2].name := 'buttons';
  GEvt_zwp_tablet_pad_v2[2].signature := 'u';
  GEvt_zwp_tablet_pad_v2[2].types := @GTypes[0];
  GEvt_zwp_tablet_pad_v2[3].name := 'done';
  GEvt_zwp_tablet_pad_v2[3].signature := '';
  GEvt_zwp_tablet_pad_v2[3].types := @GTypes[0];
  GEvt_zwp_tablet_pad_v2[4].name := 'button';
  GEvt_zwp_tablet_pad_v2[4].signature := 'uuu';
  GEvt_zwp_tablet_pad_v2[4].types := @GTypes[0];
  GEvt_zwp_tablet_pad_v2[5].name := 'enter';
  GEvt_zwp_tablet_pad_v2[5].signature := 'uoo';
  GEvt_zwp_tablet_pad_v2[5].types := @GTypes[18];
  GEvt_zwp_tablet_pad_v2[6].name := 'leave';
  GEvt_zwp_tablet_pad_v2[6].signature := 'uo';
  GEvt_zwp_tablet_pad_v2[6].types := @GTypes[21];
  GEvt_zwp_tablet_pad_v2[7].name := 'removed';
  GEvt_zwp_tablet_pad_v2[7].signature := '';
  GEvt_zwp_tablet_pad_v2[7].types := @GTypes[0];
  GIface_zwp_tablet_pad_v2.name := 'zwp_tablet_pad_v2';
  GIface_zwp_tablet_pad_v2.version := 1;
  GIface_zwp_tablet_pad_v2.method_count := 2;
  GIface_zwp_tablet_pad_v2.methods := @GReq_zwp_tablet_pad_v2[0];
  GIface_zwp_tablet_pad_v2.event_count := 8;
  GIface_zwp_tablet_pad_v2.events := @GEvt_zwp_tablet_pad_v2[0];

  GThunks_zwp_tablet_seat_v2.tablet_added := @Thunk_zwp_tablet_seat_v2_tablet_added;
  GThunks_zwp_tablet_seat_v2.tool_added := @Thunk_zwp_tablet_seat_v2_tool_added;
  GThunks_zwp_tablet_seat_v2.pad_added := @Thunk_zwp_tablet_seat_v2_pad_added;
  GThunks_zwp_tablet_tool_v2.type_ := @Thunk_zwp_tablet_tool_v2_type_;
  GThunks_zwp_tablet_tool_v2.hardware_serial := @Thunk_zwp_tablet_tool_v2_hardware_serial;
  GThunks_zwp_tablet_tool_v2.hardware_id_wacom := @Thunk_zwp_tablet_tool_v2_hardware_id_wacom;
  GThunks_zwp_tablet_tool_v2.capability := @Thunk_zwp_tablet_tool_v2_capability;
  GThunks_zwp_tablet_tool_v2.done := @Thunk_zwp_tablet_tool_v2_done;
  GThunks_zwp_tablet_tool_v2.removed := @Thunk_zwp_tablet_tool_v2_removed;
  GThunks_zwp_tablet_tool_v2.proximity_in := @Thunk_zwp_tablet_tool_v2_proximity_in;
  GThunks_zwp_tablet_tool_v2.proximity_out := @Thunk_zwp_tablet_tool_v2_proximity_out;
  GThunks_zwp_tablet_tool_v2.down := @Thunk_zwp_tablet_tool_v2_down;
  GThunks_zwp_tablet_tool_v2.up := @Thunk_zwp_tablet_tool_v2_up;
  GThunks_zwp_tablet_tool_v2.motion := @Thunk_zwp_tablet_tool_v2_motion;
  GThunks_zwp_tablet_tool_v2.pressure := @Thunk_zwp_tablet_tool_v2_pressure;
  GThunks_zwp_tablet_tool_v2.distance := @Thunk_zwp_tablet_tool_v2_distance;
  GThunks_zwp_tablet_tool_v2.tilt := @Thunk_zwp_tablet_tool_v2_tilt;
  GThunks_zwp_tablet_tool_v2.rotation := @Thunk_zwp_tablet_tool_v2_rotation;
  GThunks_zwp_tablet_tool_v2.slider := @Thunk_zwp_tablet_tool_v2_slider;
  GThunks_zwp_tablet_tool_v2.wheel := @Thunk_zwp_tablet_tool_v2_wheel;
  GThunks_zwp_tablet_tool_v2.button := @Thunk_zwp_tablet_tool_v2_button;
  GThunks_zwp_tablet_tool_v2.frame := @Thunk_zwp_tablet_tool_v2_frame;
  GThunks_zwp_tablet_v2.name := @Thunk_zwp_tablet_v2_name;
  GThunks_zwp_tablet_v2.id := @Thunk_zwp_tablet_v2_id;
  GThunks_zwp_tablet_v2.path := @Thunk_zwp_tablet_v2_path;
  GThunks_zwp_tablet_v2.done := @Thunk_zwp_tablet_v2_done;
  GThunks_zwp_tablet_v2.removed := @Thunk_zwp_tablet_v2_removed;
  GThunks_zwp_tablet_pad_ring_v2.source := @Thunk_zwp_tablet_pad_ring_v2_source;
  GThunks_zwp_tablet_pad_ring_v2.angle := @Thunk_zwp_tablet_pad_ring_v2_angle;
  GThunks_zwp_tablet_pad_ring_v2.stop := @Thunk_zwp_tablet_pad_ring_v2_stop;
  GThunks_zwp_tablet_pad_ring_v2.frame := @Thunk_zwp_tablet_pad_ring_v2_frame;
  GThunks_zwp_tablet_pad_strip_v2.source := @Thunk_zwp_tablet_pad_strip_v2_source;
  GThunks_zwp_tablet_pad_strip_v2.position := @Thunk_zwp_tablet_pad_strip_v2_position;
  GThunks_zwp_tablet_pad_strip_v2.stop := @Thunk_zwp_tablet_pad_strip_v2_stop;
  GThunks_zwp_tablet_pad_strip_v2.frame := @Thunk_zwp_tablet_pad_strip_v2_frame;
  GThunks_zwp_tablet_pad_group_v2.buttons := @Thunk_zwp_tablet_pad_group_v2_buttons;
  GThunks_zwp_tablet_pad_group_v2.ring := @Thunk_zwp_tablet_pad_group_v2_ring;
  GThunks_zwp_tablet_pad_group_v2.strip := @Thunk_zwp_tablet_pad_group_v2_strip;
  GThunks_zwp_tablet_pad_group_v2.modes := @Thunk_zwp_tablet_pad_group_v2_modes;
  GThunks_zwp_tablet_pad_group_v2.done := @Thunk_zwp_tablet_pad_group_v2_done;
  GThunks_zwp_tablet_pad_group_v2.mode_switch := @Thunk_zwp_tablet_pad_group_v2_mode_switch;
  GThunks_zwp_tablet_pad_v2.group := @Thunk_zwp_tablet_pad_v2_group;
  GThunks_zwp_tablet_pad_v2.path := @Thunk_zwp_tablet_pad_v2_path;
  GThunks_zwp_tablet_pad_v2.buttons := @Thunk_zwp_tablet_pad_v2_buttons;
  GThunks_zwp_tablet_pad_v2.done := @Thunk_zwp_tablet_pad_v2_done;
  GThunks_zwp_tablet_pad_v2.button := @Thunk_zwp_tablet_pad_v2_button;
  GThunks_zwp_tablet_pad_v2.enter := @Thunk_zwp_tablet_pad_v2_enter;
  GThunks_zwp_tablet_pad_v2.leave := @Thunk_zwp_tablet_pad_v2_leave;
  GThunks_zwp_tablet_pad_v2.removed := @Thunk_zwp_tablet_pad_v2_removed;
end;

end.
