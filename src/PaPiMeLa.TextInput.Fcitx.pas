{
  PaPiMeLa.TextInput.Fcitx — Fcitx5 の D-Bus フロントエンド

  Origin : original work (clean-room design; not derived from SDL sources)
           SDL_fcitx.c は参照していない。D-Bus のインターフェースは実機の
           introspect で確認し、手順は spikes/spike2_fcitx.pas で実測した。
  Design : docs/DESIGN.md §7.8、§11 #50

  WHAT:
    org.fcitx.Fcitx5 に入力コンテキストを作り、キーを ProcessKeyEvent で渡し、
    UpdateFormattedPreedit の各要素を文節として公開する。周辺テキストの供給と
    周辺削除要求にも対応する。

  WHY:
    Wayland text-input-v3 は preedit の文節情報を持たない（プロトコル v3 で
    preedit_styling が削除された）。文節境界を得るには IME に直接繋ぐ必要がある。

  RESOLVED:
    - 手順の順序: CreateInputContext → SetCapability → FocusIn → Controller.Activate
      Activate を忘れると fcitx5 は非アクティブ状態のままで ProcessKeyEvent が
      常に false を返す（実測）
    - capability は Preedit|FormattedPreedit|SurroundingText = 82。
      FormattedPreedit が無いと文節に分かれた形で届かない（実測）
    - UpdateFormattedPreedit の cursor は UTF-8 バイトオフセット。
      一方 SetSurroundingText の cursor / anchor はコードポイント単位。
      この非対称は fcitx5 側の仕様なので papimela が吸収する

  NOT RESOLVED:
    - フラグ → 文節状態の対応は fcitx5-mozc で実測した規則。fcitx5-anthy /
      fcitx5-chinese-addons では未確認（Design: docs/DESIGN.md §10 項目 1）
    - ProcessKeyEvent は同期呼び出し。非同期化は §10 項目 3
    - 埋め込み候補（UpdateClientSideUI）は未実装

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.TextInput.Fcitx;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Unicode,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Events,
  PaPiMeLa.Platform.DBus,
  PaPiMeLa.TextInput,
  PaPiMeLa.TextInput.Backend;

type
  TPMLFcitxTextInputBackend = class(TPMLTextInputBackend)
  strict private
    FConn        : TPMLDBusConnection;
    FICPath      : String;
    FActive      : Boolean;
    FCursorRectV2: Boolean;
    // 最後に IME へ送った周辺テキスト。DeleteSurroundingText の文字数を
    // バイト数へ変換するために保持する。
    FSurrounding     : String;
    FSurroundingCursor: Integer;   // コードポイント位置
    procedure Subscribe;
    procedure SetCapability(AValue: QWord);
    procedure DispatchSignal(AMsg: PDBusMessage);
    procedure HandleFormattedPreedit(AMsg: PDBusMessage);
    procedure HandleCommitString(AMsg: PDBusMessage);
    procedure HandleDeleteSurrounding(AMsg: PDBusMessage);
    function  ModifiersToState(const AMods: TPMLKeyModifiers): LongWord;
  public
    constructor Create;
    destructor Destroy; override;

    function  BackendName: String; override;
    function  Capabilities: TPMLTextInputCapabilities; override;
    function  Connect(ASink: IPMLTextInputSink): Boolean; override;
    procedure Disconnect; override;
    procedure Activate(AType: TPMLTextInputType; AHints: TPMLTextInputHints); override;
    procedure Deactivate; override;
    procedure ResetComposition; override;
    procedure UpdateSurroundingText(const AText: String; ACursorByte, AAnchorByte: Integer); override;
    procedure UpdateCursorRect(const ARect: TPMLRect; AScale: Double); override;
    function  FilterKey(const AKey: TPMLKeyEventData; AIsRelease: Boolean): TPMLKeyFilterResult; override;
    procedure Pump(ATimeoutMs: Integer); override;
  end;

implementation

const
  FCITX_SERVICE = 'org.fcitx.Fcitx5';
  IM_PATH       = '/org/freedesktop/portal/inputmethod';
  IM_IFACE      = 'org.fcitx.Fcitx.InputMethod1';
  IC_IFACE      = 'org.fcitx.Fcitx.InputContext1';
  CTRL_PATH     = '/controller';
  CTRL_IFACE    = 'org.fcitx.Fcitx.Controller1';

  // CapabilityFlag (fcitx5: src/lib/fcitx-utils/capabilityflags.h)
  CAP_PREEDIT           = QWord(1) shl 1;
  CAP_FORMATTED_PREEDIT = QWord(1) shl 4;
  CAP_SURROUNDING_TEXT  = QWord(1) shl 6;

  // TextFormatFlag (fcitx5: src/lib/fcitx-utils/textformatflags.h)
  FMT_UNDERLINE = 1 shl 3;
  FMT_HIGHLIGHT = 1 shl 4;

  // X11 モディファイアマスク
  X_SHIFT = 1 shl 0;
  X_LOCK  = 1 shl 1;
  X_CTRL  = 1 shl 2;
  X_ALT   = 1 shl 3;
  X_NUM   = 1 shl 4;
  X_SUPER = 1 shl 6;

constructor TPMLFcitxTextInputBackend.Create;
begin
  inherited Create;
  FSurroundingCursor := 0;
  FCursorRectV2 := True;
end;

destructor TPMLFcitxTextInputBackend.Destroy;
begin
  Disconnect;
  inherited Destroy;
end;

function TPMLFcitxTextInputBackend.BackendName: String;
begin
  Result := 'fcitx';
end;

function TPMLFcitxTextInputBackend.Capabilities: TPMLTextInputCapabilities;
begin
  Result := [
    TPMLTextInputCapability.Segments,
    TPMLTextInputCapability.SurroundingText,
    TPMLTextInputCapability.DeleteSurrounding,
    TPMLTextInputCapability.CursorRect,
    TPMLTextInputCapability.KeyFilter
  ];
end;

function TPMLFcitxTextInputBackend.Connect(ASink: IPMLTextInputSink): Boolean;
var
  Msg, Reply: PDBusMessage;
  W, Arr, St: TPMLDBusWriter;
  R: TPMLDBusReader;
begin
  Result := False;
  try
    FConn := TPMLDBusConnection.Create(DBUS_BUS_SESSION);
  except
    on E: EPMLError do
    begin
      FreeAndNil(FConn);
      Exit;   // libdbus が無い、またはセッションバスが無い
    end;
  end;

  if not FConn.NameHasOwner(FCITX_SERVICE) then
  begin
    FreeAndNil(FConn);
    Exit;     // fcitx5 が起動していない
  end;

  // CreateInputContext(a(ss)) -> (o path, ay uuid)
  Msg := FConn.BeginCall(FCITX_SERVICE, IM_PATH, IM_IFACE, 'CreateInputContext');
  Reply := nil;
  try
    W := FConn.Writer(Msg);
    Arr := W.OpenArray('(ss)');
    St := Arr.OpenStruct;
    St.AddString('program');
    St.AddString(ApplicationName);
    Arr.Close(St);
    St := Arr.OpenStruct;
    St.AddString('display');
    St.AddString('wayland:');
    Arr.Close(St);
    W.Close(Arr);

    Reply := FConn.Send(Msg);
    R := FConn.Reader(Reply);
    FICPath := R.ExpectObjectPath;
  finally
    FConn.Unref(Reply);
    FConn.Unref(Msg);
  end;

  if FICPath = '' then
  begin
    FreeAndNil(FConn);
    Exit;
  end;

  FSink := ASink;
  Subscribe;
  SetCapability(CAP_PREEDIT or CAP_FORMATTED_PREEDIT or CAP_SURROUNDING_TEXT);
  Result := True;
end;

procedure TPMLFcitxTextInputBackend.Subscribe;
begin
  FConn.AddMatch(Format('type=''signal'',interface=''%s'',path=''%s''',
    [IC_IFACE, FICPath]));
end;

procedure TPMLFcitxTextInputBackend.SetCapability(AValue: QWord);
var
  Msg, Reply: PDBusMessage;
  W: TPMLDBusWriter;
begin
  Msg := FConn.BeginCall(FCITX_SERVICE, FICPath, IC_IFACE, 'SetCapability');
  Reply := nil;
  try
    W := FConn.Writer(Msg);
    W.AddUInt64(AValue);
    Reply := FConn.Send(Msg);
  finally
    FConn.Unref(Reply);
    FConn.Unref(Msg);
  end;
end;

procedure TPMLFcitxTextInputBackend.Disconnect;
begin
  if Assigned(FConn) and (FICPath <> '') then
  begin
    try
      if FActive then
        FConn.CallVoid(FCITX_SERVICE, FICPath, IC_IFACE, 'FocusOut');
      FConn.CallVoid(FCITX_SERVICE, FICPath, IC_IFACE, 'DestroyIC');
    except
      // 切断時のエラーは無視する。既に fcitx5 が終了している場合がある。
      on E: EPMLError do ;
    end;
  end;
  FActive := False;
  FICPath := '';
  FreeAndNil(FConn);
  inherited Disconnect;
end;

procedure TPMLFcitxTextInputBackend.Activate(AType: TPMLTextInputType;
  AHints: TPMLTextInputHints);
begin
  if not Assigned(FConn) then
    Exit;
  // 順序が重要（実測）: FocusIn を先に済ませてから Controller.Activate。
  // Activate を省くと fcitx5 は非アクティブ（keyboard-us 担当）のままで、
  // ProcessKeyEvent が常に false を返す。
  FConn.CallVoid(FCITX_SERVICE, FICPath, IC_IFACE, 'FocusIn');
  FActive := True;
  try
    FConn.CallVoid(FCITX_SERVICE, CTRL_PATH, CTRL_IFACE, 'Activate');
  except
    // Controller が無い構成でも入力自体は動くので致命的ではない。
    on E: EPMLError do ;
  end;
end;

procedure TPMLFcitxTextInputBackend.Deactivate;
begin
  if Assigned(FConn) and FActive then
  begin
    FConn.CallVoid(FCITX_SERVICE, FICPath, IC_IFACE, 'FocusOut');
    FActive := False;
  end;
end;

procedure TPMLFcitxTextInputBackend.ResetComposition;
begin
  if Assigned(FConn) then
    FConn.CallVoid(FCITX_SERVICE, FICPath, IC_IFACE, 'Reset');
end;

procedure TPMLFcitxTextInputBackend.UpdateSurroundingText(const AText: String;
  ACursorByte, AAnchorByte: Integer);
var
  Msg, Reply: PDBusMessage;
  W: TPMLDBusWriter;
  CursorChar, AnchorChar: Integer;
begin
  if not Assigned(FConn) then
    Exit;
  // fcitx5 の SetSurroundingText はコードポイント単位。papimela の公開 API は
  // バイト単位なのでここで変換する（UpdateFormattedPreedit の cursor とは
  // 単位が違う点に注意）。
  CursorChar := UTF8ByteToCharOffset(AText, ACursorByte);
  AnchorChar := UTF8ByteToCharOffset(AText, AAnchorByte);
  FSurrounding := AText;
  FSurroundingCursor := CursorChar;

  Msg := FConn.BeginCall(FCITX_SERVICE, FICPath, IC_IFACE, 'SetSurroundingText');
  Reply := nil;
  try
    W := FConn.Writer(Msg);
    W.AddString(AText);
    W.AddUInt32(LongWord(CursorChar));
    W.AddUInt32(LongWord(AnchorChar));
    Reply := FConn.Send(Msg);
  finally
    FConn.Unref(Reply);
    FConn.Unref(Msg);
  end;
end;

procedure TPMLFcitxTextInputBackend.UpdateCursorRect(const ARect: TPMLRect; AScale: Double);
var
  Msg, Reply: PDBusMessage;
  W: TPMLDBusWriter;
begin
  if not Assigned(FConn) then
    Exit;
  Msg := nil;
  Reply := nil;
  try
    if FCursorRectV2 then
    begin
      // V2 はスケール値を受け取るので Wayland のグローバル座標問題を回避できる。
      Msg := FConn.BeginCall(FCITX_SERVICE, FICPath, IC_IFACE, 'SetCursorRectV2');
      W := FConn.Writer(Msg);
      W.AddInt32(ARect.X); W.AddInt32(ARect.Y);
      W.AddInt32(ARect.W); W.AddInt32(ARect.H);
      W.AddDouble(AScale);
    end
    else
    begin
      Msg := FConn.BeginCall(FCITX_SERVICE, FICPath, IC_IFACE, 'SetCursorRect');
      W := FConn.Writer(Msg);
      W.AddInt32(ARect.X); W.AddInt32(ARect.Y);
      W.AddInt32(ARect.W); W.AddInt32(ARect.H);
    end;
    try
      Reply := FConn.Send(Msg);
    except
      on E: EPMLError do
        if FCursorRectV2 then
        begin
          // 古い fcitx5。次回以降は V1 を使う。位置がずれるだけで機能は動く。
          FCursorRectV2 := False;
        end
        else
          raise;
    end;
  finally
    FConn.Unref(Reply);
    FConn.Unref(Msg);
  end;
end;

function TPMLFcitxTextInputBackend.ModifiersToState(const AMods: TPMLKeyModifiers): LongWord;
begin
  Result := 0;
  if TPMLKeyModifier.Shift    in AMods then Result := Result or X_SHIFT;
  if TPMLKeyModifier.CapsLock in AMods then Result := Result or X_LOCK;
  if TPMLKeyModifier.Ctrl     in AMods then Result := Result or X_CTRL;
  if TPMLKeyModifier.Alt      in AMods then Result := Result or X_ALT;
  if TPMLKeyModifier.NumLock  in AMods then Result := Result or X_NUM;
  if TPMLKeyModifier.Super    in AMods then Result := Result or X_SUPER;
end;

function TPMLFcitxTextInputBackend.FilterKey(const AKey: TPMLKeyEventData; AIsRelease: Boolean): TPMLKeyFilterResult;
var
  Msg, Reply: PDBusMessage;
  W: TPMLDBusWriter;
  R: TPMLDBusReader;
  Handled: Boolean;
begin
  Result := TPMLKeyFilterResult.PassThrough;
  if not Assigned(FConn) or not FActive then
    Exit;

  Msg := FConn.BeginCall(FCITX_SERVICE, FICPath, IC_IFACE, 'ProcessKeyEvent');
  Reply := nil;
  try
    W := FConn.Writer(Msg);
    W.AddUInt32(AKey.Keysym);
    W.AddUInt32(AKey.Keycode);
    W.AddUInt32(ModifiersToState(AKey.Modifiers));
    W.AddBoolean(AIsRelease);
    W.AddUInt32(0);   // time。0 は「不明」として扱われる
    Reply := FConn.Send(Msg);
    R := FConn.Reader(Reply);
    Handled := R.ExpectBoolean;
  finally
    FConn.Unref(Reply);
    FConn.Unref(Msg);
  end;

  if Handled then
    Result := TPMLKeyFilterResult.Consumed;
  // 応答の中で送られてきたシグナルを取り込む。
  Pump(0);
end;

procedure TPMLFcitxTextInputBackend.Pump(ATimeoutMs: Integer);
var
  Msg: PDBusMessage;
begin
  if not Assigned(FConn) then
    Exit;
  repeat
    Msg := FConn.PopMessage(ATimeoutMs);
    if Msg = nil then
      Break;
    try
      DispatchSignal(Msg);
    finally
      FConn.Unref(Msg);
    end;
    ATimeoutMs := 0;   // 2 通目以降は待たない
  until False;
end;

procedure TPMLFcitxTextInputBackend.DispatchSignal(AMsg: PDBusMessage);
begin
  if FConn.IsSignal(AMsg, IC_IFACE, 'UpdateFormattedPreedit') then
    HandleFormattedPreedit(AMsg)
  else if FConn.IsSignal(AMsg, IC_IFACE, 'CommitString') then
    HandleCommitString(AMsg)
  else if FConn.IsSignal(AMsg, IC_IFACE, 'DeleteSurroundingText') then
    HandleDeleteSurrounding(AMsg);
  // ForwardKey / CurrentIM / UpdateClientSideUI は現状未使用。
end;

{ UpdateFormattedPreedit(a(si) segments, i cursor)

  各要素が文節に対応する。フラグ → 状態の対応は fcitx5-mozc での実測に基づく:

  - HighLight を持つ文節      → Focused（注目文節）
  - 変換段階で Underline のみ  → Converted
  - 変換前（HighLight がどこにも無い）→ すべて Unconverted

  最後の条件は、ローマ字入力中の「わたしのなまえ」が Underline 単独で届く
  ことから必要になった。Underline だけで Converted と決めると未変換のかなを
  変換済みと誤って表示してしまう。 }
procedure TPMLFcitxTextInputBackend.HandleFormattedPreedit(AMsg: PDBusMessage);
var
  R, Arr, St: TPMLDBusReader;
  Comp: TPMLComposition;
  SegText: String;
  Flags: LongInt;
  Count, Pos_: Integer;
  AnyHighlight: Boolean;
  States: array of TPMLSegmentState;
  Texts: array of String;
  Flagged: array of LongInt;
  I: Integer;
begin
  R := FConn.Reader(AMsg);
  if R.ArgType <> DBUS_TYPE_ARRAY then
    Exit;

  Count := 0;
  AnyHighlight := False;
  SetLength(Texts, 0);
  SetLength(Flagged, 0);

  Arr := R.Recurse;
  while Arr.ArgType = DBUS_TYPE_STRUCT do
  begin
    St := Arr.Recurse;
    SegText := '';
    Flags := 0;
    if St.ArgType = DBUS_TYPE_STRING then
    begin
      SegText := St.AsString;
      St.Next;
      if St.ArgType = DBUS_TYPE_INT32 then
        Flags := St.AsInt32;
    end;
    SetLength(Texts, Count + 1);
    SetLength(Flagged, Count + 1);
    Texts[Count] := SegText;
    Flagged[Count] := Flags;
    if (Flags and FMT_HIGHLIGHT) <> 0 then
      AnyHighlight := True;
    Inc(Count);
    Arr.Next;
  end;

  // cursor は UTF-8 バイトオフセット（実測）。
  R.Next;
  if R.ArgType = DBUS_TYPE_INT32 then
    Comp.CursorByte := R.AsInt32
  else
    Comp.CursorByte := -1;

  SetLength(States, Count);
  Comp.Text := '';
  for I := 0 to Count - 1 do
  begin
    Comp.Text := Comp.Text + Texts[I];
    if (Flagged[I] and FMT_HIGHLIGHT) <> 0 then
      States[I] := TPMLSegmentState.Focused
    else if not AnyHighlight then
      States[I] := TPMLSegmentState.Unconverted
    else if (Flagged[I] and FMT_UNDERLINE) <> 0 then
      States[I] := TPMLSegmentState.Converted
    else
      States[I] := TPMLSegmentState.Unconverted;
  end;

  SetLength(Comp.Segments, Count);
  Pos_ := 0;
  for I := 0 to Count - 1 do
  begin
    Comp.Segments[I].StartByte := Pos_;
    Inc(Pos_, Length(Texts[I]));
    Comp.Segments[I].EndByte := Pos_;
    Comp.Segments[I].State := States[I];
    if (Flagged[I] and FMT_HIGHLIGHT) <> 0 then
      Comp.Segments[I].Underline := TPMLUnderlineStyle.Double
    else if (Flagged[I] and FMT_UNDERLINE) <> 0 then
      Comp.Segments[I].Underline := TPMLUnderlineStyle.Single
    else
      Comp.Segments[I].Underline := TPMLUnderlineStyle.None;
  end;

  Comp.SegmentsReliable := True;
  Comp.Finalize;
  if Assigned(FSink) then
    FSink.CompositionChanged(Comp);
end;

procedure TPMLFcitxTextInputBackend.HandleCommitString(AMsg: PDBusMessage);
var
  R: TPMLDBusReader;
begin
  R := FConn.Reader(AMsg);
  if R.ArgType <> DBUS_TYPE_STRING then
    Exit;
  if Assigned(FSink) then
    FSink.TextCommitted(R.AsString);
end;

{ DeleteSurroundingText(i offset, u size)

  offset はカーソルからの相対位置（コードポイント単位、負なら前方）、size は
  削除する文字数。papimela の公開モデルはカーソル前後のバイト数・文字数なので、
  最後に送った周辺テキストを使って変換する。 }
procedure TPMLFcitxTextInputBackend.HandleDeleteSurrounding(AMsg: PDBusMessage);
var
  R: TPMLDBusReader;
  Offset: LongInt;
  Size: LongWord;
  StartChar, EndChar: Integer;
  Data: TPMLDeleteSurroundingData;
  CurByte, StartByte, EndByte: Integer;
begin
  R := FConn.Reader(AMsg);
  if R.ArgType <> DBUS_TYPE_INT32 then
    Exit;
  Offset := R.AsInt32;
  R.Next;
  if R.ArgType <> DBUS_TYPE_UINT32 then
    Exit;
  Size := R.AsUInt32;

  StartChar := FSurroundingCursor + Offset;
  if StartChar < 0 then
    StartChar := 0;
  EndChar := StartChar + Integer(Size);

  Data.BeforeChars := FSurroundingCursor - StartChar;
  if Data.BeforeChars < 0 then
    Data.BeforeChars := 0;
  Data.AfterChars := EndChar - FSurroundingCursor;
  if Data.AfterChars < 0 then
    Data.AfterChars := 0;

  CurByte   := UTF8CharToByteOffset(FSurrounding, FSurroundingCursor);
  StartByte := UTF8CharToByteOffset(FSurrounding, StartChar);
  EndByte   := UTF8CharToByteOffset(FSurrounding, EndChar);
  Data.BeforeBytes := CurByte - StartByte;
  if Data.BeforeBytes < 0 then
    Data.BeforeBytes := 0;
  Data.AfterBytes := EndByte - CurByte;
  if Data.AfterBytes < 0 then
    Data.AfterBytes := 0;

  if Assigned(FSink) then
    FSink.DeleteSurroundingRequested(Data);
end;

end.
