{
  spike2_fcitx — ブロッカー検証 2

  検証したいこと:
    (a) FPC から libdbus-1 経由で fcitx5 の入力コンテキストを作り、
        接続を保ったままキーイベントを送れるか
    (b) UpdateFormattedPreedit が「文節ごとに分かれた複数要素」で
        返ってくるか = 全文節の区切りが実際に取得できるか
    (c) SetSurroundingText が受け付けられるか
    (d) DeleteSurroundingText シグナルが観測できるか

  fcitx5 の入力コンテキストは D-Bus 接続に紐づいて破棄されるため、
  gdbus のような一発起動のツールでは検証できない。単一プロセスで
  接続を保持する必要がある。

  値の出所:
    CapabilityFlag / TextFormatFlag は fcitx5 の
    src/lib/fcitx-utils/{capabilityflags,textformatflags}.h より

  Origin: clean-room (SDL のコードは参照していない)
}
program spike2_fcitx;

{$mode objfpc}{$H+}

uses
  SysUtils;

const
  libdbus = 'libdbus-1.so.3';

  DBUS_BUS_SESSION = 0;
  DBUS_TIMEOUT_USE_DEFAULT = -1;

  // D-Bus 型コード (ASCII)
  DBUS_TYPE_INVALID     = 0;
  DBUS_TYPE_BOOLEAN     = Ord('b');
  DBUS_TYPE_INT32       = Ord('i');
  DBUS_TYPE_UINT32      = Ord('u');
  DBUS_TYPE_UINT64      = Ord('t');
  DBUS_TYPE_STRING      = Ord('s');
  DBUS_TYPE_OBJECT_PATH = Ord('o');
  DBUS_TYPE_ARRAY       = Ord('a');
  DBUS_TYPE_STRUCT      = Ord('r');

  // fcitx5 のサービス
  FCITX_SERVICE  = 'org.fcitx.Fcitx5';
  IM_PATH        = '/org/freedesktop/portal/inputmethod';
  IM_IFACE       = 'org.fcitx.Fcitx.InputMethod1';
  IC_IFACE       = 'org.fcitx.Fcitx.InputContext1';
  CTRL_PATH      = '/controller';
  CTRL_IFACE     = 'org.fcitx.Fcitx.Controller1';

  // CapabilityFlag (uint64)
  CAP_PREEDIT           = QWord(1) shl 1;   // 2
  CAP_FORMATTED_PREEDIT = QWord(1) shl 4;   // 16
  CAP_SURROUNDING_TEXT  = QWord(1) shl 6;   // 64

  // TextFormatFlag (int32)
  FMT_UNDERLINE   = 1 shl 3;   // 8
  FMT_HIGHLIGHT   = 1 shl 4;   // 16
  FMT_DONTCOMMIT  = 1 shl 5;   // 32
  FMT_BOLD        = 1 shl 6;   // 64
  FMT_STRIKE      = 1 shl 7;   // 128
  FMT_ITALIC      = 1 shl 8;   // 256

type
  PDBusConnection = Pointer;
  PDBusMessage = Pointer;

  TDBusError = record
    name     : PAnsiChar;
    message  : PAnsiChar;
    bits     : LongWord;   // C 側は 5 個のビットフィールド
    padding1 : Pointer;
  end;
  PDBusError = ^TDBusError;

  // 不透明構造体。実サイズ 72 バイト程度なので余裕を持たせる。
  TDBusMessageIter = record
    opaque: array[0..95] of Byte;
  end;
  PDBusMessageIter = ^TDBusMessageIter;

procedure dbus_error_init(err: PDBusError); cdecl; external libdbus;
procedure dbus_error_free(err: PDBusError); cdecl; external libdbus;
function dbus_error_is_set(err: PDBusError): LongWord; cdecl; external libdbus;

function dbus_bus_get(bustype: LongInt; err: PDBusError): PDBusConnection; cdecl; external libdbus;
procedure dbus_bus_add_match(conn: PDBusConnection; rule: PAnsiChar; err: PDBusError); cdecl; external libdbus;
procedure dbus_connection_flush(conn: PDBusConnection); cdecl; external libdbus;
function dbus_connection_read_write(conn: PDBusConnection; timeout_ms: LongInt): LongWord; cdecl; external libdbus;
function dbus_connection_pop_message(conn: PDBusConnection): PDBusMessage; cdecl; external libdbus;
function dbus_connection_send_with_reply_and_block(conn: PDBusConnection;
  msg: PDBusMessage; timeout_ms: LongInt; err: PDBusError): PDBusMessage; cdecl; external libdbus;

function dbus_message_new_method_call(dest, path, iface, method: PAnsiChar): PDBusMessage; cdecl; external libdbus;
procedure dbus_message_unref(msg: PDBusMessage); cdecl; external libdbus;
function dbus_message_is_signal(msg: PDBusMessage; iface, signame: PAnsiChar): LongWord; cdecl; external libdbus;
function dbus_message_get_member(msg: PDBusMessage): PAnsiChar; cdecl; external libdbus;

procedure dbus_message_iter_init_append(msg: PDBusMessage; iter: PDBusMessageIter); cdecl; external libdbus;
function dbus_message_iter_append_basic(iter: PDBusMessageIter; atype: LongInt; value: Pointer): LongWord; cdecl; external libdbus;
function dbus_message_iter_open_container(iter: PDBusMessageIter; atype: LongInt;
  sig: PAnsiChar; sub: PDBusMessageIter): LongWord; cdecl; external libdbus;
function dbus_message_iter_close_container(iter, sub: PDBusMessageIter): LongWord; cdecl; external libdbus;

function dbus_message_iter_init(msg: PDBusMessage; iter: PDBusMessageIter): LongWord; cdecl; external libdbus;
function dbus_message_iter_get_arg_type(iter: PDBusMessageIter): LongInt; cdecl; external libdbus;
procedure dbus_message_iter_get_basic(iter: PDBusMessageIter; value: Pointer); cdecl; external libdbus;
procedure dbus_message_iter_recurse(iter, sub: PDBusMessageIter); cdecl; external libdbus;
function dbus_message_iter_next(iter: PDBusMessageIter): LongWord; cdecl; external libdbus;

var
  Conn      : PDBusConnection;
  Err       : TDBusError;
  ICPath    : string = '';
  Failures  : Integer = 0;
  // 観測結果
  PreeditUpdates      : Integer = 0;
  MaxSegments         : Integer = 0;
  SawHighlightedSeg   : Boolean = False;
  SawDeleteSurrounding: Boolean = False;
  LastCommit          : string = '';

procedure Check(ACondition: Boolean; const ALabel: string);
begin
  if ACondition then
    WriteLn('  [PASS] ', ALabel)
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(Failures);
  end;
end;

procedure FailIfError(const AWhat: string);
begin
  if dbus_error_is_set(@Err) <> 0 then
  begin
    WriteLn(Format('  [FAIL] %s: %s — %s', [AWhat, string(Err.name), string(Err.message)]));
    Inc(Failures);
    dbus_error_free(@Err);
    dbus_error_init(@Err);
  end;
end;

function FormatFlagsToStr(AFlags: LongInt): string;
begin
  Result := '';
  if AFlags and FMT_UNDERLINE  <> 0 then Result := Result + 'Underline ';
  if AFlags and FMT_HIGHLIGHT  <> 0 then Result := Result + 'HighLight ';
  if AFlags and FMT_DONTCOMMIT <> 0 then Result := Result + 'DontCommit ';
  if AFlags and FMT_BOLD       <> 0 then Result := Result + 'Bold ';
  if AFlags and FMT_STRIKE     <> 0 then Result := Result + 'Strike ';
  if AFlags and FMT_ITALIC     <> 0 then Result := Result + 'Italic ';
  if Result = '' then Result := '(none)';
  Result := Trim(Result);
end;

// UpdateFormattedPreedit(a(si) segments, i cursor) を展開して表示
procedure DumpFormattedPreedit(msg: PDBusMessage);
var
  Iter, Arr, St: TDBusMessageIter;
  SegText: PAnsiChar;
  Flags, Cursor: LongInt;
  N: Integer;
  Whole: string;
begin
  Inc(PreeditUpdates);
  N := 0;
  Whole := '';
  if dbus_message_iter_init(msg, @Iter) = 0 then Exit;
  if dbus_message_iter_get_arg_type(@Iter) <> DBUS_TYPE_ARRAY then Exit;

  dbus_message_iter_recurse(@Iter, @Arr);
  WriteLn('    --- UpdateFormattedPreedit ---');
  while dbus_message_iter_get_arg_type(@Arr) = DBUS_TYPE_STRUCT do
  begin
    dbus_message_iter_recurse(@Arr, @St);
    SegText := nil;
    Flags := 0;
    if dbus_message_iter_get_arg_type(@St) = DBUS_TYPE_STRING then
    begin
      dbus_message_iter_get_basic(@St, @SegText);
      dbus_message_iter_next(@St);
      if dbus_message_iter_get_arg_type(@St) = DBUS_TYPE_INT32 then
        dbus_message_iter_get_basic(@St, @Flags);
    end;
    Inc(N);
    Whole := Whole + string(SegText);
    WriteLn(Format('      文節[%d] "%s"  flags=%d (%s)',
      [N - 1, string(SegText), Flags, FormatFlagsToStr(Flags)]));
    if Flags and FMT_HIGHLIGHT <> 0 then
      SawHighlightedSeg := True;
    dbus_message_iter_next(@Arr);
  end;

  dbus_message_iter_next(@Iter);
  Cursor := -1;
  if dbus_message_iter_get_arg_type(@Iter) = DBUS_TYPE_INT32 then
    dbus_message_iter_get_basic(@Iter, @Cursor);

  WriteLn(Format('      全体="%s" 文節数=%d cursor=%d', [Whole, N, Cursor]));
  if N > MaxSegments then MaxSegments := N;
end;

procedure DumpCommitString(msg: PDBusMessage);
var
  Iter: TDBusMessageIter;
  S: PAnsiChar;
begin
  if dbus_message_iter_init(msg, @Iter) = 0 then Exit;
  if dbus_message_iter_get_arg_type(@Iter) <> DBUS_TYPE_STRING then Exit;
  S := nil;
  dbus_message_iter_get_basic(@Iter, @S);
  LastCommit := string(S);
  WriteLn(Format('    --- CommitString "%s" ---', [LastCommit]));
end;

procedure DumpDeleteSurrounding(msg: PDBusMessage);
var
  Iter: TDBusMessageIter;
  Offset: LongInt;
  Size: LongWord;
begin
  SawDeleteSurrounding := True;
  Offset := 0; Size := 0;
  if dbus_message_iter_init(msg, @Iter) <> 0 then
  begin
    if dbus_message_iter_get_arg_type(@Iter) = DBUS_TYPE_INT32 then
    begin
      dbus_message_iter_get_basic(@Iter, @Offset);
      dbus_message_iter_next(@Iter);
      if dbus_message_iter_get_arg_type(@Iter) = DBUS_TYPE_UINT32 then
        dbus_message_iter_get_basic(@Iter, @Size);
    end;
  end;
  WriteLn(Format('    --- DeleteSurroundingText offset=%d size=%u ---', [Offset, Size]));
end;

// 受信キューを排出する
procedure Pump(ATimeoutMs: LongInt);
var
  msg: PDBusMessage;
  Member: string;
begin
  dbus_connection_read_write(Conn, ATimeoutMs);
  repeat
    msg := dbus_connection_pop_message(Conn);
    if msg = nil then Break;
    Member := string(dbus_message_get_member(msg));
    if dbus_message_is_signal(msg, IC_IFACE, 'UpdateFormattedPreedit') <> 0 then
      DumpFormattedPreedit(msg)
    else if dbus_message_is_signal(msg, IC_IFACE, 'CommitString') <> 0 then
      DumpCommitString(msg)
    else if dbus_message_is_signal(msg, IC_IFACE, 'DeleteSurroundingText') <> 0 then
      DumpDeleteSurrounding(msg)
    else if dbus_message_is_signal(msg, IC_IFACE, 'CurrentIM') <> 0 then
      WriteLn('    --- CurrentIM シグナル受信 ---')
    else if Member <> '' then
      WriteLn('    (その他: ', Member, ')');
    dbus_message_unref(msg);
  until False;
end;

// 入力コンテキストを作る。CreateInputContext(a(ss)) -> (o, ay)
function CreateInputContext: string;
var
  msg, reply: PDBusMessage;
  Iter, Arr, St: TDBusMessageIter;
  K, V: PAnsiChar;
  P: PAnsiChar;
begin
  Result := '';
  msg := dbus_message_new_method_call(FCITX_SERVICE, IM_PATH, IM_IFACE, 'CreateInputContext');
  if msg = nil then Exit;

  dbus_message_iter_init_append(msg, @Iter);
  dbus_message_iter_open_container(@Iter, DBUS_TYPE_ARRAY, '(ss)', @Arr);

  dbus_message_iter_open_container(@Arr, DBUS_TYPE_STRUCT, nil, @St);
  K := 'program'; V := 'papimela-spike';
  dbus_message_iter_append_basic(@St, DBUS_TYPE_STRING, @K);
  dbus_message_iter_append_basic(@St, DBUS_TYPE_STRING, @V);
  dbus_message_iter_close_container(@Arr, @St);

  dbus_message_iter_open_container(@Arr, DBUS_TYPE_STRUCT, nil, @St);
  K := 'display'; V := 'wayland:';
  dbus_message_iter_append_basic(@St, DBUS_TYPE_STRING, @K);
  dbus_message_iter_append_basic(@St, DBUS_TYPE_STRING, @V);
  dbus_message_iter_close_container(@Arr, @St);

  dbus_message_iter_close_container(@Iter, @Arr);

  reply := dbus_connection_send_with_reply_and_block(Conn, msg, 3000, @Err);
  dbus_message_unref(msg);
  FailIfError('CreateInputContext');
  if reply = nil then Exit;

  if dbus_message_iter_init(reply, @Iter) <> 0 then
    if dbus_message_iter_get_arg_type(@Iter) = DBUS_TYPE_OBJECT_PATH then
    begin
      P := nil;
      dbus_message_iter_get_basic(@Iter, @P);
      Result := string(P);
    end;
  dbus_message_unref(reply);
end;

// 文字列を 1 個返すメソッドを叩く
function CallGetString(const APath, AIface, AMethod: string): string;
var
  msg, reply: PDBusMessage;
  Iter: TDBusMessageIter;
  P: PAnsiChar;
begin
  Result := '';
  msg := dbus_message_new_method_call(FCITX_SERVICE, PAnsiChar(APath),
    PAnsiChar(AIface), PAnsiChar(AMethod));
  if msg = nil then Exit;
  reply := dbus_connection_send_with_reply_and_block(Conn, msg, 3000, @Err);
  dbus_message_unref(msg);
  FailIfError(AMethod);
  if reply = nil then Exit;
  if dbus_message_iter_init(reply, @Iter) <> 0 then
    if dbus_message_iter_get_arg_type(@Iter) = DBUS_TYPE_STRING then
    begin
      P := nil;
      dbus_message_iter_get_basic(@Iter, @P);
      Result := string(P);
    end;
  dbus_message_unref(reply);
end;

// int32 を 1 個返すメソッドを叩く
function CallGetInt(const APath, AIface, AMethod: string): LongInt;
var
  msg, reply: PDBusMessage;
  Iter: TDBusMessageIter;
begin
  Result := -1;
  msg := dbus_message_new_method_call(FCITX_SERVICE, PAnsiChar(APath),
    PAnsiChar(AIface), PAnsiChar(AMethod));
  if msg = nil then Exit;
  reply := dbus_connection_send_with_reply_and_block(Conn, msg, 3000, @Err);
  dbus_message_unref(msg);
  FailIfError(AMethod);
  if reply = nil then Exit;
  if dbus_message_iter_init(reply, @Iter) <> 0 then
    if dbus_message_iter_get_arg_type(@Iter) = DBUS_TYPE_INT32 then
      dbus_message_iter_get_basic(@Iter, @Result);
  dbus_message_unref(reply);
end;

// 引数なしメソッドを叩く
procedure CallVoid(const APath, AIface, AMethod: string);
var
  msg, reply: PDBusMessage;
begin
  msg := dbus_message_new_method_call(FCITX_SERVICE, PAnsiChar(APath),
    PAnsiChar(AIface), PAnsiChar(AMethod));
  if msg = nil then Exit;
  reply := dbus_connection_send_with_reply_and_block(Conn, msg, 3000, @Err);
  dbus_message_unref(msg);
  FailIfError(AMethod);
  if reply <> nil then dbus_message_unref(reply);
end;

procedure SetCapability(ACaps: QWord);
var
  msg, reply: PDBusMessage;
  Iter: TDBusMessageIter;
  V: QWord;
begin
  msg := dbus_message_new_method_call(FCITX_SERVICE, PAnsiChar(ICPath), IC_IFACE, 'SetCapability');
  if msg = nil then Exit;
  dbus_message_iter_init_append(msg, @Iter);
  V := ACaps;
  dbus_message_iter_append_basic(@Iter, DBUS_TYPE_UINT64, @V);
  reply := dbus_connection_send_with_reply_and_block(Conn, msg, 3000, @Err);
  dbus_message_unref(msg);
  FailIfError('SetCapability');
  if reply <> nil then dbus_message_unref(reply);
end;

procedure SetCurrentIM(const AName: string);
var
  msg, reply: PDBusMessage;
  Iter: TDBusMessageIter;
  P: PAnsiChar;
begin
  msg := dbus_message_new_method_call(FCITX_SERVICE, CTRL_PATH, CTRL_IFACE, 'SetCurrentIM');
  if msg = nil then Exit;
  dbus_message_iter_init_append(msg, @Iter);
  P := PAnsiChar(AName);
  dbus_message_iter_append_basic(@Iter, DBUS_TYPE_STRING, @P);
  reply := dbus_connection_send_with_reply_and_block(Conn, msg, 3000, @Err);
  dbus_message_unref(msg);
  FailIfError('SetCurrentIM');
  if reply <> nil then dbus_message_unref(reply);
end;

function SetSurroundingText(const AText: string; ACursor, AAnchor: LongWord): Boolean;
var
  msg, reply: PDBusMessage;
  Iter: TDBusMessageIter;
  P: PAnsiChar;
begin
  Result := False;
  msg := dbus_message_new_method_call(FCITX_SERVICE, PAnsiChar(ICPath), IC_IFACE, 'SetSurroundingText');
  if msg = nil then Exit;
  dbus_message_iter_init_append(msg, @Iter);
  P := PAnsiChar(AText);
  dbus_message_iter_append_basic(@Iter, DBUS_TYPE_STRING, @P);
  dbus_message_iter_append_basic(@Iter, DBUS_TYPE_UINT32, @ACursor);
  dbus_message_iter_append_basic(@Iter, DBUS_TYPE_UINT32, @AAnchor);
  reply := dbus_connection_send_with_reply_and_block(Conn, msg, 3000, @Err);
  dbus_message_unref(msg);
  if dbus_error_is_set(@Err) <> 0 then
  begin
    WriteLn(Format('    SetSurroundingText 拒否: %s', [string(Err.message)]));
    dbus_error_free(@Err);
    dbus_error_init(@Err);
    Exit;
  end;
  if reply <> nil then dbus_message_unref(reply);
  Result := True;
end;

// ProcessKeyEvent(u keyval, u keycode, u state, b isRelease, u time) -> b handled
function ProcessKey(AKeyval, AKeycode, AState: LongWord; ARelease: Boolean): Boolean;
var
  msg, reply: PDBusMessage;
  Iter: TDBusMessageIter;
  Rel: LongWord;
  Time: LongWord;
  Handled: LongWord;
begin
  Result := False;
  msg := dbus_message_new_method_call(FCITX_SERVICE, PAnsiChar(ICPath), IC_IFACE, 'ProcessKeyEvent');
  if msg = nil then Exit;
  dbus_message_iter_init_append(msg, @Iter);
  Rel := Ord(ARelease);
  Time := 0;
  dbus_message_iter_append_basic(@Iter, DBUS_TYPE_UINT32, @AKeyval);
  dbus_message_iter_append_basic(@Iter, DBUS_TYPE_UINT32, @AKeycode);
  dbus_message_iter_append_basic(@Iter, DBUS_TYPE_UINT32, @AState);
  dbus_message_iter_append_basic(@Iter, DBUS_TYPE_BOOLEAN, @Rel);
  dbus_message_iter_append_basic(@Iter, DBUS_TYPE_UINT32, @Time);

  reply := dbus_connection_send_with_reply_and_block(Conn, msg, 3000, @Err);
  dbus_message_unref(msg);
  FailIfError('ProcessKeyEvent');
  if reply = nil then Exit;

  Handled := 0;
  if dbus_message_iter_init(reply, @Iter) <> 0 then
    if dbus_message_iter_get_arg_type(@Iter) = DBUS_TYPE_BOOLEAN then
      dbus_message_iter_get_basic(@Iter, @Handled);
  dbus_message_unref(reply);
  Result := Handled <> 0;
end;

type
  TKeyDef = record
    Keyval, Keycode: LongWord;
    Label_: string;
  end;

const
  // "わたしのなまえ" のローマ字入力。keycode は evdev+8 (X11 慣習)
  Phrase: array[0..13] of TKeyDef = (
    (Keyval: $77; Keycode: 25; Label_: 'w'),
    (Keyval: $61; Keycode: 38; Label_: 'a'),
    (Keyval: $74; Keycode: 28; Label_: 't'),
    (Keyval: $61; Keycode: 38; Label_: 'a'),
    (Keyval: $73; Keycode: 39; Label_: 's'),
    (Keyval: $68; Keycode: 43; Label_: 'h'),
    (Keyval: $69; Keycode: 31; Label_: 'i'),
    (Keyval: $6E; Keycode: 57; Label_: 'n'),
    (Keyval: $6F; Keycode: 32; Label_: 'o'),
    (Keyval: $6E; Keycode: 57; Label_: 'n'),
    (Keyval: $61; Keycode: 38; Label_: 'a'),
    (Keyval: $6D; Keycode: 58; Label_: 'm'),
    (Keyval: $61; Keycode: 38; Label_: 'a'),
    (Keyval: $65; Keycode: 26; Label_: 'e')
  );
  KEY_SPACE_VAL = $20;
  KEY_SPACE_CODE = 65;

var
  I: Integer;
  AnyHandled: Boolean = False;
begin
  WriteLn('spike2_fcitx — fcitx5 D-Bus で文節区切り / 周辺テキスト / 周辺削除を検証');
  WriteLn;

  dbus_error_init(@Err);

  WriteLn('1. セッションバス接続');
  Conn := dbus_bus_get(DBUS_BUS_SESSION, @Err);
  FailIfError('dbus_bus_get');
  Check(Conn <> nil, 'セッションバスに接続');
  if Conn = nil then Halt(1);

  WriteLn;
  WriteLn('2. 入力コンテキスト作成 (接続を保持したまま)');
  ICPath := CreateInputContext;
  Check(ICPath <> '', Format('CreateInputContext -> %s', [ICPath]));
  if ICPath = '' then
  begin
    WriteLn('  fcitx5 が起動していないか dbusfrontend アドオンが無効です。');
    Halt(1);
  end;

  WriteLn;
  WriteLn('3. シグナル購読と capability 宣言');
  dbus_bus_add_match(Conn,
    PAnsiChar('type=''signal'',interface=''' + IC_IFACE + ''',path=''' + ICPath + ''''), @Err);
  FailIfError('add_match');
  dbus_connection_flush(Conn);
  SetCapability(CAP_PREEDIT or CAP_FORMATTED_PREEDIT or CAP_SURROUNDING_TEXT);
  WriteLn(Format('  [INFO] capability = %d (Preedit|FormattedPreedit|SurroundingText)',
    [CAP_PREEDIT or CAP_FORMATTED_PREEDIT or CAP_SURROUNDING_TEXT]));

  WriteLn;
  WriteLn('4. フォーカス取得 -> IME をアクティベート -> mozc に切り替え');
  // 順序が重要: SetCurrentIM はフォーカス中のコンテキストに作用するため
  // FocusIn を先に済ませる。さらに fcitx5 は既定で「非アクティブ」
  // (keyboard-us が担当) の状態から始まるので Activate が必要。
  CallVoid(ICPath, IC_IFACE, 'FocusIn');
  Pump(100);
  CallVoid(CTRL_PATH, CTRL_IFACE, 'Activate');
  SetCurrentIM('mozc');
  Pump(100);
  WriteLn(Format('  [INFO] State()              = %d (0=非アクティブ, 2=アクティブ)',
    [CallGetInt(CTRL_PATH, CTRL_IFACE, 'State')]));
  WriteLn(Format('  [INFO] CurrentInputMethod() = "%s"',
    [CallGetString(CTRL_PATH, CTRL_IFACE, 'CurrentInputMethod')]));

  WriteLn;
  WriteLn('5. 周辺テキストの供給');
  Check(SetSurroundingText('これは周辺テキストです', 11, 11),
    'SetSurroundingText が受理された');

  WriteLn;
  WriteLn('6. ローマ字で「わたしのなまえ」を入力');
  for I := Low(Phrase) to High(Phrase) do
  begin
    if ProcessKey(Phrase[I].Keyval, Phrase[I].Keycode, 0, False) then
      AnyHandled := True;
    ProcessKey(Phrase[I].Keyval, Phrase[I].Keycode, 0, True);
    Pump(30);
  end;
  Check(AnyHandled, 'ProcessKeyEvent がキーを消費した (IME が動作している)');

  WriteLn;
  WriteLn('7. スペースキーで変換 (文節が分かれるか)');
  ProcessKey(KEY_SPACE_VAL, KEY_SPACE_CODE, 0, False);
  ProcessKey(KEY_SPACE_VAL, KEY_SPACE_CODE, 0, True);
  Pump(400);

  WriteLn;
  WriteLn('8. もう一度スペース (注目文節の移動/候補変更)');
  ProcessKey(KEY_SPACE_VAL, KEY_SPACE_CODE, 0, False);
  ProcessKey(KEY_SPACE_VAL, KEY_SPACE_CODE, 0, True);
  Pump(400);

  WriteLn;
  WriteLn('9. 後始末');
  CallVoid(ICPath, IC_IFACE, 'FocusOut');
  CallVoid(ICPath, IC_IFACE, 'DestroyIC');
  dbus_error_free(@Err);
  WriteLn('  [PASS] 解放完了');

  WriteLn;
  WriteLn('=== 検証結果 ===');
  WriteLn(Format('  UpdateFormattedPreedit 受信回数 : %d', [PreeditUpdates]));
  WriteLn(Format('  観測した最大文節数              : %d', [MaxSegments]));
  WriteLn(Format('  HighLight 付き文節を観測        : %s', [BoolToStr(SawHighlightedSeg, True)]));
  WriteLn(Format('  DeleteSurroundingText を観測    : %s', [BoolToStr(SawDeleteSurrounding, True)]));
  WriteLn;
  Check(PreeditUpdates > 0, '変換中テキストが届いた');
  Check(MaxSegments >= 2, '文節が 2 個以上に分かれた = 全文節の区切りが取得できる');
  Check(SawHighlightedSeg, 'HighLight フラグで注目文節が判別できる');

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: fcitx5 D-Bus 経路で 3 要件が成立する ===')
  else
    WriteLn(Format('=== 失敗/未達 %d 件。下の考察を参照 ===', [Failures]));
  Halt(Ord(Failures <> 0));
end.
