{
  PaPiMeLa.Platform.Evdev — Linux の入力（evdev と旧 js）のカーネル ABI

  Origin : partially ported from SDL (src/core/linux/SDL_evdev_capabilities.c, SDL_evdev_capabilities.h)
           Scope: SDL_EVDEV_GuessDeviceClass（evdev の能力のビットから機器の種類を決める）、SDL_UDEV_deviceclass、
           test_bit。ABI の定数・構造体・ioctl 番号は <linux/input.h> と <linux/joystick.h> を写した。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §9.4、§11 #18

  WHAT:
    カーネルの入力の ABI（ライブラリなし）。定数は src/generated/evdev_consts.inc（tools/genevdev.bb が C で作る）、
    構造体は同じ並びのレコード（64 ビットの Linux）、ioctl の番号は _IOC の計算を関数にした。
    ビットの集合は、ioctl が返すバイト列そのまま（Little endian の unsigned long の配列と同じ並び）。

  WHY:
    ABI は写しが合っているかを本物のヘッダで確かめる（test/test_evdev.pas が、C の出力 test/evdev_abi_expected.inc と比べる）。
    ioctl は FPC の BaseUnix.FpIOCtl で呼ぶ。

  RESOLVED:
    - 64 ビットの Linux だけ（input_event の時刻は 16 バイト）
    - ビットの集合の大きさは unsigned long 単位に切り上げる（NBITS）。SDL と同じ判定を、同じ配列の形で行う

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.Evdev;

{$I papimela.inc}
{$packrecords c}

interface

uses
  SysUtils, BaseUnix, ctypes;

{$I generated/evdev_consts.inc}

const
  // 機器の種類（SDL_UDEV_deviceclass。足し合わせて使う）
  PML_UDEV_DEVICE_UNKNOWN       = $0000;
  PML_UDEV_DEVICE_MOUSE         = $0001;
  PML_UDEV_DEVICE_KEYBOARD      = $0002;
  PML_UDEV_DEVICE_JOYSTICK      = $0004;
  PML_UDEV_DEVICE_SOUND         = $0008;
  PML_UDEV_DEVICE_TOUCHSCREEN   = $0010;
  PML_UDEV_DEVICE_ACCELEROMETER = $0020;
  PML_UDEV_DEVICE_TOUCHPAD      = $0040;
  PML_UDEV_DEVICE_HAS_KEYS      = $0080;
  PML_UDEV_DEVICE_VIDEO_CAPTURE = $0100;

type
  // ビットの集合。ioctl の戻りのバイト列。
  TPMLBits = array of Byte;

  // struct input_id（EVIOCGID）
  TPMLInputID = record
    BusType: cuint16;
    Vendor : cuint16;
    Product: cuint16;
    Version: cuint16;
  end;

  // struct input_absinfo（EVIOCGABS）
  TPMLInputAbsInfo = record
    Value     : cint32;
    Minimum   : cint32;
    Maximum   : cint32;
    Fuzz      : cint32;
    Flat      : cint32;
    Resolution: cint32;
  end;

  // struct input_event（read / write）。時刻は struct timeval（64 ビット）
  TPMLInputEvent = record
    TimeSec : cint64;
    TimeUSec: cint64;
    EventType: cuint16;
    Code    : cuint16;
    Value   : cint32;
  end;

  // struct js_event（旧 js の read）
  TPMLJsEvent = record
    Time  : cuint32;
    Value : cint16;
    EventType: cuint8;
    Number: cuint8;
  end;

  // struct ff_envelope
  TPMLFFEnvelope = record
    AttackLength: cuint16;
    AttackLevel : cuint16;
    FadeLength  : cuint16;
    FadeLevel   : cuint16;
  end;

  // struct ff_condition_effect（ばね・ダンパ・慣性・摩擦。共用体の中で 2 本ぶん）
  TPMLFFCondition = record
    RightSaturation: cuint16;
    LeftSaturation : cuint16;
    RightCoeff     : cint16;
    LeftCoeff      : cint16;
    Deadband       : cuint16;
    Center         : cint16;
  end;

  { struct ff_effect（EVIOCSFF）。共用体の部分は、ランブル・周期的・一定・傾斜・条件の効果を名前にした。
    ID は -1 で新しく割り当てさせる。 }
  TPMLFFEffect = record
    EffectType: cuint16;
    ID        : cint16;
    Direction : cuint16;
    TriggerButton  : cuint16;
    TriggerInterval: cuint16;
    ReplayLength   : cuint16;
    ReplayDelay    : cuint16;
    case Integer of
      0: (RumbleStrong: cuint16;      // ff_rumble_effect.strong_magnitude
          RumbleWeak  : cuint16);     // ff_rumble_effect.weak_magnitude
      1: (PeriodicWaveform : cuint16;
          PeriodicPeriod   : cuint16;
          PeriodicMagnitude: cint16;
          PeriodicOffset   : cint16;
          PeriodicPhase    : cuint16;
          EnvAttackLength  : cuint16;
          EnvAttackLevel   : cuint16;
          EnvFadeLength    : cuint16;
          EnvFadeLevel     : cuint16;
          CustomLen        : cuint32;
          CustomData       : Pointer);
      2: (Padding: array[0..31] of Byte);   // union の大きさ
      3: (ConstantLevel   : cint16;         // ff_constant_effect
          ConstantEnvelope: TPMLFFEnvelope);
      4: (RampStart   : cint16;             // ff_ramp_effect
          RampEnd     : cint16;
          RampEnvelope: TPMLFFEnvelope);
      5: (Condition: array[0..1] of TPMLFFCondition);   // ff_condition_effect[2]
  end;

// ---- ioctl の番号（_IOC の計算）
function PMLIOC(ADir, AType, ANr, ASize: culong): culong;
function PMLEVIOCGID: culong;
function PMLEVIOCGBIT(AEvent: Integer; ALength: Integer): culong;
function PMLEVIOCGABS(AAxis: Integer): culong;
function PMLEVIOCGNAME(ALength: Integer): culong;
function PMLEVIOCGUNIQ(ALength: Integer): culong;
function PMLEVIOCGPROP(ALength: Integer): culong;
function PMLEVIOCGKEY(ALength: Integer): culong;
function PMLEVIOCSFF: culong;
function PMLEVIOCRMFF: culong;
function PMLEVIOCGEFFECTS: culong;
function PMLJSIOCGAXES: culong;
function PMLJSIOCGBUTTONS: culong;
function PMLJSIOCGNAME(ALength: Integer): culong;
function PMLJSIOCGBTNMAP: culong;
function PMLJSIOCGAXMAP: culong;

// ---- ビットの集合
{ ビット ABit が立っているか（test_bit）。範囲外は False。 }
function PMLTestBit(const ABits: TPMLBits; ABit: Integer): Boolean;
{ 立っているビットがあるか（先頭から ACount ビットの範囲）。 }
function PMLAnyBit(const ABits: TPMLBits; AFirst, AEnd: Integer): Boolean;
{ ビットの集合の大きさ（バイト数）。unsigned long の単位に切り上げる（NBITS(n) * 8）。 }
function PMLBitsLength(ABitCount: Integer): Integer;

{ evdev の能力のビットから機器の種類を決める（SDL_EVDEV_GuessDeviceClass）。戻りは PML_UDEV_DEVICE_ を足したもの。 }
function PMLEvdevGuessDeviceClass(const AProps, AEv, AAbs, AKey, ARel: TPMLBits): Integer;

implementation

const
  IOC_NONE  = 0;
  IOC_WRITE = 1;
  IOC_READ  = 2;
  IOC_NRSHIFT   = 0;
  IOC_TYPESHIFT = 8;
  IOC_SIZESHIFT = 16;
  IOC_DIRSHIFT  = 30;

function PMLIOC(ADir, AType, ANr, ASize: culong): culong;
begin
  Result := (ADir shl IOC_DIRSHIFT) or (AType shl IOC_TYPESHIFT) or (ANr shl IOC_NRSHIFT) or (ASize shl IOC_SIZESHIFT);
end;

function PMLEVIOCGID: culong;
begin
  Result := PMLIOC(IOC_READ, Ord('E'), $02, SizeOf(TPMLInputID));
end;

function PMLEVIOCGBIT(AEvent: Integer; ALength: Integer): culong;
begin
  Result := PMLIOC(IOC_READ, Ord('E'), $20 + AEvent, ALength);
end;

function PMLEVIOCGABS(AAxis: Integer): culong;
begin
  Result := PMLIOC(IOC_READ, Ord('E'), $40 + AAxis, SizeOf(TPMLInputAbsInfo));
end;

function PMLEVIOCGNAME(ALength: Integer): culong;
begin
  Result := PMLIOC(IOC_READ, Ord('E'), $06, ALength);
end;

function PMLEVIOCGUNIQ(ALength: Integer): culong;
begin
  Result := PMLIOC(IOC_READ, Ord('E'), $08, ALength);
end;

function PMLEVIOCGPROP(ALength: Integer): culong;
begin
  Result := PMLIOC(IOC_READ, Ord('E'), $09, ALength);
end;

function PMLEVIOCGKEY(ALength: Integer): culong;
begin
  Result := PMLIOC(IOC_READ, Ord('E'), $18, ALength);
end;

function PMLEVIOCSFF: culong;
begin
  Result := PMLIOC(IOC_WRITE, Ord('E'), $80, SizeOf(TPMLFFEffect));
end;

function PMLEVIOCRMFF: culong;
begin
  Result := PMLIOC(IOC_WRITE, Ord('E'), $81, SizeOf(cint));
end;

function PMLEVIOCGEFFECTS: culong;
begin
  Result := PMLIOC(IOC_READ, Ord('E'), $84, SizeOf(cint));
end;

function PMLJSIOCGAXES: culong;
begin
  Result := PMLIOC(IOC_READ, Ord('j'), $11, SizeOf(cuint8));
end;

function PMLJSIOCGBUTTONS: culong;
begin
  Result := PMLIOC(IOC_READ, Ord('j'), $12, SizeOf(cuint8));
end;

function PMLJSIOCGNAME(ALength: Integer): culong;
begin
  Result := PMLIOC(IOC_READ, Ord('j'), $13, ALength);
end;

function PMLJSIOCGBTNMAP: culong;
begin
  // __u16[KEY_MAX - BTN_MISC + 1]
  Result := PMLIOC(IOC_READ, Ord('j'), $34, 2 * (KEY_MAX - BTN_MISC + 1));
end;

function PMLJSIOCGAXMAP: culong;
begin
  // __u8[ABS_CNT]
  Result := PMLIOC(IOC_READ, Ord('j'), $32, ABS_CNT);
end;

function PMLTestBit(const ABits: TPMLBits; ABit: Integer): Boolean;
begin
  if (ABit < 0) or ((ABit shr 3) >= Length(ABits)) then
    Exit(False);
  Result := ((ABits[ABit shr 3] shr (ABit and 7)) and 1) <> 0;
end;

function PMLAnyBit(const ABits: TPMLBits; AFirst, AEnd: Integer): Boolean;
var
  I: Integer;
begin
  for I := AFirst to AEnd - 1 do
    if PMLTestBit(ABits, I) then
      Exit(True);
  Result := False;
end;

function PMLBitsLength(ABitCount: Integer): Integer;
begin
  // NBITS(x) = ((x - 1) / BITS_PER_LONG) + 1。1 つが 8 バイト
  Result := (((ABitCount - 1) div 64) + 1) * 8;
end;

function PMLEvdevGuessDeviceClass(const AProps, AEv, AAbs, AKey, ARel: TPMLBits): Integer;
const
  // BTN_MISC より上のキーの範囲（始めを含み、終わりを含まない）
  HighKeyStart: array[0..1] of Integer = (KEY_OK, KEY_ALS_TOGGLE);
  HighKeyEnd  : array[0..1] of Integer = (BTN_DPAD_UP, BTN_TRIGGER_HAPPY);
var
  DevClass, Block, I: Integer;
  Found: Boolean;
  KeyboardMask: LongWord;
  First32: LongWord;
begin
  DevClass := 0;
  // カーネルが加速度計と言っていれば、そのとおりにする
  if PMLTestBit(AProps, INPUT_PROP_ACCELEROMETER) then
    Exit(PML_UDEV_DEVICE_ACCELEROMETER);
  // ポインティングスティックはマウスと同じに扱う
  if PMLTestBit(AProps, INPUT_PROP_POINTING_STICK) then
    Exit(PML_UDEV_DEVICE_MOUSE);
  // ボタンパッドはタッチパッドと同じに扱う
  if PMLTestBit(AProps, INPUT_PROP_TOPBUTTONPAD) or PMLTestBit(AProps, INPUT_PROP_BUTTONPAD)
  or PMLTestBit(AProps, INPUT_PROP_SEMI_MT) then
    Exit(PML_UDEV_DEVICE_TOUCHPAD);
  // X・Y・Z があってボタンが無ければ加速度計
  if PMLTestBit(AEv, EV_ABS) and PMLTestBit(AAbs, ABS_X) and PMLTestBit(AAbs, ABS_Y) and PMLTestBit(AAbs, ABS_Z)
  and not PMLTestBit(AEv, EV_KEY) then
    Exit(PML_UDEV_DEVICE_ACCELEROMETER);
  // RX・RY・RZ があってボタンが無ければジャイロか加速度計（区別しない）
  if PMLTestBit(AEv, EV_ABS) and PMLTestBit(AAbs, ABS_RX) and PMLTestBit(AAbs, ABS_RY) and PMLTestBit(AAbs, ABS_RZ)
  and not PMLTestBit(AEv, EV_KEY) then
    Exit(PML_UDEV_DEVICE_ACCELEROMETER);

  if PMLTestBit(AEv, EV_ABS) and PMLTestBit(AAbs, ABS_X) and PMLTestBit(AAbs, ABS_Y) then
  begin
    if PMLTestBit(AKey, BTN_STYLUS) or PMLTestBit(AKey, BTN_TOOL_PEN) then
    begin
      // ID_INPUT_TABLET
    end
    else if PMLTestBit(AKey, BTN_TOOL_FINGER) and not PMLTestBit(AKey, BTN_TOOL_PEN) then
      DevClass := DevClass or PML_UDEV_DEVICE_TOUCHPAD
    else if PMLTestBit(AKey, BTN_MOUSE) then
      DevClass := DevClass or PML_UDEV_DEVICE_MOUSE
    else if PMLTestBit(AKey, BTN_TOUCH) then
      DevClass := DevClass or PML_UDEV_DEVICE_TOUCHSCREEN;

    if PMLTestBit(AKey, BTN_TRIGGER) or PMLTestBit(AKey, BTN_A) or PMLTestBit(AKey, BTN_1)
    or PMLTestBit(AAbs, ABS_RX) or PMLTestBit(AAbs, ABS_RY) or PMLTestBit(AAbs, ABS_RZ)
    or PMLTestBit(AAbs, ABS_THROTTLE) or PMLTestBit(AAbs, ABS_RUDDER) or PMLTestBit(AAbs, ABS_WHEEL)
    or PMLTestBit(AAbs, ABS_GAS) or PMLTestBit(AAbs, ABS_BRAKE) then
      DevClass := DevClass or PML_UDEV_DEVICE_JOYSTICK;
  end;

  if PMLTestBit(AEv, EV_REL) and PMLTestBit(ARel, REL_X) and PMLTestBit(ARel, REL_Y) and PMLTestBit(AKey, BTN_MOUSE) then
    DevClass := DevClass or PML_UDEV_DEVICE_MOUSE;

  if PMLTestBit(AEv, EV_KEY) then
  begin
    // BTN_MISC より下に 1 つでもキーがあるか。無ければ上の範囲を調べる
    Found := PMLAnyBit(AKey, 0, (BTN_MISC div 64) * 64);
    if not Found then
      for Block := 0 to High(HighKeyStart) do
        for I := HighKeyStart[Block] to HighKeyEnd[Block] - 1 do
          if PMLTestBit(AKey, I) then
          begin
            Found := True;
            Break;
          end;
    if Found then
      DevClass := DevClass or PML_UDEV_DEVICE_HAS_KEYS;
  end;

  // 先頭の 32 ビットは ESC・数字・Q から D。全部あれば本格的なキーボード（KEY_RESERVED は見ない）
  KeyboardMask := $FFFFFFFE;
  First32 := 0;
  for I := 0 to 3 do
    if I < Length(AKey) then
      First32 := First32 or (LongWord(AKey[I]) shl (8 * I));
  if (First32 and KeyboardMask) = KeyboardMask then
    DevClass := DevClass or PML_UDEV_DEVICE_KEYBOARD;

  Result := DevClass;
end;

end.
