{
  test_pointer_constraints — ポインタ拘束（ロック / 閉じ込め / 相対移動）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    pointer-constraints と relative-pointer が能力に写ること、公開層の
    MouseGrab / RelativeMouseMode / MouseRect が要求としてバックエンドに届くこと、
    そしてどの組み合わせでもプロトコルエラーが起きないことを確認する。

  WHY:
    拘束が実際に有効になるかはコンポジタとポインタの位置に依存する。カーソルを
    プログラムから動かす手段が無いので、ここで検証できるのは「要求の記録」と
    「プロトコル違反をしないこと」まで。有効化されたかどうかは観測として出力し、
    アサーションにはしない。

    プロトコル違反をしないことは強い検証になる。ロックと閉じ込めを同じシート・
    同じサーフェスに同時に作ると already_constrained で接続が切られるため、
    wl_display_get_error が終始 0 であれば張り替えの順序が正しい。

  実行前提: Wayland セッション（labwc 等）。fcitx5 は不要。
}
program test_pointer_constraints;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland,
  PaPiMeLa.Video.Wayland.Window,
  PaPiMeLa.Video.Wayland.PointerGrab,
  PaPiMeLa.Video.Wayland.Seat,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Core;

var
  Ctx      : TPMLContext;
  Win      : TPMLWindow;
  WB       : TPMLWaylandWindowBackend;
  VB       : TPMLWaylandVideoBackend;
  Failures : Integer = 0;
  Motions  : Integer = 0;
  RelMotions: Integer = 0;

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

procedure Note(const AText: String);
begin
  WriteLn('  [観測] ', AText);
end;

procedure Settle(AMs: Integer);
var
  Ev: TPMLEvent;
begin
  Ctx.Events.Pump(AMs);
  while Ctx.Events.Poll(Ev) do
    if Ev.Kind = TPMLEventKind.MouseMotion then
    begin
      Inc(Motions);
      if (Ev.Motion.XRel <> 0) or (Ev.Motion.YRel <> 0) then
        Inc(RelMotions);
    end;
end;

function DisplayError: LongInt;
begin
  Result := wl_display_get_error(VB.Connection.Display);
end;

// どのシートも拘束を持っていないこと。ポインタフォーカスが無い状態の期待値。
function AnyGrab: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(VB.Seats) do
    if (VB.Seats[I].Grab <> nil)
    and (VB.Seats[I].Grab.Kind <> TPMLPointerGrabKind.None) then
      Exit(True);
end;

function GrabKindText: String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(VB.Seats) do
  begin
    if VB.Seats[I].Grab = nil then
      Continue;
    if Result <> '' then
      Result := Result + ', ';
    case VB.Seats[I].Grab.Kind of
      TPMLPointerGrabKind.None    : Result := Result + 'なし';
      TPMLPointerGrabKind.Locked  : Result := Result + 'ロック';
      TPMLPointerGrabKind.Confined: Result := Result + '閉じ込め';
    end;
    if VB.Seats[I].Grab.Effective then
      Result := Result + '（有効）';
    if VB.Seats[I].Grab.RelativeActive then
      Result := Result + '＋相対';
  end;
  if Result = '' then
    Result := 'ポインタを持つシートが無い';
end;

var
  Opts   : TPMLWindowOptions;
  HasConf: Boolean;
  HasRel : Boolean;
  Raised : Boolean;
  I      : Integer;
  PtrFocus: Boolean;
begin
  WriteLn('test_pointer_constraints — ポインタ拘束');
  WriteLn;

  Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
  try
    VB := Ctx.Video.Backend as TPMLWaylandVideoBackend;

    WriteLn('1. 能力とグローバル');
    HasConf := TPMLVideoCapability.MouseConfine in Ctx.Video.Capabilities;
    HasRel := TPMLVideoCapability.RelativeMouse in Ctx.Video.Capabilities;
    Check((VB.Connection.PointerConstraints <> nil) = HasConf,
      'MouseConfine 能力は zwp_pointer_constraints_v1 の有無と一致する');
    Check((HasRel = (HasConf and (VB.Connection.RelativePointerMgr <> nil))),
      'RelativeMouse 能力はロックと relative-pointer の両方を要求する');
    Note('pointer-constraints: ' + BoolToStr(VB.Connection.PointerConstraints <> nil, True)
      + ' / relative-pointer: ' + BoolToStr(VB.Connection.RelativePointerMgr <> nil, True));

    WriteLn;
    WriteLn('2. ウィンドウ生成');
    Opts := TPMLWindowOptions.Make('papimela — pointer constraints', 480, 320).Resizable;
    Win := Ctx.Video.CreateWindow(Opts);
    WB := Win.Backend as TPMLWaylandWindowBackend;
    Settle(120);
    Check(WB.Configured, 'configure を受け取った');
    Check(not WB.MouseGrabbed, '初期状態でグラブ要求は無い');
    Check(not WB.RelativeMouseRequested, '初期状態で相対モード要求は無い');
    Check(WB.MouseRect.IsEmpty, '初期状態で閉じ込め矩形は空');
    // configure がフラグ集合を丸ごと置き換えていた不具合の再発検知（D-24）。
    Check(TPMLWindowFlag.Resizable in Win.Flags,
      'configure のあとも生成時の Resizable が残る');

    PtrFocus := False;
    for I := 0 to High(VB.Seats) do
      if (VB.Seats[I].Grab <> nil) and (VB.Seats[I].Grab.FocusWindowID = Win.ID) then
        PtrFocus := True;
    Note('ポインタフォーカス: ' + BoolToStr(PtrFocus, True)
      + '（カーソルがウィンドウの上にあるかで変わる。拘束の有効化はこれ次第）');

    WriteLn;
    WriteLn('3. 能力が無いときは例外');
    if not HasConf then
    begin
      Raised := False;
      try
        Win.MouseGrab := True;
      except
        on E: EPMLUnsupported do
          Raised := True;
      end;
      Check(Raised, 'MouseConfine が無ければ MouseGrab で EPMLUnsupported');
    end
    else
      Note('MouseConfine があるので、この検査は飛ばした');

    if not HasRel then
    begin
      Raised := False;
      try
        Win.RelativeMouseMode := True;
      except
        on E: EPMLUnsupported do
          Raised := True;
      end;
      Check(Raised, 'RelativeMouse が無ければ RelativeMouseMode で EPMLUnsupported');
    end
    else
      Note('RelativeMouse があるので、この検査は飛ばした');

    if not HasConf then
    begin
      WriteLn;
      WriteLn('  このコンポジタは pointer-constraints を持たないので以降は検査しない。');
      Win.Free;
      Check(DisplayError = 0, 'プロトコルエラーなし');
      FreeAndNil(Ctx);
      if Failures = 0 then
        ExitCode := 0
      else
        ExitCode := 1;
      Halt(ExitCode);
    end;

    WriteLn;
    WriteLn('4. グラブ要求');
    Win.MouseGrab := True;
    Settle(80);
    Check(WB.MouseGrabbed, '要求がウィンドウバックエンドに届いた');
    Check(TPMLWindowFlag.MouseGrabbed in Win.Flags, 'Flags に MouseGrabbed が入る');
    Check(DisplayError = 0, '閉じ込めを張ってもプロトコルエラーなし');
    Note('拘束: ' + GrabKindText);

    WriteLn;
    WriteLn('5. 閉じ込め矩形');
    Win.MouseRect := TPMLRect.Make(40, 40, 120, 80);
    Settle(80);
    Check(WB.MouseRect.W = 120, '矩形が届いた');
    Check(DisplayError = 0, '矩形付きの閉じ込めでプロトコルエラーなし');
    Note('拘束: ' + GrabKindText);

    // 1x1 はロックで代用する分岐。矩形を渡す経路とは別のコードを通る。
    Win.MouseRect := TPMLRect.Make(60, 60, 1, 1);
    Settle(80);
    Check(DisplayError = 0, '1x1 の矩形（ロックで代用）でプロトコルエラーなし');
    Note('1x1 のときの拘束: ' + GrabKindText);

    Win.MouseRect := TPMLRect.Make(0, 0, 0, 0);
    Settle(80);
    Check(DisplayError = 0, '矩形を空に戻してもプロトコルエラーなし');

    WriteLn;
    WriteLn('6. 相対モードへの張り替え');
    // ここが最も危ない経路。閉じ込めを残したままロックを作ると
    // already_constrained で接続が切られる。
    Win.RelativeMouseMode := True;
    Settle(120);
    Check(WB.RelativeMouseRequested, '相対モードの要求が届いた');
    Check(DisplayError = 0, '閉じ込め → ロックの張り替えでプロトコルエラーなし');
    Note('拘束: ' + GrabKindText);

    WriteLn;
    WriteLn('7. 往復');
    for I := 1 to 5 do
    begin
      Win.RelativeMouseMode := False;
      Settle(40);
      Win.RelativeMouseMode := True;
      Settle(40);
    end;
    Check(DisplayError = 0, '相対モードを 5 往復してもプロトコルエラーなし');

    Win.RelativeMouseMode := False;
    Win.MouseGrab := False;
    Settle(80);
    Check(not (TPMLWindowFlag.MouseGrabbed in Win.Flags),
      'グラブを外すと Flags からも消える');
    Check(not AnyGrab, '要求を全て外すと拘束は残らない');
    Check(DisplayError = 0, '全解除後もプロトコルエラーなし');

    WriteLn;
    WriteLn('8. 後始末');
    Note(Format('MouseMotion %d 件（うち相対成分あり %d 件）', [Motions, RelMotions]));
    Win.Free;
    Settle(60);
    Check(DisplayError = 0, 'ウィンドウ破棄後もプロトコルエラーなし');
    Check(Ctx.Events.DroppedCount = 0, 'イベントの取りこぼしなし');
  finally
    FreeAndNil(Ctx);
  end;
  WriteLn('  [PASS] Context 破棄');

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn('=== 結論: 拘束の張り替えがプロトコルに違反しない ===');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('=== 失敗 %d 件 ===', [Failures]));
    ExitCode := 1;
  end;
end.
