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

// リトルエンディアンの符号付き 16 ビットを読む。AP[AOff] が下位、AP[AOff + 1] が上位。
function S16LE(AP: PByte; AOff: SizeInt): LongInt;
begin
  Result := LongInt(AP[AOff]) or (LongInt(AP[AOff + 1]) shl 8);
  if Result >= $8000 then
    Result := Result - $10000;
end;

procedure MSCalculateSampleFrames(var AFile: TWaveFile; ADataLength: SizeInt);
var
  Ch, HeaderSize, Avail, FrameBits, Trailing: SizeInt;
  TS: Int64;
begin
  Ch := SizeInt(AFile.Format.Channels);
  HeaderSize := Ch * 7;
  Avail := ADataLength div SizeInt(AFile.Format.BlockAlign);
  FrameBits := SizeInt(AFile.Format.BitsPerSample) * Ch;
  Trailing := ADataLength mod SizeInt(AFile.Format.BlockAlign);

  if (AFile.TruncHint = TTruncationHint.VeryStrict) or (AFile.TruncHint = TTruncationHint.Strict) then
  begin
    if (ADataLength < HeaderSize) or (Trailing > 0) then
      Fail('Truncated MS ADPCM block');
  end;

  AFile.SampleFrames := Int64(Avail) * AFile.Format.SamplesPerBlock;

  if (Trailing > 0) and (AFile.TruncHint = TTruncationHint.DropFrame) and (Trailing >= HeaderSize) then
  begin
    TS := 2 + (((Trailing - HeaderSize) * 8) div FrameBits);
    if TS > Int64(AFile.Format.SamplesPerBlock) then
      TS := Int64(AFile.Format.SamplesPerBlock);
    AFile.SampleFrames := AFile.SampleFrames + TS;
  end;

  AFile.SampleFrames := AdjustToFactValue(AFile, AFile.SampleFrames);
end;

procedure MSInit(var AFile: TWaveFile; ADataLength: SizeInt);
const
  PRESET: array[0..13] of LongInt = (256, 0, 512, -256, 0, 0, 192, 64, 240, 0, 460, -208, 392, -232);
var
  Ch, HeaderSize, CoeffCount, I: SizeInt;
  V: LongInt;
  BlockDataSamples: Int64;
  P: PByte;
begin
  if AFile.Format.Channels > 2 then
    Fail('Invalid number of channels');
  if AFile.Format.BitsPerSample <> 4 then
    Fail(Format('Invalid MS ADPCM bits per sample of %u', [AFile.Format.BitsPerSample]));

  Ch := SizeInt(AFile.Format.Channels);
  HeaderSize := Ch * 7;
  if SizeInt(AFile.Format.BlockAlign) < HeaderSize then
    Fail('Invalid MS ADPCM block size (nBlockAlign)');

  if AFile.Format.FormatTag = CODE_EXTENSIBLE then
    Fail('MS ADPCM with the extensible header is not supported');

  if AFile.Chunk.Size < 22 then
    Fail('Could not read MS ADPCM format header');

  P := @AFile.Chunk.Data[0];
  AFile.Format.SamplesPerBlock := LongWord(P[18]) or (LongWord(P[19]) shl 8);
  CoeffCount := SizeInt(P[20]) or (SizeInt(P[21]) shl 8);
  if CoeffCount > 256 then
    CoeffCount := 256;

  if AFile.Chunk.Size < 22 + CoeffCount * 4 then
    Fail('Could not read custom coefficients in MS ADPCM format header')
  else if SizeInt(AFile.Format.ExtSize) < 4 + CoeffCount * 4 then
    Fail('Invalid MS ADPCM format header (too small)')
  else if CoeffCount < 7 then
    Fail('Missing required coefficients in MS ADPCM format header');

  SetLength(AFile.Coeffs, CoeffCount * 2);
  for I := 0 to CoeffCount * 2 - 1 do
  begin
    V := S16LE(P, 22 + I * 2);
    if I < 14 then
    begin
      if V <> PRESET[I] then
        Fail('Wrong preset coefficients in MS ADPCM format header');
    end;
    AFile.Coeffs[I] := SmallInt(V);
  end;

  BlockDataSamples := ((Int64(AFile.Format.BlockAlign) - HeaderSize) * 8) div
    (Int64(AFile.Format.BitsPerSample) * Ch);
  if AFile.Format.SamplesPerBlock = 0 then
    AFile.Format.SamplesPerBlock := LongWord(BlockDataSamples + 2);

  if (AFile.Format.SamplesPerBlock = 1) or
    (BlockDataSamples < (Int64(AFile.Format.SamplesPerBlock) - 2)) then
    Fail('Invalid number of samples per MS ADPCM block (wSamplesPerBlock)');

  MSCalculateSampleFrames(AFile, ADataLength);
end;

function MSProcessNibble(var AState: TMSChannelState; ASample1, ASample2: LongInt;
  ANybble: Byte): SmallInt;
const
  ADAPTIVE: array[0..15] of LongWord = (230, 230, 230, 230, 307, 409, 512, 614,
    768, 614, 512, 409, 307, 230, 230, 230);
  MAX_AUDIOVAL = 32767;
  MIN_AUDIOVAL = -32768;
var
  NewSample, ErrorDelta: LongInt;
  DeltaW: LongWord;
begin
  // 係数はファイルが決めるので、2 つの積の和は LongInt を越えうる（-32768 * -32768 * 2）
  NewSample := LongInt(((Int64(ASample1) * AState.Coeff1) + (Int64(ASample2) * AState.Coeff2)) div 256);

  // ニブルは符号付き 4 ビットの誤差
  if ANybble >= 8 then
    ErrorDelta := LongInt(ANybble) - 16
  else
    ErrorDelta := LongInt(ANybble);
  NewSample := NewSample + (LongInt(AState.Delta) * ErrorDelta);
  if NewSample < MIN_AUDIOVAL then
    NewSample := MIN_AUDIOVAL
  else if NewSample > MAX_AUDIOVAL then
    NewSample := MAX_AUDIOVAL;

  DeltaW := (LongWord(AState.Delta) * ADAPTIVE[ANybble]) div 256;
  if DeltaW < 16 then
    DeltaW := 16
  else if DeltaW > 65535 then
    DeltaW := 65535;
  AState.Delta := Word(DeltaW);

  Result := SmallInt(NewSample);
end;

procedure MSDecodeBlockHeader(var AState: TADPCMState; const AFile: TWaveFile);
var
  Ch, Chan, Idx: SizeInt;
  V: LongInt;
begin
  Ch := SizeInt(AState.Channels);
  for Chan := 0 to Ch - 1 do
  begin
    Idx := AState.Block[Chan];
    // PORT-NOTE(bug): SDL は > で比べ、番号が係数の数と等しいと表の外を読む（D-73）
    if Idx >= (Length(AFile.Coeffs) div 2) then
      Fail('Invalid MS ADPCM coefficient index in block header');
    AState.MS[Chan].Coeff1 := AFile.Coeffs[Idx * 2];
    AState.MS[Chan].Coeff2 := AFile.Coeffs[Idx * 2 + 1];

    AState.MS[Chan].Delta := Word(AState.Block[Ch + Chan * 2]) or
      (Word(AState.Block[Ch + Chan * 2 + 1]) shl 8);

    // 見出しの標本は、出力の後ろに来るものが先に入っている
    V := S16LE(AState.Block, Ch * 3 + Chan * 2);
    AState.Output[AState.OutputPos + Ch] := SmallInt(V);
    V := S16LE(AState.Block, Ch * 5 + Chan * 2);
    AState.Output[AState.OutputPos] := SmallInt(V);
    Inc(AState.OutputPos);
  end;

  AState.BlockPos := AState.BlockPos + AState.BlockHeaderSize;
  AState.OutputPos := AState.OutputPos + Ch;
  AState.FramesLeft := AState.FramesLeft - 2;
end;

function MSDecodeBlockData(var AState: TADPCMState): Boolean;
var
  Ch, BlockPos, OutPos, Chan: SizeInt;
  Nybble: Word;
  BlockFramesLeft: Int64;
  S1, S2: LongInt;
begin
  Ch := SizeInt(AState.Channels);
  Nybble := 0;
  BlockPos := AState.BlockPos;
  OutPos := AState.OutputPos;
  BlockFramesLeft := Int64(AState.SamplesPerBlock) - 2;
  if BlockFramesLeft > AState.FramesLeft then
    BlockFramesLeft := AState.FramesLeft;

  while BlockFramesLeft > 0 do
  begin
    for Chan := 0 to Ch - 1 do
    begin
      if (Nybble and $4000) <> 0 then
        Nybble := Word(Nybble shl 4)
      else if BlockPos < AState.BlockLen then
      begin
        Nybble := Word(AState.Block[BlockPos]) or $4000;
        Inc(BlockPos);
      end
      else
      begin
        // 入力が尽きた。中途半端なフレームは捨てて戻る
        AState.OutputPos := OutPos - Chan;
        Exit(False);
      end;

      S1 := AState.Output[OutPos - Ch];
      S2 := AState.Output[OutPos - Ch * 2];
      AState.Output[OutPos] := MSProcessNibble(AState.MS[Chan], S1, S2, (Nybble shr 4) and $F);
      Inc(OutPos);
    end;
    AState.FramesLeft := AState.FramesLeft - 1;
    BlockFramesLeft := BlockFramesLeft - 1;
  end;

  AState.OutputPos := OutPos;
  Result := True;
end;

function MSDecode(var AFile: TWaveFile): TBytes;
var
  St: TADPCMState;
  Ch, BytesLeft: SizeInt;
  OutBytes: Int64;
begin
  Result := nil;
  if AFile.Chunk.Length <> AFile.Chunk.Size then
    MSCalculateSampleFrames(AFile, AFile.Chunk.Size);
  if AFile.SampleFrames = 0 then
    Exit;

  Ch := SizeInt(AFile.Format.Channels);
  St := Default(TADPCMState);
  St.Channels := AFile.Format.Channels;
  St.BlockSize := AFile.Format.BlockAlign;
  St.BlockHeaderSize := Ch * 7;
  St.SamplesPerBlock := AFile.Format.SamplesPerBlock;
  St.FramesTotal := AFile.SampleFrames;
  St.FramesLeft := St.FramesTotal;
  St.Input := @AFile.Chunk.Data[0];
  St.InputSize := AFile.Chunk.Size;
  St.InputPos := 0;

  OutBytes := St.FramesTotal * Ch * 2;
  if OutBytes > $FFFFFFFF then
    Fail('WAVE file too big');

  // PORT-NOTE(bug): 見出しは必ず 2 フレームを書くので、2 フレーム余分に取る。SDL は残りのフレーム数の分しか取らず、fact で切ると置き場の外へ書く（D-74）
  SetLength(St.Output, SizeInt((St.FramesTotal + 2) * Ch));

  BytesLeft := St.InputSize - St.InputPos;
  while (St.FramesLeft > 0) and (BytesLeft >= St.BlockHeaderSize) do
  begin
    St.Block := PByte(PtrUInt(St.Input) + PtrUInt(St.InputPos));
    if BytesLeft < St.BlockSize then
      St.BlockLen := BytesLeft
    else
      St.BlockLen := St.BlockSize;
    St.BlockPos := 0;

    if (Length(St.Output) - St.OutputPos) < (St.FramesLeft * Ch) then
      Fail('Unexpected overflow in MS ADPCM decoder');

    MSDecodeBlockHeader(St, AFile);
    if not MSDecodeBlockData(St) then
    begin
      if (AFile.TruncHint = TTruncationHint.VeryStrict) or (AFile.TruncHint = TTruncationHint.Strict) then
        Fail('Truncated data chunk')
      else if AFile.TruncHint <> TTruncationHint.DropFrame then
        St.OutputPos := St.OutputPos - (St.OutputPos mod (St.SamplesPerBlock * Ch));
      OutBytes := St.OutputPos * 2;
      Break;
    end;

    St.InputPos := St.InputPos + St.BlockLen;
    BytesLeft := St.InputSize - St.InputPos;
  end;

  // 出力の型は、リトルエンディアンの機械の上で S16 のまま渡す
  SetLength(Result, SizeInt(OutBytes));
  if OutBytes > 0 then
    Move(St.Output[0], Result[0], SizeInt(OutBytes));
end;

procedure IMACalculateSampleFrames(var AFile: TWaveFile; ADataLength: SizeInt);
var
  Ch, HeaderSize, SubFrame, Avail, Trailing, TBD, TSD: SizeInt;
  TS: Int64;
begin
  Ch := SizeInt(AFile.Format.Channels);
  HeaderSize := Ch * 4;
  SubFrame := Ch * 4;
  Avail := ADataLength div SizeInt(AFile.Format.BlockAlign);
  Trailing := ADataLength mod SizeInt(AFile.Format.BlockAlign);

  if (AFile.TruncHint = TTruncationHint.VeryStrict) or (AFile.TruncHint = TTruncationHint.Strict) then
  begin
    if (ADataLength < HeaderSize) or (Trailing > 0) then
      Fail('Truncated IMA ADPCM block');
  end;

  AFile.SampleFrames := Int64(Avail) * AFile.Format.SamplesPerBlock;

  // PORT-NOTE(bug): SDL は Trailing > HeaderSize - 2 で見出しの 1 フレームを数えるが、見出しが全部無いブロックは復号しないので、書かないフレームを返す（D-78）
  if (Trailing > 0) and (AFile.TruncHint = TTruncationHint.DropFrame) and (Trailing >= HeaderSize) then
  begin
    TS := 1;
    if Trailing > HeaderSize then
    begin
      TBD := Trailing - HeaderSize;
      TSD := TBD mod SubFrame;
      TS := TS + ((TBD div SubFrame) * 8);
      if TSD > (SubFrame - 4) then
        TS := TS + ((TSD mod 4) * 2);
    end;
    if TS > Int64(AFile.Format.SamplesPerBlock) then
      TS := Int64(AFile.Format.SamplesPerBlock);
    AFile.SampleFrames := AFile.SampleFrames + TS;
  end;

  AFile.SampleFrames := AdjustToFactValue(AFile, AFile.SampleFrames);
end;

procedure IMAInit(var AFile: TWaveFile; ADataLength: SizeInt);
var
  Ch, HeaderSize: SizeInt;
  BlockDataSamples: Int64;
begin
  if AFile.Format.BitsPerSample = 3 then
    Fail('3-bit IMA ADPCM currently not supported')
  else if AFile.Format.BitsPerSample <> 4 then
    Fail(Format('Invalid IMA ADPCM bits per sample of %u', [AFile.Format.BitsPerSample]));

  Ch := SizeInt(AFile.Format.Channels);
  HeaderSize := Ch * 4;
  if (SizeInt(AFile.Format.BlockAlign) < HeaderSize) or ((AFile.Format.BlockAlign mod 4) <> 0) then
    Fail('Invalid IMA ADPCM block size (nBlockAlign)');

  // 拡張ヘッダの wValidBitsPerSample は、stage 1 が SamplesPerBlock に入れてある
  if AFile.Format.FormatTag <> CODE_EXTENSIBLE then
  begin
    if (AFile.Chunk.Size >= 20) and (AFile.Format.ExtSize >= 2) then
      AFile.Format.SamplesPerBlock := LongWord(AFile.Chunk.Data[18]) or
        (LongWord(AFile.Chunk.Data[19]) shl 8);
  end;

  BlockDataSamples := ((Int64(AFile.Format.BlockAlign) - HeaderSize) * 8) div
    (Int64(AFile.Format.BitsPerSample) * Ch);
  if AFile.Format.SamplesPerBlock = 0 then
    AFile.Format.SamplesPerBlock := LongWord(BlockDataSamples + 1);

  if BlockDataSamples < (Int64(AFile.Format.SamplesPerBlock) - 1) then
    Fail('Invalid number of samples per IMA ADPCM block (wSamplesPerBlock)');

  IMACalculateSampleFrames(AFile, ADataLength);
end;

function IMAProcessNibble(var AIndex: ShortInt; ALastSample: SmallInt; ANybble: Byte): SmallInt;
const
  INDEX_TABLE: array[0..15] of ShortInt = (-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8);
  STEP_TABLE: array[0..88] of LongInt = (
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
    34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
    157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658,
    724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024,
    3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
    15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767
  );
  MAX_AUDIOVAL = 32767;
  MIN_AUDIOVAL = -32768;
var
  Index: Integer;
  Step, Delta, Sample: LongInt;
begin
  Index := AIndex;
  if Index > 88 then
    Index := 88
  else if Index < 0 then
    Index := 0;

  Step := STEP_TABLE[Index];
  AIndex := ShortInt(Index + INDEX_TABLE[ANybble]);

  Delta := Step shr 3;
  if (ANybble and 4) <> 0 then
    Delta := Delta + Step;
  if (ANybble and 2) <> 0 then
    Delta := Delta + (Step shr 1);
  if (ANybble and 1) <> 0 then
    Delta := Delta + (Step shr 2);
  if (ANybble and 8) <> 0 then
    Delta := -Delta;

  Sample := LongInt(ALastSample) + Delta;
  if Sample > MAX_AUDIOVAL then
    Sample := MAX_AUDIOVAL
  else if Sample < MIN_AUDIOVAL then
    Sample := MIN_AUDIOVAL;
  Result := SmallInt(Sample);
end;

procedure IMADecodeBlockHeader(var AState: TADPCMState);
var
  Ch, Chan, O: SizeInt;
  Idx: LongInt;
begin
  Ch := SizeInt(AState.Channels);
  for Chan := 0 to Ch - 1 do
  begin
    O := AState.BlockPos + Chan * 4;
    AState.Output[AState.OutputPos] := SmallInt(S16LE(AState.Block, O));
    Inc(AState.OutputPos);

    // 段の番号は符号付き 8 ビット。O + 3 の予約のバイトは読まない
    Idx := AState.Block[O + 2];
    if Idx > 127 then
      Idx := Idx - 256;
    AState.IMA[Chan] := ShortInt(Idx);
  end;

  AState.BlockPos := AState.BlockPos + AState.BlockHeaderSize;
  AState.FramesLeft := AState.FramesLeft - 1;
end;

function IMADecodeBlockData(var AState: TADPCMState): Boolean;
var
  Ch, SubFrame, BlockLeft, OutPos, Remain, Chan, P, Sub, I: SizeInt;
  Avail, BlockFramesLeft, BytesRequired: Int64;
  Nyb: Byte;
  Sample: SmallInt;
begin
  Ch := SizeInt(AState.Channels);
  SubFrame := Ch * 4;
  BlockLeft := AState.BlockLen - AState.BlockPos;
  OutPos := AState.OutputPos;
  Result := True;

  BlockFramesLeft := Int64(AState.SamplesPerBlock) - 1;
  if BlockFramesLeft > AState.FramesLeft then
    BlockFramesLeft := AState.FramesLeft;

  BytesRequired := ((BlockFramesLeft + 7) div 8) * SubFrame;
  if BlockLeft < BytesRequired then
  begin
    // データが足りない。取り出せるフレームの数を数え直す
    Avail := (BlockLeft div SubFrame) * 8;
    // PORT-NOTE(bug): SDL は部分ブロックの数をそのままフレームの数にしている。* 8 が無い（D-75）
    Remain := BlockLeft mod SubFrame;
    if Remain > (SubFrame - 4) then
      Avail := Avail + ((Remain mod 4) * 2);
    // PORT-NOTE(bug): 頼まれた数を超えて復号しない。SDL はこの上限を置かず、fact で残りが少ないと置き場の外へ書く（D-80）
    if Avail < BlockFramesLeft then
      BlockFramesLeft := Avail;
    Result := False;
  end;

  while BlockFramesLeft > 0 do
  begin
    if BlockFramesLeft < 8 then
      Sub := SizeInt(BlockFramesLeft)
    else
      Sub := 8;

    for Chan := 0 to Ch - 1 do
    begin
      // PORT-NOTE(bug): チャンネルごとに自分の 4 バイトから読む。SDL は続けて読むので、8 フレームに満たない部分ブロックで 2 つ目からのチャンネルが前のチャンネルのバイトを読む（D-76）
      P := AState.BlockPos + Chan * 4;
      Nyb := 0;
      // 見出しの標本か、前の副ブロックの最後の標本
      Sample := AState.Output[OutPos + Chan - Ch];
      for I := 0 to Sub - 1 do
      begin
        if Odd(I) then
          Nyb := Nyb shr 4
        else
        begin
          Nyb := AState.Block[P];
          Inc(P);
        end;
        Sample := IMAProcessNibble(AState.IMA[Chan], Sample, Nyb and $F);
        AState.Output[OutPos + Chan + I * Ch] := Sample;
      end;
    end;

    AState.BlockPos := AState.BlockPos + SubFrame;
    OutPos := OutPos + Ch * Sub;
    AState.FramesLeft := AState.FramesLeft - Sub;
    BlockFramesLeft := BlockFramesLeft - Sub;
  end;

  AState.OutputPos := OutPos;
end;

function IMADecode(var AFile: TWaveFile): TBytes;
var
  St: TADPCMState;
  Ch, BytesLeft: SizeInt;
  OutBytes: Int64;
begin
  Result := nil;
  if AFile.Chunk.Length <> AFile.Chunk.Size then
    IMACalculateSampleFrames(AFile, AFile.Chunk.Size);
  if AFile.SampleFrames = 0 then
    Exit;

  Ch := SizeInt(AFile.Format.Channels);
  St := Default(TADPCMState);
  St.Channels := AFile.Format.Channels;
  St.BlockSize := AFile.Format.BlockAlign;
  St.BlockHeaderSize := Ch * 4;
  St.SamplesPerBlock := AFile.Format.SamplesPerBlock;
  St.FramesTotal := AFile.SampleFrames;
  St.FramesLeft := St.FramesTotal;
  St.Input := @AFile.Chunk.Data[0];
  St.InputSize := AFile.Chunk.Size;
  St.InputPos := 0;
  SetLength(St.IMA, Ch);

  OutBytes := St.FramesTotal * Ch * 2;
  if OutBytes > $FFFFFFFF then
    Fail('WAVE file too big');
  SetLength(St.Output, SizeInt(St.FramesTotal * Ch));

  BytesLeft := St.InputSize - St.InputPos;
  while (St.FramesLeft > 0) and (BytesLeft >= St.BlockHeaderSize) do
  begin
    St.Block := PByte(PtrUInt(St.Input) + PtrUInt(St.InputPos));
    if BytesLeft < St.BlockSize then
      St.BlockLen := BytesLeft
    else
      St.BlockLen := St.BlockSize;
    St.BlockPos := 0;

    if (Length(St.Output) - St.OutputPos) < (St.FramesLeft * Ch) then
      Fail('Unexpected overflow in IMA ADPCM decoder');

    IMADecodeBlockHeader(St);
    if not IMADecodeBlockData(St) then
    begin
      if (AFile.TruncHint = TTruncationHint.VeryStrict) or (AFile.TruncHint = TTruncationHint.Strict) then
        Fail('Truncated data chunk')
      else if AFile.TruncHint <> TTruncationHint.DropFrame then
        St.OutputPos := St.OutputPos - (St.OutputPos mod (St.SamplesPerBlock * Ch));
      OutBytes := St.OutputPos * 2;
      Break;
    end;

    St.InputPos := St.InputPos + St.BlockLen;
    BytesLeft := St.InputSize - St.InputPos;
  end;

  SetLength(Result, SizeInt(OutBytes));
  if OutBytes > 0 then
    Move(St.Output[0], Result[0], SizeInt(OutBytes));
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
