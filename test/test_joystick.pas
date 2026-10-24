{
  test_joystick — ジョイスティックのコアと仮想ジョイスティック（SDL_joystick.c、SDL_virtualjoystick.c）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    参照版 SDL の仮想ジョイスティックに同じ場面を通した記録（test/joystick_expected.inc。
    tools/joystick-expect/gen.bb が作る）と、papimela の記録を行ごとに突き合わせる。場面ごとに 1 つの検査:
      attach             仮想ジョイスティックを足す。名前・パス・GUID・ベンダー・プロダクト・種類・player index
      open               開く（同じ ID を開くと同じオブジェクト）。軸・ハット・ボタンの数
      axes               軸の「最初の値」の規則（静止の位置の探し方）、同じ値の重複、極端な値からの戻り
      buttons / hats     押す・離す、重複、ハット
      errors             範囲外の番号、知らない ID
      callbacks          ランブル・LED・命令の呼び出し（同じ値の繰り返しは機器へ送らない）、能力
      second device      2 台目、軸が 2 本の機器は静止が 0、対応しない操作は False
      player index       player index の設定と、既にあるものの押し出し
      events disabled    ジョイスティックのイベントを切っても状態は更新され、UpdateComplete は出る
      types by hint      ヒントの VID/PID の表で種類が変わる
      default names and types  種類ごとの既定の名前
      bad descriptions   足せない記述・知らない ID
      refcount and close 同じ ID を開いた回数だけ Close しないと壊れない
      detach while open  開いたまま外すと、全部静止に戻して JoystickRemoved、Connected が False
    papimela の足した検査: ボール（SDL は仮想ジョイスティックの nballs を写さない。D-79）、
    GUID と文字列の相互変換、VID/PID の表の読み方。

  WHY:
    §3 のジョイスティック（#59）の受け入れ検査。表示サーバも実機のジョイスティックも要らない。

  SDL との違い（意図したもの）:
    - 仮想ジョイスティックのボールが使える（SDL は nballs を写さず、ボールのイベントが出ない。D-79）
    - 範囲外の番号・知らない ID は EPMLArgument（SDL は 0 / false を返してエラーを置く）
    - 開いたジョイスティックは Close で返す
}
program test_joystick;

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
  PaPiMeLa.Joystick.Tables,
  PaPiMeLa.Joystick.Backend,
  PaPiMeLa.Joystick,
  PaPiMeLa.Joystick.Virtual;

{$I joystick_expected.inc}

type
  { 仮想ジョイスティックの呼び出しの記録（SDL の側の cb_xxx と同じ文面）。 }
  TRecorder = class
  public
    Tag: String;
    Lines: TStringList;
    procedure DoUpdate;
    procedure DoPlayer(APlayerIndex: Integer);
    function  DoRumble(ALow, AHigh: Word): Boolean;
    function  DoTriggers(ALeft, ARight: Word): Boolean;
    function  DoLED(ARed, AGreen, ABlue: Byte): Boolean;
    function  DoEffect(AData: Pointer; ASize: Integer): Boolean;
    function  DoSensors(AEnabled: Boolean): Boolean;
    procedure DoCleanup;
  end;

var
  Failures: Integer = 0;
  Ctx: TPMLContext;
  Log: TStringList;
  Known: array[0..31] of TPMLJoystickID;
  NKnown: Integer = 0;
  Recorders: TList;

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

{ ジョイスティックの ID を、現れた順に J1、J2、… と呼ぶ（SDL の側と同じ）。 }
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

{ ---- 記録 ---- }

procedure TRecorder.DoUpdate;
begin
end;

procedure TRecorder.DoPlayer(APlayerIndex: Integer);
begin
  Lines.Add(Format('cb player %s %d', [Tag, APlayerIndex]));
end;

function TRecorder.DoRumble(ALow, AHigh: Word): Boolean;
begin
  Lines.Add(Format('cb rumble %s %d %d', [Tag, ALow, AHigh]));
  Result := True;
end;

function TRecorder.DoTriggers(ALeft, ARight: Word): Boolean;
begin
  Lines.Add(Format('cb triggers %s %d %d', [Tag, ALeft, ARight]));
  Result := False;
end;

function TRecorder.DoLED(ARed, AGreen, ABlue: Byte): Boolean;
begin
  Lines.Add(Format('cb led %s %d %d %d', [Tag, ARed, AGreen, ABlue]));
  Result := True;
end;

function TRecorder.DoEffect(AData: Pointer; ASize: Integer): Boolean;
var
  First: Byte;
begin
  First := 0;
  if ASize > 0 then
    First := PByte(AData)^;
  Lines.Add(Format('cb effect %s %d %d', [Tag, ASize, First]));
  Result := True;
end;

function TRecorder.DoSensors(AEnabled: Boolean): Boolean;
begin
  Result := True;
end;

procedure TRecorder.DoCleanup;
begin
  Lines.Add(Format('cb cleanup %s', [Tag]));
end;

{ ---- 場面の部品 ---- }

procedure Section(const AName: String);
begin
  L('== ' + AName);
end;

procedure Drain;
var
  E: TPMLEvent;
begin
  while Ctx.Events.Poll(E) do
    case E.Kind of
      TPMLEventKind.JoystickAdded: LF('ev added J%d', [Lab(E.JDevice.Which)]);
      TPMLEventKind.JoystickRemoved: LF('ev removed J%d', [Lab(E.JDevice.Which)]);
      TPMLEventKind.JoystickAxisMotion: LF('ev axis J%d %d %d', [Lab(E.JAxis.Which), E.JAxis.Axis, E.JAxis.Value]);
      TPMLEventKind.JoystickBallMotion:
        LF('ev ball J%d %d %d %d', [Lab(E.JBall.Which), E.JBall.Ball, E.JBall.XRel, E.JBall.YRel]);
      TPMLEventKind.JoystickHatMotion: LF('ev hat J%d %d %d', [Lab(E.JHat.Which), E.JHat.Hat, E.JHat.Value]);
      TPMLEventKind.JoystickButtonDown: LF('ev down J%d %d', [Lab(E.JButton.Which), E.JButton.Button]);
      TPMLEventKind.JoystickButtonUp: LF('ev up J%d %d', [Lab(E.JButton.Which), E.JButton.Button]);
      TPMLEventKind.JoystickBatteryUpdated:
        LF('ev battery J%d %d %d', [Lab(E.JBattery.Which), Ord(E.JBattery.State) - 1, E.JBattery.Percent]);
      TPMLEventKind.JoystickUpdateComplete: LF('ev complete J%d', [Lab(E.JDevice.Which)]);
    else
      LF('ev other %d', [Ord(E.Kind)]);
    end;
end;

procedure Update(const ATag: String);
begin
  Ctx.Joysticks.Update;
  L('-- ' + ATag);
  Drain;
end;

function Attach(const ATag: String; AType: TPMLJoystickType; AVendor, AProduct: Word;
  NAxes, NButtons, NHats, NBalls: Integer; const AName: String; ACallbacks: Boolean): TPMLJoystickID;
var
  D: TPMLVirtualJoystickDesc;
  R: TRecorder;
begin
  FillChar(D, SizeOf(D), 0);
  D.JoystickType := AType;
  D.VendorID := AVendor;
  D.ProductID := AProduct;
  D.NumAxes := NAxes;
  D.NumButtons := NButtons;
  D.NumHats := NHats;
  D.NumBalls := NBalls;
  D.Name := AName;
  R := TRecorder.Create;
  R.Tag := ATag;
  R.Lines := Log;
  Recorders.Add(R);
  D.OnCleanup := @R.DoCleanup;
  if ACallbacks then
  begin
    D.OnUpdate := @R.DoUpdate;
    D.OnSetPlayerIndex := @R.DoPlayer;
    D.OnRumble := @R.DoRumble;
    D.OnRumbleTriggers := @R.DoTriggers;
    D.OnSetLED := @R.DoLED;
    D.OnSendEffect := @R.DoEffect;
    D.OnSetSensorsEnabled := @R.DoSensors;
  end;
  Result := Ctx.Joysticks.AttachVirtual(D);
  LF('attach %s -> J%d', [ATag, Lab(Result)]);
end;

procedure InfoForID(AID: TPMLJoystickID);
var
  P: String;
begin
  P := Ctx.Joysticks.PathForID(AID);
  if P = '' then
    P := '(none)';
  LF('info J%d name=''%s'' path=%s guid=%s vendor=%s product=%s version=%s type=%d player=%d virtual=%d',
    [Lab(AID), Ctx.Joysticks.NameForID(AID), P, PMLGUIDToString(Ctx.Joysticks.GUIDForID(AID)),
     LowerCase(IntToHex(Ctx.Joysticks.VendorForID(AID), 4)), LowerCase(IntToHex(Ctx.Joysticks.ProductForID(AID), 4)),
     LowerCase(IntToHex(Ctx.Joysticks.ProductVersionForID(AID), 4)),
     Ord(Ctx.Joysticks.TypeForID(AID)), Ctx.Joysticks.PlayerIndexForID(AID),
     Ord(Ctx.Joysticks.IsVirtual(AID))]);
end;

procedure IDsList(const ATag: String);
var
  IDs: TPMLJoystickIDs;
  S: String;
  I: Integer;
begin
  IDs := Ctx.Joysticks.Joysticks;
  S := '';
  for I := 0 to High(IDs) do
    S := S + Format(' J%d', [Lab(IDs[I])]);
  LF('list %s:%s (count=%d has=%d)', [ATag, S, Length(IDs), Ord(Ctx.Joysticks.HasJoystick)]);
end;

procedure State(const ATag: String; AJoystick: TPMLJoystick);
var
  S: String;
  I: Integer;
begin
  S := '';
  for I := 0 to AJoystick.NumAxes - 1 do
    S := S + Format(' a%d=%d', [I, AJoystick.Axes[I]]);
  for I := 0 to AJoystick.NumButtons - 1 do
    S := S + Format(' b%d=%d', [I, Ord(AJoystick.Buttons[I])]);
  for I := 0 to AJoystick.NumHats - 1 do
    S := S + Format(' h%d=%d', [I, AJoystick.Hats[I]]);
  LF('state %s:%s connected=%d', [ATag, S, Ord(AJoystick.Connected)]);
end;

procedure Initial(AJoystick: TPMLJoystick; AAxis: Integer);
var
  V: SmallInt;
  Has: Boolean;
begin
  V := $7777;
  Has := AJoystick.AxisInitialState(AAxis, V);
  if not Has then
    V := 0;
  LF('initial axis %d has=%d value=%d', [AAxis, Ord(Has), V]);
end;

{ 例外が出れば False、出なければ True（SDL の bool の戻りに当たる）。 }
function Ok(const AProc: TProcedure): Boolean;
begin
  Result := True;
  try
    AProc;
  except
    on E: EPMLArgument do
      Result := False;
  end;
end;

var
  GJ: TPMLJoystick;
  GA, GB: Integer;
  GV: Integer;

procedure DoSetAxis;
begin
  Ctx.Joysticks.SetVirtualAxis(GJ, GA, GV);
end;

procedure DoSetButton;
begin
  Ctx.Joysticks.SetVirtualButton(GJ, GA, GV <> 0);
end;

procedure DoSetHat;
begin
  Ctx.Joysticks.SetVirtualHat(GJ, GA, GV);
end;

function SetAxis(J: TPMLJoystick; AAxis, AValue: Integer): Boolean;
begin
  GJ := J; GA := AAxis; GV := AValue;
  Result := Ok(@DoSetAxis);
end;

function SetButton(J: TPMLJoystick; AButton: Integer; ADown: Boolean): Boolean;
begin
  GJ := J; GA := AButton; GV := Ord(ADown);
  Result := Ok(@DoSetButton);
end;

function SetHat(J: TPMLJoystick; AHat: Integer; AValue: Byte): Boolean;
begin
  GJ := J; GA := AHat; GV := AValue;
  Result := Ok(@DoSetHat);
end;

{ ---- 場面 ---- }

var
  A, B, C, D: TPMLJoystickID;
  JA, JB, JC: TPMLJoystick;

procedure Scenario;
var
  Again: TPMLJoystick;
  I: Integer;
  Data: array[0..2] of Byte;
  TS: array[0..7] of TPMLJoystickType;
  TID: array[0..7] of TPMLJoystickID;
  Tags: array[0..7] of String;
  V: SmallInt;
  Dummy: TPMLJoystick;
begin
  Section('attach');
  A := Attach('A', TPMLJoystickType.Unknown, $1234, $5678, 4, 4, 1, 1, '', True);
  InfoForID(A);
  IDsList('after A');
  Update('added');

  Section('open');
  JA := Ctx.Joysticks.Open(A);
  LF('open A axes=%d hats=%d buttons=%d connected=%d id=J%d', [JA.NumAxes, JA.NumHats, JA.NumButtons,
    Ord(JA.Connected), Lab(JA.ID)]);
  Again := Ctx.Joysticks.Open(A);
  LF('open again same=%d', [Ord(Again = JA)]);
  Again.Close;
  LF('from id same=%d', [Ord(Ctx.Joysticks.FromID(A) = JA)]);
  State('initial', JA);

  Section('axes');
  SetAxis(JA, 0, 20000); Update('axis0=20000');
  SetAxis(JA, 0, 20000); Update('axis0=20000 again');
  SetAxis(JA, 0, -5000); SetAxis(JA, 1, 32767); Update('axis0=-5000 axis1=32767');
  SetAxis(JA, 2, -32768); Update('axis2=-32768');
  SetAxis(JA, 2, 100); Update('axis2=100');
  SetAxis(JA, 2, 30000); Update('axis2=30000');
  SetAxis(JA, 3, 1); Update('axis3=1');
  State('axes', JA);
  for I := 0 to 3 do
    Initial(JA, I);

  Section('buttons');
  SetButton(JA, 0, True); SetButton(JA, 2, True); Update('b0 b2 down');
  SetButton(JA, 0, False); Update('b0 up');
  SetButton(JA, 2, True); Update('b2 down again');
  State('buttons', JA);

  Section('hats');
  SetHat(JA, 0, PML_HAT_RIGHTUP); Update('hat right-up');
  SetHat(JA, 0, PML_HAT_RIGHTUP); Update('hat right-up again');
  SetHat(JA, 0, PML_HAT_LEFT); Update('hat left');
  SetHat(JA, 0, PML_HAT_CENTERED); Update('hat centered');

  Section('balls');
  // ボールは papimela だけの検査（下の TestBalls）。SDL の側は使えない（D-79）。
  Update('ball 5,-3 + 2,2');

  Section('errors');
  LF('axis range ok=%d', [Ord(SetAxis(JA, 4, 1))]);
  LF('button range ok=%d', [Ord(SetButton(JA, 4, True))]);
  LF('hat range ok=%d', [Ord(SetHat(JA, 1, 1))]);
  LF('axis neg ok=%d', [Ord(SetAxis(JA, -1, 1))]);
  try
    LF('axis read %d', [JA.Axes[9]]);
  except
    on E: EPMLArgument do L('axis read 0');
  end;
  try
    LF('button read %d', [Ord(JA.Buttons[9])]);
  except
    on E: EPMLArgument do L('button read 0');
  end;
  try
    LF('hat read %d', [JA.Hats[9]]);
  except
    on E: EPMLArgument do L('hat read 0');
  end;
  try
    V := 0;
    LF('initial read ok=%d', [Ord(JA.AxisInitialState(9, V))]);
  except
    on E: EPMLArgument do L('initial read ok=0');
  end;
  Dummy := nil;
  try
    Dummy := Ctx.Joysticks.Open(9999);
  except
    on E: EPMLArgument do Dummy := nil;
  end;
  LF('open missing %d', [Ord(Dummy <> nil)]);
  try
    Ctx.Joysticks.NameForID(9999);
    L('name missing ''x''');
  except
    on E: EPMLArgument do L('name missing ''(null)''');
  end;

  Section('callbacks');
  LF('rumble %d', [Ord(JA.Rumble(100, 200, 1000))]);
  LF('rumble same %d', [Ord(JA.Rumble(100, 200, 1000))]);
  LF('rumble other %d', [Ord(JA.Rumble(300, 400, 0))]);
  LF('rumble stop %d', [Ord(JA.Rumble(0, 0, 0))]);
  LF('triggers %d', [Ord(JA.RumbleTriggers(10, 20, 500))]);
  LF('led %d', [Ord(JA.SetLED(1, 2, 3))]);
  LF('led same %d', [Ord(JA.SetLED(1, 2, 3))]);
  LF('led other %d', [Ord(JA.SetLED(1, 2, 4))]);
  Data[0] := 7; Data[1] := 8; Data[2] := 9;
  LF('effect %d', [Ord(JA.SendEffect(@Data[0], 3))]);
  LF('props rumble=%d led=%d trig=%d', [Ord(TPMLJoystickCapability.Rumble in JA.Capabilities),
    Ord(TPMLJoystickCapability.RGBLED in JA.Capabilities), Ord(TPMLJoystickCapability.TriggerRumble in JA.Capabilities)]);

  Section('initial extremes');
  C := Attach('C', TPMLJoystickType.Unknown, $0C0C, $0C0D, 3, 1, 0, 0, '', False);
  Update('C added');
  JC := Ctx.Joysticks.Open(C);
  SetAxis(JC, 0, -32768); SetAxis(JC, 2, 32767); Update('C axis0=-32768 axis2=32767');
  SetAxis(JC, 0, 100); Update('C axis0=100');
  SetAxis(JC, 2, 20000); Update('C axis2=20000');
  SetAxis(JC, 2, 5); Update('C axis2=5');
  for I := 0 to 2 do
    Initial(JC, I);
  State('C', JC);
  JC.Close;
  Ctx.Joysticks.DetachVirtual(C);
  Update('C removed');

  Section('second device');
  B := Attach('B', TPMLJoystickType.Wheel, $0ABC, $0DEF, 2, 2, 0, 0, 'My Wheel', False);
  InfoForID(B);
  IDsList('after B');
  Update('added B');
  JB := Ctx.Joysticks.Open(B);
  LF('open B axes=%d buttons=%d', [JB.NumAxes, JB.NumButtons]);
  Initial(JB, 0);
  SetAxis(JB, 0, 50); Update('B axis0=50 (2 axes: zero centered)');
  Initial(JB, 0);
  LF('rumble unsupported %d', [Ord(JB.Rumble(1, 1, 0))]);
  LF('led unsupported %d', [Ord(JB.SetLED(1, 1, 1))]);
  LF('effect unsupported %d', [Ord(JB.SendEffect(@Data[0], 1))]);

  Section('player index');
  JA.PlayerIndex := 2;
  L('set A=2 1');
  LF('A player %d B player %d', [JA.PlayerIndex, JB.PlayerIndex]);
  LF('from player 2 is A %d', [Ord(Ctx.Joysticks.FromPlayerIndex(2) = JA)]);
  JB.PlayerIndex := 2;
  L('set B=2 1');
  LF('A player %d B player %d', [JA.PlayerIndex, JB.PlayerIndex]);
  JA.PlayerIndex := -1;
  L('set A=-1 1');
  LF('A player %d B player %d', [JA.PlayerIndex, JB.PlayerIndex]);

  Section('events disabled');
  Ctx.Joysticks.SetEventsEnabled(False);
  LF('enabled %d', [Ord(Ctx.Joysticks.EventsEnabled)]);
  SetButton(JA, 1, True); Update('b1 down (disabled)');
  State('after disabled', JA);
  D := Attach('D', TPMLJoystickType.Unknown, $0D0D, $0E0E, 3, 1, 0, 0, '', False);
  Update('D added (disabled)');
  Ctx.Joysticks.SetEventsEnabled(True);
  LF('enabled %d', [Ord(Ctx.Joysticks.EventsEnabled)]);
  Ctx.Joysticks.DetachVirtual(D);
  Update('D removed (enabled)');
  SetButton(JA, 1, False); Update('b1 up (enabled)');

  Section('types by hint');
  Ctx.Hints.SetHint(PML_HINT_JOYSTICK_ARCADESTICK_DEVICES, '0x1234/0x5678');
  InfoForID(A);
  Ctx.Hints.SetHint(PML_HINT_JOYSTICK_FLIGHTSTICK_DEVICES, '0x1234/0x5678');
  InfoForID(A);
  Ctx.Hints.ResetHint(PML_HINT_JOYSTICK_FLIGHTSTICK_DEVICES);
  Ctx.Hints.SetHint(PML_HINT_JOYSTICK_ARCADESTICK_DEVICES_EXCLUDED, '0x1234/0x5678');
  InfoForID(A);
  Ctx.Hints.ResetHint(PML_HINT_JOYSTICK_ARCADESTICK_DEVICES);
  Ctx.Hints.ResetHint(PML_HINT_JOYSTICK_ARCADESTICK_DEVICES_EXCLUDED);
  Ctx.Hints.SetHint(PML_HINT_JOYSTICK_FLIGHTSTICK_DEVICES, '0x1234/0x5678,0x0abc/0x0def');
  InfoForID(A);
  InfoForID(B);
  Ctx.Hints.ResetHint(PML_HINT_JOYSTICK_FLIGHTSTICK_DEVICES);
  InfoForID(A);

  Section('default names and types');
  TS[0] := TPMLJoystickType.Wheel; TS[1] := TPMLJoystickType.ArcadeStick; TS[2] := TPMLJoystickType.FlightStick;
  TS[3] := TPMLJoystickType.DancePad; TS[4] := TPMLJoystickType.Guitar; TS[5] := TPMLJoystickType.DrumKit;
  TS[6] := TPMLJoystickType.ArcadePad; TS[7] := TPMLJoystickType.Throttle;
  for I := 0 to 7 do
  begin
    Tags[I] := 't' + IntToStr(I + 1);
    TID[I] := Attach(Tags[I], TS[I], 1 + I, 2, 1, 1, 0, 0, '', False);
    InfoForID(TID[I]);
  end;
  Update('added types');
  for I := 0 to 7 do
    Ctx.Joysticks.DetachVirtual(TID[I]);
  Update('removed types');

  Section('bad descriptions');
  try
    Ctx.Joysticks.DetachVirtual(9999);
    L('detach missing 1');
  except
    on E: EPMLArgument do L('detach missing 0');
  end;
  LF('is virtual missing %d', [Ord(Ctx.Joysticks.IsVirtual(9999))]);

  Section('refcount and close');
  Again := Ctx.Joysticks.Open(A);
  LF('open #2 same=%d', [Ord(Again = JA)]);
  Again.Close;
  LF('closed once, from id valid=%d', [Ord(Ctx.Joysticks.FromID(A) <> nil)]);

  Section('detach while open');
  SetAxis(JA, 0, 12345); SetButton(JA, 3, True); SetHat(JA, 0, PML_HAT_DOWN); Update('set before detach');
  State('before detach', JA);
  // 外す: 後始末の呼び出しは、外す手続きの中で記録される
  Ctx.Joysticks.DetachVirtual(A);
  L('detach A 1');
  Update('detached A');
  State('after detach', JA);
  IDsList('after detach');
  LF('from id still %d', [Ord(Ctx.Joysticks.FromID(A) <> nil)]);
  JA.Close;
  LF('from id after close %d', [Ord(Ctx.Joysticks.FromID(A) <> nil)]);
  L('rumble stop on close ok');
  JB.Close;
  Ctx.Joysticks.DetachVirtual(B);
  Update('detached B');
  IDsList('end');
end;

{ 記録を '== 名前' で場面ごとに切る。AIndex の場面の行を AOut に入れて、名前を返す。 }
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

{ papimela の記録を、SDL の記録と場面ごとに突き合わせる。 }
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
    for I := 0 to High(JoystickExpected) do
      Want.Add(JoystickExpected[I]);
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

{ ---- papimela だけの検査 ---- }

procedure TestBalls;
var
  Id: TPMLJoystickID;
  J: TPMLJoystick;
  DX, DY: Integer;
  E: TPMLEvent;
  Got: Integer;
  GotX, GotY: SmallInt;
begin
  WriteLn('ボール（SDL は仮想ジョイスティックの nballs を写さない。D-79）');
  Log.Clear;
  Id := Attach('C', TPMLJoystickType.Unknown, $1111, $2222, 2, 2, 0, 2, '', False);
  Ctx.Joysticks.Update;
  while Ctx.Events.Poll(E) do ;
  J := Ctx.Joysticks.Open(Id);
  Check(J.NumBalls = 2, '開いた機器のボールの数が記述のとおり');
  Ctx.Joysticks.SetVirtualBall(J, 0, 5, -3);
  Ctx.Joysticks.SetVirtualBall(J, 0, 2, 2);
  Ctx.Joysticks.Update;
  Got := 0;
  GotX := 0;
  GotY := 0;
  while Ctx.Events.Poll(E) do
    if E.Kind = TPMLEventKind.JoystickBallMotion then
    begin
      Inc(Got);
      GotX := E.JBall.XRel;
      GotY := E.JBall.YRel;
    end;
  Check((Got = 1) and (GotX = 7) and (GotY = -1), '同じ更新の中の動きは足し合わされて 1 つのイベント (7, -1)');
  J.ReadBall(0, DX, DY);
  Check((DX = 7) and (DY = -1), 'ReadBall は積み上げを返す');
  J.ReadBall(0, DX, DY);
  Check((DX = 0) and (DY = 0), '読むと 0 に戻る');
  Ctx.Joysticks.SetVirtualBall(J, 1, 30000, 30000);
  Ctx.Joysticks.SetVirtualBall(J, 1, 30000, -30000);
  Ctx.Joysticks.Update;
  Got := 0;
  GotX := 0;
  GotY := 0;
  while Ctx.Events.Poll(E) do
    if E.Kind = TPMLEventKind.JoystickBallMotion then
    begin
      Inc(Got);
      GotX := E.JBall.XRel;
      GotY := E.JBall.YRel;
    end;
  Check((Got = 1) and (GotX = 32767) and (GotY = 0), '積み上げは 16 ビットに収める (60000 は 32767、30000 と -30000 は 0)');
  try
    J.ReadBall(5, DX, DY);
    Check(False, '範囲外のボールは EPMLArgument');
  except
    on EA: EPMLArgument do Check(True, '範囲外のボールは EPMLArgument');
  end;
  J.Close;
  Ctx.Joysticks.DetachVirtual(Id);
  Ctx.Joysticks.Update;
  while Ctx.Events.Poll(E) do ;
end;

procedure TestGUID;
var
  G: TPMLGUID;
  V, P, Ver, Crc: Word;
  S: String;
begin
  WriteLn('GUID');
  G := PMLCreateJoystickGUID(PML_HARDWARE_BUS_USB, $045E, $02EA, $0408, 'Microsoft', 'Xbox One Controller', 0, 0);
  PMLGetJoystickGUIDInfo(G, V, P, Ver, Crc);
  Check((V = $045E) and (P = $02EA) and (Ver = $0408), 'ベンダー・プロダクト・バージョンを取り出せる');
  Check(Crc = PMLCRC16(PMLCRC16(PMLCRC16(0, 'Microsoft'), ' '), 'Xbox One Controller'),
    '名前の CRC はベンダー名 + 空白 + プロダクト名');
  S := PMLGUIDToString(G);
  Check((Length(S) = 32) and PMLSameGUID(PMLStringToGUID(S), G), '文字列にして戻すと同じ');
  Check(PMLCRC16(0, '123456789') = $BB3D, 'CRC-16/ARC のチェック値 (123456789 は BB3D)');
  G := PMLCreateJoystickGUIDForName('A very long product name here');
  PMLGetJoystickGUIDInfo(G, V, P, Ver, Crc);
  Check((V = 0) and (P = 0) and (Ver = 0), '名前だけの GUID にはベンダーが無い');
  Check(Copy(PChar(@G.Data[4]), 1, 11) = 'A very long', '名前の先頭が 4 バイト目から入る (SDL_strlcpy で 12 バイトまで)');
  G := PMLStringToGUID('zz11');
  Check((G.Data[0] = 0) and (G.Data[1] = $11), '16 進でない文字は 0 として読む (SDL_StringToGUID)');
  G := PMLStringToGUID('abc');
  Check((G.Data[0] = $AB) and (G.Data[1] = 0), '奇数の長さは偶数に切り捨てる');
end;

procedure TestTables;
var
  List: TPMLVIDPIDList;
  E: TPMLVIDPIDEntries;
begin
  WriteLn('VID/PID の表');
  E := PMLParseVIDPIDList('0x045e/0x02ea, 0x0079 0x181A,garbage 0x1');
  Check((Length(E) = 2) and (E[0] = $045E02EA) and (E[1] = $0079181A), '「0x」から 16 進を 2 つずつ読む');
  List := TPMLVIDPIDList.Create(nil, [$12345678, $0abc0def], '', '');
  try
    Check(List.Contains($1234, $5678) and List.Contains($0abc, $0def) and not List.Contains($1234, $5679),
      '初めから入っている表を引く');
    Check(List.IncludedCount = 2, '件数');
  finally
    List.Free;
  end;
  Check(PMLGuessControllerType(nil, $045E, $028E) = PML_CONTROLLER_TYPE_XBOX360, '表にあるコントローラ (Xbox 360)');
  Check(PMLGuessControllerType(nil, $0001, $0001) = PML_CONTROLLER_TYPE_UNKNOWN_NON_STEAM, '表に無いコントローラ');
  Check(PMLGuessControllerName($045E, $028E) = 'Xbox 360 Controller', '表にある名前');
  Check(PMLGuessControllerName($0001, $0001) = '', '表に無い名前は空');
end;

procedure TestNoBackend;
var
  Opts: TPMLContextOptions;
  C: TPMLContext;
begin
  WriteLn('始めと終わり');
  Opts := TPMLContextOptions.Default;
  C := TPMLContext.Create([TPMLSubsystem.Joystick], Opts);
  try
    Check(C.Joysticks <> nil, 'Joystick を求めると Joysticks が作られる');
    Check(Length(C.Joysticks.Joysticks) = 0, '機器が無ければ一覧は空');
    Check(not C.Joysticks.HasJoystick, 'HasJoystick は False');
  finally
    C.Free;
  end;
  C := TPMLContext.Create([], Opts);
  try
    Check(C.Joysticks = nil, '求めなければ Joysticks は nil');
  finally
    C.Free;
  end;
end;

procedure RunAll;
var
  Opts: TPMLContextOptions;
  I: Integer;
begin
  Log := TStringList.Create;
  Recorders := TList.Create;
  Opts := TPMLContextOptions.Default;
  Opts.Hints.Add(PML_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, '1');
  Ctx := TPMLContext.Create([TPMLSubsystem.Joystick], Opts);
  try
    Scenario;
    CompareSections;
    TestBalls;
  finally
    FreeAndNil(Ctx);
  end;
  TestGUID;
  TestTables;
  TestNoBackend;
  for I := 0 to Recorders.Count - 1 do
    TObject(Recorders[I]).Free;
  Recorders.Free;
  Log.Free;
end;

begin
  WriteLn('=== test_joystick ===');
  RunAll;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: ジョイスティックのコアと仮想ジョイスティックが SDL と同じ記録になる ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
