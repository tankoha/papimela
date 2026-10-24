/* I444 と P010 を、参照版の SDL に通して、場面ごとの結果を書き出す。papimela の test_yuv_hd が同じ場面を
   Pascal で行って突き合わせる。tools/yuv-hd-expect/gen.bb が作って test/yuv_hd_expected.inc に書く。
   出力（1 行ずつ）:
     Z <形式> <w> <h> <大きさ> <ピッチ>                     SDL_CalculateYUVSize
     C <形式> <色空間> <w> <h> <ハッシュ>                    SDL_ConvertPixelsAndColorspace（YUV から ARGB8888 / XBGR2101010）
     T <場面> <色空間> <w> <h> <ハッシュ>                    ソフトウェアのレンダラに描かせた絵（I444 のテクスチャ）
     E <場面> <文面>                                         エラー
   8 ビットの値は範囲の内側に収める（範囲の外は SDL のスカラー版が回り込み、papimela は飽和させる。D-62）。
   P010 の出力は SDL の clamp10 が飽和させるので、値は全域から取る。 */
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

extern bool SDL_CalculateYUVSize(SDL_PixelFormat format, int w, int h, size_t *size, size_t *pitch);

static unsigned lcg = 1;
static unsigned nx(void) { lcg = lcg * 1103515245u + 12345u; return lcg >> 16; }
static unsigned fnv(const unsigned char *p, size_t n, unsigned h)
{
  for (size_t i = 0; i < n; i++) { h ^= p[i]; h *= 16777619u; }
  return h;
}

static const struct { const char *n; SDL_Colorspace c; } spaces[] = {
  { "bt601l", SDL_COLORSPACE_BT601_LIMITED }, { "jpeg", SDL_COLORSPACE_JPEG },
  { "bt709l", SDL_COLORSPACE_BT709_LIMITED }, { "bt709f", SDL_COLORSPACE_BT709_FULL },
  { "bt2020f", SDL_COLORSPACE_BT2020_FULL } };
static const int sizes[][2] = { { 7, 5 }, { 16, 4 }, { 40, 6 } };

/* 8 ビットの YUV の値。Y は 70..149、U・V は 96..159（どの行列でも 0..255 に収まる） */
static unsigned char y8(void) { return (unsigned char)(70 + (nx() % 80)); }
static unsigned char c8(void) { return (unsigned char)(96 + (nx() & 63)); }

static void fill_i444(unsigned char *p, int w, int h, int seed)
{
  lcg = seed;
  for (int i = 0; i < w * h; i++) p[i] = y8();
  for (int i = 0; i < 2 * w * h; i++) p[w * h + i] = c8();
}

static SDL_Surface *target;
static SDL_Renderer *rr;

static unsigned render_hash(SDL_Texture *t, int w, int h)
{
  SDL_SetRenderDrawColor(rr, 10, 20, 30, 255);
  SDL_RenderClear(rr);
  SDL_FRect dst = { 0, 0, (float)w, (float)h };
  SDL_RenderTexture(rr, t, NULL, &dst);
  SDL_RenderPresent(rr);
  unsigned hsh = 2166136261u;
  for (int y = 0; y < h; y++) hsh = fnv((unsigned char *)target->pixels + y * target->pitch, w * 4, hsh);
  return hsh;
}

static SDL_Texture *make_tex(SDL_PixelFormat f, SDL_Colorspace cs, int w, int h)
{
  SDL_PropertiesID p = SDL_CreateProperties();
  SDL_SetNumberProperty(p, SDL_PROP_TEXTURE_CREATE_FORMAT_NUMBER, f);
  SDL_SetNumberProperty(p, SDL_PROP_TEXTURE_CREATE_ACCESS_NUMBER, SDL_TEXTUREACCESS_STREAMING);
  SDL_SetNumberProperty(p, SDL_PROP_TEXTURE_CREATE_WIDTH_NUMBER, w);
  SDL_SetNumberProperty(p, SDL_PROP_TEXTURE_CREATE_HEIGHT_NUMBER, h);
  SDL_SetNumberProperty(p, SDL_PROP_TEXTURE_CREATE_COLORSPACE_NUMBER, cs);
  SDL_Texture *t = SDL_CreateTextureWithProperties(rr, p);
  SDL_DestroyProperties(p);
  if (t) SDL_SetTextureBlendMode(t, SDL_BLENDMODE_NONE);
  return t;
}

int main(void)
{
  SDL_SetHint("SDL_VIDEO_DRIVER", "dummy");
  if (!SDL_Init(SDL_INIT_VIDEO)) { printf("INIT-ERR %s\n", SDL_GetError()); return 1; }
  target = SDL_CreateSurface(48, 8, SDL_PIXELFORMAT_ARGB8888);
  rr = SDL_CreateSoftwareRenderer(target);
  if (!rr) { printf("INIT-ERR %s\n", SDL_GetError()); return 1; }

  /* 大きさ */
  static const struct { const char *n; SDL_PixelFormat f; } fm[] = { { "I444", SDL_PIXELFORMAT_I444 }, { "P010", SDL_PIXELFORMAT_P010 } };
  static const int zs[][2] = { { 7, 5 }, { 8, 6 }, { 1, 1 }, { 40, 6 } };
  for (int f = 0; f < 2; f++) for (int i = 0; i < 4; i++) {
    size_t sz = 0, pi = 0;
    if (SDL_CalculateYUVSize(fm[f].f, zs[i][0], zs[i][1], &sz, &pi))
      printf("Z %s %d %d %zu %zu\n", fm[f].n, zs[i][0], zs[i][1], sz, pi);
    else printf("Z %s %d %d err\n", fm[f].n, zs[i][0], zs[i][1]);
  }

  /* 変換 */
  for (int s = 0; s < 5; s++) for (int z = 0; z < 3; z++) {
    int w = sizes[z][0], h = sizes[z][1];
    /* I444 -> ARGB8888 */
    size_t sz, pi;
    SDL_CalculateYUVSize(SDL_PIXELFORMAT_I444, w, h, &sz, &pi);
    unsigned char *src = calloc(1, sz), *dst = calloc(1, (size_t)w * h * 4);
    fill_i444(src, w, h, 5 + s * 3 + z);
    if (SDL_ConvertPixelsAndColorspace(w, h, SDL_PIXELFORMAT_I444, spaces[s].c, 0, src, (int)pi,
        SDL_PIXELFORMAT_ARGB8888, SDL_COLORSPACE_SRGB, 0, dst, w * 4))
      printf("C I444 %s %d %d %08X\n", spaces[s].n, w, h, fnv(dst, (size_t)w * h * 4, 2166136261u));
    else printf("C I444 %s %d %d err %s\n", spaces[s].n, w, h, SDL_GetError());
    free(src); free(dst);

    /* P010 -> XBGR2101010。値は全域（下位 6 ビットも使う） */
    SDL_CalculateYUVSize(SDL_PIXELFORMAT_P010, w, h, &sz, &pi);
    src = calloc(1, sz); dst = calloc(1, (size_t)w * h * 4);
    lcg = 11 + s * 7 + z;
    for (size_t i = 0; i < sz / 2; i++) ((unsigned short *)src)[i] = (unsigned short)(nx() & 0xFFFF);
    if (SDL_ConvertPixelsAndColorspace(w, h, SDL_PIXELFORMAT_P010, spaces[s].c, 0, src, (int)pi,
        SDL_PIXELFORMAT_XBGR2101010, spaces[s].c, 0, dst, w * 4))
      printf("C P010 %s %d %d %08X\n", spaces[s].n, w, h, fnv(dst, (size_t)w * h * 4, 2166136261u));
    else printf("C P010 %s %d %d err %s\n", spaces[s].n, w, h, SDL_GetError());
    free(src); free(dst);
  }

  /* I444 のテクスチャ: 詰めた画素での更新（UpdateTexture）、平面ごと（UpdateYUVTexture）、Lock */
  for (int s = 0; s < 5; s++) for (int z = 0; z < 3; z++) {
    int w = sizes[z][0], h = sizes[z][1];
    size_t sz, pi;
    SDL_CalculateYUVSize(SDL_PIXELFORMAT_I444, w, h, &sz, &pi);
    unsigned char *src = calloc(1, sz);
    fill_i444(src, w, h, 40 + s + z);
    SDL_Texture *t = make_tex(SDL_PIXELFORMAT_I444, spaces[s].c, w, h);
    if (!t) { printf("E create_i444 %s\n", SDL_GetError()); free(src); continue; }
    if (SDL_UpdateTexture(t, NULL, src, (int)pi)) printf("T packed %s %d %d %08X\n", spaces[s].n, w, h, render_hash(t, w, h));
    else printf("T packed %s %d %d err %s\n", spaces[s].n, w, h, SDL_GetError());
    SDL_DestroyTexture(t);

    t = make_tex(SDL_PIXELFORMAT_I444, spaces[s].c, w, h);
    if (SDL_UpdateYUVTexture(t, NULL, src, w, src + w * h, w, src + 2 * w * h, w))
      printf("T planar %s %d %d %08X\n", spaces[s].n, w, h, render_hash(t, w, h));
    else printf("T planar %s %d %d err %s\n", spaces[s].n, w, h, SDL_GetError());
    SDL_DestroyTexture(t);

    t = make_tex(SDL_PIXELFORMAT_I444, spaces[s].c, w, h);
    void *px; int pitch;
    if (SDL_LockTexture(t, NULL, &px, &pitch)) {
      memcpy(px, src, sz); SDL_UnlockTexture(t);
      printf("T lock %s %d %d %d %08X\n", spaces[s].n, w, h, pitch, render_hash(t, w, h));
    } else printf("T lock %s %d %d err %s\n", spaces[s].n, w, h, SDL_GetError());
    SDL_DestroyTexture(t);
    free(src);
  }

  /* 部分の更新（UpdateYUVTexture の矩形） */
  {
    int w = 16, h = 4; size_t sz, pi;
    SDL_CalculateYUVSize(SDL_PIXELFORMAT_I444, w, h, &sz, &pi);
    unsigned char *a = calloc(1, sz), *b = calloc(1, sz);
    /* 平面の区切りが矩形の位置とずれるので、全部の値を 96..159 にする */
    lcg = 71; for (size_t i = 0; i < sz; i++) a[i] = c8();
    lcg = 72; for (size_t i = 0; i < sz; i++) b[i] = c8();
    SDL_Texture *t = make_tex(SDL_PIXELFORMAT_I444, SDL_COLORSPACE_BT709_LIMITED, w, h);
    SDL_UpdateTexture(t, NULL, a, w);
    SDL_Rect r = { 3, 1, 9, 2 };
    /* 平面 b の (3,1) からの 9x2。平面の先頭を矩形の位置に合わせて渡す */
    if (SDL_UpdateYUVTexture(t, &r, b + 1 * w + 3, w, b + w * h + 1 * w + 3, w, b + 2 * w * h + 1 * w + 3, w))
      printf("T planar_rect bt709l %d %d %08X\n", w, h, render_hash(t, w, h));
    else printf("T planar_rect bt709l %d %d err %s\n", w, h, SDL_GetError());
    SDL_DestroyTexture(t);
    t = make_tex(SDL_PIXELFORMAT_I444, SDL_COLORSPACE_BT709_LIMITED, w, h);
    SDL_UpdateTexture(t, NULL, a, w);
    if (SDL_UpdateTexture(t, &r, b + 1 * w + 3, w)) printf("T packed_rect bt709l %d %d %08X\n", w, h, render_hash(t, w, h));
    else printf("T packed_rect bt709l %d %d err %s\n", w, h, SDL_GetError());
    SDL_DestroyTexture(t);
    free(a); free(b);
  }

  /* 行の幅に余りがある詰めた画素（全体の更新。行ごとに写す道） */
  {
    int w = 16, h = 4, pitch = 21;
    unsigned char *a = calloc(1, (size_t)pitch * h * 3);
    lcg = 91;
    for (size_t i = 0; i < (size_t)pitch * h * 3; i++) a[i] = c8();
    SDL_Texture *t = make_tex(SDL_PIXELFORMAT_I444, SDL_COLORSPACE_BT709_LIMITED, w, h);
    if (SDL_UpdateTexture(t, NULL, a, pitch)) printf("T packed_pitch bt709l %d %d %08X\n", w, h, render_hash(t, w, h));
    else printf("T packed_pitch bt709l %d %d err %s\n", w, h, SDL_GetError());
    SDL_DestroyTexture(t);
    t = make_tex(SDL_PIXELFORMAT_I444, SDL_COLORSPACE_BT709_LIMITED, w, h);
    if (SDL_UpdateYUVTexture(t, NULL, a, pitch, a + pitch * h, pitch, a + 2 * pitch * h, pitch))
      printf("T planar_pitch bt709l %d %d %08X\n", w, h, render_hash(t, w, h));
    else printf("T planar_pitch bt709l %d %d err %s\n", w, h, SDL_GetError());
    SDL_DestroyTexture(t);
    free(a);
  }

  /* 断るもの */
  { SDL_Texture *t = make_tex(SDL_PIXELFORMAT_P010, SDL_COLORSPACE_BT709_LIMITED, 8, 6);
    if (t) printf("E create_p010 ok\n"); else printf("E create_p010 %s\n", SDL_GetError()); if (t) SDL_DestroyTexture(t); }
  { SDL_Texture *t = make_tex(SDL_PIXELFORMAT_I444, SDL_COLORSPACE_BT709_LIMITED, 8, 6);
    unsigned char buf[200] = { 0 };
    if (SDL_UpdateNVTexture(t, NULL, buf, 8, buf, 8)) printf("E nv_on_i444 ok\n"); else printf("E nv_on_i444 %s\n", SDL_GetError());
    SDL_Rect pr = { 0, 0, 4, 4 }; void *px; int pitch;
    if (SDL_LockTexture(t, &pr, &px, &pitch)) { printf("E lock_partial ok\n"); SDL_UnlockTexture(t); } else printf("E lock_partial %s\n", SDL_GetError());
    SDL_DestroyTexture(t); }
  { SDL_Texture *t = make_tex(SDL_PIXELFORMAT_NV12, SDL_COLORSPACE_BT709_LIMITED, 8, 6);
    unsigned char buf[200] = { 0 };
    if (SDL_UpdateYUVTexture(t, NULL, buf, 8, buf, 4, buf, 4)) printf("E yuv_on_nv12 ok\n"); else printf("E yuv_on_nv12 %s\n", SDL_GetError());
    SDL_DestroyTexture(t); }
  /* P010 を表面で変換するときの断り: 形式の違う出力 */
  { unsigned char src[400] = { 0 }, dst[400];
    if (SDL_ConvertPixelsAndColorspace(4, 4, SDL_PIXELFORMAT_P010, SDL_COLORSPACE_BT709_LIMITED, 0, src, 8,
        SDL_PIXELFORMAT_XBGR2101010, SDL_COLORSPACE_BT709_LIMITED, 0, dst, 16)) printf("E p010_to_xbgr ok\n");
    else printf("E p010_to_xbgr %s\n", SDL_GetError()); }
  return 0;
}
