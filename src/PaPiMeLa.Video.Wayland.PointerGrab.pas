{
  PaPiMeLa.Video.Wayland.PointerGrab — ポインタの拘束（ロック / 閉じ込め / 相対移動）

  Origin : partially ported from SDL (src/video/wayland/SDL_waylandevents.c,
           src/video/wayland/SDL_waylandmouse.c)
           Scope: プロトコルの手順に関する知見のみ。同一シート・同一サーフェスに
           ロックと閉じ込めを同時に作れないこと、1x1 の領域はロックで代用すること、
           領域外にポインタがあるときは先に引き寄せる必要があること、位置ヒントは
           ロック中しか送れないこと。構造は本設計に従う。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.2、§3.3、§11 #37

  WHAT:
    1 つの wl_pointer に対して zwp_locked_pointer_v1 / zwp_confined_pointer_v1 /
    zwp_relative_pointer_v1 を張り替える。ウィンドウ側の要求（グラブ、相対モード、
    閉じ込め矩形）とフォーカス状態から、今どの拘束を持つべきかを 1 箇所で決める。

  WHY:
    拘束オブジェクトはサーフェスではなく wl_pointer に紐づく。ウィンドウごとに
    持たせると、同じシートで 2 つのウィンドウが同時に拘束を要求したときに
    プロトコルエラーになる。持ち主をポインタ側に寄せて、要求はウィンドウから
    読みに行く形にした。

  RESOLVED:
    - ロックと閉じ込めは排他。張り替えるときは必ず片方を先に破棄する
    - 閉じ込めは「キーボードフォーカスがある」ときだけ。そうしないと利用者が
      他のウィンドウを操作できなくなる
    - 拘束中は wl_pointer.motion が来ない。相対移動だけが位置情報になる
    - 矩形が 1x1 のときはロックで代用する。閉じ込めだとサブピクセル移動が残る

  NOT RESOLVED:
    - カーソルの表示 / 非表示は扱わない（#38 の TPMLCursorBackend）。相対モードでも
      カーソルは見えたままになる
    - 相対移動の非加速値（dx_unaccel / dy_unaccel）は受け取るが捨てている。
      公開イベントに載せる場所が無い
    - wp_pointer_warp_v1 は束縛していない。ワープはロックの位置ヒントで代用する

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Wayland.PointerGrab;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Video.Wayland.Types,
  PaPiMeLa.Video.Wayland.Window,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland,
  PaPiMeLa.Platform.Wayland.Protocols.PointerConstraintsUnstableV1,
  PaPiMeLa.Platform.Wayland.Protocols.RelativePointerUnstableV1;

type
  TPMLWaylandPointerGrab = class;

  { 生成リスナーは抽象クラスなので、1 クラスで 3 つを同時に継承できない。
    シートと同じく転送クラスを置いて実体へ委譲する。 }
  TPMLWaylandLockedFwd = class(Tzwp_locked_pointer_v1_listener)
  strict private
    FOwner: TPMLWaylandPointerGrab;
  public
    constructor Create(AOwner: TPMLWaylandPointerGrab);
    procedure locked(AProxy: Pzwp_locked_pointer_v1); override;
    procedure unlocked(AProxy: Pzwp_locked_pointer_v1); override;
  end;

  TPMLWaylandConfinedFwd = class(Tzwp_confined_pointer_v1_listener)
  strict private
    FOwner: TPMLWaylandPointerGrab;
  public
    constructor Create(AOwner: TPMLWaylandPointerGrab);
    procedure confined(AProxy: Pzwp_confined_pointer_v1); override;
    procedure unconfined(AProxy: Pzwp_confined_pointer_v1); override;
  end;

  TPMLWaylandRelativeFwd = class(Tzwp_relative_pointer_v1_listener)
  strict private
    FOwner: TPMLWaylandPointerGrab;
  public
    constructor Create(AOwner: TPMLWaylandPointerGrab);
    procedure relative_motion(AProxy: Pzwp_relative_pointer_v1;
      utime_hi: LongWord; utime_lo: LongWord; dx: wl_fixed_t; dy: wl_fixed_t;
      dx_unaccel: wl_fixed_t; dy_unaccel: wl_fixed_t); override;
  end;

  { 今どの拘束を持っているか。診断とテスト用に公開する。 }
  TPMLPointerGrabKind = (None, Locked, Confined);

  TPMLWaylandPointerGrab = class
  strict private
    FConn    : TPMLWaylandConnection;
    FQueue   : TPMLEventQueue;
    FPointer : Pwl_pointer;

    FLocked  : Pzwp_locked_pointer_v1;
    FConfined: Pzwp_confined_pointer_v1;
    FRelative: Pzwp_relative_pointer_v1;

    FLockedFwd  : TPMLWaylandLockedFwd;
    FConfinedFwd: TPMLWaylandConfinedFwd;
    FRelativeFwd: TPMLWaylandRelativeFwd;

    FWindow    : TPMLWaylandWindowBackend;   // ポインタフォーカスのあるウィンドウ
    FKeyFocusID: TPMLWindowID;
    FHasKeyboard: Boolean;
    FEffective : Boolean;                    // コンポジタが拘束を有効にした
    FLastX     : Single;
    FLastY     : Single;
    FRelativeCount: Int64;                   // 受け取った相対移動の件数（テスト用）

    procedure DropLock;
    procedure DropConfine;
    procedure DropRelative;
    function  WantRelative: Boolean;
    function  WantConfine(out ARect: TPMLRect): Boolean;
    procedure EnsureRelative;
    procedure CreateLock;
    procedure CreateConfine(const ARect: TPMLRect; AWholeSurface: Boolean);
    procedure WarpInto(const ARect: TPMLRect);
    function  GetKind: TPMLPointerGrabKind;
    function  GetRelativeActive: Boolean;
    function  GetFocusWindowID: TPMLWindowID;
  private
    procedure HandleEffective(AEffective: Boolean);
    procedure HandleRelativeMotion(ADX, ADY: wl_fixed_t);
  public
    constructor Create(AConn: TPMLWaylandConnection; AQueue: TPMLEventQueue;
      APointer: Pwl_pointer);
    destructor Destroy; override;

    // シートが呼ぶ。フォーカスや要求が変わったら Update を呼び直す。
    procedure SetPointerFocus(AWindow: TPMLWaylandWindowBackend);
    procedure SetKeyboardFocus(AWindowID: TPMLWindowID);
    procedure NoteMotion(AX, AY: Single);
    procedure Update;

    property Kind          : TPMLPointerGrabKind read GetKind;
    property Effective     : Boolean read FEffective;
    property RelativeActive : Boolean read GetRelativeActive;
    property RelativeCount : Int64 read FRelativeCount;
    property HasKeyboard   : Boolean read FHasKeyboard write FHasKeyboard;
    property FocusWindowID : TPMLWindowID read GetFocusWindowID;
  end;

implementation

{ 転送クラス }

constructor TPMLWaylandLockedFwd.Create(AOwner: TPMLWaylandPointerGrab);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TPMLWaylandLockedFwd.locked(AProxy: Pzwp_locked_pointer_v1);
begin
  FOwner.HandleEffective(True);
end;

procedure TPMLWaylandLockedFwd.unlocked(AProxy: Pzwp_locked_pointer_v1);
begin
  FOwner.HandleEffective(False);
end;

constructor TPMLWaylandConfinedFwd.Create(AOwner: TPMLWaylandPointerGrab);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TPMLWaylandConfinedFwd.confined(AProxy: Pzwp_confined_pointer_v1);
begin
  FOwner.HandleEffective(True);
end;

procedure TPMLWaylandConfinedFwd.unconfined(AProxy: Pzwp_confined_pointer_v1);
begin
  FOwner.HandleEffective(False);
end;

constructor TPMLWaylandRelativeFwd.Create(AOwner: TPMLWaylandPointerGrab);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TPMLWaylandRelativeFwd.relative_motion(AProxy: Pzwp_relative_pointer_v1;
  utime_hi: LongWord; utime_lo: LongWord; dx: wl_fixed_t; dy: wl_fixed_t;
  dx_unaccel: wl_fixed_t; dy_unaccel: wl_fixed_t);
begin
  // 時刻はマイクロ秒の 64 ビット分割。イベントキューは自前で計時するので使わない。
  FOwner.HandleRelativeMotion(dx, dy);
end;

{ TPMLWaylandPointerGrab }

constructor TPMLWaylandPointerGrab.Create(AConn: TPMLWaylandConnection;
  AQueue: TPMLEventQueue; APointer: Pwl_pointer);
begin
  inherited Create;
  FConn := AConn;
  FQueue := AQueue;
  FPointer := APointer;
  FLockedFwd := TPMLWaylandLockedFwd.Create(Self);
  FConfinedFwd := TPMLWaylandConfinedFwd.Create(Self);
  FRelativeFwd := TPMLWaylandRelativeFwd.Create(Self);
end;

destructor TPMLWaylandPointerGrab.Destroy;
begin
  DropRelative;
  DropLock;
  DropConfine;
  FreeAndNil(FRelativeFwd);
  FreeAndNil(FConfinedFwd);
  FreeAndNil(FLockedFwd);
  inherited Destroy;
end;

procedure TPMLWaylandPointerGrab.DropLock;
begin
  if FLocked = nil then
    Exit;
  zwp_locked_pointer_v1_destroy(FLocked);
  FLocked := nil;
  FEffective := False;
end;

procedure TPMLWaylandPointerGrab.DropConfine;
begin
  if FConfined = nil then
    Exit;
  zwp_confined_pointer_v1_destroy(FConfined);
  FConfined := nil;
  FEffective := False;
end;

procedure TPMLWaylandPointerGrab.DropRelative;
begin
  if FRelative = nil then
    Exit;
  zwp_relative_pointer_v1_destroy(FRelative);
  FRelative := nil;
end;

{ 相対モードを張るべきか。

  キーボードを持つシートでは、そのシートのキーボードフォーカスと一致するときだけ
  張る。持たないシートではキーボードフォーカスを問わない（そのシートには
  フォーカスの概念が無いため）。 }
function TPMLWaylandPointerGrab.WantRelative: Boolean;
begin
  Result := (FWindow <> nil)
        and FWindow.RelativeMouseRequested
        and (FConn.RelativePointerMgr <> nil);
  if Result and FHasKeyboard then
    Result := FKeyFocusID = FWindow.WindowID;
end;

{ 閉じ込めるべきか。ARect が空なら「サーフェス全体」を意味する。 }
function TPMLWaylandPointerGrab.WantConfine(out ARect: TPMLRect): Boolean;
begin
  ARect := TPMLRect.Make(0, 0, 0, 0);
  Result := False;
  if FWindow = nil then
    Exit;
  // キーボードフォーカスの無いウィンドウにポインタを閉じ込めてはいけない。
  if FHasKeyboard and (FKeyFocusID <> FWindow.WindowID) then
    Exit;
  ARect := FWindow.MouseRect;
  Result := FWindow.MouseGrabbed or not ARect.IsEmpty;
end;

procedure TPMLWaylandPointerGrab.EnsureRelative;
begin
  if (FRelative <> nil) or (FConn.RelativePointerMgr = nil) then
    Exit;
  FRelative := zwp_relative_pointer_manager_v1_get_relative_pointer(
    FConn.RelativePointerMgr, FPointer);
  if FRelative <> nil then
    zwp_relative_pointer_v1_add_listener_object(FRelative, FRelativeFwd);
end;

procedure TPMLWaylandPointerGrab.CreateLock;
begin
  if (FLocked <> nil) or (FWindow = nil) then
    Exit;
  FLocked := zwp_pointer_constraints_v1_lock_pointer(FConn.PointerConstraints,
    FWindow.Surface, FPointer, nil,
    ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_PERSISTENT);
  if FLocked <> nil then
    zwp_locked_pointer_v1_add_listener_object(FLocked, FLockedFwd);
end;

{ 閉じ込めを作る。AWholeSurface なら領域を渡さない（= サーフェス全体）。 }
procedure TPMLWaylandPointerGrab.CreateConfine(const ARect: TPMLRect;
  AWholeSurface: Boolean);
var
  Region: Pwl_region;
begin
  if (FConfined <> nil) or (FWindow = nil) then
    Exit;
  Region := nil;
  if (not AWholeSurface) and (FConn.Compositor <> nil) then
  begin
    Region := wl_compositor_create_region(FConn.Compositor);
    wl_region_add(Region, ARect.X, ARect.Y, ARect.W, ARect.H);
  end;
  FConfined := zwp_pointer_constraints_v1_confine_pointer(FConn.PointerConstraints,
    FWindow.Surface, FPointer, Region,
    ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_PERSISTENT);
  if FConfined <> nil then
    zwp_confined_pointer_v1_add_listener_object(FConfined, FConfinedFwd);
  if Region <> nil then
    wl_region_destroy(Region);
end;

{ ポインタが矩形の外にいるなら、矩形内の最も近い点へ引き寄せる。

  PORT-NOTE: SDL_waylandevents.c の Wayland_SeatUpdatePointerGrab と同じ理由。
  領域を指定した閉じ込めは、作った時点でポインタが領域内にないと有効にならない
  コンポジタがある。位置ヒントはロック中しか送れないので、使い捨てのロック
  （LIFETIME_ONESHOT）を張ってヒントを送り、すぐ捨てる。

  この関数は呼び出し側が先にロックと閉じ込めを破棄していることを前提にする。
  残っていると already_constrained でプロトコルエラーになる。 }
procedure TPMLWaylandPointerGrab.WarpInto(const ARect: TPMLRect);
var
  X, Y: Single;
  Lock: Pzwp_locked_pointer_v1;
begin
  if (FWindow = nil) or ARect.IsEmpty or (FConn.PointerConstraints = nil) then
    Exit;

  X := FLastX;
  Y := FLastY;
  if X < ARect.X then
    X := ARect.X
  else if X > ARect.X + ARect.W - 1 then
    X := ARect.X + ARect.W - 1;
  if Y < ARect.Y then
    Y := ARect.Y
  else if Y > ARect.Y + ARect.H - 1 then
    Y := ARect.Y + ARect.H - 1;

  // 既に領域内なら何もしない。
  if (X = FLastX) and (Y = FLastY) then
    Exit;

  Lock := zwp_pointer_constraints_v1_lock_pointer(FConn.PointerConstraints,
    FWindow.Surface, FPointer, nil,
    ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_ONESHOT);
  if Lock = nil then
    Exit;
  zwp_locked_pointer_v1_set_cursor_position_hint(Lock,
    PMLSingleToFixed(X), PMLSingleToFixed(Y));
  // ヒントはサーフェスの次のコミットで適用される。
  wl_surface_commit(FWindow.Surface);
  zwp_locked_pointer_v1_destroy(Lock);

  FLastX := X;
  FLastY := Y;
end;

function TPMLWaylandPointerGrab.GetKind: TPMLPointerGrabKind;
begin
  if FLocked <> nil then
    Result := TPMLPointerGrabKind.Locked
  else if FConfined <> nil then
    Result := TPMLPointerGrabKind.Confined
  else
    Result := TPMLPointerGrabKind.None;
end;

function TPMLWaylandPointerGrab.GetRelativeActive: Boolean;
begin
  Result := FRelative <> nil;
end;

function TPMLWaylandPointerGrab.GetFocusWindowID: TPMLWindowID;
begin
  if FWindow = nil then
    Result := 0
  else
    Result := FWindow.WindowID;
end;

procedure TPMLWaylandPointerGrab.HandleEffective(AEffective: Boolean);
begin
  FEffective := AEffective;
end;

{ 相対移動。ロック中は wl_pointer.motion が来ないので、これが唯一の移動情報。 }
procedure TPMLWaylandPointerGrab.HandleRelativeMotion(ADX, ADY: wl_fixed_t);
begin
  Inc(FRelativeCount);
  if FWindow = nil then
    Exit;
  FQueue.Mouse.SendRelativeMotion(FWindow.WindowID,
    PMLFixedToSingle(ADX), PMLFixedToSingle(ADY));
end;

procedure TPMLWaylandPointerGrab.SetPointerFocus(AWindow: TPMLWaylandWindowBackend);
begin
  if FWindow = AWindow then
    Exit;
  FWindow := AWindow;
  // フォーカスが変わったら拘束は張り直す。サーフェスが違えば別の拘束になる。
  DropRelative;
  DropLock;
  DropConfine;
end;

procedure TPMLWaylandPointerGrab.SetKeyboardFocus(AWindowID: TPMLWindowID);
begin
  FKeyFocusID := AWindowID;
end;

procedure TPMLWaylandPointerGrab.NoteMotion(AX, AY: Single);
begin
  FLastX := AX;
  FLastY := AY;
end;

{ 今あるべき拘束へ張り替える。何度呼んでも構わない。

  相対モードが最優先。閉じ込めとロックは排他なので、相対モードなら閉じ込めを
  捨ててロックを張る。相対モードでなければロックを捨て、要求に応じて
  閉じ込めを作り直す（矩形が変わっている可能性があるため毎回作り直す）。 }
procedure TPMLWaylandPointerGrab.Update;
var
  Rect: TPMLRect;
begin
  if (FPointer = nil) or (FConn.PointerConstraints = nil) then
    Exit;

  if WantRelative then
  begin
    DropConfine;
    EnsureRelative;
    CreateLock;
    Exit;
  end;

  DropRelative;
  DropLock;
  DropConfine;

  if not WantConfine(Rect) then
    Exit;

  if Rect.IsEmpty then
  begin
    CreateConfine(Rect, True);
    Exit;
  end;

  WarpInto(Rect);
  if (Rect.W <= 1) or (Rect.H <= 1) then
    // 1 ピクセル幅の閉じ込めはサブピクセル移動が残るので、ロックで代用する。
    // 引き寄せ済みなので領域を渡さないロックでも位置は合っている。
    CreateLock
  else
    CreateConfine(Rect, False);
end;

end.
