{
  pen_expect.inc — test_pen（T-87）と test_wayland_tablet_model（T-88）が共有する、期待値の行との突き合わせ

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    tools/pen-expect/pen_cases.c が書く行（'E …' イベント、'R …' 問い合わせの答え、'C …' カーソルの要求）と、
    papimela が出したものを並び順に比べる。イベントはキューの見張り（IPMLEventWatch）で積まれた時点で拾う
    （Poll は Pump を回し、保留していた近接 out を出してしまうので使わない）。
    数は字面でなく値で比べる（C の %.9g と FPC の書き方は違う。Single に戻せば同じ値）。

  使う側の uses: SysUtils, Classes, TypInfo, PaPiMeLa.Events
  使う側が用意するもの: function SlotOfPen(AID: TPMLPenID): Integer（papimela の ID → 手順の番号。0 は 0、知らなければ 99）
}

type
  { 積まれたイベントを全部覚える。積むのは止めない。 }
  TPenRecorder = class(TObject, IPMLEventWatch)
  public
    Events: array of TPMLEvent;
    function OnEventPushed(const AEvent: TPMLEvent): Boolean;
    procedure Clear;
  end;

var
  Failures: Integer = 0;
  Passes  : Integer = 0;
  Steps   : Integer = 0;   // 比べた手順の数。期待値の表が空のまま通らないように、最後に見る
  CaseFmt : TFormatSettings;

function SlotOfPen(AID: TPMLPenID): Integer; forward;

function TPenRecorder.OnEventPushed(const AEvent: TPMLEvent): Boolean;
begin
  SetLength(Events, Length(Events) + 1);
  Events[High(Events)] := AEvent;
  Result := True;
end;

procedure TPenRecorder.Clear;
begin
  SetLength(Events, 0);
end;

procedure Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
  begin
    Inc(Passes);
    WriteLn('  [PASS] ', ALabel);
  end
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(Failures);
  end;
end;

function Tokens(const ALine: String): TStringArray;
begin
  Result := ALine.Split([' '], TStringSplitOptions.ExcludeEmpty);
end;

function Tok(const AT: TStringArray; AIndex: Integer): String;
begin
  if AIndex < Length(AT) then
    Result := AT[AIndex]
  else
    Result := '';
end;

function TokInt(const AT: TStringArray; AIndex: Integer): Int64;
begin
  Result := StrToInt64Def(Tok(AT, AIndex), -999999);
end;

function TokSingle(const AT: TStringArray; AIndex: Integer): Single;
begin
  Result := StrToFloatDef(Tok(AT, AIndex), -999999, CaseFmt);
end;

function SameSingle(const AT: TStringArray; AIndex: Integer; AValue: Single): Boolean;
begin
  Result := TokSingle(AT, AIndex) = AValue;
end;

function F(AValue: Single): String;
begin
  Result := FloatToStrF(AValue, ffGeneral, 9, 0, CaseFmt);
end;

{ papimela のイベントを、期待値の行と同じ並びの説明にする（違ったときに見せる）。 }
function DescribeEvent(const AEv: TPMLEvent): String;
var
  K: String;
begin
  K := GetEnumName(TypeInfo(TPMLEventKind), Ord(AEv.Kind));
  case AEv.Kind of
    TPMLEventKind.PenProximityIn, TPMLEventKind.PenProximityOut, TPMLEventKind.PenDown,
    TPMLEventKind.PenUp, TPMLEventKind.PenButtonDown, TPMLEventKind.PenButtonUp,
    TPMLEventKind.PenMotion, TPMLEventKind.PenAxis:
      Result := Format('E %s %d %d %u %s %s %d %d %d %d %s',
        [K, AEv.WindowID, SlotOfPen(AEv.Pen.Which), AEv.Pen.PenState, F(AEv.Pen.X), F(AEv.Pen.Y),
         Ord(AEv.Pen.Eraser), Ord(AEv.Pen.Down), AEv.Pen.Button, Ord(AEv.Pen.Axis), F(AEv.Pen.Value)]);
    TPMLEventKind.MouseMotion:
      Result := Format('E %s %d %u %s %s', [K, AEv.WindowID, AEv.Motion.MouseID,
        F(AEv.Motion.X), F(AEv.Motion.Y)]);
    TPMLEventKind.MouseButtonDown, TPMLEventKind.MouseButtonUp:
      Result := Format('E %s %d %u %d %s %s', [K, AEv.WindowID, AEv.Button.MouseID,
        AEv.Button.Button, F(AEv.Button.X), F(AEv.Button.Y)]);
    TPMLEventKind.FingerDown, TPMLEventKind.FingerUp, TPMLEventKind.FingerMotion,
    TPMLEventKind.FingerCanceled:
      Result := Format('E %s %d %u %d %s %s %s %s %s', [K, AEv.WindowID, AEv.Finger.DeviceID,
        AEv.Finger.FingerID, F(AEv.Finger.X), F(AEv.Finger.Y), F(AEv.Finger.DX), F(AEv.Finger.DY),
        F(AEv.Finger.Pressure)]);
  else
    Result := 'E ' + K;
  end;
end;

{ 期待値の 'E …' の行と papimela のイベントが同じか。 }
function EventMatches(const AT: TStringArray; const AEv: TPMLEvent): Boolean;
var
  K: String;
begin
  K := GetEnumName(TypeInfo(TPMLEventKind), Ord(AEv.Kind));
  Result := (Tok(AT, 1) = K) and (TokInt(AT, 2) = AEv.WindowID);
  if not Result then
    Exit;
  case AEv.Kind of
    TPMLEventKind.PenProximityIn, TPMLEventKind.PenProximityOut, TPMLEventKind.PenDown,
    TPMLEventKind.PenUp, TPMLEventKind.PenButtonDown, TPMLEventKind.PenButtonUp,
    TPMLEventKind.PenMotion, TPMLEventKind.PenAxis:
      Result := (TokInt(AT, 3) = SlotOfPen(AEv.Pen.Which)) and (TokInt(AT, 4) = AEv.Pen.PenState)
        and SameSingle(AT, 5, AEv.Pen.X) and SameSingle(AT, 6, AEv.Pen.Y)
        and (TokInt(AT, 7) = Ord(AEv.Pen.Eraser)) and (TokInt(AT, 8) = Ord(AEv.Pen.Down))
        and (TokInt(AT, 9) = AEv.Pen.Button) and (TokInt(AT, 10) = Ord(AEv.Pen.Axis))
        and SameSingle(AT, 11, AEv.Pen.Value);
    TPMLEventKind.MouseMotion:
      Result := (TokInt(AT, 3) = AEv.Motion.MouseID)
        and SameSingle(AT, 4, AEv.Motion.X) and SameSingle(AT, 5, AEv.Motion.Y);
    TPMLEventKind.MouseButtonDown, TPMLEventKind.MouseButtonUp:
      Result := (TokInt(AT, 3) = AEv.Button.MouseID) and (TokInt(AT, 4) = AEv.Button.Button)
        and SameSingle(AT, 5, AEv.Button.X) and SameSingle(AT, 6, AEv.Button.Y);
    TPMLEventKind.FingerDown, TPMLEventKind.FingerUp, TPMLEventKind.FingerMotion,
    TPMLEventKind.FingerCanceled:
      Result := (TokInt(AT, 3) = AEv.Finger.DeviceID) and (TokInt(AT, 4) = AEv.Finger.FingerID)
        and SameSingle(AT, 5, AEv.Finger.X) and SameSingle(AT, 6, AEv.Finger.Y)
        and SameSingle(AT, 7, AEv.Finger.DX) and SameSingle(AT, 8, AEv.Finger.DY)
        and SameSingle(AT, 9, AEv.Finger.Pressure);
  else
    Result := False;
  end;
end;

{ 期待値の 'R status p flags a0..a6' と GetStatus の答えが同じか。 }
function StatusMatches(const AT: TStringArray; AFlags: TPMLPenInputFlags;
  const AAxes: TPMLPenAxes): Boolean;
var
  A: TPMLPenAxis;
begin
  Result := TokInt(AT, 3) = AFlags;
  for A := Low(TPMLPenAxis) to High(TPMLPenAxis) do
    Result := Result and SameSingle(AT, 4 + Ord(A), AAxes[A]);
end;

function DescribeStatus(ASlot: Integer; AFlags: TPMLPenInputFlags; const AAxes: TPMLPenAxes): String;
var
  A: TPMLPenAxis;
begin
  Result := Format('R status %d %u', [ASlot, AFlags]);
  for A := Low(TPMLPenAxis) to High(TPMLPenAxis) do
    Result := Result + ' ' + F(AAxes[A]);
end;

{ status の手順の答えの行。期待値と値が同じなら期待値の行そのもの（字面で比べられるように）、
  違えば papimela の値の説明。status の手順が出す R の行は 1 つだけ。 }
function StatusLine(const AExpected: TStringArray; ASlot: Integer; AFlags: TPMLPenInputFlags;
  const AAxes: TPMLPenAxes): String;
var
  I: Integer;
  T: TStringArray;
begin
  for I := 0 to High(AExpected) do
  begin
    T := Tokens(AExpected[I]);
    if (Tok(T, 0) = 'R') and (Tok(T, 1) = 'status') and (TokInt(T, 2) = ASlot)
      and StatusMatches(T, AFlags, AAxes) then
      Exit(AExpected[I]);
  end;
  Result := DescribeStatus(ASlot, AFlags, AAxes);
end;

{ 1 つの手順の後に出たもの（イベントと、手順が作った 'R' / 'C' の行）を、期待値の行の並びと比べる。
  AExpected は 'S' の行の次から次の 'S' / 'N' の前まで。AOther は papimela 側の 'R' / 'C' の行
  （イベントの間に挟まる順番は見ない。イベント同士の順番と、R / C 同士の順番だけを見る）。 }
procedure CompareStep(const AScene, AStep: String; const AExpected: TStringArray;
  const AEvents: array of TPMLEvent; AOther: TStrings);
var
  I, E, O: Integer;
  T: TStringArray;
  OK: Boolean;
  Why: String;
begin
  OK := True;
  Why := '';
  E := 0;
  O := 0;
  for I := 0 to High(AExpected) do
  begin
    T := Tokens(AExpected[I]);
    if Tok(T, 0) = 'E' then
    begin
      if E > High(AEvents) then
      begin
        OK := False;
        Why := Why + LineEnding + '      足りない: ' + AExpected[I];
      end
      else if not EventMatches(T, AEvents[E]) then
      begin
        OK := False;
        Why := Why + LineEnding + '      期待: ' + AExpected[I] + LineEnding + '      実際: ' + DescribeEvent(AEvents[E]);
      end;
      Inc(E);
    end
    else
    begin
      // R / C の行。R status は呼び手が StatusLine で作るので、ここでは字面で比べてよい。
      if O >= AOther.Count then
      begin
        OK := False;
        Why := Why + LineEnding + '      足りない: ' + AExpected[I];
      end
      else if AOther[O] <> AExpected[I] then
      begin
        OK := False;
        Why := Why + LineEnding + '      期待: ' + AExpected[I] + LineEnding + '      実際: ' + AOther[O];
      end;
      Inc(O);
    end;
  end;
  for I := E to High(AEvents) do
  begin
    OK := False;
    Why := Why + LineEnding + '      余分: ' + DescribeEvent(AEvents[I]);
  end;
  for I := O to AOther.Count - 1 do
  begin
    OK := False;
    Why := Why + LineEnding + '      余分: ' + AOther[I];
  end;
  Inc(Steps);
  Check(OK, AScene + ': ' + AStep + Why);
end;

{ 期待値の表から比べた手順が AMinimum 以上あるか（表を作り損ねた・空の表で通ってしまうのを防ぐ）。 }
procedure CheckStepCount(AMinimum: Integer);
begin
  Check(Steps >= AMinimum, Format('期待値の表の手順を %d 件比べた（%d 件以上あるはず。表は tools/pen-expect/gen.bb が作る）',
    [Steps, AMinimum]));
end;
