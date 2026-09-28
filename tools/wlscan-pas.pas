{
  wlscan-pas — Wayland プロトコル XML から Free Pascal のバインディングを生成する

  Origin : original work (clean-room design; not derived from SDL sources)
           wayland-scanner の出力を観察してセマンティクス（シグネチャ文字列、
           types 配列プールの配置、destructor の marshal フラグ）を合わせてあるが、
           コードは参照していない。
  Design : docs/DESIGN.md §9.2

  WHAT:
    1 つの XML から 1 つのユニット PaPiMeLa.Platform.Wayland.Protocols.<Name> を
    生成する。生成物はリクエストのスタブ、イベントリスナー（レコード + 抽象クラス
    + サンク）、列挙定数、バージョン定数、wl_interface 記述子。

  WHY:
    Wayland バックエンド実装の前提。libwayland は拡張プロトコルの wl_interface
    記述子を持たないので、C では wayland-scanner が生成したコードをリンクする。
    Pascal では同等のものを自前で用意する必要がある。

  RESOLVED:
    - コアプロトコル（wayland.xml）の記述子は libwayland が公開しているので
      dlsym で引く。拡張プロトコルは記述子を Pascal 側で組む
    - 記述子は定数式では書けない（types 配列が相互参照するポインタ配列になる）。
      EnsureProtocolInitialized 手続きを生成して実行時に組む。設計 §9.2 が
      代替案として挙げていた方式を採る
    - リクエストは wl_proxy_marshal_flags を可変長引数で直接呼ぶ。関数ポインタ
      経由でも動作することを実測で確認したので wl_proxy_marshal_array_flags は不要

  使い方:
    wlscan-pas <出力ディレクトリ> <protocol.xml> [...]

    複数の XML を 1 回で渡すと、インターフェースがどのユニットに属するかを
    解決して uses 節を生成する。コアを含めて一度に渡すこと。

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス。papimela.inc を参照）
}
program wlscanpas;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, DOM, XMLRead;

const
  CORE_PROTOCOL = 'wayland';

type
  TArgKind = (akInt, akUInt, akFixed, akString, akObject, akNewId, akArray, akFD);

  TArg = record
    Name     : String;
    Kind     : TArgKind;
    IfaceName: String;      // object / new_id のみ。空 = 不定
    AllowNull: Boolean;
  end;

  TMessage = record
    Name        : String;
    Since       : Integer;
    IsDestructor: Boolean;
    Args        : array of TArg;
    Signature   : String;
    TypeSlots   : array of String;   // 1 シグネチャ文字につき 1 要素。'' = nil
    TypesOffset : Integer;
  end;

  TEnumEntry = record
    Name : String;
    Value: String;
  end;

  TEnumDef = record
    Name    : String;
    Bitfield: Boolean;
    Entries : array of TEnumEntry;
  end;

  TInterfaceDef = record
    Name    : String;
    Version : Integer;
    Requests: array of TMessage;
    Events  : array of TMessage;
    Enums   : array of TEnumDef;
  end;

  TProtocolDef = record
    Name      : String;
    UnitSuffix: String;
    Copyright : String;
    Interfaces: array of TInterfaceDef;
    PoolSize  : Integer;
    PoolSlots : array of String;
    IsCore    : Boolean;
  end;

var
  GProtocols  : array of TProtocolDef;
  GIfaceToUnit: TStringList;   // interface 名 → ユニット接尾辞
  GOutDir     : String;

{ ---- 文字列ユーティリティ ---- }

const
  PASCAL_KEYWORDS: array[0..56] of String = (
    'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor',
    'destructor', 'div', 'do', 'downto', 'else', 'end', 'except', 'exports',
    'file', 'finalization', 'finally', 'for', 'function', 'goto', 'if',
    'implementation', 'in', 'inherited', 'initialization', 'inline', 'interface',
    'is', 'label', 'library', 'mod', 'nil', 'not', 'object', 'of', 'on',
    'operator', 'or', 'out', 'packed', 'procedure', 'program', 'property',
    'raise', 'record', 'repeat', 'set', 'shl', 'shr', 'string', 'then', 'to',
    'type', 'unit'
  );

function SanitizeIdent(const AName: String): String;
var
  I: Integer;
begin
  Result := AName;
  for I := Low(PASCAL_KEYWORDS) to High(PASCAL_KEYWORDS) do
    if LowerCase(Result) = PASCAL_KEYWORDS[I] then
      Exit(Result + '_');
  if (LowerCase(Result) = 'result') or (LowerCase(Result) = 'self')
    or (LowerCase(Result) = 'uses') or (LowerCase(Result) = 'var')
    or (LowerCase(Result) = 'while') or (LowerCase(Result) = 'with')
    or (LowerCase(Result) = 'xor') or (LowerCase(Result) = 'until')
    or (LowerCase(Result) = 'threadvar') or (LowerCase(Result) = 'try')
    or (LowerCase(Result) = 'resourcestring') then
    Result := Result + '_';
end;

{ 引数名の衝突回避。

  Pascal は大文字小文字を区別しないため、C では別物になる名前が衝突する。
  避けるべきもの:
    - Pascal の予約語
    - メッセージ名そのもの（wl_pointer.axis はイベント名と引数名が同じ）
    - 生成側が使う名前（AProxy、data） }
var
  // 現在出力中のインターフェースのメッセージ名すべて。引数名がこれと衝突すると
  // FPC は Duplicate identifier を出す（クラス宣言内でメソッド名と同名の引数は
  // 許されない。例: wl_pointer.axis_stop の引数 axis はメソッド axis と衝突する）。
  GIfaceReserved: TStringList = nil;

function SanitizeArgName(const AName, AMsgName: String): String;
begin
  Result := SanitizeIdent(AName);
  if (LowerCase(Result) = LowerCase(AMsgName))
    or (LowerCase(Result) = 'aproxy')
    or (LowerCase(Result) = 'data')
    or (LowerCase(Result) = 'ainterface')
    or (LowerCase(Result) = 'aversion')
    or (LowerCase(Result) = 'alistener') then
    Exit(Result + '_');
  // 生成コードが使う型名を引数名が隠してはならない。
  // 例: zwp_relative_pointer_manager_v1.get_relative_pointer の引数 pointer は
  // Pointer 型を隠すので、可変長引数の Pointer(nil) が関数呼び出しに解釈される。
  case LowerCase(Result) of
    'pointer', 'longword', 'longint', 'integer', 'cardinal', 'boolean',
    'string', 'pansichar', 'byte', 'word', 'double', 'single', 'char',
    'wl_fixed_t', 'pwl_array', 'pwl_proxy', 'pwl_interface', 'true', 'false':
      Exit(Result + '_');
  end;
  if (GIfaceReserved <> nil) and (GIfaceReserved.IndexOf(LowerCase(Result)) >= 0) then
    Result := Result + '_';
end;

// 1 インターフェース分の予約名（リクエスト名 + イベント名）を集める。
procedure SetReservedFor(const ARequests, AEvents: array of TMessage);
var
  I: Integer;
begin
  if GIfaceReserved = nil then
    GIfaceReserved := TStringList.Create;
  GIfaceReserved.Clear;
  for I := 0 to High(ARequests) do
    GIfaceReserved.Add(LowerCase(SanitizeIdent(ARequests[I].Name)));
  for I := 0 to High(AEvents) do
    GIfaceReserved.Add(LowerCase(SanitizeIdent(AEvents[I].Name)));
end;

// text_input_unstable_v3 → TextInputUnstableV3
function ToPascalCase(const AName: String): String;
var
  I: Integer;
  Up: Boolean;
begin
  Result := '';
  Up := True;
  for I := 1 to Length(AName) do
    if AName[I] = '_' then
      Up := True
    else
    begin
      if Up then
        Result := Result + UpCase(AName[I])
      else
        Result := Result + AName[I];
      Up := False;
    end;
end;

// 0x1234 形式を Pascal の $1234 に直す。
function ToPascalNumber(const AValue: String): String;
begin
  if (Length(AValue) > 2) and (AValue[1] = '0')
    and ((AValue[2] = 'x') or (AValue[2] = 'X')) then
    Result := '$' + Copy(AValue, 3, MaxInt)
  else
    Result := AValue;
end;

{ ---- XML 解析 ---- }

function AttrOf(ANode: TDOMNode; const AName: String; const ADefault: String = ''): String;
var
  A: TDOMNode;
begin
  Result := ADefault;
  if ANode = nil then
    Exit;
  A := ANode.Attributes.GetNamedItem(AName);
  if A <> nil then
    Result := String(A.NodeValue);
end;

function ParseArgKind(const AType: String): TArgKind;
begin
  case AType of
    'int'    : Result := akInt;
    'uint'   : Result := akUInt;
    'fixed'  : Result := akFixed;
    'string' : Result := akString;
    'object' : Result := akObject;
    'new_id' : Result := akNewId;
    'array'  : Result := akArray;
    'fd'     : Result := akFD;
  else
    raise Exception.CreateFmt('unknown argument type "%s"', [AType]);
  end;
end;

procedure ParseMessage(ANode: TDOMNode; out AMsg: TMessage);
var
  Child: TDOMNode;
  N    : Integer;
begin
  AMsg.Name := AttrOf(ANode, 'name');
  AMsg.Since := StrToIntDef(AttrOf(ANode, 'since', '1'), 1);
  AMsg.IsDestructor := AttrOf(ANode, 'type') = 'destructor';
  SetLength(AMsg.Args, 0);
  N := 0;
  Child := ANode.FirstChild;
  while Child <> nil do
  begin
    if (Child.NodeType = ELEMENT_NODE) and (Child.NodeName = 'arg') then
    begin
      SetLength(AMsg.Args, N + 1);
      AMsg.Args[N].Name := AttrOf(Child, 'name');
      AMsg.Args[N].Kind := ParseArgKind(AttrOf(Child, 'type'));
      AMsg.Args[N].IfaceName := AttrOf(Child, 'interface');
      AMsg.Args[N].AllowNull := AttrOf(Child, 'allow-null') = 'true';
      Inc(N);
    end;
    Child := Child.NextSibling;
  end;
end;

procedure ParseEnum(ANode: TDOMNode; out AEnum: TEnumDef);
var
  Child: TDOMNode;
  N    : Integer;
begin
  AEnum.Name := AttrOf(ANode, 'name');
  AEnum.Bitfield := AttrOf(ANode, 'bitfield') = 'true';
  SetLength(AEnum.Entries, 0);
  N := 0;
  Child := ANode.FirstChild;
  while Child <> nil do
  begin
    if (Child.NodeType = ELEMENT_NODE) and (Child.NodeName = 'entry') then
    begin
      SetLength(AEnum.Entries, N + 1);
      AEnum.Entries[N].Name := AttrOf(Child, 'name');
      AEnum.Entries[N].Value := AttrOf(Child, 'value');
      Inc(N);
    end;
    Child := Child.NextSibling;
  end;
end;

procedure ParseInterface(ANode: TDOMNode; out AIface: TInterfaceDef);
var
  Child: TDOMNode;
  NR, NE, NEn: Integer;
begin
  AIface.Name := AttrOf(ANode, 'name');
  AIface.Version := StrToIntDef(AttrOf(ANode, 'version', '1'), 1);
  SetLength(AIface.Requests, 0);
  SetLength(AIface.Events, 0);
  SetLength(AIface.Enums, 0);
  NR := 0; NE := 0; NEn := 0;
  Child := ANode.FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = ELEMENT_NODE then
    begin
      if Child.NodeName = 'request' then
      begin
        SetLength(AIface.Requests, NR + 1);
        ParseMessage(Child, AIface.Requests[NR]);
        Inc(NR);
      end
      else if Child.NodeName = 'event' then
      begin
        SetLength(AIface.Events, NE + 1);
        ParseMessage(Child, AIface.Events[NE]);
        Inc(NE);
      end
      else if Child.NodeName = 'enum' then
      begin
        SetLength(AIface.Enums, NEn + 1);
        ParseEnum(Child, AIface.Enums[NEn]);
        Inc(NEn);
      end;
    end;
    Child := Child.NextSibling;
  end;
end;

procedure ParseProtocol(const AFileName: String; out AProto: TProtocolDef);
var
  Doc  : TXMLDocument;
  Root, Child: TDOMNode;
  N    : Integer;
begin
  ReadXMLFile(Doc, AFileName);
  try
    Root := Doc.DocumentElement;
    AProto.Name := AttrOf(Root, 'name');
    AProto.UnitSuffix := ToPascalCase(AProto.Name);
    AProto.IsCore := AProto.Name = CORE_PROTOCOL;
    AProto.Copyright := '';
    SetLength(AProto.Interfaces, 0);
    N := 0;
    Child := Root.FirstChild;
    while Child <> nil do
    begin
      if Child.NodeType = ELEMENT_NODE then
      begin
        if Child.NodeName = 'copyright' then
          AProto.Copyright := Trim(String(Child.TextContent))
        else if Child.NodeName = 'interface' then
        begin
          SetLength(AProto.Interfaces, N + 1);
          ParseInterface(Child, AProto.Interfaces[N]);
          Inc(N);
        end;
      end;
      Child := Child.NextSibling;
    end;
  finally
    Doc.Free;
  end;
end;

{ ---- シグネチャと types プール ---- }

// 1 引数が寄与するシグネチャ文字と type スロットを返す。
procedure ArgSignature(const AArg: TArg; out ALetters: String;
  out ASlots: array of String; out ASlotCount: Integer);
begin
  ASlotCount := 0;
  case AArg.Kind of
    akInt   : ALetters := 'i';
    akUInt  : ALetters := 'u';
    akFixed : ALetters := 'f';
    akString: ALetters := 's';
    akArray : ALetters := 'a';
    akFD    : ALetters := 'h';
    akObject: ALetters := 'o';
    akNewId :
      if AArg.IfaceName = '' then
        // インターフェース不定の new_id は「名前(s) + バージョン(u) + new_id(n)」に展開される
        ALetters := 'sun'
      else
        ALetters := 'n';
  end;
  if AArg.AllowNull then
    ALetters := '?' + ALetters;

  // type スロット: object / new_id の位置にインターフェース名、他は空
  case AArg.Kind of
    akObject:
      begin
        ASlots[0] := AArg.IfaceName;
        ASlotCount := 1;
      end;
    akNewId:
      if AArg.IfaceName = '' then
      begin
        ASlots[0] := ''; ASlots[1] := ''; ASlots[2] := '';
        ASlotCount := 3;
      end
      else
      begin
        ASlots[0] := AArg.IfaceName;
        ASlotCount := 1;
      end;
  else
    ASlots[0] := '';
    ASlotCount := 1;
  end;
end;

procedure ComputeMessage(var AMsg: TMessage);
var
  I, J, K, SlotCount: Integer;
  Letters: String;
  Slots  : array[0..2] of String;
begin
  AMsg.Signature := '';
  if AMsg.Since > 1 then
    AMsg.Signature := IntToStr(AMsg.Since);
  SetLength(AMsg.TypeSlots, 0);
  K := 0;
  for I := 0 to High(AMsg.Args) do
  begin
    ArgSignature(AMsg.Args[I], Letters, Slots, SlotCount);
    AMsg.Signature := AMsg.Signature + Letters;
    SetLength(AMsg.TypeSlots, K + SlotCount);
    for J := 0 to SlotCount - 1 do
      AMsg.TypeSlots[K + J] := Slots[J];
    Inc(K, SlotCount);
  end;
end;

function MessageHasTypes(const AMsg: TMessage): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(AMsg.TypeSlots) do
    if AMsg.TypeSlots[I] <> '' then
      Exit(True);
  Result := False;
end;

// wayland-scanner と同じ配置: 先頭に「型を持たないメッセージ」が共有する NULL の
// 並びを置き、その後ろに型を持つメッセージの引数列を順に追記する。
procedure ComputePool(var AProto: TProtocolDef);
var
  I, J, K, NullRun: Integer;

  procedure ScanNullRun(var AMsgs: array of TMessage);
  var
    M: Integer;
  begin
    for M := 0 to High(AMsgs) do
    begin
      ComputeMessage(AMsgs[M]);
      if not MessageHasTypes(AMsgs[M]) then
        if Length(AMsgs[M].TypeSlots) > NullRun then
          NullRun := Length(AMsgs[M].TypeSlots);
    end;
  end;

  procedure AssignOffsets(var AMsgs: array of TMessage);
  var
    M, S: Integer;
  begin
    for M := 0 to High(AMsgs) do
      if not MessageHasTypes(AMsgs[M]) then
        AMsgs[M].TypesOffset := 0
      else
      begin
        AMsgs[M].TypesOffset := Length(AProto.PoolSlots);
        for S := 0 to High(AMsgs[M].TypeSlots) do
        begin
          SetLength(AProto.PoolSlots, Length(AProto.PoolSlots) + 1);
          AProto.PoolSlots[High(AProto.PoolSlots)] := AMsgs[M].TypeSlots[S];
        end;
      end;
  end;

begin
  NullRun := 0;
  for I := 0 to High(AProto.Interfaces) do
  begin
    ScanNullRun(AProto.Interfaces[I].Requests);
    ScanNullRun(AProto.Interfaces[I].Events);
  end;

  SetLength(AProto.PoolSlots, NullRun);
  for K := 0 to NullRun - 1 do
    AProto.PoolSlots[K] := '';

  for J := 0 to High(AProto.Interfaces) do
  begin
    AssignOffsets(AProto.Interfaces[J].Requests);
    AssignOffsets(AProto.Interfaces[J].Events);
  end;
  AProto.PoolSize := Length(AProto.PoolSlots);
end;

{ ---- 出力 ---- }

function PascalArgType(const AArg: TArg): String;
begin
  case AArg.Kind of
    akInt   : Result := 'LongInt';
    akUInt  : Result := 'LongWord';
    akFixed : Result := 'wl_fixed_t';
    akString: Result := 'PAnsiChar';
    akArray : Result := 'Pwl_array';
    akFD    : Result := 'LongInt';
    akObject: if AArg.IfaceName = '' then
                Result := 'Pwl_proxy'
              else
                Result := 'P' + AArg.IfaceName;
    akNewId : Result := 'P' + AArg.IfaceName;
  else
    Result := 'Pointer';
  end;
end;

function NewIdArgIndex(const AMsg: TMessage): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AMsg.Args) do
    if AMsg.Args[I].Kind = akNewId then
      Exit(I);
  Result := -1;
end;

type
  TEmitter = class
  strict private
    FLines: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const ALine: String);
    procedure AddFmt(const AFmt: String; const AArgs: array of const);
    procedure Blank;
    procedure SaveTo(const AFileName: String);
  end;

constructor TEmitter.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
  FLines.LineBreak := #10;
end;

destructor TEmitter.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

procedure TEmitter.Add(const ALine: String);
begin
  FLines.Add(ALine);
end;

procedure TEmitter.AddFmt(const AFmt: String; const AArgs: array of const);
begin
  FLines.Add(Format(AFmt, AArgs));
end;

procedure TEmitter.Blank;
begin
  FLines.Add('');
end;

{ バイト列をそのまま書き出す。

  TStringList.SaveToFile でも結果は同じだが、コードページ変換の可能性を
  介在させないため明示的にバイトを書く。改行は常に LF。 }
procedure TEmitter.SaveTo(const AFileName: String);
var
  FS: TFileStream;
  I : Integer;
  L : String;
  NL: AnsiChar;
begin
  NL := #10;
  FS := TFileStream.Create(AFileName, fmCreate);
  try
    for I := 0 to FLines.Count - 1 do
    begin
      L := FLines[I];
      if Length(L) > 0 then
        FS.WriteBuffer(L[1], Length(L));
      FS.WriteBuffer(NL, 1);
    end;
  finally
    FS.Free;
  end;
end;

// この protocol が参照する他ユニットの接尾辞を集める。
function CollectDependencies(const AProto: TProtocolDef): TStringList;
var
  I, J, K: Integer;
  Own, U : String;

  procedure Consider(const AIfaceName: String);
  var
    Idx: Integer;
  begin
    if AIfaceName = '' then
      Exit;
    Idx := GIfaceToUnit.IndexOfName(AIfaceName);
    if Idx < 0 then
      Exit;
    U := GIfaceToUnit.ValueFromIndex[Idx];
    if (U <> Own) and (Result.IndexOf(U) < 0) then
      Result.Add(U);
  end;

  procedure ScanMsgs(const AMsgs: array of TMessage);
  var
    M, A: Integer;
  begin
    for M := 0 to High(AMsgs) do
      for A := 0 to High(AMsgs[M].Args) do
        Consider(AMsgs[M].Args[A].IfaceName);
  end;

begin
  Result := TStringList.Create;
  Own := AProto.UnitSuffix;
  for I := 0 to High(AProto.Interfaces) do
  begin
    ScanMsgs(AProto.Interfaces[I].Requests);
    ScanMsgs(AProto.Interfaces[I].Events);
  end;
  // 参照されていなくてもプールに現れる名前を拾う
  for J := 0 to High(AProto.PoolSlots) do
    Consider(AProto.PoolSlots[J]);
  K := 0;   // 未使用警告避け
  if K <> 0 then ;
end;

procedure EmitUnit(const AProto: TProtocolDef);
var
  E   : TEmitter;
  Deps: TStringList;
  I, J, K, NIdx: Integer;
  Iface: TInterfaceDef;
  Msg  : TMessage;
  UpIface, Params, VarArgs, Sig, Line, MethodName: String;
  HasParams: Boolean;

  function ListenerClassName(const AIfaceName: String): String;
  begin
    Result := 'T' + AIfaceName + '_listener';
  end;

begin
  E := TEmitter.Create;
  Deps := CollectDependencies(AProto);
  try
    // ---- ヘッダ
    E.Add('{');
    E.AddFmt('  PaPiMeLa.Platform.Wayland.Protocols.%s', [AProto.UnitSuffix]);
    E.Blank;
    E.Add('  自動生成ファイル。手で編集しないこと。');
    E.AddFmt('  生成元: %s.xml', [AProto.Name]);
    E.Add('  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）');
    E.Blank;
    E.Add('  Origin : generated from the Wayland protocol XML (not derived from SDL sources)');
    E.Blank;
    if AProto.Copyright <> '' then
    begin
      E.Add('  プロトコル XML の著作権表示:');
      E.Blank;
      with TStringList.Create do
      try
        Text := AProto.Copyright;
        for I := 0 to Count - 1 do
          E.Add('  ' + Strings[I]);
      finally
        Free;
      end;
      E.Blank;
    end;
    E.Add('}');
    E.AddFmt('unit PaPiMeLa.Platform.Wayland.Protocols.%s;', [AProto.UnitSuffix]);
    E.Blank;
    E.Add('{$I papimela.inc}');
    E.Add('{$packrecords c}');
    E.Blank;
    E.Add('interface');
    E.Blank;
    E.Add('uses');
    Line := '  PaPiMeLa.Platform.Wayland.Client';
    for I := 0 to Deps.Count - 1 do
      Line := Line + ',' + sLineBreak + '  PaPiMeLa.Platform.Wayland.Protocols.' + Deps[I];
    E.Add(Line + ';');
    E.Blank;

    // ---- 不透明型
    E.Add('type');
    for I := 0 to High(AProto.Interfaces) do
    begin
      // Pwl_display は手書きの Client ユニットが宣言しているので重複させない。
      if AProto.Interfaces[I].Name = 'wl_display' then
      begin
        E.Add('  // Pwl_display は PaPiMeLa.Platform.Wayland.Client の宣言を使う');
        Continue;
      end;
      E.AddFmt('  T%s_opaque = record end;', [AProto.Interfaces[I].Name]);
      E.AddFmt('  P%s = ^T%s_opaque;', [AProto.Interfaces[I].Name, AProto.Interfaces[I].Name]);
    end;
    E.Blank;

    // ---- 定数（オペコード、SINCE、列挙）
    E.Add('const');
    for I := 0 to High(AProto.Interfaces) do
    begin
      Iface := AProto.Interfaces[I];
      SetReservedFor(Iface.Requests, Iface.Events);
      UpIface := UpperCase(Iface.Name);
      E.AddFmt('  // %s (version %d)', [Iface.Name, Iface.Version]);
      for J := 0 to High(Iface.Requests) do
        E.AddFmt('  %s_%s_OPCODE = %d;', [UpIface, UpperCase(Iface.Requests[J].Name), J]);
      for J := 0 to High(Iface.Requests) do
        E.AddFmt('  %s_%s_SINCE_VERSION = %d;',
          [UpIface, UpperCase(Iface.Requests[J].Name), Iface.Requests[J].Since]);
      for J := 0 to High(Iface.Events) do
        E.AddFmt('  %s_%s_SINCE_VERSION = %d;',
          [UpIface, UpperCase(Iface.Events[J].Name), Iface.Events[J].Since]);
      for J := 0 to High(Iface.Enums) do
        for K := 0 to High(Iface.Enums[J].Entries) do
          E.AddFmt('  %s_%s_%s = %s;',
            [UpIface, UpperCase(Iface.Enums[J].Name),
             UpperCase(Iface.Enums[J].Entries[K].Name),
             ToPascalNumber(Iface.Enums[J].Entries[K].Value)]);
      E.Blank;
    end;

    // ---- wl_interface 記述子
    E.Add('var');
    for I := 0 to High(AProto.Interfaces) do
      E.AddFmt('  %s_interface: Pwl_interface = nil;', [AProto.Interfaces[I].Name]);
    E.Blank;

    // ---- リスナー
    // イベントを持つインターフェースが 1 つも無いプロトコルでは type 節を出さない
    // （空の type 節は構文エラーになる）。
    HasParams := False;
    for I := 0 to High(AProto.Interfaces) do
      if Length(AProto.Interfaces[I].Events) > 0 then
        HasParams := True;
    if HasParams then
      E.Add('type');
    for I := 0 to High(AProto.Interfaces) do
    begin
      Iface := AProto.Interfaces[I];
      SetReservedFor(Iface.Requests, Iface.Events);
      if Length(Iface.Events) = 0 then
        Continue;

      // 抽象クラス（1 イベント = 1 仮想メソッド、既定は空）
      E.AddFmt('  %s = class abstract(TObject)', [ListenerClassName(Iface.Name)]);
      E.Add('  public');
      for J := 0 to High(Iface.Events) do
      begin
        Msg := Iface.Events[J];
        MethodName := SanitizeIdent(Msg.Name);
        Params := Format('AProxy: P%s', [Iface.Name]);
        for K := 0 to High(Msg.Args) do
          Params := Params + Format('; %s: %s',
            [SanitizeArgName(Msg.Args[K].Name, Msg.Name), PascalArgType(Msg.Args[K])]);
        E.AddFmt('    procedure %s(%s); virtual;', [MethodName, Params]);
      end;
      E.Add('  end;');
      E.Blank;

      // C 側に渡すレコード
      E.AddFmt('  T%s_listener_rec = record', [Iface.Name]);
      for J := 0 to High(Iface.Events) do
      begin
        Msg := Iface.Events[J];
        Params := Format('data: Pointer; AProxy: P%s', [Iface.Name]);
        for K := 0 to High(Msg.Args) do
          Params := Params + Format('; %s: %s',
            [SanitizeArgName(Msg.Args[K].Name, Msg.Name), PascalArgType(Msg.Args[K])]);
        E.AddFmt('    %s: procedure(%s); cdecl;', [SanitizeIdent(Msg.Name), Params]);
      end;
      E.Add('  end;');
      E.Blank;
    end;

    // ---- リクエストと add_listener の宣言
    for I := 0 to High(AProto.Interfaces) do
    begin
      Iface := AProto.Interfaces[I];
      SetReservedFor(Iface.Requests, Iface.Events);
      if Length(Iface.Events) > 0 then
        E.AddFmt('function %s_add_listener_object(AProxy: P%s; AListener: %s): LongInt;',
          [Iface.Name, Iface.Name, ListenerClassName(Iface.Name)]);
      for J := 0 to High(Iface.Requests) do
      begin
        Msg := Iface.Requests[J];
        NIdx := NewIdArgIndex(Msg);
        Params := Format('AProxy: P%s', [Iface.Name]);
        for K := 0 to High(Msg.Args) do
        begin
          if K = NIdx then
          begin
            // インターフェース不定の new_id は呼び出し側が指定する
            if Msg.Args[K].IfaceName = '' then
              Params := Params + '; AInterface: Pwl_interface; AVersion: LongWord';
            Continue;
          end;
          Params := Params + Format('; %s: %s',
            [SanitizeArgName(Msg.Args[K].Name, Msg.Name), PascalArgType(Msg.Args[K])]);
        end;
        if NIdx < 0 then
          E.AddFmt('procedure %s_%s(%s);', [Iface.Name, SanitizeIdent(Msg.Name), Params])
        else if Msg.Args[NIdx].IfaceName = '' then
          E.AddFmt('function %s_%s(%s): Pwl_proxy;',
            [Iface.Name, SanitizeIdent(Msg.Name), Params])
        else
          E.AddFmt('function %s_%s(%s): P%s;',
            [Iface.Name, SanitizeIdent(Msg.Name), Params, Msg.Args[NIdx].IfaceName]);
      end;
      if Length(Iface.Requests) > 0 then
        E.Blank;
    end;

    E.Add('// wl_interface 記述子とサンク束を組む。多重呼び出し安全。');
    E.Add('// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。');
    E.Add('procedure EnsureProtocolInitialized;');
    E.Blank;

    // ================= implementation =================
    E.Add('implementation');
    E.Blank;
    if not AProto.IsCore then
    begin
      E.Add('var');
      E.AddFmt('  GTypes: array[0..%d] of Pwl_interface;', [AProto.PoolSize - 1]);
      for I := 0 to High(AProto.Interfaces) do
      begin
        Iface := AProto.Interfaces[I];
      SetReservedFor(Iface.Requests, Iface.Events);
        if Length(Iface.Requests) > 0 then
          E.AddFmt('  GReq_%s: array[0..%d] of Twl_message;',
            [Iface.Name, High(Iface.Requests)]);
        if Length(Iface.Events) > 0 then
          E.AddFmt('  GEvt_%s: array[0..%d] of Twl_message;',
            [Iface.Name, High(Iface.Events)]);
        E.AddFmt('  GIface_%s: Twl_interface;', [Iface.Name]);
      end;
      E.Blank;
    end;

    E.Add('var');
    E.Add('  GInitialized: Boolean = False;');
    for I := 0 to High(AProto.Interfaces) do
      if Length(AProto.Interfaces[I].Events) > 0 then
        E.AddFmt('  GThunks_%s: T%s_listener_rec;',
          [AProto.Interfaces[I].Name, AProto.Interfaces[I].Name]);
    E.Blank;

    // ---- 抽象クラスの既定実装（空）
    for I := 0 to High(AProto.Interfaces) do
    begin
      Iface := AProto.Interfaces[I];
      SetReservedFor(Iface.Requests, Iface.Events);
      for J := 0 to High(Iface.Events) do
      begin
        Msg := Iface.Events[J];
        Params := Format('AProxy: P%s', [Iface.Name]);
        for K := 0 to High(Msg.Args) do
          Params := Params + Format('; %s: %s',
            [SanitizeArgName(Msg.Args[K].Name, Msg.Name), PascalArgType(Msg.Args[K])]);
        E.AddFmt('procedure %s.%s(%s);',
          [ListenerClassName(Iface.Name), SanitizeIdent(Msg.Name), Params]);
        E.Add('begin');
        E.Add('end;');
        E.Blank;
      end;
    end;

    // ---- サンク（C → Pascal）
    for I := 0 to High(AProto.Interfaces) do
    begin
      Iface := AProto.Interfaces[I];
      SetReservedFor(Iface.Requests, Iface.Events);
      for J := 0 to High(Iface.Events) do
      begin
        Msg := Iface.Events[J];
        Params := Format('data: Pointer; AProxy: P%s', [Iface.Name]);
        VarArgs := 'AProxy';
        for K := 0 to High(Msg.Args) do
        begin
          Params := Params + Format('; %s: %s',
            [SanitizeArgName(Msg.Args[K].Name, Msg.Name), PascalArgType(Msg.Args[K])]);
          VarArgs := VarArgs + ', ' + SanitizeArgName(Msg.Args[K].Name, Msg.Name);
        end;
        E.AddFmt('procedure Thunk_%s_%s(%s); cdecl;',
          [Iface.Name, SanitizeIdent(Msg.Name), Params]);
        E.Add('begin');
        E.AddFmt('  if data <> nil then', []);
        E.AddFmt('    %s(data).%s(%s);',
          [ListenerClassName(Iface.Name), SanitizeIdent(Msg.Name), VarArgs]);
        E.Add('end;');
        E.Blank;
      end;
    end;

    // ---- add_listener_object
    for I := 0 to High(AProto.Interfaces) do
    begin
      Iface := AProto.Interfaces[I];
      SetReservedFor(Iface.Requests, Iface.Events);
      if Length(Iface.Events) = 0 then
        Continue;
      E.AddFmt('function %s_add_listener_object(AProxy: P%s; AListener: %s): LongInt;',
        [Iface.Name, Iface.Name, ListenerClassName(Iface.Name)]);
      E.Add('begin');
      E.Add('  EnsureProtocolInitialized;');
      E.AddFmt('  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_%s, AListener);',
        [Iface.Name]);
      E.Add('end;');
      E.Blank;
    end;

    // ---- リクエストの実装
    for I := 0 to High(AProto.Interfaces) do
    begin
      Iface := AProto.Interfaces[I];
      SetReservedFor(Iface.Requests, Iface.Events);
      UpIface := UpperCase(Iface.Name);
      for J := 0 to High(Iface.Requests) do
      begin
        Msg := Iface.Requests[J];
        NIdx := NewIdArgIndex(Msg);
        Params := Format('AProxy: P%s', [Iface.Name]);
        VarArgs := '';
        for K := 0 to High(Msg.Args) do
        begin
          if K = NIdx then
          begin
            if Msg.Args[K].IfaceName = '' then
            begin
              Params := Params + '; AInterface: Pwl_interface; AVersion: LongWord';
              // 不定 new_id は「インターフェース名(s) + バージョン(u) + プレースホルダ(n)」
              VarArgs := VarArgs + ', AInterface^.name, AVersion, Pointer(nil)';
            end
            else
              VarArgs := VarArgs + ', Pointer(nil)';
            Continue;
          end;
          Params := Params + Format('; %s: %s',
            [SanitizeArgName(Msg.Args[K].Name, Msg.Name), PascalArgType(Msg.Args[K])]);
          VarArgs := VarArgs + ', ' + SanitizeArgName(Msg.Args[K].Name, Msg.Name);
        end;

        if NIdx < 0 then
          E.AddFmt('procedure %s_%s(%s);', [Iface.Name, SanitizeIdent(Msg.Name), Params])
        else if Msg.Args[NIdx].IfaceName = '' then
          E.AddFmt('function %s_%s(%s): Pwl_proxy;',
            [Iface.Name, SanitizeIdent(Msg.Name), Params])
        else
          E.AddFmt('function %s_%s(%s): P%s;',
            [Iface.Name, SanitizeIdent(Msg.Name), Params, Msg.Args[NIdx].IfaceName]);
        E.Add('begin');
        E.Add('  EnsureProtocolInitialized;');

        // marshal の第 3・第 4 引数
        if NIdx < 0 then
          Sig := 'nil, wl_proxy_get_version(Pwl_proxy(AProxy))'
        else if Msg.Args[NIdx].IfaceName = '' then
          Sig := 'AInterface, AVersion'
        else
          Sig := Format('%s_interface, wl_proxy_get_version(Pwl_proxy(AProxy))',
            [Msg.Args[NIdx].IfaceName]);

        if Msg.IsDestructor then
          Line := 'WL_MARSHAL_FLAG_DESTROY'
        else
          Line := '0';

        if NIdx < 0 then
          E.AddFmt('  wl_proxy_marshal_flags(Pwl_proxy(AProxy), %s_%s, %s, %s%s);',
            [UpIface, UpperCase(Msg.Name) + '_OPCODE', Sig, Line, VarArgs])
        else if Msg.Args[NIdx].IfaceName = '' then
          E.AddFmt('  Result := wl_proxy_marshal_flags(Pwl_proxy(AProxy), %s_%s, %s, %s%s);',
            [UpIface, UpperCase(Msg.Name) + '_OPCODE', Sig, Line, VarArgs])
        else
          E.AddFmt('  Result := P%s(wl_proxy_marshal_flags(Pwl_proxy(AProxy), %s_%s, %s, %s%s));',
            [Msg.Args[NIdx].IfaceName, UpIface, UpperCase(Msg.Name) + '_OPCODE', Sig, Line, VarArgs]);
        E.Add('end;');
        E.Blank;
      end;
    end;

    // ---- EnsureProtocolInitialized
    E.Add('procedure EnsureProtocolInitialized;');
    E.Add('begin');
    E.Add('  if GInitialized then');
    E.Add('    Exit;');
    E.Add('  GInitialized := True;');
    for I := 0 to Deps.Count - 1 do
      E.AddFmt('  PaPiMeLa.Platform.Wayland.Protocols.%s.EnsureProtocolInitialized;', [Deps[I]]);
    E.Blank;
    if AProto.IsCore then
    begin
      E.Add('  // コアプロトコルの記述子は libwayland-client が公開している。');
      for I := 0 to High(AProto.Interfaces) do
        E.AddFmt('  %s_interface := PMLWaylandResolve(''%s_interface'');',
          [AProto.Interfaces[I].Name, AProto.Interfaces[I].Name]);
    end
    else
    begin
      E.Add('  FillChar(GTypes, SizeOf(GTypes), 0);');
      for I := 0 to High(AProto.PoolSlots) do
        if AProto.PoolSlots[I] <> '' then
          E.AddFmt('  GTypes[%d] := %s_interface;', [I, AProto.PoolSlots[I]]);
      E.Blank;
      for I := 0 to High(AProto.Interfaces) do
      begin
        Iface := AProto.Interfaces[I];
      SetReservedFor(Iface.Requests, Iface.Events);
        for J := 0 to High(Iface.Requests) do
        begin
          Msg := Iface.Requests[J];
          E.AddFmt('  GReq_%s[%d].name := ''%s'';', [Iface.Name, J, Msg.Name]);
          E.AddFmt('  GReq_%s[%d].signature := ''%s'';', [Iface.Name, J, Msg.Signature]);
          E.AddFmt('  GReq_%s[%d].types := @GTypes[%d];', [Iface.Name, J, Msg.TypesOffset]);
        end;
        for J := 0 to High(Iface.Events) do
        begin
          Msg := Iface.Events[J];
          E.AddFmt('  GEvt_%s[%d].name := ''%s'';', [Iface.Name, J, Msg.Name]);
          E.AddFmt('  GEvt_%s[%d].signature := ''%s'';', [Iface.Name, J, Msg.Signature]);
          E.AddFmt('  GEvt_%s[%d].types := @GTypes[%d];', [Iface.Name, J, Msg.TypesOffset]);
        end;
        E.AddFmt('  GIface_%s.name := ''%s'';', [Iface.Name, Iface.Name]);
        E.AddFmt('  GIface_%s.version := %d;', [Iface.Name, Iface.Version]);
        E.AddFmt('  GIface_%s.method_count := %d;', [Iface.Name, Length(Iface.Requests)]);
        if Length(Iface.Requests) > 0 then
          E.AddFmt('  GIface_%s.methods := @GReq_%s[0];', [Iface.Name, Iface.Name])
        else
          E.AddFmt('  GIface_%s.methods := nil;', [Iface.Name]);
        E.AddFmt('  GIface_%s.event_count := %d;', [Iface.Name, Length(Iface.Events)]);
        if Length(Iface.Events) > 0 then
          E.AddFmt('  GIface_%s.events := @GEvt_%s[0];', [Iface.Name, Iface.Name])
        else
          E.AddFmt('  GIface_%s.events := nil;', [Iface.Name]);
        E.AddFmt('  %s_interface := @GIface_%s;', [Iface.Name, Iface.Name]);
        E.Blank;
      end;
    end;

    // サンク束
    for I := 0 to High(AProto.Interfaces) do
    begin
      Iface := AProto.Interfaces[I];
      SetReservedFor(Iface.Requests, Iface.Events);
      for J := 0 to High(Iface.Events) do
        E.AddFmt('  GThunks_%s.%s := @Thunk_%s_%s;',
          [Iface.Name, SanitizeIdent(Iface.Events[J].Name),
           Iface.Name, SanitizeIdent(Iface.Events[J].Name)]);
    end;
    E.Add('end;');
    E.Blank;
    E.Add('end.');

    HasParams := True;   // 未使用変数警告の回避
    if not HasParams then ;

    E.SaveTo(IncludeTrailingPathDelimiter(GOutDir)
      + 'PaPiMeLa.Platform.Wayland.Protocols.' + AProto.UnitSuffix + '.pas');
  finally
    Deps.Free;
    E.Free;
  end;
end;

{ ---- main ---- }

var
  I, J: Integer;
begin
  if ParamCount < 2 then
  begin
    WriteLn('使い方: wlscan-pas <出力ディレクトリ> <protocol.xml> [...]');
    WriteLn;
    WriteLn('  複数の XML を 1 回で渡すと、インターフェースがどのユニットに属するかを');
    WriteLn('  解決して uses 節を生成する。wayland.xml を必ず含めること。');
    Halt(2);
  end;

  GOutDir := ParamStr(1);
  if not DirectoryExists(GOutDir) then
    ForceDirectories(GOutDir);

  GIfaceToUnit := TStringList.Create;
  try
    SetLength(GProtocols, ParamCount - 1);
    for I := 2 to ParamCount do
    begin
      ParseProtocol(ParamStr(I), GProtocols[I - 2]);
      ComputePool(GProtocols[I - 2]);
      for J := 0 to High(GProtocols[I - 2].Interfaces) do
        GIfaceToUnit.Values[GProtocols[I - 2].Interfaces[J].Name] :=
          GProtocols[I - 2].UnitSuffix;
    end;

    for I := 0 to High(GProtocols) do
    begin
      EmitUnit(GProtocols[I]);
      WriteLn(Format('  %-34s → %s.pas （interface %d、%s）',
        [ExtractFileName(ParamStr(I + 2)),
         'PaPiMeLa.Platform.Wayland.Protocols.' + GProtocols[I].UnitSuffix,
         Length(GProtocols[I].Interfaces),
         specialize IfThen<String>(GProtocols[I].IsCore,
           'libwayland から記述子を dlsym', '記述子を自前で構築')]));
    end;
    WriteLn(Format('%d ファイルを生成した', [Length(GProtocols)]));
  finally
    GIfaceToUnit.Free;
  end;
end.
