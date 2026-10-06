{
  PaPiMeLa.Platform.Wayland.Protocols.XdgOutputUnstableV1

  自動生成ファイル。手で編集しないこと。
  生成元: xdg_output_unstable_v1.xml
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
unit PaPiMeLa.Platform.Wayland.Protocols.XdgOutputUnstableV1;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  Tzxdg_output_manager_v1_opaque = record end;
  Pzxdg_output_manager_v1 = ^Tzxdg_output_manager_v1_opaque;
  Tzxdg_output_v1_opaque = record end;
  Pzxdg_output_v1 = ^Tzxdg_output_v1_opaque;

const
  // zxdg_output_manager_v1 (version 3)
  ZXDG_OUTPUT_MANAGER_V1_DESTROY_OPCODE = 0;
  ZXDG_OUTPUT_MANAGER_V1_GET_XDG_OUTPUT_OPCODE = 1;
  ZXDG_OUTPUT_MANAGER_V1_DESTROY_SINCE_VERSION = 1;
  ZXDG_OUTPUT_MANAGER_V1_GET_XDG_OUTPUT_SINCE_VERSION = 1;

  // zxdg_output_v1 (version 3)
  ZXDG_OUTPUT_V1_DESTROY_OPCODE = 0;
  ZXDG_OUTPUT_V1_DESTROY_SINCE_VERSION = 1;
  ZXDG_OUTPUT_V1_LOGICAL_POSITION_SINCE_VERSION = 1;
  ZXDG_OUTPUT_V1_LOGICAL_SIZE_SINCE_VERSION = 1;
  ZXDG_OUTPUT_V1_DONE_SINCE_VERSION = 1;
  ZXDG_OUTPUT_V1_NAME_SINCE_VERSION = 2;
  ZXDG_OUTPUT_V1_DESCRIPTION_SINCE_VERSION = 2;

var
  zxdg_output_manager_v1_interface: Pwl_interface = nil;
  zxdg_output_v1_interface: Pwl_interface = nil;

type
  Tzxdg_output_v1_listener = class abstract(TObject)
  public
    procedure logical_position(AProxy: Pzxdg_output_v1; x: LongInt; y: LongInt); virtual;
    procedure logical_size(AProxy: Pzxdg_output_v1; width: LongInt; height: LongInt); virtual;
    procedure done(AProxy: Pzxdg_output_v1); virtual;
    procedure name(AProxy: Pzxdg_output_v1; name_: PAnsiChar); virtual;
    procedure description(AProxy: Pzxdg_output_v1; description_: PAnsiChar); virtual;
  end;

  Tzxdg_output_v1_listener_rec = record
    logical_position: procedure(data: Pointer; AProxy: Pzxdg_output_v1; x: LongInt; y: LongInt); cdecl;
    logical_size: procedure(data: Pointer; AProxy: Pzxdg_output_v1; width: LongInt; height: LongInt); cdecl;
    done: procedure(data: Pointer; AProxy: Pzxdg_output_v1); cdecl;
    name: procedure(data: Pointer; AProxy: Pzxdg_output_v1; name_: PAnsiChar); cdecl;
    description: procedure(data: Pointer; AProxy: Pzxdg_output_v1; description_: PAnsiChar); cdecl;
  end;

procedure zxdg_output_manager_v1_destroy(AProxy: Pzxdg_output_manager_v1);
function zxdg_output_manager_v1_get_xdg_output(AProxy: Pzxdg_output_manager_v1; output: Pwl_output): Pzxdg_output_v1;

function zxdg_output_v1_add_listener_object(AProxy: Pzxdg_output_v1; AListener: Tzxdg_output_v1_listener): LongInt;
procedure zxdg_output_v1_destroy(AProxy: Pzxdg_output_v1);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..3] of Pwl_interface;
  GReq_zxdg_output_manager_v1: array[0..1] of Twl_message;
  GIface_zxdg_output_manager_v1: Twl_interface;
  GReq_zxdg_output_v1: array[0..0] of Twl_message;
  GEvt_zxdg_output_v1: array[0..4] of Twl_message;
  GIface_zxdg_output_v1: Twl_interface;

var
  GInitialized: Boolean = False;
  GThunks_zxdg_output_v1: Tzxdg_output_v1_listener_rec;

procedure Tzxdg_output_v1_listener.logical_position(AProxy: Pzxdg_output_v1; x: LongInt; y: LongInt);
begin
end;

procedure Tzxdg_output_v1_listener.logical_size(AProxy: Pzxdg_output_v1; width: LongInt; height: LongInt);
begin
end;

procedure Tzxdg_output_v1_listener.done(AProxy: Pzxdg_output_v1);
begin
end;

procedure Tzxdg_output_v1_listener.name(AProxy: Pzxdg_output_v1; name_: PAnsiChar);
begin
end;

procedure Tzxdg_output_v1_listener.description(AProxy: Pzxdg_output_v1; description_: PAnsiChar);
begin
end;

procedure Thunk_zxdg_output_v1_logical_position(data: Pointer; AProxy: Pzxdg_output_v1; x: LongInt; y: LongInt); cdecl;
begin
  if data <> nil then
    Tzxdg_output_v1_listener(data).logical_position(AProxy, x, y);
end;

procedure Thunk_zxdg_output_v1_logical_size(data: Pointer; AProxy: Pzxdg_output_v1; width: LongInt; height: LongInt); cdecl;
begin
  if data <> nil then
    Tzxdg_output_v1_listener(data).logical_size(AProxy, width, height);
end;

procedure Thunk_zxdg_output_v1_done(data: Pointer; AProxy: Pzxdg_output_v1); cdecl;
begin
  if data <> nil then
    Tzxdg_output_v1_listener(data).done(AProxy);
end;

procedure Thunk_zxdg_output_v1_name(data: Pointer; AProxy: Pzxdg_output_v1; name_: PAnsiChar); cdecl;
begin
  if data <> nil then
    Tzxdg_output_v1_listener(data).name(AProxy, name_);
end;

procedure Thunk_zxdg_output_v1_description(data: Pointer; AProxy: Pzxdg_output_v1; description_: PAnsiChar); cdecl;
begin
  if data <> nil then
    Tzxdg_output_v1_listener(data).description(AProxy, description_);
end;

function zxdg_output_v1_add_listener_object(AProxy: Pzxdg_output_v1; AListener: Tzxdg_output_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_zxdg_output_v1, AListener);
end;

procedure zxdg_output_manager_v1_destroy(AProxy: Pzxdg_output_manager_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZXDG_OUTPUT_MANAGER_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function zxdg_output_manager_v1_get_xdg_output(AProxy: Pzxdg_output_manager_v1; output: Pwl_output): Pzxdg_output_v1;
begin
  EnsureProtocolInitialized;
  Result := Pzxdg_output_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZXDG_OUTPUT_MANAGER_V1_GET_XDG_OUTPUT_OPCODE, zxdg_output_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), output));
end;

procedure zxdg_output_v1_destroy(AProxy: Pzxdg_output_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), ZXDG_OUTPUT_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;

  zxdg_output_manager_v1_interface := @GIface_zxdg_output_manager_v1;
  zxdg_output_v1_interface := @GIface_zxdg_output_v1;
  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[2] := zxdg_output_v1_interface;
  GTypes[3] := wl_output_interface;

  GReq_zxdg_output_manager_v1[0].name := 'destroy';
  GReq_zxdg_output_manager_v1[0].signature := '';
  GReq_zxdg_output_manager_v1[0].types := @GTypes[0];
  GReq_zxdg_output_manager_v1[1].name := 'get_xdg_output';
  GReq_zxdg_output_manager_v1[1].signature := 'no';
  GReq_zxdg_output_manager_v1[1].types := @GTypes[2];
  GIface_zxdg_output_manager_v1.name := 'zxdg_output_manager_v1';
  GIface_zxdg_output_manager_v1.version := 3;
  GIface_zxdg_output_manager_v1.method_count := 2;
  GIface_zxdg_output_manager_v1.methods := @GReq_zxdg_output_manager_v1[0];
  GIface_zxdg_output_manager_v1.event_count := 0;
  GIface_zxdg_output_manager_v1.events := nil;

  GReq_zxdg_output_v1[0].name := 'destroy';
  GReq_zxdg_output_v1[0].signature := '';
  GReq_zxdg_output_v1[0].types := @GTypes[0];
  GEvt_zxdg_output_v1[0].name := 'logical_position';
  GEvt_zxdg_output_v1[0].signature := 'ii';
  GEvt_zxdg_output_v1[0].types := @GTypes[0];
  GEvt_zxdg_output_v1[1].name := 'logical_size';
  GEvt_zxdg_output_v1[1].signature := 'ii';
  GEvt_zxdg_output_v1[1].types := @GTypes[0];
  GEvt_zxdg_output_v1[2].name := 'done';
  GEvt_zxdg_output_v1[2].signature := '';
  GEvt_zxdg_output_v1[2].types := @GTypes[0];
  GEvt_zxdg_output_v1[3].name := 'name';
  GEvt_zxdg_output_v1[3].signature := '2s';
  GEvt_zxdg_output_v1[3].types := @GTypes[0];
  GEvt_zxdg_output_v1[4].name := 'description';
  GEvt_zxdg_output_v1[4].signature := '2s';
  GEvt_zxdg_output_v1[4].types := @GTypes[0];
  GIface_zxdg_output_v1.name := 'zxdg_output_v1';
  GIface_zxdg_output_v1.version := 3;
  GIface_zxdg_output_v1.method_count := 1;
  GIface_zxdg_output_v1.methods := @GReq_zxdg_output_v1[0];
  GIface_zxdg_output_v1.event_count := 5;
  GIface_zxdg_output_v1.events := @GEvt_zxdg_output_v1[0];

  GThunks_zxdg_output_v1.logical_position := @Thunk_zxdg_output_v1_logical_position;
  GThunks_zxdg_output_v1.logical_size := @Thunk_zxdg_output_v1_logical_size;
  GThunks_zxdg_output_v1.done := @Thunk_zxdg_output_v1_done;
  GThunks_zxdg_output_v1.name := @Thunk_zxdg_output_v1_name;
  GThunks_zxdg_output_v1.description := @Thunk_zxdg_output_v1_description;
end;

end.
