{ test/pipewire_abi_expected.inc — tools/genpipewire.bb が PipeWire のヘッダで C を動かして作る。
  手で直さない（PipeWire 1.6.2 のヘッダ）。PWS_* は構造体の大きさ、PWO_* は欄の位置（x86_64）。PWBuild は SDL の initialize_spa_info と
  spa_format_audio_raw_build の結果、PWParse は C で組み立てた pod と SDL の get_range_param /
  get_int_param の結果、PWJson は SDL の get_name_from_json と client_info の結果。 }

const
  PWS_spa_list = 16;
  PWO_spa_list_next = 0;
  PWO_spa_list_prev = 8;
  PWS_spa_callbacks = 16;
  PWO_spa_callbacks_funcs = 0;
  PWO_spa_callbacks_data = 8;
  PWS_spa_interface = 32;
  PWO_spa_interface_type = 0;
  PWO_spa_interface_version = 8;
  PWO_spa_interface_cb = 16;
  PWS_spa_hook = 48;
  PWO_spa_hook_link = 0;
  PWO_spa_hook_cb = 16;
  PWO_spa_hook_removed = 32;
  PWO_spa_hook_priv = 40;
  PWS_spa_dict_item = 16;
  PWO_spa_dict_item_key = 0;
  PWO_spa_dict_item_value = 8;
  PWS_spa_dict = 16;
  PWO_spa_dict_flags = 0;
  PWO_spa_dict_n_items = 4;
  PWO_spa_dict_items = 8;
  PWS_spa_pod = 8;
  PWO_spa_pod_size = 0;
  PWO_spa_pod_type = 4;
  PWS_spa_pod_prop = 16;
  PWO_spa_pod_prop_key = 0;
  PWO_spa_pod_prop_flags = 4;
  PWO_spa_pod_prop_value = 8;
  PWS_spa_pod_object_body = 8;
  PWO_spa_pod_object_body_type = 0;
  PWO_spa_pod_object_body_id = 4;
  PWS_spa_pod_object = 16;
  PWO_spa_pod_object_pod = 0;
  PWO_spa_pod_object_body = 8;
  PWS_spa_pod_choice_body = 16;
  PWO_spa_pod_choice_body_type = 0;
  PWO_spa_pod_choice_body_flags = 4;
  PWO_spa_pod_choice_body_child = 8;
  PWS_spa_pod_choice = 24;
  PWO_spa_pod_choice_pod = 0;
  PWO_spa_pod_choice_body = 8;
  PWS_spa_pod_array_body = 8;
  PWO_spa_pod_array_body_child = 0;
  PWS_spa_param_info = 32;
  PWO_spa_param_info_id = 0;
  PWO_spa_param_info_flags = 4;
  PWO_spa_param_info_user = 8;
  PWO_spa_param_info_seq = 12;
  PWS_pw_core_info = 56;
  PWO_pw_core_info_id = 0;
  PWO_pw_core_info_cookie = 4;
  PWO_pw_core_info_user_name = 8;
  PWO_pw_core_info_host_name = 16;
  PWO_pw_core_info_version = 24;
  PWO_pw_core_info_name = 32;
  PWO_pw_core_info_change_mask = 40;
  PWO_pw_core_info_props = 48;
  PWS_pw_node_info = 72;
  PWO_pw_node_info_id = 0;
  PWO_pw_node_info_max_input_ports = 4;
  PWO_pw_node_info_max_output_ports = 8;
  PWO_pw_node_info_change_mask = 16;
  PWO_pw_node_info_n_input_ports = 24;
  PWO_pw_node_info_n_output_ports = 28;
  PWO_pw_node_info_state = 32;
  PWO_pw_node_info_error = 40;
  PWO_pw_node_info_props = 48;
  PWO_pw_node_info_params = 56;
  PWO_pw_node_info_n_params = 64;
  PWS_pw_client_info = 24;
  PWO_pw_client_info_id = 0;
  PWO_pw_client_info_change_mask = 8;
  PWO_pw_client_info_props = 16;
  PWS_pw_buffer = 40;
  PWO_pw_buffer_buffer = 0;
  PWO_pw_buffer_user_data = 8;
  PWO_pw_buffer_size = 16;
  PWO_pw_buffer_requested = 24;
  PWS_spa_buffer = 24;
  PWO_spa_buffer_n_metas = 0;
  PWO_spa_buffer_n_datas = 4;
  PWO_spa_buffer_metas = 8;
  PWO_spa_buffer_datas = 16;
  PWS_spa_data = 40;
  PWO_spa_data_type = 0;
  PWO_spa_data_flags = 4;
  PWO_spa_data_fd = 8;
  PWO_spa_data_mapoffset = 16;
  PWO_spa_data_maxsize = 20;
  PWO_spa_data_data = 24;
  PWO_spa_data_chunk = 32;
  PWS_spa_chunk = 16;
  PWO_spa_chunk_offset = 0;
  PWO_spa_chunk_size = 4;
  PWO_spa_chunk_stride = 8;
  PWO_spa_chunk_flags = 12;
  PWS_pw_core_events = 80;
  PWO_pw_core_events_version = 0;
  PWO_pw_core_events_info = 8;
  PWO_pw_core_events_done = 16;
  PWO_pw_core_events_ping = 24;
  PWO_pw_core_events_error = 32;
  PWO_pw_core_events_remove_id = 40;
  PWO_pw_core_events_bound_id = 48;
  PWO_pw_core_events_add_mem = 56;
  PWO_pw_core_events_remove_mem = 64;
  PWO_pw_core_events_bound_props = 72;
  PWS_pw_core_methods = 72;
  PWO_pw_core_methods_version = 0;
  PWO_pw_core_methods_add_listener = 8;
  PWO_pw_core_methods_hello = 16;
  PWO_pw_core_methods_sync = 24;
  PWO_pw_core_methods_pong = 32;
  PWO_pw_core_methods_error = 40;
  PWO_pw_core_methods_get_registry = 48;
  PWO_pw_core_methods_create_object = 56;
  PWO_pw_core_methods_destroy = 64;
  PWS_pw_registry_events = 24;
  PWO_pw_registry_events_version = 0;
  PWO_pw_registry_events_global = 8;
  PWO_pw_registry_events_global_remove = 16;
  PWS_pw_registry_methods = 32;
  PWO_pw_registry_methods_version = 0;
  PWO_pw_registry_methods_add_listener = 8;
  PWO_pw_registry_methods_bind = 16;
  PWO_pw_registry_methods_destroy = 24;
  PWS_pw_node_events = 24;
  PWO_pw_node_events_version = 0;
  PWO_pw_node_events_info = 8;
  PWO_pw_node_events_param = 16;
  PWS_pw_node_methods = 48;
  PWO_pw_node_methods_version = 0;
  PWO_pw_node_methods_add_listener = 8;
  PWO_pw_node_methods_subscribe_params = 16;
  PWO_pw_node_methods_enum_params = 24;
  PWO_pw_node_methods_set_param = 32;
  PWO_pw_node_methods_send_command = 40;
  PWS_pw_metadata_events = 16;
  PWO_pw_metadata_events_version = 0;
  PWO_pw_metadata_events_property = 8;
  PWS_pw_client_events = 24;
  PWO_pw_client_events_version = 0;
  PWO_pw_client_events_info = 8;
  PWO_pw_client_events_permissions = 16;
  PWS_pw_stream_events = 96;
  PWO_pw_stream_events_version = 0;
  PWO_pw_stream_events_destroy = 8;
  PWO_pw_stream_events_state_changed = 16;
  PWO_pw_stream_events_control_info = 24;
  PWO_pw_stream_events_io_changed = 32;
  PWO_pw_stream_events_param_changed = 40;
  PWO_pw_stream_events_add_buffer = 48;
  PWO_pw_stream_events_remove_buffer = 56;
  PWO_pw_stream_events_process = 64;
  PWO_pw_stream_events_drained = 72;
  PWO_pw_stream_events_command = 80;
  PWO_pw_stream_events_trigger_done = 88;

type
  TPWBuildCase = record Name: String; Format: Word; Channels, Freq: Integer; Hex: String; end;
  TPWParseCase = record Name: String; Hex: String; RateOk: Boolean; RateDef, RateMin, RateMax: Integer;
    ChannelsOk: Boolean; Channels: Integer; end;
  TPWJsonName = record Input: String; Found: Boolean; Output: String; end;
  TPWJsonServices = record Input: String; HaveServices, HaveAudio: Boolean; end;
  TPWJsonTokens = record Input: String; Tokens: String; end;

const
  PWBuild: array[0..9] of TPWBuildCase = (
    (Name: 's16_2_48000'; Format: PML_AUDIO_S16LE; Channels: 2; Freq: 48000; Hex: 'a00000000f00000003000400030000000100000000000000040000000300000001000000000000000200000000000000040000000300000001000000000000000100010000000000040000000300000003010000000000000300010000000000040000000400000080bb0000000000000400010000000000040000000400000002000000000000000500010000000000100000000d00000004000000030000000300000004000000'),
    (Name: 'f32_2_44100'; Format: PML_AUDIO_F32LE; Channels: 2; Freq: 44100; Hex: 'a00000000f0000000300040003000000010000000000000004000000030000000100000000000000020000000000000004000000030000000100000000000000010001000000000004000000030000001b010000000000000300010000000000040000000400000044ac0000000000000400010000000000040000000400000002000000000000000500010000000000100000000d00000004000000030000000300000004000000'),
    (Name: 'u8_1_8000'; Format: PML_AUDIO_U8; Channels: 1; Freq: 8000; Hex: 'a00000000f000000030004000300000001000000000000000400000003000000010000000000000002000000000000000400000003000000010000000000000001000100000000000400000003000000020100000000000003000100000000000400000004000000401f00000000000004000100000000000400000004000000010000000000000005000100000000000c0000000d00000004000000030000000200000000000000'),
    (Name: 's8_3_22050'; Format: PML_AUDIO_S8; Channels: 3; Freq: 22050; Hex: 'a80000000f00000003000400030000000100000000000000040000000300000001000000000000000200000000000000040000000300000001000000000000000100010000000000040000000300000001010000000000000300010000000000040000000400000022560000000000000400010000000000040000000400000003000000000000000500010000000000140000000d000000040000000300000003000000040000000600000000000000'),
    (Name: 's16be_4_32000'; Format: PML_AUDIO_S16BE; Channels: 4; Freq: 32000; Hex: 'a80000000f000000030004000300000001000000000000000400000003000000010000000000000002000000000000000400000003000000010000000000000001000100000000000400000003000000040100000000000003000100000000000400000004000000007d0000000000000400010000000000040000000400000004000000000000000500010000000000180000000d000000040000000300000003000000040000000c0000000d000000'),
    (Name: 's32_5_96000'; Format: PML_AUDIO_S32LE; Channels: 5; Freq: 96000; Hex: 'b00000000f0000000300040003000000010000000000000004000000030000000100000000000000020000000000000004000000030000000100000000000000010001000000000004000000030000000b0100000000000003000100000000000400000004000000007701000000000004000100000000000400000004000000050000000000000005000100000000001c0000000d00000004000000030000000300000004000000050000000c0000000d00000000000000'),
    (Name: 's32be_6_48000'; Format: PML_AUDIO_S32BE; Channels: 6; Freq: 48000; Hex: 'b00000000f0000000300040003000000010000000000000004000000030000000100000000000000020000000000000004000000030000000100000000000000010001000000000004000000030000000c010000000000000300010000000000040000000400000080bb0000000000000400010000000000040000000400000006000000000000000500010000000000200000000d0000000400000003000000030000000400000005000000060000000c0000000d000000'),
    (Name: 'f32be_7_192000'; Format: PML_AUDIO_F32BE; Channels: 7; Freq: 192000; Hex: 'b80000000f0000000300040003000000010000000000000004000000030000000100000000000000020000000000000004000000030000000100000000000000010001000000000004000000030000001c010000000000000300010000000000040000000400000000ee0200000000000400010000000000040000000400000007000000000000000500010000000000240000000d0000000400000003000000030000000400000005000000060000000b0000000c0000000d00000000000000'),
    (Name: 'f32_8_48000'; Format: PML_AUDIO_F32LE; Channels: 8; Freq: 48000; Hex: 'b80000000f0000000300040003000000010000000000000004000000030000000100000000000000020000000000000004000000030000000100000000000000010001000000000004000000030000001b010000000000000300010000000000040000000400000080bb0000000000000400010000000000040000000400000008000000000000000500010000000000280000000d0000000400000003000000030000000400000005000000060000000c0000000d0000000700000008000000'),
    (Name: 'unknown_2_48000'; Format: 0; Channels: 2; Freq: 48000; Hex: '880000000f00000003000400030000000100000000000000040000000300000001000000000000000200000000000000040000000300000001000000000000000300010000000000040000000400000080bb0000000000000400010000000000040000000400000002000000000000000500010000000000100000000d00000004000000030000000300000004000000'));
  PWParse: array[0..10] of TPWParseCase = (
    (Name: 'range_rate_int_channels'; Hex: '980000000f0000000300040003000000010000000000000004000000030000000100000000000000020000000000000004000000030000000100000000000000010001000000000004000000030000001b0100000000000003000100000000001c000000130000000100000000000000040000000400000080bb00000100000000dc050000000000040001000000000004000000040000000200000000000000'; RateOk: True; RateDef: 48000; RateMin: 1; RateMax: 384000; ChannelsOk: True; Channels: 2),
    (Name: 'plain_rate_range_channels'; Hex: '500000000f00000003000400040000000300010000000000040000000400000044ac00000000000004000100000000001c000000130000000100000000000000040000000400000002000000010000004000000000000000'; RateOk: False; RateDef: -1; RateMin: -1; RateMax: -1; ChannelsOk: False; Channels: -1),
    (Name: 'enum_rate'; Hex: '500000000f000000030004000300000003000100000000001c000000130000000300000000000000040000000400000044ac000044ac000080bb000000000000040001000000000004000000040000000600000000000000'; RateOk: False; RateDef: -1; RateMin: -1; RateMax: -1; ChannelsOk: True; Channels: 6),
    (Name: 'step_rate'; Hex: '380000000f0000000300040003000000030001000000000020000000130000000200000000000000040000000400000080bb0000401f000000770100a00f0000'; RateOk: False; RateDef: -1; RateMin: -1; RateMax: -1; ChannelsOk: False; Channels: -1),
    (Name: 'enum_channels'; Hex: '300000000f000000030004000300000004000100000000001800000013000000030000000000000004000000040000000800000008000000'; RateOk: False; RateDef: -1; RateMin: -1; RateMax: -1; ChannelsOk: False; Channels: -1),
    (Name: 'empty_object'; Hex: '080000000f0000000300040003000000'; RateOk: False; RateDef: -1; RateMin: -1; RateMax: -1; ChannelsOk: False; Channels: -1),
    (Name: 'not_object'; Hex: '040000000400000080bb0000'; RateOk: False; RateDef: -1; RateMin: -1; RateMax: -1; ChannelsOk: False; Channels: -1),
    (Name: 'rate_after_others'; Hex: '880000000f00000003000400030000000100000000000000040000000300000001000000000000000500010000000000100000000d0000000400000003000000030000000400000004000100000000000400000004000000020000000000000003000100000000001c000000130000000100000000000000040000000400000000770100401f000000ee020000000000'; RateOk: True; RateDef: 96000; RateMin: 8000; RateMax: 192000; ChannelsOk: True; Channels: 2),
    (Name: 'range_four_values'; Hex: '380000000f0000000300040003000000030001000000000020000000130000000100000000000000040000000400000080bb0000401f00000077010001000000'; RateOk: True; RateDef: 48000; RateMin: 8000; RateMax: 96000; ChannelsOk: False; Channels: -1),
    (Name: 'range_two_values'; Hex: '300000000f0000000300040003000000030001000000000018000000130000000100000000000000040000000400000080bb0000401f0000'; RateOk: False; RateDef: -1; RateMin: -1; RateMax: -1; ChannelsOk: False; Channels: -1),
    (Name: 'truncated_last_prop'; Hex: '480000000f000000030004000300000003000100000000001c000000130000000100000000000000040000000400000080bb00000100000000dc05000000000004000100000000000400000004000000'; RateOk: True; RateDef: 48000; RateMin: 1; RateMax: 384000; ChannelsOk: False; Channels: -1));
  PWJsonNames: array[0..22] of TPWJsonName = (
    (Input: '{"name":"alsa_output.usb-Burr-Brown_PCM2704-00.analog-stereo"}'; Found: True; Output: 'alsa_output.usb-Burr-Brown_PCM2704-00.analog-stereo'),
    (Input: '{ "name": "alsa_input.pci-0000_0c_00.6.analog-stereo" }'; Found: True; Output: 'alsa_input.pci-0000_0c_00.6.analog-stereo'),
    (Input: '{"name":"esc\"aped\\back\/slash"}'; Found: True; Output: 'esc"aped\back/slash'),
    (Input: '{"name":"tab\tnl\nuni\u00e9\u3042\ud83c\udfb5x"}'; Found: True; Output: 'tab'+#9+'nl'+#10+'uni'+#195#169#227#129#130#240#159#142#181+'x'),
    (Input: '{"name":"bad\uZZZZu"}'; Found: True; Output: 'baduZZZZu'),
    (Input: '{"name":"lone\udc00x"}'; Found: True; Output: 'lonex'),
    (Input: '{ name = bare-word }'; Found: True; Output: 'bare-word'),
    (Input: '{"description":"too long a key"}'; Found: False; Output: ''),
    (Input: '{"nam":"short key"}'; Found: True; Output: 'short key'),
    (Input: '{"name":""}'; Found: True; Output: ''),
    (Input: '{"name":}'; Found: False; Output: ''),
    (Input: '{"name"'; Found: False; Output: ''),
    (Input: '"just a string"'; Found: False; Output: ''),
    (Input: '["name","in array"]'; Found: False; Output: ''),
    (Input: 'not json at all'; Found: False; Output: ''),
    (Input: ''; Found: False; Output: ''),
    (Input: '{"name":{"nested":1}}'; Found: True; Output: '{'),
    (Input: '{"name":"'+#195#169+'t'+#195#169+'"}'; Found: True; Output: #195#169+'t'+#195#169),
    (Input: '{"name":"control'+#1+'char"}'; Found: False; Output: ''),
    (Input: '  # comment'+#10+'{"name":"after comment"}'; Found: True; Output: 'after comment'),
    (Input: '{"name":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'; Found: False; Output: ''),
    (Input: '{"name":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'; Found: True; Output: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
    (Input: '{"name":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}'; Found: False; Output: ''));
  PWJsonServices: array[0..6] of TPWJsonServices = (
    (Input: '["audio","video"]'; HaveServices: True; HaveAudio: True),
    (Input: '["video", "bluetooth.audio"]'; HaveServices: True; HaveAudio: False),
    (Input: '[ video audio ]'; HaveServices: True; HaveAudio: True),
    (Input: '[]'; HaveServices: True; HaveAudio: False),
    (Input: '{"audio":true}'; HaveServices: True; HaveAudio: False),
    (Input: '["audio'; HaveServices: True; HaveAudio: False),
    (Input: '["vid\u0065o","aud\u0069o"]'; HaveServices: True; HaveAudio: True));
  PWJsonTokens: array[0..16] of TPWJsonTokens = (
    (Input: '{"a":{"b":1},"c":2}'; Tokens: '3:226122|1:7b|3:226322|1:32|=0'),
    (Input: '{"a":[1,2,{"x":"y"}],"b":"z"}'; Tokens: '3:226122|1:5b|3:226222|3:227a22|=0'),
    (Input: '["s",bare,{"k":"v"},[1,[2]],3]'; Tokens: '3:227322|4:62617265|1:7b|1:5b|1:33|=0'),
    (Input: '{ key = value, other = "q" }'; Tokens: '3:6b6579|5:76616c7565|5:6f74686572|3:227122|=0'),
    (Input: '{"k":"v" # c'+#10+',"k2":"v2"}'; Tokens: '3:226b22|3:227622|4:226b3222|4:22763222|=0'),
    (Input: '{"a" "b" "c"}'; Tokens: '3:226122|3:226222|3:226322|=-1'),
    (Input: '{"a":1]'; Tokens: '3:226122|1:31|=-1'),
    (Input: '[1,2}'; Tokens: '1:31|1:32|=-1'),
    (Input: '{"a":"bad\q"}'; Tokens: '3:226122|=-1'),
    (Input: '{"a":"open}'; Tokens: '3:226122|=-1'),
    (Input: '{"a":"x'+#1+'"}'; Tokens: '3:226122|=-1'),
    (Input: '{a\b:1}'; Tokens: '=-1'),
    (Input: '[ :1 ]'; Tokens: '=-1'),
    (Input: '{"k":\v}'; Tokens: '3:226b22|=-1'),
    (Input: '{"a":1'; Tokens: '3:226122|=-1'),
    (Input: '[[1],2]'; Tokens: '1:5b|1:32|=0'),
    (Input: '{"k":"'+#195#169#227#129#130+'"}'; Tokens: '3:226b22|7:22c3a9e3818222|=0'));
