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

  NOT RESOLVED:
    - 設計 §6.3 は複数 fd を 1 回の poll(2) で待つため IPMLEventPumpSource.GetPollFDs
      を要求するが、現時点の fd ソースは D-Bus 1 本だけで、待ちは
      dbus_connection_read_write のタイムアウトで正しく行える。Wayland バックエンド
      が 2 本目の fd を持ち込む時点で統合する
    - WakeUp は eventfd ではなくフラグ。上記と同じ時点で eventfd にする
    - 排他は SyncObjs。PaPiMeLa.Threading（#8）が TPMLMutex を提供したら差し替える
    - 状態機械（TPMLKeyboardState / TPMLMouseState / TPMLTouchState）は Video 着手時
    - リングバッファはキュー内部の配列。TPMLRingBuffer<T> の汎用化は必要になってから

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Events;

{$I papimela.inc}

interface

uses
  SysUtils, Classes, SyncObjs,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
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
    JoystickAxisMotion, JoystickHatMotion, JoystickButtonDown, JoystickButtonUp,
    JoystickAdded, JoystickRemoved, JoystickBatteryUpdated,
    GamepadAxisMotion, GamepadButtonDown, GamepadButtonUp, GamepadAdded,
    GamepadRemoved, GamepadRemapped,
    FingerDown, FingerUp, FingerMotion, FingerCanceled,
    ClipboardUpdate,
    DropFile, DropText, DropBegin, DropComplete, DropPosition,
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

  // ClipboardUpdate の付随情報。MIME タイプの並びは TPMLEvent.Strings に載る。
  TPMLClipboardEventData = record
    Owner           : Boolean;   // True = このアプリが置いた（SetText など）。False = 他のアプリ
    PrimarySelection: Boolean;   // True = プライマリ選択（中クリックで貼る方）
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
      // Display / JAxis / GAxis / Finger ... は各サブシステム着手時に追加する。
      // 可変部への追加は既存コードに影響しない。
  end;

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

  TPMLEventQueue = class;

  { キーボードの状態機械。バックエンドは Push を直接呼ばず、ここを通す（§6.3）。

    IME への転送（§7.5）もここで行う。IME が消費したキーは KeyDown も
    TextInput も発生させない。

    押下状態（IsDown）はキーの物理的な状態で、IME が消費したキーも押された
    ことになる（SDL も IME が扱ったキーの状態を更新する）。

    PORT-NOTE: 押下状態の規則は SDL_keyboard.c の SDL_SendKeyboardKeyInternal と
    SDL_ResetKeyboard に従う。押されていないキーの KeyUp は捨てる。押されている
    キーの KeyDown はリピートにする。フォーカスを失ったら、押されているキーを
    すべて KeyUp にしてから WindowFocusLost を積む。こうしないと、別のウィンドウで
    離したキーがこちらでは押されたまま残る。

    KeyUp は KeyDown を出したキーにだけ出す（D-47）。IME は押すほうを消費しても
    離すほうは消費しないことが多い（fcitx5-mozc・ibus-mozc とも実測）。逆に
    KeyDown を出した後で離すほうが消費されても KeyUp は出す。アプリから見て
    押したまま残らないようにする。 }
  TPMLKeyboardState = class sealed(TPMLSystemObject)
  strict private
    FQueue     : TPMLEventQueue;
    FModifiers : TPMLKeyModifiers;
    FFocusedWindow: TPMLWindowID;
    FConsumed  : Integer;
    FDown      : array[TPMLScancode] of Boolean;
    FEmittedDown: array[TPMLScancode] of Boolean;   // KeyDown をアプリへ出した
    FDeferred  : TPMLDeferredKeyQueue;
    FNextTicket: LongWord;
    FKeymap    : TPMLKeymap;
    FKeycodeOptions: TPMLKeycodeOptions;
    function  GetIsDown(AScancode: TPMLScancode): Boolean;
    procedure ReleaseAll(AWindowID: TPMLWindowID);
    procedure Emit(const AItem: TPMLDeferredKey; AWithText: Boolean);
    procedure Drain;
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
    property Keymap       : TPMLKeymap read FKeymap;
    // キーイベントのキーコードの決め方（SDL_HINT_KEYCODE_OPTIONS）。
    property KeycodeOptions: TPMLKeycodeOptions read FKeycodeOptions write FKeycodeOptions;
    property Modifiers    : TPMLKeyModifiers read FModifiers;
    property FocusedWindow: TPMLWindowID read FFocusedWindow;
    // IME が消費したキーの累計。テストと診断用。
    property ConsumedCount: Integer read FConsumed;
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
    procedure SendMotion(AWindowID: TPMLWindowID; AX, AY: Single);
    procedure SendButton(AWindowID: TPMLWindowID; AButton: LongWord; ADown: Boolean);
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
    procedure SendDown(AWindowID: TPMLWindowID; ADeviceID: LongWord;
      AFingerID: Int32; AX, AY: Single);
    // motion と up はウィンドウを取らない。Wayland が送ってこないので、down で
    // 覚えたウィンドウを使う。
    procedure SendMotion(ADeviceID: LongWord; AFingerID: Int32; AX, AY: Single);
    procedure SendUp(ADeviceID: LongWord; AFingerID: Int32);
    // 触っている指すべてを無効にする。コンポジタがジェスチャを奪ったときに来る。
    procedure SendCancel(ADeviceID: LongWord);
    function  TryGetFinger(AFingerID: Int32; out APoint: TPMLTouchPoint): Boolean;
    property FingerCount: Integer read GetFingerCount;
  end;

  TPMLEventQueue = class sealed(TPMLSystemObject)
  strict private
    FLock      : TCriticalSection;
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
    FKeyFilter : IPMLKeyFilter;
    function  TakeLocked(out AEvent: TPMLEvent): Boolean;
    function  NotifyWatches(const AEvent: TPMLEvent): Boolean;
    function  GetCapacity: Integer;
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

    property Enabled[AKind: TPMLEventKind]: Boolean read GetEnabled write SetEnabled;
    property PendingCount: Integer read FCount;
    property DroppedCount: Integer read FDroppedLog;
    // キューに溜められるイベントの数。作るときに 16 未満を指定すると 16。
    property Capacity: Integer read GetCapacity;

    // 状態機械。バックエンドはこれを通してイベントを流す（§6.3）。
    property Keyboard: TPMLKeyboardState read FKeyboard;
    property Mouse   : TPMLMouseState read FMouse;
    property Touch   : TPMLTouchState read FTouch;
    // Context が TextInput を生成したあとに差し込む。nil なら IME 転送なし。
    property KeyFilter: IPMLKeyFilter read FKeyFilter write FKeyFilter;
  end;

// 現在時刻（ナノ秒）。TPMLTimerService ができたらそちらへ委譲する。
function PMLNowNS: UInt64;

implementation

uses
  BaseUnix, UnixType;

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
  FLock := TCriticalSection.Create;
  for K := Low(TPMLEventKind) to High(TPMLEventKind) do
    FEnabled[K] := True;
  FNextUser := 0;
  FKeyboard := TPMLKeyboardState.Create(AContextRef, Self);
  FMouse := TPMLMouseState.Create(AContextRef, Self);
  FTouch := TPMLTouchState.Create(AContextRef, Self);
end;

// 輪の長さは作るときに決まり、以後変わらないので、ロックは要らない。
function TPMLEventQueue.GetCapacity: Integer;
begin
  Result := Length(FRing);
end;

destructor TPMLEventQueue.Destroy;
begin
  FKeyFilter := nil;
  FreeAndNil(FKeyboard);
  FreeAndNil(FMouse);
  FreeAndNil(FTouch);
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

  FLock.Acquire;
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
    FLock.Release;
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
  FLock.Acquire;
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
    FLock.Release;
  end;
end;

procedure TPMLEventQueue.Pump(ATimeoutMs: Integer);
var
  I: Integer;
begin
  CheckMainThread;
  for I := 0 to High(FSources) do
  begin
    // 待ちを許すのは最初のソースだけ（§6.3）。
    if I = 0 then
      FSources[I].PumpEvents(ATimeoutMs)
    else
      FSources[I].PumpEvents(0);
  end;
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
  FLock.Acquire;
  try
    for I := 0 to FCount - 1 do
      if FRing[(FHead + I) mod Length(FRing)].Kind = AKind then
        Exit(True);
  finally
    FLock.Release;
  end;
end;

procedure TPMLEventQueue.Flush(AKinds: TPMLEventKinds);
var
  I, W: Integer;
  Kept: array of TPMLEvent;
begin
  FLock.Acquire;
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
    FLock.Release;
  end;
end;

procedure TPMLEventQueue.FlushAll;
var
  I: Integer;
begin
  FLock.Acquire;
  try
    for I := 0 to FCount - 1 do
      FRing[(FHead + I) mod Length(FRing)] := Default(TPMLEvent);
    FHead := 0;
    FCount := 0;
  finally
    FLock.Release;
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

{ TPMLKeyboardState }

constructor TPMLKeyboardState.Create(AContextRef: TObject; AQueue: TPMLEventQueue);
begin
  inherited Create(AContextRef, AQueue);
  FQueue := AQueue;
  // 配列が届くまでは空のキーマップ。空は既定（US 配列）と同じ意味になる。
  FKeymap := TPMLKeymap.Create;
  FKeycodeOptions := PML_DEFAULT_KEYCODE_OPTIONS;
  FDeferred := TPMLDeferredKeyQueue.Create;
  FNextTicket := 1;
end;

destructor TPMLKeyboardState.Destroy;
begin
  FreeAndNil(FDeferred);
  FreeAndNil(FKeymap);
  inherited Destroy;
end;

function TPMLKeyboardState.GetIsDown(AScancode: TPMLScancode): Boolean;
begin
  Result := FDown[AScancode];
end;

function TPMLKeyboardState.DeferredCount: Integer;
begin
  Result := FDeferred.Count;
end;

procedure TPMLKeyboardState.SetKeymap(AKeymap: TPMLKeymap);
begin
  if (AKeymap = nil) or (AKeymap = FKeymap) then
    Exit;
  AKeymap.DetectLayout;
  FKeymap.Free;
  FKeymap := AKeymap;
  FQueue.PushSimple(TPMLEventKind.KeymapChanged, 0);
end;

{ 押されているキーをすべて離す（SDL_ResetKeyboard）。KeyUp は KeyDown を出した
  キーにだけ出す。IME には通さない。フォーカスを失う IME には別に NotifyFocus が届く。 }
procedure TPMLKeyboardState.ReleaseAll(AWindowID: TPMLWindowID);
var
  S: TPMLScancode;
  Ev: TPMLEvent;
begin
  for S := Low(TPMLScancode) to High(TPMLScancode) do
  begin
    FDown[S] := False;
    if FEmittedDown[S] then
    begin
      FEmittedDown[S] := False;
      FillChar(Ev.Key, SizeOf(Ev.Key), 0);
      Ev.Kind := TPMLEventKind.KeyUp;
      Ev.Timestamp := PMLNowNS;
      Ev.WindowID := AWindowID;
      Ev.Text := '';
      Ev.Segments := nil;
      Ev.Strings := nil;
      Ev.Key.Scancode := S;
      Ev.Key.Key := FKeymap.KeyForEvent(S, FKeycodeOptions);
      Ev.Key.Modifiers := FModifiers;
      FQueue.Push(Ev);
    end;
  end;
end;

procedure TPMLKeyboardState.SendModifiers(AModifiers: TPMLKeyModifiers);
begin
  FModifiers := AModifiers;
end;

procedure TPMLKeyboardState.SendFocus(AWindowID: TPMLWindowID; AGained: Boolean);
begin
  // IME にも伝える。フォーカスを失ったまま IME がこちらを注目し続けると、
  // 別アプリと二重にフォーカスを持つ状態になる。
  if Assigned(FQueue.KeyFilter) then
    FQueue.KeyFilter.NotifyFocus(AWindowID, AGained);

  if AGained then
  begin
    FFocusedWindow := AWindowID;
    FQueue.PushSimple(TPMLEventKind.WindowFocusGained, AWindowID);
  end
  else
  begin
    // 返信を待っているキーを先に出す（順序を保つ）。その後、離したキーの KeyUp は
    // フォーカスを失った後は届かないので、押されているキーを全部離す。
    FlushDeferred;
    ReleaseAll(AWindowID);
    if FFocusedWindow = AWindowID then
      FFocusedWindow := 0;
    FQueue.PushSimple(TPMLEventKind.WindowFocusLost, AWindowID);
  end;
end;

{ 結果の出たキー 1 つをアプリへ出す。

  押す: 消費されたら何も出さない。されなければ KeyDown と（あれば）TextInput。
  離す: KeyDown を出したキーなら、IME の結果によらず KeyUp を出す（D-47）。 }
procedure TPMLKeyboardState.Emit(const AItem: TPMLDeferredKey; AWithText: Boolean);
var
  Ev: TPMLEvent;
  Known: Boolean;
begin
  if AItem.Consumed then
    Inc(FConsumed);
  Known := AItem.Key.Scancode <> TPMLScancode.UNKNOWN;
  if AItem.Down then
  begin
    if AItem.Consumed then
      Exit;
    if Known then
      FEmittedDown[AItem.Key.Scancode] := True;
  end
  else if Known then
  begin
    if not FEmittedDown[AItem.Key.Scancode] then
      Exit;
    FEmittedDown[AItem.Key.Scancode] := False;
  end
  else if AItem.Consumed then
    Exit;

  FillChar(Ev.Key, SizeOf(Ev.Key), 0);
  if AItem.Down then
    Ev.Kind := TPMLEventKind.KeyDown
  else
    Ev.Kind := TPMLEventKind.KeyUp;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := AItem.WindowID;
  Ev.Text := '';
  Ev.Segments := nil;
  Ev.Strings := nil;
  Ev.Key := AItem.Key;
  FQueue.Push(Ev);

  // IME が受け取らなかった印字可能キーは、こちらで確定文字列にする。
  if AItem.Down and AWithText and (AItem.Text <> '') then
  begin
    FillChar(Ev.Key, SizeOf(Ev.Key), 0);
    Ev.Kind := TPMLEventKind.TextInput;
    Ev.Timestamp := PMLNowNS;
    Ev.WindowID := AItem.WindowID;
    Ev.Text := AItem.Text;
    Ev.Segments := nil;
    Ev.Strings := nil;
    FQueue.Push(Ev);
  end;
end;

{ 先頭から、結果の出ているキーを順に出す。未解決のキーに当たったら止める。 }
procedure TPMLKeyboardState.Drain;
var
  Item: TPMLDeferredKey;
begin
  while FDeferred.PopResolved(Item) do
    Emit(Item, True);
end;

procedure TPMLKeyboardState.ResolveKey(ATicket: LongWord; AConsumed: Boolean);
begin
  if FDeferred.Resolve(ATicket, AConsumed) then
    Drain;
end;

procedure TPMLKeyboardState.FlushDeferred;
var
  Item: TPMLDeferredKey;
begin
  while FDeferred.Pop(Item) do
    if Item.Resolved then
      Emit(Item, True)
    else
    begin
      Item.Consumed := False;
      Emit(Item, False);
    end;
end;

procedure TPMLKeyboardState.ExpireDeferred(ANowNS, ATimeoutNS: Int64);
begin
  if FDeferred.Count = 0 then
    Exit;
  if FDeferred.ExpireBefore(ANowNS - ATimeoutNS) > 0 then
    Drain;
end;

{ §7.5 の経路。

  1. IME が有効なら、押下も解放も IME に通す（修飾キー単独押下もエンジンが
     モード切替に使うため通す）
  2. 結果がすぐ出れば（Consumed / PassThrough）、待っているキーが無い限りその場で出す
  3. Deferred（非同期の返信待ち）なら並べて、ResolveKey を待つ。待っているキーが
     あれば、すぐ結果の出たキーもその後ろに並べる（順序を保つ） }
procedure TPMLKeyboardState.SendKey(AWindowID: TPMLWindowID;
  const AKey: TPMLKeyEventData; ADown: Boolean; const AText: String);
var
  Item: TPMLDeferredKey;
  Filtered: TPMLKeyFilterResult;
begin
  FModifiers := AKey.Modifiers;
  Item.Key := AKey;

  // 押下状態。IME に通す前に更新する（消費されたキーも物理的には押されている）。
  if Item.Key.Scancode <> TPMLScancode.UNKNOWN then
  begin
    if ADown then
    begin
      if FDown[Item.Key.Scancode] then
        Item.Key.IsRepeat := True;
    end
    else if not FDown[Item.Key.Scancode] then
      // 押されていないキーの KeyUp は捨てる。フォーカスを失ったときに
      // ReleaseAll が離したキーの、実際の KeyUp がここへ来る。
      Exit;
    FDown[Item.Key.Scancode] := ADown;
    if Item.Key.Key = PMLK_UNKNOWN then
      Item.Key.Key := FKeymap.KeyForEvent(Item.Key.Scancode, FKeycodeOptions);
  end;

  Item.Ticket := FNextTicket;
  Inc(FNextTicket);
  if FNextTicket = 0 then
    FNextTicket := 1;
  Item.WindowID := AWindowID;
  Item.Down := ADown;
  Item.Text := AText;
  Item.SinceNS := PMLNowNS;
  Item.Resolved := True;
  Item.Consumed := False;

  if Assigned(FQueue.KeyFilter) and FQueue.KeyFilter.KeyFilterActive then
  begin
    Filtered := FQueue.KeyFilter.FilterKey(Item.Key, not ADown, Item.Ticket);
    case Filtered of
      TPMLKeyFilterResult.Consumed: Item.Consumed := True;
      TPMLKeyFilterResult.Deferred: Item.Resolved := False;
    else
    end;
  end;

  if Item.Resolved and (FDeferred.Count = 0) then
    Emit(Item, True)
  else
  begin
    FDeferred.Add(Item);
    Drain;
  end;
end;

{ TPMLMouseState }

constructor TPMLMouseState.Create(AContextRef: TObject; AQueue: TPMLEventQueue);
begin
  inherited Create(AContextRef, AQueue);
  FQueue := AQueue;
end;

procedure TPMLMouseState.SendMotion(AWindowID: TPMLWindowID; AX, AY: Single);
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
  Ev.Motion.X := AX;
  Ev.Motion.Y := AY;
  Ev.Motion.XRel := AX - FX;
  Ev.Motion.YRel := AY - FY;
  FX := AX;
  FY := AY;
  FQueue.Push(Ev);
end;

procedure TPMLMouseState.SendButton(AWindowID: TPMLWindowID;
  AButton: LongWord; ADown: Boolean);
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
  AFingerID: Int32; AX, AY: Single);
var
  I: Integer;
  P: TPMLTouchPoint;
begin
  P.DeviceID := ADeviceID;
  P.FingerID := AFingerID;
  P.WindowID := AWindowID;
  P.X := AX;
  P.Y := AY;
  P.Pressure := 1.0;

  // 同じ id が離されずに再度 down することは仕様上ないが、来ても壊れないようにする。
  I := IndexOf(AFingerID);
  if I < 0 then
  begin
    SetLength(FFingers, Length(FFingers) + 1);
    I := High(FFingers);
  end;
  FFingers[I] := P;
  Emit(TPMLEventKind.FingerDown, P, 0, 0);
end;

procedure TPMLTouchState.SendMotion(ADeviceID: LongWord; AFingerID: Int32;
  AX, AY: Single);
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
  Emit(TPMLEventKind.FingerMotion, FFingers[I], DX, DY);
end;

procedure TPMLTouchState.SendUp(ADeviceID: LongWord; AFingerID: Int32);
var
  I, J: Integer;
  P: TPMLTouchPoint;
begin
  I := IndexOf(AFingerID);
  if I < 0 then
    Exit;
  // wl_touch.up は座標を送らない。最後に分かっている位置をそのまま載せる。
  P := FFingers[I];
  P.Pressure := 0.0;
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

end.
