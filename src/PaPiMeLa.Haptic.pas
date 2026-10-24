{
  PaPiMeLa.Haptic — ハプティクス（力覚）の公開窓口

  Origin : ported from SDL (src/haptic/SDL_haptic.c)
           Scope: SDL_InitHaptics / SDL_QuitHaptics、SDL_GetHaptics、SDL_GetHapticNameForID、SDL_OpenHaptic（同じ ID は
           1 つのオブジェクトを共有）、SDL_GetHapticFromID、SDL_IsMouseHaptic / SDL_OpenHapticFromMouse、
           SDL_IsJoystickHaptic / SDL_OpenHapticFromJoystick（ヒント JOYSTICK_HAPTIC_AXES の軸の数を含む）、
           SDL_CloseHaptic（回数が尽きたら効果を消してから閉じる）、開いた直後のゲイン最大・オートセンタ切り。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #63

  WHAT:
    Ctx.Haptics（TPMLHapticSystem）。機器の一覧と、開く・閉じる。開いたデバイス（TPMLHaptic。
    PaPiMeLa.Haptic.Backend）が効果の作成・再生などを持つ。バックエンドは登録されたものを使う
    （PaPiMeLa.Haptic.Linux）。

  WHY:
    SDL の SDL_haptic.c は機器の一覧と開閉の規則を持ち、機器への触り方は SDL_syshaptic.c に任せる。
    papimela も同じ割り方で、検査が偽の機器（PaPiMeLa.Joystick.Linux.Node の抽象）を差し込める。

  RESOLVED:
    - 機器の一覧を引く前と開く前に、バックエンドの Detect（udev の抜き差しの受け取り）を呼ぶ。
      SDL は udev の監視を別スレッドで受けるが、papimela の udev は自分でスレッドを持たない
    - SDL_OpenHapticFromMouse は添字を ID として SDL_OpenHaptic へ渡し、必ず失敗する（D-85）。
      papimela は機器の ID で開く
    - ゲームパッドは開けない（SDL3 の IsJoystickHaptic と同じ。sdl2-compat の例外は無い）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Haptic;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Errors,
  PaPiMeLa.Properties,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Joystick.Backend,
  PaPiMeLa.Haptic.Backend;

type
  { ハプティクスの窓口。Context の Haptics。 }
  TPMLHapticSystem = class(TPMLHapticCore)
  strict private
    FHints  : TPMLHints;
    FBackend: TPMLHapticBackend;
    FOpen   : array of TPMLHaptic;
    function  FindIndex(AID: TPMLHapticID; out AIndex: Integer): Boolean;
    function  FindOpen(AID: TPMLHapticID): TPMLHaptic;
    procedure DoClose(AHaptic: TPMLHaptic);
    procedure Register_(AHaptic: TPMLHaptic);
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject; AHints: TPMLHints);
    destructor Destroy; override;

    // 機器の ID を並べる（SDL_GetHaptics）。
    function  Haptics: TPMLHapticIDs;
    // 機器の名前（SDL_GetHapticNameForID）。無い ID は ''。
    function  NameForID(AID: TPMLHapticID): String;
    // 開く（SDL_OpenHaptic）。同じ ID は同じオブジェクトで、Close の回数が Open に達すると壊れる。無い ID は EPMLArgument。
    function  Open(AID: TPMLHapticID): TPMLHaptic;
    // 開いている機器（SDL_GetHapticFromID）。開いていなければ nil。
    function  FromID(AID: TPMLHapticID): TPMLHaptic;
    // マウスがハプティクスを持つか（SDL_IsMouseHaptic）と、それを開く（SDL_OpenHapticFromMouse）。
    function  IsMouseHaptic: Boolean;
    function  OpenFromMouse: TPMLHaptic;
    { ジョイスティックがハプティクスを持つか（SDL_IsJoystickHaptic）。ゲームパッドは False。 }
    function  IsJoystickHaptic(AJoystick: TPMLJoystick): Boolean;
    // ジョイスティックから開く（SDL_OpenHapticFromJoystick）。持たなければ EPMLInputError。
    function  OpenFromJoystick(AJoystick: TPMLJoystick): TPMLHaptic;
    function  BackendName: String;

    // コアの口
    function  NextInstanceID: TPMLHapticID; override;
    function  Hint(const AName: String): String; override;
    procedure CloseHaptic(AHaptic: TPMLHaptic); override;
  end;

{ ヒント JOYSTICK_HAPTIC_AXES（'0xVID/0xPID/N,...'）から、機器の軸の数を引く。無ければ -1。
  0xffff/0xffff は全部の機器を指し、機器を指す項はそれを上書きする（SDL_Haptic_Get_Naxes）。 }
function PMLHapticAxesFromHint(const AHint: String; AVendor, AProduct: Word): Integer;

implementation

var
  GNextInstanceID: LongInt = 0;

function PMLHapticAxesFromHint(const AHint: String; AVendor, AProduct: Word): Integer;
type
  TEntry = record
    VID, PID, Axes: Word;
  end;
var
  Entries: array of TEntry;
  I, P, N, WildIdx, ExactIdx: Integer;
  E: TEntry;

  procedure SkipSpace;
  begin
    while (P <= N) and (AHint[P] in [' ', #9, #10, #11, #12, #13]) do
      Inc(P);
  end;

  function Literal(const S: String): Boolean;
  var
    K: Integer;
  begin
    if P + Length(S) - 1 > N then
      Exit(False);
    for K := 1 to Length(S) do
      if AHint[P + K - 1] <> S[K] then
        Exit(False);
    Inc(P, Length(S));
    Result := True;
  end;

  function HexDigit(AChar: Char): Integer;
  begin
    case AChar of
      '0'..'9': Result := Ord(AChar) - Ord('0');
      'a'..'f': Result := Ord(AChar) - Ord('a') + 10;
      'A'..'F': Result := Ord(AChar) - Ord('A') + 10;
    else
      Result := -1;
    end;
  end;

  { %hx / %hu（SDL_sscanf と同じ。空白を読み飛ばし、符号を受け付け、16 進は 0x の接頭辞も受け付ける。
    64 ビットを超えたら最大値に張り付き、16 ビットに収める）。数字が無ければ False。 }
  function ReadNumber(ABase: Integer; out AValue: Word): Boolean;
  var
    Acc: QWord;
    Start, D: Integer;
    Neg, Sat: Boolean;
  begin
    SkipSpace;
    Neg := False;
    if (P <= N) and (AHint[P] in ['+', '-']) then
    begin
      Neg := AHint[P] = '-';
      Inc(P);
    end;
    if (ABase = 16) and (P + 2 <= N) and (AHint[P] = '0') and (AHint[P + 1] in ['x', 'X']) and
      (HexDigit(AHint[P + 2]) >= 0) then
      Inc(P, 2);
    Acc := 0;
    Sat := False;
    Start := P;
    while P <= N do
    begin
      D := HexDigit(AHint[P]);
      if (D < 0) or (D >= ABase) then
        Break;
      if not Sat then
      begin
        if Acc > (High(QWord) - QWord(D)) div QWord(ABase) then
        begin
          Sat := True;
          Acc := High(QWord);
        end
        else
          Acc := Acc * QWord(ABase) + QWord(D);
      end;
      Inc(P);
    end;
    if Neg and not Sat then
      Acc := QWord(-Int64(Acc));
    AValue := Word(Acc and $FFFF);
    Result := P > Start;
  end;

begin
  Result := -1;
  if AHint = '' then
    Exit;
  Entries := nil;
  N := Length(AHint);
  P := 1;
  // "0x%hx/0x%hx/%hu" を、読めなくなるまで繰り返す
  while Literal('0x') and ReadNumber(16, E.VID) and Literal('/') and Literal('0x') and ReadNumber(16, E.PID) and
    Literal('/') and ReadNumber(10, E.Axes) do
  begin
    SetLength(Entries, Length(Entries) + 1);
    Entries[High(Entries)] := E;
    if (P <= N) and (AHint[P] = ',') then
      Inc(P);
  end;
  if Length(Entries) = 0 then
    Exit;
  // 全部の機器を指す項（最初の 1 つ）、機器を指す項（最初の 1 つ）の順。後者が前者を上書きする
  WildIdx := -1;
  ExactIdx := -1;
  for I := 0 to High(Entries) do
  begin
    if (WildIdx < 0) and (Entries[I].VID = $FFFF) and (Entries[I].PID = $FFFF) then
      WildIdx := I;
    if (ExactIdx < 0) and (Entries[I].VID = AVendor) and (Entries[I].PID = AProduct) then
      ExactIdx := I;
  end;
  if WildIdx >= 0 then
    Result := Entries[WildIdx].Axes;
  if ExactIdx >= 0 then
    Result := Entries[ExactIdx].Axes;
end;

{ TPMLHapticSystem }

constructor TPMLHapticSystem.Create(AContextRef: TObject; AOwner: TPMLObject; AHints: TPMLHints);
var
  Names: TStringArray;
  I: Integer;
  Factory: TPMLHapticBackendFactory;
  B: TPMLHapticBackend;
  Failure: String;
begin
  inherited Create(AContextRef, AOwner);
  FHints := AHints;
  Names := PMLHapticBackendNames;
  if Length(Names) = 0 then
    raise EPMLUnsupported.Create(
      'no haptic backend is registered (add PaPiMeLa or PaPiMeLa.Backends to uses)');
  Failure := '';
  for I := 0 to High(Names) do
  begin
    Factory := PMLFindHapticBackend(Names[I]);
    B := nil;
    try
      B := Factory(Self);
      if B.Init then
      begin
        FBackend := B;
        Break;
      end;
      Failure := Names[I] + ': ' + B.LastError;
      B.Free;
    except
      on E: Exception do
      begin
        B.Free;
        Failure := Names[I] + ': ' + E.Message;
      end;
    end;
  end;
  if FBackend = nil then
    raise EPMLInitError.Create('no haptic backend could start (' + Failure + ')');
end;

destructor TPMLHapticSystem.Destroy;
begin
  // 開いたままのものを全部閉じる（SDL_QuitHaptics は回数を見ない）
  while Length(FOpen) > 0 do
    DoClose(FOpen[0]);
  if FBackend <> nil then
  begin
    FBackend.Quit;
    FBackend.Free;
    FBackend := nil;
  end;
  inherited Destroy;
end;

function TPMLHapticSystem.BackendName: String;
begin
  Result := FBackend.Name;
end;

function TPMLHapticSystem.NextInstanceID: TPMLHapticID;
begin
  repeat
    Result := TPMLHapticID(LongWord(InterLockedIncrement(GNextInstanceID)));
  until Result <> 0;
end;

function TPMLHapticSystem.Hint(const AName: String): String;
begin
  if FHints = nil then
    Result := ''
  else
    Result := FHints.GetHint(AName);
end;

function TPMLHapticSystem.FindIndex(AID: TPMLHapticID; out AIndex: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  AIndex := -1;
  if AID = 0 then
    Exit;
  FBackend.Detect;
  for I := 0 to FBackend.DeviceCount - 1 do
    if FBackend.DeviceInstanceID(I) = AID then
    begin
      AIndex := I;
      Exit(True);
    end;
end;

function TPMLHapticSystem.FindOpen(AID: TPMLHapticID): TPMLHaptic;
var
  I: Integer;
begin
  for I := 0 to High(FOpen) do
    if FOpen[I].ID = AID then
      Exit(FOpen[I]);
  Result := nil;
end;

function TPMLHapticSystem.Haptics: TPMLHapticIDs;
var
  I: Integer;
begin
  FBackend.Detect;
  Result := nil;
  SetLength(Result, FBackend.DeviceCount);
  for I := 0 to High(Result) do
    Result[I] := FBackend.DeviceInstanceID(I);
end;

function TPMLHapticSystem.NameForID(AID: TPMLHapticID): String;
var
  Index: Integer;
begin
  if FindIndex(AID, Index) then
    Result := FBackend.DeviceName(Index)
  else
    Result := '';
end;

// 開いた機器を一覧の先頭に連ねる（SDL の連結リストと同じ）。ゲインを最大にし、オートセンタを切る。
procedure TPMLHapticSystem.Register_(AHaptic: TPMLHaptic);
var
  I: Integer;
begin
  AHaptic.RefAdd;
  SetLength(FOpen, Length(FOpen) + 1);
  for I := High(FOpen) downto 1 do
    FOpen[I] := FOpen[I - 1];
  FOpen[0] := AHaptic;
  AHaptic.ApplyOpenDefaults;
end;

function TPMLHapticSystem.Open(AID: TPMLHapticID): TPMLHaptic;
var
  Index: Integer;
begin
  if not FindIndex(AID, Index) then
    raise EPMLArgument.CreateFmt('Haptic device %d not found', [AID]);
  // 開いていれば、それを返す（ID ごとに 1 つ）
  Result := FindOpen(AID);
  if Result <> nil then
  begin
    Result.RefAdd;
    Exit;
  end;
  Result := TPMLHaptic.Create(ContextRef, Self, Self, FBackend, AID);
  try
    if not FBackend.Open(Result, Index) then
      raise EPMLInputError.Create(FBackend.LastError);
    if Result.Name = '' then
      Result.SetIdentity(Result.ID, FBackend.DeviceName(Index));
  except
    Result.Free;
    raise;
  end;
  Register_(Result);
end;

function TPMLHapticSystem.FromID(AID: TPMLHapticID): TPMLHaptic;
begin
  Result := FindOpen(AID);
end;

function TPMLHapticSystem.IsMouseHaptic: Boolean;
begin
  FBackend.Detect;
  Result := FBackend.MouseIndex >= 0;
end;

function TPMLHapticSystem.OpenFromMouse: TPMLHaptic;
var
  Index: Integer;
begin
  FBackend.Detect;
  Index := FBackend.MouseIndex;
  if Index < 0 then
    raise EPMLInputError.Create('Haptic: Mouse isn''t a haptic device.');
  Result := Open(FBackend.DeviceInstanceID(Index));
end;

function TPMLHapticSystem.IsJoystickHaptic(AJoystick: TPMLJoystick): Boolean;
begin
  if AJoystick = nil then
    Exit(False);
  // ゲームパッドは開けない（SDL3 は sdl2-compat のときだけ許す）
  if AJoystick.Core.IsGamepad(AJoystick.ID) then
    Exit(False);
  Result := FBackend.JoystickIsHaptic(AJoystick);
end;

function TPMLHapticSystem.OpenFromJoystick(AJoystick: TPMLJoystick): TPMLHaptic;
var
  I, Naxes, General: Integer;
begin
  if not IsJoystickHaptic(AJoystick) then
    raise EPMLInputError.Create('Haptic: Joystick isn''t a haptic device.');
  // もう開いているか
  for I := 0 to High(FOpen) do
    if FBackend.JoystickSameHaptic(FOpen[I], AJoystick) then
    begin
      Result := FOpen[I];
      Result.RefAdd;
      Exit;
    end;
  Result := TPMLHaptic.Create(ContextRef, Self, Self, FBackend, 0);
  try
    if not FBackend.OpenFromJoystick(Result, AJoystick) then
      raise EPMLInputError.Create('Haptic: ' + FBackend.LastError);
  except
    Result.Free;
    raise;
  end;
  // 軸の数をヒントで決められる。機器の本当の軸の数を超えない
  Naxes := PMLHapticAxesFromHint(Hint(PML_HINT_JOYSTICK_HAPTIC_AXES), AJoystick.VendorID, AJoystick.ProductID);
  General := AJoystick.NumAxes;
  if Naxes > 0 then
    Result.SetAxes(Naxes);
  if (General >= 0) and (Naxes > General) then
    Result.SetAxes(General);
  Register_(Result);
end;

procedure TPMLHapticSystem.DoClose(AHaptic: TPMLHaptic);
var
  I, J: Integer;
begin
  // 作った効果を消してから閉じる
  AHaptic.DestroyAllEffects;
  FBackend.Close(AHaptic);
  for I := 0 to High(FOpen) do
    if FOpen[I] = AHaptic then
    begin
      for J := I to High(FOpen) - 1 do
        FOpen[J] := FOpen[J + 1];
      SetLength(FOpen, Length(FOpen) - 1);
      Break;
    end;
  AHaptic.Free;
end;

procedure TPMLHapticSystem.CloseHaptic(AHaptic: TPMLHaptic);
begin
  if AHaptic.RefRelease > 0 then
    Exit;
  DoClose(AHaptic);
end;

end.
