{ test/alsa_chmap_expected.inc — tools/alsa-parity/genchmap.bb が作る。手で直さない。
  SDL の alsa_chmap_cfg（SDL_alsa_audio.c）を偽の ALSA で動かした結果。
  Status は 0 = 入れた、1 = 次のチャンネル数、負 = 失敗。SetCalled は snd_pcm_set_chmap を呼んだ回数、
  FreeCalled は snd_pcm_free_chmaps を呼んだ回数（SDL は成功した道で解放しない。papimela は解放する）。 }

type
  TChmapCase = record
    Name: String;
    Chans: Integer;
    Queries: String;   // 'type:pos,pos;type:pos,pos'。'-' は問い合わせが nil
    SetResult: Integer;
    Status, SetCalled, FreeCalled: Integer;
    Installed, Swizzle: array of Integer;
  end;

const
  ChmapCases: array[0..37] of TChmapCase = (
    (Name: 'no_queries'; Chans: 2; Queries: '-'; SetResult: 0; Status: 0; SetCalled: 0; FreeCalled: 0; Installed: (); Swizzle: ()),
    (Name: 'stereo_fixed'; Chans: 2; Queries: '1:3,4'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4); Swizzle: ()),
    (Name: 'stereo_paired'; Chans: 2; Queries: '3:3,4'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4); Swizzle: ()),
    (Name: 'stereo_reversed_fixed'; Chans: 2; Queries: '1:4,3'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (4, 3); Swizzle: (1, 0)),
    (Name: 'stereo_reversed_then_ordered'; Chans: 2; Queries: '1:4,3;1:3,4'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4); Swizzle: ()),
    (Name: 'stereo_var'; Chans: 2; Queries: '2:3,4'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4); Swizzle: ()),
    (Name: 'stereo_var_reversed'; Chans: 2; Queries: '2:4,3'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4); Swizzle: ()),
    (Name: 'stereo_wrong_channel_count'; Chans: 2; Queries: '1:3,4,8;1:2'; SetResult: 0; Status: 1; SetCalled: 0; FreeCalled: 0; Installed: (); Swizzle: ()),
    (Name: 'stereo_no_match'; Chans: 2; Queries: '1:3,5'; SetResult: 0; Status: 1; SetCalled: 0; FreeCalled: 0; Installed: (); Swizzle: ()),
    (Name: 'stereo_duplicate'; Chans: 2; Queries: '1:3,3'; SetResult: 0; Status: 1; SetCalled: 0; FreeCalled: 0; Installed: (); Swizzle: ()),
    (Name: 'stereo_na_filler'; Chans: 2; Queries: '1:1,1'; SetResult: 0; Status: 1; SetCalled: 0; FreeCalled: 0; Installed: (); Swizzle: ()),
    (Name: 'stereo_install_fails'; Chans: 2; Queries: '1:3,4'; SetResult: -22; Status: -1; SetCalled: 1; FreeCalled: 0; Installed: (3, 4); Swizzle: ()),
    (Name: 'mono'; Chans: 1; Queries: '1:2'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (2); Swizzle: ()),
    (Name: 'mono_other'; Chans: 1; Queries: '1:3'; SetResult: 0; Status: 1; SetCalled: 0; FreeCalled: 0; Installed: (); Swizzle: ()),
    (Name: 'ch3'; Chans: 3; Queries: '1:3,4,8'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4, 8); Swizzle: ()),
    (Name: 'ch3_swizzle'; Chans: 3; Queries: '1:8,3,4'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (8, 3, 4); Swizzle: (1, 2, 0)),
    (Name: 'ch4'; Chans: 4; Queries: '1:3,4,5,6'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4, 5, 6); Swizzle: ()),
    (Name: 'ch4_swizzle'; Chans: 4; Queries: '1:5,6,3,4'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (5, 6, 3, 4); Swizzle: (2, 3, 0, 1)),
    (Name: 'ch5'; Chans: 5; Queries: '1:3,4,8,5,6'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4, 8, 5, 6); Swizzle: ()),
    (Name: 'ch6_rear'; Chans: 6; Queries: '1:3,4,7,8,5,6'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4, 7, 8, 5, 6); Swizzle: ()),
    (Name: 'ch6_side'; Chans: 6; Queries: '1:3,4,7,8,9,10'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4, 7, 8, 9, 10); Swizzle: ()),
    (Name: 'ch6_rear_swizzle'; Chans: 6; Queries: '1:3,4,8,7,5,6'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4, 8, 7, 5, 6); Swizzle: (0, 1, 3, 2, 4, 5)),
    (Name: 'ch6_side_swizzle'; Chans: 6; Queries: '1:4,3,7,8,10,9'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (4, 3, 7, 8, 10, 9); Swizzle: (1, 0, 2, 3, 5, 4)),
    (Name: 'ch6_both'; Chans: 6; Queries: '1:3,4,7,8,5,9'; SetResult: 0; Status: 1; SetCalled: 0; FreeCalled: 0; Installed: (); Swizzle: ()),
    (Name: 'ch6_none'; Chans: 6; Queries: '1:3,4,7,8,7,7'; SetResult: 0; Status: 1; SetCalled: 0; FreeCalled: 0; Installed: (); Swizzle: ()),
    (Name: 'ch6_missing_fc'; Chans: 6; Queries: '1:3,4,8,5,6,1'; SetResult: 0; Status: 1; SetCalled: 0; FreeCalled: 0; Installed: (); Swizzle: ()),
    (Name: 'ch6_unknown_pair'; Chans: 6; Queries: '1:3,4,7,8,0,0'; SetResult: 0; Status: 1; SetCalled: 0; FreeCalled: 0; Installed: (); Swizzle: ()),
    (Name: 'ch6_unknown_pair_var'; Chans: 6; Queries: '2:3,4,7,8,0,0'; SetResult: 0; Status: 1; SetCalled: 0; FreeCalled: 0; Installed: (); Swizzle: ()),
    (Name: 'ch6_var_side'; Chans: 6; Queries: '2:3,4,7,8,9,10'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4, 7, 8, 9, 10); Swizzle: ()),
    (Name: 'ch6_var_rear'; Chans: 6; Queries: '2:3,4,7,8,5,6'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4, 7, 8, 5, 6); Swizzle: ()),
    (Name: 'ch7'; Chans: 7; Queries: '1:3,4,7,8,11,9,10'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4, 7, 8, 11, 9, 10); Swizzle: ()),
    (Name: 'ch8'; Chans: 8; Queries: '1:3,4,7,8,5,6,9,10'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4, 7, 8, 5, 6, 9, 10); Swizzle: ()),
    (Name: 'ch8_swizzle'; Chans: 8; Queries: '1:4,3,7,8,6,5,10,9'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (4, 3, 7, 8, 6, 5, 10, 9); Swizzle: (1, 0, 2, 3, 5, 4, 7, 6)),
    (Name: 'ch8_var'; Chans: 8; Queries: '2:3,4,7,8,5,6,9,10'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4, 7, 8, 5, 6, 9, 10); Swizzle: ()),
    (Name: 'ordered_wins_over_unordered'; Chans: 4; Queries: '1:4,3,5,6;1:3,4,5,6'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4, 5, 6); Swizzle: ()),
    (Name: 'var_after_fixed_miss'; Chans: 2; Queries: '1:3,5;2:3,4'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (3, 4); Swizzle: ()),
    (Name: 'unordered_after_var_miss'; Chans: 2; Queries: '2:3,5;1:4,3'; SetResult: 0; Status: 0; SetCalled: 1; FreeCalled: 0; Installed: (4, 3); Swizzle: (1, 0)),
    (Name: 'install_fails_6'; Chans: 6; Queries: '1:3,4,7,8,5,6'; SetResult: -5; Status: -1; SetCalled: 1; FreeCalled: 0; Installed: (3, 4, 7, 8, 5, 6); Swizzle: ())
  );
