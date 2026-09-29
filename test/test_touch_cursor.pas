{
  test_touch_cursor — タッチの状態機械とカーソル形状

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    TPMLTouchState に合成タッチを流して、指ごとの移動量・ウィンドウの引き継ぎ・
    取り消しが設計どおりに振る舞うことを確認する。あわせて cursor-shape-v1 が
    能力に写り、形状と表示の切り替えがプロトコル違反を起こさないことを見る。

  WHY:
    タッチパネルが無い環境でも状態機械は検証できる。Wayland は移動量を送らず、
    motion と up にウィンドウも付けてこないので、「前の位置を覚えて差分を出す」
    「down で覚えたウィンドウを使う」という部分がタッチ対応の実体になる。
    そこはハードウェアに依存せず検証できるので、ここでアサーションを置く。

    実機のタッチパネルからの確認は demo_pointer_constraints では扱えない。
    タッチ対応の環境が手元に無いため未検証のままにしてある（docs/TEST-LOG.md）。

  実行前提: Wayland セッション。タッチパネルは不要。
}
program test_touch_cursor;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland,
  PaPiMeLa.Video.Wayland.Cursor,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.CursorShapeV1,
  PaPiMeLa.Core;

var
  Ctx     : TPMLContext;
  Win     : TPMLWindow;
  VB      : TPMLWaylandVideoBackend;
  Failures: Integer = 0;
  // 直近に届いたタッチイベント
  LastKind: TPMLEventKind;
  LastData: TPMLTouchFingerData;
  LastWin : TPMLWindowID;
  Received: Integer = 0;

procedure Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
    WriteLn('  [PASS] ', ALabel)
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(Failures);
  end;
end;

procedure Note(const AText: String);
begin
  WriteLn('  [観測] ', AText);
end;

// 溜まったタッチイベントを取り込む。最後の 1 件を検査対象にする。
function Drain: Integer;
var
  Ev: TPMLEvent;
begin
  Result := 0;
  while Ctx.Events.Poll(Ev) do
    if Ev.Kind in [TPMLEventKind.FingerDown, TPMLEventKind.FingerUp,
                   TPMLEventKind.FingerMotion, TPMLEventKind.FingerCanceled] then
    begin
      LastKind := Ev.Kind;
      LastData := Ev.Finger;
      LastWin := Ev.WindowID;
      Inc(Received);
      Inc(Result);
    end;
end;

function DisplayError: LongInt;
begin
  Result := wl_display_get_error(VB.Connection.Display);
end;

const
  DEV = 7;   // 適当なデバイス識別子。状態機械は中身を見ない

var
  T      : TPMLTouchState;
  P      : TPMLTouchPoint;
  HasShape: Boolean;
  Raised : Boolean;
  N      : Integer;
begin
  WriteLn('test_touch_cursor — タッチの状態機械とカーソル形状');
  WriteLn;

  Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
  try
    VB := Ctx.Video.Backend as TPMLWaylandVideoBackend;
    T := Ctx.Events.Touch;
    Check(T <> nil, 'イベントキューがタッチ状態機械を持っている');

    WriteLn;
    WriteLn('1. 1 本指の押下 → 移動 → 解放');
    T.SendDown(42, DEV, 0, 100, 200);
    Check(Drain = 1, 'down で 1 件届く');
    Check(LastKind = TPMLEventKind.FingerDown, 'FingerDown である');
    Check(LastWin = 42, 'ウィンドウ ID が載る');
    Check((LastData.X = 100) and (LastData.Y = 200), '座標が載る');
    Check((LastData.DX = 0) and (LastData.DY = 0), 'down の移動量は 0');
    Check(LastData.Pressure = 1.0, '触っている間の圧力は 1.0');
    Check(T.FingerCount = 1, '指 1 本を保持している');

    T.SendMotion(DEV, 0, 130, 190);
    Check(Drain = 1, 'motion で 1 件届く');
    Check(LastKind = TPMLEventKind.FingerMotion, 'FingerMotion である');
    // Wayland は移動量を送らない。前回位置との差はここで出している。
    Check((LastData.DX = 30) and (LastData.DY = -10), '前回位置からの移動量が出る');
    Check(LastWin = 42, 'motion にもウィンドウ ID が載る（down で覚えたもの）');

    T.SendUp(DEV, 0);
    Check(Drain = 1, 'up で 1 件届く');
    Check(LastKind = TPMLEventKind.FingerUp, 'FingerUp である');
    // wl_touch.up は座標を送らない。最後に分かっている位置を載せている。
    Check((LastData.X = 130) and (LastData.Y = 190), 'up には最後の位置が載る');
    Check(LastData.Pressure = 0.0, '離した指の圧力は 0.0');
    Check(T.FingerCount = 0, '保持している指が無くなる');

    WriteLn;
    WriteLn('2. 複数の指を区別する');
    T.SendDown(42, DEV, 0, 10, 10);
    T.SendDown(42, DEV, 1, 50, 50);
    Drain;
    Check(T.FingerCount = 2, '指 2 本を同時に保持する');
    T.SendMotion(DEV, 1, 55, 60);
    Drain;
    Check(LastData.FingerID = 1, '動かした指の id が載る');
    Check((LastData.DX = 5) and (LastData.DY = 10), '指ごとに移動量を持つ');
    Check(T.TryGetFinger(0, P) and (P.X = 10),
      '動かしていない指の位置は変わらない');

    WriteLn;
    WriteLn('3. 取り消し');
    N := Drain;   // 溜まりを捨てる
    T.SendCancel(DEV);
    N := Drain;
    Check(N = 2, '触っていた 2 本ぶんの取り消しが届く');
    Check(LastKind = TPMLEventKind.FingerCanceled, 'FingerCanceled である');
    Check(T.FingerCount = 0, '取り消しで指をすべて落とす');

    WriteLn;
    WriteLn('4. 基準の無い入力は捨てる');
    N := Drain;
    T.SendMotion(DEV, 99, 1, 1);
    T.SendUp(DEV, 99);
    Check(Drain = 0, 'down を見ていない指の motion / up は何も出さない');

    WriteLn;
    WriteLn('5. カーソル形状');
    HasShape := TPMLVideoCapability.CursorShape in Ctx.Video.Capabilities;
    Check((VB.Connection.CursorShapeMgr <> nil) = HasShape,
      'CursorShape 能力は wp_cursor_shape_manager_v1 の有無と一致する');
    Check(Ctx.Video.Cursors <> nil, 'カーソルの公開窓口がある');
    Check(Ctx.Video.Cursors.CanChooseShape = HasShape,
      'CanChooseShape が能力と一致する');
    Check(Ctx.Video.Cursors.SystemCursor = TPMLSystemCursor.Arrow,
      '初期形状は Arrow');
    Check(Ctx.Video.Cursors.Visible, '初期状態でカーソルは見えている');
    Note('cursor-shape-v1: ' + BoolToStr(VB.Connection.CursorShapeMgr <> nil, True));

    // 対応表は全 20 種類が有効な shape 値へ写らなければならない。
    // 0 は cursor-shape-v1 では無効値なので、写し漏れがあれば 0 で出る。
    Check(PMLCursorShapeOf(TPMLSystemCursor.Arrow) = WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_DEFAULT,
      'Arrow が default へ写る');
    Check(PMLCursorShapeOf(TPMLSystemCursor.Hand) = WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER,
      'Hand が pointer へ写る（名前が違う対応の代表）');
    Check(PMLCursorShapeOf(TPMLSystemCursor.ResizeSW) <> 0,
      '末尾の種類まで写っている');

    WriteLn;
    WriteLn('6. ウィンドウを開いて形状と表示を切り替える');
    Win := Ctx.Video.CreateWindow(
      TPMLWindowOptions.Make('papimela — touch / cursor', 420, 280));
    Ctx.Events.Pump(120);
    Drain;

    if HasShape then
    begin
      Ctx.Video.Cursors.SystemCursor := TPMLSystemCursor.Crosshair;
      Ctx.Events.Pump(60);
      Check(Ctx.Video.Cursors.SystemCursor = TPMLSystemCursor.Crosshair,
        '形状を覚えている');
      Check(DisplayError = 0, '形状を変えてもプロトコルエラーなし');
      Ctx.Video.Cursors.SystemCursor := TPMLSystemCursor.Arrow;
    end
    else
    begin
      Raised := False;
      try
        Ctx.Video.Cursors.SystemCursor := TPMLSystemCursor.Crosshair;
      except
        on E: EPMLUnsupported do
          Raised := True;
      end;
      Check(Raised, 'cursor-shape が無ければ形状指定で EPMLUnsupported');
    end;

    // 表示 / 非表示は cursor-shape-v1 を必要としない（wl_pointer.set_cursor）。
    Ctx.Video.Cursors.Visible := False;
    Ctx.Events.Pump(60);
    Check(not Ctx.Video.Cursors.Visible, 'カーソルを隠した状態を覚えている');
    Check(DisplayError = 0, 'カーソルを隠してもプロトコルエラーなし');
    Ctx.Video.Cursors.Visible := True;
    Ctx.Events.Pump(60);
    Check(DisplayError = 0, 'カーソルを戻してもプロトコルエラーなし');

    WriteLn;
    WriteLn('7. 後始末');
    Note(Format('受け取ったタッチイベント %d 件（すべて合成）', [Received]));
    Note('タッチ能力: ' + BoolToStr(TPMLVideoCapability.Touch in Ctx.Video.Capabilities, True)
      + '（シートに wl_touch があるかどうか）');
    Win.Free;
    Ctx.Events.Pump(60);
    Check(DisplayError = 0, 'ウィンドウ破棄後もプロトコルエラーなし');
    Check(Ctx.Events.DroppedCount = 0, 'イベントの取りこぼしなし');
  finally
    FreeAndNil(Ctx);
  end;
  WriteLn('  [PASS] Context 破棄');

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn('=== 結論: タッチの状態機械とカーソル形状は設計どおり ===');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('=== 失敗 %d 件 ===', [Failures]));
    ExitCode := 1;
  end;
end.
