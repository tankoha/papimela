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
    - 下の層の部品がヒント・ログ・プロパティに届く道は TPMLContextBase（ContextServices）。
      TPMLContext の型は下の層から見えないので、それが持つものだけをここに置く
    - CheckMainThread は PAPIMELA_DEBUG 時のみ実体を持つ

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Core.Base;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Errors,
  PaPiMeLa.Threading,
  PaPiMeLa.Properties,
  PaPiMeLa.Log;

type
  TPMLContextBase = class;

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
    // ルート（Context）の持つヒント・ログ・プロパティへの道。Context 自身なら自分。
    // Context 無しで作られた物（単体のサーフェスなど）では nil。
    function  ContextServices: TPMLContextBase;
    property MainThreadID: TThreadID read FMainThreadID;
  end;

  { Context の土台。TPMLContext（PaPiMeLa.Core）がこれを継承し、作り始めにヒント・
    ログ・プロパティを作る。下の層の部品は ContextServices でここに届く。 }
  TPMLContextBase = class abstract(TPMLObject)
  strict protected
    FHints     : TPMLHints;
    FProperties: TPMLProperties;
    FLog       : TPMLLog;
  public
    { アプリの ID（SDL_GetAppID）。Wayland の app_id などに使う。ヒント PML_HINT_APP_ID が
      空でなければそれ、次に環境変数 FLATPAK_ID、無ければ実行ファイルの名前（ApplicationName）。 }
    function  AppID: String;
    { 呼んだスレッドの優先度を変える（SDL_SetCurrentThreadPriority）。ヒント
      PAPIMELA_THREAD_PRIORITY_POLICY と PAPIMELA_THREAD_FORCE_REALTIME_TIME_CRITICAL を読んで
      TPMLThread.SetCurrentPriority に渡す。 }
    function  SetCurrentThreadPriority(APriority: TPMLThreadPriority): Boolean;
    property  Hints     : TPMLHints      read FHints;
    property  Properties: TPMLProperties read FProperties;
    property  Log       : TPMLLog        read FLog;
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

function TPMLObject.ContextServices: TPMLContextBase;
begin
  if Self is TPMLContextBase then
    Result := TPMLContextBase(Self)
  else if FContextRef is TPMLContextBase then
    Result := TPMLContextBase(FContextRef)
  else
    Result := nil;
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

function TPMLContextBase.AppID: String;
begin
  Result := '';
  if FHints <> nil then
    Result := FHints.GetHint(PML_HINT_APP_ID);
  if Result = '' then
    PMLGetEnvironment('FLATPAK_ID', Result);
  if Result = '' then
    Result := ApplicationName;
end;

function TPMLContextBase.SetCurrentThreadPriority(APriority: TPMLThreadPriority): Boolean;
var
  Policy: String;
  Force: Boolean;
begin
  Policy := '';
  Force := False;
  if FHints <> nil then
  begin
    Policy := FHints.GetHint(PML_HINT_THREAD_PRIORITY_POLICY);
    Force := FHints.GetBoolean(PML_HINT_THREAD_FORCE_REALTIME_TIME_CRITICAL, False);
  end;
  Result := TPMLThread.SetCurrentPriority(APriority, Policy, Force);
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
