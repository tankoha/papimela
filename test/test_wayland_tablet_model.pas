{
  test_wayland_tablet_model — tablet-v2 の道具の状態（TPMLWaylandTabletToolState）を表示サーバ無しで検証する（T-88）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    検査がコンポジタの役（偽の機器）をして、道具の状態に tablet-v2 の知らせの列を流し込み、frame で
    ペンの状態機械（Ctx.Events.Pen）へ流れたイベントと、道具のカーソルへの要求を見る。手順と期待値は
    test/test_wayland_tablet_cases.inc（tools/pen-expect/gen.bb が、SDL の tablet_tool_handle_* の写しに
    同じ列を通して作る）。場面:
      info              done までの情報（種類 8 つ・能力 6 つ・wacom id）、種類の分からない道具は登録しない
      stroke            近接 in → 移動 → 触れる（移動が先）→ 圧力と距離の打ち消し・傾き・回転の折り返し・
                        スライダ → ボタン（BTN_STYLUS / 2 / 3 と他）→ wheel を無視 → 離す（触れるのが先）→ 近接 out
      eraser            消しゴムの道具の触れる・離す
      not_ours          このアプリの窓でないサーフェス（移動を捨てる、窓 0 で出す）
      cursor            近接 in で形を張る、形・見え方・相対モードの変更、近接 out で戻す、2 つの道具
      window_destroyed  道具の上の窓が壊れた（SDL はペンの登録を外したまま戻さない。下の注）
      removed           近接中の道具が無くなった
    カーソルの要求のうち、アプリがカーソルを変えたときの規則は papimela の決め方（SDL の Wayland_ShowCursor と
    違う。DESIGN #66）で、期待値の側にも同じ規則を書いてある（pen_cases.c の cursor の手順）。

  WHY:
    frame の中の順序と、知らせ同士の打ち消し（圧力と距離）は、実機ではペンの線の始まりと終わりの 1 点の
    ずれとしてしか見えない。SDL の写しに同じ列を通した結果を正とする。

  実行前提: 無し（表示サーバも機器も要らない）。
  検査を先に書いた。骨組み（空の実装）で落ちることを確かめてから実装する（docs/TEST-LOG.md の T-88）。
}
program test_wayland_tablet_model;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  cthreads,
  SysUtils, Classes, TypInfo,
  PaPiMeLa.Types,
  PaPiMeLa.Properties,
  PaPiMeLa.Events,
  PaPiMeLa.Core,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Video.Wayland.Tablet;

{$I test_wayland_tablet_cases.inc}
{$I pen_expect.inc}

const
  MaxTools = 16;

type
  { 道具のカーソルへの要求を 'C …' の行で覚える。 }
  TCursorRecorder = class(TObject, IPMLWaylandToolCursorSink)
  public
    Other: TStringList;
    procedure ToolCursorShape(ASerial, AShape: LongWord);
    procedure ToolCursorHide(ASerial: LongWord);
    procedure ToolCursorReset;
  end;

var
  Tools   : array[0..MaxTools - 1] of TPMLWaylandTabletToolState;
  Alive   : array[0..MaxTools - 1] of Boolean;
  PenIDs  : array[0..MaxTools - 1] of TPMLPenID;   // 道具が登録したペン（外れた後も覚えておく）
  Other   : TStringList;
  Cursor  : TCursorRecorder;

procedure TCursorRecorder.ToolCursorShape(ASerial, AShape: LongWord);
begin
  Other.Add(Format('C shape %u %u', [ASerial, AShape]));
end;

procedure TCursorRecorder.ToolCursorHide(ASerial: LongWord);
begin
  Other.Add(Format('C hide %u', [ASerial]));
end;

procedure TCursorRecorder.ToolCursorReset;
begin
  Other.Add('C reset');
end;

function SlotOfPen(AID: TPMLPenID): Integer;
var
  I: Integer;
begin
  if AID = 0 then
    Exit(0);
  for I := 1 to MaxTools - 1 do
    if PenIDs[I] = AID then
      Exit(I);
  Result := 99;
end;

function CapsMask(ACaps: TPMLPenCapabilities): LongWord;
var
  C: TPMLPenCapability;
begin
  Result := 0;
  for C := Low(TPMLPenCapability) to High(TPMLPenCapability) do
    if C in ACaps then
      Result := Result or (LongWord(1) shl Ord(C));
end;

procedure ClearTools;
var
  I: Integer;
begin
  for I := 0 to MaxTools - 1 do
  begin
    FreeAndNil(Tools[I]);
    Alive[I] := False;
    PenIDs[I] := 0;
  end;
end;

procedure RunStep(Ctx: TPMLContext; const AStep: String; const AExpected: TStringArray);
var
  T: TStringArray;
  Op: String;
  K, I: Integer;
  S: TPMLWaylandTabletToolState;
  Axes: TPMLPenAxes;
  Flags: TPMLPenInputFlags;
  Info: TPMLPenInfo;
begin
  T := Tokens(AStep);
  Op := Tok(T, 0);
  if Op = 'cursor' then
  begin
    for I := 1 to MaxTools - 1 do
      if Alive[I] then
        Tools[I].SetCursor(TokInt(T, 1), TokInt(T, 2) <> 0, TokInt(T, 3) <> 0);
    Exit;
  end;
  if Op = 'wdestroy' then
  begin
    for I := 1 to MaxTools - 1 do
      if Alive[I] then
        Tools[I].WindowDestroyed(TokInt(T, 1));
    Exit;
  end;
  K := TokInt(T, 1);
  if Op = 'tool' then
  begin
    FreeAndNil(Tools[K]);
    Tools[K] := TPMLWaylandTabletToolState.Create(Ctx.Events.Pen, Cursor);
    Alive[K] := True;
    Exit;
  end;
  S := Tools[K];
  if Op = 'type' then
    S.ToolType(StrToInt('$' + Tok(T, 2)))
  else if Op = 'serial' then
    S.HardwareSerial(TokInt(T, 2), TokInt(T, 3))
  else if Op = 'wacom' then
    S.HardwareIdWacom(TokInt(T, 2), TokInt(T, 3))
  else if Op = 'cap' then
    S.Capability(TokInt(T, 2))
  else if Op = 'done' then
    S.Done
  else if Op = 'removed' then
  begin
    S.Removed;
    Alive[K] := False;
  end
  else if Op = 'pin' then
    S.ProximityIn(TokInt(T, 2), TokInt(T, 3))
  else if Op = 'pout' then
    S.ProximityOut
  else if Op = 'down' then
    S.Down(TokInt(T, 2))
  else if Op = 'up' then
    S.Up
  else if Op = 'motion' then
    S.Motion(wl_fixed_t(TokInt(T, 2)), wl_fixed_t(TokInt(T, 3)))
  else if Op = 'pressure' then
    S.Pressure(TokInt(T, 2))
  else if Op = 'distance' then
    S.Distance(TokInt(T, 2))
  else if Op = 'tilt' then
    S.Tilt(wl_fixed_t(TokInt(T, 2)), wl_fixed_t(TokInt(T, 3)))
  else if Op = 'rotation' then
    S.Rotation(wl_fixed_t(TokInt(T, 2)))
  else if Op = 'slider' then
    S.Slider(TokInt(T, 2))
  else if Op = 'wheel' then
    S.Wheel(wl_fixed_t(TokInt(T, 2)), TokInt(T, 3))
  else if Op = 'button' then
    S.Button(TokInt(T, 2), StrToInt('$' + Tok(T, 3)), TokInt(T, 4))
  else if Op = 'frame' then
    S.Frame(TokInt(T, 2))
  else if Op = 'info' then
  begin
    Info := S.Info;
    Other.Add(Format('R info %d %u %s %u %d %d %d %d', [K, CapsMask(Info.Capabilities), F(Info.MaxTilt),
      Info.WacomID, Info.NumButtons, Ord(Info.Subtype), Ord(Info.DeviceType) - 1, Ord(S.PenID <> 0)]));
  end
  else if Op = 'status' then
  begin
    Flags := Ctx.Events.Pen.GetStatus(S.PenID, Axes);
    Other.Add(StatusLine(AExpected, K, Flags, Axes));
  end
  else
    Check(False, '知らない手順: ' + AStep);
end;

procedure RunCases;
var
  I, J, K: Integer;
  Ctx: TPMLContext;
  Rec: TPenRecorder;
  Scene, Step: String;
  Expected: TStringArray;
begin
  Ctx := nil;
  Rec := TPenRecorder.Create;
  Other := TStringList.Create;
  Cursor := TCursorRecorder.Create;
  Cursor.Other := Other;
  try
    I := 0;
    while I <= High(TabletCases) do
    begin
      if Copy(TabletCases[I], 1, 2) = 'N ' then
      begin
        ClearTools;
        if Ctx <> nil then
        begin
          Ctx.Events.RemoveWatch(Rec);
          FreeAndNil(Ctx);
        end;
        Scene := Copy(TabletCases[I], 3, MaxInt);
        WriteLn(Scene);
        Ctx := TPMLContext.Create([]);
        Ctx.Events.AddWatch(Rec);
        Inc(I);
        Continue;
      end;
      Step := Copy(TabletCases[I], 3, MaxInt);
      Expected := nil;
      J := I + 1;
      while (J <= High(TabletCases)) and (Copy(TabletCases[J], 1, 2) <> 'S ')
        and (Copy(TabletCases[J], 1, 2) <> 'N ') do
      begin
        SetLength(Expected, Length(Expected) + 1);
        Expected[High(Expected)] := TabletCases[J];
        Inc(J);
      end;
      Rec.Clear;
      Other.Clear;
      RunStep(Ctx, Step, Expected);
      // 道具が登録したペンを番号に結ぶ（外れた後のイベントのために覚えたままにする）。
      for K := 1 to MaxTools - 1 do
        if (Tools[K] <> nil) and (Tools[K].PenID <> 0) then
          PenIDs[K] := Tools[K].PenID;
      CompareStep(Scene, Step, Expected, Rec.Events, Other);
      Ctx.Events.FlushAll;
      I := J;
    end;
  finally
    ClearTools;
    if Ctx <> nil then
    begin
      Ctx.Events.RemoveWatch(Rec);
      Ctx.Free;
    end;
    Rec.Free;
    Cursor.Free;
    Other.Free;
  end;
end;

begin
  CaseFmt := DefaultFormatSettings;
  CaseFmt.DecimalSeparator := '.';
  WriteLn('=== test_wayland_tablet_model ===');
  RunCases;
  CheckStepCount(186);
  WriteLn;
  WriteLn(Format('PASS %d / FAIL %d', [Passes, Failures]));
  if Failures = 0 then
    WriteLn('=== 結論: tablet-v2 の道具の状態が SDL と同じ順でペンのイベントを出す ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
