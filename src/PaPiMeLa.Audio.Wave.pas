{
  PaPiMeLa.Audio.Wave — WAVE ファイルの読み込み（SDL_LoadWAV）

  Origin : ported from SDL (src/audio/SDL_wave.c, src/audio/SDL_wave.h)
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.5、§11 #54

  WHAT:
    TStream の WAVE ファイルを読み、形式・チャンネル数・周波数と標本のバイト列を返す。
    PCM（8 / 16 / 24 / 32 ビット。24 ビットは 32 ビットに広げる）、IEEE 浮動小数（32 ビット）、
    A-law / μ-law（16 ビットに広げる）、MS ADPCM、IMA ADPCM（どちらも 16 ビットに広げる）、
    WAVE_FORMAT_EXTENSIBLE（GUID が上のどれか）。

  WHY:
    SDL_LoadWAV / SDL_LoadWAV_IO。SDL のヒント（SDL_WAVE_RIFF_CHUNK_SIZE / TRUNCATION /
    FACT_CHUNK / CHUNK_LIMIT）は TPMLWaveOptions で受ける。ヒントの表から作るのは FromHints。

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Audio.Wave;

{$I papimela.inc}
{$scopedenums on}

interface

uses
  Classes, SysUtils,
  PaPiMeLa.Audio.Convert;

type
  { RIFF チャンクの大きさをどう扱うか（SDL_HINT_WAVE_RIFF_CHUNK_SIZE）。
    既定（NoHint）は IgnoreZero と同じ。 }
  TPMLWaveRiffSizeHint = (NoHint, Force, IgnoreZero, Ignore, Maximum);

  { 切り詰められたファイルをどう扱うか（SDL_HINT_WAVE_TRUNCATION）。
    既定（NoHint）は DropBlock と同じ。 }
  TPMLWaveTruncationHint = (NoHint, VeryStrict, Strict, DropFrame, DropBlock);

  { fact チャンクをどう扱うか（SDL_HINT_WAVE_FACT_CHUNK）。 }
  TPMLWaveFactHint = (NoHint, Truncate, Strict, IgnoreZero, Ignore);

  TPMLWaveOptions = record
    RiffSize  : TPMLWaveRiffSizeHint;
    Truncation: TPMLWaveTruncationHint;
    Fact      : TPMLWaveFactHint;
    ChunkLimit: LongWord;   // チャンクの数の上限（SDL_HINT_WAVE_CHUNK_LIMIT。既定 10000）
    // すべて既定。
    class function Defaults: TPMLWaveOptions; static;
    { ヒントの値の文字列から作る。空の文字列は「ヒント無し」。知らない値は NoHint。
      AChunkLimit は先頭の数字を読み、数字が無ければ既定。 }
    class function FromHints(const ARiffSize, ATruncation, AFact, AChunkLimit: String): TPMLWaveOptions; static;
  end;

{ AStream の現在の位置から WAVE を読む（SDL_LoadWAV_IO。closeio = false の形）。
  標本のバイト列を返し、形式を ASpec に置く。何も無ければ空の配列。読み終えたあと、
  AStream の位置は最後に読んだチャンクの終わり（RIFF の大きさが分かるときはその終わり）。
  読めなければ EPMLAudioError（SDL のエラーの文面と同じ）。AStream が nil なら EPMLArgument。 }
function PMLLoadWAV(AStream: TStream; const AOptions: TPMLWaveOptions;
  out ASpec: TPMLAudioSpec): TBytes; overload;
function PMLLoadWAV(AStream: TStream; out ASpec: TPMLAudioSpec): TBytes; overload;

{ ファイルから読む（SDL_LoadWAV）。開けなければ EPMLIOError（既存の IO の約束）。 }
function PMLLoadWAVFile(const APath: String; const AOptions: TPMLWaveOptions;
  out ASpec: TPMLAudioSpec): TBytes; overload;
function PMLLoadWAVFile(const APath: String; out ASpec: TPMLAudioSpec): TBytes; overload;

implementation

uses
  PaPiMeLa.Errors;

const
  FourCC_RIFF = $46464952;   // 'RIFF'
  FourCC_WAVE = $45564157;   // 'WAVE'
  FourCC_FACT = $74636166;   // 'fact'
  FourCC_FMT  = $20746D66;   // 'fmt '
  FourCC_DATA = $61746164;   // 'data'

  UNKNOWN_CODE    = $0000;
  PCM_CODE        = $0001;
  MS_ADPCM_CODE   = $0002;
  IEEE_FLOAT_CODE = $0003;
  ALAW_CODE       = $0006;
  MULAW_CODE      = $0007;
  IMA_ADPCM_CODE  = $0011;
  MPEG_CODE       = $0050;
  MPEGLAYER3_CODE = $0055;
  EXTENSIBLE_CODE = $FFFE;

  // fmt チャンクは先頭の 1046 バイトだけ読む（MS ADPCM の係数の分まで）。
  FmtReadLimit = 1046;

type
  TWaveFormat = record
    FormatTag      : Word;      // fmt の先頭の値そのまま
    Encoding       : Word;      // 実際の符号化（拡張ヘッダの GUID から）
    Channels       : Word;
    Frequency      : LongWord;
    ByteRate       : LongWord;
    BlockAlign     : Word;
    BitsPerSample  : Word;
    ExtSize        : Word;
    ValidSampleBits: Word;
    SamplesPerBlock: LongWord;
    ChannelMask    : LongWord;
    SubFormat      : array[0..15] of Byte;
  end;

  TWaveFact = record
    Status      : LongInt;   // -1 無効、0 無し、1 有効、2 標本数として使う
    SampleLength: LongWord;
  end;

  TWaveChunk = record
    FourCC  : LongWord;
    Length  : LongWord;   // 宣言された大きさ
    Position: Int64;      // データの位置
    Data    : TBytes;
    Size    : SizeInt;    // 読めたバイト数（Length より小さいことがある）
  end;

  TWaveFile = record
    Chunk       : TWaveChunk;
    Format      : TWaveFormat;
    Fact        : TWaveFact;
    SampleFrames: Int64;
    Coeffs      : array of SmallInt;   // MS ADPCM の係数
    CoeffCount  : Integer;
    Options     : TPMLWaveOptions;
  end;

procedure WaveError(const AMessage: String);
begin
  raise EPMLAudioError.Create(AMessage);
end;

// ---- オプション

class function TPMLWaveOptions.Defaults: TPMLWaveOptions;
begin
  Result.RiffSize := TPMLWaveRiffSizeHint.NoHint;
  Result.Truncation := TPMLWaveTruncationHint.NoHint;
  Result.Fact := TPMLWaveFactHint.NoHint;
  Result.ChunkLimit := 10000;
end;

class function TPMLWaveOptions.FromHints(const ARiffSize, ATruncation, AFact, AChunkLimit: String): TPMLWaveOptions;
var
  I: Integer;
  V: QWord;
begin
  Result := Defaults;
  if ARiffSize = 'force' then
    Result.RiffSize := TPMLWaveRiffSizeHint.Force
  else if ARiffSize = 'ignore' then
    Result.RiffSize := TPMLWaveRiffSizeHint.Ignore
  else if ARiffSize = 'ignorezero' then
    Result.RiffSize := TPMLWaveRiffSizeHint.IgnoreZero
  else if ARiffSize = 'maximum' then
    Result.RiffSize := TPMLWaveRiffSizeHint.Maximum;

  if ATruncation = 'verystrict' then
    Result.Truncation := TPMLWaveTruncationHint.VeryStrict
  else if ATruncation = 'strict' then
    Result.Truncation := TPMLWaveTruncationHint.Strict
  else if ATruncation = 'dropframe' then
    Result.Truncation := TPMLWaveTruncationHint.DropFrame
  else if ATruncation = 'dropblock' then
    Result.Truncation := TPMLWaveTruncationHint.DropBlock;

  if AFact = 'truncate' then
    Result.Fact := TPMLWaveFactHint.Truncate
  else if AFact = 'strict' then
    Result.Fact := TPMLWaveFactHint.Strict
  else if AFact = 'ignorezero' then
    Result.Fact := TPMLWaveFactHint.IgnoreZero
  else if AFact = 'ignore' then
    Result.Fact := TPMLWaveFactHint.Ignore;

  // SDL_sscanf(hint, "%u")。先頭の数字だけを読む（数字が無ければ既定のまま）。
  I := 1;
  while (I <= Length(AChunkLimit)) and (AChunkLimit[I] = ' ') do
    Inc(I);
  if (I <= Length(AChunkLimit)) and (AChunkLimit[I] in ['0'..'9']) then
  begin
    V := 0;
    while (I <= Length(AChunkLimit)) and (AChunkLimit[I] in ['0'..'9']) do
    begin
      V := V * 10 + QWord(Ord(AChunkLimit[I]) - Ord('0'));
      if V > High(LongWord) then
      begin
        V := High(LongWord);
        Break;
      end;
      Inc(I);
    end;
    Result.ChunkLimit := LongWord(V);
  end;
end;

// ---- 読み書きの部品

function Le16(const A: TBytes; AOfs: SizeInt): Word; inline;
begin
  Result := Word(A[AOfs]) or (Word(A[AOfs + 1]) shl 8);
end;

function Le32(const A: TBytes; AOfs: SizeInt): LongWord; inline;
begin
  Result := LongWord(A[AOfs]) or (LongWord(A[AOfs + 1]) shl 8)
    or (LongWord(A[AOfs + 2]) shl 16) or (LongWord(A[AOfs + 3]) shl 24);
end;

function SInt16(V: LongInt): SmallInt; inline;
begin
  if V >= $8000 then
    Dec(V, $10000);
  Result := SmallInt(V);
end;

{ 読めたバイト数を返す（足りなければ短い）。 }
function ReadSome(AStream: TStream; var ABuf; ACount: SizeInt): SizeInt;
begin
  Result := 0;
  if ACount > 0 then
    Result := AStream.Read(ABuf, ACount);
  if Result < 0 then
    Result := 0;
end;

function SeekTo(AStream: TStream; APos: Int64): Boolean;
begin
  Result := AStream.Seek(APos, soBeginning) = APos;
end;

// ---- チャンクの読み出し（WaveNextChunk / WaveReadPartialChunkData）

{ 次のチャンクの頭へ進む。0 成功、-1 読めない（ファイルの終わり）、-2 シークできない。 }
function WaveNextChunk(AStream: TStream; var AChunk: TWaveChunk): Integer;
var
  Header: array[0..7] of Byte;
  NextPos: Int64;
begin
  NextPos := AChunk.Position + AChunk.Length;
  AChunk.Data := nil;
  AChunk.Size := 0;
  // オーバーフローは失敗
  if (High(Int64) - Int64(AChunk.Length) < AChunk.Position) or (High(Int64) - 8 < NextPos) then
    Exit(-1);
  // RIFF のチャンクは 2 バイト境界。詰め物を飛ばす
  if (AChunk.Length and 1) <> 0 then
    Inc(NextPos);
  if not SeekTo(AStream, NextPos) then
    Exit(-2);
  if ReadSome(AStream, Header, 8) <> 8 then
    Exit(-1);
  AChunk.FourCC := LongWord(Header[0]) or (LongWord(Header[1]) shl 8) or (LongWord(Header[2]) shl 16) or (LongWord(Header[3]) shl 24);
  AChunk.Length := LongWord(Header[4]) or (LongWord(Header[5]) shl 8) or (LongWord(Header[6]) shl 16) or (LongWord(Header[7]) shl 24);
  AChunk.Position := NextPos + 8;
  Result := 0;
end;

{ チャンクのデータを先頭から ALength バイトまで読む。 }
function WaveReadPartialChunkData(AStream: TStream; var AChunk: TWaveChunk; ALength: Int64): Integer;
begin
  AChunk.Data := nil;
  AChunk.Size := 0;
  if ALength > AChunk.Length then
    ALength := AChunk.Length;
  if ALength > 0 then
  begin
    SetLength(AChunk.Data, ALength);
    if not SeekTo(AStream, AChunk.Position) then
      Exit(-2);
    AChunk.Size := ReadSome(AStream, AChunk.Data[0], ALength);
  end;
  Result := 0;
end;

// ---- fact チャンクの標本数（WaveAdjustToFactValue）

function WaveAdjustToFactValue(var AFile: TWaveFile; ASampleFrames: Int64): Int64;
begin
  Result := ASampleFrames;
  if AFile.Fact.Status = 2 then
  begin
    if (AFile.Options.Fact = TPMLWaveFactHint.Strict) and (ASampleFrames < AFile.Fact.SampleLength) then
      WaveError('Invalid number of sample frames in WAVE fact chunk (too many)')
    else if ASampleFrames > AFile.Fact.SampleLength then
      Result := AFile.Fact.SampleLength;
  end;
end;

// ---- MS ADPCM

const
  PresetCoeffs: array[0..13] of SmallInt = (256, 0, 512, -256, 0, 0, 192, 64, 240, 0, 460, -208, 392, -232);
  MSAdaptive: array[0..15] of Word = (230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230);

procedure MSCalculateSampleFrames(var AFile: TWaveFile; ADataLength: Int64);
var
  BlockHeaderSize, AvailableBlocks, BlockFrameBitSize, TrailingData, TrailingSamples: Int64;
begin
  BlockHeaderSize := Int64(AFile.Format.Channels) * 7;
  AvailableBlocks := ADataLength div AFile.Format.BlockAlign;
  BlockFrameBitSize := Int64(AFile.Format.BitsPerSample) * AFile.Format.Channels;
  TrailingData := ADataLength mod AFile.Format.BlockAlign;

  if AFile.Options.Truncation in [TPMLWaveTruncationHint.VeryStrict, TPMLWaveTruncationHint.Strict] then
    if (ADataLength < BlockHeaderSize) or (TrailingData > 0) then
      WaveError('Truncated MS ADPCM block');

  AFile.SampleFrames := AvailableBlocks * AFile.Format.SamplesPerBlock;
  if (TrailingData > 0) and (AFile.Options.Truncation = TPMLWaveTruncationHint.DropFrame) then
    if TrailingData >= BlockHeaderSize then
    begin
      TrailingSamples := 2 + ((TrailingData - BlockHeaderSize) * 8) div BlockFrameBitSize;
      if TrailingSamples > AFile.Format.SamplesPerBlock then
        TrailingSamples := AFile.Format.SamplesPerBlock;
      Inc(AFile.SampleFrames, TrailingSamples);
    end;
  AFile.SampleFrames := WaveAdjustToFactValue(AFile, AFile.SampleFrames);
end;

procedure MSInit(var AFile: TWaveFile; ADataLength: Int64);
var
  Fm: ^TWaveFormat;
  BlockHeaderSize, BlockDataSize, BlockFrameBitSize, BlockDataSamples: Int64;
  I, CoeffCount: Integer;
  C: LongInt;
begin
  Fm := @AFile.Format;
  BlockHeaderSize := Int64(Fm^.Channels) * 7;
  BlockDataSize := Int64(Fm^.BlockAlign) - BlockHeaderSize;
  BlockFrameBitSize := Int64(Fm^.BitsPerSample) * Fm^.Channels;
  BlockDataSamples := (BlockDataSize * 8) div BlockFrameBitSize;

  // 3 チャンネル以上はニブルの順が不自然なので扱わない
  if Fm^.Channels > 2 then
    WaveError('Invalid number of channels');
  if Fm^.BitsPerSample <> 4 then
    WaveError(Format('Invalid MS ADPCM bits per sample of %u', [Fm^.BitsPerSample]));
  if Fm^.BlockAlign < BlockHeaderSize then
    WaveError('Invalid MS ADPCM block size (nBlockAlign)');
  if Fm^.FormatTag = EXTENSIBLE_CODE then
    WaveError('MS ADPCM with the extensible header is not supported');
  if AFile.Chunk.Size < 22 then
    WaveError('Could not read MS ADPCM format header');

  Fm^.SamplesPerBlock := Le16(AFile.Chunk.Data, 18);
  CoeffCount := Le16(AFile.Chunk.Data, 20);
  // bPredictor は 8 ビットなので先頭の 256 個までしか指せない
  if CoeffCount > 256 then
    CoeffCount := 256;

  if AFile.Chunk.Size < 22 + CoeffCount * 4 then
    WaveError('Could not read custom coefficients in MS ADPCM format header')
  else if Fm^.ExtSize < 4 + CoeffCount * 4 then
    WaveError('Invalid MS ADPCM format header (too small)')
  else if CoeffCount < 7 then
    WaveError('Missing required coefficients in MS ADPCM format header');

  SetLength(AFile.Coeffs, CoeffCount * 2);
  AFile.CoeffCount := CoeffCount;
  for I := 0 to CoeffCount * 2 - 1 do
  begin
    C := Le16(AFile.Chunk.Data, 22 + I * 2);
    if C >= $8000 then
      Dec(C, $10000);
    if (I < 14) and (C <> PresetCoeffs[I]) then
      WaveError('Wrong preset coefficients in MS ADPCM format header');
    AFile.Coeffs[I] := SmallInt(C);
  end;

  // wSamplesPerBlock が 0 なら、他の欄から求める
  if Fm^.SamplesPerBlock = 0 then
    Fm^.SamplesPerBlock := LongWord(BlockDataSamples) + 2;

  if (Fm^.SamplesPerBlock = 1) or (BlockDataSamples < Int64(Fm^.SamplesPerBlock) - 2) then
    WaveError('Invalid number of samples per MS ADPCM block (wSamplesPerBlock)');

  MSCalculateSampleFrames(AFile, ADataLength);
end;

type
  TMSChannelState = record
    Delta : Word;
    Coeff1: SmallInt;
    Coeff2: SmallInt;
  end;

function MSProcessNibble(var ACState: TMSChannelState; ASample1, ASample2: LongInt; ANybble: Byte): SmallInt;
var
  NewSample, ErrorDelta: LongInt;
  Delta: LongWord;
begin
  Delta := ACState.Delta;
  NewSample := (ASample1 * ACState.Coeff1 + ASample2 * ACState.Coeff2) div 256;
  // ニブルは符号つき 4 ビットの誤差
  ErrorDelta := LongInt(ANybble);
  if ANybble >= 8 then
    Dec(ErrorDelta, $10);
  Inc(NewSample, LongInt(Delta) * ErrorDelta);
  if NewSample < -32768 then
    NewSample := -32768
  else if NewSample > 32767 then
    NewSample := 32767;
  Delta := (Delta * MSAdaptive[ANybble]) div 256;
  if Delta < 16 then
    Delta := 16
  else if Delta > 65535 then
    Delta := 65535;
  ACState.Delta := Word(Delta);
  Result := SmallInt(NewSample);
end;

{ 範囲の外の標本は、末尾を切り捨てて返す。ASamples は 16 ビットの標本の列。 }
function Int16Bytes(const ASamples: array of SmallInt; AByteLen: Int64): TBytes;
begin
  Result := nil;
  SetLength(Result, AByteLen);
  if AByteLen > 0 then
    Move(ASamples[0], Result[0], AByteLen);
end;

{ 展開後のバイト数が 32 ビットに収まるか（SDL の "WAVE file too big"）。 }
procedure CheckOutputSize(AFrames: Int64; AUnitBytes: Int64);
var
  Total: QWord;
begin
  if (AFrames < 0) or (AUnitBytes <= 0) then
    WaveError('WAVE file too big');
  if (AFrames > 0) and (QWord(High(QWord)) div QWord(AFrames) <= QWord(AUnitBytes)) then
    WaveError('WAVE file too big');
  Total := QWord(AFrames) * QWord(AUnitBytes);
  if Total > High(LongWord) then
    WaveError('WAVE file too big');
end;

function MSDecode(var AFile: TWaveFile): TBytes;
var
  Channels, BlockHeaderSize, SamplesPerBlock: Integer;
  BlockSize: Int64;
  FramesLeft, OutputSize, BytesLeft, InPos: Int64;
  OutData: array of SmallInt;
  OutPos, OutLen: Int64;
  CState: array[0..1] of TMSChannelState;
  BlockOfs, BlockSz, BlockPos: Int64;
  CoeffIndex: Integer;
  Sample: LongInt;
  O: Int64;
  Data: TBytes;

  { ブロックのヘッダ（1 ブロックの先頭のチャンネルごとの値）を読む。 }
  procedure DecodeBlockHeader;
  var
    Cc: Integer;
  begin
    for Cc := 0 to Channels - 1 do
    begin
      CoeffIndex := Data[BlockOfs + Cc];
      // SDL は ">" で、係数の数と同じ番号が配列の外を読む。papimela は断る
      if CoeffIndex >= AFile.CoeffCount then
        WaveError('Invalid MS ADPCM coefficient index in block header');
      CState[Cc].Coeff1 := AFile.Coeffs[CoeffIndex * 2];
      CState[Cc].Coeff2 := AFile.Coeffs[CoeffIndex * 2 + 1];
      O := BlockOfs + Channels + Cc * 2;
      CState[Cc].Delta := Word(Data[O]) or (Word(Data[O + 1]) shl 8);
      // 出力で後ろにある標本が先に来る
      O := BlockOfs + Channels * 3 + Cc * 2;
      Sample := Data[O] or (LongInt(Data[O + 1]) shl 8);
      OutData[OutPos + Channels] := SInt16(Sample);
      O := BlockOfs + Channels * 5 + Cc * 2;
      Sample := Data[O] or (LongInt(Data[O + 1]) shl 8);
      OutData[OutPos] := SInt16(Sample);
      Inc(OutPos);
    end;
    BlockPos := BlockHeaderSize;
    // ヘッダが与えた 2 つ目の標本の枠を飛ばす
    Inc(OutPos, Channels);
    Dec(FramesLeft, 2);
  end;

  { ブロックのデータ部。途中で足りなくなれば False（不完全な標本は捨てる）。 }
  function DecodeBlockData: Boolean;
  var
    Nybble: Word;
    BlockFramesLeft: Int64;
    Cc: Integer;
    S1, S2: LongInt;
  begin
    Result := True;
    Nybble := 0;
    BlockFramesLeft := SamplesPerBlock - 2;
    if BlockFramesLeft > FramesLeft then
      BlockFramesLeft := FramesLeft;
    while BlockFramesLeft > 0 do
    begin
      for Cc := 0 to Channels - 1 do
      begin
        if (Nybble and $4000) <> 0 then
          Nybble := Word((LongWord(Nybble) shl 4) and $FFFF)
        else if BlockPos < BlockSz then
        begin
          Nybble := Word(Data[BlockOfs + BlockPos]) or $4000;
          Inc(BlockPos);
        end
        else
        begin
          // 入力が尽きた。不完全な枠を捨てて戻る
          OutPos := OutPos - Cc;
          Exit(False);
        end;
        S1 := OutData[OutPos - Channels];
        S2 := OutData[OutPos - Channels * 2];
        OutData[OutPos] := MSProcessNibble(CState[Cc], S1, S2, (Nybble shr 4) and $0F);
        Inc(OutPos);
      end;
      Dec(FramesLeft);
      Dec(BlockFramesLeft);
    end;
  end;

begin
  Result := nil;
  FillChar(CState, SizeOf(CState), 0);
  if AFile.Chunk.Size <> AFile.Chunk.Length then
    MSCalculateSampleFrames(AFile, AFile.Chunk.Size);
  if AFile.SampleFrames = 0 then
    Exit;

  Channels := AFile.Format.Channels;
  BlockSize := AFile.Format.BlockAlign;
  BlockHeaderSize := Channels * 7;
  SamplesPerBlock := AFile.Format.SamplesPerBlock;
  FramesLeft := AFile.SampleFrames;
  Data := AFile.Chunk.Data;

  CheckOutputSize(AFile.SampleFrames, Channels * 2);
  OutputSize := AFile.SampleFrames * Channels * 2;
  OutLen := OutputSize div 2;
  OutData := nil;
  SetLength(OutData, OutLen);
  FillChar(OutData[0], OutLen * 2, 0);
  OutPos := 0;

  InPos := 0;
  BytesLeft := AFile.Chunk.Size - InPos;
  while (FramesLeft > 0) and (BytesLeft >= BlockHeaderSize) do
  begin
    BlockOfs := InPos;
    if BytesLeft < BlockSize then
      BlockSz := BytesLeft
    else
      BlockSz := BlockSize;
    BlockPos := 0;

    if OutLen - OutPos < FramesLeft * Channels then
      WaveError('Unexpected overflow in MS ADPCM decoder');

    DecodeBlockHeader;
    if not DecodeBlockData then
    begin
      // 予期しない終わり。必要なら途中まで返す
      if AFile.Options.Truncation in [TPMLWaveTruncationHint.VeryStrict, TPMLWaveTruncationHint.Strict] then
        WaveError('Truncated data chunk')
      else if AFile.Options.Truncation <> TPMLWaveTruncationHint.DropFrame then
        OutPos := OutPos - OutPos mod (Int64(SamplesPerBlock) * Channels);
      OutputSize := OutPos * 2;
      Break;
    end;

    Inc(InPos, BlockSz);
    BytesLeft := AFile.Chunk.Size - InPos;
  end;

  Result := Int16Bytes(OutData, OutputSize);
end;

// ---- IMA ADPCM

const
  IMAIndexTable: array[0..15] of ShortInt = (-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8);
  IMAStepTable: array[0..88] of Word = (
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
    34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130,
    143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408,
    449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282,
    1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327,
    3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630,
    9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350,
    22385, 24623, 27086, 29794, 32767);

procedure IMACalculateSampleFrames(var AFile: TWaveFile; ADataLength: Int64);
var
  Fm: ^TWaveFormat;
  BlockHeaderSize, SubBlockFrameSize, AvailableBlocks, TrailingData: Int64;
  TrailingSamples, TrailingBlockData, TrailingSubBlockData: Int64;
begin
  Fm := @AFile.Format;
  BlockHeaderSize := Int64(Fm^.Channels) * 4;
  SubBlockFrameSize := Int64(Fm^.Channels) * 4;
  AvailableBlocks := ADataLength div Fm^.BlockAlign;
  TrailingData := ADataLength mod Fm^.BlockAlign;

  if AFile.Options.Truncation in [TPMLWaveTruncationHint.VeryStrict, TPMLWaveTruncationHint.Strict] then
    if (ADataLength < BlockHeaderSize) or (TrailingData > 0) then
      WaveError('Truncated IMA ADPCM block');

  AFile.SampleFrames := AvailableBlocks * Fm^.SamplesPerBlock;
  if (TrailingData > 0) and (AFile.Options.Truncation = TPMLWaveTruncationHint.DropFrame)
    and (TrailingData > BlockHeaderSize - 2) then
  begin
    // 切れたブロックの頭の標本は残っている。不完全な標本は捨てる
    TrailingSamples := 1;
    if TrailingData > BlockHeaderSize then
    begin
      TrailingBlockData := TrailingData - BlockHeaderSize;
      TrailingSubBlockData := TrailingBlockData mod SubBlockFrameSize;
      Inc(TrailingSamples, (TrailingBlockData div SubBlockFrameSize) * 8);
      // 副ブロックが交互に並ぶので、最後の 4 バイトで切れた副ブロックの標本の数が決まる
      if TrailingSubBlockData > SubBlockFrameSize - 4 then
        Inc(TrailingSamples, (TrailingSubBlockData mod 4) * 2);
    end;
    if TrailingSamples > Fm^.SamplesPerBlock then
      TrailingSamples := Fm^.SamplesPerBlock;
    Inc(AFile.SampleFrames, TrailingSamples);
  end;

  AFile.SampleFrames := WaveAdjustToFactValue(AFile, AFile.SampleFrames);
end;

procedure IMAInit(var AFile: TWaveFile; ADataLength: Int64);
var
  Fm: ^TWaveFormat;
  BlockHeaderSize, BlockDataSize, BlockFrameBitSize, BlockDataSamples: Int64;
begin
  Fm := @AFile.Format;
  BlockHeaderSize := Int64(Fm^.Channels) * 4;
  BlockDataSize := Int64(Fm^.BlockAlign) - BlockHeaderSize;
  BlockFrameBitSize := Int64(Fm^.BitsPerSample) * Fm^.Channels;
  BlockDataSamples := (BlockDataSize * 8) div BlockFrameBitSize;

  if Fm^.BitsPerSample = 3 then
    WaveError('3-bit IMA ADPCM currently not supported')
  else if Fm^.BitsPerSample <> 4 then
    WaveError(Format('Invalid IMA ADPCM bits per sample of %u', [Fm^.BitsPerSample]));

  // ブロックの大きさは 4 の倍数で、ヘッダが入ること
  if (Fm^.BlockAlign < BlockHeaderSize) or ((Fm^.BlockAlign mod 4) <> 0) then
    WaveError('Invalid IMA ADPCM block size (nBlockAlign)');

  if Fm^.FormatTag <> EXTENSIBLE_CODE then
    // 標準の更新には wSamplesPerBlock が 2 バイトあるはず
    if (AFile.Chunk.Size >= 20) and (Fm^.ExtSize >= 2) then
      Fm^.SamplesPerBlock := Le16(AFile.Chunk.Data, 18);

  // 0 なら、エンコーダがブロックを詰めたと見なす
  if Fm^.SamplesPerBlock = 0 then
    Fm^.SamplesPerBlock := LongWord(BlockDataSamples) + 1;

  if BlockDataSamples < Int64(Fm^.SamplesPerBlock) - 1 then
    WaveError('Invalid number of samples per IMA ADPCM block (wSamplesPerBlock)');

  IMACalculateSampleFrames(AFile, ADataLength);
end;

function IMAProcessNibble(var ACIndex: ShortInt; ALastSample: SmallInt; ANybble: Byte): SmallInt;
var
  Index: ShortInt;
  Step: LongWord;
  Sample, Delta: LongInt;
begin
  Index := ACIndex;
  if Index > 88 then
    Index := 88
  else if Index < 0 then
    Index := 0;
  Step := IMAStepTable[Index];
  ACIndex := ShortInt(Index + IMAIndexTable[ANybble]);

  // SDL は乗算でなくシフトと加算で、落ちるビットまで同じにする
  Delta := LongInt(Step shr 3);
  if (ANybble and $04) <> 0 then
    Inc(Delta, Step);
  if (ANybble and $02) <> 0 then
    Inc(Delta, Step shr 1);
  if (ANybble and $01) <> 0 then
    Inc(Delta, Step shr 2);
  if (ANybble and $08) <> 0 then
    Delta := -Delta;

  Sample := ALastSample + Delta;
  if Sample > 32767 then
    Sample := 32767
  else if Sample < -32768 then
    Sample := -32768;
  Result := SmallInt(Sample);
end;

function IMADecode(var AFile: TWaveFile): TBytes;
var
  Channels, SamplesPerBlock: Integer;
  BlockSize, BlockHeaderSize, FramesLeft, OutputSize, BytesLeft, InPos: Int64;
  OutData: array of SmallInt;
  OutPos, OutLen: Int64;
  CState: array of ShortInt;
  BlockOfs, BlockSz, BlockPos: Int64;
  Data: TBytes;

  procedure DecodeBlockHeader;
  var
    Cc: Integer;
    O: Int64;
    Step: SmallInt;
  begin
    for Cc := 0 to Channels - 1 do
    begin
      O := BlockOfs + BlockPos + Cc * 4;
      OutData[OutPos] := SInt16(Data[O] or (LongInt(Data[O + 1]) shl 8));
      Inc(OutPos);
      // チャンネルごとの刻みの番号
      Step := Data[O + 2];
      if Step > $80 then
        CState[Cc] := ShortInt(Step - $100)
      else
        CState[Cc] := ShortInt(Step);
    end;
    Inc(BlockPos, BlockHeaderSize);
    // ヘッダが標本の枠を 1 つ与えた
    Dec(FramesLeft);
  end;

  function DecodeBlockData: Boolean;
  var
    SubBlockFrameSize, BlockLeft, BytesRequired, BlockFramesLeft, GuaranteedFrames, RemainingBytes: Int64;
    SubBlockSamples, I: Integer;
    Cc: Integer;
    Nybble: Byte;
    Sample: SmallInt;
  begin
    Result := True;
    SubBlockFrameSize := Int64(Channels) * 4;
    BlockLeft := BlockSz - BlockPos;
    BlockFramesLeft := SamplesPerBlock - 1;
    if BlockFramesLeft > FramesLeft then
      BlockFramesLeft := FramesLeft;

    BytesRequired := (BlockFramesLeft + 7) div 8 * SubBlockFrameSize;
    if BlockLeft < BytesRequired then
    begin
      // データが切れている。取れる標本の数を数える
      GuaranteedFrames := BlockLeft div SubBlockFrameSize;
      RemainingBytes := BlockLeft mod SubBlockFrameSize;
      BlockFramesLeft := GuaranteedFrames;
      if RemainingBytes > SubBlockFrameSize - 4 then
        Inc(BlockFramesLeft, (RemainingBytes mod 4) * 2);
      Result := False;
    end;

    // 各チャンネルのニブルは 32 ビットの塊に詰められ、その塊が交互に並ぶ
    while BlockFramesLeft > 0 do
    begin
      if BlockFramesLeft < 8 then
        SubBlockSamples := BlockFramesLeft
      else
        SubBlockSamples := 8;
      for Cc := 0 to Channels - 1 do
      begin
        Nybble := 0;
        Sample := OutData[OutPos + Cc - Channels];
        for I := 0 to SubBlockSamples - 1 do
        begin
          if (I and 1) <> 0 then
            Nybble := Nybble shr 4
          else
          begin
            Nybble := Data[BlockOfs + BlockPos];
            Inc(BlockPos);
          end;
          Sample := IMAProcessNibble(CState[Cc], Sample, Nybble and $0F);
          OutData[OutPos + Cc + I * Channels] := Sample;
        end;
      end;
      Inc(OutPos, Channels * SubBlockSamples);
      Dec(FramesLeft, SubBlockSamples);
      Dec(BlockFramesLeft, SubBlockSamples);
    end;
  end;

begin
  Result := nil;
  if AFile.Chunk.Size <> AFile.Chunk.Length then
    IMACalculateSampleFrames(AFile, AFile.Chunk.Size);
  if AFile.SampleFrames = 0 then
    Exit;

  Channels := AFile.Format.Channels;
  BlockSize := AFile.Format.BlockAlign;
  BlockHeaderSize := Int64(Channels) * 4;
  SamplesPerBlock := AFile.Format.SamplesPerBlock;
  FramesLeft := AFile.SampleFrames;
  Data := AFile.Chunk.Data;

  CheckOutputSize(AFile.SampleFrames, Channels * 2);
  OutputSize := AFile.SampleFrames * Channels * 2;
  OutLen := OutputSize div 2;
  OutData := nil;
  SetLength(OutData, OutLen);
  FillChar(OutData[0], OutLen * 2, 0);
  CState := nil;
  SetLength(CState, Channels);
  FillChar(CState[0], Channels, 0);
  OutPos := 0;

  InPos := 0;
  BytesLeft := AFile.Chunk.Size - InPos;
  while (FramesLeft > 0) and (BytesLeft >= BlockHeaderSize) do
  begin
    BlockOfs := InPos;
    if BytesLeft < BlockSize then
      BlockSz := BytesLeft
    else
      BlockSz := BlockSize;
    BlockPos := 0;

    if OutLen - OutPos < FramesLeft * Channels then
      WaveError('Unexpected overflow in IMA ADPCM decoder');

    DecodeBlockHeader;
    if not DecodeBlockData then
    begin
      if AFile.Options.Truncation in [TPMLWaveTruncationHint.VeryStrict, TPMLWaveTruncationHint.Strict] then
        WaveError('Truncated data chunk')
      else if AFile.Options.Truncation <> TPMLWaveTruncationHint.DropFrame then
        OutPos := OutPos - OutPos mod (Int64(SamplesPerBlock) * Channels);
      OutputSize := OutPos * 2;
      Break;
    end;

    Inc(InPos, BlockSz);
    BytesLeft := AFile.Chunk.Size - InPos;
  end;

  Result := Int16Bytes(OutData, OutputSize);
end;

// ---- A-law / μ-law

procedure LAWInit(var AFile: TWaveFile; ADataLength: Int64);
var
  Fm: ^TWaveFormat;
begin
  Fm := @AFile.Format;
  // 標準の更新は 8 ビットを求める
  if Fm^.BitsPerSample <> 8 then
    WaveError(Format('Invalid companded bits per sample of %u', [Fm^.BitsPerSample]));
  // 変わった詰め物は扱わない
  if Fm^.BlockAlign <> Fm^.Channels then
    WaveError('Unsupported block alignment');
  if AFile.Options.Truncation in [TPMLWaveTruncationHint.VeryStrict, TPMLWaveTruncationHint.Strict] then
    if (Fm^.BlockAlign > 1) and ((ADataLength mod Fm^.BlockAlign) <> 0) then
      WaveError('Truncated data chunk in WAVE file');
  AFile.SampleFrames := WaveAdjustToFactValue(AFile, ADataLength div Fm^.BlockAlign);
end;

function ALawSample(ASrc: Byte): SmallInt;
var
  Exponent: Byte;
  Mantissa: LongInt;
begin
  Exponent := (ASrc and $7F) xor $55;
  Mantissa := Exponent and $0F;
  Exponent := Exponent shr 4;
  if Exponent > 0 then
    Mantissa := Mantissa or $10;
  Mantissa := (Mantissa shl 4) or $8;
  if Exponent > 1 then
    Mantissa := Mantissa shl (Exponent - 1);
  if (ASrc and $80) <> 0 then
    Result := SmallInt(Mantissa)
  else
    Result := SmallInt(-Mantissa);
end;

function MuLawSample(ASrc: Byte): SmallInt;
var
  Nibble, Exponent: Byte;
  Mantissa, Step: LongInt;
begin
  Nibble := not ASrc;
  Mantissa := Nibble and $0F;
  Exponent := (Nibble shr 4) and $07;
  Step := 4 shl (Exponent + 1);
  Mantissa := (LongInt($80) shl Exponent) + Step * Mantissa + Step div 2 - 132;
  if (Nibble and $80) <> 0 then
    Result := SmallInt(-Mantissa)
  else
    Result := SmallInt(Mantissa);
end;

function LAWDecode(var AFile: TWaveFile): TBytes;
var
  SampleCount, I: Int64;
  Samples: array of SmallInt;
begin
  Result := nil;
  if AFile.Chunk.Length <> AFile.Chunk.Size then
    AFile.SampleFrames := WaveAdjustToFactValue(AFile, AFile.Chunk.Size div AFile.Format.BlockAlign);
  if AFile.SampleFrames = 0 then
    Exit;

  CheckOutputSize(AFile.SampleFrames, Int64(AFile.Format.Channels) * 2);
  SampleCount := AFile.SampleFrames * AFile.Format.Channels;
  Samples := nil;
  SetLength(Samples, SampleCount);
  for I := 0 to SampleCount - 1 do
    if AFile.Format.Encoding = ALAW_CODE then
      Samples[I] := ALawSample(AFile.Chunk.Data[I])
    else if AFile.Format.Encoding = MULAW_CODE then
      Samples[I] := MuLawSample(AFile.Chunk.Data[I])
    else
      WaveError('Unknown companded encoding');
  Result := Int16Bytes(Samples, SampleCount * 2);
end;

// ---- PCM / IEEE 浮動小数

procedure PCMInit(var AFile: TWaveFile; ADataLength: Int64);
var
  Fm: ^TWaveFormat;
begin
  Fm := @AFile.Format;
  if Fm^.Encoding = PCM_CODE then
  begin
    case Fm^.BitsPerSample of
      8, 16, 24, 32: ;   // 扱える
    else
      WaveError(Format('%u-bit PCM format not supported', [Fm^.BitsPerSample]));
    end;
  end
  else if Fm^.Encoding = IEEE_FLOAT_CODE then
    if Fm^.BitsPerSample <> 32 then
      WaveError(Format('%u-bit IEEE floating-point format not supported', [Fm^.BitsPerSample]));

  // 少なくとも blockalign の倍数であること
  if ((LongWord(Fm^.Channels) * Fm^.BitsPerSample) mod (LongWord(Fm^.BlockAlign) * 8)) <> 0 then
    WaveError('Unsupported block alignment');

  if AFile.Options.Truncation in [TPMLWaveTruncationHint.VeryStrict, TPMLWaveTruncationHint.Strict] then
    if (Fm^.BlockAlign > 1) and ((ADataLength mod Fm^.BlockAlign) <> 0) then
      WaveError('Truncated data chunk in WAVE file');

  AFile.SampleFrames := WaveAdjustToFactValue(AFile, ADataLength div Fm^.BlockAlign);
end;

function PCMDecode(var AFile: TWaveFile): TBytes;
var
  OutputSize, SampleCount, I: Int64;
begin
  Result := nil;
  if AFile.Chunk.Length <> AFile.Chunk.Size then
    AFile.SampleFrames := WaveAdjustToFactValue(AFile, AFile.Chunk.Size div AFile.Format.BlockAlign);
  if AFile.SampleFrames = 0 then
    Exit;

  // 24 ビットは 32 ビットの上位 3 バイトに置く
  if (AFile.Format.Encoding = PCM_CODE) and (AFile.Format.BitsPerSample = 24) then
  begin
    CheckOutputSize(AFile.SampleFrames, Int64(AFile.Format.Channels) * 4);
    SampleCount := AFile.SampleFrames * AFile.Format.Channels;
    SetLength(Result, SampleCount * 4);
    for I := 0 to SampleCount - 1 do
    begin
      Result[I * 4] := 0;
      Result[I * 4 + 1] := AFile.Chunk.Data[I * 3];
      Result[I * 4 + 2] := AFile.Chunk.Data[I * 3 + 1];
      Result[I * 4 + 3] := AFile.Chunk.Data[I * 3 + 2];
    end;
    Exit;
  end;

  CheckOutputSize(AFile.SampleFrames, AFile.Format.BlockAlign);
  OutputSize := AFile.SampleFrames * AFile.Format.BlockAlign;
  SetLength(Result, OutputSize);
  Move(AFile.Chunk.Data[0], Result[0], OutputSize);
end;

// ---- fmt チャンクと全体

function WaveGetFormatGUIDEncoding(const AFormat: TWaveFormat): Word;
const
  Encodings: array[0..5] of Word = (PCM_CODE, MS_ADPCM_CODE, IEEE_FLOAT_CODE, ALAW_CODE, MULAW_CODE, IMA_ADPCM_CODE);
var
  I: Integer;
  Match: Boolean;
begin
  Result := UNKNOWN_CODE;
  for I := Low(Encodings) to High(Encodings) do
  begin
    // GUID: tag(2 バイト, LE) 0 0 0 0 16 0 128 0 0 170 0 56 155 113
    Match := (AFormat.SubFormat[0] = (Encodings[I] and $FF)) and (AFormat.SubFormat[1] = (Encodings[I] shr 8))
      and (AFormat.SubFormat[2] = 0) and (AFormat.SubFormat[3] = 0)
      and (AFormat.SubFormat[4] = 0) and (AFormat.SubFormat[5] = 0)
      and (AFormat.SubFormat[6] = 16) and (AFormat.SubFormat[7] = 0)
      and (AFormat.SubFormat[8] = 128) and (AFormat.SubFormat[9] = 0)
      and (AFormat.SubFormat[10] = 0) and (AFormat.SubFormat[11] = 170)
      and (AFormat.SubFormat[12] = 0) and (AFormat.SubFormat[13] = 56)
      and (AFormat.SubFormat[14] = 155) and (AFormat.SubFormat[15] = 113);
    if Match then
      Exit(Encodings[I]);
  end;
end;

procedure WaveReadFormat(var AFile: TWaveFile);
var
  Fm: ^TWaveFormat;
  FmtLen: SizeInt;
  I: Integer;
begin
  Fm := @AFile.Format;
  FmtLen := AFile.Chunk.Size;
  // 少なくとも 14 バイトは呼び出し側が確かめた
  Fm^.FormatTag := Le16(AFile.Chunk.Data, 0);
  Fm^.Channels := Le16(AFile.Chunk.Data, 2);
  Fm^.Frequency := Le32(AFile.Chunk.Data, 4);
  Fm^.ByteRate := Le32(AFile.Chunk.Data, 8);
  Fm^.BlockAlign := Le16(AFile.Chunk.Data, 12);
  Fm^.Encoding := Fm^.FormatTag;

  // 最初の版の仕様では PCM 専用の欄
  if FmtLen >= 16 then
    Fm^.BitsPerSample := Le16(AFile.Chunk.Data, 14)
  else if Fm^.Encoding = PCM_CODE then
    WaveError('Missing wBitsPerSample field in WAVE fmt chunk');

  // 古い版にはこの欄も無い
  if FmtLen >= 18 then
    Fm^.ExtSize := Le16(AFile.Chunk.Data, 16);

  if Fm^.FormatTag = EXTENSIBLE_CODE then
  begin
    // チャンネルのマスクや、容器より小さい有効ビットなどは無視する
    if (FmtLen < 40) or (Fm^.ExtSize < 22) then
      WaveError('Extensible WAVE header too small');
    Fm^.ValidSampleBits := Le16(AFile.Chunk.Data, 18);
    Fm^.ChannelMask := Le32(AFile.Chunk.Data, 20);
    for I := 0 to 15 do
      Fm^.SubFormat[I] := AFile.Chunk.Data[24 + I];
    Fm^.SamplesPerBlock := Fm^.ValidSampleBits;
    Fm^.Encoding := WaveGetFormatGUIDEncoding(Fm^);
  end;
end;

procedure WaveCheckFormat(var AFile: TWaveFile; ADataLength: Int64);
var
  Fm: ^TWaveFormat;
  Samples: LongWord;
  FactHint: TPMLWaveFactHint;
begin
  Fm := @AFile.Format;

  if Fm^.Channels = 0 then
    WaveError('Invalid number of channels');
  if Fm^.Frequency = 0 then
    WaveError('Invalid sample rate')
  else if Fm^.Frequency > High(LongInt) then
    WaveError(Format('Sample rate exceeds limit of %d', [High(LongInt)]));

  if (AFile.Options.Fact = TPMLWaveFactHint.Strict) and (AFile.Fact.Status = -1) then
    WaveError('Invalid fact chunk in WAVE file');

  case Fm^.Encoding of
    IEEE_FLOAT_CODE, ALAW_CODE, MULAW_CODE, MS_ADPCM_CODE, IMA_ADPCM_CODE, PCM_CODE:
    begin
      if Fm^.Encoding <> PCM_CODE then
        // これらの形式には fact チャンクが要る
        if (AFile.Options.Fact = TPMLWaveFactHint.Strict) and (AFile.Fact.Status <= 0) then
          WaveError('Missing fact chunk in WAVE file');
      // どの形式も 0 でないビット数が要る
      if AFile.Chunk.Size < 16 then
        WaveError('Missing wBitsPerSample field in WAVE fmt chunk')
      else if Fm^.BitsPerSample = 0 then
        WaveError('Invalid bits per sample');
      if Fm^.BlockAlign = 0 then
        Fm^.BlockAlign := 1;   // 未設定は 1 にする
      // fact が有効でヒントがあれば、復号は fact の標本数を使う
      if AFile.Fact.Status = 1 then
      begin
        FactHint := AFile.Options.Fact;
        Samples := AFile.Fact.SampleLength;
        if (FactHint = TPMLWaveFactHint.Truncate) or (FactHint = TPMLWaveFactHint.Strict)
          or ((FactHint = TPMLWaveFactHint.IgnoreZero) and (Samples > 0)) then
          AFile.Fact.Status := 2;
      end;
    end;
  end;

  case Fm^.Encoding of
    PCM_CODE, IEEE_FLOAT_CODE:
      PCMInit(AFile, ADataLength);
    ALAW_CODE, MULAW_CODE:
      LAWInit(AFile, ADataLength);
    MS_ADPCM_CODE:
      MSInit(AFile, ADataLength);
    IMA_ADPCM_CODE:
      IMAInit(AFile, ADataLength);
    MPEG_CODE, MPEGLAYER3_CODE:
      WaveError('MPEG formats not supported');
  else
    if Fm^.FormatTag = EXTENSIBLE_CODE then
    begin
      WaveError('Unknown WAVE format GUID: ' + LowerCase(Format('%.8x-%.4x-%.4x-%.2x%.2x%.2x%.2x%.2x%.2x%.2x%.2x',
        [LongWord(Fm^.SubFormat[0]) or (LongWord(Fm^.SubFormat[1]) shl 8) or (LongWord(Fm^.SubFormat[2]) shl 16)
           or (LongWord(Fm^.SubFormat[3]) shl 24),
         Word(Fm^.SubFormat[4]) or (Word(Fm^.SubFormat[5]) shl 8),
         Word(Fm^.SubFormat[6]) or (Word(Fm^.SubFormat[7]) shl 8),
         Fm^.SubFormat[8], Fm^.SubFormat[9], Fm^.SubFormat[10], Fm^.SubFormat[11],
         Fm^.SubFormat[12], Fm^.SubFormat[13], Fm^.SubFormat[14], Fm^.SubFormat[15]])));
    end;
    WaveError('Unknown WAVE format tag: 0x' + LowerCase(Format('%.4x', [Fm^.Encoding])));
  end;
end;

function WaveLoad(AStream: TStream; var AFile: TWaveFile; out ASpec: TPMLAudioSpec): TBytes;
var
  ChunkCount: LongWord;
  ChunkCountLimit: LongWord;
  Flen: Int64;
  RiffStart, RiffEnd, LastChunkPos: Int64;
  RiffLengthKnown: Boolean;
  RiffChunk, FmtChunk, DataChunk: TWaveChunk;
  Res: Integer;
  FormType: array[0..3] of Byte;
  Tmp: array[0..3] of Byte;
  Tmp1: Byte;
  Pos64: Int64;
begin
  Result := nil;
  FillChar(RiffChunk, SizeOf(RiffChunk), 0);
  FillChar(FmtChunk, SizeOf(FmtChunk), 0);
  FillChar(DataChunk, SizeOf(DataChunk), 0);
  RiffChunk.Data := nil;
  FmtChunk.Data := nil;
  DataChunk.Data := nil;
  RiffLengthKnown := False;
  ChunkCount := 0;
  ChunkCountLimit := AFile.Options.ChunkLimit;
  Flen := AStream.Size;

  RiffStart := AStream.Position;
  RiffChunk.Position := RiffStart;
  if WaveNextChunk(AStream, RiffChunk) < 0 then
    WaveError('Could not read RIFF header');

  if RiffChunk.FourCC = FourCC_RIFF then
  begin
    // 形式の種類。"WAVE" のはず
    if ReadSome(AStream, FormType, 4) <> 4 then
      WaveError('Could not read RIFF form type')
    else if (LongWord(FormType[0]) or (LongWord(FormType[1]) shl 8) or (LongWord(FormType[2]) shl 16)
      or (LongWord(FormType[3]) shl 24)) <> FourCC_WAVE then
      WaveError('RIFF form type is not WAVE (not a Waveform file)');
  end
  else if RiffChunk.FourCC = FourCC_WAVE then
  begin
    // RIFF のチャンクが無いか、飛ばした。大きさは分からない
    RiffChunk.Position := 0;
    RiffChunk.Length := 0;
  end
  else
    WaveError('Could not find RIFF or WAVE identifiers (not a Waveform file)');

  // 形式の種類の 4 バイトの直後が最初のチャンク
  AFile.Chunk.Position := RiffChunk.Position + 4;

  // RIFF の大きさで探す範囲を区切る（信用できないこともあるのでヒントで変えられる）。
  // 既定は 4 GiB より先を探さない
  case AFile.Options.RiffSize of
    TPMLWaveRiffSizeHint.Ignore:
      RiffEnd := RiffChunk.Position + High(LongWord);
    TPMLWaveRiffSizeHint.Maximum:
      RiffEnd := High(Int64);
  else
    // NoHint と IgnoreZero は同じ。Force は大きさ 0 でも信じる
    if (AFile.Options.RiffSize <> TPMLWaveRiffSizeHint.Force) and (RiffChunk.Length = 0) then
      RiffEnd := RiffChunk.Position + High(LongWord)
    else
    begin
      RiffEnd := RiffChunk.Position + RiffChunk.Length;
      RiffLengthKnown := True;
    end;
  end;

  // すべてのチャンクをたどって fmt・data・fact を覚える。知らないチャンクは仕様どおり無視する
  while QWord(RiffEnd) > QWord(AFile.Chunk.Position) + AFile.Chunk.Length + (AFile.Chunk.Length and 1) do
  begin
    // 壊れたファイルで時間を使わないよう、チャンクの数に上限を置く
    if ChunkCount >= ChunkCountLimit then
      WaveError(Format('Chunk count in WAVE file exceeds limit of %u', [ChunkCountLimit]));
    Inc(ChunkCount);

    Res := WaveNextChunk(AStream, AFile.Chunk);
    if Res < 0 then
    begin
      if Res = -2 then
        WaveError('Could not seek to WAVE chunk header');
      // 予期しないファイルの終わり
      if AFile.Options.Truncation = TPMLWaveTruncationHint.VeryStrict then
        WaveError('Unexpected end of WAVE file');
      // ループの後の確かめに任せる
      Break;
    end;

    if AFile.Chunk.FourCC = FourCC_FMT then
    begin
      if FmtChunk.FourCC = FourCC_FMT then
        // fmt が複数ある。最初のものを使う
      else
      begin
        // fmt は data より前
        if DataChunk.FourCC = FourCC_DATA then
          WaveError('fmt chunk after data chunk in WAVE file');
        FmtChunk := AFile.Chunk;
      end;
    end
    else if AFile.Chunk.FourCC = FourCC_DATA then
    begin
      // data がファイルより大きければ壊れているか切り詰められている。
      // 大きさを切り詰めて続ける（悪意のあるファイルが 4 GiB を確保させないため）
      if (Flen > 0) and ((AFile.Chunk.Position + AFile.Chunk.Length) > Flen) then
        AFile.Chunk.Length := LongWord(Flen - AFile.Chunk.Position);
      // 最初の data だけを使う
      if DataChunk.FourCC <> FourCC_DATA then
        DataChunk := AFile.Chunk;
    end
    else if AFile.Chunk.FourCC = FourCC_FACT then
    begin
      // fact は 4 バイト以上。最初のもの以外は無視する
      if AFile.Fact.Status = 0 then
      begin
        if AFile.Chunk.Length < 4 then
          AFile.Fact.Status := -1
        else
        begin
          Pos64 := -1;
          if SeekTo(AStream, AFile.Chunk.Position) then
            Pos64 := AFile.Chunk.Position;
          if (Pos64 = AFile.Chunk.Position) and (ReadSome(AStream, Tmp, 4) = 4) then
          begin
            AFile.Fact.SampleLength := LongWord(Tmp[0]) or (LongWord(Tmp[1]) shl 8) or (LongWord(Tmp[2]) shl 16)
              or (LongWord(Tmp[3]) shl 24);
            AFile.Fact.Status := 1;
          end
          else
            AFile.Fact.Status := -1;
        end;
      end;
    end;

    // verystrict ではすべてのチャンクをたどる。そうでなければ、必要なものが揃えば探索を打ち切る
    if AFile.Options.Truncation = TPMLWaveTruncationHint.VeryStrict then
    begin
      if QWord(RiffEnd) < QWord(AFile.Chunk.Position) + AFile.Chunk.Length then
        WaveError('RIFF size truncates chunk');
    end
    else if (FmtChunk.FourCC = FourCC_FMT) and (DataChunk.FourCC = FourCC_DATA) then
      if (AFile.Fact.Status = 1) or (AFile.Options.Fact = TPMLWaveFactHint.Ignore)
        or (AFile.Options.Fact = TPMLWaveFactHint.NoHint) then
        Break;
  end;

  // 最後のチャンクの後ろの位置。RIFF の大きさが分からないときに使う
  LastChunkPos := AFile.Chunk.Position + AFile.Chunk.Length;

  if FmtChunk.FourCC <> FourCC_FMT then
    WaveError('Missing fmt chunk in WAVE file');
  if DataChunk.FourCC <> FourCC_DATA then
    WaveError('Missing data chunk in WAVE file');
  // verystrict では最後のチャンクがすべて揃っているか確かめる（data はあとで）
  if AFile.Options.Truncation = TPMLWaveTruncationHint.VeryStrict then
    if (AFile.Chunk.FourCC <> FourCC_DATA) and (AFile.Chunk.Length > 0) then
    begin
      Pos64 := AFile.Chunk.Position + AFile.Chunk.Length - 1;
      if not SeekTo(AStream, Pos64) then
        WaveError('Could not seek to WAVE chunk data')
      else if ReadSome(AStream, Tmp1, 1) <> 1 then
        WaveError('RIFF size truncates chunk');
    end;

  // fmt チャンクを処理する。今の形式では 1046 バイトより先は要らない
  AFile.Chunk := FmtChunk;
  if WaveReadPartialChunkData(AStream, AFile.Chunk, FmtReadLimit) < 0 then
    WaveError('Could not read data of WAVE fmt chunk');

  // 共通の欄に 14 バイト要る。普通は 16 で、ヘッダと符号化によってもっと大きい
  if AFile.Chunk.Length < 14 then
    WaveError('Invalid WAVE fmt chunk length (too small)')
  else if AFile.Chunk.Size < 14 then
    WaveError('Could not read data of WAVE fmt chunk');
  WaveReadFormat(AFile);
  WaveCheckFormat(AFile, DataChunk.Length);

  AFile.Chunk.Data := nil;
  AFile.Chunk.Size := 0;

  // data チャンクを処理する
  AFile.Chunk := DataChunk;
  if AFile.Chunk.Length > 0 then
    if WaveReadPartialChunkData(AStream, AFile.Chunk, AFile.Chunk.Length) < 0 then
      WaveError('Could not seek data of WAVE data chunk');

  if AFile.Chunk.Length <> AFile.Chunk.Size then
    // 入出力の問題か壊れたファイル。復号側が切り詰めを扱う
    if AFile.Options.Truncation in [TPMLWaveTruncationHint.VeryStrict, TPMLWaveTruncationHint.Strict] then
      WaveError('Could not read data of WAVE data chunk');

  case AFile.Format.Encoding of
    PCM_CODE, IEEE_FLOAT_CODE:
      Result := PCMDecode(AFile);
    ALAW_CODE, MULAW_CODE:
      Result := LAWDecode(AFile);
    MS_ADPCM_CODE:
      Result := MSDecode(AFile);
    IMA_ADPCM_CODE:
      Result := IMADecode(AFile);
  end;

  ASpec.Freq := AFile.Format.Frequency;
  ASpec.Channels := AFile.Format.Channels;
  ASpec.Format := PML_AUDIO_UNKNOWN;
  case AFile.Format.Encoding of
    MS_ADPCM_CODE, IMA_ADPCM_CODE, ALAW_CODE, MULAW_CODE:
      ASpec.Format := PML_AUDIO_S16;   // この機械のバイト順で置ける
    IEEE_FLOAT_CODE:
      ASpec.Format := PML_AUDIO_F32LE;
    PCM_CODE:
      case AFile.Format.BitsPerSample of
        8: ASpec.Format := PML_AUDIO_U8;
        16: ASpec.Format := PML_AUDIO_S16LE;
        24, 32: ASpec.Format := PML_AUDIO_S32LE;   // 24 ビットは 32 ビットに広げた
      else
        WaveError(Format('Unexpected %u-bit PCM data format', [AFile.Format.BitsPerSample]));
      end;
  else
    WaveError('Unexpected data format');
  end;

  // 終わりの位置を呼び出し側へ
  if RiffLengthKnown then
    AFile.Chunk.Position := RiffEnd
  else
    AFile.Chunk.Position := LastChunkPos;
end;

function PMLLoadWAV(AStream: TStream; const AOptions: TPMLWaveOptions;
  out ASpec: TPMLAudioSpec): TBytes;
var
  WaveFile: TWaveFile;
begin
  ASpec := Default(TPMLAudioSpec);
  Result := nil;
  if AStream = nil then
    raise EPMLArgument.Create('Parameter ''AStream'' is invalid');
  WaveFile := Default(TWaveFile);
  WaveFile.Options := AOptions;
  try
    try
      Result := WaveLoad(AStream, WaveFile, ASpec);
    except
      Result := nil;
      ASpec := Default(TPMLAudioSpec);
      raise;
    end;
  finally
    // closeio = false: 最後に読んだチャンクの終わりへ位置を戻す
    AStream.Seek(WaveFile.Chunk.Position, soBeginning);
  end;
end;

function PMLLoadWAV(AStream: TStream; out ASpec: TPMLAudioSpec): TBytes;
begin
  Result := PMLLoadWAV(AStream, TPMLWaveOptions.Defaults, ASpec);
end;

function PMLLoadWAVFile(const APath: String; const AOptions: TPMLWaveOptions;
  out ASpec: TPMLAudioSpec): TBytes;
var
  Stream: TFileStream;
begin
  ASpec := Default(TPMLAudioSpec);
  try
    Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  except
    on E: EFOpenError do
      raise EPMLIOError.Create(E.Message);
  end;
  try
    Result := PMLLoadWAV(Stream, AOptions, ASpec);
  finally
    Stream.Free;
  end;
end;

function PMLLoadWAVFile(const APath: String; out ASpec: TPMLAudioSpec): TBytes;
begin
  Result := PMLLoadWAVFile(APath, TPMLWaveOptions.Defaults, ASpec);
end;

end.
