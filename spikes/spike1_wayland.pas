{
  spike1_wayland — ブロッカー検証 1

  検証したいこと: libwayland-client の生成スタブが呼ぶ可変長引数関数
  wl_proxy_marshal_flags を FPC の cdecl; varargs で正しく呼べるか。
  これが成立しないと Wayland プロトコルバインディングの生成方式を
  根本から変える必要がある。

  同時に以下も検証する:
    - libwayland が公開する wl_interface データシンボルの取り込み
    - C から Pascal の cdecl コールバックが呼ばれること (リスナー機構)
    - marshal_flags が返した proxy を使った二段目の呼び出し

  Origin: clean-room (SDL のコードは参照していない)
}
program spike1_wayland;

{$mode objfpc}{$H+}

uses
  SysUtils;

const
  libwayland = 'libwayland-client.so.0';

  // wl_display のリクエスト opcode
  WL_DISPLAY_GET_REGISTRY = 1;
  // wl_registry のリクエスト opcode
  WL_REGISTRY_BIND = 0;
  // wl_compositor のリクエスト opcode
  WL_COMPOSITOR_CREATE_SURFACE = 0;
  // wl_surface のリクエスト opcode
  WL_SURFACE_DESTROY = 0;

type
  Pwl_proxy = Pointer;
  Pwl_display = Pointer;

  Pwl_interface = ^Twl_interface;
  Pwl_message = ^Twl_message;

  Twl_message = record
    name      : PAnsiChar;
    signature : PAnsiChar;
    types     : ^Pwl_interface;
  end;

  Twl_interface = record
    name         : PAnsiChar;
    version      : LongInt;
    method_count : LongInt;
    methods      : Pwl_message;
    event_count  : LongInt;
    events       : Pwl_message;
  end;

  // wl_registry_listener の Pascal 版。フィールド順は C の構造体と一致させる。
  Twl_registry_listener = record
    global        : procedure(data: Pointer; registry: Pwl_proxy; name: LongWord;
                              iface: PAnsiChar; version: LongWord); cdecl;
    global_remove : procedure(data: Pointer; registry: Pwl_proxy; name: LongWord); cdecl;
  end;

function wl_display_connect(name: PAnsiChar): Pwl_display; cdecl; external libwayland;
procedure wl_display_disconnect(display: Pwl_display); cdecl; external libwayland;
function wl_display_roundtrip(display: Pwl_display): LongInt; cdecl; external libwayland;

function wl_proxy_get_version(proxy: Pwl_proxy): LongWord; cdecl; external libwayland;
procedure wl_proxy_destroy(proxy: Pwl_proxy); cdecl; external libwayland;
function wl_proxy_add_listener(proxy: Pwl_proxy; impl: PPointer;
  data: Pointer): LongInt; cdecl; external libwayland;

// ここが本命。C 側は可変長引数関数。
function wl_proxy_marshal_flags(proxy: Pwl_proxy; opcode: LongWord;
  iface: Pwl_interface; version: LongWord; flags: LongWord): Pwl_proxy;
  cdecl; varargs; external libwayland;

// libwayland が公開しているインターフェース記述子 (データシンボル)
var
  wl_registry_interface: Twl_interface; external libwayland name 'wl_registry_interface';
  wl_compositor_interface: Twl_interface; external libwayland name 'wl_compositor_interface';
  wl_surface_interface: Twl_interface; external libwayland name 'wl_surface_interface';

var
  GlobalCount        : Integer = 0;
  CompositorName     : LongWord = 0;
  CompositorVersion  : LongWord = 0;
  HasTextInputV3     : Boolean = False;
  TextInputV3Version : LongWord = 0;
  HasXdgWmBase       : Boolean = False;

procedure OnGlobal(data: Pointer; registry: Pwl_proxy; name: LongWord;
  iface: PAnsiChar; version: LongWord); cdecl;
var
  S: string;
begin
  Inc(GlobalCount);
  S := string(iface);
  // 最初の数件だけ表示して、あとは件数で足りる
  if GlobalCount <= 8 then
    WriteLn(Format('    [%2d] %-42s v%d', [name, S, version]));

  if S = 'wl_compositor' then
  begin
    CompositorName := name;
    CompositorVersion := version;
  end
  else if S = 'zwp_text_input_manager_v3' then
  begin
    HasTextInputV3 := True;
    TextInputV3Version := version;
  end
  else if S = 'xdg_wm_base' then
    HasXdgWmBase := True;
end;

procedure OnGlobalRemove(data: Pointer; registry: Pwl_proxy; name: LongWord); cdecl;
begin
  // このスパイクでは何もしない
end;

// 生成コードなら wl_display_get_registry() に相当する部分を手書きする
function DisplayGetRegistry(display: Pwl_display): Pwl_proxy;
begin
  // C 側: wl_proxy_marshal_flags(proxy, 1, &wl_registry_interface,
  //         wl_proxy_get_version(proxy), 0, NULL)
  // 可変長引数は new_id のプレースホルダである NULL 1 個。
  Result := wl_proxy_marshal_flags(Pwl_proxy(display), WL_DISPLAY_GET_REGISTRY,
    @wl_registry_interface, wl_proxy_get_version(Pwl_proxy(display)), 0,
    Pointer(nil));
end;

// wl_registry_bind() 相当。可変長引数が uint32 / 文字列 / uint32 / NULL の
// 混在になるため、varargs の検証としてはこちらが本番。
function RegistryBind(registry: Pwl_proxy; name: LongWord;
  iface: Pwl_interface; version: LongWord): Pwl_proxy;
begin
  Result := wl_proxy_marshal_flags(registry, WL_REGISTRY_BIND, iface, version, 0,
    name, iface^.name, version, Pointer(nil));
end;

// wl_compositor_create_surface() 相当。marshal_flags が返した proxy を
// さらに使えるかの確認。
function CompositorCreateSurface(compositor: Pwl_proxy): Pwl_proxy;
begin
  Result := wl_proxy_marshal_flags(compositor, WL_COMPOSITOR_CREATE_SURFACE,
    @wl_surface_interface, wl_proxy_get_version(compositor), 0, Pointer(nil));
end;

var
  Display    : Pwl_display;
  Registry   : Pwl_proxy;
  Compositor : Pwl_proxy;
  Surface    : Pwl_proxy;
  Listener   : Twl_registry_listener;
  Failures   : Integer = 0;

procedure Check(ACondition: Boolean; const ALabel: string);
begin
  if ACondition then
    WriteLn('  [PASS] ', ALabel)
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(Failures);
  end;
end;

begin
  WriteLn('spike1_wayland — wl_proxy_marshal_flags の varargs 呼び出し検証');
  WriteLn;

  WriteLn('1. ディスプレイ接続');
  Display := wl_display_connect(nil);
  Check(Display <> nil, 'wl_display_connect');
  if Display = nil then
  begin
    WriteLn;
    WriteLn('WAYLAND_DISPLAY が設定された Wayland セッションが必要です。');
    Halt(1);
  end;

  WriteLn;
  WriteLn('2. レジストリ取得 (varargs: NULL 1 個)');
  Registry := DisplayGetRegistry(Display);
  Check(Registry <> nil, 'wl_display_get_registry 相当の marshal_flags');

  WriteLn;
  WriteLn('3. リスナー登録と globals 列挙 (C -> Pascal コールバック)');
  Listener.global := @OnGlobal;
  Listener.global_remove := @OnGlobalRemove;
  Check(wl_proxy_add_listener(Registry, @Listener, nil) = 0, 'wl_proxy_add_listener');

  if wl_display_roundtrip(Display) < 0 then
  begin
    WriteLn('  [FAIL] wl_display_roundtrip');
    Inc(Failures);
  end;
  WriteLn(Format('    ... 他 %d 件 (合計 %d 件)', [GlobalCount - 8, GlobalCount]));
  Check(GlobalCount > 0, Format('globals を %d 件受信 (コールバックが呼ばれた)', [GlobalCount]));

  WriteLn;
  WriteLn('4. wl_compositor を bind (varargs: uint32 + 文字列 + uint32 + NULL)');
  Check(CompositorName <> 0, 'レジストリに wl_compositor がある');
  Compositor := nil;
  if CompositorName <> 0 then
  begin
    Compositor := RegistryBind(Registry, CompositorName, @wl_compositor_interface,
      CompositorVersion);
    Check(Compositor <> nil, 'wl_registry_bind 相当の marshal_flags');
    if Compositor <> nil then
      Check(wl_proxy_get_version(Compositor) = CompositorVersion,
        Format('bind した proxy の version が %d', [CompositorVersion]));
  end;

  WriteLn;
  WriteLn('5. bind した proxy から二段目の marshal (create_surface)');
  Surface := nil;
  if Compositor <> nil then
  begin
    Surface := CompositorCreateSurface(Compositor);
    Check(Surface <> nil, 'wl_compositor_create_surface 相当の marshal_flags');
    Check(wl_display_roundtrip(Display) >= 0,
      'create_surface 後の roundtrip がプロトコルエラーなし');
  end;

  WriteLn;
  WriteLn('6. ブロッカー 2 の下調べ: text-input-v3 の広告状況');
  if HasTextInputV3 then
    WriteLn(Format('  [INFO] zwp_text_input_manager_v3 あり (v%d)', [TextInputV3Version]))
  else
    WriteLn('  [INFO] zwp_text_input_manager_v3 なし');
  if HasXdgWmBase then
    WriteLn('  [INFO] xdg_wm_base あり (ウィンドウ作成が可能)');

  WriteLn;
  WriteLn('7. 後始末');
  if Surface <> nil then
    wl_proxy_marshal_flags(Surface, WL_SURFACE_DESTROY, nil,
      wl_proxy_get_version(Surface), 0);
  if Surface <> nil then wl_proxy_destroy(Surface);
  if Compositor <> nil then wl_proxy_destroy(Compositor);
  wl_proxy_destroy(Registry);
  wl_display_disconnect(Display);
  WriteLn('  [PASS] 解放完了 (クラッシュせず)');

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn('=== 結論: varargs 経路は成立する。プロトコルバインディング生成方式で進めてよい ===');
    Halt(0);
  end
  else
  begin
    WriteLn(Format('=== 失敗 %d 件。varargs 経路の見直しが必要 ===', [Failures]));
    Halt(1);
  end;
end.
