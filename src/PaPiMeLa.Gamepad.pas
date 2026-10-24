{
  PaPiMeLa.Gamepad — ゲームパッド

  Origin : ported from SDL (src/joystick/SDL_gamepad.c)
           Scope: SDL_IsGamepad / SDL_ShouldIgnoreGamepad、機器ごとのマッピングの決め方
           （SDL_PrivateGetGamepadMapping。バックエンドの自動のマッピングを DB へ足す）、SDL_OpenGamepad と
           開いたゲームパッド（SDL_Gamepad。割り当て、軸・ボタンの読み取り、顔のボタンの並びと表示名、
           種類、ランブル・LED）、ジョイスティックのイベントからゲームパッドのイベントを作る
           SDL_GamepadEventWatcher（軸・ボタン・ハットの割り当て、半軸、反転）、Added / Removed / Remapped
           （MappingChangeTracker）、静止に戻す RecenterGamepad、ガイドボタンの遅延、
           ゲームパッドのイベントの有効・無効。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #62

  WHAT:
    TPMLGamepadSystem はジョイスティックのサブシステムが作る「ゲームパッドの層」で、マッピングの DB
    （PaPiMeLa.Gamepad.Mapping）と、無視する機器の表を持つ。Context が Gamepad を求めたとき Start して、
    ジョイスティックのイベントを見張り（イベントの監視）、ゲームパッドのイベントに言い換える。
    TPMLGamepad は開いたジョイスティックの上の「見え方」で、同じ機器を何度開いても同じオブジェクト。

  RESOLVED:
    - Steam の仮想ゲームパッド、HIDAPI、タッチパッド、センサー、静電容量、Apple の記号名は無い
      （ゲームパッドの種類は GUID と mapping の type: 欄だけで決める）
    - 機器の名前の保持（SDL_gamepad_names）は要らない: 名前は呼ぶたびに DB から引く

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Gamepad;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Properties,
  PaPiMeLa.Events,
  PaPiMeLa.Joystick.GUID,
  PaPiMeLa.Joystick.Tables,
  PaPiMeLa.Joystick.Backend,
  PaPiMeLa.Joystick,
  PaPiMeLa.Gamepad.Mapping;

type
  TPMLGamepadSystem = class;

  { 開いたゲームパッド（SDL_Gamepad）。TPMLGamepadSystem.Open が返す。Close で返す（Free しない）。 }
  TPMLGamepad = class(TPMLOwnedObject)
  strict private
    FSystem        : TPMLGamepadSystem;
    FJoystick      : TPMLJoystick;
    FRefCount      : Integer;
    FName          : String;
    FType          : TPMLGamepadType;
    FFaceStyle     : TPMLGamepadFaceStyle;
    FMapping       : TPMLGamepadMappingEntry;
    FBindings      : TPMLGamepadBindings;
    FLastMatchAxis : array of Integer;      // 軸ごとに、最後に当たった割り当ての番号（無ければ -1）
    FLastHatMask   : array of Byte;
    FGuideButtonDown: UInt64;
    function  GetID: TPMLJoystickID;
    function  GetConnected: Boolean;
    function  GetName: String;
    function  GetPlayerIndex: Integer;
    procedure SetPlayerIndex(AValue: Integer);
  public
    constructor Create(AContextRef: TObject; ASystem: TPMLGamepadSystem; AJoystick: TPMLJoystick);
    destructor Destroy; override;

    { ---- アプリが使う ---- }
    // 閉じる（SDL_CloseGamepad）。Open した回数だけ呼ぶ。
    procedure Close;
    function  HasAxis(AAxis: TPMLGamepadAxis): Boolean;
    function  HasButton(AButton: TPMLGamepadButton): Boolean;
    // 軸の今の値（SDL_GetGamepadAxis）。
    function  Axis(AAxis: TPMLGamepadAxis): SmallInt;
    // ボタンの今の状態（SDL_GetGamepadButton）。
    function  Button(AButton: TPMLGamepadButton): Boolean;
    // 顔のボタンの表示名（SDL_GetGamepadButtonLabel）。
    function  ButtonLabel(AButton: TPMLGamepadButton): TPMLGamepadButtonLabel;
    // 割り当ての一覧の写し（SDL_GetGamepadBindings）。
    function  Bindings: TPMLGamepadBindings;
    // マッピングの文字列（SDL_GetGamepadMapping）。
    function  MappingString: String;
    // 実際の種類（マッピングの type: を見ない。SDL_GetRealGamepadType）。
    function  RealType: TPMLGamepadType;
    function  Rumble(ALow, AHigh: Word; ADurationMS: Cardinal): Boolean;
    function  RumbleTriggers(ALeft, ARight: Word; ADurationMS: Cardinal): Boolean;
    function  SetLED(ARed, AGreen, ABlue: Byte): Boolean;
    function  SendEffect(AData: Pointer; ASize: Integer): Boolean;

    property ID           : TPMLJoystickID read GetID;
    property Joystick     : TPMLJoystick read FJoystick;
    // マッピングの名前。「*」なら機器の名前（SDL_GetGamepadName）。
    property Name         : String read GetName;
    property GamepadType  : TPMLGamepadType read FType;
    property FaceStyle    : TPMLGamepadFaceStyle read FFaceStyle;
    property Connected    : Boolean read GetConnected;
    property PlayerIndex  : Integer read GetPlayerIndex write SetPlayerIndex;

    { ---- システムが使う ---- }
    procedure LoadMapping(AEntry: TPMLGamepadMappingEntry);
    function  RefAdd: Integer;
    function  RefRelease: Integer;
    property  Mapping: TPMLGamepadMappingEntry read FMapping;
    property  BindingList: TPMLGamepadBindings read FBindings;
    function  LastMatchAxis(AAxis: Integer): Integer;
    procedure SetLastMatchAxis(AAxis, AValue: Integer);
    function  LastHatMask(AHat: Integer): Byte;
    procedure SetLastHatMask(AHat: Integer; AValue: Byte);
    property  GuideButtonDown: UInt64 read FGuideButtonDown write FGuideButtonDown;
  end;

  TPMLGamepadSystem = class sealed(TPMLJoystickGamepadLayer, IPMLEventWatch)
  strict private
    type
      TIDFlag = record
        ID  : TPMLJoystickID;
        Flag: Boolean;
      end;
      TTracker = class;
      TTrackerHandle = class(TPMLGamepadMappingTracker)
      strict private
        FOwner: TPMLGamepadSystem;
      public
        constructor Create(AOwner: TPMLGamepadSystem);
        procedure Push; override;
        procedure Changed(AEntry: TPMLGamepadMappingEntry); override;
        procedure Pop; override;
      end;
      TTracker = class
        RefCount : Integer;
        IDs      : TPMLJoystickIDs;
        Mappings : array of TPMLGamepadMappingEntry;
        Changed  : array of TPMLGamepadMappingEntry;
      end;
    var
    FJoy        : TPMLJoystickSystem;
    FQueue      : TPMLEventQueue;
    FHints      : TPMLHints;
    FDB         : TPMLGamepadMappingDB;
    FAllowed    : TPMLVIDPIDList;
    FIgnored    : TPMLVIDPIDList;
    FTrackerHdl : TTrackerHandle;
    FTracker    : TTracker;
    FOpen       : array of TPMLGamepad;           // 新しく開いたものが先頭
    FIDFlags    : array of TIDFlag;                // IsGamepad の覚え（SDL_gamepadInstanceIDs）
    FStarted    : Boolean;
    function  FindFlag(AID: TPMLJoystickID; out AFlag: Boolean): Boolean;
    procedure SetFlag(AID: TPMLJoystickID; AFlag: Boolean);
    function  FindOpen(AID: TPMLJoystickID): TPMLGamepad;
    function  GetMapping(AID: TPMLJoystickID; ACreate: Boolean): TPMLGamepadMappingEntry;
    function  GenerateAutomatic(const AName: String; AGUID: TPMLGUID;
      const ARaw: TPMLGamepadMapping): TPMLGamepadMappingEntry;
    procedure TrackPush;
    procedure TrackChanged(AEntry: TPMLGamepadMappingEntry);
    procedure TrackPop;
    procedure PrivateAdded(AID: TPMLJoystickID);
    procedure PrivateRemoved(AID: TPMLJoystickID);
    procedure PrivateRemapped(AID: TPMLJoystickID);
    procedure PushDeviceEvent(AKind: TPMLEventKind; AID: TPMLJoystickID);
    procedure Recenter(AGamepad: TPMLGamepad);
    procedure SendAxisEvent(ATimestamp: UInt64; AGamepad: TPMLGamepad; AAxis: TPMLGamepadAxis; AValue: SmallInt);
    procedure SendButtonEvent(ATimestamp: UInt64; AGamepad: TPMLGamepad; AButton: TPMLGamepadButton; ADown: Boolean);
    procedure ResetOutput(ATimestamp: UInt64; AGamepad: TPMLGamepad; const ABind: TPMLGamepadBinding);
    procedure HandleAxis(ATimestamp: UInt64; AGamepad: TPMLGamepad; AAxis, AValue: Integer);
    procedure HandleButton(ATimestamp: UInt64; AGamepad: TPMLGamepad; AButton: Integer; ADown: Boolean);
    procedure HandleHat(ATimestamp: UInt64; AGamepad: TPMLGamepad; AHat: Integer; AValue: Byte);
    function  OnEventPushed(const AEvent: TPMLEvent): Boolean;
    function  GetStarted: Boolean;
  public
    constructor Create(AJoy: TPMLJoystickSystem);
    destructor Destroy; override;

    { ゲームパッドの層として、ジョイスティックの側から呼ばれる }
    function  IsGamepad(AID: TPMLJoystickID): Boolean; override;
    function  ShouldIgnore(AVendor, AProduct, AVersion: Word; const AName: String): Boolean; override;
    procedure GamepadAdded(AID: TPMLJoystickID); override;
    procedure GamepadRemoved(AID: TPMLJoystickID); override;
    procedure DelayedGuideButton(AJoystick: TPMLJoystick); override;
    procedure Shutdown; override;

    // ゲームパッドを閉じる（TPMLGamepad.Close から）
    procedure CloseGamepad(AGamepad: TPMLGamepad);
    // ジョイスティックのロック（再帰）
    procedure Lock;
    procedure Unlock;

    { ---- アプリが使う ---- }
    { ゲームパッドのイベントを出し始める（SDL_InitGamepads）。今つながっているゲームパッドの Added を出す。 }
    procedure Start;
    // ゲームパッドの機器（SDL_GetGamepads）と、あるか（SDL_HasGamepad）。
    function  Gamepads: TPMLJoystickIDs;
    function  HasGamepad: Boolean;
    // ID から（SDL_GetGamepadNameForID など）。名前はマッピングのもの、「*」なら機器の名前。無ければ ''。
    function  NameForID(AID: TPMLJoystickID): String;
    function  PathForID(AID: TPMLJoystickID): String;
    function  PlayerIndexForID(AID: TPMLJoystickID): Integer;
    function  GUIDForID(AID: TPMLJoystickID): TPMLGUID;
    function  VendorForID(AID: TPMLJoystickID): Word;
    function  ProductForID(AID: TPMLJoystickID): Word;
    function  ProductVersionForID(AID: TPMLJoystickID): Word;
    // マッピングの type: を見る種類（SDL_GetGamepadTypeForID）と、見ない種類（SDL_GetRealGamepadTypeForID）。
    function  TypeForID(AID: TPMLJoystickID): TPMLGamepadType;
    function  RealTypeForID(AID: TPMLJoystickID): TPMLGamepadType;
    // 機器のマッピングの文字列（SDL_GetGamepadMappingForID）。無ければ ''。
    function  MappingForID(AID: TPMLJoystickID): String;
    // ゲームパッドとして使える機器か（マッピングがあるか）と、名前と GUID だけで調べるとき。
    function  IsGamepadNameAndGUID(const AName: String; const AGUID: TPMLGUID): Boolean;
    { 開く。同じ ID は同じオブジェクト（Close の回数が合うまで閉じない）。マッピングが無ければ EPMLArgument。 }
    function  Open(AID: TPMLJoystickID): TPMLGamepad;
    function  FromID(AID: TPMLJoystickID): TPMLGamepad;
    function  FromPlayerIndex(APlayerIndex: Integer): TPMLGamepad;
    // 状態を更新する（SDL_UpdateGamepads。ジョイスティックの更新と同じ）。
    procedure Update;

    { ---- マッピング ---- }
    function  AddMapping(const AMapping: String): Integer;
    function  AddMappingsFromText(const AText: String): Integer;
    function  AddMappingsFromFile(const APath: String): Integer;
    // 全部のマッピング（SDL_GetGamepadMappings）と、GUID のマッピング（SDL_GetGamepadMappingForGUID。無ければ ''）。
    function  Mappings: TStringArray;
    function  MappingForGUID(const AGUID: TPMLGUID): String;
    // 機器のマッピングを置き換える（SDL_SetGamepadMapping。AMapping が '' なら割り当ての無い「*,*,」）。
    function  SetMappingForID(AID: TPMLJoystickID; const AMapping: String): Boolean;
    // 内蔵の表と設定を読み直す（SDL_ReloadGamepadMappings）。
    procedure ReloadMappings;

    // ゲームパッドのイベントの有効・無効（SDL_SetGamepadEventsEnabled）。
    procedure SetEventsEnabled(AEnabled: Boolean);
    function  EventsEnabled: Boolean;

    property  Started: Boolean read GetStarted;
    property  Database: TPMLGamepadMappingDB read FDB;
  end;

// Context が差し込む。ジョイスティックのサブシステムの工場。
function PMLCreateGamepadLayer(AJoy: TPMLJoystickSystem): TPMLJoystickGamepadLayer;

implementation

const
  USB_VENDOR_VALVE = $28DE;
  USB_PRODUCT_STEAM_VIRTUAL_GAMEPAD = $11FF;

type
  TBlacklistPos = (Begin_, End_, Anywhere);
  TBlacklistWord = record
    Text: String;
    Pos : TBlacklistPos;
  end;

const
  // 名前にこれらを含む機器はゲームパッドとして扱わない（SDL_gamepad_blacklist_words。Linux の分を含む）
  BlacklistWords: array[0..19] of TBlacklistWord = (
    (Text: ' Motion Sensors'; Pos: TBlacklistPos.End_),
    (Text: ' IMU';            Pos: TBlacklistPos.End_),
    (Text: ' Touchpad';       Pos: TBlacklistPos.End_),
    (Text: ' Accelerometer';  Pos: TBlacklistPos.End_),
    (Text: ' IR';             Pos: TBlacklistPos.End_),
    (Text: ' Motion Plus';    Pos: TBlacklistPos.End_),
    (Text: ' Nunchuk';        Pos: TBlacklistPos.End_),
    (Text: 'uinput-';         Pos: TBlacklistPos.Begin_),
    (Text: 'gpio_ir_recv';    Pos: TBlacklistPos.Begin_),
    (Text: 'Synaptics ';      Pos: TBlacklistPos.Anywhere),
    (Text: 'Trackpad';        Pos: TBlacklistPos.Anywhere),
    (Text: 'Clickpad';        Pos: TBlacklistPos.Anywhere),
    (Text: ' Keyboard';       Pos: TBlacklistPos.Anywhere),
    (Text: ' Laptop ';        Pos: TBlacklistPos.Anywhere),
    (Text: 'Mouse ';          Pos: TBlacklistPos.Begin_),
    (Text: ' Pen';            Pos: TBlacklistPos.End_),
    (Text: ' Finger';         Pos: TBlacklistPos.End_),
    (Text: ' System Control'; Pos: TBlacklistPos.End_),
    (Text: ' LED ';           Pos: TBlacklistPos.Anywhere),
    (Text: ' Thelio ';        Pos: TBlacklistPos.Anywhere));

  GamepadEventKinds: array[0..5] of TPMLEventKind = (
    TPMLEventKind.GamepadAxisMotion, TPMLEventKind.GamepadButtonDown, TPMLEventKind.GamepadButtonUp,
    TPMLEventKind.GamepadAdded, TPMLEventKind.GamepadRemoved, TPMLEventKind.GamepadRemapped);

function SameGUIDZero(const AGUID: TPMLGUID): Boolean;
begin
  Result := PMLSameGUID(AGUID, PMLZeroGUID);
end;

{ ---- TPMLGamepad ---- }

{ 割り当てには機器にない番号が書かれていることがある。SDL は範囲外の軸・ボタン・ハットを 0 / 離した / 中央として返す
  （エラーは積むだけ）ので、ここでも例外にしない。 }
function SafeAxis(AJoystick: TPMLJoystick; AIndex: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex < AJoystick.NumAxes) then
    Result := AJoystick.Axes[AIndex]
  else
    Result := 0;
end;

function SafeButton(AJoystick: TPMLJoystick; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < AJoystick.NumButtons) and AJoystick.Buttons[AIndex];
end;

function SafeHat(AJoystick: TPMLJoystick; AIndex: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex < AJoystick.NumHats) then
    Result := AJoystick.Hats[AIndex]
  else
    Result := 0;
end;

constructor TPMLGamepad.Create(AContextRef: TObject; ASystem: TPMLGamepadSystem; AJoystick: TPMLJoystick);
var
  I: Integer;
begin
  inherited Create(AContextRef, ASystem);
  FSystem := ASystem;
  FJoystick := AJoystick;
  SetLength(FLastMatchAxis, AJoystick.NumAxes);
  for I := 0 to High(FLastMatchAxis) do
    FLastMatchAxis[I] := -1;
  SetLength(FLastHatMask, AJoystick.NumHats);
end;

destructor TPMLGamepad.Destroy;
begin
  inherited Destroy;
end;

function TPMLGamepad.GetID: TPMLJoystickID;
begin
  Result := FJoystick.ID;
end;

function TPMLGamepad.GetConnected: Boolean;
begin
  Result := FJoystick.Connected;
end;

function TPMLGamepad.GetName: String;
begin
  if FName = '*' then
    Result := FJoystick.Name
  else
    Result := FName;
end;

function TPMLGamepad.GetPlayerIndex: Integer;
begin
  Result := FJoystick.PlayerIndex;
end;

procedure TPMLGamepad.SetPlayerIndex(AValue: Integer);
begin
  FJoystick.PlayerIndex := AValue;
end;

function TPMLGamepad.RefAdd: Integer;
begin
  Inc(FRefCount);
  Result := FRefCount;
end;

function TPMLGamepad.RefRelease: Integer;
begin
  Dec(FRefCount);
  Result := FRefCount;
end;

function TPMLGamepad.LastMatchAxis(AAxis: Integer): Integer;
begin
  Result := FLastMatchAxis[AAxis];
end;

procedure TPMLGamepad.SetLastMatchAxis(AAxis, AValue: Integer);
begin
  FLastMatchAxis[AAxis] := AValue;
end;

function TPMLGamepad.LastHatMask(AHat: Integer): Byte;
begin
  Result := FLastHatMask[AHat];
end;

procedure TPMLGamepad.SetLastHatMask(AHat: Integer; AValue: Byte);
begin
  FLastHatMask[AHat] := AValue;
end;

procedure TPMLGamepad.LoadMapping(AEntry: TPMLGamepadMappingEntry);
var
  I: Integer;
  B: ^TPMLGamepadBinding;
  Info: ^TPMLJoystickAxisInfo;
begin
  FName := AEntry.Name;
  FBindings := nil;
  FMapping := AEntry;
  for I := 0 to High(FLastMatchAxis) do
    FLastMatchAxis[I] := -1;
  // 種類と顔のボタンの並び
  FType := PMLMappingTypeField(AEntry.Mapping, False);
  if FType = TPMLGamepadType.Unknown then
    FType := FSystem.RealTypeForID(FJoystick.ID);
  FFaceStyle := PMLMappingFaceStyle(AEntry.Mapping, FType);
  PMLParseGamepadBindings(AEntry.Mapping, FBindings);
  // トリガーの静止の位置を、入力の範囲の端に置く
  for I := 0 to High(FBindings) do
  begin
    B := @FBindings[I];
    if (B^.InputType = TPMLGamepadBindType.Axis) and (B^.OutputType = TPMLGamepadBindType.Axis)
    and (B^.OutputAxis in [TPMLGamepadAxis.LeftTrigger, TPMLGamepadAxis.RightTrigger])
    and (B^.InputIndex < FJoystick.NumAxes) then
    begin
      Info := FJoystick.AxisInfoPtr(B^.InputIndex);
      Info^.Value := SmallInt(B^.InputMin);
      Info^.Zero := SmallInt(B^.InputMin);
    end;
  end;
end;

procedure TPMLGamepad.Close;
begin
  FSystem.CloseGamepad(Self);
end;

function TPMLGamepad.HasAxis(AAxis: TPMLGamepadAxis): Boolean;
var
  I: Integer;
begin
  FSystem.Lock;
  try
    for I := 0 to High(FBindings) do
      if (FBindings[I].OutputType = TPMLGamepadBindType.Axis) and (FBindings[I].OutputAxis = AAxis) then
        Exit(True);
    Result := False;
  finally
    FSystem.Unlock;
  end;
end;

function TPMLGamepad.HasButton(AButton: TPMLGamepadButton): Boolean;
var
  I: Integer;
begin
  FSystem.Lock;
  try
    for I := 0 to High(FBindings) do
      if (FBindings[I].OutputType = TPMLGamepadBindType.Button) and (FBindings[I].OutputButton = AButton) then
        Exit(True);
    Result := False;
  finally
    FSystem.Unlock;
  end;
end;

function TPMLGamepad.Axis(AAxis: TPMLGamepadAxis): SmallInt;
var
  I, Value: Integer;
  B: ^TPMLGamepadBinding;
  ValidIn, ValidOut: Boolean;
  Normalized: Single;
begin
  Result := 0;
  FSystem.Lock;
  try
    for I := 0 to High(FBindings) do
    begin
      B := @FBindings[I];
      if (B^.OutputType <> TPMLGamepadBindType.Axis) or (B^.OutputAxis <> AAxis) then
        Continue;
      Value := 0;
      case B^.InputType of
        TPMLGamepadBindType.Axis:
        begin
          Value := SafeAxis(FJoystick, B^.InputIndex);
          if B^.InputMin < B^.InputMax then
            ValidIn := (Value >= B^.InputMin) and (Value <= B^.InputMax)
          else
            ValidIn := (Value >= B^.InputMax) and (Value <= B^.InputMin);
          if ValidIn then
          begin
            if (B^.InputMin <> B^.OutputMin) or (B^.InputMax <> B^.OutputMax) then
            begin
              Normalized := Single(Value - B^.InputMin) / Single(B^.InputMax - B^.InputMin);
              Value := B^.OutputMin + Trunc(Normalized * Single(B^.OutputMax - B^.OutputMin));
            end;
          end
          else
            Value := 0;
        end;
        TPMLGamepadBindType.Button:
          if SafeButton(FJoystick, B^.InputIndex) then
            Value := B^.OutputMax;
        TPMLGamepadBindType.Hat:
          if (SafeHat(FJoystick, B^.InputIndex) and B^.InputMask) <> 0 then
            Value := B^.OutputMax;
      end;
      if B^.OutputMin < B^.OutputMax then
        ValidOut := (Value >= B^.OutputMin) and (Value <= B^.OutputMax)
      else
        ValidOut := (Value >= B^.OutputMax) and (Value <= B^.OutputMin);
      // 0 なら、別の割り当てが 0 でない値を出すかもしれない
      if (Value <> 0) and ValidOut then
      begin
        Result := SmallInt(Value);
        Break;
      end;
    end;
  finally
    FSystem.Unlock;
  end;
end;

function TPMLGamepad.Button(AButton: TPMLGamepadButton): Boolean;
var
  I, Value, Threshold: Integer;
  B: ^TPMLGamepadBinding;
begin
  Result := False;
  FSystem.Lock;
  try
    for I := 0 to High(FBindings) do
    begin
      B := @FBindings[I];
      if (B^.OutputType <> TPMLGamepadBindType.Button) or (B^.OutputButton <> AButton) then
        Continue;
      case B^.InputType of
        TPMLGamepadBindType.Axis:
        begin
          Value := SafeAxis(FJoystick, B^.InputIndex);
          Threshold := B^.InputMin + (B^.InputMax - B^.InputMin) div 2;
          if B^.InputMin < B^.InputMax then
          begin
            if (Value >= B^.InputMin) and (Value <= B^.InputMax) then
              Result := Result or (Value >= Threshold);
          end
          else if (Value >= B^.InputMax) and (Value <= B^.InputMin) then
            Result := Result or (Value <= Threshold);
        end;
        TPMLGamepadBindType.Button:
          Result := Result or SafeButton(FJoystick, B^.InputIndex);
        TPMLGamepadBindType.Hat:
          Result := Result or ((SafeHat(FJoystick, B^.InputIndex) and B^.InputMask) <> 0);
      end;
    end;
  finally
    FSystem.Unlock;
  end;
end;

function TPMLGamepad.ButtonLabel(AButton: TPMLGamepadButton): TPMLGamepadButtonLabel;
begin
  Result := PMLGamepadButtonLabelForFaceStyle(FFaceStyle, AButton);
end;

function TPMLGamepad.Bindings: TPMLGamepadBindings;
begin
  FSystem.Lock;
  try
    Result := Copy(FBindings);
  finally
    FSystem.Unlock;
  end;
end;

function TPMLGamepad.MappingString: String;
begin
  FSystem.Lock;
  try
    Result := FSystem.Database.FormatMapping(FMapping, FJoystick.GUID);
  finally
    FSystem.Unlock;
  end;
end;

function TPMLGamepad.RealType: TPMLGamepadType;
begin
  Result := FSystem.RealTypeForID(FJoystick.ID);
end;

function TPMLGamepad.Rumble(ALow, AHigh: Word; ADurationMS: Cardinal): Boolean;
begin
  Result := FJoystick.Rumble(ALow, AHigh, ADurationMS);
end;

function TPMLGamepad.RumbleTriggers(ALeft, ARight: Word; ADurationMS: Cardinal): Boolean;
begin
  Result := FJoystick.RumbleTriggers(ALeft, ARight, ADurationMS);
end;

function TPMLGamepad.SetLED(ARed, AGreen, ABlue: Byte): Boolean;
begin
  Result := FJoystick.SetLED(ARed, AGreen, ABlue);
end;

function TPMLGamepad.SendEffect(AData: Pointer; ASize: Integer): Boolean;
begin
  Result := FJoystick.SendEffect(AData, ASize);
end;

{ ---- 変更の追跡 ---- }

constructor TPMLGamepadSystem.TTrackerHandle.Create(AOwner: TPMLGamepadSystem);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TPMLGamepadSystem.TTrackerHandle.Push;
begin
  FOwner.TrackPush;
end;

procedure TPMLGamepadSystem.TTrackerHandle.Changed(AEntry: TPMLGamepadMappingEntry);
begin
  FOwner.TrackChanged(AEntry);
end;

procedure TPMLGamepadSystem.TTrackerHandle.Pop;
begin
  FOwner.TrackPop;
end;

procedure TPMLGamepadSystem.TrackPush;
var
  I: Integer;
begin
  if FTracker <> nil then
  begin
    Inc(FTracker.RefCount);
    Exit;
  end;
  FTracker := TTracker.Create;
  FTracker.RefCount := 1;
  // 今ある機器と、それぞれのマッピングを覚える
  FTracker.IDs := FJoy.Joysticks;
  SetLength(FTracker.Mappings, Length(FTracker.IDs));
  for I := 0 to High(FTracker.IDs) do
    FTracker.Mappings[I] := GetMapping(FTracker.IDs[I], False);
end;

procedure TPMLGamepadSystem.TrackChanged(AEntry: TPMLGamepadMappingEntry);
begin
  if FTracker = nil then
    Exit;
  SetLength(FTracker.Changed, Length(FTracker.Changed) + 1);
  FTracker.Changed[High(FTracker.Changed)] := AEntry;
end;

procedure TPMLGamepadSystem.TrackPop;
var
  T: TTracker;
  I, J: Integer;
  ID: TPMLJoystickID;
  GP: TPMLGamepad;
  NewMap, OldMap: TPMLGamepadMappingEntry;
  WasChanged: Boolean;
begin
  if FTracker = nil then
    Exit;
  Dec(FTracker.RefCount);
  if FTracker.RefCount > 0 then
    Exit;
  T := FTracker;
  FTracker := nil;
  try
    // マッピングが変わって、ゲームパッドが増えた・減った・変わったものを知らせる
    for I := 0 to High(T.IDs) do
    begin
      ID := T.IDs[I];
      GP := FindOpen(ID);
      NewMap := GetMapping(ID, False);
      if GP <> nil then
        OldMap := GP.Mapping
      else
        OldMap := T.Mappings[I];
      if (NewMap <> nil) and (OldMap = nil) then
      begin
        SetFlag(ID, True);
        PrivateAdded(ID);
      end
      else if (OldMap <> nil) and (NewMap = nil) then
      begin
        SetFlag(ID, False);
        PrivateRemoved(ID);
      end
      else
      begin
        WasChanged := OldMap <> NewMap;
        for J := 0 to High(T.Changed) do
          if T.Changed[J] = NewMap then
            WasChanged := True;
        if WasChanged then
        begin
          if GP <> nil then
            GP.LoadMapping(NewMap);
          PrivateRemapped(ID);
        end;
      end;
    end;
  finally
    T.Free;
  end;
end;

{ ---- マッピングの決め方 ---- }

function TPMLGamepadSystem.GenerateAutomatic(const AName: String; AGUID: TPMLGUID;
  const ARaw: TPMLGamepadMapping): TPMLGamepadMappingEntry;
var
  Existing: Boolean;
begin
  // CRC は GUID から外す（CRC の無いマッピングを後から足したとき、それが勝つように）
  PMLSetJoystickGUIDCRC(AGUID, 0);
  Result := FDB.AddForGUID(AGUID, PMLAutomaticMappingString(AName, ARaw), Existing,
    TPMLGamepadMappingPriority.Builtin);
end;

function TPMLGamepadSystem.GetMapping(AID: TPMLJoystickID; ACreate: Boolean): TPMLGamepadMappingEntry;
var
  Name: String;
  GUID: TPMLGUID;
  Raw: TPMLGamepadMapping;
begin
  Result := nil;
  try
    Name := FJoy.NameForID(AID);
    GUID := FJoy.GUIDForID(AID);
  except
    on EPMLArgument do
      Exit(FDB.DefaultMapping);
  end;
  Result := FDB.FindForGUID(GUID, False);
  if (Result = nil) and ACreate then
    if FJoy.AutoGamepadMapping(AID, Raw) then
      Result := GenerateAutomatic(Name, GUID, Raw);
  if Result = nil then
    Result := FDB.DefaultMapping;
end;

function TPMLGamepadSystem.FindFlag(AID: TPMLJoystickID; out AFlag: Boolean): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FIDFlags) do
    if FIDFlags[I].ID = AID then
    begin
      AFlag := FIDFlags[I].Flag;
      Exit(True);
    end;
  AFlag := False;
  Result := False;
end;

procedure TPMLGamepadSystem.SetFlag(AID: TPMLJoystickID; AFlag: Boolean);
var
  I: Integer;
begin
  for I := 0 to High(FIDFlags) do
    if FIDFlags[I].ID = AID then
    begin
      FIDFlags[I].Flag := AFlag;
      Exit;
    end;
  SetLength(FIDFlags, Length(FIDFlags) + 1);
  FIDFlags[High(FIDFlags)].ID := AID;
  FIDFlags[High(FIDFlags)].Flag := AFlag;
end;

function TPMLGamepadSystem.FindOpen(AID: TPMLJoystickID): TPMLGamepad;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(FOpen) do
    if FOpen[I].ID = AID then
      Exit(FOpen[I]);
end;

{ ---- 作る・壊す ---- }

constructor TPMLGamepadSystem.Create(AJoy: TPMLJoystickSystem);
begin
  inherited Create(AJoy.ContextRef, AJoy);
  FJoy := AJoy;
  FHints := AJoy.Hints;
  FQueue := AJoy.Queue;
  FTrackerHdl := TTrackerHandle.Create(Self);
  FDB := TPMLGamepadMappingDB.Create(FHints, @FJoy.IsGameCube);
  FDB.Tracker := FTrackerHdl;
  FAllowed := TPMLVIDPIDList.Create(FHints, [], PML_HINT_GAMEPAD_IGNORE_DEVICES_EXCEPT, '');
  FIgnored := TPMLVIDPIDList.Create(FHints, [], PML_HINT_GAMEPAD_IGNORE_DEVICES, '');
  FJoy.Lock;
  try
    FDB.LoadInitial;
  finally
    FJoy.Unlock;
  end;
end;

destructor TPMLGamepadSystem.Destroy;
begin
  Shutdown;
  FDB.Tracker := nil;
  FreeAndNil(FDB);
  FreeAndNil(FAllowed);
  FreeAndNil(FIgnored);
  FreeAndNil(FTrackerHdl);
  inherited Destroy;
end;

procedure TPMLGamepadSystem.Lock;
begin
  FJoy.Lock;
end;

procedure TPMLGamepadSystem.Unlock;
begin
  FJoy.Unlock;
end;

function TPMLGamepadSystem.GetStarted: Boolean;
begin
  Result := FStarted;
end;

procedure TPMLGamepadSystem.Start;
var
  IDs: TPMLJoystickIDs;
  I: Integer;
begin
  if FStarted then
    Exit;
  FJoy.Lock;
  try
    FStarted := True;
    if FQueue <> nil then
      FQueue.AddWatch(Self as IPMLEventWatch);
    // 今つながっているゲームパッドの Added を出す
    IDs := FJoy.Joysticks;
    for I := 0 to High(IDs) do
      if IsGamepad(IDs[I]) then
        PrivateAdded(IDs[I]);
  finally
    FJoy.Unlock;
  end;
end;

procedure TPMLGamepadSystem.Shutdown;
var
  I: Integer;
  GP: TPMLGamepad;
begin
  if not FStarted then
    Exit;
  FJoy.Lock;
  try
    for I := 0 to High(FOpen) do
      PrivateRemoved(FOpen[I].ID);
    FStarted := False;
    if FQueue <> nil then
      FQueue.RemoveWatch(Self as IPMLEventWatch);
    while Length(FOpen) > 0 do
    begin
      GP := FOpen[0];
      while GP.RefRelease > 0 do ;
      CloseGamepad(GP);
    end;
  finally
    FJoy.Unlock;
  end;
end;

{ ---- ゲームパッドの層 ---- }

function TPMLGamepadSystem.IsGamepad(AID: TPMLJoystickID): Boolean;
var
  Flag: Boolean;
begin
  FJoy.Lock;
  try
    if FindFlag(AID, Flag) then
      Exit(Flag);
    Result := GetMapping(AID, True) <> nil;
    SetFlag(AID, Result);
  finally
    FJoy.Unlock;
  end;
end;

function TPMLGamepadSystem.IsGamepadNameAndGUID(const AName: String; const AGUID: TPMLGUID): Boolean;
begin
  FJoy.Lock;
  try
    Result := (FDB.DefaultMapping <> nil) or (FDB.FindForGUID(AGUID, False) <> nil);
  finally
    FJoy.Unlock;
  end;
end;

function TPMLGamepadSystem.ShouldIgnore(AVendor, AProduct, AVersion: Word; const AName: String): Boolean;
var
  I: Integer;
  W: TBlacklistWord;
  AllowSteamVirtual: Boolean;
begin
  for I := 0 to High(BlacklistWords) do
  begin
    W := BlacklistWords[I];
    case W.Pos of
      TBlacklistPos.Begin_:
        if Copy(AName, 1, Length(W.Text)) = W.Text then
          Exit(True);
      TBlacklistPos.End_:
        if (Length(AName) >= Length(W.Text)) and (Copy(AName, Length(AName) - Length(W.Text) + 1, MaxInt) = W.Text) then
          Exit(True);
      TBlacklistPos.Anywhere:
        if Pos(W.Text, AName) > 0 then
        begin
          // Ipega のゲームパッドは、キーボードのモードも持つ
          if Copy(AName, 1, 3) = 'PG-' then
            Break;
          Exit(True);
        end;
    end;
  end;
  AllowSteamVirtual := (FHints <> nil) and PMLStringBoolean(FHints.GetHint(PML_HINT_GAMEPAD_ALLOW_STEAM_VIRTUAL), False);
  if (AVendor = USB_VENDOR_VALVE) and (AProduct = USB_PRODUCT_STEAM_VIRTUAL_GAMEPAD) then
    Exit(not AllowSteamVirtual);
  if FAllowed.IncludedCount > 0 then
    Exit(not FAllowed.Contains(AVendor, AProduct));
  Result := FIgnored.Contains(AVendor, AProduct);
end;

procedure TPMLGamepadSystem.PushDeviceEvent(AKind: TPMLEventKind; AID: TPMLJoystickID);
var
  E: TPMLEvent;
begin
  if FQueue = nil then
    Exit;
  E := Default(TPMLEvent);
  E.Kind := AKind;
  E.Timestamp := FJoy.TimestampNS;
  E.JDevice.Which := AID;
  FQueue.Push(E);
end;

procedure TPMLGamepadSystem.PrivateAdded(AID: TPMLJoystickID);
begin
  if (not FStarted) or FJoy.BeingAdded then
    Exit;
  PushDeviceEvent(TPMLEventKind.GamepadAdded, AID);
end;

procedure TPMLGamepadSystem.PrivateRemapped(AID: TPMLJoystickID);
begin
  if (not FStarted) or FJoy.BeingAdded then
    Exit;
  PushDeviceEvent(TPMLEventKind.GamepadRemapped, AID);
end;

procedure TPMLGamepadSystem.PrivateRemoved(AID: TPMLJoystickID);
var
  GP: TPMLGamepad;
begin
  if not FStarted then
    Exit;
  GP := FindOpen(AID);
  if GP <> nil then
    Recenter(GP);
  PushDeviceEvent(TPMLEventKind.GamepadRemoved, AID);
end;

procedure TPMLGamepadSystem.GamepadAdded(AID: TPMLJoystickID);
begin
  PrivateAdded(AID);
end;

procedure TPMLGamepadSystem.GamepadRemoved(AID: TPMLJoystickID);
begin
  PrivateRemoved(AID);
end;

procedure TPMLGamepadSystem.DelayedGuideButton(AJoystick: TPMLJoystick);
var
  GP: TPMLGamepad;
begin
  GP := FindOpen(AJoystick.ID);
  if GP = nil then
    Exit;
  SendButtonEvent(0, GP, TPMLGamepadButton.Guide, False);
  // この変化にも UpdateComplete を出させる
  if AJoystick.UpdateComplete = 0 then
    AJoystick.UpdateComplete := FJoy.TimestampNS;
end;

{ ---- 出力 ---- }

procedure TPMLGamepadSystem.SendAxisEvent(ATimestamp: UInt64; AGamepad: TPMLGamepad;
  AAxis: TPMLGamepadAxis; AValue: SmallInt);
var
  E: TPMLEvent;
begin
  if (FQueue = nil) or not FQueue.Enabled[TPMLEventKind.GamepadAxisMotion] then
    Exit;
  E := Default(TPMLEvent);
  E.Kind := TPMLEventKind.GamepadAxisMotion;
  E.Timestamp := ATimestamp;
  E.GAxis.Which := AGamepad.ID;
  E.GAxis.Axis := Ord(AAxis);
  E.GAxis.Value := AValue;
  FQueue.Push(E);
end;

procedure TPMLGamepadSystem.SendButtonEvent(ATimestamp: UInt64; AGamepad: TPMLGamepad;
  AButton: TPMLGamepadButton; ADown: Boolean);
var
  E: TPMLEvent;
  Kind: TPMLEventKind;
  Now_: UInt64;
begin
  if ADown then
    Kind := TPMLEventKind.GamepadButtonDown
  else
    Kind := TPMLEventKind.GamepadButtonUp;
  if AButton = TPMLGamepadButton.Guide then
  begin
    Now_ := FJoy.TicksMS;
    if ADown then
    begin
      AGamepad.GuideButtonDown := Now_;
      if AGamepad.Joystick.DelayedGuideButton then
        Exit;               // 重なった押しは飛ばす
    end
    else
    begin
      if Now_ < AGamepad.GuideButtonDown + PML_MINIMUM_GUIDE_BUTTON_DELAY_MS then
      begin
        AGamepad.Joystick.DelayedGuideButton := True;
        Exit;               // 短すぎる押しは、離すのを遅らせる
      end;
      AGamepad.Joystick.DelayedGuideButton := False;
    end;
  end;
  if (FQueue = nil) or not FQueue.Enabled[Kind] then
    Exit;
  E := Default(TPMLEvent);
  E.Kind := Kind;
  if ATimestamp = 0 then
    ATimestamp := FJoy.TimestampNS;
  E.Timestamp := ATimestamp;
  E.GButton.Which := AGamepad.ID;
  E.GButton.Button := Ord(AButton);
  E.GButton.Down := ADown;
  FQueue.Push(E);
end;

procedure TPMLGamepadSystem.ResetOutput(ATimestamp: UInt64; AGamepad: TPMLGamepad; const ABind: TPMLGamepadBinding);
begin
  if ABind.OutputType = TPMLGamepadBindType.Axis then
    SendAxisEvent(ATimestamp, AGamepad, ABind.OutputAxis, 0)
  else
    SendButtonEvent(ATimestamp, AGamepad, ABind.OutputButton, False);
end;

function SameOutput(const A, B: TPMLGamepadBinding): Boolean;
begin
  if A.OutputType <> B.OutputType then
    Exit(False);
  if A.OutputType = TPMLGamepadBindType.Axis then
    Result := A.OutputAxis = B.OutputAxis
  else
    Result := A.OutputButton = B.OutputButton;
end;

procedure TPMLGamepadSystem.HandleAxis(ATimestamp: UInt64; AGamepad: TPMLGamepad; AAxis, AValue: Integer);
var
  I, MatchIndex, LastIndex, Threshold: Integer;
  B: ^TPMLGamepadBinding;
  Normalized: Single;
  Down, InRange: Boolean;
begin
  if (AAxis < 0) or (AAxis >= AGamepad.Joystick.NumAxes) then
    Exit;
  LastIndex := AGamepad.LastMatchAxis(AAxis);
  MatchIndex := -1;
  for I := 0 to High(AGamepad.BindingList) do
  begin
    B := @AGamepad.BindingList[I];
    if (B^.InputType = TPMLGamepadBindType.Axis) and (B^.InputIndex = AAxis) then
    begin
      if B^.InputMin < B^.InputMax then
        InRange := (AValue >= B^.InputMin) and (AValue <= B^.InputMax)
      else
        InRange := (AValue >= B^.InputMax) and (AValue <= B^.InputMin);
      if InRange then
      begin
        MatchIndex := I;
        Break;
      end;
    end;
  end;
  if (LastIndex >= 0) and ((MatchIndex < 0) or not SameOutput(AGamepad.BindingList[LastIndex],
    AGamepad.BindingList[MatchIndex])) then
    ResetOutput(ATimestamp, AGamepad, AGamepad.BindingList[LastIndex]);
  if MatchIndex >= 0 then
  begin
    B := @AGamepad.BindingList[MatchIndex];
    if B^.OutputType = TPMLGamepadBindType.Axis then
    begin
      if (B^.InputMin <> B^.OutputMin) or (B^.InputMax <> B^.OutputMax) then
      begin
        Normalized := Single(AValue - B^.InputMin) / Single(B^.InputMax - B^.InputMin);
        AValue := B^.OutputMin + Trunc(Normalized * Single(B^.OutputMax - B^.OutputMin));
      end;
      SendAxisEvent(ATimestamp, AGamepad, B^.OutputAxis, SmallInt(AValue));
    end
    else
    begin
      Threshold := B^.InputMin + (B^.InputMax - B^.InputMin) div 2;
      if B^.InputMax < B^.InputMin then
        Down := AValue <= Threshold
      else
        Down := AValue >= Threshold;
      SendButtonEvent(ATimestamp, AGamepad, B^.OutputButton, Down);
    end;
  end;
  AGamepad.SetLastMatchAxis(AAxis, MatchIndex);
end;

procedure TPMLGamepadSystem.HandleButton(ATimestamp: UInt64; AGamepad: TPMLGamepad; AButton: Integer; ADown: Boolean);
var
  I, Value: Integer;
  B: ^TPMLGamepadBinding;
begin
  for I := 0 to High(AGamepad.BindingList) do
  begin
    B := @AGamepad.BindingList[I];
    if (B^.InputType = TPMLGamepadBindType.Button) and (B^.InputIndex = AButton) then
    begin
      if B^.OutputType = TPMLGamepadBindType.Axis then
      begin
        if ADown then
          Value := B^.OutputMax
        else
          Value := B^.OutputMin;
        SendAxisEvent(ATimestamp, AGamepad, B^.OutputAxis, SmallInt(Value));
      end
      else
        SendButtonEvent(ATimestamp, AGamepad, B^.OutputButton, ADown);
      Break;
    end;
  end;
end;

procedure TPMLGamepadSystem.HandleHat(ATimestamp: UInt64; AGamepad: TPMLGamepad; AHat: Integer; AValue: Byte);
var
  I: Integer;
  B: ^TPMLGamepadBinding;
  Changed: Byte;
begin
  if (AHat < 0) or (AHat >= AGamepad.Joystick.NumHats) then
    Exit;
  Changed := AGamepad.LastHatMask(AHat) xor AValue;
  for I := 0 to High(AGamepad.BindingList) do
  begin
    B := @AGamepad.BindingList[I];
    if (B^.InputType = TPMLGamepadBindType.Hat) and (B^.InputIndex = AHat) then
      if (Changed and B^.InputMask) <> 0 then
      begin
        if (AValue and B^.InputMask) <> 0 then
        begin
          if B^.OutputType = TPMLGamepadBindType.Axis then
            SendAxisEvent(ATimestamp, AGamepad, B^.OutputAxis, SmallInt(B^.OutputMax))
          else
            SendButtonEvent(ATimestamp, AGamepad, B^.OutputButton, True);
        end
        else
          ResetOutput(ATimestamp, AGamepad, B^);
      end;
  end;
  AGamepad.SetLastHatMask(AHat, AValue);
end;

procedure TPMLGamepadSystem.Recenter(AGamepad: TPMLGamepad);
var
  Timestamp: UInt64;
  B: TPMLGamepadButton;
  A: TPMLGamepadAxis;
begin
  Timestamp := FJoy.TimestampNS;
  for B := Low(TPMLGamepadButton) to High(TPMLGamepadButton) do
    if AGamepad.Button(B) then
      SendButtonEvent(Timestamp, AGamepad, B, False);
  for A := Low(TPMLGamepadAxis) to High(TPMLGamepadAxis) do
    if AGamepad.Axis(A) <> 0 then
      SendAxisEvent(Timestamp, AGamepad, A, 0);
end;

function TPMLGamepadSystem.OnEventPushed(const AEvent: TPMLEvent): Boolean;
var
  GP: TPMLGamepad;
  E: TPMLEvent;
begin
  Result := True;
  case AEvent.Kind of
    TPMLEventKind.JoystickAxisMotion:
    begin
      GP := FindOpen(AEvent.JAxis.Which);
      if GP <> nil then
        HandleAxis(AEvent.Timestamp, GP, AEvent.JAxis.Axis, AEvent.JAxis.Value);
    end;
    TPMLEventKind.JoystickButtonDown, TPMLEventKind.JoystickButtonUp:
    begin
      GP := FindOpen(AEvent.JButton.Which);
      if GP <> nil then
        HandleButton(AEvent.Timestamp, GP, AEvent.JButton.Button, AEvent.JButton.Down);
    end;
    TPMLEventKind.JoystickHatMotion:
    begin
      GP := FindOpen(AEvent.JHat.Which);
      if GP <> nil then
        HandleHat(AEvent.Timestamp, GP, AEvent.JHat.Hat, AEvent.JHat.Value);
    end;
    TPMLEventKind.JoystickUpdateComplete:
      if (FQueue <> nil) and FQueue.Enabled[TPMLEventKind.GamepadUpdateComplete] then
      begin
        GP := FindOpen(AEvent.JDevice.Which);
        if GP <> nil then
        begin
          E := Default(TPMLEvent);
          E.Kind := TPMLEventKind.GamepadUpdateComplete;
          E.Timestamp := AEvent.Timestamp;
          E.JDevice.Which := AEvent.JDevice.Which;
          FQueue.Push(E);
        end;
      end;
  end;
end;

{ ---- 問い合わせ ---- }

function TPMLGamepadSystem.Gamepads: TPMLJoystickIDs;
var
  All: TPMLJoystickIDs;
  I, N: Integer;
begin
  Result := nil;
  All := FJoy.Joysticks;
  N := 0;
  for I := 0 to High(All) do
    if IsGamepad(All[I]) then
    begin
      SetLength(Result, N + 1);
      Result[N] := All[I];
      Inc(N);
    end;
end;

function TPMLGamepadSystem.HasGamepad: Boolean;
begin
  Result := Length(Gamepads) > 0;
end;

function TPMLGamepadSystem.NameForID(AID: TPMLJoystickID): String;
var
  M: TPMLGamepadMappingEntry;
begin
  Result := '';
  FJoy.Lock;
  try
    M := GetMapping(AID, True);
    if M = nil then
      Exit;
    if M.Name = '*' then
      Result := FJoy.NameForID(AID)
    else
      Result := M.Name;
  finally
    FJoy.Unlock;
  end;
end;

function TPMLGamepadSystem.PathForID(AID: TPMLJoystickID): String;
begin
  Result := FJoy.PathForID(AID);
end;

function TPMLGamepadSystem.PlayerIndexForID(AID: TPMLJoystickID): Integer;
begin
  Result := FJoy.PlayerIndexForID(AID);
end;

function TPMLGamepadSystem.GUIDForID(AID: TPMLJoystickID): TPMLGUID;
begin
  Result := FJoy.GUIDForID(AID);
end;

function TPMLGamepadSystem.VendorForID(AID: TPMLJoystickID): Word;
begin
  Result := FJoy.VendorForID(AID);
end;

function TPMLGamepadSystem.ProductForID(AID: TPMLJoystickID): Word;
begin
  Result := FJoy.ProductForID(AID);
end;

function TPMLGamepadSystem.ProductVersionForID(AID: TPMLJoystickID): Word;
begin
  Result := FJoy.ProductVersionForID(AID);
end;

function TPMLGamepadSystem.RealTypeForID(AID: TPMLJoystickID): TPMLGamepadType;
begin
  Result := FJoy.GamepadTypeFromGUID(FJoy.GUIDForID(AID), FJoy.NameForID(AID));
end;

function TPMLGamepadSystem.TypeForID(AID: TPMLJoystickID): TPMLGamepadType;
var
  M: TPMLGamepadMappingEntry;
begin
  Result := TPMLGamepadType.Unknown;
  FJoy.Lock;
  try
    M := GetMapping(AID, True);
    if M <> nil then
      Result := PMLMappingTypeField(M.Mapping, True);
  finally
    FJoy.Unlock;
  end;
  if Result = TPMLGamepadType.Unknown then
    Result := RealTypeForID(AID);
end;

function TPMLGamepadSystem.MappingForID(AID: TPMLJoystickID): String;
var
  M: TPMLGamepadMappingEntry;
begin
  Result := '';
  FJoy.Lock;
  try
    M := GetMapping(AID, True);
    if M <> nil then
      Result := PMLGUIDToString(FJoy.GUIDForID(AID)) + ',' + M.Name + ',' + M.Mapping;
  finally
    FJoy.Unlock;
  end;
end;

{ ---- 開く・閉じる ---- }

function TPMLGamepadSystem.Open(AID: TPMLJoystickID): TPMLGamepad;
var
  M: TPMLGamepadMappingEntry;
  J: TPMLJoystick;
  I: Integer;
begin
  FJoy.Lock;
  try
    Result := FindOpen(AID);
    if Result <> nil then
    begin
      Result.RefAdd;
      Exit;
    end;
    M := GetMapping(AID, True);
    if M = nil then
      raise EPMLArgument.CreateFmt('Couldn''t find mapping for device (%d)', [AID]);
    J := FJoy.Open(AID);
    Result := TPMLGamepad.Create(ContextRef, Self, J);
    Result.LoadMapping(M);
    Result.RefAdd;
    SetLength(FOpen, Length(FOpen) + 1);
    for I := High(FOpen) downto 1 do
      FOpen[I] := FOpen[I - 1];
    FOpen[0] := Result;
  finally
    FJoy.Unlock;
  end;
end;

function TPMLGamepadSystem.FromID(AID: TPMLJoystickID): TPMLGamepad;
begin
  FJoy.Lock;
  try
    Result := FindOpen(AID);
  finally
    FJoy.Unlock;
  end;
end;

function TPMLGamepadSystem.FromPlayerIndex(APlayerIndex: Integer): TPMLGamepad;
var
  J: TPMLJoystick;
begin
  Result := nil;
  FJoy.Lock;
  try
    J := FJoy.FromPlayerIndex(APlayerIndex);
    if J <> nil then
      Result := FindOpen(J.ID);
  finally
    FJoy.Unlock;
  end;
end;

procedure TPMLGamepadSystem.CloseGamepad(AGamepad: TPMLGamepad);
var
  I, J: Integer;
begin
  FJoy.Lock;
  try
    if AGamepad.RefRelease > 0 then
      Exit;
    AGamepad.Joystick.Close;
    for I := 0 to High(FOpen) do
      if FOpen[I] = AGamepad then
      begin
        for J := I to High(FOpen) - 1 do
          FOpen[J] := FOpen[J + 1];
        SetLength(FOpen, Length(FOpen) - 1);
        Break;
      end;
    AGamepad.Free;
  finally
    FJoy.Unlock;
  end;
end;

procedure TPMLGamepadSystem.Update;
begin
  FJoy.Update;
end;

{ ---- マッピング ---- }

function TPMLGamepadSystem.AddMapping(const AMapping: String): Integer;
begin
  FJoy.Lock;
  try
    Result := FDB.AddMapping(AMapping);
  finally
    FJoy.Unlock;
  end;
end;

function TPMLGamepadSystem.AddMappingsFromText(const AText: String): Integer;
begin
  FJoy.Lock;
  try
    Result := FDB.AddFromText(AText);
  finally
    FJoy.Unlock;
  end;
end;

function TPMLGamepadSystem.AddMappingsFromFile(const APath: String): Integer;
begin
  FJoy.Lock;
  try
    Result := FDB.AddFromFile(APath);
  finally
    FJoy.Unlock;
  end;
end;

function TPMLGamepadSystem.Mappings: TStringArray;
begin
  FJoy.Lock;
  try
    Result := FDB.AllMappings;
  finally
    FJoy.Unlock;
  end;
end;

function TPMLGamepadSystem.MappingForGUID(const AGUID: TPMLGUID): String;
var
  E: TPMLGamepadMappingEntry;
begin
  Result := '';
  FJoy.Lock;
  try
    E := FDB.FindForGUID(AGUID, False);
    if E <> nil then
      Result := FDB.FormatMapping(E, AGUID);
  finally
    FJoy.Unlock;
  end;
end;

function TPMLGamepadSystem.SetMappingForID(AID: TPMLJoystickID; const AMapping: String): Boolean;
var
  GUID: TPMLGUID;
  Mapping: String;
  Existing: Boolean;
begin
  GUID := FJoy.GUIDForID(AID);
  if SameGUIDZero(GUID) then
    raise EPMLArgument.Create('instance_id');
  Mapping := AMapping;
  if Mapping = '' then
    Mapping := '*,*,';
  FJoy.Lock;
  try
    Result := FDB.AddForGUID(GUID, Mapping, Existing, TPMLGamepadMappingPriority.API) <> nil;
  finally
    FJoy.Unlock;
  end;
end;

procedure TPMLGamepadSystem.ReloadMappings;
var
  I: Integer;
begin
  FJoy.Lock;
  try
    TrackPush;
    try
      for I := 0 to High(FOpen) do
        TrackChanged(FOpen[I].Mapping);
      FDB.Clear;
      FDB.LoadInitial;
    finally
      TrackPop;
    end;
  finally
    FJoy.Unlock;
  end;
end;

procedure TPMLGamepadSystem.SetEventsEnabled(AEnabled: Boolean);
var
  I: Integer;
begin
  if FQueue = nil then
    Exit;
  for I := 0 to High(GamepadEventKinds) do
    FQueue.Enabled[GamepadEventKinds[I]] := AEnabled;
end;

function TPMLGamepadSystem.EventsEnabled: Boolean;
var
  I: Integer;
begin
  Result := False;
  if FQueue = nil then
    Exit;
  for I := 0 to High(GamepadEventKinds) do
    if FQueue.Enabled[GamepadEventKinds[I]] then
      Exit(True);
end;

function PMLCreateGamepadLayer(AJoy: TPMLJoystickSystem): TPMLJoystickGamepadLayer;
begin
  Result := TPMLGamepadSystem.Create(AJoy);
end;

end.
