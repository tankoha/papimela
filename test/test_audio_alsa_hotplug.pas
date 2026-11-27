{
  test_audio_alsa_hotplug — ALSA の hotplug が udev の知らせですぐ届く（実機。手元専用）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    ALSA のバックエンドを選び、走査の間隔を 60 秒にして（スレッドの道なら追加が見えるまで最大 60 秒かかる）、
    イベントを回しながら、別の端末で次を実行してもらう:
      sudo modprobe snd-dummy     → AudioDeviceAdded が来る（再生と録音のデバイスが 1 台ずつ以上）
      sudo rmmod snd-dummy        → AudioDeviceRemoved が来る
    それぞれ、カーネルの変化（/proc/modules の snd_dummy。このプログラムが自分で観測する）から 5 秒以内に
    届けば PASS（走査の間隔 60 秒より十分に短いので、udev の知らせで走査できている）。20 秒待って届かなければ FAIL。

  WHY:
    SDL の ALSA は udev が使えれば、5 秒ごとの走査でなく、知らせですぐ走査する。papimela の
    TPMLAlsaHotplugDriver（CI の test_alsa_hotplug は偽の窓口で確かめる）を、本物の udev と
    本物のカーネルの知らせで確かめる。snd-dummy は何も鳴らさない仮想のサウンドカード（modprobe に root が要る）。

  実行前提: libasound、libudev、snd-dummy のカーネルモジュール（Raspberry Pi OS / Ubuntu の標準のカーネルにある）。
    すでに snd-dummy が読み込まれていたら、先に sudo rmmod snd-dummy する。環境が無ければ
    PAPIMELA_ALSA_HOTPLUG_OPTIONAL=1 で飛ばす（既定では失敗）。手元専用。
}
program test_audio_alsa_hotplug;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils, Classes, DateUtils,
  PaPiMeLa.Properties,
  PaPiMeLa.Log,
  PaPiMeLa.Events,
  PaPiMeLa.Core,
  PaPiMeLa.Errors,
  PaPiMeLa.Audio,
  PaPiMeLa.Audio.Alsa;

const
  WaitSeconds = 20;

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
  Flush(Output);
end;

function ModuleLoaded: Boolean;
var
  L: TStringList;
begin
  Result := False;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile('/proc/modules');
      Result := Pos('snd_dummy ', L.Text) > 0;
    except
      on E: Exception do
        WriteLn('  [INFO] /proc/modules を読めない: ', E.Message);
    end;
  finally
    L.Free;
  end;
end;

{ 指定の種類のイベントが来るまで回す。戻り値: 来たなら、カーネルの変化（snd_dummy が読み込まれた / 外れた。
  このプログラム自身が /proc/modules を見て観測する）からイベントまでのミリ秒、来なければ -1。
  人がコマンドを打つ時間は含まれない。AKernelMs にカーネルの変化を見るまでの経過を返す。 }
function WaitFor(ACtx: TPMLContext; AKind: TPMLEventKind; AWantLoaded: Boolean; out AEvents: Integer): Integer;
var
  Ev: TPMLEvent;
  T0, TKernel: QWord;
begin
  AEvents := 0;
  Result := -1;
  TKernel := 0;
  T0 := GetTickCount64;
  while GetTickCount64 - T0 < QWord(WaitSeconds) * 1000 do
  begin
    ACtx.Events.Pump(20);
    if (TKernel = 0) and (ModuleLoaded = AWantLoaded) then
      TKernel := GetTickCount64;
    while ACtx.Events.Poll(Ev) do
      if Ev.Kind = AKind then
      begin
        Inc(AEvents);
        WriteLn('    ', Ev.Kind, ' ', Ev.AudioDevice.Which, BoolToStr(Ev.AudioDevice.Recording, ' (録音)', ' (再生)'));
        if Result < 0 then
        begin
          if TKernel = 0 then
            TKernel := T0;   // カーネルの変化を先に見られなかった（Pump の間に済んだ）ときは、待ち始めからで測る
          Result := Integer(GetTickCount64 - TKernel);
        end;
      end;
    if Result >= 0 then
    begin
      // 再生と録音の 2 つ目が少し遅れて来ることがあるので、もう少し集める
      T0 := GetTickCount64;
      while GetTickCount64 - T0 < 800 do
      begin
        ACtx.Events.Pump(20);
        while ACtx.Events.Poll(Ev) do
          if Ev.Kind = AKind then
          begin
            Inc(AEvents);
            WriteLn('    ', Ev.Kind, ' ', Ev.AudioDevice.Which, BoolToStr(Ev.AudioDevice.Recording, ' (録音)', ' (再生)'));
          end;
      end;
      Exit;
    end;
  end;
end;

var
  Ctx: TPMLContext;
  Opts: TPMLContextOptions;
  Ev: TPMLEvent;
  Ms, N: Integer;
begin
  WriteLn('=== test_audio_alsa_hotplug ===');
  Flush(Output);
  if ModuleLoaded then
  begin
    WriteLn('snd-dummy がすでに読み込まれている。先に: sudo rmmod snd-dummy');
    Halt(2);
  end;
  Opts := TPMLContextOptions.Default;
  Opts.PreferredAudio := 'alsa';
  Opts.MinimumLogLevel := TPMLLogPriority.Critical;
  Opts.Hints.Add(PML_HINT_AUDIO_ALSA_HOTPLUG_INTERVAL, '60000');   // スレッドの道なら、見えるまで最大 60 秒
  try
    Ctx := TPMLContext.Create([TPMLSubsystem.Audio], Opts);
  except
    on E: Exception do
    begin
      WriteLn('Context を作れない（libasound が無い？）: ', E.Message);
      if GetEnvironmentVariable('PAPIMELA_ALSA_HOTPLUG_OPTIONAL') = '1' then
      begin
        WriteLn('飛ばす（PAPIMELA_ALSA_HOTPLUG_OPTIONAL=1）');
        Halt(0);
      end;
      Halt(1);
    end;
  end;
  try
    Check(Ctx.Audio.BackendName = 'alsa', 'ALSA のバックエンドを選べた');
    // 最初の追加（既定など）を捨てる
    Ctx.Events.Pump(0);
    while Ctx.Events.Poll(Ev) do
      ;
    WriteLn;
    WriteLn('>>> いまから ', WaitSeconds, ' 秒以内に、別の端末で:  sudo modprobe snd-dummy');
    Flush(Output);
    Ms := WaitFor(Ctx, TPMLEventKind.AudioDeviceAdded, True, N);
    Check(Ms >= 0, Format('snd-dummy を読み込むと AudioDeviceAdded が来る（カーネルの変化から %d ミリ秒、%d 件）', [Ms, N]));
    if Ms >= 0 then
      Check(Ms < 5000, 'カーネルの変化から 5 秒以内に届く（60 秒の走査ではない。udev の知らせで走査した）');
    WriteLn;
    WriteLn('>>> いまから ', WaitSeconds, ' 秒以内に、別の端末で:  sudo rmmod snd-dummy');
    Flush(Output);
    Ms := WaitFor(Ctx, TPMLEventKind.AudioDeviceRemoved, False, N);
    Check(Ms >= 0, Format('snd-dummy を外すと AudioDeviceRemoved が来る（カーネルの変化から %d ミリ秒、%d 件）', [Ms, N]));
    if Ms >= 0 then
      Check(Ms < 5000, 'カーネルの変化から 5 秒以内に届く（60 秒の走査ではない。udev の知らせで走査した）');
  finally
    Ctx.Free;
  end;
  WriteLn;
  if Failures = 0 then
    WriteLn('ALL PASSED')
  else
    WriteLn('FAILED: ', Failures);
  if Failures <> 0 then
    Halt(1);
end.
