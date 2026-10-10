{
  PaPiMeLa.Properties — 名前付きの値の表（プロパティ）とヒント

  Origin : ported from SDL (src/SDL_properties.c, src/SDL_hints.c)
           Scope: 値の種類と、種類をまたいで読むときの変換（数を文字列で、文字列を
           数・小数・真偽で読むなど）、ポインタの後始末を呼ぶ時機と写すときの扱い、
           ヒントの優先度と環境変数の関係、ヒントの変化を知らせる呼び出しの順序。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #6

  WHAT:
    TPMLProperties（SDL_PropertiesID の表 1 つ）、TPMLHints（SDL_SetHint / SDL_GetHint 系）、
    PMLStringBoolean / PMLStringInteger（SDL_GetStringBoolean / SDL_GetStringInteger）、
    C の strtoll / strtod と同じ読み方をする PMLStrToInt64C / PMLStrToFloatC。

  WHY:
    SDL は全部の表を番号で引く大域のハッシュ表に入れ、ヒントも大域の表 1 つに持つ。
    papimela は表をオブジェクトにし、ヒントは Context が持つ（大域の状態を持たない）。

  RESOLVED:
    - 名前は大文字小文字を区別する（SDL と同じ）。空の名前で書くと EPMLArgument、
      読むと既定値（SDL は書くと false を返す）
    - 表は名前の配列を順に探す。表は小さいので足りる。Enumerate は入れた順
    - 値の文字列は Pascal の String なので、数を文字列で読んだときの置き場を持たない。
      SDL の CopyProperties がその置き場を写し元と写し先で共有する誤り（D-54）は起きない
    - ヒントの環境変数は、ヒントと同じ名前（PAPIMELA_LOGGING など）を libc の getenv で
      読む。FPC の GetEnvironmentVariable は「無い」と「空」を区別しない
    - ヒントの変化の知らせは、実際に効いている値（環境変数を含む）が変わったときだけ、
      前後の効いている値で呼ぶ。SDL は環境変数があると前の値を誤って知らせ、変わって
      いないのにも呼ぶ（D-57）

  NOT RESOLVED:
    - Context を作る前にヒントを置く手段が無い（SDL は SDL_Init の前に SDL_SetHint できる）。
      当面は環境変数か TPMLContextOptions を使う
    - PAPIMELA_VIDEO と PAPIMELA_IME は、まだヒントを通さず環境変数を直接読んでいる

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Properties;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Threading;

const
  // ログの優先度（PaPiMeLa.Log）。書式は SDL_HINT_LOGGING と同じ。
  PML_HINT_LOGGING = 'PAPIMELA_LOGGING';

type
  TPMLProperties = class;

  // 数の値は SDL_PropertyType と同じ。
  TPMLPropertyType = (Invalid, Pointer_, String_, Number, Float, Boolean_);

  // ポインタの値が表から消えるとき（上書き、Clear、表を壊すとき）に呼ばれる。
  TPMLPropertyCleanup = procedure(AValue: Pointer) of object;
  // Enumerate が名前ごとに呼ぶ。表は Lock されたまま。
  TPMLPropertyEnumerator = procedure(AProps: TPMLProperties; const AName: String) of object;

  { 名前付きの値の表（SDL_PropertiesID 1 つ分）。どのスレッドから使ってもよい。

    種類をまたいで読むときの変換は SDL と同じ（Get* の注を参照）。ポインタは
    他の種類では読めず、他の種類もポインタとしては読めない（既定値が返る）。 }
  TPMLProperties = class sealed
  strict private
    type
      TEntry = record
        Name     : String;
        Kind     : TPMLPropertyType;
        PtrValue : Pointer;
        StrValue : String;
        NumValue : Int64;
        FltValue : Single;
        BoolValue: Boolean;
        Cleanup  : TPMLPropertyCleanup;
      end;
    var
      FLock   : TPMLMutex;
      FEntries: array of TEntry;
    function  IndexOf(const AName: String): Integer;
    // AName の値を AEntry で置き換える（無ければ足す）。前の値がポインタなら後始末を呼ぶ。
    procedure Put(const AName: String; const AEntry: TEntry);
  public
    constructor Create;
    // 残っているポインタの値の後始末をすべて呼ぶ（SDL_DestroyProperties）。
    destructor Destroy; override;

    { SDL_CopyProperties。自分の値を ADest へ写す（同じ名前は上書き）。後始末付きの
      ポインタは写さない（中身を複製する方法が分からないので。SDL と同じ）。
      ADest が nil か自分自身なら EPMLArgument。 }
    procedure CopyTo(ADest: TPMLProperties);

    // 複数の読み書きをまとめて排他にする（再帰的。Lock した回数だけ Unlock する）。
    procedure Lock;
    procedure Unlock;

    { SDL_SetPointerPropertyWithCleanup / SDL_SetPointerProperty。AValue が nil なら
      Clear と同じ（ACleanup があれば nil で 1 度呼ぶ。SDL と同じ）。 }
    procedure SetPointer(const AName: String; AValue: Pointer;
      ACleanup: TPMLPropertyCleanup = nil);
    procedure SetString(const AName, AValue: String);
    procedure SetNumber(const AName: String; AValue: Int64);
    procedure SetFloat(const AName: String; AValue: Single);
    procedure SetBoolean(const AName: String; AValue: Boolean);

    function  Has(const AName: String): Boolean;
    // 無い名前・空の名前は Invalid。
    function  PropertyType(const AName: String): TPMLPropertyType;

    { 無い名前、空の名前、読めない種類なら ADefault。変換:
      - GetString: 数は 10 進、小数は C の "%f"（小数点以下 6 桁）、真偽は 'true' / 'false'
      - GetNumber: 文字列は C の strtoll（基数 0）、小数は 0 から遠い側へ丸める（C の round）、
        真偽は 0 / 1
      - GetFloat : 文字列は C の strtod、数はそのまま、真偽は 0 / 1
      - GetBoolean: 文字列は PMLStringBoolean(値, ADefault)、数・小数は 0 でなければ True }
    function  GetPointer(const AName: String; ADefault: Pointer = nil): Pointer;
    function  GetString(const AName: String; const ADefault: String = ''): String;
    function  GetNumber(const AName: String; ADefault: Int64 = 0): Int64;
    function  GetFloat(const AName: String; ADefault: Single = 0): Single;
    function  GetBoolean(const AName: String; ADefault: Boolean = False): Boolean;

    // 無ければ何もしない。ポインタなら後始末を呼ぶ。
    procedure Clear(const AName: String);
    function  Count: Integer;
    // 入れた順に呼ぶ。呼び出しの中で表を書き換えてはならない。
    procedure Enumerate(ACallback: TPMLPropertyEnumerator);
  end;

  // ヒントの優先度（SDL_HintPriority）。
  TPMLHintPriority = (Default, Normal, Override);

  // ヒントの値。IsSet が False なら「置かれていない」（SDL の NULL）。
  TPMLHintValue = record
    IsSet: Boolean;
    Value: String;
    class function Unset: TPMLHintValue; static;
    class function Make(const AValue: String): TPMLHintValue; static;
  end;

  // ヒントの効いている値が変わったときに呼ばれる。AddCallback のときは AOld = ANew。
  TPMLHintCallback = procedure(const AName: String;
    const AOld, ANew: TPMLHintValue) of object;

  { ヒント（SDL_SetHint / SDL_GetHint 系）。Context が 1 つ持つ。どのスレッドから使ってもよい。

    効いている値: 同じ名前の環境変数があればそれ。ただし Override で置いた値は
    環境変数より強い。どちらも無ければ置いた値（置いていなければ「置かれていない」）。
    呼び出しは排他を持ったまま、新しく足したものから順に呼ぶ（SDL と同じ）。
    呼び出しの中から AddCallback / RemoveCallback / SetHint してよい。 }
  TPMLHints = class sealed
  strict private
    type
      TEntry = record
        Name     : String;
        Stored   : TPMLHintValue;
        Priority : TPMLHintPriority;
        Callbacks: array of TPMLHintCallback;   // 先頭が最も新しい
      end;
    var
      FLock   : TPMLMutex;
      FEntries: array of TEntry;
    function  IndexOf(const AName: String): Integer;
    // AName の効いている値（環境変数と置いた値から）。
    function  Effective(const AName: String): TPMLHintValue;
    // AName の呼び出しを、その時点の並びの写しに対して順に呼ぶ。
    procedure Notify(const AName: String; const AOld, ANew: TPMLHintValue);
  public
    constructor Create;
    destructor Destroy; override;

    { SDL_SetHintWithPriority。AName と同じ名前の環境変数があり、APriority が Override で
      なければ False（何も変えない）。置いてある優先度より低くても False。そうでなければ
      値と優先度を置いて True。効いている値が変われば呼び出しを呼ぶ。空の名前は EPMLArgument。 }
    function  SetHint(const AName, AValue: String;
      APriority: TPMLHintPriority = TPMLHintPriority.Normal): Boolean;
    { SDL_ResetHint。置いた値を消し、優先度を Default に戻す。その名前を一度も置いて
      おらず呼び出しも無ければ False。効いている値が変われば呼び出しを呼ぶ。 }
    function  ResetHint(const AName: String): Boolean;
    // SDL_ResetHints。全部の名前に ResetHint をする。
    procedure ResetHints;

    // 効いている値。置かれていなければ ''。
    function  GetHint(const AName: String): String;
    // 効いている値。置かれていなければ False。
    function  TryGetHint(const AName: String; out AValue: String): Boolean;
    // SDL_GetHintBoolean。PMLStringBoolean(効いている値, ADefault)。
    function  GetBoolean(const AName: String; ADefault: Boolean): Boolean;

    { SDL_AddHintCallback。同じ名前に同じ呼び出しがあれば、先に外してから足す。
      足したらすぐ、その時点の効いている値で 1 度呼ぶ（AOld = ANew）。
      空の名前や nil の呼び出しは EPMLArgument。 }
    procedure AddCallback(const AName: String; ACallback: TPMLHintCallback);
    // 無ければ何もしない。
    procedure RemoveCallback(const AName: String; ACallback: TPMLHintCallback);
  end;

{ SDL_GetStringBoolean。'' なら ADefault、'0' で始まるか 'false'（大文字小文字を
  区別しない）なら False、それ以外は True。 }
function PMLStringBoolean(const AValue: String; ADefault: Boolean): Boolean;
{ SDL_GetStringInteger。'' なら ADefault、'false' は 0、'true' は 1、'-' か数字で
  始まれば C の atoi、それ以外は ADefault。 }
function PMLStringInteger(const AValue: String; ADefault: Integer): Integer;
{ C の strtoll(s, NULL, 0)。先頭の空白、符号、'0x' で 16 進、'0' で 8 進。読める
  ところまで読み、何も読めなければ 0。範囲を超えたら High / Low(Int64)。 }
function PMLStrToInt64C(const AValue: String): Int64;
{ C の strtod（"C" ロケール）。先頭の空白、符号、10 進（小数点と指数）、'0x' の 16 進
  （小数点と 'p' の指数）、inf / infinity / nan。読めるところまで読み、何も読めなければ 0。 }
function PMLStrToFloatC(const AValue: String): Double;

implementation

uses
  Math;

procedure CheckName(const AName: String);
begin
  if AName = '' then
    raise EPMLArgument.Create('property name must not be empty');
end;

function IsCSpace(C: Char): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #11) or (C = #12) or (C = #13);
end;

function HexDigitValue(C: Char): Integer;
begin
  if (C >= '0') and (C <= '9') then
    Result := Ord(C) - Ord('0')
  else if (C >= 'a') and (C <= 'f') then
    Result := Ord(C) - Ord('a') + 10
  else if (C >= 'A') and (C <= 'F') then
    Result := Ord(C) - Ord('A') + 10
  else
    Result := -1;
end;

{ C の printf("%f")。

  PORT-NOTE: SDL_GetStringProperty は小数を "%f" で文字列にする。FPC の Format('%.6f') は
  ほとんど同じだが、ちょうど半分の値の丸め（C は偶数へ。123456.7890625 は C が …062、
  FPC が …063）と、-0・inf・nan の書き方が違う。後の 3 つだけ C に揃えた。 }
function FormatFloatC(AValue: Single): String;
var
  D: Double;
  FS: TFormatSettings;
begin
  D := AValue;
  if IsNaN(D) then
    Exit('nan');
  if IsInfinite(D) then
  begin
    if D > 0 then
      Exit('inf');
    Exit('-inf');
  end;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := #0;
  Result := Format('%.6f', [D], FS);
  if ((PQWord(@D)^ shr 63) = 1) and (Result[1] <> '-') then
    Result := '-' + Result;
end;

// C の (Sint64)SDL_round(x)。範囲外と NaN は x86 のキャストと同じく Low(Int64)。
function RoundCToInt64(AValue: Single): Int64;
var
  D: Double;
begin
  D := AValue;
  if IsNaN(D) then
    Exit(Low(Int64));
  if (D >= 9223372036854775807.0) or (D <= -9223372036854775807.0) then
    Exit(Low(Int64));
  if D >= 0 then
    Result := Trunc(D + 0.5)
  else
    Result := -Trunc(-D + 0.5);
end;

// C の (float)d。大きすぎれば無限大（FPC の代入は EOverflow を投げる）。
function DoubleToSingleC(D: Double): Single;
begin
  if IsNaN(D) then
    Result := NaN
  else if D > MaxSingle then
    Result := Infinity
  else if D < -MaxSingle then
    Result := NegInfinity
  else
    Result := D;
end;

{ TPMLHintValue }

class function TPMLHintValue.Unset: TPMLHintValue;
begin
  Result.IsSet := False;
  Result.Value := '';
end;

class function TPMLHintValue.Make(const AValue: String): TPMLHintValue;
begin
  Result.IsSet := True;
  Result.Value := AValue;
end;

{ TPMLProperties }

constructor TPMLProperties.Create;
begin
  inherited Create;
  FLock := TPMLMutex.Create;
end;

destructor TPMLProperties.Destroy;
var
  I: Integer;
begin
  FLock.Lock;
  try
    for I := 0 to High(FEntries) do
      if (FEntries[I].Kind = TPMLPropertyType.Pointer_) and Assigned(FEntries[I].Cleanup) then
        FEntries[I].Cleanup(FEntries[I].PtrValue);
    SetLength(FEntries, 0);
  finally
    FLock.Unlock;
  end;
  FLock.Free;
  inherited Destroy;
end;

function TPMLProperties.IndexOf(const AName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FEntries) do
    if FEntries[I].Name = AName then
      Exit(I);
  Result := -1;
end;

procedure TPMLProperties.Put(const AName: String; const AEntry: TEntry);
var
  I: Integer;
  E, Old: TEntry;
begin
  E := AEntry;
  E.Name := AName;
  I := IndexOf(AName);
  if I >= 0 then
  begin
    Old := FEntries[I];
    FEntries[I] := E;
    if (Old.Kind = TPMLPropertyType.Pointer_) and Assigned(Old.Cleanup) then
      Old.Cleanup(Old.PtrValue);
  end
  else
  begin
    SetLength(FEntries, Length(FEntries) + 1);
    FEntries[High(FEntries)] := E;
  end;
end;

{ PORT-NOTE(bug): SDL の CopyOneProperty は構造体を丸ごと写し、数を文字列で読んだときの
  置き場（string_storage）まで写し元と共有する（D-54）。papimela は値の文字列が String で、
  その置き場を持たないので、要素を写すだけでよい。 }
procedure TPMLProperties.CopyTo(ADest: TPMLProperties);
var
  I: Integer;
begin
  if (ADest = nil) or (ADest = Self) then
    raise EPMLArgument.Create('CopyTo needs another properties object');
  Lock;
  ADest.Lock;
  try
    for I := 0 to High(FEntries) do
    begin
      // 後始末付きのポインタは、中身を複製する方法が分からないので写さない（SDL と同じ）
      if (FEntries[I].Kind = TPMLPropertyType.Pointer_) and Assigned(FEntries[I].Cleanup) then
        Continue;
      ADest.Put(FEntries[I].Name, FEntries[I]);
    end;
  finally
    ADest.Unlock;
    Unlock;
  end;
end;

procedure TPMLProperties.Lock;
begin
  FLock.Lock;
end;

procedure TPMLProperties.Unlock;
begin
  FLock.Unlock;
end;

procedure TPMLProperties.SetPointer(const AName: String; AValue: Pointer;
  ACleanup: TPMLPropertyCleanup);
var
  Entry: TEntry;
begin
  CheckName(AName);
  if AValue = nil then
  begin
    if Assigned(ACleanup) then
      ACleanup(nil);
    Clear(AName);
    Exit;
  end;
  Entry := Default(TEntry);
  Entry.Kind := TPMLPropertyType.Pointer_;
  Entry.PtrValue := AValue;
  Entry.Cleanup := ACleanup;
  Lock;
  try
    Put(AName, Entry);
  finally
    Unlock;
  end;
end;

procedure TPMLProperties.SetString(const AName, AValue: String);
var
  Entry: TEntry;
begin
  CheckName(AName);
  Entry := Default(TEntry);
  Entry.Kind := TPMLPropertyType.String_;
  Entry.StrValue := AValue;
  Lock;
  try
    Put(AName, Entry);
  finally
    Unlock;
  end;
end;

procedure TPMLProperties.SetNumber(const AName: String; AValue: Int64);
var
  Entry: TEntry;
begin
  CheckName(AName);
  Entry := Default(TEntry);
  Entry.Kind := TPMLPropertyType.Number;
  Entry.NumValue := AValue;
  Lock;
  try
    Put(AName, Entry);
  finally
    Unlock;
  end;
end;

procedure TPMLProperties.SetFloat(const AName: String; AValue: Single);
var
  Entry: TEntry;
begin
  CheckName(AName);
  Entry := Default(TEntry);
  Entry.Kind := TPMLPropertyType.Float;
  Entry.FltValue := AValue;
  Lock;
  try
    Put(AName, Entry);
  finally
    Unlock;
  end;
end;

procedure TPMLProperties.SetBoolean(const AName: String; AValue: Boolean);
var
  Entry: TEntry;
begin
  CheckName(AName);
  Entry := Default(TEntry);
  Entry.Kind := TPMLPropertyType.Boolean_;
  Entry.BoolValue := AValue;
  Lock;
  try
    Put(AName, Entry);
  finally
    Unlock;
  end;
end;

function TPMLProperties.Has(const AName: String): Boolean;
begin
  Result := PropertyType(AName) <> TPMLPropertyType.Invalid;
end;

function TPMLProperties.PropertyType(const AName: String): TPMLPropertyType;
var
  I: Integer;
begin
  Result := TPMLPropertyType.Invalid;
  if AName = '' then
    Exit;
  Lock;
  try
    I := IndexOf(AName);
    if I >= 0 then
      Result := FEntries[I].Kind;
  finally
    Unlock;
  end;
end;

function TPMLProperties.GetPointer(const AName: String; ADefault: Pointer): Pointer;
var
  I: Integer;
begin
  Result := ADefault;
  if AName = '' then
    Exit;
  Lock;
  try
    I := IndexOf(AName);
    if (I >= 0) and (FEntries[I].Kind = TPMLPropertyType.Pointer_) then
      Result := FEntries[I].PtrValue;
  finally
    Unlock;
  end;
end;

function TPMLProperties.GetString(const AName: String; const ADefault: String): String;
var
  I: Integer;
begin
  Result := ADefault;
  if AName = '' then
    Exit;
  Lock;
  try
    I := IndexOf(AName);
    if I < 0 then
      Exit;
    case FEntries[I].Kind of
      TPMLPropertyType.String_ : Result := FEntries[I].StrValue;
      TPMLPropertyType.Number  : Result := IntToStr(FEntries[I].NumValue);
      TPMLPropertyType.Float   : Result := FormatFloatC(FEntries[I].FltValue);
      TPMLPropertyType.Boolean_:
        if FEntries[I].BoolValue then
          Result := 'true'
        else
          Result := 'false';
    else
      ;
    end;
  finally
    Unlock;
  end;
end;

function TPMLProperties.GetNumber(const AName: String; ADefault: Int64): Int64;
var
  I: Integer;
begin
  Result := ADefault;
  if AName = '' then
    Exit;
  Lock;
  try
    I := IndexOf(AName);
    if I < 0 then
      Exit;
    case FEntries[I].Kind of
      TPMLPropertyType.String_ : Result := PMLStrToInt64C(FEntries[I].StrValue);
      TPMLPropertyType.Number  : Result := FEntries[I].NumValue;
      TPMLPropertyType.Float   : Result := RoundCToInt64(FEntries[I].FltValue);
      TPMLPropertyType.Boolean_: Result := Ord(FEntries[I].BoolValue);
    else
      ;
    end;
  finally
    Unlock;
  end;
end;

function TPMLProperties.GetFloat(const AName: String; ADefault: Single): Single;
var
  I: Integer;
begin
  Result := ADefault;
  if AName = '' then
    Exit;
  Lock;
  try
    I := IndexOf(AName);
    if I < 0 then
      Exit;
    case FEntries[I].Kind of
      TPMLPropertyType.String_ : Result := DoubleToSingleC(PMLStrToFloatC(FEntries[I].StrValue));
      TPMLPropertyType.Number  : Result := FEntries[I].NumValue;
      TPMLPropertyType.Float   : Result := FEntries[I].FltValue;
      TPMLPropertyType.Boolean_: Result := Ord(FEntries[I].BoolValue);
    else
      ;
    end;
  finally
    Unlock;
  end;
end;

function TPMLProperties.GetBoolean(const AName: String; ADefault: Boolean): Boolean;
var
  I: Integer;
begin
  Result := ADefault;
  if AName = '' then
    Exit;
  Lock;
  try
    I := IndexOf(AName);
    if I < 0 then
      Exit;
    case FEntries[I].Kind of
      TPMLPropertyType.String_ : Result := PMLStringBoolean(FEntries[I].StrValue, ADefault);
      TPMLPropertyType.Number  : Result := FEntries[I].NumValue <> 0;
      // NaN を比較に渡すと例外になり得るので先に分ける（C では NaN != 0 は真）
      TPMLPropertyType.Float   : Result := IsNaN(FEntries[I].FltValue) or (FEntries[I].FltValue <> 0);
      TPMLPropertyType.Boolean_: Result := FEntries[I].BoolValue;
    else
      ;
    end;
  finally
    Unlock;
  end;
end;

procedure TPMLProperties.Clear(const AName: String);
var
  I, J: Integer;
  Old: TEntry;
begin
  if AName = '' then
    Exit;
  Lock;
  try
    I := IndexOf(AName);
    if I < 0 then
      Exit;
    Old := FEntries[I];
    for J := I to High(FEntries) - 1 do
      FEntries[J] := FEntries[J + 1];
    SetLength(FEntries, Length(FEntries) - 1);
    if (Old.Kind = TPMLPropertyType.Pointer_) and Assigned(Old.Cleanup) then
      Old.Cleanup(Old.PtrValue);
  finally
    Unlock;
  end;
end;

function TPMLProperties.Count: Integer;
begin
  Lock;
  try
    Result := Length(FEntries);
  finally
    Unlock;
  end;
end;

procedure TPMLProperties.Enumerate(ACallback: TPMLPropertyEnumerator);
var
  I: Integer;
begin
  if not Assigned(ACallback) then
    raise EPMLArgument.Create('Enumerate needs a callback');
  Lock;
  try
    for I := 0 to High(FEntries) do
      ACallback(Self, FEntries[I].Name);
  finally
    Unlock;
  end;
end;

{ ---- 文字列の読み方 ---- }

function PMLStringBoolean(const AValue: String; ADefault: Boolean): Boolean;
begin
  if AValue = '' then
    Result := ADefault
  else if (AValue[1] = '0') or SameText(AValue, 'false') then
    Result := False
  else
    Result := True;
end;

// C の atoi（10 進だけ）。int に収まらなければ端で止める。
function AtoiC(const AValue: String): Integer;
var
  I, N: Integer;
  Neg: Boolean;
  Acc: Int64;
begin
  N := Length(AValue);
  I := 1;
  while (I <= N) and IsCSpace(AValue[I]) do
    Inc(I);
  Neg := False;
  if (I <= N) and ((AValue[I] = '-') or (AValue[I] = '+')) then
  begin
    Neg := AValue[I] = '-';
    Inc(I);
  end;
  Acc := 0;
  while (I <= N) and (AValue[I] >= '0') and (AValue[I] <= '9') do
  begin
    if Acc <= Int64(High(Integer)) + 1 then
      Acc := Acc * 10 + (Ord(AValue[I]) - Ord('0'));
    Inc(I);
  end;
  if Neg then
    Acc := -Acc;
  if Acc > High(Integer) then
    Result := High(Integer)
  else if Acc < Low(Integer) then
    Result := Low(Integer)
  else
    Result := Integer(Acc);
end;

function PMLStringInteger(const AValue: String; ADefault: Integer): Integer;
begin
  if AValue = '' then
    Exit(ADefault);
  if SameText(AValue, 'false') then
    Exit(0);
  if SameText(AValue, 'true') then
    Exit(1);
  if (AValue[1] = '-') or ((AValue[1] >= '0') and (AValue[1] <= '9')) then
    Exit(AtoiC(AValue));
  Result := ADefault;
end;

function PMLStrToInt64C(const AValue: String): Int64;
var
  I, N, D, Base: Integer;
  Neg, Over: Boolean;
  Acc, Limit: QWord;
begin
  N := Length(AValue);
  I := 1;
  while (I <= N) and IsCSpace(AValue[I]) do
    Inc(I);
  Neg := False;
  if (I <= N) and ((AValue[I] = '-') or (AValue[I] = '+')) then
  begin
    Neg := AValue[I] = '-';
    Inc(I);
  end;
  Base := 10;
  if (I + 2 <= N) and (AValue[I] = '0') and ((AValue[I + 1] = 'x') or (AValue[I + 1] = 'X'))
    and (HexDigitValue(AValue[I + 2]) >= 0) then
  begin
    Base := 16;
    Inc(I, 2);
  end
  else if (I <= N) and (AValue[I] = '0') then
    Base := 8;
  if Neg then
    Limit := QWord(High(Int64)) + 1
  else
    Limit := QWord(High(Int64));
  Acc := 0;
  Over := False;
  while I <= N do
  begin
    D := HexDigitValue(AValue[I]);
    if (D < 0) or (D >= Base) then
      Break;
    if not Over then
    begin
      if Acc > (Limit - QWord(D)) div QWord(Base) then
        Over := True
      else
        Acc := Acc * QWord(Base) + QWord(D);
    end;
    Inc(I);
  end;
  if Over then
  begin
    if Neg then
      Exit(Low(Int64));
    Exit(High(Int64));
  end;
  if not Neg then
    Exit(Int64(Acc));
  if Acc = QWord(High(Int64)) + 1 then
    Exit(Low(Int64));
  Result := -Int64(Acc);
end;

function PMLStrToFloatC(const AValue: String): Double;
var
  I, N, D, FracDigits, Exp, ExpSign: Integer;
  Neg, Seen: Boolean;
  Rest, Txt: String;
  V: Double;
  Code: Integer;

  function DigitAt(AIndex: Integer): Boolean;
  begin
    Result := (AIndex <= N) and (AValue[AIndex] >= '0') and (AValue[AIndex] <= '9');
  end;

  function Signed(AMagnitude: Double): Double;
  begin
    if Neg then
      Result := -AMagnitude
    else
      Result := AMagnitude;
  end;

begin
  Result := 0;
  N := Length(AValue);
  I := 1;
  while (I <= N) and IsCSpace(AValue[I]) do
    Inc(I);
  Neg := False;
  if (I <= N) and ((AValue[I] = '-') or (AValue[I] = '+')) then
  begin
    Neg := AValue[I] = '-';
    Inc(I);
  end;

  Rest := LowerCase(Copy(AValue, I, 8));
  if Copy(Rest, 1, 3) = 'inf' then
    Exit(Signed(Infinity));
  if Copy(Rest, 1, 3) = 'nan' then
    Exit(NaN);

  // 16 進（"0x1.8p1"）
  if (I + 2 <= N) and (AValue[I] = '0') and ((AValue[I + 1] = 'x') or (AValue[I + 1] = 'X'))
    and ((HexDigitValue(AValue[I + 2]) >= 0)
      or ((AValue[I + 2] = '.') and (I + 3 <= N) and (HexDigitValue(AValue[I + 3]) >= 0))) then
  begin
    Inc(I, 2);
    V := 0;
    FracDigits := 0;
    Seen := False;
    while (I <= N) and (HexDigitValue(AValue[I]) >= 0) do
    begin
      V := V * 16 + HexDigitValue(AValue[I]);
      Seen := True;
      Inc(I);
    end;
    if (I <= N) and (AValue[I] = '.') then
    begin
      Inc(I);
      while (I <= N) and (HexDigitValue(AValue[I]) >= 0) do
      begin
        V := V * 16 + HexDigitValue(AValue[I]);
        Inc(FracDigits);
        Seen := True;
        Inc(I);
      end;
    end;
    if not Seen then
      Exit(0);
    Exp := 0;
    if (I <= N) and ((AValue[I] = 'p') or (AValue[I] = 'P')) then
    begin
      ExpSign := 1;
      D := I + 1;
      if (D <= N) and ((AValue[D] = '+') or (AValue[D] = '-')) then
      begin
        if AValue[D] = '-' then
          ExpSign := -1;
        Inc(D);
      end;
      if DigitAt(D) then
      begin
        while DigitAt(D) do
        begin
          if Exp < 10000 then
            Exp := Exp * 10 + (Ord(AValue[D]) - Ord('0'));
          Inc(D);
        end;
        Exp := ExpSign * Exp;
      end;
    end;
    try
      Exit(Signed(Ldexp(V, Exp - 4 * FracDigits)));
    except
      on EOverflow do
        Exit(Signed(Infinity));
      on EMathError do
        Exit(0);
    end;
  end;

  // 10 進。読めた部分だけを Txt に集めて Val に渡す。
  Txt := '';
  Seen := False;
  while DigitAt(I) do
  begin
    Txt := Txt + AValue[I];
    Seen := True;
    Inc(I);
  end;
  if (I <= N) and (AValue[I] = '.') then
  begin
    Txt := Txt + '.';
    Inc(I);
    while DigitAt(I) do
    begin
      Txt := Txt + AValue[I];
      Seen := True;
      Inc(I);
    end;
  end;
  if not Seen then
    Exit(0);
  if (I <= N) and ((AValue[I] = 'e') or (AValue[I] = 'E')) then
  begin
    D := I + 1;
    if (D <= N) and ((AValue[D] = '+') or (AValue[D] = '-')) then
      Inc(D);
    if DigitAt(D) then
    begin
      Txt := Txt + Copy(AValue, I, D - I);
      while DigitAt(D) do
      begin
        Txt := Txt + AValue[D];
        Inc(D);
      end;
    end;
  end;
  if Txt[1] = '.' then
    Txt := '0' + Txt;
  try
    Val(Txt, V, Code);
  except
    on EOverflow do
      Exit(Signed(Infinity));
    on EMathError do
      Exit(0);
  end;
  if Code <> 0 then
    Exit(0);
  Result := Signed(V);
end;

{ TPMLHints }

// FPC の GetEnvironmentVariable は「無い」と「空」を区別しないので、libc の getenv を使う。
function c_getenv(AName: PAnsiChar): PAnsiChar; cdecl; external 'c' name 'getenv';

function EnvValue(const AName: String): TPMLHintValue;
var
  P: PAnsiChar;
begin
  P := c_getenv(PAnsiChar(AName));
  if P = nil then
    Result := TPMLHintValue.Unset
  else
    Result := TPMLHintValue.Make(String(P));
end;

function SameHintValue(const A, B: TPMLHintValue): Boolean;
begin
  Result := (A.IsSet = B.IsSet) and ((not A.IsSet) or (A.Value = B.Value));
end;

constructor TPMLHints.Create;
begin
  inherited Create;
  FLock := TPMLMutex.Create;
end;

destructor TPMLHints.Destroy;
begin
  SetLength(FEntries, 0);
  FLock.Free;
  inherited Destroy;
end;

function TPMLHints.IndexOf(const AName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FEntries) do
    if FEntries[I].Name = AName then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

function TPMLHints.Effective(const AName: String): TPMLHintValue;
var
  Env: TPMLHintValue;
  I: Integer;
begin
  Env := EnvValue(AName);
  FLock.Lock;
  try
    I := IndexOf(AName);
    // 環境変数が無いか、Override で置いたなら置いた値。そうでなければ環境変数（SDL_GetHint）
    if (not Env.IsSet) or ((I >= 0) and (FEntries[I].Priority = TPMLHintPriority.Override)) then
    begin
      if I >= 0 then
        Result := FEntries[I].Stored
      else
        Result := TPMLHintValue.Unset;
    end
    else
      Result := Env;
  finally
    FLock.Unlock;
  end;
end;

{ PORT-NOTE(bug): SDL は呼び出しの並びを辿りながら呼び、次の要素を先に覚えておくだけなので、
  呼び出しの中で次の要素を外すと解放した要素を辿る。papimela は並びの写しを辿る。 }
procedure TPMLHints.Notify(const AName: String; const AOld, ANew: TPMLHintValue);
var
  I, J: Integer;
  Snap: array of TPMLHintCallback;
begin
  I := IndexOf(AName);
  if I < 0 then
    Exit;
  Snap := Copy(FEntries[I].Callbacks);
  for J := 0 to High(Snap) do
    Snap[J](AName, AOld, ANew);
end;

{ PORT-NOTE(bug): SDL_SetHintWithPriority と SDL_ResetHint は、知らせを出すかの判断と「前の値」に
  置いてあった値（hint->value）を使う。環境変数が効いていると、前の値を (null) と誤って知らせ、
  効いている値が変わらない Reset でも知らせる（D-57）。papimela は前後の効いている値で決める。 }
function TPMLHints.SetHint(const AName, AValue: String; APriority: TPMLHintPriority): Boolean;
var
  Env: TPMLHintValue;
  I: Integer;
  OldValue, NewValue: TPMLHintValue;
begin
  CheckName(AName);
  Env := EnvValue(AName);
  if Env.IsSet and (APriority <> TPMLHintPriority.Override) then
    Exit(False);
  FLock.Lock;
  try
    I := IndexOf(AName);
    if I >= 0 then
    begin
      if APriority < FEntries[I].Priority then
      begin
        Result := False;
        Exit;
      end;
      OldValue := Effective(AName);
      FEntries[I].Stored := TPMLHintValue.Make(AValue);
      FEntries[I].Priority := APriority;
      NewValue := Effective(AName);
      if not SameHintValue(OldValue, NewValue) then
        Notify(AName, OldValue, NewValue);
    end
    else
    begin
      SetLength(FEntries, Length(FEntries) + 1);
      FEntries[High(FEntries)].Name := AName;
      FEntries[High(FEntries)].Stored := TPMLHintValue.Make(AValue);
      FEntries[High(FEntries)].Priority := APriority;
      FEntries[High(FEntries)].Callbacks := nil;
    end;
    Result := True;
  finally
    FLock.Unlock;
  end;
end;

function TPMLHints.ResetHint(const AName: String): Boolean;
var
  I: Integer;
  OldValue, NewValue: TPMLHintValue;
begin
  CheckName(AName);
  FLock.Lock;
  try
    I := IndexOf(AName);
    if I < 0 then
    begin
      Result := False;
      Exit;
    end;
    OldValue := Effective(AName);
    FEntries[I].Stored := TPMLHintValue.Unset;
    FEntries[I].Priority := TPMLHintPriority.Default;
    NewValue := Effective(AName);
    if not SameHintValue(OldValue, NewValue) then
      Notify(AName, OldValue, NewValue);
    Result := True;
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLHints.ResetHints;
var
  Names: array of String;
  I: Integer;
begin
  FLock.Lock;
  try
    SetLength(Names, Length(FEntries));
    for I := 0 to High(FEntries) do
      Names[I] := FEntries[I].Name;
  finally
    FLock.Unlock;
  end;
  for I := 0 to High(Names) do
    ResetHint(Names[I]);
end;

function TPMLHints.GetHint(const AName: String): String;
begin
  if AName = '' then
    Exit('');
  Result := Effective(AName).Value;
end;

function TPMLHints.TryGetHint(const AName: String; out AValue: String): Boolean;
var
  V: TPMLHintValue;
begin
  if AName = '' then
  begin
    AValue := '';
    Result := False;
    Exit;
  end;
  V := Effective(AName);
  AValue := V.Value;
  Result := V.IsSet;
end;

function TPMLHints.GetBoolean(const AName: String; ADefault: Boolean): Boolean;
var
  S: String;
begin
  if TryGetHint(AName, S) then
    Result := PMLStringBoolean(S, ADefault)
  else
    Result := ADefault;
end;

procedure TPMLHints.AddCallback(const AName: String; ACallback: TPMLHintCallback);
var
  I, J: Integer;
  V: TPMLHintValue;
begin
  CheckName(AName);
  if not Assigned(ACallback) then
    raise EPMLArgument.Create('AddCallback needs a callback');
  FLock.Lock;
  try
    RemoveCallback(AName, ACallback);
    I := IndexOf(AName);
    if I < 0 then
    begin
      SetLength(FEntries, Length(FEntries) + 1);
      I := High(FEntries);
      FEntries[I].Name := AName;
      FEntries[I].Stored := TPMLHintValue.Unset;
      FEntries[I].Priority := TPMLHintPriority.Default;
      FEntries[I].Callbacks := nil;
    end;
    // 新しいものを先頭に（SDL と同じく、新しく足したものから呼ぶ）
    SetLength(FEntries[I].Callbacks, Length(FEntries[I].Callbacks) + 1);
    for J := High(FEntries[I].Callbacks) downto 1 do
      FEntries[I].Callbacks[J] := FEntries[I].Callbacks[J - 1];
    FEntries[I].Callbacks[0] := ACallback;
    V := Effective(AName);
    ACallback(AName, V, V);
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLHints.RemoveCallback(const AName: String; ACallback: TPMLHintCallback);
var
  I, J: Integer;
begin
  if AName = '' then
    Exit;
  FLock.Lock;
  try
    I := IndexOf(AName);
    if I < 0 then
      Exit;
    for J := 0 to High(FEntries[I].Callbacks) do
      if (TMethod(FEntries[I].Callbacks[J]).Code = TMethod(ACallback).Code) and (TMethod(FEntries[I].Callbacks[J]).Data = TMethod(ACallback).Data) then
      begin
        if J < High(FEntries[I].Callbacks) then
          Move(FEntries[I].Callbacks[J + 1], FEntries[I].Callbacks[J], (High(FEntries[I].Callbacks) - J) * SizeOf(TPMLHintCallback));
        SetLength(FEntries[I].Callbacks, Length(FEntries[I].Callbacks) - 1);
        Break;
      end;
  finally
    FLock.Unlock;
  end;
end;

end.
