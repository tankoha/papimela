/* ゲームパッド（SDL_gamepad.c の機器・開いたゲームパッド・イベント）を、仮想ジョイスティックの上で参照版の SDL に通して、
   場面ごとの値とイベントを書き出す。papimela の test_gamepad が同じ場面を Pascal で行って突き合わせる。
   tools/gamepad-expect/gen.bb が作って test/gamepad_expected.inc に書く（gen.bb の第 2 引数が gp）。
   出力は 1 行ずつ「L <文面>」。機器の ID は最初に現れた順に J1, J2, ... と書き直す。タイムスタンプは書かない。 */
#include <SDL3/SDL.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>

static SDL_JoystickID known[64];
static int nknown = 0;
static int lab(SDL_JoystickID id)
{
  for (int i = 0; i < nknown; i++) if (known[i] == id) return i + 1;
  known[nknown++] = id;
  return nknown;
}
static void L(const char *fmt, ...)
{
  va_list ap;
  printf("L ");
  va_start(ap, fmt); vprintf(fmt, ap); va_end(ap);
  printf("\n");
}
static void section(const char *name) { L("== %s", name); }

static void drain(void)
{
  SDL_Event e;
  while (SDL_PollEvent(&e)) {
    switch (e.type) {
    case SDL_EVENT_JOYSTICK_ADDED: L("ev jadded J%d", lab(e.jdevice.which)); break;
    case SDL_EVENT_JOYSTICK_REMOVED: L("ev jremoved J%d", lab(e.jdevice.which)); break;
    case SDL_EVENT_JOYSTICK_AXIS_MOTION: L("ev jaxis J%d %d %d", lab(e.jaxis.which), e.jaxis.axis, e.jaxis.value); break;
    case SDL_EVENT_JOYSTICK_HAT_MOTION: L("ev jhat J%d %d %d", lab(e.jhat.which), e.jhat.hat, e.jhat.value); break;
    case SDL_EVENT_JOYSTICK_BUTTON_DOWN: L("ev jdown J%d %d", lab(e.jbutton.which), e.jbutton.button); break;
    case SDL_EVENT_JOYSTICK_BUTTON_UP: L("ev jup J%d %d", lab(e.jbutton.which), e.jbutton.button); break;
    case SDL_EVENT_JOYSTICK_UPDATE_COMPLETE: L("ev jcomplete J%d", lab(e.jdevice.which)); break;
    case SDL_EVENT_GAMEPAD_ADDED: L("ev gadded J%d", lab(e.gdevice.which)); break;
    case SDL_EVENT_GAMEPAD_REMOVED: L("ev gremoved J%d", lab(e.gdevice.which)); break;
    case SDL_EVENT_GAMEPAD_REMAPPED: L("ev gremapped J%d", lab(e.gdevice.which)); break;
    case SDL_EVENT_GAMEPAD_UPDATE_COMPLETE: L("ev gcomplete J%d", lab(e.gdevice.which)); break;
    case SDL_EVENT_GAMEPAD_AXIS_MOTION: L("ev gaxis J%d %s %d", lab(e.gaxis.which), SDL_GetGamepadStringForAxis((SDL_GamepadAxis)e.gaxis.axis), e.gaxis.value); break;
    case SDL_EVENT_GAMEPAD_BUTTON_DOWN: L("ev gdown J%d %s", lab(e.gbutton.which), SDL_GetGamepadStringForButton((SDL_GamepadButton)e.gbutton.button)); break;
    case SDL_EVENT_GAMEPAD_BUTTON_UP: L("ev gup J%d %s", lab(e.gbutton.which), SDL_GetGamepadStringForButton((SDL_GamepadButton)e.gbutton.button)); break;
    default: L("ev other %u", e.type); break;
    }
  }
}
static void update(const char *tag)
{
  SDL_UpdateGamepads();
  L("-- %s", tag);
  drain();
}

static SDL_JoystickID attach_m(const char *tag, Uint16 type, Uint16 vid, Uint16 pid, int naxes, int nbuttons, int nhats, const char *name, Uint32 bm, Uint32 am)
{
  SDL_VirtualJoystickDesc d;
  SDL_INIT_INTERFACE(&d);
  d.type = type; d.vendor_id = vid; d.product_id = pid;
  d.naxes = naxes; d.nbuttons = nbuttons; d.nhats = nhats;
  d.name = name;
  d.button_mask = bm; d.axis_mask = am;
  SDL_JoystickID id = SDL_AttachVirtualJoystick(&d);
  if (!id) { L("attach %s failed: %s", tag, SDL_GetError()); return 0; }
  L("attach %s -> J%d", tag, lab(id));
  return id;
}

static SDL_JoystickID attach(const char *tag, Uint16 type, Uint16 vid, Uint16 pid, int naxes, int nbuttons, int nhats, const char *name)
{
  return attach_m(tag, type, vid, pid, naxes, nbuttons, nhats, name, 0, 0);
}

static void guid_hex(SDL_GUID g, char *out) { for (int i = 0; i < 16; i++) sprintf(out + i * 2, "%02x", g.data[i]); }

static void ids_list(const char *tag)
{
  int n = 0;
  SDL_JoystickID *ids = SDL_GetGamepads(&n);
  char buf[200] = "";
  for (int i = 0; i < n; i++) { char t[16]; sprintf(t, " J%d", lab(ids[i])); strcat(buf, t); }
  L("gamepads %s:%s (count=%d has=%d)", tag, buf, n, (int)SDL_HasGamepad());
  SDL_free(ids);
}

static void info_for_id(SDL_JoystickID id)
{
  char *m = SDL_GetGamepadMappingForID(id);
  const char *name = SDL_GetGamepadNameForID(id);
  L("info J%d is=%d name='%s' type=%d real=%d player=%d joytype=%d", lab(id), (int)SDL_IsGamepad(id), name ? name : "(null)",
    (int)SDL_GetGamepadTypeForID(id), (int)SDL_GetRealGamepadTypeForID(id), SDL_GetGamepadPlayerIndexForID(id),
    (int)SDL_GetJoystickTypeForID(id));
  L("mapping J%d %s", lab(id), m ? m : "(null)");
  SDL_free(m);
}

static void pad_state(const char *tag, SDL_Gamepad *g)
{
  char buf[600] = "";
  for (int i = 0; i < SDL_GAMEPAD_AXIS_COUNT; i++) {
    char t[40]; sprintf(t, " %s=%d", SDL_GetGamepadStringForAxis((SDL_GamepadAxis)i), SDL_GetGamepadAxis(g, (SDL_GamepadAxis)i));
    strcat(buf, t);
  }
  strcat(buf, " |");
  for (int i = 0; i < SDL_GAMEPAD_BUTTON_COUNT; i++)
    if (SDL_GetGamepadButton(g, (SDL_GamepadButton)i)) { strcat(buf, " "); strcat(buf, SDL_GetGamepadStringForButton((SDL_GamepadButton)i)); }
  L("pad %s:%s", tag, buf);
}

static void has_list(SDL_Gamepad *g)
{
  char buf[400] = "";
  for (int i = 0; i < SDL_GAMEPAD_AXIS_COUNT; i++)
    if (SDL_GamepadHasAxis(g, (SDL_GamepadAxis)i)) { strcat(buf, " "); strcat(buf, SDL_GetGamepadStringForAxis((SDL_GamepadAxis)i)); }
  strcat(buf, " |");
  for (int i = 0; i < SDL_GAMEPAD_BUTTON_COUNT; i++)
    if (SDL_GamepadHasButton(g, (SDL_GamepadButton)i)) { strcat(buf, " "); strcat(buf, SDL_GetGamepadStringForButton((SDL_GamepadButton)i)); }
  L("has:%s", buf);
}

static void bindings(SDL_Gamepad *g)
{
  int n = 0;
  SDL_GamepadBinding **b = SDL_GetGamepadBindings(g, &n);
  L("bindings %d", n);
  for (int i = 0; i < n; i++) {
    char in[80], out[80];
    switch (b[i]->input_type) {
    case SDL_GAMEPAD_BINDTYPE_BUTTON: sprintf(in, "b%d", b[i]->input.button); break;
    case SDL_GAMEPAD_BINDTYPE_AXIS: sprintf(in, "a%d[%d..%d]", b[i]->input.axis.axis, b[i]->input.axis.axis_min, b[i]->input.axis.axis_max); break;
    case SDL_GAMEPAD_BINDTYPE_HAT: sprintf(in, "h%d.%d", b[i]->input.hat.hat, b[i]->input.hat.hat_mask); break;
    default: sprintf(in, "none"); break;
    }
    if (b[i]->output_type == SDL_GAMEPAD_BINDTYPE_AXIS)
      sprintf(out, "%s[%d..%d]", SDL_GetGamepadStringForAxis(b[i]->output.axis.axis), b[i]->output.axis.axis_min, b[i]->output.axis.axis_max);
    else
      sprintf(out, "%s", SDL_GetGamepadStringForButton(b[i]->output.button));
    L("  bind %s -> %s", in, out);
  }
  SDL_free(b);
}

static void pad_props(SDL_Gamepad *g)
{
  L("gamepad name='%s' type=%d real=%d player=%d", SDL_GetGamepadName(g), (int)SDL_GetGamepadType(g), (int)SDL_GetRealGamepadType(g), SDL_GetGamepadPlayerIndex(g));
  L("labels south=%d east=%d west=%d north=%d start=%d", (int)SDL_GetGamepadButtonLabel(g, SDL_GAMEPAD_BUTTON_SOUTH),
    (int)SDL_GetGamepadButtonLabel(g, SDL_GAMEPAD_BUTTON_EAST), (int)SDL_GetGamepadButtonLabel(g, SDL_GAMEPAD_BUTTON_WEST),
    (int)SDL_GetGamepadButtonLabel(g, SDL_GAMEPAD_BUTTON_NORTH), (int)SDL_GetGamepadButtonLabel(g, SDL_GAMEPAD_BUTTON_START));
}

extern bool SDL_ShouldIgnoreGamepad(Uint16 vendor_id, Uint16 product_id, Uint16 version, const char *name);

int main(void)
{
  SDL_SetHint("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1");
  SDL_SetHint("SDL_GAMECONTROLLER_IGNORE_DEVICES", "0x1111/0x2222");
  if (!SDL_Init(SDL_INIT_GAMEPAD)) { printf("INIT-ERR %s\n", SDL_GetError()); return 1; }
  SDL_UpdateGamepads(); drain();
  { int n = 0; SDL_JoystickID *ids = SDL_GetJoysticks(&n); SDL_free(ids); if (n) { printf("INIT-ERR real joysticks present: %d\n", n); return 1; } }

  section("auto");
  SDL_JoystickID xb = attach("XB", SDL_JOYSTICK_TYPE_GAMEPAD, 0x045e, 0x028e, 6, 15, 1, NULL);
  info_for_id(xb);
  SDL_JoystickID ps = attach("PS", SDL_JOYSTICK_TYPE_GAMEPAD, 0x054c, 0x0ce6, 6, 17, 0, "My PS5 Pad");
  info_for_id(ps);
  SDL_JoystickID gn = attach("GN", SDL_JOYSTICK_TYPE_GAMEPAD, 0x0000, 0x0000, 4, 8, 1, "Lic Pro Controller");
  info_for_id(gn);
  SDL_JoystickID un = attach("UN", SDL_JOYSTICK_TYPE_UNKNOWN, 0x0a0a, 0x0b0b, 2, 2, 0, "Plain Stick");
  info_for_id(un);
  /* ボタンとハットと軸の割り当て方（仮想ジョイスティックの GetGamepadMapping） */
  {
    SDL_JoystickID all = attach("ALL", SDL_JOYSTICK_TYPE_GAMEPAD, 0x1234, 0x5678, 6, 26, 0, "All Buttons");
    info_for_id(all);
    SDL_JoystickID mk = attach_m("MK", SDL_JOYSTICK_TYPE_GAMEPAD, 0x1234, 0x5679, 3, 5, 1, "Masked",
      (1u << SDL_GAMEPAD_BUTTON_SOUTH) | (1u << SDL_GAMEPAD_BUTTON_GUIDE) | (1u << SDL_GAMEPAD_BUTTON_DPAD_UP) |
      (1u << SDL_GAMEPAD_BUTTON_MISC1) | (1u << SDL_GAMEPAD_BUTTON_LEFT_PADDLE2) | (1u << SDL_GAMEPAD_BUTTON_START) | (1u << SDL_GAMEPAD_BUTTON_MISC6),
      (1u << SDL_GAMEPAD_AXIS_LEFTX) | (1u << SDL_GAMEPAD_AXIS_RIGHT_TRIGGER) | (1u << SDL_GAMEPAD_AXIS_RIGHTY));
    info_for_id(mk);
    SDL_JoystickID sm = attach("SM", SDL_JOYSTICK_TYPE_GAMEPAD, 0x1234, 0x567a, 1, 3, 0, "Small");
    info_for_id(sm);
    SDL_JoystickID tk = attach("TK", SDL_JOYSTICK_TYPE_GAMEPAD, 0x1234, 0x567b, 4, 22, 1, "Touch Misc");
    info_for_id(tk);
    SDL_DetachVirtualJoystick(all); SDL_DetachVirtualJoystick(mk); SDL_DetachVirtualJoystick(sm); SDL_DetachVirtualJoystick(tk);
  }
  ids_list("all");
  update("added");

  section("open");
  { SDL_Gamepad *g = SDL_OpenGamepad(xb);
    L("open XB ok=%d id=J%d", (int)(g != NULL), g ? lab(SDL_GetGamepadID(g)) : 0);
    SDL_Gamepad *again = SDL_OpenGamepad(xb); L("open again same=%d", (int)(again == g));
    L("from id same=%d", (int)(SDL_GetGamepadFromID(xb) == g));
    L("from player same=%d", (int)(SDL_GetGamepadFromPlayerIndex(SDL_GetGamepadPlayerIndex(g)) == g));
    pad_props(g);
    has_list(g);
    bindings(g);
    L("mapping %s", SDL_GetGamepadMapping(g));
    pad_state("initial", g);
    SDL_CloseGamepad(g);
    L("from id after one close same=%d", (int)(SDL_GetGamepadFromID(xb) == g));
    SDL_CloseGamepad(again);
    L("from id after close %d", (int)(SDL_GetGamepadFromID(xb) != NULL)); }
  L("open plain stick %d", (int)(SDL_OpenGamepad(un) != NULL));
  L("open missing %d", (int)(SDL_OpenGamepad(9999) != NULL));
  L("is missing %d", (int)SDL_IsGamepad(9999));

  section("types");
  { SDL_Gamepad *g = SDL_OpenGamepad(ps); pad_props(g); has_list(g); SDL_CloseGamepad(g); }
  { SDL_Gamepad *g = SDL_OpenGamepad(gn); pad_props(g); has_list(g); SDL_CloseGamepad(g); }
  { SDL_JoystickID sw = attach("SW", SDL_JOYSTICK_TYPE_GAMEPAD, 0x057e, 0x2009, 6, 15, 1, NULL);
    SDL_Gamepad *g = SDL_OpenGamepad(sw); pad_props(g); SDL_CloseGamepad(g); SDL_DetachVirtualJoystick(sw); }
  { SDL_JoystickID gc = attach("GC", SDL_JOYSTICK_TYPE_GAMEPAD, 0x057e, 0x0337, 6, 15, 1, NULL);
    SDL_Gamepad *g = SDL_OpenGamepad(gc); pad_props(g); SDL_CloseGamepad(g); SDL_DetachVirtualJoystick(gc); }
  { SDL_JoystickID x1 = attach("X1", SDL_JOYSTICK_TYPE_GAMEPAD, 0x045e, 0x02ea, 6, 15, 1, NULL);
    SDL_Gamepad *g = SDL_OpenGamepad(x1); pad_props(g); SDL_CloseGamepad(g); SDL_DetachVirtualJoystick(x1); }
  update("types");

  section("state");
  { SDL_Gamepad *g = SDL_OpenGamepad(xb);
    SDL_Joystick *j = SDL_GetGamepadJoystick(g);
    pad_state("rest", g);
    SDL_SetJoystickVirtualButton(j, 0, true); update("a down"); pad_state("a", g);
    SDL_SetJoystickVirtualButton(j, 0, true); update("a again");
    SDL_SetJoystickVirtualButton(j, 1, true); SDL_SetJoystickVirtualButton(j, 0, false); update("b down a up"); pad_state("b", g);
    SDL_SetJoystickVirtualAxis(j, 0, 20000); update("leftx 20000"); pad_state("leftx", g);
    SDL_SetJoystickVirtualAxis(j, 0, -32768); update("leftx min"); pad_state("leftx min", g);
    SDL_SetJoystickVirtualAxis(j, 1, 12345); update("lefty 12345");
    SDL_SetJoystickVirtualAxis(j, 4, 0); update("lefttrigger half"); pad_state("trigger half", g);
    SDL_SetJoystickVirtualAxis(j, 4, 32767); update("lefttrigger full"); pad_state("trigger full", g);
    SDL_SetJoystickVirtualAxis(j, 5, 16000); update("righttrigger 16000"); pad_state("righttrigger", g);
    SDL_SetJoystickVirtualAxis(j, 4, -32768); SDL_SetJoystickVirtualAxis(j, 5, -32768); update("triggers released");
    SDL_SetJoystickVirtualHat(j, 0, SDL_HAT_RIGHTUP); update("hat rightup"); pad_state("hat", g);
    SDL_SetJoystickVirtualHat(j, 0, SDL_HAT_RIGHTUP); update("hat rightup again");
    SDL_SetJoystickVirtualHat(j, 0, SDL_HAT_LEFT); update("hat left"); pad_state("hat left", g);
    SDL_SetJoystickVirtualHat(j, 0, SDL_HAT_CENTERED); update("hat centered");
    SDL_SetJoystickVirtualButton(j, 3, true); SDL_SetJoystickVirtualButton(j, 4, true); update("x y"); pad_state("xy", g);
    SDL_SetJoystickVirtualButton(j, 3, false); SDL_SetJoystickVirtualButton(j, 4, false); update("x y up");
    SDL_SetGamepadEventsEnabled(false);
    L("events enabled %d", (int)SDL_GamepadEventsEnabled());
    SDL_SetJoystickVirtualButton(j, 0, true); update("a down (gamepad events off)"); pad_state("off", g);
    SDL_SetGamepadEventsEnabled(true);
    L("events enabled %d", (int)SDL_GamepadEventsEnabled());
    SDL_SetJoystickVirtualButton(j, 0, false); update("a up (on again)");
    SDL_CloseGamepad(g); }

  section("custom");
  { L("set map UN %d", (int)SDL_SetGamepadMapping(un, "x,Custom Pad,a:b0,b:+a1,x:-a1,leftx:a0~,lefty:a1,righttrigger:h0.1,dpup:b1,leftshoulder:+a0,rightshoulder:-a0,"));
    update("mapping set");
    info_for_id(un);
    ids_list("after set");
    SDL_Gamepad *g = SDL_OpenGamepad(un);
    SDL_Joystick *j = SDL_GetGamepadJoystick(g);
    pad_props(g); has_list(g); bindings(g);
    SDL_SetJoystickVirtualButton(j, 0, true); update("b0"); pad_state("b0", g);
    SDL_SetJoystickVirtualAxis(j, 1, 30000); update("a1=30000"); pad_state("a1 high", g);
    SDL_SetJoystickVirtualAxis(j, 1, -30000); update("a1=-30000"); pad_state("a1 low", g);
    SDL_SetJoystickVirtualAxis(j, 1, 200); update("a1=200"); pad_state("a1 near zero", g);
    SDL_SetJoystickVirtualAxis(j, 0, 15000); update("a0=15000"); pad_state("a0", g);
    SDL_SetJoystickVirtualAxis(j, 0, -15000); update("a0=-15000"); pad_state("a0 neg", g);
    SDL_SetJoystickVirtualAxis(j, 0, 0); update("a0=0");
    SDL_SetJoystickVirtualButton(j, 1, true); update("b1"); pad_state("b1", g);
    L("set map again %d", (int)SDL_SetGamepadMapping(un, "x,Custom Pad Two,a:b1,b:b0,type:ps4,face:sony,"));
    update("mapping changed");
    pad_props(g); bindings(g);
    L("add same guid via AddGamepadMapping");
    { char *m = SDL_GetGamepadMappingForID(un); char guid[40]; guid_hex(SDL_GetJoystickGUIDForID(un), guid);
      char buf[300]; sprintf(buf, "%s,Api Pad,a:b2,", guid); L("add %d", SDL_AddGamepadMapping(buf)); SDL_free(m); }
    update("added again");
    pad_props(g); bindings(g);
    L("set map NULL %d", (int)SDL_SetGamepadMapping(un, NULL));
    update("mapping cleared");
    bindings(g);
    L("name '%s'", SDL_GetGamepadName(g));
    SDL_CloseGamepad(g); }

  section("guide");
  { SDL_JoystickID gd = attach("GD", SDL_JOYSTICK_TYPE_UNKNOWN, 0x0d0d, 0x0e0e, 2, 3, 0, "Guide Pad");
    update("gd added");
    SDL_SetGamepadMapping(gd, "x,Guide Pad,a:b0,guide:b1,start:b2,"); update("gd mapped");
    SDL_Gamepad *g = SDL_OpenGamepad(gd);
    SDL_Joystick *j = SDL_GetGamepadJoystick(g);
    SDL_SetJoystickVirtualButton(j, 1, true); update("guide down");
    SDL_SetJoystickVirtualButton(j, 1, false); update("guide up quickly");
    pad_state("guide pending", g);
    SDL_SetJoystickVirtualButton(j, 1, true); update("guide down again (pending)");
    SDL_SetJoystickVirtualButton(j, 1, false); update("guide up again quickly");
    SDL_Delay(300); update("after 300ms");
    SDL_SetJoystickVirtualButton(j, 1, true); update("guide down 2");
    SDL_Delay(300);
    SDL_SetJoystickVirtualButton(j, 1, false); update("guide up slowly");
    SDL_SetJoystickVirtualButton(j, 2, true); update("start down");
    SDL_CloseGamepad(g); SDL_DetachVirtualJoystick(gd); update("gd removed"); }

  section("multi");
  { SDL_JoystickID mt = attach("MT", SDL_JOYSTICK_TYPE_UNKNOWN, 0x0f0f, 0x0f10, 3, 3, 1, "Multi Pad");
    update("mt added");
    SDL_SetGamepadMapping(mt, "x,Multi Pad,leftx:b0,leftx:a1,lefty:+a2,righty:-a2,dpleft:h0.8,dpup:h0.1,a:b1,x:a0~,rightx:a0~,start:b2,");
    update("mt mapped");
    SDL_Gamepad *g = SDL_OpenGamepad(mt);
    SDL_Joystick *j = SDL_GetGamepadJoystick(g);
    bindings(g); pad_state("rest", g);
    SDL_SetJoystickVirtualAxis(j, 1, 8000); update("a1=8000"); pad_state("a1", g);
    SDL_SetJoystickVirtualButton(j, 0, true); update("b0 down"); pad_state("b0", g);
    SDL_SetJoystickVirtualButton(j, 0, false); update("b0 up"); pad_state("b0 up", g);
    SDL_SetJoystickVirtualAxis(j, 2, 32672); update("a2=32672"); pad_state("a2 32672", g);
    SDL_SetJoystickVirtualAxis(j, 2, 32675); update("a2=32675"); pad_state("a2 32675", g);
    SDL_SetJoystickVirtualAxis(j, 2, -20000); update("a2=-20000"); pad_state("a2 neg", g);
    SDL_SetJoystickVirtualAxis(j, 2, 0); update("a2=0");
    SDL_SetJoystickVirtualHat(j, 0, SDL_HAT_LEFT); update("hat left"); pad_state("hat left", g);
    SDL_SetJoystickVirtualHat(j, 0, SDL_HAT_LEFTUP); update("hat leftup"); pad_state("hat leftup", g);
    SDL_SetJoystickVirtualHat(j, 0, SDL_HAT_UP); update("hat up"); pad_state("hat up", g);
    SDL_SetJoystickVirtualHat(j, 0, SDL_HAT_CENTERED); update("hat centered");
    SDL_SetJoystickVirtualButton(j, 1, true); SDL_SetJoystickVirtualAxis(j, 2, 32000); SDL_SetJoystickVirtualHat(j, 0, SDL_HAT_LEFT);
    update("held"); pad_state("held", g);
    SDL_DetachVirtualJoystick(mt); update("mt removed"); pad_state("after", g);
    SDL_CloseGamepad(g); }

  section("recenter");
  { SDL_Gamepad *g = SDL_OpenGamepad(xb);
    SDL_Joystick *j = SDL_GetGamepadJoystick(g);
    SDL_SetJoystickVirtualButton(j, 0, true); SDL_SetJoystickVirtualAxis(j, 0, 25000); SDL_SetJoystickVirtualAxis(j, 4, 32767);
    SDL_SetJoystickVirtualHat(j, 0, SDL_HAT_UP);
    update("held");
    SDL_DetachVirtualJoystick(xb); update("detached while held");
    L("connected %d", (int)SDL_GamepadConnected(g));
    pad_state("after", g);
    SDL_CloseGamepad(g); }

  section("ignore");
  {
    /* 仮想ジョイスティックは SDL_ShouldIgnoreJoystick を通らないので、内部の関数を直接呼ぶ */
    static const struct { Uint16 v, p, ver; const char *name; } cases[] = {
      {0x1111, 0x2222, 0, "Plain"}, {0x3333, 0x4444, 0, "Foo Touchpad"}, {0x3333, 0x4444, 0, "Foo Touchpad Bar"},
      {0x3333, 0x4445, 0, "Usb Keyboard"}, {0x3333, 0x4446, 0, "PG-9099 Keyboard"}, {0x28de, 0x11ff, 0, "Steam"},
      {0x3333, 0x4447, 0, "Sony DualSense Motion Sensors"}, {0x3333, 0x4447, 0, "Pad IMU"}, {0x3333, 0x4447, 0, "uinput-fp"},
      {0x3333, 0x4447, 0, "Mouse passthrough"}, {0x3333, 0x4447, 0, "Wacom One Pen"}, {0x3333, 0x4447, 0, "Thing System Control"},
      {0x3333, 0x4447, 0, "My Synaptics Pad"}, {0x3333, 0x4447, 0, "Pad IR"}, {0x3333, 0x4447, 0, "Pad IR 2"},
      {0x3333, 0x4447, 0, "gpio_ir_recv"}, {0x3333, 0x4447, 0, "An LED Thing"}, {0x3333, 0x4447, 0, ""},
      {0x2222, 0x1111, 0, "Normal Pad"}, {0x5555, 0x6666, 0, "Normal Pad"},
    };
    for (int i = 0; i < (int)(sizeof(cases) / sizeof(cases[0])); i++)
      L("ignore %04x/%04x '%s' -> %d", cases[i].v, cases[i].p, cases[i].name, (int)SDL_ShouldIgnoreGamepad(cases[i].v, cases[i].p, cases[i].ver, cases[i].name));
    SDL_SetHint("SDL_GAMECONTROLLER_IGNORE_DEVICES", "0x5555/0x6666,0x7777/0x8888");
    L("hint ignore changed");
    L("ignore 1111/2222 -> %d", (int)SDL_ShouldIgnoreGamepad(0x1111, 0x2222, 0, "Normal Pad"));
    L("ignore 5555/6666 -> %d", (int)SDL_ShouldIgnoreGamepad(0x5555, 0x6666, 0, "Normal Pad"));
    SDL_SetHint("SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT", "0x7777/0x8888");
    L("hint except set");
    L("ignore 5555/6666 -> %d", (int)SDL_ShouldIgnoreGamepad(0x5555, 0x6666, 0, "Normal Pad"));
    L("ignore 7777/8888 -> %d", (int)SDL_ShouldIgnoreGamepad(0x7777, 0x8888, 0, "Normal Pad"));
    L("ignore 7777/8888 touchpad -> %d", (int)SDL_ShouldIgnoreGamepad(0x7777, 0x8888, 0, "X Touchpad"));
    L("ignore steam with except -> %d", (int)SDL_ShouldIgnoreGamepad(0x28de, 0x11ff, 0, "Steam"));
    SDL_SetHint("SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT", NULL);
    SDL_SetHint("SDL_GAMECONTROLLER_IGNORE_DEVICES", NULL);
    L("ignore 5555/6666 after reset -> %d", (int)SDL_ShouldIgnoreGamepad(0x5555, 0x6666, 0, "Normal Pad"));
  }

  section("player");
  { int n = 0; SDL_JoystickID *ids = SDL_GetGamepads(&n);
    for (int i = 0; i < n; i++) L("player J%d = %d", lab(ids[i]), SDL_GetGamepadPlayerIndexForID(ids[i]));
    SDL_free(ids); }

  SDL_Quit();
  return 0;
}
