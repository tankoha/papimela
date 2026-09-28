{
  PaPiMeLa.TextInput — テキスト入力 / IME の公開モデル

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §7.3（公開モデル）、§7.6（バックエンド選択）

  WHAT:
    変換中テキストを「文節の配列」として表すモデルと、アプリが実装する契約
    （周辺テキストの供給）、バックエンドから通知を受ける Sink、セッション、
    バックエンド選択を行う TPMLTextInputSystem。

  WHY:
    SDL の SDL_TextEditingEvent は start / length の 1 組しか持たず、注目文節
    以外の境界を表現できない。各プラットフォームの IME は文節情報を持っている
    ので、それを削らずに公開するのが本プロジェクトの中核目的。

  RESOLVED:
    - 位置はバイトとコードポイントの両方を常に埋める（§7.3）
    - 周辺削除は確定より先に通知し、間に他の通知を挟まない
    - バックエンドが文節を提供しない場合は SegmentsReliable = False で
      全体を 1 文節として表す

  NOT RESOLVED:
    - 通知はイベントキュー（第 11 章 #13 / #14）へ入れる設計だが、Events が
      未実装のため暫定でメソッドポインタのイベントを公開している。Events
      着手時に TPMLEventKind.TextEditing 等へ置き換える
    - Session.Window は TPMLWindow（#10 Video）が未実装のため TObject
    - 文節の色情報（IBus の foreground / background）は IBus 着手時に追加する

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
  PaPiMeLa.Unicode;

type
  // 文節の状態。かな漢字変換の下線表示を描き分けるために使う。
  TPMLSegmentState = (Unconverted, Converted, Focused);

  // バックエンドが報告した生の下線種別。State の根拠として保持する。
  TPMLUnderlineStyle = (None, Single, Double, Low, Error);

  TPMLCompositionSegment = record
    StartByte, EndByte: Integer;   // Composition.Text 内の UTF-8 バイト範囲 [Start, End)
    StartChar, EndChar: Integer;   // 同じ範囲をコードポイント単位で
    State             : TPMLSegmentState;
    Underline         : TPMLUnderlineStyle;
    function TextOf(const AWhole: String): String;
  end;
  TPMLCompositionSegments = array of TPMLCompositionSegment;

  TPMLComposition = record
    Text                    : String;                  // 変換中テキスト全体
    Segments                : TPMLCompositionSegments;
    CursorByte, CursorChar  : Integer;                 // -1 = 非表示
    FocusedSegment          : Integer;                 // Segments の添字。-1 = なし
    SegmentsReliable        : Boolean;                  // False = バックエンドが文節を提供しない
    function IsEmpty: Boolean;
    // SDL 互換の単一範囲。Focused 文節から導出する。
    procedure GetLegacyRange(out AStartChar, ALengthChars: Integer);
  end;

  TPMLDeleteSurroundingData = record
    BeforeBytes, AfterBytes: Integer;
    BeforeChars, AfterChars: Integer;
  end;

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

  TPMLKeyFilterResult = (Consumed, PassThrough, Deferred);

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
    procedure CandidatesChanged(const ACandidates: array of String;
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
    function  FilterKey(const AKey: TPMLKeyEventData): TPMLKeyFilterResult;
    procedure Pump(ATimeoutMs: Integer);
  end;

  TPMLTextInputSystem = class;

  { ウィンドウごとの入力セッション。System.Start が返す。 }
  TPMLTextInputSession = class
  strict private
    FSystem     : TPMLTextInputSystem;
    FWindow     : TObject;
    FClient     : IPMLTextInputClient;
    FInputType  : TPMLTextInputType;
    FHints      : TPMLTextInputHints;
    FActive     : Boolean;
    function GetCapabilities: TPMLTextInputCapabilities;
    function GetComposing: Boolean;
  private
    // TPMLTextInputSystem が Sink 経由で更新する。ユニット内限定。
    FComposition: TPMLComposition;
  public
    constructor Create(ASystem: TPMLTextInputSystem; AWindow: TObject;
      AClient: IPMLTextInputClient; AType: TPMLTextInputType;
      AHints: TPMLTextInputHints);
    destructor Destroy; override;

    procedure Stop;
    // アプリが IME 以外の要因でバッファを変えた（クリック、Undo）。周辺テキストを再送する。
    procedure NotifyTextChanged;
    procedure NotifyCursorRectChanged;
    procedure ResetComposition;

    property Window      : TObject read FWindow;
    property Client      : IPMLTextInputClient read FClient;
    property InputType   : TPMLTextInputType read FInputType;
    property Hints       : TPMLTextInputHints read FHints;
    property Composing   : Boolean read GetComposing;
    property Composition : TPMLComposition read FComposition;
    property Capabilities: TPMLTextInputCapabilities read GetCapabilities;
  end;

  // 暫定の通知経路。Events 着手時にイベントキューへ置き換える。
  TPMLCompositionEvent  = procedure(ASession: TPMLTextInputSession;
    const AComposition: TPMLComposition) of object;
  TPMLCommitEvent       = procedure(ASession: TPMLTextInputSession;
    const AText: String) of object;
  TPMLDeleteSurroundEvent = procedure(ASession: TPMLTextInputSession;
    const AData: TPMLDeleteSurroundingData) of object;

  { バックエンドを選び、セッションを管理する。

    CORBA インターフェースは参照カウントしないので、バックエンドの実体を
    FBackendObject で保持して破棄する責任を持つ。 }
  TPMLTextInputSystem = class(TObject, IPMLTextInputSink)
  strict private
    FBackend      : IPMLTextInputBackend;
    FBackendObject: TObject;
    FSession      : TPMLTextInputSession;
    FOnComposition      : TPMLCompositionEvent;
    FOnCommit           : TPMLCommitEvent;
    FOnDeleteSurrounding: TPMLDeleteSurroundEvent;
    FLastLog            : String;
    procedure PushSurroundingText;
  public
    constructor Create(const APreferred: String = '');
    destructor Destroy; override;

    function  Start(AWindow: TObject; AClient: IPMLTextInputClient;
      AType: TPMLTextInputType = TPMLTextInputType.Text;
      AHints: TPMLTextInputHints = []): TPMLTextInputSession;
    procedure Stop;
    function  FilterKey(const AKey: TPMLKeyEventData): TPMLKeyFilterResult;
    procedure Pump(ATimeoutMs: Integer = 0);

    // IPMLTextInputSink
    procedure CompositionChanged(const AComposition: TPMLComposition);
    procedure TextCommitted(const AText: String);
    procedure DeleteSurroundingRequested(const AData: TPMLDeleteSurroundingData);
    procedure CandidatesChanged(const ACandidates: array of String;
      ASelected: Integer; AHorizontal: Boolean);
    procedure BackendLost(const AReason: String);

    property BackendName: String read FLastLog;
    property Backend    : IPMLTextInputBackend read FBackend;
    property Session    : TPMLTextInputSession read FSession;

    property OnComposition      : TPMLCompositionEvent read FOnComposition write FOnComposition;
    property OnCommit           : TPMLCommitEvent read FOnCommit write FOnCommit;
    property OnDeleteSurrounding: TPMLDeleteSurroundEvent read FOnDeleteSurrounding
      write FOnDeleteSurrounding;
  end;

// 文節配列から派生情報（コードポイント位置、FocusedSegment）を埋める。
// バックエンドはバイト範囲と State だけ埋めてこれを呼べばよい。
procedure PMLFinalizeComposition(var AComposition: TPMLComposition);

implementation

uses
  PaPiMeLa.TextInput.Backend,
  PaPiMeLa.TextInput.Fcitx;

{ TPMLCompositionSegment }

function TPMLCompositionSegment.TextOf(const AWhole: String): String;
begin
  if (EndByte <= StartByte) or (StartByte < 0) or (EndByte > Length(AWhole)) then
    Exit('');
  Result := Copy(AWhole, StartByte + 1, EndByte - StartByte);
end;

{ TPMLComposition }

function TPMLComposition.IsEmpty: Boolean;
begin
  Result := Text = '';
end;

procedure TPMLComposition.GetLegacyRange(out AStartChar, ALengthChars: Integer);
begin
  if (FocusedSegment >= 0) and (FocusedSegment <= High(Segments)) then
  begin
    AStartChar := Segments[FocusedSegment].StartChar;
    ALengthChars := Segments[FocusedSegment].EndChar - Segments[FocusedSegment].StartChar;
  end
  else
  begin
    AStartChar := CursorChar;
    ALengthChars := 0;
  end;
end;

procedure PMLFinalizeComposition(var AComposition: TPMLComposition);
var
  I: Integer;
begin
  AComposition.FocusedSegment := -1;
  for I := 0 to High(AComposition.Segments) do
  begin
    AComposition.Segments[I].StartChar :=
      UTF8ByteToCharOffset(AComposition.Text, AComposition.Segments[I].StartByte);
    AComposition.Segments[I].EndChar :=
      UTF8ByteToCharOffset(AComposition.Text, AComposition.Segments[I].EndByte);
    if (AComposition.FocusedSegment < 0)
      and (AComposition.Segments[I].State = TPMLSegmentState.Focused) then
      AComposition.FocusedSegment := I;
  end;
  if AComposition.CursorByte >= 0 then
    AComposition.CursorChar :=
      UTF8ByteToCharOffset(AComposition.Text, AComposition.CursorByte)
  else
    AComposition.CursorChar := -1;
end;

{ TPMLTextInputSession }

constructor TPMLTextInputSession.Create(ASystem: TPMLTextInputSystem;
  AWindow: TObject; AClient: IPMLTextInputClient; AType: TPMLTextInputType;
  AHints: TPMLTextInputHints);
begin
  inherited Create;
  FSystem := ASystem;
  FWindow := AWindow;
  FClient := AClient;
  FInputType := AType;
  FHints := AHints;
  FComposition.CursorByte := -1;
  FComposition.CursorChar := -1;
  FComposition.FocusedSegment := -1;
  FActive := True;
end;

destructor TPMLTextInputSession.Destroy;
begin
  FClient := nil;
  inherited Destroy;
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
  if FActive and Assigned(FSystem) then
  begin
    FActive := False;
    FSystem.Stop;
  end;
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

constructor TPMLTextInputSystem.Create(const APreferred: String);
var
  Wanted: String;

  // 候補を試し、繋がらなければその実体を破棄する。
  function TryBackend(ACandidate: TPMLTextInputBackend): Boolean;
  var
    Iface: IPMLTextInputBackend;
  begin
    Result := False;
    if ACandidate = nil then
      Exit;
    Iface := ACandidate as IPMLTextInputBackend;
    if ((Wanted <> '') and (LowerCase(ACandidate.BackendName) <> Wanted))
      or (not ACandidate.Connect(Self as IPMLTextInputSink)) then
    begin
      ACandidate.Free;
      Exit;
    end;
    FBackend := Iface;
    FBackendObject := ACandidate;
    FLastLog := ACandidate.BackendName;
    Result := True;
  end;

begin
  inherited Create;
  Wanted := LowerCase(Trim(APreferred));
  if Wanted = '' then
    Wanted := LowerCase(Trim(GetEnvironmentVariable('PAPIMELA_IME')));

  // §7.6 の順序。IBus は未実装なので Fcitx から試す（spikes/RESULTS.md の判断）。
  if TryBackend(TPMLFcitxTextInputBackend.Create) then
    Exit;
  if TryBackend(TPMLNullTextInputBackend.Create) then
    Exit;
  raise EPMLTextInputError.Create('no text input backend could be selected');
end;

destructor TPMLTextInputSystem.Destroy;
begin
  FreeAndNil(FSession);
  if Assigned(FBackend) then
  begin
    FBackend.Disconnect;
    FBackend := nil;
  end;
  FreeAndNil(FBackendObject);
  inherited Destroy;
end;

function TPMLTextInputSystem.Start(AWindow: TObject; AClient: IPMLTextInputClient;
  AType: TPMLTextInputType; AHints: TPMLTextInputHints): TPMLTextInputSession;
begin
  if Assigned(FSession) then
    Stop;
  FSession := TPMLTextInputSession.Create(Self, AWindow, AClient, AType, AHints);
  FBackend.Activate(AType, AHints);
  PushSurroundingText;
  Result := FSession;
end;

procedure TPMLTextInputSystem.Stop;
begin
  if not Assigned(FSession) then
    Exit;
  FBackend.Deactivate;
  FreeAndNil(FSession);
end;

procedure TPMLTextInputSystem.PushSurroundingText;
begin
  if Assigned(FSession) then
    FSession.NotifyTextChanged;
end;

function TPMLTextInputSystem.FilterKey(const AKey: TPMLKeyEventData): TPMLKeyFilterResult;
begin
  if not Assigned(FSession) or not Assigned(FBackend) then
    Exit(TPMLKeyFilterResult.PassThrough);
  if not (TPMLTextInputCapability.KeyFilter in FBackend.Capabilities) then
    Exit(TPMLKeyFilterResult.PassThrough);
  Result := FBackend.FilterKey(AKey);
end;

procedure TPMLTextInputSystem.Pump(ATimeoutMs: Integer);
begin
  if Assigned(FBackend) then
    FBackend.Pump(ATimeoutMs);
end;

procedure TPMLTextInputSystem.CompositionChanged(const AComposition: TPMLComposition);
begin
  if Assigned(FSession) then
    FSession.FComposition := AComposition;
  if Assigned(FOnComposition) then
    FOnComposition(FSession, AComposition);
end;

procedure TPMLTextInputSystem.TextCommitted(const AText: String);
begin
  if Assigned(FSession) then
  begin
    FSession.FComposition.Text := '';
    FSession.FComposition.Segments := nil;
  end;
  if Assigned(FOnCommit) then
    FOnCommit(FSession, AText);
  // 確定後はアプリのバッファが変わっているので周辺テキストを送り直す（§7.3）。
  PushSurroundingText;
end;

procedure TPMLTextInputSystem.DeleteSurroundingRequested(const AData: TPMLDeleteSurroundingData);
begin
  if Assigned(FOnDeleteSurrounding) then
    FOnDeleteSurrounding(FSession, AData);
  PushSurroundingText;
end;

procedure TPMLTextInputSystem.CandidatesChanged(const ACandidates: array of String;
  ASelected: Integer; AHorizontal: Boolean);
begin
  // 埋め込み候補描画は EmbedCandidates 指定時のみ。Events 着手時にイベント化する。
end;

procedure TPMLTextInputSystem.BackendLost(const AReason: String);
begin
  raise EPMLBackendLost.CreateNative('text input backend lost', 0,
    FLastLog, AReason);
end;

end.
