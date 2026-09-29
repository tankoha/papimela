{
  test_pixels — ピクセル形式の識別とマスク導出、色 ↔ 画素値の変換

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    形式識別子から読み取れる値、マスクの導出、そして MapRGBA → GetRGBA の
    往復が設計どおりかを確認する。

  WHY:
    マスクの導出は SDL の 240 行の switch を「並びとレイアウトからの算出」に
    置き換えた箇所で、papimela が独自に決めた規則である。**表を写していない以上、
    往復が合うことを機械的に確かめないと正しさの根拠が無い。**

    往復検査（色 → 画素値 → 色）は強い検査になる。マスクかシフトか幅のどれかが
    1 ビットでもずれれば、8 ビット成分の形式では必ず値が変わる。

  実行前提: 無し。表示サーバも IME も要らない。
}
program test_pixels;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  StrUtils,
  PaPiMeLa.Pixels;

var
  Failures: Integer = 0;

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

procedure Note(const AText: String);
begin
  WriteLn('  [観測] ', AText);
end;

// SDL のヘッダに書かれているマスクと一致するか。代表的な形式だけ直接指定する。
procedure CheckMasks(AFormat: TPMLPixelFormat; const AName: String;
  AR, AG, AB, AA: LongWord);
var
  D: TPMLPixelFormatDetails;
  OK: Boolean;
begin
  OK := PMLGetPixelFormatDetails(AFormat, D);
  Check(OK and (D.RMask = AR) and (D.GMask = AG)
           and (D.BMask = AB) and (D.AMask = AA),
    Format('%s のマスク R=$%.8x G=$%.8x B=$%.8x A=$%.8x',
      [AName, D.RMask, D.GMask, D.BMask, D.AMask]));
end;

// 8 ビット成分の形式は、色 → 画素値 → 色 が完全に一致しなければならない。
function RoundTripExact(AFormat: TPMLPixelFormat): Boolean;
var
  D: TPMLPixelFormatDetails;
  R, G, B, A: Byte;
  Pixel: LongWord;
  I: Integer;
const
  // 端と中間を混ぜる。マスクのずれは端で出やすい。
  Samples: array[0..5] of TPMLColor = (
    (R: 0;   G: 0;   B: 0;   A: 0),
    (R: 255; G: 255; B: 255; A: 255),
    (R: 255; G: 0;   B: 0;   A: 255),
    (R: 0;   G: 255; B: 0;   A: 128),
    (R: 0;   G: 0;   B: 255; A: 1),
    (R: 18;  G: 52;  B: 86;  A: 120)
  );
begin
  Result := False;
  if not PMLGetPixelFormatDetails(AFormat, D) then
    Exit;
  // 8 ビットに満たない成分は情報が落ちるので、この検査の対象外。
  if (D.RBits <> 8) or (D.GBits <> 8) or (D.BBits <> 8) then
    Exit;

  for I := Low(Samples) to High(Samples) do
  begin
    Pixel := PMLMapRGBA(D, nil, Samples[I].R, Samples[I].G, Samples[I].B,
      Samples[I].A);
    PMLGetRGBA(Pixel, D, nil, R, G, B, A);
    if (R <> Samples[I].R) or (G <> Samples[I].G) or (B <> Samples[I].B) then
      Exit;
    // アルファを持たない形式は A = 255 が返る。持つ形式は元の値。
    if D.HasAlpha then
    begin
      if A <> Samples[I].A then
        Exit;
    end
    else if A <> 255 then
      Exit;
  end;
  Result := True;
end;

const
  // 8 ビット成分の形式すべて。ここが往復検査の対象になる。
  Exact8: array[0..11] of TPMLPixelFormat = (
    PML_PIXELFORMAT_XRGB8888, PML_PIXELFORMAT_RGBX8888,
    PML_PIXELFORMAT_XBGR8888, PML_PIXELFORMAT_BGRX8888,
    PML_PIXELFORMAT_ARGB8888, PML_PIXELFORMAT_RGBA8888,
    PML_PIXELFORMAT_ABGR8888, PML_PIXELFORMAT_BGRA8888,
    PML_PIXELFORMAT_RGB24,    PML_PIXELFORMAT_BGR24,
    PML_PIXELFORMAT_RGBA32,   PML_PIXELFORMAT_ARGB32
  );

var
  D      : TPMLPixelFormatDetails;
  I      : Integer;
  Bad    : Integer;
  Names  : String;
  Palette: TPMLPalette;
  R, G, B, A: Byte;
  Pixel  : LongWord;
begin
  WriteLn('test_pixels — ピクセル形式と色の変換');
  WriteLn;

  WriteLn('1. 識別子から読み取る値');
  Check(PMLBitsPerPixel(PML_PIXELFORMAT_ARGB8888) = 32, 'ARGB8888 は 32 ビット');
  Check(PMLBytesPerPixel(PML_PIXELFORMAT_ARGB8888) = 4, 'ARGB8888 は 4 バイト');
  Check(PMLBitsPerPixel(PML_PIXELFORMAT_RGB565) = 16, 'RGB565 は 16 ビット');
  Check(PMLBytesPerPixel(PML_PIXELFORMAT_RGB24) = 3, 'RGB24 は 3 バイト');
  Check(PMLBytesPerPixel(PML_PIXELFORMAT_YUY2) = 2, 'YUY2 は 2 バイト（SDL と同じ扱い）');
  Check(PMLBytesPerPixel(PML_PIXELFORMAT_YV12) = 1, 'YV12 は 1 バイト');

  Check(PMLIsPixelFormatPacked(PML_PIXELFORMAT_ARGB8888), 'ARGB8888 はパックド');
  Check(PMLIsPixelFormatArray(PML_PIXELFORMAT_RGB24), 'RGB24 は配列');
  Check(PMLIsPixelFormatIndexed(PML_PIXELFORMAT_INDEX8), 'INDEX8 はインデックス');
  Check(PMLIsPixelFormatFourCC(PML_PIXELFORMAT_NV12), 'NV12 は FourCC');
  Check(not PMLIsPixelFormatFourCC(PML_PIXELFORMAT_ARGB8888),
    'ARGB8888 は FourCC ではない');
  Check(PMLIsPixelFormatAlpha(PML_PIXELFORMAT_ARGB8888), 'ARGB8888 はアルファあり');
  Check(not PMLIsPixelFormatAlpha(PML_PIXELFORMAT_XRGB8888),
    'XRGB8888 はアルファなし');
  Check(PMLIsPixelFormat10Bit(PML_PIXELFORMAT_ARGB2101010), 'ARGB2101010 は 10 ビット');
  Check(PMLIsPixelFormatFloat(PML_PIXELFORMAT_RGBA128_FLOAT),
    'RGBA128_FLOAT は浮動小数点');
  Check(PMLPixelFormatName(PML_PIXELFORMAT_ARGB8888) = 'ARGB8888', '名前を引ける');

  WriteLn;
  WriteLn('2. マスクの導出（SDL のヘッダに書かれている値と一致するか）');
  // これらは SDL_pixels.h の定義から決まる値で、papimela は算出で求めている。
  CheckMasks(PML_PIXELFORMAT_ARGB8888, 'ARGB8888',
    $00FF0000, $0000FF00, $000000FF, $FF000000);
  CheckMasks(PML_PIXELFORMAT_RGBA8888, 'RGBA8888',
    $FF000000, $00FF0000, $0000FF00, $000000FF);
  CheckMasks(PML_PIXELFORMAT_ABGR8888, 'ABGR8888',
    $000000FF, $0000FF00, $00FF0000, $FF000000);
  CheckMasks(PML_PIXELFORMAT_BGRA8888, 'BGRA8888',
    $0000FF00, $00FF0000, $FF000000, $000000FF);
  CheckMasks(PML_PIXELFORMAT_XRGB8888, 'XRGB8888',
    $00FF0000, $0000FF00, $000000FF, $00000000);
  CheckMasks(PML_PIXELFORMAT_RGB565, 'RGB565', $F800, $07E0, $001F, $0000);
  CheckMasks(PML_PIXELFORMAT_BGR565, 'BGR565', $001F, $07E0, $F800, $0000);
  CheckMasks(PML_PIXELFORMAT_XRGB1555, 'XRGB1555', $7C00, $03E0, $001F, $0000);
  CheckMasks(PML_PIXELFORMAT_ARGB1555, 'ARGB1555', $7C00, $03E0, $001F, $8000);
  CheckMasks(PML_PIXELFORMAT_ARGB4444, 'ARGB4444', $0F00, $00F0, $000F, $F000);
  CheckMasks(PML_PIXELFORMAT_RGB332, 'RGB332', $E0, $1C, $03, $00);
  CheckMasks(PML_PIXELFORMAT_RGB24, 'RGB24',
    $000000FF, $0000FF00, $00FF0000, $00000000);
  CheckMasks(PML_PIXELFORMAT_BGR24, 'BGR24',
    $00FF0000, $0000FF00, $000000FF, $00000000);

  // シフトとビット幅もマスクから導けているか。
  PMLGetPixelFormatDetails(PML_PIXELFORMAT_ARGB8888, D);
  Check((D.RShift = 16) and (D.GShift = 8) and (D.BShift = 0) and (D.AShift = 24),
    'ARGB8888 のシフト');
  Check((D.RBits = 8) and (D.GBits = 8) and (D.BBits = 8) and (D.ABits = 8),
    'ARGB8888 のビット幅');
  PMLGetPixelFormatDetails(PML_PIXELFORMAT_RGB565, D);
  Check((D.RBits = 5) and (D.GBits = 6) and (D.BBits = 5), 'RGB565 のビット幅');
  Check(not D.HasAlpha, 'RGB565 はアルファを持たない');

  WriteLn;
  WriteLn('3. マスクを持たない形式');
  Check(not PMLGetPixelFormatDetails(PML_PIXELFORMAT_NV12, D),
    'FourCC は False を返す');
  Check(D.BytesPerPixel = 1, 'False でも BytesPerPixel は埋まる');
  Check(not PMLGetPixelFormatDetails(PML_PIXELFORMAT_INDEX8, D),
    'インデックス形式は False を返す');
  Check(not PMLGetPixelFormatDetails(PML_PIXELFORMAT_UNKNOWN, D),
    'UNKNOWN は False を返す');

  WriteLn;
  WriteLn('4. 色 → 画素値 → 色 の往復（8 ビット成分の形式すべて）');
  Bad := 0;
  Names := '';
  for I := Low(Exact8) to High(Exact8) do
    if not RoundTripExact(Exact8[I]) then
    begin
      Inc(Bad);
      if Names <> '' then
        Names := Names + ', ';
      Names := Names + PMLPixelFormatName(Exact8[I]);
    end;
  Check(Bad = 0, Format('%d 形式 x 6 色が完全に往復する%s',
    [Length(Exact8), IfThen(Bad = 0, '', ' — 失敗: ' + Names)]));

  // 実際の値も 1 つ確かめる。算出が合っていれば ARGB8888 はこの並びになる。
  PMLGetPixelFormatDetails(PML_PIXELFORMAT_ARGB8888, D);
  Pixel := PMLMapRGBA(D, nil, $12, $34, $56, $78);
  Check(Pixel = $78123456, Format('ARGB8888 の画素値が $78123456（実際 $%.8x）', [Pixel]));
  PMLGetPixelFormatDetails(PML_PIXELFORMAT_RGBA8888, D);
  Pixel := PMLMapRGBA(D, nil, $12, $34, $56, $78);
  Check(Pixel = $12345678, Format('RGBA8888 の画素値が $12345678（実際 $%.8x）', [Pixel]));

  WriteLn;
  WriteLn('5. 狭い成分の伸縮');
  PMLGetPixelFormatDetails(PML_PIXELFORMAT_RGB565, D);
  // 5 ビットの最大値は 8 ビットの最大値へ伸びなければならない。
  Pixel := PMLMapRGBA(D, nil, 255, 255, 255, 255);
  PMLGetRGBA(Pixel, D, nil, R, G, B, A);
  Check((R = 255) and (G = 255) and (B = 255), '白が白へ戻る（RGB565）');
  Pixel := PMLMapRGBA(D, nil, 0, 0, 0, 255);
  PMLGetRGBA(Pixel, D, nil, R, G, B, A);
  Check((R = 0) and (G = 0) and (B = 0), '黒が黒へ戻る（RGB565）');
  Check(A = 255, 'アルファを持たない形式では A が 255');

  WriteLn;
  WriteLn('6. パレット');
  Palette := TPMLPalette.Create(nil, nil, 4);
  try
    Check(Palette.Count = 4, '要求した数だけ色を持つ');
    Palette.SetColors([TPMLColor.Make(255, 0, 0), TPMLColor.Make(0, 255, 0),
                       TPMLColor.Make(0, 0, 255), TPMLColor.Black]);
    Check(Palette[1].G = 255, '設定した色を読める');
    PMLGetPixelFormatDetails(PML_PIXELFORMAT_INDEX8, D);
    // パレット経路では「最も近い色」の添字が返る。
    Check(PMLMapRGB(D, Palette, 250, 10, 10) = 0, '赤に近い色は添字 0');
    Check(PMLMapRGB(D, Palette, 10, 10, 250) = 2, '青に近い色は添字 2');
    PMLGetRGBA(1, D, Palette, R, G, B, A);
    Check((R = 0) and (G = 255) and (B = 0), '添字から色を引ける');
    // 範囲外は黒にする（落ちないこと）。
    PMLGetRGBA(99, D, Palette, R, G, B, A);
    Check((R = 0) and (G = 0) and (B = 0) and (A = 255), '範囲外の添字は黒');
  finally
    Palette.Free;
  end;

  WriteLn;
  WriteLn('7. マスクからの逆引き');
  Check(PMLGetPixelFormatForMasks(32, $00FF0000, $0000FF00, $000000FF, $FF000000)
        = PML_PIXELFORMAT_ARGB8888, 'ARGB8888 を逆引きできる');
  Check(PMLGetPixelFormatForMasks(16, $F800, $07E0, $001F, 0)
        = PML_PIXELFORMAT_RGB565, 'RGB565 を逆引きできる');
  Check(PMLGetPixelFormatForMasks(32, 1, 2, 3, 4) = PML_PIXELFORMAT_UNKNOWN,
    '当てはまらなければ UNKNOWN');

  Note(Format('SizeOf(TPMLPixelFormatDetails) = %d バイト',
    [SizeOf(TPMLPixelFormatDetails)]));

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn('=== 結論: 形式の算出と色の変換が設計どおり ===');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('=== 失敗 %d 件 ===', [Failures]));
    ExitCode := 1;
  end;
end.
