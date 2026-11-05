{
  spike7_frame_callback — wl_surface.frame のコールバックが実際に届く周期を測る

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    ソフトウェアのレンダラで VSync 無しに Present する（Present は commit の前に
    フレームの頼みを出す）。直後に WaitForFrame で合図を待ち、合図が届いた時刻の
    間隔を 300 回分集めて、平均・最小・最大・標準偏差を出す。
    画面が報告するリフレッシュレート（DesktopMode.RefreshRate）と比べる。
    結果は spikes/RESULTS.md のスパイク 7。

  WHY:
    Pi 5 では画面が 180 Hz と報告されるのに、VSync 1 の窓はどのドライバでも約 90 fps
    で回る。コンポジタの合図の周期が報告より長いのか、papimela の待ち方が半分に
    しているのかを切り分ける。描画は 1 色の塗りだけにして、描画が律速にならない。
}
program spike7_frame_callback;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland.Window,
  PaPiMeLa.Video.Wayland,
  PaPiMeLa.Render,
  PaPiMeLa.Core,
  PaPiMeLa.Backends;

const
  Samples = 300;

var
  Ctx : TPMLContext;
  Win : TPMLWindow;
  R   : TPMLRenderer;
  WB  : TPMLWaylandWindowBackend;
  Mode: TPMLDisplayMode;
  T   : array[0..Samples] of UInt64;
  I, Warm: Integer;
  D, Sum, Mn, Mx, Mean, Var_: Double;
  Dt  : array[1..Samples] of Double;
begin
  Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
  try
    if not (Ctx.Video.Backend is TPMLWaylandVideoBackend) then
    begin
      WriteLn('Wayland で動かしてください: ', Ctx.Video.BackendName);
      Halt(1);
    end;
    Mode := Ctx.Video.PrimaryDisplay.DesktopMode;
    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('spike7', 320, 200));
    WB := Win.Backend as TPMLWaylandWindowBackend;
    R := TPMLRenderer.CreateForWindow(Win, 'software');
    R.VSync := 0;

    // 窓が出て configure が済むまで空回しする
    for Warm := 1 to 30 do
    begin
      R.DrawColor := TPMLColor.Make(30, 30, 30);
      R.Clear;
      R.Present;
      WB.WaitForFrame;
      Ctx.Events.Pump(0);
    end;

    for I := 0 to Samples do
    begin
      R.DrawColor := TPMLColor.Make(30 + (I mod 2) * 40, 30, 30);
      R.Clear;
      R.Present;
      WB.WaitForFrame;
      T[I] := Ctx.Timer.TicksNS;
      Ctx.Events.Pump(0);
    end;

    Sum := 0; Mn := 1e9; Mx := 0;
    for I := 1 to Samples do
    begin
      D := (T[I] - T[I - 1]) / 1e6;
      Dt[I] := D;
      Sum := Sum + D;
      Mn := Min(Mn, D);
      Mx := Max(Mx, D);
    end;
    Mean := Sum / Samples;
    Var_ := 0;
    for I := 1 to Samples do
      Var_ := Var_ + Sqr(Dt[I] - Mean);
    WriteLn(Format('画面の報告: %.2f Hz（周期 %.3f ms）', [Mode.RefreshRate, 1000 / Mode.RefreshRate]));
    WriteLn(Format('合図の間隔 (%d 回): 平均 %.3f ms（%.2f Hz）  最小 %.3f  最大 %.3f  標準偏差 %.3f',
      [Samples, Mean, 1000 / Mean, Mn, Mx, Sqrt(Var_ / Samples)]));
    Write('先頭 40 個 (ms):');
    for I := 1 to 40 do Write(Format(' %.1f', [Dt[I]]));
    WriteLn;
    WriteLn(Format('打ち切り %d 回', [WB.FrameTimeouts]));
    Win.Free;
  finally
    FreeAndNil(Ctx);
  end;
end.
