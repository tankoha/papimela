{
  spike3_ibus — IBus の私設バスで、変換中テキストの属性と通知の並びを実測する

  検証したいこと:
    (a) アドレスファイルを見つけ、私設バスに繋いで入力コンテキストを作れるか
    (b) ProcessKeyEvent を返信を待たずに送り、返信（handled）と通知の並びを
        通し番号で突き合わせられるか（非同期化の前提）
    (c) ibus-mozc の UpdatePreeditText の IBusText に、どの属性（型・値・範囲）が
        載るか。変換前・変換後・文節を移した後で
    (d) CommitText、ForwardKeyEvent、DeleteSurroundingText、RequireSurroundingText が
        いつ届くか。SetSurroundingText が受け付けられるか

  IBus の入力コンテキストは接続に紐づいて消えるので、1 つのプロセスで接続を
  保ったまま全部を行う。デスクトップの IME と混ざらないよう、隔離環境
  （ibus-session。docs/HANDOFF.md）の中で動かす。

  値の出所: IBus の公開ヘッダ（ibustypes.h の IBusCapabilite / IBusModifierType、
  ibusattribute.h の IBusAttrType / IBusAttrUnderline）の数値。

  Origin: clean-room (SDL のコードは参照していない)
}
program spike3_ibus;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes,
  PaPiMeLa.Platform.DBus;

const
  IBUS_SERVICE = 'org.freedesktop.IBus';
  IBUS_PATH    = '/org/freedesktop/IBus';
  IBUS_IFACE   = 'org.freedesktop.IBus';
  IC_IFACE     = 'org.freedesktop.IBus.InputContext';

  CAP_PREEDIT_TEXT     = 1 shl 0;
  CAP_LOOKUP_TABLE     = 1 shl 2;
  CAP_FOCUS            = 1 shl 3;
  CAP_SURROUNDING_TEXT = 1 shl 5;

  RELEASE_MASK = LongWord(1) shl 30;

var
  Conn: TPMLDBusConnection;
  ICPath: String;
  Pending: array of LongWord;   // 返信を待っている ProcessKeyEvent の通し番号
  T0: QWord;

function Stamp: String;
begin
  Result := Format('%5d ms', [GetTickCount64 - T0]);
end;

{ 値を型ごとに再帰して 1 行に書き出す。 }
function Dump(var R: TPMLDBusReader): String;
var
  Sub: TPMLDBusReader;
  First: Boolean;
begin
  Result := '';
  First := True;
  while not R.AtEnd do
  begin
    if not First then
      Result := Result + ', ';
    First := False;
    case R.ArgType of
      DBUS_TYPE_STRING, DBUS_TYPE_OBJECT_PATH, DBUS_TYPE_SIGNATURE:
        Result := Result + '"' + R.AsString + '"';
      DBUS_TYPE_UINT32:  Result := Result + IntToStr(R.AsUInt32) + 'u';
      DBUS_TYPE_INT32:   Result := Result + IntToStr(R.AsInt32) + 'i';
      DBUS_TYPE_BOOLEAN: Result := Result + BoolToStr(R.AsBoolean, 'true', 'false');
      DBUS_TYPE_STRUCT:
        begin
          Sub := R.Recurse;
          Result := Result + '(' + Dump(Sub) + ')';
        end;
      DBUS_TYPE_ARRAY:
        begin
          Sub := R.Recurse;
          Result := Result + '[' + Dump(Sub) + ']';
        end;
      DBUS_TYPE_VARIANT:
        begin
          Sub := R.Recurse;
          Result := Result + '<' + Dump(Sub) + '>';
        end;
      DBUS_TYPE_DICT_ENTRY:
        begin
          Sub := R.Recurse;
          Result := Result + '{' + Dump(Sub) + '}';
        end;
    else
      Result := Result + '?' + Chr(R.ArgType);
    end;
    R.Next;
  end;
end;

{ IBusText の variant から (文字列, 属性の並び) を取り出して読みやすく書く。
  属性は (型, 値, 開始, 終了)。開始と終了は文字（コードポイント）単位。 }
function DescribeText(R: TPMLDBusReader): String;
var
  V, S, Attrs, AttrListV, AttrList, Arr, One, OneS: TPMLDBusReader;
  Text: String;
  Ty, Va, St, En: LongWord;
begin
  // R は variant を指している
  V := R.Recurse;          // struct (s a{sv} s v)
  S := V.Recurse;
  S.Next;                  // "IBusText"
  S.Next;                  // a{sv}
  Text := S.AsString;
  S.Next;
  Result := '"' + Text + '" attrs:';
  AttrListV := S.Recurse;  // variant の中身: struct (s a{sv} av)
  AttrList := AttrListV.Recurse;
  AttrList.Next;           // "IBusAttrList"
  AttrList.Next;           // a{sv}
  Arr := AttrList.Recurse; // av
  while not Arr.AtEnd do
  begin
    Attrs := Arr.Recurse;      // variant → struct
    One := Attrs.Recurse;
    One.Next;                  // "IBusAttribute"
    One.Next;                  // a{sv}
    OneS := One;
    Ty := OneS.AsUInt32; OneS.Next;
    Va := OneS.AsUInt32; OneS.Next;
    St := OneS.AsUInt32; OneS.Next;
    En := OneS.AsUInt32;
    Result := Result + Format(' (type=%d value=$%x %d..%d)', [Ty, Va, St, En]);
    Arr.Next;
  end;
end;

procedure HandleMessage(AMsg: PDBusMessage);
var
  R: TPMLDBusReader;
  Serial: LongWord;
  I: Integer;
  Member: String;
begin
  case Conn.TypeOf(AMsg) of
    DBUS_MESSAGE_TYPE_METHOD_RETURN, DBUS_MESSAGE_TYPE_ERROR:
      begin
        Serial := Conn.ReplySerialOf(AMsg);
        for I := 0 to High(Pending) do
          if Pending[I] = Serial then
          begin
            R := Conn.Reader(AMsg);
            if Conn.TypeOf(AMsg) = DBUS_MESSAGE_TYPE_ERROR then
              WriteLn(Stamp, '  reply #', Serial, ' ERROR ', Conn.ErrorNameOf(AMsg))
            else
              WriteLn(Stamp, '  reply #', Serial, ' handled=', Dump(R));
            Delete(Pending, I, 1);
            Exit;
          end;
        WriteLn(Stamp, '  (他の返信 #', Serial, ')');
      end;
    DBUS_MESSAGE_TYPE_SIGNAL:
      begin
        Member := Conn.MemberOf(AMsg);
        R := Conn.Reader(AMsg);
        if (Member = 'UpdatePreeditText') or (Member = 'UpdatePreeditTextWithMode')
          or (Member = 'CommitText') or (Member = 'UpdateAuxiliaryText') then
        begin
          Write(Stamp, '  signal ', Member, ' ', DescribeText(R));
          R.Next;
          WriteLn('  rest: ', Dump(R));
        end
        else if Member = 'UpdateLookupTable' then
          WriteLn(Stamp, '  signal UpdateLookupTable (略)')
        else
          WriteLn(Stamp, '  signal ', Member, ' ', Dump(R));
      end;
  end;
end;

procedure Drain(AMs: Integer);
var
  Deadline: QWord;
  M: PDBusMessage;
begin
  Deadline := GetTickCount64 + QWord(AMs);
  repeat
    M := Conn.PopMessage(20);
    while M <> nil do
    begin
      HandleMessage(M);
      Conn.Unref(M);
      M := Conn.PopMessage(0);
    end;
  until GetTickCount64 >= Deadline;
end;

procedure SendKey(AKeyval, AEvdev: LongWord; ARelease: Boolean);
var
  Msg: PDBusMessage;
  W: TPMLDBusWriter;
  State: LongWord;
  Serial: LongWord;
begin
  State := 0;
  if ARelease then
    State := RELEASE_MASK;
  Msg := Conn.BeginCall(IBUS_SERVICE, ICPath, IC_IFACE, 'ProcessKeyEvent');
  try
    W := Conn.Writer(Msg);
    W.AddUInt32(AKeyval);
    W.AddUInt32(AEvdev);        // IBus の keycode は evdev の値（X の keycode - 8）
    W.AddUInt32(State);
    Serial := Conn.SendAsync(Msg);
  finally
    Conn.Unref(Msg);
  end;
  SetLength(Pending, Length(Pending) + 1);
  Pending[High(Pending)] := Serial;
  WriteLn(Stamp, 'send #', Serial, ' key $', IntToHex(AKeyval, 2), BoolToStr(ARelease, ' up', ' down'));
end;

const
  // US 配列の evdev コード（a..z）
  EVDEV: array['a'..'z'] of LongWord = (
    30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50,
    49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44);

procedure TypeRomaji(const S: String);
var
  C: Char;
begin
  for C in S do
  begin
    SendKey(Ord(C), EVDEV[C], False);
    SendKey(Ord(C), EVDEV[C], True);
  end;
  Drain(300);
end;

procedure Tap(AKeyval, AEvdev: LongWord; const ALabel: String);
begin
  WriteLn('--- ', ALabel);
  SendKey(AKeyval, AEvdev, False);
  SendKey(AKeyval, AEvdev, True);
  Drain(400);
end;

function FindAddress: String;
var
  Dir, Display, Host, Num, MachineId, FileName: String;
  L: TStringList;
  I, P: Integer;
begin
  Result := GetEnvironmentVariable('IBUS_ADDRESS');
  if Result <> '' then
  begin
    WriteLn('address: IBUS_ADDRESS から');
    Exit;
  end;
  Dir := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if Dir = '' then
    Dir := GetEnvironmentVariable('HOME') + '/.config';
  // ibus-daemon は /var/lib/dbus/machine-id を先に読み、無ければ /etc/machine-id（実測:
  // 2 つが違う環境で、ファイル名は前者の値だった）。
  L := TStringList.Create;
  try
    if FileExists('/var/lib/dbus/machine-id') then
      L.LoadFromFile('/var/lib/dbus/machine-id')
    else
      L.LoadFromFile('/etc/machine-id');
    MachineId := Trim(L.Text);
  finally
    L.Free;
  end;
  // DISPLAY=":0" → host "unix", num "0"。"host:0.0" の画面番号は落とす。
  Display := GetEnvironmentVariable('DISPLAY');
  P := Pos(':', Display);
  Host := Copy(Display, 1, P - 1);
  if Host = '' then
    Host := 'unix';
  Num := Copy(Display, P + 1, MaxInt);
  P := Pos('.', Num);
  if P > 0 then
    Num := Copy(Num, 1, P - 1);
  FileName := Format('%s/ibus/bus/%s-%s-%s', [Dir, MachineId, Host, Num]);
  WriteLn('address file: ', FileName);
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    for I := 0 to L.Count - 1 do
      if Copy(L[I], 1, 13) = 'IBUS_ADDRESS=' then
        Exit(Copy(L[I], 14, MaxInt));
  finally
    L.Free;
  end;
  raise Exception.Create('IBUS_ADDRESS not found in ' + FileName);
end;

procedure SetSurrounding(const AText: String; ACursor, AAnchor: LongWord);
var
  Msg, Reply: PDBusMessage;
  W, V, S, D, AV, AL, ALD, ALA: TPMLDBusWriter;
begin
  Msg := Conn.BeginCall(IBUS_SERVICE, ICPath, IC_IFACE, 'SetSurroundingText');
  Reply := nil;
  try
    W := Conn.Writer(Msg);
    V := W.OpenVariant('(sa{sv}sv)');
    S := V.OpenStruct;
    S.AddString('IBusText');
    D := S.OpenArray('{sv}');
    S.Close(D);
    S.AddString(AText);
    AV := S.OpenVariant('(sa{sv}av)');
    AL := AV.OpenStruct;
    AL.AddString('IBusAttrList');
    ALD := AL.OpenArray('{sv}');
    AL.Close(ALD);
    ALA := AL.OpenArray('v');
    AL.Close(ALA);
    AV.Close(AL);
    S.Close(AV);
    V.Close(S);
    W.Close(V);
    W.AddUInt32(ACursor);
    W.AddUInt32(AAnchor);
    Reply := Conn.Send(Msg);
    WriteLn(Stamp, ' SetSurroundingText("', AText, '", ', ACursor, ', ', AAnchor, ') 受理');
  finally
    Conn.Unref(Reply);
    Conn.Unref(Msg);
  end;
end;

var
  Msg, Reply: PDBusMessage;
  W: TPMLDBusWriter;
  R: TPMLDBusReader;
  Address: String;
begin
  T0 := GetTickCount64;
  Address := FindAddress;
  WriteLn('address: ', Address);
  Conn := TPMLDBusConnection.CreateForAddress(Address);
  try
    Msg := Conn.BeginCall(IBUS_SERVICE, IBUS_PATH, IBUS_IFACE, 'CreateInputContext');
    try
      Conn.Writer(Msg).AddString('papimela-spike3');
      Reply := Conn.Send(Msg);
      R := Conn.Reader(Reply);
      ICPath := R.ExpectObjectPath;
      Conn.Unref(Reply);
    finally
      Conn.Unref(Msg);
    end;
    WriteLn('(a) input context: ', ICPath);

    Conn.AddMatch(Format('type=''signal'',interface=''%s'',path=''%s''', [IC_IFACE, ICPath]));

    Msg := Conn.BeginCall(IBUS_SERVICE, ICPath, IC_IFACE, 'SetCapabilities');
    try
      W := Conn.Writer(Msg);
      W.AddUInt32(CAP_PREEDIT_TEXT or CAP_FOCUS or CAP_SURROUNDING_TEXT);
      Conn.Unref(Conn.Send(Msg));
    finally
      Conn.Unref(Msg);
    end;
    Conn.CallVoid(IBUS_SERVICE, ICPath, IC_IFACE, 'FocusIn');
    Drain(500);

    WriteLn('--- (d) 周辺テキスト');
    SetSurrounding('これは周辺', 5, 5);
    Drain(200);

    WriteLn('--- (b)(c) ローマ字 kanji');
    TypeRomaji('kanji');
    Tap($20, 57, 'スペース（変換）');
    Tap($20, 57, 'スペース（次の候補）');
    Tap($FF0D, 28, 'Enter（確定）');

    WriteLn('--- (c) 複数文節 watashinonamaeha');
    TypeRomaji('watashinonamaeha');
    Tap($20, 57, 'スペース（変換）');
    Tap($FF53, 106, '→（注目文節を次へ）');
    Tap($FF53 or 0, 106, '→（さらに次へ）');
    WriteLn('--- Shift+→（文節を伸ばす）は送らない（修飾の扱いは別途）');
    Tap($FF1B, 1, 'Escape（変換の取り消し）');
    Tap($FF1B, 1, 'Escape（変換中テキストの破棄）');

    WriteLn('--- (d) 再変換: 「漢字を」の「漢字」を選択して変換キー');
    SetSurrounding('漢字を', 2, 0);
    Tap($FF23, 92, '変換（Henkan）');
    Tap($20, 57, 'スペース（次の候補）');
    Tap($FF0D, 28, 'Enter（確定）');
    WriteLn('--- (d) 再変換: 選択なし、カーソルが「漢字」の後');
    SetSurrounding('漢字を', 2, 2);
    Tap($FF23, 92, '変換（Henkan）');
    Tap($FF1B, 1, 'Escape');
    Tap($FF1B, 1, 'Escape');

    WriteLn('--- (b) 変換中でないときの素通り');
    Tap($FF08, 14, 'BackSpace（変換中テキストが無いとき）');

    Conn.CallVoid(IBUS_SERVICE, ICPath, IC_IFACE, 'FocusOut');
    Drain(200);
    WriteLn('待ちの残り: ', Length(Pending));
  finally
    Conn.Free;
  end;
end.
