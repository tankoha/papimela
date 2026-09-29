{
  PaPiMeLa.Video.Wayland.Types — Wayland 接続とグローバル束縛

  Origin : partially ported from SDL (src/video/wayland/SDL_waylandvideo.c)
           Scope: レジストリハンドラで束縛するグローバルの一覧と、xdg_wm_base の
           ping に pong で応答する必要があるという知見。構造は本設計に従う。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.2（Wayland バックエンドの内部構成）、§11 #35

  WHAT:
    wl_display への接続、レジストリの列挙、グローバルの束縛、および拡張の有無を
    能力集合へ写す処理。ウィンドウとビデオバックエンドの両方がこれを参照する。

  WHY:
    ウィンドウ backend（#36）とビデオ backend（#35）が互いを参照すると循環する。
    共有される接続状態だけを下層のユニットに置いてある。

  RESOLVED:
    - xdg_wm_base.ping には必ず pong で応答する。無視するとコンポジタは
      アプリを応答なしと判断する
    - グローバルは 1 回目の roundtrip で列挙し、2 回目で各 output の
      メタデータ（geometry / mode / scale / name）が揃う

  NOT RESOLVED:
    - シート（wl_seat の keyboard / pointer / touch）は束縛するが中身は未実装（#37）
    - 読み取りスレッド（SDL_waylandeventthread.c 相当）は移植しない。
      PumpEvents はメインスレッドで dispatch_pending + poll(2) を行う（§3.2）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Wayland.Types;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland,
  PaPiMeLa.Platform.Wayland.Protocols.XdgShell,
  PaPiMeLa.Platform.Wayland.Protocols.XdgDecorationUnstableV1,
  PaPiMeLa.Platform.Wayland.Protocols.Viewporter,
  PaPiMeLa.Platform.Wayland.Protocols.FractionalScaleV1,
  PaPiMeLa.Platform.Wayland.Protocols.IdleInhibitUnstableV1,
  PaPiMeLa.Platform.Wayland.Protocols.XdgActivationV1,
  PaPiMeLa.Platform.Wayland.Protocols.TextInputUnstableV3,
  PaPiMeLa.Platform.Wayland.Protocols.PointerConstraintsUnstableV1,
  PaPiMeLa.Platform.Wayland.Protocols.RelativePointerUnstableV1;

type
  { 1 つの wl_output。メタデータを溜めて TPMLDisplayBackend に見せる。 }
  TPMLWaylandOutput = class(Twl_output_listener)
  strict private
    FProxy   : Pwl_output;
    FName     : String;
    FX, FY    : Integer;
    FWidth, FHeight: Integer;
    FRefresh  : Integer;      // mHz
    FScale    : Integer;
    FTransform: Integer;
    FGlobalName: LongWord;
  public
    constructor Create(AProxy: Pwl_output; AGlobalName: LongWord);
    procedure geometry(AProxy: Pwl_output; x: LongInt; y: LongInt;
      physical_width: LongInt; physical_height: LongInt; subpixel: LongInt;
      make: PAnsiChar; model: PAnsiChar; transform: LongInt); override;
    procedure mode(AProxy: Pwl_output; flags: LongWord; width: LongInt;
      height: LongInt; refresh: LongInt); override;
    procedure scale(AProxy: Pwl_output; factor: LongInt); override;
    procedure name(AProxy: Pwl_output; name_: PAnsiChar); override;

    property Proxy     : Pwl_output read FProxy;
    property GlobalName: LongWord read FGlobalName;
    property OutputName: String read FName;
    property X         : Integer read FX;
    property Y         : Integer read FY;
    property Width     : Integer read FWidth;
    property Height    : Integer read FHeight;
    property RefreshMHz: Integer read FRefresh;
    // 生成された仮想メソッド scale と同名にできないため ScaleFactor とする（D-10 と同型の衝突）
    property ScaleFactor: Integer read FScale;
  end;
  TPMLWaylandOutputs = array of TPMLWaylandOutput;
  TPMLWaylandSeatHandles = array of Pwl_seat;

  // wl_seat を束縛した瞬間に呼ばれる。リスナーはここで付けないと、
  // 直後の roundtrip で capabilities が配送されて取りこぼす。
  TPMLWaylandSeatBoundProc = procedure(ASeat: Pwl_seat) of object;

  // ウィンドウの拘束要求（グラブ / 相対モード / 矩形）が変わったときに呼ばれる。
  // 拘束オブジェクトは wl_pointer 単位なのでシートが持つ。シートを知っているのは
  // Video.Wayland なのでそちらが設定する。AWindowID = 0 は「全ウィンドウ」。
  TPMLWaylandGrabsChangedProc = procedure(AWindowID: TPMLWindowID) of object;

  { xdg_wm_base の ping に応答する。 }
  TPMLWaylandWmBaseWatcher = class(Txdg_wm_base_listener)
  public
    procedure ping(AProxy: Pxdg_wm_base; serial: LongWord); override;
  end;

  { 接続とグローバル束縛。 }
  TPMLWaylandConnection = class(Twl_registry_listener)
  strict private
    FDisplay   : Pwl_display;
    FRegistry  : Pwl_registry;
    FWmWatcher : TPMLWaylandWmBaseWatcher;
    FOutputs   : TPMLWaylandOutputs;
    FSeats     : TPMLWaylandSeatHandles;
    FOnSeatBound: TPMLWaylandSeatBoundProc;
    FOnGrabsChanged: TPMLWaylandGrabsChangedProc;
    procedure BindGlobal(AName: LongWord; const AInterface: String; AVersion: LongWord);
  public
    // 束縛したグローバル（nil = そのコンポジタに無い）
    Compositor      : Pwl_compositor;
    Shm             : Pwl_shm;
    WmBase          : Pxdg_wm_base;
    DecorationMgr   : Pzxdg_decoration_manager_v1;
    Viewporter      : Pwp_viewporter;
    FractionalMgr   : Pwp_fractional_scale_manager_v1;
    IdleInhibitMgr  : Pzwp_idle_inhibit_manager_v1;
    ActivationMgr   : Pxdg_activation_v1;
    TextInputMgr    : Pzwp_text_input_manager_v3;
    PointerConstraints: Pzwp_pointer_constraints_v1;
    RelativePointerMgr: Pzwp_relative_pointer_manager_v1;

    constructor Create;
    destructor Destroy; override;

    function  Connect: Boolean;
    procedure Disconnect;
    function  Capabilities: TPMLVideoCapabilities;

    // ウィンドウバックエンドが拘束要求を変えたときに呼ぶ。設定されていなければ何もしない。
    procedure NotifyGrabsChanged(AWindowID: TPMLWindowID);

    procedure global(AProxy: Pwl_registry; name: LongWord;
      interface_: PAnsiChar; version: LongWord); override;
    procedure global_remove(AProxy: Pwl_registry; name: LongWord); override;

    property Display: Pwl_display read FDisplay;
    property Outputs: TPMLWaylandOutputs read FOutputs;
    // シートの生成は Video.Wayland が行う（Seat ユニットを参照すると循環するため）。
    property Seats  : TPMLWaylandSeatHandles read FSeats;
    // Connect の前に設定すること。束縛時に呼ばれる。
    property OnSeatBound: TPMLWaylandSeatBoundProc read FOnSeatBound write FOnSeatBound;
    property OnGrabsChanged: TPMLWaylandGrabsChangedProc
      read FOnGrabsChanged write FOnGrabsChanged;
  end;

implementation

{ TPMLWaylandOutput }

constructor TPMLWaylandOutput.Create(AProxy: Pwl_output; AGlobalName: LongWord);
begin
  inherited Create;
  FProxy := AProxy;
  FGlobalName := AGlobalName;
  FScale := 1;
  FWidth := 0;
  FHeight := 0;
  FName := '';
end;

procedure TPMLWaylandOutput.geometry(AProxy: Pwl_output; x: LongInt; y: LongInt;
  physical_width: LongInt; physical_height: LongInt; subpixel: LongInt;
  make: PAnsiChar; model: PAnsiChar; transform: LongInt);
begin
  FX := x;
  FY := y;
  FTransform := transform;
  if FName = '' then
    FName := String(make) + ' ' + String(model);
end;

procedure TPMLWaylandOutput.mode(AProxy: Pwl_output; flags: LongWord;
  width: LongInt; height: LongInt; refresh: LongInt);
begin
  // WL_OUTPUT_MODE_CURRENT のときだけ採用する。
  if (flags and WL_OUTPUT_MODE_CURRENT) <> 0 then
  begin
    FWidth := width;
    FHeight := height;
    FRefresh := refresh;
  end;
end;

procedure TPMLWaylandOutput.scale(AProxy: Pwl_output; factor: LongInt);
begin
  FScale := factor;
end;

procedure TPMLWaylandOutput.name(AProxy: Pwl_output; name_: PAnsiChar);
begin
  FName := String(name_);
end;

{ TPMLWaylandWmBaseWatcher }

procedure TPMLWaylandWmBaseWatcher.ping(AProxy: Pxdg_wm_base; serial: LongWord);
begin
  // 応答しないとコンポジタはアプリを応答なしと判断する（SDL から継承した知見）。
  xdg_wm_base_pong(AProxy, serial);
end;

{ TPMLWaylandConnection }

constructor TPMLWaylandConnection.Create;
begin
  inherited Create;
  FWmWatcher := TPMLWaylandWmBaseWatcher.Create;
end;

destructor TPMLWaylandConnection.Destroy;
begin
  Disconnect;
  FreeAndNil(FWmWatcher);
  inherited Destroy;
end;

function TPMLWaylandConnection.Connect: Boolean;
begin
  Result := False;
  if not PMLWaylandClientLoad then
    Exit;

  PaPiMeLa.Platform.Wayland.Protocols.Wayland.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.XdgShell.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.XdgDecorationUnstableV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.Viewporter.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.FractionalScaleV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.IdleInhibitUnstableV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.XdgActivationV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.TextInputUnstableV3.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.PointerConstraintsUnstableV1.EnsureProtocolInitialized;
  PaPiMeLa.Platform.Wayland.Protocols.RelativePointerUnstableV1.EnsureProtocolInitialized;

  FDisplay := wl_display_connect(nil);
  if FDisplay = nil then
  begin
    PMLWaylandClientUnload;
    Exit;
  end;

  FRegistry := wl_display_get_registry(FDisplay);
  wl_registry_add_listener_object(FRegistry, Self);
  // 1 回目でグローバルが揃う。
  wl_display_roundtrip(FDisplay);
  // 2 回目で各 output のメタデータが揃う。
  wl_display_roundtrip(FDisplay);

  if (Compositor = nil) or (WmBase = nil) then
  begin
    Disconnect;
    Exit;
  end;
  Result := True;
end;

procedure TPMLWaylandConnection.Disconnect;
var
  I: Integer;
begin
  for I := 0 to High(FOutputs) do
    FOutputs[I].Free;
  SetLength(FOutputs, 0);
  SetLength(FSeats, 0);
  if FDisplay <> nil then
  begin
    wl_display_flush(FDisplay);
    wl_display_disconnect(FDisplay);
    FDisplay := nil;
    PMLWaylandClientUnload;
  end;
  FRegistry := nil;
  PointerConstraints := nil;
  RelativePointerMgr := nil;
  Compositor := nil;
  Shm := nil;
  WmBase := nil;
end;

procedure TPMLWaylandConnection.BindGlobal(AName: LongWord;
  const AInterface: String; AVersion: LongWord);

  function B(AIface: Pwl_interface; AMax: LongWord): Pwl_proxy;
  var
    V: LongWord;
  begin
    V := AVersion;
    if V > AMax then
      V := AMax;
    Result := wl_registry_bind(FRegistry, AName, AIface, V);
  end;

var
  Output: TPMLWaylandOutput;
  Seat  : Pwl_seat;
begin
  case AInterface of
    'wl_compositor':
      Compositor := Pwl_compositor(B(wl_compositor_interface, 6));
    'wl_shm':
      Shm := Pwl_shm(B(wl_shm_interface, 1));
    'xdg_wm_base':
      begin
        WmBase := Pxdg_wm_base(B(xdg_wm_base_interface, 6));
        xdg_wm_base_add_listener_object(WmBase, FWmWatcher);
      end;
    'zxdg_decoration_manager_v1':
      DecorationMgr := Pzxdg_decoration_manager_v1(B(zxdg_decoration_manager_v1_interface, 1));
    'wp_viewporter':
      Viewporter := Pwp_viewporter(B(wp_viewporter_interface, 1));
    'wp_fractional_scale_manager_v1':
      FractionalMgr := Pwp_fractional_scale_manager_v1(B(wp_fractional_scale_manager_v1_interface, 1));
    'zwp_idle_inhibit_manager_v1':
      IdleInhibitMgr := Pzwp_idle_inhibit_manager_v1(B(zwp_idle_inhibit_manager_v1_interface, 1));
    'xdg_activation_v1':
      ActivationMgr := Pxdg_activation_v1(B(xdg_activation_v1_interface, 1));
    'zwp_pointer_constraints_v1':
      PointerConstraints := Pzwp_pointer_constraints_v1(B(zwp_pointer_constraints_v1_interface, 1));
    'zwp_relative_pointer_manager_v1':
      RelativePointerMgr := Pzwp_relative_pointer_manager_v1(B(zwp_relative_pointer_manager_v1_interface, 1));
    'zwp_text_input_manager_v3':
      TextInputMgr := Pzwp_text_input_manager_v3(B(zwp_text_input_manager_v3_interface, 1));
    'wl_output':
      begin
        Output := TPMLWaylandOutput.Create(Pwl_output(B(wl_output_interface, 4)), AName);
        wl_output_add_listener_object(Output.Proxy, Output);
        SetLength(FOutputs, Length(FOutputs) + 1);
        FOutputs[High(FOutputs)] := Output;
      end;
    'wl_seat':
      begin
        // keyboard / pointer は TPMLWaylandSeat が取り出す。wl_touch は未実装。
        Seat := Pwl_seat(B(wl_seat_interface, 9));
        SetLength(FSeats, Length(FSeats) + 1);
        FSeats[High(FSeats)] := Seat;
        // リスナーを今ここで付ける。roundtrip を待つと capabilities を取りこぼす。
        if Assigned(FOnSeatBound) then
          FOnSeatBound(Seat);
      end;
  end;
end;

procedure TPMLWaylandConnection.global(AProxy: Pwl_registry; name: LongWord;
  interface_: PAnsiChar; version: LongWord);
begin
  BindGlobal(name, String(interface_), version);
end;

procedure TPMLWaylandConnection.global_remove(AProxy: Pwl_registry; name: LongWord);
var
  I, J: Integer;
begin
  for I := 0 to High(FOutputs) do
    if FOutputs[I].GlobalName = name then
    begin
      FOutputs[I].Free;
      for J := I to High(FOutputs) - 1 do
        FOutputs[J] := FOutputs[J + 1];
      SetLength(FOutputs, Length(FOutputs) - 1);
      Exit;
    end;
end;

function TPMLWaylandConnection.Capabilities: TPMLVideoCapabilities;
begin
  // Wayland では拡張の有無で能力が変わるので Connect 後に確定する（§3.3）。
  Result := [TPMLVideoCapability.HighDPI];
  if Shm <> nil then
    Include(Result, TPMLVideoCapability.SoftwareFramebuffer);
  if DecorationMgr <> nil then
    Include(Result, TPMLVideoCapability.ServerSideDecoration);
  if FractionalMgr <> nil then
    Include(Result, TPMLVideoCapability.FractionalScale);
  if IdleInhibitMgr <> nil then
    Include(Result, TPMLVideoCapability.IdleInhibit);
  if ActivationMgr <> nil then
    Include(Result, TPMLVideoCapability.WindowActivation);
  // 相対モードはロック（pointer-constraints）と relative-pointer の両方が要る。
  // 閉じ込めだけならロックは不要なので、必要な拡張が別であることを能力でも分ける。
  if PointerConstraints <> nil then
    Include(Result, TPMLVideoCapability.MouseConfine);
  if (PointerConstraints <> nil) and (RelativePointerMgr <> nil) then
    Include(Result, TPMLVideoCapability.RelativeMouse);
  // xdg-shell はウィンドウ位置を持たないので WindowPositioning は入れない（§3.3）。
  Include(Result, TPMLVideoCapability.SystemMenu);
end;

procedure TPMLWaylandConnection.NotifyGrabsChanged(AWindowID: TPMLWindowID);
begin
  if Assigned(FOnGrabsChanged) then
    FOnGrabsChanged(AWindowID);
end;

end.
