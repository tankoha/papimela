{
  test_audio_wave — WAVE ファイルの読み込み（SDL_LoadWAV）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    177 通りの WAVE（test_audio_wave_cases.inc）を、ヒントの組み合わせつきで読み、結果を SDL と比べる:
    成功なら形式・チャンネル数・周波数・出力のバイト数・FNV-1a・読んだあとの位置、
    失敗ならエラーの文面。場面は PCM 4 種、浮動小数と fact チャンネルの 5 通りのヒント、
    A-law / μ-law の全 256 値、拡張ヘッダ、MS ADPCM と IMA ADPCM（端数のブロックと切り詰めのヒント）、
    チャンクの構造（JUNK / LIST / 奇数の大きさ / 順番の誤り / 欠け）、RIFF の大きさのヒント 4 通り、
    切り詰め、チャンク数の上限、形式の誤り。
    ほかに FromHints、引数の誤り、ファイルから読む。

  WHY:
    オーディオの残りの #54（SDL_wave.c）の受け入れ検査。表示サーバも音の装置も要らない。
    期待値は システムの SDL 3.4.2 の SDL_LoadWAV_IO に同じバイト列を読ませて取った
    （tools/wave-expect/wav_cases.c が場面を作って表を書き出す。docs/TEST-LOG.md の使い捨て検証）。
}
program test_audio_wave;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils, Classes,
  PaPiMeLa.Errors,
  PaPiMeLa.Properties,
  PaPiMeLa.Log,
  PaPiMeLa.Core,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Wave,
  PaPiMeLa.Audio,
  PaPiMeLa.Audio.Dummy;

type
  TWaveCase = record
    N, R, T, F, L: String;
    Fake: Int64;
    Hex, Err: String;
    Fmt: Word;
    Ch, Freq: Integer;
    Len: LongWord;
    Hash: LongWord;
    Pos: Int64;
  end;

const
  Cases: array[0..176] of TWaveCase = (
{$I test_audio_wave_cases.inc}
  );

type
  { 大きさを実際より大きく答えるストリーム（読める分は本物）。data チャンクが宣言より短い場面を作る。
    SDL の側は同じ嘘をつくストリームを SDL_OpenIO で作った。 }
  TLyingStream = class(TBytesStream)
  private
    FFake: Int64;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(const ABytes: TBytes; AFake: Int64);
  end;

constructor TLyingStream.Create(const ABytes: TBytes; AFake: Int64);
begin
  inherited Create(ABytes);
  FFake := AFake;
end;

function TLyingStream.GetSize: Int64;
begin
  Result := FFake;
end;

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

function Fnv(P: PByte; ALen: Integer): LongWord;
var
  I: Integer;
begin
  Result := 2166136261;
  for I := 0 to ALen - 1 do
  begin
    Result := Result xor P[I];
    Result := Result * 16777619;
  end;
end;

function HexToBytes(const AHex: String): TBytes;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AHex) div 2);
  for I := 0 to High(Result) do
    Result[I] := StrToInt('$' + Copy(AHex, I * 2 + 1, 2));
end;

{ SDL が配列の外（未初期化の領域）を読む場面は、papimela が断る。SDL の値は当てにならない。 }
function ExpectedError(const C: TWaveCase): String;
begin
  if C.N = 'ms_coefidx7' then
    Result := 'Invalid MS ADPCM coefficient index in block header'
  else
    Result := C.Err;
end;

procedure RunCase(const C: TWaveCase);
var
  ExpErr: String;
  Data, Pcm: TBytes;
  Stream: TBytesStream;
  Spec: TPMLAudioSpec;
  Opt: TPMLWaveOptions;
  Msg: String;
  Raised: Boolean;
begin
  Data := HexToBytes(C.Hex);
  if C.Fake > 0 then
    Stream := TLyingStream.Create(Data, C.Fake)
  else
    Stream := TBytesStream.Create(Data);
  try
    Opt := TPMLWaveOptions.FromHints(C.R, C.T, C.F, C.L);
    ExpErr := ExpectedError(C);
    Raised := False;
    Msg := '';
    Pcm := nil;
    Spec := Default(TPMLAudioSpec);
    try
      Pcm := PMLLoadWAV(Stream, Opt, Spec);
    except
      on E: EPMLAudioError do
      begin
        Raised := True;
        Msg := E.Message;
      end;
    end;
    if ExpErr <> '' then
      Check(Raised and (Msg = ExpErr), Format('%s: エラー「%s」（得た: %s）', [C.N, ExpErr, Msg]))
    else
      Check((not Raised) and (Spec.Format = C.Fmt) and (Spec.Channels = C.Ch) and (Spec.Freq = C.Freq)
        and (LongWord(Length(Pcm)) = C.Len) and (Fnv(PByte(Pcm), Length(Pcm)) = C.Hash)
        and (Stream.Position = C.Pos),
        Format('%s: 形式 %x ch %d %d Hz %d バイト %.8x 位置 %d（得た: %x ch %d %d Hz %d バイト %.8x 位置 %d%s）',
          [C.N, C.Fmt, C.Ch, C.Freq, C.Len, C.Hash, C.Pos, Spec.Format, Spec.Channels, Spec.Freq,
           Length(Pcm), Fnv(PByte(Pcm), Length(Pcm)), Stream.Position, Msg]));
  finally
    Stream.Free;
  end;
end;

procedure TestOptions;
var
  O: TPMLWaveOptions;
begin
  WriteLn('-- ヒントの文字列から');
  O := TPMLWaveOptions.Defaults;
  Check((O.RiffSize = TPMLWaveRiffSizeHint.NoHint) and (O.Truncation = TPMLWaveTruncationHint.NoHint)
    and (O.Fact = TPMLWaveFactHint.NoHint) and (O.ChunkLimit = 10000), '既定');
  O := TPMLWaveOptions.FromHints('force', 'verystrict', 'truncate', '77');
  Check((O.RiffSize = TPMLWaveRiffSizeHint.Force) and (O.Truncation = TPMLWaveTruncationHint.VeryStrict)
    and (O.Fact = TPMLWaveFactHint.Truncate) and (O.ChunkLimit = 77), 'force / verystrict / truncate / 77');
  O := TPMLWaveOptions.FromHints('ignorezero', 'strict', 'strict', '5x');
  Check((O.RiffSize = TPMLWaveRiffSizeHint.IgnoreZero) and (O.Truncation = TPMLWaveTruncationHint.Strict)
    and (O.Fact = TPMLWaveFactHint.Strict) and (O.ChunkLimit = 5), 'ignorezero / strict / strict / 5x（先頭の数字）');
  O := TPMLWaveOptions.FromHints('ignore', 'dropframe', 'ignorezero', '');
  Check((O.RiffSize = TPMLWaveRiffSizeHint.Ignore) and (O.Truncation = TPMLWaveTruncationHint.DropFrame)
    and (O.Fact = TPMLWaveFactHint.IgnoreZero) and (O.ChunkLimit = 10000), 'ignore / dropframe / ignorezero / 空');
  O := TPMLWaveOptions.FromHints('maximum', 'dropblock', 'ignore', 'abc');
  Check((O.RiffSize = TPMLWaveRiffSizeHint.Maximum) and (O.Truncation = TPMLWaveTruncationHint.DropBlock)
    and (O.Fact = TPMLWaveFactHint.Ignore) and (O.ChunkLimit = 10000), 'maximum / dropblock / ignore / abc');
  O := TPMLWaveOptions.FromHints('FORCE', 'x', '', '');
  Check((O.RiffSize = TPMLWaveRiffSizeHint.NoHint) and (O.Truncation = TPMLWaveTruncationHint.NoHint)
    and (O.Fact = TPMLWaveFactHint.NoHint), '知らない値と大文字は NoHint（SDL は大文字小文字を区別する）');
end;

procedure TestArgsAndFile;
var
  Spec: TPMLAudioSpec;
  Raised: Boolean;
  Pcm: TBytes;
  Path: String;
  C: TWaveCase;
  Bytes: TBytes;
  F: TFileStream;
begin
  WriteLn('-- 引数の誤りとファイル');
  Raised := False;
  try
    PMLLoadWAV(nil, Spec);
  except
    on EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'nil のストリームは EPMLArgument');
  Raised := False;
  try
    PMLLoadWAVFile('/nonexistent/dir/none.wav', Spec);
  except
    on EPMLIOError do
      Raised := True;
  end;
  Check(Raised, '開けないファイルは EPMLIOError');
  // ファイルから読む（pcm_s16_stereo と同じ結果）
  C := Cases[1];
  Bytes := HexToBytes(C.Hex);
  Path := GetTempDir + 'papimela_test_wave_' + IntToStr(GetProcessID) + '.wav';
  F := TFileStream.Create(Path, fmCreate);
  try
    F.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    F.Free;
  end;
  try
    Pcm := PMLLoadWAVFile(Path, Spec);
    Check((C.N = 'pcm_s16_stereo') and (Spec.Format = C.Fmt) and (LongWord(Length(Pcm)) = C.Len)
      and (Fnv(PByte(Pcm), Length(Pcm)) = C.Hash), 'ファイルから読んだ結果がストリームと同じ');
  finally
    DeleteFile(Path);
  end;
end;

{ Ctx.Audio.LoadWAV は、ヒントの値で読み方を変える。 }
procedure TestSystemHints;
var
  Opts: TPMLContextOptions;
  Ctx: TPMLContext;
  C: TWaveCase;
  Data, Pcm: TBytes;
  Spec: TPMLAudioSpec;
  Stream: TBytesStream;
  Msg: String;

  function Find(const AName: String): TWaveCase;
  var
    K: Integer;
  begin
    for K := 0 to High(Cases) do
      if Cases[K].N = AName then
        Exit(Cases[K]);
    raise Exception.Create('no case ' + AName);
  end;

  function MakeCtx(const AKey, AValue: String): TPMLContext;
  begin
    Opts := TPMLContextOptions.Default;
    Opts.PreferredAudio := 'dummy';
    Opts.MinimumLogLevel := TPMLLogPriority.Critical;
    if AKey <> '' then
      Opts.Hints.Add(AKey, AValue);
    Result := TPMLContext.Create([TPMLSubsystem.Audio], Opts);
  end;

begin
  WriteLn('-- Ctx.Audio.LoadWAV がヒントを読む');
  // ヒント無し: pcm_trailing_none と同じ
  C := Find('pcm_trailing_none');
  Data := HexToBytes(C.Hex);
  Ctx := MakeCtx('', '');
  try
    Stream := TBytesStream.Create(Data);
    try
      Pcm := Ctx.Audio.LoadWAV(Stream, Spec);
      Check((LongWord(Length(Pcm)) = C.Len) and (Fnv(PByte(Pcm), Length(Pcm)) = C.Hash), 'ヒント無し');
    finally
      Stream.Free;
    end;
  finally
    Ctx.Free;
  end;
  // strict: 端数のある data はエラー
  C := Find('pcm_trailing_strict');
  Ctx := MakeCtx(PML_HINT_WAVE_TRUNCATION, 'strict');
  try
    Stream := TBytesStream.Create(Data);
    try
      Msg := '';
      try
        Ctx.Audio.LoadWAV(Stream, Spec);
      except
        on E: EPMLAudioError do
          Msg := E.Message;
      end;
      Check(Msg = C.Err, 'PAPIMELA_WAVE_TRUNCATION=strict: ' + Msg);
    finally
      Stream.Free;
    end;
  finally
    Ctx.Free;
  end;
  // チャンク数の上限
  C := Find('chunks_many_limit5');
  Data := HexToBytes(C.Hex);
  Ctx := MakeCtx(PML_HINT_WAVE_CHUNK_LIMIT, '5');
  try
    Stream := TBytesStream.Create(Data);
    try
      Msg := '';
      try
        Ctx.Audio.LoadWAV(Stream, Spec);
      except
        on E: EPMLAudioError do
          Msg := E.Message;
      end;
      Check(Msg = C.Err, 'PAPIMELA_WAVE_CHUNK_LIMIT=5: ' + Msg);
    finally
      Stream.Free;
    end;
  finally
    Ctx.Free;
  end;
end;

procedure TestStreamStart;
var
  Data, Prefixed, Pcm: TBytes;
  Stream: TBytesStream;
  Spec: TPMLAudioSpec;
  C: TWaveCase;
  I: Integer;
begin
  WriteLn('-- ストリームの途中から読む');
  C := Cases[1];
  Data := HexToBytes(C.Hex);
  SetLength(Prefixed, Length(Data) + 5);
  for I := 0 to 4 do
    Prefixed[I] := $AA;
  Move(Data[0], Prefixed[5], Length(Data));
  Stream := TBytesStream.Create(Prefixed);
  try
    Stream.Position := 5;
    Pcm := PMLLoadWAV(Stream, Spec);
    Check((LongWord(Length(Pcm)) = C.Len) and (Fnv(PByte(Pcm), Length(Pcm)) = C.Hash),
      '現在の位置から読む（位置 5 から）');
    Check(Stream.Position = C.Pos + 5, '読み終えた位置も相対');
  finally
    Stream.Free;
  end;
end;

var
  I: Integer;

begin
  WriteLn('=== test_audio_wave ===');
  WriteLn('-- 177 の場面を SDL と比べる');
  for I := 0 to High(Cases) do
    RunCase(Cases[I]);
  TestOptions;
  TestArgsAndFile;
  TestSystemHints;
  TestStreamStart;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: WAVE の読み込みが SDL_LoadWAV_IO と同じ結果になる ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
