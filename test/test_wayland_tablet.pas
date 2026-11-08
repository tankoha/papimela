{
  test_wayland_tablet — Wayland のタブレット（tablet-v2）の実機の確認

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    実際のコンポジタとペンタブレットで、tablet-v2 のペンが Ctx.Events.Pen を通ってイベントになることを確かめる。
      1. コンポジタが zwp_tablet_manager_v2 を出している（能力 Tablet）
      2. ウィンドウを出し、利用者がペンを近づける・動かす・押す・ボタンを押す・離すのを待ち、
         届いたイベントを数える（近接・動き・筆圧 0..1・PenDown / PenUp・ボタン・近接の終わり）
      3. プロトコル違反が無い（wl_display_get_error = 0）
    ウィンドウには筆圧に応じた大きさの四角がペンの位置に出る（押していない間は小さく、色が違う）。

  WHY:
    変換は test_pen と test_tablet_tool が接続なしで確かめる。ここはコンポジタが tool_added を送ること、
    表面からウィンドウへの引き方、座標の向きと範囲、実機の筆圧の範囲（Intuos M は 4096 段階）を実機で見る。
    tablet-v2 のツールはペンが初めて近づいたときに現れるコンポジタが多いので、機器があるだけでは
    イベントは出ない。ペンを近づけること。

  使い方:
    ./test/test_wayland_tablet [待つ秒数]    既定 40 秒。ペンを近づけ、押し、サイドボタンを 1 と 2 の両方押し、離し、遠ざける。
      ボタン 1 と 2 を含め全部のイベントが揃うと早く終わる。Escape または窓を閉じても終わる。
      ペンを近づけるまで何も起きないのは正常。
    PAPIMELA_TABLET_OPTIONAL=1 : コンポジタが tablet-v2 を出さない・ペンが無いときに飛ばす（既定では失敗）。

  実行前提: Wayland セッションとペンタブレット（手元専用。CI では走らない）。
}
program test_wayland_tablet;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  cthreads,
  SysUtils,
  PaPiMeLa,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Platform.XKB,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Video.Wayland;

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

function Optional: Boolean;
begin
  Result := GetEnvironmentVariable('PAPIMELA_TABLET_OPTIONAL') = '1';
end;

var
  Ctx    : TPMLContext;
  Win    : TPMLWindow;
  R      : TPMLRenderer;
  VB     : TPMLWaylandVideoBackend;
  Seconds: Integer = 40;
  Running: Boolean = True;
  // 数える
  NIn, NOut, NMotion, NDown, NUp, NButton: Integer;
  BtnSeen: array[1..5] of Boolean;
  NAxisPressure, NOtherWindow: Integer;
  MaxPressure, MinX, MaxX, MinY, MaxY: Single;
  HasMouseEvents: Boolean;
  PenX, PenY, PenPressure: Single;
  PenDownNow: Boolean;
  Start, Now: UInt64;

procedure HandleEvents;
var
  Ev: TPMLEvent;
begin
  while Ctx.Events.Poll(Ev) do
    case Ev.Kind of
      TPMLEventKind.WindowCloseRequested: Running := False;
      TPMLEventKind.KeyDown:
        if Ev.Key.Keysym = XKB_KEY_Escape then
          Running := False;
      TPMLEventKind.PenProximityIn:
        begin
          Inc(NIn);
          WriteLn(Format('  近接 ペン %d（状態 %x）', [Ev.Pen.Which, Ev.Pen.PenState]));
          if Ev.WindowID <> Win.ID then
            Inc(NOtherWindow);
        end;
      TPMLEventKind.PenProximityOut:
        begin
          Inc(NOut);
          WriteLn('  遠ざかった');
        end;
      TPMLEventKind.PenMotion:
        begin
          Inc(NMotion);
          PenX := Ev.Pen.X;
          PenY := Ev.Pen.Y;
          if NMotion = 1 then
          begin
            MinX := PenX; MaxX := PenX; MinY := PenY; MaxY := PenY;
          end;
          if PenX < MinX then MinX := PenX;
          if PenX > MaxX then MaxX := PenX;
          if PenY < MinY then MinY := PenY;
          if PenY > MaxY then MaxY := PenY;
        end;
      TPMLEventKind.PenAxis:
        if Ev.Pen.Axis = TPMLPenAxis.Pressure then
        begin
          Inc(NAxisPressure);
          PenPressure := Ev.Pen.Value;
          if PenPressure > MaxPressure then
            MaxPressure := PenPressure;
        end;
      TPMLEventKind.PenDown:
        begin
          Inc(NDown);
          PenDownNow := True;
          WriteLn(Format('  押した (%.1f, %.1f)', [Ev.Pen.X, Ev.Pen.Y]));
        end;
      TPMLEventKind.PenUp:
        begin
          Inc(NUp);
          PenDownNow := False;
          WriteLn('  離した');
        end;
      TPMLEventKind.PenButtonDown:
        begin
          Inc(NButton);
          if (Ev.Pen.Button >= 1) and (Ev.Pen.Button <= 5) then
            BtnSeen[Ev.Pen.Button] := True;
          WriteLn(Format('  ペンのボタン %d', [Ev.Pen.Button]));
        end;
      TPMLEventKind.MouseButtonDown:
        HasMouseEvents := True;
    end;
end;

procedure Draw;
var
  S: Single;
begin
  R.DrawColor := TPMLColor.Make(24, 26, 32);
  R.Clear;
  if NIn > NOut then
  begin
    S := 6 + 60 * PenPressure;
    if PenDownNow then
      R.DrawColor := TPMLColor.Make(255, 200, 40)
    else
      R.DrawColor := TPMLColor.Make(90, 140, 220);
    R.FillRect(TPMLFRect.Make(PenX - S / 2, PenY - S / 2, S, S));
  end;
  R.Present;
end;

begin
  if ParamCount >= 1 then
    Seconds := StrToIntDef(ParamStr(1), Seconds);
  WriteLn('test_wayland_tablet — Wayland のタブレット（tablet-v2）の実機の確認');
  WriteLn;
  Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
  try
    if not (Ctx.Video.Backend is TPMLWaylandVideoBackend) then
    begin
      WriteLn('  Wayland セッションで実行してください');
      Halt(1);
    end;
    VB := TPMLWaylandVideoBackend(Ctx.Video.Backend);

    WriteLn('1. コンポジタ');
    Check(TPMLVideoCapability.Tablet in Ctx.Video.Capabilities,
      'zwp_tablet_manager_v2 がある（能力 Tablet）');
    if not (TPMLVideoCapability.Tablet in Ctx.Video.Capabilities) then
    begin
      if Optional then
      begin
        WriteLn('  [SKIP] PAPIMELA_TABLET_OPTIONAL=1');
        Exit;
      end;
      Halt(1);
    end;

    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('papimela — pen', 640, 400));
    R := TPMLRenderer.CreateForWindow(Win, 'software');
    R.VSync := 1;
    WriteLn;
    WriteLn(Format('2. ペンを近づけて、動かし、押し、ボタンを押し、離し、遠ざけてください（%d 秒）', [Seconds]));
    Start := Ctx.Timer.TicksNS;
    Now := Start;
    while Running and (Now - Start < UInt64(Seconds) * 1000000000) do
    begin
      Ctx.Events.Pump(0);
      HandleEvents;
      Draw;
      Now := Ctx.Timer.TicksNS;
      if (NIn > 0) and (NOut > 0) and (NMotion > 0) and (NDown > 0) and (NUp > 0) and BtnSeen[1] and BtnSeen[2] then
        Running := False;
    end;

    WriteLn;
    WriteLn('結果');
    WriteLn(Format('  ペン %d 本、近接 %d、遠ざかり %d、動き %d、押し %d、離し %d、ボタン %d、筆圧の変化 %d',
      [Ctx.Events.Pen.Count, NIn, NOut, NMotion, NDown, NUp, NButton, NAxisPressure]));
    WriteLn(Format('  位置の範囲 x %.1f..%.1f、y %.1f..%.1f、筆圧の最大 %.4f',
      [MinX, MaxX, MinY, MaxY, MaxPressure]));
    if (NIn = 0) and Optional then
    begin
      WriteLn('  [SKIP] ペンが近づかなかった（PAPIMELA_TABLET_OPTIONAL=1）');
      Exit;
    end;
    Check(NIn > 0, 'ペンが近づいた（PenProximityIn）');
    Check(Ctx.Events.Pen.Count >= 1, 'ペンが登録されている');
    Check(NMotion > 0, 'ペンの動きが届く（PenMotion）');
    Check(NOtherWindow = 0, '近接のイベントに今の窓の ID が載る');
    Check((MinX >= 0) and (MinY >= 0) and (MaxX <= Win.Width) and (MaxY <= Win.Height) or (NMotion = 0),
      '位置が窓の中に収まる（座標の向きと範囲）');
    Check(NDown > 0, '押した（PenDown）');
    Check(NUp > 0, '離した（PenUp）');
    Check((NDown = 0) or ((MaxPressure > 0) and (MaxPressure <= 1.0)), '筆圧は 0 より大きく 1 以下');
    Check(NButton > 0, 'ペンのボタンを押した（PenButtonDown）');
    WriteLn(Format('  [INFO] 押したボタン: 1=%s 2=%s 3=%s', [BoolToStr(BtnSeen[1], True), BoolToStr(BtnSeen[2], True), BoolToStr(BtnSeen[3], True)]));
    Check(NOut > 0, '遠ざけた（PenProximityOut）');
    Check(wl_display_get_error(VB.Connection.Display) = 0, 'プロトコル違反が無い');
    WriteLn;
    if HasMouseEvents then
      WriteLn('  [INFO] ペンの押下がマウスのボタンにもなった（既定の代行）');
    Win.Free;
  finally
    FreeAndNil(Ctx);
  end;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: Wayland のタブレットのペンがイベントとして届く ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
