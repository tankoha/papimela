/* ジョイスティックのコア（SDL_joystick.c）と仮想ジョイスティックを、参照版の SDL に通して、場面ごとの
   イベントと値を書き出す。papimela の test_joystick が同じ場面を Pascal で行って突き合わせる。
   tools/joystick-expect/gen.bb が作って test/joystick_expected.inc に書く。
   出力は 1 行ずつ「L <文面>」。ジョイスティックの ID は、最初に現れた順に J1, J2, ... と書き直す
   （SDL と papimela で ID の値が違うため）。タイムスタンプは書かない。 */
#include <SDL3/SDL.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>

static SDL_JoystickID known[32];
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

/* SDL の不具合で papimela と食い違う行（D-79: 仮想ジョイスティックは nballs を写さない）。gen.bb は比べる対象から外す */
static void LB(const char *fmt, ...)
{
  va_list ap;
  printf("LB ");
  va_start(ap, fmt); vprintf(fmt, ap); va_end(ap);
  printf("\n");
}

/* 溜まったイベントを書き出す */
static void drain(void)
{
  SDL_Event e;
  while (SDL_PollEvent(&e)) {
    switch (e.type) {
    case SDL_EVENT_JOYSTICK_ADDED: L("ev added J%d", lab(e.jdevice.which)); break;
    case SDL_EVENT_JOYSTICK_REMOVED: L("ev removed J%d", lab(e.jdevice.which)); break;
    case SDL_EVENT_JOYSTICK_AXIS_MOTION: L("ev axis J%d %d %d", lab(e.jaxis.which), e.jaxis.axis, e.jaxis.value); break;
    case SDL_EVENT_JOYSTICK_BALL_MOTION: L("ev ball J%d %d %d %d", lab(e.jball.which), e.jball.ball, e.jball.xrel, e.jball.yrel); break;
    case SDL_EVENT_JOYSTICK_HAT_MOTION: L("ev hat J%d %d %d", lab(e.jhat.which), e.jhat.hat, e.jhat.value); break;
    case SDL_EVENT_JOYSTICK_BUTTON_DOWN: L("ev down J%d %d", lab(e.jbutton.which), e.jbutton.button); break;
    case SDL_EVENT_JOYSTICK_BUTTON_UP: L("ev up J%d %d", lab(e.jbutton.which), e.jbutton.button); break;
    case SDL_EVENT_JOYSTICK_BATTERY_UPDATED: L("ev battery J%d %d %d", lab(e.jbattery.which), (int)e.jbattery.state, e.jbattery.percent); break;
    case SDL_EVENT_JOYSTICK_UPDATE_COMPLETE: L("ev complete J%d", lab(e.jdevice.which)); break;
    default: L("ev other %u", e.type); break;
    }
  }
}

static void update(const char *tag)
{
  SDL_UpdateJoysticks();
  L("-- %s", tag);
  drain();
}

/* 仮想ジョイスティックの呼び出しの記録 */
static void cb_update(void *u) { (void)u; }
static void cb_player(void *u, int idx) { L("cb player %s %d", (const char *)u, idx); }
static bool cb_rumble(void *u, Uint16 lo, Uint16 hi) { L("cb rumble %s %u %u", (const char *)u, lo, hi); return true; }
static bool cb_rumble_trig(void *u, Uint16 l, Uint16 r) { L("cb triggers %s %u %u", (const char *)u, l, r); return false; }
static bool cb_led(void *u, Uint8 r, Uint8 g, Uint8 b) { L("cb led %s %u %u %u", (const char *)u, r, g, b); return true; }
static bool cb_effect(void *u, const void *d, int size) { L("cb effect %s %d %u", (const char *)u, size, size > 0 ? ((const Uint8 *)d)[0] : 0); return true; }
static bool cb_sensors(void *u, bool en) { (void)u; (void)en; return true; }
static void cb_cleanup(void *u) { L("cb cleanup %s", (const char *)u); }

static SDL_JoystickID attach(const char *tag, Uint16 type, Uint16 vid, Uint16 pid, int naxes, int nbuttons, int nhats, int nballs, const char *name, bool callbacks)
{
  SDL_VirtualJoystickDesc d;
  SDL_INIT_INTERFACE(&d);
  d.type = type; d.vendor_id = vid; d.product_id = pid;
  d.naxes = naxes; d.nbuttons = nbuttons; d.nhats = nhats; d.nballs = nballs;
  d.name = name;
  d.userdata = (void *)tag;
  d.Cleanup = cb_cleanup;
  if (callbacks) {
    d.Update = cb_update; d.SetPlayerIndex = cb_player; d.Rumble = cb_rumble; d.RumbleTriggers = cb_rumble_trig;
    d.SetLED = cb_led; d.SendEffect = cb_effect; d.SetSensorsEnabled = cb_sensors;
  }
  SDL_JoystickID id = SDL_AttachVirtualJoystick(&d);
  if (!id) { L("attach %s failed: %s", tag, SDL_GetError()); return 0; }
  L("attach %s -> J%d", tag, lab(id));
  return id;
}

static void guid_hex(SDL_GUID g, char *out) { for (int i = 0; i < 16; i++) sprintf(out + i * 2, "%02x", g.data[i]); }

static void info_for_id(SDL_JoystickID id)
{
  char gs[40];
  SDL_GUID g = SDL_GetJoystickGUIDForID(id);
  guid_hex(g, gs);
  const char *path = SDL_GetJoystickPathForID(id);
  L("info J%d name='%s' path=%s guid=%s vendor=%04x product=%04x version=%04x type=%d player=%d virtual=%d",
    lab(id), SDL_GetJoystickNameForID(id), path ? path : "(none)", gs,
    SDL_GetJoystickVendorForID(id), SDL_GetJoystickProductForID(id), SDL_GetJoystickProductVersionForID(id),
    (int)SDL_GetJoystickTypeForID(id), SDL_GetJoystickPlayerIndexForID(id), (int)SDL_IsJoystickVirtual(id));
}

static void ids_list(const char *tag)
{
  int n = 0;
  SDL_JoystickID *ids = SDL_GetJoysticks(&n);
  char buf[200] = "";
  for (int i = 0; i < n; i++) { char t[16]; sprintf(t, " J%d", lab(ids[i])); strcat(buf, t); }
  L("list %s:%s (count=%d has=%d)", tag, buf, n, (int)SDL_HasJoystick());
  SDL_free(ids);
}

static void state(const char *tag, SDL_Joystick *j)
{
  char buf[400] = "";
  int na = SDL_GetNumJoystickAxes(j), nb = SDL_GetNumJoystickButtons(j), nh = SDL_GetNumJoystickHats(j);
  for (int i = 0; i < na; i++) { char t[24]; sprintf(t, " a%d=%d", i, SDL_GetJoystickAxis(j, i)); strcat(buf, t); }
  for (int i = 0; i < nb; i++) { char t[24]; sprintf(t, " b%d=%d", i, (int)SDL_GetJoystickButton(j, i)); strcat(buf, t); }
  for (int i = 0; i < nh; i++) { char t[24]; sprintf(t, " h%d=%d", i, SDL_GetJoystickHat(j, i)); strcat(buf, t); }
  L("state %s:%s connected=%d", tag, buf, (int)SDL_JoystickConnected(j));
}

static void initial(SDL_Joystick *j, int axis)
{
  Sint16 v = 0x7777;
  bool has = SDL_GetJoystickAxisInitialState(j, axis, &v);
  L("initial axis %d has=%d value=%d", axis, (int)has, has ? v : 0);
}

int main(void)
{
  SDL_SetHint("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1");
  if (!SDL_Init(SDL_INIT_JOYSTICK)) { printf("INIT-ERR %s\n", SDL_GetError()); return 1; }
  /* 実機の機器は数えない */
  SDL_UpdateJoysticks(); drain();
  { int n = 0; SDL_JoystickID *ids = SDL_GetJoysticks(&n); SDL_free(ids); if (n) { printf("INIT-ERR real joysticks present: %d\n", n); return 1; } }

  section("attach");
  SDL_JoystickID a = attach("A", SDL_JOYSTICK_TYPE_UNKNOWN, 0x1234, 0x5678, 4, 4, 1, 1, NULL, true);
  info_for_id(a);
  ids_list("after A");
  update("added");

  section("open");
  SDL_Joystick *ja = SDL_OpenJoystick(a);
  L("open A axes=%d hats=%d buttons=%d connected=%d id=J%d", SDL_GetNumJoystickAxes(ja),
    SDL_GetNumJoystickHats(ja), SDL_GetNumJoystickButtons(ja), (int)SDL_JoystickConnected(ja), lab(SDL_GetJoystickID(ja)));
  LB("open A balls=%d", SDL_GetNumJoystickBalls(ja));
  { SDL_Joystick *again = SDL_OpenJoystick(a); L("open again same=%d", (int)(again == ja)); SDL_CloseJoystick(again);
    L("from id same=%d", (int)(SDL_GetJoystickFromID(a) == ja)); }
  state("initial", ja);

  section("axes");
  SDL_SetJoystickVirtualAxis(ja, 0, 20000); update("axis0=20000");
  SDL_SetJoystickVirtualAxis(ja, 0, 20000); update("axis0=20000 again");
  SDL_SetJoystickVirtualAxis(ja, 0, -5000); SDL_SetJoystickVirtualAxis(ja, 1, 32767); update("axis0=-5000 axis1=32767");
  SDL_SetJoystickVirtualAxis(ja, 2, -32768); update("axis2=-32768");
  SDL_SetJoystickVirtualAxis(ja, 2, 100); update("axis2=100");
  SDL_SetJoystickVirtualAxis(ja, 2, 30000); update("axis2=30000");
  SDL_SetJoystickVirtualAxis(ja, 3, 1); update("axis3=1");
  state("axes", ja);
  for (int i = 0; i < 4; i++) initial(ja, i);

  section("buttons");
  SDL_SetJoystickVirtualButton(ja, 0, true); SDL_SetJoystickVirtualButton(ja, 2, true); update("b0 b2 down");
  SDL_SetJoystickVirtualButton(ja, 0, false); update("b0 up");
  SDL_SetJoystickVirtualButton(ja, 2, true); update("b2 down again");
  state("buttons", ja);

  section("hats");
  SDL_SetJoystickVirtualHat(ja, 0, SDL_HAT_RIGHTUP); update("hat right-up");
  SDL_SetJoystickVirtualHat(ja, 0, SDL_HAT_RIGHTUP); update("hat right-up again");
  SDL_SetJoystickVirtualHat(ja, 0, SDL_HAT_LEFT); update("hat left");
  SDL_SetJoystickVirtualHat(ja, 0, SDL_HAT_CENTERED); update("hat centered");

  section("balls");
  /* SDL は仮想ジョイスティックの nballs を開いた機器へ写さないので、ボールは使えない（D-79）。LB の行は比べない */
  LB("set ball %d", (int)(SDL_SetJoystickVirtualBall(ja, 0, 5, -3) && SDL_SetJoystickVirtualBall(ja, 0, 2, 2)));
  update("ball 5,-3 + 2,2");
  { int dx = -1, dy = -1; bool ok = SDL_GetJoystickBall(ja, 0, &dx, &dy); LB("ball read ok=%d %d %d", (int)ok, dx, dy); }

  section("errors");
  L("axis range ok=%d", (int)SDL_SetJoystickVirtualAxis(ja, 4, 1));
  L("button range ok=%d", (int)SDL_SetJoystickVirtualButton(ja, 4, true));
  L("hat range ok=%d", (int)SDL_SetJoystickVirtualHat(ja, 1, 1));
  LB("ball range ok=%d", (int)SDL_SetJoystickVirtualBall(ja, 1, 1, 1));
  L("axis neg ok=%d", (int)SDL_SetJoystickVirtualAxis(ja, -1, 1));
  L("axis read %d", SDL_GetJoystickAxis(ja, 9));
  L("button read %d", (int)SDL_GetJoystickButton(ja, 9));
  L("hat read %d", SDL_GetJoystickHat(ja, 9));
  { Sint16 v; L("initial read ok=%d", (int)SDL_GetJoystickAxisInitialState(ja, 9, &v)); }
  L("open missing %d", (int)(SDL_OpenJoystick(9999) != NULL));
  L("name missing '%s'", SDL_GetJoystickNameForID(9999) ? "x" : "(null)");

  section("callbacks");
  L("rumble %d", (int)SDL_RumbleJoystick(ja, 100, 200, 1000));
  L("rumble same %d", (int)SDL_RumbleJoystick(ja, 100, 200, 1000));
  L("rumble other %d", (int)SDL_RumbleJoystick(ja, 300, 400, 0));
  L("rumble stop %d", (int)SDL_RumbleJoystick(ja, 0, 0, 0));
  L("triggers %d", (int)SDL_RumbleJoystickTriggers(ja, 10, 20, 500));
  L("led %d", (int)SDL_SetJoystickLED(ja, 1, 2, 3));
  L("led same %d", (int)SDL_SetJoystickLED(ja, 1, 2, 3));
  L("led other %d", (int)SDL_SetJoystickLED(ja, 1, 2, 4));
  { Uint8 data[3] = { 7, 8, 9 }; L("effect %d", (int)SDL_SendJoystickEffect(ja, data, 3)); }
  L("props rumble=%d led=%d trig=%d", (int)SDL_GetBooleanProperty(SDL_GetJoystickProperties(ja), SDL_PROP_JOYSTICK_CAP_RUMBLE_BOOLEAN, false),
    (int)SDL_GetBooleanProperty(SDL_GetJoystickProperties(ja), SDL_PROP_JOYSTICK_CAP_RGB_LED_BOOLEAN, false),
    (int)SDL_GetBooleanProperty(SDL_GetJoystickProperties(ja), SDL_PROP_JOYSTICK_CAP_TRIGGER_RUMBLE_BOOLEAN, false));

  section("initial extremes");
  { SDL_JoystickID c = attach("C", SDL_JOYSTICK_TYPE_UNKNOWN, 0x0c0c, 0x0c0d, 3, 1, 0, 0, NULL, false);
    update("C added");
    SDL_Joystick *jc = SDL_OpenJoystick(c);
    SDL_SetJoystickVirtualAxis(jc, 0, -32768); SDL_SetJoystickVirtualAxis(jc, 2, 32767); update("C axis0=-32768 axis2=32767");
    SDL_SetJoystickVirtualAxis(jc, 0, 100); update("C axis0=100");
    SDL_SetJoystickVirtualAxis(jc, 2, 20000); update("C axis2=20000");
    SDL_SetJoystickVirtualAxis(jc, 2, 5); update("C axis2=5");
    for (int i = 0; i < 3; i++) initial(jc, i);
    state("C", jc);
    SDL_CloseJoystick(jc);
    SDL_DetachVirtualJoystick(c); update("C removed"); }

  section("second device");
  SDL_JoystickID b = attach("B", SDL_JOYSTICK_TYPE_WHEEL, 0x0abc, 0x0def, 2, 2, 0, 0, "My Wheel", false);
  info_for_id(b);
  ids_list("after B");
  update("added B");
  SDL_Joystick *jb = SDL_OpenJoystick(b);
  L("open B axes=%d buttons=%d", SDL_GetNumJoystickAxes(jb), SDL_GetNumJoystickButtons(jb));
  initial(jb, 0);
  SDL_SetJoystickVirtualAxis(jb, 0, 50); update("B axis0=50 (2 axes: zero centered)");
  initial(jb, 0);
  L("rumble unsupported %d", (int)SDL_RumbleJoystick(jb, 1, 1, 0));
  L("led unsupported %d", (int)SDL_SetJoystickLED(jb, 1, 1, 1));
  L("effect unsupported %d", (int)SDL_SendJoystickEffect(jb, "x", 1));

  section("player index");
  L("set A=2 %d", (int)SDL_SetJoystickPlayerIndex(ja, 2));
  L("A player %d B player %d", SDL_GetJoystickPlayerIndex(ja), SDL_GetJoystickPlayerIndex(jb));
  L("from player 2 is A %d", (int)(SDL_GetJoystickFromPlayerIndex(2) == ja));
  L("set B=2 %d", (int)SDL_SetJoystickPlayerIndex(jb, 2));
  L("A player %d B player %d", SDL_GetJoystickPlayerIndex(ja), SDL_GetJoystickPlayerIndex(jb));
  L("set A=-1 %d", (int)SDL_SetJoystickPlayerIndex(ja, -1));
  L("A player %d B player %d", SDL_GetJoystickPlayerIndex(ja), SDL_GetJoystickPlayerIndex(jb));

  section("events disabled");
  SDL_SetJoystickEventsEnabled(false);
  L("enabled %d", (int)SDL_JoystickEventsEnabled());
  SDL_SetJoystickVirtualButton(ja, 1, true); update("b1 down (disabled)");
  state("after disabled", ja);
  { SDL_JoystickID d = attach("D", SDL_JOYSTICK_TYPE_UNKNOWN, 0x0d0d, 0x0e0e, 3, 1, 0, 0, NULL, false);
    update("D added (disabled)");
    SDL_SetJoystickEventsEnabled(true);
    L("enabled %d", (int)SDL_JoystickEventsEnabled());
    SDL_DetachVirtualJoystick(d); update("D removed (enabled)"); }
  SDL_SetJoystickVirtualButton(ja, 1, false); update("b1 up (enabled)");

  section("types by hint");
  SDL_SetHint("SDL_JOYSTICK_ARCADESTICK_DEVICES", "0x1234/0x5678");
  info_for_id(a);
  SDL_SetHint("SDL_JOYSTICK_FLIGHTSTICK_DEVICES", "0x1234/0x5678");
  info_for_id(a);      /* 両方の表にあれば、アーケードスティックが先 */
  SDL_SetHint("SDL_JOYSTICK_FLIGHTSTICK_DEVICES", NULL);
  SDL_SetHint("SDL_JOYSTICK_ARCADESTICK_DEVICES_EXCLUDED", "0x1234/0x5678");
  info_for_id(a);
  SDL_SetHint("SDL_JOYSTICK_ARCADESTICK_DEVICES", NULL);
  SDL_SetHint("SDL_JOYSTICK_ARCADESTICK_DEVICES_EXCLUDED", NULL);
  SDL_SetHint("SDL_JOYSTICK_FLIGHTSTICK_DEVICES", "0x1234/0x5678,0x0abc/0x0def");
  info_for_id(a); info_for_id(b);
  SDL_SetHint("SDL_JOYSTICK_FLIGHTSTICK_DEVICES", NULL);
  info_for_id(a);

  section("default names and types");
  { static const struct { Uint16 t; const char *tag; } ts[] = { { SDL_JOYSTICK_TYPE_WHEEL, "t1" }, { SDL_JOYSTICK_TYPE_ARCADE_STICK, "t2" },
      { SDL_JOYSTICK_TYPE_FLIGHT_STICK, "t3" }, { SDL_JOYSTICK_TYPE_DANCE_PAD, "t4" }, { SDL_JOYSTICK_TYPE_GUITAR, "t5" },
      { SDL_JOYSTICK_TYPE_DRUM_KIT, "t6" }, { SDL_JOYSTICK_TYPE_ARCADE_PAD, "t7" }, { SDL_JOYSTICK_TYPE_THROTTLE, "t8" } };
    SDL_JoystickID tid[8];
    for (int i = 0; i < 8; i++) { tid[i] = attach(ts[i].tag, ts[i].t, 0x0001 + i, 0x0002, 1, 1, 0, 0, NULL, false); info_for_id(tid[i]); }
    update("added types");
    for (int i = 0; i < 8; i++) SDL_DetachVirtualJoystick(tid[i]);
    update("removed types"); }

  section("bad descriptions");
  L("detach missing %d", (int)SDL_DetachVirtualJoystick(9999));
  L("is virtual missing %d", (int)SDL_IsJoystickVirtual(9999));

  section("refcount and close");
  { SDL_Joystick *x = SDL_OpenJoystick(a); L("open #2 same=%d", (int)(x == ja));
    SDL_CloseJoystick(x); L("closed once, from id valid=%d", (int)(SDL_GetJoystickFromID(a) != NULL)); }

  section("detach while open");
  SDL_SetJoystickVirtualAxis(ja, 0, 12345); SDL_SetJoystickVirtualButton(ja, 3, true); SDL_SetJoystickVirtualHat(ja, 0, SDL_HAT_DOWN); update("set before detach");
  state("before detach", ja);
  L("detach A %d", (int)SDL_DetachVirtualJoystick(a));
  update("detached A");
  state("after detach", ja);
  ids_list("after detach");
  L("from id still %d", (int)(SDL_GetJoystickFromID(a) != NULL));
  SDL_CloseJoystick(ja);
  L("from id after close %d", (int)(SDL_GetJoystickFromID(a) != NULL));
  L("rumble stop on close ok");
  SDL_CloseJoystick(jb);
  SDL_DetachVirtualJoystick(b);
  update("detached B");
  ids_list("end");

  SDL_Quit();
  return 0;
}
