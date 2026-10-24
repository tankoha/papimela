{
  test_gamepad_mapping — ゲームパッドのマッピングの DB（SDL_gamepad.c の AddMapping 系）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    参照版 SDL に同じ操作の列を通した記録（test/gamepad_mapping_expected.inc。
    tools/gamepad-expect/gen.bb が作る）を読み、操作（'> ADD ...' など）を papimela の
    TPMLGamepadMappingDB に行い、結果（'= ...'）が一致するかを 1 操作ごとに調べる。
      CONFIG   利用者の優先度の設定（ヒント。DB を作る前に置く）
      ADD      AddMapping。新しい 1、更新 0、失敗 -1、ヒント条件で効かない 0
      GUIDMAP  GUID から文字列（CRC・バージョンでの一致、platform の補い、位置どおりの読み替え、GameCube）
      ALL      内蔵の表を含む全部の文字列（件数と中身と順）
      IO       gamecontrollerdb.txt 形式の文章（platform の比べ方、CR、最後の行）
      HINT     ヒントを置く
    papimela の足した検査: 自動マッピングの文字列、割り当ての解釈、名前の表、顔のボタン、
    種類の欄、位置どおりの読み替えの単独の呼び出し。
}
program test_gamepad_mapping;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils, Classes,
  PaPiMeLa.Properties,
  PaPiMeLa.Joystick.GUID,
  PaPiMeLa.Joystick.Tables,
  PaPiMeLa.Joystick.Backend,
  PaPiMeLa.Gamepad.Mapping;

{$I gamepad_mapping_expected.inc}

type
  TGameCubeHolder = class
  public
    List: TPMLVIDPIDList;
    function IsGameCube(AVendor, AProduct: Word): Boolean;
  end;

var
  Failures: Integer = 0;
  Hints: TPMLHints;
  DB: TPMLGamepadMappingDB;
  Holder: TGameCubeHolder;

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

function TGameCubeHolder.IsGameCube(AVendor, AProduct: Word): Boolean;
begin
  Result := List.Contains(AVendor, AProduct);
end;

{ 記録の引数の \n \r \\ を戻す。 }
function Unescape(const AText: String): String;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '\') and (I < Length(AText)) then
    begin
      Inc(I);
      case AText[I] of
        'n': Result := Result + #10;
        'r': Result := Result + #13;
      else
        Result := Result + AText[I];
      end;
    end
    else
      Result := Result + AText[I];
    Inc(I);
  end;
end;

procedure SetupDB(const AConfig: String);
begin
  Hints := TPMLHints.Create;
  Hints.SetHint(PML_HINT_GAMEPAD_CONFIG, AConfig, TPMLHintPriority.Normal);
  Holder := TGameCubeHolder.Create;
  Holder.List := TPMLVIDPIDList.Create(Hints, JoystickGameCubeDevicesInitial,
    PML_HINT_JOYSTICK_GAMECUBE_DEVICES, PML_HINT_JOYSTICK_GAMECUBE_DEVICES_EXCLUDED);
  DB := TPMLGamepadMappingDB.Create(Hints, @Holder.IsGameCube);
  DB.LoadInitial;
end;

{ 操作を行って、結果の行を返す。 }
procedure RunOp(const AOp, AArg: String; AResult: TStringList);
var
  Arg: String;
  Name, Value: String;
  P, I: Integer;
  E: TPMLGamepadMappingEntry;
  All: TStringArray;
begin
  Arg := Unescape(AArg);
  if AOp = 'CONFIG' then
    AResult.Add('= ok')
  else if AOp = 'ADD' then
    AResult.Add('= ' + IntToStr(DB.AddMapping(Arg)))
  else if AOp = 'GUIDMAP' then
  begin
    E := DB.FindForGUID(PMLStringToGUID(Arg), False);
    if E <> nil then
      AResult.Add('= ' + DB.FormatMapping(E, PMLStringToGUID(Arg)))
    else
      AResult.Add('= NULL');
  end
  else if AOp = 'ALL' then
  begin
    All := DB.AllMappings;
    AResult.Add('= count ' + IntToStr(Length(All)));
    for I := 0 to High(All) do
      AResult.Add('= ' + All[I]);
  end
  else if AOp = 'IO' then
    AResult.Add('= ' + IntToStr(DB.AddFromText(Arg)))
  else if AOp = 'HINT' then
  begin
    P := Pos('=', Arg);
    Name := Copy(Arg, 1, P - 1);
    Value := Copy(Arg, P + 1, MaxInt);
    Hints.SetHint(Name, Value, TPMLHintPriority.Normal);
    AResult.Add('= ok');
  end
  else
    AResult.Add('= ?? unknown op ' + AOp);
end;

procedure ReplayRecord;
var
  I, J, Ops: Integer;
  Line, Op, Arg, Config: String;
  Want, Mine: TStringList;
  Same: Boolean;
  Label_: String;
begin
  WriteLn('参照版 SDL の記録を 1 操作ずつ再現する');
  // 最初の操作は CONFIG
  Line := GamepadMapExpected[0];
  Config := Unescape(Copy(Line, Pos(' ', Copy(Line, 3, MaxInt)) + 3, MaxInt));
  SetupDB(Config);
  Want := TStringList.Create;
  Mine := TStringList.Create;
  try
    Ops := 0;
    I := 0;
    while I <= High(GamepadMapExpected) do
    begin
      Line := GamepadMapExpected[I];
      Inc(I);
      Op := Copy(Line, 3, MaxInt);
      J := Pos(' ', Op);
      Arg := Copy(Op, J + 1, MaxInt);
      Op := Copy(Op, 1, J - 1);
      Want.Clear;
      while (I <= High(GamepadMapExpected)) and (Copy(GamepadMapExpected[I], 1, 2) = '= ') do
      begin
        Want.Add(GamepadMapExpected[I]);
        Inc(I);
      end;
      Mine.Clear;
      RunOp(Op, Arg, Mine);
      Same := Want.Text = Mine.Text;
      Inc(Ops);
      Label_ := Format('%d %s %s', [Ops, Op, Copy(StringReplace(Arg, #10, '|', [rfReplaceAll]), 1, 56)]);
      if not Same then
      begin
        for J := 0 to Want.Count - 1 do
          if (J >= Mine.Count) or (Want[J] <> Mine[J]) then
          begin
            WriteLn('    SDL      : ', Copy(Want[J], 1, 200));
            if J < Mine.Count then
              WriteLn('    papimela : ', Copy(Mine[J], 1, 200))
            else
              WriteLn('    papimela : (終わり)');
            Break;
          end;
        if Mine.Count > Want.Count then
          WriteLn('    余分な行 papimela: ', Copy(Mine[Want.Count], 1, 200));
      end;
      Check(Same, Label_);
    end;
  finally
    Mine.Free;
    Want.Free;
  end;
end;

{ ---- papimela だけの検査 ---- }

procedure TestNames;
var
  A: TPMLGamepadAxis;
  B: TPMLGamepadButton;
begin
  WriteLn('名前の表');
  Check(PMLGamepadTypeFromString('ps5') = TPMLGamepadType.PS5, '種類 ps5');
  Check(PMLGamepadTypeFromString('+XBOXONE') = TPMLGamepadType.XboxOne, '種類は符号を飛ばして大小文字を見ない');
  Check(PMLGamepadTypeFromString('') = TPMLGamepadType.Unknown, '空は不明');
  Check(PMLGamepadTypeFromString('nonsense') = TPMLGamepadType.Unknown, '知らない名前は不明');
  Check(PMLGamepadTypeToString(TPMLGamepadType.Steam) = 'steam', '種類を文字列へ');
  Check(PMLGamepadTypeToString(TPMLGamepadType.Unknown) = '', '不明は文字列が無い');
  Check(PMLGamepadAxisFromString('-LeftTrigger', A) and (A = TPMLGamepadAxis.LeftTrigger), '軸は符号を飛ばす');
  Check(not PMLGamepadAxisFromString('a', A), '軸にボタンの名前は無い');
  Check(PMLGamepadButtonFromString('Paddle2', B) and (B = TPMLGamepadButton.LeftPaddle1), 'paddle2 は左上のパドル');
  Check(PMLGamepadButtonFromString('paddle1', B) and (B = TPMLGamepadButton.RightPaddle1), 'paddle1 は右上のパドル');
  Check(PMLGamepadButtonFromString('paddle3', B) and (B = TPMLGamepadButton.RightPaddle2), 'paddle3 は右下のパドル');
  Check(PMLGamepadButtonFromString('paddle4', B) and (B = TPMLGamepadButton.LeftPaddle2), 'paddle4 は左下のパドル');
  Check(not PMLGamepadButtonFromString('+a', B), 'ボタンは符号を飛ばさない');
  Check(PMLGamepadButtonToString(TPMLGamepadButton.Touchpad) = 'touchpad', 'ボタンを文字列へ');
  Check(PMLGamepadAxisToString(TPMLGamepadAxis.RightY) = 'righty', '軸を文字列へ');
end;

procedure TestFace;
begin
  WriteLn('顔のボタン');
  Check(PMLGamepadFaceStyleForType(TPMLGamepadType.PS4) = TPMLGamepadFaceStyle.Sony, 'PS4 は Sony');
  Check(PMLGamepadFaceStyleForType(TPMLGamepadType.SwitchPro) = TPMLGamepadFaceStyle.BAYX, 'Switch は BAYX');
  Check(PMLGamepadFaceStyleForType(TPMLGamepadType.GameCube) = TPMLGamepadFaceStyle.AXBY, 'GameCube は AXBY');
  Check(PMLGamepadFaceStyleForType(TPMLGamepadType.Xbox360) = TPMLGamepadFaceStyle.ABXY, 'Xbox は ABXY');
  Check(PMLGamepadButtonLabelForType(TPMLGamepadType.PS5, TPMLGamepadButton.North) = TPMLGamepadButtonLabel.Triangle, 'PS5 の北は三角');
  Check(PMLGamepadButtonLabelForType(TPMLGamepadType.SwitchPro, TPMLGamepadButton.South) = TPMLGamepadButtonLabel.B, 'Switch の南は B');
  Check(PMLGamepadButtonLabelForType(TPMLGamepadType.GameCube, TPMLGamepadButton.East) = TPMLGamepadButtonLabel.X, 'GameCube の東は X');
  Check(PMLGamepadButtonLabelForType(TPMLGamepadType.Standard, TPMLGamepadButton.Start) = TPMLGamepadButtonLabel.Unknown, '顔のボタンでなければ不明');
  Check(PMLMappingFaceStyle('a:b0,face:sony,', TPMLGamepadType.Standard) = TPMLGamepadFaceStyle.Sony, 'face: 欄');
  Check(PMLMappingFaceStyle('a:b0,hint:!SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1,', TPMLGamepadType.Standard) = TPMLGamepadFaceStyle.BAYX, 'ボタンの印は BAYX');
  Check(PMLMappingFaceStyle('a:b0,hint:SDL_GAMECONTROLLER_USE_GAMECUBE_LABELS,', TPMLGamepadType.PS4) = TPMLGamepadFaceStyle.AXBY, 'GameCube の印は AXBY（種類より先）');
  Check(PMLMappingFaceStyle('a:b0,', TPMLGamepadType.PS4) = TPMLGamepadFaceStyle.Sony, '印が無ければ種類から');
  Check(PMLMappingTypeField('a:b0,type:ps4,b:b1,', True) = TPMLGamepadType.PS4, 'type: 欄');
  Check(PMLMappingTypeField('a:b0,type:ps4', True) = TPMLGamepadType.Unknown, 'type: の後ろにコンマが無いと GetGamepadTypeForID は不明');
  Check(PMLMappingTypeField('a:b0,type:ps4', False) = TPMLGamepadType.PS4, 'UpdateGamepadType は欄の終わりまで');
end;

function Bindings(const AMapping: String): TPMLGamepadBindings;
begin
  Result := nil;
  PMLParseGamepadBindings(AMapping, Result);
end;

procedure TestBindings;
var
  B: TPMLGamepadBindings;
begin
  WriteLn('割り当ての解釈');
  B := Bindings('a:b0,leftx:a1,lefty:a2~,righttrigger:+a5,dpup:h0.1,dpleft:-a3,');
  Check(Length(B) = 6, '6 つ読む');
  Check((B[0].InputType = TPMLGamepadBindType.Button) and (B[0].InputIndex = 0)
    and (B[0].OutputType = TPMLGamepadBindType.Button) and (B[0].OutputButton = TPMLGamepadButton.South), 'a:b0');
  Check((B[1].InputType = TPMLGamepadBindType.Axis) and (B[1].InputIndex = 1) and (B[1].InputMin = -32768)
    and (B[1].InputMax = 32767) and (B[1].OutputAxis = TPMLGamepadAxis.LeftX) and (B[1].OutputMin = -32768)
    and (B[1].OutputMax = 32767), 'leftx:a1');
  Check((B[2].InputMin = 32767) and (B[2].InputMax = -32768), '~ は入力の範囲を逆にする');
  Check((B[3].InputMin = 0) and (B[3].InputMax = 32767) and (B[3].OutputMin = 0) and (B[3].OutputMax = 32767), 'トリガー +a5');
  Check((B[4].InputType = TPMLGamepadBindType.Hat) and (B[4].InputIndex = 0) and (B[4].InputMask = 1), 'h0.1');
  Check((B[5].InputMin = 0) and (B[5].InputMax = -32768) and (B[5].OutputType = TPMLGamepadBindType.Button), '半軸 -a3 はボタンへ');
  B := Bindings('+leftx:a0,-leftx:a1,');
  Check((Length(B) = 2) and (B[0].OutputMin = 0) and (B[0].OutputMax = 32767)
    and (B[1].OutputMin = 0) and (B[1].OutputMax = -32768), '出力の半軸');
  B := Bindings('a:b0,a:b0,');
  Check(Length(B) = 1, '同じ割り当ては足さない');
  B := Bindings('a:b0,b:b1,x:b2,y:b3,hint:SDL_GAMECONTROLLER_USE_GAMECUBE_LABELS:=1,');
  Check((Length(B) = 4) and (B[1].OutputButton = TPMLGamepadButton.West) and (B[2].OutputButton = TPMLGamepadButton.East),
    'GameCube の印で b と x が入れ替わる');
  B := Bindings('a:b0,b:b1,x:b2,y:b3,hint:SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1,');
  Check((B[0].OutputButton = TPMLGamepadButton.East) and (B[1].OutputButton = TPMLGamepadButton.South)
    and (B[2].OutputButton = TPMLGamepadButton.North) and (B[3].OutputButton = TPMLGamepadButton.West),
    'ボタンの印で a/b と x/y が入れ替わる');
  B := Bindings('nonsense:b0,a:zz,b:b1');
  Check((Length(B) = 1) and (B[0].OutputButton = TPMLGamepadButton.East), '読めない欄は飛ばす');
  B := Bindings('a : b 0,');
  Check(Length(B) = 1, '空白は読み飛ばす');
  Check(not PMLParseGamepadBindings('abcdefghijklmnopqrstuvwxyz:b0,', B), '欄の名前が長すぎると False');
  Check(Length(Bindings('a:b99999999999999,')) = 1, '大きな番号も読む');
end;

procedure TestAuto;
var
  Raw: TPMLGamepadMapping;
  S: String;
begin
  WriteLn('自動マッピングの文字列');
  Raw := PMLEmptyGamepadMapping;
  Raw.Buttons[TPMLGamepadButton.South].Kind := TPMLMappingKind.Button;
  Raw.Buttons[TPMLGamepadButton.South].Target := 3;
  Raw.Axes[TPMLGamepadAxis.LeftY].Kind := TPMLMappingKind.Axis;
  Raw.Axes[TPMLGamepadAxis.LeftY].Target := 1;
  Raw.Axes[TPMLGamepadAxis.LeftY].AxisReversed := True;
  Raw.Axes[TPMLGamepadAxis.LeftTrigger].Kind := TPMLMappingKind.Axis;
  Raw.Axes[TPMLGamepadAxis.LeftTrigger].Target := 4;
  Raw.Axes[TPMLGamepadAxis.LeftTrigger].HalfAxisPositive := True;
  Raw.Buttons[TPMLGamepadButton.DPadUp].Kind := TPMLMappingKind.Hat;
  Raw.Buttons[TPMLGamepadButton.DPadUp].Target := $11;
  Raw.Buttons[TPMLGamepadButton.LeftPaddle1].Kind := TPMLMappingKind.Button;
  Raw.Buttons[TPMLGamepadButton.LeftPaddle1].Target := 9;
  S := PMLAutomaticMappingString('Pad, with comma', Raw);
  Check(S = 'none,Pad  with comma,a:b3,dpup:h1.1,paddle2:b9,lefty:a1~,lefttrigger:+a4,', '文字列 "' + S + '"');
end;

procedure TestPlatform;
begin
  WriteLn('内蔵の表');
  Check(DB.Count > 270, '内蔵の表を読んだ (' + IntToStr(DB.Count) + ')');
  Check(DB.DefaultMapping <> nil, '記録の default の行が既定のマッピングになる');
end;

begin
  WriteLn('=== test_gamepad_mapping ===');
  ReplayRecord;
  TestPlatform;
  TestNames;
  TestFace;
  TestBindings;
  TestAuto;
  DB.Free;
  Holder.List.Free;
  Holder.Free;
  Hints.Free;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: ゲームパッドのマッピングの DB が SDL と同じ記録になる ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
