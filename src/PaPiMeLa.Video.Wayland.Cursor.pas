{
  PaPiMeLa.Video.Wayland.Cursor — カーソルの形状と表示（cursor-shape-v1）

  Origin : partially ported from SDL (src/video/wayland/SDL_waylandmouse.c)
           Scope: プロトコルの手順に関する知見のみ。形状の指定にも消去にも
           wl_pointer.enter の serial が必要であること、サーフェスを渡さない
           set_cursor がカーソルを消す意味になること。構造は本設計に従う。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.2、§4.2、§11 #37

  WHAT:
    TPMLCursorBackend の Wayland 実装。システムカーソルの選択と表示 / 非表示を
    すべてのシートへ配る。

  WHY:
    カーソルは wl_pointer ごとに設定する。アプリが指定するのは「今どの形にするか」
    1 つだけなので、要求はここで 1 箇所に持ち、各シートへ配る形にした。
    シートは serial を持っているので、実際の設定はシート側で行う。

  RESOLVED:
    - cursor-shape-v1 が無くても表示 / 非表示（wl_pointer.set_cursor）は使える。
      形状の選択だけができなくなる
    - 設定にはポインタがウィンドウ上にある（enter を受けた）必要がある。
      無い間は要求を覚えておき、シートが次の enter で張り直す

  NOT RESOLVED:
    - 任意のピクセルからカーソルを作る経路は未実装。wl_shm の共通部品（#39）待ち。
      libwayland-cursor（テーマからの読み込み）も同じ理由で使っていない
    - 相対モード中にカーソルを自動で隠すことはしない。アプリが Visible を
      False にする

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Wayland.Cursor;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video.Wayland.Seat,
  PaPiMeLa.Platform.Wayland.Protocols.CursorShapeV1;

type
  // シート一覧を借りるための間接。所有者（TPMLWaylandVideoBackend）が渡す。
  // Seat ユニットは Cursor を参照しないので循環しない。
  TPMLWaylandSeatsFunc = function: TPMLWaylandSeats of object;

  TPMLWaylandCursorBackend = class(TPMLCursorBackend)
  strict private
    FSeats  : TPMLWaylandSeatsFunc;
    FKind   : TPMLSystemCursor;
    FVisible: Boolean;
    procedure Broadcast;
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject;
      ASeats: TPMLWaylandSeatsFunc);
    procedure SetSystemCursor(AKind: TPMLSystemCursor); override;
    procedure SetVisible(AVisible: Boolean); override;

    property Kind   : TPMLSystemCursor read FKind;
    property Visible: Boolean read FVisible;
  end;

// TPMLSystemCursor を cursor-shape-v1 の shape 値へ写す。
function PMLCursorShapeOf(AKind: TPMLSystemCursor): LongWord;

implementation

{ papimela の名前と Wayland の shape 値の対応表。

  Wayland 側は CSS のカーソル名に倣っているので、斜めリサイズ 4 方向のように
  papimela が持たない種類もある。逆に papimela に無い種類は足さない。 }
function PMLCursorShapeOf(AKind: TPMLSystemCursor): LongWord;
begin
  case AKind of
    TPMLSystemCursor.Arrow     : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_DEFAULT;
    TPMLSystemCursor.Text      : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_TEXT;
    TPMLSystemCursor.Wait      : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_WAIT;
    TPMLSystemCursor.Crosshair : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_CROSSHAIR;
    TPMLSystemCursor.Progress  : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_PROGRESS;
    TPMLSystemCursor.Hand      : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER;
    TPMLSystemCursor.Move      : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_MOVE;
    TPMLSystemCursor.NotAllowed: Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NOT_ALLOWED;
    TPMLSystemCursor.ResizeNWSE: Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NWSE_RESIZE;
    TPMLSystemCursor.ResizeNESW: Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NESW_RESIZE;
    TPMLSystemCursor.ResizeEW  : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_EW_RESIZE;
    TPMLSystemCursor.ResizeNS  : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NS_RESIZE;
    TPMLSystemCursor.ResizeN   : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_N_RESIZE;
    TPMLSystemCursor.ResizeE   : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_E_RESIZE;
    TPMLSystemCursor.ResizeS   : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_S_RESIZE;
    TPMLSystemCursor.ResizeW   : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_W_RESIZE;
    TPMLSystemCursor.ResizeNE  : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NE_RESIZE;
    TPMLSystemCursor.ResizeNW  : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NW_RESIZE;
    TPMLSystemCursor.ResizeSE  : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_SE_RESIZE;
    TPMLSystemCursor.ResizeSW  : Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_SW_RESIZE;
  else
    Result := WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_DEFAULT;
  end;
end;

constructor TPMLWaylandCursorBackend.Create(AContextRef: TObject;
  AOwner: TPMLObject; ASeats: TPMLWaylandSeatsFunc);
begin
  inherited Create(AContextRef, AOwner);
  FSeats := ASeats;
  FKind := TPMLSystemCursor.Arrow;
  FVisible := True;
end;

procedure TPMLWaylandCursorBackend.Broadcast;
var
  Seats: TPMLWaylandSeats;
  Shape: LongWord;
  I: Integer;
begin
  if not Assigned(FSeats) then
    Exit;
  Seats := FSeats();
  Shape := PMLCursorShapeOf(FKind);
  for I := 0 to High(Seats) do
    Seats[I].ApplyCursor(Shape, FVisible);
end;

procedure TPMLWaylandCursorBackend.SetSystemCursor(AKind: TPMLSystemCursor);
begin
  FKind := AKind;
  Broadcast;
end;

procedure TPMLWaylandCursorBackend.SetVisible(AVisible: Boolean);
begin
  if FVisible = AVisible then
    Exit;
  FVisible := AVisible;
  Broadcast;
end;

end.
