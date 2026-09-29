{
  PaPiMeLa.Video — ビデオサブシステムの公開 API

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §4.2、§3.3、§11 #32

  WHAT:
    TPMLVideoSystem / TPMLDisplay / TPMLWindow。バックエンドの能力集合を見て
    未対応の操作を EPMLUnsupported にし、バックエンドからの通知をイベント
    キューへ積む。

  WHY:
    「呼んでよいか」の判断を公開層に 1 箇所だけ置く。バックエンド実装は
    「呼ばれたら必ずできる」前提で書ける（§3.3）。

  RESOLVED:
    - ウィンドウ ID は 1 から連番。0 は「ウィンドウ無関係」の意味で予約
    - バックエンドからの通知はイベントキューへ積むと同時にウィンドウの
      キャッシュ済み状態も更新する
    - TPMLWindow は TPMLOwnedObject。アプリが Free してもよいし、
      TPMLVideoSystem の破棄に任せてもよい

  NOT RESOLVED:
    - GL / Vulkan / Renderer / Clipboard / Cursors は未実装（#33、#39、#41、#38）
    - フルスクリーン、ウィンドウ位置、不透明度、グラブ、ヒットテストは
      対応する能力と一緒に追加する
    - ディスプレイの hotplug は DisplaysChanged で列挙をやり直すだけ。
      個々の DisplayAdded / DisplayRemoved イベントは未実装

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Events,
  PaPiMeLa.Video.Backend;

type
  TPMLVideoSystem = class;

  TPMLWindowOptions = record
    Title        : String;
    Width, Height: Integer;
    Flags        : TPMLWindowFlags;
    class function Make(const ATitle: String; AWidth, AHeight: Integer): TPMLWindowOptions; static;
    function WithTitle(const ATitle: String): TPMLWindowOptions;
    function WithSize(AWidth, AHeight: Integer): TPMLWindowOptions;
    function Resizable: TPMLWindowOptions;
    function Borderless: TPMLWindowOptions;
    function HighPixelDensity: TPMLWindowOptions;
    function StartHidden: TPMLWindowOptions;
  end;

  TPMLDisplay = class sealed(TPMLSystemObject)
  strict private
    FBackend: TPMLDisplayBackend;
    FID     : LongWord;
    function GetName: String;
    function GetBounds: TPMLRect;
    function GetUsableBounds: TPMLRect;
    function GetContentScale: Single;
    function GetDesktopMode: TPMLDisplayMode;
  public
    constructor Create(AOwner: TPMLVideoSystem; AID: LongWord;
      ABackend: TPMLDisplayBackend);
    destructor Destroy; override;
    property ID          : LongWord read FID;
    property Name        : String read GetName;
    property Bounds      : TPMLRect read GetBounds;
    property UsableBounds: TPMLRect read GetUsableBounds;
    property ContentScale: Single read GetContentScale;
    property DesktopMode : TPMLDisplayMode read GetDesktopMode;
    property Backend     : TPMLDisplayBackend read FBackend;
  end;

  TPMLWindow = class sealed(TPMLOwnedObject)
  strict private
    FSystem : TPMLVideoSystem;
    FBackend: TPMLWindowBackend;
    FID     : TPMLWindowID;
    FTitle  : String;
    FWidth, FHeight: Integer;
    FFlags  : TPMLWindowFlags;
    FCloseRequested: Boolean;
    FMouseGrab      : Boolean;
    FRelativeMouseMode: Boolean;
    FMouseRect      : TPMLRect;
    procedure SetTitle(const AValue: String);
    procedure SetSize(AWidth, AHeight: Integer);
    procedure SetMouseGrab(AValue: Boolean);
    procedure SetRelativeMouseMode(AValue: Boolean);
    procedure SetMouseRect(const AValue: TPMLRect);
    function  GetSizeInPixels: TPMLRect;
    function  GetDisplayScale: Single;
  protected
    procedure OwnerDestroying; override;
  private
    // TPMLVideoSystem が Sink 経由で更新する。ユニット内限定。
    procedure ApplyResized(AWidth, AHeight: Integer);
    procedure ApplyFlags(AFlags: TPMLWindowFlags);
    procedure ApplyCloseRequested;
  public
    constructor Create(ASystem: TPMLVideoSystem; AID: TPMLWindowID;
      ABackend: TPMLWindowBackend; const AOptions: TPMLWindowOptions);
    destructor Destroy; override;

    procedure Show;
    procedure Hide;
    procedure Maximize;
    procedure Minimize;
    procedure Restore;
    procedure RaiseWindow;
    procedure Sync;
    procedure SetMinimumSize(AWidth, AHeight: Integer);
    procedure SetMaximumSize(AWidth, AHeight: Integer);

    // ソフトウェアフレームバッファ。SoftwareFramebuffer 能力が必要。
    function  LockFramebuffer(out APixels: Pointer; out APitch: Integer): Boolean;
    procedure UpdateFramebuffer;

    function  NativeHandles: TPMLNativeWindowHandles;

    property ID      : TPMLWindowID read FID;
    property Title   : String read FTitle write SetTitle;
    property Width   : Integer read FWidth;
    property Height  : Integer read FHeight;
    property Flags   : TPMLWindowFlags read FFlags;
    property SizeInPixels: TPMLRect read GetSizeInPixels;
    property DisplayScale: Single read GetDisplayScale;
    // ポインタの拘束。能力 MouseConfine / RelativeMouse が無ければ例外になる。
    property MouseGrab: Boolean read FMouseGrab write SetMouseGrab;
    property RelativeMouseMode: Boolean
      read FRelativeMouseMode write SetRelativeMouseMode;
    // ウィンドウ内の閉じ込め矩形。空 = ウィンドウ全体。
    property MouseRect: TPMLRect read FMouseRect write SetMouseRect;
    property CloseRequested: Boolean read FCloseRequested;
    property Backend : TPMLWindowBackend read FBackend;
  end;

  { カーソルの公開窓口。TPMLVideoSystem.Cursors で取る。

    WHAT:
      システムカーソルの選択と表示 / 非表示。

    WHY:
      バックエンドの部品（TPMLCursorBackend）はウィンドウ単位ではなく
      デバイス単位なので、ウィンドウではなく TPMLVideoSystem 側に置く。

    NOT RESOLVED:
      任意のピクセルからカーソルを作る `Create(Surface, HotX, HotY)`（設計 4.2）は
      未実装。形状は cursor-shape-v1 が持つ 20 種類から選ぶ。 }
  TPMLCursorSystem = class sealed(TPMLSystemObject)
  strict private
    FSystem : TPMLVideoSystem;
    FBackend: TPMLCursorBackend;     // nil = カーソルを扱えないバックエンド
    FKind   : TPMLSystemCursor;
    FVisible: Boolean;
    procedure SetSystemCursor(AValue: TPMLSystemCursor);
    procedure SetVisible(AValue: Boolean);
    function  GetCanChooseShape: Boolean;
  public
    constructor Create(ASystem: TPMLVideoSystem; ABackend: TPMLCursorBackend);
    // 形状を選べるか。False でも表示 / 非表示は使える。
    property CanChooseShape: Boolean read GetCanChooseShape;
    property SystemCursor: TPMLSystemCursor read FKind write SetSystemCursor;
    property Visible: Boolean read FVisible write SetVisible;
  end;

  TPMLWindowList = array of TPMLWindow;
  TPMLDisplayList = array of TPMLDisplay;

  TPMLVideoSystem = class sealed(TPMLSystemObject, IPMLVideoSink, IPMLEventPumpSource)
  strict private
    FQueue        : TPMLEventQueue;
    FBackend      : TPMLVideoBackend;
    FDisplays     : TPMLDisplayList;
    FWindows      : TPMLWindowList;
    FNextWindowID : TPMLWindowID;
    FSelectedName : String;
    FCursors      : TPMLCursorSystem;
    function  GetCapabilities: TPMLVideoCapabilities;
    procedure RefreshDisplays;
    procedure PushWindowEvent(AKind: TPMLEventKind; AWindowID: TPMLWindowID;
      AData1: Int32 = 0; AData2: Int32 = 0);
  private
    procedure RemoveWindow(AWindow: TPMLWindow);
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject;
      AQueue: TPMLEventQueue; const APreferred: String = '');
    destructor Destroy; override;

    function  CreateWindow(const AOptions: TPMLWindowOptions): TPMLWindow;
    function  WindowFromID(AID: TPMLWindowID): TPMLWindow;
    function  PrimaryDisplay: TPMLDisplay;
    procedure Require(ACapability: TPMLVideoCapability; const AWhat: String);

    // IPMLEventPumpSource
    function  PumpSourceName: String;
    procedure PumpEvents(ATimeoutMs: Integer);

    // IPMLVideoSink
    procedure WindowResized(AWindowID: TPMLWindowID; AWidth, AHeight: Integer);
    procedure WindowPixelSizeChanged(AWindowID: TPMLWindowID; AWidth, AHeight: Integer);
    procedure WindowStateChanged(AWindowID: TPMLWindowID; AFlags: TPMLWindowFlags);
    procedure WindowCloseRequested(AWindowID: TPMLWindowID);
    procedure WindowExposed(AWindowID: TPMLWindowID);
    procedure WindowDisplayScaleChanged(AWindowID: TPMLWindowID; AScale: Single);
    procedure DisplaysChanged;
    procedure BackendLost(const AReason: String);

    property BackendName : String read FSelectedName;
    property Backend     : TPMLVideoBackend read FBackend;
    property Displays    : TPMLDisplayList read FDisplays;
    property Windows     : TPMLWindowList read FWindows;
    property Cursors     : TPMLCursorSystem read FCursors;
    property Capabilities: TPMLVideoCapabilities read GetCapabilities;
  end;

implementation

uses
  PaPiMeLa.Video.Wayland;

{ TPMLWindowOptions }

class function TPMLWindowOptions.Make(const ATitle: String;
  AWidth, AHeight: Integer): TPMLWindowOptions;
begin
  Result.Title := ATitle;
  Result.Width := AWidth;
  Result.Height := AHeight;
  Result.Flags := [];
end;

function TPMLWindowOptions.WithTitle(const ATitle: String): TPMLWindowOptions;
begin
  Result := Self;
  Result.Title := ATitle;
end;

function TPMLWindowOptions.WithSize(AWidth, AHeight: Integer): TPMLWindowOptions;
begin
  Result := Self;
  Result.Width := AWidth;
  Result.Height := AHeight;
end;

function TPMLWindowOptions.Resizable: TPMLWindowOptions;
begin
  Result := Self;
  Include(Result.Flags, TPMLWindowFlag.Resizable);
end;

function TPMLWindowOptions.Borderless: TPMLWindowOptions;
begin
  Result := Self;
  Include(Result.Flags, TPMLWindowFlag.Borderless);
end;

function TPMLWindowOptions.HighPixelDensity: TPMLWindowOptions;
begin
  Result := Self;
  Include(Result.Flags, TPMLWindowFlag.HighPixelDensity);
end;

function TPMLWindowOptions.StartHidden: TPMLWindowOptions;
begin
  Result := Self;
  Include(Result.Flags, TPMLWindowFlag.Hidden);
end;

{ TPMLDisplay }

constructor TPMLDisplay.Create(AOwner: TPMLVideoSystem; AID: LongWord;
  ABackend: TPMLDisplayBackend);
begin
  inherited Create(AOwner.ContextRef, AOwner);
  FID := AID;
  FBackend := ABackend;
end;

destructor TPMLDisplay.Destroy;
begin
  FreeAndNil(FBackend);
  inherited Destroy;
end;

function TPMLDisplay.GetName: String;
begin
  Result := FBackend.GetName;
end;

function TPMLDisplay.GetBounds: TPMLRect;
begin
  Result := FBackend.GetBounds;
end;

function TPMLDisplay.GetUsableBounds: TPMLRect;
begin
  Result := FBackend.GetUsableBounds;
end;

function TPMLDisplay.GetContentScale: Single;
begin
  Result := FBackend.GetContentScale;
end;

function TPMLDisplay.GetDesktopMode: TPMLDisplayMode;
begin
  Result := FBackend.GetDesktopMode;
end;

{ TPMLWindow }

constructor TPMLWindow.Create(ASystem: TPMLVideoSystem; AID: TPMLWindowID;
  ABackend: TPMLWindowBackend; const AOptions: TPMLWindowOptions);
begin
  inherited Create(ASystem.ContextRef, ASystem);
  FSystem := ASystem;
  FID := AID;
  FBackend := ABackend;
  FTitle := AOptions.Title;
  FWidth := AOptions.Width;
  FHeight := AOptions.Height;
  FFlags := AOptions.Flags;
end;

destructor TPMLWindow.Destroy;
begin
  if Assigned(FSystem) then
    FSystem.RemoveWindow(Self);
  FreeAndNil(FBackend);
  inherited Destroy;
end;

procedure TPMLWindow.OwnerDestroying;
begin
  FSystem := nil;   // 所有者が先に死ぬので RemoveWindow を呼ばない
  inherited OwnerDestroying;
end;

procedure TPMLWindow.ApplyResized(AWidth, AHeight: Integer);
begin
  FWidth := AWidth;
  FHeight := AHeight;
end;

{ バックエンドが報告した状態フラグを取り込む。

  WHAT:
    バックエンドが知っているフラグだけを差し替え、公開層が持つフラグ
    （生成時の指定、ポインタ拘束の要求）はそのまま残す。

  WHY:
    以前は集合をまるごと置き換えていたため、最初の configure で Resizable や
    MouseGrabbed が消えていた（不具合 D-24）。どちらが持ち主かはフラグごとに
    決まっているので、境界を定数で明示する。 }
procedure TPMLWindow.ApplyFlags(AFlags: TPMLWindowFlags);
const
  // コンポジタしか知らないフラグ。これ以外は公開層が持つ。
  BackendOwned = [TPMLWindowFlag.Maximized, TPMLWindowFlag.Fullscreen,
    TPMLWindowFlag.InputFocus, TPMLWindowFlag.Minimized,
    TPMLWindowFlag.Occluded];
begin
  FFlags := (FFlags - BackendOwned) + (AFlags * BackendOwned);
end;

procedure TPMLWindow.ApplyCloseRequested;
begin
  FCloseRequested := True;
end;

procedure TPMLWindow.SetTitle(const AValue: String);
begin
  CheckMainThread;
  FTitle := AValue;
  FBackend.SetTitle(AValue);
end;

procedure TPMLWindow.SetSize(AWidth, AHeight: Integer);
begin
  CheckMainThread;
  FBackend.SetSize(AWidth, AHeight);
end;

function TPMLWindow.GetSizeInPixels: TPMLRect;
var
  W, H: Integer;
begin
  FBackend.GetSizeInPixels(W, H);
  Result := TPMLRect.Make(0, 0, W, H);
end;

function TPMLWindow.GetDisplayScale: Single;
begin
  Result := FBackend.GetDisplayScale;
end;

procedure TPMLWindow.Show;
begin
  CheckMainThread;
  FBackend.Show;
  Exclude(FFlags, TPMLWindowFlag.Hidden);
end;

procedure TPMLWindow.Hide;
begin
  CheckMainThread;
  FBackend.Hide;
  Include(FFlags, TPMLWindowFlag.Hidden);
end;

procedure TPMLWindow.Maximize;
begin
  CheckMainThread;
  FBackend.Maximize;
end;

procedure TPMLWindow.Minimize;
begin
  CheckMainThread;
  FBackend.Minimize;
end;

procedure TPMLWindow.Restore;
begin
  CheckMainThread;
  FBackend.Restore;
end;

procedure TPMLWindow.RaiseWindow;
begin
  CheckMainThread;
  FBackend.RaiseWindow;
end;

procedure TPMLWindow.Sync;
begin
  CheckMainThread;
  FBackend.Sync;
end;


{ ポインタをこのウィンドウに閉じ込める。

  Flags の MouseGrabbed も併せて更新する。実際に閉じ込めが有効になるのは
  ウィンドウがキーボードフォーカスを持っているときだけで、それはバックエンドが
  判断する。ここは「要求」を記録するだけ。 }
procedure TPMLWindow.SetMouseGrab(AValue: Boolean);
begin
  CheckMainThread;
  if FMouseGrab = AValue then
    Exit;
  FSystem.Require(TPMLVideoCapability.MouseConfine, 'Mouse grab');
  FMouseGrab := AValue;
  if AValue then
    Include(FFlags, TPMLWindowFlag.MouseGrabbed)
  else
    Exclude(FFlags, TPMLWindowFlag.MouseGrabbed);
  FBackend.SetMouseGrab(AValue);
end;

{ 相対マウスモード。ポインタを固定して移動量だけを受け取る。

  有効な間 MouseMotion の X / Y は動かず、XRel / YRel だけが変化する。
  カーソルの表示は変えない（#38 の TPMLCursorBackend を待つ）。 }
procedure TPMLWindow.SetRelativeMouseMode(AValue: Boolean);
begin
  CheckMainThread;
  if FRelativeMouseMode = AValue then
    Exit;
  FSystem.Require(TPMLVideoCapability.RelativeMouse, 'Relative mouse mode');
  FRelativeMouseMode := AValue;
  FBackend.SetRelativeMouseMode(AValue);
end;

procedure TPMLWindow.SetMouseRect(const AValue: TPMLRect);
begin
  CheckMainThread;
  FSystem.Require(TPMLVideoCapability.MouseConfine, 'Mouse confinement rectangle');
  FMouseRect := AValue;
  FBackend.SetMouseRect(AValue);
end;

procedure TPMLWindow.SetMinimumSize(AWidth, AHeight: Integer);
begin
  FBackend.SetMinimumSize(AWidth, AHeight);
end;

procedure TPMLWindow.SetMaximumSize(AWidth, AHeight: Integer);
begin
  FBackend.SetMaximumSize(AWidth, AHeight);
end;

function TPMLWindow.LockFramebuffer(out APixels: Pointer; out APitch: Integer): Boolean;
begin
  FSystem.Require(TPMLVideoCapability.SoftwareFramebuffer, 'software framebuffer');
  Result := FBackend.CreateFramebuffer(APixels, APitch);
end;

procedure TPMLWindow.UpdateFramebuffer;
begin
  FBackend.UpdateFramebuffer;
end;

function TPMLWindow.NativeHandles: TPMLNativeWindowHandles;
begin
  Result := FBackend.NativeHandles;
end;


{ TPMLCursorSystem }

constructor TPMLCursorSystem.Create(ASystem: TPMLVideoSystem;
  ABackend: TPMLCursorBackend);
begin
  inherited Create(ASystem.ContextRef, ASystem);
  FSystem := ASystem;
  FBackend := ABackend;
  FKind := TPMLSystemCursor.Arrow;
  FVisible := True;
end;

function TPMLCursorSystem.GetCanChooseShape: Boolean;
begin
  Result := (FBackend <> nil)
        and (TPMLVideoCapability.CursorShape in FSystem.Capabilities);
end;

procedure TPMLCursorSystem.SetSystemCursor(AValue: TPMLSystemCursor);
begin
  CheckMainThread;
  if FKind = AValue then
    Exit;
  FSystem.Require(TPMLVideoCapability.CursorShape, 'System cursor shapes');
  FKind := AValue;
  FBackend.SetSystemCursor(AValue);
end;

{ 表示 / 非表示は cursor-shape-v1 を必要としない。wl_pointer.set_cursor だけで済む。 }
procedure TPMLCursorSystem.SetVisible(AValue: Boolean);
begin
  CheckMainThread;
  if FVisible = AValue then
    Exit;
  if FBackend = nil then
    raise EPMLUnsupported.CreateNative(
      'Cursor visibility is not supported by this video backend', 0,
      FSystem.BackendName);
  FVisible := AValue;
  FBackend.SetVisible(AValue);
end;

{ TPMLVideoSystem }

constructor TPMLVideoSystem.Create(AContextRef: TObject; AOwner: TPMLObject;
  AQueue: TPMLEventQueue; const APreferred: String);
var
  Wanted: String;

  function TryBackend(ACandidate: TPMLVideoBackend): Boolean;
  begin
    Result := False;
    if ACandidate = nil then
      Exit;
    if ((Wanted <> '') and (LowerCase(ACandidate.BackendName) <> Wanted))
      or (not ACandidate.Connect(Self as IPMLVideoSink)) then
    begin
      ACandidate.Free;
      Exit;
    end;
    FBackend := ACandidate;
    FSelectedName := ACandidate.BackendName;
    Result := True;
  end;

begin
  inherited Create(AContextRef, AOwner);
  FQueue := AQueue;
  FNextWindowID := 1;
  Wanted := LowerCase(Trim(APreferred));
  if Wanted = '' then
    Wanted := LowerCase(Trim(GetEnvironmentVariable('PAPIMELA_VIDEO')));

  if not TryBackend(TPMLWaylandVideoBackend.Create(AContextRef, Self, AQueue)) then
    raise EPMLVideoError.Create('no video backend could be selected');

  RefreshDisplays;
  // カーソル部品はバックエンドが Connect のときに用意する。無い場合もある。
  FCursors := TPMLCursorSystem.Create(Self, FBackend.Cursors);
  FQueue.RegisterPumpSource(Self as IPMLEventPumpSource);
end;

destructor TPMLVideoSystem.Destroy;
var
  I: Integer;
begin
  if Assigned(FQueue) then
    FQueue.UnregisterPumpSource(Self as IPMLEventPumpSource);
  // ウィンドウはアプリが Free してもよいので、残っているものだけ処理する。
  for I := High(FWindows) downto 0 do
    if Assigned(FWindows[I]) then
      FWindows[I].OwnerDestroying;
  SetLength(FWindows, 0);
  for I := High(FDisplays) downto 0 do
    FDisplays[I].Free;
  SetLength(FDisplays, 0);
  // 公開窓口はバックエンドの部品を借りているので、切断より先に捨てる。
  FreeAndNil(FCursors);
  if Assigned(FBackend) then
  begin
    FBackend.Disconnect;
    FreeAndNil(FBackend);
  end;
  inherited Destroy;
end;

function TPMLVideoSystem.GetCapabilities: TPMLVideoCapabilities;
begin
  if Assigned(FBackend) then
    Result := FBackend.Capabilities
  else
    Result := [];
end;

procedure TPMLVideoSystem.Require(ACapability: TPMLVideoCapability;
  const AWhat: String);
begin
  if not (ACapability in GetCapabilities) then
    raise EPMLUnsupported.CreateNative(
      Format('%s is not supported by this video backend', [AWhat]), 0,
      FSelectedName);
end;

procedure TPMLVideoSystem.RefreshDisplays;
var
  Backends: TPMLDisplayBackends;
  I: Integer;
begin
  for I := High(FDisplays) downto 0 do
    FDisplays[I].Free;
  SetLength(FDisplays, 0);
  Backends := FBackend.EnumerateDisplays;
  SetLength(FDisplays, Length(Backends));
  for I := 0 to High(Backends) do
    FDisplays[I] := TPMLDisplay.Create(Self, LongWord(I + 1), Backends[I]);
end;

function TPMLVideoSystem.PrimaryDisplay: TPMLDisplay;
begin
  if Length(FDisplays) = 0 then
    Exit(nil);
  Result := FDisplays[0];
end;

function TPMLVideoSystem.CreateWindow(const AOptions: TPMLWindowOptions): TPMLWindow;
var
  WB: TPMLWindowBackend;
  ID: TPMLWindowID;
begin
  CheckMainThread;
  ID := FNextWindowID;
  Inc(FNextWindowID);
  WB := FBackend.CreateWindowBackend(ID, AOptions.Title,
    AOptions.Width, AOptions.Height, AOptions.Flags);
  Result := TPMLWindow.Create(Self, ID, WB, AOptions);
  SetLength(FWindows, Length(FWindows) + 1);
  FWindows[High(FWindows)] := Result;
  if not (TPMLWindowFlag.Hidden in AOptions.Flags) then
    Result.Show;
end;

procedure TPMLVideoSystem.RemoveWindow(AWindow: TPMLWindow);
var
  I, J: Integer;
begin
  for I := 0 to High(FWindows) do
    if FWindows[I] = AWindow then
    begin
      PushWindowEvent(TPMLEventKind.WindowDestroyed, AWindow.ID);
      for J := I to High(FWindows) - 1 do
        FWindows[J] := FWindows[J + 1];
      SetLength(FWindows, Length(FWindows) - 1);
      Exit;
    end;
end;

function TPMLVideoSystem.WindowFromID(AID: TPMLWindowID): TPMLWindow;
var
  I: Integer;
begin
  for I := 0 to High(FWindows) do
    if FWindows[I].ID = AID then
      Exit(FWindows[I]);
  Result := nil;
end;

function TPMLVideoSystem.PumpSourceName: String;
begin
  Result := 'video:' + FSelectedName;
end;

procedure TPMLVideoSystem.PumpEvents(ATimeoutMs: Integer);
begin
  if not Assigned(FBackend) then
    Exit;
  if ATimeoutMs > 0 then
    FBackend.WaitEvents(ATimeoutMs)
  else
    FBackend.PumpEvents;
end;

procedure TPMLVideoSystem.PushWindowEvent(AKind: TPMLEventKind;
  AWindowID: TPMLWindowID; AData1: Int32; AData2: Int32);
var
  Ev: TPMLEvent;
begin
  FillChar(Ev.Window, SizeOf(Ev.Window), 0);
  Ev.Kind := AKind;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := AWindowID;
  Ev.Text := '';
  Ev.Segments := nil;
  Ev.Strings := nil;
  Ev.Window.Data1 := AData1;
  Ev.Window.Data2 := AData2;
  FQueue.Push(Ev);
end;

procedure TPMLVideoSystem.WindowResized(AWindowID: TPMLWindowID;
  AWidth, AHeight: Integer);
var
  W: TPMLWindow;
begin
  W := WindowFromID(AWindowID);
  if Assigned(W) then
    W.ApplyResized(AWidth, AHeight);
  PushWindowEvent(TPMLEventKind.WindowResized, AWindowID, AWidth, AHeight);
end;

procedure TPMLVideoSystem.WindowPixelSizeChanged(AWindowID: TPMLWindowID;
  AWidth, AHeight: Integer);
begin
  PushWindowEvent(TPMLEventKind.WindowPixelSizeChanged, AWindowID, AWidth, AHeight);
end;

procedure TPMLVideoSystem.WindowStateChanged(AWindowID: TPMLWindowID;
  AFlags: TPMLWindowFlags);
var
  W: TPMLWindow;
begin
  W := WindowFromID(AWindowID);
  if Assigned(W) then
    W.ApplyFlags(AFlags);
  if TPMLWindowFlag.Maximized in AFlags then
    PushWindowEvent(TPMLEventKind.WindowMaximized, AWindowID)
  else if TPMLWindowFlag.Minimized in AFlags then
    PushWindowEvent(TPMLEventKind.WindowMinimized, AWindowID)
  else
    PushWindowEvent(TPMLEventKind.WindowRestored, AWindowID);
end;

procedure TPMLVideoSystem.WindowCloseRequested(AWindowID: TPMLWindowID);
var
  W: TPMLWindow;
begin
  W := WindowFromID(AWindowID);
  if Assigned(W) then
    W.ApplyCloseRequested;
  PushWindowEvent(TPMLEventKind.WindowCloseRequested, AWindowID);
end;

procedure TPMLVideoSystem.WindowExposed(AWindowID: TPMLWindowID);
begin
  PushWindowEvent(TPMLEventKind.WindowExposed, AWindowID);
end;

procedure TPMLVideoSystem.WindowDisplayScaleChanged(AWindowID: TPMLWindowID;
  AScale: Single);
begin
  PushWindowEvent(TPMLEventKind.WindowDisplayScaleChanged, AWindowID,
    Round(AScale * 1000));
end;

procedure TPMLVideoSystem.DisplaysChanged;
begin
  RefreshDisplays;
  PushWindowEvent(TPMLEventKind.DisplayAdded, 0);
end;

procedure TPMLVideoSystem.BackendLost(const AReason: String);
begin
  FQueue.PushSimple(TPMLEventKind.BackendLost);
  raise EPMLBackendLost.CreateNative('video backend lost', 0, FSelectedName, AReason);
end;

end.
