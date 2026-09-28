{
  test_wayland_protocols — 生成したプロトコルバインディングの結合テスト

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    tools/wlscan-pas が生成したユニットだけを使って、実際のコンポジタと
    プロトコル通信を行う。

  WHY:
    拡張プロトコルの wl_interface 記述子（メッセージ表、シグネチャ文字列、
    types 配列プール）は生成器が自前で組む。1 バイトでも違えばコンポジタは
    プロトコルエラーを返して接続を切る。xdg_surface.configure が届いて
    wl_display_get_error が 0 のままなら、記述子が正しいことの証明になる。

  実行前提: Wayland セッション（labwc / sway / GNOME / KDE のいずれか）。
}
program test_wayland_protocols;

{$mode objfpc}{$H+}
{$scopedenums off}

uses
  SysUtils,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland,
  PaPiMeLa.Platform.Wayland.Protocols.XdgShell,
  PaPiMeLa.Platform.Wayland.Protocols.TextInputUnstableV3;

var
  Failures: Integer = 0;
  Display : Pwl_display = nil;
  Registry: Pwl_registry = nil;

  // レジストリから拾うもの
  CompositorName, CompositorVer: LongWord;
  WmBaseName, WmBaseVer        : LongWord;
  SeatName, SeatVer            : LongWord;
  TIManagerName, TIManagerVer  : LongWord;
  GlobalCount                  : Integer = 0;

  Compositor: Pwl_compositor = nil;
  WmBase    : Pxdg_wm_base = nil;
  Seat      : Pwl_seat = nil;
  TIManager : Pzwp_text_input_manager_v3 = nil;
  Surface   : Pwl_surface = nil;
  XdgSurface: Pxdg_surface = nil;
  Toplevel  : Pxdg_toplevel = nil;
  TextInput : Pzwp_text_input_v3 = nil;

  ConfigureSerial: LongWord = 0;
  GotConfigure   : Boolean = False;
  GotToplevelCfg : Boolean = False;

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

type
  TRegistryWatcher = class(Twl_registry_listener)
  public
    procedure global(AProxy: Pwl_registry; name: LongWord; interface_: PAnsiChar;
      version: LongWord); override;
  end;

  TWmBaseWatcher = class(Txdg_wm_base_listener)
  public
    procedure ping(AProxy: Pxdg_wm_base; serial: LongWord); override;
  end;

  TXdgSurfaceWatcher = class(Txdg_surface_listener)
  public
    procedure configure(AProxy: Pxdg_surface; serial: LongWord); override;
  end;

  TToplevelWatcher = class(Txdg_toplevel_listener)
  public
    procedure configure(AProxy: Pxdg_toplevel; width: LongInt; height: LongInt;
      states: Pwl_array); override;
  end;

procedure TRegistryWatcher.global(AProxy: Pwl_registry; name: LongWord;
  interface_: PAnsiChar; version: LongWord);
var
  S: String;
begin
  Inc(GlobalCount);
  S := String(interface_);
  if S = 'wl_compositor' then
  begin
    CompositorName := name; CompositorVer := version;
  end
  else if S = 'xdg_wm_base' then
  begin
    WmBaseName := name; WmBaseVer := version;
  end
  else if S = 'wl_seat' then
  begin
    SeatName := name; SeatVer := version;
  end
  else if S = 'zwp_text_input_manager_v3' then
  begin
    TIManagerName := name; TIManagerVer := version;
  end;
end;

procedure TWmBaseWatcher.ping(AProxy: Pxdg_wm_base; serial: LongWord);
begin
  // 応答しないとコンポジタは応答なしと判断する。
  xdg_wm_base_pong(AProxy, serial);
  WriteLn('    (xdg_wm_base.ping に pong で応答した)');
end;

procedure TXdgSurfaceWatcher.configure(AProxy: Pxdg_surface; serial: LongWord);
begin
  GotConfigure := True;
  ConfigureSerial := serial;
  WriteLn(Format('    xdg_surface.configure serial=%d', [serial]));
end;

procedure TToplevelWatcher.configure(AProxy: Pxdg_toplevel; width: LongInt;
  height: LongInt; states: Pwl_array);
begin
  GotToplevelCfg := True;
  WriteLn(Format('    xdg_toplevel.configure %dx%d states.size=%d',
    [width, height, PtrInt(states^.size)]));
end;

var
  RegWatcher : TRegistryWatcher;
  WmWatcher  : TWmBaseWatcher;
  XsWatcher  : TXdgSurfaceWatcher;
  TlWatcher  : TToplevelWatcher;
begin
  WriteLn('test_wayland_protocols — 生成したバインディングで実際に通信する');
  WriteLn;

  WriteLn('1. libwayland のロードと接続');
  Check(PMLWaylandClientLoad, 'PMLWaylandClientLoad');
  if not PMLWaylandClientLoaded then
    Halt(1);
  Display := wl_display_connect(nil);
  Check(Display <> nil, 'wl_display_connect');
  if Display = nil then
  begin
    WriteLn('  WAYLAND_DISPLAY が設定されたセッションが必要です。');
    Halt(1);
  end;

  WriteLn;
  WriteLn('2. 記述子の初期化');
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.XdgShell.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.TextInputUnstableV3.EnsureProtocolInitialized;
  Check(wl_compositor_interface <> nil, 'コア: wl_compositor_interface を dlsym で取得');
  Check(xdg_wm_base_interface <> nil, '拡張: xdg_wm_base_interface を自前で構築');
  Check(String(xdg_wm_base_interface^.name) = 'xdg_wm_base',
    Format('構築した記述子の name = "%s"', [String(xdg_wm_base_interface^.name)]));
  Check(xdg_wm_base_interface^.method_count = 4,
    Format('xdg_wm_base のリクエスト数 = %d', [xdg_wm_base_interface^.method_count]));
  Check(xdg_wm_base_interface^.event_count = 1,
    Format('xdg_wm_base のイベント数 = %d', [xdg_wm_base_interface^.event_count]));

  WriteLn;
  WriteLn('3. レジストリ列挙（生成したリスナー抽象クラス経由）');
  RegWatcher := TRegistryWatcher.Create;
  Registry := wl_display_get_registry(Display);
  Check(Registry <> nil, 'wl_display_get_registry');
  Check(wl_registry_add_listener_object(Registry, RegWatcher) = 0,
    'wl_registry_add_listener_object');
  wl_display_roundtrip(Display);
  Check(GlobalCount > 0, Format('globals を %d 件受信', [GlobalCount]));
  Check(CompositorName <> 0, 'wl_compositor を発見');
  Check(WmBaseName <> 0, 'xdg_wm_base を発見');

  WriteLn;
  WriteLn('4. bind（拡張プロトコルの記述子を使う）');
  Compositor := Pwl_compositor(wl_registry_bind(Registry, CompositorName,
    wl_compositor_interface, CompositorVer));
  Check(Compositor <> nil, 'wl_compositor を bind');
  WmBase := Pxdg_wm_base(wl_registry_bind(Registry, WmBaseName,
    xdg_wm_base_interface, WmBaseVer));
  Check(WmBase <> nil, Format('xdg_wm_base を bind (v%d)', [WmBaseVer]));
  WmWatcher := TWmBaseWatcher.Create;
  xdg_wm_base_add_listener_object(WmBase, WmWatcher);

  WriteLn;
  WriteLn('5. サーフェス → xdg_surface → xdg_toplevel');
  Surface := wl_compositor_create_surface(Compositor);
  Check(Surface <> nil, 'wl_compositor_create_surface');
  XdgSurface := xdg_wm_base_get_xdg_surface(WmBase, Surface);
  Check(XdgSurface <> nil, 'xdg_wm_base_get_xdg_surface');
  XsWatcher := TXdgSurfaceWatcher.Create;
  xdg_surface_add_listener_object(XdgSurface, XsWatcher);
  Toplevel := xdg_surface_get_toplevel(XdgSurface);
  Check(Toplevel <> nil, 'xdg_surface_get_toplevel');
  TlWatcher := TToplevelWatcher.Create;
  xdg_toplevel_add_listener_object(Toplevel, TlWatcher);
  xdg_toplevel_set_title(Toplevel, 'papimela wlscan-pas test');
  xdg_toplevel_set_app_id(Toplevel, 'papimela.test');
  wl_surface_commit(Surface);

  WriteLn;
  WriteLn('6. configure の受信（記述子が正しいことの証明）');
  wl_display_roundtrip(Display);
  wl_display_roundtrip(Display);
  Check(GotConfigure, 'xdg_surface.configure が届いた');
  if GotConfigure then
  begin
    xdg_surface_ack_configure(XdgSurface, ConfigureSerial);
    wl_surface_commit(Surface);
    wl_display_roundtrip(Display);
  end;
  Check(GotToplevelCfg, 'xdg_toplevel.configure が届いた（wl_array 引数を含む）');

  WriteLn;
  WriteLn('7. text-input-v3（new_id + object の 2 引数を持つメッセージ）');
  if (TIManagerName <> 0) and (SeatName <> 0) then
  begin
    Seat := Pwl_seat(wl_registry_bind(Registry, SeatName, wl_seat_interface, SeatVer));
    TIManager := Pzwp_text_input_manager_v3(wl_registry_bind(Registry,
      TIManagerName, zwp_text_input_manager_v3_interface, TIManagerVer));
    Check(TIManager <> nil, 'zwp_text_input_manager_v3 を bind');
    TextInput := zwp_text_input_manager_v3_get_text_input(TIManager, Seat);
    Check(TextInput <> nil, 'get_text_input(seat)');
    wl_display_roundtrip(Display);
  end
  else
    WriteLn('  [SKIP] zwp_text_input_manager_v3 または wl_seat が無い');

  WriteLn;
  WriteLn('8. プロトコルエラーの確認');
  Check(wl_display_get_error(Display) = 0,
    Format('wl_display_get_error = %d', [wl_display_get_error(Display)]));

  WriteLn;
  WriteLn('9. 後始末（destructor リクエストの marshal フラグ）');
  if TextInput <> nil then zwp_text_input_v3_destroy(TextInput);
  if TIManager <> nil then zwp_text_input_manager_v3_destroy(TIManager);
  if Toplevel <> nil then xdg_toplevel_destroy(Toplevel);
  if XdgSurface <> nil then xdg_surface_destroy(XdgSurface);
  if Surface <> nil then wl_surface_destroy(Surface);
  if WmBase <> nil then xdg_wm_base_destroy(WmBase);
  wl_display_roundtrip(Display);
  Check(wl_display_get_error(Display) = 0, '破棄後もプロトコルエラーなし');

  wl_display_disconnect(Display);
  PMLWaylandClientUnload;
  RegWatcher.Free; WmWatcher.Free; XsWatcher.Free; TlWatcher.Free;
  WriteLn('  [PASS] 切断完了');

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn('=== 結論: 生成した記述子とスタブは実機のコンポジタと正しく通信できる ===');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('=== 失敗 %d 件 ===', [Failures]));
    ExitCode := 1;
  end;
end.
