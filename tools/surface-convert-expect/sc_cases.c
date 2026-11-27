/* サーフェスの変換（SDL_ConvertSurface / SDL_ConvertSurfaceAndColorspace）を参照版の SDL に通して、場面ごとの結果を書き出す。
   papimela の test_surface_convert が同じ場面を Pascal で行って突き合わせる。
   tools/surface-convert-expect/gen.bb が作って test/surface_convert_expected.inc に書く。
   出力（1 行ずつ）:
     C <場面> <src形式> <src色空間> <dst形式> <求めた色空間（0 = SDL_ConvertSurface。形式の既定へ）> <w> <h>
       <src白点> <srcヘッドルーム> <トーンマップ or -> <src画素> <srcパレット or ->
       <dst画素> <dst色空間> <dst白点> <dstヘッドルーム> <dstトーンマップ or ->
   浮動小数は 32 ビットの並び。求めた色空間が 0 でも SDL_ConvertSurfaceAndColorspace(…, UNKNOWN, …) の場面は 'U' を前に付ける
   （色空間 UNKNOWN は転送元の色空間のまま）。 */
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>

static unsigned lcg = 1;
static unsigned nx(void) { lcg = lcg * 1103515245u + 12345u; return lcg >> 16; }
static uint32_t bits(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }

static uint16_t to_half(float a)
{
  uint32_t ia; uint16_t ir; memcpy(&ia, &a, 4);
  ir = (ia >> 16) & 0x8000;
  if ((ia & 0x7f800000) >= 0x33000000) {
    int shift = (int)((ia >> 23) & 0xff) - 127;
    if (shift > 15) ir |= 0x7c00;
    else {
      ia = (ia & 0x007fffff) | 0x00800000;
      if (shift < -14) { ir |= ia >> (-1 - shift); ia = ia << (32 - (-1 - shift)); }
      else { ir |= ia >> (24 - 11); ia = ia << (32 - (24 - 11)); ir = ir + ((14 + shift) << 10); }
      if ((ia > 0x80000000) || ((ia == 0x80000000) && (ir & 1))) ir++;
    }
  }
  return ir;
}

static void hexn(const unsigned char *p, int n) { for (int i = 0; i < n; i++) printf("%02X", p[i]); }

static void make_input(unsigned char *p, SDL_PixelFormat f, int npix)
{
  int bpp = SDL_BYTESPERPIXEL(f);
  if (SDL_ISPIXELFORMAT_INDEXED(f)) {
    for (int i = 0; i < npix; i++) p[i] = (unsigned char)(nx() % 16);
  } else if (SDL_PIXELTYPE(f) == SDL_PIXELTYPE_ARRAYF16) {
    for (int i = 0; i < npix * (bpp / 2); i++) ((uint16_t *)p)[i] = to_half((float)(nx() % 1500) / 1000.0f);
  } else if (SDL_PIXELTYPE(f) == SDL_PIXELTYPE_ARRAYF32) {
    for (int i = 0; i < npix * (bpp / 4); i++) ((float *)p)[i] = (float)(nx() % 1500) / 1000.0f;
  } else {
    for (int i = 0; i < npix * bpp; i++) p[i] = (unsigned char)nx();
  }
}

typedef struct {
  const char *name;
  SDL_PixelFormat sf; SDL_Colorspace sc;
  SDL_PixelFormat df;
  int mode;               /* 0 = SDL_ConvertSurface、1 = SDL_ConvertSurfaceAndColorspace（dc を渡す） */
  SDL_Colorspace dc;
  int w, h;
  float swp, shr;
  const char *tonemap;
} Scene;

static int case_no = 0;

static void run(const Scene *sc)
{
  int bs = SDL_BYTESPERPIXEL(sc->sf);
  SDL_Surface *src = SDL_CreateSurface(sc->w, sc->h, sc->sf);
  if (!src) { printf("X %s err %s\n", sc->name, SDL_GetError()); return; }
  lcg = 100 + (case_no++) * 7;
  unsigned char *sbuf = calloc(1, (size_t)sc->w * sc->h * bs);
  make_input(sbuf, sc->sf, sc->w * sc->h);
  SDL_Palette *sp = NULL;
  if (SDL_ISPIXELFORMAT_INDEXED(sc->sf)) {
    sp = SDL_CreateSurfacePalette(src);
    SDL_Color c[16];
    for (int i = 0; i < 16; i++) { c[i].r = nx(); c[i].g = nx(); c[i].b = nx(); c[i].a = 255; }
    SDL_SetPaletteColors(sp, c, 0, 16);
  }
  for (int y = 0; y < sc->h; y++) memcpy((unsigned char *)src->pixels + y * src->pitch, sbuf + y * sc->w * bs, (size_t)sc->w * bs);
  SDL_SetSurfaceColorspace(src, sc->sc);
  SDL_PropertiesID p = SDL_GetSurfaceProperties(src);
  if (sc->swp != 0) SDL_SetFloatProperty(p, SDL_PROP_SURFACE_SDR_WHITE_POINT_FLOAT, sc->swp);
  if (sc->shr != 0) SDL_SetFloatProperty(p, SDL_PROP_SURFACE_HDR_HEADROOM_FLOAT, sc->shr);
  if (sc->tonemap) SDL_SetStringProperty(p, SDL_PROP_SURFACE_TONEMAP_OPERATOR_STRING, sc->tonemap);
  SDL_Surface *dst = sc->mode == 0 ? SDL_ConvertSurface(src, sc->df)
                                    : SDL_ConvertSurfaceAndColorspace(src, sc->df, NULL, sc->dc, SDL_GetSurfaceProperties(src));
  if (!dst) { printf("X %s err %s\n", sc->name, SDL_GetError()); return; }
  int bd = SDL_BYTESPERPIXEL(sc->df);
  SDL_PropertiesID q = SDL_GetSurfaceProperties(dst);
  const char *tm = SDL_GetStringProperty(q, SDL_PROP_SURFACE_TONEMAP_OPERATOR_STRING, NULL);
  printf("C %s %08X %08X %08X %c%08X %d %d %08X %08X %s ", sc->name, sc->sf, sc->sc, sc->df, sc->mode ? 'U' : '-',
         sc->dc, sc->w, sc->h, bits(sc->swp), bits(sc->shr), sc->tonemap ? sc->tonemap : "-");
  hexn(sbuf, sc->w * sc->h * bs); printf(" ");
  if (sp) { for (int i = 0; i < 16; i++) printf("%02X%02X%02X%02X", sp->colors[i].r, sp->colors[i].g, sp->colors[i].b, sp->colors[i].a); }
  else printf("-");
  printf(" ");
  for (int y = 0; y < sc->h; y++) hexn((unsigned char *)dst->pixels + y * dst->pitch, sc->w * bd);
  printf(" %08X %08X %08X %s\n", SDL_GetSurfaceColorspace(dst),
         bits(SDL_GetFloatProperty(q, SDL_PROP_SURFACE_SDR_WHITE_POINT_FLOAT, 0.0f)),
         bits(SDL_GetFloatProperty(q, SDL_PROP_SURFACE_HDR_HEADROOM_FLOAT, 0.0f)), tm ? tm : "-");
  SDL_DestroySurface(src); SDL_DestroySurface(dst);
  free(sbuf);
}

#define F_ARGB  SDL_PIXELFORMAT_ARGB8888
#define F_ABGR  SDL_PIXELFORMAT_ABGR8888
#define F_A64F  SDL_PIXELFORMAT_RGBA64_FLOAT
#define F_A128F SDL_PIXELFORMAT_RGBA128_FLOAT
#define F_A64   SDL_PIXELFORMAT_RGBA64
#define F_RGB24 SDL_PIXELFORMAT_RGB24
#define F_A2R10 SDL_PIXELFORMAT_ARGB2101010
#define F_X2R10 SDL_PIXELFORMAT_XBGR2101010
#define F_IDX8  SDL_PIXELFORMAT_INDEX8
#define C_S     SDL_COLORSPACE_SRGB
#define C_L     SDL_COLORSPACE_SRGB_LINEAR
#define C_H     SDL_COLORSPACE_HDR10
#define C_J     SDL_COLORSPACE_JPEG
#define C_B709  SDL_COLORSPACE_BT709_LIMITED

int main(void)
{
  if (!SDL_Init(0)) { printf("INIT-ERR %s\n", SDL_GetError()); return 1; }
  static const Scene scenes[] = {
    /* SDL_ConvertSurface: 求める色空間は形式の既定。形式の組 */
    { "d_argb_to_abgr",     F_ARGB,  C_S, F_ABGR,  0, 0,     5,4, 0,0, NULL },
    { "d_argb_to_rgb24",    F_ARGB,  C_S, F_RGB24, 0, 0,     5,4, 0,0, NULL },
    { "d_argb_to_a2r10",    F_ARGB,  C_S, F_A2R10, 0, 0,     5,4, 0,0, NULL },
    { "d_a2r10_to_argb",    F_A2R10, C_H, F_ARGB,  0, 0,     5,4, 0,0, NULL },
    { "d_x2r10_to_argb",    F_X2R10, C_S, F_ARGB,  0, 0,     5,4, 0,0, NULL },
    { "d_argb_to_a64",      F_ARGB,  C_S, F_A64,   0, 0,     5,4, 0,0, NULL },
    { "d_a64_to_argb",      F_A64,   C_S, F_ARGB,  0, 0,     5,4, 0,0, NULL },
    { "d_argb_to_a64f",     F_ARGB,  C_S, F_A64F,  0, 0,     5,4, 0,0, NULL },
    { "d_a64f_to_argb",     F_A64F,  C_L, F_ARGB,  0, 0,     5,4, 0,0, NULL },
    { "d_argb_to_a128f",    F_ARGB,  C_S, F_A128F, 0, 0,     5,4, 0,0, NULL },
    { "d_a128f_to_argb",    F_A128F, C_L, F_ARGB,  0, 0,     5,4, 0,0, NULL },
    { "d_a128f_to_a64",     F_A128F, C_L, F_A64,   0, 0,     5,4, 0,0, NULL },
    { "d_a64f_to_a128f",    F_A64F,  C_L, F_A128F, 0, 0,     5,4, 0,0, NULL },
    { "d_rgb24_to_a64f",    F_RGB24, C_S, F_A64F,  0, 0,     5,4, 0,0, NULL },
    { "d_a64f_to_rgb24",    F_A64F,  C_L, F_RGB24, 0, 0,     5,4, 0,0, NULL },
    { "d_a2r10_to_a128f",   F_A2R10, C_H, F_A128F, 0, 0,     5,4, 0,0, NULL },
    { "d_a128f_to_a2r10",   F_A128F, C_L, F_A2R10, 0, 0,     5,4, 0,0, NULL },
    /* 同じ形式への変換（色空間が違うと値が変わる） */
    { "d_argb_to_argb",     F_ARGB,  C_S, F_ARGB,  0, 0,     5,4, 0,0, NULL },
    { "d_a64f_to_a64f_s",   F_A64F,  C_S, F_A64F,  0, 0,     5,4, 0,0, NULL },
    /* SDL_ConvertSurfaceAndColorspace: 色空間を指定する */
    { "c_argb_s_to_lin",    F_ARGB,  C_S, F_ARGB,  1, C_L,   5,4, 0,0, NULL },
    { "c_argb_l_to_s",      F_ARGB,  C_L, F_ARGB,  1, C_S,   5,4, 0,0, NULL },
    { "c_a64f_l_to_s",      F_A64F,  C_L, F_A64F,  1, C_S,   5,4, 0,0, NULL },
    { "c_a128f_l_to_h",     F_A128F, C_L, F_A128F, 1, C_H,   5,4, 0,0, NULL },
    { "c_argb_s_to_h_a2r10",F_ARGB,  C_S, F_A2R10, 1, C_H,   5,4, 0,0, NULL },
    { "c_a2r10_h_to_s",     F_A2R10, C_H, F_ARGB,  1, C_S,   5,4, 0,0, NULL },
    { "c_a128f_709_to_jpeg",F_A128F, C_B709, F_ARGB, 1, C_J, 5,4, 0,0, NULL },
    /* 色空間 UNKNOWN は転送元の色空間のまま */
    { "u_argb_unknown",     F_ARGB,  C_L, F_ARGB,  1, 0,     5,4, 0,0, NULL },   /* 既定は sRGB だが、転送元の線形のまま */
    { "u_a128f_unknown",    F_A128F, C_S, F_A128F, 1, 0,     5,4, 0,0, NULL },   /* 既定は線形だが、転送元の sRGB のまま */
    { "u_argb_lin_to_a64f", F_ARGB,  C_L, F_A64F,  1, 0,     5,4, 0,0, NULL },
    { "u_a64f_srgb_to_argb",F_A64F,  C_S, F_ARGB,  1, 0,     5,4, 0,0, NULL },
    /* 白点・ヘッドルーム・トーンマップ（転送元のプロパティを使い、結果へ引き継ぐ） */
    { "p_wp_a2r10_to_argb", F_A2R10, C_H, F_ARGB,  0, 0,     5,4, 100.0f,0, NULL },
    { "p_chrome_a2r10",     F_A2R10, C_H, F_ARGB,  0, 0,     5,4, 0,4.0f, NULL },
    { "p_none_a2r10",       F_A2R10, C_H, F_ARGB,  0, 0,     5,4, 0,4.0f, "none" },
    { "p_linear_a2r10",     F_A2R10, C_H, F_ARGB,  0, 0,     5,4, 0,4.0f, "*=0.5" },
    { "p_inherit_to_a128f", F_A2R10, C_H, F_A128F, 0, 0,     5,4, 0,4.0f, NULL },
    { "p_carry_props_same", F_ARGB,  C_S, F_ABGR,  0, 0,     5,4, 150.0f,2.0f, "chrome" },
    /* パレットの入力（インデックスの変換は従来の経路。結果が SDL と同じことを守る） */
    { "i_idx8_to_argb",     F_IDX8,  C_S, F_ARGB,  0, 0,     5,4, 0,0, NULL },
    { "i_idx8_to_a64f",     F_IDX8,  C_S, F_A64F,  0, 0,     5,4, 0,0, NULL },
  };
  for (unsigned i = 0; i < sizeof(scenes) / sizeof(scenes[0]); i++) run(&scenes[i]);
  return 0;
}
