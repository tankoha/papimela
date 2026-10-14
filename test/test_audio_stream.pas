{
  test_audio_stream — 音声のストリーム（周波数の変換・キュー・呼び出し）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 引数の確かめ（形式・チャンネル数・周波数・半端なフレーム・並び・周波数の比・音量）、
       チャンネル数を変えると並びが消える、写さない入力の解放の知らせ
    2. 15 の場面を流し、出力のバイト列の FNV-1a とバイト数（場面によって途中の Available・
       Queued・呼び出しの量）を SDL と比べる: 周波数の上げ下げ、変換の前後のチャンネル数の増減、
       音量、周波数の比の途中の変更、入力の形式の途中の変更、流し切る前後、Clear、入力の並び、
       平面ごとの入力、PMLConvertAudioSamples、OnGet / OnPut の量

  WHY:
    オーディオの 1 段目の後半（#52 の周波数の変換と SDL_AudioStream、#53 のキュー）の受け入れ検査。
    表示サーバも音の装置も要らない。期待値は参照版の SDL の SIMD を切って（SDL_CPU_FEATURE_MASK）
    取った（docs/TEST-LOG.md の使い捨て検証）。SDL は x86 で周波数の変換の 1 フレームの計算を SSE で
    行い、足し算の順番が違うので、SIMD を切らないと周波数を変える 8 場面の値が違う。papimela は
    スカラー版を写している。SDL 3.4.2 の SIMD を切った版も同じ値。
}
program test_audio_stream;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Stream;

type
  TStreamCase = record
    Hash  : LongWord;
    Bytes : Integer;
    Extra1: Integer;
    Extra2: Integer;
  end;

const
  StreamCases: array[0..14] of TStreamCase = (
     (Hash: $DD914E24; Bytes: 4356; Extra1: 0; Extra2: 0)   // 0: S16 2ch 44100->48000
,    (Hash: $9F389E2A; Bytes: 4356; Extra1: 0; Extra2: 0)   // 1: F32 1ch 22050->48000
,    (Hash: $62BEE9ED; Bytes: 17640; Extra1: 0; Extra2: 0)   // 2: S16 1ch 8000->F32 2ch 44100
,    (Hash: $43264394; Bytes: 1104; Extra1: 0; Extra2: 0)   // 3: F32 6ch 96000->S16 2ch 44100
,    (Hash: $E204253E; Bytes: 3736; Extra1: 0; Extra2: 0)   // 4: U8 2ch 48000->S32 32000 gain 0.6
,    (Hash: $3C492C49; Bytes: 2552; Extra1: 0; Extra2: 0)   // 5: ratio 1.25 then 0.8
,    (Hash: $7807945D; Bytes: 2616; Extra1: 0; Extra2: 0)   // 6: format change mid-stream
,    (Hash: $BF59DE49; Bytes: 4356; Extra1: 4324; Extra2: 4324)   // 7: before/after flush
,    (Hash: $EC285F0A; Bytes: 872; Extra1: 816; Extra2: 400)   // 8: available/queued
,    (Hash: $9A4C34E5; Bytes: 220; Extra1: 0; Extra2: 0)   // 9: clear
,    (Hash: $D5D3982E; Bytes: 1104; Extra1: 0; Extra2: 0)   // 10: input map + resample
,    (Hash: $620B1319; Bytes: 400; Extra1: 0; Extra2: 0)   // 11: planar
,    (Hash: $34EB1FD5; Bytes: 2232; Extra1: 0; Extra2: 0)   // 12: ConvertAudioSamples 44100->48000
,    (Hash: $00000000; Bytes: 408; Extra1: 1464; Extra2: 1840)   // 13: callbacks
,    (Hash: $10902371; Bytes: 1104; Extra1: 0; Extra2: 0)   // 14: F32 6ch 96000->F32 2ch 44100
  );

var
  Failures: Integer = 0;
  Lcg: LongWord;
  FnvH: LongWord;

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

procedure FnvReset;
begin
  FnvH := 2166136261;
end;

procedure FnvAdd(P: PByte; ALen: Integer);
var
  I: Integer;
begin
  for I := 0 to ALen - 1 do
  begin
    FnvH := FnvH xor P[I];
    FnvH := FnvH * 16777619;
  end;
end;

function SwapLong(V: LongWord): LongWord;
begin
  Result := (V shr 24) or ((V shr 8) and $FF00) or ((V shl 8) and $FF0000) or (V shl 24);
end;

{ プローブの make: 浮動小数は -1..1、ほかは LCG のバイト。Lcg は続けて使う。 }
function MakeInput(AFormat: TPMLAudioFormat; AChannels, AFrames: Integer): TBytes;
var
  I, Len: Integer;
  F: Single;
  U: LongWord;
begin
  Result := nil;
  Len := AFrames * AChannels * PMLAudioByteSize(AFormat);
  SetLength(Result, Len);
  if PMLAudioIsFloat(AFormat) then
    for I := 0 to AFrames * AChannels - 1 do
    begin
      Lcg := Lcg * 1103515245 + 12345;
      F := Single(Lcg shr 8) / Single(8388608.0) - Single(1.0);
      U := PLongWord(@F)^;
      if PMLAudioIsBigEndian(AFormat) then
        U := SwapLong(U);
      PLongWord(@Result[I * 4])^ := U;
    end
  else
    for I := 0 to Len - 1 do
    begin
      Lcg := Lcg * 1103515245 + 12345;
      Result[I] := Byte(Lcg shr 16);
    end;
end;

{ 出せるだけ AChunk バイトずつ取り出してハッシュに足し、取り出したバイト数を返す。 }
function Drain(AStream: TPMLAudioStream; AChunk: Integer): Integer;
var
  Buf: array[0..65535] of Byte;
  Got: Integer;
begin
  Result := 0;
  repeat
    Got := AStream.GetData(@Buf[0], AChunk);
    if Got > 0 then
    begin
      FnvAdd(@Buf[0], Got);
      Inc(Result, Got);
    end;
  until Got <= 0;
end;

procedure PutChunks(AStream: TPMLAudioStream; const ABuf: TBytes; AChunk: Integer);
var
  Off, N: Integer;
begin
  Off := 0;
  while Off < Length(ABuf) do
  begin
    N := Length(ABuf) - Off;
    if N > AChunk then
      N := AChunk;
    AStream.PutData(@ABuf[Off], N);
    Inc(Off, N);
  end;
end;

function Spec(AFormat: TPMLAudioFormat; AChannels, AFreq: Integer): TPMLAudioSpec;
begin
  Result := TPMLAudioSpec.Make(AFormat, AChannels, AFreq);
end;

function SameCase(K: Integer; ABytes: Integer; AExtra1: Integer = 0; AExtra2: Integer = 0): Boolean;
begin
  Result := (FnvH = StreamCases[K].Hash) and (ABytes = StreamCases[K].Bytes)
    and (AExtra1 = StreamCases[K].Extra1) and (AExtra2 = StreamCases[K].Extra2);
  if not Result then
    WriteLn(Format('      hash %.8x bytes %d extra %d %d / expected %.8x %d %d %d',
      [FnvH, ABytes, AExtra1, AExtra2, StreamCases[K].Hash, StreamCases[K].Bytes,
       StreamCases[K].Extra1, StreamCases[K].Extra2]));
end;

type
  TPlainProc = procedure;

  { 呼び出しの量を覚える。 }
  TCallbackLog = class
  public
    PutAdd, GetAdd, GetTotal: Integer;
    constructor Create;
    procedure OnPut(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
    procedure OnGet(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
  end;

var
  Released: Integer = 0;

constructor TCallbackLog.Create;
begin
  inherited Create;
  PutAdd := -1;
  GetAdd := -1;
  GetTotal := -1;
end;

procedure TCallbackLog.OnPut(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
begin
  if PutAdd < 0 then
    PutAdd := AAdditional;
end;

procedure TCallbackLog.OnGet(AStream: TPMLAudioStream; AAdditional, ATotal: Integer);
begin
  if GetAdd < 0 then
  begin
    GetAdd := AAdditional;
    GetTotal := ATotal;
  end;
end;

procedure CountRelease(AUserData: Pointer; ABuf: Pointer; ALen: Integer);
begin
  Inc(Released);
end;

procedure Guard(AProc: TPlainProc);
begin
  try
    AProc;
  except
    on E: Exception do
      Check(False, '思わぬ例外: ' + E.ClassName + ': ' + E.Message);
  end;
end;

function Raises(AStream: TPMLAudioStream; AWhat: Integer): Boolean;
var
  B: array[0..15] of Byte;
  S: TPMLAudioStream;
begin
  Result := False;
  FillChar(B, SizeOf(B), 0);
  S := nil;
  try
    case AWhat of
      0: S := TPMLAudioStream.Create(Spec(TPMLAudioFormat($8018), 2, 48000), Spec(PML_AUDIO_S16, 2, 48000));
      1: S := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 9, 48000), Spec(PML_AUDIO_S16, 2, 48000));
      2: S := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 2, 48000), Spec(PML_AUDIO_S16, 2, 0));
      3: AStream.PutData(@B[0], 3);
      4: AStream.SetInputChannelMap(TPMLChannelMap.Create(0, 1, 2));
      5: AStream.SetInputChannelMap(TPMLChannelMap.Create(0, 2));
      6: AStream.FrequencyRatio := 0.001;
      7: AStream.FrequencyRatio := 200;
      8: AStream.Gain := -1;
      9: AStream.PutPlanarData([@B[0]], 2);
    end;
  except
    on E: Exception do
      Result := E is EPMLArgument;
  end;
  S.Free;
end;

procedure TestApi;
var
  S: TPMLAudioStream;
  Map: TPMLChannelMap;
  Buf: TBytes;
  Out: array[0..4095] of Byte;
  I: Integer;
  Ok: Boolean;
begin
  WriteLn('1. 引数と状態');
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 2, 44100), Spec(PML_AUDIO_F32, 2, 48000));
  try
    Check((S.SrcSpec.Freq = 44100) and (S.DstSpec.Format = PML_AUDIO_F32) and (S.Gain = 1.0)
      and (S.FrequencyRatio = 1.0), '作った直後の形式・音量 1・比 1');
    Ok := True;
    for I := 0 to 9 do
      if not Raises(S, I) then
      begin
        WriteLn('      ', I, ' は EPMLArgument にならない');
        Ok := False;
      end;
    Check(Ok, '形式・チャンネル数・周波数・半端なフレーム・並びの長さと値・比の範囲・負の音量・平面の数は EPMLArgument');
    S.SetInputChannelMap(TPMLChannelMap.Create(1, 0));
    Map := S.InputChannelMap;
    Check((Length(Map) = 2) and (Map[0] = 1) and (Map[1] = 0), '入力の並びを読み戻せる（写し）');
    S.SetInputChannelMap(TPMLChannelMap.Create(0, 1));
    Check(Length(S.InputChannelMap) = 0, '恒等の並びは既定（空）に戻る');
    S.SetInputChannelMap(TPMLChannelMap.Create(1, 0));
    S.SetSrcFormat(Spec(PML_AUDIO_S16, 1, 44100));
    Check(Length(S.InputChannelMap) = 0, '入力のチャンネル数を変えると入力の並びが消える');
    S.SetFormat(Spec(PML_AUDIO_S16, 2, 44100), Spec(PML_AUDIO_F32, 2, 48000));
    Lcg := 1;
    Buf := MakeInput(PML_AUDIO_S16, 2, 64);
    S.PutData(@Buf[0], Length(Buf));
    Check(S.Queued = 256, 'Queued は入力のバイト数（64 フレーム x 4 バイト）');
    S.Clear;
    Check((S.Queued = 0) and (S.Available = 0), 'Clear で空になる');
    Released := 0;
    S.PutDataNoCopy(@Buf[0], Length(Buf), @CountRelease, nil);
    S.Flush;
    while S.GetData(@Out[0], SizeOf(Out)) > 0 do
      ;
    Check(Released = 1, '写さない入力は、使い終えたら解放の知らせが 1 回来る');
    Released := 0;
    S.PutDataNoCopy(@Buf[0], Length(Buf), @CountRelease, nil);
  finally
    S.Free;
  end;
  Check(Released = 1, '使い終える前に Free しても、解放の知らせは来る');
end;

procedure TestCases;
var
  S: TPMLAudioStream;
  Inp, Inp2, L, R: TBytes;
  N, A, Q, Before: Integer;
  Small: array[0..799] of Byte;
  Log: TCallbackLog;
  Conv: TBytes;
begin
  WriteLn('2. SDL と比べる（FNV-1a）');
  // 0
  Lcg := 500;
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 2, 44100), Spec(PML_AUDIO_S16, 2, 48000));
  Inp := MakeInput(PML_AUDIO_S16, 2, 1000);
  FnvReset; PutChunks(S, Inp, 37 * 4); S.Flush; N := Drain(S, 333);
  Check(SameCase(0, N), 'S16 2ch 44100 → 48000（37 フレームずつ入れ、333 バイトずつ出す）');
  S.Free;
  // 1
  Lcg := 501;
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_F32, 1, 22050), Spec(PML_AUDIO_F32, 1, 48000));
  Inp := MakeInput(PML_AUDIO_F32, 1, 500);
  FnvReset; S.PutData(@Inp[0], Length(Inp)); S.Flush; N := Drain(S, 4096);
  Check(SameCase(1, N), 'F32 1ch 22050 → 48000');
  S.Free;
  // 2
  Lcg := 502;
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 1, 8000), Spec(PML_AUDIO_F32, 2, 44100));
  Inp := MakeInput(PML_AUDIO_S16, 1, 400);
  FnvReset; S.PutData(@Inp[0], Length(Inp)); S.Flush; N := Drain(S, 1000);
  Check(SameCase(2, N), 'S16 1ch 8000 → F32 2ch 44100（チャンネルを増やすのは変換の後）');
  S.Free;
  // 3
  Lcg := 503;
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_F32, 6, 96000), Spec(PML_AUDIO_S16, 2, 44100));
  Inp := MakeInput(PML_AUDIO_F32, 6, 600);
  FnvReset; PutChunks(S, Inp, 24 * 50); S.Flush; N := Drain(S, 512);
  Check(SameCase(3, N), 'F32 6ch 96000 → S16 2ch 44100（チャンネルを減らすのは変換の前）');
  S.Free;
  // 4
  Lcg := 504;
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_U8, 2, 48000), Spec(PML_AUDIO_S32, 2, 32000));
  S.Gain := 0.6;
  Inp := MakeInput(PML_AUDIO_U8, 2, 700);
  FnvReset; S.PutData(@Inp[0], Length(Inp)); S.Flush; N := Drain(S, 800);
  Check(SameCase(4, N), 'U8 2ch 48000 → S32 2ch 32000、音量 0.6');
  S.Free;
  // 5
  Lcg := 505;
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 2, 48000), Spec(PML_AUDIO_S16, 2, 48000));
  S.FrequencyRatio := 1.25;
  Inp := MakeInput(PML_AUDIO_S16, 2, 600);
  FnvReset; S.PutData(@Inp[0], 1200);
  N := S.GetData(@Small[0], 800); FnvAdd(@Small[0], N);
  S.FrequencyRatio := 0.8;
  S.PutData(@Inp[1200], 1200); S.Flush; N := N + Drain(S, 640);
  Check(SameCase(5, N), '周波数の比 1.25、途中で 0.8');
  S.Free;
  // 6
  Lcg := 506;
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 2, 44100), Spec(PML_AUDIO_S16, 2, 48000));
  Inp := MakeInput(PML_AUDIO_S16, 2, 200);
  FnvReset; S.PutData(@Inp[0], Length(Inp));
  S.SetSrcFormat(Spec(PML_AUDIO_F32, 1, 22050));
  Inp2 := MakeInput(PML_AUDIO_F32, 1, 200);
  S.PutData(@Inp2[0], Length(Inp2)); S.Flush; N := Drain(S, 700);
  Check(SameCase(6, N), '入力の形式を途中で変える（S16 2ch 44100 → F32 1ch 22050）');
  S.Free;
  // 7
  Lcg := 507;
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 2, 44100), Spec(PML_AUDIO_S16, 2, 48000));
  Inp := MakeInput(PML_AUDIO_S16, 2, 1000);
  FnvReset; S.PutData(@Inp[0], Length(Inp)); A := S.Available; Before := Drain(S, 4000);
  S.Flush; N := Before + Drain(S, 4000);
  Check(SameCase(7, N, A, Before), '流し切る前に出せる量（余白の分だけ少ない）と、流し切った後の残り');
  S.Free;
  // 8
  Lcg := 508;
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 2, 44100), Spec(PML_AUDIO_F32, 2, 48000));
  Inp := MakeInput(PML_AUDIO_S16, 2, 100);
  FnvReset; S.PutData(@Inp[0], Length(Inp)); A := S.Available; Q := S.Queued; S.Flush; N := S.Available;
  Drain(S, 4096);
  Check(SameCase(8, N, A, Q), 'Available と Queued（流し切る前と後）');
  S.Free;
  // 9
  Lcg := 509;
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 2, 44100), Spec(PML_AUDIO_S16, 2, 48000));
  Inp := MakeInput(PML_AUDIO_S16, 2, 150);
  FnvReset; S.PutData(@Inp[0], 400); S.Clear; S.PutData(@Inp[400], 200); S.Flush; N := Drain(S, 4096);
  Check(SameCase(9, N), 'Clear の後に入れた分だけが出る（変換の途中の状態も消える）');
  S.Free;
  // 10
  Lcg := 510;
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 4, 48000), Spec(PML_AUDIO_S16, 2, 44100));
  S.SetInputChannelMap(TPMLChannelMap.Create(3, 2, 1, 0));
  Inp := MakeInput(PML_AUDIO_S16, 4, 300);
  FnvReset; S.PutData(@Inp[0], Length(Inp)); S.Flush; N := Drain(S, 4096);
  Check(SameCase(10, N), '入力の並びと周波数の変換');
  S.Free;
  // 11
  Lcg := 511;
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_F32, 2, 48000), Spec(PML_AUDIO_S16, 2, 48000));
  L := MakeInput(PML_AUDIO_F32, 1, 100);
  R := MakeInput(PML_AUDIO_F32, 1, 100);
  FnvReset; S.PutPlanarData([@L[0], @R[0]], 100); S.Flush; N := Drain(S, 4096);
  Check(SameCase(11, N), 'チャンネルごとの置き場からの入力');
  S.Free;
  // 12
  Lcg := 512;
  Inp := MakeInput(PML_AUDIO_S16, 2, 256);
  Conv := PMLConvertAudioSamples(Spec(PML_AUDIO_S16, 2, 44100), @Inp[0], Length(Inp), Spec(PML_AUDIO_F32, 2, 48000));
  FnvReset;
  if Length(Conv) > 0 then
    FnvAdd(@Conv[0], Length(Conv));
  Check(SameCase(12, Length(Conv)), 'PMLConvertAudioSamples（S16 2ch 44100 → F32 2ch 48000）');
  // 14
  Lcg := 514;
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_F32, 6, 96000), Spec(PML_AUDIO_F32, 2, 44100));
  Inp := MakeInput(PML_AUDIO_F32, 6, 300);
  FnvReset; S.PutData(@Inp[0], Length(Inp)); S.Flush; N := Drain(S, 4096);
  Check(SameCase(14, N), 'F32 6ch 96000 → F32 2ch 44100（減らすのは変換の前。F32 なので丸めの差が残る）');
  S.Free;
  // 13
  Lcg := 513;
  S := TPMLAudioStream.Create(Spec(PML_AUDIO_S16, 2, 44100), Spec(PML_AUDIO_S16, 2, 48000));
  Log := TCallbackLog.Create;
  try
    Inp := MakeInput(PML_AUDIO_S16, 2, 100);
    S.OnPut := @Log.OnPut;
    S.OnGet := @Log.OnGet;
    S.PutData(@Inp[0], Length(Inp));
    SetLength(Conv, 2000);
    S.GetData(@Conv[0], 2000);
    FnvH := 0;
    Check(SameCase(13, Log.PutAdd, Log.GetAdd, Log.GetTotal),
      'OnPut の増えた量、OnGet の足りない量と求められた量（入力のバイト数に直したもの）');
  finally
    S.Free;
    Log.Free;
  end;
end;

begin
  WriteLn('test_audio_stream — 音声のストリーム');
  WriteLn;
  Guard(@TestApi);
  WriteLn;
  Guard(@TestCases);
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: 音声のストリームが SDL と同じ値を出す ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
