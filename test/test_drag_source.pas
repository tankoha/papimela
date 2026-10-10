{
  test_drag_source — ドラッグを始める側（TPMLClipboard.StartDrag）の約束を表示サーバ無しで検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. ダミーのビデオ（部品が無い）: DragAvailable は False、StartDrag は EPMLUnsupported
    2. 偽の部品: 引数の検査、部品に渡すもの（ウィンドウ、MIME タイプ、提供者、操作、絵）、
       ドラッグ中の 2 度目は False、部品が断れば False で提供者に触れない、
       終わりの知らせ（DragEnd を積んでから提供者に ClipboardDataCancelled を 1 回）、
       重ねて来た終わりの知らせは捨てる、CancelDrag（部品が知らせなくても終わる）、
       DragEnd を切っても提供者には知らせる、クリップボードの選択と独立、
       Context を壊すとドラッグ中の提供者に知らせる、終わりの知らせの中から次を始められる

  WHY:
    ドラッグを始めるのは papimela 独自の API（SDL には無い）。Wayland の部品（#38）は
    実機のポインタの操作が要るので、公開窓口の約束はここで固める。

  実行前提: 無し。
}
program test_drag_source;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Events,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Dummy,
  PaPiMeLa.Clipboard,
  PaPiMeLa.Core;

type
  { アプリの提供者。知らされた回数と、知らされたときの様子を覚える。 }
  TProvider = class(TObject, IPMLClipboardDataProvider)
  public
    Cancelled     : Integer;
    SawDragEnd    : Boolean;   // 知らされたとき、DragEnd がもう積まれていたか
    SawDragging   : Boolean;   // 知らされたとき、まだ IsDragging だったか
    RestartOnCancel: Boolean;  // 知らされたら、もう一度 StartDrag する
    RestartResult : Boolean;
    function  GetClipboardData(const AMimeType: String; out AData: TBytes): Boolean;
    procedure ClipboardDataCancelled;
  end;

  { 偽のクリップボード部品。ドラッグの開始と終わりを思いどおりに作る。 }
  TFakeClipboard = class(TPMLClipboardBackend)
  public
    NoDrag      : Boolean;     // SupportsDrag を False にする
    RefuseDrag  : Boolean;     // StartDrag を False にする
    SilentCancel: Boolean;     // CancelDrag で DragEnded を呼ばない（行儀の悪い部品）
    DragCalls   : Integer;
    CancelCalls : Integer;
    Dragging    : Boolean;
    LastWindow  : TPMLWindowID;
    LastMimes   : TStringArray;
    LastProvider: IPMLClipboardDataProvider;
    LastActions : TPMLDragActions;
    LastIcon    : TPMLDragIcon;
    function  SupportsSelection(ASelection: TPMLClipboardSelection): Boolean; override;
    function  SetSelection(ASelection: TPMLClipboardSelection; const AMimeTypes: TStringArray;
      AProvider: IPMLClipboardDataProvider): Boolean; override;
    function  OfferedMimeTypes(ASelection: TPMLClipboardSelection): TStringArray; override;
    function  ReceiveOffer(ASelection: TPMLClipboardSelection; const AMimeType: String;
      out AData: TBytes): Boolean; override;
    function  SupportsDrag: Boolean; override;
    function  StartDrag(AWindowID: TPMLWindowID; const AMimeTypes: TStringArray;
      AProvider: IPMLClipboardDataProvider; AActions: TPMLDragActions;
      const AIcon: TPMLDragIcon): Boolean; override;
    procedure CancelDrag; override;
    // 落とし先とのやり取りが終わったことにする。
    procedure Finish(ADropped: Boolean; AAction: TPMLDragAction);
  end;

  TFakeClipVideo = class(TPMLDummyVideoBackend)
  public
    function BackendName: String; override;
    function Connect(ASink: IPMLVideoSink): Boolean; override;
    destructor Destroy; override;
  end;

var
  Failures: Integer = 0;
  Fake    : TFakeClipboard = nil;
  Ctx     : TPMLContext = nil;

function TProvider.GetClipboardData(const AMimeType: String; out AData: TBytes): Boolean;
begin
  SetLength(AData, 1);
  AData[0] := Ord('x');
  Result := True;
end;

procedure TProvider.ClipboardDataCancelled;
begin
  Inc(Cancelled);
  // Context を壊している最中（FreeAndNil は先に nil にする）は、数えるだけ。
  if Ctx = nil then
    Exit;
  SawDragEnd := Ctx.Events.Peek(TPMLEventKind.DragEnd);
  SawDragging := Ctx.Video.Clipboard.IsDragging;
  if RestartOnCancel then
  begin
    RestartOnCancel := False;
    RestartResult := Ctx.Video.Clipboard.StartDrag(7, ['text/plain'], Self);
  end;
end;

function TFakeClipboard.SupportsSelection(ASelection: TPMLClipboardSelection): Boolean;
begin
  Result := True;
end;

function TFakeClipboard.SetSelection(ASelection: TPMLClipboardSelection;
  const AMimeTypes: TStringArray; AProvider: IPMLClipboardDataProvider): Boolean;
begin
  Result := True;
end;

function TFakeClipboard.OfferedMimeTypes(ASelection: TPMLClipboardSelection): TStringArray;
begin
  Result := nil;
end;

function TFakeClipboard.ReceiveOffer(ASelection: TPMLClipboardSelection;
  const AMimeType: String; out AData: TBytes): Boolean;
begin
  AData := nil;
  Result := False;
end;

function TFakeClipboard.SupportsDrag: Boolean;
begin
  Result := not NoDrag;
end;

function TFakeClipboard.StartDrag(AWindowID: TPMLWindowID; const AMimeTypes: TStringArray;
  AProvider: IPMLClipboardDataProvider; AActions: TPMLDragActions;
  const AIcon: TPMLDragIcon): Boolean;
begin
  Inc(DragCalls);
  LastWindow := AWindowID;
  LastMimes := Copy(AMimeTypes);
  LastProvider := AProvider;
  LastActions := AActions;
  LastIcon := AIcon;
  LastIcon.Pixels := Copy(AIcon.Pixels);
  Result := not RefuseDrag;
  Dragging := Result;
end;

procedure TFakeClipboard.CancelDrag;
begin
  Inc(CancelCalls);
  if not Dragging then
    Exit;
  Dragging := False;
  if not SilentCancel then
    FSink.DragEnded(False, TPMLDragAction.Copy);
end;

procedure TFakeClipboard.Finish(ADropped: Boolean; AAction: TPMLDragAction);
begin
  Dragging := False;
  FSink.DragEnded(ADropped, AAction);
end;

function TFakeClipVideo.BackendName: String;
begin
  Result := 'fake-drag';
end;

function TFakeClipVideo.Connect(ASink: IPMLVideoSink): Boolean;
begin
  Result := inherited Connect(ASink);
  Fake := TFakeClipboard.Create(ContextRef, Self);
  FClipboard := Fake;
end;

destructor TFakeClipVideo.Destroy;
begin
  FreeAndNil(FClipboard);
  Fake := nil;
  inherited Destroy;
end;

function MakeFakeDrag(AContextRef: TObject; AOwner: TPMLObject;
  AQueue: TPMLEventQueue): TPMLVideoBackend;
begin
  Result := TFakeClipVideo.Create(AContextRef, AOwner);
end;

procedure Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
    WriteLn('  [PASS] ', ALabel)
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(Failures);
  end;
end;

function NewContext(const AVideo: String): TPMLContext;
var
  Opts: TPMLContextOptions;
begin
  Opts := TPMLContextOptions.Default;
  Opts.PreferredVideo := AVideo;
  Result := TPMLContext.Create([TPMLSubsystem.Video], Opts);
end;

function Join(const A: TStringArray): String;
var
  S: String;
begin
  Result := '';
  for S in A do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + S;
  end;
end;

{ 積まれた DragEnd を「窓:落とした:操作」の並びにする。他のイベントは捨てる。 }
function TakeDragEnds: String;
var
  Ev: TPMLEvent;
begin
  Result := '';
  while Ctx.Events.Poll(Ev) do
    if Ev.Kind = TPMLEventKind.DragEnd then
    begin
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + Format('%d:%s:%d', [Ev.WindowID, BoolToStr(Ev.Drag.Dropped, 'T', 'F'),
        Ord(Ev.Drag.Action)]);
    end;
end;

procedure TestDummy;
var
  P: TProvider;
  Raised: Boolean;
begin
  WriteLn('1. ダミーのビデオ（部品が無い）');
  P := TProvider.Create;
  Ctx := NewContext('dummy');
  try
    Check(not Ctx.Video.Clipboard.DragAvailable, 'DragAvailable は False');
    Raised := False;
    try
      Ctx.Video.Clipboard.StartDrag(1, ['text/plain'], P);
    except
      on E: EPMLUnsupported do
        Raised := True;
    end;
    Check(Raised, 'StartDrag は EPMLUnsupported');
    Ctx.Video.Clipboard.CancelDrag;
    Check(not Ctx.Video.Clipboard.IsDragging and (P.Cancelled = 0),
      'ドラッグ中でなく、CancelDrag は何もしない');
  finally
    FreeAndNil(Ctx);
    P.Free;
  end;
  WriteLn;
end;

procedure TestStartAndEnd;
var
  C: TPMLClipboard;
  P: TProvider;
  O: TPMLDragOptions;
  D: TBytes;
  S: String;

  function RaisesArg(AWindow: TPMLWindowID; const AMimes: array of String;
    AProv: IPMLClipboardDataProvider; const AOpts: TPMLDragOptions): Boolean;
  begin
    Result := False;
    try
      C.StartDrag(AWindow, AMimes, AProv, AOpts);
    except
      on E: EPMLArgument do
        Result := True;
    end;
  end;

begin
  WriteLn('2. 偽の部品: 始める・終わる');
  P := TProvider.Create;
  Ctx := NewContext('fake-drag');
  try
    C := Ctx.Video.Clipboard;
    Check(C.DragAvailable, 'DragAvailable は True（部品が SupportsDrag）');
    O := TPMLDragOptions.Default;
    Check((O.Actions = [TPMLDragAction.Copy]) and (O.Icon = nil), '既定の選び方は Copy だけ・絵なし');

    Check(RaisesArg(0, ['text/plain'], P, O), 'ウィンドウ 0 は EPMLArgument');
    Check(RaisesArg(1, [], P, O), 'MIME タイプが無いのは EPMLArgument');
    Check(RaisesArg(1, ['text/plain', ''], P, O), '空の名前の MIME タイプは EPMLArgument');
    Check(RaisesArg(1, ['text/plain'], nil, O), '提供者が nil は EPMLArgument');
    O.Actions := [];
    Check(RaisesArg(1, ['text/plain'], P, O), '操作が空は EPMLArgument');
    Check((Fake.DragCalls = 0) and not C.IsDragging, '引数の誤りでは部品を呼ばない');

    Check(C.StartDrag(3, ['text/uri-list', 'text/plain'], P), '始められる');
    Check((Fake.DragCalls = 1) and (Fake.LastWindow = 3)
      and (Join(Fake.LastMimes) = 'text/uri-list,text/plain')
      and (Fake.LastProvider = IPMLClipboardDataProvider(P))
      and (Fake.LastActions = [TPMLDragAction.Copy]) and (Fake.LastIcon.Width = 0),
      Format('部品にウィンドウ・MIME タイプ（順のまま）・提供者・既定の操作を渡し、絵は無い（%s）',
        [Join(Fake.LastMimes)]));
    Check(C.IsDragging, 'IsDragging');
    Check(Fake.LastProvider.GetClipboardData('text/plain', D) and (Length(D) = 1),
      '部品は借りた提供者からデータを読める');
    Check(not C.StartDrag(4, ['text/plain'], P) and (Fake.DragCalls = 1),
      'ドラッグ中にもう一度始めると False で、部品は呼ばない');
    Check(P.Cancelled = 0, '終わるまで提供者には知らせない');

    Fake.Finish(True, TPMLDragAction.Move);
    Check(P.Cancelled = 1, '終わると提供者に 1 回知らせる');
    Check(P.SawDragEnd, '知らせる時には DragEnd がもう積まれている');
    Check(not P.SawDragging, '知らせる時には IsDragging はもう False');
    S := TakeDragEnds;
    Check(S = '3:T:1', 'DragEnd に始めたウィンドウ、落とした、決まった操作（Move）が載る（' + S + '）');
    Check(not C.IsDragging, '終わると IsDragging は False');

    Fake.Finish(True, TPMLDragAction.Copy);
    S := TakeDragEnds;
    Check((S = '') and (P.Cancelled = 1), '重ねて来た終わりの知らせは捨てる（' + S + '）');

    Check(C.StartDrag(5, ['text/plain'], P), 'もう一度始められる');
    Fake.Finish(False, TPMLDragAction.Move);
    S := TakeDragEnds;
    Check((S = '5:F:0') and (P.Cancelled = 2),
      '落とされなければ Dropped は False、操作は Copy に揃える（' + S + '）');

    Fake.RefuseDrag := True;
    Check(not C.StartDrag(6, ['text/plain'], P), '部品が断れば False');
    Check(not C.IsDragging and (P.Cancelled = 2) and (TakeDragEnds = ''),
      '断られたら、ドラッグ中にならず、提供者にも知らせず、DragEnd も無い');
    Fake.RefuseDrag := False;

    Fake.NoDrag := True;
    Check(not C.DragAvailable, '部品が SupportsDrag でなければ DragAvailable は False');
    try
      C.StartDrag(6, ['text/plain'], P);
      Check(False, 'SupportsDrag でない部品で StartDrag は EPMLUnsupported');
    except
      on E: EPMLUnsupported do
        Check(Fake.DragCalls = 3, 'SupportsDrag でない部品で StartDrag は EPMLUnsupported（部品は呼ばない）');
    end;
    Fake.NoDrag := False;
  finally
    FreeAndNil(Ctx);
    P.Free;
  end;
  WriteLn;
end;

procedure TestCancelAndOptions;
var
  C: TPMLClipboard;
  P, Q: TProvider;
  O: TPMLDragOptions;
  Icon: TPMLSurface;
  S: String;
begin
  WriteLn('3. 偽の部品: 取り消し・選び方・クリップボードとの関係');
  P := TProvider.Create;
  Q := TProvider.Create;
  Ctx := NewContext('fake-drag');
  try
    C := Ctx.Video.Clipboard;

    Check(C.StartDrag(2, ['text/plain'], P), '始める');
    C.CancelDrag;
    S := TakeDragEnds;
    Check((Fake.CancelCalls = 1) and (S = '2:F:0') and (P.Cancelled = 1) and not C.IsDragging,
      'CancelDrag は部品を取り消し、DragEnd（落とされない）を 1 つ積み、提供者に知らせる（' + S + '）');
    C.CancelDrag;
    Check((Fake.CancelCalls = 1) and (P.Cancelled = 1), 'ドラッグ中でなければ CancelDrag は何もしない');

    Fake.SilentCancel := True;
    Check(C.StartDrag(2, ['text/plain'], P), '始める（知らせない部品）');
    C.CancelDrag;
    S := TakeDragEnds;
    Check((S = '2:F:0') and (P.Cancelled = 2) and not C.IsDragging,
      '部品が知らせなくても、CancelDrag で終わる（' + S + '）');
    Fake.Finish(False, TPMLDragAction.Copy);
    Check((TakeDragEnds = '') and (P.Cancelled = 2), 'そのあと遅れて来た知らせは捨てる');
    Fake.SilentCancel := False;

    Icon := TPMLSurface.Create(3, 2, PML_PIXELFORMAT_ARGB8888);
    try
      Icon.WritePixel(0, 0, TPMLColor.Make(255, 0, 0, 255));
      Icon.WritePixel(1, 0, TPMLColor.Make(0, 255, 0, 128));
      Icon.WritePixel(2, 0, TPMLColor.Make(0, 0, 255, 0));
      Icon.WritePixel(0, 1, TPMLColor.Make(10, 20, 30, 40));
      Icon.WritePixel(1, 1, TPMLColor.Make(200, 100, 50, 255));
      Icon.WritePixel(2, 1, TPMLColor.Make(1, 2, 3, 4));
      O := TPMLDragOptions.Default;
      O.Actions := [TPMLDragAction.Copy, TPMLDragAction.Move];
      O.Icon := Icon;
      O.HotX := 1;
      O.HotY := 2;
      Check(C.StartDrag(9, ['text/plain'], P, O), '絵と操作を指定して始める');
    finally
      Icon.Free;   // 写したはずなので、すぐ捨ててよい
    end;
    Check(Fake.LastActions = [TPMLDragAction.Copy, TPMLDragAction.Move], '操作をそのまま渡す');
    Check((Fake.LastIcon.Width = 3) and (Fake.LastIcon.Height = 2) and (Fake.LastIcon.HotX = 1)
      and (Fake.LastIcon.HotY = 2) and (Length(Fake.LastIcon.Pixels) = 6),
      '絵の大きさと先の位置を渡す');
    Check((Length(Fake.LastIcon.Pixels) = 6)
      and (Fake.LastIcon.Pixels[0] = $FFFF0000) and (Fake.LastIcon.Pixels[1] = $8000FF00)
      and (Fake.LastIcon.Pixels[2] = $000000FF) and (Fake.LastIcon.Pixels[3] = $280A141E)
      and (Fake.LastIcon.Pixels[4] = $FFC86432) and (Fake.LastIcon.Pixels[5] = $04010203),
      '絵の画素は ARGB8888 の行の順で、アルファを掛けない');

    // ドラッグ中のクリップボードの操作は、ドラッグの提供者に触れない。
    C.SetData(['text/plain'], Q);
    C.Clear;
    Check((Q.Cancelled = 1) and (P.Cancelled = 2) and C.IsDragging,
      'クリップボードを消しても、ドラッグの提供者には知らせない');
    C.SetData(['text/plain'], P);
    Fake.Finish(True, TPMLDragAction.Copy);
    Check((P.Cancelled = 3) and C.IsOwner, 'ドラッグが終わっても、クリップボードは持ったまま');
    C.Clear;
    Check(P.Cancelled = 4, '同じ提供者でも、クリップボードとドラッグでそれぞれ 1 回知らせる');
    TakeDragEnds;

    Ctx.Events.SetEnabled(TPMLEventKind.DragEnd, False);
    Check(C.StartDrag(2, ['text/plain'], P), '始める（DragEnd を切って）');
    Fake.Finish(True, TPMLDragAction.Copy);
    Check((TakeDragEnds = '') and (P.Cancelled = 5),
      'DragEnd を切っても、提供者には知らせる');
    Ctx.Events.SetEnabled(TPMLEventKind.DragEnd, True);

    P.RestartOnCancel := True;
    Check(C.StartDrag(2, ['text/plain'], P), '始める（知らせの中で次を始める提供者）');
    Fake.Finish(True, TPMLDragAction.Copy);
    Check(P.RestartResult and C.IsDragging and (Fake.LastWindow = 7),
      '終わりの知らせの中から次のドラッグを始められる');

    Check(C.IsDragging, 'ドラッグ中のまま Context を壊す');
    S := IntToStr(P.Cancelled);
  finally
    FreeAndNil(Ctx);
  end;
  Check(P.Cancelled = StrToInt(S) + 1, 'Context を壊すと、ドラッグ中の提供者に 1 回知らせる');
  P.Free;
  Q.Free;
  WriteLn;
end;

begin
  WriteLn('test_drag_source — ドラッグを始める側の約束');
  WriteLn;
  PMLRegisterVideoBackend('fake-drag', -10, @MakeFakeDrag);
  TestDummy;
  TestStartAndEnd;
  TestCancelAndOptions;
  if Failures = 0 then
    WriteLn('=== 結論: ドラッグを始める側が papimela の約束どおりに動く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
