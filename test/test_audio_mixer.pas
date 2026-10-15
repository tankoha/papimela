{
  test_audio_mixer — SDL_MixAudio（8 つの形式の混ぜ合わせ）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    8 つの形式（U8 / S8 / S16LE / S16BE / S32LE / S32BE / F32LE / F32BE）× 9 つの音量
    （1・0.5・0.3・1.7・0・0.004・0.99・±64.5/128。後ろの 2 つは丸めの半分と負の音量）で、固定の LCG の入力 1001 バイト（標本に満たない端つき。
    浮動小数は -1.5〜1.5）を混ぜた出力の FNV-1a を SDL と比べる。知らない形式と、引数の誤り。

  WHY:
    オーディオの残りの #53（.Audio.Mixer）の受け入れ検査。表示サーバも音の装置も要らない。
    期待値は システムの SDL 3.4.2 の SDL_MixAudio に同じ入力を通して取った（F32 の 2 行だけ例外。
    aarch64 の SDL は src * 音量 + dst を FMA 命令に融合して丸めが 1 回になり、融合しない x86 の SDL と
    値が割れる。papimela は融合しない版（FPC も融合しない）に合わせ、SDL のループを -ffp-contract=off で
    動かした値を使う。音量 0 は SDL が何もしない）
    （docs/TEST-LOG.md の使い捨て検証）。音量 1.7 は S8 / S16 で SDL の (Sint8) などへの
    切り詰めが回り込む場面を含む。
}
program test_audio_mixer;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Mixer;

const
  Formats: array[0..7] of TPMLAudioFormat = (
    PML_AUDIO_U8, PML_AUDIO_S8, PML_AUDIO_S16LE, PML_AUDIO_S16BE,
    PML_AUDIO_S32LE, PML_AUDIO_S32BE, PML_AUDIO_F32LE, PML_AUDIO_F32BE);
  FormatNames: array[0..7] of String = (
    'U8', 'S8', 'S16LE', 'S16BE', 'S32LE', 'S32BE', 'F32LE', 'F32BE');
  Volumes: array[0..8] of Single = (1.0, 0.5, 0.3, 1.7, 0.0, 0.004, 0.99, 0.50390625, -0.50390625);

  Expected: array[0..7, 0..8] of LongWord = (
    ($2FEB135A, $EB99B0A2, $7C453CD5, $428918C8, $AB3B02A6, $98E26E67, $26C37B8D, $569649E5, $DB3A623A),   // U8
    ($FAF0578E, $ADAE6D6C, $2B6DBA8D, $8C7D3B00, $2B2405A5, $0031FDB8, $765272B7, $E2D8972F, $F85912AA),   // S8
    ($BB56DA29, $5839D10B, $1C657526, $E6BA2A70, $E4AAED8B, $28F706F1, $6AEFDCA3, $DA057A24, $3E3BA5AC),   // S16LE
    ($013DBE18, $CEE5BDCB, $A80C939D, $711B1B9F, $3D7957FB, $B3299F26, $C8252B68, $9A5D9D1C, $9D5BD062),   // S16BE
    ($0944596A, $66847035, $32AD3727, $EC6ECDE4, $D005683D, $31BD15BD, $3D2AC8E6, $D7E3C032, $F2657BC4),   // S32LE
    ($F7ACA30A, $5305F286, $86AB5A25, $12D39139, $CDA62FD9, $CCC9BCE5, $2A5D2A8B, $673BF0FD, $4E6DE3D4),   // S32BE
    ($BC8933C7, $CF3128E7, $99582662, $8CCDFFEF, $5E5D2528, $645B1B11, $90D5503B, $07052FF9, $16A09FC8),   // F32LE
    ($44A0B9A3, $7BFFE848, $299D1A81, $ECA1E6AD, $20FBE545, $099E094F, $D0F0BC80, $D65AFA10, $2005B918));   // F32BE

  BufLen = 1001;

var
  Failures: Integer = 0;
  Lcg: LongWord;

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

function SwapLong(V: LongWord): LongWord;
begin
  Result := (V shr 24) or ((V shr 8) and $FF00) or ((V shl 8) and $FF0000) or (V shl 24);
end;

procedure Fill(var ABuf: array of Byte; AFormat: TPMLAudioFormat);
var
  I: Integer;
  F, K: Single;
  U: LongWord;
begin
  if PMLAudioIsFloat(AFormat) then
  begin
    // 末尾の 1 バイトは標本に満たないので触らない（0 のまま）
    FillChar(ABuf[0], Length(ABuf), 0);
    for I := 0 to (Length(ABuf) div 4) - 1 do
    begin
      Lcg := Lcg * 1103515245 + 12345;
      K := Single(Lcg shr 8);
      F := K / Single(8388608.0);
      F := F * Single(1.5);
      F := F - Single(0.75);
      F := F * Single(2.0);
      U := PLongWord(@F)^;
      if PMLAudioIsBigEndian(AFormat) then
        U := SwapLong(U);
      PLongWord(@ABuf[I * 4])^ := U;
    end;
  end
  else
    for I := 0 to High(ABuf) do
    begin
      Lcg := Lcg * 1103515245 + 12345;
      ABuf[I] := Byte(Lcg shr 16);
    end;
end;

procedure TestScenes;
var
  F, V: Integer;
  Dst, Src: array[0..BufLen - 1] of Byte;
begin
  WriteLn('-- 72 の場面（形式 × 音量）を SDL と比べる');
  for F := 0 to 7 do
    for V := 0 to 8 do
    begin
      Lcg := LongWord(1000 + F * 10 + V);
      Fill(Dst, Formats[F]);
      Fill(Src, Formats[F]);
      PMLMixAudio(@Dst[0], @Src[0], Formats[F], BufLen, Volumes[V]);
      Check(Fnv(@Dst[0], BufLen) = Expected[F, V],
        Format('%s 音量 %g: %.8x（期待 %.8x）', [FormatNames[F], Volumes[V], Fnv(@Dst[0], BufLen), Expected[F, V]]));
    end;
end;

procedure TestErrors;
var
  A, B: array[0..7] of Byte;
  Raised: Boolean;
begin
  WriteLn('-- 引数の誤り');
  FillChar(A, SizeOf(A), 1);
  FillChar(B, SizeOf(B), 2);
  Raised := False;
  try
    PMLMixAudio(@A[0], @B[0], TPMLAudioFormat($1234), 8, 1.0);
  except
    on EPMLArgument do
      Raised := True;
  end;
  Check(Raised, '知らない形式は EPMLArgument');
  Check((A[0] = 1) and (A[7] = 1), '知らない形式では書き込まない');
  // 音量が 0 なら形式が何でも何もしない（SDL は形式を見る前に戻る）
  Raised := False;
  try
    PMLMixAudio(@A[0], @B[0], TPMLAudioFormat($1234), 8, 0.0);
  except
    on EPMLArgument do
      Raised := True;
  end;
  Check(not Raised, '音量 0 は形式を見ずに戻る');
  // 長さ 0 と標本に満たない長さ
  PMLMixAudio(@A[0], @B[0], PML_AUDIO_S16LE, 0, 1.0);
  PMLMixAudio(@A[0], @B[0], PML_AUDIO_S32LE, 3, 1.0);
  Check((A[0] = 1) and (A[1] = 1) and (A[2] = 1), '長さ 0 と標本に満たない長さは触らない');
  Raised := False;
  try
    PMLMixAudio(@A[0], @B[0], PML_AUDIO_U8, -1, 1.0);
  except
    on EPMLArgument do
      Raised := True;
  end;
  Check(Raised, '負の長さは EPMLArgument');
end;

begin
  WriteLn('=== test_audio_mixer ===');
  TestScenes;
  TestErrors;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: 混ぜ合わせが SDL_MixAudio と同じ値になる ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
