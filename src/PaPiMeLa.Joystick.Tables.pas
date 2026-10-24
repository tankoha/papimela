{
  PaPiMeLa.Joystick.Tables — ジョイスティックの VID/PID の表とコントローラの表

  Origin : ported from SDL (src/joystick/SDL_joystick.c, src/joystick/controller_type.c,
           src/joystick/controller_list.h)
           Scope: 機器の種類を決める VID/PID の表 11 個（SDL_vidpid_list。ヒントで足し引きできる）、
           SDL_LoadVIDPIDList / SDL_VIDPIDInList、コントローラの表（GuessControllerType、
           GuessControllerName。Valve。zlib）。表の中身は tools/genjoystick.bb が作る。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #59

  WHAT:
    TPMLVIDPIDList は「初めから入っている VID/PID」に、ヒントで足したもの（TPMLHints の効いている値。
    環境変数も含む）を足し、_EXCLUDED のヒントで外したものを引いた表。ヒントが変わると読み直す。
    PMLGuessControllerType / PMLGuessControllerName はコントローラの表を引く。

  RESOLVED:
    - 初めから入っている表は、生成器が SDL から写す（tools/genjoystick.bb）。件数は生成器が元と突き合わせる
    - ヒントの値は「0x045e/0x02ea,...」のように、0x で始まる 16 進を 2 つずつ読む。@で始まれば
      その名前のファイルから読む（SDL と同じ）

  Copyright (C) Valve Corporation（コントローラの表）
  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Joystick.Tables;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Properties;

const
  // コントローラの種類（controller_type.h の EControllerType。値を変えてはいけない）。
  PML_CONTROLLER_TYPE_NONE                     = -1;
  PML_CONTROLLER_TYPE_UNKNOWN                  = 0;
  PML_CONTROLLER_TYPE_UNKNOWN_STEAM            = 1;
  PML_CONTROLLER_TYPE_STEAM                    = 2;
  PML_CONTROLLER_TYPE_STEAM_V2                 = 3;
  PML_CONTROLLER_TYPE_STEAM_NEPTUNE            = 4;
  PML_CONTROLLER_TYPE_STEAM_TRITON             = 10;
  PML_CONTROLLER_TYPE_UNKNOWN_NON_STEAM        = 30;
  PML_CONTROLLER_TYPE_XBOX360                  = 31;
  PML_CONTROLLER_TYPE_XBOXONE                  = 32;
  PML_CONTROLLER_TYPE_PS3                      = 33;
  PML_CONTROLLER_TYPE_PS4                      = 34;
  PML_CONTROLLER_TYPE_WII                      = 35;
  PML_CONTROLLER_TYPE_APPLE                    = 36;
  PML_CONTROLLER_TYPE_ANDROID                  = 37;
  PML_CONTROLLER_TYPE_SWITCH_PRO               = 38;
  PML_CONTROLLER_TYPE_SWITCH_JOYCON_LEFT       = 39;
  PML_CONTROLLER_TYPE_SWITCH_JOYCON_RIGHT      = 40;
  PML_CONTROLLER_TYPE_SWITCH_JOYCON_PAIR       = 41;
  PML_CONTROLLER_TYPE_SWITCH_INPUT_ONLY        = 42;
  PML_CONTROLLER_TYPE_MOBILE_TOUCH             = 43;
  PML_CONTROLLER_TYPE_XINPUT_SWITCH            = 44;
  PML_CONTROLLER_TYPE_PS5                      = 45;
  PML_CONTROLLER_TYPE_XBOX_ELITE               = 46;
  PML_CONTROLLER_TYPE_XINPUT_PS4               = 47;
  PML_CONTROLLER_TYPE_PS5_EDGE                 = 48;
  PML_CONTROLLER_TYPE_HORI_STEAM               = 49;
  PML_CONTROLLER_TYPE_8BITDO                   = 50;
  PML_CONTROLLER_TYPE_SWITCH2_PRO              = 51;
  PML_CONTROLLER_TYPE_SWITCH2_INPUT_ONLY       = 52;

{$I generated/joystick_tables.inc}

type
  TPMLVIDPIDEntries = array of LongWord;

  { VID/PID の表（SDL_vidpid_list）。IncludedHint のヒントで足し、ExcludedHint のヒントで外す。
    ヒントが変わると読み直す。 }
  TPMLVIDPIDList = class
  strict private
    FHints        : TPMLHints;
    FInitial      : TPMLVIDPIDEntries;
    FIncludedHint : String;
    FExcludedHint : String;
    FIncluded     : TPMLVIDPIDEntries;
    FExcluded     : TPMLVIDPIDEntries;
    procedure Reload;
    procedure HintChanged(const AName: String; const AOld, ANew: TPMLHintValue);
  public
    { AHints は nil でもよい（ヒントを見ない）。AInitial は初めから入っている VID/PID。 }
    constructor Create(AHints: TPMLHints; const AInitial: array of LongWord;
      const AIncludedHint, AExcludedHint: String);
    destructor Destroy; override;
    // 外す表に入っていなくて、入れる表に入っていれば True（SDL_VIDPIDInList）。
    function  Contains(AVendor, AProduct: Word): Boolean;
    // 入れる表の件数（初めから入っているものと、ヒントで足したもの）。
    function  IncludedCount: Integer;
  end;

// ヒントの値（「0x045e/0x02ea,...」か「@ファイル」）から、VID/PID を 32 ビットにして並べる。
function PMLParseVIDPIDList(const AText: String): TPMLVIDPIDEntries;

{ コントローラの種類（GuessControllerType）。AHints のヒント PML_HINT_GAMEPAD_TYPE が
  「0x045e/0x02ea=XboxOne」のように上書きできる。表に無ければ PML_CONTROLLER_TYPE_UNKNOWN_NON_STEAM。 }
function PMLGuessControllerType(AHints: TPMLHints; AVendor, AProduct: Word): Integer;
// 表にある名前（GuessControllerName）。無ければ ''。
function PMLGuessControllerName(AVendor, AProduct: Word): String;

implementation

// 「0x」で始まる 16 進を読む（strtol の基数 0）。APos は読んだ後ろへ進む。
function ReadHex(const AText: String; var APos: Integer): LongWord;
var
  C: Char;
begin
  Result := 0;
  Inc(APos, 2);        // 0x
  while APos <= Length(AText) do
  begin
    C := AText[APos];
    case C of
      '0'..'9': Result := (Result shl 4) or LongWord(Ord(C) - Ord('0'));
      'a'..'f': Result := (Result shl 4) or LongWord(Ord(C) - Ord('a') + 10);
      'A'..'F': Result := (Result shl 4) or LongWord(Ord(C) - Ord('A') + 10);
    else
      Break;
    end;
    Inc(APos);
  end;
end;

function PMLParseVIDPIDList(const AText: String): TPMLVIDPIDEntries;
var
  Source: String;
  Pos1, Next, N: Integer;
  Entry: LongWord;
  Stream: TStringList;
begin
  Result := nil;
  Source := AText;
  if (Source <> '') and (Source[1] = '@') then
  begin
    // ファイルから読む（読めなければ何も足さない）
    Stream := TStringList.Create;
    try
      try
        Stream.LoadFromFile(Copy(Source, 2, MaxInt));
        Source := Stream.Text;
      except
        on E: EInOutError do
          Source := '';
      end;
    finally
      Stream.Free;
    end;
  end;
  N := 0;
  Pos1 := 1;
  while True do
  begin
    Next := Pos('0x', Copy(Source, Pos1, MaxInt));
    if Next = 0 then
      Break;
    Pos1 := Pos1 + Next - 1;
    Entry := Word(ReadHex(Source, Pos1));
    Entry := Entry shl 16;
    Next := Pos('0x', Copy(Source, Pos1, MaxInt));
    if Next = 0 then
      Break;
    Pos1 := Pos1 + Next - 1;
    Entry := Entry or Word(ReadHex(Source, Pos1));
    SetLength(Result, N + 1);
    Result[N] := Entry;
    Inc(N);
  end;
end;

{ TPMLVIDPIDList }

constructor TPMLVIDPIDList.Create(AHints: TPMLHints; const AInitial: array of LongWord;
  const AIncludedHint, AExcludedHint: String);
var
  I: Integer;
begin
  inherited Create;
  FHints := AHints;
  SetLength(FInitial, Length(AInitial));
  for I := 0 to High(AInitial) do
    FInitial[I] := AInitial[I];
  FIncludedHint := AIncludedHint;
  FExcludedHint := AExcludedHint;
  if FHints <> nil then
  begin
    if FIncludedHint <> '' then
      FHints.AddCallback(FIncludedHint, @HintChanged);
    if FExcludedHint <> '' then
      FHints.AddCallback(FExcludedHint, @HintChanged);
  end;
  Reload;
end;

destructor TPMLVIDPIDList.Destroy;
begin
  if FHints <> nil then
  begin
    if FIncludedHint <> '' then
      FHints.RemoveCallback(FIncludedHint, @HintChanged);
    if FExcludedHint <> '' then
      FHints.RemoveCallback(FExcludedHint, @HintChanged);
  end;
  inherited Destroy;
end;

procedure TPMLVIDPIDList.Reload;
var
  Extra: TPMLVIDPIDEntries;
  I: Integer;
begin
  FIncluded := Copy(FInitial);
  FExcluded := nil;
  if (FHints <> nil) and (FIncludedHint <> '') then
  begin
    Extra := PMLParseVIDPIDList(FHints.GetHint(FIncludedHint));
    for I := 0 to High(Extra) do
    begin
      SetLength(FIncluded, Length(FIncluded) + 1);
      FIncluded[High(FIncluded)] := Extra[I];
    end;
  end;
  if (FHints <> nil) and (FExcludedHint <> '') then
    FExcluded := PMLParseVIDPIDList(FHints.GetHint(FExcludedHint));
end;

procedure TPMLVIDPIDList.HintChanged(const AName: String; const AOld, ANew: TPMLHintValue);
begin
  Reload;
end;

function TPMLVIDPIDList.Contains(AVendor, AProduct: Word): Boolean;
var
  Key: LongWord;
  I: Integer;
begin
  Key := (LongWord(AVendor) shl 16) or AProduct;
  for I := 0 to High(FExcluded) do
    if FExcluded[I] = Key then
      Exit(False);
  for I := 0 to High(FIncluded) do
    if FIncluded[I] = Key then
      Exit(True);
  Result := False;
end;

function TPMLVIDPIDList.IncludedCount: Integer;
begin
  Result := Length(FIncluded);
end;

{ コントローラの表 }

// ヒントの「0x045e/0x02ea=...」の「=」の後ろの名前。無ければ ''。
function ControllerTypeOverride(AHints: TPMLHints; AVendor, AProduct: Word): String;
var
  Hint, Key: String;
  P: Integer;
begin
  Result := '';
  if AHints = nil then
    Exit;
  Hint := AHints.GetHint(PML_HINT_GAMEPAD_TYPE);
  if Hint = '' then
    Exit;
  Key := Format('0x%.4x/0x%.4x=', [AVendor, AProduct]);
  P := Pos(Key, Hint);
  if P = 0 then
  begin
    Key := Format('0x%.4X/0x%.4X=', [AVendor, AProduct]);
    P := Pos(Key, Hint);
  end;
  if P = 0 then
    Exit;
  Result := Copy(Hint, P + Length(Key), MaxInt);
  if Copy(Result, 1, 18) = 'k_eControllerType_' then
    Delete(Result, 1, 18);
end;

function StartsWithNoCase(const AText, APrefix: String): Boolean;
begin
  Result := SameText(Copy(AText, 1, Length(APrefix)), APrefix);
end;

function PMLGuessControllerType(AHints: TPMLHints; AVendor, AProduct: Word): Integer;
var
  Override_: String;
  Key: LongWord;
  I: Integer;
begin
  Override_ := ControllerTypeOverride(AHints, AVendor, AProduct);
  if Override_ <> '' then
  begin
    if StartsWithNoCase(Override_, 'Xbox360') then Exit(PML_CONTROLLER_TYPE_XBOX360);
    if StartsWithNoCase(Override_, 'XboxOne') then Exit(PML_CONTROLLER_TYPE_XBOXONE);
    if StartsWithNoCase(Override_, 'PS3') then Exit(PML_CONTROLLER_TYPE_PS3);
    if StartsWithNoCase(Override_, 'PS4') then Exit(PML_CONTROLLER_TYPE_PS4);
    if StartsWithNoCase(Override_, 'PS5') then Exit(PML_CONTROLLER_TYPE_PS5);
    if StartsWithNoCase(Override_, 'SwitchPro') then Exit(PML_CONTROLLER_TYPE_SWITCH_PRO);
    if StartsWithNoCase(Override_, 'Steam') then Exit(PML_CONTROLLER_TYPE_STEAM);
    Exit(PML_CONTROLLER_TYPE_UNKNOWN_NON_STEAM);
  end;
  Key := (LongWord(AVendor) shl 16) or AProduct;
  for I := 0 to High(JoystickControllerTable) do
    if JoystickControllerTable[I].DeviceID = Key then
      Exit(JoystickControllerTable[I].Kind);
  Result := PML_CONTROLLER_TYPE_UNKNOWN_NON_STEAM;
end;

function PMLGuessControllerName(AVendor, AProduct: Word): String;
var
  Key: LongWord;
  I: Integer;
begin
  Key := (LongWord(AVendor) shl 16) or AProduct;
  for I := 0 to High(JoystickControllerTable) do
    if JoystickControllerTable[I].DeviceID = Key then
      Exit(JoystickControllerTable[I].Name);
  Result := '';
end;

end.
