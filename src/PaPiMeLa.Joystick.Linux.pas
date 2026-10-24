{
  PaPiMeLa.Joystick.Linux — Linux（evdev）のジョイスティック

  Origin : ported from SDL (src/joystick/linux/SDL_sysjoystick.c, src/core/linux/SDL_evdev.c)
           Scope: LINUX_JoystickXxx の入り口、機器の見つけ方（udev・inotify・3 秒ごとの一覧の見直し、
           SDL_JOYSTICK_DEVICE）、IsJoystick（名前と GUID、禁止の判定）、ConfigJoystick（ボタン・軸・ハット・ボールの
           割り当てと、軸の補正の用意）、AxisCorrect、HandleHat、HandleBall、PollAllValues、HandleInputEvents
           （SYN_DROPPED からの復帰を含む）、ランブル（ff_rumble と ff_sine）、LINUX_JoystickGetGamepadMapping
           （Linux Gamepad Specification の割り当て）、SDL_EVDEV_GetEventTimestamp。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #60

  WHAT:
    /dev/input/event* の機器を、ジョイスティックのバックエンド（TPMLJoystickBackend）として見せる。
    機器への触り方は PaPiMeLa.Joystick.Linux.Node の抽象（TPMLEvdevHost・TPMLEvdevNode）を通す。
    本物は既定で使い、検査は偽物（PMLLinuxJoystickHostFactory で差し込む）を使う。

  RESOLVED:
    - 軸の補正は SDL のまま: 既定は範囲を -32768..32767 へ線形に伸ばし、ヒントで死帯域を使う
    - 軸の補正の計算は、SDL の float と同じに Single で行う（Double に広げない）
    - 外れた機器（ENODEV）は、次の Detect まで一覧に残す
    - コードが配列の外のイベントは捨てる（SDL は 8 ビットの添字で 0xFF を使う。結果は同じ）

  NOT RESOLVED:
    - 旧 js のインターフェース（SDL_HINT_JOYSTICK_LINUX_CLASSIC）、加速度・ジャイロ（別の機器をひも付ける）、
      Steam の仮想ゲームパッドの並べ替え、xow の仮想機器は移植しない

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Joystick.Linux;

{$I papimela.inc}

interface

uses
  SysUtils, Classes, Math,
  PaPiMeLa.Properties,
  PaPiMeLa.Joystick.GUID,
  PaPiMeLa.Joystick.Backend,
  PaPiMeLa.Platform.Evdev,
  PaPiMeLa.Joystick.Linux.Node;

type
  TPMLLinuxHostFactory = function: TPMLEvdevHost;

var
  { 機器の窓口を作る工場。nil なら本物（/dev/input）。検査が偽物を差し込む。 }
  PMLLinuxJoystickHostFactory: TPMLLinuxHostFactory = nil;

type
  TLinuxHwData = class;

  // 一覧の 1 台（SDL_joylist_item）
  TLinuxItem = class
  public
    InstanceID    : TPMLJoystickID;
    Path          : String;
    Name          : String;
    Driver        : String;
    Vendor        : Word;
    Product       : Word;
    GUID          : TPMLGUID;
    DevNum        : QWord;
    Hw            : TLinuxHwData;
    CheckedMapping: Boolean;
    HasMapping    : Boolean;
    Mapping       : TPMLGamepadMapping;
  end;

  // 軸の補正（struct axis_correct）
  TAxisCorrect = record
    UseDeadzones: Boolean;
    Coef        : array[0..2] of Integer;
    Minimum     : Integer;
    Maximum     : Integer;
    Scale       : Single;
  end;

  // ハットの補正（struct hat_axis_correct）
  THatCorrect = record
    UseDeadzones: Boolean;
    Minimum     : array[0..1] of Integer;
    Maximum     : array[0..1] of Integer;
  end;

  // 開いた機器の中身（struct joystick_hwdata）
  TLinuxHwData = class
  public
    Node         : TPMLEvdevNode;
    Item         : TLinuxItem;
    FFRumble     : Boolean;
    FFSine       : Boolean;
    Effect       : TPMLFFEffect;
    Balls        : array of array[0..1] of Integer;
    Hats         : array of array[0..1] of Integer;
    KeyMap       : array[0..KEY_MAX] of Byte;
    AbsMap       : array[0..ABS_MAX] of Byte;
    HasKey       : array[0..KEY_MAX] of Boolean;
    HasAbs       : array[0..ABS_MAX] of Boolean;
    AbsCorrect   : array[0..ABS_MAX] of TAxisCorrect;
    HatsIndices  : array[0..3] of Integer;
    HasHat       : array[0..3] of Boolean;
    HatCorrect   : array[0..3] of THatCorrect;
    Fresh        : Boolean;
    Recovering   : Boolean;
    Gone         : Boolean;
    NumAxes, NumBalls, NumHats, NumButtons: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TPMLLinuxJoystickBackend = class sealed(TPMLJoystickBackend)
  strict private
    FHost           : TPMLEvdevHost;
    FOwnsHost       : Boolean;
    FItems          : array of TLinuxItem;
    FMethod         : TPMLHotplugMethod;
    FLastDetectTime : UInt64;
    FLastInputMTime : Int64;
    FTimestampOffset: UInt64;
    FUdevMode       : Boolean;
    FDevicesChecked : Boolean;
    function  FindByDevNum(ADevNum: QWord): TLinuxItem;
    function  GuessDeviceClass(ANode: TPMLEvdevNode): Integer;
    function  IsJoystick(const APath: String; ANode: TPMLEvdevNode; out AName, ADriver: String;
      out AVendor, AProduct: Word; out AGUID: TPMLGUID): Boolean;
    procedure MaybeAddDevice(const APath: String);
    procedure MaybeRemoveDevice(const APath: String);
    procedure HandlePendingRemovals;
    procedure RemoveItem(AIndex: Integer);
    procedure OnHotplug(AKind: TPMLHotplugKind; AClass: Integer; const APath: String);
    procedure FallbackDetect;
    procedure ScanInputDevices;
    function  PrepareHwData(AItem: TLinuxItem; AHw: TLinuxHwData): Boolean;
    procedure ConfigJoystick(AHw: TLinuxHwData);
    function  GuessIfAxesAreDigitalHat(AHasX: Boolean; const AX: TPMLInputAbsInfo; AHasY: Boolean;
      const AY: TPMLInputAbsInfo): Boolean;
    function  EventTimestamp(const AEvent: TPMLInputEvent): UInt64;
    function  AxisCorrect(AHw: TLinuxHwData; AWhich, AValue: Integer): Integer;
    procedure HandleHat(ATimestamp: UInt64; AJoystick: TPMLJoystick; AHw: TLinuxHwData; AHatIdx, AAxis, AValue: Integer);
    procedure PollAllValues(ATimestamp: UInt64; AJoystick: TPMLJoystick; AHw: TLinuxHwData);
    procedure HandleInputEvents(AJoystick: TPMLJoystick; AHw: TLinuxHwData);
    function  ItemAt(AIndex: Integer): TLinuxItem;
  public
    { AHost を渡すと、それを使う（検査用。壊すのは呼び出し側）。nil なら PMLLinuxJoystickHostFactory、
      それも nil なら本物。 }
    constructor Create(ACore: TPMLJoystickCore; AHost: TPMLEvdevHost = nil);
    destructor Destroy; override;

    function  Name: String; override;
    function  Init: Boolean; override;
    function  DeviceCount: Integer; override;
    procedure Detect; override;
    function  DeviceName(AIndex: Integer): String; override;
    function  DevicePath(AIndex: Integer): String; override;
    function  DeviceGUID(AIndex: Integer): TPMLGUID; override;
    function  DeviceInstanceID(AIndex: Integer): TPMLJoystickID; override;
    function  Open(AJoystick: TPMLJoystick; AIndex: Integer): Boolean; override;
    function  Rumble(AJoystick: TPMLJoystick; ALow, AHigh: Word): Boolean; override;
    procedure Update(AJoystick: TPMLJoystick); override;
    procedure Close(AJoystick: TPMLJoystick); override;
    procedure Quit; override;
    function  GamepadMapping(AIndex: Integer; out AMapping: TPMLGamepadMapping): Boolean; override;
    // 見つけ方（検査用）。
    property  HotplugMethod: TPMLHotplugMethod read FMethod;
  end;

implementation

const
  AXIS_MIN = PML_JOYSTICK_AXIS_MIN;
  AXIS_MAX = PML_JOYSTICK_AXIS_MAX;
  DetectIntervalMS = 3000;
  EventBatch = 32;

{ TLinuxHwData }

constructor TLinuxHwData.Create;
begin
  inherited Create;
  FillChar(KeyMap, SizeOf(KeyMap), $FF);
  FillChar(AbsMap, SizeOf(AbsMap), $FF);
  FillChar(Effect, SizeOf(Effect), 0);
  Effect.ID := -1;
end;

destructor TLinuxHwData.Destroy;
begin
  FreeAndNil(Node);
  inherited Destroy;
end;

{ ---- 小さな部品 ---- }

function BaseName(const APath: String): String;
var
  P: Integer;
begin
  P := LastDelimiter('/', APath);
  Result := Copy(APath, P + 1, MaxInt);
end;

function IsInteger(const AText: String): Boolean;
var
  I: Integer;
begin
  if AText = '' then
    Exit(False);
  for I := 1 to Length(AText) do
    if not (AText[I] in ['0'..'9']) then
      Exit(False);
  Result := True;
end;

function IsEventNode(const ANode: String): Boolean;
var
  N: String;
begin
  N := BaseName(ANode);
  Result := (Copy(N, 1, 5) = 'event') and IsInteger(Copy(N, 6, MaxInt));
end;

function IsJSNode(const ANode: String): Boolean;
var
  N: String;
begin
  N := BaseName(ANode);
  Result := (Copy(N, 1, 2) = 'js') and IsInteger(Copy(N, 3, MaxInt));
end;

{ ---- 作る・壊す ---- }

constructor TPMLLinuxJoystickBackend.Create(ACore: TPMLJoystickCore; AHost: TPMLEvdevHost);
begin
  inherited Create(ACore);
  if AHost <> nil then
    FHost := AHost
  else if Assigned(PMLLinuxJoystickHostFactory) then
  begin
    FHost := PMLLinuxJoystickHostFactory();
    FOwnsHost := True;
  end
  else
  begin
    FHost := TPMLRealEvdevHost.Create;
    FOwnsHost := True;
  end;
end;

destructor TPMLLinuxJoystickBackend.Destroy;
begin
  Quit;
  if FOwnsHost then
    FHost.Free;
  inherited Destroy;
end;

function TPMLLinuxJoystickBackend.Name: String;
begin
  Result := 'linux';
end;

function TPMLLinuxJoystickBackend.ItemAt(AIndex: Integer): TLinuxItem;
begin
  if (AIndex < 0) or (AIndex >= Length(FItems)) then
    Result := nil
  else
    Result := FItems[AIndex];
end;

function TPMLLinuxJoystickBackend.FindByDevNum(ADevNum: QWord): TLinuxItem;
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
    if FItems[I].DevNum = ADevNum then
      Exit(FItems[I]);
  Result := nil;
end;

{ ---- 機器の判定 ---- }

function TPMLLinuxJoystickBackend.GuessDeviceClass(ANode: TPMLEvdevNode): Integer;
var
  Props, Ev, Key, Abs_, Rel: TPMLBits;
begin
  Result := 0;
  if not (ANode.GetBits(0, EV_MAX + 1, Ev) and ANode.GetBits(EV_KEY, KEY_MAX + 1, Key)
    and ANode.GetBits(EV_REL, REL_MAX + 1, Rel) and ANode.GetBits(EV_ABS, ABS_MAX + 1, Abs_)) then
    Exit;
  // 新しい仕組みなので、失敗してよい（性質が無いだけ）
  if not ANode.GetProps(Props) then
  begin
    SetLength(Props, PMLBitsLength(INPUT_PROP_MAX + 1));
    FillChar(Props[0], Length(Props), 0);
  end;
  Result := PMLEvdevGuessDeviceClass(Props, Ev, Abs_, Key, Rel);
end;

function TPMLLinuxJoystickBackend.IsJoystick(const APath: String; ANode: TPMLEvdevNode;
  out AName, ADriver: String; out AVendor, AProduct: Word; out AGUID: TPMLGUID): Boolean;
var
  ID: TPMLInputID;
  ProductString: String;
  DevClass: Integer;
  Keys: TPMLBits;
begin
  Result := False;
  AName := '';
  ADriver := '';
  FillChar(ID, SizeOf(ID), 0);
  DevClass := 0;
  // 機器を開くと同期した I/O が起きることがあるので、udev で分かれば先に断る
  if FHost.ProductInfo(APath, ID, DevClass, ADriver) and ((DevClass and PML_UDEV_DEVICE_JOYSTICK) = 0) then
    Exit;
  if ANode = nil then
    Exit;

  if not ANode.GetJsName(ProductString) then
  begin
    // udev で列挙・分類したときは、ここに来るのはジョイスティックだけなので確かめない
    if (not FUdevMode) and (DevClass = 0) and
      ((GuessDeviceClass(ANode) and PML_UDEV_DEVICE_JOYSTICK) = 0) then
      Exit;
    // udev から ID を取れていても、evdev と一致するはず
    if not ANode.GetID(ID) then
      Exit;
    if not ANode.GetName(ProductString) then
      Exit;
  end;

  AName := Core.CreateJoystickName(ID.Vendor, ID.Product, '', ProductString);
  if AName = '' then
    Exit;
  if Core.HandledByAnotherBackend(Self, ID.Vendor, ID.Product, ID.Version, AName) then
    Exit;

  // Xbox One Elite Series 2 の最初のファームウェアは入力を二重に持つ。割り当てを分けるため版を変える
  if (ID.Vendor = $045E) and (ID.Product = $0B05) and (ID.Version = $0903) then
    if ANode.GetBits(EV_KEY, KEY_MAX + 1, Keys) and PMLTestBit(Keys, $2C0) then
      ID.Version := $0902;
  // Atari VCS のコントローラは、版がファームウェアの版で、割り当ては変わらない
  if (ID.Vendor = $3250) and ((ID.Product = $1001) or (ID.Product = $1002)) then
    ID.Version := 0;

  if Core.ShouldIgnoreDevice(ID.Vendor, ID.Product, ID.Version, AName) then
    Exit;

  AVendor := ID.Vendor;
  AProduct := ID.Product;
  AGUID := PMLCreateJoystickGUID(ID.BusType, ID.Vendor, ID.Product, ID.Version, '', ProductString, 0, 0);
  Result := True;
end;

procedure TPMLLinuxJoystickBackend.MaybeAddDevice(const APath: String);
var
  Node: TPMLEvdevNode;
  DevNum: QWord;
  Item: TLinuxItem;
  ItemName, Driver: String;
  Vendor, Product: Word;
  GUID: TPMLGUID;
begin
  if APath = '' then
    Exit;
  Node := FHost.OpenNode(APath, False);
  if Node = nil then
    Exit;
  try
    if not FHost.DeviceNumber(APath, DevNum) then
      Exit;
    Core.Lock;
    try
      // もう持っている機器
      if FindByDevNum(DevNum) <> nil then
        Exit;
      if IsJoystick(APath, Node, ItemName, Driver, Vendor, Product, GUID) then
      begin
        Item := TLinuxItem.Create;
        Item.DevNum := DevNum;
        Item.Path := APath;
        Item.Vendor := Vendor;
        Item.Product := Product;
        Item.Name := ItemName;
        Item.GUID := GUID;
        Item.Driver := Driver;
        Item.InstanceID := Core.NextInstanceID;
        SetLength(FItems, Length(FItems) + 1);
        FItems[High(FItems)] := Item;
        // 数を増やしてから知らせる
        Core.DeviceAdded(Item.InstanceID);
      end;
    finally
      Core.Unlock;
    end;
  finally
    Node.Free;
  end;
end;

procedure TPMLLinuxJoystickBackend.RemoveItem(AIndex: Integer);
var
  Item: TLinuxItem;
  I: Integer;
begin
  Item := FItems[AIndex];
  if Item.Hw <> nil then
    Item.Hw.Item := nil;
  for I := AIndex to High(FItems) - 1 do
    FItems[I] := FItems[I + 1];
  SetLength(FItems, Length(FItems) - 1);
  // 数を減らしてから知らせる
  Core.DeviceRemoved(Item.InstanceID);
  Item.Free;
end;

procedure TPMLLinuxJoystickBackend.MaybeRemoveDevice(const APath: String);
var
  I: Integer;
begin
  if APath = '' then
    Exit;
  Core.Lock;
  try
    for I := 0 to High(FItems) do
      if FItems[I].Path = APath then
      begin
        RemoveItem(I);
        Exit;
      end;
  finally
    Core.Unlock;
  end;
end;

procedure TPMLLinuxJoystickBackend.HandlePendingRemovals;
var
  I: Integer;
begin
  I := 0;
  while I < Length(FItems) do
    if (FItems[I].Hw <> nil) and FItems[I].Hw.Gone then
      RemoveItem(I)
    else
      Inc(I);
end;

procedure TPMLLinuxJoystickBackend.OnHotplug(AKind: TPMLHotplugKind; AClass: Integer; const APath: String);
begin
  if APath = '' then
    Exit;
  if AClass >= 0 then
  begin
    // udev
    if AKind = TPMLHotplugKind.Added then
    begin
      if (AClass and (PML_UDEV_DEVICE_JOYSTICK or PML_UDEV_DEVICE_ACCELEROMETER)) = 0 then
        Exit;
      if IsJSNode(APath) then
        Exit;
      // hidraw の udev ノードが整うのを少し待つ
      Sleep(10);
      MaybeAddDevice(APath);
    end
    else
      MaybeRemoveDevice(APath);
  end
  else if IsEventNode(APath) then
  begin
    // inotify
    if AKind = TPMLHotplugKind.Added then
      MaybeAddDevice(APath)
    else
      MaybeRemoveDevice(APath);
  end;
end;

{ ---- 一覧の見直し ---- }

procedure TPMLLinuxJoystickBackend.ScanInputDevices;
var
  Names: TStringArray;
  Sorted: array of Integer;     // 番号
  Js: array of Integer;
  I, J, N, T: Integer;

  // sort_entries: js の番号が分かるものを先に、その中は js の番号で、他は event の番号で
  function Less(X, Y: Integer): Boolean;
  var
    JX, JY: Integer;
  begin
    JX := Js[X];
    JY := Js[Y];
    if (JX >= 0) and (JY >= 0) then
      Exit(JX < JY);
    if JX >= 0 then
      Exit(True);
    if JY >= 0 then
      Exit(False);
    Result := Sorted[X] < Sorted[Y];
  end;

var
  Order: array of Integer;
begin
  Names := FHost.ListInputDirectory;
  N := 0;
  for I := 0 to High(Names) do
    if IsEventNode(Names[I]) then
    begin
      SetLength(Sorted, N + 1);
      SetLength(Js, N + 1);
      Sorted[N] := StrToInt(Copy(Names[I], 6, MaxInt));
      Js[N] := FHost.JsIndexForEvent(Sorted[N]);
      Inc(N);
    end;
  SetLength(Order, N);
  for I := 0 to N - 1 do
    Order[I] := I;
  // 挿入ソート（同じなら元の順）
  for I := 1 to N - 1 do
  begin
    T := Order[I];
    J := I - 1;
    while (J >= 0) and Less(T, Order[J]) do
    begin
      Order[J + 1] := Order[J];
      Dec(J);
    end;
    Order[J + 1] := T;
  end;
  for I := 0 to N - 1 do
    MaybeAddDevice('/dev/input/event' + IntToStr(Sorted[Order[I]]));
end;

procedure TPMLLinuxJoystickBackend.FallbackDetect;
var
  Now_: UInt64;
  MTime: Int64;
begin
  Now_ := FHost.TicksMS;
  if (FLastDetectTime = 0) or (Now_ >= FLastDetectTime + DetectIntervalMS) then
  begin
    // 機器を開くと同期した I/O が起きることがあるので、ディレクトリが変わっていなければ見ない
    if FHost.InputDirectoryMTime(MTime) and (MTime <> FLastInputMTime) then
    begin
      ScanInputDevices;
      FLastInputMTime := MTime;
    end;
    FLastDetectTime := Now_;
    if FLastDetectTime = 0 then
      FLastDetectTime := 1;
  end;
end;

procedure TPMLLinuxJoystickBackend.Detect;
begin
  if FUdevMode or (FMethod = TPMLHotplugMethod.Inotify) then
  begin
    if FLastDetectTime <> 0 then
      FHost.PollHotplug
    else
      FallbackDetect;
  end
  else
    FallbackDetect;
  HandlePendingRemovals;
end;

function TPMLLinuxJoystickBackend.Init: Boolean;
var
  Devices: String;
  Parts: TStringList;
  I: Integer;
  UseUdev: Boolean;
begin
  FUdevMode := False;
  FMethod := TPMLHotplugMethod.None;

  // 使う機器を指定されていれば、それを先に足す
  Devices := Core.Hint(PML_HINT_JOYSTICK_DEVICE);
  if Devices <> '' then
  begin
    Parts := TStringList.Create;
    try
      Parts.StrictDelimiter := True;
      Parts.Delimiter := ':';
      Parts.DelimitedText := Devices;
      for I := 0 to Parts.Count - 1 do
        MaybeAddDevice(Parts[I]);
    finally
      Parts.Free;
    end;
  end;

  // 初めに一覧を直接見る（udev は番号の順に並べてくれないので）
  FLastDetectTime := 0;
  FLastInputMTime := 0;
  FallbackDetect;

  UseUdev := not PMLStringBoolean(Core.Hint(PML_HINT_JOYSTICK_DISABLE_UDEV), False);
  if UseUdev and FHost.Sandboxed then
    UseUdev := False;      // コンテナの中では udev を使わない
  FMethod := FHost.StartHotplug(UseUdev, @OnHotplug);
  if FMethod = TPMLHotplugMethod.Udev then
  begin
    FUdevMode := True;
    // 今ある機器で一覧を作り直す（持っている機器は番号で飛ばされる）
    FHost.ScanHotplug;
  end;
  Result := True;
end;

procedure TPMLLinuxJoystickBackend.Quit;
var
  I: Integer;
begin
  if FHost <> nil then
    FHost.StopHotplug;
  for I := 0 to High(FItems) do
    FItems[I].Free;
  FItems := nil;
end;

{ ---- 機器の問い合わせ ---- }

function TPMLLinuxJoystickBackend.DeviceCount: Integer;
begin
  Result := Length(FItems);
end;

function TPMLLinuxJoystickBackend.DeviceName(AIndex: Integer): String;
begin
  Result := FItems[AIndex].Name;
end;

function TPMLLinuxJoystickBackend.DevicePath(AIndex: Integer): String;
begin
  Result := FItems[AIndex].Path;
end;

function TPMLLinuxJoystickBackend.DeviceGUID(AIndex: Integer): TPMLGUID;
begin
  Result := FItems[AIndex].GUID;
end;

function TPMLLinuxJoystickBackend.DeviceInstanceID(AIndex: Integer): TPMLJoystickID;
begin
  Result := FItems[AIndex].InstanceID;
end;

{ ---- 開く ---- }

function TPMLLinuxJoystickBackend.GuessIfAxesAreDigitalHat(AHasX: Boolean; const AX: TPMLInputAbsInfo;
  AHasY: Boolean; const AY: TPMLInputAbsInfo): Boolean;
begin
  // どちらの軸も無ければ何でもない
  if not AHasX and not AHasY then
    Exit(False);
  // ヒントが言えば、全部をデジタルのハットとして扱う
  if PMLStringBoolean(Core.Hint(PML_HINT_JOYSTICK_LINUX_DIGITAL_HATS), False) then
    Exit(True);
  // 範囲が -1..1 に収まるなら、確かにデジタル
  if ((not AHasX) or ((AX.Minimum = -1) and (AX.Maximum = 1)))
  and ((not AHasY) or ((AY.Minimum = -1) and (AY.Maximum = 1))) then
    Exit(True);
  // fuzz・flat・resolution のどれも無ければ、たぶんデジタル
  if ((not AHasX) or ((AX.Fuzz = 0) and (AX.Flat = 0) and (AX.Resolution = 0)))
  and ((not AHasY) or ((AY.Fuzz = 0) and (AY.Flat = 0) and (AY.Resolution = 0))) then
    Exit(True);
  Result := False;
end;

procedure TPMLLinuxJoystickBackend.ConfigJoystick(AHw: TLinuxHwData);
var
  Key, Abs_, Rel, FF: TPMLBits;
  I, T, HatIndex: Integer;
  HatX, HatY: Boolean;
  AX, AY, Info: TPMLInputAbsInfo;
  UseDeadzones, UseHatDeadzones: Boolean;
  ValueRange, OutputRange: Single;
  Node: TPMLEvdevNode;
begin
  Node := AHw.Node;
  UseDeadzones := PMLStringBoolean(Core.Hint(PML_HINT_JOYSTICK_LINUX_DEADZONES), False);
  UseHatDeadzones := PMLStringBoolean(Core.Hint(PML_HINT_JOYSTICK_LINUX_HAT_DEADZONES), True);

  if Node.GetBits(EV_KEY, KEY_MAX + 1, Key) and Node.GetBits(EV_ABS, ABS_MAX + 1, Abs_)
  and Node.GetBits(EV_REL, REL_MAX + 1, Rel) then
  begin
    // ボタンは、ジョイスティックのコードから先、そのあと手前の順に番号を振る
    for I := BTN_JOYSTICK to KEY_MAX - 1 do
      if PMLTestBit(Key, I) then
      begin
        AHw.KeyMap[I] := Byte(AHw.NumButtons);
        AHw.HasKey[I] := True;
        Inc(AHw.NumButtons);
      end;
    for I := 0 to BTN_JOYSTICK - 1 do
      if PMLTestBit(Key, I) then
      begin
        AHw.KeyMap[I] := Byte(AHw.NumButtons);
        AHw.HasKey[I] := True;
        Inc(AHw.NumButtons);
      end;

    // デジタルのハット
    I := ABS_HAT0X;
    while I <= ABS_HAT3Y do
    begin
      HatX := False;
      HatY := False;
      FillChar(AX, SizeOf(AX), 0);
      FillChar(AY, SizeOf(AY), 0);
      if PMLTestBit(Abs_, I) then
        HatX := Node.GetAbsInfo(I, AX);
      if PMLTestBit(Abs_, I + 1) then
        HatY := Node.GetAbsInfo(I + 1, AY);
      if GuessIfAxesAreDigitalHat(HatX, AX, HatY, AY) then
      begin
        HatIndex := (I - ABS_HAT0X) div 2;
        AHw.HatsIndices[HatIndex] := AHw.NumHats;
        AHw.HasHat[HatIndex] := True;
        AHw.HatCorrect[HatIndex].UseDeadzones := UseHatDeadzones;
        if HatX then AHw.HatCorrect[HatIndex].Minimum[0] := AX.Minimum else AHw.HatCorrect[HatIndex].Minimum[0] := -1;
        if HatX then AHw.HatCorrect[HatIndex].Maximum[0] := AX.Maximum else AHw.HatCorrect[HatIndex].Maximum[0] := 1;
        if HatY then AHw.HatCorrect[HatIndex].Minimum[1] := AY.Minimum else AHw.HatCorrect[HatIndex].Minimum[1] := -1;
        if HatY then AHw.HatCorrect[HatIndex].Maximum[1] := AY.Maximum else AHw.HatCorrect[HatIndex].Maximum[1] := 1;
        Inc(AHw.NumHats);
      end;
      Inc(I, 2);
    end;

    // 軸
    for I := 0 to ABS_MAX - 1 do
    begin
      // デジタルのハットは飛ばす
      if (I >= ABS_HAT0X) and (I <= ABS_HAT3Y) and AHw.HasHat[(I - ABS_HAT0X) div 2] then
        Continue;
      if PMLTestBit(Abs_, I) then
      begin
        if not Node.GetAbsInfo(I, Info) then
          Continue;
        AHw.AbsMap[I] := Byte(AHw.NumAxes);
        AHw.HasAbs[I] := True;
        AHw.AbsCorrect[I].Minimum := Info.Minimum;
        AHw.AbsCorrect[I].Maximum := Info.Maximum;
        if AHw.AbsCorrect[I].Minimum <> AHw.AbsCorrect[I].Maximum then
        begin
          if UseDeadzones then
          begin
            AHw.AbsCorrect[I].UseDeadzones := True;
            AHw.AbsCorrect[I].Coef[0] := (Info.Maximum + Info.Minimum) - 2 * Info.Flat;
            AHw.AbsCorrect[I].Coef[1] := (Info.Maximum + Info.Minimum) + 2 * Info.Flat;
            T := (Info.Maximum - Info.Minimum) - 4 * Info.Flat;
            if T <> 0 then
              AHw.AbsCorrect[I].Coef[2] := (1 shl 28) div T
            else
              AHw.AbsCorrect[I].Coef[2] := 0;
          end
          else
          begin
            ValueRange := AHw.AbsCorrect[I].Maximum - AHw.AbsCorrect[I].Minimum;
            OutputRange := AXIS_MAX - AXIS_MIN;
            AHw.AbsCorrect[I].Scale := OutputRange / ValueRange;
          end;
        end;
        Inc(AHw.NumAxes);
      end;
    end;
    if PMLTestBit(Rel, REL_X) or PMLTestBit(Rel, REL_Y) then
      Inc(AHw.NumBalls);
  end;

  SetLength(AHw.Balls, AHw.NumBalls);
  SetLength(AHw.Hats, AHw.NumHats);
  for I := 0 to AHw.NumHats - 1 do
  begin
    AHw.Hats[I][0] := 1;
    AHw.Hats[I][1] := 1;
  end;

  if Node.GetBits(EV_FF, FF_MAX + 1, FF) then
  begin
    if PMLTestBit(FF, FF_RUMBLE) then
      AHw.FFRumble := True;
    if PMLTestBit(FF, FF_SINE) then
      AHw.FFSine := True;
  end;
end;

function TPMLLinuxJoystickBackend.PrepareHwData(AItem: TLinuxItem; AHw: TLinuxHwData): Boolean;
begin
  AHw.Item := AItem;
  // 読み書きで先に開く（ランブルのため）。だめなら読むだけ（イベントは取れる）
  AHw.Node := FHost.OpenNode(AItem.Path, True);
  if AHw.Node = nil then
  begin
    FLastError := 'Unable to open ' + AItem.Path;
    Exit(False);
  end;
  ConfigJoystick(AHw);
  Result := True;
end;

function TPMLLinuxJoystickBackend.Open(AJoystick: TPMLJoystick; AIndex: Integer): Boolean;
var
  Item: TLinuxItem;
  Hw: TLinuxHwData;
begin
  Item := ItemAt(AIndex);
  if Item = nil then
  begin
    FLastError := 'No such device';
    Exit(False);
  end;
  Hw := TLinuxHwData.Create;
  if not PrepareHwData(Item, Hw) then
  begin
    Hw.Free;
    Exit(False);
  end;
  Item.Hw := Hw;
  AJoystick.HwData := Hw;
  AJoystick.SetCounts(Hw.NumAxes, Hw.NumBalls, Hw.NumHats, Hw.NumButtons);
  AJoystick.Serial := FHost.ProductSerial(Item.Path);
  // 初めの更新で、今の状態を全部読む
  Hw.Fresh := True;
  if Hw.FFRumble or Hw.FFSine then
    AJoystick.AddCapability(TPMLJoystickCapability.Rumble);
  Result := True;
end;

{ ---- 入力 ---- }

function TPMLLinuxJoystickBackend.EventTimestamp(const AEvent: TPMLInputEvent): UInt64;
var
  Now_, T: UInt64;
begin
  Now_ := Core.TimestampNS;
  // カーネルの時刻はナノ秒だが、マイクロ秒にして渡される
  T := UInt64(AEvent.TimeSec) * 1000000000 + UInt64(AEvent.TimeUSec) * 1000;
  if FTimestampOffset = 0 then
    FTimestampOffset := Now_ - T;
  T := T + FTimestampOffset;
  if T > Now_ then
  begin
    FTimestampOffset := FTimestampOffset - (T - Now_);
    T := Now_;
  end;
  Result := T;
end;

function TPMLLinuxJoystickBackend.AxisCorrect(AHw: TLinuxHwData; AWhich, AValue: Integer): Integer;
var
  C: ^TAxisCorrect;
  F: Single;
begin
  Result := AValue;
  C := @AHw.AbsCorrect[AWhich];
  if C^.Minimum <> C^.Maximum then
  begin
    if C^.UseDeadzones then
    begin
      Result := Result * 2;
      if Result > C^.Coef[0] then
      begin
        if Result < C^.Coef[1] then
          Exit(0);
        Result := Result - C^.Coef[1];
      end
      else
        Result := Result - C^.Coef[0];
      Result := Result * C^.Coef[2];
      Result := SarLongint(Result, 13);
    end
    else
    begin
      // C の float と同じに、1 つずつ Single に丸める
      F := Single(AValue - C^.Minimum);
      F := F * C^.Scale;
      F := F + Single(AXIS_MIN);
      F := F + Single(0.5);
      Result := Floor(F);
    end;
  end;
  if Result < AXIS_MIN then
    Exit(AXIS_MIN);
  if Result > AXIS_MAX then
    Exit(AXIS_MAX);
end;

procedure TPMLLinuxJoystickBackend.HandleHat(ATimestamp: UInt64; AJoystick: TPMLJoystick; AHw: TLinuxHwData;
  AHatIdx, AAxis, AValue: Integer);
const
  PositionMap: array[0..2, 0..2] of Byte = (
    (PML_HAT_LEFTUP, PML_HAT_UP, PML_HAT_RIGHTUP),
    (PML_HAT_LEFT, PML_HAT_CENTERED, PML_HAT_RIGHT),
    (PML_HAT_LEFTDOWN, PML_HAT_DOWN, PML_HAT_RIGHTDOWN));
var
  HatNum: Integer;
  C: ^THatCorrect;
  V: Integer;
begin
  HatNum := AHw.HatsIndices[AHatIdx];
  C := @AHw.HatCorrect[AHatIdx];
  V := AValue;
  // 本当は軸の補正が要る機器を見分けそこねても、死帯域が軸の微かな揺れをハットの動きにしない。
  // デジタルなら、最小・0・最大しか来ないので影響しない
  if V < 0 then
  begin
    if V <= C^.Minimum[AAxis] then
    begin
      C^.Minimum[AAxis] := V;
      V := 0;
    end
    else if (not C^.UseDeadzones) or (V < C^.Minimum[AAxis] div 3) then
      V := 0
    else
      V := 1;
  end
  else if V > 0 then
  begin
    if V >= C^.Maximum[AAxis] then
    begin
      C^.Maximum[AAxis] := V;
      V := 2;
    end
    else if (not C^.UseDeadzones) or (V > C^.Maximum[AAxis] div 3) then
      V := 2
    else
      V := 1;
  end
  else
    V := 1;
  if V <> AHw.Hats[HatNum][AAxis] then
  begin
    AHw.Hats[HatNum][AAxis] := V;
    Core.SendHat(ATimestamp, AJoystick, HatNum, PositionMap[AHw.Hats[HatNum][1]][AHw.Hats[HatNum][0]]);
  end;
end;

procedure TPMLLinuxJoystickBackend.PollAllValues(ATimestamp: UInt64; AJoystick: TPMLJoystick; AHw: TLinuxHwData);
var
  I, BaseAxis, HatIdx: Integer;
  Info: TPMLInputAbsInfo;
  Keys: TPMLBits;
begin
  // 軸
  for I := ABS_X to ABS_MAX - 1 do
    if AHw.HasAbs[I] then
      if AHw.Node.GetAbsInfo(I, Info) then
        Core.SendAxis(ATimestamp, AJoystick, AHw.AbsMap[I], AxisCorrect(AHw, I, Info.Value));
  // デジタルのハット
  for I := ABS_HAT0X to ABS_HAT3Y do
  begin
    BaseAxis := I - ABS_HAT0X;
    HatIdx := BaseAxis div 2;
    if AHw.HasHat[HatIdx] then
      if AHw.Node.GetAbsInfo(I, Info) then
        HandleHat(ATimestamp, AJoystick, AHw, HatIdx, BaseAxis mod 2, Info.Value);
  end;
  // ボタン
  if AHw.Node.GetKeyState(Keys) then
    for I := 0 to KEY_MAX - 1 do
      if AHw.HasKey[I] then
        Core.SendButton(ATimestamp, AJoystick, AHw.KeyMap[I], PMLTestBit(Keys, I));
end;

procedure TPMLLinuxJoystickBackend.HandleInputEvents(AJoystick: TPMLJoystick; AHw: TLinuxHwData);
var
  Events: TPMLInputEventArray;
  Len, I, Code, HatIndex: Integer;
  E: ^TPMLInputEvent;
  Ticks: UInt64;
begin
  if AHw.Fresh then
  begin
    Ticks := Core.TimestampNS;
    PollAllValues(Ticks, AJoystick, AHw);
    AHw.Fresh := False;
  end;

  SetLength(Events, EventBatch);
  Len := AHw.Node.ReadEvents(Events);
  while Len > 0 do
  begin
    for I := 0 to Len - 1 do
    begin
      E := @Events[I];
      Code := E^.Code;
      // SYN_DROPPED のあとは、次の SYN_REPORT までを読み捨てる
      if AHw.Recovering and ((E^.EventType <> EV_SYN) or (Code <> SYN_REPORT)) then
        Continue;
      case E^.EventType of
        EV_KEY:
          if Code <= KEY_MAX then
            Core.SendButton(EventTimestamp(E^), AJoystick, AHw.KeyMap[Code], E^.Value <> 0);
        EV_ABS:
          if Code <= ABS_MAX then
          begin
            HatIndex := (Code - ABS_HAT0X) div 2;
            if (Code >= ABS_HAT0X) and (Code <= ABS_HAT3Y) and AHw.HasHat[HatIndex] then
              HandleHat(EventTimestamp(E^), AJoystick, AHw, HatIndex, Code mod 2, E^.Value)
            else
              Core.SendAxis(EventTimestamp(E^), AJoystick, AHw.AbsMap[Code], AxisCorrect(AHw, Code, E^.Value));
          end;
        EV_REL:
          if (Code = REL_X) or (Code = REL_Y) then
            if Length(AHw.Balls) > 0 then
              Inc(AHw.Balls[(Code - REL_X) div 2][(Code - REL_X) mod 2], E^.Value);
        EV_SYN:
          case Code of
            SYN_DROPPED:
              AHw.Recovering := True;
            SYN_REPORT:
              if AHw.Recovering then
              begin
                AHw.Recovering := False;
                // 今の状態に追い付く
                PollAllValues(Core.TimestampNS, AJoystick, AHw);
              end;
          end;
      end;
    end;
    Len := AHw.Node.ReadEvents(Events);
  end;
  // 外された機器は、次の Detect で一覧から外す
  if Len < 0 then
    AHw.Gone := True;
end;

procedure TPMLLinuxJoystickBackend.Update(AJoystick: TPMLJoystick);
var
  Hw: TLinuxHwData;
  I, XRel, YRel: Integer;
begin
  Hw := TLinuxHwData(AJoystick.HwData);
  if Hw = nil then
    Exit;
  HandleInputEvents(AJoystick, Hw);
  // ボールの動きを渡す
  for I := 0 to Hw.NumBalls - 1 do
  begin
    XRel := Hw.Balls[I][0];
    YRel := Hw.Balls[I][1];
    if (XRel <> 0) or (YRel <> 0) then
    begin
      Hw.Balls[I][0] := 0;
      Hw.Balls[I][1] := 0;
      Core.SendBall(0, AJoystick, I, XRel, YRel);
    end;
  end;
end;

{ ---- ランブル ---- }

function TPMLLinuxJoystickBackend.Rumble(AJoystick: TPMLJoystick; ALow, AHigh: Word): Boolean;
var
  Hw: TLinuxHwData;
begin
  Hw := TLinuxHwData(AJoystick.HwData);
  Result := False;
  if (Hw = nil) or not (Hw.FFRumble or Hw.FFSine) then
    Exit;
  if Hw.FFRumble then
  begin
    Hw.Effect.EffectType := FF_RUMBLE;
    Hw.Effect.ReplayLength := PML_MAX_RUMBLE_DURATION_MS;
    Hw.Effect.RumbleStrong := ALow;
    Hw.Effect.RumbleWeak := AHigh;
  end
  else
  begin
    // 2 つの強さを半分にして平均する
    Hw.Effect.EffectType := FF_PERIODIC;
    Hw.Effect.ReplayLength := PML_MAX_RUMBLE_DURATION_MS;
    Hw.Effect.PeriodicWaveform := FF_SINE;
    Hw.Effect.PeriodicMagnitude := SmallInt(((ALow div 2) + (AHigh div 2)) div 2);
  end;
  if not Hw.Node.UploadEffect(Hw.Effect) then
  begin
    // カーネルが効果を失っているかもしれない。新しく割り当てさせる
    Hw.Effect.ID := -1;
    if not Hw.Node.UploadEffect(Hw.Effect) then
    begin
      FLastError := 'Couldn''t set rumble effect: ' + Hw.Node.Error;
      Exit;
    end;
  end;
  if not Hw.Node.PlayEffect(Hw.Effect.ID) then
  begin
    FLastError := 'Couldn''t start rumble effect: ' + Hw.Node.Error;
    Exit;
  end;
  Result := True;
end;

{ ---- 閉じる ---- }

procedure TPMLLinuxJoystickBackend.Close(AJoystick: TPMLJoystick);
var
  Hw: TLinuxHwData;
begin
  Hw := TLinuxHwData(AJoystick.HwData);
  if Hw = nil then
    Exit;
  if (Hw.Effect.ID >= 0) and (Hw.Node <> nil) then
  begin
    Hw.Node.RemoveEffect(Hw.Effect.ID);
    Hw.Effect.ID := -1;
  end;
  if Hw.Item <> nil then
    Hw.Item.Hw := nil;
  AJoystick.HwData := nil;
  Hw.Free;
end;

{ ---- ゲームパッドの割り当て ---- }

{ Linux Gamepad Specification と Android のゲームパッドの文書に基づく割り当て。
  https://www.kernel.org/doc/html/v4.15/input/gamepad.html }
function TPMLLinuxJoystickBackend.GamepadMapping(AIndex: Integer; out AMapping: TPMLGamepadMapping): Boolean;
const
  VendorSony = $054C;
  VendorMicrosoft = $045E;
  MappedLeft = 1;
  MappedRight = 2;
  MappedBoth = 3;
var
  Item: TLinuxItem;
  Hw: TLinuxHwData;
  Mapped, Hat: Integer;

  procedure SetButton(AWhich: TPMLGamepadButton; ACode: Integer);
  begin
    AMapping.Buttons[AWhich].Kind := TPMLMappingKind.Button;
    AMapping.Buttons[AWhich].Target := Hw.KeyMap[ACode];
  end;

  procedure SetAxis(AWhich: TPMLGamepadAxis; ACode: Integer);
  begin
    AMapping.Axes[AWhich].Kind := TPMLMappingKind.Axis;
    AMapping.Axes[AWhich].Target := Hw.AbsMap[ACode];
  end;

  procedure SetHatButton(AWhich: TPMLGamepadButton; AHatIndex, AMask: Integer);
  begin
    AMapping.Buttons[AWhich].Kind := TPMLMappingKind.Hat;
    AMapping.Buttons[AWhich].Target := Byte((AHatIndex shl 4) or AMask);
  end;

  procedure SetAxisButton(AWhich: TPMLGamepadButton; ACode: Integer);
  begin
    AMapping.Buttons[AWhich].Kind := TPMLMappingKind.Axis;
    AMapping.Buttons[AWhich].Target := Hw.AbsMap[ACode];
  end;

  procedure SetHatTrigger(AWhich: TPMLGamepadAxis; AHatIndex, AMask: Integer);
  begin
    AMapping.Axes[AWhich].Kind := TPMLMappingKind.Hat;
    AMapping.Axes[AWhich].Target := Byte((AHatIndex shl 4) or AMask);
  end;

  procedure SetButtonTrigger(AWhich: TPMLGamepadAxis; ACode: Integer);
  begin
    AMapping.Axes[AWhich].Kind := TPMLMappingKind.Button;
    AMapping.Axes[AWhich].Target := Hw.KeyMap[ACode];
  end;

  procedure SetHatShoulder(AWhich: TPMLGamepadButton; AHatIndex, AMask: Integer);
  begin
    SetHatButton(AWhich, AHatIndex, AMask);
  end;

begin
  AMapping := PMLEmptyGamepadMapping;
  Result := False;
  Item := ItemAt(AIndex);
  if Item = nil then
    Exit;
  if Item.CheckedMapping then
  begin
    if Item.HasMapping then
    begin
      AMapping := Item.Mapping;
      Exit(True);
    end;
    Exit(False);
  end;

  // 機器の作りを見るために、一時的に開く
  Hw := TLinuxHwData.Create;
  try
    Item.CheckedMapping := True;
    if not PrepareHwData(Item, Hw) then
      Exit;
    // 一覧の機器にはひも付けない（グローバルな状態にしない）
    if not Hw.HasKey[BTN_GAMEPAD] then
      Exit;        // 仕様でいうゲームパッドではない

    if Hw.HasKey[BTN_A] then SetButton(TPMLGamepadButton.South, BTN_A);
    if Hw.HasKey[BTN_B] then SetButton(TPMLGamepadButton.East, BTN_B);
    // Xbox は BTN_X と BTN_Y、PS4 は BTN_WEST と BTN_NORTH
    if Item.Vendor = VendorSony then
    begin
      if Hw.HasKey[BTN_WEST] then SetButton(TPMLGamepadButton.West, BTN_WEST);
      if Hw.HasKey[BTN_NORTH] then SetButton(TPMLGamepadButton.North, BTN_NORTH);
    end
    else
    begin
      if Hw.HasKey[BTN_X] then SetButton(TPMLGamepadButton.West, BTN_X);
      if Hw.HasKey[BTN_Y] then SetButton(TPMLGamepadButton.North, BTN_Y);
    end;
    if Hw.HasKey[BTN_SELECT] then SetButton(TPMLGamepadButton.Back, BTN_SELECT);
    if Hw.HasKey[BTN_START] then SetButton(TPMLGamepadButton.Start, BTN_START);
    if Hw.HasKey[BTN_THUMBL] then SetButton(TPMLGamepadButton.LeftStick, BTN_THUMBL);
    if Hw.HasKey[BTN_THUMBR] then SetButton(TPMLGamepadButton.RightStick, BTN_THUMBR);
    if Hw.HasKey[BTN_MODE] then SetButton(TPMLGamepadButton.Guide, BTN_MODE);

    // 十字キー・肩のボタン・トリガーは、デジタルでもアナログでも、両方でもよい

    // 肩のボタンはデジタルを優先、無ければハット、無ければ軸
    Mapped := 0;
    if Hw.HasKey[BTN_TL] then
    begin
      SetButton(TPMLGamepadButton.LeftShoulder, BTN_TL);
      Mapped := Mapped or 1;
    end;
    if Hw.HasKey[BTN_TR] then
    begin
      SetButton(TPMLGamepadButton.RightShoulder, BTN_TR);
      Mapped := Mapped or 2;
    end;
    if (Mapped <> 3) and Hw.HasHat[1] then
    begin
      Hat := Hw.HatsIndices[1];
      SetHatShoulder(TPMLGamepadButton.LeftShoulder, Hat, 4);
      SetHatShoulder(TPMLGamepadButton.RightShoulder, Hat, 2);
      Mapped := 3;
    end;
    if ((Mapped and 1) = 0) and Hw.HasAbs[ABS_HAT1Y] then
    begin
      SetAxisButton(TPMLGamepadButton.LeftShoulder, ABS_HAT1Y);
      Mapped := Mapped or 1;
    end;
    if ((Mapped and 2) = 0) and Hw.HasAbs[ABS_HAT1X] then
    begin
      SetAxisButton(TPMLGamepadButton.RightShoulder, ABS_HAT1X);
      Mapped := Mapped or 2;
    end;

    // トリガーはアナログを優先、無ければデジタルのハットかボタン。軸の表し方には 3 通りある:
    //  Linux Gamepad Specification: LT = ABS_HAT2Y、RT = ABS_HAT2X
    //  Android（多くの Bluetooth）: LT = ABS_BRAKE、RT = ABS_GAS
    //  古い Xbox と PlayStation の事実上の標準: LT = ABS_Z、RT = ABS_RZ
    Mapped := 0;
    if Hw.HasAbs[ABS_HAT2Y] then
    begin
      SetAxis(TPMLGamepadAxis.LeftTrigger, ABS_HAT2Y);
      Mapped := Mapped or MappedLeft;
    end
    else if Hw.HasAbs[ABS_BRAKE] then
    begin
      SetAxis(TPMLGamepadAxis.LeftTrigger, ABS_BRAKE);
      Mapped := Mapped or MappedLeft;
    end
    else if Hw.HasAbs[ABS_Z] then
    begin
      SetAxis(TPMLGamepadAxis.LeftTrigger, ABS_Z);
      Mapped := Mapped or MappedLeft;
    end;
    if Hw.HasAbs[ABS_HAT2X] then
    begin
      SetAxis(TPMLGamepadAxis.RightTrigger, ABS_HAT2X);
      Mapped := Mapped or MappedRight;
    end
    else if Hw.HasAbs[ABS_GAS] then
    begin
      SetAxis(TPMLGamepadAxis.RightTrigger, ABS_GAS);
      Mapped := Mapped or MappedRight;
    end
    else if Hw.HasAbs[ABS_RZ] then
    begin
      SetAxis(TPMLGamepadAxis.RightTrigger, ABS_RZ);
      Mapped := Mapped or MappedRight;
    end;
    if (Mapped <> MappedBoth) and Hw.HasHat[2] then
    begin
      Hat := Hw.HatsIndices[2];
      SetHatTrigger(TPMLGamepadAxis.LeftTrigger, Hat, 4);
      SetHatTrigger(TPMLGamepadAxis.RightTrigger, Hat, 2);
      Mapped := MappedBoth;
    end;
    if ((Mapped and MappedLeft) = 0) and Hw.HasKey[BTN_TL2] then
    begin
      SetButtonTrigger(TPMLGamepadAxis.LeftTrigger, BTN_TL2);
      Mapped := Mapped or MappedLeft;
    end;
    if ((Mapped and MappedRight) = 0) and Hw.HasKey[BTN_TR2] then
    begin
      SetButtonTrigger(TPMLGamepadAxis.RightTrigger, BTN_TR2);
      Mapped := Mapped or MappedRight;
    end;

    // 十字キーはデジタルのボタンを優先、無ければハット（デジタルかアナログ）
    Mapped := 0;
    if Hw.HasKey[BTN_DPAD_UP] then
    begin
      SetButton(TPMLGamepadButton.DPadUp, BTN_DPAD_UP);
      Mapped := Mapped or 1;
    end;
    if Hw.HasKey[BTN_DPAD_DOWN] then
    begin
      SetButton(TPMLGamepadButton.DPadDown, BTN_DPAD_DOWN);
      Mapped := Mapped or 2;
    end;
    if Hw.HasKey[BTN_DPAD_LEFT] then
    begin
      SetButton(TPMLGamepadButton.DPadLeft, BTN_DPAD_LEFT);
      Mapped := Mapped or 4;
    end;
    if Hw.HasKey[BTN_DPAD_RIGHT] then
    begin
      SetButton(TPMLGamepadButton.DPadRight, BTN_DPAD_RIGHT);
      Mapped := Mapped or 8;
    end;
    if Mapped <> 15 then
    begin
      if Hw.HasHat[0] then
      begin
        Hat := Hw.HatsIndices[0];
        SetHatButton(TPMLGamepadButton.DPadLeft, Hat, 8);
        SetHatButton(TPMLGamepadButton.DPadRight, Hat, 2);
        SetHatButton(TPMLGamepadButton.DPadUp, Hat, 1);
        SetHatButton(TPMLGamepadButton.DPadDown, Hat, 4);
      end
      else if Hw.HasAbs[ABS_HAT0X] and Hw.HasAbs[ABS_HAT0Y] then
      begin
        SetAxisButton(TPMLGamepadButton.DPadLeft, ABS_HAT0X);
        SetAxisButton(TPMLGamepadButton.DPadRight, ABS_HAT0X);
        SetAxisButton(TPMLGamepadButton.DPadUp, ABS_HAT0Y);
        SetAxisButton(TPMLGamepadButton.DPadDown, ABS_HAT0Y);
      end
      else if Item.Driver = 'xpad' then
      begin
        // xpad は十字キーを BTN_TRIGGER_HAPPY1〜4 にすることがある
        if Hw.HasKey[BTN_TRIGGER_HAPPY1] and Hw.HasKey[BTN_TRIGGER_HAPPY2]
        and Hw.HasKey[BTN_TRIGGER_HAPPY3] and Hw.HasKey[BTN_TRIGGER_HAPPY4] then
        begin
          SetButton(TPMLGamepadButton.DPadLeft, BTN_TRIGGER_HAPPY1);
          SetButton(TPMLGamepadButton.DPadRight, BTN_TRIGGER_HAPPY2);
          SetButton(TPMLGamepadButton.DPadUp, BTN_TRIGGER_HAPPY3);
          SetButton(TPMLGamepadButton.DPadDown, BTN_TRIGGER_HAPPY4);
        end;
      end;
    end;

    if Hw.HasAbs[ABS_X] and Hw.HasAbs[ABS_Y] then
    begin
      SetAxis(TPMLGamepadAxis.LeftX, ABS_X);
      SetAxis(TPMLGamepadAxis.LeftY, ABS_Y);
    end;
    // 2 本目のスティックは、仕様では RX・RY（古い USB と Bluetooth）、Android では Z・RZ
    if Hw.HasAbs[ABS_RX] and Hw.HasAbs[ABS_RY] then
    begin
      SetAxis(TPMLGamepadAxis.RightX, ABS_RX);
      SetAxis(TPMLGamepadAxis.RightY, ABS_RY);
    end
    else if Hw.HasAbs[ABS_Z] and Hw.HasAbs[ABS_RZ] then
    begin
      SetAxis(TPMLGamepadAxis.RightX, ABS_Z);
      SetAxis(TPMLGamepadAxis.RightY, ABS_RZ);
    end;

    Mapped := 0;
    if Hw.HasKey[BTN_GRIPR] then
    begin
      SetButton(TPMLGamepadButton.RightPaddle1, BTN_GRIPR);
      Mapped := Mapped or 2;
    end;
    if Hw.HasKey[BTN_GRIPL] then
    begin
      SetButton(TPMLGamepadButton.LeftPaddle1, BTN_GRIPL);
      Mapped := Mapped or 1;
    end;
    if Hw.HasKey[BTN_GRIPR2] then
    begin
      SetButton(TPMLGamepadButton.RightPaddle2, BTN_GRIPR2);
      Mapped := Mapped or 8;
    end;
    if Hw.HasKey[BTN_GRIPL2] then
    begin
      SetButton(TPMLGamepadButton.LeftPaddle2, BTN_GRIPL2);
      Mapped := Mapped or 4;
    end;
    if (Mapped <> 15) and (Item.Vendor = VendorMicrosoft) then
    begin
      // 古いドライバの Xbox Elite は、パドルが BTN_TRIGGER_HAPPY5〜8
      if Hw.HasKey[BTN_TRIGGER_HAPPY5] and Hw.HasKey[BTN_TRIGGER_HAPPY6]
      and Hw.HasKey[BTN_TRIGGER_HAPPY7] and Hw.HasKey[BTN_TRIGGER_HAPPY8] then
      begin
        SetButton(TPMLGamepadButton.RightPaddle1, BTN_TRIGGER_HAPPY5);
        SetButton(TPMLGamepadButton.LeftPaddle1, BTN_TRIGGER_HAPPY7);
        SetButton(TPMLGamepadButton.RightPaddle2, BTN_TRIGGER_HAPPY6);
        SetButton(TPMLGamepadButton.LeftPaddle2, BTN_TRIGGER_HAPPY8);
      end;
    end;

    // Xbox Series の共有ボタンは KEY_RECORD
    if Hw.HasKey[KEY_RECORD] then
      SetButton(TPMLGamepadButton.Misc1, KEY_RECORD);

    Item.Mapping := AMapping;
    Item.HasMapping := True;
    Result := True;
  finally
    Hw.Free;
  end;
end;

{ ---- 登録 ---- }

function CreateLinuxBackend(ACore: TPMLJoystickCore): TPMLJoystickBackend;
begin
  Result := TPMLLinuxJoystickBackend.Create(ACore);
end;

initialization
  // 優先度は仮想より低い（SDL の並びは 仮想 が先）
  PMLRegisterJoystickBackend('linux', 0, @CreateLinuxBackend);

end.
