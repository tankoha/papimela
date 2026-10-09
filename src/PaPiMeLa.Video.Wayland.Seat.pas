{
  PaPiMeLa.Video.Wayland.Seat — wl_seat（キーボード / ポインタ / タッチ）

  Origin : partially ported from SDL (src/video/wayland/SDL_waylandevents.c,
           src/video/wayland/SDL_waylandkeyboard.c)
           Scope: キーマップを fd から mmap して xkb に渡す手順、evdev ボタン番号の
           対応、キーリピートをクライアント側で生成する必要があるという知見。
           構造は本設計に従う。text_input_* は含まない（#49 へ）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.2、§7.5、§11 #37

  WHAT:
    wl_seat から wl_keyboard / wl_pointer / wl_touch を取り出し、xkb でキーコードを
    キーシムと文字へ変換して、イベントキューの状態機械へ流す。

  WHY:
    Wayland はキーコードしか送らない。文字も修飾キーもクライアントが求める。
    キーリピートもコンポジタは送ってこず、repeat_info で通知されたレートに
    従ってクライアントが生成する。

  RESOLVED:
    - 生成リスナーは抽象クラスなので 1 クラスで seat / keyboard / pointer / touch を
      同時に継承できない。転送用の内部クラスを置いて実体へ委譲する
    - サーフェスからウィンドウを引くのは wl_proxy_get_user_data。
      ウィンドウ backend が自分自身を設定しておく
    - キーは押下も解放も IME に通す。修飾キー単独押下もエンジンがモード切替に
      使うため通す（§7.5）

  NOT RESOLVED:
    - タッチは押下・移動・解放・取り消しだけ。shape / orientation（接触面の
      大きさと向き）は受け取っていない
    - ポインタ拘束は PaPiMeLa.Video.Wayland.PointerGrab に分けた。ここはフォーカスと
      直近位置を渡すだけ
    - カーソル形状は PaPiMeLa.Video.Wayland.Cursor に分けた。ここは serial を
      持っているので、実際の set_shape / set_cursor だけを引き受ける
    - Scancode（USB HID Usage 準拠）への変換は未実装。現状は evdev コードと
      キーシムのみを載せる

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Wayland.Seat;

{$I papimela.inc}

interface

uses
  SysUtils, BaseUnix,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Events,
  PaPiMeLa.Events.Keymap,
  PaPiMeLa.Platform.XKB,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland,
  PaPiMeLa.Platform.Wayland.Protocols.CursorShapeV1,
  PaPiMeLa.Platform.Wayland.Protocols.TabletV2,
  PaPiMeLa.Video.Wayland.Types,
  PaPiMeLa.Video.Wayland.Window,
  PaPiMeLa.Video.Wayland.PointerGrab;

type
  TPMLWaylandSeat = class;

  // 入力に伴う serial が更新されたときに呼ばれる（クリップボードの set_selection が使う）。
  TPMLWaylandSerialProc = procedure(ASerial: LongWord) of object;

  TPMLWaylandKeyboardFwd = class(Twl_keyboard_listener)
  strict private
    FOwner: TPMLWaylandSeat;
  public
    constructor Create(AOwner: TPMLWaylandSeat);
    procedure keymap(AProxy: Pwl_keyboard; format: LongWord; fd: LongInt;
      size: LongWord); override;
    procedure enter(AProxy: Pwl_keyboard; serial: LongWord; surface: Pwl_surface;
      keys: Pwl_array); override;
    procedure leave(AProxy: Pwl_keyboard; serial: LongWord;
      surface: Pwl_surface); override;
    procedure key(AProxy: Pwl_keyboard; serial: LongWord; time: LongWord;
      key_: LongWord; state: LongWord); override;
    procedure modifiers(AProxy: Pwl_keyboard; serial: LongWord;
      mods_depressed: LongWord; mods_latched: LongWord; mods_locked: LongWord;
      group: LongWord); override;
    procedure repeat_info(AProxy: Pwl_keyboard; rate: LongInt;
      delay: LongInt); override;
  end;

  TPMLWaylandPointerFwd = class(Twl_pointer_listener)
  strict private
    FOwner: TPMLWaylandSeat;
  public
    constructor Create(AOwner: TPMLWaylandSeat);
    procedure enter(AProxy: Pwl_pointer; serial: LongWord; surface: Pwl_surface;
      surface_x: wl_fixed_t; surface_y: wl_fixed_t); override;
    procedure leave(AProxy: Pwl_pointer; serial: LongWord;
      surface: Pwl_surface); override;
    procedure motion(AProxy: Pwl_pointer; time: LongWord;
      surface_x: wl_fixed_t; surface_y: wl_fixed_t); override;
    procedure button(AProxy: Pwl_pointer; serial: LongWord; time: LongWord;
      button_: LongWord; state: LongWord); override;
    procedure axis(AProxy: Pwl_pointer; time: LongWord; axis_: LongWord;
      value: wl_fixed_t); override;
  end;

  TPMLWaylandTouchFwd = class(Twl_touch_listener)
  strict private
    FOwner: TPMLWaylandSeat;
  public
    constructor Create(AOwner: TPMLWaylandSeat);
    procedure down(AProxy: Pwl_touch; serial: LongWord; time: LongWord;
      surface: Pwl_surface; id: LongInt; x: wl_fixed_t; y: wl_fixed_t); override;
    procedure up(AProxy: Pwl_touch; serial: LongWord; time: LongWord;
      id: LongInt); override;
    procedure motion(AProxy: Pwl_touch; time: LongWord; id: LongInt;
      x: wl_fixed_t; y: wl_fixed_t); override;
    procedure cancel(AProxy: Pwl_touch); override;
  end;

  TPMLWaylandSeat = class(Twl_seat_listener)
  strict private
    FQueue    : TPMLEventQueue;
    FConn     : TPMLWaylandConnection;
    FSeat     : Pwl_seat;
    FKeyboard : Pwl_keyboard;
    FPointer  : Pwl_pointer;
    FKbdFwd   : TPMLWaylandKeyboardFwd;
    FPtrFwd   : TPMLWaylandPointerFwd;
    FTouch    : Pwl_touch;
    FTouchFwd : TPMLWaylandTouchFwd;
    FXKB      : TPMLXKBState;
    FGrab     : TPMLWaylandPointerGrab;
    FName     : String;

    FKeyFocus : TPMLWindowID;
    FPtrFocus : TPMLWindowID;
    FPtrSerial: LongWord;      // 直近の wl_pointer.enter の serial。set_cursor に要る
    // 直近の入力（キーボードの enter / キー、ポインタのボタン押下、タッチの down）の
    // serial。set_selection に要る。SDL の last_implicit_grab_serial に当たる。
    FInputSerial  : LongWord;
    FOnInputSerial: TPMLWaylandSerialProc;
    FTouchDeviceID: LongWord;  // wl_touch はシートに 1 つ。シートを識別子にする

    // カーソル形状（cursor-shape-v1）。要求は TPMLWaylandCursorBackend から来る。
    FCursorDev    : Pwp_cursor_shape_device_v1;
    FCursorShape  : LongWord;
    FCursorVisible: Boolean;

    // キーリピート（コンポジタは送ってこない。クライアントが生成する）
    FRepeatRate : Integer;    // 1 秒あたりの回数。0 = リピートしない
    FRepeatDelay: Integer;    // 初回までの遅延（ミリ秒）
    FRepeatKey  : LongWord;   // evdev コード。0 = リピート中でない
    FRepeatNext : UInt64;     // 次に発火する時刻（ナノ秒）
    FRepeatText : String;

    procedure StopRepeat;
    function  GetHasKeyboard: Boolean;
    function  GetHasTouch: Boolean;
    function  GetHasKeyFocus: Boolean;
    procedure ReapplyCursor;
    function  WindowOf(ASurface: Pwl_surface): TPMLWaylandWindowBackend;
    procedure DeliverKey(AEvdevCode: LongWord; ADown, AIsRepeat: Boolean);
    procedure NotifyKeyFocusToGrab;
  private
    procedure NoteInputSerial(ASerial: LongWord);
    procedure HandleKeymap(AFormat: LongWord; AFD: LongInt; ASize: LongWord);
    procedure HandleKeyEnter(ASurface: Pwl_surface);
    procedure HandleKeyLeave(ASurface: Pwl_surface);
    procedure HandleKey(AEvdevCode: LongWord; ADown: Boolean);
    procedure HandleModifiers(ADepressed, ALatched, ALocked, AGroup: LongWord);
    procedure HandleRepeatInfo(ARate, ADelay: Integer);
    procedure HandlePointerEnter(ASerial: LongWord; ASurface: Pwl_surface;
      AX, AY: wl_fixed_t);
    procedure HandlePointerLeave(ASurface: Pwl_surface);
    procedure HandlePointerMotion(AX, AY: wl_fixed_t);
    procedure HandlePointerButton(AButton: LongWord; ADown: Boolean);
    procedure HandlePointerAxis(AAxis: LongWord; AValue: wl_fixed_t);
    procedure HandleTouchDown(ASurface: Pwl_surface; AID: LongInt;
      AX, AY: wl_fixed_t);
    procedure HandleTouchUp(AID: LongInt);
    procedure HandleTouchMotion(AID: LongInt; AX, AY: wl_fixed_t);
    procedure HandleTouchCancel;
  public
    // ADeviceID は入力デバイスの識別子。所有者が連番で振る（wl_touch はシートに
    // 1 つなので、シートの識別子がそのままタッチデバイスの識別子になる）。
    constructor Create(AQueue: TPMLEventQueue; AConn: TPMLWaylandConnection;
      ASeat: Pwl_seat; ADeviceID: LongWord);
    destructor Destroy; override;

    procedure capabilities(AProxy: Pwl_seat; capabilities_: LongWord); override;
    procedure name(AProxy: Pwl_seat; name_: PAnsiChar); override;

    // ビデオバックエンドの Pump から呼ぶ。期限が来たリピートを発火させる。
    procedure ProcessRepeat;
    // ウィンドウの拘束要求が変わったときに Video.Wayland から呼ばれる。
    // AWindowID = 0 は「どのウィンドウか分からないので必ず見直せ」。
    procedure UpdateGrabs(AWindowID: TPMLWindowID);
    // カーソル部品（TPMLWaylandCursorBackend）から呼ばれる。要求を覚えて即適用し、
    // 次に wl_pointer.enter が来たときにも同じ形を張り直す。
    procedure ApplyCursor(AShape: LongWord; AVisible: Boolean);
    // サーフェスを持つウィンドウの ID（user_data のウィンドウ backend から引く）。
    // 解決できなければ 0。データデバイス（ドラッグ＆ドロップ）が使う。
    function  WindowIDOf(ASurface: Pwl_surface): TPMLWindowID;
    // 次のリピートまでの残り時間（ミリ秒）。リピート中でなければ -1。
    function  MillisecondsUntilRepeat: Integer;

    // イベントを流す先。データデバイスがドロップのイベントを流すのに使う。
    property Queue: TPMLEventQueue read FQueue;
    property SeatName: String read FName;
    // 生の wl_seat。データデバイスのようにシートから作るものが使う。
    property Handle: Pwl_seat read FSeat;
    // 直近の入力の serial（まだ入力が無ければ 0）。
    property InputSerial: LongWord read FInputSerial;
    property OnInputSerial: TPMLWaylandSerialProc read FOnInputSerial write FOnInputSerial;
    property HasKeyboard: Boolean read GetHasKeyboard;
    // いまキーボードフォーカスがこのシートのウィンドウにあるか。
    property HasKeyFocus: Boolean read GetHasKeyFocus;
    property HasTouch: Boolean read GetHasTouch;
    // ポインタ拘束。ポインタが無いシートでは nil。
    property Grab: TPMLWaylandPointerGrab read FGrab;
  end;
  TPMLWaylandSeats = array of TPMLWaylandSeat;

implementation

const
  // evdev のボタン番号
  BTN_LEFT   = $110;
  BTN_RIGHT  = $111;
  BTN_MIDDLE = $112;

{ 転送クラス }

constructor TPMLWaylandKeyboardFwd.Create(AOwner: TPMLWaylandSeat);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TPMLWaylandKeyboardFwd.keymap(AProxy: Pwl_keyboard; format: LongWord;
  fd: LongInt; size: LongWord);
begin
  FOwner.HandleKeymap(format, fd, size);
end;

procedure TPMLWaylandKeyboardFwd.enter(AProxy: Pwl_keyboard; serial: LongWord;
  surface: Pwl_surface; keys: Pwl_array);
begin
  FOwner.NoteInputSerial(serial);
  FOwner.HandleKeyEnter(surface);
end;

procedure TPMLWaylandKeyboardFwd.leave(AProxy: Pwl_keyboard; serial: LongWord;
  surface: Pwl_surface);
begin
  FOwner.HandleKeyLeave(surface);
end;

procedure TPMLWaylandKeyboardFwd.key(AProxy: Pwl_keyboard; serial: LongWord;
  time: LongWord; key_: LongWord; state: LongWord);
begin
  FOwner.NoteInputSerial(serial);
  FOwner.HandleKey(key_, state = WL_KEYBOARD_KEY_STATE_PRESSED);
end;

procedure TPMLWaylandKeyboardFwd.modifiers(AProxy: Pwl_keyboard; serial: LongWord;
  mods_depressed: LongWord; mods_latched: LongWord; mods_locked: LongWord;
  group: LongWord);
begin
  FOwner.HandleModifiers(mods_depressed, mods_latched, mods_locked, group);
end;

procedure TPMLWaylandKeyboardFwd.repeat_info(AProxy: Pwl_keyboard;
  rate: LongInt; delay: LongInt);
begin
  FOwner.HandleRepeatInfo(rate, delay);
end;

constructor TPMLWaylandPointerFwd.Create(AOwner: TPMLWaylandSeat);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TPMLWaylandPointerFwd.enter(AProxy: Pwl_pointer; serial: LongWord;
  surface: Pwl_surface; surface_x: wl_fixed_t; surface_y: wl_fixed_t);
begin
  FOwner.HandlePointerEnter(serial, surface, surface_x, surface_y);
end;

procedure TPMLWaylandPointerFwd.leave(AProxy: Pwl_pointer; serial: LongWord;
  surface: Pwl_surface);
begin
  FOwner.HandlePointerLeave(surface);
end;

procedure TPMLWaylandPointerFwd.motion(AProxy: Pwl_pointer; time: LongWord;
  surface_x: wl_fixed_t; surface_y: wl_fixed_t);
begin
  FOwner.HandlePointerMotion(surface_x, surface_y);
end;

procedure TPMLWaylandPointerFwd.button(AProxy: Pwl_pointer; serial: LongWord;
  time: LongWord; button_: LongWord; state: LongWord);
begin
  // 押下だけ（SDL と同じ）。離したときの serial は選択の根拠にしない。
  if state = 1 then
    FOwner.NoteInputSerial(serial);
  FOwner.HandlePointerButton(button_, state = 1);
end;

procedure TPMLWaylandPointerFwd.axis(AProxy: Pwl_pointer; time: LongWord;
  axis_: LongWord; value: wl_fixed_t);
begin
  FOwner.HandlePointerAxis(axis_, value);
end;


constructor TPMLWaylandTouchFwd.Create(AOwner: TPMLWaylandSeat);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TPMLWaylandTouchFwd.down(AProxy: Pwl_touch; serial: LongWord;
  time: LongWord; surface: Pwl_surface; id: LongInt; x: wl_fixed_t;
  y: wl_fixed_t);
begin
  FOwner.NoteInputSerial(serial);
  FOwner.HandleTouchDown(surface, id, x, y);
end;

procedure TPMLWaylandTouchFwd.up(AProxy: Pwl_touch; serial: LongWord;
  time: LongWord; id: LongInt);
begin
  FOwner.HandleTouchUp(id);
end;

procedure TPMLWaylandTouchFwd.motion(AProxy: Pwl_touch; time: LongWord;
  id: LongInt; x: wl_fixed_t; y: wl_fixed_t);
begin
  FOwner.HandleTouchMotion(id, x, y);
end;

procedure TPMLWaylandTouchFwd.cancel(AProxy: Pwl_touch);
begin
  FOwner.HandleTouchCancel;
end;

// wl_touch.frame は「この一連の変化はここまで」の区切り。papimela は指ごとに
// その場でイベントを出すのでまとめる必要がなく、既定の空実装のままにしてある。

{ TPMLWaylandSeat }

constructor TPMLWaylandSeat.Create(AQueue: TPMLEventQueue;
  AConn: TPMLWaylandConnection; ASeat: Pwl_seat; ADeviceID: LongWord);
begin
  inherited Create;
  FQueue := AQueue;
  FConn := AConn;
  FSeat := ASeat;
  FXKB := TPMLXKBState.Create;
  FRepeatRate := 25;
  FRepeatDelay := 600;
  FCursorVisible := True;
  FTouchDeviceID := ADeviceID;
  wl_seat_add_listener_object(FSeat, Self);
end;

destructor TPMLWaylandSeat.Destroy;
begin
  // 拘束は wl_pointer より先に捨てる。ポインタを解放したあとに拘束オブジェクトを
  // 破棄する順序はプロトコル上あいまいなので、依存する側から畳む。
  FreeAndNil(FGrab);
  if FCursorDev <> nil then
    wp_cursor_shape_device_v1_destroy(FCursorDev);
  if FKeyboard <> nil then
    wl_keyboard_release(FKeyboard);
  if FPointer <> nil then
    wl_pointer_release(FPointer);
  if FTouch <> nil then
    wl_touch_release(FTouch);
  FreeAndNil(FKbdFwd);
  FreeAndNil(FPtrFwd);
  FreeAndNil(FTouchFwd);
  FreeAndNil(FXKB);
  inherited Destroy;
end;

function TPMLWaylandSeat.GetHasKeyboard: Boolean;
begin
  Result := FKeyboard <> nil;
end;

function TPMLWaylandSeat.GetHasKeyFocus: Boolean;
begin
  Result := FKeyFocus <> 0;
end;

function TPMLWaylandSeat.GetHasTouch: Boolean;
begin
  Result := FTouch <> nil;
end;

{ 入力の serial を覚える。大きくなったときだけ更新して知らせる（SDL の
  Wayland_UpdateImplicitGrabSerial）。

  PORT-NOTE: SDL は wl_keyboard.enter の serial を覚えない（キー・ボタン押下・タッチだけ）。
  papimela は enter の serial も覚える。フォーカスを得た直後（まだ何も押していない）に
  クリップボードへ置いても、選択を保留にせず送れるようにするため。 }
procedure TPMLWaylandSeat.NoteInputSerial(ASerial: LongWord);
begin
  if ASerial <= FInputSerial then
    Exit;
  FInputSerial := ASerial;
  if Assigned(FOnInputSerial) then
    FOnInputSerial(ASerial);
end;

{ ---- カーソル形状（cursor-shape-v1） ---- }

{ 覚えている形状を今の serial で張り直す。

  set_shape も set_cursor も wl_pointer.enter の serial を要求する。enter を
  まだ受けていない（= カーソルがウィンドウの上にない）場合は何もできないので、
  次の enter で呼び直す。 }
procedure TPMLWaylandSeat.ReapplyCursor;
begin
  if (FPointer = nil) or (FPtrSerial = 0) then
    Exit;
  if not FCursorVisible then
  begin
    // サーフェスを渡さない set_cursor が「カーソルを消す」の意味になる。
    wl_pointer_set_cursor(FPointer, FPtrSerial, nil, 0, 0);
    Exit;
  end;
  if (FCursorDev <> nil) and (FCursorShape <> 0) then
    wp_cursor_shape_device_v1_set_shape(FCursorDev, FPtrSerial, FCursorShape);
end;

procedure TPMLWaylandSeat.ApplyCursor(AShape: LongWord; AVisible: Boolean);
begin
  FCursorShape := AShape;
  FCursorVisible := AVisible;
  ReapplyCursor;
end;

{ ---- wl_touch ---- }

procedure TPMLWaylandSeat.HandleTouchDown(ASurface: Pwl_surface; AID: LongInt;
  AX, AY: wl_fixed_t);
var
  ID: TPMLWindowID;
begin
  ID := WindowIDOf(ASurface);
  if ID = 0 then
    Exit;
  // デバイス識別子はシートごとに 1 つ。wl_touch は seat に 1 つしかない。
  FQueue.Touch.SendDown(ID, FTouchDeviceID, Int32(AID),
    PMLFixedToSingle(AX), PMLFixedToSingle(AY));
end;

procedure TPMLWaylandSeat.HandleTouchUp(AID: LongInt);
begin
  FQueue.Touch.SendUp(FTouchDeviceID, Int32(AID));
end;

procedure TPMLWaylandSeat.HandleTouchMotion(AID: LongInt; AX, AY: wl_fixed_t);
begin
  FQueue.Touch.SendMotion(FTouchDeviceID, Int32(AID),
    PMLFixedToSingle(AX), PMLFixedToSingle(AY));
end;

procedure TPMLWaylandSeat.HandleTouchCancel;
begin
  FQueue.Touch.SendCancel(FTouchDeviceID);
end;

procedure TPMLWaylandSeat.capabilities(AProxy: Pwl_seat; capabilities_: LongWord);
begin
  if ((capabilities_ and WL_SEAT_CAPABILITY_KEYBOARD) <> 0) and (FKeyboard = nil) then
  begin
    FKeyboard := wl_seat_get_keyboard(FSeat);
    FKbdFwd := TPMLWaylandKeyboardFwd.Create(Self);
    wl_keyboard_add_listener_object(FKeyboard, FKbdFwd);
  end
  else if ((capabilities_ and WL_SEAT_CAPABILITY_KEYBOARD) = 0) and (FKeyboard <> nil) then
  begin
    wl_keyboard_release(FKeyboard);
    FKeyboard := nil;
    FreeAndNil(FKbdFwd);
    StopRepeat;
  end;

  if ((capabilities_ and WL_SEAT_CAPABILITY_POINTER) <> 0) and (FPointer = nil) then
  begin
    FPointer := wl_seat_get_pointer(FSeat);
    FPtrFwd := TPMLWaylandPointerFwd.Create(Self);
    wl_pointer_add_listener_object(FPointer, FPtrFwd);
    FGrab := TPMLWaylandPointerGrab.Create(FConn, FQueue, FPointer);
    // カーソル形状の装置はポインタごと。無い環境では nil のままで、
    // 表示 / 非表示（set_cursor）だけが使える。
    if FConn.CursorShapeMgr <> nil then
      FCursorDev := wp_cursor_shape_manager_v1_get_pointer(FConn.CursorShapeMgr,
        FPointer);
  end
  else if ((capabilities_ and WL_SEAT_CAPABILITY_POINTER) = 0) and (FPointer <> nil) then
  begin
    FreeAndNil(FGrab);
    if FCursorDev <> nil then
    begin
      wp_cursor_shape_device_v1_destroy(FCursorDev);
      FCursorDev := nil;
    end;
    wl_pointer_release(FPointer);
    FPointer := nil;
    FPtrSerial := 0;
    FreeAndNil(FPtrFwd);
  end;

  if ((capabilities_ and WL_SEAT_CAPABILITY_TOUCH) <> 0) and (FTouch = nil) then
  begin
    FTouch := wl_seat_get_touch(FSeat);
    FTouchFwd := TPMLWaylandTouchFwd.Create(Self);
    wl_touch_add_listener_object(FTouch, FTouchFwd);
  end
  else if ((capabilities_ and WL_SEAT_CAPABILITY_TOUCH) = 0) and (FTouch <> nil) then
  begin
    // 触っている指が残っていると押されたままになる。先に全部落とす。
    FQueue.Touch.SendCancel(FTouchDeviceID);
    wl_touch_release(FTouch);
    FTouch := nil;
    FreeAndNil(FTouchFwd);
  end;
  // 相対モードと閉じ込めの判定はキーボードフォーカスを見る。このシートに
  // キーボードがあるかどうかで規則が変わるので、拘束側へ伝えておく（§3.2）。
  if FGrab <> nil then
    FGrab.HasKeyboard := FKeyboard <> nil;
end;

procedure TPMLWaylandSeat.name(AProxy: Pwl_seat; name_: PAnsiChar);
begin
  FName := String(name_);
end;

{ サーフェスからウィンドウバックエンドを引く。ウィンドウ backend が自分自身を
  user_data に入れている。破棄済みのサーフェスでは nil になる。 }
function TPMLWaylandSeat.WindowOf(ASurface: Pwl_surface): TPMLWaylandWindowBackend;
var
  Obj: TObject;
begin
  Result := nil;
  if ASurface = nil then
    Exit;
  Obj := TObject(wl_proxy_get_user_data(Pwl_proxy(ASurface)));
  if Obj is TPMLWaylandWindowBackend then
    Result := TPMLWaylandWindowBackend(Obj);
end;

function TPMLWaylandSeat.WindowIDOf(ASurface: Pwl_surface): TPMLWindowID;
var
  W: TPMLWaylandWindowBackend;
begin
  W := WindowOf(ASurface);
  if W = nil then
    Result := 0
  else
    Result := W.WindowID;
end;

{ キーマップは fd で渡ってくる。mmap してヌル終端文字列として読む。 }
procedure TPMLWaylandSeat.HandleKeymap(AFormat: LongWord; AFD: LongInt;
  ASize: LongWord);
var
  Map : Pointer;
  Text: String;
begin
  if AFormat <> WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1 then
  begin
    FpClose(AFD);
    Exit;
  end;
  Map := Fpmmap(nil, ASize, PROT_READ, MAP_PRIVATE, AFD, 0);
  if (Map = nil) or (Map = Pointer(-1)) then
  begin
    FpClose(AFD);
    Exit;
  end;
  try
    // ASize はヌル終端を含む長さ。
    Text := String(PAnsiChar(Map));
    if not FXKB.LoadKeymap(Text) then
      Exit;
    // スキャンコード → キーコードの表を作り直す。KeymapChanged はこの中で積まれる。
    FQueue.Keyboard.SetKeymap(FXKB.BuildKeymap);
  finally
    Fpmunmap(Map, ASize);
    FpClose(AFD);
  end;
end;

procedure TPMLWaylandSeat.HandleKeyEnter(ASurface: Pwl_surface);
begin
  FKeyFocus := WindowIDOf(ASurface);
  // 閉じ込めと相対モードはキーボードフォーカスの有無で成立が変わる（§3.2）。
  NotifyKeyFocusToGrab;
  if FKeyFocus <> 0 then
    FQueue.Keyboard.SendFocus(FKeyFocus, True);
end;

{ wl_keyboard.leave はフォーカスを失ったことを意味する。サーフェスが解決できなくても
  （既に破棄されている、user_data が無い等）失ったことに変わりはないので、
  直前に持っていたフォーカスを使って必ず通知する。

  ここを「解決できたときだけ通知する」にしていると、IME にフォーカス喪失が
  届かないまま別アプリへ移る経路ができる（D-22 と同じ症状になる）。 }
procedure TPMLWaylandSeat.HandleKeyLeave(ASurface: Pwl_surface);
var
  ID: TPMLWindowID;
begin
  StopRepeat;
  ID := WindowIDOf(ASurface);
  if ID = 0 then
    ID := FKeyFocus;
  FKeyFocus := 0;
  NotifyKeyFocusToGrab;
  if ID <> 0 then
    FQueue.Keyboard.SendFocus(ID, False);
end;

procedure TPMLWaylandSeat.DeliverKey(AEvdevCode: LongWord; ADown, AIsRepeat: Boolean);
var
  K: TPMLKeyEventData;
  Text: String;
begin
  FillChar(K, SizeOf(K), 0);
  K.Scancode := PMLScancodeFromEvdev(AEvdevCode);
  // K.Key は TPMLKeyboardState が今のキーマップから決める。
  K.Keysym := FXKB.KeysymOf(AEvdevCode);
  K.Raw := AEvdevCode + XKB_EVDEV_OFFSET;
  K.Modifiers := FXKB.Modifiers;
  K.IsRepeat := AIsRepeat;

  Text := '';
  if ADown then
    Text := FXKB.TextOf(AEvdevCode);
  // 制御文字は確定文字列にしない（Enter / Tab / Backspace など）。
  if (Length(Text) = 1) and (Text[1] < #32) then
    Text := '';

  FQueue.Keyboard.SendKey(FKeyFocus, K, ADown, Text);
end;

procedure TPMLWaylandSeat.HandleKey(AEvdevCode: LongWord; ADown: Boolean);
begin
  DeliverKey(AEvdevCode, ADown, False);

  if ADown then
  begin
    if (FRepeatRate > 0) and FXKB.Repeats(AEvdevCode) then
    begin
      FRepeatKey := AEvdevCode;
      FRepeatNext := PMLNowNS + UInt64(FRepeatDelay) * 1000000;
    end
    else
      StopRepeat;
  end
  else if FRepeatKey = AEvdevCode then
    StopRepeat;
end;

procedure TPMLWaylandSeat.HandleModifiers(ADepressed, ALatched, ALocked,
  AGroup: LongWord);
var
  OldGroup: LongWord;
begin
  OldGroup := FXKB.Group;
  FXKB.UpdateMask(ADepressed, ALatched, ALocked, AGroup);
  // 配列が切り替わった（例: us と ru を切り替えて使う設定）。キーマップを作り直す。
  if FXKB.Group <> OldGroup then
    FQueue.Keyboard.SetKeymap(FXKB.BuildKeymap);
  FQueue.Keyboard.SendModifiers(FXKB.Modifiers);
end;

procedure TPMLWaylandSeat.HandleRepeatInfo(ARate, ADelay: Integer);
begin
  FRepeatRate := ARate;
  FRepeatDelay := ADelay;
  if ARate = 0 then
    StopRepeat;
end;

procedure TPMLWaylandSeat.StopRepeat;
begin
  FRepeatKey := 0;
  FRepeatNext := 0;
  FRepeatText := '';
end;

procedure TPMLWaylandSeat.ProcessRepeat;
var
  Now_: UInt64;
begin
  if (FRepeatKey = 0) or (FRepeatRate <= 0) then
    Exit;
  Now_ := PMLNowNS;
  while (FRepeatKey <> 0) and (Now_ >= FRepeatNext) do
  begin
    DeliverKey(FRepeatKey, True, True);
    FRepeatNext := FRepeatNext + UInt64(1000000000 div FRepeatRate);
  end;
end;

function TPMLWaylandSeat.MillisecondsUntilRepeat: Integer;
var
  Now_: UInt64;
begin
  if (FRepeatKey = 0) or (FRepeatRate <= 0) then
    Exit(-1);
  Now_ := PMLNowNS;
  if Now_ >= FRepeatNext then
    Exit(0);
  Result := Integer((FRepeatNext - Now_) div 1000000) + 1;
end;

{ キーボードフォーカスを拘束側へ渡して、拘束を張り直させる。 }
procedure TPMLWaylandSeat.NotifyKeyFocusToGrab;
begin
  if FGrab = nil then
    Exit;
  FGrab.SetKeyboardFocus(FKeyFocus);
  FGrab.Update;
end;

procedure TPMLWaylandSeat.UpdateGrabs(AWindowID: TPMLWindowID);
begin
  if FGrab = nil then
    Exit;
  // 関係のないウィンドウの変化で張り替えると、無駄な破棄と再生成が起きる。
  if (AWindowID <> 0) and (AWindowID <> FPtrFocus) then
    Exit;
  FGrab.Update;
end;

procedure TPMLWaylandSeat.HandlePointerEnter(ASerial: LongWord;
  ASurface: Pwl_surface; AX, AY: wl_fixed_t);
var
  W: TPMLWaylandWindowBackend;
  X, Y: Single;
begin
  // set_cursor と set_shape はこの serial を要求する。カーソルの張り直しにも使う。
  FPtrSerial := ASerial;
  ReapplyCursor;
  W := WindowOf(ASurface);
  if W = nil then
  begin
    FPtrFocus := 0;
    if FGrab <> nil then
      FGrab.SetPointerFocus(nil);
    Exit;
  end;

  FPtrFocus := W.WindowID;
  X := PMLFixedToSingle(AX);
  Y := PMLFixedToSingle(AY);
  if FGrab <> nil then
  begin
    FGrab.SetPointerFocus(W);
    FGrab.NoteMotion(X, Y);
    FGrab.Update;
  end;
  FQueue.Mouse.SendFocus(FPtrFocus, True);
  FQueue.Mouse.SendMotion(FPtrFocus, X, Y);
end;

{ wl_pointer.leave。HandleKeyLeave と同じ理由で、サーフェスが解決できなくても
  直前のフォーカスを使って通知する（D-23）。拘束もここで捨てる。 }
procedure TPMLWaylandSeat.HandlePointerLeave(ASurface: Pwl_surface);
var
  ID: TPMLWindowID;
begin
  ID := WindowIDOf(ASurface);
  if ID = 0 then
    ID := FPtrFocus;
  FPtrFocus := 0;
  // serial は enter のときだけ有効。離れたあとに set_cursor を送っても
  // コンポジタは無視するので、無駄な要求を出さないよう捨てる。
  FPtrSerial := 0;
  if FGrab <> nil then
    FGrab.SetPointerFocus(nil);
  if ID <> 0 then
    FQueue.Mouse.SendFocus(ID, False);
end;

procedure TPMLWaylandSeat.HandlePointerMotion(AX, AY: wl_fixed_t);
var
  X, Y: Single;
begin
  if FPtrFocus = 0 then
    Exit;
  X := PMLFixedToSingle(AX);
  Y := PMLFixedToSingle(AY);
  // 閉じ込め矩形へ引き寄せるときに直近位置が要る。ロック中はこの経路が来ない。
  if FGrab <> nil then
    FGrab.NoteMotion(X, Y);
  FQueue.Mouse.SendMotion(FPtrFocus, X, Y);
end;

procedure TPMLWaylandSeat.HandlePointerButton(AButton: LongWord; ADown: Boolean);
var
  N: LongWord;
begin
  case AButton of
    BTN_LEFT  : N := 1;
    BTN_RIGHT : N := 2;
    BTN_MIDDLE: N := 3;
  else
    N := 0;
  end;
  if (N <> 0) and (FPtrFocus <> 0) then
    FQueue.Mouse.SendButton(FPtrFocus, N, ADown);
end;

procedure TPMLWaylandSeat.HandlePointerAxis(AAxis: LongWord; AValue: wl_fixed_t);
var
  V: Single;
begin
  if FPtrFocus = 0 then
    Exit;
  // 表面座標での移動量。ノッチ換算は 10 単位を 1 とする（SDL と同じ目安）。
  V := PMLFixedToSingle(AValue) / 10.0;
  if AAxis = WL_POINTER_AXIS_VERTICAL_SCROLL then
    FQueue.Mouse.SendWheel(FPtrFocus, 0, -V)
  else
    FQueue.Mouse.SendWheel(FPtrFocus, -V, 0);
end;

end.
