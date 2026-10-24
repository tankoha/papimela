/*
 * haptic_cases.c — SDL の SDL_SYS_ToFFEffect（Linux のハプティクス）と SDL_Haptic_Get_Naxes（ヒントの軸の数）を
 * そのまま動かして、結果を書き出す。tools/haptic-expect/gen.bb が、SDL のソースから関数の本文を
 * gen_toffeffect.inc と gen_naxes.inc に抜き出して、このファイルに取り込む（手で写さない）。
 *
 * 出力（1 行 1 場面。先頭の 1 字が種類）:
 *   E <型> <値...> <ok> <ff_effect の 48 バイトの 16 進>   効果の変換
 *   N <ヒントの文字列を 16 進> <vid> <pid> <結果>          ヒントの軸の数
 */
#include <SDL3/SDL.h>
#include <linux/input.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>

static const char *g_hint = NULL;
#define SDL_HINT_JOYSTICK_HAPTIC_AXES "x"
#define SDL_GetHint(x) (g_hint)

#include "gen_naxes.inc"
#include "gen_toffeffect.inc"

static uint64_t lcg_state = 0x9E3779B97F4A7C15ULL;
static uint32_t rnd32(void)
{
    lcg_state = lcg_state * 6364136223846793005ULL + 1442695040888963407ULL;
    return (uint32_t)(lcg_state >> 33);
}
static uint32_t rn(uint32_t n) { return rnd32() % n; }

static const Sint32 dir_edges[] = { 0, 1, -1, 4500, 9000, 17999, 18000, 18001, 35999, 36000, 36001, -4500, -9000,
                                    -36000, -36001, 100000, -100000, 1999999999, -1999999999, 7, -7, 2000000, -2000000 };
static Sint32 rdir(void)
{
    if (rn(3) == 0) return dir_edges[rn(sizeof(dir_edges) / sizeof(dir_edges[0]))];
    return (Sint32)(rnd32() % 200001) - 100000;
}
static const Uint32 len_edges[] = { 0, 1, 32766, 32767, 32768, 65535, 65536, 100000, 0xFFFFFFFFu };
static Uint32 rlen(void)
{
    if (rn(2) == 0) return len_edges[rn(sizeof(len_edges) / sizeof(len_edges[0]))];
    return rnd32() % 70000;
}
static Uint16 ru16(void)
{
    switch (rn(4)) {
    case 0: return 32767;
    case 1: return 32768;
    case 2: return 65535;
    default: return (Uint16)rnd32();
    }
}
static Sint16 rs16(void)
{
    switch (rn(5)) {
    case 0: return 32767;
    case 1: return -32768;
    case 2: return 0;
    default: return (Sint16)rnd32();
    }
}
static Uint16 rbutton(void) { return (Uint16)(rn(4) == 0 ? rn(30) : rn(5)); }

static void dump_header(SDL_HapticDirection *d, Uint32 *length, Uint16 *delay, Uint16 *button, Uint16 *interval)
{
    d->type = (Uint8)(rn(10) == 0 ? 4 : rn(4));
    d->dir[0] = rdir();
    d->dir[1] = rdir();
    d->dir[2] = rdir();
    *length = rlen();
    *delay = ru16();
    *button = rbutton();
    *interval = ru16();
}
static void print_header(const SDL_HapticDirection *d, Uint32 length, Uint16 delay, Uint16 button, Uint16 interval)
{
    printf(" %d %d %d %d %u %u %u %u", (int)d->type, (int)d->dir[0], (int)d->dir[1], (int)d->dir[2],
           (unsigned)length, (unsigned)delay, (unsigned)button, (unsigned)interval);
}

static void finish(const SDL_HapticEffect *e)
{
    struct ff_effect ff;
    unsigned char *p = (unsigned char *)&ff;
    bool ok;
    size_t i;
    memset(&ff, 0xAB, sizeof(ff));
    ok = SDL_SYS_ToFFEffect(&ff, e);
    printf(" %d ", ok ? 1 : 0);
    if (ok) {
        for (i = 0; i < sizeof(ff); i++) printf("%02x", p[i]);
    } else {
        printf("-");
    }
    printf("\n");
}

static void one_case(Uint16 type)
{
    SDL_HapticEffect e;
    int i;
    memset(&e, 0, sizeof(e));
    e.type = type;
    printf("E %u", (unsigned)type);
    switch (type) {
    case SDL_HAPTIC_CONSTANT: {
        SDL_HapticConstant *c = &e.constant;
        dump_header(&c->direction, &c->length, &c->delay, &c->button, &c->interval);
        c->level = rs16(); c->attack_length = ru16(); c->attack_level = ru16(); c->fade_length = ru16(); c->fade_level = ru16();
        print_header(&c->direction, c->length, c->delay, c->button, c->interval);
        printf(" %d %u %u %u %u", (int)c->level, c->attack_length, c->attack_level, c->fade_length, c->fade_level);
        break;
    }
    case SDL_HAPTIC_SINE: case SDL_HAPTIC_SQUARE: case SDL_HAPTIC_TRIANGLE:
    case SDL_HAPTIC_SAWTOOTHUP: case SDL_HAPTIC_SAWTOOTHDOWN: {
        SDL_HapticPeriodic *p = &e.periodic;
        dump_header(&p->direction, &p->length, &p->delay, &p->button, &p->interval);
        p->period = ru16(); p->magnitude = rs16(); p->offset = rs16(); p->phase = ru16();
        p->attack_length = ru16(); p->attack_level = ru16(); p->fade_length = ru16(); p->fade_level = ru16();
        print_header(&p->direction, p->length, p->delay, p->button, p->interval);
        printf(" %u %d %d %u %u %u %u %u", p->period, (int)p->magnitude, (int)p->offset, p->phase,
               p->attack_length, p->attack_level, p->fade_length, p->fade_level);
        break;
    }
    case SDL_HAPTIC_SPRING: case SDL_HAPTIC_DAMPER: case SDL_HAPTIC_INERTIA: case SDL_HAPTIC_FRICTION: {
        SDL_HapticCondition *c = &e.condition;
        dump_header(&c->direction, &c->length, &c->delay, &c->button, &c->interval);
        for (i = 0; i < 3; i++) c->right_sat[i] = ru16();
        for (i = 0; i < 3; i++) c->left_sat[i] = ru16();
        for (i = 0; i < 3; i++) c->right_coeff[i] = rs16();
        for (i = 0; i < 3; i++) c->left_coeff[i] = rs16();
        for (i = 0; i < 3; i++) c->deadband[i] = ru16();
        for (i = 0; i < 3; i++) c->center[i] = rs16();
        print_header(&c->direction, c->length, c->delay, c->button, c->interval);
        for (i = 0; i < 3; i++) printf(" %u", c->right_sat[i]);
        for (i = 0; i < 3; i++) printf(" %u", c->left_sat[i]);
        for (i = 0; i < 3; i++) printf(" %d", (int)c->right_coeff[i]);
        for (i = 0; i < 3; i++) printf(" %d", (int)c->left_coeff[i]);
        for (i = 0; i < 3; i++) printf(" %u", c->deadband[i]);
        for (i = 0; i < 3; i++) printf(" %d", (int)c->center[i]);
        break;
    }
    case SDL_HAPTIC_RAMP: {
        SDL_HapticRamp *r = &e.ramp;
        dump_header(&r->direction, &r->length, &r->delay, &r->button, &r->interval);
        r->start = rs16(); r->end = rs16();
        r->attack_length = ru16(); r->attack_level = ru16(); r->fade_length = ru16(); r->fade_level = ru16();
        print_header(&r->direction, r->length, r->delay, r->button, r->interval);
        printf(" %d %d %u %u %u %u", (int)r->start, (int)r->end, r->attack_length, r->attack_level, r->fade_length, r->fade_level);
        break;
    }
    case SDL_HAPTIC_LEFTRIGHT: {
        SDL_HapticLeftRight *l = &e.leftright;
        l->length = rlen(); l->large_magnitude = ru16(); l->small_magnitude = ru16();
        printf(" %u %u %u", (unsigned)l->length, l->large_magnitude, l->small_magnitude);
        break;
    }
    default:
        break;
    }
    finish(&e);
}

static void naxes_case(const char *hint, Uint16 vid, Uint16 pid)
{
    const char *s;
    g_hint = hint;
    printf("N ");
    if (!hint[0]) printf("-");
    for (s = hint; *s; s++) printf("%02x", (unsigned char)*s);
    printf(" %u %u %d\n", vid, pid, SDL_Haptic_Get_Naxes(vid, pid));
}

/* 単精度の丸めが効く向き: 2^24 を超える整数は float で偶数に丸まり、atan2f と倍精度の atan2 で、100 分の 1 度の切り捨てが変わる */
static void crafted(void)
{
    static const Sint32 xs[] = { 16777217, 16777216, 16777219, 33554433, 2000000001, 1999999999, 100000001, 1073741825 };
    static const Sint32 ys[] = { 16777216, 16777217, 16777216, 33554432, 1000000064, 1999999931, 100000000, 1073741824 };
    size_t i;
    for (i = 0; i < sizeof(xs) / sizeof(xs[0]); i++) {
        int neg;
        for (neg = 0; neg < 4; neg++) {
            SDL_HapticEffect e;
            SDL_HapticConstant *c = &e.constant;
            memset(&e, 0, sizeof(e));
            c->type = SDL_HAPTIC_CONSTANT;
            c->direction.type = SDL_HAPTIC_CARTESIAN;
            c->direction.dir[0] = (neg & 1) ? -xs[i] : xs[i];
            c->direction.dir[1] = (neg & 2) ? -ys[i] : ys[i];
            c->length = 100;
            c->level = 1;
            printf("E %u", (unsigned)c->type);
            print_header(&c->direction, c->length, c->delay, c->button, c->interval);
            printf(" %d %u %u %u %u", (int)c->level, c->attack_length, c->attack_level, c->fade_length, c->fade_level);
            finish(&e);
        }
    }
}

int main(void)
{
    static const Uint16 types[] = { SDL_HAPTIC_CONSTANT, SDL_HAPTIC_SINE, SDL_HAPTIC_SQUARE, SDL_HAPTIC_TRIANGLE,
        SDL_HAPTIC_SAWTOOTHUP, SDL_HAPTIC_SAWTOOTHDOWN, SDL_HAPTIC_SPRING, SDL_HAPTIC_DAMPER, SDL_HAPTIC_INERTIA,
        SDL_HAPTIC_FRICTION, SDL_HAPTIC_RAMP, SDL_HAPTIC_LEFTRIGHT };
    static const char *hints[] = {
        "", "0x045e/0x028e/2", "0x045e/0x028e/2,0x057e/0x2009/1", "0xffff/0xffff/1,0x045e/0x028e/4",
        "0x045E/0x028E/3", "0x1/0x2/3", "0x0x045e/0x0x028e/5", " 0x045e/0x028e/2", "0x045e / 0x028e / 2",
        "0x045e/0x028e/2,,0x057e/0x2009/1", "0x045e/0x028e/-2", "0x045e/0x028e/70000", "0xfffff/0x1/5",
        "0x/0x/1", "0x045e/0x028e/", "0x045e/0x028e/2,0x045e/0x028e/9", "0x057e/0x2009/1,0xffff/0xffff/7",
        "0x045e/0x028e/2 ,0x057e/0x2009/1", "0x045e/0x028e/ 6", "0x045e/ 0x028e/6", "0x045e/0x028e/0",
        "0xffff/0xffff/0", "junk", "0x045e/0x028e/2,junk", "0x045e/0x028e/2,0x057e/0x2009/1,", "0x045e/0x028e/08",
        "0x045e/0x028e/0x5", "0X045e/0x028e/2", "0x045e/0x028e/2147483647", "0x045e/0x028e/65536", "0x-1/0x1/3", "0x10000000000000000/0x10000000000000000/3", "0xffff/0xffff/18446744073709551616", "0xffff/0xffff/18446744073709551617", "0xffff/0xffff/18446744073709551615", "0x1ffffffffffffffff/0xffff/4",  "0x-1/0x-1/3", "0x+ffff/0x+ffff/4", "0x0xffff/0x0Xffff/5", "0xFFFF/0xFfFf/6", "0x 0xffff/0x 0xffff/8", "0x-0x1/0x1/2", "0x0x/0x0x/2",  "0x+45e/0x28e/2", "0xffffffffffffffffff/0xffff/3", "0xffff/0xfffffffffffffffffff/3", "0x045e/0x028e/99999999999999999999999", "0x045e/0x028e/+7", "0x045e/0X028E/7", "0x 45e/0x28e/3", "0x045e/0x028e/2\n,0x057e/0x2009/1", "0x045e/0x028e/ -3", 
        "0xffff/0xffff/3,0xffff/0xffff/4", "0x045e/0x028e/1,0x045e/0x028e/2,0xffff/0xffff/5",
        "0x1/0x2/3,0x4/0x5/6,0x7/0x8/9,0xa/0xb/10,0xc/0xd/11,0xe/0xf/12,0x10/0x11/13,0x12/0x13/14,0x14/0x15/15,0x045e/0x028e/2",
        NULL };
    size_t i;
    int n;
    for (n = 0; n < 700; n++) {
        one_case(types[n % (sizeof(types) / sizeof(types[0]))]);
    }
    crafted();
    one_case(SDL_HAPTIC_CUSTOM);
    one_case(0x4000);
    one_case(0);
    for (i = 0; hints[i]; i++) {
        naxes_case(hints[i], 0x045e, 0x028e);
        naxes_case(hints[i], 0x057e, 0x2009);
        naxes_case(hints[i], 0x1234, 0x5678);
    }
    return 0;
}
