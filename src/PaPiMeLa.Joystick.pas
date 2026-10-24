{
  PaPiMeLa.Joystick — ジョイスティックのサブシステム

  Origin : ported from SDL (src/joystick/SDL_joystick.c)
           Scope: SDL_InitJoysticks / SDL_QuitJoysticks、機器の一覧（SDL_GetJoysticks）と名前・パス・
           GUID・種類・player index の問い合わせ、SDL_OpenJoystick の ref_count とオープン、
           SDL_PrivateJoystickAdded / Removed、SDL_SendJoystickAxis / Ball / Hat / Button、
           SDL_UpdateJoysticks（ランブルの期限と再送、UpdateComplete）、SDL_SendJoystickPowerInfo、
           SDL_ShouldIgnoreJoystick、SDL_GetJoystickGUIDType、仮想ジョイスティックの窓口。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.6、§11 #59

  WHAT:
    Context が作って壊すサブシステム。登録されたバックエンド（Linux の evdev、仮想）を全部同時に使い、
    機器の抜き差しと入力を、ジョイスティックのイベント（JoystickAdded など）と、開いたジョイスティック
    （TPMLJoystick）の状態にする。イベントポンプのソースとして登録され、Pump のたびに更新する。

  RESOLVED:
    - 機器の一覧と ID の割り当ては SDL のまま（バックエンドが持つ一覧を、バックエンドの並び順に連ねる）
    - 軸の「最初の値」の扱い（静止の位置の探し方、揺れの許容）は SDL と同じ（SendAxis）
    - ウィンドウがあってキーボードフォーカスが無いときに入力を捨てる規則（ヒント
      PAPIMELA_JOYSTICK_ALLOW_BACKGROUND_EVENTS で切る）は、BackgroundGuard を差し込んだときだけ働く
      （Context が Video を持つときに差し込む）

  NOT RESOLVED:
    - タッチパッド・センサー・静電容量、Steam の仮想ゲームパッド、HIDAPI、ROG Ally の扱いは無い
    - ゲームパッド（SDL_IsGamepad）は PaPiMeLa.Gamepad が入るまで常に False

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Joystick;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Threading,
  PaPiMeLa.Properties,
  PaPiMeLa.Log,
  PaPiMeLa.Events,
  PaPiMeLa.Joystick.GUID,
  PaPiMeLa.Joystick.Tables,
  PaPiMeLa.Joystick.Backend,
  PaPiMeLa.Gamepad.Mapping;

type
  { ゲームパッドの層（PaPiMeLa.Gamepad の TPMLGamepadSystem が実装する）。マッピングの DB を持ち、
    機器がゲームパッドか、無視するか、を答え、ゲームパッドの Added / Removed と、遅れたガイドボタンの
    処理を受け持つ。差し込まれていなければ、ゲームパッドは無い（IsGamepad は False）。 }
  TPMLJoystickGamepadLayer = class abstract(TPMLSystemObject)
  public
    // ゲームパッドのイベントを止め、開いたものを全部閉じる（SDL_QuitGamepads）。
    procedure Shutdown; virtual; abstract;
    function  IsGamepad(AID: TPMLJoystickID): Boolean; virtual; abstract;
    function  ShouldIgnore(AVendor, AProduct, AVersion: Word; const AName: String): Boolean; virtual; abstract;
    procedure GamepadAdded(AID: TPMLJoystickID); virtual; abstract;
    procedure GamepadRemoved(AID: TPMLJoystickID); virtual; abstract;
    procedure DelayedGuideButton(AJoystick: TPMLJoystick); virtual; abstract;
  end;

  { ウィンドウがあってキーボードフォーカスが無いか（SDL_HasWindows() かつ SDL_GetKeyboardFocus() = NULL）。
    True の間は、入力のイベントを捨てる（静止に戻す動きは通す）。nil なら捨てない。 }
  TPMLJoystickBackgroundGuard = function: Boolean of object;

  TPMLJoystickSystem = class;

  // ゲームパッドの層を作る工場。ジョイスティックのサブシステムが、バックエンドを始める前に呼ぶ。
  TPMLJoystickGamepadLayerFactory = function(AJoy: TPMLJoystickSystem): TPMLJoystickGamepadLayer;

  TPMLJoystickSystem = class sealed(TPMLJoystickCore, IPMLEventPumpSource)
  strict private
    type
      TLists = record
        OldXboxOne, ArcadeStick, Blacklist, Drum, FlightStick, GameCube, Guitar, RogMice,
        Throttle, Wheel, ZeroCentered: TPMLVIDPIDList;
      end;
    var
    FQueue          : TPMLEventQueue;
    FHints          : TPMLHints;
    FLock           : TPMLMutex;
    FBackends       : array of TPMLJoystickBackend;
    FOpen           : array of TPMLJoystick;       // 新しく開いたものが先頭（SDL の連結リストと同じ）
    FPlayers        : array of TPMLJoystickID;     // player index -> ID（0 は空き）
    FLists          : TLists;
    FQuitting       : Boolean;
    FBeingAdded     : Boolean;
    FAllowBackground: Boolean;
    FGuard          : TPMLJoystickBackgroundGuard;
    FLayer          : TPMLJoystickGamepadLayer;
    procedure CreateLists;
    procedure FreeLists;
    procedure AllowBackgroundChanged(const AName: String; const AOld, ANew: TPMLHintValue);
    function  FindBackendAndIndex(AID: TPMLJoystickID; out ABackend: TPMLJoystickBackend;
      out AIndex: Integer): Boolean;
    function  FindFreePlayerIndex: Integer;
    function  PlayerIndexForIDLocked(AID: TPMLJoystickID): Integer;
    function  IDForPlayerIndexLocked(APlayerIndex: Integer): TPMLJoystickID;
    function  SetIDForPlayerIndexLocked(APlayerIndex: Integer; AID: TPMLJoystickID): Boolean;
    function  ShouldIgnoreEvent: Boolean;
    procedure PushEvent(const AEvent: TPMLEvent);
    procedure ForceRecentering(AJoystick: TPMLJoystick);
    procedure DoClose(AJoystick: TPMLJoystick);
    function  FindOpen(AID: TPMLJoystickID): TPMLJoystick;
    function  GetBackendCount: Integer;
    function  FindVirtual: IPMLVirtualJoystickBackend;
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject; AQueue: TPMLEventQueue;
      AHints: TPMLHints; AMakeLayer: TPMLJoystickGamepadLayerFactory = nil);
    destructor Destroy; override;

    { ---- アプリが使う ---- }
    // 今つながっている機器の ID（SDL_GetJoysticks）。バックエンドの並び順。
    function  Joysticks: TPMLJoystickIDs;
    // 機器があるか（SDL_HasJoystick）。
    function  HasJoystick: Boolean;
    { ID から機器の情報（SDL_GetJoystickNameForID など）。知らない ID は EPMLArgument。
      パスは持たない機器で ''。 }
    function  NameForID(AID: TPMLJoystickID): String;
    function  PathForID(AID: TPMLJoystickID): String;
    function  GUIDForID(AID: TPMLJoystickID): TPMLGUID;
    function  VendorForID(AID: TPMLJoystickID): Word;
    function  ProductForID(AID: TPMLJoystickID): Word;
    function  ProductVersionForID(AID: TPMLJoystickID): Word;
    function  TypeForID(AID: TPMLJoystickID): TPMLJoystickType;
    // 機器の player index（SDL_GetJoystickPlayerIndexForID）。無ければ -1。
    function  PlayerIndexForID(AID: TPMLJoystickID): Integer;
    { 開く（SDL_OpenJoystick）。同じ ID を開いていれば、それを返して数を足す。閉じるのは
      TPMLJoystick.Close（Open した回数だけ）。見つからなければ EPMLArgument、開けなければ EPMLInputError。 }
    function  Open(AID: TPMLJoystickID): TPMLJoystick;
    // 開いているジョイスティック（SDL_GetJoystickFromID）。開いていなければ nil。
    function  FromID(AID: TPMLJoystickID): TPMLJoystick;
    // player index のジョイスティック（SDL_GetJoystickFromPlayerIndex）。無ければ nil。
    function  FromPlayerIndex(APlayerIndex: Integer): TPMLJoystick;
    { ---- 仮想ジョイスティック ---- }
    function  AttachVirtual(const ADesc: TPMLVirtualJoystickDesc): TPMLJoystickID;
    procedure DetachVirtual(AID: TPMLJoystickID);
    function  IsVirtual(AID: TPMLJoystickID): Boolean;
    procedure SetVirtualAxis(AJoystick: TPMLJoystick; AAxis: Integer; AValue: SmallInt);
    procedure SetVirtualBall(AJoystick: TPMLJoystick; ABall: Integer; AXRel, AYRel: SmallInt);
    procedure SetVirtualButton(AJoystick: TPMLJoystick; AButton: Integer; ADown: Boolean);
    procedure SetVirtualHat(AJoystick: TPMLJoystick; AHat: Integer; AValue: Byte);
    { ---- 更新 ---- }
    // 全部のジョイスティックを更新して、抜き差しを調べる（SDL_UpdateJoysticks）。Pump も呼ぶ。
    procedure Update;
    // ジョイスティックのイベントをまとめて有効・無効にする（SDL_SetJoystickEventsEnabled）。
    procedure SetEventsEnabled(AEnabled: Boolean);
    function  EventsEnabled: Boolean;
    // 入力を捨ててよい（フォーカスが無い）かを聞く手続き。
    property  BackgroundGuard: TPMLJoystickBackgroundGuard read FGuard write FGuard;
    // ゲームパッドの層（Context が差し込む）。
    property  GamepadLayer: TPMLJoystickGamepadLayer read FLayer write FLayer;
    // 機器を足している最中か（SDL_IsJoystickBeingAdded）。ゲームパッドの Added を二重に出さないために見る。
    property  BeingAdded: Boolean read FBeingAdded;
    property  Hints: TPMLHints read FHints;
    property  Queue: TPMLEventQueue read FQueue;
    // バックエンドが言う、自動のマッピング（SDL_PrivateJoystickGetAutoGamepadMapping）。無ければ False。
    function  AutoGamepadMapping(AID: TPMLJoystickID; out AMapping: TPMLGamepadMapping): Boolean;
    // GameCube のアダプタか（SDL_IsJoystickGameCube）。
    function  IsGameCube(AVendor, AProduct: Word): Boolean;
    { ゲームパッドの種類（SDL_GetGamepadTypeFromVIDPID / SDL_GetGamepadTypeFromGUID）。AForUI は
      表示用の種類（GameCube などを見分ける）。HIDAPI は無いので、その GUID は Standard。 }
    function  GamepadTypeFromVIDPID(AVendor, AProduct: Word; const AName: String; AForUI: Boolean): TPMLGamepadType;
    function  GamepadTypeFromGUID(const AGUID: TPMLGUID; const AName: String): TPMLGamepadType;
    // 開いている機器の数（ゲームパッドが閉じ終わったかの確認用）。
    function  OpenCount: Integer;
    property  BackendCount: Integer read GetBackendCount;
    function  BackendName(AIndex: Integer): String;

    { ---- TPMLJoystickCore（バックエンドとジョイスティックが呼ぶ） ---- }
    procedure Lock; override;
    procedure Unlock; override;
    function  NextInstanceID: TPMLJoystickID; override;
    procedure DeviceAdded(AID: TPMLJoystickID); override;
    procedure DeviceRemoved(AID: TPMLJoystickID); override;
    procedure SendAxis(ATimestamp: UInt64; AJoystick: TPMLJoystick; AAxis: Byte; AValue: SmallInt); override;
    procedure SendBall(ATimestamp: UInt64; AJoystick: TPMLJoystick; ABall: Byte; AXRel, AYRel: SmallInt); override;
    procedure SendHat(ATimestamp: UInt64; AJoystick: TPMLJoystick; AHat: Byte; AValue: Byte); override;
    procedure SendButton(ATimestamp: UInt64; AJoystick: TPMLJoystick; AButton: Byte; ADown: Boolean); override;
    procedure SendPowerInfo(AJoystick: TPMLJoystick; AState: TPMLPowerState; APercent: Integer); override;
    function  TimestampNS: UInt64; override;
    function  TicksMS: UInt64; override;
    function  Hint(const AName: String): String; override;
    function  ShouldIgnoreDevice(AVendor, AProduct, AVersion: Word; const AName: String): Boolean; override;
    function  HandledByAnotherBackend(ABackend: TPMLJoystickBackend; AVendor, AProduct, AVersion: Word;
      const AName: String): Boolean; override;
    function  IsZeroCenteredDevice(AVendor, AProduct: Word): Boolean; override;
    function  IsGamepad(AID: TPMLJoystickID): Boolean; override;
    procedure CloseJoystick(AJoystick: TPMLJoystick); override;
    function  PlayerIndexOf(AID: TPMLJoystickID): Integer; override;
    function  SetPlayerIndexOf(AID: TPMLJoystickID; APlayerIndex: Integer): Boolean; override;
    function  JoystickTypeOf(const AGUID: TPMLGUID): TPMLJoystickType; override;

    { IPMLEventPumpSource }
    function  PumpSourceName: String;
    procedure PumpEvents(ATimeoutMs: Integer);
  end;

implementation

var
  // 機器の ID の次の値（プロセスに 1 つ。SDL_GetNextObjectID の相当）。
  GNextInstanceID: LongInt = 0;

{ ---- 作る・壊す ---- }

constructor TPMLJoystickSystem.Create(AContextRef: TObject; AOwner: TPMLObject;
  AQueue: TPMLEventQueue; AHints: TPMLHints; AMakeLayer: TPMLJoystickGamepadLayerFactory);
var
  Names: TStringArray;
  I: Integer;
  Factory: TPMLJoystickBackendFactory;
  B: TPMLJoystickBackend;
begin
  inherited Create(AContextRef, AOwner);
  FQueue := AQueue;
  FHints := AHints;
  FLock := TPMLMutex.Create;
  CreateLists;
  if FHints <> nil then
    FHints.AddCallback(PML_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, @AllowBackgroundChanged);
  Lock;
  try
    // マッピングの DB は、バックエンドが機器を見つけるより前に要る
    if Assigned(AMakeLayer) then
      FLayer := AMakeLayer(Self);
    // 登録されたバックエンドを、並び順（優先度の大きい順）に全部始める。始められなければ使わない
    Names := PMLJoystickBackendNames;
    for I := 0 to High(Names) do
    begin
      Factory := PMLFindJoystickBackend(Names[I]);
      if not Assigned(Factory) then
        Continue;
      B := nil;
      try
        B := Factory(Self);
        if (B <> nil) and B.Init then
        begin
          SetLength(FBackends, Length(FBackends) + 1);
          FBackends[High(FBackends)] := B;
        end
        else
          B.Free;
      except
        on E: Exception do
        begin
          B.Free;
          if ContextServices <> nil then
            ContextServices.Log.Debug(PML_LOG_CATEGORY_INPUT,
              Format('joystick backend "%s" failed: %s', [Names[I], E.Message]));
        end;
      end;
    end;
  finally
    Unlock;
  end;
  if FQueue <> nil then
    FQueue.RegisterPumpSource(Self as IPMLEventPumpSource);
end;

destructor TPMLJoystickSystem.Destroy;
var
  IDs: TPMLJoystickIDs;
  I: Integer;
begin
  if FQueue <> nil then
    FQueue.UnregisterPumpSource(Self as IPMLEventPumpSource);
  if FLayer <> nil then
    FLayer.Shutdown;
  Lock;
  try
    FQuitting := True;
    // 残っている機器を外し、開いたものを全部閉じる（SDL_QuitJoysticks）
    IDs := Joysticks;
    for I := 0 to High(IDs) do
      DeviceRemoved(IDs[I]);
    while Length(FOpen) > 0 do
      DoClose(FOpen[0]);
    // バックエンドは逆順に終わる（依存を壊さないため）
    for I := High(FBackends) downto 0 do
    begin
      FBackends[I].Quit;
      FBackends[I].Free;
    end;
    FBackends := nil;
    FPlayers := nil;
  finally
    Unlock;
  end;
  FreeAndNil(FLayer);
  if FHints <> nil then
    FHints.RemoveCallback(PML_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, @AllowBackgroundChanged);
  FreeLists;
  FLock.Free;
  inherited Destroy;
end;

procedure TPMLJoystickSystem.CreateLists;
begin
  FLists.OldXboxOne := TPMLVIDPIDList.Create(FHints, JoystickOldXboxOneControllersInitial,
    PML_HINT_JOYSTICK_OLD_XBOXONE_CONTROLLERS, PML_HINT_JOYSTICK_OLD_XBOXONE_CONTROLLERS_EXCLUDED);
  FLists.ArcadeStick := TPMLVIDPIDList.Create(FHints, JoystickArcadeStickDevicesInitial,
    PML_HINT_JOYSTICK_ARCADESTICK_DEVICES, PML_HINT_JOYSTICK_ARCADESTICK_DEVICES_EXCLUDED);
  FLists.Blacklist := TPMLVIDPIDList.Create(FHints, JoystickBlacklistDevicesInitial,
    PML_HINT_JOYSTICK_BLACKLIST_DEVICES, PML_HINT_JOYSTICK_BLACKLIST_DEVICES_EXCLUDED);
  FLists.Drum := TPMLVIDPIDList.Create(FHints, JoystickDrumDevicesInitial,
    PML_HINT_JOYSTICK_DRUM_DEVICES, '');
  FLists.FlightStick := TPMLVIDPIDList.Create(FHints, JoystickFlightStickDevicesInitial,
    PML_HINT_JOYSTICK_FLIGHTSTICK_DEVICES, PML_HINT_JOYSTICK_FLIGHTSTICK_DEVICES_EXCLUDED);
  FLists.GameCube := TPMLVIDPIDList.Create(FHints, JoystickGameCubeDevicesInitial,
    PML_HINT_JOYSTICK_GAMECUBE_DEVICES, PML_HINT_JOYSTICK_GAMECUBE_DEVICES_EXCLUDED);
  FLists.Guitar := TPMLVIDPIDList.Create(FHints, JoystickGuitarDevicesInitial,
    PML_HINT_JOYSTICK_GUITAR_DEVICES, '');
  FLists.RogMice := TPMLVIDPIDList.Create(FHints, JoystickROGGamepadMiceInitial,
    PML_HINT_ROG_GAMEPAD_MICE, PML_HINT_ROG_GAMEPAD_MICE_EXCLUDED);
  FLists.Throttle := TPMLVIDPIDList.Create(FHints, JoystickThrottleDevicesInitial,
    PML_HINT_JOYSTICK_THROTTLE_DEVICES, PML_HINT_JOYSTICK_THROTTLE_DEVICES_EXCLUDED);
  FLists.Wheel := TPMLVIDPIDList.Create(FHints, JoystickWheelDevicesInitial,
    PML_HINT_JOYSTICK_WHEEL_DEVICES, PML_HINT_JOYSTICK_WHEEL_DEVICES_EXCLUDED);
  FLists.ZeroCentered := TPMLVIDPIDList.Create(FHints, JoystickZeroCenteredDevicesInitial,
    PML_HINT_JOYSTICK_ZERO_CENTERED_DEVICES, '');
end;

procedure TPMLJoystickSystem.FreeLists;
begin
  FreeAndNil(FLists.OldXboxOne);
  FreeAndNil(FLists.ArcadeStick);
  FreeAndNil(FLists.Blacklist);
  FreeAndNil(FLists.Drum);
  FreeAndNil(FLists.FlightStick);
  FreeAndNil(FLists.GameCube);
  FreeAndNil(FLists.Guitar);
  FreeAndNil(FLists.RogMice);
  FreeAndNil(FLists.Throttle);
  FreeAndNil(FLists.Wheel);
  FreeAndNil(FLists.ZeroCentered);
end;

procedure TPMLJoystickSystem.AllowBackgroundChanged(const AName: String; const AOld, ANew: TPMLHintValue);
begin
  FAllowBackground := PMLStringBoolean(FHints.GetHint(PML_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS), False);
end;

function TPMLJoystickSystem.GetBackendCount: Integer;
begin
  Result := Length(FBackends);
end;

function TPMLJoystickSystem.BackendName(AIndex: Integer): String;
begin
  Result := FBackends[AIndex].Name;
end;

function TPMLJoystickSystem.FindVirtual: IPMLVirtualJoystickBackend;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(FBackends) do
    if Supports(FBackends[I], IPMLVirtualJoystickBackend, Result) then
      Exit;
  Result := nil;
end;

{ ---- ロック・時刻・ヒント ---- }

procedure TPMLJoystickSystem.Lock;
begin
  FLock.Lock;
end;

procedure TPMLJoystickSystem.Unlock;
begin
  FLock.Unlock;
end;

function TPMLJoystickSystem.NextInstanceID: TPMLJoystickID;
begin
  repeat
    Result := TPMLJoystickID(LongWord(InterLockedIncrement(GNextInstanceID)));
  until Result <> 0;
end;

function TPMLJoystickSystem.TimestampNS: UInt64;
begin
  Result := PMLNowNS;
end;

function TPMLJoystickSystem.TicksMS: UInt64;
begin
  Result := PMLNowNS div 1000000;
end;

function TPMLJoystickSystem.Hint(const AName: String): String;
begin
  if FHints = nil then
    Result := ''
  else
    Result := FHints.GetHint(AName);
end;

{ ---- 機器の検索 ---- }

function TPMLJoystickSystem.FindBackendAndIndex(AID: TPMLJoystickID; out ABackend: TPMLJoystickBackend;
  out AIndex: Integer): Boolean;
var
  I, N: Integer;
begin
  ABackend := nil;
  AIndex := -1;
  Result := False;
  if AID = 0 then
    Exit;
  for I := 0 to High(FBackends) do
    for N := 0 to FBackends[I].DeviceCount - 1 do
      if FBackends[I].DeviceInstanceID(N) = AID then
      begin
        ABackend := FBackends[I];
        AIndex := N;
        Exit(True);
      end;
end;

function TPMLJoystickSystem.Joysticks: TPMLJoystickIDs;
var
  I, N, Total: Integer;
begin
  Lock;
  try
    Total := 0;
    for I := 0 to High(FBackends) do
      Inc(Total, FBackends[I].DeviceCount);
    SetLength(Result, Total);
    Total := 0;
    for I := 0 to High(FBackends) do
      for N := 0 to FBackends[I].DeviceCount - 1 do
      begin
        Result[Total] := FBackends[I].DeviceInstanceID(N);
        Inc(Total);
      end;
  finally
    Unlock;
  end;
end;

function TPMLJoystickSystem.HasJoystick: Boolean;
var
  I: Integer;
begin
  Result := False;
  Lock;
  try
    for I := 0 to High(FBackends) do
      if FBackends[I].DeviceCount > 0 then
        Exit(True);
  finally
    Unlock;
  end;
end;

function TPMLJoystickSystem.NameForID(AID: TPMLJoystickID): String;
var
  B: TPMLJoystickBackend;
  N: Integer;
begin
  Lock;
  try
    if not FindBackendAndIndex(AID, B, N) then
      raise EPMLArgument.CreateFmt('Joystick %d not found', [AID]);
    Result := B.DeviceName(N);
  finally
    Unlock;
  end;
end;

function TPMLJoystickSystem.PathForID(AID: TPMLJoystickID): String;
var
  B: TPMLJoystickBackend;
  N: Integer;
begin
  Lock;
  try
    if not FindBackendAndIndex(AID, B, N) then
      raise EPMLArgument.CreateFmt('Joystick %d not found', [AID]);
    Result := B.DevicePath(N);
  finally
    Unlock;
  end;
end;

function TPMLJoystickSystem.GUIDForID(AID: TPMLJoystickID): TPMLGUID;
var
  B: TPMLJoystickBackend;
  N: Integer;
begin
  Lock;
  try
    if FindBackendAndIndex(AID, B, N) then
      Result := B.DeviceGUID(N)
    else
      Result := PMLZeroGUID;
  finally
    Unlock;
  end;
end;

function TPMLJoystickSystem.VendorForID(AID: TPMLJoystickID): Word;
var
  P, V, C: Word;
begin
  PMLGetJoystickGUIDInfo(GUIDForID(AID), Result, P, V, C);
end;

function TPMLJoystickSystem.ProductForID(AID: TPMLJoystickID): Word;
var
  V, Ver, C: Word;
begin
  PMLGetJoystickGUIDInfo(GUIDForID(AID), V, Result, Ver, C);
end;

function TPMLJoystickSystem.ProductVersionForID(AID: TPMLJoystickID): Word;
var
  V, P, C: Word;
begin
  PMLGetJoystickGUIDInfo(GUIDForID(AID), V, P, Result, C);
end;

function TPMLJoystickSystem.TypeForID(AID: TPMLJoystickID): TPMLJoystickType;
begin
  Result := JoystickTypeOf(GUIDForID(AID));
  if (Result = TPMLJoystickType.Unknown) and IsGamepad(AID) then
    Result := TPMLJoystickType.Gamepad;
end;

function TPMLJoystickSystem.PlayerIndexForID(AID: TPMLJoystickID): Integer;
begin
  Result := PlayerIndexOf(AID);
end;

{ ---- player index ---- }

function TPMLJoystickSystem.FindFreePlayerIndex: Integer;
begin
  Result := 0;
  while Result < Length(FPlayers) do
  begin
    if FPlayers[Result] = 0 then
      Break;
    Inc(Result);
  end;
end;

function TPMLJoystickSystem.PlayerIndexForIDLocked(AID: TPMLJoystickID): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FPlayers) do
    if FPlayers[I] = AID then
      Exit(I);
  Result := -1;
end;

function TPMLJoystickSystem.IDForPlayerIndexLocked(APlayerIndex: Integer): TPMLJoystickID;
begin
  if (APlayerIndex < 0) or (APlayerIndex >= Length(FPlayers)) then
    Result := 0
  else
    Result := FPlayers[APlayerIndex];
end;

function TPMLJoystickSystem.SetIDForPlayerIndexLocked(APlayerIndex: Integer; AID: TPMLJoystickID): Boolean;
var
  Existing: TPMLJoystickID;
  Old, OldCount: Integer;
  B: TPMLJoystickBackend;
  N: Integer;
begin
  Existing := IDForPlayerIndexLocked(APlayerIndex);
  if APlayerIndex >= Length(FPlayers) then
  begin
    OldCount := Length(FPlayers);
    SetLength(FPlayers, APlayerIndex + 1);
    FillChar(FPlayers[OldCount], (APlayerIndex - OldCount + 1) * SizeOf(FPlayers[0]), 0);
  end
  else if (APlayerIndex >= 0) and (FPlayers[APlayerIndex] = AID) then
    Exit(True);        // 既に割り当て済み

  // 古い player index を空ける
  Old := PlayerIndexForIDLocked(AID);
  if Old >= 0 then
    FPlayers[Old] := 0;
  if APlayerIndex >= 0 then
    FPlayers[APlayerIndex] := AID;

  // バックエンドへ新しい番号を知らせる
  if FindBackendAndIndex(AID, B, N) then
    B.SetDevicePlayerIndex(N, APlayerIndex);

  // 元の持ち主を別の空きへ動かす
  if Existing > 0 then
    SetIDForPlayerIndexLocked(FindFreePlayerIndex, Existing);
  Result := True;
end;

function TPMLJoystickSystem.PlayerIndexOf(AID: TPMLJoystickID): Integer;
begin
  Lock;
  try
    Result := PlayerIndexForIDLocked(AID);
  finally
    Unlock;
  end;
end;

function TPMLJoystickSystem.SetPlayerIndexOf(AID: TPMLJoystickID; APlayerIndex: Integer): Boolean;
begin
  Lock;
  try
    Result := SetIDForPlayerIndexLocked(APlayerIndex, AID);
  finally
    Unlock;
  end;
end;

function TPMLJoystickSystem.FromPlayerIndex(APlayerIndex: Integer): TPMLJoystick;
begin
  Lock;
  try
    Result := FindOpen(IDForPlayerIndexLocked(APlayerIndex));
  finally
    Unlock;
  end;
end;

{ ---- 開く・閉じる ---- }

function TPMLJoystickSystem.FindOpen(AID: TPMLJoystickID): TPMLJoystick;
var
  I: Integer;
begin
  Result := nil;
  if AID = 0 then
    Exit;
  for I := 0 to High(FOpen) do
    if FOpen[I].ID = AID then
      Exit(FOpen[I]);
end;

function TPMLJoystickSystem.FromID(AID: TPMLJoystickID): TPMLJoystick;
begin
  Lock;
  try
    Result := FindOpen(AID);
  finally
    Unlock;
  end;
end;

function TPMLJoystickSystem.Open(AID: TPMLJoystickID): TPMLJoystick;
var
  B: TPMLJoystickBackend;
  N, I: Integer;
  Virtual_: IPMLVirtualJoystickBackend;
begin
  Lock;
  try
    if not FindBackendAndIndex(AID, B, N) then
      raise EPMLArgument.CreateFmt('Joystick %d not found', [AID]);
    // 開いていれば、それを返す（ID ごとに 1 つ）
    Result := FindOpen(AID);
    if Result <> nil then
    begin
      Result.RefAdd;
      Exit;
    end;
    Result := TPMLJoystick.Create(ContextRef, Self, Self, B, AID);
    try
      if not B.Open(Result, N) then
        raise EPMLInputError.Create(B.LastError);
      Result.Setup(B.DeviceName(N), B.DevicePath(N), B.DeviceGUID(N),
        Supports(B, IPMLVirtualJoystickBackend, Virtual_));
    except
      Result.Free;
      raise;
    end;
    // 先頭に連ねる（SDL の連結リストと同じ）
    SetLength(FOpen, Length(FOpen) + 1);
    for I := High(FOpen) downto 1 do
      FOpen[I] := FOpen[I - 1];
    FOpen[0] := Result;
    Result.RefAdd;
    B.Update(Result);
  finally
    Unlock;
  end;
end;

procedure TPMLJoystickSystem.CloseJoystick(AJoystick: TPMLJoystick);
begin
  Lock;
  try
    if AJoystick.RefRelease > 0 then
      Exit;
    DoClose(AJoystick);
  finally
    Unlock;
  end;
end;

procedure TPMLJoystickSystem.DoClose(AJoystick: TPMLJoystick);
var
  I, J: Integer;
begin
  AJoystick.StopRumbleForClose;
  AJoystick.Backend.Close(AJoystick);
  AJoystick.HwData := nil;
  for I := 0 to High(FOpen) do
    if FOpen[I] = AJoystick then
    begin
      for J := I to High(FOpen) - 1 do
        FOpen[J] := FOpen[J + 1];
      SetLength(FOpen, Length(FOpen) - 1);
      Break;
    end;
  AJoystick.Free;
end;

{ ---- 抜き差し ---- }

function TPMLJoystickSystem.IsGamepad(AID: TPMLJoystickID): Boolean;
begin
  Result := (FLayer <> nil) and FLayer.IsGamepad(AID);
end;

function TPMLJoystickSystem.AutoGamepadMapping(AID: TPMLJoystickID; out AMapping: TPMLGamepadMapping): Boolean;
var
  B: TPMLJoystickBackend;
  N: Integer;
begin
  AMapping := PMLEmptyGamepadMapping;
  Lock;
  try
    Result := FindBackendAndIndex(AID, B, N) and B.GamepadMapping(N, AMapping);
  finally
    Unlock;
  end;
end;

function TPMLJoystickSystem.IsGameCube(AVendor, AProduct: Word): Boolean;
begin
  Result := FLists.GameCube.Contains(AVendor, AProduct);
end;

function TPMLJoystickSystem.OpenCount: Integer;
begin
  Result := Length(FOpen);
end;

procedure TPMLJoystickSystem.PushEvent(const AEvent: TPMLEvent);
begin
  if FQueue <> nil then
    FQueue.Push(AEvent);
end;

procedure TPMLJoystickSystem.DeviceAdded(AID: TPMLJoystickID);
var
  B: TPMLJoystickBackend;
  N, PlayerIndex: Integer;
  E: TPMLEvent;
  IsGamepadNow: Boolean;
begin
  IsGamepadNow := False;
  if FQuitting then
    Exit;
  FBeingAdded := True;
  try
    PlayerIndex := -1;
    if FindBackendAndIndex(AID, B, N) then
      PlayerIndex := B.DevicePlayerIndex(N);
    if (PlayerIndex < 0) and IsGamepad(AID) then
      PlayerIndex := FindFreePlayerIndex;
    if PlayerIndex >= 0 then
      SetIDForPlayerIndexLocked(PlayerIndex, AID);
    if (FQueue <> nil) and FQueue.Enabled[TPMLEventKind.JoystickAdded] then
    begin
      E := Default(TPMLEvent);
      E.Kind := TPMLEventKind.JoystickAdded;
      E.Timestamp := TimestampNS;
      E.JDevice.Which := AID;
      PushEvent(E);
    end;
    // 自動のマッピングを作るかもしれないので、判定はイベントのあと（SDL と同じ）
    IsGamepadNow := IsGamepad(AID);
  finally
    FBeingAdded := False;
  end;
  if IsGamepadNow and (FLayer <> nil) then
    FLayer.GamepadAdded(AID);
end;

procedure TPMLJoystickSystem.ForceRecentering(AJoystick: TPMLJoystick);
var
  I: Integer;
  Timestamp: UInt64;
  Info: ^TPMLJoystickAxisInfo;
begin
  Timestamp := TimestampNS;
  // すべて静止・離した状態に戻したと、アプリへ知らせる
  for I := 0 to AJoystick.NumAxes - 1 do
  begin
    Info := AJoystick.AxisInfoPtr(I);
    if Info^.HasInitialValue then
      SendAxis(Timestamp, AJoystick, I, Info^.Zero);
  end;
  for I := 0 to AJoystick.NumButtons - 1 do
    SendButton(Timestamp, AJoystick, I, False);
  for I := 0 to AJoystick.NumHats - 1 do
    SendHat(Timestamp, AJoystick, I, PML_HAT_CENTERED);
end;

procedure TPMLJoystickSystem.DeviceRemoved(AID: TPMLJoystickID);
var
  J: TPMLJoystick;
  E: TPMLEvent;
  PlayerIndex: Integer;
begin
  J := FindOpen(AID);
  if J <> nil then
  begin
    ForceRecentering(J);
    J.SetAttached(False);
  end;
  if IsGamepad(AID) and (FLayer <> nil) then
    FLayer.GamepadRemoved(AID);
  if (FQueue <> nil) and FQueue.Enabled[TPMLEventKind.JoystickRemoved] then
  begin
    E := Default(TPMLEvent);
    E.Kind := TPMLEventKind.JoystickRemoved;
    E.Timestamp := TimestampNS;
    E.JDevice.Which := AID;
    PushEvent(E);
  end;
  PlayerIndex := PlayerIndexForIDLocked(AID);
  if PlayerIndex >= 0 then
    FPlayers[PlayerIndex] := 0;
end;

{ ---- 状態の送り込み ---- }

function TPMLJoystickSystem.ShouldIgnoreEvent: Boolean;
begin
  if FAllowBackground then
    Exit(False);
  Result := Assigned(FGuard) and FGuard();
end;

procedure TPMLJoystickSystem.SendAxis(ATimestamp: UInt64; AJoystick: TPMLJoystick; AAxis: Byte; AValue: SmallInt);
const
  MaxAllowedJitter = PML_JOYSTICK_AXIS_MAX div 80;     // ShanWan の PS3 のコントローラが 96 を要した
var
  Info: ^TPMLJoystickAxisInfo;
  E: TPMLEvent;
begin
  if AAxis >= AJoystick.NumAxes then
    Exit;
  Info := AJoystick.AxisInfoPtr(AAxis);
  if (not Info^.HasInitialValue)
  or ((not Info^.HasSecondValue) and ((Info^.InitialValue <= -32767) or (Info^.InitialValue = 32767))
      and (Abs(AValue) < (PML_JOYSTICK_AXIS_MAX div 4))) then
  begin
    Info^.InitialValue := AValue;
    Info^.Value := AValue;
    Info^.Zero := AValue;
    Info^.HasInitialValue := True;
  end
  else if (AValue = Info^.Value) and not Info^.SendingInitialValue then
    Exit
  else
    Info^.HasSecondValue := True;
  if not Info^.SentInitialValue then
  begin
    // 本当に動くまで、動きを送らない（仮想ジョイスティックは別）
    if (Abs(AValue - Info^.Value) <= MaxAllowedJitter) and not PMLIsJoystickVirtualGUID(AJoystick.GUID) then
      Exit;
    Info^.SentInitialValue := True;
    Info^.SendingInitialValue := True;
    SendAxis(ATimestamp, AJoystick, AAxis, Info^.InitialValue);
    Info^.SendingInitialValue := False;
  end;
  // フォーカスが無いときは捨てる。静止に戻す動きは通す
  if ShouldIgnoreEvent then
    if Info^.SendingInitialValue or ((AValue > Info^.Zero) and (AValue >= Info^.Value))
    or ((AValue < Info^.Zero) and (AValue <= Info^.Value)) then
      Exit;
  Info^.Value := AValue;
  AJoystick.UpdateComplete := ATimestamp;
  if (FQueue <> nil) and FQueue.Enabled[TPMLEventKind.JoystickAxisMotion] then
  begin
    E := Default(TPMLEvent);
    E.Kind := TPMLEventKind.JoystickAxisMotion;
    E.Timestamp := ATimestamp;
    E.JAxis.Which := AJoystick.ID;
    E.JAxis.Axis := AAxis;
    E.JAxis.Value := AValue;
    PushEvent(E);
  end;
end;

procedure TPMLJoystickSystem.SendBall(ATimestamp: UInt64; AJoystick: TPMLJoystick; ABall: Byte; AXRel, AYRel: SmallInt);
var
  Ball: ^TPMLJoystickBallData;
  E: TPMLEvent;
begin
  if ABall >= AJoystick.NumBalls then
    Exit;
  if ShouldIgnoreEvent then
    Exit;
  Ball := AJoystick.BallPtr(ABall);
  Inc(Ball^.DX, AXRel);
  Inc(Ball^.DY, AYRel);
  if (FQueue <> nil) and FQueue.Enabled[TPMLEventKind.JoystickBallMotion] then
  begin
    E := Default(TPMLEvent);
    E.Kind := TPMLEventKind.JoystickBallMotion;
    E.Timestamp := ATimestamp;
    E.JBall.Which := AJoystick.ID;
    E.JBall.Ball := ABall;
    E.JBall.XRel := AXRel;
    E.JBall.YRel := AYRel;
    PushEvent(E);
  end;
end;

procedure TPMLJoystickSystem.SendHat(ATimestamp: UInt64; AJoystick: TPMLJoystick; AHat: Byte; AValue: Byte);
var
  Hat: PByte;
  E: TPMLEvent;
begin
  if AHat >= AJoystick.NumHats then
    Exit;
  Hat := AJoystick.HatPtr(AHat);
  if AValue = Hat^ then
    Exit;
  // フォーカスが無いときは捨てる。真ん中に戻す動きは通す
  if ShouldIgnoreEvent and (AValue <> PML_HAT_CENTERED) then
    Exit;
  Hat^ := AValue;
  AJoystick.UpdateComplete := ATimestamp;
  if (FQueue <> nil) and FQueue.Enabled[TPMLEventKind.JoystickHatMotion] then
  begin
    E := Default(TPMLEvent);
    E.Kind := TPMLEventKind.JoystickHatMotion;
    E.Timestamp := ATimestamp;
    E.JHat.Which := AJoystick.ID;
    E.JHat.Hat := AHat;
    E.JHat.Value := AValue;
    PushEvent(E);
  end;
end;

procedure TPMLJoystickSystem.SendButton(ATimestamp: UInt64; AJoystick: TPMLJoystick; AButton: Byte; ADown: Boolean);
var
  Button: PBoolean;
  Kind: TPMLEventKind;
  E: TPMLEvent;
begin
  if ADown then
    Kind := TPMLEventKind.JoystickButtonDown
  else
    Kind := TPMLEventKind.JoystickButtonUp;
  if AJoystick.SwapFaceButtons then
    case AButton of
      0: AButton := 1;
      1: AButton := 0;
      2: AButton := 3;
      3: AButton := 2;
    end;
  if AButton >= AJoystick.NumButtons then
    Exit;
  Button := AJoystick.ButtonPtr(AButton);
  if ADown = Button^ then
    Exit;
  // フォーカスが無いときは捨てる。離す動きは通す
  if ShouldIgnoreEvent and ADown then
    Exit;
  Button^ := ADown;
  AJoystick.UpdateComplete := ATimestamp;
  if (FQueue <> nil) and FQueue.Enabled[Kind] then
  begin
    E := Default(TPMLEvent);
    E.Kind := Kind;
    E.Timestamp := ATimestamp;
    E.JButton.Which := AJoystick.ID;
    E.JButton.Button := AButton;
    E.JButton.Down := ADown;
    PushEvent(E);
  end;
end;

procedure TPMLJoystickSystem.SendPowerInfo(AJoystick: TPMLJoystick; AState: TPMLPowerState; APercent: Integer);
var
  E: TPMLEvent;
begin
  if (AState = AJoystick.BatteryState) and (APercent = AJoystick.BatteryPercent) then
    Exit;
  AJoystick.SetPower(AState, APercent);
  if (FQueue <> nil) and FQueue.Enabled[TPMLEventKind.JoystickBatteryUpdated] then
  begin
    E := Default(TPMLEvent);
    E.Kind := TPMLEventKind.JoystickBatteryUpdated;
    E.Timestamp := TimestampNS;
    E.JBattery.Which := AJoystick.ID;
    E.JBattery.State := AState;
    E.JBattery.Percent := APercent;
    PushEvent(E);
  end;
end;

{ ---- 更新 ---- }

procedure TPMLJoystickSystem.Update;
var
  I: Integer;
  J: TPMLJoystick;
  E: TPMLEvent;
  Snapshot: array of TPMLJoystick;
begin
  Lock;
  try
    // 更新の途中で開閉されても壊れないよう、今の並びの写しを回る
    SetLength(Snapshot, Length(FOpen));
    for I := 0 to High(FOpen) do
      Snapshot[I] := FOpen[I];
    for I := 0 to High(Snapshot) do
    begin
      J := Snapshot[I];
      if not J.Connected then
        Continue;
      J.Backend.Update(J);
      if J.DelayedGuideButton and (FLayer <> nil) then
        FLayer.DelayedGuideButton(J);
      J.UpdateRumbleTimers;
    end;
    if (FQueue <> nil) and FQueue.Enabled[TPMLEventKind.JoystickUpdateComplete] then
      for I := 0 to High(Snapshot) do
      begin
        J := Snapshot[I];
        if J.UpdateComplete <> 0 then
        begin
          E := Default(TPMLEvent);
          E.Kind := TPMLEventKind.JoystickUpdateComplete;
          E.Timestamp := J.UpdateComplete;
          E.JDevice.Which := J.ID;
          PushEvent(E);
          J.UpdateComplete := 0;
        end;
      end;
    // 抜き差しの検出は、ジョイスティックを回ったあと（外れた機器の持ち物を片付けられるように）
    for I := 0 to High(FBackends) do
      FBackends[I].Detect;
  finally
    Unlock;
  end;
end;

function TPMLJoystickSystem.PumpSourceName: String;
begin
  Result := 'joystick';
end;

procedure TPMLJoystickSystem.PumpEvents(ATimeoutMs: Integer);
begin
  // SDL_PumpEvents は、ジョイスティックのイベントが有効なときだけ SDL_UpdateJoysticks を呼ぶ
  if EventsEnabled then
    Update;
end;

const
  JoystickEventKinds: array[0..7] of TPMLEventKind = (
    TPMLEventKind.JoystickAxisMotion, TPMLEventKind.JoystickBallMotion, TPMLEventKind.JoystickHatMotion,
    TPMLEventKind.JoystickButtonDown, TPMLEventKind.JoystickButtonUp, TPMLEventKind.JoystickAdded,
    TPMLEventKind.JoystickRemoved, TPMLEventKind.JoystickBatteryUpdated);

procedure TPMLJoystickSystem.SetEventsEnabled(AEnabled: Boolean);
var
  I: Integer;
begin
  if FQueue = nil then
    Exit;
  for I := 0 to High(JoystickEventKinds) do
    FQueue.Enabled[JoystickEventKinds[I]] := AEnabled;
end;

function TPMLJoystickSystem.EventsEnabled: Boolean;
var
  I: Integer;
begin
  Result := False;
  if FQueue = nil then
    Exit;
  for I := 0 to High(JoystickEventKinds) do
    if FQueue.Enabled[JoystickEventKinds[I]] then
      Exit(True);
end;

{ ---- 機器の扱い ---- }

function TPMLJoystickSystem.ShouldIgnoreDevice(AVendor, AProduct, AVersion: Word; const AName: String): Boolean;
begin
  if FLists.Blacklist.Contains(AVendor, AProduct) then
    Exit(True);
  if not PMLStringBoolean(Hint(PML_HINT_JOYSTICK_ROG_CHAKRAM), False) then
    if FLists.RogMice.Contains(AVendor, AProduct) then
      Exit(True);
  Result := (FLayer <> nil) and FLayer.ShouldIgnore(AVendor, AProduct, AVersion, AName);
end;

function TPMLJoystickSystem.HandledByAnotherBackend(ABackend: TPMLJoystickBackend; AVendor, AProduct,
  AVersion: Word; const AName: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  Lock;
  try
    for I := 0 to High(FBackends) do
    begin
      if FBackends[I] = ABackend then
        Break;     // 優先度の高いバックエンドにはこの機器が無い
      if FBackends[I].IsDevicePresent(AVendor, AProduct, AVersion, AName) then
        Exit(True);
    end;
  finally
    Unlock;
  end;
end;

function TPMLJoystickSystem.IsZeroCenteredDevice(AVendor, AProduct: Word): Boolean;
begin
  Result := FLists.ZeroCentered.Contains(AVendor, AProduct);
end;

function IsWheelDevice(ALists: TPMLVIDPIDList; AVendor, AProduct, ACRC: Word): Boolean;
begin
  if (AVendor = $11FF) and (AProduct = $3331) and ((ACRC = $FAF6) or (ACRC = $2004)) then
    Exit(True);        // Oklick W-2 のレーシングホイール（Windows の DirectInput）
  Result := ALists.Contains(AVendor, AProduct);
end;

function TPMLJoystickSystem.JoystickTypeOf(const AGUID: TPMLGUID): TPMLJoystickType;
var
  V, P, Ver, CRC: Word;
begin
  PMLGetJoystickGUIDInfo(AGUID, V, P, Ver, CRC);
  if IsWheelDevice(FLists.Wheel, V, P, CRC) then
    Exit(TPMLJoystickType.Wheel);
  if FLists.ArcadeStick.Contains(V, P) then
    Exit(TPMLJoystickType.ArcadeStick);
  if FLists.FlightStick.Contains(V, P) then
    Exit(TPMLJoystickType.FlightStick);
  if FLists.Throttle.Contains(V, P) then
    Exit(TPMLJoystickType.Throttle);
  if FLists.Guitar.Contains(V, P) then
    Exit(TPMLJoystickType.Guitar);
  if FLists.Drum.Contains(V, P) then
    Exit(TPMLJoystickType.DrumKit);
  if PMLIsJoystickXInputGUID(AGUID) then
    case AGUID.Data[15] of
      $01: Exit(TPMLJoystickType.Gamepad);
      $02: Exit(TPMLJoystickType.Wheel);
      $03: Exit(TPMLJoystickType.ArcadeStick);
      $04: Exit(TPMLJoystickType.FlightStick);
      $05: Exit(TPMLJoystickType.DancePad);
      $06, $07, $0B: Exit(TPMLJoystickType.Guitar);
      $08: Exit(TPMLJoystickType.DrumKit);
      $13: Exit(TPMLJoystickType.ArcadePad);
    else
      Exit(TPMLJoystickType.Unknown);
    end;
  if PMLIsJoystickVirtualGUID(AGUID) then
  begin
    if AGUID.Data[15] <= Ord(High(TPMLJoystickType)) then
      Exit(TPMLJoystickType(AGUID.Data[15]));
    Exit(TPMLJoystickType.Unknown);
  end;
  if PMLGuessControllerType(FHints, V, P) <> PML_CONTROLLER_TYPE_UNKNOWN_NON_STEAM then
    Exit(TPMLJoystickType.Gamepad);
  Result := TPMLJoystickType.Unknown;
end;

{ ---- ゲームパッドの種類 ---- }

function TPMLJoystickSystem.GamepadTypeFromVIDPID(AVendor, AProduct: Word; const AName: String;
  AForUI: Boolean): TPMLGamepadType;
const
  VendorNintendo = $057E;
begin
  Result := TPMLGamepadType.Standard;
  if (AVendor = 0) and (AProduct = 0) then
  begin
    // 名前でしか分からない機器
    if (AName = 'Lic Pro Controller') or (AName = 'Nintendo Wireless Gamepad') or (AName = 'Wireless Gamepad') then
      Result := TPMLGamepadType.SwitchPro;
  end
  else if (AVendor = 1) and (AProduct = 1) then
    Result := TPMLGamepadType.Standard
  else if (AVendor = VendorNintendo) and ((AProduct = $2006) or (AProduct = $2067)) then
    Result := TPMLGamepadType.JoyConLeft
  else if (AVendor = VendorNintendo) and ((AProduct = $2007) or (AProduct = $2066)) then
  begin
    if Pos('NES Controller', AName) > 0 then
      Result := TPMLGamepadType.Standard
    else
      Result := TPMLGamepadType.JoyConRight;
  end
  else if (AVendor = VendorNintendo) and (AProduct = $200E) then
  begin
    if Pos('(L)', AName) > 0 then
      Result := TPMLGamepadType.JoyConLeft
    else if Pos('L+R', AName) > 0 then
      Result := TPMLGamepadType.JoyConPair
    else
      Result := TPMLGamepadType.JoyConRight;
  end
  else if (AVendor = VendorNintendo) and ((AProduct = $2008) or (AProduct = $2068)) then
    Result := TPMLGamepadType.JoyConPair
  else if AForUI and IsGameCube(AVendor, AProduct) then
    Result := TPMLGamepadType.GameCube
  else
    case PMLGuessControllerType(FHints, AVendor, AProduct) of
      PML_CONTROLLER_TYPE_XBOX360: Result := TPMLGamepadType.Xbox360;
      PML_CONTROLLER_TYPE_XBOXONE, PML_CONTROLLER_TYPE_XBOX_ELITE: Result := TPMLGamepadType.XboxOne;
      PML_CONTROLLER_TYPE_PS3: Result := TPMLGamepadType.PS3;
      PML_CONTROLLER_TYPE_PS4: Result := TPMLGamepadType.PS4;
      PML_CONTROLLER_TYPE_PS5, PML_CONTROLLER_TYPE_PS5_EDGE: Result := TPMLGamepadType.PS5;
      PML_CONTROLLER_TYPE_XINPUT_PS4:
        if AForUI then Result := TPMLGamepadType.PS4 else Result := TPMLGamepadType.Standard;
      PML_CONTROLLER_TYPE_SWITCH_PRO, PML_CONTROLLER_TYPE_SWITCH2_PRO,
      PML_CONTROLLER_TYPE_SWITCH_INPUT_ONLY, PML_CONTROLLER_TYPE_SWITCH2_INPUT_ONLY:
        Result := TPMLGamepadType.SwitchPro;
      PML_CONTROLLER_TYPE_XINPUT_SWITCH:
        if AForUI then Result := TPMLGamepadType.SwitchPro else Result := TPMLGamepadType.Xbox360;
      PML_CONTROLLER_TYPE_STEAM, PML_CONTROLLER_TYPE_STEAM_V2, PML_CONTROLLER_TYPE_STEAM_NEPTUNE,
      PML_CONTROLLER_TYPE_STEAM_TRITON, PML_CONTROLLER_TYPE_HORI_STEAM, PML_CONTROLLER_TYPE_UNKNOWN_STEAM:
        Result := TPMLGamepadType.Steam;
    end;
end;

function TPMLJoystickSystem.GamepadTypeFromGUID(const AGUID: TPMLGUID; const AName: String): TPMLGamepadType;
var
  V, P, Ver, CRC: Word;
begin
  PMLGetJoystickGUIDInfo(AGUID, V, P, Ver, CRC);
  Result := GamepadTypeFromVIDPID(V, P, AName, True);
  if (Result = TPMLGamepadType.Standard) and PMLIsJoystickXInputGUID(AGUID) then
    Result := TPMLGamepadType.XboxOne;
end;

{ ---- 仮想ジョイスティック ---- }

function TPMLJoystickSystem.AttachVirtual(const ADesc: TPMLVirtualJoystickDesc): TPMLJoystickID;
var
  V: IPMLVirtualJoystickBackend;
begin
  V := FindVirtual;
  if V = nil then
    raise EPMLUnsupported.Create('no virtual joystick backend is linked in');
  Lock;
  try
    Result := V.AttachVirtual(ADesc);
  finally
    Unlock;
  end;
end;

procedure TPMLJoystickSystem.DetachVirtual(AID: TPMLJoystickID);
var
  V: IPMLVirtualJoystickBackend;
begin
  V := FindVirtual;
  if V = nil then
    raise EPMLUnsupported.Create('no virtual joystick backend is linked in');
  Lock;
  try
    V.DetachVirtual(AID);
  finally
    Unlock;
  end;
end;

function TPMLJoystickSystem.IsVirtual(AID: TPMLJoystickID): Boolean;
var
  V: IPMLVirtualJoystickBackend;
begin
  V := FindVirtual;
  Result := False;
  if V = nil then
    Exit;
  Lock;
  try
    Result := V.IsVirtual(AID);
  finally
    Unlock;
  end;
end;

procedure TPMLJoystickSystem.SetVirtualAxis(AJoystick: TPMLJoystick; AAxis: Integer; AValue: SmallInt);
var
  V: IPMLVirtualJoystickBackend;
begin
  V := FindVirtual;
  if (V = nil) or not AJoystick.IsVirtual then
    raise EPMLArgument.Create('joystick isn''t virtual');
  Lock;
  try
    V.SetVirtualAxis(AJoystick, AAxis, AValue);
  finally
    Unlock;
  end;
end;

procedure TPMLJoystickSystem.SetVirtualBall(AJoystick: TPMLJoystick; ABall: Integer; AXRel, AYRel: SmallInt);
var
  V: IPMLVirtualJoystickBackend;
begin
  V := FindVirtual;
  if (V = nil) or not AJoystick.IsVirtual then
    raise EPMLArgument.Create('joystick isn''t virtual');
  Lock;
  try
    V.SetVirtualBall(AJoystick, ABall, AXRel, AYRel);
  finally
    Unlock;
  end;
end;

procedure TPMLJoystickSystem.SetVirtualButton(AJoystick: TPMLJoystick; AButton: Integer; ADown: Boolean);
var
  V: IPMLVirtualJoystickBackend;
begin
  V := FindVirtual;
  if (V = nil) or not AJoystick.IsVirtual then
    raise EPMLArgument.Create('joystick isn''t virtual');
  Lock;
  try
    V.SetVirtualButton(AJoystick, AButton, ADown);
  finally
    Unlock;
  end;
end;

procedure TPMLJoystickSystem.SetVirtualHat(AJoystick: TPMLJoystick; AHat: Integer; AValue: Byte);
var
  V: IPMLVirtualJoystickBackend;
begin
  V := FindVirtual;
  if (V = nil) or not AJoystick.IsVirtual then
    raise EPMLArgument.Create('joystick isn''t virtual');
  Lock;
  try
    V.SetVirtualHat(AJoystick, AHat, AValue);
  finally
    Unlock;
  end;
end;

end.
