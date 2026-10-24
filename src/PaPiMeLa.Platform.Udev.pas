{
  PaPiMeLa.Platform.Udev — libudev による入力機器の列挙と抜き差しの監視

  Origin : ported from SDL (src/core/linux/SDL_udev.c)
           Scope: SDL_UDEV_Init / Quit / Scan / Poll、機器の種類の決め方（device_class、guess_device_class、
           get_caps）、SDL_UDEV_GetProductInfo / GetProductSerial、コールバックの並び。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §9.4、§11 #19

  WHAT:
    libudev.so.1 を dlopen で結合し（無ければ EPMLPlatformLibrary）、input / sound / video4linux の
    機器を列挙し、ネットリンクの監視で抜き差しを受け取る。機器が足されたとき（種類つき）と外れたとき、
    登録されたコールバックを呼ぶ。監視はスレッドを持たない: Poll を呼んだときに、溜まった分を処理する
    （SDL と同じ。ジョイスティックのバックエンドの Detect が呼ぶ）。

  RESOLVED:
    - SDL は SDL_UDEV_Init を数えて共有する。ここでは使う側が TPMLUdev を 1 つ持つ（共有しない）
    - udev が動いていない環境のために、機器の種類は ID_INPUT_xxx の無いときに /sys の capabilities から
      自分で決める（PMLEvdevGuessDeviceClass）。SDL と同じ

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.Udev;

{$I papimela.inc}
{$packrecords c}

interface

uses
  SysUtils, BaseUnix, Unix, ctypes,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Platform.Evdev;

const
  // SDL_udev.c が結合するライブラリ
  PML_UDEV_LIBRARIES: array[0..1] of String = ('libudev.so.1', 'libudev.so.0');

type
  TPMLUdevHandle  = Pointer;     // struct udev *
  TPMLUdevMonitor = Pointer;     // struct udev_monitor *
  TPMLUdevDevice  = Pointer;     // struct udev_device *
  TPMLUdevEnum    = Pointer;     // struct udev_enumerate *
  TPMLUdevEntry   = Pointer;     // struct udev_list_entry *

  TPMLUdevAPI = record
    udev_new: function: TPMLUdevHandle; cdecl;
    udev_unref: function(AUdev: TPMLUdevHandle): TPMLUdevHandle; cdecl;
    udev_monitor_new_from_netlink: function(AUdev: TPMLUdevHandle; AName: PChar): TPMLUdevMonitor; cdecl;
    udev_monitor_filter_add_match_subsystem_devtype: function(AMon: TPMLUdevMonitor; ASubsystem, ADevType: PChar): cint; cdecl;
    udev_monitor_enable_receiving: function(AMon: TPMLUdevMonitor): cint; cdecl;
    udev_monitor_get_fd: function(AMon: TPMLUdevMonitor): cint; cdecl;
    udev_monitor_receive_device: function(AMon: TPMLUdevMonitor): TPMLUdevDevice; cdecl;
    udev_monitor_unref: function(AMon: TPMLUdevMonitor): TPMLUdevMonitor; cdecl;
    udev_enumerate_new: function(AUdev: TPMLUdevHandle): TPMLUdevEnum; cdecl;
    udev_enumerate_add_match_subsystem: function(AEnum: TPMLUdevEnum; ASubsystem: PChar): cint; cdecl;
    udev_enumerate_scan_devices: function(AEnum: TPMLUdevEnum): cint; cdecl;
    udev_enumerate_get_list_entry: function(AEnum: TPMLUdevEnum): TPMLUdevEntry; cdecl;
    udev_enumerate_unref: function(AEnum: TPMLUdevEnum): TPMLUdevEnum; cdecl;
    udev_list_entry_get_next: function(AEntry: TPMLUdevEntry): TPMLUdevEntry; cdecl;
    udev_list_entry_get_name: function(AEntry: TPMLUdevEntry): PChar; cdecl;
    udev_device_new_from_syspath: function(AUdev: TPMLUdevHandle; ASysPath: PChar): TPMLUdevDevice; cdecl;
    udev_device_new_from_devnum: function(AUdev: TPMLUdevHandle; AType: cchar; ADevNum: culong): TPMLUdevDevice; cdecl;
    udev_device_unref: function(ADev: TPMLUdevDevice): TPMLUdevDevice; cdecl;
    udev_device_get_action: function(ADev: TPMLUdevDevice): PChar; cdecl;
    udev_device_get_devnode: function(ADev: TPMLUdevDevice): PChar; cdecl;
    udev_device_get_driver: function(ADev: TPMLUdevDevice): PChar; cdecl;
    udev_device_get_subsystem: function(ADev: TPMLUdevDevice): PChar; cdecl;
    udev_device_get_parent_with_subsystem_devtype: function(ADev: TPMLUdevDevice; ASubsystem, ADevType: PChar): TPMLUdevDevice; cdecl;
    udev_device_get_property_value: function(ADev: TPMLUdevDevice; AKey: PChar): PChar; cdecl;
    udev_device_get_sysattr_value: function(ADev: TPMLUdevDevice; AAttr: PChar): PChar; cdecl;
  end;

  // 機器の追加と削除（SDL_UDEV_deviceevent）
  TPMLUdevDeviceEvent = (Added, Removed);

  { 抜き差しの通知（SDL_UDEV_Callback）。AClass は追加のとき PML_UDEV_DEVICE_ を足したもの（削除では 0）。 }
  TPMLUdevCallback = procedure(AEvent: TPMLUdevDeviceEvent; AClass: Integer; const APath: String) of object;

  TPMLUdev = class
  strict private
    FLib      : TPMLDynLib;
    FAPI      : TPMLUdevAPI;
    FUdev     : TPMLUdevHandle;
    FMonitor  : TPMLUdevMonitor;
    FCallbacks: array of TPMLUdevCallback;
    procedure Bind(out ATarget; const ASymbol: String);
    function  DeviceFromPath(const ADevicePath: String): TPMLUdevDevice;
    function  Prop(ADev: TPMLUdevDevice; const AKey: String): String;
    function  Attr(ADev: TPMLUdevDevice; const AName: String; out AValue: String): Boolean;
    procedure GetCaps(APDev: TPMLUdevDevice; const AAttr: String; ABitCount: Integer; out ABits: TPMLBits);
    function  GuessDeviceClass(ADev: TPMLUdevDevice): Integer;
    function  DeviceClass(ADev: TPMLUdevDevice): Integer;
    procedure DeviceEvent(AEvent: TPMLUdevDeviceEvent; ADev: TPMLUdevDevice);
    function  HotplugAvailable: Boolean;
  public
    { libudev を開き、監視を始める（SDL_UDEV_Init）。開けなければ EPMLPlatformLibrary、
      udev_new などが失敗すれば EPMLPlatformLibrary。 }
    constructor Create;
    destructor Destroy; override;
    class function IsAvailable: Boolean; static;

    // 今ある機器を列挙し、コールバックを呼ぶ（SDL_UDEV_Scan）。
    procedure Scan;
    // 溜まった抜き差しを処理する（SDL_UDEV_Poll）。
    procedure Poll;
    procedure AddCallback(ACallback: TPMLUdevCallback);
    procedure DelCallback(ACallback: TPMLUdevCallback);

    { 機器ファイルのパスから、ID・種類・ドライバを引く（SDL_UDEV_GetProductInfo）。
      udev が機器を知らなければ False。AID の各欄は、udev に値があるものだけ書き換える。AClass は種類が決まったときだけ。 }
    function  GetProductInfo(const ADevicePath: String; var AID: TPMLInputID; var AClass: Integer;
      out ADriver: String): Boolean;
    // シリアル番号（ID_SERIAL_SHORT。無ければ ''）。
    function  GetProductSerial(const ADevicePath: String): String;
  end;

// "1f 00ff" のような sysfs の capabilities（16 進の語を空白で区切り、上位が先）を、ビットの集合にする（get_caps）。
function PMLUdevParseCaps(const AText: String; ABitCount: Integer): TPMLBits;

implementation

function PMLUdevParseCaps(const AText: String; ABitCount: Integer): TPMLBits;
var
  Words: array of QWord;
  Count, I, P, Start, B: Integer;
  S: String;
  V: QWord;
  Longs: Integer;
begin
  Result := nil;
  Longs := PMLBitsLength(ABitCount) div 8;
  SetLength(Result, Longs * 8);
  FillChar(Result[0], Length(Result), 0);
  S := AText;
  // 後ろの語が下位。SDL は最後の空白から切って、先頭の語まで進める
  Count := 0;
  P := Length(S);
  while P > 0 do
  begin
    Start := P;
    while (Start > 0) and (S[Start] <> ' ') do
      Dec(Start);
    // S[Start + 1 .. P] が 1 語（先頭の語のときは Start = 0）
    V := 0;
    for I := Start + 1 to P do
      case S[I] of
        '0'..'9': V := (V shl 4) or QWord(Ord(S[I]) - 48);
        'a'..'f': V := (V shl 4) or QWord(Ord(S[I]) - 87);
        'A'..'F': V := (V shl 4) or QWord(Ord(S[I]) - 55);
      else
        Break;
      end;
    SetLength(Words, Count + 1);
    Words[Count] := V;
    Inc(Count);
    P := Start - 1;
    if Start = 0 then
      Break;
  end;
  for I := 0 to Count - 1 do
    if I < Longs then
      for B := 0 to 7 do
        Result[I * 8 + B] := Byte((Words[I] shr (8 * B)) and $FF);
end;

{ TPMLUdev }

procedure TPMLUdev.Bind(out ATarget; const ASymbol: String);
begin
  Pointer(ATarget) := FLib.Resolve(ASymbol);
end;

constructor TPMLUdev.Create;
begin
  inherited Create;
  FLib := TPMLDynLib.Create(PML_UDEV_LIBRARIES);
  try
    Bind(FAPI.udev_new, 'udev_new');
    Bind(FAPI.udev_unref, 'udev_unref');
    Bind(FAPI.udev_monitor_new_from_netlink, 'udev_monitor_new_from_netlink');
    Bind(FAPI.udev_monitor_filter_add_match_subsystem_devtype, 'udev_monitor_filter_add_match_subsystem_devtype');
    Bind(FAPI.udev_monitor_enable_receiving, 'udev_monitor_enable_receiving');
    Bind(FAPI.udev_monitor_get_fd, 'udev_monitor_get_fd');
    Bind(FAPI.udev_monitor_receive_device, 'udev_monitor_receive_device');
    Bind(FAPI.udev_monitor_unref, 'udev_monitor_unref');
    Bind(FAPI.udev_enumerate_new, 'udev_enumerate_new');
    Bind(FAPI.udev_enumerate_add_match_subsystem, 'udev_enumerate_add_match_subsystem');
    Bind(FAPI.udev_enumerate_scan_devices, 'udev_enumerate_scan_devices');
    Bind(FAPI.udev_enumerate_get_list_entry, 'udev_enumerate_get_list_entry');
    Bind(FAPI.udev_enumerate_unref, 'udev_enumerate_unref');
    Bind(FAPI.udev_list_entry_get_next, 'udev_list_entry_get_next');
    Bind(FAPI.udev_list_entry_get_name, 'udev_list_entry_get_name');
    Bind(FAPI.udev_device_new_from_syspath, 'udev_device_new_from_syspath');
    Bind(FAPI.udev_device_new_from_devnum, 'udev_device_new_from_devnum');
    Bind(FAPI.udev_device_unref, 'udev_device_unref');
    Bind(FAPI.udev_device_get_action, 'udev_device_get_action');
    Bind(FAPI.udev_device_get_devnode, 'udev_device_get_devnode');
    Bind(FAPI.udev_device_get_driver, 'udev_device_get_driver');
    Bind(FAPI.udev_device_get_subsystem, 'udev_device_get_subsystem');
    Bind(FAPI.udev_device_get_parent_with_subsystem_devtype, 'udev_device_get_parent_with_subsystem_devtype');
    Bind(FAPI.udev_device_get_property_value, 'udev_device_get_property_value');
    Bind(FAPI.udev_device_get_sysattr_value, 'udev_device_get_sysattr_value');

    FUdev := FAPI.udev_new();
    if FUdev = nil then
      raise EPMLPlatformLibrary.CreateNative('udev_new() failed', 0, FLib.Name);
    FMonitor := FAPI.udev_monitor_new_from_netlink(FUdev, 'udev');
    if FMonitor = nil then
      raise EPMLPlatformLibrary.CreateNative('udev_monitor_new_from_netlink() failed', 0, FLib.Name);
    FAPI.udev_monitor_filter_add_match_subsystem_devtype(FMonitor, 'input', nil);
    FAPI.udev_monitor_filter_add_match_subsystem_devtype(FMonitor, 'sound', nil);
    FAPI.udev_monitor_filter_add_match_subsystem_devtype(FMonitor, 'video4linux', nil);
    FAPI.udev_monitor_enable_receiving(FMonitor);
  except
    if FMonitor <> nil then
      FAPI.udev_monitor_unref(FMonitor);
    if FUdev <> nil then
      FAPI.udev_unref(FUdev);
    FMonitor := nil;
    FUdev := nil;
    FreeAndNil(FLib);
    raise;
  end;
end;

destructor TPMLUdev.Destroy;
begin
  if FMonitor <> nil then
    FAPI.udev_monitor_unref(FMonitor);
  if FUdev <> nil then
    FAPI.udev_unref(FUdev);
  FreeAndNil(FLib);
  inherited Destroy;
end;

class function TPMLUdev.IsAvailable: Boolean;
begin
  Result := TPMLDynLib.IsAvailable(PML_UDEV_LIBRARIES);
end;

function TPMLUdev.Prop(ADev: TPMLUdevDevice; const AKey: String): String;
var
  P: PChar;
begin
  P := FAPI.udev_device_get_property_value(ADev, PChar(AKey));
  if P = nil then
    Result := ''
  else
    Result := P;
end;

function TPMLUdev.Attr(ADev: TPMLUdevDevice; const AName: String; out AValue: String): Boolean;
var
  P: PChar;
begin
  P := FAPI.udev_device_get_sysattr_value(ADev, PChar(AName));
  Result := P <> nil;
  if Result then
    AValue := P
  else
    AValue := '';
end;

procedure TPMLUdev.GetCaps(APDev: TPMLUdevDevice; const AAttr: String; ABitCount: Integer; out ABits: TPMLBits);
var
  Value: String;
begin
  if Attr(APDev, AAttr, Value) then
    ABits := PMLUdevParseCaps(Copy(Value, 1, 4095), ABitCount)
  else
  begin
    SetLength(ABits, PMLBitsLength(ABitCount));
    FillChar(ABits[0], Length(ABits), 0);
  end;
end;

function TPMLUdev.GuessDeviceClass(ADev: TPMLUdevDevice): Integer;
var
  PDev: TPMLUdevDevice;
  Dummy: String;
  Props, Ev, Abs_, Rel, Key: TPMLBits;
begin
  // 親をたどって、本物の入力機器（eventN の親）を探す
  PDev := ADev;
  while (PDev <> nil) and not Attr(PDev, 'capabilities/ev', Dummy) do
    PDev := FAPI.udev_device_get_parent_with_subsystem_devtype(PDev, 'input', nil);
  if PDev = nil then
    Exit(0);
  GetCaps(PDev, 'properties', INPUT_PROP_MAX + 1, Props);
  GetCaps(PDev, 'capabilities/ev', EV_MAX + 1, Ev);
  GetCaps(PDev, 'capabilities/abs', ABS_MAX + 1, Abs_);
  GetCaps(PDev, 'capabilities/rel', REL_MAX + 1, Rel);
  GetCaps(PDev, 'capabilities/key', KEY_MAX + 1, Key);
  Result := PMLEvdevGuessDeviceClass(Props, Ev, Abs_, Key, Rel);
end;

function TPMLUdev.DeviceClass(ADev: TPMLUdevDevice): Integer;
var
  Subsystem, Val, State: String;
  P: PChar;
begin
  Result := 0;
  P := FAPI.udev_device_get_subsystem(ADev);
  if P = nil then
    Exit;
  Subsystem := P;
  if Subsystem = 'sound' then
    Result := PML_UDEV_DEVICE_SOUND
  else if Subsystem = 'video4linux' then
  begin
    Val := Prop(ADev, 'ID_V4L_CAPABILITIES');
    if Val <> '' then
    begin
      if Pos('capture', LowerCase(Val)) > 0 then
        Result := PML_UDEV_DEVICE_VIDEO_CAPTURE
      else if Pos('video_output', LowerCase(Val)) > 0 then
        // v4l2loopback は、出力の能力を先に言い、ID_V4L_CAPABILITIES を更新しない
        if Attr(ADev, 'state', State) and (State = 'capture') then
          Result := PML_UDEV_DEVICE_VIDEO_CAPTURE;
    end;
  end
  else if Subsystem = 'input' then
  begin
    // udev の規則: systemd の udev-builtin-input_id.c
    if Prop(ADev, 'ID_INPUT_JOYSTICK') = '1' then
      Result := Result or PML_UDEV_DEVICE_JOYSTICK;
    if Prop(ADev, 'ID_INPUT_ACCELEROMETER') = '1' then
      Result := Result or PML_UDEV_DEVICE_ACCELEROMETER;
    if Prop(ADev, 'ID_INPUT_MOUSE') = '1' then
      Result := Result or PML_UDEV_DEVICE_MOUSE;
    if Prop(ADev, 'ID_INPUT_TOUCHSCREEN') = '1' then
      Result := Result or PML_UDEV_DEVICE_TOUCHSCREEN;
    // キーのある機器は ID_INPUT_KEY、ESC・数字・Q から D まで全部あれば ID_INPUT_KEYBOARD も
    if Prop(ADev, 'ID_INPUT_KEY') = '1' then
      Result := Result or PML_UDEV_DEVICE_HAS_KEYS;
    if Prop(ADev, 'ID_INPUT_KEYBOARD') = '1' then
      Result := Result or PML_UDEV_DEVICE_KEYBOARD;
    if Result = 0 then
    begin
      // 古い形の ID_CLASS
      Val := Prop(ADev, 'ID_CLASS');
      if Val <> '' then
      begin
        if Val = 'joystick' then
          Result := PML_UDEV_DEVICE_JOYSTICK
        else if Val = 'mouse' then
          Result := PML_UDEV_DEVICE_MOUSE
        else if Val = 'kbd' then
          Result := PML_UDEV_DEVICE_HAS_KEYS or PML_UDEV_DEVICE_KEYBOARD;
      end
      else
        // udev が動いていない環境に libudev だけ結合している場合
        Result := GuessDeviceClass(ADev);
    end;
  end;
end;

procedure TPMLUdev.DeviceEvent(AEvent: TPMLUdevDeviceEvent; ADev: TPMLUdevDevice);
var
  Node: PChar;
  DevClass, I: Integer;
  Path: String;
  Copy_: array of TPMLUdevCallback;
begin
  Node := FAPI.udev_device_get_devnode(ADev);
  if Node = nil then
    Exit;
  DevClass := 0;
  if AEvent = TPMLUdevDeviceEvent.Added then
  begin
    DevClass := DeviceClass(ADev);
    if DevClass = 0 then
      Exit;
  end;
  Path := Node;
  // コールバックの中で登録が変わっても壊れないよう、写しを回る
  SetLength(Copy_, Length(FCallbacks));
  for I := 0 to High(FCallbacks) do
    Copy_[I] := FCallbacks[I];
  for I := 0 to High(Copy_) do
    Copy_[I](AEvent, DevClass, Path);
end;

procedure TPMLUdev.Scan;
var
  En: TPMLUdevEnum;
  Item: TPMLUdevEntry;
  Dev: TPMLUdevDevice;
begin
  En := FAPI.udev_enumerate_new(FUdev);
  if En = nil then
    raise EPMLPlatformLibrary.CreateNative('udev_enumerate_new() failed', 0, FLib.Name);
  try
    FAPI.udev_enumerate_add_match_subsystem(En, 'input');
    FAPI.udev_enumerate_add_match_subsystem(En, 'sound');
    FAPI.udev_enumerate_add_match_subsystem(En, 'video4linux');
    FAPI.udev_enumerate_scan_devices(En);
    Item := FAPI.udev_enumerate_get_list_entry(En);
    while Item <> nil do
    begin
      Dev := FAPI.udev_device_new_from_syspath(FUdev, FAPI.udev_list_entry_get_name(Item));
      if Dev <> nil then
      begin
        try
          DeviceEvent(TPMLUdevDeviceEvent.Added, Dev);
        finally
          FAPI.udev_device_unref(Dev);
        end;
      end;
      Item := FAPI.udev_list_entry_get_next(Item);
    end;
  finally
    FAPI.udev_enumerate_unref(En);
  end;
end;

function TPMLUdev.HotplugAvailable: Boolean;
var
  Fds: TPollFd;
begin
  Result := False;
  if FMonitor = nil then
    Exit;
  Fds.fd := FAPI.udev_monitor_get_fd(FMonitor);
  Fds.events := POLLIN;
  Fds.revents := 0;
  Result := (fpPoll(@Fds, 1, 0) > 0) and ((Fds.revents and POLLIN) <> 0);
end;

procedure TPMLUdev.Poll;
var
  Dev: TPMLUdevDevice;
  Action: PChar;
begin
  while HotplugAvailable do
  begin
    Dev := FAPI.udev_monitor_receive_device(FMonitor);
    if Dev = nil then
      Break;
    try
      Action := FAPI.udev_device_get_action(Dev);
      if Action <> nil then
      begin
        if StrComp(Action, 'add') = 0 then
          DeviceEvent(TPMLUdevDeviceEvent.Added, Dev)
        else if StrComp(Action, 'remove') = 0 then
          DeviceEvent(TPMLUdevDeviceEvent.Removed, Dev);
      end;
    finally
      FAPI.udev_device_unref(Dev);
    end;
  end;
end;

procedure TPMLUdev.AddCallback(ACallback: TPMLUdevCallback);
begin
  SetLength(FCallbacks, Length(FCallbacks) + 1);
  FCallbacks[High(FCallbacks)] := ACallback;
end;

procedure TPMLUdev.DelCallback(ACallback: TPMLUdevCallback);
var
  I, J: Integer;
begin
  for I := 0 to High(FCallbacks) do
    if CompareByte(FCallbacks[I], ACallback, SizeOf(ACallback)) = 0 then
    begin
      for J := I to High(FCallbacks) - 1 do
        FCallbacks[J] := FCallbacks[J + 1];
      SetLength(FCallbacks, Length(FCallbacks) - 1);
      Exit;
    end;
end;

function TPMLUdev.DeviceFromPath(const ADevicePath: String): TPMLUdevDevice;
var
  St: Stat;
  T: cchar;
begin
  Result := nil;
  if fpStat(ADevicePath, St) < 0 then
    Exit;
  if fpS_ISBLK(St.st_mode) then
    T := Ord('b')
  else if fpS_ISCHR(St.st_mode) then
    T := Ord('c')
  else
    Exit;
  Result := FAPI.udev_device_new_from_devnum(FUdev, T, culong(St.st_rdev));
end;

function TPMLUdev.GetProductInfo(const ADevicePath: String; var AID: TPMLInputID; var AClass: Integer;
  out ADriver: String): Boolean;
var
  Dev: TPMLUdevDevice;
  Val: String;
  P: PChar;
  Tmp: Integer;

  function Hex16(const AText: String): Word;
  var
    I: Integer;
    V: LongWord;
  begin
    V := 0;
    for I := 1 to Length(AText) do
      case AText[I] of
        '0'..'9': V := (V shl 4) or LongWord(Ord(AText[I]) - 48);
        'a'..'f': V := (V shl 4) or LongWord(Ord(AText[I]) - 87);
        'A'..'F': V := (V shl 4) or LongWord(Ord(AText[I]) - 55);
      else
        Break;
      end;
    Result := Word(V and $FFFF);
  end;

begin
  ADriver := '';
  Dev := DeviceFromPath(ADevicePath);
  if Dev = nil then
    Exit(False);
  try
    Val := Prop(Dev, 'ID_VENDOR_ID');
    if Val <> '' then
      AID.Vendor := Hex16(Val);
    Val := Prop(Dev, 'ID_MODEL_ID');
    if Val <> '' then
      AID.Product := Hex16(Val);
    Val := Prop(Dev, 'ID_REVISION');
    if Val <> '' then
      AID.Version := Hex16(Val);
    P := FAPI.udev_device_get_driver(Dev);
    if P <> nil then
      ADriver := P
    else
      ADriver := Prop(Dev, 'ID_USB_DRIVER');
    Tmp := DeviceClass(Dev);
    if Tmp <> 0 then
      AClass := Tmp;
  finally
    FAPI.udev_device_unref(Dev);
  end;
  Result := True;
end;

function TPMLUdev.GetProductSerial(const ADevicePath: String): String;
var
  Dev: TPMLUdevDevice;
begin
  Result := '';
  Dev := DeviceFromPath(ADevicePath);
  if Dev = nil then
    Exit;
  try
    Result := Prop(Dev, 'ID_SERIAL_SHORT');
  finally
    FAPI.udev_device_unref(Dev);
  end;
end;

end.
