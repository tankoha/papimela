{
  demo_audio_tone — 既定の再生のデバイスで音を鳴らす（耳で確かめる）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    オーディオのバックエンド（既定は PipeWire）で既定の再生のデバイスを開き、
    1. 440 Hz の正弦波を F32 2ch 48000 で 2 秒（左右とも）
    2. 660 Hz を S16 1ch 22050 で 2 秒（周波数とチャンネル数の変換を通る）
    3. 左だけ 1 秒、右だけ 1 秒（チャンネルの並びの確かめ）
    を鳴らす。音量は -20 dB（振幅 0.1）。

  使い方:
    test/demo_audio_tone [バックエンドの名前]
    聞こえ方: 1 は同じ高さの音が 2 秒、2 は少し高い音が 2 秒、3 は左のスピーカーから 1 秒、
    次に右から 1 秒。ぶつぶつ切れる・速さが違う・左右が逆なら誤り。
}
program demo_audio_tone;

{$mode objfpc}{$H+}

uses
  cthreads,
  SysUtils,
  PaPiMeLa.Log,
  PaPiMeLa.Core,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Stream,
  PaPiMeLa.Audio.Backend,
  PaPiMeLa.Audio,
  PaPiMeLa.Backends;

const
  Amplitude = 0.1;

procedure PlayF32(ACtx: TPMLContext; AFreq: Double; ASeconds: Double; ALeft, ARight: Boolean);
var
  S: TPMLAudioStream;
  Buf: array of Single;
  I, Frames: Integer;
  V: Single;
begin
  Frames := Round(48000 * ASeconds);
  Buf := nil;
  SetLength(Buf, Frames * 2);
  for I := 0 to Frames - 1 do
  begin
    V := Single(Amplitude * Sin(2 * Pi * AFreq * I / 48000));
    if ALeft then
      Buf[I * 2] := V
    else
      Buf[I * 2] := 0;
    if ARight then
      Buf[I * 2 + 1] := V
    else
      Buf[I * 2 + 1] := 0;
  end;
  S := ACtx.Audio.OpenDeviceStream(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK, TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000));
  try
    S.PutData(@Buf[0], Length(Buf) * 4);
    S.Flush;
    ACtx.Audio.ResumeStreamDevice(S);
    while S.Queued > 0 do
      Sleep(20);
    Sleep(150);
  finally
    S.Free;
  end;
end;

procedure PlayS16Mono(ACtx: TPMLContext; AFreq: Double; ASeconds: Double);
var
  S: TPMLAudioStream;
  Buf: array of SmallInt;
  I, Frames: Integer;
begin
  Frames := Round(22050 * ASeconds);
  Buf := nil;
  SetLength(Buf, Frames);
  for I := 0 to Frames - 1 do
    Buf[I] := Round(32767 * Amplitude * Sin(2 * Pi * AFreq * I / 22050));
  S := ACtx.Audio.OpenDeviceStream(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK, TPMLAudioSpec.Make(PML_AUDIO_S16, 1, 22050));
  try
    S.PutData(@Buf[0], Length(Buf) * 2);
    S.Flush;
    ACtx.Audio.ResumeStreamDevice(S);
    while S.Queued > 0 do
      Sleep(20);
    Sleep(150);
  finally
    S.Free;
  end;
end;

var
  Opts: TPMLContextOptions;
  Ctx: TPMLContext;
  Keeper: TPMLLogicalAudioDevice;
begin
  Opts := TPMLContextOptions.Default;
  if ParamCount >= 1 then
    Opts.PreferredAudio := ParamStr(1);
  Opts.MinimumLogLevel := TPMLLogPriority.Warn;
  Ctx := TPMLContext.Create([TPMLSubsystem.Audio], Opts);
  try
    WriteLn('バックエンド: ', Ctx.Audio.BackendName);
    WriteLn('既定の再生: ', Ctx.Audio.DeviceName(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK));
    // 物理デバイスを F32 2ch 48000 で開いたままにする（2 の変換を papimela がするように）。
    Keeper := Ctx.Audio.OpenDevice(PML_AUDIO_DEVICE_DEFAULT_PLAYBACK, TPMLAudioSpec.Make(PML_AUDIO_F32, 2, 48000));
    WriteLn('デバイスの形式: ', PMLAudioFormatName(Keeper.Format.Format), ' ', Keeper.Format.Channels, 'ch ', Keeper.Format.Freq);
    WriteLn('1. 440 Hz、F32 2ch 48000、2 秒');
    PlayF32(Ctx, 440, 2, True, True);
    WriteLn('2. 660 Hz、S16 1ch 22050、2 秒（変換を通る）');
    PlayS16Mono(Ctx, 660, 2);
    WriteLn('3. 左だけ 1 秒、右だけ 1 秒');
    PlayF32(Ctx, 440, 1, True, False);
    PlayF32(Ctx, 440, 1, False, True);
    Keeper.Free;
    WriteLn('終わり');
  finally
    Ctx.Free;
  end;
end.
