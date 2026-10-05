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
  PaPiMeLa.Events,
  PaPiMeLa.Video,
  PaPiMeLa.TextInput;

type
  TPMLTextInputBackend = class abstract(TObject, IPMLTextInputBackend)
  strict protected
    FSink: IPMLTextInputSink;
    FVideo: TPMLVideoSystem;     // 借りている。AttachVideo で受け取る（nil もありうる）
  public
    function  BackendName: String; virtual; abstract;
    function  Capabilities: TPMLTextInputCapabilities; virtual;
    procedure AttachVideo(AVideo: TPMLVideoSystem); virtual;
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
  end;

  { IME が無い環境。キーはそのままアプリへ流れる。 }
  TPMLNullTextInputBackend = class(TPMLTextInputBackend)
  public
    function BackendName: String; override;
    function Connect(ASink: IPMLTextInputSink): Boolean; override;
  end;

  TPMLTextInputBackendFactory = function: TPMLTextInputBackend;

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
  PaPiMeLa.Errors;

function TPMLTextInputBackend.Capabilities: TPMLTextInputCapabilities;
begin
  Result := [];
end;

procedure TPMLTextInputBackend.Disconnect;
begin
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

end.
