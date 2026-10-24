/* 機器の名前の整え方 SDL_CreateJoystickName（SDL_CreateDeviceName を含む）を、参照版の SDL に通して書き出す。
   papimela の test_joystick_linux が同じ入力を PMLCreateDeviceName に通して突き合わせる。
   tools/evdev-expect/gen.bb が作って test/joystick_names_expected.inc に書く。
   出力は 1 行ずつ「L <ベンダー>|<プロダクト>|<ベンダー名>|<製品名>|<結果。NULL は (null)>」。 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <SDL3/SDL.h>

extern char *SDL_CreateJoystickName(Uint16 vendor, Uint16 product, const char *vendor_name, const char *product_name);

static unsigned long long rng = 0x2545F4914F6CDD1DULL;
static unsigned next(void) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return (unsigned)(rng >> 20); }

static void one(Uint16 v, Uint16 p, const char *vn, const char *pn)
{
  char *r = SDL_CreateJoystickName(v, p, vn, pn);
  printf("L %04x|%04x|%s|%s|%s\n", v, p, vn ? vn : "", pn ? pn : "", r ? r : "(null)");
  SDL_free(r);
}

int main(void)
{
  static const char *vendors[] = { "", "Acme", "  Acme  Corp", "8BitDo Tech Ltd", "ASTRO Gaming", "Bensussen Deutsch & Associates,Inc.(BDA)",
    "Guangzhou Chicken Run Network Technology Co., Ltd.", "HORI CO.,LTD.", "HORI CO.,LTD", "Mad Catz Inc.", "Nintendo Co., Ltd.",
    "NVIDIA Corporation ", "Performance Designed Products", "QANBA USA, LLC", "QANBA USA,LLC", "Voyetra Turtle Beach,Inc.", "Unknown ",
    "(Standard system devices) ", "Razer", "HORI", "Sony Interactive Entertainment" };
  static const char *products[] = { "", "Pad", "Razer Raiju Tournament Edition Wired", "Raiju", "  Spaced   Out  Pad  ", "HORl Taiko No Tatsujin Drum Controller",
    "HORI Taiko", "Wireless Controller", "Controller", "Xbox 360 Wireless Receiver", "Acme-Acme Stick", "Pro Controller", "Unknown Gamepad",
    "8BitDo Pro 2", "NVIDIA Controller v01.04", "x", "a a", "Pad Pad Pad", "   ", "Sony Sony Pad" };
  static const unsigned short vp[][2] = { {0,0}, {0x045e,0x028e}, {0x045e,0x02ea}, {0x054c,0x0268}, {0x054c,0x05c4}, {0x054c,0x0ce6}, {0x057e,0x2009},
    {0x28de,0x1102}, {0x1234,0x5678}, {0x0079,0x0006}, {0x2dc8,0x3106}, {0x0e6f,0x0113}, {0x057e,0x0337}, {0x0001,0x0001}, {0xffff,0xffff} };
  int i, n;
  const int nv = sizeof(vendors) / sizeof(vendors[0]), np = sizeof(products) / sizeof(products[0]), nvp = sizeof(vp) / sizeof(vp[0]);
  /* 全部の組み合わせ（ベンダー名 × 製品名）を、数個の VID/PID と */
  for (i = 0; i < nv; i++) {
    int j;
    for (j = 0; j < np; j++) {
      one(vp[0][0], vp[0][1], vendors[i], products[j]);
      one(vp[8][0], vp[8][1], vendors[i], products[j]);
    }
  }
  /* VID/PID だけ（名前なし） */
  for (i = 0; i < nvp; i++) one(vp[i][0], vp[i][1], NULL, NULL);
  for (i = 0; i < nvp; i++) one(vp[i][0], vp[i][1], "", "");
  /* 製品名だけで VID/PID が表にある（表の名前が勝つか） */
  for (i = 0; i < nvp; i++) one(vp[i][0], vp[i][1], NULL, "Some Product");
  /* 乱数 */
  for (n = 0; n < 2000; n++) {
    const unsigned short *x = vp[next() % nvp];
    one(x[0], x[1], vendors[next() % nv], products[next() % np]);
  }
  return 0;
}
