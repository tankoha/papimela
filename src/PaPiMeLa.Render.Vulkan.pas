{
  PaPiMeLa.Render.Vulkan — Vulkan で描くレンダラドライバ

  Origin : ported from SDL (src/render/vulkan/SDL_render_vulkan.c, src/render/vulkan/SDL_shaders_vulkan.c)
           Scope: VULKAN_CreateDeviceResources（インスタンス・物理デバイスの選択・デバイス・シェーダ・レイアウト）、
           VULKAN_CreateSwapChain（スワップチェーンと、それに付随する画像ビュー・フレームバッファ・セマフォ）、
           VULKAN_CreateFramebuffersAndRenderPasses、VULKAN_CreatePipelineState（ブレンドモードごとのパイプライン）、
           VULKAN_AllocateBuffer / AllocateImage / AllocateImageView / FindMemoryTypeIndex、
           VULKAN_CreateTexture / UpdateTexture / UpdateTextureYUV / UpdateTextureNV / Lock / Unlock / DestroyTexture
           （INDEX8・YV12・IYUV・I444・NV12・NV21。形式の対応表）、パレット（256x1 の画像）、VULKAN_SetRenderTarget、
           VULKAN_SetupShaderConstants / SelectShader、VULKAN_SetDrawState / SetCopyState（頂点のプッシュ定数・
           ビューポート・シザー・定数バッファ・ディスクリプタセット）、VULKAN_RunCommandQueue、VULKAN_RenderReadPixels、
           VULKAN_RenderPresent、VULKAN_SetVSync、シェーダは SDL の SPIR-V（tools/genspirv.bb が写す）。
           移植しないもの: HDR / PQ と scRGB の出力、外部のハードウェアバッファ（Android）、YCbCr サンプラ、
           P010 / I0FL / I4FL、デバイスのリセットの再作成、プロパティによる外部のインスタンス・デバイス・面の持ち込み。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.3、§11 #67

  WHAT:
    TPMLRenderDriver の Vulkan 版。ウィンドウ（Vulkan の面とスワップチェーン）か、窓の無いオフスクリーン
    （画像に描いて読み戻す。検査用）に描く。

  WHY:
    SDL の render/vulkan の移植。Platform.Vulkan（型と関数表）と Video.Vulkan（ローダと面）の上に載る。

  RESOLVED:
    - 同期は SDL と同じく単純にする: コマンドバッファは 1 本、IssueBatch は提出して vkQueueWaitIdle で待つ。
      SDL は N 本を回して先行させるが、SDL 自身も IssueBatch（読み戻し・描画先の切り替え・テクスチャの破棄）では
      待っており、papimela の描画はそれで十分
    - 点と線は三角形に直す（基底の既定）。SDL は POINT_LIST / LINE_LIST を使うが、Vulkan の線の規則は
      ソフトウェアのドライバと違い、GLES2 のドライバも同じ理由で三角形にしている。パイプラインは TRIANGLE_LIST だけ
    - 描画の状態は RunCommandQueue ごとに作り直す（ビューポートは出力全体、クリップは無し）。GL のドライバと同じ
    - NV12 / NV21 は、SDL の 2 平面の 1 枚の画像（G8_B8R8_2PLANE_420 に R8 と R8G8 のビュー）の代わりに、
      R8 の画像と R8G8 の画像の 2 枚で持つ。2 平面の形式を持たない Vulkan でも動き、シェーダ（TEXTURETYPE_NV12）は
      同じ。色差は縦横とも半分（奇数は切り上げ）
    - XRGB8888 / XBGR8888 は、B8G8R8A8 / R8G8B8A8 の画像にアルファを 1 にするビューを付けて持つ。SDL の Vulkan は
      持たない（SDL_CreateTexture が断り、CreateTextureFromSurface が変換する）が、papimela の共通の検査は
      この形式の描画先を作る。画像のアルファの成分は触らない（描画先に書けば残る。読むときはビューが 1 にする）
    - 作った直後の画像は 0 で埋める。SDL は未定義のまま
    - 最近傍の標本で、画素の中心がテクセルの境目に来るときは上のテクセルを選ぶよう、頂点のテクスチャ座標に
      TIE_BIAS を足す（SDL にはこの補正が無い。GL のドライバと同じ）。SDL のシェーダは変えられないので、CPU 側で足す
    - ウィンドウの大きさが変わったら、実行の頭と GetOutputSize でスワップチェーンを作り直す（SDL は
      ウィンドウのイベントでフラグを立てる）。VK_ERROR_OUT_OF_DATE_KHR / VK_SUBOPTIMAL_KHR のときも作り直す

  NOT RESOLVED:
    - YUV の変換結果は SDL のシェーダのまま（0..1 に挟まない）。範囲の外へ出る色ではソフトウェアのドライバと違う
      （GL のドライバはシェーダを変えて挟んでいる）
    - コンテキスト喪失（VK_ERROR_DEVICE_LOST）の再作成は未実装

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Render.Vulkan;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.YUV,
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Platform.Vulkan,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Render;

type
  { バッファ（SDL の VULKAN_Buffer）。 }
  TPMLVkBuffer = record
    Memory: VkDeviceMemory;
    Buffer: VkBuffer;
    Size  : VkDeviceSize;
    Mapped: Pointer;
  end;

  { 画像（SDL の VULKAN_Image）。 }
  TPMLVkImage = record
    Image : VkImage;
    Memory: VkDeviceMemory;
    Layout: VkImageLayout;
    Format: VkFormat;
  end;

  { テクスチャ 1 枚（TPMLTexture.DriverData）。 }
  TPMLVulkanTexture = class
  public
    NumImages: Integer;
    Images   : array[0..2] of TPMLVkImage;
    Views    : array[0..2] of VkImageView;
    // 描画先のとき
    Passes     : array[0..1] of VkRenderPass;   // 0 = LOAD、1 = CLEAR
    Framebuffer: VkFramebuffer;
    PixelFormat: TPMLPixelFormat;
    // 画像の大きさ（4:2:0 の YUV は偶数に切り上げる）と、テクスチャの大きさ
    Width, Height: Integer;
    LogicalW, LogicalH: Integer;
    YCbCr: Integer;           // -1 = YUV でない。それ以外は TPMLYCbCrType の序数
    Planar, NV, Indexed: Boolean;
    // Lock の置き場
    PixelData : TBytes;
    PixelPitch: Integer;
    LockedRect: TPMLRect;
  end;

  { パレットの写し（TPMLTexturePalette.DriverData）。256x1 の RGBA32 の画像。 }
  TPMLVulkanPalette = class
  public
    Image: TPMLVkImage;
    View : VkImageView;
  end;

  TPMLVkShader = (Solid, RGB, Advanced);

  { ディスクリプタの内容と一緒に持つ、ピクセルシェーダの定数（SDL の VULKAN_PixelShaderConstants。112 バイト）。 }
  TPMLVkPixelConstants = record
    scRGB_output, texture_type, input_type, color_scale: Single;
    texel_width, texel_height, texture_width, texture_height: Single;
    tonemap_method, tonemap_factor1, tonemap_factor2, sdr_white_point: Single;
    YCbCr_matrix: array[0..15] of Single;
  end;

  TPMLVkPipeline = record
    Shader  : TPMLVkShader;
    Blend   : TPMLBlendMode;
    Format  : VkFormat;
    Topology: LongInt;
    Pipeline: VkPipeline;
  end;

  TPMLVulkanRenderDriver = class(TPMLRenderDriver)
  strict private
    FLib        : TPMLDynLib;
    FGetProc    : PFN_vkGetInstanceProcAddr;
    FGlobal     : TPMLVulkanGlobalFunctions;
    FInst       : TPMLVulkanInstanceFunctions;
    FDev        : TPMLVulkanDeviceFunctions;
    FWindow     : TPMLWindow;
    FVideo      : TPMLVideoSystem;
    FInstance   : VkInstance;
    FPhysical   : VkPhysicalDevice;
    FDevice     : VkDevice;
    FQueue      : VkQueue;
    FQueueFamily: LongWord;
    FSurface    : VkSurfaceKHR;
    FMemProps   : TVkPhysicalDeviceMemoryProperties;
    FMinUboAlign: VkDeviceSize;
    FDeviceName : String;
    FPoolCmd    : VkCommandPool;
    FCmd        : VkCommandBuffer;
    FCmdOpen    : Boolean;

    // 出力（ウィンドウのスワップチェーン、またはオフスクリーンの 1 枚）
    FOutFormat  : VkFormat;
    FOutW, FOutH: Integer;
    FOutCount   : Integer;
    FOutImages  : array of VkImage;
    FOutViews   : array of VkImageView;
    FOutFBs     : array of VkFramebuffer;
    FOutLayouts : array of VkImageLayout;
    FOutMemory  : VkDeviceMemory;            // オフスクリーンの画像の置き場
    FOutPasses  : array[0..1] of VkRenderPass;
    FOutPixel   : TPMLPixelFormat;
    FSwapchain  : VkSwapchainKHR;
    FImageIdx   : LongWord;
    FFrame      : Integer;
    FAcquireSems, FFinishSems: array of VkSemaphore;
    FWaitSem    : VkSemaphore;               // 次の提出で待つ「画像が使える」セマフォ
    FSurfaceFormat: TVkSurfaceFormatKHR;
    FPreTransform: LongWord;
    FVSync      : Integer;
    FRecreate   : Boolean;
    FMinimized  : Boolean;

    // 共通の資源
    FVertexModule, FFragModules: array[TPMLVkShader] of VkShaderModule;
    FSetLayout  : VkDescriptorSetLayout;
    FPipeLayout : VkPipelineLayout;
    FSamplers   : array[0..1] of VkSampler;  // 0 = Nearest、1 = Linear
    FPipelines  : array of TPMLVkPipeline;
    FVertexBufs : array of TPMLVkBuffer;
    FVertexIdx  : Integer;
    FCurVBuf    : VkBuffer;
    FConstBufs  : array of TPMLVkBuffer;
    FConstIdx   : Integer;
    FConstOffset: VkDeviceSize;
    FLastConsts : TPMLVkPixelConstants;
    FHaveLastConsts: Boolean;
    FLastConstBuf: VkBuffer;
    FLastConstOff: VkDeviceSize;
    FPools      : array of VkDescriptorPool;
    FPoolIdx    : Integer;
    FSetCount   : Integer;
    FPending    : array of TPMLVkBuffer;     // 提出が済むまで消せない置き場（アップロード・読み戻し）
    FSupported  : array of TPMLPixelFormat;
    FDummyImage : TPMLVkImage;               // 画像を持たない描画（単色）の束縛に使う 1x1
    FDummyView  : VkImageView;

    // 実行中の状態
    FTarget     : TPMLVulkanTexture;
    FPassOpen   : Boolean;
    FCurPass    : VkRenderPass;
    FCurPipeline: Integer;
    FViewport   : TPMLRect;
    FClip       : TPMLRect;
    FClipOn     : Boolean;
    FViewportDirty, FClipDirty: Boolean;
    FProj       : array[0..31] of Single;    // model + projectionAndView
    FPushDirty  : Boolean;
    FLastNonFatalError: String;

    procedure Fail(const AWhat: String; ARc: VkResult);
    procedure LoadCommon;
    procedure CreateInstanceAndDevice(ASurface: Boolean);
    procedure PickPhysicalDevice(AWithSurface: Boolean);
    procedure CreateDeviceObjects;
    procedure LoadModules;
    procedure CreateLayouts;
    procedure CreateSamplers;
    procedure FindSupportedFormats;
    function  FormatSupported(AFormat: VkFormat): Boolean;
    function  FindMemoryType(ATypeBits: LongWord; ARequired, ADesired: LongWord): LongWord;
    procedure AllocBuffer(ASize: VkDeviceSize; AUsage: LongWord; var ABuf: TPMLVkBuffer);
    procedure FreeBuffer(var ABuf: TPMLVkBuffer);
    procedure AllocImage(AWidth, AHeight: Integer; AFormat: VkFormat; AUsage: LongWord; var AImg: TPMLVkImage);
    procedure FreeImage(var AImg: TPMLVkImage);
    function  MakeView(AImage: VkImage; AFormat: VkFormat; AAlphaOne: Boolean): VkImageView;
    procedure CreatePasses(AFormat: VkFormat; var APasses: array of VkRenderPass);
    function  CreateFramebuffer(APass: VkRenderPass; AView: VkImageView; AWidth, AHeight: Integer): VkFramebuffer;
    procedure DestroyPasses(var APasses: array of VkRenderPass);
    procedure CreateOffscreenOutput(AWidth, AHeight: Integer);
    procedure CreateSwapchain;
    procedure DestroySwapchainObjects;
    procedure AcquireNext;
    function  WindowPixelSize(out AWidth, AHeight: Integer): Boolean;
    procedure CheckResize;
    procedure EnsureCmd;
    procedure EndPass;
    procedure BeginPass(AClear: Boolean; const AColor: TPMLFColor);
    procedure IssueBatch;
    procedure SubmitAndWait(ASignal: VkSemaphore);
    procedure AfterSubmit;
    procedure ExecClear(const ACmd: TPMLRenderCommand);
    procedure ConstantSlot(const AConsts: TPMLVkPixelConstants; out ABuffer: VkBuffer; out AOffset: VkDeviceSize);
    function  AllocDescriptorSet(ABuffer: VkBuffer; AOffset: VkDeviceSize; const AViews: array of VkImageView;
      const ASamplers: array of VkSampler): VkDescriptorSet;
    function  NewDescriptorPool: VkDescriptorPool;
    procedure Barrier(AImage: VkImage; var ALayout: VkImageLayout; ANewLayout: VkImageLayout;
      ASrcAccess, ADstAccess, ASrcStage, ADstStage: LongWord);
    procedure ToShaderRead(var AImg: TPMLVkImage);
    procedure TextureClear(var AImg: TPMLVkImage);
    procedure Upload(var AImg: TPMLVkImage; AX, AY, AW, AH: Integer; APixels: Pointer; APitch, ABytes: Integer);
    procedure PushVertices(AQueue: TPMLRenderQueue);
    function  GetPipeline(AShader: TPMLVkShader; ABlend: TPMLBlendMode; AFormat: VkFormat; ATopology: LongInt): Integer;
    procedure SetupConstants(const ACmd: TPMLRenderCommand; AData: TPMLVulkanTexture; out AConsts: TPMLVkPixelConstants);
    function  SelectShader(const AConsts: TPMLVkPixelConstants; ATextured: Boolean): TPMLVkShader;
    procedure ExecDraw(const ACmd: TPMLRenderCommand; ATopology: LongInt);
    procedure UpdateViewportAndClip;
    procedure ActivatePass;
    function  CurrentFormat: VkFormat;
    function  OutPixelOf(AFormat: VkFormat): TPMLPixelFormat;
    procedure ReleasePending;
    procedure ReleaseAll;
    function  TextureOf(ATexture: TPMLTexture): TPMLVulkanTexture; inline;
    function  VkFormatOf(AFormat: TPMLPixelFormat; out AAlphaOne: Boolean): VkFormat;
    procedure RecordUpdate(AData: TPMLVulkanTexture; const ARect: TPMLRect; APixels: Pointer; APitch: Integer);
    procedure RecordUpdateYUV(AData: TPMLVulkanTexture; const ARect: TPMLRect; AY: Pointer; AYPitch: Integer;
      AU: Pointer; AUPitch: Integer; AV: Pointer; AVPitch: Integer);
    procedure RecordUpdateNV(AData: TPMLVulkanTexture; const ARect: TPMLRect; AY: Pointer; AYPitch: Integer;
      AUV: Pointer; AUVPitch: Integer);
  public
    { ウィンドウに描く。ウィンドウは TPMLWindowOptions.Vulkan で作ってあること。 }
    constructor CreateForWindow(AWindow: TPMLWindow);
    { 面の無いオフスクリーン（AWidth x AHeight の画像）に描く。検査用。使えない環境では EPMLUnsupported。 }
    constructor CreateOffscreen(AWidth, AHeight: Integer);
    destructor Destroy; override;

    function  Name: String; override;                 // 'vulkan'
    function  GetOutputSize(out AWidth, AHeight: Integer): Boolean; override;
    function  SupportsBlendMode(AMode: TPMLBlendMode): Boolean; override;
    function  SupportsTextureFormat(AFormat: TPMLPixelFormat): Boolean; override;
    function  CreateTexture(ATexture: TPMLTexture): Boolean; override;
    function  UpdateTexture(ATexture: TPMLTexture; const ARect: TPMLRect;
      APixels: Pointer; APitch: Integer): Boolean; override;
    function  UpdateTextureYUV(ATexture: TPMLTexture; const ARect: TPMLRect;
      AY: Pointer; AYPitch: Integer; AU: Pointer; AUPitch: Integer;
      AV: Pointer; AVPitch: Integer): Boolean; override;
    function  UpdateTextureNV(ATexture: TPMLTexture; const ARect: TPMLRect;
      AY: Pointer; AYPitch: Integer; AUV: Pointer; AUVPitch: Integer): Boolean; override;
    function  LockTexture(ATexture: TPMLTexture; const ARect: TPMLRect;
      out APixels: Pointer; out APitch: Integer): Boolean; override;
    procedure UnlockTexture(ATexture: TPMLTexture); override;
    procedure DestroyTexture(ATexture: TPMLTexture); override;
    function  CreatePalette(APalette: TPMLTexturePalette): Boolean; override;
    function  UpdatePalette(APalette: TPMLTexturePalette;
      const AColors: array of TPMLColor): Boolean; override;
    procedure DestroyPalette(APalette: TPMLTexturePalette); override;
    function  SupportsRenderTargets: Boolean; override;
    function  SetRenderTarget(ATexture: TPMLTexture): Boolean; override;
    procedure QueueGeometry(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const AVertices: array of TPMLVertex); override;
    procedure QueueDrawLines(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const APoints: array of TPMLFPoint); override;
    procedure RunCommandQueue(AQueue: TPMLRenderQueue); override;
    { 描画先の画素を読む。1 行目が上（出力の向きのまま）。 }
    function  ReadPixels(const ARect: TPMLRect): TPMLSurface; override;
    procedure Present; override;
    function  SetVSync(AInterval: Integer): Boolean; override;

    // 検査用: 選んだ物理デバイスの名前
    function  DeviceName: String;
  end;

var
  { 検査用。空でなければ、物理デバイスの名前にこの文字列を含むものを選ぶ（V3DV と lavapipe の両方で検査するため）。 }
  PMLVulkanRenderDeviceFilter: String = '';
  { 検査用。True の間、ウィンドウへ描くドライバの作成が EPMLUnsupported で失敗する。 }
  PMLVulkanRenderFailCreate: Boolean = False;

implementation

uses
  Math;

const
  VERTEX_BUFFER_DEFAULT_SIZE   = 65536;
  CONSTANT_BUFFER_SIZE         = 65536;
  MAX_DESCRIPTOR_SETS          = 4096;
  NUM_TEXTURE_BINDINGS         = 3;
  MAX_VERTEX_BUFFERS           = 256;

  TEXTURETYPE_NONE             = 0;
  TEXTURETYPE_RGB              = 1;
  TEXTURETYPE_RGB_PIXELART     = 2;
  TEXTURETYPE_PALETTE_NEAREST  = 3;
  TEXTURETYPE_PALETTE_LINEAR   = 4;
  TEXTURETYPE_PALETTE_PIXELART = 5;
  TEXTURETYPE_NV12             = 6;
  TEXTURETYPE_NV21             = 7;
  TEXTURETYPE_YUV              = 8;

  INPUTTYPE_UNSPECIFIED        = 0;
  INPUTTYPE_SRGB               = 1;

  // 最近傍の標本で、画素の中心がテクセルの境目に来るとき、上のテクセルを選ぶ向きに寄せる量（テクセル）。
  TIE_BIAS = 0.0001;

  // 線分の終点を向きに沿って延ばす長さ（画素）。QueueDrawLines を参照。
  LINE_EXTEND = 0.75;

  ALL_ACCESS = VK_ACCESS_SHADER_READ_BIT or VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT or VK_ACCESS_COLOR_ATTACHMENT_READ_BIT
    or VK_ACCESS_TRANSFER_READ_BIT or VK_ACCESS_TRANSFER_WRITE_BIT;
  ALL_STAGES = VK_PIPELINE_STAGE_TRANSFER_BIT or VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
    or VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;

  // SDL の vk_format_map（リトルエンディアンの並び）。unorm と srgb の両方が使えるものだけを持つ
  FormatMapCount = 13;

type
  TFormatMapEntry = record
    Pml : TPMLPixelFormat;
    Unorm, Srgb: VkFormat;
  end;

function FormatMap(AIndex: Integer): TFormatMapEntry;
begin
  case AIndex of
    0:  begin Result.Pml := PML_PIXELFORMAT_BGRA32;       Result.Unorm := VK_FORMAT_B8G8R8A8_UNORM;            Result.Srgb := VK_FORMAT_B8G8R8A8_SRGB; end;
    1:  begin Result.Pml := PML_PIXELFORMAT_RGBA32;       Result.Unorm := VK_FORMAT_R8G8B8A8_UNORM;            Result.Srgb := VK_FORMAT_R8G8B8A8_SRGB; end;
    2:  begin Result.Pml := PML_PIXELFORMAT_ABGR2101010;  Result.Unorm := VK_FORMAT_A2B10G10R10_UNORM_PACK32;  Result.Srgb := VK_FORMAT_A2B10G10R10_UNORM_PACK32; end;
    3:  begin Result.Pml := PML_PIXELFORMAT_RGBA64_FLOAT; Result.Unorm := VK_FORMAT_R16G16B16A16_SFLOAT;       Result.Srgb := VK_FORMAT_R16G16B16A16_SFLOAT; end;
    4:  begin Result.Pml := PML_PIXELFORMAT_RGB565;       Result.Unorm := VK_FORMAT_R5G6B5_UNORM_PACK16;       Result.Srgb := VK_FORMAT_R5G6B5_UNORM_PACK16; end;
    5:  begin Result.Pml := PML_PIXELFORMAT_BGR565;       Result.Unorm := VK_FORMAT_B5G6R5_UNORM_PACK16;       Result.Srgb := VK_FORMAT_B5G6R5_UNORM_PACK16; end;
    6:  begin Result.Pml := PML_PIXELFORMAT_RGBA5551;     Result.Unorm := VK_FORMAT_R5G5B5A1_UNORM_PACK16;     Result.Srgb := VK_FORMAT_R5G5B5A1_UNORM_PACK16; end;
    7:  begin Result.Pml := PML_PIXELFORMAT_BGRA5551;     Result.Unorm := VK_FORMAT_B5G5R5A1_UNORM_PACK16;     Result.Srgb := VK_FORMAT_B5G5R5A1_UNORM_PACK16; end;
    8:  begin Result.Pml := PML_PIXELFORMAT_ARGB1555;     Result.Unorm := VK_FORMAT_A1R5G5B5_UNORM_PACK16;     Result.Srgb := VK_FORMAT_A1R5G5B5_UNORM_PACK16; end;
    9:  begin Result.Pml := PML_PIXELFORMAT_RGBA4444;     Result.Unorm := VK_FORMAT_R4G4B4A4_UNORM_PACK16;     Result.Srgb := VK_FORMAT_R4G4B4A4_UNORM_PACK16; end;
    10: begin Result.Pml := PML_PIXELFORMAT_BGRA4444;     Result.Unorm := VK_FORMAT_B4G4R4A4_UNORM_PACK16;     Result.Srgb := VK_FORMAT_B4G4R4A4_UNORM_PACK16; end;
    11: begin Result.Pml := PML_PIXELFORMAT_ARGB4444;     Result.Unorm := VK_FORMAT_A4R4G4B4_UNORM_PACK16_EXT; Result.Srgb := VK_FORMAT_A4R4G4B4_UNORM_PACK16_EXT; end;
  else
        begin Result.Pml := PML_PIXELFORMAT_ABGR4444;     Result.Unorm := VK_FORMAT_A4B4G4R4_UNORM_PACK16_EXT; Result.Srgb := VK_FORMAT_A4B4G4R4_UNORM_PACK16_EXT; end;
  end;
end;

function IsPlanarYUVFormat(AFormat: TPMLPixelFormat): Boolean; inline;
begin
  Result := (AFormat = PML_PIXELFORMAT_YV12) or (AFormat = PML_PIXELFORMAT_IYUV)
    or (AFormat = PML_PIXELFORMAT_I444);
end;

function IsNVFormat(AFormat: TPMLPixelFormat): Boolean; inline;
begin
  Result := (AFormat = PML_PIXELFORMAT_NV12) or (AFormat = PML_PIXELFORMAT_NV21);
end;

const
  {$I generated/vulkan_ycbcr.inc}

var
  // SPIR-V（tools/genspirv.bb が SDL のヘッダから写す）
  {$I generated/vulkan_shaders.inc}

type
  PPMLVertex = ^TPMLVertex;

{ カンマ区切りの名前の一覧 AMissing から、AAllowed に含まれる名前を除いたもの（欠けてよい関数を外す）。 }
function MissingExcept(const AMissing: String; const AAllowed: array of String): String;
var
  Names: TStringArray;
  I, J: Integer;
  Skip: Boolean;
begin
  Result := '';
  Names := AMissing.Split([', ']);
  for I := 0 to High(Names) do
  begin
    if Names[I] = '' then
      Continue;
    Skip := False;
    for J := 0 to High(AAllowed) do
      if Names[I] = AAllowed[J] then
        Skip := True;
    if not Skip then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + Names[I];
    end;
  end;
end;

{ ---- 構築と破棄 ---- }

procedure TPMLVulkanRenderDriver.Fail(const AWhat: String; ARc: VkResult);
begin
  raise EPMLRenderError.CreateNative(Format('%s: %s', [AWhat, PMLVulkanResultString(ARc)]), ARc, 'vulkan');
end;

constructor TPMLVulkanRenderDriver.CreateOffscreen(AWidth, AHeight: Integer);
begin
  inherited Create(nil, nil);
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EPMLArgument.CreateFmt('the offscreen size must be positive (%d x %d)', [AWidth, AHeight]);
  FCurPipeline := -1;
  LoadCommon;
  CreateInstanceAndDevice(False);
  CreateDeviceObjects;
  CreateOffscreenOutput(AWidth, AHeight);
end;

constructor TPMLVulkanRenderDriver.CreateForWindow(AWindow: TPMLWindow);
begin
  inherited Create(nil, nil);
  if PMLVulkanRenderFailCreate then
    raise EPMLUnsupported.Create('the Vulkan render driver was told to fail (test hook)');
  if AWindow = nil then
    raise EPMLArgument.Create('the Vulkan render driver needs a window');
  if not (TPMLWindowFlag.Vulkan in AWindow.Flags) then
    raise EPMLUnsupported.Create(
      'the Vulkan render driver needs a window created with TPMLWindowOptions.Vulkan');
  FWindow := AWindow;
  FVideo := AWindow.Owner as TPMLVideoSystem;
  FCurPipeline := -1;
  FVSync := 0;
  LoadCommon;
  CreateInstanceAndDevice(True);
  CreateDeviceObjects;
  CreateSwapchain;
end;

destructor TPMLVulkanRenderDriver.Destroy;
begin
  try
    ReleaseAll;
  except
    on E: EPMLError do
      FLastNonFatalError := 'Vulkan cleanup failed: ' + E.Message;
  end;
  FreeAndNil(FLib);
  inherited Destroy;
end;

{ ローダを開く。ウィンドウのときは、ビデオの部品が読んだものを借りる（TPMLWindowOptions.Vulkan が読んである）。
  オフスクリーンは自分で libvulkan.so.1 を開く（ヒントは見ない。検査用）。 }
procedure TPMLVulkanRenderDriver.LoadCommon;
var
  Missing: String;
begin
  // C のドライバは浮動小数点の例外が無効であることを前提にしている（D-40）。
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  if FVideo <> nil then
  begin
    if not (TPMLVideoCapability.Vulkan in FVideo.Capabilities) then
      raise EPMLUnsupported.Create('Vulkan is not supported by this video backend');
    FGetProc := FVideo.VulkanGetInstanceProcAddr;
  end
  else
  begin
    if not TPMLDynLib.IsAvailable(['libvulkan.so.1']) then
      raise EPMLUnsupported.Create('libvulkan.so.1 is not available');
    FLib := TPMLDynLib.Create(['libvulkan.so.1']);
    Pointer(FGetProc) := FLib.TryResolve('vkGetInstanceProcAddr');
    if not Assigned(FGetProc) then
      raise EPMLUnsupported.Create('vkGetInstanceProcAddr is not found in libvulkan.so.1');
  end;
  Missing := PMLVulkanLoadGlobalFunctions(FGetProc, FGlobal);
  if Missing <> '' then
    raise EPMLUnsupported.Create('the Vulkan loader lacks: ' + Missing);
end;

procedure TPMLVulkanRenderDriver.CreateInstanceAndDevice(ASurface: Boolean);
var
  App: TVkApplicationInfo;
  ICI: TVkInstanceCreateInfo;
  Exts: TPMLVulkanExtensionNames;
  Names: array of PAnsiChar;
  I: Integer;
  Rc: VkResult;
  Missing: String;
begin
  FillChar(App, SizeOf(App), 0);
  App.sType := VK_STRUCTURE_TYPE_APPLICATION_INFO;
  App.apiVersion := VK_API_VERSION_1_0;
  FillChar(ICI, SizeOf(ICI), 0);
  ICI.sType := VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  ICI.pApplicationInfo := @App;
  Names := nil;
  if ASurface then
  begin
    Exts := FVideo.VulkanInstanceExtensions;
    SetLength(Names, Length(Exts));
    for I := 0 to High(Exts) do
      Names[I] := PAnsiChar(Exts[I]);
    ICI.enabledExtensionCount := Length(Names);
    if Length(Names) > 0 then
      ICI.ppEnabledExtensionNames := @Names[0];
  end;
  FInstance := nil;
  Rc := FGlobal.vkCreateInstance(@ICI, nil, @FInstance);
  if Rc <> VK_SUCCESS then
    raise EPMLUnsupported.CreateNative('vkCreateInstance: ' + PMLVulkanResultString(Rc), Rc, 'vulkan');
  Missing := PMLVulkanLoadInstanceFunctions(FGetProc, FInstance, FInst);
  // *2KHR の 3 つは拡張を有効にしたときだけ。面の関数はウィンドウのときだけ。このドライバは前者を使わない
  if ASurface then
    Missing := MissingExcept(Missing, ['vkGetPhysicalDeviceFeatures2KHR', 'vkGetPhysicalDeviceMemoryProperties2KHR',
      'vkGetPhysicalDeviceProperties2KHR'])
  else
    Missing := MissingExcept(Missing, ['vkGetPhysicalDeviceFeatures2KHR', 'vkGetPhysicalDeviceMemoryProperties2KHR',
      'vkGetPhysicalDeviceProperties2KHR', 'vkCreateWaylandSurfaceKHR', 'vkDestroySurfaceKHR',
      'vkGetPhysicalDeviceSurfaceCapabilitiesKHR', 'vkGetPhysicalDeviceSurfaceFormatsKHR',
      'vkGetPhysicalDeviceSurfacePresentModesKHR', 'vkGetPhysicalDeviceSurfaceSupportKHR',
      'vkGetPhysicalDeviceWaylandPresentationSupportKHR']);
  if Missing <> '' then
    raise EPMLUnsupported.Create('the Vulkan instance lacks: ' + Missing);

  if ASurface then
    FSurface := FWindow.VulkanCreateSurface(FInstance);
  PickPhysicalDevice(ASurface);
end;

{ SDL の VULKAN_FindPhysicalDevice: グラフィックスのキュー（ウィンドウなら、面へ出せるもの）があり、
  （ウィンドウなら）VK_KHR_swapchain を持つ最初の物理デバイス。検査用のフィルタがあれば、名前も見る。 }
procedure TPMLVulkanRenderDriver.PickPhysicalDevice(AWithSurface: Boolean);
var
  Count, QCount, Q, ExtCount, E: LongWord;
  Devs: array of VkPhysicalDevice;
  QProps: array of TVkQueueFamilyProperties;
  Props: TVkPhysicalDeviceProperties;
  Exts: array of TVkExtensionProperties;
  Gfx, PresentQ: LongWord;
  Supported: VkBool32;
  HasSwap: Boolean;
  D: Integer;
  DevName: String;
begin
  Count := 0;
  FInst.vkEnumeratePhysicalDevices(FInstance, @Count, nil);
  if Count = 0 then
    raise EPMLUnsupported.Create('vkEnumeratePhysicalDevices: no physical devices');
  SetLength(Devs, Count);
  FInst.vkEnumeratePhysicalDevices(FInstance, @Count, @Devs[0]);
  FPhysical := nil;
  for D := 0 to Count - 1 do
  begin
    FInst.vkGetPhysicalDeviceProperties(Devs[D], @Props);
    DevName := String(PAnsiChar(@Props.deviceName[0]));
    if (PMLVulkanRenderDeviceFilter <> '') and (Pos(PMLVulkanRenderDeviceFilter, DevName) = 0) then
      Continue;
    if VK_API_VERSION_MAJOR(Props.apiVersion) < 1 then
      Continue;
    QCount := 0;
    FInst.vkGetPhysicalDeviceQueueFamilyProperties(Devs[D], @QCount, nil);
    if QCount = 0 then
      Continue;
    SetLength(QProps, QCount);
    FInst.vkGetPhysicalDeviceQueueFamilyProperties(Devs[D], @QCount, @QProps[0]);
    Gfx := QCount;
    PresentQ := QCount;
    for Q := 0 to QCount - 1 do
    begin
      if QProps[Q].queueCount = 0 then
        Continue;
      if (QProps[Q].queueFlags and VK_QUEUE_GRAPHICS_BIT) <> 0 then
        if (not AWithSurface) then
        begin
          Gfx := Q;
          PresentQ := Q;
          Break;
        end
        else
          Gfx := Q;
      if AWithSurface then
      begin
        Supported := 0;
        if FInst.vkGetPhysicalDeviceSurfaceSupportKHR(Devs[D], Q, FSurface, @Supported) <> VK_SUCCESS then
          Continue;
        if Supported <> 0 then
        begin
          PresentQ := Q;
          if (QProps[Q].queueFlags and VK_QUEUE_GRAPHICS_BIT) <> 0 then
          begin
            Gfx := Q;
            Break;     // グラフィックスと出力を両方できるキューを使う
          end;
        end;
      end;
    end;
    if (Gfx = QCount) or (PresentQ = QCount) then
      Continue;
    if AWithSurface then
    begin
      // グラフィックスと出力が別のキューのときは扱わない（SDL は 2 本作る。papimela は出力も同じキューで出す）
      if Gfx <> PresentQ then
        Continue;
      ExtCount := 0;
      FInst.vkEnumerateDeviceExtensionProperties(Devs[D], nil, @ExtCount, nil);
      if ExtCount = 0 then
        Continue;
      SetLength(Exts, ExtCount);
      FInst.vkEnumerateDeviceExtensionProperties(Devs[D], nil, @ExtCount, @Exts[0]);
      HasSwap := False;
      for E := 0 to ExtCount - 1 do
        if String(PAnsiChar(@Exts[E].extensionName[0])) = VK_KHR_SWAPCHAIN_EXTENSION_NAME then
        begin
          HasSwap := True;
          Break;
        end;
      if not HasSwap then
        Continue;
    end;
    FPhysical := Devs[D];
    FQueueFamily := Gfx;
    FDeviceName := DevName;
    FMinUboAlign := Props.limits.minUniformBufferOffsetAlignment;
    FInst.vkGetPhysicalDeviceMemoryProperties(FPhysical, @FMemProps);
    Break;
  end;
  if FPhysical = nil then
    raise EPMLUnsupported.Create('no viable Vulkan physical device found');
end;

procedure TPMLVulkanRenderDriver.CreateDeviceObjects;
var
  Prio: Single;
  QInfo: TVkDeviceQueueCreateInfo;
  DInfo: TVkDeviceCreateInfo;
  DevExts: array[0..0] of PAnsiChar;
  Rc: VkResult;
  Missing: String;
  PoolInfo: TVkCommandPoolCreateInfo;
  Alloc: TVkCommandBufferAllocateInfo;
begin
  Prio := 1.0;
  FillChar(QInfo, SizeOf(QInfo), 0);
  QInfo.sType := VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
  QInfo.queueFamilyIndex := FQueueFamily;
  QInfo.queueCount := 1;
  QInfo.pQueuePriorities := @Prio;
  FillChar(DInfo, SizeOf(DInfo), 0);
  DInfo.sType := VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
  DInfo.queueCreateInfoCount := 1;
  DInfo.pQueueCreateInfos := @QInfo;
  if FWindow <> nil then
  begin
    DevExts[0] := VK_KHR_SWAPCHAIN_EXTENSION_NAME;
    DInfo.enabledExtensionCount := 1;
    DInfo.ppEnabledExtensionNames := @DevExts[0];
  end;
  FDevice := nil;
  Rc := FInst.vkCreateDevice(FPhysical, @DInfo, nil, @FDevice);
  if Rc <> VK_SUCCESS then
    raise EPMLUnsupported.CreateNative('vkCreateDevice: ' + PMLVulkanResultString(Rc), Rc, 'vulkan');
  Missing := PMLVulkanLoadDeviceFunctions(PFN_vkGetDeviceProcAddr(FInst.vkGetDeviceProcAddr), FDevice, FDev);
  // YCbCr 変換の 2 つは使わない。スワップチェーンの関数はウィンドウのときだけ引ける
  Missing := MissingExcept(Missing, ['vkCreateSamplerYcbcrConversionKHR', 'vkDestroySamplerYcbcrConversionKHR']);
  if FWindow = nil then
    Missing := MissingExcept(Missing, ['vkAcquireNextImageKHR', 'vkCreateSwapchainKHR', 'vkDestroySwapchainKHR',
      'vkGetSwapchainImagesKHR', 'vkQueuePresentKHR']);
  if Missing <> '' then
    raise EPMLUnsupported.Create('the Vulkan device lacks: ' + Missing);
  FQueue := nil;
  FDev.vkGetDeviceQueue(FDevice, FQueueFamily, 0, @FQueue);

  FillChar(PoolInfo, SizeOf(PoolInfo), 0);
  PoolInfo.sType := VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
  PoolInfo.flags := VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
  PoolInfo.queueFamilyIndex := FQueueFamily;
  Rc := FDev.vkCreateCommandPool(FDevice, @PoolInfo, nil, @FPoolCmd);
  if Rc <> VK_SUCCESS then
    Fail('vkCreateCommandPool()', Rc);
  FillChar(Alloc, SizeOf(Alloc), 0);
  Alloc.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  Alloc.commandPool := FPoolCmd;
  Alloc.level := VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  Alloc.commandBufferCount := 1;
  Rc := FDev.vkAllocateCommandBuffers(FDevice, @Alloc, @FCmd);
  if Rc <> VK_SUCCESS then
    Fail('vkAllocateCommandBuffers()', Rc);

  LoadModules;
  CreateLayouts;
  CreateSamplers;
  FindSupportedFormats;
  AllocImage(1, 1, VK_FORMAT_R8G8B8A8_UNORM, VK_IMAGE_USAGE_SAMPLED_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT, FDummyImage);
  FDummyView := MakeView(FDummyImage.Image, FDummyImage.Format, False);
  TextureClear(FDummyImage);
  FConstOffset := 0;
end;

procedure TPMLVulkanRenderDriver.LoadModules;
var
  Info: TVkShaderModuleCreateInfo;
  S: TPMLVkShader;
  Rc: VkResult;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.sType := VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
  for S := Low(TPMLVkShader) to High(TPMLVkShader) do
  begin
    // 頂点シェーダは 1 本（SDL の VULKAN_VertexShader。どの断片シェーダとも組む）
    Info.codeSize := SizeOf(VulkanVertexShader);
    Info.pCode := @VulkanVertexShader[0];
    Rc := FDev.vkCreateShaderModule(FDevice, @Info, nil, @FVertexModule[S]);
    if Rc <> VK_SUCCESS then
      Fail('vkCreateShaderModule()', Rc);
    case S of
      TPMLVkShader.Solid:
        begin
          Info.codeSize := SizeOf(VulkanPixelShaderColors);
          Info.pCode := @VulkanPixelShaderColors[0];
        end;
      TPMLVkShader.RGB:
        begin
          Info.codeSize := SizeOf(VulkanPixelShaderTextures);
          Info.pCode := @VulkanPixelShaderTextures[0];
        end;
    else
      begin
        Info.codeSize := SizeOf(VulkanPixelShaderAdvanced);
        Info.pCode := @VulkanPixelShaderAdvanced[0];
      end;
    end;
    Rc := FDev.vkCreateShaderModule(FDevice, @Info, nil, @FFragModules[S]);
    if Rc <> VK_SUCCESS then
      Fail('vkCreateShaderModule()', Rc);
  end;
end;

procedure TPMLVulkanRenderDriver.CreateLayouts;
var
  Bindings: array[0..NUM_TEXTURE_BINDINGS] of TVkDescriptorSetLayoutBinding;
  SetInfo: TVkDescriptorSetLayoutCreateInfo;
  PushRange: TVkPushConstantRange;
  PipeInfo: TVkPipelineLayoutCreateInfo;
  I: Integer;
  Rc: VkResult;
begin
  FillChar(Bindings, SizeOf(Bindings), 0);
  Bindings[0].binding := 0;
  Bindings[0].descriptorCount := 1;
  Bindings[0].descriptorType := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
  Bindings[0].stageFlags := VK_SHADER_STAGE_FRAGMENT_BIT;
  for I := 1 to NUM_TEXTURE_BINDINGS do
  begin
    Bindings[I].binding := I;
    Bindings[I].descriptorCount := 1;
    Bindings[I].descriptorType := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    Bindings[I].stageFlags := VK_SHADER_STAGE_FRAGMENT_BIT;
  end;
  FillChar(SetInfo, SizeOf(SetInfo), 0);
  SetInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
  SetInfo.bindingCount := NUM_TEXTURE_BINDINGS + 1;
  SetInfo.pBindings := @Bindings[0];
  Rc := FDev.vkCreateDescriptorSetLayout(FDevice, @SetInfo, nil, @FSetLayout);
  if Rc <> VK_SUCCESS then
    Fail('vkCreateDescriptorSetLayout()', Rc);
  PushRange.size := 128;   // VULKAN_VertexShaderConstants（model と projectionAndView。4x4 の 2 つ）
  PushRange.offset := 0;
  PushRange.stageFlags := VK_SHADER_STAGE_VERTEX_BIT;
  FillChar(PipeInfo, SizeOf(PipeInfo), 0);
  PipeInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
  PipeInfo.setLayoutCount := 1;
  PipeInfo.pSetLayouts := @FSetLayout;
  PipeInfo.pushConstantRangeCount := 1;
  PipeInfo.pPushConstantRanges := @PushRange;
  Rc := FDev.vkCreatePipelineLayout(FDevice, @PipeInfo, nil, @FPipeLayout);
  if Rc <> VK_SUCCESS then
    Fail('vkCreatePipelineLayout()', Rc);
end;

procedure TPMLVulkanRenderDriver.CreateSamplers;
var
  Info: TVkSamplerCreateInfo;
  I: Integer;
  Rc: VkResult;
begin
  for I := 0 to 1 do
  begin
    FillChar(Info, SizeOf(Info), 0);
    Info.sType := VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    Info.mipmapMode := VK_SAMPLER_MIPMAP_MODE_NEAREST;
    Info.addressModeU := VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    Info.addressModeV := VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    Info.addressModeW := VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    Info.maxAnisotropy := 1.0;
    Info.maxLod := 1000.0;
    if I = 0 then
    begin
      Info.magFilter := VK_FILTER_NEAREST;
      Info.minFilter := VK_FILTER_NEAREST;
    end
    else
    begin
      Info.magFilter := VK_FILTER_LINEAR;
      Info.minFilter := VK_FILTER_LINEAR;
    end;
    Rc := FDev.vkCreateSampler(FDevice, @Info, nil, @FSamplers[I]);
    if Rc <> VK_SUCCESS then
      Fail('vkCreateSampler()', Rc);
  end;
end;

{ SDL の VULKAN_TextureFormatSupported。 }
function TPMLVulkanRenderDriver.FormatSupported(AFormat: VkFormat): Boolean;
var
  Props: TVkImageFormatProperties;
begin
  Result := FInst.vkGetPhysicalDeviceImageFormatProperties(FPhysical, AFormat, VK_IMAGE_TYPE_2D,
    VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_USAGE_SAMPLED_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT, 0, @Props) = VK_SUCCESS;
end;

procedure TPMLVulkanRenderDriver.FindSupportedFormats;
var
  I: Integer;
  M: TFormatMapEntry;
begin
  FSupported := nil;
  for I := 0 to FormatMapCount - 1 do
  begin
    M := FormatMap(I);
    if FormatSupported(M.Unorm) and FormatSupported(M.Srgb) then
    begin
      SetLength(FSupported, Length(FSupported) + 1);
      FSupported[High(FSupported)] := M.Pml;
    end;
  end;
  // XRGB8888 / XBGR8888 は B8G8R8A8 / R8G8B8A8 にアルファを 1 にするビューを付けて持つ（この unit の RESOLVED）
  if FormatSupported(VK_FORMAT_B8G8R8A8_UNORM) then
  begin
    SetLength(FSupported, Length(FSupported) + 1);
    FSupported[High(FSupported)] := PML_PIXELFORMAT_XRGB8888;
  end;
  if FormatSupported(VK_FORMAT_R8G8B8A8_UNORM) then
  begin
    SetLength(FSupported, Length(FSupported) + 1);
    FSupported[High(FSupported)] := PML_PIXELFORMAT_XBGR8888;
  end;
end;

function TPMLVulkanRenderDriver.VkFormatOf(AFormat: TPMLPixelFormat; out AAlphaOne: Boolean): VkFormat;
var
  I: Integer;
  M: TFormatMapEntry;
begin
  AAlphaOne := False;
  if AFormat = PML_PIXELFORMAT_XRGB8888 then
  begin
    AAlphaOne := True;
    Exit(VK_FORMAT_B8G8R8A8_UNORM);
  end;
  if AFormat = PML_PIXELFORMAT_XBGR8888 then
  begin
    AAlphaOne := True;
    Exit(VK_FORMAT_R8G8B8A8_UNORM);
  end;
  for I := 0 to FormatMapCount - 1 do
  begin
    M := FormatMap(I);
    if M.Pml = AFormat then
      Exit(M.Unorm);
  end;
  Result := VK_FORMAT_UNDEFINED;
end;

{ ---- メモリ・バッファ・画像 ---- }

{ SDL の VULKAN_FindMemoryTypeIndex。 }
function TPMLVulkanRenderDriver.FindMemoryType(ATypeBits: LongWord; ARequired, ADesired: LongWord): LongWord;
var
  I: LongWord;
begin
  ADesired := ADesired or ARequired;
  for I := 0 to FMemProps.memoryTypeCount - 1 do
    if ((ATypeBits and (LongWord(1) shl I)) <> 0) and (FMemProps.memoryTypes[I].propertyFlags = ADesired) then
      Exit(I);
  for I := 0 to FMemProps.memoryTypeCount - 1 do
    if ((ATypeBits and (LongWord(1) shl I)) <> 0)
      and ((FMemProps.memoryTypes[I].propertyFlags and ARequired) = ARequired) then
      Exit(I);
  raise EPMLRenderError.Create('Unable to find memory type for allocation');
end;

procedure TPMLVulkanRenderDriver.AllocBuffer(ASize: VkDeviceSize; AUsage: LongWord; var ABuf: TPMLVkBuffer);
var
  Info: TVkBufferCreateInfo;
  Req: TVkMemoryRequirements;
  Alloc: TVkMemoryAllocateInfo;
  Rc: VkResult;
begin
  FillChar(ABuf, SizeOf(ABuf), 0);
  FillChar(Info, SizeOf(Info), 0);
  Info.sType := VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
  Info.size := ASize;
  Info.usage := AUsage;
  Rc := FDev.vkCreateBuffer(FDevice, @Info, nil, @ABuf.Buffer);
  if Rc <> VK_SUCCESS then
    Fail('vkCreateBuffer()', Rc);
  try
    FDev.vkGetBufferMemoryRequirements(FDevice, ABuf.Buffer, @Req);
    FillChar(Alloc, SizeOf(Alloc), 0);
    Alloc.sType := VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    Alloc.allocationSize := Req.size;
    Alloc.memoryTypeIndex := FindMemoryType(Req.memoryTypeBits,
      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    Rc := FDev.vkAllocateMemory(FDevice, @Alloc, nil, @ABuf.Memory);
    if Rc <> VK_SUCCESS then
      Fail('vkAllocateMemory()', Rc);
    Rc := FDev.vkBindBufferMemory(FDevice, ABuf.Buffer, ABuf.Memory, 0);
    if Rc <> VK_SUCCESS then
      Fail('vkBindBufferMemory()', Rc);
    Rc := FDev.vkMapMemory(FDevice, ABuf.Memory, 0, ASize, 0, @ABuf.Mapped);
    if Rc <> VK_SUCCESS then
      Fail('vkMapMemory()', Rc);
    ABuf.Size := ASize;
  except
    FreeBuffer(ABuf);
    raise;
  end;
end;

procedure TPMLVulkanRenderDriver.FreeBuffer(var ABuf: TPMLVkBuffer);
begin
  if ABuf.Buffer <> 0 then
    FDev.vkDestroyBuffer(FDevice, ABuf.Buffer, nil);
  if ABuf.Memory <> 0 then
    FDev.vkFreeMemory(FDevice, ABuf.Memory, nil);
  FillChar(ABuf, SizeOf(ABuf), 0);
end;

procedure TPMLVulkanRenderDriver.AllocImage(AWidth, AHeight: Integer; AFormat: VkFormat; AUsage: LongWord;
  var AImg: TPMLVkImage);
var
  Info: TVkImageCreateInfo;
  Req: TVkMemoryRequirements;
  Alloc: TVkMemoryAllocateInfo;
  Rc: VkResult;
begin
  FillChar(AImg, SizeOf(AImg), 0);
  AImg.Format := AFormat;
  FillChar(Info, SizeOf(Info), 0);
  Info.sType := VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
  Info.imageType := VK_IMAGE_TYPE_2D;
  Info.format := AFormat;
  Info.extent.width := AWidth;
  Info.extent.height := AHeight;
  Info.extent.depth := 1;
  Info.mipLevels := 1;
  Info.arrayLayers := 1;
  Info.samples := VK_SAMPLE_COUNT_1_BIT;
  Info.tiling := VK_IMAGE_TILING_OPTIMAL;
  Info.usage := AUsage;
  Info.sharingMode := VK_SHARING_MODE_EXCLUSIVE;
  Info.initialLayout := VK_IMAGE_LAYOUT_UNDEFINED;
  Rc := FDev.vkCreateImage(FDevice, @Info, nil, @AImg.Image);
  if Rc <> VK_SUCCESS then
    Fail('vkCreateImage()', Rc);
  try
    FDev.vkGetImageMemoryRequirements(FDevice, AImg.Image, @Req);
    FillChar(Alloc, SizeOf(Alloc), 0);
    Alloc.sType := VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    Alloc.allocationSize := Req.size;
    Alloc.memoryTypeIndex := FindMemoryType(Req.memoryTypeBits, 0, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    Rc := FDev.vkAllocateMemory(FDevice, @Alloc, nil, @AImg.Memory);
    if Rc <> VK_SUCCESS then
      Fail('vkAllocateMemory()', Rc);
    Rc := FDev.vkBindImageMemory(FDevice, AImg.Image, AImg.Memory, 0);
    if Rc <> VK_SUCCESS then
      Fail('vkBindImageMemory()', Rc);
  except
    FreeImage(AImg);
    raise;
  end;
end;

procedure TPMLVulkanRenderDriver.FreeImage(var AImg: TPMLVkImage);
begin
  if AImg.Image <> 0 then
    FDev.vkDestroyImage(FDevice, AImg.Image, nil);
  if AImg.Memory <> 0 then
    FDev.vkFreeMemory(FDevice, AImg.Memory, nil);
  FillChar(AImg, SizeOf(AImg), 0);
end;

function TPMLVulkanRenderDriver.MakeView(AImage: VkImage; AFormat: VkFormat; AAlphaOne: Boolean): VkImageView;
var
  Info: TVkImageViewCreateInfo;
  Rc: VkResult;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.sType := VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
  Info.image := AImage;
  Info.viewType := VK_IMAGE_VIEW_TYPE_2D;
  Info.format := AFormat;
  Info.components.r := VK_COMPONENT_SWIZZLE_IDENTITY;
  Info.components.g := VK_COMPONENT_SWIZZLE_IDENTITY;
  Info.components.b := VK_COMPONENT_SWIZZLE_IDENTITY;
  if AAlphaOne then
    Info.components.a := VK_COMPONENT_SWIZZLE_ONE
  else
    Info.components.a := VK_COMPONENT_SWIZZLE_IDENTITY;
  Info.subresourceRange.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
  Info.subresourceRange.levelCount := 1;
  Info.subresourceRange.layerCount := 1;
  Result := 0;
  Rc := FDev.vkCreateImageView(FDevice, @Info, nil, @Result);
  if Rc <> VK_SUCCESS then
    Fail('vkCreateImageView()', Rc);
end;

{ SDL の VULKAN_CreateFramebuffersAndRenderPasses のレンダーパスの部分。0 = LOAD、1 = CLEAR。 }
procedure TPMLVulkanRenderDriver.CreatePasses(AFormat: VkFormat; var APasses: array of VkRenderPass);
var
  Att: TVkAttachmentDescription;
  Ref: TVkAttachmentReference;
  Sub: TVkSubpassDescription;
  Dep: TVkSubpassDependency;
  Info: TVkRenderPassCreateInfo;
  I: Integer;
  Rc: VkResult;
begin
  FillChar(Att, SizeOf(Att), 0);
  Att.format := AFormat;
  Att.loadOp := VK_ATTACHMENT_LOAD_OP_LOAD;
  Att.storeOp := VK_ATTACHMENT_STORE_OP_STORE;
  Att.stencilLoadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
  Att.stencilStoreOp := VK_ATTACHMENT_STORE_OP_DONT_CARE;
  Att.initialLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  Att.finalLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  Att.samples := VK_SAMPLE_COUNT_1_BIT;
  Ref.attachment := 0;
  Ref.layout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  FillChar(Sub, SizeOf(Sub), 0);
  Sub.pipelineBindPoint := VK_PIPELINE_BIND_POINT_GRAPHICS;
  Sub.colorAttachmentCount := 1;
  Sub.pColorAttachments := @Ref;
  FillChar(Dep, SizeOf(Dep), 0);
  Dep.srcSubpass := VK_SUBPASS_EXTERNAL;
  Dep.dstSubpass := 0;
  Dep.srcStageMask := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  Dep.dstStageMask := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  Dep.srcAccessMask := VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
  Dep.dstAccessMask := VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT or VK_ACCESS_COLOR_ATTACHMENT_READ_BIT;
  Dep.dependencyFlags := VK_DEPENDENCY_BY_REGION_BIT;
  FillChar(Info, SizeOf(Info), 0);
  Info.sType := VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
  Info.attachmentCount := 1;
  Info.pAttachments := @Att;
  Info.subpassCount := 1;
  Info.pSubpasses := @Sub;
  Info.dependencyCount := 1;
  Info.pDependencies := @Dep;
  for I := 0 to 1 do
  begin
    if I = 1 then
      Att.loadOp := VK_ATTACHMENT_LOAD_OP_CLEAR;
    Rc := FDev.vkCreateRenderPass(FDevice, @Info, nil, @APasses[I]);
    if Rc <> VK_SUCCESS then
      Fail('vkCreateRenderPass()', Rc);
  end;
end;

procedure TPMLVulkanRenderDriver.DestroyPasses(var APasses: array of VkRenderPass);
var
  I: Integer;
begin
  for I := 0 to High(APasses) do
    if APasses[I] <> 0 then
    begin
      FDev.vkDestroyRenderPass(FDevice, APasses[I], nil);
      APasses[I] := 0;
    end;
end;

function TPMLVulkanRenderDriver.CreateFramebuffer(APass: VkRenderPass; AView: VkImageView;
  AWidth, AHeight: Integer): VkFramebuffer;
var
  Info: TVkFramebufferCreateInfo;
  Rc: VkResult;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.sType := VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
  Info.renderPass := APass;
  Info.attachmentCount := 1;
  Info.pAttachments := @AView;
  Info.width := AWidth;
  Info.height := AHeight;
  Info.layers := 1;
  Result := 0;
  Rc := FDev.vkCreateFramebuffer(FDevice, @Info, nil, @Result);
  if Rc <> VK_SUCCESS then
    Fail('vkCreateFramebuffer()', Rc);
end;

{ ---- 出力 ---- }

function TPMLVulkanRenderDriver.OutPixelOf(AFormat: VkFormat): TPMLPixelFormat;
begin
  case AFormat of
    VK_FORMAT_B8G8R8A8_UNORM, VK_FORMAT_B8G8R8A8_SRGB: Result := PML_PIXELFORMAT_ARGB8888;
    VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_R8G8B8A8_SRGB: Result := PML_PIXELFORMAT_ABGR8888;
  else
    Result := PML_PIXELFORMAT_ARGB8888;
  end;
end;

procedure TPMLVulkanRenderDriver.CreateOffscreenOutput(AWidth, AHeight: Integer);
var
  Img: TPMLVkImage;
begin
  FOutW := AWidth;
  FOutH := AHeight;
  FOutFormat := VK_FORMAT_B8G8R8A8_UNORM;
  FOutPixel := PML_PIXELFORMAT_ARGB8888;
  FOutCount := 1;
  SetLength(FOutImages, 1);
  SetLength(FOutViews, 1);
  SetLength(FOutFBs, 1);
  SetLength(FOutLayouts, 1);
  AllocImage(AWidth, AHeight, FOutFormat,
    VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT or VK_IMAGE_USAGE_TRANSFER_SRC_BIT, Img);
  FOutImages[0] := Img.Image;
  FOutMemory := Img.Memory;
  FOutLayouts[0] := VK_IMAGE_LAYOUT_UNDEFINED;
  FOutViews[0] := MakeView(FOutImages[0], FOutFormat, False);
  CreatePasses(FOutFormat, FOutPasses);
  FOutFBs[0] := CreateFramebuffer(FOutPasses[0], FOutViews[0], AWidth, AHeight);
end;

function TPMLVulkanRenderDriver.WindowPixelSize(out AWidth, AHeight: Integer): Boolean;
var
  R: TPMLRect;
begin
  R := FWindow.SizeInPixels;
  AWidth := R.W;
  AHeight := R.H;
  Result := (AWidth > 0) and (AHeight > 0);
end;

procedure TPMLVulkanRenderDriver.DestroySwapchainObjects;
var
  I: Integer;
begin
  for I := 0 to High(FOutFBs) do
    if FOutFBs[I] <> 0 then
      FDev.vkDestroyFramebuffer(FDevice, FOutFBs[I], nil);
  for I := 0 to High(FOutViews) do
    if FOutViews[I] <> 0 then
      FDev.vkDestroyImageView(FDevice, FOutViews[I], nil);
  for I := 0 to High(FAcquireSems) do
    if FAcquireSems[I] <> 0 then
      FDev.vkDestroySemaphore(FDevice, FAcquireSems[I], nil);
  for I := 0 to High(FFinishSems) do
    if FFinishSems[I] <> 0 then
      FDev.vkDestroySemaphore(FDevice, FFinishSems[I], nil);
  FOutFBs := nil;
  FOutViews := nil;
  FAcquireSems := nil;
  FFinishSems := nil;
  FOutImages := nil;
  FOutLayouts := nil;
  FOutCount := 0;
  DestroyPasses(FOutPasses);
end;

{ SDL の VULKAN_CreateSwapChain。 }
procedure TPMLVulkanRenderDriver.CreateSwapchain;
var
  Caps: TVkSurfaceCapabilitiesKHR;
  FCount, MCount, ImgCount, I: LongWord;
  Formats: array of TVkSurfaceFormatKHR;
  Modes: array of VkPresentModeKHR;
  Info: TVkSwapchainCreateInfoKHR;
  Old: VkSwapchainKHR;
  Mode: VkPresentModeKHR;
  W, H: Integer;
  Rc: VkResult;
  SemInfo: TVkSemaphoreCreateInfo;
  Desired: VkFormat;
  Found: Boolean;
begin
  IssueBatch;
  FDev.vkDeviceWaitIdle(FDevice);
  if not WindowPixelSize(W, H) then
  begin
    FMinimized := True;
    Exit;       // 大きさが 0 のあいだは作らない。大きさが戻ったら CheckResize が作る
  end;
  FMinimized := False;
  Rc := FInst.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(FPhysical, FSurface, @Caps);
  if Rc <> VK_SUCCESS then
    Fail('vkGetPhysicalDeviceSurfaceCapabilitiesKHR()', Rc);

  FCount := 0;
  FInst.vkGetPhysicalDeviceSurfaceFormatsKHR(FPhysical, FSurface, @FCount, nil);
  SetLength(Formats, FCount);
  if FCount > 0 then
    FInst.vkGetPhysicalDeviceSurfaceFormatsKHR(FPhysical, FSurface, @FCount, @Formats[0]);
  Desired := VK_FORMAT_B8G8R8A8_UNORM;
  if (FCount = 1) and (Formats[0].format = VK_FORMAT_UNDEFINED) then
  begin
    FSurfaceFormat.colorSpace := VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
    FSurfaceFormat.format := Desired;
  end
  else
  begin
    FSurfaceFormat := Formats[0];
    for I := 0 to FCount - 1 do
      if (Formats[I].format = Desired) and (Formats[I].colorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) then
      begin
        FSurfaceFormat := Formats[I];
        Break;
      end;
  end;

  FillChar(Info, SizeOf(Info), 0);
  Info.imageExtent.width := Min(Max(LongWord(W), Caps.minImageExtent.width), Caps.maxImageExtent.width);
  Info.imageExtent.height := Min(Max(LongWord(H), Caps.minImageExtent.height), Caps.maxImageExtent.height);
  FPreTransform := Caps.currentTransform;

  // present モード: vsync が 1 なら FIFO。0 なら IMMEDIATE、MAILBOX、FIFO_RELAXED の順。-1 なら FIFO_RELAXED
  Mode := VK_PRESENT_MODE_FIFO_KHR;
  if FVSync <= 0 then
  begin
    MCount := 0;
    FInst.vkGetPhysicalDeviceSurfacePresentModesKHR(FPhysical, FSurface, @MCount, nil);
    SetLength(Modes, MCount);
    if MCount > 0 then
      FInst.vkGetPhysicalDeviceSurfacePresentModesKHR(FPhysical, FSurface, @MCount, @Modes[0]);
    if FVSync = 0 then
    begin
      for I := 0 to MCount - 1 do
        if Modes[I] = VK_PRESENT_MODE_IMMEDIATE_KHR then
        begin
          Mode := VK_PRESENT_MODE_IMMEDIATE_KHR;
          Break;
        end
        else if Modes[I] = VK_PRESENT_MODE_MAILBOX_KHR then
          Mode := VK_PRESENT_MODE_MAILBOX_KHR
        else if (Mode <> VK_PRESENT_MODE_MAILBOX_KHR) and (Modes[I] = VK_PRESENT_MODE_FIFO_RELAXED_KHR) then
          Mode := VK_PRESENT_MODE_FIFO_RELAXED_KHR;
    end
    else
      for I := 0 to MCount - 1 do
        if Modes[I] = VK_PRESENT_MODE_FIFO_RELAXED_KHR then
        begin
          Mode := VK_PRESENT_MODE_FIFO_RELAXED_KHR;
          Break;
        end;
  end;

  Old := FSwapchain;
  Info.sType := VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
  Info.surface := FSurface;
  Info.minImageCount := Caps.minImageCount + 2;     // SDL_VULKAN_FRAME_QUEUE_DEPTH
  if (Caps.maxImageCount > 0) and (Info.minImageCount > Caps.maxImageCount) then
    Info.minImageCount := Caps.maxImageCount;
  Info.imageFormat := FSurfaceFormat.format;
  Info.imageColorSpace := FSurfaceFormat.colorSpace;
  Info.imageArrayLayers := 1;
  Info.imageUsage := VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT;
  // 読み戻し（SDL_RenderReadPixels）はスワップチェーンの画像から写すので TRANSFER_SRC が要る
  if (Caps.supportedUsageFlags and VK_IMAGE_USAGE_TRANSFER_SRC_BIT) <> 0 then
    Info.imageUsage := Info.imageUsage or VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  Info.imageSharingMode := VK_SHARING_MODE_EXCLUSIVE;
  Info.preTransform := FPreTransform;
  Info.presentMode := Mode;
  Info.clipped := VK_TRUE;
  Info.oldSwapchain := Old;
  Found := False;
  if (Caps.supportedCompositeAlpha and VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR) <> 0 then
  begin
    Info.compositeAlpha := VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    Found := True;
  end
  else if (Caps.supportedCompositeAlpha and VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR) <> 0 then
  begin
    Info.compositeAlpha := VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;
    Found := True;
  end;
  if not Found then
    Info.compositeAlpha := VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;

  // 古い画像・ビュー・フレームバッファは、新しいスワップチェーンを作る前に捨てる（古いスワップチェーンは oldSwapchain で渡す）
  DestroySwapchainObjects;
  FSwapchain := 0;
  Rc := FDev.vkCreateSwapchainKHR(FDevice, @Info, nil, @FSwapchain);
  if Old <> 0 then
    FDev.vkDestroySwapchainKHR(FDevice, Old, nil);
  if Rc <> VK_SUCCESS then
  begin
    FSwapchain := 0;
    Fail('vkCreateSwapchainKHR()', Rc);
  end;
  FOutW := Info.imageExtent.width;
  FOutH := Info.imageExtent.height;
  FOutFormat := FSurfaceFormat.format;
  FOutPixel := OutPixelOf(FOutFormat);

  ImgCount := 0;
  FDev.vkGetSwapchainImagesKHR(FDevice, FSwapchain, @ImgCount, nil);
  SetLength(FOutImages, ImgCount);
  FDev.vkGetSwapchainImagesKHR(FDevice, FSwapchain, @ImgCount, @FOutImages[0]);
  FOutCount := ImgCount;
  SetLength(FOutViews, ImgCount);
  SetLength(FOutFBs, ImgCount);
  SetLength(FOutLayouts, ImgCount);
  SetLength(FAcquireSems, ImgCount);
  SetLength(FFinishSems, ImgCount);
  FillChar(SemInfo, SizeOf(SemInfo), 0);
  SemInfo.sType := VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
  CreatePasses(FOutFormat, FOutPasses);
  for I := 0 to ImgCount - 1 do
  begin
    FOutViews[I] := MakeView(FOutImages[I], FOutFormat, False);
    FOutFBs[I] := CreateFramebuffer(FOutPasses[0], FOutViews[I], FOutW, FOutH);
    FOutLayouts[I] := VK_IMAGE_LAYOUT_UNDEFINED;
    Rc := FDev.vkCreateSemaphore(FDevice, @SemInfo, nil, @FAcquireSems[I]);
    if Rc <> VK_SUCCESS then
      Fail('vkCreateSemaphore()', Rc);
    Rc := FDev.vkCreateSemaphore(FDevice, @SemInfo, nil, @FFinishSems[I]);
    if Rc <> VK_SUCCESS then
      Fail('vkCreateSemaphore()', Rc);
  end;
  FFrame := 0;
  FRecreate := False;
  FCurPipeline := -1;
  AcquireNext;
end;

{ SDL の VULKAN_AcquireNextSwapchainImage。期限切れなら作り直す。 }
procedure TPMLVulkanRenderDriver.AcquireNext;
var
  Rc: VkResult;
begin
  if (FSwapchain = 0) or (FOutCount = 0) then
    Exit;
  FWaitSem := 0;
  Rc := FDev.vkAcquireNextImageKHR(FDevice, FSwapchain, High(QWord), FAcquireSems[FFrame], 0, @FImageIdx);
  if (Rc = VK_ERROR_OUT_OF_DATE_KHR) or (Rc = VK_ERROR_SURFACE_LOST_KHR) then
  begin
    FRecreate := True;
    Exit;
  end
  else if (Rc <> VK_SUCCESS) and (Rc <> VK_SUBOPTIMAL_KHR) then
    Fail('vkAcquireNextImageKHR()', Rc);
  FWaitSem := FAcquireSems[FFrame];
end;

{ ウィンドウの大きさが変わっていたら、スワップチェーンを作り直す。 }
procedure TPMLVulkanRenderDriver.CheckResize;
var
  W, H: Integer;
begin
  if FWindow = nil then
    Exit;
  if WindowPixelSize(W, H) then
  begin
    if FMinimized or FRecreate or (FSwapchain = 0) or (W <> FOutW) or (H <> FOutH) then
      CreateSwapchain;
  end
  else
    FMinimized := True;
end;

{ ---- コマンドバッファ ---- }

procedure TPMLVulkanRenderDriver.EnsureCmd;
var
  Info: TVkCommandBufferBeginInfo;
  Idx: Integer;
begin
  if FCmdOpen then
    Exit;
  FDev.vkResetCommandBuffer(FCmd, 0);
  FillChar(Info, SizeOf(Info), 0);
  Info.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  FDev.vkBeginCommandBuffer(FCmd, @Info);
  FCmdOpen := True;
  FCurPipeline := -1;
  FConstIdx := 0;
  FConstOffset := 0;
  FHaveLastConsts := False;
  FPoolIdx := 0;
  FSetCount := 0;
  FViewportDirty := True;
  FClipDirty := True;
  FPushDirty := True;
  if FOutCount > 0 then
  begin
    // 出力の画像を描画先の並びにする（SDL の VULKAN_EnsureCommandBuffer）
    Idx := FImageIdx;
    if FOutLayouts[Idx] = VK_IMAGE_LAYOUT_UNDEFINED then
      Barrier(FOutImages[Idx], FOutLayouts[Idx], VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, 0,
        VK_ACCESS_COLOR_ATTACHMENT_READ_BIT or VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT)
    else if FOutLayouts[Idx] <> VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL then
      Barrier(FOutImages[Idx], FOutLayouts[Idx], VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        VK_ACCESS_COLOR_ATTACHMENT_READ_BIT,
        VK_ACCESS_COLOR_ATTACHMENT_READ_BIT or VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);
  end;
end;

procedure TPMLVulkanRenderDriver.EndPass;
begin
  if FPassOpen then
  begin
    FDev.vkCmdEndRenderPass(FCmd);
    FPassOpen := False;
  end;
end;

procedure TPMLVulkanRenderDriver.BeginPass(AClear: Boolean; const AColor: TPMLFColor);
var
  Info: TVkRenderPassBeginInfo;
  CV: TVkClearValue;
  W, H, Slot: Integer;
  FB: VkFramebuffer;
begin
  if AClear then
    Slot := 1
  else
    Slot := 0;
  if FTarget <> nil then
  begin
    W := FTarget.LogicalW;
    H := FTarget.LogicalH;
    FCurPass := FTarget.Passes[Slot];
    FB := FTarget.Framebuffer;
  end
  else
  begin
    W := FOutW;
    H := FOutH;
    FCurPass := FOutPasses[Slot];
    FB := FOutFBs[FImageIdx];
  end;
  FillChar(Info, SizeOf(Info), 0);
  Info.sType := VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
  Info.renderPass := FCurPass;
  Info.framebuffer := FB;
  Info.renderArea.extent.width := W;
  Info.renderArea.extent.height := H;
  if AClear then
  begin
    FillChar(CV, SizeOf(CV), 0);
    CV.color.float32[0] := AColor.R;
    CV.color.float32[1] := AColor.G;
    CV.color.float32[2] := AColor.B;
    CV.color.float32[3] := AColor.A;
    Info.clearValueCount := 1;
    Info.pClearValues := @CV;
  end;
  FDev.vkCmdBeginRenderPass(FCmd, @Info, VK_SUBPASS_CONTENTS_INLINE);
  FPassOpen := True;
  FCurPipeline := -1;
  FViewportDirty := True;
  FClipDirty := True;
  FPushDirty := True;
end;

{ SDL の VULKAN_IssueBatch: 提出して待つ。待ったあとで、提出済みの置き場を捨てる。 }
procedure TPMLVulkanRenderDriver.IssueBatch;
begin
  if not FCmdOpen then
    Exit;
  SubmitAndWait(0);
end;

{ コマンドバッファを閉じて提出し、終わるまで待つ。ASignal が 0 でなければ、終わったときに知らせる（Present 用）。 }
procedure TPMLVulkanRenderDriver.SubmitAndWait(ASignal: VkSemaphore);
var
  Submit: TVkSubmitInfo;
  Stage: VkPipelineStageFlags;
  Rc: VkResult;
begin
  EndPass;
  FCurPipeline := -1;
  FViewportDirty := True;
  FDev.vkEndCommandBuffer(FCmd);
  FCmdOpen := False;
  FillChar(Submit, SizeOf(Submit), 0);
  Submit.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
  Stage := VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
  if FWaitSem <> 0 then
  begin
    Submit.waitSemaphoreCount := 1;
    Submit.pWaitSemaphores := @FWaitSem;
    Submit.pWaitDstStageMask := @Stage;
  end;
  Submit.commandBufferCount := 1;
  Submit.pCommandBuffers := @FCmd;
  if ASignal <> 0 then
  begin
    Submit.signalSemaphoreCount := 1;
    Submit.pSignalSemaphores := @ASignal;
  end;
  Rc := FDev.vkQueueSubmit(FQueue, 1, @Submit, 0);
  FWaitSem := 0;
  if Rc <> VK_SUCCESS then
    Fail('vkQueueSubmit()', Rc);
  FDev.vkQueueWaitIdle(FQueue);
  AfterSubmit;
end;

{ 提出が済んで GPU が止まったあと: ディスクリプタの置き場・定数・頂点を最初から使い直し、提出済みの置き場を捨てる。 }
procedure TPMLVulkanRenderDriver.AfterSubmit;
var
  I: Integer;
begin
  for I := 0 to High(FPools) do
    FDev.vkResetDescriptorPool(FDevice, FPools[I], 0);
  FPoolIdx := 0;
  FSetCount := 0;
  FConstIdx := 0;
  FConstOffset := 0;
  FHaveLastConsts := False;
  FVertexIdx := 0;
  ReleasePending;
end;

procedure TPMLVulkanRenderDriver.ReleasePending;
var
  I: Integer;
begin
  for I := 0 to High(FPending) do
    FreeBuffer(FPending[I]);
  FPending := nil;
end;

{ SDL の VULKAN_RecordPipelineImageBarrier。進行中のレンダーパスは先に閉じる。 }
procedure TPMLVulkanRenderDriver.Barrier(AImage: VkImage; var ALayout: VkImageLayout; ANewLayout: VkImageLayout;
  ASrcAccess, ADstAccess, ASrcStage, ADstStage: LongWord);
var
  B: TVkImageMemoryBarrier;
begin
  EndPass;
  FillChar(B, SizeOf(B), 0);
  B.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  B.srcAccessMask := ASrcAccess;
  B.dstAccessMask := ADstAccess;
  B.oldLayout := ALayout;
  B.newLayout := ANewLayout;
  B.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  B.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  B.image := AImage;
  B.subresourceRange.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
  B.subresourceRange.levelCount := 1;
  B.subresourceRange.layerCount := 1;
  FDev.vkCmdPipelineBarrier(FCmd, ASrcStage, ADstStage, 0, 0, nil, 0, nil, 1, @B);
  ALayout := ANewLayout;
end;

procedure TPMLVulkanRenderDriver.ToShaderRead(var AImg: TPMLVkImage);
begin
  if AImg.Layout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL then
    Exit;
  Barrier(AImg.Image, AImg.Layout, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, ALL_ACCESS and not VK_ACCESS_SHADER_READ_BIT
    or VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_SHADER_READ_BIT, ALL_STAGES, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
end;

{ 作ったばかりの画像を 0 で埋め、シェーダから読める並びにする。 }
procedure TPMLVulkanRenderDriver.TextureClear(var AImg: TPMLVkImage);
var
  CV: TVkClearColorValue;
  Range: TVkImageSubresourceRange;
begin
  EnsureCmd;
  Barrier(AImg.Image, AImg.Layout, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 0, VK_ACCESS_TRANSFER_WRITE_BIT,
    VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);
  FillChar(CV, SizeOf(CV), 0);
  FillChar(Range, SizeOf(Range), 0);
  Range.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
  Range.levelCount := 1;
  Range.layerCount := 1;
  FDev.vkCmdClearColorImage(FCmd, AImg.Image, AImg.Layout, @CV, 1, @Range);
  Barrier(AImg.Image, AImg.Layout, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_ACCESS_TRANSFER_WRITE_BIT,
    VK_ACCESS_SHADER_READ_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
end;

{ SDL の VULKAN_UpdateTextureInternal: 詰めた置き場に写して、画像の AX, AY, AW x AH へ転送する。 }
procedure TPMLVulkanRenderDriver.Upload(var AImg: TPMLVkImage; AX, AY, AW, AH: Integer; APixels: Pointer;
  APitch, ABytes: Integer);
var
  Buf: TPMLVkBuffer;
  Region: TVkBufferImageCopy;
  Row, Len: Integer;
  Src, Dst: PByte;
begin
  if (AW <= 0) or (AH <= 0) then
    Exit;
  EnsureCmd;
  Len := AW * ABytes;
  AllocBuffer(PtrUInt(Len) * PtrUInt(AH), VK_BUFFER_USAGE_TRANSFER_SRC_BIT, Buf);
  Src := PByte(APixels);
  Dst := PByte(Buf.Mapped);
  if Len > APitch then
    Len := APitch;
  for Row := 0 to AH - 1 do
  begin
    Move(Src^, Dst^, Len);
    Inc(Src, APitch);
    Inc(Dst, AW * ABytes);
  end;
  Barrier(AImg.Image, AImg.Layout, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, ALL_ACCESS, VK_ACCESS_TRANSFER_WRITE_BIT,
    ALL_STAGES, VK_PIPELINE_STAGE_TRANSFER_BIT);
  FillChar(Region, SizeOf(Region), 0);
  Region.imageSubresource.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
  Region.imageSubresource.layerCount := 1;
  Region.imageOffset.x := AX;
  Region.imageOffset.y := AY;
  Region.imageExtent.width := AW;
  Region.imageExtent.height := AH;
  Region.imageExtent.depth := 1;
  FDev.vkCmdCopyBufferToImage(FCmd, Buf.Buffer, AImg.Image, AImg.Layout, 1, @Region);
  Barrier(AImg.Image, AImg.Layout, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_ACCESS_TRANSFER_WRITE_BIT,
    VK_ACCESS_SHADER_READ_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
  SetLength(FPending, Length(FPending) + 1);
  FPending[High(FPending)] := Buf;
  // アップロードの置き場が溜まったら提出する（SDL の SDL_VULKAN_NUM_UPLOAD_BUFFERS）
  if Length(FPending) >= 32 then
    IssueBatch;
end;

{ ---- ドライバの問い合わせ ---- }

function TPMLVulkanRenderDriver.Name: String;
begin
  Result := 'vulkan';
end;

function TPMLVulkanRenderDriver.DeviceName: String;
begin
  Result := FDeviceName;
end;

function TPMLVulkanRenderDriver.GetOutputSize(out AWidth, AHeight: Integer): Boolean;
begin
  if FWindow <> nil then
    CheckResize;
  AWidth := FOutW;
  AHeight := FOutH;
  Result := (AWidth > 0) and (AHeight > 0);
end;

function TPMLVulkanRenderDriver.SupportsBlendMode(AMode: TPMLBlendMode): Boolean;
begin
  Result := True;
end;

function TPMLVulkanRenderDriver.SupportsTextureFormat(AFormat: TPMLPixelFormat): Boolean;
var
  I: Integer;
begin
  if (AFormat = PML_PIXELFORMAT_INDEX8) or IsPlanarYUVFormat(AFormat) or IsNVFormat(AFormat) then
    Exit(True);
  for I := 0 to High(FSupported) do
    if FSupported[I] = AFormat then
      Exit(True);
  Result := False;
end;

function TPMLVulkanRenderDriver.SupportsRenderTargets: Boolean;
begin
  Result := True;
end;

function TPMLVulkanRenderDriver.TextureOf(ATexture: TPMLTexture): TPMLVulkanTexture;
begin
  if (ATexture = nil) or not (ATexture.DriverData is TPMLVulkanTexture) then
    Result := nil
  else
    Result := TPMLVulkanTexture(ATexture.DriverData);
end;

{ ---- テクスチャ ---- }

function TPMLVulkanRenderDriver.CreateTexture(ATexture: TPMLTexture): Boolean;
var
  Data: TPMLVulkanTexture;
  Fmt: VkFormat;
  AlphaOne: Boolean;
  Usage: LongWord;
  CW, CH, I: Integer;
  YCbCr: TPMLYCbCrType;
  Size: PtrUInt;
  Done: Boolean;
begin
  Result := False;
  Data := TPMLVulkanTexture.Create;
  Data.PixelFormat := ATexture.Format;
  Data.LogicalW := ATexture.Width;
  Data.LogicalH := ATexture.Height;
  Data.Width := ATexture.Width;
  Data.Height := ATexture.Height;
  Data.YCbCr := -1;
  Data.Indexed := ATexture.Format = PML_PIXELFORMAT_INDEX8;
  Data.Planar := IsPlanarYUVFormat(ATexture.Format);
  Data.NV := IsNVFormat(ATexture.Format);
  Done := False;
  try
    if Data.Planar or Data.NV then
    begin
      if ATexture.Access = TPMLTextureAccess.Target then
        Exit;
      if not PMLYCbCrTypeOf(ATexture.Colorspace, YCbCr) then
        Exit;
      Data.YCbCr := Ord(YCbCr);
      // 4:2:0 は偶数に切り上げる（SDL）。I444 は切り上げない
      if ATexture.Format <> PML_PIXELFORMAT_I444 then
      begin
        Data.Width := (Data.Width + 1) and not 1;
        Data.Height := (Data.Height + 1) and not 1;
      end;
    end;
    Usage := VK_IMAGE_USAGE_SAMPLED_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    if ATexture.Access = TPMLTextureAccess.Target then
      Usage := Usage or VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    AlphaOne := False;
    if Data.Indexed or Data.Planar then
      Fmt := VK_FORMAT_R8_UNORM
    else if Data.NV then
      Fmt := VK_FORMAT_R8_UNORM
    else
    begin
      Fmt := VkFormatOf(ATexture.Format, AlphaOne);
      if Fmt = VK_FORMAT_UNDEFINED then
        Exit;
    end;

    if Data.Planar then
    begin
      if ATexture.Format = PML_PIXELFORMAT_I444 then
      begin
        CW := Data.Width;
        CH := Data.Height;
      end
      else
      begin
        CW := Data.Width div 2;
        CH := Data.Height div 2;
      end;
      Data.NumImages := 3;
    end
    else if Data.NV then
    begin
      CW := Data.Width div 2;
      CH := Data.Height div 2;
      Data.NumImages := 2;
    end
    else
    begin
      CW := Data.Width;
      CH := Data.Height;
      Data.NumImages := 1;
    end;
    for I := 0 to Data.NumImages - 1 do
    begin
      if I = 0 then
        AllocImage(Data.Width, Data.Height, Fmt, Usage, Data.Images[I])
      else if Data.NV then
        AllocImage(CW, CH, VK_FORMAT_R8G8_UNORM, Usage, Data.Images[I])
      else
        AllocImage(CW, CH, Fmt, Usage, Data.Images[I]);
      Data.Views[I] := MakeView(Data.Images[I].Image, Data.Images[I].Format, AlphaOne);
      TextureClear(Data.Images[I]);
    end;
    if ATexture.Access = TPMLTextureAccess.Target then
    begin
      CreatePasses(Fmt, Data.Passes);
      Data.Framebuffer := CreateFramebuffer(Data.Passes[0], Data.Views[0], ATexture.Width, ATexture.Height);
    end;
    if ATexture.Access = TPMLTextureAccess.Streaming then
    begin
      // Lock の置き場。SDL と同じ大きさ（YUV は色差の平面の分も）で、0 で埋める
      Data.PixelPitch := ATexture.Width * PMLBytesPerPixel(ATexture.Format);
      Size := PtrUInt(ATexture.Height) * PtrUInt(Data.PixelPitch);
      if Data.Planar or Data.NV then
        PMLCalculateYUVSize(ATexture.Format, ATexture.Width, ATexture.Height, Size, Data.PixelPitch);
      SetLength(Data.PixelData, Size);
      if Size > 0 then
        FillChar(Data.PixelData[0], Size, 0);
    end;
    ATexture.DriverData := Data;
    Done := True;
    Result := True;
  finally
    if not Done then
    begin
      // 作れなかった（途中の失敗も含む）ので、作った分を畳む
      if Data.Framebuffer <> 0 then
        FDev.vkDestroyFramebuffer(FDevice, Data.Framebuffer, nil);
      DestroyPasses(Data.Passes);
      for I := 0 to 2 do
      begin
        if Data.Views[I] <> 0 then
          FDev.vkDestroyImageView(FDevice, Data.Views[I], nil);
        FreeImage(Data.Images[I]);
      end;
      Data.Free;
    end;
  end;
end;

procedure TPMLVulkanRenderDriver.DestroyTexture(ATexture: TPMLTexture);
var
  Data: TPMLVulkanTexture;
  I: Integer;
begin
  Data := TextureOf(ATexture);
  if Data = nil then
    Exit;
  // 破棄は提出済みの描画の途中かもしれないので、先に提出して待つ（SDL と同じ）
  IssueBatch;
  if FTarget = Data then
    FTarget := nil;
  for I := 0 to 2 do
  begin
    if Data.Views[I] <> 0 then
      FDev.vkDestroyImageView(FDevice, Data.Views[I], nil);
    FreeImage(Data.Images[I]);
  end;
  if Data.Framebuffer <> 0 then
    FDev.vkDestroyFramebuffer(FDevice, Data.Framebuffer, nil);
  DestroyPasses(Data.Passes);
  Data.Free;
  ATexture.DriverData := nil;
end;

{ ---- テクスチャの更新 ---- }

procedure TPMLVulkanRenderDriver.RecordUpdate(AData: TPMLVulkanTexture; const ARect: TPMLRect;
  APixels: Pointer; APitch: Integer);
begin
  Upload(AData.Images[0], ARect.X, ARect.Y, ARect.W, ARect.H, APixels, APitch,
    PMLBytesPerPixel(AData.PixelFormat));
end;

procedure TPMLVulkanRenderDriver.RecordUpdateYUV(AData: TPMLVulkanTexture; const ARect: TPMLRect; AY: Pointer;
  AYPitch: Integer; AU: Pointer; AUPitch: Integer; AV: Pointer; AVPitch: Integer);
begin
  Upload(AData.Images[0], ARect.X, ARect.Y, ARect.W, ARect.H, AY, AYPitch, 1);
  if AData.PixelFormat = PML_PIXELFORMAT_I444 then
  begin
    Upload(AData.Images[1], ARect.X, ARect.Y, ARect.W, ARect.H, AU, AUPitch, 1);
    Upload(AData.Images[2], ARect.X, ARect.Y, ARect.W, ARect.H, AV, AVPitch, 1);
  end
  else
  begin
    Upload(AData.Images[1], ARect.X div 2, ARect.Y div 2, (ARect.W + 1) div 2, (ARect.H + 1) div 2, AU, AUPitch, 1);
    Upload(AData.Images[2], ARect.X div 2, ARect.Y div 2, (ARect.W + 1) div 2, (ARect.H + 1) div 2, AV, AVPitch, 1);
  end;
end;

procedure TPMLVulkanRenderDriver.RecordUpdateNV(AData: TPMLVulkanTexture; const ARect: TPMLRect; AY: Pointer;
  AYPitch: Integer; AUV: Pointer; AUVPitch: Integer);
begin
  Upload(AData.Images[0], ARect.X, ARect.Y, ARect.W, ARect.H, AY, AYPitch, 1);
  Upload(AData.Images[1], ARect.X div 2, ARect.Y div 2, (ARect.W + 1) div 2, (ARect.H + 1) div 2, AUV, AUVPitch, 2);
end;

function TPMLVulkanRenderDriver.UpdateTexture(ATexture: TPMLTexture; const ARect: TPMLRect;
  APixels: Pointer; APitch: Integer): Boolean;
var
  Data: TPMLVulkanTexture;
  YPitch, UVPitch: Integer;
  P0, P1, P2: PByte;
begin
  Data := TextureOf(ATexture);
  if Data = nil then
    Exit(False);
  P0 := PByte(APixels);
  if Data.NV then
  begin
    // SDL: UV の行の幅は、Y の行の幅を 2 の倍数へ切り上げたもの
    YPitch := APitch;
    UVPitch := (APitch + 1) and not 1;
    P1 := P0 + PtrUInt(ARect.H) * PtrUInt(APitch);
    RecordUpdateNV(Data, ARect, P0, YPitch, P1, UVPitch);
  end
  else if Data.Planar then
  begin
    if ATexture.Format = PML_PIXELFORMAT_I444 then
    begin
      P1 := P0 + PtrUInt(ARect.H) * PtrUInt(APitch);
      P2 := P1 + PtrUInt(ARect.H) * PtrUInt(APitch);
      RecordUpdateYUV(Data, ARect, P0, APitch, P1, APitch, P2, APitch);
    end
    else
    begin
      YPitch := APitch;
      UVPitch := (YPitch + 1) div 2;
      P1 := P0 + PtrUInt(ARect.H) * PtrUInt(YPitch);
      P2 := P1 + PtrUInt((ARect.H + 1) div 2) * PtrUInt(UVPitch);
      if ATexture.Format = PML_PIXELFORMAT_YV12 then
        RecordUpdateYUV(Data, ARect, P0, YPitch, P2, UVPitch, P1, UVPitch)
      else
        RecordUpdateYUV(Data, ARect, P0, YPitch, P1, UVPitch, P2, UVPitch);
    end;
  end
  else
    RecordUpdate(Data, ARect, APixels, APitch);
  Result := True;
end;

function TPMLVulkanRenderDriver.UpdateTextureYUV(ATexture: TPMLTexture; const ARect: TPMLRect;
  AY: Pointer; AYPitch: Integer; AU: Pointer; AUPitch: Integer; AV: Pointer; AVPitch: Integer): Boolean;
var
  Data: TPMLVulkanTexture;
begin
  Data := TextureOf(ATexture);
  Result := (Data <> nil) and Data.Planar;
  if Result then
    RecordUpdateYUV(Data, ARect, AY, AYPitch, AU, AUPitch, AV, AVPitch);
end;

function TPMLVulkanRenderDriver.UpdateTextureNV(ATexture: TPMLTexture; const ARect: TPMLRect;
  AY: Pointer; AYPitch: Integer; AUV: Pointer; AUVPitch: Integer): Boolean;
var
  Data: TPMLVulkanTexture;
begin
  Data := TextureOf(ATexture);
  Result := (Data <> nil) and Data.NV;
  if Result then
    RecordUpdateNV(Data, ARect, AY, AYPitch, AUV, AUVPitch);
end;

function TPMLVulkanRenderDriver.LockTexture(ATexture: TPMLTexture; const ARect: TPMLRect;
  out APixels: Pointer; out APitch: Integer): Boolean;
var
  Data: TPMLVulkanTexture;
begin
  APixels := nil;
  APitch := 0;
  Data := TextureOf(ATexture);
  if (Data = nil) or (Length(Data.PixelData) = 0) then
    Exit(False);
  Data.LockedRect := ARect;
  APixels := @Data.PixelData[0] + PtrUInt(ARect.Y) * PtrUInt(Data.PixelPitch)
    + PtrUInt(ARect.X) * PtrUInt(PMLBytesPerPixel(ATexture.Format));
  APitch := Data.PixelPitch;
  Result := True;
end;

procedure TPMLVulkanRenderDriver.UnlockTexture(ATexture: TPMLTexture);
var
  Data: TPMLVulkanTexture;
  P: Pointer;
begin
  Data := TextureOf(ATexture);
  if (Data = nil) or (Length(Data.PixelData) = 0) then
    Exit;
  // SDL の VULKAN_UnlockTexture（複数の画像を持つ形式）: 置き場の矩形の左上から、UpdateTexture と同じに送る
  P := @Data.PixelData[0] + PtrUInt(Data.LockedRect.Y) * PtrUInt(Data.PixelPitch)
    + PtrUInt(Data.LockedRect.X) * PtrUInt(PMLBytesPerPixel(ATexture.Format));
  UpdateTexture(ATexture, Data.LockedRect, P, Data.PixelPitch);
end;

{ ---- パレット ---- }

function TPMLVulkanRenderDriver.CreatePalette(APalette: TPMLTexturePalette): Boolean;
var
  Pal: TPMLVulkanPalette;
  White: array[0..255] of TPMLColor;
  I: Integer;
begin
  Pal := TPMLVulkanPalette.Create;
  try
    AllocImage(256, 1, VK_FORMAT_R8G8B8A8_UNORM, VK_IMAGE_USAGE_SAMPLED_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT, Pal.Image);
    Pal.View := MakeView(Pal.Image.Image, Pal.Image.Format, False);
    // 写しは白の不透明で始める（アプリのパレットの外の添字は白で描かれる。ソフトウェアのドライバと同じ）
    for I := 0 to 255 do
      White[I] := TPMLColor.Make(255, 255, 255, 255);
    Upload(Pal.Image, 0, 0, 256, 1, @White[0], 256 * 4, 4);
  except
    if Pal.View <> 0 then
      FDev.vkDestroyImageView(FDevice, Pal.View, nil);
    FreeImage(Pal.Image);
    Pal.Free;
    raise;
  end;
  APalette.DriverData := Pal;
  Result := True;
end;

function TPMLVulkanRenderDriver.UpdatePalette(APalette: TPMLTexturePalette;
  const AColors: array of TPMLColor): Boolean;
var
  Pal: TPMLVulkanPalette;
  N: Integer;
begin
  Pal := TPMLVulkanPalette(APalette.DriverData);
  N := Length(AColors);
  if (Pal = nil) or (N = 0) then
    Exit(Pal <> nil);
  if N > 256 then
    N := 256;
  Upload(Pal.Image, 0, 0, N, 1, @AColors[0], N * 4, 4);
  Result := True;
end;

procedure TPMLVulkanRenderDriver.DestroyPalette(APalette: TPMLTexturePalette);
var
  Pal: TPMLVulkanPalette;
begin
  Pal := TPMLVulkanPalette(APalette.DriverData);
  if Pal = nil then
    Exit;
  // 描画の途中かもしれないので、先に提出して待つ（SDL と同じ）
  IssueBatch;
  if Pal.View <> 0 then
    FDev.vkDestroyImageView(FDevice, Pal.View, nil);
  FreeImage(Pal.Image);
  Pal.Free;
  APalette.DriverData := nil;
end;

{ ---- 描画先 ---- }

function TPMLVulkanRenderDriver.SetRenderTarget(ATexture: TPMLTexture): Boolean;
var
  Data: TPMLVulkanTexture;
begin
  EnsureCmd;
  if ATexture <> nil then
  begin
    Data := TextureOf(ATexture);
    if (Data = nil) or (Data.Framebuffer = 0) then
      Exit(False);
    FTarget := Data;
    Barrier(Data.Images[0].Image, Data.Images[0].Layout, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
      ALL_ACCESS and not VK_ACCESS_TRANSFER_READ_BIT, ALL_ACCESS and not VK_ACCESS_TRANSFER_READ_BIT,
      ALL_STAGES, ALL_STAGES);
  end
  else
  begin
    if FTarget <> nil then
      Barrier(FTarget.Images[0].Image, FTarget.Images[0].Layout, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        ALL_ACCESS, VK_ACCESS_SHADER_READ_BIT, ALL_STAGES, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
    FTarget := nil;
  end;
  IssueBatch;
  Result := True;
end;

function TPMLVulkanRenderDriver.CurrentFormat: VkFormat;
begin
  if FTarget <> nil then
    Result := FTarget.Images[0].Format
  else
    Result := FOutFormat;
end;

{ ---- 積む ---- }

{ SDL の VULKAN_QueueGeometry: テクスチャ座標に、画像の大きさとテクスチャの大きさの比（YUV の切り上げ）を掛ける。
  PORT-NOTE: 最近傍の境目の補正（TIE_BIAS）を足す。SDL にはこの補正が無い。 }
procedure TPMLVulkanRenderDriver.QueueGeometry(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
  const AVertices: array of TPMLVertex);
var
  Data: TPMLVulkanTexture;
  V: TPMLVertices;
  I: Integer;
  US, VS: Single;
begin
  Data := nil;
  if ACmd.Texture <> nil then
    Data := TextureOf(ACmd.Texture);
  if Data <> nil then
  begin
    US := Data.LogicalW / Data.Width;
    VS := Data.LogicalH / Data.Height;
    SetLength(V, Length(AVertices));
    for I := 0 to High(AVertices) do
    begin
      V[I] := AVertices[I];
      V[I].TexCoord.X := V[I].TexCoord.X * US + TIE_BIAS * US / Data.LogicalW;
      V[I].TexCoord.Y := V[I].TexCoord.Y * VS + TIE_BIAS * VS / Data.LogicalH;
    end;
    ACmd.First := AQueue.AddVertices(V);
  end
  else
    ACmd.First := AQueue.AddVertices(AVertices);
  ACmd.Count := Length(AVertices);
end;

{ 折れ線を、線分ごとに 2 頂点（LINE_LIST）にする。始点は画素の中心（+0.5）。終点は中心から線の向きへ LINE_EXTEND
  画素延ばして、線の規則で最後の画素が落ちないようにする。

  PORT-NOTE: SDL は LINE_STRIP と、最後の点の POINT_LIST を使い、座標は小数のまま。ここはソフトウェアのドライバ
  （両端を含むブレゼンハム）と同じ画素になるよう、座標を切り捨ててから +0.5 し、線分ごとに独立の 2 頂点にする
  （キューが同じ状態の DrawLines を結合するので、折れ線の境目が分からなくなるため）。延ばす量は GL / GLES2 の
  ドライバと同じ 0.75（V3D と llvmpipe で、0.25〜0.75 は軸に平行な線が全部合い、1.0 は終点が 1 画素はみ出す）。 }
procedure TPMLVulkanRenderDriver.QueueDrawLines(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
  const APoints: array of TPMLFPoint);
var
  V: TPMLVertices;
  I: Integer;
  X0, Y0, X1, Y1, Angle: Single;

  function Make(AX, AY: Single): TPMLVertex;
  begin
    Result.Position := TPMLFPoint.Make(AX, AY);
    Result.Color := ACmd.Color;
    Result.TexCoord := TPMLFPoint.Make(0, 0);
  end;

begin
  if Length(APoints) < 2 then
    Exit;
  SetLength(V, (Length(APoints) - 1) * 2);
  for I := 0 to High(APoints) - 1 do
  begin
    X0 := Int(APoints[I].X) + 0.5;
    Y0 := Int(APoints[I].Y) + 0.5;
    X1 := Int(APoints[I + 1].X) + 0.5;
    Y1 := Int(APoints[I + 1].Y) + 0.5;
    Angle := ArcTan2(Y1 - Y0, X1 - X0);
    V[I * 2] := Make(X0, Y0);
    V[I * 2 + 1] := Make(X1 + Cos(Angle) * LINE_EXTEND, Y1 + Sin(Angle) * LINE_EXTEND);
  end;
  ACmd.First := AQueue.AddVertices(V);
  ACmd.Count := Length(V);
end;

{ ---- 実行 ---- }

procedure TPMLVulkanRenderDriver.PushVertices(AQueue: TPMLRenderQueue);
var
  I: Integer;
  Need: VkDeviceSize;
  P: PByte;
begin
  FCurVBuf := 0;
  if AQueue.VertexCount = 0 then
    Exit;
  Need := PtrUInt(AQueue.VertexCount) * SizeOf(TPMLVertex);
  if FVertexIdx >= Length(FVertexBufs) then
    SetLength(FVertexBufs, FVertexIdx + 1);
  // まだ使っていない（前の提出で済んだ）バッファなので、足りなければその場で作り直してよい
  if FVertexBufs[FVertexIdx].Size < Need then
  begin
    FreeBuffer(FVertexBufs[FVertexIdx]);
    AllocBuffer(Max(Need, VkDeviceSize(VERTEX_BUFFER_DEFAULT_SIZE)), VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, FVertexBufs[FVertexIdx]);
  end;
  P := PByte(FVertexBufs[FVertexIdx].Mapped);
  for I := 0 to AQueue.VertexCount - 1 do
    PPMLVertex(P + PtrUInt(I) * SizeOf(TPMLVertex))^ := AQueue.Vertex(I);
  FCurVBuf := FVertexBufs[FVertexIdx].Buffer;
  Inc(FVertexIdx);
end;

function TPMLVulkanRenderDriver.GetPipeline(AShader: TPMLVkShader; ABlend: TPMLBlendMode;
  AFormat: VkFormat; ATopology: LongInt): Integer;
var
  I: Integer;
  Stages: array[0..1] of TVkPipelineShaderStageCreateInfo;
  Attrs: array[0..2] of TVkVertexInputAttributeDescription;
  Bind: TVkVertexInputBindingDescription;
  VI: TVkPipelineVertexInputStateCreateInfo;
  IA: TVkPipelineInputAssemblyStateCreateInfo;
  VP: TVkPipelineViewportStateCreateInfo;
  Dyn: array[0..1] of VkDynamicState;
  DS: TVkPipelineDynamicStateCreateInfo;
  RS: TVkPipelineRasterizationStateCreateInfo;
  MS: TVkPipelineMultisampleStateCreateInfo;
  Mask: LongWord;
  DSt: TVkPipelineDepthStencilStateCreateInfo;
  CBA: TVkPipelineColorBlendAttachmentState;
  CB: TVkPipelineColorBlendStateCreateInfo;
  PI: TVkGraphicsPipelineCreateInfo;
  Pipe: VkPipeline;
  Rc: VkResult;
begin
  for I := 0 to High(FPipelines) do
    if (FPipelines[I].Shader = AShader) and (FPipelines[I].Blend = ABlend) and (FPipelines[I].Format = AFormat)
      and (FPipelines[I].Topology = ATopology) then
      Exit(I);
  FillChar(Stages, SizeOf(Stages), 0);
  Stages[0].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
  Stages[0].stage := VK_SHADER_STAGE_VERTEX_BIT;
  Stages[0].module := FVertexModule[AShader];
  Stages[0].pName := 'main';
  Stages[1].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
  Stages[1].stage := VK_SHADER_STAGE_FRAGMENT_BIT;
  Stages[1].module := FFragModules[AShader];
  Stages[1].pName := 'main';
  // 頂点の並びは TPMLVertex（位置 0、色 8、テクスチャ座標 24。32 バイト）。SDL のシェーダの入力は
  // 位置・テクスチャ座標・色の順（location 0 / 1 / 2）
  FillChar(Attrs, SizeOf(Attrs), 0);
  Attrs[0].location := 0;
  Attrs[0].format := VK_FORMAT_R32G32_SFLOAT;
  Attrs[0].offset := 0;
  Attrs[1].location := 1;
  Attrs[1].format := VK_FORMAT_R32G32_SFLOAT;
  Attrs[1].offset := 24;
  Attrs[2].location := 2;
  Attrs[2].format := VK_FORMAT_R32G32B32A32_SFLOAT;
  Attrs[2].offset := 8;
  FillChar(Bind, SizeOf(Bind), 0);
  Bind.binding := 0;
  Bind.stride := SizeOf(TPMLVertex);
  Bind.inputRate := VK_VERTEX_INPUT_RATE_VERTEX;
  FillChar(VI, SizeOf(VI), 0);
  VI.sType := VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
  VI.vertexBindingDescriptionCount := 1;
  VI.pVertexBindingDescriptions := @Bind;
  VI.vertexAttributeDescriptionCount := 3;
  VI.pVertexAttributeDescriptions := @Attrs[0];
  FillChar(IA, SizeOf(IA), 0);
  IA.sType := VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
  IA.topology := ATopology;
  FillChar(VP, SizeOf(VP), 0);
  VP.sType := VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
  VP.viewportCount := 1;
  VP.scissorCount := 1;
  Dyn[0] := VK_DYNAMIC_STATE_VIEWPORT;
  Dyn[1] := VK_DYNAMIC_STATE_SCISSOR;
  FillChar(DS, SizeOf(DS), 0);
  DS.sType := VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
  DS.dynamicStateCount := 2;
  DS.pDynamicStates := @Dyn[0];
  FillChar(RS, SizeOf(RS), 0);
  RS.sType := VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
  RS.cullMode := VK_CULL_MODE_NONE;
  RS.polygonMode := VK_POLYGON_MODE_FILL;
  RS.frontFace := VK_FRONT_FACE_COUNTER_CLOCKWISE;
  RS.lineWidth := 1.0;
  Mask := $FFFFFFFF;
  FillChar(MS, SizeOf(MS), 0);
  MS.sType := VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
  MS.pSampleMask := @Mask;
  MS.rasterizationSamples := VK_SAMPLE_COUNT_1_BIT;
  FillChar(DSt, SizeOf(DSt), 0);
  DSt.sType := VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
  // ブレンドモードの係数（GL のドライバの表と同じ。SDL の SDL_BLENDMODE_*）。None も、1 と 0 の係数で有効にする（SDL と同じ）
  FillChar(CBA, SizeOf(CBA), 0);
  CBA.blendEnable := VK_TRUE;
  CBA.colorBlendOp := VK_BLEND_OP_ADD;
  CBA.alphaBlendOp := VK_BLEND_OP_ADD;
  case ABlend of
    TPMLBlendMode.None:
      begin
        CBA.srcColorBlendFactor := VK_BLEND_FACTOR_ONE;
        CBA.dstColorBlendFactor := VK_BLEND_FACTOR_ZERO;
        CBA.srcAlphaBlendFactor := VK_BLEND_FACTOR_ONE;
        CBA.dstAlphaBlendFactor := VK_BLEND_FACTOR_ZERO;
      end;
    TPMLBlendMode.Blend:
      begin
        CBA.srcColorBlendFactor := VK_BLEND_FACTOR_SRC_ALPHA;
        CBA.dstColorBlendFactor := VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        CBA.srcAlphaBlendFactor := VK_BLEND_FACTOR_ONE;
        CBA.dstAlphaBlendFactor := VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
      end;
    TPMLBlendMode.Add:
      begin
        CBA.srcColorBlendFactor := VK_BLEND_FACTOR_SRC_ALPHA;
        CBA.dstColorBlendFactor := VK_BLEND_FACTOR_ONE;
        CBA.srcAlphaBlendFactor := VK_BLEND_FACTOR_ZERO;
        CBA.dstAlphaBlendFactor := VK_BLEND_FACTOR_ONE;
      end;
    TPMLBlendMode.Modulate:
      begin
        CBA.srcColorBlendFactor := VK_BLEND_FACTOR_DST_COLOR;
        CBA.dstColorBlendFactor := VK_BLEND_FACTOR_ZERO;
        CBA.srcAlphaBlendFactor := VK_BLEND_FACTOR_ZERO;
        CBA.dstAlphaBlendFactor := VK_BLEND_FACTOR_ONE;
      end;
    TPMLBlendMode.Multiply:
      begin
        CBA.srcColorBlendFactor := VK_BLEND_FACTOR_DST_COLOR;
        CBA.dstColorBlendFactor := VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        CBA.srcAlphaBlendFactor := VK_BLEND_FACTOR_ZERO;
        CBA.dstAlphaBlendFactor := VK_BLEND_FACTOR_ONE;
      end;
  end;
  CBA.colorWriteMask := VK_COLOR_COMPONENT_R_BIT or VK_COLOR_COMPONENT_G_BIT or VK_COLOR_COMPONENT_B_BIT
    or VK_COLOR_COMPONENT_A_BIT;
  FillChar(CB, SizeOf(CB), 0);
  CB.sType := VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
  CB.attachmentCount := 1;
  CB.pAttachments := @CBA;
  FillChar(PI, SizeOf(PI), 0);
  PI.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  PI.stageCount := 2;
  PI.pStages := @Stages[0];
  PI.pVertexInputState := @VI;
  PI.pInputAssemblyState := @IA;
  PI.pViewportState := @VP;
  PI.pRasterizationState := @RS;
  PI.pMultisampleState := @MS;
  PI.pDepthStencilState := @DSt;
  PI.pColorBlendState := @CB;
  PI.pDynamicState := @DS;
  PI.layout := FPipeLayout;
  PI.renderPass := FCurPass;
  Pipe := 0;
  Rc := FDev.vkCreateGraphicsPipelines(FDevice, 0, 1, @PI, nil, @Pipe);
  if Rc <> VK_SUCCESS then
    Fail('vkCreateGraphicsPipelines()', Rc);
  SetLength(FPipelines, Length(FPipelines) + 1);
  FPipelines[High(FPipelines)].Shader := AShader;
  FPipelines[High(FPipelines)].Blend := ABlend;
  FPipelines[High(FPipelines)].Format := AFormat;
  FPipelines[High(FPipelines)].Topology := ATopology;
  FPipelines[High(FPipelines)].Pipeline := Pipe;
  Result := High(FPipelines);
end;

{ SDL の VULKAN_SetupShaderConstants（sRGB の出力だけ）。 }
procedure TPMLVulkanRenderDriver.SetupConstants(const ACmd: TPMLRenderCommand; AData: TPMLVulkanTexture;
  out AConsts: TPMLVkPixelConstants);
var
  I: Integer;
begin
  FillChar(AConsts, SizeOf(AConsts), 0);
  AConsts.color_scale := 1.0;
  if AData = nil then
    Exit;
  if AData.Indexed then
    case ACmd.ScaleMode of
      TPMLScaleMode.Nearest: AConsts.texture_type := TEXTURETYPE_PALETTE_NEAREST;
      TPMLScaleMode.Linear: AConsts.texture_type := TEXTURETYPE_PALETTE_LINEAR;
    else
      AConsts.texture_type := TEXTURETYPE_PALETTE_PIXELART;
    end
  else if AData.Planar then
  begin
    AConsts.texture_type := TEXTURETYPE_YUV;
    AConsts.input_type := INPUTTYPE_SRGB;
  end
  else if AData.PixelFormat = PML_PIXELFORMAT_NV12 then
  begin
    AConsts.texture_type := TEXTURETYPE_NV12;
    AConsts.input_type := INPUTTYPE_SRGB;
  end
  else if AData.PixelFormat = PML_PIXELFORMAT_NV21 then
  begin
    AConsts.texture_type := TEXTURETYPE_NV21;
    AConsts.input_type := INPUTTYPE_SRGB;
  end
  else
  begin
    if ACmd.ScaleMode = TPMLScaleMode.PixelArt then
      AConsts.texture_type := TEXTURETYPE_RGB_PIXELART
    else
      AConsts.texture_type := TEXTURETYPE_RGB;
    AConsts.input_type := INPUTTYPE_UNSPECIFIED;
  end;
  if (AConsts.texture_type = TEXTURETYPE_PALETTE_LINEAR) or (AConsts.texture_type = TEXTURETYPE_PALETTE_PIXELART)
    or (AConsts.texture_type = TEXTURETYPE_RGB_PIXELART) then
  begin
    AConsts.texture_width := AData.LogicalW;
    AConsts.texture_height := AData.LogicalH;
    AConsts.texel_width := 1.0 / AConsts.texture_width;
    AConsts.texel_height := 1.0 / AConsts.texture_height;
  end;
  AConsts.sdr_white_point := 1.0;
  if AData.YCbCr >= 0 then
    for I := 0 to 15 do
      AConsts.YCbCr_matrix[I] := VulkanYCbCrMatrix[AData.YCbCr][I];
end;

{ SDL の SelectShader（sRGB の出力）。 }
function TPMLVulkanRenderDriver.SelectShader(const AConsts: TPMLVkPixelConstants; ATextured: Boolean): TPMLVkShader;
begin
  if not ATextured then
    Exit(TPMLVkShader.Solid);
  if (AConsts.texture_type = TEXTURETYPE_RGB) and (AConsts.input_type = INPUTTYPE_UNSPECIFIED)
    and (AConsts.tonemap_method = 0) then
    Result := TPMLVkShader.RGB
  else
    Result := TPMLVkShader.Advanced;
end;

function TPMLVulkanRenderDriver.NewDescriptorPool: VkDescriptorPool;
var
  Sizes: array[0..2] of TVkDescriptorPoolSize;
  Info: TVkDescriptorPoolCreateInfo;
  Rc: VkResult;
begin
  Sizes[0].type_ := VK_DESCRIPTOR_TYPE_SAMPLER;
  Sizes[0].descriptorCount := MAX_DESCRIPTOR_SETS;
  Sizes[1].type_ := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
  Sizes[1].descriptorCount := NUM_TEXTURE_BINDINGS * MAX_DESCRIPTOR_SETS;
  Sizes[2].type_ := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
  Sizes[2].descriptorCount := MAX_DESCRIPTOR_SETS;
  FillChar(Info, SizeOf(Info), 0);
  Info.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
  Info.poolSizeCount := 3;
  Info.pPoolSizes := @Sizes[0];
  Info.maxSets := MAX_DESCRIPTOR_SETS;
  Result := 0;
  Rc := FDev.vkCreateDescriptorPool(FDevice, @Info, nil, @Result);
  if Rc <> VK_SUCCESS then
    Fail('vkCreateDescriptorPool()', Rc);
end;

function TPMLVulkanRenderDriver.AllocDescriptorSet(ABuffer: VkBuffer; AOffset: VkDeviceSize;
  const AViews: array of VkImageView; const ASamplers: array of VkSampler): VkDescriptorSet;
var
  Alloc: TVkDescriptorSetAllocateInfo;
  BufInfo: TVkDescriptorBufferInfo;
  ImgInfo: array[0..NUM_TEXTURE_BINDINGS - 1] of TVkDescriptorImageInfo;
  Writes: array[0..NUM_TEXTURE_BINDINGS] of TVkWriteDescriptorSet;
  I: Integer;
  Rc: VkResult;
begin
  if FSetCount >= MAX_DESCRIPTOR_SETS then
  begin
    Inc(FPoolIdx);
    FSetCount := 0;
  end;
  if FPoolIdx >= Length(FPools) then
  begin
    SetLength(FPools, FPoolIdx + 1);
    FPools[FPoolIdx] := NewDescriptorPool;
  end;
  FillChar(Alloc, SizeOf(Alloc), 0);
  Alloc.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
  Alloc.descriptorPool := FPools[FPoolIdx];
  Alloc.descriptorSetCount := 1;
  Alloc.pSetLayouts := @FSetLayout;
  Result := 0;
  Rc := FDev.vkAllocateDescriptorSets(FDevice, @Alloc, @Result);
  if Rc <> VK_SUCCESS then
    Fail('vkAllocateDescriptorSets()', Rc);
  Inc(FSetCount);
  FillChar(BufInfo, SizeOf(BufInfo), 0);
  BufInfo.buffer := ABuffer;
  BufInfo.offset := AOffset;
  BufInfo.range := SizeOf(TPMLVkPixelConstants);
  FillChar(Writes, SizeOf(Writes), 0);
  Writes[0].sType := VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
  Writes[0].dstSet := Result;
  Writes[0].dstBinding := 0;
  Writes[0].descriptorCount := 1;
  Writes[0].descriptorType := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
  Writes[0].pBufferInfo := @BufInfo;
  for I := 0 to NUM_TEXTURE_BINDINGS - 1 do
  begin
    FillChar(ImgInfo[I], SizeOf(ImgInfo[I]), 0);
    ImgInfo[I].sampler := ASamplers[I];
    ImgInfo[I].imageView := AViews[I];
    ImgInfo[I].imageLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    Writes[1 + I].sType := VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    Writes[1 + I].dstSet := Result;
    Writes[1 + I].dstBinding := 1 + I;
    Writes[1 + I].descriptorCount := 1;
    Writes[1 + I].descriptorType := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    Writes[1 + I].pImageInfo := @ImgInfo[I];
  end;
  FDev.vkUpdateDescriptorSets(FDevice, NUM_TEXTURE_BINDINGS + 1, @Writes[0], 0, nil);
end;

{ 定数を、前回と同じなら前回の置き場のまま、違えば定数バッファの次の場所へ写す。 }
procedure TPMLVulkanRenderDriver.ConstantSlot(const AConsts: TPMLVkPixelConstants; out ABuffer: VkBuffer;
  out AOffset: VkDeviceSize);
var
  Step: VkDeviceSize;
  Dst: PByte;
begin
  if FHaveLastConsts and CompareMem(@AConsts, @FLastConsts, SizeOf(AConsts)) then
  begin
    ABuffer := FLastConstBuf;
    AOffset := FLastConstOff;
    Exit;
  end;
  Step := (SizeOf(TPMLVkPixelConstants) + FMinUboAlign - 1) and not (FMinUboAlign - 1);
  if FConstIdx >= Length(FConstBufs) then
  begin
    SetLength(FConstBufs, FConstIdx + 1);
    AllocBuffer(CONSTANT_BUFFER_SIZE, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, FConstBufs[FConstIdx]);
  end;
  if FConstOffset + Step > CONSTANT_BUFFER_SIZE then
  begin
    Inc(FConstIdx);
    FConstOffset := 0;
    if FConstIdx >= Length(FConstBufs) then
    begin
      SetLength(FConstBufs, FConstIdx + 1);
      AllocBuffer(CONSTANT_BUFFER_SIZE, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, FConstBufs[FConstIdx]);
    end;
  end;
  Dst := PByte(FConstBufs[FConstIdx].Mapped) + FConstOffset;
  Move(AConsts, Dst^, SizeOf(AConsts));
  ABuffer := FConstBufs[FConstIdx].Buffer;
  AOffset := FConstOffset;
  FConstOffset := FConstOffset + Step;
  FLastConsts := AConsts;
  FHaveLastConsts := True;
  FLastConstBuf := ABuffer;
  FLastConstOff := AOffset;
end;

procedure TPMLVulkanRenderDriver.UpdateViewportAndClip;
var
  VW, VH, TW, TH, X1, Y1, X2, Y2: Integer;
  Vp: TVkViewport;
  Sc: TVkRect2D;
  I: Integer;
begin
  if FTarget <> nil then
  begin
    TW := FTarget.LogicalW;
    TH := FTarget.LogicalH;
  end
  else
  begin
    TW := FOutW;
    TH := FOutH;
  end;
  if FViewportDirty then
  begin
    VW := FViewport.W;
    VH := FViewport.H;
    if (VW <= 0) or (VH <= 0) then
    begin
      VW := Max(TW, 1);
      VH := Max(TH, 1);
    end;
    // model は単位行列、projectionAndView は SDL の view の行列（行優先）
    FillChar(FProj, SizeOf(FProj), 0);
    for I := 0 to 3 do
      FProj[I * 5] := 1.0;
    FProj[16] := 2.0 / VW;
    FProj[21] := -2.0 / VH;
    FProj[26] := 1.0;
    FProj[28] := -1.0;
    FProj[29] := 1.0;
    FProj[31] := 1.0;
    Vp.x := FViewport.X;
    Vp.y := FViewport.Y;
    Vp.width := VW;
    Vp.height := VH;
    Vp.minDepth := 0.0;
    Vp.maxDepth := 1.0;
    FDev.vkCmdSetViewport(FCmd, 0, 1, @Vp);
    FViewportDirty := False;
    FPushDirty := True;
  end;
  if FClipDirty then
  begin
    X1 := FViewport.X;
    Y1 := FViewport.Y;
    X2 := X1 + FViewport.W;
    Y2 := Y1 + FViewport.H;
    if (FViewport.W <= 0) or (FViewport.H <= 0) then
    begin
      X1 := 0;
      Y1 := 0;
      X2 := TW;
      Y2 := TH;
    end;
    if FClipOn then
    begin
      // クリップ矩形はビューポートの原点からの相対。ビューポートと重なる部分だけ
      X1 := Max(X1, FViewport.X + FClip.X);
      Y1 := Max(Y1, FViewport.Y + FClip.Y);
      X2 := Min(X2, FViewport.X + FClip.X + FClip.W);
      Y2 := Min(Y2, FViewport.Y + FClip.Y + FClip.H);
    end;
    // 描画先からはみ出さない（シザーの原点は 0 以上）
    X1 := Max(X1, 0);
    Y1 := Max(Y1, 0);
    X2 := Min(X2, TW);
    Y2 := Min(Y2, TH);
    Sc.offset.x := X1;
    Sc.offset.y := Y1;
    Sc.extent.width := Max(X2 - X1, 0);
    Sc.extent.height := Max(Y2 - Y1, 0);
    FDev.vkCmdSetScissor(FCmd, 0, 1, @Sc);
    FClipDirty := False;
  end;
end;

procedure TPMLVulkanRenderDriver.ActivatePass;
var
  Black: TPMLFColor;
begin
  EnsureCmd;
  if not FPassOpen then
  begin
    FillChar(Black, SizeOf(Black), 0);
    BeginPass(False, Black);
  end;
end;

procedure TPMLVulkanRenderDriver.ExecClear(const ACmd: TPMLRenderCommand);
begin
  EnsureCmd;
  // クリアはクリップを無視して全体を塗る（レンダーパスの loadOp。SDL と同じ）
  EndPass;
  BeginPass(True, ACmd.Color);
end;

procedure TPMLVulkanRenderDriver.ExecDraw(const ACmd: TPMLRenderCommand; ATopology: LongInt);
var
  Data: TPMLVulkanTexture;
  Pal: TPMLVulkanPalette;
  Consts: TPMLVkPixelConstants;
  Shader: TPMLVkShader;
  Views: array[0..NUM_TEXTURE_BINDINGS - 1] of VkImageView;
  Samps: array[0..NUM_TEXTURE_BINDINGS - 1] of VkSampler;
  I, Idx: Integer;
  Buf: VkBuffer;
  Off: VkDeviceSize;
  Set_: VkDescriptorSet;
  Zero: VkDeviceSize;
  Nearest: Boolean;
begin
  if (ACmd.Count <= 0) or (FCurVBuf = 0) then
    Exit;
  Data := nil;
  Pal := nil;
  if ACmd.Texture <> nil then
  begin
    Data := TextureOf(ACmd.Texture);
    if Data = nil then
      Exit;       // 破棄されたテクスチャ。描くものが無い
  end;
  EnsureCmd;
  FillChar(Views, SizeOf(Views), 0);
  FillChar(Samps, SizeOf(Samps), 0);
  if Data <> nil then
  begin
    // テクスチャの画像をシェーダから読める並びにする（レンダーパスの外で）
    for I := 0 to Data.NumImages - 1 do
      ToShaderRead(Data.Images[I]);
    Nearest := Data.Indexed or (ACmd.ScaleMode = TPMLScaleMode.Nearest);
    for I := 0 to Data.NumImages - 1 do
    begin
      Views[I] := Data.Views[I];
      if Nearest then
        Samps[I] := FSamplers[0]
      else
        Samps[I] := FSamplers[1];
    end;
    if Data.Indexed then
    begin
      if (ACmd.Texture.DriverPalette <> nil) and (ACmd.Texture.DriverPalette.DriverData is TPMLVulkanPalette) then
        Pal := TPMLVulkanPalette(ACmd.Texture.DriverPalette.DriverData);
      if Pal = nil then
        Exit;
      ToShaderRead(Pal.Image);
      Views[1] := Pal.View;
      Samps[1] := FSamplers[0];
    end;
    for I := 0 to NUM_TEXTURE_BINDINGS - 1 do
      if Views[I] = 0 then
      begin
        Views[I] := Views[0];
        Samps[I] := Samps[0];
      end;
  end;
  SetupConstants(ACmd, Data, Consts);
  Shader := SelectShader(Consts, Data <> nil);
  ActivatePass;
  Idx := GetPipeline(Shader, ACmd.Blend, CurrentFormat, ATopology);
  if Idx <> FCurPipeline then
  begin
    FDev.vkCmdBindPipeline(FCmd, VK_PIPELINE_BIND_POINT_GRAPHICS, FPipelines[Idx].Pipeline);
    FCurPipeline := Idx;
  end;
  UpdateViewportAndClip;
  if FPushDirty then
  begin
    FDev.vkCmdPushConstants(FCmd, FPipeLayout, VK_SHADER_STAGE_VERTEX_BIT, 0, 128, @FProj[0]);
    FPushDirty := False;
  end;
  if Data = nil then
  begin
    // 単色: 何も束縛しないが、レイアウトの上は埋める（SDL は最初の画像のビューをそのまま使う。ここは 1 枚目の
    // 画像が無いので、パレットの無い白の画像の代わりに、描画先に使う出力のビューを渡さない）
    // → 画像を持たない描画は、ダミーの 1x1 の画像のビューを使う
    Views[0] := FDummyView;
    Samps[0] := FSamplers[0];
    for I := 1 to NUM_TEXTURE_BINDINGS - 1 do
    begin
      Views[I] := Views[0];
      Samps[I] := Samps[0];
    end;
  end;
  ConstantSlot(Consts, Buf, Off);
  Set_ := AllocDescriptorSet(Buf, Off, Views, Samps);
  FDev.vkCmdBindDescriptorSets(FCmd, VK_PIPELINE_BIND_POINT_GRAPHICS, FPipeLayout, 0, 1, @Set_, 0, nil);
  Zero := 0;
  FDev.vkCmdBindVertexBuffers(FCmd, 0, 1, @FCurVBuf, @Zero);
  FDev.vkCmdDraw(FCmd, ACmd.Count, 1, ACmd.First, 0);
end;

procedure TPMLVulkanRenderDriver.RunCommandQueue(AQueue: TPMLRenderQueue);
var
  I: Integer;
  Cmd: TPMLRenderCommand;
begin
  if FWindow <> nil then
  begin
    CheckResize;
    if FMinimized or (FSwapchain = 0) then
      Exit;
  end;
  EnsureCmd;
  FViewport := TPMLRect.Make(0, 0, 0, 0);
  FClipOn := False;
  FViewportDirty := True;
  FClipDirty := True;
  PushVertices(AQueue);
  for I := 0 to AQueue.CommandCount - 1 do
  begin
    Cmd := AQueue.Commands[I];
    case Cmd.Kind of
      TPMLRenderCommandKind.SetViewport:
        begin
          FViewport := Cmd.Rect;
          FViewportDirty := True;
          FClipDirty := True;
        end;
      TPMLRenderCommandKind.SetClipRect:
        begin
          FClipOn := Cmd.Enabled;
          FClip := Cmd.Rect;
          FClipDirty := True;
        end;
      TPMLRenderCommandKind.Clear   : ExecClear(Cmd);
      TPMLRenderCommandKind.DrawLines: ExecDraw(Cmd, VK_PRIMITIVE_TOPOLOGY_LINE_LIST);
      TPMLRenderCommandKind.Geometry: ExecDraw(Cmd, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    else
      // NoOp / DrawPoints / FillRects / Copy。点・矩形・転送はこのドライバが上書きしないので、
      // 三角形（Geometry）に書き換わってから来る。
    end;
  end;
  // 頂点バッファを使い切ったら提出して、最初から使い直す（SDL_VULKAN_NUM_VERTEX_BUFFERS）
  if FVertexIdx >= MAX_VERTEX_BUFFERS then
    IssueBatch;
end;

{ ---- 読み戻しと表示 ---- }

function TPMLVulkanRenderDriver.ReadPixels(const ARect: TPMLRect): TPMLSurface;
var
  OutW, OutH, X1, Y1, X2, Y2, W, H, Row, Bpp: Integer;
  Fmt: TPMLPixelFormat;
  Buf: TPMLVkBuffer;
  Region: TVkBufferImageCopy;
  Image: VkImage;
  LayoutPtr: ^VkImageLayout;
  Src, Dst: PByte;
  RowBytes: PtrUInt;
begin
  if FTarget <> nil then
  begin
    Fmt := FTarget.PixelFormat;
    OutW := FTarget.LogicalW;
    OutH := FTarget.LogicalH;
  end
  else
  begin
    if FWindow <> nil then
      CheckResize;
    Fmt := FOutPixel;
    OutW := FOutW;
    OutH := FOutH;
  end;
  Result := TPMLSurface.Create(ARect.W, ARect.H, Fmt);
  try
    X1 := Max(ARect.X, 0);
    Y1 := Max(ARect.Y, 0);
    X2 := Min(ARect.X + ARect.W, OutW);
    Y2 := Min(ARect.Y + ARect.H, OutH);
    W := X2 - X1;
    H := Y2 - Y1;
    if (W <= 0) or (H <= 0) or (FOutCount = 0) or FMinimized then
      Exit;
    Bpp := PMLBytesPerPixel(Fmt);
    EnsureCmd;
    EndPass;
    if FTarget <> nil then
    begin
      Image := FTarget.Images[0].Image;
      LayoutPtr := @FTarget.Images[0].Layout;
    end
    else
    begin
      Image := FOutImages[FImageIdx];
      LayoutPtr := @FOutLayouts[FImageIdx];
    end;
    AllocBuffer(PtrUInt(W) * PtrUInt(H) * PtrUInt(Bpp), VK_BUFFER_USAGE_TRANSFER_DST_BIT, Buf);
    try
      Barrier(Image, LayoutPtr^, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, ALL_ACCESS, VK_ACCESS_TRANSFER_READ_BIT,
        ALL_STAGES, VK_PIPELINE_STAGE_TRANSFER_BIT);
      FillChar(Region, SizeOf(Region), 0);
      Region.imageSubresource.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
      Region.imageSubresource.layerCount := 1;
      Region.imageOffset.x := X1;
      Region.imageOffset.y := Y1;
      Region.imageExtent.width := W;
      Region.imageExtent.height := H;
      Region.imageExtent.depth := 1;
      FDev.vkCmdCopyImageToBuffer(FCmd, Image, LayoutPtr^, Buf.Buffer, 1, @Region);
      // 写しが終わるまで提出して待つ。そのあと描画先の並びへ戻す
      IssueBatch;
      EnsureCmd;
      if FTarget <> nil then
        Barrier(Image, LayoutPtr^, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_ACCESS_TRANSFER_READ_BIT, ALL_ACCESS,
          VK_PIPELINE_STAGE_TRANSFER_BIT, ALL_STAGES);
      RowBytes := PtrUInt(W) * PtrUInt(Bpp);
      for Row := 0 to H - 1 do
      begin
        Src := PByte(Buf.Mapped) + PtrUInt(Row) * RowBytes;
        Dst := PByte(Result.Pixels) + PtrUInt(Y1 - ARect.Y + Row) * PtrUInt(Result.Pitch)
          + PtrUInt(X1 - ARect.X) * PtrUInt(Bpp);
        Move(Src^, Dst^, RowBytes);
      end;
    finally
      FreeBuffer(Buf);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TPMLVulkanRenderDriver.Present;
var
  Info: TVkPresentInfoKHR;
  Sig: VkSemaphore;
  Idx: LongWord;
  Rc: VkResult;
begin
  if FWindow = nil then
  begin
    // オフスクリーンは見せる先が無い。溜まった描画だけ終わらせる
    IssueBatch;
    Exit;
  end;
  CheckResize;
  if FMinimized or (FSwapchain = 0) or not FCmdOpen then
    Exit;
  Idx := FImageIdx;
  Barrier(FOutImages[Idx], FOutLayouts[Idx], VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    VK_ACCESS_COLOR_ATTACHMENT_READ_BIT or VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);
  Sig := FFinishSems[FFrame];
  SubmitAndWait(Sig);
  FillChar(Info, SizeOf(Info), 0);
  Info.sType := VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
  Info.waitSemaphoreCount := 1;
  Info.pWaitSemaphores := @Sig;
  Info.swapchainCount := 1;
  Info.pSwapchains := @FSwapchain;
  Info.pImageIndices := @Idx;
  Rc := FDev.vkQueuePresentKHR(FQueue, @Info);
  if (Rc = VK_ERROR_OUT_OF_DATE_KHR) or (Rc = VK_ERROR_SURFACE_LOST_KHR) or (Rc = VK_SUBOPTIMAL_KHR) then
    FRecreate := True
  else if Rc <> VK_SUCCESS then
    Fail('vkQueuePresentKHR()', Rc);
  FFrame := (FFrame + 1) mod Max(FOutCount, 1);
  if not FRecreate then
    AcquireNext;
end;

function TPMLVulkanRenderDriver.SetVSync(AInterval: Integer): Boolean;
begin
  if FWindow = nil then
    Exit(AInterval = 0);
  if (AInterval < -1) or (AInterval > 1) then
    Exit(False);
  if AInterval <> FVSync then
  begin
    FVSync := AInterval;
    FRecreate := True;
  end;
  Result := True;
end;

{ ---- 破棄 ---- }

procedure TPMLVulkanRenderDriver.ReleaseAll;
var
  I: Integer;
  S: TPMLVkShader;
begin
  if FDevice <> nil then
  begin
    if FCmdOpen then
      IssueBatch;
    FDev.vkDeviceWaitIdle(FDevice);
    ReleasePending;
    for I := 0 to High(FPipelines) do
      FDev.vkDestroyPipeline(FDevice, FPipelines[I].Pipeline, nil);
    FPipelines := nil;
    for I := 0 to High(FVertexBufs) do
      FreeBuffer(FVertexBufs[I]);
    FVertexBufs := nil;
    for I := 0 to High(FConstBufs) do
      FreeBuffer(FConstBufs[I]);
    FConstBufs := nil;
    for I := 0 to High(FPools) do
      FDev.vkDestroyDescriptorPool(FDevice, FPools[I], nil);
    FPools := nil;
    if FDummyView <> 0 then
      FDev.vkDestroyImageView(FDevice, FDummyView, nil);
    FreeImage(FDummyImage);
    for I := 0 to 1 do
      if FSamplers[I] <> 0 then
        FDev.vkDestroySampler(FDevice, FSamplers[I], nil);
    if FPipeLayout <> 0 then
      FDev.vkDestroyPipelineLayout(FDevice, FPipeLayout, nil);
    if FSetLayout <> 0 then
      FDev.vkDestroyDescriptorSetLayout(FDevice, FSetLayout, nil);
    for S := Low(TPMLVkShader) to High(TPMLVkShader) do
    begin
      if FVertexModule[S] <> 0 then
        FDev.vkDestroyShaderModule(FDevice, FVertexModule[S], nil);
      if FFragModules[S] <> 0 then
        FDev.vkDestroyShaderModule(FDevice, FFragModules[S], nil);
    end;
    if FWindow <> nil then
    begin
      DestroySwapchainObjects;
      if FSwapchain <> 0 then
        FDev.vkDestroySwapchainKHR(FDevice, FSwapchain, nil);
    end
    else
    begin
      for I := 0 to High(FOutFBs) do
        if FOutFBs[I] <> 0 then
          FDev.vkDestroyFramebuffer(FDevice, FOutFBs[I], nil);
      for I := 0 to High(FOutViews) do
        if FOutViews[I] <> 0 then
          FDev.vkDestroyImageView(FDevice, FOutViews[I], nil);
      for I := 0 to High(FOutImages) do
        if FOutImages[I] <> 0 then
          FDev.vkDestroyImage(FDevice, FOutImages[I], nil);
      if FOutMemory <> 0 then
        FDev.vkFreeMemory(FDevice, FOutMemory, nil);
      DestroyPasses(FOutPasses);
    end;
    if FPoolCmd <> 0 then
      FDev.vkDestroyCommandPool(FDevice, FPoolCmd, nil);
    FDev.vkDestroyDevice(FDevice, nil);
    FDevice := nil;
  end;
  if (FSurface <> 0) and (FVideo <> nil) then
  begin
    FVideo.VulkanDestroySurface(FInstance, FSurface, nil);
    FSurface := 0;
  end;
  if FInstance <> nil then
  begin
    FInst.vkDestroyInstance(FInstance, nil);
    FInstance := nil;
  end;
end;

{ ---- 登録 ---- }

{ Vulkan で作ったウィンドウには、このドライバを選ぶ。SDL の render_drivers の並びでは opengl と opengles2 の後ろ
  （GL のウィンドウと Vulkan のウィンドウは別のフラグなので、同じウィンドウを取り合わない）。
  作れなかったら、次のドライバ（ソフトウェア）へ進む（CreateWindowDriver）。 }
function VulkanDriverPrefers(AWindow: TPMLWindow): Boolean;
begin
  Result := TPMLWindowFlag.Vulkan in AWindow.Flags;
end;

function CreateVulkanDriver(AWindow: TPMLWindow): TPMLRenderDriver;
begin
  Result := TPMLVulkanRenderDriver.CreateForWindow(AWindow);
end;

initialization
  PMLRegisterRenderDriver('vulkan', 50, @VulkanDriverPrefers, @CreateVulkanDriver);

end.
