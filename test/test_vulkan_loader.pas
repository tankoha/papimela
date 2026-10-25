{
  test_vulkan_loader — Vulkan 部品の共通実装（PaPiMeLa.Video.Vulkan）。ローダの読み込みと回数の管理

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    TPMLVulkanLoaderBackend を、プラットフォームの面の無い検査用の派生クラスで確かめる（Wayland の面の作成は
    コンポジタが要るので test_vulkan_window.pas、手元専用）。
      missing    読めないパスは失敗し、理由にパスが入る。読み込み状態は変わらない
      hint       PAPIMELA_VULKAN_LIBRARY のヒントが使われ、引数のパスがヒントに勝つ（SDL の path の優先順位）
      refcount   読んだ回数を数える。別のパスでの 2 回目は失敗する。0 になったら手放す。余分な Unload は無視
      extension  必要な拡張が欠けたら失敗し、ローダを閉じる。そのあと正しい拡張で読み直せる
      instance   読んだローダで、必要な拡張つきのインスタンスが作れ、物理デバイスが見える（ICD が要る）
      destroy    数えた回数が残ったままでも、破棄でローダを手放す。面の破棄は関数が無くても落ちない

    ローダ（libvulkan.so.1）が無い環境では失敗にする。飛ばしてよいのは PAPIMELA_VULKAN_OPTIONAL=1 のときだけ
    （空の実装が「飛ばした」ことで通ってしまわないように）。
}
program test_vulkan_loader;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Core,
  PaPiMeLa.Properties,
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Platform.Vulkan,
  PaPiMeLa.Errors,
  PaPiMeLa.Backends,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video.Vulkan;

type
  { 面を作らない検査用。必要な拡張は ExtraRequired で足せる。 }
  TTestLoader = class(TPMLVulkanLoaderBackend)
  public
    ExtraRequired: String;
    function  CreateSurface(AWindow: TPMLWindowBackend; AInstance: VkInstance;
      AAllocator: PVkAllocationCallbacks; out ASurface: VkSurfaceKHR): Boolean; override;
    function  GetPresentationSupport(AInstance: VkInstance; APhysicalDevice: VkPhysicalDevice;
      AQueueFamilyIndex: LongWord): Boolean; override;
    function  Loaded: Boolean;
  strict protected
    function  RequiredExtensions: TPMLVulkanExtensionNames; override;
  end;

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

function TTestLoader.CreateSurface(AWindow: TPMLWindowBackend; AInstance: VkInstance;
  AAllocator: PVkAllocationCallbacks; out ASurface: VkSurfaceKHR): Boolean;
begin
  ASurface := 0;
  Result := False;
end;

function TTestLoader.GetPresentationSupport(AInstance: VkInstance;
  APhysicalDevice: VkPhysicalDevice; AQueueFamilyIndex: LongWord): Boolean;
begin
  Result := False;
end;

function TTestLoader.Loaded: Boolean;
begin
  Result := IsLoaded;
end;

function TTestLoader.RequiredExtensions: TPMLVulkanExtensionNames;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := VK_KHR_SURFACE_EXTENSION_NAME;
  Result[1] := VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME;
  if ExtraRequired <> '' then
  begin
    SetLength(Result, 3);
    Result[2] := ExtraRequired;
  end;
end;

function NewContext(const AHintPath: String): TPMLContext;
var
  Opts: TPMLContextOptions;
begin
  Opts := TPMLContextOptions.Default;
  if AHintPath <> '' then
    Opts.Hints.Add(PML_HINT_VULKAN_LIBRARY, AHintPath);
  Result := TPMLContext.Create([], Opts);
end;

function Optional: Boolean;
begin
  Result := GetEnvironmentVariable('PAPIMELA_VULKAN_OPTIONAL') = '1';
end;

procedure MissingSection;
var
  L: TTestLoader;
begin
  WriteLn('1. 読めないパス');
  L := TTestLoader.Create(Ctx, nil);
  try
    Check(not L.LoadLibrary('/nonexistent/libvulkan-nothing.so.1'), '読めないパスは失敗する');
    Check(Pos('/nonexistent/libvulkan-nothing.so.1', L.LastError) > 0, '理由にパスが入る（' + L.LastError + '）');
    Check((L.LoadCount = 0) and not L.Loaded, '読み込み状態は変わらない');
    Check(L.GetInstanceProcAddr = nil, '読んでいなければ vkGetInstanceProcAddr は nil');
    Check(Pos('No Vulkan loader', L.LastError) > 0, 'その理由は「読んでいない」');
    L.UnloadLibrary;
    Check(L.LoadCount = 0, '読んでいないときの Unload は無視される');
  finally
    L.Free;
  end;
end;

procedure HintSection;
var
  C: TPMLContext;
  L: TTestLoader;
begin
  WriteLn('2. ヒントと引数の優先順位');
  C := NewContext('/nonexistent/hinted-vulkan.so');
  try
    L := TTestLoader.Create(C, nil);
    try
      Check(not L.LoadLibrary(''), 'ヒントのパスが使われる（読めないので失敗）');
      Check(Pos('/nonexistent/hinted-vulkan.so', L.LastError) > 0, '理由にヒントのパスが入る（' + L.LastError + '）');
      if TPMLDynLib.IsAvailable(['libvulkan.so.1']) then
      begin
        Check(L.LoadLibrary('libvulkan.so.1') and L.Loaded, '引数のパスはヒントに勝つ');
        Check(L.LoaderPath = 'libvulkan.so.1', '読んだパスを覚える');
      end;
    finally
      L.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure RefcountSection;
var
  L: TTestLoader;
begin
  WriteLn('3. 読んだ回数');
  if not TPMLDynLib.IsAvailable(['libvulkan.so.1']) then
  begin
    if Optional then
      WriteLn('  [SKIP] libvulkan.so.1 が無い')
    else
      Check(False, 'libvulkan.so.1 がある（無い環境では PAPIMELA_VULKAN_OPTIONAL=1）');
    Exit;
  end;
  L := TTestLoader.Create(Ctx, nil);
  try
    Check(L.LoadLibrary('') and (L.LoadCount = 1) and L.Loaded, '1 回目: 読める');
    Check(L.GetInstanceProcAddr <> nil, 'vkGetInstanceProcAddr が得られる');
    Check(L.LoadLibrary('') and (L.LoadCount = 2), '2 回目（パスが空）: 回数が増えるだけ');
    Check(L.LoadLibrary(L.LoaderPath) and (L.LoadCount = 3), '3 回目（同じパス）: 回数が増えるだけ');
    Check(not L.LoadLibrary('/other/libvulkan.so.1') and (L.LoadCount = 3), '別のパスは失敗し、回数は変わらない');
    Check(Pos('already loaded', L.LastError) > 0, 'その理由は「既に読んである」');
    L.UnloadLibrary;
    L.UnloadLibrary;
    Check((L.LoadCount = 1) and L.Loaded and (L.GetInstanceProcAddr <> nil), '2 回 Unload しても、まだ 1 回分あるので生きている');
    L.UnloadLibrary;
    Check((L.LoadCount = 0) and not L.Loaded and (L.GetInstanceProcAddr = nil), '0 になったら手放す');
    L.UnloadLibrary;
    L.UnloadLibrary;
    Check(L.LoadCount = 0, '余分な Unload で負にならない');
    Check(L.LoadLibrary('') and (L.LoadCount = 1) and L.Loaded, '手放したあとで読み直せる');
  finally
    L.Free;
  end;
end;

procedure ExtensionSection;
var
  L: TTestLoader;
begin
  WriteLn('4. 必要な拡張');
  if not TPMLDynLib.IsAvailable(['libvulkan.so.1']) then
    Exit;
  L := TTestLoader.Create(Ctx, nil);
  try
    L.ExtraRequired := 'VK_KHR_nonexistent_extension_for_test';
    Check(not L.LoadLibrary(''), '無い拡張を要るなら失敗する');
    Check(Pos('doesn''t implement the VK_KHR_nonexistent_extension_for_test extension', L.LastError) > 0,
      '理由に拡張の名前が入る（' + L.LastError + '）');
    Check((L.LoadCount = 0) and not L.Loaded and (L.GetInstanceProcAddr = nil), 'ローダは閉じられ、回数も増えない');
    L.ExtraRequired := '';
    Check(L.LoadLibrary('') and L.Loaded, '正しい拡張で読み直せる');
    Check((Length(L.GetInstanceExtensions) = 2) and (L.GetInstanceExtensions[0] = 'VK_KHR_surface')
      and (L.GetInstanceExtensions[1] = 'VK_KHR_wayland_surface'), 'インスタンスの拡張の名前');
  finally
    L.Free;
  end;
end;

procedure InstanceSection;
var
  L: TTestLoader;
  Exts: TPMLVulkanExtensionNames;
  Names: array of PAnsiChar;
  G: TPMLVulkanGlobalFunctions;
  I: TPMLVulkanInstanceFunctions;
  App: TVkApplicationInfo;
  ICI: TVkInstanceCreateInfo;
  Inst: VkInstance;
  Rc: VkResult;
  Count: LongWord;
  K: Integer;
  MissingNames: String;
begin
  WriteLn('5. インスタンス');
  if not TPMLDynLib.IsAvailable(['libvulkan.so.1']) then
    Exit;
  L := TTestLoader.Create(Ctx, nil);
  try
    if not L.LoadLibrary('') then
    begin
      Check(False, 'ローダが読める（' + L.LastError + '）');
      Exit;
    end;
    Check(PMLVulkanLoadGlobalFunctions(L.GetInstanceProcAddr, G) = '', 'global の関数が引ける');
    Exts := L.GetInstanceExtensions;
    SetLength(Names, Length(Exts));
    for K := 0 to High(Exts) do
      Names[K] := PAnsiChar(Exts[K]);
    FillChar(App, SizeOf(App), 0);
    App.sType := VK_STRUCTURE_TYPE_APPLICATION_INFO;
    App.pApplicationName := 'test_vulkan_loader';
    App.apiVersion := VK_API_VERSION_1_0;
    FillChar(ICI, SizeOf(ICI), 0);
    ICI.sType := VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    ICI.pApplicationInfo := @App;
    ICI.enabledExtensionCount := Length(Names);
    ICI.ppEnabledExtensionNames := @Names[0];
    Inst := nil;
    Rc := G.vkCreateInstance(@ICI, nil, @Inst);
    if Rc <> VK_SUCCESS then
    begin
      if Optional and (Rc = VK_ERROR_INCOMPATIBLE_DRIVER) then
        WriteLn('  [SKIP] ICD が無い（', PMLVulkanResultString(Rc), '）')
      else
        Check(False, 'インスタンスが作れる（' + PMLVulkanResultString(Rc) + '。ICD が要る。無い環境では PAPIMELA_VULKAN_OPTIONAL=1）');
      Exit;
    end;
    try
      Check(Inst <> nil, 'GetInstanceExtensions の拡張つきでインスタンスが作れる');
      MissingNames := PMLVulkanLoadInstanceFunctions(L.GetInstanceProcAddr, Inst, I);
      // *2KHR の 3 つは VK_KHR_get_physical_device_properties2 を有効にしたインスタンスでだけ引ける（SDL は条件つきで有効にする）
      Check((Pos('vkCreate', MissingNames) = 0) and (Pos('vkEnumerate', MissingNames) = 0)
        and (Pos('vkGetPhysicalDeviceWayland', MissingNames) = 0) and (Pos('vkGetPhysicalDeviceSurface', MissingNames) = 0)
        and (Pos('vkGetDeviceProcAddr', MissingNames) = 0),
        'instance の関数が引ける（Wayland の面の関数も。欠けてよいのは *2KHR の 3 つだけ。欠け: ' + MissingNames + '）');
      Check((I.vkCreateWaylandSurfaceKHR <> nil) and (I.vkGetPhysicalDeviceWaylandPresentationSupportKHR <> nil)
        and (I.vkDestroySurfaceKHR <> nil) and (I.vkGetDeviceProcAddr <> nil), 'Wayland の面と vkGetDeviceProcAddr が引ける');
      Count := 0;
      Rc := I.vkEnumeratePhysicalDevices(Inst, @Count, nil);
      Check((Rc = VK_SUCCESS) and (Count > 0), Format('物理デバイスが見える（%d）', [Count]));
      // 面の破棄: VK_NULL_HANDLE は何もしない。関数が引けない（インスタンス nil）ときは何も呼ばない
      L.DestroySurface(Inst, 0, nil);
      L.DestroySurface(nil, 0, nil);
      Check(True, 'DestroySurface は VK_NULL_HANDLE でも、インスタンス nil でも落ちない');
    finally
      I.vkDestroyInstance(Inst, nil);
    end;
  finally
    L.Free;
  end;
end;

procedure DestroySection;
var
  L: TTestLoader;
begin
  WriteLn('6. 破棄');
  L := TTestLoader.Create(Ctx, nil);
  // ローダを読まないまま、面の破棄とアンロードを呼んでも落ちない
  L.DestroySurface(nil, 0, nil);
  L.UnloadLibrary;
  L.Free;
  Check(True, '読んでいないバックエンドの破棄');
  if not TPMLDynLib.IsAvailable(['libvulkan.so.1']) then
    Exit;
  L := TTestLoader.Create(Ctx, nil);
  L.LoadLibrary('');
  L.LoadLibrary('');
  L.Free;
  Check(True, '回数が残ったままの破棄（ローダを手放す）');
end;

{ 公開層（TPMLVideoSystem / TPMLWindowOptions）。Vulkan の無い（ダミーの）ビデオでは能力が無く、
  EPMLUnsupported で断る。ウィンドウも作らない。 }
procedure PublicSection;
var
  C: TPMLContext;
  Opts: TPMLContextOptions;
  W: TPMLWindow;
  Raised: Boolean;
begin
  WriteLn('7. 公開層（ダミーのビデオ。能力 Vulkan が無い）');
  Opts := TPMLContextOptions.Default;
  Opts.PreferredVideo := 'dummy';
  C := TPMLContext.Create([TPMLSubsystem.Video], Opts);
  try
    Check(not (TPMLVideoCapability.Vulkan in C.Video.Capabilities), 'ダミーは能力 Vulkan を持たない');
    Raised := False;
    try
      C.Video.VulkanLoadLibrary;
    except
      on EPMLUnsupported do Raised := True;
    end;
    Check(Raised, 'VulkanLoadLibrary は EPMLUnsupported');
    Raised := False;
    try
      C.Video.CreateWindow(TPMLWindowOptions.Make('t', 64, 64).Vulkan);
    except
      on EPMLUnsupported do Raised := True;
    end;
    Check(Raised and (Length(C.Video.Windows) = 0), 'Vulkan のウィンドウは作れず、EPMLUnsupported（ウィンドウは残らない）');
    Raised := False;
    try
      C.Video.VulkanInstanceExtensions;
    except
      on EPMLUnsupported do Raised := True;
    end;
    Check(Raised, 'VulkanInstanceExtensions は EPMLUnsupported');
    C.Video.VulkanDestroySurface(nil, 0, nil);
    Check(True, 'VulkanDestroySurface は何もしない（SDL_Vulkan_DestroySurface）');
    W := C.Video.CreateWindow(TPMLWindowOptions.Make('t', 64, 64));
    Raised := False;
    try
      W.VulkanCreateSurface(nil);
    except
      on EPMLUnsupported do Raised := True;
    end;
    Check(Raised, '面は、能力が無ければ EPMLUnsupported');
  finally
    C.Free;
  end;
end;

begin
  WriteLn('test_vulkan_loader');
  Ctx := NewContext('');
  try
    MissingSection;
    HintSection;
    RefcountSection;
    ExtensionSection;
    InstanceSection;
    DestroySection;
    PublicSection;
  finally
    Ctx.Free;
  end;
  WriteLn;
  WriteLn('失敗: ', Failures);
  if Failures > 0 then
    Halt(1);
end.
