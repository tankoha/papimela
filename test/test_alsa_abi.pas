{
  test_alsa_abi — libasound の結合の写し（定数・構造体の並び・関数）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. チャンネルの並びの構造体の大きさと欄の位置が、本物のヘッダで動かした C の値
       （test/alsa_abi_expected.inc）と同じ。型の大きさ
    2. 結合する関数がこの機械の libasound.so.2 に全部ある（ライブラリがあるとき）。xxx_sizeof() が動く
    3. 並びの位置の読み書き（PMLAlsaChmapPos / SetPos）

  WHY:
    オーディオの残りの #20（Platform.Alsa）の受け入れ検査。音の装置も要らない（ライブラリが無ければ
    2 は飛ばす）。
}
program test_alsa_abi;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, ctypes,
  PaPiMeLa.Platform.Alsa;

{$I alsa_abi_expected.inc}

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

procedure CheckVal(const AName: String; AGot, AWant: PtrInt);
begin
  Check(AGot = AWant, Format('%s = %d（C: %d）', [AName, AGot, AWant]));
end;

procedure TestLayouts;
var
  Q: TSndPcmChmapQuery;
  Base: PtrUInt;
begin
  WriteLn('-- 構造体の大きさと欄の位置');
  CheckVal('sizeof(snd_pcm_chmap_t)', SizeOf(TSndPcmChmap), ALS_snd_pcm_chmap_t);
  CheckVal('offsetof(snd_pcm_chmap_t, channels)', 0, ALO_snd_pcm_chmap_t_channels);
  CheckVal('offsetof(snd_pcm_chmap_t, pos)', SizeOf(TSndPcmChmap), ALO_snd_pcm_chmap_t_pos);
  CheckVal('sizeof(snd_pcm_chmap_query_t)', SizeOf(Q), ALS_snd_pcm_chmap_query_t);
  Base := PtrUInt(@Q);
  CheckVal('offsetof(snd_pcm_chmap_query_t, type)', PtrUInt(@Q.ChmapType) - Base, ALO_snd_pcm_chmap_query_t_type);
  CheckVal('offsetof(snd_pcm_chmap_query_t, map)', PtrUInt(@Q.Map) - Base, ALO_snd_pcm_chmap_query_t_map);
  WriteLn('-- 型の大きさ');
  CheckVal('snd_pcm_uframes_t（culong）', SizeOf(culong), ALS_snd_pcm_uframes_t);
  CheckVal('snd_pcm_sframes_t（clong）', SizeOf(clong), ALS_snd_pcm_sframes_t);
  CheckVal('snd_pcm_format_t（cint）', SizeOf(cint), ALS_snd_pcm_format_t);
  CheckVal('snd_pcm_access_t（cint）', SizeOf(cint), ALS_snd_pcm_access_t);
  CheckVal('snd_pcm_stream_t（cint）', SizeOf(cint), ALS_snd_pcm_stream_t);
  CheckVal('snd_pcm_state_t（cint）', SizeOf(cint), ALS_snd_pcm_state_t);
  CheckVal('enum snd_pcm_chmap_type（cint）', SizeOf(cint), ALS_enum_snd_pcm_chmap_type);
  CheckVal('enum snd_pcm_chmap_position（cuint）', SizeOf(cuint), ALS_enum_snd_pcm_chmap_position);
end;

procedure TestChmapAccess;
var
  Buf: array[0..7] of cuint;
  M: PSndPcmChmap;
  I: Integer;
  Ok: Boolean;
begin
  WriteLn('-- 並びの位置の読み書き');
  FillChar(Buf, SizeOf(Buf), 0);
  M := PSndPcmChmap(@Buf[0]);
  M^.Channels := 3;
  PMLAlsaChmapSetPos(M, 0, SND_CHMAP_FL);
  PMLAlsaChmapSetPos(M, 1, SND_CHMAP_FR);
  PMLAlsaChmapSetPos(M, 2, SND_CHMAP_LFE);
  Check((Buf[1] = SND_CHMAP_FL) and (Buf[2] = SND_CHMAP_FR) and (Buf[3] = SND_CHMAP_LFE),
    '位置は channels の次の cuint から並ぶ');
  Ok := True;
  for I := 0 to 2 do
    if PMLAlsaChmapPos(M, I) <> Buf[I + 1] then
      Ok := False;
  Check(Ok, 'PMLAlsaChmapPos が書いた値を読める');
end;

procedure TestLibrary;
var
  Lib: TPMLAlsa;
begin
  WriteLn('-- 結合する関数');
  if not TPMLAlsa.IsAvailable then
  begin
    WriteLn('  （libasound.so.2 が無いので飛ばす）');
    Exit;
  end;
  Lib := TPMLAlsa.Create;
  try
    Check(Assigned(Lib.API.pcm_open) and Assigned(Lib.API.pcm_writei) and Assigned(Lib.API.pcm_hw_params_any)
      and Assigned(Lib.API.ctl_open) and Assigned(Lib.API.pcm_query_chmaps) and Assigned(Lib.API.device_name_hint),
      '主な関数が解決できた');
    Check(Lib.API.pcm_hw_params_sizeof() > 0, 'snd_pcm_hw_params_sizeof が呼べる: ' + IntToStr(Lib.API.pcm_hw_params_sizeof()));
    Check(Lib.API.pcm_sw_params_sizeof() > 0, 'snd_pcm_sw_params_sizeof が呼べる: ' + IntToStr(Lib.API.pcm_sw_params_sizeof()));
    Check(Lib.API.pcm_info_sizeof() > 0, 'snd_pcm_info_sizeof が呼べる: ' + IntToStr(Lib.API.pcm_info_sizeof()));
    Check(Lib.API.ctl_card_info_sizeof() > 0, 'snd_ctl_card_info_sizeof が呼べる: ' + IntToStr(Lib.API.ctl_card_info_sizeof()));
    Check(Lib.API.strerror(-ENOENT) <> nil, 'snd_strerror が呼べる: ' + String(Lib.API.strerror(-ENOENT)));
  finally
    Lib.Free;
  end;
end;

begin
  WriteLn('=== test_alsa_abi ===');
  TestLayouts;
  TestChmapAccess;
  TestLibrary;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 全部通った ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
