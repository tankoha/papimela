{
  PaPiMeLa.Platform.Wayland.Protocols.TextInputUnstableV3

  自動生成ファイル。手で編集しないこと。
  生成元: text_input_unstable_v3.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright � 2012, 2013 Intel Corporation
      Copyright � 2015, 2016 Jan Arne Petersen
      Copyright � 2017, 2018 Red Hat, Inc.
      Copyright � 2018       Purism SPC
  
      Permission to use, copy, modify, distribute, and sell this
      software and its documentation for any purpose is hereby granted
      without fee, provided that the above copyright notice appear in
      all copies and that both that copyright notice and this permission
      notice appear in supporting documentation, and that the name of
      the copyright holders not be used in advertising or publicity
      pertaining to distribution of the software without specific,
      written prior permission.  The copyright holders make no
      representations about the suitability of this software for any
      purpose.  It is provided "as is" without express or implied
      warranty.
  
      THE COPYRIGHT HOLDERS DISCLAIM ALL WARRANTIES WITH REGARD TO THIS
      SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
      FITNESS, IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
      SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
      WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
      AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
      ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
      THIS SOFTWARE.

}
unit PaPiMeLa.Platform.Wayland.Protocols.TextInputUnstableV3;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  Tzwp_text_input_v3_opaque = record end;
  Pzwp_text_input_v3 = ^Tzwp_text_input_v3_opaque;
  Tzwp_text_input_manager_v3_opaque = record end;
  Pzwp_text_input_manager_v3 = ^Tzwp_text_input_manager_v3_opaque;

const
  // zwp_text_input_v3 (version 1)
  ZWP_TEXT_INPUT_V3_DESTROY_OPCODE = 0;
  ZWP_TEXT_INPUT_V3_ENABLE_OPCODE = 1;
  ZWP_TEXT_INPUT_V3_DISABLE_OPCODE = 2;
  ZWP_TEXT_INPUT_V3_SET_SURROUNDING_TEXT_OPCODE = 3;
  ZWP_TEXT_INPUT_V3_SET_TEXT_CHANGE_CAUSE_OPCODE = 4;
  ZWP_TEXT_INPUT_V3_SET_CONTENT_TYPE_OPCODE = 5;
  ZWP_TEXT_INPUT_V3_SET_CURSOR_RECTANGLE_OPCODE = 6;
  ZWP_TEXT_INPUT_V3_COMMIT_OPCODE = 7;
  ZWP_TEXT_INPUT_V3_DESTROY_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_V3_ENABLE_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_V3_DISABLE_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_V3_SET_SURROUNDING_TEXT_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_V3_SET_TEXT_CHANGE_CAUSE_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_V3_SET_CONTENT_TYPE_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_V3_SET_CURSOR_RECTANGLE_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_V3_COMMIT_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_V3_ENTER_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_V3_LEAVE_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_V3_PREEDIT_STRING_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_V3_COMMIT_STRING_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_V3_DELETE_SURROUNDING_TEXT_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_V3_DONE_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_INPUT_METHOD = 0;
  ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER = 1;
  ZWP_TEXT_INPUT_V3_CONTENT_HINT_NONE = $0;
  ZWP_TEXT_INPUT_V3_CONTENT_HINT_COMPLETION = $1;
  ZWP_TEXT_INPUT_V3_CONTENT_HINT_SPELLCHECK = $2;
  ZWP_TEXT_INPUT_V3_CONTENT_HINT_AUTO_CAPITALIZATION = $4;
  ZWP_TEXT_INPUT_V3_CONTENT_HINT_LOWERCASE = $8;
  ZWP_TEXT_INPUT_V3_CONTENT_HINT_UPPERCASE = $10;
  ZWP_TEXT_INPUT_V3_CONTENT_HINT_TITLECASE = $20;
  ZWP_TEXT_INPUT_V3_CONTENT_HINT_HIDDEN_TEXT = $40;
  ZWP_TEXT_INPUT_V3_CONTENT_HINT_SENSITIVE_DATA = $80;
  ZWP_TEXT_INPUT_V3_CONTENT_HINT_LATIN = $100;
  ZWP_TEXT_INPUT_V3_CONTENT_HINT_MULTILINE = $200;
  ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_NORMAL = 0;
  ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_ALPHA = 1;
  ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_DIGITS = 2;
  ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_NUMBER = 3;
  ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_PHONE = 4;
  ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_URL = 5;
  ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_EMAIL = 6;
  ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_NAME = 7;
  ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_PASSWORD = 8;
  ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_PIN = 9;
  ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_DATE = 10;
  ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_TIME = 11;
  ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_DATETIME = 12;
  ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_TERMINAL = 13;

  // zwp_text_input_manager_v3 (version 1)
  ZWP_TEXT_INPUT_MANAGER_V3_DESTROY_OPCODE = 0;
  ZWP_TEXT_INPUT_MANAGER_V3_GET_TEXT_INPUT_OPCODE = 1;
  ZWP_TEXT_INPUT_MANAGER_V3_DESTROY_SINCE_VERSION = 1;
  ZWP_TEXT_INPUT_MANAGER_V3_GET_TEXT_INPUT_SINCE_VERSION = 1;

var
  zwp_text_input_v3_interface: Pwl_interface = nil;
  zwp_text_input_manager_v3_interface: Pwl_interface = nil;

type
  Tzwp_text_input_v3_listener = class abstract(TObject)
  public
    procedure enter(AProxy: Pzwp_text_input_v3; surface: Pwl_surface); virtual;
    procedure leave(AProxy: Pzwp_text_input_v3; surface: Pwl_surface); virtual;
    procedure preedit_string(AProxy: Pzwp_text_input_v3; text: PAnsiChar; cursor_begin: LongInt; cursor_end: LongInt); virtual;
    procedure commit_string(AProxy: Pzwp_text_input_v3; text: PAnsiChar); virtual;
    procedure delete_surrounding_text(AProxy: Pzwp_text_input_v3; before_length: LongWord; after_length: LongWord); virtual;
    procedure done(AProxy: Pzwp_text_input_v3; serial: LongWord); virtual;
  end;

  Tzwp_text_input_v3_listener_rec = record
    enter: procedure(data: Pointer; AProxy: Pzwp_text_input_v3; surface: Pwl_surface); cdecl;
    leave: procedure(data: Pointer; AProxy: Pzwp_text_input_v3; surface: Pwl_surface); cdecl;
    preedit_string: procedure(data: Pointer; AProxy: Pzwp_text_input_v3; text: PAnsiChar; cursor_begin: LongInt; cursor_end: LongInt); cdecl;
    commit_string: procedure(data: Pointer; AProxy: Pzwp_text_input_v3; text: PAnsiChar); cdecl;
    delete_surrounding_text: procedure(data: Pointer; AProxy: Pzwp_text_input_v3; before_length: LongWord; after_length: LongWord); cdecl;
    done: procedure(data: Pointer; AProxy: Pzwp_text_input_v3; serial: LongWord); cdecl;
  end;

function zwp_text_input_v3_add_listener_object(AProxy: Pzwp_text_input_v3; AListener: Tzwp_text_input_v3_listener): LongInt;
procedure zwp_text_input_v3_destroy(AProxy: Pzwp_text_input_v3);
procedure zwp_text_input_v3_enable(AProxy: Pzwp_text_input_v3);
procedure zwp_text_input_v3_disable(AProxy: Pzwp_text_input_v3);
procedure zwp_text_input_v3_set_surrounding_text(AProxy: Pzwp_text_input_v3; text: PAnsiChar; cursor: LongInt; anchor: LongInt);
procedure zwp_text_input_v3_set_text_change_cause(AProxy: Pzwp_text_input_v3; cause: LongWord);
procedure zwp_text_input_v3_set_content_type(AProxy: Pzwp_text_input_v3; hint: LongWord; purpose: LongWord);
procedure zwp_text_input_v3_set_cursor_rectangle(AProxy: Pzwp_text_input_v3; x: LongInt; y: LongInt; width: LongInt; height: LongInt);
procedure zwp_text_input_v3_commit(AProxy: Pzwp_text_input_v3);

procedure zwp_text_input_manager_v3_destroy(AProxy: Pzwp_text_input_manager_v3);
function zwp_text_input_manager_v3_get_text_input(AProxy: Pzwp_text_input_manager_v3; seat: Pwl_seat): Pzwp_text_input_v3;

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..7] of Pwl_interface;
  GReq_zwp_text_input_v3: array[0..7] of Twl_message;
  GEvt_zwp_text_input_v3: array[0..5] of Twl_message;
  GIface_zwp_text_input_v3: Twl_interface;
  GReq_zwp_text_input_manager_v3: array[0..1] of Twl_message;
  GIface_zwp_text_input_manager_v3: Twl_interface;

var
  GInitialized: Boolean = False;
  GThunks_zwp_text_input_v3: Tzwp_text_input_v3_listener_rec;

procedure Tzwp_text_input_v3_listener.enter(AProxy: Pzwp_text_input_v3; surface: Pwl_surface);
begin
end;

procedure Tzwp_text_input_v3_listener.leave(AProxy: Pzwp_text_input_v3; surface: Pwl_surface);
begin
end;

procedure Tzwp_text_input_v3_listener.preedit_string(AProxy: Pzwp_text_input_v3; text: PAnsiChar; cursor_begin: LongInt; cursor_end: LongInt);
begin
end;

procedure Tzwp_text_input_v3_listener.commit_string(AProxy: Pzwp_text_input_v3; text: PAnsiChar);
begin
end;

procedure Tzwp_text_input_v3_listener.delete_surrounding_text(AProxy: Pzwp_text_input_v3; before_length: LongWord; after_length: LongWord);
begin
end;

procedure Tzwp_text_input_v3_listener.done(AProxy: Pzwp_text_input_v3; serial: LongWord);
begin
end;

procedure Thunk_zwp_text_input_v3_enter(data: Pointer; AProxy: Pzwp_text_input_v3; surface: Pwl_surface); cdecl;
begin
  if data <> nil then
    Tzwp_text_input_v3_listener(data).enter(AProxy, surface);
end;

procedure Thunk_zwp_text_input_v3_leave(data: Pointer; AProxy: Pzwp_text_input_v3; surface: Pwl_surface); cdecl;
begin
  if data <> nil then
    Tzwp_text_input_v3_listener(data).leave(AProxy, surface);
end;

procedure Thunk_zwp_text_input_v3_preedit_string(data: Pointer; AProxy: Pzwp_text_input_v3; text: PAnsiChar; cursor_begin: LongInt; cursor_end: LongInt); cdecl;
begin
  if data <> nil then
    Tzwp_text_input_v3_listener(data).preedit_string(AProxy, text, cursor_begin, cursor_end);
end;

procedure Thunk_zwp_text_input_v3_commit_string(data: Pointer; AProxy: Pzwp_text_input_v3; text: PAnsiChar); cdecl;
begin
  if data <> nil then
    Tzwp_text_input_v3_listener(data).commit_string(AProxy, text);
end;

procedure Thunk_zwp_text_input_v3_delete_surrounding_text(data: Pointer; AProxy: Pzwp_text_input_v3; before_length: LongWord; after_length: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_text_input_v3_listener(data).delete_surrounding_text(AProxy, before_length, after_length);
end;

procedure Thunk_zwp_text_input_v3_done(data: Pointer; AProxy: Pzwp_text_input_v3; serial: LongWord); cdecl;
begin
  if data <> nil then
    Tzwp_text_input_v3_listener(data).done(AProxy, serial);
end;

function zwp_text_input_v3_add_listener_object(AProxy: Pzwp_text_input_v3; AListener: Tzwp_text_input_v3_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zwp_text_input_v3, AListener);
end;

procedure zwp_text_input_v3_destroy(AProxy: Pzwp_text_input_v3);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TEXT_INPUT_V3_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure zwp_text_input_v3_enable(AProxy: Pzwp_text_input_v3);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TEXT_INPUT_V3_ENABLE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure zwp_text_input_v3_disable(AProxy: Pzwp_text_input_v3);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TEXT_INPUT_V3_DISABLE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure zwp_text_input_v3_set_surrounding_text(AProxy: Pzwp_text_input_v3; text: PAnsiChar; cursor: LongInt; anchor: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TEXT_INPUT_V3_SET_SURROUNDING_TEXT_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, text, cursor, anchor);
end;

procedure zwp_text_input_v3_set_text_change_cause(AProxy: Pzwp_text_input_v3; cause: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TEXT_INPUT_V3_SET_TEXT_CHANGE_CAUSE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, cause);
end;

procedure zwp_text_input_v3_set_content_type(AProxy: Pzwp_text_input_v3; hint: LongWord; purpose: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TEXT_INPUT_V3_SET_CONTENT_TYPE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, hint, purpose);
end;

procedure zwp_text_input_v3_set_cursor_rectangle(AProxy: Pzwp_text_input_v3; x: LongInt; y: LongInt; width: LongInt; height: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TEXT_INPUT_V3_SET_CURSOR_RECTANGLE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, x, y, width, height);
end;

procedure zwp_text_input_v3_commit(AProxy: Pzwp_text_input_v3);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TEXT_INPUT_V3_COMMIT_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure zwp_text_input_manager_v3_destroy(AProxy: Pzwp_text_input_manager_v3);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TEXT_INPUT_MANAGER_V3_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function zwp_text_input_manager_v3_get_text_input(AProxy: Pzwp_text_input_manager_v3; seat: Pwl_seat): Pzwp_text_input_v3;
begin
  EnsureProtocolInitialized;
  Result := Pzwp_text_input_v3(wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZWP_TEXT_INPUT_MANAGER_V3_GET_TEXT_INPUT_OPCODE, zwp_text_input_v3_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), seat));
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;

  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[4] := wl_surface_interface;
  GTypes[5] := wl_surface_interface;
  GTypes[6] := zwp_text_input_v3_interface;
  GTypes[7] := wl_seat_interface;

  GReq_zwp_text_input_v3[0].name := 'destroy';
  GReq_zwp_text_input_v3[0].signature := '';
  GReq_zwp_text_input_v3[0].types := @GTypes[0];
  GReq_zwp_text_input_v3[1].name := 'enable';
  GReq_zwp_text_input_v3[1].signature := '';
  GReq_zwp_text_input_v3[1].types := @GTypes[0];
  GReq_zwp_text_input_v3[2].name := 'disable';
  GReq_zwp_text_input_v3[2].signature := '';
  GReq_zwp_text_input_v3[2].types := @GTypes[0];
  GReq_zwp_text_input_v3[3].name := 'set_surrounding_text';
  GReq_zwp_text_input_v3[3].signature := 'sii';
  GReq_zwp_text_input_v3[3].types := @GTypes[0];
  GReq_zwp_text_input_v3[4].name := 'set_text_change_cause';
  GReq_zwp_text_input_v3[4].signature := 'u';
  GReq_zwp_text_input_v3[4].types := @GTypes[0];
  GReq_zwp_text_input_v3[5].name := 'set_content_type';
  GReq_zwp_text_input_v3[5].signature := 'uu';
  GReq_zwp_text_input_v3[5].types := @GTypes[0];
  GReq_zwp_text_input_v3[6].name := 'set_cursor_rectangle';
  GReq_zwp_text_input_v3[6].signature := 'iiii';
  GReq_zwp_text_input_v3[6].types := @GTypes[0];
  GReq_zwp_text_input_v3[7].name := 'commit';
  GReq_zwp_text_input_v3[7].signature := '';
  GReq_zwp_text_input_v3[7].types := @GTypes[0];
  GEvt_zwp_text_input_v3[0].name := 'enter';
  GEvt_zwp_text_input_v3[0].signature := 'o';
  GEvt_zwp_text_input_v3[0].types := @GTypes[4];
  GEvt_zwp_text_input_v3[1].name := 'leave';
  GEvt_zwp_text_input_v3[1].signature := 'o';
  GEvt_zwp_text_input_v3[1].types := @GTypes[5];
  GEvt_zwp_text_input_v3[2].name := 'preedit_string';
  GEvt_zwp_text_input_v3[2].signature := '?sii';
  GEvt_zwp_text_input_v3[2].types := @GTypes[0];
  GEvt_zwp_text_input_v3[3].name := 'commit_string';
  GEvt_zwp_text_input_v3[3].signature := '?s';
  GEvt_zwp_text_input_v3[3].types := @GTypes[0];
  GEvt_zwp_text_input_v3[4].name := 'delete_surrounding_text';
  GEvt_zwp_text_input_v3[4].signature := 'uu';
  GEvt_zwp_text_input_v3[4].types := @GTypes[0];
  GEvt_zwp_text_input_v3[5].name := 'done';
  GEvt_zwp_text_input_v3[5].signature := 'u';
  GEvt_zwp_text_input_v3[5].types := @GTypes[0];
  GIface_zwp_text_input_v3.name := 'zwp_text_input_v3';
  GIface_zwp_text_input_v3.version := 1;
  GIface_zwp_text_input_v3.method_count := 8;
  GIface_zwp_text_input_v3.methods := @GReq_zwp_text_input_v3[0];
  GIface_zwp_text_input_v3.event_count := 6;
  GIface_zwp_text_input_v3.events := @GEvt_zwp_text_input_v3[0];
  zwp_text_input_v3_interface := @GIface_zwp_text_input_v3;

  GReq_zwp_text_input_manager_v3[0].name := 'destroy';
  GReq_zwp_text_input_manager_v3[0].signature := '';
  GReq_zwp_text_input_manager_v3[0].types := @GTypes[0];
  GReq_zwp_text_input_manager_v3[1].name := 'get_text_input';
  GReq_zwp_text_input_manager_v3[1].signature := 'no';
  GReq_zwp_text_input_manager_v3[1].types := @GTypes[6];
  GIface_zwp_text_input_manager_v3.name := 'zwp_text_input_manager_v3';
  GIface_zwp_text_input_manager_v3.version := 1;
  GIface_zwp_text_input_manager_v3.method_count := 2;
  GIface_zwp_text_input_manager_v3.methods := @GReq_zwp_text_input_manager_v3[0];
  GIface_zwp_text_input_manager_v3.event_count := 0;
  GIface_zwp_text_input_manager_v3.events := nil;
  zwp_text_input_manager_v3_interface := @GIface_zwp_text_input_manager_v3;

  GThunks_zwp_text_input_v3.enter := @Thunk_zwp_text_input_v3_enter;
  GThunks_zwp_text_input_v3.leave := @Thunk_zwp_text_input_v3_leave;
  GThunks_zwp_text_input_v3.preedit_string := @Thunk_zwp_text_input_v3_preedit_string;
  GThunks_zwp_text_input_v3.commit_string := @Thunk_zwp_text_input_v3_commit_string;
  GThunks_zwp_text_input_v3.delete_surrounding_text := @Thunk_zwp_text_input_v3_delete_surrounding_text;
  GThunks_zwp_text_input_v3.done := @Thunk_zwp_text_input_v3_done;
end;

end.
