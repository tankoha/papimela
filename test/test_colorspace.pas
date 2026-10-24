{
  test_colorspace — 色空間の変換（転送関数・原色・トーンマップ）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    参照版 SDL の結果（test/colorspace_expected.inc。tools/colorspace-expect/gen.bb が作る）と、
    papimela の結果を突き合わせる:
    1. 転送関数（sRGB の符号化と復号、PQ の符号化と復号）。26 の入力値
    2. 原色の変換行列（7 つの原色の 49 通りの組。無い組は nil）
    3. SDR の白点と HDR のヘッドルームの既定
    4. 画素の変換 69 場面: 12 の入力形式 x 11 の出力形式（8 ビット・RGB24・RGB565・10 ビット・16 ビット整数・
       16 ビット浮動小数・32 ビット浮動小数）、7 つの色空間の組（sRGB・線形・HDR10・YUV の色空間を RGB の
       色空間として使う組を含む）、SDR の白点・HDR のヘッドルーム・トーンマップ（chrome・none・倍率）の指定
    5. papimela の足した検査: YUV・インデックス形式を断る、色空間が同じなら 8 ビット同士の変換は
       SDL と同じ丸め（最も近い整数）になる

  WHY:
    §3 の 2「色空間の変換の仕組み」の受け入れ検査。I0FL / I4FL / P010 の YUV を、RGB48 / XBGR2101010
    から先の形式へ直すために要る。表示サーバは要らない。

  SDL との違い（意図したもの）:
    - 浮動小数の演算は CPU とコンパイラに依る（powf の最後の 1 ビット、aarch64 の gcc の積和の融合）。
      期待値は積和を融合しない参照版で作る（`-DCMAKE_C_FLAGS=-ffp-contract=off`。x86_64 の SDL と同じ。
      融合する参照版では PQ が数百 ulp ずれる）。そうして作った期待値には 100% 一致するが、libm の違いに
      備えて、転送関数は 2 ulp、整数の形式は成分ごとに 1、浮動小数の形式は相対 1e-5（16 ビット浮動小数は 3e-3）
      まで許す。完全に一致した成分の割合は表示する
    - 入力に RGB565 は使わない: 5・6 ビットの拡張の丸めが SDL_blit_N と違う（HANDOFF §8。持ち主が直さないと決めた）
}
program test_colorspace;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface.Colorspace;

{$I colorspace_expected.inc}

var
  Failures: Integer = 0;
  // 成分が完全に一致した数と、比べた成分の数
  ExactCount: Int64 = 0;
  TotalCount: Int64 = 0;

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

{ ---- 文字列の分解 ---- }

function Tokens(const ALine: String): TStringArray;
begin
  Result := ALine.Split([' ']);
end;

function Hex32(const S: String): LongWord;
begin
  Result := LongWord(StrToInt64('$' + S));
end;

function BitsToSingle(ABits: LongWord): Single;
begin
  Result := PSingle(@ABits)^;
end;

function SingleToBits(AValue: Single): LongWord;
begin
  Result := PLongWord(@AValue)^;
end;

function HexToBytes(const S: String): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Length(S) div 2);
  for I := 0 to High(Result) do
    Result[I] := Byte(StrToInt('$' + Copy(S, I * 2 + 1, 2)));
end;

{ 2 つの Single の並びの距離（ULP の数）。符号つきの並びを辞書順に直して引く。 }
function UlpDistance(A, B: Single): Int64;
  function Ordered(X: Single): Int64;
  var
    U: LongWord;
  begin
    U := SingleToBits(X);
    if (U and $80000000) <> 0 then
      Result := -Int64(U and $7FFFFFFF)
    else
      Result := Int64(U);
  end;
begin
  Result := Abs(Ordered(A) - Ordered(B));
end;

{ ---- 1〜3 ---- }

procedure TestScalars;
const
  Max = 2;
var
  I: Integer;
  T: TStringArray;
  X, Want, Got: Single;
  D: Int64;
  Kind: String;
  Count: array[0..3] of Integer;
  Worst: array[0..3] of Int64;
  K: Integer;
begin
  WriteLn('1 転送関数');
  FillChar(Count, SizeOf(Count), 0);
  FillChar(Worst, SizeOf(Worst), 0);
  for I := 0 to High(ColorspaceExpected) do
    if Copy(ColorspaceExpected[I], 1, 2) = 'F ' then
    begin
      T := Tokens(ColorspaceExpected[I]);
      Kind := T[1];
      X := BitsToSingle(Hex32(T[2]));
      Want := BitsToSingle(Hex32(T[3]));
      if Kind = 'srgb_to_linear' then begin Got := PMLSRGBToLinear(X); K := 0; end
      else if Kind = 'srgb_from_linear' then begin Got := PMLSRGBFromLinear(X); K := 1; end
      else if Kind = 'pq_to_nits' then begin Got := PMLPQToNits(X); K := 2; end
      else begin Got := PMLPQFromNits(X); K := 3; end;
      D := UlpDistance(Got, Want);
      Inc(Count[K]);
      if D > Worst[K] then
        Worst[K] := D;
      if D > Max then
        WriteLn(Format('      %s(%g) = %g, SDL %g (%d ulp)', [Kind, X, Got, Want, D]));
    end;
  Check((Count[0] = 26) and (Count[1] = 26) and (Count[2] = 18) and (Count[3] = 26),
    '26 の入力値 x 4 つの関数（PQ の復号は 0..1 の 18 値）');
  Check(Worst[0] <= Max, Format('sRGB の復号は SDL と同じ値（最大 %d ulp）', [Worst[0]]));
  Check(Worst[1] <= Max, Format('sRGB の符号化は SDL と同じ値（最大 %d ulp）', [Worst[1]]));
  Check(Worst[2] <= Max, Format('PQ の復号は SDL と同じ値（最大 %d ulp）', [Worst[2]]));
  Check(Worst[3] <= Max, Format('PQ の符号化は SDL と同じ値（最大 %d ulp）', [Worst[3]]));
end;

procedure TestMatrices;
var
  I, J, N, Bad, Nones: Integer;
  T: TStringArray;
  M: PSingle;
begin
  WriteLn('2 原色の変換行列');
  N := 0;
  Bad := 0;
  Nones := 0;
  for I := 0 to High(ColorspaceExpected) do
    if Copy(ColorspaceExpected[I], 1, 2) = 'M ' then
    begin
      T := Tokens(ColorspaceExpected[I]);
      M := PMLColorPrimariesMatrix(StrToInt(T[1]), StrToInt(T[2]));
      Inc(N);
      if T[3] = 'none' then
      begin
        Inc(Nones);
        if M <> nil then
          Inc(Bad);
      end
      else if M = nil then
        Inc(Bad)
      else
        for J := 0 to 8 do
          if SingleToBits(M[J]) <> Hex32(T[3 + J]) then
          begin
            Inc(Bad);
            Break;
          end;
    end;
  Check(N = 49, '7 x 7 の組');
  Check(Bad = 0, Format('行列は SDL と同じ値で、無い組（%d 組）は nil', [Nones]));
end;

procedure TestWhitePoints;
var
  I, N, Bad: Integer;
  T: TStringArray;
  CS: TPMLColorspace;
begin
  WriteLn('3 SDR の白点と HDR のヘッドルームの既定');
  N := 0;
  Bad := 0;
  for I := 0 to High(ColorspaceExpected) do
    if Copy(ColorspaceExpected[I], 1, 2) = 'W ' then
    begin
      T := Tokens(ColorspaceExpected[I]);
      CS := TPMLColorspace(Hex32(T[1]));
      Inc(N);
      if (SingleToBits(PMLDefaultSDRWhitePoint(CS)) <> Hex32(T[2]))
      or (SingleToBits(PMLDefaultHDRHeadroom(CS)) <> Hex32(T[3])) then
      begin
        Inc(Bad);
        WriteLn(Format('      %s: 白点 %g (SDL %g)、ヘッドルーム %g (SDL %g)', [T[1], PMLDefaultSDRWhitePoint(CS),
          BitsToSingle(Hex32(T[2])), PMLDefaultHDRHeadroom(CS), BitsToSingle(Hex32(T[3]))]));
      end;
    end;
  Check(N = 6, '6 つの色空間');
  Check(Bad = 0, '白点（PQ は 203、線形は 1、ほかは 1）とヘッドルーム（線形・PQ は 0、ほかは 1）が SDL と同じ');
end;

{ ---- 4 画素の変換 ---- }

function HalfToDouble(AHalf: Word): Double;
var
  E, M: Integer;
begin
  E := (AHalf shr 10) and $1F;
  M := AHalf and $3FF;
  if E = 0 then
    Result := M * Power(2, -24)
  else if E = 31 then
    Result := Infinity
  else
    Result := (1024 + M) * Power(2, E - 25);
  if (AHalf and $8000) <> 0 then
    Result := -Result;
end;

{ 出力の比べ。整数の形式は成分ごとに 1 まで、浮動小数は相対の誤差まで許す。ExactCount / TotalCount を数える。 }
function SameOutput(AFormat: TPMLPixelFormat; const AGot, AWant: TBytes; out AWorst: String): Boolean;
var
  I, N: Integer;
  G, W: LongWord;
  GD, WD, Tol: Double;
  Typ: TPMLPixelType;
  procedure Count(AExact: Boolean);
  begin
    Inc(TotalCount);
    if AExact then
      Inc(ExactCount);
  end;
begin
  Result := True;
  AWorst := '';
  Typ := PMLPixelType(AFormat);
  if Length(AGot) <> Length(AWant) then
  begin
    AWorst := '大きさが違う';
    Exit(False);
  end;
  if (Typ = TPMLPixelType.Packed32) and (PMLPixelLayout(AFormat) = TPMLPackedLayout.Layout2101010) then
  begin
    for I := 0 to Length(AGot) div 4 - 1 do
    begin
      G := PLongWord(@AGot[I * 4])^;
      W := PLongWord(@AWant[I * 4])^;
      // 10 ビットの 3 成分は 1 まで、2 ビットのアルファ（最上位）は完全に一致
      for N := 0 to 2 do
      begin
        Count(((G shr (N * 10)) and $3FF) = ((W shr (N * 10)) and $3FF));
        if Abs(Integer((G shr (N * 10)) and $3FF) - Integer((W shr (N * 10)) and $3FF)) > 1 then
        begin
          Result := False;
          AWorst := Format('画素 %d の成分 %d: %d (SDL %d)', [I, N, (G shr (N * 10)) and $3FF, (W shr (N * 10)) and $3FF]);
        end;
      end;
      Count((G shr 30) = (W shr 30));
      if (G shr 30) <> (W shr 30) then
      begin
        Result := False;
        AWorst := Format('画素 %d のアルファ: %d (SDL %d)', [I, G shr 30, W shr 30]);
      end;
    end;
  end
  else if Typ = TPMLPixelType.ArrayU16 then
  begin
    for I := 0 to Length(AGot) div 2 - 1 do
    begin
      Count(PWord(@AGot[I * 2])^ = PWord(@AWant[I * 2])^);
      if Abs(Integer(PWord(@AGot[I * 2])^) - Integer(PWord(@AWant[I * 2])^)) > 1 then
      begin
        Result := False;
        AWorst := Format('成分 %d: %d (SDL %d)', [I, PWord(@AGot[I * 2])^, PWord(@AWant[I * 2])^]);
      end;
    end;
  end
  else if Typ = TPMLPixelType.ArrayF16 then
  begin
    for I := 0 to Length(AGot) div 2 - 1 do
    begin
      GD := HalfToDouble(PWord(@AGot[I * 2])^);
      WD := HalfToDouble(PWord(@AWant[I * 2])^);
      Count(PWord(@AGot[I * 2])^ = PWord(@AWant[I * 2])^);
      Tol := 3e-3 * Abs(WD) + 1e-4;
      if Abs(GD - WD) > Tol then
      begin
        Result := False;
        AWorst := Format('成分 %d: %g (SDL %g)', [I, GD, WD]);
      end;
    end;
  end
  else if Typ = TPMLPixelType.ArrayF32 then
  begin
    for I := 0 to Length(AGot) div 4 - 1 do
    begin
      GD := PSingle(@AGot[I * 4])^;
      WD := PSingle(@AWant[I * 4])^;
      Count(PLongWord(@AGot[I * 4])^ = PLongWord(@AWant[I * 4])^);
      Tol := 1e-5 * Abs(WD) + 1e-6;
      if Abs(GD - WD) > Tol then
      begin
        Result := False;
        AWorst := Format('成分 %d: %g (SDL %g)', [I, GD, WD]);
      end;
    end;
  end
  else
  begin
    // 8 ビット（RGB24 と RGB565 の出力は無い）。1 バイト 1 成分
    for I := 0 to High(AGot) do
    begin
      Count(AGot[I] = AWant[I]);
      if Abs(Integer(AGot[I]) - Integer(AWant[I])) > 1 then
      begin
        Result := False;
        AWorst := Format('バイト %d: %d (SDL %d)', [I, AGot[I], AWant[I]]);
      end;
    end;
  end;
end;

procedure TestPixels;
var
  I, N, Bad: Integer;
  T: TStringArray;
  SF, DF: TPMLPixelFormat;
  SC, DC: TPMLColorspace;
  W, H: Integer;
  Src, Want, Got: TBytes;
  Opt: TPMLColorspaceOptions;
  Worst, Name: String;
  Ok: Boolean;
begin
  WriteLn('4 画素の変換');
  N := 0;
  Bad := 0;
  for I := 0 to High(ColorspaceExpected) do
    if Copy(ColorspaceExpected[I], 1, 2) = 'X ' then
    begin
      T := Tokens(ColorspaceExpected[I]);
      Name := T[1];
      SF := TPMLPixelFormat(Hex32(T[2]));
      SC := TPMLColorspace(Hex32(T[3]));
      DF := TPMLPixelFormat(Hex32(T[4]));
      DC := TPMLColorspace(Hex32(T[5]));
      W := StrToInt(T[6]);
      H := StrToInt(T[7]);
      Opt := PMLColorspaceDefaults;
      Opt.SrcWhitePoint := BitsToSingle(Hex32(T[8]));
      Opt.SrcHeadroom := BitsToSingle(Hex32(T[9]));
      Opt.DstWhitePoint := BitsToSingle(Hex32(T[10]));
      Opt.DstHeadroom := BitsToSingle(Hex32(T[11]));
      if T[12] <> '-' then
        Opt.Tonemap := T[12];
      Src := HexToBytes(T[13]);
      Want := HexToBytes(T[14]);
      SetLength(Got, Length(Want));
      FillChar(Got[0], Length(Got), 0);
      Inc(N);
      try
        PMLConvertPixelsAndColorspace(W, H, SF, SC, @Src[0], W * PMLBytesPerPixel(SF),
          DF, DC, @Got[0], W * PMLBytesPerPixel(DF), Opt);
        Ok := SameOutput(DF, Got, Want, Worst);
        // 丸めの境目を狙った場面（半分・同点）は 1 ビットの違いも許さない
        if Ok and ((Name = 'half_tie') or (Name = 'round_half')) then
          if (Length(Got) <> Length(Want)) or not CompareMem(@Got[0], @Want[0], Length(Got)) then
          begin
            Ok := False;
            Worst := '丸めの境目の場面は完全に一致する';
          end;
      except
        on E: Exception do
        begin
          Ok := False;
          Worst := E.ClassName + ': ' + E.Message;
        end;
      end;
      if not Ok then
      begin
        Inc(Bad);
        WriteLn(Format('      %s %s -> %s (%s -> %s): %s', [Name, PMLPixelFormatName(SF), PMLPixelFormatName(DF),
          T[3], T[5], Worst]));
      end;
    end;
  Check(N = 69, '69 場面');
  Check(Bad = 0, Format('出力が SDL と同じ（整数は 1 まで、浮動小数は相対誤差まで。%d 場面が外れた）', [Bad]));
  WriteLn(Format('  [INFO] 完全に一致した成分: %d / %d（%.2f%%）', [ExactCount, TotalCount,
    100.0 * ExactCount / Max(TotalCount, 1)]));
end;

{ ---- 5 papimela の足した検査 ---- }

procedure TestExtras;
var
  Buf: array[0..63] of Byte;
  Dst: array[0..63] of Byte;
  Raised: Boolean;
begin
  WriteLn('5 papimela の足した検査');
  FillChar(Buf, SizeOf(Buf), 0);
  FillChar(Dst, SizeOf(Dst), 0);
  Raised := False;
  try
    PMLConvertPixelsAndColorspace(2, 2, PML_PIXELFORMAT_IYUV, PML_COLORSPACE_BT709_LIMITED, @Buf[0], 2,
      PML_PIXELFORMAT_ARGB8888, PML_COLORSPACE_SRGB, @Dst[0], 8);
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'YUV の形式は断る（EPMLArgument。YUV は PaPiMeLa.Surface.YUV の仕事）');
  Raised := False;
  try
    PMLConvertPixelsAndColorspace(2, 2, PML_PIXELFORMAT_ARGB8888, PML_COLORSPACE_SRGB, @Buf[0], 8,
      PML_PIXELFORMAT_INDEX8, PML_COLORSPACE_SRGB, @Dst[0], 2);
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'インデックス形式は断る（EPMLArgument）');
  Raised := False;
  try
    PMLConvertPixelsAndColorspace(2, 2, PML_PIXELFORMAT_UNKNOWN, PML_COLORSPACE_SRGB, @Buf[0], 8,
      PML_PIXELFORMAT_ARGB8888, PML_COLORSPACE_SRGB, @Dst[0], 8);
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, '不明な形式は断る（EPMLArgument）');
  // 幅か高さが 0 なら何もしない
  Buf[0] := $FF;
  PMLConvertPixelsAndColorspace(0, 2, PML_PIXELFORMAT_ARGB8888, PML_COLORSPACE_SRGB, @Buf[0], 8,
    PML_PIXELFORMAT_ARGB8888, PML_COLORSPACE_SRGB_LINEAR, @Dst[0], 8);
  Check(Dst[0] = 0, '幅 0 は何も書かない');
  // 色空間が UNKNOWN なら形式の既定になる（SDL_ConvertPixelsAndColorspace と同じ）
  FillChar(Buf, SizeOf(Buf), 128);
  PMLConvertPixelsAndColorspace(1, 1, PML_PIXELFORMAT_ARGB8888, PML_COLORSPACE_UNKNOWN, @Buf[0], 4,
    PML_PIXELFORMAT_RGBA128_FLOAT, PML_COLORSPACE_UNKNOWN, @Dst[0], 16);
  Check(Abs(PSingle(@Dst[0])^ - 0.2158) < 1e-3,
    '色空間 UNKNOWN は形式の既定（ARGB8888 は sRGB、RGBA128_FLOAT は線形）になる');
end;

begin
  WriteLn('=== test_colorspace ===');
  TestScalars;
  TestMatrices;
  TestWhitePoints;
  TestPixels;
  TestExtras;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: 色空間の変換が SDL と同じ値になる ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
