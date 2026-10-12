{
  PaPiMeLa.TextInput.Backend — IME バックエンドの抽象基底と Null 実装

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §3.6、§11 #47

  WHAT:
    IPMLTextInputBackend の既定実装。未対応の操作は例外ではなく能力集合
    （Capabilities）で表すため、既定実装は何もしない。

  WHY:
    SDL は SDL_VideoDevice の 98 個の関数ポインタに「対応しないものは nil」を
    混ぜていた。papimela は「呼んでよいか」を能力集合で先に判断し、既定実装は
    安全に無視する。abstract メソッドにすると EAbstractError になるため、
    Connect / Disconnect 以外は virtual の空実装にする。

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.TextInput.Backend;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Properties,
  PaPiMeLa.Events,
  PaPiMeLa.Video,
  PaPiMeLa.TextInput;

type
  // アプリが自分で描く IME の部品（ヒント PAPIMELA_IME_IMPLEMENTED_UI）。
  TPMLImeUIElement  = (Composition, Candidates);
  TPMLImeUIElements = set of TPMLImeUIElement;

  TPMLTextInputBackend = class abstract(TObject, IPMLTextInputBackend)
  strict protected
    FSink: IPMLTextInputSink;
    FVideo: TPMLVideoSystem;     // 借りている。AttachVideo で受け取る（nil もありうる）
    FContextServices: TPMLContextBase;  // 借りている。AttachContext で受け取る（nil もありうる）
    FImeUI: TPMLImeUIElements;   // ヒント PAPIMELA_IME_IMPLEMENTED_UI の今の値（読んだもの）
    FImeUIChanged: Boolean;      // 最後に Take した後で FImeUI が変わった。変わりうるのは SetHint したスレッド
    FImeUIHints: TPMLHints;      // コールバックを置いたヒント表（借りている）。nil なら置いていない
    { ヒントの表。AttachContext で受け取った Context の表、無ければ AttachVideo で受け取った
      ビデオの Context の表。どちらも無ければ nil。 }
    function  FindHints: TPMLHints;
    { ヒントの変更を受け取り始める。置いた時点の値が FImeUI に入る（変更の印は付かない）。
      二重に呼んでも 1 つだけ。ヒントの表が無ければ FImeUI は既定（[Composition]）のまま。 }
    procedure SubscribeImeUI;
    { 受け取るのをやめる。SubscribeImeUI していなければ何もしない。 }
    procedure UnsubscribeImeUI;
    { FImeUI が変わっていたら True を返して印を消す。変わったときの送り直しはメインスレッドで
      （コールバックはどのスレッドからも来る）。 }
    function  TakeImeUIChanged: Boolean;
  public
    function  BackendName: String; virtual; abstract;
    function  Capabilities: TPMLTextInputCapabilities; virtual;
    procedure AttachVideo(AVideo: TPMLVideoSystem); virtual;
    // Context の土台（ヒントやログ）を渡す。Connect より前に呼ぶ。ビデオを使わない Context でも渡す。
    procedure AttachContext(AServices: TPMLContextBase);
    function  Connect(ASink: IPMLTextInputSink): Boolean; virtual; abstract;
    procedure Disconnect; virtual;
    procedure Activate(AWindow: TPMLWindow; AType: TPMLTextInputType;
      AHints: TPMLTextInputHints); virtual;
    procedure Deactivate; virtual;
    procedure ResetComposition; virtual;
    procedure UpdateSurroundingText(const AText: String; ACursorByte, AAnchorByte: Integer); virtual;
    procedure UpdateCursorRect(const ARect: TPMLRect; AScale: Double); virtual;
    function  FilterKey(const AKey: TPMLKeyEventData; AIsRelease: Boolean;
      ATicket: LongWord): TPMLKeyFilterResult; virtual;
    procedure Pump(ATimeoutMs: Integer); virtual;
  private
    procedure ImeUIHintChanged(const AName: String; const AOld, ANew: TPMLHintValue);
  end;

  { IME が無い環境。キーはそのままアプリへ流れる。 }
  TPMLNullTextInputBackend = class(TPMLTextInputBackend)
  public
    function BackendName: String; override;
    function Connect(ASink: IPMLTextInputSink): Boolean; override;
  end;

  TPMLTextInputBackendFactory = function: TPMLTextInputBackend;

{ ---- バックエンドが共有する変換 ---- }

{ ヒント PAPIMELA_IME_IMPLEMENTED_UI の値を読む。カンマで分けた語（前後の空白は除き、大文字
  小文字は区別しない）の 'composition' / 'candidates' の和。'none' か '0' があれば空。
  値が空（置かれていない）なら [Composition]: papimela は変換中の文字を全文節つきでアプリへ渡す
  のが既定（SDL の既定は none で、変換中の文字は IME が自分で描く）。 }
function PMLParseImeImplementedUI(const AHint: String): TPMLImeUIElements;


// 修飾キーを X11 の状態マスク（ShiftMask=1、LockMask=2、ControlMask=4、Mod1=8（Alt）、
// Mod2=16（NumLock）、Mod4=64（Super））にする。Fcitx5 も IBus もこれで話す。
function PMLModifiersToXState(const AMods: TPMLKeyModifiers): LongWord;

// IME の「カーソルから AOffset 文字の位置から ACount 文字を消す」を、papimela の
// 「カーソルの前後を消す」（バイト数と文字数）に直す。AText は最後に IME へ送った
// 周辺テキスト、ACursorChar はその中のカーソル（文字単位）。送ったテキストの外へ
// はみ出す分は IME が知り得ないので切り捨てる。範囲がカーソルに接していなければ
// （例: カーソル 3 で「先頭の 1 文字だけ」）papimela のモデルでは表せないので、何も消さない
// （両方 0）。頼まれていない文字まで消すよりよい。
function PMLDeleteSurroundingFromChars(const AText: String;
  ACursorChar, AOffset, ACount: Integer): TPMLDeleteSurroundingData;

{ ---- 登録（#45） ----

  具象バックエンドは、自分のユニットの initialization で自分を登録する。
  公開層（PaPiMeLa.TextInput）は具象バックエンドを uses しない（設計 §2.1）。どれを
  リンクするかはアプリの uses で決まる: PaPiMeLa.Backends（またはアンブレラの
  PaPiMeLa）を uses すれば全部、個別のユニットを uses すればそれだけ。

  名前は大文字小文字を区別せずに比べる。同じ名前を 2 度登録すると
  EPMLArgument。試す順は優先度の大きい順、同じなら登録した順。

  IME の無い環境のための 'none'（TPMLNullTextInputBackend）は登録しない。
  公開層が最後の候補として必ず持つ。 }
procedure PMLRegisterTextInputBackend(const AName: String; APriority: Integer;
  AFactory: TPMLTextInputBackendFactory);
function  PMLTextInputBackendNames: TStringArray;
function  PMLFindTextInputBackend(const AName: String): TPMLTextInputBackendFactory;

implementation

uses
  PaPiMeLa.Errors,
  PaPiMeLa.Unicode;

function PMLModifiersToXState(const AMods: TPMLKeyModifiers): LongWord;
begin
  Result := 0;
  if TPMLKeyModifier.Shift    in AMods then Result := Result or (1 shl 0);
  if TPMLKeyModifier.CapsLock in AMods then Result := Result or (1 shl 1);
  if TPMLKeyModifier.Ctrl     in AMods then Result := Result or (1 shl 2);
  if TPMLKeyModifier.Alt      in AMods then Result := Result or (1 shl 3);
  if TPMLKeyModifier.NumLock  in AMods then Result := Result or (1 shl 4);
  if TPMLKeyModifier.Super    in AMods then Result := Result or (1 shl 6);
end;

function PMLDeleteSurroundingFromChars(const AText: String;
  ACursorChar, AOffset, ACount: Integer): TPMLDeleteSurroundingData;
var
  Total, StartChar, EndChar, CurByte: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Total := UTF8CodePointCount(AText);
  if ACursorChar < 0 then
    ACursorChar := 0;
  if ACursorChar > Total then
    ACursorChar := Total;
  if ACount < 0 then
    ACount := 0;
  StartChar := ACursorChar + AOffset;
  EndChar := StartChar + ACount;
  if StartChar < 0 then
    StartChar := 0;
  if EndChar > Total then
    EndChar := Total;
  if (EndChar <= StartChar) or (StartChar > ACursorChar) or (EndChar < ACursorChar) then
    Exit;
  // カーソルの前後に分ける。
  if StartChar < ACursorChar then
    Result.BeforeChars := ACursorChar - StartChar;
  if EndChar > ACursorChar then
    Result.AfterChars := EndChar - ACursorChar;
  CurByte := UTF8CharToByteOffset(AText, ACursorChar);
  Result.BeforeBytes := CurByte - UTF8CharToByteOffset(AText, ACursorChar - Result.BeforeChars);
  Result.AfterBytes := UTF8CharToByteOffset(AText, ACursorChar + Result.AfterChars) - CurByte;
end;

procedure TPMLTextInputBackend.AttachContext(AServices: TPMLContextBase);
begin
  FContextServices := AServices;
end;

function TPMLTextInputBackend.FindHints: TPMLHints;
begin
  Result := nil;
  if Assigned(FContextServices) then
    Exit(FContextServices.Hints);
  if Assigned(FVideo) and Assigned(FVideo.ContextServices) then
    Result := FVideo.ContextServices.Hints;
end;

procedure TPMLTextInputBackend.ImeUIHintChanged(const AName: String;
  const AOld, ANew: TPMLHintValue);
var
  NewUI: TPMLImeUIElements;
begin
  // 置かれていないヒントの Value は ''（既定の [Composition] になる）。
  NewUI := PMLParseImeImplementedUI(ANew.Value);
  if NewUI <> FImeUI then
  begin
    FImeUI := NewUI;
    FImeUIChanged := True;
  end;
end;

procedure TPMLTextInputBackend.SubscribeImeUI;
begin
  FImeUI := PMLParseImeImplementedUI('');
  if Assigned(FImeUIHints) then
    Exit;
  FImeUIHints := FindHints;
  if not Assigned(FImeUIHints) then
    Exit;
  // AddCallback はその場で 1 度呼ぶので、今の値が FImeUI に入る。
  FImeUIHints.AddCallback(PML_HINT_IME_IMPLEMENTED_UI, @ImeUIHintChanged);
  FImeUIChanged := False;
end;

procedure TPMLTextInputBackend.UnsubscribeImeUI;
begin
  if Assigned(FImeUIHints) then
    FImeUIHints.RemoveCallback(PML_HINT_IME_IMPLEMENTED_UI, @ImeUIHintChanged);
  FImeUIHints := nil;
end;

function TPMLTextInputBackend.TakeImeUIChanged: Boolean;
begin
  Result := FImeUIChanged;
  FImeUIChanged := False;
end;

function TPMLTextInputBackend.Capabilities: TPMLTextInputCapabilities;
begin
  Result := [];
end;

procedure TPMLTextInputBackend.Disconnect;
begin
  UnsubscribeImeUI;
  FSink := nil;
end;

procedure TPMLTextInputBackend.AttachVideo(AVideo: TPMLVideoSystem);
begin
  FVideo := AVideo;
end;

procedure TPMLTextInputBackend.Activate(AWindow: TPMLWindow; AType: TPMLTextInputType;
  AHints: TPMLTextInputHints);
begin
end;

procedure TPMLTextInputBackend.Deactivate;
begin
end;

procedure TPMLTextInputBackend.ResetComposition;
begin
end;

procedure TPMLTextInputBackend.UpdateSurroundingText(const AText: String;
  ACursorByte, AAnchorByte: Integer);
begin
end;

procedure TPMLTextInputBackend.UpdateCursorRect(const ARect: TPMLRect; AScale: Double);
begin
end;

function TPMLTextInputBackend.FilterKey(const AKey: TPMLKeyEventData; AIsRelease: Boolean;
  ATicket: LongWord): TPMLKeyFilterResult;
begin
  Result := TPMLKeyFilterResult.PassThrough;
end;

procedure TPMLTextInputBackend.Pump(ATimeoutMs: Integer);
begin
end;

{ TPMLNullTextInputBackend }

function TPMLNullTextInputBackend.BackendName: String;
begin
  Result := 'none';
end;

function TPMLNullTextInputBackend.Connect(ASink: IPMLTextInputSink): Boolean;
begin
  FSink := ASink;
  Result := True;
end;

{ ---- 登録（#45） ---- }

type
  TTextInputRegistration = record
    Name    : String;
    Priority: Integer;
    Factory : TPMLTextInputBackendFactory;
  end;

var
  // 試す順（優先度の大きい順、同じなら登録順）に並べて持つ。
  TextInputRegistry: array of TTextInputRegistration;

function FindTextInputIndex(const AName: String): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(TextInputRegistry) do
    if SameText(TextInputRegistry[I].Name, AName) then
      Exit(I);
end;

procedure PMLRegisterTextInputBackend(const AName: String; APriority: Integer;
  AFactory: TPMLTextInputBackendFactory);
var
  At, I: Integer;
begin
  if AName = '' then
    raise EPMLArgument.Create('text input backend name is empty');
  if not Assigned(AFactory) then
    raise EPMLArgument.Create('text input backend factory is nil');
  if FindTextInputIndex(AName) >= 0 then
    raise EPMLArgument.CreateFmt('text input backend "%s" is already registered', [AName]);
  // 自分より優先度の小さい最初の位置へ入れる（同じ優先度は後ろへ回る）。
  At := Length(TextInputRegistry);
  for I := 0 to High(TextInputRegistry) do
    if TextInputRegistry[I].Priority < APriority then
    begin
      At := I;
      Break;
    end;
  SetLength(TextInputRegistry, Length(TextInputRegistry) + 1);
  for I := High(TextInputRegistry) downto At + 1 do
    TextInputRegistry[I] := TextInputRegistry[I - 1];
  TextInputRegistry[At].Name := AName;
  TextInputRegistry[At].Priority := APriority;
  TextInputRegistry[At].Factory := AFactory;
end;

function PMLTextInputBackendNames: TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(TextInputRegistry));
  for I := 0 to High(TextInputRegistry) do
    Result[I] := TextInputRegistry[I].Name;
end;

function PMLFindTextInputBackend(const AName: String): TPMLTextInputBackendFactory;
var
  I: Integer;
begin
  I := FindTextInputIndex(AName);
  if I >= 0 then
    Result := TextInputRegistry[I].Factory
  else
    Result := nil;
end;

function PMLParseImeImplementedUI(const AHint: String): TPMLImeUIElements;
var
  Rest, Token: String;
  P: Integer;
  Found: TPMLImeUIElements;
  IsNone: Boolean;
begin
  // 空白だけの値も、置かれていないのと同じに扱う。
  if Trim(AHint) = '' then
    Exit([TPMLImeUIElement.Composition]);
  Found := [];
  IsNone := False;
  Rest := AHint;
  repeat
    P := Pos(',', Rest);
    if P > 0 then
    begin
      Token := Trim(Copy(Rest, 1, P - 1));
      Delete(Rest, 1, P);
    end
    else
    begin
      Token := Trim(Rest);
      Rest := '';
    end;
    if SameText(Token, 'composition') then
      Include(Found, TPMLImeUIElement.Composition)
    else if SameText(Token, 'candidates') then
      Include(Found, TPMLImeUIElement.Candidates)
    else if SameText(Token, 'none') or (Token = '0') then
      IsNone := True;
  until (P = 0);
  // 'none' は他の語より強い。知らない語は無視する。
  if IsNone then
    Result := []
  else
    Result := Found;
end;

end.
