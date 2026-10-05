{
  PaPiMeLa.TextInput.IBus — IBus の私設バスに直接繋ぐ IME バックエンド

  Origin : original work (clean-room design; not derived from SDL sources)
           SDL_ibus.c は接続手順の存在を知るためにだけ読み、構造もコードも写していない。
           D-Bus の定義は ibus-daemon 1.5.29 が持つ introspection、値は IBus 1.5.29 の
           公開ヘッダ（ibustypes.h、ibusattribute.h）、振る舞いは spikes/spike3_ibus.pas で実測した。
  Design : docs/DESIGN.md §7.4、§7.5、§11 #48

  WHAT:
    アドレスファイルから IBus の私設バスを見つけて入力コンテキストを作り、キーを
    返信を待たずに ProcessKeyEvent で渡す。UpdatePreeditText の IBusText の属性を
    全部読み、文節の並びとして公開する。周辺テキストの供給と周辺削除に対応する。

  WHY:
    IBus の属性には全文節の区切りと注目文節が載っている（SDL は背景色だけを見て
    単一の範囲にしていた）。キーを同期で渡すと IME が遅いときにアプリが止まるので、
    返信は TPMLKeyboardState の待ち行列（§7.5）で受ける。

  RESOLVED:
    - アドレスファイル: $XDG_CONFIG_HOME/ibus/bus/<machine-id>-<host>-<display>。
      machine-id は /var/lib/dbus/machine-id が先、display は WAYLAND_DISPLAY があれば
      "unix-<それ>"、次に DISPLAY（"host:3.1" → "host-3"）、最後に "unix-0"（実測）
    - fcitx5 は IBus のアドレスファイルを自分で書き、セッションバスの IBus 互換の口を
      指させる（IBUS_DAEMON_PID が fcitx5、アドレスに fcitx_random_string）。そこへ
      繋ぐと Fcitx の本来の口（文節の情報が多い）より先に選ばれてしまうので、断る
    - 文節の規則（TPMLIBusSegmenter）: 下線と背景の属性の境目で区間に分け、下線
      DOUBLE か背景のある区間を注目文節にする。注目文節があれば、他の下線 SINGLE の
      区間は変換済み。無ければ全部未変換（ibus-mozc は変換前の読みも、注目していない
      変換済みの文節も SINGLE だけなので、SINGLE だけでは区別できない。実測）
    - HidePreeditText は変換中テキストの消滅として扱う（確定の後・破棄で来る。実測）
    - RequireSurroundingText はキーごとに来る（実測）。前に送ったものと同じなら送らない
    - 入力の種類は ContentType プロパティ（(uu)、書き込み専用）で送る
    - 接続が切れたら、待っているキーを素通しにして、1 秒ごとにアドレスファイルを
      読み直して繋ぎ直す（ibus-daemon の再起動に追従する）

  NOT RESOLVED:
    - ForwardKeyEvent（IME がアプリへキーを渡す）は ibus-mozc では来なかったので、
      受けたら数えて記録するだけ（ForwardedKeyCount）。キーとして出すのは来る IME を
      見つけてから
    - 埋め込み候補（UpdateLookupTable → TextEditingCandidates）は未実装
    - アドレスファイルの inotify 監視は入れていない。切れたことに気づいてから読み直す
    - ibus-anthy / ibus-skk / ibus-libpinyin の属性は未実測（§10 項目 1）

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.TextInput.IBus;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Types,
  PaPiMeLa.Unicode,
  PaPiMeLa.Events,
  PaPiMeLa.Video,
  PaPiMeLa.Platform.DBus,
  PaPiMeLa.TextInput,
  PaPiMeLa.TextInput.Backend;

const
  // ibusattribute.h
  IBUS_ATTR_TYPE_UNDERLINE  = 1;
  IBUS_ATTR_TYPE_FOREGROUND = 2;
  IBUS_ATTR_TYPE_BACKGROUND = 3;
  IBUS_ATTR_UNDERLINE_NONE   = 0;
  IBUS_ATTR_UNDERLINE_SINGLE = 1;
  IBUS_ATTR_UNDERLINE_DOUBLE = 2;
  IBUS_ATTR_UNDERLINE_LOW    = 3;
  IBUS_ATTR_UNDERLINE_ERROR  = 4;

  // ibustypes.h
  IBUS_CAP_PREEDIT_TEXT     = 1 shl 0;
  IBUS_CAP_LOOKUP_TABLE     = 1 shl 2;
  IBUS_CAP_FOCUS            = 1 shl 3;
  IBUS_CAP_SURROUNDING_TEXT = 1 shl 5;
  IBUS_RELEASE_MASK         = LongWord(1) shl 30;

  IBUS_INPUT_PURPOSE_FREE_FORM = 0;
  IBUS_INPUT_PURPOSE_ALPHA     = 1;
  IBUS_INPUT_PURPOSE_DIGITS    = 2;
  IBUS_INPUT_PURPOSE_NUMBER    = 3;
  IBUS_INPUT_PURPOSE_PHONE     = 4;
  IBUS_INPUT_PURPOSE_URL       = 5;
  IBUS_INPUT_PURPOSE_EMAIL     = 6;
  IBUS_INPUT_PURPOSE_NAME      = 7;
  IBUS_INPUT_PURPOSE_PASSWORD  = 8;
  IBUS_INPUT_HINT_SPELLCHECK          = 1 shl 0;
  IBUS_INPUT_HINT_WORD_COMPLETION     = 1 shl 2;
  IBUS_INPUT_HINT_UPPERCASE_SENTENCES = 1 shl 6;
  IBUS_INPUT_HINT_PRIVATE             = 1 shl 11;

type
  TPMLIBusAttribute = record
    AttrType, Value     : LongWord;
    StartChar, EndChar  : LongWord;   // 文字（コードポイント）単位 [Start, End)
  end;
  TPMLIBusAttributes = array of TPMLIBusAttribute;

  TPMLIBusText = record
    Text      : String;
    Attributes: TPMLIBusAttributes;
  end;

  { IBus の属性から文節の並びを作る。規則は上の RESOLVED。 }
  TPMLIBusSegmenter = class sealed
  public
    class function Build(const AText: TPMLIBusText; ACursorChar: Integer): TPMLComposition; static;
  end;

  TPMLIBusPendingKey = record
    Serial, Ticket: LongWord;
  end;

  TPMLIBusTextInputBackend = class(TPMLTextInputBackend)
  strict private
    FConn        : TPMLDBusConnection;
    FICPath      : String;
    FPending     : array of TPMLIBusPendingKey;
    FActive      : Boolean;
    FType        : TPMLTextInputType;
    FHints       : TPMLTextInputHints;
    FComposition : TPMLComposition;
    FPreedit     : TPMLComposition;   // 最後に届いた変換中テキスト（Hide の間も覚える）
    FSurrounding : String;            // 最後に送った周辺テキスト
    FSurCursor, FSurAnchor: Integer;  // 文字単位
    FHaveSent    : Boolean;
    FLost        : Boolean;
    FRetryAtNS   : Int64;
    FForwarded   : Integer;
    FLastNonFatalError: String;
    function  OpenConnection: Boolean;
    procedure CloseConnection;
    procedure ConnectionLost;
    procedure SendActivation;
    procedure CallAsync(const AMethod: String);
    procedure SetComposition(const AComposition: TPMLComposition);
    procedure HandleMessage(AMsg: PDBusMessage);
    procedure HandleReply(AMsg: PDBusMessage);
    procedure HandleSignal(AMsg: PDBusMessage);
    function  GetPendingKeyCount: Integer;
  public
    destructor Destroy; override;
    function  BackendName: String; override;
    function  Capabilities: TPMLTextInputCapabilities; override;
    function  Connect(ASink: IPMLTextInputSink): Boolean; override;
    procedure Disconnect; override;
    procedure Activate(AWindow: TPMLWindow; AType: TPMLTextInputType;
      AHints: TPMLTextInputHints); override;
    procedure Deactivate; override;
    procedure ResetComposition; override;
    procedure UpdateSurroundingText(const AText: String; ACursorByte, AAnchorByte: Integer); override;
    procedure UpdateCursorRect(const ARect: TPMLRect; AScale: Double); override;
    function  FilterKey(const AKey: TPMLKeyEventData; AIsRelease: Boolean;
      ATicket: LongWord): TPMLKeyFilterResult; override;
    procedure Pump(ATimeoutMs: Integer); override;

    // テストと診断用。
    property InputContextPath: String read FICPath;
    property Connected: Boolean read FActive;
    property PendingKeyCount: Integer read GetPendingKeyCount;
    property ForwardedKeyCount: Integer read FForwarded;
    property LastNonFatalError: String read FLastNonFatalError;
  end;

{ IBusText（variant）を読む。AReader は variant を指していること。型名が違えば False。 }
function PMLReadIBusText(const AReader: TPMLDBusReader; out AText: TPMLIBusText): Boolean;
{ IBusText を variant として書く。 }
procedure PMLWriteIBusText(var AWriter: TPMLDBusWriter; const AText: TPMLIBusText);

{ アドレスファイルの候補を試す順に返す。AConfigDir は $XDG_CONFIG_HOME（無ければ
  ~/.config）。 }
function PMLIBusAddressFileCandidates(const AConfigDir, AMachineId,
  AWaylandDisplay, ADisplay: String): TStringArray;
{ アドレスファイルの中身から IBUS_ADDRESS と IBUS_DAEMON_PID を取り出す。 }
function PMLIBusParseAddressFile(const AContent: String; out AAddress: String;
  out APid: Integer): Boolean;
{ fcitx5 が IBus を装って書いたアドレスか。APidComm は IBUS_DAEMON_PID の
  プロセス名（/proc/<pid>/comm。読めなければ空）。 }
function PMLIBusIsFcitxEmulation(const AAddress, APidComm: String): Boolean;
{ 今の環境で使うアドレスを探す。見つからなければ空。AFile に見つけたファイル名。 }
function PMLIBusFindAddress(out AFile: String; out AFromFcitx: Boolean): String;

implementation

uses
  PaPiMeLa.Errors;

const
  IBUS_SERVICE = 'org.freedesktop.IBus';
  IBUS_PATH    = '/org/freedesktop/IBus';
  IBUS_IFACE   = 'org.freedesktop.IBus';
  IC_IFACE     = 'org.freedesktop.IBus.InputContext';
  PROPS_IFACE  = 'org.freedesktop.DBus.Properties';
  RETRY_NS     = Int64(1000) * 1000 * 1000;

{ ---- IBusText ---- }

// (s 型名, a{sv}, ...) の先頭の 2 つを読み、型名を確かめて 3 つ目に進める。
function EnterSerializable(var AStruct: TPMLDBusReader; const AName: String): Boolean;
begin
  Result := (AStruct.ArgType = DBUS_TYPE_STRING) and (AStruct.AsString = AName);
  if not Result then
    Exit;
  AStruct.Next;                                  // 型名
  Result := AStruct.ArgType = DBUS_TYPE_ARRAY;   // a{sv}（添付。使わない）
  if Result then
    AStruct.Next;
end;

{ AVariant が指す variant を開いて struct の中身を返す。 }
function OpenVariantStruct(const AVariant: TPMLDBusReader; out AFields: TPMLDBusReader): Boolean;
var
  V, S: TPMLDBusReader;
begin
  Result := False;
  V := AVariant;
  if V.ArgType <> DBUS_TYPE_VARIANT then
    Exit;
  S := V.Recurse;
  if S.ArgType <> DBUS_TYPE_STRUCT then
    Exit;
  AFields := S.Recurse;
  Result := True;
end;

function PMLReadIBusText(const AReader: TPMLDBusReader; out AText: TPMLIBusText): Boolean;
var
  F, L, Arr, A: TPMLDBusReader;
  N: Integer;
begin
  AText.Text := '';
  AText.Attributes := nil;
  Result := False;
  if not OpenVariantStruct(AReader, F) or not EnterSerializable(F, 'IBusText') then
    Exit;
  if F.ArgType <> DBUS_TYPE_STRING then
    Exit;
  AText.Text := F.AsString;
  F.Next;
  // 属性の並び。無い（古い IBus）なら属性なしとして受ける。
  if F.ArgType = DBUS_TYPE_VARIANT then
  begin
    if not OpenVariantStruct(F, L) or not EnterSerializable(L, 'IBusAttrList') then
      Exit;
    if L.ArgType <> DBUS_TYPE_ARRAY then
      Exit;
    Arr := L.Recurse;
    N := 0;
    while not Arr.AtEnd do
    begin
      if not OpenVariantStruct(Arr, A) or not EnterSerializable(A, 'IBusAttribute') then
        Exit;
      SetLength(AText.Attributes, N + 1);
      AText.Attributes[N].AttrType := A.AsUInt32;  A.Next;
      AText.Attributes[N].Value := A.AsUInt32;     A.Next;
      AText.Attributes[N].StartChar := A.AsUInt32; A.Next;
      AText.Attributes[N].EndChar := A.AsUInt32;
      Inc(N);
      Arr.Next;
    end;
  end;
  Result := True;
end;

procedure PMLWriteIBusText(var AWriter: TPMLDBusWriter; const AText: TPMLIBusText);
var
  V, S, D, LV, L, LD, Arr, AV, A, AD: TPMLDBusWriter;
  I: Integer;
begin
  V := AWriter.OpenVariant('(sa{sv}sv)');
  S := V.OpenStruct;
  S.AddString('IBusText');
  D := S.OpenArray('{sv}');
  S.Close(D);
  S.AddString(AText.Text);
  LV := S.OpenVariant('(sa{sv}av)');
  L := LV.OpenStruct;
  L.AddString('IBusAttrList');
  LD := L.OpenArray('{sv}');
  L.Close(LD);
  Arr := L.OpenArray('v');
  for I := 0 to High(AText.Attributes) do
  begin
    AV := Arr.OpenVariant('(sa{sv}uuuu)');
    A := AV.OpenStruct;
    A.AddString('IBusAttribute');
    AD := A.OpenArray('{sv}');
    A.Close(AD);
    A.AddUInt32(AText.Attributes[I].AttrType);
    A.AddUInt32(AText.Attributes[I].Value);
    A.AddUInt32(AText.Attributes[I].StartChar);
    A.AddUInt32(AText.Attributes[I].EndChar);
    AV.Close(A);
    Arr.Close(AV);
  end;
  L.Close(Arr);
  LV.Close(L);
  S.Close(LV);
  V.Close(S);
  AWriter.Close(V);
end;

{ ---- 文節 ---- }

function UnderlineStyleOf(AValue: LongWord): TPMLUnderlineStyle;
begin
  case AValue of
    IBUS_ATTR_UNDERLINE_SINGLE: Result := TPMLUnderlineStyle.Single;
    IBUS_ATTR_UNDERLINE_DOUBLE: Result := TPMLUnderlineStyle.Double;
    IBUS_ATTR_UNDERLINE_LOW:    Result := TPMLUnderlineStyle.Low;
    IBUS_ATTR_UNDERLINE_ERROR:  Result := TPMLUnderlineStyle.Error;
  else
    Result := TPMLUnderlineStyle.None;
  end;
end;

{ 1 つの区間に下線が重なったとき、どれを採るか。注目を表す DOUBLE を最も強くする。 }
function UnderlineRank(AStyle: TPMLUnderlineStyle): Integer;
begin
  case AStyle of
    TPMLUnderlineStyle.Double: Result := 4;
    TPMLUnderlineStyle.Error:  Result := 3;
    TPMLUnderlineStyle.Single: Result := 2;
    TPMLUnderlineStyle.Low:    Result := 1;
  else
    Result := 0;
  end;
end;

class function TPMLIBusSegmenter.Build(const AText: TPMLIBusText;
  ACursorChar: Integer): TPMLComposition;
type
  TCut = record
    A, B   : Integer;
    Style  : TPMLUnderlineStyle;
    Back   : Boolean;
  end;
var
  Total, I, J, K, N, Lo, Hi: Integer;
  Bounds: array of Integer;
  Cuts: array of TCut;
  AnyFocused: Boolean;
  Attr: TPMLIBusAttribute;
  St: TPMLUnderlineStyle;

  procedure AddBound(AValue: Integer);
  var
    P: Integer;
  begin
    for P := 0 to High(Bounds) do
      if Bounds[P] = AValue then
        Exit;
    SetLength(Bounds, Length(Bounds) + 1);
    Bounds[High(Bounds)] := AValue;
  end;

  function Relevant(const AA: TPMLIBusAttribute): Boolean;
  begin
    Result := ((AA.AttrType = IBUS_ATTR_TYPE_UNDERLINE) and (AA.Value <> IBUS_ATTR_UNDERLINE_NONE))
      or (AA.AttrType = IBUS_ATTR_TYPE_BACKGROUND);
  end;

begin
  Result.Clear;
  if AText.Text = '' then
    Exit;
  Result.Text := AText.Text;
  Total := UTF8CodePointCount(AText.Text);

  // 1. 下線と背景の属性の境目で [0, Total) を区間に分ける。範囲外は切り詰め、
  //    空になった属性は捨てる。
  Bounds := nil;
  AddBound(0);
  AddBound(Total);
  for I := 0 to High(AText.Attributes) do
  begin
    Attr := AText.Attributes[I];
    if not Relevant(Attr) then
      Continue;
    Lo := Integer(Attr.StartChar);
    Hi := Integer(Attr.EndChar);
    if Hi > Total then
      Hi := Total;
    if (Lo < 0) or (Lo >= Hi) then
      Continue;
    AddBound(Lo);
    AddBound(Hi);
  end;
  // 小さい順に並べる（数は高々数十）。
  for I := 1 to High(Bounds) do
  begin
    K := Bounds[I];
    J := I - 1;
    while (J >= 0) and (Bounds[J] > K) do
    begin
      Bounds[J + 1] := Bounds[J];
      Dec(J);
    end;
    Bounds[J + 1] := K;
  end;

  // 2. 区間ごとに、覆っている下線（最も強いもの）と背景の有無を求める。
  N := Length(Bounds) - 1;
  SetLength(Cuts, N);
  AnyFocused := False;
  for I := 0 to N - 1 do
  begin
    Cuts[I].A := Bounds[I];
    Cuts[I].B := Bounds[I + 1];
    Cuts[I].Style := TPMLUnderlineStyle.None;
    Cuts[I].Back := False;
    for J := 0 to High(AText.Attributes) do
    begin
      Attr := AText.Attributes[J];
      if not Relevant(Attr) then
        Continue;
      if (Integer(Attr.StartChar) > Cuts[I].A) or (Integer(Attr.EndChar) < Cuts[I].B) then
        Continue;
      if Attr.AttrType = IBUS_ATTR_TYPE_BACKGROUND then
        Cuts[I].Back := True
      else
      begin
        St := UnderlineStyleOf(Attr.Value);
        if UnderlineRank(St) > UnderlineRank(Cuts[I].Style) then
          Cuts[I].Style := St;
      end;
    end;
    if (Cuts[I].Style = TPMLUnderlineStyle.Double)
      or (Cuts[I].Back and (Cuts[I].Style <> TPMLUnderlineStyle.Error)) then
      AnyFocused := True;
  end;

  // 3. 状態を決めて、バイト位置で埋める。
  SetLength(Result.Segments, N);
  for I := 0 to N - 1 do
  begin
    Result.Segments[I].StartByte := UTF8CharToByteOffset(AText.Text, Cuts[I].A);
    Result.Segments[I].EndByte := UTF8CharToByteOffset(AText.Text, Cuts[I].B);
    Result.Segments[I].Underline := Cuts[I].Style;
    if Cuts[I].Style = TPMLUnderlineStyle.Error then
      Result.Segments[I].State := TPMLSegmentState.Unconverted
    else if (Cuts[I].Style = TPMLUnderlineStyle.Double) or Cuts[I].Back then
      Result.Segments[I].State := TPMLSegmentState.Focused
    else if AnyFocused and (Cuts[I].Style = TPMLUnderlineStyle.Single) then
      Result.Segments[I].State := TPMLSegmentState.Converted
    else
      Result.Segments[I].State := TPMLSegmentState.Unconverted;
  end;

  if ACursorChar < 0 then
    Result.CursorByte := -1
  else
  begin
    if ACursorChar > Total then
      ACursorChar := Total;
    Result.CursorByte := UTF8CharToByteOffset(AText.Text, ACursorChar);
  end;
  Result.SegmentsReliable := True;
  Result.Finalize;
end;

{ ---- アドレス ---- }

function PMLIBusAddressFileCandidates(const AConfigDir, AMachineId,
  AWaylandDisplay, ADisplay: String): TStringArray;
var
  Base, Host, Num: String;
  P: Integer;

  procedure Add(const AName: String);
  var
    I: Integer;
  begin
    for I := 0 to High(Result) do
      if Result[I] = AName then
        Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := AName;
  end;

begin
  Result := nil;
  Base := IncludeTrailingPathDelimiter(AConfigDir) + 'ibus/bus/' + AMachineId + '-';
  if AWaylandDisplay <> '' then
    Add(Base + 'unix-' + ExtractFileName(AWaylandDisplay));
  if ADisplay <> '' then
  begin
    P := Pos(':', ADisplay);
    if P > 0 then
    begin
      Host := Copy(ADisplay, 1, P - 1);
      if Host = '' then
        Host := 'unix';
      Num := Copy(ADisplay, P + 1, MaxInt);
      P := Pos('.', Num);
      if P > 0 then
        Num := Copy(Num, 1, P - 1);
      if Num <> '' then
        Add(Base + Host + '-' + Num);
    end;
  end;
  Add(Base + 'unix-0');
end;

function PMLIBusParseAddressFile(const AContent: String; out AAddress: String;
  out APid: Integer): Boolean;
var
  L: TStringList;
  I: Integer;
begin
  AAddress := '';
  APid := 0;
  L := TStringList.Create;
  try
    L.Text := AContent;
    for I := 0 to L.Count - 1 do
      if Copy(L[I], 1, 13) = 'IBUS_ADDRESS=' then
        AAddress := Trim(Copy(L[I], 14, MaxInt))
      else if Copy(L[I], 1, 16) = 'IBUS_DAEMON_PID=' then
        APid := StrToIntDef(Trim(Copy(L[I], 17, MaxInt)), 0);
  finally
    L.Free;
  end;
  Result := AAddress <> '';
end;

function PMLIBusIsFcitxEmulation(const AAddress, APidComm: String): Boolean;
begin
  Result := (Pos('fcitx', AAddress) > 0) or (Copy(Trim(APidComm), 1, 5) = 'fcitx');
end;

function ReadSmallFile(const AName: String): String;
var
  L: TStringList;
begin
  Result := '';
  if not FileExists(AName) then
    Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(AName);
      Result := L.Text;
    except
      on E: EStreamError do
        Result := '';
    end;
  finally
    L.Free;
  end;
end;

function PMLIBusFindAddress(out AFile: String; out AFromFcitx: Boolean): String;
var
  Config, MachineId: String;
  Names: TStringArray;
  I, Pid: Integer;
begin
  AFile := '';
  AFromFcitx := False;
  Result := GetEnvironmentVariable('IBUS_ADDRESS');
  if Result <> '' then
  begin
    AFromFcitx := PMLIBusIsFcitxEmulation(Result, '');
    Exit;
  end;
  Config := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if Config = '' then
    Config := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + '.config';
  // ibus-daemon と同じ順（実測）。
  MachineId := Trim(ReadSmallFile('/var/lib/dbus/machine-id'));
  if MachineId = '' then
    MachineId := Trim(ReadSmallFile('/etc/machine-id'));
  if MachineId = '' then
    Exit;
  Names := PMLIBusAddressFileCandidates(Config, MachineId,
    GetEnvironmentVariable('WAYLAND_DISPLAY'), GetEnvironmentVariable('DISPLAY'));
  for I := 0 to High(Names) do
    if PMLIBusParseAddressFile(ReadSmallFile(Names[I]), Result, Pid) then
    begin
      AFile := Names[I];
      AFromFcitx := PMLIBusIsFcitxEmulation(Result,
        ReadSmallFile(Format('/proc/%d/comm', [Pid])));
      Exit;
    end;
  Result := '';
end;

{ ---- バックエンド ---- }

destructor TPMLIBusTextInputBackend.Destroy;
begin
  Disconnect;
  inherited Destroy;
end;

function TPMLIBusTextInputBackend.BackendName: String;
begin
  Result := 'ibus';
end;

function TPMLIBusTextInputBackend.Capabilities: TPMLTextInputCapabilities;
begin
  Result := [
    TPMLTextInputCapability.Segments,
    TPMLTextInputCapability.SurroundingText,
    TPMLTextInputCapability.DeleteSurrounding,
    TPMLTextInputCapability.CursorRect,
    TPMLTextInputCapability.KeyFilter
  ];
end;

function TPMLIBusTextInputBackend.GetPendingKeyCount: Integer;
begin
  Result := Length(FPending);
end;

{ アドレスを探して繋ぎ、入力コンテキストを作る。失敗は False（例外にしない）。 }
function TPMLIBusTextInputBackend.OpenConnection: Boolean;
var
  Address, AddrFile: String;
  FromFcitx: Boolean;
  Msg, Reply: PDBusMessage;
  R: TPMLDBusReader;
begin
  Result := False;
  Address := PMLIBusFindAddress(AddrFile, FromFcitx);
  if Address = '' then
    Exit;
  if FromFcitx then
  begin
    FLastNonFatalError := 'IBus address belongs to fcitx5 (' + AddrFile + ')';
    Exit;
  end;
  try
    FConn := TPMLDBusConnection.CreateForAddress(Address);
    Msg := FConn.BeginCall(IBUS_SERVICE, IBUS_PATH, IBUS_IFACE, 'CreateInputContext');
    Reply := nil;
    try
      FConn.Writer(Msg).AddString('papimela');
      Reply := FConn.Send(Msg);
      R := FConn.Reader(Reply);
      FICPath := R.ExpectObjectPath;
    finally
      FConn.Unref(Reply);
      FConn.Unref(Msg);
    end;
    FConn.AddMatch(Format('type=''signal'',interface=''%s'',path=''%s''', [IC_IFACE, FICPath]));
    Result := True;
  except
    on E: EPMLError do
    begin
      // アドレスファイルが古い（デーモンが居ない）など。次の候補へ回す。
      FLastNonFatalError := E.Message;
      FreeAndNil(FConn);
      FICPath := '';
    end;
  end;
end;

procedure TPMLIBusTextInputBackend.CloseConnection;
begin
  if Assigned(FConn) and FConn.IsConnected and (FICPath <> '') then
  begin
    try
      CallAsync('Destroy');
    except
      on E: EPMLError do
        FLastNonFatalError := E.Message;
    end;
  end;
  FreeAndNil(FConn);
  FICPath := '';
end;

function TPMLIBusTextInputBackend.Connect(ASink: IPMLTextInputSink): Boolean;
begin
  Result := OpenConnection;
  if Result then
    FSink := ASink;
end;

procedure TPMLIBusTextInputBackend.Disconnect;
begin
  CloseConnection;
  FPending := nil;
  FActive := False;
  FLost := False;
  inherited Disconnect;
end;

{ 返信を待たずに引数なしのメソッドを呼ぶ。返信は Pump で読み捨てる。 }
procedure TPMLIBusTextInputBackend.CallAsync(const AMethod: String);
var
  Msg: PDBusMessage;
begin
  Msg := FConn.BeginCall(IBUS_SERVICE, FICPath, IC_IFACE, AMethod);
  try
    FConn.SendAsync(Msg);
  finally
    FConn.Unref(Msg);
  end;
end;

{ 能力・入力の種類を送ってからフォーカスを渡す。繋ぎ直した後にも使う。 }
procedure TPMLIBusTextInputBackend.SendActivation;
var
  Msg: PDBusMessage;
  W, V, S: TPMLDBusWriter;
  Caps, Purpose, Hint: LongWord;
begin
  Caps := IBUS_CAP_PREEDIT_TEXT or IBUS_CAP_FOCUS or IBUS_CAP_SURROUNDING_TEXT;
  Msg := FConn.BeginCall(IBUS_SERVICE, FICPath, IC_IFACE, 'SetCapabilities');
  try
    FConn.Writer(Msg).AddUInt32(Caps);
    FConn.SendAsync(Msg);
  finally
    FConn.Unref(Msg);
  end;

  case FType of
    TPMLTextInputType.Name:     Purpose := IBUS_INPUT_PURPOSE_NAME;
    TPMLTextInputType.Email:    Purpose := IBUS_INPUT_PURPOSE_EMAIL;
    TPMLTextInputType.Username: Purpose := IBUS_INPUT_PURPOSE_ALPHA;
    TPMLTextInputType.Password: Purpose := IBUS_INPUT_PURPOSE_PASSWORD;
    TPMLTextInputType.Number:   Purpose := IBUS_INPUT_PURPOSE_NUMBER;
    TPMLTextInputType.Phone:    Purpose := IBUS_INPUT_PURPOSE_PHONE;
    TPMLTextInputType.Url:      Purpose := IBUS_INPUT_PURPOSE_URL;
  else
    Purpose := IBUS_INPUT_PURPOSE_FREE_FORM;
  end;
  Hint := 0;
  if TPMLTextInputHint.AutoCorrect in FHints then
    Hint := Hint or IBUS_INPUT_HINT_SPELLCHECK or IBUS_INPUT_HINT_WORD_COMPLETION;
  if TPMLTextInputHint.AutoCapitalize in FHints then
    Hint := Hint or IBUS_INPUT_HINT_UPPERCASE_SENTENCES;
  if (TPMLTextInputHint.Sensitive in FHints) or (FType = TPMLTextInputType.Password) then
    Hint := Hint or IBUS_INPUT_HINT_PRIVATE;
  // ContentType はメソッドではなく書き込み専用のプロパティ (uu)。
  Msg := FConn.BeginCall(IBUS_SERVICE, FICPath, PROPS_IFACE, 'Set');
  try
    W := FConn.Writer(Msg);
    W.AddString(IC_IFACE);
    W.AddString('ContentType');
    V := W.OpenVariant('(uu)');
    S := V.OpenStruct;
    S.AddUInt32(Purpose);
    S.AddUInt32(Hint);
    V.Close(S);
    W.Close(V);
    FConn.SendAsync(Msg);
  finally
    FConn.Unref(Msg);
  end;

  CallAsync('FocusIn');
  FHaveSent := False;
end;

procedure TPMLIBusTextInputBackend.Activate(AWindow: TPMLWindow;
  AType: TPMLTextInputType; AHints: TPMLTextInputHints);
begin
  FType := AType;
  FHints := AHints;
  FActive := True;
  if Assigned(FConn) then
    SendActivation;
end;

procedure TPMLIBusTextInputBackend.Deactivate;
var
  Empty: TPMLComposition;
begin
  FActive := False;
  if Assigned(FConn) then
    CallAsync('FocusOut');
  Empty.Clear;
  FPreedit.Clear;
  SetComposition(Empty);
end;

procedure TPMLIBusTextInputBackend.ResetComposition;
var
  Empty: TPMLComposition;
begin
  if Assigned(FConn) then
    CallAsync('Reset');
  Empty.Clear;
  FPreedit.Clear;
  SetComposition(Empty);
end;

{ IBus は周辺テキストを文字単位で話す。前に送ったものと同じなら送らない
  （mozc はキーごとに求めてくる。実測）。 }
procedure TPMLIBusTextInputBackend.UpdateSurroundingText(const AText: String;
  ACursorByte, AAnchorByte: Integer);
var
  Msg: PDBusMessage;
  W: TPMLDBusWriter;
  T: TPMLIBusText;
  C, A: Integer;
begin
  if not Assigned(FConn) then
    Exit;
  C := UTF8ByteToCharOffset(AText, ACursorByte);
  A := UTF8ByteToCharOffset(AText, AAnchorByte);
  if FHaveSent and (AText = FSurrounding) and (C = FSurCursor) and (A = FSurAnchor) then
    Exit;
  T.Text := AText;
  T.Attributes := nil;
  Msg := FConn.BeginCall(IBUS_SERVICE, FICPath, IC_IFACE, 'SetSurroundingText');
  try
    W := FConn.Writer(Msg);
    PMLWriteIBusText(W, T);
    W.AddUInt32(LongWord(C));
    W.AddUInt32(LongWord(A));
    FConn.SendAsync(Msg);
  finally
    FConn.Unref(Msg);
  end;
  FSurrounding := AText;
  FSurCursor := C;
  FSurAnchor := A;
  FHaveSent := True;
end;

{ ウィンドウからの相対位置で送る（Wayland には画面の座標が無い）。 }
procedure TPMLIBusTextInputBackend.UpdateCursorRect(const ARect: TPMLRect; AScale: Double);
var
  Msg: PDBusMessage;
  W: TPMLDBusWriter;
begin
  if not Assigned(FConn) then
    Exit;
  Msg := FConn.BeginCall(IBUS_SERVICE, FICPath, IC_IFACE, 'SetCursorLocationRelative');
  try
    W := FConn.Writer(Msg);
    W.AddInt32(ARect.X);
    W.AddInt32(ARect.Y);
    W.AddInt32(ARect.W);
    W.AddInt32(ARect.H);
    FConn.SendAsync(Msg);
  finally
    FConn.Unref(Msg);
  end;
end;

{ キーを返信を待たずに送り、番号を覚えて Deferred を返す。返信は Pump で受けて
  Sink.KeyResolved に渡す。keycode は evdev の値（X の keycode - 8）。 }
function TPMLIBusTextInputBackend.FilterKey(const AKey: TPMLKeyEventData;
  AIsRelease: Boolean; ATicket: LongWord): TPMLKeyFilterResult;
var
  Msg: PDBusMessage;
  W: TPMLDBusWriter;
  State, Code, Serial: LongWord;
begin
  Result := TPMLKeyFilterResult.PassThrough;
  if not Assigned(FConn) or not FActive or (AKey.Keysym = 0) then
    Exit;
  State := PMLModifiersToXState(AKey.Modifiers);
  if AIsRelease then
    State := State or IBUS_RELEASE_MASK;
  Code := 0;
  if AKey.Raw >= 8 then
    Code := AKey.Raw - 8;
  Msg := FConn.BeginCall(IBUS_SERVICE, FICPath, IC_IFACE, 'ProcessKeyEvent');
  try
    W := FConn.Writer(Msg);
    W.AddUInt32(AKey.Keysym);
    W.AddUInt32(Code);
    W.AddUInt32(State);
    Serial := FConn.SendAsync(Msg);
  finally
    FConn.Unref(Msg);
  end;
  SetLength(FPending, Length(FPending) + 1);
  FPending[High(FPending)].Serial := Serial;
  FPending[High(FPending)].Ticket := ATicket;
  Result := TPMLKeyFilterResult.Deferred;
end;

procedure TPMLIBusTextInputBackend.SetComposition(const AComposition: TPMLComposition);
begin
  if AComposition.SameAs(FComposition) then
    Exit;
  FComposition := AComposition;
  if Assigned(FSink) then
    FSink.CompositionChanged(FComposition);
end;

procedure TPMLIBusTextInputBackend.HandleReply(AMsg: PDBusMessage);
var
  Serial: LongWord;
  I: Integer;
  Ticket: LongWord;
  Handled: Boolean;
  R: TPMLDBusReader;
begin
  Serial := FConn.ReplySerialOf(AMsg);
  for I := 0 to High(FPending) do
    if FPending[I].Serial = Serial then
    begin
      Ticket := FPending[I].Ticket;
      Delete(FPending, I, 1);
      Handled := False;
      if FConn.TypeOf(AMsg) = DBUS_MESSAGE_TYPE_METHOD_RETURN then
      begin
        R := FConn.Reader(AMsg);
        Handled := (R.ArgType = DBUS_TYPE_BOOLEAN) and R.AsBoolean;
      end
      else
        FLastNonFatalError := 'ProcessKeyEvent: ' + FConn.ErrorNameOf(AMsg);
      if Assigned(FSink) then
        FSink.KeyResolved(Ticket, Handled);
      Exit;
    end;
  // キー以外の呼び出し（FocusIn など）の返信。エラーだけ残す。
  if FConn.TypeOf(AMsg) = DBUS_MESSAGE_TYPE_ERROR then
    FLastNonFatalError := FConn.ErrorNameOf(AMsg);
end;

procedure TPMLIBusTextInputBackend.HandleSignal(AMsg: PDBusMessage);
var
  Member: String;
  R: TPMLDBusReader;
  T: TPMLIBusText;
  Cursor: LongWord;
  Visible: Boolean;
  Offset: LongInt;
  Count: LongWord;
  Empty: TPMLComposition;
begin
  Member := FConn.MemberOf(AMsg);
  R := FConn.Reader(AMsg);
  if Member = 'CommitText' then
  begin
    if PMLReadIBusText(R, T) and (T.Text <> '') and Assigned(FSink) then
      FSink.TextCommitted(T.Text);
  end
  else if (Member = 'UpdatePreeditText') or (Member = 'UpdatePreeditTextWithMode') then
  begin
    if not PMLReadIBusText(R, T) then
      Exit;
    R.Next;
    Cursor := 0;
    if R.ArgType = DBUS_TYPE_UINT32 then
      Cursor := R.AsUInt32;
    R.Next;
    Visible := (R.ArgType = DBUS_TYPE_BOOLEAN) and R.AsBoolean;
    FPreedit := TPMLIBusSegmenter.Build(T, Integer(Cursor));
    if Visible then
      SetComposition(FPreedit)
    else
    begin
      Empty.Clear;
      SetComposition(Empty);
    end;
  end
  else if Member = 'ShowPreeditText' then
    SetComposition(FPreedit)
  else if Member = 'HidePreeditText' then
  begin
    Empty.Clear;
    SetComposition(Empty);
  end
  else if Member = 'DeleteSurroundingText' then
  begin
    if R.ArgType <> DBUS_TYPE_INT32 then
      Exit;
    Offset := R.AsInt32;
    R.Next;
    if R.ArgType <> DBUS_TYPE_UINT32 then
      Exit;
    Count := R.AsUInt32;
    if not FHaveSent then
    begin
      FLastNonFatalError := 'DeleteSurroundingText without surrounding text';
      Exit;
    end;
    if Assigned(FSink) then
      FSink.DeleteSurroundingRequested(
        PMLDeleteSurroundingFromChars(FSurrounding, FSurCursor, Offset, Integer(Count)));
    // 削除を適用したら周辺テキストは変わる。同じものでも送り直させる。
    FHaveSent := False;
  end
  else if Member = 'RequireSurroundingText' then
  begin
    if Assigned(FSink) then
      FSink.SurroundingTextRequested;
  end
  else if Member = 'ForwardKeyEvent' then
    Inc(FForwarded);
end;

procedure TPMLIBusTextInputBackend.HandleMessage(AMsg: PDBusMessage);
begin
  case FConn.TypeOf(AMsg) of
    DBUS_MESSAGE_TYPE_METHOD_RETURN, DBUS_MESSAGE_TYPE_ERROR:
      HandleReply(AMsg);
    DBUS_MESSAGE_TYPE_SIGNAL:
      HandleSignal(AMsg);
  end;
end;

{ ibus-daemon が居なくなった。待っているキーは返信が来ないので素通しにし、
  変換中テキストを消し、後で繋ぎ直す。 }
procedure TPMLIBusTextInputBackend.ConnectionLost;
var
  I: Integer;
  Pending: array of TPMLIBusPendingKey;
  Empty: TPMLComposition;
begin
  Pending := FPending;
  FPending := nil;
  FreeAndNil(FConn);
  FICPath := '';
  FHaveSent := False;
  FLost := True;
  FRetryAtNS := Int64(PMLNowNS) + RETRY_NS;
  FLastNonFatalError := 'IBus connection lost';
  if Assigned(FSink) then
    for I := 0 to High(Pending) do
      FSink.KeyResolved(Pending[I].Ticket, False);
  Empty.Clear;
  FPreedit.Clear;
  SetComposition(Empty);
end;

procedure TPMLIBusTextInputBackend.Pump(ATimeoutMs: Integer);
var
  Msg: PDBusMessage;
begin
  if not Assigned(FConn) then
  begin
    // 繋ぎ直し（ibus-daemon の再起動に追従する）。
    if FLost and (Int64(PMLNowNS) >= FRetryAtNS) then
    begin
      FRetryAtNS := Int64(PMLNowNS) + RETRY_NS;
      if OpenConnection then
      begin
        FLost := False;
        if FActive then
        begin
          SendActivation;
          if Assigned(FSink) then
            FSink.SurroundingTextRequested;
        end;
      end;
    end;
    Exit;
  end;
  repeat
    Msg := FConn.PopMessage(ATimeoutMs);
    if Msg = nil then
      Break;
    try
      HandleMessage(Msg);
    finally
      FConn.Unref(Msg);
    end;
    ATimeoutMs := 0;   // 2 通目以降は待たない
  until False;
  if not FConn.IsConnected then
    ConnectionLost;
end;

{ ---- 登録 ---- }

function CreateIBusTextInputBackend: TPMLTextInputBackend;
begin
  Result := TPMLIBusTextInputBackend.Create;
end;

initialization
  // 文節が取れて、キーを返信を待たずに渡せる。IBus が動いていれば最初に選ぶ
  // （fcitx5 が IBus を装っているときは Connect で断るので、Fcitx が選ばれる）。
  PMLRegisterTextInputBackend('ibus', 200, @CreateIBusTextInputBackend);

end.
