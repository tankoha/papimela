/* ゲームパッドのマッピングの DB（SDL_gamepad.c の AddMapping 系）を、参照版の SDL に通して書き出す。
   papimela の test_gamepad_mapping が、この「操作」の行を読んで同じ操作を行い、結果を突き合わせる。
   tools/gamepad-expect/gen.bb が作って test/gamepad_mapping_expected.inc に書く。
   出力は 1 行ずつ「L > 操作 引数」（操作）と「L = 結果」（結果）。引数の \ と改行は \\ \n \r に書く。 */
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

typedef struct { const char *op; const char *arg; } Op;

#define G_PLAIN  "03000000aaaa00000001000000000000"
#define G_CRC    "03003412bbbb00000002000000000000"
#define G_CRC2   "03007856bbbb00000002000000000000"
#define G_NOCRC  "03000000bbbb00000002000000000000"
#define G_VER    "03000000dddd00000004000001020000"
#define G_VER2   "03000000dddd00000004000099990000"
#define G_VER0   "03000000dddd00000004000000000000"
#define G_GC     "030000007e0500003703000000000000"
#define G_CRCIN  "03003412cccc00000003000000000000"
#define G_FIRST  "03000000c82d00001930000011010000"
#define G_HINT   "03000000eeee00000005000000000000"
#define G_LAB    "03000000ffff00000006000000000000"
#define G_PLAT   "03000000abab00000007000000000000"
#define G_USER   "03000000a1a100000008000000000000"

static const Op ops[] = {
  /* 利用者の優先度（ヒントの設定。SDL_Init より前に効く） */
  {"CONFIG", G_USER ",User Pad,a:b0,b:b1,platform:Linux,\n" "03000000a2a200000009000000000000,User Pad Two,a:b2,platform:Linux,"},

  /* 内蔵の表 */
  {"ALL", ""},

  /* 足す・更新・失敗 */
  {"ADD", G_PLAIN ",Test Pad One,a:b0,b:b1,x:b2,y:b3,leftx:a0,lefty:a1,dpup:h0.1,platform:Linux,"},
  {"GUIDMAP", G_PLAIN},
  {"ADD", G_PLAIN ",Test Pad Renamed,a:b5,leftx:a2,"},
  {"GUIDMAP", G_PLAIN},
  {"ADD", "garbage"},
  {"ADD", ""},
  {"ADD", G_PLAIN ",no second comma"},
  {"ADD", "notaguid,Odd Pad,a:b0,"},
  {"ADD", "03000000abcd,Short Guid,a:b0,"},

  /* 空白 */
  {"ADD", "03000000cdcd00000010000000000000,  Spaced Name  ,   a:b0,b:b1  \r"},
  {"GUIDMAP", "03000000cdcd00000010000000000000"},

  /* 終わりのコンマと platform */
  {"ADD", "03000000cece00000011000000000000,No Trailing Comma,a:b0,b:b1"},
  {"GUIDMAP", "03000000cece00000011000000000000"},
  {"ADD", G_PLAT ",Two Platforms,a:b0,platform:Windows,b:b1,platform:Linux,"},
  {"GUIDMAP", G_PLAT},

  /* CRC */
  {"ADD", G_CRC ",CRC Pad,crc:3412,a:b0,"},
  {"GUIDMAP", G_CRC},
  {"GUIDMAP", G_CRC2},
  {"GUIDMAP", G_NOCRC},
  {"ADD", G_NOCRC ",NoCRC Pad,a:b9,"},
  {"GUIDMAP", G_NOCRC},
  {"GUIDMAP", G_CRC},
  {"ADD", G_CRCIN ",CRC In Guid,a:b0,"},
  {"GUIDMAP", G_CRCIN},
  {"ADD", G_CRCIN ",CRC In Guid Again,a:b1,crc:3412,b:b2,"},
  {"GUIDMAP", G_CRCIN},

  {"ADD", "03003412cccc00000013000000000000,Crc No Comma,a:b0"},
  {"GUIDMAP", "03003412cccc00000013000000000000"},
  {"ADD", "03003412cccc00000014000000000000,Crc Replaced,a:b1,crc:0000,b:b2"},
  {"GUIDMAP", "03003412cccc00000014000000000000"},
  {"ADD", "03000000cccc00000015000000000000,Crc From Body,a:b1,crc:00ab,b:b2"},
  {"GUIDMAP", "03000000cccc00000015000000000000"},
  {"GUIDMAP", "0300ab00cccc00000015000000000000"},

  /* バージョン（ベンダーとプロダクトがあるとき、合わなければバージョンを見ずに探す） */
  {"ADD", G_VER ",Versioned,a:b0,"},
  {"GUIDMAP", G_VER},
  {"GUIDMAP", G_VER2},
  {"ADD", G_VER0 ",Unversioned,a:b1,"},
  {"GUIDMAP", G_VER0},
  {"GUIDMAP", G_VER2},

  /* 優先度（内蔵 < API < 利用者） */
  {"ADD", G_FIRST ",Override Builtin,a:b7,"},
  {"GUIDMAP", G_FIRST},
  {"ADD", G_USER ",Api Over User,a:b9,"},
  {"GUIDMAP", G_USER},
  {"ADD", "03000000a2a200000009000000000000,Api Over User Two,a:b9,"},
  {"GUIDMAP", "03000000a2a200000009000000000000"},

  /* ヒント条件 */
  {"ADD", G_HINT ",Hinted,a:b0,hint:TEST_HINT_A,"},
  {"HINT", "TEST_HINT_A=1"},
  {"ADD", G_HINT ",Hinted,a:b0,hint:TEST_HINT_A,"},
  {"HINT", "TEST_HINT_A=0"},
  {"ADD", G_HINT ",Hinted Off,a:b1,hint:TEST_HINT_A,"},
  {"ADD", G_HINT ",Hinted Not,a:b2,hint:!TEST_HINT_A,"},
  {"ADD", G_HINT ",Hinted Not B,a:b3,hint:!TEST_HINT_B,"},
  {"ADD", "03000000eeee00000015000000000000,Hinted Default,a:b3,hint:TEST_HINT_C:=1,"},
  {"ADD", "03000000eeee00000016000000000000,Hinted Default Off,a:b3,hint:TEST_HINT_C:=0,"},
  {"GUIDMAP", G_HINT},
  {"GUIDMAP", "03000000eeee00000015000000000000"},

  /* 位置どおりのボタンへの読み替え */
  {"ADD", G_LAB ",Gamecube Labels,a:b0,b:b1,x:b2,y:b3,hint:SDL_GAMECONTROLLER_USE_GAMECUBE_LABELS,"},
  {"GUIDMAP", G_LAB},
  {"ADD", "03000000ffff00000017000000000000,Button Labels,a:b0,b:b1,x:b2,y:b3,hint:SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1,"},
  {"GUIDMAP", "03000000ffff00000017000000000000"},
  {"ADD", "03000000ffff00000018000000000000,Positional,a:b0,b:b1,x:b2,y:b3,hint:!SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1,"},
  {"GUIDMAP", "03000000ffff00000018000000000000"},
  {"ADD", "03000000ffff00000019000000000000,Positional Gc,a:b0,b:b1,x:b2,y:b3,hint:!SDL_GAMECONTROLLER_USE_GAMECUBE_LABELS,"},
  {"GUIDMAP", "03000000ffff00000019000000000000"},
  {"ADD", G_GC ",Gamecube Adapter,a:b0,b:b1,x:b2,y:b3,"},
  {"GUIDMAP", G_GC},

  /* default */
  {"ADD", "default,*,a:b0,b:b1,"},
  {"ADD", "default,*,a:b2,"},
  {"GUIDMAP", "00000000000000000000000000000000"},

  /* 文章から読む */
  {"IO",
   "# comment line\n"
   "03000000f1f100000020000000000000,Io Linux,a:b0,platform:Linux,\n"
   "03000000f1f100000021000000000000,Io Windows,a:b0,platform:Windows,\n"
   "03000000f1f100000022000000000000,Io Lower,a:b0,platform:linux,\r\n"
   "03000000f1f100000023000000000000,Io Short,a:b0,platform:Lin,\n"
   "03000000f1f100000024000000000000,Io Long,a:b0,platform:Linuxx,\n"
   "03000000f1f100000025000000000000,Io Empty,a:b0,platform:,\n"
   "03000000f1f100000026000000000000,Io No Platform,a:b0,\n"
   "03000000f1f100000027000000000000,Io No Comma,a:b0,platform:Linux\n"
   "\n"
   "03000000f1f100000028000000000000,Io Last,a:b0,platform:Linux,"},
  {"IO", "03000000f1f100000020000000000000,Io Linux Again,a:b3,platform:Linux,\n"},
  {"GUIDMAP", "03000000f1f100000020000000000000"},
  {"GUIDMAP", "03000000f1f100000028000000000000"},
  {"GUIDMAP", "03000000f1f100000023000000000000"},
  {"GUIDMAP", "03000000f1f100000024000000000000"},
  {"GUIDMAP", "03000000f1f100000025000000000000"},

  {"ALL", ""},
};

static void esc(const char *s)
{
  for (; *s; s++) {
    if (*s == '\\') printf("\\\\");
    else if (*s == '\n') printf("\\n");
    else if (*s == '\r') printf("\\r");
    else putchar(*s);
  }
}

int main(void)
{
  const int n = (int)(sizeof(ops) / sizeof(ops[0]));
  int i;
  SDL_SetHint(SDL_HINT_GAMECONTROLLERCONFIG, ops[0].arg);
  if (!SDL_Init(SDL_INIT_GAMEPAD)) { printf("INIT-ERR %s\n", SDL_GetError()); return 1; }
  {
    int cnt = 0;
    SDL_JoystickID *j = SDL_GetJoysticks(&cnt);
    SDL_free(j);
    if (cnt != 0) { printf("INIT-ERR joysticks present: %d\n", cnt); return 1; }
  }
  for (i = 0; i < n; i++) {
    const char *op = ops[i].op, *arg = ops[i].arg;
    printf("L > %s ", op); esc(arg); printf("\n");
    if (!strcmp(op, "CONFIG")) {
      printf("L = ok\n");
    } else if (!strcmp(op, "ADD")) {
      printf("L = %d\n", SDL_AddGamepadMapping(arg));
    } else if (!strcmp(op, "GUIDMAP")) {
      char *m = SDL_GetGamepadMappingForGUID(SDL_StringToGUID(arg));
      printf("L = %s\n", m ? m : "NULL");
      SDL_free(m);
    } else if (!strcmp(op, "ALL")) {
      int c = 0, k;
      char **all = SDL_GetGamepadMappings(&c);
      printf("L = count %d\n", c);
      for (k = 0; k < c; k++) printf("L = %s\n", all[k]);
      SDL_free(all);
    } else if (!strcmp(op, "IO")) {
      SDL_IOStream *io = SDL_IOFromConstMem(arg, strlen(arg));
      printf("L = %d\n", SDL_AddGamepadMappingsFromIO(io, true));
    } else if (!strcmp(op, "HINT")) {
      char name[64]; const char *eq = strchr(arg, '=');
      memcpy(name, arg, eq - arg); name[eq - arg] = 0;
      SDL_SetHint(name, eq + 1);
      printf("L = ok\n");
    }
  }
  SDL_Quit();
  return 0;
}
