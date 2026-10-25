{
  PaPiMeLa.Video.Vulkan — Vulkan 部品の共通実装（ローダの読み込みと面の破棄）

  Origin : partially ported from SDL (src/video/SDL_vulkan_utils.c、src/video/wayland/SDL_waylandvulkan.c、
           src/video/SDL_video.c)
           Scope: SDL_Vulkan_CreateInstanceExtensionsList（インスタンスの拡張の列挙と、失敗の文言）、
           Wayland_Vulkan_LoadLibrary / UnloadLibrary の共通の部分（パスの決め方、vkGetInstanceProcAddr の取得、
           必要な拡張の確認）、SDL_Vulkan_DestroySurface_Internal、SDL_Vulkan_LoadLibrary / UnloadLibrary の
           読んだ回数の数え方（loader_loaded）。
           移植しないもの: KHR display（KMS）の面（SDL_Vulkan_Display_CreateSurface）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.4、§9、§11 #77、#67

  WHAT:
    プラットフォームに依らない Vulkan の部品。libvulkan.so.1 の読み込みと、読んだ回数の管理、
    インスタンスの拡張の一覧の確認、面の破棄。プラットフォーム固有の部分（必要な拡張の名前、
    面の作成、presentation support）は抽象メソッドで、Wayland は TPMLWaylandVulkan が実装する。

  WHY:
    SDL は X11 / Wayland / KMS が同じ SDL_vulkan_utils.c を使い、読み込みの回数は SDL_video.c が持つ。
    papimela は状態をこのオブジェクトのフィールドに持つ（Context が複数あっても混ざらない）。

  RESOLVED:
    - 読んだ回数が 0 でない間は、同じパスなら回数を増やすだけ。別のパスなら失敗する
      （SDL_Vulkan_LoadLibrary の「Vulkan loader library already loaded」）。パスが空なら何でもよい
    - 必要な拡張が欠けたら、読み込んだローダを閉じて失敗する（SDL の fail ラベル）
    - ローダを開く名前は libvulkan.so.1 だけ（SDL も DEFAULT_VULKAN の 1 つ。libvulkan.so へは逃げない。
      開発用のリンクは入っていないことが多い）。パスを渡されたらそれだけを試す
    - 浮動小数点の例外はローダを読むスレッドで止める（D-40）。Vulkan を呼ぶほかのスレッドは各自で止める
    - デストラクタは、数えた回数に関係なく手放す（SDL_VideoQuit の vulkan_config.loader_loaded = 0）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Vulkan;

{$I papimela.inc}

interface

uses
  SysUtils, Math,
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Platform.Vulkan,
  PaPiMeLa.Properties,
  PaPiMeLa.Video.Backend;

type
  TPMLVulkanLoaderBackend = class abstract(TPMLVulkanBackend)
  strict private
    FLib        : TPMLDynLib;
    FLoadCount  : Integer;
    FLoaderPath : String;
    FGetProc    : PFN_vkGetInstanceProcAddr;
    function  HintValue(const AName: String): String;
    function  OpenLoader(const APath: String): Boolean;
    procedure CloseLoader;
    function  CheckExtensions: Boolean;
  strict protected
    { インスタンスに要るプラットフォームの拡張（VK_KHR_surface を含む）。 }
    function  RequiredExtensions: TPMLVulkanExtensionNames; virtual; abstract;
    function  IsLoaded: Boolean;
    property  GetProc: PFN_vkGetInstanceProcAddr read FGetProc;
  public
    destructor Destroy; override;

    function  LoadLibrary(const APath: String): Boolean; override;
    procedure UnloadLibrary; override;
    function  GetInstanceProcAddr: PFN_vkGetInstanceProcAddr; override;
    function  GetInstanceExtensions: TPMLVulkanExtensionNames; override;
    procedure DestroySurface(AInstance: VkInstance; ASurface: VkSurfaceKHR;
      AAllocator: PVkAllocationCallbacks); override;

    { 読んだ回数（検査用）。 }
    property  LoadCount: Integer read FLoadCount;
    property  LoaderPath: String read FLoaderPath;
  end;

implementation

const
  DEFAULT_VULKAN = 'libvulkan.so.1';

destructor TPMLVulkanLoaderBackend.Destroy;
begin
  CloseLoader;
  FLoadCount := 0;
  inherited Destroy;
end;

function TPMLVulkanLoaderBackend.HintValue(const AName: String): String;
begin
  if (ContextServices <> nil) and (ContextServices.Hints <> nil) then
    Result := ContextServices.Hints.GetHint(AName)
  else
    Result := '';
end;

function TPMLVulkanLoaderBackend.IsLoaded: Boolean;
begin
  Result := FLib <> nil;
end;

procedure TPMLVulkanLoaderBackend.CloseLoader;
begin
  FGetProc := nil;
  FreeAndNil(FLib);
  FLoaderPath := '';
end;

{ vkEnumerateInstanceExtensionProperties で拡張の一覧を作り、必要なものが全部あるかを見る
  （SDL_Vulkan_CreateInstanceExtensionsList と、Wayland_Vulkan_LoadLibrary の確認）。 }
function TPMLVulkanLoaderBackend.CheckExtensions: Boolean;
type
  TEnumExt = function(ALayer: PAnsiChar; var ACount: LongWord;
    AProps: PVkExtensionProperties): VkResult; cdecl;
var
  Enum: TEnumExt;
  Count: LongWord;
  Props: array of TVkExtensionProperties;
  Rc: VkResult;
  Required: TPMLVulkanExtensionNames;
  I, J: Integer;
  Found: Boolean;
begin
  Result := False;
  Pointer(Enum) := Pointer(FGetProc(nil, 'vkEnumerateInstanceExtensionProperties'));
  if not Assigned(Enum) then
  begin
    FLastError := 'vkEnumerateInstanceExtensionProperties is not available';
    Exit;
  end;
  Count := 0;
  Rc := Enum(nil, Count, nil);
  if Rc = VK_ERROR_INCOMPATIBLE_DRIVER then
  begin
    FLastError := Format('You probably don''t have a working Vulkan driver installed. %s %s %s(%d)',
      ['Getting Vulkan extensions failed:', 'vkEnumerateInstanceExtensionProperties returned',
       PMLVulkanResultString(Rc), Rc]);
    Exit;
  end
  else if Rc <> VK_SUCCESS then
  begin
    FLastError := Format('Getting Vulkan extensions failed: vkEnumerateInstanceExtensionProperties returned %s(%d)',
      [PMLVulkanResultString(Rc), Rc]);
    Exit;
  end;
  SetLength(Props, Max(Count, 1));   // SDL は 0 個でも非 nil を返す（確保を空にしない）
  FillChar(Props[0], Length(Props) * SizeOf(TVkExtensionProperties), 0);
  Rc := Enum(nil, Count, @Props[0]);
  if Rc <> VK_SUCCESS then
  begin
    FLastError := Format('Getting Vulkan extensions failed: vkEnumerateInstanceExtensionProperties returned %s(%d)',
      [PMLVulkanResultString(Rc), Rc]);
    Exit;
  end;
  Required := RequiredExtensions;
  for I := 0 to High(Required) do
  begin
    Found := False;
    for J := 0 to Integer(Count) - 1 do
      if String(PAnsiChar(@Props[J].extensionName[0])) = Required[I] then
      begin
        Found := True;
        Break;
      end;
    if not Found then
    begin
      FLastError := 'Installed Vulkan doesn''t implement the ' + Required[I] + ' extension';
      Exit;
    end;
  end;
  Result := True;
end;

function TPMLVulkanLoaderBackend.OpenLoader(const APath: String): Boolean;
var
  Path: String;
begin
  Result := False;
  Path := APath;
  if Path = '' then
    Path := HintValue(PML_HINT_VULKAN_LIBRARY);
  if Path = '' then
    Path := DEFAULT_VULKAN;
  // C のドライバは浮動小数点の例外が無効であることを前提にしている（D-40）。
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
  try
    FLib := TPMLDynLib.Create([Path]);
  except
    on E: Exception do
    begin
      FLib := nil;
      FLastError := 'could not load the Vulkan loader ' + Path + ': ' + E.Message;
      Exit;
    end;
  end;
  FLoaderPath := Path;
  Pointer(FGetProc) := FLib.TryResolve('vkGetInstanceProcAddr');
  if not Assigned(FGetProc) then
  begin
    FLastError := 'vkGetInstanceProcAddr is not found in ' + Path;
    CloseLoader;
    Exit;
  end;
  if not CheckExtensions then
  begin
    CloseLoader;
    Exit;
  end;
  Result := True;
end;

function TPMLVulkanLoaderBackend.LoadLibrary(const APath: String): Boolean;
begin
  if FLoadCount > 0 then
  begin
    if (APath <> '') and (APath <> FLoaderPath) then
    begin
      FLastError := 'Vulkan loader library already loaded';
      Exit(False);
    end;
  end
  else if not OpenLoader(APath) then
    Exit(False);
  Inc(FLoadCount);
  Result := True;
end;

procedure TPMLVulkanLoaderBackend.UnloadLibrary;
begin
  if FLoadCount <= 0 then
    Exit;
  Dec(FLoadCount);
  if FLoadCount = 0 then
    CloseLoader;
end;

function TPMLVulkanLoaderBackend.GetInstanceProcAddr: PFN_vkGetInstanceProcAddr;
begin
  if FLoadCount > 0 then
    Result := FGetProc
  else
  begin
    FLastError := 'No Vulkan loader has been loaded';
    Result := nil;
  end;
end;

function TPMLVulkanLoaderBackend.GetInstanceExtensions: TPMLVulkanExtensionNames;
begin
  Result := RequiredExtensions;
end;

procedure TPMLVulkanLoaderBackend.DestroySurface(AInstance: VkInstance;
  ASurface: VkSurfaceKHR; AAllocator: PVkAllocationCallbacks);
var
  Fn: PFN_vkDestroySurfaceKHR;
begin
  if FLoadCount <= 0 then
    Exit;
  // SDL_Vulkan_DestroySurface_Internal: 関数が引けなければ何もしない
  Pointer(Fn) := Pointer(FGetProc(AInstance, 'vkDestroySurfaceKHR'));
  if Assigned(Fn) then
    Fn(AInstance, ASurface, AAllocator);
end;

end.
