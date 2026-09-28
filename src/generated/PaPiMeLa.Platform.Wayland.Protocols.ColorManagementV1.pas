{
  PaPiMeLa.Platform.Wayland.Protocols.ColorManagementV1

  自動生成ファイル。手で編集しないこと。
  生成元: color_management_v1.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright 2019 Sebastian Wick
      Copyright 2019 Erwin Burema
      Copyright 2020 AMD
      Copyright 2020-2024 Collabora, Ltd.
      Copyright 2024 Xaver Hugl
      Copyright 2022-2025 Red Hat, Inc.
  
      Permission is hereby granted, free of charge, to any person obtaining a
      copy of this software and associated documentation files (the "Software"),
      to deal in the Software without restriction, including without limitation
      the rights to use, copy, modify, merge, publish, distribute, sublicense,
      and/or sell copies of the Software, and to permit persons to whom the
      Software is furnished to do so, subject to the following conditions:
  
      The above copyright notice and this permission notice (including the next
      paragraph) shall be included in all copies or substantial portions of the
      Software.
  
      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
      IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
      FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
      THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
      LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
      FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
      DEALINGS IN THE SOFTWARE.

}
unit PaPiMeLa.Platform.Wayland.Protocols.ColorManagementV1;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  Twp_color_manager_v1_opaque = record end;
  Pwp_color_manager_v1 = ^Twp_color_manager_v1_opaque;
  Twp_color_management_output_v1_opaque = record end;
  Pwp_color_management_output_v1 = ^Twp_color_management_output_v1_opaque;
  Twp_color_management_surface_v1_opaque = record end;
  Pwp_color_management_surface_v1 = ^Twp_color_management_surface_v1_opaque;
  Twp_color_management_surface_feedback_v1_opaque = record end;
  Pwp_color_management_surface_feedback_v1 = ^Twp_color_management_surface_feedback_v1_opaque;
  Twp_image_description_creator_icc_v1_opaque = record end;
  Pwp_image_description_creator_icc_v1 = ^Twp_image_description_creator_icc_v1_opaque;
  Twp_image_description_creator_params_v1_opaque = record end;
  Pwp_image_description_creator_params_v1 = ^Twp_image_description_creator_params_v1_opaque;
  Twp_image_description_v1_opaque = record end;
  Pwp_image_description_v1 = ^Twp_image_description_v1_opaque;
  Twp_image_description_info_v1_opaque = record end;
  Pwp_image_description_info_v1 = ^Twp_image_description_info_v1_opaque;
  Twp_image_description_reference_v1_opaque = record end;
  Pwp_image_description_reference_v1 = ^Twp_image_description_reference_v1_opaque;

const
  // wp_color_manager_v1 (version 2)
  WP_COLOR_MANAGER_V1_DESTROY_OPCODE = 0;
  WP_COLOR_MANAGER_V1_GET_OUTPUT_OPCODE = 1;
  WP_COLOR_MANAGER_V1_GET_SURFACE_OPCODE = 2;
  WP_COLOR_MANAGER_V1_GET_SURFACE_FEEDBACK_OPCODE = 3;
  WP_COLOR_MANAGER_V1_CREATE_ICC_CREATOR_OPCODE = 4;
  WP_COLOR_MANAGER_V1_CREATE_PARAMETRIC_CREATOR_OPCODE = 5;
  WP_COLOR_MANAGER_V1_CREATE_WINDOWS_SCRGB_OPCODE = 6;
  WP_COLOR_MANAGER_V1_GET_IMAGE_DESCRIPTION_OPCODE = 7;
  WP_COLOR_MANAGER_V1_DESTROY_SINCE_VERSION = 1;
  WP_COLOR_MANAGER_V1_GET_OUTPUT_SINCE_VERSION = 1;
  WP_COLOR_MANAGER_V1_GET_SURFACE_SINCE_VERSION = 1;
  WP_COLOR_MANAGER_V1_GET_SURFACE_FEEDBACK_SINCE_VERSION = 1;
  WP_COLOR_MANAGER_V1_CREATE_ICC_CREATOR_SINCE_VERSION = 1;
  WP_COLOR_MANAGER_V1_CREATE_PARAMETRIC_CREATOR_SINCE_VERSION = 1;
  WP_COLOR_MANAGER_V1_CREATE_WINDOWS_SCRGB_SINCE_VERSION = 1;
  WP_COLOR_MANAGER_V1_GET_IMAGE_DESCRIPTION_SINCE_VERSION = 2;
  WP_COLOR_MANAGER_V1_SUPPORTED_INTENT_SINCE_VERSION = 1;
  WP_COLOR_MANAGER_V1_SUPPORTED_FEATURE_SINCE_VERSION = 1;
  WP_COLOR_MANAGER_V1_SUPPORTED_TF_NAMED_SINCE_VERSION = 1;
  WP_COLOR_MANAGER_V1_SUPPORTED_PRIMARIES_NAMED_SINCE_VERSION = 1;
  WP_COLOR_MANAGER_V1_DONE_SINCE_VERSION = 1;
  WP_COLOR_MANAGER_V1_ERROR_UNSUPPORTED_FEATURE = 0;
  WP_COLOR_MANAGER_V1_ERROR_SURFACE_EXISTS = 1;
  WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL = 0;
  WP_COLOR_MANAGER_V1_RENDER_INTENT_RELATIVE = 1;
  WP_COLOR_MANAGER_V1_RENDER_INTENT_SATURATION = 2;
  WP_COLOR_MANAGER_V1_RENDER_INTENT_ABSOLUTE = 3;
  WP_COLOR_MANAGER_V1_RENDER_INTENT_RELATIVE_BPC = 4;
  WP_COLOR_MANAGER_V1_RENDER_INTENT_ABSOLUTE_NO_ADAPTATION = 5;
  WP_COLOR_MANAGER_V1_FEATURE_ICC_V2_V4 = 0;
  WP_COLOR_MANAGER_V1_FEATURE_PARAMETRIC = 1;
  WP_COLOR_MANAGER_V1_FEATURE_SET_PRIMARIES = 2;
  WP_COLOR_MANAGER_V1_FEATURE_SET_TF_POWER = 3;
  WP_COLOR_MANAGER_V1_FEATURE_SET_LUMINANCES = 4;
  WP_COLOR_MANAGER_V1_FEATURE_SET_MASTERING_DISPLAY_PRIMARIES = 5;
  WP_COLOR_MANAGER_V1_FEATURE_EXTENDED_TARGET_VOLUME = 6;
  WP_COLOR_MANAGER_V1_FEATURE_WINDOWS_SCRGB = 7;
  WP_COLOR_MANAGER_V1_PRIMARIES_SRGB = 1;
  WP_COLOR_MANAGER_V1_PRIMARIES_PAL_M = 2;
  WP_COLOR_MANAGER_V1_PRIMARIES_PAL = 3;
  WP_COLOR_MANAGER_V1_PRIMARIES_NTSC = 4;
  WP_COLOR_MANAGER_V1_PRIMARIES_GENERIC_FILM = 5;
  WP_COLOR_MANAGER_V1_PRIMARIES_BT2020 = 6;
  WP_COLOR_MANAGER_V1_PRIMARIES_CIE1931_XYZ = 7;
  WP_COLOR_MANAGER_V1_PRIMARIES_DCI_P3 = 8;
  WP_COLOR_MANAGER_V1_PRIMARIES_DISPLAY_P3 = 9;
  WP_COLOR_MANAGER_V1_PRIMARIES_ADOBE_RGB = 10;
  WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_BT1886 = 1;
  WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_GAMMA22 = 2;
  WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_GAMMA28 = 3;
  WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST240 = 4;
  WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_EXT_LINEAR = 5;
  WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_LOG_100 = 6;
  WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_LOG_316 = 7;
  WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_XVYCC = 8;
  WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_SRGB = 9;
  WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_EXT_SRGB = 10;
  WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ = 11;
  WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST428 = 12;
  WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_HLG = 13;
  WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_COMPOUND_POWER_2_4 = 14;

  // wp_color_management_output_v1 (version 2)
  WP_COLOR_MANAGEMENT_OUTPUT_V1_DESTROY_OPCODE = 0;
  WP_COLOR_MANAGEMENT_OUTPUT_V1_GET_IMAGE_DESCRIPTION_OPCODE = 1;
  WP_COLOR_MANAGEMENT_OUTPUT_V1_DESTROY_SINCE_VERSION = 1;
  WP_COLOR_MANAGEMENT_OUTPUT_V1_GET_IMAGE_DESCRIPTION_SINCE_VERSION = 1;
  WP_COLOR_MANAGEMENT_OUTPUT_V1_IMAGE_DESCRIPTION_CHANGED_SINCE_VERSION = 1;

  // wp_color_management_surface_v1 (version 2)
  WP_COLOR_MANAGEMENT_SURFACE_V1_DESTROY_OPCODE = 0;
  WP_COLOR_MANAGEMENT_SURFACE_V1_SET_IMAGE_DESCRIPTION_OPCODE = 1;
  WP_COLOR_MANAGEMENT_SURFACE_V1_UNSET_IMAGE_DESCRIPTION_OPCODE = 2;
  WP_COLOR_MANAGEMENT_SURFACE_V1_DESTROY_SINCE_VERSION = 1;
  WP_COLOR_MANAGEMENT_SURFACE_V1_SET_IMAGE_DESCRIPTION_SINCE_VERSION = 1;
  WP_COLOR_MANAGEMENT_SURFACE_V1_UNSET_IMAGE_DESCRIPTION_SINCE_VERSION = 1;
  WP_COLOR_MANAGEMENT_SURFACE_V1_ERROR_RENDER_INTENT = 0;
  WP_COLOR_MANAGEMENT_SURFACE_V1_ERROR_IMAGE_DESCRIPTION = 1;
  WP_COLOR_MANAGEMENT_SURFACE_V1_ERROR_INERT = 2;

  // wp_color_management_surface_feedback_v1 (version 2)
  WP_COLOR_MANAGEMENT_SURFACE_FEEDBACK_V1_DESTROY_OPCODE = 0;
  WP_COLOR_MANAGEMENT_SURFACE_FEEDBACK_V1_GET_PREFERRED_OPCODE = 1;
  WP_COLOR_MANAGEMENT_SURFACE_FEEDBACK_V1_GET_PREFERRED_PARAMETRIC_OPCODE = 2;
  WP_COLOR_MANAGEMENT_SURFACE_FEEDBACK_V1_DESTROY_SINCE_VERSION = 1;
  WP_COLOR_MANAGEMENT_SURFACE_FEEDBACK_V1_GET_PREFERRED_SINCE_VERSION = 1;
  WP_COLOR_MANAGEMENT_SURFACE_FEEDBACK_V1_GET_PREFERRED_PARAMETRIC_SINCE_VERSION = 1;
  WP_COLOR_MANAGEMENT_SURFACE_FEEDBACK_V1_PREFERRED_CHANGED_SINCE_VERSION = 1;
  WP_COLOR_MANAGEMENT_SURFACE_FEEDBACK_V1_PREFERRED_CHANGED2_SINCE_VERSION = 2;
  WP_COLOR_MANAGEMENT_SURFACE_FEEDBACK_V1_ERROR_INERT = 0;
  WP_COLOR_MANAGEMENT_SURFACE_FEEDBACK_V1_ERROR_UNSUPPORTED_FEATURE = 1;

  // wp_image_description_creator_icc_v1 (version 2)
  WP_IMAGE_DESCRIPTION_CREATOR_ICC_V1_CREATE_OPCODE = 0;
  WP_IMAGE_DESCRIPTION_CREATOR_ICC_V1_SET_ICC_FILE_OPCODE = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_ICC_V1_CREATE_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_ICC_V1_SET_ICC_FILE_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_ICC_V1_ERROR_INCOMPLETE_SET = 0;
  WP_IMAGE_DESCRIPTION_CREATOR_ICC_V1_ERROR_ALREADY_SET = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_ICC_V1_ERROR_BAD_FD = 2;
  WP_IMAGE_DESCRIPTION_CREATOR_ICC_V1_ERROR_BAD_SIZE = 3;
  WP_IMAGE_DESCRIPTION_CREATOR_ICC_V1_ERROR_OUT_OF_FILE = 4;

  // wp_image_description_creator_params_v1 (version 2)
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_CREATE_OPCODE = 0;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_TF_NAMED_OPCODE = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_TF_POWER_OPCODE = 2;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_PRIMARIES_NAMED_OPCODE = 3;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_PRIMARIES_OPCODE = 4;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_LUMINANCES_OPCODE = 5;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_MASTERING_DISPLAY_PRIMARIES_OPCODE = 6;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_MASTERING_LUMINANCE_OPCODE = 7;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_MAX_CLL_OPCODE = 8;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_MAX_FALL_OPCODE = 9;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_CREATE_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_TF_NAMED_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_TF_POWER_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_PRIMARIES_NAMED_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_PRIMARIES_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_LUMINANCES_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_MASTERING_DISPLAY_PRIMARIES_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_MASTERING_LUMINANCE_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_MAX_CLL_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_MAX_FALL_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_ERROR_INCOMPLETE_SET = 0;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_ERROR_ALREADY_SET = 1;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_ERROR_UNSUPPORTED_FEATURE = 2;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_ERROR_INVALID_TF = 3;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_ERROR_INVALID_PRIMARIES_NAMED = 4;
  WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_ERROR_INVALID_LUMINANCE = 5;

  // wp_image_description_v1 (version 2)
  WP_IMAGE_DESCRIPTION_V1_DESTROY_OPCODE = 0;
  WP_IMAGE_DESCRIPTION_V1_GET_INFORMATION_OPCODE = 1;
  WP_IMAGE_DESCRIPTION_V1_DESTROY_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_V1_GET_INFORMATION_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_V1_FAILED_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_V1_READY_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_V1_READY2_SINCE_VERSION = 2;
  WP_IMAGE_DESCRIPTION_V1_ERROR_NOT_READY = 0;
  WP_IMAGE_DESCRIPTION_V1_ERROR_NO_INFORMATION = 1;
  WP_IMAGE_DESCRIPTION_V1_CAUSE_LOW_VERSION = 0;
  WP_IMAGE_DESCRIPTION_V1_CAUSE_UNSUPPORTED = 1;
  WP_IMAGE_DESCRIPTION_V1_CAUSE_OPERATING_SYSTEM = 2;
  WP_IMAGE_DESCRIPTION_V1_CAUSE_NO_OUTPUT = 3;

  // wp_image_description_info_v1 (version 2)
  WP_IMAGE_DESCRIPTION_INFO_V1_DONE_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_INFO_V1_ICC_FILE_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_INFO_V1_PRIMARIES_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_INFO_V1_PRIMARIES_NAMED_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_INFO_V1_TF_POWER_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_INFO_V1_TF_NAMED_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_INFO_V1_LUMINANCES_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_INFO_V1_TARGET_PRIMARIES_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_INFO_V1_TARGET_LUMINANCE_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_INFO_V1_TARGET_MAX_CLL_SINCE_VERSION = 1;
  WP_IMAGE_DESCRIPTION_INFO_V1_TARGET_MAX_FALL_SINCE_VERSION = 1;

  // wp_image_description_reference_v1 (version 1)
  WP_IMAGE_DESCRIPTION_REFERENCE_V1_DESTROY_OPCODE = 0;
  WP_IMAGE_DESCRIPTION_REFERENCE_V1_DESTROY_SINCE_VERSION = 1;

var
  wp_color_manager_v1_interface: Pwl_interface = nil;
  wp_color_management_output_v1_interface: Pwl_interface = nil;
  wp_color_management_surface_v1_interface: Pwl_interface = nil;
  wp_color_management_surface_feedback_v1_interface: Pwl_interface = nil;
  wp_image_description_creator_icc_v1_interface: Pwl_interface = nil;
  wp_image_description_creator_params_v1_interface: Pwl_interface = nil;
  wp_image_description_v1_interface: Pwl_interface = nil;
  wp_image_description_info_v1_interface: Pwl_interface = nil;
  wp_image_description_reference_v1_interface: Pwl_interface = nil;

type
  Twp_color_manager_v1_listener = class abstract(TObject)
  public
    procedure supported_intent(AProxy: Pwp_color_manager_v1; render_intent: LongWord); virtual;
    procedure supported_feature(AProxy: Pwp_color_manager_v1; feature: LongWord); virtual;
    procedure supported_tf_named(AProxy: Pwp_color_manager_v1; tf: LongWord); virtual;
    procedure supported_primaries_named(AProxy: Pwp_color_manager_v1; primaries: LongWord); virtual;
    procedure done(AProxy: Pwp_color_manager_v1); virtual;
  end;

  Twp_color_manager_v1_listener_rec = record
    supported_intent: procedure(data: Pointer; AProxy: Pwp_color_manager_v1; render_intent: LongWord); cdecl;
    supported_feature: procedure(data: Pointer; AProxy: Pwp_color_manager_v1; feature: LongWord); cdecl;
    supported_tf_named: procedure(data: Pointer; AProxy: Pwp_color_manager_v1; tf: LongWord); cdecl;
    supported_primaries_named: procedure(data: Pointer; AProxy: Pwp_color_manager_v1; primaries: LongWord); cdecl;
    done: procedure(data: Pointer; AProxy: Pwp_color_manager_v1); cdecl;
  end;

  Twp_color_management_output_v1_listener = class abstract(TObject)
  public
    procedure image_description_changed(AProxy: Pwp_color_management_output_v1); virtual;
  end;

  Twp_color_management_output_v1_listener_rec = record
    image_description_changed: procedure(data: Pointer; AProxy: Pwp_color_management_output_v1); cdecl;
  end;

  Twp_color_management_surface_feedback_v1_listener = class abstract(TObject)
  public
    procedure preferred_changed(AProxy: Pwp_color_management_surface_feedback_v1; identity: LongWord); virtual;
    procedure preferred_changed2(AProxy: Pwp_color_management_surface_feedback_v1; identity_hi: LongWord; identity_lo: LongWord); virtual;
  end;

  Twp_color_management_surface_feedback_v1_listener_rec = record
    preferred_changed: procedure(data: Pointer; AProxy: Pwp_color_management_surface_feedback_v1; identity: LongWord); cdecl;
    preferred_changed2: procedure(data: Pointer; AProxy: Pwp_color_management_surface_feedback_v1; identity_hi: LongWord; identity_lo: LongWord); cdecl;
  end;

  Twp_image_description_v1_listener = class abstract(TObject)
  public
    procedure failed(AProxy: Pwp_image_description_v1; cause: LongWord; msg: PAnsiChar); virtual;
    procedure ready(AProxy: Pwp_image_description_v1; identity: LongWord); virtual;
    procedure ready2(AProxy: Pwp_image_description_v1; identity_hi: LongWord; identity_lo: LongWord); virtual;
  end;

  Twp_image_description_v1_listener_rec = record
    failed: procedure(data: Pointer; AProxy: Pwp_image_description_v1; cause: LongWord; msg: PAnsiChar); cdecl;
    ready: procedure(data: Pointer; AProxy: Pwp_image_description_v1; identity: LongWord); cdecl;
    ready2: procedure(data: Pointer; AProxy: Pwp_image_description_v1; identity_hi: LongWord; identity_lo: LongWord); cdecl;
  end;

  Twp_image_description_info_v1_listener = class abstract(TObject)
  public
    procedure done(AProxy: Pwp_image_description_info_v1); virtual;
    procedure icc_file(AProxy: Pwp_image_description_info_v1; icc: LongInt; icc_size: LongWord); virtual;
    procedure primaries(AProxy: Pwp_image_description_info_v1; r_x: LongInt; r_y: LongInt; g_x: LongInt; g_y: LongInt; b_x: LongInt; b_y: LongInt; w_x: LongInt; w_y: LongInt); virtual;
    procedure primaries_named(AProxy: Pwp_image_description_info_v1; primaries_: LongWord); virtual;
    procedure tf_power(AProxy: Pwp_image_description_info_v1; eexp: LongWord); virtual;
    procedure tf_named(AProxy: Pwp_image_description_info_v1; tf: LongWord); virtual;
    procedure luminances(AProxy: Pwp_image_description_info_v1; min_lum: LongWord; max_lum: LongWord; reference_lum: LongWord); virtual;
    procedure target_primaries(AProxy: Pwp_image_description_info_v1; r_x: LongInt; r_y: LongInt; g_x: LongInt; g_y: LongInt; b_x: LongInt; b_y: LongInt; w_x: LongInt; w_y: LongInt); virtual;
    procedure target_luminance(AProxy: Pwp_image_description_info_v1; min_lum: LongWord; max_lum: LongWord); virtual;
    procedure target_max_cll(AProxy: Pwp_image_description_info_v1; max_cll: LongWord); virtual;
    procedure target_max_fall(AProxy: Pwp_image_description_info_v1; max_fall: LongWord); virtual;
  end;

  Twp_image_description_info_v1_listener_rec = record
    done: procedure(data: Pointer; AProxy: Pwp_image_description_info_v1); cdecl;
    icc_file: procedure(data: Pointer; AProxy: Pwp_image_description_info_v1; icc: LongInt; icc_size: LongWord); cdecl;
    primaries: procedure(data: Pointer; AProxy: Pwp_image_description_info_v1; r_x: LongInt; r_y: LongInt; g_x: LongInt; g_y: LongInt; b_x: LongInt; b_y: LongInt; w_x: LongInt; w_y: LongInt); cdecl;
    primaries_named: procedure(data: Pointer; AProxy: Pwp_image_description_info_v1; primaries_: LongWord); cdecl;
    tf_power: procedure(data: Pointer; AProxy: Pwp_image_description_info_v1; eexp: LongWord); cdecl;
    tf_named: procedure(data: Pointer; AProxy: Pwp_image_description_info_v1; tf: LongWord); cdecl;
    luminances: procedure(data: Pointer; AProxy: Pwp_image_description_info_v1; min_lum: LongWord; max_lum: LongWord; reference_lum: LongWord); cdecl;
    target_primaries: procedure(data: Pointer; AProxy: Pwp_image_description_info_v1; r_x: LongInt; r_y: LongInt; g_x: LongInt; g_y: LongInt; b_x: LongInt; b_y: LongInt; w_x: LongInt; w_y: LongInt); cdecl;
    target_luminance: procedure(data: Pointer; AProxy: Pwp_image_description_info_v1; min_lum: LongWord; max_lum: LongWord); cdecl;
    target_max_cll: procedure(data: Pointer; AProxy: Pwp_image_description_info_v1; max_cll: LongWord); cdecl;
    target_max_fall: procedure(data: Pointer; AProxy: Pwp_image_description_info_v1; max_fall: LongWord); cdecl;
  end;

function wp_color_manager_v1_add_listener_object(AProxy: Pwp_color_manager_v1; AListener: Twp_color_manager_v1_listener): LongInt;
procedure wp_color_manager_v1_destroy(AProxy: Pwp_color_manager_v1);
function wp_color_manager_v1_get_output(AProxy: Pwp_color_manager_v1; output: Pwl_output): Pwp_color_management_output_v1;
function wp_color_manager_v1_get_surface(AProxy: Pwp_color_manager_v1; surface: Pwl_surface): Pwp_color_management_surface_v1;
function wp_color_manager_v1_get_surface_feedback(AProxy: Pwp_color_manager_v1; surface: Pwl_surface): Pwp_color_management_surface_feedback_v1;
function wp_color_manager_v1_create_icc_creator(AProxy: Pwp_color_manager_v1): Pwp_image_description_creator_icc_v1;
function wp_color_manager_v1_create_parametric_creator(AProxy: Pwp_color_manager_v1): Pwp_image_description_creator_params_v1;
function wp_color_manager_v1_create_windows_scrgb(AProxy: Pwp_color_manager_v1): Pwp_image_description_v1;
function wp_color_manager_v1_get_image_description(AProxy: Pwp_color_manager_v1; reference: Pwp_image_description_reference_v1): Pwp_image_description_v1;

function wp_color_management_output_v1_add_listener_object(AProxy: Pwp_color_management_output_v1; AListener: Twp_color_management_output_v1_listener): LongInt;
procedure wp_color_management_output_v1_destroy(AProxy: Pwp_color_management_output_v1);
function wp_color_management_output_v1_get_image_description(AProxy: Pwp_color_management_output_v1): Pwp_image_description_v1;

procedure wp_color_management_surface_v1_destroy(AProxy: Pwp_color_management_surface_v1);
procedure wp_color_management_surface_v1_set_image_description(AProxy: Pwp_color_management_surface_v1; image_description: Pwp_image_description_v1; render_intent: LongWord);
procedure wp_color_management_surface_v1_unset_image_description(AProxy: Pwp_color_management_surface_v1);

function wp_color_management_surface_feedback_v1_add_listener_object(AProxy: Pwp_color_management_surface_feedback_v1; AListener: Twp_color_management_surface_feedback_v1_listener): LongInt;
procedure wp_color_management_surface_feedback_v1_destroy(AProxy: Pwp_color_management_surface_feedback_v1);
function wp_color_management_surface_feedback_v1_get_preferred(AProxy: Pwp_color_management_surface_feedback_v1): Pwp_image_description_v1;
function wp_color_management_surface_feedback_v1_get_preferred_parametric(AProxy: Pwp_color_management_surface_feedback_v1): Pwp_image_description_v1;

function wp_image_description_creator_icc_v1_create(AProxy: Pwp_image_description_creator_icc_v1): Pwp_image_description_v1;
procedure wp_image_description_creator_icc_v1_set_icc_file(AProxy: Pwp_image_description_creator_icc_v1; icc_profile: LongInt; offset: LongWord; length: LongWord);

function wp_image_description_creator_params_v1_create(AProxy: Pwp_image_description_creator_params_v1): Pwp_image_description_v1;
procedure wp_image_description_creator_params_v1_set_tf_named(AProxy: Pwp_image_description_creator_params_v1; tf: LongWord);
procedure wp_image_description_creator_params_v1_set_tf_power(AProxy: Pwp_image_description_creator_params_v1; eexp: LongWord);
procedure wp_image_description_creator_params_v1_set_primaries_named(AProxy: Pwp_image_description_creator_params_v1; primaries: LongWord);
procedure wp_image_description_creator_params_v1_set_primaries(AProxy: Pwp_image_description_creator_params_v1; r_x: LongInt; r_y: LongInt; g_x: LongInt; g_y: LongInt; b_x: LongInt; b_y: LongInt; w_x: LongInt; w_y: LongInt);
procedure wp_image_description_creator_params_v1_set_luminances(AProxy: Pwp_image_description_creator_params_v1; min_lum: LongWord; max_lum: LongWord; reference_lum: LongWord);
procedure wp_image_description_creator_params_v1_set_mastering_display_primaries(AProxy: Pwp_image_description_creator_params_v1; r_x: LongInt; r_y: LongInt; g_x: LongInt; g_y: LongInt; b_x: LongInt; b_y: LongInt; w_x: LongInt; w_y: LongInt);
procedure wp_image_description_creator_params_v1_set_mastering_luminance(AProxy: Pwp_image_description_creator_params_v1; min_lum: LongWord; max_lum: LongWord);
procedure wp_image_description_creator_params_v1_set_max_cll(AProxy: Pwp_image_description_creator_params_v1; max_cll: LongWord);
procedure wp_image_description_creator_params_v1_set_max_fall(AProxy: Pwp_image_description_creator_params_v1; max_fall: LongWord);

function wp_image_description_v1_add_listener_object(AProxy: Pwp_image_description_v1; AListener: Twp_image_description_v1_listener): LongInt;
procedure wp_image_description_v1_destroy(AProxy: Pwp_image_description_v1);
function wp_image_description_v1_get_information(AProxy: Pwp_image_description_v1): Pwp_image_description_info_v1;

function wp_image_description_info_v1_add_listener_object(AProxy: Pwp_image_description_info_v1; AListener: Twp_image_description_info_v1_listener): LongInt;
procedure wp_image_description_reference_v1_destroy(AProxy: Pwp_image_description_reference_v1);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GTypes: array[0..26] of Pwl_interface;
  GReq_wp_color_manager_v1: array[0..7] of Twl_message;
  GEvt_wp_color_manager_v1: array[0..4] of Twl_message;
  GIface_wp_color_manager_v1: Twl_interface;
  GReq_wp_color_management_output_v1: array[0..1] of Twl_message;
  GEvt_wp_color_management_output_v1: array[0..0] of Twl_message;
  GIface_wp_color_management_output_v1: Twl_interface;
  GReq_wp_color_management_surface_v1: array[0..2] of Twl_message;
  GIface_wp_color_management_surface_v1: Twl_interface;
  GReq_wp_color_management_surface_feedback_v1: array[0..2] of Twl_message;
  GEvt_wp_color_management_surface_feedback_v1: array[0..1] of Twl_message;
  GIface_wp_color_management_surface_feedback_v1: Twl_interface;
  GReq_wp_image_description_creator_icc_v1: array[0..1] of Twl_message;
  GIface_wp_image_description_creator_icc_v1: Twl_interface;
  GReq_wp_image_description_creator_params_v1: array[0..9] of Twl_message;
  GIface_wp_image_description_creator_params_v1: Twl_interface;
  GReq_wp_image_description_v1: array[0..1] of Twl_message;
  GEvt_wp_image_description_v1: array[0..2] of Twl_message;
  GIface_wp_image_description_v1: Twl_interface;
  GEvt_wp_image_description_info_v1: array[0..10] of Twl_message;
  GIface_wp_image_description_info_v1: Twl_interface;
  GReq_wp_image_description_reference_v1: array[0..0] of Twl_message;
  GIface_wp_image_description_reference_v1: Twl_interface;

var
  GInitialized: Boolean = False;
  GThunks_wp_color_manager_v1: Twp_color_manager_v1_listener_rec;
  GThunks_wp_color_management_output_v1: Twp_color_management_output_v1_listener_rec;
  GThunks_wp_color_management_surface_feedback_v1: Twp_color_management_surface_feedback_v1_listener_rec;
  GThunks_wp_image_description_v1: Twp_image_description_v1_listener_rec;
  GThunks_wp_image_description_info_v1: Twp_image_description_info_v1_listener_rec;

procedure Twp_color_manager_v1_listener.supported_intent(AProxy: Pwp_color_manager_v1; render_intent: LongWord);
begin
end;

procedure Twp_color_manager_v1_listener.supported_feature(AProxy: Pwp_color_manager_v1; feature: LongWord);
begin
end;

procedure Twp_color_manager_v1_listener.supported_tf_named(AProxy: Pwp_color_manager_v1; tf: LongWord);
begin
end;

procedure Twp_color_manager_v1_listener.supported_primaries_named(AProxy: Pwp_color_manager_v1; primaries: LongWord);
begin
end;

procedure Twp_color_manager_v1_listener.done(AProxy: Pwp_color_manager_v1);
begin
end;

procedure Twp_color_management_output_v1_listener.image_description_changed(AProxy: Pwp_color_management_output_v1);
begin
end;

procedure Twp_color_management_surface_feedback_v1_listener.preferred_changed(AProxy: Pwp_color_management_surface_feedback_v1; identity: LongWord);
begin
end;

procedure Twp_color_management_surface_feedback_v1_listener.preferred_changed2(AProxy: Pwp_color_management_surface_feedback_v1; identity_hi: LongWord; identity_lo: LongWord);
begin
end;

procedure Twp_image_description_v1_listener.failed(AProxy: Pwp_image_description_v1; cause: LongWord; msg: PAnsiChar);
begin
end;

procedure Twp_image_description_v1_listener.ready(AProxy: Pwp_image_description_v1; identity: LongWord);
begin
end;

procedure Twp_image_description_v1_listener.ready2(AProxy: Pwp_image_description_v1; identity_hi: LongWord; identity_lo: LongWord);
begin
end;

procedure Twp_image_description_info_v1_listener.done(AProxy: Pwp_image_description_info_v1);
begin
end;

procedure Twp_image_description_info_v1_listener.icc_file(AProxy: Pwp_image_description_info_v1; icc: LongInt; icc_size: LongWord);
begin
end;

procedure Twp_image_description_info_v1_listener.primaries(AProxy: Pwp_image_description_info_v1; r_x: LongInt; r_y: LongInt; g_x: LongInt; g_y: LongInt; b_x: LongInt; b_y: LongInt; w_x: LongInt; w_y: LongInt);
begin
end;

procedure Twp_image_description_info_v1_listener.primaries_named(AProxy: Pwp_image_description_info_v1; primaries_: LongWord);
begin
end;

procedure Twp_image_description_info_v1_listener.tf_power(AProxy: Pwp_image_description_info_v1; eexp: LongWord);
begin
end;

procedure Twp_image_description_info_v1_listener.tf_named(AProxy: Pwp_image_description_info_v1; tf: LongWord);
begin
end;

procedure Twp_image_description_info_v1_listener.luminances(AProxy: Pwp_image_description_info_v1; min_lum: LongWord; max_lum: LongWord; reference_lum: LongWord);
begin
end;

procedure Twp_image_description_info_v1_listener.target_primaries(AProxy: Pwp_image_description_info_v1; r_x: LongInt; r_y: LongInt; g_x: LongInt; g_y: LongInt; b_x: LongInt; b_y: LongInt; w_x: LongInt; w_y: LongInt);
begin
end;

procedure Twp_image_description_info_v1_listener.target_luminance(AProxy: Pwp_image_description_info_v1; min_lum: LongWord; max_lum: LongWord);
begin
end;

procedure Twp_image_description_info_v1_listener.target_max_cll(AProxy: Pwp_image_description_info_v1; max_cll: LongWord);
begin
end;

procedure Twp_image_description_info_v1_listener.target_max_fall(AProxy: Pwp_image_description_info_v1; max_fall: LongWord);
begin
end;

procedure Thunk_wp_color_manager_v1_supported_intent(data: Pointer; AProxy: Pwp_color_manager_v1; render_intent: LongWord); cdecl;
begin
  if data <> nil then
    Twp_color_manager_v1_listener(data).supported_intent(AProxy, render_intent);
end;

procedure Thunk_wp_color_manager_v1_supported_feature(data: Pointer; AProxy: Pwp_color_manager_v1; feature: LongWord); cdecl;
begin
  if data <> nil then
    Twp_color_manager_v1_listener(data).supported_feature(AProxy, feature);
end;

procedure Thunk_wp_color_manager_v1_supported_tf_named(data: Pointer; AProxy: Pwp_color_manager_v1; tf: LongWord); cdecl;
begin
  if data <> nil then
    Twp_color_manager_v1_listener(data).supported_tf_named(AProxy, tf);
end;

procedure Thunk_wp_color_manager_v1_supported_primaries_named(data: Pointer; AProxy: Pwp_color_manager_v1; primaries: LongWord); cdecl;
begin
  if data <> nil then
    Twp_color_manager_v1_listener(data).supported_primaries_named(AProxy, primaries);
end;

procedure Thunk_wp_color_manager_v1_done(data: Pointer; AProxy: Pwp_color_manager_v1); cdecl;
begin
  if data <> nil then
    Twp_color_manager_v1_listener(data).done(AProxy);
end;

procedure Thunk_wp_color_management_output_v1_image_description_changed(data: Pointer; AProxy: Pwp_color_management_output_v1); cdecl;
begin
  if data <> nil then
    Twp_color_management_output_v1_listener(data).image_description_changed(AProxy);
end;

procedure Thunk_wp_color_management_surface_feedback_v1_preferred_changed(data: Pointer; AProxy: Pwp_color_management_surface_feedback_v1; identity: LongWord); cdecl;
begin
  if data <> nil then
    Twp_color_management_surface_feedback_v1_listener(data).preferred_changed(AProxy, identity);
end;

procedure Thunk_wp_color_management_surface_feedback_v1_preferred_changed2(data: Pointer; AProxy: Pwp_color_management_surface_feedback_v1; identity_hi: LongWord; identity_lo: LongWord); cdecl;
begin
  if data <> nil then
    Twp_color_management_surface_feedback_v1_listener(data).preferred_changed2(AProxy, identity_hi, identity_lo);
end;

procedure Thunk_wp_image_description_v1_failed(data: Pointer; AProxy: Pwp_image_description_v1; cause: LongWord; msg: PAnsiChar); cdecl;
begin
  if data <> nil then
    Twp_image_description_v1_listener(data).failed(AProxy, cause, msg);
end;

procedure Thunk_wp_image_description_v1_ready(data: Pointer; AProxy: Pwp_image_description_v1; identity: LongWord); cdecl;
begin
  if data <> nil then
    Twp_image_description_v1_listener(data).ready(AProxy, identity);
end;

procedure Thunk_wp_image_description_v1_ready2(data: Pointer; AProxy: Pwp_image_description_v1; identity_hi: LongWord; identity_lo: LongWord); cdecl;
begin
  if data <> nil then
    Twp_image_description_v1_listener(data).ready2(AProxy, identity_hi, identity_lo);
end;

procedure Thunk_wp_image_description_info_v1_done(data: Pointer; AProxy: Pwp_image_description_info_v1); cdecl;
begin
  if data <> nil then
    Twp_image_description_info_v1_listener(data).done(AProxy);
end;

procedure Thunk_wp_image_description_info_v1_icc_file(data: Pointer; AProxy: Pwp_image_description_info_v1; icc: LongInt; icc_size: LongWord); cdecl;
begin
  if data <> nil then
    Twp_image_description_info_v1_listener(data).icc_file(AProxy, icc, icc_size);
end;

procedure Thunk_wp_image_description_info_v1_primaries(data: Pointer; AProxy: Pwp_image_description_info_v1; r_x: LongInt; r_y: LongInt; g_x: LongInt; g_y: LongInt; b_x: LongInt; b_y: LongInt; w_x: LongInt; w_y: LongInt); cdecl;
begin
  if data <> nil then
    Twp_image_description_info_v1_listener(data).primaries(AProxy, r_x, r_y, g_x, g_y, b_x, b_y, w_x, w_y);
end;

procedure Thunk_wp_image_description_info_v1_primaries_named(data: Pointer; AProxy: Pwp_image_description_info_v1; primaries_: LongWord); cdecl;
begin
  if data <> nil then
    Twp_image_description_info_v1_listener(data).primaries_named(AProxy, primaries_);
end;

procedure Thunk_wp_image_description_info_v1_tf_power(data: Pointer; AProxy: Pwp_image_description_info_v1; eexp: LongWord); cdecl;
begin
  if data <> nil then
    Twp_image_description_info_v1_listener(data).tf_power(AProxy, eexp);
end;

procedure Thunk_wp_image_description_info_v1_tf_named(data: Pointer; AProxy: Pwp_image_description_info_v1; tf: LongWord); cdecl;
begin
  if data <> nil then
    Twp_image_description_info_v1_listener(data).tf_named(AProxy, tf);
end;

procedure Thunk_wp_image_description_info_v1_luminances(data: Pointer; AProxy: Pwp_image_description_info_v1; min_lum: LongWord; max_lum: LongWord; reference_lum: LongWord); cdecl;
begin
  if data <> nil then
    Twp_image_description_info_v1_listener(data).luminances(AProxy, min_lum, max_lum, reference_lum);
end;

procedure Thunk_wp_image_description_info_v1_target_primaries(data: Pointer; AProxy: Pwp_image_description_info_v1; r_x: LongInt; r_y: LongInt; g_x: LongInt; g_y: LongInt; b_x: LongInt; b_y: LongInt; w_x: LongInt; w_y: LongInt); cdecl;
begin
  if data <> nil then
    Twp_image_description_info_v1_listener(data).target_primaries(AProxy, r_x, r_y, g_x, g_y, b_x, b_y, w_x, w_y);
end;

procedure Thunk_wp_image_description_info_v1_target_luminance(data: Pointer; AProxy: Pwp_image_description_info_v1; min_lum: LongWord; max_lum: LongWord); cdecl;
begin
  if data <> nil then
    Twp_image_description_info_v1_listener(data).target_luminance(AProxy, min_lum, max_lum);
end;

procedure Thunk_wp_image_description_info_v1_target_max_cll(data: Pointer; AProxy: Pwp_image_description_info_v1; max_cll: LongWord); cdecl;
begin
  if data <> nil then
    Twp_image_description_info_v1_listener(data).target_max_cll(AProxy, max_cll);
end;

procedure Thunk_wp_image_description_info_v1_target_max_fall(data: Pointer; AProxy: Pwp_image_description_info_v1; max_fall: LongWord); cdecl;
begin
  if data <> nil then
    Twp_image_description_info_v1_listener(data).target_max_fall(AProxy, max_fall);
end;

function wp_color_manager_v1_add_listener_object(AProxy: Pwp_color_manager_v1; AListener: Twp_color_manager_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wp_color_manager_v1, AListener);
end;

function wp_color_management_output_v1_add_listener_object(AProxy: Pwp_color_management_output_v1; AListener: Twp_color_management_output_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wp_color_management_output_v1, AListener);
end;

function wp_color_management_surface_feedback_v1_add_listener_object(AProxy: Pwp_color_management_surface_feedback_v1; AListener: Twp_color_management_surface_feedback_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wp_color_management_surface_feedback_v1, AListener);
end;

function wp_image_description_v1_add_listener_object(AProxy: Pwp_image_description_v1; AListener: Twp_image_description_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wp_image_description_v1, AListener);
end;

function wp_image_description_info_v1_add_listener_object(AProxy: Pwp_image_description_info_v1; AListener: Twp_image_description_info_v1_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wp_image_description_info_v1, AListener);
end;

procedure wp_color_manager_v1_destroy(AProxy: Pwp_color_manager_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGER_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function wp_color_manager_v1_get_output(AProxy: Pwp_color_manager_v1; output: Pwl_output): Pwp_color_management_output_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_color_management_output_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGER_V1_GET_OUTPUT_OPCODE, wp_color_management_output_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), output));
end;

function wp_color_manager_v1_get_surface(AProxy: Pwp_color_manager_v1; surface: Pwl_surface): Pwp_color_management_surface_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_color_management_surface_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGER_V1_GET_SURFACE_OPCODE, wp_color_management_surface_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), surface));
end;

function wp_color_manager_v1_get_surface_feedback(AProxy: Pwp_color_manager_v1; surface: Pwl_surface): Pwp_color_management_surface_feedback_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_color_management_surface_feedback_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGER_V1_GET_SURFACE_FEEDBACK_OPCODE, wp_color_management_surface_feedback_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), surface));
end;

function wp_color_manager_v1_create_icc_creator(AProxy: Pwp_color_manager_v1): Pwp_image_description_creator_icc_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_image_description_creator_icc_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGER_V1_CREATE_ICC_CREATOR_OPCODE, wp_image_description_creator_icc_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function wp_color_manager_v1_create_parametric_creator(AProxy: Pwp_color_manager_v1): Pwp_image_description_creator_params_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_image_description_creator_params_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGER_V1_CREATE_PARAMETRIC_CREATOR_OPCODE, wp_image_description_creator_params_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function wp_color_manager_v1_create_windows_scrgb(AProxy: Pwp_color_manager_v1): Pwp_image_description_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_image_description_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGER_V1_CREATE_WINDOWS_SCRGB_OPCODE, wp_image_description_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function wp_color_manager_v1_get_image_description(AProxy: Pwp_color_manager_v1; reference: Pwp_image_description_reference_v1): Pwp_image_description_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_image_description_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGER_V1_GET_IMAGE_DESCRIPTION_OPCODE, wp_image_description_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), reference));
end;

procedure wp_color_management_output_v1_destroy(AProxy: Pwp_color_management_output_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGEMENT_OUTPUT_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function wp_color_management_output_v1_get_image_description(AProxy: Pwp_color_management_output_v1): Pwp_image_description_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_image_description_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGEMENT_OUTPUT_V1_GET_IMAGE_DESCRIPTION_OPCODE, wp_image_description_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

procedure wp_color_management_surface_v1_destroy(AProxy: Pwp_color_management_surface_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGEMENT_SURFACE_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wp_color_management_surface_v1_set_image_description(AProxy: Pwp_color_management_surface_v1; image_description: Pwp_image_description_v1; render_intent: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGEMENT_SURFACE_V1_SET_IMAGE_DESCRIPTION_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, image_description, render_intent);
end;

procedure wp_color_management_surface_v1_unset_image_description(AProxy: Pwp_color_management_surface_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGEMENT_SURFACE_V1_UNSET_IMAGE_DESCRIPTION_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure wp_color_management_surface_feedback_v1_destroy(AProxy: Pwp_color_management_surface_feedback_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGEMENT_SURFACE_FEEDBACK_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function wp_color_management_surface_feedback_v1_get_preferred(AProxy: Pwp_color_management_surface_feedback_v1): Pwp_image_description_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_image_description_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGEMENT_SURFACE_FEEDBACK_V1_GET_PREFERRED_OPCODE, wp_image_description_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function wp_color_management_surface_feedback_v1_get_preferred_parametric(AProxy: Pwp_color_management_surface_feedback_v1): Pwp_image_description_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_image_description_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_COLOR_MANAGEMENT_SURFACE_FEEDBACK_V1_GET_PREFERRED_PARAMETRIC_OPCODE, wp_image_description_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function wp_image_description_creator_icc_v1_create(AProxy: Pwp_image_description_creator_icc_v1): Pwp_image_description_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_image_description_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_CREATOR_ICC_V1_CREATE_OPCODE, wp_image_description_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY, Pointer(nil)));
end;

procedure wp_image_description_creator_icc_v1_set_icc_file(AProxy: Pwp_image_description_creator_icc_v1; icc_profile: LongInt; offset: LongWord; length: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_CREATOR_ICC_V1_SET_ICC_FILE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, icc_profile, offset, length);
end;

function wp_image_description_creator_params_v1_create(AProxy: Pwp_image_description_creator_params_v1): Pwp_image_description_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_image_description_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_CREATE_OPCODE, wp_image_description_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY, Pointer(nil)));
end;

procedure wp_image_description_creator_params_v1_set_tf_named(AProxy: Pwp_image_description_creator_params_v1; tf: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_TF_NAMED_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, tf);
end;

procedure wp_image_description_creator_params_v1_set_tf_power(AProxy: Pwp_image_description_creator_params_v1; eexp: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_TF_POWER_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, eexp);
end;

procedure wp_image_description_creator_params_v1_set_primaries_named(AProxy: Pwp_image_description_creator_params_v1; primaries: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_PRIMARIES_NAMED_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, primaries);
end;

procedure wp_image_description_creator_params_v1_set_primaries(AProxy: Pwp_image_description_creator_params_v1; r_x: LongInt; r_y: LongInt; g_x: LongInt; g_y: LongInt; b_x: LongInt; b_y: LongInt; w_x: LongInt; w_y: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_PRIMARIES_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, r_x, r_y, g_x, g_y, b_x, b_y, w_x, w_y);
end;

procedure wp_image_description_creator_params_v1_set_luminances(AProxy: Pwp_image_description_creator_params_v1; min_lum: LongWord; max_lum: LongWord; reference_lum: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_LUMINANCES_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, min_lum, max_lum, reference_lum);
end;

procedure wp_image_description_creator_params_v1_set_mastering_display_primaries(AProxy: Pwp_image_description_creator_params_v1; r_x: LongInt; r_y: LongInt; g_x: LongInt; g_y: LongInt; b_x: LongInt; b_y: LongInt; w_x: LongInt; w_y: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_MASTERING_DISPLAY_PRIMARIES_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, r_x, r_y, g_x, g_y, b_x, b_y, w_x, w_y);
end;

procedure wp_image_description_creator_params_v1_set_mastering_luminance(AProxy: Pwp_image_description_creator_params_v1; min_lum: LongWord; max_lum: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_MASTERING_LUMINANCE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, min_lum, max_lum);
end;

procedure wp_image_description_creator_params_v1_set_max_cll(AProxy: Pwp_image_description_creator_params_v1; max_cll: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_MAX_CLL_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, max_cll);
end;

procedure wp_image_description_creator_params_v1_set_max_fall(AProxy: Pwp_image_description_creator_params_v1; max_fall: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_SET_MAX_FALL_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, max_fall);
end;

procedure wp_image_description_v1_destroy(AProxy: Pwp_image_description_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function wp_image_description_v1_get_information(AProxy: Pwp_image_description_v1): Pwp_image_description_info_v1;
begin
  EnsureProtocolInitialized;
  Result := Pwp_image_description_info_v1(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_V1_GET_INFORMATION_OPCODE, wp_image_description_info_v1_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

procedure wp_image_description_reference_v1_destroy(AProxy: Pwp_image_description_reference_v1);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WP_IMAGE_DESCRIPTION_REFERENCE_V1_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;
  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;

  FillChar(GTypes, SizeOf(GTypes), 0);
  GTypes[8] := wp_color_management_output_v1_interface;
  GTypes[9] := wl_output_interface;
  GTypes[10] := wp_color_management_surface_v1_interface;
  GTypes[11] := wl_surface_interface;
  GTypes[12] := wp_color_management_surface_feedback_v1_interface;
  GTypes[13] := wl_surface_interface;
  GTypes[14] := wp_image_description_creator_icc_v1_interface;
  GTypes[15] := wp_image_description_creator_params_v1_interface;
  GTypes[16] := wp_image_description_v1_interface;
  GTypes[17] := wp_image_description_v1_interface;
  GTypes[18] := wp_image_description_reference_v1_interface;
  GTypes[19] := wp_image_description_v1_interface;
  GTypes[20] := wp_image_description_v1_interface;
  GTypes[22] := wp_image_description_v1_interface;
  GTypes[23] := wp_image_description_v1_interface;
  GTypes[24] := wp_image_description_v1_interface;
  GTypes[25] := wp_image_description_v1_interface;
  GTypes[26] := wp_image_description_info_v1_interface;

  GReq_wp_color_manager_v1[0].name := 'destroy';
  GReq_wp_color_manager_v1[0].signature := '';
  GReq_wp_color_manager_v1[0].types := @GTypes[0];
  GReq_wp_color_manager_v1[1].name := 'get_output';
  GReq_wp_color_manager_v1[1].signature := 'no';
  GReq_wp_color_manager_v1[1].types := @GTypes[8];
  GReq_wp_color_manager_v1[2].name := 'get_surface';
  GReq_wp_color_manager_v1[2].signature := 'no';
  GReq_wp_color_manager_v1[2].types := @GTypes[10];
  GReq_wp_color_manager_v1[3].name := 'get_surface_feedback';
  GReq_wp_color_manager_v1[3].signature := 'no';
  GReq_wp_color_manager_v1[3].types := @GTypes[12];
  GReq_wp_color_manager_v1[4].name := 'create_icc_creator';
  GReq_wp_color_manager_v1[4].signature := 'n';
  GReq_wp_color_manager_v1[4].types := @GTypes[14];
  GReq_wp_color_manager_v1[5].name := 'create_parametric_creator';
  GReq_wp_color_manager_v1[5].signature := 'n';
  GReq_wp_color_manager_v1[5].types := @GTypes[15];
  GReq_wp_color_manager_v1[6].name := 'create_windows_scrgb';
  GReq_wp_color_manager_v1[6].signature := 'n';
  GReq_wp_color_manager_v1[6].types := @GTypes[16];
  GReq_wp_color_manager_v1[7].name := 'get_image_description';
  GReq_wp_color_manager_v1[7].signature := '2no';
  GReq_wp_color_manager_v1[7].types := @GTypes[17];
  GEvt_wp_color_manager_v1[0].name := 'supported_intent';
  GEvt_wp_color_manager_v1[0].signature := 'u';
  GEvt_wp_color_manager_v1[0].types := @GTypes[0];
  GEvt_wp_color_manager_v1[1].name := 'supported_feature';
  GEvt_wp_color_manager_v1[1].signature := 'u';
  GEvt_wp_color_manager_v1[1].types := @GTypes[0];
  GEvt_wp_color_manager_v1[2].name := 'supported_tf_named';
  GEvt_wp_color_manager_v1[2].signature := 'u';
  GEvt_wp_color_manager_v1[2].types := @GTypes[0];
  GEvt_wp_color_manager_v1[3].name := 'supported_primaries_named';
  GEvt_wp_color_manager_v1[3].signature := 'u';
  GEvt_wp_color_manager_v1[3].types := @GTypes[0];
  GEvt_wp_color_manager_v1[4].name := 'done';
  GEvt_wp_color_manager_v1[4].signature := '';
  GEvt_wp_color_manager_v1[4].types := @GTypes[0];
  GIface_wp_color_manager_v1.name := 'wp_color_manager_v1';
  GIface_wp_color_manager_v1.version := 2;
  GIface_wp_color_manager_v1.method_count := 8;
  GIface_wp_color_manager_v1.methods := @GReq_wp_color_manager_v1[0];
  GIface_wp_color_manager_v1.event_count := 5;
  GIface_wp_color_manager_v1.events := @GEvt_wp_color_manager_v1[0];
  wp_color_manager_v1_interface := @GIface_wp_color_manager_v1;

  GReq_wp_color_management_output_v1[0].name := 'destroy';
  GReq_wp_color_management_output_v1[0].signature := '';
  GReq_wp_color_management_output_v1[0].types := @GTypes[0];
  GReq_wp_color_management_output_v1[1].name := 'get_image_description';
  GReq_wp_color_management_output_v1[1].signature := 'n';
  GReq_wp_color_management_output_v1[1].types := @GTypes[19];
  GEvt_wp_color_management_output_v1[0].name := 'image_description_changed';
  GEvt_wp_color_management_output_v1[0].signature := '';
  GEvt_wp_color_management_output_v1[0].types := @GTypes[0];
  GIface_wp_color_management_output_v1.name := 'wp_color_management_output_v1';
  GIface_wp_color_management_output_v1.version := 2;
  GIface_wp_color_management_output_v1.method_count := 2;
  GIface_wp_color_management_output_v1.methods := @GReq_wp_color_management_output_v1[0];
  GIface_wp_color_management_output_v1.event_count := 1;
  GIface_wp_color_management_output_v1.events := @GEvt_wp_color_management_output_v1[0];
  wp_color_management_output_v1_interface := @GIface_wp_color_management_output_v1;

  GReq_wp_color_management_surface_v1[0].name := 'destroy';
  GReq_wp_color_management_surface_v1[0].signature := '';
  GReq_wp_color_management_surface_v1[0].types := @GTypes[0];
  GReq_wp_color_management_surface_v1[1].name := 'set_image_description';
  GReq_wp_color_management_surface_v1[1].signature := 'ou';
  GReq_wp_color_management_surface_v1[1].types := @GTypes[20];
  GReq_wp_color_management_surface_v1[2].name := 'unset_image_description';
  GReq_wp_color_management_surface_v1[2].signature := '';
  GReq_wp_color_management_surface_v1[2].types := @GTypes[0];
  GIface_wp_color_management_surface_v1.name := 'wp_color_management_surface_v1';
  GIface_wp_color_management_surface_v1.version := 2;
  GIface_wp_color_management_surface_v1.method_count := 3;
  GIface_wp_color_management_surface_v1.methods := @GReq_wp_color_management_surface_v1[0];
  GIface_wp_color_management_surface_v1.event_count := 0;
  GIface_wp_color_management_surface_v1.events := nil;
  wp_color_management_surface_v1_interface := @GIface_wp_color_management_surface_v1;

  GReq_wp_color_management_surface_feedback_v1[0].name := 'destroy';
  GReq_wp_color_management_surface_feedback_v1[0].signature := '';
  GReq_wp_color_management_surface_feedback_v1[0].types := @GTypes[0];
  GReq_wp_color_management_surface_feedback_v1[1].name := 'get_preferred';
  GReq_wp_color_management_surface_feedback_v1[1].signature := 'n';
  GReq_wp_color_management_surface_feedback_v1[1].types := @GTypes[22];
  GReq_wp_color_management_surface_feedback_v1[2].name := 'get_preferred_parametric';
  GReq_wp_color_management_surface_feedback_v1[2].signature := 'n';
  GReq_wp_color_management_surface_feedback_v1[2].types := @GTypes[23];
  GEvt_wp_color_management_surface_feedback_v1[0].name := 'preferred_changed';
  GEvt_wp_color_management_surface_feedback_v1[0].signature := 'u';
  GEvt_wp_color_management_surface_feedback_v1[0].types := @GTypes[0];
  GEvt_wp_color_management_surface_feedback_v1[1].name := 'preferred_changed2';
  GEvt_wp_color_management_surface_feedback_v1[1].signature := '2uu';
  GEvt_wp_color_management_surface_feedback_v1[1].types := @GTypes[0];
  GIface_wp_color_management_surface_feedback_v1.name := 'wp_color_management_surface_feedback_v1';
  GIface_wp_color_management_surface_feedback_v1.version := 2;
  GIface_wp_color_management_surface_feedback_v1.method_count := 3;
  GIface_wp_color_management_surface_feedback_v1.methods := @GReq_wp_color_management_surface_feedback_v1[0];
  GIface_wp_color_management_surface_feedback_v1.event_count := 2;
  GIface_wp_color_management_surface_feedback_v1.events := @GEvt_wp_color_management_surface_feedback_v1[0];
  wp_color_management_surface_feedback_v1_interface := @GIface_wp_color_management_surface_feedback_v1;

  GReq_wp_image_description_creator_icc_v1[0].name := 'create';
  GReq_wp_image_description_creator_icc_v1[0].signature := 'n';
  GReq_wp_image_description_creator_icc_v1[0].types := @GTypes[24];
  GReq_wp_image_description_creator_icc_v1[1].name := 'set_icc_file';
  GReq_wp_image_description_creator_icc_v1[1].signature := 'huu';
  GReq_wp_image_description_creator_icc_v1[1].types := @GTypes[0];
  GIface_wp_image_description_creator_icc_v1.name := 'wp_image_description_creator_icc_v1';
  GIface_wp_image_description_creator_icc_v1.version := 2;
  GIface_wp_image_description_creator_icc_v1.method_count := 2;
  GIface_wp_image_description_creator_icc_v1.methods := @GReq_wp_image_description_creator_icc_v1[0];
  GIface_wp_image_description_creator_icc_v1.event_count := 0;
  GIface_wp_image_description_creator_icc_v1.events := nil;
  wp_image_description_creator_icc_v1_interface := @GIface_wp_image_description_creator_icc_v1;

  GReq_wp_image_description_creator_params_v1[0].name := 'create';
  GReq_wp_image_description_creator_params_v1[0].signature := 'n';
  GReq_wp_image_description_creator_params_v1[0].types := @GTypes[25];
  GReq_wp_image_description_creator_params_v1[1].name := 'set_tf_named';
  GReq_wp_image_description_creator_params_v1[1].signature := 'u';
  GReq_wp_image_description_creator_params_v1[1].types := @GTypes[0];
  GReq_wp_image_description_creator_params_v1[2].name := 'set_tf_power';
  GReq_wp_image_description_creator_params_v1[2].signature := 'u';
  GReq_wp_image_description_creator_params_v1[2].types := @GTypes[0];
  GReq_wp_image_description_creator_params_v1[3].name := 'set_primaries_named';
  GReq_wp_image_description_creator_params_v1[3].signature := 'u';
  GReq_wp_image_description_creator_params_v1[3].types := @GTypes[0];
  GReq_wp_image_description_creator_params_v1[4].name := 'set_primaries';
  GReq_wp_image_description_creator_params_v1[4].signature := 'iiiiiiii';
  GReq_wp_image_description_creator_params_v1[4].types := @GTypes[0];
  GReq_wp_image_description_creator_params_v1[5].name := 'set_luminances';
  GReq_wp_image_description_creator_params_v1[5].signature := 'uuu';
  GReq_wp_image_description_creator_params_v1[5].types := @GTypes[0];
  GReq_wp_image_description_creator_params_v1[6].name := 'set_mastering_display_primaries';
  GReq_wp_image_description_creator_params_v1[6].signature := 'iiiiiiii';
  GReq_wp_image_description_creator_params_v1[6].types := @GTypes[0];
  GReq_wp_image_description_creator_params_v1[7].name := 'set_mastering_luminance';
  GReq_wp_image_description_creator_params_v1[7].signature := 'uu';
  GReq_wp_image_description_creator_params_v1[7].types := @GTypes[0];
  GReq_wp_image_description_creator_params_v1[8].name := 'set_max_cll';
  GReq_wp_image_description_creator_params_v1[8].signature := 'u';
  GReq_wp_image_description_creator_params_v1[8].types := @GTypes[0];
  GReq_wp_image_description_creator_params_v1[9].name := 'set_max_fall';
  GReq_wp_image_description_creator_params_v1[9].signature := 'u';
  GReq_wp_image_description_creator_params_v1[9].types := @GTypes[0];
  GIface_wp_image_description_creator_params_v1.name := 'wp_image_description_creator_params_v1';
  GIface_wp_image_description_creator_params_v1.version := 2;
  GIface_wp_image_description_creator_params_v1.method_count := 10;
  GIface_wp_image_description_creator_params_v1.methods := @GReq_wp_image_description_creator_params_v1[0];
  GIface_wp_image_description_creator_params_v1.event_count := 0;
  GIface_wp_image_description_creator_params_v1.events := nil;
  wp_image_description_creator_params_v1_interface := @GIface_wp_image_description_creator_params_v1;

  GReq_wp_image_description_v1[0].name := 'destroy';
  GReq_wp_image_description_v1[0].signature := '';
  GReq_wp_image_description_v1[0].types := @GTypes[0];
  GReq_wp_image_description_v1[1].name := 'get_information';
  GReq_wp_image_description_v1[1].signature := 'n';
  GReq_wp_image_description_v1[1].types := @GTypes[26];
  GEvt_wp_image_description_v1[0].name := 'failed';
  GEvt_wp_image_description_v1[0].signature := 'us';
  GEvt_wp_image_description_v1[0].types := @GTypes[0];
  GEvt_wp_image_description_v1[1].name := 'ready';
  GEvt_wp_image_description_v1[1].signature := 'u';
  GEvt_wp_image_description_v1[1].types := @GTypes[0];
  GEvt_wp_image_description_v1[2].name := 'ready2';
  GEvt_wp_image_description_v1[2].signature := '2uu';
  GEvt_wp_image_description_v1[2].types := @GTypes[0];
  GIface_wp_image_description_v1.name := 'wp_image_description_v1';
  GIface_wp_image_description_v1.version := 2;
  GIface_wp_image_description_v1.method_count := 2;
  GIface_wp_image_description_v1.methods := @GReq_wp_image_description_v1[0];
  GIface_wp_image_description_v1.event_count := 3;
  GIface_wp_image_description_v1.events := @GEvt_wp_image_description_v1[0];
  wp_image_description_v1_interface := @GIface_wp_image_description_v1;

  GEvt_wp_image_description_info_v1[0].name := 'done';
  GEvt_wp_image_description_info_v1[0].signature := '';
  GEvt_wp_image_description_info_v1[0].types := @GTypes[0];
  GEvt_wp_image_description_info_v1[1].name := 'icc_file';
  GEvt_wp_image_description_info_v1[1].signature := 'hu';
  GEvt_wp_image_description_info_v1[1].types := @GTypes[0];
  GEvt_wp_image_description_info_v1[2].name := 'primaries';
  GEvt_wp_image_description_info_v1[2].signature := 'iiiiiiii';
  GEvt_wp_image_description_info_v1[2].types := @GTypes[0];
  GEvt_wp_image_description_info_v1[3].name := 'primaries_named';
  GEvt_wp_image_description_info_v1[3].signature := 'u';
  GEvt_wp_image_description_info_v1[3].types := @GTypes[0];
  GEvt_wp_image_description_info_v1[4].name := 'tf_power';
  GEvt_wp_image_description_info_v1[4].signature := 'u';
  GEvt_wp_image_description_info_v1[4].types := @GTypes[0];
  GEvt_wp_image_description_info_v1[5].name := 'tf_named';
  GEvt_wp_image_description_info_v1[5].signature := 'u';
  GEvt_wp_image_description_info_v1[5].types := @GTypes[0];
  GEvt_wp_image_description_info_v1[6].name := 'luminances';
  GEvt_wp_image_description_info_v1[6].signature := 'uuu';
  GEvt_wp_image_description_info_v1[6].types := @GTypes[0];
  GEvt_wp_image_description_info_v1[7].name := 'target_primaries';
  GEvt_wp_image_description_info_v1[7].signature := 'iiiiiiii';
  GEvt_wp_image_description_info_v1[7].types := @GTypes[0];
  GEvt_wp_image_description_info_v1[8].name := 'target_luminance';
  GEvt_wp_image_description_info_v1[8].signature := 'uu';
  GEvt_wp_image_description_info_v1[8].types := @GTypes[0];
  GEvt_wp_image_description_info_v1[9].name := 'target_max_cll';
  GEvt_wp_image_description_info_v1[9].signature := 'u';
  GEvt_wp_image_description_info_v1[9].types := @GTypes[0];
  GEvt_wp_image_description_info_v1[10].name := 'target_max_fall';
  GEvt_wp_image_description_info_v1[10].signature := 'u';
  GEvt_wp_image_description_info_v1[10].types := @GTypes[0];
  GIface_wp_image_description_info_v1.name := 'wp_image_description_info_v1';
  GIface_wp_image_description_info_v1.version := 2;
  GIface_wp_image_description_info_v1.method_count := 0;
  GIface_wp_image_description_info_v1.methods := nil;
  GIface_wp_image_description_info_v1.event_count := 11;
  GIface_wp_image_description_info_v1.events := @GEvt_wp_image_description_info_v1[0];
  wp_image_description_info_v1_interface := @GIface_wp_image_description_info_v1;

  GReq_wp_image_description_reference_v1[0].name := 'destroy';
  GReq_wp_image_description_reference_v1[0].signature := '';
  GReq_wp_image_description_reference_v1[0].types := @GTypes[0];
  GIface_wp_image_description_reference_v1.name := 'wp_image_description_reference_v1';
  GIface_wp_image_description_reference_v1.version := 1;
  GIface_wp_image_description_reference_v1.method_count := 1;
  GIface_wp_image_description_reference_v1.methods := @GReq_wp_image_description_reference_v1[0];
  GIface_wp_image_description_reference_v1.event_count := 0;
  GIface_wp_image_description_reference_v1.events := nil;
  wp_image_description_reference_v1_interface := @GIface_wp_image_description_reference_v1;

  GThunks_wp_color_manager_v1.supported_intent := @Thunk_wp_color_manager_v1_supported_intent;
  GThunks_wp_color_manager_v1.supported_feature := @Thunk_wp_color_manager_v1_supported_feature;
  GThunks_wp_color_manager_v1.supported_tf_named := @Thunk_wp_color_manager_v1_supported_tf_named;
  GThunks_wp_color_manager_v1.supported_primaries_named := @Thunk_wp_color_manager_v1_supported_primaries_named;
  GThunks_wp_color_manager_v1.done := @Thunk_wp_color_manager_v1_done;
  GThunks_wp_color_management_output_v1.image_description_changed := @Thunk_wp_color_management_output_v1_image_description_changed;
  GThunks_wp_color_management_surface_feedback_v1.preferred_changed := @Thunk_wp_color_management_surface_feedback_v1_preferred_changed;
  GThunks_wp_color_management_surface_feedback_v1.preferred_changed2 := @Thunk_wp_color_management_surface_feedback_v1_preferred_changed2;
  GThunks_wp_image_description_v1.failed := @Thunk_wp_image_description_v1_failed;
  GThunks_wp_image_description_v1.ready := @Thunk_wp_image_description_v1_ready;
  GThunks_wp_image_description_v1.ready2 := @Thunk_wp_image_description_v1_ready2;
  GThunks_wp_image_description_info_v1.done := @Thunk_wp_image_description_info_v1_done;
  GThunks_wp_image_description_info_v1.icc_file := @Thunk_wp_image_description_info_v1_icc_file;
  GThunks_wp_image_description_info_v1.primaries := @Thunk_wp_image_description_info_v1_primaries;
  GThunks_wp_image_description_info_v1.primaries_named := @Thunk_wp_image_description_info_v1_primaries_named;
  GThunks_wp_image_description_info_v1.tf_power := @Thunk_wp_image_description_info_v1_tf_power;
  GThunks_wp_image_description_info_v1.tf_named := @Thunk_wp_image_description_info_v1_tf_named;
  GThunks_wp_image_description_info_v1.luminances := @Thunk_wp_image_description_info_v1_luminances;
  GThunks_wp_image_description_info_v1.target_primaries := @Thunk_wp_image_description_info_v1_target_primaries;
  GThunks_wp_image_description_info_v1.target_luminance := @Thunk_wp_image_description_info_v1_target_luminance;
  GThunks_wp_image_description_info_v1.target_max_cll := @Thunk_wp_image_description_info_v1_target_max_cll;
  GThunks_wp_image_description_info_v1.target_max_fall := @Thunk_wp_image_description_info_v1_target_max_fall;
end;

end.
