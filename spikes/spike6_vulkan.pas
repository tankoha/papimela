{
  spike6_vulkan — Vulkan を FPC から dlopen で使えるか、Wayland の窓から VkSurfaceKHR が作れるか

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    次を実測する。結果は spikes/RESULTS.md のスパイク 6。
      1. libvulkan.so.1 の dlopen と vkGetInstanceProcAddr（浮動小数点の例外を止めて）
      2. インスタンス（VK_KHR_surface + VK_KHR_wayland_surface）の作成と、物理デバイスの列挙
         （V3DV / lavapipe）
      3. キューファミリと、Wayland の presentation support
      4. wl_surface（役割なし）から vkCreateWaylandSurfaceKHR で VkSurfaceKHR を作り、
         能力・形式・present モードを引けるか
      5. VK_KHR_swapchain 付きの論理デバイスの作成
    構造体は手で書いた最小限。段 1 では生成器が元ヘッダから作る。

  WHY:
    Vulkan（#67）は、ローダ・ICD・Wayland の面が CI（bwrap の Ubuntu 24.04 + lavapipe）で動くことが前提。
    動かなければ計画を見直す。
}
program spike6_vulkan;

{$mode objfpc}{$H+}

uses
  SysUtils, Math,
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland,
  PaPiMeLa.Video.Wayland.Types;

const
  VK_SUCCESS = 0;
  VK_STRUCTURE_TYPE_APPLICATION_INFO = 0;
  VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1;
  VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO = 2;
  VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO = 3;
  VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR = 1000006000;
  VK_QUEUE_GRAPHICS_BIT = 1;
  VK_API_VERSION_1_1 = (1 shl 22) or (1 shl 12);

type
  VkResult = LongInt;
  PVkApplicationInfo = ^TVkApplicationInfo;
  TVkApplicationInfo = record
    sType: LongWord;
    pNext: Pointer;
    pApplicationName: PAnsiChar;
    applicationVersion: LongWord;
    pEngineName: PAnsiChar;
    engineVersion: LongWord;
    apiVersion: LongWord;
  end;
  TVkInstanceCreateInfo = record
    sType: LongWord;
    pNext: Pointer;
    flags: LongWord;
    pApplicationInfo: PVkApplicationInfo;
    enabledLayerCount: LongWord;
    ppEnabledLayerNames: PPAnsiChar;
    enabledExtensionCount: LongWord;
    ppEnabledExtensionNames: PPAnsiChar;
  end;
  TVkDeviceQueueCreateInfo = record
    sType: LongWord;
    pNext: Pointer;
    flags: LongWord;
    queueFamilyIndex: LongWord;
    queueCount: LongWord;
    pQueuePriorities: PSingle;
  end;
  TVkDeviceCreateInfo = record
    sType: LongWord;
    pNext: Pointer;
    flags: LongWord;
    queueCreateInfoCount: LongWord;
    pQueueCreateInfos: ^TVkDeviceQueueCreateInfo;
    enabledLayerCount: LongWord;
    ppEnabledLayerNames: PPAnsiChar;
    enabledExtensionCount: LongWord;
    ppEnabledExtensionNames: PPAnsiChar;
    pEnabledFeatures: Pointer;
  end;
  TVkQueueFamilyProperties = record
    queueFlags: LongWord;
    queueCount: LongWord;
    timestampValidBits: LongWord;
    granularity: array[0..2] of LongWord;
  end;
  // VkPhysicalDeviceProperties は limits を含んで大きいので、名前の欄までを読む
  TVkPhysicalDevicePropertiesBuf = record
    apiVersion, driverVersion, vendorID, deviceID, deviceType: LongWord;
    deviceName: array[0..255] of AnsiChar;
    rest: array[0..1023] of Byte;
  end;
  TVkWaylandSurfaceCreateInfoKHR = record
    sType: LongWord;
    pNext: Pointer;
    flags: LongWord;
    display: Pointer;
    surface: Pointer;
  end;
  TVkSurfaceCapabilitiesKHR = record
    minImageCount, maxImageCount: LongWord;
    currentExtent, minImageExtent, maxImageExtent: array[0..1] of LongWord;
    maxImageArrayLayers, supportedTransforms, currentTransform,
    supportedCompositeAlpha, supportedUsageFlags: LongWord;
  end;
  TVkSurfaceFormatKHR = record
    format, colorSpace: LongWord;
  end;

var
  vkGetInstanceProcAddr: function(AInstance: Pointer; AName: PAnsiChar): Pointer; cdecl;
  vkCreateInstance: function(const AInfo: TVkInstanceCreateInfo; AAlloc: Pointer; out AInstance: Pointer): VkResult; cdecl;
  vkDestroyInstance: procedure(AInstance: Pointer; AAlloc: Pointer); cdecl;
  vkEnumeratePhysicalDevices: function(AInstance: Pointer; var ACount: LongWord; ADevices: PPointer): VkResult; cdecl;
  vkGetPhysicalDeviceProperties: procedure(ADevice: Pointer; out AProps: TVkPhysicalDevicePropertiesBuf); cdecl;
  vkGetPhysicalDeviceQueueFamilyProperties: procedure(ADevice: Pointer; var ACount: LongWord; AProps: Pointer); cdecl;
  vkGetPhysicalDeviceWaylandPresentationSupportKHR: function(ADevice: Pointer; AQueueFamily: LongWord; ADisplay: Pointer): LongWord; cdecl;
  vkCreateWaylandSurfaceKHR: function(AInstance: Pointer; const AInfo: TVkWaylandSurfaceCreateInfoKHR; AAlloc: Pointer; out ASurface: QWord): VkResult; cdecl;
  vkDestroySurfaceKHR: procedure(AInstance: Pointer; ASurface: QWord; AAlloc: Pointer); cdecl;
  vkGetPhysicalDeviceSurfaceCapabilitiesKHR: function(ADevice: Pointer; ASurface: QWord; out ACaps: TVkSurfaceCapabilitiesKHR): VkResult; cdecl;
  vkGetPhysicalDeviceSurfaceFormatsKHR: function(ADevice: Pointer; ASurface: QWord; var ACount: LongWord; AFormats: Pointer): VkResult; cdecl;
  vkGetPhysicalDeviceSurfacePresentModesKHR: function(ADevice: Pointer; ASurface: QWord; var ACount: LongWord; AModes: Pointer): VkResult; cdecl;
  vkCreateDevice: function(ADevice: Pointer; const AInfo: TVkDeviceCreateInfo; AAlloc: Pointer; out ALogical: Pointer): VkResult; cdecl;
  vkDestroyDevice: procedure(ADevice: Pointer; AAlloc: Pointer); cdecl;

  Failures: Integer = 0;

procedure Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
    WriteLn('  [OK]   ', ALabel)
  else
  begin
    WriteLn('  [NG]   ', ALabel);
    Inc(Failures);
  end;
end;

function Inst(AInstance: Pointer; const AName: String): Pointer;
begin
  Result := vkGetInstanceProcAddr(AInstance, PAnsiChar(AName));
end;

procedure RunOneDevice(AInstance: Pointer; ADev: Pointer; ADisplay: Pointer; ASurface: QWord);
var
  Props: TVkPhysicalDevicePropertiesBuf;
  QCount, Q, FCount, MCount: LongWord;
  QProps: array of TVkQueueFamilyProperties;
  GraphicsQ: LongInt;
  Caps: TVkSurfaceCapabilitiesKHR;
  Formats: array of TVkSurfaceFormatKHR;
  Modes: array of LongWord;
  Prio: Single;
  QInfo: TVkDeviceQueueCreateInfo;
  DInfo: TVkDeviceCreateInfo;
  Exts: array[0..0] of PAnsiChar;
  Logical: Pointer;
  R: VkResult;
  Pres: LongWord;
  S: String;
  I: Integer;
begin
  vkGetPhysicalDeviceProperties(ADev, Props);
  WriteLn('  --- ', PAnsiChar(@Props.deviceName[0]), '  api=', Props.apiVersion shr 22, '.',
    (Props.apiVersion shr 12) and $3FF, '  type=', Props.deviceType);
  QCount := 0;
  vkGetPhysicalDeviceQueueFamilyProperties(ADev, QCount, nil);
  SetLength(QProps, QCount);
  if QCount > 0 then
    vkGetPhysicalDeviceQueueFamilyProperties(ADev, QCount, @QProps[0]);
  GraphicsQ := -1;
  for Q := 0 to QCount - 1 do
    if (GraphicsQ < 0) and ((QProps[Q].queueFlags and VK_QUEUE_GRAPHICS_BIT) <> 0) then
      GraphicsQ := Q;
  Check(GraphicsQ >= 0, 'グラフィックスのキューファミリがある（' + IntToStr(QCount) + ' 個中）');
  if GraphicsQ < 0 then Exit;
  if ASurface <> 0 then
  begin
  Pres := vkGetPhysicalDeviceWaylandPresentationSupportKHR(ADev, GraphicsQ, ADisplay);
  Check(Pres <> 0, 'Wayland の presentation support がある');

  Check(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(ADev, ASurface, Caps) = VK_SUCCESS,
    '面の能力が引ける');
  WriteLn('         minImages=', Caps.minImageCount, ' max=', Caps.maxImageCount,
    ' currentExtent=', Caps.currentExtent[0], 'x', Caps.currentExtent[1],
    ' usage=$', IntToHex(Caps.supportedUsageFlags, 2), ' alpha=$', IntToHex(Caps.supportedCompositeAlpha, 2));
  FCount := 0;
  R := vkGetPhysicalDeviceSurfaceFormatsKHR(ADev, ASurface, FCount, nil);
  Check((R = VK_SUCCESS) and (FCount > 0), '面の形式が引ける（' + IntToStr(FCount) + ' 個）');
  if FCount > 0 then
  begin
    SetLength(Formats, FCount);
    vkGetPhysicalDeviceSurfaceFormatsKHR(ADev, ASurface, FCount, @Formats[0]);
    S := '';
    for I := 0 to Min(FCount, 6) - 1 do
      S := S + Format(' %d/%d', [Formats[I].format, Formats[I].colorSpace]);
    WriteLn('         formats(format/colorspace):', S);
  end;
  MCount := 0;
  R := vkGetPhysicalDeviceSurfacePresentModesKHR(ADev, ASurface, MCount, nil);
  Check((R = VK_SUCCESS) and (MCount > 0), 'present モードが引ける（' + IntToStr(MCount) + ' 個）');
  if MCount > 0 then
  begin
    SetLength(Modes, MCount);
    vkGetPhysicalDeviceSurfacePresentModesKHR(ADev, ASurface, MCount, @Modes[0]);
    S := '';
    for I := 0 to MCount - 1 do
      S := S + ' ' + IntToStr(Modes[I]);
    WriteLn('         present modes:', S);
  end;
  end;

  // VK_KHR_swapchain 付きの論理デバイス
  Prio := 1.0;
  FillChar(QInfo, SizeOf(QInfo), 0);
  QInfo.sType := VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
  QInfo.queueFamilyIndex := GraphicsQ;
  QInfo.queueCount := 1;
  QInfo.pQueuePriorities := @Prio;
  Exts[0] := 'VK_KHR_swapchain';
  FillChar(DInfo, SizeOf(DInfo), 0);
  DInfo.sType := VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
  DInfo.queueCreateInfoCount := 1;
  DInfo.pQueueCreateInfos := @QInfo;
  DInfo.enabledExtensionCount := 1;
  DInfo.ppEnabledExtensionNames := @Exts[0];
  Logical := nil;
  R := vkCreateDevice(ADev, DInfo, nil, Logical);
  Check((R = VK_SUCCESS) and (Logical <> nil), 'VK_KHR_swapchain 付きの論理デバイスが作れる（VkResult=' + IntToStr(R) + '）');
  if Logical <> nil then
    vkDestroyDevice(Logical, nil);
end;

var
  Lib: TPMLDynLib;
  Conn: TPMLWaylandConnection;
  Surf: Pwl_surface;
  App: TVkApplicationInfo;
  ICI: TVkInstanceCreateInfo;
  IExts: array[0..1] of PAnsiChar;
  Instance: Pointer;
  Count, D: LongWord;
  Devs: array of Pointer;
  R: VkResult;
  SInfo: TVkWaylandSurfaceCreateInfoKHR;
  VkSurface: QWord;
  HaveWayland: Boolean;
begin
  WriteLn('spike6_vulkan');
  // C の ICD は浮動小数点の例外が無効であることを前提にしている（D-40）
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);

  Lib := TPMLDynLib.Create(['libvulkan.so.1', 'libvulkan.so']);
  Pointer(vkGetInstanceProcAddr) := Lib.Resolve('vkGetInstanceProcAddr');
  Check(vkGetInstanceProcAddr <> nil, 'libvulkan.so.1 を開いて vkGetInstanceProcAddr が引ける');
  Pointer(vkCreateInstance) := Inst(nil, 'vkCreateInstance');
  Check(vkCreateInstance <> nil, 'インスタンス無しで vkCreateInstance が引ける');

  Conn := TPMLWaylandConnection.Create;
  HaveWayland := Conn.Connect;
  if not HaveWayland then
    WriteLn('  [--]   Wayland に繋がらない（面の区間は飛ばす。CI はこちら）');

  FillChar(App, SizeOf(App), 0);
  App.sType := VK_STRUCTURE_TYPE_APPLICATION_INFO;
  App.pApplicationName := 'spike6';
  App.apiVersion := VK_API_VERSION_1_1;
  IExts[0] := 'VK_KHR_surface';
  IExts[1] := 'VK_KHR_wayland_surface';
  FillChar(ICI, SizeOf(ICI), 0);
  ICI.sType := VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  ICI.pApplicationInfo := @App;
  ICI.enabledExtensionCount := 2;
  ICI.ppEnabledExtensionNames := @IExts[0];
  Instance := nil;
  R := vkCreateInstance(ICI, nil, Instance);
  Check((R = VK_SUCCESS) and (Instance <> nil), 'インスタンスが作れる（VkResult=' + IntToStr(R) + '）');
  if Instance = nil then Halt(1);

  Pointer(vkDestroyInstance) := Inst(Instance, 'vkDestroyInstance');
  Pointer(vkEnumeratePhysicalDevices) := Inst(Instance, 'vkEnumeratePhysicalDevices');
  Pointer(vkGetPhysicalDeviceProperties) := Inst(Instance, 'vkGetPhysicalDeviceProperties');
  Pointer(vkGetPhysicalDeviceQueueFamilyProperties) := Inst(Instance, 'vkGetPhysicalDeviceQueueFamilyProperties');
  Pointer(vkGetPhysicalDeviceWaylandPresentationSupportKHR) := Inst(Instance, 'vkGetPhysicalDeviceWaylandPresentationSupportKHR');
  Pointer(vkCreateWaylandSurfaceKHR) := Inst(Instance, 'vkCreateWaylandSurfaceKHR');
  Pointer(vkDestroySurfaceKHR) := Inst(Instance, 'vkDestroySurfaceKHR');
  Pointer(vkGetPhysicalDeviceSurfaceCapabilitiesKHR) := Inst(Instance, 'vkGetPhysicalDeviceSurfaceCapabilitiesKHR');
  Pointer(vkGetPhysicalDeviceSurfaceFormatsKHR) := Inst(Instance, 'vkGetPhysicalDeviceSurfaceFormatsKHR');
  Pointer(vkGetPhysicalDeviceSurfacePresentModesKHR) := Inst(Instance, 'vkGetPhysicalDeviceSurfacePresentModesKHR');
  Pointer(vkCreateDevice) := Inst(Instance, 'vkCreateDevice');
  Pointer(vkDestroyDevice) := Inst(Instance, 'vkDestroyDevice');

  Count := 0;
  R := vkEnumeratePhysicalDevices(Instance, Count, nil);
  Check((R = VK_SUCCESS) and (Count > 0), '物理デバイスが見える（' + IntToStr(Count) + ' 個）');

  VkSurface := 0;
  if HaveWayland then
  begin
    Surf := wl_compositor_create_surface(Conn.Compositor);
    FillChar(SInfo, SizeOf(SInfo), 0);
    SInfo.sType := VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR;
    SInfo.display := Conn.Display;
    SInfo.surface := Surf;
    R := vkCreateWaylandSurfaceKHR(Instance, SInfo, nil, VkSurface);
    Check((R = VK_SUCCESS) and (VkSurface <> 0), '役割の無い wl_surface から VkSurfaceKHR が作れる（VkResult=' + IntToStr(R) + '）');
  end;

  if Count > 0 then
  begin
    SetLength(Devs, Count);
    vkEnumeratePhysicalDevices(Instance, Count, @Devs[0]);
    for D := 0 to Count - 1 do
      RunOneDevice(Instance, Devs[D], Conn.Display, VkSurface);
  end;

  if VkSurface <> 0 then
    vkDestroySurfaceKHR(Instance, VkSurface, nil);
  vkDestroyInstance(Instance, nil);
  if HaveWayland then
    Conn.Disconnect;
  Conn.Free;
  WriteLn;
  WriteLn('失敗: ', Failures);
  if Failures > 0 then
    Halt(1);
end.
