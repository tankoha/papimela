{
  PaPiMeLa.Video.Wayland.Vulkan — Wayland の Vulkan 部品（VK_KHR_wayland_surface）

  Origin : partially ported from SDL (src/video/wayland/SDL_waylandvulkan.c)
           Scope: Wayland_Vulkan_GetInstanceExtensions（VK_KHR_surface と VK_KHR_wayland_surface）、
           Wayland_Vulkan_CreateSurface（wl_display と wl_surface を vkCreateWaylandSurfaceKHR へ）、
           Wayland_Vulkan_GetPresentationSupport（vkGetPhysicalDeviceWaylandPresentationSupportKHR）。
           移植しないもの: Wayland_Vulkan_LoadLibrary / UnloadLibrary / DestroySurface（ローダの読み込みと面の破棄は Video.Vulkan が持つ）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.4、§11 #77、#67

  WHAT:
    TPMLVulkanBackend の Wayland 実装。ネイティブディスプレイは wl_display、
    ネイティブの面は TPMLWaylandWindowBackend.Surface（wl_surface）。

  WHY:
    Vulkan の WSI（Mesa）は、渡された wl_surface へ自分でバッファを付けて commit する。
    papimela が行うのは、面を渡すことと、ウィンドウの役割（xdg_toplevel）の管理まで。

  RESOLVED:
    - 面を作る前に、ローダが読み込み済みかを見る（SDL は関数を引いてから確認している。
      未読み込みなら vkGetInstanceProcAddr が nil で落ちる順序）
    - 拡張が有効でないインスタンスなら、関数が引けず失敗する（SDL と同じ文言）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Wayland.Vulkan;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Platform.Vulkan,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video.Vulkan,
  PaPiMeLa.Video.Wayland.Types,
  PaPiMeLa.Video.Wayland.Window;

type
  TPMLWaylandVulkan = class(TPMLVulkanLoaderBackend)
  strict private
    FConn: TPMLWaylandConnection;
  strict protected
    function  RequiredExtensions: TPMLVulkanExtensionNames; override;
  public
    // AConn は部品より長生きしなければならない（wl_display を借りる）。
    constructor Create(AContextRef: TObject; AOwner: TPMLObject; AConn: TPMLWaylandConnection);

    function  CreateSurface(AWindow: TPMLWindowBackend; AInstance: VkInstance;
      AAllocator: PVkAllocationCallbacks; out ASurface: VkSurfaceKHR): Boolean; override;
    function  GetPresentationSupport(AInstance: VkInstance; APhysicalDevice: VkPhysicalDevice;
      AQueueFamilyIndex: LongWord): Boolean; override;
  end;

implementation

constructor TPMLWaylandVulkan.Create(AContextRef: TObject; AOwner: TPMLObject;
  AConn: TPMLWaylandConnection);
begin
  inherited Create(AContextRef, AOwner);
  FConn := AConn;
end;

function TPMLWaylandVulkan.RequiredExtensions: TPMLVulkanExtensionNames;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := VK_KHR_SURFACE_EXTENSION_NAME;
  Result[1] := VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME;
end;

function TPMLWaylandVulkan.CreateSurface(AWindow: TPMLWindowBackend; AInstance: VkInstance;
  AAllocator: PVkAllocationCallbacks; out ASurface: VkSurfaceKHR): Boolean;
var
  CreateFn: PFN_vkCreateWaylandSurfaceKHR;
  Info: TVkWaylandSurfaceCreateInfoKHR;
  Rc: VkResult;
begin
  Result := False;
  ASurface := 0;
  if not IsLoaded then
  begin
    FLastError := 'Vulkan is not loaded';
    Exit;
  end;
  if not (AWindow is TPMLWaylandWindowBackend) then
  begin
    FLastError := 'the window is not a Wayland window';
    Exit;
  end;
  Pointer(CreateFn) := Pointer(GetProc(AInstance, 'vkCreateWaylandSurfaceKHR'));
  if not Assigned(CreateFn) then
  begin
    FLastError := VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME + ' extension is not enabled in the Vulkan instance.';
    Exit;
  end;
  FillChar(Info, SizeOf(Info), 0);
  Info.sType := VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR;
  Info.pNext := nil;
  Info.flags := 0;
  Info.display := FConn.Display;
  Info.surface := TPMLWaylandWindowBackend(AWindow).Surface;
  Rc := CreateFn(AInstance, @Info, AAllocator, @ASurface);
  if Rc <> VK_SUCCESS then
  begin
    ASurface := 0;
    FLastError := 'vkCreateWaylandSurfaceKHR failed: ' + PMLVulkanResultString(Rc);
    Exit;
  end;
  Result := True;
end;

function TPMLWaylandVulkan.GetPresentationSupport(AInstance: VkInstance;
  APhysicalDevice: VkPhysicalDevice; AQueueFamilyIndex: LongWord): Boolean;
var
  Fn: PFN_vkGetPhysicalDeviceWaylandPresentationSupportKHR;
begin
  Result := False;
  if not IsLoaded then
  begin
    FLastError := 'Vulkan is not loaded';
    Exit;
  end;
  Pointer(Fn) := Pointer(GetProc(AInstance, 'vkGetPhysicalDeviceWaylandPresentationSupportKHR'));
  if not Assigned(Fn) then
  begin
    FLastError := VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME + ' extension is not enabled in the Vulkan instance.';
    Exit;
  end;
  Result := Fn(APhysicalDevice, AQueueFamilyIndex, FConn.Display) <> 0;
end;

end.
