{
  vsync_probe.inc — VSync の検査の基準になる周期を、コンポジタの合図から測る

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    PMLProbeFrameHz は、小さなソフトウェアの窓を作り、wl_surface.frame の合図が届く
    間隔を測って、1 秒あたりの回数（Hz）を返す。測れないとき（Wayland でない、窓が
    出ない、合図が来ない）は 0 を返す。
    PMLVSyncReferenceHz は、測れたらその値、測れなければ画面の報告値を返す。
    測れなかったかどうかは VSyncMeasured で分かる。

  WHY:
    画面が報告するリフレッシュレート（DesktopMode.RefreshRate）と、コンポジタが
    合図を出す周期は一致するとは限らない。Pi 5 の labwc では、画面は 180 Hz と
    報告されるが合図は約 90 Hz で届く（spikes/RESULTS.md のスパイク 7）。
    VSync が合図に揃うことを見る検査は、合図の周期を基準にする。

  使う側の uses: SysUtils, Math, PaPiMeLa.Video.Wayland.Window, PaPiMeLa.Render
}

var
  VSyncMeasured: Boolean = False;

function PMLProbeFrameHz(ACtx: TPMLContext): Double;
const
  Warmup  = 60;
  Samples = 150;
var
  Win : TPMLWindow;
  R   : TPMLRenderer;
  WB  : TPMLWaylandWindowBackend;
  I   : Integer;
  T0, T1: UInt64;
  TO0 : Integer;
begin
  Result := 0;
  if not (ACtx.Video.Backend is TPMLWaylandVideoBackend) then
    Exit;
  Win := ACtx.Video.CreateWindow(TPMLWindowOptions.Make('vsync probe', 160, 100));
  try
    WB := Win.Backend as TPMLWaylandWindowBackend;
    R := TPMLRenderer.CreateForWindow(Win, 'software');
    R.VSync := 0;
    // Present は commit の前に合図を頼む。続けて WaitForFrame で届くのを待つ。
    for I := 1 to Warmup do
    begin
      R.DrawColor := TPMLColor.Make(30, 30, 30);
      R.Clear;
      R.Present;
      WB.WaitForFrame;
      ACtx.Events.Pump(0);
    end;
    TO0 := WB.FrameTimeouts;
    T0 := ACtx.Timer.TicksNS;
    for I := 1 to Samples do
    begin
      R.DrawColor := TPMLColor.Make(30 + (I mod 2) * 40, 30, 30);
      R.Clear;
      R.Present;
      WB.WaitForFrame;
      ACtx.Events.Pump(0);
    end;
    T1 := ACtx.Timer.TicksNS;
    // 1 回でも打ち切りがあれば、合図が来ていない区間が混じっている
    if WB.FrameTimeouts = TO0 then
      Result := Samples / ((T1 - T0) / 1e9);
  finally
    Win.Free;
  end;
end;

function PMLVSyncReferenceHz(ACtx: TPMLContext): Double;
begin
  Result := PMLProbeFrameHz(ACtx);
  VSyncMeasured := Result > 0;
  if not VSyncMeasured then
    Result := ACtx.Video.PrimaryDisplay.DesktopMode.RefreshRate;
end;
