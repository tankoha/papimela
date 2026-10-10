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
    - ドラッグを始める（StartDrag。papimela 独自）。状態はクリップボードの選択とは別に
      持つ。終わったら状態を空にし、DragEnd を積んでから提供者に 1 回知らせる（知らせの
      中から次の StartDrag を呼べる）。DragEnd を切っていても提供者には知らせる。
      CancelDrag・Context の破棄は、部品が DragEnded を呼ばなくても終わらせる
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
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Video.Backend;

type
  // 部品の約束（PaPiMeLa.Video.Backend）にある型を、公開層からも同じ名前で使えるようにする。
  // アンブレラ（uses PaPiMeLa）はこちらを並べ直す。
  TPMLClipboardSelection    = PaPiMeLa.Video.Backend.TPMLClipboardSelection;
  IPMLClipboardDataProvider = PaPiMeLa.Video.Backend.IPMLClipboardDataProvider;

  { StartDrag の選び方。
      Actions : 落とし先に許す操作。空は EPMLArgument
      Icon    : ドラッグ中にポインタに付ける絵。nil なら付けない。StartDrag の中で写すので、
                呼んだあとは捨ててよい
      HotX, HotY: ポインタの先が絵のどこに来るか（絵の左上からの画素） }
  TPMLDragOptions = record
    Actions   : TPMLDragActions;
    Icon      : TPMLSurface;
    HotX, HotY: Integer;
    // Actions = [Copy]、絵なし。
    class function Default: TPMLDragOptions; static;
  end;

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
    // ドラッグ（StartDrag）。クリップボードの選択とは別に持つ。
    FDragging   : Boolean;
    FDragWindow : TPMLWindowID;
    FDragProvider: IPMLClipboardDataProvider;
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
    function  GetDragAvailable: Boolean;
    procedure EndDragByCancel;
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

    // ---- ドラッグを始める（papimela 独自。SDL には無い）
    // AWindowID のウィンドウから、AMimeTypes を配るドラッグを始める。ポインタのボタンを
    // そのウィンドウで押している間（MouseButtonDown のあと、MouseButtonUp の前）に呼ぶ。
    // データは、落とし先が求めたときに AProvider.GetClipboardData で渡す（Pump の中から）。
    // 始まったら True。終わると DragEnd を積み、そのあと AProvider.ClipboardDataCancelled を
    // 1 回呼ぶ。始まらなければ False（ボタンが押されていない、ドラッグ中、など）で、
    // AProvider は呼ばない。
    // AWindowID = 0、MIME タイプが無い・空の名前、AProvider = nil、Actions が空は EPMLArgument。
    // DragAvailable が False なら EPMLUnsupported。
    function  StartDrag(AWindowID: TPMLWindowID; const AMimeTypes: array of String;
      AProvider: IPMLClipboardDataProvider): Boolean; overload;
    function  StartDrag(AWindowID: TPMLWindowID; const AMimeTypes: array of String;
      AProvider: IPMLClipboardDataProvider; const AOptions: TPMLDragOptions): Boolean; overload;
    // 始めたドラッグを取り消す（DragEnd の Dropped は False）。ドラッグ中でなければ何もしない。
    procedure CancelDrag;
    property  IsDragging: Boolean read FDragging;
    // ビデオのバックエンドがドラッグを始められるか（能力 DragAndDrop）。
    property  DragAvailable: Boolean read GetDragAvailable;

    // IPMLClipboardSink（部品が呼ぶ）
    procedure ClipboardOwnershipLost(ASelection: TPMLClipboardSelection);
    procedure ClipboardOffered(ASelection: TPMLClipboardSelection;
      const AMimeTypes: TStringArray);
    procedure DragEnded(ADropped: Boolean; AAction: TPMLDragAction);
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
  // ドラッグ中なら取り消し、提供者に知らせる（部品を外す前に）。
  EndDragByCancel;
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


{ ---- ドラッグ（StartDrag）----
  WHAT:
    ドラッグの状態（FDragging / FDragWindow / FDragProvider）はクリップボードの選択
    （FSel）とは別に持つ。同じ提供者を両方に使っても、それぞれ 1 回ずつ知らせる。

  WHY:
    終わりの知らせ（DragEnded）の中で、提供者がすぐ次の StartDrag を呼べるようにするため、
    状態を先に空にしてから DragEnd を積み、最後に提供者へ知らせる。 }

class function TPMLDragOptions.Default: TPMLDragOptions;
begin
  Result.Actions := [TPMLDragAction.Copy];
  Result.Icon := nil;
  Result.HotX := 0;
  Result.HotY := 0;
end;

function TPMLClipboard.GetDragAvailable: Boolean;
begin
  Result := Assigned(FBackend) and FBackend.SupportsDrag;
end;

{ 絵を部品に渡す形（ARGB8888、アルファを掛けない、行の詰め物なし）にする。
  どの形式の Surface でも受け、呼んだあとは Surface に触らない。 }
function SurfaceToDragIcon(ASurface: TPMLSurface; AHotX, AHotY: Integer): TPMLDragIcon;
var
  Src: TPMLSurface;
  Y: Integer;
begin
  Result.Width := 0;
  Result.Height := 0;
  Result.HotX := AHotX;
  Result.HotY := AHotY;
  Result.Pixels := nil;
  if (ASurface = nil) or (ASurface.Width <= 0) or (ASurface.Height <= 0) then
    Exit;
  if ASurface.Format = PML_PIXELFORMAT_ARGB8888 then
    Src := ASurface
  else
    Src := ASurface.Convert(PML_PIXELFORMAT_ARGB8888);
  try
    Result.Width := Src.Width;
    Result.Height := Src.Height;
    SetLength(Result.Pixels, Src.Width * Src.Height);
    // Pitch に詰め物があることがあるので、行ごとに写す。
    for Y := 0 to Src.Height - 1 do
      Move((PByte(Src.Pixels) + PtrUInt(Y) * PtrUInt(Src.Pitch))^,
        Result.Pixels[Y * Src.Width], Src.Width * SizeOf(LongWord));
  finally
    if Src <> ASurface then
      Src.Free;
  end;
end;

function TPMLClipboard.StartDrag(AWindowID: TPMLWindowID; const AMimeTypes: array of String;
  AProvider: IPMLClipboardDataProvider): Boolean;
begin
  Result := StartDrag(AWindowID, AMimeTypes, AProvider, TPMLDragOptions.Default);
end;

function TPMLClipboard.StartDrag(AWindowID: TPMLWindowID; const AMimeTypes: array of String;
  AProvider: IPMLClipboardDataProvider; const AOptions: TPMLDragOptions): Boolean;
var
  L: TStringArray;
  I: Integer;
  Icon: TPMLDragIcon;
begin
  CheckMainThread;
  if AWindowID = 0 then
    raise EPMLArgument.Create('StartDrag: window ID 0');
  if Length(AMimeTypes) = 0 then
    raise EPMLArgument.Create('StartDrag needs at least one MIME type');
  if AProvider = nil then
    raise EPMLArgument.Create('StartDrag needs a provider');
  if AOptions.Actions = [] then
    raise EPMLArgument.Create('StartDrag: Actions is empty');
  SetLength(L, Length(AMimeTypes));
  for I := 0 to High(AMimeTypes) do
  begin
    if AMimeTypes[I] = '' then
      raise EPMLArgument.Create('StartDrag: empty MIME type');
    L[I] := AMimeTypes[I];
  end;
  if not GetDragAvailable then
    raise EPMLUnsupported.Create('the video backend cannot start a drag');
  // ドラッグ中の 2 度目は、部品にも提供者にも触れずに False。
  if FDragging then
    Exit(False);
  Icon := SurfaceToDragIcon(AOptions.Icon, AOptions.HotX, AOptions.HotY);
  Result := FBackend.StartDrag(AWindowID, L, AProvider, AOptions.Actions, Icon);
  if Result then
  begin
    FDragging := True;
    FDragWindow := AWindowID;
    FDragProvider := AProvider;
  end;
end;

procedure TPMLClipboard.CancelDrag;
begin
  CheckMainThread;
  EndDragByCancel;
end;

{ 取り消し。部品が DragEnded を呼ばない（行儀の悪い）ときは、こちらで終わらせる。
  そのあとに遅れて来た DragEnded は、ドラッグ中でないので捨てられる。 }
procedure TPMLClipboard.EndDragByCancel;
begin
  if not FDragging then
    Exit;
  if Assigned(FBackend) then
    FBackend.CancelDrag;
  if FDragging then
    DragEnded(False, TPMLDragAction.Copy);
end;

procedure TPMLClipboard.DragEnded(ADropped: Boolean; AAction: TPMLDragAction);
var
  Old: IPMLClipboardDataProvider;
  Win: TPMLWindowID;
  Ev: TPMLEvent;
begin
  if not FDragging then
    Exit;
  Old := FDragProvider;
  Win := FDragWindow;
  // 状態を先に空にする。提供者が知らせの中で次の StartDrag を呼べるように。
  FDragging := False;
  FDragWindow := 0;
  FDragProvider := nil;

  Ev := Default(TPMLEvent);
  Ev.Kind := TPMLEventKind.DragEnd;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := Win;
  Ev.Drag.Dropped := ADropped;
  if ADropped then
    Ev.Drag.Action := AAction
  else
    Ev.Drag.Action := TPMLDragAction.Copy;
  // DragEnd を切っていても、キューが捨てるだけで提供者には知らせる。
  FQueue.Push(Ev);

  if Assigned(Old) then
    Old.ClipboardDataCancelled;
end;

end.
