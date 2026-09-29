{
  PaPiMeLa.Surface.BMP — BMP の読み書き

  Origin : ported from SDL (src/video/SDL_bmp.c)
           Scope: ヘッダ版ごとの分岐（12 / 40 / 52 / 56 バイト）、BI_BITFIELDS の
           マスクがどこに置かれるか、高さが負のとき上から下へ並ぶこと、
           行が 4 バイト境界へ揃うこと。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.4、§11 #28

  WHAT:
    TStream から BMP を読んで TPMLSurface にし、TPMLSurface を BMP として書く。

  WHY:
    テストと標本画像のために、外部ライブラリ無しで読み書きできる形式が 1 つ要る。
    BMP は圧縮が無く、どの環境でも開けるので、その役に向いている。

  RESOLVED:
    - 読み込みは 1 / 4 / 8 / 16 / 24 / 32 ビット、BI_RGB と BI_BITFIELDS
    - 書き出しはアルファの有無で 24 ビット BI_RGB と 32 ビット BI_BITFIELDS を
      使い分ける。24 ビットの方がどこでも開けるので、不要なら使わない
    - 行の詰め物は 4 バイト境界。読み書きの両方で必要

  NOT RESOLVED:
    - RLE 圧縮（BI_RLE4 / BI_RLE8）は未対応。出会ったら例外にする。
      SDL は読める。標本画像で使う予定が無いので後回しにした
    - 色空間や ICC プロファイル（BITMAPV4 / V5 の追加部分）は読み飛ばす

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Surface.BMP;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface;

// 読めなければ EPMLIOError。戻り値は呼び出し側が Free する。
function PMLLoadBMP(AStream: TStream): TPMLSurface;
function PMLLoadBMPFile(const APath: String): TPMLSurface;

// アルファを持つ形式なら 32 ビット、そうでなければ 24 ビットで書く。
procedure PMLSaveBMP(AStream: TStream; ASurface: TPMLSurface);
procedure PMLSaveBMPFile(const APath: String; ASurface: TPMLSurface);

implementation

uses
  PaPiMeLa.IO;

const
  BI_RGB       = 0;
  BI_RLE8      = 1;
  BI_RLE4      = 2;
  BI_BITFIELDS = 3;

  FILE_HEADER_SIZE = 14;

{ ---- 読み込み ---- }

{ パレットを読む。

  ヘッダが 12 バイト（BITMAPCOREHEADER）のときは 1 色 3 バイト、
  それ以降は 4 バイト（末尾が未使用）。ここを取り違えると色がずれる。 }
function ReadPalette(AStream: TStream; ACount: Integer;
  AThreeByte: Boolean): TPMLPalette;
var
  I: Integer;
  B, G, R: Byte;
begin
  Result := TPMLPalette.Create(nil, nil, ACount);
  try
    for I := 0 to ACount - 1 do
    begin
      B := PMLReadU8(AStream);
      G := PMLReadU8(AStream);
      R := PMLReadU8(AStream);
      if not AThreeByte then
        PMLReadU8(AStream);
      Result[I] := TPMLColor.Make(R, G, B, 255);
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ ビット数とマスクから papimela の形式を決める。

  BI_BITFIELDS でマスクが与えられていればそれで逆引きし、駄目なら
  ビット数ごとの既定（BMP が昔から使ってきた並び）にする。 }
function FormatFor(ABits: Integer; AHaveMasks: Boolean;
  AR, AG, AB, AA: LongWord): TPMLPixelFormat;
begin
  if AHaveMasks then
  begin
    Result := PMLGetPixelFormatForMasks(ABits, AR, AG, AB, AA);
    if Result <> PML_PIXELFORMAT_UNKNOWN then
      Exit;
  end;
  case ABits of
    1 : Result := PML_PIXELFORMAT_INDEX1MSB;
    4 : Result := PML_PIXELFORMAT_INDEX4MSB;
    8 : Result := PML_PIXELFORMAT_INDEX8;
    // 無印の 16 ビット BMP は 5-5-5。565 ではない。
    16: Result := PML_PIXELFORMAT_XRGB1555;
    24: Result := PML_PIXELFORMAT_BGR24;
    32: Result := PML_PIXELFORMAT_XRGB8888;
  else
    Result := PML_PIXELFORMAT_UNKNOWN;
  end;
end;

{ 1 行ぶんのビットを画素へ展開する。1 / 4 ビットはバイトに複数詰まっている。 }
procedure ExpandIndexedRow(ASurface: TPMLSurface; AY: Integer;
  const ARow: TBytes; ABits: Integer);
var
  X, Idx: Integer;
begin
  for X := 0 to ASurface.Width - 1 do
  begin
    case ABits of
      1: Idx := (ARow[X shr 3] shr (7 - (X and 7))) and 1;
      4: if (X and 1) = 0 then
           Idx := ARow[X shr 1] shr 4
         else
           Idx := ARow[X shr 1] and $0F;
    else
      Idx := ARow[X];
    end;
    ASurface.WriteRaw(X, AY, LongWord(Idx));
  end;
end;

function PMLLoadBMP(AStream: TStream): TPMLSurface;
var
  Magic     : Word;
  DataOffset: LongWord;
  HeaderSize: LongWord;
  W, H      : LongInt;
  Bits      : Word;
  Compress  : LongWord;
  ClrUsed   : LongWord;
  RMask, GMask, BMask, AMask: LongWord;
  HaveMasks : Boolean;
  TopDown   : Boolean;
  Fmt       : TPMLPixelFormat;
  Consumed  : Int64;
  Base      : Int64;
  PaletteN  : Integer;
  Pal       : TPMLPalette;
  SrcPitch  : Integer;
  Row       : TBytes;
  Y, DstY, X: Integer;
begin
  Result := nil;
  Pal := nil;
  Base := AStream.Position;

  Magic := PMLReadU16LE(AStream);
  if Magic <> $4D42 then    // 'BM'
    raise EPMLIOError.Create('not a BMP file (bad magic)');
  PMLReadU32LE(AStream);    // ファイル全体の大きさ。信用しない
  PMLReadU32LE(AStream);    // 予約
  DataOffset := PMLReadU32LE(AStream);

  HeaderSize := PMLReadU32LE(AStream);
  RMask := 0; GMask := 0; BMask := 0; AMask := 0;
  HaveMasks := False;
  ClrUsed := 0;
  Compress := BI_RGB;

  if HeaderSize = 12 then
  begin
    // BITMAPCOREHEADER。幅と高さが 16 ビット。
    W := PMLReadU16LE(AStream);
    H := SmallInt(PMLReadU16LE(AStream));
    PMLReadU16LE(AStream);              // プレーン数
    Bits := PMLReadU16LE(AStream);
  end
  else if HeaderSize >= 40 then
  begin
    W := PMLReadS32LE(AStream);
    H := PMLReadS32LE(AStream);
    PMLReadU16LE(AStream);              // プレーン数
    Bits := PMLReadU16LE(AStream);
    Compress := PMLReadU32LE(AStream);
    PMLReadU32LE(AStream);              // 画像の大きさ
    PMLReadU32LE(AStream);              // 横解像度
    PMLReadU32LE(AStream);              // 縦解像度
    ClrUsed := PMLReadU32LE(AStream);
    PMLReadU32LE(AStream);              // 重要な色数

    // 64 は OS/2 2.x の別物。追加部分は読まずに飛ばす。
    if HeaderSize <> 64 then
    begin
      if Compress = BI_BITFIELDS then
      begin
        // マスクは v2 以降のヘッダ内、または v1 の直後（bmiColors の位置）。
        // どちらでもバイト位置は同じ。
        HaveMasks := True;
        RMask := PMLReadU32LE(AStream);
        GMask := PMLReadU32LE(AStream);
        BMask := PMLReadU32LE(AStream);
        if HeaderSize >= 56 then
          AMask := PMLReadU32LE(AStream);
      end
      else
      begin
        if HeaderSize >= 52 then
        begin
          PMLReadU32LE(AStream);
          PMLReadU32LE(AStream);
          PMLReadU32LE(AStream);
        end;
        if HeaderSize >= 56 then
          PMLReadU32LE(AStream);
      end;
    end;

    // 扱わなかったヘッダの残りを飛ばす。
    Consumed := AStream.Position - (Base + FILE_HEADER_SIZE);
    if Int64(HeaderSize) > Consumed then
      AStream.Seek(Int64(HeaderSize) - Consumed, soCurrent);
  end
  else
    raise EPMLIOError.CreateFmt('unsupported BMP header size %d', [HeaderSize]);

  if (Compress = BI_RLE4) or (Compress = BI_RLE8) then
    raise EPMLUnsupported.Create('RLE compressed BMP is not supported');
  if (W <= 0) or (H = 0) then
    raise EPMLIOError.CreateFmt('BMP has bad dimensions (%d x %d)', [W, H]);

  TopDown := H < 0;
  if TopDown then
    H := -H;

  Fmt := FormatFor(Bits, HaveMasks, RMask, GMask, BMask, AMask);
  if Fmt = PML_PIXELFORMAT_UNKNOWN then
    raise EPMLUnsupported.CreateFmt('unsupported BMP bit depth %d', [Bits]);

  // パレット。色数が書かれていなければビット数から求める。
  if Bits <= 8 then
  begin
    PaletteN := Integer(ClrUsed);
    if PaletteN <= 0 then
      PaletteN := 1 shl Bits;
    Pal := ReadPalette(AStream, PaletteN, HeaderSize = 12);
  end;

  try
    Result := TPMLSurface.Create(W, H, Fmt);
    if Pal <> nil then
    begin
      Result.SetPalette(Pal, True);
      Pal := nil;    // 所有権はサーフェスへ移った
    end;

    // 画素の開始位置はヘッダの値に従う。ここまでの読み取り位置とは限らない。
    AStream.Position := Base + Int64(DataOffset);

    // BMP の行は 4 バイト境界へ揃う。サーフェスのピッチとは別に計算する。
    SrcPitch := ((W * Bits + 31) div 32) * 4;
    SetLength(Row, SrcPitch);

    for Y := 0 to H - 1 do
    begin
      PMLReadExactly(AStream, Row[0], SrcPitch);
      if TopDown then
        DstY := Y
      else
        DstY := H - 1 - Y;

      if Bits <= 8 then
        ExpandIndexedRow(Result, DstY, Row, Bits)
      else
        // 16 / 24 / 32 ビットはバイト列がそのまま画素値になる。
        for X := 0 to W - 1 do
          Move(Row[X * (Bits div 8)],
               (PByte(Result.Pixels) + PtrUInt(DstY) * PtrUInt(Result.Pitch)
                + PtrUInt(X) * PtrUInt(Bits div 8))^,
               Bits div 8);
    end;
  except
    Pal.Free;
    FreeAndNil(Result);
    raise;
  end;
end;

function PMLLoadBMPFile(const APath: String): TPMLSurface;
var
  S: TPMLFileStream;
begin
  S := TPMLFileStream.Create(APath, TPMLFileMode.Read);
  try
    Result := PMLLoadBMP(S);
  finally
    S.Free;
  end;
end;

{ ---- 書き出し ---- }

{ BMP として書く。

  アルファを持つ形式なら 32 ビット BI_BITFIELDS（BITMAPV3INFOHEADER）、
  そうでなければ 24 ビット BI_RGB にする。24 ビットの方が古い閲覧ソフトでも
  開けるので、アルファが要らないなら使わない。

  PORT-NOTE: SDL_SaveBMP_IO と同じ使い分け。SDL はパレット付きサーフェスを
  8 ビットのまま書けるが、こちらは常に 24 / 32 ビットへ展開する。
  読み込み側がパレットを扱えるので往復はできる。 }
procedure PMLSaveBMP(AStream: TStream; ASurface: TPMLSurface);
var
  UseAlpha  : Boolean;
  BytesPP   : Integer;
  RowPitch  : Integer;
  HeaderSize: LongWord;
  DataOffset: LongWord;
  Y, X, I   : Integer;
  Row       : TBytes;
  C         : TPMLColor;
begin
  if ASurface = nil then
    raise EPMLArgument.Create('PMLSaveBMP needs a surface');

  UseAlpha := ASurface.Details.HasAlpha;
  if UseAlpha then
    BytesPP := 4
  else
    BytesPP := 3;
  RowPitch := ((ASurface.Width * BytesPP * 8 + 31) div 32) * 4;

  if UseAlpha then
    HeaderSize := 56    // BITMAPV3INFOHEADER。アルファマスクまで書く
  else
    HeaderSize := 40;   // BITMAPINFOHEADER
  DataOffset := FILE_HEADER_SIZE + HeaderSize;

  // ファイルヘッダ
  PMLWriteU16LE(AStream, $4D42);   // 'BM'
  PMLWriteU32LE(AStream, DataOffset + LongWord(RowPitch * ASurface.Height));
  PMLWriteU32LE(AStream, 0);
  PMLWriteU32LE(AStream, DataOffset);

  // 情報ヘッダ
  PMLWriteU32LE(AStream, HeaderSize);
  PMLWriteU32LE(AStream, LongWord(ASurface.Width));
  PMLWriteU32LE(AStream, LongWord(ASurface.Height));   // 正 = 下から上
  PMLWriteU16LE(AStream, 1);                           // プレーン数
  PMLWriteU16LE(AStream, Word(BytesPP * 8));
  if UseAlpha then
    PMLWriteU32LE(AStream, BI_BITFIELDS)
  else
    PMLWriteU32LE(AStream, BI_RGB);
  PMLWriteU32LE(AStream, LongWord(RowPitch * ASurface.Height));
  PMLWriteU32LE(AStream, 2835);    // 横解像度（72 dpi 相当）
  PMLWriteU32LE(AStream, 2835);    // 縦解像度
  PMLWriteU32LE(AStream, 0);       // 使った色数
  PMLWriteU32LE(AStream, 0);       // 重要な色数
  if UseAlpha then
  begin
    // BGRA の並び。読み込み側が逆引きできるマスクにする。
    PMLWriteU32LE(AStream, $00FF0000);
    PMLWriteU32LE(AStream, $0000FF00);
    PMLWriteU32LE(AStream, $000000FF);
    PMLWriteU32LE(AStream, $FF000000);
  end;

  // 画素。下から上へ書く。
  SetLength(Row, RowPitch);
  for Y := ASurface.Height - 1 downto 0 do
  begin
    for I := 0 to RowPitch - 1 do
      Row[I] := 0;
    for X := 0 to ASurface.Width - 1 do
    begin
      C := ASurface.ReadPixel(X, Y);
      // BMP はバイト順が B, G, R, A。
      Row[X * BytesPP + 0] := C.B;
      Row[X * BytesPP + 1] := C.G;
      Row[X * BytesPP + 2] := C.R;
      if UseAlpha then
        Row[X * BytesPP + 3] := C.A;
    end;
    PMLWriteExactly(AStream, Row[0], RowPitch);
  end;
end;

procedure PMLSaveBMPFile(const APath: String; ASurface: TPMLSurface);
var
  S: TPMLFileStream;
begin
  S := TPMLFileStream.Create(APath, TPMLFileMode.Write);
  try
    PMLSaveBMP(S, ASurface);
  finally
    S.Free;
  end;
end;

end.
