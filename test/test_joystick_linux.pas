{
  test_joystick_linux — Linux（evdev）のジョイスティックのバックエンド（PaPiMeLa.Joystick.Linux）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    /dev/input/event* は input グループが要り、実機のゲームパッドも CI に無い。そこで機器への触り方の抽象
    （TPMLEvdevHost・TPMLEvdevNode。PaPiMeLa.Joystick.Linux.Node）の偽物を作り、機器の能力と入力を与えて
    バックエンドの中身を通す。期待値は、SDL の SDL_sysjoystick.c の読みから手で求めたもの（SDL に同じ場面を通した
    記録は取れない。SDL の C は fd を直接使う）:
      names     機器の名前（コントローラの表、製品名の整形。SDL_CreateJoystickName との突き合わせは別の検査）
      detect    機器の見つけ方: 禁止の機器、キーボードやマウス、重複、番号の並び、3 秒ごとの見直し、
                inotify と udev の通知、外れる、ENODEV、SDL_JOYSTICK_DEVICE
      config    ボタン・軸・ハット・ボールの数と番号、デジタルのハットの見分け、軸の補正（線形と死帯域）
      events    ボタン・軸・ハット・ボール、最初の状態、SYN_DROPPED からの復帰、時刻
      rumble    ff_rumble / ff_sine、効果の作り直し、閉じるときの削除
      mapping   Linux Gamepad Specification の割り当て（Xbox 風、PlayStation 風、ハットのトリガー、xpad の十字キー）
    加えて、本物の窓口（TPMLRealEvdevHost）が /dev/input を見られるときは、機器を数えるだけの確認を行う。
}
program test_joystick_linux;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils, Classes, Math,
  PaPiMeLa.Errors,
  PaPiMeLa.Properties,
  PaPiMeLa.Events,
  PaPiMeLa.Core,
  PaPiMeLa.Joystick.GUID,
  PaPiMeLa.Joystick.Backend,
  PaPiMeLa.Joystick,
  PaPiMeLa.Gamepad.Mapping,
  PaPiMeLa.Gamepad,
  PaPiMeLa.Joystick.Names,
  PaPiMeLa.Platform.Evdev,
  PaPiMeLa.Joystick.Linux.Node,
  PaPiMeLa.Joystick.Linux;

{$I joystick_names_expected.inc}

type
  { 偽の機器 1 台。能力・軸の範囲・押されているキー・読ませるイベントを持つ。 }
  TFakeDev = class
  public
    Path       : String;
    DevNum     : QWord;
    JsIndex    : Integer;
    Name       : String;
    JsName     : String;
    ID         : TPMLInputID;
    Props, EvBits, KeyBits, AbsBits, RelBits, FFBits: TPMLBits;
    AbsInfo    : array[0..ABS_MAX] of TPMLInputAbsInfo;
    AbsFail    : array[0..ABS_MAX] of Boolean;
    KeyState   : TPMLBits;
    Queue      : TPMLInputEventArray;
    GoneFlag   : Boolean;
    DenyWrite  : Boolean;
    Log        : TStringList;
    NextEffect : Integer;
    FailUploads: Integer;
    Opens      : Integer;
    UdevVendor, UdevProduct, UdevVersion: Word;
    UdevClass  : Integer;
    UdevDriver : String;
    constructor Create(const APath: String; ADevNum: QWord);
    destructor Destroy; override;
    procedure SetKey(ACode: Integer);
    procedure SetAbs(ACode, AMin, AMax, AFuzz, AFlat, AValue: Integer);
    procedure Push(AType, ACode, AValue: Integer);
    procedure PushSecs(AType, ACode, AValue: Integer; ASec, AUSec: Int64);
  end;

  TFakeNode = class(TPMLEvdevNode)
  strict private
    FDev: TFakeDev;
    FWritable: Boolean;
    function Bits(const ASource: TPMLBits; ABitCount: Integer): TPMLBits;
  public
    constructor Create(ADev: TFakeDev; AWritable: Boolean);
    destructor Destroy; override;
    function  GetBits(AEvent, ABitCount: Integer; out ABits: TPMLBits): Boolean; override;
    function  GetProps(out ABits: TPMLBits): Boolean; override;
    function  GetID(out AID: TPMLInputID): Boolean; override;
    function  GetName(out AName: String): Boolean; override;
    function  GetJsName(out AName: String): Boolean; override;
    function  GetAbsInfo(AAxis: Integer; out AInfo: TPMLInputAbsInfo): Boolean; override;
    function  GetKeyState(out ABits: TPMLBits): Boolean; override;
    function  ReadEvents(var ABuffer: TPMLInputEventArray): Integer; override;
    function  UploadEffect(var AEffect: TPMLFFEffect): Boolean; override;
    function  RemoveEffect(AID: Integer): Boolean; override;
    function  PlayEffect(AID: Integer): Boolean; override;
    function  Gone: Boolean; override;
    function  Writable: Boolean; override;
    function  Error: String; override;
  end;

  TFakeHost = class(TPMLEvdevHost)
  public
    Devices    : TList;
    Method     : TPMLHotplugMethod;
    Callback   : TPMLHotplugCallback;
    Fired      : TStringList;      // 'A|class|path' / 'R|0|path'
    Clock      : UInt64;
    MTime      : Int64;
    InSandbox  : Boolean;
    UdevAsked  : Boolean;
    ScanCount  : Integer;
    ListCalls  : Integer;
    Extra      : TStringList;      // /dev/input にあるが機器でないもの（mouse0 など）
    constructor Create;
    destructor Destroy; override;
    function  Add(ADev: TFakeDev): TFakeDev;
    function  Find(const APath: String): TFakeDev;
    procedure Fire(AAdded: Boolean; AClass: Integer; const APath: String);
    function  OpenNode(const APath: String; AWritable: Boolean): TPMLEvdevNode; override;
    function  DeviceNumber(const APath: String; out ADevNum: QWord): Boolean; override;
    function  ListInputDirectory: TStringArray; override;
    function  InputDirectoryMTime(out AMTime: Int64): Boolean; override;
    function  JsIndexForEvent(AEvent: Integer): Integer; override;
    function  StartHotplug(AUseUdev: Boolean; ACallback: TPMLHotplugCallback): TPMLHotplugMethod; override;
    procedure ScanHotplug; override;
    procedure PollHotplug; override;
    procedure StopHotplug; override;
    function  ProductInfo(const APath: String; var AID: TPMLInputID; var AClass: Integer;
      out ADriver: String): Boolean; override;
    function  ProductSerial(const APath: String): String; override;
    function  Sandboxed: Boolean; override;
    function  TicksMS: UInt64; override;
  end;

var
  Failures: Integer = 0;
  Host: TFakeHost;
  Ctx: TPMLContext;

procedure Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
    WriteLn('  [PASS] ', ALabel)
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(Failures);
  end;
end;

{ ---- 偽物 ---- }

procedure SetBit(var ABits: TPMLBits; ABit: Integer);
begin
  if (ABit shr 3) >= Length(ABits) then
    SetLength(ABits, ((ABit shr 3) div 8 + 1) * 8);
  ABits[ABit shr 3] := ABits[ABit shr 3] or (1 shl (ABit and 7));
end;

constructor TFakeDev.Create(const APath: String; ADevNum: QWord);
begin
  inherited Create;
  Path := APath;
  DevNum := ADevNum;
  JsIndex := -1;
  Log := TStringList.Create;
  SetLength(Props, 8);
  SetLength(EvBits, 8);
  SetLength(KeyBits, 96);
  SetLength(AbsBits, 8);
  SetLength(RelBits, 8);
  SetLength(FFBits, 16);
  SetLength(KeyState, 96);
  UdevClass := PML_UDEV_DEVICE_JOYSTICK;
  NextEffect := 0;
end;

destructor TFakeDev.Destroy;
begin
  Log.Free;
  inherited Destroy;
end;

procedure TFakeDev.SetKey(ACode: Integer);
begin
  SetBit(KeyBits, ACode);
  SetBit(EvBits, EV_KEY);
end;

procedure TFakeDev.SetAbs(ACode, AMin, AMax, AFuzz, AFlat, AValue: Integer);
begin
  SetBit(AbsBits, ACode);
  SetBit(EvBits, EV_ABS);
  AbsInfo[ACode].Minimum := AMin;
  AbsInfo[ACode].Maximum := AMax;
  AbsInfo[ACode].Fuzz := AFuzz;
  AbsInfo[ACode].Flat := AFlat;
  AbsInfo[ACode].Value := AValue;
end;

procedure TFakeDev.Push(AType, ACode, AValue: Integer);
begin
  PushSecs(AType, ACode, AValue, 0, 0);
end;

procedure TFakeDev.PushSecs(AType, ACode, AValue: Integer; ASec, AUSec: Int64);
var
  E: TPMLInputEvent;
begin
  FillChar(E, SizeOf(E), 0);
  E.TimeSec := ASec;
  E.TimeUSec := AUSec;
  E.EventType := AType;
  E.Code := ACode;
  E.Value := AValue;
  SetLength(Queue, Length(Queue) + 1);
  Queue[High(Queue)] := E;
end;

constructor TFakeNode.Create(ADev: TFakeDev; AWritable: Boolean);
begin
  inherited Create;
  FDev := ADev;
  FWritable := AWritable;
  Inc(ADev.Opens);
end;

destructor TFakeNode.Destroy;
begin
  Dec(FDev.Opens);
  inherited Destroy;
end;

function TFakeNode.Bits(const ASource: TPMLBits; ABitCount: Integer): TPMLBits;
var
  Size: Integer;
begin
  Size := PMLBitsLength(ABitCount);
  SetLength(Result, Size);
  FillChar(Result[0], Size, 0);
  Move(ASource[0], Result[0], Min(Size, Length(ASource)));
end;

function TFakeNode.GetBits(AEvent, ABitCount: Integer; out ABits: TPMLBits): Boolean;
begin
  Result := True;
  case AEvent of
    0: ABits := Bits(FDev.EvBits, ABitCount);
    EV_KEY: ABits := Bits(FDev.KeyBits, ABitCount);
    EV_ABS: ABits := Bits(FDev.AbsBits, ABitCount);
    EV_REL: ABits := Bits(FDev.RelBits, ABitCount);
    EV_FF: ABits := Bits(FDev.FFBits, ABitCount);
  else
    Result := False;
  end;
end;

function TFakeNode.GetProps(out ABits: TPMLBits): Boolean;
begin
  ABits := Bits(FDev.Props, INPUT_PROP_MAX + 1);
  Result := True;
end;

function TFakeNode.GetID(out AID: TPMLInputID): Boolean;
begin
  AID := FDev.ID;
  Result := True;
end;

function TFakeNode.GetName(out AName: String): Boolean;
begin
  AName := FDev.Name;
  Result := True;
end;

function TFakeNode.GetJsName(out AName: String): Boolean;
begin
  AName := FDev.JsName;
  Result := FDev.JsName <> '';
end;

function TFakeNode.GetAbsInfo(AAxis: Integer; out AInfo: TPMLInputAbsInfo): Boolean;
begin
  Result := (AAxis >= 0) and (AAxis <= ABS_MAX) and not FDev.AbsFail[AAxis];
  if Result then
    AInfo := FDev.AbsInfo[AAxis]
  else
    FillChar(AInfo, SizeOf(AInfo), 0);
end;

function TFakeNode.GetKeyState(out ABits: TPMLBits): Boolean;
begin
  ABits := Bits(FDev.KeyState, KEY_MAX + 1);
  Result := True;
end;

function TFakeNode.ReadEvents(var ABuffer: TPMLInputEventArray): Integer;
var
  N, I: Integer;
begin
  if FDev.GoneFlag and (Length(FDev.Queue) = 0) then
    Exit(-1);
  N := Min(Length(ABuffer), Length(FDev.Queue));
  for I := 0 to N - 1 do
    ABuffer[I] := FDev.Queue[I];
  for I := N to High(FDev.Queue) do
    FDev.Queue[I - N] := FDev.Queue[I];
  SetLength(FDev.Queue, Length(FDev.Queue) - N);
  Result := N;
end;

function TFakeNode.UploadEffect(var AEffect: TPMLFFEffect): Boolean;
begin
  if FDev.FailUploads > 0 then
  begin
    Dec(FDev.FailUploads);
    FDev.Log.Add('upload failed id=' + IntToStr(AEffect.ID));
    Exit(False);
  end;
  if AEffect.ID < 0 then
  begin
    AEffect.ID := FDev.NextEffect;
    Inc(FDev.NextEffect);
  end;
  if AEffect.EffectType = FF_RUMBLE then
    FDev.Log.Add(Format('upload rumble id=%d len=%d strong=%d weak=%d',
      [AEffect.ID, AEffect.ReplayLength, AEffect.RumbleStrong, AEffect.RumbleWeak]))
  else
    FDev.Log.Add(Format('upload periodic id=%d len=%d wave=%d mag=%d',
      [AEffect.ID, AEffect.ReplayLength, AEffect.PeriodicWaveform, AEffect.PeriodicMagnitude]));
  Result := True;
end;

function TFakeNode.RemoveEffect(AID: Integer): Boolean;
begin
  FDev.Log.Add('remove id=' + IntToStr(AID));
  Result := True;
end;

function TFakeNode.PlayEffect(AID: Integer): Boolean;
begin
  FDev.Log.Add('play id=' + IntToStr(AID));
  Result := True;
end;

function TFakeNode.Gone: Boolean;
begin
  Result := FDev.GoneFlag;
end;

function TFakeNode.Writable: Boolean;
begin
  Result := FWritable;
end;

function TFakeNode.Error: String;
begin
  Result := 'fake error';
end;

constructor TFakeHost.Create;
begin
  inherited Create;
  Devices := TList.Create;
  Fired := TStringList.Create;
  Extra := TStringList.Create;
  Method := TPMLHotplugMethod.None;
  Clock := 10000;
  MTime := 1;
end;

destructor TFakeHost.Destroy;
var
  I: Integer;
begin
  for I := 0 to Devices.Count - 1 do
    TObject(Devices[I]).Free;
  Devices.Free;
  Fired.Free;
  Extra.Free;
  inherited Destroy;
end;

function TFakeHost.Add(ADev: TFakeDev): TFakeDev;
begin
  Devices.Add(ADev);
  Inc(MTime);
  Result := ADev;
end;

function TFakeHost.Find(const APath: String): TFakeDev;
var
  I: Integer;
begin
  for I := 0 to Devices.Count - 1 do
    if TFakeDev(Devices[I]).Path = APath then
      Exit(TFakeDev(Devices[I]));
  Result := nil;
end;

procedure TFakeHost.Fire(AAdded: Boolean; AClass: Integer; const APath: String);
begin
  if AAdded then
    Fired.Add(Format('A|%d|%s', [AClass, APath]))
  else
    Fired.Add(Format('R|%d|%s', [AClass, APath]));
end;

function TFakeHost.OpenNode(const APath: String; AWritable: Boolean): TPMLEvdevNode;
var
  D: TFakeDev;
begin
  D := Find(APath);
  if D = nil then
    Exit(nil);
  Result := TFakeNode.Create(D, AWritable and not D.DenyWrite);
end;

function TFakeHost.DeviceNumber(const APath: String; out ADevNum: QWord): Boolean;
var
  D: TFakeDev;
begin
  D := Find(APath);
  Result := D <> nil;
  if Result then
    ADevNum := D.DevNum
  else
    ADevNum := 0;
end;

function TFakeHost.ListInputDirectory: TStringArray;
var
  I, N: Integer;
begin
  Inc(ListCalls);
  Result := nil;
  N := 0;
  for I := 0 to Devices.Count - 1 do
  begin
    SetLength(Result, N + 1);
    Result[N] := ExtractFileName(TFakeDev(Devices[I]).Path);
    Inc(N);
  end;
  for I := 0 to Extra.Count - 1 do
  begin
    SetLength(Result, N + 1);
    Result[N] := Extra[I];
    Inc(N);
  end;
end;

function TFakeHost.InputDirectoryMTime(out AMTime: Int64): Boolean;
begin
  AMTime := MTime;
  Result := True;
end;

function TFakeHost.JsIndexForEvent(AEvent: Integer): Integer;
var
  D: TFakeDev;
begin
  D := Find('/dev/input/event' + IntToStr(AEvent));
  if D = nil then
    Result := -1
  else
    Result := D.JsIndex;
end;

function TFakeHost.StartHotplug(AUseUdev: Boolean; ACallback: TPMLHotplugCallback): TPMLHotplugMethod;
begin
  UdevAsked := AUseUdev;
  Callback := ACallback;
  Result := Method;
  if (Method = TPMLHotplugMethod.Udev) and not AUseUdev then
    Result := TPMLHotplugMethod.Inotify;
  Method := Result;
end;

procedure TFakeHost.ScanHotplug;
var
  I: Integer;
  D: TFakeDev;
begin
  Inc(ScanCount);
  for I := 0 to Devices.Count - 1 do
  begin
    D := TFakeDev(Devices[I]);
    Callback(TPMLHotplugKind.Added, D.UdevClass, D.Path);
  end;
end;

procedure TFakeHost.PollHotplug;
var
  I: Integer;
  Parts: TStringList;
  Items: TStringList;
begin
  Items := TStringList.Create;
  Parts := TStringList.Create;
  try
    Items.Assign(Fired);
    Fired.Clear;
    Parts.Delimiter := '|';
    Parts.StrictDelimiter := True;
    for I := 0 to Items.Count - 1 do
    begin
      Parts.DelimitedText := Items[I];
      if Parts[0] = 'A' then
        Callback(TPMLHotplugKind.Added, StrToInt(Parts[1]), Parts[2])
      else
        Callback(TPMLHotplugKind.Removed, StrToInt(Parts[1]), Parts[2]);
    end;
  finally
    Parts.Free;
    Items.Free;
  end;
end;

procedure TFakeHost.StopHotplug;
begin
end;

function TFakeHost.ProductInfo(const APath: String; var AID: TPMLInputID; var AClass: Integer;
  out ADriver: String): Boolean;
var
  D: TFakeDev;
begin
  ADriver := '';
  D := Find(APath);
  if (Method <> TPMLHotplugMethod.Udev) or (D = nil) then
    Exit(False);
  AID.Vendor := D.UdevVendor;
  AID.Product := D.UdevProduct;
  AID.Version := D.UdevVersion;
  AClass := D.UdevClass;
  ADriver := D.UdevDriver;
  Result := True;
end;

function TFakeHost.ProductSerial(const APath: String): String;
begin
  Result := '';
end;

function TFakeHost.Sandboxed: Boolean;
begin
  Result := InSandbox;
end;

function TFakeHost.TicksMS: UInt64;
begin
  Result := Clock;
end;

{ ---- 場面の部品 ---- }

function MakeHost: TFakeHost;
begin
  Host := TFakeHost.Create;
  Result := Host;
end;

function FactoryFunc: TPMLEvdevHost;
begin
  Result := Host;
end;

procedure OpenContext(const AExtraHints: array of String);
var
  Opts: TPMLContextOptions;
  I: Integer;
begin
  PMLLinuxJoystickHostFactory := @FactoryFunc;
  Opts := TPMLContextOptions.Default;
  Opts.Hints.Add(PML_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, '1');
  I := 0;
  while I + 1 <= High(AExtraHints) do
  begin
    Opts.Hints.Add(AExtraHints[I], AExtraHints[I + 1]);
    Inc(I, 2);
  end;
  Ctx := TPMLContext.Create([TPMLSubsystem.Gamepad], Opts);
end;

procedure CloseContext;
begin
  FreeAndNil(Ctx);          // バックエンドが窓口を壊す
  Host := nil;
  PMLLinuxJoystickHostFactory := nil;
end;

procedure Pump;
begin
  Ctx.Joysticks.Update;
end;

function DrainText: String;
var
  E: TPMLEvent;
begin
  Result := '';
  while Ctx.Events.Poll(E) do
    case E.Kind of
      TPMLEventKind.JoystickAdded: Result := Result + 'jadded;';
      TPMLEventKind.JoystickRemoved: Result := Result + 'jremoved;';
      TPMLEventKind.JoystickAxisMotion: Result := Result + Format('axis%d=%d;', [E.JAxis.Axis, E.JAxis.Value]);
      TPMLEventKind.JoystickHatMotion: Result := Result + Format('hat%d=%d;', [E.JHat.Hat, E.JHat.Value]);
      TPMLEventKind.JoystickButtonDown: Result := Result + Format('down%d;', [E.JButton.Button]);
      TPMLEventKind.JoystickButtonUp: Result := Result + Format('up%d;', [E.JButton.Button]);
      TPMLEventKind.JoystickBallMotion: Result := Result + Format('ball%d=%d,%d;', [E.JBall.Ball, E.JBall.XRel, E.JBall.YRel]);
      TPMLEventKind.JoystickUpdateComplete, TPMLEventKind.GamepadUpdateComplete: ;
      TPMLEventKind.GamepadAdded: Result := Result + 'gadded;';
      TPMLEventKind.GamepadRemoved: Result := Result + 'gremoved;';
    end;
end;

{ Xbox 360 風のパッド: ボタン 15、軸 6（X・Y・Z・RX・RY・RZ）、十字キーはハット、ランブル }
function XboxLike(const APath: String; ADevNum: QWord; AVendor, AProduct, AVersion: Word;
  const AName: String): TFakeDev;
var
  D: TFakeDev;
begin
  D := TFakeDev.Create(APath, ADevNum);
  D.Name := AName;
  D.ID.BusType := 3;
  D.ID.Vendor := AVendor;
  D.ID.Product := AProduct;
  D.ID.Version := AVersion;
  D.SetKey(BTN_A); D.SetKey(BTN_B); D.SetKey(BTN_X); D.SetKey(BTN_Y);
  D.SetKey(BTN_TL); D.SetKey(BTN_TR); D.SetKey(BTN_SELECT); D.SetKey(BTN_START);
  D.SetKey(BTN_MODE); D.SetKey(BTN_THUMBL); D.SetKey(BTN_THUMBR);
  D.SetAbs(ABS_X, -32768, 32767, 16, 128, 0);
  D.SetAbs(ABS_Y, -32768, 32767, 16, 128, 0);
  D.SetAbs(ABS_Z, 0, 255, 0, 0, 0);
  D.SetAbs(ABS_RX, -32768, 32767, 16, 128, 0);
  D.SetAbs(ABS_RY, -32768, 32767, 16, 128, 0);
  D.SetAbs(ABS_RZ, 0, 255, 0, 0, 0);
  D.SetAbs(ABS_HAT0X, -1, 1, 0, 0, 0);
  D.SetAbs(ABS_HAT0Y, -1, 1, 0, 0, 0);
  SetBit(D.EvBits, EV_FF);
  SetBit(D.FFBits, FF_RUMBLE);
  Result := D;
end;

function OnlyDevice: TPMLJoystickID;
var
  IDs: TPMLJoystickIDs;
begin
  IDs := Ctx.Joysticks.Joysticks;
  Result := 0;
  if Length(IDs) > 0 then
    Result := IDs[0];
end;

{ ---- 場面 ---- }

procedure TestDetect;
var
  H: TFakeHost;
  D: TFakeDev;
  IDs: TPMLJoystickIDs;
  S: String;
  Kb, Mouse, Sensor: TFakeDev;
  I: Integer;
begin
  WriteLn('機器の見つけ方（一覧の見直し）');
  H := MakeHost;
  // event10 が先に見つかるが、並びは番号の順（js の番号があるものが先）
  H.Add(XboxLike('/dev/input/event10', 110, $1234, $0001, 1, 'Pad Ten'));
  H.Add(XboxLike('/dev/input/event2', 102, $1234, $0002, 1, 'Pad Two'));
  D := H.Add(XboxLike('/dev/input/event7', 107, $1234, $0003, 1, 'Pad Seven'));
  D.JsIndex := 0;
  D := H.Add(XboxLike('/dev/input/event5', 105, $1234, $0004, 1, 'Pad Five'));
  D.JsIndex := 1;
  // キーボードとマウスは機器ではない
  Kb := TFakeDev.Create('/dev/input/event3', 103);
  Kb.Name := 'Plain Keyboard';
  Kb.ID.Vendor := $0abc; Kb.ID.Product := $0001;
  for I := 1 to 31 do
    Kb.SetKey(I);
  H.Add(Kb);
  Mouse := TFakeDev.Create('/dev/input/event4', 104);
  Mouse.Name := 'Plain Mouse';
  Mouse.ID.Vendor := $0abc; Mouse.ID.Product := $0002;
  Mouse.SetKey(BTN_MOUSE);
  SetBit(Mouse.EvBits, EV_REL);
  SetBit(Mouse.RelBits, REL_X);
  SetBit(Mouse.RelBits, REL_Y);
  H.Add(Mouse);
  H.Extra.Add('mouse0');
  H.Extra.Add('js0');
  H.Extra.Add('by-id');
  Sensor := TFakeDev.Create('/dev/input/event6', 106);
  Sensor.Name := 'Pad Motion Sensors';
  Sensor.ID.Vendor := $1234; Sensor.ID.Product := $0005;
  Sensor.SetAbs(ABS_X, -100, 100, 0, 0, 0);
  Sensor.SetAbs(ABS_Y, -100, 100, 0, 0, 0);
  Sensor.SetAbs(ABS_Z, -100, 100, 0, 0, 0);
  H.Add(Sensor);
  OpenContext([]);
  try
    IDs := Ctx.Joysticks.Joysticks;
    Check(Length(IDs) = 4, '機器は 4 台（キーボード・マウス・加速度計は入らない）');
    S := '';
    if Length(IDs) = 4 then
      S := Ctx.Joysticks.NameForID(IDs[0]) + ',' + Ctx.Joysticks.NameForID(IDs[1]) + ',' +
        Ctx.Joysticks.NameForID(IDs[2]) + ',' + Ctx.Joysticks.NameForID(IDs[3]);
    Check(S = 'Pad Seven,Pad Five,Pad Two,Pad Ten', 'js の番号があるものが先、他は event の番号の順: ' + S);
    Check(Ctx.Joysticks.PathForID(IDs[0]) = '/dev/input/event7', 'パスは /dev/input/event7');
    Check(Host.Find('/dev/input/event3').Opens = 0, '開いた機器は閉じてある（キーボード）');
    Check(Host.Find('/dev/input/event7').Opens = 0, '開いた機器は閉じてある');
    Check(Host.Method = TPMLHotplugMethod.None, '見つける方法は一覧の見直し');
    // 3 秒より前は見直さない。ディレクトリが変わらなければ 3 秒たっても見直さない
    H.ListCalls := 0;
    Pump;
    Pump;
    Check(H.ListCalls = 0, '3 秒たつまで一覧は見ない');
    H.Clock := H.Clock + 3500;
    Pump;
    Check(H.ListCalls = 0, 'ディレクトリの更新時刻が同じなら見ない');
    // 新しい機器が足される
    H.Add(XboxLike('/dev/input/event11', 111, $1234, $0006, 1, 'Pad Eleven'));
    H.Clock := H.Clock + 2000;
    Pump;
    Check(Length(Ctx.Joysticks.Joysticks) = 4, '3 秒たたないうちは新しい機器に気づかない');
    H.Clock := H.Clock + 1500;
    Pump;
    Check(Length(Ctx.Joysticks.Joysticks) = 5, '3 秒たって見直すと足される');
    S := DrainText;
    Check(S = 'jadded;jadded;jadded;jadded;gadded;gadded;gadded;gadded;jadded;gadded;',
      '足されたら JoystickAdded のあと GamepadAdded: ' + S);
  finally
    CloseContext;
  end;
end;

function OpenPad(AIndex: Integer = 0): TPMLJoystick;
var
  IDs: TPMLJoystickIDs;
begin
  IDs := Ctx.Joysticks.Joysticks;
  Result := Ctx.Joysticks.Open(IDs[AIndex]);
end;

procedure TestFilters;
var
  H: TFakeHost;
  D: TFakeDev;
  IDs: TPMLJoystickIDs;
  Name_: String;
begin
  WriteLn('機器の判定（名前・禁止・重複・指定）');
  H := MakeHost;
  D := H.Add(XboxLike('/dev/input/event0', 100, $045E, $028E, $0114, 'Microsoft X-Box 360 pad'));
  H.Add(XboxLike('/dev/input/event1', 101, $1234, $5678, 7, 'Plain Pad'));
  // 同じ機器番号（別の経路）は 1 台だけ
  H.Add(XboxLike('/dev/input/event2', 101, $1234, $5678, 7, 'Plain Pad Alias'));
  // 名前に禁止の語（ゲームパッドの禁止: 名前の中ほどの " Keyboard"）
  H.Add(XboxLike('/dev/input/event3', 103, $1234, $5679, 1, 'Fake Keyboard Pad'));
  // ヒントで無視する VID/PID
  H.Add(XboxLike('/dev/input/event4', 104, $1234, $9999, 1, 'Ignored By Id'));
  // Steam の仮想ゲームパッド
  H.Add(XboxLike('/dev/input/event5', 105, $28DE, $11FF, 1, 'Steam Virtual Gamepad'));
  OpenContext([PML_HINT_GAMEPAD_IGNORE_DEVICES, '0x1234/0x9999']);
  try
    IDs := Ctx.Joysticks.Joysticks;
    Check(Length(IDs) = 2, '禁止・無視・重複を除いて 2 台');
    if Length(IDs) = 2 then
    begin
      Name_ := Ctx.Joysticks.NameForID(IDs[0]);
      Check(Name_ = PMLCreateJoystickName($045E, $028E, '', 'Microsoft X-Box 360 pad', nil),
        '名前はコントローラの表または整形した製品名: ' + Name_);
      Check(Ctx.Joysticks.NameForID(IDs[1]) = 'Plain Pad', '表に無い機器の名前は製品名');
      Check(PMLSameGUID(Ctx.Joysticks.GUIDForID(IDs[1]),
        PMLCreateJoystickGUID(3, $1234, $5678, 7, '', 'Plain Pad', 0, 0)), 'GUID はバス・ベンダー・プロダクト・版・名前の CRC');
      Check(Ctx.Joysticks.VendorForID(IDs[0]) = $045E, 'ベンダー');
      Check(Ctx.Joysticks.ProductVersionForID(IDs[1]) = 7, '版');
      Check(Ctx.Gamepads.IsGamepad(IDs[1]), 'Linux Gamepad Specification のゲームパッドは IsGamepad');
    end;
  finally
    CloseContext;
  end;

  // 指定した機器（SDL_JOYSTICK_DEVICE）は、一覧の前に足される
  H := MakeHost;
  H.Add(XboxLike('/dev/input/event0', 100, $1234, $0001, 1, 'Pad A'));
  H.Add(XboxLike('/dev/input/event1', 101, $1234, $0002, 1, 'Pad B'));
  H.Add(XboxLike('/dev/input/event9', 109, $1234, $0003, 1, 'Pad C'));
  OpenContext([PML_HINT_JOYSTICK_DEVICE, '/dev/input/event9:/dev/input/missing:/dev/input/event1']);
  try
    IDs := Ctx.Joysticks.Joysticks;
    Check((Length(IDs) = 3) and (Ctx.Joysticks.NameForID(IDs[0]) = 'Pad C') and (Ctx.Joysticks.NameForID(IDs[1]) = 'Pad B')
      and (Ctx.Joysticks.NameForID(IDs[2]) = 'Pad A'), '指定した機器が先（無い機器は飛ばす）、残りは一覧');
  finally
    CloseContext;
  end;
end;

procedure TestHotplug;
var
  H: TFakeHost;
  D: TFakeDev;
  S: String;
begin
  WriteLn('抜き差しの通知（inotify・udev）');
  // inotify
  H := MakeHost;
  H.Method := TPMLHotplugMethod.Inotify;
  H.Add(XboxLike('/dev/input/event0', 100, $1234, $0001, 1, 'Pad A'));
  OpenContext([]);
  try
    S := DrainText;
    Check(Length(Ctx.Joysticks.Joysticks) = 1, 'はじめに一覧から 1 台');
    Check(Host.UdevAsked, 'udev を先に試す');
    Check(Host.ScanCount = 0, 'inotify では udev の Scan はしない');
    D := Host.Add(XboxLike('/dev/input/event9', 109, $1234, $0002, 1, 'Pad B'));
    Host.Fire(True, -1, '/dev/input/event9');
    Host.Fire(True, -1, '/dev/input/mouse0');
    Host.Fire(True, -1, '/dev/input/js0');
    Pump;
    Check(Length(Ctx.Joysticks.Joysticks) = 2, 'event の通知で足される（mouse と js は無視）');
    Host.Fire(False, -1, '/dev/input/event9');
    Pump;
    Check(Length(Ctx.Joysticks.Joysticks) = 1, '消える通知で外れる');
    S := DrainText;
    Check(S = 'jadded;gadded;gremoved;jremoved;', '足す→外すのイベント: ' + S);
    // 属性が変わって読めるようになった（同じ通知）。もう持っている機器は足さない
    Host.Fire(True, -1, '/dev/input/event0');
    Pump;
    Check(Length(Ctx.Joysticks.Joysticks) = 1, '持っている機器の通知は無視');
    Check(D.Opens = 0, '開いたものは閉じてある');
  finally
    CloseContext;
  end;

  // udev
  H := MakeHost;
  H.Method := TPMLHotplugMethod.Udev;
  D := H.Add(XboxLike('/dev/input/event0', 100, $1234, $0001, 1, 'Pad A'));
  D.UdevVendor := $1234; D.UdevProduct := $0001; D.UdevVersion := 1; D.UdevDriver := 'xpad';
  OpenContext([]);
  try
    S := DrainText;
    Check(Host.ScanCount = 1, 'udev では、はじめに Scan');
    Check(Length(Ctx.Joysticks.Joysticks) = 1, '一覧と Scan が同じ機器を重ねない');
    D := Host.Add(XboxLike('/dev/input/event8', 108, $1234, $0002, 1, 'Pad B'));
    Host.Fire(True, PML_UDEV_DEVICE_KEYBOARD, '/dev/input/event8');
    Pump;
    Check(Length(Ctx.Joysticks.Joysticks) = 1, '種類がジョイスティックでない通知は無視');
    Host.Add(XboxLike('/dev/input/js1', 191, $1234, $0003, 1, 'Pad On Js'));
    Host.Fire(True, PML_UDEV_DEVICE_JOYSTICK, '/dev/input/js1');
    Pump;
    Check(Length(Ctx.Joysticks.Joysticks) = 1, 'js の機器ファイルは無視');
    D.UdevVendor := $1234; D.UdevProduct := $0002; D.UdevVersion := 1; D.UdevClass := PML_UDEV_DEVICE_KEYBOARD;
    Host.Fire(True, PML_UDEV_DEVICE_JOYSTICK, '/dev/input/event8');
    Pump;
    Check(Length(Ctx.Joysticks.Joysticks) = 1, 'udev が先にキーボードと答える機器は開かずに断る');
    D.UdevClass := PML_UDEV_DEVICE_JOYSTICK;
    Host.Fire(True, PML_UDEV_DEVICE_JOYSTICK, '/dev/input/event8');
    Pump;
    Check(Length(Ctx.Joysticks.Joysticks) = 2, 'ジョイスティックの種類の通知で足される');
    Host.Fire(False, 0, '/dev/input/event8');
    Pump;
    Check(Length(Ctx.Joysticks.Joysticks) = 1, '外れる通知');
  finally
    CloseContext;
  end;

  // コンテナの中では udev を使わない
  H := MakeHost;
  H.Method := TPMLHotplugMethod.Udev;
  H.InSandbox := True;
  OpenContext([]);
  try
    Check(not Host.UdevAsked, 'コンテナの中では udev を試さない');
    Check(Host.Method = TPMLHotplugMethod.Inotify, 'inotify になる');
  finally
    CloseContext;
  end;
  H := MakeHost;
  H.Method := TPMLHotplugMethod.Udev;
  OpenContext([PML_HINT_JOYSTICK_DISABLE_UDEV, '1']);
  try
    Check(not Host.UdevAsked, 'ヒントで udev を切る');
  finally
    CloseContext;
  end;
end;

procedure TestConfig;
var
  H: TFakeHost;
  D: TFakeDev;
  J: TPMLJoystick;
begin
  WriteLn('割り当てと軸の補正');
  H := MakeHost;
  D := H.Add(XboxLike('/dev/input/event0', 100, $1234, $5678, 1, 'Xbox Pad X'));
  // 範囲の違う軸、ボールのある機器
  D.SetAbs(ABS_X, -32768, 32767, 16, 128, 100);
  SetBit(D.EvBits, EV_REL);
  SetBit(D.RelBits, REL_X);
  OpenContext([]);
  try
    J := OpenPad;
    Check(J.NumButtons = 11, 'ボタンは 11 個');
    Check(J.NumAxes = 6, '軸は 6 本（十字キーはハット）');
    Check(J.NumHats = 1, 'ハットは 1 つ');
    Check(J.NumBalls = 1, 'REL_X があればボールは 1 つ');
    Pump;
    D.Push(EV_ABS, ABS_Z, 255);
    D.Push(EV_ABS, ABS_Z, 128);
    Pump;
    Check(J.Axes[0] = 100, '最初の状態: 軸 0 は機器の値 100（線形で同じ値）');
    Check(J.Axes[2] = 128, 'Z（0..255）の 128 は 128: 線形に伸ばして -32768..32767');
    D.Push(EV_ABS, ABS_Z, 1);
    Pump;
    Check(J.Axes[2] = -32511, 'Z の 1 は -32511（float の丸め: floor(257 - 32768 + 0.5)）');
    D.Push(EV_ABS, ABS_Z, 255);
    Pump;
    Check(J.Axes[2] = 32767, 'Z の最大は 32767');
    D.Push(EV_ABS, ABS_Z, 0);
    Pump;
    Check(J.Axes[2] = -32768, 'Z の最小は -32768');
    J.Close;
  finally
    CloseContext;
  end;

  // 死帯域
  H := MakeHost;
  D := H.Add(XboxLike('/dev/input/event0', 100, $1234, $5678, 1, 'Xbox Pad X'));
  OpenContext([PML_HINT_JOYSTICK_LINUX_DEADZONES, '1']);
  try
    J := OpenPad;
    Pump;
    D.Push(EV_ABS, ABS_X, 0);
    D.Push(EV_ABS, ABS_X, 20000);
    Pump;
    Check(J.Axes[0] = 20027, 'ヒントで死帯域を使うと 20000 は 20027（(40000 - 255) * 4128 >> 13。係数 -257・255・4128）: ' + IntToStr(J.Axes[0]));
    D.Push(EV_ABS, ABS_X, 200);
    Pump;
    Check(J.Axes[0] = 73, '200 は 73');
    D.Push(EV_ABS, ABS_X, -200);
    Pump;
    Check(J.Axes[0] = -73, '-200 は -73（算術シフトは負の無限大へ丸める）');
    D.Push(EV_ABS, ABS_X, 100);
    Pump;
    Check(J.Axes[0] = 0, '死帯域の中は 0');
    D.Push(EV_ABS, ABS_X, 32767);
    Pump;
    Check(J.Axes[0] = 32767, '範囲の端は 32767 で止まる');
    J.Close;
  finally
    CloseContext;
  end;

  // デジタルのハットの見分け
  H := MakeHost;
  D := TFakeDev.Create('/dev/input/event0', 100);
  D.Name := 'Hat Test';
  D.ID.BusType := 3; D.ID.Vendor := $1234; D.ID.Product := $0010; D.ID.Version := 1;
  D.SetKey(BTN_TRIGGER); D.SetKey(BTN_A);
  D.SetAbs(ABS_X, -100, 100, 0, 0, 0);
  D.SetAbs(ABS_Y, -100, 100, 0, 0, 0);
  D.SetAbs(ABS_HAT0X, -255, 255, 16, 16, 0);     // アナログに見える
  D.SetAbs(ABS_HAT0Y, -255, 255, 16, 16, 0);
  D.SetAbs(ABS_HAT1X, -1, 1, 0, 0, 0);           // 範囲が -1..1
  D.SetAbs(ABS_HAT1Y, 0, 4, 0, 0, 0);            // fuzz・flat が無い
  D.SetAbs(ABS_HAT2X, -50, 50, 3, 0, 0);         // 片方だけ（Y は無い）で fuzz がある
  H.Add(D);
  OpenContext([]);
  try
    J := OpenPad;
    Check(J.NumHats = 1, 'ハットは HAT1 だけ（HAT0 は fuzz・flat があるのでアナログ、HAT2X も fuzz があってアナログ）');
    Check(J.NumAxes = 2 + 2 + 1, '軸は X・Y と HAT0X・HAT0Y と HAT2X');
    J.Close;
  finally
    CloseContext;
  end;
  H := MakeHost;
  D := TFakeDev.Create('/dev/input/event0', 100);
  D.Name := 'Hat Test';
  D.ID.BusType := 3; D.ID.Vendor := $1234; D.ID.Product := $0010; D.ID.Version := 1;
  D.SetKey(BTN_TRIGGER);
  D.SetAbs(ABS_X, -100, 100, 0, 0, 0);
  D.SetAbs(ABS_Y, -100, 100, 0, 0, 0);
  D.SetAbs(ABS_HAT0X, -255, 255, 16, 16, 0);
  D.SetAbs(ABS_HAT0Y, -255, 255, 16, 16, 0);
  H.Add(D);
  OpenContext([PML_HINT_JOYSTICK_LINUX_DIGITAL_HATS, '1']);
  try
    J := OpenPad;
    Check((J.NumHats = 1) and (J.NumAxes = 2), 'ヒントで全部デジタルのハット');
    J.Close;
  finally
    CloseContext;
  end;
end;

procedure TestConfigMore;
var
  H: TFakeHost;
  D: TFakeDev;
  J: TPMLJoystick;
  IDs: TPMLJoystickIDs;
begin
  WriteLn('割り当てと軸の補正（続き）');
  // 軸の範囲 0..100: 小数の丸め
  H := MakeHost;
  D := TFakeDev.Create('/dev/input/event0', 100);
  D.Name := 'Range Test';
  D.ID.BusType := 3; D.ID.Vendor := $1234; D.ID.Product := $0040; D.ID.Version := 1;
  D.SetKey(BTN_TRIGGER); D.SetKey(BTN_1); D.SetKey(BTN_A);
  D.SetAbs(ABS_X, 0, 100, 0, 0, 0);
  D.SetAbs(ABS_Y, 0, 100, 0, 0, 0);
  H.Add(D);
  OpenContext([]);
  try
    J := OpenPad;
    Pump;
    D.Push(EV_ABS, ABS_X, 100);
    D.Push(EV_ABS, ABS_X, 2);
    Pump;
    Check(J.Axes[0] = -31457, '範囲 0..100 の 2 は -31457（655.35 倍 + (-32768) + 0.5 を切り捨て）: ' + IntToStr(J.Axes[0]));
    D.Push(EV_ABS, ABS_X, 100);
    Pump;
    Check(J.Axes[0] = 32767, '範囲 0..100 の 100 は 32767');
    // ボタンの番号: ジョイスティックのコード以上が先、手前の BTN_1 は最後
    Check(J.NumButtons = 3, 'ボタン 3 個');
    D.Push(EV_KEY, BTN_TRIGGER, 1);
    D.Push(EV_KEY, BTN_A, 1);
    D.Push(EV_KEY, BTN_1, 1);
    Pump;
    Check(J.Buttons[0] and J.Buttons[1] and J.Buttons[2], 'BTN_TRIGGER=0、BTN_A=1、BTN_1=2');
    D.Push(EV_KEY, BTN_1, 0);
    Pump;
    Check(J.Buttons[0] and J.Buttons[1] and not J.Buttons[2], 'BTN_1 はボタン 2');
    J.Close;
  finally
    CloseContext;
  end;

  // デジタルとみなしたハットが範囲の広い値を送る（死帯域）
  H := MakeHost;
  D := TFakeDev.Create('/dev/input/event0', 100);
  D.Name := 'Wide Hat';
  D.ID.BusType := 3; D.ID.Vendor := $1234; D.ID.Product := $0041; D.ID.Version := 1;
  D.SetKey(BTN_TRIGGER);
  D.SetAbs(ABS_X, -100, 100, 0, 0, 0);
  D.SetAbs(ABS_Y, -100, 100, 0, 0, 0);
  D.SetAbs(ABS_HAT0X, -255, 255, 16, 16, 0);
  D.SetAbs(ABS_HAT0Y, -255, 255, 16, 16, 0);
  H.Add(D);
  OpenContext([PML_HINT_JOYSTICK_LINUX_DIGITAL_HATS, '1']);
  try
    J := OpenPad;
    Pump;
    D.Push(EV_ABS, ABS_HAT0X, -50);
    Pump;
    Check(J.Hats[0] = PML_HAT_CENTERED, '死帯域の中（-50 は最小 -255 の 3 分の 1 より内側）は中央');
    D.Push(EV_ABS, ABS_HAT0X, -200);
    Pump;
    Check(J.Hats[0] = PML_HAT_LEFT, '-200 は左');
    D.Push(EV_ABS, ABS_HAT0X, 100);
    Pump;
    Check(J.Hats[0] = PML_HAT_RIGHT, '100 は最大 255 の 3 分の 1 を超えるので右');
    D.Push(EV_ABS, ABS_HAT0X, 50);
    Pump;
    Check(J.Hats[0] = PML_HAT_CENTERED, '50 は中央');
    D.Push(EV_ABS, ABS_HAT0X, -300);
    Pump;
    Check(J.Hats[0] = PML_HAT_LEFT, '最小を超えたら最小を覚えて左');
    D.Push(EV_ABS, ABS_HAT0X, -150);
    Pump;
    Check(J.Hats[0] = PML_HAT_LEFT, '覚えた最小 -300 の 3 分の 1 (-100) より外側の -150 は左');
    J.Close;
  finally
    CloseContext;
  end;
  H := MakeHost;
  D := TFakeDev.Create('/dev/input/event0', 100);
  D.Name := 'Wide Hat';
  D.ID.BusType := 3; D.ID.Vendor := $1234; D.ID.Product := $0041; D.ID.Version := 1;
  D.SetKey(BTN_TRIGGER);
  D.SetAbs(ABS_X, -100, 100, 0, 0, 0);
  D.SetAbs(ABS_Y, -100, 100, 0, 0, 0);
  D.SetAbs(ABS_HAT0X, -255, 255, 16, 16, 0);
  D.SetAbs(ABS_HAT0Y, -255, 255, 16, 16, 0);
  H.Add(D);
  OpenContext([PML_HINT_JOYSTICK_LINUX_DIGITAL_HATS, '1', PML_HINT_JOYSTICK_LINUX_HAT_DEADZONES, '0']);
  try
    J := OpenPad;
    Pump;
    D.Push(EV_ABS, ABS_HAT0X, -50);
    Pump;
    Check(J.Hats[0] = PML_HAT_LEFT, 'ヒントで死帯域を切ると -50 でも左');
    D.Push(EV_ABS, ABS_HAT0X, 50);
    Pump;
    Check(J.Hats[0] = PML_HAT_RIGHT, '50 は右');
    J.Close;
  finally
    CloseContext;
  end;

  // 機器ごとの版の補正
  H := MakeHost;
  H.Add(XboxLike('/dev/input/event0', 100, $3250, $1001, 5, 'Atari VCS'));
  H.Add(XboxLike('/dev/input/event1', 101, $045E, $0B05, $0903, 'Elite 2 old'));
  D := XboxLike('/dev/input/event2', 102, $045E, $0B05, $0903, 'Elite 2 dup');
  D.SetKey($2C0);
  H.Add(D);
  OpenContext([]);
  try
    IDs := Ctx.Joysticks.Joysticks;
    Check(Ctx.Joysticks.ProductVersionForID(IDs[0]) = 0, 'Atari VCS の版は 0（ファームウェアの版を使わない）');
    Check(Ctx.Joysticks.ProductVersionForID(IDs[1]) = $0903, 'Elite 2 の版はそのまま');
    Check(Ctx.Joysticks.ProductVersionForID(IDs[2]) = $0902, '入力を二重に持つ Elite 2 の最初のファームウェアは版を 0x0902 にする');
  finally
    CloseContext;
  end;
end;

procedure TestEvents;
var
  H: TFakeHost;
  D: TFakeDev;
  J: TPMLJoystick;
  S: String;
  E: TPMLEvent;
  Last, T1, T2: UInt64;
begin
  WriteLn('入力');
  H := MakeHost;
  D := H.Add(XboxLike('/dev/input/event0', 100, $1234, $5678, 1, 'Xbox Pad X'));
  SetBit(D.EvBits, EV_REL);
  SetBit(D.RelBits, REL_X);
  SetBit(D.RelBits, REL_Y);
  // 最初に押されているボタンと、軸の初期値
  SetBit(D.KeyState, BTN_B);
  D.AbsInfo[ABS_X].Value := 5000;
  OpenContext([]);
  try
    S := DrainText;
    J := OpenPad;
    S := DrainText;
    Check(S = 'down1;', '最初の更新で、押されているボタンが押された扱い: ' + S);
    Check(J.Buttons[1] and (J.Axes[0] = 5000), '初めの状態が読まれる');

    D.Push(EV_KEY, BTN_A, 1);
    D.Push(EV_SYN, SYN_REPORT, 0);
    Pump;
    S := DrainText;
    Check(S = 'down0;', 'ボタンを押す（BTN_A はボタン 0）: ' + S);
    D.Push(EV_KEY, BTN_A, 0);
    D.Push(EV_KEY, BTN_B, 0);
    D.Push(EV_KEY, BTN_THUMBR, 1);
    Pump;
    S := DrainText;
    Check(S = 'up0;up1;down10;', '離す・離す・押す: ' + S);
    D.Push(EV_KEY, BTN_C, 1);
    D.Push(EV_KEY, $7FF, 1);
    Pump;
    Check(DrainText = '', '機器が持たないキーは捨てる');

    // ハット
    D.Push(EV_ABS, ABS_HAT0X, -1);
    Pump;
    Check(J.Hats[0] = PML_HAT_LEFT, '十字キー 左');
    D.Push(EV_ABS, ABS_HAT0Y, -1);
    Pump;
    Check(J.Hats[0] = PML_HAT_LEFTUP, '十字キー 左上');
    D.Push(EV_ABS, ABS_HAT0X, 1);
    D.Push(EV_ABS, ABS_HAT0Y, 1);
    Pump;
    Check(J.Hats[0] = PML_HAT_RIGHTDOWN, '十字キー 右下');
    D.Push(EV_ABS, ABS_HAT0X, 0);
    D.Push(EV_ABS, ABS_HAT0Y, 0);
    Pump;
    Check(J.Hats[0] = PML_HAT_CENTERED, '十字キー 中央');
    S := DrainText;

    // ボール
    D.Push(EV_REL, REL_X, 5);
    D.Push(EV_REL, REL_Y, -3);
    D.Push(EV_REL, REL_X, 2);
    D.Push(EV_REL, 8, 9);          // REL_WHEEL は無視
    Pump;
    S := DrainText;
    Check(S = 'ball0=7,-3;', 'ボールの動きは 1 つに足される: ' + S);

    // SYN_DROPPED
    S := DrainText;
    D.Push(EV_KEY, BTN_A, 1);
    D.Push(EV_SYN, SYN_DROPPED, 0);
    D.Push(EV_KEY, BTN_START, 1);
    D.Push(EV_ABS, ABS_X, -9000);
    D.Push(EV_SYN, SYN_REPORT, 0);
    D.KeyState := Copy(D.KeyState);
    FillChar(D.KeyState[0], Length(D.KeyState), 0);
    SetBit(D.KeyState, BTN_Y);
    D.AbsInfo[ABS_X].Value := 7000;
    Pump;
    Check(not J.Buttons[0] and not J.Buttons[7] and J.Buttons[3], 'SYN_DROPPED の間の入力は捨て、SYN_REPORT で今の状態に追い付く');
    Check(J.Axes[0] = 7000, '軸も今の状態へ');
    S := DrainText;
    Check(Pos('down7', S) = 0, 'SYN_DROPPED の間の START の押下は出ない: ' + S);

    // 時刻
    Last := 0;
    D.PushSecs(EV_KEY, BTN_A, 1, 100, 0);
    D.PushSecs(EV_KEY, BTN_A, 0, 100, 2000);
    D.PushSecs(EV_KEY, BTN_A, 1, 100, 4000);
    Pump;
    T1 := 0;
    T2 := 0;
    while Ctx.Events.Poll(E) do
      if E.Kind in [TPMLEventKind.JoystickButtonDown, TPMLEventKind.JoystickButtonUp] then
      begin
        if T1 = 0 then
          T1 := E.Timestamp
        else
          T2 := E.Timestamp;
        Last := E.Timestamp;
      end;
    Check((T1 > 0) and (T2 >= T1) and (Last <= PMLNowNS), '時刻は増え、今を超えない');
    D.PushSecs(EV_KEY, BTN_A, 0, 100, 6000);
    D.PushSecs(EV_KEY, BTN_A, 1, 900000, 0);      // 未来の時刻は今に切り詰める
    Pump;
    T1 := 0;
    while Ctx.Events.Poll(E) do
      if E.Kind = TPMLEventKind.JoystickButtonDown then
        T1 := E.Timestamp;
    Check((T1 > 0) and (T1 <= PMLNowNS), '未来の時刻は今を超えない');

    // 外れる（ENODEV）
    D.GoneFlag := True;
    Pump;
    Check(Length(Ctx.Joysticks.Joysticks) = 0, '読むと ENODEV になった機器は、同じ更新で一覧から外れる');
    Check(not J.Connected, '開いたジョイスティックは Connected が False');
    J.Close;
  finally
    CloseContext;
  end;

  // 開かれていない機器が外れても気づかない（SDL と同じ）
  H := MakeHost;
  D := H.Add(XboxLike('/dev/input/event0', 100, $1234, $5678, 1, 'Xbox Pad X'));
  OpenContext([]);
  try
    D.GoneFlag := True;
    Pump;
    Check(Length(Ctx.Joysticks.Joysticks) = 1, '開かれていない機器は、通知が無ければ残る');
  finally
    CloseContext;
  end;
end;

procedure TestRumble;
var
  H: TFakeHost;
  D: TFakeDev;
  J: TPMLJoystick;
begin
  WriteLn('ランブル');
  H := MakeHost;
  D := H.Add(XboxLike('/dev/input/event0', 100, $1234, $5678, 1, 'Xbox Pad X'));
  OpenContext([]);
  try
    J := OpenPad;
    Check(TPMLJoystickCapability.Rumble in J.Capabilities, 'ff_rumble があれば能力に Rumble');
    Check(J.Rumble(100, 200, 0), 'ランブル');
    Check(D.Log.Text = 'upload rumble id=0 len=65535 strong=100 weak=200' + LineEnding + 'play id=0' + LineEnding,
      '効果を書いて始める（強い=低周波、弱い=高周波、長さ 65535）: ' + D.Log.Text);
    D.Log.Clear;
    Check(J.Rumble(300, 400, 0), '強さを変える');
    Check(D.Log.Text = 'upload rumble id=0 len=65535 strong=300 weak=400' + LineEnding + 'play id=0' + LineEnding,
      '同じ効果を更新して始める: ' + D.Log.Text);
    D.Log.Clear;
    D.FailUploads := 1;
    Check(J.Rumble(500, 600, 0), 'カーネルが効果を失っていても作り直す');
    Check(D.Log.Text = 'upload failed id=0' + LineEnding + 'upload rumble id=1 len=65535 strong=500 weak=600' + LineEnding
      + 'play id=1' + LineEnding, '失敗したら ID を -1 にして新しく割り当てさせる: ' + D.Log.Text);
    D.Log.Clear;
    J.Close;
    Check(D.Log.Text = 'remove id=1' + LineEnding, '閉じるときに効果を消す: ' + D.Log.Text);
  finally
    CloseContext;
  end;

  H := MakeHost;
  D := H.Add(XboxLike('/dev/input/event0', 100, $1234, $5678, 1, 'Xbox Pad X'));
  FillChar(D.FFBits[0], Length(D.FFBits), 0);
  SetBit(D.FFBits, FF_SINE);
  OpenContext([]);
  try
    J := OpenPad;
    Check(J.Rumble(1000, 3000, 0), 'ff_sine だけでも鳴らせる');
    Check(D.Log.Text = 'upload periodic id=0 len=65535 wave=' + IntToStr(FF_SINE) + ' mag=1000' + LineEnding + 'play id=0' + LineEnding,
      '2 つの強さを半分にして平均（(500 + 1500) / 2 = 1000）: ' + D.Log.Text);
    J.Close;
  finally
    CloseContext;
  end;

  H := MakeHost;
  D := H.Add(XboxLike('/dev/input/event0', 100, $1234, $5678, 1, 'Xbox Pad X'));
  FillChar(D.FFBits[0], Length(D.FFBits), 0);
  OpenContext([]);
  try
    J := OpenPad;
    Check(not (TPMLJoystickCapability.Rumble in J.Capabilities), 'ff が無ければ Rumble の能力は無い');
    Check(not J.Rumble(1, 1, 0), 'ランブルは対応しない');
    J.Close;
  finally
    CloseContext;
  end;
end;

procedure TestMapping;
var
  H: TFakeHost;
  D: TFakeDev;
  IDs: TPMLJoystickIDs;
  M, Body: String;

  function MappingBody(AID: TPMLJoystickID): String;
  var
    S: String;
    P: Integer;
  begin
    S := Ctx.Gamepads.MappingForID(AID);
    // GUID,名前, の後ろ
    P := Pos(',', S);
    S := Copy(S, P + 1, MaxInt);
    P := Pos(',', S);
    Result := Copy(S, P + 1, MaxInt);
  end;

begin
  WriteLn('ゲームパッドの割り当て（Linux Gamepad Specification）');
  H := MakeHost;
  H.Add(XboxLike('/dev/input/event0', 100, $1234, $5678, 1, 'Xbox Pad X'));
  // PlayStation 風（ベンダーが Sony）: X と Y は BTN_WEST と BTN_NORTH
  H.Add(XboxLike('/dev/input/event1', 101, $054C, $0001, 1, 'Sony Like Pad'));
  // xpad: 十字キーが BTN_TRIGGER_HAPPY1〜4
  D := H.Add(XboxLike('/dev/input/event2', 102, $1234, $0010, 1, 'Xpad Dpad'));
  D.SetKey(BTN_TRIGGER_HAPPY1); D.SetKey(BTN_TRIGGER_HAPPY2); D.SetKey(BTN_TRIGGER_HAPPY3); D.SetKey(BTN_TRIGGER_HAPPY4);
  FillChar(D.AbsBits[0], Length(D.AbsBits), 0);
  D.SetAbs(ABS_X, -32768, 32767, 16, 128, 0);
  D.SetAbs(ABS_Y, -32768, 32767, 16, 128, 0);
  D.UdevDriver := 'xpad'; D.UdevVendor := $1234; D.UdevProduct := $0010; D.UdevVersion := 1;
  H.Method := TPMLHotplugMethod.Udev;
  // デジタルの十字キー・Android 流のトリガーと右スティック
  D := TFakeDev.Create('/dev/input/event3', 103);
  D.Name := 'Android Like';
  D.ID.BusType := 3; D.ID.Vendor := $1234; D.ID.Product := $0020; D.ID.Version := 1;
  D.SetKey(BTN_A); D.SetKey(BTN_B);
  D.SetKey(BTN_DPAD_UP); D.SetKey(BTN_DPAD_DOWN); D.SetKey(BTN_DPAD_LEFT); D.SetKey(BTN_DPAD_RIGHT);
  D.SetKey(BTN_TL2); D.SetKey(BTN_TR2);
  D.SetAbs(ABS_X, -128, 127, 0, 0, 0);
  D.SetAbs(ABS_Y, -128, 127, 0, 0, 0);
  D.SetAbs(ABS_Z, -128, 127, 0, 0, 0);
  D.SetAbs(ABS_RZ, -128, 127, 0, 0, 0);
  D.SetAbs(ABS_BRAKE, 0, 255, 0, 0, 0);
  D.SetAbs(ABS_GAS, 0, 255, 0, 0, 0);
  H.Add(D);
  // ハットで十字キー・肩のボタン・トリガーを持つ機器
  D := TFakeDev.Create('/dev/input/event4', 104);
  D.Name := 'Hat Pad';
  D.ID.BusType := 3; D.ID.Vendor := $1234; D.ID.Product := $0021; D.ID.Version := 1;
  D.SetKey(BTN_A);
  D.SetKey(BTN_B);
  D.SetAbs(ABS_HAT0X, -1, 1, 0, 0, 0);
  D.SetAbs(ABS_HAT0Y, -1, 1, 0, 0, 0);
  D.SetAbs(ABS_HAT1X, -1, 1, 0, 0, 0);
  D.SetAbs(ABS_HAT1Y, -1, 1, 0, 0, 0);
  D.SetAbs(ABS_HAT2X, -1, 1, 0, 0, 0);
  D.SetAbs(ABS_HAT2Y, -1, 1, 0, 0, 0);
  H.Add(D);
  OpenContext([]);
  try
    IDs := Ctx.Joysticks.Joysticks;
    Check(Length(IDs) = 5, '5 台');
    Body := MappingBody(IDs[4]);
    Check(Body = 'a:b0,b:b1,leftshoulder:h1.4,rightshoulder:h1.2,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,'
      + 'lefttrigger:h2.4,righttrigger:h2.2,', 'ハットの肩のボタン・トリガー・十字キー: ' + Body);
    // Xbox 風
    Body := MappingBody(IDs[0]);
    Check(Body = 'a:b0,b:b1,x:b2,y:b3,back:b6,guide:b8,start:b7,leftstick:b9,rightstick:b10,leftshoulder:b4,'
      + 'rightshoulder:b5,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a3,righty:a4,'
      + 'lefttrigger:a2,righttrigger:a5,', 'Xbox 風: ' + Body);
    // Sony: x は BTN_WEST（BTN_Y と同じコード）、y は BTN_NORTH（BTN_X と同じコード）
    Body := MappingBody(IDs[1]);
    Check(Pos('x:b3,y:b2,', Body) > 0, 'Sony は X が BTN_WEST・Y が BTN_NORTH: ' + Body);
    // xpad の十字キー
    Body := MappingBody(IDs[2]);
    Check(Body = 'a:b0,b:b1,x:b2,y:b3,back:b6,guide:b8,start:b7,leftstick:b9,rightstick:b10,leftshoulder:b4,'
      + 'rightshoulder:b5,dpup:b13,dpdown:b14,dpleft:b11,dpright:b12,leftx:a0,lefty:a1,',
      'xpad の BTN_TRIGGER_HAPPY1〜4（番号 11〜14）が十字キー: ' + Body);
    // Android 流
    Body := MappingBody(IDs[3]);
    // 軸の番号は コードの順: X0・Y1・Z2・RZ3・GAS4・BRAKE5
    Check(Body = 'a:b0,b:b1,dpup:b4,dpdown:b5,dpleft:b6,dpright:b7,leftx:a0,lefty:a1,rightx:a2,righty:a3,'
      + 'lefttrigger:a5,righttrigger:a4,', 'Android 流（ABS_BRAKE・ABS_GAS のトリガー、Z・RZ の右スティック、デジタルの十字キー）: ' + Body);
    M := Ctx.Gamepads.MappingForID(IDs[3]);
    Check(M <> '', 'ゲームパッドとして使える');
  finally
    CloseContext;
  end;

  // BTN_GAMEPAD が無い機器はゲームパッドではない
  H := MakeHost;
  D := TFakeDev.Create('/dev/input/event0', 100);
  D.Name := 'Flight Stick';
  D.ID.BusType := 3; D.ID.Vendor := $1234; D.ID.Product := $0030; D.ID.Version := 1;
  D.SetKey(BTN_TRIGGER);
  D.SetAbs(ABS_X, -100, 100, 0, 0, 0);
  D.SetAbs(ABS_Y, -100, 100, 0, 0, 0);
  H.Add(D);
  OpenContext([]);
  try
    IDs := Ctx.Joysticks.Joysticks;
    Check((Length(IDs) = 1) and not Ctx.Gamepads.IsGamepad(IDs[0]), 'BTN_GAMEPAD が無ければゲームパッドではない');
  finally
    CloseContext;
  end;
end;

procedure TestNames;
var
  I, Bad, P1, P2, P3, P4: Integer;
  Line, VN, PN, Want, Got: String;
  V, P: Word;
begin
  WriteLn('機器の名前（SDL_CreateJoystickName と同じ）');
  MakeHost;
  OpenContext([]);
  try
    Bad := 0;
    for I := 0 to High(JoystickNamesExpected) do
    begin
      Line := JoystickNamesExpected[I];
      P1 := Pos('|', Line);
      P2 := P1 + Pos('|', Copy(Line, P1 + 1, MaxInt));
      P3 := P2 + Pos('|', Copy(Line, P2 + 1, MaxInt));
      P4 := P3 + Pos('|', Copy(Line, P3 + 1, MaxInt));
      V := StrToInt('$' + Copy(Line, 1, P1 - 1));
      P := StrToInt('$' + Copy(Line, P1 + 1, P2 - P1 - 1));
      VN := Copy(Line, P2 + 1, P3 - P2 - 1);
      PN := Copy(Line, P3 + 1, P4 - P3 - 1);
      Want := Copy(Line, P4 + 1, MaxInt);
      Got := Ctx.Joysticks.CreateJoystickName(V, P, VN, PN);
      if Got = '' then
        Got := '(null)';
      if Got <> Want then
      begin
        Inc(Bad);
        if Bad <= 3 then
          WriteLn(Format('    %s → papimela="%s" SDL="%s"', [Line, Got, Want]));
      end;
    end;
    Check(Length(JoystickNamesExpected) > 2800, Format('%d 件を比べた', [Length(JoystickNamesExpected)]));
    Check(Bad = 0, Format('全件が SDL と同じ（食い違い %d 件）', [Bad]));
  finally
    CloseContext;
  end;
end;

procedure TestReal;
var
  Host_: TPMLRealEvdevHost;
  Names: TStringArray;
  MTime: Int64;
  I, Events, DummyClass: Integer;
  DummyID: TPMLInputID;
  DummyDriver: String;
begin
  DummyClass := 0;
  FillChar(DummyID, SizeOf(DummyID), 0);
  WriteLn('本物の窓口（/dev/input を数えるだけ）');
  Host_ := TPMLRealEvdevHost.Create;
  try
    Names := Host_.ListInputDirectory;
    Events := 0;
    for I := 0 to High(Names) do
      if (Copy(Names[I], 1, 5) = 'event') then
        Inc(Events);
    if DirectoryExists('/dev/input') then
    begin
      Check(Host_.InputDirectoryMTime(MTime) and (MTime > 0), '/dev/input の更新時刻が分かる');
      Check(True, Format('event の機器 %d 台', [Events]));
    end
    else
      Check(Length(Names) = 0, '/dev/input が無ければ一覧は空');
    Check(Host_.OpenNode('/dev/input/event-no-such', True) = nil, '無い機器は開けない');
    Check(Host_.JsIndexForEvent(99999) = -1, '知らない event の js の番号は -1');
    Check(not Host_.ProductInfo('/dev/null', DummyID, DummyClass, DummyDriver), 'udev を始めていなければ ProductInfo は False');
  finally
    Host_.Free;
  end;
end;

begin
  WriteLn('=== test_joystick_linux ===');
  TestDetect;
  TestFilters;
  TestHotplug;
  TestConfig;
  TestConfigMore;
  TestEvents;
  TestRumble;
  TestMapping;
  TestNames;
  TestReal;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: Linux のジョイスティックのバックエンドが期待どおり動く ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
