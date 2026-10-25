{ test/vulkan_layout.inc — tools/genvulkan.bb --layout が作る。手で直さない。
  Vulkan の構造体と共用体の大きさと各フィールドの位置。gcc が reference/SDL/src/video/khronos/vulkan のヘッダで測った実物。
  Pascal の record の配置との往復検査（test/test_platform_vulkan.pas）の期待値。 }
procedure Layout_VkAllocationCallbacks;
var
  V: TVkAllocationCallbacks;
begin
  CheckSize('TVkAllocationCallbacks', SizeOf(V), 48);
  CheckOffset('TVkAllocationCallbacks.pUserData', PtrUInt(@V.pUserData) - PtrUInt(@V), 0);
  CheckOffset('TVkAllocationCallbacks.pfnAllocation', PtrUInt(@V.pfnAllocation) - PtrUInt(@V), 8);
  CheckOffset('TVkAllocationCallbacks.pfnReallocation', PtrUInt(@V.pfnReallocation) - PtrUInt(@V), 16);
  CheckOffset('TVkAllocationCallbacks.pfnFree', PtrUInt(@V.pfnFree) - PtrUInt(@V), 24);
  CheckOffset('TVkAllocationCallbacks.pfnInternalAllocation', PtrUInt(@V.pfnInternalAllocation) - PtrUInt(@V), 32);
  CheckOffset('TVkAllocationCallbacks.pfnInternalFree', PtrUInt(@V.pfnInternalFree) - PtrUInt(@V), 40);
end;

procedure Layout_VkApplicationInfo;
var
  V: TVkApplicationInfo;
begin
  CheckSize('TVkApplicationInfo', SizeOf(V), 48);
  CheckOffset('TVkApplicationInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkApplicationInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkApplicationInfo.pApplicationName', PtrUInt(@V.pApplicationName) - PtrUInt(@V), 16);
  CheckOffset('TVkApplicationInfo.applicationVersion', PtrUInt(@V.applicationVersion) - PtrUInt(@V), 24);
  CheckOffset('TVkApplicationInfo.pEngineName', PtrUInt(@V.pEngineName) - PtrUInt(@V), 32);
  CheckOffset('TVkApplicationInfo.engineVersion', PtrUInt(@V.engineVersion) - PtrUInt(@V), 40);
  CheckOffset('TVkApplicationInfo.apiVersion', PtrUInt(@V.apiVersion) - PtrUInt(@V), 44);
end;

procedure Layout_VkAttachmentDescription;
var
  V: TVkAttachmentDescription;
begin
  CheckSize('TVkAttachmentDescription', SizeOf(V), 36);
  CheckOffset('TVkAttachmentDescription.flags', PtrUInt(@V.flags) - PtrUInt(@V), 0);
  CheckOffset('TVkAttachmentDescription.format', PtrUInt(@V.format) - PtrUInt(@V), 4);
  CheckOffset('TVkAttachmentDescription.samples', PtrUInt(@V.samples) - PtrUInt(@V), 8);
  CheckOffset('TVkAttachmentDescription.loadOp', PtrUInt(@V.loadOp) - PtrUInt(@V), 12);
  CheckOffset('TVkAttachmentDescription.storeOp', PtrUInt(@V.storeOp) - PtrUInt(@V), 16);
  CheckOffset('TVkAttachmentDescription.stencilLoadOp', PtrUInt(@V.stencilLoadOp) - PtrUInt(@V), 20);
  CheckOffset('TVkAttachmentDescription.stencilStoreOp', PtrUInt(@V.stencilStoreOp) - PtrUInt(@V), 24);
  CheckOffset('TVkAttachmentDescription.initialLayout', PtrUInt(@V.initialLayout) - PtrUInt(@V), 28);
  CheckOffset('TVkAttachmentDescription.finalLayout', PtrUInt(@V.finalLayout) - PtrUInt(@V), 32);
end;

procedure Layout_VkAttachmentReference;
var
  V: TVkAttachmentReference;
begin
  CheckSize('TVkAttachmentReference', SizeOf(V), 8);
  CheckOffset('TVkAttachmentReference.attachment', PtrUInt(@V.attachment) - PtrUInt(@V), 0);
  CheckOffset('TVkAttachmentReference.layout', PtrUInt(@V.layout) - PtrUInt(@V), 4);
end;

procedure Layout_VkBufferCreateInfo;
var
  V: TVkBufferCreateInfo;
begin
  CheckSize('TVkBufferCreateInfo', SizeOf(V), 56);
  CheckOffset('TVkBufferCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkBufferCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkBufferCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkBufferCreateInfo.size', PtrUInt(@V.size) - PtrUInt(@V), 24);
  CheckOffset('TVkBufferCreateInfo.usage', PtrUInt(@V.usage) - PtrUInt(@V), 32);
  CheckOffset('TVkBufferCreateInfo.sharingMode', PtrUInt(@V.sharingMode) - PtrUInt(@V), 36);
  CheckOffset('TVkBufferCreateInfo.queueFamilyIndexCount', PtrUInt(@V.queueFamilyIndexCount) - PtrUInt(@V), 40);
  CheckOffset('TVkBufferCreateInfo.pQueueFamilyIndices', PtrUInt(@V.pQueueFamilyIndices) - PtrUInt(@V), 48);
end;

procedure Layout_VkBufferImageCopy;
var
  V: TVkBufferImageCopy;
begin
  CheckSize('TVkBufferImageCopy', SizeOf(V), 56);
  CheckOffset('TVkBufferImageCopy.bufferOffset', PtrUInt(@V.bufferOffset) - PtrUInt(@V), 0);
  CheckOffset('TVkBufferImageCopy.bufferRowLength', PtrUInt(@V.bufferRowLength) - PtrUInt(@V), 8);
  CheckOffset('TVkBufferImageCopy.bufferImageHeight', PtrUInt(@V.bufferImageHeight) - PtrUInt(@V), 12);
  CheckOffset('TVkBufferImageCopy.imageSubresource', PtrUInt(@V.imageSubresource) - PtrUInt(@V), 16);
  CheckOffset('TVkBufferImageCopy.imageOffset', PtrUInt(@V.imageOffset) - PtrUInt(@V), 32);
  CheckOffset('TVkBufferImageCopy.imageExtent', PtrUInt(@V.imageExtent) - PtrUInt(@V), 44);
end;

procedure Layout_VkBufferMemoryBarrier;
var
  V: TVkBufferMemoryBarrier;
begin
  CheckSize('TVkBufferMemoryBarrier', SizeOf(V), 56);
  CheckOffset('TVkBufferMemoryBarrier.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkBufferMemoryBarrier.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkBufferMemoryBarrier.srcAccessMask', PtrUInt(@V.srcAccessMask) - PtrUInt(@V), 16);
  CheckOffset('TVkBufferMemoryBarrier.dstAccessMask', PtrUInt(@V.dstAccessMask) - PtrUInt(@V), 20);
  CheckOffset('TVkBufferMemoryBarrier.srcQueueFamilyIndex', PtrUInt(@V.srcQueueFamilyIndex) - PtrUInt(@V), 24);
  CheckOffset('TVkBufferMemoryBarrier.dstQueueFamilyIndex', PtrUInt(@V.dstQueueFamilyIndex) - PtrUInt(@V), 28);
  CheckOffset('TVkBufferMemoryBarrier.buffer', PtrUInt(@V.buffer) - PtrUInt(@V), 32);
  CheckOffset('TVkBufferMemoryBarrier.offset', PtrUInt(@V.offset) - PtrUInt(@V), 40);
  CheckOffset('TVkBufferMemoryBarrier.size', PtrUInt(@V.size) - PtrUInt(@V), 48);
end;

procedure Layout_VkClearColorValue;
var
  V: TVkClearColorValue;
begin
  CheckSize('TVkClearColorValue', SizeOf(V), 16);
  CheckOffset('TVkClearColorValue.float32', PtrUInt(@V.float32) - PtrUInt(@V), 0);
  CheckOffset('TVkClearColorValue.int32', PtrUInt(@V.int32) - PtrUInt(@V), 0);
  CheckOffset('TVkClearColorValue.uint32', PtrUInt(@V.uint32) - PtrUInt(@V), 0);
end;

procedure Layout_VkClearDepthStencilValue;
var
  V: TVkClearDepthStencilValue;
begin
  CheckSize('TVkClearDepthStencilValue', SizeOf(V), 8);
  CheckOffset('TVkClearDepthStencilValue.depth', PtrUInt(@V.depth) - PtrUInt(@V), 0);
  CheckOffset('TVkClearDepthStencilValue.stencil', PtrUInt(@V.stencil) - PtrUInt(@V), 4);
end;

procedure Layout_VkClearValue;
var
  V: TVkClearValue;
begin
  CheckSize('TVkClearValue', SizeOf(V), 16);
  CheckOffset('TVkClearValue.color', PtrUInt(@V.color) - PtrUInt(@V), 0);
  CheckOffset('TVkClearValue.depthStencil', PtrUInt(@V.depthStencil) - PtrUInt(@V), 0);
end;

procedure Layout_VkCommandBufferAllocateInfo;
var
  V: TVkCommandBufferAllocateInfo;
begin
  CheckSize('TVkCommandBufferAllocateInfo', SizeOf(V), 32);
  CheckOffset('TVkCommandBufferAllocateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkCommandBufferAllocateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkCommandBufferAllocateInfo.commandPool', PtrUInt(@V.commandPool) - PtrUInt(@V), 16);
  CheckOffset('TVkCommandBufferAllocateInfo.level', PtrUInt(@V.level) - PtrUInt(@V), 24);
  CheckOffset('TVkCommandBufferAllocateInfo.commandBufferCount', PtrUInt(@V.commandBufferCount) - PtrUInt(@V), 28);
end;

procedure Layout_VkCommandBufferBeginInfo;
var
  V: TVkCommandBufferBeginInfo;
begin
  CheckSize('TVkCommandBufferBeginInfo', SizeOf(V), 32);
  CheckOffset('TVkCommandBufferBeginInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkCommandBufferBeginInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkCommandBufferBeginInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkCommandBufferBeginInfo.pInheritanceInfo', PtrUInt(@V.pInheritanceInfo) - PtrUInt(@V), 24);
end;

procedure Layout_VkCommandBufferInheritanceInfo;
var
  V: TVkCommandBufferInheritanceInfo;
begin
  CheckSize('TVkCommandBufferInheritanceInfo', SizeOf(V), 56);
  CheckOffset('TVkCommandBufferInheritanceInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkCommandBufferInheritanceInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkCommandBufferInheritanceInfo.renderPass', PtrUInt(@V.renderPass) - PtrUInt(@V), 16);
  CheckOffset('TVkCommandBufferInheritanceInfo.subpass', PtrUInt(@V.subpass) - PtrUInt(@V), 24);
  CheckOffset('TVkCommandBufferInheritanceInfo.framebuffer', PtrUInt(@V.framebuffer) - PtrUInt(@V), 32);
  CheckOffset('TVkCommandBufferInheritanceInfo.occlusionQueryEnable', PtrUInt(@V.occlusionQueryEnable) - PtrUInt(@V), 40);
  CheckOffset('TVkCommandBufferInheritanceInfo.queryFlags', PtrUInt(@V.queryFlags) - PtrUInt(@V), 44);
  CheckOffset('TVkCommandBufferInheritanceInfo.pipelineStatistics', PtrUInt(@V.pipelineStatistics) - PtrUInt(@V), 48);
end;

procedure Layout_VkCommandPoolCreateInfo;
var
  V: TVkCommandPoolCreateInfo;
begin
  CheckSize('TVkCommandPoolCreateInfo', SizeOf(V), 24);
  CheckOffset('TVkCommandPoolCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkCommandPoolCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkCommandPoolCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkCommandPoolCreateInfo.queueFamilyIndex', PtrUInt(@V.queueFamilyIndex) - PtrUInt(@V), 20);
end;

procedure Layout_VkComponentMapping;
var
  V: TVkComponentMapping;
begin
  CheckSize('TVkComponentMapping', SizeOf(V), 16);
  CheckOffset('TVkComponentMapping.r', PtrUInt(@V.r) - PtrUInt(@V), 0);
  CheckOffset('TVkComponentMapping.g', PtrUInt(@V.g) - PtrUInt(@V), 4);
  CheckOffset('TVkComponentMapping.b', PtrUInt(@V.b) - PtrUInt(@V), 8);
  CheckOffset('TVkComponentMapping.a', PtrUInt(@V.a) - PtrUInt(@V), 12);
end;

procedure Layout_VkCopyDescriptorSet;
var
  V: TVkCopyDescriptorSet;
begin
  CheckSize('TVkCopyDescriptorSet', SizeOf(V), 56);
  CheckOffset('TVkCopyDescriptorSet.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkCopyDescriptorSet.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkCopyDescriptorSet.srcSet', PtrUInt(@V.srcSet) - PtrUInt(@V), 16);
  CheckOffset('TVkCopyDescriptorSet.srcBinding', PtrUInt(@V.srcBinding) - PtrUInt(@V), 24);
  CheckOffset('TVkCopyDescriptorSet.srcArrayElement', PtrUInt(@V.srcArrayElement) - PtrUInt(@V), 28);
  CheckOffset('TVkCopyDescriptorSet.dstSet', PtrUInt(@V.dstSet) - PtrUInt(@V), 32);
  CheckOffset('TVkCopyDescriptorSet.dstBinding', PtrUInt(@V.dstBinding) - PtrUInt(@V), 40);
  CheckOffset('TVkCopyDescriptorSet.dstArrayElement', PtrUInt(@V.dstArrayElement) - PtrUInt(@V), 44);
  CheckOffset('TVkCopyDescriptorSet.descriptorCount', PtrUInt(@V.descriptorCount) - PtrUInt(@V), 48);
end;

procedure Layout_VkDescriptorBufferInfo;
var
  V: TVkDescriptorBufferInfo;
begin
  CheckSize('TVkDescriptorBufferInfo', SizeOf(V), 24);
  CheckOffset('TVkDescriptorBufferInfo.buffer', PtrUInt(@V.buffer) - PtrUInt(@V), 0);
  CheckOffset('TVkDescriptorBufferInfo.offset', PtrUInt(@V.offset) - PtrUInt(@V), 8);
  CheckOffset('TVkDescriptorBufferInfo.range', PtrUInt(@V.range) - PtrUInt(@V), 16);
end;

procedure Layout_VkDescriptorImageInfo;
var
  V: TVkDescriptorImageInfo;
begin
  CheckSize('TVkDescriptorImageInfo', SizeOf(V), 24);
  CheckOffset('TVkDescriptorImageInfo.sampler', PtrUInt(@V.sampler) - PtrUInt(@V), 0);
  CheckOffset('TVkDescriptorImageInfo.imageView', PtrUInt(@V.imageView) - PtrUInt(@V), 8);
  CheckOffset('TVkDescriptorImageInfo.imageLayout', PtrUInt(@V.imageLayout) - PtrUInt(@V), 16);
end;

procedure Layout_VkDescriptorPoolCreateInfo;
var
  V: TVkDescriptorPoolCreateInfo;
begin
  CheckSize('TVkDescriptorPoolCreateInfo', SizeOf(V), 40);
  CheckOffset('TVkDescriptorPoolCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkDescriptorPoolCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkDescriptorPoolCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkDescriptorPoolCreateInfo.maxSets', PtrUInt(@V.maxSets) - PtrUInt(@V), 20);
  CheckOffset('TVkDescriptorPoolCreateInfo.poolSizeCount', PtrUInt(@V.poolSizeCount) - PtrUInt(@V), 24);
  CheckOffset('TVkDescriptorPoolCreateInfo.pPoolSizes', PtrUInt(@V.pPoolSizes) - PtrUInt(@V), 32);
end;

procedure Layout_VkDescriptorPoolSize;
var
  V: TVkDescriptorPoolSize;
begin
  CheckSize('TVkDescriptorPoolSize', SizeOf(V), 8);
  CheckOffset('TVkDescriptorPoolSize.type_', PtrUInt(@V.type_) - PtrUInt(@V), 0);
  CheckOffset('TVkDescriptorPoolSize.descriptorCount', PtrUInt(@V.descriptorCount) - PtrUInt(@V), 4);
end;

procedure Layout_VkDescriptorSetAllocateInfo;
var
  V: TVkDescriptorSetAllocateInfo;
begin
  CheckSize('TVkDescriptorSetAllocateInfo', SizeOf(V), 40);
  CheckOffset('TVkDescriptorSetAllocateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkDescriptorSetAllocateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkDescriptorSetAllocateInfo.descriptorPool', PtrUInt(@V.descriptorPool) - PtrUInt(@V), 16);
  CheckOffset('TVkDescriptorSetAllocateInfo.descriptorSetCount', PtrUInt(@V.descriptorSetCount) - PtrUInt(@V), 24);
  CheckOffset('TVkDescriptorSetAllocateInfo.pSetLayouts', PtrUInt(@V.pSetLayouts) - PtrUInt(@V), 32);
end;

procedure Layout_VkDescriptorSetLayoutBinding;
var
  V: TVkDescriptorSetLayoutBinding;
begin
  CheckSize('TVkDescriptorSetLayoutBinding', SizeOf(V), 24);
  CheckOffset('TVkDescriptorSetLayoutBinding.binding', PtrUInt(@V.binding) - PtrUInt(@V), 0);
  CheckOffset('TVkDescriptorSetLayoutBinding.descriptorType', PtrUInt(@V.descriptorType) - PtrUInt(@V), 4);
  CheckOffset('TVkDescriptorSetLayoutBinding.descriptorCount', PtrUInt(@V.descriptorCount) - PtrUInt(@V), 8);
  CheckOffset('TVkDescriptorSetLayoutBinding.stageFlags', PtrUInt(@V.stageFlags) - PtrUInt(@V), 12);
  CheckOffset('TVkDescriptorSetLayoutBinding.pImmutableSamplers', PtrUInt(@V.pImmutableSamplers) - PtrUInt(@V), 16);
end;

procedure Layout_VkDescriptorSetLayoutCreateInfo;
var
  V: TVkDescriptorSetLayoutCreateInfo;
begin
  CheckSize('TVkDescriptorSetLayoutCreateInfo', SizeOf(V), 32);
  CheckOffset('TVkDescriptorSetLayoutCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkDescriptorSetLayoutCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkDescriptorSetLayoutCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkDescriptorSetLayoutCreateInfo.bindingCount', PtrUInt(@V.bindingCount) - PtrUInt(@V), 20);
  CheckOffset('TVkDescriptorSetLayoutCreateInfo.pBindings', PtrUInt(@V.pBindings) - PtrUInt(@V), 24);
end;

procedure Layout_VkDeviceCreateInfo;
var
  V: TVkDeviceCreateInfo;
begin
  CheckSize('TVkDeviceCreateInfo', SizeOf(V), 72);
  CheckOffset('TVkDeviceCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkDeviceCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkDeviceCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkDeviceCreateInfo.queueCreateInfoCount', PtrUInt(@V.queueCreateInfoCount) - PtrUInt(@V), 20);
  CheckOffset('TVkDeviceCreateInfo.pQueueCreateInfos', PtrUInt(@V.pQueueCreateInfos) - PtrUInt(@V), 24);
  CheckOffset('TVkDeviceCreateInfo.enabledLayerCount', PtrUInt(@V.enabledLayerCount) - PtrUInt(@V), 32);
  CheckOffset('TVkDeviceCreateInfo.ppEnabledLayerNames', PtrUInt(@V.ppEnabledLayerNames) - PtrUInt(@V), 40);
  CheckOffset('TVkDeviceCreateInfo.enabledExtensionCount', PtrUInt(@V.enabledExtensionCount) - PtrUInt(@V), 48);
  CheckOffset('TVkDeviceCreateInfo.ppEnabledExtensionNames', PtrUInt(@V.ppEnabledExtensionNames) - PtrUInt(@V), 56);
  CheckOffset('TVkDeviceCreateInfo.pEnabledFeatures', PtrUInt(@V.pEnabledFeatures) - PtrUInt(@V), 64);
end;

procedure Layout_VkDeviceQueueCreateInfo;
var
  V: TVkDeviceQueueCreateInfo;
begin
  CheckSize('TVkDeviceQueueCreateInfo', SizeOf(V), 40);
  CheckOffset('TVkDeviceQueueCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkDeviceQueueCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkDeviceQueueCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkDeviceQueueCreateInfo.queueFamilyIndex', PtrUInt(@V.queueFamilyIndex) - PtrUInt(@V), 20);
  CheckOffset('TVkDeviceQueueCreateInfo.queueCount', PtrUInt(@V.queueCount) - PtrUInt(@V), 24);
  CheckOffset('TVkDeviceQueueCreateInfo.pQueuePriorities', PtrUInt(@V.pQueuePriorities) - PtrUInt(@V), 32);
end;

procedure Layout_VkExtensionProperties;
var
  V: TVkExtensionProperties;
begin
  CheckSize('TVkExtensionProperties', SizeOf(V), 260);
  CheckOffset('TVkExtensionProperties.extensionName', PtrUInt(@V.extensionName) - PtrUInt(@V), 0);
  CheckOffset('TVkExtensionProperties.specVersion', PtrUInt(@V.specVersion) - PtrUInt(@V), 256);
end;

procedure Layout_VkExtent2D;
var
  V: TVkExtent2D;
begin
  CheckSize('TVkExtent2D', SizeOf(V), 8);
  CheckOffset('TVkExtent2D.width', PtrUInt(@V.width) - PtrUInt(@V), 0);
  CheckOffset('TVkExtent2D.height', PtrUInt(@V.height) - PtrUInt(@V), 4);
end;

procedure Layout_VkExtent3D;
var
  V: TVkExtent3D;
begin
  CheckSize('TVkExtent3D', SizeOf(V), 12);
  CheckOffset('TVkExtent3D.width', PtrUInt(@V.width) - PtrUInt(@V), 0);
  CheckOffset('TVkExtent3D.height', PtrUInt(@V.height) - PtrUInt(@V), 4);
  CheckOffset('TVkExtent3D.depth', PtrUInt(@V.depth) - PtrUInt(@V), 8);
end;

procedure Layout_VkExternalMemoryImageCreateInfo;
var
  V: TVkExternalMemoryImageCreateInfo;
begin
  CheckSize('TVkExternalMemoryImageCreateInfo', SizeOf(V), 24);
  CheckOffset('TVkExternalMemoryImageCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkExternalMemoryImageCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkExternalMemoryImageCreateInfo.handleTypes', PtrUInt(@V.handleTypes) - PtrUInt(@V), 16);
end;

procedure Layout_VkFenceCreateInfo;
var
  V: TVkFenceCreateInfo;
begin
  CheckSize('TVkFenceCreateInfo', SizeOf(V), 24);
  CheckOffset('TVkFenceCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkFenceCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkFenceCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
end;

procedure Layout_VkFramebufferCreateInfo;
var
  V: TVkFramebufferCreateInfo;
begin
  CheckSize('TVkFramebufferCreateInfo', SizeOf(V), 64);
  CheckOffset('TVkFramebufferCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkFramebufferCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkFramebufferCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkFramebufferCreateInfo.renderPass', PtrUInt(@V.renderPass) - PtrUInt(@V), 24);
  CheckOffset('TVkFramebufferCreateInfo.attachmentCount', PtrUInt(@V.attachmentCount) - PtrUInt(@V), 32);
  CheckOffset('TVkFramebufferCreateInfo.pAttachments', PtrUInt(@V.pAttachments) - PtrUInt(@V), 40);
  CheckOffset('TVkFramebufferCreateInfo.width', PtrUInt(@V.width) - PtrUInt(@V), 48);
  CheckOffset('TVkFramebufferCreateInfo.height', PtrUInt(@V.height) - PtrUInt(@V), 52);
  CheckOffset('TVkFramebufferCreateInfo.layers', PtrUInt(@V.layers) - PtrUInt(@V), 56);
end;

procedure Layout_VkGraphicsPipelineCreateInfo;
var
  V: TVkGraphicsPipelineCreateInfo;
begin
  CheckSize('TVkGraphicsPipelineCreateInfo', SizeOf(V), 144);
  CheckOffset('TVkGraphicsPipelineCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkGraphicsPipelineCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkGraphicsPipelineCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkGraphicsPipelineCreateInfo.stageCount', PtrUInt(@V.stageCount) - PtrUInt(@V), 20);
  CheckOffset('TVkGraphicsPipelineCreateInfo.pStages', PtrUInt(@V.pStages) - PtrUInt(@V), 24);
  CheckOffset('TVkGraphicsPipelineCreateInfo.pVertexInputState', PtrUInt(@V.pVertexInputState) - PtrUInt(@V), 32);
  CheckOffset('TVkGraphicsPipelineCreateInfo.pInputAssemblyState', PtrUInt(@V.pInputAssemblyState) - PtrUInt(@V), 40);
  CheckOffset('TVkGraphicsPipelineCreateInfo.pTessellationState', PtrUInt(@V.pTessellationState) - PtrUInt(@V), 48);
  CheckOffset('TVkGraphicsPipelineCreateInfo.pViewportState', PtrUInt(@V.pViewportState) - PtrUInt(@V), 56);
  CheckOffset('TVkGraphicsPipelineCreateInfo.pRasterizationState', PtrUInt(@V.pRasterizationState) - PtrUInt(@V), 64);
  CheckOffset('TVkGraphicsPipelineCreateInfo.pMultisampleState', PtrUInt(@V.pMultisampleState) - PtrUInt(@V), 72);
  CheckOffset('TVkGraphicsPipelineCreateInfo.pDepthStencilState', PtrUInt(@V.pDepthStencilState) - PtrUInt(@V), 80);
  CheckOffset('TVkGraphicsPipelineCreateInfo.pColorBlendState', PtrUInt(@V.pColorBlendState) - PtrUInt(@V), 88);
  CheckOffset('TVkGraphicsPipelineCreateInfo.pDynamicState', PtrUInt(@V.pDynamicState) - PtrUInt(@V), 96);
  CheckOffset('TVkGraphicsPipelineCreateInfo.layout', PtrUInt(@V.layout) - PtrUInt(@V), 104);
  CheckOffset('TVkGraphicsPipelineCreateInfo.renderPass', PtrUInt(@V.renderPass) - PtrUInt(@V), 112);
  CheckOffset('TVkGraphicsPipelineCreateInfo.subpass', PtrUInt(@V.subpass) - PtrUInt(@V), 120);
  CheckOffset('TVkGraphicsPipelineCreateInfo.basePipelineHandle', PtrUInt(@V.basePipelineHandle) - PtrUInt(@V), 128);
  CheckOffset('TVkGraphicsPipelineCreateInfo.basePipelineIndex', PtrUInt(@V.basePipelineIndex) - PtrUInt(@V), 136);
end;

procedure Layout_VkImageCreateInfo;
var
  V: TVkImageCreateInfo;
begin
  CheckSize('TVkImageCreateInfo', SizeOf(V), 88);
  CheckOffset('TVkImageCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkImageCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkImageCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkImageCreateInfo.imageType', PtrUInt(@V.imageType) - PtrUInt(@V), 20);
  CheckOffset('TVkImageCreateInfo.format', PtrUInt(@V.format) - PtrUInt(@V), 24);
  CheckOffset('TVkImageCreateInfo.extent', PtrUInt(@V.extent) - PtrUInt(@V), 28);
  CheckOffset('TVkImageCreateInfo.mipLevels', PtrUInt(@V.mipLevels) - PtrUInt(@V), 40);
  CheckOffset('TVkImageCreateInfo.arrayLayers', PtrUInt(@V.arrayLayers) - PtrUInt(@V), 44);
  CheckOffset('TVkImageCreateInfo.samples', PtrUInt(@V.samples) - PtrUInt(@V), 48);
  CheckOffset('TVkImageCreateInfo.tiling', PtrUInt(@V.tiling) - PtrUInt(@V), 52);
  CheckOffset('TVkImageCreateInfo.usage', PtrUInt(@V.usage) - PtrUInt(@V), 56);
  CheckOffset('TVkImageCreateInfo.sharingMode', PtrUInt(@V.sharingMode) - PtrUInt(@V), 60);
  CheckOffset('TVkImageCreateInfo.queueFamilyIndexCount', PtrUInt(@V.queueFamilyIndexCount) - PtrUInt(@V), 64);
  CheckOffset('TVkImageCreateInfo.pQueueFamilyIndices', PtrUInt(@V.pQueueFamilyIndices) - PtrUInt(@V), 72);
  CheckOffset('TVkImageCreateInfo.initialLayout', PtrUInt(@V.initialLayout) - PtrUInt(@V), 80);
end;

procedure Layout_VkImageFormatProperties;
var
  V: TVkImageFormatProperties;
begin
  CheckSize('TVkImageFormatProperties', SizeOf(V), 32);
  CheckOffset('TVkImageFormatProperties.maxExtent', PtrUInt(@V.maxExtent) - PtrUInt(@V), 0);
  CheckOffset('TVkImageFormatProperties.maxMipLevels', PtrUInt(@V.maxMipLevels) - PtrUInt(@V), 12);
  CheckOffset('TVkImageFormatProperties.maxArrayLayers', PtrUInt(@V.maxArrayLayers) - PtrUInt(@V), 16);
  CheckOffset('TVkImageFormatProperties.sampleCounts', PtrUInt(@V.sampleCounts) - PtrUInt(@V), 20);
  CheckOffset('TVkImageFormatProperties.maxResourceSize', PtrUInt(@V.maxResourceSize) - PtrUInt(@V), 24);
end;

procedure Layout_VkImageMemoryBarrier;
var
  V: TVkImageMemoryBarrier;
begin
  CheckSize('TVkImageMemoryBarrier', SizeOf(V), 72);
  CheckOffset('TVkImageMemoryBarrier.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkImageMemoryBarrier.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkImageMemoryBarrier.srcAccessMask', PtrUInt(@V.srcAccessMask) - PtrUInt(@V), 16);
  CheckOffset('TVkImageMemoryBarrier.dstAccessMask', PtrUInt(@V.dstAccessMask) - PtrUInt(@V), 20);
  CheckOffset('TVkImageMemoryBarrier.oldLayout', PtrUInt(@V.oldLayout) - PtrUInt(@V), 24);
  CheckOffset('TVkImageMemoryBarrier.newLayout', PtrUInt(@V.newLayout) - PtrUInt(@V), 28);
  CheckOffset('TVkImageMemoryBarrier.srcQueueFamilyIndex', PtrUInt(@V.srcQueueFamilyIndex) - PtrUInt(@V), 32);
  CheckOffset('TVkImageMemoryBarrier.dstQueueFamilyIndex', PtrUInt(@V.dstQueueFamilyIndex) - PtrUInt(@V), 36);
  CheckOffset('TVkImageMemoryBarrier.image', PtrUInt(@V.image) - PtrUInt(@V), 40);
  CheckOffset('TVkImageMemoryBarrier.subresourceRange', PtrUInt(@V.subresourceRange) - PtrUInt(@V), 48);
end;

procedure Layout_VkImageSubresourceLayers;
var
  V: TVkImageSubresourceLayers;
begin
  CheckSize('TVkImageSubresourceLayers', SizeOf(V), 16);
  CheckOffset('TVkImageSubresourceLayers.aspectMask', PtrUInt(@V.aspectMask) - PtrUInt(@V), 0);
  CheckOffset('TVkImageSubresourceLayers.mipLevel', PtrUInt(@V.mipLevel) - PtrUInt(@V), 4);
  CheckOffset('TVkImageSubresourceLayers.baseArrayLayer', PtrUInt(@V.baseArrayLayer) - PtrUInt(@V), 8);
  CheckOffset('TVkImageSubresourceLayers.layerCount', PtrUInt(@V.layerCount) - PtrUInt(@V), 12);
end;

procedure Layout_VkImageSubresourceRange;
var
  V: TVkImageSubresourceRange;
begin
  CheckSize('TVkImageSubresourceRange', SizeOf(V), 20);
  CheckOffset('TVkImageSubresourceRange.aspectMask', PtrUInt(@V.aspectMask) - PtrUInt(@V), 0);
  CheckOffset('TVkImageSubresourceRange.baseMipLevel', PtrUInt(@V.baseMipLevel) - PtrUInt(@V), 4);
  CheckOffset('TVkImageSubresourceRange.levelCount', PtrUInt(@V.levelCount) - PtrUInt(@V), 8);
  CheckOffset('TVkImageSubresourceRange.baseArrayLayer', PtrUInt(@V.baseArrayLayer) - PtrUInt(@V), 12);
  CheckOffset('TVkImageSubresourceRange.layerCount', PtrUInt(@V.layerCount) - PtrUInt(@V), 16);
end;

procedure Layout_VkImageViewCreateInfo;
var
  V: TVkImageViewCreateInfo;
begin
  CheckSize('TVkImageViewCreateInfo', SizeOf(V), 80);
  CheckOffset('TVkImageViewCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkImageViewCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkImageViewCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkImageViewCreateInfo.image', PtrUInt(@V.image) - PtrUInt(@V), 24);
  CheckOffset('TVkImageViewCreateInfo.viewType', PtrUInt(@V.viewType) - PtrUInt(@V), 32);
  CheckOffset('TVkImageViewCreateInfo.format', PtrUInt(@V.format) - PtrUInt(@V), 36);
  CheckOffset('TVkImageViewCreateInfo.components', PtrUInt(@V.components) - PtrUInt(@V), 40);
  CheckOffset('TVkImageViewCreateInfo.subresourceRange', PtrUInt(@V.subresourceRange) - PtrUInt(@V), 56);
end;

procedure Layout_VkImageViewUsageCreateInfo;
var
  V: TVkImageViewUsageCreateInfo;
begin
  CheckSize('TVkImageViewUsageCreateInfo', SizeOf(V), 24);
  CheckOffset('TVkImageViewUsageCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkImageViewUsageCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkImageViewUsageCreateInfo.usage', PtrUInt(@V.usage) - PtrUInt(@V), 16);
end;

procedure Layout_VkInstanceCreateInfo;
var
  V: TVkInstanceCreateInfo;
begin
  CheckSize('TVkInstanceCreateInfo', SizeOf(V), 64);
  CheckOffset('TVkInstanceCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkInstanceCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkInstanceCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkInstanceCreateInfo.pApplicationInfo', PtrUInt(@V.pApplicationInfo) - PtrUInt(@V), 24);
  CheckOffset('TVkInstanceCreateInfo.enabledLayerCount', PtrUInt(@V.enabledLayerCount) - PtrUInt(@V), 32);
  CheckOffset('TVkInstanceCreateInfo.ppEnabledLayerNames', PtrUInt(@V.ppEnabledLayerNames) - PtrUInt(@V), 40);
  CheckOffset('TVkInstanceCreateInfo.enabledExtensionCount', PtrUInt(@V.enabledExtensionCount) - PtrUInt(@V), 48);
  CheckOffset('TVkInstanceCreateInfo.ppEnabledExtensionNames', PtrUInt(@V.ppEnabledExtensionNames) - PtrUInt(@V), 56);
end;

procedure Layout_VkLayerProperties;
var
  V: TVkLayerProperties;
begin
  CheckSize('TVkLayerProperties', SizeOf(V), 520);
  CheckOffset('TVkLayerProperties.layerName', PtrUInt(@V.layerName) - PtrUInt(@V), 0);
  CheckOffset('TVkLayerProperties.specVersion', PtrUInt(@V.specVersion) - PtrUInt(@V), 256);
  CheckOffset('TVkLayerProperties.implementationVersion', PtrUInt(@V.implementationVersion) - PtrUInt(@V), 260);
  CheckOffset('TVkLayerProperties.description', PtrUInt(@V.description) - PtrUInt(@V), 264);
end;

procedure Layout_VkMemoryAllocateInfo;
var
  V: TVkMemoryAllocateInfo;
begin
  CheckSize('TVkMemoryAllocateInfo', SizeOf(V), 32);
  CheckOffset('TVkMemoryAllocateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkMemoryAllocateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkMemoryAllocateInfo.allocationSize', PtrUInt(@V.allocationSize) - PtrUInt(@V), 16);
  CheckOffset('TVkMemoryAllocateInfo.memoryTypeIndex', PtrUInt(@V.memoryTypeIndex) - PtrUInt(@V), 24);
end;

procedure Layout_VkMemoryBarrier;
var
  V: TVkMemoryBarrier;
begin
  CheckSize('TVkMemoryBarrier', SizeOf(V), 24);
  CheckOffset('TVkMemoryBarrier.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkMemoryBarrier.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkMemoryBarrier.srcAccessMask', PtrUInt(@V.srcAccessMask) - PtrUInt(@V), 16);
  CheckOffset('TVkMemoryBarrier.dstAccessMask', PtrUInt(@V.dstAccessMask) - PtrUInt(@V), 20);
end;

procedure Layout_VkMemoryDedicatedAllocateInfo;
var
  V: TVkMemoryDedicatedAllocateInfo;
begin
  CheckSize('TVkMemoryDedicatedAllocateInfo', SizeOf(V), 32);
  CheckOffset('TVkMemoryDedicatedAllocateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkMemoryDedicatedAllocateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkMemoryDedicatedAllocateInfo.image', PtrUInt(@V.image) - PtrUInt(@V), 16);
  CheckOffset('TVkMemoryDedicatedAllocateInfo.buffer', PtrUInt(@V.buffer) - PtrUInt(@V), 24);
end;

procedure Layout_VkMemoryHeap;
var
  V: TVkMemoryHeap;
begin
  CheckSize('TVkMemoryHeap', SizeOf(V), 16);
  CheckOffset('TVkMemoryHeap.size', PtrUInt(@V.size) - PtrUInt(@V), 0);
  CheckOffset('TVkMemoryHeap.flags', PtrUInt(@V.flags) - PtrUInt(@V), 8);
end;

procedure Layout_VkMemoryRequirements;
var
  V: TVkMemoryRequirements;
begin
  CheckSize('TVkMemoryRequirements', SizeOf(V), 24);
  CheckOffset('TVkMemoryRequirements.size', PtrUInt(@V.size) - PtrUInt(@V), 0);
  CheckOffset('TVkMemoryRequirements.alignment', PtrUInt(@V.alignment) - PtrUInt(@V), 8);
  CheckOffset('TVkMemoryRequirements.memoryTypeBits', PtrUInt(@V.memoryTypeBits) - PtrUInt(@V), 16);
end;

procedure Layout_VkMemoryType;
var
  V: TVkMemoryType;
begin
  CheckSize('TVkMemoryType', SizeOf(V), 8);
  CheckOffset('TVkMemoryType.propertyFlags', PtrUInt(@V.propertyFlags) - PtrUInt(@V), 0);
  CheckOffset('TVkMemoryType.heapIndex', PtrUInt(@V.heapIndex) - PtrUInt(@V), 4);
end;

procedure Layout_VkOffset2D;
var
  V: TVkOffset2D;
begin
  CheckSize('TVkOffset2D', SizeOf(V), 8);
  CheckOffset('TVkOffset2D.x', PtrUInt(@V.x) - PtrUInt(@V), 0);
  CheckOffset('TVkOffset2D.y', PtrUInt(@V.y) - PtrUInt(@V), 4);
end;

procedure Layout_VkOffset3D;
var
  V: TVkOffset3D;
begin
  CheckSize('TVkOffset3D', SizeOf(V), 12);
  CheckOffset('TVkOffset3D.x', PtrUInt(@V.x) - PtrUInt(@V), 0);
  CheckOffset('TVkOffset3D.y', PtrUInt(@V.y) - PtrUInt(@V), 4);
  CheckOffset('TVkOffset3D.z', PtrUInt(@V.z) - PtrUInt(@V), 8);
end;

procedure Layout_VkPhysicalDeviceFeatures;
var
  V: TVkPhysicalDeviceFeatures;
begin
  CheckSize('TVkPhysicalDeviceFeatures', SizeOf(V), 220);
  CheckOffset('TVkPhysicalDeviceFeatures.robustBufferAccess', PtrUInt(@V.robustBufferAccess) - PtrUInt(@V), 0);
  CheckOffset('TVkPhysicalDeviceFeatures.fullDrawIndexUint32', PtrUInt(@V.fullDrawIndexUint32) - PtrUInt(@V), 4);
  CheckOffset('TVkPhysicalDeviceFeatures.imageCubeArray', PtrUInt(@V.imageCubeArray) - PtrUInt(@V), 8);
  CheckOffset('TVkPhysicalDeviceFeatures.independentBlend', PtrUInt(@V.independentBlend) - PtrUInt(@V), 12);
  CheckOffset('TVkPhysicalDeviceFeatures.geometryShader', PtrUInt(@V.geometryShader) - PtrUInt(@V), 16);
  CheckOffset('TVkPhysicalDeviceFeatures.tessellationShader', PtrUInt(@V.tessellationShader) - PtrUInt(@V), 20);
  CheckOffset('TVkPhysicalDeviceFeatures.sampleRateShading', PtrUInt(@V.sampleRateShading) - PtrUInt(@V), 24);
  CheckOffset('TVkPhysicalDeviceFeatures.dualSrcBlend', PtrUInt(@V.dualSrcBlend) - PtrUInt(@V), 28);
  CheckOffset('TVkPhysicalDeviceFeatures.logicOp', PtrUInt(@V.logicOp) - PtrUInt(@V), 32);
  CheckOffset('TVkPhysicalDeviceFeatures.multiDrawIndirect', PtrUInt(@V.multiDrawIndirect) - PtrUInt(@V), 36);
  CheckOffset('TVkPhysicalDeviceFeatures.drawIndirectFirstInstance', PtrUInt(@V.drawIndirectFirstInstance) - PtrUInt(@V), 40);
  CheckOffset('TVkPhysicalDeviceFeatures.depthClamp', PtrUInt(@V.depthClamp) - PtrUInt(@V), 44);
  CheckOffset('TVkPhysicalDeviceFeatures.depthBiasClamp', PtrUInt(@V.depthBiasClamp) - PtrUInt(@V), 48);
  CheckOffset('TVkPhysicalDeviceFeatures.fillModeNonSolid', PtrUInt(@V.fillModeNonSolid) - PtrUInt(@V), 52);
  CheckOffset('TVkPhysicalDeviceFeatures.depthBounds', PtrUInt(@V.depthBounds) - PtrUInt(@V), 56);
  CheckOffset('TVkPhysicalDeviceFeatures.wideLines', PtrUInt(@V.wideLines) - PtrUInt(@V), 60);
  CheckOffset('TVkPhysicalDeviceFeatures.largePoints', PtrUInt(@V.largePoints) - PtrUInt(@V), 64);
  CheckOffset('TVkPhysicalDeviceFeatures.alphaToOne', PtrUInt(@V.alphaToOne) - PtrUInt(@V), 68);
  CheckOffset('TVkPhysicalDeviceFeatures.multiViewport', PtrUInt(@V.multiViewport) - PtrUInt(@V), 72);
  CheckOffset('TVkPhysicalDeviceFeatures.samplerAnisotropy', PtrUInt(@V.samplerAnisotropy) - PtrUInt(@V), 76);
  CheckOffset('TVkPhysicalDeviceFeatures.textureCompressionETC2', PtrUInt(@V.textureCompressionETC2) - PtrUInt(@V), 80);
  CheckOffset('TVkPhysicalDeviceFeatures.textureCompressionASTC_LDR', PtrUInt(@V.textureCompressionASTC_LDR) - PtrUInt(@V), 84);
  CheckOffset('TVkPhysicalDeviceFeatures.textureCompressionBC', PtrUInt(@V.textureCompressionBC) - PtrUInt(@V), 88);
  CheckOffset('TVkPhysicalDeviceFeatures.occlusionQueryPrecise', PtrUInt(@V.occlusionQueryPrecise) - PtrUInt(@V), 92);
  CheckOffset('TVkPhysicalDeviceFeatures.pipelineStatisticsQuery', PtrUInt(@V.pipelineStatisticsQuery) - PtrUInt(@V), 96);
  CheckOffset('TVkPhysicalDeviceFeatures.vertexPipelineStoresAndAtomics', PtrUInt(@V.vertexPipelineStoresAndAtomics) - PtrUInt(@V), 100);
  CheckOffset('TVkPhysicalDeviceFeatures.fragmentStoresAndAtomics', PtrUInt(@V.fragmentStoresAndAtomics) - PtrUInt(@V), 104);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderTessellationAndGeometryPointSize', PtrUInt(@V.shaderTessellationAndGeometryPointSize) - PtrUInt(@V), 108);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderImageGatherExtended', PtrUInt(@V.shaderImageGatherExtended) - PtrUInt(@V), 112);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderStorageImageExtendedFormats', PtrUInt(@V.shaderStorageImageExtendedFormats) - PtrUInt(@V), 116);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderStorageImageMultisample', PtrUInt(@V.shaderStorageImageMultisample) - PtrUInt(@V), 120);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderStorageImageReadWithoutFormat', PtrUInt(@V.shaderStorageImageReadWithoutFormat) - PtrUInt(@V), 124);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderStorageImageWriteWithoutFormat', PtrUInt(@V.shaderStorageImageWriteWithoutFormat) - PtrUInt(@V), 128);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderUniformBufferArrayDynamicIndexing', PtrUInt(@V.shaderUniformBufferArrayDynamicIndexing) - PtrUInt(@V), 132);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderSampledImageArrayDynamicIndexing', PtrUInt(@V.shaderSampledImageArrayDynamicIndexing) - PtrUInt(@V), 136);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderStorageBufferArrayDynamicIndexing', PtrUInt(@V.shaderStorageBufferArrayDynamicIndexing) - PtrUInt(@V), 140);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderStorageImageArrayDynamicIndexing', PtrUInt(@V.shaderStorageImageArrayDynamicIndexing) - PtrUInt(@V), 144);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderClipDistance', PtrUInt(@V.shaderClipDistance) - PtrUInt(@V), 148);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderCullDistance', PtrUInt(@V.shaderCullDistance) - PtrUInt(@V), 152);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderFloat64', PtrUInt(@V.shaderFloat64) - PtrUInt(@V), 156);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderInt64', PtrUInt(@V.shaderInt64) - PtrUInt(@V), 160);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderInt16', PtrUInt(@V.shaderInt16) - PtrUInt(@V), 164);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderResourceResidency', PtrUInt(@V.shaderResourceResidency) - PtrUInt(@V), 168);
  CheckOffset('TVkPhysicalDeviceFeatures.shaderResourceMinLod', PtrUInt(@V.shaderResourceMinLod) - PtrUInt(@V), 172);
  CheckOffset('TVkPhysicalDeviceFeatures.sparseBinding', PtrUInt(@V.sparseBinding) - PtrUInt(@V), 176);
  CheckOffset('TVkPhysicalDeviceFeatures.sparseResidencyBuffer', PtrUInt(@V.sparseResidencyBuffer) - PtrUInt(@V), 180);
  CheckOffset('TVkPhysicalDeviceFeatures.sparseResidencyImage2D', PtrUInt(@V.sparseResidencyImage2D) - PtrUInt(@V), 184);
  CheckOffset('TVkPhysicalDeviceFeatures.sparseResidencyImage3D', PtrUInt(@V.sparseResidencyImage3D) - PtrUInt(@V), 188);
  CheckOffset('TVkPhysicalDeviceFeatures.sparseResidency2Samples', PtrUInt(@V.sparseResidency2Samples) - PtrUInt(@V), 192);
  CheckOffset('TVkPhysicalDeviceFeatures.sparseResidency4Samples', PtrUInt(@V.sparseResidency4Samples) - PtrUInt(@V), 196);
  CheckOffset('TVkPhysicalDeviceFeatures.sparseResidency8Samples', PtrUInt(@V.sparseResidency8Samples) - PtrUInt(@V), 200);
  CheckOffset('TVkPhysicalDeviceFeatures.sparseResidency16Samples', PtrUInt(@V.sparseResidency16Samples) - PtrUInt(@V), 204);
  CheckOffset('TVkPhysicalDeviceFeatures.sparseResidencyAliased', PtrUInt(@V.sparseResidencyAliased) - PtrUInt(@V), 208);
  CheckOffset('TVkPhysicalDeviceFeatures.variableMultisampleRate', PtrUInt(@V.variableMultisampleRate) - PtrUInt(@V), 212);
  CheckOffset('TVkPhysicalDeviceFeatures.inheritedQueries', PtrUInt(@V.inheritedQueries) - PtrUInt(@V), 216);
end;

procedure Layout_VkPhysicalDeviceFeatures2;
var
  V: TVkPhysicalDeviceFeatures2;
begin
  CheckSize('TVkPhysicalDeviceFeatures2', SizeOf(V), 240);
  CheckOffset('TVkPhysicalDeviceFeatures2.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPhysicalDeviceFeatures2.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPhysicalDeviceFeatures2.features', PtrUInt(@V.features) - PtrUInt(@V), 16);
end;

procedure Layout_VkPhysicalDeviceLimits;
var
  V: TVkPhysicalDeviceLimits;
begin
  CheckSize('TVkPhysicalDeviceLimits', SizeOf(V), 504);
  CheckOffset('TVkPhysicalDeviceLimits.maxImageDimension1D', PtrUInt(@V.maxImageDimension1D) - PtrUInt(@V), 0);
  CheckOffset('TVkPhysicalDeviceLimits.maxImageDimension2D', PtrUInt(@V.maxImageDimension2D) - PtrUInt(@V), 4);
  CheckOffset('TVkPhysicalDeviceLimits.maxImageDimension3D', PtrUInt(@V.maxImageDimension3D) - PtrUInt(@V), 8);
  CheckOffset('TVkPhysicalDeviceLimits.maxImageDimensionCube', PtrUInt(@V.maxImageDimensionCube) - PtrUInt(@V), 12);
  CheckOffset('TVkPhysicalDeviceLimits.maxImageArrayLayers', PtrUInt(@V.maxImageArrayLayers) - PtrUInt(@V), 16);
  CheckOffset('TVkPhysicalDeviceLimits.maxTexelBufferElements', PtrUInt(@V.maxTexelBufferElements) - PtrUInt(@V), 20);
  CheckOffset('TVkPhysicalDeviceLimits.maxUniformBufferRange', PtrUInt(@V.maxUniformBufferRange) - PtrUInt(@V), 24);
  CheckOffset('TVkPhysicalDeviceLimits.maxStorageBufferRange', PtrUInt(@V.maxStorageBufferRange) - PtrUInt(@V), 28);
  CheckOffset('TVkPhysicalDeviceLimits.maxPushConstantsSize', PtrUInt(@V.maxPushConstantsSize) - PtrUInt(@V), 32);
  CheckOffset('TVkPhysicalDeviceLimits.maxMemoryAllocationCount', PtrUInt(@V.maxMemoryAllocationCount) - PtrUInt(@V), 36);
  CheckOffset('TVkPhysicalDeviceLimits.maxSamplerAllocationCount', PtrUInt(@V.maxSamplerAllocationCount) - PtrUInt(@V), 40);
  CheckOffset('TVkPhysicalDeviceLimits.bufferImageGranularity', PtrUInt(@V.bufferImageGranularity) - PtrUInt(@V), 48);
  CheckOffset('TVkPhysicalDeviceLimits.sparseAddressSpaceSize', PtrUInt(@V.sparseAddressSpaceSize) - PtrUInt(@V), 56);
  CheckOffset('TVkPhysicalDeviceLimits.maxBoundDescriptorSets', PtrUInt(@V.maxBoundDescriptorSets) - PtrUInt(@V), 64);
  CheckOffset('TVkPhysicalDeviceLimits.maxPerStageDescriptorSamplers', PtrUInt(@V.maxPerStageDescriptorSamplers) - PtrUInt(@V), 68);
  CheckOffset('TVkPhysicalDeviceLimits.maxPerStageDescriptorUniformBuffers', PtrUInt(@V.maxPerStageDescriptorUniformBuffers) - PtrUInt(@V), 72);
  CheckOffset('TVkPhysicalDeviceLimits.maxPerStageDescriptorStorageBuffers', PtrUInt(@V.maxPerStageDescriptorStorageBuffers) - PtrUInt(@V), 76);
  CheckOffset('TVkPhysicalDeviceLimits.maxPerStageDescriptorSampledImages', PtrUInt(@V.maxPerStageDescriptorSampledImages) - PtrUInt(@V), 80);
  CheckOffset('TVkPhysicalDeviceLimits.maxPerStageDescriptorStorageImages', PtrUInt(@V.maxPerStageDescriptorStorageImages) - PtrUInt(@V), 84);
  CheckOffset('TVkPhysicalDeviceLimits.maxPerStageDescriptorInputAttachments', PtrUInt(@V.maxPerStageDescriptorInputAttachments) - PtrUInt(@V), 88);
  CheckOffset('TVkPhysicalDeviceLimits.maxPerStageResources', PtrUInt(@V.maxPerStageResources) - PtrUInt(@V), 92);
  CheckOffset('TVkPhysicalDeviceLimits.maxDescriptorSetSamplers', PtrUInt(@V.maxDescriptorSetSamplers) - PtrUInt(@V), 96);
  CheckOffset('TVkPhysicalDeviceLimits.maxDescriptorSetUniformBuffers', PtrUInt(@V.maxDescriptorSetUniformBuffers) - PtrUInt(@V), 100);
  CheckOffset('TVkPhysicalDeviceLimits.maxDescriptorSetUniformBuffersDynamic', PtrUInt(@V.maxDescriptorSetUniformBuffersDynamic) - PtrUInt(@V), 104);
  CheckOffset('TVkPhysicalDeviceLimits.maxDescriptorSetStorageBuffers', PtrUInt(@V.maxDescriptorSetStorageBuffers) - PtrUInt(@V), 108);
  CheckOffset('TVkPhysicalDeviceLimits.maxDescriptorSetStorageBuffersDynamic', PtrUInt(@V.maxDescriptorSetStorageBuffersDynamic) - PtrUInt(@V), 112);
  CheckOffset('TVkPhysicalDeviceLimits.maxDescriptorSetSampledImages', PtrUInt(@V.maxDescriptorSetSampledImages) - PtrUInt(@V), 116);
  CheckOffset('TVkPhysicalDeviceLimits.maxDescriptorSetStorageImages', PtrUInt(@V.maxDescriptorSetStorageImages) - PtrUInt(@V), 120);
  CheckOffset('TVkPhysicalDeviceLimits.maxDescriptorSetInputAttachments', PtrUInt(@V.maxDescriptorSetInputAttachments) - PtrUInt(@V), 124);
  CheckOffset('TVkPhysicalDeviceLimits.maxVertexInputAttributes', PtrUInt(@V.maxVertexInputAttributes) - PtrUInt(@V), 128);
  CheckOffset('TVkPhysicalDeviceLimits.maxVertexInputBindings', PtrUInt(@V.maxVertexInputBindings) - PtrUInt(@V), 132);
  CheckOffset('TVkPhysicalDeviceLimits.maxVertexInputAttributeOffset', PtrUInt(@V.maxVertexInputAttributeOffset) - PtrUInt(@V), 136);
  CheckOffset('TVkPhysicalDeviceLimits.maxVertexInputBindingStride', PtrUInt(@V.maxVertexInputBindingStride) - PtrUInt(@V), 140);
  CheckOffset('TVkPhysicalDeviceLimits.maxVertexOutputComponents', PtrUInt(@V.maxVertexOutputComponents) - PtrUInt(@V), 144);
  CheckOffset('TVkPhysicalDeviceLimits.maxTessellationGenerationLevel', PtrUInt(@V.maxTessellationGenerationLevel) - PtrUInt(@V), 148);
  CheckOffset('TVkPhysicalDeviceLimits.maxTessellationPatchSize', PtrUInt(@V.maxTessellationPatchSize) - PtrUInt(@V), 152);
  CheckOffset('TVkPhysicalDeviceLimits.maxTessellationControlPerVertexInputComponents', PtrUInt(@V.maxTessellationControlPerVertexInputComponents) - PtrUInt(@V), 156);
  CheckOffset('TVkPhysicalDeviceLimits.maxTessellationControlPerVertexOutputComponents', PtrUInt(@V.maxTessellationControlPerVertexOutputComponents) - PtrUInt(@V), 160);
  CheckOffset('TVkPhysicalDeviceLimits.maxTessellationControlPerPatchOutputComponents', PtrUInt(@V.maxTessellationControlPerPatchOutputComponents) - PtrUInt(@V), 164);
  CheckOffset('TVkPhysicalDeviceLimits.maxTessellationControlTotalOutputComponents', PtrUInt(@V.maxTessellationControlTotalOutputComponents) - PtrUInt(@V), 168);
  CheckOffset('TVkPhysicalDeviceLimits.maxTessellationEvaluationInputComponents', PtrUInt(@V.maxTessellationEvaluationInputComponents) - PtrUInt(@V), 172);
  CheckOffset('TVkPhysicalDeviceLimits.maxTessellationEvaluationOutputComponents', PtrUInt(@V.maxTessellationEvaluationOutputComponents) - PtrUInt(@V), 176);
  CheckOffset('TVkPhysicalDeviceLimits.maxGeometryShaderInvocations', PtrUInt(@V.maxGeometryShaderInvocations) - PtrUInt(@V), 180);
  CheckOffset('TVkPhysicalDeviceLimits.maxGeometryInputComponents', PtrUInt(@V.maxGeometryInputComponents) - PtrUInt(@V), 184);
  CheckOffset('TVkPhysicalDeviceLimits.maxGeometryOutputComponents', PtrUInt(@V.maxGeometryOutputComponents) - PtrUInt(@V), 188);
  CheckOffset('TVkPhysicalDeviceLimits.maxGeometryOutputVertices', PtrUInt(@V.maxGeometryOutputVertices) - PtrUInt(@V), 192);
  CheckOffset('TVkPhysicalDeviceLimits.maxGeometryTotalOutputComponents', PtrUInt(@V.maxGeometryTotalOutputComponents) - PtrUInt(@V), 196);
  CheckOffset('TVkPhysicalDeviceLimits.maxFragmentInputComponents', PtrUInt(@V.maxFragmentInputComponents) - PtrUInt(@V), 200);
  CheckOffset('TVkPhysicalDeviceLimits.maxFragmentOutputAttachments', PtrUInt(@V.maxFragmentOutputAttachments) - PtrUInt(@V), 204);
  CheckOffset('TVkPhysicalDeviceLimits.maxFragmentDualSrcAttachments', PtrUInt(@V.maxFragmentDualSrcAttachments) - PtrUInt(@V), 208);
  CheckOffset('TVkPhysicalDeviceLimits.maxFragmentCombinedOutputResources', PtrUInt(@V.maxFragmentCombinedOutputResources) - PtrUInt(@V), 212);
  CheckOffset('TVkPhysicalDeviceLimits.maxComputeSharedMemorySize', PtrUInt(@V.maxComputeSharedMemorySize) - PtrUInt(@V), 216);
  CheckOffset('TVkPhysicalDeviceLimits.maxComputeWorkGroupCount', PtrUInt(@V.maxComputeWorkGroupCount) - PtrUInt(@V), 220);
  CheckOffset('TVkPhysicalDeviceLimits.maxComputeWorkGroupInvocations', PtrUInt(@V.maxComputeWorkGroupInvocations) - PtrUInt(@V), 232);
  CheckOffset('TVkPhysicalDeviceLimits.maxComputeWorkGroupSize', PtrUInt(@V.maxComputeWorkGroupSize) - PtrUInt(@V), 236);
  CheckOffset('TVkPhysicalDeviceLimits.subPixelPrecisionBits', PtrUInt(@V.subPixelPrecisionBits) - PtrUInt(@V), 248);
  CheckOffset('TVkPhysicalDeviceLimits.subTexelPrecisionBits', PtrUInt(@V.subTexelPrecisionBits) - PtrUInt(@V), 252);
  CheckOffset('TVkPhysicalDeviceLimits.mipmapPrecisionBits', PtrUInt(@V.mipmapPrecisionBits) - PtrUInt(@V), 256);
  CheckOffset('TVkPhysicalDeviceLimits.maxDrawIndexedIndexValue', PtrUInt(@V.maxDrawIndexedIndexValue) - PtrUInt(@V), 260);
  CheckOffset('TVkPhysicalDeviceLimits.maxDrawIndirectCount', PtrUInt(@V.maxDrawIndirectCount) - PtrUInt(@V), 264);
  CheckOffset('TVkPhysicalDeviceLimits.maxSamplerLodBias', PtrUInt(@V.maxSamplerLodBias) - PtrUInt(@V), 268);
  CheckOffset('TVkPhysicalDeviceLimits.maxSamplerAnisotropy', PtrUInt(@V.maxSamplerAnisotropy) - PtrUInt(@V), 272);
  CheckOffset('TVkPhysicalDeviceLimits.maxViewports', PtrUInt(@V.maxViewports) - PtrUInt(@V), 276);
  CheckOffset('TVkPhysicalDeviceLimits.maxViewportDimensions', PtrUInt(@V.maxViewportDimensions) - PtrUInt(@V), 280);
  CheckOffset('TVkPhysicalDeviceLimits.viewportBoundsRange', PtrUInt(@V.viewportBoundsRange) - PtrUInt(@V), 288);
  CheckOffset('TVkPhysicalDeviceLimits.viewportSubPixelBits', PtrUInt(@V.viewportSubPixelBits) - PtrUInt(@V), 296);
  CheckOffset('TVkPhysicalDeviceLimits.minMemoryMapAlignment', PtrUInt(@V.minMemoryMapAlignment) - PtrUInt(@V), 304);
  CheckOffset('TVkPhysicalDeviceLimits.minTexelBufferOffsetAlignment', PtrUInt(@V.minTexelBufferOffsetAlignment) - PtrUInt(@V), 312);
  CheckOffset('TVkPhysicalDeviceLimits.minUniformBufferOffsetAlignment', PtrUInt(@V.minUniformBufferOffsetAlignment) - PtrUInt(@V), 320);
  CheckOffset('TVkPhysicalDeviceLimits.minStorageBufferOffsetAlignment', PtrUInt(@V.minStorageBufferOffsetAlignment) - PtrUInt(@V), 328);
  CheckOffset('TVkPhysicalDeviceLimits.minTexelOffset', PtrUInt(@V.minTexelOffset) - PtrUInt(@V), 336);
  CheckOffset('TVkPhysicalDeviceLimits.maxTexelOffset', PtrUInt(@V.maxTexelOffset) - PtrUInt(@V), 340);
  CheckOffset('TVkPhysicalDeviceLimits.minTexelGatherOffset', PtrUInt(@V.minTexelGatherOffset) - PtrUInt(@V), 344);
  CheckOffset('TVkPhysicalDeviceLimits.maxTexelGatherOffset', PtrUInt(@V.maxTexelGatherOffset) - PtrUInt(@V), 348);
  CheckOffset('TVkPhysicalDeviceLimits.minInterpolationOffset', PtrUInt(@V.minInterpolationOffset) - PtrUInt(@V), 352);
  CheckOffset('TVkPhysicalDeviceLimits.maxInterpolationOffset', PtrUInt(@V.maxInterpolationOffset) - PtrUInt(@V), 356);
  CheckOffset('TVkPhysicalDeviceLimits.subPixelInterpolationOffsetBits', PtrUInt(@V.subPixelInterpolationOffsetBits) - PtrUInt(@V), 360);
  CheckOffset('TVkPhysicalDeviceLimits.maxFramebufferWidth', PtrUInt(@V.maxFramebufferWidth) - PtrUInt(@V), 364);
  CheckOffset('TVkPhysicalDeviceLimits.maxFramebufferHeight', PtrUInt(@V.maxFramebufferHeight) - PtrUInt(@V), 368);
  CheckOffset('TVkPhysicalDeviceLimits.maxFramebufferLayers', PtrUInt(@V.maxFramebufferLayers) - PtrUInt(@V), 372);
  CheckOffset('TVkPhysicalDeviceLimits.framebufferColorSampleCounts', PtrUInt(@V.framebufferColorSampleCounts) - PtrUInt(@V), 376);
  CheckOffset('TVkPhysicalDeviceLimits.framebufferDepthSampleCounts', PtrUInt(@V.framebufferDepthSampleCounts) - PtrUInt(@V), 380);
  CheckOffset('TVkPhysicalDeviceLimits.framebufferStencilSampleCounts', PtrUInt(@V.framebufferStencilSampleCounts) - PtrUInt(@V), 384);
  CheckOffset('TVkPhysicalDeviceLimits.framebufferNoAttachmentsSampleCounts', PtrUInt(@V.framebufferNoAttachmentsSampleCounts) - PtrUInt(@V), 388);
  CheckOffset('TVkPhysicalDeviceLimits.maxColorAttachments', PtrUInt(@V.maxColorAttachments) - PtrUInt(@V), 392);
  CheckOffset('TVkPhysicalDeviceLimits.sampledImageColorSampleCounts', PtrUInt(@V.sampledImageColorSampleCounts) - PtrUInt(@V), 396);
  CheckOffset('TVkPhysicalDeviceLimits.sampledImageIntegerSampleCounts', PtrUInt(@V.sampledImageIntegerSampleCounts) - PtrUInt(@V), 400);
  CheckOffset('TVkPhysicalDeviceLimits.sampledImageDepthSampleCounts', PtrUInt(@V.sampledImageDepthSampleCounts) - PtrUInt(@V), 404);
  CheckOffset('TVkPhysicalDeviceLimits.sampledImageStencilSampleCounts', PtrUInt(@V.sampledImageStencilSampleCounts) - PtrUInt(@V), 408);
  CheckOffset('TVkPhysicalDeviceLimits.storageImageSampleCounts', PtrUInt(@V.storageImageSampleCounts) - PtrUInt(@V), 412);
  CheckOffset('TVkPhysicalDeviceLimits.maxSampleMaskWords', PtrUInt(@V.maxSampleMaskWords) - PtrUInt(@V), 416);
  CheckOffset('TVkPhysicalDeviceLimits.timestampComputeAndGraphics', PtrUInt(@V.timestampComputeAndGraphics) - PtrUInt(@V), 420);
  CheckOffset('TVkPhysicalDeviceLimits.timestampPeriod', PtrUInt(@V.timestampPeriod) - PtrUInt(@V), 424);
  CheckOffset('TVkPhysicalDeviceLimits.maxClipDistances', PtrUInt(@V.maxClipDistances) - PtrUInt(@V), 428);
  CheckOffset('TVkPhysicalDeviceLimits.maxCullDistances', PtrUInt(@V.maxCullDistances) - PtrUInt(@V), 432);
  CheckOffset('TVkPhysicalDeviceLimits.maxCombinedClipAndCullDistances', PtrUInt(@V.maxCombinedClipAndCullDistances) - PtrUInt(@V), 436);
  CheckOffset('TVkPhysicalDeviceLimits.discreteQueuePriorities', PtrUInt(@V.discreteQueuePriorities) - PtrUInt(@V), 440);
  CheckOffset('TVkPhysicalDeviceLimits.pointSizeRange', PtrUInt(@V.pointSizeRange) - PtrUInt(@V), 444);
  CheckOffset('TVkPhysicalDeviceLimits.lineWidthRange', PtrUInt(@V.lineWidthRange) - PtrUInt(@V), 452);
  CheckOffset('TVkPhysicalDeviceLimits.pointSizeGranularity', PtrUInt(@V.pointSizeGranularity) - PtrUInt(@V), 460);
  CheckOffset('TVkPhysicalDeviceLimits.lineWidthGranularity', PtrUInt(@V.lineWidthGranularity) - PtrUInt(@V), 464);
  CheckOffset('TVkPhysicalDeviceLimits.strictLines', PtrUInt(@V.strictLines) - PtrUInt(@V), 468);
  CheckOffset('TVkPhysicalDeviceLimits.standardSampleLocations', PtrUInt(@V.standardSampleLocations) - PtrUInt(@V), 472);
  CheckOffset('TVkPhysicalDeviceLimits.optimalBufferCopyOffsetAlignment', PtrUInt(@V.optimalBufferCopyOffsetAlignment) - PtrUInt(@V), 480);
  CheckOffset('TVkPhysicalDeviceLimits.optimalBufferCopyRowPitchAlignment', PtrUInt(@V.optimalBufferCopyRowPitchAlignment) - PtrUInt(@V), 488);
  CheckOffset('TVkPhysicalDeviceLimits.nonCoherentAtomSize', PtrUInt(@V.nonCoherentAtomSize) - PtrUInt(@V), 496);
end;

procedure Layout_VkPhysicalDeviceMemoryProperties;
var
  V: TVkPhysicalDeviceMemoryProperties;
begin
  CheckSize('TVkPhysicalDeviceMemoryProperties', SizeOf(V), 520);
  CheckOffset('TVkPhysicalDeviceMemoryProperties.memoryTypeCount', PtrUInt(@V.memoryTypeCount) - PtrUInt(@V), 0);
  CheckOffset('TVkPhysicalDeviceMemoryProperties.memoryTypes', PtrUInt(@V.memoryTypes) - PtrUInt(@V), 4);
  CheckOffset('TVkPhysicalDeviceMemoryProperties.memoryHeapCount', PtrUInt(@V.memoryHeapCount) - PtrUInt(@V), 260);
  CheckOffset('TVkPhysicalDeviceMemoryProperties.memoryHeaps', PtrUInt(@V.memoryHeaps) - PtrUInt(@V), 264);
end;

procedure Layout_VkPhysicalDeviceMemoryProperties2;
var
  V: TVkPhysicalDeviceMemoryProperties2;
begin
  CheckSize('TVkPhysicalDeviceMemoryProperties2', SizeOf(V), 536);
  CheckOffset('TVkPhysicalDeviceMemoryProperties2.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPhysicalDeviceMemoryProperties2.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPhysicalDeviceMemoryProperties2.memoryProperties', PtrUInt(@V.memoryProperties) - PtrUInt(@V), 16);
end;

procedure Layout_VkPhysicalDeviceProperties;
var
  V: TVkPhysicalDeviceProperties;
begin
  CheckSize('TVkPhysicalDeviceProperties', SizeOf(V), 824);
  CheckOffset('TVkPhysicalDeviceProperties.apiVersion', PtrUInt(@V.apiVersion) - PtrUInt(@V), 0);
  CheckOffset('TVkPhysicalDeviceProperties.driverVersion', PtrUInt(@V.driverVersion) - PtrUInt(@V), 4);
  CheckOffset('TVkPhysicalDeviceProperties.vendorID', PtrUInt(@V.vendorID) - PtrUInt(@V), 8);
  CheckOffset('TVkPhysicalDeviceProperties.deviceID', PtrUInt(@V.deviceID) - PtrUInt(@V), 12);
  CheckOffset('TVkPhysicalDeviceProperties.deviceType', PtrUInt(@V.deviceType) - PtrUInt(@V), 16);
  CheckOffset('TVkPhysicalDeviceProperties.deviceName', PtrUInt(@V.deviceName) - PtrUInt(@V), 20);
  CheckOffset('TVkPhysicalDeviceProperties.pipelineCacheUUID', PtrUInt(@V.pipelineCacheUUID) - PtrUInt(@V), 276);
  CheckOffset('TVkPhysicalDeviceProperties.limits', PtrUInt(@V.limits) - PtrUInt(@V), 296);
  CheckOffset('TVkPhysicalDeviceProperties.sparseProperties', PtrUInt(@V.sparseProperties) - PtrUInt(@V), 800);
end;

procedure Layout_VkPhysicalDeviceProperties2;
var
  V: TVkPhysicalDeviceProperties2;
begin
  CheckSize('TVkPhysicalDeviceProperties2', SizeOf(V), 840);
  CheckOffset('TVkPhysicalDeviceProperties2.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPhysicalDeviceProperties2.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPhysicalDeviceProperties2.properties', PtrUInt(@V.properties) - PtrUInt(@V), 16);
end;

procedure Layout_VkPhysicalDeviceSamplerYcbcrConversionFeatures;
var
  V: TVkPhysicalDeviceSamplerYcbcrConversionFeatures;
begin
  CheckSize('TVkPhysicalDeviceSamplerYcbcrConversionFeatures', SizeOf(V), 24);
  CheckOffset('TVkPhysicalDeviceSamplerYcbcrConversionFeatures.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPhysicalDeviceSamplerYcbcrConversionFeatures.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPhysicalDeviceSamplerYcbcrConversionFeatures.samplerYcbcrConversion', PtrUInt(@V.samplerYcbcrConversion) - PtrUInt(@V), 16);
end;

procedure Layout_VkPhysicalDeviceSparseProperties;
var
  V: TVkPhysicalDeviceSparseProperties;
begin
  CheckSize('TVkPhysicalDeviceSparseProperties', SizeOf(V), 20);
  CheckOffset('TVkPhysicalDeviceSparseProperties.residencyStandard2DBlockShape', PtrUInt(@V.residencyStandard2DBlockShape) - PtrUInt(@V), 0);
  CheckOffset('TVkPhysicalDeviceSparseProperties.residencyStandard2DMultisampleBlockShape', PtrUInt(@V.residencyStandard2DMultisampleBlockShape) - PtrUInt(@V), 4);
  CheckOffset('TVkPhysicalDeviceSparseProperties.residencyStandard3DBlockShape', PtrUInt(@V.residencyStandard3DBlockShape) - PtrUInt(@V), 8);
  CheckOffset('TVkPhysicalDeviceSparseProperties.residencyAlignedMipSize', PtrUInt(@V.residencyAlignedMipSize) - PtrUInt(@V), 12);
  CheckOffset('TVkPhysicalDeviceSparseProperties.residencyNonResidentStrict', PtrUInt(@V.residencyNonResidentStrict) - PtrUInt(@V), 16);
end;

procedure Layout_VkPipelineColorBlendAttachmentState;
var
  V: TVkPipelineColorBlendAttachmentState;
begin
  CheckSize('TVkPipelineColorBlendAttachmentState', SizeOf(V), 32);
  CheckOffset('TVkPipelineColorBlendAttachmentState.blendEnable', PtrUInt(@V.blendEnable) - PtrUInt(@V), 0);
  CheckOffset('TVkPipelineColorBlendAttachmentState.srcColorBlendFactor', PtrUInt(@V.srcColorBlendFactor) - PtrUInt(@V), 4);
  CheckOffset('TVkPipelineColorBlendAttachmentState.dstColorBlendFactor', PtrUInt(@V.dstColorBlendFactor) - PtrUInt(@V), 8);
  CheckOffset('TVkPipelineColorBlendAttachmentState.colorBlendOp', PtrUInt(@V.colorBlendOp) - PtrUInt(@V), 12);
  CheckOffset('TVkPipelineColorBlendAttachmentState.srcAlphaBlendFactor', PtrUInt(@V.srcAlphaBlendFactor) - PtrUInt(@V), 16);
  CheckOffset('TVkPipelineColorBlendAttachmentState.dstAlphaBlendFactor', PtrUInt(@V.dstAlphaBlendFactor) - PtrUInt(@V), 20);
  CheckOffset('TVkPipelineColorBlendAttachmentState.alphaBlendOp', PtrUInt(@V.alphaBlendOp) - PtrUInt(@V), 24);
  CheckOffset('TVkPipelineColorBlendAttachmentState.colorWriteMask', PtrUInt(@V.colorWriteMask) - PtrUInt(@V), 28);
end;

procedure Layout_VkPipelineColorBlendStateCreateInfo;
var
  V: TVkPipelineColorBlendStateCreateInfo;
begin
  CheckSize('TVkPipelineColorBlendStateCreateInfo', SizeOf(V), 56);
  CheckOffset('TVkPipelineColorBlendStateCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPipelineColorBlendStateCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPipelineColorBlendStateCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkPipelineColorBlendStateCreateInfo.logicOpEnable', PtrUInt(@V.logicOpEnable) - PtrUInt(@V), 20);
  CheckOffset('TVkPipelineColorBlendStateCreateInfo.logicOp', PtrUInt(@V.logicOp) - PtrUInt(@V), 24);
  CheckOffset('TVkPipelineColorBlendStateCreateInfo.attachmentCount', PtrUInt(@V.attachmentCount) - PtrUInt(@V), 28);
  CheckOffset('TVkPipelineColorBlendStateCreateInfo.pAttachments', PtrUInt(@V.pAttachments) - PtrUInt(@V), 32);
  CheckOffset('TVkPipelineColorBlendStateCreateInfo.blendConstants', PtrUInt(@V.blendConstants) - PtrUInt(@V), 40);
end;

procedure Layout_VkPipelineDepthStencilStateCreateInfo;
var
  V: TVkPipelineDepthStencilStateCreateInfo;
begin
  CheckSize('TVkPipelineDepthStencilStateCreateInfo', SizeOf(V), 104);
  CheckOffset('TVkPipelineDepthStencilStateCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPipelineDepthStencilStateCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPipelineDepthStencilStateCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkPipelineDepthStencilStateCreateInfo.depthTestEnable', PtrUInt(@V.depthTestEnable) - PtrUInt(@V), 20);
  CheckOffset('TVkPipelineDepthStencilStateCreateInfo.depthWriteEnable', PtrUInt(@V.depthWriteEnable) - PtrUInt(@V), 24);
  CheckOffset('TVkPipelineDepthStencilStateCreateInfo.depthCompareOp', PtrUInt(@V.depthCompareOp) - PtrUInt(@V), 28);
  CheckOffset('TVkPipelineDepthStencilStateCreateInfo.depthBoundsTestEnable', PtrUInt(@V.depthBoundsTestEnable) - PtrUInt(@V), 32);
  CheckOffset('TVkPipelineDepthStencilStateCreateInfo.stencilTestEnable', PtrUInt(@V.stencilTestEnable) - PtrUInt(@V), 36);
  CheckOffset('TVkPipelineDepthStencilStateCreateInfo.front', PtrUInt(@V.front) - PtrUInt(@V), 40);
  CheckOffset('TVkPipelineDepthStencilStateCreateInfo.back', PtrUInt(@V.back) - PtrUInt(@V), 68);
  CheckOffset('TVkPipelineDepthStencilStateCreateInfo.minDepthBounds', PtrUInt(@V.minDepthBounds) - PtrUInt(@V), 96);
  CheckOffset('TVkPipelineDepthStencilStateCreateInfo.maxDepthBounds', PtrUInt(@V.maxDepthBounds) - PtrUInt(@V), 100);
end;

procedure Layout_VkPipelineDynamicStateCreateInfo;
var
  V: TVkPipelineDynamicStateCreateInfo;
begin
  CheckSize('TVkPipelineDynamicStateCreateInfo', SizeOf(V), 32);
  CheckOffset('TVkPipelineDynamicStateCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPipelineDynamicStateCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPipelineDynamicStateCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkPipelineDynamicStateCreateInfo.dynamicStateCount', PtrUInt(@V.dynamicStateCount) - PtrUInt(@V), 20);
  CheckOffset('TVkPipelineDynamicStateCreateInfo.pDynamicStates', PtrUInt(@V.pDynamicStates) - PtrUInt(@V), 24);
end;

procedure Layout_VkPipelineInputAssemblyStateCreateInfo;
var
  V: TVkPipelineInputAssemblyStateCreateInfo;
begin
  CheckSize('TVkPipelineInputAssemblyStateCreateInfo', SizeOf(V), 32);
  CheckOffset('TVkPipelineInputAssemblyStateCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPipelineInputAssemblyStateCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPipelineInputAssemblyStateCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkPipelineInputAssemblyStateCreateInfo.topology', PtrUInt(@V.topology) - PtrUInt(@V), 20);
  CheckOffset('TVkPipelineInputAssemblyStateCreateInfo.primitiveRestartEnable', PtrUInt(@V.primitiveRestartEnable) - PtrUInt(@V), 24);
end;

procedure Layout_VkPipelineLayoutCreateInfo;
var
  V: TVkPipelineLayoutCreateInfo;
begin
  CheckSize('TVkPipelineLayoutCreateInfo', SizeOf(V), 48);
  CheckOffset('TVkPipelineLayoutCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPipelineLayoutCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPipelineLayoutCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkPipelineLayoutCreateInfo.setLayoutCount', PtrUInt(@V.setLayoutCount) - PtrUInt(@V), 20);
  CheckOffset('TVkPipelineLayoutCreateInfo.pSetLayouts', PtrUInt(@V.pSetLayouts) - PtrUInt(@V), 24);
  CheckOffset('TVkPipelineLayoutCreateInfo.pushConstantRangeCount', PtrUInt(@V.pushConstantRangeCount) - PtrUInt(@V), 32);
  CheckOffset('TVkPipelineLayoutCreateInfo.pPushConstantRanges', PtrUInt(@V.pPushConstantRanges) - PtrUInt(@V), 40);
end;

procedure Layout_VkPipelineMultisampleStateCreateInfo;
var
  V: TVkPipelineMultisampleStateCreateInfo;
begin
  CheckSize('TVkPipelineMultisampleStateCreateInfo', SizeOf(V), 48);
  CheckOffset('TVkPipelineMultisampleStateCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPipelineMultisampleStateCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPipelineMultisampleStateCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkPipelineMultisampleStateCreateInfo.rasterizationSamples', PtrUInt(@V.rasterizationSamples) - PtrUInt(@V), 20);
  CheckOffset('TVkPipelineMultisampleStateCreateInfo.sampleShadingEnable', PtrUInt(@V.sampleShadingEnable) - PtrUInt(@V), 24);
  CheckOffset('TVkPipelineMultisampleStateCreateInfo.minSampleShading', PtrUInt(@V.minSampleShading) - PtrUInt(@V), 28);
  CheckOffset('TVkPipelineMultisampleStateCreateInfo.pSampleMask', PtrUInt(@V.pSampleMask) - PtrUInt(@V), 32);
  CheckOffset('TVkPipelineMultisampleStateCreateInfo.alphaToCoverageEnable', PtrUInt(@V.alphaToCoverageEnable) - PtrUInt(@V), 40);
  CheckOffset('TVkPipelineMultisampleStateCreateInfo.alphaToOneEnable', PtrUInt(@V.alphaToOneEnable) - PtrUInt(@V), 44);
end;

procedure Layout_VkPipelineRasterizationStateCreateInfo;
var
  V: TVkPipelineRasterizationStateCreateInfo;
begin
  CheckSize('TVkPipelineRasterizationStateCreateInfo', SizeOf(V), 64);
  CheckOffset('TVkPipelineRasterizationStateCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPipelineRasterizationStateCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPipelineRasterizationStateCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkPipelineRasterizationStateCreateInfo.depthClampEnable', PtrUInt(@V.depthClampEnable) - PtrUInt(@V), 20);
  CheckOffset('TVkPipelineRasterizationStateCreateInfo.rasterizerDiscardEnable', PtrUInt(@V.rasterizerDiscardEnable) - PtrUInt(@V), 24);
  CheckOffset('TVkPipelineRasterizationStateCreateInfo.polygonMode', PtrUInt(@V.polygonMode) - PtrUInt(@V), 28);
  CheckOffset('TVkPipelineRasterizationStateCreateInfo.cullMode', PtrUInt(@V.cullMode) - PtrUInt(@V), 32);
  CheckOffset('TVkPipelineRasterizationStateCreateInfo.frontFace', PtrUInt(@V.frontFace) - PtrUInt(@V), 36);
  CheckOffset('TVkPipelineRasterizationStateCreateInfo.depthBiasEnable', PtrUInt(@V.depthBiasEnable) - PtrUInt(@V), 40);
  CheckOffset('TVkPipelineRasterizationStateCreateInfo.depthBiasConstantFactor', PtrUInt(@V.depthBiasConstantFactor) - PtrUInt(@V), 44);
  CheckOffset('TVkPipelineRasterizationStateCreateInfo.depthBiasClamp', PtrUInt(@V.depthBiasClamp) - PtrUInt(@V), 48);
  CheckOffset('TVkPipelineRasterizationStateCreateInfo.depthBiasSlopeFactor', PtrUInt(@V.depthBiasSlopeFactor) - PtrUInt(@V), 52);
  CheckOffset('TVkPipelineRasterizationStateCreateInfo.lineWidth', PtrUInt(@V.lineWidth) - PtrUInt(@V), 56);
end;

procedure Layout_VkPipelineShaderStageCreateInfo;
var
  V: TVkPipelineShaderStageCreateInfo;
begin
  CheckSize('TVkPipelineShaderStageCreateInfo', SizeOf(V), 48);
  CheckOffset('TVkPipelineShaderStageCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPipelineShaderStageCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPipelineShaderStageCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkPipelineShaderStageCreateInfo.stage', PtrUInt(@V.stage) - PtrUInt(@V), 20);
  CheckOffset('TVkPipelineShaderStageCreateInfo.module', PtrUInt(@V.module) - PtrUInt(@V), 24);
  CheckOffset('TVkPipelineShaderStageCreateInfo.pName', PtrUInt(@V.pName) - PtrUInt(@V), 32);
  CheckOffset('TVkPipelineShaderStageCreateInfo.pSpecializationInfo', PtrUInt(@V.pSpecializationInfo) - PtrUInt(@V), 40);
end;

procedure Layout_VkPipelineTessellationStateCreateInfo;
var
  V: TVkPipelineTessellationStateCreateInfo;
begin
  CheckSize('TVkPipelineTessellationStateCreateInfo', SizeOf(V), 24);
  CheckOffset('TVkPipelineTessellationStateCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPipelineTessellationStateCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPipelineTessellationStateCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkPipelineTessellationStateCreateInfo.patchControlPoints', PtrUInt(@V.patchControlPoints) - PtrUInt(@V), 20);
end;

procedure Layout_VkPipelineVertexInputStateCreateInfo;
var
  V: TVkPipelineVertexInputStateCreateInfo;
begin
  CheckSize('TVkPipelineVertexInputStateCreateInfo', SizeOf(V), 48);
  CheckOffset('TVkPipelineVertexInputStateCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPipelineVertexInputStateCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPipelineVertexInputStateCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkPipelineVertexInputStateCreateInfo.vertexBindingDescriptionCount', PtrUInt(@V.vertexBindingDescriptionCount) - PtrUInt(@V), 20);
  CheckOffset('TVkPipelineVertexInputStateCreateInfo.pVertexBindingDescriptions', PtrUInt(@V.pVertexBindingDescriptions) - PtrUInt(@V), 24);
  CheckOffset('TVkPipelineVertexInputStateCreateInfo.vertexAttributeDescriptionCount', PtrUInt(@V.vertexAttributeDescriptionCount) - PtrUInt(@V), 32);
  CheckOffset('TVkPipelineVertexInputStateCreateInfo.pVertexAttributeDescriptions', PtrUInt(@V.pVertexAttributeDescriptions) - PtrUInt(@V), 40);
end;

procedure Layout_VkPipelineViewportStateCreateInfo;
var
  V: TVkPipelineViewportStateCreateInfo;
begin
  CheckSize('TVkPipelineViewportStateCreateInfo', SizeOf(V), 48);
  CheckOffset('TVkPipelineViewportStateCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPipelineViewportStateCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPipelineViewportStateCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkPipelineViewportStateCreateInfo.viewportCount', PtrUInt(@V.viewportCount) - PtrUInt(@V), 20);
  CheckOffset('TVkPipelineViewportStateCreateInfo.pViewports', PtrUInt(@V.pViewports) - PtrUInt(@V), 24);
  CheckOffset('TVkPipelineViewportStateCreateInfo.scissorCount', PtrUInt(@V.scissorCount) - PtrUInt(@V), 32);
  CheckOffset('TVkPipelineViewportStateCreateInfo.pScissors', PtrUInt(@V.pScissors) - PtrUInt(@V), 40);
end;

procedure Layout_VkPresentInfoKHR;
var
  V: TVkPresentInfoKHR;
begin
  CheckSize('TVkPresentInfoKHR', SizeOf(V), 64);
  CheckOffset('TVkPresentInfoKHR.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkPresentInfoKHR.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkPresentInfoKHR.waitSemaphoreCount', PtrUInt(@V.waitSemaphoreCount) - PtrUInt(@V), 16);
  CheckOffset('TVkPresentInfoKHR.pWaitSemaphores', PtrUInt(@V.pWaitSemaphores) - PtrUInt(@V), 24);
  CheckOffset('TVkPresentInfoKHR.swapchainCount', PtrUInt(@V.swapchainCount) - PtrUInt(@V), 32);
  CheckOffset('TVkPresentInfoKHR.pSwapchains', PtrUInt(@V.pSwapchains) - PtrUInt(@V), 40);
  CheckOffset('TVkPresentInfoKHR.pImageIndices', PtrUInt(@V.pImageIndices) - PtrUInt(@V), 48);
  CheckOffset('TVkPresentInfoKHR.pResults', PtrUInt(@V.pResults) - PtrUInt(@V), 56);
end;

procedure Layout_VkPushConstantRange;
var
  V: TVkPushConstantRange;
begin
  CheckSize('TVkPushConstantRange', SizeOf(V), 12);
  CheckOffset('TVkPushConstantRange.stageFlags', PtrUInt(@V.stageFlags) - PtrUInt(@V), 0);
  CheckOffset('TVkPushConstantRange.offset', PtrUInt(@V.offset) - PtrUInt(@V), 4);
  CheckOffset('TVkPushConstantRange.size', PtrUInt(@V.size) - PtrUInt(@V), 8);
end;

procedure Layout_VkQueueFamilyProperties;
var
  V: TVkQueueFamilyProperties;
begin
  CheckSize('TVkQueueFamilyProperties', SizeOf(V), 24);
  CheckOffset('TVkQueueFamilyProperties.queueFlags', PtrUInt(@V.queueFlags) - PtrUInt(@V), 0);
  CheckOffset('TVkQueueFamilyProperties.queueCount', PtrUInt(@V.queueCount) - PtrUInt(@V), 4);
  CheckOffset('TVkQueueFamilyProperties.timestampValidBits', PtrUInt(@V.timestampValidBits) - PtrUInt(@V), 8);
  CheckOffset('TVkQueueFamilyProperties.minImageTransferGranularity', PtrUInt(@V.minImageTransferGranularity) - PtrUInt(@V), 12);
end;

procedure Layout_VkRect2D;
var
  V: TVkRect2D;
begin
  CheckSize('TVkRect2D', SizeOf(V), 16);
  CheckOffset('TVkRect2D.offset', PtrUInt(@V.offset) - PtrUInt(@V), 0);
  CheckOffset('TVkRect2D.extent', PtrUInt(@V.extent) - PtrUInt(@V), 8);
end;

procedure Layout_VkRenderPassBeginInfo;
var
  V: TVkRenderPassBeginInfo;
begin
  CheckSize('TVkRenderPassBeginInfo', SizeOf(V), 64);
  CheckOffset('TVkRenderPassBeginInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkRenderPassBeginInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkRenderPassBeginInfo.renderPass', PtrUInt(@V.renderPass) - PtrUInt(@V), 16);
  CheckOffset('TVkRenderPassBeginInfo.framebuffer', PtrUInt(@V.framebuffer) - PtrUInt(@V), 24);
  CheckOffset('TVkRenderPassBeginInfo.renderArea', PtrUInt(@V.renderArea) - PtrUInt(@V), 32);
  CheckOffset('TVkRenderPassBeginInfo.clearValueCount', PtrUInt(@V.clearValueCount) - PtrUInt(@V), 48);
  CheckOffset('TVkRenderPassBeginInfo.pClearValues', PtrUInt(@V.pClearValues) - PtrUInt(@V), 56);
end;

procedure Layout_VkRenderPassCreateInfo;
var
  V: TVkRenderPassCreateInfo;
begin
  CheckSize('TVkRenderPassCreateInfo', SizeOf(V), 64);
  CheckOffset('TVkRenderPassCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkRenderPassCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkRenderPassCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkRenderPassCreateInfo.attachmentCount', PtrUInt(@V.attachmentCount) - PtrUInt(@V), 20);
  CheckOffset('TVkRenderPassCreateInfo.pAttachments', PtrUInt(@V.pAttachments) - PtrUInt(@V), 24);
  CheckOffset('TVkRenderPassCreateInfo.subpassCount', PtrUInt(@V.subpassCount) - PtrUInt(@V), 32);
  CheckOffset('TVkRenderPassCreateInfo.pSubpasses', PtrUInt(@V.pSubpasses) - PtrUInt(@V), 40);
  CheckOffset('TVkRenderPassCreateInfo.dependencyCount', PtrUInt(@V.dependencyCount) - PtrUInt(@V), 48);
  CheckOffset('TVkRenderPassCreateInfo.pDependencies', PtrUInt(@V.pDependencies) - PtrUInt(@V), 56);
end;

procedure Layout_VkSamplerCreateInfo;
var
  V: TVkSamplerCreateInfo;
begin
  CheckSize('TVkSamplerCreateInfo', SizeOf(V), 80);
  CheckOffset('TVkSamplerCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkSamplerCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkSamplerCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkSamplerCreateInfo.magFilter', PtrUInt(@V.magFilter) - PtrUInt(@V), 20);
  CheckOffset('TVkSamplerCreateInfo.minFilter', PtrUInt(@V.minFilter) - PtrUInt(@V), 24);
  CheckOffset('TVkSamplerCreateInfo.mipmapMode', PtrUInt(@V.mipmapMode) - PtrUInt(@V), 28);
  CheckOffset('TVkSamplerCreateInfo.addressModeU', PtrUInt(@V.addressModeU) - PtrUInt(@V), 32);
  CheckOffset('TVkSamplerCreateInfo.addressModeV', PtrUInt(@V.addressModeV) - PtrUInt(@V), 36);
  CheckOffset('TVkSamplerCreateInfo.addressModeW', PtrUInt(@V.addressModeW) - PtrUInt(@V), 40);
  CheckOffset('TVkSamplerCreateInfo.mipLodBias', PtrUInt(@V.mipLodBias) - PtrUInt(@V), 44);
  CheckOffset('TVkSamplerCreateInfo.anisotropyEnable', PtrUInt(@V.anisotropyEnable) - PtrUInt(@V), 48);
  CheckOffset('TVkSamplerCreateInfo.maxAnisotropy', PtrUInt(@V.maxAnisotropy) - PtrUInt(@V), 52);
  CheckOffset('TVkSamplerCreateInfo.compareEnable', PtrUInt(@V.compareEnable) - PtrUInt(@V), 56);
  CheckOffset('TVkSamplerCreateInfo.compareOp', PtrUInt(@V.compareOp) - PtrUInt(@V), 60);
  CheckOffset('TVkSamplerCreateInfo.minLod', PtrUInt(@V.minLod) - PtrUInt(@V), 64);
  CheckOffset('TVkSamplerCreateInfo.maxLod', PtrUInt(@V.maxLod) - PtrUInt(@V), 68);
  CheckOffset('TVkSamplerCreateInfo.borderColor', PtrUInt(@V.borderColor) - PtrUInt(@V), 72);
  CheckOffset('TVkSamplerCreateInfo.unnormalizedCoordinates', PtrUInt(@V.unnormalizedCoordinates) - PtrUInt(@V), 76);
end;

procedure Layout_VkSamplerYcbcrConversionCreateInfo;
var
  V: TVkSamplerYcbcrConversionCreateInfo;
begin
  CheckSize('TVkSamplerYcbcrConversionCreateInfo', SizeOf(V), 64);
  CheckOffset('TVkSamplerYcbcrConversionCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkSamplerYcbcrConversionCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkSamplerYcbcrConversionCreateInfo.format', PtrUInt(@V.format) - PtrUInt(@V), 16);
  CheckOffset('TVkSamplerYcbcrConversionCreateInfo.ycbcrModel', PtrUInt(@V.ycbcrModel) - PtrUInt(@V), 20);
  CheckOffset('TVkSamplerYcbcrConversionCreateInfo.ycbcrRange', PtrUInt(@V.ycbcrRange) - PtrUInt(@V), 24);
  CheckOffset('TVkSamplerYcbcrConversionCreateInfo.components', PtrUInt(@V.components) - PtrUInt(@V), 28);
  CheckOffset('TVkSamplerYcbcrConversionCreateInfo.xChromaOffset', PtrUInt(@V.xChromaOffset) - PtrUInt(@V), 44);
  CheckOffset('TVkSamplerYcbcrConversionCreateInfo.yChromaOffset', PtrUInt(@V.yChromaOffset) - PtrUInt(@V), 48);
  CheckOffset('TVkSamplerYcbcrConversionCreateInfo.chromaFilter', PtrUInt(@V.chromaFilter) - PtrUInt(@V), 52);
  CheckOffset('TVkSamplerYcbcrConversionCreateInfo.forceExplicitReconstruction', PtrUInt(@V.forceExplicitReconstruction) - PtrUInt(@V), 56);
end;

procedure Layout_VkSamplerYcbcrConversionInfo;
var
  V: TVkSamplerYcbcrConversionInfo;
begin
  CheckSize('TVkSamplerYcbcrConversionInfo', SizeOf(V), 24);
  CheckOffset('TVkSamplerYcbcrConversionInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkSamplerYcbcrConversionInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkSamplerYcbcrConversionInfo.conversion', PtrUInt(@V.conversion) - PtrUInt(@V), 16);
end;

procedure Layout_VkSemaphoreCreateInfo;
var
  V: TVkSemaphoreCreateInfo;
begin
  CheckSize('TVkSemaphoreCreateInfo', SizeOf(V), 24);
  CheckOffset('TVkSemaphoreCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkSemaphoreCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkSemaphoreCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
end;

procedure Layout_VkShaderModuleCreateInfo;
var
  V: TVkShaderModuleCreateInfo;
begin
  CheckSize('TVkShaderModuleCreateInfo', SizeOf(V), 40);
  CheckOffset('TVkShaderModuleCreateInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkShaderModuleCreateInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkShaderModuleCreateInfo.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkShaderModuleCreateInfo.codeSize', PtrUInt(@V.codeSize) - PtrUInt(@V), 24);
  CheckOffset('TVkShaderModuleCreateInfo.pCode', PtrUInt(@V.pCode) - PtrUInt(@V), 32);
end;

procedure Layout_VkSpecializationInfo;
var
  V: TVkSpecializationInfo;
begin
  CheckSize('TVkSpecializationInfo', SizeOf(V), 32);
  CheckOffset('TVkSpecializationInfo.mapEntryCount', PtrUInt(@V.mapEntryCount) - PtrUInt(@V), 0);
  CheckOffset('TVkSpecializationInfo.pMapEntries', PtrUInt(@V.pMapEntries) - PtrUInt(@V), 8);
  CheckOffset('TVkSpecializationInfo.dataSize', PtrUInt(@V.dataSize) - PtrUInt(@V), 16);
  CheckOffset('TVkSpecializationInfo.pData', PtrUInt(@V.pData) - PtrUInt(@V), 24);
end;

procedure Layout_VkSpecializationMapEntry;
var
  V: TVkSpecializationMapEntry;
begin
  CheckSize('TVkSpecializationMapEntry', SizeOf(V), 16);
  CheckOffset('TVkSpecializationMapEntry.constantID', PtrUInt(@V.constantID) - PtrUInt(@V), 0);
  CheckOffset('TVkSpecializationMapEntry.offset', PtrUInt(@V.offset) - PtrUInt(@V), 4);
  CheckOffset('TVkSpecializationMapEntry.size', PtrUInt(@V.size) - PtrUInt(@V), 8);
end;

procedure Layout_VkStencilOpState;
var
  V: TVkStencilOpState;
begin
  CheckSize('TVkStencilOpState', SizeOf(V), 28);
  CheckOffset('TVkStencilOpState.failOp', PtrUInt(@V.failOp) - PtrUInt(@V), 0);
  CheckOffset('TVkStencilOpState.passOp', PtrUInt(@V.passOp) - PtrUInt(@V), 4);
  CheckOffset('TVkStencilOpState.depthFailOp', PtrUInt(@V.depthFailOp) - PtrUInt(@V), 8);
  CheckOffset('TVkStencilOpState.compareOp', PtrUInt(@V.compareOp) - PtrUInt(@V), 12);
  CheckOffset('TVkStencilOpState.compareMask', PtrUInt(@V.compareMask) - PtrUInt(@V), 16);
  CheckOffset('TVkStencilOpState.writeMask', PtrUInt(@V.writeMask) - PtrUInt(@V), 20);
  CheckOffset('TVkStencilOpState.reference', PtrUInt(@V.reference) - PtrUInt(@V), 24);
end;

procedure Layout_VkSubmitInfo;
var
  V: TVkSubmitInfo;
begin
  CheckSize('TVkSubmitInfo', SizeOf(V), 72);
  CheckOffset('TVkSubmitInfo.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkSubmitInfo.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkSubmitInfo.waitSemaphoreCount', PtrUInt(@V.waitSemaphoreCount) - PtrUInt(@V), 16);
  CheckOffset('TVkSubmitInfo.pWaitSemaphores', PtrUInt(@V.pWaitSemaphores) - PtrUInt(@V), 24);
  CheckOffset('TVkSubmitInfo.pWaitDstStageMask', PtrUInt(@V.pWaitDstStageMask) - PtrUInt(@V), 32);
  CheckOffset('TVkSubmitInfo.commandBufferCount', PtrUInt(@V.commandBufferCount) - PtrUInt(@V), 40);
  CheckOffset('TVkSubmitInfo.pCommandBuffers', PtrUInt(@V.pCommandBuffers) - PtrUInt(@V), 48);
  CheckOffset('TVkSubmitInfo.signalSemaphoreCount', PtrUInt(@V.signalSemaphoreCount) - PtrUInt(@V), 56);
  CheckOffset('TVkSubmitInfo.pSignalSemaphores', PtrUInt(@V.pSignalSemaphores) - PtrUInt(@V), 64);
end;

procedure Layout_VkSubpassDependency;
var
  V: TVkSubpassDependency;
begin
  CheckSize('TVkSubpassDependency', SizeOf(V), 28);
  CheckOffset('TVkSubpassDependency.srcSubpass', PtrUInt(@V.srcSubpass) - PtrUInt(@V), 0);
  CheckOffset('TVkSubpassDependency.dstSubpass', PtrUInt(@V.dstSubpass) - PtrUInt(@V), 4);
  CheckOffset('TVkSubpassDependency.srcStageMask', PtrUInt(@V.srcStageMask) - PtrUInt(@V), 8);
  CheckOffset('TVkSubpassDependency.dstStageMask', PtrUInt(@V.dstStageMask) - PtrUInt(@V), 12);
  CheckOffset('TVkSubpassDependency.srcAccessMask', PtrUInt(@V.srcAccessMask) - PtrUInt(@V), 16);
  CheckOffset('TVkSubpassDependency.dstAccessMask', PtrUInt(@V.dstAccessMask) - PtrUInt(@V), 20);
  CheckOffset('TVkSubpassDependency.dependencyFlags', PtrUInt(@V.dependencyFlags) - PtrUInt(@V), 24);
end;

procedure Layout_VkSubpassDescription;
var
  V: TVkSubpassDescription;
begin
  CheckSize('TVkSubpassDescription', SizeOf(V), 72);
  CheckOffset('TVkSubpassDescription.flags', PtrUInt(@V.flags) - PtrUInt(@V), 0);
  CheckOffset('TVkSubpassDescription.pipelineBindPoint', PtrUInt(@V.pipelineBindPoint) - PtrUInt(@V), 4);
  CheckOffset('TVkSubpassDescription.inputAttachmentCount', PtrUInt(@V.inputAttachmentCount) - PtrUInt(@V), 8);
  CheckOffset('TVkSubpassDescription.pInputAttachments', PtrUInt(@V.pInputAttachments) - PtrUInt(@V), 16);
  CheckOffset('TVkSubpassDescription.colorAttachmentCount', PtrUInt(@V.colorAttachmentCount) - PtrUInt(@V), 24);
  CheckOffset('TVkSubpassDescription.pColorAttachments', PtrUInt(@V.pColorAttachments) - PtrUInt(@V), 32);
  CheckOffset('TVkSubpassDescription.pResolveAttachments', PtrUInt(@V.pResolveAttachments) - PtrUInt(@V), 40);
  CheckOffset('TVkSubpassDescription.pDepthStencilAttachment', PtrUInt(@V.pDepthStencilAttachment) - PtrUInt(@V), 48);
  CheckOffset('TVkSubpassDescription.preserveAttachmentCount', PtrUInt(@V.preserveAttachmentCount) - PtrUInt(@V), 56);
  CheckOffset('TVkSubpassDescription.pPreserveAttachments', PtrUInt(@V.pPreserveAttachments) - PtrUInt(@V), 64);
end;

procedure Layout_VkSurfaceCapabilitiesKHR;
var
  V: TVkSurfaceCapabilitiesKHR;
begin
  CheckSize('TVkSurfaceCapabilitiesKHR', SizeOf(V), 52);
  CheckOffset('TVkSurfaceCapabilitiesKHR.minImageCount', PtrUInt(@V.minImageCount) - PtrUInt(@V), 0);
  CheckOffset('TVkSurfaceCapabilitiesKHR.maxImageCount', PtrUInt(@V.maxImageCount) - PtrUInt(@V), 4);
  CheckOffset('TVkSurfaceCapabilitiesKHR.currentExtent', PtrUInt(@V.currentExtent) - PtrUInt(@V), 8);
  CheckOffset('TVkSurfaceCapabilitiesKHR.minImageExtent', PtrUInt(@V.minImageExtent) - PtrUInt(@V), 16);
  CheckOffset('TVkSurfaceCapabilitiesKHR.maxImageExtent', PtrUInt(@V.maxImageExtent) - PtrUInt(@V), 24);
  CheckOffset('TVkSurfaceCapabilitiesKHR.maxImageArrayLayers', PtrUInt(@V.maxImageArrayLayers) - PtrUInt(@V), 32);
  CheckOffset('TVkSurfaceCapabilitiesKHR.supportedTransforms', PtrUInt(@V.supportedTransforms) - PtrUInt(@V), 36);
  CheckOffset('TVkSurfaceCapabilitiesKHR.currentTransform', PtrUInt(@V.currentTransform) - PtrUInt(@V), 40);
  CheckOffset('TVkSurfaceCapabilitiesKHR.supportedCompositeAlpha', PtrUInt(@V.supportedCompositeAlpha) - PtrUInt(@V), 44);
  CheckOffset('TVkSurfaceCapabilitiesKHR.supportedUsageFlags', PtrUInt(@V.supportedUsageFlags) - PtrUInt(@V), 48);
end;

procedure Layout_VkSurfaceFormatKHR;
var
  V: TVkSurfaceFormatKHR;
begin
  CheckSize('TVkSurfaceFormatKHR', SizeOf(V), 8);
  CheckOffset('TVkSurfaceFormatKHR.format', PtrUInt(@V.format) - PtrUInt(@V), 0);
  CheckOffset('TVkSurfaceFormatKHR.colorSpace', PtrUInt(@V.colorSpace) - PtrUInt(@V), 4);
end;

procedure Layout_VkSwapchainCreateInfoKHR;
var
  V: TVkSwapchainCreateInfoKHR;
begin
  CheckSize('TVkSwapchainCreateInfoKHR', SizeOf(V), 104);
  CheckOffset('TVkSwapchainCreateInfoKHR.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkSwapchainCreateInfoKHR.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkSwapchainCreateInfoKHR.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkSwapchainCreateInfoKHR.surface', PtrUInt(@V.surface) - PtrUInt(@V), 24);
  CheckOffset('TVkSwapchainCreateInfoKHR.minImageCount', PtrUInt(@V.minImageCount) - PtrUInt(@V), 32);
  CheckOffset('TVkSwapchainCreateInfoKHR.imageFormat', PtrUInt(@V.imageFormat) - PtrUInt(@V), 36);
  CheckOffset('TVkSwapchainCreateInfoKHR.imageColorSpace', PtrUInt(@V.imageColorSpace) - PtrUInt(@V), 40);
  CheckOffset('TVkSwapchainCreateInfoKHR.imageExtent', PtrUInt(@V.imageExtent) - PtrUInt(@V), 44);
  CheckOffset('TVkSwapchainCreateInfoKHR.imageArrayLayers', PtrUInt(@V.imageArrayLayers) - PtrUInt(@V), 52);
  CheckOffset('TVkSwapchainCreateInfoKHR.imageUsage', PtrUInt(@V.imageUsage) - PtrUInt(@V), 56);
  CheckOffset('TVkSwapchainCreateInfoKHR.imageSharingMode', PtrUInt(@V.imageSharingMode) - PtrUInt(@V), 60);
  CheckOffset('TVkSwapchainCreateInfoKHR.queueFamilyIndexCount', PtrUInt(@V.queueFamilyIndexCount) - PtrUInt(@V), 64);
  CheckOffset('TVkSwapchainCreateInfoKHR.pQueueFamilyIndices', PtrUInt(@V.pQueueFamilyIndices) - PtrUInt(@V), 72);
  CheckOffset('TVkSwapchainCreateInfoKHR.preTransform', PtrUInt(@V.preTransform) - PtrUInt(@V), 80);
  CheckOffset('TVkSwapchainCreateInfoKHR.compositeAlpha', PtrUInt(@V.compositeAlpha) - PtrUInt(@V), 84);
  CheckOffset('TVkSwapchainCreateInfoKHR.presentMode', PtrUInt(@V.presentMode) - PtrUInt(@V), 88);
  CheckOffset('TVkSwapchainCreateInfoKHR.clipped', PtrUInt(@V.clipped) - PtrUInt(@V), 92);
  CheckOffset('TVkSwapchainCreateInfoKHR.oldSwapchain', PtrUInt(@V.oldSwapchain) - PtrUInt(@V), 96);
end;

procedure Layout_VkVertexInputAttributeDescription;
var
  V: TVkVertexInputAttributeDescription;
begin
  CheckSize('TVkVertexInputAttributeDescription', SizeOf(V), 16);
  CheckOffset('TVkVertexInputAttributeDescription.location', PtrUInt(@V.location) - PtrUInt(@V), 0);
  CheckOffset('TVkVertexInputAttributeDescription.binding', PtrUInt(@V.binding) - PtrUInt(@V), 4);
  CheckOffset('TVkVertexInputAttributeDescription.format', PtrUInt(@V.format) - PtrUInt(@V), 8);
  CheckOffset('TVkVertexInputAttributeDescription.offset', PtrUInt(@V.offset) - PtrUInt(@V), 12);
end;

procedure Layout_VkVertexInputBindingDescription;
var
  V: TVkVertexInputBindingDescription;
begin
  CheckSize('TVkVertexInputBindingDescription', SizeOf(V), 12);
  CheckOffset('TVkVertexInputBindingDescription.binding', PtrUInt(@V.binding) - PtrUInt(@V), 0);
  CheckOffset('TVkVertexInputBindingDescription.stride', PtrUInt(@V.stride) - PtrUInt(@V), 4);
  CheckOffset('TVkVertexInputBindingDescription.inputRate', PtrUInt(@V.inputRate) - PtrUInt(@V), 8);
end;

procedure Layout_VkViewport;
var
  V: TVkViewport;
begin
  CheckSize('TVkViewport', SizeOf(V), 24);
  CheckOffset('TVkViewport.x', PtrUInt(@V.x) - PtrUInt(@V), 0);
  CheckOffset('TVkViewport.y', PtrUInt(@V.y) - PtrUInt(@V), 4);
  CheckOffset('TVkViewport.width', PtrUInt(@V.width) - PtrUInt(@V), 8);
  CheckOffset('TVkViewport.height', PtrUInt(@V.height) - PtrUInt(@V), 12);
  CheckOffset('TVkViewport.minDepth', PtrUInt(@V.minDepth) - PtrUInt(@V), 16);
  CheckOffset('TVkViewport.maxDepth', PtrUInt(@V.maxDepth) - PtrUInt(@V), 20);
end;

procedure Layout_VkWaylandSurfaceCreateInfoKHR;
var
  V: TVkWaylandSurfaceCreateInfoKHR;
begin
  CheckSize('TVkWaylandSurfaceCreateInfoKHR', SizeOf(V), 40);
  CheckOffset('TVkWaylandSurfaceCreateInfoKHR.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkWaylandSurfaceCreateInfoKHR.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkWaylandSurfaceCreateInfoKHR.flags', PtrUInt(@V.flags) - PtrUInt(@V), 16);
  CheckOffset('TVkWaylandSurfaceCreateInfoKHR.display', PtrUInt(@V.display) - PtrUInt(@V), 24);
  CheckOffset('TVkWaylandSurfaceCreateInfoKHR.surface', PtrUInt(@V.surface) - PtrUInt(@V), 32);
end;

procedure Layout_VkWriteDescriptorSet;
var
  V: TVkWriteDescriptorSet;
begin
  CheckSize('TVkWriteDescriptorSet', SizeOf(V), 64);
  CheckOffset('TVkWriteDescriptorSet.sType', PtrUInt(@V.sType) - PtrUInt(@V), 0);
  CheckOffset('TVkWriteDescriptorSet.pNext', PtrUInt(@V.pNext) - PtrUInt(@V), 8);
  CheckOffset('TVkWriteDescriptorSet.dstSet', PtrUInt(@V.dstSet) - PtrUInt(@V), 16);
  CheckOffset('TVkWriteDescriptorSet.dstBinding', PtrUInt(@V.dstBinding) - PtrUInt(@V), 24);
  CheckOffset('TVkWriteDescriptorSet.dstArrayElement', PtrUInt(@V.dstArrayElement) - PtrUInt(@V), 28);
  CheckOffset('TVkWriteDescriptorSet.descriptorCount', PtrUInt(@V.descriptorCount) - PtrUInt(@V), 32);
  CheckOffset('TVkWriteDescriptorSet.descriptorType', PtrUInt(@V.descriptorType) - PtrUInt(@V), 36);
  CheckOffset('TVkWriteDescriptorSet.pImageInfo', PtrUInt(@V.pImageInfo) - PtrUInt(@V), 40);
  CheckOffset('TVkWriteDescriptorSet.pBufferInfo', PtrUInt(@V.pBufferInfo) - PtrUInt(@V), 48);
  CheckOffset('TVkWriteDescriptorSet.pTexelBufferView', PtrUInt(@V.pTexelBufferView) - PtrUInt(@V), 56);
end;

procedure AllLayouts;
begin
  Layout_VkAllocationCallbacks;
  Layout_VkApplicationInfo;
  Layout_VkAttachmentDescription;
  Layout_VkAttachmentReference;
  Layout_VkBufferCreateInfo;
  Layout_VkBufferImageCopy;
  Layout_VkBufferMemoryBarrier;
  Layout_VkClearColorValue;
  Layout_VkClearDepthStencilValue;
  Layout_VkClearValue;
  Layout_VkCommandBufferAllocateInfo;
  Layout_VkCommandBufferBeginInfo;
  Layout_VkCommandBufferInheritanceInfo;
  Layout_VkCommandPoolCreateInfo;
  Layout_VkComponentMapping;
  Layout_VkCopyDescriptorSet;
  Layout_VkDescriptorBufferInfo;
  Layout_VkDescriptorImageInfo;
  Layout_VkDescriptorPoolCreateInfo;
  Layout_VkDescriptorPoolSize;
  Layout_VkDescriptorSetAllocateInfo;
  Layout_VkDescriptorSetLayoutBinding;
  Layout_VkDescriptorSetLayoutCreateInfo;
  Layout_VkDeviceCreateInfo;
  Layout_VkDeviceQueueCreateInfo;
  Layout_VkExtensionProperties;
  Layout_VkExtent2D;
  Layout_VkExtent3D;
  Layout_VkExternalMemoryImageCreateInfo;
  Layout_VkFenceCreateInfo;
  Layout_VkFramebufferCreateInfo;
  Layout_VkGraphicsPipelineCreateInfo;
  Layout_VkImageCreateInfo;
  Layout_VkImageFormatProperties;
  Layout_VkImageMemoryBarrier;
  Layout_VkImageSubresourceLayers;
  Layout_VkImageSubresourceRange;
  Layout_VkImageViewCreateInfo;
  Layout_VkImageViewUsageCreateInfo;
  Layout_VkInstanceCreateInfo;
  Layout_VkLayerProperties;
  Layout_VkMemoryAllocateInfo;
  Layout_VkMemoryBarrier;
  Layout_VkMemoryDedicatedAllocateInfo;
  Layout_VkMemoryHeap;
  Layout_VkMemoryRequirements;
  Layout_VkMemoryType;
  Layout_VkOffset2D;
  Layout_VkOffset3D;
  Layout_VkPhysicalDeviceFeatures;
  Layout_VkPhysicalDeviceFeatures2;
  Layout_VkPhysicalDeviceLimits;
  Layout_VkPhysicalDeviceMemoryProperties;
  Layout_VkPhysicalDeviceMemoryProperties2;
  Layout_VkPhysicalDeviceProperties;
  Layout_VkPhysicalDeviceProperties2;
  Layout_VkPhysicalDeviceSamplerYcbcrConversionFeatures;
  Layout_VkPhysicalDeviceSparseProperties;
  Layout_VkPipelineColorBlendAttachmentState;
  Layout_VkPipelineColorBlendStateCreateInfo;
  Layout_VkPipelineDepthStencilStateCreateInfo;
  Layout_VkPipelineDynamicStateCreateInfo;
  Layout_VkPipelineInputAssemblyStateCreateInfo;
  Layout_VkPipelineLayoutCreateInfo;
  Layout_VkPipelineMultisampleStateCreateInfo;
  Layout_VkPipelineRasterizationStateCreateInfo;
  Layout_VkPipelineShaderStageCreateInfo;
  Layout_VkPipelineTessellationStateCreateInfo;
  Layout_VkPipelineVertexInputStateCreateInfo;
  Layout_VkPipelineViewportStateCreateInfo;
  Layout_VkPresentInfoKHR;
  Layout_VkPushConstantRange;
  Layout_VkQueueFamilyProperties;
  Layout_VkRect2D;
  Layout_VkRenderPassBeginInfo;
  Layout_VkRenderPassCreateInfo;
  Layout_VkSamplerCreateInfo;
  Layout_VkSamplerYcbcrConversionCreateInfo;
  Layout_VkSamplerYcbcrConversionInfo;
  Layout_VkSemaphoreCreateInfo;
  Layout_VkShaderModuleCreateInfo;
  Layout_VkSpecializationInfo;
  Layout_VkSpecializationMapEntry;
  Layout_VkStencilOpState;
  Layout_VkSubmitInfo;
  Layout_VkSubpassDependency;
  Layout_VkSubpassDescription;
  Layout_VkSurfaceCapabilitiesKHR;
  Layout_VkSurfaceFormatKHR;
  Layout_VkSwapchainCreateInfoKHR;
  Layout_VkVertexInputAttributeDescription;
  Layout_VkVertexInputBindingDescription;
  Layout_VkViewport;
  Layout_VkWaylandSurfaceCreateInfoKHR;
  Layout_VkWriteDescriptorSet;
end;
const
  LayoutCount = 95;
