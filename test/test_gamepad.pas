{
  test_gamepad — ゲームパッド（SDL_gamepad.c の機器・開いたゲームパッド・イベント）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    参照版 SDL の仮想ジョイスティック（ゲームパッドの種類）に同じ場面を通した記録（test/gamepad_expected.inc。
    tools/gamepad-expect/gen.bb が作る）と、papimela の記録を場面ごとに突き合わせる:
      auto     自動のマッピング（バックエンドの言う割り当て）、種類（VID/PID）、player index、Added の順
      open     開く（同じ ID は同じオブジェクト）、割り当ての一覧、HasAxis/HasButton、Close の回数
      types    PS5 / Switch / GameCube / Xbox One の種類と顔のボタンの表示名
      state    ボタン・軸・ハット・トリガー（静止が -32768）の値とゲームパッドのイベント。ジョイスティックの
               イベントとの出る順、イベントを切っても値は読める、UpdateComplete
      custom   SetGamepadMapping（半軸・反転・ハットから軸・ボタンから軸）、非ゲームパッドが Added になる、
               Remapped、type:/face: 欄、AddMapping での更新、マッピングを空に
      guide    ガイドボタンの短い押しの遅延
      recenter 押したまま外す（全部静止に戻して Removed、値は外す前のまま残る）
      ignore   SDL_ShouldIgnoreGamepad（名前の禁止語、Steam の仮想、ヒントの許可・無視の表）
      player   player index
    papimela の足した検査: 名前の表の単独の呼び出し、始める前は Added が出ない、Close と破棄。
}
program test_gamepad;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils, Classes,
  PaPiMeLa.Errors,
  PaPiMeLa.Properties,
  PaPiMeLa.Events,
  PaPiMeLa.Core,
  PaPiMeLa.Joystick.GUID,
  PaPiMeLa.Joystick.Backend,
  PaPiMeLa.Joystick,
  PaPiMeLa.Joystick.Virtual,
  PaPiMeLa.Gamepad.Mapping,
  PaPiMeLa.Gamepad;

{$I gamepad_expected.inc}

var
  Failures: Integer = 0;
  Ctx: TPMLContext;
  Log: TStringList;
  Known: array[0..63] of TPMLJoystickID;
  NKnown: Integer = 0;

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

procedure L(const AText: String);
begin
  Log.Add(AText);
end;

procedure LF(const AFormat: String; const AArgs: array of const);
begin
  Log.Add(Format(AFormat, AArgs));
end;

function Lab(AID: TPMLJoystickID): Integer;
var
  I: Integer;
begin
  for I := 0 to NKnown - 1 do
    if Known[I] = AID then
      Exit(I + 1);
  Known[NKnown] := AID;
  Inc(NKnown);
  Result := NKnown;
end;

procedure Section(const AName: String);
begin
  L('== ' + AName);
end;

function AxisName(AAxis: Integer): String;
begin
  Result := PMLGamepadAxisToString(TPMLGamepadAxis(AAxis));
end;

function ButtonName(AButton: Integer): String;
begin
  Result := PMLGamepadButtonToString(TPMLGamepadButton(AButton));
end;

procedure Drain;
var
  E: TPMLEvent;
begin
  while Ctx.Events.Poll(E) do
    case E.Kind of
      TPMLEventKind.JoystickAdded: LF('ev jadded J%d', [Lab(E.JDevice.Which)]);
      TPMLEventKind.JoystickRemoved: LF('ev jremoved J%d', [Lab(E.JDevice.Which)]);
      TPMLEventKind.JoystickAxisMotion: LF('ev jaxis J%d %d %d', [Lab(E.JAxis.Which), E.JAxis.Axis, E.JAxis.Value]);
      TPMLEventKind.JoystickHatMotion: LF('ev jhat J%d %d %d', [Lab(E.JHat.Which), E.JHat.Hat, E.JHat.Value]);
      TPMLEventKind.JoystickButtonDown: LF('ev jdown J%d %d', [Lab(E.JButton.Which), E.JButton.Button]);
      TPMLEventKind.JoystickButtonUp: LF('ev jup J%d %d', [Lab(E.JButton.Which), E.JButton.Button]);
      TPMLEventKind.JoystickUpdateComplete: LF('ev jcomplete J%d', [Lab(E.JDevice.Which)]);
      TPMLEventKind.GamepadAdded: LF('ev gadded J%d', [Lab(E.JDevice.Which)]);
      TPMLEventKind.GamepadRemoved: LF('ev gremoved J%d', [Lab(E.JDevice.Which)]);
      TPMLEventKind.GamepadRemapped: LF('ev gremapped J%d', [Lab(E.JDevice.Which)]);
      TPMLEventKind.GamepadUpdateComplete: LF('ev gcomplete J%d', [Lab(E.JDevice.Which)]);
      TPMLEventKind.GamepadAxisMotion:
        LF('ev gaxis J%d %s %d', [Lab(E.GAxis.Which), AxisName(E.GAxis.Axis), E.GAxis.Value]);
      TPMLEventKind.GamepadButtonDown: LF('ev gdown J%d %s', [Lab(E.GButton.Which), ButtonName(E.GButton.Button)]);
      TPMLEventKind.GamepadButtonUp: LF('ev gup J%d %s', [Lab(E.GButton.Which), ButtonName(E.GButton.Button)]);
    else
      LF('ev other %d', [Ord(E.Kind)]);
    end;
end;

{ SDL の SDL_PollEvent は、1 巡の始めに 1 度だけ Pump する。papimela の Poll は、キューが空になるたびに Pump するので、
  遅れたガイドボタンのように「更新するたびにイベントが出る」場面では回数が合わない。そこで Joystick の Pump を外し
  （RunAll）、SDL と同じく「Update を 1 回 + 1 巡の始めの Pump 1 回」を自分で行う。 }
procedure Update(const ATag: String);
begin
  Ctx.Gamepads.Update;
  Ctx.Joysticks.Update;
  L('-- ' + ATag);
  Drain;
end;

function AttachMasked(const ATag: String; AType: TPMLJoystickType; AVendor, AProduct: Word;
  NAxes, NButtons, NHats: Integer; const AName: String; AButtonMask, AAxisMask: LongWord): TPMLJoystickID;
var
  D: TPMLVirtualJoystickDesc;
begin
  FillChar(D, SizeOf(D), 0);
  D.JoystickType := AType;
  D.VendorID := AVendor;
  D.ProductID := AProduct;
  D.NumAxes := NAxes;
  D.NumButtons := NButtons;
  D.NumHats := NHats;
  D.Name := AName;
  D.ButtonMask := AButtonMask;
  D.AxisMask := AAxisMask;
  Result := Ctx.Joysticks.AttachVirtual(D);
  LF('attach %s -> J%d', [ATag, Lab(Result)]);
end;

function Attach(const ATag: String; AType: TPMLJoystickType; AVendor, AProduct: Word;
  NAxes, NButtons, NHats: Integer; const AName: String): TPMLJoystickID;
begin
  Result := AttachMasked(ATag, AType, AVendor, AProduct, NAxes, NButtons, NHats, AName, 0, 0);
end;

procedure IDsList(const ATag: String);
var
  IDs: TPMLJoystickIDs;
  S: String;
  I: Integer;
begin
  IDs := Ctx.Gamepads.Gamepads;
  S := '';
  for I := 0 to High(IDs) do
    S := S + Format(' J%d', [Lab(IDs[I])]);
  LF('gamepads %s:%s (count=%d has=%d)', [ATag, S, Length(IDs), Ord(Ctx.Gamepads.HasGamepad)]);
end;

procedure InfoForID(AID: TPMLJoystickID);
var
  M, N: String;
begin
  M := Ctx.Gamepads.MappingForID(AID);
  N := Ctx.Gamepads.NameForID(AID);
  if N = '' then
    N := '(null)';
  LF('info J%d is=%d name=''%s'' type=%d real=%d player=%d joytype=%d',
    [Lab(AID), Ord(Ctx.Gamepads.IsGamepad(AID)), N, Ord(Ctx.Gamepads.TypeForID(AID)),
     Ord(Ctx.Gamepads.RealTypeForID(AID)), Ctx.Gamepads.PlayerIndexForID(AID), Ord(Ctx.Joysticks.TypeForID(AID))]);
  if M = '' then
    M := '(null)';
  LF('mapping J%d %s', [Lab(AID), M]);
end;

procedure PadState(const ATag: String; AGamepad: TPMLGamepad);
var
  S: String;
  A: TPMLGamepadAxis;
  B: TPMLGamepadButton;
begin
  S := '';
  for A := Low(TPMLGamepadAxis) to High(TPMLGamepadAxis) do
    S := S + Format(' %s=%d', [PMLGamepadAxisToString(A), AGamepad.Axis(A)]);
  S := S + ' |';
  for B := Low(TPMLGamepadButton) to High(TPMLGamepadButton) do
    if AGamepad.Button(B) then
      S := S + ' ' + PMLGamepadButtonToString(B);
  LF('pad %s:%s', [ATag, S]);
end;

procedure HasList(AGamepad: TPMLGamepad);
var
  S: String;
  A: TPMLGamepadAxis;
  B: TPMLGamepadButton;
begin
  S := '';
  for A := Low(TPMLGamepadAxis) to High(TPMLGamepadAxis) do
    if AGamepad.HasAxis(A) then
      S := S + ' ' + PMLGamepadAxisToString(A);
  S := S + ' |';
  for B := Low(TPMLGamepadButton) to High(TPMLGamepadButton) do
    if AGamepad.HasButton(B) then
      S := S + ' ' + PMLGamepadButtonToString(B);
  L('has:' + S);
end;

procedure BindingsList(AGamepad: TPMLGamepad);
var
  Bs: TPMLGamepadBindings;
  I: Integer;
  InS, OutS: String;
begin
  Bs := AGamepad.Bindings;
  LF('bindings %d', [Length(Bs)]);
  for I := 0 to High(Bs) do
  begin
    case Bs[I].InputType of
      TPMLGamepadBindType.Button: InS := Format('b%d', [Bs[I].InputIndex]);
      TPMLGamepadBindType.Axis: InS := Format('a%d[%d..%d]', [Bs[I].InputIndex, Bs[I].InputMin, Bs[I].InputMax]);
      TPMLGamepadBindType.Hat: InS := Format('h%d.%d', [Bs[I].InputIndex, Bs[I].InputMask]);
    else
      InS := 'none';
    end;
    if Bs[I].OutputType = TPMLGamepadBindType.Axis then
      OutS := Format('%s[%d..%d]', [PMLGamepadAxisToString(Bs[I].OutputAxis), Bs[I].OutputMin, Bs[I].OutputMax])
    else
      OutS := PMLGamepadButtonToString(Bs[I].OutputButton);
    LF('  bind %s -> %s', [InS, OutS]);
  end;
end;

procedure PadProps(AGamepad: TPMLGamepad);
begin
  LF('gamepad name=''%s'' type=%d real=%d player=%d',
    [AGamepad.Name, Ord(AGamepad.GamepadType), Ord(AGamepad.RealType), AGamepad.PlayerIndex]);
  LF('labels south=%d east=%d west=%d north=%d start=%d',
    [Ord(AGamepad.ButtonLabel(TPMLGamepadButton.South)), Ord(AGamepad.ButtonLabel(TPMLGamepadButton.East)),
     Ord(AGamepad.ButtonLabel(TPMLGamepadButton.West)), Ord(AGamepad.ButtonLabel(TPMLGamepadButton.North)),
     Ord(AGamepad.ButtonLabel(TPMLGamepadButton.Start))]);
end;

procedure SetBtn(AGamepad: TPMLGamepad; AButton: Integer; ADown: Boolean);
begin
  Ctx.Joysticks.SetVirtualButton(AGamepad.Joystick, AButton, ADown);
end;

procedure SetAx(AGamepad: TPMLGamepad; AAxis: Integer; AValue: Integer);
begin
  Ctx.Joysticks.SetVirtualAxis(AGamepad.Joystick, AAxis, AValue);
end;

procedure SetHat(AGamepad: TPMLGamepad; AValue: Integer);
begin
  Ctx.Joysticks.SetVirtualHat(AGamepad.Joystick, 0, AValue);
end;

procedure Scenario;
var
  XB, PS, GN, UN, SW, GC, X1, GD, MT, AL, MK, SM, TK: TPMLJoystickID;
  G, Again: TPMLGamepad;
  Opened: Boolean;
begin
  Section('auto');
  XB := Attach('XB', TPMLJoystickType.Gamepad, $045E, $028E, 6, 15, 1, '');
  InfoForID(XB);
  PS := Attach('PS', TPMLJoystickType.Gamepad, $054C, $0CE6, 6, 17, 0, 'My PS5 Pad');
  InfoForID(PS);
  GN := Attach('GN', TPMLJoystickType.Gamepad, 0, 0, 4, 8, 1, 'Lic Pro Controller');
  InfoForID(GN);
  UN := Attach('UN', TPMLJoystickType.Unknown, $0A0A, $0B0B, 2, 2, 0, 'Plain Stick');
  InfoForID(UN);
  // ボタンとハットと軸の割り当て方（仮想ジョイスティックの GetGamepadMapping）
  AL := Attach('ALL', TPMLJoystickType.Gamepad, $1234, $5678, 6, 26, 0, 'All Buttons');
  InfoForID(AL);
  MK := AttachMasked('MK', TPMLJoystickType.Gamepad, $1234, $5679, 3, 5, 1, 'Masked',
    (1 shl Ord(TPMLGamepadButton.South)) or (1 shl Ord(TPMLGamepadButton.Guide)) or (1 shl Ord(TPMLGamepadButton.DPadUp))
    or (1 shl Ord(TPMLGamepadButton.Misc1)) or (1 shl Ord(TPMLGamepadButton.LeftPaddle2))
    or (1 shl Ord(TPMLGamepadButton.Start)) or (1 shl Ord(TPMLGamepadButton.Misc6)),
    (1 shl Ord(TPMLGamepadAxis.LeftX)) or (1 shl Ord(TPMLGamepadAxis.RightTrigger)) or (1 shl Ord(TPMLGamepadAxis.RightY)));
  InfoForID(MK);
  SM := Attach('SM', TPMLJoystickType.Gamepad, $1234, $567A, 1, 3, 0, 'Small');
  InfoForID(SM);
  TK := Attach('TK', TPMLJoystickType.Gamepad, $1234, $567B, 4, 22, 1, 'Touch Misc');
  InfoForID(TK);
  Ctx.Joysticks.DetachVirtual(AL); Ctx.Joysticks.DetachVirtual(MK);
  Ctx.Joysticks.DetachVirtual(SM); Ctx.Joysticks.DetachVirtual(TK);
  IDsList('all');
  Update('added');

  Section('open');
  G := Ctx.Gamepads.Open(XB);
  LF('open XB ok=%d id=J%d', [Ord(G <> nil), Lab(G.ID)]);
  Again := Ctx.Gamepads.Open(XB);
  LF('open again same=%d', [Ord(Again = G)]);
  LF('from id same=%d', [Ord(Ctx.Gamepads.FromID(XB) = G)]);
  LF('from player same=%d', [Ord(Ctx.Gamepads.FromPlayerIndex(G.PlayerIndex) = G)]);
  PadProps(G);
  HasList(G);
  BindingsList(G);
  L('mapping ' + G.MappingString);
  PadState('initial', G);
  G.Close;
  LF('from id after one close same=%d', [Ord(Ctx.Gamepads.FromID(XB) = G)]);
  Again.Close;
  LF('from id after close %d', [Ord(Ctx.Gamepads.FromID(XB) <> nil)]);
  Opened := True;
  try
    Ctx.Gamepads.Open(UN);
  except
    on EPMLArgument do
      Opened := False;
  end;
  LF('open plain stick %d', [Ord(Opened)]);
  Opened := True;
  try
    Ctx.Gamepads.Open(9999);
  except
    on EPMLArgument do
      Opened := False;
  end;
  LF('open missing %d', [Ord(Opened)]);
  LF('is missing %d', [Ord(Ctx.Gamepads.IsGamepad(9999))]);

  Section('types');
  G := Ctx.Gamepads.Open(PS); PadProps(G); HasList(G); G.Close;
  G := Ctx.Gamepads.Open(GN); PadProps(G); HasList(G); G.Close;
  SW := Attach('SW', TPMLJoystickType.Gamepad, $057E, $2009, 6, 15, 1, '');
  G := Ctx.Gamepads.Open(SW); PadProps(G); G.Close; Ctx.Joysticks.DetachVirtual(SW);
  GC := Attach('GC', TPMLJoystickType.Gamepad, $057E, $0337, 6, 15, 1, '');
  G := Ctx.Gamepads.Open(GC); PadProps(G); G.Close; Ctx.Joysticks.DetachVirtual(GC);
  X1 := Attach('X1', TPMLJoystickType.Gamepad, $045E, $02EA, 6, 15, 1, '');
  G := Ctx.Gamepads.Open(X1); PadProps(G); G.Close; Ctx.Joysticks.DetachVirtual(X1);
  Update('types');

  Section('state');
  G := Ctx.Gamepads.Open(XB);
  PadState('rest', G);
  SetBtn(G, 0, True); Update('a down'); PadState('a', G);
  SetBtn(G, 0, True); Update('a again');
  SetBtn(G, 1, True); SetBtn(G, 0, False); Update('b down a up'); PadState('b', G);
  SetAx(G, 0, 20000); Update('leftx 20000'); PadState('leftx', G);
  SetAx(G, 0, -32768); Update('leftx min'); PadState('leftx min', G);
  SetAx(G, 1, 12345); Update('lefty 12345');
  SetAx(G, 4, 0); Update('lefttrigger half'); PadState('trigger half', G);
  SetAx(G, 4, 32767); Update('lefttrigger full'); PadState('trigger full', G);
  SetAx(G, 5, 16000); Update('righttrigger 16000'); PadState('righttrigger', G);
  SetAx(G, 4, -32768); SetAx(G, 5, -32768); Update('triggers released');
  SetHat(G, PML_HAT_RIGHTUP); Update('hat rightup'); PadState('hat', G);
  SetHat(G, PML_HAT_RIGHTUP); Update('hat rightup again');
  SetHat(G, PML_HAT_LEFT); Update('hat left'); PadState('hat left', G);
  SetHat(G, PML_HAT_CENTERED); Update('hat centered');
  SetBtn(G, 3, True); SetBtn(G, 4, True); Update('x y'); PadState('xy', G);
  SetBtn(G, 3, False); SetBtn(G, 4, False); Update('x y up');
  Ctx.Gamepads.SetEventsEnabled(False);
  LF('events enabled %d', [Ord(Ctx.Gamepads.EventsEnabled)]);
  SetBtn(G, 0, True); Update('a down (gamepad events off)'); PadState('off', G);
  Ctx.Gamepads.SetEventsEnabled(True);
  LF('events enabled %d', [Ord(Ctx.Gamepads.EventsEnabled)]);
  SetBtn(G, 0, False); Update('a up (on again)');
  G.Close;

  Section('custom');
  LF('set map UN %d', [Ord(Ctx.Gamepads.SetMappingForID(UN,
    'x,Custom Pad,a:b0,b:+a1,x:-a1,leftx:a0~,lefty:a1,righttrigger:h0.1,dpup:b1,leftshoulder:+a0,rightshoulder:-a0,'))]);
  Update('mapping set');
  InfoForID(UN);
  IDsList('after set');
  G := Ctx.Gamepads.Open(UN);
  PadProps(G); HasList(G); BindingsList(G);
  SetBtn(G, 0, True); Update('b0'); PadState('b0', G);
  SetAx(G, 1, 30000); Update('a1=30000'); PadState('a1 high', G);
  SetAx(G, 1, -30000); Update('a1=-30000'); PadState('a1 low', G);
  SetAx(G, 1, 200); Update('a1=200'); PadState('a1 near zero', G);
  SetAx(G, 0, 15000); Update('a0=15000'); PadState('a0', G);
  SetAx(G, 0, -15000); Update('a0=-15000'); PadState('a0 neg', G);
  SetAx(G, 0, 0); Update('a0=0');
  SetBtn(G, 1, True); Update('b1'); PadState('b1', G);
  LF('set map again %d', [Ord(Ctx.Gamepads.SetMappingForID(UN, 'x,Custom Pad Two,a:b1,b:b0,type:ps4,face:sony,'))]);
  Update('mapping changed');
  PadProps(G); BindingsList(G);
  L('add same guid via AddGamepadMapping');
  LF('add %d', [Ctx.Gamepads.AddMapping(PMLGUIDToString(Ctx.Joysticks.GUIDForID(UN)) + ',Api Pad,a:b2,')]);
  Update('added again');
  PadProps(G); BindingsList(G);
  LF('set map NULL %d', [Ord(Ctx.Gamepads.SetMappingForID(UN, ''))]);
  Update('mapping cleared');
  BindingsList(G);
  LF('name ''%s''', [G.Name]);
  G.Close;

  Section('guide');
  GD := Attach('GD', TPMLJoystickType.Unknown, $0D0D, $0E0E, 2, 3, 0, 'Guide Pad');
  Update('gd added');
  Ctx.Gamepads.SetMappingForID(GD, 'x,Guide Pad,a:b0,guide:b1,start:b2,'); Update('gd mapped');
  G := Ctx.Gamepads.Open(GD);
  SetBtn(G, 1, True); Update('guide down');
  SetBtn(G, 1, False); Update('guide up quickly');
  PadState('guide pending', G);
  SetBtn(G, 1, True); Update('guide down again (pending)');
  SetBtn(G, 1, False); Update('guide up again quickly');
  Sleep(300); Update('after 300ms');
  SetBtn(G, 1, True); Update('guide down 2');
  Sleep(300);
  SetBtn(G, 1, False); Update('guide up slowly');
  SetBtn(G, 2, True); Update('start down');
  G.Close; Ctx.Joysticks.DetachVirtual(GD); Update('gd removed');

  Section('multi');
  MT := Attach('MT', TPMLJoystickType.Unknown, $0F0F, $0F10, 3, 3, 1, 'Multi Pad');
  Update('mt added');
  Ctx.Gamepads.SetMappingForID(MT,
    'x,Multi Pad,leftx:b0,leftx:a1,lefty:+a2,righty:-a2,dpleft:h0.8,dpup:h0.1,a:b1,x:a0~,rightx:a0~,start:b2,');
  Update('mt mapped');
  G := Ctx.Gamepads.Open(MT);
  BindingsList(G); PadState('rest', G);
  SetAx(G, 1, 8000); Update('a1=8000'); PadState('a1', G);
  SetBtn(G, 0, True); Update('b0 down'); PadState('b0', G);
  SetBtn(G, 0, False); Update('b0 up'); PadState('b0 up', G);
  SetAx(G, 2, 32672); Update('a2=32672'); PadState('a2 32672', G);
  SetAx(G, 2, 32675); Update('a2=32675'); PadState('a2 32675', G);
  SetAx(G, 2, -20000); Update('a2=-20000'); PadState('a2 neg', G);
  SetAx(G, 2, 0); Update('a2=0');
  SetHat(G, PML_HAT_LEFT); Update('hat left'); PadState('hat left', G);
  SetHat(G, PML_HAT_LEFTUP); Update('hat leftup'); PadState('hat leftup', G);
  SetHat(G, PML_HAT_UP); Update('hat up'); PadState('hat up', G);
  SetHat(G, PML_HAT_CENTERED); Update('hat centered');
  SetBtn(G, 1, True); SetAx(G, 2, 32000); SetHat(G, PML_HAT_LEFT);
  Update('held'); PadState('held', G);
  Ctx.Joysticks.DetachVirtual(MT); Update('mt removed'); PadState('after', G);
  G.Close;

  Section('recenter');
  G := Ctx.Gamepads.Open(XB);
  SetBtn(G, 0, True); SetAx(G, 0, 25000); SetAx(G, 4, 32767);
  SetHat(G, PML_HAT_UP);
  Update('held');
  Ctx.Joysticks.DetachVirtual(XB); Update('detached while held');
  LF('connected %d', [Ord(G.Connected)]);
  PadState('after', G);
  G.Close;
end;

procedure IgnoreCases;
type
  TCase = record
    V, P: Word;
    Name: String;
  end;
const
  Cases: array[0..19] of TCase = (
    (V: $1111; P: $2222; Name: 'Plain'), (V: $3333; P: $4444; Name: 'Foo Touchpad'),
    (V: $3333; P: $4444; Name: 'Foo Touchpad Bar'), (V: $3333; P: $4445; Name: 'Usb Keyboard'),
    (V: $3333; P: $4446; Name: 'PG-9099 Keyboard'), (V: $28DE; P: $11FF; Name: 'Steam'),
    (V: $3333; P: $4447; Name: 'Sony DualSense Motion Sensors'), (V: $3333; P: $4447; Name: 'Pad IMU'),
    (V: $3333; P: $4447; Name: 'uinput-fp'), (V: $3333; P: $4447; Name: 'Mouse passthrough'),
    (V: $3333; P: $4447; Name: 'Wacom One Pen'), (V: $3333; P: $4447; Name: 'Thing System Control'),
    (V: $3333; P: $4447; Name: 'My Synaptics Pad'), (V: $3333; P: $4447; Name: 'Pad IR'),
    (V: $3333; P: $4447; Name: 'Pad IR 2'), (V: $3333; P: $4447; Name: 'gpio_ir_recv'),
    (V: $3333; P: $4447; Name: 'An LED Thing'), (V: $3333; P: $4447; Name: ''),
    (V: $2222; P: $1111; Name: 'Normal Pad'), (V: $5555; P: $6666; Name: 'Normal Pad'));
var
  I: Integer;
  Layer: TPMLJoystickGamepadLayer;

  function Ign(V, P: Word; const AName: String): Integer;
  begin
    Result := Ord(Layer.ShouldIgnore(V, P, 0, AName));
  end;
begin
  Section('ignore');
  Layer := Ctx.Joysticks.GamepadLayer;
  for I := 0 to High(Cases) do
    LF('ignore %s/%s ''%s'' -> %d', [LowerCase(IntToHex(Cases[I].V, 4)), LowerCase(IntToHex(Cases[I].P, 4)),
      Cases[I].Name, Ign(Cases[I].V, Cases[I].P, Cases[I].Name)]);
  Ctx.Hints.SetHint(PML_HINT_GAMEPAD_IGNORE_DEVICES, '0x5555/0x6666,0x7777/0x8888', TPMLHintPriority.Normal);
  L('hint ignore changed');
  LF('ignore 1111/2222 -> %d', [Ign($1111, $2222, 'Normal Pad')]);
  LF('ignore 5555/6666 -> %d', [Ign($5555, $6666, 'Normal Pad')]);
  Ctx.Hints.SetHint(PML_HINT_GAMEPAD_IGNORE_DEVICES_EXCEPT, '0x7777/0x8888', TPMLHintPriority.Normal);
  L('hint except set');
  LF('ignore 5555/6666 -> %d', [Ign($5555, $6666, 'Normal Pad')]);
  LF('ignore 7777/8888 -> %d', [Ign($7777, $8888, 'Normal Pad')]);
  LF('ignore 7777/8888 touchpad -> %d', [Ign($7777, $8888, 'X Touchpad')]);
  LF('ignore steam with except -> %d', [Ign($28DE, $11FF, 'Steam')]);
  Ctx.Hints.ResetHint(PML_HINT_GAMEPAD_IGNORE_DEVICES_EXCEPT);
  Ctx.Hints.ResetHint(PML_HINT_GAMEPAD_IGNORE_DEVICES);
  LF('ignore 5555/6666 after reset -> %d', [Ign($5555, $6666, 'Normal Pad')]);
end;

procedure PlayerCases;
var
  IDs: TPMLJoystickIDs;
  I: Integer;
begin
  Section('player');
  IDs := Ctx.Gamepads.Gamepads;
  for I := 0 to High(IDs) do
    LF('player J%d = %d', [Lab(IDs[I]), Ctx.Gamepads.PlayerIndexForID(IDs[I])]);
end;

{ 記録を '== 名前' で場面ごとに切る。 }
procedure SplitSections(ALines: TStrings; ANames: TStringList; ABlocks: TList);
var
  I: Integer;
  Block: TStringList;
begin
  Block := nil;
  for I := 0 to ALines.Count - 1 do
  begin
    if Copy(ALines[I], 1, 3) = '== ' then
    begin
      Block := TStringList.Create;
      ANames.Add(Copy(ALines[I], 4, MaxInt));
      ABlocks.Add(Block);
    end;
    if Block <> nil then
      Block.Add(ALines[I]);
  end;
end;

procedure CompareSections;
var
  Want: TStringList;
  WantNames, MineNames: TStringList;
  WantBlocks, MineBlocks: TList;
  I, J, K: Integer;
  W, M: TStringList;
  Same: Boolean;
begin
  WriteLn('場面ごとの比べ');
  Want := TStringList.Create;
  WantNames := TStringList.Create;
  MineNames := TStringList.Create;
  WantBlocks := TList.Create;
  MineBlocks := TList.Create;
  try
    for I := 0 to High(GamepadExpected) do
      Want.Add(GamepadExpected[I]);
    SplitSections(Want, WantNames, WantBlocks);
    SplitSections(Log, MineNames, MineBlocks);
    Check(WantNames.Text = MineNames.Text, '場面の並びが SDL と同じ (' + IntToStr(WantNames.Count) + ' 場面)');
    for I := 0 to WantNames.Count - 1 do
    begin
      K := MineNames.IndexOf(WantNames[I]);
      Same := K >= 0;
      if Same then
      begin
        W := TStringList(WantBlocks[I]);
        M := TStringList(MineBlocks[K]);
        if W.Text <> M.Text then
        begin
          Same := False;
          for J := 0 to W.Count - 1 do
            if (J >= M.Count) or (W[J] <> M[J]) then
            begin
              if J < M.Count then
                WriteLn(Format('    %d 行目 papimela: ''%s''  SDL: ''%s''', [J, M[J], W[J]]))
              else
                WriteLn(Format('    %d 行目 papimela: (終わり)  SDL: ''%s''', [J, W[J]]));
              Break;
            end;
          if (J >= W.Count) and (M.Count > W.Count) then
            WriteLn(Format('    余分な行 papimela: ''%s''', [M[W.Count]]));
        end;
      end;
      Check(Same, '場面 ' + WantNames[I] + ' が SDL と同じ記録になる');
    end;
  finally
    for I := 0 to WantBlocks.Count - 1 do
      TObject(WantBlocks[I]).Free;
    for I := 0 to MineBlocks.Count - 1 do
      TObject(MineBlocks[I]).Free;
    WantBlocks.Free;
    MineBlocks.Free;
    WantNames.Free;
    MineNames.Free;
    Want.Free;
  end;
end;

procedure RunAll;
var
  Opts: TPMLContextOptions;
begin
  Log := TStringList.Create;
  Opts := TPMLContextOptions.Default;
  Opts.Hints.Add(PML_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, '1');
  Opts.Hints.Add(PML_HINT_GAMEPAD_IGNORE_DEVICES, '0x1111/0x2222');
  Ctx := TPMLContext.Create([TPMLSubsystem.Gamepad], Opts);
  try
    Ctx.Events.UnregisterPumpSource(Ctx.Joysticks as IPMLEventPumpSource);
    Scenario;
    IgnoreCases;
    PlayerCases;
    CompareSections;
  finally
    FreeAndNil(Ctx);
  end;
  Log.Free;
end;

begin
  WriteLn('=== test_gamepad ===');
  RunAll;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: ゲームパッドが SDL と同じ記録になる ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
