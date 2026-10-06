{
  test_clipboard — クリップボードの公開窓口を表示サーバ無しで検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. ダミーのビデオ（クリップボードの部品が無い）で、プロセスの中だけで持つ
       クリップボードとプライマリ選択の振る舞い
    2. 偽の部品を持つビデオで、公開窓口と部品の約束: 置くと部品が提供者を借りる、
       他のアプリの選択が見えたら提供者を手放して ClipboardUpdate を積む、
       持ち主でないときは部品から読む、配っていない MIME タイプは読みに行かない、
       部品が断ったら例外、プライマリ選択の無い部品

  WHY:
    Wayland の部品（#38）は実機のコンポジタが要る。公開窓口の約束はここで
    固めておき、部品はこの約束どおりに書く。

  実行前提: 無し。
}
program test_clipboard;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Events,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Dummy,
  PaPiMeLa.Clipboard,
  PaPiMeLa.Core;

type
  { アプリの提供者。呼ばれた回数を数える。 }
  TProvider = class(TObject, IPMLClipboardDataProvider)
  public
    Asked    : String;
    Cancelled: Integer;
    Refuse   : Boolean;
    function  GetClipboardData(const AMimeType: String; out AData: TBytes): Boolean;
    procedure ClipboardDataCancelled;
  end;

  { 偽のクリップボード部品。他のアプリの選択を思いどおりに作る。 }
  TFakeClipboard = class(TPMLClipboardBackend)
  public
    SetCalls   : Integer;
    LastMimes  : TStringArray;
    LastProvider: IPMLClipboardDataProvider;
    Offered    : TStringArray;
    Received   : String;
    RefuseSet  : Boolean;
    function  SupportsSelection(ASelection: TPMLClipboardSelection): Boolean; override;
    function  SetSelection(ASelection: TPMLClipboardSelection; const AMimeTypes: TStringArray;
      AProvider: IPMLClipboardDataProvider): Boolean; override;
    function  OfferedMimeTypes(ASelection: TPMLClipboardSelection): TStringArray; override;
    function  ReceiveOffer(ASelection: TPMLClipboardSelection; const AMimeType: String;
      out AData: TBytes): Boolean; override;
    function  TextMimeTypes: TStringArray; override;
    // 他のアプリが選択を取ったことにする。
    procedure Offer(const AMimes: TStringArray);
    procedure Lose;
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

function TProvider.GetClipboardData(const AMimeType: String; out AData: TBytes): Boolean;
var
  S: String;
begin
  Asked := Asked + AMimeType + ';';
  Result := not Refuse;
  S := 'data for ' + AMimeType;
  SetLength(AData, Length(S));
  Move(S[1], AData[0], Length(S));
end;

procedure TProvider.ClipboardDataCancelled;
begin
  Inc(Cancelled);
end;

function TFakeClipboard.SupportsSelection(ASelection: TPMLClipboardSelection): Boolean;
begin
  Result := ASelection = TPMLClipboardSelection.Clipboard;
end;

function TFakeClipboard.SetSelection(ASelection: TPMLClipboardSelection;
  const AMimeTypes: TStringArray; AProvider: IPMLClipboardDataProvider): Boolean;
begin
  Inc(SetCalls);
  LastMimes := AMimeTypes;
  LastProvider := AProvider;
  Result := not RefuseSet;
end;

function TFakeClipboard.OfferedMimeTypes(ASelection: TPMLClipboardSelection): TStringArray;
begin
  Result := Offered;
end;

function TFakeClipboard.ReceiveOffer(ASelection: TPMLClipboardSelection;
  const AMimeType: String; out AData: TBytes): Boolean;
var
  S: String;
begin
  Received := Received + AMimeType + ';';
  S := 'outside ' + AMimeType;
  SetLength(AData, Length(S));
  Move(S[1], AData[0], Length(S));
  Result := True;
end;

function TFakeClipboard.TextMimeTypes: TStringArray;
begin
  Result := ['text/plain;charset=utf-8', 'UTF8_STRING', 'text/plain'];
end;

procedure TFakeClipboard.Offer(const AMimes: TStringArray);
begin
  Offered := AMimes;
  FSink.ClipboardOffered(TPMLClipboardSelection.Clipboard, AMimes);
end;

procedure TFakeClipboard.Lose;
begin
  Offered := nil;
  FSink.ClipboardOwnershipLost(TPMLClipboardSelection.Clipboard);
end;

function TFakeClipVideo.BackendName: String;
begin
  Result := 'fake-clip';
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

function MakeFakeClip(AContextRef: TObject; AOwner: TPMLObject;
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

function Join(const A: TStringArray): String;
begin
  Result := String.Join(',', A);
end;

function AsString(const D: TBytes): String;
begin
  SetLength(Result, Length(D));
  if Length(D) > 0 then
    Move(D[0], Result[1], Length(D));
end;

{ 積まれた ClipboardUpdate を「o|p:mime,mime」の並びにする（o = 持ち主、x = 他、p = プライマリ）。 }
function Updates(Ctx: TPMLContext): String;
var
  Ev: TPMLEvent;
begin
  Result := '';
  Ctx.Events.Pump(0);
  while Ctx.Events.Poll(Ev) do
    if Ev.Kind = TPMLEventKind.ClipboardUpdate then
    begin
      if Ev.Clipboard.Owner then Result := Result + 'o' else Result := Result + 'x';
      if Ev.Clipboard.PrimarySelection then Result := Result + 'p';
      Result := Result + ':' + Join(Ev.Strings) + ' ';
    end;
  Result := Trim(Result);
end;

function NewContext(const AVideo: String): TPMLContext;
var
  Opts: TPMLContextOptions;
begin
  Opts := TPMLContextOptions.Default;
  Opts.PreferredVideo := AVideo;
  Result := TPMLContext.Create([TPMLSubsystem.Video], Opts);
end;

procedure TestInternal;
var
  Ctx: TPMLContext;
  C  : TPMLClipboard;
  P, Q: TProvider;
  D  : TBytes;
  Raised: Boolean;
  U  : String;
begin
  WriteLn('1. 部品の無いビデオ（ダミー）: プロセスの中だけで持つ');
  P := TProvider.Create;
  Q := TProvider.Create;
  Ctx := NewContext('dummy');
  try
    C := Ctx.Video.Clipboard;
    Check(C <> nil, 'Video.Clipboard がある');
    Check(not C.HasText and (C.Text = '') and (Length(C.MimeTypes) = 0) and not C.IsOwner,
      '最初は空');

    C.Text := 'こんにちは';
    U := Updates(Ctx);
    Check(U = 'o:text/plain;charset=utf-8', '置くと ClipboardUpdate（持ち主、UTF-8 の text/plain）: ' + U);
    Check(C.HasText and (C.Text = 'こんにちは') and C.IsOwner, '読み戻せる');
    Check(C.GetData('text/plain;charset=utf-8', D) and (AsString(D) = 'こんにちは'),
      'GetData でもバイト列で読める');
    Check(not C.GetData('image/png', D) and (Length(D) = 0) and not C.HasData('image/png'),
      '配っていない MIME タイプは無い');

    C.Text := '';
    U := Updates(Ctx);
    Check(not C.HasText and (C.Text = '') and not C.IsOwner, '空文字列を置くと消える');
    Check(U = 'o:', '消したときも ClipboardUpdate（MIME タイプなし）: ' + U);

    WriteLn;
    WriteLn('2. 任意の MIME タイプ');
    C.SetData(['application/x-papimela', 'text/plain'], P);
    Updates(Ctx);
    Check(Join(C.MimeTypes) = 'application/x-papimela,text/plain', 'MimeTypes は置いたもの');
    Check(C.HasData('text/plain') and C.HasData('application/x-papimela'), 'HasData');
    Check(C.GetData('application/x-papimela', D) and (AsString(D) = 'data for application/x-papimela'),
      '提供者から読む');
    P.Asked := '';
    Check(not C.GetData('application/x-other', D) and (P.Asked = ''),
      '配っていない MIME タイプでは提供者を呼ばない');
    Check(not C.HasText and (C.Text = '') and (P.Asked = ''),
      '文字列の MIME タイプ（UTF-8 の text/plain）を配っていなければ Text は空');
    P.Refuse := True;
    Check(not C.GetData('text/plain', D) and (Length(D) = 0), '提供者が断れば False');
    P.Refuse := False;

    WriteLn;
    WriteLn('3. 置き換え・消去で提供者に 1 回だけ知らせる');
    C.SetData(['text/plain'], Q);
    Check((P.Cancelled = 1) and (Q.Cancelled = 0), '置き換えると古い提供者に ClipboardDataCancelled');
    C.Clear;
    Check((Q.Cancelled = 1) and not C.IsOwner and (Length(C.MimeTypes) = 0), 'Clear で今の提供者にも');
    C.Clear;
    Check((P.Cancelled = 1) and (Q.Cancelled = 1), '2 度消しても重ねて知らせない');

    Raised := False;
    try
      C.SetData([], P);
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    Check(Raised, 'MIME タイプが無ければ EPMLArgument');
    Raised := False;
    try
      C.SetData(['text/plain'], nil);
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    Check(Raised, '提供者が無ければ EPMLArgument');

    WriteLn;
    WriteLn('4. プライマリ選択はクリップボードと別');
    Updates(Ctx);
    Check(C.PrimarySelectionAvailable, '部品が無ければプライマリ選択も中で持つ');
    C.Text := 'clip';
    C.PrimarySelectionText := 'prim';
    U := Updates(Ctx);
    Check(U = 'o:text/plain;charset=utf-8 op:text/plain;charset=utf-8',
      'プライマリ選択の ClipboardUpdate は印が付く: ' + U);
    Check((C.Text = 'clip') and (C.PrimarySelectionText = 'prim') and C.HasPrimarySelectionText,
      'それぞれ読める');
    C.Clear;
    Check((C.PrimarySelectionText = 'prim') and not C.HasText, 'クリップボードを消してもプライマリ選択は残る');

    C.SetData(['text/plain'], P);
  finally
    Ctx.Free;
  end;
  Check(P.Cancelled = 2, '終了で置いたままの提供者にも知らせる');
  P.Free;
  Q.Free;
  WriteLn;
end;

procedure TestBackend;
var
  Ctx: TPMLContext;
  C  : TPMLClipboard;
  P  : TProvider;
  D  : TBytes;
  Raised: Boolean;
  U  : String;
begin
  WriteLn('5. 部品を持つビデオ: 置く');
  PMLRegisterVideoBackend('fake-clip', -10, @MakeFakeClip);
  P := TProvider.Create;
  Ctx := NewContext('fake-clip');
  try
    C := Ctx.Video.Clipboard;
    C.Text := 'x';
    Check((Fake.SetCalls = 1) and (Join(Fake.LastMimes) = 'text/plain;charset=utf-8,UTF8_STRING,text/plain'),
      '文字列は部品の TextMimeTypes の全部で配る');
    Check(Fake.LastProvider.GetClipboardData('UTF8_STRING', D) and (AsString(D) = 'x'),
      '部品は借りた提供者から読める（貼り付けを頼まれたとき）');
    Check(C.Text = 'x', '持ち主のときは部品を通さずに読む');
    Check(Fake.Received = '', '自分の選択を部品から受け取りに行かない');

    C.SetData(['application/x-a'], P);
    Updates(Ctx);

    WriteLn;
    WriteLn('6. 他のアプリが選択を取る');
    Fake.Offer(['text/plain', 'image/png']);
    U := Updates(Ctx);
    Check(P.Cancelled = 1, '提供者に ClipboardDataCancelled');
    Check(not C.IsOwner, '持ち主でなくなる');
    Check(U = 'x:text/plain,image/png', 'ClipboardUpdate（他のアプリ、相手の MIME タイプ）: ' + U);
    Check(Join(C.MimeTypes) = 'text/plain,image/png', 'MimeTypes は相手のもの');
    Check(C.HasData('image/png') and not C.HasData('application/x-a'), 'HasData は相手のもので答える');
    Check(C.GetData('image/png', D) and (AsString(D) = 'outside image/png'), '部品から受け取る');
    Fake.Received := '';
    Check(C.HasText and (C.Text = 'outside text/plain') and (Fake.Received = 'text/plain;'),
      'Text は TextMimeTypes の順に、相手が配っている最初のもの（text/plain）を受け取る');
    Fake.Received := '';
    Check(not C.GetData('application/x-a', D) and (Fake.Received = ''),
      '相手が配っていない MIME タイプは受け取りに行かない');

    Fake.Offer(nil);
    U := Updates(Ctx);
    Check((U = 'x:') and not C.HasText, '相手の選択が無くなったときも知らせる: ' + U);

    WriteLn;
    WriteLn('7. 持ち主でなくなったことだけが分かる（フォーカスが無い間）');
    P.Cancelled := 0;
    C.SetData(['application/x-a'], P);
    Updates(Ctx);
    Fake.Lose;
    U := Updates(Ctx);
    Check((P.Cancelled = 1) and not C.IsOwner and (U = ''),
      '提供者に知らせ、ClipboardUpdate は積まない（' + U + '）');

    WriteLn;
    WriteLn('8. 部品が断る・プライマリ選択が無い');
    Fake.RefuseSet := True;
    Raised := False;
    try
      C.Text := 'refused';
    except
      on E: EPMLVideoError do
        Raised := True;
    end;
    Check(Raised and not C.IsOwner, '部品が断れば EPMLVideoError で、持ち主にならない');
    Fake.RefuseSet := False;
    Check(not C.PrimarySelectionAvailable, 'プライマリ選択の無い部品');
    Raised := False;
    try
      C.PrimarySelectionText := 'p';
    except
      on E: EPMLUnsupported do
        Raised := True;
    end;
    Check(Raised, 'プライマリ選択に置くと EPMLUnsupported');
    Check(not C.HasPrimarySelectionText and (C.PrimarySelectionText = ''), '読むのは空で返る');

    C.Text := 'last';
    Fake.SetCalls := 0;
  finally
    Ctx.Free;
  end;
  Check(P.Cancelled = 1, '終了で（アプリの提供者は置いていないので）重ねて知らせない');
  P.Free;
  WriteLn;
end;

begin
  WriteLn('test_clipboard — クリップボードの公開窓口');
  WriteLn;
  TestInternal;
  TestBackend;
  if Failures = 0 then
    WriteLn('=== 結論: クリップボードの公開窓口が SDL の約束と papimela の部品の約束どおりに動く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
