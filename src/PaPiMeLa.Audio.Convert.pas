{
  PaPiMeLa.Audio.Convert — 音声の形式とチャンネル数の変換

  Origin : ported from SDL (src/audio/SDL_audiocvt.c, src/audio/SDL_audiotypecvt.c,
           src/audio/SDL_audio_channel_converters.h, include/SDL3/SDL_audio.h)
           Scope: 音声の形式の値と判定（SDL_AUDIO_xxx と SDL_AUDIO_ISxxx）、無音の値、
           チャンネルの並び（channel map）の判定、標本の型の変換（スカラー版のビット操作）、
           バイト順の入れ替え、チャンネル数の変換（56 個。src/generated/audio_channel_converters.inc。
           tools/genchannelconv.bb が生成）、並びの入れ替え（SwizzleAudio）、
           それらをつなぐ ConvertAudio（周波数の変換は含まない）、周波数の変換（SDL_audioresample.c の
           スカラー版の 1 フレームの計算と 32.32 の位置の計算。係数の表は
           src/generated/audio_resampler_filter.inc。tools/genresampler.bb が SDL のコードを C で動かして作る）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.5、§11 #52

  WHAT:
    音声の標本を、形式（U8 / S8 / S16 / S32 / F32 と、そのバイト順）とチャンネル数（1〜8）と
    チャンネルの並びの間で変換する。途中は 32 ビットの浮動小数を通る（SDL と同じ）。

  WHY:
    SDL_AudioStream と、デバイスへ混ぜる処理の土台。周波数の変換の部品もここに置き、
    ストリーム（PaPiMeLa.Audio.Stream）が使う。

  RESOLVED:
    - スカラー版だけ（設計 §9.5）。SDL は x86 で SSE2 などの版を使うが、範囲の中の値では
      どれも同じ結果になる（docs/TEST-LOG.md の使い捨て検証）
    - チャンネル数の変換は、SDL の生成済みの C を生成器で写し、式の順番まで同じにする
      （単精度の結果をビット単位でそろえるため）

  PORT-NOTE(bug):
    SDL のスカラー版の F32 → S32 は、絶対値がとても大きい値と無限大を 0 にする（範囲の外の
    小さい値（2.0 など）は正しく飽和させる）。SSE2 版は飽和させる。papimela は飽和させる（D-65）。
    SDL の SSE2 版の F32 → S8 / U8 は逆に、正のとても大きな値と +∞ を最小値にする（D-64）。
    papimela はスカラー版どおり飽和させる。

  NOT RESOLVED:
    - SDL_AudioStream は PaPiMeLa.Audio.Stream、キューは PaPiMeLa.Audio.Queue

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Audio.Convert;

{$I papimela.inc}

interface

uses
  SysUtils;

type
  { 音声の形式（SDL_AudioFormat と同じ 16 ビットの値）。下位 8 ビットがビット数、
    ビット 8 が浮動小数、ビット 12 がビッグエンディアン、ビット 15 が符号つき。 }
  TPMLAudioFormat = type Word;

const
  PML_AUDIO_MASK_BITSIZE    = $00FF;
  PML_AUDIO_MASK_FLOAT      = $0100;
  PML_AUDIO_MASK_BIG_ENDIAN = $1000;
  PML_AUDIO_MASK_SIGNED     = $8000;

  PML_AUDIO_UNKNOWN = TPMLAudioFormat($0000);
  PML_AUDIO_U8      = TPMLAudioFormat($0008);
  PML_AUDIO_S8      = TPMLAudioFormat($8008);
  PML_AUDIO_S16LE   = TPMLAudioFormat($8010);
  PML_AUDIO_S16BE   = TPMLAudioFormat($9010);
  PML_AUDIO_S32LE   = TPMLAudioFormat($8020);
  PML_AUDIO_S32BE   = TPMLAudioFormat($9020);
  PML_AUDIO_F32LE   = TPMLAudioFormat($8120);
  PML_AUDIO_F32BE   = TPMLAudioFormat($9120);
  // この機械のバイト順のもの。papimela の初回スコープはリトルエンディアンだけ（PaPiMeLa.Pixels と同じ）。
  PML_AUDIO_S16     = PML_AUDIO_S16LE;
  PML_AUDIO_S32     = PML_AUDIO_S32LE;
  PML_AUDIO_F32     = PML_AUDIO_F32LE;

  // チャンネルの並びの長さの上限（SDL_MAX_CHANNELMAP_CHANNELS）。チャンネル数も 1〜8。
  PML_MAX_CHANNEL_MAP_CHANNELS = 8;

type
  { 形式・チャンネル数・周波数（SDL_AudioSpec）。 }
  TPMLAudioSpec = record
    Format  : TPMLAudioFormat;
    Channels: Integer;
    Freq    : Integer;
    class function Make(AFormat: TPMLAudioFormat; AChannels, AFreq: Integer): TPMLAudioSpec; static;
    // 1 フレーム（全チャンネルの 1 標本ずつ）のバイト数（SDL_AUDIO_FRAMESIZE）。
    function FrameSize: Integer;
  end;

  { チャンネルの並び。出力のチャンネル i に入力のチャンネル Map[i] を置く。-1 は無音。
    空の配列は「並べ替えない」（SDL の NULL）。 }
  TPMLChannelMap = array of Integer;

  // チャンネル数の変換 1 つ（SDL_AudioChannelConverter）。同じ置き場でもよい。
  TPMLChannelConverter = procedure(ADst, ASrc: PSingle; ANumFrames: Integer);

// ---- 形式の判定（SDL_AUDIO_BITSIZE など）
function PMLAudioBitSize(AFormat: TPMLAudioFormat): Integer; inline;
function PMLAudioByteSize(AFormat: TPMLAudioFormat): Integer; inline;
function PMLAudioIsFloat(AFormat: TPMLAudioFormat): Boolean; inline;
function PMLAudioIsBigEndian(AFormat: TPMLAudioFormat): Boolean; inline;
function PMLAudioIsSigned(AFormat: TPMLAudioFormat): Boolean; inline;
// 変換できる形式か（上の 8 つ）。
function PMLIsSupportedAudioFormat(AFormat: TPMLAudioFormat): Boolean;
// チャンネル数が 1〜8 か。
function PMLIsSupportedChannelCount(AChannels: Integer): Boolean;
// 'S16LE' など（SDL_GetAudioFormatName から "SDL_AUDIO_" を外したもの）。知らなければ 'UNKNOWN'。
function PMLAudioFormatName(AFormat: TPMLAudioFormat): String;
// 無音の標本のバイト（SDL_GetSilenceValueForFormat。U8 だけ $80、ほかは 0）。
function PMLAudioSilenceValue(AFormat: TPMLAudioFormat): Byte;
type
  TPMLAudioFormats = array of TPMLAudioFormat;
{ 求めた形式に近い順の、扱える 8 つの形式（SDL_ClosestAudioFormats）。先頭は求めた形式、次が F32（この
  機械のバイト順、逆の順）…と続く。知らない形式なら空。バックエンドが、デバイスの対応する形式を
  順に試すのに使う。 }
function PMLClosestAudioFormats(AFormat: TPMLAudioFormat): TPMLAudioFormats;

// ---- チャンネルの並び（SDL_ChannelMapIsBogus / IsDefault、SDL_AudioChannelMapsEqual）
// 並びの値が -1..AChannels-1 の外にあれば True。空の並びは False。
function PMLChannelMapIsBogus(const AMap: TPMLChannelMap; AChannels: Integer): Boolean;
// 空か、i 番が i の並びなら True。
function PMLChannelMapIsDefault(const AMap: TPMLChannelMap; AChannels: Integer): Boolean;
// 両方空、または両方が同じ値なら True（片方だけ空なら、恒等の並びでも False。SDL と同じ）。
function PMLChannelMapsEqual(AChannels: Integer; const A, B: TPMLChannelMap): Boolean;

// ---- 標本の変換（SDL_audiotypecvt.c の ConvertAudioToFloat / FromFloat / SwapEndian）
// ANumSamples はチャンネルを数えた標本の数。ADst と ASrc は同じ置き場でもよい。
procedure PMLConvertAudioToFloat(ADst: PSingle; ASrc: Pointer; ANumSamples: Integer;
  ASrcFormat: TPMLAudioFormat);
procedure PMLConvertAudioFromFloat(ADst: Pointer; ASrc: PSingle; ANumSamples: Integer;
  ADstFormat: TPMLAudioFormat);
procedure PMLConvertAudioSwapEndian(ADst, ASrc: Pointer; ANumSamples, ABitSize: Integer);

{ 形式・チャンネル数・並びを変え、音量を掛ける（SDL の ConvertAudio。周波数は変えない）。

  ASrc・ADst・AScratch は同じ置き場でもよい。AScratch は
  ANumFrames * PMLAudioMaxFrameSize(...) バイト以上。nil なら ADst がその大きさであること。
  形式とチャンネル数は確かめない（呼び出し側が PMLIsSupportedAudioFormat などで確かめる）。 }
procedure PMLConvertAudio(ANumFrames: Integer;
  ASrc: Pointer; ASrcFormat: TPMLAudioFormat; ASrcChannels: Integer; const ASrcMap: TPMLChannelMap;
  ADst: Pointer; ADstFormat: TPMLAudioFormat; ADstChannels: Integer; const ADstMap: TPMLChannelMap;
  AScratch: Pointer; AGain: Single);

// 変換の途中で要る 1 フレームのバイト数の最大（CalculateMaxFrameSize。浮動小数を通るので 4 バイト以上）。
function PMLAudioMaxFrameSize(ASrcFormat: TPMLAudioFormat; ASrcChannels: Integer;
  ADstFormat: TPMLAudioFormat; ADstChannels: Integer): Integer;

// ---- 周波数の変換（SDL_audioresample.c）。位置は 32.32 の固定小数点。
// 変換の速さ（入力の 1 フレームが出力の何フレームか、の逆を 2^32 倍したもの。切り上げ）。
function PMLGetResampleRate(ASrcRate, ADstRate: Integer): Int64;
// 前の入力を何フレーム残しておくか（RESAMPLER_MAX_PADDING_FRAMES = 7）。
function PMLResamplerHistoryFrames: Integer;
// ARate で変換するとき、入力の前後に要る余白のフレーム数（0 なら変換しない）。
function PMLResamplerPaddingFrames(ARate: Int64): Integer;
// AOutputFrames を出すのに要る入力のフレーム数。
function PMLResamplerInputFrames(AOutputFrames, ARate, AOffset: Int64): Int64;
// AInputFrames から出せる出力のフレーム数。AOffset を進める。
function PMLResamplerOutputFrames(AInputFrames, ARate: Int64; var AOffset: Int64): Int64;
{ 変換する（SDL_ResampleAudio）。ASrc の前と、ASrc + AInFrames の後ろに
  PMLResamplerPaddingFrames(ARate) フレームの余白があること。AInFrames は
  PMLResamplerInputFrames(AOutFrames, ...) 以上。浮動小数のチャンネルを交互に並べたもの。 }
procedure PMLResampleAudio(AChannels: Integer; ASrc: PSingle; AInFrames: Integer;
  ADst: PSingle; AOutFrames: Integer; ARate: Int64; var AOffset: Int64);

implementation

uses
  Math;

{$I generated/audio_channel_converters.inc}
{$I generated/audio_resampler_filter.inc}

{ ---- 形式（SDL_audio.h の SDL_AUDIO_xxx） ---- }

class function TPMLAudioSpec.Make(AFormat: TPMLAudioFormat; AChannels, AFreq: Integer): TPMLAudioSpec;
begin
  Result.Format := AFormat;
  Result.Channels := AChannels;
  Result.Freq := AFreq;
end;

function TPMLAudioSpec.FrameSize: Integer;
begin
  Result := PMLAudioByteSize(Format) * Channels;
end;

function PMLAudioBitSize(AFormat: TPMLAudioFormat): Integer;
begin
  Result := AFormat and PML_AUDIO_MASK_BITSIZE;
end;

function PMLAudioByteSize(AFormat: TPMLAudioFormat): Integer;
begin
  Result := PMLAudioBitSize(AFormat) div 8;
end;

function PMLAudioIsFloat(AFormat: TPMLAudioFormat): Boolean;
begin
  Result := (AFormat and PML_AUDIO_MASK_FLOAT) <> 0;
end;

function PMLAudioIsBigEndian(AFormat: TPMLAudioFormat): Boolean;
begin
  Result := (AFormat and PML_AUDIO_MASK_BIG_ENDIAN) <> 0;
end;

function PMLAudioIsSigned(AFormat: TPMLAudioFormat): Boolean;
begin
  Result := (AFormat and PML_AUDIO_MASK_SIGNED) <> 0;
end;

{ SDL_IsSupportedAudioFormat。 }
function PMLIsSupportedAudioFormat(AFormat: TPMLAudioFormat): Boolean;
begin
  case AFormat of
    PML_AUDIO_U8, PML_AUDIO_S8, PML_AUDIO_S16LE, PML_AUDIO_S16BE,
    PML_AUDIO_S32LE, PML_AUDIO_S32BE, PML_AUDIO_F32LE, PML_AUDIO_F32BE:
      Result := True;
  else
    Result := False;
  end;
end;

function PMLIsSupportedChannelCount(AChannels: Integer): Boolean;
begin
  Result := (AChannels >= 1) and (AChannels <= 8);
end;

function PMLAudioFormatName(AFormat: TPMLAudioFormat): String;
begin
  case AFormat of
    PML_AUDIO_U8   : Result := 'U8';
    PML_AUDIO_S8   : Result := 'S8';
    PML_AUDIO_S16LE: Result := 'S16LE';
    PML_AUDIO_S16BE: Result := 'S16BE';
    PML_AUDIO_S32LE: Result := 'S32LE';
    PML_AUDIO_S32BE: Result := 'S32BE';
    PML_AUDIO_F32LE: Result := 'F32LE';
    PML_AUDIO_F32BE: Result := 'F32BE';
  else
    Result := 'UNKNOWN';
  end;
end;

{ SDL_GetSilenceValueForFormat。 }
function PMLAudioSilenceValue(AFormat: TPMLAudioFormat): Byte;
begin
  if AFormat = PML_AUDIO_U8 then
    Result := $80
  else
    Result := 0;
end;

const
  // SDL_audio.c の format_list（NATIVE はこの機械のバイト順の LE、SWAPPED は BE）。
  // 常に F32 を好む。どうせ処理のために F32 に変えるから（SDL のコメント）。
  ClosestFormatList: array[0..7, 0..7] of TPMLAudioFormat = (
    (PML_AUDIO_U8, PML_AUDIO_F32LE, PML_AUDIO_F32BE, PML_AUDIO_S8, PML_AUDIO_S16LE, PML_AUDIO_S16BE, PML_AUDIO_S32LE, PML_AUDIO_S32BE),
    (PML_AUDIO_S8, PML_AUDIO_F32LE, PML_AUDIO_F32BE, PML_AUDIO_U8, PML_AUDIO_S16LE, PML_AUDIO_S16BE, PML_AUDIO_S32LE, PML_AUDIO_S32BE),
    (PML_AUDIO_S16LE, PML_AUDIO_F32LE, PML_AUDIO_F32BE, PML_AUDIO_S16BE, PML_AUDIO_S32LE, PML_AUDIO_S32BE, PML_AUDIO_U8, PML_AUDIO_S8),
    (PML_AUDIO_S16BE, PML_AUDIO_F32LE, PML_AUDIO_F32BE, PML_AUDIO_S16LE, PML_AUDIO_S32BE, PML_AUDIO_S32LE, PML_AUDIO_U8, PML_AUDIO_S8),
    (PML_AUDIO_S32LE, PML_AUDIO_F32LE, PML_AUDIO_F32BE, PML_AUDIO_S32BE, PML_AUDIO_S16LE, PML_AUDIO_S16BE, PML_AUDIO_U8, PML_AUDIO_S8),
    (PML_AUDIO_S32BE, PML_AUDIO_F32LE, PML_AUDIO_F32BE, PML_AUDIO_S32LE, PML_AUDIO_S16BE, PML_AUDIO_S16LE, PML_AUDIO_U8, PML_AUDIO_S8),
    (PML_AUDIO_F32LE, PML_AUDIO_F32BE, PML_AUDIO_S32LE, PML_AUDIO_S32BE, PML_AUDIO_S16LE, PML_AUDIO_S16BE, PML_AUDIO_U8, PML_AUDIO_S8),
    (PML_AUDIO_F32BE, PML_AUDIO_F32LE, PML_AUDIO_S32BE, PML_AUDIO_S32LE, PML_AUDIO_S16BE, PML_AUDIO_S16LE, PML_AUDIO_U8, PML_AUDIO_S8)
  );

{ SDL_ClosestAudioFormats。 }
function PMLClosestAudioFormats(AFormat: TPMLAudioFormat): TPMLAudioFormats;
var
  I, J: Integer;
begin
  Result := nil;
  for I := 0 to High(ClosestFormatList) do
    if ClosestFormatList[I, 0] = AFormat then
    begin
      SetLength(Result, Length(ClosestFormatList[I]));
      for J := 0 to High(ClosestFormatList[I]) do
        Result[J] := ClosestFormatList[I, J];
      Exit;
    end;
end;

{ ---- チャンネルの並び ---- }

{ SDL_ChannelMapIsBogus。 }
function PMLChannelMapIsBogus(const AMap: TPMLChannelMap; AChannels: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  if Length(AMap) = 0 then
    Exit;
  for I := 0 to AChannels - 1 do
    if (AMap[I] < -1) or (AMap[I] >= AChannels) then
      Exit(True);
end;

{ SDL_ChannelMapIsDefault。 }
function PMLChannelMapIsDefault(const AMap: TPMLChannelMap; AChannels: Integer): Boolean;
var
  I: Integer;
begin
  Result := True;
  if Length(AMap) = 0 then
    Exit;
  for I := 0 to AChannels - 1 do
    if AMap[I] <> I then
      Exit(False);
end;

{ SDL_AudioChannelMapsEqual。 }
function PMLChannelMapsEqual(AChannels: Integer; const A, B: TPMLChannelMap): Boolean;
var
  I: Integer;
begin
  if (Length(A) = 0) and (Length(B) = 0) then
    Exit(True);
  if (Length(A) = 0) <> (Length(B) = 0) then
    Exit(False);
  for I := 0 to AChannels - 1 do
    if A[I] <> B[I] then
      Exit(False);
  Result := True;
end;

{ ---- 標本の変換（SDL_audiotypecvt.c のスカラー版） ----

  浮動小数のビットを作ったり読んだりする技はそのまま写す。演算はすべて単精度。 }

function SignMask(X: LongWord): LongWord; inline;
begin
  Result := LongWord(0 - (X shr 31));
end;

function BitsOf(F: Single): LongWord; inline;
begin
  Result := PLongWord(@F)^;
end;

function FloatOf(U: LongWord): Single; inline;
begin
  Result := PSingle(@U)^;
end;

{ SDL_Convert_S8_to_F32_Scalar: [65536, 65538) の浮動小数を作ってから [-1, 1) へずらす。
  出力が入力より大きいので後ろから回る。 }
procedure ConvS8ToF32(ADst: PSingle; ASrc: PShortInt; ANumSamples: Integer);
var
  I: Integer;
begin
  for I := ANumSamples - 1 downto 0 do
    ADst[I] := FloatOf(LongWord(Byte(ASrc[I])) xor $47800080) - Single(65537.0);
end;

procedure ConvU8ToF32(ADst: PSingle; ASrc: PByte; ANumSamples: Integer);
var
  I: Integer;
begin
  for I := ANumSamples - 1 downto 0 do
    ADst[I] := FloatOf(LongWord(ASrc[I]) xor $47800000) - Single(65537.0);
end;

procedure ConvS16ToF32(ADst: PSingle; ASrc: PSmallInt; ANumSamples: Integer);
var
  I: Integer;
begin
  for I := ANumSamples - 1 downto 0 do
    ADst[I] := FloatOf(LongWord(Word(ASrc[I])) xor $43808000) - Single(257.0);
end;

procedure ConvS32ToF32(ADst: PSingle; ASrc: PLongInt; ANumSamples: Integer);
const
  DivBy2147483648: Single = 4.656612873077392578125e-10;   // 2^-31
var
  I: Integer;
begin
  for I := ANumSamples - 1 downto 0 do
    ADst[I] := Single(ASrc[I]) * DivBy2147483648;
end;

{ SDL_Convert_F32_to_S8_Scalar: [-1, 1] を [98303, 98305] へずらし、ビットの差を [-128, 127] に挟む。 }
procedure ConvF32ToS8(ADst: PShortInt; ASrc: PSingle; ANumSamples: Integer);
var
  I: Integer;
  Y, Z: LongWord;
begin
  for I := 0 to ANumSamples - 1 do
  begin
    Y := LongWord(BitsOf(ASrc[I] + Single(98304.0)) - $47C00000);
    Z := LongWord($7F - (Y xor SignMask(Y)));
    Y := Y xor (Z and SignMask(Z));
    ADst[I] := ShortInt(Y and $FF);
  end;
end;

procedure ConvF32ToU8(ADst: PByte; ASrc: PSingle; ANumSamples: Integer);
var
  I: Integer;
  Y, Z: LongWord;
begin
  for I := 0 to ANumSamples - 1 do
  begin
    Y := LongWord(BitsOf(ASrc[I] + Single(98304.0)) - $47C00000);
    Z := LongWord($7F - (Y xor SignMask(Y)));
    Y := (Y xor $80) xor (Z and SignMask(Z));
    ADst[I] := Byte(Y and $FF);
  end;
end;

procedure ConvF32ToS16(ADst: PSmallInt; ASrc: PSingle; ANumSamples: Integer);
var
  I: Integer;
  Y, Z: LongWord;
begin
  for I := 0 to ANumSamples - 1 do
  begin
    Y := LongWord(BitsOf(ASrc[I] + Single(384.0)) - $43C00000);
    Z := LongWord($7FFF - (Y xor SignMask(Y)));
    Y := Y xor (Z and SignMask(Z));
    ADst[I] := SmallInt(Y and $FFFF);
  end;
end;

{ SDL_Convert_F32_to_S32_Scalar。

  PORT-NOTE(bug): SDL のスカラー版は絶対値のとても大きい値と無限大を 0 にする（範囲の外の小さい値は
  正しく飽和させる）。SSE2 版は飽和させる。papimela は飽和させる（D-65）。±1 以上は先に飽和させ、
  NaN は 0（SDL のスカラー版と同じ）。ビットで比べるのは、FPC が浮動小数点の例外を有効にしていて、
  NaN を比べると例外になるため。正の浮動小数はビットの大小と値の大小が同じで、負の浮動小数は
  符号のビットを立てたまま絶対値の順に並ぶ。 }
procedure ConvF32ToS32(ADst: PLongInt; ASrc: PSingle; ANumSamples: Integer);
var
  I: Integer;
  U, Y, Z: LongWord;
begin
  for I := 0 to ANumSamples - 1 do
  begin
    U := BitsOf(ASrc[I]);
    if ((U and $7F800000) = $7F800000) and ((U and $007FFFFF) <> 0) then
      ADst[I] := 0
    else if ((U and $80000000) = 0) and (U >= $3F800000) then
      ADst[I] := High(LongInt)
    else if ((U and $80000000) <> 0) and (U >= $BF800000) then
      ADst[I] := Low(LongInt)
    else
    begin
      // SDL の技: 指数に 31 を足して [-2^31, 2^31) にし、整数へ切り捨てる。
      Y := LongWord(U + $0F800000);
      Z := LongWord(Y - $CF000000);
      Z := Z and SignMask(Y xor Z);
      ADst[I] := LongInt(Trunc(FloatOf(LongWord(Y - Z)))) xor LongInt(SignMask(Z));
    end;
  end;
end;

procedure Swap16(ADst, ASrc: PWord; ANumSamples: Integer);
var
  I: Integer;
begin
  for I := 0 to ANumSamples - 1 do
    ADst[I] := SwapEndian(ASrc[I]);
end;

procedure Swap32(ADst, ASrc: PLongWord; ANumSamples: Integer);
var
  I: Integer;
begin
  for I := 0 to ANumSamples - 1 do
    ADst[I] := SwapEndian(ASrc[I]);
end;

{ ConvertAudioToFloat。ビッグエンディアンは先に入れ替える。F32LE は来ない。 }
procedure PMLConvertAudioToFloat(ADst: PSingle; ASrc: Pointer; ANumSamples: Integer;
  ASrcFormat: TPMLAudioFormat);
begin
  case ASrcFormat of
    PML_AUDIO_S8   : ConvS8ToF32(ADst, PShortInt(ASrc), ANumSamples);
    PML_AUDIO_U8   : ConvU8ToF32(ADst, PByte(ASrc), ANumSamples);
    PML_AUDIO_S16LE: ConvS16ToF32(ADst, PSmallInt(ASrc), ANumSamples);
    PML_AUDIO_S16BE:
      begin
        Swap16(PWord(ADst), PWord(ASrc), ANumSamples);
        ConvS16ToF32(ADst, PSmallInt(ADst), ANumSamples);
      end;
    PML_AUDIO_S32LE: ConvS32ToF32(ADst, PLongInt(ASrc), ANumSamples);
    PML_AUDIO_S32BE:
      begin
        Swap32(PLongWord(ADst), PLongWord(ASrc), ANumSamples);
        ConvS32ToF32(ADst, PLongInt(ADst), ANumSamples);
      end;
    PML_AUDIO_F32BE: Swap32(PLongWord(ADst), PLongWord(ASrc), ANumSamples);
  end;
end;

{ ConvertAudioFromFloat。ビッグエンディアンは後で入れ替える。 }
procedure PMLConvertAudioFromFloat(ADst: Pointer; ASrc: PSingle; ANumSamples: Integer;
  ADstFormat: TPMLAudioFormat);
begin
  case ADstFormat of
    PML_AUDIO_S8   : ConvF32ToS8(PShortInt(ADst), ASrc, ANumSamples);
    PML_AUDIO_U8   : ConvF32ToU8(PByte(ADst), ASrc, ANumSamples);
    PML_AUDIO_S16LE: ConvF32ToS16(PSmallInt(ADst), ASrc, ANumSamples);
    PML_AUDIO_S16BE:
      begin
        ConvF32ToS16(PSmallInt(ADst), ASrc, ANumSamples);
        Swap16(PWord(ADst), PWord(ADst), ANumSamples);
      end;
    PML_AUDIO_S32LE: ConvF32ToS32(PLongInt(ADst), ASrc, ANumSamples);
    PML_AUDIO_S32BE:
      begin
        ConvF32ToS32(PLongInt(ADst), ASrc, ANumSamples);
        Swap32(PLongWord(ADst), PLongWord(ADst), ANumSamples);
      end;
    PML_AUDIO_F32BE: Swap32(PLongWord(ADst), PLongWord(ASrc), ANumSamples);
  end;
end;

{ ConvertAudioSwapEndian。 }
procedure PMLConvertAudioSwapEndian(ADst, ASrc: Pointer; ANumSamples, ABitSize: Integer);
begin
  case ABitSize of
    16: Swap16(PWord(ADst), PWord(ASrc), ANumSamples);
    32: Swap32(PLongWord(ADst), PLongWord(ASrc), ANumSamples);
  end;
end;

{ ---- ConvertAudio（SDL_audiocvt.c） ---- }

{ 標本 1 つ（1・2・4 バイト）を読む・書く。並べ替えは型を見ずにビットを動かすだけ（SDL と同じ）。 }
function ReadSample(P: PByte; ASize: Integer): LongWord; inline;
begin
  case ASize of
    1: Result := P^;
    2: Result := PWord(P)^;
  else
    Result := PLongWord(P)^;
  end;
end;

procedure WriteSample(P: PByte; ASize: Integer; AValue: LongWord); inline;
begin
  case ASize of
    1: P^ := Byte(AValue);
    2: PWord(P)^ := Word(AValue);
  else
    PLongWord(P)^ := AValue;
  end;
end;

{ チャンネルを並べ替える（SwizzleAudio）。ADst と ASrc は同じでもよい（そのときは 1 フレームずつ
  一時の置き場を通す）。-1 は無音。 }
procedure SwizzleAudio(ANumFrames: Integer; ADst, ASrc: Pointer; AChannels: Integer;
  const AMap: TPMLChannelMap; AFormat: TPMLAudioFormat);
var
  Size, I, Ch, M: Integer;
  Silence: LongWord;
  Src, Dst: PByte;
  Tmp: array[0..PML_MAX_CHANNEL_MAP_CHANNELS - 1] of LongWord;
begin
  Size := PMLAudioByteSize(AFormat);
  // SDL は無音の値（int の 0 か 0x80）を標本の型へそのまま縮める。
  Silence := PMLAudioSilenceValue(AFormat);
  Src := PByte(ASrc);
  Dst := PByte(ADst);
  for I := 0 to ANumFrames - 1 do
  begin
    for Ch := 0 to AChannels - 1 do
    begin
      M := AMap[Ch];
      if M = -1 then
        Tmp[Ch] := Silence
      else
        Tmp[Ch] := ReadSample(Src + M * Size, Size);
    end;
    for Ch := 0 to AChannels - 1 do
      WriteSample(Dst + Ch * Size, Size, Tmp[Ch]);
    Inc(Src, AChannels * Size);
    Inc(Dst, AChannels * Size);
  end;
end;

{ ConvertAudio。手順は SDL と同じ:
  入力の並びを標準へ → 必要なら浮動小数へ（バイト順もここで）→ 音量 → チャンネル数 →
  出力の形式へ → 出力の並びへ。形式・チャンネル数が同じで音量 1 なら、写すかバイト順の
  入れ替えだけで済ませる。 }
procedure PMLConvertAudio(ANumFrames: Integer;
  ASrc: Pointer; ASrcFormat: TPMLAudioFormat; ASrcChannels: Integer; const ASrcMap: TPMLChannelMap;
  ADst: Pointer; ADstFormat: TPMLAudioFormat; ADstChannels: Integer; const ADstMap: TPMLChannelMap;
  AScratch: Pointer; AGain: Single);
var
  SrcMap, DstMap: TPMLChannelMap;
  Src, Buf: Pointer;
  DstBitSize, DstFrameSize, I, Total: Integer;
  SrcConvert, ChannelConvert, DstConvert: Boolean;
begin
  if ANumFrames = 0 then
    Exit;
  DstBitSize := PMLAudioBitSize(ADstFormat);
  DstFrameSize := (DstBitSize div 8) * ADstChannels;
  SrcMap := ASrcMap;
  DstMap := ADstMap;
  // 並びが同じなら、どちらも並べ替えない。
  if (ASrcChannels = ADstChannels) and PMLChannelMapsEqual(ASrcChannels, ASrcMap, ADstMap) then
  begin
    SrcMap := nil;
    DstMap := nil;
  end;
  Src := ASrc;

  if Length(SrcMap) > 0 then
  begin
    // 一時の置き場は入力を収められる大きさなので、あればそちらを使う。
    if AScratch <> nil then
      Buf := AScratch
    else
      Buf := ADst;
    SwizzleAudio(ANumFrames, Buf, Src, ASrcChannels, SrcMap, ASrcFormat);
    Src := Buf;
  end;

  if (ASrcChannels = ADstChannels) and (AGain = Single(1.0)) then
  begin
    if ASrcFormat = ADstFormat then
    begin
      if Length(DstMap) > 0 then
        SwizzleAudio(ANumFrames, ADst, Src, ADstChannels, DstMap, ADstFormat)
      else if Src <> ADst then
        Move(Src^, ADst^, ANumFrames * DstFrameSize);
      Exit;
    end;
    if (ASrcFormat xor ADstFormat) = PML_AUDIO_MASK_BIG_ENDIAN then
    begin
      // 並べ替えを先に（チャンネルを複製するとき、写しを 1 回減らせる）。
      if Length(DstMap) > 0 then
      begin
        SwizzleAudio(ANumFrames, ADst, Src, ADstChannels, DstMap, ADstFormat);
        Src := ADst;
      end;
      PMLConvertAudioSwapEndian(ADst, Src, ANumFrames * ADstChannels, DstBitSize);
      Exit;
    end;
  end;

  if AScratch = nil then
    AScratch := ADst;
  SrcConvert := ASrcFormat <> PML_AUDIO_F32;
  ChannelConvert := ASrcChannels <> ADstChannels;
  DstConvert := ADstFormat <> PML_AUDIO_F32;

  if SrcConvert then
  begin
    if ChannelConvert or DstConvert then
      Buf := AScratch
    else
      Buf := ADst;
    PMLConvertAudioToFloat(PSingle(Buf), Src, ANumFrames * ASrcChannels, ASrcFormat);
    Src := Buf;
  end;

  if AGain <> Single(1.0) then
  begin
    if ChannelConvert or DstConvert then
      Buf := AScratch
    else
      Buf := ADst;
    Total := ANumFrames * ASrcChannels;
    for I := 0 to Total - 1 do
      PSingle(Buf)[I] := PSingle(Src)[I] * AGain;
    Src := Buf;
  end;

  if ChannelConvert then
  begin
    if DstConvert then
      Buf := AScratch
    else
      Buf := ADst;
    ChannelConverters[ASrcChannels, ADstChannels](PSingle(Buf), PSingle(Src), ANumFrames);
    Src := Buf;
  end;

  if DstConvert then
  begin
    PMLConvertAudioFromFloat(ADst, PSingle(Src), ANumFrames * ADstChannels, ADstFormat);
    Src := ADst;
  end;

  if Length(DstMap) > 0 then
    SwizzleAudio(ANumFrames, ADst, Src, ADstChannels, DstMap, ADstFormat);
end;

{ CalculateMaxFrameSize。途中は浮動小数なので 4 バイト以上。 }
function PMLAudioMaxFrameSize(ASrcFormat: TPMLAudioFormat; ASrcChannels: Integer;
  ADstFormat: TPMLAudioFormat; ADstChannels: Integer): Integer;
begin
  Result := Max(Max(PMLAudioByteSize(ASrcFormat), PMLAudioByteSize(ADstFormat)), SizeOf(Single))
    * Max(ASrcChannels, ADstChannels);
end;

{ ---- 周波数の変換（SDL_audioresample.c） ----

  帯域を制限した補間（https://ccrma.stanford.edu/~jos/resample/）。係数の表は
  src/generated/audio_resampler_filter.inc（SDL のコードを C で動かして作った値）。

  PORT-NOTE: SDL は SSE か NEON の組み込み関数を持つ版で零交差を 6、持たない版で 5 にし、
  x86 では 1 フレームの計算を SSE で行う（足し算の順番がスカラー版と違う）。papimela は零交差 6 の
  表と、SDL のスカラー版の計算（ResampleFrame_Mono / Stereo / Generic）を使う。SDL の SIMD を
  切ったときと同じ値になる（docs/TEST-LOG.md の使い捨て検証）。 }

const
  ResamplerZeroCrossings  = 6;
  ResamplerSamplesPerFrame = ResamplerZeroCrossings * 2;
  ResamplerMaxPaddingFrames = ResamplerZeroCrossings + 1;
  ResamplerBitsPerZeroCrossing = 3;
  ResamplerFilterInterpBits = 32 - ResamplerBitsPerZeroCrossing;
  ResamplerFilterInterpRange = LongWord(1) shl ResamplerFilterInterpBits;
  // 1 / 2^29（2 の冪なので Single で割り切れる）
  ResamplerFilterInterpScale: Single = 1.0 / 536870912.0;

type
  TCubic = array[0..3] of Single;
  PCubic = ^TCubic;

function FilterAt(AIndex: LongWord): PCubic; inline;
begin
  Result := PCubic(@ResamplerFilterBits[AIndex, 0, 0]);
end;

{ ResampleFrame_Generic: 係数を 3 次式で補間し、入力に掛けて足す。 }
procedure ResampleFrameGeneric(ASrc, ADst: PSingle; AFilter: PCubic; AFrac: Single; AChans: Integer);
var
  Frac2, Frac3, OutV: Single;
  Scales: array[0..ResamplerSamplesPerFrame - 1] of Single;
  I, Chan: Integer;
begin
  Frac2 := AFrac * AFrac;
  Frac3 := AFrac * Frac2;
  for I := 0 to ResamplerSamplesPerFrame - 1 do
  begin
    Scales[I] := AFilter^[0] + (AFilter^[1] * AFrac) + (AFilter^[2] * Frac2) + (AFilter^[3] * Frac3);
    Inc(AFilter);
  end;
  for Chan := 0 to AChans - 1 do
  begin
    OutV := 0;
    for I := 0 to ResamplerSamplesPerFrame - 1 do
      OutV := OutV + (ASrc[I * AChans + Chan] * Scales[I]);
    ADst[Chan] := OutV;
  end;
end;

{ ResampleFrame_Mono。 }
procedure ResampleFrameMono(ASrc, ADst: PSingle; AFilter: PCubic; AFrac: Single);
var
  Frac2, Frac3, Scale, OutV: Single;
  I: Integer;
begin
  Frac2 := AFrac * AFrac;
  Frac3 := AFrac * Frac2;
  OutV := 0;
  for I := 0 to ResamplerSamplesPerFrame - 1 do
  begin
    Scale := AFilter^[0] + (AFilter^[1] * AFrac) + (AFilter^[2] * Frac2) + (AFilter^[3] * Frac3);
    OutV := OutV + (ASrc[I] * Scale);
    Inc(AFilter);
  end;
  ADst[0] := OutV;
end;

{ ResampleFrame_Stereo。 }
procedure ResampleFrameStereo(ASrc, ADst: PSingle; AFilter: PCubic; AFrac: Single);
var
  Frac2, Frac3, Scale, Out0, Out1: Single;
  I: Integer;
begin
  Frac2 := AFrac * AFrac;
  Frac3 := AFrac * Frac2;
  Out0 := 0;
  Out1 := 0;
  for I := 0 to ResamplerSamplesPerFrame - 1 do
  begin
    Scale := AFilter^[0] + (AFilter^[1] * AFrac) + (AFilter^[2] * Frac2) + (AFilter^[3] * Frac3);
    Out0 := Out0 + (ASrc[I * 2] * Scale);
    Out1 := Out1 + (ASrc[I * 2 + 1] * Scale);
    Inc(AFilter);
  end;
  ADst[0] := Out0;
  ADst[1] := Out1;
end;

{ SDL_GetResampleRate。dst = src * dst_rate / src_rate に合わせるため、速さは切り上げる。 }
function PMLGetResampleRate(ASrcRate, ADstRate: Integer): Int64;
var
  Numerator: Int64;
begin
  Numerator := Int64(ASrcRate) shl 32;
  Result := ((Numerator - 1) div ADstRate) + 1;
end;

function PMLResamplerHistoryFrames: Integer;
begin
  Result := ResamplerMaxPaddingFrames;
end;

function PMLResamplerPaddingFrames(ARate: Int64): Integer;
begin
  if ARate <> 0 then
    Result := ResamplerMaxPaddingFrames
  else
    Result := 0;
end;

{ ResamplerAdd / ResamplerMul: 溢れるなら False（汎用ではない。SDL と同じ確かめだけ）。 }
function ResamplerAdd(A, B: Int64; out AResult: Int64): Boolean; inline;
begin
  AResult := 0;
  if (B > 0) and (A > High(Int64) - B) then
    Exit(False);
  AResult := A + B;
  Result := True;
end;

function ResamplerMul(A, B: Int64; out AResult: Int64): Boolean; inline;
begin
  AResult := 0;
  if (B > 0) and (A > High(Int64) div B) then
    Exit(False);
  AResult := A * B;
  Result := True;
end;

{ SDL_GetResamplerInputFrames: 最後の入力のフレームの番号 + 1。
  ((((output_frames - 1) * rate) + offset) >> 32) + 1 }
function PMLResamplerInputFrames(AOutputFrames, ARate, AOffset: Int64): Int64;
var
  OutputOffset: Int64;
begin
  if not (ResamplerMul(AOutputFrames, ARate, OutputOffset)
    and ResamplerAdd(OutputOffset, -ARate + AOffset + $100000000, OutputOffset)) then
    OutputOffset := High(Int64);
  // SDL と同じく、上の 32 ビットを符号つきの 32 ビットとして読む。
  Result := LongInt(SarInt64(OutputOffset, 32));
  if Result < 0 then
    Result := 0;
end;

{ SDL_GetResamplerOutputFrames。 }
function PMLResamplerOutputFrames(AInputFrames, ARate: Int64; var AOffset: Int64): Int64;
var
  InputOffset: Int64;
begin
  if not (ResamplerMul(AInputFrames, $100000000, InputOffset)
    and ResamplerAdd(InputOffset, -AOffset, InputOffset)) then
    InputOffset := High(Int64);
  if InputOffset > 0 then
    Result := ((InputOffset - 1) div ARate) + 1
  else
    Result := 0;
  AOffset := (Result * ARate) - InputOffset;
end;

{ SDL_ResampleAudio。 }
procedure PMLResampleAudio(AChannels: Integer; ASrc: PSingle; AInFrames: Integer;
  ADst: PSingle; AOutFrames: Integer; ARate: Int64; var AOffset: Int64);
var
  I, SrcIndex: Integer;
  SrcPos: Int64;
  SrcFraction: LongWord;
  Filter: PCubic;
  Frac: Single;
  Frame: PSingle;
begin
  SrcPos := AOffset;
  Dec(ASrc, (ResamplerZeroCrossings - 1) * AChannels);
  for I := 0 to AOutFrames - 1 do
  begin
    SrcIndex := LongInt(SarInt64(SrcPos, 32));
    SrcFraction := LongWord(SrcPos and $FFFFFFFF);
    SrcPos := SrcPos + ARate;
    Filter := FilterAt(SrcFraction shr ResamplerFilterInterpBits);
    Frac := Single(SrcFraction and (ResamplerFilterInterpRange - 1)) * ResamplerFilterInterpScale;
    Frame := ASrc + PtrInt(SrcIndex) * AChannels;
    case AChannels of
      1: ResampleFrameMono(Frame, ADst, Filter, Frac);
      2: ResampleFrameStereo(Frame, ADst, Filter, Frac);
    else
      ResampleFrameGeneric(Frame, ADst, Filter, Frac, AChannels);
    end;
    Inc(ADst, AChannels);
  end;
  AOffset := SrcPos - (Int64(AInFrames) shl 32);
end;

end.
