/* ペンの場面を参照版の SDL に通して、手順と出たイベントを書き出す。papimela の test_pen（T-87）と
   test_wayland_tablet_model（T-88）が同じ手順を Pascal で行って突き合わせる。
   tools/pen-expect/gen.bb が作って test/test_pen_cases.inc と test/test_wayland_tablet_cases.inc に書く。

   使い方: pen_cases pen | tablet

   pen    : SDL_pen.c の内部の関数（SDL_AddPenDevice / SDL_SendPen* / SDL_SendPendingPenProximity など）を直接呼ぶ。
   tablet : SDL_waylandevents.c の tablet_tool_handle_*（3222〜3460 行）を下に写し、プロトコルの知らせの列を流す。
            写した関数は SDL の本文のまま。変えたのは Wayland のオブジェクトに触る所（サーフェスから窓を引く、
            道具の破棄、時刻の換算）だけで、そこには「papimela:」と書いた。カーソルの要求（Wayland_TabletToolUpdateCursor）
            は SDL_waylandmouse.c の分岐を写し、要求を記録する。

   出力（1 行ずつ）:
     N <場面>                        場面の始まり（SDL を初期化し直し、512x256 の窓を 2 つ作る）
     S <手順…>                       手順（Pascal 側が同じものを解釈して行う）
     E <種類> <窓> …                  そのとき出たイベント（ペン・マウス・タッチだけ。種類は papimela の名前）
       ペン    : E <種類> <窓> <ペン> <状態> <x> <y> <消しゴム> <下> <ボタン> <軸> <値>
       マウス  : E MouseMotion <窓> <MouseID> <x> <y> / E MouseButtonDown|Up <窓> <MouseID> <ボタン> <x> <y>
       タッチ  : E FingerDown|Up|Motion|Canceled <窓> <TouchID> <指> <x> <y> <dx> <dy> <圧力>
     R <問い> …                      問い合わせの答え（status / devtype / find / removed / info）
     C shape <serial> <形> | C hide <serial> | C reset      道具のカーソルへの要求（tablet だけ）
   窓は 1 か 2（0 は窓無し）、ペンは手順で付けた番号（SDL の ID を番号に戻す）。ID は下の 32 ビット。
   タッチの座標は SDL が窓の大きさで正規化するので、窓の大きさ（2 の冪乗）を掛けて papimela の座標に戻す。
   浮動小数は %.9g（Single に戻すと同じ値）。 */
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* ---- SDL の内部（src/events/SDL_pen_c.h の写し） ---- */
typedef Uint32 SDL_PenCapabilityFlags;
typedef enum SDL_PenSubtype {
  SDL_PEN_TYPE_UNKNOWN, SDL_PEN_TYPE_ERASER, SDL_PEN_TYPE_PEN, SDL_PEN_TYPE_PENCIL,
  SDL_PEN_TYPE_BRUSH, SDL_PEN_TYPE_AIRBRUSH
} SDL_PenSubtype;
typedef struct SDL_PenInfo {
  SDL_PenCapabilityFlags capabilities;
  float max_tilt;
  Uint32 wacom_id;
  int num_buttons;
  SDL_PenSubtype subtype;
  SDL_PenDeviceType device_type;
} SDL_PenInfo;
#define SDL_PEN_CAPABILITY_PRESSURE  (1u << 0)
#define SDL_PEN_CAPABILITY_XTILT     (1u << 1)
#define SDL_PEN_CAPABILITY_YTILT     (1u << 2)
#define SDL_PEN_CAPABILITY_DISTANCE  (1u << 3)
#define SDL_PEN_CAPABILITY_ROTATION  (1u << 4)
#define SDL_PEN_CAPABILITY_SLIDER    (1u << 5)
extern SDL_PenID SDL_AddPenDevice(Uint64 timestamp, const char *name, SDL_Window *window, const SDL_PenInfo *info, void *handle, bool in_proximity);
extern void SDL_RemovePenDevice(Uint64 timestamp, SDL_Window *window, SDL_PenID instance_id);
extern void SDL_RemoveAllPenDevices(void (*callback)(SDL_PenID instance_id, void *handle, void *userdata), void *userdata);
extern void SDL_SendPenTouch(Uint64 timestamp, SDL_PenID instance_id, SDL_Window *window, bool eraser, bool down);
extern void SDL_SendPenMotion(Uint64 timestamp, SDL_PenID instance_id, SDL_Window *window, float x, float y);
extern void SDL_SendPenAxis(Uint64 timestamp, SDL_PenID instance_id, SDL_Window *window, SDL_PenAxis axis, float value);
extern void SDL_SendPenButton(Uint64 timestamp, SDL_PenID instance_id, SDL_Window *window, Uint8 button, bool down);
extern void SDL_SendPenProximity(Uint64 timestamp, SDL_PenID instance_id, SDL_Window *window, bool in, bool immediate);
extern void SDL_SendPendingPenProximity(void);
extern SDL_PenID SDL_FindPenByHandle(void *handle);
extern SDL_PenInputFlags SDL_GetPenStatus(SDL_PenID instance_id, float *axes, int num_axes);

/* ---- 場面の土台 ---- */
#define WIN_W 512
#define WIN_H 256
#define MAXP 16
static SDL_Window *win[3];          /* 1 と 2。0 は NULL */
static bool win_gone[3];
static SDL_WindowID win_id[3];      /* 作ったときの窓の ID。壊した後に SDL_GetWindowID を呼ばないために覚える */
static SDL_PenID pen_id[MAXP];       /* 番号 → SDL の ID（外した後も覚えておく） */
static char handles[MAXP];           /* 番号 → バックエンドの Handle */

static SDL_Window *W(int i) { return (i >= 1 && i <= 2 && !win_gone[i]) ? win[i] : NULL; }
static int win_index(SDL_WindowID id)
{
  for (int i = 1; i <= 2; i++)
    if (win[i] && win_id[i] == id) return i;
  return 0;
}
static int pen_index(SDL_PenID id)
{
  if (!id) return 0;
  for (int i = 1; i < MAXP; i++)
    if (pen_id[i] == id) return i;
  return 99;
}
static SDL_PenID P(int i) { return (i >= 1 && i < MAXP) ? pen_id[i] : 0; }

static const char *pen_kind(Uint32 t)
{
  switch (t) {
  case SDL_EVENT_PEN_PROXIMITY_IN: return "PenProximityIn";
  case SDL_EVENT_PEN_PROXIMITY_OUT: return "PenProximityOut";
  case SDL_EVENT_PEN_DOWN: return "PenDown";
  case SDL_EVENT_PEN_UP: return "PenUp";
  case SDL_EVENT_PEN_BUTTON_DOWN: return "PenButtonDown";
  case SDL_EVENT_PEN_BUTTON_UP: return "PenButtonUp";
  case SDL_EVENT_PEN_MOTION: return "PenMotion";
  case SDL_EVENT_PEN_AXIS: return "PenAxis";
  }
  return NULL;
}
static Uint32 kind_by_name(const char *n)
{
  static const Uint32 all[] = { SDL_EVENT_PEN_PROXIMITY_IN, SDL_EVENT_PEN_PROXIMITY_OUT, SDL_EVENT_PEN_DOWN,
    SDL_EVENT_PEN_UP, SDL_EVENT_PEN_BUTTON_DOWN, SDL_EVENT_PEN_BUTTON_UP, SDL_EVENT_PEN_MOTION, SDL_EVENT_PEN_AXIS };
  for (size_t i = 0; i < sizeof(all) / sizeof(all[0]); i++)
    if (strcmp(pen_kind(all[i]), n) == 0) return all[i];
  fprintf(stderr, "unknown kind %s\n", n);
  exit(2);
}

static void flush_events(bool print)
{
  SDL_Event e;
  while (SDL_PeepEvents(&e, 1, SDL_GETEVENT, SDL_EVENT_FIRST, SDL_EVENT_LAST) > 0) {
    if (!print) continue;
    const char *k = pen_kind(e.type);
    if (k) {
      /* ペンのイベントは窓・which・pen_state が同じ位置にある（SDL_events.h） */
      float x = 0, y = 0, value = 0;
      int eraser = 0, down = 0, button = 0, axis = 0;
      switch (e.type) {
      case SDL_EVENT_PEN_DOWN: case SDL_EVENT_PEN_UP:
        x = e.ptouch.x; y = e.ptouch.y; eraser = e.ptouch.eraser; down = e.ptouch.down; break;
      case SDL_EVENT_PEN_BUTTON_DOWN: case SDL_EVENT_PEN_BUTTON_UP:
        x = e.pbutton.x; y = e.pbutton.y; button = e.pbutton.button; down = e.pbutton.down; break;
      case SDL_EVENT_PEN_MOTION:
        x = e.pmotion.x; y = e.pmotion.y; break;
      case SDL_EVENT_PEN_AXIS:
        x = e.paxis.x; y = e.paxis.y; axis = (int)e.paxis.axis; value = e.paxis.value; break;
      }
      printf("E %s %d %d %u %.9g %.9g %d %d %d %d %.9g\n", k, win_index(e.pproximity.windowID),
             pen_index(e.pproximity.which), (unsigned)e.pproximity.pen_state, x, y, eraser, down, button, axis, value);
    } else if (e.type == SDL_EVENT_MOUSE_MOTION) {
      printf("E MouseMotion %d %u %.9g %.9g\n", win_index(e.motion.windowID), (unsigned)e.motion.which,
             e.motion.x, e.motion.y);
    } else if (e.type == SDL_EVENT_MOUSE_BUTTON_DOWN || e.type == SDL_EVENT_MOUSE_BUTTON_UP) {
      printf("E %s %d %u %d %.9g %.9g\n", e.type == SDL_EVENT_MOUSE_BUTTON_DOWN ? "MouseButtonDown" : "MouseButtonUp",
             win_index(e.button.windowID), (unsigned)e.button.which, (int)e.button.button, e.button.x, e.button.y);
    } else if (e.type == SDL_EVENT_FINGER_DOWN || e.type == SDL_EVENT_FINGER_UP ||
               e.type == SDL_EVENT_FINGER_MOTION || e.type == SDL_EVENT_FINGER_CANCELED) {
      const char *fk = e.type == SDL_EVENT_FINGER_DOWN ? "FingerDown" : e.type == SDL_EVENT_FINGER_UP ? "FingerUp" :
                       e.type == SDL_EVENT_FINGER_MOTION ? "FingerMotion" : "FingerCanceled";
      printf("E %s %d %u %u %.9g %.9g %.9g %.9g %.9g\n", fk, win_index(e.tfinger.windowID),
             (unsigned)(e.tfinger.touchID & 0xffffffffu), (unsigned)(e.tfinger.fingerID & 0xffffffffu),
             e.tfinger.x * WIN_W, e.tfinger.y * WIN_H, e.tfinger.dx * WIN_W, e.tfinger.dy * WIN_H, e.tfinger.pressure);
    }
  }
}

static void scene(const char *name)
{
  SDL_Quit();
  SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "dummy");
  /* タッチとマウスの相互の合成は切る（papimela に無い。ペンの合成だけを見る） */
  SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
  SDL_SetHint(SDL_HINT_MOUSE_TOUCH_EVENTS, "0");
  if (!SDL_Init(SDL_INIT_VIDEO)) { printf("INIT-ERR %s\n", SDL_GetError()); exit(1); }
  win[0] = NULL;
  for (int i = 1; i <= 2; i++) {
    win[i] = SDL_CreateWindow("pen", WIN_W, WIN_H, 0);
    if (!win[i]) { printf("INIT-ERR %s\n", SDL_GetError()); exit(1); }
    win_id[i] = SDL_GetWindowID(win[i]);
    win_gone[i] = false;
  }
  memset(pen_id, 0, sizeof(pen_id));
  flush_events(false);
  printf("N %s\n", name);
}

static void removed_cb(SDL_PenID id, void *handle, void *userdata)
{
  (void)userdata;
  printf("R removed %d %d\n", pen_index(id), (int)((char *)handle - handles));
}

static void print_status(int p)
{
  /* 知らない ID なら SDL は axes に触らない。papimela の GetStatus は 0 で埋めるので、そのときは 0 と書く。
     ペンがあるかは SDL_GetPenDeviceType で見る（外したペンの ID は覚えているので、P(p) では分からない） */
  float a[SDL_PEN_AXIS_COUNT];
  memset(a, 0, sizeof(a));
  const bool exists = SDL_GetPenDeviceType(P(p)) != SDL_PEN_DEVICE_TYPE_INVALID;
  SDL_PenInputFlags f = SDL_GetPenStatus(P(p), a, SDL_PEN_AXIS_COUNT);
  printf("R status %d %u", p, (unsigned)f);
  for (int i = 0; i < SDL_PEN_AXIS_COUNT; i++) printf(" %.9g", exists ? a[i] : 0.0f);
  printf("\n");
}

/* ---- pen: SDL_pen.c を直接呼ぶ ---- */
static void pen_step(const char *line)
{
  char op[32];
  int p, w, a, b;
  float x, y;
  printf("S %s\n", line);
  sscanf(line, "%31s", op);
  if (!strcmp(op, "add")) {
    /* add <ペン> <近接> <窓> <種類> <機器の種類> <能力> <最大の傾き> <wacom> <ボタン数> */
    int inprox, sub, dev, nb; unsigned caps, wacom; float mt;
    sscanf(line, "%*s %d %d %d %d %d %u %f %u %d", &p, &inprox, &w, &sub, &dev, &caps, &mt, &wacom, &nb);
    SDL_PenInfo info = { caps, mt, wacom, nb, (SDL_PenSubtype)sub, (SDL_PenDeviceType)dev };
    pen_id[p] = SDL_AddPenDevice(0, "pen", W(w), &info, &handles[p], inprox != 0);
  } else if (!strcmp(op, "remove")) {
    sscanf(line, "%*s %d %d", &p, &w);
    SDL_RemovePenDevice(0, W(w), P(p));
  } else if (!strcmp(op, "removeall")) {
    SDL_RemoveAllPenDevices(removed_cb, NULL);
  } else if (!strcmp(op, "touch")) {
    sscanf(line, "%*s %d %d %d %d", &p, &w, &a, &b);
    SDL_SendPenTouch(0, P(p), W(w), a != 0, b != 0);
  } else if (!strcmp(op, "motion")) {
    sscanf(line, "%*s %d %d %f %f", &p, &w, &x, &y);
    SDL_SendPenMotion(0, P(p), W(w), x, y);
  } else if (!strcmp(op, "axis")) {
    sscanf(line, "%*s %d %d %d %f", &p, &w, &a, &x);
    SDL_SendPenAxis(0, P(p), W(w), (SDL_PenAxis)a, x);
  } else if (!strcmp(op, "button")) {
    sscanf(line, "%*s %d %d %d %d", &p, &w, &a, &b);
    SDL_SendPenButton(0, P(p), W(w), (Uint8)a, b != 0);
  } else if (!strcmp(op, "prox")) {
    sscanf(line, "%*s %d %d %d %d", &p, &w, &a, &b);
    SDL_SendPenProximity(0, P(p), W(w), a != 0, b != 0);
  } else if (!strcmp(op, "pending")) {
    SDL_SendPendingPenProximity();
  } else if (!strcmp(op, "hint")) {
    char which[16];
    sscanf(line, "%*s %15s %d", which, &a);
    SDL_SetHint(!strcmp(which, "mouse") ? SDL_HINT_PEN_MOUSE_EVENTS : SDL_HINT_PEN_TOUCH_EVENTS, a ? "1" : "0");
  } else if (!strcmp(op, "enable")) {
    char k[32];
    sscanf(line, "%*s %31s %d", k, &a);
    SDL_SetEventEnabled(kind_by_name(k), a != 0);
  } else if (!strcmp(op, "destroywin")) {
    sscanf(line, "%*s %d", &w);
    win_gone[w] = true;     /* 窓の ID は覚えたまま（保留した近接 out が古い ID を持つ） */
    SDL_DestroyWindow(win[w]);
    flush_events(false);
  } else if (!strcmp(op, "status")) {
    sscanf(line, "%*s %d", &p);
    print_status(p);
  } else if (!strcmp(op, "devtype")) {
    sscanf(line, "%*s %d", &p);
    printf("R devtype %d %d\n", p, (int)SDL_GetPenDeviceType(P(p)));
  } else if (!strcmp(op, "find")) {
    sscanf(line, "%*s %d", &p);
    printf("R find %d %d\n", p, pen_index(SDL_FindPenByHandle(&handles[p])));
  } else {
    fprintf(stderr, "unknown step %s\n", line);
    exit(2);
  }
  flush_events(true);
}

static const char *pen_scenes[] = {
  "N register",
  "add 1 0 1 2 1 3 60 0 2", "devtype 1", "find 1", "status 1",
  "add 2 1 1 1 2 0 -1 2050 -1", "devtype 2", "find 2", "status 2",
  "motion 9 1 1 1", "touch 9 1 0 1", "devtype 9", "find 9",
  "remove 1 1", "devtype 1", "find 1", "status 1",
  "remove 2 0", "devtype 2", "status 2",
  "add 3 0 1 0 0 255 -1 0 -1", "devtype 3", "remove 3 1",

  "N proximity",
  "add 1 0 1 2 1 0 -1 0 -1",
  "prox 1 1 1 1", "prox 1 1 1 1", "status 1",
  "button 1 1 1 1", "button 1 1 3 1", "status 1",
  "prox 1 1 0 1", "status 1", "prox 1 1 0 1",
  "prox 1 1 1 0", "prox 1 1 0 0", "status 1", "motion 1 1 10 20", "pending", "status 1",
  "prox 1 1 0 0", "pending", "pending", "status 1",
  "button 1 1 2 1", "prox 1 1 0 0", "button 1 1 2 0", "pending",
  "prox 1 2 1 1", "prox 1 2 0 0", "destroywin 2", "pending", "status 1",
  "motion 1 0 5 5", "motion 1 1 5 5", "motion 1 1 5 5", "status 1",
  "remove 1 1",

  "N touch",
  "add 1 1 1 2 1 1 -1 0 -1",
  "motion 1 1 100 50", "axis 1 1 0 0.5",
  "touch 1 1 0 1", "touch 1 1 0 1", "status 1",
  "motion 1 1 101.5 52.25", "axis 1 1 0 0.75", "axis 1 1 0 0.75",
  "axis 1 1 1 -30", "axis 1 1 2 45.5", "axis 1 1 4 179.5", "axis 1 1 5 1", "axis 1 1 6 2.5", "axis 1 1 3 0",
  "axis 1 1 3 0.25", "status 1",
  "button 1 1 2 1", "button 1 1 2 1", "button 1 1 2 0", "button 1 1 5 1", "button 1 1 5 0",
  "button 1 1 0 1", "button 1 1 6 1", "status 1",
  "touch 1 1 1 1", "status 1", "touch 1 1 1 0", "touch 1 1 0 0", "status 1",
  "touch 1 1 0 1", "remove 1 1", "status 1",

  "N two_pens",
  "add 1 1 1 2 1 0 -1 0 -1", "add 2 1 1 2 1 0 -1 0 -1",
  "motion 1 1 10 10", "motion 2 1 20 20",
  "touch 1 1 0 1", "motion 2 1 21 21", "motion 1 1 11 11",
  "touch 2 1 0 1", "button 2 1 1 1", "axis 2 1 0 0.5", "axis 1 1 0 0.25",
  "touch 1 1 0 0", "motion 2 1 22 22", "touch 2 1 0 0", "touch 2 1 0 1", "touch 1 1 0 1", "touch 2 1 0 0",
  "removeall", "status 1", "status 2", "find 1",

  "N hints",
  "hint mouse 0",
  "add 1 1 1 2 1 0 -1 0 -1", "motion 1 1 10 10", "touch 1 1 0 1", "motion 1 1 12 12", "button 1 1 1 1",
  "button 1 1 1 0", "touch 1 1 0 0",
  "hint touch 0", "hint mouse 1", "touch 1 1 0 1", "motion 1 1 11 11", "axis 1 1 0 0.5", "touch 1 1 0 0",
  "hint mouse 0", "touch 1 1 0 1", "touch 1 1 0 0",
  "hint touch 1", "hint mouse 1", "touch 1 0 0 1", "motion 1 0 13 13", "touch 1 0 0 0",
  "touch 1 1 0 1", "hint touch 0", "touch 1 1 0 0", "hint touch 1", "touch 1 1 0 1", "touch 1 1 0 0",

  "N disabled",
  "add 1 1 1 2 1 0 -1 0 -1",
  "enable PenMotion 0", "motion 1 1 10 10", "status 1",
  "enable PenDown 0", "touch 1 1 0 1", "status 1",
  "enable PenButtonDown 0", "button 1 1 1 1",
  "enable PenAxis 0", "axis 1 1 0 0.5", "status 1",
  "enable PenMotion 1", "motion 1 1 11 11",
  "enable PenProximityOut 0", "prox 1 1 0 1", "status 1",
  "enable PenProximityIn 0", "prox 1 1 1 1", "status 1",
  NULL
};

/* ---- tablet: SDL_waylandevents.c の tablet_tool_handle_* の写し ---- */
typedef Sint32 wl_fixed_t;
static double wl_fixed_to_double(wl_fixed_t f) { return (double)f / 256.0; }
#define BTN_STYLUS  0x14b
#define BTN_STYLUS2 0x14c
#define BTN_STYLUS3 0x149
#define ZWP_TABLET_TOOL_V2_TYPE_PEN 0x140
#define ZWP_TABLET_TOOL_V2_TYPE_ERASER 0x141
#define ZWP_TABLET_TOOL_V2_TYPE_BRUSH 0x142
#define ZWP_TABLET_TOOL_V2_TYPE_PENCIL 0x143
#define ZWP_TABLET_TOOL_V2_TYPE_AIRBRUSH 0x144
#define ZWP_TABLET_TOOL_V2_CAPABILITY_TILT 1
#define ZWP_TABLET_TOOL_V2_CAPABILITY_PRESSURE 2
#define ZWP_TABLET_TOOL_V2_CAPABILITY_DISTANCE 3
#define ZWP_TABLET_TOOL_V2_CAPABILITY_ROTATION 4
#define ZWP_TABLET_TOOL_V2_CAPABILITY_SLIDER 5
#define ZWP_TABLET_PAD_V2_BUTTON_STATE_PRESSED 1

/* papimela: SDL_WindowData の要る欄だけ */
typedef struct SDL_WindowData { SDL_Window *sdlwindow; struct { double x, y; } pointer_scale; } SDL_WindowData;
static SDL_WindowData wdata[3];

/* SDL_waylandevents_c.h の SDL_WaylandPenTool（cursor_state と link を除く） */
typedef struct SDL_WaylandPenTool {
  SDL_PenID instance_id;
  SDL_PenInfo info;
  SDL_WindowData *focus;
  void *wltool;
  Uint32 proximity_serial;
  struct {
    float x;
    float y;
    float axes[SDL_PEN_AXIS_COUNT];
    Uint32 axes_set;
    enum { WAYLAND_TABLET_TOOL_BUTTON_NONE = 0, WAYLAND_TABLET_TOOL_BUTTON_DOWN, WAYLAND_TABLET_TOOL_BUTTON_UP } buttons[3];
    enum { WAYLAND_TABLET_TOOL_STATE_NONE = 0, WAYLAND_TABLET_TOOL_STATE_DOWN, WAYLAND_TABLET_TOOL_STATE_UP } tool_state;
    bool in_proximity;
    bool have_motion;
    bool have_proximity;
  } frame;
  bool alive;   /* papimela: removed の後に free する代わり */
} SDL_WaylandPenTool;
static SDL_WaylandPenTool tools[MAXP];

/* papimela: アプリのカーソル（SDL_Mouse の cursor_visible と cur_cursor、相対モードで隠すかの判断） */
static unsigned cur_shape;
static bool cur_visible;
static bool cur_rel_hidden;

/* SDL_waylandmouse.c の Wayland_TabletToolUpdateCursor の分岐。要求は記録する（papimela:） */
static void Wayland_TabletToolUpdateCursor(SDL_WaylandPenTool *tool)
{
  SDL_WindowData *tool_focus = tool->focus;
  if (tool_focus) {
    if (cur_visible) {
      const bool relative = cur_rel_hidden;   /* pen_mouse_events && 相対モード && relative_mode_hide_cursor */
      if (!relative) {
        printf("C shape %u %u\n", (unsigned)tool->proximity_serial, cur_shape);
      } else {
        printf("C hide %u\n", (unsigned)tool->proximity_serial);
      }
    } else {
      printf("C hide %u\n", (unsigned)tool->proximity_serial);
    }
  } else {
    printf("C reset\n");
  }
}

static void tablet_tool_handle_type(void *data, void *tool, uint32_t type)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    switch (type) {
        #define CASE(typ) case ZWP_TABLET_TOOL_V2_TYPE_##typ: sdltool->info.subtype = SDL_PEN_TYPE_##typ; return
        CASE(ERASER);
        CASE(PEN);
        CASE(PENCIL);
        CASE(AIRBRUSH);
        CASE(BRUSH);
        #undef CASE
        default: sdltool->info.subtype = SDL_PEN_TYPE_UNKNOWN;  // we'll decline to add this when the `done` event comes through.
    }
}

static void tablet_tool_handle_hardware_id_wacom(void *data, void *tool, uint32_t id_hi, uint32_t id_lo)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    sdltool->info.wacom_id = id_lo;
}

static void tablet_tool_handle_capability(void *data, void *tool, uint32_t capability)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    switch (capability) {
        #define CASE(wltyp,sdltyp) case ZWP_TABLET_TOOL_V2_CAPABILITY_##wltyp: sdltool->info.capabilities |= sdltyp; return
        CASE(TILT, SDL_PEN_CAPABILITY_XTILT | SDL_PEN_CAPABILITY_YTILT);
        CASE(PRESSURE, SDL_PEN_CAPABILITY_PRESSURE);
        CASE(DISTANCE, SDL_PEN_CAPABILITY_DISTANCE);
        CASE(ROTATION, SDL_PEN_CAPABILITY_ROTATION);
        CASE(SLIDER, SDL_PEN_CAPABILITY_SLIDER);
        #undef CASE
        default: break;  // unsupported here.
    }
}

static void tablet_tool_handle_done(void *data, void *tool)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    if (sdltool->info.subtype != SDL_PEN_TYPE_UNKNOWN) {   // don't tell SDL about it if we don't know its role.
        SDL_Window *window = sdltool->focus ? sdltool->focus->sdlwindow : NULL;
        sdltool->instance_id = SDL_AddPenDevice(0, NULL, window, &sdltool->info, sdltool, false);
    }
}

static void tablet_tool_handle_removed(void *data, void *tool)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    if (sdltool->instance_id) {
        SDL_Window *window = sdltool->focus ? sdltool->focus->sdlwindow : NULL;
        SDL_RemovePenDevice(0, window, sdltool->instance_id);
    }

    /* papimela: Wayland_CursorStateRelease・zwp_tablet_tool_v2_destroy・リストから外す・free の代わり */
    sdltool->alive = false;
}

static void tablet_tool_handle_proximity_in(void *data, void *tool, uint32_t serial, void *tablet, int window_index)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    /* papimela: Wayland_GetWindowDataForOwnedSurface の代わりに窓の番号（0 = このアプリの窓でない） */
    SDL_WindowData *windowdata = window_index ? &wdata[window_index] : NULL;
    sdltool->focus = windowdata;
    sdltool->proximity_serial = serial;
    sdltool->frame.have_proximity = true;
    sdltool->frame.in_proximity = true;

    // According to the docs, this should be followed by a frame event, where we'll send our SDL events.
}

static void tablet_tool_handle_proximity_out(void *data, void *tool)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    sdltool->frame.have_proximity = true;
    sdltool->frame.in_proximity = false;
}

static void tablet_tool_handle_down(void *data, void *tool, uint32_t serial)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    sdltool->frame.tool_state = WAYLAND_TABLET_TOOL_STATE_DOWN;
}

static void tablet_tool_handle_up(void *data, void *tool)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    sdltool->frame.tool_state = WAYLAND_TABLET_TOOL_STATE_UP;
}

static void tablet_tool_handle_motion(void *data, void *tool, wl_fixed_t sx_w, wl_fixed_t sy_w)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    SDL_WindowData *windowdata = sdltool->focus;
    if (windowdata) {
        sdltool->frame.x = (float)(wl_fixed_to_double(sx_w) * windowdata->pointer_scale.x);
        sdltool->frame.y = (float)(wl_fixed_to_double(sy_w) * windowdata->pointer_scale.y);
        sdltool->frame.have_motion = true;
    }
}

static void tablet_tool_handle_pressure(void *data, void *tool, uint32_t pressure)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    sdltool->frame.axes[SDL_PEN_AXIS_PRESSURE] = ((float) pressure) / 65535.0f;
    sdltool->frame.axes_set |= (1u << SDL_PEN_AXIS_PRESSURE);
    if (pressure) {
        sdltool->frame.axes[SDL_PEN_AXIS_DISTANCE] = 0.0f;
        sdltool->frame.axes_set |= (1u << SDL_PEN_AXIS_DISTANCE);
    }
}

static void tablet_tool_handle_distance(void *data, void *tool, uint32_t distance)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    sdltool->frame.axes[SDL_PEN_AXIS_DISTANCE] = ((float) distance) / 65535.0f;
    sdltool->frame.axes_set |= (1u << SDL_PEN_AXIS_DISTANCE);
    if (distance) {
        sdltool->frame.axes[SDL_PEN_AXIS_PRESSURE] = 0.0f;
        sdltool->frame.axes_set |= (1u << SDL_PEN_AXIS_PRESSURE);
    }
}

static void tablet_tool_handle_tilt(void *data, void *tool, wl_fixed_t xtilt, wl_fixed_t ytilt)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    sdltool->frame.axes[SDL_PEN_AXIS_XTILT] = (float)(wl_fixed_to_double(xtilt));
    sdltool->frame.axes[SDL_PEN_AXIS_YTILT] = (float)(wl_fixed_to_double(ytilt));
    sdltool->frame.axes_set |= (1u << SDL_PEN_AXIS_XTILT) | (1u << SDL_PEN_AXIS_YTILT);
}

static void tablet_tool_handle_button(void *data, void *tool, uint32_t serial, uint32_t button, uint32_t state)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    int sdlbutton;

    switch (button) {
    case BTN_STYLUS:
        sdlbutton = 1;
        break;
    case BTN_STYLUS2:
        sdlbutton = 2;
        break;
    case BTN_STYLUS3:
        sdlbutton = 3;
        break;
    default:
        return;  // don't care about this button, I guess.
    }

    SDL_assert((sdlbutton >= 1) && (sdlbutton <= SDL_arraysize(sdltool->frame.buttons)));
    sdltool->frame.buttons[sdlbutton-1] = (state == ZWP_TABLET_PAD_V2_BUTTON_STATE_PRESSED) ? WAYLAND_TABLET_TOOL_BUTTON_DOWN : WAYLAND_TABLET_TOOL_BUTTON_UP;
}

static void tablet_tool_handle_rotation(void *data, void *tool, wl_fixed_t degrees)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    const float rotation = (float)(wl_fixed_to_double(degrees));
    sdltool->frame.axes[SDL_PEN_AXIS_ROTATION] = (rotation > 180.0f) ? (rotation - 360.0f) : rotation;  // map to -180.0f ... 179.0f range
    sdltool->frame.axes_set |= (1u << SDL_PEN_AXIS_ROTATION);
}

static void tablet_tool_handle_slider(void *data, void *tool, int32_t position)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    sdltool->frame.axes[SDL_PEN_AXIS_SLIDER] = position / 65535.f;
    sdltool->frame.axes_set |= (1u << SDL_PEN_AXIS_SLIDER);
}

static void tablet_tool_handle_wheel(void *data, void *tool, int32_t degrees, int32_t clicks)
{
    // not supported at the moment
}

static void tablet_tool_handle_frame(void *data, void *tool, uint32_t time)
{
    SDL_WaylandPenTool *sdltool = (SDL_WaylandPenTool *) data;
    const SDL_PenID instance_id = sdltool->instance_id;
    if (!instance_id) {
        return;  // Not a pen we report on.
    }

    const Uint64 timestamp = 0;   /* papimela: Wayland_AdjustEventTimestampBase(Wayland_EventTimestampMSToNS(time)) */
    SDL_Window *window = sdltool->focus ? sdltool->focus->sdlwindow : NULL;
    const bool is_eraser = sdltool->info.subtype == SDL_PEN_TYPE_ERASER;

    if (sdltool->frame.have_proximity && sdltool->frame.in_proximity) {
        SDL_SendPenProximity(timestamp, instance_id, window, true, true);
        Wayland_TabletToolUpdateCursor(sdltool);
    }

    // !!! FIXME: Should hit testing be done if pens generate pointer motion?

    // I don't know if this is necessary (or makes sense), but send motion before pen downs, but after pen ups, so you don't get unexpected lines drawn.
    if (sdltool->frame.have_motion && sdltool->frame.tool_state) {
        if (sdltool->frame.tool_state == WAYLAND_TABLET_TOOL_STATE_DOWN) {
            SDL_SendPenMotion(timestamp, instance_id, window, sdltool->frame.x, sdltool->frame.y);
            SDL_SendPenTouch(timestamp, instance_id, window, is_eraser, true);
        } else {
            SDL_SendPenTouch(timestamp, instance_id, window, is_eraser, false);
            SDL_SendPenMotion(timestamp, instance_id, window, sdltool->frame.x, sdltool->frame.y);
        }
    } else {
        if (sdltool->frame.tool_state) {
            SDL_SendPenTouch(timestamp, instance_id, window, is_eraser, sdltool->frame.tool_state == WAYLAND_TABLET_TOOL_STATE_DOWN);
        }

        if (sdltool->frame.have_motion) {
            SDL_SendPenMotion(timestamp, instance_id, window, sdltool->frame.x, sdltool->frame.y);
        }
    }

    for (SDL_PenAxis i = 0; i < SDL_PEN_AXIS_COUNT; i++) {
        if (sdltool->frame.axes_set & (1u << i)) {
            SDL_SendPenAxis(timestamp, instance_id, window, i, sdltool->frame.axes[i]);
        }
    }

    for (int i = 0; i < SDL_arraysize(sdltool->frame.buttons); i++) {
        const int state = sdltool->frame.buttons[i];
        if (state) {
            SDL_SendPenButton(timestamp, instance_id, window, (Uint8)(i + 1), state == WAYLAND_TABLET_TOOL_BUTTON_DOWN);
        }
    }

    if (sdltool->frame.have_proximity && !sdltool->frame.in_proximity) {
        SDL_SendPenProximity(timestamp, instance_id, window, false, false);
        sdltool->focus = NULL;
        Wayland_TabletToolUpdateCursor(sdltool);
    }

    // Reset for the next frame.
    SDL_zero(sdltool->frame);
}

static void tablet_step(const char *line)
{
  char op[32];
  int t, w;
  unsigned a, b, c;
  int ia, ib;
  printf("S %s\n", line);
  sscanf(line, "%31s", op);
  if (!strcmp(op, "tool")) {
    /* tablet_seat_handle_tool_added の初期値 */
    sscanf(line, "%*s %d", &t);
    memset(&tools[t], 0, sizeof(tools[t]));
    tools[t].info.max_tilt = -1.0f;
    tools[t].info.num_buttons = -1;
    tools[t].alive = true;
    return;
  }
  sscanf(line, "%*s %d", &t);
  SDL_WaylandPenTool *d = &tools[t];
  if (!strcmp(op, "type")) { sscanf(line, "%*s %*d %x", &a); tablet_tool_handle_type(d, NULL, a); }
  else if (!strcmp(op, "serial")) { /* hardware_serial は SDL が使わない */ }
  else if (!strcmp(op, "wacom")) { sscanf(line, "%*s %*d %u %u", &a, &b); tablet_tool_handle_hardware_id_wacom(d, NULL, a, b); }
  else if (!strcmp(op, "cap")) { sscanf(line, "%*s %*d %u", &a); tablet_tool_handle_capability(d, NULL, a); }
  else if (!strcmp(op, "done")) tablet_tool_handle_done(d, NULL);
  else if (!strcmp(op, "removed")) tablet_tool_handle_removed(d, NULL);
  else if (!strcmp(op, "pin")) { sscanf(line, "%*s %*d %u %d", &a, &w); tablet_tool_handle_proximity_in(d, NULL, a, NULL, w); }
  else if (!strcmp(op, "pout")) tablet_tool_handle_proximity_out(d, NULL);
  else if (!strcmp(op, "down")) { sscanf(line, "%*s %*d %u", &a); tablet_tool_handle_down(d, NULL, a); }
  else if (!strcmp(op, "up")) tablet_tool_handle_up(d, NULL);
  else if (!strcmp(op, "motion")) { sscanf(line, "%*s %*d %d %d", &ia, &ib); tablet_tool_handle_motion(d, NULL, ia, ib); }
  else if (!strcmp(op, "pressure")) { sscanf(line, "%*s %*d %u", &a); tablet_tool_handle_pressure(d, NULL, a); }
  else if (!strcmp(op, "distance")) { sscanf(line, "%*s %*d %u", &a); tablet_tool_handle_distance(d, NULL, a); }
  else if (!strcmp(op, "tilt")) { sscanf(line, "%*s %*d %d %d", &ia, &ib); tablet_tool_handle_tilt(d, NULL, ia, ib); }
  else if (!strcmp(op, "rotation")) { sscanf(line, "%*s %*d %d", &ia); tablet_tool_handle_rotation(d, NULL, ia); }
  else if (!strcmp(op, "slider")) { sscanf(line, "%*s %*d %d", &ia); tablet_tool_handle_slider(d, NULL, ia); }
  else if (!strcmp(op, "wheel")) { sscanf(line, "%*s %*d %d %d", &ia, &ib); tablet_tool_handle_wheel(d, NULL, ia, ib); }
  else if (!strcmp(op, "button")) { sscanf(line, "%*s %*d %u %x %u", &a, &b, &c); tablet_tool_handle_button(d, NULL, a, b, c); }
  else if (!strcmp(op, "frame")) { sscanf(line, "%*s %*d %u", &a); tablet_tool_handle_frame(d, NULL, a); }
  else if (!strcmp(op, "cursor")) {
    /* cursor <形> <見える> <相対で隠す>。papimela は道具が窓の上なら Wayland_TabletToolUpdateCursor と同じ規則で張り直す
       （SDL の Wayland_ShowCursor はカーソルを隠していても道具に cur_cursor を張る。DESIGN #66 の行） */
    int vis, rel;
    sscanf(line, "%*s %u %d %d", &a, &vis, &rel);
    cur_shape = a; cur_visible = vis != 0; cur_rel_hidden = rel != 0;
    for (int i = 1; i < MAXP; i++)
      if (tools[i].alive) Wayland_TabletToolUpdateCursor(&tools[i]);
  } else if (!strcmp(op, "wdestroy")) {
    /* Wayland_RemoveWindowDataFromExternalList の道具の部分（3620〜3629 行） */
    sscanf(line, "%*s %d", &w);
    for (int i = 1; i < MAXP; i++) {
      SDL_WaylandPenTool *tool = &tools[i];
      if (tool->alive && tool->focus == &wdata[w]) {
        tool->focus = NULL;
        Wayland_TabletToolUpdateCursor(tool);
        if (tool->instance_id) {
          SDL_RemovePenDevice(0, wdata[w].sdlwindow, tool->instance_id);
          tool->instance_id = 0;
        }
      }
    }
  } else if (!strcmp(op, "info")) {
    printf("R info %d %u %.9g %u %d %d %d %d\n", t, (unsigned)d->info.capabilities, d->info.max_tilt,
           (unsigned)d->info.wacom_id, d->info.num_buttons, (int)d->info.subtype, (int)d->info.device_type,
           d->instance_id ? 1 : 0);
  } else if (!strcmp(op, "status")) {
    /* 道具 t の登録したペン（番号は道具の番号） */
    pen_id[t] = d->instance_id;
    print_status(t);
  } else {
    fprintf(stderr, "unknown step %s\n", line);
    exit(2);
  }
  /* 道具の登録したペンを番号に結ぶ（ペンの番号 = 道具の番号） */
  for (int i = 1; i < MAXP; i++)
    if (tools[i].instance_id) pen_id[i] = tools[i].instance_id;
  flush_events(true);
}

static void tablet_scene_init(void)
{
  memset(tools, 0, sizeof(tools));
  for (int i = 1; i <= 2; i++) {
    wdata[i].sdlwindow = win[i];
    wdata[i].pointer_scale.x = wdata[i].pointer_scale.y = 1.0;
  }
  cur_shape = 0; cur_visible = true; cur_rel_hidden = false;
}

/* 座標と角度は wl_fixed_t（256 倍）の整数で書く */
static const char *tablet_scenes[] = {
  "N info",
  "tool 1", "type 1 140", "serial 1 1 2", "wacom 1 7 2050", "cap 1 1", "cap 1 2", "cap 1 3", "cap 1 4", "cap 1 5", "cap 1 6",
  "info 1", "done 1", "info 1", "status 1",
  "tool 2", "type 2 146", "done 2", "info 2", "pin 2 5 1", "motion 2 2560 2560", "frame 2 0", "status 2",
  "tool 3", "type 3 141", "done 3", "info 3",
  "tool 4", "type 4 142", "done 4", "info 4",
  "tool 5", "type 5 143", "done 5", "info 5",
  "tool 6", "type 6 144", "done 6", "info 6",
  "tool 7", "type 7 145", "done 7", "info 7",
  "tool 8", "type 8 147", "done 8", "info 8",
  "tool 9", "done 9", "info 9",

  "N stroke",
  "tool 1", "type 1 140", "cap 1 1", "cap 1 2", "cap 1 3", "done 1",
  "pin 1 10 1", "motion 1 25600 12800", "distance 1 6553", "frame 1 100", "status 1",
  "motion 1 25728 12864", "frame 1 101",
  "down 1 11", "pressure 1 32768", "motion 1 25856 12928", "frame 1 102", "status 1",
  "pressure 1 65535", "tilt 1 -7680 11520", "frame 1 103",
  "rotation 1 69120", "slider 1 65535", "frame 1 104",
  "rotation 1 46080", "slider 1 -65535", "frame 1 105",
  "rotation 1 46336", "frame 1 106",
  "button 1 12 14b 1", "button 1 13 14c 1", "frame 1 107", "status 1",
  "button 1 14 149 1", "button 1 15 110 1", "button 1 16 14b 0", "frame 1 108", "status 1",
  "wheel 1 3840 1", "frame 1 109",
  "up 1", "motion 1 25984 12992", "distance 1 1000", "frame 1 110", "status 1",
  "down 1 17", "frame 1 111", "up 1", "frame 1 112",
  "pressure 1 0", "distance 1 0", "frame 1 113", "status 1",
  "pout 1", "frame 1 114", "status 1",
  "motion 1 2560 2560", "frame 1 115",

  "N eraser",
  "tool 1", "type 1 141", "done 1",
  "pin 1 20 2", "motion 1 2560 5120", "down 1 21", "frame 1 0",
  "up 1", "pout 1", "frame 1 1", "status 1",

  "N not_ours",
  "tool 1", "type 1 140", "done 1",
  "pin 1 30 0", "motion 1 2560 2560", "frame 1 0", "status 1",
  "down 1 31", "frame 1 1", "pout 1", "frame 1 2", "status 1",
  "pin 1 32 1", "pout 1", "frame 1 3", "status 1",

  "N cursor",
  "tool 1", "type 1 140", "done 1", "tool 2", "type 2 141", "done 2",
  "cursor 5 1 0",
  "pin 1 40 1", "frame 1 0",
  "cursor 7 1 0", "cursor 7 0 0", "cursor 7 1 1", "cursor 7 1 0",
  "pin 2 41 2", "frame 2 0", "cursor 9 1 0",
  "pout 1", "frame 1 1", "cursor 3 0 0",
  "pout 2", "frame 2 1",

  "N window_destroyed",
  "tool 1", "type 1 140", "done 1", "tool 2", "type 2 140", "done 2",
  "pin 1 50 1", "down 1 51", "motion 1 2560 2560", "frame 1 0",
  "pin 2 52 2", "motion 2 1280 1280", "frame 2 0",
  "wdestroy 1", "status 1", "info 1",
  "pin 1 53 1", "motion 1 2816 2816", "frame 1 1", "info 1",
  "status 2",

  "N removed",
  "tool 1", "type 1 140", "done 1",
  "pin 1 60 1", "down 1 61", "motion 1 2560 2560", "button 1 62 14b 1", "frame 1 0",
  "removed 1", "status 1",
  NULL
};

int main(int argc, char **argv)
{
  bool tablet = argc > 1 && !strcmp(argv[1], "tablet");
  if (argc < 2 || (!tablet && strcmp(argv[1], "pen"))) {
    fprintf(stderr, "usage: pen_cases pen|tablet\n");
    return 2;
  }
  const char **s = tablet ? tablet_scenes : pen_scenes;
  for (; *s; s++) {
    if ((*s)[0] == 'N' && (*s)[1] == ' ') {
      scene(*s + 2);
      if (tablet) tablet_scene_init();
    } else if (tablet) {
      tablet_step(*s);
    } else {
      pen_step(*s);
    }
  }
  SDL_Quit();
  return 0;
}
