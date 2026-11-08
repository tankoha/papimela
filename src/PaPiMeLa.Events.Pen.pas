{
  PaPiMeLa.Events.Pen — ペンの状態機械の中身（機器の一覧・入力の状態・マウスとタッチの合成）

  Origin : ported from SDL (src/events/SDL_pen.c)
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #66

  WHAT:
    公開の TPMLPenState（PaPiMeLa.Events。バックエンドが呼ぶ窓口）の中身。
    ペンの機器の一覧と、ペンごとの入力の状態（PML_PEN_INPUT_xxx）・座標・軸の値を持ち、
    変わったときだけ Pen* のイベントを積む。ヒント PAPIMELA_PEN_MOUSE_EVENTS /
    PAPIMELA_PEN_TOUCH_EVENTS に従ってマウスとタッチのイベントも合成する。

  WHY:
    PaPiMeLa.Events はクリーンルームのユニット。ここは SDL のソースを読んで写した部分
    なので、由来を分けるためにユニットを分けた（PaPiMeLa.Events.Keyboard と同じ形）。

  RESOLVED:
    - 排他は不要。papimela のイベントはメインスレッドで積むので、SDL の pen_device_rwlock
      （配列を別スレッドの再割り当てから守る）と、保留の印の原子変数は写さない
    - 登録簿は登録順の配列。ID は 1 から振り、外しても再利用しない
    - ヒント PAPIMELA_PEN_MOUSE_EVENTS / _TOUCH_EVENTS はコールバックで追い、既定は有効

  NOT RESOLVED:
    - SDL は触れているペンを 1 本（pen_touching）だけプロセスに持つ。papimela はキューごと

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Events.Pen;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Properties,
  PaPiMeLa.Events;

type
  // SDL_Pen。ペン 1 本分の登録と状態。
  TPMLPenRecord = record
    ID        : TPMLPenID;
    Name      : String;
    Info      : TPMLPenInfo;
    Handle    : Pointer;
    X, Y      : Single;
    Axes      : TPMLPenAxes;
    InputState: TPMLPenInputFlags;
    PendingOut: Boolean;        // pending_proximity_out
    PendingWin: TPMLWindowID;   // pending_proximity_window_id
  end;

  { TPMLPenState の中身。公開側の各メソッドはここへ渡す。メソッドの意味は TPMLPenState の宣言。 }
  TPMLPenImpl = class
  strict private
    FQueue       : TPMLEventQueue;
    FHints       : TPMLHints;
    FWindowExists: TPMLWindowExistsFunc;
    FPens        : array of TPMLPenRecord;
    FNextID      : TPMLPenID;
    FTouching    : TPMLPenID;   // pen_touching。マウスとタッチを合成している（最初に触れた）ペン。0 = 無し
    FAnyPending  : Boolean;     // 保留の近接 out を持つペンがあるかもしれない
    FMouseEvents : Boolean;     // mouse->pen_mouse_events
    FTouchEvents : Boolean;     // mouse->pen_touch_events
    FMouseWindow : TPMLWindowID; // 合成したマウスの最後の窓（SDL_UpdateMouseFocus の窓）。0 = まだ無い
    function  IndexOf(AID: TPMLPenID): Integer;
    procedure PushPen(AKind: TPMLEventKind; AWindowID: TPMLWindowID; AID: TPMLPenID;
      AState: TPMLPenInputFlags; AX, AY: Single; AAxis: TPMLPenAxis; AValue: Single;
      AButton: Byte; ADown, AEraser: Boolean);
    procedure EnsureProximity(AIndex: Integer; AWindowID: TPMLWindowID);
    procedure SendButtonEvents(AID: TPMLPenID; AWindowID: TPMLWindowID; AButton: Byte;
      ADown: Boolean; AState: TPMLPenInputFlags; AX, AY: Single);
    // SDL の UpdateTouchEmulationDevicePresence。合成を切った・ペンが 1 本も無いとき、合成した指を忘れる（SDL_DelTouch）。
    procedure UpdateTouchPresence;
    procedure SendMouseMotion(AWindowID: TPMLWindowID; AX, AY: Single);
    procedure SendMouseButton(AWindowID: TPMLWindowID; AButton: LongWord; ADown: Boolean);
    procedure MouseEventsChanged(const AName: String; const AOld, ANew: TPMLHintValue);
    procedure TouchEventsChanged(const AName: String; const AOld, ANew: TPMLHintValue);
  public
    // AHints が nil なら、ヒントは既定（どちらの合成も有効）のまま。
    constructor Create(AQueue: TPMLEventQueue; AHints: TPMLHints);
    destructor Destroy; override;

    function  AddDevice(const AName: String; AWindowID: TPMLWindowID;
      const AInfo: TPMLPenInfo; AHandle: Pointer; AInProximity: Boolean): TPMLPenID;
    procedure RemoveDevice(AWindowID: TPMLWindowID; AID: TPMLPenID);
    procedure RemoveAll(ACallback: TPMLPenRemoveProc);
    procedure SendTouch(AID: TPMLPenID; AWindowID: TPMLWindowID; AEraser, ADown: Boolean);
    procedure SendMotion(AID: TPMLPenID; AWindowID: TPMLWindowID; AX, AY: Single);
    procedure SendAxis(AID: TPMLPenID; AWindowID: TPMLWindowID; AAxis: TPMLPenAxis;
      AValue: Single);
    procedure SendButton(AID: TPMLPenID; AWindowID: TPMLWindowID; AButton: Byte;
      ADown: Boolean);
    procedure SendProximity(AID: TPMLPenID; AWindowID: TPMLWindowID; AIn, AImmediate: Boolean);
    procedure SendPendingProximity;
    function  FindByHandle(AHandle: Pointer): TPMLPenID;
    function  GetStatus(AID: TPMLPenID; out AAxes: TPMLPenAxes): TPMLPenInputFlags;
    function  GetDeviceType(AID: TPMLPenID): TPMLPenDeviceType;
    function  Count: Integer;
    property WindowExists: TPMLWindowExistsFunc read FWindowExists write FWindowExists;
  end;

implementation

const
  // 合成するタッチの指 ID は SDL_BUTTON_LEFT（1）。
  PEN_FINGER_ID = 1;
  // papimela のマウスのボタン番号（1 = 左、2 = 右、3 = 中、4 = X1、5 = X2）。
  MOUSE_BUTTON_LEFT = 1;

constructor TPMLPenImpl.Create(AQueue: TPMLEventQueue; AHints: TPMLHints);
begin
  inherited Create;
  FQueue := AQueue;
  FHints := AHints;
  FNextID := 1;
  FMouseEvents := True;
  FTouchEvents := True;
  // AddCallback はその場で 1 度呼ぶので、作った時点のヒントの値が入る。
  if FHints <> nil then
  begin
    FHints.AddCallback(PML_HINT_PEN_MOUSE_EVENTS, @MouseEventsChanged);
    FHints.AddCallback(PML_HINT_PEN_TOUCH_EVENTS, @TouchEventsChanged);
  end;
end;

destructor TPMLPenImpl.Destroy;
begin
  if FHints <> nil then
  begin
    FHints.RemoveCallback(PML_HINT_PEN_MOUSE_EVENTS, @MouseEventsChanged);
    FHints.RemoveCallback(PML_HINT_PEN_TOUCH_EVENTS, @TouchEventsChanged);
  end;
  SetLength(FPens, 0);
  inherited Destroy;
end;

procedure TPMLPenImpl.MouseEventsChanged(const AName: String; const AOld, ANew: TPMLHintValue);
begin
  FMouseEvents := PMLStringBoolean(ANew.Value, True);
end;

procedure TPMLPenImpl.TouchEventsChanged(const AName: String; const AOld, ANew: TPMLHintValue);
begin
  FTouchEvents := PMLStringBoolean(ANew.Value, True);
  UpdateTouchPresence;
end;

procedure TPMLPenImpl.UpdateTouchPresence;
begin
  if (not FTouchEvents) or (Length(FPens) = 0) then
    FQueue.Touch.ForgetDevice(PML_PEN_TOUCHID);
end;

{ ペンから合成するマウスの移動。

  PORT-NOTE: SDL_PrivateSendMouseMotion は位置が変わらない移動を捨てる（has_position 付き）。
  papimela の TPMLMouseState は捨てないので、ここで現在位置と比べて捨てる。窓が変わった
  ときは has_position が偽に戻るので、同じ位置でも送る。 }
procedure TPMLPenImpl.SendMouseMotion(AWindowID: TPMLWindowID; AX, AY: Single);
begin
  if (AWindowID = FMouseWindow) and (FQueue.Mouse.X = AX) and (FQueue.Mouse.Y = AY) then
    Exit;
  FMouseWindow := AWindowID;
  FQueue.Mouse.SendMotion(AWindowID, AX, AY, PML_PEN_MOUSEID);
end;

{ ペンから合成するマウスのボタン。

  PORT-NOTE: SDL_PrivateSendMouseButton は押下の状態が変わらないボタン（押していないボタンの
  離す、押しているボタンの押す）を捨てる。papimela の TPMLMouseState は捨てないので、ここで
  ButtonState と比べて捨てる。 }
procedure TPMLPenImpl.SendMouseButton(AWindowID: TPMLWindowID; AButton: LongWord;
  ADown: Boolean);
var
  Pressed: Boolean;
begin
  Pressed := (FQueue.Mouse.ButtonState and (LongWord(1) shl (AButton - 1))) <> 0;
  if Pressed = ADown then
    Exit;
  // SDL_PrivateSendMouseButton は SDL_UpdateMouseFocus を呼び、窓が変わっていれば今の位置で
  // 移動（MouseID 0）を 1 つ出す。papimela の実フォーカスは wl_pointer の enter が担うが、
  // ペンから合成したイベントの前にも同じ印を出して SDL の並びに合わせる。
  if AWindowID <> FMouseWindow then
  begin
    FMouseWindow := AWindowID;
    FQueue.Mouse.SendMotion(AWindowID, FQueue.Mouse.X, FQueue.Mouse.Y, 0);
  end;
  FQueue.Mouse.SendButton(AWindowID, AButton, ADown, PML_PEN_MOUSEID);
end;

{ SDL の FindPenByInstanceId。見つからなければ -1。 }
function TPMLPenImpl.IndexOf(AID: TPMLPenID): Integer;
var
  I: Integer;
begin
  Result := -1;
  if AID = 0 then
    Exit;
  for I := 0 to High(FPens) do
    if FPens[I].ID = AID then
      Exit(I);
end;

procedure TPMLPenImpl.PushPen(AKind: TPMLEventKind; AWindowID: TPMLWindowID; AID: TPMLPenID;
  AState: TPMLPenInputFlags; AX, AY: Single; AAxis: TPMLPenAxis; AValue: Single;
  AButton: Byte; ADown, AEraser: Boolean);
var
  Ev: TPMLEvent;
begin
  FillChar(Ev.Pen, SizeOf(Ev.Pen), 0);
  Ev.Kind := AKind;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := AWindowID;
  Ev.Text := '';
  Ev.Segments := nil;
  Ev.Strings := nil;
  Ev.Pen.Which := AID;
  Ev.Pen.PenState := AState;
  Ev.Pen.X := AX;
  Ev.Pen.Y := AY;
  Ev.Pen.Axis := AAxis;
  Ev.Pen.Value := AValue;
  Ev.Pen.Button := AButton;
  Ev.Pen.Down := ADown;
  Ev.Pen.Eraser := AEraser;
  FQueue.Push(Ev);
end;

{ SDL の EnsurePenProximity。保留の近接 out があれば取り消し、近接していなければ入れる。 }
procedure TPMLPenImpl.EnsureProximity(AIndex: Integer; AWindowID: TPMLWindowID);
begin
  if FPens[AIndex].PendingOut then
    FPens[AIndex].PendingOut := False
  else if (FPens[AIndex].InputState and PML_PEN_INPUT_IN_PROXIMITY) = 0 then
    SendProximity(FPens[AIndex].ID, AWindowID, True, True);
end;

{ SDL の SendPenButtonEvents。ペンのボタンのイベントと、マウスのボタンの合成。

  PORT-NOTE: SDL の mouse_buttons は { LEFT, RIGHT, MIDDLE, X1, X2 } を button（1..5）で引く。
  ペンのボタン 1 が RIGHT になり、ペンのボタン 5 は配列の外で何もしない（button < 5）。
  papimela のマウスは 1 = 左、2 = 右、3 = 中、4 = X1、5 = X2 なので、引いた結果は button + 1。
  マウスの合成は SDL と同じく、ペンのボタンのイベントが有効なときだけ（EventEnabled の中）。 }
procedure TPMLPenImpl.SendButtonEvents(AID: TPMLPenID; AWindowID: TPMLWindowID; AButton: Byte;
  ADown: Boolean; AState: TPMLPenInputFlags; AX, AY: Single);
var
  Kind: TPMLEventKind;
begin
  if ADown then
    Kind := TPMLEventKind.PenButtonDown
  else
    Kind := TPMLEventKind.PenButtonUp;
  if not FQueue.Enabled[Kind] then
    Exit;
  PushPen(Kind, AWindowID, AID, AState, AX, AY, TPMLPenAxis.Pressure, 0, AButton, ADown, False);

  if (AWindowID <> 0) and ((FTouching = 0) or (FTouching = AID)) and FMouseEvents
    and (AButton < 5) then
    SendMouseButton(AWindowID, LongWord(AButton) + 1, ADown);
end;

{ SDL_AddPenDevice。

  PORT-NOTE: SDL は name が NULL のときだけ "Unnamed pen" にする。papimela は空文字列でも
  "Unnamed pen" にする。ID は SDL_GetNextObjectID（SDL 全体の連番）でなくこの登録簿の連番。
  UpdateTouchEmulationDevicePresence は UpdateTouchPresence に写した（papimela のタッチには
  機器の登録が無いので、SDL_DelTouch は「その機器の指を黙って忘れる」だけ）。 }
function TPMLPenImpl.AddDevice(const AName: String; AWindowID: TPMLWindowID;
  const AInfo: TPMLPenInfo; AHandle: Pointer; AInProximity: Boolean): TPMLPenID;
var
  N: Integer;
begin
  Result := 0;
  if (AHandle = nil) or (FindByHandle(AHandle) <> 0) then
    Exit;
  N := Length(FPens);
  SetLength(FPens, N + 1);
  FillChar(FPens[N].Axes, SizeOf(FPens[N].Axes), 0);
  FPens[N].ID := FNextID;
  Inc(FNextID);
  if AName = '' then
    FPens[N].Name := 'Unnamed pen'
  else
    FPens[N].Name := AName;
  FPens[N].Info := AInfo;
  FPens[N].Handle := AHandle;
  FPens[N].X := 0;
  FPens[N].Y := 0;
  FPens[N].InputState := 0;
  FPens[N].PendingOut := False;
  FPens[N].PendingWin := 0;
  Result := FPens[N].ID;

  if AInProximity then
    SendProximity(Result, AWindowID, True, True);
end;

{ SDL_RemovePenDevice。

  PORT-NOTE: SDL は外すペンが pen_touching の持ち主でも pen_touching を 0 に戻さない
  （触れたまま外すと、以後ほかのペンがマウスとタッチを合成できない）。同じ振る舞いのまま写した。 }
procedure TPMLPenImpl.RemoveDevice(AWindowID: TPMLWindowID; AID: TPMLPenID);
var
  I, J: Integer;
begin
  if AID = 0 then
    Exit;
  SendProximity(AID, AWindowID, False, True);   // bye bye
  I := IndexOf(AID);
  if I < 0 then
    Exit;
  for J := I to High(FPens) - 1 do
    FPens[J] := FPens[J + 1];
  SetLength(FPens, Length(FPens) - 1);
  UpdateTouchPresence;
end;

procedure TPMLPenImpl.RemoveAll(ACallback: TPMLPenRemoveProc);
var
  I: Integer;
begin
  if Assigned(ACallback) then
    for I := 0 to High(FPens) do
      ACallback(FPens[I].ID, FPens[I].Handle);
  SetLength(FPens, 0);
  FTouching := 0;
  UpdateTouchPresence;
  FAnyPending := False;
end;

function TPMLPenImpl.FindByHandle(AHandle: Pointer): TPMLPenID;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FPens) do
    if FPens[I].Handle = AHandle then
      Exit(FPens[I].ID);
end;

{ SDL_SendPenTouch。

  PORT-NOTE: タッチの座標はウィンドウ座標のまま渡す（SDL は x / window->w で正規化する。
  TPMLTouchPoint の方針）。圧力は SDL と同じくペンの筆圧。 }
procedure TPMLPenImpl.SendTouch(AID: TPMLPenID; AWindowID: TPMLWindowID; AEraser, ADown: Boolean);
var
  I: Integer;
  SendEvent: Boolean;
  State: TPMLPenInputFlags;
  X, Y, Pressure: Single;
  Kind: TPMLEventKind;
begin
  I := IndexOf(AID);
  if I < 0 then
    Exit;
  State := FPens[I].InputState;
  X := FPens[I].X;
  Y := FPens[I].Y;
  Pressure := FPens[I].Axes[TPMLPenAxis.Pressure];
  SendEvent := False;

  if ADown and ((State and PML_PEN_INPUT_DOWN) = 0) then
  begin
    State := State or PML_PEN_INPUT_DOWN;
    SendEvent := True;
  end
  else if (not ADown) and ((State and PML_PEN_INPUT_DOWN) <> 0) then
  begin
    State := State and (not PML_PEN_INPUT_DOWN);
    SendEvent := True;
  end;

  if AEraser and ((State and PML_PEN_INPUT_ERASER_TIP) = 0) then
  begin
    State := State or PML_PEN_INPUT_ERASER_TIP;
    SendEvent := True;
  end
  else if (not AEraser) and ((State and PML_PEN_INPUT_ERASER_TIP) <> 0) then
  begin
    State := State and (not PML_PEN_INPUT_ERASER_TIP);
    SendEvent := True;
  end;
  FPens[I].InputState := State;

  if not SendEvent then
    Exit;

  if ADown then
    Kind := TPMLEventKind.PenDown
  else
    Kind := TPMLEventKind.PenUp;
  if FQueue.Enabled[Kind] then
    PushPen(Kind, AWindowID, AID, State, X, Y, TPMLPenAxis.Pressure, 0, 0, ADown, AEraser);

  if AWindowID <> 0 then
  begin
    if FMouseEvents then
    begin
      if ADown then
      begin
        if FTouching = 0 then
        begin
          SendMouseMotion(AWindowID, X, Y);
          SendMouseButton(AWindowID, MOUSE_BUTTON_LEFT, True);
        end;
      end
      else if FTouching = AID then
        SendMouseButton(AWindowID, MOUSE_BUTTON_LEFT, False);
    end;

    if FTouchEvents and ((FTouching = 0) or (FTouching = AID)) then
    begin
      if ADown then
        FQueue.Touch.SendDown(AWindowID, PML_PEN_TOUCHID, PEN_FINGER_ID, X, Y, Pressure)
      else
        FQueue.Touch.SendUp(PML_PEN_TOUCHID, PEN_FINGER_ID, Pressure);
    end;
  end;

  if ADown then
  begin
    if FTouching = 0 then
      FTouching := AID;
  end
  else if FTouching = AID then
    FTouching := 0;
end;

{ SDL_SendPenAxis。 }
procedure TPMLPenImpl.SendAxis(AID: TPMLPenID; AWindowID: TPMLWindowID; AAxis: TPMLPenAxis;
  AValue: Single);
var
  I: Integer;
  State: TPMLPenInputFlags;
  X, Y: Single;
begin
  I := IndexOf(AID);
  if I < 0 then
    Exit;
  if FPens[I].Axes[AAxis] = AValue then
    Exit;
  FPens[I].Axes[AAxis] := AValue;
  State := FPens[I].InputState;
  X := FPens[I].X;
  Y := FPens[I].Y;

  if not FQueue.Enabled[TPMLEventKind.PenAxis] then
    Exit;
  PushPen(TPMLEventKind.PenAxis, AWindowID, AID, State, X, Y, AAxis, AValue, 0, False, False);

  if (AWindowID <> 0) and (AAxis = TPMLPenAxis.Pressure) and (FTouching = AID)
    and FTouchEvents then
    FQueue.Touch.SendMotion(PML_PEN_TOUCHID, PEN_FINGER_ID, X, Y, AValue);
end;

{ SDL_SendPenMotion。 }
procedure TPMLPenImpl.SendMotion(AID: TPMLPenID; AWindowID: TPMLWindowID; AX, AY: Single);
var
  I: Integer;
  State: TPMLPenInputFlags;
begin
  I := IndexOf(AID);
  if I < 0 then
    Exit;
  EnsureProximity(I, AWindowID);
  if (FPens[I].X = AX) and (FPens[I].Y = AY) then
    Exit;
  FPens[I].X := AX;
  FPens[I].Y := AY;
  State := FPens[I].InputState;

  if not FQueue.Enabled[TPMLEventKind.PenMotion] then
    Exit;
  PushPen(TPMLEventKind.PenMotion, AWindowID, AID, State, AX, AY, TPMLPenAxis.Pressure, 0, 0,
    False, False);

  if AWindowID = 0 then
    Exit;
  if FTouching = AID then
  begin
    if FMouseEvents then
      SendMouseMotion(AWindowID, AX, AY);
    if FTouchEvents then
      FQueue.Touch.SendMotion(PML_PEN_TOUCHID, PEN_FINGER_ID, AX, AY,
        FPens[I].Axes[TPMLPenAxis.Pressure]);
  end
  else if FTouching = 0 then
  begin
    // 触れていないペンのマウスの動き（ボタン無し）。何本も近接していると混ざるが、SDL もそのまま。
    if FMouseEvents then
      SendMouseMotion(AWindowID, AX, AY);
  end;
end;

{ SDL_SendPenButton。 }
procedure TPMLPenImpl.SendButton(AID: TPMLPenID; AWindowID: TPMLWindowID; AButton: Byte;
  ADown: Boolean);
var
  I: Integer;
  State, Flag: TPMLPenInputFlags;
  SendEvent, Current: Boolean;
  X, Y: Single;
begin
  if (AButton < 1) or (AButton > 5) then
    Exit;
  I := IndexOf(AID);
  if I < 0 then
    Exit;
  EnsureProximity(I, AWindowID);

  State := FPens[I].InputState;
  Flag := LongWord(1) shl AButton;
  Current := (State and Flag) <> 0;
  X := FPens[I].X;
  Y := FPens[I].Y;
  SendEvent := False;
  if ADown and (not Current) then
  begin
    State := State or Flag;
    SendEvent := True;
  end
  else if (not ADown) and Current then
  begin
    State := State and (not Flag);
    SendEvent := True;
  end;
  FPens[I].InputState := State;

  if SendEvent then
    SendButtonEvents(AID, AWindowID, AButton, ADown, State, X, Y);
end;

{ SDL_SendPenProximity。入るか即時に出るときは状態を変えて積む。保留の出る（AIn = False かつ
  AImmediate = False）ときは印を付けるだけで、SendPendingProximity が積む。 }
procedure TPMLPenImpl.SendProximity(AID: TPMLPenID; AWindowID: TPMLWindowID;
  AIn, AImmediate: Boolean);
var
  I, B: Integer;
  SendEvent: Boolean;
  State, Orig, Flag: TPMLPenInputFlags;
  X, Y: Single;
  Kind: TPMLEventKind;
begin
  I := IndexOf(AID);
  if I < 0 then
    Exit;
  SendEvent := False;
  State := 0;
  Orig := 0;
  X := 0;
  Y := 0;

  if AIn or AImmediate then
  begin
    Orig := FPens[I].InputState;
    State := Orig;
    if ((State and PML_PEN_INPUT_IN_PROXIMITY) <> 0) <> AIn then
    begin
      if AIn then
        State := State or PML_PEN_INPUT_IN_PROXIMITY
      else
      begin
        State := State and (not PML_PEN_INPUT_IN_PROXIMITY);
        // 押しているボタンも全部離す。
        for B := 1 to 5 do
          State := State and (not (LongWord(1) shl B));
      end;
      SendEvent := True;
      FPens[I].InputState := State;
      X := FPens[I].X;
      Y := FPens[I].Y;
    end;
    FPens[I].PendingOut := False;
  end
  else
  begin
    FPens[I].PendingOut := True;
    FPens[I].PendingWin := AWindowID;
    FAnyPending := True;
  end;

  if not SendEvent then
    Exit;

  // 出るなら、押していたボタンを離したと先に知らせる（Orig は近接中のままの状態）。
  if not AIn then
    for B := 1 to 5 do
    begin
      Flag := LongWord(1) shl B;
      if (Orig and Flag) <> 0 then
      begin
        Orig := Orig and (not Flag);
        SendButtonEvents(AID, AWindowID, Byte(B), False, Orig, X, Y);
      end;
    end;

  if AIn then
    Kind := TPMLEventKind.PenProximityIn
  else
    Kind := TPMLEventKind.PenProximityOut;
  if FQueue.Enabled[Kind] then
    PushPen(Kind, AWindowID, AID, State, 0, 0, TPMLPenAxis.Pressure, 0, 0, False, False);
end;

{ SDL_SendPendingPenProximity。窓の存在確認は WindowExists に聞く（SDL_GetWindowFromID）。
  WindowExists が nil なら、あるものとする。 }
procedure TPMLPenImpl.SendPendingProximity;
var
  I: Integer;
begin
  if not FAnyPending then
    Exit;
  FAnyPending := False;
  for I := 0 to High(FPens) do
    if FPens[I].PendingOut then
    begin
      FPens[I].PendingOut := False;
      // 窓がもう無ければ、この近接 out は捨てる。
      if (FPens[I].PendingWin <> 0) and Assigned(FWindowExists)
        and (not FWindowExists(FPens[I].PendingWin)) then
        Continue;
      SendProximity(FPens[I].ID, FPens[I].PendingWin, False, True);
    end;
end;

function TPMLPenImpl.GetStatus(AID: TPMLPenID; out AAxes: TPMLPenAxes): TPMLPenInputFlags;
var
  I: Integer;
begin
  I := IndexOf(AID);
  if I < 0 then
  begin
    FillChar(AAxes, SizeOf(AAxes), 0);
    Result := 0;
  end
  else
  begin
    AAxes := FPens[I].Axes;
    Result := FPens[I].InputState;
  end;
end;

function TPMLPenImpl.GetDeviceType(AID: TPMLPenID): TPMLPenDeviceType;
var
  I: Integer;
begin
  I := IndexOf(AID);
  if I < 0 then
    Result := TPMLPenDeviceType.Invalid
  else
    Result := FPens[I].Info.DeviceType;
end;

function TPMLPenImpl.Count: Integer;
begin
  Result := Length(FPens);
end;

end.
