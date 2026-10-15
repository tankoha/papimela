{ test/texture_lock_expected.inc — tools/texture-lock-expect/gen.bb が作る。手で直さない。
  SDL（参照版）のソフトウェアのレンダラに、SDL_LockTexture などを通した結果。
  1 行 = 1 場面。'<場面> ok <ピッチ> <位置> <ハッシュ>' か '<場面> err <文面>'。 }

const
  LockExpected: array[0..36] of String = (
    'argb_full ok 24 0 3065B9D8',
    'argb_rect ok 24 52 0C58B59F',
    'argb_corner ok 24 116 DD001F01',
    'bgr24_rect ok 20 43 48C65CF5',
    'rgb24_full ok 16 0 48BC3D10',
    'abgr8888_rect ok 24 52 61461887',
    'yuy2_rect ok 12 16 78AAAB94',
    'uyvy_full ok 12 0 F25A66B8',
    'yvyu_rect ok 12 32 3EEBDE3D',
    'static_lock err SDL_LockTexture(): texture must be streaming',
    'static_unlock ok',
    'target_lock err SDL_LockTexture(): texture must be streaming',
    'iyuv_full ok 6 0 CCDF5FC2',
    'iyuv_partial err YV12, IYUV, I444, I4FL, NV12, NV21 textures only support full surface locks',
    'iyuv_fullrect ok 6',
    'yv12_full ok 6 0 14384C47',
    'yv12_partial err YV12, IYUV, I444, I4FL, NV12, NV21 textures only support full surface locks',
    'yv12_fullrect ok 6',
    'nv12_full ok 6 0 9F55C29A',
    'nv12_partial err YV12, IYUV, I444, I4FL, NV12, NV21 textures only support full surface locks',
    'nv12_fullrect ok 6',
    'nv21_full ok 6 0 D948D502',
    'nv21_partial err YV12, IYUV, I444, I4FL, NV12, NV21 textures only support full surface locks',
    'nv21_fullrect ok 6',
    'index8_full ok 8 0 3D2563D3',
    'index8_rect_pos 8 10',
    'index8_rect ok 8 3EF7E187',
    'tosurf_rect 3 2 24 372645892 28',
    'tosurf_rect_hash 09B291D5',
    'tosurf_clip 3 3 0',
    'tosurf_full 6 5 24',
    'tosurf_outside err Parameter ''width'' is invalid',
    'tosurf_static err SDL_LockTexture(): texture must be streaming',
    'tosurf_index8 4 4 4 palette=1',
    'tosurf_iyuv ok 4 4 4',
    'double_lock 1 1',
    'double_unlock ok'
  );
