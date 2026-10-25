#!/usr/bin/env bb
;; genvulkan — Vulkan の型・定数・関数表を、SDL 同梱の Khronos ヘッダから Pascal へ写す。
;;
;; なぜ要るか:
;;   Render.Vulkan と Video.Wayland.Vulkan（設計 #67）は SDL の移植で、SDL が使う Vulkan の型・定数・関数だけを持つ。
;;   papimela は C のヘッダを使えない（バインディングではない）。手で写すと写し間違える
;;   （CLAUDE.md: 大きな表は手にも qwen にも写させない）ので、SDL が同梱する Khronos ヘッダ
;;   reference/SDL/src/video/khronos/vulkan/ の vulkan_core.h と vulkan_wayland.h を読んで作る。
;;
;; 使い方:
;;   tools/genvulkan.bb            生成物を書く
;;   tools/genvulkan.bb --check    書いてあるものが古くないかを見る（CI。差があれば失敗）
;;   tools/genvulkan.bb --layout   gcc で実物の sizeof / offsetof を取り、test/vulkan_layout.inc を作る
;;                                 （Pascal の record の配置との往復検査の期待値。gcc が要る）
;;
;; 書くもの（src/generated/）:
;;   vulkan_types.inc        型（ハンドル・列挙・フラグ・record・union・関数の型）。ポインタ型を先頭に置く
;;   vulkan_constants.inc    定数（SDL が使う VK_ の名前。列挙の値・マクロの数値・拡張名の文字列）
;;   vulkan_functions_{global,instance,device}.inc  関数表のフィールド（PFN の型）
;;   vulkan_bind_{global,instance,device}.inc       表を埋める本文
;;
;; 型の方針:
;;   - record は T を付ける（TVkInstanceCreateInfo）。そのポインタは PVkInstanceCreateInfo。
;;     ハンドルと列挙とフラグは C の名前のまま（VkInstance = Pointer、VkFormat = LongInt）
;;   - 列挙は Pascal の列挙型にしない。C の値をそのまま定数にし、型は LongInt（C の int）。
;;     フラグは LongWord（VkFlags）、64 ビットのフラグは QWord
;;   - 非ディスパッチャブルのハンドルは UInt64（64 ビットでは C のポインタと同じ大きさ・渡し方）
;;   - 関数は 3 つの表に分ける: global（インスタンス無し）、instance、device（第 1 引数が
;;     VkDevice / VkQueue / VkCommandBuffer）。vkGetInstanceProcAddr は表に入れず、ローダから dlsym する
;;
;; 確かめること（どれかが合わなければ止まる）:
;;   - 並べた関数・定数・型がどれもヘッダで見つかる（見つからない名前は名前を出して止まる）
;;   - C の型がすべて対応表で解ける、配列の大きさが数に解ける
;;   - 書いた件数が、元の一覧から数えた件数と同じ
;;   - 同じ入力からは同じファイルができる（時刻などを書かない）

(require '[babashka.fs :as fs]
         '[babashka.process :as proc]
         '[clojure.string :as str])

(def ^:private header-dir "reference/SDL/src/video/khronos/vulkan")
(def ^:private out-dir "src/generated")
(def ^:private layout-out "test/vulkan_layout.inc")

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "genvulkan: " msg)))
  (System/exit 1))

(doseq [f ["vulkan_core.h" "vulkan_wayland.h"]]
  (when-not (fs/exists? (str header-dir "/" f)) (fail header-dir "/" f " が無い（docs/ORIGIN.md の取り直し方）")))

;; ---- 入口: SDL が使う名前。SDL の 4 ファイル（render/vulkan/SDL_render_vulkan.c、SDL_shaders_vulkan.c、
;;      video/SDL_vulkan_utils.c、video/wayland/SDL_waylandvulkan.c）の Vk / vk / VK_ の名前から、
;;      Android・KHR display（KMS）・コメントの打ち間違い・マクロの断片を除いたもの。

(def ^:private root-functions
  (str/split "vkAcquireNextImageKHR vkAllocateCommandBuffers vkAllocateDescriptorSets vkAllocateMemory vkBeginCommandBuffer
vkBindBufferMemory vkBindImageMemory vkCmdBeginRenderPass vkCmdBindDescriptorSets vkCmdBindPipeline vkCmdBindVertexBuffers
vkCmdClearColorImage vkCmdCopyBufferToImage vkCmdCopyImageToBuffer vkCmdDraw vkCmdEndRenderPass vkCmdPipelineBarrier
vkCmdPushConstants vkCmdSetScissor vkCmdSetViewport vkCreateBuffer vkCreateCommandPool vkCreateDescriptorPool
vkCreateDescriptorSetLayout vkCreateDevice vkCreateFence vkCreateFramebuffer vkCreateGraphicsPipelines vkCreateImage
vkCreateImageView vkCreateInstance vkCreatePipelineLayout vkCreateRenderPass vkCreateSampler
vkCreateSamplerYcbcrConversionKHR vkCreateSemaphore vkCreateShaderModule vkCreateSwapchainKHR vkCreateWaylandSurfaceKHR
vkDestroyBuffer vkDestroyCommandPool vkDestroyDescriptorPool vkDestroyDescriptorSetLayout vkDestroyDevice vkDestroyFence
vkDestroyFramebuffer vkDestroyImage vkDestroyImageView vkDestroyInstance vkDestroyPipeline vkDestroyPipelineLayout
vkDestroyRenderPass vkDestroySampler vkDestroySamplerYcbcrConversionKHR vkDestroySemaphore vkDestroyShaderModule
vkDestroySurfaceKHR vkDestroySwapchainKHR vkDeviceWaitIdle vkEndCommandBuffer vkEnumerateDeviceExtensionProperties
vkEnumerateInstanceExtensionProperties vkEnumerateInstanceLayerProperties vkEnumeratePhysicalDevices vkFreeCommandBuffers
vkFreeMemory vkGetBufferMemoryRequirements vkGetDeviceProcAddr vkGetDeviceQueue vkGetFenceStatus
vkGetImageMemoryRequirements vkGetInstanceProcAddr vkGetPhysicalDeviceFeatures vkGetPhysicalDeviceFeatures2KHR
vkGetPhysicalDeviceImageFormatProperties vkGetPhysicalDeviceMemoryProperties vkGetPhysicalDeviceMemoryProperties2KHR
vkGetPhysicalDeviceProperties vkGetPhysicalDeviceProperties2KHR vkGetPhysicalDeviceQueueFamilyProperties
vkGetPhysicalDeviceSurfaceCapabilitiesKHR vkGetPhysicalDeviceSurfaceFormatsKHR vkGetPhysicalDeviceSurfacePresentModesKHR
vkGetPhysicalDeviceSurfaceSupportKHR vkGetPhysicalDeviceWaylandPresentationSupportKHR vkGetSwapchainImagesKHR vkMapMemory
vkQueuePresentKHR vkQueueSubmit vkQueueWaitIdle vkResetCommandBuffer vkResetCommandPool vkResetDescriptorPool vkResetFences
vkUnmapMemory vkUpdateDescriptorSets vkWaitForFences"
             #"\s+"))

;; 関数の引数に出ないが、pNext の鎖や構造体で SDL が使う型
(def ^:private extra-types
  ["VkAllocationCallbacks" "VkPhysicalDeviceSamplerYcbcrConversionFeatures" "VkSamplerYcbcrConversionInfoKHR"
   "VkSamplerYcbcrConversionCreateInfoKHR" "VkMemoryDedicatedAllocateInfoKHR" "VkExternalMemoryImageCreateInfoKHR"
   "VkImageViewUsageCreateInfo" "VkClearValue" "VkPhysicalDeviceFeatures2KHR" "VkPhysicalDeviceMemoryProperties2KHR"
   "VkPhysicalDeviceProperties2KHR" "VkSampleMask" "VkViewport" "VkRect2D"])

(def ^:private root-constants
  (str/split "VK_ACCESS_COLOR_ATTACHMENT_READ_BIT VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT VK_ACCESS_NONE VK_ACCESS_SHADER_READ_BIT
VK_ACCESS_TRANSFER_READ_BIT VK_ACCESS_TRANSFER_WRITE_BIT VK_API_VERSION_1_0 VK_ATTACHMENT_LOAD_OP_CLEAR
VK_ATTACHMENT_LOAD_OP_DONT_CARE VK_ATTACHMENT_LOAD_OP_LOAD VK_ATTACHMENT_STORE_OP_DONT_CARE VK_ATTACHMENT_STORE_OP_STORE
VK_BLEND_FACTOR_DST_ALPHA VK_BLEND_FACTOR_DST_COLOR VK_BLEND_FACTOR_MAX_ENUM VK_BLEND_FACTOR_ONE
VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR VK_BLEND_FACTOR_SRC_ALPHA VK_BLEND_FACTOR_SRC_COLOR VK_BLEND_FACTOR_ZERO VK_BLEND_OP_ADD
VK_BLEND_OP_MAX VK_BLEND_OP_MAX_ENUM VK_BLEND_OP_MIN VK_BLEND_OP_REVERSE_SUBTRACT VK_BLEND_OP_SUBTRACT
VK_BUFFER_USAGE_TRANSFER_DST_BIT VK_BUFFER_USAGE_TRANSFER_SRC_BIT VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT
VK_BUFFER_USAGE_VERTEX_BUFFER_BIT VK_CHROMA_LOCATION_COSITED_EVEN_KHR VK_CHROMA_LOCATION_MIDPOINT_KHR
VK_COLOR_COMPONENT_A_BIT VK_COLOR_COMPONENT_B_BIT VK_COLOR_COMPONENT_G_BIT VK_COLOR_COMPONENT_R_BIT
VK_COLOR_SPACE_EXTENDED_SRGB_LINEAR_EXT VK_COLOR_SPACE_HDR10_ST2084_EXT VK_COLOR_SPACE_SRGB_NONLINEAR_KHR
VK_COMMAND_BUFFER_LEVEL_PRIMARY VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT VK_COMPONENT_SWIZZLE_IDENTITY
VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR VK_CULL_MODE_NONE VK_DEPENDENCY_BY_REGION_BIT
VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER VK_DESCRIPTOR_TYPE_SAMPLER VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
VK_DYNAMIC_STATE_SCISSOR VK_DYNAMIC_STATE_VIEWPORT VK_ERROR_DEVICE_LOST VK_ERROR_EXTENSION_NOT_PRESENT
VK_ERROR_FEATURE_NOT_PRESENT VK_ERROR_FORMAT_NOT_SUPPORTED VK_ERROR_FRAGMENTATION VK_ERROR_FRAGMENTED_POOL
VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT VK_ERROR_INCOMPATIBLE_DISPLAY_KHR VK_ERROR_INCOMPATIBLE_DRIVER
VK_ERROR_INITIALIZATION_FAILED VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT
VK_ERROR_INVALID_EXTERNAL_HANDLE VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS VK_ERROR_INVALID_SHADER_NV VK_ERROR_LAYER_NOT_PRESENT
VK_ERROR_MEMORY_MAP_FAILED VK_ERROR_NATIVE_WINDOW_IN_USE_KHR VK_ERROR_NOT_PERMITTED_EXT VK_ERROR_OUT_OF_DATE_KHR
VK_ERROR_OUT_OF_DEVICE_MEMORY VK_ERROR_OUT_OF_HOST_MEMORY VK_ERROR_OUT_OF_POOL_MEMORY VK_ERROR_SURFACE_LOST_KHR
VK_ERROR_TOO_MANY_OBJECTS VK_ERROR_UNKNOWN VK_ERROR_VALIDATION_FAILED_EXT VK_EVENT_RESET VK_EVENT_SET
VK_EXT_QUEUE_FAMILY_FOREIGN_EXTENSION_NAME VK_EXT_SWAPCHAIN_COLOR_SPACE_EXTENSION_NAME VK_FALSE VK_FENCE_CREATE_SIGNALED_BIT
VK_FILTER_LINEAR VK_FILTER_NEAREST VK_FORMAT_A1R5G5B5_UNORM_PACK16 VK_FORMAT_A2B10G10R10_UNORM_PACK32
VK_FORMAT_A4B4G4R4_UNORM_PACK16_EXT VK_FORMAT_A4R4G4B4_UNORM_PACK16_EXT VK_FORMAT_A8B8G8R8_SRGB_PACK32
VK_FORMAT_A8B8G8R8_UNORM_PACK32 VK_FORMAT_B4G4R4A4_UNORM_PACK16 VK_FORMAT_B5G5R5A1_UNORM_PACK16
VK_FORMAT_B5G6R5_UNORM_PACK16 VK_FORMAT_B8G8R8A8_SRGB VK_FORMAT_B8G8R8A8_UNORM
VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_LINEAR_FILTER_BIT
VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_SEPARATE_RECONSTRUCTION_FILTER_BIT
VK_FORMAT_G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16 VK_FORMAT_G16_B16_R16_3PLANE_420_UNORM
VK_FORMAT_G16_B16_R16_3PLANE_444_UNORM VK_FORMAT_G8_B8R8_2PLANE_420_UNORM VK_FORMAT_G8_B8_R8_3PLANE_420_UNORM
VK_FORMAT_G8_B8_R8_3PLANE_444_UNORM VK_FORMAT_R16G16B16A16_SFLOAT VK_FORMAT_R16G16_UNORM VK_FORMAT_R16_UNORM
VK_FORMAT_R32G32B32A32_SFLOAT VK_FORMAT_R32G32_SFLOAT VK_FORMAT_R4G4B4A4_UNORM_PACK16 VK_FORMAT_R5G5B5A1_UNORM_PACK16
VK_FORMAT_R5G6B5_UNORM_PACK16 VK_FORMAT_R8G8B8A8_SRGB VK_FORMAT_R8G8B8A8_UNORM VK_FORMAT_R8G8_UNORM VK_FORMAT_R8_UNORM
VK_FORMAT_UNDEFINED VK_FRONT_FACE_COUNTER_CLOCKWISE VK_IMAGE_ASPECT_COLOR_BIT VK_IMAGE_ASPECT_PLANE_0_BIT
VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
VK_IMAGE_LAYOUT_UNDEFINED VK_IMAGE_TILING_OPTIMAL VK_IMAGE_TYPE_2D VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT
VK_IMAGE_USAGE_SAMPLED_BIT VK_IMAGE_USAGE_TRANSFER_DST_BIT VK_IMAGE_USAGE_TRANSFER_SRC_BIT VK_IMAGE_VIEW_TYPE_2D VK_INCOMPLETE
VK_KHR_BIND_MEMORY_2_EXTENSION_NAME VK_KHR_DEDICATED_ALLOCATION_EXTENSION_NAME
VK_KHR_EXTERNAL_MEMORY_CAPABILITIES_EXTENSION_NAME VK_KHR_EXTERNAL_MEMORY_EXTENSION_NAME
VK_KHR_GET_MEMORY_REQUIREMENTS_2_EXTENSION_NAME VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME
VK_KHR_MAINTENANCE1_EXTENSION_NAME VK_KHR_MAINTENANCE2_EXTENSION_NAME VK_KHR_SAMPLER_YCBCR_CONVERSION_EXTENSION_NAME
VK_KHR_SURFACE_EXTENSION_NAME VK_KHR_SWAPCHAIN_EXTENSION_NAME VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME
VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT VK_MEMORY_PROPERTY_HOST_COHERENT_BIT VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT VK_NOT_READY
VK_OPERATION_DEFERRED_KHR VK_OPERATION_NOT_DEFERRED_KHR VK_PIPELINE_BIND_POINT_GRAPHICS VK_PIPELINE_COMPILE_REQUIRED_EXT
VK_PIPELINE_STAGE_ALL_COMMANDS_BIT VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT
VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT VK_PIPELINE_STAGE_TRANSFER_BIT VK_POLYGON_MODE_FILL VK_PRESENT_MODE_FIFO_KHR
VK_PRESENT_MODE_FIFO_RELAXED_KHR VK_PRESENT_MODE_IMMEDIATE_KHR VK_PRESENT_MODE_MAILBOX_KHR VK_PRIMITIVE_TOPOLOGY_LINE_LIST
VK_PRIMITIVE_TOPOLOGY_LINE_STRIP VK_PRIMITIVE_TOPOLOGY_POINT_LIST VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
VK_QUEUE_FAMILY_FOREIGN_EXT VK_QUEUE_FAMILY_IGNORED VK_QUEUE_GRAPHICS_BIT VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
VK_SAMPLER_ADDRESS_MODE_REPEAT VK_SAMPLER_MIPMAP_MODE_NEAREST VK_SAMPLER_YCBCR_MODEL_CONVERSION_RGB_IDENTITY_KHR
VK_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_2020_KHR VK_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_601_KHR
VK_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_709_KHR VK_SAMPLER_YCBCR_RANGE_ITU_FULL_KHR VK_SAMPLER_YCBCR_RANGE_ITU_NARROW_KHR
VK_SAMPLE_COUNT_1_BIT VK_SHADER_STAGE_FRAGMENT_BIT VK_SHADER_STAGE_VERTEX_BIT VK_SHARING_MODE_EXCLUSIVE
VK_STRUCTURE_TYPE_APPLICATION_INFO VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO_KHR
VK_STRUCTURE_TYPE_FENCE_CREATE_INFO VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO
VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
VK_STRUCTURE_TYPE_IMAGE_VIEW_USAGE_CREATE_INFO VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO_KHR VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SAMPLER_YCBCR_CONVERSION_FEATURES
VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
VK_STRUCTURE_TYPE_PRESENT_INFO_KHR VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO VK_STRUCTURE_TYPE_SAMPLER_YCBCR_CONVERSION_CREATE_INFO_KHR
VK_STRUCTURE_TYPE_SAMPLER_YCBCR_CONVERSION_INFO_KHR VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO VK_STRUCTURE_TYPE_SUBMIT_INFO VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET VK_SUBOPTIMAL_KHR
VK_SUBPASS_CONTENTS_INLINE VK_SUBPASS_EXTERNAL VK_SUCCESS VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR
VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR
VK_THREAD_DONE_KHR VK_THREAD_IDLE_KHR VK_TIMEOUT VK_TRUE VK_VERTEX_INPUT_RATE_VERTEX"
             #"\s+"))

;; ---- ヘッダを読む。コメントを消し、プリプロセッサの行は #define 以外を捨てる

(defn- strip-comments [s]
  (-> s
      (str/replace #"(?s)/\*.*?\*/" " ")
      (str/replace #"//[^\n]*" "")
      (str/replace #"(?m)^[ \t]*#(?!define)[^\n]*$" "")))

(def ^:private text
  (strip-comments (str (slurp (str header-dir "/vulkan_core.h")) "\n" (slurp (str header-dir "/vulkan_wayland.h")))))

;; ---- 数値のマクロと文字列のマクロ

(defn- parse-int-literal
  "C の整数リテラル（接尾辞 U / L / ULL つき）→ [値 幅]。読めなければ nil"
  [s]
  (when-let [[_ body suf] (re-matches #"(0x[0-9A-Fa-f]+|[0-9]+)((?:[Uu]?[Ll]{0,2})?)" (str/trim s))]
    [(if (str/starts-with? body "0x") (BigInteger. (subs body 2) 16) (BigInteger. body))
     (if (re-find #"(?i)ll" suf) 64 32)]))

(def ^:private defines
  "名前 → 値の文字列（関数形のマクロは除く）"
  (into {} (for [[_ n v] (re-seq #"(?m)^#define\s+([A-Za-z_][A-Za-z0-9_]*)[ \t]+([^\n]+?)\s*$" text)]
             [n (str/trim v)])))

(def ^:private enum-values (atom {}))
(def ^:private enum-types (atom #{}))

(defn- eval-const
  "式（数値・16 進・~0U・(~0ULL)・(~0U-1)・(1 << n)・別の名前・VK_MAKE_API_VERSION）を BigInteger に。"
  [expr]
  (let [e (-> expr str/trim (str/replace #"^\((.*)\)$" "$1") str/trim)]
    (cond
      (parse-int-literal e) (first (parse-int-literal e))
      (re-matches #"~(\d+)(U|UL|ULL)?(?:\s*-\s*(\d+))?" e)
      (let [[_ n suf m] (re-matches #"~(\d+)(U|UL|ULL)?(?:\s*-\s*(\d+))?" e)
            width (if (= suf "ULL") 64 32)
            mask (.subtract (.shiftLeft BigInteger/ONE width) BigInteger/ONE)
            v (.and (.not (BigInteger. n)) mask)]
        (if m (.subtract v (BigInteger. m)) v))
      (re-matches #"\(?\s*(\d+)\s*<<\s*(\d+)\s*\)?" e)
      (let [[_ a b] (re-matches #"\(?\s*(\d+)\s*<<\s*(\d+)\s*\)?" e)]
        (.shiftLeft (BigInteger. a) (Integer/parseInt b)))
      (re-matches #"-\s*(\d+)" e) (.negate (BigInteger. (second (re-matches #"-\s*(\d+)" e))))
      (re-matches #"VK_MAKE_API_VERSION\(\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\s*\)" e)
      (let [[_ v a b c] (re-matches #"VK_MAKE_API_VERSION\(\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\s*\)" e)
            n #(BigInteger. ^String %)]
        (.or (.or (.shiftLeft (n v) 29) (.shiftLeft (n a) 22)) (.or (.shiftLeft (n b) 12) (n c))))
      (re-matches #"[A-Za-z_][A-Za-z0-9_]*" e)
      (if-let [v (or (get defines e) (get @enum-values e))]
        (if (string? v) (eval-const v) v)
        (fail "値を解けない名前: " e))
      :else (fail "値の式を解けない: " expr))))

;; ---- 列挙: typedef enum VkX { A = 1, ... } VkX;

(def ^:private enum-blocks
  (re-seq #"(?s)typedef enum (\w+)\s*\{(.*?)\}\s*(\w+)\s*;" text))

(doseq [[_ _ body ename] enum-blocks]
  (swap! enum-types conj ename)
  (let [entries (map str/trim (str/split body #","))]
    (doseq [en entries :when (not (str/blank? en))]
      (if-let [[_ n v] (re-matches #"(?s)(\w+)\s*=\s*(.+)" en)]
        (swap! enum-values assoc n (str/trim v))
        (fail "列挙の項目を読めない: " ename " / " en)))))

;; ---- スカラーの typedef、ハンドル、構造体、共用体、関数の型

(def ^:private c-scalars
  {"uint8_t" ["Byte" 1] "int8_t" ["ShortInt" 1] "uint16_t" ["Word" 2] "int16_t" ["SmallInt" 2]
   "uint32_t" ["LongWord" 4] "int32_t" ["LongInt" 4] "uint64_t" ["QWord" 8] "int64_t" ["Int64" 8]
   "float" ["Single" 4] "double" ["Double" 8] "size_t" ["SizeUInt" 8] "char" ["AnsiChar" 1]
   "int" ["LongInt" 4]})

(def ^:private scalar-typedefs
  "typedef uint32_t VkFlags; など → 名前 → C の型"
  (into {} (for [[_ ct n] (re-seq #"(?m)^typedef\s+(uint8_t|int8_t|uint16_t|int16_t|uint32_t|int32_t|uint64_t|int64_t|float|double|size_t)\s+(Vk\w+)\s*;" text)]
             [n ct])))

(def ^:private alias-typedefs
  "typedef VkX VkXKHR; → 別名 → 元の名前（VkFlags の別名も含む。構造体の別名は構造体として扱う）"
  (into {} (for [[_ target n] (re-seq #"(?m)^typedef\s+(Vk\w+)\s+(Vk\w+)\s*;" text)]
             [n target])))

(def ^:private handles
  "VK_DEFINE_HANDLE(VkX) → :dispatchable、VK_DEFINE_NON_DISPATCHABLE_HANDLE(VkX) → :non-dispatchable"
  (merge (into {} (for [[_ n] (re-seq #"(?m)^VK_DEFINE_HANDLE\((\w+)\)" text)] [n :dispatchable]))
         (into {} (for [[_ n] (re-seq #"(?m)^VK_DEFINE_NON_DISPATCHABLE_HANDLE\((\w+)\)" text)] [n :non-dispatchable]))))

(def ^:private aggregates
  "構造体と共用体 → {:kind :struct/:union :body 本文}"
  (into {} (for [[_ kind n body _] (re-seq #"(?s)typedef (struct|union) (\w+)\s*\{(.*?)\}\s*(\w+)\s*;" text)]
             [n {:kind (keyword kind) :body body}])))

(def ^:private pfns
  "typedef R (VKAPI_PTR *PFN_x)(params); → 名前 → {:ret :params}"
  (into {} (for [[_ ret n params] (re-seq #"(?s)typedef\s+([^(;]+?)\s*\(VKAPI_PTR \*(PFN_\w+)\)\s*\((.*?)\)\s*;" text)]
             [n {:ret (str/trim ret) :params (str/replace params #"\s+" " ")}])))

;; ---- C の型 → Pascal

(defn- parse-ctype
  "「const struct wl_display* const* name」のような宣言から {:base :stars} を取る（名前は呼び出し側が外す）"
  [ctype]
  (let [stars (count (re-seq #"\*" ctype))
        base (-> ctype (str/replace "*" " ") (str/replace #"\bconst\b" " ") (str/replace #"\bstruct\b" " ") str/trim
                 (str/replace #"\s+" " "))]
    {:base base :stars stars}))

(def ^:private reserved
  #{"type" "object" "string" "file" "set" "to" "in" "or" "and" "not" "array" "begin" "end" "class" "unit" "label" "packed"
    "procedure" "function" "record" "program" "repeat" "until" "while" "with" "var" "const" "case" "do" "downto" "else"
    "for" "goto" "if" "mod" "nil" "of" "shl" "shr" "then" "try" "xor" "div" "is" "as" "on" "out" "property" "raise"
    "default" "index" "name" "uses" "finally" "except" "inherited" "interface" "implementation"})

(defn- field-name [n] (if (reserved (str/lower-case n)) (str n "_") n))

(defn- pas-name
  "Vk の型名 → Pascal での型名（構造体と共用体は T 付き。別名は元の種類に従う）"
  [n]
  (cond
    (get aggregates n) (str "T" n)
    (and (get alias-typedefs n) (get aggregates (get alias-typedefs n))) (str "T" n)
    :else n))

(declare kind-of)

(defn- kind-of [n]
  (cond
    (get aggregates n) (:kind (get aggregates n))
    (get handles n) :handle
    (@enum-types n) :enum
    (get scalar-typedefs n) :scalar
    (get pfns n) :pfn
    (get alias-typedefs n) (kind-of (get alias-typedefs n))
    :else nil))

(def ^:private needed-ptrs (atom #{}))   ; [名前 深さ]（Vk の型へのポインタ）

(defn- ptr-name [n depth] (str (apply str (repeat depth "P")) n))

(defn- prim-ptr [base stars]
  (case [base stars]
    ["void" 1] "Pointer" ["void" 2] "PPointer"
    ["char" 1] "PAnsiChar" ["char" 2] "PPAnsiChar"
    ["uint32_t" 1] "PLongWord" ["int32_t" 1] "PLongInt" ["uint64_t" 1] "PQWord" ["uint8_t" 1] "PByte"
    ["float" 1] "PSingle" ["size_t" 1] "PSizeUInt"
    nil))

(defn- map-type
  "C の型（const と引数名を除いたもの）→ {:pas Pascal の型名 :deps #{Vk の型名}}。void だけは {:void true}。"
  [ctype]
  (let [{:keys [base stars]} (parse-ctype ctype)]
    (cond
      (and (= base "void") (zero? stars)) {:void true}
      (zero? stars)
      (cond
        (c-scalars base) {:pas (first (c-scalars base)) :deps #{}}
        (kind-of base) {:pas (pas-name base) :deps #{base}}
        :else (fail "型を解けない: " ctype))
      :else
      (cond
        (and (= base "wl_display") (= stars 1)) {:pas "Pointer" :deps #{}}
        (and (= base "wl_surface") (= stars 1)) {:pas "Pointer" :deps #{}}
        (prim-ptr base stars) {:pas (prim-ptr base stars) :deps #{}}
        (kind-of base) (do (swap! needed-ptrs conj [base stars])
                           {:pas (ptr-name base stars) :deps #{base}})
        :else (fail "型を解けない: " ctype)))))

(defn- split-decl
  "「型 名前」または「型 名前[N]」→ [型 名前 配列の大きさまたは nil]"
  [decl]
  (let [d (str/replace (str/trim decl) #"\s+" " ")
        [_ head arr] (or (re-matches #"(.*?)\s*(\[[^\]]+\])" d) [nil d nil])
        m (re-matches #"(.*?[\s\*])([A-Za-z_][A-Za-z0-9_]*)$" head)]
    (when-not m (fail "宣言を読めない: " decl))
    [(str/trim (nth m 1)) (nth m 2)
     (when arr
       (let [inner (subs arr 1 (dec (count arr)))]
         (when (str/includes? inner "][") (fail "多次元配列は未対応: " decl))
         (int (eval-const inner))))]))

;; ---- 構造体の本文 → フィールド

(defn- fields-of [n]
  (let [{:keys [body]} (get aggregates n)
        decls (->> (str/split body #";") (map str/trim) (remove str/blank?))]
    (vec (for [d decls]
           (do (when (re-find #":\s*\d+\s*$" d) (fail "ビットフィールドは未対応: " n " / " d))
               (let [[ct nm cnt] (split-decl d)
                     t (map-type ct)]
                 (when (:void t) (fail "void のフィールド: " n " / " d))
                 {:cname nm :pas (field-name nm) :type t :count cnt}))))))

;; ---- 関数

(defn- param-list [s]
  (let [s (str/trim s)]
    (if (or (str/blank? s) (= s "void")) [] (mapv str/trim (str/split s #",")))))

(defn- pascal-param-name [i name]
  (if (and name (> (count name) 2))
    (str "A" (str/upper-case (subs name 0 1)) (subs name 1))
    (str "A" (inc i))))

(defn- sig-of [{:keys [ret params]}]
  (let [rt (map-type ret)
        ps (map-indexed (fn [i p]
                          (let [[ct nm cnt] (split-decl (if (re-find #"[A-Za-z_][A-Za-z0-9_]*$" p) p (str p " x")))
                                t (map-type ct)]
                            (when cnt (fail "引数に配列: " p))
                            {:name (pascal-param-name i nm) :type t}))
                        (param-list params))]
    {:ret rt :params ps}))

(defn- pas-sig [pfn-name {:keys [ret params]}]
  (let [ps (str/join "; " (for [{:keys [name type]} params] (str name ": " (:pas type))))
        head (if (:void ret) "procedure" "function")]
    (str "  " pfn-name " = " head (if (empty? params) "" (str "(" ps ")"))
         (if (:void ret) "" (str ": " (:pas ret))) "; cdecl;")))

(defn- pfn-name-of [fn-name] (str "PFN_" fn-name))

(def ^:private func-sigs
  (into {} (for [f root-functions]
             (let [p (get pfns (pfn-name-of f))]
               (when-not p (fail "ヘッダに無い関数: " f))
               [f (sig-of p)]))))

(defn- level-of [fname]
  (let [s (get func-sigs fname)
        first-t (some-> s :params first :type :pas)]
    (cond
      (= fname "vkGetInstanceProcAddr") :loader
      (= fname "vkGetDeviceProcAddr") :instance
      (#{"vkCreateInstance" "vkEnumerateInstanceExtensionProperties" "vkEnumerateInstanceLayerProperties"} fname) :global
      (contains? #{"VkDevice" "VkQueue" "VkCommandBuffer"} first-t) :device
      :else :instance)))

;; ---- 型の閉包

(defn- deps-of [n]
  (let [k (if (get alias-typedefs n) :alias (kind-of n))]
    (case k
      (:struct :union) (into #{} (mapcat #(:deps (:type %)) (fields-of n)))
      :pfn (let [s (sig-of (get pfns n))]
             (into (set (:deps (:ret s))) (mapcat #(:deps (:type %)) (:params s))))
      (if-let [t (get alias-typedefs n)] #{t} #{}))))

(def ^:private func-deps
  (into #{} (mapcat (fn [[_ s]] (concat (:deps (:ret s)) (mapcat #(:deps (:type %)) (:params s)))) func-sigs)))

(def ^:private all-types
  "入口から届く Vk の型の名前の集合"
  (loop [todo (vec (concat func-deps extra-types (map pfn-name-of root-functions))) seen #{}]
    (if (empty? todo)
      seen
      (let [n (peek todo) todo (pop todo)]
        (if (seen n)
          (recur todo seen)
          (do (when-not (kind-of n) (fail "ヘッダに無い型: " n))
              (recur (into todo (deps-of n)) (conj seen n))))))))

;; 型の並び: 依存先が先（同じ型ブロックで、ポインタ型は先頭にまとめて前方参照にする）
(def ^:private ordered-types
  (let [out (atom []) seen (atom #{})]
    (letfn [(visit [n]
              (when-not (@seen n)
                (swap! seen conj n)
                (doseq [d (sort (deps-of n))] (visit d))
                (swap! out conj n)))]
      (doseq [n (sort all-types)] (visit n)))
    @out))

;; ---- 型の出力

(defn- type-decl [n]
  (let [k (if (get alias-typedefs n) :alias (kind-of n))]
    (case k
      :handle (str "  " n " = " (if (= :dispatchable (get handles n)) "Pointer" "UInt64") ";")
      :enum (str "  " n " = LongInt;")
      :scalar (str "  " n " = " (first (c-scalars (get scalar-typedefs n))) ";")
      :pfn (pas-sig n (sig-of (get pfns n)))
      (:struct :union)
      (let [fs (fields-of n)]
        (str "  " (pas-name n) " = record\n"
             (if (= k :union)
               (str "    case Integer of\n"
                    (str/join "\n" (map-indexed (fn [i {:keys [pas type count]}]
                                                  (str "      " i ": (" pas ": "
                                                       (if count (str "array[0.." (dec count) "] of " (:pas type)) (:pas type)) ");"))
                                                fs)) "\n")
               (str (str/join "\n" (for [{:keys [pas type count]} fs]
                                     (str "    " pas ": " (if count (str "array[0.." (dec count) "] of " (:pas type)) (:pas type)) ";")))
                    "\n"))
             "  end;"))
      ;; 別名
      (if-let [t (get alias-typedefs n)]
        (str "  " (pas-name n) " = " (pas-name t) ";")
        (fail "出力できない型: " n)))))

(defn- ptr-decl [[n depth]]
  (let [target (if (= depth 1) (pas-name n) (ptr-name n (dec depth)))]
    (str "  " (ptr-name n depth) " = ^" target ";")))

;; ポインタ型: 構造体・共用体・別名の P 名（PVkX = ^TVkX）を全部作る（SDL の移植で使うので）。
;; 加えて、引数と構造体のフィールドで使われた深さのもの
(def ^:private ptr-set
  (into @needed-ptrs
        (for [n all-types :when (#{:struct :union :scalar :enum :handle} (kind-of n))] [n 1])))

(def ^:private types-text
  (str "{ src/generated/vulkan_types.inc — tools/genvulkan.bb が作る。手で直さない。\n"
       "  SDL が使う Vulkan の型（" (count ordered-types) " 件。うち構造体と共用体 "
       (count (filter #(#{:struct :union} (kind-of %)) ordered-types)) " 件）と、そのポインタ型。\n"
       "  元は reference/SDL/src/video/khronos/vulkan/vulkan_core.h と vulkan_wayland.h。 }\n"
       "  // ---- ポインタ型（前方参照）\n"
       (str/join "\n" (map ptr-decl (sort-by (juxt first second) ptr-set))) "\n"
       "  // ---- 型\n"
       (str/join "\n" (map type-decl ordered-types)) "\n"))

;; ---- 定数

(def ^:private constants
  (vec (for [n root-constants]
         (let [raw (loop [r (or (get defines n) (get @enum-values n))]
                     ;; 文字列のマクロは、別のマクロの名前になっていることがある（MAINTENANCE1 → MAINTENANCE_1）
                     (if (and r (re-matches #"[A-Za-z_]\w*" r) (get defines r) (str/ends-with? r "_EXTENSION_NAME"))
                       (recur (get defines r))
                       r))]
           (when-not raw (fail "ヘッダに無い定数: " n))
           (if (re-matches #"\".*\"" raw)
             [n (str "'" (subs raw 1 (dec (count raw))) "'")]
             [n (str (eval-const raw))])))))

(def ^:private constants-text
  (str "{ src/generated/vulkan_constants.inc — tools/genvulkan.bb が作る。手で直さない。\n"
       "  SDL が使う VK_ の定数（" (count constants) " 件）。値は vulkan_core.h と vulkan_wayland.h から。 }\n"
       (apply str (for [[n v] constants] (format "  %s = %s;\n" n v)))))

;; ---- 関数の表

(def ^:private by-level
  (group-by level-of root-functions))

(defn- functions-text [level title]
  (let [fs (sort (get by-level level))]
    (str "{ src/generated/vulkan_functions_" (name level) ".inc — tools/genvulkan.bb が作る。手で直さない。\n"
         "  " title "（" (count fs) " 件）。 }\n"
         (apply str (for [f fs] (format "    %s: %s;\n" f (pfn-name-of f)))))))

(defn- bind-text [level]
  (let [fs (sort (get by-level level))]
    (str "{ src/generated/vulkan_bind_" (name level) ".inc — tools/genvulkan.bb が作る。手で直さない。 }\n"
         (apply str (for [f fs] (format "  Bind(AFuncs.%s, '%s');\n" f f))))))

;; ---- VkResult の名前（SDL_Vulkan_GetResultString。video/SDL_vulkan_utils.c の case 一覧から）

(def ^:private result-cases
  (let [src (slurp "reference/SDL/src/video/SDL_vulkan_utils.c")
        pairs (re-seq #"case (VK_\w+):\s*return \"(VK_\w+)\";" src)
        ;; #if VK_HEADER_VERSION >= 135 && VK_HEADER_VERSION < 162 の枝。同梱ヘッダの版では無効
        skipped #{"VK_ERROR_INCOMPATIBLE_VERSION_KHR"}]
    (vec (for [[_ c s] pairs :when (not (skipped c))]
           (do (when-not (= c s) (fail "case の名前と返す文字列が違う: " c " / " s))
               (when-not (some #{c} root-constants) (fail "result の case が定数の一覧に無い: " c))
               c)))))

(def ^:private result-text
  (str "{ src/generated/vulkan_result_strings.inc — tools/genvulkan.bb が作る。手で直さない。\n"
       "  SDL_Vulkan_GetResultString の case 一覧（" (count result-cases) " 件）。 }\n"
       (apply str (for [c result-cases] (format "    %s: Result := '%s';\n" c c)))))

(def ^:private files
  {"vulkan_types.inc" types-text
   "vulkan_constants.inc" constants-text
   "vulkan_functions_global.inc" (functions-text :global "インスタンス無しで引く関数")
   "vulkan_functions_instance.inc" (functions-text :instance "vkGetInstanceProcAddr で引く関数")
   "vulkan_functions_device.inc" (functions-text :device "vkGetDeviceProcAddr で引く関数")
   "vulkan_bind_global.inc" (bind-text :global)
   "vulkan_bind_instance.inc" (bind-text :instance)
   "vulkan_bind_device.inc" (bind-text :device)
   "vulkan_result_strings.inc" result-text})

;; 件数を本文から数え直して確かめる
(when-not (= (count (re-seq #"(?m)^  VK_[A-Z0-9_]+ = (?:-?[0-9]+|'[^']*');$" constants-text)) (count root-constants))
  (fail "書いた定数の件数が名前の数と違う"))
(let [n-fields (reduce + (for [l [:global :instance :device]] (count (re-seq #"(?m)^    vk\w+: PFN_" (get files (str "vulkan_functions_" (name l) ".inc"))))))
      n-binds (reduce + (for [l [:global :instance :device]] (count (re-seq #"(?m)^  Bind\(" (get files (str "vulkan_bind_" (name l) ".inc"))))))
      n-expected (dec (count root-functions))]   ; vkGetInstanceProcAddr は表に入れない
  (when-not (and (= n-fields n-expected) (= n-binds n-expected))
    (fail "関数の件数が合わない: 表 " n-fields " / Bind " n-binds " / 期待 " n-expected)))
(when-not (= (count (re-seq #"(?m)^  P+Vk\w+ = \^" types-text)) (count ptr-set))
  (fail "書いたポインタ型の件数が合わない"))

;; ---- --layout: 実物の配置を gcc から取る

(defn- layout-text []
  (let [structs (sort (filter #(get aggregates %) all-types))
        c (str "#include <stdio.h>\n#include <stddef.h>\n#define VK_NO_PROTOTYPES\n#define VK_USE_PLATFORM_WAYLAND_KHR\n"
               "struct wl_display; struct wl_surface;\n#include \"vulkan.h\"\n"
               "int main(void){\n"
               (apply str
                      (for [n structs :let [fs (fields-of n)]]
                        (str "printf(\"S " n " %zu\\n\", sizeof(" n "));\n"
                             (apply str (for [f fs]
                                          (str "printf(\"F " n " " (:cname f) " %zu\\n\", offsetof(" n ", " (:cname f) "));\n"))))))
               "return 0;}\n")
        tmp (str (fs/create-temp-dir) "/layout")]
    (spit (str tmp ".c") c)
    (let [r (proc/shell {:continue true :out :string :err :string}
                        "gcc" "-I" header-dir "-o" tmp (str tmp ".c"))]
      (when-not (zero? (:exit r)) (fail "gcc: " (:err r))))
    (let [out (:out (proc/shell {:out :string} tmp))
          lines (str/split-lines out)
          sizes (into {} (for [l lines :let [[k n v] (str/split l #" ")] :when (= k "S")] [n v]))
          offs (group-by second (for [l lines :let [[k n f v] (str/split l #" ")] :when (= k "F")] [k n f v]))]
      (str "{ test/vulkan_layout.inc — tools/genvulkan.bb --layout が作る。手で直さない。\n"
           "  Vulkan の構造体と共用体の大きさと各フィールドの位置。gcc が " header-dir " のヘッダで測った実物。\n"
           "  Pascal の record の配置との往復検査（test/test_platform_vulkan.pas）の期待値。 }\n"
           (apply str
                  (for [n structs :let [fs (fields-of n) pn (pas-name n)]]
                    (str "procedure Layout_" n ";\nvar\n  V: " pn ";\nbegin\n"
                         "  CheckSize('" pn "', SizeOf(V), " (get sizes n) ");\n"
                         (apply str (for [f fs :let [[_ _ _ v] (first (filter #(= (nth % 2) (:cname f)) (get offs n)))]]
                                      (str "  CheckOffset('" pn "." (:pas f) "', PtrUInt(@V." (:pas f) ") - PtrUInt(@V), " v ");\n")))
                         "end;\n\n")))
           "procedure AllLayouts;\nbegin\n"
           (apply str (for [n structs] (str "  Layout_" n ";\n")))
           "end;\n"
           "const\n  LayoutCount = " (count structs) ";\n"))))

(let [mode (first *command-line-args*)]
  (case mode
    "--layout"
    (let [t (layout-text)]
      (spit layout-out t)
      (println (format "genvulkan: 配置の期待値 %d 構造体を %s に書いた" (count (filter #(get aggregates %) all-types)) layout-out)))

    "--check"
    (let [stale (for [[f t] (sort files) :when (not= t (when (fs/exists? (str out-dir "/" f)) (slurp (str out-dir "/" f))))] f)]
      (if (seq stale)
        (fail "古い、または無い: " (str/join ", " stale) "（tools/genvulkan.bb を実行する）")
        (println "genvulkan: 生成物は新しい")))

    nil
    (do (doseq [[f t] files] (spit (str out-dir "/" f) t))
        (println (format "genvulkan: 型 %d 件（ポインタ型 %d 件）、定数 %d 件、関数 %d 件（global %d / instance %d / device %d。vkGetInstanceProcAddr は表に入れない）を書いた"
                         (count ordered-types) (count ptr-set) (count constants) (dec (count root-functions))
                         (count (:global by-level)) (count (:instance by-level)) (count (:device by-level)))))

    (fail "使い方: tools/genvulkan.bb [--check|--layout]")))
