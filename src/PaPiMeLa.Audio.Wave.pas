{
  PaPiMeLa.Audio.Wave — WAV の読み込み

  Origin : ported from SDL (src/audio/SDL_wave.c, src/audio/SDL_wave.h)
           Scope: RIFF のチャンクの辿り方と、RIFF の大きさ・切り詰め・fact・チャンクの数の
           ヒントの効き方、fmt の解析（拡張ヘッダの GUID を含む）、形式ごとの検査、
           PCM（24 ビットは 32 ビットへ）、IEEE float、A-law・μ-law の展開、
           MS-ADPCM と IMA-ADPCM の復号、読み終えたストリームの位置。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.5、§11 #54

  WHAT:
    TStream から WAV を読み、音声の形式（TPMLAudioSpec）と標本のバイト列を返す
    （SDL_LoadWAV_IO / SDL_LoadWAV）。

  WHY:
    効果音や音楽を外部ライブラリ無しで読める形式が 1 つ要る。

  RESOLVED:
    - 出す形式は SDL と同じ: PCM 8 ビットは U8、16 ビットは S16LE、24 / 32 ビットは S32LE、
      IEEE float（32 ビットだけ）は F32LE、A-law・μ-law・ADPCM は S16
    - 読めなければ EPMLAudioError。読めたらストリームは RIFF の終わり（RIFF の大きさが
      分からなければ最後に見たチャンクの終わり）にある。断ったときの位置は決めない
      （SDL は断っても途中の位置へ動かす）
    - ヒントは引数の TPMLHints で読む（nil なら何も置いていないのと同じ）。papimela は
      大域のヒントの表を持たないので、SDL_GetHint の代わり

  NOT RESOLVED:
    - 3 ビットの IMA-ADPCM、MPEG、IEEE float の 64 ビットは SDL と同じく断る

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Audio.Wave;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Errors,
  PaPiMeLa.Properties,
  PaPiMeLa.Audio.Convert;

{ AStream の今の位置から WAV を読む（SDL_LoadWAV_IO）。標本が無ければ空の配列を返す。
  読めなければ EPMLAudioError。AHints は PML_HINT_WAVE_* を読むのに使い、nil でもよい。 }
function PMLLoadWAV(AStream: TStream; out ASpec: TPMLAudioSpec;
  AHints: TPMLHints = nil): TBytes;
// ファイルから読む（SDL_LoadWAV）。開けなければ EPMLIOError。
function PMLLoadWAVFile(const APath: String; out ASpec: TPMLAudioSpec;
  AHints: TPMLHints = nil): TBytes;

implementation

uses
  PaPiMeLa.IO;

const
  // チャンクの FOURCC（リトルエンディアンで読んだ値）。
  FOURCC_RIFF = $46464952;   // "RIFF"
  FOURCC_WAVE = $45564157;   // "WAVE"
  FOURCC_FACT = $74636166;   // "fact"
  FOURCC_FMT  = $20746D66;   // "fmt "
  FOURCC_DATA = $61746164;   // "data"

  // fmt の形式の番号。
  CODE_UNKNOWN    = $0000;
  CODE_PCM        = $0001;
  CODE_MS_ADPCM   = $0002;
  CODE_IEEE_FLOAT = $0003;
  CODE_ALAW       = $0006;
  CODE_MULAW      = $0007;
  CODE_IMA_ADPCM  = $0011;
  CODE_MPEG       = $0050;
  CODE_MPEGLAYER3 = $0055;
  CODE_EXTENSIBLE = $FFFE;

  DEFAULT_CHUNK_LIMIT = 10000;

type
  TRiffSizeHint   = (NoHint, Force, IgnoreZero, Ignore, Maximum);
  TTruncationHint = (NoHint, VeryStrict, Strict, DropFrame, DropBlock);
  TFactChunkHint  = (NoHint, Truncate, Strict, IgnoreZero, Ignore);

  // fmt の中身（SDL の WaveFormat）。
  TWaveFormat = record
    FormatTag      : Word;      // fmt の最初の欄の値そのもの
    Encoding       : Word;      // 実際の形式（拡張ヘッダなら GUID から）
    Channels       : Word;
    Frequency      : LongWord;
    ByteRate       : LongWord;
    BlockAlign     : Word;
    BitsPerSample  : Word;
    ExtSize        : Word;      // 18 バイト目からの追加の大きさ
    ValidSampleBits: Word;      // 拡張ヘッダ
    SamplesPerBlock: LongWord;  // 圧縮の形式。0 のこともある
    ChannelMask    : LongWord;  // 拡張ヘッダ
    SubFormat      : array[0..15] of Byte;   // 拡張ヘッダの GUID
  end;

  // fact の状態（SDL の WaveFact）。Status: -1 は壊れている、0 は無い、1 は有効、
  // 2 は SampleLength をフレーム数として使う。
  TWaveFact = record
    Status      : Integer;
    SampleLength: LongWord;
  end;

  // チャンク 1 つ（SDL の WaveChunk）。Data は読んだ中身で、Size は実際に読めたバイト数
  // （Length より小さいことがある）。
  TWaveChunk = record
    FourCC  : LongWord;
    Length  : LongWord;
    Position: Int64;      // 中身の始まりのストリームの位置
    Data    : TBytes;
    Size    : SizeInt;
  end;

  // 読み込みの全体の状態（SDL の WaveFile）。
  TWaveFile = record
    Chunk       : TWaveChunk;
    Format      : TWaveFormat;
    Fact        : TWaveFact;
    SampleFrames: Int64;           // 復号するフレーム数
    Coeffs      : array of SmallInt;   // MS-ADPCM の係数の組（2 つずつ）
    RiffHint    : TRiffSizeHint;
    TruncHint   : TTruncationHint;
    FactHint    : TFactChunkHint;
    ChunkLimit  : LongWord;
  end;

  // MS-ADPCM の 1 チャンネルの状態。
  TMSChannelState = record
    Delta : Word;
    Coeff1: SmallInt;
    Coeff2: SmallInt;
  end;

  // ADPCM の復号の状態（SDL の ADPCM_DecoderState）。
  TADPCMState = record
    Channels       : LongWord;
    BlockSize      : SizeInt;   // ブロックのバイト数（nBlockAlign）
    BlockHeaderSize: SizeInt;
    SamplesPerBlock: SizeInt;   // 1 ブロックの 1 チャンネルあたりの標本の数
    FramesTotal    : Int64;
    FramesLeft     : Int64;
    Input          : PByte;     // data チャンクの中身
    InputSize      : SizeInt;
    InputPos       : SizeInt;
    Block          : PByte;     // 今のブロックの始まり（Input の中）
    BlockLen       : SizeInt;   // 今のブロックのバイト数（最後は短いことがある）
    BlockPos       : SizeInt;
    Output         : array of SmallInt;   // 復号した標本（チャンネルが交互に並ぶ）
    OutputPos      : SizeInt;   // 次に書く標本の添字
    MS             : array[0..1] of TMSChannelState;
    IMA            : array of ShortInt;   // チャンネルごとの段の番号
  end;

procedure Fail(const AMsg: String);
begin
  raise EPMLAudioError.Create(AMsg);
end;

{ ---- 1 段目: ヒント・チャンク・fmt・全体の流れ ---- }

// AStream から読めるだけ読む。ACount に届くか Read が 0 以下を返すまで繰り返す。
function TryRead(AStream: TStream; var ABuf; ACount: SizeInt): SizeInt;
var
  Dst: PByte;
  N: LongInt;
begin
  Result := 0;
  if ACount <= 0 then
    Exit;
  Dst := @ABuf;
  while Result < ACount do
  begin
    // TStream.Read の数は LongInt。2 GiB を越える data チャンクは分けて読む
    if ACount - Result > High(LongInt) then
      N := AStream.Read(Dst[Result], High(LongInt))
    else
      N := AStream.Read(Dst[Result], LongInt(ACount - Result));
    if N <= 0 then
      Break;
    Inc(Result, N);
  end;
end;

procedure ReadHints(AHints: TPMLHints; var AFile: TWaveFile);
var
  V: String;
  Value: QWord;
  I: Integer;
  Negative: Boolean;
begin
  AFile.RiffHint := TRiffSizeHint.NoHint;
  AFile.TruncHint := TTruncationHint.NoHint;
  AFile.FactHint := TFactChunkHint.NoHint;
  AFile.ChunkLimit := DEFAULT_CHUNK_LIMIT;
  if AHints = nil then
    Exit;

  V := AHints.GetHint(PML_HINT_WAVE_RIFF_CHUNK_SIZE);
  case V of
    'force': AFile.RiffHint := TRiffSizeHint.Force;
    'ignore': AFile.RiffHint := TRiffSizeHint.Ignore;
    'ignorezero': AFile.RiffHint := TRiffSizeHint.IgnoreZero;
    'maximum': AFile.RiffHint := TRiffSizeHint.Maximum;
  end;

  V := AHints.GetHint(PML_HINT_WAVE_TRUNCATION);
  case V of
    'verystrict': AFile.TruncHint := TTruncationHint.VeryStrict;
    'strict': AFile.TruncHint := TTruncationHint.Strict;
    'dropframe': AFile.TruncHint := TTruncationHint.DropFrame;
    'dropblock': AFile.TruncHint := TTruncationHint.DropBlock;
  end;

  V := AHints.GetHint(PML_HINT_WAVE_FACT_CHUNK);
  case V of
    'truncate': AFile.FactHint := TFactChunkHint.Truncate;
    'strict': AFile.FactHint := TFactChunkHint.Strict;
    'ignorezero': AFile.FactHint := TFactChunkHint.IgnoreZero;
    'ignore': AFile.FactHint := TFactChunkHint.Ignore;
  end;

  // C の sscanf(v, "%u") と同じ読み方。数字が無ければ既定のまま。
  V := AHints.GetHint(PML_HINT_WAVE_CHUNK_LIMIT);
  I := 1;
  while (I <= Length(V)) and (V[I] in [#9, #10, #11, #12, #13, ' ']) do
    Inc(I);
  Negative := (I <= Length(V)) and (V[I] = '-');
  if (I <= Length(V)) and ((V[I] = '+') or (V[I] = '-')) then
    Inc(I);
  if (I > Length(V)) or not (V[I] in ['0'..'9']) then
    Exit;
  Value := 0;
  while (I <= Length(V)) and (V[I] in ['0'..'9']) do
  begin
    if Value < QWord($100000000) then
      Value := Value * 10 + QWord(Ord(V[I]) - Ord('0'));
    if Value > QWord($FFFFFFFF) then
      Value := QWord($FFFFFFFF);
    Inc(I);
  end;
  if Negative then
    Value := (QWord($100000000) - Value) and QWord($FFFFFFFF);
  AFile.ChunkLimit := LongWord(Value);
end;

function NextChunk(AStream: TStream; var AChunk: TWaveChunk): Integer;
var
  NextPos: Int64;
  B: array[0..7] of Byte;

  function LE32(AOff: Integer): LongWord;
  begin
    Result := LongWord(B[AOff]) or (LongWord(B[AOff + 1]) shl 8) or
      (LongWord(B[AOff + 2]) shl 16) or (LongWord(B[AOff + 3]) shl 24);
  end;

begin
  NextPos := AChunk.Position + AChunk.Length;
  AChunk.Data := nil;
  AChunk.Size := 0;
  if (High(Int64) - AChunk.Length < AChunk.Position) or (High(Int64) - 8 < NextPos) then
    Exit(-1);
  // RIFF のチャンクは偶数の大きさに詰めてある
  if (AChunk.Length and 1) <> 0 then
    Inc(NextPos);
  if AStream.Seek(NextPos, soBeginning) <> NextPos then
    Exit(-2);
  if TryRead(AStream, B, 8) < 8 then
    Exit(-1);
  AChunk.FourCC := LE32(0);
  AChunk.Length := LE32(4);
  AChunk.Position := NextPos + 8;
  Result := 0;
end;

function ReadPartialChunkData(AStream: TStream; var AChunk: TWaveChunk; ALength: SizeInt): Integer;
begin
  AChunk.Data := nil;
  AChunk.Size := 0;
  if ALength > AChunk.Length then
    ALength := AChunk.Length;
  Result := 0;
  if ALength > 0 then
  begin
    SetLength(AChunk.Data, ALength);
    if AStream.Seek(AChunk.Position, soBeginning) <> AChunk.Position then
      Exit(-2);
    AChunk.Size := TryRead(AStream, AChunk.Data[0], ALength);
  end;
end;

function ReadChunkData(AStream: TStream; var AChunk: TWaveChunk): Integer;
begin
  Result := ReadPartialChunkData(AStream, AChunk, AChunk.Length);
end;

function AdjustToFactValue(var AFile: TWaveFile; ASampleFrames: Int64): Int64;
begin
  Result := ASampleFrames;
  if AFile.Fact.Status = 2 then
  begin
    if (AFile.FactHint = TFactChunkHint.Strict) and (ASampleFrames < AFile.Fact.SampleLength) then
      Fail('Invalid number of sample frames in WAVE fact chunk (too many)')
    else if ASampleFrames > AFile.Fact.SampleLength then
      Exit(AFile.Fact.SampleLength);
  end;
end;

function GuidEncoding(const AFormat: TWaveFormat): Word;
const
  // GUID の 3 バイト目以降（先頭 2 バイトは形式の番号）
  TAIL: array[0..13] of Byte = (0, 0, 0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113);
  TAGS: array[0..5] of Word = (CODE_PCM, CODE_MS_ADPCM, CODE_IEEE_FLOAT, CODE_ALAW,
    CODE_MULAW, CODE_IMA_ADPCM);
var
  I, K: Integer;
  Same: Boolean;
  Guid: array[0..15] of Byte;
begin
  for I := 0 to High(TAGS) do
  begin
    Guid[0] := Byte(TAGS[I] and $FF);
    Guid[1] := Byte(TAGS[I] shr 8);
    for K := 0 to 13 do
      Guid[K + 2] := TAIL[K];
    Same := True;
    for K := 0 to 15 do
      if Guid[K] <> AFormat.SubFormat[K] then
        Same := False;
    if Same then
      Exit(TAGS[I]);
  end;
  Result := CODE_UNKNOWN;
end;

procedure ReadFormat(var AFile: TWaveFile);
var
  P: PByte;
  FmtLen: SizeInt;
  I: Integer;

  function U16(AOff: Integer): Word;
  begin
    Result := Word(P[AOff]) or (Word(P[AOff + 1]) shl 8);
  end;

  function U32(AOff: Integer): LongWord;
  begin
    Result := LongWord(P[AOff]) or (LongWord(P[AOff + 1]) shl 8) or
      (LongWord(P[AOff + 2]) shl 16) or (LongWord(P[AOff + 3]) shl 24);
  end;

begin
  FmtLen := AFile.Chunk.Size;
  P := @AFile.Chunk.Data[0];
  AFile.Format.FormatTag := U16(0);
  AFile.Format.Encoding := AFile.Format.FormatTag;
  AFile.Format.Channels := U16(2);
  AFile.Format.Frequency := U32(4);
  AFile.Format.ByteRate := U32(8);
  AFile.Format.BlockAlign := U16(12);
  if FmtLen >= 16 then
    AFile.Format.BitsPerSample := U16(14)
  else if AFile.Format.Encoding = CODE_PCM then
    Fail('Missing wBitsPerSample field in WAVE fmt chunk');
  if FmtLen >= 18 then
    AFile.Format.ExtSize := U16(16);
  if AFile.Format.FormatTag = CODE_EXTENSIBLE then
  begin
    if (FmtLen < 40) or (AFile.Format.ExtSize < 22) then
      Fail('Extensible WAVE header too small');
    AFile.Format.ValidSampleBits := U16(18);
    AFile.Format.ChannelMask := U32(20);
    for I := 0 to 15 do
      AFile.Format.SubFormat[I] := P[24 + I];
    AFile.Format.SamplesPerBlock := AFile.Format.ValidSampleBits;
    AFile.Format.Encoding := GuidEncoding(AFile.Format);
  end;
end;

procedure CheckFormat(var AFile: TWaveFile; ADataLength: SizeInt); forward;
function DecodeData(var AFile: TWaveFile): TBytes; forward;

function WaveLoad(AStream: TStream; var AFile: TWaveFile; out ASpec: TPMLAudioSpec): TBytes;
var
  RiffChunk, FmtChunk, DataChunk: TWaveChunk;
  RiffStart, RiffEnd, LastChunkPos, FLen, P: Int64;
  RiffLengthKnown: Boolean;
  ChunkCount: LongWord;
  R: Integer;
  Buf: array[0..3] of Byte;

  function LE32: LongWord;
  begin
    Result := LongWord(Buf[0]) or (LongWord(Buf[1]) shl 8) or
      (LongWord(Buf[2]) shl 16) or (LongWord(Buf[3]) shl 24);
  end;

begin
  ASpec := Default(TPMLAudioSpec);
  Result := nil;
  RiffChunk := Default(TWaveChunk);
  FmtChunk := Default(TWaveChunk);
  DataChunk := Default(TWaveChunk);
  RiffLengthKnown := False;
  ChunkCount := 0;

  FLen := AStream.Size;
  RiffStart := AStream.Position;
  RiffChunk.Position := RiffStart;
  if NextChunk(AStream, RiffChunk) < 0 then
    Fail('Could not read RIFF header');
  if RiffChunk.FourCC = FOURCC_RIFF then
  begin
    if TryRead(AStream, Buf, 4) < 4 then
      Fail('Could not read RIFF form type');
    if LE32 <> FOURCC_WAVE then
      Fail('RIFF form type is not WAVE (not a Waveform file)');
  end
  else if RiffChunk.FourCC = FOURCC_WAVE then
  begin
    RiffChunk.Position := RiffStart; // PORT-NOTE(bug): SDL は 0 を置き、ストリームの途中から読むと位置 4 から探す（D-77）。読み始めの位置を使う
    RiffChunk.Length := 0;
  end
  else
    Fail('Could not find RIFF or WAVE identifiers (not a Waveform file)');

  AFile.Chunk.Position := RiffChunk.Position + 4;
  AFile.Chunk.Length := 0;

  case AFile.RiffHint of
    TRiffSizeHint.Ignore:
      RiffEnd := RiffChunk.Position + $FFFFFFFF;
    TRiffSizeHint.Maximum:
      RiffEnd := High(Int64);
    TRiffSizeHint.Force:
      begin
        RiffEnd := RiffChunk.Position + RiffChunk.Length;
        RiffLengthKnown := True;
      end;
  else
    // NoHint と IgnoreZero: 大きさが 0 なら無いものとして扱う
    if RiffChunk.Length = 0 then
      RiffEnd := RiffChunk.Position + $FFFFFFFF
    else
    begin
      RiffEnd := RiffChunk.Position + RiffChunk.Length;
      RiffLengthKnown := True;
    end;
  end;

  while QWord(RiffEnd) > (QWord(AFile.Chunk.Position) + AFile.Chunk.Length + (AFile.Chunk.Length and 1)) do
  begin
    if ChunkCount >= AFile.ChunkLimit then
      Fail(Format('Chunk count in WAVE file exceeds limit of %u', [AFile.ChunkLimit]));
    Inc(ChunkCount);

    R := NextChunk(AStream, AFile.Chunk);
    if R < 0 then
    begin
      if AFile.TruncHint = TTruncationHint.VeryStrict then
        Fail('Unexpected end of WAVE file');
      Break;
    end;

    if (AFile.Chunk.FourCC = FOURCC_FMT) and (FmtChunk.FourCC <> FOURCC_FMT) then
    begin
      if DataChunk.FourCC = FOURCC_DATA then
        Fail('fmt chunk after data chunk in WAVE file');
      FmtChunk := AFile.Chunk;
    end
    else if AFile.Chunk.FourCC = FOURCC_DATA then
    begin
      if (FLen > 0) and ((AFile.Chunk.Position + AFile.Chunk.Length) > FLen) then
        AFile.Chunk.Length := LongWord(FLen - AFile.Chunk.Position);
      if DataChunk.FourCC <> FOURCC_DATA then
        DataChunk := AFile.Chunk;
    end
    else if AFile.Chunk.FourCC = FOURCC_FACT then
    begin
      if AFile.Fact.Status = 0 then
      begin
        if AFile.Chunk.Length < 4 then
          AFile.Fact.Status := -1
        else if (AStream.Seek(AFile.Chunk.Position, soBeginning) = AFile.Chunk.Position) and
          (TryRead(AStream, Buf, 4) = 4) then
        begin
          AFile.Fact.SampleLength := LE32;
          AFile.Fact.Status := 1;
        end
        else
          AFile.Fact.Status := -1;
      end;
    end;

    if AFile.TruncHint = TTruncationHint.VeryStrict then
    begin
      if QWord(RiffEnd) < (QWord(AFile.Chunk.Position) + AFile.Chunk.Length) then
        Fail('RIFF size truncates chunk');
    end
    else if (FmtChunk.FourCC = FOURCC_FMT) and (DataChunk.FourCC = FOURCC_DATA) then
    begin
      if (AFile.Fact.Status = 1) or (AFile.FactHint = TFactChunkHint.Ignore) or
        (AFile.FactHint = TFactChunkHint.NoHint) then
        Break;
    end;
  end;

  LastChunkPos := AFile.Chunk.Position + AFile.Chunk.Length;
  if FmtChunk.FourCC <> FOURCC_FMT then
    Fail('Missing fmt chunk in WAVE file');
  if DataChunk.FourCC <> FOURCC_DATA then
    Fail('Missing data chunk in WAVE file');

  if (AFile.TruncHint = TTruncationHint.VeryStrict) and (AFile.Chunk.FourCC <> FOURCC_DATA) and
    (AFile.Chunk.Length > 0) then
  begin
    P := AFile.Chunk.Position + AFile.Chunk.Length - 1;
    if AStream.Seek(P, soBeginning) <> P then
      Fail('Could not seek to WAVE chunk data')
    else if TryRead(AStream, Buf, 1) <> 1 then
      Fail('RIFF size truncates chunk');
  end;

  AFile.Chunk := FmtChunk;
  if ReadPartialChunkData(AStream, AFile.Chunk, 1046) < 0 then
    Fail('Could not read data of WAVE fmt chunk');
  if AFile.Chunk.Length < 14 then
    Fail('Invalid WAVE fmt chunk length (too small)')
  else if AFile.Chunk.Size < 14 then
    Fail('Could not read data of WAVE fmt chunk');
  ReadFormat(AFile);
  CheckFormat(AFile, DataChunk.Length);

  AFile.Chunk := DataChunk;
  if AFile.Chunk.Length > 0 then
    if ReadChunkData(AStream, AFile.Chunk) < 0 then
      Fail('Could not seek data of WAVE data chunk');
  if (AFile.Chunk.Length <> AFile.Chunk.Size) and
    ((AFile.TruncHint = TTruncationHint.VeryStrict) or (AFile.TruncHint = TTruncationHint.Strict)) then
    Fail('Could not read data of WAVE data chunk');

  Result := DecodeData(AFile);

  ASpec.Freq := Integer(AFile.Format.Frequency);
  ASpec.Channels := AFile.Format.Channels;
  case AFile.Format.Encoding of
    CODE_MS_ADPCM, CODE_IMA_ADPCM, CODE_ALAW, CODE_MULAW:
      ASpec.Format := PML_AUDIO_S16;
    CODE_IEEE_FLOAT:
      ASpec.Format := PML_AUDIO_F32LE;
    CODE_PCM:
      case AFile.Format.BitsPerSample of
        8: ASpec.Format := PML_AUDIO_U8;
        16: ASpec.Format := PML_AUDIO_S16LE;
        24, 32: ASpec.Format := PML_AUDIO_S32LE;
      else
        Fail(Format('Unexpected %u-bit PCM data format', [AFile.Format.BitsPerSample]));
      end;
  else
    Fail('Unexpected data format');
  end;

  if RiffLengthKnown then
    AFile.Chunk.Position := RiffEnd
  else
    AFile.Chunk.Position := LastChunkPos;
end;

{ ---- 2 段目: PCM・IEEE float・A-law・μ-law ---- }

// 厳密な切り詰めの検査（PCM と A-law・μ-law で共通）。
procedure CheckStrictTruncation(const AFile: TWaveFile; ADataLength: SizeInt);
begin
  if (AFile.TruncHint = TTruncationHint.VeryStrict) or (AFile.TruncHint = TTruncationHint.Strict) then
    if (AFile.Format.BlockAlign > 1) and ((ADataLength mod AFile.Format.BlockAlign) <> 0) then
      Fail('Truncated data chunk in WAVE file');
end;

procedure PCMInit(var AFile: TWaveFile; ADataLength: SizeInt);
begin
  if AFile.Format.Encoding = CODE_PCM then
  begin
    case AFile.Format.BitsPerSample of
      8, 16, 24, 32: ;
    else
      Fail(Format('%u-bit PCM format not supported', [AFile.Format.BitsPerSample]));
    end;
  end
  else if AFile.Format.Encoding = CODE_IEEE_FLOAT then
  begin
    if AFile.Format.BitsPerSample <> 32 then
      Fail(Format('%u-bit IEEE floating-point format not supported', [AFile.Format.BitsPerSample]));
  end;

  // 1 フレームのビット数が nBlockAlign の整数倍か（SDL と同じく、フレームより小さい nBlockAlign も通す）
  if ((LongWord(AFile.Format.Channels) * AFile.Format.BitsPerSample) mod
    (LongWord(AFile.Format.BlockAlign) * 8)) <> 0 then
    Fail('Unsupported block alignment');

  CheckStrictTruncation(AFile, ADataLength);

  AFile.SampleFrames := AdjustToFactValue(AFile, ADataLength div AFile.Format.BlockAlign);
end;

function PCMDecode(var AFile: TWaveFile): TBytes;
var
  Count, OutLen: Int64;
  I: SizeInt;
begin
  Result := nil;
  if AFile.Chunk.Length <> AFile.Chunk.Size then
    AFile.SampleFrames := AdjustToFactValue(AFile, AFile.Chunk.Size div AFile.Format.BlockAlign);
  if AFile.SampleFrames = 0 then
    Exit;

  if (AFile.Format.Encoding = CODE_PCM) and (AFile.Format.BitsPerSample = 24) then
  begin
    // PORT-NOTE(bug): SDL は SampleFrames * Channels を数え、nBlockAlign がフレームより小さいと data の後ろを読む（D-79）。data にある標本だけを数える
    Count := (AFile.SampleFrames * AFile.Format.BlockAlign) div 3;
    if Count * 4 > $FFFFFFFF then
      Fail('WAVE file too big');
    SetLength(Result, Count * 4);
    for I := 0 to SizeInt(Count) - 1 do
    begin
      Result[I * 4] := 0;
      Result[I * 4 + 1] := AFile.Chunk.Data[I * 3];
      Result[I * 4 + 2] := AFile.Chunk.Data[I * 3 + 1];
      Result[I * 4 + 3] := AFile.Chunk.Data[I * 3 + 2];
    end;
  end
  else
  begin
    OutLen := AFile.SampleFrames * AFile.Format.BlockAlign;
    if OutLen > $FFFFFFFF then
      Fail('WAVE file too big');
    Result := Copy(AFile.Chunk.Data, 0, SizeInt(OutLen));
  end;

  // データは結果へ移った
  AFile.Chunk.Data := nil;
  AFile.Chunk.Size := 0;
end;

procedure LawInit(var AFile: TWaveFile; ADataLength: SizeInt);
begin
  if AFile.Format.BitsPerSample <> 8 then
    Fail(Format('Invalid companded bits per sample of %u', [AFile.Format.BitsPerSample]));
  if AFile.Format.BlockAlign <> AFile.Format.Channels then
    Fail('Unsupported block alignment');

  CheckStrictTruncation(AFile, ADataLength);

  AFile.SampleFrames := AdjustToFactValue(AFile, ADataLength div AFile.Format.BlockAlign);
end;

function LawDecode(var AFile: TWaveFile): TBytes;
var
  Count, OutLen: Int64;
  I: SizeInt;
  B: Byte;
  V: Integer;
  Exponent, Mantissa, N, Step: Integer;
begin
  Result := nil;
  if AFile.Chunk.Length <> AFile.Chunk.Size then
    AFile.SampleFrames := AdjustToFactValue(AFile, AFile.Chunk.Size div AFile.Format.BlockAlign);
  if AFile.SampleFrames = 0 then
    Exit;

  // 復号の形式は、標本を読む前に決める（SDL は同じ検査を変換の直前に行う）
  if (AFile.Format.Encoding <> CODE_ALAW) and (AFile.Format.Encoding <> CODE_MULAW) then
    Fail('Unknown companded encoding');

  Count := AFile.SampleFrames * AFile.Format.Channels;
  OutLen := Count * 2;
  if OutLen > $FFFFFFFF then
    Fail('WAVE file too big');
  SetLength(Result, OutLen);

  for I := 0 to SizeInt(Count) - 1 do
  begin
    B := AFile.Chunk.Data[I];
    if AFile.Format.Encoding = CODE_ALAW then
    begin
      Exponent := (B and $7F) xor $55;
      Mantissa := Exponent and $F;
      Exponent := Exponent shr 4;
      if Exponent > 0 then
        Mantissa := Mantissa or $10;
      Mantissa := (Mantissa shl 4) or $8;
      if Exponent > 1 then
        Mantissa := Mantissa shl (Exponent - 1);
      if (B and $80) <> 0 then
        V := Mantissa
      else
        V := -Mantissa;
    end
    else
    begin
      N := (not B) and $FF;
      Mantissa := N and $F;
      Exponent := (N shr 4) and $7;
      Step := 4 shl (Exponent + 1);
      Mantissa := ($80 shl Exponent) + (Step * Mantissa) + (Step div 2) - 132;
      if (N and $80) <> 0 then
        V := -Mantissa
      else
        V := Mantissa;
    end;
    Result[I * 2] := Byte(V and $FF);
    Result[I * 2 + 1] := Byte((V shr 8) and $FF);
  end;

  // データは結果へ移った
  AFile.Chunk.Data := nil;
  AFile.Chunk.Size := 0;
end;

{ ---- 3 段目: MS-ADPCM と IMA-ADPCM ---- }

procedure MSCalculateSampleFrames(var AFile: TWaveFile; ADataLength: SizeInt);
begin
end;

procedure MSInit(var AFile: TWaveFile; ADataLength: SizeInt);
begin
end;

function MSProcessNibble(var AState: TMSChannelState; ASample1, ASample2: LongInt;
  ANybble: Byte): SmallInt;
begin
  Result := 0;
end;

procedure MSDecodeBlockHeader(var AState: TADPCMState; const AFile: TWaveFile);
begin
end;

function MSDecodeBlockData(var AState: TADPCMState): Boolean;
begin
  Result := False;
end;

function MSDecode(var AFile: TWaveFile): TBytes;
begin
  Result := nil;
end;

procedure IMACalculateSampleFrames(var AFile: TWaveFile; ADataLength: SizeInt);
begin
end;

procedure IMAInit(var AFile: TWaveFile; ADataLength: SizeInt);
begin
end;

function IMAProcessNibble(var AIndex: ShortInt; ALastSample: SmallInt; ANybble: Byte): SmallInt;
begin
  Result := 0;
end;

procedure IMADecodeBlockHeader(var AState: TADPCMState);
begin
end;

function IMADecodeBlockData(var AState: TADPCMState): Boolean;
begin
  Result := False;
end;

function IMADecode(var AFile: TWaveFile): TBytes;
begin
  Result := nil;
end;

{ ---- 形式ごとへの振り分け（1 段目） ---- }

procedure CheckFormat(var AFile: TWaveFile; ADataLength: SizeInt);
var
  Enc: Word;
  NonPcm: Boolean;
  Digits: String;
  I: Integer;
begin
  Enc := AFile.Format.Encoding;
  if AFile.Format.Channels = 0 then
    Fail('Invalid number of channels');
  if AFile.Format.Frequency = 0 then
    Fail('Invalid sample rate')
  else if AFile.Format.Frequency > 2147483647 then
    Fail('Sample rate exceeds limit of 2147483647');
  if (AFile.FactHint = TFactChunkHint.Strict) and (AFile.Fact.Status = -1) then
    Fail('Invalid fact chunk in WAVE file');

  NonPcm := (Enc = CODE_IEEE_FLOAT) or (Enc = CODE_ALAW) or (Enc = CODE_MULAW) or
    (Enc = CODE_MS_ADPCM) or (Enc = CODE_IMA_ADPCM);
  if NonPcm and (AFile.FactHint = TFactChunkHint.Strict) and (AFile.Fact.Status <= 0) then
    Fail('Missing fact chunk in WAVE file');

  if NonPcm or (Enc = CODE_PCM) then
  begin
    if AFile.Chunk.Size < 16 then
      Fail('Missing wBitsPerSample field in WAVE fmt chunk')
    else if AFile.Format.BitsPerSample = 0 then
      Fail('Invalid bits per sample');
    if AFile.Format.BlockAlign = 0 then
      AFile.Format.BlockAlign := 1;
    if (AFile.Fact.Status = 1) and ((AFile.FactHint = TFactChunkHint.Truncate) or
      (AFile.FactHint = TFactChunkHint.Strict) or
      ((AFile.FactHint = TFactChunkHint.IgnoreZero) and (AFile.Fact.SampleLength > 0))) then
      AFile.Fact.Status := 2;
  end;

  case Enc of
    CODE_PCM, CODE_IEEE_FLOAT:
      PCMInit(AFile, ADataLength);
    CODE_ALAW, CODE_MULAW:
      LawInit(AFile, ADataLength);
    CODE_MS_ADPCM:
      MSInit(AFile, ADataLength);
    CODE_IMA_ADPCM:
      IMAInit(AFile, ADataLength);
    CODE_MPEG, CODE_MPEGLAYER3:
      Fail('MPEG formats not supported');
  else
    if AFile.Format.FormatTag = CODE_EXTENSIBLE then
    begin
      Digits := '';
      for I := 0 to 15 do
        Digits := Digits + LowerCase(IntToHex(AFile.Format.SubFormat[I], 2));
      Fail('Unknown WAVE format GUID: ' + Digits);
    end
    else
      Fail(Format('Unknown WAVE format tag: 0x%.4x', [Enc]));
  end;
end;

function DecodeData(var AFile: TWaveFile): TBytes;
begin
  Result := nil;
  case AFile.Format.Encoding of
    CODE_PCM, CODE_IEEE_FLOAT: Result := PCMDecode(AFile);
    CODE_ALAW, CODE_MULAW: Result := LawDecode(AFile);
    CODE_MS_ADPCM: Result := MSDecode(AFile);
    CODE_IMA_ADPCM: Result := IMADecode(AFile);
  end;
end;

{ ---- 公開 ---- }

function PMLLoadWAV(AStream: TStream; out ASpec: TPMLAudioSpec; AHints: TPMLHints): TBytes;
var
  F: TWaveFile;
  P: Int64;
begin
  F := Default(TWaveFile);
  ReadHints(AHints, F);
  Result := WaveLoad(AStream, F, ASpec);
  // SDL のメモリストリームと同じく、終わりを越える位置へは動かさない
  P := F.Chunk.Position;
  if P > AStream.Size then
    P := AStream.Size;
  AStream.Position := P;
end;

function PMLLoadWAVFile(const APath: String; out ASpec: TPMLAudioSpec; AHints: TPMLHints): TBytes;
var
  S: TPMLFileStream;
begin
  S := TPMLFileStream.Create(APath);
  try
    Result := PMLLoadWAV(S, ASpec, AHints);
  finally
    S.Free;
  end;
end;

end.
