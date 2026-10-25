{
  test_libdecor_window — Wayland のウィンドウを libdecor（クライアントサイド装飾）で動かす

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    実機のコンポジタで、libdecor のフレームを持つウィンドウを動かす。
    1. 既定の選択: xdg-decoration のあるコンポジタでは libdecor を使わない
    2. ヒント PAPIMELA_WAYLAND_PREFER_LIBDECOR を立てると libdecor の文脈ができ、ウィンドウは libdecor のフレームで動く
    3. 最初の configure が来て（libdecor が commit を受け取る）、絵（ソフトウェアのフレームバッファ）が出せる
    4. タイトルの変更、最大化と戻し（状態のフラグと大きさ）、Hide / Show（フレームを作り直す）、枠なしの窓
    5. プロトコル違反なし

  WHY:
    #69 の受け入れ検査。libdecor は GNOME のようにクライアントが枠を描くコンポジタのためだが、手元のコンポジタ
    （labwc）でも、ヒントで libdecor を選べばフレームの配線（configure・commit・状態・破棄の順序）は確かめられる。
    コンポジタが相手なので CI では走らない（手元専用）。

  実行前提: Wayland セッションと libdecor-0.so.0（と、そのプラグイン）。
}
program test_libdecor_window;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Pixels,
  PaPiMeLa.Properties,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland,
  PaPiMeLa.Video.Wayland.Window,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Core;

var
  Failures: Integer = 0;
  Ctx: TPMLContext;

procedure Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
    WriteLn('  [PASS] ', ALabel)
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(Failures);
  end;
  Flush(Output);
end;

procedure Pump(AMs: Integer);
var
  T0: UInt64;
  Ev: TPMLEvent;
begin
  T0 := Ctx.Timer.TicksNS;
  repeat
    Ctx.Events.Pump(10);
    while Ctx.Events.Poll(Ev) do ;
  until (Ctx.Timer.TicksNS - T0) div 1000000 >= UInt64(AMs);
end;

function WaitConfigured(ABackend: TPMLWaylandWindowBackend; AMs: Integer): Boolean;
var
  T0: UInt64;
  Ev: TPMLEvent;
begin
  T0 := Ctx.Timer.TicksNS;
  while not ABackend.Configured do
  begin
    Ctx.Events.Pump(10);
    while Ctx.Events.Poll(Ev) do ;
    if (Ctx.Timer.TicksNS - T0) div 1000000 >= UInt64(AMs) then
      Break;
  end;
  Result := ABackend.Configured;
end;

function NewContext(APrefer: Boolean): TPMLContext;
var
  Opts: TPMLContextOptions;
begin
  Opts := TPMLContextOptions.Default;
  if APrefer then
    Opts.Hints.Add(PML_HINT_WAYLAND_PREFER_LIBDECOR, '1');
  Result := TPMLContext.Create([TPMLSubsystem.Video], Opts);
end;

procedure DrawFrame(AWin: TPMLWindow);
var
  Pixels: Pointer;
  Pitch: Integer;
  Fmt: TPMLPixelFormat;
begin
  if AWin.Backend.CreateFramebuffer(Pixels, Pitch, Fmt) then
  begin
    FillChar(Pixels^, Pitch * AWin.Height, $80);
    AWin.Backend.UpdateFramebuffer;
  end;
end;

procedure DefaultSection;
var
  VB: TPMLWaylandVideoBackend;
  Win: TPMLWindow;
  W0: Integer;
begin
  WriteLn('1. 既定の選択');
  Ctx := NewContext(False);
  try
    VB := TPMLWaylandVideoBackend(Ctx.Video.Backend);
    if VB.Connection.DecorationMgr <> nil then
      Check(VB.LibDecor = nil, 'xdg-decoration があるコンポジタでは、libdecor を使わない')
    else
      Check(VB.LibDecor <> nil, 'xdg-decoration が無いコンポジタでは、libdecor を使う（' + VB.LibDecorError + '）');
    // xdg のままの窓でも、最大化を戻すと、浮いていたときの大きさへ戻る（0 x 0 の configure）
    if VB.LibDecor = nil then
    begin
      Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('xdg', 320, 200).Resizable);
      Check(WaitConfigured(TPMLWaylandWindowBackend(Win.Backend), 3000), 'xdg の窓の configure が来る');
      W0 := Win.Width;
      Win.Maximize;
      Pump(600);
      Check(Win.Width > W0, 'xdg の窓: 最大化すると大きさが増える');
      Win.Restore;
      Pump(600);
      Check(Win.Width = W0, Format('xdg の窓: 戻すと元の大きさ（%d）', [Win.Width]));
      Win.Free;
      Pump(100);
    end;
  finally
    Ctx.Free;
  end;
end;

procedure PreferSection;
var
  VB: TPMLWaylandVideoBackend;
  Win, Plain, Bare: TPMLWindow;
  B: TPMLWaylandWindowBackend;
  W0: Integer;
begin
  WriteLn('2. ヒントで libdecor を選ぶ');
  Ctx := NewContext(True);
  try
    VB := TPMLWaylandVideoBackend(Ctx.Video.Backend);
    Check(VB.LibDecor <> nil, 'libdecor の文脈ができる（' + VB.LibDecorError + '）');
    if VB.LibDecor = nil then
      Exit;

    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('papimela libdecor', 320, 200).Resizable);
    B := TPMLWaylandWindowBackend(Win.Backend);
    Check(B.UsesLibDecor, 'ウィンドウは libdecor のフレームで動く');
    Check(WaitConfigured(B, 3000), '最初の configure が来る（libdecor が commit を受け取る）');
    Check((Win.Width = 320) and (Win.Height = 200), '大きさは要求どおり');
    DrawFrame(Win);
    Pump(200);

    WriteLn('3. 操作');
    Win.Title := 'libdecor のタイトル';
    Pump(100);
    Check(True, 'タイトルを変えても落ちない');

    W0 := Win.Width;
    Win.Maximize;
    Pump(600);
    Check(TPMLWindowFlag.Maximized in Win.Flags, '最大化の状態のフラグが立つ');
    Check(Win.Width > W0, Format('最大化すると大きさが増える（%d → %d）', [W0, Win.Width]));
    Win.Restore;
    Pump(600);
    Check(not (TPMLWindowFlag.Maximized in Win.Flags), '戻すと最大化のフラグが消える');
    Check(Win.Width = W0, Format('戻すと元の大きさ（%d）', [Win.Width]));

    Win.Hide;
    Pump(200);
    Check(not B.Configured and not B.HasFrame, 'Hide でフレームを壊し、configure の済んだ状態を捨てる');
    Win.Show;
    Check(B.HasFrame, 'Show でフレームを作り直す');
    Check(WaitConfigured(B, 3000), 'Show のあと、また configure が来る');
    DrawFrame(Win);
    Pump(200);

    Plain := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('fixed', 200, 120));
    Check(WaitConfigured(TPMLWaylandWindowBackend(Plain.Backend), 3000), '大きさを変えられない窓も configure が来る');
    Check((Plain.Width = 200) and (Plain.Height = 120), '大きさを変えられない窓は、要求の大きさのまま');
    Plain.Maximize;
    Pump(400);
    Check((Plain.Width = 200) and (Plain.Height = 120) or (TPMLWindowFlag.Maximized in Plain.Flags),
      '大きさを変えられない窓は、最大化の要求でも壊れない');

    Bare := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('bare', 160, 100).Borderless);
    Check(WaitConfigured(TPMLWaylandWindowBackend(Bare.Backend), 3000), '枠なしの窓も configure が来る');

    WriteLn('4. 破棄');
    Bare.Free;
    Plain.Free;
    Win.Free;
    Pump(150);
    Check(wl_display_get_error(VB.Connection.Display) = 0, 'プロトコル違反が無い');
  finally
    Ctx.Free;
  end;
end;

begin
  WriteLn('test_libdecor_window');
  if GetEnvironmentVariable('WAYLAND_DISPLAY') = '' then
  begin
    WriteLn('Wayland セッションが無い。この検査は手元専用');
    Halt(1);
  end;
  DefaultSection;
  PreferSection;
  WriteLn;
  WriteLn('失敗: ', Failures);
  if Failures > 0 then
    Halt(1);
end.
