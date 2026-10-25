{
  test_vulkan_window — Wayland のウィンドウに Vulkan で描く（TPMLWindowOptions.Vulkan / VulkanCreateSurface）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    実機のコンポジタで、Vulkan の面とスワップチェーンを動かす。
    1. 前提（能力 Vulkan、ウィンドウの作成でローダが読まれる）
    2. インスタンス（VulkanInstanceExtensions の拡張つき）、物理デバイスの列挙（V3DV / lavapipe など全部）
    3. 物理デバイスごとに: presentation support（VulkanGetPresentationSupport）、面（VulkanCreateSurface）、
       面の能力・形式・present モード、論理デバイス、スワップチェーン、数フレームの
       acquire → 塗る（vkCmdClearColorImage）→ present
    4. 面の破棄（VulkanDestroySurface）、ウィンドウの破棄とローダの手放し、プロトコル違反なし
    5. Vulkan のフラグの無いウィンドウでは面を作れない（EPMLVideoError）

  WHY:
    Vulkan（#67）の段 2 の受け入れ検査。Platform.Vulkan が生成した型・関数表が、実物のドライバで
    スワップチェーンまで使えることの確認も兼ねる。コンポジタと GPU が相手なので CI では走らない
    （T-21 と同じく手元専用）。

  実行前提: Wayland セッションと Vulkan のローダ・ICD（Mesa の V3DV / lavapipe など）。
}
program test_vulkan_window;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland,
  PaPiMeLa.Platform.Vulkan,
  PaPiMeLa.Core;

var
  Failures: Integer = 0;
  Ctx: TPMLContext;

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

procedure Pump(AMs: Integer);
var
  T0: UInt64;
  Ev: TPMLEvent;
begin
  T0 := Ctx.Timer.TicksNS;
  repeat
    Ctx.Events.Pump(10);
    while Ctx.Events.Poll(Ev) do ;
  until (Ctx.Timer.TicksNS - T0) div 1000000 >= UInt64(AMs);
end;

function Ok(ARc: VkResult): Boolean;
begin
  Result := (ARc = VK_SUCCESS) or (ARc = VK_SUBOPTIMAL_KHR);
end;

function MakeBarrier(AImage: VkImage; AOld, ANew: VkImageLayout; ASrc, ADst: VkAccessFlags): TVkImageMemoryBarrier;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  Result.srcAccessMask := ASrc;
  Result.dstAccessMask := ADst;
  Result.oldLayout := AOld;
  Result.newLayout := ANew;
  Result.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Result.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Result.image := AImage;
  Result.subresourceRange.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
  Result.subresourceRange.levelCount := 1;
  Result.subresourceRange.layerCount := 1;
end;

{ 1 台の物理デバイスで、面からスワップチェーン・present まで。 }
procedure RunDevice(AWin: TPMLWindow; AInst: VkInstance; const I: TPMLVulkanInstanceFunctions;
  APhys: VkPhysicalDevice);
var
  Props: TVkPhysicalDeviceProperties;
  QCount, Q, GraphicsQ, FCount, MCount, ImgCount, ImgIdx, Frame, K: LongWord;
  QProps: array of TVkQueueFamilyProperties;
  Surface: VkSurfaceKHR;
  Supported: VkBool32;
  Caps: TVkSurfaceCapabilitiesKHR;
  Formats: array of TVkSurfaceFormatKHR;
  Modes: array of VkPresentModeKHR;
  Prio: Single;
  QInfo: TVkDeviceQueueCreateInfo;
  DInfo: TVkDeviceCreateInfo;
  DevExts: array[0..0] of PAnsiChar;
  Dev: VkDevice;
  D: TPMLVulkanDeviceFunctions;
  Queue: VkQueue;
  SInfo: TVkSwapchainCreateInfoKHR;
  Swap: VkSwapchainKHR;
  Images: array of VkImage;
  Extent: TVkExtent2D;
  Rc: VkResult;
  PoolInfo: TVkCommandPoolCreateInfo;
  Pool: VkCommandPool;
  AllocInfo: TVkCommandBufferAllocateInfo;
  Cmd: VkCommandBuffer;
  SemInfo: TVkSemaphoreCreateInfo;
  AcqSem, RelSem: VkSemaphore;
  FenceInfo: TVkFenceCreateInfo;
  Fence: VkFence;
  BeginInfo: TVkCommandBufferBeginInfo;
  B1, B2: TVkImageMemoryBarrier;
  Clear: TVkClearColorValue;
  Range: TVkImageSubresourceRange;
  Stage: VkPipelineStageFlags;
  Submit: TVkSubmitInfo;
  Present: TVkPresentInfoKHR;
  Missing: String;
  FramesOk, FifoOk: Boolean;
  Alpha: LongWord;
begin
  I.vkGetPhysicalDeviceProperties(APhys, @Props);
  WriteLn('--- ', PAnsiChar(@Props.deviceName[0]), '（API ', VK_API_VERSION_MAJOR(Props.apiVersion), '.',
    VK_API_VERSION_MINOR(Props.apiVersion), '）');

  QCount := 0;
  I.vkGetPhysicalDeviceQueueFamilyProperties(APhys, @QCount, nil);
  SetLength(QProps, QCount);
  I.vkGetPhysicalDeviceQueueFamilyProperties(APhys, @QCount, @QProps[0]);
  GraphicsQ := High(LongWord);
  for Q := 0 to QCount - 1 do
    if ((QProps[Q].queueFlags and VK_QUEUE_GRAPHICS_BIT) <> 0)
      and Ctx.Video.VulkanGetPresentationSupport(AInst, APhys, Q) then
    begin
      GraphicsQ := Q;
      Break;
    end;
  Check(GraphicsQ <> High(LongWord), 'グラフィックスで、Wayland へ出せるキューファミリがある（VulkanGetPresentationSupport）');
  if GraphicsQ = High(LongWord) then
    Exit;

  Surface := AWin.VulkanCreateSurface(AInst);
  Check(Surface <> 0, 'VulkanCreateSurface で面が作れる');
  try
    Supported := 0;
    Check(Ok(I.vkGetPhysicalDeviceSurfaceSupportKHR(APhys, GraphicsQ, Surface, @Supported)) and (Supported <> 0),
      'vkGetPhysicalDeviceSurfaceSupportKHR も「出せる」と答える');
    FillChar(Caps, SizeOf(Caps), 0);
    Check(I.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(APhys, Surface, @Caps) = VK_SUCCESS, '面の能力が引ける');
    FCount := 0;
    I.vkGetPhysicalDeviceSurfaceFormatsKHR(APhys, Surface, @FCount, nil);
    Check(FCount > 0, Format('面の形式がある（%d）', [FCount]));
    SetLength(Formats, FCount);
    I.vkGetPhysicalDeviceSurfaceFormatsKHR(APhys, Surface, @FCount, @Formats[0]);
    MCount := 0;
    I.vkGetPhysicalDeviceSurfacePresentModesKHR(APhys, Surface, @MCount, nil);
    SetLength(Modes, MCount);
    I.vkGetPhysicalDeviceSurfacePresentModesKHR(APhys, Surface, @MCount, @Modes[0]);
    FifoOk := False;
    for K := 0 to MCount - 1 do
      if Modes[K] = VK_PRESENT_MODE_FIFO_KHR then
        FifoOk := True;
    Check(FifoOk, 'FIFO の present モードがある（仕様で必須）');
    Check((Caps.supportedUsageFlags and VK_IMAGE_USAGE_TRANSFER_DST_BIT) <> 0, '画像を転送先に使える（塗るのに使う）');

    // 論理デバイス
    Prio := 1.0;
    FillChar(QInfo, SizeOf(QInfo), 0);
    QInfo.sType := VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    QInfo.queueFamilyIndex := GraphicsQ;
    QInfo.queueCount := 1;
    QInfo.pQueuePriorities := @Prio;
    DevExts[0] := VK_KHR_SWAPCHAIN_EXTENSION_NAME;
    FillChar(DInfo, SizeOf(DInfo), 0);
    DInfo.sType := VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    DInfo.queueCreateInfoCount := 1;
    DInfo.pQueueCreateInfos := @QInfo;
    DInfo.enabledExtensionCount := 1;
    DInfo.ppEnabledExtensionNames := @DevExts[0];
    Dev := nil;
    Rc := I.vkCreateDevice(APhys, @DInfo, nil, @Dev);
    Check((Rc = VK_SUCCESS) and (Dev <> nil), 'VK_KHR_swapchain 付きの論理デバイスが作れる');
    if Dev = nil then
      Exit;
    try
      Missing := PMLVulkanLoadDeviceFunctions(PFN_vkGetDeviceProcAddr(I.vkGetDeviceProcAddr), Dev, D);
      // YCbCr 変換の 2 つは VK_KHR_sampler_ycbcr_conversion を有効にしたデバイスでだけ引ける（SDL は条件つき）
      Check((Missing = '') or (Missing = 'vkCreateSamplerYcbcrConversionKHR, vkDestroySamplerYcbcrConversionKHR'),
        'device の関数が引ける（欠けてよいのは YCbCr 変換の 2 つだけ。欠け: ' + Missing + '）');
      Queue := nil;
      D.vkGetDeviceQueue(Dev, GraphicsQ, 0, @Queue);

      // スワップチェーン
      Extent.width := Caps.currentExtent.width;
      Extent.height := Caps.currentExtent.height;
      if Extent.width = LongWord($FFFFFFFF) then
      begin
        Extent.width := AWin.Width;
        Extent.height := AWin.Height;
      end;
      Alpha := VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
      if (Caps.supportedCompositeAlpha and Alpha) = 0 then
        Alpha := VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;
      FillChar(SInfo, SizeOf(SInfo), 0);
      SInfo.sType := VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
      SInfo.surface := Surface;
      SInfo.minImageCount := Max(Caps.minImageCount, 2);
      SInfo.imageFormat := Formats[0].format;
      SInfo.imageColorSpace := Formats[0].colorSpace;
      SInfo.imageExtent := Extent;
      SInfo.imageArrayLayers := 1;
      SInfo.imageUsage := VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT;
      SInfo.imageSharingMode := VK_SHARING_MODE_EXCLUSIVE;
      SInfo.preTransform := Caps.currentTransform;
      SInfo.compositeAlpha := Alpha;
      SInfo.presentMode := VK_PRESENT_MODE_FIFO_KHR;
      SInfo.clipped := VK_TRUE;
      Swap := 0;
      Rc := D.vkCreateSwapchainKHR(Dev, @SInfo, nil, @Swap);
      Check((Rc = VK_SUCCESS) and (Swap <> 0), Format('スワップチェーンが作れる（%dx%d）', [Extent.width, Extent.height]));
      if Swap = 0 then
        Exit;
      try
        ImgCount := 0;
        D.vkGetSwapchainImagesKHR(Dev, Swap, @ImgCount, nil);
        SetLength(Images, ImgCount);
        D.vkGetSwapchainImagesKHR(Dev, Swap, @ImgCount, @Images[0]);
        Check(ImgCount >= 2, Format('画像が 2 枚以上ある（%d）', [ImgCount]));

        FillChar(PoolInfo, SizeOf(PoolInfo), 0);
        PoolInfo.sType := VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
        PoolInfo.flags := VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        PoolInfo.queueFamilyIndex := GraphicsQ;
        Pool := 0;
        D.vkCreateCommandPool(Dev, @PoolInfo, nil, @Pool);
        FillChar(AllocInfo, SizeOf(AllocInfo), 0);
        AllocInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        AllocInfo.commandPool := Pool;
        AllocInfo.level := VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        AllocInfo.commandBufferCount := 1;
        Cmd := nil;
        D.vkAllocateCommandBuffers(Dev, @AllocInfo, @Cmd);
        FillChar(SemInfo, SizeOf(SemInfo), 0);
        SemInfo.sType := VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
        AcqSem := 0;
        RelSem := 0;
        D.vkCreateSemaphore(Dev, @SemInfo, nil, @AcqSem);
        D.vkCreateSemaphore(Dev, @SemInfo, nil, @RelSem);
        FillChar(FenceInfo, SizeOf(FenceInfo), 0);
        FenceInfo.sType := VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
        Fence := 0;
        D.vkCreateFence(Dev, @FenceInfo, nil, @Fence);
        try
          FramesOk := True;
          for Frame := 0 to 5 do
          begin
            ImgIdx := 0;
            Rc := D.vkAcquireNextImageKHR(Dev, Swap, High(QWord), AcqSem, 0, @ImgIdx);
            if not Ok(Rc) then
            begin
              WriteLn('    acquire: ', PMLVulkanResultString(Rc));
              FramesOk := False;
              Break;
            end;
            D.vkResetCommandBuffer(Cmd, 0);
            FillChar(BeginInfo, SizeOf(BeginInfo), 0);
            BeginInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
            D.vkBeginCommandBuffer(Cmd, @BeginInfo);
            B1 := MakeBarrier(Images[ImgIdx], VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
              0, VK_ACCESS_TRANSFER_WRITE_BIT);
            D.vkCmdPipelineBarrier(Cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0,
              0, nil, 0, nil, 1, @B1);
            FillChar(Clear, SizeOf(Clear), 0);
            Clear.float32[0] := (Frame mod 3) / 2.0;
            Clear.float32[1] := ((Frame + 1) mod 3) / 2.0;
            Clear.float32[2] := ((Frame + 2) mod 3) / 2.0;
            Clear.float32[3] := 1.0;
            FillChar(Range, SizeOf(Range), 0);
            Range.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
            Range.levelCount := 1;
            Range.layerCount := 1;
            D.vkCmdClearColorImage(Cmd, Images[ImgIdx], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, @Clear, 1, @Range);
            B2 := MakeBarrier(Images[ImgIdx], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
              VK_ACCESS_TRANSFER_WRITE_BIT, 0);
            D.vkCmdPipelineBarrier(Cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0,
              0, nil, 0, nil, 1, @B2);
            D.vkEndCommandBuffer(Cmd);
            Stage := VK_PIPELINE_STAGE_TRANSFER_BIT;
            FillChar(Submit, SizeOf(Submit), 0);
            Submit.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
            Submit.waitSemaphoreCount := 1;
            Submit.pWaitSemaphores := @AcqSem;
            Submit.pWaitDstStageMask := @Stage;
            Submit.commandBufferCount := 1;
            Submit.pCommandBuffers := @Cmd;
            Submit.signalSemaphoreCount := 1;
            Submit.pSignalSemaphores := @RelSem;
            if D.vkQueueSubmit(Queue, 1, @Submit, Fence) <> VK_SUCCESS then
            begin
              FramesOk := False;
              Break;
            end;
            FillChar(Present, SizeOf(Present), 0);
            Present.sType := VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
            Present.waitSemaphoreCount := 1;
            Present.pWaitSemaphores := @RelSem;
            Present.swapchainCount := 1;
            Present.pSwapchains := @Swap;
            Present.pImageIndices := @ImgIdx;
            Rc := D.vkQueuePresentKHR(Queue, @Present);
            if not Ok(Rc) then
            begin
              WriteLn('    present: ', PMLVulkanResultString(Rc));
              FramesOk := False;
              Break;
            end;
            D.vkWaitForFences(Dev, 1, @Fence, VK_TRUE, High(QWord));
            D.vkResetFences(Dev, 1, @Fence);
            Pump(30);
          end;
          Check(FramesOk, '6 フレーム、acquire → 塗る → submit → present が通る');
          D.vkDeviceWaitIdle(Dev);
        finally
          D.vkDestroyFence(Dev, Fence, nil);
          D.vkDestroySemaphore(Dev, RelSem, nil);
          D.vkDestroySemaphore(Dev, AcqSem, nil);
          D.vkFreeCommandBuffers(Dev, Pool, 1, @Cmd);
          D.vkDestroyCommandPool(Dev, Pool, nil);
        end;
      finally
        D.vkDestroySwapchainKHR(Dev, Swap, nil);
      end;
    finally
      D.vkDeviceWaitIdle(Dev);
      D.vkDestroyDevice(Dev, nil);
    end;
  finally
    Ctx.Video.VulkanDestroySurface(AInst, Surface, nil);
  end;
end;

procedure Run;
var
  Win, Plain: TPMLWindow;
  G: TPMLVulkanGlobalFunctions;
  I: TPMLVulkanInstanceFunctions;
  Exts: TPMLVulkanExtensionNames;
  Names: array of PAnsiChar;
  App: TVkApplicationInfo;
  ICI: TVkInstanceCreateInfo;
  Inst: VkInstance;
  Count, K: LongWord;
  Devs: array of VkPhysicalDevice;
  Rc: VkResult;
  Raised: Boolean;
  GetProc: PFN_vkGetInstanceProcAddr;
begin
  WriteLn('1. 前提');
  Check(TPMLVideoCapability.Vulkan in Ctx.Video.Capabilities, '能力 Vulkan がある');
  Plain := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('plain', 160, 100));
  Raised := False;
  GetProc := nil;
  try
    GetProc := Ctx.Video.VulkanGetInstanceProcAddr;
  except
    on EPMLVideoError do Raised := True;
  end;
  Check(Raised and not Assigned(GetProc), 'Vulkan のウィンドウが無い間は、ローダは読まれていない');
  Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('papimela Vulkan', 320, 240).Resizable.Vulkan);
  Check(TPMLWindowFlag.Vulkan in Win.Flags, 'ウィンドウに Vulkan のフラグがある');
  GetProc := Ctx.Video.VulkanGetInstanceProcAddr;
  Check(Assigned(GetProc), 'ウィンドウを作ると、ローダが読まれている');
  Pump(200);

  WriteLn('2. インスタンスと物理デバイス');
  Check(PMLVulkanLoadGlobalFunctions(GetProc, G) = '', 'global の関数が引ける');
  Exts := Ctx.Video.VulkanInstanceExtensions;
  Check((Length(Exts) = 2) and (Exts[0] = VK_KHR_SURFACE_EXTENSION_NAME)
    and (Exts[1] = VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME), 'インスタンスの拡張は surface と wayland_surface');
  SetLength(Names, Length(Exts));
  for K := 0 to High(Exts) do
    Names[K] := PAnsiChar(Exts[K]);
  FillChar(App, SizeOf(App), 0);
  App.sType := VK_STRUCTURE_TYPE_APPLICATION_INFO;
  App.pApplicationName := 'test_vulkan_window';
  App.apiVersion := VK_API_VERSION_1_0;
  FillChar(ICI, SizeOf(ICI), 0);
  ICI.sType := VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  ICI.pApplicationInfo := @App;
  ICI.enabledExtensionCount := Length(Names);
  ICI.ppEnabledExtensionNames := @Names[0];
  Inst := nil;
  Rc := G.vkCreateInstance(@ICI, nil, @Inst);
  Check((Rc = VK_SUCCESS) and (Inst <> nil), 'インスタンスが作れる（' + PMLVulkanResultString(Rc) + '）');
  if Inst = nil then
    Exit;
  try
    PMLVulkanLoadInstanceFunctions(GetProc, Inst, I);
    Count := 0;
    I.vkEnumeratePhysicalDevices(Inst, @Count, nil);
    Check(Count > 0, Format('物理デバイスが見える（%d）', [Count]));
    SetLength(Devs, Count);
    I.vkEnumeratePhysicalDevices(Inst, @Count, @Devs[0]);

    WriteLn('3. 物理デバイスごとに面からスワップチェーン、present まで');
    for K := 0 to Count - 1 do
      RunDevice(Win, Inst, I, Devs[K]);

    WriteLn('5. Vulkan のフラグの無いウィンドウ');
    Raised := False;
    try
      Plain.VulkanCreateSurface(Inst);
    except
      on EPMLVideoError do Raised := True;
    end;
    Check(Raised, '面は作れない（EPMLVideoError）');
    Raised := False;
    try
      Win.VulkanCreateSurface(nil);
    except
      on EPMLVideoError do Raised := True;
    end;
    Check(Raised, 'インスタンスが nil なら EPMLVideoError');
  finally
    I.vkDestroyInstance(Inst, nil);
  end;

  WriteLn('4. 破棄');
  Win.Free;
  Plain.Free;
  Raised := False;
  try
    Ctx.Video.VulkanGetInstanceProcAddr;
  except
    on EPMLVideoError do Raised := True;
  end;
  Check(Raised, 'Vulkan のウィンドウを壊すと、ローダが手放される');
  Ctx.Video.VulkanLoadLibrary;
  Check(Assigned(Ctx.Video.VulkanGetInstanceProcAddr), 'VulkanLoadLibrary で読み直せる');
  Ctx.Video.VulkanUnloadLibrary;
end;

begin
  WriteLn('test_vulkan_window');
  Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
  try
    if Ctx.Video.BackendName <> 'wayland' then
    begin
      WriteLn('Wayland ではない（', Ctx.Video.BackendName, '）。この検査は手元専用');
      Halt(1);
    end;
    Run;
  finally
    Ctx.Free;
  end;
  WriteLn;
  WriteLn('失敗: ', Failures);
  if Failures > 0 then
    Halt(1);
end.
