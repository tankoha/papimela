{
  PaPiMeLa.Render.Vulkan — Vulkan で描くレンダラドライバ

  Origin : ported from SDL (src/render/vulkan/SDL_render_vulkan.c, src/render/vulkan/SDL_shaders_vulkan.c)
           Scope: VULKAN_CreateRenderer / VULKAN_CreateDeviceResources / VULKAN_CreateWindowSizeDependentResources
           （物理デバイスの選択、スワップチェーン、レンダーパス、パイプライン、ディスクリプタ）、
           テクスチャ（形式の対応表、INDEX8、YUV）、描画先のテクスチャ、頂点バッファ、
           VULKAN_RunCommandQueue、VULKAN_RenderReadPixels、VULKAN_RenderPresent、VULKAN_SetVSync。
           移植しないもの: HDR / PQ と Advanced のシェーダ（初回の範囲外）、Android のハードウェアバッファ。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.3、§11 #67

  WHAT:
    TPMLRenderDriver の Vulkan 版。ウィンドウ（Vulkan の面とスワップチェーン）か、窓の無いオフスクリーン
    （画像に描いて読み戻す。検査用）に描く。

  WHY:
    SDL の render/vulkan の移植。Platform.Vulkan（型と関数表）と Video.Vulkan（ローダと面）の上に載る。

  NOT RESOLVED:
    - 段 3（検査）の骨組み: ドライバの中身は未実装で、作ろうとすると EPMLUnsupported になる。
      検査（test/test_render_vulkan.pas）が落ちることを先に確かめるため（空の実装で通ってしまう検査は何も保証しない）

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
  PaPiMeLa.Platform.Vulkan,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Render;

type
  TPMLVulkanRenderDriver = class(TPMLRenderDriver)
  public
    { ウィンドウに描く。ウィンドウは TPMLWindowOptions.Vulkan で作ってあること。 }
    constructor CreateForWindow(AWindow: TPMLWindow);
    { 面の無いオフスクリーン（AWidth x AHeight の画像）に描く。検査用。使えない環境では EPMLUnsupported。 }
    constructor CreateOffscreen(AWidth, AHeight: Integer);

    function  Name: String; override;                 // 'vulkan'
    function  GetOutputSize(out AWidth, AHeight: Integer): Boolean; override;
    function  CreateTexture(ATexture: TPMLTexture): Boolean; override;
    function  UpdateTexture(ATexture: TPMLTexture; const ARect: TPMLRect;
      APixels: Pointer; APitch: Integer): Boolean; override;
    procedure DestroyTexture(ATexture: TPMLTexture); override;
    procedure QueueGeometry(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const AVertices: array of TPMLVertex); override;
    procedure RunCommandQueue(AQueue: TPMLRenderQueue); override;
    function  ReadPixels(const ARect: TPMLRect): TPMLSurface; override;
    procedure Present; override;

    // 検査用: 選んだ物理デバイスの名前
    function  DeviceName: String;
  end;

var
  { 検査用。空でなければ、物理デバイスの名前にこの文字列を含むものを選ぶ（V3DV と lavapipe の両方で検査するため）。 }
  PMLVulkanRenderDeviceFilter: String = '';
  { 検査用。True の間、ウィンドウへ描くドライバの作成が EPMLUnsupported で失敗する。 }
  PMLVulkanRenderFailCreate: Boolean = False;

implementation

const
  NOT_IMPLEMENTED = 'PaPiMeLa.Render.Vulkan is not implemented yet';

constructor TPMLVulkanRenderDriver.CreateForWindow(AWindow: TPMLWindow);
begin
  raise EPMLUnsupported.CreateNative(NOT_IMPLEMENTED, 0, 'vulkan');
end;

constructor TPMLVulkanRenderDriver.CreateOffscreen(AWidth, AHeight: Integer);
begin
  raise EPMLUnsupported.CreateNative(NOT_IMPLEMENTED, 0, 'vulkan');
end;

function TPMLVulkanRenderDriver.Name: String;
begin
  Result := 'vulkan';
end;

function TPMLVulkanRenderDriver.GetOutputSize(out AWidth, AHeight: Integer): Boolean;
begin
  AWidth := 0;
  AHeight := 0;
  Result := False;
end;

function TPMLVulkanRenderDriver.CreateTexture(ATexture: TPMLTexture): Boolean;
begin
  Result := False;
end;

function TPMLVulkanRenderDriver.UpdateTexture(ATexture: TPMLTexture; const ARect: TPMLRect;
  APixels: Pointer; APitch: Integer): Boolean;
begin
  Result := False;
end;

procedure TPMLVulkanRenderDriver.DestroyTexture(ATexture: TPMLTexture);
begin
end;

procedure TPMLVulkanRenderDriver.QueueGeometry(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const AVertices: array of TPMLVertex);
begin
end;

procedure TPMLVulkanRenderDriver.RunCommandQueue(AQueue: TPMLRenderQueue);
begin
end;

function TPMLVulkanRenderDriver.ReadPixels(const ARect: TPMLRect): TPMLSurface;
begin
  Result := nil;
end;

procedure TPMLVulkanRenderDriver.Present;
begin
end;

function TPMLVulkanRenderDriver.DeviceName: String;
begin
  Result := '';
end;

{ ---- 登録 ---- }

{ Vulkan で作ったウィンドウには、このドライバを選ぶ。SDL の render_drivers の並びでは opengl と opengles2 の後ろ
  （GL のウィンドウと Vulkan のウィンドウは別のフラグなので、同じウィンドウを取り合わない）。 }
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
