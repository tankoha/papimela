{
  PaPiMeLa.Joystick.GUID — ジョイスティックの GUID

  Origin : ported from SDL (src/joystick/SDL_joystick.c, src/stdlib/SDL_crc16.c, src/SDL_guid.c)
           Scope: SDL_GUID と、ジョイスティックの GUID の作り方（SDL_CreateJoystickGUID、
           SDL_CreateJoystickGUIDForName）、読み取り（SDL_GetJoystickGUIDInfo）、各欄の書き換え
           （SDL_SetJoystickGUID* の 4 つ）、ドライバの印の判定（'v' の仮想など）、
           SDL_crc16、GUID と文字列の相互変換（SDL_GUIDToString / SDL_StringToGUID）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.6、§11 #59

  WHAT:
    128 ビットの GUID と、ジョイスティックの GUID の決まった並び:
      16 ビットのバス、16 ビットの名前の CRC、16 ビットのベンダー、16 ビットの 0、
      16 ビットのプロダクト、16 ビットの 0、16 ビットのバージョン、
      8 ビットのドライバの印（'h' = HIDAPI、'x' = XInput、'v' = 仮想など）、8 ビットのドライバ固有の値。
    ベンダーの無い GUID は、バスと CRC の後ろに名前の先頭 11 文字を置く。

  WHY:
    GUID はゲームパッドのマッピングの鍵であり、バックエンドが作ってコアが読む。両方から
    使うので、バックエンドの抽象（Joystick.Backend）とは別のユニットにした。

  RESOLVED:
    - 16 ビットの欄はリトルエンディアンで置く（SDL の SDL_Swap16LE。異なる CPU で同じ GUID になる）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Joystick.GUID;

{$I papimela.inc}

interface

uses
  SysUtils;

type
  { 128 ビットの GUID（SDL_GUID）。 }
  TPMLGUID = record
    Data: array[0..15] of Byte;
  end;

const
  // 接続のバス（SDL_HARDWARE_BUS_xxx。GUID の先頭 16 ビット）。
  PML_HARDWARE_BUS_UNKNOWN   = $00;
  PML_HARDWARE_BUS_USB       = $03;
  PML_HARDWARE_BUS_BLUETOOTH = $05;
  PML_HARDWARE_BUS_VIRTUAL   = $FF;

// SDL_crc16（CRC-16/ARC。ジョイスティックの GUID が頼る。変えてはいけない）。
function PMLCRC16(ACRC: Word; AData: Pointer; ALength: PtrInt): Word; overload;
function PMLCRC16(ACRC: Word; const AText: String): Word; overload;

{ ジョイスティックの GUID を作る（SDL_CreateJoystickGUID）。ベンダー名とプロダクト名が両方あれば
  「ベンダー名 + 空白 + プロダクト名」の CRC、プロダクト名だけなら その CRC。AVendor が 0 のときは
  ベンダー欄を使わず、名前の先頭を GUID の後半へ置く。 }
function PMLCreateJoystickGUID(ABus, AVendor, AProduct, AVersion: Word;
  const AVendorName, AProductName: String; ADriverSignature, ADriverData: Byte): TPMLGUID;
{ 名前だけの GUID（SDL_CreateJoystickGUIDForName。バスは不明、ベンダー・プロダクトは 0）。 }
function PMLCreateJoystickGUIDForName(const AName: String): TPMLGUID;

{ 標準の並びの GUID からベンダー・プロダクト・バージョン・名前の CRC を取り出す
  （SDL_GetJoystickGUIDInfo）。標準でなければ 0 を返す。 }
procedure PMLGetJoystickGUIDInfo(const AGUID: TPMLGUID; out AVendor, AProduct, AVersion, ACRC: Word);

procedure PMLSetJoystickGUIDVendor(var AGUID: TPMLGUID; AVendor: Word);
procedure PMLSetJoystickGUIDProduct(var AGUID: TPMLGUID; AProduct: Word);
procedure PMLSetJoystickGUIDVersion(var AGUID: TPMLGUID; AVersion: Word);
procedure PMLSetJoystickGUIDCRC(var AGUID: TPMLGUID; ACRC: Word);

// ドライバの印（GUID の 15 バイト目）。
function PMLIsJoystickVirtualGUID(const AGUID: TPMLGUID): Boolean;
function PMLIsJoystickHIDAPIGUID(const AGUID: TPMLGUID): Boolean;
function PMLIsJoystickXInputGUID(const AGUID: TPMLGUID): Boolean;

// GUID と 32 桁の 16 進（小文字）の相互変換（SDL_GUIDToString / SDL_StringToGUID）。
function PMLGUIDToString(const AGUID: TPMLGUID): String;
function PMLStringToGUID(const AText: String): TPMLGUID;
function PMLSameGUID(const A, B: TPMLGUID): Boolean;
function PMLZeroGUID: TPMLGUID;

implementation

function PMLZeroGUID: TPMLGUID;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

function PMLSameGUID(const A, B: TPMLGUID): Boolean;
begin
  Result := CompareByte(A.Data, B.Data, SizeOf(A.Data)) = 0;
end;

function CRC16ForByte(R: Byte): Word;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to 7 do
  begin
    if ((Result xor R) and 1) <> 0 then
      Result := Word($A001 xor (Result shr 1))
    else
      Result := Result shr 1;
    R := R shr 1;
  end;
end;

function PMLCRC16(ACRC: Word; AData: Pointer; ALength: PtrInt): Word;
var
  I: PtrInt;
begin
  Result := ACRC;
  for I := 0 to ALength - 1 do
    Result := CRC16ForByte(Byte(Result) xor PByte(AData)[I]) xor (Result shr 8);
end;

function PMLCRC16(ACRC: Word; const AText: String): Word;
begin
  if AText = '' then
    Result := ACRC
  else
    Result := PMLCRC16(ACRC, @AText[1], Length(AText));
end;

procedure PutWord(var AGUID: TPMLGUID; AIndex: Integer; AValue: Word);
begin
  AGUID.Data[AIndex * 2] := Byte(AValue);
  AGUID.Data[AIndex * 2 + 1] := Byte(AValue shr 8);
end;

function GetWord(const AGUID: TPMLGUID; AIndex: Integer): Word;
begin
  Result := Word(AGUID.Data[AIndex * 2]) or (Word(AGUID.Data[AIndex * 2 + 1]) shl 8);
end;

function PMLCreateJoystickGUID(ABus, AVendor, AProduct, AVersion: Word;
  const AVendorName, AProductName: String; ADriverSignature, ADriverData: Byte): TPMLGUID;
var
  CRC: Word;
  Available, N: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  CRC := 0;
  if (AVendorName <> '') and (AProductName <> '') then
  begin
    CRC := PMLCRC16(CRC, AVendorName);
    CRC := PMLCRC16(CRC, ' ');
    CRC := PMLCRC16(CRC, AProductName);
  end
  else if AProductName <> '' then
    CRC := PMLCRC16(CRC, AProductName);

  PutWord(Result, 0, ABus);
  PutWord(Result, 1, CRC);
  if AVendor <> 0 then
  begin
    PutWord(Result, 2, AVendor);
    PutWord(Result, 3, 0);
    PutWord(Result, 4, AProduct);
    PutWord(Result, 5, 0);
    PutWord(Result, 6, AVersion);
    Result.Data[14] := ADriverSignature;
    Result.Data[15] := ADriverData;
  end
  else
  begin
    Available := SizeOf(Result.Data) - 4;
    if ADriverSignature <> 0 then
    begin
      Dec(Available, 2);
      Result.Data[14] := ADriverSignature;
      Result.Data[15] := ADriverData;
    end;
    if AProductName <> '' then
    begin
      // SDL_strlcpy: Available - 1 文字まで写して終端を置く
      N := Length(AProductName);
      if N > Available - 1 then
        N := Available - 1;
      if N > 0 then
        Move(AProductName[1], Result.Data[4], N);
    end;
  end;
end;

function PMLCreateJoystickGUIDForName(const AName: String): TPMLGUID;
begin
  Result := PMLCreateJoystickGUID(PML_HARDWARE_BUS_UNKNOWN, 0, 0, 0, '', AName, 0, 0);
end;

procedure PMLGetJoystickGUIDInfo(const AGUID: TPMLGUID; out AVendor, AProduct, AVersion, ACRC: Word);
var
  Bus: Word;
begin
  Bus := GetWord(AGUID, 0);
  AVendor := 0;
  AProduct := 0;
  AVersion := 0;
  ACRC := 0;
  if ((Bus < Ord(' ')) or (Bus = PML_HARDWARE_BUS_VIRTUAL)) and (GetWord(AGUID, 3) = 0)
  and (GetWord(AGUID, 5) = 0) then
  begin
    // 標準の並び
    AVendor := GetWord(AGUID, 2);
    AProduct := GetWord(AGUID, 4);
    AVersion := GetWord(AGUID, 6);
    ACRC := GetWord(AGUID, 1);
  end
  else if (Bus < Ord(' ')) or (Bus = PML_HARDWARE_BUS_VIRTUAL) then
    // ベンダー・プロダクト不明の並び
    ACRC := GetWord(AGUID, 1);
end;

procedure PMLSetJoystickGUIDVendor(var AGUID: TPMLGUID; AVendor: Word);
begin
  PutWord(AGUID, 2, AVendor);
end;

procedure PMLSetJoystickGUIDProduct(var AGUID: TPMLGUID; AProduct: Word);
begin
  PutWord(AGUID, 4, AProduct);
end;

procedure PMLSetJoystickGUIDVersion(var AGUID: TPMLGUID; AVersion: Word);
begin
  PutWord(AGUID, 6, AVersion);
end;

procedure PMLSetJoystickGUIDCRC(var AGUID: TPMLGUID; ACRC: Word);
begin
  PutWord(AGUID, 1, ACRC);
end;

function PMLIsJoystickVirtualGUID(const AGUID: TPMLGUID): Boolean;
begin
  Result := AGUID.Data[14] = Ord('v');
end;

function PMLIsJoystickHIDAPIGUID(const AGUID: TPMLGUID): Boolean;
begin
  Result := AGUID.Data[14] = Ord('h');
end;

function PMLIsJoystickXInputGUID(const AGUID: TPMLGUID): Boolean;
begin
  Result := (AGUID.Data[14] = Ord('x')) and (GetWord(AGUID, 0) = PML_HARDWARE_BUS_USB);
end;

function PMLGUIDToString(const AGUID: TPMLGUID): String;
const
  Hex: array[0..15] of Char = '0123456789abcdef';
var
  I: Integer;
begin
  SetLength(Result, 32);
  for I := 0 to 15 do
  begin
    Result[I * 2 + 1] := Hex[AGUID.Data[I] shr 4];
    Result[I * 2 + 2] := Hex[AGUID.Data[I] and $F];
  end;
end;

function Nibble(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := 0;     // SDL は 16 進でない文字を 0 として読む
  end;
end;

{ SDL_StringToGUID。長さは偶数に切り捨て、16 バイトまで。16 進でない文字は 0 として読む。 }
function PMLStringToGUID(const AText: String): TPMLGUID;
var
  I, Len: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Len := Length(AText) and not 1;
  I := 0;
  while (I * 2 < Len) and (I < 16) do
  begin
    Result.Data[I] := Byte(Nibble(AText[I * 2 + 1]) * 16 + Nibble(AText[I * 2 + 2]));
    Inc(I);
  end;
end;

end.
