{
  test_platform_libdecor — libdecor の結合と、使うかどうかの判断（PaPiMeLa.Platform.LibDecor / Video.Wayland.LibDecor）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    layout     構造体（libdecor_interface 88 バイト、libdecor_frame_interface 112 バイト）の大きさと
               各欄の位置、列挙の値が、gcc が libdecor.h（0.2.x）で測った値と一致する（値は手で書いた。
               測り直すには libdecor-0-dev を展開して gcc で printf する）
    load       libdecor が開ければ、全部の関数が引け、手放すと全部 nil になる。参照カウントで数える
    decision   ShouldUse（SDL の should_use_libdecor）: xdg-decoration があれば使わない、
               無ければ使う、ヒント PAPIMELA_WAYLAND_PREFER_LIBDECOR が真なら xdg-decoration があっても使う

    libdecor（libdecor-0.so.0）が無い環境では、load と decision は失敗にする。
    飛ばしてよいのは PAPIMELA_LIBDECOR_OPTIONAL=1 のときだけ（空の実装が通らないように）。
}
program test_platform_libdecor;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Core,
  PaPiMeLa.Properties,
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Platform.LibDecor,
  PaPiMeLa.Platform.Wayland.Protocols.XdgDecorationUnstableV1,
  PaPiMeLa.Video.Wayland.Types,
  PaPiMeLa.Video.Wayland.LibDecor;

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
  Result := GetEnvironmentVariable('PAPIMELA_LIBDECOR_OPTIONAL') = '1';
end;

procedure LayoutSection;
var
  I: TLibDecorInterface;
  F: TLibDecorFrameInterface;
begin
  WriteLn('1. 配置（gcc の実測）');
  Check(SizeOf(I) = 88, 'libdecor_interface は 88 バイト');
  Check(PtrUInt(@I.error) - PtrUInt(@I) = 0, 'error は 0');
  Check(SizeOf(F) = 112, 'libdecor_frame_interface は 112 バイト');
  Check((PtrUInt(@F.configure) - PtrUInt(@F) = 0) and (PtrUInt(@F.close) - PtrUInt(@F) = 8)
    and (PtrUInt(@F.commit) - PtrUInt(@F) = 16) and (PtrUInt(@F.dismiss_popup) - PtrUInt(@F) = 24)
    and (PtrUInt(@F.reserved) - PtrUInt(@F) = 32), 'configure / close / commit / dismiss_popup / reserved の位置');
  Check((LIBDECOR_WINDOW_STATE_ACTIVE = 1) and (LIBDECOR_WINDOW_STATE_MAXIMIZED = 2)
    and (LIBDECOR_WINDOW_STATE_FULLSCREEN = 4) and (LIBDECOR_WINDOW_STATE_TILED_LEFT = 8)
    and (LIBDECOR_WINDOW_STATE_TILED_RIGHT = 16) and (LIBDECOR_WINDOW_STATE_TILED_TOP = 32)
    and (LIBDECOR_WINDOW_STATE_TILED_BOTTOM = 64) and (LIBDECOR_WINDOW_STATE_SUSPENDED = 128), '状態の値');
  Check((LIBDECOR_RESIZE_EDGE_NONE = 0) and (LIBDECOR_RESIZE_EDGE_TOP = 1) and (LIBDECOR_RESIZE_EDGE_BOTTOM = 2)
    and (LIBDECOR_RESIZE_EDGE_LEFT = 3) and (LIBDECOR_RESIZE_EDGE_TOP_LEFT = 4)
    and (LIBDECOR_RESIZE_EDGE_BOTTOM_LEFT = 5) and (LIBDECOR_RESIZE_EDGE_RIGHT = 6)
    and (LIBDECOR_RESIZE_EDGE_TOP_RIGHT = 7) and (LIBDECOR_RESIZE_EDGE_BOTTOM_RIGHT = 8), '端の値');
  Check((LIBDECOR_ACTION_MOVE = 1) and (LIBDECOR_ACTION_RESIZE = 2) and (LIBDECOR_ACTION_MINIMIZE = 4)
    and (LIBDECOR_ACTION_FULLSCREEN = 8) and (LIBDECOR_ACTION_CLOSE = 16), '機能の値');
  Check((LIBDECOR_ERROR_COMPOSITOR_INCOMPATIBLE = 0) and (LIBDECOR_ERROR_INVALID_FRAME_CONFIGURATION = 1),
    'エラーの値');
end;

function AllLoaded: Boolean;
begin
  Result := Assigned(libdecor_new) and Assigned(libdecor_unref) and Assigned(libdecor_get_fd)
    and Assigned(libdecor_dispatch) and Assigned(libdecor_decorate) and Assigned(libdecor_frame_unref)
    and Assigned(libdecor_frame_set_visibility) and Assigned(libdecor_frame_is_visible)
    and Assigned(libdecor_frame_set_title) and Assigned(libdecor_frame_set_app_id)
    and Assigned(libdecor_frame_set_capabilities) and Assigned(libdecor_frame_unset_capabilities)
    and Assigned(libdecor_frame_has_capability) and Assigned(libdecor_frame_show_window_menu)
    and Assigned(libdecor_frame_set_min_content_size) and Assigned(libdecor_frame_set_max_content_size)
    and Assigned(libdecor_frame_get_min_content_size) and Assigned(libdecor_frame_resize)
    and Assigned(libdecor_frame_move) and Assigned(libdecor_frame_commit)
    and Assigned(libdecor_frame_set_minimized) and Assigned(libdecor_frame_set_maximized)
    and Assigned(libdecor_frame_unset_maximized) and Assigned(libdecor_frame_set_fullscreen)
    and Assigned(libdecor_frame_unset_fullscreen) and Assigned(libdecor_frame_map)
    and Assigned(libdecor_frame_get_xdg_surface) and Assigned(libdecor_frame_get_xdg_toplevel)
    and Assigned(libdecor_state_new) and Assigned(libdecor_state_free)
    and Assigned(libdecor_configuration_get_content_size) and Assigned(libdecor_configuration_get_window_state);
end;

function NoneLoaded: Boolean;
begin
  Result := not (Assigned(libdecor_new) or Assigned(libdecor_unref) or Assigned(libdecor_dispatch)
    or Assigned(libdecor_decorate) or Assigned(libdecor_frame_commit) or Assigned(libdecor_state_new)
    or Assigned(libdecor_configuration_get_content_size));
end;

function HaveLibrary: Boolean;
begin
  Result := TPMLDynLib.IsAvailable(['libdecor-0.so.0', 'libdecor-0.so']);
  if not Result then
  begin
    if Optional then
      WriteLn('  [SKIP] libdecor-0.so.0 が無い')
    else
      Check(False, 'libdecor-0.so.0 がある（無い環境では PAPIMELA_LIBDECOR_OPTIONAL=1）');
  end;
end;

procedure LoadSection;
begin
  WriteLn('2. 読み込み');
  Check(not PMLLibDecorLoaded and NoneLoaded, '読み込む前は何も引けていない');
  if not HaveLibrary then
    Exit;
  Check(PMLLibDecorAvailable and not PMLLibDecorLoaded, 'PMLLibDecorAvailable は読み込みを残さない');
  Check(PMLLibDecorLoad and PMLLibDecorLoaded and AllLoaded, '読み込むと全部の関数が引ける');
  Check(PMLLibDecorLoad, '2 回目の読み込み（参照カウント）');
  PMLLibDecorUnload;
  Check(PMLLibDecorLoaded and AllLoaded, '1 回手放しても、まだ使える');
  PMLLibDecorUnload;
  Check(not PMLLibDecorLoaded and NoneLoaded, '全部手放すと、全部 nil に戻る');
  PMLLibDecorUnload;
  Check(not PMLLibDecorLoaded, '余分な手放しは無視される');
end;

procedure DecisionSection;
var
  Conn: TPMLWaylandConnection;
  Ctx, CtxPrefer: TPMLContext;
  Opts: TPMLContextOptions;
begin
  WriteLn('3. 使うかどうかの判断（SDL の should_use_libdecor）');
  if not HaveLibrary then
    Exit;
  Conn := TPMLWaylandConnection.Create;
  Ctx := nil;
  CtxPrefer := nil;
  try
    Opts := TPMLContextOptions.Default;
    Ctx := TPMLContext.Create([], Opts);
    Opts := TPMLContextOptions.Default;
    Opts.Hints.Add(PML_HINT_WAYLAND_PREFER_LIBDECOR, '1');
    CtxPrefer := TPMLContext.Create([], Opts);

    Conn.DecorationMgr := nil;
    Check(TPMLWaylandLibDecor.ShouldUse(Ctx, Conn), 'xdg-decoration が無ければ使う');
    Check(TPMLWaylandLibDecor.ShouldUse(nil, Conn), 'Context が無くても、xdg-decoration が無ければ使う');
    Conn.DecorationMgr := Pzxdg_decoration_manager_v1(Pointer(1));
    Check(not TPMLWaylandLibDecor.ShouldUse(Ctx, Conn), 'xdg-decoration があれば使わない（サーバが枠を描く）');
    Check(TPMLWaylandLibDecor.ShouldUse(CtxPrefer, Conn), 'ヒントが真なら、xdg-decoration があっても使う');
    Conn.DecorationMgr := nil;
    Check(TPMLWaylandLibDecor.ShouldUse(CtxPrefer, Conn), 'ヒントが真で、xdg-decoration が無ければ使う');
  finally
    Conn.DecorationMgr := nil;
    CtxPrefer.Free;
    Ctx.Free;
    Conn.Free;
  end;
end;

begin
  WriteLn('test_platform_libdecor');
  LayoutSection;
  LoadSection;
  DecisionSection;
  WriteLn;
  WriteLn('失敗: ', Failures);
  if Failures > 0 then
    Halt(1);
end.
