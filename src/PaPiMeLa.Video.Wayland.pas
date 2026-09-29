{
  PaPiMeLa.Video.Wayland — Wayland ビデオバックエンド

  Origin : partially ported from SDL (src/video/wayland/SDL_waylandvideo.c)
           Scope: wl_display の安全な読み取り手順（prepare_read / read_events /
           cancel_read を poll と組み合わせる）と、出力メタデータの解釈。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.2、§11 #35

  WHAT:
    TPMLVideoBackend の Wayland 実装。接続、ディスプレイ列挙、ウィンドウ生成、
    イベントポンプ。

  WHY:
    SDL_waylandeventthread.c の読み取りスレッドは初回では移植しない（§3.2）。
    メインスレッドで dispatch_pending + poll(2) を行う。prepare_read /
    read_events / cancel_read の組み合わせは、複数スレッドが同じ wl_display を
    読むときに取りこぼさないための libwayland の規約で、単一スレッドでも
    この手順に従っておく。

  RESOLVED:
    - wl_display_get_error が 0 以外になったら回復不能。Sink 経由で BackendLost
    - 能力集合は Connect 後に確定する（拡張の有無で変わる）

  NOT RESOLVED:
    - シートはキーボード / ポインタ / タッチを実装済み。タブレット（tablet-v2）は未対応
    - GL / Vulkan / クリップボードの部品は nil のまま（#33、#38、#39）。
      カーソル部品は cursor-shape-v1 で実装済みだが、任意ピクセルのカーソルは未対応
    - ディスプレイ hotplug は DisplaysChanged で全列挙をやり直すだけ

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Wayland;

{$I papimela.inc}

interface

uses
  SysUtils, BaseUnix, Unix,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video.Wayland.Types,
  PaPiMeLa.Video.Wayland.Window,
  PaPiMeLa.Video.Wayland.Seat,
  PaPiMeLa.Video.Wayland.Cursor,
  PaPiMeLa.Events,
  PaPiMeLa.Platform.XKB,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  TPMLWaylandDisplayBackend = class(TPMLDisplayBackend)
  strict private
    FOutput: TPMLWaylandOutput;
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject;
      AOutput: TPMLWaylandOutput);
    function GetName: String; override;
    function GetBounds: TPMLRect; override;
    function GetContentScale: Single; override;
    function GetDesktopMode: TPMLDisplayMode; override;
  end;

  TPMLWaylandVideoBackend = class(TPMLVideoBackend)
  strict private
    FConn : TPMLWaylandConnection;
    FQueue: TPMLEventQueue;
    FSeats: TPMLWaylandSeats;
    procedure CheckConnectionAlive;
    procedure HandleSeatBound(ASeat: Pwl_seat);
    procedure HandleGrabsChanged(AWindowID: TPMLWindowID);
    function  GetSeats: TPMLWaylandSeats;
    procedure DestroySeats;
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject;
      AQueue: TPMLEventQueue);
    destructor Destroy; override;

    function  BackendName: String; override;
    function  Connect(ASink: IPMLVideoSink): Boolean; override;
    procedure Disconnect; override;
    function  EnumerateDisplays: TPMLDisplayBackends; override;
    function  CreateWindowBackend(AWindowID: TPMLWindowID; const ATitle: String;
      AWidth, AHeight: Integer; AFlags: TPMLWindowFlags): TPMLWindowBackend; override;
    procedure PumpEvents; override;
    procedure WaitEvents(ATimeoutMs: Integer); override;
    procedure WakeEventLoop; override;

    // IME バックエンド（TextInput.WaylandTI、#49）が seat を得るために使う。
    property Connection: TPMLWaylandConnection read FConn;
    // テストと診断用。拘束の状態はシートが持つ。
    property Seats: TPMLWaylandSeats read FSeats;
  end;

implementation

{ TPMLWaylandDisplayBackend }

constructor TPMLWaylandDisplayBackend.Create(AContextRef: TObject;
  AOwner: TPMLObject; AOutput: TPMLWaylandOutput);
begin
  inherited Create(AContextRef, AOwner);
  FOutput := AOutput;
end;

function TPMLWaylandDisplayBackend.GetName: String;
begin
  Result := FOutput.OutputName;
  if Result = '' then
    Result := 'wayland-output';
end;

function TPMLWaylandDisplayBackend.GetBounds: TPMLRect;
begin
  // wl_output の論理座標。scale を掛けた物理ピクセルではない。
  Result := TPMLRect.Make(FOutput.X, FOutput.Y,
    FOutput.Width div FOutput.ScaleFactor, FOutput.Height div FOutput.ScaleFactor);
end;

function TPMLWaylandDisplayBackend.GetContentScale: Single;
begin
  Result := FOutput.ScaleFactor;
end;

function TPMLWaylandDisplayBackend.GetDesktopMode: TPMLDisplayMode;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Width := FOutput.Width;
  Result.Height := FOutput.Height;
  Result.PixelDensity := FOutput.ScaleFactor;
  Result.RefreshNumerator := FOutput.RefreshMHz;
  Result.RefreshDenominator := 1000;
  if FOutput.RefreshMHz > 0 then
    Result.RefreshRate := FOutput.RefreshMHz / 1000.0;
end;

{ TPMLWaylandVideoBackend }

constructor TPMLWaylandVideoBackend.Create(AContextRef: TObject; AOwner: TPMLObject;
  AQueue: TPMLEventQueue);
begin
  inherited Create(AContextRef, AOwner);
  FQueue := AQueue;
  FConn := TPMLWaylandConnection.Create;
end;

destructor TPMLWaylandVideoBackend.Destroy;
begin
  FreeAndNil(FCursors);
  DestroySeats;
  FreeAndNil(FConn);
  inherited Destroy;
end;

function TPMLWaylandVideoBackend.BackendName: String;
begin
  Result := 'wayland';
end;

function TPMLWaylandVideoBackend.Connect(ASink: IPMLVideoSink): Boolean;
var
  I: Integer;
begin
  // xkb が無ければキーは扱えないが、ウィンドウ表示自体は成立するので
  // 失敗しても接続は続ける（シートを作らないだけ）。
  if PMLXKBLoad then
    FConn.OnSeatBound := @HandleSeatBound;
  FConn.OnGrabsChanged := @HandleGrabsChanged;
  Result := FConn.Connect;
  if not Result then
    Exit;
  FSink := ASink;
  FCapabilities := FConn.Capabilities;

  // タッチの有無は接続ではなくシートが知っている。wl_seat.capabilities は
  // Connect の roundtrip で配送済みなので、ここで能力へ写せる。
  for I := 0 to High(FSeats) do
    if FSeats[I].HasTouch then
      Include(FCapabilities, TPMLVideoCapability.Touch);

  // カーソル部品。cursor-shape-v1 が無くても表示 / 非表示は使えるので常に作る。
  FCursors := TPMLWaylandCursorBackend.Create(ContextRef, Self, @GetSeats);
end;

procedure TPMLWaylandVideoBackend.Disconnect;
begin
  // カーソル部品はシートを触るので、シートより先に捨てる。
  FreeAndNil(FCursors);
  DestroySeats;
  FConn.Disconnect;
  inherited Disconnect;
end;

{ レジストリが wl_seat を束縛した瞬間に呼ばれる。

  ここでリスナーを付けないと、Connect の中の roundtrip が capabilities を
  配送してしまい、キーボードを取り出す機会を失う（不具合 D-21）。 }
procedure TPMLWaylandVideoBackend.HandleSeatBound(ASeat: Pwl_seat);
begin
  SetLength(FSeats, Length(FSeats) + 1);
  // 識別子は 1 から振る。0 は「デバイス無し」の意味に取っておく。
  FSeats[High(FSeats)] := TPMLWaylandSeat.Create(FQueue, FConn, ASeat,
    LongWord(Length(FSeats)));
end;

{ ウィンドウの拘束要求が変わった。ポインタフォーカスを持つシートだけが張り直す。

  拘束オブジェクトは wl_pointer 単位なので、ウィンドウが直接張ることはできない。
  ウィンドウ → 接続 → ここ → シート、という順で伝わる。 }
procedure TPMLWaylandVideoBackend.HandleGrabsChanged(AWindowID: TPMLWindowID);
var
  I: Integer;
begin
  for I := 0 to High(FSeats) do
    FSeats[I].UpdateGrabs(AWindowID);
end;

{ カーソル部品にシート一覧を貸す。Cursor ユニットは Seat を参照できるが、
  シートを所有しているのはこちらなので、取得だけを関数で渡す。 }
function TPMLWaylandVideoBackend.GetSeats: TPMLWaylandSeats;
begin
  Result := FSeats;
end;

procedure TPMLWaylandVideoBackend.DestroySeats;
var
  I: Integer;
begin
  if Length(FSeats) = 0 then
    Exit;
  for I := 0 to High(FSeats) do
    FSeats[I].Free;
  SetLength(FSeats, 0);
  PMLXKBUnload;
end;

function TPMLWaylandVideoBackend.EnumerateDisplays: TPMLDisplayBackends;
var
  I: Integer;
begin
  SetLength(Result, Length(FConn.Outputs));
  for I := 0 to High(FConn.Outputs) do
    Result[I] := TPMLWaylandDisplayBackend.Create(ContextRef, Self, FConn.Outputs[I]);
end;

function TPMLWaylandVideoBackend.CreateWindowBackend(AWindowID: TPMLWindowID;
  const ATitle: String; AWidth, AHeight: Integer;
  AFlags: TPMLWindowFlags): TPMLWindowBackend;
begin
  Result := TPMLWaylandWindowBackend.Create(ContextRef, Self, FConn, FSink,
    AWindowID, ATitle, AWidth, AHeight, AFlags);
end;

procedure TPMLWaylandVideoBackend.CheckConnectionAlive;
var
  Err: LongInt;
begin
  Err := wl_display_get_error(FConn.Display);
  if (Err <> 0) and Assigned(FSink) then
    FSink.BackendLost(Format('wl_display_get_error = %d', [Err]));
end;

procedure TPMLWaylandVideoBackend.PumpEvents;
begin
  if FConn.Display = nil then
    Exit;
  wl_display_dispatch_pending(FConn.Display);
  wl_display_flush(FConn.Display);
  // 溜まっている分だけ取り込む。待たない。
  WaitEvents(0);
end;

{ 安全な読み取り手順（libwayland の規約）:

  1. prepare_read が 0 を返すまで dispatch_pending でキューを空にする
  2. flush して送信を済ませる
  3. poll で fd を待つ
  4. 読めるなら read_events、そうでなければ cancel_read
  5. dispatch_pending で配送する }
procedure TPMLWaylandVideoBackend.WaitEvents(ATimeoutMs: Integer);
var
  FDS: TFDSet;
  PFD: TPollFd;
  R  : LongInt;
  I, M, RepeatMs: Integer;
begin
  if FConn.Display = nil then
    Exit;

  // キーリピートの期限が近ければ、その分だけ待ちを短くする。
  // そうしないとリピートが poll のタイムアウトまで遅れる。
  RepeatMs := -1;
  for I := 0 to High(FSeats) do
  begin
    M := FSeats[I].MillisecondsUntilRepeat;
    if (M >= 0) and ((RepeatMs < 0) or (M < RepeatMs)) then
      RepeatMs := M;
  end;
  if (RepeatMs >= 0) and ((ATimeoutMs < 0) or (RepeatMs < ATimeoutMs)) then
    ATimeoutMs := RepeatMs;

  while wl_display_prepare_read(FConn.Display) <> 0 do
    wl_display_dispatch_pending(FConn.Display);
  wl_display_flush(FConn.Display);

  FillChar(FDS, SizeOf(FDS), 0);
  PFD.fd := wl_display_get_fd(FConn.Display);
  PFD.events := POLLIN;
  PFD.revents := 0;
  R := fppoll(@PFD, 1, ATimeoutMs);

  if (R > 0) and ((PFD.revents and POLLIN) <> 0) then
  begin
    if wl_display_read_events(FConn.Display) < 0 then
    begin
      CheckConnectionAlive;
      Exit;
    end;
  end
  else
    wl_display_cancel_read(FConn.Display);

  wl_display_dispatch_pending(FConn.Display);

  // 期限の来たキーリピートを発火させる。
  for I := 0 to High(FSeats) do
    FSeats[I].ProcessRepeat;

  CheckConnectionAlive;
end;

procedure TPMLWaylandVideoBackend.WakeEventLoop;
begin
  // 起こす専用の eventfd は未導入（Events の NOT RESOLVED と同じ理由）。
  // flush だけ行い、待ちは poll のタイムアウトで抜ける。
  if FConn.Display <> nil then
    wl_display_flush(FConn.Display);
end;

end.
