{
  PaPiMeLa.Clipboard — クリップボードとプライマリ選択の公開窓口

  Origin : original work (clean-room design; not derived from SDL sources)
           振る舞いの契約は SDL_clipboard.c を読んで合わせた（コードは写していない）。
  Design : docs/DESIGN.md §4（TPMLClipboard）、§11 #32、#38

  WHAT:
    文字列（Text / PrimarySelectionText）と、MIME タイプごとのデータ（SetData /
    GetData）を置き・読む。他のアプリが選択を取ったら ClipboardUpdate を積む。

  WHY:
    SDL は関数ポインタとユーザーデータの組（コールバック + 後始末）でデータを
    受け取る。papimela は CORBA のインターフェース IPMLClipboardDataProvider に
    まとめた。文字列は内部の提供者で同じ経路を通す。

  RESOLVED:
    - 持ち主（Owner）がこちらなら、データは提供者から直接読む（自分の選択を
      パイプで読みに行くと、自分が書くのを待って止まる）
    - 置き換えるときは、部品を新しいデータへ切り替えてから古い提供者に
      ClipboardDataCancelled を送る（部品が古い提供者を呼ぶ隙間を作らない）。
      SDL は後始末を先に呼ぶ
    - SetData に MIME タイプが無い・提供者が無いのは EPMLArgument（SDL は
      「両方ある」か「両方無い」を許し、後者を Clear にする。papimela は Clear を
      別に持つ）
    - Text に '' を置くのは Clear（SDL と同じ）
    - プライマリ選択の ClipboardUpdate にはプライマリ選択の MIME タイプを載せる
      （SDL はクリップボードの方を載せている）
    - 部品が無い（ダミーのビデオ）ときは、プロセスの中だけで持つ。部品はあるが
      プライマリ選択が無い（コンポジタが広告しない）ときは、置くと EPMLUnsupported

  NOT RESOLVED:
    - 他のアプリが選択を取ったことは、ウィンドウにキーボードのフォーカスがあるときに
      しか届かない（Wayland の規定）。フォーカスが無い間は持ち主でなくなったことだけ
      分かり、ClipboardUpdate は積まない（SDL と同じ）

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Clipboard;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Events,
  PaPiMeLa.Video.Backend;

type
  // 部品の約束（PaPiMeLa.Video.Backend）にある型を、公開層からも同じ名前で使えるようにする。
  // アンブレラ（uses PaPiMeLa）はこちらを並べ直す。
  TPMLClipboardSelection    = PaPiMeLa.Video.Backend.TPMLClipboardSelection;
  IPMLClipboardDataProvider = PaPiMeLa.Video.Backend.IPMLClipboardDataProvider;

  { 文字列を配る内部の提供者。TPMLClipboard が持ち、置き換えたら捨てる。 }
  TPMLTextClipboardProvider = class(TObject, IPMLClipboardDataProvider)
  strict private
    FBytes: TBytes;
  public
    constructor Create(const AText: String);
    function  GetClipboardData(const AMimeType: String; out AData: TBytes): Boolean;
    procedure ClipboardDataCancelled;
  end;

  { 1 つの選択（クリップボードかプライマリ選択）の状態。 }
  TPMLSelectionState = record
    Owner    : Boolean;                    // こちらが置いたデータを配っている
    Provider : IPMLClipboardDataProvider;  // Owner のとき
    MimeTypes: TStringArray;               // Owner のとき、置いた MIME タイプ
    Internal : TPMLTextClipboardProvider;  // Provider がこれなら所有している
  end;

  TPMLClipboard = class sealed(TPMLSystemObject, IPMLClipboardSink)
  strict private
    FQueue  : TPMLEventQueue;
    FBackend: TPMLClipboardBackend;     // 借りている。nil = プロセスの中だけ
    FSel    : array[TPMLClipboardSelection] of TPMLSelectionState;
    procedure Place(ASelection: TPMLClipboardSelection; const AMimeTypes: TStringArray;
      AProvider: IPMLClipboardDataProvider; AInternal: TPMLTextClipboardProvider);
    procedure Drop(ASelection: TPMLClipboardSelection);
    procedure PushUpdate(ASelection: TPMLClipboardSelection; AOwner: Boolean;
      const AMimeTypes: TStringArray);
    function  ReadData(ASelection: TPMLClipboardSelection; const AMimeType: String;
      out AData: TBytes): Boolean;
    function  HasMime(ASelection: TPMLClipboardSelection; const AMimeType: String): Boolean;
    function  ReadText(ASelection: TPMLClipboardSelection): String;
    function  HasTextIn(ASelection: TPMLClipboardSelection): Boolean;
    procedure PlaceText(ASelection: TPMLClipboardSelection; const AText: String);
    function  GetText: String;
    procedure SetText(const AValue: String);
    function  GetPrimarySelectionText: String;
    procedure SetPrimarySelectionText(const AValue: String);
    function  GetOwner: Boolean;
    function  GetPrimaryAvailable: Boolean;
  public
    // ABackend は TPMLVideoBackend.Clipboard（nil 可）。借りるだけ。
    constructor Create(AContextRef: TObject; AOwner: TPMLObject; AQueue: TPMLEventQueue;
      ABackend: TPMLClipboardBackend);
    destructor Destroy; override;

    // ---- クリップボード
    // AMimeTypes のどれかを求められたら AProvider.GetClipboardData を呼ぶ。
    procedure SetData(const AMimeTypes: array of String; AProvider: IPMLClipboardDataProvider);
    procedure Clear;
    // AMimeType のデータを読む。無ければ False（AData は空）。
    function  GetData(const AMimeType: String; out AData: TBytes): Boolean;
    function  HasData(const AMimeType: String): Boolean;
    // 今のクリップボードが配っている MIME タイプ（こちらのものでも他のアプリのものでも）。
    function  MimeTypes: TStringArray;
    function  HasText: Boolean;
    // 置くと、TextMimeTypes の全部で配る。'' は Clear。読むと、無ければ ''。
    property  Text: String read GetText write SetText;
    // 今のクリップボードがこのアプリの置いたものか。
    property  IsOwner: Boolean read GetOwner;

    // ---- プライマリ選択（文字列だけ）
    function  HasPrimarySelectionText: Boolean;
    property  PrimarySelectionText: String read GetPrimarySelectionText
      write SetPrimarySelectionText;
    // 置けるか。False のとき PrimarySelectionText に置くと EPMLUnsupported。
    property  PrimarySelectionAvailable: Boolean read GetPrimaryAvailable;

    // IPMLClipboardSink（部品が呼ぶ）
    procedure ClipboardOwnershipLost(ASelection: TPMLClipboardSelection);
    procedure ClipboardOffered(ASelection: TPMLClipboardSelection;
      const AMimeTypes: TStringArray);
  end;

implementation

{ TPMLTextClipboardProvider }

constructor TPMLTextClipboardProvider.Create(const AText: String);
begin
  inherited Create;
  SetLength(FBytes, Length(AText));
  if Length(AText) > 0 then
    Move(AText[1], FBytes[0], Length(AText));
end;

function TPMLTextClipboardProvider.GetClipboardData(const AMimeType: String;
  out AData: TBytes): Boolean;
begin
  AData := Copy(FBytes);
  Result := True;
end;

procedure TPMLTextClipboardProvider.ClipboardDataCancelled;
begin
  // 持ち主（TPMLClipboard）が捨てるので、ここでは何もしない。
end;

function BytesToString(const AData: TBytes): String;
begin
  SetLength(Result, Length(AData));
  if Length(AData) > 0 then
    Move(AData[0], Result[1], Length(AData));
end;

function Contains(const AList: TStringArray; const AValue: String): Boolean;
var
  S: String;
begin
  for S in AList do
    if S = AValue then
      Exit(True);
  Result := False;
end;

{ TPMLClipboard }

constructor TPMLClipboard.Create(AContextRef: TObject; AOwner: TPMLObject;
  AQueue: TPMLEventQueue; ABackend: TPMLClipboardBackend);
begin
  inherited Create(AContextRef, AOwner);
  FQueue := AQueue;
  FBackend := ABackend;
  if Assigned(FBackend) then
    FBackend.Attach(Self as IPMLClipboardSink);
end;

destructor TPMLClipboard.Destroy;
var
  S: TPMLClipboardSelection;
begin
  // 終わるときは配るのをやめ、提供者に知らせる。
  for S := Low(TPMLClipboardSelection) to High(TPMLClipboardSelection) do
    if FSel[S].Owner then
    begin
      if Assigned(FBackend) and FBackend.SupportsSelection(S) then
        FBackend.SetSelection(S, nil, nil);
      Drop(S);
    end;
  if Assigned(FBackend) then
    FBackend.Attach(nil);
  inherited Destroy;
end;

{ 持っているデータを手放す。提供者には 1 回だけ知らせる。部品はもう呼ばない前提。 }
procedure TPMLClipboard.Drop(ASelection: TPMLClipboardSelection);
var
  Old: IPMLClipboardDataProvider;
  OldInternal: TPMLTextClipboardProvider;
begin
  Old := FSel[ASelection].Provider;
  OldInternal := FSel[ASelection].Internal;
  FSel[ASelection].Owner := False;
  FSel[ASelection].Provider := nil;
  FSel[ASelection].MimeTypes := nil;
  FSel[ASelection].Internal := nil;
  if Assigned(Old) then
    Old.ClipboardDataCancelled;
  OldInternal.Free;
end;

{ 新しいデータを置く。AProvider が nil なら手放すだけ。部品を先に切り替えてから
  古い提供者に知らせる。 }
procedure TPMLClipboard.Place(ASelection: TPMLClipboardSelection;
  const AMimeTypes: TStringArray; AProvider: IPMLClipboardDataProvider;
  AInternal: TPMLTextClipboardProvider);
var
  Ok: Boolean;
begin
  CheckMainThread;
  Ok := True;
  if Assigned(FBackend) then
  begin
    if not FBackend.SupportsSelection(ASelection) then
    begin
      AInternal.Free;
      raise EPMLUnsupported.Create('the video backend has no primary selection');
    end;
    Ok := FBackend.SetSelection(ASelection, AMimeTypes, AProvider);
  end;
  Drop(ASelection);
  if not Ok then
  begin
    AInternal.Free;
    raise EPMLVideoError.Create('the video backend refused to set the selection');
  end;
  if Assigned(AProvider) then
  begin
    FSel[ASelection].Owner := True;
    FSel[ASelection].Provider := AProvider;
    FSel[ASelection].MimeTypes := Copy(AMimeTypes);
    FSel[ASelection].Internal := AInternal;
  end;
  PushUpdate(ASelection, True, AMimeTypes);
end;

procedure TPMLClipboard.PushUpdate(ASelection: TPMLClipboardSelection; AOwner: Boolean;
  const AMimeTypes: TStringArray);
var
  Ev: TPMLEvent;
begin
  FillChar(Ev.Clipboard, SizeOf(Ev.Clipboard), 0);
  Ev.Kind := TPMLEventKind.ClipboardUpdate;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := 0;
  Ev.Text := '';
  Ev.Segments := nil;
  Ev.Strings := Copy(AMimeTypes);
  Ev.Clipboard.Owner := AOwner;
  Ev.Clipboard.PrimarySelection := ASelection = TPMLClipboardSelection.Primary;
  FQueue.Push(Ev);
end;

function TPMLClipboard.HasMime(ASelection: TPMLClipboardSelection;
  const AMimeType: String): Boolean;
begin
  if FSel[ASelection].Owner then
    Result := Contains(FSel[ASelection].MimeTypes, AMimeType)
  else if Assigned(FBackend) and FBackend.SupportsSelection(ASelection) then
    Result := Contains(FBackend.OfferedMimeTypes(ASelection), AMimeType)
  else
    Result := False;
end;

function TPMLClipboard.ReadData(ASelection: TPMLClipboardSelection;
  const AMimeType: String; out AData: TBytes): Boolean;
begin
  AData := nil;
  Result := False;
  if not HasMime(ASelection, AMimeType) then
    Exit;
  if FSel[ASelection].Owner then
    Result := FSel[ASelection].Provider.GetClipboardData(AMimeType, AData)
  else
    Result := FBackend.ReceiveOffer(ASelection, AMimeType, AData);
  if not Result then
    AData := nil;
end;

function TextMimes(ABackend: TPMLClipboardBackend): TStringArray;
begin
  if Assigned(ABackend) then
    Result := ABackend.TextMimeTypes
  else
    Result := ['text/plain;charset=utf-8'];
end;

function TPMLClipboard.ReadText(ASelection: TPMLClipboardSelection): String;
var
  M: String;
  D: TBytes;
begin
  for M in TextMimes(FBackend) do
    if ReadData(ASelection, M, D) then
      Exit(BytesToString(D));
  Result := '';
end;

function TPMLClipboard.HasTextIn(ASelection: TPMLClipboardSelection): Boolean;
var
  M: String;
begin
  for M in TextMimes(FBackend) do
    if HasMime(ASelection, M) then
      Exit(True);
  Result := False;
end;

procedure TPMLClipboard.PlaceText(ASelection: TPMLClipboardSelection; const AText: String);
var
  P: TPMLTextClipboardProvider;
begin
  if AText = '' then
  begin
    Place(ASelection, nil, nil, nil);
    Exit;
  end;
  P := TPMLTextClipboardProvider.Create(AText);
  Place(ASelection, TextMimes(FBackend), P as IPMLClipboardDataProvider, P);
end;

procedure TPMLClipboard.SetData(const AMimeTypes: array of String;
  AProvider: IPMLClipboardDataProvider);
var
  L: TStringArray;
  I: Integer;
begin
  if (Length(AMimeTypes) = 0) or (AProvider = nil) then
    raise EPMLArgument.Create('SetData needs at least one MIME type and a provider (use Clear to empty)');
  SetLength(L, Length(AMimeTypes));
  for I := 0 to High(AMimeTypes) do
  begin
    if AMimeTypes[I] = '' then
      raise EPMLArgument.Create('SetData: empty MIME type');
    L[I] := AMimeTypes[I];
  end;
  Place(TPMLClipboardSelection.Clipboard, L, AProvider, nil);
end;

procedure TPMLClipboard.Clear;
begin
  Place(TPMLClipboardSelection.Clipboard, nil, nil, nil);
end;

function TPMLClipboard.GetData(const AMimeType: String; out AData: TBytes): Boolean;
begin
  CheckMainThread;
  Result := ReadData(TPMLClipboardSelection.Clipboard, AMimeType, AData);
end;

function TPMLClipboard.HasData(const AMimeType: String): Boolean;
begin
  Result := HasMime(TPMLClipboardSelection.Clipboard, AMimeType);
end;

function TPMLClipboard.MimeTypes: TStringArray;
begin
  if FSel[TPMLClipboardSelection.Clipboard].Owner then
    Result := Copy(FSel[TPMLClipboardSelection.Clipboard].MimeTypes)
  else if Assigned(FBackend) then
    Result := FBackend.OfferedMimeTypes(TPMLClipboardSelection.Clipboard)
  else
    Result := nil;
end;

function TPMLClipboard.HasText: Boolean;
begin
  Result := HasTextIn(TPMLClipboardSelection.Clipboard);
end;

function TPMLClipboard.GetText: String;
begin
  CheckMainThread;
  Result := ReadText(TPMLClipboardSelection.Clipboard);
end;

procedure TPMLClipboard.SetText(const AValue: String);
begin
  PlaceText(TPMLClipboardSelection.Clipboard, AValue);
end;

function TPMLClipboard.GetOwner: Boolean;
begin
  Result := FSel[TPMLClipboardSelection.Clipboard].Owner;
end;

function TPMLClipboard.HasPrimarySelectionText: Boolean;
begin
  Result := HasTextIn(TPMLClipboardSelection.Primary);
end;

function TPMLClipboard.GetPrimarySelectionText: String;
begin
  CheckMainThread;
  Result := ReadText(TPMLClipboardSelection.Primary);
end;

procedure TPMLClipboard.SetPrimarySelectionText(const AValue: String);
begin
  PlaceText(TPMLClipboardSelection.Primary, AValue);
end;

function TPMLClipboard.GetPrimaryAvailable: Boolean;
begin
  Result := not Assigned(FBackend) or FBackend.SupportsSelection(TPMLClipboardSelection.Primary);
end;

procedure TPMLClipboard.ClipboardOwnershipLost(ASelection: TPMLClipboardSelection);
begin
  if FSel[ASelection].Owner then
    Drop(ASelection);
end;

procedure TPMLClipboard.ClipboardOffered(ASelection: TPMLClipboardSelection;
  const AMimeTypes: TStringArray);
begin
  // 他のアプリが選択を取った。こちらのデータはもう配られない。
  if FSel[ASelection].Owner then
    Drop(ASelection);
  PushUpdate(ASelection, False, AMimeTypes);
end;

end.
