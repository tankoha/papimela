{ src/generated/vulkan_bind_global.inc — tools/genvulkan.bb が作る。手で直さない。 }
  Bind(AFuncs.vkCreateInstance, 'vkCreateInstance');
  Bind(AFuncs.vkEnumerateInstanceExtensionProperties, 'vkEnumerateInstanceExtensionProperties');
  Bind(AFuncs.vkEnumerateInstanceLayerProperties, 'vkEnumerateInstanceLayerProperties');
