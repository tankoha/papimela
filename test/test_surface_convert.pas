{
  test_surface_convert — サーフェスの変換（色空間つき）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    参照版 SDL の結果（test/surface_convert_expected.inc。tools/surface-convert-expect/gen.bb が作る）と、
    papimela の TPMLSurface.Convert / ConvertTo の結果を突き合わせる:
    1. 38 場面（SDL_ConvertSurface と SDL_ConvertSurfaceAndColorspace）: 形式の組（8 ビット・RGB24・10 ビット・
       16 ビット整数・16 / 32 ビット浮動小数）、色空間の既定（変換先の形式の既定）と指定（sRGB・線形・HDR10・
       JPEG）、色空間 UNKNOWN は転送元のまま、白点・ヘッドルーム・トーンマップの引き継ぎ、パレットの入力
       （従来の経路。結果が SDL と同じことを守る）。比べるのは画素・結果の色空間・結果の白点・ヘッドルーム・
       トーンマップ
    2. papimela の足した検査: 元のサーフェスを変えない、ブレンドモード・変調・カラーキーは変換に影響しない
       （SDL は変換の間だけ外す）

  WHY:
    §3 の 2「サーフェスに色空間を持たせた先」の受け入れ検査。今までの Convert は 1 画素ずつ 8 ビットの色へ戻して
    書き直すだけで、浮動小数や 16 ビットの形式を ARGB8888 へ直すとき色空間の変換（ガンマ）が入らなかった。
    表示サーバは要らない。

  SDL との違い（意図したもの）:
    - 浮動小数の演算の最後の 1 ビット（powf など）は CPU とコンパイラに依る。期待値は積和を融合しない参照版で作る。
      整数の形式は成分ごとに 1、浮動小数は相対 1e-5（16 ビット浮動小数は 3e-3、転送元が PQ のとき 3e-4）まで許す
    - インデックス形式への変換、カラーキー・ブレンドモード・変調・クリップ矩形を結果へ引き継ぐことは、今回の範囲外
      （従来の Convert も引き継がない）
}
program test_surface_convert;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.Colorspace;

{$I surface_convert_expected.inc}

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
  SC, DC, WantCS: TPMLColorspace;
  Src, Dst: TPMLSurface;
  SPal: TPMLPalette;
  Props: TPMLSurfaceColorProps;
  Want, Got: TBytes;
  Worst, Name, WantTone: String;
  Ok: Boolean;
  RelTol: Double;
begin
  WriteLn('1 SDL のサーフェスの変換と突き合わせる');
  N := 0;
  Bad := 0;
  for I := 0 to High(SurfaceConvertExpected) do
  begin
    T := Tokens(SurfaceConvertExpected[I]);
    Name := T[1];
    SF := TPMLPixelFormat(Hex32(T[2]));
    SC := TPMLColorspace(Hex32(T[3]));
    DF := TPMLPixelFormat(Hex32(T[4]));
    DC := TPMLColorspace(Hex32(Copy(T[5], 2, 8)));
    Src := TPMLSurface.Create(StrToInt(T[6]), StrToInt(T[7]), SF);
    SPal := MakePalette(T[12]);
    Dst := nil;
    try
      if SPal <> nil then
        Src.SetPalette(SPal, True);
      Src.Colorspace := SC;
      FillSurface(Src, HexToBytes(T[11]));
      Props.SDRWhitePoint := BitsToSingle(Hex32(T[8]));
      Props.HDRHeadroom := BitsToSingle(Hex32(T[9]));
      Props.Tonemap := '';
      if T[10] <> '-' then
        Props.Tonemap := T[10];
      Src.ColorProps := Props;
      Want := HexToBytes(T[13]);
      WantCS := TPMLColorspace(Hex32(T[14]));
      WantTone := T[17];
      if WantTone = '-' then
        WantTone := '';
      Inc(N);
      try
        if T[5][1] = 'U' then
          Dst := Src.ConvertTo(DF, DC)
        else
          Dst := Src.Convert(DF);
        Got := SurfaceBytes(Dst);
        if PMLColorspaceTransfer(SC) = 16 then   // 16 = PQ（SDR の白の約 49 倍まで届き、行列で 1 ulp が増幅される）
          RelTol := 3e-4
        else
          RelTol := 1e-5;
        Ok := SameOutput(DF, Got, Want, Worst, RelTol);
        if Ok and (Dst.Colorspace <> WantCS) then
        begin
          Ok := False;
          Worst := Format('結果の色空間 $%x (SDL $%x)', [Dst.Colorspace, WantCS]);
        end;
        if Ok and (SingleToBits(Dst.ColorProps.SDRWhitePoint) <> Hex32(T[15])) then
        begin
          Ok := False;
          Worst := Format('結果の白点 %g (SDL %g)', [Dst.ColorProps.SDRWhitePoint, BitsToSingle(Hex32(T[15]))]);
        end;
        if Ok and (SingleToBits(Dst.ColorProps.HDRHeadroom) <> Hex32(T[16])) then
        begin
          Ok := False;
          Worst := Format('結果のヘッドルーム %g (SDL %g)', [Dst.ColorProps.HDRHeadroom, BitsToSingle(Hex32(T[16]))]);
        end;
        if Ok and (Dst.ColorProps.Tonemap <> WantTone) then
        begin
          Ok := False;
          Worst := Format('結果のトーンマップ ''%s'' (SDL ''%s'')', [Dst.ColorProps.Tonemap, WantTone]);
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
  Check(N = 38, '38 場面');
  Check(Bad = 0, Format('結果が SDL と同じ（画素・色空間・白点・ヘッドルーム・トーンマップ。%d 場面が外れた）', [Bad]));
  WriteLn(Format('  [INFO] 完全に一致した成分: %d / %d（%.2f%%）', [ExactCount, TotalCount,
    100.0 * ExactCount / Max(TotalCount, 1)]));
end;

{ ---- 2 papimela の足した検査 ---- }

procedure TestExtras;
var
  Src, Dst: TPMLSurface;
  Before, After: TBytes;
begin
  WriteLn('2 papimela の足した検査');
  Src := TPMLSurface.Create(2, 2, PML_PIXELFORMAT_ARGB8888);
  try
    Src.WriteRaw(0, 0, $80FF0000);
    Src.WriteRaw(1, 0, $FF00FF00);
    Src.WriteRaw(0, 1, $FF0000FF);
    Src.WriteRaw(1, 1, $00FFFFFF);
    Src.BlendMode := TPMLBlendMode.Blend;
    Src.ColorMod := TPMLColor.Make(10, 20, 30);
    Src.AlphaMod := 100;
    Src.SetColorKey(True, $FF00FF00);
    Before := SurfaceBytes(Src);
    Dst := Src.Convert(PML_PIXELFORMAT_ABGR8888);
    try
      After := SurfaceBytes(Src);
      Check((Length(Before) = Length(After)) and CompareMem(@Before[0], @After[0], Length(Before)), '元のサーフェスの画素は変わらない');
      Check((Src.BlendMode = TPMLBlendMode.Blend) and (Src.AlphaMod = 100) and (Src.ColorMod.R = 10) and Src.HasColorKey,
        '元のサーフェスのブレンド・変調・カラーキーは変わらない');
      // 変換は色の写しで、ブレンドや変調やカラーキーは掛からない（ARGB の $80FF0000 は ABGR の $800000FF になる）
      Check(Dst.ReadRaw(0, 0) = $800000FF, '半透明の赤は変調もブレンドも掛からずそのまま写る');
      Check(Dst.ReadRaw(1, 0) = $FF00FF00, 'カラーキーの色もそのまま写る（透明にならない）');
    finally
      Dst.Free;
    end;
  finally
    Src.Free;
  end;
end;

begin
  WriteLn('=== test_surface_convert ===');
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
