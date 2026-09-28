{
  test_wayland_window — Wayland ビデオバックエンドの結合テスト

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    TPMLContext でビデオサブシステムを起動し、ウィンドウを開いて wl_shm の
    フレームバッファへ描画し、イベントキュー経由で通知を受け取る。

  WHY:
    xdg-shell の configure → ack_configure → attach → commit の順序を守らないと
    サーフェスは可視にならない。WindowExposed が届き、描画したフレームが
    コンポジタに受理されることが、状態機械が正しいことの証明になる。

  実行前提: Wayland セッション。約 2 秒間ウィンドウが表示される。
}
program test_wayland_window;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Core;

var
  Ctx      : TPMLContext;
  Win      : TPMLWindow;
  Failures : Integer = 0;
  GotExposed  : Boolean = False;
  GotResized  : Boolean = False;
  GotClose    : Boolean = False;
  FramesDrawn : Integer = 0;

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

// フレームバッファへ市松模様のグラデーションを描く（XRGB8888）。
procedure PaintFrame(AWindow: TPMLWindow; APhase: Integer);
var
  Pixels: Pointer;
  Pitch : Integer;
  X, Y  : Integer;
  Row   : PLongWord;
  R, G, B: Byte;
begin
  if not AWindow.LockFramebuffer(Pixels, Pitch) then
    Exit;
  for Y := 0 to AWindow.Height - 1 do
  begin
    Row := PLongWord(PByte(Pixels) + PtrUInt(Y) * PtrUInt(Pitch));
    for X := 0 to AWindow.Width - 1 do
    begin
      R := Byte((X + APhase) * 255 div Max(1, AWindow.Width));
      G := Byte(Y * 255 div Max(1, AWindow.Height));
      B := Byte(128 + ((X xor Y) and 63));
      Row[X] := (LongWord(R) shl 16) or (LongWord(G) shl 8) or LongWord(B);
    end;
  end;
  AWindow.UpdateFramebuffer;
  Inc(FramesDrawn);
end;

procedure DrainEvents;
var
  Ev: TPMLEvent;
begin
  while Ctx.Events.Poll(Ev) do
    case Ev.Kind of
      TPMLEventKind.WindowExposed:
        GotExposed := True;
      TPMLEventKind.WindowResized:
        begin
          GotResized := True;
          WriteLn(Format('    WindowResized %dx%d', [Ev.Window.Data1, Ev.Window.Data2]));
        end;
      TPMLEventKind.WindowCloseRequested:
        begin
          GotClose := True;
          WriteLn('    WindowCloseRequested');
        end;
      TPMLEventKind.WindowMaximized:
        WriteLn('    WindowMaximized');
      TPMLEventKind.WindowRestored:
        WriteLn('    WindowRestored');
      TPMLEventKind.BackendLost:
        WriteLn('    [WARN] BackendLost');
    end;
end;

var
  Opts   : TPMLWindowOptions;
  Handles: TPMLNativeWindowHandles;
  I      : Integer;
  Disp   : TPMLDisplay;
begin
  WriteLn('test_wayland_window — ウィンドウを開いて描画する');
  WriteLn;

  WriteLn('1. Context 生成（Video サブシステム）');
  try
    Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
  except
    on E: EPMLError do
    begin
      WriteLn('  [FAIL] ', E.Message);
      Halt(1);
    end;
  end;

  try
    Check(Ctx.Video <> nil, 'Context.Video が存在する');
    Check(Ctx.Video.BackendName = 'wayland',
      Format('選ばれたバックエンド = "%s"', [Ctx.Video.BackendName]));
    Check(TPMLVideoCapability.SoftwareFramebuffer in Ctx.Video.Capabilities,
      'SoftwareFramebuffer 能力あり（wl_shm）');
    WriteLn(Format('  [INFO] ServerSideDecoration=%s FractionalScale=%s IdleInhibit=%s',
      [BoolToStr(TPMLVideoCapability.ServerSideDecoration in Ctx.Video.Capabilities, True),
       BoolToStr(TPMLVideoCapability.FractionalScale in Ctx.Video.Capabilities, True),
       BoolToStr(TPMLVideoCapability.IdleInhibit in Ctx.Video.Capabilities, True)]));
    Check(not (TPMLVideoCapability.WindowPositioning in Ctx.Video.Capabilities),
      'WindowPositioning は無効（xdg-shell はウィンドウ位置を持たない）');

    WriteLn;
    WriteLn('2. ディスプレイ列挙');
    Check(Length(Ctx.Video.Displays) > 0,
      Format('ディスプレイを %d 台検出', [Length(Ctx.Video.Displays)]));
    if Length(Ctx.Video.Displays) > 0 then
    begin
      Disp := Ctx.Video.PrimaryDisplay;
      WriteLn(Format('  [INFO] "%s" %dx%d scale=%.1f refresh=%.2fHz',
        [Disp.Name, Disp.DesktopMode.Width, Disp.DesktopMode.Height,
         Disp.ContentScale, Disp.DesktopMode.RefreshRate]));
      Check(Disp.DesktopMode.Width > 0, 'デスクトップモードの幅が取得できている');
    end;

    WriteLn;
    WriteLn('3. ウィンドウ生成');
    Opts := TPMLWindowOptions.Make('papimela — Wayland backend', 640, 480).Resizable;
    Win := Ctx.Video.CreateWindow(Opts);
    Check(Win <> nil, 'CreateWindow');
    Check(Win.ID <> 0, Format('ウィンドウ ID = %d', [Win.ID]));
    Check(Ctx.Video.WindowFromID(Win.ID) = Win, 'WindowFromID で引ける');

    WriteLn;
    WriteLn('4. configure を待つ');
    for I := 0 to 50 do
    begin
      Ctx.Events.Pump(20);
      DrainEvents;
      if GotExposed then
        Break;
    end;
    Check(GotExposed, 'WindowExposed が届いた（configure → ack_configure が成立）');

    WriteLn;
    WriteLn('5. ネイティブハンドル');
    Handles := Win.NativeHandles;
    Check(Handles.WaylandDisplay <> nil, 'wl_display');
    Check(Handles.WaylandSurface <> nil, 'wl_surface');
    Check(Handles.WaylandXdgSurface <> nil, 'xdg_surface');
    Check(Handles.WaylandXdgToplevel <> nil, 'xdg_toplevel');

    WriteLn;
    WriteLn('6. 約 2 秒間描画する（ウィンドウが表示される）');
    for I := 0 to 119 do
    begin
      PaintFrame(Win, I * 4);
      Ctx.Events.Pump(16);
      DrainEvents;
      if GotClose then
      begin
        WriteLn('    ユーザーが閉じたので終了する');
        Break;
      end;
    end;
    Check(FramesDrawn > 60, Format('%d フレーム描画した', [FramesDrawn]));
    Check(Ctx.Events.DroppedCount = 0, 'イベントの取りこぼしなし');

    WriteLn;
    WriteLn('7. タイトル変更と最大化の往復');
    Win.Title := 'papimela — title changed';
    Check(Win.Title = 'papimela — title changed', 'Title を設定できる');
    Win.Maximize;
    for I := 0 to 20 do begin Ctx.Events.Pump(16); DrainEvents; end;
    Win.Restore;
    for I := 0 to 20 do begin Ctx.Events.Pump(16); DrainEvents; end;
    WriteLn(Format('  [INFO] リサイズ通知の受信: %s', [BoolToStr(GotResized, True)]));

    WriteLn;
    WriteLn('8. 後始末');
    Win.Free;
    Check(Length(Ctx.Video.Windows) = 0, 'ウィンドウ一覧から外れた');
  finally
    FreeAndNil(Ctx);
  end;
  WriteLn('  [PASS] Context 破棄');

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn('=== 結論: Wayland バックエンドでウィンドウを開いて描画できる ===');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('=== 失敗 %d 件 ===', [Failures]));
    ExitCode := 1;
  end;
end.
