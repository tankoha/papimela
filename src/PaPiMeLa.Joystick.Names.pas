{
  PaPiMeLa.Joystick.Names — 機器の名前の整え方

  Origin : ported from SDL (src/SDL_utils.c, src/joystick/SDL_joystick.c)
           Scope: SDL_CreateDeviceName（ベンダー名と製品名を 1 つの名前にする。製造元の長い名前の置き換え、
           重複した空白と製造元名の削除、名前が無いときの種類による名前）、SDL_CreateJoystickName
           （コントローラの表にある機器は表の名前、無ければ SDL_CreateDeviceName で既定の名前が Controller）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #60

  WHAT:
    Linux のバックエンドが、evdev の名前（製品名だけ）から、アプリに見せる名前を作る。

  RESOLVED:
    - SDL の「置き換えの文字列が元より長いときは何もしない」の分岐（FIXME）は、置き換えの表に
      そういう行が無いので起きない。同じく何もしない
    - 製造元名の削除のループは、削除したあとも元の長さで回るが、削除したらすぐ抜けるので結果は同じ

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Joystick.Names;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Joystick.Tables,
  PaPiMeLa.Gamepad.Mapping;

type
  // ベンダーとプロダクトから、ゲームパッドの種類（SDL_GetGamepadTypeFromVIDPID(…, NULL, true)）を答える。
  TPMLGamepadTypeOfVIDPID = function(AVendor, AProduct: Word): TPMLGamepadType of object;

{ SDL_CreateDeviceName。名前が決まらなければ ''（SDL の NULL）。ATypeOf は nil でもよい（種類は Standard）。 }
function PMLCreateDeviceName(AVendor, AProduct: Word; const AVendorName, AProductName, ADefaultName: String;
  AHasDefault: Boolean; ATypeOf: TPMLGamepadTypeOfVIDPID): String;

{ SDL_CreateJoystickName。コントローラの表にある機器は表の名前、無ければ SDL_CreateDeviceName（既定の名前は Controller）。 }
function PMLCreateJoystickName(AVendor, AProduct: Word; const AVendorName, AProductName: String;
  ATypeOf: TPMLGamepadTypeOfVIDPID): String;

implementation

type
  TReplacement = record
    Prefix, Replacement: String;
  end;

const
  Replacements: array[0..14] of TReplacement = (
    (Prefix: '(Standard system devices) '; Replacement: ''),
    (Prefix: '8BitDo Tech Ltd'; Replacement: '8BitDo'),
    (Prefix: 'ASTRO Gaming'; Replacement: 'ASTRO'),
    (Prefix: 'Bensussen Deutsch & Associates,Inc.(BDA)'; Replacement: 'BDA'),
    (Prefix: 'Guangzhou Chicken Run Network Technology Co., Ltd.'; Replacement: 'GameSir'),
    (Prefix: 'HORI CO.,LTD.'; Replacement: 'HORI'),
    (Prefix: 'HORI CO.,LTD'; Replacement: 'HORI'),
    (Prefix: 'Mad Catz Inc.'; Replacement: 'Mad Catz'),
    (Prefix: 'Nintendo Co., Ltd.'; Replacement: 'Nintendo'),
    (Prefix: 'NVIDIA Corporation '; Replacement: ''),
    (Prefix: 'Performance Designed Products'; Replacement: 'PDP'),
    (Prefix: 'QANBA USA, LLC'; Replacement: 'Qanba'),
    (Prefix: 'QANBA USA,LLC'; Replacement: 'Qanba'),
    (Prefix: 'Voyetra Turtle Beach,Inc.'; Replacement: 'Turtle Beach'),
    (Prefix: 'Unknown '; Replacement: ''));

// 先頭から、大小文字を見ずに同じ文字がいくつ続くか（PrefixMatch。A は 0 始まりの位置 AStart から）
function PrefixMatch(const A: String; AStart: Integer): Integer;
var
  I: Integer;
begin
  // HORI の「HORl」（小文字の L）を HORI と同じに扱う
  if (Copy(A, 1, 5) = 'HORI ') and (Copy(A, AStart + 1, 5) = 'HORl ') then
    Exit(5);
  Result := 0;
  I := 0;
  while (1 + I <= Length(A)) and (AStart + 1 + I <= Length(A)) do
  begin
    if LowerCase(A[1 + I]) = LowerCase(A[AStart + 1 + I]) then
      Inc(Result)
    else
      Break;
    Inc(I);
  end;
end;

function PMLCreateDeviceName(AVendor, AProduct: Word; const AVendorName, AProductName, ADefaultName: String;
  AHasDefault: Boolean; ATypeOf: TPMLGamepadTypeOfVIDPID): String;
var
  VN, PN, Name: String;
  HaveName: Boolean;
  T: TPMLGamepadType;
  I, MatchLen, Len: Integer;
begin
  VN := AVendorName;
  PN := AProductName;
  while (VN <> '') and (VN[1] = ' ') do
    Delete(VN, 1, 1);
  while (PN <> '') and (PN[1] = ' ') do
    Delete(PN, 1, 1);
  HaveName := True;
  if (VN <> '') and (PN <> '') then
    Name := VN + ' ' + PN
  else if PN <> '' then
    Name := PN
  else if (AVendor <> 0) or (AProduct <> 0) then
  begin
    // 名前が見つからない: 種類で名前を付ける
    if Assigned(ATypeOf) then
      T := ATypeOf(AVendor, AProduct)
    else
      T := TPMLGamepadType.Standard;
    case T of
      TPMLGamepadType.Xbox360: Name := 'Xbox 360 Controller';
      TPMLGamepadType.XboxOne: Name := 'Xbox One Controller';
      TPMLGamepadType.PS3: Name := 'PS3 Controller';
      TPMLGamepadType.PS4: Name := 'PS4 Controller';
      TPMLGamepadType.PS5: Name := 'DualSense Wireless Controller';
      TPMLGamepadType.SwitchPro: Name := 'Nintendo Switch Pro Controller';
      TPMLGamepadType.Steam: Name := 'Steam Controller';
    else
      Name := Format('0x%s/0x%s', [LowerCase(IntToHex(AVendor, 4)), LowerCase(IntToHex(AProduct, 4))]);
    end;
  end
  else if AHasDefault then
    Name := ADefaultName
  else
    HaveName := False;
  if not HaveName then
    Exit('');

  // 終わりの空白を落とす
  Len := Length(Name);
  while (Len > 0) and (Name[Len] = ' ') do
    Dec(Len);
  SetLength(Name, Len);

  // 重なった空白を 1 つにする
  I := 1;
  while I < Len do
    if (Name[I] = ' ') and (Name[I + 1] = ' ') then
    begin
      Delete(Name, I, 1);
      Dec(Len);
    end
    else
      Inc(I);

  // 製造元の置き換え（最初に合ったものだけ）
  for I := 0 to High(Replacements) do
    if SameText(Copy(Name, 1, Length(Replacements[I].Prefix)), Replacements[I].Prefix)
    and (Length(Name) >= Length(Replacements[I].Prefix)) then
    begin
      if Length(Replacements[I].Replacement) <= Length(Replacements[I].Prefix) then
      begin
        Name := Replacements[I].Replacement + Copy(Name, Length(Replacements[I].Prefix) + 1, MaxInt);
        Len := Length(Name);
      end;
      Break;
    end;

  // 製造元名や製品名の重複を落とす（例: Razer Razer Raiju Tournament Edition Wired）
  I := 1;
  while I < Len - 1 do
  begin
    MatchLen := PrefixMatch(Name, I);
    while MatchLen > 0 do
    begin
      if (Name[MatchLen + 1] = ' ') or (Name[MatchLen + 1] = '-') then
      begin
        Delete(Name, 1, MatchLen + 1);
        Break;
      end;
      Dec(MatchLen);
    end;
    if MatchLen > 0 then
      Break;
    Inc(I);
  end;
  Result := Name;
end;

function PMLCreateJoystickName(AVendor, AProduct: Word; const AVendorName, AProductName: String;
  ATypeOf: TPMLGamepadTypeOfVIDPID): String;
begin
  Result := PMLGuessControllerName(AVendor, AProduct);
  if Result <> '' then
    Exit;
  Result := PMLCreateDeviceName(AVendor, AProduct, AVendorName, AProductName, 'Controller', True, ATypeOf);
end;

end.
