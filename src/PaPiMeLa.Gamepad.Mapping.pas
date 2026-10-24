{
  PaPiMeLa.Gamepad.Mapping — ゲームパッドのマッピングの文字列と DB

  Origin : ported from SDL (src/joystick/SDL_gamepad.c, src/joystick/SDL_gamepad_db.h)
           Scope: マッピング文字列の読み書き（GUID・名前・割り当ての切り出し、crc: / type: / face: / platform: /
           hint: 欄、位置どおりの A/B/X/Y への読み替え）、割り当ての解釈（SDL_PrivateParseGamepadElement。
           半軸・反転・ハット）、DB（優先度、CRC とバージョンでの一致、更新時の上書きの規則、既定の
           マッピング）、外部 DB（gamecontrollerdb.txt）の読み込み、バックエンドの自動マッピングの文字列、
           種類・軸・ボタンの名前の表、顔のボタンの並びと表示名、内蔵の DB（Linux の分）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #62（TPMLGamepadMappingDB）、§12 の 16

  WHAT:
    マッピングの文字列は「GUID,名前,a:b0,b:b1,...,crc:xxxx,platform:Linux,hint:...,type:...,face:...」。
    DB は文字列を GUID ごとに 1 件持ち、追加のたびに優先度（内蔵 < API < 利用者）の高いほうを残す。
    開いたゲームパッドや接続中の機器との結び付け（IsGamepad、Added/Removed/Remapped）は PaPiMeLa.Gamepad。

  RESOLVED:
    - 対応する端末の分だけを持つ。内蔵の表は Linux の分（tools/gengamepaddb.bb）。XInput / WGI /
      DirectInput / macOS / Android / HIDAPI / RAWINPUT の自動マッピングと、その GUID の読み替えは無い
    - 外部 DB の行は platform: 欄が無いと読まない（SDL と同じ）。platform の比較は SDL の
      SDL_strncasecmp と同じで、欄の長さの分だけ頭から比べる

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Gamepad.Mapping;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Properties,
  PaPiMeLa.Joystick.GUID,
  PaPiMeLa.Joystick.Backend;

type
  // ゲームパッドの種類（SDL_GamepadType。値は SDL と同じ）。
  TPMLGamepadType = (Unknown, Standard, Xbox360, XboxOne, PS3, PS4, PS5, SwitchPro,
    JoyConLeft, JoyConRight, JoyConPair, GameCube, Steam);

  // 顔のボタンの並び（SDL_GamepadFaceStyle）。
  TPMLGamepadFaceStyle = (Unknown, ABXY, AXBY, BAYX, Sony);

  // 顔のボタンの表示名（SDL_GamepadButtonLabel）。
  TPMLGamepadButtonLabel = (Unknown, A, B, X, Y, Cross, Circle, Square, Triangle);

  // 割り当ての入力と出力の種類（SDL_GamepadBindingType）。
  TPMLGamepadBindType = (None, Button, Axis, Hat);

  { 割り当て 1 つ（SDL_GamepadBinding）。入力が軸のときは InputIndex が軸の番号、InputMin..InputMax が
    入力の範囲（反転は Min > Max）、ハットのときは InputIndex がハット、InputMask が方向、ボタンのときは
    InputIndex がボタンの番号。出力がボタンなら OutputButton、軸なら OutputAxis と OutputMin..OutputMax。 }
  TPMLGamepadBinding = record
    InputType   : TPMLGamepadBindType;
    InputIndex  : Integer;
    InputMin    : Integer;
    InputMax    : Integer;
    InputMask   : Integer;
    OutputType  : TPMLGamepadBindType;
    OutputButton: TPMLGamepadButton;
    OutputAxis  : TPMLGamepadAxis;
    OutputMin   : Integer;
    OutputMax   : Integer;
  end;
  TPMLGamepadBindings = array of TPMLGamepadBinding;

  // マッピングの優先度（SDL_GamepadMappingPriority の DEFAULT / API / USER）。
  TPMLGamepadMappingPriority = (Builtin, API, User);

  // DB の 1 件（GamepadMapping_t）。GUID の CRC は常に 0（CRC は Mapping の crc: 欄に持つ）。
  TPMLGamepadMappingEntry = class
  public
    GUID    : TPMLGUID;
    Name    : String;
    Mapping : String;
    Priority: TPMLGamepadMappingPriority;
  end;

  { マッピングの変更の追跡（MappingChangeTracker）。DB が追加・更新の前後で呼ぶ。入れ子にできる。
    実装は PaPiMeLa.Gamepad（追跡の前後の機器とマッピングを比べて Added / Removed / Remapped を出す）。 }
  TPMLGamepadMappingTracker = class abstract
  public
    procedure Push; virtual; abstract;
    procedure Changed(AEntry: TPMLGamepadMappingEntry); virtual; abstract;
    procedure Pop; virtual; abstract;
  end;

  // ベンダーとプロダクトから、GameCube のアダプタか（SDL_IsJoystickGameCube）。
  TPMLIsGameCubeFunc = function(AVendor, AProduct: Word): Boolean of object;

  TPMLGamepadMappingDB = class
  strict private
    FHints      : TPMLHints;
    FIsGameCube : TPMLIsGameCubeFunc;
    FEntries    : array of TPMLGamepadMappingEntry;
    FRetired    : array of TPMLGamepadMappingEntry;
    FDefault    : TPMLGamepadMappingEntry;
    FXInput     : TPMLGamepadMappingEntry;
    FTracker    : TPMLGamepadMappingTracker;
    FLastError  : String;
    function  MatchForGUID(const AGUID: TPMLGUID; AMatchVersion, AExactCRC: Boolean): TPMLGamepadMappingEntry;
    function  GetCount: Integer;
    function  GetEntry(AIndex: Integer): TPMLGamepadMappingEntry;
    procedure TrackPush;
    procedure TrackChanged(AEntry: TPMLGamepadMappingEntry);
    procedure TrackPop;
    procedure LoadHintMappings;
  public
    { AHints は nil でもよい。AIsGameCube は nil なら GameCube は無い。 }
    constructor Create(AHints: TPMLHints; AIsGameCube: TPMLIsGameCubeFunc);
    destructor Destroy; override;

    { 内蔵の表・ヒントの設定ファイル・ヒントの設定を読む（SDL_InitGamepadMappings）。 }
    procedure LoadInitial;
    { 全部捨てる（SDL_QuitGamepadMappings）。捨てた件は、追跡が終わっても指せるよう次の Clear か破棄まで残す。 }
    procedure Clear;

    { 優先度 API で足す（SDL_AddGamepadMapping）。新しければ 1、既にあって更新は 0、失敗は -1。
      ヒントで効かない行は 0。失敗の理由は LastError。 }
    function  AddMapping(const AMapping: String): Integer;
    { 優先度を指定して足す（SDL_PrivateAddGamepadMapping）。 }
    function  AddMappingWithPriority(const AMapping: String; APriority: TPMLGamepadMappingPriority): Integer;
    { GUID を指定して足す（SDL_PrivateAddMappingForGUID）。AMapping は「GUID,名前,割り当て」の形で、
      GUID の欄は読み飛ばす。AExisting は同じ GUID が既にあったか。失敗は nil。 }
    function  AddForGUID(AGUID: TPMLGUID; const AMapping: String; out AExisting: Boolean;
      APriority: TPMLGamepadMappingPriority): TPMLGamepadMappingEntry;
    { gamecontrollerdb.txt 形式の文章を読む（SDL_AddGamepadMappingsFromIO）。platform: の合う行の
      うち、新しく足せた件数を返す。 }
    function  AddFromText(const AText: String): Integer;
    // ファイルから読む（SDL_AddGamepadMappingsFromFile）。開けなければ -1。
    function  AddFromFile(const APath: String): Integer;

    { GUID に合うマッピング（SDL_PrivateGetGamepadMappingForGUID）。AAdding が True なら、バージョンと CRC が
      そろったものだけ。無ければ nil。XInput / HIDAPI / RAWINPUT / WGI の自動の作成は無い。 }
    function  FindForGUID(const AGUID: TPMLGUID; AAdding: Boolean): TPMLGamepadMappingEntry;

    { 「GUID,名前,割り当て,platform:Linux,」の形の文字列（CreateMappingString）。 }
    function  FormatMapping(AEntry: TPMLGamepadMappingEntry; const AGUID: TPMLGUID): String;
    // 全部の文字列（SDL_GetGamepadMappings。GUID が 0 のものは除く）。
    function  AllMappings: TStringArray;

    property Count: Integer read GetCount;
    property Entries[AIndex: Integer]: TPMLGamepadMappingEntry read GetEntry;
    property DefaultMapping: TPMLGamepadMappingEntry read FDefault;
    property XInputMapping: TPMLGamepadMappingEntry read FXInput;
    property Tracker: TPMLGamepadMappingTracker read FTracker write FTracker;
    property LastError: String read FLastError;
  end;

const
  // 内蔵のマッピングの端末の名前（SDL_GetPlatform）。
  PML_GAMEPAD_PLATFORM = 'Linux';
  // 最小の「しばらく押されたままのガイドボタン」の長さ（SDL_MINIMUM_GUIDE_BUTTON_DELAY_MS）。
  PML_MINIMUM_GUIDE_BUTTON_DELAY_MS = 250;

{ ---- 名前の表 ---- }
function  PMLGamepadTypeFromString(const AText: String): TPMLGamepadType;
function  PMLGamepadTypeToString(AType: TPMLGamepadType): String;       // Unknown は ''
function  PMLGamepadAxisFromString(const AText: String; out AAxis: TPMLGamepadAxis): Boolean;
function  PMLGamepadAxisToString(AAxis: TPMLGamepadAxis): String;
function  PMLGamepadButtonFromString(const AText: String; out AButton: TPMLGamepadButton): Boolean;
function  PMLGamepadButtonToString(AButton: TPMLGamepadButton): String;

{ ---- 顔のボタン ---- }
function  PMLGamepadFaceStyleFromString(const AText: String): TPMLGamepadFaceStyle;
function  PMLGamepadFaceStyleForType(AType: TPMLGamepadType): TPMLGamepadFaceStyle;
function  PMLGamepadButtonLabelForFaceStyle(AStyle: TPMLGamepadFaceStyle; AButton: TPMLGamepadButton): TPMLGamepadButtonLabel;
function  PMLGamepadButtonLabelForType(AType: TPMLGamepadType; AButton: TPMLGamepadButton): TPMLGamepadButtonLabel;

{ ---- マッピングの文字列 ---- }
{ 割り当ての部分（3 つ目のコンマの後ろ）を読んで、割り当てを AOutput へ足す（SDL_PrivateParseGamepadConfigString）。
  欄の名前が長すぎると False（それまでに読んだ分は残る）。読めない欄は黙って飛ばす。 }
function  PMLParseGamepadBindings(const AMapping: String; var ABindings: TPMLGamepadBindings): Boolean;
{ マッピングの type: 欄（SDL_GAMEPAD_TYPE_FIELD）。ANeedComma が True だと、後ろにコンマが無い欄は無いものとする
  （SDL_GetGamepadTypeForID）。False は欄の終わりまで（SDL_UpdateGamepadType）。 }
function  PMLMappingTypeField(const AMapping: String; ANeedComma: Boolean): TPMLGamepadType;
{ 顔のボタンの並び（SDL_UpdateGamepadFaceStyle）。face: 欄、無ければヒントの印、無ければ種類から。 }
function  PMLMappingFaceStyle(const AMapping: String; AType: TPMLGamepadType): TPMLGamepadFaceStyle;
// 文字列から GUID・名前・割り当てを切り出す。コンマが足りなければ False。
function  PMLMappingStringGUID(const AText: String; out AGUID: String): Boolean;
function  PMLMappingStringName(const AText: String; out AName: String): Boolean;
function  PMLMappingStringBody(const AText: String; out ABody: String): Boolean;
{ バックエンドが言う自動のマッピングを「none,名前,a:b0,...,」の文字列にする
  （SDL_PrivateGenerateAutomaticGamepadMapping の前半）。 }
function  PMLAutomaticMappingString(const AName: String; const ARaw: TPMLGamepadMapping): String;

implementation

const
  TypeNames: array[TPMLGamepadType] of String = (
    'unknown', 'standard', 'xbox360', 'xboxone', 'ps3', 'ps4', 'ps5', 'switchpro',
    'joyconleft', 'joyconright', 'joyconpair', 'gamecube', 'steam');
  AxisNames: array[TPMLGamepadAxis] of String = (
    'leftx', 'lefty', 'rightx', 'righty', 'lefttrigger', 'righttrigger');
  ButtonNames: array[TPMLGamepadButton] of String = (
    'a', 'b', 'x', 'y', 'back', 'guide', 'start', 'leftstick', 'rightstick',
    'leftshoulder', 'rightshoulder', 'dpup', 'dpdown', 'dpleft', 'dpright', 'misc1',
    'paddle1', 'paddle2', 'paddle3', 'paddle4', 'touchpad', 'misc2', 'misc3', 'misc4', 'misc5', 'misc6');

  CRCField      = 'crc:';
  TypeField     = 'type:';
  FaceField     = 'face:';
  PlatformField = 'platform:';
  HintField     = 'hint:';
  GamecubeLabelsHint = 'SDL_GAMECONTROLLER_USE_GAMECUBE_LABELS';
  ButtonLabelsHint   = 'SDL_GAMECONTROLLER_USE_BUTTON_LABELS';

{$I generated/gamepad_db_linux.inc}

{ ---- C の関数の写し ---- }

function IsSpaceC(C: Char): Boolean;
begin
  Result := C in [#9..#13, ' '];
end;

function IsDigitC(C: Char): Boolean;
begin
  Result := C in ['0'..'9'];
end;

// SDL_atoi（SDL_strtol の基数 10。long の飽和のあと int へ切る）。
function AtoiAt(const S: String; AStart: Integer): Integer;
var
  I: Integer;
  Neg: Boolean;
  V: Int64;
begin
  I := AStart;
  while (I <= Length(S)) and IsSpaceC(S[I]) do
    Inc(I);
  Neg := False;
  if (I <= Length(S)) and (S[I] in ['+', '-']) then
  begin
    Neg := S[I] = '-';
    Inc(I);
  end;
  V := 0;
  while (I <= Length(S)) and IsDigitC(S[I]) do
  begin
    if V > (High(Int64) - 9) div 10 then
      V := High(Int64)
    else
      V := V * 10 + (Ord(S[I]) - 48);
    Inc(I);
  end;
  if Neg then
    V := -V;
  Result := LongInt(Cardinal(V and $FFFFFFFF));
end;

// SDL_strtol(…, 16) の先頭の数。16 ビットへ切る。
function StrToLongHex16(const S: String; AStart: Integer): Word;
var
  I, D: Integer;
  Neg: Boolean;
  V: QWord;
begin
  I := AStart;
  while (I <= Length(S)) and IsSpaceC(S[I]) do
    Inc(I);
  Neg := False;
  if (I <= Length(S)) and (S[I] in ['+', '-']) then
  begin
    Neg := S[I] = '-';
    Inc(I);
  end;
  if (I + 2 <= Length(S)) and (S[I] = '0') and (S[I + 1] in ['x', 'X'])
  and (S[I + 2] in ['0'..'9', 'a'..'f', 'A'..'F']) then
    Inc(I, 2);
  V := 0;
  while I <= Length(S) do
  begin
    case S[I] of
      '0'..'9': D := Ord(S[I]) - 48;
      'a'..'f': D := Ord(S[I]) - 87;
      'A'..'F': D := Ord(S[I]) - 55;
    else
      Break;
    end;
    if V > (High(QWord) - D) div 16 then
      V := High(QWord)
    else
      V := V * 16 + QWord(D);
    Inc(I);
  end;
  if Neg then
    V := QWord(-Int64(V));
  Result := Word(V and $FFFF);
end;

// 行を LF で分ける（最後に LF が無くてもよい）。
function SplitLF(const AText: String): TStringArray;
var
  Start, I, N: Integer;
begin
  Result := nil;
  N := 0;
  Start := 1;
  for I := 1 to Length(AText) + 1 do
    if (I > Length(AText)) or (AText[I] = #10) then
    begin
      if (I <= Length(AText)) or (I > Start) then
      begin
        SetLength(Result, N + 1);
        Result[N] := Copy(AText, Start, I - Start);
        Inc(N);
      end;
      Start := I + 1;
    end;
end;

{ ---- 名前の表 ---- }

function PMLGamepadTypeFromString(const AText: String): TPMLGamepadType;
var
  S: String;
  T: TPMLGamepadType;
begin
  Result := TPMLGamepadType.Unknown;
  S := AText;
  if S = '' then
    Exit;
  if S[1] in ['+', '-'] then
    Delete(S, 1, 1);
  for T := Low(TPMLGamepadType) to High(TPMLGamepadType) do
    if SameText(S, TypeNames[T]) then
      Exit(T);
end;

function PMLGamepadTypeToString(AType: TPMLGamepadType): String;
begin
  if AType = TPMLGamepadType.Unknown then
    Result := ''
  else
    Result := TypeNames[AType];
end;

function PMLGamepadAxisFromString(const AText: String; out AAxis: TPMLGamepadAxis): Boolean;
var
  S: String;
  A: TPMLGamepadAxis;
begin
  Result := False;
  AAxis := TPMLGamepadAxis.LeftX;
  S := AText;
  if S = '' then
    Exit;
  if S[1] in ['+', '-'] then
    Delete(S, 1, 1);
  for A := Low(TPMLGamepadAxis) to High(TPMLGamepadAxis) do
    if SameText(S, AxisNames[A]) then
    begin
      AAxis := A;
      Exit(True);
    end;
end;

function PMLGamepadAxisToString(AAxis: TPMLGamepadAxis): String;
begin
  Result := AxisNames[AAxis];
end;

function PMLGamepadButtonFromString(const AText: String; out AButton: TPMLGamepadButton): Boolean;
var
  B: TPMLGamepadButton;
begin
  Result := False;
  AButton := TPMLGamepadButton.South;
  if AText = '' then
    Exit;
  for B := Low(TPMLGamepadButton) to High(TPMLGamepadButton) do
    if SameText(AText, ButtonNames[B]) then
    begin
      AButton := B;
      Exit(True);
    end;
end;

function PMLGamepadButtonToString(AButton: TPMLGamepadButton): String;
begin
  Result := ButtonNames[AButton];
end;

{ 顔のボタンを位置どおりに入れ替えて読む（SDL_PrivateGetGamepadButtonFromString の AXBY / BAXY）。 }
function ButtonFromStringSwapped(const AText: String; AAxby, ABaxy: Boolean;
  out AButton: TPMLGamepadButton): Boolean;
begin
  Result := PMLGamepadButtonFromString(AText, AButton);
  if not Result then
    Exit;
  if AAxby then
    case AButton of
      TPMLGamepadButton.East: AButton := TPMLGamepadButton.West;
      TPMLGamepadButton.West: AButton := TPMLGamepadButton.East;
    end
  else if ABaxy then
    case AButton of
      TPMLGamepadButton.South: AButton := TPMLGamepadButton.East;
      TPMLGamepadButton.East : AButton := TPMLGamepadButton.South;
      TPMLGamepadButton.West : AButton := TPMLGamepadButton.North;
      TPMLGamepadButton.North: AButton := TPMLGamepadButton.West;
    end;
end;

{ ---- 顔のボタン ---- }

function PMLGamepadFaceStyleFromString(const AText: String): TPMLGamepadFaceStyle;
begin
  if AText = 'abxy' then Result := TPMLGamepadFaceStyle.ABXY
  else if AText = 'axby' then Result := TPMLGamepadFaceStyle.AXBY
  else if AText = 'bayx' then Result := TPMLGamepadFaceStyle.BAYX
  else if AText = 'sony' then Result := TPMLGamepadFaceStyle.Sony
  else Result := TPMLGamepadFaceStyle.Unknown;
end;

function PMLGamepadFaceStyleForType(AType: TPMLGamepadType): TPMLGamepadFaceStyle;
begin
  case AType of
    TPMLGamepadType.PS3, TPMLGamepadType.PS4, TPMLGamepadType.PS5:
      Result := TPMLGamepadFaceStyle.Sony;
    TPMLGamepadType.SwitchPro, TPMLGamepadType.JoyConLeft, TPMLGamepadType.JoyConRight,
    TPMLGamepadType.JoyConPair:
      Result := TPMLGamepadFaceStyle.BAYX;
    TPMLGamepadType.GameCube:
      Result := TPMLGamepadFaceStyle.AXBY;
  else
    Result := TPMLGamepadFaceStyle.ABXY;
  end;
end;

function PMLGamepadButtonLabelForFaceStyle(AStyle: TPMLGamepadFaceStyle;
  AButton: TPMLGamepadButton): TPMLGamepadButtonLabel;
const
  // [並び, 南, 東, 西, 北]
  Labels: array[TPMLGamepadFaceStyle, 0..3] of TPMLGamepadButtonLabel = (
    (TPMLGamepadButtonLabel.Unknown, TPMLGamepadButtonLabel.Unknown, TPMLGamepadButtonLabel.Unknown, TPMLGamepadButtonLabel.Unknown),
    (TPMLGamepadButtonLabel.A, TPMLGamepadButtonLabel.B, TPMLGamepadButtonLabel.X, TPMLGamepadButtonLabel.Y),
    (TPMLGamepadButtonLabel.A, TPMLGamepadButtonLabel.X, TPMLGamepadButtonLabel.B, TPMLGamepadButtonLabel.Y),
    (TPMLGamepadButtonLabel.B, TPMLGamepadButtonLabel.A, TPMLGamepadButtonLabel.Y, TPMLGamepadButtonLabel.X),
    (TPMLGamepadButtonLabel.Cross, TPMLGamepadButtonLabel.Circle, TPMLGamepadButtonLabel.Square, TPMLGamepadButtonLabel.Triangle));
begin
  case AButton of
    TPMLGamepadButton.South: Result := Labels[AStyle, 0];
    TPMLGamepadButton.East : Result := Labels[AStyle, 1];
    TPMLGamepadButton.West : Result := Labels[AStyle, 2];
    TPMLGamepadButton.North: Result := Labels[AStyle, 3];
  else
    Result := TPMLGamepadButtonLabel.Unknown;
  end;
end;

function PMLGamepadButtonLabelForType(AType: TPMLGamepadType; AButton: TPMLGamepadButton): TPMLGamepadButtonLabel;
begin
  Result := PMLGamepadButtonLabelForFaceStyle(PMLGamepadFaceStyleForType(AType), AButton);
end;

{ ---- マッピングの文字列 ---- }

function PMLMappingStringGUID(const AText: String; out AGUID: String): Boolean;
var
  P: Integer;
begin
  P := Pos(',', AText);
  Result := P > 0;
  if Result then
    AGUID := Copy(AText, 1, P - 1)
  else
    AGUID := '';
end;

function PMLMappingStringName(const AText: String; out AName: String): Boolean;
var
  P1, P2: Integer;
begin
  AName := '';
  P1 := Pos(',', AText);
  if P1 = 0 then
    Exit(False);
  P2 := Pos(',', Copy(AText, P1 + 1, MaxInt));
  if P2 = 0 then
    Exit(False);
  AName := Copy(AText, P1 + 1, P2 - 1);
  Result := True;
end;

function PMLMappingStringBody(const AText: String; out ABody: String): Boolean;
var
  P1, P2, P: Integer;
begin
  ABody := '';
  P1 := Pos(',', AText);
  if P1 = 0 then
    Exit(False);
  P2 := Pos(',', Copy(AText, P1 + 1, MaxInt));
  if P2 = 0 then
    Exit(False);
  P := P1 + P2;                // 2 つ目のコンマの位置
  // 空白を飛ばす
  while (P + 1 <= Length(AText)) and IsSpaceC(AText[P + 1]) do
    Inc(P);
  ABody := Copy(AText, P + 1, MaxInt);
  P := Length(ABody);
  while (P > 0) and IsSpaceC(ABody[P]) do
    Dec(P);
  SetLength(ABody, P);
  Result := True;
end;

{ 欄 AField（'type:' など）の値。後ろのコンマまで。コンマが無ければ、ANeedComma が False のとき最後まで。 }
function FieldValue(const AMapping, AField: String; ANeedComma: Boolean; out AValue: String): Boolean;
var
  P, C: Integer;
begin
  AValue := '';
  P := Pos(AField, AMapping);
  if P = 0 then
    Exit(False);
  P := P + Length(AField);
  C := Pos(',', Copy(AMapping, P, MaxInt));
  if C > 0 then
    AValue := Copy(AMapping, P, C - 1)
  else if ANeedComma then
    Exit(False)
  else
    AValue := Copy(AMapping, P, MaxInt);
  Result := True;
end;

function PMLMappingTypeField(const AMapping: String; ANeedComma: Boolean): TPMLGamepadType;
var
  V: String;
begin
  if FieldValue(AMapping, TypeField, ANeedComma, V) then
    Result := PMLGamepadTypeFromString(V)
  else
    Result := TPMLGamepadType.Unknown;
end;

function PMLMappingFaceStyle(const AMapping: String; AType: TPMLGamepadType): TPMLGamepadFaceStyle;
var
  V: String;
begin
  Result := TPMLGamepadFaceStyle.Unknown;
  if FieldValue(AMapping, FaceField, False, V) then
    Result := PMLGamepadFaceStyleFromString(V);
  if (Result = TPMLGamepadFaceStyle.Unknown) and (Pos(GamecubeLabelsHint, AMapping) > 0) then
    Result := TPMLGamepadFaceStyle.AXBY;
  if (Result = TPMLGamepadFaceStyle.Unknown) and (Pos(ButtonLabelsHint, AMapping) > 0) then
    Result := TPMLGamepadFaceStyle.BAYX;
  if Result = TPMLGamepadFaceStyle.Unknown then
    Result := PMLGamepadFaceStyleForType(AType);
end;

{ 欄 1 つ（ゲーム側の名前, 機器側の名前）を割り当てにして足す（SDL_PrivateParseGamepadElement）。 }
procedure ParseElement(const AMapping, AGameButton, AJoyButton: String; var ABindings: TPMLGamepadBindings);
var
  Bind: TPMLGamepadBinding;
  GameName, JoyName: String;
  HalfOut, HalfIn: Char;
  Axby, Baxy, Invert: Boolean;
  Axis: TPMLGamepadAxis;
  Button: TPMLGamepadButton;
  I, Tmp: Integer;
begin
  GameName := AGameButton;
  JoyName := AJoyButton;
  Bind := Default(TPMLGamepadBinding);
  HalfOut := #0;
  HalfIn := #0;
  Invert := False;
  if (GameName <> '') and (GameName[1] in ['+', '-']) then
  begin
    HalfOut := GameName[1];
    Delete(GameName, 1, 1);
  end;
  Axby := Pos(',hint:' + GamecubeLabelsHint + ':=1', AMapping) > 0;
  Baxy := Pos(',hint:' + ButtonLabelsHint + ':=1', AMapping) > 0;

  if PMLGamepadAxisFromString(GameName, Axis) then
  begin
    Bind.OutputType := TPMLGamepadBindType.Axis;
    Bind.OutputAxis := Axis;
    if Axis in [TPMLGamepadAxis.LeftTrigger, TPMLGamepadAxis.RightTrigger] then
    begin
      Bind.OutputMin := 0;
      Bind.OutputMax := PML_JOYSTICK_AXIS_MAX;
    end
    else if HalfOut = '+' then
    begin
      Bind.OutputMin := 0;
      Bind.OutputMax := PML_JOYSTICK_AXIS_MAX;
    end
    else if HalfOut = '-' then
    begin
      Bind.OutputMin := 0;
      Bind.OutputMax := PML_JOYSTICK_AXIS_MIN;
    end
    else
    begin
      Bind.OutputMin := PML_JOYSTICK_AXIS_MIN;
      Bind.OutputMax := PML_JOYSTICK_AXIS_MAX;
    end;
  end
  else if ButtonFromStringSwapped(GameName, Axby, Baxy, Button) then
  begin
    Bind.OutputType := TPMLGamepadBindType.Button;
    Bind.OutputButton := Button;
  end
  else
    Exit;

  if (JoyName <> '') and (JoyName[1] in ['+', '-']) then
  begin
    HalfIn := JoyName[1];
    Delete(JoyName, 1, 1);
  end;
  if (JoyName <> '') and (JoyName[Length(JoyName)] = '~') then
    Invert := True;

  if (Length(JoyName) >= 2) and (JoyName[1] = 'a') and IsDigitC(JoyName[2]) then
  begin
    Bind.InputType := TPMLGamepadBindType.Axis;
    Bind.InputIndex := AtoiAt(JoyName, 2);
    if HalfIn = '+' then
    begin
      Bind.InputMin := 0;
      Bind.InputMax := PML_JOYSTICK_AXIS_MAX;
    end
    else if HalfIn = '-' then
    begin
      Bind.InputMin := 0;
      Bind.InputMax := PML_JOYSTICK_AXIS_MIN;
    end
    else
    begin
      Bind.InputMin := PML_JOYSTICK_AXIS_MIN;
      Bind.InputMax := PML_JOYSTICK_AXIS_MAX;
    end;
    if Invert then
    begin
      Tmp := Bind.InputMin;
      Bind.InputMin := Bind.InputMax;
      Bind.InputMax := Tmp;
    end;
  end
  else if (Length(JoyName) >= 2) and (JoyName[1] = 'b') and IsDigitC(JoyName[2]) then
  begin
    Bind.InputType := TPMLGamepadBindType.Button;
    Bind.InputIndex := AtoiAt(JoyName, 2);
  end
  else if (Length(JoyName) >= 4) and (JoyName[1] = 'h') and IsDigitC(JoyName[2]) and (JoyName[3] = '.')
  and IsDigitC(JoyName[4]) then
  begin
    Bind.InputType := TPMLGamepadBindType.Hat;
    Bind.InputIndex := AtoiAt(JoyName, 2);
    Bind.InputMask := AtoiAt(JoyName, 4);
  end
  else
    Exit;

  // 同じ割り当てが既にあれば足さない（顔のボタンの別名で重なる）
  for I := 0 to High(ABindings) do
    if CompareByte(ABindings[I], Bind, SizeOf(Bind)) = 0 then
      Exit;
  SetLength(ABindings, Length(ABindings) + 1);
  ABindings[High(ABindings)] := Bind;
end;

function PMLParseGamepadBindings(const AMapping: String; var ABindings: TPMLGamepadBindings): Boolean;
const
  MaxGame = 20;
  MaxJoy = 128;
var
  GameButton, JoyButton: String;
  IsGame: Boolean;
  I, P: Integer;
  C: Char;
begin
  GameButton := '';
  JoyButton := '';
  IsGame := True;
  I := 0;
  for P := 1 to Length(AMapping) do
  begin
    C := AMapping[P];
    if C = ':' then
    begin
      I := 0;
      IsGame := False;
    end
    else if C = ' ' then
    begin
    end
    else if C = ',' then
    begin
      I := 0;
      IsGame := True;
      ParseElement(AMapping, GameButton, JoyButton, ABindings);
      GameButton := '';
      JoyButton := '';
    end
    else if IsGame then
    begin
      if I >= MaxGame then
        Exit(False);
      GameButton := GameButton + C;
      Inc(I);
    end
    else
    begin
      if I >= MaxJoy then
        Exit(False);
      JoyButton := JoyButton + C;
      Inc(I);
    end;
  end;
  // 最後がコンマで終わっていなければ、残りの欄がある
  if (GameButton <> '') or (JoyButton <> '') then
    ParseElement(AMapping, GameButton, JoyButton, ABindings);
  Result := True;
end;

procedure AppendInput(var AText: String; const AName: String; const AInput: TPMLInputMapping);
var
  Piece: String;
begin
  if AInput.Kind = TPMLMappingKind.None then
    Exit;
  case AInput.Kind of
    TPMLMappingKind.Button:
      Piece := Format('b%d', [AInput.Target]);
    TPMLMappingKind.Axis:
    begin
      Piece := '';
      if AInput.HalfAxisPositive then
        Piece := '+'
      else if AInput.HalfAxisNegative then
        Piece := '-';
      Piece := Piece + Format('a%d', [AInput.Target]);
      if AInput.AxisReversed then
        Piece := Piece + '~';
    end;
    TPMLMappingKind.Hat:
      Piece := Format('h%d.%d', [AInput.Target shr 4, AInput.Target and $0F]);
  end;
  AText := AText + AName + ':' + Piece + ',';
end;

function PMLAutomaticMappingString(const AName: String; const ARaw: TPMLGamepadMapping): String;
var
  Name: String;
  I: Integer;
begin
  // 名前は 127 文字まで、コンマは空白にする
  Name := Copy(AName, 1, 127);
  for I := 1 to Length(Name) do
    if Name[I] = ',' then
      Name[I] := ' ';
  Result := 'none,' + Name + ',';
  with ARaw do
  begin
    AppendInput(Result, 'a', Buttons[TPMLGamepadButton.South]);
    AppendInput(Result, 'b', Buttons[TPMLGamepadButton.East]);
    AppendInput(Result, 'x', Buttons[TPMLGamepadButton.West]);
    AppendInput(Result, 'y', Buttons[TPMLGamepadButton.North]);
    AppendInput(Result, 'back', Buttons[TPMLGamepadButton.Back]);
    AppendInput(Result, 'guide', Buttons[TPMLGamepadButton.Guide]);
    AppendInput(Result, 'start', Buttons[TPMLGamepadButton.Start]);
    AppendInput(Result, 'leftstick', Buttons[TPMLGamepadButton.LeftStick]);
    AppendInput(Result, 'rightstick', Buttons[TPMLGamepadButton.RightStick]);
    AppendInput(Result, 'leftshoulder', Buttons[TPMLGamepadButton.LeftShoulder]);
    AppendInput(Result, 'rightshoulder', Buttons[TPMLGamepadButton.RightShoulder]);
    AppendInput(Result, 'dpup', Buttons[TPMLGamepadButton.DPadUp]);
    AppendInput(Result, 'dpdown', Buttons[TPMLGamepadButton.DPadDown]);
    AppendInput(Result, 'dpleft', Buttons[TPMLGamepadButton.DPadLeft]);
    AppendInput(Result, 'dpright', Buttons[TPMLGamepadButton.DPadRight]);
    AppendInput(Result, 'misc1', Buttons[TPMLGamepadButton.Misc1]);
    AppendInput(Result, 'misc2', Buttons[TPMLGamepadButton.Misc2]);
    AppendInput(Result, 'misc3', Buttons[TPMLGamepadButton.Misc3]);
    AppendInput(Result, 'misc4', Buttons[TPMLGamepadButton.Misc4]);
    AppendInput(Result, 'misc5', Buttons[TPMLGamepadButton.Misc5]);
    AppendInput(Result, 'misc6', Buttons[TPMLGamepadButton.Misc6]);
    // SDL2 でも使えるよう、パドルは paddle1〜4 の名前で出す
    AppendInput(Result, 'paddle1', Buttons[TPMLGamepadButton.RightPaddle1]);
    AppendInput(Result, 'paddle2', Buttons[TPMLGamepadButton.LeftPaddle1]);
    AppendInput(Result, 'paddle3', Buttons[TPMLGamepadButton.RightPaddle2]);
    AppendInput(Result, 'paddle4', Buttons[TPMLGamepadButton.LeftPaddle2]);
    AppendInput(Result, 'leftx', Axes[TPMLGamepadAxis.LeftX]);
    AppendInput(Result, 'lefty', Axes[TPMLGamepadAxis.LeftY]);
    AppendInput(Result, 'rightx', Axes[TPMLGamepadAxis.RightX]);
    AppendInput(Result, 'righty', Axes[TPMLGamepadAxis.RightY]);
    AppendInput(Result, 'lefttrigger', Axes[TPMLGamepadAxis.LeftTrigger]);
    AppendInput(Result, 'righttrigger', Axes[TPMLGamepadAxis.RightTrigger]);
    AppendInput(Result, 'touchpad', Buttons[TPMLGamepadButton.Touchpad]);
  end;
  // SDL は 1024 バイトの置き場に切って入れる
  if Length(Result) > 1023 then
    SetLength(Result, 1023);
end;

{ ---- 位置どおりの並びへの読み替え ---- }

function ReplaceAt(const S: String; APos: Integer; AChar: Char): String;
begin
  Result := S;
  if APos > 0 then
    Result[APos + 1] := AChar;     // ",b:" の 'b'
end;

function ConvertToPositionalAXBY(const AMapping: String): String;
var
  B, X, H: Integer;
begin
  Result := AMapping;
  B := Pos(',b:', AMapping);
  X := Pos(',x:', AMapping);
  H := Pos('hint:' + GamecubeLabelsHint, AMapping);
  Result := ReplaceAt(Result, B, 'x');
  Result := ReplaceAt(Result, X, 'b');
  if H > 0 then
    Insert('!', Result, H + 5);
end;

function ConvertToPositionalBAXY(const AMapping: String): String;
var
  A, B, X, Y, H: Integer;
begin
  Result := AMapping;
  A := Pos(',a:', AMapping);
  B := Pos(',b:', AMapping);
  X := Pos(',x:', AMapping);
  Y := Pos(',y:', AMapping);
  H := Pos('hint:' + ButtonLabelsHint, AMapping);
  Result := ReplaceAt(Result, A, 'b');
  Result := ReplaceAt(Result, B, 'a');
  Result := ReplaceAt(Result, X, 'y');
  Result := ReplaceAt(Result, Y, 'x');
  if H > 0 then
    Insert('!', Result, H + 5);
end;

{ ---- TPMLGamepadMappingDB ---- }

constructor TPMLGamepadMappingDB.Create(AHints: TPMLHints; AIsGameCube: TPMLIsGameCubeFunc);
begin
  inherited Create;
  FHints := AHints;
  FIsGameCube := AIsGameCube;
end;

destructor TPMLGamepadMappingDB.Destroy;
var
  I: Integer;
begin
  Clear;
  for I := 0 to High(FRetired) do
    FRetired[I].Free;
  inherited Destroy;
end;

function TPMLGamepadMappingDB.GetCount: Integer;
begin
  Result := Length(FEntries);
end;

function TPMLGamepadMappingDB.GetEntry(AIndex: Integer): TPMLGamepadMappingEntry;
begin
  Result := FEntries[AIndex];
end;

procedure TPMLGamepadMappingDB.TrackPush;
begin
  if FTracker <> nil then
    FTracker.Push;
end;

procedure TPMLGamepadMappingDB.TrackChanged(AEntry: TPMLGamepadMappingEntry);
begin
  if FTracker <> nil then
    FTracker.Changed(AEntry);
end;

procedure TPMLGamepadMappingDB.TrackPop;
begin
  if FTracker <> nil then
    FTracker.Pop;
end;

procedure TPMLGamepadMappingDB.Clear;
var
  I, N: Integer;
begin
  // 前に捨てた分は、ここで本当に捨てる（追跡はもう終わっている）
  for I := 0 to High(FRetired) do
    FRetired[I].Free;
  FRetired := nil;
  N := Length(FEntries);
  SetLength(FRetired, N);
  for I := 0 to N - 1 do
    FRetired[I] := FEntries[I];
  FEntries := nil;
  FDefault := nil;
  FXInput := nil;
end;

function TPMLGamepadMappingDB.MatchForGUID(const AGUID: TPMLGUID; AMatchVersion, AExactCRC: Boolean): TPMLGamepadMappingEntry;
var
  G, MG: TPMLGUID;
  V, P, Ver, CRC, MapCRC: Word;
  I, CP: Integer;
  E: TPMLGamepadMappingEntry;
begin
  Result := nil;
  G := AGUID;
  PMLGetJoystickGUIDInfo(G, V, P, Ver, CRC);
  PMLSetJoystickGUIDCRC(G, 0);
  if not AMatchVersion then
    PMLSetJoystickGUIDVersion(G, 0);
  for I := 0 to High(FEntries) do
  begin
    E := FEntries[I];
    if PMLSameGUID(E.GUID, PMLZeroGUID) then
      Continue;
    MG := E.GUID;
    if not AMatchVersion then
      PMLSetJoystickGUIDVersion(MG, 0);
    if PMLSameGUID(G, MG) then
    begin
      CP := Pos(CRCField, E.Mapping);
      if CP > 0 then
      begin
        MapCRC := StrToLongHex16(E.Mapping, CP + Length(CRCField));
        if MapCRC <> CRC then
          Continue;                     // この行は CRC を指定していて、合わない
        Exit(E);                        // CRC まで一致
      end
      else if (CRC <> 0) and AExactCRC then
        Continue;
      if Result = nil then
        Result := E;
    end;
  end;
end;

function TPMLGamepadMappingDB.FindForGUID(const AGUID: TPMLGUID; AAdding: Boolean): TPMLGamepadMappingEntry;
var
  V, P, Ver, CRC: Word;
begin
  Result := MatchForGUID(AGUID, True, True);
  if Result <> nil then
    Exit;
  if AAdding then
    Exit(nil);
  Result := MatchForGUID(AGUID, True, False);
  if Result <> nil then
    Exit;
  // バージョンを見ない（GUID がバージョンを使うとき。SDL_JoystickGUIDUsesVersion）
  PMLGetJoystickGUIDInfo(AGUID, V, P, Ver, CRC);
  if (V <> 0) and (P <> 0) then
  begin
    Result := MatchForGUID(AGUID, False, True);
    if Result <> nil then
      Exit;
    Result := MatchForGUID(AGUID, False, False);
  end;
end;

function TPMLGamepadMappingDB.AddForGUID(AGUID: TPMLGUID; const AMapping: String; out AExisting: Boolean;
  APriority: TPMLGamepadMappingPriority): TPMLGamepadMappingEntry;
var
  Name, Body, CRCEnd, Sep: String;
  CRC: Word;
  V, P, Ver: Word;
  CP, EP: Integer;
  E: TPMLGamepadMappingEntry;
begin
  Result := nil;
  AExisting := False;
  if not PMLMappingStringName(AMapping, Name) then
  begin
    FLastError := 'Couldn''t parse the name in ' + AMapping;
    Exit;
  end;
  if not PMLMappingStringBody(AMapping, Body) then
  begin
    FLastError := 'Couldn''t parse ' + AMapping;
    Exit;
  end;
  // GUID と本体に CRC を合わせる
  PMLGetJoystickGUIDInfo(AGUID, V, P, Ver, CRC);
  if CRC <> 0 then
  begin
    CRCEnd := '';
    CP := Pos(CRCField, Body);
    if CP > 0 then
    begin
      EP := Pos(',', Copy(Body, CP, MaxInt));
      if EP > 0 then
        CRCEnd := Copy(Body, CP + EP, MaxInt);
      SetLength(Body, CP - 1);
    end;
    if (Body = '') or (Body[Length(Body)] = ',') then
      Sep := ''
    else
      Sep := ',';
    Body := Body + Sep + CRCField + LowerCase(Format('%.4x', [CRC])) + ',' + CRCEnd;
  end
  else
  begin
    CP := Pos(CRCField, Body);
    if CP > 0 then
    begin
      CRC := StrToLongHex16(Body, CP + Length(CRCField));
      if CRC <> 0 then
        PMLSetJoystickGUIDCRC(AGUID, CRC);
    end;
  end;

  TrackPush;
  try
    E := FindForGUID(AGUID, True);
    if E <> nil then
    begin
      // 優先度が同じか高いときだけ上書きする
      if E.Priority <= APriority then
      begin
        E.Name := Name;
        E.Mapping := Body;
        E.Priority := APriority;
      end;
      AExisting := True;
      TrackChanged(E);
      Result := E;
    end
    else
    begin
      if CRC <> 0 then
        PMLSetJoystickGUIDCRC(AGUID, 0);
      E := TPMLGamepadMappingEntry.Create;
      E.GUID := AGUID;
      E.Name := Name;
      E.Mapping := Body;
      E.Priority := APriority;
      SetLength(FEntries, Length(FEntries) + 1);
      FEntries[High(FEntries)] := E;
      Result := E;
    end;
  finally
    TrackPop;
  end;
end;

function TPMLGamepadMappingDB.AddMapping(const AMapping: String): Integer;
begin
  Result := AddMappingWithPriority(AMapping, TPMLGamepadMappingPriority.API);
end;


function TPMLGamepadMappingDB.AddMappingWithPriority(const AMapping: String;
  APriority: TPMLGamepadMappingPriority): Integer;
var
  S, GUIDText, HintName, HintValue: String;
  GUID: TPMLGUID;
  V, P, Ver, CRC: Word;
  IsDefault, IsXInput, Existing, DefaultValue, Value, Negate: Boolean;
  HP, I: Integer;
  E: TPMLGamepadMappingEntry;
begin
  Result := -1;
  S := AMapping;
  if not PMLMappingStringGUID(S, GUIDText) then
  begin
    FLastError := 'Couldn''t parse the GUID in ' + S;
    Exit;
  end;
  IsDefault := SameText(GUIDText, 'default');
  IsXInput := SameText(GUIDText, 'xinput');
  GUID := PMLStringToGUID(GUIDText);

  // GameCube のアダプタには、位置どおりの並びの印を足す
  PMLGetJoystickGUIDInfo(GUID, V, P, Ver, CRC);
  if Assigned(FIsGameCube) and FIsGameCube(V, P) and (Pos(GamecubeLabelsHint, S) = 0) then
    S := S + 'hint:' + GamecubeLabelsHint + ':=1,';

  // hint: 欄（最初の 1 つだけ）
  HP := Pos(HintField, S);
  if HP > 0 then
  begin
    I := HP + Length(HintField);
    Negate := (I <= Length(S)) and (S[I] = '!');
    if Negate then
      Inc(I);
    HintName := '';
    while (I <= Length(S)) and not (S[I] in [',', ':']) and (Length(HintName) < 127) do
    begin
      HintName := HintName + S[I];
      Inc(I);
    end;
    DefaultValue := False;
    if (I < Length(S)) and (S[I] = ':') and (S[I + 1] = '=') then
      DefaultValue := AtoiAt(S, I + 2) <> 0;
    if HintName = GamecubeLabelsHint then
    begin
      // 印は、割り当てが位置どおりかどうか。「!」が無ければ文字どおりなので位置どおりへ読み替える
      if not Negate then
        S := ConvertToPositionalAXBY(S);
    end
    else if HintName = ButtonLabelsHint then
    begin
      if not Negate then
        S := ConvertToPositionalBAXY(S);
    end
    else
    begin
      HintValue := '';
      if FHints <> nil then
        FHints.TryGetHint(HintName, HintValue);
      Value := PMLStringBoolean(HintValue, DefaultValue);
      if Negate then
        Value := not Value;
      if not Value then
        Exit(0);
    end;
  end;

  E := AddForGUID(GUID, S, Existing, APriority);
  if E = nil then
    Exit;
  if Existing then
    Result := 0
  else
  begin
    if IsDefault then
      FDefault := E
    else if IsXInput then
      FXInput := E;
    Result := 1;
  end;
end;

// SDL_strncasecmp(欄, "Linux", 欄の長さ) = 0。C の文字列の終わりも 1 文字として比べる。
function PlatformMatches(const AText: String; ALen: Integer): Boolean;
var
  I: Integer;
  B: Char;
begin
  for I := 1 to ALen do
  begin
    if I <= Length(PML_GAMEPAD_PLATFORM) then
      B := PML_GAMEPAD_PLATFORM[I]
    else
      B := #0;
    if UpCase(AText[I]) <> UpCase(B) then
      Exit(False);
    if B = #0 then
      Break;
  end;
  Result := True;
end;

function TPMLGamepadMappingDB.AddFromText(const AText: String): Integer;
var
  Lines: TStringArray;
  I, P, C: Integer;
  Tail: String;
begin
  Result := 0;
  Lines := SplitLF(AText);
  TrackPush;
  try
    for I := 0 to High(Lines) do
    begin
      P := Pos(PlatformField, Lines[I]);
      if P = 0 then
        Continue;
      Tail := Copy(Lines[I], P + Length(PlatformField), MaxInt);
      C := Pos(',', Tail);
      if C = 0 then
        Continue;
      if PlatformMatches(Tail, C - 1) and (AddMapping(Lines[I]) > 0) then
        Inc(Result);
    end;
  finally
    TrackPop;
  end;
end;

function TPMLGamepadMappingDB.AddFromFile(const APath: String): Integer;
var
  F: TFileStream;
  Buf: String;
begin
  try
    F := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  except
    FLastError := 'Could not open ' + APath;
    Exit(-1);
  end;
  try
    SetLength(Buf, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Buf[1], F.Size);
  finally
    F.Free;
  end;
  Result := AddFromText(Buf);
end;

function TPMLGamepadMappingDB.FormatMapping(AEntry: TPMLGamepadMappingEntry; const AGUID: TPMLGUID): String;
var
  P: Integer;
  NeedPlatform: Boolean;
begin
  Result := PMLGUIDToString(AGUID) + ',' + AEntry.Name + ',' + AEntry.Mapping;
  NeedPlatform := Pos(PlatformField, AEntry.Mapping) = 0;
  if NeedPlatform then
  begin
    // SDL は空の割り当ての「手前の 1 文字」を読む（未定義）。ここではコンマではないものとして扱う
    if (AEntry.Mapping = '') or (AEntry.Mapping[Length(AEntry.Mapping)] <> ',') then
      Result := Result + ',';
    Result := Result + PlatformField + PML_GAMEPAD_PLATFORM + ',';
  end;
  // platform: が 2 つ入り込んでいたら、2 つ目から後ろを切る
  P := Pos(PlatformField, Result);
  if P > 0 then
  begin
    P := Pos(PlatformField, Copy(Result, P + 1, MaxInt)) ;
    if P > 0 then
    begin
      P := Pos(PlatformField, Result) + P;
      SetLength(Result, P - 1);
    end;
  end;
end;

function TPMLGamepadMappingDB.AllMappings: TStringArray;
var
  I, N: Integer;
begin
  Result := nil;
  N := 0;
  for I := 0 to High(FEntries) do
  begin
    if PMLSameGUID(FEntries[I].GUID, PMLZeroGUID) then
      Continue;
    SetLength(Result, N + 1);
    Result[N] := FormatMapping(FEntries[I], FEntries[I].GUID);
    Inc(N);
  end;
end;

procedure TPMLGamepadMappingDB.LoadHintMappings;
var
  Lines: TStringArray;
  I: Integer;
begin
  if FHints = nil then
    Exit;
  if FHints.GetHint(PML_HINT_GAMEPAD_CONFIG) = '' then
    Exit;
  Lines := SplitLF(FHints.GetHint(PML_HINT_GAMEPAD_CONFIG));
  TrackPush;
  try
    // SDL は改行ごとに、空の行も含めて渡す（空の行は失敗で何も起きない）
    for I := 0 to High(Lines) do
      AddMappingWithPriority(Lines[I], TPMLGamepadMappingPriority.User);
  finally
    TrackPop;
  end;
end;

procedure TPMLGamepadMappingDB.LoadInitial;
var
  I: Integer;
  Path: String;
begin
  TrackPush;
  try
    for I := 0 to High(GamepadDBLinux) do
      AddMappingWithPriority(GamepadDBLinux[I], TPMLGamepadMappingPriority.Builtin);
    if FHints <> nil then
    begin
      Path := FHints.GetHint(PML_HINT_GAMEPAD_CONFIG_FILE);
      if Path <> '' then
        AddFromFile(Path);
    end;
    LoadHintMappings;
  finally
    TrackPop;
  end;
end;

end.
