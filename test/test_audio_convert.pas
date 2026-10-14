{
  test_audio_convert — 音声の形式・チャンネル数・並び・音量の変換（周波数は変えない）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 形式の判定、名前、無音の値、チャンネルの並びの判定
    2. 形式 x 形式（8 x 8、ステレオ）、チャンネル数 x チャンネル数（F32 と S16 で 8 x 8）、
       ストリームでの並びと音量の 8 場面を変換し、出力のバイト列の FNV-1a を SDL と比べる
    3. 範囲の外の浮動小数（NaN・無限大・とても大きな値）を整数の形式へ変換したときの値

  WHY:
    §3 のオーディオの 1 段目（#52）の受け入れ検査。表示サーバも音の装置も要らない。
    期待値は参照版の SDL の SDL_ConvertAudioSamples と SDL_AudioStream（同じ周波数）で、入力を
    固定の LCG で作って取った（docs/TEST-LOG.md の使い捨て検証）。SDL の SSE2 版・スカラー版・
    SDL 3.4.2 のどれでも同じ値になる入力だけを使う（浮動小数は -2..2）。範囲の外の大きな値は
    SDL の経路で結果が割れるので、3 で papimela の規則（飽和させる）を確かめる（D-64・D-65）。
}
program test_audio_convert;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils,
  PaPiMeLa.Audio.Convert;

const
  // 形式 x 形式（ステレオ、64 フレーム、入力は LCG のバイト、浮動小数の形式は -2..2。種 = 1 + 8*src + dst）
  FormatHashes: array[0..7, 0..7] of LongWord = (
    ($05DDDA47, $5EDF34BB, $E1D077C6, $994279DE, $1C3FE074, $E9D96C80, $BBC0E7FA, $AFDE3F7F),
    ($895E6A0D, $8B577041, $39CDC56D, $8CAD1BD4, $ECB102C3, $9112814A, $DAE623DC, $FB3127D3),
    ($F55B598D, $51B043BE, $BB852781, $F813B3BD, $A6B21984, $159FFC96, $E9448844, $3DF7460D),
    ($94A98EAC, $7DEB1994, $F1A3B95A, $6D228E1B, $CAC2E704, $DCE93B0A, $0155A0A7, $074AA6FD),
    ($E995A76F, $B01C4D51, $501D889B, $D2B34F0A, $CAA59746, $FA7AA481, $96A94B60, $2B389BD6),
    ($AE23F524, $C4F384CF, $058E9F72, $8E8286E7, $A6D58120, $8346623A, $7F4D00C5, $E71FD160),
    ($83EEBD3C, $9E3F3A6E, $A356188E, $F3D9B4A0, $ACC4E328, $8BCD5135, $05382EE0, $18BD7F1F),
    ($16A380CF, $9B80F018, $D69E2501, $AD6DAFEE, $D84CDFCA, $7D499C46, $CE6CD658, $64DAE0BB));
  // F32 のチャンネル数 x チャンネル数（50 フレーム、-1..1。種 = 100 + 8*src + dst）
  ChannelHashesF32: array[1..8, 1..8] of LongWord = (
    ($B34257C8, $B9AC4729, $0E8A15ED, $F553682D, $7E0F78D5, $439A0E11, $98B3404D, $50A2C695),
    ($43C30DA9, $D371557C, $9A447010, $27CC937D, $EC099344, $406CA629, $B268E81B, $F13690E2),
    ($58B04056, $6577ACFE, $0FEB4728, $2704C9B3, $1B88A240, $F7964939, $BF01B3A7, $A1BA3FB9),
    ($EBAB8FE1, $1AFB0A55, $E086A8C4, $45427B3A, $FC09BD5D, $ACFE1F1B, $E22841C4, $8E2F6291),
    ($5D2C1C02, $881466D9, $00CDD99E, $A5F7899A, $29447430, $775003C1, $2E9619E0, $B91A9659),
    ($70713BC1, $17E51E48, $235FAF5A, $28A53D77, $02FF0FE7, $29EC7B19, $DF749655, $5ED3A833),
    ($93EF234C, $5C8B3545, $CD94D77C, $0C8AD94E, $8A074A0D, $79157B9C, $D6997118, $336C9D9B),
    ($5C6182A0, $09CD2244, $18F5D69B, $0F469ED8, $6F8D6AE1, $B5C6F528, $4BD6285F, $9CA51501));
  // S16 のチャンネル数 x チャンネル数（50 フレーム、入力は LCG のバイト。種 = 200 + 8*src + dst）
  ChannelHashesS16: array[1..8, 1..8] of LongWord = (
    ($A69FF6AE, $52F60D05, $2225EED1, $45781FFD, $A341F281, $01195D0D, $2BFA9261, $A1795175),
    ($DA805441, $EEF7A776, $553FF80C, $34E990DA, $AF55A100, $BFD5B99E, $A8447768, $5C9FFBB4),
    ($5D6638BE, $562EFBF6, $C5656B4D, $3B0983A1, $E4830A10, $58E1A5CD, $1CC33558, $440A507D),
    ($31D4EEA2, $4D971D99, $3CE3B405, $83D4D1F7, $143DF5D2, $22F1C87C, $E7F011A3, $8E86DA4A),
    ($BD7B54BF, $93A94F92, $A3D5E347, $424A6AC1, $985849EC, $3609AD87, $424F9792, $50BEE4F5),
    ($B18815D9, $6B37E1DE, $14AA0D66, $D1CE9A62, $A063EDC9, $D9F36600, $B26B6972, $A9E2B797),
    ($C807E956, $911A2745, $39C92B1D, $F6F8C86B, $DB357B0C, $ED8FBCDF, $E024FC32, $3C87B3B4),
    ($3A73D5BA, $736D9C73, $D3122DF9, $88CC23A7, $DE1FFC7D, $833E2150, $67D16D74, $14297B93));
  // ストリームでの並びと音量（30 フレーム、種 = 300 + 番号）
  MapHashes: array[0..7] of LongWord = ($C46A5942, $C61C45E3, $012C0764, $DC361099, $81596359, $B34DAAB9, $8F730F9C, $F8541DE9);

  Formats: array[0..7] of TPMLAudioFormat = (PML_AUDIO_U8, PML_AUDIO_S8, PML_AUDIO_S16LE,
    PML_AUDIO_S16BE, PML_AUDIO_S32LE, PML_AUDIO_S32BE, PML_AUDIO_F32LE, PML_AUDIO_F32BE);

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

function NextByte: Byte;
begin
  Lcg := Lcg * 1103515245 + 12345;
  Result := Byte(Lcg shr 16);
end;

{ -1..1 の浮動小数（プローブの ((float)(lcg >> 8) / 8388608.0f) - 1.0f。どれも単精度で割り切れる）。 }
function NextFloat: Single;
begin
  Lcg := Lcg * 1103515245 + 12345;
  Result := Single(Lcg shr 8) / Single(8388608.0) - Single(1.0);
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

{ プローブの入力（AFloatInput は -1..1、そうでなく浮動小数の形式なら -2..2、ほかはバイト）。 }
function MakeInput(AFormat: TPMLAudioFormat; AChannels, AFrames: Integer; ASeed: LongWord;
  AFloatInput: Boolean): TBytes;
var
  I, Len: Integer;
  F: Single;
  U: LongWord;
begin
  Result := nil;
  Len := AFrames * AChannels * PMLAudioByteSize(AFormat);
  SetLength(Result, Len);
  Lcg := ASeed;
  if AFloatInput or PMLAudioIsFloat(AFormat) then
    for I := 0 to AFrames * AChannels - 1 do
    begin
      F := NextFloat;
      if not AFloatInput then
        F := F * Single(2.0);
      U := PLongWord(@F)^;
      if PMLAudioIsBigEndian(AFormat) then
        U := SwapLong(U);
      PLongWord(@Result[I * 4])^ := U;
    end
  else
    for I := 0 to Len - 1 do
      Result[I] := NextByte;
end;

function ConvertHash(ASrcFormat: TPMLAudioFormat; ASrcChannels: Integer;
  ADstFormat: TPMLAudioFormat; ADstChannels: Integer; const AIn: TBytes; AFrames: Integer;
  const ASrcMap, ADstMap: TPMLChannelMap; AGain: Single): LongWord;
var
  Dst, Scratch: TBytes;
begin
  SetLength(Dst, AFrames * ADstChannels * PMLAudioByteSize(ADstFormat));
  SetLength(Scratch, AFrames * PMLAudioMaxFrameSize(ASrcFormat, ASrcChannels, ADstFormat, ADstChannels));
  PMLConvertAudio(AFrames, @AIn[0], ASrcFormat, ASrcChannels, ASrcMap,
    @Dst[0], ADstFormat, ADstChannels, ADstMap, @Scratch[0], AGain);
  Result := Fnv(@Dst[0], Length(Dst));
end;

type
  TPlainProc = procedure;

{ 1 つの節で思わぬ例外が出ても、失敗に数えて次の節へ進む。 }
procedure Guard(AProc: TPlainProc);
begin
  try
    AProc;
  except
    on E: Exception do
      Check(False, '思わぬ例外: ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure TestBasics;
var
  Ok: Boolean;
  I: Integer;
begin
  WriteLn('1. 形式・名前・無音・並び');
  Check((PMLAudioBitSize(PML_AUDIO_S16BE) = 16) and (PMLAudioByteSize(PML_AUDIO_F32LE) = 4)
    and (PMLAudioByteSize(PML_AUDIO_U8) = 1), 'ビット数とバイト数');
  Check(PMLAudioIsFloat(PML_AUDIO_F32BE) and not PMLAudioIsFloat(PML_AUDIO_S32LE)
    and PMLAudioIsBigEndian(PML_AUDIO_S16BE) and not PMLAudioIsBigEndian(PML_AUDIO_S16LE)
    and PMLAudioIsSigned(PML_AUDIO_S8) and not PMLAudioIsSigned(PML_AUDIO_U8), '浮動小数・バイト順・符号の判定');
  Ok := True;
  for I := 0 to 7 do
    if not PMLIsSupportedAudioFormat(Formats[I]) then
      Ok := False;
  Check(Ok and not PMLIsSupportedAudioFormat(PML_AUDIO_UNKNOWN)
    and not PMLIsSupportedAudioFormat(TPMLAudioFormat($8018)), '変換できる形式は 8 つ（24 ビットは無い）');
  Check(PMLIsSupportedChannelCount(1) and PMLIsSupportedChannelCount(8)
    and not PMLIsSupportedChannelCount(0) and not PMLIsSupportedChannelCount(9), 'チャンネル数は 1〜8');
  Check((PMLAudioFormatName(PML_AUDIO_S16LE) = 'S16LE') and (PMLAudioFormatName(PML_AUDIO_F32BE) = 'F32BE')
    and (PMLAudioFormatName(PML_AUDIO_U8) = 'U8') and (PMLAudioFormatName(TPMLAudioFormat($1234)) = 'UNKNOWN'),
    '形式の名前（SDL_GetAudioFormatName から SDL_AUDIO_ を外したもの）');
  Check((PMLAudioSilenceValue(PML_AUDIO_U8) = $80) and (PMLAudioSilenceValue(PML_AUDIO_S8) = 0)
    and (PMLAudioSilenceValue(PML_AUDIO_F32LE) = 0), '無音は U8 だけ $80');
  Check(TPMLAudioSpec.Make(PML_AUDIO_S16, 6, 48000).FrameSize = 12, '1 フレームのバイト数');
  Check(not PMLChannelMapIsBogus(nil, 2) and not PMLChannelMapIsBogus([1, -1], 2)
    and PMLChannelMapIsBogus([0, 2], 2) and PMLChannelMapIsBogus([-2, 0], 2), '並びの値の範囲');
  Check(PMLChannelMapIsDefault(nil, 3) and PMLChannelMapIsDefault([0, 1, 2], 3)
    and not PMLChannelMapIsDefault([0, 2, 1], 3), '恒等の並び');
  Check(PMLChannelMapsEqual(2, nil, nil) and PMLChannelMapsEqual(2, [1, 0], [1, 0])
    and not PMLChannelMapsEqual(2, nil, [0, 1]) and not PMLChannelMapsEqual(2, [0, 1], [1, 0]),
    '並びの比べ方（片方だけ空なら恒等でも違う。SDL と同じ）');
  Check(PMLAudioMaxFrameSize(PML_AUDIO_U8, 2, PML_AUDIO_S16, 6) = 24, '途中で要る 1 フレームの大きさ（浮動小数で 4 バイト x 6）');
end;

procedure TestHashes;
var
  A, B, K, Bad: Integer;
  Inp: TBytes;
  Maps: array[0..7, 0..1] of TPMLChannelMap;
  Specs: array[0..7] of record SF: TPMLAudioFormat; SC: Integer; DF: TPMLAudioFormat; DC: Integer; G: Single; end;
begin
  WriteLn('2. SDL の出力と比べる（FNV-1a）');
  Bad := 0;
  for A := 0 to 7 do
    for B := 0 to 7 do
    begin
      Inp := MakeInput(Formats[A], 2, 64, 1 + 8 * A + B, False);
      if ConvertHash(Formats[A], 2, Formats[B], 2, Inp, 64, nil, nil, 1.0) <> FormatHashes[A, B] then
      begin
        WriteLn(Format('      %s → %s', [PMLAudioFormatName(Formats[A]), PMLAudioFormatName(Formats[B])]));
        Inc(Bad);
      end;
    end;
  Check(Bad = 0, Format('形式 x 形式の 64 通りが SDL と同じ（違う %d）', [Bad]));
  Bad := 0;
  for A := 1 to 8 do
    for B := 1 to 8 do
    begin
      Inp := MakeInput(PML_AUDIO_F32, A, 50, 100 + 8 * A + B, True);
      if ConvertHash(PML_AUDIO_F32, A, PML_AUDIO_F32, B, Inp, 50, nil, nil, 1.0) <> ChannelHashesF32[A, B] then
      begin
        WriteLn(Format('      F32 %d → %d', [A, B]));
        Inc(Bad);
      end;
    end;
  Check(Bad = 0, Format('F32 のチャンネル数 x チャンネル数の 64 通りが SDL と同じ（違う %d）', [Bad]));
  Bad := 0;
  for A := 1 to 8 do
    for B := 1 to 8 do
    begin
      Inp := MakeInput(PML_AUDIO_S16, A, 50, 200 + 8 * A + B, False);
      if ConvertHash(PML_AUDIO_S16, A, PML_AUDIO_S16, B, Inp, 50, nil, nil, 1.0) <> ChannelHashesS16[A, B] then
      begin
        WriteLn(Format('      S16 %d → %d', [A, B]));
        Inc(Bad);
      end;
    end;
  Check(Bad = 0, Format('S16 のチャンネル数 x チャンネル数の 64 通りが SDL と同じ（違う %d）', [Bad]));

  // プローブの 8 場面（ストリームの入力の並び・出力の並び・音量）
  Specs[0].SF := PML_AUDIO_S16; Specs[0].SC := 4; Specs[0].DF := PML_AUDIO_S16; Specs[0].DC := 4; Specs[0].G := 1.0;
  Maps[0, 0] := TPMLChannelMap.Create(3, 2, 1, 0); Maps[0, 1] := nil;
  Specs[1] := Specs[0];
  Maps[1, 0] := TPMLChannelMap.Create(0, -1, 2, 2); Maps[1, 1] := nil;
  Specs[2] := Specs[0];
  Maps[2, 0] := nil; Maps[2, 1] := TPMLChannelMap.Create(1, 0, -1, 3);
  Specs[3].SF := PML_AUDIO_U8; Specs[3].SC := 3; Specs[3].DF := PML_AUDIO_F32; Specs[3].DC := 2; Specs[3].G := 1.0;
  Maps[3, 0] := TPMLChannelMap.Create(2, 1, 0); Maps[3, 1] := TPMLChannelMap.Create(1, 0);
  Specs[4].SF := PML_AUDIO_S16; Specs[4].SC := 2; Specs[4].DF := PML_AUDIO_S16; Specs[4].DC := 2; Specs[4].G := 0.5;
  Maps[4, 0] := nil; Maps[4, 1] := nil;
  Specs[5] := Specs[4]; Specs[5].G := 1.7;
  Maps[5, 0] := nil; Maps[5, 1] := nil;
  Specs[6].SF := PML_AUDIO_F32; Specs[6].SC := 6; Specs[6].DF := PML_AUDIO_S16BE; Specs[6].DC := 2; Specs[6].G := 0.3;
  Maps[6, 0] := TPMLChannelMap.Create(5, 4, 3, 2, 1, 0); Maps[6, 1] := nil;
  Specs[7].SF := PML_AUDIO_S32BE; Specs[7].SC := 2; Specs[7].DF := PML_AUDIO_S32BE; Specs[7].DC := 2; Specs[7].G := 1.0;
  Maps[7, 0] := TPMLChannelMap.Create(1, 0); Maps[7, 1] := nil;
  Bad := 0;
  for K := 0 to 7 do
  begin
    Inp := MakeInput(Specs[K].SF, Specs[K].SC, 30, 300 + K, PMLAudioIsFloat(Specs[K].SF));
    if ConvertHash(Specs[K].SF, Specs[K].SC, Specs[K].DF, Specs[K].DC, Inp, 30,
      Maps[K, 0], Maps[K, 1], Specs[K].G) <> MapHashes[K] then
    begin
      WriteLn(Format('      場面 %d', [K]));
      Inc(Bad);
    end;
  end;
  Check(Bad = 0, Format('並び（入力・出力・無音・重複）と音量（0.5・1.7・0.3）の 8 場面が SDL と同じ（違う %d）', [Bad]));
end;

procedure TestSpecialValues;
const
  N = 20;
  // NaN、-NaN、+∞、-∞、1e30、-1e30、3e9、-3e9、2、-2、1、-1、1 の直前、-1 の直前、0.5、1 の直後、
  // -1 の直後、0、-0、1e-30（単精度のビット）
  Bits: array[0..N - 1] of LongWord = ($7FC00000, $FFC00000, $7F800000, $FF800000, $7149F2CA, $F149F2CA,
    $4F32D05E, $CF32D05E, $40000000, $C0000000, $3F800000, $BF800000, $3F7FFFFF, $BF7FFFFF,
    $3F000000, $3F800001, $BF800001, $00000000, $80000000, $0DA24260);
  WantS8: array[0..N - 1] of ShortInt = (127, -128, 127, -128, 127, -128, 127, -128, 127, -128,
    127, -128, 127, -128, 64, 127, -128, 0, 0, 0);
  WantU8: array[0..N - 1] of Byte = (255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0,
    192, 255, 0, 128, 128, 128);
  WantS16: array[0..N - 1] of SmallInt = (32767, -32768, 32767, -32768, 32767, -32768, 32767, -32768,
    32767, -32768, 32767, -32768, 32767, -32768, 16384, 32767, -32768, 0, 0, 0);
  WantS32: array[0..N - 1] of LongInt = (0, 0, 2147483647, -2147483648, 2147483647, -2147483648,
    2147483647, -2147483648, 2147483647, -2147483648, 2147483647, -2147483648,
    2147483520, -2147483520, 1073741824, 2147483647, -2147483648, 0, 0, 0);
var
  S8: array[0..N - 1] of ShortInt;
  U8: array[0..N - 1] of Byte;
  S16: array[0..N - 1] of SmallInt;
  S32: array[0..N - 1] of LongInt;
  I: Integer;
  Ok: Boolean;
begin
  WriteLn('3. 範囲の外の浮動小数（D-64・D-65）');
  PMLConvertAudioFromFloat(@S8[0], PSingle(@Bits[0]), N, PML_AUDIO_S8);
  PMLConvertAudioFromFloat(@U8[0], PSingle(@Bits[0]), N, PML_AUDIO_U8);
  PMLConvertAudioFromFloat(@S16[0], PSingle(@Bits[0]), N, PML_AUDIO_S16);
  PMLConvertAudioFromFloat(@S32[0], PSingle(@Bits[0]), N, PML_AUDIO_S32);
  Ok := True;
  for I := 0 to N - 1 do
    if S8[I] <> WantS8[I] then
    begin
      WriteLn(Format('      S8 [%d] = %d, expected %d', [I, S8[I], WantS8[I]]));
      Ok := False;
    end;
  Check(Ok, 'F32 → S8 は飽和する（NaN は符号の側。SDL のスカラー版と同じ。SSE2 版は +∞ と 1e30 を -128 にする）');
  Ok := True;
  for I := 0 to N - 1 do
    if U8[I] <> WantU8[I] then
      Ok := False;
  Check(Ok, 'F32 → U8 も同じ（SSE2 版は +∞ と 1e30 を 0 にする）');
  Ok := True;
  for I := 0 to N - 1 do
    if S16[I] <> WantS16[I] then
      Ok := False;
  Check(Ok, 'F32 → S16 は飽和する（SDL の両方の版と同じ）');
  Ok := True;
  for I := 0 to N - 1 do
    if S32[I] <> WantS32[I] then
    begin
      WriteLn(Format('      S32 [%d] = %d, expected %d', [I, S32[I], WantS32[I]]));
      Ok := False;
    end;
  Check(Ok, 'F32 → S32 は ±∞ と 1e30 も飽和し、NaN は 0（SDL のスカラー版は ±∞・1e30 も 0。D-65）');
end;

begin
  WriteLn('test_audio_convert — 音声の変換');
  WriteLn;
  Guard(@TestBasics);
  WriteLn;
  Guard(@TestHashes);
  WriteLn;
  Guard(@TestSpecialValues);
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: 音声の変換が SDL と同じ値になる ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
