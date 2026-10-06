{
  test_protocol_types — 生成したプロトコルの記述子で、新しいオブジェクトを作るイベントの型が埋まっているか

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    tools/wlscan-pas が作った 20 のプロトコル（コアの wl_* を除く）の全インターフェースについて、
    イベントの引数のうち新しいオブジェクトを作るもの（シグネチャの 'n'）の型が nil でないことを見る。

  WHY:
    D-49。生成器が types 配列を、同じプロトコルのインターフェースの記述子を指す前に
    埋めていたので、その欄が nil のまま残っていた。リクエストは呼ぶ側が型を渡すので
    困らないが、イベントで new_id を受けると libwayland が nil を引いて落ちる
    （primary selection の data_offer で初めて踏んだ）。表示サーバ無しで捕まえる。

  実行前提: libwayland-client（記述子を組むのに dlopen する。コンポジタには繋がない）。
            プロトコルを足したら、下の一覧を足すこと。
}
program test_protocol_types;

{$mode objfpc}{$H+}

uses
  SysUtils,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.AlphaModifierV1,
  PaPiMeLa.Platform.Wayland.Protocols.ColorManagementV1,
  PaPiMeLa.Platform.Wayland.Protocols.CursorShapeV1,
  PaPiMeLa.Platform.Wayland.Protocols.FractionalScaleV1,
  PaPiMeLa.Platform.Wayland.Protocols.IdleInhibitUnstableV1,
  PaPiMeLa.Platform.Wayland.Protocols.InputTimestampsUnstableV1,
  PaPiMeLa.Platform.Wayland.Protocols.KeyboardShortcutsInhibitUnstableV1,
  PaPiMeLa.Platform.Wayland.Protocols.PointerConstraintsUnstableV1,
  PaPiMeLa.Platform.Wayland.Protocols.PointerWarpV1,
  PaPiMeLa.Platform.Wayland.Protocols.RelativePointerUnstableV1,
  PaPiMeLa.Platform.Wayland.Protocols.TabletV2,
  PaPiMeLa.Platform.Wayland.Protocols.TextInputUnstableV3,
  PaPiMeLa.Platform.Wayland.Protocols.Viewporter,
  PaPiMeLa.Platform.Wayland.Protocols.WpPrimarySelectionUnstableV1,
  PaPiMeLa.Platform.Wayland.Protocols.XdgActivationV1,
  PaPiMeLa.Platform.Wayland.Protocols.XdgDecorationUnstableV1,
  PaPiMeLa.Platform.Wayland.Protocols.XdgDialogV1,
  PaPiMeLa.Platform.Wayland.Protocols.XdgOutputUnstableV1,
  PaPiMeLa.Platform.Wayland.Protocols.XdgShell,
  PaPiMeLa.Platform.Wayland.Protocols.XdgToplevelIconV1;

var
  Failures, Checked: Integer;

procedure CheckInterface(const AName: String; AIface: Pwl_interface);
var
  I, Slot: Integer;
  M: Pwl_message;
  P: PAnsiChar;
begin
  if AIface = nil then
  begin
    WriteLn('  [FAIL] ', AName, ' が nil');
    Inc(Failures);
    Exit;
  end;
  for I := 0 to AIface^.event_count - 1 do
  begin
    M := @AIface^.events[I];
    Slot := 0;
    P := M^.signature;
    while P^ <> #0 do
    begin
      case P^ of
        '?', '0'..'9': ;   // nullable の印と since の版
      else
        begin
          if P^ = 'n' then
          begin
            Inc(Checked);
            if M^.types[Slot] = nil then
            begin
              WriteLn('  [FAIL] ', AName, '.', M^.name, ' の new_id（', Slot, ' 番目）の型が nil');
              Inc(Failures);
            end;
          end;
          Inc(Slot);
        end;
      end;
      Inc(P);
    end;
  end;
end;

begin
  WriteLn('test_protocol_types — 生成したプロトコルの記述子');
  WriteLn;
  Failures := 0;
  Checked := 0;
  PaPiMeLa.Platform.Wayland.Protocols.AlphaModifierV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.ColorManagementV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.CursorShapeV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.FractionalScaleV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.IdleInhibitUnstableV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.InputTimestampsUnstableV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.KeyboardShortcutsInhibitUnstableV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.PointerConstraintsUnstableV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.PointerWarpV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.RelativePointerUnstableV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.TabletV2.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.TextInputUnstableV3.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.Viewporter.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.WpPrimarySelectionUnstableV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.XdgActivationV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.XdgDecorationUnstableV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.XdgDialogV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.XdgOutputUnstableV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.XdgShell.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.XdgToplevelIconV1.EnsureProtocolInitialized;
  CheckInterface('wp_cursor_shape_manager_v1_interface', wp_cursor_shape_manager_v1_interface);
  CheckInterface('wp_cursor_shape_device_v1_interface', wp_cursor_shape_device_v1_interface);
  CheckInterface('wp_alpha_modifier_v1_interface', wp_alpha_modifier_v1_interface);
  CheckInterface('wp_alpha_modifier_surface_v1_interface', wp_alpha_modifier_surface_v1_interface);
  CheckInterface('wp_fractional_scale_manager_v1_interface', wp_fractional_scale_manager_v1_interface);
  CheckInterface('wp_fractional_scale_v1_interface', wp_fractional_scale_v1_interface);
  CheckInterface('wp_color_manager_v1_interface', wp_color_manager_v1_interface);
  CheckInterface('wp_color_management_output_v1_interface', wp_color_management_output_v1_interface);
  CheckInterface('wp_color_management_surface_v1_interface', wp_color_management_surface_v1_interface);
  CheckInterface('wp_color_management_surface_feedback_v1_interface', wp_color_management_surface_feedback_v1_interface);
  CheckInterface('wp_image_description_creator_icc_v1_interface', wp_image_description_creator_icc_v1_interface);
  CheckInterface('wp_image_description_creator_params_v1_interface', wp_image_description_creator_params_v1_interface);
  CheckInterface('wp_image_description_v1_interface', wp_image_description_v1_interface);
  CheckInterface('wp_image_description_info_v1_interface', wp_image_description_info_v1_interface);
  CheckInterface('wp_image_description_reference_v1_interface', wp_image_description_reference_v1_interface);
  CheckInterface('wp_viewporter_interface', wp_viewporter_interface);
  CheckInterface('wp_viewport_interface', wp_viewport_interface);
  CheckInterface('xdg_activation_v1_interface', xdg_activation_v1_interface);
  CheckInterface('xdg_activation_token_v1_interface', xdg_activation_token_v1_interface);
  CheckInterface('zxdg_decoration_manager_v1_interface', zxdg_decoration_manager_v1_interface);
  CheckInterface('zxdg_toplevel_decoration_v1_interface', zxdg_toplevel_decoration_v1_interface);
  CheckInterface('zwp_primary_selection_device_manager_v1_interface', zwp_primary_selection_device_manager_v1_interface);
  CheckInterface('zwp_primary_selection_device_v1_interface', zwp_primary_selection_device_v1_interface);
  CheckInterface('zwp_primary_selection_offer_v1_interface', zwp_primary_selection_offer_v1_interface);
  CheckInterface('zwp_primary_selection_source_v1_interface', zwp_primary_selection_source_v1_interface);
  CheckInterface('zwp_idle_inhibit_manager_v1_interface', zwp_idle_inhibit_manager_v1_interface);
  CheckInterface('zwp_idle_inhibitor_v1_interface', zwp_idle_inhibitor_v1_interface);
  CheckInterface('zwp_input_timestamps_manager_v1_interface', zwp_input_timestamps_manager_v1_interface);
  CheckInterface('zwp_input_timestamps_v1_interface', zwp_input_timestamps_v1_interface);
  CheckInterface('zwp_keyboard_shortcuts_inhibit_manager_v1_interface', zwp_keyboard_shortcuts_inhibit_manager_v1_interface);
  CheckInterface('zwp_keyboard_shortcuts_inhibitor_v1_interface', zwp_keyboard_shortcuts_inhibitor_v1_interface);
  CheckInterface('zwp_pointer_constraints_v1_interface', zwp_pointer_constraints_v1_interface);
  CheckInterface('zwp_locked_pointer_v1_interface', zwp_locked_pointer_v1_interface);
  CheckInterface('zwp_confined_pointer_v1_interface', zwp_confined_pointer_v1_interface);
  CheckInterface('xdg_wm_dialog_v1_interface', xdg_wm_dialog_v1_interface);
  CheckInterface('xdg_dialog_v1_interface', xdg_dialog_v1_interface);
  CheckInterface('zwp_relative_pointer_manager_v1_interface', zwp_relative_pointer_manager_v1_interface);
  CheckInterface('zwp_relative_pointer_v1_interface', zwp_relative_pointer_v1_interface);
  CheckInterface('wp_pointer_warp_v1_interface', wp_pointer_warp_v1_interface);
  CheckInterface('xdg_wm_base_interface', xdg_wm_base_interface);
  CheckInterface('xdg_positioner_interface', xdg_positioner_interface);
  CheckInterface('xdg_surface_interface', xdg_surface_interface);
  CheckInterface('xdg_toplevel_interface', xdg_toplevel_interface);
  CheckInterface('xdg_popup_interface', xdg_popup_interface);
  CheckInterface('xdg_toplevel_icon_manager_v1_interface', xdg_toplevel_icon_manager_v1_interface);
  CheckInterface('xdg_toplevel_icon_v1_interface', xdg_toplevel_icon_v1_interface);
  CheckInterface('zwp_tablet_manager_v2_interface', zwp_tablet_manager_v2_interface);
  CheckInterface('zwp_tablet_seat_v2_interface', zwp_tablet_seat_v2_interface);
  CheckInterface('zwp_tablet_tool_v2_interface', zwp_tablet_tool_v2_interface);
  CheckInterface('zwp_tablet_v2_interface', zwp_tablet_v2_interface);
  CheckInterface('zwp_tablet_pad_ring_v2_interface', zwp_tablet_pad_ring_v2_interface);
  CheckInterface('zwp_tablet_pad_strip_v2_interface', zwp_tablet_pad_strip_v2_interface);
  CheckInterface('zwp_tablet_pad_group_v2_interface', zwp_tablet_pad_group_v2_interface);
  CheckInterface('zwp_tablet_pad_v2_interface', zwp_tablet_pad_v2_interface);
  CheckInterface('zwp_text_input_v3_interface', zwp_text_input_v3_interface);
  CheckInterface('zwp_text_input_manager_v3_interface', zwp_text_input_manager_v3_interface);
  CheckInterface('zxdg_output_manager_v1_interface', zxdg_output_manager_v1_interface);
  CheckInterface('zxdg_output_v1_interface', zxdg_output_v1_interface);
  if Checked = 0 then
  begin
    WriteLn('  [FAIL] new_id のイベントが 1 つも無い（検査が何も見ていない）');
    Inc(Failures);
  end
  else if Failures = 0 then
    WriteLn('  [PASS] ', Checked, ' 個のイベントの new_id の型が埋まっている');
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: 生成したプロトコルの new_id を受けるイベントは全部型を持つ ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
