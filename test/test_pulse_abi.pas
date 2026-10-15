{
  test_pulse_abi — libpulse の結合の写し（構造体の並び・定数・IS_GOOD）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 構造体の大きさと欄の位置が、本物のヘッダで動かした C の値（test/pulse_abi_expected.inc）と同じ
    2. 列挙の大きさ（4 バイト）
    3. PA_CONTEXT_IS_GOOD / PA_STREAM_IS_GOOD の結果が C のマクロと同じ
    4. 結合する関数がこの機械の libpulse.so.0 に全部ある（ライブラリがあるとき）

  WHY:
    オーディオの残りの #20（Platform.Pulse）の受け入れ検査。表示サーバも音の装置も PulseAudio の
    サーバも要らない（ライブラリが無ければ 4 は飛ばす）。
}
program test_pulse_abi;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, ctypes,
  PaPiMeLa.Platform.Pulse;

{$I pulse_abi_expected.inc}

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

procedure CheckSize(const AName: String; AGot, AWant: PtrInt);
begin
  Check(AGot = AWant, Format('sizeof(%s) = %d（C: %d）', [AName, AGot, AWant]));
end;

procedure CheckOfs(const AName: String; AGot, AWant: PtrInt);
begin
  Check(AGot = AWant, Format('offsetof(%s) = %d（C: %d）', [AName, AGot, AWant]));
end;

procedure TestLayouts;
var
  Sink: TPASinkInfo;
  Source: TPASourceInfo;
  Server: TPAServerInfo;
  Spec: TPASampleSpec;
  CMap: TPAChannelMap;
  Attr: TPABufferAttr;
  Vol: TPACVolume;
  Base: PtrUInt;
begin
  WriteLn('-- 構造体の大きさと欄の位置');
  CheckSize('pa_sample_spec', SizeOf(Spec), PAS_pa_sample_spec);
  Base := PtrUInt(@Spec);
  CheckOfs('pa_sample_spec.format', PtrUInt(@Spec.Format) - Base, PAO_pa_sample_spec_format);
  CheckOfs('pa_sample_spec.rate', PtrUInt(@Spec.Rate) - Base, PAO_pa_sample_spec_rate);
  CheckOfs('pa_sample_spec.channels', PtrUInt(@Spec.Channels) - Base, PAO_pa_sample_spec_channels);

  CheckSize('pa_channel_map', SizeOf(CMap), PAS_pa_channel_map);
  Base := PtrUInt(@CMap);
  CheckOfs('pa_channel_map.channels', PtrUInt(@CMap.Channels) - Base, PAO_pa_channel_map_channels);
  CheckOfs('pa_channel_map.map', PtrUInt(@CMap.Map) - Base, PAO_pa_channel_map_map);

  CheckSize('pa_buffer_attr', SizeOf(Attr), PAS_pa_buffer_attr);
  Base := PtrUInt(@Attr);
  CheckOfs('pa_buffer_attr.maxlength', PtrUInt(@Attr.MaxLength) - Base, PAO_pa_buffer_attr_maxlength);
  CheckOfs('pa_buffer_attr.tlength', PtrUInt(@Attr.TLength) - Base, PAO_pa_buffer_attr_tlength);
  CheckOfs('pa_buffer_attr.prebuf', PtrUInt(@Attr.PreBuf) - Base, PAO_pa_buffer_attr_prebuf);
  CheckOfs('pa_buffer_attr.minreq', PtrUInt(@Attr.MinReq) - Base, PAO_pa_buffer_attr_minreq);
  CheckOfs('pa_buffer_attr.fragsize', PtrUInt(@Attr.FragSize) - Base, PAO_pa_buffer_attr_fragsize);

  CheckSize('pa_cvolume', SizeOf(Vol), PAS_pa_cvolume);
  Base := PtrUInt(@Vol);
  CheckOfs('pa_cvolume.channels', PtrUInt(@Vol.Channels) - Base, PAO_pa_cvolume_channels);
  CheckOfs('pa_cvolume.values', PtrUInt(@Vol.Values) - Base, PAO_pa_cvolume_values);

  // コールバックが渡してくる構造体は前半だけを写した。使う欄の位置が合えばよい。
  Base := PtrUInt(@Sink);
  CheckOfs('pa_sink_info.name', PtrUInt(@Sink.Name) - Base, PAO_pa_sink_info_name);
  CheckOfs('pa_sink_info.index', PtrUInt(@Sink.Index) - Base, PAO_pa_sink_info_index);
  CheckOfs('pa_sink_info.description', PtrUInt(@Sink.Description) - Base, PAO_pa_sink_info_description);
  CheckOfs('pa_sink_info.sample_spec', PtrUInt(@Sink.SampleSpec) - Base, PAO_pa_sink_info_sample_spec);
  CheckOfs('pa_sink_info.channel_map', PtrUInt(@Sink.ChannelMap) - Base, PAO_pa_sink_info_channel_map);
  CheckOfs('pa_sink_info.owner_module', PtrUInt(@Sink.OwnerModule) - Base, PAO_pa_sink_info_owner_module);
  CheckOfs('pa_sink_info.volume', PtrUInt(@Sink.Volume) - Base, PAO_pa_sink_info_volume);
  CheckOfs('pa_sink_info.mute', PtrUInt(@Sink.Mute) - Base, PAO_pa_sink_info_mute);
  CheckOfs('pa_sink_info.monitor_source', PtrUInt(@Sink.MonitorSource) - Base, PAO_pa_sink_info_monitor_source);
  CheckOfs('pa_sink_info.monitor_source_name', PtrUInt(@Sink.MonitorSourceName) - Base,
    PAO_pa_sink_info_monitor_source_name);

  Base := PtrUInt(@Source);
  CheckOfs('pa_source_info.name', PtrUInt(@Source.Name) - Base, PAO_pa_source_info_name);
  CheckOfs('pa_source_info.index', PtrUInt(@Source.Index) - Base, PAO_pa_source_info_index);
  CheckOfs('pa_source_info.description', PtrUInt(@Source.Description) - Base, PAO_pa_source_info_description);
  CheckOfs('pa_source_info.sample_spec', PtrUInt(@Source.SampleSpec) - Base, PAO_pa_source_info_sample_spec);
  CheckOfs('pa_source_info.channel_map', PtrUInt(@Source.ChannelMap) - Base, PAO_pa_source_info_channel_map);
  CheckOfs('pa_source_info.owner_module', PtrUInt(@Source.OwnerModule) - Base, PAO_pa_source_info_owner_module);
  CheckOfs('pa_source_info.volume', PtrUInt(@Source.Volume) - Base, PAO_pa_source_info_volume);
  CheckOfs('pa_source_info.mute', PtrUInt(@Source.Mute) - Base, PAO_pa_source_info_mute);
  CheckOfs('pa_source_info.monitor_of_sink', PtrUInt(@Source.MonitorOfSink) - Base,
    PAO_pa_source_info_monitor_of_sink);
  CheckOfs('pa_source_info.monitor_of_sink_name', PtrUInt(@Source.MonitorOfSinkName) - Base,
    PAO_pa_source_info_monitor_of_sink_name);

  Base := PtrUInt(@Server);
  CheckOfs('pa_server_info.user_name', PtrUInt(@Server.UserName) - Base, PAO_pa_server_info_user_name);
  CheckOfs('pa_server_info.host_name', PtrUInt(@Server.HostName) - Base, PAO_pa_server_info_host_name);
  CheckOfs('pa_server_info.server_version', PtrUInt(@Server.ServerVersion) - Base,
    PAO_pa_server_info_server_version);
  CheckOfs('pa_server_info.server_name', PtrUInt(@Server.ServerName) - Base, PAO_pa_server_info_server_name);
  CheckOfs('pa_server_info.sample_spec', PtrUInt(@Server.SampleSpec) - Base, PAO_pa_server_info_sample_spec);
  CheckOfs('pa_server_info.default_sink_name', PtrUInt(@Server.DefaultSinkName) - Base,
    PAO_pa_server_info_default_sink_name);
  CheckOfs('pa_server_info.default_source_name', PtrUInt(@Server.DefaultSourceName) - Base,
    PAO_pa_server_info_default_source_name);
  CheckOfs('pa_server_info.cookie', PtrUInt(@Server.Cookie) - Base, PAO_pa_server_info_cookie);
  CheckOfs('pa_server_info.channel_map', PtrUInt(@Server.ChannelMap) - Base, PAO_pa_server_info_channel_map);
  // 前半だけの構造体は、実物より小さくてよい（後ろの欄を読まない）が、写した欄は実物の中に収まる
  Check(SizeOf(Sink) <= PAS_pa_sink_info, '写した pa_sink_info は実物の中に収まる');
  Check(SizeOf(Source) <= PAS_pa_source_info, '写した pa_source_info は実物の中に収まる');
  Check(SizeOf(Server) <= PAS_pa_server_info, '写した pa_server_info は実物の中に収まる');
end;

procedure TestEnumSizes;
begin
  WriteLn('-- 列挙の大きさ（cint で受ける）');
  CheckSize('pa_sample_format_t', SizeOf(cint), PAS_pa_sample_format_t);
  CheckSize('pa_channel_position_t', SizeOf(cint), PAS_pa_channel_position_t);
  CheckSize('pa_channel_map_def_t', SizeOf(cint), PAS_pa_channel_map_def_t);
  CheckSize('pa_context_state_t', SizeOf(cint), PAS_pa_context_state_t);
  CheckSize('pa_stream_state_t', SizeOf(cint), PAS_pa_stream_state_t);
  CheckSize('pa_operation_state_t', SizeOf(cint), PAS_pa_operation_state_t);
  CheckSize('pa_stream_flags_t', SizeOf(cint), PAS_pa_stream_flags_t);
  CheckSize('pa_context_flags_t', SizeOf(cint), PAS_pa_context_flags_t);
  CheckSize('pa_seek_mode_t', SizeOf(cint), PAS_pa_seek_mode_t);
  CheckSize('pa_subscription_mask_t', SizeOf(cint), PAS_pa_subscription_mask_t);
  CheckSize('pa_subscription_event_type_t', SizeOf(cint), PAS_pa_subscription_event_type_t);
end;

procedure TestGood;
var
  I: Integer;
begin
  WriteLn('-- PA_CONTEXT_IS_GOOD / PA_STREAM_IS_GOOD');
  for I := 0 to High(PAGoodContext) do
    Check(PMLPulseContextIsGood(I) = PAGoodContext[I], Format('コンテキストの状態 %d', [I]));
  for I := 0 to High(PAGoodStream) do
    Check(PMLPulseStreamIsGood(I) = PAGoodStream[I], Format('ストリームの状態 %d', [I]));
end;

procedure TestLibrary;
var
  Lib: TPMLPulse;
begin
  WriteLn('-- 結合する関数');
  if not TPMLPulse.IsAvailable then
  begin
    WriteLn('  （libpulse.so.0 が無いので飛ばす）');
    Exit;
  end;
  Lib := TPMLPulse.Create;
  try
    Check(Assigned(Lib.API.threaded_mainloop_new) and Assigned(Lib.API.context_new_with_proplist)
      and Assigned(Lib.API.stream_new) and Assigned(Lib.API.stream_write) and Assigned(Lib.API.stream_peek)
      and Assigned(Lib.API.context_get_server_info) and Assigned(Lib.API.proplist_sets),
      '主な関数が解決できた');
    Check(Lib.API.get_library_version() <> nil, 'pa_get_library_version が呼べる: ' + String(Lib.API.get_library_version()));
    Check(Lib.API.strerror(0) <> nil, 'pa_strerror が呼べる');
  finally
    Lib.Free;
  end;
end;

begin
  WriteLn('=== test_pulse_abi ===');
  TestLayouts;
  TestEnumSizes;
  TestGood;
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
