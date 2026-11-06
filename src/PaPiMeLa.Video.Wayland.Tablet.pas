{
  PaPiMeLa.Video.Wayland.Tablet — tablet-v2（ペンの道具）をペンの状態機械へ流す

  Origin : ported from SDL (src/video/wayland/SDL_waylandevents.c の tablet_tool_handle_* と
           tablet_seat_handle_*、src/video/wayland/SDL_waylandmouse.c の
           Wayland_TabletToolUpdateCursor)
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #66

  WHAT:
    zwp_tablet_seat_v2 から道具（zwp_tablet_tool_v2）を受け取り、道具ごとに知らせを frame まで
    ため、frame で TPMLPenState（Ctx.Events.Pen）へ SDL と同じ順に流す。道具ごとのカーソルの
    形（cursor-shape の get_tablet_tool_v2）も張る。

  WHY:
    tablet-v2 は 1 回の変化を複数の知らせに分けて送り、frame で区切る。順序（近接 in →
    移動と触れるの順は down / up で入れ替え → 軸 → ボタン → 近接 out）を決めるのは frame の
    受け手なので、ためる場所が要る。
    ためる部分（TPMLWaylandTabletToolState）はプロトコルのオブジェクトに触らない純粋な
    クラスにし、表示サーバ無しで知らせの列を流し込んで検査できるようにした
    （TPMLTextInputV3State と同じ形。検査は test/test_wayland_tablet_model）。

  SDL から外した所:
    - 座標に pointer_scale を掛けない（papimela の wl_pointer と同じくサーフェスの座標のまま）

  NOT RESOLVED:
    - 骨組みだけ。メソッドの中身と、Video.Wayland.Types の zwp_tablet_manager_v2 の束縛・
      TPMLWaylandSeat からの生成・能力 Tablet は #66 の実装で書く（検査 T-88 を先に書いた）
    - パッド（zwp_tablet_pad_v2）と tablet の情報は受け取らない（SDL も使わない）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Wayland.Tablet;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Events,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland,
  PaPiMeLa.Platform.Wayland.Protocols.TabletV2,
  PaPiMeLa.Platform.Wayland.Protocols.CursorShapeV1;

type
  { 道具のカーソルへの要求の行き先。本物はプロトコルの要求を出し、検査は記録する。 }
  IPMLWaylandToolCursorSink = interface
    ['{5B0E2C71-8D44-4A3F-9E61-27C4F0A9B3D8}']
    // 形を張る（wp_cursor_shape_device_v1.set_shape）。ASerial は近接 in の serial。
    procedure ToolCursorShape(ASerial, AShape: LongWord);
    // 隠す（zwp_tablet_tool_v2.set_cursor に nil）。
    procedure ToolCursorHide(ASerial: LongWord);
    // 道具が窓から離れた。張った形を忘れる（SDL の Wayland_CursorStateResetCursor）。
    procedure ToolCursorReset;
  end;

  { 道具 1 つの状態。tablet-v2 の知らせを frame までためて、frame で TPMLPenState へ流す。

    サーフェスは渡さない。リスナーが自分のウィンドウの ID に引いてから ProximityIn に渡す
    （このアプリの窓でなければ 0）。座標・角度は wl_fixed_t のまま受け取る。 }
  TPMLWaylandTabletToolState = class
  strict private
    FPens  : TPMLPenState;
    FCursor: IPMLWaylandToolCursorSink;
    FInfo  : TPMLPenInfo;
    FPenID : TPMLPenID;
    FFocus : TPMLWindowID;
    FProximitySerial: LongWord;
  public
    // ACursor は nil でよい。TPMLPenState.AddDevice の Handle にはこのオブジェクト自身を渡す
    // （SDL が sdltool を渡すのと同じ。FindByHandle で道具からペンを引ける）。
    constructor Create(APens: TPMLPenState; ACursor: IPMLWaylandToolCursorSink);

    // ---- 道具の情報（done まで） ----
    procedure ToolType(AToolType: LongWord);
    procedure HardwareSerial(AHi, ALo: LongWord);
    procedure HardwareIdWacom(AHi, ALo: LongWord);
    procedure Capability(ACapability: LongWord);
    // 情報が揃った。種類が分かればペンとして登録する（分からなければ登録しない）。
    procedure Done;
    // 道具が無くなった。登録していれば外す（近接 out が出る）。
    procedure Removed;

    // ---- 1 回の変化（frame まで） ----
    procedure ProximityIn(ASerial: LongWord; AWindowID: TPMLWindowID);
    procedure ProximityOut;
    procedure Down(ASerial: LongWord);
    procedure Up;
    procedure Motion(AX, AY: wl_fixed_t);
    procedure Pressure(AValue: LongWord);
    procedure Distance(AValue: LongWord);
    procedure Tilt(AX, AY: wl_fixed_t);
    procedure Rotation(ADegrees: wl_fixed_t);
    procedure Slider(APosition: LongInt);
    procedure Wheel(ADegrees: wl_fixed_t; AClicks: LongInt);
    // AButton は evdev のボタン番号（BTN_STYLUS など）、AState は ZWP_TABLET_TOOL_V2_BUTTON_STATE_xxx。
    procedure Button(ASerial, AButton, AState: LongWord);
    procedure Frame(ATime: LongWord);

    // ---- カーソル ----
    // アプリのカーソルの形が変わった（TPMLWaylandSeat.ApplyCursor と同じ値）。ARelativeHidden は
    // 「ペンがマウスを合成し、窓が相対モードでカーソルを隠す」とき True。道具が窓の上なら張り直す。
    procedure SetCursor(AShape: LongWord; AVisible, ARelativeHidden: Boolean);

    // 窓が壊された（SDL の Wayland_RemoveWindowDataFromExternalList の道具の部分）。道具がその窓の
    // 上なら、フォーカスを外し、カーソルを戻し、ペンの登録を外す（近接 out が出る）。
    procedure WindowDestroyed(AWindowID: TPMLWindowID);

    property PenID: TPMLPenID read FPenID;
    property Info: TPMLPenInfo read FInfo;
    // 近接 in で決まった窓（このアプリの窓でなければ 0）。
    property FocusWindow: TPMLWindowID read FFocus;
    property ProximitySerial: LongWord read FProximitySerial;
  end;

  // サーフェスからこのアプリの窓の ID を引く（TPMLWaylandSeat.WindowIDOf）。
  TPMLWaylandSurfaceWindowFunc = function(ASurface: Pwl_surface): TPMLWindowID of object;

  { zwp_tablet_seat_v2 のリスナー。道具が来るたびに TPMLWaylandTabletToolState と転送の
    リスナーを作り、道具が removed になったら壊す。 }
  TPMLWaylandTabletSeat = class(Tzwp_tablet_seat_v2_listener)
  strict private
    FTabletSeat : Pzwp_tablet_seat_v2;
    FPens       : TPMLPenState;
    FWindowOf   : TPMLWaylandSurfaceWindowFunc;
    FCursorShape: Pwp_cursor_shape_manager_v1;
    FTools      : array of TObject;   // 道具ごとの転送リスナー（中身は implementation 側）
  public
    // ACursorShape は nil でよい（そのときは形を張れず、隠すことだけできる）。
    constructor Create(AManager: Pzwp_tablet_manager_v2; ASeat: Pwl_seat;
      APens: TPMLPenState; AWindowOf: TPMLWaylandSurfaceWindowFunc;
      ACursorShape: Pwp_cursor_shape_manager_v1);
    destructor Destroy; override;

    procedure tool_added(AProxy: Pzwp_tablet_seat_v2; id: Pzwp_tablet_tool_v2); override;

    // アプリのカーソルが変わった。全部の道具へ伝える。
    procedure SetCursor(AShape: LongWord; AVisible, ARelativeHidden: Boolean);
  end;

implementation

{ 骨組み。T-88 が空の実装で落ちることを確かめるためのもの。中身は #66 の実装で書く。 }

{ TPMLWaylandTabletToolState }

constructor TPMLWaylandTabletToolState.Create(APens: TPMLPenState;
  ACursor: IPMLWaylandToolCursorSink);
begin
  inherited Create;
  FPens := APens;
  FCursor := ACursor;
end;

procedure TPMLWaylandTabletToolState.ToolType(AToolType: LongWord);
begin
end;

procedure TPMLWaylandTabletToolState.HardwareSerial(AHi, ALo: LongWord);
begin
end;

procedure TPMLWaylandTabletToolState.HardwareIdWacom(AHi, ALo: LongWord);
begin
end;

procedure TPMLWaylandTabletToolState.Capability(ACapability: LongWord);
begin
end;

procedure TPMLWaylandTabletToolState.Done;
begin
end;

procedure TPMLWaylandTabletToolState.Removed;
begin
end;

procedure TPMLWaylandTabletToolState.ProximityIn(ASerial: LongWord; AWindowID: TPMLWindowID);
begin
end;

procedure TPMLWaylandTabletToolState.ProximityOut;
begin
end;

procedure TPMLWaylandTabletToolState.Down(ASerial: LongWord);
begin
end;

procedure TPMLWaylandTabletToolState.Up;
begin
end;

procedure TPMLWaylandTabletToolState.Motion(AX, AY: wl_fixed_t);
begin
end;

procedure TPMLWaylandTabletToolState.Pressure(AValue: LongWord);
begin
end;

procedure TPMLWaylandTabletToolState.Distance(AValue: LongWord);
begin
end;

procedure TPMLWaylandTabletToolState.Tilt(AX, AY: wl_fixed_t);
begin
end;

procedure TPMLWaylandTabletToolState.Rotation(ADegrees: wl_fixed_t);
begin
end;

procedure TPMLWaylandTabletToolState.Slider(APosition: LongInt);
begin
end;

procedure TPMLWaylandTabletToolState.Wheel(ADegrees: wl_fixed_t; AClicks: LongInt);
begin
end;

procedure TPMLWaylandTabletToolState.Button(ASerial, AButton, AState: LongWord);
begin
end;

procedure TPMLWaylandTabletToolState.Frame(ATime: LongWord);
begin
end;

procedure TPMLWaylandTabletToolState.SetCursor(AShape: LongWord;
  AVisible, ARelativeHidden: Boolean);
begin
end;

procedure TPMLWaylandTabletToolState.WindowDestroyed(AWindowID: TPMLWindowID);
begin
end;

{ TPMLWaylandTabletSeat }

constructor TPMLWaylandTabletSeat.Create(AManager: Pzwp_tablet_manager_v2; ASeat: Pwl_seat;
  APens: TPMLPenState; AWindowOf: TPMLWaylandSurfaceWindowFunc;
  ACursorShape: Pwp_cursor_shape_manager_v1);
begin
  inherited Create;
  FTabletSeat := nil;
  FPens := APens;
  FWindowOf := AWindowOf;
  FCursorShape := ACursorShape;
end;

destructor TPMLWaylandTabletSeat.Destroy;
begin
  SetLength(FTools, 0);
  inherited Destroy;
end;

procedure TPMLWaylandTabletSeat.tool_added(AProxy: Pzwp_tablet_seat_v2;
  id: Pzwp_tablet_tool_v2);
begin
end;

procedure TPMLWaylandTabletSeat.SetCursor(AShape: LongWord; AVisible, ARelativeHidden: Boolean);
begin
end;

end.
