{
  pong — papimela の公開 API だけで書いた Pong

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    2 本のパドルと 1 つの球。先に 7 点取った側が勝つ。左が自分、右がコンピュータ
    （2 キーで 2 人対戦に切り替え）。ウィンドウの大きさを変えると、縦横比を保った
    まま盤面が拡大縮小される。

  WHY:
    papimela を「使う側」から試すためのサンプル。ライブラリの中から見て足りている
    つもりでも、アプリを 1 本書くと足りないものが見える。書いていて足りなかった
    API は examples/README.md に記録した。

    パドルの操作は TController の派生（キーボード / コンピュータ）で差し替える。
    盤面の計算（TPongGame）は描画にも入力にも依存しないので、表示サーバ無しで
    検査できる。

  使い方:
    ./examples/pong              遊ぶ
    ./examples/pong --selftest   表示サーバ無しで、コンピュータ同士に 60 秒ぶん
                                 対戦させて盤面と描画を検査する（CI が走らせる）
  操作:
    W / S、↑ / ↓   左のパドル（2 人対戦では左が W / S、右が ↑ / ↓）。
                   W / S はキーの位置で読むので、AZERTY でも同じ場所（Z / S）で動く
    2              1 人用 / 2 人対戦の切り替え
    P              一時停止
    Space          勝負がついた後に再開
    Escape         終了
}
program pong;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Keycodes,
  PaPiMeLa.Surface,
  PaPiMeLa.Video,
  PaPiMeLa.Render,
  PaPiMeLa.Core;

const
  // 盤面は論理座標 640x400 で計算し、描くときにウィンドウへ合わせる。
  FieldW = 640;
  FieldH = 400;
  PaddleW = 10;
  PaddleH = 64;
  PaddleMargin = 24;
  PaddleSpeed = 360;        // 論理座標 / 秒
  BallSize = 10;
  BallStartSpeed = 300;
  BallMaxSpeed = 900;
  SpeedUpPerHit = 1.06;
  MaxBounceAngle = 60 * Pi / 180;
  ServeDelay = 1.0;         // 得点の後、次のサーブまでの秒数
  WinScore = 7;
  // 盤面は固定の刻みで進める。1/240 秒なら最高速でも 1 刻み 3.75 で、
  // パドルの厚み 10 をすり抜けない。
  StepSeconds = 1 / 240;
  // 1 フレームの最短の長さ。VSync が使えないときは 60 fps。VSync を受け付けても
  // Present が待つとは限らない（ダミーのビデオは受け付けるだけで待たない）ので、
  // そのときも 240 fps で頭打ちにする。240 Hz までの画面の VSync なら効かない。
  FrameNSNoVSync = UInt64(1000000000) div 60;
  FrameNSVSync   = UInt64(1000000000) div 240;

type
  TSide = (Left, Right);

  { 盤面。入力も描画も知らない。 }
  TPongGame = class
  strict private
    FPaddleY : array[TSide] of Single;   // パドルの上端
    FScore   : array[TSide] of Integer;
    FBallX, FBallY, FVelX, FVelY: Single; // 球の左上と速度
    FServeTimer: Single;                 // 0 より大きい間は球が中央で止まっている
    FServeTo : TSide;
    FHits    : Integer;
    FSeed    : LongWord;
    function  Random01: Single;
    procedure Serve;
    procedure BounceOffPaddle(ASide: TSide);
    function  GetPaddleY(ASide: TSide): Single;
    function  GetScore(ASide: TSide): Integer;
    function  GetHasWinner: Boolean;
    function  GetWinner: TSide;
    function  GetWaiting: Boolean;
  public
    constructor Create(ASeed: LongWord);
    procedure Reset;
    { ADt 秒だけ進める。AMove はパドルの向き（-1 = 上、0 = 止まる、1 = 下）。 }
    procedure Step(ADt: Single; ALeftMove, ARightMove: Integer);

    property PaddleY[ASide: TSide]: Single read GetPaddleY;
    property Score[ASide: TSide]: Integer read GetScore;
    property BallX: Single read FBallX;
    property BallY: Single read FBallY;
    property VelX: Single read FVelX;
    property VelY: Single read FVelY;
    // 得点の後、次のサーブを待っている間は True。球は中央で止まっている。
    property Waiting: Boolean read GetWaiting;
    property Hits: Integer read FHits;
    property HasWinner: Boolean read GetHasWinner;
    property Winner: TSide read GetWinner;
  end;

  { パドルを動かすもの。1 刻みごとに向きを返す。 }
  TController = class abstract
  public
    function Decide(AGame: TPongGame; ASide: TSide): Integer; virtual; abstract;
  end;

  { キーを押している間だけ動く。押下状態はキーボードの状態機械に問い合わせ、
    キーは位置（スキャンコード）で指定する。配列が変わっても同じ場所で動く。 }
  TKeyboardController = class(TController)
  strict private
    FKeyboard: TPMLKeyboardState;
    FUp, FDown: array of TPMLScancode;
    function AnyDown(const AKeys: array of TPMLScancode): Boolean;
  public
    constructor Create(AKeyboard: TPMLKeyboardState;
      const AUp, ADown: array of TPMLScancode);
    function Decide(AGame: TPongGame; ASide: TSide): Integer; override;
  end;

  { 球がこちらへ向かっている間は球の高さを追い、離れている間は中央へ戻る。
    打ち返すたびに狙いを少しずらすので、速くなると取りこぼす。 }
  TComputerController = class(TController)
  strict private
    FAimOffset: Single;
    FLastHits : Integer;
    FSeed     : LongWord;
  public
    constructor Create(ASeed: LongWord);
    function Decide(AGame: TPongGame; ASide: TSide): Integer; override;
  end;

  { 盤面を描く。ウィンドウへ合わせるのはレンダラの論理解像度に任せる。 }
  TPongView = class
  strict private
    FRenderer: TPMLRenderer;
    procedure Fill(AX, AY, AW, AH: Single; const AColor: TPMLColor);
    procedure DrawText(AX, AY, AScale: Single; const AText: String;
      const AColor: TPMLColor);
  public
    constructor Create(ARenderer: TPMLRenderer);
    procedure Draw(AGame: TPongGame; APaused: Boolean; ATime: Double);
    { 論理座標の点が、ウィンドウのどの画素に描かれるか。検査用。 }
    procedure LogicalToWindow(AX, AY: Single; out AWX, AWY: Integer);
  end;

const
  ColorBorder : TPMLColor = (R: 0;   G: 0;   B: 0;   A: 255);
  ColorField  : TPMLColor = (R: 20;  G: 24;  B: 30;  A: 255);
  ColorLine   : TPMLColor = (R: 70;  G: 76;  B: 88;  A: 255);
  ColorPaddle : TPMLColor = (R: 240; G: 240; B: 240; A: 255);
  ColorBall   : TPMLColor = (R: 255; G: 214; B: 64;  A: 255);
  ColorGlow   : TPMLColor = (R: 255; G: 214; B: 64;  A: 60);
  ColorScore  : TPMLColor = (R: 150; G: 160; B: 176; A: 255);
  ColorShade  : TPMLColor = (R: 0;   G: 0;   B: 0;   A: 140);

{ ---- TPongGame ---- }

constructor TPongGame.Create(ASeed: LongWord);
begin
  inherited Create;
  FSeed := ASeed;
  Reset;
end;

// 再現できるよう自前の線形合同法を使う（検査で同じ試合を毎回再生する）。
function TPongGame.Random01: Single;
begin
  FSeed := FSeed * 1664525 + 1013904223;
  Result := (FSeed shr 8) / 16777216;
end;

procedure TPongGame.Reset;
var
  S: TSide;
begin
  for S := Low(TSide) to High(TSide) do
  begin
    FPaddleY[S] := (FieldH - PaddleH) / 2;
    FScore[S] := 0;
  end;
  FHits := 0;
  if Random01 < 0.5 then
    FServeTo := TSide.Left
  else
    FServeTo := TSide.Right;
  FServeTimer := ServeDelay;
  FBallX := (FieldW - BallSize) / 2;
  FBallY := (FieldH - BallSize) / 2;
  FVelX := 0;
  FVelY := 0;
end;

// 中央から、FServeTo の側へ ±30 度の範囲で打ち出す。
procedure TPongGame.Serve;
var
  Angle: Single;
begin
  Angle := (Random01 * 2 - 1) * (30 * Pi / 180);
  FBallX := (FieldW - BallSize) / 2;
  FBallY := (FieldH - BallSize) / 2;
  FVelX := BallStartSpeed * Cos(Angle);
  if FServeTo = TSide.Left then
    FVelX := -FVelX;
  FVelY := BallStartSpeed * Sin(Angle);
end;

{ パドルのどこに当たったかで返す角度を決める。中央なら水平、端ほど角度が付く。 }
procedure TPongGame.BounceOffPaddle(ASide: TSide);
var
  Rel, Angle, Speed: Single;
begin
  Rel := ((FBallY + BallSize / 2) - (FPaddleY[ASide] + PaddleH / 2)) / (PaddleH / 2);
  Rel := EnsureRange(Rel, -1, 1);
  Angle := Rel * MaxBounceAngle;
  Speed := Min(Hypot(FVelX, FVelY) * SpeedUpPerHit, BallMaxSpeed);
  FVelX := Speed * Cos(Angle);
  if ASide = TSide.Right then
    FVelX := -FVelX;
  FVelY := Speed * Sin(Angle);
  Inc(FHits);
end;

procedure TPongGame.Step(ADt: Single; ALeftMove, ARightMove: Integer);
var
  LeftFace, RightFace: Single;

  function OverlapsPaddle(ASide: TSide): Boolean;
  begin
    Result := (FBallY + BallSize >= FPaddleY[ASide])
          and (FBallY <= FPaddleY[ASide] + PaddleH);
  end;

begin
  if HasWinner then
    Exit;

  FPaddleY[TSide.Left] := EnsureRange(
    FPaddleY[TSide.Left] + Sign(ALeftMove) * PaddleSpeed * ADt, 0, FieldH - PaddleH);
  FPaddleY[TSide.Right] := EnsureRange(
    FPaddleY[TSide.Right] + Sign(ARightMove) * PaddleSpeed * ADt, 0, FieldH - PaddleH);

  if FServeTimer > 0 then
  begin
    FServeTimer := FServeTimer - ADt;
    if FServeTimer <= 0 then
      Serve;
    Exit;
  end;

  FBallX := FBallX + FVelX * ADt;
  FBallY := FBallY + FVelY * ADt;

  // 上下の壁。はみ出した分を折り返す。
  if FBallY < 0 then
  begin
    FBallY := -FBallY;
    FVelY := -FVelY;
  end
  else if FBallY + BallSize > FieldH then
  begin
    FBallY := 2 * (FieldH - BallSize) - FBallY;
    FVelY := -FVelY;
  end;

  // パドル。こちらへ向かっていて、面を越え、厚みの中にあるときだけ返す。
  LeftFace := PaddleMargin + PaddleW;
  RightFace := FieldW - PaddleMargin - PaddleW;
  if (FVelX < 0) and (FBallX <= LeftFace) and (FBallX + BallSize >= PaddleMargin)
  and OverlapsPaddle(TSide.Left) then
  begin
    FBallX := LeftFace;
    BounceOffPaddle(TSide.Left);
  end
  else if (FVelX > 0) and (FBallX + BallSize >= RightFace)
  and (FBallX <= RightFace + PaddleW) and OverlapsPaddle(TSide.Right) then
  begin
    FBallX := RightFace - BallSize;
    BounceOffPaddle(TSide.Right);
  end;

  // 得点。取られた側へ次のサーブを出す。
  if FBallX + BallSize < 0 then
  begin
    Inc(FScore[TSide.Right]);
    FServeTo := TSide.Left;
    FServeTimer := ServeDelay;
  end
  else if FBallX > FieldW then
  begin
    Inc(FScore[TSide.Left]);
    FServeTo := TSide.Right;
    FServeTimer := ServeDelay;
  end;
  if FServeTimer > 0 then
  begin
    FBallX := (FieldW - BallSize) / 2;
    FBallY := (FieldH - BallSize) / 2;
    FVelX := 0;
    FVelY := 0;
  end;
end;

function TPongGame.GetPaddleY(ASide: TSide): Single;
begin
  Result := FPaddleY[ASide];
end;

function TPongGame.GetScore(ASide: TSide): Integer;
begin
  Result := FScore[ASide];
end;

function TPongGame.GetHasWinner: Boolean;
begin
  Result := (FScore[TSide.Left] >= WinScore) or (FScore[TSide.Right] >= WinScore);
end;

function TPongGame.GetWaiting: Boolean;
begin
  Result := FServeTimer > 0;
end;

function TPongGame.GetWinner: TSide;
begin
  if FScore[TSide.Left] >= WinScore then
    Result := TSide.Left
  else
    Result := TSide.Right;
end;

{ ---- コントローラ ---- }

constructor TKeyboardController.Create(AKeyboard: TPMLKeyboardState;
  const AUp, ADown: array of TPMLScancode);
var
  I: Integer;
begin
  inherited Create;
  FKeyboard := AKeyboard;
  SetLength(FUp, Length(AUp));
  for I := 0 to High(AUp) do
    FUp[I] := AUp[I];
  SetLength(FDown, Length(ADown));
  for I := 0 to High(ADown) do
    FDown[I] := ADown[I];
end;

function TKeyboardController.AnyDown(const AKeys: array of TPMLScancode): Boolean;
var
  K: TPMLScancode;
begin
  for K in AKeys do
    if FKeyboard.IsDown[K] then
      Exit(True);
  Result := False;
end;

function TKeyboardController.Decide(AGame: TPongGame; ASide: TSide): Integer;
begin
  Result := Ord(AnyDown(FDown)) - Ord(AnyDown(FUp));
end;

constructor TComputerController.Create(ASeed: LongWord);
begin
  inherited Create;
  FSeed := ASeed;
  FLastHits := -1;
end;

function TComputerController.Decide(AGame: TPongGame; ASide: TSide): Integer;
const
  DeadZone = 6;
var
  Target, Center: Single;
  Incoming: Boolean;
begin
  // 打ち返しがあるたびに、パドルのどこで受けるかを選び直す。
  if AGame.Hits <> FLastHits then
  begin
    FLastHits := AGame.Hits;
    FSeed := FSeed * 1664525 + 1013904223;
    FAimOffset := ((FSeed shr 8) / 16777216 * 2 - 1) * PaddleH * 0.55;
  end;

  if ASide = TSide.Left then
    Incoming := AGame.VelX < 0
  else
    Incoming := AGame.VelX > 0;
  if Incoming then
    Target := AGame.BallY + BallSize / 2 + FAimOffset
  else
    Target := FieldH / 2;

  Center := AGame.PaddleY[ASide] + PaddleH / 2;
  if Target < Center - DeadZone then
    Result := -1
  else if Target > Center + DeadZone then
    Result := 1
  else
    Result := 0;
end;

{ ---- TPongView ---- }

constructor TPongView.Create(ARenderer: TPMLRenderer);
begin
  inherited Create;
  FRenderer := ARenderer;
  // 盤面の座標のまま描く。縦横比を保ってウィンドウに収め、余りは帯になる。
  // ウィンドウの大きさが変わっても、レンダラが当てはめ直す。
  FRenderer.SetLogicalPresentation(FieldW, FieldH, TPMLLogicalPresentation.Letterbox);
end;

procedure TPongView.Fill(AX, AY, AW, AH: Single; const AColor: TPMLColor);
begin
  FRenderer.DrawColor := AColor;
  FRenderer.FillRect(TPMLFRect.Make(AX, AY, AW, AH));
end;

{ 文字を AScale 倍で描く。倍率は描く間だけ掛け、座標もその倍率で割っておく。 }
procedure TPongView.DrawText(AX, AY, AScale: Single; const AText: String;
  const AColor: TPMLColor);
begin
  FRenderer.Scale := TPMLFPoint.Make(AScale, AScale);
  FRenderer.DrawColor := AColor;
  FRenderer.DebugText(AX / AScale, AY / AScale, AText);
  FRenderer.Scale := TPMLFPoint.Make(1, 1);
end;

procedure TPongView.LogicalToWindow(AX, AY: Single; out AWX, AWY: Integer);
var
  P: TPMLFPoint;
begin
  P := FRenderer.RenderCoordinatesToWindow(AX, AY);
  AWX := Floor(P.X);
  AWY := Floor(P.Y);
end;

procedure TPongView.Draw(AGame: TPongGame; APaused: Boolean; ATime: Double);
const
  ScoreScale = 5;           // 8x8 の文字を 40x40 に
var
  Y: Single;
  S: TSide;
  Blink: Boolean;
begin
  FRenderer.BlendMode := TPMLBlendMode.None;
  FRenderer.DrawColor := ColorBorder;
  FRenderer.Clear;
  Fill(0, 0, FieldW, FieldH, ColorField);

  Y := 8;
  while Y < FieldH do
  begin
    Fill(FieldW / 2 - 2, Y, 4, 12, ColorLine);
    Y := Y + 24;
  end;

  // 勝った側の点数は点滅させる。
  Blink := AGame.HasWinner and (Frac(ATime * 2) < 0.5);
  if not (Blink and (AGame.Winner = TSide.Left)) then
    DrawText(FieldW / 2 - 64, 24, ScoreScale, IntToStr(AGame.Score[TSide.Left]), ColorScore);
  if not (Blink and (AGame.Winner = TSide.Right)) then
    DrawText(FieldW / 2 + 24, 24, ScoreScale, IntToStr(AGame.Score[TSide.Right]), ColorScore);
  if AGame.HasWinner then
    DrawText(FieldW / 2 - 6 * 16, FieldH - 48, 2, 'SPACE: AGAIN', ColorScore);

  for S := Low(TSide) to High(TSide) do
    if S = TSide.Left then
      Fill(PaddleMargin, AGame.PaddleY[S], PaddleW, PaddleH, ColorPaddle)
    else
      Fill(FieldW - PaddleMargin - PaddleW, AGame.PaddleY[S], PaddleW, PaddleH, ColorPaddle);

  // 球の周りに薄い光。半透明の合成で描く。
  FRenderer.BlendMode := TPMLBlendMode.Blend;
  Fill(AGame.BallX - 4, AGame.BallY - 4, BallSize + 8, BallSize + 8, ColorGlow);
  FRenderer.BlendMode := TPMLBlendMode.None;
  Fill(AGame.BallX, AGame.BallY, BallSize, BallSize, ColorBall);

  if APaused then
  begin
    FRenderer.BlendMode := TPMLBlendMode.Blend;
    Fill(0, 0, FieldW, FieldH, ColorShade);
    FRenderer.BlendMode := TPMLBlendMode.None;
    Fill(FieldW / 2 - 22, FieldH / 2 - 30, 14, 60, ColorPaddle);
    Fill(FieldW / 2 + 8, FieldH / 2 - 30, 14, 60, ColorPaddle);
    DrawText(FieldW / 2 - 8 * 2 * 8, FieldH / 2 + 48, 2, 'P: RESUME  2: 2P', ColorPaddle);
  end;
end;

{ ---- 遊ぶ ---- }

procedure Play;
var
  Ctx      : TPMLContext;
  Win      : TPMLWindow;
  R        : TPMLRenderer;
  Game     : TPongGame;
  View     : TPongView;
  Solo     : TKeyboardController;   // 1 人用: W / S と ↑ / ↓ のどちらでも
  DuoLeft  : TKeyboardController;   // 2 人対戦の左: W / S
  DuoRight : TKeyboardController;   // 2 人対戦の右: ↑ / ↓
  Computer : TComputerController;
  Left, Right: TController;
  Ev       : TPMLEvent;
  Running, Paused, TwoPlayers, VSyncOn: Boolean;
  Start, Last, Now, FrameStart, Spent, MinFrame: UInt64;
  Acc      : Double;

begin
  Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
  Solo := TKeyboardController.Create(Ctx.Events.Keyboard,
    [TPMLScancode.W, TPMLScancode.UP], [TPMLScancode.S, TPMLScancode.DOWN]);
  DuoLeft := TKeyboardController.Create(Ctx.Events.Keyboard,
    [TPMLScancode.W], [TPMLScancode.S]);
  DuoRight := TKeyboardController.Create(Ctx.Events.Keyboard,
    [TPMLScancode.UP], [TPMLScancode.DOWN]);
  Computer := TComputerController.Create(LongWord(GetTickCount64));
  Game := TPongGame.Create(LongWord(GetTickCount64 xor $5EED));
  View := nil;
  try
    Win := Ctx.Video.CreateWindow(
      TPMLWindowOptions.Make('papimela pong', 960, 600).Resizable);
    R := TPMLRenderer.CreateForWindow(Win);
    VSyncOn := True;
    try
      R.VSync := 1;
    except
      // VSync が使えなければ、1 フレームの残りを自分で眠って 60 fps に抑える。
      on E: EPMLUnsupported do
      begin
        WriteLn('VSync なしで動かします（60 fps に抑えます）: ', E.Message);
        VSyncOn := False;
      end;
    end;
    View := TPongView.Create(R);

    Running := True;
    Paused := False;
    TwoPlayers := False;
    Left := Solo;
    Right := Computer;
    Acc := 0;
    Start := Ctx.Timer.TicksNS;
    Last := Start;
    while Running do
    begin
      FrameStart := Ctx.Timer.TicksNS;
      Ctx.Events.Pump(0);
      while Ctx.Events.Poll(Ev) do
        case Ev.Kind of
          TPMLEventKind.Quit, TPMLEventKind.WindowCloseRequested:
            Running := False;
          // パドルは IsDown で読むので、ここで扱うのはショートカットだけ。
          // ショートカットはキーの意味（Key）で見る。AZERTY でも P は P。
          TPMLEventKind.KeyDown:
            if not Ev.Key.IsRepeat then
              case Ev.Key.Key of
                PMLK_ESCAPE: Running := False;
                PMLK_P: Paused := not Paused;
                PMLK_2:
                  begin
                    TwoPlayers := not TwoPlayers;
                    if TwoPlayers then
                    begin
                      Left := DuoLeft;
                      Right := DuoRight;
                      Win.Title := 'papimela pong — 2 人対戦';
                    end
                    else
                    begin
                      Left := Solo;
                      Right := Computer;
                      Win.Title := 'papimela pong';
                    end;
                  end;
                PMLK_SPACE:
                  if Game.HasWinner then
                    Game.Reset;
              end;
        end;

      Now := Ctx.Timer.TicksNS;
      // 止まっていた（ウィンドウを掴んでいた等）ときに一度に進めすぎない。
      Acc := Acc + Min((Now - Last) / 1e9, 0.1);
      Last := Now;
      if Paused then
        Acc := 0;
      while Acc >= StepSeconds do
      begin
        Game.Step(StepSeconds, Left.Decide(Game, TSide.Left),
          Right.Decide(Game, TSide.Right));
        Acc := Acc - StepSeconds;
      end;

      View.Draw(Game, Paused, (Now - Start) / 1e9);
      R.Present;
      // Present が待たなかったら、残りの時間を眠り、CPU を使い切らない（F-6）。
      if VSyncOn then
        MinFrame := FrameNSVSync
      else
        MinFrame := FrameNSNoVSync;
      Spent := Ctx.Timer.TicksNS - FrameStart;
      if Spent < MinFrame then
        Ctx.Timer.DelayNS(MinFrame - Spent);
    end;
    // レンダラはウィンドウと一緒に消える。
    Win.Free;
  finally
    View.Free;
    Game.Free;
    Computer.Free;
    DuoRight.Free;
    DuoLeft.Free;
    Solo.Free;
    Ctx.Free;
  end;
end;

{ ---- 自己検査（表示サーバ無し） ---- }

var
  Failures: Integer = 0;

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

function SameRGB(const A, B: TPMLColor): Boolean;
begin
  Result := (A.R = B.R) and (A.G = B.G) and (A.B = B.B);
end;

{ 描いた画面の、論理座標 (AX, AY) にあたる画素の色。 }
function PixelAt(AR: TPMLRenderer; AView: TPongView; AX, AY: Single): TPMLColor;
var
  S: TPMLSurface;
  WX, WY: Integer;
begin
  AView.LogicalToWindow(AX, AY, WX, WY);
  S := AR.ReadPixels(TPMLRect.Make(WX, WY, 1, 1));
  try
    Result := S.ReadPixel(0, 0);
  finally
    S.Free;
  end;
end;

{ 論理座標の矩形の中に、AColor の画素がいくつあるか。 }
function CountColor(AR: TPMLRenderer; AView: TPongView; AX, AY, AW, AH: Single;
  const AColor: TPMLColor): Integer;
var
  S: TPMLSurface;
  X1, Y1, X2, Y2, X, Y: Integer;
begin
  AView.LogicalToWindow(AX, AY, X1, Y1);
  AView.LogicalToWindow(AX + AW, AY + AH, X2, Y2);
  S := AR.ReadPixels(TPMLRect.Make(X1, Y1, X2 - X1, Y2 - Y1));
  try
    Result := 0;
    for Y := 0 to S.Height - 1 do
      for X := 0 to S.Width - 1 do
        if SameRGB(S.ReadPixel(X, Y), AColor) then
          Inc(Result);
  finally
    S.Free;
  end;
end;

{ シートが届けるのと同じ形で、スキャンコードだけのキーを流す。 }
procedure SendKey(ACtx: TPMLContext; AWin: TPMLWindow; AScancode: TPMLScancode;
  ADown: Boolean);
var
  K: TPMLKeyEventData;
begin
  FillChar(K, SizeOf(K), 0);
  K.Scancode := AScancode;
  ACtx.Events.Keyboard.SendKey(AWin.ID, K, ADown, '');
end;

procedure SelfTest;
const
  SimSeconds = 60;
  StepsPerFrame = 4;              // 240 刻み / 秒を 60 フレーム / 秒で描く
var
  Opts : TPMLContextOptions;
  Ctx  : TPMLContext;
  Win  : TPMLWindow;
  R    : TPMLRenderer;
  Game : TPongGame;
  View : TPongView;
  A, B : TComputerController;
  Kb   : TKeyboardController;
  I, Steps, Done, OutOfField, PaddleOut, Frames, Serves: Integer;
  WasWaiting: Boolean;
  S    : TSide;
begin
  WriteLn('pong --selftest — コンピュータ同士の対戦を再生して検査する');
  WriteLn;
  Opts := TPMLContextOptions.Default;
  Opts.PreferredVideo := 'dummy';
  Ctx := TPMLContext.Create([TPMLSubsystem.Video], Opts);
  Game := TPongGame.Create(12345);
  A := TComputerController.Create(111);
  B := TComputerController.Create(222);
  View := nil;
  try
    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('pong selftest', 640, 400));
    R := TPMLRenderer.CreateForWindow(Win);
    View := TPongView.Create(R);

    WriteLn('1. 盤面');
    Steps := Round(SimSeconds / StepSeconds);
    OutOfField := 0;
    PaddleOut := 0;
    Frames := 0;
    Serves := 0;
    WasWaiting := Game.Waiting;
    Done := 0;
    for I := 1 to Steps do
    begin
      Done := I;
      Game.Step(StepSeconds, A.Decide(Game, TSide.Left), B.Decide(Game, TSide.Right));
      if WasWaiting and not Game.Waiting then
        Inc(Serves);
      WasWaiting := Game.Waiting;
      // 球は上下の壁の内側にいる。左右は得点の瞬間だけ外へ出てよい。
      if (Game.BallY < 0) or (Game.BallY + BallSize > FieldH)
      or (Game.BallX < -BallSize - 8) or (Game.BallX > FieldW + 8) then
        Inc(OutOfField);
      for S := Low(TSide) to High(TSide) do
        if (Game.PaddleY[S] < 0) or (Game.PaddleY[S] + PaddleH > FieldH) then
          Inc(PaddleOut);
      if I mod StepsPerFrame = 0 then
      begin
        View.Draw(Game, False, I * StepSeconds);
        R.Present;
        Inc(Frames);
      end;
      if Game.HasWinner then
        Break;
    end;
    WriteLn(Format('  （%.1f 秒ぶん、%d 対 %d、打ち返し %d 回、サーブ %d 回、描画 %d フレーム）',
      [Done * StepSeconds, Game.Score[TSide.Left], Game.Score[TSide.Right],
       Game.Hits, Serves, Frames]));
    Check(OutOfField = 0, '球は盤面の外へ出ない');
    Check(PaddleOut = 0, 'パドルは盤面の外へ出ない');
    Check(Game.Hits >= 10, '打ち返しが起きている');
    Check(Game.Score[TSide.Left] + Game.Score[TSide.Right] >= 1, '得点が入る');
    Check(Serves = Game.Score[TSide.Left] + Game.Score[TSide.Right] + 1,
      'サーブの回数は得点 + 1（最初のサーブ）');

    WriteLn;
    WriteLn('2. 描画（640x400 は拡大なし）');
    View.Draw(Game, False, 0);
    R.Present;
    Check(SameRGB(PixelAt(R, View, PaddleMargin + PaddleW / 2,
      Game.PaddleY[TSide.Left] + PaddleH / 2), ColorPaddle), '左のパドル');
    Check(SameRGB(PixelAt(R, View, FieldW - PaddleMargin - PaddleW / 2,
      Game.PaddleY[TSide.Right] + PaddleH / 2), ColorPaddle), '右のパドル');
    Check(SameRGB(PixelAt(R, View, FieldW / 4, FieldH - 4), ColorField), '盤面の地の色');
    Check(CountColor(R, View, FieldW / 2 - 64, 24, 40, 40, ColorScore) > 100,
      '左の得点が文字（DebugText）で描かれている');
    Check(CountColor(R, View, FieldW / 2 + 24, 24, 40, 40, ColorScore) > 100,
      '右の得点が文字（DebugText）で描かれている');

    WriteLn;
    WriteLn('3. ウィンドウを横長にすると、縦横比を保って左右に帯が付く');
    Win.SetSize(1000, 400);
    View.Draw(Game, False, 0);
    R.Present;
    Check(SameRGB(PixelAt(R, View, PaddleMargin + PaddleW / 2,
      Game.PaddleY[TSide.Left] + PaddleH / 2), ColorPaddle), '左のパドルが帯の内側にある');
    Check(SameRGB(PixelAt(R, View, FieldW / 4, FieldH - 4), ColorField), '盤面の地の色');
    Check(SameRGB(PixelAt(R, View, -1, FieldH / 2), ColorBorder), '盤面の左外は帯の色');

    WriteLn;
    WriteLn('4. 一時停止の表示');
    View.Draw(Game, True, 0);
    R.Present;
    Check(SameRGB(PixelAt(R, View, FieldW / 2 - 15, FieldH / 2), ColorPaddle),
      '一時停止の記号が出る');
    Check(not SameRGB(PixelAt(R, View, FieldW / 4, FieldH - 4), ColorField),
      '盤面が暗くなる');

    WriteLn;
    WriteLn('5. キーボードのパドル（キーの位置で読む）');
    Kb := TKeyboardController.Create(Ctx.Events.Keyboard,
      [TPMLScancode.W, TPMLScancode.UP], [TPMLScancode.S, TPMLScancode.DOWN]);
    try
      Check(Kb.Decide(Game, TSide.Left) = 0, '何も押していなければ止まる');
      SendKey(Ctx, Win, TPMLScancode.S, True);
      Check(Kb.Decide(Game, TSide.Left) = 1, 'S を押している間は下へ');
      SendKey(Ctx, Win, TPMLScancode.S, False);
      SendKey(Ctx, Win, TPMLScancode.UP, True);
      Check(Kb.Decide(Game, TSide.Left) = -1, '↑ を押している間は上へ');
      Ctx.Events.Keyboard.SendFocus(Win.ID, False);
      Check(Kb.Decide(Game, TSide.Left) = 0,
        'フォーカスを失ったら止まる（押しっぱなしが残らない）');
    finally
      Kb.Free;
    end;
    Win.Free;
  finally
    View.Free;
    B.Free;
    A.Free;
    Game.Free;
    Ctx.Free;
  end;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: Pong は表示サーバ無しでも最後まで動く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end;

begin
  if (ParamCount >= 1) and (ParamStr(1) = '--selftest') then
    SelfTest
  else
    Play;
end.
