/* サーフェスからテクスチャを作る（SDL_CreateTextureFromSurface）ときの、カラーキー・変調・ブレンドの扱いを、
   参照版 SDL（ソフトウェアのレンダラ。表示サーバ無し）で測る。papimela の test_texture_colorkey が
   同じ場面を行って突き合わせる。tools/texture-colorkey-expect/gen.bb が test/texture_colorkey_expected.inc に書く。
   出力（1 行ずつ）:
     R <場面> <テクスチャの形式> blend=<n> cmod=<r>,<g>,<b> amod=<a> <ハッシュ（テクスチャのブレンドで描いた絵）> <ハッシュ（ブレンド無しで描いた絵）>
   または  R <場面> err <文面> */
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>

static SDL_Surface *target;
static SDL_Renderer *rr;

static unsigned fnv(const unsigned char *p, int n, unsigned h) { for (int i = 0; i < n; i++) { h ^= p[i]; h *= 16777619u; } return h; }

static unsigned render_hash(SDL_Texture *t, int w, int h)
{
  SDL_SetRenderDrawColor(rr, 10, 20, 30, 255);
  SDL_RenderClear(rr);
  SDL_FRect dst = { 0, 0, (float)w, (float)h };
  SDL_RenderTexture(rr, t, NULL, &dst);
  SDL_RenderPresent(rr);
  unsigned hsh = 2166136261u;
  for (int y = 0; y < target->h; y++) hsh = fnv((unsigned char *)target->pixels + y * target->pitch, target->w * 4, 2166136261u) ^ (hsh * 16777619u);
  return hsh;
}

static const SDL_Color cols[4] = { { 255, 0, 0, 255 }, { 0, 255, 0, 255 }, { 0, 0, 255, 255 }, { 255, 255, 0, 255 } };

static SDL_Surface *make(SDL_PixelFormat f)
{
  SDL_Surface *s = SDL_CreateSurface(4, 3, f);
  if (!s) return NULL;
  if (SDL_ISPIXELFORMAT_INDEXED(f)) {
    SDL_Palette *pal = SDL_CreatePalette(4);
    SDL_SetPaletteColors(pal, cols, 0, 4);
    SDL_SetSurfacePalette(s, pal);
    SDL_DestroyPalette(pal);
    for (int y = 0; y < 3; y++) for (int x = 0; x < 4; x++) ((unsigned char *)s->pixels)[y * s->pitch + x] = (unsigned char)((x + y) % 4);
  } else {
    for (int y = 0; y < 3; y++) for (int x = 0; x < 4; x++) {
      SDL_Rect r = { x, y, 1, 1 };
      const SDL_Color c = cols[(x + y) % 4];
      SDL_FillSurfaceRect(s, &r, SDL_MapSurfaceRGBA(s, c.r, c.g, c.b, c.a));
    }
  }
  return s;
}

static void emit(const char *name, SDL_Surface *s)
{
  SDL_Texture *t = SDL_CreateTextureFromSurface(rr, s);
  if (!t) { printf("R %s err %s\n", name, SDL_GetError()); return; }
  SDL_PixelFormat f = (SDL_PixelFormat)SDL_GetNumberProperty(SDL_GetTextureProperties(t), SDL_PROP_TEXTURE_FORMAT_NUMBER, 0);
  SDL_BlendMode bm; Uint8 r, g, b, a;
  SDL_GetTextureBlendMode(t, &bm); SDL_GetTextureColorMod(t, &r, &g, &b); SDL_GetTextureAlphaMod(t, &a);
  unsigned h1 = render_hash(t, 4, 3);
  SDL_SetTextureBlendMode(t, SDL_BLENDMODE_NONE);
  unsigned h2 = render_hash(t, 4, 3);
  printf("R %s %s blend=%u cmod=%u,%u,%u amod=%u %08X %08X\n", name, SDL_GetPixelFormatName(f) + 16, (unsigned)bm, r, g, b, a, h1, h2);
  SDL_DestroyTexture(t);
}

int main(void)
{
  SDL_SetHint("SDL_VIDEO_DRIVER", "dummy");
  if (!SDL_Init(SDL_INIT_VIDEO)) { printf("INIT-ERR %s\n", SDL_GetError()); return 1; }
  target = SDL_CreateSurface(8, 8, SDL_PIXELFORMAT_ARGB8888);
  rr = SDL_CreateSoftwareRenderer(target);
  static const struct { const char *n; SDL_PixelFormat f; } fmts[] = {
    { "argb8888", SDL_PIXELFORMAT_ARGB8888 }, { "xrgb8888", SDL_PIXELFORMAT_XRGB8888 },
    { "abgr8888", SDL_PIXELFORMAT_ABGR8888 }, { "xbgr8888", SDL_PIXELFORMAT_XBGR8888 },
    { "bgra8888", SDL_PIXELFORMAT_BGRA8888 }, { "bgrx8888", SDL_PIXELFORMAT_BGRX8888 },
    { "rgba8888", SDL_PIXELFORMAT_RGBA8888 }, { "rgbx8888", SDL_PIXELFORMAT_RGBX8888 },
    { "rgb24", SDL_PIXELFORMAT_RGB24 }, { "bgr24", SDL_PIXELFORMAT_BGR24 },
    { "rgb565", SDL_PIXELFORMAT_RGB565 }, { "argb4444", SDL_PIXELFORMAT_ARGB4444 }, { "xrgb4444", SDL_PIXELFORMAT_XRGB4444 },
    { "argb1555", SDL_PIXELFORMAT_ARGB1555 }, { "xrgb1555", SDL_PIXELFORMAT_XRGB1555 }, { "rgb332", SDL_PIXELFORMAT_RGB332 },
    { "index8", SDL_PIXELFORMAT_INDEX8 } };
  for (unsigned i = 0; i < sizeof(fmts) / sizeof(fmts[0]); i++) {
    char nm[64];
    SDL_Surface *s = make(fmts[i].f);
    if (!s) { printf("R %s err create %s\n", fmts[i].n, SDL_GetError()); continue; }
    snprintf(nm, sizeof nm, "%s_plain", fmts[i].n);
    emit(nm, s);
    /* カラーキー: 赤のところを透明に */
    Uint32 key = SDL_ISPIXELFORMAT_INDEXED(fmts[i].f) ? 0 : SDL_MapSurfaceRGB(s, 255, 0, 0);
    SDL_SetSurfaceColorKey(s, true, key);
    snprintf(nm, sizeof nm, "%s_key", fmts[i].n);
    emit(nm, s);
    SDL_DestroySurface(s);
  }
  /* 変調とブレンドモードの引き継ぎ（カラーキー無し） */
  {
    SDL_Surface *s = make(SDL_PIXELFORMAT_XRGB8888);
    SDL_SetSurfaceColorMod(s, 200, 150, 100); SDL_SetSurfaceAlphaMod(s, 128); SDL_SetSurfaceBlendMode(s, SDL_BLENDMODE_ADD);
    emit("xrgb8888_mods_add", s);
    SDL_SetSurfaceColorKey(s, true, SDL_MapSurfaceRGB(s, 255, 0, 0));
    emit("xrgb8888_mods_add_key", s);
    SDL_DestroySurface(s);
    s = make(SDL_PIXELFORMAT_ARGB8888);
    SDL_SetSurfaceBlendMode(s, SDL_BLENDMODE_NONE);
    emit("argb8888_blend_none", s);
    SDL_SetSurfaceBlendMode(s, SDL_BLENDMODE_MOD);
    SDL_SetSurfaceColorMod(s, 90, 200, 255);
    emit("argb8888_blend_mod", s);
    SDL_DestroySurface(s);
    s = make(SDL_PIXELFORMAT_RGB24);
    emit("rgb24_default", s);
    SDL_SetSurfaceBlendMode(s, SDL_BLENDMODE_BLEND);
    emit("rgb24_blend", s);
    SDL_DestroySurface(s);
  }
  /* アルファのあるサーフェスのカラーキー（キーの色のところだけ透明にして、元のアルファは見ない） */
  {
    SDL_Surface *s = make(SDL_PIXELFORMAT_ARGB8888);
    SDL_Rect r = { 1, 0, 1, 1 };
    SDL_FillSurfaceRect(s, &r, SDL_MapSurfaceRGBA(s, 255, 0, 0, 100));   /* キーと RGB は同じ、アルファが違う */
    SDL_SetSurfaceColorKey(s, true, SDL_MapSurfaceRGBA(s, 255, 0, 0, 255));
    emit("argb8888_key_alpha_differs", s);
    SDL_DestroySurface(s);
  }
  SDL_Quit();
  return 0;
}
