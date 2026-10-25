{
  test_platform_vulkan — Vulkan の型・定数・関数表（PaPiMeLa.Platform.Vulkan）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    tools/genvulkan.bb が生成した型と表、その読み込みを確かめる。
      layout     全構造体・共用体の大きさと各フィールドの位置が、gcc が実物のヘッダで測った値と一致する
                 （期待値は tools/genvulkan.bb --layout が作る test/vulkan_layout.inc）
      constants  Vulkan の仕様で決まっている定数の値（生成物とは別に、仕様の値を手で書いた）
      macros     VK_MAKE_API_VERSION と取り出しの往復
      tables     偽の取得関数で、global 3・instance 20・device 73 の関数がちょうど要求される。
                 欠けた名前はカンマ区切りで返り、欠けた欄は nil
      loader     本物の libvulkan.so.1 があれば、global の 3 関数とインスタンス作成まで通ること
                 （無い環境では飛ばす。上の偽物の検査が本体）
}
program test_platform_vulkan;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, Classes, Math,
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Platform.Vulkan;

var
  Failures: Integer = 0;
  Requested: TStringList;
  MissingNames: TStringList;
  LayoutFailures: Integer = 0;

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

procedure CheckSize(const AName: String; AActual, AExpected: PtrUInt);
begin
  if AActual <> AExpected then
  begin
    WriteLn('  [FAIL] sizeof(', AName, ') = ', AActual, '（gcc: ', AExpected, '）');
    Inc(LayoutFailures);
  end;
end;

procedure CheckOffset(const AName: String; AActual, AExpected: PtrUInt);
begin
  if AActual <> AExpected then
  begin
    WriteLn('  [FAIL] offsetof(', AName, ') = ', AActual, '（gcc: ', AExpected, '）');
    Inc(LayoutFailures);
  end;
end;

{$I vulkan_layout.inc}

procedure Dummy; cdecl;
begin
end;

// 偽の取得関数: 要求された名前を記録し、MissingNames にあるものだけ nil を返す
function FakeGetInstanceProc(AInstance: VkInstance; AName: PAnsiChar): PFN_vkVoidFunction; cdecl;
begin
  Requested.Add(String(AName));
  if MissingNames.IndexOf(String(AName)) >= 0 then
    Result := nil
  else
    Result := PFN_vkVoidFunction(@Dummy);
end;

function FakeGetDeviceProc(ADevice: VkDevice; AName: PAnsiChar): PFN_vkVoidFunction; cdecl;
begin
  Requested.Add(String(AName));
  if MissingNames.IndexOf(String(AName)) >= 0 then
    Result := nil
  else
    Result := PFN_vkVoidFunction(@Dummy);
end;

procedure Reset;
begin
  Requested.Clear;
  MissingNames.Clear;
end;

function HasDuplicates: Boolean;
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.Sorted := True;
    S.Duplicates := dupError;
    try
      S.AddStrings(Requested);
      Result := False;
    except
      on E: EStringListError do
      begin
        WriteLn('    重複: ', E.Message);
        Result := True;
      end;
    end;
  finally
    S.Free;
  end;
end;

procedure LayoutSection;
begin
  WriteLn('1. 配置（gcc の実測との往復）');
  AllLayouts;
  Check(LayoutFailures = 0, Format('%d 個の構造体・共用体の大きさと位置が gcc と一致する', [LayoutCount]));
  Check(LayoutCount >= 90, '検査する構造体の数が少なすぎない');
end;

procedure ConstantsSection;
begin
  WriteLn('2. 定数（仕様の値）');
  Check(VK_SUCCESS = 0, 'VK_SUCCESS = 0');
  Check(VK_NOT_READY = 1, 'VK_NOT_READY = 1');
  Check(VK_TIMEOUT = 2, 'VK_TIMEOUT = 2');
  Check(VK_INCOMPLETE = 5, 'VK_INCOMPLETE = 5');
  Check(VK_ERROR_OUT_OF_HOST_MEMORY = -1, 'VK_ERROR_OUT_OF_HOST_MEMORY = -1（負）');
  Check(VK_ERROR_DEVICE_LOST = -4, 'VK_ERROR_DEVICE_LOST = -4');
  Check(VK_ERROR_OUT_OF_DATE_KHR = -1000001004, 'VK_ERROR_OUT_OF_DATE_KHR = -1000001004');
  Check(VK_SUBOPTIMAL_KHR = 1000001003, 'VK_SUBOPTIMAL_KHR = 1000001003');
  Check(VK_STRUCTURE_TYPE_APPLICATION_INFO = 0, 'VK_STRUCTURE_TYPE_APPLICATION_INFO = 0');
  Check(VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1, 'VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1');
  Check(VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR = 1000001000, 'VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR');
  Check(VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR = 1000006000, 'VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR');
  Check(VK_FORMAT_UNDEFINED = 0, 'VK_FORMAT_UNDEFINED = 0');
  Check(VK_FORMAT_R8G8B8A8_UNORM = 37, 'VK_FORMAT_R8G8B8A8_UNORM = 37');
  Check(VK_FORMAT_B8G8R8A8_UNORM = 44, 'VK_FORMAT_B8G8R8A8_UNORM = 44');
  Check(VK_FORMAT_B8G8R8A8_SRGB = 50, 'VK_FORMAT_B8G8R8A8_SRGB = 50');
  Check(VK_FORMAT_R16G16B16A16_SFLOAT = 97, 'VK_FORMAT_R16G16B16A16_SFLOAT = 97');
  Check(VK_IMAGE_LAYOUT_PRESENT_SRC_KHR = 1000001002, 'VK_IMAGE_LAYOUT_PRESENT_SRC_KHR');
  Check(VK_PRESENT_MODE_IMMEDIATE_KHR = 0, 'VK_PRESENT_MODE_IMMEDIATE_KHR = 0');
  Check(VK_PRESENT_MODE_MAILBOX_KHR = 1, 'VK_PRESENT_MODE_MAILBOX_KHR = 1');
  Check(VK_PRESENT_MODE_FIFO_KHR = 2, 'VK_PRESENT_MODE_FIFO_KHR = 2');
  Check(VK_PRESENT_MODE_FIFO_RELAXED_KHR = 3, 'VK_PRESENT_MODE_FIFO_RELAXED_KHR = 3');
  Check(VK_BLEND_FACTOR_ZERO = 0, 'VK_BLEND_FACTOR_ZERO = 0');
  Check(VK_BLEND_FACTOR_ONE = 1, 'VK_BLEND_FACTOR_ONE = 1');
  Check(VK_BLEND_OP_ADD = 0, 'VK_BLEND_OP_ADD = 0');
  Check(VK_BLEND_OP_MAX = 4, 'VK_BLEND_OP_MAX = 4');
  Check(VK_QUEUE_GRAPHICS_BIT = 1, 'VK_QUEUE_GRAPHICS_BIT = 1');
  Check(VK_IMAGE_USAGE_TRANSFER_SRC_BIT = 1, 'VK_IMAGE_USAGE_TRANSFER_SRC_BIT = 1');
  Check(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT = $10, 'VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT = $10');
  Check(VK_SHADER_STAGE_VERTEX_BIT = 1, 'VK_SHADER_STAGE_VERTEX_BIT = 1');
  Check(VK_SHADER_STAGE_FRAGMENT_BIT = $10, 'VK_SHADER_STAGE_FRAGMENT_BIT = $10');
  Check(VK_TRUE = 1, 'VK_TRUE = 1');
  Check(VK_FALSE = 0, 'VK_FALSE = 0');
  // ~0U（32 ビット）と ~0ULL（64 ビット）と ~2U。符号の落とし穴
  Check(VK_QUEUE_FAMILY_IGNORED = LongWord($FFFFFFFF), 'VK_QUEUE_FAMILY_IGNORED = ~0U');
  Check(VK_SUBPASS_EXTERNAL = LongWord($FFFFFFFF), 'VK_SUBPASS_EXTERNAL = ~0U');
  Check(VK_QUEUE_FAMILY_FOREIGN_EXT = LongWord($FFFFFFFD), 'VK_QUEUE_FAMILY_FOREIGN_EXT = ~2U');
  Check(VK_KHR_SWAPCHAIN_EXTENSION_NAME = 'VK_KHR_swapchain', '拡張名: VK_KHR_swapchain');
  Check(VK_KHR_SURFACE_EXTENSION_NAME = 'VK_KHR_surface', '拡張名: VK_KHR_surface');
  Check(VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME = 'VK_KHR_wayland_surface', '拡張名: VK_KHR_wayland_surface');
  Check(VK_KHR_MAINTENANCE1_EXTENSION_NAME = 'VK_KHR_maintenance1', '別名の拡張名: VK_KHR_MAINTENANCE1 → maintenance1');
  Check(VK_API_VERSION_1_0 = $400000, 'VK_API_VERSION_1_0 = 1 shl 22');
  // 別名の値は元と同じ
  Check(VK_CHROMA_LOCATION_COSITED_EVEN_KHR = 0, 'VK_CHROMA_LOCATION_COSITED_EVEN_KHR = 0');
  Check(VK_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_709_KHR = 2, 'VK_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_709_KHR = 2');
end;

procedure MacrosSection;
var
  V: LongWord;
begin
  WriteLn('3. バージョンのマクロ');
  V := VK_MAKE_API_VERSION(0, 1, 3, 250);
  Check(V = $1003 * 4096 * 0 + (1 shl 22) + (3 shl 12) + 250, 'VK_MAKE_API_VERSION(0,1,3,250)');
  Check((VK_API_VERSION_MAJOR(V) = 1) and (VK_API_VERSION_MINOR(V) = 3)
    and (VK_API_VERSION_PATCH(V) = 250) and (VK_API_VERSION_VARIANT(V) = 0), '取り出しが往復する');
  V := VK_MAKE_API_VERSION(2, 127, 1023, 4095);
  Check((VK_API_VERSION_VARIANT(V) = 2) and (VK_API_VERSION_MAJOR(V) = 127)
    and (VK_API_VERSION_MINOR(V) = 1023) and (VK_API_VERSION_PATCH(V) = 4095), '各欄の上限が隣へ漏れない');
end;

procedure TablesSection;
var
  G: TPMLVulkanGlobalFunctions;
  I: TPMLVulkanInstanceFunctions;
  D: TPMLVulkanDeviceFunctions;
  Missing: String;
begin
  WriteLn('4. 関数表（偽の取得関数）');
  Reset;
  Missing := PMLVulkanLoadGlobalFunctions(@FakeGetInstanceProc, G);
  Check((Missing = '') and (Requested.Count = 3) and not HasDuplicates,
    Format('global は 3 関数、重複なし、欠けなし（%d）', [Requested.Count]));
  Check(Requested.IndexOf('vkCreateInstance') >= 0, 'global に vkCreateInstance');
  Check(G.vkCreateInstance <> nil, '欄が埋まる');

  Reset;
  MissingNames.Add('vkCreateInstance');
  Missing := PMLVulkanLoadGlobalFunctions(@FakeGetInstanceProc, G);
  Check((Missing = 'vkCreateInstance') and (G.vkCreateInstance = nil)
    and (G.vkEnumerateInstanceExtensionProperties <> nil), '欠けた名前を返し、その欄だけ nil');

  Reset;
  Missing := PMLVulkanLoadInstanceFunctions(@FakeGetInstanceProc, nil, I);
  Check((Missing = '') and (Requested.Count = 20) and not HasDuplicates,
    Format('instance は 20 関数、重複なし（%d）', [Requested.Count]));
  Check(Requested.IndexOf('vkGetDeviceProcAddr') >= 0, 'instance に vkGetDeviceProcAddr');
  Check(Requested.IndexOf('vkGetInstanceProcAddr') < 0, 'vkGetInstanceProcAddr は表に入らない');
  Check(Requested.IndexOf('vkCreateWaylandSurfaceKHR') >= 0, 'instance に vkCreateWaylandSurfaceKHR');

  Reset;
  MissingNames.Add('vkGetPhysicalDeviceFeatures2KHR');
  MissingNames.Add('vkGetPhysicalDeviceProperties2KHR');
  Missing := PMLVulkanLoadInstanceFunctions(@FakeGetInstanceProc, nil, I);
  Check((Pos('vkGetPhysicalDeviceFeatures2KHR', Missing) > 0) and (Pos('vkGetPhysicalDeviceProperties2KHR', Missing) > 0)
    and (Pos(', ', Missing) > 0) and (I.vkEnumeratePhysicalDevices <> nil), '欠けた拡張の関数がカンマ区切りで返る');

  Reset;
  Missing := PMLVulkanLoadDeviceFunctions(@FakeGetDeviceProc, nil, D);
  Check((Missing = '') and (Requested.Count = 73) and not HasDuplicates,
    Format('device は 73 関数、重複なし（%d）', [Requested.Count]));
  Check(Requested.IndexOf('vkCmdDraw') >= 0, 'device に vkCmdDraw');
  Check(Requested.IndexOf('vkQueueSubmit') >= 0, 'device に vkQueueSubmit（第 1 引数が VkQueue）');
  Check(Requested.IndexOf('vkCreateSwapchainKHR') >= 0, 'device に vkCreateSwapchainKHR');
  Check(Requested.IndexOf('vkGetDeviceProcAddr') < 0, 'device に vkGetDeviceProcAddr は入らない');
  Check(D.vkQueuePresentKHR <> nil, '欄が埋まる');

  Check(SizeOf(TPMLVulkanGlobalFunctions) = 3 * SizeOf(Pointer), 'global の表は 3 ポインタ');
  Check(SizeOf(TPMLVulkanInstanceFunctions) = 20 * SizeOf(Pointer), 'instance の表は 20 ポインタ');
  Check(SizeOf(TPMLVulkanDeviceFunctions) = 73 * SizeOf(Pointer), 'device の表は 73 ポインタ');
end;

procedure LoaderSection;
var
  Lib: TPMLDynLib;
  GetProc: PFN_vkGetInstanceProcAddr;
  G: TPMLVulkanGlobalFunctions;
  Count: LongWord;
begin
  WriteLn('5. 本物のローダ（libvulkan.so.1）');
  if not TPMLDynLib.IsAvailable(['libvulkan.so.1', 'libvulkan.so']) then
  begin
    WriteLn('  [SKIP] libvulkan が無い（偽物の検査が本体）');
    Exit;
  end;
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  Lib := TPMLDynLib.Create(['libvulkan.so.1', 'libvulkan.so']);
  try
    GetProc := PFN_vkGetInstanceProcAddr(Lib.Resolve('vkGetInstanceProcAddr'));
    Check(PMLVulkanLoadGlobalFunctions(GetProc, G) = '', '本物のローダで global の 3 関数が引ける');
    Count := 0;
    Check(G.vkEnumerateInstanceExtensionProperties(nil, @Count, nil) = VK_SUCCESS, '拡張の数が引ける');
    Check(Count > 0, Format('インスタンスの拡張が 1 個以上ある（%d）', [Count]));
  finally
    Lib.Free;
  end;
end;

begin
  Requested := TStringList.Create;
  MissingNames := TStringList.Create;
  try
    WriteLn('test_platform_vulkan');
    LayoutSection;
    ConstantsSection;
    MacrosSection;
    TablesSection;
    LoaderSection;
  finally
    MissingNames.Free;
    Requested.Free;
  end;
  WriteLn;
  WriteLn('失敗: ', Failures);
  if Failures > 0 then
    Halt(1);
end.
