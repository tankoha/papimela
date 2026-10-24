/* メッセージボックスの zenity のバックエンド（SDL_Zenity_ShowMessageBox）を、参照版の SDL に通して書き出す。
   zenity は test/fake-zenity/zenity（偽物。引数を記録し、決めた出力と終了コードを返す）で、PATH の先頭に置く。
   papimela の test_messagebox が同じ場面を PMLShowMessageBox に通して突き合わせる。
   tools/messagebox-expect/gen.bb が作って test/messagebox_expected.inc に書く。
   使い方: mb_cases <偽の zenity のフォルダ> <記録のファイル>
   出力は 1 行ずつ「L 文面」。場面の始めに「C <名前>」、zenity に渡った引数は「A <番号> <値>」（改行は \n）、
   結果は「R <True/False> id=<押されたボタンの ID>」。入力は F（フラグ）T（題）M（本文）B（ボタンの ID と文字）V（zenity の版）O（出力）X（終了コード）。 */
#include <SDL3/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern bool SDL_Zenity_ShowMessageBox(const SDL_MessageBoxData *messageboxdata, int *buttonID);

typedef struct {
  const char *name;
  SDL_MessageBoxFlags flags;
  const char *title, *message;
  int nb;
  SDL_MessageBoxButtonData b[10];
  const char *version, *output, *exitcode;
} Case;

/* 子プロセスに渡る環境は SDL が起動時に写した SDL_GetEnvironment() のもの。setenv では変わらない */
static void setv(const char *name, const char *value) { SDL_SetEnvironmentVariable(SDL_GetEnvironment(), name, value, true); }

#define B(f, id, t) { f, id, t }
#define R SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT
#define E SDL_MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT

static const Case cases[] = {
  { "simple", SDL_MESSAGEBOX_ERROR, "Title", "Message", 1, { B(R | E, 7, "OK") }, "3.44.0", "OK\n", "1" },
  { "warning two", SDL_MESSAGEBOX_WARNING, "Careful", "Sure?", 2, { B(R, 1, "Yes"), B(E, 2, "No") }, "3.44.0", "No\n", "1" },
  { "information three", SDL_MESSAGEBOX_INFORMATION, "Info", "Pick", 3, { B(0, 10, "A"), B(0, 20, "B"), B(0, 30, "C") }, "3.44.0", "C\n", "1" },
  { "no kind", 0, "T", "M", 1, { B(0, 1, "OK") }, "3.44.0", "OK\n", "0" },
  { "error and warning", SDL_MESSAGEBOX_ERROR | SDL_MESSAGEBOX_WARNING, "T", "M", 1, { B(0, 1, "OK") }, "3.44.0", "OK\n", "1" },
  { "left to right only", SDL_MESSAGEBOX_BUTTONS_LEFT_TO_RIGHT, "T", "M", 1, { B(0, 1, "OK") }, "3.44.0", "OK\n", "1" },
  { "error with ltr", SDL_MESSAGEBOX_ERROR | SDL_MESSAGEBOX_BUTTONS_RIGHT_TO_LEFT, "T", "M", 1, { B(0, 1, "OK") }, "3.44.0", "OK\n", "1" },
  { "no buttons", SDL_MESSAGEBOX_INFORMATION, "T", "M", 0, { B(0, 0, NULL) }, "3.44.0", "OK\n", "1" },
  { "empty title and message", SDL_MESSAGEBOX_INFORMATION, "", "", 1, { B(0, 1, "OK") }, "3.44.0", "OK\n", "1" },
  { "empty title", SDL_MESSAGEBOX_INFORMATION, "", "Only message", 1, { B(0, 1, "OK") }, "3.44.0", "OK\n", "1" },
  { "empty message", SDL_MESSAGEBOX_INFORMATION, "Only title", "", 1, { B(0, 1, "OK") }, "3.44.0", "OK\n", "1" },
  { "empty button text", SDL_MESSAGEBOX_INFORMATION, "T", "M", 3, { B(0, 1, "A"), B(0, 2, ""), B(0, 3, "C") }, "3.44.0", "C\n", "1" },
  { "null button text", SDL_MESSAGEBOX_INFORMATION, "T", "M", 2, { B(0, 1, NULL), B(0, 2, "B") }, "3.44.0", "B\n", "1" },
  { "eight buttons", SDL_MESSAGEBOX_INFORMATION, "T", "M", 8, { B(0, 1, "1"), B(0, 2, "2"), B(0, 3, "3"), B(0, 4, "4"), B(0, 5, "5"), B(0, 6, "6"), B(0, 7, "7"), B(0, 8, "8") }, "3.44.0", "8\n", "1" },
  { "nine buttons", SDL_MESSAGEBOX_INFORMATION, "T", "M", 9, { B(0, 1, "1"), B(0, 2, "2"), B(0, 3, "3"), B(0, 4, "4"), B(0, 5, "5"), B(0, 6, "6"), B(0, 7, "7"), B(0, 8, "8"), B(0, 9, "9") }, "3.44.0", "9\n", "1" },
  { "version 3.90", SDL_MESSAGEBOX_ERROR, "T", "M", 1, { B(0, 1, "OK") }, "3.90.0", "OK\n", "1" },
  { "version 3.89.9", SDL_MESSAGEBOX_ERROR, "T", "M", 1, { B(0, 1, "OK") }, "3.89.9", "OK\n", "1" },
  { "version 4.0", SDL_MESSAGEBOX_ERROR, "T", "M", 1, { B(0, 1, "OK") }, "4.0.1", "OK\n", "1" },
  { "version 4", SDL_MESSAGEBOX_ERROR, "T", "M", 1, { B(0, 1, "OK") }, "4", "OK\n", "1" },
  { "version 3", SDL_MESSAGEBOX_ERROR, "T", "M", 1, { B(0, 1, "OK") }, "3", "OK\n", "1" },
  { "version 3.x", SDL_MESSAGEBOX_ERROR, "T", "M", 1, { B(0, 1, "OK") }, "3.x", "OK\n", "1" },
  { "version 3.", SDL_MESSAGEBOX_ERROR, "T", "M", 1, { B(0, 1, "OK") }, "3.", "OK\n", "1" },
  { "version abc", SDL_MESSAGEBOX_ERROR, "T", "M", 1, { B(0, 1, "OK") }, "abc", "OK\n", "1" },
  { "version empty", SDL_MESSAGEBOX_ERROR, "T", "M", 1, { B(0, 1, "OK") }, "", "OK\n", "1" },
  { "version 0.5", SDL_MESSAGEBOX_ERROR, "T", "M", 1, { B(0, 1, "OK") }, "0.5.0", "OK\n", "1" },
  { "version spaces", SDL_MESSAGEBOX_ERROR, "T", "M", 1, { B(0, 1, "OK") }, "  3.91.2 (extra)", "OK\n", "1" },
  { "special text", SDL_MESSAGEBOX_INFORMATION, "T \"quoted\" 'x'", "line1\nline2 --foo $HOME `x` %s \\n", 1, { B(0, 1, "Ok & <b>") }, "3.44.0", "Ok & <b>\n", "1" },
  { "unicode", SDL_MESSAGEBOX_INFORMATION, "ゲーム", "メッセージ ß 😀", 2, { B(0, 1, "はい"), B(0, 2, "いいえ") }, "3.44.0", "いいえ\n", "1" },
  { "dash message", SDL_MESSAGEBOX_INFORMATION, "--title", "--text", 1, { B(0, 1, "--extra-button") }, "3.44.0", "--extra-button\n", "1" },
  { "output no match", SDL_MESSAGEBOX_INFORMATION, "T", "M", 2, { B(0, 1, "A"), B(0, 2, "B") }, "3.44.0", "Z\n", "1" },
  { "output empty", SDL_MESSAGEBOX_INFORMATION, "T", "M", 2, { B(0, 1, "A"), B(0, 2, "B") }, "3.44.0", "", "1" },
  { "output no newline", SDL_MESSAGEBOX_INFORMATION, "T", "M", 2, { B(0, 1, "A"), B(0, 2, "B") }, "3.44.0", "B", "1" },
  { "output two newlines", SDL_MESSAGEBOX_INFORMATION, "T", "M", 2, { B(0, 1, "A"), B(0, 2, "B") }, "3.44.0", "B\n\n", "1" },
  { "output two lines", SDL_MESSAGEBOX_INFORMATION, "T", "M", 2, { B(0, 1, "A"), B(0, 2, "B") }, "3.44.0", "A\nB\n", "1" },
  { "duplicate button text", SDL_MESSAGEBOX_INFORMATION, "T", "M", 3, { B(0, 11, "A"), B(0, 22, "A"), B(0, 33, "B") }, "3.44.0", "A\n", "1" },
  { "case differs", SDL_MESSAGEBOX_INFORMATION, "T", "M", 1, { B(0, 1, "Yes") }, "3.44.0", "yes\n", "1" },
  { "closed 255", SDL_MESSAGEBOX_INFORMATION, "T", "M", 2, { B(0, 1, "A"), B(0, 2, "B") }, "3.44.0", "", "255" },
  { "closed 255 with output", SDL_MESSAGEBOX_INFORMATION, "T", "M", 2, { B(0, 1, "A"), B(0, 2, "B") }, "3.44.0", "B\n", "255" },
  { "exit 0", SDL_MESSAGEBOX_INFORMATION, "T", "M", 2, { B(0, 1, "A"), B(0, 2, "B") }, "3.44.0", "A\n", "0" },
  { "exit 2", SDL_MESSAGEBOX_INFORMATION, "T", "M", 2, { B(0, 1, "A"), B(0, 2, "B") }, "3.44.0", "A\n", "2" },
  { "exit 254", SDL_MESSAGEBOX_INFORMATION, "T", "M", 2, { B(0, 1, "A"), B(0, 2, "B") }, "3.44.0", "B\n", "254" },
};

static void esc(const unsigned char *s, size_t n)
{
  size_t i;
  for (i = 0; i < n; i++) {
    if (s[i] == '\n') printf("\\n");
    else if (s[i] == '\\') printf("\\\\");
    else putchar(s[i]);
  }
}

int main(int argc, char **argv)
{
  const char *fakedir, *logfile;
  char path[4096];
  size_t i;
  if (argc < 3) { fprintf(stderr, "usage\n"); return 2; }
  fakedir = argv[1]; logfile = argv[2];
  snprintf(path, sizeof(path), "%s:%s", fakedir, getenv("PATH") ? getenv("PATH") : "/usr/bin:/bin");
  setenv("PATH", path, 1);      /* 実行ファイルの探索は libc の PATH */
  setv("PATH", path);
  setv("FAKE_ZENITY_LOG", logfile);
  for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
    const Case *c = &cases[i];
    SDL_MessageBoxData d;
    int id = -1, k;
    bool r;
    FILE *f;
    memset(&d, 0, sizeof(d));
    d.flags = c->flags; d.title = c->title; d.message = c->message; d.numbuttons = c->nb; d.buttons = c->b;
    setv("FAKE_ZENITY_VERSION", c->version);
    setv("FAKE_ZENITY_OUTPUT", c->output);
    setv("FAKE_ZENITY_EXIT", c->exitcode);
    remove(logfile);
    printf("L C %s\n", c->name);
    /* 入力（papimela の検査が読んで、同じ場面を作る） */
    printf("L F %u\n", (unsigned)c->flags);
    printf("L T "); esc((const unsigned char *)c->title, strlen(c->title)); printf("\n");
    printf("L M "); esc((const unsigned char *)c->message, strlen(c->message)); printf("\n");
    for (k = 0; k < c->nb; k++) {
      const char *t = c->b[k].text ? c->b[k].text : "";
      printf("L B %d ", c->b[k].buttonID); esc((const unsigned char *)t, strlen(t)); printf("\n");
    }
    printf("L V %s\n", c->version);
    printf("L O "); esc((const unsigned char *)c->output, strlen(c->output)); printf("\n");
    printf("L X %s\n", c->exitcode);
    r = SDL_Zenity_ShowMessageBox(&d, &id);
    f = fopen(logfile, "rb");
    if (!f) printf("L A (none)\n");
    else {
      unsigned char buf[8192]; size_t n = fread(buf, 1, sizeof(buf), f), start = 0, j; int idx = 0;
      fclose(f);
      for (j = 0; j < n; j++) if (buf[j] == 0) { printf("L A %d ", idx++); esc(buf + start, j - start); printf("\n"); start = j + 1; }
    }
    printf("L R %s id=%d\n", r ? "True" : "False", id);
  }
  return 0;
}
