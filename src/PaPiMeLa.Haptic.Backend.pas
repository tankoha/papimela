{
  PaPiMeLa.Haptic.Backend — ハプティクス（力覚）のバックエンドの抽象と、開いたデバイス

  Origin : ported from SDL (src/haptic/SDL_haptic.c, src/haptic/SDL_syshaptic.h,
           include/SDL3/SDL_haptic.h)
           Scope: SDL_HapticEffect とその部品の型・定数（SDL_haptic.h）、SDL_SYS_Haptic の入り口
           （SDL_syshaptic.h）、SDL_Haptic の中身と、デバイスごとの規則（SDL_haptic.c の
           SDL_CreateHapticEffect / Update / Run / Stop / Destroy / GetStatus、SDL_SetHapticGain /
           Autocenter、簡易ランブル SDL_InitHapticRumble / Play / Stop、ValidEffect、開くときの
           ゲイン最大・オートセンタ切り）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #63

  WHAT:
    具象バックエンド（Linux の evdev）が派生する TPMLHapticBackend と、コア
    （PaPiMeLa.Haptic の TPMLHapticSystem）が実装してバックエンドに渡す TPMLHapticCore、
    アプリが Open して使う TPMLHaptic。

  WHY:
    ジョイスティックと同じ割り方（PaPiMeLa.Joystick.Backend 参照）。SDL のバックエンドは
    SDL_SYS_Haptic〜という名前の関数を中核が直接呼ぶ。papimela は抽象クラスにして、検査が偽の機器を
    差し込めるようにする。

  RESOLVED:
    - SDL と同じに、スレッド安全にしない（SDL の haptic は排他を持たない）。メインスレッドから使う
    - 失敗の伝え方は、SDL の bool を返す関数は Boolean を返し、理由を TPMLHaptic.LastError に置く。
      資源を作る関数（Open、CreateEffect）は例外（EPMLInputError、引数は EPMLArgument）
    - 効果の番号は 0 から MaxEffects - 1 の空きの番号で、作った効果の無い番号に Run / Stop /
      Update を呼ぶと False（SDL は Linux でヌルを辿って落ちる。D-84 の疑い）
    - 効果の型は SDL の共用体と同じ並び（先頭が EffectType）。代入で丸ごと写せる

  NOT RESOLVED:
    - ゲームパッド（SDL_IsGamepad が真のジョイスティック）はハプティクスとして開けない。
      SDL3 の SDL_IsJoystickHaptic が sdl2-compat 以外では断る規則のまま（ランブルは Gamepad の側で使う）
    - HIDAPI のハプティクスは無い

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Haptic.Backend;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Errors,
  PaPiMeLa.Properties,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Joystick.Backend;

const
  // 継続時間の「無限」（SDL_HAPTIC_INFINITY）。
  PML_HAPTIC_INFINITY = $FFFFFFFF;

  // 効果の種類と、機器の能力（SDL_HAPTIC_xxx。どちらも同じ値で、足し合わせて使う）。
  PML_HAPTIC_CONSTANT     = 1 shl 0;
  PML_HAPTIC_SINE         = 1 shl 1;
  PML_HAPTIC_SQUARE       = 1 shl 2;
  PML_HAPTIC_TRIANGLE     = 1 shl 3;
  PML_HAPTIC_SAWTOOTHUP   = 1 shl 4;
  PML_HAPTIC_SAWTOOTHDOWN = 1 shl 5;
  PML_HAPTIC_RAMP         = 1 shl 6;
  PML_HAPTIC_SPRING       = 1 shl 7;
  PML_HAPTIC_DAMPER       = 1 shl 8;
  PML_HAPTIC_INERTIA      = 1 shl 9;
  PML_HAPTIC_FRICTION     = 1 shl 10;
  PML_HAPTIC_LEFTRIGHT    = 1 shl 11;
  PML_HAPTIC_CUSTOM       = 1 shl 15;
  // 機器の能力だけ
  PML_HAPTIC_GAIN         = 1 shl 16;
  PML_HAPTIC_AUTOCENTER   = 1 shl 17;
  PML_HAPTIC_STATUS       = 1 shl 18;
  PML_HAPTIC_PAUSE        = 1 shl 19;

  // 向きの種類（SDL_HAPTIC_POLAR など）。
  PML_HAPTIC_POLAR         = 0;
  PML_HAPTIC_CARTESIAN     = 1;
  PML_HAPTIC_SPHERICAL     = 2;
  PML_HAPTIC_STEERING_AXIS = 3;

type
  TPMLHapticID = type LongWord;
  TPMLHapticIDs = array of TPMLHapticID;
  // 効果の番号。作れなかったときは例外なので、負の値は「無い」の印にだけ使う。
  TPMLHapticEffectID = type Integer;

  // 向き（SDL_HapticDirection）。DirType は PML_HAPTIC_POLAR など。
  TPMLHapticDirection = record
    DirType: Byte;
    Dir    : array[0..2] of LongInt;
  end;

  // 一定の力（SDL_HapticConstant）。
  TPMLHapticConstant = record
    EffectType   : Word;
    Direction    : TPMLHapticDirection;
    Length       : Cardinal;
    Delay        : Word;
    Button       : Word;
    Interval     : Word;
    Level        : SmallInt;
    AttackLength : Word;
    AttackLevel  : Word;
    FadeLength   : Word;
    FadeLevel    : Word;
  end;

  // 周期的な力（SDL_HapticPeriodic。サイン・矩形・三角・のこぎり）。Phase は 100 分の 1 度。
  TPMLHapticPeriodic = record
    EffectType   : Word;
    Direction    : TPMLHapticDirection;
    Length       : Cardinal;
    Delay        : Word;
    Button       : Word;
    Interval     : Word;
    Period       : Word;
    Magnitude    : SmallInt;
    Offset       : SmallInt;
    Phase        : Word;
    AttackLength : Word;
    AttackLevel  : Word;
    FadeLength   : Word;
    FadeLevel    : Word;
  end;

  // 条件つきの力（SDL_HapticCondition。ばね・ダンパ・慣性・摩擦）。
  TPMLHapticCondition = record
    EffectType: Word;
    Direction : TPMLHapticDirection;
    Length    : Cardinal;
    Delay     : Word;
    Button    : Word;
    Interval  : Word;
    RightSat  : array[0..2] of Word;
    LeftSat   : array[0..2] of Word;
    RightCoeff: array[0..2] of SmallInt;
    LeftCoeff : array[0..2] of SmallInt;
    Deadband  : array[0..2] of Word;
    Center    : array[0..2] of SmallInt;
  end;

  // 傾斜（SDL_HapticRamp）。
  TPMLHapticRamp = record
    EffectType   : Word;
    Direction    : TPMLHapticDirection;
    Length       : Cardinal;
    Delay        : Word;
    Button       : Word;
    Interval     : Word;
    Start        : SmallInt;
    End_         : SmallInt;
    AttackLength : Word;
    AttackLevel  : Word;
    FadeLength   : Word;
    FadeLevel    : Word;
  end;

  // 左右のモーター（SDL_HapticLeftRight）。
  TPMLHapticLeftRight = record
    EffectType    : Word;
    Length        : Cardinal;
    LargeMagnitude: Word;
    SmallMagnitude: Word;
  end;

  // 波形の指定（SDL_HapticCustom）。Data は Channels * Samples 個。Linux は使えない。
  TPMLHapticCustom = record
    EffectType   : Word;
    Direction    : TPMLHapticDirection;
    Length       : Cardinal;
    Delay        : Word;
    Button       : Word;
    Interval     : Word;
    Channels     : Byte;
    Period       : Word;
    Samples      : Word;
    Data         : PWord;
    AttackLength : Word;
    AttackLevel  : Word;
    FadeLength   : Word;
    FadeLevel    : Word;
  end;

  { 効果（SDL_HapticEffect の共用体）。どの欄も先頭が EffectType なので、EffectType で種類を見て、
    その種類の欄を読む。 }
  TPMLHapticEffect = record
    case Integer of
      0: (EffectType: Word);
      1: (Constant : TPMLHapticConstant);
      2: (Periodic : TPMLHapticPeriodic);
      3: (Condition: TPMLHapticCondition);
      4: (Ramp     : TPMLHapticRamp);
      5: (LeftRight: TPMLHapticLeftRight);
      6: (Custom   : TPMLHapticCustom);
  end;

  TPMLHaptic = class;
  TPMLHapticBackend = class;

  { コアの口（バックエンドが呼ぶ）。PaPiMeLa.Haptic の TPMLHapticSystem が実装する。 }
  TPMLHapticCore = class abstract(TPMLSystemObject)
  public
    // 機器の ID を新しく振る（SDL_GetNextObjectID）。0 は「無い」。
    function  NextInstanceID: TPMLHapticID; virtual; abstract;
    // ヒントの効いている値（空なら ''）。
    function  Hint(const AName: String): String; virtual; abstract;
    // 開いている機器を返す（TPMLHaptic.Close から）。
    procedure CloseHaptic(AHaptic: TPMLHaptic); virtual; abstract;
  end;

  // 1 つの効果の置き場（SDL_haptic の haptic_effect）。Hw はバックエンドの持ち物（nil なら空き）。
  TPMLHapticSlot = record
    Effect: TPMLHapticEffect;
    Hw    : TObject;
  end;

  { 開いたハプティクスのデバイス（SDL_Haptic）。アプリは Close で返す（Free しない）。
    同じ ID を何度 Open しても同じオブジェクトで、Close した回数が Open の回数に達すると壊れる。 }
  TPMLHaptic = class(TPMLOwnedObject)
  strict private
    FCore       : TPMLHapticCore;
    FBackend    : TPMLHapticBackend;
    FID         : TPMLHapticID;
    FName       : String;
    FSlots      : array of TPMLHapticSlot;
    FNEffects   : Integer;
    FNPlaying   : Integer;
    FSupported  : Cardinal;
    FNAxes      : Integer;
    FRefCount   : Integer;
    FRumbleID   : TPMLHapticEffectID;
    FRumbleEffect: TPMLHapticEffect;
    FHwData     : TObject;
    FLastError  : String;
    function  Fail(const AMessage: String): Boolean;
    function  ValidEffect(AEffect: TPMLHapticEffectID): Boolean;
  protected
    procedure DetachFromOwner; override;
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject; ACore: TPMLHapticCore;
      ABackend: TPMLHapticBackend; AID: TPMLHapticID);
    destructor Destroy; override;

    // ---- バックエンドとコアが使う
    { バックエンドの Open が、機器の能力・軸の数・効果の数を決める。効果の置き場を作る。 }
    procedure Configure(ASupported: Cardinal; ANAxes, ANEffects, ANPlaying: Integer);
    // 名前と ID を決める（OpenFromJoystick が、joystick の側の機器の ID を持ち込む）。
    procedure SetIdentity(AID: TPMLHapticID; const AName: String);
    // 軸の数を後から変える（ヒント SDL_HINT_JOYSTICK_HAPTIC_AXES）。
    procedure SetAxes(ANAxes: Integer);
    function  RefAdd: Integer;
    function  RefRelease: Integer;
    { 閉じる前の後始末（SDL_CloseHaptic の中身）。作った効果を全部消す。 }
    procedure DestroyAllEffects;
    { 開いた直後の既定（SDL_OpenHaptic の終わり）。ゲインを最大にし、オートセンタを切る。失敗は無視する。 }
    procedure ApplyOpenDefaults;
    // 効果の置き場の中のバックエンドの持ち物。差し替えると前のものを Free する。
    function  EffectHw(ASlot: Integer): TObject;
    procedure SetEffectHw(ASlot: Integer; AHw: TObject);
    // 効果の記録（SDL が memcpy で持つ「今の効果」）。
    function  EffectSpec(ASlot: Integer): TPMLHapticEffect;
    // 今の呼び出しで失敗した理由（バックエンドが置く）。
    procedure SetError(const AMessage: String);
    property  Backend: TPMLHapticBackend read FBackend;
    property  Core: TPMLHapticCore read FCore;
    property  HwData: TObject read FHwData write FHwData;

    // ---- アプリが使う
    // 開いた機器を返す（SDL_CloseHaptic）。回数が尽きると壊れる。
    procedure Close;
    // 効果が使えるか（SDL_HapticEffectSupported）。
    function  EffectSupported(const AEffect: TPMLHapticEffect): Boolean;
    { 効果を作る（SDL_CreateHapticEffect）。使えない種類・空きの無いときは EPMLInputError。
      返る番号は 0 から。 }
    function  CreateEffect(const AEffect: TPMLHapticEffect): TPMLHapticEffectID;
    function  UpdateEffect(AEffect: TPMLHapticEffectID; const AData: TPMLHapticEffect): Boolean;
    function  RunEffect(AEffect: TPMLHapticEffectID; AIterations: Cardinal): Boolean;
    function  StopEffect(AEffect: TPMLHapticEffectID): Boolean;
    procedure DestroyEffect(AEffect: TPMLHapticEffectID);
    // 効果が鳴っているか（SDL_GetHapticEffectStatus）。能力 PML_HAPTIC_STATUS が無いと False。
    function  GetEffectStatus(AEffect: TPMLHapticEffectID): Boolean;
    // ゲイン 0〜100（SDL_SetHapticGain。ヒント PAPIMELA_HAPTIC_GAIN_MAX で最大を絞れる）。
    function  SetGain(AGain: Integer): Boolean;
    // オートセンタ 0〜100（SDL_SetHapticAutocenter）。
    function  SetAutocenter(AAutocenter: Integer): Boolean;
    function  Pause: Boolean;
    function  Resume: Boolean;
    function  StopEffects: Boolean;
    // 簡易ランブル（SDL_HapticRumbleSupported など）。強さは 0.0〜1.0、長さはミリ秒。
    function  RumbleSupported: Boolean;
    function  InitRumble: Boolean;
    function  PlayRumble(AStrength: Single; ALengthMS: Cardinal): Boolean;
    function  StopRumble: Boolean;

    property  ID: TPMLHapticID read FID;
    property  Name: String read FName;
    // 能力（PML_HAPTIC_xxx の足し合わせ）。
    property  Features: Cardinal read FSupported;
    property  NumAxes: Integer read FNAxes;
    property  MaxEffects: Integer read FNEffects;
    property  MaxEffectsPlaying: Integer read FNPlaying;
    property  LastError: String read FLastError;
  end;

  { バックエンド（SDL_SYS_Haptic の入り口）。機器の一覧を持ち、添字（0 から DeviceCount - 1）で指す。 }
  TPMLHapticBackend = class abstract
  strict private
    FCore: TPMLHapticCore;
  protected
    FLastError: String;
    property Core: TPMLHapticCore read FCore;
  public
    constructor Create(ACore: TPMLHapticCore);
    // 名前（'linux'）。
    function  Name: String; virtual; abstract;
    // 始める（SDL_SYS_HapticInit）。機器の一覧を作る。False ならこのバックエンドは使わない。
    function  Init: Boolean; virtual; abstract;
    procedure Quit; virtual;
    // 溜まった抜き差しを処理する（udev の通知の受け取り）。一覧を見る前にコアが呼ぶ。
    procedure Detect; virtual;
    function  DeviceCount: Integer; virtual; abstract;
    function  DeviceInstanceID(AIndex: Integer): TPMLHapticID; virtual; abstract;
    // 名前。開けないときは ''。
    function  DeviceName(AIndex: Integer): String; virtual; abstract;
    { 開く（SDL_SYS_HapticOpen）。AHaptic.Configure で能力と数を決める。失敗は False にして LastError に理由。 }
    function  Open(AHaptic: TPMLHaptic; AIndex: Integer): Boolean; virtual; abstract;
    // マウスの機器の添字（SDL_SYS_HapticMouse）。無ければ -1。
    function  MouseIndex: Integer; virtual; abstract;
    // ジョイスティックがハプティクスを持つか（SDL_SYS_JoystickIsHaptic）。
    function  JoystickIsHaptic(AJoystick: TPMLJoystick): Boolean; virtual; abstract;
    // 開いたハプティクスがそのジョイスティックと同じ機器か（SDL_SYS_JoystickSameHaptic）。
    function  JoystickSameHaptic(AHaptic: TPMLHaptic; AJoystick: TPMLJoystick): Boolean; virtual; abstract;
    // ジョイスティックから開く（SDL_SYS_HapticOpenFromJoystick）。ID と名前は SetIdentity で決める。
    function  OpenFromJoystick(AHaptic: TPMLHaptic; AJoystick: TPMLJoystick): Boolean; virtual; abstract;
    // 閉じる（SDL_SYS_HapticClose）。効果は呼ぶ前にコアが消している。
    procedure Close(AHaptic: TPMLHaptic); virtual; abstract;
    // 効果の操作。ASlot は効果の置き場の番号（コアが検査済み）。失敗は False で AHaptic.SetError。
    function  NewEffect(AHaptic: TPMLHaptic; ASlot: Integer; const ABase: TPMLHapticEffect): Boolean; virtual; abstract;
    function  UpdateEffect(AHaptic: TPMLHaptic; ASlot: Integer; const AData: TPMLHapticEffect): Boolean; virtual; abstract;
    function  RunEffect(AHaptic: TPMLHaptic; ASlot: Integer; AIterations: Cardinal): Boolean; virtual; abstract;
    function  StopEffect(AHaptic: TPMLHaptic; ASlot: Integer): Boolean; virtual; abstract;
    procedure DestroyEffect(AHaptic: TPMLHaptic; ASlot: Integer); virtual; abstract;
    // 鳴っていれば 1、鳴っていなければ 0、できなければ -1（SDL_SYS_HapticGetEffectStatus）。
    function  GetEffectStatus(AHaptic: TPMLHaptic; ASlot: Integer): Integer; virtual; abstract;
    function  SetGain(AHaptic: TPMLHaptic; AGain: Integer): Boolean; virtual; abstract;
    function  SetAutocenter(AHaptic: TPMLHaptic; AAutocenter: Integer): Boolean; virtual; abstract;
    function  Pause(AHaptic: TPMLHaptic): Boolean; virtual; abstract;
    function  Resume(AHaptic: TPMLHaptic): Boolean; virtual; abstract;
    function  StopAll(AHaptic: TPMLHaptic): Boolean; virtual; abstract;
    property  LastError: String read FLastError;
  end;

  // 作るだけの関数。作れなければ例外を投げる。
  TPMLHapticBackendFactory = function(ACore: TPMLHapticCore): TPMLHapticBackend;

{ ---- 登録 ----

  具象バックエンドは自分のユニットの initialization で自分を登録する。ハプティクスは登録された
  バックエンドを優先度の大きい順に試し、最初に Init が成功したものを使う（ジョイスティックと違って 1 つ）。
  名前は大文字小文字を区別せずに比べる。同じ名前を 2 度登録すると EPMLArgument。 }
procedure PMLRegisterHapticBackend(const AName: String; APriority: Integer;
  AFactory: TPMLHapticBackendFactory);
// 登録済みの名前を並べ順に返す。
function  PMLHapticBackendNames: TStringArray;
function  PMLFindHapticBackend(const AName: String): TPMLHapticBackendFactory;

implementation

{ TPMLHaptic }

constructor TPMLHaptic.Create(AContextRef: TObject; AOwner: TPMLObject; ACore: TPMLHapticCore;
  ABackend: TPMLHapticBackend; AID: TPMLHapticID);
begin
  inherited Create(AContextRef, AOwner);
  FCore := ACore;
  FBackend := ABackend;
  FID := AID;
  FRumbleID := -1;
end;

destructor TPMLHaptic.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FSlots) do
    FreeAndNil(FSlots[I].Hw);
  FSlots := nil;
  FreeAndNil(FHwData);
  inherited Destroy;
end;

procedure TPMLHaptic.DetachFromOwner;
begin
  inherited DetachFromOwner;
end;

function TPMLHaptic.Fail(const AMessage: String): Boolean;
begin
  FLastError := AMessage;
  Result := False;
end;

procedure TPMLHaptic.SetError(const AMessage: String);
begin
  FLastError := AMessage;
end;

procedure TPMLHaptic.Configure(ASupported: Cardinal; ANAxes, ANEffects, ANPlaying: Integer);
var
  I: Integer;
begin
  FSupported := ASupported;
  FNAxes := ANAxes;
  FNEffects := ANEffects;
  FNPlaying := ANPlaying;
  for I := 0 to High(FSlots) do
    FreeAndNil(FSlots[I].Hw);
  if ANEffects < 0 then
    ANEffects := 0;
  SetLength(FSlots, 0);
  SetLength(FSlots, ANEffects);
  FillChar(FSlots[0], Length(FSlots) * SizeOf(TPMLHapticSlot), 0);
end;

procedure TPMLHaptic.SetIdentity(AID: TPMLHapticID; const AName: String);
begin
  FID := AID;
  FName := AName;
end;

procedure TPMLHaptic.SetAxes(ANAxes: Integer);
begin
  FNAxes := ANAxes;
end;

function TPMLHaptic.RefAdd: Integer;
begin
  Inc(FRefCount);
  Result := FRefCount;
end;

function TPMLHaptic.RefRelease: Integer;
begin
  Dec(FRefCount);
  Result := FRefCount;
end;

procedure TPMLHaptic.DestroyAllEffects;
var
  I: Integer;
begin
  for I := 0 to High(FSlots) do
    if FSlots[I].Hw <> nil then
      DestroyEffect(I);
end;

function TPMLHaptic.EffectHw(ASlot: Integer): TObject;
begin
  Result := FSlots[ASlot].Hw;
end;

procedure TPMLHaptic.SetEffectHw(ASlot: Integer; AHw: TObject);
begin
  if FSlots[ASlot].Hw <> AHw then
    FSlots[ASlot].Hw.Free;
  FSlots[ASlot].Hw := AHw;
end;

function TPMLHaptic.EffectSpec(ASlot: Integer): TPMLHapticEffect;
begin
  Result := FSlots[ASlot].Effect;
end;

function TPMLHaptic.ValidEffect(AEffect: TPMLHapticEffectID): Boolean;
begin
  if (AEffect < 0) or (AEffect >= FNEffects) then
    Exit(Fail('Haptic: Invalid effect identifier.'));
  Result := True;
end;


procedure TPMLHaptic.ApplyOpenDefaults;
begin
  if (FSupported and PML_HAPTIC_GAIN) <> 0 then
    SetGain(100);
  if (FSupported and PML_HAPTIC_AUTOCENTER) <> 0 then
    SetAutocenter(0);
end;

procedure TPMLHaptic.Close;
begin
  FCore.CloseHaptic(Self);
end;

function TPMLHaptic.EffectSupported(const AEffect: TPMLHapticEffect): Boolean;
begin
  Result := (FSupported and AEffect.EffectType) <> 0;
end;

function TPMLHaptic.CreateEffect(const AEffect: TPMLHapticEffect): TPMLHapticEffectID;
var
  I: Integer;
begin
  if not EffectSupported(AEffect) then
    raise EPMLInputError.Create('Haptic: Effect not supported by haptic device.');
  // 空きの置き場を探し、バックエンドに本物の効果を作らせる
  for I := 0 to FNEffects - 1 do
    if FSlots[I].Hw = nil then
    begin
      FLastError := '';
      if not FBackend.NewEffect(Self, I, AEffect) then
        raise EPMLInputError.Create(FLastError);
      FSlots[I].Effect := AEffect;
      Exit(I);
    end;
  raise EPMLInputError.Create('Haptic: Device has no free space left.');
end;

function TPMLHaptic.UpdateEffect(AEffect: TPMLHapticEffectID; const AData: TPMLHapticEffect): Boolean;
begin
  if not ValidEffect(AEffect) then
    Exit(False);
  // 種類は後から変えられない
  if AData.EffectType <> FSlots[AEffect].Effect.EffectType then
    Exit(Fail('Haptic: Updating effect type is illegal.'));
  if FSlots[AEffect].Hw = nil then
    Exit(Fail('Haptic: Invalid effect identifier.'));
  FLastError := '';
  if not FBackend.UpdateEffect(Self, AEffect, AData) then
    Exit(False);
  FSlots[AEffect].Effect := AData;
  Result := True;
end;

function TPMLHaptic.RunEffect(AEffect: TPMLHapticEffectID; AIterations: Cardinal): Boolean;
begin
  if not ValidEffect(AEffect) then
    Exit(False);
  // PORT-NOTE: SDL は作っていない番号でもバックエンドへ渡し、Linux ではヌルを辿って落ちる
  if FSlots[AEffect].Hw = nil then
    Exit(Fail('Haptic: Invalid effect identifier.'));
  FLastError := '';
  Result := FBackend.RunEffect(Self, AEffect, AIterations);
end;

function TPMLHaptic.StopEffect(AEffect: TPMLHapticEffectID): Boolean;
begin
  if not ValidEffect(AEffect) then
    Exit(False);
  // PORT-NOTE: RunEffect と同じ
  if FSlots[AEffect].Hw = nil then
    Exit(Fail('Haptic: Invalid effect identifier.'));
  FLastError := '';
  Result := FBackend.StopEffect(Self, AEffect);
end;

procedure TPMLHaptic.DestroyEffect(AEffect: TPMLHapticEffectID);
begin
  if not ValidEffect(AEffect) then
    Exit;
  // 作っていなければ何もしない
  if FSlots[AEffect].Hw = nil then
    Exit;
  FBackend.DestroyEffect(Self, AEffect);
  SetEffectHw(AEffect, nil);
end;

function TPMLHaptic.GetEffectStatus(AEffect: TPMLHapticEffectID): Boolean;
begin
  if not ValidEffect(AEffect) then
    Exit(False);
  if (FSupported and PML_HAPTIC_STATUS) = 0 then
    Exit(Fail('Haptic: Device does not support status queries.'));
  if FSlots[AEffect].Hw = nil then
    Exit(Fail('Haptic: Invalid effect identifier.'));
  FLastError := '';
  Result := FBackend.GetEffectStatus(Self, AEffect) > 0;
end;

{ SDL_atoi。先頭の空白と符号を読み、10 進の数字が続く間だけ読む。数字が無ければ 0。 }
function AtoiC10(const AValue: String): Integer;
var
  I, N: Integer;
  Neg: Boolean;
  Acc: Int64;
begin
  N := Length(AValue);
  I := 1;
  while (I <= N) and (AValue[I] in [' ', #9, #10, #11, #12, #13]) do
    Inc(I);
  Neg := False;
  if (I <= N) and (AValue[I] in ['+', '-']) then
  begin
    Neg := AValue[I] = '-';
    Inc(I);
  end;
  Acc := 0;
  while (I <= N) and (AValue[I] in ['0'..'9']) do
  begin
    Acc := Acc * 10 + (Ord(AValue[I]) - Ord('0'));
    if Acc > High(Integer) then
      Acc := High(Integer);
    Inc(I);
  end;
  if Neg then
    Acc := -Acc;
  Result := Integer(Acc);
end;

function TPMLHaptic.SetGain(AGain: Integer): Boolean;
var
  S: String;
  MaxGain, RealGain: Integer;
begin
  if (FSupported and PML_HAPTIC_GAIN) = 0 then
    Exit(Fail('Haptic: Device does not support setting gain.'));
  if (AGain < 0) or (AGain > 100) then
    Exit(Fail('Haptic: Gain must be between 0 and 100.'));
  // 利用者はヒントで最大のゲインを絞れる（線形に縮める）
  S := FCore.Hint(PML_HINT_HAPTIC_GAIN_MAX);
  if S <> '' then
  begin
    MaxGain := AtoiC10(S);
    if MaxGain < 0 then
      MaxGain := 0
    else if MaxGain > 100 then
      MaxGain := 100;
    RealGain := (AGain * MaxGain) div 100;
  end
  else
    RealGain := AGain;
  FLastError := '';
  Result := FBackend.SetGain(Self, RealGain);
end;

function TPMLHaptic.SetAutocenter(AAutocenter: Integer): Boolean;
begin
  if (FSupported and PML_HAPTIC_AUTOCENTER) = 0 then
    Exit(Fail('Haptic: Device does not support setting autocenter.'));
  if (AAutocenter < 0) or (AAutocenter > 100) then
    Exit(Fail('Haptic: Autocenter must be between 0 and 100.'));
  FLastError := '';
  Result := FBackend.SetAutocenter(Self, AAutocenter);
end;

function TPMLHaptic.Pause: Boolean;
begin
  if (FSupported and PML_HAPTIC_PAUSE) = 0 then
    Exit(Fail('Haptic: Device does not support setting pausing.'));
  FLastError := '';
  Result := FBackend.Pause(Self);
end;

function TPMLHaptic.Resume: Boolean;
begin
  // 一時停止できない機器は止まっていないので、戻した事にする
  if (FSupported and PML_HAPTIC_PAUSE) = 0 then
    Exit(True);
  FLastError := '';
  Result := FBackend.Resume(Self);
end;

function TPMLHaptic.StopEffects: Boolean;
begin
  FLastError := '';
  Result := FBackend.StopAll(Self);
end;

function TPMLHaptic.RumbleSupported: Boolean;
begin
  // たいていはサインで足りるが、XInput には左右しか無い
  Result := (FSupported and (PML_HAPTIC_SINE or PML_HAPTIC_LEFTRIGHT)) <> 0;
end;

function TPMLHaptic.InitRumble: Boolean;
begin
  if FRumbleID >= 0 then
    Exit(True);
  FillChar(FRumbleEffect, SizeOf(FRumbleEffect), 0);
  if (FSupported and PML_HAPTIC_SINE) <> 0 then
  begin
    FRumbleEffect.EffectType := PML_HAPTIC_SINE;
    FRumbleEffect.Periodic.Direction.DirType := PML_HAPTIC_CARTESIAN;
    FRumbleEffect.Periodic.Period := 1000;
    FRumbleEffect.Periodic.Magnitude := $4000;
    FRumbleEffect.Periodic.Length := 5000;
    FRumbleEffect.Periodic.AttackLength := 0;
    FRumbleEffect.Periodic.FadeLength := 0;
  end
  else if (FSupported and PML_HAPTIC_LEFTRIGHT) <> 0 then
  begin
    FRumbleEffect.EffectType := PML_HAPTIC_LEFTRIGHT;
    FRumbleEffect.LeftRight.Length := 5000;
    FRumbleEffect.LeftRight.LargeMagnitude := $4000;
    FRumbleEffect.LeftRight.SmallMagnitude := $4000;
  end
  else
    Exit(Fail('Device doesn''t support rumble'));
  try
    FRumbleID := CreateEffect(FRumbleEffect);
  except
    on E: EPMLInputError do
    begin
      FRumbleID := -1;
      Exit(Fail(E.Message));
    end;
  end;
  Result := True;
end;

function TPMLHaptic.PlayRumble(AStrength: Single; ALengthMS: Cardinal): Boolean;
var
  K: Single;
  Magnitude: SmallInt;
begin
  if FRumbleID < 0 then
    Exit(Fail('Haptic: Rumble effect not initialized on haptic device'));
  // 強さを 0.0〜1.0 に収める（NaN は 0 とみなす。SDL は不定）
  if AStrength > 1.0 then
    AStrength := 1.0
  else if not (AStrength >= 0.0) then
    AStrength := 0.0;
  K := 32767.0;
  Magnitude := SmallInt(Trunc(K * AStrength));
  if FRumbleEffect.EffectType = PML_HAPTIC_SINE then
  begin
    FRumbleEffect.Periodic.Magnitude := Magnitude;
    FRumbleEffect.Periodic.Length := ALengthMS;
  end
  else
  begin
    FRumbleEffect.LeftRight.SmallMagnitude := Word(Magnitude);
    FRumbleEffect.LeftRight.LargeMagnitude := Word(Magnitude);
    FRumbleEffect.LeftRight.Length := ALengthMS;
  end;
  if not UpdateEffect(FRumbleID, FRumbleEffect) then
    Exit(False);
  Result := RunEffect(FRumbleID, 1);
end;

function TPMLHaptic.StopRumble: Boolean;
begin
  if FRumbleID < 0 then
    Exit(Fail('Haptic: Rumble effect not initialized on haptic device'));
  Result := StopEffect(FRumbleID);
end;

{ TPMLHapticBackend }

constructor TPMLHapticBackend.Create(ACore: TPMLHapticCore);
begin
  inherited Create;
  FCore := ACore;
end;

procedure TPMLHapticBackend.Quit;
begin
end;

procedure TPMLHapticBackend.Detect;
begin
end;

{ ---- 登録 ---- }

type
  THapticRegistration = record
    Name    : String;
    Priority: Integer;
    Factory : TPMLHapticBackendFactory;
  end;

var
  HapticRegistry: array of THapticRegistration;

procedure PMLRegisterHapticBackend(const AName: String; APriority: Integer;
  AFactory: TPMLHapticBackendFactory);
var
  I, At: Integer;
begin
  if AName = '' then
    raise EPMLArgument.Create('haptic backend name must not be empty');
  if not Assigned(AFactory) then
    raise EPMLArgument.Create('haptic backend factory must not be nil');
  for I := 0 to High(HapticRegistry) do
    if SameText(HapticRegistry[I].Name, AName) then
      raise EPMLArgument.CreateFmt('haptic backend "%s" is already registered', [AName]);
  // 優先度の大きい順、同じなら登録した順
  At := Length(HapticRegistry);
  for I := 0 to High(HapticRegistry) do
    if HapticRegistry[I].Priority < APriority then
    begin
      At := I;
      Break;
    end;
  SetLength(HapticRegistry, Length(HapticRegistry) + 1);
  for I := High(HapticRegistry) downto At + 1 do
    HapticRegistry[I] := HapticRegistry[I - 1];
  HapticRegistry[At].Name := AName;
  HapticRegistry[At].Priority := APriority;
  HapticRegistry[At].Factory := AFactory;
end;

function PMLHapticBackendNames: TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(HapticRegistry));
  for I := 0 to High(HapticRegistry) do
    Result[I] := HapticRegistry[I].Name;
end;

function PMLFindHapticBackend(const AName: String): TPMLHapticBackendFactory;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(HapticRegistry) do
    if SameText(HapticRegistry[I].Name, AName) then
      Exit(HapticRegistry[I].Factory);
end;

end.
