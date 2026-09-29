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
  PaPiMeLa.Core.Base;

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

    NOT RESOLVED:
      Scancode（USB HID Usage 準拠の列挙）は TPMLKeyboardState と同時に追加する。
      現状は IME 経路が必要とする X11/XKB キーシムと evdev キーコードのみ。 }
  TPMLKeyEventData = record
    Keysym    : LongWord;          // X11 / XKB キーシム。Fcitx5 / IBus がこれで話す
    Keycode   : LongWord;          // evdev + 8（X11 慣習）
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
    Strings  : TPMLStringArray;            // TextEditingCandidates
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
    function FilterKey(const AKey: TPMLKeyEventData;
      AIsRelease: Boolean): TPMLKeyFilterResult;
  end;

  TPMLEventQueue = class;

  { キーボードの状態機械。バックエンドは Push を直接呼ばず、ここを通す（§6.3）。

    IME への転送（§7.5）もここで行う。IME が消費したキーは KeyDown も
    TextInput も発生させない。 }
  TPMLKeyboardState = class sealed(TPMLSystemObject)
  strict private
    FQueue     : TPMLEventQueue;
    FModifiers : TPMLKeyModifiers;
    FFocusedWindow: TPMLWindowID;
    FConsumed  : Integer;
  public
    constructor Create(AContextRef: TObject; AQueue: TPMLEventQueue);
    // バックエンドが呼ぶ唯一の入口。AText は xkb が求めた確定文字列（無ければ空）。
    procedure SendKey(AWindowID: TPMLWindowID; const AKey: TPMLKeyEventData;
      ADown: Boolean; const AText: String);
    procedure SendModifiers(AModifiers: TPMLKeyModifiers);
    procedure SendFocus(AWindowID: TPMLWindowID; AGained: Boolean);
    property Modifiers    : TPMLKeyModifiers read FModifiers;
    property FocusedWindow: TPMLWindowID read FFocusedWindow;
    // IME が消費したキーの累計。テストと診断用。
    property ConsumedCount: Integer read FConsumed;
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
    procedure SendFocus(AWindowID: TPMLWindowID; AEntered: Boolean);
    property X: Single read FX;
    property Y: Single read FY;
    property ButtonState: LongWord read FButtonState;
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
    FKeyFilter : IPMLKeyFilter;
    function  TakeLocked(out AEvent: TPMLEvent): Boolean;
    function  NotifyWatches(const AEvent: TPMLEvent): Boolean;
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

    // 状態機械。バックエンドはこれを通してイベントを流す（§6.3）。
    property Keyboard: TPMLKeyboardState read FKeyboard;
    property Mouse   : TPMLMouseState read FMouse;
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
end;

destructor TPMLEventQueue.Destroy;
begin
  FKeyFilter := nil;
  FreeAndNil(FKeyboard);
  FreeAndNil(FMouse);
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

{ TPMLKeyboardState }

constructor TPMLKeyboardState.Create(AContextRef: TObject; AQueue: TPMLEventQueue);
begin
  inherited Create(AContextRef, AQueue);
  FQueue := AQueue;
end;

procedure TPMLKeyboardState.SendModifiers(AModifiers: TPMLKeyModifiers);
begin
  FModifiers := AModifiers;
end;

procedure TPMLKeyboardState.SendFocus(AWindowID: TPMLWindowID; AGained: Boolean);
begin
  if AGained then
  begin
    FFocusedWindow := AWindowID;
    FQueue.PushSimple(TPMLEventKind.WindowFocusGained, AWindowID);
  end
  else
  begin
    if FFocusedWindow = AWindowID then
      FFocusedWindow := 0;
    FQueue.PushSimple(TPMLEventKind.WindowFocusLost, AWindowID);
  end;
end;

{ §7.5 の経路。

  1. IME が有効なら、押下も解放も IME に通す（修飾キー単独押下もエンジンが
     モード切替に使うため通す）
  2. Consumed なら KeyDown も TextInput も出さずに終わる
  3. PassThrough なら通常どおり KeyDown / KeyUp を出し、xkb が文字を求めていれば
     TextInput も出す

  Deferred（非同期返信待ち）は現在のバックエンドが返さないので、保留キューは
  実装していない。IBus の非同期化（§10 項目 3）と同時に入れる。 }
procedure TPMLKeyboardState.SendKey(AWindowID: TPMLWindowID;
  const AKey: TPMLKeyEventData; ADown: Boolean; const AText: String);
var
  Ev: TPMLEvent;
  Filtered: TPMLKeyFilterResult;
begin
  FModifiers := AKey.Modifiers;

  if Assigned(FQueue.KeyFilter) and FQueue.KeyFilter.KeyFilterActive then
  begin
    Filtered := FQueue.KeyFilter.FilterKey(AKey, not ADown);
    if Filtered = TPMLKeyFilterResult.Consumed then
    begin
      Inc(FConsumed);
      Exit;
    end;
  end;

  FillChar(Ev.Key, SizeOf(Ev.Key), 0);
  if ADown then
    Ev.Kind := TPMLEventKind.KeyDown
  else
    Ev.Kind := TPMLEventKind.KeyUp;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := AWindowID;
  Ev.Text := '';
  Ev.Segments := nil;
  Ev.Strings := nil;
  Ev.Key := AKey;
  FQueue.Push(Ev);

  // IME が受け取らなかった印字可能キーは、こちらで確定文字列にする。
  if ADown and (AText <> '') then
  begin
    FillChar(Ev.Key, SizeOf(Ev.Key), 0);
    Ev.Kind := TPMLEventKind.TextInput;
    Ev.Timestamp := PMLNowNS;
    Ev.WindowID := AWindowID;
    Ev.Text := AText;
    Ev.Segments := nil;
    Ev.Strings := nil;
    FQueue.Push(Ev);
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

end.
