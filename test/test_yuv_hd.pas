{
  test_yuv_hd — I444 と P010（SDL_PIXELFORMAT_I444 / SDL_PIXELFORMAT_P010）と、I0FL / I4FL の変換

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    参照版 SDL に I444 と P010 を通した結果（test/yuv_hd_expected.inc。tools/yuv-hd-expect/gen.bb が作る）と、
    papimela の結果を場面ごとに突き合わせる:
    1. 大きさ（SDL_CalculateYUVSize）。I444 は 3 平面 w*h*3、P010 は 16 ビットの Y と色差
    2. YUV から RGB への変換の値。I444 は ARGB8888 へ、P010 は XBGR2101010 へ。5 つの色空間 x 3 つの大きさ
    3. I444 のテクスチャ（ソフトウェアのレンダラの肩代わり）: 詰めた画素での更新、平面ごとの更新、Lock、
       矩形つきの更新。描いた絵のハッシュ
    4. 断るもの: P010 のテクスチャ（SDL のソフトウェアのレンダラも作れない）、I444 に UpdateNV、
       I444 の部分の Lock、NV12 に UpdateYUV
    4b. I0FL / I4FL のテクスチャ（肩代わり）: 詰めた画素・平面ごと・Lock・矩形つきの更新。色空間は PQ でない 4 つ
    4c. YUV から任意の形式への変換（色空間の変換を挟む。PMLConvertYUVPixels）。7 つの YUV の形式 x 出力の形式
    4d. 詰めた画素の部分の更新が平面ごとと同じ絵（D-78。SDL の参照版は 3 つ目の平面を誤った位置に書く）
    5. papimela の足した検査: 形式の判定（PMLIsYUVFormat は I444 / I0FL / I4FL を含み P010 を含まない）、
       P010 を ARGB8888 に直す道（PMLConvertYUVToARGB8888）は無い、色空間を選べないものは断る

  WHY:
    §3 の 2「残してあるテクスチャのもの」の I444 / P010 の受け入れ検査。表示サーバは要らない。
    GLES2 のドライバの I444 は test_render_gles2 のオフスクリーンの節にある。

  SDL との違い（意図したもの）:
    - 8 ビットの値は範囲の内側に収めて比べる（範囲の外は SDL のスカラー版が回り込み、papimela は飽和させる。D-62）
    - 色空間を変換できないときは作るときに断る（SDL は更新のときに断る）
    - エラーの文面は種類で比べない。投げるかどうかだけ比べる
}
program test_yuv_hd;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, StrUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.YUV,
  PaPiMeLa.Render,
  PaPiMeLa.Render.Software;

{$I yuv_hd_expected.inc}

type
  TSpace = record
    Name : String;
    Space: TPMLColorspace;
  end;

var
  Failures: Integer = 0;
  Lcg: LongWord = 1;
  Target: TPMLSurface;
  R: TPMLRenderer;

procedure Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
    WriteLn('  [PASS] ', ALabel)
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(Failures);
  end;
end;

function Spaces(AIndex: Integer): TSpace;
begin
  case AIndex of
    0: begin Result.Name := 'bt601l'; Result.Space := PML_COLORSPACE_BT601_LIMITED; end;
    1: begin Result.Name := 'jpeg'; Result.Space := PML_COLORSPACE_JPEG; end;
    2: begin Result.Name := 'bt709l'; Result.Space := PML_COLORSPACE_BT709_LIMITED; end;
    3: begin Result.Name := 'bt709f'; Result.Space := PML_COLORSPACE_BT709_FULL; end;
  else
    begin Result.Name := 'bt2020f'; Result.Space := PML_COLORSPACE_BT2020_FULL; end;
  end;
end;

const
  SizeW: array[0..2] of Integer = (7, 16, 40);
  SizeH: array[0..2] of Integer = (5, 4, 6);

{ ---- SDL の側 (yuv_cases.c) と同じ部品 ---- }

function Nx: LongWord;
begin
  Lcg := Lcg * 1103515245 + 12345;
  Result := Lcg shr 16;
end;

function Y8: Byte;
begin
  Result := Byte(70 + (Nx mod 80));
end;

function C8: Byte;
begin
  Result := Byte(96 + (Nx and 63));
end;

procedure FillI444(P: PByte; AW, AH: Integer; ASeed: LongWord);
var
  I: Integer;
begin
  Lcg := ASeed;
  for I := 0 to AW * AH - 1 do
    P[I] := Y8;
  for I := 0 to 2 * AW * AH - 1 do
    P[AW * AH + I] := C8;
end;

function Fnv(P: PByte; ALen: PtrInt; AHash: LongWord): LongWord;
var
  I: PtrInt;
begin
  Result := AHash;
  for I := 0 to ALen - 1 do
  begin
    Result := Result xor P[I];
    Result := Result * 16777619;
  end;
end;

function Hex(AValue: LongWord): String;
begin
  Result := IntToHex(AValue, 8);
end;

{ 期待の表に、この行がそのまま入っているか。 }
function Has(const ALine: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(YUVHDExpected) do
    if YUVHDExpected[I] = ALine then
      Exit(True);
end;

{ ALine から最後の語（ハッシュ）を除いた先頭と同じ行を探して返す（失敗の表示用）。 }
function Wanted(const ALine: String): String;
var
  Head: String;
  I: Integer;
begin
  Head := Copy(ALine, 1, RPos(' ', ALine));
  Result := '(場面が無い)';
  for I := 0 to High(YUVHDExpected) do
    if Copy(YUVHDExpected[I], 1, Length(Head)) = Head then
      Exit(YUVHDExpected[I]);
end;

procedure Same(const ALine: String);
begin
  Check(Has(ALine), ALine + '   (SDL: ' + Wanted(ALine) + ')');
end;

{ 描いた絵のハッシュ（SDL の側の render_hash と同じ。AW x AH の 1:1）。 }
function RenderHash(T: TPMLTexture; AW, AH: Integer): LongWord;
var
  Y: Integer;
begin
  R.DrawColor := TPMLColor.Make(10, 20, 30, 255);
  R.Clear;
  R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, AW, AH));
  R.Present;
  Result := 2166136261;
  for Y := 0 to AH - 1 do
    Result := Fnv(PByte(Target.Pixels) + Y * Target.Pitch, AW * 4, Result);
end;

function NewTexture(AFormat: TPMLPixelFormat; ASpace: TPMLColorspace; AW, AH: Integer): TPMLTexture;
begin
  Result := R.CreateTexture(AFormat, TPMLTextureAccess.Streaming, AW, AH, ASpace);
  Result.BlendMode := TPMLBlendMode.None;
end;

{ ---- 場面 ---- }

procedure TestSizes;
const
  Ws: array[0..3] of Integer = (7, 8, 1, 40);
  Hs: array[0..3] of Integer = (5, 6, 1, 6);
var
  I, F: Integer;
  Size: PtrUInt;
  Pitch: Integer;
  Fmt: TPMLPixelFormat;
  Name: String;
begin
  WriteLn('1 大きさ（SDL_CalculateYUVSize）');
  for F := 0 to 3 do
  begin
    case F of
      0: begin Fmt := PML_PIXELFORMAT_I444; Name := 'I444'; end;
      1: begin Fmt := PML_PIXELFORMAT_P010; Name := 'P010'; end;
      2: begin Fmt := PML_PIXELFORMAT_I0FL; Name := 'I0FL'; end;
    else
      begin Fmt := PML_PIXELFORMAT_I4FL; Name := 'I4FL'; end;
    end;
    for I := 0 to 3 do
    begin
      Size := 0;
      Pitch := 0;
      if PMLCalculateYUVSize(Fmt, Ws[I], Hs[I], Size, Pitch) then
        Same(Format('Z %s %d %d %d %d', [Name, Ws[I], Hs[I], Size, Pitch]))
      else
        Check(False, Format('%s %dx%d の大きさを返す', [Name, Ws[I], Hs[I]]));
    end;
  end;
end;

procedure TestConvert;
var
  S, Z, W, H, I, K: Integer;
  Size: PtrUInt;
  Pitch: Integer;
  Src, Dst: TBytes;
  Sp: TSpace;
  Fmt: TPMLPixelFormat;
begin
  WriteLn('2 変換の値（5 つの色空間 x 3 つの大きさ）');
  for S := 0 to 4 do
    for Z := 0 to 2 do
    begin
      Sp := Spaces(S);
      W := SizeW[Z];
      H := SizeH[Z];
      // I444 -> ARGB8888
      PMLCalculateYUVSize(PML_PIXELFORMAT_I444, W, H, Size, Pitch);
      SetLength(Src, Size);
      SetLength(Dst, W * H * 4);
      FillChar(Src[0], Size, 0);
      FillChar(Dst[0], Length(Dst), 0);
      FillI444(@Src[0], W, H, 5 + S * 3 + Z);
      PMLConvertYUVToARGB8888(W, H, PML_PIXELFORMAT_I444, Sp.Space, @Src[0], Pitch, @Dst[0], W * 4);
      Same(Format('C I444 %s %d %d %s', [Sp.Name, W, H, Hex(Fnv(@Dst[0], Length(Dst), 2166136261))]));
      // P010 -> XBGR2101010（値は 16 ビットの全域）
      PMLCalculateYUVSize(PML_PIXELFORMAT_P010, W, H, Size, Pitch);
      SetLength(Src, Size);
      SetLength(Dst, W * H * 4);
      FillChar(Src[0], Size, 0);
      FillChar(Dst[0], Length(Dst), 0);
      Lcg := 11 + S * 7 + Z;
      for I := 0 to Size div 2 - 1 do
        PWord(@Src[0])[I] := Word(Nx and $FFFF);
      PMLConvertP010ToXBGR2101010(W, H, Sp.Space, @Src[0], Pitch, @Dst[0], W * 4);
      Same(Format('C P010 %s %d %d %s', [Sp.Name, W, H, Hex(Fnv(@Dst[0], Length(Dst), 2166136261))]));
      // I0FL / I4FL -> RGB48（16 ビットの全域）
      for K := 0 to 1 do
      begin
        if K = 0 then
          Fmt := PML_PIXELFORMAT_I0FL
        else
          Fmt := PML_PIXELFORMAT_I4FL;
        PMLCalculateYUVSize(Fmt, W, H, Size, Pitch);
        SetLength(Src, Size);
        SetLength(Dst, W * H * 6);
        FillChar(Src[0], Size, 0);
        FillChar(Dst[0], Length(Dst), 0);
        Lcg := 23 + S * 5 + Z + K * 100;
        for I := 0 to Size div 2 - 1 do
          PWord(@Src[0])[I] := Word(Nx and $FFFF);
        PMLConvertYUV16ToRGB48(W, H, Fmt, Sp.Space, @Src[0], Pitch, @Dst[0], W * 6);
        Same(Format('C %s %s %d %d %s', [PMLPixelFormatName(Fmt), Sp.Name, W, H,
          Hex(Fnv(@Dst[0], Length(Dst), 2166136261))]));
      end;
    end;
end;

{ YUV から任意の形式・色空間へ（SDL_ConvertPixels_YUV_to_RGB の後半。色空間の変換を挟む）。
  SDL の側 (yuv_cases.c) と同じ順で入力を作る。ハッシュは出力の全バイトで、完全に一致する。 }
procedure TestAnyDestination;
const
  YF: array[0..6] of TPMLPixelFormat = (PML_PIXELFORMAT_I444, PML_PIXELFORMAT_IYUV, PML_PIXELFORMAT_NV12,
    PML_PIXELFORMAT_YUY2, PML_PIXELFORMAT_P010, PML_PIXELFORMAT_I0FL, PML_PIXELFORMAT_I4FL);
  DF: array[0..9] of TPMLPixelFormat = (PML_PIXELFORMAT_ARGB8888, PML_PIXELFORMAT_ABGR8888,
    PML_PIXELFORMAT_XRGB8888, PML_PIXELFORMAT_RGB24, PML_PIXELFORMAT_RGB565, PML_PIXELFORMAT_XBGR2101010,
    PML_PIXELFORMAT_RGB48, PML_PIXELFORMAT_RGBA128_FLOAT, PML_PIXELFORMAT_ARGB2101010,
    PML_PIXELFORMAT_RGB48_FLOAT);
var
  DC: array[0..9] of TPMLColorspace;
  Y, D, K, SIdx, W, H, Pitch, Bpp, I: Integer;
  Size: PtrUInt;
  Src, Dst: TBytes;
  Sp: TSpace;
begin
  WriteLn('3c YUV から任意の形式へ（色空間の変換つき）');
  DC[0] := PML_COLORSPACE_SRGB; DC[1] := PML_COLORSPACE_SRGB; DC[2] := PML_COLORSPACE_SRGB;
  DC[3] := PML_COLORSPACE_SRGB; DC[4] := PML_COLORSPACE_SRGB; DC[5] := PML_COLORSPACE_HDR10;
  DC[6] := PML_COLORSPACE_SRGB_LINEAR; DC[7] := PML_COLORSPACE_SRGB_LINEAR; DC[8] := PML_COLORSPACE_SRGB;
  DC[9] := PML_COLORSPACE_HDR10;
  K := 0;
  W := 7;
  H := 5;
  for Y := 0 to 6 do
    for D := 0 to 9 do
    begin
      if ((Y + D) mod 2 <> 0) and (D <> 0) and (D <> 5) and (D <> 6) then
        Continue;
      Inc(K);
      SIdx := (K - 1) mod 5;
      Sp := Spaces(SIdx);
      PMLCalculateYUVSize(YF[Y], W, H, Size, Pitch);
      SetLength(Src, Size);
      FillChar(Src[0], Size, 0);
      Bpp := PMLBytesPerPixel(DF[D]);
      SetLength(Dst, W * H * Bpp);
      FillChar(Dst[0], Length(Dst), 0);
      Lcg := 300 + K;
      if (YF[Y] = PML_PIXELFORMAT_P010) or (YF[Y] = PML_PIXELFORMAT_I0FL) or (YF[Y] = PML_PIXELFORMAT_I4FL) then
        for I := 0 to Size div 2 - 1 do
          PWord(@Src[0])[I] := Word(Nx and $FFFF)
      else
        for I := 0 to Size - 1 do
          Src[I] := Byte(96 + (Nx and 63));
      PMLConvertYUVPixels(W, H, YF[Y], Sp.Space, @Src[0], Pitch, DF[D], DC[D], @Dst[0], W * Bpp);
      Same(Format('Y y%.2d %s %s %s %s %d %d %s', [K, Hex(YF[Y]), Hex(Sp.Space), Hex(DF[D]), Hex(DC[D]), W, H,
        Hex(Fnv(@Dst[0], Length(Dst), 2166136261))]));
    end;
end;

{ 限定範囲の黒（16 ビットで 16 << 8）。SDL の輝度のオフセットの扱い（D-77）まで同じ値になる。 }
procedure TestBlack;
var
  Buf: array[0..5] of Word;
  Dst: array[0..11] of Word;
  Line, Want: String;
  I: Integer;
begin
  WriteLn('2b I0FL の黒と白（限定範囲。D-77）');
  Buf[0] := 16 shl 8;
  Buf[1] := 235 shl 8;
  Buf[2] := 16 shl 8;
  Buf[3] := 235 shl 8;
  Buf[4] := 128 shl 8;
  Buf[5] := 128 shl 8;
  FillChar(Dst, SizeOf(Dst), 0);
  PMLConvertYUV16ToRGB48(2, 2, PML_PIXELFORMAT_I0FL, PML_COLORSPACE_BT709_LIMITED, @Buf[0], 4, @Dst[0], 12);
  Line := Format('B I0FL_black %d %d %d white %d %d %d', [Dst[0], Dst[1], Dst[2], Dst[3], Dst[4], Dst[5]]);
  Want := '(場面が無い)';
  for I := 0 to High(YUVHDExpected) do
    if Copy(YUVHDExpected[I], 1, 13) = 'B I0FL_black ' then
      Want := YUVHDExpected[I];
  Check(Line = Want, Line + '   (SDL: ' + Want + ')');
end;

procedure TestTexture;
var
  S, Z, W, H, Pitch, LockPitch: Integer;
  Size: PtrUInt;
  Buf, A, B: TBytes;
  T: TPMLTexture;
  P: PByte;
  Sp: TSpace;
  Rc: TPMLRect;
  I: Integer;
begin
  WriteLn('3 I444 のテクスチャ');
  for S := 0 to 4 do
    for Z := 0 to 2 do
    begin
      Sp := Spaces(S);
      W := SizeW[Z];
      H := SizeH[Z];
      PMLCalculateYUVSize(PML_PIXELFORMAT_I444, W, H, Size, Pitch);
      SetLength(Buf, Size);
      FillChar(Buf[0], Size, 0);
      FillI444(@Buf[0], W, H, 40 + S + Z);
      // 詰めた画素
      T := NewTexture(PML_PIXELFORMAT_I444, Sp.Space, W, H);
      try
        T.Update(TPMLRect.Make(0, 0, 0, 0), @Buf[0], Pitch);
        Same(Format('T packed %s %d %d %s', [Sp.Name, W, H, Hex(RenderHash(T, W, H))]));
      finally
        T.Free;
      end;
      // 平面ごと
      T := NewTexture(PML_PIXELFORMAT_I444, Sp.Space, W, H);
      try
        T.UpdateYUV(TPMLRect.Make(0, 0, 0, 0), @Buf[0], W, @Buf[W * H], W, @Buf[2 * W * H], W);
        Same(Format('T planar %s %d %d %s', [Sp.Name, W, H, Hex(RenderHash(T, W, H))]));
      finally
        T.Free;
      end;
      // Lock
      T := NewTexture(PML_PIXELFORMAT_I444, Sp.Space, W, H);
      try
        P := T.Lock(TPMLRect.Make(0, 0, 0, 0), LockPitch);
        Move(Buf[0], P^, Size);
        T.Unlock;
        Same(Format('T lock %s %d %d %d %s', [Sp.Name, W, H, LockPitch, Hex(RenderHash(T, W, H))]));
      finally
        T.Free;
      end;
    end;

  // 矩形つきの更新。平面の区切りが矩形の位置とずれるので、全部の値を 96..159 にする
  W := 16;
  H := 4;
  PMLCalculateYUVSize(PML_PIXELFORMAT_I444, W, H, Size, Pitch);
  SetLength(A, Size);
  SetLength(B, Size);
  Lcg := 71;
  for I := 0 to Size - 1 do
    A[I] := C8;
  Lcg := 72;
  for I := 0 to Size - 1 do
    B[I] := C8;
  Rc := TPMLRect.Make(3, 1, 9, 2);
  T := NewTexture(PML_PIXELFORMAT_I444, PML_COLORSPACE_BT709_LIMITED, W, H);
  try
    T.Update(TPMLRect.Make(0, 0, 0, 0), @A[0], W);
    T.UpdateYUV(Rc, @B[1 * W + 3], W, @B[W * H + 1 * W + 3], W, @B[2 * W * H + 1 * W + 3], W);
    Same(Format('T planar_rect bt709l %d %d %s', [W, H, Hex(RenderHash(T, W, H))]));
  finally
    T.Free;
  end;
  T := NewTexture(PML_PIXELFORMAT_I444, PML_COLORSPACE_BT709_LIMITED, W, H);
  try
    T.Update(TPMLRect.Make(0, 0, 0, 0), @A[0], W);
    T.Update(Rc, @B[1 * W + 3], W);
    Same(Format('T packed_rect bt709l %d %d %s', [W, H, Hex(RenderHash(T, W, H))]));
  finally
    T.Free;
  end;
end;

{ I0FL / I4FL のテクスチャ（16 ビット。色空間は PQ でない 4 つ）。SDL の側と同じ順で入力を作る。 }
procedure TestTexture16;
const
  HF: array[0..1] of TPMLPixelFormat = (PML_PIXELFORMAT_I0FL, PML_PIXELFORMAT_I4FL);
  HN: array[0..1] of String = ('I0FL', 'I4FL');
var
  F, S, Z, W, H, Pitch, LockPitch, CW, CH, I: Integer;
  Size: PtrUInt;
  Src, A, B: TBytes;
  T: TPMLTexture;
  P: PByte;
  Sp: TSpace;
  HS: array[0..3] of TSpace;
  Rc: TPMLRect;
begin
  WriteLn('3d I0FL / I4FL のテクスチャ');
  HS[0] := Spaces(0);   // bt601l
  HS[1] := Spaces(1);   // jpeg
  HS[2] := Spaces(2);   // bt709l
  HS[3] := Spaces(3);   // bt709f
  for F := 0 to 1 do
    for S := 0 to 3 do
      for Z := 0 to 2 do
      begin
        Sp := HS[S];
        W := SizeW[Z];
        H := SizeH[Z];
        PMLCalculateYUVSize(HF[F], W, H, Size, Pitch);
        SetLength(Src, Size);
        FillChar(Src[0], Size, 0);
        Lcg := 500 + F * 100 + S * 10 + Z;
        for I := 0 to Size div 2 - 1 do
          PWord(@Src[0])[I] := Word(Nx and $FFFF);
        T := NewTexture(HF[F], Sp.Space, W, H);
        try
          T.Update(TPMLRect.Make(0, 0, 0, 0), @Src[0], Pitch);
          Same(Format('T %s_packed %s %d %d %s', [HN[F], Sp.Name, W, H, Hex(RenderHash(T, W, H))]));
        finally
          T.Free;
        end;
        if F = 1 then
        begin
          CW := W;
          CH := H;
        end
        else
        begin
          CW := (W + 1) div 2;
          CH := (H + 1) div 2;
        end;
        T := NewTexture(HF[F], Sp.Space, W, H);
        try
          T.UpdateYUV(TPMLRect.Make(0, 0, 0, 0), @Src[0], Pitch, @Src[Pitch * H], CW * 2,
            @Src[Pitch * H + CW * 2 * CH], CW * 2);
          Same(Format('T %s_planar %s %d %d %s', [HN[F], Sp.Name, W, H, Hex(RenderHash(T, W, H))]));
        finally
          T.Free;
        end;
        T := NewTexture(HF[F], Sp.Space, W, H);
        try
          P := T.Lock(TPMLRect.Make(0, 0, 0, 0), LockPitch);
          Move(Src[0], P^, Size);
          T.Unlock;
          Same(Format('T %s_lock %s %d %d %d %s', [HN[F], Sp.Name, W, H, LockPitch, Hex(RenderHash(T, W, H))]));
        finally
          T.Free;
        end;
      end;
  // 矩形つきの更新
  for F := 0 to 1 do
  begin
    W := 16;
    H := 6;
    PMLCalculateYUVSize(HF[F], W, H, Size, Pitch);
    SetLength(A, Size);
    SetLength(B, Size);
    Lcg := 900 + F;
    for I := 0 to Size div 2 - 1 do
      PWord(@A[0])[I] := Word(Nx and $FFFF);
    Lcg := 910 + F;
    for I := 0 to Size div 2 - 1 do
      PWord(@B[0])[I] := Word(Nx and $FFFF);
    Rc := TPMLRect.Make(3, 0, 9, 6);   // 高さは全体（D-78。SDL の参照版は部分の高さで 3 つ目の平面を測る）
    T := NewTexture(HF[F], PML_COLORSPACE_BT709_LIMITED, W, H);
    try
      T.Update(TPMLRect.Make(0, 0, 0, 0), @A[0], Pitch);
      T.Update(Rc, @B[0], Pitch);
      Same(Format('T %s_packed_rect bt709l %d %d %s', [HN[F], W, H, Hex(RenderHash(T, W, H))]));
    finally
      T.Free;
    end;
    if F = 1 then
    begin
      CW := W;
      CH := H;
    end
    else
    begin
      CW := (W + 1) div 2;
      CH := (H + 1) div 2;
    end;
    T := NewTexture(HF[F], PML_COLORSPACE_BT709_LIMITED, W, H);
    try
      T.Update(TPMLRect.Make(0, 0, 0, 0), @A[0], Pitch);
      T.UpdateYUV(Rc, @B[0], Pitch, @B[Pitch * H], CW * 2, @B[Pitch * H + CW * 2 * CH], CW * 2);
      Same(Format('T %s_planar_rect bt709l %d %d %s', [HN[F], W, H, Hex(RenderHash(T, W, H))]));
    finally
      T.Free;
    end;
  end;
end;

{ 詰めた画素での部分の更新と、平面ごとの部分の更新が、同じ絵になる（YV12 / IYUV / I0FL）。
  SDL の参照版は、詰めた画素の部分の更新で 3 つ目の平面を「矩形の高さ」で測った位置に書く
  （D-78。3.4.2 は正しい）。papimela は 3.4.2 と同じ（正しい位置）で、平面ごとの更新（SDL も正しい）と比べる。 }
procedure TestPartialPacked;
const
  Fmts: array[0..2] of TPMLPixelFormat = (PML_PIXELFORMAT_IYUV, PML_PIXELFORMAT_YV12, PML_PIXELFORMAT_I0FL);
var
  F, I, W, H, RW, RH, CW, CH, Bpp, FullPitch, PktPitch, Cfg: Integer;
  Size: PtrUInt;
  A, Pkt, YPl, UPl, VPl: TBytes;
  T1, T2: TPMLTexture;
  Rc: TPMLRect;
  H1, H2: LongWord;
  Sp: TPMLColorspace;
begin
  WriteLn('3e 部分の更新（詰めた画素と平面ごとが同じ絵。D-78）');
  W := 8;
  H := 6;
  for Cfg := 0 to 1 do
  for F := 0 to 2 do
  begin
    // 矩形は (2, 2, 4, 2) と、幅が奇数の (2, 2, 3, 3)
    if Cfg = 0 then
    begin
      RW := 4;
      RH := 2;
    end
    else
    begin
      RW := 3;
      RH := 3;
    end;
    CW := (RW + 1) div 2;
    CH := (RH + 1) div 2;
    Rc := TPMLRect.Make(2, 2, RW, RH);
    if Fmts[F] = PML_PIXELFORMAT_I0FL then
    begin
      Bpp := 2;
      Sp := PML_COLORSPACE_BT709_LIMITED;
    end
    else
    begin
      Bpp := 1;
      Sp := PML_COLORSPACE_BT709_LIMITED;
    end;
    PMLCalculateYUVSize(Fmts[F], W, H, Size, FullPitch);
    SetLength(A, Size);
    Lcg := 1234 + F;
    for I := 0 to High(A) do
      A[I] := Byte(96 + (Nx and 63));
    // 矩形の分の Y・U・V（値は 96..159 の 1 バイト。I0FL は 1 標本 2 バイトにして同じ値を 2 つ並べる）
    SetLength(YPl, RW * RH * Bpp);
    SetLength(UPl, CW * CH * Bpp);
    SetLength(VPl, CW * CH * Bpp);
    Lcg := 4321 + F;
    for I := 0 to High(YPl) do
      YPl[I] := Byte(96 + (Nx and 63));
    for I := 0 to High(UPl) do
      UPl[I] := Byte(96 + (Nx and 63));
    for I := 0 to High(VPl) do
      VPl[I] := Byte(96 + (Nx and 63));
    // 詰めた画素: Y、次の平面、その次の平面（YV12 は V・U の順）
    PktPitch := RW * Bpp;
    SetLength(Pkt, Length(YPl) + Length(UPl) + Length(VPl));
    Move(YPl[0], Pkt[0], Length(YPl));
    if Fmts[F] = PML_PIXELFORMAT_YV12 then
    begin
      Move(VPl[0], Pkt[Length(YPl)], Length(VPl));
      Move(UPl[0], Pkt[Length(YPl) + Length(VPl)], Length(UPl));
    end
    else
    begin
      Move(UPl[0], Pkt[Length(YPl)], Length(UPl));
      Move(VPl[0], Pkt[Length(YPl) + Length(UPl)], Length(VPl));
    end;
    T1 := NewTexture(Fmts[F], Sp, W, H);
    T2 := NewTexture(Fmts[F], Sp, W, H);
    try
      T1.Update(TPMLRect.Make(0, 0, 0, 0), @A[0], FullPitch);
      T1.Update(Rc, @Pkt[0], PktPitch);
      T2.Update(TPMLRect.Make(0, 0, 0, 0), @A[0], FullPitch);
      T2.UpdateYUV(Rc, @YPl[0], PktPitch, @UPl[0], CW * Bpp, @VPl[0], CW * Bpp);
      H1 := RenderHash(T1, W, H);
      H2 := RenderHash(T2, W, H);
      Check(H1 = H2, PMLPixelFormatName(Fmts[F]) + ': 詰めた画素の部分の更新（' + IntToStr(RW) + 'x' + IntToStr(RH) + '）が平面ごとと同じ絵（'
        + Hex(H1) + ' / ' + Hex(H2) + '）');
    finally
      T1.Free;
      T2.Free;
    end;
  end;
end;

{ 行の幅に余りがある詰めた画素と平面ごと（全体の更新。行ごとに写す道）。 }
procedure TestPitch;
var
  Buf: TBytes;
  I: Integer;
  T: TPMLTexture;
  W, H, Pitch: Integer;
begin
  WriteLn('3b 行の幅に余り');
  W := 16;
  H := 4;
  Pitch := 21;
  SetLength(Buf, Pitch * H * 3);
  Lcg := 91;
  for I := 0 to High(Buf) do
    Buf[I] := C8;
  T := NewTexture(PML_PIXELFORMAT_I444, PML_COLORSPACE_BT709_LIMITED, W, H);
  try
    T.Update(TPMLRect.Make(0, 0, 0, 0), @Buf[0], Pitch);
    Same(Format('T packed_pitch bt709l %d %d %s', [W, H, Hex(RenderHash(T, W, H))]));
  finally
    T.Free;
  end;
  T := NewTexture(PML_PIXELFORMAT_I444, PML_COLORSPACE_BT709_LIMITED, W, H);
  try
    T.UpdateYUV(TPMLRect.Make(0, 0, 0, 0), @Buf[0], Pitch, @Buf[Pitch * H], Pitch, @Buf[2 * Pitch * H], Pitch);
    Same(Format('T planar_pitch bt709l %d %d %s', [W, H, Hex(RenderHash(T, W, H))]));
  finally
    T.Free;
  end;
end;

{ 例外が出るか。SDL の側は '<場面> <文面>' か '<場面> ok'。 }
procedure ExpectRaise(const AName: String; ARaised: Boolean);
var
  I: Integer;
  Want: String;
begin
  Want := '(場面が無い)';
  for I := 0 to High(YUVHDExpected) do
    if Copy(YUVHDExpected[I], 1, Length(AName) + 3) = 'E ' + AName + ' ' then
      Want := Copy(YUVHDExpected[I], Length(AName) + 4, MaxInt);
  Check(ARaised = (Want <> 'ok'), AName + ' は' + BoolToStr(ARaised, '断る', '通る') + '（SDL: ' + Want + '）');
end;

procedure TestRefusals;
var
  T: TPMLTexture;
  Buf: array[0..399] of Byte;
  Raised: Boolean;
  P: Pointer;
  Pitch: Integer;
  Dst: array[0..399] of Byte;
begin
  WriteLn('4 断るもの');
  FillChar(Buf, SizeOf(Buf), 0);
  Raised := False;
  try
    T := NewTexture(PML_PIXELFORMAT_P010, PML_COLORSPACE_BT709_LIMITED, 8, 6);
    T.Free;
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  ExpectRaise('create_p010', Raised);

  T := NewTexture(PML_PIXELFORMAT_I444, PML_COLORSPACE_BT709_LIMITED, 8, 6);
  try
    Raised := False;
    try
      T.UpdateNV(TPMLRect.Make(0, 0, 0, 0), @Buf[0], 8, @Buf[0], 8);
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    ExpectRaise('nv_on_i444', Raised);
    Raised := False;
    try
      P := T.Lock(TPMLRect.Make(0, 0, 4, 4), Pitch);
      T.Unlock;
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    ExpectRaise('lock_partial', Raised);
  finally
    T.Free;
  end;

  T := NewTexture(PML_PIXELFORMAT_NV12, PML_COLORSPACE_BT709_LIMITED, 8, 6);
  try
    Raised := False;
    try
      T.UpdateYUV(TPMLRect.Make(0, 0, 0, 0), @Buf[0], 8, @Buf[0], 4, @Buf[0], 4);
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    ExpectRaise('yuv_on_nv12', Raised);
  finally
    T.Free;
  end;

  // 面での P010 -> XBGR2101010 は通る（SDL も通る）
  FillChar(Dst, SizeOf(Dst), 0);
  Raised := False;
  try
    PMLConvertP010ToXBGR2101010(4, 4, PML_COLORSPACE_BT709_LIMITED, @Buf[0], 8, @Dst[0], 16);
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  ExpectRaise('p010_to_xbgr', Raised);
end;

procedure TestExtras;
var
  Size: PtrUInt;
  Pitch: Integer;
  Buf: array[0..399] of Byte;
  Dst: array[0..399] of Byte;
  Raised: Boolean;
begin
  WriteLn('5 papimela の足した検査');
  Check(PMLIsYUVFormat(PML_PIXELFORMAT_I444), 'PMLIsYUVFormat は I444 を含む（肩代わりの層が扱える）');
  Check(not PMLIsYUVFormat(PML_PIXELFORMAT_P010), 'PMLIsYUVFormat は P010 を含まない（SDL のソフトウェアのレンダラも作れない）');
  Check(PMLIsYUVFormat(PML_PIXELFORMAT_IYUV) and PMLIsYUVFormat(PML_PIXELFORMAT_YUY2) and PMLIsYUVFormat(PML_PIXELFORMAT_NV21),
    '既存の 7 形式は変わらない');
  Check(not PMLIsYUVFormat(PML_PIXELFORMAT_ARGB8888), 'ARGB8888 は YUV でない');
  Check(PMLIsYUVFormat(PML_PIXELFORMAT_I0FL) and PMLIsYUVFormat(PML_PIXELFORMAT_I4FL),
    'PMLIsYUVFormat は I0FL / I4FL を含む（16 ビットのテクスチャを肩代わりで持つ）');
  Raised := False;
  try
    R.CreateTexture(PML_PIXELFORMAT_I0FL, TPMLTextureAccess.Streaming, 4, 4).Free;
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  ExpectRaise('i0fl_default_cs', Raised);
  Raised := False;
  try
    R.CreateTexture(PML_PIXELFORMAT_I4FL, TPMLTextureAccess.Target, 4, 4, PML_COLORSPACE_BT709_FULL).Free;
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'I4FL は描画先にできない');

  FillChar(Buf, SizeOf(Buf), 0);
  FillChar(Dst, SizeOf(Dst), 0);
  Raised := False;
  try
    PMLConvertYUVToARGB8888(4, 4, PML_PIXELFORMAT_P010, PML_COLORSPACE_BT709_LIMITED, @Buf[0], 8, @Dst[0], 16);
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'P010 を ARGB8888 に直す道は無い（EPMLArgument）。P010 は XBGR2101010 だけ');
  Raised := False;
  try
    PMLConvertYUVToARGB8888(4, 4, PML_PIXELFORMAT_I4FL, PML_COLORSPACE_BT709_LIMITED, @Buf[0], 8, @Dst[0], 16);
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'I4FL を ARGB8888 に直す道は無い（EPMLArgument）。I0FL / I4FL は RGB48 だけ');
  Raised := False;
  try
    PMLConvertYUV16ToRGB48(4, 4, PML_PIXELFORMAT_I444, PML_COLORSPACE_BT709_LIMITED, @Buf[0], 8, @Dst[0], 24);
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'PMLConvertYUV16ToRGB48 は I0FL / I4FL 以外の形式を断る');
  Raised := False;
  try
    PMLConvertYUV16ToRGB48(4, 4, PML_PIXELFORMAT_I0FL, PML_COLORSPACE_BT2020_LIMITED, @Buf[0], 8, @Dst[0], 24);
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'PMLConvertYUV16ToRGB48 は行列を選べない色空間（BT.2020 の限定範囲）を断る');
  Raised := False;
  try
    PMLConvertP010ToXBGR2101010(4, 4, PML_COLORSPACE_BT2020_LIMITED, @Buf[0], 8, @Dst[0], 16);
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'P010 の変換は、行列を選べない色空間（BT.2020 の限定範囲）を断る');
  Raised := False;
  try
    R.CreateTexture(PML_PIXELFORMAT_I444, TPMLTextureAccess.Streaming, 4, 4, PML_COLORSPACE_SRGB).Free;
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'I444 のテクスチャは、変換できない色空間を作るときに断る');
  Raised := False;
  try
    R.CreateTexture(PML_PIXELFORMAT_I444, TPMLTextureAccess.Target, 4, 4, PML_COLORSPACE_BT709_FULL).Free;
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'I444 は描画先にできない');
end;

begin
  WriteLn('=== test_yuv_hd ===');
  Target := TPMLSurface.Create(48, 8, PML_PIXELFORMAT_ARGB8888);
  R := TPMLRenderer.CreateSoftware(Target);
  try
    TestSizes;
    TestConvert;
    TestBlack;
    TestAnyDestination;
    TestTexture;
    TestTexture16;
    TestPartialPacked;
    TestPitch;
    TestRefusals;
    TestExtras;
  finally
    FreeAndNil(R);
    FreeAndNil(Target);
  end;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: I444 と P010 の大きさ・変換・テクスチャが SDL と同じ値・絵・断り方になる ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
