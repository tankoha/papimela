{
  PaPiMeLa.Video.Wayland.Seat — wl_seat（キーボード / ポインタ）

  Origin : partially ported from SDL (src/video/wayland/SDL_waylandevents.c,
           src/video/wayland/SDL_waylandkeyboard.c)
           Scope: キーマップを fd から mmap して xkb に渡す手順、evdev ボタン番号の
           対応、キーリピートをクライアント側で生成する必要があるという知見。
           構造は本設計に従う。text_input_* は含まない（#49 へ）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.2、§7.5、§11 #37

  WHAT:
    wl_seat から wl_keyboard と wl_pointer を取り出し、xkb でキーコードを
    キーシムと文字へ変換して、イベントキューの状態機械へ流す。

  WHY:
    Wayland はキーコードしか送らない。文字も修飾キーもクライアントが求める。
    キーリピートもコンポジタは送ってこず、repeat_info で通知されたレートに
    従ってクライアントが生成する。

  RESOLVED:
    - 生成リスナーは抽象クラスなので 1 クラスで seat / keyboard / pointer を
      同時に継承できない。転送用の内部クラスを置いて実体へ委譲する
    - サーフェスからウィンドウを引くのは wl_proxy_get_user_data。
      ウィンドウ backend が自分自身を設定しておく
    - キーは押下も解放も IME に通す。修飾キー単独押下もエンジンがモード切替に
      使うため通す（§7.5）

  NOT RESOLVED:
    - wl_touch は未実装。タッチは本ユニットの対象だが今回のスコープ外
    - pointer-constraints / relative-pointer / cursor-shape は未実装
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
  PaPiMeLa.Platform.XKB,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland,
  PaPiMeLa.Video.Wayland.Window;

type
  TPMLWaylandSeat = class;

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

  TPMLWaylandSeat = class(Twl_seat_listener)
  strict private
    FQueue    : TPMLEventQueue;
    FSeat     : Pwl_seat;
    FKeyboard : Pwl_keyboard;
    FPointer  : Pwl_pointer;
    FKbdFwd   : TPMLWaylandKeyboardFwd;
    FPtrFwd   : TPMLWaylandPointerFwd;
    FXKB      : TPMLXKBState;
    FName     : String;

    FKeyFocus : TPMLWindowID;
    FPtrFocus : TPMLWindowID;

    // キーリピート（コンポジタは送ってこない。クライアントが生成する）
    FRepeatRate : Integer;    // 1 秒あたりの回数。0 = リピートしない
    FRepeatDelay: Integer;    // 初回までの遅延（ミリ秒）
    FRepeatKey  : LongWord;   // evdev コード。0 = リピート中でない
    FRepeatNext : UInt64;     // 次に発火する時刻（ナノ秒）
    FRepeatText : String;

    procedure StopRepeat;
    function  GetHasKeyboard: Boolean;
    function  WindowIDOf(ASurface: Pwl_surface): TPMLWindowID;
    procedure DeliverKey(AEvdevCode: LongWord; ADown, AIsRepeat: Boolean);
  private
    procedure HandleKeymap(AFormat: LongWord; AFD: LongInt; ASize: LongWord);
    procedure HandleKeyEnter(ASurface: Pwl_surface);
    procedure HandleKeyLeave(ASurface: Pwl_surface);
    procedure HandleKey(AEvdevCode: LongWord; ADown: Boolean);
    procedure HandleModifiers(ADepressed, ALatched, ALocked, AGroup: LongWord);
    procedure HandleRepeatInfo(ARate, ADelay: Integer);
    procedure HandlePointerEnter(ASurface: Pwl_surface; AX, AY: wl_fixed_t);
    procedure HandlePointerLeave(ASurface: Pwl_surface);
    procedure HandlePointerMotion(AX, AY: wl_fixed_t);
    procedure HandlePointerButton(AButton: LongWord; ADown: Boolean);
    procedure HandlePointerAxis(AAxis: LongWord; AValue: wl_fixed_t);
  public
    constructor Create(AQueue: TPMLEventQueue; ASeat: Pwl_seat);
    destructor Destroy; override;

    procedure capabilities(AProxy: Pwl_seat; capabilities_: LongWord); override;
    procedure name(AProxy: Pwl_seat; name_: PAnsiChar); override;

    // ビデオバックエンドの Pump から呼ぶ。期限が来たリピートを発火させる。
    procedure ProcessRepeat;
    // 次のリピートまでの残り時間（ミリ秒）。リピート中でなければ -1。
    function  MillisecondsUntilRepeat: Integer;

    property SeatName: String read FName;
    property HasKeyboard: Boolean read GetHasKeyboard;
  end;
  TPMLWaylandSeats = array of TPMLWaylandSeat;

implementation

const
  // evdev のボタン番号
  BTN_LEFT   = $110;
  BTN_RIGHT  = $111;
  BTN_MIDDLE = $112;

function FixedToSingle(AValue: wl_fixed_t): Single;
begin
  Result := AValue / 256.0;
end;

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
  FOwner.HandlePointerEnter(surface, surface_x, surface_y);
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
  FOwner.HandlePointerButton(button_, state = 1);
end;

procedure TPMLWaylandPointerFwd.axis(AProxy: Pwl_pointer; time: LongWord;
  axis_: LongWord; value: wl_fixed_t);
begin
  FOwner.HandlePointerAxis(axis_, value);
end;

{ TPMLWaylandSeat }

constructor TPMLWaylandSeat.Create(AQueue: TPMLEventQueue; ASeat: Pwl_seat);
begin
  inherited Create;
  FQueue := AQueue;
  FSeat := ASeat;
  FXKB := TPMLXKBState.Create;
  FRepeatRate := 25;
  FRepeatDelay := 600;
  wl_seat_add_listener_object(FSeat, Self);
end;

destructor TPMLWaylandSeat.Destroy;
begin
  if FKeyboard <> nil then
    wl_keyboard_release(FKeyboard);
  if FPointer <> nil then
    wl_pointer_release(FPointer);
  FreeAndNil(FKbdFwd);
  FreeAndNil(FPtrFwd);
  FreeAndNil(FXKB);
  inherited Destroy;
end;

function TPMLWaylandSeat.GetHasKeyboard: Boolean;
begin
  Result := FKeyboard <> nil;
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
  end
  else if ((capabilities_ and WL_SEAT_CAPABILITY_POINTER) = 0) and (FPointer <> nil) then
  begin
    wl_pointer_release(FPointer);
    FPointer := nil;
    FreeAndNil(FPtrFwd);
  end;
  // wl_touch は未実装（#37 の残り）。
end;

procedure TPMLWaylandSeat.name(AProxy: Pwl_seat; name_: PAnsiChar);
begin
  FName := String(name_);
end;

function TPMLWaylandSeat.WindowIDOf(ASurface: Pwl_surface): TPMLWindowID;
var
  Obj: TObject;
begin
  Result := 0;
  if ASurface = nil then
    Exit;
  // ウィンドウ backend が自分自身を user_data に入れている。
  Obj := TObject(wl_proxy_get_user_data(Pwl_proxy(ASurface)));
  if Obj is TPMLWaylandWindowBackend then
    Result := TPMLWaylandWindowBackend(Obj).WindowID;
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
    FQueue.PushSimple(TPMLEventKind.KeymapChanged);
  finally
    Fpmunmap(Map, ASize);
    FpClose(AFD);
  end;
end;

procedure TPMLWaylandSeat.HandleKeyEnter(ASurface: Pwl_surface);
begin
  FKeyFocus := WindowIDOf(ASurface);
  if FKeyFocus <> 0 then
    FQueue.Keyboard.SendFocus(FKeyFocus, True);
end;

procedure TPMLWaylandSeat.HandleKeyLeave(ASurface: Pwl_surface);
var
  ID: TPMLWindowID;
begin
  ID := WindowIDOf(ASurface);
  StopRepeat;
  if ID <> 0 then
    FQueue.Keyboard.SendFocus(ID, False);
  if FKeyFocus = ID then
    FKeyFocus := 0;
end;

procedure TPMLWaylandSeat.DeliverKey(AEvdevCode: LongWord; ADown, AIsRepeat: Boolean);
var
  K: TPMLKeyEventData;
  Text: String;
begin
  FillChar(K, SizeOf(K), 0);
  K.Keysym := FXKB.KeysymOf(AEvdevCode);
  K.Keycode := AEvdevCode + XKB_EVDEV_OFFSET;
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
begin
  FXKB.UpdateMask(ADepressed, ALatched, ALocked, AGroup);
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

procedure TPMLWaylandSeat.HandlePointerEnter(ASurface: Pwl_surface;
  AX, AY: wl_fixed_t);
begin
  FPtrFocus := WindowIDOf(ASurface);
  if FPtrFocus <> 0 then
  begin
    FQueue.Mouse.SendFocus(FPtrFocus, True);
    FQueue.Mouse.SendMotion(FPtrFocus, FixedToSingle(AX), FixedToSingle(AY));
  end;
end;

procedure TPMLWaylandSeat.HandlePointerLeave(ASurface: Pwl_surface);
var
  ID: TPMLWindowID;
begin
  ID := WindowIDOf(ASurface);
  if ID <> 0 then
    FQueue.Mouse.SendFocus(ID, False);
  if FPtrFocus = ID then
    FPtrFocus := 0;
end;

procedure TPMLWaylandSeat.HandlePointerMotion(AX, AY: wl_fixed_t);
begin
  if FPtrFocus <> 0 then
    FQueue.Mouse.SendMotion(FPtrFocus, FixedToSingle(AX), FixedToSingle(AY));
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
  V := FixedToSingle(AValue) / 10.0;
  if AAxis = WL_POINTER_AXIS_VERTICAL_SCROLL then
    FQueue.Mouse.SendWheel(FPtrFocus, 0, -V)
  else
    FQueue.Mouse.SendWheel(FPtrFocus, -V, 0);
end;

end.
