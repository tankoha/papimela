{
  PaPiMeLa.Audio.Mixer — 音声の混ぜ合わせ（SDL_MixAudio）

  Origin : ported from SDL (src/audio/SDL_mixer.c)
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #53

  WHAT:
    ASrc の標本に音量を掛けて ADst に足し、範囲に挟む。8 つの形式すべてを扱う。

  WHY:
    SDL_MixAudio の公開窓口。デバイスの中で混ぜる F32 の分は PaPiMeLa.Audio の
    PMLMixFloat32Audio が持つ。

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Audio.Mixer;

{$I papimela.inc}

interface

uses
  PaPiMeLa.Audio.Convert;

{ ASrc の ALen バイトに AVolume（0〜1 が標準）を掛けて ADst に足す（SDL_MixAudio）。
  標本に満たない端のバイトは触らない。音量が丸めて 0 になるとき（1/128 の半分より小さい）は何もしない。
  形式が 8 つの外なら EPMLArgument。 }
procedure PMLMixAudio(ADst, ASrc: Pointer; AFormat: TPMLAudioFormat; ALen: Integer; AVolume: Single);

implementation

uses
  PaPiMeLa.Errors;

const
  MixMaxVolume = 128;   // 音量は 0〜128（MIX_MAXVOLUME）

{ 標本の読み書き。置き場の並びに頼らず、バイトから組み立てる。 }
function ReadU16(P: PByte; ABig: Boolean): Word; inline;
begin
  if ABig then
    Result := (Word(P[0]) shl 8) or P[1]
  else
    Result := (Word(P[1]) shl 8) or P[0];
end;

procedure WriteU16(P: PByte; V: Word; ABig: Boolean); inline;
begin
  if ABig then
  begin
    P[0] := Byte(V shr 8);
    P[1] := Byte(V);
  end
  else
  begin
    P[1] := Byte(V shr 8);
    P[0] := Byte(V);
  end;
end;

function ReadU32(P: PByte; ABig: Boolean): LongWord; inline;
begin
  if ABig then
    Result := (LongWord(P[0]) shl 24) or (LongWord(P[1]) shl 16) or (LongWord(P[2]) shl 8) or P[3]
  else
    Result := (LongWord(P[3]) shl 24) or (LongWord(P[2]) shl 16) or (LongWord(P[1]) shl 8) or P[0];
end;

procedure WriteU32(P: PByte; V: LongWord; ABig: Boolean); inline;
begin
  if ABig then
  begin
    P[0] := Byte(V shr 24);
    P[1] := Byte(V shr 16);
    P[2] := Byte(V shr 8);
    P[3] := Byte(V);
  end
  else
  begin
    P[3] := Byte(V shr 24);
    P[2] := Byte(V shr 16);
    P[1] := Byte(V shr 8);
    P[0] := Byte(V);
  end;
end;

{ SDL_roundf(AVolume * 128) を整数で（半分は 0 から遠い方へ）。 }
function RoundVolume(AVolume: Single): Integer;
var
  X: Single;
  T: Integer;
begin
  X := AVolume * Single(MixMaxVolume);
  T := Trunc(X);
  if X - Single(T) >= Single(0.5) then
    Inc(T)
  else if Single(T) - X >= Single(0.5) then
    Dec(T);
  Result := T;
end;

{ SDL の ADJUST_VOLUME の (type) への切り詰めは、範囲の外では回り込む。 }
function Wrap8(V: Integer): ShortInt; inline;
begin
  Result := ShortInt(V and $FF);
end;

function Wrap16(V: Integer): SmallInt; inline;
begin
  Result := SmallInt(V and $FFFF);
end;

procedure MixS8(D, S: PByte; ALen, AVolume: Integer);
var
  Sample, Sum: Integer;
begin
  while ALen > 0 do
  begin
    Sample := Wrap8((ShortInt(S^) * AVolume) div MixMaxVolume);
    Sum := ShortInt(D^) + Sample;
    if Sum > 127 then
      Sum := 127
    else if Sum < -128 then
      Sum := -128;
    D^ := Byte(Sum);
    Inc(D);
    Inc(S);
    Dec(ALen);
  end;
end;

{ mix8 の表（512 個）は clamp(i - 128, 0, 255)。SDL のコードと全要素が一致することを確かめた。 }
procedure MixU8(D, S: PByte; ALen, AVolume: Integer);
var
  Sample, Idx: Integer;
begin
  while ALen > 0 do
  begin
    Sample := Byte((((Integer(S^) - 128) * AVolume) div MixMaxVolume) + 128);
    Idx := Integer(D^) + Sample - 128;
    if Idx < 0 then
      Idx := 0
    else if Idx > 255 then
      Idx := 255;
    D^ := Byte(Idx);
    Inc(D);
    Inc(S);
    Dec(ALen);
  end;
end;

procedure MixS16(D, S: PByte; ALen, AVolume: Integer; ABig: Boolean);
var
  Sample, Sum: Integer;
begin
  ALen := ALen div 2;
  while ALen > 0 do
  begin
    Sample := Wrap16((SmallInt(ReadU16(S, ABig)) * AVolume) div MixMaxVolume);
    Sum := Sample + SmallInt(ReadU16(D, ABig));
    if Sum > 32767 then
      Sum := 32767
    else if Sum < -32768 then
      Sum := -32768;
    WriteU16(D, Word(SmallInt(Sum)), ABig);
    Inc(S, 2);
    Inc(D, 2);
    Dec(ALen);
  end;
end;

procedure MixS32(D, S: PByte; ALen, AVolume: Integer; ABig: Boolean);
var
  Sample, Sum: Int64;
begin
  ALen := ALen div 4;
  while ALen > 0 do
  begin
    Sample := (Int64(LongInt(ReadU32(S, ABig))) * AVolume) div MixMaxVolume;
    Sum := Sample + LongInt(ReadU32(D, ABig));
    if Sum > High(LongInt) then
      Sum := High(LongInt)
    else if Sum < Low(LongInt) then
      Sum := Low(LongInt);
    WriteU32(D, LongWord(LongInt(Sum)), ABig);
    Inc(S, 4);
    Inc(D, 4);
    Dec(ALen);
  end;
end;

procedure MixF32(D, S: PByte; ALen: Integer; AVolume: Single; ABig: Boolean);
var
  A, B, Sum: Single;
  U: LongWord;
begin
  ALen := ALen div 4;
  while ALen > 0 do
  begin
    U := ReadU32(S, ABig);
    A := PSingle(@U)^ * AVolume;
    U := ReadU32(D, ABig);
    B := PSingle(@U)^;
    Sum := A + B;
    if Sum > Single(1.0) then
      Sum := Single(1.0)
    else if Sum < Single(-1.0) then
      Sum := Single(-1.0);
    U := PLongWord(@Sum)^;
    WriteU32(D, U, ABig);
    Inc(S, 4);
    Inc(D, 4);
    Dec(ALen);
  end;
end;

procedure PMLMixAudio(ADst, ASrc: Pointer; AFormat: TPMLAudioFormat; ALen: Integer; AVolume: Single);
var
  Volume: Integer;
begin
  if ALen < 0 then
    raise EPMLArgument.Create('Parameter ''ALen'' is invalid');
  Volume := RoundVolume(AVolume);
  if Volume = 0 then
    Exit;
  if (AFormat = PML_AUDIO_U8) then
    MixU8(ADst, ASrc, ALen, Volume)
  else if AFormat = PML_AUDIO_S8 then
    MixS8(ADst, ASrc, ALen, Volume)
  else if AFormat = PML_AUDIO_S16LE then
    MixS16(ADst, ASrc, ALen, Volume, False)
  else if AFormat = PML_AUDIO_S16BE then
    MixS16(ADst, ASrc, ALen, Volume, True)
  else if AFormat = PML_AUDIO_S32LE then
    MixS32(ADst, ASrc, ALen, Volume, False)
  else if AFormat = PML_AUDIO_S32BE then
    MixS32(ADst, ASrc, ALen, Volume, True)
  else if AFormat = PML_AUDIO_F32LE then
    MixF32(ADst, ASrc, ALen, AVolume, False)
  else if AFormat = PML_AUDIO_F32BE then
    MixF32(ADst, ASrc, ALen, AVolume, True)
  else
    raise EPMLArgument.Create('SDL_MixAudio(): unknown audio format');
end;

end.
