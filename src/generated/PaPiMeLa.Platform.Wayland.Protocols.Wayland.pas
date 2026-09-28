{
  PaPiMeLa.Platform.Wayland.Protocols.Wayland

  自動生成ファイル。手で編集しないこと。
  生成元: wayland.xml
  生成器: tools/wlscan-pas （docs/DESIGN.md §9.2）

  Origin : generated from the Wayland protocol XML (not derived from SDL sources)

  プロトコル XML の著作権表示:

  Copyright � 2008-2011 Kristian H�gsberg
      Copyright � 2010-2011 Intel Corporation
      Copyright � 2012-2013 Collabora, Ltd.
  
      Permission is hereby granted, free of charge, to any person
      obtaining a copy of this software and associated documentation files
      (the "Software"), to deal in the Software without restriction,
      including without limitation the rights to use, copy, modify, merge,
      publish, distribute, sublicense, and/or sell copies of the Software,
      and to permit persons to whom the Software is furnished to do so,
      subject to the following conditions:
  
      The above copyright notice and this permission notice (including the
      next paragraph) shall be included in all copies or substantial
      portions of the Software.
  
      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
      EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
      MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
      NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
      BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
      ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
      CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
      SOFTWARE.

}
unit PaPiMeLa.Platform.Wayland.Protocols.Wayland;

{$I papimela.inc}
{$packrecords c}

interface

uses
  PaPiMeLa.Platform.Wayland.Client;

type
  // Pwl_display は PaPiMeLa.Platform.Wayland.Client の宣言を使う
  Twl_registry_opaque = record end;
  Pwl_registry = ^Twl_registry_opaque;
  Twl_callback_opaque = record end;
  Pwl_callback = ^Twl_callback_opaque;
  Twl_compositor_opaque = record end;
  Pwl_compositor = ^Twl_compositor_opaque;
  Twl_shm_pool_opaque = record end;
  Pwl_shm_pool = ^Twl_shm_pool_opaque;
  Twl_shm_opaque = record end;
  Pwl_shm = ^Twl_shm_opaque;
  Twl_buffer_opaque = record end;
  Pwl_buffer = ^Twl_buffer_opaque;
  Twl_data_offer_opaque = record end;
  Pwl_data_offer = ^Twl_data_offer_opaque;
  Twl_data_source_opaque = record end;
  Pwl_data_source = ^Twl_data_source_opaque;
  Twl_data_device_opaque = record end;
  Pwl_data_device = ^Twl_data_device_opaque;
  Twl_data_device_manager_opaque = record end;
  Pwl_data_device_manager = ^Twl_data_device_manager_opaque;
  Twl_shell_opaque = record end;
  Pwl_shell = ^Twl_shell_opaque;
  Twl_shell_surface_opaque = record end;
  Pwl_shell_surface = ^Twl_shell_surface_opaque;
  Twl_surface_opaque = record end;
  Pwl_surface = ^Twl_surface_opaque;
  Twl_seat_opaque = record end;
  Pwl_seat = ^Twl_seat_opaque;
  Twl_pointer_opaque = record end;
  Pwl_pointer = ^Twl_pointer_opaque;
  Twl_keyboard_opaque = record end;
  Pwl_keyboard = ^Twl_keyboard_opaque;
  Twl_touch_opaque = record end;
  Pwl_touch = ^Twl_touch_opaque;
  Twl_output_opaque = record end;
  Pwl_output = ^Twl_output_opaque;
  Twl_region_opaque = record end;
  Pwl_region = ^Twl_region_opaque;
  Twl_subcompositor_opaque = record end;
  Pwl_subcompositor = ^Twl_subcompositor_opaque;
  Twl_subsurface_opaque = record end;
  Pwl_subsurface = ^Twl_subsurface_opaque;
  Twl_fixes_opaque = record end;
  Pwl_fixes = ^Twl_fixes_opaque;

const
  // wl_display (version 1)
  WL_DISPLAY_SYNC_OPCODE = 0;
  WL_DISPLAY_GET_REGISTRY_OPCODE = 1;
  WL_DISPLAY_SYNC_SINCE_VERSION = 1;
  WL_DISPLAY_GET_REGISTRY_SINCE_VERSION = 1;
  WL_DISPLAY_ERROR_SINCE_VERSION = 1;
  WL_DISPLAY_DELETE_ID_SINCE_VERSION = 1;
  WL_DISPLAY_ERROR_INVALID_OBJECT = 0;
  WL_DISPLAY_ERROR_INVALID_METHOD = 1;
  WL_DISPLAY_ERROR_NO_MEMORY = 2;
  WL_DISPLAY_ERROR_IMPLEMENTATION = 3;

  // wl_registry (version 1)
  WL_REGISTRY_BIND_OPCODE = 0;
  WL_REGISTRY_BIND_SINCE_VERSION = 1;
  WL_REGISTRY_GLOBAL_SINCE_VERSION = 1;
  WL_REGISTRY_GLOBAL_REMOVE_SINCE_VERSION = 1;

  // wl_callback (version 1)
  WL_CALLBACK_DONE_SINCE_VERSION = 1;

  // wl_compositor (version 6)
  WL_COMPOSITOR_CREATE_SURFACE_OPCODE = 0;
  WL_COMPOSITOR_CREATE_REGION_OPCODE = 1;
  WL_COMPOSITOR_CREATE_SURFACE_SINCE_VERSION = 1;
  WL_COMPOSITOR_CREATE_REGION_SINCE_VERSION = 1;

  // wl_shm_pool (version 2)
  WL_SHM_POOL_CREATE_BUFFER_OPCODE = 0;
  WL_SHM_POOL_DESTROY_OPCODE = 1;
  WL_SHM_POOL_RESIZE_OPCODE = 2;
  WL_SHM_POOL_CREATE_BUFFER_SINCE_VERSION = 1;
  WL_SHM_POOL_DESTROY_SINCE_VERSION = 1;
  WL_SHM_POOL_RESIZE_SINCE_VERSION = 1;

  // wl_shm (version 2)
  WL_SHM_CREATE_POOL_OPCODE = 0;
  WL_SHM_RELEASE_OPCODE = 1;
  WL_SHM_CREATE_POOL_SINCE_VERSION = 1;
  WL_SHM_RELEASE_SINCE_VERSION = 2;
  WL_SHM_FORMAT_SINCE_VERSION = 1;
  WL_SHM_ERROR_INVALID_FORMAT = 0;
  WL_SHM_ERROR_INVALID_STRIDE = 1;
  WL_SHM_ERROR_INVALID_FD = 2;
  WL_SHM_FORMAT_ARGB8888 = 0;
  WL_SHM_FORMAT_XRGB8888 = 1;
  WL_SHM_FORMAT_C8 = $20203843;
  WL_SHM_FORMAT_RGB332 = $38424752;
  WL_SHM_FORMAT_BGR233 = $38524742;
  WL_SHM_FORMAT_XRGB4444 = $32315258;
  WL_SHM_FORMAT_XBGR4444 = $32314258;
  WL_SHM_FORMAT_RGBX4444 = $32315852;
  WL_SHM_FORMAT_BGRX4444 = $32315842;
  WL_SHM_FORMAT_ARGB4444 = $32315241;
  WL_SHM_FORMAT_ABGR4444 = $32314241;
  WL_SHM_FORMAT_RGBA4444 = $32314152;
  WL_SHM_FORMAT_BGRA4444 = $32314142;
  WL_SHM_FORMAT_XRGB1555 = $35315258;
  WL_SHM_FORMAT_XBGR1555 = $35314258;
  WL_SHM_FORMAT_RGBX5551 = $35315852;
  WL_SHM_FORMAT_BGRX5551 = $35315842;
  WL_SHM_FORMAT_ARGB1555 = $35315241;
  WL_SHM_FORMAT_ABGR1555 = $35314241;
  WL_SHM_FORMAT_RGBA5551 = $35314152;
  WL_SHM_FORMAT_BGRA5551 = $35314142;
  WL_SHM_FORMAT_RGB565 = $36314752;
  WL_SHM_FORMAT_BGR565 = $36314742;
  WL_SHM_FORMAT_RGB888 = $34324752;
  WL_SHM_FORMAT_BGR888 = $34324742;
  WL_SHM_FORMAT_XBGR8888 = $34324258;
  WL_SHM_FORMAT_RGBX8888 = $34325852;
  WL_SHM_FORMAT_BGRX8888 = $34325842;
  WL_SHM_FORMAT_ABGR8888 = $34324241;
  WL_SHM_FORMAT_RGBA8888 = $34324152;
  WL_SHM_FORMAT_BGRA8888 = $34324142;
  WL_SHM_FORMAT_XRGB2101010 = $30335258;
  WL_SHM_FORMAT_XBGR2101010 = $30334258;
  WL_SHM_FORMAT_RGBX1010102 = $30335852;
  WL_SHM_FORMAT_BGRX1010102 = $30335842;
  WL_SHM_FORMAT_ARGB2101010 = $30335241;
  WL_SHM_FORMAT_ABGR2101010 = $30334241;
  WL_SHM_FORMAT_RGBA1010102 = $30334152;
  WL_SHM_FORMAT_BGRA1010102 = $30334142;
  WL_SHM_FORMAT_YUYV = $56595559;
  WL_SHM_FORMAT_YVYU = $55595659;
  WL_SHM_FORMAT_UYVY = $59565955;
  WL_SHM_FORMAT_VYUY = $59555956;
  WL_SHM_FORMAT_AYUV = $56555941;
  WL_SHM_FORMAT_NV12 = $3231564e;
  WL_SHM_FORMAT_NV21 = $3132564e;
  WL_SHM_FORMAT_NV16 = $3631564e;
  WL_SHM_FORMAT_NV61 = $3136564e;
  WL_SHM_FORMAT_YUV410 = $39565559;
  WL_SHM_FORMAT_YVU410 = $39555659;
  WL_SHM_FORMAT_YUV411 = $31315559;
  WL_SHM_FORMAT_YVU411 = $31315659;
  WL_SHM_FORMAT_YUV420 = $32315559;
  WL_SHM_FORMAT_YVU420 = $32315659;
  WL_SHM_FORMAT_YUV422 = $36315559;
  WL_SHM_FORMAT_YVU422 = $36315659;
  WL_SHM_FORMAT_YUV444 = $34325559;
  WL_SHM_FORMAT_YVU444 = $34325659;
  WL_SHM_FORMAT_R8 = $20203852;
  WL_SHM_FORMAT_R16 = $20363152;
  WL_SHM_FORMAT_RG88 = $38384752;
  WL_SHM_FORMAT_GR88 = $38385247;
  WL_SHM_FORMAT_RG1616 = $32334752;
  WL_SHM_FORMAT_GR1616 = $32335247;
  WL_SHM_FORMAT_XRGB16161616F = $48345258;
  WL_SHM_FORMAT_XBGR16161616F = $48344258;
  WL_SHM_FORMAT_ARGB16161616F = $48345241;
  WL_SHM_FORMAT_ABGR16161616F = $48344241;
  WL_SHM_FORMAT_XYUV8888 = $56555958;
  WL_SHM_FORMAT_VUY888 = $34325556;
  WL_SHM_FORMAT_VUY101010 = $30335556;
  WL_SHM_FORMAT_Y210 = $30313259;
  WL_SHM_FORMAT_Y212 = $32313259;
  WL_SHM_FORMAT_Y216 = $36313259;
  WL_SHM_FORMAT_Y410 = $30313459;
  WL_SHM_FORMAT_Y412 = $32313459;
  WL_SHM_FORMAT_Y416 = $36313459;
  WL_SHM_FORMAT_XVYU2101010 = $30335658;
  WL_SHM_FORMAT_XVYU12_16161616 = $36335658;
  WL_SHM_FORMAT_XVYU16161616 = $38345658;
  WL_SHM_FORMAT_Y0L0 = $304c3059;
  WL_SHM_FORMAT_X0L0 = $304c3058;
  WL_SHM_FORMAT_Y0L2 = $324c3059;
  WL_SHM_FORMAT_X0L2 = $324c3058;
  WL_SHM_FORMAT_YUV420_8BIT = $38305559;
  WL_SHM_FORMAT_YUV420_10BIT = $30315559;
  WL_SHM_FORMAT_XRGB8888_A8 = $38415258;
  WL_SHM_FORMAT_XBGR8888_A8 = $38414258;
  WL_SHM_FORMAT_RGBX8888_A8 = $38415852;
  WL_SHM_FORMAT_BGRX8888_A8 = $38415842;
  WL_SHM_FORMAT_RGB888_A8 = $38413852;
  WL_SHM_FORMAT_BGR888_A8 = $38413842;
  WL_SHM_FORMAT_RGB565_A8 = $38413552;
  WL_SHM_FORMAT_BGR565_A8 = $38413542;
  WL_SHM_FORMAT_NV24 = $3432564e;
  WL_SHM_FORMAT_NV42 = $3234564e;
  WL_SHM_FORMAT_P210 = $30313250;
  WL_SHM_FORMAT_P010 = $30313050;
  WL_SHM_FORMAT_P012 = $32313050;
  WL_SHM_FORMAT_P016 = $36313050;
  WL_SHM_FORMAT_AXBXGXRX106106106106 = $30314241;
  WL_SHM_FORMAT_NV15 = $3531564e;
  WL_SHM_FORMAT_Q410 = $30313451;
  WL_SHM_FORMAT_Q401 = $31303451;
  WL_SHM_FORMAT_XRGB16161616 = $38345258;
  WL_SHM_FORMAT_XBGR16161616 = $38344258;
  WL_SHM_FORMAT_ARGB16161616 = $38345241;
  WL_SHM_FORMAT_ABGR16161616 = $38344241;
  WL_SHM_FORMAT_C1 = $20203143;
  WL_SHM_FORMAT_C2 = $20203243;
  WL_SHM_FORMAT_C4 = $20203443;
  WL_SHM_FORMAT_D1 = $20203144;
  WL_SHM_FORMAT_D2 = $20203244;
  WL_SHM_FORMAT_D4 = $20203444;
  WL_SHM_FORMAT_D8 = $20203844;
  WL_SHM_FORMAT_R1 = $20203152;
  WL_SHM_FORMAT_R2 = $20203252;
  WL_SHM_FORMAT_R4 = $20203452;
  WL_SHM_FORMAT_R10 = $20303152;
  WL_SHM_FORMAT_R12 = $20323152;
  WL_SHM_FORMAT_AVUY8888 = $59555641;
  WL_SHM_FORMAT_XVUY8888 = $59555658;
  WL_SHM_FORMAT_P030 = $30333050;

  // wl_buffer (version 1)
  WL_BUFFER_DESTROY_OPCODE = 0;
  WL_BUFFER_DESTROY_SINCE_VERSION = 1;
  WL_BUFFER_RELEASE_SINCE_VERSION = 1;

  // wl_data_offer (version 3)
  WL_DATA_OFFER_ACCEPT_OPCODE = 0;
  WL_DATA_OFFER_RECEIVE_OPCODE = 1;
  WL_DATA_OFFER_DESTROY_OPCODE = 2;
  WL_DATA_OFFER_FINISH_OPCODE = 3;
  WL_DATA_OFFER_SET_ACTIONS_OPCODE = 4;
  WL_DATA_OFFER_ACCEPT_SINCE_VERSION = 1;
  WL_DATA_OFFER_RECEIVE_SINCE_VERSION = 1;
  WL_DATA_OFFER_DESTROY_SINCE_VERSION = 1;
  WL_DATA_OFFER_FINISH_SINCE_VERSION = 3;
  WL_DATA_OFFER_SET_ACTIONS_SINCE_VERSION = 3;
  WL_DATA_OFFER_OFFER_SINCE_VERSION = 1;
  WL_DATA_OFFER_SOURCE_ACTIONS_SINCE_VERSION = 3;
  WL_DATA_OFFER_ACTION_SINCE_VERSION = 3;
  WL_DATA_OFFER_ERROR_INVALID_FINISH = 0;
  WL_DATA_OFFER_ERROR_INVALID_ACTION_MASK = 1;
  WL_DATA_OFFER_ERROR_INVALID_ACTION = 2;
  WL_DATA_OFFER_ERROR_INVALID_OFFER = 3;

  // wl_data_source (version 3)
  WL_DATA_SOURCE_OFFER_OPCODE = 0;
  WL_DATA_SOURCE_DESTROY_OPCODE = 1;
  WL_DATA_SOURCE_SET_ACTIONS_OPCODE = 2;
  WL_DATA_SOURCE_OFFER_SINCE_VERSION = 1;
  WL_DATA_SOURCE_DESTROY_SINCE_VERSION = 1;
  WL_DATA_SOURCE_SET_ACTIONS_SINCE_VERSION = 3;
  WL_DATA_SOURCE_TARGET_SINCE_VERSION = 1;
  WL_DATA_SOURCE_SEND_SINCE_VERSION = 1;
  WL_DATA_SOURCE_CANCELLED_SINCE_VERSION = 1;
  WL_DATA_SOURCE_DND_DROP_PERFORMED_SINCE_VERSION = 3;
  WL_DATA_SOURCE_DND_FINISHED_SINCE_VERSION = 3;
  WL_DATA_SOURCE_ACTION_SINCE_VERSION = 3;
  WL_DATA_SOURCE_ERROR_INVALID_ACTION_MASK = 0;
  WL_DATA_SOURCE_ERROR_INVALID_SOURCE = 1;

  // wl_data_device (version 3)
  WL_DATA_DEVICE_START_DRAG_OPCODE = 0;
  WL_DATA_DEVICE_SET_SELECTION_OPCODE = 1;
  WL_DATA_DEVICE_RELEASE_OPCODE = 2;
  WL_DATA_DEVICE_START_DRAG_SINCE_VERSION = 1;
  WL_DATA_DEVICE_SET_SELECTION_SINCE_VERSION = 1;
  WL_DATA_DEVICE_RELEASE_SINCE_VERSION = 2;
  WL_DATA_DEVICE_DATA_OFFER_SINCE_VERSION = 1;
  WL_DATA_DEVICE_ENTER_SINCE_VERSION = 1;
  WL_DATA_DEVICE_LEAVE_SINCE_VERSION = 1;
  WL_DATA_DEVICE_MOTION_SINCE_VERSION = 1;
  WL_DATA_DEVICE_DROP_SINCE_VERSION = 1;
  WL_DATA_DEVICE_SELECTION_SINCE_VERSION = 1;
  WL_DATA_DEVICE_ERROR_ROLE = 0;
  WL_DATA_DEVICE_ERROR_USED_SOURCE = 1;

  // wl_data_device_manager (version 3)
  WL_DATA_DEVICE_MANAGER_CREATE_DATA_SOURCE_OPCODE = 0;
  WL_DATA_DEVICE_MANAGER_GET_DATA_DEVICE_OPCODE = 1;
  WL_DATA_DEVICE_MANAGER_CREATE_DATA_SOURCE_SINCE_VERSION = 1;
  WL_DATA_DEVICE_MANAGER_GET_DATA_DEVICE_SINCE_VERSION = 1;
  WL_DATA_DEVICE_MANAGER_DND_ACTION_NONE = 0;
  WL_DATA_DEVICE_MANAGER_DND_ACTION_COPY = 1;
  WL_DATA_DEVICE_MANAGER_DND_ACTION_MOVE = 2;
  WL_DATA_DEVICE_MANAGER_DND_ACTION_ASK = 4;

  // wl_shell (version 1)
  WL_SHELL_GET_SHELL_SURFACE_OPCODE = 0;
  WL_SHELL_GET_SHELL_SURFACE_SINCE_VERSION = 1;
  WL_SHELL_ERROR_ROLE = 0;

  // wl_shell_surface (version 1)
  WL_SHELL_SURFACE_PONG_OPCODE = 0;
  WL_SHELL_SURFACE_MOVE_OPCODE = 1;
  WL_SHELL_SURFACE_RESIZE_OPCODE = 2;
  WL_SHELL_SURFACE_SET_TOPLEVEL_OPCODE = 3;
  WL_SHELL_SURFACE_SET_TRANSIENT_OPCODE = 4;
  WL_SHELL_SURFACE_SET_FULLSCREEN_OPCODE = 5;
  WL_SHELL_SURFACE_SET_POPUP_OPCODE = 6;
  WL_SHELL_SURFACE_SET_MAXIMIZED_OPCODE = 7;
  WL_SHELL_SURFACE_SET_TITLE_OPCODE = 8;
  WL_SHELL_SURFACE_SET_CLASS_OPCODE = 9;
  WL_SHELL_SURFACE_PONG_SINCE_VERSION = 1;
  WL_SHELL_SURFACE_MOVE_SINCE_VERSION = 1;
  WL_SHELL_SURFACE_RESIZE_SINCE_VERSION = 1;
  WL_SHELL_SURFACE_SET_TOPLEVEL_SINCE_VERSION = 1;
  WL_SHELL_SURFACE_SET_TRANSIENT_SINCE_VERSION = 1;
  WL_SHELL_SURFACE_SET_FULLSCREEN_SINCE_VERSION = 1;
  WL_SHELL_SURFACE_SET_POPUP_SINCE_VERSION = 1;
  WL_SHELL_SURFACE_SET_MAXIMIZED_SINCE_VERSION = 1;
  WL_SHELL_SURFACE_SET_TITLE_SINCE_VERSION = 1;
  WL_SHELL_SURFACE_SET_CLASS_SINCE_VERSION = 1;
  WL_SHELL_SURFACE_PING_SINCE_VERSION = 1;
  WL_SHELL_SURFACE_CONFIGURE_SINCE_VERSION = 1;
  WL_SHELL_SURFACE_POPUP_DONE_SINCE_VERSION = 1;
  WL_SHELL_SURFACE_RESIZE_NONE = 0;
  WL_SHELL_SURFACE_RESIZE_TOP = 1;
  WL_SHELL_SURFACE_RESIZE_BOTTOM = 2;
  WL_SHELL_SURFACE_RESIZE_LEFT = 4;
  WL_SHELL_SURFACE_RESIZE_TOP_LEFT = 5;
  WL_SHELL_SURFACE_RESIZE_BOTTOM_LEFT = 6;
  WL_SHELL_SURFACE_RESIZE_RIGHT = 8;
  WL_SHELL_SURFACE_RESIZE_TOP_RIGHT = 9;
  WL_SHELL_SURFACE_RESIZE_BOTTOM_RIGHT = 10;
  WL_SHELL_SURFACE_TRANSIENT_INACTIVE = $1;
  WL_SHELL_SURFACE_FULLSCREEN_METHOD_DEFAULT = 0;
  WL_SHELL_SURFACE_FULLSCREEN_METHOD_SCALE = 1;
  WL_SHELL_SURFACE_FULLSCREEN_METHOD_DRIVER = 2;
  WL_SHELL_SURFACE_FULLSCREEN_METHOD_FILL = 3;

  // wl_surface (version 6)
  WL_SURFACE_DESTROY_OPCODE = 0;
  WL_SURFACE_ATTACH_OPCODE = 1;
  WL_SURFACE_DAMAGE_OPCODE = 2;
  WL_SURFACE_FRAME_OPCODE = 3;
  WL_SURFACE_SET_OPAQUE_REGION_OPCODE = 4;
  WL_SURFACE_SET_INPUT_REGION_OPCODE = 5;
  WL_SURFACE_COMMIT_OPCODE = 6;
  WL_SURFACE_SET_BUFFER_TRANSFORM_OPCODE = 7;
  WL_SURFACE_SET_BUFFER_SCALE_OPCODE = 8;
  WL_SURFACE_DAMAGE_BUFFER_OPCODE = 9;
  WL_SURFACE_OFFSET_OPCODE = 10;
  WL_SURFACE_DESTROY_SINCE_VERSION = 1;
  WL_SURFACE_ATTACH_SINCE_VERSION = 1;
  WL_SURFACE_DAMAGE_SINCE_VERSION = 1;
  WL_SURFACE_FRAME_SINCE_VERSION = 1;
  WL_SURFACE_SET_OPAQUE_REGION_SINCE_VERSION = 1;
  WL_SURFACE_SET_INPUT_REGION_SINCE_VERSION = 1;
  WL_SURFACE_COMMIT_SINCE_VERSION = 1;
  WL_SURFACE_SET_BUFFER_TRANSFORM_SINCE_VERSION = 2;
  WL_SURFACE_SET_BUFFER_SCALE_SINCE_VERSION = 3;
  WL_SURFACE_DAMAGE_BUFFER_SINCE_VERSION = 4;
  WL_SURFACE_OFFSET_SINCE_VERSION = 5;
  WL_SURFACE_ENTER_SINCE_VERSION = 1;
  WL_SURFACE_LEAVE_SINCE_VERSION = 1;
  WL_SURFACE_PREFERRED_BUFFER_SCALE_SINCE_VERSION = 6;
  WL_SURFACE_PREFERRED_BUFFER_TRANSFORM_SINCE_VERSION = 6;
  WL_SURFACE_ERROR_INVALID_SCALE = 0;
  WL_SURFACE_ERROR_INVALID_TRANSFORM = 1;
  WL_SURFACE_ERROR_INVALID_SIZE = 2;
  WL_SURFACE_ERROR_INVALID_OFFSET = 3;
  WL_SURFACE_ERROR_DEFUNCT_ROLE_OBJECT = 4;

  // wl_seat (version 10)
  WL_SEAT_GET_POINTER_OPCODE = 0;
  WL_SEAT_GET_KEYBOARD_OPCODE = 1;
  WL_SEAT_GET_TOUCH_OPCODE = 2;
  WL_SEAT_RELEASE_OPCODE = 3;
  WL_SEAT_GET_POINTER_SINCE_VERSION = 1;
  WL_SEAT_GET_KEYBOARD_SINCE_VERSION = 1;
  WL_SEAT_GET_TOUCH_SINCE_VERSION = 1;
  WL_SEAT_RELEASE_SINCE_VERSION = 5;
  WL_SEAT_CAPABILITIES_SINCE_VERSION = 1;
  WL_SEAT_NAME_SINCE_VERSION = 2;
  WL_SEAT_CAPABILITY_POINTER = 1;
  WL_SEAT_CAPABILITY_KEYBOARD = 2;
  WL_SEAT_CAPABILITY_TOUCH = 4;
  WL_SEAT_ERROR_MISSING_CAPABILITY = 0;

  // wl_pointer (version 10)
  WL_POINTER_SET_CURSOR_OPCODE = 0;
  WL_POINTER_RELEASE_OPCODE = 1;
  WL_POINTER_SET_CURSOR_SINCE_VERSION = 1;
  WL_POINTER_RELEASE_SINCE_VERSION = 3;
  WL_POINTER_ENTER_SINCE_VERSION = 1;
  WL_POINTER_LEAVE_SINCE_VERSION = 1;
  WL_POINTER_MOTION_SINCE_VERSION = 1;
  WL_POINTER_BUTTON_SINCE_VERSION = 1;
  WL_POINTER_AXIS_SINCE_VERSION = 1;
  WL_POINTER_FRAME_SINCE_VERSION = 5;
  WL_POINTER_AXIS_SOURCE_SINCE_VERSION = 5;
  WL_POINTER_AXIS_STOP_SINCE_VERSION = 5;
  WL_POINTER_AXIS_DISCRETE_SINCE_VERSION = 5;
  WL_POINTER_AXIS_VALUE120_SINCE_VERSION = 8;
  WL_POINTER_AXIS_RELATIVE_DIRECTION_SINCE_VERSION = 9;
  WL_POINTER_ERROR_ROLE = 0;
  WL_POINTER_BUTTON_STATE_RELEASED = 0;
  WL_POINTER_BUTTON_STATE_PRESSED = 1;
  WL_POINTER_AXIS_VERTICAL_SCROLL = 0;
  WL_POINTER_AXIS_HORIZONTAL_SCROLL = 1;
  WL_POINTER_AXIS_SOURCE_WHEEL = 0;
  WL_POINTER_AXIS_SOURCE_FINGER = 1;
  WL_POINTER_AXIS_SOURCE_CONTINUOUS = 2;
  WL_POINTER_AXIS_SOURCE_WHEEL_TILT = 3;
  WL_POINTER_AXIS_RELATIVE_DIRECTION_IDENTICAL = 0;
  WL_POINTER_AXIS_RELATIVE_DIRECTION_INVERTED = 1;

  // wl_keyboard (version 10)
  WL_KEYBOARD_RELEASE_OPCODE = 0;
  WL_KEYBOARD_RELEASE_SINCE_VERSION = 3;
  WL_KEYBOARD_KEYMAP_SINCE_VERSION = 1;
  WL_KEYBOARD_ENTER_SINCE_VERSION = 1;
  WL_KEYBOARD_LEAVE_SINCE_VERSION = 1;
  WL_KEYBOARD_KEY_SINCE_VERSION = 1;
  WL_KEYBOARD_MODIFIERS_SINCE_VERSION = 1;
  WL_KEYBOARD_REPEAT_INFO_SINCE_VERSION = 4;
  WL_KEYBOARD_KEYMAP_FORMAT_NO_KEYMAP = 0;
  WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1 = 1;
  WL_KEYBOARD_KEY_STATE_RELEASED = 0;
  WL_KEYBOARD_KEY_STATE_PRESSED = 1;
  WL_KEYBOARD_KEY_STATE_REPEATED = 2;

  // wl_touch (version 10)
  WL_TOUCH_RELEASE_OPCODE = 0;
  WL_TOUCH_RELEASE_SINCE_VERSION = 3;
  WL_TOUCH_DOWN_SINCE_VERSION = 1;
  WL_TOUCH_UP_SINCE_VERSION = 1;
  WL_TOUCH_MOTION_SINCE_VERSION = 1;
  WL_TOUCH_FRAME_SINCE_VERSION = 1;
  WL_TOUCH_CANCEL_SINCE_VERSION = 1;
  WL_TOUCH_SHAPE_SINCE_VERSION = 6;
  WL_TOUCH_ORIENTATION_SINCE_VERSION = 6;

  // wl_output (version 4)
  WL_OUTPUT_RELEASE_OPCODE = 0;
  WL_OUTPUT_RELEASE_SINCE_VERSION = 3;
  WL_OUTPUT_GEOMETRY_SINCE_VERSION = 1;
  WL_OUTPUT_MODE_SINCE_VERSION = 1;
  WL_OUTPUT_DONE_SINCE_VERSION = 2;
  WL_OUTPUT_SCALE_SINCE_VERSION = 2;
  WL_OUTPUT_NAME_SINCE_VERSION = 4;
  WL_OUTPUT_DESCRIPTION_SINCE_VERSION = 4;
  WL_OUTPUT_SUBPIXEL_UNKNOWN = 0;
  WL_OUTPUT_SUBPIXEL_NONE = 1;
  WL_OUTPUT_SUBPIXEL_HORIZONTAL_RGB = 2;
  WL_OUTPUT_SUBPIXEL_HORIZONTAL_BGR = 3;
  WL_OUTPUT_SUBPIXEL_VERTICAL_RGB = 4;
  WL_OUTPUT_SUBPIXEL_VERTICAL_BGR = 5;
  WL_OUTPUT_TRANSFORM_NORMAL = 0;
  WL_OUTPUT_TRANSFORM_90 = 1;
  WL_OUTPUT_TRANSFORM_180 = 2;
  WL_OUTPUT_TRANSFORM_270 = 3;
  WL_OUTPUT_TRANSFORM_FLIPPED = 4;
  WL_OUTPUT_TRANSFORM_FLIPPED_90 = 5;
  WL_OUTPUT_TRANSFORM_FLIPPED_180 = 6;
  WL_OUTPUT_TRANSFORM_FLIPPED_270 = 7;
  WL_OUTPUT_MODE_CURRENT = $1;
  WL_OUTPUT_MODE_PREFERRED = $2;

  // wl_region (version 1)
  WL_REGION_DESTROY_OPCODE = 0;
  WL_REGION_ADD_OPCODE = 1;
  WL_REGION_SUBTRACT_OPCODE = 2;
  WL_REGION_DESTROY_SINCE_VERSION = 1;
  WL_REGION_ADD_SINCE_VERSION = 1;
  WL_REGION_SUBTRACT_SINCE_VERSION = 1;

  // wl_subcompositor (version 1)
  WL_SUBCOMPOSITOR_DESTROY_OPCODE = 0;
  WL_SUBCOMPOSITOR_GET_SUBSURFACE_OPCODE = 1;
  WL_SUBCOMPOSITOR_DESTROY_SINCE_VERSION = 1;
  WL_SUBCOMPOSITOR_GET_SUBSURFACE_SINCE_VERSION = 1;
  WL_SUBCOMPOSITOR_ERROR_BAD_SURFACE = 0;
  WL_SUBCOMPOSITOR_ERROR_BAD_PARENT = 1;

  // wl_subsurface (version 1)
  WL_SUBSURFACE_DESTROY_OPCODE = 0;
  WL_SUBSURFACE_SET_POSITION_OPCODE = 1;
  WL_SUBSURFACE_PLACE_ABOVE_OPCODE = 2;
  WL_SUBSURFACE_PLACE_BELOW_OPCODE = 3;
  WL_SUBSURFACE_SET_SYNC_OPCODE = 4;
  WL_SUBSURFACE_SET_DESYNC_OPCODE = 5;
  WL_SUBSURFACE_DESTROY_SINCE_VERSION = 1;
  WL_SUBSURFACE_SET_POSITION_SINCE_VERSION = 1;
  WL_SUBSURFACE_PLACE_ABOVE_SINCE_VERSION = 1;
  WL_SUBSURFACE_PLACE_BELOW_SINCE_VERSION = 1;
  WL_SUBSURFACE_SET_SYNC_SINCE_VERSION = 1;
  WL_SUBSURFACE_SET_DESYNC_SINCE_VERSION = 1;
  WL_SUBSURFACE_ERROR_BAD_SURFACE = 0;

  // wl_fixes (version 1)
  WL_FIXES_DESTROY_OPCODE = 0;
  WL_FIXES_DESTROY_REGISTRY_OPCODE = 1;
  WL_FIXES_DESTROY_SINCE_VERSION = 1;
  WL_FIXES_DESTROY_REGISTRY_SINCE_VERSION = 1;

var
  wl_display_interface: Pwl_interface = nil;
  wl_registry_interface: Pwl_interface = nil;
  wl_callback_interface: Pwl_interface = nil;
  wl_compositor_interface: Pwl_interface = nil;
  wl_shm_pool_interface: Pwl_interface = nil;
  wl_shm_interface: Pwl_interface = nil;
  wl_buffer_interface: Pwl_interface = nil;
  wl_data_offer_interface: Pwl_interface = nil;
  wl_data_source_interface: Pwl_interface = nil;
  wl_data_device_interface: Pwl_interface = nil;
  wl_data_device_manager_interface: Pwl_interface = nil;
  wl_shell_interface: Pwl_interface = nil;
  wl_shell_surface_interface: Pwl_interface = nil;
  wl_surface_interface: Pwl_interface = nil;
  wl_seat_interface: Pwl_interface = nil;
  wl_pointer_interface: Pwl_interface = nil;
  wl_keyboard_interface: Pwl_interface = nil;
  wl_touch_interface: Pwl_interface = nil;
  wl_output_interface: Pwl_interface = nil;
  wl_region_interface: Pwl_interface = nil;
  wl_subcompositor_interface: Pwl_interface = nil;
  wl_subsurface_interface: Pwl_interface = nil;
  wl_fixes_interface: Pwl_interface = nil;

type
  Twl_display_listener = class abstract(TObject)
  public
    procedure error(AProxy: Pwl_display; object_id: Pwl_proxy; code: LongWord; message: PAnsiChar); virtual;
    procedure delete_id(AProxy: Pwl_display; id: LongWord); virtual;
  end;

  Twl_display_listener_rec = record
    error: procedure(data: Pointer; AProxy: Pwl_display; object_id: Pwl_proxy; code: LongWord; message: PAnsiChar); cdecl;
    delete_id: procedure(data: Pointer; AProxy: Pwl_display; id: LongWord); cdecl;
  end;

  Twl_registry_listener = class abstract(TObject)
  public
    procedure global(AProxy: Pwl_registry; name: LongWord; interface_: PAnsiChar; version: LongWord); virtual;
    procedure global_remove(AProxy: Pwl_registry; name: LongWord); virtual;
  end;

  Twl_registry_listener_rec = record
    global: procedure(data: Pointer; AProxy: Pwl_registry; name: LongWord; interface_: PAnsiChar; version: LongWord); cdecl;
    global_remove: procedure(data: Pointer; AProxy: Pwl_registry; name: LongWord); cdecl;
  end;

  Twl_callback_listener = class abstract(TObject)
  public
    procedure done(AProxy: Pwl_callback; callback_data: LongWord); virtual;
  end;

  Twl_callback_listener_rec = record
    done: procedure(data: Pointer; AProxy: Pwl_callback; callback_data: LongWord); cdecl;
  end;

  Twl_shm_listener = class abstract(TObject)
  public
    procedure format(AProxy: Pwl_shm; format_: LongWord); virtual;
  end;

  Twl_shm_listener_rec = record
    format: procedure(data: Pointer; AProxy: Pwl_shm; format_: LongWord); cdecl;
  end;

  Twl_buffer_listener = class abstract(TObject)
  public
    procedure release(AProxy: Pwl_buffer); virtual;
  end;

  Twl_buffer_listener_rec = record
    release: procedure(data: Pointer; AProxy: Pwl_buffer); cdecl;
  end;

  Twl_data_offer_listener = class abstract(TObject)
  public
    procedure offer(AProxy: Pwl_data_offer; mime_type: PAnsiChar); virtual;
    procedure source_actions(AProxy: Pwl_data_offer; source_actions_: LongWord); virtual;
    procedure action(AProxy: Pwl_data_offer; dnd_action: LongWord); virtual;
  end;

  Twl_data_offer_listener_rec = record
    offer: procedure(data: Pointer; AProxy: Pwl_data_offer; mime_type: PAnsiChar); cdecl;
    source_actions: procedure(data: Pointer; AProxy: Pwl_data_offer; source_actions_: LongWord); cdecl;
    action: procedure(data: Pointer; AProxy: Pwl_data_offer; dnd_action: LongWord); cdecl;
  end;

  Twl_data_source_listener = class abstract(TObject)
  public
    procedure target(AProxy: Pwl_data_source; mime_type: PAnsiChar); virtual;
    procedure send(AProxy: Pwl_data_source; mime_type: PAnsiChar; fd: LongInt); virtual;
    procedure cancelled(AProxy: Pwl_data_source); virtual;
    procedure dnd_drop_performed(AProxy: Pwl_data_source); virtual;
    procedure dnd_finished(AProxy: Pwl_data_source); virtual;
    procedure action(AProxy: Pwl_data_source; dnd_action: LongWord); virtual;
  end;

  Twl_data_source_listener_rec = record
    target: procedure(data: Pointer; AProxy: Pwl_data_source; mime_type: PAnsiChar); cdecl;
    send: procedure(data: Pointer; AProxy: Pwl_data_source; mime_type: PAnsiChar; fd: LongInt); cdecl;
    cancelled: procedure(data: Pointer; AProxy: Pwl_data_source); cdecl;
    dnd_drop_performed: procedure(data: Pointer; AProxy: Pwl_data_source); cdecl;
    dnd_finished: procedure(data: Pointer; AProxy: Pwl_data_source); cdecl;
    action: procedure(data: Pointer; AProxy: Pwl_data_source; dnd_action: LongWord); cdecl;
  end;

  Twl_data_device_listener = class abstract(TObject)
  public
    procedure data_offer(AProxy: Pwl_data_device; id: Pwl_data_offer); virtual;
    procedure enter(AProxy: Pwl_data_device; serial: LongWord; surface: Pwl_surface; x: wl_fixed_t; y: wl_fixed_t; id: Pwl_data_offer); virtual;
    procedure leave(AProxy: Pwl_data_device); virtual;
    procedure motion(AProxy: Pwl_data_device; time: LongWord; x: wl_fixed_t; y: wl_fixed_t); virtual;
    procedure drop(AProxy: Pwl_data_device); virtual;
    procedure selection(AProxy: Pwl_data_device; id: Pwl_data_offer); virtual;
  end;

  Twl_data_device_listener_rec = record
    data_offer: procedure(data: Pointer; AProxy: Pwl_data_device; id: Pwl_data_offer); cdecl;
    enter: procedure(data: Pointer; AProxy: Pwl_data_device; serial: LongWord; surface: Pwl_surface; x: wl_fixed_t; y: wl_fixed_t; id: Pwl_data_offer); cdecl;
    leave: procedure(data: Pointer; AProxy: Pwl_data_device); cdecl;
    motion: procedure(data: Pointer; AProxy: Pwl_data_device; time: LongWord; x: wl_fixed_t; y: wl_fixed_t); cdecl;
    drop: procedure(data: Pointer; AProxy: Pwl_data_device); cdecl;
    selection: procedure(data: Pointer; AProxy: Pwl_data_device; id: Pwl_data_offer); cdecl;
  end;

  Twl_shell_surface_listener = class abstract(TObject)
  public
    procedure ping(AProxy: Pwl_shell_surface; serial: LongWord); virtual;
    procedure configure(AProxy: Pwl_shell_surface; edges: LongWord; width: LongInt; height: LongInt); virtual;
    procedure popup_done(AProxy: Pwl_shell_surface); virtual;
  end;

  Twl_shell_surface_listener_rec = record
    ping: procedure(data: Pointer; AProxy: Pwl_shell_surface; serial: LongWord); cdecl;
    configure: procedure(data: Pointer; AProxy: Pwl_shell_surface; edges: LongWord; width: LongInt; height: LongInt); cdecl;
    popup_done: procedure(data: Pointer; AProxy: Pwl_shell_surface); cdecl;
  end;

  Twl_surface_listener = class abstract(TObject)
  public
    procedure enter(AProxy: Pwl_surface; output: Pwl_output); virtual;
    procedure leave(AProxy: Pwl_surface; output: Pwl_output); virtual;
    procedure preferred_buffer_scale(AProxy: Pwl_surface; factor: LongInt); virtual;
    procedure preferred_buffer_transform(AProxy: Pwl_surface; transform: LongWord); virtual;
  end;

  Twl_surface_listener_rec = record
    enter: procedure(data: Pointer; AProxy: Pwl_surface; output: Pwl_output); cdecl;
    leave: procedure(data: Pointer; AProxy: Pwl_surface; output: Pwl_output); cdecl;
    preferred_buffer_scale: procedure(data: Pointer; AProxy: Pwl_surface; factor: LongInt); cdecl;
    preferred_buffer_transform: procedure(data: Pointer; AProxy: Pwl_surface; transform: LongWord); cdecl;
  end;

  Twl_seat_listener = class abstract(TObject)
  public
    procedure capabilities(AProxy: Pwl_seat; capabilities_: LongWord); virtual;
    procedure name(AProxy: Pwl_seat; name_: PAnsiChar); virtual;
  end;

  Twl_seat_listener_rec = record
    capabilities: procedure(data: Pointer; AProxy: Pwl_seat; capabilities_: LongWord); cdecl;
    name: procedure(data: Pointer; AProxy: Pwl_seat; name_: PAnsiChar); cdecl;
  end;

  Twl_pointer_listener = class abstract(TObject)
  public
    procedure enter(AProxy: Pwl_pointer; serial: LongWord; surface: Pwl_surface; surface_x: wl_fixed_t; surface_y: wl_fixed_t); virtual;
    procedure leave(AProxy: Pwl_pointer; serial: LongWord; surface: Pwl_surface); virtual;
    procedure motion(AProxy: Pwl_pointer; time: LongWord; surface_x: wl_fixed_t; surface_y: wl_fixed_t); virtual;
    procedure button(AProxy: Pwl_pointer; serial: LongWord; time: LongWord; button_: LongWord; state: LongWord); virtual;
    procedure axis(AProxy: Pwl_pointer; time: LongWord; axis_: LongWord; value: wl_fixed_t); virtual;
    procedure frame(AProxy: Pwl_pointer); virtual;
    procedure axis_source(AProxy: Pwl_pointer; axis_source_: LongWord); virtual;
    procedure axis_stop(AProxy: Pwl_pointer; time: LongWord; axis_: LongWord); virtual;
    procedure axis_discrete(AProxy: Pwl_pointer; axis_: LongWord; discrete: LongInt); virtual;
    procedure axis_value120(AProxy: Pwl_pointer; axis_: LongWord; value120: LongInt); virtual;
    procedure axis_relative_direction(AProxy: Pwl_pointer; axis_: LongWord; direction: LongWord); virtual;
  end;

  Twl_pointer_listener_rec = record
    enter: procedure(data: Pointer; AProxy: Pwl_pointer; serial: LongWord; surface: Pwl_surface; surface_x: wl_fixed_t; surface_y: wl_fixed_t); cdecl;
    leave: procedure(data: Pointer; AProxy: Pwl_pointer; serial: LongWord; surface: Pwl_surface); cdecl;
    motion: procedure(data: Pointer; AProxy: Pwl_pointer; time: LongWord; surface_x: wl_fixed_t; surface_y: wl_fixed_t); cdecl;
    button: procedure(data: Pointer; AProxy: Pwl_pointer; serial: LongWord; time: LongWord; button_: LongWord; state: LongWord); cdecl;
    axis: procedure(data: Pointer; AProxy: Pwl_pointer; time: LongWord; axis_: LongWord; value: wl_fixed_t); cdecl;
    frame: procedure(data: Pointer; AProxy: Pwl_pointer); cdecl;
    axis_source: procedure(data: Pointer; AProxy: Pwl_pointer; axis_source_: LongWord); cdecl;
    axis_stop: procedure(data: Pointer; AProxy: Pwl_pointer; time: LongWord; axis_: LongWord); cdecl;
    axis_discrete: procedure(data: Pointer; AProxy: Pwl_pointer; axis_: LongWord; discrete: LongInt); cdecl;
    axis_value120: procedure(data: Pointer; AProxy: Pwl_pointer; axis_: LongWord; value120: LongInt); cdecl;
    axis_relative_direction: procedure(data: Pointer; AProxy: Pwl_pointer; axis_: LongWord; direction: LongWord); cdecl;
  end;

  Twl_keyboard_listener = class abstract(TObject)
  public
    procedure keymap(AProxy: Pwl_keyboard; format: LongWord; fd: LongInt; size: LongWord); virtual;
    procedure enter(AProxy: Pwl_keyboard; serial: LongWord; surface: Pwl_surface; keys: Pwl_array); virtual;
    procedure leave(AProxy: Pwl_keyboard; serial: LongWord; surface: Pwl_surface); virtual;
    procedure key(AProxy: Pwl_keyboard; serial: LongWord; time: LongWord; key_: LongWord; state: LongWord); virtual;
    procedure modifiers(AProxy: Pwl_keyboard; serial: LongWord; mods_depressed: LongWord; mods_latched: LongWord; mods_locked: LongWord; group: LongWord); virtual;
    procedure repeat_info(AProxy: Pwl_keyboard; rate: LongInt; delay: LongInt); virtual;
  end;

  Twl_keyboard_listener_rec = record
    keymap: procedure(data: Pointer; AProxy: Pwl_keyboard; format: LongWord; fd: LongInt; size: LongWord); cdecl;
    enter: procedure(data: Pointer; AProxy: Pwl_keyboard; serial: LongWord; surface: Pwl_surface; keys: Pwl_array); cdecl;
    leave: procedure(data: Pointer; AProxy: Pwl_keyboard; serial: LongWord; surface: Pwl_surface); cdecl;
    key: procedure(data: Pointer; AProxy: Pwl_keyboard; serial: LongWord; time: LongWord; key_: LongWord; state: LongWord); cdecl;
    modifiers: procedure(data: Pointer; AProxy: Pwl_keyboard; serial: LongWord; mods_depressed: LongWord; mods_latched: LongWord; mods_locked: LongWord; group: LongWord); cdecl;
    repeat_info: procedure(data: Pointer; AProxy: Pwl_keyboard; rate: LongInt; delay: LongInt); cdecl;
  end;

  Twl_touch_listener = class abstract(TObject)
  public
    procedure down(AProxy: Pwl_touch; serial: LongWord; time: LongWord; surface: Pwl_surface; id: LongInt; x: wl_fixed_t; y: wl_fixed_t); virtual;
    procedure up(AProxy: Pwl_touch; serial: LongWord; time: LongWord; id: LongInt); virtual;
    procedure motion(AProxy: Pwl_touch; time: LongWord; id: LongInt; x: wl_fixed_t; y: wl_fixed_t); virtual;
    procedure frame(AProxy: Pwl_touch); virtual;
    procedure cancel(AProxy: Pwl_touch); virtual;
    procedure shape(AProxy: Pwl_touch; id: LongInt; major: wl_fixed_t; minor: wl_fixed_t); virtual;
    procedure orientation(AProxy: Pwl_touch; id: LongInt; orientation_: wl_fixed_t); virtual;
  end;

  Twl_touch_listener_rec = record
    down: procedure(data: Pointer; AProxy: Pwl_touch; serial: LongWord; time: LongWord; surface: Pwl_surface; id: LongInt; x: wl_fixed_t; y: wl_fixed_t); cdecl;
    up: procedure(data: Pointer; AProxy: Pwl_touch; serial: LongWord; time: LongWord; id: LongInt); cdecl;
    motion: procedure(data: Pointer; AProxy: Pwl_touch; time: LongWord; id: LongInt; x: wl_fixed_t; y: wl_fixed_t); cdecl;
    frame: procedure(data: Pointer; AProxy: Pwl_touch); cdecl;
    cancel: procedure(data: Pointer; AProxy: Pwl_touch); cdecl;
    shape: procedure(data: Pointer; AProxy: Pwl_touch; id: LongInt; major: wl_fixed_t; minor: wl_fixed_t); cdecl;
    orientation: procedure(data: Pointer; AProxy: Pwl_touch; id: LongInt; orientation_: wl_fixed_t); cdecl;
  end;

  Twl_output_listener = class abstract(TObject)
  public
    procedure geometry(AProxy: Pwl_output; x: LongInt; y: LongInt; physical_width: LongInt; physical_height: LongInt; subpixel: LongInt; make: PAnsiChar; model: PAnsiChar; transform: LongInt); virtual;
    procedure mode(AProxy: Pwl_output; flags: LongWord; width: LongInt; height: LongInt; refresh: LongInt); virtual;
    procedure done(AProxy: Pwl_output); virtual;
    procedure scale(AProxy: Pwl_output; factor: LongInt); virtual;
    procedure name(AProxy: Pwl_output; name_: PAnsiChar); virtual;
    procedure description(AProxy: Pwl_output; description_: PAnsiChar); virtual;
  end;

  Twl_output_listener_rec = record
    geometry: procedure(data: Pointer; AProxy: Pwl_output; x: LongInt; y: LongInt; physical_width: LongInt; physical_height: LongInt; subpixel: LongInt; make: PAnsiChar; model: PAnsiChar; transform: LongInt); cdecl;
    mode: procedure(data: Pointer; AProxy: Pwl_output; flags: LongWord; width: LongInt; height: LongInt; refresh: LongInt); cdecl;
    done: procedure(data: Pointer; AProxy: Pwl_output); cdecl;
    scale: procedure(data: Pointer; AProxy: Pwl_output; factor: LongInt); cdecl;
    name: procedure(data: Pointer; AProxy: Pwl_output; name_: PAnsiChar); cdecl;
    description: procedure(data: Pointer; AProxy: Pwl_output; description_: PAnsiChar); cdecl;
  end;

function wl_display_add_listener_object(AProxy: Pwl_display; AListener: Twl_display_listener): LongInt;
function wl_display_sync(AProxy: Pwl_display): Pwl_callback;
function wl_display_get_registry(AProxy: Pwl_display): Pwl_registry;

function wl_registry_add_listener_object(AProxy: Pwl_registry; AListener: Twl_registry_listener): LongInt;
function wl_registry_bind(AProxy: Pwl_registry; name: LongWord; AInterface: Pwl_interface; AVersion: LongWord): Pwl_proxy;

function wl_callback_add_listener_object(AProxy: Pwl_callback; AListener: Twl_callback_listener): LongInt;
function wl_compositor_create_surface(AProxy: Pwl_compositor): Pwl_surface;
function wl_compositor_create_region(AProxy: Pwl_compositor): Pwl_region;

function wl_shm_pool_create_buffer(AProxy: Pwl_shm_pool; offset: LongInt; width: LongInt; height: LongInt; stride: LongInt; format: LongWord): Pwl_buffer;
procedure wl_shm_pool_destroy(AProxy: Pwl_shm_pool);
procedure wl_shm_pool_resize(AProxy: Pwl_shm_pool; size: LongInt);

function wl_shm_add_listener_object(AProxy: Pwl_shm; AListener: Twl_shm_listener): LongInt;
function wl_shm_create_pool(AProxy: Pwl_shm; fd: LongInt; size: LongInt): Pwl_shm_pool;
procedure wl_shm_release(AProxy: Pwl_shm);

function wl_buffer_add_listener_object(AProxy: Pwl_buffer; AListener: Twl_buffer_listener): LongInt;
procedure wl_buffer_destroy(AProxy: Pwl_buffer);

function wl_data_offer_add_listener_object(AProxy: Pwl_data_offer; AListener: Twl_data_offer_listener): LongInt;
procedure wl_data_offer_accept(AProxy: Pwl_data_offer; serial: LongWord; mime_type: PAnsiChar);
procedure wl_data_offer_receive(AProxy: Pwl_data_offer; mime_type: PAnsiChar; fd: LongInt);
procedure wl_data_offer_destroy(AProxy: Pwl_data_offer);
procedure wl_data_offer_finish(AProxy: Pwl_data_offer);
procedure wl_data_offer_set_actions(AProxy: Pwl_data_offer; dnd_actions: LongWord; preferred_action: LongWord);

function wl_data_source_add_listener_object(AProxy: Pwl_data_source; AListener: Twl_data_source_listener): LongInt;
procedure wl_data_source_offer(AProxy: Pwl_data_source; mime_type: PAnsiChar);
procedure wl_data_source_destroy(AProxy: Pwl_data_source);
procedure wl_data_source_set_actions(AProxy: Pwl_data_source; dnd_actions: LongWord);

function wl_data_device_add_listener_object(AProxy: Pwl_data_device; AListener: Twl_data_device_listener): LongInt;
procedure wl_data_device_start_drag(AProxy: Pwl_data_device; source: Pwl_data_source; origin: Pwl_surface; icon: Pwl_surface; serial: LongWord);
procedure wl_data_device_set_selection(AProxy: Pwl_data_device; source: Pwl_data_source; serial: LongWord);
procedure wl_data_device_release(AProxy: Pwl_data_device);

function wl_data_device_manager_create_data_source(AProxy: Pwl_data_device_manager): Pwl_data_source;
function wl_data_device_manager_get_data_device(AProxy: Pwl_data_device_manager; seat: Pwl_seat): Pwl_data_device;

function wl_shell_get_shell_surface(AProxy: Pwl_shell; surface: Pwl_surface): Pwl_shell_surface;

function wl_shell_surface_add_listener_object(AProxy: Pwl_shell_surface; AListener: Twl_shell_surface_listener): LongInt;
procedure wl_shell_surface_pong(AProxy: Pwl_shell_surface; serial: LongWord);
procedure wl_shell_surface_move(AProxy: Pwl_shell_surface; seat: Pwl_seat; serial: LongWord);
procedure wl_shell_surface_resize(AProxy: Pwl_shell_surface; seat: Pwl_seat; serial: LongWord; edges: LongWord);
procedure wl_shell_surface_set_toplevel(AProxy: Pwl_shell_surface);
procedure wl_shell_surface_set_transient(AProxy: Pwl_shell_surface; parent: Pwl_surface; x: LongInt; y: LongInt; flags: LongWord);
procedure wl_shell_surface_set_fullscreen(AProxy: Pwl_shell_surface; method: LongWord; framerate: LongWord; output: Pwl_output);
procedure wl_shell_surface_set_popup(AProxy: Pwl_shell_surface; seat: Pwl_seat; serial: LongWord; parent: Pwl_surface; x: LongInt; y: LongInt; flags: LongWord);
procedure wl_shell_surface_set_maximized(AProxy: Pwl_shell_surface; output: Pwl_output);
procedure wl_shell_surface_set_title(AProxy: Pwl_shell_surface; title: PAnsiChar);
procedure wl_shell_surface_set_class(AProxy: Pwl_shell_surface; class_: PAnsiChar);

function wl_surface_add_listener_object(AProxy: Pwl_surface; AListener: Twl_surface_listener): LongInt;
procedure wl_surface_destroy(AProxy: Pwl_surface);
procedure wl_surface_attach(AProxy: Pwl_surface; buffer: Pwl_buffer; x: LongInt; y: LongInt);
procedure wl_surface_damage(AProxy: Pwl_surface; x: LongInt; y: LongInt; width: LongInt; height: LongInt);
function wl_surface_frame(AProxy: Pwl_surface): Pwl_callback;
procedure wl_surface_set_opaque_region(AProxy: Pwl_surface; region: Pwl_region);
procedure wl_surface_set_input_region(AProxy: Pwl_surface; region: Pwl_region);
procedure wl_surface_commit(AProxy: Pwl_surface);
procedure wl_surface_set_buffer_transform(AProxy: Pwl_surface; transform: LongInt);
procedure wl_surface_set_buffer_scale(AProxy: Pwl_surface; scale: LongInt);
procedure wl_surface_damage_buffer(AProxy: Pwl_surface; x: LongInt; y: LongInt; width: LongInt; height: LongInt);
procedure wl_surface_offset(AProxy: Pwl_surface; x: LongInt; y: LongInt);

function wl_seat_add_listener_object(AProxy: Pwl_seat; AListener: Twl_seat_listener): LongInt;
function wl_seat_get_pointer(AProxy: Pwl_seat): Pwl_pointer;
function wl_seat_get_keyboard(AProxy: Pwl_seat): Pwl_keyboard;
function wl_seat_get_touch(AProxy: Pwl_seat): Pwl_touch;
procedure wl_seat_release(AProxy: Pwl_seat);

function wl_pointer_add_listener_object(AProxy: Pwl_pointer; AListener: Twl_pointer_listener): LongInt;
procedure wl_pointer_set_cursor(AProxy: Pwl_pointer; serial: LongWord; surface: Pwl_surface; hotspot_x: LongInt; hotspot_y: LongInt);
procedure wl_pointer_release(AProxy: Pwl_pointer);

function wl_keyboard_add_listener_object(AProxy: Pwl_keyboard; AListener: Twl_keyboard_listener): LongInt;
procedure wl_keyboard_release(AProxy: Pwl_keyboard);

function wl_touch_add_listener_object(AProxy: Pwl_touch; AListener: Twl_touch_listener): LongInt;
procedure wl_touch_release(AProxy: Pwl_touch);

function wl_output_add_listener_object(AProxy: Pwl_output; AListener: Twl_output_listener): LongInt;
procedure wl_output_release(AProxy: Pwl_output);

procedure wl_region_destroy(AProxy: Pwl_region);
procedure wl_region_add(AProxy: Pwl_region; x: LongInt; y: LongInt; width: LongInt; height: LongInt);
procedure wl_region_subtract(AProxy: Pwl_region; x: LongInt; y: LongInt; width: LongInt; height: LongInt);

procedure wl_subcompositor_destroy(AProxy: Pwl_subcompositor);
function wl_subcompositor_get_subsurface(AProxy: Pwl_subcompositor; surface: Pwl_surface; parent: Pwl_surface): Pwl_subsurface;

procedure wl_subsurface_destroy(AProxy: Pwl_subsurface);
procedure wl_subsurface_set_position(AProxy: Pwl_subsurface; x: LongInt; y: LongInt);
procedure wl_subsurface_place_above(AProxy: Pwl_subsurface; sibling: Pwl_surface);
procedure wl_subsurface_place_below(AProxy: Pwl_subsurface; sibling: Pwl_surface);
procedure wl_subsurface_set_sync(AProxy: Pwl_subsurface);
procedure wl_subsurface_set_desync(AProxy: Pwl_subsurface);

procedure wl_fixes_destroy(AProxy: Pwl_fixes);
procedure wl_fixes_destroy_registry(AProxy: Pwl_fixes; registry: Pwl_registry);

// wl_interface 記述子とサンク束を組む。多重呼び出し安全。
// libwayland のロード（PMLWaylandClientLoad）を先に済ませておくこと。
procedure EnsureProtocolInitialized;

implementation

var
  GInitialized: Boolean = False;
  GThunks_wl_display: Twl_display_listener_rec;
  GThunks_wl_registry: Twl_registry_listener_rec;
  GThunks_wl_callback: Twl_callback_listener_rec;
  GThunks_wl_shm: Twl_shm_listener_rec;
  GThunks_wl_buffer: Twl_buffer_listener_rec;
  GThunks_wl_data_offer: Twl_data_offer_listener_rec;
  GThunks_wl_data_source: Twl_data_source_listener_rec;
  GThunks_wl_data_device: Twl_data_device_listener_rec;
  GThunks_wl_shell_surface: Twl_shell_surface_listener_rec;
  GThunks_wl_surface: Twl_surface_listener_rec;
  GThunks_wl_seat: Twl_seat_listener_rec;
  GThunks_wl_pointer: Twl_pointer_listener_rec;
  GThunks_wl_keyboard: Twl_keyboard_listener_rec;
  GThunks_wl_touch: Twl_touch_listener_rec;
  GThunks_wl_output: Twl_output_listener_rec;

procedure Twl_display_listener.error(AProxy: Pwl_display; object_id: Pwl_proxy; code: LongWord; message: PAnsiChar);
begin
end;

procedure Twl_display_listener.delete_id(AProxy: Pwl_display; id: LongWord);
begin
end;

procedure Twl_registry_listener.global(AProxy: Pwl_registry; name: LongWord; interface_: PAnsiChar; version: LongWord);
begin
end;

procedure Twl_registry_listener.global_remove(AProxy: Pwl_registry; name: LongWord);
begin
end;

procedure Twl_callback_listener.done(AProxy: Pwl_callback; callback_data: LongWord);
begin
end;

procedure Twl_shm_listener.format(AProxy: Pwl_shm; format_: LongWord);
begin
end;

procedure Twl_buffer_listener.release(AProxy: Pwl_buffer);
begin
end;

procedure Twl_data_offer_listener.offer(AProxy: Pwl_data_offer; mime_type: PAnsiChar);
begin
end;

procedure Twl_data_offer_listener.source_actions(AProxy: Pwl_data_offer; source_actions_: LongWord);
begin
end;

procedure Twl_data_offer_listener.action(AProxy: Pwl_data_offer; dnd_action: LongWord);
begin
end;

procedure Twl_data_source_listener.target(AProxy: Pwl_data_source; mime_type: PAnsiChar);
begin
end;

procedure Twl_data_source_listener.send(AProxy: Pwl_data_source; mime_type: PAnsiChar; fd: LongInt);
begin
end;

procedure Twl_data_source_listener.cancelled(AProxy: Pwl_data_source);
begin
end;

procedure Twl_data_source_listener.dnd_drop_performed(AProxy: Pwl_data_source);
begin
end;

procedure Twl_data_source_listener.dnd_finished(AProxy: Pwl_data_source);
begin
end;

procedure Twl_data_source_listener.action(AProxy: Pwl_data_source; dnd_action: LongWord);
begin
end;

procedure Twl_data_device_listener.data_offer(AProxy: Pwl_data_device; id: Pwl_data_offer);
begin
end;

procedure Twl_data_device_listener.enter(AProxy: Pwl_data_device; serial: LongWord; surface: Pwl_surface; x: wl_fixed_t; y: wl_fixed_t; id: Pwl_data_offer);
begin
end;

procedure Twl_data_device_listener.leave(AProxy: Pwl_data_device);
begin
end;

procedure Twl_data_device_listener.motion(AProxy: Pwl_data_device; time: LongWord; x: wl_fixed_t; y: wl_fixed_t);
begin
end;

procedure Twl_data_device_listener.drop(AProxy: Pwl_data_device);
begin
end;

procedure Twl_data_device_listener.selection(AProxy: Pwl_data_device; id: Pwl_data_offer);
begin
end;

procedure Twl_shell_surface_listener.ping(AProxy: Pwl_shell_surface; serial: LongWord);
begin
end;

procedure Twl_shell_surface_listener.configure(AProxy: Pwl_shell_surface; edges: LongWord; width: LongInt; height: LongInt);
begin
end;

procedure Twl_shell_surface_listener.popup_done(AProxy: Pwl_shell_surface);
begin
end;

procedure Twl_surface_listener.enter(AProxy: Pwl_surface; output: Pwl_output);
begin
end;

procedure Twl_surface_listener.leave(AProxy: Pwl_surface; output: Pwl_output);
begin
end;

procedure Twl_surface_listener.preferred_buffer_scale(AProxy: Pwl_surface; factor: LongInt);
begin
end;

procedure Twl_surface_listener.preferred_buffer_transform(AProxy: Pwl_surface; transform: LongWord);
begin
end;

procedure Twl_seat_listener.capabilities(AProxy: Pwl_seat; capabilities_: LongWord);
begin
end;

procedure Twl_seat_listener.name(AProxy: Pwl_seat; name_: PAnsiChar);
begin
end;

procedure Twl_pointer_listener.enter(AProxy: Pwl_pointer; serial: LongWord; surface: Pwl_surface; surface_x: wl_fixed_t; surface_y: wl_fixed_t);
begin
end;

procedure Twl_pointer_listener.leave(AProxy: Pwl_pointer; serial: LongWord; surface: Pwl_surface);
begin
end;

procedure Twl_pointer_listener.motion(AProxy: Pwl_pointer; time: LongWord; surface_x: wl_fixed_t; surface_y: wl_fixed_t);
begin
end;

procedure Twl_pointer_listener.button(AProxy: Pwl_pointer; serial: LongWord; time: LongWord; button_: LongWord; state: LongWord);
begin
end;

procedure Twl_pointer_listener.axis(AProxy: Pwl_pointer; time: LongWord; axis_: LongWord; value: wl_fixed_t);
begin
end;

procedure Twl_pointer_listener.frame(AProxy: Pwl_pointer);
begin
end;

procedure Twl_pointer_listener.axis_source(AProxy: Pwl_pointer; axis_source_: LongWord);
begin
end;

procedure Twl_pointer_listener.axis_stop(AProxy: Pwl_pointer; time: LongWord; axis_: LongWord);
begin
end;

procedure Twl_pointer_listener.axis_discrete(AProxy: Pwl_pointer; axis_: LongWord; discrete: LongInt);
begin
end;

procedure Twl_pointer_listener.axis_value120(AProxy: Pwl_pointer; axis_: LongWord; value120: LongInt);
begin
end;

procedure Twl_pointer_listener.axis_relative_direction(AProxy: Pwl_pointer; axis_: LongWord; direction: LongWord);
begin
end;

procedure Twl_keyboard_listener.keymap(AProxy: Pwl_keyboard; format: LongWord; fd: LongInt; size: LongWord);
begin
end;

procedure Twl_keyboard_listener.enter(AProxy: Pwl_keyboard; serial: LongWord; surface: Pwl_surface; keys: Pwl_array);
begin
end;

procedure Twl_keyboard_listener.leave(AProxy: Pwl_keyboard; serial: LongWord; surface: Pwl_surface);
begin
end;

procedure Twl_keyboard_listener.key(AProxy: Pwl_keyboard; serial: LongWord; time: LongWord; key_: LongWord; state: LongWord);
begin
end;

procedure Twl_keyboard_listener.modifiers(AProxy: Pwl_keyboard; serial: LongWord; mods_depressed: LongWord; mods_latched: LongWord; mods_locked: LongWord; group: LongWord);
begin
end;

procedure Twl_keyboard_listener.repeat_info(AProxy: Pwl_keyboard; rate: LongInt; delay: LongInt);
begin
end;

procedure Twl_touch_listener.down(AProxy: Pwl_touch; serial: LongWord; time: LongWord; surface: Pwl_surface; id: LongInt; x: wl_fixed_t; y: wl_fixed_t);
begin
end;

procedure Twl_touch_listener.up(AProxy: Pwl_touch; serial: LongWord; time: LongWord; id: LongInt);
begin
end;

procedure Twl_touch_listener.motion(AProxy: Pwl_touch; time: LongWord; id: LongInt; x: wl_fixed_t; y: wl_fixed_t);
begin
end;

procedure Twl_touch_listener.frame(AProxy: Pwl_touch);
begin
end;

procedure Twl_touch_listener.cancel(AProxy: Pwl_touch);
begin
end;

procedure Twl_touch_listener.shape(AProxy: Pwl_touch; id: LongInt; major: wl_fixed_t; minor: wl_fixed_t);
begin
end;

procedure Twl_touch_listener.orientation(AProxy: Pwl_touch; id: LongInt; orientation_: wl_fixed_t);
begin
end;

procedure Twl_output_listener.geometry(AProxy: Pwl_output; x: LongInt; y: LongInt; physical_width: LongInt; physical_height: LongInt; subpixel: LongInt; make: PAnsiChar; model: PAnsiChar; transform: LongInt);
begin
end;

procedure Twl_output_listener.mode(AProxy: Pwl_output; flags: LongWord; width: LongInt; height: LongInt; refresh: LongInt);
begin
end;

procedure Twl_output_listener.done(AProxy: Pwl_output);
begin
end;

procedure Twl_output_listener.scale(AProxy: Pwl_output; factor: LongInt);
begin
end;

procedure Twl_output_listener.name(AProxy: Pwl_output; name_: PAnsiChar);
begin
end;

procedure Twl_output_listener.description(AProxy: Pwl_output; description_: PAnsiChar);
begin
end;

procedure Thunk_wl_display_error(data: Pointer; AProxy: Pwl_display; object_id: Pwl_proxy; code: LongWord; message: PAnsiChar); cdecl;
begin
  if data <> nil then
    Twl_display_listener(data).error(AProxy, object_id, code, message);
end;

procedure Thunk_wl_display_delete_id(data: Pointer; AProxy: Pwl_display; id: LongWord); cdecl;
begin
  if data <> nil then
    Twl_display_listener(data).delete_id(AProxy, id);
end;

procedure Thunk_wl_registry_global(data: Pointer; AProxy: Pwl_registry; name: LongWord; interface_: PAnsiChar; version: LongWord); cdecl;
begin
  if data <> nil then
    Twl_registry_listener(data).global(AProxy, name, interface_, version);
end;

procedure Thunk_wl_registry_global_remove(data: Pointer; AProxy: Pwl_registry; name: LongWord); cdecl;
begin
  if data <> nil then
    Twl_registry_listener(data).global_remove(AProxy, name);
end;

procedure Thunk_wl_callback_done(data: Pointer; AProxy: Pwl_callback; callback_data: LongWord); cdecl;
begin
  if data <> nil then
    Twl_callback_listener(data).done(AProxy, callback_data);
end;

procedure Thunk_wl_shm_format(data: Pointer; AProxy: Pwl_shm; format_: LongWord); cdecl;
begin
  if data <> nil then
    Twl_shm_listener(data).format(AProxy, format_);
end;

procedure Thunk_wl_buffer_release(data: Pointer; AProxy: Pwl_buffer); cdecl;
begin
  if data <> nil then
    Twl_buffer_listener(data).release(AProxy);
end;

procedure Thunk_wl_data_offer_offer(data: Pointer; AProxy: Pwl_data_offer; mime_type: PAnsiChar); cdecl;
begin
  if data <> nil then
    Twl_data_offer_listener(data).offer(AProxy, mime_type);
end;

procedure Thunk_wl_data_offer_source_actions(data: Pointer; AProxy: Pwl_data_offer; source_actions_: LongWord); cdecl;
begin
  if data <> nil then
    Twl_data_offer_listener(data).source_actions(AProxy, source_actions_);
end;

procedure Thunk_wl_data_offer_action(data: Pointer; AProxy: Pwl_data_offer; dnd_action: LongWord); cdecl;
begin
  if data <> nil then
    Twl_data_offer_listener(data).action(AProxy, dnd_action);
end;

procedure Thunk_wl_data_source_target(data: Pointer; AProxy: Pwl_data_source; mime_type: PAnsiChar); cdecl;
begin
  if data <> nil then
    Twl_data_source_listener(data).target(AProxy, mime_type);
end;

procedure Thunk_wl_data_source_send(data: Pointer; AProxy: Pwl_data_source; mime_type: PAnsiChar; fd: LongInt); cdecl;
begin
  if data <> nil then
    Twl_data_source_listener(data).send(AProxy, mime_type, fd);
end;

procedure Thunk_wl_data_source_cancelled(data: Pointer; AProxy: Pwl_data_source); cdecl;
begin
  if data <> nil then
    Twl_data_source_listener(data).cancelled(AProxy);
end;

procedure Thunk_wl_data_source_dnd_drop_performed(data: Pointer; AProxy: Pwl_data_source); cdecl;
begin
  if data <> nil then
    Twl_data_source_listener(data).dnd_drop_performed(AProxy);
end;

procedure Thunk_wl_data_source_dnd_finished(data: Pointer; AProxy: Pwl_data_source); cdecl;
begin
  if data <> nil then
    Twl_data_source_listener(data).dnd_finished(AProxy);
end;

procedure Thunk_wl_data_source_action(data: Pointer; AProxy: Pwl_data_source; dnd_action: LongWord); cdecl;
begin
  if data <> nil then
    Twl_data_source_listener(data).action(AProxy, dnd_action);
end;

procedure Thunk_wl_data_device_data_offer(data: Pointer; AProxy: Pwl_data_device; id: Pwl_data_offer); cdecl;
begin
  if data <> nil then
    Twl_data_device_listener(data).data_offer(AProxy, id);
end;

procedure Thunk_wl_data_device_enter(data: Pointer; AProxy: Pwl_data_device; serial: LongWord; surface: Pwl_surface; x: wl_fixed_t; y: wl_fixed_t; id: Pwl_data_offer); cdecl;
begin
  if data <> nil then
    Twl_data_device_listener(data).enter(AProxy, serial, surface, x, y, id);
end;

procedure Thunk_wl_data_device_leave(data: Pointer; AProxy: Pwl_data_device); cdecl;
begin
  if data <> nil then
    Twl_data_device_listener(data).leave(AProxy);
end;

procedure Thunk_wl_data_device_motion(data: Pointer; AProxy: Pwl_data_device; time: LongWord; x: wl_fixed_t; y: wl_fixed_t); cdecl;
begin
  if data <> nil then
    Twl_data_device_listener(data).motion(AProxy, time, x, y);
end;

procedure Thunk_wl_data_device_drop(data: Pointer; AProxy: Pwl_data_device); cdecl;
begin
  if data <> nil then
    Twl_data_device_listener(data).drop(AProxy);
end;

procedure Thunk_wl_data_device_selection(data: Pointer; AProxy: Pwl_data_device; id: Pwl_data_offer); cdecl;
begin
  if data <> nil then
    Twl_data_device_listener(data).selection(AProxy, id);
end;

procedure Thunk_wl_shell_surface_ping(data: Pointer; AProxy: Pwl_shell_surface; serial: LongWord); cdecl;
begin
  if data <> nil then
    Twl_shell_surface_listener(data).ping(AProxy, serial);
end;

procedure Thunk_wl_shell_surface_configure(data: Pointer; AProxy: Pwl_shell_surface; edges: LongWord; width: LongInt; height: LongInt); cdecl;
begin
  if data <> nil then
    Twl_shell_surface_listener(data).configure(AProxy, edges, width, height);
end;

procedure Thunk_wl_shell_surface_popup_done(data: Pointer; AProxy: Pwl_shell_surface); cdecl;
begin
  if data <> nil then
    Twl_shell_surface_listener(data).popup_done(AProxy);
end;

procedure Thunk_wl_surface_enter(data: Pointer; AProxy: Pwl_surface; output: Pwl_output); cdecl;
begin
  if data <> nil then
    Twl_surface_listener(data).enter(AProxy, output);
end;

procedure Thunk_wl_surface_leave(data: Pointer; AProxy: Pwl_surface; output: Pwl_output); cdecl;
begin
  if data <> nil then
    Twl_surface_listener(data).leave(AProxy, output);
end;

procedure Thunk_wl_surface_preferred_buffer_scale(data: Pointer; AProxy: Pwl_surface; factor: LongInt); cdecl;
begin
  if data <> nil then
    Twl_surface_listener(data).preferred_buffer_scale(AProxy, factor);
end;

procedure Thunk_wl_surface_preferred_buffer_transform(data: Pointer; AProxy: Pwl_surface; transform: LongWord); cdecl;
begin
  if data <> nil then
    Twl_surface_listener(data).preferred_buffer_transform(AProxy, transform);
end;

procedure Thunk_wl_seat_capabilities(data: Pointer; AProxy: Pwl_seat; capabilities_: LongWord); cdecl;
begin
  if data <> nil then
    Twl_seat_listener(data).capabilities(AProxy, capabilities_);
end;

procedure Thunk_wl_seat_name(data: Pointer; AProxy: Pwl_seat; name_: PAnsiChar); cdecl;
begin
  if data <> nil then
    Twl_seat_listener(data).name(AProxy, name_);
end;

procedure Thunk_wl_pointer_enter(data: Pointer; AProxy: Pwl_pointer; serial: LongWord; surface: Pwl_surface; surface_x: wl_fixed_t; surface_y: wl_fixed_t); cdecl;
begin
  if data <> nil then
    Twl_pointer_listener(data).enter(AProxy, serial, surface, surface_x, surface_y);
end;

procedure Thunk_wl_pointer_leave(data: Pointer; AProxy: Pwl_pointer; serial: LongWord; surface: Pwl_surface); cdecl;
begin
  if data <> nil then
    Twl_pointer_listener(data).leave(AProxy, serial, surface);
end;

procedure Thunk_wl_pointer_motion(data: Pointer; AProxy: Pwl_pointer; time: LongWord; surface_x: wl_fixed_t; surface_y: wl_fixed_t); cdecl;
begin
  if data <> nil then
    Twl_pointer_listener(data).motion(AProxy, time, surface_x, surface_y);
end;

procedure Thunk_wl_pointer_button(data: Pointer; AProxy: Pwl_pointer; serial: LongWord; time: LongWord; button_: LongWord; state: LongWord); cdecl;
begin
  if data <> nil then
    Twl_pointer_listener(data).button(AProxy, serial, time, button_, state);
end;

procedure Thunk_wl_pointer_axis(data: Pointer; AProxy: Pwl_pointer; time: LongWord; axis_: LongWord; value: wl_fixed_t); cdecl;
begin
  if data <> nil then
    Twl_pointer_listener(data).axis(AProxy, time, axis_, value);
end;

procedure Thunk_wl_pointer_frame(data: Pointer; AProxy: Pwl_pointer); cdecl;
begin
  if data <> nil then
    Twl_pointer_listener(data).frame(AProxy);
end;

procedure Thunk_wl_pointer_axis_source(data: Pointer; AProxy: Pwl_pointer; axis_source_: LongWord); cdecl;
begin
  if data <> nil then
    Twl_pointer_listener(data).axis_source(AProxy, axis_source_);
end;

procedure Thunk_wl_pointer_axis_stop(data: Pointer; AProxy: Pwl_pointer; time: LongWord; axis_: LongWord); cdecl;
begin
  if data <> nil then
    Twl_pointer_listener(data).axis_stop(AProxy, time, axis_);
end;

procedure Thunk_wl_pointer_axis_discrete(data: Pointer; AProxy: Pwl_pointer; axis_: LongWord; discrete: LongInt); cdecl;
begin
  if data <> nil then
    Twl_pointer_listener(data).axis_discrete(AProxy, axis_, discrete);
end;

procedure Thunk_wl_pointer_axis_value120(data: Pointer; AProxy: Pwl_pointer; axis_: LongWord; value120: LongInt); cdecl;
begin
  if data <> nil then
    Twl_pointer_listener(data).axis_value120(AProxy, axis_, value120);
end;

procedure Thunk_wl_pointer_axis_relative_direction(data: Pointer; AProxy: Pwl_pointer; axis_: LongWord; direction: LongWord); cdecl;
begin
  if data <> nil then
    Twl_pointer_listener(data).axis_relative_direction(AProxy, axis_, direction);
end;

procedure Thunk_wl_keyboard_keymap(data: Pointer; AProxy: Pwl_keyboard; format: LongWord; fd: LongInt; size: LongWord); cdecl;
begin
  if data <> nil then
    Twl_keyboard_listener(data).keymap(AProxy, format, fd, size);
end;

procedure Thunk_wl_keyboard_enter(data: Pointer; AProxy: Pwl_keyboard; serial: LongWord; surface: Pwl_surface; keys: Pwl_array); cdecl;
begin
  if data <> nil then
    Twl_keyboard_listener(data).enter(AProxy, serial, surface, keys);
end;

procedure Thunk_wl_keyboard_leave(data: Pointer; AProxy: Pwl_keyboard; serial: LongWord; surface: Pwl_surface); cdecl;
begin
  if data <> nil then
    Twl_keyboard_listener(data).leave(AProxy, serial, surface);
end;

procedure Thunk_wl_keyboard_key(data: Pointer; AProxy: Pwl_keyboard; serial: LongWord; time: LongWord; key_: LongWord; state: LongWord); cdecl;
begin
  if data <> nil then
    Twl_keyboard_listener(data).key(AProxy, serial, time, key_, state);
end;

procedure Thunk_wl_keyboard_modifiers(data: Pointer; AProxy: Pwl_keyboard; serial: LongWord; mods_depressed: LongWord; mods_latched: LongWord; mods_locked: LongWord; group: LongWord); cdecl;
begin
  if data <> nil then
    Twl_keyboard_listener(data).modifiers(AProxy, serial, mods_depressed, mods_latched, mods_locked, group);
end;

procedure Thunk_wl_keyboard_repeat_info(data: Pointer; AProxy: Pwl_keyboard; rate: LongInt; delay: LongInt); cdecl;
begin
  if data <> nil then
    Twl_keyboard_listener(data).repeat_info(AProxy, rate, delay);
end;

procedure Thunk_wl_touch_down(data: Pointer; AProxy: Pwl_touch; serial: LongWord; time: LongWord; surface: Pwl_surface; id: LongInt; x: wl_fixed_t; y: wl_fixed_t); cdecl;
begin
  if data <> nil then
    Twl_touch_listener(data).down(AProxy, serial, time, surface, id, x, y);
end;

procedure Thunk_wl_touch_up(data: Pointer; AProxy: Pwl_touch; serial: LongWord; time: LongWord; id: LongInt); cdecl;
begin
  if data <> nil then
    Twl_touch_listener(data).up(AProxy, serial, time, id);
end;

procedure Thunk_wl_touch_motion(data: Pointer; AProxy: Pwl_touch; time: LongWord; id: LongInt; x: wl_fixed_t; y: wl_fixed_t); cdecl;
begin
  if data <> nil then
    Twl_touch_listener(data).motion(AProxy, time, id, x, y);
end;

procedure Thunk_wl_touch_frame(data: Pointer; AProxy: Pwl_touch); cdecl;
begin
  if data <> nil then
    Twl_touch_listener(data).frame(AProxy);
end;

procedure Thunk_wl_touch_cancel(data: Pointer; AProxy: Pwl_touch); cdecl;
begin
  if data <> nil then
    Twl_touch_listener(data).cancel(AProxy);
end;

procedure Thunk_wl_touch_shape(data: Pointer; AProxy: Pwl_touch; id: LongInt; major: wl_fixed_t; minor: wl_fixed_t); cdecl;
begin
  if data <> nil then
    Twl_touch_listener(data).shape(AProxy, id, major, minor);
end;

procedure Thunk_wl_touch_orientation(data: Pointer; AProxy: Pwl_touch; id: LongInt; orientation_: wl_fixed_t); cdecl;
begin
  if data <> nil then
    Twl_touch_listener(data).orientation(AProxy, id, orientation_);
end;

procedure Thunk_wl_output_geometry(data: Pointer; AProxy: Pwl_output; x: LongInt; y: LongInt; physical_width: LongInt; physical_height: LongInt; subpixel: LongInt; make: PAnsiChar; model: PAnsiChar; transform: LongInt); cdecl;
begin
  if data <> nil then
    Twl_output_listener(data).geometry(AProxy, x, y, physical_width, physical_height, subpixel, make, model, transform);
end;

procedure Thunk_wl_output_mode(data: Pointer; AProxy: Pwl_output; flags: LongWord; width: LongInt; height: LongInt; refresh: LongInt); cdecl;
begin
  if data <> nil then
    Twl_output_listener(data).mode(AProxy, flags, width, height, refresh);
end;

procedure Thunk_wl_output_done(data: Pointer; AProxy: Pwl_output); cdecl;
begin
  if data <> nil then
    Twl_output_listener(data).done(AProxy);
end;

procedure Thunk_wl_output_scale(data: Pointer; AProxy: Pwl_output; factor: LongInt); cdecl;
begin
  if data <> nil then
    Twl_output_listener(data).scale(AProxy, factor);
end;

procedure Thunk_wl_output_name(data: Pointer; AProxy: Pwl_output; name_: PAnsiChar); cdecl;
begin
  if data <> nil then
    Twl_output_listener(data).name(AProxy, name_);
end;

procedure Thunk_wl_output_description(data: Pointer; AProxy: Pwl_output; description_: PAnsiChar); cdecl;
begin
  if data <> nil then
    Twl_output_listener(data).description(AProxy, description_);
end;

function wl_display_add_listener_object(AProxy: Pwl_display; AListener: Twl_display_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_display, AListener);
end;

function wl_registry_add_listener_object(AProxy: Pwl_registry; AListener: Twl_registry_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_registry, AListener);
end;

function wl_callback_add_listener_object(AProxy: Pwl_callback; AListener: Twl_callback_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_callback, AListener);
end;

function wl_shm_add_listener_object(AProxy: Pwl_shm; AListener: Twl_shm_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_shm, AListener);
end;

function wl_buffer_add_listener_object(AProxy: Pwl_buffer; AListener: Twl_buffer_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_buffer, AListener);
end;

function wl_data_offer_add_listener_object(AProxy: Pwl_data_offer; AListener: Twl_data_offer_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_data_offer, AListener);
end;

function wl_data_source_add_listener_object(AProxy: Pwl_data_source; AListener: Twl_data_source_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_data_source, AListener);
end;

function wl_data_device_add_listener_object(AProxy: Pwl_data_device; AListener: Twl_data_device_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_data_device, AListener);
end;

function wl_shell_surface_add_listener_object(AProxy: Pwl_shell_surface; AListener: Twl_shell_surface_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_shell_surface, AListener);
end;

function wl_surface_add_listener_object(AProxy: Pwl_surface; AListener: Twl_surface_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_surface, AListener);
end;

function wl_seat_add_listener_object(AProxy: Pwl_seat; AListener: Twl_seat_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_seat, AListener);
end;

function wl_pointer_add_listener_object(AProxy: Pwl_pointer; AListener: Twl_pointer_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_pointer, AListener);
end;

function wl_keyboard_add_listener_object(AProxy: Pwl_keyboard; AListener: Twl_keyboard_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_keyboard, AListener);
end;

function wl_touch_add_listener_object(AProxy: Pwl_touch; AListener: Twl_touch_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_touch, AListener);
end;

function wl_output_add_listener_object(AProxy: Pwl_output; AListener: Twl_output_listener): LongInt;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_add_listener(Pwl_proxy(AProxy), @GThunks_wl_output, AListener);
end;

function wl_display_sync(AProxy: Pwl_display): Pwl_callback;
begin
  EnsureProtocolInitialized;
  Result := Pwl_callback(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DISPLAY_SYNC_OPCODE, wl_callback_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function wl_display_get_registry(AProxy: Pwl_display): Pwl_registry;
begin
  EnsureProtocolInitialized;
  Result := Pwl_registry(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DISPLAY_GET_REGISTRY_OPCODE, wl_registry_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function wl_registry_bind(AProxy: Pwl_registry; name: LongWord; AInterface: Pwl_interface; AVersion: LongWord): Pwl_proxy;
begin
  EnsureProtocolInitialized;
  Result := wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_REGISTRY_BIND_OPCODE, AInterface, AVersion, 0, name, AInterface^.name, AVersion, Pointer(nil));
end;

function wl_compositor_create_surface(AProxy: Pwl_compositor): Pwl_surface;
begin
  EnsureProtocolInitialized;
  Result := Pwl_surface(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_COMPOSITOR_CREATE_SURFACE_OPCODE, wl_surface_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function wl_compositor_create_region(AProxy: Pwl_compositor): Pwl_region;
begin
  EnsureProtocolInitialized;
  Result := Pwl_region(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_COMPOSITOR_CREATE_REGION_OPCODE, wl_region_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function wl_shm_pool_create_buffer(AProxy: Pwl_shm_pool; offset: LongInt; width: LongInt; height: LongInt; stride: LongInt; format: LongWord): Pwl_buffer;
begin
  EnsureProtocolInitialized;
  Result := Pwl_buffer(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHM_POOL_CREATE_BUFFER_OPCODE, wl_buffer_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), offset, width, height, stride, format));
end;

procedure wl_shm_pool_destroy(AProxy: Pwl_shm_pool);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHM_POOL_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wl_shm_pool_resize(AProxy: Pwl_shm_pool; size: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHM_POOL_RESIZE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, size);
end;

function wl_shm_create_pool(AProxy: Pwl_shm; fd: LongInt; size: LongInt): Pwl_shm_pool;
begin
  EnsureProtocolInitialized;
  Result := Pwl_shm_pool(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHM_CREATE_POOL_OPCODE, wl_shm_pool_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), fd, size));
end;

procedure wl_shm_release(AProxy: Pwl_shm);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHM_RELEASE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wl_buffer_destroy(AProxy: Pwl_buffer);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_BUFFER_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wl_data_offer_accept(AProxy: Pwl_data_offer; serial: LongWord; mime_type: PAnsiChar);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DATA_OFFER_ACCEPT_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, serial, mime_type);
end;

procedure wl_data_offer_receive(AProxy: Pwl_data_offer; mime_type: PAnsiChar; fd: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DATA_OFFER_RECEIVE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, mime_type, fd);
end;

procedure wl_data_offer_destroy(AProxy: Pwl_data_offer);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DATA_OFFER_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wl_data_offer_finish(AProxy: Pwl_data_offer);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DATA_OFFER_FINISH_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure wl_data_offer_set_actions(AProxy: Pwl_data_offer; dnd_actions: LongWord; preferred_action: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DATA_OFFER_SET_ACTIONS_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, dnd_actions, preferred_action);
end;

procedure wl_data_source_offer(AProxy: Pwl_data_source; mime_type: PAnsiChar);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DATA_SOURCE_OFFER_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, mime_type);
end;

procedure wl_data_source_destroy(AProxy: Pwl_data_source);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DATA_SOURCE_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wl_data_source_set_actions(AProxy: Pwl_data_source; dnd_actions: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DATA_SOURCE_SET_ACTIONS_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, dnd_actions);
end;

procedure wl_data_device_start_drag(AProxy: Pwl_data_device; source: Pwl_data_source; origin: Pwl_surface; icon: Pwl_surface; serial: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DATA_DEVICE_START_DRAG_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, source, origin, icon, serial);
end;

procedure wl_data_device_set_selection(AProxy: Pwl_data_device; source: Pwl_data_source; serial: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DATA_DEVICE_SET_SELECTION_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, source, serial);
end;

procedure wl_data_device_release(AProxy: Pwl_data_device);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DATA_DEVICE_RELEASE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function wl_data_device_manager_create_data_source(AProxy: Pwl_data_device_manager): Pwl_data_source;
begin
  EnsureProtocolInitialized;
  Result := Pwl_data_source(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DATA_DEVICE_MANAGER_CREATE_DATA_SOURCE_OPCODE, wl_data_source_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function wl_data_device_manager_get_data_device(AProxy: Pwl_data_device_manager; seat: Pwl_seat): Pwl_data_device;
begin
  EnsureProtocolInitialized;
  Result := Pwl_data_device(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_DATA_DEVICE_MANAGER_GET_DATA_DEVICE_OPCODE, wl_data_device_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), seat));
end;

function wl_shell_get_shell_surface(AProxy: Pwl_shell; surface: Pwl_surface): Pwl_shell_surface;
begin
  EnsureProtocolInitialized;
  Result := Pwl_shell_surface(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHELL_GET_SHELL_SURFACE_OPCODE, wl_shell_surface_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), surface));
end;

procedure wl_shell_surface_pong(AProxy: Pwl_shell_surface; serial: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHELL_SURFACE_PONG_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, serial);
end;

procedure wl_shell_surface_move(AProxy: Pwl_shell_surface; seat: Pwl_seat; serial: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHELL_SURFACE_MOVE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, seat, serial);
end;

procedure wl_shell_surface_resize(AProxy: Pwl_shell_surface; seat: Pwl_seat; serial: LongWord; edges: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHELL_SURFACE_RESIZE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, seat, serial, edges);
end;

procedure wl_shell_surface_set_toplevel(AProxy: Pwl_shell_surface);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHELL_SURFACE_SET_TOPLEVEL_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure wl_shell_surface_set_transient(AProxy: Pwl_shell_surface; parent: Pwl_surface; x: LongInt; y: LongInt; flags: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHELL_SURFACE_SET_TRANSIENT_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, parent, x, y, flags);
end;

procedure wl_shell_surface_set_fullscreen(AProxy: Pwl_shell_surface; method: LongWord; framerate: LongWord; output: Pwl_output);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHELL_SURFACE_SET_FULLSCREEN_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, method, framerate, output);
end;

procedure wl_shell_surface_set_popup(AProxy: Pwl_shell_surface; seat: Pwl_seat; serial: LongWord; parent: Pwl_surface; x: LongInt; y: LongInt; flags: LongWord);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHELL_SURFACE_SET_POPUP_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, seat, serial, parent, x, y, flags);
end;

procedure wl_shell_surface_set_maximized(AProxy: Pwl_shell_surface; output: Pwl_output);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHELL_SURFACE_SET_MAXIMIZED_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, output);
end;

procedure wl_shell_surface_set_title(AProxy: Pwl_shell_surface; title: PAnsiChar);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHELL_SURFACE_SET_TITLE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, title);
end;

procedure wl_shell_surface_set_class(AProxy: Pwl_shell_surface; class_: PAnsiChar);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SHELL_SURFACE_SET_CLASS_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, class_);
end;

procedure wl_surface_destroy(AProxy: Pwl_surface);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SURFACE_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wl_surface_attach(AProxy: Pwl_surface; buffer: Pwl_buffer; x: LongInt; y: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SURFACE_ATTACH_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, buffer, x, y);
end;

procedure wl_surface_damage(AProxy: Pwl_surface; x: LongInt; y: LongInt; width: LongInt; height: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SURFACE_DAMAGE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, x, y, width, height);
end;

function wl_surface_frame(AProxy: Pwl_surface): Pwl_callback;
begin
  EnsureProtocolInitialized;
  Result := Pwl_callback(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SURFACE_FRAME_OPCODE, wl_callback_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

procedure wl_surface_set_opaque_region(AProxy: Pwl_surface; region: Pwl_region);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SURFACE_SET_OPAQUE_REGION_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, region);
end;

procedure wl_surface_set_input_region(AProxy: Pwl_surface; region: Pwl_region);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SURFACE_SET_INPUT_REGION_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, region);
end;

procedure wl_surface_commit(AProxy: Pwl_surface);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SURFACE_COMMIT_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure wl_surface_set_buffer_transform(AProxy: Pwl_surface; transform: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SURFACE_SET_BUFFER_TRANSFORM_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, transform);
end;

procedure wl_surface_set_buffer_scale(AProxy: Pwl_surface; scale: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SURFACE_SET_BUFFER_SCALE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, scale);
end;

procedure wl_surface_damage_buffer(AProxy: Pwl_surface; x: LongInt; y: LongInt; width: LongInt; height: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SURFACE_DAMAGE_BUFFER_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, x, y, width, height);
end;

procedure wl_surface_offset(AProxy: Pwl_surface; x: LongInt; y: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SURFACE_OFFSET_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, x, y);
end;

function wl_seat_get_pointer(AProxy: Pwl_seat): Pwl_pointer;
begin
  EnsureProtocolInitialized;
  Result := Pwl_pointer(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SEAT_GET_POINTER_OPCODE, wl_pointer_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function wl_seat_get_keyboard(AProxy: Pwl_seat): Pwl_keyboard;
begin
  EnsureProtocolInitialized;
  Result := Pwl_keyboard(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SEAT_GET_KEYBOARD_OPCODE, wl_keyboard_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

function wl_seat_get_touch(AProxy: Pwl_seat): Pwl_touch;
begin
  EnsureProtocolInitialized;
  Result := Pwl_touch(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SEAT_GET_TOUCH_OPCODE, wl_touch_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil)));
end;

procedure wl_seat_release(AProxy: Pwl_seat);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SEAT_RELEASE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wl_pointer_set_cursor(AProxy: Pwl_pointer; serial: LongWord; surface: Pwl_surface; hotspot_x: LongInt; hotspot_y: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_POINTER_SET_CURSOR_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, serial, surface, hotspot_x, hotspot_y);
end;

procedure wl_pointer_release(AProxy: Pwl_pointer);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_POINTER_RELEASE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wl_keyboard_release(AProxy: Pwl_keyboard);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_KEYBOARD_RELEASE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wl_touch_release(AProxy: Pwl_touch);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_TOUCH_RELEASE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wl_output_release(AProxy: Pwl_output);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_OUTPUT_RELEASE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wl_region_destroy(AProxy: Pwl_region);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_REGION_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wl_region_add(AProxy: Pwl_region; x: LongInt; y: LongInt; width: LongInt; height: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_REGION_ADD_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, x, y, width, height);
end;

procedure wl_region_subtract(AProxy: Pwl_region; x: LongInt; y: LongInt; width: LongInt; height: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_REGION_SUBTRACT_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, x, y, width, height);
end;

procedure wl_subcompositor_destroy(AProxy: Pwl_subcompositor);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SUBCOMPOSITOR_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

function wl_subcompositor_get_subsurface(AProxy: Pwl_subcompositor; surface: Pwl_surface; parent: Pwl_surface): Pwl_subsurface;
begin
  EnsureProtocolInitialized;
  Result := Pwl_subsurface(wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SUBCOMPOSITOR_GET_SUBSURFACE_OPCODE, wl_subsurface_interface, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, Pointer(nil), surface, parent));
end;

procedure wl_subsurface_destroy(AProxy: Pwl_subsurface);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SUBSURFACE_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wl_subsurface_set_position(AProxy: Pwl_subsurface; x: LongInt; y: LongInt);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SUBSURFACE_SET_POSITION_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, x, y);
end;

procedure wl_subsurface_place_above(AProxy: Pwl_subsurface; sibling: Pwl_surface);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SUBSURFACE_PLACE_ABOVE_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, sibling);
end;

procedure wl_subsurface_place_below(AProxy: Pwl_subsurface; sibling: Pwl_surface);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SUBSURFACE_PLACE_BELOW_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, sibling);
end;

procedure wl_subsurface_set_sync(AProxy: Pwl_subsurface);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SUBSURFACE_SET_SYNC_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure wl_subsurface_set_desync(AProxy: Pwl_subsurface);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_SUBSURFACE_SET_DESYNC_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0);
end;

procedure wl_fixes_destroy(AProxy: Pwl_fixes);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_FIXES_DESTROY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), WL_MARSHAL_FLAG_DESTROY);
end;

procedure wl_fixes_destroy_registry(AProxy: Pwl_fixes; registry: Pwl_registry);
begin
  EnsureProtocolInitialized;
  wl_proxy_marshal_flags(Pwl_proxy(AProxy), WL_FIXES_DESTROY_REGISTRY_OPCODE, nil, wl_proxy_get_version(Pwl_proxy(AProxy)), 0, registry);
end;

procedure EnsureProtocolInitialized;
begin
  if GInitialized then
    Exit;
  GInitialized := True;

  // コアプロトコルの記述子は libwayland-client が公開している。
  wl_display_interface := PMLWaylandResolve('wl_display_interface');
  wl_registry_interface := PMLWaylandResolve('wl_registry_interface');
  wl_callback_interface := PMLWaylandResolve('wl_callback_interface');
  wl_compositor_interface := PMLWaylandResolve('wl_compositor_interface');
  wl_shm_pool_interface := PMLWaylandResolve('wl_shm_pool_interface');
  wl_shm_interface := PMLWaylandResolve('wl_shm_interface');
  wl_buffer_interface := PMLWaylandResolve('wl_buffer_interface');
  wl_data_offer_interface := PMLWaylandResolve('wl_data_offer_interface');
  wl_data_source_interface := PMLWaylandResolve('wl_data_source_interface');
  wl_data_device_interface := PMLWaylandResolve('wl_data_device_interface');
  wl_data_device_manager_interface := PMLWaylandResolve('wl_data_device_manager_interface');
  wl_shell_interface := PMLWaylandResolve('wl_shell_interface');
  wl_shell_surface_interface := PMLWaylandResolve('wl_shell_surface_interface');
  wl_surface_interface := PMLWaylandResolve('wl_surface_interface');
  wl_seat_interface := PMLWaylandResolve('wl_seat_interface');
  wl_pointer_interface := PMLWaylandResolve('wl_pointer_interface');
  wl_keyboard_interface := PMLWaylandResolve('wl_keyboard_interface');
  wl_touch_interface := PMLWaylandResolve('wl_touch_interface');
  wl_output_interface := PMLWaylandResolve('wl_output_interface');
  wl_region_interface := PMLWaylandResolve('wl_region_interface');
  wl_subcompositor_interface := PMLWaylandResolve('wl_subcompositor_interface');
  wl_subsurface_interface := PMLWaylandResolve('wl_subsurface_interface');
  wl_fixes_interface := PMLWaylandResolve('wl_fixes_interface');
  GThunks_wl_display.error := @Thunk_wl_display_error;
  GThunks_wl_display.delete_id := @Thunk_wl_display_delete_id;
  GThunks_wl_registry.global := @Thunk_wl_registry_global;
  GThunks_wl_registry.global_remove := @Thunk_wl_registry_global_remove;
  GThunks_wl_callback.done := @Thunk_wl_callback_done;
  GThunks_wl_shm.format := @Thunk_wl_shm_format;
  GThunks_wl_buffer.release := @Thunk_wl_buffer_release;
  GThunks_wl_data_offer.offer := @Thunk_wl_data_offer_offer;
  GThunks_wl_data_offer.source_actions := @Thunk_wl_data_offer_source_actions;
  GThunks_wl_data_offer.action := @Thunk_wl_data_offer_action;
  GThunks_wl_data_source.target := @Thunk_wl_data_source_target;
  GThunks_wl_data_source.send := @Thunk_wl_data_source_send;
  GThunks_wl_data_source.cancelled := @Thunk_wl_data_source_cancelled;
  GThunks_wl_data_source.dnd_drop_performed := @Thunk_wl_data_source_dnd_drop_performed;
  GThunks_wl_data_source.dnd_finished := @Thunk_wl_data_source_dnd_finished;
  GThunks_wl_data_source.action := @Thunk_wl_data_source_action;
  GThunks_wl_data_device.data_offer := @Thunk_wl_data_device_data_offer;
  GThunks_wl_data_device.enter := @Thunk_wl_data_device_enter;
  GThunks_wl_data_device.leave := @Thunk_wl_data_device_leave;
  GThunks_wl_data_device.motion := @Thunk_wl_data_device_motion;
  GThunks_wl_data_device.drop := @Thunk_wl_data_device_drop;
  GThunks_wl_data_device.selection := @Thunk_wl_data_device_selection;
  GThunks_wl_shell_surface.ping := @Thunk_wl_shell_surface_ping;
  GThunks_wl_shell_surface.configure := @Thunk_wl_shell_surface_configure;
  GThunks_wl_shell_surface.popup_done := @Thunk_wl_shell_surface_popup_done;
  GThunks_wl_surface.enter := @Thunk_wl_surface_enter;
  GThunks_wl_surface.leave := @Thunk_wl_surface_leave;
  GThunks_wl_surface.preferred_buffer_scale := @Thunk_wl_surface_preferred_buffer_scale;
  GThunks_wl_surface.preferred_buffer_transform := @Thunk_wl_surface_preferred_buffer_transform;
  GThunks_wl_seat.capabilities := @Thunk_wl_seat_capabilities;
  GThunks_wl_seat.name := @Thunk_wl_seat_name;
  GThunks_wl_pointer.enter := @Thunk_wl_pointer_enter;
  GThunks_wl_pointer.leave := @Thunk_wl_pointer_leave;
  GThunks_wl_pointer.motion := @Thunk_wl_pointer_motion;
  GThunks_wl_pointer.button := @Thunk_wl_pointer_button;
  GThunks_wl_pointer.axis := @Thunk_wl_pointer_axis;
  GThunks_wl_pointer.frame := @Thunk_wl_pointer_frame;
  GThunks_wl_pointer.axis_source := @Thunk_wl_pointer_axis_source;
  GThunks_wl_pointer.axis_stop := @Thunk_wl_pointer_axis_stop;
  GThunks_wl_pointer.axis_discrete := @Thunk_wl_pointer_axis_discrete;
  GThunks_wl_pointer.axis_value120 := @Thunk_wl_pointer_axis_value120;
  GThunks_wl_pointer.axis_relative_direction := @Thunk_wl_pointer_axis_relative_direction;
  GThunks_wl_keyboard.keymap := @Thunk_wl_keyboard_keymap;
  GThunks_wl_keyboard.enter := @Thunk_wl_keyboard_enter;
  GThunks_wl_keyboard.leave := @Thunk_wl_keyboard_leave;
  GThunks_wl_keyboard.key := @Thunk_wl_keyboard_key;
  GThunks_wl_keyboard.modifiers := @Thunk_wl_keyboard_modifiers;
  GThunks_wl_keyboard.repeat_info := @Thunk_wl_keyboard_repeat_info;
  GThunks_wl_touch.down := @Thunk_wl_touch_down;
  GThunks_wl_touch.up := @Thunk_wl_touch_up;
  GThunks_wl_touch.motion := @Thunk_wl_touch_motion;
  GThunks_wl_touch.frame := @Thunk_wl_touch_frame;
  GThunks_wl_touch.cancel := @Thunk_wl_touch_cancel;
  GThunks_wl_touch.shape := @Thunk_wl_touch_shape;
  GThunks_wl_touch.orientation := @Thunk_wl_touch_orientation;
  GThunks_wl_output.geometry := @Thunk_wl_output_geometry;
  GThunks_wl_output.mode := @Thunk_wl_output_mode;
  GThunks_wl_output.done := @Thunk_wl_output_done;
  GThunks_wl_output.scale := @Thunk_wl_output_scale;
  GThunks_wl_output.name := @Thunk_wl_output_name;
  GThunks_wl_output.description := @Thunk_wl_output_description;
end;

end.
