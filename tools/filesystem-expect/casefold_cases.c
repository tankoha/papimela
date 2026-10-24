/* 大文字小文字の畳み込み SDL_CaseFoldUnicode と、UTF-8 の読み進め SDL_StepUTF8 を、参照版の SDL に通して書き出す。
   papimela の test_filesystem が同じ入力を PMLCaseFoldCodepoint / PMLStepUTF8 に通して突き合わせる。
   tools/filesystem-expect/gen.bb が作って test/casefold_expected.inc に書く。
   出力は 1 行ずつ「L 文面」。
     F <cp> <n> <to0> <to1> <to2>   畳み込みのあるコードポイントだけ（16 進）。最後に「F-count <n>」
     U <入力のバイト 16 進> = <読んだコードポイントの並び 16 進>   StepUTF8 を終わりまで
     UB ...                                                         SDL の不具合（D-82）で papimela と違う行。比べない */
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>

extern int SDL_CaseFoldUnicode(Uint32 from, Uint32 *to);

static void steps(const char *tag, const unsigned char *bytes, size_t n)
{
  char buf[256];
  const char *p;
  size_t slen = n;
  size_t i;
  printf("L %s ", tag);
  for (i = 0; i < n; i++) printf("%02x", bytes[i]);
  printf(" =");
  memcpy(buf, bytes, n);
  buf[n] = 0;
  p = buf;
  for (;;) {
    Uint32 cp = SDL_StepUTF8(&p, &slen);
    if (cp == 0) break;
    printf(" %x", cp);
  }
  printf("\n");
}

int main(void)
{
  Uint32 cp;
  int count = 0;
  for (cp = 0; cp <= 0x10FFFF; cp++) {
    Uint32 to[3] = {0, 0, 0};
    int n = SDL_CaseFoldUnicode(cp, to);
    if (n != 1 || to[0] != cp) {
      if (n < 3) { if (n < 2) to[1] = 0; to[2] = 0; }
      printf("L F %x %d %x %x %x\n", cp, n, to[0], n > 1 ? to[1] : 0, n > 2 ? to[2] : 0);
      count++;
    }
  }
  printf("L F-count %d\n", count);
  {
    static const unsigned char c1[] = "abc";
    static const unsigned char c2[] = { 0xC3, 0xA4, 'x' };            /* ä x */
    static const unsigned char c3[] = { 0xE3, 0x81, 0x82 };           /* あ */
    static const unsigned char c4[] = { 0xF0, 0x9F, 0x98, 0x80 };     /* U+1F600 */
    static const unsigned char c5[] = { 0xF0, 0x90, 0x90, 0x80 };     /* U+10400 */
    static const unsigned char c6[] = { 0xC0, 0x80 };                 /* 冗長 */
    static const unsigned char c7[] = { 0xC3 };                       /* 切れた */
    static const unsigned char c8[] = { 0xE3, 0x81 };                 /* 切れた */
    static const unsigned char c9[] = { 0xED, 0xA0, 0x80 };           /* サロゲート */
    static const unsigned char c10[] = { 0x80, 'a' };                 /* 継続バイトだけ */
    static const unsigned char c11[] = { 0xFF, 'a', 0xFE };
    static const unsigned char c12[] = { 0xE0, 0x80, 0x80 };          /* 冗長 */
    static const unsigned char c13[] = { 0xF0, 0x80, 0x80, 0x80 };    /* 冗長 */
    static const unsigned char c14[] = { 0xC3, 'a' };                 /* 継続が違う */
    static const unsigned char c15[] = { 0xF4, 0x8F, 0xBF, 0xBF };    /* U+10FFFF */
    static const unsigned char c16[] = { 0xF4, 0x90, 0x80, 0x80 };    /* U+110000（範囲外） */
    static const unsigned char c17[] = { 0xEF, 0xBF, 0xBD };          /* U+FFFD */
    static const unsigned char c18[] = { 0xF0, 0xA0, 0x80, 0x80 };    /* U+20000: SDL は不具合で U+FFFD（D-82） */
    static const unsigned char c19[] = { 0xF0, 0xAA, 0x9B, 0x96 };    /* U+2A6D6 */
    static const unsigned char c20[] = { 0xF3, 0xA0, 0x80, 0x80 };    /* U+E0000 */
    steps("U", c1, sizeof(c1) - 1);
    steps("U", c2, sizeof(c2)); steps("U", c3, sizeof(c3)); steps("U", c4, sizeof(c4)); steps("U", c5, sizeof(c5));
    steps("U", c6, sizeof(c6)); steps("U", c7, sizeof(c7)); steps("U", c8, sizeof(c8)); steps("U", c9, sizeof(c9));
    steps("U", c10, sizeof(c10)); steps("U", c11, sizeof(c11)); steps("U", c12, sizeof(c12)); steps("U", c13, sizeof(c13));
    steps("U", c14, sizeof(c14)); steps("U", c15, sizeof(c15)); steps("U", c16, sizeof(c16)); steps("U", c17, sizeof(c17));
    steps("UB", c18, sizeof(c18)); steps("UB", c19, sizeof(c19)); steps("UB", c20, sizeof(c20));
  }
  return 0;
}
