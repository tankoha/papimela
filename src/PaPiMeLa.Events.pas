{
  PaPiMeLa.Events — イベントレコードとキュー

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §6

  WHAT:
    固定サイズの可変部レコード + 管理型フィールドで構成した TPMLEvent と、
    それを値として持つリングバッファのキュー。

  WHY:
    C との共用体互換が不要になったので、可変長データ（テキスト、IME の文節配列、
    候補一覧）を管理型フィールドで安全に持てる。SDL は const char* をイベントに
    入れて SDL_free のタイミングを内部管理していたが、Pascal では参照カウントで
    自然に解決する。キー・マウスはゼロアロケーションのまま。

  RESOLVED:
    - 管理型フィールドは可変部（case）の前に置く。FPC は可変部に管理型を置けない
    - Push は任意スレッドから可。満杯時は最古を捨てる
    - Poll / Wait はメインスレッド専用
    - IME の返信を待つキーは TPMLDeferredKeyQueue に並べ、番号で解決して届いた順に出す（§7.5）。
      KeyUp は KeyDown を出したキーにだけ出す（D-47）
    - ドラッグ＆ドロップの窓口（TPMLDropState）。中身（SDL_dropevents.c から写した部分）と
      text/uri-list の変換は、由来が移植なので PaPiMeLa.Events.Drop に分けた
    - キーボードの窓口（TPMLKeyboardState）。状態機械の中身（SDL_keyboard.c から写した
      押下状態の規則とキーコードのオプション）は、由来が移植なので PaPiMeLa.Events.Keyboard
      に分けた。IME の返信待ちの列（TPMLDeferredKeyQueue）は papimela 独自なのでここに置く

  NOT RESOLVED:
    - 設計 §6.3 は複数 fd を 1 回の poll(2) で待つため IPMLEventPumpSource.GetPollFDs
      を要求するが、現時点の fd ソースは D-Bus 1 本だけで、待ちは
      dbus_connection_read_write のタイムアウトで正しく行える。Wayland バックエンド
      が 2 本目の fd を持ち込む時点で統合する
    - WakeUp は eventfd ではなくフラグ。上記と同じ時点で eventfd にする
    - 状態機械（TPMLKeyboardState / TPMLMouseState / TPMLTouchState）は Video 着手時
    - リングバッファはキュー内部の配列。TPMLRingBuffer<T> の汎用化は必要になってから

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Events;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Properties,
  PaPiMeLa.Threading,
  PaPiMeLa.Keycodes,
  PaPiMeLa.Events.Keymap;

type
  TPMLEventKind = (
    None,
    Quit, BackendLost, Terminating, LowMemory,
    WillEnterBackground, DidEnterBackground, WillEnterForeground, DidEnterForeground,
    LocaleChanged, SystemThemeChanged,
    DisplayAdded, DisplayRemoved, DisplayOrientation, DisplayMoved,
    DisplayDesktopModeChanged, DisplayCurrentModeChanged, DisplayContentScaleChanged,
    WindowShown, WindowHidden, WindowExposed, WindowMoved, WindowResized,
    WindowPixelSizeChanged, WindowMinimized, WindowMaximized, WindowRestored,
    WindowMouseEnter, WindowMouseLeave, WindowFocusGained, WindowFocusLost,
    WindowCloseRequested, WindowDisplayChanged, WindowDisplayScaleChanged,
    WindowOccluded, WindowEnterFullscreen, WindowLeaveFullscreen, WindowDestroyed,
    KeyDown, KeyUp, KeymapChanged, KeyboardAdded, KeyboardRemoved,
    TextEditing, TextInput, TextEditingCandidates,
    TextInputDeleteSurrounding,          // papimela 独自（§7.3）
    MouseMotion, MouseButtonDown, MouseButtonUp, MouseWheel, MouseAdded, MouseRemoved,
    JoystickAxisMotion, JoystickBallMotion, JoystickHatMotion, JoystickButtonDown, JoystickButtonUp,
    JoystickAdded, JoystickRemoved, JoystickBatteryUpdated, JoystickUpdateComplete,
    GamepadAxisMotion, GamepadButtonDown, GamepadButtonUp, GamepadAdded,
    GamepadRemoved, GamepadRemapped, GamepadUpdateComplete,
    FingerDown, FingerUp, FingerMotion, FingerCanceled,
    PenProximityIn, PenProximityOut, PenDown, PenUp, PenButtonDown, PenButtonUp,
    PenMotion, PenAxis,
    ClipboardUpdate,
    DropFile, DropText, DropBegin, DropComplete, DropPosition,
    DragEnd,                             // papimela 独自（こちらが始めたドラッグの終わり）
    AudioDeviceAdded, AudioDeviceRemoved, AudioDeviceFormatChanged,
    RenderTargetsReset, RenderDeviceReset, RenderDeviceLost,
    User
  );
  TPMLEventKinds = set of TPMLEventKind;

  { キーイベント。

    ゲームは Scancode（キーの位置）、ショートカットは Key（今の配列でそのキーに
    書いてある文字）を見る。Keysym と Raw は IME とプラットフォーム層のためのもの。 }
  TPMLKeyEventData = record
    Scancode  : TPMLScancode;      // キーの物理的な位置（USB HID Usage。SDL と同じ値）
    Key       : TPMLKeycode;       // 今の配列でのキーコード（修飾なし。SDL と同じ値）
    Keysym    : LongWord;          // X11 / XKB キーシム。Fcitx5 / IBus がこれで話す
    Raw       : LongWord;          // プラットフォームのキーコード。Wayland では evdev + 8
    Modifiers : TPMLKeyModifiers;
    IsRepeat  : Boolean;
    KeyboardID: LongWord;
  end;

  TPMLWindowEventData = record
    Data1, Data2: Int32;
  end;

  TPMLMouseMotionData = record
    MouseID    : LongWord;
    ButtonState: LongWord;    // ビットマスク。bit0 = 左、bit1 = 右、bit2 = 中
    X, Y       : Single;      // ウィンドウ座標
    XRel, YRel : Single;
  end;

  TPMLMouseButtonData = record
    MouseID: LongWord;
    Button : LongWord;        // 1 = 左、2 = 右、3 = 中
    Clicks : Byte;
    X, Y   : Single;
  end;

  TPMLMouseWheelData = record
    MouseID: LongWord;
    X, Y   : Single;          // 正 = 右 / 上
    Flipped: Boolean;
  end;

  { 指 1 本。

    SDL は座標をウィンドウ幅・高さで正規化した 0..1 で渡すが、papimela は
    マウスと同じウィンドウ座標のまま渡す。Wayland のタッチは必ずサーフェスと
    一緒に届くので正規化する理由が無く、2 つの座標系を混ぜない方が使いやすい。

    Pressure は Wayland に無いので、触っている間 1.0、離したら 0.0 とする。 }
  TPMLTouchPoint = record
    DeviceID: LongWord;      // wl_touch ごとの識別子（シート単位）
    FingerID: Int32;         // wl_touch の id。同時に触っている指を区別する
    WindowID: TPMLWindowID;  // down のときに決まる。motion と up には付いてこない
    X, Y    : Single;        // ウィンドウ座標
    Pressure: Single;
  end;
  TPMLTouchPoints = array of TPMLTouchPoint;

  TPMLTouchFingerData = record
    DeviceID: LongWord;
    FingerID: Int32;
    X, Y    : Single;
    DX, DY  : Single;        // 同じ指の前回位置からの移動量
    Pressure: Single;
  end;

  { ペン（SDL_pen.h と SDL_pen_c.h）。ID は 0 が「無い」。 }
  TPMLPenID = LongWord;
  // PML_PEN_INPUT_xxx のビットの和（SDL_PenInputFlags と同じ値）。
  TPMLPenInputFlags = LongWord;

  // 軸の並びと意味は SDL_PenAxis と同じ。
  //   Pressure 0..1、XTilt / YTilt -90..90（度）、Distance 0..1、Rotation -180..179.9（度）、
  //   Slider 0..1、TangentialPressure（筒を握る圧力）
  TPMLPenAxis = (Pressure, XTilt, YTilt, Distance, Rotation, Slider, TangentialPressure);
  TPMLPenAxes = array[TPMLPenAxis] of Single;

  // SDL_PEN_CAPABILITY_xxx。Eraser は「消しゴムの先も持つ」。
  TPMLPenCapability = (Pressure, XTilt, YTilt, Distance, Rotation, Slider,
    TangentialPressure, Eraser);
  TPMLPenCapabilities = set of TPMLPenCapability;

  // SDL_PenSubtype（道具の種類）。
  TPMLPenSubtype = (Unknown, Eraser, Pen, Pencil, Brush, Airbrush);
  // SDL_PenDeviceType。SDL の INVALID は -1 だが、papimela は値を指定しない列挙にする
  // （Direct = 画面に触れる、Indirect = 画面でない板に触れる）。
  TPMLPenDeviceType = (Invalid, Unknown, Direct, Indirect);

  // SDL_PenInfo。バックエンドが AddDevice に渡す。
  TPMLPenInfo = record
    Capabilities: TPMLPenCapabilities;
    MaxTilt     : Single;      // 傾けられる最大の角度。分からなければ -1
    WacomID     : LongWord;    // Wacom の道具の種類の ID。他は 0
    NumButtons  : Integer;     // 先端を除くボタンの数。分からなければ -1
    Subtype     : TPMLPenSubtype;
    DeviceType  : TPMLPenDeviceType;
  end;

  { PenProximityIn / Out、PenDown / Up、PenButtonDown / Up、PenMotion、PenAxis の付随情報
    （SDL の pproximity / ptouch / pbutton / pmotion / paxis を 1 つにした）。
    X / Y はウィンドウの座標。使わない種類では 0。 }
  TPMLPenEventData = record
    Which   : TPMLPenID;
    PenState: TPMLPenInputFlags;
    X, Y    : Single;
    Eraser  : Boolean;          // PenDown / PenUp: 消しゴムの先か
    Down    : Boolean;          // PenDown / PenUp / PenButtonDown / PenButtonUp
    Button  : Byte;             // PenButtonDown / Up: 1..5
    Axis    : TPMLPenAxis;      // PenAxis
    Value   : Single;           // PenAxis
  end;

  // DropBegin / DropFile / DropText / DropPosition / DropComplete の付随情報。ファイルの
  // パスと文字列は TPMLEvent.Text に載る。位置はウィンドウの座標（DropBegin では 0）。
  TPMLDropEventData = record
    X, Y: Single;
  end;

  { ドラッグで、落とし先とやり取りする操作（wl_data_device_manager の dnd_action）。
      Copy: 落とし先が写す。元はそのまま
      Move: 落とし先が写したあと、元を消してよい（消すのはアプリ）
      Ask : 落としたあとで落とし先が利用者に聞く（最後は Copy か Move に決まる） }
  TPMLDragAction = (Copy, Move, Ask);
  TPMLDragActions = set of TPMLDragAction;

  // DragEnd の付随情報（TPMLClipboard.StartDrag で始めたドラッグの終わり）。
  // WindowID はドラッグを始めたウィンドウ。
  TPMLDragEventData = record
    Dropped: Boolean;          // True = 落とし先が受け取り終えた。False = 取り消された・断られた
    Action : TPMLDragAction;   // Dropped のとき、落とし先と決まった操作（Copy か Move）
  end;

  // ClipboardUpdate の付随情報。MIME タイプの並びは TPMLEvent.Strings に載る。
  TPMLClipboardEventData = record
    Owner           : Boolean;   // True = このアプリが置いた（SetText など）。False = 他のアプリ
    PrimarySelection: Boolean;   // True = プライマリ選択（中クリックで貼る方）
  end;

  { AudioDeviceAdded / AudioDeviceRemoved / AudioDeviceFormatChanged の付随情報
    （SDL_AudioDeviceEvent）。Which は物理か論理のデバイスの ID（TPMLAudioDeviceID の値）。 }
  TPMLAudioDeviceEventData = record
    Which    : LongWord;
    Recording: Boolean;        // True = 録音のデバイス
  end;

  { JoystickAdded / JoystickRemoved / JoystickUpdateComplete の付随情報（SDL_JoyDeviceEvent）。 }
  TPMLJoystickDeviceEventData = record
    Which: LongWord;          // ジョイスティックの ID（TPMLJoystickID の値）
  end;

  TPMLJoystickAxisEventData = record
    Which: LongWord;
    Axis : Byte;
    Value: SmallInt;          // -32768..32767
  end;

  TPMLJoystickBallEventData = record
    Which: LongWord;
    Ball : Byte;
    XRel, YRel: SmallInt;
  end;

  TPMLJoystickHatEventData = record
    Which: LongWord;
    Hat  : Byte;
    Value: Byte;              // PML_HAT_xxx のビットの和
  end;

  TPMLJoystickButtonEventData = record
    Which : LongWord;
    Button: Byte;
    Down  : Boolean;
  end;

  TPMLJoystickBatteryEventData = record
    Which  : LongWord;
    State  : TPMLPowerState;
    Percent: Integer;         // 0..100。分からなければ -1
  end;

  { GamepadAxisMotion の付随情報（SDL_GamepadAxisEvent）。Axis は TPMLGamepadAxis の値。 }
  TPMLGamepadAxisEventData = record
    Which: LongWord;
    Axis : Byte;
    Value: SmallInt;          // -32768..32767
  end;

  { GamepadButtonDown / GamepadButtonUp の付随情報（SDL_GamepadButtonEvent）。Button は TPMLGamepadButton の値。 }
  TPMLGamepadButtonEventData = record
    Which : LongWord;
    Button: Byte;
    Down  : Boolean;
  end;

  TPMLUserEventData = record
    Code        : Int32;
    Data1, Data2: Pointer;
  end;

  TPMLEvent = record
  public
    Kind     : TPMLEventKind;
    Timestamp: UInt64;                    // ナノ秒
    WindowID : TPMLWindowID;              // 0 = ウィンドウ無関係
    // ---- 管理型フィールド（可変部の外）。使わない Kind では空のまま
    Text     : String;                    // TextInput / TextEditing / DropFile / DropText
    Segments : TPMLCompositionSegments;   // TextEditing（§7.3）
    Strings  : TPMLStringArray;            // TextEditingCandidates、ClipboardUpdate（MIME タイプ）
    // ---- 固定部
    case Integer of
      0: (Key              : TPMLKeyEventData);
      1: (Edit             : TPMLTextEditingData);
      2: (DeleteSurrounding: TPMLDeleteSurroundingData);
      3: (Window           : TPMLWindowEventData);
      4: (UserData         : TPMLUserEventData);
      5: (Motion           : TPMLMouseMotionData);
      6: (Button           : TPMLMouseButtonData);
      7: (Wheel            : TPMLMouseWheelData);
      8: (Finger           : TPMLTouchFingerData);
      9: (Clipboard        : TPMLClipboardEventData);
      10: (Drop            : TPMLDropEventData);
      11: (Drag            : TPMLDragEventData);
      12: (AudioDevice     : TPMLAudioDeviceEventData);
      13: (JDevice         : TPMLJoystickDeviceEventData);
      14: (JAxis           : TPMLJoystickAxisEventData);
      15: (JBall           : TPMLJoystickBallEventData);
      16: (JHat            : TPMLJoystickHatEventData);
      17: (JButton         : TPMLJoystickButtonEventData);
      18: (JBattery        : TPMLJoystickBatteryEventData);
      // GamepadAdded / GamepadRemoved / GamepadRemapped / GamepadUpdateComplete は JDevice を使う
      19: (GAxis           : TPMLGamepadAxisEventData);
      20: (GButton         : TPMLGamepadButtonEventData);
      21: (Pen             : TPMLPenEventData);
      // Display / JAxis / GAxis / Finger ... は各サブシステム着手時に追加する。
      // 可変部への追加は既存コードに影響しない。
  end;

const
  // TPMLPenInputFlags のビット（SDL_PEN_INPUT_xxx と同じ値）。
  PML_PEN_INPUT_DOWN         = LongWord(1) shl 0;
  PML_PEN_INPUT_BUTTON_1     = LongWord(1) shl 1;
  PML_PEN_INPUT_BUTTON_2     = LongWord(1) shl 2;
  PML_PEN_INPUT_BUTTON_3     = LongWord(1) shl 3;
  PML_PEN_INPUT_BUTTON_4     = LongWord(1) shl 4;
  PML_PEN_INPUT_BUTTON_5     = LongWord(1) shl 5;
  PML_PEN_INPUT_ERASER_TIP   = LongWord(1) shl 30;
  PML_PEN_INPUT_IN_PROXIMITY = LongWord(1) shl 31;
  // ペンから合成したマウスとタッチのイベントの MouseID / DeviceID（SDL の (SDL_MouseID)-2 と
  // (SDL_TouchID)-2。papimela の ID は 32 ビットなので下の 32 ビット）。
  PML_PEN_MOUSEID = LongWord($FFFFFFFE);
  PML_PEN_TOUCHID = LongWord($FFFFFFFE);

type

  { バックエンドがキューに登録する。Pump の呼び出し順は登録順（§6.3）。 }
  IPMLEventPumpSource = interface
    ['{7E1B5C94-0A36-4F82-B6D7-3C49E08A1F5B}']
    function  PumpSourceName: String;
    // ATimeoutMs > 0 のとき、そのソースは待ってよい。
    procedure PumpEvents(ATimeoutMs: Integer);
  end;

  IPMLEventWatch = interface
    ['{2C8D6E31-94A7-4B05-8F1C-D6730B5E2A48}']
    // Push したスレッドで呼ばれる。False を返すとイベントを落とす。
    function OnEventPushed(const AEvent: TPMLEvent): Boolean;
  end;

  { キーを IME に通すための契約。TPMLTextInputSystem が実装する。

    Events が PaPiMeLa.TextInput を参照すると循環するため、インターフェースで
    受け取る。Context が TextInput を生成したあとにキューへ差し込む。 }
  IPMLKeyFilter = interface
    ['{A31F7D50-6C82-4E19-B074-29D5E8A6F3C1}']
    // セッションが開いていて IME にキーを流すべきなら True。
    function KeyFilterActive: Boolean;
    // ATicket はこのキーの番号。Deferred を返したら、後で TPMLKeyboardState.ResolveKey に
    // 同じ番号で結果を渡してもらう（§7.5）。
    function FilterKey(const AKey: TPMLKeyEventData; AIsRelease: Boolean;
      ATicket: LongWord): TPMLKeyFilterResult;
    // ウィンドウのキーボードフォーカスが変わったことを IME に伝える。
    // これを送らないと、他のアプリへ移っても IME はこちらを注目したままになる。
    procedure NotifyFocus(AWindowID: TPMLWindowID; AGained: Boolean);
  end;

  { IME の返信を待っているキーと、その後ろに並んだキー（§7.5）。

    キーはアプリへ届いた順に出す。先頭が解決するまで、後ろのキーは結果が
    出ていても出さない。返信の順番が入れ替わっても、番号（Ticket）で解決する。 }
  TPMLDeferredKey = record
    Ticket  : LongWord;
    WindowID: TPMLWindowID;
    Key     : TPMLKeyEventData;
    Down    : Boolean;
    Text    : String;       // xkb が求めた文字（PassThrough のときに TextInput にする）
    Resolved: Boolean;
    Consumed: Boolean;
    SinceNS : Int64;        // 並べた時刻。返信が来ないときの打ち切りに使う
  end;

  TPMLDeferredKeyQueue = class sealed
  strict private
    FItems: array of TPMLDeferredKey;
    FHead : Integer;
    function GetCount: Integer;
  public
    procedure Add(const AItem: TPMLDeferredKey);
    // 番号の一致するものを解決する。無ければ（打ち切った後の返信など）False。
    function  Resolve(ATicket: LongWord; AConsumed: Boolean): Boolean;
    // 先頭が解決していれば取り出す。
    function  PopResolved(out AItem: TPMLDeferredKey): Boolean;
    // 先頭から無条件に取り出す（全部を流すとき）。
    function  Pop(out AItem: TPMLDeferredKey): Boolean;
    // ASinceNS より前に並んだ未解決のものを、消費されなかったことにする。件数を返す。
    function  ExpireBefore(ASinceNS: Int64): Integer;
    property  Count: Integer read GetCount;
  end;

  // RunOnMainThread で動かす手続き。
  TPMLMainThreadProc = procedure of object;

  TPMLEventQueue = class;

  { キーボードの状態機械。バックエンドは Push を直接呼ばず、ここを通す（§6.3）。

    IME への転送（§7.5）もここで行う。IME が消費したキーは KeyDown も
    TextInput も発生させない。

    押下状態（IsDown）はキーの物理的な状態で、IME が消費したキーも押された
    ことになる（SDL も IME が扱ったキーの状態を更新する）。

    中身は PaPiMeLa.Events.Keyboard（押下状態の規則とキーコードの決め方。SDL_keyboard.c を写した
    部分）。KeyUp を KeyDown を出したキーにだけ出す規則（D-47）もそちらに書いてある。 }
  TPMLKeyboardState = class sealed(TPMLSystemObject)
  strict private
    FImpl : TObject;   // 状態の本体（TPMLKeyboardImpl）。中身は implementation 側
    function  GetIsDown(AScancode: TPMLScancode): Boolean;
    function  GetKeymap: TPMLKeymap;
    function  GetKeycodeOptions: TPMLKeycodeOptions;
    procedure SetKeycodeOptions(AValue: TPMLKeycodeOptions);
    function  GetModifiers: TPMLKeyModifiers;
    function  GetFocusedWindow: TPMLWindowID;
    function  GetConsumedCount: Integer;
  public
    constructor Create(AContextRef: TObject; AQueue: TPMLEventQueue);
    destructor Destroy; override;
    // バックエンドが呼ぶ唯一の入口。AText は xkb が求めた確定文字列（無ければ空）。
    // AKey.Key が 0 なら、Scancode と今のキーマップから決める。
    procedure SendKey(AWindowID: TPMLWindowID; const AKey: TPMLKeyEventData;
      ADown: Boolean; const AText: String);
    procedure SendModifiers(AModifiers: TPMLKeyModifiers);
    procedure SendFocus(AWindowID: TPMLWindowID; AGained: Boolean);
    // バックエンドが配列を読み込んだ（切り替えた）ときに呼ぶ。所有権はこちらへ移る。
    // KeymapChanged を積む。
    procedure SetKeymap(AKeymap: TPMLKeymap);

    // IME が Deferred にしたキーの結果。番号の合わないもの（打ち切った後の返信）は捨てる。
    procedure ResolveKey(ATicket: LongWord; AConsumed: Boolean);
    // 待っているキーを全部、IME に消費されなかったものとして出す。ただし文字
    // （TextInput）は出さない。IME 向けだった生の文字をアプリへ入れないため。
    // フォーカスを失ったとき・IME のセッションを止めたときに使う。
    procedure FlushDeferred;
    // ATimeoutNS より長く返信の無いキーを、消費されなかったもの（文字も出す）とする。
    // IME が固まってもキーが失われないようにする。TextInput の Pump が呼ぶ。
    procedure ExpireDeferred(ANowNS, ATimeoutNS: Int64);

    // キーが押されているか（SDL_GetKeyboardState）。ゲームの操作はこれで読む。
    property IsDown[AScancode: TPMLScancode]: Boolean read GetIsDown;
    // 今の配列のキーマップ。配列が届く前は既定（US 配列）と同じ意味の空のもの。
    property Keymap       : TPMLKeymap read GetKeymap;
    // キーイベントのキーコードの決め方（SDL_HINT_KEYCODE_OPTIONS）。
    property KeycodeOptions: TPMLKeycodeOptions read GetKeycodeOptions write SetKeycodeOptions;
    property Modifiers    : TPMLKeyModifiers read GetModifiers;
    property FocusedWindow: TPMLWindowID read GetFocusedWindow;
    // IME が消費したキーの累計。テストと診断用。
    property ConsumedCount: Integer read GetConsumedCount;
    // IME の返信を待っているキー（とその後ろに並んだキー）の数。
    function  DeferredCount: Integer;
  end;

  { マウスの状態機械。 }
  TPMLMouseState = class sealed(TPMLSystemObject)
  strict private
    FQueue      : TPMLEventQueue;
    FX, FY      : Single;
    FButtonState: LongWord;
    FFocusedWindow: TPMLWindowID;
  public
    constructor Create(AContextRef: TObject; AQueue: TPMLEventQueue);
    // AMouseID はイベントの MouseID に載る。ペンから合成するときは PML_PEN_MOUSEID。
    procedure SendMotion(AWindowID: TPMLWindowID; AX, AY: Single;
      AMouseID: LongWord = 0);
    procedure SendButton(AWindowID: TPMLWindowID; AButton: LongWord; ADown: Boolean;
      AMouseID: LongWord = 0);
    procedure SendWheel(AWindowID: TPMLWindowID; AX, AY: Single);
    // ポインタがロックされている間の移動。絶対座標は動かない。
    procedure SendRelativeMotion(AWindowID: TPMLWindowID; ADX, ADY: Single);
    procedure SendFocus(AWindowID: TPMLWindowID; AEntered: Boolean);
    property X: Single read FX;
    property Y: Single read FY;
    property ButtonState: LongWord read FButtonState;
  end;


  { タッチの状態機械。

    WHAT:
      wl_touch の down / motion / up / cancel を FingerDown / FingerMotion /
      FingerUp / FingerCanceled に変換し、指ごとの前回位置から移動量を出す。

    WHY:
      Wayland は移動量を送らない。同じ指の前回位置を覚えているのはここだけなので、
      DX / DY はここで算出する。cancel は「今触っている指すべてが無効」の意味なので、
      保持している指の一覧が必要になる。 }
  TPMLTouchState = class sealed(TPMLSystemObject)
  strict private
    FQueue  : TPMLEventQueue;
    FFingers: array of TPMLTouchPoint;
    function  IndexOf(AFingerID: Int32): Integer;
    procedure Emit(AKind: TPMLEventKind; const APoint: TPMLTouchPoint;
      ADX, ADY: Single);
    function  GetFingerCount: Integer;
  public
    constructor Create(AContextRef: TObject; AQueue: TPMLEventQueue);
    // APressure は wl_touch には無い（触っている間 1.0、離したら 0.0）。ペンから合成する
    // ときはペンの圧力を渡す。
    procedure SendDown(AWindowID: TPMLWindowID; ADeviceID: LongWord;
      AFingerID: Int32; AX, AY: Single; APressure: Single = 1.0);
    // motion と up はウィンドウを取らない。Wayland が送ってこないので、down で
    // 覚えたウィンドウを使う。
    procedure SendMotion(ADeviceID: LongWord; AFingerID: Int32; AX, AY: Single;
      APressure: Single = 1.0);
    procedure SendUp(ADeviceID: LongWord; AFingerID: Int32; APressure: Single = 0.0);
    // 触っている指すべてを無効にする。コンポジタがジェスチャを奪ったときに来る。
    procedure SendCancel(ADeviceID: LongWord);
    // その機器の指を、イベントを出さずに忘れる（SDL_DelTouch。ペンの合成を切ったときなど）。
    procedure ForgetDevice(ADeviceID: LongWord);
    function  TryGetFinger(AFingerID: Int32; out APoint: TPMLTouchPoint): Boolean;
    property FingerCount: Integer read GetFingerCount;
  end;

  // RemoveAll がペンごとに呼ぶ。AHandle は AddDevice に渡したもの（バックエンドが自分の物を片付ける）。
  TPMLPenRemoveProc = procedure(AID: TPMLPenID; AHandle: Pointer) of object;
  // ウィンドウがまだあるか。保留していた近接 out を出す前に聞く（SDL_GetWindowFromID）。
  TPMLWindowExistsFunc = function(AWindowID: TPMLWindowID): Boolean of object;

  { ペンの状態機械の窓口。バックエンドは Push を直接呼ばず、ここを通す（§6.3）。
    中身は PaPiMeLa.Events.Pen（SDL_pen.c を写した部分）。

    WHAT:
      ペンの機器の一覧（ID・名前・情報・バックエンドの Handle）と、ペンごとの状態
      （PML_PEN_INPUT_xxx・座標・軸の値）を持ち、変わったときだけ Pen* のイベントを積む。
      ヒント PAPIMELA_PEN_MOUSE_EVENTS / PAPIMELA_PEN_TOUCH_EVENTS（既定は有効）に従い、
      マウス（PML_PEN_MOUSEID）とタッチ（PML_PEN_TOUCHID の指 1）のイベントも合成する。

    WHY:
      バックエンドの知らせ（Wayland は frame ごと）は「今の値」を送るだけで、変わったかは
      言わない。押下・ボタン・近接の状態と最後の座標を覚えているのはここだけ。

    SDL から外した所:
      - 時刻の引数は取らない（他の状態機械と同じく積むときの PMLNowNS）
      - 合成するタッチの座標は窓の座標のまま（SDL は窓の大きさで正規化する。TPMLTouchPoint の方針） }
  TPMLPenState = class sealed(TPMLSystemObject)
  strict private
    FImpl: TObject;   // 状態の本体（TPMLPenImpl）。中身は implementation 側
    function  GetCount: Integer;
    function  GetWindowExists: TPMLWindowExistsFunc;
    procedure SetWindowExists(AValue: TPMLWindowExistsFunc);
  public
    constructor Create(AContextRef: TObject; AQueue: TPMLEventQueue);
    destructor Destroy; override;

    // SDL_AddPenDevice。AHandle はバックエンドの物（nil 以外で、ペンごとに違うこと）。
    // AName が空なら 'Unnamed pen'。AInProximity なら続けて近接 in を出す。
    function  AddDevice(const AName: String; AWindowID: TPMLWindowID;
      const AInfo: TPMLPenInfo; AHandle: Pointer; AInProximity: Boolean): TPMLPenID;
    // SDL_RemovePenDevice。先に近接 out を出す（押下中のボタンも離す）。
    procedure RemoveDevice(AWindowID: TPMLWindowID; AID: TPMLPenID);
    // SDL_RemoveAllPenDevices。終わるとき用。近接 out は出さない。ACallback は nil でよい。
    procedure RemoveAll(ACallback: TPMLPenRemoveProc);

    procedure SendTouch(AID: TPMLPenID; AWindowID: TPMLWindowID; AEraser, ADown: Boolean);
    procedure SendMotion(AID: TPMLPenID; AWindowID: TPMLWindowID; AX, AY: Single);
    procedure SendAxis(AID: TPMLPenID; AWindowID: TPMLWindowID; AAxis: TPMLPenAxis;
      AValue: Single);
    // AButton は 1..5。それ以外は捨てる。
    procedure SendButton(AID: TPMLPenID; AWindowID: TPMLWindowID; AButton: Byte;
      ADown: Boolean);
    // AImmediate = False の近接 out は保留にし、次の SendPendingProximity で出す
    // （それまでに移動かボタンが来れば取り消す）。in は常にすぐ出す。
    procedure SendProximity(AID: TPMLPenID; AWindowID: TPMLWindowID; AIn, AImmediate: Boolean);
    // 保留していた近接 out を出す。TPMLEventQueue.Pump が呼ぶ。
    procedure SendPendingProximity;

    // AddDevice に渡した AHandle のペン。無ければ 0。
    function  FindByHandle(AHandle: Pointer): TPMLPenID;
    // SDL_GetPenStatus。知らない ID なら 0 を返し、AAxes は全部 0。
    function  GetStatus(AID: TPMLPenID; out AAxes: TPMLPenAxes): TPMLPenInputFlags;
    // SDL_GetPenDeviceType。知らない ID なら Invalid。
    function  GetDeviceType(AID: TPMLPenID): TPMLPenDeviceType;
    // つながっているペンの数。
    property Count: Integer read GetCount;
    // 保留した近接 out の窓がまだあるかを聞く先。nil ならあるものとする。
    property WindowExists: TPMLWindowExistsFunc read GetWindowExists write SetWindowExists;
  end;

  { ドラッグ＆ドロップの窓口。バックエンドは Push を直接呼ばず、ここを通す。
    中身は PaPiMeLa.Events.Drop（SDL_SendDrop を写した部分）。

    約束（SDL と同じ）:
      - そのウィンドウで落とし始めてから最初の SendFile / SendText / SendPosition の前に、
        DropBegin を 1 回だけ積む
      - DropFile / DropText / DropComplete の位置は、最後に SendPosition で受けた位置
      - SendComplete で DropComplete を積み、そのウィンドウの「落とし中」と位置を戻す
      - その種類のイベントが無効（SetEnabled で切った）なら何も積まない（DropBegin も）
    SDL は最後の位置をウィンドウをまたいで 1 つだけ持つ。papimela はウィンドウごとに持つ
    （同時に 2 つのウィンドウで落とすことは無いので、違いは出にくい）。 }
  TPMLDropState = class sealed(TPMLSystemObject)
  strict private
    FQueue: TPMLEventQueue;
    FImpl : TObject;   // ウィンドウごとの状態。中身は implementation 側
  public
    constructor Create(AContextRef: TObject; AQueue: TPMLEventQueue);
    destructor Destroy; override;
    procedure SendFile(AWindowID: TPMLWindowID; const APath: String);
    procedure SendText(AWindowID: TPMLWindowID; const AText: String);
    procedure SendPosition(AWindowID: TPMLWindowID; AX, AY: Single);
    procedure SendComplete(AWindowID: TPMLWindowID);
    function  IsDropping(AWindowID: TPMLWindowID): Boolean;
  end;

  TPMLEventQueue = class sealed(TPMLSystemObject)
  strict private
    FLock      : TPMLMutex;
    FCalls     : array of Pointer;   // PPMLMainThreadCall。FLock で守る
    FRing      : array of TPMLEvent;
    FHead      : Integer;        // 次に読む位置
    FCount     : Integer;
    FEnabled   : array[TPMLEventKind] of Boolean;
    FSources   : array of IPMLEventPumpSource;
    FWatches   : array of IPMLEventWatch;
    FWokenUp   : Boolean;
    FDroppedLog: Integer;
    FNextUser  : Integer;
    FKeyboard  : TPMLKeyboardState;
    FMouse     : TPMLMouseState;
    FTouch     : TPMLTouchState;
    FPen       : TPMLPenState;
    FDrop      : TPMLDropState;
    FKeyFilter : IPMLKeyFilter;
    FLogVerbosity  : Integer;    // ヒント PAPIMELA_EVENT_LOGGING の値（0..3）。どのスレッドの Push からも読む
    FQuitGeneration: LongWord;   // 作ったとき（と Quit を出したとき）の PMLQuitSignalGeneration
    function  TakeLocked(out AEvent: TPMLEvent): Boolean;
    function  NotifyWatches(const AEvent: TPMLEvent): Boolean;
    function  GetCapacity: Integer;
    procedure RunMainThreadCalls;
    procedure CancelMainThreadCalls;
    // ヒント PAPIMELA_EVENT_LOGGING の変更。
    procedure EventLoggingChanged(const AName: String; const AOld, ANew: TPMLHintValue);
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject;
      ACapacity: Integer = 256);
    destructor Destroy; override;

    // 全ソースを Pump してから 1 つ取り出す。
    function  Poll(out AEvent: TPMLEvent): Boolean;
    // イベントが来るまで待つ。False = 待ちが中断された（WakeUp）。
    function  Wait(out AEvent: TPMLEvent): Boolean;
    function  WaitTimeout(out AEvent: TPMLEvent; ATimeoutMs: Integer): Boolean;
    procedure Pump(ATimeoutMs: Integer = 0);

    // 任意スレッドから呼べる。満杯時は最古を捨てる。
    procedure Push(const AEvent: TPMLEvent);
    // Kind と Timestamp だけを埋めた最小のイベントを積む。
    procedure PushSimple(AKind: TPMLEventKind; AWindowID: TPMLWindowID = 0);

    function  Peek(AKind: TPMLEventKind): Boolean;
    procedure Flush(AKinds: TPMLEventKinds);
    procedure FlushAll;
    function  GetEnabled(AKind: TPMLEventKind): Boolean;
    procedure SetEnabled(AKind: TPMLEventKind; AValue: Boolean);
    function  RegisterUserEvents(ACount: Integer): TPMLEventKind;

    procedure RegisterPumpSource(ASource: IPMLEventPumpSource);
    procedure UnregisterPumpSource(ASource: IPMLEventPumpSource);
    procedure AddWatch(AWatch: IPMLEventWatch);
    procedure RemoveWatch(AWatch: IPMLEventWatch);
    procedure WakeUp;

    // AProc をメインスレッドで動かす（SDL_RunOnMainThread）。メインスレッドから呼べば
    // その場で動かす。他のスレッドからなら次の Pump の始めに動かす。AWait なら動き終わる
    // まで待ち、動いたら True。キューが先に壊れたら動かさずに False（待たないなら
    // 積めたら True）。メインスレッドが Pump しない間は動かないので、AWait で待つ側は
    // メインスレッドが止まっていると戻らない。
    function  RunOnMainThread(AProc: TPMLMainThreadProc; AWait: Boolean): Boolean;

    property Enabled[AKind: TPMLEventKind]: Boolean read GetEnabled write SetEnabled;
    property PendingCount: Integer read FCount;
    property DroppedCount: Integer read FDroppedLog;
    // キューに溜められるイベントの数。作るときに 16 未満を指定すると 16。
    property Capacity: Integer read GetCapacity;

    // 状態機械。バックエンドはこれを通してイベントを流す（§6.3）。
    property Keyboard: TPMLKeyboardState read FKeyboard;
    property Mouse   : TPMLMouseState read FMouse;
    property Touch   : TPMLTouchState read FTouch;
    property Pen     : TPMLPenState read FPen;
    property Drop    : TPMLDropState read FDrop;
    // Context が TextInput を生成したあとに差し込む。nil なら IME 転送なし。
    property KeyFilter: IPMLKeyFilter read FKeyFilter write FKeyFilter;
  end;

// 現在時刻（ナノ秒）。TPMLTimerService ができたらそちらへ委譲する。
{ イベントを 1 行の説明にする（ヒント PAPIMELA_EVENT_LOGGING でログに出す行の本文）。種類の名前
  （TPMLEventKind の名前、例えば KeyDown）で始め、括弧の中に主な値を「名前=値」で並べる。 }
function PMLEventDescription(const AEvent: TPMLEvent): String;

function PMLNowNS: UInt64;

implementation


uses
  BaseUnix, UnixType, TypInfo,
  PaPiMeLa.Events.Drop,
  PaPiMeLa.Events.Keyboard,
  PaPiMeLa.Events.Pen,
  PaPiMeLa.Events.Quit;

const
  CLOCK_MONOTONIC = 1;

// FPC 3.2.2 の BaseUnix / Unix は clock_gettime を公開していないので直接束縛する。
function clock_gettime(clk_id: LongInt; tp: PTimeSpec): LongInt; cdecl;
  external 'c' name 'clock_gettime';

function PMLNowNS: UInt64;
var
  TS: TTimeSpec;
begin
  if clock_gettime(CLOCK_MONOTONIC, @TS) = 0 then
    Result := UInt64(TS.tv_sec) * 1000000000 + UInt64(TS.tv_nsec)
  else
    Result := 0;
end;

constructor TPMLEventQueue.Create(AContextRef: TObject; AOwner: TPMLObject;
  ACapacity: Integer);
var
  K: TPMLEventKind;
begin
  inherited Create(AContextRef, AOwner);
  if ACapacity < 16 then
    ACapacity := 16;
  SetLength(FRing, ACapacity);
  FLock := TPMLMutex.Create;
  for K := Low(TPMLEventKind) to High(TPMLEventKind) do
    FEnabled[K] := True;
  FNextUser := 0;
  FKeyboard := TPMLKeyboardState.Create(AContextRef, Self);
  FMouse := TPMLMouseState.Create(AContextRef, Self);
  FTouch := TPMLTouchState.Create(AContextRef, Self);
  // ペンはマウスとタッチへ合成するので、その後に作り、先に壊す。
  FPen := TPMLPenState.Create(AContextRef, Self);
  FDrop := TPMLDropState.Create(AContextRef, Self);
  // 作った時点の世代を覚える。これより後に来たシグナルだけを Quit にする。
  FQuitGeneration := PMLQuitSignalGeneration;
  // AddCallback はその場で 1 度呼ぶので、作った時点のヒントの値が FLogVerbosity に入る。
  if (ContextServices <> nil) and (ContextServices.Hints <> nil) then
    ContextServices.Hints.AddCallback(PML_HINT_EVENT_LOGGING, @EventLoggingChanged);
end;

procedure TPMLEventQueue.EventLoggingChanged(const AName: String;
  const AOld, ANew: TPMLHintValue);
begin
  // 置かれていないヒントの Value は ''（PMLEventLoggingVerbosity は 0 を返す）。
  FLogVerbosity := PMLEventLoggingVerbosity(ANew.Value);
end;

// 輪の長さは作るときに決まり、以後変わらないので、ロックは要らない。
function TPMLEventQueue.GetCapacity: Integer;
begin
  Result := Length(FRing);
end;

type
  { RunOnMainThread の 1 件。AWait のときだけ Done を作り、待つ側が捨てる。 }
  TPMLMainThreadCall = record
    Proc    : TPMLMainThreadProc;
    Done    : TPMLSemaphore;
    Executed: Boolean;
  end;
  PPMLMainThreadCall = ^TPMLMainThreadCall;

{ 待っている呼び出しを動かさずに片付ける。待つ側には False で知らせる。 }
procedure CancelCall(ACall: PPMLMainThreadCall);
begin
  if Assigned(ACall^.Done) then
  begin
    ACall^.Executed := False;
    ACall^.Done.Signal;      // 以後 ACall は待つ側のもの
  end
  else
    Dispose(ACall);
end;

destructor TPMLEventQueue.Destroy;
begin
  // 何かを壊す前に外す（ヒントの変更がここへ届かないように）。
  if (ContextServices <> nil) and (ContextServices.Hints <> nil) then
    ContextServices.Hints.RemoveCallback(PML_HINT_EVENT_LOGGING, @EventLoggingChanged);
  CancelMainThreadCalls;
  FKeyFilter := nil;
  FreeAndNil(FPen);
  FreeAndNil(FKeyboard);
  FreeAndNil(FMouse);
  FreeAndNil(FTouch);
  FreeAndNil(FDrop);
  SetLength(FSources, 0);
  SetLength(FWatches, 0);
  SetLength(FRing, 0);
  FreeAndNil(FLock);
  inherited Destroy;
end;

function TPMLEventQueue.NotifyWatches(const AEvent: TPMLEvent): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to High(FWatches) do
    if not FWatches[I].OnEventPushed(AEvent) then
      Exit(False);
end;

procedure TPMLEventQueue.Push(const AEvent: TPMLEvent);
var
  Slot: Integer;
begin
  if not FEnabled[AEvent.Kind] then
    Exit;
  if not NotifyWatches(AEvent) then
    Exit;
  // 積む入口はここだけなので、PushSimple も他のバックエンドもここを通る。
  if PMLEventLogged(AEvent.Kind, FLogVerbosity) and (ContextServices <> nil)
    and (ContextServices.Log <> nil) then
    ContextServices.Log.Log('papimela EVENT: ' + PMLEventDescription(AEvent));

  FLock.Lock;
  try
    if FCount = Length(FRing) then
    begin
      // 満杯。最古を捨てる。管理型フィールドは代入で解放される。
      FHead := (FHead + 1) mod Length(FRing);
      Dec(FCount);
      Inc(FDroppedLog);
    end;
    Slot := (FHead + FCount) mod Length(FRing);
    FRing[Slot] := AEvent;
    Inc(FCount);
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLEventQueue.PushSimple(AKind: TPMLEventKind; AWindowID: TPMLWindowID);
var
  Ev: TPMLEvent;
begin
  FillChar(Ev.Key, SizeOf(Ev.Key), 0);
  Ev.Kind := AKind;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := AWindowID;
  Ev.Text := '';
  Ev.Segments := nil;
  Ev.Strings := nil;
  Push(Ev);
end;

function TPMLEventQueue.TakeLocked(out AEvent: TPMLEvent): Boolean;
begin
  FLock.Lock;
  try
    if FCount = 0 then
      Exit(False);
    AEvent := FRing[FHead];
    // 取り出したスロットの管理型フィールドを解放する。
    FRing[FHead] := Default(TPMLEvent);
    FHead := (FHead + 1) mod Length(FRing);
    Dec(FCount);
    Result := True;
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLEventQueue.Pump(ATimeoutMs: Integer);
var
  I: Integer;
begin
  CheckMainThread;
  RunMainThreadCalls;
  // シグナルの手続きは世代を進めるだけなので、Quit はここで積む。
  // Context ごとに自分の見た世代と比べるので、どの Context にも 1 回のシグナルで 1 回出る。
  if FQuitGeneration <> PMLQuitSignalGeneration then
  begin
    FQuitGeneration := PMLQuitSignalGeneration;
    PushSimple(TPMLEventKind.Quit);
  end;
  for I := 0 to High(FSources) do
  begin
    // 待ちを許すのは最初のソースだけ（§6.3）。
    if I = 0 then
      FSources[I].PumpEvents(ATimeoutMs)
    else
      FSources[I].PumpEvents(0);
  end;
  // SDL_PumpEventMaintenance と同じく、バックエンドを回した後に保留の近接 out を出す
  // （同じ Pump の中で来た移動が保留を取り消せる）。
  FPen.SendPendingProximity;
end;

function TPMLEventQueue.Poll(out AEvent: TPMLEvent): Boolean;
begin
  CheckMainThread;
  if TakeLocked(AEvent) then
    Exit(True);
  Pump(0);
  Result := TakeLocked(AEvent);
end;

function TPMLEventQueue.WaitTimeout(out AEvent: TPMLEvent; ATimeoutMs: Integer): Boolean;
var
  Deadline: UInt64;
  Slice: Integer;
begin
  CheckMainThread;
  if TakeLocked(AEvent) then
    Exit(True);

  if ATimeoutMs < 0 then
    Deadline := High(UInt64)
  else
    Deadline := PMLNowNS + UInt64(ATimeoutMs) * 1000000;

  FWokenUp := False;
  repeat
    Slice := 20;
    if ATimeoutMs >= 0 then
    begin
      if PMLNowNS >= Deadline then
        Break;
      if (Deadline - PMLNowNS) div 1000000 < UInt64(Slice) then
        Slice := Integer((Deadline - PMLNowNS) div 1000000) + 1;
    end;
    Pump(Slice);
    if TakeLocked(AEvent) then
      Exit(True);
    if FWokenUp then
    begin
      FWokenUp := False;
      Exit(False);
    end;
  until False;
  Result := False;
end;

function TPMLEventQueue.Wait(out AEvent: TPMLEvent): Boolean;
begin
  Result := WaitTimeout(AEvent, -1);
end;

function TPMLEventQueue.Peek(AKind: TPMLEventKind): Boolean;
var
  I: Integer;
begin
  Result := False;
  FLock.Lock;
  try
    for I := 0 to FCount - 1 do
      if FRing[(FHead + I) mod Length(FRing)].Kind = AKind then
        Exit(True);
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLEventQueue.Flush(AKinds: TPMLEventKinds);
var
  I, W: Integer;
  Kept: array of TPMLEvent;
begin
  FLock.Lock;
  try
    SetLength(Kept, FCount);
    W := 0;
    for I := 0 to FCount - 1 do
      if not (FRing[(FHead + I) mod Length(FRing)].Kind in AKinds) then
      begin
        Kept[W] := FRing[(FHead + I) mod Length(FRing)];
        Inc(W);
      end;
    for I := 0 to FCount - 1 do
      FRing[(FHead + I) mod Length(FRing)] := Default(TPMLEvent);
    FHead := 0;
    FCount := W;
    for I := 0 to W - 1 do
      FRing[I] := Kept[I];
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLEventQueue.FlushAll;
var
  I: Integer;
begin
  FLock.Lock;
  try
    for I := 0 to FCount - 1 do
      FRing[(FHead + I) mod Length(FRing)] := Default(TPMLEvent);
    FHead := 0;
    FCount := 0;
  finally
    FLock.Unlock;
  end;
end;

function TPMLEventQueue.GetEnabled(AKind: TPMLEventKind): Boolean;
begin
  Result := FEnabled[AKind];
end;

procedure TPMLEventQueue.SetEnabled(AKind: TPMLEventKind; AValue: Boolean);
begin
  FEnabled[AKind] := AValue;
end;

function TPMLEventQueue.RegisterUserEvents(ACount: Integer): TPMLEventKind;
begin
  if ACount <= 0 then
    raise EPMLArgument.Create('RegisterUserEvents: count must be positive');
  if Ord(TPMLEventKind.User) + FNextUser + ACount > 255 then
    raise EPMLEventError.Create('RegisterUserEvents: no user event slots left');
  Result := TPMLEventKind(Ord(TPMLEventKind.User) + FNextUser);
  Inc(FNextUser, ACount);
end;

procedure TPMLEventQueue.RegisterPumpSource(ASource: IPMLEventPumpSource);
begin
  SetLength(FSources, Length(FSources) + 1);
  FSources[High(FSources)] := ASource;
end;

procedure TPMLEventQueue.UnregisterPumpSource(ASource: IPMLEventPumpSource);
var
  I, J: Integer;
begin
  for I := 0 to High(FSources) do
    if FSources[I] = ASource then
    begin
      for J := I to High(FSources) - 1 do
        FSources[J] := FSources[J + 1];
      SetLength(FSources, Length(FSources) - 1);
      Exit;
    end;
end;

procedure TPMLEventQueue.AddWatch(AWatch: IPMLEventWatch);
begin
  SetLength(FWatches, Length(FWatches) + 1);
  FWatches[High(FWatches)] := AWatch;
end;

procedure TPMLEventQueue.RemoveWatch(AWatch: IPMLEventWatch);
var
  I, J: Integer;
begin
  for I := 0 to High(FWatches) do
    if FWatches[I] = AWatch then
    begin
      for J := I to High(FWatches) - 1 do
        FWatches[J] := FWatches[J + 1];
      SetLength(FWatches, Length(FWatches) - 1);
      Exit;
    end;
end;

procedure TPMLEventQueue.WakeUp;
begin
  FWokenUp := True;
end;

function TPMLEventQueue.RunOnMainThread(AProc: TPMLMainThreadProc; AWait: Boolean): Boolean;
var
  Call: PPMLMainThreadCall;
begin
  if not Assigned(AProc) then
    raise EPMLArgument.Create('RunOnMainThread: no procedure');
  // メインスレッドからならその場で（SDL と同じ）。
  if GetCurrentThreadID = MainThreadID then
  begin
    AProc();
    Exit(True);
  end;
  New(Call);
  Call^.Proc := AProc;
  Call^.Executed := False;
  Call^.Done := nil;
  if AWait then
    Call^.Done := TPMLSemaphore.Create(0);
  FLock.Lock;
  try
    SetLength(FCalls, Length(FCalls) + 1);
    FCalls[High(FCalls)] := Call;
  finally
    FLock.Unlock;
  end;
  if not AWait then
    Exit(True);
  // 動き終わる（か、キューが壊れる）まで待つ。待ち終わったら Call はこちらのもの。
  Call^.Done.Wait;
  Result := Call^.Executed;
  Call^.Done.Free;
  Dispose(Call);
end;

{ 動かし終わった（か、例外で抜けた）呼び出しを片付ける。待つ側がいれば起こす。 }
procedure FinishCall(ACall: PPMLMainThreadCall);
begin
  if Assigned(ACall^.Done) then
    ACall^.Done.Signal      // 以後 ACall は待つ側のもの
  else
    Dispose(ACall);
end;

{ メインスレッドで、積まれた呼び出しを積まれた順に動かす。動かしている間に積まれた分は
  次の Pump に回す。手続きが例外を出したら、その呼び出しは動いていない（Executed = False）
  として待つ側を起こし、残りを次の Pump に回してから外へ出す。 }
procedure TPMLEventQueue.RunMainThreadCalls;
var
  Calls, Rest: array of Pointer;
  I: Integer;
  Call: PPMLMainThreadCall;
begin
  FLock.Lock;
  try
    Calls := FCalls;
    FCalls := nil;
  finally
    FLock.Unlock;
  end;
  for I := 0 to High(Calls) do
  begin
    Call := PPMLMainThreadCall(Calls[I]);
    try
      Call^.Proc();
    except
      FinishCall(Call);
      Rest := Copy(Calls, I + 1, Length(Calls) - I - 1);
      FLock.Lock;
      try
        FCalls := Concat(Rest, FCalls);
      finally
        FLock.Unlock;
      end;
      raise;
    end;
    Call^.Executed := True;
    FinishCall(Call);
  end;
end;

procedure TPMLEventQueue.CancelMainThreadCalls;
var
  Calls: array of Pointer;
  I: Integer;
begin
  FLock.Lock;
  try
    Calls := FCalls;
    FCalls := nil;
  finally
    FLock.Unlock;
  end;
  for I := 0 to High(Calls) do
    CancelCall(PPMLMainThreadCall(Calls[I]));
end;

{ TPMLDeferredKeyQueue }

function TPMLDeferredKeyQueue.GetCount: Integer;
begin
  Result := Length(FItems) - FHead;
end;

procedure TPMLDeferredKeyQueue.Add(const AItem: TPMLDeferredKey);
begin
  // 空になったら詰め直す。キーの数は高々数十なので、配列の作り直しで足りる。
  if (FHead > 0) and (FHead = Length(FItems)) then
  begin
    FItems := nil;
    FHead := 0;
  end;
  SetLength(FItems, Length(FItems) + 1);
  FItems[High(FItems)] := AItem;
end;

function TPMLDeferredKeyQueue.Resolve(ATicket: LongWord; AConsumed: Boolean): Boolean;
var
  I: Integer;
begin
  for I := FHead to High(FItems) do
    if (FItems[I].Ticket = ATicket) and not FItems[I].Resolved then
    begin
      FItems[I].Resolved := True;
      FItems[I].Consumed := AConsumed;
      Exit(True);
    end;
  Result := False;
end;

function TPMLDeferredKeyQueue.PopResolved(out AItem: TPMLDeferredKey): Boolean;
begin
  Result := (FHead < Length(FItems)) and FItems[FHead].Resolved;
  if Result then
    Result := Pop(AItem);
end;

function TPMLDeferredKeyQueue.Pop(out AItem: TPMLDeferredKey): Boolean;
begin
  Result := FHead < Length(FItems);
  if not Result then
    Exit;
  AItem := FItems[FHead];
  FItems[FHead].Text := '';
  Inc(FHead);
end;

function TPMLDeferredKeyQueue.ExpireBefore(ASinceNS: Int64): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := FHead to High(FItems) do
    if not FItems[I].Resolved and (FItems[I].SinceNS < ASinceNS) then
    begin
      FItems[I].Resolved := True;
      FItems[I].Consumed := False;
      Inc(Result);
    end;
end;

{ ---- キーボードの状態機械（中身は PaPiMeLa.Events.Keyboard） ---- }

constructor TPMLKeyboardState.Create(AContextRef: TObject; AQueue: TPMLEventQueue);
var
  Hints: TPMLHints;
begin
  inherited Create(AContextRef, AQueue);
  Hints := nil;
  if ContextServices <> nil then
    Hints := ContextServices.Hints;
  FImpl := TPMLKeyboardImpl.Create(AQueue, Hints);
end;

destructor TPMLKeyboardState.Destroy;
begin
  FreeAndNil(FImpl);
  inherited Destroy;
end;

function TPMLKeyboardState.GetIsDown(AScancode: TPMLScancode): Boolean;
begin
  Result := TPMLKeyboardImpl(FImpl).GetIsDown(AScancode);
end;

function TPMLKeyboardState.GetKeymap: TPMLKeymap;
begin
  Result := TPMLKeyboardImpl(FImpl).Keymap;
end;

function TPMLKeyboardState.GetKeycodeOptions: TPMLKeycodeOptions;
begin
  Result := TPMLKeyboardImpl(FImpl).KeycodeOptions;
end;

procedure TPMLKeyboardState.SetKeycodeOptions(AValue: TPMLKeycodeOptions);
begin
  TPMLKeyboardImpl(FImpl).KeycodeOptions := AValue;
end;

function TPMLKeyboardState.GetModifiers: TPMLKeyModifiers;
begin
  Result := TPMLKeyboardImpl(FImpl).Modifiers;
end;

function TPMLKeyboardState.GetFocusedWindow: TPMLWindowID;
begin
  Result := TPMLKeyboardImpl(FImpl).FocusedWindow;
end;

function TPMLKeyboardState.GetConsumedCount: Integer;
begin
  Result := TPMLKeyboardImpl(FImpl).ConsumedCount;
end;

function TPMLKeyboardState.DeferredCount: Integer;
begin
  Result := TPMLKeyboardImpl(FImpl).DeferredCount;
end;

procedure TPMLKeyboardState.SendKey(AWindowID: TPMLWindowID;
  const AKey: TPMLKeyEventData; ADown: Boolean; const AText: String);
begin
  TPMLKeyboardImpl(FImpl).SendKey(AWindowID, AKey, ADown, AText);
end;

procedure TPMLKeyboardState.SendModifiers(AModifiers: TPMLKeyModifiers);
begin
  TPMLKeyboardImpl(FImpl).SendModifiers(AModifiers);
end;

procedure TPMLKeyboardState.SendFocus(AWindowID: TPMLWindowID; AGained: Boolean);
begin
  TPMLKeyboardImpl(FImpl).SendFocus(AWindowID, AGained);
end;

procedure TPMLKeyboardState.SetKeymap(AKeymap: TPMLKeymap);
begin
  TPMLKeyboardImpl(FImpl).SetKeymap(AKeymap);
end;

procedure TPMLKeyboardState.ResolveKey(ATicket: LongWord; AConsumed: Boolean);
begin
  TPMLKeyboardImpl(FImpl).ResolveKey(ATicket, AConsumed);
end;

procedure TPMLKeyboardState.FlushDeferred;
begin
  TPMLKeyboardImpl(FImpl).FlushDeferred;
end;

procedure TPMLKeyboardState.ExpireDeferred(ANowNS, ATimeoutNS: Int64);
begin
  TPMLKeyboardImpl(FImpl).ExpireDeferred(ANowNS, ATimeoutNS);
end;

{ TPMLMouseState }

constructor TPMLMouseState.Create(AContextRef: TObject; AQueue: TPMLEventQueue);
begin
  inherited Create(AContextRef, AQueue);
  FQueue := AQueue;
end;

procedure TPMLMouseState.SendMotion(AWindowID: TPMLWindowID; AX, AY: Single;
  AMouseID: LongWord);
var
  Ev: TPMLEvent;
begin
  FillChar(Ev.Motion, SizeOf(Ev.Motion), 0);
  Ev.Kind := TPMLEventKind.MouseMotion;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := AWindowID;
  Ev.Text := '';
  Ev.Segments := nil;
  Ev.Strings := nil;
  Ev.Motion.MouseID := AMouseID;
  Ev.Motion.ButtonState := FButtonState;
  Ev.Motion.X := AX;
  Ev.Motion.Y := AY;
  Ev.Motion.XRel := AX - FX;
  Ev.Motion.YRel := AY - FY;
  FX := AX;
  FY := AY;
  FQueue.Push(Ev);
end;

procedure TPMLMouseState.SendButton(AWindowID: TPMLWindowID;
  AButton: LongWord; ADown: Boolean; AMouseID: LongWord);
var
  Ev: TPMLEvent;
  Mask: LongWord;
begin
  if AButton = 0 then
    Exit;
  Mask := LongWord(1) shl (AButton - 1);
  if ADown then
    FButtonState := FButtonState or Mask
  else
    FButtonState := FButtonState and not Mask;

  FillChar(Ev.Button, SizeOf(Ev.Button), 0);
  if ADown then
    Ev.Kind := TPMLEventKind.MouseButtonDown
  else
    Ev.Kind := TPMLEventKind.MouseButtonUp;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := AWindowID;
  Ev.Text := '';
  Ev.Segments := nil;
  Ev.Strings := nil;
  Ev.Button.MouseID := AMouseID;
  Ev.Button.Button := AButton;
  Ev.Button.Clicks := 1;
  Ev.Button.X := FX;
  Ev.Button.Y := FY;
  FQueue.Push(Ev);
end;

procedure TPMLMouseState.SendWheel(AWindowID: TPMLWindowID; AX, AY: Single);
var
  Ev: TPMLEvent;
begin
  FillChar(Ev.Wheel, SizeOf(Ev.Wheel), 0);
  Ev.Kind := TPMLEventKind.MouseWheel;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := AWindowID;
  Ev.Text := '';
  Ev.Segments := nil;
  Ev.Strings := nil;
  Ev.Wheel.X := AX;
  Ev.Wheel.Y := AY;
  FQueue.Push(Ev);
end;

{ ロック中の相対移動。

  ロック中はコンポジタが wl_pointer.motion を送ってこない。ポインタは実際に
  動いていないので、絶対座標は直前の値をそのまま載せ、FX / FY も更新しない。
  アプリは XRel / YRel だけを見る。 }
procedure TPMLMouseState.SendRelativeMotion(AWindowID: TPMLWindowID;
  ADX, ADY: Single);
var
  Ev: TPMLEvent;
begin
  FillChar(Ev.Motion, SizeOf(Ev.Motion), 0);
  Ev.Kind := TPMLEventKind.MouseMotion;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := AWindowID;
  Ev.Text := '';
  Ev.Segments := nil;
  Ev.Strings := nil;
  Ev.Motion.ButtonState := FButtonState;
  Ev.Motion.X := FX;
  Ev.Motion.Y := FY;
  Ev.Motion.XRel := ADX;
  Ev.Motion.YRel := ADY;
  FQueue.Push(Ev);
end;

procedure TPMLMouseState.SendFocus(AWindowID: TPMLWindowID; AEntered: Boolean);
begin
  if AEntered then
  begin
    FFocusedWindow := AWindowID;
    FQueue.PushSimple(TPMLEventKind.WindowMouseEnter, AWindowID);
  end
  else
  begin
    if FFocusedWindow = AWindowID then
      FFocusedWindow := 0;
    FButtonState := 0;
    FQueue.PushSimple(TPMLEventKind.WindowMouseLeave, AWindowID);
  end;
end;


{ TPMLTouchState }

constructor TPMLTouchState.Create(AContextRef: TObject; AQueue: TPMLEventQueue);
begin
  inherited Create(AContextRef, AQueue);
  FQueue := AQueue;
end;

function TPMLTouchState.GetFingerCount: Integer;
begin
  Result := Length(FFingers);
end;

function TPMLTouchState.IndexOf(AFingerID: Int32): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FFingers) do
    if FFingers[I].FingerID = AFingerID then
      Exit(I);
  Result := -1;
end;

function TPMLTouchState.TryGetFinger(AFingerID: Int32;
  out APoint: TPMLTouchPoint): Boolean;
var
  I: Integer;
begin
  I := IndexOf(AFingerID);
  Result := I >= 0;
  if Result then
    APoint := FFingers[I]
  else
    FillChar(APoint, SizeOf(APoint), 0);
end;

procedure TPMLTouchState.Emit(AKind: TPMLEventKind; const APoint: TPMLTouchPoint;
  ADX, ADY: Single);
var
  Ev: TPMLEvent;
begin
  FillChar(Ev.Finger, SizeOf(Ev.Finger), 0);
  Ev.Kind := AKind;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := APoint.WindowID;
  Ev.Text := '';
  Ev.Segments := nil;
  Ev.Strings := nil;
  Ev.Finger.DeviceID := APoint.DeviceID;
  Ev.Finger.FingerID := APoint.FingerID;
  Ev.Finger.X := APoint.X;
  Ev.Finger.Y := APoint.Y;
  Ev.Finger.DX := ADX;
  Ev.Finger.DY := ADY;
  Ev.Finger.Pressure := APoint.Pressure;
  FQueue.Push(Ev);
end;

procedure TPMLTouchState.SendDown(AWindowID: TPMLWindowID; ADeviceID: LongWord;
  AFingerID: Int32; AX, AY: Single; APressure: Single);
var
  I: Integer;
  P: TPMLTouchPoint;
begin
  P.DeviceID := ADeviceID;
  P.FingerID := AFingerID;
  P.WindowID := AWindowID;
  P.X := AX;
  P.Y := AY;
  P.Pressure := APressure;

  // 同じ id が離されずに再度 down することは wl_touch では無いが、ペンの消しゴムの切り替えなどで
  // 来る。SDL_SendTouch は先に FingerCanceled を出すので、同じ並びにする（位置と圧力は新しいもの）。
  I := IndexOf(AFingerID);
  if I >= 0 then
    Emit(TPMLEventKind.FingerCanceled, P, 0, 0)
  else
  begin
    SetLength(FFingers, Length(FFingers) + 1);
    I := High(FFingers);
  end;
  FFingers[I] := P;
  Emit(TPMLEventKind.FingerDown, P, 0, 0);
end;

procedure TPMLTouchState.SendMotion(ADeviceID: LongWord; AFingerID: Int32;
  AX, AY: Single; APressure: Single);
var
  I: Integer;
  DX, DY: Single;
begin
  I := IndexOf(AFingerID);
  // down を見ていない指の motion は捨てる。移動量の基準もウィンドウも無い。
  if I < 0 then
    Exit;
  DX := AX - FFingers[I].X;
  DY := AY - FFingers[I].Y;
  FFingers[I].X := AX;
  FFingers[I].Y := AY;
  FFingers[I].Pressure := APressure;
  Emit(TPMLEventKind.FingerMotion, FFingers[I], DX, DY);
end;

procedure TPMLTouchState.SendUp(ADeviceID: LongWord; AFingerID: Int32;
  APressure: Single);
var
  I, J: Integer;
  P: TPMLTouchPoint;
begin
  I := IndexOf(AFingerID);
  if I < 0 then
    Exit;
  // wl_touch.up は座標を送らない。最後に分かっている位置をそのまま載せる。
  P := FFingers[I];
  P.Pressure := APressure;
  for J := I to High(FFingers) - 1 do
    FFingers[J] := FFingers[J + 1];
  SetLength(FFingers, Length(FFingers) - 1);
  Emit(TPMLEventKind.FingerUp, P, 0, 0);
end;

{ コンポジタがタッチ列を奪った（ジェスチャとして解釈した等）。

  触っている指すべてを無効にする。up は来ないので、ここで全部落とさないと
  指が押されたままになる。 }
procedure TPMLTouchState.SendCancel(ADeviceID: LongWord);
var
  I: Integer;
  Snapshot: TPMLTouchPoints;
begin
  if Length(FFingers) = 0 then
    Exit;
  Snapshot := Copy(FFingers, 0, Length(FFingers));
  SetLength(FFingers, 0);
  for I := 0 to High(Snapshot) do
  begin
    Snapshot[I].Pressure := 0.0;
    Emit(TPMLEventKind.FingerCanceled, Snapshot[I], 0, 0);
  end;
end;

procedure TPMLTouchState.ForgetDevice(ADeviceID: LongWord);
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to High(FFingers) do
    if FFingers[I].DeviceID <> ADeviceID then
    begin
      FFingers[N] := FFingers[I];
      Inc(N);
    end;
  SetLength(FFingers, N);
end;

{ ---- ペン（中身は PaPiMeLa.Events.Pen） ---- }

constructor TPMLPenState.Create(AContextRef: TObject; AQueue: TPMLEventQueue);
var
  Hints: TPMLHints;
begin
  inherited Create(AContextRef, AQueue);
  Hints := nil;
  if ContextServices <> nil then
    Hints := ContextServices.Hints;
  FImpl := TPMLPenImpl.Create(AQueue, Hints);
end;

destructor TPMLPenState.Destroy;
begin
  FreeAndNil(FImpl);
  inherited Destroy;
end;

function TPMLPenState.GetCount: Integer;
begin
  Result := TPMLPenImpl(FImpl).Count;
end;

function TPMLPenState.GetWindowExists: TPMLWindowExistsFunc;
begin
  Result := TPMLPenImpl(FImpl).WindowExists;
end;

procedure TPMLPenState.SetWindowExists(AValue: TPMLWindowExistsFunc);
begin
  TPMLPenImpl(FImpl).WindowExists := AValue;
end;

function TPMLPenState.AddDevice(const AName: String; AWindowID: TPMLWindowID;
  const AInfo: TPMLPenInfo; AHandle: Pointer; AInProximity: Boolean): TPMLPenID;
begin
  Result := TPMLPenImpl(FImpl).AddDevice(AName, AWindowID, AInfo, AHandle, AInProximity);
end;

procedure TPMLPenState.RemoveDevice(AWindowID: TPMLWindowID; AID: TPMLPenID);
begin
  TPMLPenImpl(FImpl).RemoveDevice(AWindowID, AID);
end;

procedure TPMLPenState.RemoveAll(ACallback: TPMLPenRemoveProc);
begin
  TPMLPenImpl(FImpl).RemoveAll(ACallback);
end;

procedure TPMLPenState.SendTouch(AID: TPMLPenID; AWindowID: TPMLWindowID;
  AEraser, ADown: Boolean);
begin
  TPMLPenImpl(FImpl).SendTouch(AID, AWindowID, AEraser, ADown);
end;

procedure TPMLPenState.SendMotion(AID: TPMLPenID; AWindowID: TPMLWindowID; AX, AY: Single);
begin
  TPMLPenImpl(FImpl).SendMotion(AID, AWindowID, AX, AY);
end;

procedure TPMLPenState.SendAxis(AID: TPMLPenID; AWindowID: TPMLWindowID;
  AAxis: TPMLPenAxis; AValue: Single);
begin
  TPMLPenImpl(FImpl).SendAxis(AID, AWindowID, AAxis, AValue);
end;

procedure TPMLPenState.SendButton(AID: TPMLPenID; AWindowID: TPMLWindowID;
  AButton: Byte; ADown: Boolean);
begin
  TPMLPenImpl(FImpl).SendButton(AID, AWindowID, AButton, ADown);
end;

procedure TPMLPenState.SendProximity(AID: TPMLPenID; AWindowID: TPMLWindowID;
  AIn, AImmediate: Boolean);
begin
  TPMLPenImpl(FImpl).SendProximity(AID, AWindowID, AIn, AImmediate);
end;

procedure TPMLPenState.SendPendingProximity;
begin
  TPMLPenImpl(FImpl).SendPendingProximity;
end;

function TPMLPenState.FindByHandle(AHandle: Pointer): TPMLPenID;
begin
  Result := TPMLPenImpl(FImpl).FindByHandle(AHandle);
end;

function TPMLPenState.GetStatus(AID: TPMLPenID; out AAxes: TPMLPenAxes): TPMLPenInputFlags;
begin
  Result := TPMLPenImpl(FImpl).GetStatus(AID, AAxes);
end;

function TPMLPenState.GetDeviceType(AID: TPMLPenID): TPMLPenDeviceType;
begin
  Result := TPMLPenImpl(FImpl).GetDeviceType(AID);
end;

{ ---- ドラッグ＆ドロップ（中身は PaPiMeLa.Events.Drop） ---- }

constructor TPMLDropState.Create(AContextRef: TObject; AQueue: TPMLEventQueue);
begin
  inherited Create(AContextRef, AQueue);
  FQueue := AQueue;
  FImpl := TPMLDropImpl.Create;
end;

destructor TPMLDropState.Destroy;
begin
  FreeAndNil(FImpl);
  inherited Destroy;
end;

procedure TPMLDropState.SendFile(AWindowID: TPMLWindowID; const APath: String);
begin
  PMLSendDrop(FQueue, TPMLDropImpl(FImpl), TPMLEventKind.DropFile, AWindowID, APath, 0, 0);
end;

procedure TPMLDropState.SendText(AWindowID: TPMLWindowID; const AText: String);
begin
  PMLSendDrop(FQueue, TPMLDropImpl(FImpl), TPMLEventKind.DropText, AWindowID, AText, 0, 0);
end;

procedure TPMLDropState.SendPosition(AWindowID: TPMLWindowID; AX, AY: Single);
begin
  PMLSendDrop(FQueue, TPMLDropImpl(FImpl), TPMLEventKind.DropPosition, AWindowID, '', AX, AY);
end;

procedure TPMLDropState.SendComplete(AWindowID: TPMLWindowID);
begin
  PMLSendDrop(FQueue, TPMLDropImpl(FImpl), TPMLEventKind.DropComplete, AWindowID, '', 0, 0);
end;

function TPMLDropState.IsDropping(AWindowID: TPMLWindowID): Boolean;
begin
  Result := TPMLDropImpl(FImpl).IndexOf(AWindowID) >= 0;
end;

function PMLEventDescription(const AEvent: TPMLEvent): String;
var
  Details: String;

  procedure Add(const AName, AValue: String);
  begin
    Details := Details + ', ' + AName + '=' + AValue;
  end;

  // 押されている修飾キーの名前を '+' でつなぐ（無ければ 'none'）。
  function ModifierNames(AMods: TPMLKeyModifiers): String;
  var
    M: TPMLKeyModifier;
  begin
    Result := '';
    for M := Low(TPMLKeyModifier) to High(TPMLKeyModifier) do
      if M in AMods then
      begin
        if Result <> '' then
          Result := Result + '+';
        Result := Result + GetEnumName(TypeInfo(TPMLKeyModifier), Ord(M));
      end;
    if Result = '' then
      Result := 'none';
  end;

  function Flt(AValue: Single): String;
  begin
    Result := FloatToStrF(AValue, ffFixed, 15, 2, DefaultFormatSettings);
  end;

begin
  Details := 'timestamp=' + IntToStr(AEvent.Timestamp);
  if AEvent.WindowID <> 0 then
    Add('windowid', IntToStr(AEvent.WindowID));
  case AEvent.Kind of
    TPMLEventKind.KeyDown, TPMLEventKind.KeyUp:
    begin
      Add('scancode', IntToStr(Ord(AEvent.Key.Scancode)));
      Add('key', IntToStr(Ord(AEvent.Key.Key)));
      Add('modifiers', ModifierNames(AEvent.Key.Modifiers));
      Add('repeat', BoolToStr(AEvent.Key.IsRepeat, True));
    end;
    TPMLEventKind.TextInput, TPMLEventKind.TextEditing,
    TPMLEventKind.DropText, TPMLEventKind.DropFile:
      Add('text', '"' + AEvent.Text + '"');
    TPMLEventKind.MouseMotion:
    begin
      Add('x', Flt(AEvent.Motion.X));
      Add('y', Flt(AEvent.Motion.Y));
      Add('xrel', Flt(AEvent.Motion.XRel));
      Add('yrel', Flt(AEvent.Motion.YRel));
    end;
    TPMLEventKind.MouseButtonDown, TPMLEventKind.MouseButtonUp:
    begin
      Add('button', IntToStr(AEvent.Button.Button));
      Add('clicks', IntToStr(AEvent.Button.Clicks));
      Add('x', Flt(AEvent.Button.X));
      Add('y', Flt(AEvent.Button.Y));
    end;
    TPMLEventKind.MouseWheel:
    begin
      Add('x', Flt(AEvent.Wheel.X));
      Add('y', Flt(AEvent.Wheel.Y));
    end;
    TPMLEventKind.FingerDown, TPMLEventKind.FingerUp,
    TPMLEventKind.FingerMotion, TPMLEventKind.FingerCanceled:
    begin
      Add('finger', IntToStr(AEvent.Finger.FingerID));
      Add('x', Flt(AEvent.Finger.X));
      Add('y', Flt(AEvent.Finger.Y));
    end;
    // SDL_EventLogging の pproximity / ptouch / pbutton / pmotion / paxis。
    TPMLEventKind.PenProximityIn, TPMLEventKind.PenProximityOut:
    begin
      Add('which', IntToStr(AEvent.Pen.Which));
      Add('pen_state', IntToStr(AEvent.Pen.PenState));
    end;
    TPMLEventKind.PenDown, TPMLEventKind.PenUp:
    begin
      Add('which', IntToStr(AEvent.Pen.Which));
      Add('pen_state', IntToStr(AEvent.Pen.PenState));
      Add('x', Flt(AEvent.Pen.X));
      Add('y', Flt(AEvent.Pen.Y));
      Add('eraser', BoolToStr(AEvent.Pen.Eraser, True));
    end;
    TPMLEventKind.PenButtonDown, TPMLEventKind.PenButtonUp:
    begin
      Add('which', IntToStr(AEvent.Pen.Which));
      Add('pen_state', IntToStr(AEvent.Pen.PenState));
      Add('x', Flt(AEvent.Pen.X));
      Add('y', Flt(AEvent.Pen.Y));
      Add('button', IntToStr(AEvent.Pen.Button));
    end;
    TPMLEventKind.PenMotion:
    begin
      Add('which', IntToStr(AEvent.Pen.Which));
      Add('pen_state', IntToStr(AEvent.Pen.PenState));
      Add('x', Flt(AEvent.Pen.X));
      Add('y', Flt(AEvent.Pen.Y));
    end;
    TPMLEventKind.PenAxis:
    begin
      Add('which', IntToStr(AEvent.Pen.Which));
      Add('pen_state', IntToStr(AEvent.Pen.PenState));
      Add('x', Flt(AEvent.Pen.X));
      Add('y', Flt(AEvent.Pen.Y));
      Add('axis', GetEnumName(TypeInfo(TPMLPenAxis), Ord(AEvent.Pen.Axis)));
      Add('value', Flt(AEvent.Pen.Value));
    end;
    TPMLEventKind.WindowMoved, TPMLEventKind.WindowResized,
    TPMLEventKind.WindowPixelSizeChanged:
    begin
      Add('data1', IntToStr(AEvent.Window.Data1));
      Add('data2', IntToStr(AEvent.Window.Data2));
    end;
    // SDL_EventLogging の adevice（which と recording）。
    TPMLEventKind.AudioDeviceAdded, TPMLEventKind.AudioDeviceRemoved,
    TPMLEventKind.AudioDeviceFormatChanged:
    begin
      Add('which', IntToStr(AEvent.AudioDevice.Which));
      Add('recording', BoolToStr(AEvent.AudioDevice.Recording, True));
    end;
    // SDL_EventLogging の jaxis / jball / jhat / jbutton / jdevice。
    TPMLEventKind.JoystickAxisMotion:
    begin
      Add('which', IntToStr(AEvent.JAxis.Which));
      Add('axis', IntToStr(AEvent.JAxis.Axis));
      Add('value', IntToStr(AEvent.JAxis.Value));
    end;
    TPMLEventKind.JoystickBallMotion:
    begin
      Add('which', IntToStr(AEvent.JBall.Which));
      Add('ball', IntToStr(AEvent.JBall.Ball));
      Add('xrel', IntToStr(AEvent.JBall.XRel));
      Add('yrel', IntToStr(AEvent.JBall.YRel));
    end;
    TPMLEventKind.JoystickHatMotion:
    begin
      Add('which', IntToStr(AEvent.JHat.Which));
      Add('hat', IntToStr(AEvent.JHat.Hat));
      Add('value', IntToStr(AEvent.JHat.Value));
    end;
    TPMLEventKind.JoystickButtonDown, TPMLEventKind.JoystickButtonUp:
    begin
      Add('which', IntToStr(AEvent.JButton.Which));
      Add('button', IntToStr(AEvent.JButton.Button));
    end;
    TPMLEventKind.JoystickAdded, TPMLEventKind.JoystickRemoved, TPMLEventKind.JoystickUpdateComplete:
      Add('which', IntToStr(AEvent.JDevice.Which));
    TPMLEventKind.GamepadAxisMotion:
    begin
      Add('which', IntToStr(AEvent.GAxis.Which));
      Add('axis', IntToStr(AEvent.GAxis.Axis));
      Add('value', IntToStr(AEvent.GAxis.Value));
    end;
    TPMLEventKind.GamepadButtonDown, TPMLEventKind.GamepadButtonUp:
    begin
      Add('which', IntToStr(AEvent.GButton.Which));
      Add('button', IntToStr(AEvent.GButton.Button));
    end;
    TPMLEventKind.GamepadAdded, TPMLEventKind.GamepadRemoved, TPMLEventKind.GamepadRemapped,
    TPMLEventKind.GamepadUpdateComplete:
      Add('which', IntToStr(AEvent.JDevice.Which));
    TPMLEventKind.JoystickBatteryUpdated:
    begin
      Add('which', IntToStr(AEvent.JBattery.Which));
      Add('state', IntToStr(Ord(AEvent.JBattery.State)));
      Add('percent', IntToStr(AEvent.JBattery.Percent));
    end;
  end;
  Result := GetEnumName(TypeInfo(TPMLEventKind), Ord(AEvent.Kind)) + ' (' + Details + ')';
end;

end.
