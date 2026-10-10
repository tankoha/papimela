{
  PaPiMeLa.Video.EGL — EGL による GL 部品の共通実装

  Origin : ported from SDL (src/video/SDL_egl.c)
           Scope: SDL_EGL_HasExtension、SDL_EGL_GetProcAddressInternal、
           SDL_EGL_LoadLibrary（ディスプレイの取得と初期化）、
           SDL_EGL_PrivateChooseConfig / SDL_EGL_ChooseConfig（コンフィグの
           選別と、EGL_CONFIG_CAVEAT を付けた試行と付けない試行）、
           SDL_EGL_CreateContext、SDL_EGL_MakeCurrent、SDL_EGL_SetSwapInterval、
           SDL_EGL_SwapBuffers、SDL_EGL_DestroyContext、SDL_EGL_CreateSurface、
           SDL_EGL_DestroySurface。
           移植しないもの: オフスクリーン（pbuffer / デバイス列挙）、ヒントと
           コールバックによる属性の差し込み、Android / QNX / Vita の分岐、
           サーフェス無しの MakeCurrent（gl_allow_no_surface）、
           マルチサンプルと浮動小数点バッファ、sRGB 属性、共有コンテキスト。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.4、§9、§11 #33

  WHAT:
    プラットフォームに依らない EGL の処理。ライブラリの読み込み、ディスプレイの
    取得と初期化、ウィンドウごとの描画面（EGLSurface）の管理、コンテキストの
    作成と切り替え、関数の番地の取得。プラットフォーム固有の部分（ネイティブ
    ディスプレイ、ネイティブウィンドウの作成と破棄、画面へ出す手順）は抽象メソッドに
    してあり、Wayland は TPMLWaylandEGL が実装する。

  WHY:
    SDL は X11 と Wayland と KMS が同じ SDL_egl.c を使うために大域の
    gl_config と egl_data を読み書きしている。papimela は属性を値として
    受け取り、状態をこのオブジェクトのフィールドに持つ。

  RESOLVED:
    - 初期化は最初の CreateContext（または GetProcAddress）まで遅らせる。
      GL を使わないアプリは libEGL を読み込まない
    - 描画面はウィンドウ単位の記録（ネイティブウィンドウ、EGLSurface、EGLConfig）で、
      そのウィンドウへの最初の CreateContext で作る。以後の属性は変わらない
    - 例外は投げない。失敗は False / nil と FLastError で返す。メッセージの
      形は SDL_EGL_SetErrorEx と同じ（呼んだ EGL 関数とエラー名を添える）
    - GetProcAddress: 下の PORT-NOTE を参照
    - スワップ間隔はコンテキストごとに持ち、現在にするたびに描画面へ効かせる
      （SDL は全体で 1 つ。SetSwapInterval の PORT-NOTE(bug)、D-53）

  NOT RESOLVED:
    - EGL_KHR_create_context が無く、ES 2.0 より上や Core プロファイルを
      求められたら失敗する（SDL と同じ）

  PORT-NOTE: SDL_EGL_GetProcAddressInternal は EGL 1.5 以降なら eglGetProcAddress を
  先に使う。Mesa（glvnd の libEGL）は EGL_KHR_client_get_all_proc_addresses により、
  存在しない `gl*` の名前にも非 nil の代理（呼ぶと落ちる）を返す。手元で測ると
  glNoSuchFunction も glFooBarBaz も非 nil だった。そこで `gl` で始まる名前は
  先に libGLESv2 から引き（コア関数はここで確定する）、無ければ拡張関数の
  接尾辞（KHR / EXT / OES ...）を持つ名前に限って eglGetProcAddress に任せる。
  接尾辞の付いた存在しない名前は代理が返る（EGL の仕様どおり）。

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.EGL;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Platform.EGL,
  PaPiMeLa.Video.Backend;

type
  { ウィンドウ 1 枚分の描画面の記録。 }
  TPMLEGLWindowSurface = class
  public
    Window : TPMLWindowBackend;
    Native : EGLNativeWindowType;
    Surface: EGLSurface;
    Config : EGLConfig;
  end;

  { コンテキスト 1 つ分の記録。 }
  TPMLEGLContextRec = record
    Context : EGLContext;
    Interval: Integer;   // このコンテキストのスワップ間隔（D-53）
  end;

  TPMLEGLBackend = class abstract(TPMLGLBackend)
  strict private
    FLibLoaded : Boolean;
    FDisplay   : EGLDisplay;
    FVersionMajor, FVersionMinor: Integer;
    FDisplayExtensions: String;
    FGLES      : TPMLDynLib;
    FGLESTried : Boolean;
    FSurfaces  : array of TPMLEGLWindowSurface;
    FContexts  : array of TPMLEGLContextRec;
    FCurrentSurface: EGLSurface;
    FCurrentContext: EGLContext;
    FApiType   : EGLenum;
    FShutdownDone: Boolean;

    function  EnsureLoaded: Boolean;
    function  EnsureInitialized: Boolean;
    procedure ReadVersion(ADisplay: EGLDisplay);
    function  HasClientExtension(const AExt: String): Boolean;
    function  FindSurface(AWindow: TPMLWindowBackend): TPMLEGLWindowSurface;
    function  ApiFor(AProfile: TPMLGLProfile): EGLenum;
    function  ChooseConfigPass(const AAttrs: TPMLGLAttributes;
      ACaveatNone: Boolean; out AConfig: EGLConfig): Boolean;
    function  ChooseConfig(const AAttrs: TPMLGLAttributes;
      out AConfig: EGLConfig): Boolean;
    function  CreateEGLSurface(ANative: EGLNativeWindowType;
      AConfig: EGLConfig): EGLSurface;
    function  EnsureWindowSurface(AWindow: TPMLWindowBackend;
      const AAttrs: TPMLGLAttributes): TPMLEGLWindowSurface;
    function  BuildContextAttribs(const AAttrs: TPMLGLAttributes;
      var AAttribs: array of EGLint): Boolean;
    function  ReleaseCurrent: Boolean;
    function  IndexOfContext(AContext: EGLContext): Integer;
    function  GLESSymbol(const AName: String): Pointer;
  strict protected
    { 描画面の記録とコンテキストを畳み、eglTerminate してライブラリを手放す。
      何度呼んでもよい。派生クラスは、自分のフィールドを壊す前にこれを呼ぶこと
      （基底のデストラクタからでは、派生クラスの後始末が済んでいる）。 }
    procedure Shutdown;
    { SDL_EGL_SetErrorEx。AMessage に、呼んだ EGL 関数とエラー名を添えて FLastError に置く。 }
    procedure SetEGLError(const AMessage, AFunction: String);
    // 取り出し済みのエラーコードで記録する。eglGetError は読むと消えるので、
    // 一度読んだ値で判断したら、記録にもその値を使う。
    procedure SetEGLErrorCode(const AMessage, AFunction: String; ACode: EGLint);
    { 表示側の拡張（EGL_EXTENSIONS）に AExt があるか。語の完全一致。 }
    function  HasDisplayExtension(const AExt: String): Boolean;
    { AWindow の描画面。無ければ EGL_NO_SURFACE。 }
    function  SurfaceOf(AWindow: TPMLWindowBackend): EGLSurface;
    property  EGLDisplayHandle: EGLDisplay read FDisplay;
    { 現在のコンテキストのスワップ間隔。現在のものが無ければ 0。 }
    function  CurrentSwapInterval: Integer;
    { AContext の間隔を覚える。知らないコンテキストなら False。EGL には何もしない。 }
    function  StoreSwapInterval(AContext: TPMLGLContextHandle; AInterval: Integer): Boolean;
    { 現在の描画面に AInterval を効かせる。既定は eglSwapInterval（EGL の間隔は
      現在の描画面ごと）。現在にするたびと、現在のコンテキストの値を変えたときに呼ぶ。
      Wayland は待ちを自前で行うので、常に 0 を渡すよう差し替える。 }
    function  ApplySwapInterval(AInterval: Integer): Boolean; virtual;

    { ---- プラットフォーム固有（設計 §3.4） ---- }
    function  GetPlatform: EGLenum; virtual; abstract;
    function  GetNativeDisplay: Pointer; virtual; abstract;
    { 失敗したら nil。詳しい理由は FLastError に置いてよい。 }
    function  CreateNativeWindow(AWindow: TPMLWindowBackend): EGLNativeWindowType;
      virtual; abstract;
    procedure DestroyNativeWindow(AWindow: TPMLWindowBackend;
      ANative: EGLNativeWindowType); virtual; abstract;
    { 描いた面を画面へ出す。既定は eglSwapBuffers。Wayland はフレームの
      ペース取りのために差し替える。 }
    function  SwapSurface(AWindow: TPMLWindowBackend;
      ASurface: EGLSurface): Boolean; virtual;
  public
    destructor Destroy; override;

    function  GetProcAddress(const AName: String): Pointer; override;
    function  CreateContext(AWindow: TPMLWindowBackend;
      const AAttrs: TPMLGLAttributes): TPMLGLContextHandle; override;
    function  MakeCurrent(AWindow: TPMLWindowBackend;
      AContext: TPMLGLContextHandle): Boolean; override;
    procedure DestroyContext(AContext: TPMLGLContextHandle); override;
    function  SwapWindow(AWindow: TPMLWindowBackend): Boolean; override;
    function  SetSwapInterval(AContext: TPMLGLContextHandle;
      AInterval: Integer): Boolean; override;
    function  GetSwapInterval(AContext: TPMLGLContextHandle): Integer; override;
    procedure ReleaseWindow(AWindow: TPMLWindowBackend); override;
  end;

{ 空白区切りの拡張名の一覧に AExt が語として含まれるか（SDL_EGL_HasExtension の
  文字列照合の部分）。部分文字列では一致としない。 }
function PMLEGLExtensionInList(const AList, AExt: String): Boolean;

implementation

const
  GLES_NAMES: array[0..1] of String = ('libGLESv2.so.2', 'libGLESv2.so');

  // SDL_GL_CONTEXT_DEBUG_FLAG と EGL_CONTEXT_OPENGL_DEBUG_BIT_KHR は同じ値
  CONTEXT_DEBUG_FLAG = 1;

  // 拡張関数の接尾辞。この一覧に無い `gl` の名前は、libGLESv2 に無ければ無い
  // ものとして扱う（PORT-NOTE 参照）。
  VendorSuffixes: array[0..27] of String = (
    'KHR', 'EXT', 'OES', 'ARB', 'NV', 'NVX', 'AMD', 'ANGLE', 'APPLE', 'ARM',
    'IMG', 'INTEL', 'MESA', 'QCOM', 'OVR', 'SGIS', 'SGIX', 'SUN', 'ATI', 'DMP',
    'FJ', 'VIV', 'PVR', 'SEC', 'OML', 'HP', 'IBM', 'ANDROID');

function PMLEGLExtensionInList(const AList, AExt: String): Boolean;
begin
  // 語の完全一致。両端に空白を足して、部分文字列の一致（EGL_KHR_foo が
  // EGL_KHR_foo_bar に当たる）を避ける。
  if (AExt = '') or (Pos(' ', AExt) > 0) then
    Exit(False);
  Result := Pos(' ' + AExt + ' ', ' ' + AList + ' ') > 0;
end;

function HasVendorSuffix(const AName: String): Boolean;
var
  I, L: Integer;
  S: String;
begin
  for I := Low(VendorSuffixes) to High(VendorSuffixes) do
  begin
    S := VendorSuffixes[I];
    L := Length(AName);
    // 接尾辞の直前は小文字か数字（glFooNV の o）。大文字なら単語の一部
    if (L > Length(S) + 2) and (Copy(AName, L - Length(S) + 1, Length(S)) = S)
      and (AName[L - Length(S)] in ['a'..'z', '0'..'9']) then
      Exit(True);
  end;
  Result := False;
end;

{ TPMLEGLBackend }

destructor TPMLEGLBackend.Destroy;
begin
  Shutdown;
  inherited Destroy;
end;

procedure TPMLEGLBackend.Shutdown;
var
  I: Integer;
begin
  if FShutdownDone then
    Exit;
  FShutdownDone := True;
  if FLibLoaded and (FDisplay <> EGL_NO_DISPLAY) then
  begin
    ReleaseCurrent;
    for I := High(FContexts) downto 0 do
      eglDestroyContext(FDisplay, FContexts[I].Context);
    SetLength(FContexts, 0);
    for I := High(FSurfaces) downto 0 do
    begin
      eglDestroySurface(FDisplay, FSurfaces[I].Surface);
      DestroyNativeWindow(FSurfaces[I].Window, FSurfaces[I].Native);
      FSurfaces[I].Free;
    end;
    SetLength(FSurfaces, 0);
    eglTerminate(FDisplay);
    FDisplay := EGL_NO_DISPLAY;
  end;
  FreeAndNil(FGLES);
  if FLibLoaded then
  begin
    PMLEGLUnload;
    FLibLoaded := False;
  end;
end;

procedure TPMLEGLBackend.SetEGLError(const AMessage, AFunction: String);
begin
  SetEGLErrorCode(AMessage, AFunction, eglGetError());
end;

procedure TPMLEGLBackend.SetEGLErrorCode(const AMessage, AFunction: String; ACode: EGLint);
begin
  FLastError := Format('%s (call to %s failed, reporting an error of %s)',
    [AMessage, AFunction, PMLEGLErrorName(ACode)]);
end;

function TPMLEGLBackend.HasDisplayExtension(const AExt: String): Boolean;
begin
  Result := PMLEGLExtensionInList(FDisplayExtensions, AExt);
end;

function TPMLEGLBackend.HasClientExtension(const AExt: String): Boolean;
var
  P: PAnsiChar;
begin
  // EGL_EXT_client_extensions: ディスプレイ無しで EGL_EXTENSIONS を引くと
  // クライアント拡張が返る（EGL 1.5 では標準）。実装が対応しなければ nil。
  P := eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
  if P = nil then
    Exit(False);
  Result := PMLEGLExtensionInList(String(P), AExt);
end;

function TPMLEGLBackend.SurfaceOf(AWindow: TPMLWindowBackend): EGLSurface;
var
  R: TPMLEGLWindowSurface;
begin
  R := FindSurface(AWindow);
  if R = nil then
    Result := EGL_NO_SURFACE
  else
    Result := R.Surface;
end;

function TPMLEGLBackend.FindSurface(AWindow: TPMLWindowBackend): TPMLEGLWindowSurface;
var
  I: Integer;
begin
  for I := 0 to High(FSurfaces) do
    if FSurfaces[I].Window = AWindow then
      Exit(FSurfaces[I]);
  Result := nil;
end;

function TPMLEGLBackend.EnsureLoaded: Boolean;
begin
  if FLibLoaded then
    Exit(True);
  if not PMLEGLLoad then
  begin
    FLastError := 'could not load libEGL';
    Exit(False);
  end;
  FLibLoaded := True;
  FShutdownDone := False;
  Result := True;
end;

{ EGL_VERSION の文字列（'1.5 Mesa ...'）から版を読む。 }
procedure TPMLEGLBackend.ReadVersion(ADisplay: EGLDisplay);
var
  P: PAnsiChar;
  S: String;
  Dot, I: Integer;
  Major, Minor: Integer;
begin
  P := eglQueryString(ADisplay, EGL_VERSION);
  if P = nil then
    Exit;
  S := String(P);
  Dot := Pos('.', S);
  if Dot < 2 then
    Exit;
  Major := StrToIntDef(Copy(S, 1, Dot - 1), -1);
  I := Dot + 1;
  while (I <= Length(S)) and (S[I] in ['0'..'9']) do
    Inc(I);
  Minor := StrToIntDef(Copy(S, Dot + 1, I - Dot - 1), -1);
  if (Major >= 0) and (Minor >= 0) then
  begin
    FVersionMajor := Major;
    FVersionMinor := Minor;
  end;
end;

{ SDL_EGL_LoadLibrary のうち、ディスプレイを得て初期化するところ。 }
function TPMLEGLBackend.EnsureInitialized: Boolean;
var
  Native: Pointer;
  PlatformID: EGLenum;
begin
  if FDisplay <> EGL_NO_DISPLAY then
    Exit(True);
  if not EnsureLoaded then
    Exit(False);

  Native := GetNativeDisplay;
  PlatformID := GetPlatform;
  FDisplay := EGL_NO_DISPLAY;

  // EGL 1.5 ならクライアントの版をディスプレイ無しで引ける
  ReadVersion(EGL_NO_DISPLAY);
  if PlatformID <> 0 then
  begin
    if Assigned(eglGetPlatformDisplay)
      and ((FVersionMajor > 1) or ((FVersionMajor = 1) and (FVersionMinor >= 5))) then
      FDisplay := eglGetPlatformDisplay(PlatformID, Native, nil)
    else if Assigned(eglGetPlatformDisplayEXT)
      and HasClientExtension('EGL_EXT_platform_base') then
      FDisplay := eglGetPlatformDisplayEXT(PlatformID, Native, nil);
  end;
  // eglGetPlatformDisplay が失敗しても、実装固有の eglGetDisplay を試す
  if FDisplay = EGL_NO_DISPLAY then
    FDisplay := eglGetDisplay(Native);
  if FDisplay = EGL_NO_DISPLAY then
  begin
    FLastError := 'Could not get EGL display';
    Exit(False);
  end;

  if eglInitialize(FDisplay, nil, nil) = EGL_FALSE then
  begin
    SetEGLError('Could not initialize EGL', 'eglInitialize');
    FDisplay := EGL_NO_DISPLAY;
    Exit(False);
  end;

  // EGL 1.4 以前は、ディスプレイを初期化してからでないと版が引けない
  ReadVersion(FDisplay);
  FDisplayExtensions := '';
  if eglQueryString(FDisplay, EGL_EXTENSIONS) <> nil then
    FDisplayExtensions := String(eglQueryString(FDisplay, EGL_EXTENSIONS));
  Result := True;
end;

function TPMLEGLBackend.ApiFor(AProfile: TPMLGLProfile): EGLenum;
begin
  if AProfile = TPMLGLProfile.ES then
    Result := EGL_OPENGL_ES_API
  else
    Result := EGL_OPENGL_API;
end;

{ SDL_EGL_PrivateChooseConfig。eglChooseConfig は「要求以上」の候補を返すので、
  そこから要求との差（ビット数の超過）が最小のものを選ぶ。 }
function TPMLEGLBackend.ChooseConfigPass(const AAttrs: TPMLGLAttributes;
  ACaveatNone: Boolean; out AConfig: EGLConfig): Boolean;
var
  Attribs: array[0..63] of EGLint;
  N: Integer;
  Configs: array[0..127] of EGLConfig;
  Found, Value: EGLint;
  I, J, BitDiff, BestBitDiff, BestTrueDiff, TrueIdx: Integer;
  IsTrue: Boolean;

  procedure Add(AKey, AValue: EGLint);
  begin
    Attribs[N] := AKey;
    Attribs[N + 1] := AValue;
    Inc(N, 2);
  end;

begin
  AConfig := nil;
  N := 0;
  Add(EGL_RED_SIZE, AAttrs.RedSize);
  Add(EGL_GREEN_SIZE, AAttrs.GreenSize);
  Add(EGL_BLUE_SIZE, AAttrs.BlueSize);
  if ACaveatNone then
    Add(EGL_CONFIG_CAVEAT, EGL_NONE);
  if AAttrs.AlphaSize <> 0 then
    Add(EGL_ALPHA_SIZE, AAttrs.AlphaSize);
  if AAttrs.DepthSize <> 0 then
    Add(EGL_DEPTH_SIZE, AAttrs.DepthSize);
  if AAttrs.StencilSize <> 0 then
    Add(EGL_STENCIL_SIZE, AAttrs.StencilSize);

  if AAttrs.Profile = TPMLGLProfile.ES then
  begin
    if (AAttrs.MajorVersion >= 3)
      and (HasDisplayExtension('EGL_KHR_create_context')
        or (FVersionMajor > 1) or ((FVersionMajor = 1) and (FVersionMinor >= 5))) then
      Add(EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT_KHR)
    else if AAttrs.MajorVersion >= 2 then
      Add(EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT)
    else
      Add(EGL_RENDERABLE_TYPE, EGL_OPENGL_ES_BIT);
  end
  else
    Add(EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT);
  eglBindAPI(ApiFor(AAttrs.Profile));

  Add(EGL_SURFACE_TYPE, EGL_WINDOW_BIT);
  Attribs[N] := EGL_NONE;

  Found := 0;
  if (eglChooseConfig(FDisplay, @Attribs[0], @Configs[0], Length(Configs),
    @Found) = EGL_FALSE) or (Found = 0) then
    Exit(False);

  BestBitDiff := -1;
  BestTrueDiff := -1;
  TrueIdx := -1;
  for I := 0 to Found - 1 do
  begin
    IsTrue := False;
    BitDiff := 0;

    if (eglGetConfigAttrib(FDisplay, Configs[I], EGL_RED_SIZE, @Value) <> EGL_FALSE)
      and (Value = 8)
      and (eglGetConfigAttrib(FDisplay, Configs[I], EGL_GREEN_SIZE, @Value) <> EGL_FALSE)
      and (Value = 8)
      and (eglGetConfigAttrib(FDisplay, Configs[I], EGL_BLUE_SIZE, @Value) <> EGL_FALSE)
      and (Value = 8) then
      IsTrue := True;

    J := 0;
    while J < N do
    begin
      if (Attribs[J + 1] <> EGL_DONT_CARE)
        and ((Attribs[J] = EGL_RED_SIZE) or (Attribs[J] = EGL_GREEN_SIZE)
          or (Attribs[J] = EGL_BLUE_SIZE) or (Attribs[J] = EGL_ALPHA_SIZE)
          or (Attribs[J] = EGL_DEPTH_SIZE) or (Attribs[J] = EGL_STENCIL_SIZE)) then
      begin
        eglGetConfigAttrib(FDisplay, Configs[I], Attribs[J], @Value);
        BitDiff := BitDiff + (Value - Attribs[J + 1]);   // 値は常に要求以上
      end;
      Inc(J, 2);
    end;

    if (BestBitDiff = -1) or (BitDiff < BestBitDiff) then
    begin
      AConfig := Configs[I];
      BestBitDiff := BitDiff;
    end;
    if IsTrue and ((BestTrueDiff = -1) or (BitDiff < BestTrueDiff)) then
    begin
      TrueIdx := I;
      BestTrueDiff := BitDiff;
    end;
  end;

  // 16 ビット以下の色を求められても、8:8:8 の候補があればそちらを選ぶ。
  // 低い深さを「どうせ大きいのが来る」と仮定して頼むアプリで、
  // ディザのかかった画面になるのを避けるための SDL の方針（FAVOR_TRUECOLOR）。
  if ((AAttrs.RedSize + AAttrs.GreenSize + AAttrs.BlueSize) <= 16) and (TrueIdx <> -1) then
    AConfig := Configs[TrueIdx];
  Result := True;
end;

{ SDL_EGL_ChooseConfig。まず遅い / 不適合の候補（CONFIG_CAVEAT）を除いて探し、
  無ければそれも含めて探す。 }
function TPMLEGLBackend.ChooseConfig(const AAttrs: TPMLGLAttributes;
  out AConfig: EGLConfig): Boolean;
begin
  if ChooseConfigPass(AAttrs, True, AConfig) then
    Exit(True);
  if ChooseConfigPass(AAttrs, False, AConfig) then
    Exit(True);
  SetEGLError('Couldn''t find matching EGL config', 'eglChooseConfig');
  Result := False;
end;

{ SDL_EGL_CreateSurface のうち papimela に関わる部分。

  PORT-NOTE: papimela のウィンドウは透過にならない（TPMLWindowFlag.Transparent
  の対応は未実装）ので、EGL_PRESENT_OPAQUE_EXT は拡張があれば常に EGL_TRUE。
  Nvidia のドライバは拡張を名乗りながら EGL_BAD_ATTRIBUTE を返すことがあるため、
  その場合は属性を外してもう一度試す（SDL と同じ）。

  PORT-NOTE(bug): SDL は再試行の判定で eglGetError を読み、失敗の記録でもう一度
  読む。eglGetError は読むと EGL_SUCCESS に戻るので、EGL_BAD_ATTRIBUTE 以外で
  失敗すると「EGL_SUCCESS で失敗した」と記録される（D-38）。ここでは一度だけ読む。 }
function TPMLEGLBackend.CreateEGLSurface(ANative: EGLNativeWindowType;
  AConfig: EGLConfig): EGLSurface;
var
  Attribs: array[0..3] of EGLint;
  Err: EGLint;
begin
  Attribs[0] := EGL_NONE;
  if HasDisplayExtension('EGL_EXT_present_opaque') then
  begin
    Attribs[0] := EGL_PRESENT_OPAQUE_EXT;
    Attribs[1] := EGL_TRUE;
    Attribs[2] := EGL_NONE;
  end;
  Result := eglCreateWindowSurface(FDisplay, AConfig, ANative, @Attribs[0]);
  if Result = EGL_NO_SURFACE then
  begin
    Err := eglGetError();
    if (Attribs[0] = EGL_PRESENT_OPAQUE_EXT) and (Err = EGL_BAD_ATTRIBUTE) then
    begin
      Attribs[0] := EGL_NONE;
      Result := eglCreateWindowSurface(FDisplay, AConfig, ANative, @Attribs[0]);
      if Result = EGL_NO_SURFACE then
        Err := eglGetError();
    end;
    if Result = EGL_NO_SURFACE then
      SetEGLErrorCode('unable to create an EGL window surface', 'eglCreateWindowSurface', Err);
  end;
end;

function TPMLEGLBackend.EnsureWindowSurface(AWindow: TPMLWindowBackend;
  const AAttrs: TPMLGLAttributes): TPMLEGLWindowSurface;
var
  Config: EGLConfig;
  Native: EGLNativeWindowType;
  Surf: EGLSurface;
begin
  Result := FindSurface(AWindow);
  if Result <> nil then
    Exit;
  if not ChooseConfig(AAttrs, Config) then
    Exit(nil);
  Native := CreateNativeWindow(AWindow);
  if Native = nil then
  begin
    if FLastError = '' then
      FLastError := 'could not create the native window for EGL';
    Exit(nil);
  end;
  Surf := CreateEGLSurface(Native, Config);
  if Surf = EGL_NO_SURFACE then
  begin
    DestroyNativeWindow(AWindow, Native);
    Exit(nil);
  end;
  Result := TPMLEGLWindowSurface.Create;
  Result.Window := AWindow;
  Result.Native := Native;
  Result.Surface := Surf;
  Result.Config := Config;
  SetLength(FSurfaces, Length(FSurfaces) + 1);
  FSurfaces[High(FSurfaces)] := Result;
end;

{ SDL_EGL_CreateContext の属性を組む部分。AAttribs の末尾は EGL_NONE。
  作れない組み合わせなら False（FLastError を置く）。 }
function TPMLEGLBackend.BuildContextAttribs(const AAttrs: TPMLGLAttributes;
  var AAttribs: array of EGLint): Boolean;
var
  N: Integer;
  ProfileEs: Boolean;
  Flags, Major, Minor: EGLint;

  procedure Add(AKey, AValue: EGLint);
  begin
    AAttribs[N] := AKey;
    AAttribs[N + 1] := AValue;
    Inc(N, 2);
  end;

begin
  N := 0;
  ProfileEs := AAttrs.Profile = TPMLGLProfile.ES;
  Major := AAttrs.MajorVersion;
  Minor := AAttrs.MinorVersion;
  Flags := 0;
  if AAttrs.Debug then
    Flags := CONTEXT_DEBUG_FLAG;

  if ((Major < 3) or ((Minor = 0) and ProfileEs)) and (Flags = 0) and ProfileEs then
  begin
    // EGL_KHR_create_context 無しで作る。ES では主版だけ指定できる。
    // SDL はデスクトップ GL の 3.0 未満もここで作る（プロファイル未指定のとき）が、
    // papimela の Core / Compatibility は必ずプロファイルを持つので、ここへは来ない。
    if Major < 1 then
      Add(EGL_CONTEXT_CLIENT_VERSION, 1)
    else
      Add(EGL_CONTEXT_CLIENT_VERSION, Major);
  end
  else
  begin
    // 版・プロファイル・フラグは EGL_KHR_create_context（EGL 1.5 では標準）が要る。
    if not (HasDisplayExtension('EGL_KHR_create_context')
      or (FVersionMajor > 1) or ((FVersionMajor = 1) and (FVersionMinor >= 5))) then
    begin
      FLastError := 'Could not create EGL context (context attributes are not supported)';
      Exit(False);
    end;
    Add(EGL_CONTEXT_MAJOR_VERSION_KHR, Major);
    Add(EGL_CONTEXT_MINOR_VERSION_KHR, Minor);
    // SDL のプロファイルのビットは EGL のビットと同じ値
    if AAttrs.Profile = TPMLGLProfile.Core then
      Add(EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR)
    else if AAttrs.Profile = TPMLGLProfile.Compatibility then
      Add(EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR, EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT_KHR);
    if Flags <> 0 then
      Add(EGL_CONTEXT_FLAGS_KHR, Flags);
  end;
  AAttribs[N] := EGL_NONE;
  Result := True;
end;

function TPMLEGLBackend.ReleaseCurrent: Boolean;
begin
  Result := True;
  if FDisplay = EGL_NO_DISPLAY then
    Exit;
  Result := eglMakeCurrent(FDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE,
    EGL_NO_CONTEXT) <> EGL_FALSE;
  FCurrentSurface := EGL_NO_SURFACE;
  FCurrentContext := EGL_NO_CONTEXT;
end;

function TPMLEGLBackend.IndexOfContext(AContext: EGLContext): Integer;
begin
  for Result := 0 to High(FContexts) do
    if FContexts[Result].Context = AContext then
      Exit;
  Result := -1;
end;

function TPMLEGLBackend.CreateContext(AWindow: TPMLWindowBackend;
  const AAttrs: TPMLGLAttributes): TPMLGLContextHandle;
var
  Rec: TPMLEGLWindowSurface;
  Attribs: array[0..32] of EGLint;
  Ctx: EGLContext;
begin
  Result := nil;
  FLastError := '';
  FillChar(Attribs, SizeOf(Attribs), 0);
  if not EnsureInitialized then
    Exit;
  Rec := EnsureWindowSurface(AWindow, AAttrs);
  if Rec = nil then
    Exit;
  if not BuildContextAttribs(AAttrs, Attribs) then
    Exit;

  FApiType := ApiFor(AAttrs.Profile);
  if eglBindAPI(FApiType) = EGL_FALSE then
  begin
    SetEGLError('Could not bind EGL API', 'eglBindAPI');
    Exit;
  end;
  Ctx := eglCreateContext(FDisplay, Rec.Config, EGL_NO_CONTEXT, @Attribs[0]);
  if Ctx = EGL_NO_CONTEXT then
  begin
    SetEGLError('Could not create EGL context', 'eglCreateContext');
    Exit;
  end;
  // EGL の既定は 1 だが、SDL の方針は「既定で VSync 無し」。MakeCurrent が
  // この 0 を描画面に効かせる。
  SetLength(FContexts, Length(FContexts) + 1);
  FContexts[High(FContexts)].Context := Ctx;
  FContexts[High(FContexts)].Interval := 0;
  if not MakeCurrent(AWindow, Ctx) then
  begin
    DestroyContext(Ctx);
    Exit;
  end;
  Result := Ctx;
end;

function TPMLEGLBackend.MakeCurrent(AWindow: TPMLWindowBackend;
  AContext: TPMLGLContextHandle): Boolean;
var
  Surf: EGLSurface;
begin
  FLastError := '';
  if FDisplay = EGL_NO_DISPLAY then
  begin
    // 何も作っていないうちの解放は、することが無いので成功
    if (AWindow = nil) and (AContext = nil) then
      Exit(True);
    FLastError := 'EGL not initialized';
    Exit(False);
  end;

  // このスレッドに正しい API が結び付いているようにする
  if FApiType <> 0 then
    eglBindAPI(FApiType);

  if (AWindow = nil) or (AContext = nil) then
    Exit(ReleaseCurrent);

  Surf := SurfaceOf(AWindow);
  if Surf = EGL_NO_SURFACE then
  begin
    FLastError := 'the window has no EGL surface';
    Exit(False);
  end;
  if eglMakeCurrent(FDisplay, Surf, Surf, AContext) = EGL_FALSE then
  begin
    SetEGLError('Unable to make EGL context current', 'eglMakeCurrent');
    Exit(False);
  end;
  FCurrentSurface := Surf;
  FCurrentContext := AContext;
  // EGL の間隔は描画面ごとなので、現在にするたびにこのコンテキストの値を効かせる。
  // 効かなくても現在にはなっているので、失敗は返さない（SDL も読み捨てている）
  ApplySwapInterval(CurrentSwapInterval);
  Result := True;
end;

procedure TPMLEGLBackend.DestroyContext(AContext: TPMLGLContextHandle);
var
  I: Integer;
begin
  if (AContext = nil) or (FDisplay = EGL_NO_DISPLAY) then
    Exit;
  // 現在のコンテキストは、先に外してから壊す（壊した後も使われ続けないように）
  if (eglGetCurrentContext() = AContext) or (FCurrentContext = AContext) then
    ReleaseCurrent;
  eglDestroyContext(FDisplay, AContext);
  I := IndexOfContext(AContext);
  if I >= 0 then
  begin
    FContexts[I] := FContexts[High(FContexts)];
    SetLength(FContexts, Length(FContexts) - 1);
  end;
end;

function TPMLEGLBackend.SwapSurface(AWindow: TPMLWindowBackend;
  ASurface: EGLSurface): Boolean;
begin
  if eglSwapBuffers(FDisplay, ASurface) = EGL_FALSE then
  begin
    SetEGLError('unable to show color buffer in an OS-native window', 'eglSwapBuffers');
    Exit(False);
  end;
  Result := True;
end;

function TPMLEGLBackend.SwapWindow(AWindow: TPMLWindowBackend): Boolean;
var
  Surf: EGLSurface;
begin
  FLastError := '';
  Surf := SurfaceOf(AWindow);
  if Surf = EGL_NO_SURFACE then
  begin
    FLastError := 'the window has no EGL surface';
    Exit(False);
  end;
  Result := SwapSurface(AWindow, Surf);
end;

function TPMLEGLBackend.CurrentSwapInterval: Integer;
begin
  Result := GetSwapInterval(FCurrentContext);
end;

function TPMLEGLBackend.StoreSwapInterval(AContext: TPMLGLContextHandle;
  AInterval: Integer): Boolean;
var
  I: Integer;
begin
  I := IndexOfContext(AContext);
  if I < 0 then
  begin
    FLastError := 'unknown GL context';
    Exit(False);
  end;
  FContexts[I].Interval := AInterval;
  Result := True;
end;

function TPMLEGLBackend.ApplySwapInterval(AInterval: Integer): Boolean;
begin
  Result := eglSwapInterval(FDisplay, AInterval) <> EGL_FALSE;
end;

{ PORT-NOTE(bug): SDL_EGL_SetSwapInterval は値を egl_data に 1 つだけ持ち、
  SDL_EGL_CreateContext が 0 に戻す。ヘッダは「現在のコンテキストの」間隔と
  書いているのに、2 つ目のコンテキストを作ると 1 つ目の値も消える（D-53。SDL 3.4.2
  で実測）。papimela はコンテキストごとに持ち、現在のものなら今すぐ、そうでなければ
  次に MakeCurrent したときに描画面へ効かせる。 }
function TPMLEGLBackend.SetSwapInterval(AContext: TPMLGLContextHandle;
  AInterval: Integer): Boolean;
begin
  FLastError := '';
  if FDisplay = EGL_NO_DISPLAY then
  begin
    FLastError := 'EGL not initialized';
    Exit(False);
  end;
  // EGL_EXT_swap_control_tear（適応 VSync）はまだ公開されていない（SDL の FIXME）
  if AInterval < 0 then
  begin
    FLastError := 'Late swap tearing currently unsupported';
    Exit(False);
  end;
  if IndexOfContext(AContext) < 0 then
  begin
    FLastError := 'unknown GL context';
    Exit(False);
  end;
  if (AContext = FCurrentContext) and not ApplySwapInterval(AInterval) then
  begin
    SetEGLError('Unable to set the EGL swap interval', 'eglSwapInterval');
    Exit(False);
  end;
  Result := StoreSwapInterval(AContext, AInterval);
end;

function TPMLEGLBackend.GetSwapInterval(AContext: TPMLGLContextHandle): Integer;
var
  I: Integer;
begin
  I := IndexOfContext(AContext);
  if I < 0 then
    Exit(0);
  Result := FContexts[I].Interval;
end;
procedure TPMLEGLBackend.ReleaseWindow(AWindow: TPMLWindowBackend);
var
  I, J: Integer;
  Rec: TPMLEGLWindowSurface;
begin
  for I := 0 to High(FSurfaces) do
    if FSurfaces[I].Window = AWindow then
    begin
      Rec := FSurfaces[I];
      if FCurrentSurface = Rec.Surface then
        ReleaseCurrent;
      eglDestroySurface(FDisplay, Rec.Surface);
      DestroyNativeWindow(AWindow, Rec.Native);
      for J := I to High(FSurfaces) - 1 do
        FSurfaces[J] := FSurfaces[J + 1];
      SetLength(FSurfaces, Length(FSurfaces) - 1);
      Rec.Free;
      Exit;
    end;
end;

{ libGLESv2 から AName を引く。ライブラリは最初に要るときに 1 度だけ開く。 }
function TPMLEGLBackend.GLESSymbol(const AName: String): Pointer;
begin
  if (FGLES = nil) and (not FGLESTried) then
  begin
    FGLESTried := True;
    try
      FGLES := TPMLDynLib.Create(GLES_NAMES);
    except
      on E: Exception do
      begin
        FGLES := nil;
        FLastError := E.Message;
      end;
    end;
  end;
  if FGLES = nil then
    Exit(nil);
  Result := FGLES.TryResolve(AName);
end;

function TPMLEGLBackend.GetProcAddress(const AName: String): Pointer;
begin
  Result := nil;
  if AName = '' then
    Exit;
  if not EnsureLoaded then
    Exit;
  if (Length(AName) > 2) and (Copy(AName, 1, 2) = 'gl') then
  begin
    // コア関数は libGLESv2 が確定させる。無い名前は、拡張の接尾辞があるときだけ
    // eglGetProcAddress に任せる（ヘッダの PORT-NOTE を参照）。
    Result := GLESSymbol(AName);
    if Result <> nil then
      Exit;
    if not HasVendorSuffix(AName) then
      Exit(nil);
  end;
  Result := eglGetProcAddress(PAnsiChar(AName));
end;

end.
