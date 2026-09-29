{
  demo_pointer_constraints — ポインタ拘束を実際のマウスで確認する対話デモ

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    ウィンドウを開き、キー操作でグラブ・相対モード・閉じ込め矩形を切り替えて、
    コンポジタが拘束を有効にしたかどうかと、届いた移動量を表示する。

  WHY:
    test_pointer_constraints は「要求の記録」と「プロトコル違反をしないこと」しか
    検証できない。拘束が実際に有効になるにはポインタがウィンドウの上にある必要が
    あり、カーソルをプログラムから動かす手段が無いためである。ここは人が触る。

  使い方:
    ./test/demo_pointer_constraints [秒数]        既定は 60 秒

    ウィンドウをクリックしてフォーカスし、カーソルをウィンドウの中に入れる。
      G  グラブ（ウィンドウ全体への閉じ込め）を切り替え
      R  相対モード（ロック）を切り替え
      C  閉じ込め矩形を 切らない → 中央 160x120 → 1x1 の順で切り替え
      Escape  終了
}
program demo_pointer_constraints;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Platform.XKB,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland,
  PaPiMeLa.Video.Wayland.PointerGrab,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Core;

const
  KEY_g = $0067;
  KEY_r = $0072;
  KEY_c = $0063;

var
  Ctx     : TPMLContext;
  Win     : TPMLWindow;
  VB      : TPMLWaylandVideoBackend;
  Running : Boolean = True;
  Seconds : Integer = 60;
  RectMode: Integer = 0;     // 0 = 無し、1 = 中央 160x120、2 = 1x1
  AbsCount: Integer = 0;
  RelCount: Integer = 0;
  SumRelX : Single = 0;
  SumRelY : Single = 0;
  LastKind: String = '';
  SawLock : Boolean = False;
  SawConfine: Boolean = False;
  SawRelative: Boolean = False;

function GrabText: String;
var
  I: Integer;
  G: TPMLWaylandPointerGrab;
begin
  Result := '';
  for I := 0 to High(VB.Seats) do
  begin
    G := VB.Seats[I].Grab;
    if G = nil then
      Continue;
    if Result <> '' then
      Result := Result + ' / ';
    case G.Kind of
      TPMLPointerGrabKind.None    : Result := Result + '拘束なし';
      TPMLPointerGrabKind.Locked  : begin Result := Result + 'ロック'; SawLock := True; end;
      TPMLPointerGrabKind.Confined: begin Result := Result + '閉じ込め'; SawConfine := True; end;
    end;
    if G.Effective then
      Result := Result + '（コンポジタが有効化）'
    else if G.Kind <> TPMLPointerGrabKind.None then
      Result := Result + '（要求のみ・まだ有効でない）';
    if G.RelativeActive then
    begin
      Result := Result + ' ＋相対ポインタ';
      SawRelative := True;
    end;
    Result := Result + Format(' [フォーカス=%d, 相対移動 %d 件]',
      [G.FocusWindowID, G.RelativeCount]);
  end;
  if Result = '' then
    Result := 'ポインタを持つシートが無い';
end;

procedure ReportGrab;
var
  S: String;
begin
  S := GrabText;
  if S = LastKind then
    Exit;
  LastKind := S;
  WriteLn('  状態: ', S);
end;

procedure ApplyRect;
begin
  case RectMode of
    0: begin
         Win.MouseRect := TPMLRect.Make(0, 0, 0, 0);
         WriteLn('  閉じ込め矩形: 無し（グラブが有効ならウィンドウ全体）');
       end;
    1: begin
         Win.MouseRect := TPMLRect.Make((Win.Width - 160) div 2,
           (Win.Height - 120) div 2, 160, 120);
         WriteLn('  閉じ込め矩形: 中央 160x120');
       end;
    2: begin
         Win.MouseRect := TPMLRect.Make(Win.Width div 2, Win.Height div 2, 1, 1);
         WriteLn('  閉じ込め矩形: 1x1（実装はロックで代用する）');
       end;
  end;
end;

procedure Paint;
var
  Pixels: Pointer;
  Pitch, X, Y: Integer;
  Row: PLongWord;
  Base: LongWord;
begin
  if not Win.LockFramebuffer(Pixels, Pitch) then
    Exit;
  // 相対モードは赤寄り、グラブは青寄り、素は緑寄り。
  if Win.RelativeMouseMode then
    Base := $502020
  else if Win.MouseGrab then
    Base := $202050
  else
    Base := $205020;
  for Y := 0 to Win.Height - 1 do
  begin
    Row := PLongWord(PByte(Pixels) + PtrUInt(Y) * PtrUInt(Pitch));
    for X := 0 to Win.Width - 1 do
      Row[X] := Base + LongWord((X * 48) div Max(1, Win.Width));
  end;
  Win.UpdateFramebuffer;
end;

procedure HandleEvents;
var
  Ev: TPMLEvent;
begin
  while Ctx.Events.Poll(Ev) do
    case Ev.Kind of
      TPMLEventKind.WindowMouseEnter:
        WriteLn('  ポインタがウィンドウに入った');
      TPMLEventKind.WindowMouseLeave:
        WriteLn('  ポインタがウィンドウから出た');
      TPMLEventKind.WindowFocusGained:
        WriteLn('  キーボードフォーカスを取得');
      TPMLEventKind.WindowFocusLost:
        WriteLn('  キーボードフォーカスを喪失');
      TPMLEventKind.MouseMotion:
        begin
          if (Ev.Motion.XRel = 0) and (Ev.Motion.YRel = 0) then
            Inc(AbsCount)
          else
          begin
            Inc(RelCount);
            SumRelX := SumRelX + Ev.Motion.XRel;
            SumRelY := SumRelY + Ev.Motion.YRel;
            // 相対モード中は絶対座標が動かないことを見せる。
            if (RelCount mod 20) = 1 then
              WriteLn(Format('  移動 abs=(%.0f, %.0f) rel=(%+.1f, %+.1f)',
                [Ev.Motion.X, Ev.Motion.Y, Ev.Motion.XRel, Ev.Motion.YRel]));
          end;
        end;
      TPMLEventKind.KeyDown:
        case Ev.Key.Keysym of
          XKB_KEY_Escape: Running := False;
          KEY_g:
            begin
              Win.MouseGrab := not Win.MouseGrab;
              WriteLn('  グラブ: ', BoolToStr(Win.MouseGrab, True));
            end;
          KEY_r:
            begin
              Win.RelativeMouseMode := not Win.RelativeMouseMode;
              WriteLn('  相対モード: ', BoolToStr(Win.RelativeMouseMode, True));
            end;
          KEY_c:
            begin
              RectMode := (RectMode + 1) mod 3;
              ApplyRect;
            end;
        end;
      TPMLEventKind.WindowCloseRequested:
        Running := False;
    end;
end;

var
  Opts    : TPMLWindowOptions;
  Deadline: UInt64;
begin
  if ParamCount >= 1 then
    Seconds := StrToIntDef(ParamStr(1), 60);

  WriteLn('demo_pointer_constraints — ポインタ拘束を実際のマウスで試す');
  WriteLn;
  WriteLn('  ウィンドウをクリックしてフォーカスし、カーソルを中に入れてください。');
  WriteLn('    G  グラブ（ウィンドウ全体への閉じ込め）');
  WriteLn('    R  相対モード（ロック。カーソルが止まり移動量だけが届く）');
  WriteLn('    C  閉じ込め矩形を 無し → 中央 160x120 → 1x1 と切り替え');
  WriteLn(Format('    Escape で終了。%d 秒で自動終了します。', [Seconds]));
  WriteLn;

  Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
  try
    VB := Ctx.Video.Backend as TPMLWaylandVideoBackend;
    WriteLn(Format('  ビデオ: %s', [Ctx.Video.BackendName]));
    WriteLn(Format('  能力: MouseConfine=%s RelativeMouse=%s',
      [BoolToStr(TPMLVideoCapability.MouseConfine in Ctx.Video.Capabilities, True),
       BoolToStr(TPMLVideoCapability.RelativeMouse in Ctx.Video.Capabilities, True)]));
    if not (TPMLVideoCapability.MouseConfine in Ctx.Video.Capabilities) then
    begin
      WriteLn('  このコンポジタは pointer-constraints を持たないので何も試せません。');
      Exit;
    end;

    Opts := TPMLWindowOptions.Make('papimela — pointer constraints', 640, 400).Resizable;
    Win := Ctx.Video.CreateWindow(Opts);

    Deadline := Ctx.Timer.TicksNS + UInt64(Seconds) * 1000000000;
    while Running and (Ctx.Timer.TicksNS < Deadline) do
    begin
      Paint;
      Ctx.Events.Pump(16);
      HandleEvents;
      ReportGrab;
    end;

    WriteLn;
    WriteLn('=== 結果 ===');
    WriteLn(Format('  絶対移動: %d 件 / 相対移動: %d 件', [AbsCount, RelCount]));
    WriteLn(Format('  相対移動の累計: (%+.1f, %+.1f)', [SumRelX, SumRelY]));
    WriteLn(Format('  ロックを張れた: %s', [BoolToStr(SawLock, True)]));
    WriteLn(Format('  閉じ込めを張れた: %s', [BoolToStr(SawConfine, True)]));
    WriteLn(Format('  相対ポインタを張れた: %s', [BoolToStr(SawRelative, True)]));
    WriteLn(Format('  wl_display_get_error: %d（0 ならプロトコル違反なし）',
      [wl_display_get_error(VB.Connection.Display)]));
    Win.Free;
  finally
    FreeAndNil(Ctx);
  end;
end.
