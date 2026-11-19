/* 色空間つきの転送（SDL_Blit_Slow_Float の拡大縮小・ブレンド・変調・カラーキー・インデックスの出力）を
   参照版の SDL に通して、場面ごとの結果を書き出す。
   papimela の test_colorspace_blit が同じ場面を Pascal で行って突き合わせる。
   tools/colorspace-blit-expect/gen.bb が作って test/colorspace_blit_expected.inc に書く。
   出力（1 行ずつ）:
     B <場面> <src形式> <src色空間> <dst形式> <dst色空間> <sw> <sh> <dw> <dh>
       <src矩形 x y w h> <dst矩形 x y w h> <ブレンド> <r g b a の変調> <カラーキー or -> <白点> <ヘッドルーム> <dst白点> <dst ヘッドルーム>
       <トーンマップ or -> <src の画素> <src のパレット or -> <dst の元の画素> <dst のパレット or -> <dst の結果> <dst の結果のヘッドルーム>
   画素は 16 進、浮動小数は 32 ビットの並び（0 = 指定なし）。dst の結果のヘッドルームは転送の後に dst が持っていた値（SDL は 0 のとき
   src のヘッドルームを書き込む）。 */
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

/* 入力を作る。整数の形式は乱数のバイト、浮動小数の形式は 0..1.5 の値、インデックスは 0..15 */
static void make_input(unsigned char *p, SDL_PixelFormat f, int npix)
{
  int bpp = SDL_BYTESPERPIXEL(f);
  if (SDL_ISPIXELFORMAT_INDEXED(f)) {
    for (int i = 0; i < npix; i++) p[i] = (unsigned char)(nx() % 16);
  } else if (SDL_PIXELTYPE(f) == SDL_PIXELTYPE_ARRAYF16) {
    int comps = bpp / 2;
    for (int i = 0; i < npix * comps; i++) ((uint16_t *)p)[i] = to_half((float)(nx() % 1500) / 1000.0f);
  } else if (SDL_PIXELTYPE(f) == SDL_PIXELTYPE_ARRAYF32) {
    int comps = bpp / 4;
    for (int i = 0; i < npix * comps; i++) ((float *)p)[i] = (float)(nx() % 1500) / 1000.0f;
  } else {
    for (int i = 0; i < npix * bpp; i++) p[i] = (unsigned char)nx();
  }
}

static SDL_Palette *make_palette(SDL_Surface *s, int seed)
{
  SDL_Palette *pal = SDL_CreateSurfacePalette(s);
  SDL_Color c[16];
  lcg = 5000 + seed;
  for (int i = 0; i < 16; i++) { c[i].r = nx(); c[i].g = nx(); c[i].b = nx(); c[i].a = 255; }
  SDL_SetPaletteColors(pal, c, 0, 16);
  return pal;
}

static void print_pal(const SDL_Palette *p)
{
  if (!p) { printf("-"); return; }
  for (int i = 0; i < 16; i++) printf("%02X%02X%02X%02X", p->colors[i].r, p->colors[i].g, p->colors[i].b, p->colors[i].a);
}

typedef struct {
  const char *name;
  SDL_PixelFormat sf, df; SDL_Colorspace sc, dc;
  int sw, sh, dw, dh;            /* サーフェスの大きさ */
  SDL_Rect sr, dr;               /* 矩形（w = 0 なら全体） */
  SDL_BlendMode blend;
  int r, g, b, a;                /* 変調（255 = 指定なし） */
  int key;                       /* カラーキー（-1 = 無し） */
  float swp, shr, dwp, dhr;      /* 白点・ヘッドルーム（0 = 指定なし） */
  const char *tonemap;
} Scene;

static int case_no = 0;

static void run(const Scene *sc)
{
  int bs = SDL_BYTESPERPIXEL(sc->sf), bd = SDL_BYTESPERPIXEL(sc->df);
  SDL_Surface *src = SDL_CreateSurface(sc->sw, sc->sh, sc->sf);
  SDL_Surface *dst = SDL_CreateSurface(sc->dw, sc->dh, sc->df);
  if (!src || !dst) { printf("X %s err %s\n", sc->name, SDL_GetError()); return; }
  lcg = 100 + (case_no++) * 7;
  unsigned char *sbuf = calloc(1, (size_t)sc->sw * sc->sh * bs);
  unsigned char *dbuf = calloc(1, (size_t)sc->dw * sc->dh * bd);
  make_input(sbuf, sc->sf, sc->sw * sc->sh);
  make_input(dbuf, sc->df, sc->dw * sc->dh);
  SDL_Palette *sp = NULL, *dp = NULL;
  if (SDL_ISPIXELFORMAT_INDEXED(sc->sf)) sp = make_palette(src, case_no);
  if (SDL_ISPIXELFORMAT_INDEXED(sc->df)) dp = make_palette(dst, case_no + 100);
  for (int y = 0; y < sc->sh; y++) memcpy((unsigned char *)src->pixels + y * src->pitch, sbuf + y * sc->sw * bs, (size_t)sc->sw * bs);
  for (int y = 0; y < sc->dh; y++) memcpy((unsigned char *)dst->pixels + y * dst->pitch, dbuf + y * sc->dw * bd, (size_t)sc->dw * bd);
  SDL_SetSurfaceColorspace(src, sc->sc);
  SDL_SetSurfaceColorspace(dst, sc->dc);
  SDL_SetSurfaceBlendMode(src, sc->blend);
  SDL_SetSurfaceColorMod(src, sc->r, sc->g, sc->b);
  SDL_SetSurfaceAlphaMod(src, sc->a);
  if (sc->key >= 0) SDL_SetSurfaceColorKey(src, true, sc->key);
  SDL_PropertiesID p = SDL_GetSurfaceProperties(src), q = SDL_GetSurfaceProperties(dst);
  if (sc->swp != 0) SDL_SetFloatProperty(p, SDL_PROP_SURFACE_SDR_WHITE_POINT_FLOAT, sc->swp);
  if (sc->shr != 0) SDL_SetFloatProperty(p, SDL_PROP_SURFACE_HDR_HEADROOM_FLOAT, sc->shr);
  if (sc->tonemap) SDL_SetStringProperty(p, SDL_PROP_SURFACE_TONEMAP_OPERATOR_STRING, sc->tonemap);
  if (sc->dwp != 0) SDL_SetFloatProperty(q, SDL_PROP_SURFACE_SDR_WHITE_POINT_FLOAT, sc->dwp);
  if (sc->dhr != 0) SDL_SetFloatProperty(q, SDL_PROP_SURFACE_HDR_HEADROOM_FLOAT, sc->dhr);
  SDL_Rect sr = sc->sr, dr = sc->dr;
  if (sr.w == 0) { sr.x = 0; sr.y = 0; sr.w = sc->sw; sr.h = sc->sh; }
  if (dr.w == 0) { dr.x = 0; dr.y = 0; dr.w = sc->dw; dr.h = sc->dh; }
  bool ok = SDL_BlitSurfaceScaled(src, &sr, dst, &dr, SDL_SCALEMODE_NEAREST);
  if (!ok) { printf("X %s err %s\n", sc->name, SDL_GetError()); }
  else {
    printf("B %s %08X %08X %08X %08X %d %d %d %d %d %d %d %d %d %d %d %d %u %d %d %d %d %d %08X %08X %08X %08X %s ",
           sc->name, sc->sf, sc->sc, sc->df, sc->dc, sc->sw, sc->sh, sc->dw, sc->dh,
           sr.x, sr.y, sr.w, sr.h, dr.x, dr.y, dr.w, dr.h, (unsigned)sc->blend, sc->r, sc->g, sc->b, sc->a, sc->key,
           bits(sc->swp), bits(sc->shr), bits(sc->dwp), bits(sc->dhr), sc->tonemap ? sc->tonemap : "-");
    hexn(sbuf, sc->sw * sc->sh * bs); printf(" "); print_pal(sp); printf(" ");
    hexn(dbuf, sc->dw * sc->dh * bd); printf(" "); print_pal(dp); printf(" ");
    for (int y = 0; y < sc->dh; y++) hexn((unsigned char *)dst->pixels + y * dst->pitch, sc->dw * bd);
    printf(" %08X\n", bits(SDL_GetFloatProperty(q, SDL_PROP_SURFACE_HDR_HEADROOM_FLOAT, 0.0f)));
  }
  SDL_DestroySurface(src); SDL_DestroySurface(dst);
  free(sbuf); free(dbuf);
}

#define NB SDL_BLENDMODE_NONE
#define BL SDL_BLENDMODE_BLEND
#define AD SDL_BLENDMODE_ADD
#define MD SDL_BLENDMODE_MOD
#define ML SDL_BLENDMODE_MUL
#define F_ARGB  SDL_PIXELFORMAT_ARGB8888
#define F_A64F  SDL_PIXELFORMAT_RGBA64_FLOAT
#define F_A128F SDL_PIXELFORMAT_RGBA128_FLOAT
#define F_A64   SDL_PIXELFORMAT_RGBA64
#define F_RGB24 SDL_PIXELFORMAT_RGB24
#define F_A2R10 SDL_PIXELFORMAT_ARGB2101010
#define F_IDX8  SDL_PIXELFORMAT_INDEX8
#define C_S     SDL_COLORSPACE_SRGB
#define C_L     SDL_COLORSPACE_SRGB_LINEAR
#define C_H     SDL_COLORSPACE_HDR10

int main(void)
{
  if (!SDL_Init(0)) { printf("INIT-ERR %s\n", SDL_GetError()); return 1; }
  static const SDL_Rect NR = { 0, 0, 0, 0 };
  /* name, sf, df, sc, dc, sw sh dw dh, sr, dr, blend, r g b a, key, swp shr dwp dhr, tonemap */
  static const Scene scenes[] = {
    /* 等倍。形式と色空間の組（変換だけ。ブレンドなし） */
    { "p_argb_srgb_to_a64f_lin",   F_ARGB,  F_A64F,  C_S, C_L, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "p_a64f_lin_to_argb_srgb",   F_A64F,  F_ARGB,  C_L, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "p_a128f_lin_to_a64_srgb",   F_A128F, F_A64,   C_L, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "p_argb_srgb_to_a128f_lin",  F_ARGB,  F_A128F, C_S, C_L, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "p_argb_srgb_to_a2r10_h10",  F_ARGB,  F_A2R10, C_S, C_H, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "p_a2r10_h10_to_argb_srgb",  F_A2R10, F_ARGB,  C_H, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "p_rgb24_srgb_to_a64f_lin",  F_RGB24, F_A64F,  C_S, C_L, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "p_a64f_lin_to_rgb24_srgb",  F_A64F,  F_RGB24, C_L, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "p_a64_srgb_to_a128f_lin",   F_A64,   F_A128F, C_S, C_L, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    /* 4 バイトの形式同士でも、色空間が違えば浮動小数の経路 */
    { "p_argb_srgb_to_argb_lin",   F_ARGB,  F_ARGB,  C_S, C_L, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "p_argb_lin_to_argb_srgb_bl",F_ARGB,  F_ARGB,  C_L, C_S, 5,4, 5,4, NR, NR, BL, 255,255,255,255, -1, 0,0,0,0, NULL },
    /* 同じ色空間でも、5 バイト以上の形式は浮動小数の経路 */
    { "p_a64f_lin_to_a128f_lin",   F_A64F,  F_A128F, C_L, C_L, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "p_a64_srgb_to_argb_srgb",   F_A64,   F_ARGB,  C_S, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "p_argb_srgb_to_a64_srgb",   F_ARGB,  F_A64,   C_S, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    /* インデックス（パレット）から読む / へ書く */
    { "p_idx8_srgb_to_a64f_lin",   F_IDX8,  F_A64F,  C_S, C_L, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "p_a64f_lin_to_idx8",        F_A64F,  F_IDX8,  C_L, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "p_a128f_lin_to_idx8",       F_A128F, F_IDX8,  C_L, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "p_a64_srgb_to_idx8",        F_A64,   F_IDX8,  C_S, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    /* ブレンド 5 通り x 2 つの組 */
    { "b_none_a64f_to_argb",       F_A64F,  F_ARGB,  C_L, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "b_blend_a64f_to_argb",      F_A64F,  F_ARGB,  C_L, C_S, 5,4, 5,4, NR, NR, BL, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "b_add_a64f_to_argb",        F_A64F,  F_ARGB,  C_L, C_S, 5,4, 5,4, NR, NR, AD, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "b_mod_a64f_to_argb",        F_A64F,  F_ARGB,  C_L, C_S, 5,4, 5,4, NR, NR, MD, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "b_mul_a64f_to_argb",        F_A64F,  F_ARGB,  C_L, C_S, 5,4, 5,4, NR, NR, ML, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "b_blend_argb_to_a128f",     F_ARGB,  F_A128F, C_S, C_L, 5,4, 5,4, NR, NR, BL, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "b_add_argb_to_a128f",       F_ARGB,  F_A128F, C_S, C_L, 5,4, 5,4, NR, NR, AD, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "b_mod_argb_to_a128f",       F_ARGB,  F_A128F, C_S, C_L, 5,4, 5,4, NR, NR, MD, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "b_mul_argb_to_a128f",       F_ARGB,  F_A128F, C_S, C_L, 5,4, 5,4, NR, NR, ML, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "b_blend_a128f_to_a64",      F_A128F, F_A64,   C_L, C_S, 5,4, 5,4, NR, NR, BL, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "b_blend_idx8_to_a64f",      F_IDX8,  F_A64F,  C_S, C_L, 5,4, 5,4, NR, NR, BL, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "b_blend_a64f_to_idx8",      F_A64F,  F_IDX8,  C_L, C_S, 5,4, 5,4, NR, NR, BL, 255,255,255,255, -1, 0,0,0,0, NULL },
    /* 変調 */
    { "m_color_a64f_to_argb",      F_A64F,  F_ARGB,  C_L, C_S, 5,4, 5,4, NR, NR, NB, 200,128,64,255, -1, 0,0,0,0, NULL },
    { "m_alpha_a64f_to_argb",      F_A64F,  F_ARGB,  C_L, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,100, -1, 0,0,0,0, NULL },
    { "m_all_blend_argb_a128f",    F_ARGB,  F_A128F, C_S, C_L, 5,4, 5,4, NR, NR, BL, 200,128,64,100, -1, 0,0,0,0, NULL },
    { "m_all_add_argb_a128f",      F_ARGB,  F_A128F, C_S, C_L, 5,4, 5,4, NR, NR, AD, 200,128,64,100, -1, 0,0,0,0, NULL },
    { "m_all_mul_a64f_argb",       F_A64F,  F_ARGB,  C_L, C_S, 5,4, 5,4, NR, NR, ML, 200,128,64,100, -1, 0,0,0,0, NULL },
    /* カラーキー（浮動小数の経路は何もしない） */
    { "k_ignored_argb_to_a64f",    F_ARGB,  F_A64F,  C_S, C_L, 5,4, 5,4, NR, NR, NB, 255,255,255,255, 0x123456, 0,0,0,0, NULL },
    /* 拡大・縮小（最近傍。中心の標本点） */
    { "s_up_a64f_to_argb",         F_A64F,  F_ARGB,  C_L, C_S, 5,4, 9,7, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "s_up2_argb_to_a128f",       F_ARGB,  F_A128F, C_S, C_L, 4,3, 8,6, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "s_down_a64f_to_argb",       F_A64F,  F_ARGB,  C_L, C_S, 9,7, 4,3, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "s_down_blend_argb_a128f",   F_ARGB,  F_A128F, C_S, C_L, 9,7, 5,4, NR, NR, BL, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "s_up_idx8_to_a64f",         F_IDX8,  F_A64F,  C_S, C_L, 4,3, 7,5, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "s_up_a64f_to_idx8",         F_A64F,  F_IDX8,  C_L, C_S, 4,3, 7,5, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "s_aniso_a64f_to_argb",      F_A64F,  F_ARGB,  C_L, C_S, 6,2, 3,5, NR, NR, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    /* 矩形の指定（切り出して、途中へ置く） */
    { "r_sub_a64f_to_argb",        F_A64F,  F_ARGB,  C_L, C_S, 8,6, 9,7, {2,1,4,3}, {3,2,0,0}, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "r_subscale_argb_a128f",     F_ARGB,  F_A128F, C_S, C_L, 8,6, 9,7, {1,1,3,2}, {2,3,5,3}, BL, 255,255,255,255, -1, 0,0,0,0, NULL },
    { "r_clip_a64f_to_argb",       F_A64F,  F_ARGB,  C_L, C_S, 5,4, 6,5, NR, {4,3,5,4}, NB, 255,255,255,255, -1, 0,0,0,0, NULL },
    /* 白点・ヘッドルーム・トーンマップ */
    { "h_chrome_a2r10_to_argb",    F_A2R10, F_ARGB,  C_H, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,4.0f,0,0, NULL },
    { "h_none_a2r10_to_argb",      F_A2R10, F_ARGB,  C_H, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,4.0f,0,0, "none" },
    { "h_linear_a2r10_to_argb",    F_A2R10, F_ARGB,  C_H, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,4.0f,0,0, "*=0.5" },
    { "h_inherit_a2r10_to_a128f",  F_A2R10, F_A128F, C_H, C_L, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,4.0f,0,0, NULL },
    { "h_dst_hdr_a2r10_to_a128f",  F_A2R10, F_A128F, C_H, C_L, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,6.0f,0,2.0f, NULL },
    { "h_wp_a128f_to_argb",        F_A128F, F_ARGB,  C_L, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 2.0f,0,0,0, NULL },
    { "h_wp_pq_to_a128f",          F_A2R10, F_A128F, C_H, C_L, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 100.0f,0,0,0, NULL },
    { "h_chrome_709_a128f_to_argb", F_A128F, F_ARGB, C_L, C_S, 5,4, 5,4, NR, NR, NB, 255,255,255,255, -1, 0,3.0f,0,0, NULL },
    { "h_chrome_709_blend_a128f",  F_A128F, F_A128F, C_L, C_L, 5,4, 5,4, NR, NR, BL, 255,255,255,255, -1, 0,3.0f,0,1.0f, NULL },
    { "h_blend_a2r10_to_a128f",    F_A2R10, F_A128F, C_H, C_L, 5,4, 5,4, NR, NR, BL, 255,255,255,255, -1, 0,0,0,0, NULL },
  };
  for (unsigned i = 0; i < sizeof(scenes) / sizeof(scenes[0]); i++) run(&scenes[i]);
  return 0;
}
