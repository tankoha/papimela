/* evdev の能力のビットから機器の種類を決める SDL_EVDEV_GuessDeviceClass を、参照版の SDL に通して書き出す。
   papimela の test_evdev が同じビットを PMLEvdevGuessDeviceClass に通して突き合わせる。
   tools/evdev-expect/gen.bb が作って test/evdev_caps_expected.inc に書く。
   出力は 1 行ずつ「L p=<16進> e=<16進> a=<16進> k=<16進> r=<16進> c=<種類>」。16進はメモリ上のバイトを先頭から並べたもの。 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <linux/input.h>

#define BITS_PER_LONG (sizeof(unsigned long) * 8)
#define NBITS(x) ((((x)-1) / BITS_PER_LONG) + 1)
#ifndef INPUT_PROP_SEMI_MT
#define INPUT_PROP_SEMI_MT 0x03
#endif
#ifndef INPUT_PROP_TOPBUTTONPAD
#define INPUT_PROP_TOPBUTTONPAD 0x04
#endif
#ifndef INPUT_PROP_POINTING_STICK
#define INPUT_PROP_POINTING_STICK 0x05
#endif
#ifndef INPUT_PROP_ACCELEROMETER
#define INPUT_PROP_ACCELEROMETER 0x06
#endif
#ifndef INPUT_PROP_MAX
#define INPUT_PROP_MAX 0x1f
#endif
#ifndef BTN_DPAD_UP
#define BTN_DPAD_UP 0x220
#endif
#ifndef KEY_ALS_TOGGLE
#define KEY_ALS_TOGGLE 0x230
#endif
#ifndef BTN_TRIGGER_HAPPY
#define BTN_TRIGGER_HAPPY 0x2c0
#endif

extern int SDL_EVDEV_GuessDeviceClass(const unsigned long bitmask_props[NBITS(INPUT_PROP_MAX)],
                                      const unsigned long bitmask_ev[NBITS(EV_MAX)],
                                      const unsigned long bitmask_abs[NBITS(ABS_MAX)],
                                      const unsigned long bitmask_key[NBITS(KEY_MAX)],
                                      const unsigned long bitmask_rel[NBITS(REL_MAX)]);

static unsigned long long rng = 0x9E3779B97F4A7C15ULL;
static unsigned next(void)
{
  rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17;
  return (unsigned)(rng >> 16);
}

static unsigned long props[NBITS(INPUT_PROP_MAX)], ev[NBITS(EV_MAX)], absb[NBITS(ABS_MAX)], key[NBITS(KEY_MAX)], rel[NBITS(REL_MAX)];

static void setb(unsigned long *a, int bit) { a[bit / BITS_PER_LONG] |= 1UL << (bit % BITS_PER_LONG); }

static void hex(const void *p, size_t n)
{
  const unsigned char *b = p;
  for (size_t i = 0; i < n; i++) printf("%02x", b[i]);
}

static void emit(void)
{
  int c = SDL_EVDEV_GuessDeviceClass(props, ev, absb, key, rel);
  printf("L p="); hex(props, sizeof(props));
  printf(" e="); hex(ev, sizeof(ev));
  printf(" a="); hex(absb, sizeof(absb));
  printf(" k="); hex(key, sizeof(key));
  printf(" r="); hex(rel, sizeof(rel));
  printf(" c=%d\n", c);
}

static void clear(void) { memset(props, 0, sizeof(props)); memset(ev, 0, sizeof(ev)); memset(absb, 0, sizeof(absb)); memset(key, 0, sizeof(key)); memset(rel, 0, sizeof(rel)); }

int main(void)
{
  static const int prop_pool[] = { INPUT_PROP_POINTER, INPUT_PROP_DIRECT, INPUT_PROP_BUTTONPAD, INPUT_PROP_SEMI_MT, INPUT_PROP_TOPBUTTONPAD, INPUT_PROP_POINTING_STICK, INPUT_PROP_ACCELEROMETER };
  static const int abs_pool[] = { ABS_X, ABS_Y, ABS_Z, ABS_RX, ABS_RY, ABS_RZ, ABS_THROTTLE, ABS_RUDDER, ABS_WHEEL, ABS_GAS, ABS_BRAKE, ABS_HAT0X, ABS_HAT0Y, ABS_PRESSURE, ABS_MT_SLOT };
  static const int key_pool[] = { KEY_ESC, KEY_1, KEY_Q, KEY_D, KEY_A, KEY_ENTER, BTN_TRIGGER, BTN_1, BTN_A, BTN_MOUSE, BTN_LEFT, BTN_TOUCH, BTN_STYLUS, BTN_TOOL_PEN, BTN_TOOL_FINGER, BTN_GAMEPAD, BTN_MISC, BTN_THUMBL, KEY_OK, KEY_ALS_TOGGLE, BTN_DPAD_UP, BTN_TRIGGER_HAPPY, KEY_POWER, KEY_VOLUMEUP, 0x1ff, 0x2ff };
  int n, i;

  /* 実在する型の機器 */
  clear(); setb(ev, EV_SYN); setb(ev, EV_KEY); setb(ev, EV_ABS); setb(ev, EV_FF);
  setb(key, BTN_A); setb(key, BTN_B); setb(key, BTN_X); setb(key, BTN_Y); setb(key, BTN_TL); setb(key, BTN_TR);
  setb(absb, ABS_X); setb(absb, ABS_Y); setb(absb, ABS_RX); setb(absb, ABS_RY); setb(absb, ABS_Z); setb(absb, ABS_RZ);
  emit();
  clear(); setb(ev, EV_SYN); setb(ev, EV_KEY); setb(ev, EV_REL); setb(key, BTN_LEFT); setb(rel, REL_X); setb(rel, REL_Y);
  emit();
  clear(); setb(ev, EV_KEY);
  for (i = 1; i < 32; i++) setb(key, i);
  emit();
  clear(); setb(ev, EV_KEY); setb(key, KEY_POWER); emit();
  clear(); setb(ev, EV_KEY); setb(key, KEY_OK); emit();
  clear(); setb(ev, EV_ABS); setb(absb, ABS_X); setb(absb, ABS_Y); setb(absb, ABS_Z); emit();
  clear(); setb(ev, EV_ABS); setb(absb, ABS_RX); setb(absb, ABS_RY); setb(absb, ABS_RZ); emit();
  clear(); emit();

  /* 乱数の組み合わせ。選ぶ確率を変えて、全部の枝を通す */
  for (n = 0; n < 4000; n++) {
    unsigned density = 1 + next() % 5;
    clear();
    for (i = 0; i < (int)(sizeof(prop_pool) / sizeof(prop_pool[0])); i++) if (next() % 12 == 0) setb(props, prop_pool[i]);
    for (i = 0; i <= EV_MAX; i++) if (next() % 3 == 0) setb(ev, i);
    if (next() % 4) setb(ev, EV_ABS);
    if (next() % 4) setb(ev, EV_KEY);
    if (next() % 3 == 0) setb(ev, EV_REL);
    for (i = 0; i < (int)(sizeof(abs_pool) / sizeof(abs_pool[0])); i++) if (next() % (density + 1) == 0) setb(absb, abs_pool[i]);
    if (next() % 2) { setb(absb, ABS_X); setb(absb, ABS_Y); }
    for (i = 0; i < (int)(sizeof(key_pool) / sizeof(key_pool[0])); i++) if (next() % (density + 2) == 0) setb(key, key_pool[i]);
    if (next() % 6 == 0) for (i = 1; i < 32; i++) setb(key, i);
    if (next() % 5 == 0) { setb(rel, REL_X); setb(rel, REL_Y); }
    if (next() % 9 == 0) for (i = 0; i < 40; i++) if (next() % 2) setb(key, next() % (KEY_MAX + 1));
    emit();
  }
  return 0;
}
