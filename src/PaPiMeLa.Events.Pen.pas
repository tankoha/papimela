{
  PaPiMeLa.Events.Pen — ペンの状態機械の中身（機器の一覧・入力の状態・マウスとタッチの合成）

  Origin : ported from SDL (src/events/SDL_pen.c)
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #66

  WHAT:
    公開の TPMLPenState（PaPiMeLa.Events。バックエンドが呼ぶ窓口）の中身。
    ペンの機器の一覧と、ペンごとの入力の状態（PML_PEN_INPUT_xxx）・座標・軸の値を持ち、
    変わったときだけ Pen* のイベントを積む。ヒント PAPIMELA_PEN_MOUSE_EVENTS /
    PAPIMELA_PEN_TOUCH_EVENTS に従ってマウスとタッチのイベントも合成する。

  WHY:
    PaPiMeLa.Events はクリーンルームのユニット。ここは SDL のソースを読んで写した部分
    なので、由来を分けるためにユニットを分けた（PaPiMeLa.Events.Keyboard と同じ形）。

  NOT RESOLVED:
    - 骨組みだけ。メソッドの中身は #66 の実装で書く（検査 T-87 を先に書いた）
    - SDL は触れているペンを 1 本（pen_touching）だけプロセスに持つ。papimela はキューごと

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Events.Pen;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Properties,
  PaPiMeLa.Events;

type
  { TPMLPenState の中身。公開側の各メソッドはここへ渡す。メソッドの意味は TPMLPenState の宣言。 }
  TPMLPenImpl = class
  strict private
    FQueue       : TPMLEventQueue;
    FHints       : TPMLHints;
    FWindowExists: TPMLWindowExistsFunc;
  public
    // AHints が nil なら、ヒントは既定（どちらの合成も有効）のまま。
    constructor Create(AQueue: TPMLEventQueue; AHints: TPMLHints);
    destructor Destroy; override;

    function  AddDevice(const AName: String; AWindowID: TPMLWindowID;
      const AInfo: TPMLPenInfo; AHandle: Pointer; AInProximity: Boolean): TPMLPenID;
    procedure RemoveDevice(AWindowID: TPMLWindowID; AID: TPMLPenID);
    procedure RemoveAll(ACallback: TPMLPenRemoveProc);
    procedure SendTouch(AID: TPMLPenID; AWindowID: TPMLWindowID; AEraser, ADown: Boolean);
    procedure SendMotion(AID: TPMLPenID; AWindowID: TPMLWindowID; AX, AY: Single);
    procedure SendAxis(AID: TPMLPenID; AWindowID: TPMLWindowID; AAxis: TPMLPenAxis;
      AValue: Single);
    procedure SendButton(AID: TPMLPenID; AWindowID: TPMLWindowID; AButton: Byte;
      ADown: Boolean);
    procedure SendProximity(AID: TPMLPenID; AWindowID: TPMLWindowID; AIn, AImmediate: Boolean);
    procedure SendPendingProximity;
    function  FindByHandle(AHandle: Pointer): TPMLPenID;
    function  GetStatus(AID: TPMLPenID; out AAxes: TPMLPenAxes): TPMLPenInputFlags;
    function  GetDeviceType(AID: TPMLPenID): TPMLPenDeviceType;
    function  Count: Integer;
    property WindowExists: TPMLWindowExistsFunc read FWindowExists write FWindowExists;
  end;

implementation

{ 骨組み。T-87 が空の実装で落ちることを確かめるためのもの。中身は #66 の実装で書く。 }

constructor TPMLPenImpl.Create(AQueue: TPMLEventQueue; AHints: TPMLHints);
begin
  inherited Create;
  FQueue := AQueue;
  FHints := AHints;
end;

destructor TPMLPenImpl.Destroy;
begin
  inherited Destroy;
end;

function TPMLPenImpl.AddDevice(const AName: String; AWindowID: TPMLWindowID;
  const AInfo: TPMLPenInfo; AHandle: Pointer; AInProximity: Boolean): TPMLPenID;
begin
  Result := 0;
end;

procedure TPMLPenImpl.RemoveDevice(AWindowID: TPMLWindowID; AID: TPMLPenID);
begin
end;

procedure TPMLPenImpl.RemoveAll(ACallback: TPMLPenRemoveProc);
begin
end;

procedure TPMLPenImpl.SendTouch(AID: TPMLPenID; AWindowID: TPMLWindowID;
  AEraser, ADown: Boolean);
begin
end;

procedure TPMLPenImpl.SendMotion(AID: TPMLPenID; AWindowID: TPMLWindowID; AX, AY: Single);
begin
end;

procedure TPMLPenImpl.SendAxis(AID: TPMLPenID; AWindowID: TPMLWindowID;
  AAxis: TPMLPenAxis; AValue: Single);
begin
end;

procedure TPMLPenImpl.SendButton(AID: TPMLPenID; AWindowID: TPMLWindowID;
  AButton: Byte; ADown: Boolean);
begin
end;

procedure TPMLPenImpl.SendProximity(AID: TPMLPenID; AWindowID: TPMLWindowID;
  AIn, AImmediate: Boolean);
begin
end;

procedure TPMLPenImpl.SendPendingProximity;
begin
end;

function TPMLPenImpl.FindByHandle(AHandle: Pointer): TPMLPenID;
begin
  Result := 0;
end;

function TPMLPenImpl.GetStatus(AID: TPMLPenID; out AAxes: TPMLPenAxes): TPMLPenInputFlags;
begin
  FillChar(AAxes, SizeOf(AAxes), 0);
  Result := 0;
end;

function TPMLPenImpl.GetDeviceType(AID: TPMLPenID): TPMLPenDeviceType;
begin
  Result := TPMLPenDeviceType.Invalid;
end;

function TPMLPenImpl.Count: Integer;
begin
  Result := 0;
end;

end.
