{ test/alsa_abi_expected.inc — tools/genalsa.bb が libasound のヘッダで C を動かして作る。
  手で直さない（1.2.15.3 のヘッダ）。ALS_* は構造体と型の大きさ、ALO_* は欄の位置。 }

const
  ALS_snd_pcm_chmap_t = 4;
  ALO_snd_pcm_chmap_t_channels = 0;
  ALO_snd_pcm_chmap_t_pos = 4;
  ALS_snd_pcm_chmap_query_t = 8;
  ALO_snd_pcm_chmap_query_t_type = 0;
  ALO_snd_pcm_chmap_query_t_map = 4;
  ALS_snd_pcm_uframes_t = 8;
  ALS_snd_pcm_sframes_t = 8;
  ALS_snd_pcm_format_t = 4;
  ALS_snd_pcm_access_t = 4;
  ALS_snd_pcm_stream_t = 4;
  ALS_snd_pcm_state_t = 4;
  ALS_enum_snd_pcm_chmap_type = 4;
  ALS_enum_snd_pcm_chmap_position = 4;
