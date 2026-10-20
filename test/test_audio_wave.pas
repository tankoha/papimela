{
  test_audio_wave — WAV の読み込み（PMLLoadWAV）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 場面ごとに WAV のバイト列を組み立てて PMLLoadWAV に通し、成否・形式・チャンネル数・
       周波数・バイト数・出力の FNV-1a・読み終えたストリームの位置を表と比べる。場面は
       PCM（8 / 16 / 24 / 32 ビット）、IEEE float、A-law・μ-law、MS-ADPCM、IMA-ADPCM、
       拡張ヘッダ、fact、チャンクの並び・詰め物、壊れた RIFF の大きさ、切り詰め、
       ヒント 4 つ（RIFF の大きさ・切り詰め・fact・チャンクの数）の各値、断られる入力
    2. 表の入力の FNV-1a も持ち、組み立てが表を取った時から変わっていないことを確かめる
    3. ファイルから読む口（PMLLoadWAVFile）がストリームと同じ結果になる

  WHY:
    #54（SDL_wave.c の移植）の受け入れ検査。表示サーバも音の装置も要らない。
    期待値は参照版の SDL に同じバイト列を SDL_LoadWAV_IO で読ませて取った
    （docs/TEST-LOG.md の使い捨て検証）。`--write-cases <dir>` で場面を書き出せる。
    SDL の不具合で SDL の値を使えない場面は、表の注に D 番号を書き、papimela の期待値を
    手で求めた理由を添える。
}
program test_audio_wave;

{$mode objfpc}{$H+}
{$scopedenums on}
// LCG と FNV-1a は桁あふれで回り込ませる。-Cr -Co で作ってもユニットの側だけを検査する。
{$R-}{$Q-}

uses
  SysUtils, Classes,
  PaPiMeLa.Errors,
  PaPiMeLa.Properties,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Wave;

type
  TWaveCase = record
    Name  : String;
    Data  : TBytes;
    Offset: Integer;   // ストリームの読み始めの位置（前に余計なバイトを置く場面）
    Riff  : String;    // PML_HINT_WAVE_RIFF_CHUNK_SIZE（'' は置かない）
    Trunc : String;    // PML_HINT_WAVE_TRUNCATION
    Fact  : String;    // PML_HINT_WAVE_FACT_CHUNK
    Limit : String;    // PML_HINT_WAVE_CHUNK_LIMIT
  end;

  // Ok が False なら EPMLAudioError で断られる。それ以外の欄は Ok のときだけ見る。
  TWaveExpect = record
    InHash  : LongWord;
    Ok      : Boolean;
    Format  : Word;
    Channels: Integer;
    Freq    : Integer;
    Len     : Integer;
    Hash    : LongWord;
    EndPos  : Int64;
  end;

{$I test_audio_wave_expected.inc}

var
  Failures: Integer = 0;
  Lcg     : LongWord;
  Cases   : array of TWaveCase;

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

function Fnv(const A: TBytes): LongWord;
var
  I: Integer;
begin
  Result := 2166136261;
  for I := 0 to High(A) do
  begin
    Result := Result xor A[I];
    Result := Result * 16777619;
  end;
end;

{ ---- バイト列の組み立て ---- }

function B8(V: Byte): TBytes;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0] := V;
end;

function B16(V: Word): TBytes;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := Byte(V);
  Result[1] := Byte(V shr 8);
end;

function B32(V: LongWord): TBytes;
begin
  Result := nil;
  SetLength(Result, 4);
  Result[0] := Byte(V);
  Result[1] := Byte(V shr 8);
  Result[2] := Byte(V shr 16);
  Result[3] := Byte(V shr 24);
end;

function Id(const S: AnsiString): TBytes;
begin
  Result := nil;
  SetLength(Result, 4);
  Move(S[1], Result[0], 4);
end;

function Cat(const AParts: array of TBytes): TBytes;
var
  I, N: Integer;
begin
  Result := nil;
  N := 0;
  for I := 0 to High(AParts) do
    Inc(N, Length(AParts[I]));
  SetLength(Result, N);
  N := 0;
  for I := 0 to High(AParts) do
    if Length(AParts[I]) > 0 then
    begin
      Move(AParts[I][0], Result[N], Length(AParts[I]));
      Inc(N, Length(AParts[I]));
    end;
end;

function Head(const A: TBytes; ACount: Integer): TBytes;
begin
  Result := Copy(A, 0, ACount);
end;

// LCG のバイト。Lcg は続けて使う。
function Noise(ACount: Integer): TBytes;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
  begin
    Lcg := Lcg * 1103515245 + 12345;
    Result[I] := Byte(Lcg shr 16);
  end;
end;

function Rnd(AMod: LongWord): LongWord;
begin
  Lcg := Lcg * 1103515245 + 12345;
  Result := (Lcg shr 16) mod AMod;
end;

// 宣言する長さ ALen のチャンク。中身が奇数の長さなら詰め物の 1 バイトを足す。
function ChunkLen(const AId: AnsiString; const APayload: TBytes; ALen: LongWord): TBytes;
begin
  if Odd(Length(APayload)) then
    Result := Cat([Id(AId), B32(ALen), APayload, B8(0)])
  else
    Result := Cat([Id(AId), B32(ALen), APayload]);
end;

function Chunk(const AId: AnsiString; const APayload: TBytes): TBytes;
begin
  Result := ChunkLen(AId, APayload, Length(APayload));
end;

function RiffLen(const ABody: TBytes; ALen: LongWord): TBytes;
begin
  Result := Cat([Id('RIFF'), B32(ALen), Id('WAVE'), ABody]);
end;

function Riff(const ABody: TBytes): TBytes;
begin
  Result := RiffLen(ABody, 4 + Length(ABody));
end;

function Fmt16(ATag, ACh: Word; AFreq: LongWord; AAlign, ABits: Word): TBytes;
begin
  Result := Cat([B16(ATag), B16(ACh), B32(AFreq), B32(AFreq * AAlign), B16(AAlign), B16(ABits)]);
end;

function FmtExt(ATag, ACh: Word; AFreq: LongWord; AAlign, ABits: Word; const AExtra: TBytes): TBytes;
begin
  Result := Cat([Fmt16(ATag, ACh, AFreq, AAlign, ABits), B16(Length(AExtra)), AExtra]);
end;

function Guid(ATag: Word): TBytes;
const
  Tail: array[0..13] of Byte = (0, 0, 0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113);
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, 16);
  Result[0] := Byte(ATag);
  Result[1] := Byte(ATag shr 8);
  for I := 0 to 13 do
    Result[I + 2] := Tail[I];
end;

function Extensible(ACh: Word; AFreq: LongWord; AAlign, ABits, AValid: Word;
  const AGuid: TBytes): TBytes;
begin
  Result := FmtExt($FFFE, ACh, AFreq, AAlign, ABits,
    Cat([B16(AValid), B32(3), AGuid]));
end;

function Wav(const AFmt, AData: TBytes): TBytes;
begin
  Result := Riff(Cat([Chunk('fmt ', AFmt), Chunk('data', AData)]));
end;

function WavFact(const AFmt: TBytes; AFact: LongWord; const AData: TBytes): TBytes;
begin
  Result := Riff(Cat([Chunk('fmt ', AFmt), Chunk('fact', B32(AFact)), Chunk('data', AData)]));
end;

const
  MsPreset: array[0..13] of SmallInt = (256, 0, 512, -256, 0, 0, 192, 64, 240, 0, 460, -208, 392, -232);

// MS-ADPCM の fmt の追加部分（wSamplesPerBlock、wNumCoef、係数の組）。
function MsExtra(ASpb: Word; const ACoeffs: array of SmallInt): TBytes;
var
  I: Integer;
begin
  Result := Cat([B16(ASpb), B16(Length(ACoeffs) div 2)]);
  for I := 0 to High(ACoeffs) do
    Result := Cat([Result, B16(Word(ACoeffs[I]))]);
end;

function MsPresetExtra(ASpb: Word): TBytes;
begin
  Result := MsExtra(ASpb, MsPreset);
end;

{ MS-ADPCM のブロック。ABlocks 個の完全なブロックの後に ATrail バイトの半端なブロック。
  見出しの予測の番号は 0..ACoeffs-1 の乱数、差分の大きさと標本は乱数、中身は乱数。 }
function MsBlocks(ACh, AAlign, ABlocks, ATrail, ACoeffs: Integer): TBytes;
var
  B, C, N: Integer;
  Blk: TBytes;
begin
  Result := nil;
  for B := 0 to ABlocks do
  begin
    if B < ABlocks then
      N := AAlign
    else
      N := ATrail;
    if N = 0 then
      Break;
    Blk := Noise(AAlign);
    for C := 0 to ACh - 1 do
      Blk[C] := Byte(Rnd(ACoeffs));
    Result := Cat([Result, Head(Blk, N)]);
  end;
end;

// IMA-ADPCM のブロック。見出しの段の番号も予約のバイトも乱数のまま（挟みと読み捨てを通す）。
function ImaBlocks(AAlign, ABlocks, ATrail: Integer): TBytes;
begin
  Result := Noise(AAlign * ABlocks + ATrail);
end;

procedure Add(const AName: String; const AData: TBytes; const ARiff: String = '';
  const ATrunc: String = ''; const AFact: String = ''; const ALimit: String = '';
  AOffset: Integer = 0);
var
  N: Integer;
begin
  N := Length(Cases);
  SetLength(Cases, N + 1);
  Cases[N].Name := AName;
  Cases[N].Data := AData;
  Cases[N].Offset := AOffset;
  Cases[N].Riff := ARiff;
  Cases[N].Trunc := ATrunc;
  Cases[N].Fact := AFact;
  Cases[N].Limit := ALimit;
end;

const
  RiffHints: array[0..4] of String = ('', 'force', 'ignorezero', 'ignore', 'maximum');

{ 場面。番号は表の番号。足すときは末尾に足す（表の行がずれないように）。 }
procedure BuildCases;
var
  D, F, Body: TBytes;
  I: Integer;
begin
  Lcg := 20261020;
  Cases := nil;

  // ---- PCM ----
  Add('0: U8 mono 8000', Wav(Fmt16(1, 1, 8000, 1, 8), Noise(101)));
  Add('1: S16 stereo 44100', Wav(Fmt16(1, 2, 44100, 4, 16), Noise(400)));
  Add('2: S24 stereo -> S32', Wav(Fmt16(1, 2, 48000, 6, 24), Noise(360)));
  Add('3: S32 mono', Wav(Fmt16(1, 1, 96000, 4, 32), Noise(256)));
  Add('4: F32 stereo', Wav(Fmt16(3, 2, 22050, 8, 32), Noise(320)));
  Add('5: F64 (rejected)', Wav(Fmt16(3, 1, 22050, 8, 64), Noise(64)));
  Add('6: PCM 12-bit (rejected)', Wav(Fmt16(1, 1, 8000, 2, 12), Noise(64)));
  D := Noise(402);
  Add('7: S16 stereo, half frame left over', Wav(Fmt16(1, 2, 44100, 4, 16), D));
  Add('8: same, truncation=strict', Wav(Fmt16(1, 2, 44100, 4, 16), D), '', 'strict');
  Add('9: same, truncation=verystrict', Wav(Fmt16(1, 2, 44100, 4, 16), D), '', 'verystrict');
  // data の長さが 1000 と言いながら 998 バイトでファイルが終わる。
  Body := Riff(Cat([Chunk('fmt ', Fmt16(1, 2, 44100, 4, 16)), Id('data'), B32(1000), Noise(998)]));
  Add('10: data longer than file', Body);
  Add('11: same, truncation=strict', Body, '', 'strict');
  Add('12: same, truncation=dropframe', Body, '', 'dropframe');
  Add('13: extensible PCM S16', Wav(Extensible(2, 32000, 4, 16, 16, Guid(1)), Noise(200)));
  Add('14: extensible float', Wav(Extensible(1, 32000, 4, 32, 32, Guid(3)), Noise(200)));
  Add('15: extensible unknown GUID', Wav(Extensible(1, 32000, 4, 32, 32, Guid($55)), Noise(200)));
  Add('16: extensible too small', Wav(FmtExt($FFFE, 1, 8000, 2, 16, Noise(10)), Noise(20)));
  Add('17: block align 0 (forced to 1)', Wav(Fmt16(1, 1, 8000, 0, 16), Noise(51)));
  Add('18: channels 0', Wav(Fmt16(1, 0, 8000, 2, 16), Noise(20)));
  Add('19: frequency 0', Wav(Fmt16(1, 1, 0, 2, 16), Noise(20)));
  Add('20: frequency over INT_MAX', Wav(Fmt16(1, 1, $80000000, 2, 16), Noise(20)));
  Add('21: fmt of 14 bytes, PCM', Wav(Head(Fmt16(1, 1, 8000, 2, 16), 14), Noise(20)));
  Add('22: fmt of 14 bytes, A-law', Wav(Head(Fmt16(6, 1, 8000, 1, 8), 14), Noise(20)));
  Add('23: fmt of 12 bytes', Wav(Head(Fmt16(1, 1, 8000, 2, 16), 12), Noise(20)));
  Add('24: MPEG tag', Wav(Fmt16($50, 1, 8000, 2, 16), Noise(20)));
  Add('25: unknown tag', Wav(Fmt16($1234, 1, 8000, 2, 16), Noise(20)));
  Add('26: bits per sample 0', Wav(Fmt16(1, 1, 8000, 2, 0), Noise(20)));

  // ---- チャンクの並び ----
  F := Fmt16(1, 1, 8000, 1, 8);
  Add('27: fmt after data', Riff(Cat([Chunk('data', Noise(20)), Chunk('fmt ', F)])));
  Add('28: no fmt', Riff(Chunk('data', Noise(20))));
  Add('29: no data', Riff(Chunk('fmt ', F)));
  Add('30: odd JUNK and LIST around, odd data', Riff(Cat([Chunk('JUNK', Noise(7)),
    Chunk('fmt ', F), Chunk('LIST', Noise(9)), Chunk('data', Noise(33)), Chunk('JUNK', Noise(3))])));
  Add('31: two fmt and two data (first ones)', Riff(Cat([Chunk('fmt ', F),
    Chunk('fmt ', Fmt16(1, 2, 44100, 4, 16)), Chunk('data', Noise(30)), Chunk('data', Noise(40))])));
  Add('32: WAVE without RIFF', Cat([Id('WAVE'), Chunk('fmt ', F), Chunk('data', Noise(20))]));
  Add('33: not RIFF', Cat([Id('RIFX'), B32(100), Id('WAVE'), Chunk('fmt ', F), Chunk('data', Noise(20))]));
  Add('34: RIFF but not WAVE', Cat([Id('RIFF'), B32(100), Id('AVI '), Chunk('fmt ', F), Chunk('data', Noise(20))]));
  Add('35: prefix bytes, trailing bytes', Cat([Noise(13), Wav(F, Noise(21)), Noise(17)]), '', '', '', '', 13);
  Add('36: trailing bytes after RIFF', Cat([Wav(F, Noise(24)), Noise(40)]));

  // ---- RIFF の大きさ ----
  Body := Cat([Chunk('fmt ', F), Chunk('JUNK', Noise(64)), Chunk('data', Noise(48))]);
  for I := 0 to 4 do
    Add(Format('%d: RIFF size short of data, riff=%s', [37 + I, RiffHints[I]]),
      RiffLen(Body, 40), RiffHints[I]);
  Add('42: RIFF size 0, default', RiffLen(Body, 0));
  Add('43: RIFF size 0, riff=force', RiffLen(Body, 0), 'force');
  Add('44: RIFF size 0, riff=maximum', RiffLen(Body, 0), 'maximum');
  Add('45: RIFF size cuts data, verystrict', RiffLen(Body, 4 + Length(Body) - 10), '', 'verystrict');
  Add('46: chunk limit 2', Riff(Cat([Chunk('JUNK', Noise(4)), Chunk('fmt ', F), Chunk('data', Noise(8))])),
    '', '', '', '2');
  Add('47: chunk limit 3', Riff(Cat([Chunk('JUNK', Noise(4)), Chunk('fmt ', F), Chunk('data', Noise(8))])),
    '', '', '', '3');
  Add('48: chunk limit not a number', Riff(Cat([Chunk('JUNK', Noise(4)), Chunk('fmt ', F), Chunk('data', Noise(8))])),
    '', '', '', 'abc');
  Add('49: chunk limit "2x"', Riff(Cat([Chunk('JUNK', Noise(4)), Chunk('fmt ', F), Chunk('data', Noise(8))])),
    '', '', '', '2x');

  // ---- A-law / μ-law ----
  D := nil;
  SetLength(D, 256);
  for I := 0 to 255 do
    D[I] := I;
  Add('50: A-law every value', Wav(Fmt16(6, 1, 8000, 1, 8), D));
  Add('51: mu-law every value', Wav(Fmt16(7, 1, 8000, 1, 8), D));
  Add('52: A-law stereo', Wav(Fmt16(6, 2, 8000, 2, 8), Noise(101)));
  Add('53: A-law 16 bits (rejected)', Wav(Fmt16(6, 1, 8000, 2, 16), Noise(20)));
  Add('54: mu-law align 2 mono (rejected)', Wav(Fmt16(7, 1, 8000, 2, 8), Noise(20)));
  Add('55: extensible mu-law', Wav(Extensible(1, 8000, 1, 8, 8, Guid(7)), Noise(31)));

  // ---- fact ----
  F := Fmt16(6, 1, 8000, 1, 8);
  D := Noise(100);
  Add('56: fact 60, default (ignored)', WavFact(F, 60, D));
  Add('57: fact 60, fact=truncate', WavFact(F, 60, D), '', '', 'truncate');
  Add('58: fact 60, fact=strict', WavFact(F, 60, D), '', '', 'strict');
  Add('59: fact 150, fact=truncate', WavFact(F, 150, D), '', '', 'truncate');
  Add('60: fact 150, fact=strict', WavFact(F, 150, D), '', '', 'strict');
  Add('61: fact 0, fact=ignorezero', WavFact(F, 0, D), '', '', 'ignorezero');
  Add('62: fact 0, fact=truncate', WavFact(F, 0, D), '', '', 'truncate');
  Add('63: fact 60, fact=ignore', WavFact(F, 60, D), '', '', 'ignore');
  Add('64: no fact, fact=strict', Wav(F, D), '', '', 'strict');
  Add('65: fact of 2 bytes, fact=strict', Riff(Cat([Chunk('fmt ', F), Chunk('fact', B16(60)), Chunk('data', D)])),
    '', '', 'strict');
  Add('66: fact after data, fact=truncate', Riff(Cat([Chunk('fmt ', F), Chunk('data', D), Chunk('fact', B32(40))])),
    '', '', 'truncate');
  Add('67: fact after data, default', Riff(Cat([Chunk('fmt ', F), Chunk('data', D), Chunk('fact', B32(40))])));
  Add('68: PCM with fact 10, fact=truncate', WavFact(Fmt16(1, 1, 8000, 2, 16), 10, Noise(100)), '', '', 'truncate');

  // ---- MS-ADPCM（モノは 64 バイトで 116 フレーム、ステレオは 128 バイトで 116 フレーム） ----
  Add('69: MS-ADPCM mono 3 blocks', Wav(FmtExt(2, 1, 22050, 64, 4, MsPresetExtra(116)), MsBlocks(1, 64, 3, 0, 7)));
  Add('70: MS-ADPCM stereo 2 blocks', Wav(FmtExt(2, 2, 22050, 128, 4, MsPresetExtra(116)), MsBlocks(2, 128, 2, 0, 7)));
  D := MsBlocks(2, 128, 2, 41, 7);
  F := FmtExt(2, 2, 22050, 128, 4, MsPresetExtra(116));
  Add('71: MS-ADPCM stereo, short last block, default', Wav(F, D));
  Add('72: same, truncation=dropframe', Wav(F, D), '', 'dropframe');
  Add('73: same, truncation=dropblock', Wav(F, D), '', 'dropblock');
  Add('74: same, truncation=strict', Wav(F, D), '', 'strict');
  Add('75: MS-ADPCM, last block shorter than header, dropframe', Wav(F, MsBlocks(2, 128, 2, 10, 7)), '', 'dropframe');
  Add('76: MS-ADPCM samples per block 0 (computed)', Wav(FmtExt(2, 1, 22050, 64, 4, MsPresetExtra(0)), MsBlocks(1, 64, 2, 0, 7)));
  Add('77: MS-ADPCM fewer samples per block than fit', Wav(FmtExt(2, 1, 22050, 64, 4, MsPresetExtra(100)), MsBlocks(1, 64, 2, 0, 7)));
  Add('78: MS-ADPCM more samples per block than fit', Wav(FmtExt(2, 1, 22050, 64, 4, MsPresetExtra(117)), MsBlocks(1, 64, 2, 0, 7)));
  Add('79: MS-ADPCM samples per block 1', Wav(FmtExt(2, 1, 22050, 64, 4, MsPresetExtra(1)), MsBlocks(1, 64, 2, 0, 7)));
  Add('80: MS-ADPCM 9 coefficients, index up to 8',
    Wav(FmtExt(2, 1, 22050, 64, 4, MsExtra(116, [256, 0, 512, -256, 0, 0, 192, 64, 240, 0, 460, -208, 392, -232, 1000, -700, -300, 900])),
    MsBlocks(1, 64, 4, 0, 9)));
  Add('81: MS-ADPCM wrong preset', Wav(FmtExt(2, 1, 22050, 64, 4, MsExtra(116, [256, 0, 512, -256, 0, 0, 192, 64, 240, 0, 460, -208, 392, -231])), MsBlocks(1, 64, 1, 0, 7)));
  Add('82: MS-ADPCM 6 coefficients', Wav(FmtExt(2, 1, 22050, 64, 4, MsExtra(116, [256, 0, 512, -256, 0, 0, 192, 64, 240, 0, 460, -208])), MsBlocks(1, 64, 1, 0, 6)));
  Add('83: MS-ADPCM 3 channels', Wav(FmtExt(2, 3, 22050, 192, 4, MsPresetExtra(116)), Noise(192)));
  Add('84: MS-ADPCM 3 bits', Wav(FmtExt(2, 1, 22050, 64, 3, MsPresetExtra(116)), MsBlocks(1, 64, 1, 0, 7)));
  Add('85: MS-ADPCM block smaller than header', Wav(FmtExt(2, 2, 22050, 12, 4, MsPresetExtra(2)), Noise(24)));
  Add('86: MS-ADPCM extensible', Wav(Extensible(1, 22050, 64, 4, 116, Guid(2)), MsBlocks(1, 64, 1, 0, 7)));
  Add('87: MS-ADPCM extsize says less than coefficients',
    Wav(Cat([Fmt16(2, 1, 22050, 64, 4), B16(20), MsPresetExtra(116)]), MsBlocks(1, 64, 1, 0, 7)));
  Add('88: MS-ADPCM fmt cut inside coefficients', Wav(Head(FmtExt(2, 1, 22050, 64, 4, MsPresetExtra(116)), 40), MsBlocks(1, 64, 1, 0, 7)));
  // 予測の番号に 200（係数の数より大きい。SDL も断る）。
  D := MsBlocks(1, 64, 2, 0, 7);
  D[64] := 200;
  Add('89: MS-ADPCM predictor index 200', Wav(FmtExt(2, 1, 22050, 64, 4, MsPresetExtra(116)), D));
  // 予測の番号がちょうど係数の数（7）。D-73 を見よ。
  D := MsBlocks(1, 64, 2, 0, 7);
  D[64] := 7;
  Add('90: MS-ADPCM predictor index = coefficient count', Wav(FmtExt(2, 1, 22050, 64, 4, MsPresetExtra(116)), D));
  F := FmtExt(2, 1, 22050, 64, 4, MsPresetExtra(116));
  D := MsBlocks(1, 64, 3, 0, 7);
  Add('91: MS-ADPCM mono fact 233 (one frame into the last block), truncate', WavFact(F, 233, D), '', '', 'truncate');
  Add('92: MS-ADPCM mono fact 234, truncate', WavFact(F, 234, D), '', '', 'truncate');
  Add('93: MS-ADPCM mono fact 1, truncate', WavFact(F, 1, D), '', '', 'truncate');
  Add('94: MS-ADPCM stereo fact 117, truncate',
    WavFact(FmtExt(2, 2, 22050, 128, 4, MsPresetExtra(116)), 117, MsBlocks(2, 128, 2, 0, 7)), '', '', 'truncate');
  Add('95: MS-ADPCM mono fact 150, truncate', WavFact(F, 150, D), '', '', 'truncate');

  // ---- IMA-ADPCM（モノは 64 バイトで 121 フレーム、ステレオは 128 バイトで 121 フレーム） ----
  Add('96: IMA mono 4 blocks', Wav(FmtExt($11, 1, 22050, 64, 4, B16(121)), ImaBlocks(64, 4, 0)));
  Add('97: IMA stereo 3 blocks', Wav(FmtExt($11, 2, 22050, 128, 4, B16(121)), ImaBlocks(128, 3, 0)));
  F := FmtExt($11, 2, 22050, 128, 4, B16(121));
  D := ImaBlocks(128, 2, 8 + 22);
  Add('98: IMA stereo, short last block (2 sub-blocks + 6 bytes), default', Wav(F, D));
  Add('99: same, truncation=dropframe', Wav(F, D), '', 'dropframe');
  Add('100: same, truncation=strict', Wav(F, D), '', 'strict');
  D := ImaBlocks(128, 2, 8 + 20);
  Add('101: IMA stereo, short last block (2 sub-blocks + 4 bytes), dropframe', Wav(F, D), '', 'dropframe');
  D := ImaBlocks(128, 2, 7);
  Add('102: IMA stereo, last block cuts header, dropframe', Wav(F, D), '', 'dropframe');
  D := ImaBlocks(128, 2, 3);
  Add('103: IMA stereo, last block shorter than header - 2, dropframe', Wav(F, D), '', 'dropframe');
  D := ImaBlocks(128, 2, 0);
  Add('104: IMA stereo fact 126, truncate', WavFact(F, 126, D), '', '', 'truncate');
  Add('105: IMA stereo fact 122, truncate', WavFact(F, 122, D), '', '', 'truncate');
  Add('106: IMA mono fact 126, truncate', WavFact(FmtExt($11, 1, 22050, 64, 4, B16(121)), 126, ImaBlocks(64, 2, 0)), '', '', 'truncate');
  Add('107: IMA extensible (samples per block from wValidBitsPerSample)',
    Wav(Extensible(2, 22050, 128, 4, 121, Guid($11)), ImaBlocks(128, 2, 0)));
  Add('108: IMA samples per block 0 (computed)', Wav(FmtExt($11, 1, 22050, 64, 4, B16(0)), ImaBlocks(64, 2, 0)));
  Add('109: IMA no extra (computed)', Wav(Fmt16($11, 1, 22050, 64, 4), ImaBlocks(64, 2, 0)));
  Add('110: IMA 3 bits', Wav(FmtExt($11, 1, 22050, 64, 3, B16(121)), ImaBlocks(64, 1, 0)));
  Add('111: IMA 5 bits', Wav(FmtExt($11, 1, 22050, 64, 5, B16(121)), ImaBlocks(64, 1, 0)));
  Add('112: IMA block not a multiple of 4', Wav(FmtExt($11, 1, 22050, 62, 4, B16(117)), ImaBlocks(62, 1, 0)));
  Add('113: IMA more samples per block than fit', Wav(FmtExt($11, 1, 22050, 64, 4, B16(122)), ImaBlocks(64, 1, 0)));
  Add('114: IMA 4 channels', Wav(FmtExt($11, 4, 22050, 256, 4, B16(121)), ImaBlocks(256, 2, 0)));
  Add('115: IMA block smaller than header', Wav(FmtExt($11, 2, 22050, 4, 4, B16(1)), ImaBlocks(4, 2, 0)));
  // 32 と同じ中身を、前に 9 バイトを置いて読む。D-77 を見よ。
  Add('116: WAVE without RIFF after prefix bytes', Cat([Noise(9), Cases[32].Data]), '', '', '', '', 9);
  // 24 ビットで nBlockAlign がフレームより小さい（SDL は通す）。119 は同じ中身の正しい nBlockAlign。D-79 を見よ。
  D := Noise(60);
  Add('117: S24 stereo, block align 3', Wav(Fmt16(1, 2, 48000, 3, 24), D));
  Add('118: S24 stereo, block align 1', Wav(Fmt16(1, 2, 48000, 1, 24), D));
  Add('119: S24 stereo, block align 6 (same data as 117)', Wav(Fmt16(1, 2, 48000, 6, 24), D));
  // 最後のブロックが短く（見出しと部分ブロック 1 つと 7 バイト。14 フレーム取れる）、fact はそのうち 9 フレームだけ求める。
  // 数え直した数を求めた数で抑えないと、出力の置き場の外へ書く。
  Add('120: IMA stereo, short last block and fact inside it, dropframe + truncate',
    WavFact(FmtExt($11, 2, 22050, 128, 4, B16(121)), 252, ImaBlocks(128, 2, 8 + 8 + 7)), '', 'dropframe', 'truncate');
  // RIFF の大きさがファイルより 100 バイト大きい。読み終えた位置はファイルの終わりで止まる。
  Body := Cat([Chunk('fmt ', Fmt16(1, 1, 8000, 1, 8)), Chunk('data', Noise(30))]);
  Add('121: RIFF size beyond the end of the file', RiffLen(Body, 4 + Length(Body) + 100));
  // MS-ADPCM の差分の大きさが下限（16）に張り付く: 見出しの差分 16、中身はニブル 1 だけ（係数 230 で縮む）。
  D := MsBlocks(1, 64, 1, 0, 7);
  D[1] := 16;
  D[2] := 0;
  for I := 7 to 63 do
    D[I] := $11;
  Add('122: MS-ADPCM delta held at the floor', Wav(FmtExt(2, 1, 22050, 64, 4, MsPresetExtra(116)), D));
  // 120 と同じ形で、fact は最後のブロックの見出しの次の 1 フレームだけを求める（見出しの後ろは 7 バイト）。D-80 を見よ。
  Add('123: IMA stereo, fact wants 1 frame of a short last block, dropframe + truncate',
    WavFact(FmtExt($11, 2, 22050, 128, 4, B16(121)), 244, ImaBlocks(128, 2, 8 + 7)), '', 'dropframe', 'truncate');
end;

{ ---- 書き出し（期待値を取るため） ---- }

procedure WriteCases(const ADir: String);
var
  I: Integer;
  S: TFileStream;
  M: TStringList;
  function Hint(const V: String): String;
  begin
    if V = '' then
      Result := '-'
    else
      Result := V;
  end;
begin
  ForceDirectories(ADir);
  M := TStringList.Create;
  try
    for I := 0 to High(Cases) do
    begin
      S := TFileStream.Create(Format('%s/%.3d.wav', [ADir, I]), fmCreate);
      try
        if Length(Cases[I].Data) > 0 then
          S.WriteBuffer(Cases[I].Data[0], Length(Cases[I].Data));
      finally
        S.Free;
      end;
      M.Add(Format('%.3d %d %s %s %s %s', [I, Cases[I].Offset, Hint(Cases[I].Riff),
        Hint(Cases[I].Trunc), Hint(Cases[I].Fact), Hint(Cases[I].Limit)]));
    end;
    M.SaveToFile(ADir + '/manifest.txt');
  finally
    M.Free;
  end;
  WriteLn(Length(Cases), ' cases written to ', ADir);
end;

{ ---- 流す ---- }

function MakeHints(const C: TWaveCase): TPMLHints;
begin
  // 何も置かない場面は nil で渡す（nil を受けられることも見る）。
  if (C.Riff = '') and (C.Trunc = '') and (C.Fact = '') and (C.Limit = '') then
    Exit(nil);
  Result := TPMLHints.Create;
  if C.Riff <> '' then
    Result.SetHint(PML_HINT_WAVE_RIFF_CHUNK_SIZE, C.Riff);
  if C.Trunc <> '' then
    Result.SetHint(PML_HINT_WAVE_TRUNCATION, C.Trunc);
  if C.Fact <> '' then
    Result.SetHint(PML_HINT_WAVE_FACT_CHUNK, C.Fact);
  if C.Limit <> '' then
    Result.SetHint(PML_HINT_WAVE_CHUNK_LIMIT, C.Limit);
end;

procedure RunCase(AIndex: Integer);
var
  C: TWaveCase;
  E: TWaveExpect;
  S: TBytesStream;
  H: TPMLHints;
  Spec: TPMLAudioSpec;
  Got: TBytes;
  Ok, Same: Boolean;
  Msg, Detail: String;
begin
  C := Cases[AIndex];
  E := WaveExpected[AIndex];
  Got := nil;
  Spec := Default(TPMLAudioSpec);
  Msg := '';
  S := TBytesStream.Create(C.Data);
  H := MakeHints(C);
  try
    S.Position := C.Offset;
    try
      Got := PMLLoadWAV(S, Spec, H);
      Ok := True;
    except
      on X: EPMLAudioError do
      begin
        Ok := False;
        Msg := X.Message;
      end;
    end;
    if Fnv(C.Data) <> E.InHash then
    begin
      Check(False, Format('%s: 入力が表を取った時と違う（%.8x、表は %.8x）', [C.Name, Fnv(C.Data), E.InHash]));
      Exit;
    end;
    if not E.Ok then
    begin
      Check(not Ok, Format('%s: 断られる（%s）', [C.Name, Msg]));
      Exit;
    end;
    Same := Ok and (Spec.Format = E.Format) and (Spec.Channels = E.Channels) and
      (Spec.Freq = E.Freq) and (Length(Got) = E.Len) and (Fnv(Got) = E.Hash) and
      (S.Position = E.EndPos);
    if Ok then
      Detail := Format('fmt=$%.4x ch=%d freq=%d len=%d hash=%.8x pos=%d',
        [Word(Spec.Format), Spec.Channels, Spec.Freq, Length(Got), Fnv(Got), S.Position])
    else
      Detail := 'raised: ' + Msg;
    if Same then
      Check(True, Format('%s: %s', [C.Name, Detail]))
    else
      Check(False, Format('%s: %s（表は fmt=$%.4x ch=%d freq=%d len=%d hash=%.8x pos=%d）',
        [C.Name, Detail, E.Format, E.Channels, E.Freq, E.Len, E.Hash, E.EndPos]));
  finally
    H.Free;
    S.Free;
  end;
end;

procedure TestCases;
var
  I: Integer;
begin
  WriteLn('1. 場面を SDL の値と比べる');
  Check(Length(Cases) = Length(WaveExpected), Format('場面の数 %d が表の行の数 %d と同じ',
    [Length(Cases), Length(WaveExpected)]));
  if Length(Cases) <> Length(WaveExpected) then
    Exit;
  for I := 0 to High(Cases) do
    RunCase(I);
end;

procedure TestFile;
var
  Path: String;
  S: TBytesStream;
  Spec1, Spec2: TPMLAudioSpec;
  A, B: TBytes;
  Raised: Boolean;
begin
  WriteLn('2. ファイルから読む');
  Path := GetTempDir(False) + 'papimela_test_audio_wave.wav';
  S := TBytesStream.Create(Cases[97].Data);
  try
    S.SaveToFile(Path);
    S.Position := 0;
    A := PMLLoadWAV(S, Spec1);
  finally
    S.Free;
  end;
  try
    B := PMLLoadWAVFile(Path, Spec2);
    Check((Spec1.Format = Spec2.Format) and (Spec1.Channels = Spec2.Channels) and
      (Spec1.Freq = Spec2.Freq) and (Length(A) = Length(B)) and (Fnv(A) = Fnv(B)) and (Length(A) > 0),
      'PMLLoadWAVFile がストリームと同じ形式とバイト列を返す');
  finally
    DeleteFile(Path);
  end;
  Raised := False;
  try
    PMLLoadWAVFile(Path, Spec2);
  except
    on EPMLError do
      Raised := True;
  end;
  Check(Raised, '無いファイルは EPMLError');
end;

procedure Guard(AProc: TProcedure);
begin
  try
    AProc();
  except
    on X: Exception do
    begin
      WriteLn('  [FAIL] 例外 ', X.ClassName, ': ', X.Message);
      Inc(Failures);
    end;
  end;
end;

begin
  BuildCases;
  if (ParamCount = 2) and (ParamStr(1) = '--write-cases') then
  begin
    WriteCases(ParamStr(2));
    Exit;
  end;
  WriteLn('test_audio_wave — WAV の読み込み');
  WriteLn;
  Guard(@TestCases);
  WriteLn;
  Guard(@TestFile);
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: WAV の読み込みが SDL と同じ値を出す ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
