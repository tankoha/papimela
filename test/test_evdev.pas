{
  test_evdev — Linux の入力の ABI と、機器の種類の決め方（PaPiMeLa.Platform.Evdev）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. ABI: 構造体の大きさと欄の位置、ioctl の要求番号を、本物のヘッダで動かした C の出力
       （test/evdev_abi_expected.inc。tools/genevdev.bb が作る）と比べる。
    2. 機器の種類: PMLEvdevGuessDeviceClass を、参照版 SDL の SDL_EVDEV_GuessDeviceClass に通した記録
       （test/evdev_caps_expected.inc。tools/evdev-expect/gen.bb が作る。実在する型と乱数の組み合わせ約 4000 件）と突き合わせる。
    3. ビットの集合の部品（PMLTestBit・PMLAnyBit・PMLBitsLength）と、sysfs の capabilities の読み方。
}
program test_evdev;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, Classes,
  PaPiMeLa.Platform.Evdev,
  PaPiMeLa.Platform.Udev;

{$I evdev_abi_expected.inc}
{$I evdev_caps_expected.inc}

var
  Failures: Integer = 0;

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

{ 構造体の欄の位置（先頭からのバイト数）。 }
function Off(var ARec; var AField): Integer;
begin
  Result := Integer(PtrUInt(@AField) - PtrUInt(@ARec));
end;

function ActualAbi(const AKey: String): String;
var
  Ev: TPMLInputEvent;
  Abs_: TPMLInputAbsInfo;
  Id: TPMLInputID;
  Ff: TPMLFFEffect;
  Env: TPMLFFEnvelope;
  Cond: TPMLFFCondition;
  Js: TPMLJsEvent;
  P: TStringList;
  Name: String;
  A, B: Integer;
begin
  Result := '?';
  P := TStringList.Create;
  try
    P.Delimiter := ' ';
    P.StrictDelimiter := True;
    P.DelimitedText := AKey;
    Name := P[0] + ' ' + P[1];
    if P[0] = 'size' then
    begin
      if P[1] = 'input_event' then Result := IntToStr(SizeOf(TPMLInputEvent))
      else if P[1] = 'input_absinfo' then Result := IntToStr(SizeOf(TPMLInputAbsInfo))
      else if P[1] = 'input_id' then Result := IntToStr(SizeOf(TPMLInputID))
      else if P[1] = 'ff_effect' then Result := IntToStr(SizeOf(TPMLFFEffect))
      else if P[1] = 'ff_replay' then Result := '4'
      else if P[1] = 'ff_trigger' then Result := '4'
      else if P[1] = 'ff_envelope' then Result := '8'
      else if P[1] = 'ff_rumble_effect' then Result := '4'
      else if P[1] = 'ff_constant_effect' then Result := IntToStr(SizeOf(Ff.ConstantLevel) + SizeOf(Ff.ConstantEnvelope))
      else if P[1] = 'ff_ramp_effect' then Result := IntToStr(SizeOf(Ff.RampStart) + SizeOf(Ff.RampEnd) + SizeOf(Ff.RampEnvelope))
      else if P[1] = 'ff_condition_effect' then Result := IntToStr(SizeOf(Ff.Condition[0]))
      else if P[1] = 'ff_periodic_effect' then Result := '32'
      else if P[1] = 'js_event' then Result := IntToStr(SizeOf(TPMLJsEvent))
      else if P[1] = 'timeval' then Result := '16';
    end
    else if P[0] = 'off' then
    begin
      Name := P[1];
      if Name = 'input_event.time' then Result := '0'
      else if Name = 'input_event.type' then Result := IntToStr(Off(Ev, Ev.EventType))
      else if Name = 'input_event.code' then Result := IntToStr(Off(Ev, Ev.Code))
      else if Name = 'input_event.value' then Result := IntToStr(Off(Ev, Ev.Value))
      else if Name = 'input_absinfo.value' then Result := IntToStr(Off(Abs_, Abs_.Value))
      else if Name = 'input_absinfo.minimum' then Result := IntToStr(Off(Abs_, Abs_.Minimum))
      else if Name = 'input_absinfo.maximum' then Result := IntToStr(Off(Abs_, Abs_.Maximum))
      else if Name = 'input_absinfo.fuzz' then Result := IntToStr(Off(Abs_, Abs_.Fuzz))
      else if Name = 'input_absinfo.flat' then Result := IntToStr(Off(Abs_, Abs_.Flat))
      else if Name = 'input_absinfo.resolution' then Result := IntToStr(Off(Abs_, Abs_.Resolution))
      else if Name = 'input_id.bustype' then Result := IntToStr(Off(Id, Id.BusType))
      else if Name = 'input_id.vendor' then Result := IntToStr(Off(Id, Id.Vendor))
      else if Name = 'input_id.product' then Result := IntToStr(Off(Id, Id.Product))
      else if Name = 'input_id.version' then Result := IntToStr(Off(Id, Id.Version))
      else if Name = 'ff_effect.type' then Result := IntToStr(Off(Ff, Ff.EffectType))
      else if Name = 'ff_effect.id' then Result := IntToStr(Off(Ff, Ff.ID))
      else if Name = 'ff_effect.direction' then Result := IntToStr(Off(Ff, Ff.Direction))
      else if Name = 'ff_effect.trigger' then Result := IntToStr(Off(Ff, Ff.TriggerButton))
      else if Name = 'ff_effect.replay' then Result := IntToStr(Off(Ff, Ff.ReplayLength))
      else if Name = 'ff_effect.u' then Result := IntToStr(Off(Ff, Ff.RumbleStrong))
      else if Name = 'ff_replay.length' then Result := '0'
      else if Name = 'ff_replay.delay' then Result := '2'
      else if Name = 'ff_rumble_effect.strong_magnitude' then Result := IntToStr(Off(Ff.RumbleStrong, Ff.RumbleStrong))
      else if Name = 'ff_rumble_effect.weak_magnitude' then Result := IntToStr(Off(Ff.RumbleStrong, Ff.RumbleWeak))
      else if Name = 'ff_periodic_effect.waveform' then Result := IntToStr(Off(Ff.RumbleStrong, Ff.PeriodicWaveform))
      else if Name = 'ff_periodic_effect.period' then Result := IntToStr(Off(Ff.RumbleStrong, Ff.PeriodicPeriod))
      else if Name = 'ff_periodic_effect.magnitude' then Result := IntToStr(Off(Ff.RumbleStrong, Ff.PeriodicMagnitude))
      else if Name = 'ff_periodic_effect.offset' then Result := IntToStr(Off(Ff.RumbleStrong, Ff.PeriodicOffset))
      else if Name = 'ff_periodic_effect.phase' then Result := IntToStr(Off(Ff.RumbleStrong, Ff.PeriodicPhase))
      else if Name = 'ff_periodic_effect.envelope' then Result := IntToStr(Off(Ff.RumbleStrong, Ff.EnvAttackLength))
      else if Name = 'ff_periodic_effect.custom_len' then Result := IntToStr(Off(Ff.RumbleStrong, Ff.CustomLen))
      else if Name = 'ff_periodic_effect.custom_data' then Result := IntToStr(Off(Ff.RumbleStrong, Ff.CustomData))
      else if Name = 'ff_trigger.button' then Result := IntToStr(Off(Ff.TriggerButton, Ff.TriggerButton))
      else if Name = 'ff_trigger.interval' then Result := IntToStr(Off(Ff.TriggerButton, Ff.TriggerInterval))
      else if Name = 'ff_envelope.attack_length' then Result := IntToStr(Off(Env, Env.AttackLength))
      else if Name = 'ff_envelope.attack_level' then Result := IntToStr(Off(Env, Env.AttackLevel))
      else if Name = 'ff_envelope.fade_length' then Result := IntToStr(Off(Env, Env.FadeLength))
      else if Name = 'ff_envelope.fade_level' then Result := IntToStr(Off(Env, Env.FadeLevel))
      else if Name = 'ff_constant_effect.level' then Result := IntToStr(Off(Ff.ConstantLevel, Ff.ConstantLevel))
      else if Name = 'ff_constant_effect.envelope' then Result := IntToStr(Off(Ff.ConstantLevel, Ff.ConstantEnvelope))
      else if Name = 'ff_ramp_effect.start_level' then Result := IntToStr(Off(Ff.RampStart, Ff.RampStart))
      else if Name = 'ff_ramp_effect.end_level' then Result := IntToStr(Off(Ff.RampStart, Ff.RampEnd))
      else if Name = 'ff_ramp_effect.envelope' then Result := IntToStr(Off(Ff.RampStart, Ff.RampEnvelope))
      else if Name = 'ff_condition_effect.right_saturation' then Result := IntToStr(Off(Cond, Cond.RightSaturation))
      else if Name = 'ff_condition_effect.left_saturation' then Result := IntToStr(Off(Cond, Cond.LeftSaturation))
      else if Name = 'ff_condition_effect.right_coeff' then Result := IntToStr(Off(Cond, Cond.RightCoeff))
      else if Name = 'ff_condition_effect.left_coeff' then Result := IntToStr(Off(Cond, Cond.LeftCoeff))
      else if Name = 'ff_condition_effect.deadband' then Result := IntToStr(Off(Cond, Cond.Deadband))
      else if Name = 'ff_condition_effect.center' then Result := IntToStr(Off(Cond, Cond.Center))
      else if Name = 'js_event.time' then Result := IntToStr(Off(Js, Js.Time))
      else if Name = 'js_event.value' then Result := IntToStr(Off(Js, Js.Value))
      else if Name = 'js_event.type' then Result := IntToStr(Off(Js, Js.EventType))
      else if Name = 'js_event.number' then Result := IntToStr(Off(Js, Js.Number));
    end
    else if P[0] = 'ioctl' then
    begin
      Name := P[1];
      if P.Count > 2 then A := StrToInt(P[2]) else A := 0;
      if P.Count > 3 then B := StrToInt(P[3]) else B := 0;
      if Name = 'EVIOCGID' then Result := LowerCase(IntToHex(PMLEVIOCGID, 1))
      else if Name = 'EVIOCSFF' then Result := LowerCase(IntToHex(PMLEVIOCSFF, 1))
      else if Name = 'EVIOCRMFF' then Result := LowerCase(IntToHex(PMLEVIOCRMFF, 1))
      else if Name = 'EVIOCGEFFECTS' then Result := LowerCase(IntToHex(PMLEVIOCGEFFECTS, 1))
      else if Name = 'JSIOCGAXES' then Result := LowerCase(IntToHex(PMLJSIOCGAXES, 1))
      else if Name = 'JSIOCGBUTTONS' then Result := LowerCase(IntToHex(PMLJSIOCGBUTTONS, 1))
      else if Name = 'EVIOCGBIT' then Result := LowerCase(IntToHex(PMLEVIOCGBIT(A, B), 1))
      else if Name = 'EVIOCGABS' then Result := LowerCase(IntToHex(PMLEVIOCGABS(A), 1))
      else if Name = 'EVIOCGNAME' then Result := LowerCase(IntToHex(PMLEVIOCGNAME(A), 1))
      else if Name = 'EVIOCGUNIQ' then Result := LowerCase(IntToHex(PMLEVIOCGUNIQ(A), 1))
      else if Name = 'EVIOCGPROP' then Result := LowerCase(IntToHex(PMLEVIOCGPROP(A), 1))
      else if Name = 'EVIOCGKEY' then Result := LowerCase(IntToHex(PMLEVIOCGKEY(A), 1))
      else if Name = 'JSIOCGNAME' then Result := LowerCase(IntToHex(PMLJSIOCGNAME(A), 1))
      else if Name = 'JSIOCGBTNMAP' then Result := LowerCase(IntToHex(PMLJSIOCGBTNMAP, 1))
      else if Name = 'JSIOCGAXMAP' then Result := LowerCase(IntToHex(PMLJSIOCGAXMAP, 1));
    end;
  finally
    P.Free;
  end;
end;

procedure TestAbi;
var
  I, Eq: Integer;
  Line, Key, Want: String;
begin
  WriteLn('ABI（構造体の大きさと位置、ioctl の番号）');
  for I := 0 to High(EvdevAbiExpected) do
  begin
    Line := EvdevAbiExpected[I];
    Eq := Pos(' = ', Line);
    Key := Copy(Line, 1, Eq - 1);
    Want := Copy(Line, Eq + 3, MaxInt);
    Check(ActualAbi(Key) = Want, Line + '  papimela=' + ActualAbi(Key));
  end;
end;

function HexToBits(const AHex: String): TPMLBits;
var
  I: Integer;
begin
  SetLength(Result, Length(AHex) div 2);
  for I := 0 to High(Result) do
    Result[I] := StrToInt('$' + Copy(AHex, I * 2 + 1, 2));
end;

function Field(const ALine, AKey: String): String;
var
  P, E: Integer;
begin
  P := Pos(' ' + AKey + '=', ' ' + ALine);
  if P = 0 then
    Exit('');
  P := P + Length(AKey) + 1;
  E := P;
  while (E <= Length(ALine)) and (ALine[E] <> ' ') do
    Inc(E);
  Result := Copy(ALine, P, E - P);
end;

procedure TestCaps;
var
  I, Bad, Want, Got: Integer;
  Line: String;
  Seen: array[0..511] of Boolean;
  Kinds: Integer;
begin
  WriteLn('機器の種類（SDL_EVDEV_GuessDeviceClass と同じ）');
  Bad := 0;
  FillChar(Seen, SizeOf(Seen), 0);
  for I := 0 to High(EvdevCapsExpected) do
  begin
    Line := EvdevCapsExpected[I];
    Want := StrToInt(Field(Line, 'c'));
    Got := PMLEvdevGuessDeviceClass(HexToBits(Field(Line, 'p')), HexToBits(Field(Line, 'e')),
      HexToBits(Field(Line, 'a')), HexToBits(Field(Line, 'k')), HexToBits(Field(Line, 'r')));
    if Want <> Got then
    begin
      Inc(Bad);
      if Bad <= 3 then
        WriteLn(Format('    %d 件目 SDL=%d papimela=%d  %s', [I, Want, Got, Line]));
    end;
    if Want < 512 then
      Seen[Want] := True;
  end;
  Kinds := 0;
  for I := 0 to 511 do
    if Seen[I] then
      Inc(Kinds);
  Check(Length(EvdevCapsExpected) > 4000, Format('%d 件を比べた', [Length(EvdevCapsExpected)]));
  Check(Kinds >= 10, Format('種類の組み合わせが %d 通り出る', [Kinds]));
  Check(Bad = 0, Format('全件が SDL と同じ（食い違い %d 件）', [Bad]));
end;

procedure TestBits;
var
  B: TPMLBits;
begin
  WriteLn('ビットの集合の部品');
  Check(PMLBitsLength(32) = 8, 'NBITS(32) は 1 語（8 バイト）');
  Check(PMLBitsLength(64) = 8, 'NBITS(64) は 1 語');
  Check(PMLBitsLength(65) = 16, 'NBITS(65) は 2 語');
  Check(PMLBitsLength(KEY_MAX + 1) = 96, 'KEY_MAX のビットは 96 バイト');
  SetLength(B, 8);
  FillChar(B[0], 8, 0);
  B[1] := $04;      // ビット 10
  Check(PMLTestBit(B, 10) and not PMLTestBit(B, 9) and not PMLTestBit(B, 11), 'PMLTestBit');
  Check(not PMLTestBit(B, -1) and not PMLTestBit(B, 64) and not PMLTestBit(B, 1000), '範囲外は立っていない');
  Check(PMLAnyBit(B, 0, 11) and not PMLAnyBit(B, 0, 10) and not PMLAnyBit(B, 11, 64), 'PMLAnyBit');
  B := PMLUdevParseCaps('120013', 64);
  Check(PMLTestBit(B, 0) and PMLTestBit(B, 1) and PMLTestBit(B, 4) and PMLTestBit(B, 16) and PMLTestBit(B, 20)
    and PMLTestBit(B, 17) = False, 'capabilities の 16 進（1 語）');
  B := PMLUdevParseCaps('3 80000000 0', 192);
  Check(PMLTestBit(B, 31 + 64) and PMLTestBit(B, 128) and PMLTestBit(B, 129) and not PMLTestBit(B, 0),
    'capabilities の複数の語は、後ろが下位');
  B := PMLUdevParseCaps('', 64);
  Check(not PMLAnyBit(B, 0, 64), '空は全部 0');
  B := PMLUdevParseCaps('ff ff ff', 64);
  Check(PMLTestBit(B, 0) and PMLTestBit(B, 7) and not PMLTestBit(B, 8), '語の数が多すぎても下位の語だけ入る');
end;

begin
  WriteLn('=== test_evdev ===');
  TestAbi;
  TestCaps;
  TestBits;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: evdev の ABI と機器の種類の決め方が SDL と同じ ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
