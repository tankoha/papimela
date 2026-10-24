/* 色空間の変換（転送関数・原色・トーンマップ）を、参照版の SDL に通して、場面ごとの結果を書き出す。
   papimela の test_colorspace が同じ場面を Pascal で行って突き合わせる。
   tools/colorspace-expect/gen.bb が作って test/colorspace_expected.inc に書く。
   出力（1 行ずつ）:
     F <関数> <入力の 32 ビット> <出力の 32 ビット>                 転送関数（SDL_sRGBtoLinear など）
     M <原色の組> <9 つの 32 ビット>                                  原色の変換行列（無ければ none）
     W <色空間> <白点の 32 ビット> <ヘッドルームの 32 ビット>        既定の SDR の白点と HDR のヘッドルーム
     X <場面> <src 形式> <src 色空間> <dst 形式> <dst 色空間> <w> <h> <sw> <sh> <dw> <dh> <トーンマップ> <src の 16 進> <dst の 16 進>
   X の sw/sh/dw/dh は 32 ビットの浮動小数（0 = 指定なし）、トーンマップは - か文字列。 */
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>

extern float SDL_sRGBtoLinear(float v);
extern float SDL_sRGBfromLinear(float v);
extern float SDL_PQtoNits(float v);
extern float SDL_PQfromNits(float v);
extern const float *SDL_GetColorPrimariesConversionMatrix(SDL_ColorPrimaries src, SDL_ColorPrimaries dst);
extern float SDL_GetDefaultSDRWhitePoint(SDL_Colorspace colorspace);
extern float SDL_GetDefaultHDRHeadroom(SDL_Colorspace colorspace);

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

static void hex(const unsigned char *p, int n)
{
  for (int i = 0; i < n; i++) printf("%02X", p[i]);
}

/* 入力を作る。整数の形式は乱数のバイト、浮動小数の形式は 0..1.5 の値 */
static void make_input(unsigned char *p, SDL_PixelFormat f, int npix)
{
  int bpp = SDL_BYTESPERPIXEL(f);
  int comps = bpp * 8 / (SDL_PIXELTYPE(f) == SDL_PIXELTYPE_ARRAYF32 ? 32 : 16);
  if (SDL_PIXELTYPE(f) == SDL_PIXELTYPE_ARRAYF16) {
    for (int i = 0; i < npix * comps; i++) ((uint16_t *)p)[i] = to_half((float)(nx() % 1500) / 1000.0f);
  } else if (SDL_PIXELTYPE(f) == SDL_PIXELTYPE_ARRAYF32) {
    for (int i = 0; i < npix * comps; i++) ((float *)p)[i] = (float)(nx() % 1500) / 1000.0f;
  } else {
    for (int i = 0; i < npix * bpp; i++) p[i] = (unsigned char)nx();
  }
  if (!SDL_ISPIXELFORMAT_ARRAY(f) && SDL_ISPIXELFORMAT_10BIT(f)) {
    /* 10 ビットは全ビットが値 */
  }
}

static int case_no = 0;
static const unsigned char *forced_src = NULL;   /* 入力を決め打ちする場面（1 x 1） */

static void run(const char *name, SDL_PixelFormat sf, SDL_Colorspace sc, SDL_PixelFormat df, SDL_Colorspace dc,
                float sw, float sh, float dw, float dh, const char *tonemap)
{
  int w = forced_src ? 1 : 6, h = forced_src ? 1 : 3, n = w * h;
  unsigned char *src = calloc(1, (size_t)n * SDL_BYTESPERPIXEL(sf));
  unsigned char *dst = calloc(1, (size_t)n * SDL_BYTESPERPIXEL(df));
  lcg = 100 + (case_no++) * 7;
  if (forced_src) memcpy(src, forced_src, SDL_BYTESPERPIXEL(sf)); else make_input(src, sf, n);
  SDL_PropertiesID sp = 0, dp = 0;
  if (sw != 0 || sh != 0 || tonemap) {
    sp = SDL_CreateProperties();
    if (sw != 0) SDL_SetFloatProperty(sp, SDL_PROP_SURFACE_SDR_WHITE_POINT_FLOAT, sw);
    if (sh != 0) SDL_SetFloatProperty(sp, SDL_PROP_SURFACE_HDR_HEADROOM_FLOAT, sh);
    if (tonemap) SDL_SetStringProperty(sp, SDL_PROP_SURFACE_TONEMAP_OPERATOR_STRING, tonemap);
  }
  if (dw != 0 || dh != 0) {
    dp = SDL_CreateProperties();
    if (dw != 0) SDL_SetFloatProperty(dp, SDL_PROP_SURFACE_SDR_WHITE_POINT_FLOAT, dw);
    if (dh != 0) SDL_SetFloatProperty(dp, SDL_PROP_SURFACE_HDR_HEADROOM_FLOAT, dh);
  }
  bool ok = SDL_ConvertPixelsAndColorspace(w, h, sf, sc, sp, src, w * SDL_BYTESPERPIXEL(sf),
                                           df, dc, dp, dst, w * SDL_BYTESPERPIXEL(df));
  if (!ok) { printf("X %s err %s\n", name, SDL_GetError()); }
  else {
    printf("X %s %08X %08X %08X %08X %d %d %08X %08X %08X %08X %s ", name, sf, sc, df, dc, w, h,
           bits(sw), bits(sh), bits(dw), bits(dh), tonemap ? tonemap : "-");
    hex(src, n * SDL_BYTESPERPIXEL(sf)); printf(" ");
    hex(dst, n * SDL_BYTESPERPIXEL(df)); printf("\n");
  }
  if (sp) SDL_DestroyProperties(sp);
  if (dp) SDL_DestroyProperties(dp);
  free(src); free(dst);
}

int main(void)
{
  /* 転送関数 */
  static const float ins[] = { 0.0f, 0.001f, 0.003f, 0.0031308f, 0.01f, 0.04045f, 0.05f, 0.1f, 0.2f, 0.3f, 0.4f, 0.5f, 0.6f,
                               0.7f, 0.8f, 0.9f, 0.99f, 1.0f, 1.2f, 2.0f, 5.0f, 100.0f, 203.0f, 1000.0f, 4000.0f, 10000.0f };
  for (unsigned i = 0; i < sizeof(ins) / sizeof(ins[0]); i++) {
    float v = ins[i];
    printf("F srgb_to_linear %08X %08X\n", bits(v), bits(SDL_sRGBtoLinear(v)));
    printf("F srgb_from_linear %08X %08X\n", bits(v), bits(SDL_sRGBfromLinear(v)));
    if (v <= 1.0f) printf("F pq_to_nits %08X %08X\n", bits(v), bits(SDL_PQtoNits(v)));
    printf("F pq_from_nits %08X %08X\n", bits(v), bits(SDL_PQfromNits(v)));
  }
  /* 原色の行列 */
  static const int prim[] = { SDL_COLOR_PRIMARIES_BT709, SDL_COLOR_PRIMARIES_BT601, SDL_COLOR_PRIMARIES_BT2020,
                              SDL_COLOR_PRIMARIES_SMPTE240, SDL_COLOR_PRIMARIES_SMPTE431, SDL_COLOR_PRIMARIES_SMPTE432,
                              SDL_COLOR_PRIMARIES_UNSPECIFIED };
  for (int s = 0; s < 7; s++) for (int d = 0; d < 7; d++) {
    const float *m = SDL_GetColorPrimariesConversionMatrix((SDL_ColorPrimaries)prim[s], (SDL_ColorPrimaries)prim[d]);
    printf("M %d %d", prim[s], prim[d]);
    if (!m) printf(" none\n");
    else { for (int i = 0; i < 9; i++) printf(" %08X", bits(m[i])); printf("\n"); }
  }
  /* 白点とヘッドルーム */
  static const SDL_Colorspace css[] = { SDL_COLORSPACE_SRGB, SDL_COLORSPACE_SRGB_LINEAR, SDL_COLORSPACE_HDR10,
                                        SDL_COLORSPACE_BT709_LIMITED, SDL_COLORSPACE_BT2020_FULL, SDL_COLORSPACE_JPEG };
  for (unsigned i = 0; i < sizeof(css) / sizeof(css[0]); i++)
    printf("W %08X %08X %08X\n", css[i], bits(SDL_GetDefaultSDRWhitePoint(css[i])), bits(SDL_GetDefaultHDRHeadroom(css[i])));

  /* 画素の変換 */
  static const SDL_PixelFormat srcs[] = {
    SDL_PIXELFORMAT_ARGB8888, SDL_PIXELFORMAT_XBGR8888, SDL_PIXELFORMAT_RGB24, SDL_PIXELFORMAT_BGRA8888, /* RGB565 は入れない: 5・6 ビットの拡張の丸めが SDL_blit_N と違う（HANDOFF §8） */
    SDL_PIXELFORMAT_XBGR2101010, SDL_PIXELFORMAT_ARGB2101010, SDL_PIXELFORMAT_RGB48, SDL_PIXELFORMAT_BGRA64,
    SDL_PIXELFORMAT_RGB48_FLOAT, SDL_PIXELFORMAT_ABGR64_FLOAT, SDL_PIXELFORMAT_RGB96_FLOAT, SDL_PIXELFORMAT_ARGB128_FLOAT };
  static const SDL_PixelFormat dsts[] = {
    SDL_PIXELFORMAT_ARGB8888, SDL_PIXELFORMAT_ABGR8888, SDL_PIXELFORMAT_RGB24, SDL_PIXELFORMAT_XBGR2101010,
    SDL_PIXELFORMAT_ARGB2101010, SDL_PIXELFORMAT_RGB48, SDL_PIXELFORMAT_RGBA64, SDL_PIXELFORMAT_RGB48_FLOAT,
    SDL_PIXELFORMAT_BGRA64_FLOAT, SDL_PIXELFORMAT_RGB96_FLOAT, SDL_PIXELFORMAT_RGBA128_FLOAT };
  static const struct { SDL_Colorspace s, d; } pairs[] = {
    { SDL_COLORSPACE_SRGB, SDL_COLORSPACE_SRGB_LINEAR },
    { SDL_COLORSPACE_SRGB_LINEAR, SDL_COLORSPACE_SRGB },
    { SDL_COLORSPACE_HDR10, SDL_COLORSPACE_SRGB },
    { SDL_COLORSPACE_SRGB, SDL_COLORSPACE_HDR10 },
    { SDL_COLORSPACE_BT709_LIMITED, SDL_COLORSPACE_SRGB },   /* YUV の色空間を RGB の色空間として使う（I0FL / P010 の経路） */
    { SDL_COLORSPACE_BT2020_FULL, SDL_COLORSPACE_SRGB },
    { SDL_COLORSPACE_SRGB, SDL_COLORSPACE_SRGB } };
  int k = 0;
  for (unsigned s = 0; s < sizeof(srcs) / sizeof(srcs[0]); s++)
    for (unsigned d = 0; d < sizeof(dsts) / sizeof(dsts[0]); d++) {
      if ((s + d) % 3 != 0 && !(s == d % 12)) continue;   /* 組み合わせを間引く */
      char nm[40]; snprintf(nm, sizeof nm, "c%03d", k);
      run(nm, srcs[s], pairs[k % 7].s, dsts[d], pairs[k % 7].d, 0, 0, 0, 0, NULL);
      k++;
    }
  /* 同じ色空間（整数の経路）の 10 ビット */
  run("same_8_to_10", SDL_PIXELFORMAT_ARGB8888, SDL_COLORSPACE_SRGB, SDL_PIXELFORMAT_XBGR2101010, SDL_COLORSPACE_SRGB, 0, 0, 0, 0, NULL);
  run("same_8_to_a10", SDL_PIXELFORMAT_ABGR8888, SDL_COLORSPACE_SRGB, SDL_PIXELFORMAT_ARGB2101010, SDL_COLORSPACE_SRGB, 0, 0, 0, 0, NULL);
  run("same_10_to_8", SDL_PIXELFORMAT_XBGR2101010, SDL_COLORSPACE_SRGB, SDL_PIXELFORMAT_ARGB8888, SDL_COLORSPACE_SRGB, 0, 0, 0, 0, NULL);
  run("same_a10_to_8", SDL_PIXELFORMAT_ARGB2101010, SDL_COLORSPACE_SRGB, SDL_PIXELFORMAT_ABGR8888, SDL_COLORSPACE_SRGB, 0, 0, 0, 0, NULL);
  run("same_10_to_10", SDL_PIXELFORMAT_ABGR2101010, SDL_COLORSPACE_SRGB, SDL_PIXELFORMAT_XRGB2101010, SDL_COLORSPACE_SRGB, 0, 0, 0, 0, NULL);
  run("same_24_to_8", SDL_PIXELFORMAT_RGB24, SDL_COLORSPACE_SRGB, SDL_PIXELFORMAT_BGRA8888, SDL_COLORSPACE_SRGB, 0, 0, 0, 0, NULL);
  /* 半分の丸め: 0.5 を 255 倍すると 0.5 になる値。roundf は 1、偶数への丸めは 0 */
  { float half_v; uint32_t hb = 0x3B008081u; memcpy(&half_v, &hb, 4);
    float px[4] = { half_v, half_v, half_v, 1.0f };
    forced_src = (const unsigned char *)px;
    run("round_half", SDL_PIXELFORMAT_RGBA128_FLOAT, SDL_COLORSPACE_SRGB_LINEAR, SDL_PIXELFORMAT_ARGB8888, SDL_COLORSPACE_SRGB_LINEAR, 0, 0, 0, 0, NULL);
    forced_src = NULL; }
  /* 半精度への丸め: 隣り合う 2 つの半精度のちょうど真ん中の値は、偶数の仮数のほうへ丸める */
  { float px[4] = { 1.0f + 1.0f / 2048.0f, 1.0f + 3.0f / 2048.0f, 0.5f, 1.0f };
    forced_src = (const unsigned char *)px;
    run("half_tie", SDL_PIXELFORMAT_RGBA128_FLOAT, SDL_COLORSPACE_SRGB_LINEAR, SDL_PIXELFORMAT_RGBA64_FLOAT, SDL_COLORSPACE_SRGB_LINEAR, 0, 0, 0, 0, NULL);
    forced_src = NULL; }
  /* 白点・ヘッドルームの指定は、線形と PQ の色空間だけが読む */
  run("wp_srgb_ignored", SDL_PIXELFORMAT_ARGB8888, SDL_COLORSPACE_SRGB, SDL_PIXELFORMAT_RGBA128_FLOAT, SDL_COLORSPACE_SRGB_LINEAR, 100.0f, 7.0f, 0, 0, NULL);
  /* 白点・ヘッドルーム・トーンマップ */
  run("wp_pq_to_srgb", SDL_PIXELFORMAT_XBGR2101010, SDL_COLORSPACE_HDR10, SDL_PIXELFORMAT_ARGB8888, SDL_COLORSPACE_SRGB, 100.0f, 0, 0, 0, NULL);
  run("wp_linear", SDL_PIXELFORMAT_RGBA128_FLOAT, SDL_COLORSPACE_SRGB_LINEAR, SDL_PIXELFORMAT_ARGB8888, SDL_COLORSPACE_SRGB, 2.0f, 0, 0, 0, NULL);
  run("wp_to_pq", SDL_PIXELFORMAT_ARGB8888, SDL_COLORSPACE_SRGB, SDL_PIXELFORMAT_XBGR2101010, SDL_COLORSPACE_HDR10, 0, 0, 300.0f, 0, NULL);
  run("tm_chrome", SDL_PIXELFORMAT_XBGR2101010, SDL_COLORSPACE_HDR10, SDL_PIXELFORMAT_ARGB8888, SDL_COLORSPACE_SRGB, 0, 4.0f, 0, 0, NULL);
  run("tm_chrome_709", SDL_PIXELFORMAT_RGBA128_FLOAT, SDL_COLORSPACE_SRGB_LINEAR, SDL_PIXELFORMAT_ARGB8888, SDL_COLORSPACE_SRGB, 0, 3.0f, 0, 0, NULL);
  run("tm_none", SDL_PIXELFORMAT_XBGR2101010, SDL_COLORSPACE_HDR10, SDL_PIXELFORMAT_ARGB8888, SDL_COLORSPACE_SRGB, 0, 4.0f, 0, 0, "none");
  run("tm_linear", SDL_PIXELFORMAT_XBGR2101010, SDL_COLORSPACE_HDR10, SDL_PIXELFORMAT_ARGB8888, SDL_COLORSPACE_SRGB, 0, 4.0f, 0, 0, "*=0.5");
  run("hr_dst_inherits", SDL_PIXELFORMAT_XBGR2101010, SDL_COLORSPACE_HDR10, SDL_PIXELFORMAT_RGBA128_FLOAT, SDL_COLORSPACE_SRGB_LINEAR, 0, 4.0f, 0, 0, NULL);
  run("tm_chrome_dst_hdr", SDL_PIXELFORMAT_XBGR2101010, SDL_COLORSPACE_HDR10, SDL_PIXELFORMAT_RGBA128_FLOAT, SDL_COLORSPACE_SRGB_LINEAR, 0, 6.0f, 0, 2.0f, NULL);
  return 0;
}
