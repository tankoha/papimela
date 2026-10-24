{
  test_haptic — ハプティクス（力覚。PaPiMeLa.Haptic・.Haptic.Backend・.Haptic.Linux）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    /dev/input/event* の FF は input グループが要り、実機の力覚の機器も CI に無い。そこで機器への触り方の抽象
    （TPMLEvdevHost・TPMLEvdevNode。PaPiMeLa.Joystick.Linux.Node）の偽物を作り、機器の能力と書き込みの記録で
    バックエンドの中身を通す。期待値は 2 通り:
      convert  SDL の SDL_SYS_ToFFEffect を、SDL のソースから抜き出して動かした結果（test/haptic_expected.inc の E 行）と、
               ff_effect の 48 バイトまで比べる（12 種類 700 場面ぶん + 変換できない 3 つ）。向きの変換の整数の回り込みと
               atan2f も含む
      axes     ヒントの軸の数（SDL_Haptic_Get_Naxes。SDL_sscanf の癖を含む。N 行）
    それ以外は、SDL_haptic.c と SDL_syshaptic.c の読みから手で求めた期待値（SDL に同じ場面を通した記録が取れない。
    SDL の C は fd を直接使う）:
      scan     初めの走査（event0〜31。FF の無い機器・書き込めない機器・重複は捨てる）、能力の写し、名前、ID
      open     開く・閉じる（同じ ID は同じオブジェクト、回数）、開いた直後のゲイン最大・オートセンタ切り
      effects  作る・更新・再生・止める・消す、型の違反、番号の違反、空きの無いとき、作っていない番号（SDL は落ちる）
      gain     ゲインとオートセンタ（範囲、ヒントによる最大の絞り込み）、一時停止、状態の問い合わせ
      rumble   簡易ランブル（サインのある機器・左右だけの機器）
      mouse    マウスの機器（BTN_MOUSE を持つ機器だけ）
      joystick ジョイスティックから開く（ゲームパッドは断る、同じ機器は同じオブジェクト、ヒントの軸の数）
      hotplug  抜き差し（udev は JOYSTICK の種類だけ）
      context  Context に組み込まれること
    検査は実装の後に書いた。空の実装で落ちることの代わりに、変異（誤りを入れて落ちること）で歯を確かめた
    （docs/TEST-LOG.md の T-76）。
}
program test_haptic;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils, Classes, Math,
  PaPiMeLa.Errors,
  PaPiMeLa.Properties,
  PaPiMeLa.Events,
  PaPiMeLa.Core,
  PaPiMeLa.Joystick.Backend,
  PaPiMeLa.Joystick,
  PaPiMeLa.Haptic.Backend,
  PaPiMeLa.Haptic,
  PaPiMeLa.Platform.Evdev,
  PaPiMeLa.Joystick.Linux.Node,
  PaPiMeLa.Joystick.Linux,
  PaPiMeLa.Joystick.Virtual,
  PaPiMeLa.Haptic.Linux;

{$I haptic_expected.inc}

type
  { 偽の機器 1 台。能力と、書き込みの記録を持つ。 }
  TFakeDev = class
  public
    Path       : String;
    DevNum     : QWord;
    Name       : String;
    ID         : TPMLInputID;
    EvBits, KeyBits, AbsBits, FFBits: TPMLBits;
    Capacity   : Integer;             // EVIOCGEFFECTS
    CapacityFails: Boolean;
    Effects    : array of TPMLFFEffect;
    Present    : array of Boolean;
    Log        : TStringList;
    NextEffect : Integer;
    FailUploads: Integer;
    FailWrites : Boolean;
    Opens      : Integer;
    DenyWrite  : Boolean;
    UdevClass  : Integer;
    constructor Create(const APath: String; ADevNum: QWord);
    destructor Destroy; override;
    procedure SetKey(ACode: Integer);
    procedure SetAbs(ACode: Integer);
    procedure SetFF(ACode: Integer);
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
    function  WriteFF(ACode, AValue: Integer): Boolean; override;
    function  GetEffectCount(out ACount: Integer): Boolean; override;
    function  Gone: Boolean; override;
    function  Writable: Boolean; override;
    function  Error: String; override;
  end;

  // 偽の窓口。機器の一覧は全部の窓口で共有する（ジョイスティックと力覚が同じ機器を見る）。
  TFakeHost = class(TPMLEvdevHost)
  public
    Method     : TPMLHotplugMethod;
    Callback   : TPMLHotplugCallback;
    Fired      : TStringList;      // 'A|class|path' / 'R|0|path'
    InSandbox  : Boolean;
    UdevAsked  : Boolean;
    ScanCount  : Integer;
    Stopped    : Boolean;
    constructor Create;
    destructor Destroy; override;
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
  Devices: TList;                 // TFakeDev（全部の窓口で共有。終わりに壊す）
  HapHost: TFakeHost;             // 最後に作った力覚の窓口
  UdevMode: TPMLHotplugMethod = TPMLHotplugMethod.None;
  SandboxMode: Boolean = False;     // 次に作る力覚の窓口を、コンテナの中にいることにする
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
  Log := TStringList.Create;
  SetLength(EvBits, 8);
  SetLength(KeyBits, 96);
  SetLength(AbsBits, 8);
  SetLength(FFBits, 16);
  UdevClass := PML_UDEV_DEVICE_JOYSTICK;
  Capacity := 16;
  SetLength(Effects, 64);
  SetLength(Present, 64);
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

procedure TFakeDev.SetAbs(ACode: Integer);
begin
  SetBit(AbsBits, ACode);
  SetBit(EvBits, EV_ABS);
end;

procedure TFakeDev.SetFF(ACode: Integer);
begin
  SetBit(FFBits, ACode);
  SetBit(EvBits, EV_FF);
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
    EV_FF: ABits := Bits(FDev.FFBits, ABitCount);
    EV_REL: ABits := Bits(FDev.AbsBits, ABitCount);
  else
    Result := False;
  end;
end;

function TFakeNode.GetProps(out ABits: TPMLBits): Boolean;
begin
  SetLength(ABits, 8);
  FillChar(ABits[0], 8, 0);
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
  Result := FDev.Name <> '';
end;

function TFakeNode.GetJsName(out AName: String): Boolean;
begin
  AName := '';
  Result := False;
end;

function TFakeNode.GetAbsInfo(AAxis: Integer; out AInfo: TPMLInputAbsInfo): Boolean;
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
  AInfo.Minimum := -32768;
  AInfo.Maximum := 32767;
  Result := True;
end;

function TFakeNode.GetKeyState(out ABits: TPMLBits): Boolean;
begin
  ABits := Bits(FDev.KeyBits, KEY_MAX + 1);
  FillChar(ABits[0], Length(ABits), 0);
  Result := True;
end;

function TFakeNode.ReadEvents(var ABuffer: TPMLInputEventArray): Integer;
begin
  Result := 0;
end;

function TFakeNode.UploadEffect(var AEffect: TPMLFFEffect): Boolean;
var
  I: Integer;
begin
  if FDev.FailUploads > 0 then
  begin
    Dec(FDev.FailUploads);
    FDev.Log.Add('upload failed id=' + IntToStr(AEffect.ID));
    Exit(False);
  end;
  if AEffect.ID < 0 then
  begin
    // 空いた番号を割り当てる。容量が尽きていたら断る（カーネルの ENOSPC）
    AEffect.ID := -1;
    for I := 0 to FDev.Capacity - 1 do
      if not FDev.Present[I] then
      begin
        AEffect.ID := I;
        Break;
      end;
    if AEffect.ID < 0 then
    begin
      FDev.Log.Add('upload full');
      Exit(False);
    end;
  end;
  FDev.Present[AEffect.ID] := True;
  FDev.Effects[AEffect.ID] := AEffect;
  FDev.Log.Add(Format('upload id=%d type=%d', [AEffect.ID, AEffect.EffectType]));
  Result := True;
end;

function TFakeNode.RemoveEffect(AID: Integer): Boolean;
begin
  FDev.Log.Add('remove id=' + IntToStr(AID));
  if (AID >= 0) and (AID < Length(FDev.Present)) then
    FDev.Present[AID] := False;
  Result := True;
end;

function TFakeNode.PlayEffect(AID: Integer): Boolean;
begin
  FDev.Log.Add('play id=' + IntToStr(AID));
  Result := True;
end;

function TFakeNode.WriteFF(ACode, AValue: Integer): Boolean;
begin
  if FDev.FailWrites then
    Exit(False);
  if ACode = FF_GAIN then
    FDev.Log.Add('gain=' + IntToStr(AValue))
  else if ACode = FF_AUTOCENTER then
    FDev.Log.Add('autocenter=' + IntToStr(AValue))
  else
    FDev.Log.Add(Format('ff id=%d value=%d', [ACode, AValue]));
  Result := True;
end;

function TFakeNode.GetEffectCount(out ACount: Integer): Boolean;
begin
  ACount := FDev.Capacity;
  Result := not FDev.CapacityFails;
end;

function TFakeNode.Gone: Boolean;
begin
  Result := False;
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
  Fired := TStringList.Create;
  Method := UdevMode;
end;

destructor TFakeHost.Destroy;
begin
  Fired.Free;
  inherited Destroy;
end;

procedure TFakeHost.Fire(AAdded: Boolean; AClass: Integer; const APath: String);
begin
  if AAdded then
    Fired.Add(Format('A|%d|%s', [AClass, APath]))
  else
    Fired.Add(Format('R|%d|%s', [AClass, APath]));
end;

function FindDev(const APath: String): TFakeDev;
var
  I: Integer;
begin
  for I := 0 to Devices.Count - 1 do
    if TFakeDev(Devices[I]).Path = APath then
      Exit(TFakeDev(Devices[I]));
  Result := nil;
end;

function TFakeHost.OpenNode(const APath: String; AWritable: Boolean): TPMLEvdevNode;
var
  D: TFakeDev;
begin
  D := FindDev(APath);
  if D = nil then
    Exit(nil);
  // 書き込みを許さない機器は、書き込みで開くと開けない（O_RDWR の失敗）
  if AWritable and D.DenyWrite then
    Exit(nil);
  Result := TFakeNode.Create(D, AWritable);
end;

function TFakeHost.DeviceNumber(const APath: String; out ADevNum: QWord): Boolean;
var
  D: TFakeDev;
begin
  D := FindDev(APath);
  Result := D <> nil;
  if Result then
    ADevNum := D.DevNum
  else
    ADevNum := 0;
end;

function TFakeHost.ListInputDirectory: TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Devices.Count);
  for I := 0 to Devices.Count - 1 do
    Result[I] := ExtractFileName(TFakeDev(Devices[I]).Path);
end;

function TFakeHost.InputDirectoryMTime(out AMTime: Int64): Boolean;
begin
  AMTime := Devices.Count;
  Result := True;
end;

function TFakeHost.JsIndexForEvent(AEvent: Integer): Integer;
begin
  Result := -1;
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
  Parts, Items: TStringList;
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
  Stopped := True;
end;

function TFakeHost.ProductInfo(const APath: String; var AID: TPMLInputID; var AClass: Integer;
  out ADriver: String): Boolean;
begin
  ADriver := '';
  Result := False;
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
  Result := 10000;
end;

function HapticHostFactory: TPMLEvdevHost;
begin
  HapHost := TFakeHost.Create;
  HapHost.InSandbox := SandboxMode;
  Result := HapHost;
end;

function JoystickHostFactory: TPMLEvdevHost;
begin
  Result := TFakeHost.Create;
end;

{ ---- 場面の道具 ---- }

procedure ClearDevices;
var
  I: Integer;
begin
  for I := 0 to Devices.Count - 1 do
    TObject(Devices[I]).Free;
  Devices.Clear;
end;

function AddDev(ADev: TFakeDev): TFakeDev;
begin
  Devices.Add(ADev);
  Result := ADev;
end;

{ ハンドル付きの力覚の機器: サインと左右とゲインとオートセンタ（FF のハンドル風）。 }
function Wheel(const APath: String; ADevNum: QWord; const AName: String): TFakeDev;
var
  D: TFakeDev;
begin
  D := TFakeDev.Create(APath, ADevNum);
  D.Name := AName;
  D.ID.BusType := 3;
  D.ID.Vendor := $1234;
  D.ID.Product := Word(ADevNum);
  D.ID.Version := 1;
  D.SetFF(FF_CONSTANT); D.SetFF(FF_SINE); D.SetFF(FF_SQUARE); D.SetFF(FF_TRIANGLE);
  D.SetFF(FF_SAW_UP); D.SetFF(FF_SAW_DOWN); D.SetFF(FF_RAMP); D.SetFF(FF_SPRING);
  D.SetFF(FF_FRICTION); D.SetFF(FF_DAMPER); D.SetFF(FF_INERTIA);
  D.SetFF(FF_GAIN); D.SetFF(FF_AUTOCENTER); D.SetFF(FF_RUMBLE);
  // 軸とボタン（ジョイスティックとしても見える。BTN_SOUTH が無いのでゲームパッドではない）
  D.SetKey(BTN_TRIGGER);
  D.SetAbs(ABS_X); D.SetAbs(ABS_Y);
  Result := D;
end;

{ 左右のモーターだけのパッド（FF_RUMBLE だけ）。 }
function RumblePad(const APath: String; ADevNum: QWord; const AName: String): TFakeDev;
var
  D: TFakeDev;
begin
  D := TFakeDev.Create(APath, ADevNum);
  D.Name := AName;
  D.ID.BusType := 3;
  D.ID.Vendor := $045E;
  D.ID.Product := $028E;
  D.ID.Version := 0;
  D.SetFF(FF_RUMBLE);
  D.SetKey(BTN_SOUTH); D.SetKey(BTN_EAST); D.SetKey(BTN_NORTH); D.SetKey(BTN_WEST);
  D.SetKey(BTN_TL); D.SetKey(BTN_TR); D.SetKey(BTN_SELECT); D.SetKey(BTN_START);
  D.SetKey(BTN_MODE); D.SetKey(BTN_THUMBL); D.SetKey(BTN_THUMBR);
  D.SetAbs(ABS_X); D.SetAbs(ABS_Y); D.SetAbs(ABS_RX); D.SetAbs(ABS_RY); D.SetAbs(ABS_Z); D.SetAbs(ABS_RZ);
  D.SetAbs(ABS_HAT0X); D.SetAbs(ABS_HAT0Y);
  Result := D;
end;

function Mouse(const APath: String; ADevNum: QWord): TFakeDev;
var
  D: TFakeDev;
begin
  D := TFakeDev.Create(APath, ADevNum);
  D.Name := 'Force Mouse';
  D.SetKey(BTN_MOUSE);
  D.SetFF(FF_RUMBLE);
  Result := D;
end;

procedure OpenContext(ASubsystems: TPMLSubsystems; const AExtraHints: array of String);
var
  Opts: TPMLContextOptions;
  I: Integer;
begin
  PMLLinuxHapticHostFactory := @HapticHostFactory;
  PMLLinuxJoystickHostFactory := @JoystickHostFactory;
  Opts := TPMLContextOptions.Default;
  Opts.Hints.Add(PML_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, '1');
  I := 0;
  while I + 1 <= High(AExtraHints) do
  begin
    Opts.Hints.Add(AExtraHints[I], AExtraHints[I + 1]);
    Inc(I, 2);
  end;
  Ctx := TPMLContext.Create(ASubsystems, Opts);
end;

procedure CloseContext;
begin
  FreeAndNil(Ctx);
  HapHost := nil;
  PMLLinuxHapticHostFactory := nil;
  PMLLinuxJoystickHostFactory := nil;
end;

function FirstID: TPMLHapticID;
var
  IDs: TPMLHapticIDs;
begin
  IDs := Ctx.Haptics.Haptics;
  Result := 0;
  if Length(IDs) > 0 then
    Result := IDs[0];
end;

function LogText(ADev: TFakeDev): String;
begin
  Result := StringReplace(Trim(ADev.Log.Text), #10, ';', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
end;

function Constant_(ALength: Cardinal; ALevel: SmallInt): TPMLHapticEffect;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.EffectType := PML_HAPTIC_CONSTANT;
  Result.Constant.Direction.DirType := PML_HAPTIC_CARTESIAN;
  Result.Constant.Direction.Dir[0] := 1;
  Result.Constant.Length := ALength;
  Result.Constant.Level := ALevel;
end;

function Sine_(ALength: Cardinal; AMagnitude: SmallInt): TPMLHapticEffect;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.EffectType := PML_HAPTIC_SINE;
  Result.Periodic.Direction.DirType := PML_HAPTIC_CARTESIAN;
  Result.Periodic.Direction.Dir[0] := 1;
  Result.Periodic.Length := ALength;
  Result.Periodic.Period := 100;
  Result.Periodic.Magnitude := AMagnitude;
end;

function LeftRight_(ALength: Cardinal; ALarge, ASmall: Word): TPMLHapticEffect;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.EffectType := PML_HAPTIC_LEFTRIGHT;
  Result.LeftRight.Length := ALength;
  Result.LeftRight.LargeMagnitude := ALarge;
  Result.LeftRight.SmallMagnitude := ASmall;
end;

function Spring_: TPMLHapticEffect;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.EffectType := PML_HAPTIC_SPRING;
  Result.Condition.Direction.DirType := PML_HAPTIC_STEERING_AXIS;
  Result.Condition.Length := PML_HAPTIC_INFINITY;
end;

{ ---- 場面: convert（SDL の SDL_SYS_ToFFEffect の出力と ff_effect の 48 バイトまで比べる） ---- }

function Hex48(const AEffect: TPMLFFEffect): String;
var
  P: PByte;
  I: Integer;
begin
  Result := '';
  P := @AEffect;
  for I := 0 to SizeOf(AEffect) - 1 do
    Result := Result + LowerCase(IntToHex(P[I], 2));
end;

procedure SplitRow(const ARow: String; ATokens: TStringList);
begin
  ATokens.Clear;
  ATokens.Delimiter := ' ';
  ATokens.StrictDelimiter := True;
  ATokens.DelimitedText := ARow;
end;

// 行の値から効果を組み立てる。ARest は型の後ろの先頭の番号。
procedure ReadHeader(T: TStringList; var AIdx: Integer; out ADir: TPMLHapticDirection;
  out ALength: Cardinal; out ADelay, AButton, AInterval: Word);
begin
  ADir.DirType := Byte(StrToInt(T[AIdx]));
  ADir.Dir[0] := StrToInt(T[AIdx + 1]);
  ADir.Dir[1] := StrToInt(T[AIdx + 2]);
  ADir.Dir[2] := StrToInt(T[AIdx + 3]);
  ALength := Cardinal(StrToInt64(T[AIdx + 4]));
  ADelay := Word(StrToInt(T[AIdx + 5]));
  AButton := Word(StrToInt(T[AIdx + 6]));
  AInterval := Word(StrToInt(T[AIdx + 7]));
  Inc(AIdx, 8);
end;

procedure TestConvert;
var
  T: TStringList;
  Row, Pass, Fail, OkCount, I, K, Idx: Integer;
  E: TPMLHapticEffect;
  FF: TPMLFFEffect;
  Err, ExpectedHex: String;
  Expected: Boolean;
  Typ: Word;
  Bad: String;
  Cnt: array[0..3] of Integer;
begin
  WriteLn('convert: SDL の SDL_SYS_ToFFEffect と ff_effect の 48 バイトまで一致するか');
  T := TStringList.Create;
  try
    Pass := 0;
    Fail := 0;
    OkCount := 0;
    FillChar(Cnt, SizeOf(Cnt), 0);
    Bad := '';
    for Row := 0 to High(HapticExpected) do
    begin
      if HapticExpected[Row][1] <> 'E' then
        Continue;
      SplitRow(HapticExpected[Row], T);
      Typ := Word(StrToInt(T[1]));
      FillChar(E, SizeOf(E), 0);
      E.EffectType := Typ;
      Idx := 2;
      case Typ of
        PML_HAPTIC_CONSTANT:
          begin
            ReadHeader(T, Idx, E.Constant.Direction, E.Constant.Length, E.Constant.Delay, E.Constant.Button,
              E.Constant.Interval);
            E.Constant.Level := SmallInt(StrToInt(T[Idx]));
            E.Constant.AttackLength := Word(StrToInt(T[Idx + 1]));
            E.Constant.AttackLevel := Word(StrToInt(T[Idx + 2]));
            E.Constant.FadeLength := Word(StrToInt(T[Idx + 3]));
            E.Constant.FadeLevel := Word(StrToInt(T[Idx + 4]));
            Inc(Idx, 5);
          end;
        PML_HAPTIC_SINE, PML_HAPTIC_SQUARE, PML_HAPTIC_TRIANGLE, PML_HAPTIC_SAWTOOTHUP, PML_HAPTIC_SAWTOOTHDOWN:
          begin
            ReadHeader(T, Idx, E.Periodic.Direction, E.Periodic.Length, E.Periodic.Delay, E.Periodic.Button,
              E.Periodic.Interval);
            E.Periodic.Period := Word(StrToInt(T[Idx]));
            E.Periodic.Magnitude := SmallInt(StrToInt(T[Idx + 1]));
            E.Periodic.Offset := SmallInt(StrToInt(T[Idx + 2]));
            E.Periodic.Phase := Word(StrToInt(T[Idx + 3]));
            E.Periodic.AttackLength := Word(StrToInt(T[Idx + 4]));
            E.Periodic.AttackLevel := Word(StrToInt(T[Idx + 5]));
            E.Periodic.FadeLength := Word(StrToInt(T[Idx + 6]));
            E.Periodic.FadeLevel := Word(StrToInt(T[Idx + 7]));
            Inc(Idx, 8);
          end;
        PML_HAPTIC_SPRING, PML_HAPTIC_DAMPER, PML_HAPTIC_INERTIA, PML_HAPTIC_FRICTION:
          begin
            ReadHeader(T, Idx, E.Condition.Direction, E.Condition.Length, E.Condition.Delay, E.Condition.Button,
              E.Condition.Interval);
            for K := 0 to 2 do E.Condition.RightSat[K] := Word(StrToInt(T[Idx + K]));
            for K := 0 to 2 do E.Condition.LeftSat[K] := Word(StrToInt(T[Idx + 3 + K]));
            for K := 0 to 2 do E.Condition.RightCoeff[K] := SmallInt(StrToInt(T[Idx + 6 + K]));
            for K := 0 to 2 do E.Condition.LeftCoeff[K] := SmallInt(StrToInt(T[Idx + 9 + K]));
            for K := 0 to 2 do E.Condition.Deadband[K] := Word(StrToInt(T[Idx + 12 + K]));
            for K := 0 to 2 do E.Condition.Center[K] := SmallInt(StrToInt(T[Idx + 15 + K]));
            Inc(Idx, 18);
          end;
        PML_HAPTIC_RAMP:
          begin
            ReadHeader(T, Idx, E.Ramp.Direction, E.Ramp.Length, E.Ramp.Delay, E.Ramp.Button, E.Ramp.Interval);
            E.Ramp.Start := SmallInt(StrToInt(T[Idx]));
            E.Ramp.End_ := SmallInt(StrToInt(T[Idx + 1]));
            E.Ramp.AttackLength := Word(StrToInt(T[Idx + 2]));
            E.Ramp.AttackLevel := Word(StrToInt(T[Idx + 3]));
            E.Ramp.FadeLength := Word(StrToInt(T[Idx + 4]));
            E.Ramp.FadeLevel := Word(StrToInt(T[Idx + 5]));
            Inc(Idx, 6);
          end;
        PML_HAPTIC_LEFTRIGHT:
          begin
            E.LeftRight.Length := Cardinal(StrToInt64(T[Idx]));
            E.LeftRight.LargeMagnitude := Word(StrToInt(T[Idx + 1]));
            E.LeftRight.SmallMagnitude := Word(StrToInt(T[Idx + 2]));
            Inc(Idx, 3);
          end;
      end;
      Expected := T[Idx] = '1';
      ExpectedHex := T[Idx + 1];
      if PMLHapticToFFEffect(FF, E, Err) = Expected then
      begin
        if (not Expected) or (Hex48(FF) = ExpectedHex) then
          Inc(Pass)
        else
        begin
          Inc(Fail);
          if Bad = '' then
            Bad := Format('行 %d 型 %d: papimela=%s SDL=%s', [Row, Typ, Hex48(FF), ExpectedHex]);
        end;
      end
      else
      begin
        Inc(Fail);
        if Bad = '' then
          Bad := Format('行 %d 型 %d: 変換の成否が違う（SDL=%s）', [Row, Typ, T[Idx]]);
      end;
      if Expected then
        Inc(OkCount);
    end;
    Check(Fail = 0, Format('変換 %d 場面が SDL と全バイト一致（成功 %d、失敗 %d）%s',
      [Pass, OkCount, Pass - OkCount, Bad]));
    Check(Pass >= 700, '場面の数が足りている（700 以上）');
    I := 0;
  finally
    T.Free;
  end;
end;

{ ---- 場面: axes（ヒントの軸の数） ---- }

function HexToStr(const AHex: String): String;
var
  I: Integer;
begin
  Result := '';
  if AHex = '-' then
    Exit;
  for I := 0 to Length(AHex) div 2 - 1 do
    Result := Result + Chr(StrToInt('$' + Copy(AHex, I * 2 + 1, 2)));
end;

procedure TestAxes;
var
  T: TStringList;
  Row, Pass, Fail, Got, Want: Integer;
  Bad, Hint: String;
begin
  WriteLn('axes: ヒントの軸の数が SDL_Haptic_Get_Naxes と一致するか（SDL_sscanf の癖を含む）');
  T := TStringList.Create;
  try
    Pass := 0;
    Fail := 0;
    Bad := '';
    for Row := 0 to High(HapticExpected) do
    begin
      if HapticExpected[Row][1] <> 'N' then
        Continue;
      SplitRow(HapticExpected[Row], T);
      Hint := HexToStr(T[1]);
      Want := StrToInt(T[4]);
      // SDL は Uint16 の 65534 のような値を返す（int）。papimela も同じ値
      Got := PMLHapticAxesFromHint(Hint, Word(StrToInt(T[2])), Word(StrToInt(T[3])));
      if Got = Want then
        Inc(Pass)
      else
      begin
        Inc(Fail);
        if Bad = '' then
          Bad := Format('ヒント "%s" vid=%s pid=%s: papimela=%d SDL=%d', [Hint, T[2], T[3], Got, Want]);
      end;
    end;
    Check(Fail = 0, Format('ヒント %d 場面が SDL と一致%s', [Pass, Bad]));
    Check(Pass >= 150, '場面の数が足りている（150 以上）');
  finally
    T.Free;
  end;
end;

{ ---- 場面: scan ---- }

procedure TestScan;
var
  IDs: TPMLHapticIDs;
  Kb, NoFF, Dup, Locked: TFakeDev;
  I: Integer;
begin
  WriteLn('scan: 初めの走査、能力、名前、ID');
  ClearDevices;
  AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  AddDev(RumblePad('/dev/input/event8', 108, 'Rumble Pad'));
  // FF の無い機器（キーボード）は一覧に入らない
  Kb := TFakeDev.Create('/dev/input/event1', 101);
  Kb.Name := 'Plain Keyboard';
  for I := 1 to 31 do
    Kb.SetKey(I);
  AddDev(Kb);
  // FF のビットは立っているが何も使えない機器も、能力が 0 なので入らない
  NoFF := TFakeDev.Create('/dev/input/event2', 102);
  NoFF.Name := 'FF Without Effects';
  SetBit(NoFF.EvBits, EV_FF);
  AddDev(NoFF);
  // 同じ機器番号（重複）は 1 つ
  Dup := Wheel('/dev/input/event30', 103, 'Force Wheel Again');
  AddDev(Dup);
  // 書き込みで開けない機器は入らない
  Locked := Wheel('/dev/input/event4', 104, 'Locked');
  Locked.DenyWrite := True;
  AddDev(Locked);
  // 32 番以上は走査の外（SDL は event0〜31 だけ試す）
  AddDev(Wheel('/dev/input/event32', 132, 'Far Away'));
  OpenContext([TPMLSubsystem.Haptic], []);
  try
    IDs := Ctx.Haptics.Haptics;
    Check(Length(IDs) = 2, '機器は 2 台（FF の無いもの・書き込めないもの・32 番以上は入らず、重複は 1 つ）: ' + IntToStr(Length(IDs)));
    if Length(IDs) = 2 then
    begin
          Check((IDs[0] <> 0) and (IDs[1] <> 0) and (IDs[0] <> IDs[1]), 'ID は 0 でなく、すべて違う');
      Check(Ctx.Haptics.NameForID(IDs[0]) = 'Force Wheel', '1 台目の名前: ' + Ctx.Haptics.NameForID(IDs[0]));
      Check(Ctx.Haptics.NameForID(IDs[1]) = 'Rumble Pad', '2 台目の名前: ' + Ctx.Haptics.NameForID(IDs[1]));
    end;
    Check(Ctx.Haptics.NameForID(0) = '', 'ID 0 は名前が無い');
    Check(Ctx.Haptics.NameForID(99999) = '', '無い ID は名前が無い');
    Check(FindDev('/dev/input/event3').Opens = 0, '走査で開いた機器は閉じてある');
    Check(HapHost.UdevAsked, 'udev を使う（コンテナの外）');
    Check(Ctx.Haptics.BackendName = 'linux', 'バックエンドの名前は linux');
  finally
    CloseContext;
  end;
  // 名前の無い機器は、パスを名前にする（SDL は EVIOCGNAME が取れなければ機器のパス）
  ClearDevices;
  NoFF := Wheel('/dev/input/event5', 105, '');
  AddDev(NoFF);
  OpenContext([TPMLSubsystem.Haptic], []);
  try
    Check(Ctx.Haptics.NameForID(FirstID) = '/dev/input/event5', '名前が取れない機器はパスを名前にする');
  finally
    CloseContext;
  end;
end;

{ ---- 場面: open ---- }

procedure TestOpen;
var
  H, H2: TPMLHaptic;
  D: TFakeDev;
  ID: TPMLHapticID;
  Raised: Boolean;
begin
  WriteLn('open: 開く・閉じる、回数、開いた直後の既定');
  ClearDevices;
  D := AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  OpenContext([TPMLSubsystem.Haptic], []);
  try
    ID := FirstID;
    H := Ctx.Haptics.Open(ID);
    Check(H <> nil, '開ける');
    Check(H.ID = ID, 'ID は機器の ID');
    Check(H.Name = 'Force Wheel', '名前: ' + H.Name);
    Check(H.MaxEffects = 16, '効果の数は EVIOCGEFFECTS: ' + IntToStr(H.MaxEffects));
    Check(H.MaxEffectsPlaying = 16, '同時に鳴らせる数も同じ（Linux は区別しない）');
    Check(H.NumAxes = 2, '軸は 2 つ');
    Check(H.Features = (PML_HAPTIC_CONSTANT or PML_HAPTIC_SINE or PML_HAPTIC_SQUARE or PML_HAPTIC_TRIANGLE or
      PML_HAPTIC_SAWTOOTHUP or PML_HAPTIC_SAWTOOTHDOWN or PML_HAPTIC_RAMP or PML_HAPTIC_SPRING or
      PML_HAPTIC_FRICTION or PML_HAPTIC_DAMPER or PML_HAPTIC_INERTIA or PML_HAPTIC_GAIN or
      PML_HAPTIC_AUTOCENTER or PML_HAPTIC_LEFTRIGHT), '能力は FF のビットの写し: ' + IntToHex(H.Features, 8));
    Check(LogText(D) = 'gain=65535;autocenter=0', '開いた直後に、ゲインを最大にしてオートセンタを切る: ' + LogText(D));
    Check(D.Opens = 1, '機器を 1 つ開いている');
    // 同じ ID は同じオブジェクト
    H2 := Ctx.Haptics.Open(ID);
    Check(H2 = H, '同じ ID は同じオブジェクト');
    Check(Ctx.Haptics.FromID(ID) = H, 'FromID は開いている機器を返す');
    Check(D.Opens = 1, '2 度目の Open は機器を開き直さない');
    H2.Close;
    Check(Ctx.Haptics.FromID(ID) = H, 'Close が 1 回では壊れない');
    Check(D.Opens = 1, 'まだ開いている');
    H.Close;
    Check(Ctx.Haptics.FromID(ID) = nil, 'Open の回数だけ Close すると閉じる');
    Check(D.Opens = 0, '機器を閉じた');
    // 開き直せる
    H := Ctx.Haptics.Open(ID);
    Check(H <> nil, '閉じた後でも開き直せる');
    // 無い ID は断る
    Raised := False;
    try
      Ctx.Haptics.Open(4242);
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    Check(Raised, '無い ID は EPMLArgument');
    Raised := False;
    try
      Ctx.Haptics.Open(0);
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    Check(Raised, 'ID 0 は EPMLArgument');
    // 開いたままの機器は、Context を壊すときに閉じる
    Check(Ctx.Haptics.FromID(ID) = H, '開いたままにしておく（Context が閉じる）');
  finally
    CloseContext;
  end;
  Check(D.Opens = 0, 'Context を壊すと、開いたままの機器も閉じる');
  // 効果の数が聞けない機器は開けない
  ClearDevices;
  D := AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  OpenContext([TPMLSubsystem.Haptic], []);
  try
    D.CapacityFails := True;
    Raised := False;
    try
      Ctx.Haptics.Open(FirstID);
    except
      on E: EPMLInputError do
        Raised := Pos('Unable to query device memory', E.Message) > 0;
    end;
    Check(Raised, '効果の数が聞けない機器は、理由つきで EPMLInputError');
    Check(D.Opens = 0, '開けなかった機器は閉じてある');
  finally
    CloseContext;
  end;
end;

{ ---- 場面: effects ---- }

procedure TestEffects;
var
  H: TPMLHaptic;
  D: TFakeDev;
  A, B, C: TPMLHapticEffectID;
  E: TPMLHapticEffect;
  I: Integer;
  Raised: Boolean;
  Msg: String;
begin
  WriteLn('effects: 作る・更新・再生・止める・消す');
  ClearDevices;
  D := AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  OpenContext([TPMLSubsystem.Haptic], []);
  try
    H := Ctx.Haptics.Open(FirstID);
    D.Log.Clear;
    Check(H.EffectSupported(Constant_(1000, 100)), '一定の力は使える');
    E := LeftRight_(100, 1, 1);
    Check(H.EffectSupported(E), '左右は使える');
    FillChar(E, SizeOf(E), 0);
    E.EffectType := PML_HAPTIC_CUSTOM;
    Check(not H.EffectSupported(E), '波形の指定は使えない（機器が FF_CUSTOM を持たない）');
    A := H.CreateEffect(Constant_(1000, 100));
    B := H.CreateEffect(Sine_(2000, 500));
    Check((A = 0) and (B = 1), '番号は 0 から空きの順: ' + IntToStr(A) + ',' + IntToStr(B));
    Check(LogText(D) = 'upload id=0 type=' + IntToStr(FF_CONSTANT) + ';upload id=1 type=' + IntToStr(FF_PERIODIC),
      '機器へ効果を上げる: ' + LogText(D));
    Check(D.Effects[0].ConstantLevel = 100, '一定の力のレベルが写る');
    Check(D.Effects[1].PeriodicMagnitude = 500, '周期の大きさが写る');
    // 種類は変えられない
    Check(not H.UpdateEffect(A, Sine_(10, 10)), '種類を変える更新は断る');
    Check(H.LastError = 'Haptic: Updating effect type is illegal.', '理由: ' + H.LastError);
    // 更新
    D.Log.Clear;
    Check(H.UpdateEffect(A, Constant_(3000, 7)), '同じ種類の更新はできる');
    Check(LogText(D) = 'upload id=0 type=' + IntToStr(FF_CONSTANT), '更新は同じ番号で上げ直す: ' + LogText(D));
    Check(D.Effects[0].ConstantLevel = 7, '更新の中身が写る');
    Check(H.EffectSpec(A).Constant.Level = 7, '更新した効果の記録（EffectSpec）が新しい中身になる');
    Check(H.EffectSpec(B).Periodic.Magnitude = 500, '作った効果の記録（EffectSpec）は作ったときの中身');
    // 再生・停止
    D.Log.Clear;
    Check(H.RunEffect(A, 3), '再生');
    Check(H.RunEffect(A, PML_HAPTIC_INFINITY), '無限の再生');
    Check(H.StopEffect(A), '停止');
    Check(LogText(D) = 'ff id=0 value=3;ff id=0 value=2147483647;ff id=0 value=0',
      '回数 3、無限は INT_MAX、停止は 0: ' + LogText(D));
    D.Log.Clear;
    H.RunEffect(A, 5000);
    H.RunEffect(A, 2147483647);
    H.RunEffect(A, 2147483648);
    Check(LogText(D) = 'ff id=0 value=5000;ff id=0 value=2147483647;ff id=0 value=2147483647',
      'INT_MAX までの回数はそのまま、超えたら INT_MAX: ' + LogText(D));
    // 番号の違反
    Check(not H.RunEffect(-1, 1), '負の番号は断る');
    Check(H.LastError = 'Haptic: Invalid effect identifier.', '理由: ' + H.LastError);
    Check(not H.RunEffect(16, 1), '範囲の外の番号は断る');
    Check(not H.UpdateEffect(99, Constant_(1, 1)), '範囲の外の更新は断る');
    Check(not H.StopEffect(99), '範囲の外の停止は断る');
    H.DestroyEffect(99);
    // 作っていない番号（SDL は Linux でヌルを辿って落ちる）
    Check(not H.RunEffect(5, 1), '作っていない番号の再生は断る（落ちない）');
    Check(not H.StopEffect(5), '作っていない番号の停止は断る（落ちない）');
    Check(not H.UpdateEffect(5, Constant_(1, 1)), '作っていない番号の更新は断る（落ちない）');
    // 消す
    D.Log.Clear;
    H.DestroyEffect(A);
    Check(LogText(D) = 'remove id=0', '消すと機器からも外す: ' + LogText(D));
    Check(not H.RunEffect(A, 1), '消した番号は使えない');
    Check(not H.UpdateEffect(A, Constant_(1, 1)), '消した番号の更新も断る（落ちない）');
    Check(not H.StopEffect(A), '消した番号の停止も断る');
    H.DestroyEffect(A);
    Check(LogText(D) = 'remove id=0', '2 度消しても何もしない');
    C := H.CreateEffect(Constant_(1, 1));
    Check(C = 0, '消した番号が空いてまた使われる');
    // 作れない種類
    Raised := False;
    try
      H.CreateEffect(E);
    except
      on Ex: EPMLInputError do
      begin
        Raised := True;
        Msg := Ex.Message;
      end;
    end;
    Check(Raised and (Msg = 'Haptic: Effect not supported by haptic device.'), '使えない種類は EPMLInputError: ' + Msg);
    // 向きの種類が未知
    E := Constant_(100, 1);
    E.Constant.Direction.DirType := 9;
    Raised := False;
    try
      H.CreateEffect(E);
    except
      on Ex: EPMLInputError do
      begin
        Raised := True;
        Msg := Ex.Message;
      end;
    end;
    Check(Raised and (Msg = 'Haptic: Unsupported direction type.'), '向きの種類が未知なら断る: ' + Msg);
    // 機器が断る
    D.FailUploads := 1;
    Raised := False;
    try
      H.CreateEffect(Constant_(1, 1));
    except
      on Ex: EPMLInputError do
        Raised := Pos('Error uploading effect to the device', Ex.Message) > 0;
    end;
    Check(Raised, '機器が断ると、理由つきで EPMLInputError');
    D.FailUploads := 1;
    Check(not H.UpdateEffect(B, Sine_(1, 1)), '機器が断ると更新は False');
    Check(Pos('Error updating the effect', H.LastError) > 0, '理由: ' + H.LastError);
    Check(D.Effects[1].PeriodicMagnitude = 500, '断られた更新は、前の中身のまま');
    // 空きが無い
    for I := 1 to 14 do
      H.CreateEffect(Constant_(1, 1));
    Raised := False;
    try
      H.CreateEffect(Constant_(1, 1));
    except
      on Ex: EPMLInputError do
      begin
        Raised := True;
        Msg := Ex.Message;
      end;
    end;
    Check(Raised and (Msg = 'Haptic: Device has no free space left.'), '空きが無ければ断る: ' + Msg);
    // 閉じると効果を全部消す
    D.Log.Clear;
    H.Close;
    Check(Pos('remove id=0', LogText(D)) > 0, '閉じると作った効果を機器から消す');
    Check(D.Log.Count = 16, '16 個の効果をすべて消した: ' + IntToStr(D.Log.Count));
    Check(D.Opens = 0, '閉じた');
  finally
    CloseContext;
  end;
end;

{ ---- 場面: gain ---- }

procedure TestGain;
var
  H: TPMLHaptic;
  D: TFakeDev;
  E: TPMLHapticEffect;
begin
  WriteLn('gain: ゲイン・オートセンタ・一時停止・状態');
  ClearDevices;
  D := AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  OpenContext([TPMLSubsystem.Haptic], []);
  try
    H := Ctx.Haptics.Open(FirstID);
    D.Log.Clear;
    Check(H.SetGain(50), 'ゲイン 50');
    Check(H.SetGain(0), 'ゲイン 0');
    Check(H.SetGain(100), 'ゲイン 100');
    Check(LogText(D) = 'gain=32767;gain=0;gain=65535', '0〜100 を 0〜0xFFFF に伸ばす: ' + LogText(D));
    Check(not H.SetGain(-1), 'ゲインが負なら断る');
    Check(H.LastError = 'Haptic: Gain must be between 0 and 100.', '理由: ' + H.LastError);
    Check(not H.SetGain(101), 'ゲインが 101 なら断る');
    D.Log.Clear;
    Check(H.SetAutocenter(100), 'オートセンタ 100');
    Check(LogText(D) = 'autocenter=65535', 'オートセンタも伸ばす: ' + LogText(D));
    Check(not H.SetAutocenter(101), 'オートセンタが範囲の外なら断る');
    Check(H.LastError = 'Haptic: Autocenter must be between 0 and 100.', '理由: ' + H.LastError);
    Check(not H.Pause, '一時停止は Linux では断る（能力が無い）');
    Check(H.LastError = 'Haptic: Device does not support setting pausing.', '理由: ' + H.LastError);
    Check(H.Resume, '再開は、一時停止できない機器では成功したことにする');
    Check(not H.GetEffectStatus(0), '状態の問い合わせは断る（能力が無い）');
    Check(H.LastError = 'Haptic: Device does not support status queries.', '理由: ' + H.LastError);
    // 全部を止める
    H.CreateEffect(Constant_(1, 1));
    H.CreateEffect(Sine_(1, 1));
    D.Log.Clear;
    Check(H.StopEffects, '全部止める');
    Check(LogText(D) = 'ff id=0 value=0;ff id=1 value=0', '作った効果を 1 つずつ止める: ' + LogText(D));
    D.FailWrites := True;
    Check(not H.StopEffects, '止められなければ False');
    Check(H.LastError = 'Haptic: Error while trying to stop all playing effects.', '理由: ' + H.LastError);
    Check(not H.SetGain(10), '書き込めなければゲインは False');
    Check(Pos('Error setting gain', H.LastError) > 0, '理由: ' + H.LastError);
    D.FailWrites := False;
    // 能力の無い機器
    H.Close;
  finally
    CloseContext;
  end;
  // ゲインもオートセンタも持たない機器
  ClearDevices;
  D := AddDev(RumblePad('/dev/input/event3', 103, 'Rumble Pad'));
  OpenContext([TPMLSubsystem.Haptic], []);
  try
    H := Ctx.Haptics.Open(FirstID);
    Check(D.Log.Count = 0, 'ゲインもオートセンタも持たない機器は、開いても書かない');
    Check(not H.SetGain(10), 'ゲインが無い機器は断る');
    Check(H.LastError = 'Haptic: Device does not support setting gain.', '理由: ' + H.LastError);
    Check(not H.SetAutocenter(10), 'オートセンタが無い機器は断る');
    Check(H.LastError = 'Haptic: Device does not support setting autocenter.', '理由: ' + H.LastError);
    FillChar(E, SizeOf(E), 0);
    E.EffectType := PML_HAPTIC_CONSTANT;
    Check(not H.EffectSupported(E), '左右だけの機器は一定の力を持たない');
  finally
    CloseContext;
  end;
  // ヒントでゲインの最大を絞る
  ClearDevices;
  D := AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  OpenContext([TPMLSubsystem.Haptic], [PML_HINT_HAPTIC_GAIN_MAX, '50']);
  try
    H := Ctx.Haptics.Open(FirstID);
    Check(LogText(D) = 'gain=32767;autocenter=0', '開いた直後のゲイン 100 も絞られる（50%）: ' + LogText(D));
    D.Log.Clear;
    H.SetGain(100);
    H.SetGain(50);
    H.SetGain(0);
    Check(LogText(D) = 'gain=32767;gain=16383;gain=0', '最大 50 のとき、線形に縮める: ' + LogText(D));
    H.Close;
  finally
    CloseContext;
  end;
  ClearDevices;
  D := AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  OpenContext([TPMLSubsystem.Haptic], [PML_HINT_HAPTIC_GAIN_MAX, '500']);
  try
    H := Ctx.Haptics.Open(FirstID);
    Check(LogText(D) = 'gain=65535;autocenter=0', '最大が 100 を超えれば 100 に収める');
    H.Close;
  finally
    CloseContext;
  end;
  ClearDevices;
  D := AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  OpenContext([TPMLSubsystem.Haptic], [PML_HINT_HAPTIC_GAIN_MAX, '-5']);
  try
    H := Ctx.Haptics.Open(FirstID);
    Check(LogText(D) = 'gain=0;autocenter=0', '最大が負なら 0 に収める（ゲイン 0）');
    H.Close;
  finally
    CloseContext;
  end;
  ClearDevices;
  D := AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  OpenContext([TPMLSubsystem.Haptic], [PML_HINT_HAPTIC_GAIN_MAX, 'abc']);
  try
    H := Ctx.Haptics.Open(FirstID);
    Check(LogText(D) = 'gain=0;autocenter=0', '数でない最大は atoi で 0（ゲイン 0）');
    H.Close;
  finally
    CloseContext;
  end;
end;

{ ---- 場面: rumble ---- }

procedure TestRumble;
var
  H: TPMLHaptic;
  D: TFakeDev;
begin
  WriteLn('rumble: 簡易ランブル');
  ClearDevices;
  D := AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  OpenContext([TPMLSubsystem.Haptic], []);
  try
    H := Ctx.Haptics.Open(FirstID);
    Check(H.RumbleSupported, 'サインがあればランブルできる');
    Check(not H.PlayRumble(0.5, 100), '初期化の前は再生できない');
    Check(H.LastError = 'Haptic: Rumble effect not initialized on haptic device', '理由: ' + H.LastError);
    Check(not H.StopRumble, '初期化の前は止められない');
    D.Log.Clear;
    Check(H.InitRumble, '初期化');
    Check(H.InitRumble, '2 度目は何もしない');
    Check(LogText(D) = 'upload id=0 type=' + IntToStr(FF_PERIODIC), '周期の効果（サイン）を 1 つだけ作る: ' + LogText(D));
    Check(D.Effects[0].PeriodicWaveform = FF_SINE, '波形はサイン');
    Check(D.Effects[0].PeriodicPeriod = 1000, '周期 1000');
    Check(D.Effects[0].PeriodicMagnitude = $4000, '大きさ 0x4000');
    Check(D.Effects[0].Direction = $4000, '向きは CARTESIAN の (0, 0) → 0x4000');
    D.Log.Clear;
    Check(H.PlayRumble(0.5, 250), '再生 0.5・250 ms');
    Check(D.Effects[0].PeriodicMagnitude = 16383, '大きさ 32767 * 0.5 の切り捨て: ' + IntToStr(D.Effects[0].PeriodicMagnitude));
    Check(D.Effects[0].ReplayLength = 250, '長さ 250');
    Check(LogText(D) = 'upload id=0 type=' + IntToStr(FF_PERIODIC) + ';ff id=0 value=1', '更新して 1 回再生: ' + LogText(D));
    Check(H.PlayRumble(2.0, 100), '強さは 1.0 に収める');
    Check(D.Effects[0].PeriodicMagnitude = 32767, '1.0 は 32767');
    Check(H.PlayRumble(-1.0, 100), '強さは 0.0 に収める');
    Check(D.Effects[0].PeriodicMagnitude = 0, '0.0 は 0');
    D.Log.Clear;
    Check(H.StopRumble, '止める');
    Check(LogText(D) = 'ff id=0 value=0', '停止: ' + LogText(D));
    H.Close;
  finally
    CloseContext;
  end;
  // 左右だけの機器
  ClearDevices;
  D := AddDev(RumblePad('/dev/input/event3', 103, 'Rumble Pad'));
  OpenContext([TPMLSubsystem.Haptic], []);
  try
    H := Ctx.Haptics.Open(FirstID);
    Check(H.RumbleSupported, '左右があればランブルできる');
    Check(H.InitRumble, '初期化');
    Check(D.Effects[0].EffectType = FF_RUMBLE, '左右の効果');
    Check((D.Effects[0].RumbleStrong = $8000) and (D.Effects[0].RumbleWeak = $8000),
      '初期の大きさ 0x4000 は、Linux の 0〜65535 で 0x8000: ' + IntToHex(D.Effects[0].RumbleStrong, 4));
    Check(H.PlayRumble(1.0, 100), '再生');
    Check((D.Effects[0].RumbleStrong = 65534) and (D.Effects[0].RumbleWeak = 65534),
      '1.0 は 32767 * 2 = 65534: ' + IntToStr(D.Effects[0].RumbleStrong));
    Check(D.Effects[0].ReplayLength = 100, '長さ 100');
    H.Close;
  finally
    CloseContext;
  end;
  // ランブルの無い機器
  ClearDevices;
  D := AddDev(TFakeDev.Create('/dev/input/event3', 103));
  D.Name := 'Constant Only';
  D.SetFF(FF_CONSTANT);
  OpenContext([TPMLSubsystem.Haptic], []);
  try
    H := Ctx.Haptics.Open(FirstID);
    Check(not H.RumbleSupported, 'サインも左右も無ければランブルできない');
    Check(not H.InitRumble, '初期化は断る');
    Check(H.LastError = 'Device doesn''t support rumble', '理由: ' + H.LastError);
    H.Close;
  finally
    CloseContext;
  end;
end;

{ ---- 場面: mouse ---- }

procedure TestMouse;
var
  H: TPMLHaptic;
  Raised: Boolean;
begin
  WriteLn('mouse: マウスの機器');
  ClearDevices;
  AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  OpenContext([TPMLSubsystem.Haptic], []);
  try
    Check(not Ctx.Haptics.IsMouseHaptic, 'BTN_MOUSE の無い機器はマウスではない（SDL は何でも true）');
    Raised := False;
    try
      Ctx.Haptics.OpenFromMouse;
    except
      on E: EPMLInputError do
        Raised := E.Message = 'Haptic: Mouse isn''t a haptic device.';
    end;
    Check(Raised, 'マウスが無ければ EPMLInputError');
  finally
    CloseContext;
  end;
  ClearDevices;
  AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  AddDev(Mouse('/dev/input/event6', 106));
  OpenContext([TPMLSubsystem.Haptic], []);
  try
    Check(Ctx.Haptics.IsMouseHaptic, 'BTN_MOUSE を持つ機器があればマウス');
    H := Ctx.Haptics.OpenFromMouse;
    Check(H.Name = 'Force Mouse', 'マウスを開ける（添字でなく ID で開く）: ' + H.Name);
    H.Close;
  finally
    CloseContext;
  end;
end;

{ ---- 場面: joystick ---- }

procedure TestJoystick;
var
  JIDs: TPMLJoystickIDs;
  J, JPad: TPMLJoystick;
  H, H2: TPMLHaptic;
  I: Integer;
  Raised: Boolean;
  Wh, Pad: TFakeDev;
  Desc: TPMLVirtualJoystickDesc;
  VJ: TPMLJoystick;
begin
  WriteLn('joystick: ジョイスティックから開く');
  ClearDevices;
  Wh := AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  Pad := AddDev(RumblePad('/dev/input/event8', 108, 'Rumble Pad'));
  OpenContext([TPMLSubsystem.Joystick, TPMLSubsystem.Gamepad, TPMLSubsystem.Haptic], []);
  try
    JIDs := Ctx.Joysticks.Joysticks;
    Check(Length(JIDs) = 2, 'ジョイスティックは 2 台: ' + IntToStr(Length(JIDs)));
    J := nil;
    JPad := nil;
    for I := 0 to High(JIDs) do
      if Ctx.Joysticks.NameForID(JIDs[I]) = 'Force Wheel' then
        J := Ctx.Joysticks.Open(JIDs[I])
      else
        JPad := Ctx.Joysticks.Open(JIDs[I]);
    Check((J <> nil) and (JPad <> nil), 'どちらも開ける');
    Check(not Ctx.Joysticks.IsGamepad(J.ID), 'ハンドルはゲームパッドではない');
    Check(Ctx.Joysticks.IsGamepad(JPad.ID), 'パッドはゲームパッド');
    Check(Ctx.Haptics.IsJoystickHaptic(J), 'ハンドルはハプティクスを持つ');
    Check(not Ctx.Haptics.IsJoystickHaptic(JPad), 'ゲームパッドはハプティクスとして開けない（SDL3）');
    Check(not Ctx.Haptics.IsJoystickHaptic(nil), 'nil は断る');
    Raised := False;
    try
      Ctx.Haptics.OpenFromJoystick(JPad);
    except
      on E: EPMLInputError do
        Raised := E.Message = 'Haptic: Joystick isn''t a haptic device.';
    end;
    Check(Raised, 'ゲームパッドから開くと EPMLInputError');
    H := Ctx.Haptics.OpenFromJoystick(J);
    Check(H <> nil, 'ハンドルから開ける');
    Check(H.Name = 'Force Wheel', '名前は機器の名前: ' + H.Name);
    Check(H.ID <> 0, 'ID は 0 でない（一覧の ID と同じ）');
    Check(H.ID = FirstID, '一覧の ID と同じ');
    Check(H.NumAxes = 2, '軸の数は 2');
    Check(Wh.Opens = 2, '機器を開いている（ジョイスティックの分と力覚の分）: ' + IntToStr(Wh.Opens));
    H2 := Ctx.Haptics.OpenFromJoystick(J);
    Check(H2 = H, '同じ機器は同じオブジェクト');
    H2.Close;
    H2 := Ctx.Haptics.Open(H.ID);
    Check(H2 = H, 'ID から開いても同じオブジェクト');
    H2.Close;
    H.Close;
    Check(Ctx.Haptics.FromID(H.ID) = nil, 'Close の回数だけ閉じると閉じる');
    // 他のバックエンドのジョイスティック（仮想）は力覚を持たない
    Desc := Default(TPMLVirtualJoystickDesc);
    Desc.JoystickType := TPMLJoystickType.Unknown;
    Desc.Name := 'Virtual Stick';
    Desc.NumAxes := 2;
    Desc.NumButtons := 2;
    VJ := Ctx.Joysticks.Open(Ctx.Joysticks.AttachVirtual(Desc));
    Check(not Ctx.Haptics.IsJoystickHaptic(VJ), '仮想のジョイスティックは力覚を持たない');
    Raised := False;
    try
      Ctx.Haptics.OpenFromJoystick(VJ);
    except
      on E: EPMLInputError do
        Raised := True;
    end;
    Check(Raised, '仮想のジョイスティックから開くと EPMLInputError');
    Check(Ctx.Joysticks.OpenCount = 3, 'ジョイスティックの開いた数は 3（2 台と仮想）');
  finally
    CloseContext;
  end;
  // 力覚の一覧に無い機器（走査のときは FF のビットが無かった）を、ジョイスティックから開く
  ClearDevices;
  Wh := AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  FillChar(Wh.FFBits[0], Length(Wh.FFBits), 0);
  OpenContext([TPMLSubsystem.Joystick, TPMLSubsystem.Haptic], []);
  try
    Check(Length(Ctx.Haptics.Haptics) = 0, 'FF の無い間は力覚の一覧は空');
    JIDs := Ctx.Joysticks.Joysticks;
    J := Ctx.Joysticks.Open(JIDs[0]);
    Check(not Ctx.Haptics.IsJoystickHaptic(J), 'FF の無い機器は力覚を持たない');
    Wh.SetFF(FF_CONSTANT); Wh.SetFF(FF_SINE);
    Check(Ctx.Haptics.IsJoystickHaptic(J), 'FF が使えるようになれば持つ');
    H := Ctx.Haptics.OpenFromJoystick(J);
    Check(H.ID <> 0, '一覧に無い機器でも ID は 0 でない（足してから開く）');
    Check((Length(Ctx.Haptics.Haptics) = 1) and (Ctx.Haptics.Haptics[0] = H.ID), '開くと一覧にも載る');
    H.Close;
  finally
    CloseContext;
  end;
  // ヒントの軸の数
  ClearDevices;
  Wh := AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  OpenContext([TPMLSubsystem.Joystick, TPMLSubsystem.Haptic],
    [PML_HINT_JOYSTICK_HAPTIC_AXES, '0xffff/0xffff/1']);
  try
    JIDs := Ctx.Joysticks.Joysticks;
    J := Ctx.Joysticks.Open(JIDs[0]);
    H := Ctx.Haptics.OpenFromJoystick(J);
    Check(H.NumAxes = 1, 'ヒントで軸を 1 つにできる（全部の機器）: ' + IntToStr(H.NumAxes));
    H.Close;
  finally
    CloseContext;
  end;
  ClearDevices;
  Wh := AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  OpenContext([TPMLSubsystem.Joystick, TPMLSubsystem.Haptic],
    [PML_HINT_JOYSTICK_HAPTIC_AXES, '0x1234/0x0067/5']);
  try
    JIDs := Ctx.Joysticks.Joysticks;
    J := Ctx.Joysticks.Open(JIDs[0]);
    H := Ctx.Haptics.OpenFromJoystick(J);
    // Wheel は 2 つの軸（ABS_X・ABS_Y）しか持たないので、本当の軸の数に収める
    Check(H.NumAxes = J.NumAxes, 'ヒントの軸の数は、機器の本当の軸の数を超えない: ' + IntToStr(H.NumAxes) + '/' + IntToStr(J.NumAxes));
    H.Close;
  finally
    CloseContext;
  end;
end;

{ ---- 場面: hotplug ---- }

procedure TestHotplug;
var
  IDs: TPMLHapticIDs;
  H: TPMLHaptic;
  D, New_: TFakeDev;
begin
  WriteLn('hotplug: 抜き差し');
  UdevMode := TPMLHotplugMethod.Udev;
  try
    ClearDevices;
    D := AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
    OpenContext([TPMLSubsystem.Haptic], []);
    try
      Check(HapHost.Method = TPMLHotplugMethod.Udev, 'udev で見張る');
      Check(HapHost.ScanCount = 1, '初めに今ある機器を通知させる');
      Check(Length(Ctx.Haptics.Haptics) = 1, '走査と udev の通知で重複しない（機器番号で飛ばす）');
      // 新しい機器が足される
      New_ := AddDev(RumblePad('/dev/input/event9', 109, 'Rumble Pad'));
      HapHost.Fire(True, PML_UDEV_DEVICE_JOYSTICK, '/dev/input/event9');
      IDs := Ctx.Haptics.Haptics;
      Check(Length(IDs) = 2, '足された機器が一覧に出る（一覧を引くときに通知を受け取る）');
      // JOYSTICK でない機器の通知は無視する
      AddDev(Wheel('/dev/input/event10', 110, 'Keyboard-like'));
      HapHost.Fire(True, PML_UDEV_DEVICE_KEYBOARD, '/dev/input/event10');
      Check(Length(Ctx.Haptics.Haptics) = 2, 'JOYSTICK の種類でない通知は無視する');
      // 外れる
      H := Ctx.Haptics.Open(IDs[1]);
      HapHost.Fire(False, PML_UDEV_DEVICE_JOYSTICK, '/dev/input/event9');
      Check(Length(Ctx.Haptics.Haptics) = 1, '外れた機器は一覧から消える');
      Check(Ctx.Haptics.FromID(IDs[1]) = H, '開いている機器は外れても残る（SDL と同じ）');
      H.Close;
      Check(Ctx.Haptics.NameForID(IDs[1]) = '', '外れた機器の名前は引けない');
      // 外れた機器は、また足される
      HapHost.Fire(True, PML_UDEV_DEVICE_JOYSTICK, '/dev/input/event9');
      Check(Length(Ctx.Haptics.Haptics) = 2, '外れた機器がまた足される');
      Check(Ctx.Haptics.Haptics[1] <> IDs[1], '足し直した機器は新しい ID');
    finally
      CloseContext;
    end;
    Check(HapHost = nil, '（窓口は壊れた）');
    // コンテナの中では udev を使わず、inotify で見張る。通知は event の機器を全部足す（種類を持たない）
    ClearDevices;
    AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
    SandboxMode := True;
    OpenContext([TPMLSubsystem.Haptic], []);
    try
      Check(not HapHost.UdevAsked, 'コンテナの中では udev を使わない');
      Check(HapHost.Method = TPMLHotplugMethod.Inotify, 'inotify で見張る');
      Check(HapHost.ScanCount = 0, 'inotify では今ある機器を通知させない（走査で足してある）');
      AddDev(RumblePad('/dev/input/event9', 109, 'Rumble Pad'));
      HapHost.Fire(True, -1, '/dev/input/event9');
      Check(Length(Ctx.Haptics.Haptics) = 2, 'inotify の通知で足される（種類は問わない）');
      AddDev(Wheel('/dev/input/mouse0', 190, 'Not An Event'));
      HapHost.Fire(True, -1, '/dev/input/mouse0');
      Check(Length(Ctx.Haptics.Haptics) = 2, 'event の機器でない名前は足さない');
      HapHost.Fire(False, -1, '/dev/input/event9');
      Check(Length(Ctx.Haptics.Haptics) = 1, 'inotify の通知で外れる');
    finally
      CloseContext;
      SandboxMode := False;
    end;
  finally
    UdevMode := TPMLHotplugMethod.None;
    SandboxMode := False;
  end;
end;

{ ---- 場面: context ---- }

procedure TestContext;
var
  Raised: Boolean;
  Names: TStringArray;
begin
  WriteLn('context: Context への組み込みと登録');
  ClearDevices;
  AddDev(Wheel('/dev/input/event3', 103, 'Force Wheel'));
  OpenContext([TPMLSubsystem.Haptic], []);
  try
    Check(Ctx.Haptics <> nil, 'Haptic を要求すれば Haptics がある');
    Check(Ctx.Joysticks = nil, 'ジョイスティックは作らない');
  finally
    CloseContext;
  end;
  OpenContext([TPMLSubsystem.Joystick], []);
  try
    Check(Ctx.Haptics = nil, 'Haptic を要求しなければ Haptics は nil');
  finally
    CloseContext;
  end;
  Names := PMLHapticBackendNames;
  Check((Length(Names) = 1) and (Names[0] = 'linux'), '登録されたバックエンドは linux だけ');
  Check(PMLFindHapticBackend('LINUX') <> nil, '名前は大文字小文字を区別しない');
  Check(PMLFindHapticBackend('none') = nil, '登録の無い名前は nil');
  Raised := False;
  try
    PMLRegisterHapticBackend('linux', 0, PMLFindHapticBackend('linux'));
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, '同じ名前を 2 度登録すると EPMLArgument');
  // 機器の無い環境（/dev/input の機器が無い）でも始まる
  ClearDevices;
  OpenContext([TPMLSubsystem.Haptic], []);
  try
    Check(Length(Ctx.Haptics.Haptics) = 0, '機器が無くても始まり、一覧は空');
  finally
    CloseContext;
  end;
  // 実機の窓口（既定）で始まる。機器の数は環境で違うので数えるだけ
  PMLLinuxHapticHostFactory := nil;
  PMLLinuxJoystickHostFactory := nil;
  Ctx := TPMLContext.Create([TPMLSubsystem.Haptic]);
  try
    Check(Length(Ctx.Haptics.Haptics) >= 0, '実機の /dev/input で始まる（機器 ' + IntToStr(Length(Ctx.Haptics.Haptics)) + ' 台）');
  finally
    FreeAndNil(Ctx);
  end;
end;

begin
  Devices := TList.Create;
  try
    WriteLn('=== test_haptic ===');
    TestConvert;
    TestAxes;
    TestScan;
    TestOpen;
    TestEffects;
    TestGain;
    TestRumble;
    TestMouse;
    TestJoystick;
    TestHotplug;
    TestContext;
  finally
    ClearDevices;
    Devices.Free;
  end;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: ハプティクスが期待どおり動く ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
