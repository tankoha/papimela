/* SDL_LockTexture / SDL_UnlockTexture / SDL_LockTextureToSurface を、システムの SDL（ソフトウェアの
   レンダラ。表示サーバ無し）に通して、場面ごとの結果を書き出す。papimela の test_texture_lock が
   同じ場面を Pascal で行って突き合わせる。tools/texture-lock-expect/gen.bb が作って
   test/texture_lock_expected.inc に書く。
   出力（1 行ずつ）:
     R <場面> ok <ピッチ> <位置> <ハッシュ> ...   または   R <場面> err <文面>
   位置は、同じテクスチャの全体 Lock の先頭からの差（バイト）。ハッシュは描いた絵の FNV-1a。 */
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static unsigned lcg = 1;
static unsigned nx(void) { lcg = lcg * 1103515245u + 12345u; return lcg >> 16; }
static unsigned fnv(const unsigned char *p, int n) { unsigned h = 2166136261u; for (int i = 0; i < n; i++) { h ^= p[i]; h *= 16777619u; } return h; }

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
  for (int y = 0; y < target->h; y++) hsh = fnv((unsigned char *)target->pixels + y * target->pitch, target->w * 4) ^ (hsh * 16777619u);
  return hsh;
}

/* YUV の値は範囲の内側（96..159）に収める。範囲の外は SDL のスカラー版が回り込み、papimela は飽和させる（D-62） */
static int yuv_safe = 0;
static void fill(unsigned char *p, int pitch, int rowbytes, int rows, int seed)
{
  lcg = seed;
  for (int y = 0; y < rows; y++) for (int x = 0; x < rowbytes; x++) {
    unsigned v = nx();
    p[y * pitch + x] = yuv_safe ? (unsigned char)(96 + (v & 63)) : (unsigned char)v;
  }
}

/* 全体を Lock して中身を seed で埋める（初期の絵） */
static void init_full(SDL_Texture *t, int w, int h, int bpp, int seed)
{
  void *px; int pitch;
  if (SDL_LockTexture(t, NULL, &px, &pitch)) { fill(px, pitch, w * bpp, h, seed); SDL_UnlockTexture(t); }
}

static void scenario_rgb(const char *name, SDL_PixelFormat fmt, int w, int h, int bpp, SDL_Rect *r)
{
  SDL_Texture *t = SDL_CreateTexture(rr, fmt, SDL_TEXTUREACCESS_STREAMING, w, h);
  if (!t) { printf("R %s err create %s\n", name, SDL_GetError()); return; }
  SDL_SetTextureBlendMode(t, SDL_BLENDMODE_NONE);   /* 合成の丸めは SDL と 1 違う（D-44）ので、写すだけにする */
  yuv_safe = (fmt == SDL_PIXELFORMAT_YUY2 || fmt == SDL_PIXELFORMAT_UYVY || fmt == SDL_PIXELFORMAT_YVYU);
  init_full(t, w, h, bpp, 7);
  void *full; int fp; SDL_LockTexture(t, NULL, &full, &fp); SDL_UnlockTexture(t);
  void *px; int pitch;
  if (!SDL_LockTexture(t, r, &px, &pitch)) { printf("R %s err %s\n", name, SDL_GetError()); SDL_DestroyTexture(t); return; }
  long off = (unsigned char *)px - (unsigned char *)full;
  int rw = r ? r->w : w, rh = r ? r->h : h;
  fill(px, pitch, rw * bpp, rh, 99);
  SDL_UnlockTexture(t);
  printf("R %s ok %d %ld %08X\n", name, pitch, off, render_hash(t, w, h));
  yuv_safe = 0;
  SDL_DestroyTexture(t);
}

int main(void)
{
  SDL_SetHint("SDL_VIDEO_DRIVER", "dummy");
  if (!SDL_Init(SDL_INIT_VIDEO)) { printf("INIT-ERR %s\n", SDL_GetError()); return 1; }
  target = SDL_CreateSurface(8, 8, SDL_PIXELFORMAT_ARGB8888);
  rr = SDL_CreateSoftwareRenderer(target);
  if (!rr) { printf("INIT-ERR %s\n", SDL_GetError()); return 1; }

  /* ARGB8888 */
  scenario_rgb("argb_full", SDL_PIXELFORMAT_ARGB8888, 6, 5, 4, NULL);
  SDL_Rect r1 = { 1, 2, 3, 2 };
  scenario_rgb("argb_rect", SDL_PIXELFORMAT_ARGB8888, 6, 5, 4, &r1);
  SDL_Rect r2 = { 5, 4, 1, 1 };
  scenario_rgb("argb_corner", SDL_PIXELFORMAT_ARGB8888, 6, 5, 4, &r2);
  scenario_rgb("bgr24_rect", SDL_PIXELFORMAT_BGR24, 6, 5, 3, &r1);   /* RGB565 は SDL の高速なブリット（SDL_blit_N）と papimela で拡張の丸めが違う */
  scenario_rgb("rgb24_full", SDL_PIXELFORMAT_RGB24, 5, 3, 3, NULL);
  scenario_rgb("abgr8888_rect", SDL_PIXELFORMAT_ABGR8888, 6, 5, 4, &r1);
  scenario_rgb("yuy2_rect", SDL_PIXELFORMAT_YUY2, 6, 4, 2, &(SDL_Rect){ 2, 1, 2, 2 });
  scenario_rgb("uyvy_full", SDL_PIXELFORMAT_UYVY, 6, 4, 2, NULL);
  scenario_rgb("yvyu_rect", SDL_PIXELFORMAT_YVYU, 6, 4, 2, &(SDL_Rect){ 4, 2, 2, 1 });

  /* 静的・描画先は断る */
  { SDL_Texture *t = SDL_CreateTexture(rr, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STATIC, 4, 4); void *p; int pi;
    if (SDL_LockTexture(t, NULL, &p, &pi)) printf("R static_lock ok\n"); else printf("R static_lock err %s\n", SDL_GetError());
    SDL_UnlockTexture(t); printf("R static_unlock ok\n"); SDL_DestroyTexture(t); }
  { SDL_Texture *t = SDL_CreateTexture(rr, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, 4, 4); void *p; int pi;
    if (SDL_LockTexture(t, NULL, &p, &pi)) printf("R target_lock ok\n"); else printf("R target_lock err %s\n", SDL_GetError());
    SDL_DestroyTexture(t); }

  /* YUV の平面形式は全体の Lock だけ */
  static const struct { const char *n; SDL_PixelFormat f; } planar[] = {
    { "iyuv", SDL_PIXELFORMAT_IYUV }, { "yv12", SDL_PIXELFORMAT_YV12 }, { "nv12", SDL_PIXELFORMAT_NV12 }, { "nv21", SDL_PIXELFORMAT_NV21 } };
  for (int i = 0; i < 4; i++) {
    char nm[48];
    SDL_Texture *t = SDL_CreateTexture(rr, planar[i].f, SDL_TEXTUREACCESS_STREAMING, 6, 4);
    if (!t) { printf("R %s_full err create %s\n", planar[i].n, SDL_GetError()); continue; }
    yuv_safe = 1;
    void *px; int pitch;
    snprintf(nm, sizeof nm, "%s_full", planar[i].n);
    if (SDL_LockTexture(t, NULL, &px, &pitch)) {
      /* Y 平面 6x4、色差は (6+1)/2 x (4+1)/2 の 2 枚（NV は交互の 1 枚）= 全体 36 バイト */
      fill(px, 0, 36, 1, 21);
      SDL_UnlockTexture(t);
      printf("R %s ok %d 0 %08X\n", nm, pitch, render_hash(t, 6, 4));
    } else printf("R %s err %s\n", nm, SDL_GetError());
    snprintf(nm, sizeof nm, "%s_partial", planar[i].n);
    SDL_Rect pr = { 0, 0, 4, 4 };
    if (SDL_LockTexture(t, &pr, &px, &pitch)) { printf("R %s ok\n", nm); SDL_UnlockTexture(t); } else printf("R %s err %s\n", nm, SDL_GetError());
    snprintf(nm, sizeof nm, "%s_fullrect", planar[i].n);
    SDL_Rect fr = { 0, 0, 6, 4 };
    if (SDL_LockTexture(t, &fr, &px, &pitch)) { printf("R %s ok %d\n", nm, pitch); SDL_UnlockTexture(t); } else printf("R %s err %s\n", nm, SDL_GetError());
    yuv_safe = 0;
    SDL_DestroyTexture(t);
  }

  /* INDEX8（ソフトウェアのレンダラは直接持てない: palette_surface の道） */
  {
    SDL_Texture *t = SDL_CreateTexture(rr, SDL_PIXELFORMAT_INDEX8, SDL_TEXTUREACCESS_STREAMING, 6, 4);
    if (!t) printf("R index8 err create %s\n", SDL_GetError());
    else {
      SDL_Palette *pal = SDL_CreatePalette(256);
      for (int i = 0; i < 256; i++) { pal->colors[i].r = (Uint8)(i * 3); pal->colors[i].g = (Uint8)(255 - i); pal->colors[i].b = (Uint8)(i * 7); pal->colors[i].a = 255; }
      SDL_SetTexturePalette(t, pal);
      void *full; int fp; SDL_LockTexture(t, NULL, &full, &fp);
      fill(full, fp, 6, 4, 5);
      SDL_UnlockTexture(t);
      printf("R index8_full ok %d 0 %08X\n", fp, render_hash(t, 6, 4));
      void *px; int pitch; SDL_Rect r = { 2, 1, 3, 2 };
      SDL_LockTexture(t, &r, &px, &pitch);
      printf("R index8_rect_pos %d %ld\n", pitch, (long)((unsigned char *)px - (unsigned char *)full));
      fill(px, pitch, 3, 2, 77);
      SDL_UnlockTexture(t);
      printf("R index8_rect ok %d %08X\n", pitch, render_hash(t, 6, 4));
      SDL_DestroyPalette(pal);
      SDL_DestroyTexture(t);
    }
  }

  /* LockTextureToSurface */
  {
    SDL_Texture *t = SDL_CreateTexture(rr, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, 6, 5);
    SDL_SetTextureBlendMode(t, SDL_BLENDMODE_NONE);
    init_full(t, 6, 5, 4, 7);
    void *full; int fp; SDL_LockTexture(t, NULL, &full, &fp); SDL_UnlockTexture(t);
    SDL_Surface *s;
    SDL_Rect r = { 1, 1, 3, 2 };
    if (SDL_LockTextureToSurface(t, &r, &s)) {
      printf("R tosurf_rect %d %d %d %d %ld\n", s->w, s->h, s->pitch, s->format, (long)((unsigned char *)s->pixels - (unsigned char *)full));
      for (int y = 0; y < s->h; y++) memset((unsigned char *)s->pixels + y * s->pitch, 0x7F, s->w * 4);
      SDL_UnlockTexture(t);
      printf("R tosurf_rect_hash %08X\n", render_hash(t, 6, 5));
    } else printf("R tosurf_rect err %s\n", SDL_GetError());
    SDL_Rect r2b = { -1, -1, 4, 4 };
    if (SDL_LockTextureToSurface(t, &r2b, &s)) { printf("R tosurf_clip %d %d %ld\n", s->w, s->h, (long)((unsigned char *)s->pixels - (unsigned char *)full)); SDL_UnlockTexture(t); } else printf("R tosurf_clip err %s\n", SDL_GetError());
    if (SDL_LockTextureToSurface(t, NULL, &s)) { printf("R tosurf_full %d %d %d\n", s->w, s->h, s->pitch); SDL_UnlockTexture(t); } else printf("R tosurf_full err %s\n", SDL_GetError());
    SDL_Rect r3 = { 10, 10, 2, 2 };
    if (SDL_LockTextureToSurface(t, &r3, &s)) { printf("R tosurf_outside %d %d\n", s->w, s->h); SDL_UnlockTexture(t); } else printf("R tosurf_outside err %s\n", SDL_GetError());
    SDL_DestroyTexture(t);
    SDL_Texture *st = SDL_CreateTexture(rr, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STATIC, 4, 4);
    if (SDL_LockTextureToSurface(st, NULL, &s)) printf("R tosurf_static ok\n"); else printf("R tosurf_static err %s\n", SDL_GetError());
    SDL_DestroyTexture(st);
    /* インデックス形式のサーフェスはパレットを持つか */
    SDL_Texture *it = SDL_CreateTexture(rr, SDL_PIXELFORMAT_INDEX8, SDL_TEXTUREACCESS_STREAMING, 4, 4);
    SDL_Palette *pal = SDL_CreatePalette(16); SDL_SetTexturePalette(it, pal);
    if (SDL_LockTextureToSurface(it, NULL, &s)) { printf("R tosurf_index8 %d %d %d palette=%d\n", s->w, s->h, s->pitch, SDL_GetSurfacePalette(s) == pal); SDL_UnlockTexture(it); } else printf("R tosurf_index8 err %s\n", SDL_GetError());
    SDL_DestroyTexture(it); SDL_DestroyPalette(pal);
    /* YUV のサーフェスは作れるか */
    SDL_Texture *yt = SDL_CreateTexture(rr, SDL_PIXELFORMAT_IYUV, SDL_TEXTUREACCESS_STREAMING, 4, 4);
    if (SDL_LockTextureToSurface(yt, NULL, &s)) { printf("R tosurf_iyuv ok %d %d %d\n", s->w, s->h, s->pitch); SDL_UnlockTexture(yt); } else printf("R tosurf_iyuv err %s\n", SDL_GetError());
    SDL_DestroyTexture(yt);
  }

  /* 二重の Lock、Lock せずに Unlock */
  { SDL_Texture *t = SDL_CreateTexture(rr, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, 4, 4);
    void *a, *b; int pa, pb;
    SDL_LockTexture(t, NULL, &a, &pa); SDL_LockTexture(t, NULL, &b, &pb);
    printf("R double_lock %d %d\n", a == b, pa == pb);
    SDL_UnlockTexture(t); SDL_UnlockTexture(t);
    printf("R double_unlock ok\n");
    SDL_DestroyTexture(t); }

  SDL_Quit();
  return 0;
}
