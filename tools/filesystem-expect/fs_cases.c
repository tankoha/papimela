/* ファイルシステム（SDL_filesystem.c と unix / posix の部分）を、参照版の SDL に通して書き出す。
   papimela の test_filesystem が同じ操作を TPMLFileSystem に行って突き合わせる。
   tools/filesystem-expect/gen.bb が作って test/filesystem_expected.inc に書く。

   使い方:  fs_cases ops <作業のフォルダ>        フォルダの操作（木を作って、Glob・列挙・作る・消す・写す・情報）
            fs_cases envcount                    環境変数の場面の数
            fs_cases env <番号> <作業のフォルダ>  環境変数の場面 1 つ（ユーザーのフォルダと設定のフォルダ）
   SDL は基準のパスなどを覚えるので、環境の場面はプロセスを分けて 1 つずつ動かす。
   出力は 1 行ずつ「L 文面」。作業のフォルダの絶対パスは <T> に書き直す（機械ごとに違うため）。 */
#include <SDL3/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <sys/stat.h>

static char Base[1024];

static void L(const char *fmt, ...)
{
  char buf[4096];
  va_list ap;
  char *p;
  printf("L ");
  va_start(ap, fmt); vsnprintf(buf, sizeof(buf), fmt, ap); va_end(ap);
  /* 作業のフォルダを <T> に */
  p = buf;
  for (;;) {
    char *q = strstr(p, Base);
    if (!q || !*Base) { fputs(p, stdout); break; }
    fwrite(p, 1, q - p, stdout);
    fputs("<T>", stdout);
    p = q + strlen(Base);
  }
  printf("\n");
}

static void mkd(const char *rel)
{
  char p[2048]; snprintf(p, sizeof(p), "%s/%s", Base, rel); mkdir(p, 0777);
}
static void mkf(const char *rel, const char *content)
{
  char p[2048]; FILE *f; snprintf(p, sizeof(p), "%s/%s", Base, rel);
  f = fopen(p, "wb"); if (f) { fputs(content, f); fclose(f); }
}
static void mkl(const char *target, const char *rel)
{
  char p[2048]; snprintf(p, sizeof(p), "%s/%s", Base, rel); symlink(target, p);
}

static int cmp(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }

static void glob_case(const char *relbase, const char *pattern, SDL_GlobFlags flags)
{
  char path[2048];
  int count = -1, i;
  char **r;
  snprintf(path, sizeof(path), "%s%s%s", Base, relbase[0] ? "/" : "", relbase);
  r = SDL_GlobDirectory(path, pattern, flags, &count);
  if (!r) { L("G %s | %s | %d -> NULL (count %d)", relbase, pattern ? pattern : "(null)", (int)flags, count); return; }
  qsort(r, count, sizeof(char *), cmp);
  {
    char line[3500] = "";
    for (i = 0; i < count; i++) { strcat(line, r[i]); strcat(line, ";"); }
    L("G %s | %s | %d -> %d: %s", relbase, pattern ? pattern : "(null)", (int)flags, count, line);
  }
  SDL_free(r);
}

static const char *ptype(SDL_PathType t) { return t == SDL_PATHTYPE_FILE ? "file" : t == SDL_PATHTYPE_DIRECTORY ? "dir" : t == SDL_PATHTYPE_OTHER ? "other" : "none"; }

static void info_case(const char *rel)
{
  char path[2048]; SDL_PathInfo info;
  snprintf(path, sizeof(path), "%s/%s", Base, rel);
  if (SDL_GetPathInfo(path, &info))
    L("I %s -> %s size=%llu times=%d", rel, ptype(info.type), (unsigned long long)info.size,
      (int)(info.create_time > 0 && info.modify_time > 0 && info.access_time > 0));
  else
    L("I %s -> fail", rel);
}

typedef struct { char dirs[2048]; char names[64][128]; int n; int stop_after; int fail_after; } EnumData;
static SDL_EnumerationResult SDLCALL enum_cb(void *ud, const char *dirname, const char *fname)
{
  EnumData *d = (EnumData *)ud;
  if (d->n == 0) snprintf(d->dirs, sizeof(d->dirs), "%s", dirname);
  snprintf(d->names[d->n++], 128, "%s", fname);
  if (d->stop_after && d->n >= d->stop_after) return SDL_ENUM_SUCCESS;
  if (d->fail_after && d->n >= d->fail_after) return SDL_ENUM_FAILURE;
  return SDL_ENUM_CONTINUE;
}
static void enum_case(const char *rel, int stop_after, int fail_after)
{
  char path[2048]; EnumData d; char *names[64]; int i; bool r;
  memset(&d, 0, sizeof(d)); d.stop_after = stop_after; d.fail_after = fail_after;
  snprintf(path, sizeof(path), "%s%s", Base, rel);
  r = SDL_EnumerateDirectory(path, enum_cb, &d);
  for (i = 0; i < d.n; i++) names[i] = d.names[i];
  qsort(names, d.n, sizeof(char *), cmp);
  {
    char line[3000] = "";
    for (i = 0; i < d.n; i++) { strcat(line, names[i]); strcat(line, ";"); }
    if (stop_after || fail_after) L("E %s stop=%d fail=%d -> %d, n=%d dir=%s", rel, stop_after, fail_after, (int)r, d.n, d.n ? d.dirs : "-");
    else L("E %s -> %d, n=%d dir=%s names=%s", rel, (int)r, d.n, d.n ? d.dirs : "-", line);
  }
}

static void ops(void)
{
  char a[2048], b[2048];
  /* 木 */
  mkd("a"); mkd("a/c"); mkd("empty"); mkd("sub dir"); mkd("ß"); mkd("Dir");
  mkf("a/b.txt", "hello"); mkf("a/B.TXT", "HELLO!"); mkf("a/c/d.txt", "d"); mkf("a/c/E.md", "# e");
  mkf("ß/ss.txt", "s"); mkf("Äpfel.txt", "a"); mkf("äpfel.TXT", "b"); mkf("x.y", "xy"); mkf(".hidden", "h");
  mkf("sub dir/f", "f"); mkf("Dir/File.TXT", "F"); mkf("Dir/file.txt", "f");
  mkl("a/b.txt", "flink");

  /* Glob */
  glob_case("", NULL, 0);
  glob_case("", "*", 0);
  glob_case("", "*/", 0);
  glob_case("", "*.txt", 0);
  glob_case("", "*.txt", SDL_GLOB_CASEINSENSITIVE);
  glob_case("", "*.TXT", 0);
  glob_case("", "a/*", 0);
  glob_case("", "a/*/*", 0);
  glob_case("", "a/*.TXT", SDL_GLOB_CASEINSENSITIVE);
  glob_case("", "?", 0);
  glob_case("", "??", 0);
  glob_case("", "x.?", 0);
  glob_case("", "a?b.txt", 0);
  glob_case("", "a/?.txt", 0);
  glob_case("", "*/d.txt", 0);
  glob_case("", "*/*/d.txt", 0);
  glob_case("", "**", 0);
  glob_case("", "a/**", 0);
  glob_case("", ".*", 0);
  glob_case("", "*d.txt", 0);
  glob_case("", "*.md", 0);
  glob_case("", "", 0);
  glob_case("", "a", 0);
  glob_case("", "a/", 0);
  glob_case("", "a/c", 0);
  glob_case("", "[ab]", 0);
  glob_case("", "sub*", 0);
  glob_case("", "sub?dir/*", 0);
  glob_case("", "ÄPFEL.TXT", SDL_GLOB_CASEINSENSITIVE);
  glob_case("", "ÄPFEL.TXT", 0);
  glob_case("", "ä*", SDL_GLOB_CASEINSENSITIVE);
  glob_case("", "SS/SS.TXT", SDL_GLOB_CASEINSENSITIVE);
  glob_case("", "ß/*", 0);
  glob_case("", "ß/*", SDL_GLOB_CASEINSENSITIVE);
  glob_case("", "dir/file.txt", SDL_GLOB_CASEINSENSITIVE);
  glob_case("", "DIR/*", SDL_GLOB_CASEINSENSITIVE);
  glob_case("", "DIR/*", 0);
  glob_case("", "*", SDL_GLOB_CASEINSENSITIVE);
  glob_case("", NULL, SDL_GLOB_CASEINSENSITIVE);
  glob_case("a", NULL, 0);
  glob_case("a", "*", 0);
  glob_case("a", "c/*", 0);
  glob_case("a", "*.txt", SDL_GLOB_CASEINSENSITIVE);
  glob_case("a/", "*", 0);
  glob_case("a//", "*", 0);
  glob_case("a/c", "*", 0);
  glob_case("missing", "*", 0);
  glob_case("x.y", "*", 0);
  glob_case("empty", NULL, 0);
  glob_case("flink", NULL, 0);

  /* 列挙 */
  enum_case("", 0, 0);
  enum_case("/a", 0, 0);
  enum_case("/a/", 0, 0);
  enum_case("/a//", 0, 0);
  enum_case("/a/c", 0, 0);
  enum_case("/empty", 0, 0);
  enum_case("/a", 1, 0);
  enum_case("/a", 0, 1);
  enum_case("/a", 0, 99);
  enum_case("/missing", 0, 0);
  enum_case("/x.y", 0, 0);
  enum_case("/sub dir", 0, 0);

  /* 情報 */
  info_case("a"); info_case("a/b.txt"); info_case("x.y"); info_case("flink"); info_case("empty"); info_case("missing");
  info_case("a/"); info_case("a/b.txt/");

  /* 作る */
#define CD(rel) do { snprintf(a, sizeof(a), "%s/%s", Base, rel); L("CD %s -> %d", rel, (int)SDL_CreateDirectory(a)); } while (0)
  CD("n1/n2/n3");
  CD("n1/n2/n3");
  CD("t1/t2/");
  CD("t1/t2//");
  CD("a");
  CD("x.y");
  CD("x.y/z");
  CD("a/b.txt/q");
  CD("p/q/r/s/t/u");
  info_case("n1/n2/n3"); info_case("t1/t2"); info_case("p/q/r/s/t/u");
  L("CD empty -> %d", (int)SDL_CreateDirectory(""));
  L("CD slash -> %d", (int)SDL_CreateDirectory("/"));

  /* 消す */
#define RM(rel) do { snprintf(a, sizeof(a), "%s/%s", Base, rel); L("RM %s -> %d", rel, (int)SDL_RemovePath(a)); } while (0)
  RM("x.y");
  RM("x.y");
  RM("empty");
  RM("a");
  RM("n1/n2/n3");
  RM("missing/deep");
  RM("flink");
  info_case("a/b.txt"); info_case("x.y"); info_case("empty"); info_case("n1/n2");

  /* 名前を変える */
#define RN(o, n) do { snprintf(a, sizeof(a), "%s/%s", Base, o); snprintf(b, sizeof(b), "%s/%s", Base, n); L("RN %s %s -> %d", o, n, (int)SDL_RenamePath(a, b)); } while (0)
  RN("a/B.TXT", "a/renamed.txt");
  RN("missing", "gone");
  RN("a/c", "a/c2");
  RN("a/b.txt", "a/c2/d.txt");
  RN("Dir", "a/c2/Dir");
  info_case("a/renamed.txt"); info_case("a/B.TXT"); info_case("a/c2/d.txt"); info_case("a/c2/Dir/File.TXT");

  /* 写す */
#define CP(o, n) do { snprintf(a, sizeof(a), "%s/%s", Base, o); snprintf(b, sizeof(b), "%s/%s", Base, n); L("CP %s %s -> %d", o, n, (int)SDL_CopyFile(a, b)); } while (0)
  CP("a/c2/d.txt", "copy1.txt");
  CP("a/c2/d.txt", "copy1.txt");
  CP("a/renamed.txt", "copy1.txt");
  CP("missing", "copy2.txt");
  CP("a/c2/d.txt", "missing/dir/copy3.txt");
  CP("a", "copy4");
  CP("empty_none", "copy5");
  info_case("copy1.txt"); info_case("copy2.txt");
  {
    /* 大きなファイル（4096 を跨ぐ） */
    FILE *f; char *big = malloc(20000); int i; for (i = 0; i < 20000; i++) big[i] = (char)('A' + i % 26);
    snprintf(a, sizeof(a), "%s/big.bin", Base); f = fopen(a, "wb"); fwrite(big, 1, 20000, f); fclose(f); free(big);
    CP("big.bin", "big2.bin");
    info_case("big2.bin");
  }

  /* 今のフォルダ */
  if (chdir(Base) == 0) {
    char *cwd = SDL_GetCurrentDirectory();
    L("CWD %s", cwd ? cwd : "(null)");
    SDL_free(cwd);
  }
}

typedef struct { const char *name; const char *home; const char *xdg_data; const char *xdg_config; const char *dirs; } EnvCase;
/* ファイルの本体の中の @H はホーム。@T は作業のフォルダ */
static const char *std_dirs =
  "# comment\n"
  "XDG_DESKTOP_DIR=\"$HOME/Desktop\"\n"
  "XDG_DOWNLOAD_DIR=\"$HOME/Downloads\"\n"
  "XDG_TEMPLATES_DIR=\"$HOME/Templates\"\n"
  "XDG_PUBLICSHARE_DIR=\"$HOME/Public\"\n"
  "XDG_DOCUMENTS_DIR=\"$HOME/Documents\"\n"
  "XDG_MUSIC_DIR=\"$HOME/Music\"\n"
  "XDG_PICTURES_DIR=\"$HOME/Pictures\"\n"
  "XDG_VIDEOS_DIR=\"$HOME/Videos\"\n";
static const char *odd_dirs =
  "  \tXDG_DESKTOP_DIR  =  \"/abs/desk top\"\n"            /* 前後の空白、絶対パス */
  "XDG_DOWNLOAD_DIR=\"$HOME/Down\\\"loads\"\n"             /* 引用符のエスケープ */
  "XDG_MUSIC_DIR=\"relative/music\"\n"                    /* $HOME でも / でもない: 飛ばす */
  "XDG_PICTURES_DIR=$HOME/NoQuotes\n"                     /* 引用符なし: 飛ばす */
  "XDG_VIDEOS_DIR=\"$HOME/First\"\n"
  "XDG_VIDEOS_DIR=\"$HOME/Last\"\n"                       /* 最後のものが勝つ */
  "XDG_DOCUMENTS_DIR=\"$HOME/Docs\" trailing\n"           /* 閉じた引用符の後ろは捨てる */
  "XDG_TEMPLATES_DIR=\"$HOME/Tmpl\\\\x\"\n"               /* バックスラッシュ */
  "XDG_PUBLICSHARE_DIR_EXTRA=\"$HOME/Nope\"\n"            /* _DIR の直後でない */
  "XDG_DESKTOPX_DIR=\"$HOME/Nope\"\n"
  "XDG_MUSIC_DIR=\"/bad";                                 /* 閉じていない。最後の行は改行なし */
static char long_dirs[2000];

static EnvCase envcases[] = {
  { "std", "@T/home", NULL, NULL, NULL },                 /* dirs は後で入れる（下）*/
  { "std-xdgdata", "@T/home", "@T/data", NULL, NULL },
  { "std-xdgdata-slash", "@T/home", "@T/data/", NULL, NULL },
  { "std-xdgconfig", "@T/home", NULL, "@T/cfg", NULL },
  { "std-home-slash", "@T/home/", NULL, NULL, NULL },
  { "nofile", "@T/home", NULL, NULL, NULL },
  { "odd", "@T/home", NULL, NULL, NULL },
  { "long", "@T/home", NULL, NULL, NULL },
  { "nohome", NULL, NULL, NULL, NULL },
  { "nohome-xdgdata", NULL, "@T/data", NULL, NULL },
  { "emptyhome", "", NULL, NULL, NULL },
  { "emptyconfig", "@T/home", NULL, "", NULL },
};
#define NENV ((int)(sizeof(envcases) / sizeof(envcases[0])))

static void subst(char *out, size_t n, const char *in)
{
  /* @T → Base */
  out[0] = 0;
  while (*in) {
    if (in[0] == '@' && in[1] == 'T') { strncat(out, Base, n - strlen(out) - 1); in += 2; }
    else { size_t l = strlen(out); if (l + 1 < n) { out[l] = *in; out[l + 1] = 0; } in++; }
  }
}

static void envscene(int idx)
{
  EnvCase *c = &envcases[idx];
  char home[2048], data[2048], cfg[2048], file[2048];
  const char *dirs = NULL;
  int i;
  static const char *prefs[][2] = { {"Org", "App"}, {"", "App2"}, {"My Org", "My App 3"}, {"o/rg", "a/pp"} };
  static const SDL_Folder folders[] = { SDL_FOLDER_HOME, SDL_FOLDER_DESKTOP, SDL_FOLDER_DOCUMENTS, SDL_FOLDER_DOWNLOADS, SDL_FOLDER_MUSIC,
    SDL_FOLDER_PICTURES, SDL_FOLDER_PUBLICSHARE, SDL_FOLDER_SAVEDGAMES, SDL_FOLDER_SCREENSHOTS, SDL_FOLDER_TEMPLATES, SDL_FOLDER_VIDEOS };
  static const char *fnames[] = { "home", "desktop", "documents", "downloads", "music", "pictures", "publicshare", "savedgames", "screenshots", "templates", "videos" };

  memset(long_dirs, 0, sizeof(long_dirs));
  { /* 511 文字を越える行（fgets の分割）の後に普通の行 */
    int k; strcpy(long_dirs, "XDG_DESKTOP_DIR=\"$HOME/");
    for (k = 0; k < 600; k++) strcat(long_dirs, "x");
    strcat(long_dirs, "\"\nXDG_MUSIC_DIR=\"$HOME/AfterLong\"\n");
  }
  if (!strcmp(c->name, "nofile") || !strcmp(c->name, "emptyhome") || !strcmp(c->name, "nohome") || !strcmp(c->name, "nohome-xdgdata") || !strcmp(c->name, "emptyconfig")) dirs = NULL;
  else if (!strcmp(c->name, "odd")) dirs = odd_dirs;
  else if (!strcmp(c->name, "long")) dirs = long_dirs;
  else dirs = std_dirs;

  if (c->home) { subst(home, sizeof(home), c->home); setenv("HOME", home, 1); } else unsetenv("HOME");
  if (c->xdg_data) { subst(data, sizeof(data), c->xdg_data); setenv("XDG_DATA_HOME", data, 1); } else unsetenv("XDG_DATA_HOME");
  if (c->xdg_config) { subst(cfg, sizeof(cfg), c->xdg_config); setenv("XDG_CONFIG_HOME", cfg, 1); } else unsetenv("XDG_CONFIG_HOME");

  mkd("home"); mkd("data"); mkd("cfg"); mkd(".cfgdummy");
  if (dirs) {
    /* 設定ファイルの置き場所: XDG_CONFIG_HOME（空でなければ）か $HOME/.config */
    if (c->xdg_config && *c->xdg_config) snprintf(file, sizeof(file), "%s/cfg/user-dirs.dirs", Base);
    else snprintf(file, sizeof(file), "%s/home/.config/user-dirs.dirs", Base);
    if (!(c->xdg_config && *c->xdg_config)) { char d[2048]; snprintf(d, sizeof(d), "%s/home/.config", Base); mkdir(d, 0777); }
    { FILE *f = fopen(file, "wb"); if (f) { fputs(dirs, f); fclose(f); } }
  }
  L("ENV %s", c->name);
  for (i = 0; i < (int)(sizeof(folders) / sizeof(folders[0])); i++) {
    const char *r = SDL_GetUserFolder(folders[i]);
    L("UF %s -> %s", fnames[i], r ? r : "NULL");
  }
  for (i = 0; i < 4; i++) {
    char *p = SDL_GetPrefPath(prefs[i][0], prefs[i][1]);
    L("PP '%s' '%s' -> %s", prefs[i][0], prefs[i][1], p ? p : "NULL");
    if (p) { struct stat st; L("PP exists %d", (int)(stat(p, &st) == 0 && S_ISDIR(st.st_mode))); }
    SDL_free(p);
  }
}

int main(int argc, char **argv)
{
  if (argc >= 2 && !strcmp(argv[1], "envcount")) { printf("%d\n", NENV); return 0; }
  if (argc >= 3 && !strcmp(argv[1], "ops")) { snprintf(Base, sizeof(Base), "%s", argv[2]); ops(); return 0; }
  if (argc >= 4 && !strcmp(argv[1], "env")) { snprintf(Base, sizeof(Base), "%s", argv[3]); envscene(atoi(argv[2])); return 0; }
  fprintf(stderr, "usage\n");
  return 2;
}
