{ test/pulse_abi_expected.inc — tools/genpulse.bb が libpulse のヘッダで C を動かして作る。
  手で直さない（17.0.0 のヘッダ）。PAS_* は構造体と列挙の大きさ、PAO_* は欄の位置。
  PAGoodContext / PAGoodStream は PA_CONTEXT_IS_GOOD / PA_STREAM_IS_GOOD の結果。 }

const
  PAS_pa_sample_spec = 12;
  PAO_pa_sample_spec_format = 0;
  PAO_pa_sample_spec_rate = 4;
  PAO_pa_sample_spec_channels = 8;
  PAS_pa_channel_map = 132;
  PAO_pa_channel_map_channels = 0;
  PAO_pa_channel_map_map = 4;
  PAS_pa_buffer_attr = 20;
  PAO_pa_buffer_attr_maxlength = 0;
  PAO_pa_buffer_attr_tlength = 4;
  PAO_pa_buffer_attr_prebuf = 8;
  PAO_pa_buffer_attr_minreq = 12;
  PAO_pa_buffer_attr_fragsize = 16;
  PAS_pa_cvolume = 132;
  PAO_pa_cvolume_channels = 0;
  PAO_pa_cvolume_values = 4;
  PAS_pa_sink_info = 416;
  PAO_pa_sink_info_name = 0;
  PAO_pa_sink_info_index = 8;
  PAO_pa_sink_info_description = 16;
  PAO_pa_sink_info_sample_spec = 24;
  PAO_pa_sink_info_channel_map = 36;
  PAO_pa_sink_info_owner_module = 168;
  PAO_pa_sink_info_volume = 172;
  PAO_pa_sink_info_mute = 304;
  PAO_pa_sink_info_monitor_source = 308;
  PAO_pa_sink_info_monitor_source_name = 312;
  PAS_pa_source_info = 416;
  PAO_pa_source_info_name = 0;
  PAO_pa_source_info_index = 8;
  PAO_pa_source_info_description = 16;
  PAO_pa_source_info_sample_spec = 24;
  PAO_pa_source_info_channel_map = 36;
  PAO_pa_source_info_owner_module = 168;
  PAO_pa_source_info_volume = 172;
  PAO_pa_source_info_mute = 304;
  PAO_pa_source_info_monitor_of_sink = 308;
  PAO_pa_source_info_monitor_of_sink_name = 312;
  PAS_pa_server_info = 200;
  PAO_pa_server_info_user_name = 0;
  PAO_pa_server_info_host_name = 8;
  PAO_pa_server_info_server_version = 16;
  PAO_pa_server_info_server_name = 24;
  PAO_pa_server_info_sample_spec = 32;
  PAO_pa_server_info_default_sink_name = 48;
  PAO_pa_server_info_default_source_name = 56;
  PAO_pa_server_info_cookie = 64;
  PAO_pa_server_info_channel_map = 68;
  PAS_pa_sample_format_t = 4;
  PAS_pa_channel_position_t = 4;
  PAS_pa_channel_map_def_t = 4;
  PAS_pa_context_state_t = 4;
  PAS_pa_stream_state_t = 4;
  PAS_pa_operation_state_t = 4;
  PAS_pa_stream_flags_t = 4;
  PAS_pa_context_flags_t = 4;
  PAS_pa_seek_mode_t = 4;
  PAS_pa_subscription_mask_t = 4;
  PAS_pa_subscription_event_type_t = 4;

  PAGoodContext: array[0..6] of Boolean = (False, True, True, True, True, False, False);
  PAGoodStream: array[0..4] of Boolean = (False, True, True, False, False);
