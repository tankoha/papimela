{
  PaPiMeLa.Platform.Wayland.Client — libwayland-client の実行時結合

  Origin : original work (clean-room design; not derived from SDL sources)
           シンボルの一覧は SDL_waylandsym.h を参考にしたが、構造は本設計に従う。
  Design : docs/DESIGN.md §9.3

  WHAT:
    libwayland-client を dlopen し、生成プロトコルユニット（tools/wlscan-pas の
    出力）が必要とする型と関数を公開する。プロトコル定義は含まない。

  WHY:
    Wayland は任意機能なので、不在はリンクエラーではなく実行時の能力判定で
    なければならない。関数を変数（関数ポインタ）として公開しているのは、
    生成コードが可変長引数の wl_proxy_marshal_flags を直接呼ぶため。
    ポインタ経由の varargs 呼び出しが動作することは実測で確認した。

  RESOLVED:
    - コアプロトコルの wl_interface 記述子は libwayland が公開しているので
      dlsym で引く。拡張プロトコルの記述子は生成ユニットが自分で組む
    - ロードは参照カウント付き。多重呼び出し安全

  NOT RESOLVED:
    - wl_egl_window_* / wl_cursor_* は EGL / カーソル着手時に追加する
    - wl_list / wl_array の操作関数はインライン関数なので、必要になったら
      Pascal 側で再実装する

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.Wayland.Client;

{$I papimela.inc}
{$packrecords c}

interface

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.DynLib;

const
  WL_MARSHAL_FLAG_DESTROY = 1 shl 0;

type
  // 不透明型。生成ユニットがインターフェースごとの別名を定義する。
  Twl_proxy_opaque = record end;
  Pwl_proxy = ^Twl_proxy_opaque;

  Twl_display_opaque = record end;
  Pwl_display = ^Twl_display_opaque;

  Twl_event_queue_opaque = record end;
  Pwl_event_queue = ^Twl_event_queue_opaque;

  wl_fixed_t = LongInt;

  Twl_array = record
    size : PtrUInt;
    alloc: PtrUInt;
    data : Pointer;
  end;
  Pwl_array = ^Twl_array;

  Pwl_interface  = ^Twl_interface;
  PPwl_interface = ^Pwl_interface;
  Pwl_message    = ^Twl_message;

  Twl_message = record
    name     : PAnsiChar;
    signature: PAnsiChar;
    types    : PPwl_interface;
  end;

  Twl_interface = record
    name        : PAnsiChar;
    version     : LongInt;
    method_count: LongInt;
    methods     : Pwl_message;
    event_count : LongInt;
    events      : Pwl_message;
  end;

var
  // ---- wl_proxy（生成コードが使う）
  wl_proxy_marshal_flags: function(proxy: Pwl_proxy; opcode: LongWord;
    iface: Pwl_interface; version: LongWord; flags: LongWord): Pwl_proxy;
    cdecl; varargs = nil;
  wl_proxy_get_version : function(proxy: Pwl_proxy): LongWord; cdecl = nil;
  wl_proxy_add_listener: function(proxy: Pwl_proxy; impl: PPointer;
    data: Pointer): LongInt; cdecl = nil;
  wl_proxy_destroy     : procedure(proxy: Pwl_proxy); cdecl = nil;
  wl_proxy_set_user_data: procedure(proxy: Pwl_proxy; data: Pointer); cdecl = nil;
  wl_proxy_get_user_data: function(proxy: Pwl_proxy): Pointer; cdecl = nil;
  wl_proxy_get_id      : function(proxy: Pwl_proxy): LongWord; cdecl = nil;
  wl_proxy_get_class   : function(proxy: Pwl_proxy): PAnsiChar; cdecl = nil;
  wl_proxy_set_queue   : procedure(proxy: Pwl_proxy; queue: Pwl_event_queue); cdecl = nil;

  // ---- wl_display
  wl_display_connect        : function(name: PAnsiChar): Pwl_display; cdecl = nil;
  wl_display_connect_to_fd  : function(fd: LongInt): Pwl_display; cdecl = nil;
  wl_display_disconnect     : procedure(display: Pwl_display); cdecl = nil;
  wl_display_get_fd         : function(display: Pwl_display): LongInt; cdecl = nil;
  wl_display_dispatch       : function(display: Pwl_display): LongInt; cdecl = nil;
  wl_display_dispatch_pending: function(display: Pwl_display): LongInt; cdecl = nil;
  wl_display_flush          : function(display: Pwl_display): LongInt; cdecl = nil;
  wl_display_roundtrip      : function(display: Pwl_display): LongInt; cdecl = nil;
  wl_display_get_error      : function(display: Pwl_display): LongInt; cdecl = nil;
  wl_display_prepare_read   : function(display: Pwl_display): LongInt; cdecl = nil;
  wl_display_read_events    : function(display: Pwl_display): LongInt; cdecl = nil;
  wl_display_cancel_read    : procedure(display: Pwl_display); cdecl = nil;

  // ---- wl_event_queue
  wl_event_queue_destroy       : procedure(queue: Pwl_event_queue); cdecl = nil;
  wl_display_create_queue      : function(display: Pwl_display): Pwl_event_queue; cdecl = nil;
  wl_display_dispatch_queue    : function(display: Pwl_display;
    queue: Pwl_event_queue): LongInt; cdecl = nil;
  wl_display_roundtrip_queue   : function(display: Pwl_display;
    queue: Pwl_event_queue): LongInt; cdecl = nil;

// libwayland-client をロードする。既にロード済みなら参照カウントを増やすだけ。
// False = libwayland が無い（Wayland を使えない環境）。
function  PMLWaylandClientLoad: Boolean;
procedure PMLWaylandClientUnload;
function  PMLWaylandClientLoaded: Boolean;

// wl_fixed_t（24.8 固定小数点）との相互変換。libwayland のインライン関数
// wl_fixed_to_double / wl_fixed_from_double に相当する。インラインなので
// dlsym では引けず、自前で持つ必要がある。
function  PMLFixedToSingle(AValue: wl_fixed_t): Single; inline;
function  PMLSingleToFixed(AValue: Single): wl_fixed_t; inline;

// 生成プロトコルユニットがコアの wl_interface 記述子を引くために使う。
// 見つからなければ nil。
function PMLWaylandResolve(const ASymbol: String): Pointer;

implementation

const
  LIBWAYLAND_NAMES: array[0..1] of String = ('libwayland-client.so.0', 'libwayland-client.so');

var
  GLib     : TPMLDynLib = nil;
  GRefCount: Integer = 0;

procedure Bind(out ATarget; const ASymbol: String);
begin
  Pointer(ATarget) := GLib.Resolve(ASymbol);
end;

{ 24.8 固定小数点。下位 8 ビットが小数部。 }
function PMLFixedToSingle(AValue: wl_fixed_t): Single;
begin
  Result := AValue / 256.0;
end;

function PMLSingleToFixed(AValue: Single): wl_fixed_t;
begin
  Result := Round(AValue * 256.0);
end;

procedure LoadAll;
begin
  Bind(wl_proxy_marshal_flags, 'wl_proxy_marshal_flags');
  Bind(wl_proxy_get_version,   'wl_proxy_get_version');
  Bind(wl_proxy_add_listener,  'wl_proxy_add_listener');
  Bind(wl_proxy_destroy,       'wl_proxy_destroy');
  Bind(wl_proxy_set_user_data, 'wl_proxy_set_user_data');
  Bind(wl_proxy_get_user_data, 'wl_proxy_get_user_data');
  Bind(wl_proxy_get_id,        'wl_proxy_get_id');
  Bind(wl_proxy_get_class,     'wl_proxy_get_class');
  Bind(wl_proxy_set_queue,     'wl_proxy_set_queue');

  Bind(wl_display_connect,         'wl_display_connect');
  Bind(wl_display_connect_to_fd,   'wl_display_connect_to_fd');
  Bind(wl_display_disconnect,      'wl_display_disconnect');
  Bind(wl_display_get_fd,          'wl_display_get_fd');
  Bind(wl_display_dispatch,        'wl_display_dispatch');
  Bind(wl_display_dispatch_pending,'wl_display_dispatch_pending');
  Bind(wl_display_flush,           'wl_display_flush');
  Bind(wl_display_roundtrip,       'wl_display_roundtrip');
  Bind(wl_display_get_error,       'wl_display_get_error');
  Bind(wl_display_prepare_read,    'wl_display_prepare_read');
  Bind(wl_display_read_events,     'wl_display_read_events');
  Bind(wl_display_cancel_read,     'wl_display_cancel_read');

  Bind(wl_event_queue_destroy,    'wl_event_queue_destroy');
  Bind(wl_display_create_queue,   'wl_display_create_queue');
  Bind(wl_display_dispatch_queue, 'wl_display_dispatch_queue');
  Bind(wl_display_roundtrip_queue,'wl_display_roundtrip_queue');
end;

function PMLWaylandClientLoad: Boolean;
begin
  if GRefCount > 0 then
  begin
    Inc(GRefCount);
    Exit(True);
  end;
  try
    GLib := TPMLDynLib.Create(LIBWAYLAND_NAMES);
  except
    on E: EPMLPlatformLibrary do
    begin
      GLib := nil;
      Exit(False);
    end;
  end;
  LoadAll;
  GRefCount := 1;
  Result := True;
end;

procedure PMLWaylandClientUnload;
begin
  if GRefCount = 0 then
    Exit;
  Dec(GRefCount);
  if GRefCount > 0 then
    Exit;
  FreeAndNil(GLib);
  wl_proxy_marshal_flags := nil;
end;

function PMLWaylandClientLoaded: Boolean;
begin
  Result := GRefCount > 0;
end;

function PMLWaylandResolve(const ASymbol: String): Pointer;
begin
  if GLib = nil then
    Exit(nil);
  Result := GLib.TryResolve(ASymbol);
end;

end.
