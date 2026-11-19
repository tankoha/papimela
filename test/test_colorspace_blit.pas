{
  test_colorspace_blit — 色空間つきの転送（拡大縮小・ブレンド・変調・カラーキー・インデックスの出力）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    参照版 SDL の結果（test/colorspace_blit_expected.inc。tools/colorspace-blit-expect/gen.bb が作る）と、
    papimela の PMLBlit / PMLBlitScaled の結果を突き合わせる:
    1. 56 場面（SDL_BlitSurfaceScaled が SDL_Blit_Slow_Float を通る場面）: 形式と色空間の組（8 ビット・RGB24・
       10 ビット・16 ビット整数・16 / 32 ビット浮動小数・INDEX8）、ブレンド 5 通り（なし・ブレンド・加算・
       変調・乗算）、色の変調とアルファの変調、カラーキー（浮動小数の経路は何もしない）、拡大・縮小（最近傍、
       中心の標本点）、矩形の切り出しと転送先の端での切り取り、白点・ヘッドルーム・トーンマップ、
       転送先のヘッドルームが 0 のとき転送元の値が書き込まれること
    2. papimela の足した検査: サーフェスの色空間の既定、Duplicate が色空間と指定を引き継ぐこと、
       色空間が同じ 4 バイト以下の形式は従来どおりの整数の経路（色空間つきの転送を通らない）

  WHY:
    §3 の 2「色空間の変換の残り」（SDL_Blit_Slow_Float の拡大・縮小・ブレンド・変調・カラーキー）の受け入れ検査。
    表示サーバは要らない。

  SDL との違い（意図したもの）:
    - 浮動小数の演算の最後の 1 ビット（powf など）は CPU とコンパイラに依る。転送元が PQ の場面は、入力が SDR の白の約 49 倍まで
      届き、行列で打ち消し合って 1 ulp の差が 1e-4 に増幅されるので、相対 3e-4 まで許す。期待値は積和を融合しない
      参照版で作る（tools/colorspace-expect/gen.bb と同じ）。整数の形式は成分ごとに 1、浮動小数は相対 1e-5
      （16 ビット浮動小数は 3e-3）まで許し、完全に一致した割合は表示する。インデックスの出力は完全に一致する
    - 転送先の端で切り取る拡大・縮小は SDL と経路が違う（SDL は先に別のサーフェスへ拡大してから転送する）。
      検査には入れない
}
program test_colorspace_blit;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.Colorspace,
  PaPiMeLa.Surface.Blit;

{$I colorspace_blit_expected.inc}

var
  Failures: Integer = 0;
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

{ 出力の比べ。整数の形式は成分ごとに 1 まで、浮動小数は相対の誤差まで許す。インデックスは完全に一致。 }
function SameOutput(AFormat: TPMLPixelFormat; const AGot, AWant: TBytes; out AWorst: String;
  ARelTol: Double = 1e-5): Boolean;
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
      Tol := ARelTol * Abs(WD) + 1e-6;
      if Abs(GD - WD) > Tol then
      begin
        Result := False;
        AWorst := Format('成分 %d: %g (SDL %g)', [I, GD, WD]);
      end;
    end;
  end
  else if Typ = TPMLPixelType.Index8 then
  begin
    for I := 0 to High(AGot) do
    begin
      Count(AGot[I] = AWant[I]);
      if AGot[I] <> AWant[I] then
      begin
        Result := False;
        AWorst := Format('番号 %d: %d (SDL %d)', [I, AGot[I], AWant[I]]);
      end;
    end;
  end
  else
  begin
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

{ 16 進の文字列（RRGGBBAA を 16 個）からパレット（256 色。残りは白）を作る。nil = '-' }
function MakePalette(const S: String): TPMLPalette;
var
  I: Integer;
  Cols: array[0..15] of TPMLColor;
begin
  Result := nil;
  if S = '-' then
    Exit;
  Result := TPMLPalette.Create(nil, nil, 256);
  for I := 0 to 15 do
    Cols[I] := TPMLColor.Make(
      Byte(StrToInt('$' + Copy(S, I * 8 + 1, 2))), Byte(StrToInt('$' + Copy(S, I * 8 + 3, 2))),
      Byte(StrToInt('$' + Copy(S, I * 8 + 5, 2))), Byte(StrToInt('$' + Copy(S, I * 8 + 7, 2))));
  Result.SetColors(Cols, 0);
end;

function BlendFromSDL(AValue: Integer): TPMLBlendMode;
begin
  case AValue of
    1: Result := TPMLBlendMode.Blend;
    2: Result := TPMLBlendMode.Add;
    4: Result := TPMLBlendMode.Modulate;
    8: Result := TPMLBlendMode.Multiply;
  else
    Result := TPMLBlendMode.None;
  end;
end;

procedure FillSurface(ASurf: TPMLSurface; const ABytes: TBytes);
var
  Y, Row: Integer;
begin
  Row := ASurf.Width * ASurf.Details.BytesPerPixel;
  for Y := 0 to ASurf.Height - 1 do
    Move(ABytes[Y * Row], (PByte(ASurf.Pixels) + Y * ASurf.Pitch)^, Row);
end;

function SurfaceBytes(ASurf: TPMLSurface): TBytes;
var
  Y, Row: Integer;
begin
  Row := ASurf.Width * ASurf.Details.BytesPerPixel;
  SetLength(Result, Row * ASurf.Height);
  for Y := 0 to ASurf.Height - 1 do
    Move((PByte(ASurf.Pixels) + Y * ASurf.Pitch)^, Result[Y * Row], Row);
end;

{ ---- 1 SDL との突き合わせ ---- }

procedure TestScenes;
var
  I, N, Bad: Integer;
  T: TStringArray;
  SF, DF: TPMLPixelFormat;
  Src, Dst: TPMLSurface;
  SPal, DPal: TPMLPalette;
  SR, DR: TPMLRect;
  Props: TPMLSurfaceColorProps;
  Want, Got: TBytes;
  Worst, Name: String;
  Ok, Scaled: Boolean;
  WantHead: LongWord;
  RelTol: Double;
  Key: Integer;
begin
  WriteLn('1 SDL の色空間つきの転送と突き合わせる');
  N := 0;
  Bad := 0;
  for I := 0 to High(ColorspaceBlitExpected) do
  begin
    T := Tokens(ColorspaceBlitExpected[I]);
    Name := T[1];
    SF := TPMLPixelFormat(Hex32(T[2]));
    DF := TPMLPixelFormat(Hex32(T[4]));
    Src := TPMLSurface.Create(StrToInt(T[6]), StrToInt(T[7]), SF);
    Dst := TPMLSurface.Create(StrToInt(T[8]), StrToInt(T[9]), DF);
    SPal := MakePalette(T[30]);
    DPal := MakePalette(T[32]);
    try
      if SPal <> nil then
        Src.SetPalette(SPal, True);
      if DPal <> nil then
        Dst.SetPalette(DPal, True);
      Src.Colorspace := TPMLColorspace(Hex32(T[3]));
      Dst.Colorspace := TPMLColorspace(Hex32(T[5]));
      FillSurface(Src, HexToBytes(T[29]));
      FillSurface(Dst, HexToBytes(T[31]));
      Src.BlendMode := BlendFromSDL(StrToInt(T[18]));
      Src.ColorMod := TPMLColor.Make(StrToInt(T[19]), StrToInt(T[20]), StrToInt(T[21]));
      Src.AlphaMod := StrToInt(T[22]);
      Key := StrToInt(T[23]);
      if Key >= 0 then
        Src.SetColorKey(True, LongWord(Key));
      Props.SDRWhitePoint := BitsToSingle(Hex32(T[24]));
      Props.HDRHeadroom := BitsToSingle(Hex32(T[25]));
      Props.Tonemap := '';
      if T[28] <> '-' then
        Props.Tonemap := T[28];
      Src.ColorProps := Props;
      Props.SDRWhitePoint := BitsToSingle(Hex32(T[26]));
      Props.HDRHeadroom := BitsToSingle(Hex32(T[27]));
      Props.Tonemap := '';
      Dst.ColorProps := Props;
      SR := TPMLRect.Make(StrToInt(T[10]), StrToInt(T[11]), StrToInt(T[12]), StrToInt(T[13]));
      DR := TPMLRect.Make(StrToInt(T[14]), StrToInt(T[15]), StrToInt(T[16]), StrToInt(T[17]));
      Scaled := (SR.W <> DR.W) or (SR.H <> DR.H);
      // 転送元が PQ（HDR10）の場面: SDR の白で割ると 10000 nit は約 49 倍になり、BT.2020 から BT.709 への行列で打ち消し合う。
      // powf の 1 ulp の差が増幅されて 1e-4 になる（既存の PMLConvertPixelsAndColorspace も同じ値）ので、相対許容を広げる
      if PMLColorspaceTransfer(Src.Colorspace) = 16 then   // 16 = PQ
        RelTol := 3e-4
      else
        RelTol := 1e-5;
      Want := HexToBytes(T[33]);
      WantHead := Hex32(T[34]);
      Inc(N);
      try
        // SDL_BlitSurfaceScaled は大きさが同じなら SDL_BlitSurface へ回す。papimela も同じ呼び分けで両方を通す
        if Scaled then
          PMLBlitScaled(Src, SR, Dst, DR)
        else
          PMLBlit(Src, SR, Dst, DR);
        Got := SurfaceBytes(Dst);
        Ok := SameOutput(DF, Got, Want, Worst, RelTol);
        if Ok and (SingleToBits(Dst.ColorProps.HDRHeadroom) <> WantHead) then
        begin
          Ok := False;
          Worst := Format('転送先のヘッドルーム %.4g (SDL %.4g)',
            [Dst.ColorProps.HDRHeadroom, BitsToSingle(WantHead)]);
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
        WriteLn(Format('      %s %s -> %s: %s', [Name, PMLPixelFormatName(SF), PMLPixelFormatName(DF), Worst]));
      end;
    finally
      Src.Free;
      Dst.Free;
    end;
  end;
  Check(N = 56, '56 場面');
  Check(Bad = 0, Format('転送先が SDL と同じ（整数は 1 まで、浮動小数は相対誤差まで、インデックスは完全に。%d 場面が外れた）', [Bad]));
  WriteLn(Format('  [INFO] 完全に一致した成分: %d / %d（%.2f%%）', [ExactCount, TotalCount,
    100.0 * ExactCount / Max(TotalCount, 1)]));
end;

{ ---- 2 papimela の足した検査 ---- }

procedure TestClippedScale;
var
  Src, Full, Clipped: TPMLSurface;
  X, Y, Bad: Integer;
  A, B: TPMLColor;
  P: PSingle;
begin
  Src := TPMLSurface.Create(5, 4, PML_PIXELFORMAT_RGBA128_FLOAT);
  Full := TPMLSurface.Create(14, 11, PML_PIXELFORMAT_ARGB8888);
  Clipped := TPMLSurface.Create(14, 11, PML_PIXELFORMAT_ARGB8888);
  try
    // WritePixel は浮動小数の形式へ書けないので、メモリへ直接書く（線形の 0..1 の傾き）
    for Y := 0 to 3 do
      for X := 0 to 4 do
      begin
        P := PSingle(PByte(Src.Pixels) + Y * Src.Pitch + X * 16);
        P[0] := 0.1 + X * 0.2;
        P[1] := 0.05 + Y * 0.25;
        P[2] := 0.02 * (X + Y);
        P[3] := 1.0;
      end;
    Full.Colorspace := PML_COLORSPACE_SRGB;
    Clipped.Colorspace := PML_COLORSPACE_SRGB;
    PMLBlitScaled(Src, TPMLRect.Make(0, 0, 0, 0), Full, TPMLRect.Make(0, 0, 14, 11));
    Clipped.ClipRect := TPMLRect.Make(3, 2, 8, 6);
    PMLBlitScaled(Src, TPMLRect.Make(0, 0, 0, 0), Clipped, TPMLRect.Make(0, 0, 14, 11));
    // 比べる範囲に色の違う画素があること（一色の絵では標本点の誤りを見つけられない）
    Check((Full.ReadPixel(3, 2).R <> Full.ReadPixel(10, 7).R) and (Full.ReadPixel(3, 2).G <> Full.ReadPixel(10, 7).G),
      '入力の絵に色の変化がある（空の絵ではない）');
    Bad := 0;
    for Y := 2 to 7 do
      for X := 3 to 10 do
      begin
        A := Full.ReadPixel(X, Y);
        B := Clipped.ReadPixel(X, Y);
        if (A.R <> B.R) or (A.G <> B.G) or (A.B <> B.B) or (A.A <> B.A) then
          Inc(Bad);
      end;
    Check(Bad = 0, Format('クリップ矩形で切られた拡大は、切られない拡大の同じ位置と同じ（%d 画素が違った）', [Bad]));
    A := Clipped.ReadPixel(0, 0);
    Check((A.R = 0) and (A.G = 0) and (A.B = 0) and (A.A = 0), 'クリップ矩形の外は書かれない');
  finally
    Src.Free;
    Full.Free;
    Clipped.Free;
  end;
end;

procedure TestExtras;
var
  A, B, C: TPMLSurface;
  Props: TPMLSurfaceColorProps;
  Raw: LongWord;
begin
  WriteLn('2 papimela の足した検査');
  A := TPMLSurface.Create(2, 2, PML_PIXELFORMAT_ARGB8888);
  B := TPMLSurface.Create(2, 2, PML_PIXELFORMAT_RGBA64_FLOAT);
  try
    Check(A.Colorspace = PML_COLORSPACE_SRGB, 'ARGB8888 の色空間の既定は sRGB');
    Check(B.Colorspace = PML_COLORSPACE_SRGB_LINEAR, 'RGBA64_FLOAT の色空間の既定は線形');
    Props.SDRWhitePoint := 2.0;
    Props.HDRHeadroom := 4.0;
    Props.Tonemap := 'chrome';
    A.ColorProps := Props;
    A.Colorspace := PML_COLORSPACE_HDR10;
    C := A.Duplicate;
    try
      Check(C.Colorspace = PML_COLORSPACE_HDR10, 'Duplicate は色空間を引き継ぐ');
      Check((C.ColorProps.SDRWhitePoint = 2.0) and (C.ColorProps.HDRHeadroom = 4.0) and (C.ColorProps.Tonemap = 'chrome'),
        'Duplicate は白点・ヘッドルーム・トーンマップを引き継ぐ');
    finally
      C.Free;
    end;
  finally
    A.Free;
    B.Free;
  end;
  // 転送先の端で切られた拡大（クリップ矩形）: 切られた範囲の画素は、切られない転送の同じ位置の画素と同じになる
  // （SDL は先に別のサーフェスへ拡大するが、標本点は切られる前の矩形の中の位置で決まる）
  TestClippedScale;
  // 色空間が同じ 4 バイトの形式は従来の整数の経路。半透明の赤をブレンドして、色空間つきの経路（浮動小数）を
  // 通っていないことを、四捨五入の整数の式（Mul255）の値で確かめる
  A := TPMLSurface.Create(1, 1, PML_PIXELFORMAT_ARGB8888);
  B := TPMLSurface.Create(1, 1, PML_PIXELFORMAT_ARGB8888);
  try
    A.WriteRaw(0, 0, $80FF0000);
    B.WriteRaw(0, 0, $FF0000FF);
    A.BlendMode := TPMLBlendMode.Blend;
    PMLBlit(A, TPMLRect.Make(0, 0, 0, 0), B, TPMLRect.Make(0, 0, 0, 0));
    Raw := B.ReadRaw(0, 0);
    Check(Raw = B.MapColor(PMLBlendColor(TPMLColor.Make(255, 0, 0, 128), TPMLColor.Make(0, 0, 255, 255), TPMLBlendMode.Blend)),
      '色空間が同じ 4 バイトの形式は従来の整数の経路（PMLBlendColor と同じ値）');
  finally
    A.Free;
    B.Free;
  end;
end;

begin
  WriteLn('=== test_colorspace_blit ===');
  TestScenes;
  TestExtras;
  WriteLn;
  if Failures = 0 then
    WriteLn('ALL PASSED')
  else
    WriteLn('FAILED: ', Failures);
  if Failures <> 0 then
    Halt(1);
end.
