{
  PaPiMeLa.TextInput.WaylandTI — Wayland text-input-v3 のバックエンド

  Origin : original work (clean-room design; not derived from SDL sources)
           SDL_waylandevents.c の text_input_* は参照していない。手順はプロトコルの
           XML（text-input-unstable-v3.xml）の記述に従った。
  Design : docs/DESIGN.md §7.7、§11 #49

  WHAT:
    コンポジタの zwp_text_input_v3 で IME と話す。変換中テキスト・確定・周辺削除を
    done でまとめて適用し、周辺テキスト・カーソル矩形・入力の種類を送る。

  WHY:
    IBus / Fcitx に直接繋げない環境（別の IME フレームワーク、sandbox で D-Bus が
    無い、コンポジタ内蔵の IME）でも日本語を入れられるようにする。文節の情報は
    プロトコルに無い（v3 で preedit_styling が消えた）ので SegmentsReliable は False。

  RESOLVED:
    - preedit / commit / delete は done までは保留し、done で 周辺削除 → 確定 →
      変換中テキスト の順に通知する。done で届かなかった値は初期値（空、0）に戻す
      （プロトコルの「double-buffered ... reset to initial on the next done」）
    - done の serial が送った commit の回数と違っても適用する（プロトコルの規定。
      状態の更新だけ控えよとあるが、papimela は IME へ送る状態を done で変えない）
    - enable は enter を受けたサーフェスがセッションのウィンドウのときだけ送る。
      enable は状態を初期化するので、入力の種類・周辺テキスト・カーソル矩形を
      同じ commit で送り直す
    - 要求は Pump でまとめて 1 回の commit にする。Activate の直後に System が
      周辺テキストを送ってくるので、その場で commit すると 2 回になる
    - 周辺テキストは 4000 バイト以内（プロトコルの上限）。カーソルを中心に文字境界で切る
    - 周辺削除のバイト数は、最後に送った周辺テキストの上で文字数へ直す。IME が
      知っているのは送ったテキストだけなので、その外へはみ出す分は切り捨てる

  NOT RESOLVED:
    - 削除の長さは「選択を除いたカーソルの前後」だが、選択があるときの扱いは
      カーソル基準のまま（Fcitx バックエンドと同じ）
    - v3 には変換のリセット要求が無い。ResetComposition は手元の変換中テキストを
      消し、周辺テキストを cause = other で送り直すだけ（IME 側が破棄するかは IME 次第）

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.TextInput.WaylandTI;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Unicode,
  PaPiMeLa.Events,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland.Types,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland,
  PaPiMeLa.Platform.Wayland.Protocols.TextInputUnstableV3,
  PaPiMeLa.TextInput,
  PaPiMeLa.TextInput.Backend;

const
  // set_surrounding_text の上限（プロトコルの記述）。
  PML_TEXT_INPUT_V3_MAX_SURROUNDING = 4000;

type
  { text-input-v3 の受信側の状態。Wayland に触れないので表示サーバ無しで検査できる。

    イベントは done まで保留し、done で Sink へまとめて流す。周辺テキストは
    送る前にここを通し、周辺削除の換算に使うため送った形を覚えておく。 }
  TPMLTextInputV3State = class
  strict private
    FPendingPreedit  : String;
    FPendingBegin    : Integer;
    FPendingEnd      : Integer;
    FPendingCommit   : String;
    FPendingBefore   : LongWord;
    FPendingAfter    : LongWord;
    FComposition     : TPMLComposition;
    FSentText        : String;     // 最後に送った（切り詰めた後の）周辺テキスト
    FSentCursor      : Integer;    // その中のカーソルのバイト位置
    FHasSent         : Boolean;
    FEditedByIME     : Boolean;
    procedure ResetPending;
    function  ConvertDelete(ABefore, AAfter: LongWord): TPMLDeleteSurroundingData;
  public
    constructor Create;

    procedure Preedit(const AText: String; ACursorBegin, ACursorEnd: Integer);
    procedure CommitString(const AText: String);
    procedure DeleteSurrounding(ABeforeBytes, AAfterBytes: LongWord);
    // 保留していた分を 周辺削除 → 確定 → 変換中テキスト の順に ASink へ流す。
    procedure Done(ASink: IPMLTextInputSink);
    // フォーカスが外れた。保留を捨て、変換中テキストがあれば空にして通知する。
    procedure Leave(ASink: IPMLTextInputSink);
    // 変換中テキストを手元で捨てる（ResetComposition）。あれば空にして通知する。
    procedure ClearComposition(ASink: IPMLTextInputSink);

    // 送る周辺テキストを作って覚える。4000 バイトを超えればカーソルを中心に切る。
    procedure PrepareSurrounding(const AText: String; ACursorByte, AAnchorByte: Integer;
      out AOutText: String; out AOutCursor, AOutAnchor: Integer);
    // 周辺テキストの変更理由。直前の done が確定か削除を適用していれば True。
    // 読むと False に戻る（次に送る周辺テキスト 1 回分にだけ効く）。
    function  TakeEditedByIME: Boolean;

    // preedit_string の引数から変換中テキストを組む。
    class function BuildComposition(const AText: String;
      ACursorBegin, ACursorEnd: Integer): TPMLComposition; static;
    // AText を AMaxBytes 以内に切る。カーソルを含む範囲を文字境界で選ぶ。
    class procedure TruncateSurrounding(const AText: String; ACursorByte, AAnchorByte,
      AMaxBytes: Integer; out AOutText: String; out AOutCursor, AOutAnchor: Integer); static;
    // 入力の種類とヒントを content_type の hint / purpose へ写す。
    class procedure ContentType(AType: TPMLTextInputType; AHints: TPMLTextInputHints;
      out AHint, APurpose: LongWord); static;

    property Composition: TPMLComposition read FComposition;
  end;

  TPMLWaylandTextInputBackend = class;

  { zwp_text_input_v3 のイベントをバックエンドへ回す。 }
  TPMLTextInputV3Forwarder = class(Tzwp_text_input_v3_listener)
  strict private
    FOwner: TPMLWaylandTextInputBackend;
  public
    constructor Create(AOwner: TPMLWaylandTextInputBackend);
    procedure enter(AProxy: Pzwp_text_input_v3; surface: Pwl_surface); override;
    procedure leave(AProxy: Pzwp_text_input_v3; surface: Pwl_surface); override;
    procedure preedit_string(AProxy: Pzwp_text_input_v3; text: PAnsiChar;
      cursor_begin: LongInt; cursor_end: LongInt); override;
    procedure commit_string(AProxy: Pzwp_text_input_v3; text: PAnsiChar); override;
    procedure delete_surrounding_text(AProxy: Pzwp_text_input_v3;
      before_length: LongWord; after_length: LongWord); override;
    procedure done(AProxy: Pzwp_text_input_v3; serial: LongWord); override;
  end;

  TPMLWaylandTextInputBackend = class(TPMLTextInputBackend)
  strict private
    FProvider     : IPMLWaylandSeatProvider;
    FDisplay      : Pwl_display;
    FTextInput    : Pzwp_text_input_v3;
    FForwarder    : TPMLTextInputV3Forwarder;
    FState        : TPMLTextInputV3State;
    FEntered      : Pwl_surface;   // enter で受けたサーフェス（leave で nil）
    FTarget       : Pwl_surface;   // セッションのウィンドウのサーフェス
    FWanted       : Boolean;       // Activate されている
    FEnabled      : Boolean;       // enable を送ってある
    FHint, FPurpose: LongWord;
    // 送る予定の状態。Pump で 1 回の commit にまとめる。
    FHaveSurrounding: Boolean;
    FSurrounding    : String;
    FSurCursor, FSurAnchor: Integer;
    FCause          : LongWord;
    FHaveRect       : Boolean;
    FRect           : TPMLRect;
    FDirty          : Boolean;     // 次の Pump で送るものがある
    FNeedEnable     : Boolean;
    FNeedDisable    : Boolean;
    procedure UpdateEnabled;
    procedure Flush;
  public
    destructor Destroy; override;
    function  BackendName: String; override;
    function  Capabilities: TPMLTextInputCapabilities; override;
    function  Connect(ASink: IPMLTextInputSink): Boolean; override;
    procedure Disconnect; override;
    procedure Activate(AWindow: TPMLWindow; AType: TPMLTextInputType;
      AHints: TPMLTextInputHints); override;
    procedure Deactivate; override;
    procedure ResetComposition; override;
    procedure UpdateSurroundingText(const AText: String; ACursorByte, AAnchorByte: Integer); override;
    procedure UpdateCursorRect(const ARect: TPMLRect; AScale: Double); override;
    procedure Pump(ATimeoutMs: Integer); override;

    // TPMLTextInputV3Forwarder から呼ばれる。
    procedure HandleEnter(ASurface: Pwl_surface);
    procedure HandleLeave(ASurface: Pwl_surface);
    procedure HandlePreedit(AText: PAnsiChar; ABegin, AEnd: LongInt);
    procedure HandleCommit(AText: PAnsiChar);
    procedure HandleDelete(ABefore, AAfter: LongWord);
    procedure HandleDone;

    // テストと診断用。enter を受けているか、enable を送ってあるか。
    function  Entered: Boolean;
    property  Enabled: Boolean read FEnabled;
  end;

implementation

{ 文字境界へ切り上げる。 }
function CeilToCharBoundary(const AText: String; AByte: Integer): Integer;
begin
  Result := AByte;
  if Result < 0 then
    Result := 0;
  while (Result < Length(AText)) and not IsUTF8Lead(Byte(AText[Result + 1])) do
    Inc(Result);
  if Result > Length(AText) then
    Result := Length(AText);
end;

{ 文節の区切りと状態、カーソルが同じか。 }
function SameComposition(const A, B: TPMLComposition): Boolean;
var
  I: Integer;
begin
  Result := (A.Text = B.Text) and (A.CursorByte = B.CursorByte)
    and (Length(A.Segments) = Length(B.Segments));
  if not Result then
    Exit;
  for I := 0 to High(A.Segments) do
    if (A.Segments[I].StartByte <> B.Segments[I].StartByte)
      or (A.Segments[I].EndByte <> B.Segments[I].EndByte)
      or (A.Segments[I].State <> B.Segments[I].State) then
      Exit(False);
end;

{ TPMLTextInputV3State }

constructor TPMLTextInputV3State.Create;
begin
  inherited Create;
  FComposition.Clear;
  ResetPending;
end;

procedure TPMLTextInputV3State.ResetPending;
begin
  // プロトコルの初期値: 空文字列、カーソル 0、削除 0。
  FPendingPreedit := '';
  FPendingBegin := 0;
  FPendingEnd := 0;
  FPendingCommit := '';
  FPendingBefore := 0;
  FPendingAfter := 0;
end;

procedure TPMLTextInputV3State.Preedit(const AText: String; ACursorBegin, ACursorEnd: Integer);
begin
  FPendingPreedit := AText;
  FPendingBegin := ACursorBegin;
  FPendingEnd := ACursorEnd;
end;

procedure TPMLTextInputV3State.CommitString(const AText: String);
begin
  FPendingCommit := AText;
end;

procedure TPMLTextInputV3State.DeleteSurrounding(ABeforeBytes, AAfterBytes: LongWord);
begin
  FPendingBefore := ABeforeBytes;
  FPendingAfter := AAfterBytes;
end;

{ 最後に送った周辺テキストの上で、カーソル前後のバイト数を文字数へ直す。
  送ったテキストの外へはみ出す分は IME が知り得ないので切り捨てる。
  周辺テキストを送っていなければ何も消せない（両方 0）。 }
function TPMLTextInputV3State.ConvertDelete(ABefore, AAfter: LongWord): TPMLDeleteSurroundingData;
var
  StartByte, EndByte: Int64;
begin
  FillChar(Result, SizeOf(Result), 0);
  if not FHasSent then
    Exit;
  StartByte := Int64(FSentCursor) - Int64(ABefore);
  if StartByte < 0 then
    StartByte := 0;
  EndByte := Int64(FSentCursor) + Int64(AAfter);
  if EndByte > Length(FSentText) then
    EndByte := Length(FSentText);
  // 文字の途中を指していれば、その文字は消さない（どちらも縮む向きに寄せる）。
  StartByte := CeilToCharBoundary(FSentText, Integer(StartByte));
  EndByte := UTF8FloorToCharBoundary(FSentText, Integer(EndByte));

  Result.BeforeBytes := FSentCursor - Integer(StartByte);
  Result.AfterBytes := Integer(EndByte) - FSentCursor;
  Result.BeforeChars := UTF8ByteToCharOffset(FSentText, FSentCursor)
                      - UTF8ByteToCharOffset(FSentText, Integer(StartByte));
  Result.AfterChars := UTF8ByteToCharOffset(FSentText, Integer(EndByte))
                     - UTF8ByteToCharOffset(FSentText, FSentCursor);
end;

procedure TPMLTextInputV3State.Done(ASink: IPMLTextInputSink);
var
  NewComp: TPMLComposition;
begin
  // 1. 周辺削除
  if (FPendingBefore > 0) or (FPendingAfter > 0) then
  begin
    FEditedByIME := True;
    if Assigned(ASink) then
      ASink.DeleteSurroundingRequested(ConvertDelete(FPendingBefore, FPendingAfter));
  end;
  // 2. 確定
  if FPendingCommit <> '' then
  begin
    FEditedByIME := True;
    if Assigned(ASink) then
      ASink.TextCommitted(FPendingCommit);
  end;
  // 3. 変換中テキスト。done に preedit が無ければ空（初期値）になる。
  NewComp := BuildComposition(FPendingPreedit, FPendingBegin, FPendingEnd);
  if not SameComposition(NewComp, FComposition) then
  begin
    FComposition := NewComp;
    if Assigned(ASink) then
      ASink.CompositionChanged(FComposition);
  end;
  ResetPending;
end;

procedure TPMLTextInputV3State.Leave(ASink: IPMLTextInputSink);
begin
  ResetPending;
  ClearComposition(ASink);
end;

procedure TPMLTextInputV3State.ClearComposition(ASink: IPMLTextInputSink);
begin
  if FComposition.IsEmpty then
    Exit;
  FComposition.Clear;
  if Assigned(ASink) then
    ASink.CompositionChanged(FComposition);
end;

procedure TPMLTextInputV3State.PrepareSurrounding(const AText: String;
  ACursorByte, AAnchorByte: Integer; out AOutText: String;
  out AOutCursor, AOutAnchor: Integer);
begin
  TruncateSurrounding(AText, ACursorByte, AAnchorByte, PML_TEXT_INPUT_V3_MAX_SURROUNDING,
    AOutText, AOutCursor, AOutAnchor);
  FSentText := AOutText;
  FSentCursor := AOutCursor;
  FHasSent := True;
end;

function TPMLTextInputV3State.TakeEditedByIME: Boolean;
begin
  Result := FEditedByIME;
  FEditedByIME := False;
end;

class function TPMLTextInputV3State.BuildComposition(const AText: String;
  ACursorBegin, ACursorEnd: Integer): TPMLComposition;
var
  B, E, N: Integer;

  procedure Add(AStart, AEnd: Integer; AState: TPMLSegmentState);
  begin
    if AEnd <= AStart then
      Exit;
    SetLength(Result.Segments, N + 1);
    Result.Segments[N].StartByte := AStart;
    Result.Segments[N].EndByte := AEnd;
    Result.Segments[N].State := AState;
    Result.Segments[N].Underline := TPMLUnderlineStyle.None;
    Inc(N);
  end;

begin
  Result.Clear;
  if AText = '' then
    Exit;
  Result.Text := AText;
  N := 0;
  if (ACursorBegin < 0) or (ACursorEnd < 0) then
  begin
    // 両方 -1 はカーソル非表示。片方だけ負の値は壊れた引数なので同じ扱いにする。
    Add(0, Length(AText), TPMLSegmentState.Unconverted);
  end
  else
  begin
    B := UTF8FloorToCharBoundary(AText, ACursorBegin);
    E := UTF8FloorToCharBoundary(AText, ACursorEnd);
    if E < B then
    begin
      N := B; B := E; E := N;
      N := 0;
    end;
    if B = E then
    begin
      // 同じ位置なら線で描くカーソル。強調する範囲は無い。
      Add(0, Length(AText), TPMLSegmentState.Unconverted);
      Result.CursorByte := B;
    end
    else
    begin
      // 違えば範囲の強調（線のカーソルは描かない）。注目文節として扱う。
      Add(0, B, TPMLSegmentState.Unconverted);
      Add(B, E, TPMLSegmentState.Focused);
      Add(E, Length(AText), TPMLSegmentState.Unconverted);
    end;
  end;
  Result.SegmentsReliable := False;
  Result.Finalize;
end;

class procedure TPMLTextInputV3State.TruncateSurrounding(const AText: String;
  ACursorByte, AAnchorByte, AMaxBytes: Integer; out AOutText: String;
  out AOutCursor, AOutAnchor: Integer);
var
  Cursor, Anchor, Lo, Hi, Start, Stop: Integer;
begin
  Cursor := UTF8FloorToCharBoundary(AText, ACursorByte);
  Anchor := UTF8FloorToCharBoundary(AText, AAnchorByte);
  if Length(AText) <= AMaxBytes then
  begin
    AOutText := AText;
    AOutCursor := Cursor;
    AOutAnchor := Anchor;
    Exit;
  end;

  // 選択ごと入るなら選択の中央を、入らなければカーソルを中央に置く。
  if Cursor < Anchor then
  begin
    Lo := Cursor; Hi := Anchor;
  end
  else
  begin
    Lo := Anchor; Hi := Cursor;
  end;
  if Hi - Lo > AMaxBytes then
  begin
    Lo := Cursor; Hi := Cursor;
  end;
  Start := (Lo + Hi) div 2 - AMaxBytes div 2;
  if Start > Length(AText) - AMaxBytes then
    Start := Length(AText) - AMaxBytes;
  if Start < 0 then
    Start := 0;
  Stop := Start + AMaxBytes;
  // 文字の途中で切らない。始まりは後ろへ、終わりは前へ寄せる（どちらも縮む向き）。
  Start := CeilToCharBoundary(AText, Start);
  Stop := UTF8FloorToCharBoundary(AText, Stop);

  AOutText := Copy(AText, Start + 1, Stop - Start);
  if Cursor < Start then
    Cursor := Start;
  if Cursor > Stop then
    Cursor := Stop;
  if Anchor < Start then
    Anchor := Start;
  if Anchor > Stop then
    Anchor := Stop;
  AOutCursor := Cursor - Start;
  AOutAnchor := Anchor - Start;
end;

class procedure TPMLTextInputV3State.ContentType(AType: TPMLTextInputType;
  AHints: TPMLTextInputHints; out AHint, APurpose: LongWord);
begin
  AHint := ZWP_TEXT_INPUT_V3_CONTENT_HINT_NONE;
  case AType of
    TPMLTextInputType.Name:     APurpose := ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_NAME;
    TPMLTextInputType.Email:    APurpose := ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_EMAIL;
    TPMLTextInputType.Username:
      begin
        APurpose := ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_NORMAL;
        AHint := AHint or ZWP_TEXT_INPUT_V3_CONTENT_HINT_LATIN;
      end;
    TPMLTextInputType.Password:
      begin
        APurpose := ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_PASSWORD;
        AHint := AHint or ZWP_TEXT_INPUT_V3_CONTENT_HINT_HIDDEN_TEXT
                       or ZWP_TEXT_INPUT_V3_CONTENT_HINT_SENSITIVE_DATA;
      end;
    TPMLTextInputType.Number:   APurpose := ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_NUMBER;
    TPMLTextInputType.Phone:    APurpose := ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_PHONE;
    TPMLTextInputType.Url:      APurpose := ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_URL;
    TPMLTextInputType.Date:     APurpose := ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_DATE;
    TPMLTextInputType.Time:     APurpose := ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_TIME;
  else
    APurpose := ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_NORMAL;
  end;
  if TPMLTextInputHint.Multiline in AHints then
    AHint := AHint or ZWP_TEXT_INPUT_V3_CONTENT_HINT_MULTILINE;
  if TPMLTextInputHint.AutoCorrect in AHints then
    AHint := AHint or ZWP_TEXT_INPUT_V3_CONTENT_HINT_SPELLCHECK
                   or ZWP_TEXT_INPUT_V3_CONTENT_HINT_COMPLETION;
  if TPMLTextInputHint.AutoCapitalize in AHints then
    AHint := AHint or ZWP_TEXT_INPUT_V3_CONTENT_HINT_AUTO_CAPITALIZATION;
  if TPMLTextInputHint.Sensitive in AHints then
    AHint := AHint or ZWP_TEXT_INPUT_V3_CONTENT_HINT_SENSITIVE_DATA;
end;

{ TPMLTextInputV3Forwarder }

constructor TPMLTextInputV3Forwarder.Create(AOwner: TPMLWaylandTextInputBackend);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TPMLTextInputV3Forwarder.enter(AProxy: Pzwp_text_input_v3; surface: Pwl_surface);
begin
  FOwner.HandleEnter(surface);
end;

procedure TPMLTextInputV3Forwarder.leave(AProxy: Pzwp_text_input_v3; surface: Pwl_surface);
begin
  FOwner.HandleLeave(surface);
end;

procedure TPMLTextInputV3Forwarder.preedit_string(AProxy: Pzwp_text_input_v3;
  text: PAnsiChar; cursor_begin: LongInt; cursor_end: LongInt);
begin
  FOwner.HandlePreedit(text, cursor_begin, cursor_end);
end;

procedure TPMLTextInputV3Forwarder.commit_string(AProxy: Pzwp_text_input_v3; text: PAnsiChar);
begin
  FOwner.HandleCommit(text);
end;

procedure TPMLTextInputV3Forwarder.delete_surrounding_text(AProxy: Pzwp_text_input_v3;
  before_length: LongWord; after_length: LongWord);
begin
  FOwner.HandleDelete(before_length, after_length);
end;

procedure TPMLTextInputV3Forwarder.done(AProxy: Pzwp_text_input_v3; serial: LongWord);
begin
  FOwner.HandleDone;
end;

{ TPMLWaylandTextInputBackend }

destructor TPMLWaylandTextInputBackend.Destroy;
begin
  Disconnect;
  inherited Destroy;
end;

function TPMLWaylandTextInputBackend.BackendName: String;
begin
  Result := 'wayland';
end;

function TPMLWaylandTextInputBackend.Capabilities: TPMLTextInputCapabilities;
begin
  Result := [
    TPMLTextInputCapability.SurroundingText,
    TPMLTextInputCapability.DeleteSurrounding,
    TPMLTextInputCapability.CursorRect
  ];
end;

{ Wayland のビデオで動いていて、コンポジタが text-input-v3 を広告し、シートが
  あるときだけ繋がる。どれかが無ければ False（次の候補へ）。 }
function TPMLWaylandTextInputBackend.Connect(ASink: IPMLTextInputSink): Boolean;
var
  Conn: TPMLWaylandConnection;
begin
  Result := False;
  if not Assigned(FVideo) or not Assigned(FVideo.Backend) then
    Exit;
  if not Supports(FVideo.Backend, IPMLWaylandSeatProvider, FProvider) then
    Exit;
  Conn := FProvider.WaylandConnection;
  if not Assigned(Conn) or (Conn.Display = nil) or (Conn.TextInputMgr = nil)
    or (Length(Conn.Seats) = 0) then
  begin
    FProvider := nil;
    Exit;
  end;

  // 最初のシートだけを使う（papimela はシートを 1 つとして扱う。§6）。
  FTextInput := zwp_text_input_manager_v3_get_text_input(Conn.TextInputMgr, Conn.Seats[0]);
  if FTextInput = nil then
  begin
    FProvider := nil;
    Exit;
  end;
  FDisplay := Conn.Display;
  FState := TPMLTextInputV3State.Create;
  FForwarder := TPMLTextInputV3Forwarder.Create(Self);
  zwp_text_input_v3_add_listener_object(FTextInput, FForwarder);
  FSink := ASink;
  TPMLTextInputV3State.ContentType(TPMLTextInputType.Text, [], FHint, FPurpose);
  Result := True;
end;

procedure TPMLWaylandTextInputBackend.Disconnect;
begin
  if FTextInput <> nil then
  begin
    zwp_text_input_v3_destroy(FTextInput);
    FTextInput := nil;
    if FDisplay <> nil then
      wl_display_flush(FDisplay);
  end;
  FreeAndNil(FForwarder);
  FreeAndNil(FState);
  FProvider := nil;
  FDisplay := nil;
  FSink := nil;
  FEntered := nil;
  FTarget := nil;
  FWanted := False;
  FEnabled := False;
end;

procedure TPMLWaylandTextInputBackend.Activate(AWindow: TPMLWindow;
  AType: TPMLTextInputType; AHints: TPMLTextInputHints);
begin
  if FTextInput = nil then
    Exit;
  FTarget := nil;
  if Assigned(AWindow) and Assigned(FProvider) then
    FTarget := FProvider.WaylandSurfaceOf(AWindow.Backend);
  TPMLTextInputV3State.ContentType(AType, AHints, FHint, FPurpose);
  FWanted := True;
  // 同じサーフェスでも、入力欄が変わるたびに enable を送り直す（プロトコルの規定）。
  FEnabled := False;
  UpdateEnabled;
end;

procedure TPMLWaylandTextInputBackend.Deactivate;
begin
  if FTextInput = nil then
    Exit;
  FWanted := False;
  UpdateEnabled;
  FState.ClearComposition(FSink);
end;

{ 望む状態（Activate されていて、対象のサーフェスに enter している）と
  送ってある状態を突き合わせ、次の Pump で送るものを決める。 }
procedure TPMLWaylandTextInputBackend.UpdateEnabled;
var
  Want: Boolean;
begin
  Want := FWanted and (FEntered <> nil) and (FEntered = FTarget);
  if Want and not FEnabled then
  begin
    FNeedEnable := True;
    FNeedDisable := False;
    FDirty := True;
  end
  else if not Want and FEnabled then
  begin
    FNeedDisable := True;
    FNeedEnable := False;
    FDirty := True;
  end
  else if not Want then
    FNeedEnable := False;
end;

procedure TPMLWaylandTextInputBackend.ResetComposition;
begin
  if FTextInput = nil then
    Exit;
  FState.ClearComposition(FSink);
  // IME に知らせる手段は周辺テキストの送り直しだけ。理由は other。
  if FHaveSurrounding then
  begin
    FCause := ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER;
    FDirty := True;
  end;
end;

procedure TPMLWaylandTextInputBackend.UpdateSurroundingText(const AText: String;
  ACursorByte, AAnchorByte: Integer);
begin
  if FTextInput = nil then
    Exit;
  FSurrounding := AText;
  FSurCursor := ACursorByte;
  FSurAnchor := AAnchorByte;
  FHaveSurrounding := True;
  if FState.TakeEditedByIME then
    FCause := ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_INPUT_METHOD
  else
    FCause := ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER;
  FDirty := True;
end;

{ 矩形はサーフェスの座標（論理ピクセル）。papimela のウィンドウ座標と同じ。 }
procedure TPMLWaylandTextInputBackend.UpdateCursorRect(const ARect: TPMLRect; AScale: Double);
begin
  if FTextInput = nil then
    Exit;
  FRect := ARect;
  FHaveRect := True;
  FDirty := True;
end;

{ 溜めた要求を 1 回の commit にまとめて送る。enable は状態を初期化するので、
  enable を送るときは持っている状態を全部送り直す。 }
procedure TPMLWaylandTextInputBackend.Flush;
var
  S: String;
  C, A: Integer;
begin
  if not FDirty or (FTextInput = nil) then
    Exit;
  FDirty := False;
  if FNeedDisable then
  begin
    FNeedDisable := False;
    FEnabled := False;
    zwp_text_input_v3_disable(FTextInput);
    zwp_text_input_v3_commit(FTextInput);
    wl_display_flush(FDisplay);
    Exit;
  end;
  if FNeedEnable then
  begin
    FNeedEnable := False;
    FEnabled := True;
    zwp_text_input_v3_enable(FTextInput);
    zwp_text_input_v3_set_content_type(FTextInput, FHint, FPurpose);
  end
  else if not FEnabled then
    Exit;   // 有効でない間の状態は覚えておき、enable のときにまとめて送る
  if FHaveSurrounding then
  begin
    FState.PrepareSurrounding(FSurrounding, FSurCursor, FSurAnchor, S, C, A);
    zwp_text_input_v3_set_surrounding_text(FTextInput, PAnsiChar(S), C, A);
    zwp_text_input_v3_set_text_change_cause(FTextInput, FCause);
    FCause := ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER;
  end;
  if FHaveRect then
    zwp_text_input_v3_set_cursor_rectangle(FTextInput, FRect.X, FRect.Y, FRect.W, FRect.H);
  zwp_text_input_v3_commit(FTextInput);
  wl_display_flush(FDisplay);
end;

{ イベントの受信はビデオのバックエンドが同じ wl_display で行う。ここは送るだけ。 }
procedure TPMLWaylandTextInputBackend.Pump(ATimeoutMs: Integer);
begin
  Flush;
end;

procedure TPMLWaylandTextInputBackend.HandleEnter(ASurface: Pwl_surface);
begin
  FEntered := ASurface;
  // enter の前の enable は無視されるので、ここで送り直す。
  FEnabled := False;
  UpdateEnabled;
end;

procedure TPMLWaylandTextInputBackend.HandleLeave(ASurface: Pwl_surface);
begin
  FEntered := nil;
  // leave の後はコンポジタが要求を無視する。disable は送らず、送ってある印だけ消す。
  FEnabled := False;
  FNeedEnable := False;
  FNeedDisable := False;
  FState.Leave(FSink);
end;

procedure TPMLWaylandTextInputBackend.HandlePreedit(AText: PAnsiChar; ABegin, AEnd: LongInt);
begin
  FState.Preedit(String(AText), ABegin, AEnd);
end;

procedure TPMLWaylandTextInputBackend.HandleCommit(AText: PAnsiChar);
begin
  FState.CommitString(String(AText));
end;

procedure TPMLWaylandTextInputBackend.HandleDelete(ABefore, AAfter: LongWord);
begin
  FState.DeleteSurrounding(ABefore, AAfter);
end;

procedure TPMLWaylandTextInputBackend.HandleDone;
begin
  FState.Done(FSink);
end;

function TPMLWaylandTextInputBackend.Entered: Boolean;
begin
  Result := FEntered <> nil;
end;

{ ---- 登録 ---- }

function CreateWaylandTextInputBackend: TPMLTextInputBackend;
begin
  Result := TPMLWaylandTextInputBackend.Create;
end;

initialization
  // IBus（200）・Fcitx（100）に繋がらないときの受け皿。文節が取れないので後回し。
  PMLRegisterTextInputBackend('wayland', 50, @CreateWaylandTextInputBackend);

end.
