{
  PaPiMeLa.Core.Base — 所有グラフを型で表す基底クラス

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §4.1、§2.4

  WHAT:
    TPMLObject と、所有関係の 2 種類（システムが所有する / アプリが生成する）を
    型で区別する基底クラス。

  WHY:
    §4.1 の基底を PaPiMeLa.Core から分けてあるのは、Pascal がユニットをまたいだ
    クラスの前方宣言を許さないため。TPMLObject は Context への参照を持ち、
    TPMLContext は TPMLEventQueue を持ち、TPMLEventQueue は TPMLSystemObject を
    継承するので、1 ユニットに押し込むと Core が巨大になる。Context 参照を
    TObject 型で持ち、Core が TPMLContext として解決する。

  RESOLVED:
    - 親は子への参照を持ち、子は親への借用参照を持つ。破棄は常に親から
    - CheckMainThread は PAPIMELA_DEBUG 時のみ実体を持つ

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Core.Base;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Errors;

type
  TPMLObject = class abstract(TObject)
  strict private
    FContextRef  : TObject;
    FMainThreadID: TThreadID;
  protected
    constructor Create(AContextRef: TObject);
    // メインスレッド制約の検査。違反は EPMLThreadAffinity。
    procedure CheckMainThread;
    procedure SetMainThreadID(AID: TThreadID);
  public
    // ルートへの借用参照。PaPiMeLa.Core が TPMLContext へキャストして使う。
    property ContextRef  : TObject read FContextRef;
    property MainThreadID: TThreadID read FMainThreadID;
  end;

  { 所有者（サブシステム）だけが生成・破棄する。アプリは Free してはならない。 }
  TPMLSystemObject = class abstract(TPMLObject)
  strict private
    FOwner: TPMLObject;
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject);
    property Owner: TPMLObject read FOwner;
  end;

  { アプリが Create し、アプリまたは所有者のどちらが先に Free してもよい。 }
  TPMLOwnedObject = class abstract(TPMLObject)
  strict private
    FOwner: TPMLObject;
  protected
    procedure DetachFromOwner; virtual;
    procedure OwnerDestroying; virtual;
  public
    constructor Create(AContextRef: TObject; AOwner: TPMLObject);
    destructor Destroy; override;
    property Owner: TPMLObject read FOwner;
  end;

implementation

constructor TPMLObject.Create(AContextRef: TObject);
begin
  inherited Create;
  FContextRef := AContextRef;
  // Context 自身（AContextRef = nil）は生成したスレッドをメインとみなす。
  if AContextRef is TPMLObject then
    FMainThreadID := TPMLObject(AContextRef).MainThreadID
  else
    FMainThreadID := GetCurrentThreadID;
end;

procedure TPMLObject.SetMainThreadID(AID: TThreadID);
begin
  FMainThreadID := AID;
end;

procedure TPMLObject.CheckMainThread;
begin
{$ifdef PAPIMELA_DEBUG}
  if GetCurrentThreadID <> FMainThreadID then
    raise EPMLThreadAffinity.CreateFmt(
      '%s must be used from the main thread (context thread %d, current %d)',
      [ClassName, PtrUInt(FMainThreadID), PtrUInt(GetCurrentThreadID)]);
{$endif}
end;

constructor TPMLSystemObject.Create(AContextRef: TObject; AOwner: TPMLObject);
begin
  inherited Create(AContextRef);
  FOwner := AOwner;
end;

constructor TPMLOwnedObject.Create(AContextRef: TObject; AOwner: TPMLObject);
begin
  inherited Create(AContextRef);
  FOwner := AOwner;
end;

destructor TPMLOwnedObject.Destroy;
begin
  if Assigned(FOwner) then
    DetachFromOwner;
  inherited Destroy;
end;

procedure TPMLOwnedObject.DetachFromOwner;
begin
  FOwner := nil;
end;

procedure TPMLOwnedObject.OwnerDestroying;
begin
  FOwner := nil;
  Free;
end;

end.
