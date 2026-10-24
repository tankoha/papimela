{
  PaPiMeLa.Joystick.Backend — ジョイスティックのバックエンドの抽象と、開いたジョイスティック

  Origin : ported from SDL (src/joystick/SDL_sysjoystick.h, src/joystick/SDL_joystick.c,
           src/joystick/SDL_joystick_c.h)
           Scope: SDL_JoystickDriver の 21 個の入り口（Init・GetCount・Detect・IsDevicePresent・
           GetDeviceName / Path / PlayerIndex / GUID / InstanceID・Open・Rumble・RumbleTriggers・SetLED・
           SendEffect・SetSensorsEnabled・Update・Close・Quit・GetGamepadMapping）、SDL_Joystick の中身
           （軸・ボール・ハット・ボタン、軸の初期値の扱い、ランブルとその期限、LED、電源の情報）、
           バックエンドがコアを呼ぶ口（SDL_PrivateJoystickAdded / Removed と SDL_SendJoystickAxis / Ball /
           Hat / Button / PowerInfo）、ゲームパッドのマッピング（SDL_GamepadMapping）の型。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.5、§4.6、§11 #59

  WHAT:
    具象バックエンド（Linux の evdev、仮想）が派生する TPMLJoystickBackend と、コア
    （PaPiMeLa.Joystick の TPMLJoystickSystem）が実装してバックエンドに渡す TPMLJoystickCore、
    アプリが Open して使う TPMLJoystick。

  WHY:
    SDL のバックエンドは中核の関数（SDL_PrivateJoystickAdded など）を直接呼ぶ。papimela では
    中核が公開層にあるので、バックエンドの単位が公開層を uses すると循環する。中核の口を
    抽象クラス TPMLJoystickCore にしてここに置き、公開層が実装する（オーディオと同じ）。

  RESOLVED:
    - SDL と同じく、バックエンドが機器の一覧を持ち（添字で指す）、コアは ID で指す。ID は
      コアが振る（NextInstanceID）
    - 開いたジョイスティックは、同じ ID を何度 Open しても同じオブジェクトで、Close した回数が
      Open の回数に達すると壊れる（SDL の ref_count と同じ）。Free しない（Close を使う）
    - 軸の値が最初の 1 回だけ「静止の位置」として扱われる規則（has_initial_value など）と、
      ShanWan の PS3 のコントローラが要る揺れの許容（32767 / 80）は SDL のまま

  NOT RESOLVED:
    - タッチパッド・センサー・静電容量（capsense）と、センサーの融合は無い。仮想ジョイスティックの
      desc に出てきたら断る
    - Steam の仮想ゲームパッド、HIDAPI、ROG Ally は無い

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Joystick.Backend;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Joystick.GUID;

type
  { ジョイスティックの ID（SDL_JoystickID）。接続のたびに増える番号で、0 は「無い」。 }
  TPMLJoystickID = type LongWord;
  TPMLJoystickIDs = array of TPMLJoystickID;

  // ジョイスティックの種類（SDL_JoystickType。値は SDL と同じ）。
  TPMLJoystickType = (Unknown, Gamepad, Wheel, ArcadeStick, FlightStick, DancePad,
    Guitar, DrumKit, ArcadePad, Throttle);

  // 接続の様子（SDL_JoystickConnectionState。Invalid は SDL の -1）。
  TPMLJoystickConnectionState = (Invalid, Unknown, Wired, Wireless);

  // ゲームパッドのボタン（SDL_GamepadButton。並びと値は SDL と同じ。SDL の INVALID = -1 は列挙の外）。
  TPMLGamepadButton = (South, East, West, North, Back, Guide, Start, LeftStick, RightStick,
    LeftShoulder, RightShoulder, DPadUp, DPadDown, DPadLeft, DPadRight, Misc1,
    RightPaddle1, LeftPaddle1, RightPaddle2, LeftPaddle2, Touchpad, Misc2, Misc3, Misc4, Misc5, Misc6);

  // ゲームパッドの軸（SDL_GamepadAxis）。
  TPMLGamepadAxis = (LeftX, LeftY, RightX, RightY, LeftTrigger, RightTrigger);

  // 入力 1 つの割り当て先の種類（EMappingKind）。
  TPMLMappingKind = (None, Button, Axis, Hat);

  { 入力 1 つの割り当て（SDL_InputMapping）。Kind が Hat のとき Target は ハット番号 << 4 | 方向（SDL の
    mapping 文字列の「h0.1」の意味）。 }
  TPMLInputMapping = record
    Kind              : TPMLMappingKind;
    Target            : Byte;
    AxisReversed      : Boolean;
    HalfAxisPositive  : Boolean;
    HalfAxisNegative  : Boolean;
  end;

  { バックエンドが言う、自動のゲームパッドのマッピング（SDL_GamepadMapping）。 }
  TPMLGamepadMapping = record
    Buttons: array[TPMLGamepadButton] of TPMLInputMapping;
    Axes   : array[TPMLGamepadAxis] of TPMLInputMapping;
  end;

  // ジョイスティックの能力（SDL_PROP_JOYSTICK_CAP_xxx_BOOLEAN）。
  TPMLJoystickCapability = (MonoLED, RGBLED, PlayerLED, Rumble, TriggerRumble);
  TPMLJoystickCapabilities = set of TPMLJoystickCapability;

const
  // ハットの値（SDL_HAT_xxx）。
  PML_HAT_CENTERED  = $00;
  PML_HAT_UP        = $01;
  PML_HAT_RIGHT     = $02;
  PML_HAT_DOWN      = $04;
  PML_HAT_LEFT      = $08;
  PML_HAT_RIGHTUP   = PML_HAT_RIGHT or PML_HAT_UP;
  PML_HAT_RIGHTDOWN = PML_HAT_RIGHT or PML_HAT_DOWN;
  PML_HAT_LEFTUP    = PML_HAT_LEFT or PML_HAT_UP;
  PML_HAT_LEFTDOWN  = PML_HAT_LEFT or PML_HAT_DOWN;

  // 軸の値の範囲（SDL_JOYSTICK_AXIS_MIN / MAX）。
  PML_JOYSTICK_AXIS_MIN = -32768;
  PML_JOYSTICK_AXIS_MAX = 32767;

  // ランブルの長さの上限（ミリ秒。SDL_MAX_RUMBLE_DURATION_MS）と、再送の間隔、LED を繰り返す最短の間隔。
  PML_MAX_RUMBLE_DURATION_MS = $FFFF;
  PML_RUMBLE_RESEND_MS       = 2000;
  PML_LED_MIN_REPEAT_MS      = 5000;

type
  TPMLJoystick = class;
  TPMLJoystickBackend = class;

  { コアの口（バックエンドが呼ぶ）。PaPiMeLa.Joystick の TPMLJoystickSystem が実装する。
    ロックはコアが持つ再帰ミューテックスで、バックエンドの入り口はロックを持ったまま呼ばれる
    （SDL の SDL_LockJoysticks と同じ）。バックエンドが自分のスレッドから呼ぶときは先に Lock する。 }
  TPMLJoystickCore = class abstract(TPMLSystemObject)
  public
    procedure Lock; virtual; abstract;
    procedure Unlock; virtual; abstract;
    // ジョイスティックの ID を新しく振る（SDL_GetNextObjectID）。
    function  NextInstanceID: TPMLJoystickID; virtual; abstract;
    { 機器が足された（SDL_PrivateJoystickAdded）。player index の割り当てと JoystickAdded を出す。 }
    procedure DeviceAdded(AID: TPMLJoystickID); virtual; abstract;
    { 機器が外れた（SDL_PrivateJoystickRemoved）。開いていれば全部を静止に戻して Connected を False にし、
      JoystickRemoved を出す。 }
    procedure DeviceRemoved(AID: TPMLJoystickID); virtual; abstract;
    { 状態の送り込み（SDL_SendJoystickAxis / Ball / Hat / Button）。ATimestamp はナノ秒（0 でない）。
      範囲外の番号や、前と同じ値は何もしない。イベントが無効なら状態だけ更新する。 }
    procedure SendAxis(ATimestamp: UInt64; AJoystick: TPMLJoystick; AAxis: Byte; AValue: SmallInt); virtual; abstract;
    procedure SendBall(ATimestamp: UInt64; AJoystick: TPMLJoystick; ABall: Byte; AXRel, AYRel: SmallInt); virtual; abstract;
    procedure SendHat(ATimestamp: UInt64; AJoystick: TPMLJoystick; AHat: Byte; AValue: Byte); virtual; abstract;
    procedure SendButton(ATimestamp: UInt64; AJoystick: TPMLJoystick; AButton: Byte; ADown: Boolean); virtual; abstract;
    // 電源の情報（SDL_SendJoystickPowerInfo）。変わったときだけ JoystickBatteryUpdated を出す。
    procedure SendPowerInfo(AJoystick: TPMLJoystick; AState: TPMLPowerState; APercent: Integer); virtual; abstract;
    // 時刻（ナノ秒と、ミリ秒。SDL_GetTicksNS / SDL_GetTicks）。
    function  TimestampNS: UInt64; virtual; abstract;
    function  TicksMS: UInt64; virtual; abstract;
    // ヒントの効いている値（空なら ''）。
    function  Hint(const AName: String): String; virtual; abstract;
    // この機器を使わないか（SDL_ShouldIgnoreJoystick。禁止の表など）。
    function  ShouldIgnoreDevice(AVendor, AProduct, AVersion: Word; const AName: String): Boolean; virtual; abstract;
    // 他のバックエンドが同じ機器を持っているか（SDL_JoystickHandledByAnotherDriver）。ABackend より先のもの。
    function  HandledByAnotherBackend(ABackend: TPMLJoystickBackend; AVendor, AProduct, AVersion: Word;
      const AName: String): Boolean; virtual; abstract;
    // 軸が全部 0 を中心にしている機器か（SDL_JoystickAxesCenteredAtZero の表の分）。
    function  IsZeroCenteredDevice(AVendor, AProduct: Word): Boolean; virtual; abstract;
    // 自動のゲームパッド（マッピングがある機器か。SDL_IsGamepad）。
    function  IsGamepad(AID: TPMLJoystickID): Boolean; virtual; abstract;
    // 開いているジョイスティックを閉じる（TPMLJoystick.Close から）。
    procedure CloseJoystick(AJoystick: TPMLJoystick); virtual; abstract;
    // player index（無ければ -1）と、その設定（SDL_SetJoystickIDForPlayerIndex）。
    function  PlayerIndexOf(AID: TPMLJoystickID): Integer; virtual; abstract;
    function  SetPlayerIndexOf(AID: TPMLJoystickID; APlayerIndex: Integer): Boolean; virtual; abstract;
    // 種類（SDL_GetJoystickGUIDType）。
    function  JoystickTypeOf(const AGUID: TPMLGUID): TPMLJoystickType; virtual; abstract;
  end;

  // 軸 1 本の状態（SDL_JoystickAxisInfo）。
  TPMLJoystickAxisInfo = record
    InitialValue    : SmallInt;    // 最初に見た位置
    Value           : SmallInt;    // 今の位置
    Zero            : SmallInt;    // 静止の位置（トリガーは -32768）
    HasInitialValue : Boolean;     // もう値を見たか
    HasSecondValue  : Boolean;     // 2 つ目の値を見たか
    SentInitialValue: Boolean;     // 最初の値を送ったか
    SendingInitialValue: Boolean;  // 最初の値を送っている最中か
  end;

  // ボールの動きの積み上げ（SDL_JoystickBallData）。読むと 0 に戻る。
  TPMLJoystickBallData = record
    DX, DY: Integer;
  end;

  { 開いたジョイスティック（SDL_Joystick）。TPMLJoystickSystem.Open が返す。

    「バックエンドも触る」欄は Open の中で数を決める。それ以外はコアが書く。アプリは
    Close で返す（Free しない。複数の持ち主が同じ ID を Open すると、同じオブジェクトが共有される）。 }
  TPMLJoystick = class(TPMLOwnedObject)
  strict private
    FCore            : TPMLJoystickCore;
    FBackend         : TPMLJoystickBackend;
    FID              : TPMLJoystickID;
    FName            : String;
    FPath            : String;
    FSerial          : String;
    FGUID            : TPMLGUID;
    FFirmwareVersion : Word;
    FAttached        : Boolean;
    FConnectionState : TPMLJoystickConnectionState;
    FBatteryState    : TPMLPowerState;
    FBatteryPercent  : Integer;
    FCapabilities    : TPMLJoystickCapabilities;
    FNumAxes, FNumBalls, FNumHats, FNumButtons: Integer;
    FAxes            : array of TPMLJoystickAxisInfo;
    FBalls           : array of TPMLJoystickBallData;
    FHats            : array of Byte;
    FButtons         : array of Boolean;
    FSwapFaceButtons : Boolean;
    FIsVirtual       : Boolean;
    FUpdateComplete  : UInt64;
    FLowFrequencyRumble, FHighFrequencyRumble: Word;
    FRumbleExpiration, FRumbleResend: UInt64;
    FLeftTriggerRumble, FRightTriggerRumble: Word;
    FTriggerRumbleExpiration, FTriggerRumbleResend: UInt64;
    FLEDRed, FLEDGreen, FLEDBlue: Byte;
    FLEDExpiration   : UInt64;
    FRefCount        : Integer;
    FHwData          : TObject;
    function  GetNumAxes: Integer;
    function  GetNumBalls: Integer;
    function  GetNumHats: Integer;
    function  GetNumButtons: Integer;
    function  GetAxis(AIndex: Integer): SmallInt;
    function  GetHat(AIndex: Integer): Byte;
    function  GetButton(AIndex: Integer): Boolean;
    function  GetConnected: Boolean;
    function  GetPlayerIndex: Integer;
    procedure SetPlayerIndex(AValue: Integer);
    function  GetJoystickType: TPMLJoystickType;
    function  GetVendorID: Word;
    function  GetProductID: Word;
    function  GetProductVersion: Word;
  protected
    procedure DetachFromOwner; override;
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject; ACore: TPMLJoystickCore;
      ABackend: TPMLJoystickBackend; AID: TPMLJoystickID);
    destructor Destroy; override;

    { ---- アプリが使う ---- }
    { 閉じる（SDL_CloseJoystick）。Open の回数だけ呼ぶと壊れる。鳴らしているランブルは止める。 }
    procedure Close;

    // 軸の今の値（SDL_GetJoystickAxis）。範囲外は EPMLArgument。
    function  AxisInitialState(AIndex: Integer; out AState: SmallInt): Boolean;
    { ボールの動き（前に読んでからの積み上げ）。読むと 0 に戻る。範囲外は EPMLArgument。 }
    procedure ReadBall(AIndex: Integer; out ADX, ADY: Integer);

    { ランブル（SDL_RumbleJoystick）。ALow / AHigh は 0..65535、ADurationMS は 0 で「止めるまで」。
      機器が対応しなければ False。長さは 65535 ミリ秒で頭打ち。 }
    function  Rumble(ALow, AHigh: Word; ADurationMS: Cardinal): Boolean;
    function  RumbleTriggers(ALeft, ARight: Word; ADurationMS: Cardinal): Boolean;
    // LED の色（SDL_SetJoystickLED）。同じ色は 5 秒の間は機器へ送り直さない。
    function  SetLED(ARed, AGreen, ABlue: Byte): Boolean;
    // 機器へ決まった形の命令を送る（SDL_SendJoystickEffect）。
    function  SendEffect(AData: Pointer; ASize: Integer): Boolean;

    property ID              : TPMLJoystickID read FID;
    property Name            : String read FName;
    property Path            : String read FPath;
    property Serial          : String read FSerial write FSerial;
    property GUID            : TPMLGUID read FGUID;
    property VendorID        : Word read GetVendorID;
    property ProductID       : Word read GetProductID;
    property ProductVersion  : Word read GetProductVersion;
    property FirmwareVersion : Word read FFirmwareVersion write FFirmwareVersion;
    property JoystickType    : TPMLJoystickType read GetJoystickType;
    // 機器がまだ繋がっているか。外れても、このオブジェクトは Close するまで残る。
    property Connected       : Boolean read GetConnected;
    property ConnectionState : TPMLJoystickConnectionState read FConnectionState write FConnectionState;
    property BatteryState    : TPMLPowerState read FBatteryState;
    property BatteryPercent  : Integer read FBatteryPercent;
    property Capabilities    : TPMLJoystickCapabilities read FCapabilities;
    property PlayerIndex     : Integer read GetPlayerIndex write SetPlayerIndex;
    property IsVirtual       : Boolean read FIsVirtual;
    property NumAxes         : Integer read GetNumAxes;
    property NumBalls        : Integer read GetNumBalls;
    property NumHats         : Integer read GetNumHats;
    property NumButtons      : Integer read GetNumButtons;
    property Axes[AIndex: Integer]   : SmallInt read GetAxis;
    property Hats[AIndex: Integer]   : Byte read GetHat;
    property Buttons[AIndex: Integer]: Boolean read GetButton;

    { ---- バックエンドとコアが使う（アプリは触らない） ---- }
    // Open の中で、数を決める（SDL の joystick->naxes などへの代入）。
    procedure SetCounts(AAxes, ABalls, AHats, AButtons: Integer);
    // 能力を足す（SDL_PROP_JOYSTICK_CAP_xxx_BOOLEAN を true にする）。
    procedure AddCapability(ACapability: TPMLJoystickCapability);
    // コアが Open の最後に、名前・パス・GUID を写し、状態の置き場を作る。
    procedure Setup(const AName, APath: String; const AGUID: TPMLGUID; AIsVirtual: Boolean);
    procedure SetAttached(AValue: Boolean);
    procedure SetPower(AState: TPMLPowerState; APercent: Integer);
    function  RefAdd: Integer;
    function  RefRelease: Integer;
    // コアの状態の送り込みが、軸・ハット・ボタンの置き場を触る。
    function  AxisInfoPtr(AIndex: Integer): Pointer;
    function  BallPtr(AIndex: Integer): Pointer;
    function  HatPtr(AIndex: Integer): PByte;
    function  ButtonPtr(AIndex: Integer): PBoolean;
    // 期限の見張り（SDL_UpdateJoysticks の中の、ランブルの期限と再送）。
    procedure UpdateRumbleTimers;
    // 閉じる前に、鳴らしているランブルを止める（SDL_CloseJoystick の始め）。
    procedure StopRumbleForClose;
    // 最後に状態を送った時刻（ナノ秒。0 なら無い）。UpdateComplete のイベントに使う。
    property  UpdateComplete: UInt64 read FUpdateComplete write FUpdateComplete;
    property  SwapFaceButtons: Boolean read FSwapFaceButtons write FSwapFaceButtons;
    property  Backend: TPMLJoystickBackend read FBackend;
    property  HwData: TObject read FHwData write FHwData;
    property  Core: TPMLJoystickCore read FCore;
  end;

  { バックエンド（SDL_JoystickDriver）。機器の一覧を持ち、添字（0 から DeviceCount - 1）で指す。
    入り口はどれもコアのロックを持ったまま呼ばれる。 }
  TPMLJoystickBackend = class abstract
  strict private
    FCore: TPMLJoystickCore;
  protected
    FLastError: String;
    property Core: TPMLJoystickCore read FCore;
  public
    constructor Create(ACore: TPMLJoystickCore);
    // 名前（'linux'、'virtual'）。
    function  Name: String; virtual; abstract;
    // 始める（Init）。機器の一覧を作る。False ならこのバックエンドは使わない。
    function  Init: Boolean; virtual; abstract;
    // 今の機器の数（GetCount）。
    function  DeviceCount: Integer; virtual; abstract;
    // 溜まった抜き差しを処理する（Detect）。
    procedure Detect; virtual;
    // 同じ機器を持っているか（IsDevicePresent。他のバックエンドから聞かれる）。
    function  IsDevicePresent(AVendor, AProduct, AVersion: Word; const AName: String): Boolean; virtual;
    function  DeviceName(AIndex: Integer): String; virtual; abstract;
    // パス（無ければ ''）。
    function  DevicePath(AIndex: Integer): String; virtual;
    // 機器の player index（無ければ -1）と、その設定の通知。
    function  DevicePlayerIndex(AIndex: Integer): Integer; virtual;
    procedure SetDevicePlayerIndex(AIndex, APlayerIndex: Integer); virtual;
    function  DeviceGUID(AIndex: Integer): TPMLGUID; virtual; abstract;
    function  DeviceInstanceID(AIndex: Integer): TPMLJoystickID; virtual; abstract;
    { 開く（Open）。AJoystick.SetCounts で数を決め、能力を足す。失敗したら False にして LastError に理由。 }
    function  Open(AJoystick: TPMLJoystick; AIndex: Integer): Boolean; virtual; abstract;
    // 対応しなければ False（SDL_Unsupported）。
    function  Rumble(AJoystick: TPMLJoystick; ALow, AHigh: Word): Boolean; virtual;
    function  RumbleTriggers(AJoystick: TPMLJoystick; ALeft, ARight: Word): Boolean; virtual;
    function  SetLED(AJoystick: TPMLJoystick; ARed, AGreen, ABlue: Byte): Boolean; virtual;
    function  SendEffect(AJoystick: TPMLJoystick; AData: Pointer; ASize: Integer): Boolean; virtual;
    function  SetSensorsEnabled(AJoystick: TPMLJoystick; AEnabled: Boolean): Boolean; virtual;
    // 機器をたずねて、変化を Core.SendAxis などで送る（Update）。
    procedure Update(AJoystick: TPMLJoystick); virtual; abstract;
    procedure Close(AJoystick: TPMLJoystick); virtual; abstract;
    procedure Quit; virtual;
    // 自動のマッピング（GetGamepadMapping）。無ければ False。
    function  GamepadMapping(AIndex: Integer; out AMapping: TPMLGamepadMapping): Boolean; virtual;
    property  LastError: String read FLastError;
  end;

  { 仮想ジョイスティックの記述（SDL_VirtualJoystickDesc）。アプリが埋めて AttachVirtual に渡す。
    Name が空なら種類に合った名前（「Virtual Controller」など）になる。ButtonMask と AxisMask は
    ゲームパッドの種類のときに、どのボタン・軸を持つか（TPMLGamepadButton / TPMLGamepadAxis の
    順位のビット）。0 なら数から決める（SDL と同じ）。呼び出しは、仮想ジョイスティックが
    ある間、アプリのオブジェクトの手続きを呼ぶ。 }
  TPMLVirtualUpdateEvent = procedure of object;
  TPMLVirtualPlayerIndexEvent = procedure(APlayerIndex: Integer) of object;
  TPMLVirtualRumbleEvent = function(ALow, AHigh: Word): Boolean of object;
  TPMLVirtualLEDEvent = function(ARed, AGreen, ABlue: Byte): Boolean of object;
  TPMLVirtualEffectEvent = function(AData: Pointer; ASize: Integer): Boolean of object;
  TPMLVirtualSensorsEvent = function(AEnabled: Boolean): Boolean of object;
  TPMLVirtualCleanupEvent = procedure of object;

  TPMLVirtualJoystickDesc = record
    JoystickType: TPMLJoystickType;
    VendorID    : Word;
    ProductID   : Word;
    NumAxes     : Word;
    NumButtons  : Word;
    NumBalls    : Word;
    NumHats     : Word;
    ButtonMask  : LongWord;
    AxisMask    : LongWord;
    Name        : String;
    OnUpdate           : TPMLVirtualUpdateEvent;
    OnSetPlayerIndex   : TPMLVirtualPlayerIndexEvent;
    OnRumble           : TPMLVirtualRumbleEvent;
    OnRumbleTriggers   : TPMLVirtualRumbleEvent;
    OnSetLED           : TPMLVirtualLEDEvent;
    OnSendEffect       : TPMLVirtualEffectEvent;
    OnSetSensorsEnabled: TPMLVirtualSensorsEvent;
    OnCleanup          : TPMLVirtualCleanupEvent;
  end;

  { 仮想ジョイスティックを持つバックエンド（PaPiMeLa.Joystick.Virtual）の窓口。コア（TPMLJoystickSystem）が
    これを探して、AttachVirtual などを渡す。仮想の機器を持たない構成では見つからず、EPMLUnsupported になる。 }
  IPMLVirtualJoystickBackend = interface
    ['{5C2A9E14-7D83-4B61-A0F5-3E9D1B47C862}']
    // 足す（SDL_AttachVirtualJoystick）。記述が正しくなければ EPMLArgument。ID を返す。
    function  AttachVirtual(const ADesc: TPMLVirtualJoystickDesc): TPMLJoystickID;
    // 外す（SDL_DetachVirtualJoystick）。見つからなければ EPMLArgument。
    procedure DetachVirtual(AID: TPMLJoystickID);
    // 仮想の機器か（SDL_IsJoystickVirtual）。
    function  IsVirtual(AID: TPMLJoystickID): Boolean;
    // 状態を置く（SDL_SetJoystickVirtualAxis など）。範囲外は EPMLArgument。次の Update で送られる。
    procedure SetVirtualAxis(AJoystick: TPMLJoystick; AAxis: Integer; AValue: SmallInt);
    procedure SetVirtualBall(AJoystick: TPMLJoystick; ABall: Integer; AXRel, AYRel: SmallInt);
    procedure SetVirtualButton(AJoystick: TPMLJoystick; AButton: Integer; ADown: Boolean);
    procedure SetVirtualHat(AJoystick: TPMLJoystick; AHat: Integer; AValue: Byte);
  end;

  // 作るだけの関数。作れなければ（ライブラリが無いなど）例外を投げる。
  TPMLJoystickBackendFactory = function(ACore: TPMLJoystickCore): TPMLJoystickBackend;

{ ---- 登録 ----

  具象バックエンドは、自分のユニットの initialization で自分を登録する（ビデオ・オーディオと同じ）。
  ジョイスティックは、オーディオと違って登録されたバックエンドを全部同時に使う（SDL の
  SDL_joystick_drivers）。並びは優先度の大きい順、同じなら登録した順。名前は大文字小文字を区別せずに
  比べる。同じ名前を 2 度登録すると EPMLArgument。 }
procedure PMLRegisterJoystickBackend(const AName: String; APriority: Integer;
  AFactory: TPMLJoystickBackendFactory);
// 登録済みの名前を並べ順に返す。
function  PMLJoystickBackendNames: TStringArray;
// 名前の工場。登録されていなければ nil。
function  PMLFindJoystickBackend(const AName: String): TPMLJoystickBackendFactory;

// 空のマッピング（全部 None）。
function PMLEmptyGamepadMapping: TPMLGamepadMapping;

implementation

function PMLEmptyGamepadMapping: TPMLGamepadMapping;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

{ TPMLJoystick }

constructor TPMLJoystick.Create(AContextRef: TObject; AOwner: TPMLObject; ACore: TPMLJoystickCore;
  ABackend: TPMLJoystickBackend; AID: TPMLJoystickID);
begin
  inherited Create(AContextRef, AOwner);
  FCore := ACore;
  FBackend := ABackend;
  FID := AID;
  FAttached := True;
  FBatteryPercent := -1;
  FConnectionState := TPMLJoystickConnectionState.Invalid;
  FBatteryState := TPMLPowerState.Unknown;
  FLEDExpiration := ACore.TicksMS;
end;

destructor TPMLJoystick.Destroy;
begin
  inherited Destroy;
end;

procedure TPMLJoystick.DetachFromOwner;
begin
  inherited DetachFromOwner;
end;

procedure TPMLJoystick.SetCounts(AAxes, ABalls, AHats, AButtons: Integer);
begin
  FNumAxes := AAxes;
  FNumBalls := ABalls;
  FNumHats := AHats;
  FNumButtons := AButtons;
end;

procedure TPMLJoystick.AddCapability(ACapability: TPMLJoystickCapability);
begin
  Include(FCapabilities, ACapability);
end;

procedure TPMLJoystick.Setup(const AName, APath: String; const AGUID: TPMLGUID; AIsVirtual: Boolean);
var
  I: Integer;
  V, P, Ver, Crc: Word;
begin
  FName := AName;
  FPath := APath;
  FGUID := AGUID;
  FIsVirtual := AIsVirtual;
  SetLength(FAxes, FNumAxes);
  SetLength(FBalls, FNumBalls);
  SetLength(FHats, FNumHats);
  SetLength(FButtons, FNumButtons);
  if FNumAxes > 0 then
    FillChar(FAxes[0], FNumAxes * SizeOf(FAxes[0]), 0);
  if FNumBalls > 0 then
    FillChar(FBalls[0], FNumBalls * SizeOf(FBalls[0]), 0);
  if FNumHats > 0 then
    FillChar(FHats[0], FNumHats, 0);
  if FNumButtons > 0 then
    FillChar(FButtons[0], FNumButtons * SizeOf(FButtons[0]), 0);
  // 軸が全部 0 を中心にしていると分かっている機器は、静止の位置を探す処理を飛ばす
  PMLGetJoystickGUIDInfo(AGUID, V, P, Ver, Crc);
  if (FNumAxes = 2) or FCore.IsZeroCenteredDevice(V, P) then
    for I := 0 to FNumAxes - 1 do
      FAxes[I].HasInitialValue := True;
end;

procedure TPMLJoystick.SetAttached(AValue: Boolean);
begin
  FAttached := AValue;
end;

procedure TPMLJoystick.SetPower(AState: TPMLPowerState; APercent: Integer);
begin
  FBatteryState := AState;
  FBatteryPercent := APercent;
end;

function TPMLJoystick.RefAdd: Integer;
begin
  Inc(FRefCount);
  Result := FRefCount;
end;

function TPMLJoystick.RefRelease: Integer;
begin
  Dec(FRefCount);
  Result := FRefCount;
end;

function TPMLJoystick.AxisInfoPtr(AIndex: Integer): Pointer;
begin
  Result := @FAxes[AIndex];
end;

function TPMLJoystick.BallPtr(AIndex: Integer): Pointer;
begin
  Result := @FBalls[AIndex];
end;

function TPMLJoystick.HatPtr(AIndex: Integer): PByte;
begin
  Result := @FHats[AIndex];
end;

function TPMLJoystick.ButtonPtr(AIndex: Integer): PBoolean;
begin
  Result := @FButtons[AIndex];
end;

function TPMLJoystick.GetNumAxes: Integer;
begin
  Result := FNumAxes;
end;

function TPMLJoystick.GetNumBalls: Integer;
begin
  Result := FNumBalls;
end;

function TPMLJoystick.GetNumHats: Integer;
begin
  Result := FNumHats;
end;

function TPMLJoystick.GetNumButtons: Integer;
begin
  Result := FNumButtons;
end;

function TPMLJoystick.GetAxis(AIndex: Integer): SmallInt;
begin
  FCore.Lock;
  try
    if (AIndex < 0) or (AIndex >= FNumAxes) then
      raise EPMLArgument.CreateFmt('Joystick only has %d axes', [FNumAxes]);
    Result := FAxes[AIndex].Value;
  finally
    FCore.Unlock;
  end;
end;

function TPMLJoystick.AxisInitialState(AIndex: Integer; out AState: SmallInt): Boolean;
begin
  FCore.Lock;
  try
    if (AIndex < 0) or (AIndex >= FNumAxes) then
      raise EPMLArgument.CreateFmt('Joystick only has %d axes', [FNumAxes]);
    AState := FAxes[AIndex].InitialValue;
    Result := FAxes[AIndex].HasInitialValue;
  finally
    FCore.Unlock;
  end;
end;

function TPMLJoystick.GetHat(AIndex: Integer): Byte;
begin
  FCore.Lock;
  try
    if (AIndex < 0) or (AIndex >= FNumHats) then
      raise EPMLArgument.CreateFmt('Joystick only has %d hats', [FNumHats]);
    Result := FHats[AIndex];
  finally
    FCore.Unlock;
  end;
end;

procedure TPMLJoystick.ReadBall(AIndex: Integer; out ADX, ADY: Integer);
begin
  FCore.Lock;
  try
    if (AIndex < 0) or (AIndex >= FNumBalls) then
      raise EPMLArgument.CreateFmt('Joystick only has %d balls', [FNumBalls]);
    ADX := FBalls[AIndex].DX;
    ADY := FBalls[AIndex].DY;
    FBalls[AIndex].DX := 0;
    FBalls[AIndex].DY := 0;
  finally
    FCore.Unlock;
  end;
end;

function TPMLJoystick.GetButton(AIndex: Integer): Boolean;
begin
  FCore.Lock;
  try
    if (AIndex < 0) or (AIndex >= FNumButtons) then
      raise EPMLArgument.CreateFmt('Joystick only has %d buttons', [FNumButtons]);
    Result := FButtons[AIndex];
  finally
    FCore.Unlock;
  end;
end;

function TPMLJoystick.GetConnected: Boolean;
begin
  FCore.Lock;
  try
    Result := FAttached;
  finally
    FCore.Unlock;
  end;
end;

function TPMLJoystick.GetPlayerIndex: Integer;
begin
  Result := FCore.PlayerIndexOf(FID);
end;

procedure TPMLJoystick.SetPlayerIndex(AValue: Integer);
begin
  FCore.SetPlayerIndexOf(FID, AValue);
end;

function TPMLJoystick.GetJoystickType: TPMLJoystickType;
begin
  Result := FCore.JoystickTypeOf(FGUID);
end;

function TPMLJoystick.GetVendorID: Word;
var
  P, V, C: Word;
begin
  PMLGetJoystickGUIDInfo(FGUID, Result, P, V, C);
end;

function TPMLJoystick.GetProductID: Word;
var
  V, Ver, C: Word;
begin
  PMLGetJoystickGUIDInfo(FGUID, V, Result, Ver, C);
end;

function TPMLJoystick.GetProductVersion: Word;
var
  V, P, C: Word;
begin
  PMLGetJoystickGUIDInfo(FGUID, V, P, Result, C);
end;

procedure TPMLJoystick.Close;
begin
  FCore.CloseJoystick(Self);
end;

function TPMLJoystick.Rumble(ALow, AHigh: Word; ADurationMS: Cardinal): Boolean;
begin
  FCore.Lock;
  try
    if (ALow = FLowFrequencyRumble) and (AHigh = FHighFrequencyRumble) then
      Result := True      // 期限だけ更新する
    else
    begin
      Result := FBackend.Rumble(Self, ALow, AHigh);
      if Result then
      begin
        FRumbleResend := FCore.TicksMS + PML_RUMBLE_RESEND_MS;
        if FRumbleResend = 0 then
          FRumbleResend := 1;
      end
      else
        FRumbleResend := 0;
    end;
    if Result then
    begin
      FLowFrequencyRumble := ALow;
      FHighFrequencyRumble := AHigh;
      if ((ALow <> 0) or (AHigh <> 0)) and (ADurationMS <> 0) then
      begin
        if ADurationMS > PML_MAX_RUMBLE_DURATION_MS then
          ADurationMS := PML_MAX_RUMBLE_DURATION_MS;
        FRumbleExpiration := FCore.TicksMS + ADurationMS;
        if FRumbleExpiration = 0 then
          FRumbleExpiration := 1;
      end
      else
      begin
        FRumbleExpiration := 0;
        FRumbleResend := 0;
      end;
    end;
  finally
    FCore.Unlock;
  end;
end;

function TPMLJoystick.RumbleTriggers(ALeft, ARight: Word; ADurationMS: Cardinal): Boolean;
begin
  FCore.Lock;
  try
    if (ALeft = FLeftTriggerRumble) and (ARight = FRightTriggerRumble) then
      Result := True
    else
    begin
      Result := FBackend.RumbleTriggers(Self, ALeft, ARight);
      if Result then
      begin
        FTriggerRumbleResend := FCore.TicksMS + PML_RUMBLE_RESEND_MS;
        if FTriggerRumbleResend = 0 then
          FTriggerRumbleResend := 1;
      end
      else
        FTriggerRumbleResend := 0;
    end;
    if Result then
    begin
      FLeftTriggerRumble := ALeft;
      FRightTriggerRumble := ARight;
      if ((ALeft <> 0) or (ARight <> 0)) and (ADurationMS <> 0) then
      begin
        if ADurationMS > PML_MAX_RUMBLE_DURATION_MS then
          ADurationMS := PML_MAX_RUMBLE_DURATION_MS;
        FTriggerRumbleExpiration := FCore.TicksMS + ADurationMS;
      end
      else
      begin
        FTriggerRumbleExpiration := 0;
        FTriggerRumbleResend := 0;
      end;
    end;
  finally
    FCore.Unlock;
  end;
end;

function TPMLJoystick.SetLED(ARed, AGreen, ABlue: Byte): Boolean;
var
  Fresh: Boolean;
begin
  FCore.Lock;
  try
    Fresh := (ARed <> FLEDRed) or (AGreen <> FLEDGreen) or (ABlue <> FLEDBlue);
    if Fresh or (FCore.TicksMS >= FLEDExpiration) then
    begin
      Result := FBackend.SetLED(Self, ARed, AGreen, ABlue);
      FLEDExpiration := FCore.TicksMS + PML_LED_MIN_REPEAT_MS;
    end
    else
      Result := True;      // 機器へ送り続けない
    // 失敗しても値は覚える（機器へ送り続けないため）
    FLEDRed := ARed;
    FLEDGreen := AGreen;
    FLEDBlue := ABlue;
  finally
    FCore.Unlock;
  end;
end;

function TPMLJoystick.SendEffect(AData: Pointer; ASize: Integer): Boolean;
begin
  FCore.Lock;
  try
    Result := FBackend.SendEffect(Self, AData, ASize);
  finally
    FCore.Unlock;
  end;
end;

procedure TPMLJoystick.StopRumbleForClose;
begin
  if FRumbleExpiration <> 0 then
    Rumble(0, 0, 0);
  if FTriggerRumbleExpiration <> 0 then
    RumbleTriggers(0, 0, 0);
end;

procedure TPMLJoystick.UpdateRumbleTimers;
var
  Now_: UInt64;
begin
  Now_ := FCore.TicksMS;
  if (FRumbleExpiration <> 0) and (Now_ >= FRumbleExpiration) then
  begin
    Rumble(0, 0, 0);
    FRumbleResend := 0;
  end;
  if (FRumbleResend <> 0) and (Now_ >= FRumbleResend) then
  begin
    FBackend.Rumble(Self, FLowFrequencyRumble, FHighFrequencyRumble);
    FRumbleResend := Now_ + PML_RUMBLE_RESEND_MS;
    if FRumbleResend = 0 then
      FRumbleResend := 1;
  end;
  if (FTriggerRumbleExpiration <> 0) and (Now_ >= FTriggerRumbleExpiration) then
  begin
    RumbleTriggers(0, 0, 0);
    FTriggerRumbleResend := 0;
  end;
  if (FTriggerRumbleResend <> 0) and (Now_ >= FTriggerRumbleResend) then
  begin
    FBackend.RumbleTriggers(Self, FLeftTriggerRumble, FRightTriggerRumble);
    FTriggerRumbleResend := Now_ + PML_RUMBLE_RESEND_MS;
    if FTriggerRumbleResend = 0 then
      FTriggerRumbleResend := 1;
  end;
end;

{ ---- 登録 ---- }

type
  TJoystickRegistration = record
    Name    : String;
    Priority: Integer;
    Factory : TPMLJoystickBackendFactory;
  end;

var
  JoystickRegistry: array of TJoystickRegistration;

function FindJoystickIndex(const AName: String): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(JoystickRegistry) do
    if SameText(JoystickRegistry[I].Name, AName) then
      Exit(I);
end;

procedure PMLRegisterJoystickBackend(const AName: String; APriority: Integer;
  AFactory: TPMLJoystickBackendFactory);
var
  At, I: Integer;
begin
  if AName = '' then
    raise EPMLArgument.Create('joystick backend name is empty');
  if not Assigned(AFactory) then
    raise EPMLArgument.Create('joystick backend factory is nil');
  if FindJoystickIndex(AName) >= 0 then
    raise EPMLArgument.CreateFmt('joystick backend "%s" is already registered', [AName]);
  At := Length(JoystickRegistry);
  for I := 0 to High(JoystickRegistry) do
    if JoystickRegistry[I].Priority < APriority then
    begin
      At := I;
      Break;
    end;
  SetLength(JoystickRegistry, Length(JoystickRegistry) + 1);
  for I := High(JoystickRegistry) downto At + 1 do
    JoystickRegistry[I] := JoystickRegistry[I - 1];
  JoystickRegistry[At].Name := AName;
  JoystickRegistry[At].Priority := APriority;
  JoystickRegistry[At].Factory := AFactory;
end;

function PMLJoystickBackendNames: TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(JoystickRegistry));
  for I := 0 to High(JoystickRegistry) do
    Result[I] := JoystickRegistry[I].Name;
end;

function PMLFindJoystickBackend(const AName: String): TPMLJoystickBackendFactory;
var
  I: Integer;
begin
  I := FindJoystickIndex(AName);
  if I >= 0 then
    Result := JoystickRegistry[I].Factory
  else
    Result := nil;
end;

{ TPMLJoystickBackend }

constructor TPMLJoystickBackend.Create(ACore: TPMLJoystickCore);
begin
  inherited Create;
  FCore := ACore;
end;

procedure TPMLJoystickBackend.Detect;
begin
end;

function TPMLJoystickBackend.IsDevicePresent(AVendor, AProduct, AVersion: Word; const AName: String): Boolean;
begin
  Result := False;
end;

function TPMLJoystickBackend.DevicePath(AIndex: Integer): String;
begin
  Result := '';
end;

function TPMLJoystickBackend.DevicePlayerIndex(AIndex: Integer): Integer;
begin
  Result := -1;
end;

procedure TPMLJoystickBackend.SetDevicePlayerIndex(AIndex, APlayerIndex: Integer);
begin
end;

function TPMLJoystickBackend.Rumble(AJoystick: TPMLJoystick; ALow, AHigh: Word): Boolean;
begin
  Result := False;
end;

function TPMLJoystickBackend.RumbleTriggers(AJoystick: TPMLJoystick; ALeft, ARight: Word): Boolean;
begin
  Result := False;
end;

function TPMLJoystickBackend.SetLED(AJoystick: TPMLJoystick; ARed, AGreen, ABlue: Byte): Boolean;
begin
  Result := False;
end;

function TPMLJoystickBackend.SendEffect(AJoystick: TPMLJoystick; AData: Pointer; ASize: Integer): Boolean;
begin
  Result := False;
end;

function TPMLJoystickBackend.SetSensorsEnabled(AJoystick: TPMLJoystick; AEnabled: Boolean): Boolean;
begin
  Result := False;
end;

procedure TPMLJoystickBackend.Quit;
begin
end;

function TPMLJoystickBackend.GamepadMapping(AIndex: Integer; out AMapping: TPMLGamepadMapping): Boolean;
begin
  AMapping := PMLEmptyGamepadMapping;
  Result := False;
end;

end.
