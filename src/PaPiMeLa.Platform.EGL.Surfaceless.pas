{
  PaPiMeLa.Platform.EGL.Surfaceless — 窓の無い EGL ディスプレイ（EGL_MESA_platform_surfaceless）の共有

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §11 #43、#44

  WHAT:
    オフスクリーンの GL（窓の無いコンテキスト。GLES2 と GL のレンダラドライバが使う）のための、
    EGL ディスプレイを 1 つ借りる・返す手続き。最初の 1 人が eglInitialize し、最後の 1 人が返すときに
    eglTerminate する。

  WHY:
    Mesa は同じプラットフォームなら、何度 eglGetPlatformDisplay を呼んでも同じ EGLDisplay を返す。
    eglTerminate は参照を数えないので、ドライバごとに初期化と終了をすると、先に消えたドライバが
    ほかのドライバのコンテキストを巻き添えにする（実測: EGL_BAD_DISPLAY）。GLES2 と GL の両方が
    同じ手続きを通るよう、数えるところを 1 つにした。

  RESOLVED:
    - 数えるのは大域の 1 つ（プロセスに 1 つ）。スレッド安全にはしない（レンダラはメインスレッドから使う）
    - 足りないもの（クライアント拡張 EGL_MESA_platform_surfaceless、ディスプレイ拡張
      EGL_KHR_surfaceless_context、eglInitialize）は EPMLUnsupported で、何が足りないかを文面にする

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.EGL.Surfaceless;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.EGL;

{ 空白区切りの拡張名の一覧に AExt が語として含まれるか。 }
const
  // eglGetPlatformDisplay のプラットフォーム（EGL_MESA_platform_surfaceless）。Mesa だけが持つ
  EGL_PLATFORM_SURFACELESS_MESA = $31DD;

function PMLEGLHasExtension(const AList, AExt: String): Boolean;

{ surfaceless のディスプレイを 1 つ借りる。最初の 1 人が初期化する。AWhat は文面の頭（'offscreen GLES2' など）。 }
function PMLAcquireSurfacelessDisplay(const AWhat: String): EGLDisplay;

{ 借りたディスプレイを返す。最後の 1 人が返すときに eglTerminate する。 }
procedure PMLReleaseSurfacelessDisplay;

implementation

var
  GSurfacelessDisplay: EGLDisplay = nil;
  GSurfacelessRefs: Integer = 0;

function PMLEGLHasExtension(const AList, AExt: String): Boolean;
begin
  Result := Pos(' ' + AExt + ' ', ' ' + AList + ' ') > 0;
end;

function PMLAcquireSurfacelessDisplay(const AWhat: String): EGLDisplay;
var
  Ext: PAnsiChar;
  Display: EGLDisplay;
  Major, Minor, Err: EGLint;
begin
  if GSurfacelessRefs > 0 then
  begin
    Inc(GSurfacelessRefs);
    Exit(GSurfacelessDisplay);
  end;

  Ext := eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
  if (Ext = nil) or not PMLEGLHasExtension(String(Ext), 'EGL_MESA_platform_surfaceless') then
    raise EPMLUnsupported.Create(
      AWhat + ': the client extension EGL_MESA_platform_surfaceless is missing');

  Display := EGL_NO_DISPLAY;
  if Assigned(eglGetPlatformDisplayEXT) then
    Display := eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, nil, nil);
  if (Display = EGL_NO_DISPLAY) and Assigned(eglGetPlatformDisplay) then
    Display := eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, nil, nil);
  if Display = EGL_NO_DISPLAY then
    raise EPMLUnsupported.Create(
      AWhat + ': could not get an EGL display for the surfaceless platform');

  Major := 0;
  Minor := 0;
  if eglInitialize(Display, @Major, @Minor) = EGL_FALSE then
  begin
    Err := eglGetError();
    raise EPMLUnsupported.CreateFmt('%s: eglInitialize failed (%s)', [AWhat, PMLEGLErrorName(Err)]);
  end;

  Ext := eglQueryString(Display, EGL_EXTENSIONS);
  if (Ext = nil) or not PMLEGLHasExtension(String(Ext), 'EGL_KHR_surfaceless_context') then
  begin
    eglTerminate(Display);
    raise EPMLUnsupported.Create(
      AWhat + ': the display extension EGL_KHR_surfaceless_context is missing');
  end;

  GSurfacelessDisplay := Display;
  GSurfacelessRefs := 1;
  Result := Display;
end;

procedure PMLReleaseSurfacelessDisplay;
begin
  if GSurfacelessRefs = 0 then
    Exit;
  Dec(GSurfacelessRefs);
  if GSurfacelessRefs = 0 then
  begin
    eglTerminate(GSurfacelessDisplay);
    GSurfacelessDisplay := EGL_NO_DISPLAY;
  end;
end;

end.
