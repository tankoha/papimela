{
  PaPiMeLa.Surface.YUV — YUV の平面の置き場と、YUV から ARGB8888（P010 は XBGR2101010）への変換

  Origin : ported from SDL (src/video/SDL_yuv.c, src/video/yuv2rgb/yuv_rgb_std.c,
           src/video/yuv2rgb/yuv_rgb_std_func.h, src/video/yuv2rgb/yuv_rgb_internal.h,
           src/render/SDL_yuv_sw.c)
           Scope: YUV の形式の大きさと平面の並び（SDL_CalculateYUVSize、GetYUVPlanes）、
           色空間から変換の種類を選ぶ規則（GetYUVConversionType）、YUV から RGB への
           整数の変換（yuv_rgb_std の 4:2:0 / 4:2:2 / NV12 を ARGB8888 へ。係数の表と
           2x2 ずつの回り方、奇数の幅と高さの端の扱い）、YUV のテクスチャの平面の置き場と
           更新（SDL_SW_CreateYUVTexture、SDL_SW_UpdateYUVTexture、
           SDL_SW_UpdateYUVTexturePlanar、SDL_SW_UpdateNVTexturePlanar）。I444 の置き場・更新・変換
           （3 平面で色差も輝度と同じ大きさ）、P010 から XBGR2101010 への変換（yuvp010_xbgr2101010_std）、
           I0FL / I4FL の置き場・更新と RGB48 への変換（yuvi0fl_rgb48_std / yuvi4fl_rgb48_std）、
           任意の形式への変換（SDL_ConvertPixels_YUV_to_RGB の中継の道。色空間の変換は
           PaPiMeLa.Surface.Colorspace）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #68

  WHAT:
    YV12 / IYUV / I444 / NV12 / NV21 / YUY2 / UYVY / YVYU の画素を ARGB8888 に直す。P010 は
    XBGR2101010 に直す（PMLConvertP010ToXBGR2101010。テクスチャにはならない）。I0FL / I4FL は RGB48 に直す
    （PMLConvertYUV16ToRGB48）。PMLConvertYUVPixels は、どの YUV からも任意の形式・色空間へ直す。
    I0FL / I4FL は 1 標本 2 バイトの平面で、レンダラの肩代わりのテクスチャにもなる（既定の色空間
    HDR10 は変換できないので、BT.601 / BT.709 / BT.2020 の全範囲を明示して作る）。
    TPMLYUVPlanes は YUV のテクスチャの中身（SDL の SDL_SW_YUVTexture）で、
    レンダラの肩代わりの層が持ち、更新のたびに全体を ARGB8888 に直して肩代わりへ写す。

  WHY:
    ソフトウェアのレンダラは YUV を直接描けない。GLES2 のドライバも 4:2:2 の詰めた形式
    （YUY2 系）は持たない。どちらも ARGB8888 に直してから描く（SDL と同じ）。

  RESOLVED:
    - 出力は ARGB8888 だけ。肩代わりのテクスチャの形式がそれだけなので、SDL の
      RGB565 / RGB24 / RGBA などの出力は写さない
    - スカラー版だけ（設計 §9.5）。SDL は x86 で幅 32 以上の部分を SSE2 で変換する

  PORT-NOTE(bug):
    SDL の参照版（3.4.2 より新しい）は、YV12 / IYUV / I0FL の詰めた画素の部分の更新（SDL_SW_UpdateYUVTexture）で、
    3 つ目の平面の書き込み先を「矩形の高さ」で測る（正しくはテクスチャの高さ）。矩形が全体より低いと
    3 つ目の平面の行が 2 つ目の平面に入る（D-78）。papimela は 3.4.2 と同じ正しい位置に書く。

  PORT-NOTE(bug):
    P010 の輝度のオフセット（y_shift）を SDL は 16 ビットの Y から引いてから 6 ビット寄せる（D-76）。
    限定範囲では黒（Y = 64）が (73, 73, 73) になる。papimela は SDL と同じ値にそろえている。

  PORT-NOTE(bug):
    SDL のスカラー版の clampU8 は (v + 128*64) >> 6 を 512 の表で引くとき & 511 で丸めるので、
    表の外（とても明るい・とても暗い）の値が反対側へ回り込む（明るすぎる赤が 0、暗すぎる青が 255）。
    SSE2 版は飽和させるので正しい。papimela は 0..255 に飽和させる。結果は SDL の SSE2 版と同じで、
    スカラー版（x86 では幅 32 未満の画像と、右端の 32 未満の列）とは回り込む画素だけ違う（D-62）。

  NOT RESOLVED:
    - RGB から YUV・YUV から YUV への変換は無い
    - I0FL の部分の Lock は断る（SDL の断りの一覧に I0FL が抜けている。papimela は I4FL と同じく全体だけ）
    - P010 のテクスチャは持たない。SDL のソフトウェアのレンダラも GLES2 も P010 のテクスチャを作れない
      （Vulkan などの GPU のドライバが持つときは、ドライバが SupportsTextureFormat で答える）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）

  YUV から RGB への変換（yuv2rgb の移植の部分）は次の BSD 3 条項ライセンスにも従う:

  Copyright (c) 2016, Adrien Descamps
  All rights reserved.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice, this
    list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

  * Neither the name of yuv2rgb nor the names of its
    contributors may be used to endorse or promote products derived from
    this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
}
unit PaPiMeLa.Surface.YUV;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface.Colorspace;

type
  { 変換の種類（SDL の YCbCrType。並びは係数の表と同じ）。 }
  TPMLYCbCrType = (BT601Full, BT601Limited, BT709Full, BT709Limited, BT2020Full);

  { YUV のテクスチャの中身（SDL_SW_YUVTexture）。平面は 1 つの連続した領域に、
    SDL と同じ並びと行の幅で置く。 }
  TPMLYUVPlanes = class
  strict private
    FFormat    : TPMLPixelFormat;
    FColorspace: TPMLColorspace;
    FWidth     : Integer;
    FHeight    : Integer;
    FPixels    : TBytes;
    FPitches   : array[0..2] of Integer;
    FOffsets   : array[0..2] of PtrUInt;    // 平面の先頭（FPixels の中の位置）
    function GetPlane(AIndex: Integer): PByte;
    function GetPitch(AIndex: Integer): Integer;
  public
    { 形式か色空間を変換できなければ EPMLArgument。中身は 0。 }
    constructor Create(AFormat: TPMLPixelFormat; AColorspace: TPMLColorspace;
      AWidth, AHeight: Integer);
    { 詰めた画素（SDL_SW_UpdateYUVTexture）。ARect はテクスチャの中に収まっていること。 }
    procedure Update(const ARect: TPMLRect; APixels: Pointer; APitch: Integer);
    { 平面ごと（SDL_SW_UpdateYUVTexturePlanar）。YV12 / IYUV / I444 だけ。 }
    procedure UpdatePlanar(const ARect: TPMLRect; AY: Pointer; AYPitch: Integer;
      AU: Pointer; AUPitch: Integer; AV: Pointer; AVPitch: Integer);
    { Y と、U・V を交互に詰めた平面（SDL_SW_UpdateNVTexturePlanar）。NV12 / NV21 だけ。 }
    procedure UpdateNV(const ARect: TPMLRect; AY: Pointer; AYPitch: Integer;
      AUV: Pointer; AUVPitch: Integer);
    { 全体を ARGB8888 に直して ADst へ書く（行の幅 ADstPitch バイト）。 }
    procedure ConvertToARGB8888(ADst: Pointer; ADstPitch: Integer);

    property Format    : TPMLPixelFormat read FFormat;
    property Colorspace: TPMLColorspace read FColorspace;
    property Width     : Integer read FWidth;
    property Height    : Integer read FHeight;
    // 平面 0..2 の先頭と行の幅（SDL の planes / pitches）。使わない平面は nil と 0。
    property Planes[AIndex: Integer]: PByte read GetPlane;
    property Pitches[AIndex: Integer]: Integer read GetPitch;
  end;

// このユニットがテクスチャの肩代わりで扱える YUV の形式か（YV12 / IYUV / I444 / NV12 / NV21 / YUY2 / UYVY / YVYU /
// I0FL / I4FL）。P010 は含まない（ARGB8888 の肩代わりでは 10 ビットを表せず、SDL も P010 のテクスチャを肩代わりしない）。
function PMLIsYUVFormat(AFormat: TPMLPixelFormat): Boolean;

// 色空間から変換の種類を選ぶ（GetYUVConversionType）。選べなければ False。
// BT.601 と BT.709 は限定・全範囲の両方、BT.2020 は全範囲だけ。
function PMLYCbCrTypeOf(AColorspace: TPMLColorspace; out AType: TPMLYCbCrType): Boolean;

// 詰めた画素の大きさと、Y の行の幅（SDL_CalculateYUVSize）。形式を知らなければ False。
function PMLCalculateYUVSize(AFormat: TPMLPixelFormat; AWidth, AHeight: Integer;
  out ASize: PtrUInt; out APitch: Integer): Boolean;

// 詰めた YUV の画素（Y の行の幅 ASrcPitch）を ARGB8888 に直す（SDL_ConvertPixels_YUV_to_RGB）。
// 形式か色空間を変換できなければ EPMLArgument。
procedure PMLConvertYUVToARGB8888(AWidth, AHeight: Integer; AFormat: TPMLPixelFormat;
  AColorspace: TPMLColorspace; ASrc: Pointer; ASrcPitch: Integer;
  ADst: Pointer; ADstPitch: Integer);

// P010（10 ビットを上位に置いた 16 ビットの Y と、U・V を交互に詰めた平面）を XBGR2101010 に直す
// （SDL_ConvertPixels_YUV_to_RGB の yuvp010_xbgr2101010_std）。ASrcPitch は Y の行の幅（バイト）。
procedure PMLConvertP010ToXBGR2101010(AWidth, AHeight: Integer; AColorspace: TPMLColorspace;
  ASrc: Pointer; ASrcPitch: Integer; ADst: Pointer; ADstPitch: Integer);

// I0FL / I4FL（16 ビットの Y・U・V の 3 平面。I0FL は色差が縦横とも半分、I4FL は同じ大きさ）を
// RGB48（R・G・B の順に 16 ビットずつ）に直す（yuvi0fl_rgb48_std / yuvi4fl_rgb48_std）。
// ASrcPitch は Y の行の幅（バイト）、ADstPitch は RGB48 の行の幅（バイト）。
// 形式が I0FL / I4FL でない、または色空間を変換できなければ EPMLArgument。
procedure PMLConvertYUV16ToRGB48(AWidth, AHeight: Integer; AFormat: TPMLPixelFormat;
  AColorspace: TPMLColorspace; ASrc: Pointer; ASrcPitch: Integer; ADst: Pointer; ADstPitch: Integer);

{ YUV の画素を、任意の形式・色空間の画素に直す（SDL_ConvertPixels_YUV_to_RGB）。
  ASrcPitch は Y の行の幅（バイト）、ADstPitch は出力の行の幅（バイト）。色空間が UNKNOWN なら形式の既定。
  経路は SDL と同じ:
    8 ビットの YUV  → ARGB8888（sRGB）に直してから、出力の形式・色空間へ
    P010            → XBGR2101010 に直してから（元の色空間のまま）、出力の形式・色空間へ
    I0FL / I4FL     → RGB48 に直してから（元の色空間のまま）、出力の形式・色空間へ
  出力が直接の形式（ARGB8888、XBGR2101010、RGB48）なら中継は要らない。
  YUV でない形式、変換できない色空間、出力がインデックス・YUV なら EPMLArgument。 }
procedure PMLConvertYUVPixels(AWidth, AHeight: Integer;
  ASrcFormat: TPMLPixelFormat; ASrcColorspace: TPMLColorspace; ASrc: Pointer; ASrcPitch: Integer;
  ADstFormat: TPMLPixelFormat; ADstColorspace: TPMLColorspace; ADst: Pointer; ADstPitch: Integer);

implementation

const
  { 係数の表（SDL の yuv_rgb_internal.h の YUV2RGB。V(x) = Trunc(x * 64 + 0.5) を計算済み）。
    並びは TPMLYCbCrType と同じ。各行は (y_shift, y_factor, v_r_factor, u_g_factor, v_g_factor, u_b_factor)。 }
  YUV2RGB: array[TPMLYCbCrType] of array[0..5] of LongInt = (
    (0, 64, 90, -22, -46, 113),     // BT601Full（JPEG。ITU-T T.871）
    (16, 75, 102, -25, -52, 129),   // BT601Limited
    (0, 64, 101, -12, -30, 119),    // BT709Full
    (16, 75, 115, -14, -34, 135),   // BT709Limited
    (0, 64, 94, -11, -37, 121));    // BT2020Full

{ 固定小数点（下 6 ビット）を 0..255 に飽和させる（SDL の clampU8）。

  PORT-NOTE(bug): SDL の clampU8 は ((V + 128*64) >> 6) and 511 で 512 の表を引くので、表の外の値が
  反対側へ回り込む（明るすぎると 0、暗すぎると 255）。SSE2 版は飽和させる。papimela は飽和させる（D-62）。 }
function Clamp8(V: LongInt): LongWord;
var
  T: LongInt;
begin
  T := SarLongint(V, 6);
  if T < 0 then
    Result := 0
  else if T > 255 then
    Result := 255
  else
    Result := LongWord(T);
end;

type
  { 標本の場所（SDL の GetYUVPlanes が返すもの）。 }
  TYUVLayout = record
    Y, U, V   : PByte;      // 最初の Y・U・V の標本
    YStride   : PtrInt;     // 行から次の行までのバイト数
    UVStride  : PtrInt;
    YStep     : PtrInt;     // 行の中で次の Y の標本までのバイト数
    UVStep    : PtrInt;     // 行の中で次の色差の標本までのバイト数
    ChromaRows: Integer;    // 色差 1 行が受け持つ画像の行数（4:2:0 と NV12 は 2、4:2:2 と 4:4:4 は 1）
    ChromaCols: Integer;    // 色差 1 標本が受け持つ画像の列数（4:4:4 は 1、ほかは 2）
  end;

{ 詰めた画素の中の各標本の場所（SDL の GetYUVPlanes）。 }
function GetLayout(AFormat: TPMLPixelFormat; AHeight: Integer; ASrc: Pointer;
  APitch: Integer; out L: TYUVLayout): Boolean;
var
  CP, CH: PtrInt;
  Chroma: PByte;
begin
  CP := (APitch + 1) div 2;
  CH := (AHeight + 1) div 2;
  Chroma := PByte(ASrc) + PtrInt(APitch) * AHeight;
  L.Y := PByte(ASrc);
  L.YStride := APitch;
  L.ChromaCols := 2;
  Result := True;
  case AFormat of
    PML_PIXELFORMAT_I444:
      begin
        L.U := Chroma;
        L.V := Chroma + PtrInt(APitch) * AHeight;
        L.UVStride := APitch;
        L.YStep := 1;
        L.UVStep := 1;
        L.ChromaRows := 1;
        L.ChromaCols := 1;
      end;
    PML_PIXELFORMAT_YV12, PML_PIXELFORMAT_IYUV:
      begin
        if AFormat = PML_PIXELFORMAT_YV12 then
        begin
          L.V := Chroma;
          L.U := Chroma + CP * CH;
        end
        else
        begin
          L.U := Chroma;
          L.V := Chroma + CP * CH;
        end;
        L.UVStride := CP;
        L.YStep := 1;
        L.UVStep := 1;
        L.ChromaRows := 2;
      end;
    PML_PIXELFORMAT_NV12, PML_PIXELFORMAT_NV21:
      begin
        if AFormat = PML_PIXELFORMAT_NV12 then
        begin
          L.U := Chroma;
          L.V := Chroma + 1;
        end
        else
        begin
          L.V := Chroma;
          L.U := Chroma + 1;
        end;
        L.UVStride := 2 * CP;
        L.YStep := 1;
        L.UVStep := 2;
        L.ChromaRows := 2;
      end;
    PML_PIXELFORMAT_YUY2, PML_PIXELFORMAT_UYVY, PML_PIXELFORMAT_YVYU:
      begin
        case AFormat of
          PML_PIXELFORMAT_YUY2:
            begin
              L.U := PByte(ASrc) + 1;
              L.V := PByte(ASrc) + 3;
            end;
          PML_PIXELFORMAT_UYVY:
            begin
              L.Y := PByte(ASrc) + 1;
              L.U := PByte(ASrc);
              L.V := PByte(ASrc) + 2;
            end;
        else
          L.V := PByte(ASrc) + 1;
          L.U := PByte(ASrc) + 3;
        end;
        L.UVStride := APitch;
        L.YStep := 2;
        L.UVStep := 4;
        L.ChromaRows := 1;
      end;
  else
    Result := False;
  end;
end;

function PMLIsYUVFormat(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := (AFormat = PML_PIXELFORMAT_YV12) or (AFormat = PML_PIXELFORMAT_IYUV)
         or (AFormat = PML_PIXELFORMAT_NV12) or (AFormat = PML_PIXELFORMAT_NV21)
         or (AFormat = PML_PIXELFORMAT_YUY2) or (AFormat = PML_PIXELFORMAT_UYVY)
         or (AFormat = PML_PIXELFORMAT_YVYU) or (AFormat = PML_PIXELFORMAT_I444)
         or (AFormat = PML_PIXELFORMAT_I0FL) or (AFormat = PML_PIXELFORMAT_I4FL);
end;

{ SDL の GetYUVConversionType。JPEG と BT.601 の全範囲は同じ行列。BT.2020 は全範囲だけ。 }
function PMLYCbCrTypeOf(AColorspace: TPMLColorspace; out AType: TPMLYCbCrType): Boolean;
begin
  Result := True;
  case AColorspace of
    PML_COLORSPACE_JPEG, PML_COLORSPACE_BT601_FULL: AType := TPMLYCbCrType.BT601Full;
    PML_COLORSPACE_BT601_LIMITED: AType := TPMLYCbCrType.BT601Limited;
    PML_COLORSPACE_BT709_FULL: AType := TPMLYCbCrType.BT709Full;
    PML_COLORSPACE_BT709_LIMITED: AType := TPMLYCbCrType.BT709Limited;
    PML_COLORSPACE_BT2020_FULL: AType := TPMLYCbCrType.BT2020Full;
  else
    AType := TPMLYCbCrType.BT601Limited;
    Result := False;
  end;
end;

{ SDL_CalculateYUVSize（この形式だけ。1 標本 1 バイト）。 }
function PMLCalculateYUVSize(AFormat: TPMLPixelFormat; AWidth, AHeight: Integer;
  out ASize: PtrUInt; out APitch: Integer): Boolean;
var
  Chroma: PtrUInt;
begin
  Result := True;
  Chroma := PtrUInt((AWidth + 1) div 2) * PtrUInt((AHeight + 1) div 2);
  case AFormat of
    PML_PIXELFORMAT_YV12, PML_PIXELFORMAT_IYUV, PML_PIXELFORMAT_NV12, PML_PIXELFORMAT_NV21:
      begin
        APitch := AWidth;
        ASize := PtrUInt(AWidth) * PtrUInt(AHeight) + 2 * Chroma;
      end;
    PML_PIXELFORMAT_YUY2, PML_PIXELFORMAT_UYVY, PML_PIXELFORMAT_YVYU:
      begin
        APitch := ((AWidth + 1) div 2) * 4;
        ASize := PtrUInt(APitch) * PtrUInt(AHeight);
      end;
    PML_PIXELFORMAT_I444:
      begin
        APitch := AWidth;
        ASize := 3 * PtrUInt(AWidth) * PtrUInt(AHeight);
      end;
    PML_PIXELFORMAT_P010:
      begin
        // 1 標本 2 バイト。色差は U・V を交互に詰めるので、1 区画が 4 バイト
        APitch := 2 * AWidth;
        ASize := PtrUInt(APitch) * PtrUInt(AHeight) + 4 * Chroma;
      end;
    PML_PIXELFORMAT_I0FL:
      begin
        // 1 標本 2 バイトの 3 平面。U・V は縦横とも半分（切り上げ）
        APitch := 2 * AWidth;
        ASize := PtrUInt(APitch) * PtrUInt(AHeight) + 4 * Chroma;
      end;
    PML_PIXELFORMAT_I4FL:
      begin
        APitch := 2 * AWidth;
        ASize := 3 * PtrUInt(APitch) * PtrUInt(AHeight);
      end;
  else
    ASize := 0;
    APitch := 0;
    Result := False;
  end;
end;

{ SDL_ConvertPixels_YUV_to_RGB と yuv_rgb_std の ARGB8888 の出力。

  SDL は 2x2（4:2:2 は 2x1）ずつ回り、端の奇数の列と行を別に描くが、どの画素も「自分の Y と、
  自分の区画の U・V」で決まるので、1 画素ずつ同じ式で計算しても結果は同じになる。 }
procedure PMLConvertYUVToARGB8888(AWidth, AHeight: Integer; AFormat: TPMLPixelFormat;
  AColorspace: TPMLColorspace; ASrc: Pointer; ASrcPitch: Integer;
  ADst: Pointer; ADstPitch: Integer);
var
  L: TYUVLayout;
  Kind: TPMLYCbCrType;
  X, Y, CY: Integer;
  YRow, URow, VRow: PByte;
  Dst: PLongWord;
  YT, UT, VT, RT, GT, BT, YShift, YFactor, VR, UG, VG, UB: LongInt;
begin
  if not GetLayout(AFormat, AHeight, ASrc, ASrcPitch, L) then
    raise EPMLArgument.CreateFmt('%s is not a YUV format the converter knows',
      [PMLPixelFormatName(AFormat)]);
  if not PMLYCbCrTypeOf(AColorspace, Kind) then
    raise EPMLArgument.CreateFmt('colorspace $%.8x has no YUV conversion', [AColorspace]);
  YShift := YUV2RGB[Kind][0];
  YFactor := YUV2RGB[Kind][1];
  VR := YUV2RGB[Kind][2];
  UG := YUV2RGB[Kind][3];
  VG := YUV2RGB[Kind][4];
  UB := YUV2RGB[Kind][5];
  for Y := 0 to AHeight - 1 do
  begin
    CY := Y div L.ChromaRows;
    YRow := L.Y + PtrInt(Y) * L.YStride;
    URow := L.U + PtrInt(CY) * L.UVStride;
    VRow := L.V + PtrInt(CY) * L.UVStride;
    Dst := PLongWord(PByte(ADst) + PtrInt(Y) * ADstPitch);
    for X := 0 to AWidth - 1 do
    begin
      UT := LongInt((URow + PtrInt(X div L.ChromaCols) * L.UVStep)^) - 128;
      VT := LongInt((VRow + PtrInt(X div L.ChromaCols) * L.UVStep)^) - 128;
      RT := VT * VR;
      GT := (UT * UG) + (VT * VG);
      BT := UT * UB;
      YT := (LongInt((YRow + PtrInt(X) * L.YStep)^) - YShift) * YFactor;
      Dst[X] := $FF000000 or (Clamp8(YT + RT) shl 16) or (Clamp8(YT + GT) shl 8) or Clamp8(YT + BT);
    end;
  end;
end;

{ ---- TPMLYUVPlanes（SDL_yuv_sw.c） ---- }

{ SDL_SW_CreateYUVTexture。 }
constructor TPMLYUVPlanes.Create(AFormat: TPMLPixelFormat; AColorspace: TPMLColorspace;
  AWidth, AHeight: Integer);
var
  Kind: TPMLYCbCrType;
  Size: PtrUInt;
  Pitch: Integer;
begin
  inherited Create;
  if not PMLIsYUVFormat(AFormat) then
    raise EPMLArgument.CreateFmt('%s textures are not supported', [PMLPixelFormatName(AFormat)]);
  if not PMLYCbCrTypeOf(AColorspace, Kind) then
    raise EPMLArgument.CreateFmt('colorspace $%.8x has no YUV conversion', [AColorspace]);
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EPMLArgument.CreateFmt('YUV size must be positive (%d x %d)', [AWidth, AHeight]);
  FFormat := AFormat;
  FColorspace := AColorspace;
  FWidth := AWidth;
  FHeight := AHeight;
  PMLCalculateYUVSize(AFormat, AWidth, AHeight, Size, Pitch);
  SetLength(FPixels, Size);
  FillChar(FPixels[0], Size, 0);
  case AFormat of
    PML_PIXELFORMAT_YV12, PML_PIXELFORMAT_IYUV:
      begin
        FPitches[0] := AWidth;
        FPitches[1] := (AWidth + 1) div 2;
        FPitches[2] := FPitches[1];
        FOffsets[0] := 0;
        FOffsets[1] := PtrUInt(FPitches[0]) * PtrUInt(AHeight);
        FOffsets[2] := FOffsets[1] + PtrUInt(FPitches[1]) * PtrUInt((AHeight + 1) div 2);
      end;
    PML_PIXELFORMAT_NV12, PML_PIXELFORMAT_NV21:
      begin
        FPitches[0] := AWidth;
        FPitches[1] := 2 * ((AWidth + 1) div 2);
        FOffsets[0] := 0;
        FOffsets[1] := PtrUInt(AWidth) * PtrUInt(AHeight);
      end;
    PML_PIXELFORMAT_I444:
      begin
        FPitches[0] := AWidth;
        FPitches[1] := AWidth;
        FPitches[2] := AWidth;
        FOffsets[0] := 0;
        FOffsets[1] := PtrUInt(AWidth) * PtrUInt(AHeight);
        FOffsets[2] := 2 * FOffsets[1];
      end;
    PML_PIXELFORMAT_I0FL:
      begin
        // 1 標本 2 バイト。色差は縦横とも半分（IYUV と同じ並び: Y、U、V）
        FPitches[0] := 2 * AWidth;
        FPitches[1] := ((AWidth + 1) div 2) * 2;
        FPitches[2] := FPitches[1];
        FOffsets[0] := 0;
        FOffsets[1] := PtrUInt(FPitches[0]) * PtrUInt(AHeight);
        FOffsets[2] := FOffsets[1] + PtrUInt(FPitches[1]) * PtrUInt((AHeight + 1) div 2);
      end;
    PML_PIXELFORMAT_I4FL:
      begin
        FPitches[0] := 2 * AWidth;
        FPitches[1] := FPitches[0];
        FPitches[2] := FPitches[0];
        FOffsets[0] := 0;
        FOffsets[1] := PtrUInt(FPitches[0]) * PtrUInt(AHeight);
        FOffsets[2] := 2 * FOffsets[1];
      end;
  else
    FPitches[0] := ((AWidth + 1) div 2) * 4;
    FOffsets[0] := 0;
  end;
end;

function TPMLYUVPlanes.GetPlane(AIndex: Integer): PByte;
begin
  if (AIndex < 0) or (AIndex > 2) or (FPitches[AIndex] = 0) then
    Result := nil
  else
    Result := @FPixels[FOffsets[AIndex]];
end;

function TPMLYUVPlanes.GetPitch(AIndex: Integer): Integer;
begin
  if (AIndex < 0) or (AIndex > 2) then
    Result := 0
  else
    Result := FPitches[AIndex];
end;

{ ARows 行を、行の幅 ASrcPitch・ADstPitch で ALen バイトずつ写す。 }
procedure CopyRows(ASrc, ADst: PByte; ASrcPitch, ADstPitch: PtrInt; ALen, ARows: Integer);
var
  Row: Integer;
begin
  for Row := 0 to ARows - 1 do
  begin
    Move(ASrc^, ADst^, ALen);
    Inc(ASrc, ASrcPitch);
    Inc(ADst, ADstPitch);
  end;
end;

{ 詰めた画素で更新する（SDL_SW_UpdateYUVTexture）。

  PORT-NOTE(bug): SDL は NV12 / NV21 で矩形が全体なら、行の幅を見ずに丸ごと写す（YV12 / IYUV は
  行の幅が詰まっているときだけ）。行の幅に余りがあると、余りのバイトを画素として読む（D-63）。
  papimela は NV12 / NV21 でも行の幅が詰まっているときだけ丸ごと写す。 }
procedure TPMLYUVPlanes.Update(const ARect: TPMLRect; APixels: Pointer; APitch: Integer);
var
  Base, Src: PByte;
  UVPitch: PtrInt;
  CW, CH, Plane: Integer;
begin
  Base := @FPixels[0];
  CW := (FWidth + 1) div 2;
  CH := (FHeight + 1) div 2;
  case FFormat of
    PML_PIXELFORMAT_YV12, PML_PIXELFORMAT_IYUV:
      if (ARect.X = 0) and (ARect.Y = 0) and (ARect.W = FWidth) and (ARect.H = FHeight)
      and (APitch = FPitches[0]) then
        Move(APixels^, Base^, FHeight * FWidth + 2 * CH * CW)
      else
      begin
        UVPitch := (APitch + 1) div 2;
        // Y
        CopyRows(PByte(APixels), Base + PtrInt(ARect.Y) * FWidth + ARect.X,
          APitch, FPitches[0], ARect.W, ARect.H);
        // 次の平面（YV12 は V、IYUV は U。詰めた画素と同じ並びなので、そのまま写す）
        Src := PByte(APixels) + PtrInt(ARect.H) * APitch;
        CopyRows(Src, Base + PtrInt(FHeight) * FPitches[0]
          + PtrInt(ARect.Y div 2) * FPitches[1] + (ARect.X div 2),
          UVPitch, FPitches[1], (ARect.W + 1) div 2, (ARect.H + 1) div 2);
        // その次の平面
        Src := PByte(APixels) + PtrInt(ARect.H) * APitch + PtrInt((ARect.H + 1) div 2) * UVPitch;
        CopyRows(Src, Base + PtrInt(FHeight) * FPitches[0] + PtrInt(CH) * FPitches[1]
          + PtrInt(ARect.Y div 2) * FPitches[2] + (ARect.X div 2),
          UVPitch, FPitches[2], (ARect.W + 1) div 2, (ARect.H + 1) div 2);
      end;
    PML_PIXELFORMAT_NV12, PML_PIXELFORMAT_NV21:
      if (ARect.X = 0) and (ARect.Y = 0) and (ARect.W = FWidth) and (ARect.H = FHeight)
      and (APitch = FPitches[0]) then
        Move(APixels^, Base^, FHeight * FWidth + 2 * CH * CW)
      else
      begin
        CopyRows(PByte(APixels), Base + PtrInt(ARect.Y) * FWidth + ARect.X,
          APitch, FWidth, ARect.W, ARect.H);
        // SDL と同じく、色差の行は (y + 1) div 2 から（y が奇数のとき 1 行下から書く）
        Src := PByte(APixels) + PtrInt(ARect.H) * APitch;
        CopyRows(Src, Base + PtrInt(FHeight) * FWidth
          + 2 * PtrInt((ARect.Y + 1) div 2) * CW + 2 * (ARect.X div 2),
          2 * ((APitch + 1) div 2), 2 * CW, 2 * ((ARect.W + 1) div 2), (ARect.H + 1) div 2);
      end;
    PML_PIXELFORMAT_I0FL:
      // 1 標本 2 バイトの IYUV（SDL_SW_UpdateYUVTexture の YV12 / IYUV / I0FL）
      if (ARect.X = 0) and (ARect.Y = 0) and (ARect.W = FWidth) and (ARect.H = FHeight)
      and (APitch = FPitches[0]) then
        Move(APixels^, Base^, FHeight * FWidth * 2 + 2 * CH * CW * 2)
      else
      begin
        UVPitch := (((APitch div 2) + 1) div 2) * 2;
        CopyRows(PByte(APixels), Base + PtrInt(ARect.Y) * FPitches[0] + ARect.X * 2,
          APitch, FPitches[0], ARect.W * 2, ARect.H);
        Src := PByte(APixels) + PtrInt(ARect.H) * APitch;
        CopyRows(Src, Base + PtrInt(FOffsets[1]) + PtrInt(ARect.Y div 2) * FPitches[1] + (ARect.X div 2) * 2,
          UVPitch, FPitches[1], ((ARect.W + 1) div 2) * 2, (ARect.H + 1) div 2);
        Src := PByte(APixels) + PtrInt(ARect.H) * APitch + PtrInt((ARect.H + 1) div 2) * UVPitch;
        CopyRows(Src, Base + PtrInt(FOffsets[2]) + PtrInt(ARect.Y div 2) * FPitches[2] + (ARect.X div 2) * 2,
          UVPitch, FPitches[2], ((ARect.W + 1) div 2) * 2, (ARect.H + 1) div 2);
      end;
    PML_PIXELFORMAT_I4FL:
      // 1 標本 2 バイトの I444
      if (ARect.X = 0) and (ARect.Y = 0) and (ARect.W = FWidth) and (ARect.H = FHeight)
      and (APitch = FPitches[0]) then
        Move(APixels^, Base^, 3 * FHeight * APitch)
      else
      begin
        Src := PByte(APixels);
        for Plane := 0 to 2 do
        begin
          CopyRows(Src, Base + PtrInt(FOffsets[Plane]) + PtrInt(ARect.Y) * FPitches[Plane] + ARect.X * 2,
            APitch, FPitches[Plane], ARect.W * 2, ARect.H);
          Inc(Src, PtrInt(ARect.H) * APitch);
        end;
      end;
    PML_PIXELFORMAT_I444:
      // 色差も Y と同じ大きさ。全体で行の幅が詰まっていれば丸ごと、でなければ 3 平面を続けて読む
      if (ARect.X = 0) and (ARect.Y = 0) and (ARect.W = FWidth) and (ARect.H = FHeight)
      and (APitch = FPitches[0]) then
        Move(APixels^, Base^, 3 * FHeight * FWidth)
      else
      begin
        Src := PByte(APixels);
        for Plane := 0 to 2 do
        begin
          CopyRows(Src, Base + PtrInt(FOffsets[Plane]) + PtrInt(ARect.Y) * FPitches[Plane] + ARect.X,
            APitch, FPitches[Plane], ARect.W, ARect.H);
          Inc(Src, PtrInt(ARect.H) * APitch);
        end;
      end;
  else
    // YUY2 / UYVY / YVYU
    CopyRows(PByte(APixels), Base + PtrInt(ARect.Y) * FPitches[0] + PtrInt(ARect.X) * 2,
      APitch, FPitches[0], 4 * ((ARect.W + 1) div 2), ARect.H);
  end;
end;

{ 平面ごとに更新する（SDL_SW_UpdateYUVTexturePlanar の YV12 / IYUV / I444）。 }
procedure TPMLYUVPlanes.UpdatePlanar(const ARect: TPMLRect; AY: Pointer; AYPitch: Integer;
  AU: Pointer; AUPitch: Integer; AV: Pointer; AVPitch: Integer);
var
  Base, First, Second: PByte;
  Offset: PtrInt;
  CW, CH: Integer;
begin
  Base := @FPixels[0];
  CW := (FWidth + 1) div 2;
  CH := (FHeight + 1) div 2;
  if (FFormat = PML_PIXELFORMAT_I0FL) or (FFormat = PML_PIXELFORMAT_I4FL) then
  begin
    // 1 標本 2 バイト
    CopyRows(PByte(AY), Base + PtrInt(ARect.Y) * FPitches[0] + ARect.X * 2,
      AYPitch, FPitches[0], ARect.W * 2, ARect.H);
    if FFormat = PML_PIXELFORMAT_I4FL then
    begin
      CopyRows(PByte(AU), Base + PtrInt(FOffsets[1]) + PtrInt(ARect.Y) * FPitches[1] + ARect.X * 2,
        AUPitch, FPitches[1], ARect.W * 2, ARect.H);
      CopyRows(PByte(AV), Base + PtrInt(FOffsets[2]) + PtrInt(ARect.Y) * FPitches[2] + ARect.X * 2,
        AVPitch, FPitches[2], ARect.W * 2, ARect.H);
    end
    else
    begin
      CopyRows(PByte(AU), Base + PtrInt(FOffsets[1]) + PtrInt(ARect.Y div 2) * FPitches[1] + (ARect.X div 2) * 2,
        AUPitch, FPitches[1], ((ARect.W + 1) div 2) * 2, (ARect.H + 1) div 2);
      CopyRows(PByte(AV), Base + PtrInt(FOffsets[2]) + PtrInt(ARect.Y div 2) * FPitches[2] + (ARect.X div 2) * 2,
        AVPitch, FPitches[2], ((ARect.W + 1) div 2) * 2, (ARect.H + 1) div 2);
    end;
    Exit;
  end;
  CopyRows(PByte(AY), Base + PtrInt(ARect.Y) * FPitches[0] + ARect.X,
    AYPitch, FPitches[0], ARect.W, ARect.H);
  if FFormat = PML_PIXELFORMAT_I444 then
  begin
    // 色差も Y と同じ大きさ
    CopyRows(PByte(AU), Base + PtrInt(FOffsets[1]) + PtrInt(ARect.Y) * FPitches[1] + ARect.X,
      AUPitch, FPitches[1], ARect.W, ARect.H);
    CopyRows(PByte(AV), Base + PtrInt(FOffsets[2]) + PtrInt(ARect.Y) * FPitches[2] + ARect.X,
      AVPitch, FPitches[2], ARect.W, ARect.H);
    Exit;
  end;
  // 色差の平面は Y の後に 2 つ。IYUV は U・V、YV12 は V・U の順
  First := Base + PtrInt(FHeight) * FPitches[0];
  Second := First + PtrInt(CH) * FPitches[1];
  Offset := PtrInt(ARect.Y div 2) * CW + (ARect.X div 2);
  if FFormat = PML_PIXELFORMAT_IYUV then
  begin
    CopyRows(PByte(AU), First + Offset, AUPitch, FPitches[1], (ARect.W + 1) div 2, (ARect.H + 1) div 2);
    CopyRows(PByte(AV), Second + Offset, AVPitch, FPitches[2], (ARect.W + 1) div 2, (ARect.H + 1) div 2);
  end
  else
  begin
    CopyRows(PByte(AU), Second + Offset, AUPitch, FPitches[1], (ARect.W + 1) div 2, (ARect.H + 1) div 2);
    CopyRows(PByte(AV), First + Offset, AVPitch, FPitches[2], (ARect.W + 1) div 2, (ARect.H + 1) div 2);
  end;
end;

{ Y と、U・V を交互に詰めた平面で更新する（SDL_SW_UpdateNVTexturePlanar）。
  色差の位置は SDL と同じく y * ((w + 1) div 2) + x（y と x が偶数なら区画の位置そのもの）。 }
procedure TPMLYUVPlanes.UpdateNV(const ARect: TPMLRect; AY: Pointer; AYPitch: Integer;
  AUV: Pointer; AUVPitch: Integer);
var
  Base: PByte;
  CW: Integer;
begin
  Base := @FPixels[0];
  CW := (FWidth + 1) div 2;
  CopyRows(PByte(AY), Base + PtrInt(ARect.Y) * FWidth + ARect.X,
    AYPitch, FWidth, ARect.W, ARect.H);
  CopyRows(PByte(AUV), Base + PtrInt(FHeight) * FWidth + PtrInt(ARect.Y) * CW + ARect.X,
    AUVPitch, 2 * CW, 2 * ((ARect.W + 1) div 2), (ARect.H + 1) div 2);
end;

{ SDL の clamp10: 固定小数点（下 6 ビット）を 0..1023 に飽和させる。 }
function Clamp10(V: LongInt): LongWord;
var
  T: LongInt;
begin
  T := SarLongint(V, 6);
  if T < 0 then
    Result := 0
  else if T > 1023 then
    Result := 1023
  else
    Result := LongWord(T);
end;

{ SDL_ConvertPixels_YUV_to_RGB の P010 から XBGR2101010（yuvp010_xbgr2101010_std）。
  1 画素ずつ同じ式で計算する（SDL は 2x2 ずつ回るが、どの画素も自分の Y と区画の U・V で決まる）。

  PORT-NOTE: SDL は Y から y_shift を引くのを 16 ビットの値に対して行ってから 6 ビット右へ寄せる
  （GET(Y - y_shift)）。y_shift は 8 ビットの 16（限定範囲の黒）なので、10 ビットの限定範囲の黒（64）の
  代わりに 16 / 64 を引く。10 ビットの全範囲（BT.2020 の全範囲）では y_shift が 0 なので影響しない。
  papimela は SDL と同じ値にそろえる。 }
procedure PMLConvertP010ToXBGR2101010(AWidth, AHeight: Integer; AColorspace: TPMLColorspace;
  ASrc: Pointer; ASrcPitch: Integer; ADst: Pointer; ADstPitch: Integer);
var
  Kind: TPMLYCbCrType;
  UVPitch: PtrInt;
  X, Y: Integer;
  YRow, UVRow: PWord;
  Dst: PLongWord;
  YT, UT, VT, RT, GT, BT, YShift, YFactor, VR, UG, VG, UB: LongInt;
begin
  if not PMLYCbCrTypeOf(AColorspace, Kind) then
    raise EPMLArgument.CreateFmt('colorspace $%.8x has no YUV conversion', [AColorspace]);
  YShift := YUV2RGB[Kind][0];
  YFactor := YUV2RGB[Kind][1];
  VR := YUV2RGB[Kind][2];
  UG := YUV2RGB[Kind][3];
  VG := YUV2RGB[Kind][4];
  UB := YUV2RGB[Kind][5];
  // 色差の行の幅は、Y の行の幅と、区画ごとに 4 バイトの大きいほう（SDL の GetYUVPlanes）
  UVPitch := ((AWidth + 1) div 2) * 4;
  if UVPitch < ASrcPitch then
    UVPitch := ASrcPitch;
  for Y := 0 to AHeight - 1 do
  begin
    YRow := PWord(PByte(ASrc) + PtrInt(Y) * ASrcPitch);
    UVRow := PWord(PByte(ASrc) + PtrInt(ASrcPitch) * AHeight + PtrInt(Y div 2) * UVPitch);
    Dst := PLongWord(PByte(ADst) + PtrInt(Y) * ADstPitch);
    for X := 0 to AWidth - 1 do
    begin
      UT := LongInt(UVRow[(X div 2) * 2] shr 6) - 512;
      VT := LongInt(UVRow[(X div 2) * 2 + 1] shr 6) - 512;
      RT := VT * VR;
      GT := (UT * UG) + (VT * VG);
      BT := UT * UB;
      YT := SarLongint(LongInt(YRow[X]) - YShift, 6) * YFactor;
      Dst[X] := $C0000000 or (Clamp10(YT + BT) shl 20) or (Clamp10(YT + GT) shl 10) or Clamp10(YT + RT);
    end;
  end;
end;

{ SDL の clamp16: 固定小数点（下 6 ビット）を 0..65535 に飽和させる。 }
function Clamp16(V: LongInt): Word;
var
  T: LongInt;
begin
  T := SarLongint(V, 6);
  if T < 0 then
    Result := 0
  else if T > 65535 then
    Result := 65535
  else
    Result := Word(T);
end;

{ yuvi0fl_rgb48_std と yuvi4fl_rgb48_std。P010 と同じく、1 画素ずつ同じ式で計算する。

  PORT-NOTE(bug): SDL は 16 ビットの Y から y_shift（8 ビットの 16）をそのまま引く。限定範囲の黒
  （16 ビットで 16 << 8）は 0 にならず、BT.709 の限定範囲では 4781 になる（D-77。D-76 の 16 ビット版）。
  papimela は SDL と同じ値にそろえる。 }
procedure PMLConvertYUV16ToRGB48(AWidth, AHeight: Integer; AFormat: TPMLPixelFormat;
  AColorspace: TPMLColorspace; ASrc: Pointer; ASrcPitch: Integer; ADst: Pointer; ADstPitch: Integer);
var
  Kind: TPMLYCbCrType;
  Is444: Boolean;
  UVPitch: PtrInt;
  X, Y, CX: Integer;
  YRow, URow, VRow: PWord;
  UPlane, VPlane: PByte;
  Dst: PWord;
  YT, UT, VT, RT, GT, BT, YShift, YFactor, VR, UG, VG, UB: LongInt;
begin
  if (AFormat <> PML_PIXELFORMAT_I0FL) and (AFormat <> PML_PIXELFORMAT_I4FL) then
    raise EPMLArgument.CreateFmt('%s is not an I0FL or I4FL format', [PMLPixelFormatName(AFormat)]);
  if not PMLYCbCrTypeOf(AColorspace, Kind) then
    raise EPMLArgument.CreateFmt('colorspace $%.8x has no YUV conversion', [AColorspace]);
  Is444 := AFormat = PML_PIXELFORMAT_I4FL;
  YShift := YUV2RGB[Kind][0];
  YFactor := YUV2RGB[Kind][1];
  VR := YUV2RGB[Kind][2];
  UG := YUV2RGB[Kind][3];
  VG := YUV2RGB[Kind][4];
  UB := YUV2RGB[Kind][5];
  UPlane := PByte(ASrc) + PtrInt(ASrcPitch) * AHeight;
  if Is444 then
  begin
    UVPitch := ASrcPitch;
    VPlane := UPlane + UVPitch * AHeight;
  end
  else
  begin
    // 色差の行の幅は ((Y の行の幅 / 2 + 1) / 2) 標本（SDL の GetYUVPlanes）
    UVPitch := (((ASrcPitch div 2) + 1) div 2) * 2;
    VPlane := UPlane + UVPitch * ((AHeight + 1) div 2);
  end;
  for Y := 0 to AHeight - 1 do
  begin
    YRow := PWord(PByte(ASrc) + PtrInt(Y) * ASrcPitch);
    if Is444 then
    begin
      URow := PWord(UPlane + PtrInt(Y) * UVPitch);
      VRow := PWord(VPlane + PtrInt(Y) * UVPitch);
    end
    else
    begin
      URow := PWord(UPlane + PtrInt(Y div 2) * UVPitch);
      VRow := PWord(VPlane + PtrInt(Y div 2) * UVPitch);
    end;
    Dst := PWord(PByte(ADst) + PtrInt(Y) * ADstPitch);
    for X := 0 to AWidth - 1 do
    begin
      if Is444 then
        CX := X
      else
        CX := X div 2;
      UT := LongInt(URow[CX]) - 32768;
      VT := LongInt(VRow[CX]) - 32768;
      RT := VT * VR;
      GT := (UT * UG) + (VT * VG);
      BT := UT * UB;
      YT := (LongInt(YRow[X]) - YShift) * YFactor;
      Dst[X * 3] := Clamp16(YT + RT);
      Dst[X * 3 + 1] := Clamp16(YT + GT);
      Dst[X * 3 + 2] := Clamp16(YT + BT);
    end;
  end;
end;

procedure PMLConvertYUVPixels(AWidth, AHeight: Integer;
  ASrcFormat: TPMLPixelFormat; ASrcColorspace: TPMLColorspace; ASrc: Pointer; ASrcPitch: Integer;
  ADstFormat: TPMLPixelFormat; ADstColorspace: TPMLColorspace; ADst: Pointer; ADstPitch: Integer);
var
  SCS, DCS: TPMLColorspace;
  Tmp: TBytes;
  TmpFormat: TPMLPixelFormat;
  TmpPitch, X, Y: Integer;
  TmpColorspace: TPMLColorspace;
begin
  if not (PMLIsYUVFormat(ASrcFormat) or (ASrcFormat = PML_PIXELFORMAT_P010)
  or (ASrcFormat = PML_PIXELFORMAT_I0FL) or (ASrcFormat = PML_PIXELFORMAT_I4FL)) then
    raise EPMLArgument.CreateFmt('%s is not a YUV format the converter knows',
      [PMLPixelFormatName(ASrcFormat)]);
  if PMLIsPixelFormatFourCC(ADstFormat) or PMLIsPixelFormatIndexed(ADstFormat)
  or (ADstFormat = PML_PIXELFORMAT_UNKNOWN) then
    raise EPMLArgument.CreateFmt('%s cannot be a destination of a YUV conversion',
      [PMLPixelFormatName(ADstFormat)]);
  if (AWidth <= 0) or (AHeight <= 0) then
    Exit;
  SCS := ASrcColorspace;
  if SCS = PML_COLORSPACE_UNKNOWN then
    SCS := PMLDefaultColorspace(ASrcFormat);
  DCS := ADstColorspace;
  if DCS = PML_COLORSPACE_UNKNOWN then
    DCS := PMLDefaultColorspace(ADstFormat);

  if ASrcFormat = PML_PIXELFORMAT_P010 then
  begin
    if ADstFormat = PML_PIXELFORMAT_XBGR2101010 then
    begin
      PMLConvertP010ToXBGR2101010(AWidth, AHeight, SCS, ASrc, ASrcPitch, ADst, ADstPitch);
      Exit;
    end;
    TmpFormat := PML_PIXELFORMAT_XBGR2101010;
    TmpPitch := AWidth * 4;
    TmpColorspace := SCS;
    SetLength(Tmp, TmpPitch * AHeight);
    PMLConvertP010ToXBGR2101010(AWidth, AHeight, SCS, ASrc, ASrcPitch, @Tmp[0], TmpPitch);
  end
  else if (ASrcFormat = PML_PIXELFORMAT_I0FL) or (ASrcFormat = PML_PIXELFORMAT_I4FL) then
  begin
    if ADstFormat = PML_PIXELFORMAT_RGB48 then
    begin
      PMLConvertYUV16ToRGB48(AWidth, AHeight, ASrcFormat, SCS, ASrc, ASrcPitch, ADst, ADstPitch);
      Exit;
    end;
    TmpFormat := PML_PIXELFORMAT_RGB48;
    TmpPitch := AWidth * 6;
    TmpColorspace := SCS;
    SetLength(Tmp, TmpPitch * AHeight);
    PMLConvertYUV16ToRGB48(AWidth, AHeight, ASrcFormat, SCS, ASrc, ASrcPitch, @Tmp[0], TmpPitch);
  end
  else
  begin
    if ADstFormat = PML_PIXELFORMAT_ARGB8888 then
    begin
      PMLConvertYUVToARGB8888(AWidth, AHeight, ASrcFormat, SCS, ASrc, ASrcPitch, ADst, ADstPitch);
      Exit;
    end;
    TmpFormat := PML_PIXELFORMAT_ARGB8888;
    TmpPitch := AWidth * 4;
    TmpColorspace := PML_COLORSPACE_SRGB;
    SetLength(Tmp, TmpPitch * AHeight);
    PMLConvertYUVToARGB8888(AWidth, AHeight, ASrcFormat, SCS, ASrc, ASrcPitch, @Tmp[0], TmpPitch);
  end;
  PMLConvertPixelsAndColorspace(AWidth, AHeight, TmpFormat, TmpColorspace, @Tmp[0], TmpPitch,
    ADstFormat, DCS, ADst, ADstPitch);
  // 8 ビットの YUV の直接の変換（yuv_rgb_std）は、X の付く 8888 の X のバイトにも 0xFF を書く
  // （P010 / I0FL / I4FL の中継を通る道は書かない）
  if (ASrcFormat <> PML_PIXELFORMAT_I0FL) and (ASrcFormat <> PML_PIXELFORMAT_I4FL)
  and (ASrcFormat <> PML_PIXELFORMAT_P010) and ((ADstFormat = PML_PIXELFORMAT_XRGB8888) or (ADstFormat = PML_PIXELFORMAT_XBGR8888)
  or (ADstFormat = PML_PIXELFORMAT_RGBX8888) or (ADstFormat = PML_PIXELFORMAT_BGRX8888)) then
    for Y := 0 to AHeight - 1 do
      for X := 0 to AWidth - 1 do
        if (ADstFormat = PML_PIXELFORMAT_XRGB8888) or (ADstFormat = PML_PIXELFORMAT_XBGR8888) then
          PByte(ADst)[PtrInt(Y) * ADstPitch + X * 4 + 3] := $FF
        else
          PByte(ADst)[PtrInt(Y) * ADstPitch + X * 4] := $FF;
end;

procedure TPMLYUVPlanes.ConvertToARGB8888(ADst: Pointer; ADstPitch: Integer);
begin
  if (FFormat = PML_PIXELFORMAT_I0FL) or (FFormat = PML_PIXELFORMAT_I4FL) then
    // 16 ビットは RGB48 を経て、色空間を sRGB に直す（SDL_SW_CopyYUVToRGB）
    PMLConvertYUVPixels(FWidth, FHeight, FFormat, FColorspace, @FPixels[0], FPitches[0],
      PML_PIXELFORMAT_ARGB8888, PML_COLORSPACE_SRGB, ADst, ADstPitch)
  else
    PMLConvertYUVToARGB8888(FWidth, FHeight, FFormat, FColorspace, @FPixels[0], FPitches[0],
      ADst, ADstPitch);
end;

end.
