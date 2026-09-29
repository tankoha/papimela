{
  PaPiMeLa.TextInput — テキスト入力 / IME の公開モデル

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §7.3（公開モデル）、§7.6（バックエンド選択）

  WHAT:
    アプリが実装する契約（周辺テキストの供給）、バックエンドから通知を受ける
    Sink、ウィンドウごとのセッション、バックエンド選択。通知はイベントキューへ
    TextEditing / TextInput / TextInputDeleteSurrounding として積む。

  WHY:
    SDL の SDL_TextEditingEvent は start / length の 1 組しか持たず、注目文節
    以外の境界を表現できない。各プラットフォームの IME は文節情報を持っている
    ので、それを削らずに公開するのが本プロジェクトの中核目的。

  RESOLVED:
    - 位置はバイトとコードポイントの両方を常に埋める（§7.3）
    - 周辺削除は確定より先にキューへ入れ、間に他のイベントを挟まない。
      バックエンドの Pump が到着順に Sink を呼ぶので順序はそのまま保たれる
    - 文節を提供しないバックエンドは SegmentsReliable = False で全体を 1 文節にする

  NOT RESOLVED:
    - 埋め込み候補（TextEditingCandidates）はバックエンド側が未実装

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.TextInput;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Unicode,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Video,
  PaPiMeLa.Events;

type
  TPMLTextInputCapability = (
    Segments,           // 文節境界を提供できる
    Candidates,         // 候補一覧をアプリに渡せる
    SurroundingText,    // 周辺テキストを IME に供給できる
    DeleteSurrounding,  // 周辺削除要求を受け取れる
    CursorRect,         // カーソル矩形を伝えられる
    KeyFilter           // キーを IME に通して消費判定できる
  );
  TPMLTextInputCapabilities = set of TPMLTextInputCapability;

  TPMLTextInputType = (Text, Name, Email, Username, Password, Number, Phone, Url, Date, Time);

  TPMLTextInputHint = (Multiline, AutoCorrect, AutoCapitalize, Sensitive, EmbedCandidates);
  TPMLTextInputHints = set of TPMLTextInputHint;

  { アプリが実装する契約。papimela が必要なときに呼ぶ。 }
  IPMLTextInputClient = interface
    ['{4A2E8F10-7C3B-4D62-9E15-B8A0D6F23C71}']
    // カーソル周辺の確定済みテキストを返す。AText は UTF-8、位置はその中のバイト位置。
    // 選択が無ければ ACursorByte と AAnchorByte は同じ値。
    function GetSurroundingText(out AText: String;
      out ACursorByte, AAnchorByte: Integer): Boolean;
    // キャレット矩形（ウィンドウ座標、ピクセル）。候補ウィンドウの位置決めに使う。
    function GetCursorRect: TPMLRect;
  end;

  { バックエンド → TextInputSystem の通知経路。 }
  IPMLTextInputSink = interface
    ['{9D71C4E8-2B06-4F3A-8C5D-1E7A94B0F268}']
    procedure CompositionChanged(const AComposition: TPMLComposition);
    procedure TextCommitted(const AText: String);
    procedure DeleteSurroundingRequested(const AData: TPMLDeleteSurroundingData);
    procedure CandidatesChanged(const ACandidates: TPMLStringArray;
      ASelected: Integer; AHorizontal: Boolean);
    procedure BackendLost(const AReason: String);
  end;

  { バックエンドの契約。実装は PaPiMeLa.TextInput.Backend の抽象クラス。

    System 側がこのインターフェースで保持することで、公開モデルのユニットが
    バックエンドのユニットを interface 節で参照せずに済む（循環回避）。 }
  IPMLTextInputBackend = interface
    ['{B3F6A012-5E84-4C79-A1D3-60B85F2E9C47}']
    function  BackendName: String;
    function  Capabilities: TPMLTextInputCapabilities;
    function  Connect(ASink: IPMLTextInputSink): Boolean;
    procedure Disconnect;
    procedure Activate(AType: TPMLTextInputType; AHints: TPMLTextInputHints);
    procedure Deactivate;
    procedure ResetComposition;
    procedure UpdateSurroundingText(const AText: String; ACursorByte, AAnchorByte: Integer);
    procedure UpdateCursorRect(const ARect: TPMLRect; AScale: Double);
    function  FilterKey(const AKey: TPMLKeyEventData; AIsRelease: Boolean): TPMLKeyFilterResult;
    procedure Pump(ATimeoutMs: Integer);
  end;

  TPMLTextInputSystem = class;

  { ウィンドウごとの入力セッション。System.Start が返す。所有は System。 }
  TPMLTextInputSession = class sealed(TPMLSystemObject)
  strict private
    FSystem   : TPMLTextInputSystem;
    FWindow   : TPMLWindow;
    FClient   : IPMLTextInputClient;
    FInputType: TPMLTextInputType;
    FHints    : TPMLTextInputHints;
    function GetCapabilities: TPMLTextInputCapabilities;
    function GetComposing: Boolean;
  private
    // System が Sink 経由で更新する。ユニット内限定。
    FComposition: TPMLComposition;
  public
    constructor Create(ASystem: TPMLTextInputSystem; AWindow: TPMLWindow;
      AClient: IPMLTextInputClient; AType: TPMLTextInputType;
      AHints: TPMLTextInputHints);

    procedure Stop;
    // アプリが IME 以外の要因でバッファを変えた（クリック、Undo）。周辺テキストを再送する。
    procedure NotifyTextChanged;
    procedure NotifyCursorRectChanged;
    procedure ResetComposition;

    property Window      : TPMLWindow read FWindow;
    property Client      : IPMLTextInputClient read FClient;
    property InputType   : TPMLTextInputType read FInputType;
    property Hints       : TPMLTextInputHints read FHints;
    property Composing   : Boolean read GetComposing;
    property Composition : TPMLComposition read FComposition;
    property Capabilities: TPMLTextInputCapabilities read GetCapabilities;
  end;

  { バックエンドを選び、セッションを管理し、通知をイベントキューへ積む。

    CORBA インターフェースは参照カウントしないので、バックエンドの実体を
    FBackendObject で保持して破棄する責任を持つ。 }
  TPMLTextInputSystem = class sealed(TPMLSystemObject,
    IPMLTextInputSink, IPMLEventPumpSource, IPMLKeyFilter)
  strict private
    FQueue        : TPMLEventQueue;
    FBackend      : IPMLTextInputBackend;
    FBackendObject: TObject;
    FSession      : TPMLTextInputSession;
    FSelectedName : String;
    FFocused      : Boolean;
    procedure PushSurroundingText;
    procedure PushComposition(const AComposition: TPMLComposition);
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject;
      AQueue: TPMLEventQueue; const APreferred: String = '');
    destructor Destroy; override;

    function  Start(AWindow: TPMLWindow; AClient: IPMLTextInputClient;
      AType: TPMLTextInputType = TPMLTextInputType.Text;
      AHints: TPMLTextInputHints = []): TPMLTextInputSession;
    procedure Stop;
    // IPMLKeyFilter。キーを IME に通す。Consumed なら KeyDown / KeyUp を積んではならない。
    function  KeyFilterActive: Boolean;
    function  FilterKey(const AKey: TPMLKeyEventData; AIsRelease: Boolean): TPMLKeyFilterResult;
    procedure NotifyFocus(AWindowID: TPMLWindowID; AGained: Boolean);

    // IPMLEventPumpSource
    function  PumpSourceName: String;
    procedure PumpEvents(ATimeoutMs: Integer);

    // IPMLTextInputSink
    procedure CompositionChanged(const AComposition: TPMLComposition);
    procedure TextCommitted(const AText: String);
    procedure DeleteSurroundingRequested(const AData: TPMLDeleteSurroundingData);
    procedure CandidatesChanged(const ACandidates: TPMLStringArray;
      ASelected: Integer; AHorizontal: Boolean);
    procedure BackendLost(const AReason: String);

    property BackendName: String read FSelectedName;
    property Backend    : IPMLTextInputBackend read FBackend;
    property Session    : TPMLTextInputSession read FSession;
  end;

implementation

uses
  PaPiMeLa.TextInput.Backend,
  PaPiMeLa.TextInput.Fcitx;

{ TPMLTextInputSession }

constructor TPMLTextInputSession.Create(ASystem: TPMLTextInputSystem;
  AWindow: TPMLWindow; AClient: IPMLTextInputClient; AType: TPMLTextInputType;
  AHints: TPMLTextInputHints);
begin
  inherited Create(ASystem.ContextRef, ASystem);
  FSystem := ASystem;
  FWindow := AWindow;
  FClient := AClient;
  FInputType := AType;
  FHints := AHints;
  FComposition.Clear;
end;

function TPMLTextInputSession.GetCapabilities: TPMLTextInputCapabilities;
begin
  if Assigned(FSystem) and Assigned(FSystem.Backend) then
    Result := FSystem.Backend.Capabilities
  else
    Result := [];
end;

function TPMLTextInputSession.GetComposing: Boolean;
begin
  Result := not FComposition.IsEmpty;
end;

procedure TPMLTextInputSession.Stop;
begin
  if Assigned(FSystem) then
    FSystem.Stop;
end;

procedure TPMLTextInputSession.NotifyTextChanged;
var
  S: String;
  C, A: Integer;
begin
  if not Assigned(FSystem) or not Assigned(FSystem.Backend) then
    Exit;
  if not (TPMLTextInputCapability.SurroundingText in FSystem.Backend.Capabilities) then
    Exit;
  if not Assigned(FClient) then
    Exit;
  if FClient.GetSurroundingText(S, C, A) then
    FSystem.Backend.UpdateSurroundingText(S, C, A);
end;

procedure TPMLTextInputSession.NotifyCursorRectChanged;
begin
  if not Assigned(FSystem) or not Assigned(FSystem.Backend) then
    Exit;
  if not (TPMLTextInputCapability.CursorRect in FSystem.Backend.Capabilities) then
    Exit;
  if Assigned(FClient) then
    FSystem.Backend.UpdateCursorRect(FClient.GetCursorRect, 1.0);
end;

procedure TPMLTextInputSession.ResetComposition;
begin
  if Assigned(FSystem) and Assigned(FSystem.Backend) then
    FSystem.Backend.ResetComposition;
end;

{ TPMLTextInputSystem }

constructor TPMLTextInputSystem.Create(AContextRef: TObject; AOwner: TPMLObject;
  AQueue: TPMLEventQueue; const APreferred: String);
var
  Wanted: String;

  // 候補を試し、繋がらなければその実体を破棄する。
  function TryBackend(ACandidate: TPMLTextInputBackend): Boolean;
  begin
    Result := False;
    if ACandidate = nil then
      Exit;
    if ((Wanted <> '') and (LowerCase(ACandidate.BackendName) <> Wanted))
      or (not ACandidate.Connect(Self as IPMLTextInputSink)) then
    begin
      ACandidate.Free;
      Exit;
    end;
    FBackend := ACandidate as IPMLTextInputBackend;
    FBackendObject := ACandidate;
    FSelectedName := ACandidate.BackendName;
    Result := True;
  end;

begin
  inherited Create(AContextRef, AOwner);
  FQueue := AQueue;
  Wanted := LowerCase(Trim(APreferred));
  if Wanted = '' then
    Wanted := LowerCase(Trim(GetEnvironmentVariable('PAPIMELA_IME')));

  // §7.6 の順序。IBus は未実装なので Fcitx から試す（spikes/RESULTS.md の判断）。
  if not TryBackend(TPMLFcitxTextInputBackend.Create) then
    if not TryBackend(TPMLNullTextInputBackend.Create) then
      raise EPMLTextInputError.Create('no text input backend could be selected');

  FQueue.RegisterPumpSource(Self as IPMLEventPumpSource);
end;

destructor TPMLTextInputSystem.Destroy;
begin
  if Assigned(FQueue) then
    FQueue.UnregisterPumpSource(Self as IPMLEventPumpSource);
  FreeAndNil(FSession);
  if Assigned(FBackend) then
  begin
    FBackend.Disconnect;
    FBackend := nil;
  end;
  FreeAndNil(FBackendObject);
  inherited Destroy;
end;

function TPMLTextInputSystem.PumpSourceName: String;
begin
  Result := 'textinput:' + FSelectedName;
end;

procedure TPMLTextInputSystem.PumpEvents(ATimeoutMs: Integer);
begin
  if Assigned(FBackend) then
    FBackend.Pump(ATimeoutMs);
end;

function TPMLTextInputSystem.Start(AWindow: TPMLWindow; AClient: IPMLTextInputClient;
  AType: TPMLTextInputType; AHints: TPMLTextInputHints): TPMLTextInputSession;
begin
  CheckMainThread;
  if Assigned(FSession) then
    Stop;
  FSession := TPMLTextInputSession.Create(Self, AWindow, AClient, AType, AHints);
  FBackend.Activate(AType, AHints);
  FFocused := True;
  PushSurroundingText;
  Result := FSession;
end;

procedure TPMLTextInputSystem.Stop;
begin
  if not Assigned(FSession) then
    Exit;
  FBackend.Deactivate;
  FFocused := False;
  FreeAndNil(FSession);
end;

procedure TPMLTextInputSystem.PushSurroundingText;
begin
  if Assigned(FSession) then
    FSession.NotifyTextChanged;
end;

{ ウィンドウのフォーカス変化を IME へ伝える。

  これを送らないと、別アプリへ移っても fcitx5 はこちらの入力コンテキストを
  注目したままになり、2 つのクライアントが同時にフォーカスを持つ状態になる。
  変換中テキストもフォーカスをまたいで残る。

  セッションのウィンドウと一致するフォーカス変化だけを通す。Start / Stop でも
  Activate / Deactivate を呼ぶので、二重呼び出しを FFocused で防ぐ。 }
procedure TPMLTextInputSystem.NotifyFocus(AWindowID: TPMLWindowID; AGained: Boolean);
begin
  if not Assigned(FSession) or not Assigned(FBackend) then
    Exit;
  if Assigned(FSession.Window) and (FSession.Window.ID <> AWindowID) then
    Exit;
  if AGained = FFocused then
    Exit;
  FFocused := AGained;
  if AGained then
  begin
    FBackend.Activate(FSession.InputType, FSession.Hints);
    PushSurroundingText;
  end
  else
    FBackend.Deactivate;
end;

function TPMLTextInputSystem.KeyFilterActive: Boolean;
begin
  Result := Assigned(FSession) and Assigned(FBackend)
    and (TPMLTextInputCapability.KeyFilter in FBackend.Capabilities);
end;

function TPMLTextInputSystem.FilterKey(const AKey: TPMLKeyEventData;
  AIsRelease: Boolean): TPMLKeyFilterResult;
begin
  if not Assigned(FSession) or not Assigned(FBackend) then
    Exit(TPMLKeyFilterResult.PassThrough);
  if not (TPMLTextInputCapability.KeyFilter in FBackend.Capabilities) then
    Exit(TPMLKeyFilterResult.PassThrough);
  Result := FBackend.FilterKey(AKey, AIsRelease);
end;

procedure TPMLTextInputSystem.PushComposition(const AComposition: TPMLComposition);
var
  Ev: TPMLEvent;
  StartChar, LengthChars: Integer;
begin
  FillChar(Ev.Edit, SizeOf(Ev.Edit), 0);
  Ev.Kind := TPMLEventKind.TextEditing;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := 0;
  Ev.Text := AComposition.Text;
  Ev.Segments := AComposition.Segments;
  Ev.Strings := nil;

  Ev.Edit.CursorByte := AComposition.CursorByte;
  Ev.Edit.CursorChar := AComposition.CursorChar;
  Ev.Edit.FocusedSegment := AComposition.FocusedSegment;
  Ev.Edit.SegmentsReliable := AComposition.SegmentsReliable;
  // SDL 互換の単一範囲は注目文節から導出する。
  if (AComposition.FocusedSegment >= 0)
    and (AComposition.FocusedSegment <= High(AComposition.Segments)) then
  begin
    StartChar := AComposition.Segments[AComposition.FocusedSegment].StartChar;
    LengthChars := AComposition.Segments[AComposition.FocusedSegment].EndChar - StartChar;
  end
  else
  begin
    StartChar := AComposition.CursorChar;
    LengthChars := 0;
  end;
  Ev.Edit.SelectionStartChar := StartChar;
  Ev.Edit.SelectionLengthChars := LengthChars;

  FQueue.Push(Ev);
end;

procedure TPMLTextInputSystem.CompositionChanged(const AComposition: TPMLComposition);
begin
  if Assigned(FSession) then
    FSession.FComposition := AComposition;
  PushComposition(AComposition);
end;

procedure TPMLTextInputSystem.TextCommitted(const AText: String);
var
  Ev: TPMLEvent;
begin
  if Assigned(FSession) then
    FSession.FComposition.Clear;

  FillChar(Ev.Key, SizeOf(Ev.Key), 0);
  Ev.Kind := TPMLEventKind.TextInput;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := 0;
  Ev.Text := AText;
  Ev.Segments := nil;
  Ev.Strings := nil;
  FQueue.Push(Ev);
  // 確定後はアプリのバッファが変わっているので周辺テキストを送り直す（§7.3）。
  // アプリは同じ Pump 内で TextInput を処理するので、ここでの再送は
  // 次の Pump 以降に効く。
  PushSurroundingText;
end;

procedure TPMLTextInputSystem.DeleteSurroundingRequested(const AData: TPMLDeleteSurroundingData);
var
  Ev: TPMLEvent;
begin
  FillChar(Ev.DeleteSurrounding, SizeOf(Ev.DeleteSurrounding), 0);
  Ev.Kind := TPMLEventKind.TextInputDeleteSurrounding;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := 0;
  Ev.Text := '';
  Ev.Segments := nil;
  Ev.Strings := nil;
  Ev.DeleteSurrounding := AData;
  FQueue.Push(Ev);
end;

procedure TPMLTextInputSystem.CandidatesChanged(const ACandidates: TPMLStringArray;
  ASelected: Integer; AHorizontal: Boolean);
var
  Ev: TPMLEvent;
begin
  FillChar(Ev.Edit, SizeOf(Ev.Edit), 0);
  Ev.Kind := TPMLEventKind.TextEditingCandidates;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := 0;
  Ev.Text := '';
  Ev.Segments := nil;
  Ev.Strings := ACandidates;
  Ev.Edit.FocusedSegment := ASelected;
  FQueue.Push(Ev);
end;

procedure TPMLTextInputSystem.BackendLost(const AReason: String);
begin
  // §5.2: まずイベントで穏やかに知らせ、次に例外で強制的に知らせる。
  FQueue.PushSimple(TPMLEventKind.BackendLost);
  raise EPMLBackendLost.CreateNative('text input backend lost', 0,
    FSelectedName, AReason);
end;

end.
