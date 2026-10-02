{
  PaPiMeLa.Video.Dummy — 画面を持たないビデオバックエンド

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §3.2、§3.3、§11 #34

  WHAT:
    コンポジタに繋がずにウィンドウとディスプレイを成立させる。ピクセルは
    ただのメモリで、描いた内容はどこにも表示されない。

  WHY:
    テストを Wayland セッションから切り離すため。CI には表示サーバが無く、
    現在の自動テストはすべて実機のコンポジタに依存している。ここが入ると
    公開 API（TPMLVideoSystem / TPMLWindow / イベントキュー）の検証だけは
    ヘッドレスで回せるようになる（第 11 章 #70）。

  RESOLVED:
    - 環境変数 PAPIMELA_VIDEO=dummy で選ぶ。既定では Wayland を先に試す
    - ディスプレイの大きさは PAPIMELA_DUMMY_SIZE=幅x高さ で変えられる。
      既定は 1280x720 固定で、実行するたびに変わらないようにしてある

  NOT RESOLVED:
    - 入力は一切発生しない。キーやポインタを流したいテストは
      TPMLKeyboardState などへ直接合成イベントを送る（test_key_routing と同じ方法）
    - ウィンドウの重なりやフォーカスの概念が無い。Flags の InputFocus は
      生成時から立てたままにする

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Dummy;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Pixels,
  PaPiMeLa.Events,
  PaPiMeLa.Video.Backend;

type
  TPMLDummyDisplayBackend = class(TPMLDisplayBackend)
  strict private
    FIndex : Integer;
    FWidth : Integer;
    FHeight: Integer;
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject;
      AIndex, AWidth, AHeight: Integer);
    function GetName: String; override;
    function GetBounds: TPMLRect; override;
    function GetDesktopMode: TPMLDisplayMode; override;
  end;

  { ピクセルはヒープ上の 32bit バッファ。Pitch は幅 * 4。 }
  TPMLDummyWindowBackend = class(TPMLWindowBackend)
  strict private
    FSink  : IPMLVideoSink;
    FTitle : String;
    FWidth : Integer;
    FHeight: Integer;
    FFlags : TPMLWindowFlags;
    FVisible: Boolean;
    FPixels: Pointer;
    FPixelBytes: PtrUInt;
    FPresentCount: Integer;
    FVSync: Integer;
    procedure FreePixels;
    // 現在の状態フラグを Sink へ通知する。Maximize / Minimize / Restore が使う。
    procedure ReportState(const AAdd, ARemove: TPMLWindowFlags);
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject;
      ASink: IPMLVideoSink; AWindowID: TPMLWindowID; const ATitle: String;
      AWidth, AHeight: Integer; AFlags: TPMLWindowFlags);
    destructor Destroy; override;

    procedure SetTitle(const ATitle: String); override;
    procedure SetSize(AWidth, AHeight: Integer); override;
    procedure Show; override;
    procedure Hide; override;
    procedure Maximize; override;
    procedure Minimize; override;
    procedure Restore; override;
    procedure GetSizeInPixels(out AWidth, AHeight: Integer); override;
    function  CreateFramebuffer(out APixels: Pointer; out APitch: Integer;
      out AFormat: TPMLPixelFormat): Boolean; override;
    procedure UpdateFramebuffer; override;
    procedure DestroyFramebuffer; override;
    function  SetFramebufferVSync(AInterval: Integer): Boolean; override;

    property Title  : String read FTitle;
    property Visible: Boolean read FVisible;
    property Flags  : TPMLWindowFlags read FFlags;
    // 検査用。UpdateFramebuffer が呼ばれた回数と、最後に設定された VSync。
    property PresentCount: Integer read FPresentCount;
    property VSync: Integer read FVSync;
  end;

  TPMLDummyVideoBackend = class(TPMLVideoBackend)
  strict private
    FWidth : Integer;
    FHeight: Integer;
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject);
    function  BackendName: String; override;
    function  Connect(ASink: IPMLVideoSink): Boolean; override;
    function  EnumerateDisplays: TPMLDisplayBackends; override;
    function  CreateWindowBackend(AWindowID: TPMLWindowID; const ATitle: String;
      AWidth, AHeight: Integer; AFlags: TPMLWindowFlags): TPMLWindowBackend; override;
    procedure PumpEvents; override;
    procedure WaitEvents(ATimeoutMs: Integer); override;

    property DisplayWidth : Integer read FWidth;
    property DisplayHeight: Integer read FHeight;
  end;

implementation

constructor TPMLDummyDisplayBackend.Create(AContextRef: TObject; AOwner: TPMLObject;
  AIndex, AWidth, AHeight: Integer);
begin
  inherited Create(AContextRef, AOwner);
  FIndex := AIndex;
  FWidth := AWidth;
  FHeight := AHeight;
end;

function TPMLDummyDisplayBackend.GetName: String;
begin
  Result := Format('dummy-display-%d', [FIndex]);
end;

function TPMLDummyDisplayBackend.GetBounds: TPMLRect;
begin
  Result := TPMLRect.Make(0, 0, FWidth, FHeight);
end;

function TPMLDummyDisplayBackend.GetDesktopMode: TPMLDisplayMode;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Width := FWidth;
  Result.Height := FHeight;
  Result.PixelDensity := 1.0;
  Result.RefreshRate := 60.0;
  Result.RefreshNumerator := 60000;
  Result.RefreshDenominator := 1000;
end;

constructor TPMLDummyWindowBackend.Create(AContextRef: TObject; AOwner: TPMLObject;
  ASink: IPMLVideoSink; AWindowID: TPMLWindowID; const ATitle: String;
  AWidth, AHeight: Integer; AFlags: TPMLWindowFlags);
begin
  inherited Create(AContextRef, AOwner);
  FSink := ASink;
  FWindowID := AWindowID;
  FTitle := ATitle;
  FWidth := AWidth;
  FHeight := AHeight;
  FFlags := AFlags;
  Include(FFlags, TPMLWindowFlag.InputFocus);
  if not (TPMLWindowFlag.Hidden in AFlags) then
    FVisible := True;
end;

destructor TPMLDummyWindowBackend.Destroy;
begin
  FreePixels;
  inherited Destroy;
end;

procedure TPMLDummyWindowBackend.FreePixels;
begin
  if FPixels <> nil then
  begin
    FreeMem(FPixels);
    FPixels := nil;
    FPixelBytes := 0;
  end;
end;

procedure TPMLDummyWindowBackend.ReportState(const AAdd, ARemove: TPMLWindowFlags);
begin
  FFlags := FFlags - ARemove + AAdd;
  if Assigned(FSink) then
    FSink.WindowStateChanged(FWindowID, FFlags);
end;

procedure TPMLDummyWindowBackend.SetTitle(const ATitle: String);
begin
  FTitle := ATitle;
end;

procedure TPMLDummyWindowBackend.SetSize(AWidth, AHeight: Integer);
begin
  if (AWidth < 1) or (AHeight < 1) then
    Exit;
  if (AWidth = FWidth) and (AHeight = FHeight) then
    Exit;
  FWidth := AWidth;
  FHeight := AHeight;
  FreePixels;
  if Assigned(FSink) then
  begin
    FSink.WindowResized(FWindowID, FWidth, FHeight);
    FSink.WindowPixelSizeChanged(FWindowID, FWidth, FHeight);
  end;
end;

procedure TPMLDummyWindowBackend.Show;
begin
  FVisible := True;
  ReportState([], [TPMLWindowFlag.Hidden]);
end;

procedure TPMLDummyWindowBackend.Hide;
begin
  FVisible := False;
  ReportState([TPMLWindowFlag.Hidden], []);
end;

procedure TPMLDummyWindowBackend.Maximize;
begin
  ReportState([TPMLWindowFlag.Maximized], [TPMLWindowFlag.Minimized]);
end;

procedure TPMLDummyWindowBackend.Minimize;
begin
  ReportState([TPMLWindowFlag.Minimized], [TPMLWindowFlag.Maximized]);
end;

procedure TPMLDummyWindowBackend.Restore;
begin
  ReportState([], [TPMLWindowFlag.Maximized, TPMLWindowFlag.Minimized]);
end;

procedure TPMLDummyWindowBackend.GetSizeInPixels(out AWidth, AHeight: Integer);
begin
  AWidth := FWidth;
  AHeight := FHeight;
end;

function TPMLDummyWindowBackend.CreateFramebuffer(out APixels: Pointer;
  out APitch: Integer; out AFormat: TPMLPixelFormat): Boolean;
var
  Needed: PtrUInt;
begin
  APixels := nil;
  APitch := 0;
  AFormat := PML_PIXELFORMAT_XRGB8888;
  Needed := PtrUInt(FWidth) * PtrUInt(FHeight) * 4;
  if Needed = 0 then
    Exit(False);
  // 大きさが変わっていたら作り直す。SetSize が先に解放しているので通常は nil。
  if (FPixels = nil) or (FPixelBytes <> Needed) then
  begin
    FreePixels;
    GetMem(FPixels, Needed);
    FillChar(FPixels^, Needed, 0);
    FPixelBytes := Needed;
  end;
  APixels := FPixels;
  APitch := FWidth * 4;
  Result := True;
end;

procedure TPMLDummyWindowBackend.UpdateFramebuffer;
begin
  // 表示先が無いので数えるだけ
  Inc(FPresentCount);
end;

// 待つ相手が無いので、値を覚えるだけで常に受け付ける。
function TPMLDummyWindowBackend.SetFramebufferVSync(AInterval: Integer): Boolean;
begin
  Result := AInterval >= 0;
  if Result then
    FVSync := AInterval;
end;

procedure TPMLDummyWindowBackend.DestroyFramebuffer;
begin
  FreePixels;
end;

{ 大きさは PAPIMELA_DUMMY_SIZE=幅x高さ で変えられる。

  片方だけ解釈できた状態で確定させないよう、両方が揃ってから代入する。
  そうしないと "1920xABC" のときに幅だけ変わって高さが既定のまま残る。 }
constructor TPMLDummyVideoBackend.Create(AContextRef: TObject; AOwner: TPMLObject);
var
  Spec: String;
  P, W, H: Integer;
begin
  inherited Create(AContextRef, AOwner);
  FWidth := 1280;
  FHeight := 720;

  Spec := GetEnvironmentVariable('PAPIMELA_DUMMY_SIZE');
  P := Pos('x', Spec);
  if P < 2 then
    Exit;
  if not TryStrToInt(Copy(Spec, 1, P - 1), W) then
    Exit;
  if not TryStrToInt(Copy(Spec, P + 1, Length(Spec) - P), H) then
    Exit;
  if (W < 1) or (H < 1) then
    Exit;
  FWidth := W;
  FHeight := H;
end;

function TPMLDummyVideoBackend.BackendName: String;
begin
  Result := 'dummy';
end;

function TPMLDummyVideoBackend.Connect(ASink: IPMLVideoSink): Boolean;
begin
  FSink := ASink;
  FCapabilities := [TPMLVideoCapability.SoftwareFramebuffer,
                    TPMLVideoCapability.HighDPI,
                    TPMLVideoCapability.WindowPositioning];
  Result := True;
end;

function TPMLDummyVideoBackend.EnumerateDisplays: TPMLDisplayBackends;
begin
  SetLength(Result, 1);
  Result[0] := TPMLDummyDisplayBackend.Create(ContextRef, Self, 0, FWidth, FHeight);
end;

function TPMLDummyVideoBackend.CreateWindowBackend(AWindowID: TPMLWindowID; const ATitle: String;
  AWidth, AHeight: Integer; AFlags: TPMLWindowFlags): TPMLWindowBackend;
begin
  Result := TPMLDummyWindowBackend.Create(ContextRef, Self, FSink, AWindowID, ATitle, AWidth, AHeight, AFlags);
end;

procedure TPMLDummyVideoBackend.PumpEvents;
begin
  // 発生源が無いので何もしない
end;

procedure TPMLDummyVideoBackend.WaitEvents(ATimeoutMs: Integer);
begin
  if ATimeoutMs > 0 then
    Sleep(ATimeoutMs);
end;

{ ---- 登録 ---- }

function CreateDummyVideoBackend(AContextRef: TObject; AOwner: TPMLObject;
  AQueue: TPMLEventQueue): TPMLVideoBackend;
begin
  Result := TPMLDummyVideoBackend.Create(AContextRef, AOwner);
end;

initialization
  // 優先度 0: 既定では、実画面のバックエンドが全部断ったときの最後の候補。
  PMLRegisterVideoBackend('dummy', 0, @CreateDummyVideoBackend);

end.
