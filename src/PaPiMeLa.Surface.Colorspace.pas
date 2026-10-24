{
  PaPiMeLa.Surface.Colorspace — 色空間の変換（転送関数・原色・トーンマップ）つきの画素の変換

  Origin : partially ported from SDL (src/video/SDL_blit_slow.c, src/video/SDL_pixels.c, src/video/SDL_surface.c)
           Scope: SDL_Blit_Slow_Float の 1:1 の経路（ReadFloatPixel / WriteFloatPixel、トーンマップ、
           原色の変換）、SDL_Blit_Slow の 8 ビット成分の読み書きの規則（色空間が同じとき）、転送関数
           （SDL_sRGBtoLinear など）、原色の変換行列（SDL_GetColorPrimariesConversionMatrix）、
           SDR の白点と HDR のヘッドルームの既定。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #73

  WHAT:
    画素の並び（8 ビット・10 ビット・16 ビット・浮動小数）と色空間の組を変えて、画素を変換する。
    SDL_ConvertPixelsAndColorspace の、YUV でもインデックスでもない形式の分。

  WHY:
    I0FL / I4FL / P010 などの YUV は、RGB48 や XBGR2101010 に直した後、色空間の変換を挟んで
    ふつうの形式へ直す（SDL_ConvertPixels_YUV_to_RGB の後半）。その後半がこのユニット。

  RESOLVED:
    - 1:1 の変換だけ（SDL_Blit_Slow_Float の拡大・縮小、ブレンド、変調、カラーキーは写さない）。
      SDL_ConvertPixelsAndColorspace が呼ぶ経路がこれ
    - 色空間が同じで、どちらの形式も 4 バイト以下のときは、SDL は浮動小数でなく整数のブリット
      （SDL_Blit_N、SDL_Blit_Slow）を使う。ここでは 8 ビットの成分で読み書きする
      （10 ビットは SDL_Blit_Slow と同じ 8 ビット成分への落とし方・戻し方）
    - 色空間が違うか、どちらかが 5 バイト以上（16 ビット整数・浮動小数）のときは、SDL と同じ
      浮動小数の経路（読む → 線形にする → トーンマップ → 原色の変換 → 符号化して書く）

  PORT-NOTE:
    SDL の転送関数の分岐は sRGB・PQ・線形だけで、BT.709 などは何もしない（「不明なものはそのまま」）。
    YUV の色空間（BT.709 の限定範囲など）を RGB の色空間として渡すと、転送関数を通らず原色だけが効く。
    SDL の I0FL / P010 の経路がこれで、papimela も同じにする。

    浮動小数の演算は Single で行う。powf は Double の Power を通して Single に丸める
    （glibc の powf と最後の 1 ビットが違うことがある）。

  NOT RESOLVED:
    - 拡大・縮小、ブレンド、変調、カラーキー、インデックス形式の出力（SDL_Blit_Slow_Float の残り）
    - YUV は PaPiMeLa.Surface.YUV の仕事（この関数は断る）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Surface.Colorspace;

{$I papimela.inc}

interface

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels;

type
  { SDL の surface のプロパティ（SDR_WHITE_POINT_FLOAT、HDR_HEADROOM_FLOAT、TONEMAP_OPERATOR_STRING）。
    浮動小数は 0 = 指定なし（色空間の既定）。Tonemap は '' = 指定なし、'chrome' / 'none' / '*=<倍率>'。 }
  TPMLColorspaceOptions = record
    SrcWhitePoint: Single;
    SrcHeadroom  : Single;
    DstWhitePoint: Single;
    DstHeadroom  : Single;
    Tonemap      : String;
  end;

// 指定なしの TPMLColorspaceOptions。
function PMLColorspaceDefaults: TPMLColorspaceOptions;

// 色空間の値から取り出す（SDL_COLORSPACEPRIMARIES / SDL_COLORSPACETRANSFER と同じ）。
function PMLColorspacePrimaries(AColorspace: TPMLColorspace): Integer; inline;
function PMLColorspaceTransfer(AColorspace: TPMLColorspace): Integer; inline;

// 転送関数（SDL_sRGBtoLinear / SDL_sRGBfromLinear / SDL_PQtoNits / SDL_PQfromNits）。
function PMLSRGBToLinear(AValue: Single): Single;
function PMLSRGBFromLinear(AValue: Single): Single;
function PMLPQToNits(AValue: Single): Single;
function PMLPQFromNits(AValue: Single): Single;

// 原色の変換行列（行優先の 3x3。SDL_GetColorPrimariesConversionMatrix）。無ければ nil。
function PMLColorPrimariesMatrix(ASrc, ADst: Integer): PSingle;

// SDR の白点と HDR のヘッドルームの既定（SDL_GetDefaultSDRWhitePoint / SDL_GetDefaultHDRHeadroom）。
function PMLDefaultSDRWhitePoint(AColorspace: TPMLColorspace): Single;
function PMLDefaultHDRHeadroom(AColorspace: TPMLColorspace): Single;

{ 画素を色空間つきで変換する（SDL_ConvertPixelsAndColorspace の、YUV でもインデックスでもない形式の分）。
  幅 AWidth・高さ AHeight の画素を、行の幅 ASrcPitch・ADstPitch（バイト）で読み書きする。
  色空間が PML_COLORSPACE_UNKNOWN なら形式の既定（PMLDefaultColorspace）。
  形式が YUV・インデックス・不明なら EPMLArgument。 }
procedure PMLConvertPixelsAndColorspace(AWidth, AHeight: Integer;
  ASrcFormat: TPMLPixelFormat; ASrcColorspace: TPMLColorspace; ASrc: Pointer; ASrcPitch: Integer;
  ADstFormat: TPMLPixelFormat; ADstColorspace: TPMLColorspace; ADst: Pointer; ADstPitch: Integer); overload;
procedure PMLConvertPixelsAndColorspace(AWidth, AHeight: Integer;
  ASrcFormat: TPMLPixelFormat; ASrcColorspace: TPMLColorspace; ASrc: Pointer; ASrcPitch: Integer;
  ADstFormat: TPMLPixelFormat; ADstColorspace: TPMLColorspace; ADst: Pointer; ADstPitch: Integer;
  const AOptions: TPMLColorspaceOptions); overload;

implementation

const
  TRANSFER_LINEAR = 8;
  TRANSFER_SRGB   = 13;
  TRANSFER_PQ     = 16;

  PRIMARIES_BT709    = 1;
  PRIMARIES_BT601    = 6;
  PRIMARIES_SMPTE240 = 7;
  PRIMARIES_BT2020   = 9;
  PRIMARIES_SMPTE431 = 11;
  PRIMARIES_SMPTE432 = 12;

  // 型付きの定数。SDL の float の定数（0.055f など）と同じ値で、Single の演算に使う。
  One         : Single = 1.0;
  Three       : Single = 3.0;
  C0_04045    : Single = 0.04045;
  C12_92      : Single = 12.92;
  C0_055      : Single = 0.055;
  C1_055      : Single = 1.055;
  C2_4        : Single = 2.4;
  C0_0031308  : Single = 0.0031308;
  C255        : Single = 255.0;
  C1023       : Single = 1023.0;
  C65535      : Single = 65535.0;
  C10000      : Single = 10000.0;
  PQ_C1       : Single = 0.8359375;
  PQ_C2       : Single = 18.8515625;
  PQ_C3       : Single = 18.6875;
  PQ_M1       : Single = 0.1593017578125;
  PQ_M2       : Single = 78.84375;

function PMLColorspaceDefaults: TPMLColorspaceOptions;
begin
  Result.SrcWhitePoint := 0;
  Result.SrcHeadroom := 0;
  Result.DstWhitePoint := 0;
  Result.DstHeadroom := 0;
  Result.Tonemap := '';
end;

function PMLColorspacePrimaries(AColorspace: TPMLColorspace): Integer; inline;
begin
  Result := (AColorspace shr 10) and $1F;
end;

function PMLColorspaceTransfer(AColorspace: TPMLColorspace): Integer; inline;
begin
  Result := (AColorspace shr 5) and $1F;
end;

{ ---- 転送関数（SDL_pixels.c） ---- }

{ SDL_powf。Double で計算して Single に丸める。 }
function PowF(AX, AY: Single): Single; inline;
begin
  if AX = 0 then
  begin
    if AY = 0 then
      Result := 1
    else
      Result := 0;
    Exit;
  end;
  Result := Single(Power(Double(AX), Double(AY)));
end;

function PMLSRGBToLinear(AValue: Single): Single;
var
  V: Single;
begin
  V := AValue;
  if V <= C0_04045 then
    V := V / C12_92
  else
  begin
    V := (V + C0_055) / C1_055;
    V := PowF(V, C2_4);
  end;
  Result := V;
end;

function PMLSRGBFromLinear(AValue: Single): Single;
var
  V, T: Single;
begin
  V := AValue;
  if V <= C0_0031308 then
    V := V * C12_92
  else
  begin
    T := One / C2_4;
    V := PowF(V, T) * C1_055 - C0_055;
  end;
  Result := V;
end;

function PMLPQToNits(AValue: Single): Single;
var
  OOM1, OOM2, P, Num, Den: Single;
begin
  OOM1 := One / PQ_M1;
  OOM2 := One / PQ_M2;
  P := PowF(AValue, OOM2);
  Num := P - PQ_C1;
  if Num < 0 then
    Num := 0;
  Den := PQ_C2 - PQ_C3 * P;
  Result := C10000 * PowF(Num / Den, OOM1);
end;

function PMLPQFromNits(AValue: Single): Single;
var
  Y, Num, Den, P: Single;
begin
  Y := AValue / C10000;
  if Y < 0 then
    Y := 0
  else if Y > 1 then
    Y := 1;
  P := PowF(Y, PQ_M1);
  Num := PQ_C1 + PQ_C2 * P;
  Den := One + PQ_C3 * P;
  Result := PowF(Num / Den, PQ_M2);
end;

{ ---- 原色の変換行列（SDL_pixels.c。gamescope の色の道具で作った値） ---- }

const
  Mat601to709: array[0..8] of Single = (
    0.939542, 0.050181, 0.010277,
    0.017772, 0.965793, 0.016435,
    -0.001622, -0.004370, 1.005991);
  Mat601to2020: array[0..8] of Single = (
    0.595254, 0.349314, 0.055432,
    0.081244, 0.891503, 0.027253,
    0.015512, 0.081912, 0.902576);
  Mat709to601: array[0..8] of Single = (
    1.065379, -0.055401, -0.009978,
    -0.019633, 1.036363, -0.016731,
    0.001632, 0.004412, 0.993956);
  Mat709to2020: array[0..8] of Single = (
    0.627404, 0.329283, 0.043313,
    0.069097, 0.919541, 0.011362,
    0.016391, 0.088013, 0.895595);
  Mat2020to601: array[0..8] of Single = (
    1.776133, -0.687820, -0.088313,
    -0.161376, 1.187315, -0.025940,
    -0.015881, -0.095931, 1.111812);
  Mat2020to709: array[0..8] of Single = (
    1.660496, -0.587656, -0.072840,
    -0.124547, 1.132895, -0.008348,
    -0.018154, -0.100597, 1.118751);
  MatSMPTE431to709: array[0..8] of Single = (
    1.120713, -0.234649, 0.000000,
    -0.038478, 1.087034, 0.000000,
    -0.017967, -0.082030, 0.954576);
  MatSMPTE431to2020: array[0..8] of Single = (
    0.689691, 0.207169, 0.041346,
    0.041852, 0.982426, 0.010846,
    -0.001107, 0.018362, 0.854914);
  MatSMPTE432to709: array[0..8] of Single = (
    1.224940, -0.224940, -0.000000,
    -0.042057, 1.042057, 0.000000,
    -0.019638, -0.078636, 1.098273);
  MatSMPTE432to2020: array[0..8] of Single = (
    0.753833, 0.198597, 0.047570,
    0.045744, 0.941777, 0.012479,
    -0.001210, 0.017602, 0.983609);

function PMLColorPrimariesMatrix(ASrc, ADst: Integer): PSingle;
begin
  Result := nil;
  case ADst of
    PRIMARIES_BT601, PRIMARIES_SMPTE240:
      case ASrc of
        PRIMARIES_BT709: Result := @Mat709to601[0];
        PRIMARIES_BT2020: Result := @Mat2020to601[0];
      end;
    PRIMARIES_BT709:
      case ASrc of
        PRIMARIES_BT601, PRIMARIES_SMPTE240: Result := @Mat601to709[0];
        PRIMARIES_BT2020: Result := @Mat2020to709[0];
        PRIMARIES_SMPTE431: Result := @MatSMPTE431to709[0];
        PRIMARIES_SMPTE432: Result := @MatSMPTE432to709[0];
      end;
    PRIMARIES_BT2020:
      case ASrc of
        PRIMARIES_BT601, PRIMARIES_SMPTE240: Result := @Mat601to2020[0];
        PRIMARIES_BT709: Result := @Mat709to2020[0];
        PRIMARIES_SMPTE431: Result := @MatSMPTE431to2020[0];
        PRIMARIES_SMPTE432: Result := @MatSMPTE432to2020[0];
      end;
  end;
end;

procedure ConvertColorPrimaries(var AR, AG, AB: Single; AMatrix: PSingle);
var
  V0, V1, V2: Single;
begin
  V0 := AR;
  V1 := AG;
  V2 := AB;
  AR := AMatrix[0] * V0 + AMatrix[1] * V1 + AMatrix[2] * V2;
  AG := AMatrix[3] * V0 + AMatrix[4] * V1 + AMatrix[5] * V2;
  AB := AMatrix[6] * V0 + AMatrix[7] * V1 + AMatrix[8] * V2;
end;

{ ---- 白点とヘッドルーム（SDL_surface.c） ---- }

function PMLDefaultSDRWhitePoint(AColorspace: TPMLColorspace): Single;
begin
  if PMLColorspaceTransfer(AColorspace) = TRANSFER_PQ then
    Result := 203.0
  else
    Result := 1.0;
end;

function PMLDefaultHDRHeadroom(AColorspace: TPMLColorspace): Single;
var
  T: Integer;
begin
  T := PMLColorspaceTransfer(AColorspace);
  if (T = TRANSFER_LINEAR) or (T = TRANSFER_PQ) then
    Result := 0.0
  else
    Result := 1.0;
end;

{ 呼び出し側の指定を入れた白点。線形と PQ だけが指定を読む（SDL_GetSurfaceSDRWhitePoint）。 }
function EffectiveWhitePoint(AColorspace: TPMLColorspace; AGiven: Single): Single;
var
  T: Integer;
begin
  T := PMLColorspaceTransfer(AColorspace);
  if ((T = TRANSFER_LINEAR) or (T = TRANSFER_PQ)) and (AGiven <> 0) then
    Result := AGiven
  else
    Result := PMLDefaultSDRWhitePoint(AColorspace);
end;

function EffectiveHeadroom(AColorspace: TPMLColorspace; AGiven: Single): Single;
var
  T: Integer;
begin
  T := PMLColorspaceTransfer(AColorspace);
  if (T = TRANSFER_LINEAR) or (T = TRANSFER_PQ) then
    Result := AGiven
  else
    Result := 1.0;
end;

{ ---- 半精度 ---- }

function HalfToFloat(AHalf: Word): Single;
var
  E, M, U: LongWord;
begin
  E := (AHalf shr 10) and $1F;
  M := AHalf and $3FF;
  if E = 0 then
  begin
    // 0 と非正規化数
    Result := Single(M) * Single(5.9604644775390625e-8);
    if (AHalf and $8000) <> 0 then
      Result := -Result;
    Exit;
  end;
  if E = 31 then
    U := $7F800000 or (M shl 13)
  else
    U := ((E + 112) shl 23) or (M shl 13);
  U := U or (LongWord(AHalf and $8000) shl 16);
  Result := PSingle(@U)^;
end;

{ SDL の float_to_half（IEEE 754 の最近接偶数への丸め）。 }
function FloatToHalf(AValue: Single): Word;
var
  IA, IR: LongWord;
  Shift: Integer;
begin
  IA := PLongWord(@AValue)^;
  IR := (IA shr 16) and $8000;
  if (IA and $7F800000) = $7F800000 then
  begin
    if (IA and $7FFFFFFF) = $7F800000 then
      IR := IR or $7C00
    else
      IR := IR or $7E00 or ((IA shr (24 - 11)) and $1FF);
  end
  else if (IA and $7F800000) >= $33000000 then
  begin
    Shift := Integer((IA shr 23) and $FF) - 127;
    if Shift > 15 then
      IR := IR or $7C00
    else
    begin
      IA := (IA and $007FFFFF) or $00800000;
      if Shift < -14 then
      begin
        IR := IR or (IA shr (-1 - Shift));
        IA := LongWord(IA shl (32 - (-1 - Shift)));
      end
      else
      begin
        IR := IR or (IA shr (24 - 11));
        IA := LongWord(IA shl (32 - (24 - 11)));
        IR := IR + LongWord((14 + Shift) shl 10);
      end;
      if (IA > $80000000) or ((IA = $80000000) and ((IR and 1) <> 0)) then
        Inc(IR);
    end;
  end;
  Result := Word(IR);
end;

{ ---- 画素の読み書き ---- }

type
  TAccess = (RGB, RGBA, Bit10, Large);

function AccessOf(AFormat: TPMLPixelFormat): TAccess;
begin
  if PMLBytesPerPixel(AFormat) > 4 then
    Result := TAccess.Large
  else if PMLIsPixelFormat10Bit(AFormat) then
    Result := TAccess.Bit10
  else if PMLIsPixelFormatAlpha(AFormat) then
    Result := TAccess.RGBA
  else
    Result := TAccess.RGB;
end;

procedure CheckFormat(AFormat: TPMLPixelFormat);
begin
  if (AFormat = PML_PIXELFORMAT_UNKNOWN) or PMLIsPixelFormatFourCC(AFormat)
  or PMLIsPixelFormatIndexed(AFormat) then
    raise EPMLArgument.CreateFmt('%s cannot be converted with a colorspace here',
      [PMLPixelFormatName(AFormat)]);
end;

{ 画素値（1〜4 バイト、リトルエンディアン）。RGB24 のような 3 バイトも同じ並びで読む。 }
function LoadPacked(APixels: PByte; ABytes: Integer): LongWord;
begin
  case ABytes of
    1: Result := APixels^;
    2: Result := PWord(APixels)^;
    3: Result := LongWord(APixels[0]) or (LongWord(APixels[1]) shl 8) or (LongWord(APixels[2]) shl 16);
  else
    Result := PLongWord(APixels)^;
  end;
end;

procedure StorePacked(APixels: PByte; ABytes: Integer; AValue: LongWord);
begin
  case ABytes of
    1: APixels^ := Byte(AValue);
    2: PWord(APixels)^ := Word(AValue);
    3:
      begin
        APixels[0] := Byte(AValue);
        APixels[1] := Byte(AValue shr 8);
        APixels[2] := Byte(AValue shr 16);
      end;
  else
    PLongWord(APixels)^ := AValue;
  end;
end;

{ 10 ビット形式の R が下位（XBGR / ABGR）か。 }
function IsBGROrder(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := (PMLPixelOrder(AFormat) = LongWord(TPMLPackedOrder.XBGR))
         or (PMLPixelOrder(AFormat) = LongWord(TPMLPackedOrder.ABGR));
end;

{ 配列形式の成分の並び。AA < 0 ならアルファは無い。 }
procedure ArrayOrderOf(AFormat: TPMLPixelFormat; out AR, AG, AB, AA: Integer);
begin
  AR := 0; AG := 1; AB := 2; AA := 3;
  case TPMLArrayOrder(PMLPixelOrder(AFormat)) of
    TPMLArrayOrder.ArrayRGB:
      AA := -1;
    TPMLArrayOrder.ArrayRGBA: ;
    TPMLArrayOrder.ArrayARGB:
      begin AA := 0; AR := 1; AG := 2; AB := 3; end;
    TPMLArrayOrder.ArrayBGR:
      begin AB := 0; AG := 1; AR := 2; AA := -1; end;
    TPMLArrayOrder.ArrayBGRA:
      begin AB := 0; AG := 1; AR := 2; AA := 3; end;
    TPMLArrayOrder.ArrayABGR:
      begin AA := 0; AB := 1; AG := 2; AR := 3; end;
  end;
end;

{ SDL の ReadFloatPixel の、画素を浮動小数にする前半。転送関数は後で掛ける。 }
procedure ReadRaw(APixels: PByte; AAccess: TAccess; AFormat: TPMLPixelFormat;
  const ADetails: TPMLPixelFormatDetails; out AR, AG, AB, AA: Single);
var
  Pixel: LongWord;
  R8, G8, B8, A8: Byte;
  V: array[0..3] of Single;
  OR_, OG, OB, OA, I, Comps: Integer;
  Typ: TPMLPixelType;
begin
  case AAccess of
    TAccess.RGB, TAccess.RGBA:
      begin
        Pixel := LoadPacked(APixels, ADetails.BytesPerPixel);
        PMLGetRGBA(Pixel, ADetails, nil, R8, G8, B8, A8);
        AR := Single(R8) / C255;
        AG := Single(G8) / C255;
        AB := Single(B8) / C255;
        if AAccess = TAccess.RGBA then
          AA := Single(A8) / C255
        else
          AA := 1.0;
      end;
    TAccess.Bit10:
      begin
        Pixel := PLongWord(APixels)^;
        if IsBGROrder(AFormat) then
        begin
          AR := Single((Pixel shr 0) and $3FF) / C1023;
          AG := Single((Pixel shr 10) and $3FF) / C1023;
          AB := Single((Pixel shr 20) and $3FF) / C1023;
        end
        else
        begin
          AR := Single((Pixel shr 20) and $3FF) / C1023;
          AG := Single((Pixel shr 10) and $3FF) / C1023;
          AB := Single((Pixel shr 0) and $3FF) / C1023;
        end;
        if PMLIsPixelFormatAlpha(AFormat) then
          AA := Single(Pixel shr 30) / Three
        else
          AA := 1.0;
      end;
  else
    begin
      Typ := PMLPixelType(AFormat);
      if Typ = TPMLPixelType.ArrayF32 then
        Comps := PMLBytesPerPixel(AFormat) div 4
      else
        Comps := PMLBytesPerPixel(AFormat) div 2;
      V[0] := 0; V[1] := 0; V[2] := 0; V[3] := 1.0;
      for I := 0 to Comps - 1 do
        case Typ of
          TPMLPixelType.ArrayU16: V[I] := Single(PWord(APixels)[I]) / C65535;
          TPMLPixelType.ArrayF16: V[I] := HalfToFloat(PWord(APixels)[I]);
          TPMLPixelType.ArrayF32: V[I] := PSingle(APixels)[I];
        end;
      ArrayOrderOf(AFormat, OR_, OG, OB, OA);
      AR := V[OR_];
      AG := V[OG];
      AB := V[OB];
      if OA >= 0 then
        AA := V[OA]
      else
        AA := 1.0;
    end;
  end;
end;

{ SDL_roundf。引数は 0 以上なので、四捨五入（半分は大きいほう）。 }
function RoundF(AValue: Single): LongWord; inline;
begin
  Result := LongWord(Trunc(Double(AValue) + 0.5));
end;

function Clamp01(AValue: Single): Single; inline;
begin
  if AValue < 0 then
    Result := 0
  else if AValue > 1 then
    Result := 1
  else
    Result := AValue;
end;

{ SDL の WriteFloatPixel の、浮動小数を画素にする後半（転送関数は済んだ後）。 }
procedure WriteRaw(APixels: PByte; AAccess: TAccess; AFormat: TPMLPixelFormat;
  const ADetails: TPMLPixelFormatDetails; AR, AG, AB, AA: Single);
var
  R8, G8, B8, A8: Byte;
  R10, G10, B10, A2: LongWord;
  V: array[0..3] of Single;
  OR_, OG, OB, OA, I, Comps: Integer;
  Typ: TPMLPixelType;
begin
  case AAccess of
    TAccess.RGB, TAccess.RGBA:
      begin
        R8 := Byte(RoundF(Clamp01(AR) * C255));
        G8 := Byte(RoundF(Clamp01(AG) * C255));
        B8 := Byte(RoundF(Clamp01(AB) * C255));
        if AAccess = TAccess.RGBA then
          A8 := Byte(RoundF(Clamp01(AA) * C255))
        else
          A8 := 255;
        StorePacked(APixels, ADetails.BytesPerPixel, PMLMapRGBA(ADetails, nil, R8, G8, B8, A8));
      end;
    TAccess.Bit10:
      begin
        R10 := RoundF(Clamp01(AR) * C1023);
        G10 := RoundF(Clamp01(AG) * C1023);
        B10 := RoundF(Clamp01(AB) * C1023);
        if PMLIsPixelFormatAlpha(AFormat) then
          A2 := RoundF(Clamp01(AA) * Three)
        else
          A2 := 3;
        if IsBGROrder(AFormat) then
          PLongWord(APixels)^ := (A2 shl 30) or (B10 shl 20) or (G10 shl 10) or R10
        else
          PLongWord(APixels)^ := (A2 shl 30) or (R10 shl 20) or (G10 shl 10) or B10;
      end;
  else
    begin
      Typ := PMLPixelType(AFormat);
      ArrayOrderOf(AFormat, OR_, OG, OB, OA);
      V[0] := 0; V[1] := 0; V[2] := 0; V[3] := 1.0;
      V[OR_] := AR;
      V[OG] := AG;
      V[OB] := AB;
      if OA >= 0 then
        V[OA] := AA;
      if Typ = TPMLPixelType.ArrayF32 then
        Comps := PMLBytesPerPixel(AFormat) div 4
      else
        Comps := PMLBytesPerPixel(AFormat) div 2;
      for I := 0 to Comps - 1 do
        case Typ of
          TPMLPixelType.ArrayU16: PWord(APixels)[I] := Word(RoundF(Clamp01(V[I]) * C65535));
          TPMLPixelType.ArrayF16: PWord(APixels)[I] := FloatToHalf(V[I]);
          TPMLPixelType.ArrayF32: PSingle(APixels)[I] := V[I];
        end;
    end;
  end;
end;

{ ---- 変換本体 ---- }

{ 色空間が同じで、どちらも 4 バイト以下のとき（SDL は整数のブリット）。8 ビット成分で読み書きする。
  10 ビットは SDL_Blit_Slow と同じ（上位 8 ビットへ落とす。戻すときは下位に 0x3 を足す）。 }
procedure ConvertInteger(AWidth, AHeight: Integer; ASrcFormat: TPMLPixelFormat; ASrc: PByte; ASrcPitch: Integer;
  ADstFormat: TPMLPixelFormat; ADst: PByte; ADstPitch: Integer);
var
  SD, DD: TPMLPixelFormatDetails;
  SAccess, DAccess: TAccess;
  X, Y, SBytes, DBytes: Integer;
  S, D: PByte;
  Pixel, R10, G10, B10, A2: LongWord;
  R, G, B, A: Byte;
  SBGR, DBGR: Boolean;
begin
  PMLGetPixelFormatDetails(ASrcFormat, SD);
  PMLGetPixelFormatDetails(ADstFormat, DD);
  SAccess := AccessOf(ASrcFormat);
  DAccess := AccessOf(ADstFormat);
  SBytes := PMLBytesPerPixel(ASrcFormat);
  DBytes := PMLBytesPerPixel(ADstFormat);
  SBGR := IsBGROrder(ASrcFormat);
  DBGR := IsBGROrder(ADstFormat);
  for Y := 0 to AHeight - 1 do
  begin
    S := ASrc + PtrInt(Y) * ASrcPitch;
    D := ADst + PtrInt(Y) * ADstPitch;
    for X := 0 to AWidth - 1 do
    begin
      if SAccess = TAccess.Bit10 then
      begin
        Pixel := PLongWord(S)^;
        if SBGR then
        begin
          R := (Pixel shr 2) and $FF;
          G := (Pixel shr 12) and $FF;
          B := (Pixel shr 22) and $FF;
        end
        else
        begin
          R := (Pixel shr 22) and $FF;
          G := (Pixel shr 12) and $FF;
          B := (Pixel shr 2) and $FF;
        end;
        if PMLIsPixelFormatAlpha(ASrcFormat) then
          A := Byte(((Pixel shr 30) * 255) div 3)
        else
          A := 255;
      end
      else
      begin
        Pixel := LoadPacked(S, SBytes);
        PMLGetRGBA(Pixel, SD, nil, R, G, B, A);
        if SAccess = TAccess.RGB then
          A := 255;
      end;
      if DAccess = TAccess.Bit10 then
      begin
        if R <> 0 then R10 := (LongWord(R) shl 2) or 3 else R10 := 0;
        if G <> 0 then G10 := (LongWord(G) shl 2) or 3 else G10 := 0;
        if B <> 0 then B10 := (LongWord(B) shl 2) or 3 else B10 := 0;
        if PMLIsPixelFormatAlpha(ADstFormat) then
          A2 := (LongWord(A) * 3) div 255
        else
          A2 := 3;
        if DBGR then
          PLongWord(D)^ := (A2 shl 30) or (B10 shl 20) or (G10 shl 10) or R10
        else
          PLongWord(D)^ := (A2 shl 30) or (R10 shl 20) or (G10 shl 10) or B10;
      end
      else
        StorePacked(D, DBytes, PMLMapRGBA(DD, nil, R, G, B, A));
      Inc(S, SBytes);
      Inc(D, DBytes);
    end;
  end;
end;

type
  TTonemapOp = (None, Linear, Chrome);

{ 線形にして白点で割る（SDL の ReadFloatPixel の後半）。 }
procedure ToLinear(ATransfer: Integer; AWhitePoint: Single; var AR, AG, AB: Single);
begin
  case ATransfer of
    TRANSFER_SRGB:
      begin
        AR := PMLSRGBToLinear(AR);
        AG := PMLSRGBToLinear(AG);
        AB := PMLSRGBToLinear(AB);
      end;
    TRANSFER_PQ:
      begin
        AR := PMLPQToNits(AR) / AWhitePoint;
        AG := PMLPQToNits(AG) / AWhitePoint;
        AB := PMLPQToNits(AB) / AWhitePoint;
      end;
    TRANSFER_LINEAR:
      begin
        AR := AR / AWhitePoint;
        AG := AG / AWhitePoint;
        AB := AB / AWhitePoint;
      end;
  end;
end;

procedure FromLinear(ATransfer: Integer; AWhitePoint: Single; var AR, AG, AB: Single);
begin
  case ATransfer of
    TRANSFER_SRGB:
      begin
        AR := PMLSRGBFromLinear(AR);
        AG := PMLSRGBFromLinear(AG);
        AB := PMLSRGBFromLinear(AB);
      end;
    TRANSFER_PQ:
      begin
        AR := PMLPQFromNits(AR * AWhitePoint);
        AG := PMLPQFromNits(AG * AWhitePoint);
        AB := PMLPQFromNits(AB * AWhitePoint);
      end;
    TRANSFER_LINEAR:
      begin
        AR := AR * AWhitePoint;
        AG := AG * AWhitePoint;
        AB := AB * AWhitePoint;
      end;
  end;
end;

procedure PMLConvertPixelsAndColorspace(AWidth, AHeight: Integer;
  ASrcFormat: TPMLPixelFormat; ASrcColorspace: TPMLColorspace; ASrc: Pointer; ASrcPitch: Integer;
  ADstFormat: TPMLPixelFormat; ADstColorspace: TPMLColorspace; ADst: Pointer; ADstPitch: Integer);
begin
  PMLConvertPixelsAndColorspace(AWidth, AHeight, ASrcFormat, ASrcColorspace, ASrc, ASrcPitch,
    ADstFormat, ADstColorspace, ADst, ADstPitch, PMLColorspaceDefaults);
end;

procedure PMLConvertPixelsAndColorspace(AWidth, AHeight: Integer;
  ASrcFormat: TPMLPixelFormat; ASrcColorspace: TPMLColorspace; ASrc: Pointer; ASrcPitch: Integer;
  ADstFormat: TPMLPixelFormat; ADstColorspace: TPMLColorspace; ADst: Pointer; ADstPitch: Integer;
  const AOptions: TPMLColorspaceOptions);
var
  SCS, DCS: TPMLColorspace;
  SD, DD: TPMLPixelFormatDetails;
  SAccess, DAccess: TAccess;
  SBytes, DBytes, Y, X: Integer;
  S, D: PByte;
  SWhite, DWhite, SHead, DHead: Single;
  Op: TTonemapOp;
  TmScale, TmA, TmB: Single;
  TmMatrix, PrimMatrix: PSingle;
  SPrim, DPrim, STransfer, DTransfer: Integer;
  R, G, B, A, VMax, Scale: Single;
  Name: String;
  FS: TFormatSettings;
begin
  CheckFormat(ASrcFormat);
  CheckFormat(ADstFormat);
  if (AWidth <= 0) or (AHeight <= 0) then
    Exit;
  SCS := ASrcColorspace;
  if SCS = PML_COLORSPACE_UNKNOWN then
    SCS := PMLDefaultColorspace(ASrcFormat);
  DCS := ADstColorspace;
  if DCS = PML_COLORSPACE_UNKNOWN then
    DCS := PMLDefaultColorspace(ADstFormat);
  SBytes := PMLBytesPerPixel(ASrcFormat);
  DBytes := PMLBytesPerPixel(ADstFormat);

  // 同じ形式で同じ色空間は、そのまま写す
  if (ASrcFormat = ADstFormat) and (SCS = DCS) then
  begin
    for Y := 0 to AHeight - 1 do
      Move((PByte(ASrc) + PtrInt(Y) * ASrcPitch)^, (PByte(ADst) + PtrInt(Y) * ADstPitch)^, AWidth * SBytes);
    Exit;
  end;
  // 色空間が同じで、どちらも 4 バイト以下は整数の経路
  if (SCS = DCS) and (SBytes <= 4) and (DBytes <= 4) then
  begin
    ConvertInteger(AWidth, AHeight, ASrcFormat, ASrc, ASrcPitch, ADstFormat, ADst, ADstPitch);
    Exit;
  end;

  // ---- 浮動小数の経路（SDL_Blit_Slow_Float）
  PMLGetPixelFormatDetails(ASrcFormat, SD);
  PMLGetPixelFormatDetails(ADstFormat, DD);
  SAccess := AccessOf(ASrcFormat);
  DAccess := AccessOf(ADstFormat);
  SPrim := PMLColorspacePrimaries(SCS);
  DPrim := PMLColorspacePrimaries(DCS);
  STransfer := PMLColorspaceTransfer(SCS);
  DTransfer := PMLColorspaceTransfer(DCS);
  SWhite := EffectiveWhitePoint(SCS, AOptions.SrcWhitePoint);
  DWhite := EffectiveWhitePoint(DCS, AOptions.DstWhitePoint);
  SHead := EffectiveHeadroom(SCS, AOptions.SrcHeadroom);
  DHead := EffectiveHeadroom(DCS, AOptions.DstHeadroom);
  if DHead = 0 then
    DHead := SHead;

  Op := TTonemapOp.None;
  TmScale := 1.0;
  TmA := 0;
  TmB := 0;
  TmMatrix := nil;
  if SHead > DHead then
  begin
    if AOptions.Tonemap <> '' then
    begin
      Name := AOptions.Tonemap;
      if Copy(Name, 1, 2) = '*=' then
      begin
        Op := TTonemapOp.Linear;
        FS := DefaultFormatSettings;
        FS.DecimalSeparator := '.';
        TmScale := Single(StrToFloatDef(Copy(Name, 3, MaxInt), 0.0, FS));
      end
      else if SameText(Name, 'chrome') then
        Op := TTonemapOp.Chrome
      else if SameText(Name, 'none') then
        Op := TTonemapOp.None;
    end
    else
      Op := TTonemapOp.Chrome;
    if Op = TTonemapOp.Chrome then
    begin
      TmA := DHead / (SHead * SHead);
      TmB := One / DHead;
      // トーンマップは BT.2020 の原色で行う
      TmMatrix := PMLColorPrimariesMatrix(SPrim, PRIMARIES_BT2020);
      if TmMatrix <> nil then
        SPrim := PRIMARIES_BT2020;
    end;
  end;
  PrimMatrix := nil;
  if SPrim <> DPrim then
    PrimMatrix := PMLColorPrimariesMatrix(SPrim, DPrim);

  for Y := 0 to AHeight - 1 do
  begin
    S := PByte(ASrc) + PtrInt(Y) * ASrcPitch;
    D := PByte(ADst) + PtrInt(Y) * ADstPitch;
    for X := 0 to AWidth - 1 do
    begin
      ReadRaw(S, SAccess, ASrcFormat, SD, R, G, B, A);
      ToLinear(STransfer, SWhite, R, G, B);
      case Op of
        TTonemapOp.Linear:
          begin
            R := R * TmScale;
            G := G * TmScale;
            B := B * TmScale;
          end;
        TTonemapOp.Chrome:
          begin
            if TmMatrix <> nil then
              ConvertColorPrimaries(R, G, B, TmMatrix);
            VMax := R;
            if G > VMax then VMax := G;
            if B > VMax then VMax := B;
            if VMax > 0 then
            begin
              Scale := (One + TmA * VMax) / (One + TmB * VMax);
              R := R * Scale;
              G := G * Scale;
              B := B * Scale;
            end;
          end;
      end;
      if PrimMatrix <> nil then
        ConvertColorPrimaries(R, G, B, PrimMatrix);
      FromLinear(DTransfer, DWhite, R, G, B);
      WriteRaw(D, DAccess, ADstFormat, DD, R, G, B, A);
      Inc(S, SBytes);
      Inc(D, DBytes);
    end;
  end;
end;

end.
