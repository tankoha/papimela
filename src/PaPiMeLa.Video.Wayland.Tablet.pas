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

  RESOLVED:
    - 道具のリスナ（転送クラス）の寿命は席が持つ。removed ではペンの登録を外して proxy を壊す
      だけで、Pascal のオブジェクトは席が次の tool_added か破棄で解放する（自分のコールバックの
      中で自分を解放しないため）
    - 道具のカーソルの要求は IPMLWaylandToolCursorSink を通す。本物（転送クラス）は cursor-shape の
      set_shape か zwp_tablet_tool_v2.set_cursor(nil) を出し、検査は記録する

  SDL から外した所:
    - 座標に pointer_scale を掛けない（papimela の wl_pointer と同じくサーフェスの座標のまま）
    - 「ペンがマウスを合成し、窓が相対モードでカーソルを隠す」判断（SDL の relative）は呼び手が
      SetCursor の引数で渡す。papimela は相対モード中にカーソルを自動で隠さない（Cursor ユニット）
      ので、本物の席は常に False を渡す
    - frame の time（ミリ秒）は使わない。タイムスタンプは TPMLPenState が積むときに付ける
    - down とボタンの serial は覚えない（SDL も覚えない。クリップボードの serial はポインタ・
      キーボード・タッチから取る）

  NOT RESOLVED:
    - 席より後に現れた tablet manager は拾わない（SDL は拾う。Seat ユニットの注記）
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
    type
      TFrameButtons = array[0..2] of Integer;   // 0 = 無し、1 = 押した、2 = 離した
    var
      FPens  : TPMLPenState;
      FCursor: IPMLWaylandToolCursorSink;
      FInfo  : TPMLPenInfo;
      FPenID : TPMLPenID;
      FFocus : TPMLWindowID;
      FProximitySerial: LongWord;
      // 見た目のカーソル（SetCursor が覚える）。SDL の mouse->cur_cursor / cursor_visible。
      FShape : LongWord;
      FVisible: Boolean;
      FRelativeHidden: Boolean;
      // frame の間にためる分（SDL_WaylandPenTool の frame）
      FX, FY      : Single;
      FAxes       : TPMLPenAxes;
      FAxesSet    : set of TPMLPenAxis;
      FButtons    : TFrameButtons;
      FToolState  : Integer;      // 0 = 無し、1 = 下りた、2 = 上がった
      FInProximity: Boolean;
      FHaveMotion : Boolean;
      FHaveProximity: Boolean;
    procedure ResetFrame;
    procedure UpdateCursor;
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
    // 直近の SetCursor（あとから現れた道具に引き継ぐ）
    FHaveCursor : Boolean;
    FShape      : LongWord;
    FVisible    : Boolean;
    FRelativeHidden: Boolean;
    procedure ReapRemoved;
  public
    // ACursorShape は nil でよい（そのときは形を張れず、隠すことだけできる）。
    constructor Create(AManager: Pzwp_tablet_manager_v2; ASeat: Pwl_seat;
      APens: TPMLPenState; AWindowOf: TPMLWaylandSurfaceWindowFunc;
      ACursorShape: Pwp_cursor_shape_manager_v1);
    destructor Destroy; override;

    procedure tool_added(AProxy: Pzwp_tablet_seat_v2; id: Pzwp_tablet_tool_v2); override;

    // アプリのカーソルが変わった。全部の道具へ伝える。
    procedure SetCursor(AShape: LongWord; AVisible, ARelativeHidden: Boolean);
    // 窓が壊される。全部の道具へ伝える。
    procedure WindowDestroyed(AWindowID: TPMLWindowID);
  end;

implementation

const
  // linux/input-event-codes.h
  BTN_STYLUS  = $14B;
  BTN_STYLUS2 = $14C;
  BTN_STYLUS3 = $149;

  AXIS_SCALE: Single = 65535.0;

  // frame の tool_state / buttons の値
  FRAME_NONE = 0;
  FRAME_DOWN = 1;
  FRAME_UP   = 2;

{ TPMLWaylandTabletToolState }

constructor TPMLWaylandTabletToolState.Create(APens: TPMLPenState;
  ACursor: IPMLWaylandToolCursorSink);
begin
  inherited Create;
  FPens := APens;
  FCursor := ACursor;
  // tablet_seat_handle_tool_added の初期値。
  FillChar(FInfo, SizeOf(FInfo), 0);
  FInfo.MaxTilt := -1;
  FInfo.NumButtons := -1;
  FInfo.Subtype := TPMLPenSubtype.Unknown;
  // PORT-NOTE: SDL の Wayland は device_type を設定しない（SDL_zero のまま = UNKNOWN）。
  // papimela の TPMLPenDeviceType は先頭が Invalid なので、SDL の既定値に当たる Unknown を置く。
  FInfo.DeviceType := TPMLPenDeviceType.Unknown;
  FShape := 0;
  FVisible := True;
  FRelativeHidden := False;
  ResetFrame;
end;

procedure TPMLWaylandTabletToolState.ResetFrame;
begin
  FX := 0;
  FY := 0;
  FillChar(FAxes, SizeOf(FAxes), 0);
  FAxesSet := [];
  FillChar(FButtons, SizeOf(FButtons), 0);
  FToolState := FRAME_NONE;
  FInProximity := False;
  FHaveMotion := False;
  FHaveProximity := False;
end;

{ SDL の Wayland_TabletToolUpdateCursor の分岐。

  窓の上にいて、カーソルが見え、相対で隠す状況でなければ形を張る。見えない・隠す状況なら隠す。
  窓の上にいなければ張った形を忘れる。 }
procedure TPMLWaylandTabletToolState.UpdateCursor;
begin
  if FCursor = nil then
    Exit;
  if FFocus <> 0 then
  begin
    if FVisible and (not FRelativeHidden) then
      FCursor.ToolCursorShape(FProximitySerial, FShape)
    else
      FCursor.ToolCursorHide(FProximitySerial);
  end
  else
    FCursor.ToolCursorReset;
end;

procedure TPMLWaylandTabletToolState.ToolType(AToolType: LongWord);
begin
  case AToolType of
    ZWP_TABLET_TOOL_V2_TYPE_ERASER:   FInfo.Subtype := TPMLPenSubtype.Eraser;
    ZWP_TABLET_TOOL_V2_TYPE_PEN:      FInfo.Subtype := TPMLPenSubtype.Pen;
    ZWP_TABLET_TOOL_V2_TYPE_PENCIL:   FInfo.Subtype := TPMLPenSubtype.Pencil;
    ZWP_TABLET_TOOL_V2_TYPE_AIRBRUSH: FInfo.Subtype := TPMLPenSubtype.Airbrush;
    ZWP_TABLET_TOOL_V2_TYPE_BRUSH:    FInfo.Subtype := TPMLPenSubtype.Brush;
  else
    // 役割が分からない。done で登録しない。
    FInfo.Subtype := TPMLPenSubtype.Unknown;
  end;
end;

procedure TPMLWaylandTabletToolState.HardwareSerial(AHi, ALo: LongWord);
begin
  // SDL は使わない。
end;

procedure TPMLWaylandTabletToolState.HardwareIdWacom(AHi, ALo: LongWord);
begin
  FInfo.WacomID := ALo;
end;

procedure TPMLWaylandTabletToolState.Capability(ACapability: LongWord);
begin
  case ACapability of
    ZWP_TABLET_TOOL_V2_CAPABILITY_TILT:
      FInfo.Capabilities := FInfo.Capabilities
        + [TPMLPenCapability.XTilt, TPMLPenCapability.YTilt];
    ZWP_TABLET_TOOL_V2_CAPABILITY_PRESSURE:
      Include(FInfo.Capabilities, TPMLPenCapability.Pressure);
    ZWP_TABLET_TOOL_V2_CAPABILITY_DISTANCE:
      Include(FInfo.Capabilities, TPMLPenCapability.Distance);
    ZWP_TABLET_TOOL_V2_CAPABILITY_ROTATION:
      Include(FInfo.Capabilities, TPMLPenCapability.Rotation);
    ZWP_TABLET_TOOL_V2_CAPABILITY_SLIDER:
      Include(FInfo.Capabilities, TPMLPenCapability.Slider);
  else
    // 使わない（wheel など）。
    ;
  end;
end;

procedure TPMLWaylandTabletToolState.Done;
begin
  // 役割の分からない道具は知らせない。
  // PORT-NOTE: SDL は done のたびに SDL_AddPenDevice を呼ぶ（同じ handle の二重登録は assert）。
  // 二度目の done では増やさない。
  if (FInfo.Subtype <> TPMLPenSubtype.Unknown) and (FPenID = 0) then
    FPenID := FPens.AddDevice('', FFocus, FInfo, Pointer(Self), False);
end;

procedure TPMLWaylandTabletToolState.Removed;
begin
  if FPenID <> 0 then
  begin
    FPens.RemoveDevice(FFocus, FPenID);
    FPenID := 0;
  end;
end;

procedure TPMLWaylandTabletToolState.ProximityIn(ASerial: LongWord; AWindowID: TPMLWindowID);
begin
  FFocus := AWindowID;
  FProximitySerial := ASerial;
  FHaveProximity := True;
  FInProximity := True;
  // 次に frame が来て、そこで初めてイベントを出す。
end;

procedure TPMLWaylandTabletToolState.ProximityOut;
begin
  FHaveProximity := True;
  FInProximity := False;
end;

procedure TPMLWaylandTabletToolState.Down(ASerial: LongWord);
begin
  FToolState := FRAME_DOWN;
end;

procedure TPMLWaylandTabletToolState.Up;
begin
  FToolState := FRAME_UP;
end;

procedure TPMLWaylandTabletToolState.Motion(AX, AY: wl_fixed_t);
begin
  // 焦点（このアプリの窓）が無ければ捨てる。
  if FFocus = 0 then
    Exit;
  FX := PMLFixedToSingle(AX);
  FY := PMLFixedToSingle(AY);
  FHaveMotion := True;
end;

procedure TPMLWaylandTabletToolState.Pressure(AValue: LongWord);
begin
  FAxes[TPMLPenAxis.Pressure] := Single(AValue) / AXIS_SCALE;
  Include(FAxesSet, TPMLPenAxis.Pressure);
  if AValue <> 0 then
  begin
    FAxes[TPMLPenAxis.Distance] := 0;
    Include(FAxesSet, TPMLPenAxis.Distance);
  end;
end;

procedure TPMLWaylandTabletToolState.Distance(AValue: LongWord);
begin
  FAxes[TPMLPenAxis.Distance] := Single(AValue) / AXIS_SCALE;
  Include(FAxesSet, TPMLPenAxis.Distance);
  if AValue <> 0 then
  begin
    FAxes[TPMLPenAxis.Pressure] := 0;
    Include(FAxesSet, TPMLPenAxis.Pressure);
  end;
end;

procedure TPMLWaylandTabletToolState.Tilt(AX, AY: wl_fixed_t);
begin
  FAxes[TPMLPenAxis.XTilt] := PMLFixedToSingle(AX);
  FAxes[TPMLPenAxis.YTilt] := PMLFixedToSingle(AY);
  FAxesSet := FAxesSet + [TPMLPenAxis.XTilt, TPMLPenAxis.YTilt];
end;

procedure TPMLWaylandTabletToolState.Rotation(ADegrees: wl_fixed_t);
var
  R: Single;
begin
  R := PMLFixedToSingle(ADegrees);
  // -180 .. 180 の範囲に直す。
  if R > 180.0 then
    R := R - 360.0;
  FAxes[TPMLPenAxis.Rotation] := R;
  Include(FAxesSet, TPMLPenAxis.Rotation);
end;

procedure TPMLWaylandTabletToolState.Slider(APosition: LongInt);
begin
  FAxes[TPMLPenAxis.Slider] := Single(APosition) / AXIS_SCALE;
  Include(FAxesSet, TPMLPenAxis.Slider);
end;

procedure TPMLWaylandTabletToolState.Wheel(ADegrees: wl_fixed_t; AClicks: LongInt);
begin
  // SDL も未対応（"not supported at the moment"）。
end;

procedure TPMLWaylandTabletToolState.Button(ASerial, AButton, AState: LongWord);
var
  Index: Integer;
begin
  case AButton of
    BTN_STYLUS:  Index := 0;
    BTN_STYLUS2: Index := 1;
    BTN_STYLUS3: Index := 2;
  else
    // 使わないボタン。
    Exit;
  end;
  if AState = ZWP_TABLET_TOOL_V2_BUTTON_STATE_PRESSED then
    FButtons[Index] := FRAME_DOWN
  else
    FButtons[Index] := FRAME_UP;
end;

{ frame。ためたものを SDL の tablet_tool_handle_frame と同じ順で TPMLPenState へ流す。 }
procedure TPMLWaylandTabletToolState.Frame(ATime: LongWord);
var
  IsEraser: Boolean;
  Axis: TPMLPenAxis;
  I: Integer;
begin
  // 報告しない道具。SDL はためたものを捨てずに戻る。
  if FPenID = 0 then
    Exit;

  IsEraser := FInfo.Subtype = TPMLPenSubtype.Eraser;

  if FHaveProximity and FInProximity then
  begin
    FPens.SendProximity(FPenID, FFocus, True, True);
    UpdateCursor;
  end;

  // 意図しない線が引かれないように、動きは下りる前、上がった後に送る。
  if FHaveMotion and (FToolState <> FRAME_NONE) then
  begin
    if FToolState = FRAME_DOWN then
    begin
      FPens.SendMotion(FPenID, FFocus, FX, FY);
      FPens.SendTouch(FPenID, FFocus, IsEraser, True);
    end
    else
    begin
      FPens.SendTouch(FPenID, FFocus, IsEraser, False);
      FPens.SendMotion(FPenID, FFocus, FX, FY);
    end;
  end
  else
  begin
    if FToolState <> FRAME_NONE then
      FPens.SendTouch(FPenID, FFocus, IsEraser, FToolState = FRAME_DOWN);
    if FHaveMotion then
      FPens.SendMotion(FPenID, FFocus, FX, FY);
  end;

  for Axis := Low(TPMLPenAxis) to High(TPMLPenAxis) do
    if Axis in FAxesSet then
      FPens.SendAxis(FPenID, FFocus, Axis, FAxes[Axis]);

  for I := 0 to High(FButtons) do
    if FButtons[I] <> FRAME_NONE then
      FPens.SendButton(FPenID, FFocus, Byte(I + 1), FButtons[I] = FRAME_DOWN);

  if FHaveProximity and (not FInProximity) then
  begin
    // 近接の終わりは遅らせて出す（Pump が積む。それまでに動きが来れば取り消される）。
    FPens.SendProximity(FPenID, FFocus, False, False);
    FFocus := 0;
    UpdateCursor;
  end;

  ResetFrame;
end;

procedure TPMLWaylandTabletToolState.SetCursor(AShape: LongWord;
  AVisible, ARelativeHidden: Boolean);
begin
  FShape := AShape;
  FVisible := AVisible;
  FRelativeHidden := ARelativeHidden;
  UpdateCursor;
end;

procedure TPMLWaylandTabletToolState.WindowDestroyed(AWindowID: TPMLWindowID);
begin
  if (AWindowID = 0) or (FFocus <> AWindowID) then
    Exit;
  FFocus := 0;
  UpdateCursor;
  // PORT-NOTE: SDL はペンの登録を外したまま戻さない（instance_id を 0 にする）。同じ。
  if FPenID <> 0 then
  begin
    FPens.RemoveDevice(AWindowID, FPenID);
    FPenID := 0;
  end;
end;

{ ---- プロトコルのオブジェクトにつなぐ部分（接続が要る。検査は手元専用の実機） ---- }

type
  { 道具 1 つ分の転送リスナー。プロトコルの知らせを TPMLWaylandTabletToolState へ渡し、
    道具のカーソルの要求を本物のプロトコルの要求にする。 }
  TToolForwarder = class(Tzwp_tablet_tool_v2_listener, IPMLWaylandToolCursorSink)
  strict private
    FState   : TPMLWaylandTabletToolState;
    FProxy   : Pzwp_tablet_tool_v2;
    FShapeDev: Pwp_cursor_shape_device_v1;
    FWindowOf: TPMLWaylandSurfaceWindowFunc;
    FRemoved : Boolean;
  public
    constructor Create(AProxy: Pzwp_tablet_tool_v2; APens: TPMLPenState;
      AWindowOf: TPMLWaylandSurfaceWindowFunc; ACursorShape: Pwp_cursor_shape_manager_v1);
    destructor Destroy; override;

    procedure type_(AProxy: Pzwp_tablet_tool_v2; tool_type: LongWord); override;
    procedure hardware_serial(AProxy: Pzwp_tablet_tool_v2; hardware_serial_hi: LongWord;
      hardware_serial_lo: LongWord); override;
    procedure hardware_id_wacom(AProxy: Pzwp_tablet_tool_v2; hardware_id_hi: LongWord;
      hardware_id_lo: LongWord); override;
    procedure capability(AProxy: Pzwp_tablet_tool_v2; capability_: LongWord); override;
    procedure done(AProxy: Pzwp_tablet_tool_v2); override;
    procedure removed(AProxy: Pzwp_tablet_tool_v2); override;
    procedure proximity_in(AProxy: Pzwp_tablet_tool_v2; serial: LongWord;
      tablet: Pzwp_tablet_v2; surface: Pwl_surface); override;
    procedure proximity_out(AProxy: Pzwp_tablet_tool_v2); override;
    procedure down(AProxy: Pzwp_tablet_tool_v2; serial: LongWord); override;
    procedure up(AProxy: Pzwp_tablet_tool_v2); override;
    procedure motion(AProxy: Pzwp_tablet_tool_v2; x: wl_fixed_t; y: wl_fixed_t); override;
    procedure pressure(AProxy: Pzwp_tablet_tool_v2; pressure_: LongWord); override;
    procedure distance(AProxy: Pzwp_tablet_tool_v2; distance_: LongWord); override;
    procedure tilt(AProxy: Pzwp_tablet_tool_v2; tilt_x: wl_fixed_t; tilt_y: wl_fixed_t); override;
    procedure rotation(AProxy: Pzwp_tablet_tool_v2; degrees: wl_fixed_t); override;
    procedure slider(AProxy: Pzwp_tablet_tool_v2; position: LongInt); override;
    procedure wheel(AProxy: Pzwp_tablet_tool_v2; degrees: wl_fixed_t; clicks: LongInt); override;
    procedure button(AProxy: Pzwp_tablet_tool_v2; serial: LongWord; button_: LongWord;
      state: LongWord); override;
    procedure frame(AProxy: Pzwp_tablet_tool_v2; time: LongWord); override;

    // IPMLWaylandToolCursorSink
    procedure ToolCursorShape(ASerial, AShape: LongWord);
    procedure ToolCursorHide(ASerial: LongWord);
    procedure ToolCursorReset;

    // proxy を壊した（removed を受けた）あと True。席が次の機会に解放する。
    property IsRemoved: Boolean read FRemoved;
    property State: TPMLWaylandTabletToolState read FState;
  end;

constructor TToolForwarder.Create(AProxy: Pzwp_tablet_tool_v2; APens: TPMLPenState;
  AWindowOf: TPMLWaylandSurfaceWindowFunc; ACursorShape: Pwp_cursor_shape_manager_v1);
begin
  inherited Create;
  FProxy := AProxy;
  FWindowOf := AWindowOf;
  FState := TPMLWaylandTabletToolState.Create(APens, Self);
  // cursor-shape の装置は道具ごと。無い環境では nil のままで、隠すことだけができる。
  if ACursorShape <> nil then
    FShapeDev := wp_cursor_shape_manager_v1_get_tablet_tool_v2(ACursorShape, AProxy);
end;

destructor TToolForwarder.Destroy;
begin
  // 登録中なら外す（近接 out が出る）。removed で外していれば何もしない。
  FState.Removed;
  if FShapeDev <> nil then
  begin
    wp_cursor_shape_device_v1_destroy(FShapeDev);
    FShapeDev := nil;
  end;
  if FProxy <> nil then
  begin
    zwp_tablet_tool_v2_destroy(FProxy);
    FProxy := nil;
  end;
  FreeAndNil(FState);
  inherited Destroy;
end;

procedure TToolForwarder.type_(AProxy: Pzwp_tablet_tool_v2; tool_type: LongWord);
begin
  FState.ToolType(tool_type);
end;

procedure TToolForwarder.hardware_serial(AProxy: Pzwp_tablet_tool_v2;
  hardware_serial_hi: LongWord; hardware_serial_lo: LongWord);
begin
  FState.HardwareSerial(hardware_serial_hi, hardware_serial_lo);
end;

procedure TToolForwarder.hardware_id_wacom(AProxy: Pzwp_tablet_tool_v2;
  hardware_id_hi: LongWord; hardware_id_lo: LongWord);
begin
  FState.HardwareIdWacom(hardware_id_hi, hardware_id_lo);
end;

procedure TToolForwarder.capability(AProxy: Pzwp_tablet_tool_v2; capability_: LongWord);
begin
  FState.Capability(capability_);
end;

procedure TToolForwarder.done(AProxy: Pzwp_tablet_tool_v2);
begin
  FState.Done;
end;

procedure TToolForwarder.removed(AProxy: Pzwp_tablet_tool_v2);
begin
  // SDL の tablet_tool_handle_removed。ペンの登録を外し、proxy を壊す。オブジェクト自身は
  // 席が後で解放する（自分のコールバックの中で自分を解放しないため）。
  FState.Removed;
  if FShapeDev <> nil then
  begin
    wp_cursor_shape_device_v1_destroy(FShapeDev);
    FShapeDev := nil;
  end;
  if FProxy <> nil then
  begin
    zwp_tablet_tool_v2_destroy(FProxy);
    FProxy := nil;
  end;
  FRemoved := True;
end;

procedure TToolForwarder.proximity_in(AProxy: Pzwp_tablet_tool_v2; serial: LongWord;
  tablet: Pzwp_tablet_v2; surface: Pwl_surface);
var
  ID: TPMLWindowID;
begin
  // このアプリの窓でないサーフェス（引けなければ 0）でも近接は溜める（SDL と同じ）。
  ID := 0;
  if (surface <> nil) and Assigned(FWindowOf) then
    ID := FWindowOf(surface);
  FState.ProximityIn(serial, ID);
end;

procedure TToolForwarder.proximity_out(AProxy: Pzwp_tablet_tool_v2);
begin
  FState.ProximityOut;
end;

procedure TToolForwarder.down(AProxy: Pzwp_tablet_tool_v2; serial: LongWord);
begin
  FState.Down(serial);
end;

procedure TToolForwarder.up(AProxy: Pzwp_tablet_tool_v2);
begin
  FState.Up;
end;

procedure TToolForwarder.motion(AProxy: Pzwp_tablet_tool_v2; x: wl_fixed_t; y: wl_fixed_t);
begin
  FState.Motion(x, y);
end;

procedure TToolForwarder.pressure(AProxy: Pzwp_tablet_tool_v2; pressure_: LongWord);
begin
  FState.Pressure(pressure_);
end;

procedure TToolForwarder.distance(AProxy: Pzwp_tablet_tool_v2; distance_: LongWord);
begin
  FState.Distance(distance_);
end;

procedure TToolForwarder.tilt(AProxy: Pzwp_tablet_tool_v2; tilt_x: wl_fixed_t;
  tilt_y: wl_fixed_t);
begin
  FState.Tilt(tilt_x, tilt_y);
end;

procedure TToolForwarder.rotation(AProxy: Pzwp_tablet_tool_v2; degrees: wl_fixed_t);
begin
  FState.Rotation(degrees);
end;

procedure TToolForwarder.slider(AProxy: Pzwp_tablet_tool_v2; position: LongInt);
begin
  FState.Slider(position);
end;

procedure TToolForwarder.wheel(AProxy: Pzwp_tablet_tool_v2; degrees: wl_fixed_t;
  clicks: LongInt);
begin
  FState.Wheel(degrees, clicks);
end;

procedure TToolForwarder.button(AProxy: Pzwp_tablet_tool_v2; serial: LongWord;
  button_: LongWord; state: LongWord);
begin
  FState.Button(serial, button_, state);
end;

procedure TToolForwarder.frame(AProxy: Pzwp_tablet_tool_v2; time: LongWord);
begin
  FState.Frame(time);
end;

procedure TToolForwarder.ToolCursorShape(ASerial, AShape: LongWord);
begin
  // 形の値 0 は「まだ決まっていない」。
  if (FShapeDev <> nil) and (AShape <> 0) then
    wp_cursor_shape_device_v1_set_shape(FShapeDev, ASerial, AShape);
end;

procedure TToolForwarder.ToolCursorHide(ASerial: LongWord);
begin
  // サーフェスを渡さない set_cursor が「カーソルを消す」の意味になる。
  if FProxy <> nil then
    zwp_tablet_tool_v2_set_cursor(FProxy, ASerial, nil, 0, 0);
end;

procedure TToolForwarder.ToolCursorReset;
begin
  // 張った形を覚えていないので、することが無い（次の近接 in で張り直す）。
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
  FVisible := True;
  if AManager <> nil then
  begin
    FTabletSeat := zwp_tablet_manager_v2_get_tablet_seat(AManager, ASeat);
    if FTabletSeat <> nil then
      zwp_tablet_seat_v2_add_listener_object(FTabletSeat, Self);
  end;
end;

destructor TPMLWaylandTabletSeat.Destroy;
var
  I: Integer;
begin
  // 転送リスナーの破棄が、ペンの登録の取り消しと proxy の破棄を引き受ける。
  for I := 0 to High(FTools) do
    FTools[I].Free;
  SetLength(FTools, 0);
  if FTabletSeat <> nil then
  begin
    zwp_tablet_seat_v2_destroy(FTabletSeat);
    FTabletSeat := nil;
  end;
  inherited Destroy;
end;

{ removed を受けた転送リスナーを解放する。コールバックの中では自分を解放できないので、
  次の tool_added か席の破棄のときにまとめて行う。 }
procedure TPMLWaylandTabletSeat.ReapRemoved;
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to High(FTools) do
    if TToolForwarder(FTools[I]).IsRemoved then
      FTools[I].Free
    else
    begin
      FTools[N] := FTools[I];
      Inc(N);
    end;
  SetLength(FTools, N);
end;

procedure TPMLWaylandTabletSeat.tool_added(AProxy: Pzwp_tablet_seat_v2;
  id: Pzwp_tablet_tool_v2);
var
  Tool: TToolForwarder;
begin
  ReapRemoved;
  Tool := TToolForwarder.Create(id, FPens, FWindowOf, FCursorShape);
  SetLength(FTools, Length(FTools) + 1);
  FTools[High(FTools)] := Tool;
  // あとから現れた道具にも、いまのアプリのカーソルを引き継ぐ。
  if FHaveCursor then
    Tool.State.SetCursor(FShape, FVisible, FRelativeHidden);
  // 種類・能力などの知らせが続けて届き、done で全部そろう。
  zwp_tablet_tool_v2_add_listener_object(id, Tool);
end;

procedure TPMLWaylandTabletSeat.SetCursor(AShape: LongWord;
  AVisible, ARelativeHidden: Boolean);
var
  I: Integer;
begin
  FHaveCursor := True;
  FShape := AShape;
  FVisible := AVisible;
  FRelativeHidden := ARelativeHidden;
  for I := 0 to High(FTools) do
    if not TToolForwarder(FTools[I]).IsRemoved then
      TToolForwarder(FTools[I]).State.SetCursor(AShape, AVisible, ARelativeHidden);
end;

procedure TPMLWaylandTabletSeat.WindowDestroyed(AWindowID: TPMLWindowID);
var
  I: Integer;
begin
  for I := 0 to High(FTools) do
    if not TToolForwarder(FTools[I]).IsRemoved then
      TToolForwarder(FTools[I]).State.WindowDestroyed(AWindowID);
end;

end.
