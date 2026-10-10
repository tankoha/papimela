{
  PaPiMeLa.Platform.DBus — libdbus-1 の実行時結合

  Origin : original work (clean-room design; not derived from SDL sources)
           SDL_dbus.c は構造を参照していない。接続手順は spikes/spike2_fcitx.pas で
           実測した順序に基づく。
  Design : docs/DESIGN.md §11 #16

  WHAT:
    libdbus-1 を dlopen で結合し、メソッド呼び出しとシグナル受信、および
    D-Bus の型システムを再帰的に読み書きする Reader / Writer を提供する。

  WHY:
    IME 経路（Fcitx5 / IBus）の土台。入力コンテキストは D-Bus 接続に紐づいて
    破棄されるため、接続を保持するオブジェクトが必要になる。

  RESOLVED:
    - 接続はプライベート接続（dbus_bus_get_private）。他の用途と共有しない
    - IBus の私設バスはアドレスを指定して繋ぐ（CreateForAddress。open_private + bus_register）
    - シグナル受信は dbus_connection_pop_message のポーリング
    - C コールバック境界を作らないので例外遮断は不要

  NOT RESOLVED:
    - dbus_connection_set_watch_functions によるイベントループ統合は、
      PaPiMeLa.Core の Pump が存在してから行う（Design: docs/DESIGN.md §6.3）
    - 返信を待たない呼び出しは SendAsync（通し番号を返す）。返信は PopMessage で通知と同じ列に
      届くので、ReplySerialOf で突き合わせる（dbus_pending_call は使わない。spikes/spike3_ibus.pas で実測）
}
unit PaPiMeLa.Platform.DBus;

{$I papimela.inc}
{$packrecords c}

interface

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.DynLib;

const
  DBUS_BUS_SESSION = 0;
  DBUS_BUS_SYSTEM  = 1;

  // 型コード（ASCII）
  DBUS_TYPE_INVALID     = 0;
  DBUS_TYPE_BOOLEAN     = Ord('b');
  DBUS_TYPE_INT16       = Ord('n');
  DBUS_TYPE_UINT16      = Ord('q');
  DBUS_TYPE_INT32       = Ord('i');
  DBUS_TYPE_UINT32      = Ord('u');
  DBUS_TYPE_INT64       = Ord('x');
  DBUS_TYPE_UINT64      = Ord('t');
  DBUS_TYPE_DOUBLE      = Ord('d');
  DBUS_TYPE_STRING      = Ord('s');
  DBUS_TYPE_OBJECT_PATH = Ord('o');
  DBUS_TYPE_SIGNATURE   = Ord('g');
  DBUS_TYPE_ARRAY       = Ord('a');
  DBUS_TYPE_UNIX_FD     = Ord('h');
  DBUS_TYPE_STRUCT      = Ord('r');
  DBUS_TYPE_VARIANT     = Ord('v');
  DBUS_TYPE_BYTE        = Ord('y');
  DBUS_TYPE_DICT_ENTRY  = Ord('e');

  // dbus_message_get_type の値
  DBUS_MESSAGE_TYPE_METHOD_CALL   = 1;
  DBUS_MESSAGE_TYPE_METHOD_RETURN = 2;
  DBUS_MESSAGE_TYPE_ERROR         = 3;
  DBUS_MESSAGE_TYPE_SIGNAL        = 4;

type
  PDBusConnection = Pointer;
  PDBusMessage    = Pointer;

  TDBusError = record
    name     : PAnsiChar;
    message_ : PAnsiChar;
    bits     : LongWord;   // C 側は 5 個のビットフィールド
    padding1 : Pointer;
  end;
  PDBusError = ^TDBusError;

  // 不透明構造体。実サイズは 72 バイト程度。余裕を持たせる。
  TDBusMessageIter = record
    opaque: array[0..95] of Byte;
  end;
  PDBusMessageIter = ^TDBusMessageIter;

  // libdbus-1 の関数ポインタ表
  TPMLDBusAPI = record
    error_init   : procedure(err: PDBusError); cdecl;
    error_free   : procedure(err: PDBusError); cdecl;
    error_is_set : function(err: PDBusError): LongWord; cdecl;

    bus_get_private       : function(bustype: LongInt; err: PDBusError): PDBusConnection; cdecl;
    bus_register          : function(conn: PDBusConnection; err: PDBusError): LongWord; cdecl;
    connection_open_private: function(address: PAnsiChar; err: PDBusError): PDBusConnection; cdecl;
    bus_add_match         : procedure(conn: PDBusConnection; rule: PAnsiChar; err: PDBusError); cdecl;
    bus_remove_match      : procedure(conn: PDBusConnection; rule: PAnsiChar; err: PDBusError); cdecl;
    bus_name_has_owner    : function(conn: PDBusConnection; name: PAnsiChar; err: PDBusError): LongWord; cdecl;

    connection_close                 : procedure(conn: PDBusConnection); cdecl;
    connection_unref                 : procedure(conn: PDBusConnection); cdecl;
    connection_flush                 : procedure(conn: PDBusConnection); cdecl;
    connection_read_write            : function(conn: PDBusConnection; timeout_ms: LongInt): LongWord; cdecl;
    connection_pop_message           : function(conn: PDBusConnection): PDBusMessage; cdecl;
    connection_get_is_connected      : function(conn: PDBusConnection): LongWord; cdecl;
    connection_set_exit_on_disconnect: procedure(conn: PDBusConnection; exit_on_disconnect: LongWord); cdecl;
    connection_send_with_reply_and_block: function(conn: PDBusConnection; msg: PDBusMessage;
      timeout_ms: LongInt; err: PDBusError): PDBusMessage; cdecl;
    connection_send                  : function(conn: PDBusConnection; msg: PDBusMessage;
      serial: PLongWord): LongWord; cdecl;

    message_new_method_call: function(dest, path, iface, method: PAnsiChar): PDBusMessage; cdecl;
    message_unref          : procedure(msg: PDBusMessage); cdecl;
    message_is_signal      : function(msg: PDBusMessage; iface, signame: PAnsiChar): LongWord; cdecl;
    message_get_member     : function(msg: PDBusMessage): PAnsiChar; cdecl;
    message_get_interface  : function(msg: PDBusMessage): PAnsiChar; cdecl;
    message_get_path       : function(msg: PDBusMessage): PAnsiChar; cdecl;
    message_get_type       : function(msg: PDBusMessage): LongInt; cdecl;
    message_get_reply_serial: function(msg: PDBusMessage): LongWord; cdecl;
    message_get_error_name : function(msg: PDBusMessage): PAnsiChar; cdecl;

    message_iter_init_append   : procedure(msg: PDBusMessage; iter: PDBusMessageIter); cdecl;
    message_iter_append_basic  : function(iter: PDBusMessageIter; atype: LongInt; value: Pointer): LongWord; cdecl;
    message_iter_open_container: function(iter: PDBusMessageIter; atype: LongInt;
      sig: PAnsiChar; sub: PDBusMessageIter): LongWord; cdecl;
    message_iter_close_container: function(iter, sub: PDBusMessageIter): LongWord; cdecl;

    message_iter_init        : function(msg: PDBusMessage; iter: PDBusMessageIter): LongWord; cdecl;
    message_iter_get_arg_type: function(iter: PDBusMessageIter): LongInt; cdecl;
    message_iter_get_basic   : procedure(iter: PDBusMessageIter; value: Pointer); cdecl;
    message_iter_recurse     : procedure(iter, sub: PDBusMessageIter); cdecl;
    message_iter_next        : function(iter: PDBusMessageIter): LongWord; cdecl;
  end;
  PPMLDBusAPI = ^TPMLDBusAPI;

  { シグネチャ駆動の再帰リーダ。

    値型なので Recurse は子リーダを返す。親の Next は子を読み終えてから呼ぶ。 }
  TPMLDBusReader = record
  strict private
    FIter: TDBusMessageIter;
    FAPI : PPMLDBusAPI;
    procedure GetBasic(out AValue);
  public
    class function FromMessage(AAPI: PPMLDBusAPI; AMsg: PDBusMessage): TPMLDBusReader; static;

    function ArgType: LongInt; inline;
    function AtEnd: Boolean; inline;
    function Next: Boolean;
    function Recurse: TPMLDBusReader;

    function AsString: String;
    function AsInt32: LongInt;
    function AsUInt32: LongWord;
    function AsInt64: Int64;
    function AsUInt64: QWord;
    function AsDouble: Double;
    function AsBoolean: Boolean;

    // 型が一致しなければ例外。取得後に Next はしない。
    function ExpectString: String;
    function ExpectObjectPath: String;
    function ExpectInt32: LongInt;
    function ExpectBoolean: Boolean;
  end;

  { 引数の書き込み。OpenArray / OpenStruct で得た子は必ず Close に渡す。 }
  TPMLDBusWriter = record
  strict private
    FIter: TDBusMessageIter;
    FAPI : PPMLDBusAPI;
    procedure AddBasic(AType: LongInt; AValue: Pointer);
  public
    class function ForMessage(AAPI: PPMLDBusAPI; AMsg: PDBusMessage): TPMLDBusWriter; static;

    procedure AddString(const AValue: String);
    procedure AddObjectPath(const AValue: String);
    procedure AddInt32(AValue: LongInt);
    procedure AddUInt32(AValue: LongWord);
    procedure AddUInt64(AValue: QWord);
    // ファイル記述子を渡す（型 h）。libdbus が複製して送るので、AFD は呼び出し側が閉じてよい。
    procedure AddUnixFD(AFD: LongInt);
    procedure AddDouble(AValue: Double);
    procedure AddBoolean(AValue: Boolean);

    function OpenArray(const AElementSignature: String): TPMLDBusWriter;
    function OpenStruct: TPMLDBusWriter;
    // AContentSignature は中身 1 つの型（例: '(sa{sv}sv)'）。
    function OpenVariant(const AContentSignature: String): TPMLDBusWriter;
    function OpenDictEntry: TPMLDBusWriter;
    procedure Close(var ASub: TPMLDBusWriter);
  end;

  { プライベートな D-Bus 接続。 }
  TPMLDBusConnection = class
  strict private
    FLib   : TPMLDynLib;
    FAPI   : TPMLDBusAPI;
    FConn  : PDBusConnection;
    FErr   : TDBusError;
    // untyped out を使うのは、FPC が Pointer から手続き変数型への暗黙変換を
    // 許さないため。呼び出し 30 箇所に個別のキャストを書くのを避ける。
    procedure Bind(out ATarget; const ASymbol: String);
    procedure LoadAPI;
    procedure RaiseIfError(const AWhat: String);
    procedure ClearError;
  public
    constructor Create(ABusType: LongInt = DBUS_BUS_SESSION);
    // アドレスを指定して繋ぐ（IBus の私設バスなど）。Hello（bus_register）まで済ませる。
    constructor CreateForAddress(const AAddress: String);
    // どこにも繋がない。メッセージの組み立てと読み取りだけに使う（表示サーバも
    // IME も無しで IBusText の読み書きを検査するため）。送る操作は使えない。
    constructor CreateOffline;
    destructor Destroy; override;

    function IsConnected: Boolean;
    function NameHasOwner(const AName: String): Boolean;

    procedure AddMatch(const ARule: String);
    procedure RemoveMatch(const ARule: String);
    procedure Flush;

    // 呼び出しの組み立て。返した message は Unref すること。
    function BeginCall(const AService, APath, AIface, AMethod: String): PDBusMessage;
    function Writer(AMsg: PDBusMessage): TPMLDBusWriter;
    // 返信を返す。呼び出し側が Unref する。エラー時は例外。
    function Send(AMsg: PDBusMessage; ATimeoutMs: LongInt = 3000): PDBusMessage;
    procedure Unref(AMsg: PDBusMessage);
    function Reader(AMsg: PDBusMessage): TPMLDBusReader;

    // 引数なし・戻り値なしの呼び出し。
    procedure CallVoid(const AService, APath, AIface, AMethod: String);

    // 受信キューから 1 通取り出す。無ければ nil。呼び出し側が Unref する。
    function PopMessage(ATimeoutMs: LongInt): PDBusMessage;

    function IsSignal(AMsg: PDBusMessage; const AIface, AName: String): Boolean;
    function MemberOf(AMsg: PDBusMessage): String;
    function TypeOf(AMsg: PDBusMessage): LongInt;
    // 返信（METHOD_RETURN / ERROR）が答えている呼び出しの通し番号。
    function ReplySerialOf(AMsg: PDBusMessage): LongWord;
    function ErrorNameOf(AMsg: PDBusMessage): String;

    // 返信を待たずに送る。返信は PopMessage で他の通知と同じ列に届くので、
    // ReplySerialOf をこの戻り値と突き合わせる。
    function SendAsync(AMsg: PDBusMessage): LongWord;

    property API: TPMLDBusAPI read FAPI;
  end;

implementation

const
  LIBDBUS_NAMES: array[0..1] of String = ('libdbus-1.so.3', 'libdbus-1.so');

{ TPMLDBusReader }

class function TPMLDBusReader.FromMessage(AAPI: PPMLDBusAPI; AMsg: PDBusMessage): TPMLDBusReader;
begin
  Result.FAPI := AAPI;
  FillChar(Result.FIter, SizeOf(Result.FIter), 0);
  AAPI^.message_iter_init(AMsg, @Result.FIter);
end;

function TPMLDBusReader.ArgType: LongInt;
begin
  Result := FAPI^.message_iter_get_arg_type(@FIter);
end;

function TPMLDBusReader.AtEnd: Boolean;
begin
  Result := ArgType = DBUS_TYPE_INVALID;
end;

function TPMLDBusReader.Next: Boolean;
begin
  Result := FAPI^.message_iter_next(@FIter) <> 0;
end;

function TPMLDBusReader.Recurse: TPMLDBusReader;
begin
  Result.FAPI := FAPI;
  FillChar(Result.FIter, SizeOf(Result.FIter), 0);
  FAPI^.message_iter_recurse(@FIter, @Result.FIter);
end;

procedure TPMLDBusReader.GetBasic(out AValue);
begin
  FAPI^.message_iter_get_basic(@FIter, @AValue);
end;

function TPMLDBusReader.AsString: String;
var
  P: PAnsiChar;
begin
  P := nil;
  GetBasic(P);
  if P = nil then
    Result := ''
  else
    Result := String(P);
end;

function TPMLDBusReader.AsInt32: LongInt;
begin
  Result := 0;
  GetBasic(Result);
end;

function TPMLDBusReader.AsUInt32: LongWord;
begin
  Result := 0;
  GetBasic(Result);
end;

function TPMLDBusReader.AsInt64: Int64;
begin
  Result := 0;
  GetBasic(Result);
end;

function TPMLDBusReader.AsUInt64: QWord;
begin
  Result := 0;
  GetBasic(Result);
end;

function TPMLDBusReader.AsDouble: Double;
begin
  Result := 0;
  GetBasic(Result);
end;

function TPMLDBusReader.AsBoolean: Boolean;
var
  V: LongWord;
begin
  V := 0;
  GetBasic(V);
  Result := V <> 0;
end;

function TPMLDBusReader.ExpectString: String;
begin
  if ArgType <> DBUS_TYPE_STRING then
    raise EPMLError.CreateFmt('D-Bus: expected string, got type code %d', [ArgType]);
  Result := AsString;
end;

function TPMLDBusReader.ExpectObjectPath: String;
begin
  if ArgType <> DBUS_TYPE_OBJECT_PATH then
    raise EPMLError.CreateFmt('D-Bus: expected object path, got type code %d', [ArgType]);
  Result := AsString;
end;

function TPMLDBusReader.ExpectInt32: LongInt;
begin
  if ArgType <> DBUS_TYPE_INT32 then
    raise EPMLError.CreateFmt('D-Bus: expected int32, got type code %d', [ArgType]);
  Result := AsInt32;
end;

function TPMLDBusReader.ExpectBoolean: Boolean;
begin
  if ArgType <> DBUS_TYPE_BOOLEAN then
    raise EPMLError.CreateFmt('D-Bus: expected boolean, got type code %d', [ArgType]);
  Result := AsBoolean;
end;

{ TPMLDBusWriter }

class function TPMLDBusWriter.ForMessage(AAPI: PPMLDBusAPI; AMsg: PDBusMessage): TPMLDBusWriter;
begin
  Result.FAPI := AAPI;
  FillChar(Result.FIter, SizeOf(Result.FIter), 0);
  AAPI^.message_iter_init_append(AMsg, @Result.FIter);
end;

procedure TPMLDBusWriter.AddBasic(AType: LongInt; AValue: Pointer);
begin
  if FAPI^.message_iter_append_basic(@FIter, AType, AValue) = 0 then
    raise EPMLError.Create('D-Bus: out of memory while appending argument');
end;

procedure TPMLDBusWriter.AddString(const AValue: String);
var
  P: PAnsiChar;
begin
  P := PAnsiChar(AValue);
  AddBasic(DBUS_TYPE_STRING, @P);
end;

procedure TPMLDBusWriter.AddObjectPath(const AValue: String);
var
  P: PAnsiChar;
begin
  P := PAnsiChar(AValue);
  AddBasic(DBUS_TYPE_OBJECT_PATH, @P);
end;

procedure TPMLDBusWriter.AddInt32(AValue: LongInt);
begin
  AddBasic(DBUS_TYPE_INT32, @AValue);
end;

procedure TPMLDBusWriter.AddUInt32(AValue: LongWord);
begin
  AddBasic(DBUS_TYPE_UINT32, @AValue);
end;

procedure TPMLDBusWriter.AddUInt64(AValue: QWord);
begin
  AddBasic(DBUS_TYPE_UINT64, @AValue);
end;

procedure TPMLDBusWriter.AddUnixFD(AFD: LongInt);
begin
  AddBasic(DBUS_TYPE_UNIX_FD, @AFD);
end;

procedure TPMLDBusWriter.AddDouble(AValue: Double);
begin
  AddBasic(DBUS_TYPE_DOUBLE, @AValue);
end;

procedure TPMLDBusWriter.AddBoolean(AValue: Boolean);
var
  V: LongWord;
begin
  V := Ord(AValue);
  AddBasic(DBUS_TYPE_BOOLEAN, @V);
end;

function TPMLDBusWriter.OpenArray(const AElementSignature: String): TPMLDBusWriter;
begin
  Result.FAPI := FAPI;
  FillChar(Result.FIter, SizeOf(Result.FIter), 0);
  if FAPI^.message_iter_open_container(@FIter, DBUS_TYPE_ARRAY,
       PAnsiChar(AElementSignature), @Result.FIter) = 0 then
    raise EPMLError.Create('D-Bus: failed to open array container');
end;

function TPMLDBusWriter.OpenStruct: TPMLDBusWriter;
begin
  Result.FAPI := FAPI;
  FillChar(Result.FIter, SizeOf(Result.FIter), 0);
  if FAPI^.message_iter_open_container(@FIter, DBUS_TYPE_STRUCT, nil, @Result.FIter) = 0 then
    raise EPMLError.Create('D-Bus: failed to open struct container');
end;

function TPMLDBusWriter.OpenVariant(const AContentSignature: String): TPMLDBusWriter;
begin
  Result.FAPI := FAPI;
  FillChar(Result.FIter, SizeOf(Result.FIter), 0);
  if FAPI^.message_iter_open_container(@FIter, DBUS_TYPE_VARIANT,
       PAnsiChar(AContentSignature), @Result.FIter) = 0 then
    raise EPMLError.Create('D-Bus: failed to open variant container');
end;

function TPMLDBusWriter.OpenDictEntry: TPMLDBusWriter;
begin
  Result.FAPI := FAPI;
  FillChar(Result.FIter, SizeOf(Result.FIter), 0);
  if FAPI^.message_iter_open_container(@FIter, DBUS_TYPE_DICT_ENTRY, nil, @Result.FIter) = 0 then
    raise EPMLError.Create('D-Bus: failed to open dict entry container');
end;

procedure TPMLDBusWriter.Close(var ASub: TPMLDBusWriter);
begin
  if FAPI^.message_iter_close_container(@FIter, @ASub.FIter) = 0 then
    raise EPMLError.Create('D-Bus: failed to close container');
end;

{ TPMLDBusConnection }

procedure TPMLDBusConnection.Bind(out ATarget; const ASymbol: String);
begin
  Pointer(ATarget) := FLib.Resolve(ASymbol);
end;

procedure TPMLDBusConnection.LoadAPI;
begin
  FillChar(FAPI, SizeOf(FAPI), 0);
  Bind(FAPI.error_init,   'dbus_error_init');
  Bind(FAPI.error_free,   'dbus_error_free');
  Bind(FAPI.error_is_set, 'dbus_error_is_set');

  Bind(FAPI.bus_get_private,    'dbus_bus_get_private');
  Bind(FAPI.bus_register,       'dbus_bus_register');
  Bind(FAPI.connection_open_private, 'dbus_connection_open_private');
  Bind(FAPI.bus_add_match,      'dbus_bus_add_match');
  Bind(FAPI.bus_remove_match,   'dbus_bus_remove_match');
  Bind(FAPI.bus_name_has_owner, 'dbus_bus_name_has_owner');

  Bind(FAPI.connection_close,                  'dbus_connection_close');
  Bind(FAPI.connection_unref,                  'dbus_connection_unref');
  Bind(FAPI.connection_flush,                  'dbus_connection_flush');
  Bind(FAPI.connection_read_write,             'dbus_connection_read_write');
  Bind(FAPI.connection_pop_message,            'dbus_connection_pop_message');
  Bind(FAPI.connection_get_is_connected,       'dbus_connection_get_is_connected');
  Bind(FAPI.connection_set_exit_on_disconnect, 'dbus_connection_set_exit_on_disconnect');
  Bind(FAPI.connection_send_with_reply_and_block, 'dbus_connection_send_with_reply_and_block');
  Bind(FAPI.connection_send,                   'dbus_connection_send');

  Bind(FAPI.message_new_method_call, 'dbus_message_new_method_call');
  Bind(FAPI.message_unref,           'dbus_message_unref');
  Bind(FAPI.message_is_signal,       'dbus_message_is_signal');
  Bind(FAPI.message_get_member,      'dbus_message_get_member');
  Bind(FAPI.message_get_interface,   'dbus_message_get_interface');
  Bind(FAPI.message_get_path,        'dbus_message_get_path');
  Bind(FAPI.message_get_type,        'dbus_message_get_type');
  Bind(FAPI.message_get_reply_serial, 'dbus_message_get_reply_serial');
  Bind(FAPI.message_get_error_name,  'dbus_message_get_error_name');

  Bind(FAPI.message_iter_init_append,     'dbus_message_iter_init_append');
  Bind(FAPI.message_iter_append_basic,    'dbus_message_iter_append_basic');
  Bind(FAPI.message_iter_open_container,  'dbus_message_iter_open_container');
  Bind(FAPI.message_iter_close_container, 'dbus_message_iter_close_container');

  Bind(FAPI.message_iter_init,         'dbus_message_iter_init');
  Bind(FAPI.message_iter_get_arg_type, 'dbus_message_iter_get_arg_type');
  Bind(FAPI.message_iter_get_basic,    'dbus_message_iter_get_basic');
  Bind(FAPI.message_iter_recurse,      'dbus_message_iter_recurse');
  Bind(FAPI.message_iter_next,         'dbus_message_iter_next');
end;

procedure TPMLDBusConnection.ClearError;
begin
  if FAPI.error_is_set(@FErr) <> 0 then
  begin
    FAPI.error_free(@FErr);
    FAPI.error_init(@FErr);
  end;
end;

procedure TPMLDBusConnection.RaiseIfError(const AWhat: String);
var
  N, M: String;
begin
  if FAPI.error_is_set(@FErr) = 0 then
    Exit;
  N := String(FErr.name);
  M := String(FErr.message_);
  FAPI.error_free(@FErr);
  FAPI.error_init(@FErr);
  raise EPMLTextInputError.CreateNative(AWhat, 0, 'dbus', N + ' — ' + M);
end;

constructor TPMLDBusConnection.Create(ABusType: LongInt);
begin
  inherited Create;
  FLib := TPMLDynLib.Create(LIBDBUS_NAMES);
  LoadAPI;
  FAPI.error_init(@FErr);
  FConn := FAPI.bus_get_private(ABusType, @FErr);
  RaiseIfError('failed to connect to the D-Bus daemon');
  if FConn = nil then
    raise EPMLTextInputError.CreateNative('D-Bus connection is nil', 0, 'dbus');
  // プロセスが D-Bus 切断で終了しないようにする。切断は EPMLBackendLost で扱う。
  FAPI.connection_set_exit_on_disconnect(FConn, 0);
end;

constructor TPMLDBusConnection.CreateOffline;
begin
  inherited Create;
  FLib := TPMLDynLib.Create(LIBDBUS_NAMES);
  LoadAPI;
  FAPI.error_init(@FErr);
  FConn := nil;
end;

constructor TPMLDBusConnection.CreateForAddress(const AAddress: String);
begin
  inherited Create;
  FLib := TPMLDynLib.Create(LIBDBUS_NAMES);
  LoadAPI;
  FAPI.error_init(@FErr);
  FConn := FAPI.connection_open_private(PAnsiChar(AAddress), @FErr);
  RaiseIfError('failed to connect to ' + AAddress);
  if FConn = nil then
    raise EPMLTextInputError.CreateNative('D-Bus connection is nil', 0, 'dbus');
  FAPI.connection_set_exit_on_disconnect(FConn, 0);
  // メッセージバスとして話すには Hello が要る（名前の割り当て）。
  FAPI.bus_register(FConn, @FErr);
  RaiseIfError('failed to register on ' + AAddress);
end;

destructor TPMLDBusConnection.Destroy;
begin
  if FConn <> nil then
  begin
    // プライベート接続は close してから unref する必要がある。
    FAPI.connection_close(FConn);
    FAPI.connection_unref(FConn);
    FConn := nil;
  end;
  if Assigned(FAPI.error_free) then
    FAPI.error_free(@FErr);
  FreeAndNil(FLib);
  inherited Destroy;
end;

function TPMLDBusConnection.IsConnected: Boolean;
begin
  Result := (FConn <> nil) and (FAPI.connection_get_is_connected(FConn) <> 0);
end;

function TPMLDBusConnection.NameHasOwner(const AName: String): Boolean;
begin
  Result := FAPI.bus_name_has_owner(FConn, PAnsiChar(AName), @FErr) <> 0;
  ClearError;
end;

procedure TPMLDBusConnection.AddMatch(const ARule: String);
begin
  FAPI.bus_add_match(FConn, PAnsiChar(ARule), @FErr);
  RaiseIfError('failed to add a signal match rule');
  Flush;
end;

procedure TPMLDBusConnection.RemoveMatch(const ARule: String);
begin
  FAPI.bus_remove_match(FConn, PAnsiChar(ARule), @FErr);
  ClearError;
end;

procedure TPMLDBusConnection.Flush;
begin
  FAPI.connection_flush(FConn);
end;

function TPMLDBusConnection.BeginCall(const AService, APath, AIface, AMethod: String): PDBusMessage;
begin
  Result := FAPI.message_new_method_call(PAnsiChar(AService), PAnsiChar(APath),
    PAnsiChar(AIface), PAnsiChar(AMethod));
  if Result = nil then
    raise EPMLError.CreateFmt('D-Bus: failed to build a call to %s.%s', [AIface, AMethod]);
end;

function TPMLDBusConnection.Writer(AMsg: PDBusMessage): TPMLDBusWriter;
begin
  Result := TPMLDBusWriter.ForMessage(@FAPI, AMsg);
end;

function TPMLDBusConnection.Reader(AMsg: PDBusMessage): TPMLDBusReader;
begin
  Result := TPMLDBusReader.FromMessage(@FAPI, AMsg);
end;

function TPMLDBusConnection.Send(AMsg: PDBusMessage; ATimeoutMs: LongInt): PDBusMessage;
begin
  Result := FAPI.connection_send_with_reply_and_block(FConn, AMsg, ATimeoutMs, @FErr);
  RaiseIfError('D-Bus method call failed');
end;

procedure TPMLDBusConnection.Unref(AMsg: PDBusMessage);
begin
  if AMsg <> nil then
    FAPI.message_unref(AMsg);
end;

procedure TPMLDBusConnection.CallVoid(const AService, APath, AIface, AMethod: String);
var
  Msg, Reply: PDBusMessage;
begin
  Msg := BeginCall(AService, APath, AIface, AMethod);
  try
    Reply := Send(Msg);
    Unref(Reply);
  finally
    Unref(Msg);
  end;
end;

function TPMLDBusConnection.PopMessage(ATimeoutMs: LongInt): PDBusMessage;
begin
  FAPI.connection_read_write(FConn, ATimeoutMs);
  Result := FAPI.connection_pop_message(FConn);
end;

function TPMLDBusConnection.IsSignal(AMsg: PDBusMessage; const AIface, AName: String): Boolean;
begin
  Result := FAPI.message_is_signal(AMsg, PAnsiChar(AIface), PAnsiChar(AName)) <> 0;
end;

function TPMLDBusConnection.TypeOf(AMsg: PDBusMessage): LongInt;
begin
  Result := FAPI.message_get_type(AMsg);
end;

function TPMLDBusConnection.ReplySerialOf(AMsg: PDBusMessage): LongWord;
begin
  Result := FAPI.message_get_reply_serial(AMsg);
end;

function TPMLDBusConnection.ErrorNameOf(AMsg: PDBusMessage): String;
var
  P: PAnsiChar;
begin
  P := FAPI.message_get_error_name(AMsg);
  if P = nil then
    Result := ''
  else
    Result := String(P);
end;

function TPMLDBusConnection.SendAsync(AMsg: PDBusMessage): LongWord;
begin
  Result := 0;
  if FAPI.connection_send(FConn, AMsg, @Result) = 0 then
    raise EPMLTextInputError.CreateNative('D-Bus: out of memory while sending', 0, 'dbus');
  Flush;
end;

function TPMLDBusConnection.MemberOf(AMsg: PDBusMessage): String;
var
  P: PAnsiChar;
begin
  P := FAPI.message_get_member(AMsg);
  if P = nil then
    Result := ''
  else
    Result := String(P);
end;

end.
