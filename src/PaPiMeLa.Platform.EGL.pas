{
  PaPiMeLa.Platform.EGL — libEGL の実行時結合

  Origin : partially ported from SDL (src/video/SDL_egl_c.h, src/video/SDL_egl.c)
           Scope: 使う EGL 関数の一覧、どれをライブラリから直接取りどれを
           eglGetProcAddress で取るかの区別、エラーコードの名前。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §9、§11 #17

  WHAT:
    EGL の型、定数（tools/genkhronos.bb が egl.h から生成）、関数ポインタと
    その読み込み（PMLEGLLoad / PMLEGLUnload）。

  WHY:
    libEGL はリンクせず dlopen する（§9）。EGL の無い環境でも papimela は
    起動でき、GL を使おうとしたときに初めて失敗する。

  RESOLVED:
    - EGL 1.4 の関数は libEGL から直接取る。1 つでも無ければ読み込み失敗
    - eglGetPlatformDisplay（EGL 1.5）と eglGetPlatformDisplayEXT は無くてもよい。
      ライブラリに無ければ eglGetProcAddress で探し、それでも無ければ nil のまま
    - 読み込みは参照カウント。PaPiMeLa.Platform.XKB と同じ形
    - 読み込み処理（implementation 部）は qwen2.5-coder が書いた

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.EGL;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.DynLib;

type
  EGLBoolean = LongWord;
  EGLint     = LongInt;
  EGLenum    = LongWord;
  EGLAttrib  = PtrInt;
  EGLDisplay = Pointer;
  EGLConfig  = Pointer;
  EGLContext = Pointer;
  EGLSurface = Pointer;
  EGLNativeDisplayType = Pointer;
  EGLNativeWindowType  = Pointer;

  PEGLint    = ^EGLint;
  PEGLConfig = ^EGLConfig;
  PEGLAttrib = ^EGLAttrib;

const
{$I generated/egl_constants.inc}

  // egl.h で EGL_CAST(...) として定義されるもの。生成器は写さない。
  EGL_DONT_CARE       = -1;
  EGL_NO_CONTEXT      = nil;
  EGL_NO_DISPLAY      = nil;
  EGL_NO_SURFACE      = nil;
  EGL_NO_CONFIG_KHR   = nil;
  EGL_DEFAULT_DISPLAY = nil;

var
  // ---- EGL 1.4。libEGL から直接取る。PMLEGLLoad が成功したら全部 nil でない
  eglGetDisplay: function(ADisplayID: EGLNativeDisplayType): EGLDisplay; cdecl = nil;
  eglInitialize: function(ADisplay: EGLDisplay; AMajor, AMinor: PEGLint): EGLBoolean; cdecl = nil;
  eglTerminate: function(ADisplay: EGLDisplay): EGLBoolean; cdecl = nil;
  eglGetProcAddress: function(AProcName: PAnsiChar): Pointer; cdecl = nil;
  eglChooseConfig: function(ADisplay: EGLDisplay; AAttribList: PEGLint;
    AConfigs: PEGLConfig; AConfigSize: EGLint; ANumConfig: PEGLint): EGLBoolean; cdecl = nil;
  eglGetConfigAttrib: function(ADisplay: EGLDisplay; AConfig: EGLConfig;
    AAttribute: EGLint; AValue: PEGLint): EGLBoolean; cdecl = nil;
  eglCreateContext: function(ADisplay: EGLDisplay; AConfig: EGLConfig;
    AShareContext: EGLContext; AAttribList: PEGLint): EGLContext; cdecl = nil;
  eglDestroyContext: function(ADisplay: EGLDisplay; AContext: EGLContext): EGLBoolean; cdecl = nil;
  eglCreateWindowSurface: function(ADisplay: EGLDisplay; AConfig: EGLConfig;
    AWindow: EGLNativeWindowType; AAttribList: PEGLint): EGLSurface; cdecl = nil;
  eglCreatePbufferSurface: function(ADisplay: EGLDisplay; AConfig: EGLConfig;
    AAttribList: PEGLint): EGLSurface; cdecl = nil;
  eglDestroySurface: function(ADisplay: EGLDisplay; ASurface: EGLSurface): EGLBoolean; cdecl = nil;
  eglMakeCurrent: function(ADisplay: EGLDisplay; ADraw, ARead: EGLSurface;
    AContext: EGLContext): EGLBoolean; cdecl = nil;
  eglSwapBuffers: function(ADisplay: EGLDisplay; ASurface: EGLSurface): EGLBoolean; cdecl = nil;
  eglSwapInterval: function(ADisplay: EGLDisplay; AInterval: EGLint): EGLBoolean; cdecl = nil;
  eglQueryString: function(ADisplay: EGLDisplay; AName: EGLint): PAnsiChar; cdecl = nil;
  eglQuerySurface: function(ADisplay: EGLDisplay; ASurface: EGLSurface;
    AAttribute: EGLint; AValue: PEGLint): EGLBoolean; cdecl = nil;
  eglBindAPI: function(AApi: EGLenum): EGLBoolean; cdecl = nil;
  eglGetError: function: EGLint; cdecl = nil;
  eglGetCurrentContext: function: EGLContext; cdecl = nil;

  // ---- 無くてもよいもの。無ければ nil
  eglGetPlatformDisplay: function(APlatform: EGLenum; ANativeDisplay: Pointer;
    AAttribList: PEGLAttrib): EGLDisplay; cdecl = nil;
  eglGetPlatformDisplayEXT: function(APlatform: EGLenum; ANativeDisplay: Pointer;
    AAttribList: PEGLint): EGLDisplay; cdecl = nil;

{ libEGL を読み込む。既に読み込んでいれば参照カウントを増やすだけ。
  ライブラリが無いか、EGL 1.4 の関数が 1 つでも無ければ False（何も残さない）。 }
function  PMLEGLLoad: Boolean;
procedure PMLEGLUnload;
function  PMLEGLLoaded: Boolean;

{ EGL のエラーコードの名前（'EGL_BAD_MATCH' など）。知らない値なら '0x' + 16 進。 }
function  PMLEGLErrorName(ACode: EGLint): String;

implementation

// 以下は qwen2.5-coder が書いた。仕様どおりで、そのまま採用した。

const
  LIBEGL_NAMES: array[0..1] of String = ('libEGL.so.1', 'libEGL.so');

var
  GLib: TPMLDynLib = nil;
  GRefCount: Integer = 0;

procedure Bind(out ATarget; const ASymbol: String);
begin
  Pointer(ATarget) := GLib.Resolve(ASymbol);
end;

procedure ClearAll;
begin
  eglGetDisplay := nil;
  eglInitialize := nil;
  eglTerminate := nil;
  eglGetProcAddress := nil;
  eglChooseConfig := nil;
  eglGetConfigAttrib := nil;
  eglCreateContext := nil;
  eglDestroyContext := nil;
  eglCreateWindowSurface := nil;
  eglCreatePbufferSurface := nil;
  eglDestroySurface := nil;
  eglMakeCurrent := nil;
  eglSwapBuffers := nil;
  eglSwapInterval := nil;
  eglQueryString := nil;
  eglQuerySurface := nil;
  eglBindAPI := nil;
  eglGetError := nil;
  eglGetCurrentContext := nil;
  eglGetPlatformDisplay := nil;
  eglGetPlatformDisplayEXT := nil;
end;

function PMLEGLLoad: Boolean;
begin
  if GRefCount > 0 then
  begin
    Inc(GRefCount);
    Exit(True);
  end;
  try
    GLib := TPMLDynLib.Create(LIBEGL_NAMES);
  except
    on E: EPMLPlatformLibrary do
    begin
      GLib := nil;
      Exit(False);
    end;
  end;

  try
    Bind(eglGetDisplay, 'eglGetDisplay');
    Bind(eglInitialize, 'eglInitialize');
    Bind(eglTerminate, 'eglTerminate');
    Bind(eglGetProcAddress, 'eglGetProcAddress');
    Bind(eglChooseConfig, 'eglChooseConfig');
    Bind(eglGetConfigAttrib, 'eglGetConfigAttrib');
    Bind(eglCreateContext, 'eglCreateContext');
    Bind(eglDestroyContext, 'eglDestroyContext');
    Bind(eglCreateWindowSurface, 'eglCreateWindowSurface');
    Bind(eglCreatePbufferSurface, 'eglCreatePbufferSurface');
    Bind(eglDestroySurface, 'eglDestroySurface');
    Bind(eglMakeCurrent, 'eglMakeCurrent');
    Bind(eglSwapBuffers, 'eglSwapBuffers');
    Bind(eglSwapInterval, 'eglSwapInterval');
    Bind(eglQueryString, 'eglQueryString');
    Bind(eglQuerySurface, 'eglQuerySurface');
    Bind(eglBindAPI, 'eglBindAPI');
    Bind(eglGetError, 'eglGetError');
    Bind(eglGetCurrentContext, 'eglGetCurrentContext');
  except
    on E: EPMLPlatformLibrary do
    begin
      ClearAll;
      FreeAndNil(GLib);
      Exit(False);
    end;
  end;

  Pointer(eglGetPlatformDisplay) := GLib.TryResolve('eglGetPlatformDisplay');
  if eglGetPlatformDisplay = nil then
    Pointer(eglGetPlatformDisplay) := eglGetProcAddress('eglGetPlatformDisplay');

  Pointer(eglGetPlatformDisplayEXT) := GLib.TryResolve('eglGetPlatformDisplayEXT');
  if eglGetPlatformDisplayEXT = nil then
    Pointer(eglGetPlatformDisplayEXT) := eglGetProcAddress('eglGetPlatformDisplayEXT');

  GRefCount := 1;
  Result := True;
end;

procedure PMLEGLUnload;
begin
  if GRefCount = 0 then
    Exit;
  Dec(GRefCount);
  if GRefCount > 0 then
    Exit;
  ClearAll;
  FreeAndNil(GLib);
end;

function PMLEGLLoaded: Boolean;
begin
  Result := GRefCount > 0;
end;

function PMLEGLErrorName(ACode: EGLint): String;
begin
  case ACode of
    EGL_SUCCESS: Result := 'EGL_SUCCESS';
    EGL_NOT_INITIALIZED: Result := 'EGL_NOT_INITIALIZED';
    EGL_BAD_ACCESS: Result := 'EGL_BAD_ACCESS';
    EGL_BAD_ALLOC: Result := 'EGL_BAD_ALLOC';
    EGL_BAD_ATTRIBUTE: Result := 'EGL_BAD_ATTRIBUTE';
    EGL_BAD_CONTEXT: Result := 'EGL_BAD_CONTEXT';
    EGL_BAD_CONFIG: Result := 'EGL_BAD_CONFIG';
    EGL_BAD_CURRENT_SURFACE: Result := 'EGL_BAD_CURRENT_SURFACE';
    EGL_BAD_DISPLAY: Result := 'EGL_BAD_DISPLAY';
    EGL_BAD_SURFACE: Result := 'EGL_BAD_SURFACE';
    EGL_BAD_MATCH: Result := 'EGL_BAD_MATCH';
    EGL_BAD_PARAMETER: Result := 'EGL_BAD_PARAMETER';
    EGL_BAD_NATIVE_PIXMAP: Result := 'EGL_BAD_NATIVE_PIXMAP';
    EGL_BAD_NATIVE_WINDOW: Result := 'EGL_BAD_NATIVE_WINDOW';
    EGL_CONTEXT_LOST: Result := 'EGL_CONTEXT_LOST';
  else
    Result := '0x' + LowerCase(IntToHex(ACode, 1));
  end;
end;


end.
