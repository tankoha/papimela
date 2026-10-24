{
  PaPiMeLa.Haptic.Linux — Linux（evdev の力覚 FF）のハプティクス

  Origin : ported from SDL (src/haptic/linux/SDL_syshaptic.c)
           Scope: SDL_SYS_HapticInit（/dev/input/event0〜31 の走査と、udev の抜き差し）、EV_IsHaptic（FF のビットから
           能力へ）、EV_IsMouse、SDL_SYS_HapticOpen / OpenFromJoystick / Close / Mouse、JoystickIsHaptic /
           JoystickSameHaptic、SDL_SYS_ToDirection / ToButton / ToFFEffect（SDL の効果から ff_effect への変換）、
           NewEffect / UpdateEffect / RunEffect / StopEffect / DestroyEffect、SetGain / SetAutocenter、
           StopAll、Pause / Resume / GetEffectStatus（Linux は非対応）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #63

  WHAT:
    /dev/input/event* の FF 対応機器を、ハプティクスのバックエンド（TPMLHapticBackend）として見せる。
    機器への触り方は PaPiMeLa.Joystick.Linux.Node の抽象（TPMLEvdevHost・TPMLEvdevNode）を通す。
    本物は既定で使い、検査は偽物（PMLLinuxHapticHostFactory で差し込む）を使う。

  RESOLVED:
    - 初めの走査は SDL と同じに event0〜31 を全部試す（キーボードなど FF を持たない機器は捨てる）。
      抜き差しの通知（udev）は JOYSTICK の種類の機器だけを足す。inotify が使われたときは event の機器を全部足す
    - SDL_SYS_HapticMouse（D-84）: EV_IsMouse は SDL では何を調べても true を返す（BTN_MOUSE を調べた後に return true）。
      papimela は BTN_MOUSE を持つ機器だけをマウスとみなす。機器が開けないとき SDL は添字 0（SDL_SetError の戻り値の
      false）を返すが、papimela は -1 を返す
    - ジョイスティックから開くとき、その機器がまだ一覧に無ければ足してから開く（SDL は ID 0 のまま開く）
    - 向きの変換は SDL の整数の演算（符号なしの回り込みを含む）のまま。CARTESIAN の atan2f は
      単精度で行う

  NOT RESOLVED:
    - 旧 js の機器は扱わない（evdev の FF だけ）
    - FF_CUSTOM は変換できない（SDL も Unknown effect type で断る）
    - 一時停止・効果の状態の問い合わせは Linux の ABI に無い

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Haptic.Linux;

{$I papimela.inc}

interface

uses
  SysUtils, Classes, Math,
  PaPiMeLa.Joystick.Backend,
  PaPiMeLa.Haptic.Backend,
  PaPiMeLa.Platform.Evdev,
  PaPiMeLa.Joystick.Linux.Node;

type
  TPMLLinuxHapticHostFactory = function: TPMLEvdevHost;

var
  { 機器の窓口を作る工場。nil なら本物（/dev/input）。検査が偽物を差し込む。 }
  PMLLinuxHapticHostFactory: TPMLLinuxHapticHostFactory = nil;

{ SDL の効果を Linux の ff_effect にする（SDL_SYS_ToFFEffect）。変換できない効果は False で AError に理由。
  ID は 0 に初期化される（呼び出し側が -1 か既存の番号を置く）。検査が直接呼ぶ。 }
function PMLHapticToFFEffect(out ADest: TPMLFFEffect; const ASrc: TPMLHapticEffect;
  out AError: String): Boolean;

{ 向きの変換（SDL_SYS_ToDirection）。ADirType が未知なら False。 }
function PMLHapticToDirection(out ADest: Word; const ASrc: TPMLHapticDirection): Boolean;

implementation

const
  MAX_HAPTICS = 32;       // SDL_syshaptic.c の MAX_HAPTICS（初めに試す event の数）
  UNSUPPORTED = 'That operation is not supported';

type
  TLinuxHapticItem = class
  public
    InstanceID: TPMLHapticID;
    Path      : String;
    DevNum    : QWord;
  end;

  // 開いた機器（haptic_hwdata）
  THapticHw = class
  public
    Node: TPMLEvdevNode;
    Path: String;
    destructor Destroy; override;
  end;

  // 作った効果（haptic_hweffect）
  THapticHwEffect = class
  public
    Effect: TPMLFFEffect;
  end;

  TPMLLinuxHapticBackend = class sealed(TPMLHapticBackend)
  strict private
    FHost    : TPMLEvdevHost;
    FOwnsHost: Boolean;
    FItems   : array of TLinuxHapticItem;
    FMethod  : TPMLHotplugMethod;
    function  FindByDevNum(ADevNum: QWord): TLinuxHapticItem;
    function  FindByPath(const APath: String): TLinuxHapticItem;
    function  MaybeAddDevice(const APath: String): Boolean;
    procedure MaybeRemoveDevice(const APath: String);
    procedure OnHotplug(AKind: TPMLHotplugKind; AClass: Integer; const APath: String);
    function  OpenFromNode(AHaptic: TPMLHaptic; ANode: TPMLEvdevNode; const APath: String): Boolean;
    function  HwOf(AHaptic: TPMLHaptic): THapticHw;
    function  IsLinuxJoystick(AJoystick: TPMLJoystick): Boolean;
  public
    constructor Create(ACore: TPMLHapticCore);
    destructor Destroy; override;
    function  Name: String; override;
    function  Init: Boolean; override;
    procedure Quit; override;
    procedure Detect; override;
    function  DeviceCount: Integer; override;
    function  DeviceInstanceID(AIndex: Integer): TPMLHapticID; override;
    function  DeviceName(AIndex: Integer): String; override;
    function  Open(AHaptic: TPMLHaptic; AIndex: Integer): Boolean; override;
    function  MouseIndex: Integer; override;
    function  JoystickIsHaptic(AJoystick: TPMLJoystick): Boolean; override;
    function  JoystickSameHaptic(AHaptic: TPMLHaptic; AJoystick: TPMLJoystick): Boolean; override;
    function  OpenFromJoystick(AHaptic: TPMLHaptic; AJoystick: TPMLJoystick): Boolean; override;
    procedure Close(AHaptic: TPMLHaptic); override;
    function  NewEffect(AHaptic: TPMLHaptic; ASlot: Integer; const ABase: TPMLHapticEffect): Boolean; override;
    function  UpdateEffect(AHaptic: TPMLHaptic; ASlot: Integer; const AData: TPMLHapticEffect): Boolean; override;
    function  RunEffect(AHaptic: TPMLHaptic; ASlot: Integer; AIterations: Cardinal): Boolean; override;
    function  StopEffect(AHaptic: TPMLHaptic; ASlot: Integer): Boolean; override;
    procedure DestroyEffect(AHaptic: TPMLHaptic; ASlot: Integer); override;
    function  GetEffectStatus(AHaptic: TPMLHaptic; ASlot: Integer): Integer; override;
    function  SetGain(AHaptic: TPMLHaptic; AGain: Integer): Boolean; override;
    function  SetAutocenter(AHaptic: TPMLHaptic; AAutocenter: Integer): Boolean; override;
    function  Pause(AHaptic: TPMLHaptic): Boolean; override;
    function  Resume(AHaptic: TPMLHaptic): Boolean; override;
    function  StopAll(AHaptic: TPMLHaptic): Boolean; override;
  end;

destructor THapticHw.Destroy;
begin
  Node.Free;
  inherited Destroy;
end;

function IsEventNode(const APath: String): Boolean;
var
  N, Digits: String;
  I: Integer;
begin
  N := ExtractFileName(APath);
  Result := Copy(N, 1, 5) = 'event';
  if not Result then
    Exit;
  Digits := Copy(N, 6, MaxInt);
  Result := Digits <> '';
  for I := 1 to Length(Digits) do
    if not (Digits[I] in ['0'..'9']) then
      Exit(False);
end;

{ ---- 能力 ---- }

// EV_IsHaptic。FF のビットを SDL の能力にする。取れなければ 0。
function EVIsHaptic(ANode: TPMLEvdevNode): Cardinal;
var
  Bits: TPMLBits;

  procedure Test(ABit: Integer; AFeature: Cardinal);
  begin
    if PMLTestBit(Bits, ABit) then
      Result := Result or AFeature;
  end;

begin
  Result := 0;
  if not ANode.GetBits(EV_FF, FF_MAX + 1, Bits) then
    Exit;
  Test(FF_CONSTANT, PML_HAPTIC_CONSTANT);
  Test(FF_SINE, PML_HAPTIC_SINE);
  Test(FF_SQUARE, PML_HAPTIC_SQUARE);
  Test(FF_TRIANGLE, PML_HAPTIC_TRIANGLE);
  Test(FF_SAW_UP, PML_HAPTIC_SAWTOOTHUP);
  Test(FF_SAW_DOWN, PML_HAPTIC_SAWTOOTHDOWN);
  Test(FF_RAMP, PML_HAPTIC_RAMP);
  Test(FF_SPRING, PML_HAPTIC_SPRING);
  Test(FF_FRICTION, PML_HAPTIC_FRICTION);
  Test(FF_DAMPER, PML_HAPTIC_DAMPER);
  Test(FF_INERTIA, PML_HAPTIC_INERTIA);
  Test(FF_CUSTOM, PML_HAPTIC_CUSTOM);
  Test(FF_GAIN, PML_HAPTIC_GAIN);
  Test(FF_AUTOCENTER, PML_HAPTIC_AUTOCENTER);
  Test(FF_RUMBLE, PML_HAPTIC_LEFTRIGHT);
end;

// EV_IsMouse（BTN_MOUSE を持つか。SDL は結果にかかわらず true を返す。上の RESOLVED 参照）。
function EVIsMouse(ANode: TPMLEvdevNode): Boolean;
var
  Keys: TPMLBits;
begin
  if not ANode.GetBits(EV_KEY, KEY_MAX + 1, Keys) then
    Exit(False);
  Result := PMLTestBit(Keys, BTN_MOUSE);
end;

{ ---- SDL の効果から ff_effect へ ---- }

{$push}{$R-}{$Q-}

function Clamp(AValue: Cardinal): Word;
begin
  if AValue > 32767 then
    Result := 32767
  else
    Result := Word(AValue);
end;

// SDL_SYS_ToButton
function ToButton(AButton: Word): Word;
begin
  if AButton <> 0 then
    Result := Word(BTN_GAMEPAD + AButton - 1)
  else
    Result := 0;
end;

function PMLHapticToDirection(out ADest: Word; const ASrc: TPMLHapticDirection): Boolean;
const
  PI_D: Double = 3.141592653589793238462643383279502884;
var
  Tmp: LongWord;
  Signed: LongInt;
  F: Single;
begin
  ADest := 0;
  Result := True;
  case ASrc.DirType of
    PML_HAPTIC_POLAR:
      begin
        // 符号つきの剰余と除算（負の向きは、符号なしに入れたとき回り込む）
        Signed := ((ASrc.Dir[0] mod 36000) * $8000) div 18000;
        Tmp := LongWord(Signed);
        ADest := Word(Tmp and $FFFF);
      end;
    PML_HAPTIC_SPHERICAL:
      begin
        // 極座標に直す: 東から南へ測る第 1 成分に 90 度を足す。符号なしの演算
        Signed := (ASrc.Dir[0] + 9000) mod 36000;
        Tmp := LongWord(Signed);
        Tmp := LongWord(Tmp * LongWord($8000));
        Tmp := Tmp div 18000;
        ADest := Word(Tmp and $FFFF);
      end;
    PML_HAPTIC_CARTESIAN:
      begin
        if ASrc.Dir[1] = 0 then
        begin
          if ASrc.Dir[0] >= 0 then
            ADest := $4000
          else
            ADest := $C000;
        end
        else if ASrc.Dir[0] = 0 then
        begin
          if ASrc.Dir[1] >= 0 then
            ADest := $8000
          else
            ADest := 0;
        end
        else
        begin
          // atan2f は単精度。-π〜π を 100 分の 1 度にし、45000 を足して極座標の向きにする
          F := Single(ArcTan2(Double(Single(ASrc.Dir[1])), Double(Single(ASrc.Dir[0]))));
          Signed := (Trunc(Double(F) * 18000.0 / PI_D) + 45000) mod 36000;
          Tmp := LongWord(Signed);
          Tmp := LongWord(Tmp * LongWord($8000));
          Tmp := Tmp div 18000;
          ADest := Word(Tmp and $FFFF);
        end;
      end;
    PML_HAPTIC_STEERING_AXIS:
      ADest := $4000;
  else
    Result := False;
  end;
end;

// 共通の頭（replay と trigger）。長さ PML_HAPTIC_INFINITY は 0 にする。
procedure SetHeader(var ADest: TPMLFFEffect; ALength: Cardinal; ADelay, AButton, AInterval: Word);
begin
  if ALength = PML_HAPTIC_INFINITY then
    ADest.ReplayLength := 0
  else
    ADest.ReplayLength := Clamp(ALength);
  ADest.ReplayDelay := Clamp(ADelay);
  ADest.TriggerButton := ToButton(AButton);
  ADest.TriggerInterval := Clamp(AInterval);
end;

procedure SetEnvelope(var AEnv: TPMLFFEnvelope; AAttackLength, AAttackLevel, AFadeLength, AFadeLevel: Word);
begin
  AEnv.AttackLength := Clamp(AAttackLength);
  AEnv.AttackLevel := Clamp(AAttackLevel);
  AEnv.FadeLength := Clamp(AFadeLength);
  AEnv.FadeLevel := Clamp(AFadeLevel);
end;

function PMLHapticToFFEffect(out ADest: TPMLFFEffect; const ASrc: TPMLHapticEffect;
  out AError: String): Boolean;
var
  Env: TPMLFFEnvelope;
  I: Integer;
begin
  FillChar(ADest, SizeOf(ADest), 0);
  AError := '';
  Result := False;
  case ASrc.EffectType of
    PML_HAPTIC_CONSTANT:
      with ASrc.Constant do
      begin
        ADest.EffectType := FF_CONSTANT;
        if not PMLHapticToDirection(ADest.Direction, Direction) then
        begin
          AError := 'Haptic: Unsupported direction type.';
          Exit;
        end;
        SetHeader(ADest, Length, Delay, Button, Interval);
        ADest.ConstantLevel := Level;
        SetEnvelope(Env, AttackLength, AttackLevel, FadeLength, FadeLevel);
        ADest.ConstantEnvelope := Env;
      end;

    PML_HAPTIC_SINE, PML_HAPTIC_SQUARE, PML_HAPTIC_TRIANGLE, PML_HAPTIC_SAWTOOTHUP, PML_HAPTIC_SAWTOOTHDOWN:
      with ASrc.Periodic do
      begin
        ADest.EffectType := FF_PERIODIC;
        if not PMLHapticToDirection(ADest.Direction, Direction) then
        begin
          AError := 'Haptic: Unsupported direction type.';
          Exit;
        end;
        SetHeader(ADest, Length, Delay, Button, Interval);
        case EffectType of
          PML_HAPTIC_SINE: ADest.PeriodicWaveform := FF_SINE;
          PML_HAPTIC_SQUARE: ADest.PeriodicWaveform := FF_SQUARE;
          PML_HAPTIC_TRIANGLE: ADest.PeriodicWaveform := FF_TRIANGLE;
          PML_HAPTIC_SAWTOOTHUP: ADest.PeriodicWaveform := FF_SAW_UP;
          PML_HAPTIC_SAWTOOTHDOWN: ADest.PeriodicWaveform := FF_SAW_DOWN;
        end;
        ADest.PeriodicPeriod := Clamp(Period);
        ADest.PeriodicMagnitude := Magnitude;
        ADest.PeriodicOffset := Offset;
        // Linux の位相は [0, 0x10000) が [0 度, 360 度)。100 分の 1 度を符号なし 32 ビットで換算し、16 ビットに切る
        ADest.PeriodicPhase := Word((LongWord(Phase) * LongWord($10000)) div 36000);
        ADest.EnvAttackLength := Clamp(AttackLength);
        ADest.EnvAttackLevel := Clamp(AttackLevel);
        ADest.EnvFadeLength := Clamp(FadeLength);
        ADest.EnvFadeLevel := Clamp(FadeLevel);
      end;

    PML_HAPTIC_SPRING, PML_HAPTIC_DAMPER, PML_HAPTIC_INERTIA, PML_HAPTIC_FRICTION:
      with ASrc.Condition do
      begin
        case EffectType of
          PML_HAPTIC_SPRING: ADest.EffectType := FF_SPRING;
          PML_HAPTIC_DAMPER: ADest.EffectType := FF_DAMPER;
          PML_HAPTIC_INERTIA: ADest.EffectType := FF_INERTIA;
          PML_HAPTIC_FRICTION: ADest.EffectType := FF_FRICTION;
        end;
        if not PMLHapticToDirection(ADest.Direction, Direction) then
        begin
          AError := 'Haptic: Unsupported direction type.';
          Exit;
        end;
        SetHeader(ADest, Length, Delay, Button, Interval);
        // X 軸と Y 軸。条件の効果に包絡線は無い
        for I := 0 to 1 do
        begin
          ADest.Condition[I].RightSaturation := RightSat[I];
          ADest.Condition[I].LeftSaturation := LeftSat[I];
          ADest.Condition[I].RightCoeff := RightCoeff[I];
          ADest.Condition[I].LeftCoeff := LeftCoeff[I];
          ADest.Condition[I].Deadband := Deadband[I];
          ADest.Condition[I].Center := Center[I];
        end;
      end;

    PML_HAPTIC_RAMP:
      with ASrc.Ramp do
      begin
        ADest.EffectType := FF_RAMP;
        if not PMLHapticToDirection(ADest.Direction, Direction) then
        begin
          AError := 'Haptic: Unsupported direction type.';
          Exit;
        end;
        SetHeader(ADest, Length, Delay, Button, Interval);
        ADest.RampStart := Start;
        ADest.RampEnd := End_;
        SetEnvelope(Env, AttackLength, AttackLevel, FadeLength, FadeLevel);
        ADest.RampEnvelope := Env;
      end;

    PML_HAPTIC_LEFTRIGHT:
      with ASrc.LeftRight do
      begin
        ADest.EffectType := FF_RUMBLE;
        ADest.Direction := $4000;
        // 遅れとトリガーは無い
        if Length = PML_HAPTIC_INFINITY then
          ADest.ReplayLength := 0
        else
          ADest.ReplayLength := Clamp(Length);
        ADest.TriggerButton := 0;
        ADest.TriggerInterval := 0;
        // Linux は 0〜65535 を期待するので 2 倍する
        ADest.RumbleStrong := Word(Clamp(LargeMagnitude) * 2);
        ADest.RumbleWeak := Word(Clamp(SmallMagnitude) * 2);
      end;
  else
    AError := 'Haptic: Unknown effect type.';
    Exit;
  end;
  Result := True;
end;

{$pop}

{ ---- バックエンド ---- }

constructor TPMLLinuxHapticBackend.Create(ACore: TPMLHapticCore);
begin
  inherited Create(ACore);
  if Assigned(PMLLinuxHapticHostFactory) then
    FHost := PMLLinuxHapticHostFactory()
  else
    FHost := TPMLRealEvdevHost.Create;
  FOwnsHost := True;
end;

destructor TPMLLinuxHapticBackend.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
    FItems[I].Free;
  FItems := nil;
  if FOwnsHost then
    FHost.Free;
  inherited Destroy;
end;

function TPMLLinuxHapticBackend.Name: String;
begin
  Result := 'linux';
end;

function TPMLLinuxHapticBackend.FindByDevNum(ADevNum: QWord): TLinuxHapticItem;
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
    if FItems[I].DevNum = ADevNum then
      Exit(FItems[I]);
  Result := nil;
end;

function TPMLLinuxHapticBackend.FindByPath(const APath: String): TLinuxHapticItem;
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
    if FItems[I].Path = APath then
      Exit(FItems[I]);
  Result := nil;
end;

function TPMLLinuxHapticBackend.MaybeAddDevice(const APath: String): Boolean;
var
  Node: TPMLEvdevNode;
  DevNum: QWord;
  Item: TLinuxHapticItem;
begin
  Result := False;
  if APath = '' then
    Exit;
  // 書き込みで開く（開けなければ、FF を使えない機器なので足さない）
  Node := FHost.OpenNode(APath, True);
  if Node = nil then
    Exit;
  try
    if not FHost.DeviceNumber(APath, DevNum) then
      Exit;
    // もう持っている機器
    if FindByDevNum(DevNum) <> nil then
      Exit;
    if EVIsHaptic(Node) = 0 then
      Exit;
  finally
    Node.Free;
  end;
  Item := TLinuxHapticItem.Create;
  Item.InstanceID := Core.NextInstanceID;
  Item.Path := APath;
  Item.DevNum := DevNum;
  SetLength(FItems, Length(FItems) + 1);
  FItems[High(FItems)] := Item;
  Result := True;
end;

procedure TPMLLinuxHapticBackend.MaybeRemoveDevice(const APath: String);
var
  I, J: Integer;
begin
  if APath = '' then
    Exit;
  for I := 0 to High(FItems) do
    if FItems[I].Path = APath then
    begin
      FItems[I].Free;
      for J := I to High(FItems) - 1 do
        FItems[J] := FItems[J + 1];
      SetLength(FItems, Length(FItems) - 1);
      Exit;
    end;
end;

procedure TPMLLinuxHapticBackend.OnHotplug(AKind: TPMLHotplugKind; AClass: Integer; const APath: String);
begin
  if APath = '' then
    Exit;
  if AClass >= 0 then
  begin
    // udev: JOYSTICK の種類の機器だけ
    if (AClass and PML_UDEV_DEVICE_JOYSTICK) = 0 then
      Exit;
  end
  else if not IsEventNode(APath) then
    Exit;   // inotify: event の機器だけ
  if AKind = TPMLHotplugKind.Added then
    MaybeAddDevice(APath)
  else
    MaybeRemoveDevice(APath);
end;

function TPMLLinuxHapticBackend.Init: Boolean;
var
  I: Integer;
begin
  // 試す数に上限を置く（権限のない機器が多くても止まらない）
  for I := 0 to MAX_HAPTICS - 1 do
    MaybeAddDevice('/dev/input/event' + IntToStr(I));
  FMethod := FHost.StartHotplug(not FHost.Sandboxed, @OnHotplug);
  if FMethod = TPMLHotplugMethod.Udev then
    // 今ある機器で一覧を作り直す（持っている機器は番号で飛ばされる）
    FHost.ScanHotplug;
  Result := True;
end;

procedure TPMLLinuxHapticBackend.Quit;
begin
  FHost.StopHotplug;
end;

procedure TPMLLinuxHapticBackend.Detect;
begin
  if FMethod <> TPMLHotplugMethod.None then
    FHost.PollHotplug;
end;

function TPMLLinuxHapticBackend.DeviceCount: Integer;
begin
  Result := Length(FItems);
end;

function TPMLLinuxHapticBackend.DeviceInstanceID(AIndex: Integer): TPMLHapticID;
begin
  if (AIndex < 0) or (AIndex > High(FItems)) then
    Exit(0);
  Result := FItems[AIndex].InstanceID;
end;

function TPMLLinuxHapticBackend.DeviceName(AIndex: Integer): String;
var
  Node: TPMLEvdevNode;
  N: String;
begin
  Result := '';
  if (AIndex < 0) or (AIndex > High(FItems)) then
    Exit;
  Node := FHost.OpenNode(FItems[AIndex].Path, False);
  if Node = nil then
    Exit;
  try
    if Node.GetName(N) and (N <> '') then
      Result := N
    else
      Result := FItems[AIndex].Path;   // 名前が無ければ機器のパス
  finally
    Node.Free;
  end;
end;

function TPMLLinuxHapticBackend.HwOf(AHaptic: TPMLHaptic): THapticHw;
begin
  Result := THapticHw(AHaptic.HwData);
end;

// SDL_SYS_HapticOpenFromFD
function TPMLLinuxHapticBackend.OpenFromNode(AHaptic: TPMLHaptic; ANode: TPMLEvdevNode;
  const APath: String): Boolean;
var
  Hw: THapticHw;
  NEffects: Integer;
begin
  Hw := THapticHw.Create;
  Hw.Node := ANode;
  Hw.Path := APath;
  // 効果の数を聞く。聞けなければ閉じる（Hw が Node を持つので Free で閉じる）
  if not ANode.GetEffectCount(NEffects) then
  begin
    FLastError := 'Haptic: Unable to query device memory: ' + ANode.Error;
    Hw.Free;
    Exit(False);
  end;
  AHaptic.HwData := Hw;
  // 軸は 2 つで決め打ち（SDL も調べ方が分からないまま）。同時に鳴らせる数は Linux では区別しない
  AHaptic.Configure(EVIsHaptic(ANode), 2, NEffects, NEffects);
  Result := True;
end;

function TPMLLinuxHapticBackend.Open(AHaptic: TPMLHaptic; AIndex: Integer): Boolean;
var
  Item: TLinuxHapticItem;
  Node: TPMLEvdevNode;
begin
  Item := FItems[AIndex];
  Node := FHost.OpenNode(Item.Path, True);
  if Node = nil then
  begin
    FLastError := 'Haptic: Unable to open ' + Item.Path;
    Exit(False);
  end;
  Result := OpenFromNode(AHaptic, Node, Item.Path);
end;

function TPMLLinuxHapticBackend.MouseIndex: Integer;
var
  I: Integer;
  Node: TPMLEvdevNode;
begin
  for I := 0 to High(FItems) do
  begin
    Node := FHost.OpenNode(FItems[I].Path, True);
    // 開けない機器は飛ばす（SDL は添字 0 を返してしまう）
    if Node = nil then
      Continue;
    try
      if EVIsMouse(Node) then
        Exit(I);
    finally
      Node.Free;
    end;
  end;
  Result := -1;
end;

function TPMLLinuxHapticBackend.IsLinuxJoystick(AJoystick: TPMLJoystick): Boolean;
begin
  Result := (AJoystick <> nil) and (AJoystick.Backend <> nil) and SameText(AJoystick.Backend.Name, 'linux');
end;

function TPMLLinuxHapticBackend.JoystickIsHaptic(AJoystick: TPMLJoystick): Boolean;
var
  Node: TPMLEvdevNode;
begin
  Result := False;
  if not IsLinuxJoystick(AJoystick) then
    Exit;
  // 調べるだけなので、読み取りで開く
  Node := FHost.OpenNode(AJoystick.Path, False);
  if Node = nil then
    Exit;
  try
    Result := EVIsHaptic(Node) <> 0;
  finally
    Node.Free;
  end;
end;

function TPMLLinuxHapticBackend.JoystickSameHaptic(AHaptic: TPMLHaptic; AJoystick: TPMLJoystick): Boolean;
begin
  Result := IsLinuxJoystick(AJoystick) and (AHaptic.HwData is THapticHw) and
    (HwOf(AHaptic).Path = AJoystick.Path);
end;

function TPMLLinuxHapticBackend.OpenFromJoystick(AHaptic: TPMLHaptic; AJoystick: TPMLJoystick): Boolean;
var
  Item: TLinuxHapticItem;
  Node: TPMLEvdevNode;
  N: String;
begin
  if not IsLinuxJoystick(AJoystick) then
  begin
    FLastError := 'not a Linux joystick';
    Exit(False);
  end;
  // 一覧に無ければ足す（SDL は ID 0 のまま進む）
  Item := FindByPath(AJoystick.Path);
  if Item = nil then
  begin
    MaybeAddDevice(AJoystick.Path);
    Item := FindByPath(AJoystick.Path);
  end;
  Node := FHost.OpenNode(AJoystick.Path, True);
  if Node = nil then
  begin
    FLastError := 'Haptic: Unable to open ' + AJoystick.Path;
    Exit(False);
  end;
  if not OpenFromNode(AHaptic, Node, AJoystick.Path) then
    Exit(False);
  N := '';
  Node.GetName(N);
  if Item <> nil then
    AHaptic.SetIdentity(Item.InstanceID, N)
  else
    AHaptic.SetIdentity(Core.NextInstanceID, N);
  Result := True;
end;

procedure TPMLLinuxHapticBackend.Close(AHaptic: TPMLHaptic);
begin
  // 機器を閉じる（効果はコアが先に消している）
  AHaptic.HwData.Free;
  AHaptic.HwData := nil;
end;

function TPMLLinuxHapticBackend.NewEffect(AHaptic: TPMLHaptic; ASlot: Integer;
  const ABase: TPMLHapticEffect): Boolean;
var
  Hw: THapticHwEffect;
  Err: String;
begin
  Hw := THapticHwEffect.Create;
  if not PMLHapticToFFEffect(Hw.Effect, ABase, Err) then
  begin
    AHaptic.SetError(Err);
    Hw.Free;
    Exit(False);
  end;
  Hw.Effect.ID := -1;     // カーネルに番号を決めさせる
  if not HwOf(AHaptic).Node.UploadEffect(Hw.Effect) then
  begin
    AHaptic.SetError('Haptic: Error uploading effect to the device: ' + HwOf(AHaptic).Node.Error);
    Hw.Free;
    Exit(False);
  end;
  AHaptic.SetEffectHw(ASlot, Hw);
  Result := True;
end;

function TPMLLinuxHapticBackend.UpdateEffect(AHaptic: TPMLHaptic; ASlot: Integer;
  const AData: TPMLHapticEffect): Boolean;
var
  Hw: THapticHwEffect;
  New_: TPMLFFEffect;
  Err: String;
begin
  Hw := THapticHwEffect(AHaptic.EffectHw(ASlot));
  if not PMLHapticToFFEffect(New_, AData, Err) then
  begin
    AHaptic.SetError(Err);
    Exit(False);
  end;
  New_.ID := Hw.Effect.ID;
  if not HwOf(AHaptic).Node.UploadEffect(New_) then
  begin
    AHaptic.SetError('Haptic: Error updating the effect: ' + HwOf(AHaptic).Node.Error);
    Exit(False);
  end;
  Hw.Effect := New_;
  Result := True;
end;

function TPMLLinuxHapticBackend.RunEffect(AHaptic: TPMLHaptic; ASlot: Integer; AIterations: Cardinal): Boolean;
var
  Hw: THapticHwEffect;
  Count: Integer;
begin
  Hw := THapticHwEffect(AHaptic.EffectHw(ASlot));
  // 本当の無限は無いので、INT_MAX で代える
  if AIterations > Cardinal(High(LongInt)) then
    Count := High(LongInt)
  else
    Count := Integer(AIterations);
  Result := HwOf(AHaptic).Node.WriteFF(Hw.Effect.ID, Count);
  if not Result then
    AHaptic.SetError('Haptic: Unable to run the effect: ' + HwOf(AHaptic).Node.Error);
end;

function TPMLLinuxHapticBackend.StopEffect(AHaptic: TPMLHaptic; ASlot: Integer): Boolean;
var
  Hw: THapticHwEffect;
begin
  Hw := THapticHwEffect(AHaptic.EffectHw(ASlot));
  Result := HwOf(AHaptic).Node.WriteFF(Hw.Effect.ID, 0);
  if not Result then
    AHaptic.SetError('Haptic: Unable to stop the effect: ' + HwOf(AHaptic).Node.Error);
end;

procedure TPMLLinuxHapticBackend.DestroyEffect(AHaptic: TPMLHaptic; ASlot: Integer);
var
  Hw: THapticHwEffect;
begin
  Hw := THapticHwEffect(AHaptic.EffectHw(ASlot));
  if not HwOf(AHaptic).Node.RemoveEffect(Hw.Effect.ID) then
    AHaptic.SetError('Haptic: Error removing the effect from the device');
end;

function TPMLLinuxHapticBackend.GetEffectStatus(AHaptic: TPMLHaptic; ASlot: Integer): Integer;
begin
  AHaptic.SetError(UNSUPPORTED);
  Result := -1;
end;

function TPMLLinuxHapticBackend.SetGain(AHaptic: TPMLHaptic; AGain: Integer): Boolean;
begin
  // 0〜100 を 0〜0xFFFF に伸ばす
  Result := HwOf(AHaptic).Node.WriteFF(FF_GAIN, Integer((Int64($FFFF) * AGain) div 100));
  if not Result then
    AHaptic.SetError('Haptic: Error setting gain: ' + HwOf(AHaptic).Node.Error);
end;

function TPMLLinuxHapticBackend.SetAutocenter(AHaptic: TPMLHaptic; AAutocenter: Integer): Boolean;
begin
  Result := HwOf(AHaptic).Node.WriteFF(FF_AUTOCENTER, Integer((Int64($FFFF) * AAutocenter) div 100));
  if not Result then
    AHaptic.SetError('Haptic: Error setting autocenter: ' + HwOf(AHaptic).Node.Error);
end;

function TPMLLinuxHapticBackend.Pause(AHaptic: TPMLHaptic): Boolean;
begin
  AHaptic.SetError(UNSUPPORTED);
  Result := False;
end;

function TPMLLinuxHapticBackend.Resume(AHaptic: TPMLHaptic): Boolean;
begin
  AHaptic.SetError(UNSUPPORTED);
  Result := False;
end;

function TPMLLinuxHapticBackend.StopAll(AHaptic: TPMLHaptic): Boolean;
var
  I: Integer;
begin
  // Linux には全部を止める手が無いので、1 つずつ止める
  for I := 0 to AHaptic.MaxEffects - 1 do
    if AHaptic.EffectHw(I) <> nil then
      if not StopEffect(AHaptic, I) then
      begin
        AHaptic.SetError('Haptic: Error while trying to stop all playing effects.');
        Exit(False);
      end;
  Result := True;
end;

function CreateLinuxHapticBackend(ACore: TPMLHapticCore): TPMLHapticBackend;
begin
  Result := TPMLLinuxHapticBackend.Create(ACore);
end;

initialization
  PMLRegisterHapticBackend('linux', 0, @CreateLinuxHapticBackend);

end.
