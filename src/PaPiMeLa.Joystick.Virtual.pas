{
  PaPiMeLa.Joystick.Virtual — 仮想ジョイスティック

  Origin : ported from SDL (src/joystick/virtual/SDL_virtualjoystick.c)
           Scope: SDL_JoystickAttachVirtualInner / DetachVirtualInner、仮想の機器の一覧（g_VJoys）、
           VIRTUAL_JoystickXxx の 21 個の入り口、SDL_SetJoystickVirtualXxxInner（軸・ボール・ボタン・ハット）、
           ゲームパッドのマッピングの自動生成（VIRTUAL_JoystickGetGamepadMapping）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #61

  WHAT:
    アプリが AttachVirtual で作った仮想の機器を、バックエンドの一覧（FDevices）で持ち、
    開かれたジョイスティックには状態を送る。Update で Changes の立った分だけをコアへ送る。

  WHY:
    SDL は仮想の機器を SDL 全体の連結リストに持つ。papimela では機器の一覧はバックエンドが持つ
    （TPMLJoystickBackend の約束）ので、同じ並び（足した順）をバックエンドのフィールドにする。

  RESOLVED:
    - 機器の中身（記述のコピー・状態・Changes）は TVirtualData。開いている間だけ
      TPMLJoystick.HwData が指す
    - SDL は nballs を開いた機器へ写さない（PORT-NOTE(bug): 上流の不具合 D-79）。
      ここでは SetCounts に NumBalls も入れる
    - タッチパッドとセンサーの記述は TPMLVirtualJoystickDesc に無いので扱わない

  NOT RESOLVED:
    - 仮想の機器にタッチパッドとセンサーは無い（SDL の touchpad / sensor の口は移植しない）
    - SDL の DeviceInstanceID は範囲外で true（1）を返すが、ここでは 0 を返す（PORT-NOTE(bug)）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Joystick.Virtual;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Joystick.GUID,
  PaPiMeLa.Joystick.Backend;

type
  // 変わった所（SDL の AXES_CHANGED など）。
  TPMLVirtualChange = (VCAxes, VCBalls, VCButtons, VCHats);
  TPMLVirtualChanges = set of TPMLVirtualChange;

  // ボールの積み上げ（SDL_JoystickBallData）。
  TPMLVirtualBall = record
    DX, DY: Integer;
  end;

  { 仮想の機器 1 台（SDL の joystick_hwdata）。記述のコピーと状態を持つ。
    Joystick は開いている間だけ入る。 }
  TVirtualData = class
  public
    Desc    : TPMLVirtualJoystickDesc;
    Name    : String;
    GUID    : TPMLGUID;
    InstanceID: TPMLJoystickID;
    Axes    : array of SmallInt;
    Buttons : array of Boolean;
    Hats    : array of Byte;
    Balls   : array of TPMLVirtualBall;
    Changes : TPMLVirtualChanges;
    Joystick: TPMLJoystick;
  end;

  TVirtualDataArray = array of TVirtualData;

  TPMLVirtualJoystickBackend = class(TPMLJoystickBackend, IPMLVirtualJoystickBackend)
  strict private
    FDevices: TVirtualDataArray;
  public
    function  Name: String; override;
    function  Init: Boolean; override;
    function  DeviceCount: Integer; override;
    function  DeviceName(AIndex: Integer): String; override;
    function  DeviceGUID(AIndex: Integer): TPMLGUID; override;
    function  DeviceInstanceID(AIndex: Integer): TPMLJoystickID; override;
    procedure SetDevicePlayerIndex(AIndex, APlayerIndex: Integer); override;
    function  Open(AJoystick: TPMLJoystick; AIndex: Integer): Boolean; override;
    function  Rumble(AJoystick: TPMLJoystick; ALow, AHigh: Word): Boolean; override;
    function  RumbleTriggers(AJoystick: TPMLJoystick; ALeft, ARight: Word): Boolean; override;
    function  SetLED(AJoystick: TPMLJoystick; ARed, AGreen, ABlue: Byte): Boolean; override;
    function  SendEffect(AJoystick: TPMLJoystick; AData: Pointer; ASize: Integer): Boolean; override;
    function  SetSensorsEnabled(AJoystick: TPMLJoystick; AEnabled: Boolean): Boolean; override;
    procedure Update(AJoystick: TPMLJoystick); override;
    procedure Close(AJoystick: TPMLJoystick); override;
    procedure Quit; override;
    function  GamepadMapping(AIndex: Integer; out AMapping: TPMLGamepadMapping): Boolean; override;
    function  AttachVirtual(const ADesc: TPMLVirtualJoystickDesc): TPMLJoystickID;
    procedure DetachVirtual(AID: TPMLJoystickID);
    function  IsVirtual(AID: TPMLJoystickID): Boolean;
    procedure SetVirtualAxis(AJoystick: TPMLJoystick; AAxis: Integer; AValue: SmallInt);
    procedure SetVirtualBall(AJoystick: TPMLJoystick; ABall: Integer; AXRel, AYRel: SmallInt);
    procedure SetVirtualButton(AJoystick: TPMLJoystick; AButton: Integer; ADown: Boolean);
    procedure SetVirtualHat(AJoystick: TPMLJoystick; AHat: Integer; AValue: Byte);
  end;

implementation

{ 添字の位置（ID で探す）。無ければ -1。 }
function VirtualFindIndex(const ADevices: TVirtualDataArray; AID: TPMLJoystickID): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(ADevices) do
    if ADevices[I].InstanceID = AID then
    begin
      Result := I;
      Exit;
    end;
end;

{ 添字の位置の機器を一覧から外す（後ろを詰める）。 }
procedure VirtualRemoveAt(var ADevices: TVirtualDataArray; AIndex: Integer);
var
  I: Integer;
begin
  for I := AIndex to High(ADevices) - 1 do
    ADevices[I] := ADevices[I + 1];
  SetLength(ADevices, Length(ADevices) - 1);
end;

{ 外れる機器の後始末（SDL の VIRTUAL_FreeHWData）。一覧からは先に外してあること。
  OnCleanup を呼び、開いているジョイスティックの HwData を nil にする。Core は呼ばない。 }
procedure VirtualRelease(ADev: TVirtualData);
begin
  if Assigned(ADev.Desc.OnCleanup) then
    ADev.Desc.OnCleanup;
  if ADev.Joystick <> nil then
  begin
    ADev.Joystick.HwData := nil;
    ADev.Joystick := nil;
  end;
  ADev.Free;
end;

{ 開いたジョイスティックから機器を取る。無ければ EPMLArgument。 }
function VirtualDataOf(AJoystick: TPMLJoystick): TVirtualData;
begin
  if (AJoystick = nil) or (AJoystick.HwData = nil) then
    raise EPMLArgument.Create('Invalid joystick');
  Result := TVirtualData(AJoystick.HwData);
end;

{ -32768..32767 に挟む（SDL_clamp）。 }
function VirtualClamp16(AValue: Integer): Integer;
begin
  Result := AValue;
  if Result < PML_JOYSTICK_AXIS_MIN then
    Result := PML_JOYSTICK_AXIS_MIN;
  if Result > PML_JOYSTICK_AXIS_MAX then
    Result := PML_JOYSTICK_AXIS_MAX;
end;

function TPMLVirtualJoystickBackend.Name: String;
begin
  Result := 'virtual';
end;

function TPMLVirtualJoystickBackend.Init: Boolean;
begin
  Result := True;
end;

function TPMLVirtualJoystickBackend.DeviceCount: Integer;
begin
  Result := Length(FDevices);
end;

function TPMLVirtualJoystickBackend.DeviceName(AIndex: Integer): String;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex < Length(FDevices)) then
    Result := FDevices[AIndex].Name;
end;

function TPMLVirtualJoystickBackend.DeviceGUID(AIndex: Integer): TPMLGUID;
begin
  Result := PMLZeroGUID;
  if (AIndex >= 0) and (AIndex < Length(FDevices)) then
    Result := FDevices[AIndex].GUID;
end;

function TPMLVirtualJoystickBackend.DeviceInstanceID(AIndex: Integer): TPMLJoystickID;
begin
  // PORT-NOTE(bug): SDL は範囲外で true（1）を返す。ここでは「無い」の 0。
  Result := 0;
  if (AIndex >= 0) and (AIndex < Length(FDevices)) then
    Result := FDevices[AIndex].InstanceID;
end;

procedure TPMLVirtualJoystickBackend.SetDevicePlayerIndex(AIndex, APlayerIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < Length(FDevices)) then
    if Assigned(FDevices[AIndex].Desc.OnSetPlayerIndex) then
      FDevices[AIndex].Desc.OnSetPlayerIndex(APlayerIndex);
end;

function TPMLVirtualJoystickBackend.Open(AJoystick: TPMLJoystick; AIndex: Integer): Boolean;
var
  D: TVirtualData;
begin
  if (AIndex < 0) or (AIndex >= Length(FDevices)) then
  begin
    FLastError := 'No such device';
    Result := False;
    Exit;
  end;
  D := FDevices[AIndex];
  AJoystick.HwData := D;
  D.Joystick := AJoystick;
  // PORT-NOTE(bug): SDL は nballs を写さない（D-79）。ここでは NumBalls も入れる。
  AJoystick.SetCounts(Integer(D.Desc.NumAxes), Integer(D.Desc.NumBalls),
    Integer(D.Desc.NumHats), Integer(D.Desc.NumButtons));
  if Assigned(D.Desc.OnSetLED) then
    AJoystick.AddCapability(TPMLJoystickCapability.RGBLED);
  if Assigned(D.Desc.OnRumble) then
    AJoystick.AddCapability(TPMLJoystickCapability.Rumble);
  if Assigned(D.Desc.OnRumbleTriggers) then
    AJoystick.AddCapability(TPMLJoystickCapability.TriggerRumble);
  Result := True;
end;

function TPMLVirtualJoystickBackend.Rumble(AJoystick: TPMLJoystick; ALow, AHigh: Word): Boolean;
begin
  Result := False;
  if (AJoystick = nil) or (AJoystick.HwData = nil) then
    Exit;
  if Assigned(TVirtualData(AJoystick.HwData).Desc.OnRumble) then
    Result := TVirtualData(AJoystick.HwData).Desc.OnRumble(ALow, AHigh);
end;

function TPMLVirtualJoystickBackend.RumbleTriggers(AJoystick: TPMLJoystick; ALeft, ARight: Word): Boolean;
begin
  Result := False;
  if (AJoystick = nil) or (AJoystick.HwData = nil) then
    Exit;
  if Assigned(TVirtualData(AJoystick.HwData).Desc.OnRumbleTriggers) then
    Result := TVirtualData(AJoystick.HwData).Desc.OnRumbleTriggers(ALeft, ARight);
end;

function TPMLVirtualJoystickBackend.SetLED(AJoystick: TPMLJoystick; ARed, AGreen, ABlue: Byte): Boolean;
begin
  Result := False;
  if (AJoystick = nil) or (AJoystick.HwData = nil) then
    Exit;
  if Assigned(TVirtualData(AJoystick.HwData).Desc.OnSetLED) then
    Result := TVirtualData(AJoystick.HwData).Desc.OnSetLED(ARed, AGreen, ABlue);
end;

function TPMLVirtualJoystickBackend.SendEffect(AJoystick: TPMLJoystick; AData: Pointer; ASize: Integer): Boolean;
begin
  Result := False;
  if (AJoystick = nil) or (AJoystick.HwData = nil) then
    Exit;
  if Assigned(TVirtualData(AJoystick.HwData).Desc.OnSendEffect) then
    Result := TVirtualData(AJoystick.HwData).Desc.OnSendEffect(AData, ASize);
end;

function TPMLVirtualJoystickBackend.SetSensorsEnabled(AJoystick: TPMLJoystick; AEnabled: Boolean): Boolean;
begin
  // 機器が外れていれば False（SDL と同じ。仕様に無い所だが C の分岐に合わせた）。
  Result := False;
  if (AJoystick = nil) or (AJoystick.HwData = nil) then
    Exit;
  Result := True;
  if Assigned(TVirtualData(AJoystick.HwData).Desc.OnSetSensorsEnabled) then
    Result := TVirtualData(AJoystick.HwData).Desc.OnSetSensorsEnabled(AEnabled);
end;

procedure TPMLVirtualJoystickBackend.Update(AJoystick: TPMLJoystick);
var
  D : TVirtualData;
  Ts: UInt64;
  I : Integer;
begin
  if (AJoystick = nil) or (AJoystick.HwData = nil) then
    Exit;
  D := TVirtualData(AJoystick.HwData);
  Ts := Core.TimestampNS;
  if Assigned(D.Desc.OnUpdate) then
    D.Desc.OnUpdate;
  if (TPMLVirtualChange.VCAxes in D.Changes) then
    for I := 0 to High(D.Axes) do
      Core.SendAxis(Ts, AJoystick, Byte(I), D.Axes[I]);
  if (TPMLVirtualChange.VCBalls in D.Changes) then
    for I := 0 to High(D.Balls) do
      if (D.Balls[I].DX <> 0) or (D.Balls[I].DY <> 0) then
      begin
        Core.SendBall(Ts, AJoystick, Byte(I), SmallInt(D.Balls[I].DX), SmallInt(D.Balls[I].DY));
        D.Balls[I].DX := 0;
        D.Balls[I].DY := 0;
      end;
  if (TPMLVirtualChange.VCButtons in D.Changes) then
    for I := 0 to High(D.Buttons) do
      Core.SendButton(Ts, AJoystick, Byte(I), D.Buttons[I]);
  if (TPMLVirtualChange.VCHats in D.Changes) then
    for I := 0 to High(D.Hats) do
      Core.SendHat(Ts, AJoystick, Byte(I), D.Hats[I]);
  D.Changes := [];
end;

procedure TPMLVirtualJoystickBackend.Close(AJoystick: TPMLJoystick);
begin
  if (AJoystick = nil) or (AJoystick.HwData = nil) then
    Exit;
  TVirtualData(AJoystick.HwData).Joystick := nil;
  AJoystick.HwData := nil;
end;

procedure TPMLVirtualJoystickBackend.Quit;
var
  Dev: TVirtualData;
begin
  // Core.DeviceRemoved は呼ばない（コアの Quit が先に呼ぶ）。
  while Length(FDevices) > 0 do
  begin
    Dev := FDevices[High(FDevices)];
    SetLength(FDevices, Length(FDevices) - 1);
    VirtualRelease(Dev);
  end;
end;

function TPMLVirtualJoystickBackend.GamepadMapping(AIndex: Integer; out AMapping: TPMLGamepadMapping): Boolean;
var
  D         : TVirtualData;
  B         : TPMLGamepadButton;
  A         : TPMLGamepadAxis;
  CurButton : Integer;
  CurAxis   : Integer;
begin
  AMapping := PMLEmptyGamepadMapping;
  Result := False;
  if (AIndex < 0) or (AIndex >= Length(FDevices)) then
    Exit;
  D := FDevices[AIndex];
  if D.Desc.JoystickType <> TPMLJoystickType.Gamepad then
    Exit;

  CurButton := 0;
  for B := Low(TPMLGamepadButton) to High(TPMLGamepadButton) do
    if (CurButton < Integer(D.Desc.NumButtons)) and
       ((D.Desc.ButtonMask and (LongWord(1) shl Ord(B))) <> 0) then
    begin
      AMapping.Buttons[B].Kind := TPMLMappingKind.Button;
      AMapping.Buttons[B].Target := Byte(CurButton);
      Inc(CurButton);
    end;

  CurAxis := 0;
  for A := Low(TPMLGamepadAxis) to High(TPMLGamepadAxis) do
    if (CurAxis < Integer(D.Desc.NumAxes)) and
       ((D.Desc.AxisMask and (LongWord(1) shl Ord(A))) <> 0) then
    begin
      AMapping.Axes[A].Kind := TPMLMappingKind.Axis;
      AMapping.Axes[A].Target := Byte(CurAxis);
      Inc(CurAxis);
    end;

  Result := True;
end;

function TPMLVirtualJoystickBackend.AttachVirtual(const ADesc: TPMLVirtualJoystickDesc): TPMLJoystickID;
var
  D         : TVirtualData;
  LName     : String;
  I, N      : Integer;
  Ax        : Integer;
  TriggerLeft : Integer;
  TriggerRight: Integer;
begin
  D := TVirtualData.Create;

  if ADesc.Name <> '' then
    LName := ADesc.Name
  else
    case ADesc.JoystickType of
      TPMLJoystickType.Gamepad:     LName := 'Virtual Controller';
      TPMLJoystickType.Wheel:       LName := 'Virtual Wheel';
      TPMLJoystickType.ArcadeStick: LName := 'Virtual Arcade Stick';
      TPMLJoystickType.FlightStick: LName := 'Virtual Flight Stick';
      TPMLJoystickType.DancePad:    LName := 'Virtual Dance Pad';
      TPMLJoystickType.Guitar:      LName := 'Virtual Guitar';
      TPMLJoystickType.DrumKit:     LName := 'Virtual Drum Kit';
      TPMLJoystickType.ArcadePad:   LName := 'Virtual Arcade Pad';
      TPMLJoystickType.Throttle:    LName := 'Virtual Throttle';
    else
      LName := 'Virtual Joystick';
    end;

  D.Desc := ADesc;
  D.Name := LName;
  TriggerLeft := -1;
  TriggerRight := -1;

  if ADesc.JoystickType = TPMLJoystickType.Gamepad then
  begin
    if D.Desc.ButtonMask = 0 then
    begin
      N := Integer(D.Desc.NumButtons);
      if N > 32 then
        N := 32;
      for I := 0 to N - 1 do
        D.Desc.ButtonMask := D.Desc.ButtonMask or (LongWord(1) shl I);
    end;

    if D.Desc.AxisMask = 0 then
    begin
      if (D.Desc.NumAxes >= 2) then
        D.Desc.AxisMask := D.Desc.AxisMask or (LongWord(1) shl Ord(TPMLGamepadAxis.LeftX))
          or (LongWord(1) shl Ord(TPMLGamepadAxis.LeftY));
      if (D.Desc.NumAxes >= 4) then
        D.Desc.AxisMask := D.Desc.AxisMask or (LongWord(1) shl Ord(TPMLGamepadAxis.RightX))
          or (LongWord(1) shl Ord(TPMLGamepadAxis.RightY));
      if (D.Desc.NumAxes >= 6) then
        D.Desc.AxisMask := D.Desc.AxisMask or (LongWord(1) shl Ord(TPMLGamepadAxis.LeftTrigger))
          or (LongWord(1) shl Ord(TPMLGamepadAxis.RightTrigger));
    end;

    // トリガーの軸の番号を探す（SDL の Find the trigger axes）。
    Ax := 0;
    I := 0;
    while (Ax < Integer(D.Desc.NumAxes)) and (I < 6) do
    begin
      if (D.Desc.AxisMask and (LongWord(1) shl I)) <> 0 then
      begin
        if I = Ord(TPMLGamepadAxis.LeftTrigger) then
          TriggerLeft := Ax;
        if I = Ord(TPMLGamepadAxis.RightTrigger) then
          TriggerRight := Ax;
        Inc(Ax);
      end;
      Inc(I);
    end;
  end;

  D.GUID := PMLCreateJoystickGUID(PML_HARDWARE_BUS_VIRTUAL, ADesc.VendorID, ADesc.ProductID, 0,
    '', LName, Byte(Ord('v')), Byte(Ord(ADesc.JoystickType)));

  SetLength(D.Axes, Integer(ADesc.NumAxes));
  for I := 0 to High(D.Axes) do
    D.Axes[I] := 0;
  if TriggerLeft >= 0 then
    D.Axes[TriggerLeft] := PML_JOYSTICK_AXIS_MIN;
  if TriggerRight >= 0 then
    D.Axes[TriggerRight] := PML_JOYSTICK_AXIS_MIN;

  SetLength(D.Buttons, Integer(ADesc.NumButtons));
  for I := 0 to High(D.Buttons) do
    D.Buttons[I] := False;
  SetLength(D.Hats, Integer(ADesc.NumHats));
  for I := 0 to High(D.Hats) do
    D.Hats[I] := 0;
  SetLength(D.Balls, Integer(ADesc.NumBalls));
  for I := 0 to High(D.Balls) do
  begin
    D.Balls[I].DX := 0;
    D.Balls[I].DY := 0;
  end;

  D.InstanceID := Core.NextInstanceID;
  SetLength(FDevices, Length(FDevices) + 1);
  FDevices[High(FDevices)] := D;
  Core.DeviceAdded(D.InstanceID);
  Result := D.InstanceID;
end;

procedure TPMLVirtualJoystickBackend.DetachVirtual(AID: TPMLJoystickID);
var
  Idx: Integer;
  Dev: TVirtualData;
begin
  Idx := VirtualFindIndex(FDevices, AID);
  if Idx < 0 then
    raise EPMLArgument.Create('Virtual joystick data not found');
  // 先に一覧から外して後始末し、そのあとで Core に知らせる（検査が見ている順序）。
  Dev := FDevices[Idx];
  VirtualRemoveAt(FDevices, Idx);
  VirtualRelease(Dev);
  Core.DeviceRemoved(AID);
end;

function TPMLVirtualJoystickBackend.IsVirtual(AID: TPMLJoystickID): Boolean;
begin
  Result := VirtualFindIndex(FDevices, AID) >= 0;
end;

procedure TPMLVirtualJoystickBackend.SetVirtualAxis(AJoystick: TPMLJoystick; AAxis: Integer; AValue: SmallInt);
var
  D: TVirtualData;
begin
  D := VirtualDataOf(AJoystick);
  if (AAxis < 0) or (AAxis >= Length(D.Axes)) then
    raise EPMLArgument.Create('Invalid axis index');
  D.Axes[AAxis] := AValue;
  D.Changes := D.Changes + [TPMLVirtualChange.VCAxes];
end;

procedure TPMLVirtualJoystickBackend.SetVirtualBall(AJoystick: TPMLJoystick; ABall: Integer; AXRel, AYRel: SmallInt);
var
  D: TVirtualData;
begin
  D := VirtualDataOf(AJoystick);
  if (ABall < 0) or (ABall >= Length(D.Balls)) then
    raise EPMLArgument.Create('Invalid ball index');
  D.Balls[ABall].DX := VirtualClamp16(D.Balls[ABall].DX + AXRel);
  D.Balls[ABall].DY := VirtualClamp16(D.Balls[ABall].DY + AYRel);
  D.Changes := D.Changes + [TPMLVirtualChange.VCBalls];
end;

procedure TPMLVirtualJoystickBackend.SetVirtualButton(AJoystick: TPMLJoystick; AButton: Integer; ADown: Boolean);
var
  D: TVirtualData;
begin
  D := VirtualDataOf(AJoystick);
  if (AButton < 0) or (AButton >= Length(D.Buttons)) then
    raise EPMLArgument.Create('Invalid button index');
  D.Buttons[AButton] := ADown;
  D.Changes := D.Changes + [TPMLVirtualChange.VCButtons];
end;

procedure TPMLVirtualJoystickBackend.SetVirtualHat(AJoystick: TPMLJoystick; AHat: Integer; AValue: Byte);
var
  D: TVirtualData;
begin
  D := VirtualDataOf(AJoystick);
  if (AHat < 0) or (AHat >= Length(D.Hats)) then
    raise EPMLArgument.Create('Invalid hat index');
  D.Hats[AHat] := AValue;
  D.Changes := D.Changes + [TPMLVirtualChange.VCHats];
end;

function CreateBackend(ACore: TPMLJoystickCore): TPMLJoystickBackend;
begin
  Result := TPMLVirtualJoystickBackend.Create(ACore);
end;

initialization
  PMLRegisterJoystickBackend('virtual', 10, @CreateBackend);

end.
