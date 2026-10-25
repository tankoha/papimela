{
  PaPiMeLa.Platform.LibDecor — libdecor（クライアントサイド装飾）の実行時結合

  Origin : partially ported from SDL (src/video/wayland/SDL_waylandsym.h)
           Scope: libdecor の関数の一覧（SDL の SDL_waylandsym.h の libdecor の節）と引数の型。
           SDL が使わない libdecor_frame_set_parent / popup_grab / popup_ungrab / translate_coordinate /
           get_max_content_size / is_floating / close / ref / get_fd は宣言しない。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §9、§11 #78、#69

  WHAT:
    libdecor.so.0 から、ウィンドウの装飾を作る関数を実行時に取る。コールバックの構造体
    （libdecor_interface / libdecor_frame_interface）と、定数（状態・端・機能）。

  WHY:
    libdecor はリンクしない（§9）。GNOME のように xdg-decoration を持たないコンポジタでだけ要るので、
    無い環境でも papimela は起動できる。

  RESOLVED:
    - 構造体と列挙は libdecor.h（0.2.x）の並びと値のまま。配置は gcc が測った大きさとの往復検査
      （test/test_platform_libdecor.pas）。frame_interface の予約欄は 10 個で、新しい版が使う欄も
      nil のままなら古い版と同じに動く
    - 関数は全部あること（1 つでも無ければ読み込み失敗で、何も残さない）。0.1.2 より前の版は
      libdecor_frame_get_min_content_size が無いので、そのような古い版は使わない
    - C の bool は Boolean（1 バイト）で受ける。返り値は呼ぶ側が下位 1 バイトだけ見る
    - 読み込みは参照カウント。PaPiMeLa.Platform.Wayland.EGL と同じ形。C のプラグイン（GTK など）が
      浮動小数点の例外が無効であることを前提にするので、読み込むスレッドで止める（D-40）

  NOT RESOLVED:
    - bounds（0.3 のトップレベルの最大の大きさ）の通知は受けない（reserved 欄のまま）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.LibDecor;

{$I papimela.inc}

interface

uses
  SysUtils, Math,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  { 不透明型。 }
  Plibdecor               = Pointer;
  Plibdecor_frame         = Pointer;
  Plibdecor_configuration = Pointer;
  Plibdecor_state         = Pointer;

const
  // enum libdecor_error
  LIBDECOR_ERROR_COMPOSITOR_INCOMPATIBLE     = 0;
  LIBDECOR_ERROR_INVALID_FRAME_CONFIGURATION = 1;

  // enum libdecor_window_state
  LIBDECOR_WINDOW_STATE_NONE        = 0;
  LIBDECOR_WINDOW_STATE_ACTIVE      = 1 shl 0;
  LIBDECOR_WINDOW_STATE_MAXIMIZED   = 1 shl 1;
  LIBDECOR_WINDOW_STATE_FULLSCREEN  = 1 shl 2;
  LIBDECOR_WINDOW_STATE_TILED_LEFT  = 1 shl 3;
  LIBDECOR_WINDOW_STATE_TILED_RIGHT = 1 shl 4;
  LIBDECOR_WINDOW_STATE_TILED_TOP   = 1 shl 5;
  LIBDECOR_WINDOW_STATE_TILED_BOTTOM = 1 shl 6;
  LIBDECOR_WINDOW_STATE_SUSPENDED   = 1 shl 7;

  // enum libdecor_resize_edge
  LIBDECOR_RESIZE_EDGE_NONE         = 0;
  LIBDECOR_RESIZE_EDGE_TOP          = 1;
  LIBDECOR_RESIZE_EDGE_BOTTOM       = 2;
  LIBDECOR_RESIZE_EDGE_LEFT         = 3;
  LIBDECOR_RESIZE_EDGE_TOP_LEFT     = 4;
  LIBDECOR_RESIZE_EDGE_BOTTOM_LEFT  = 5;
  LIBDECOR_RESIZE_EDGE_RIGHT        = 6;
  LIBDECOR_RESIZE_EDGE_TOP_RIGHT    = 7;
  LIBDECOR_RESIZE_EDGE_BOTTOM_RIGHT = 8;

  // enum libdecor_capabilities
  LIBDECOR_ACTION_MOVE       = 1 shl 0;
  LIBDECOR_ACTION_RESIZE     = 1 shl 1;
  LIBDECOR_ACTION_MINIMIZE   = 1 shl 2;
  LIBDECOR_ACTION_FULLSCREEN = 1 shl 3;
  LIBDECOR_ACTION_CLOSE      = 1 shl 4;

type
  TLibDecorErrorProc = procedure(AContext: Plibdecor; AError: LongInt; AMessage: PAnsiChar); cdecl;
  TLibDecorConfigureProc = procedure(AFrame: Plibdecor_frame; AConfiguration: Plibdecor_configuration;
    AUserData: Pointer); cdecl;
  TLibDecorCloseProc = procedure(AFrame: Plibdecor_frame; AUserData: Pointer); cdecl;
  TLibDecorCommitProc = procedure(AFrame: Plibdecor_frame; AUserData: Pointer); cdecl;
  TLibDecorDismissPopupProc = procedure(AFrame: Plibdecor_frame; ASeatName: PAnsiChar; AUserData: Pointer); cdecl;

  { struct libdecor_interface。 }
  TLibDecorInterface = record
    error   : TLibDecorErrorProc;
    reserved: array[0..9] of Pointer;
  end;
  PLibDecorInterface = ^TLibDecorInterface;

  { struct libdecor_frame_interface。 }
  TLibDecorFrameInterface = record
    configure    : TLibDecorConfigureProc;
    close        : TLibDecorCloseProc;
    commit       : TLibDecorCommitProc;
    dismiss_popup: TLibDecorDismissPopupProc;
    reserved     : array[0..9] of Pointer;
  end;
  PLibDecorFrameInterface = ^TLibDecorFrameInterface;

var
  libdecor_new: function(ADisplay: Pwl_display; AInterface: PLibDecorInterface): Plibdecor; cdecl = nil;
  libdecor_unref: procedure(AContext: Plibdecor); cdecl = nil;
  libdecor_get_fd: function(AContext: Plibdecor): LongInt; cdecl = nil;
  { ATimeout が 0 なら待たない。-1 なら届くまで待つ。負の値（-1）が返ったら失敗。 }
  libdecor_dispatch: function(AContext: Plibdecor; ATimeout: LongInt): LongInt; cdecl = nil;
  libdecor_decorate: function(AContext: Plibdecor; ASurface: Pwl_surface; AInterface: PLibDecorFrameInterface;
    AUserData: Pointer): Plibdecor_frame; cdecl = nil;
  libdecor_frame_unref: procedure(AFrame: Plibdecor_frame); cdecl = nil;
  libdecor_frame_set_visibility: procedure(AFrame: Plibdecor_frame; AVisible: Boolean); cdecl = nil;
  libdecor_frame_is_visible: function(AFrame: Plibdecor_frame): Boolean; cdecl = nil;
  libdecor_frame_set_title: procedure(AFrame: Plibdecor_frame; ATitle: PAnsiChar); cdecl = nil;
  libdecor_frame_set_app_id: procedure(AFrame: Plibdecor_frame; AAppId: PAnsiChar); cdecl = nil;
  libdecor_frame_set_capabilities: procedure(AFrame: Plibdecor_frame; ACapabilities: LongInt); cdecl = nil;
  libdecor_frame_unset_capabilities: procedure(AFrame: Plibdecor_frame; ACapabilities: LongInt); cdecl = nil;
  libdecor_frame_has_capability: function(AFrame: Plibdecor_frame; ACapability: LongInt): Boolean; cdecl = nil;
  libdecor_frame_show_window_menu: procedure(AFrame: Plibdecor_frame; ASeat: Pwl_seat; ASerial: LongWord;
    AX, AY: LongInt); cdecl = nil;
  libdecor_frame_set_min_content_size: procedure(AFrame: Plibdecor_frame; AWidth, AHeight: LongInt); cdecl = nil;
  libdecor_frame_set_max_content_size: procedure(AFrame: Plibdecor_frame; AWidth, AHeight: LongInt); cdecl = nil;
  libdecor_frame_get_min_content_size: procedure(AFrame: Plibdecor_frame; AWidth, AHeight: PLongInt); cdecl = nil;
  libdecor_frame_resize: procedure(AFrame: Plibdecor_frame; ASeat: Pwl_seat; ASerial: LongWord;
    AEdge: LongInt); cdecl = nil;
  libdecor_frame_move: procedure(AFrame: Plibdecor_frame; ASeat: Pwl_seat; ASerial: LongWord); cdecl = nil;
  libdecor_frame_commit: procedure(AFrame: Plibdecor_frame; AState: Plibdecor_state;
    AConfiguration: Plibdecor_configuration); cdecl = nil;
  libdecor_frame_set_minimized: procedure(AFrame: Plibdecor_frame); cdecl = nil;
  libdecor_frame_set_maximized: procedure(AFrame: Plibdecor_frame); cdecl = nil;
  libdecor_frame_unset_maximized: procedure(AFrame: Plibdecor_frame); cdecl = nil;
  libdecor_frame_set_fullscreen: procedure(AFrame: Plibdecor_frame; AOutput: Pwl_output); cdecl = nil;
  libdecor_frame_unset_fullscreen: procedure(AFrame: Plibdecor_frame); cdecl = nil;
  libdecor_frame_map: procedure(AFrame: Plibdecor_frame); cdecl = nil;
  libdecor_frame_get_xdg_surface: function(AFrame: Plibdecor_frame): Pointer; cdecl = nil;
  libdecor_frame_get_xdg_toplevel: function(AFrame: Plibdecor_frame): Pointer; cdecl = nil;
  libdecor_state_new: function(AWidth, AHeight: LongInt): Plibdecor_state; cdecl = nil;
  libdecor_state_free: procedure(AState: Plibdecor_state); cdecl = nil;
  { 設定が持つ内容の大きさ（装飾を除く）。持っていなければ False。 }
  libdecor_configuration_get_content_size: function(AConfiguration: Plibdecor_configuration;
    AFrame: Plibdecor_frame; AWidth, AHeight: PLongInt): Boolean; cdecl = nil;
  libdecor_configuration_get_window_state: function(AConfiguration: Plibdecor_configuration;
    AState: PLongInt): Boolean; cdecl = nil;

{ libdecor を読み込む。既に読み込んでいれば参照カウントを増やすだけ。
  ライブラリが無いか、関数が 1 つでも無ければ False（何も残さない）。 }
function  PMLLibDecorLoad: Boolean;
procedure PMLLibDecorUnload;
function  PMLLibDecorLoaded: Boolean;
{ ライブラリが開けるか（開いてすぐ閉じる。読み込みは残さない）。 }
function  PMLLibDecorAvailable: Boolean;

implementation

const
  LIBDECOR_NAMES: array[0..1] of String = ('libdecor-0.so.0', 'libdecor-0.so');

var
  GLib: TPMLDynLib = nil;
  GRefCount: Integer = 0;

procedure ClearAll;
begin
  libdecor_new := nil;
  libdecor_unref := nil;
  libdecor_get_fd := nil;
  libdecor_dispatch := nil;
  libdecor_decorate := nil;
  libdecor_frame_unref := nil;
  libdecor_frame_set_visibility := nil;
  libdecor_frame_is_visible := nil;
  libdecor_frame_set_title := nil;
  libdecor_frame_set_app_id := nil;
  libdecor_frame_set_capabilities := nil;
  libdecor_frame_unset_capabilities := nil;
  libdecor_frame_has_capability := nil;
  libdecor_frame_show_window_menu := nil;
  libdecor_frame_set_min_content_size := nil;
  libdecor_frame_set_max_content_size := nil;
  libdecor_frame_get_min_content_size := nil;
  libdecor_frame_resize := nil;
  libdecor_frame_move := nil;
  libdecor_frame_commit := nil;
  libdecor_frame_set_minimized := nil;
  libdecor_frame_set_maximized := nil;
  libdecor_frame_unset_maximized := nil;
  libdecor_frame_set_fullscreen := nil;
  libdecor_frame_unset_fullscreen := nil;
  libdecor_frame_map := nil;
  libdecor_frame_get_xdg_surface := nil;
  libdecor_frame_get_xdg_toplevel := nil;
  libdecor_state_new := nil;
  libdecor_state_free := nil;
  libdecor_configuration_get_content_size := nil;
  libdecor_configuration_get_window_state := nil;
end;

function PMLLibDecorLoad: Boolean;
begin
  if GRefCount > 0 then
  begin
    Inc(GRefCount);
    Exit(True);
  end;
  // プラグイン（GTK など）は浮動小数点の例外が無効であることを前提にしている（D-40）。
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    GLib := TPMLDynLib.Create(LIBDECOR_NAMES);
  except
    on E: EPMLPlatformLibrary do
    begin
      GLib := nil;
      Exit(False);
    end;
  end;
  try
    Pointer(libdecor_new) := GLib.Resolve('libdecor_new');
    Pointer(libdecor_unref) := GLib.Resolve('libdecor_unref');
    Pointer(libdecor_get_fd) := GLib.Resolve('libdecor_get_fd');
    Pointer(libdecor_dispatch) := GLib.Resolve('libdecor_dispatch');
    Pointer(libdecor_decorate) := GLib.Resolve('libdecor_decorate');
    Pointer(libdecor_frame_unref) := GLib.Resolve('libdecor_frame_unref');
    Pointer(libdecor_frame_set_visibility) := GLib.Resolve('libdecor_frame_set_visibility');
    Pointer(libdecor_frame_is_visible) := GLib.Resolve('libdecor_frame_is_visible');
    Pointer(libdecor_frame_set_title) := GLib.Resolve('libdecor_frame_set_title');
    Pointer(libdecor_frame_set_app_id) := GLib.Resolve('libdecor_frame_set_app_id');
    Pointer(libdecor_frame_set_capabilities) := GLib.Resolve('libdecor_frame_set_capabilities');
    Pointer(libdecor_frame_unset_capabilities) := GLib.Resolve('libdecor_frame_unset_capabilities');
    Pointer(libdecor_frame_has_capability) := GLib.Resolve('libdecor_frame_has_capability');
    Pointer(libdecor_frame_show_window_menu) := GLib.Resolve('libdecor_frame_show_window_menu');
    Pointer(libdecor_frame_set_min_content_size) := GLib.Resolve('libdecor_frame_set_min_content_size');
    Pointer(libdecor_frame_set_max_content_size) := GLib.Resolve('libdecor_frame_set_max_content_size');
    Pointer(libdecor_frame_get_min_content_size) := GLib.Resolve('libdecor_frame_get_min_content_size');
    Pointer(libdecor_frame_resize) := GLib.Resolve('libdecor_frame_resize');
    Pointer(libdecor_frame_move) := GLib.Resolve('libdecor_frame_move');
    Pointer(libdecor_frame_commit) := GLib.Resolve('libdecor_frame_commit');
    Pointer(libdecor_frame_set_minimized) := GLib.Resolve('libdecor_frame_set_minimized');
    Pointer(libdecor_frame_set_maximized) := GLib.Resolve('libdecor_frame_set_maximized');
    Pointer(libdecor_frame_unset_maximized) := GLib.Resolve('libdecor_frame_unset_maximized');
    Pointer(libdecor_frame_set_fullscreen) := GLib.Resolve('libdecor_frame_set_fullscreen');
    Pointer(libdecor_frame_unset_fullscreen) := GLib.Resolve('libdecor_frame_unset_fullscreen');
    Pointer(libdecor_frame_map) := GLib.Resolve('libdecor_frame_map');
    Pointer(libdecor_frame_get_xdg_surface) := GLib.Resolve('libdecor_frame_get_xdg_surface');
    Pointer(libdecor_frame_get_xdg_toplevel) := GLib.Resolve('libdecor_frame_get_xdg_toplevel');
    Pointer(libdecor_state_new) := GLib.Resolve('libdecor_state_new');
    Pointer(libdecor_state_free) := GLib.Resolve('libdecor_state_free');
    Pointer(libdecor_configuration_get_content_size) := GLib.Resolve('libdecor_configuration_get_content_size');
    Pointer(libdecor_configuration_get_window_state) := GLib.Resolve('libdecor_configuration_get_window_state');
  except
    on E: EPMLPlatformLibrary do
    begin
      ClearAll;
      FreeAndNil(GLib);
      Exit(False);
    end;
  end;
  GRefCount := 1;
  Result := True;
end;

procedure PMLLibDecorUnload;
begin
  if GRefCount = 0 then
    Exit;
  Dec(GRefCount);
  if GRefCount > 0 then
    Exit;
  ClearAll;
  FreeAndNil(GLib);
end;

function PMLLibDecorLoaded: Boolean;
begin
  Result := GRefCount > 0;
end;

function PMLLibDecorAvailable: Boolean;
begin
  Result := PMLLibDecorLoaded or TPMLDynLib.IsAvailable(LIBDECOR_NAMES);
end;

end.
