{
  PaPiMeLa.Platform.Vulkan — Vulkan の型・定数・関数表

  Origin : partially ported from SDL (src/video/khronos/vulkan/vulkan_core.h、vulkan_wayland.h、
           src/video/SDL_vulkan_internal.h、src/video/SDL_vulkan_utils.c、src/render/vulkan/SDL_render_vulkan.c)
           Scope: SDL の Wayland + レンダラの経路が使う Vulkan の型（330 件。うち構造体と共用体 95、関数の型 103）・定数（246 件）・関数（96 件）。
           関数の取り方は PMLVulkanLoad*Functions（SDL の vkGetInstanceProcAddr / vkGetDeviceProcAddr の表）
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §9、§11 #76、#67

  WHAT:
    SDL が同梱する Khronos ヘッダ（tools/genvulkan.bb が読む）から作った、Vulkan の型・定数・関数の型と、
    3 つの関数表（global / instance / device）とその読み込み。

  WHY:
    papimela は C のヘッダを使わない。SDL の video/ と render/vulkan/ が使う分だけを持つ
    （SDL もヘッダを同梱し、関数はリンクせず vkGetInstanceProcAddr から実行時に引く）。

  RESOLVED:
    - record は T を付ける（TVkInstanceCreateInfo）。ポインタ型は PVk...。列挙は LongInt の別名と C の値の定数
      （Pascal の列挙型にしない: C の値をそのまま渡す、フラグを or で組む、VkResult が負になる）
    - PACKRECORDS C: Vulkan の構造体は C の配置。大きさと各フィールドの位置は、gcc が測った値との往復検査
      （test/test_platform_vulkan.pas、期待値は tools/genvulkan.bb --layout が作る test/vulkan_layout.inc）
    - 非ディスパッチャブルのハンドルは UInt64（64 ビットの C ではポインタと同じ大きさ・渡し方）
    - 表を埋める関数は、見つからなかった名前をカンマ区切りで返す（全部あれば空文字列）。見つからなかった欄は nil。
      どれが必須かは呼ぶ側が決める（SDL も拡張の関数は欠けていてよい）
    - vkGetInstanceProcAddr は表に入れない。ローダ（libvulkan.so.1）から dlsym で取る（Video の部品の仕事）
    - 呼び出し側は、C のドライバを呼ぶので浮動小数点の例外を止めること（D-40。PMLEGLLoad と同じ）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.Vulkan;

{$I papimela.inc}

interface

{$PACKRECORDS C}

type
{$I generated/vulkan_types.inc}

const
{$I generated/vulkan_constants.inc}

type
  { vkCreateInstance など、インスタンスが無くても引ける関数。 }
  TPMLVulkanGlobalFunctions = record
{$I generated/vulkan_functions_global.inc}
  end;

  { vkGetInstanceProcAddr(instance, ...) で引く関数。 }
  TPMLVulkanInstanceFunctions = record
{$I generated/vulkan_functions_instance.inc}
  end;

  { vkGetDeviceProcAddr(device, ...) で引く関数（第 1 引数が VkDevice / VkQueue / VkCommandBuffer）。 }
  TPMLVulkanDeviceFunctions = record
{$I generated/vulkan_functions_device.inc}
  end;

{$PACKRECORDS DEFAULT}

{ VK_MAKE_API_VERSION / VK_VERSION_MAJOR など（C のマクロ）。 }
function VK_MAKE_API_VERSION(AVariant, AMajor, AMinor, APatch: LongWord): LongWord;
function VK_API_VERSION_VARIANT(AVersion: LongWord): LongWord;
function VK_API_VERSION_MAJOR(AVersion: LongWord): LongWord;
function VK_API_VERSION_MINOR(AVersion: LongWord): LongWord;
function VK_API_VERSION_PATCH(AVersion: LongWord): LongWord;

{ VkResult の名前（SDL_Vulkan_GetResultString）。知らない値は、負なら 'VK_ERROR_<Unknown>'、
  そうでなければ 'VK_<Unknown>'。 }
function PMLVulkanResultString(AResult: VkResult): String;

{ ローダの vkGetInstanceProcAddr で、インスタンス無しの関数表を埋める。 }
function PMLVulkanLoadGlobalFunctions(AGetProc: PFN_vkGetInstanceProcAddr;
  out AFuncs: TPMLVulkanGlobalFunctions): String;

{ インスタンスの関数表を埋める。AInstance は vkCreateInstance の結果。 }
function PMLVulkanLoadInstanceFunctions(AGetProc: PFN_vkGetInstanceProcAddr; AInstance: VkInstance;
  out AFuncs: TPMLVulkanInstanceFunctions): String;

{ デバイスの関数表を埋める。AGetProc はインスタンスの表の vkGetDeviceProcAddr。 }
function PMLVulkanLoadDeviceFunctions(AGetProc: PFN_vkGetDeviceProcAddr; ADevice: VkDevice;
  out AFuncs: TPMLVulkanDeviceFunctions): String;

implementation

function VK_MAKE_API_VERSION(AVariant, AMajor, AMinor, APatch: LongWord): LongWord;
begin
  Result := (AVariant shl 29) or (AMajor shl 22) or (AMinor shl 12) or APatch;
end;

function VK_API_VERSION_VARIANT(AVersion: LongWord): LongWord;
begin
  Result := AVersion shr 29;
end;

function VK_API_VERSION_MAJOR(AVersion: LongWord): LongWord;
begin
  Result := (AVersion shr 22) and $7F;
end;

function VK_API_VERSION_MINOR(AVersion: LongWord): LongWord;
begin
  Result := (AVersion shr 12) and $3FF;
end;

function VK_API_VERSION_PATCH(AVersion: LongWord): LongWord;
begin
  Result := AVersion and $FFF;
end;

function PMLVulkanResultString(AResult: VkResult): String;
begin
  case AResult of
{$I generated/vulkan_result_strings.inc}
  else
    if AResult < 0 then
      Result := 'VK_ERROR_<Unknown>'
    else
      Result := 'VK_<Unknown>';
  end;
end;

function PMLVulkanLoadGlobalFunctions(AGetProc: PFN_vkGetInstanceProcAddr;
  out AFuncs: TPMLVulkanGlobalFunctions): String;
var
  Missing: String;

  procedure Bind(out ATarget; const AName: String);
  begin
    Pointer(ATarget) := Pointer(AGetProc(nil, PAnsiChar(AName)));
    if Pointer(ATarget) = nil then
    begin
      if Missing <> '' then
        Missing := Missing + ', ';
      Missing := Missing + AName;
    end;
  end;

begin
  FillChar(AFuncs, SizeOf(AFuncs), 0);
  Missing := '';
{$I generated/vulkan_bind_global.inc}
  Result := Missing;
end;

function PMLVulkanLoadInstanceFunctions(AGetProc: PFN_vkGetInstanceProcAddr; AInstance: VkInstance;
  out AFuncs: TPMLVulkanInstanceFunctions): String;
var
  Missing: String;

  procedure Bind(out ATarget; const AName: String);
  begin
    Pointer(ATarget) := Pointer(AGetProc(AInstance, PAnsiChar(AName)));
    if Pointer(ATarget) = nil then
    begin
      if Missing <> '' then
        Missing := Missing + ', ';
      Missing := Missing + AName;
    end;
  end;

begin
  FillChar(AFuncs, SizeOf(AFuncs), 0);
  Missing := '';
{$I generated/vulkan_bind_instance.inc}
  Result := Missing;
end;

function PMLVulkanLoadDeviceFunctions(AGetProc: PFN_vkGetDeviceProcAddr; ADevice: VkDevice;
  out AFuncs: TPMLVulkanDeviceFunctions): String;
var
  Missing: String;

  procedure Bind(out ATarget; const AName: String);
  begin
    Pointer(ATarget) := Pointer(AGetProc(ADevice, PAnsiChar(AName)));
    if Pointer(ATarget) = nil then
    begin
      if Missing <> '' then
        Missing := Missing + ', ';
      Missing := Missing + AName;
    end;
  end;

begin
  FillChar(AFuncs, SizeOf(AFuncs), 0);
  Missing := '';
{$I generated/vulkan_bind_device.inc}
  Result := Missing;
end;

end.
