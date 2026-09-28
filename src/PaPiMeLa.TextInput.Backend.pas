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
  PaPiMeLa.Types,
  PaPiMeLa.TextInput;

type
  TPMLTextInputBackend = class abstract(TObject, IPMLTextInputBackend)
  strict protected
    FSink: IPMLTextInputSink;
  public
    function  BackendName: String; virtual; abstract;
    function  Capabilities: TPMLTextInputCapabilities; virtual;
    function  Connect(ASink: IPMLTextInputSink): Boolean; virtual; abstract;
    procedure Disconnect; virtual;
    procedure Activate(AType: TPMLTextInputType; AHints: TPMLTextInputHints); virtual;
    procedure Deactivate; virtual;
    procedure ResetComposition; virtual;
    procedure UpdateSurroundingText(const AText: String; ACursorByte, AAnchorByte: Integer); virtual;
    procedure UpdateCursorRect(const ARect: TPMLRect; AScale: Double); virtual;
    function  FilterKey(const AKey: TPMLKeyEventData): TPMLKeyFilterResult; virtual;
    procedure Pump(ATimeoutMs: Integer); virtual;
  end;

  { IME が無い環境。キーはそのままアプリへ流れる。 }
  TPMLNullTextInputBackend = class(TPMLTextInputBackend)
  public
    function BackendName: String; override;
    function Connect(ASink: IPMLTextInputSink): Boolean; override;
  end;

implementation

function TPMLTextInputBackend.Capabilities: TPMLTextInputCapabilities;
begin
  Result := [];
end;

procedure TPMLTextInputBackend.Disconnect;
begin
  FSink := nil;
end;

procedure TPMLTextInputBackend.Activate(AType: TPMLTextInputType; AHints: TPMLTextInputHints);
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

function TPMLTextInputBackend.FilterKey(const AKey: TPMLKeyEventData): TPMLKeyFilterResult;
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

end.
