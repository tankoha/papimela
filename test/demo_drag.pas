{
  demo_drag — ドラッグを始める側（TPMLClipboard.StartDrag）を実際の操作で確認する対話デモ

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    640x400 のウィンドウを開く。左半分は「ファイルのドラッグ」、右半分は「文字列のドラッグ」。
    マウスの左ボタンを押すとドラッグが始まる。求められたデータ（MIME タイプ）、DragEnd
    （Dropped / Action）、このウィンドウへ届いた Drop* イベントを 1 件ずつ出す。
    ウィンドウを閉じる・Escape・指定の秒数で、要約と wl_display_get_error を出して終わる。

  WHY:
    ドラッグを始めるにはポインタのボタンを押している間という実機の操作が要る
    （wl_data_device.start_drag は押下の serial を要求する）。test_drag_source は公開窓口の約束まで
    しか確かめられないので、コンポジタとの受け渡し（start_drag、絵、send、action、
    dnd_finished / cancelled）と、受け取る側（ファイルマネージャ、ブラウザ、ターミナル）との
    やり取りはここで実際に動かして確かめる。ウィンドウは落とし先にもなるので、自分への
    ドロップ（パイプを通すと止まる経路）が止まらないことも確かめられる。

  使い方:
    ./test/demo_drag [秒数] [ディレクトリ] [noportal]

      秒数        既定は 60 秒
      ディレクトリ 左半分のドラッグで配るファイルの置き場所（直下のファイルだけ）。
                  既定は /tmp/claude-1000/-home-joerg-claude-work/b534dfe0-bfc4-4322-ba2d-07ac88d7d39e/scratchpad/drop-test
      noportal    application/vnd.portal.filetransfer を配らない

    左半分（ファイル）は次の MIME タイプを配る。操作は Copy だけ。
      - text/uri-list                       ディレクトリの全ファイル（file:// の URI、CRLF 区切り）
      - text/plain                          同じ全ファイルのパス（1 行に 1 つ）
      - application/vnd.portal.filetransfer 最初の 1 ファイル（名前順）だけを入れた Documents
                                            ポータルの鍵。最初に求められたときに作り、DragEnd で捨てる
    右半分（文字列）は text/plain;charset=utf-8 と text/plain を配る（日本語を含む 2 行）。
    操作は Copy と Move。

    試すこと:
      1. 左半分を押したままウィンドウの外へ出し、ファイルマネージャへ落とす。
         ポータルを理解する受け手が 1 つだけ受け取れば、portal の枝を通った証拠になる
         （text/uri-list の枝なら全ファイルが届く）。noportal を付けると全ファイルが届く。
      2. 右半分を押したまま、ターミナルやテキストエディタへ落とす。2 行が入る。
      3. 押したままウィンドウの中で離す（自分への落とし）。DropBegin から DropComplete までの
         ミリ秒が出る。止まらず短ければ、パイプを通さず提供者から直接読めている。
      4. 落とさずに Escape（コンポジタの取り消し）や何も無い所で離す。DragEnd の Dropped が False。
      5. ドラッグ中に c キーは、フォーカスがドラッグ先に移っているので届かないことが多い。
         c は「ドラッグ中でないのに CancelDrag を呼んでも何も起きない」確認や、押した直後の
         取り消し（押す→すぐ c）に使う。
    Escape かウィンドウを閉じる操作で、秒数より前に終わる（ドラッグ中は届かない）。
}
program demo_drag;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Classes,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Events,
  PaPiMeLa.Platform.XKB,
  PaPiMeLa.Platform.DocumentPortal,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Clipboard,
  PaPiMeLa.Core;

const
  DEFAULT_DIR = '/tmp/claude-1000/-home-joerg-claude-work/b534dfe0-bfc4-4322-ba2d-07ac88d7d39e/scratchpad/drop-test';
  KEY_C = $63;

type
  { 配るデータ。左半分（ファイル）と右半分（文字列）で 1 つずつ作る。 }
  TDragProvider = class(TObject, IPMLClipboardDataProvider)
  public
    Name    : String;
    Paths   : TStringArray;     // ファイルのとき。空なら文字列
    Transfer: TPMLPortalFileTransfer;   // 最初に求められたときに作る
    Requests: Integer;
    Cancelled: Integer;
    function  GetClipboardData(const AMimeType: String; out AData: TBytes): Boolean;
    procedure ClipboardDataCancelled;
    procedure DropTransfer;
  end;

var
  Ctx     : TPMLContext;
  Win     : TPMLWindow;
  VB      : TPMLWaylandVideoBackend;
  Running : Boolean = True;
  Seconds : Integer = 60;
  Dir     : String = DEFAULT_DIR;
  NoPortal: Boolean = False;
  FileProv: TDragProvider;
  TextProv: TDragProvider;
  NStart, NRefused, NDragEnd, NDroppedTrue: Integer;
  NBegin, NFile, NText, NComplete: Integer;
  DropBeginNS: UInt64 = 0;
  MaxDropMs  : Int64 = 0;

function BytesOf(const S: String): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if Length(S) > 0 then
    Move(S[1], Result[0], Length(S));
end;

{ file:// の URI にする。予約文字以外はバイトごとに %XX。 }
function PathToURI(const APath: String): String;
var
  I: Integer;
  C: Char;
begin
  Result := 'file://';
  for I := 1 to Length(APath) do
  begin
    C := APath[I];
    if C in ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~', '/'] then
      Result := Result + C
    else
      Result := Result + '%' + IntToHex(Ord(C), 2);
  end;
end;

function TDragProvider.GetClipboardData(const AMimeType: String; out AData: TBytes): Boolean;
var
  S, P: String;
begin
  Inc(Requests);
  WriteLn(Format('  [%s] データを求められた: %s', [Name, AMimeType]));
  AData := nil;
  Result := True;
  if Length(Paths) = 0 then
  begin
    // 文字列のドラッグ。日本語を含む 2 行。
    AData := BytesOf('papimela のドラッグ' + LineEnding + 'ドラッグして落とした文字列 (2 行目)');
    Exit;
  end;
  if AMimeType = 'text/uri-list' then
  begin
    S := '';
    for P in Paths do
      S := S + PathToURI(P) + #13#10;
    AData := BytesOf(S);
  end
  else if AMimeType = 'text/plain' then
  begin
    S := '';
    for P in Paths do
      S := S + P + LineEnding;
    AData := BytesOf(S);
  end
  else if AMimeType = PML_PORTAL_FILETRANSFER_MIME then
  begin
    // 最初の 1 ファイルだけ。受け手が 1 つだけ表示すれば、ポータルの枝を通った証拠。
    try
      if Transfer = nil then
      begin
        Transfer := TPMLPortalFileTransfer.Create([Paths[0]]);
        WriteLn(Format('  [%s] ポータルの鍵を作った: %s（対象 %s）', [Name, Transfer.Key, Paths[0]]));
      end;
      AData := BytesOf(Transfer.Key);
    except
      on E: Exception do
      begin
        WriteLn('  [', Name, '] ポータルの鍵が作れない: ', E.ClassName, ': ', E.Message);
        Result := False;
      end;
    end;
  end
  else
    Result := False;
end;

procedure TDragProvider.ClipboardDataCancelled;
begin
  Inc(Cancelled);
  WriteLn(Format('  [%s] ClipboardDataCancelled（ドラッグが終わった）', [Name]));
end;

procedure TDragProvider.DropTransfer;
begin
  if Transfer <> nil then
  begin
    FreeAndNil(Transfer);
    WriteLn(Format('  [%s] ポータルの鍵を捨てた（StopTransfer）', [Name]));
  end;
end;

function JoinStr(const A: TStringArray): String;
var
  S: String;
begin
  Result := '';
  for S in A do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + S;
  end;
end;

{ ディレクトリ直下のファイル（名前順）。 }
function ListFiles(const ADir: String): TStringArray;
var
  SR: TSearchRec;
  L: TStringList;
  I: Integer;
  Base: String;
begin
  Result := nil;
  Base := IncludeTrailingPathDelimiter(ExpandFileName(ADir));
  L := TStringList.Create;
  try
    if FindFirst(Base + '*', faAnyFile, SR) = 0 then
    begin
      repeat
        if (SR.Attr and faDirectory) = 0 then
          L.Add(Base + SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
    L.Sort;
    SetLength(Result, L.Count);
    for I := 0 to L.Count - 1 do
      Result[I] := L[I];
  finally
    L.Free;
  end;
end;

{ 32x32 の絵。ファイルは青の丸、文字列は橙の丸。縁は半透明。 }
function MakeIcon(AFiles: Boolean): TPMLSurface;
var
  X, Y: Integer;
  DX, DY, D2: Integer;
  A: Byte;
begin
  Result := TPMLSurface.Create(32, 32, PML_PIXELFORMAT_ARGB8888);
  for Y := 0 to 31 do
    for X := 0 to 31 do
    begin
      DX := X - 16;
      DY := Y - 16;
      D2 := DX * DX + DY * DY;
      if D2 > 15 * 15 then
        A := 0
      else if D2 > 12 * 12 then
        A := 120
      else
        A := 220;
      if A = 0 then
        Result.WritePixel(X, Y, TPMLColor.Make(0, 0, 0, 0))
      else if (X = 16) or (Y = 16) then
        // 中心の十字: 先（ホットスポット）の位置が分かる。
        Result.WritePixel(X, Y, TPMLColor.Make(255, 255, 255, 255))
      else if AFiles then
        Result.WritePixel(X, Y, TPMLColor.Make(40, 110 + LongWord(Y * 3), 230, A))
      else
        Result.WritePixel(X, Y, TPMLColor.Make(240, 130 + LongWord(Y * 2), 30, A));
    end;
end;

function Paint: Boolean;
var
  Pixels: Pointer;
  Pitch, X, Y, HalfX: Integer;
  Row: PLongWord;
  Left, Right: LongWord;
begin
  Result := Win.LockFramebuffer(Pixels, Pitch);
  if not Result then
    Exit;
  // 左半分はファイル（青）、右半分は文字列（橙）。ドラッグ中・落とし中は明るくする。
  if Ctx.Video.Clipboard.IsDragging or Ctx.Events.Drop.IsDropping(Win.ID) then
  begin
    Left := $5080D0;
    Right := $D09050;
  end
  else
  begin
    Left := $203060;
    Right := $603820;
  end;
  HalfX := Win.Width div 2;
  for Y := 0 to Win.Height - 1 do
  begin
    Row := PLongWord(PByte(Pixels) + PtrUInt(Y) * PtrUInt(Pitch));
    for X := 0 to Win.Width - 1 do
      if (X >= HalfX - 1) and (X <= HalfX) then
        Row[X] := $FFFFFF
      else if X < HalfX then
        Row[X] := Left
      else
        Row[X] := Right;
  end;
  Win.UpdateFramebuffer;
end;

function ActionName(AAction: TPMLDragAction): String;
begin
  case AAction of
    TPMLDragAction.Copy: Result := 'Copy';
    TPMLDragAction.Move: Result := 'Move';
  else
    Result := 'Ask';
  end;
end;

procedure StartFileDrag;
var
  Opts: TPMLDragOptions;
  Icon: TPMLSurface;
  Mimes: TStringArray;
  Ok: Boolean;
begin
  if Length(FileProv.Paths) = 0 then
  begin
    WriteLn('  ディレクトリにファイルが無いので始められません: ', Dir);
    Exit;
  end;
  Mimes := ['text/uri-list', 'text/plain'];
  if not NoPortal then
  begin
    SetLength(Mimes, 3);
    Mimes[2] := PML_PORTAL_FILETRANSFER_MIME;
  end;
  Icon := MakeIcon(True);
  try
    Opts := TPMLDragOptions.Default;
    Opts.Icon := Icon;
    Opts.HotX := 16;
    Opts.HotY := 16;
    Ok := Ctx.Video.Clipboard.StartDrag(Win.ID, Mimes, FileProv, Opts);
  finally
    Icon.Free;
  end;
  if Ok then
  begin
    Inc(NStart);
    WriteLn(Format('StartDrag: ファイル %d 個 (%s)', [Length(FileProv.Paths), JoinStr(Mimes)]));
  end
  else
  begin
    Inc(NRefused);
    WriteLn('StartDrag: 始められませんでした（False）');
  end;
end;

procedure StartTextDrag;
var
  Opts: TPMLDragOptions;
  Icon: TPMLSurface;
  Ok: Boolean;
begin
  Icon := MakeIcon(False);
  try
    Opts := TPMLDragOptions.Default;
    Opts.Actions := [TPMLDragAction.Copy, TPMLDragAction.Move];
    Opts.Icon := Icon;
    Opts.HotX := 16;
    Opts.HotY := 16;
    Ok := Ctx.Video.Clipboard.StartDrag(Win.ID,
      ['text/plain;charset=utf-8', 'text/plain'], TextProv, Opts);
  finally
    Icon.Free;
  end;
  if Ok then
  begin
    Inc(NStart);
    WriteLn('StartDrag: 文字列（Copy / Move）');
  end
  else
  begin
    Inc(NRefused);
    WriteLn('StartDrag: 始められませんでした（False）');
  end;
end;

procedure HandleEvents;
var
  Ev: TPMLEvent;
  Ms: Int64;
begin
  while Ctx.Events.Poll(Ev) do
    case Ev.Kind of
      TPMLEventKind.MouseButtonDown:
        if (Ev.Button.Button = 1) and not Ctx.Video.Clipboard.IsDragging then
        begin
          WriteLn(Format('MouseButtonDown x=%.1f y=%.1f', [Ev.Button.X, Ev.Button.Y]));
          if Ev.Button.X < Win.Width / 2 then
            StartFileDrag
          else
            StartTextDrag;
        end;
      TPMLEventKind.DragEnd:
        begin
          Inc(NDragEnd);
          if Ev.Drag.Dropped then
            Inc(NDroppedTrue);
          WriteLn(Format('DragEnd  窓=%d  Dropped=%s  Action=%s',
            [Ev.WindowID, BoolToStr(Ev.Drag.Dropped, True), ActionName(Ev.Drag.Action)]));
          FileProv.DropTransfer;
        end;
      TPMLEventKind.DropBegin:
        begin
          Inc(NBegin);
          DropBeginNS := Ctx.Timer.TicksNS;
          WriteLn(Format('  DropBegin     窓=%d', [Ev.WindowID]));
        end;
      TPMLEventKind.DropFile:
        begin
          Inc(NFile);
          WriteLn(Format('  DropFile      窓=%d  "%s"', [Ev.WindowID, Ev.Text]));
        end;
      TPMLEventKind.DropText:
        begin
          Inc(NText);
          WriteLn(Format('  DropText      窓=%d  "%s"', [Ev.WindowID, Ev.Text]));
        end;
      TPMLEventKind.DropComplete:
        begin
          Inc(NComplete);
          Ms := Int64((Ctx.Timer.TicksNS - DropBeginNS) div 1000000);
          if Ms > MaxDropMs then
            MaxDropMs := Ms;
          WriteLn(Format('  DropComplete  窓=%d  DropBegin から %d ms', [Ev.WindowID, Ms]));
        end;
      TPMLEventKind.KeyDown:
        begin
          if Ev.Key.Keysym = XKB_KEY_Escape then
            Running := False
          else if Ev.Key.Keysym = KEY_C then
          begin
            WriteLn(Format('c キー: CancelDrag（IsDragging=%s）',
              [BoolToStr(Ctx.Video.Clipboard.IsDragging, True)]));
            Ctx.Video.Clipboard.CancelDrag;
          end;
        end;
      TPMLEventKind.WindowCloseRequested:
        Running := False;
    end;
end;

var
  Opts    : TPMLWindowOptions;
  Deadline: UInt64;
  I       : Integer;
  Arg     : String;
  Dragging, LastDragging, Dropping, LastDropping, Painted: Boolean;
  LastW, LastH: Integer;
begin
  LastDragging := False;
  LastDropping := False;
  Painted := False;
  LastW := 0;
  LastH := 0;
  if ParamCount >= 1 then
    Seconds := StrToIntDef(ParamStr(1), 60);
  for I := 2 to ParamCount do
  begin
    Arg := ParamStr(I);
    if Arg = 'noportal' then
      NoPortal := True
    else
      Dir := Arg;
  end;

  WriteLn('demo_drag — ドラッグを始める側を実際の操作で試す');
  WriteLn;
  WriteLn('  左半分を押す: ファイルのドラッグ（', Dir, '）');
  WriteLn('  右半分を押す: 文字列のドラッグ（Copy / Move）');
  WriteLn('  押したままウィンドウの外（ファイルマネージャなど）か、ウィンドウの中へ落とす。');
  WriteLn('  c キー: CancelDrag。Escape かウィンドウを閉じるか、', Seconds, ' 秒で終わります。');
  if NoPortal then
    WriteLn('  noportal: application/vnd.portal.filetransfer は配りません。');
  WriteLn;

  FileProv := TDragProvider.Create;
  FileProv.Name := 'files';
  FileProv.Paths := ListFiles(Dir);
  TextProv := TDragProvider.Create;
  TextProv.Name := 'text';
  for I := 0 to High(FileProv.Paths) do
    WriteLn(Format('  ファイル %d: %s', [I + 1, FileProv.Paths[I]]));
  WriteLn;

  Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
  try
    VB := Ctx.Video.Backend as TPMLWaylandVideoBackend;
    WriteLn(Format('  ビデオ: %s', [Ctx.Video.BackendName]));
    WriteLn(Format('  能力: DragAndDrop=%s  DragAvailable=%s',
      [BoolToStr(TPMLVideoCapability.DragAndDrop in Ctx.Video.Capabilities, True),
       BoolToStr(Ctx.Video.Clipboard.DragAvailable, True)]));
    if not Ctx.Video.Clipboard.DragAvailable then
    begin
      WriteLn('  このコンポジタでは StartDrag が使えないので何も試せません。');
      Exit;
    end;

    Opts := TPMLWindowOptions.Make('papimela — drag (左: ファイル / 右: 文字列)', 640, 400).Resizable;
    Win := Ctx.Video.CreateWindow(Opts);
    WriteLn(Format('  ウィンドウ ID=%d', [Win.ID]));
    WriteLn;

    Deadline := Ctx.Timer.TicksNS + UInt64(Seconds) * 1000000000;
    while Running and (Ctx.Timer.TicksNS < Deadline) do
    begin
      Dragging := Ctx.Video.Clipboard.IsDragging;
      Dropping := Ctx.Events.Drop.IsDropping(Win.ID);
      if (not Painted) or (Dragging <> LastDragging) or (Dropping <> LastDropping)
        or (Win.Width <> LastW) or (Win.Height <> LastH) then
      begin
        Painted := Paint;
        LastDragging := Dragging;
        LastDropping := Dropping;
        LastW := Win.Width;
        LastH := Win.Height;
      end;
      Ctx.Events.Pump(16);
      HandleEvents;
    end;

    // ドラッグ中に終わるなら取り消す（提供者に知らせて鍵を捨てる）。
    if Ctx.Video.Clipboard.IsDragging then
      Ctx.Video.Clipboard.CancelDrag;
    HandleEvents;

    WriteLn;
    WriteLn('=== 結果 ===');
    WriteLn(Format('  StartDrag 成功 %d 回 / 断られた %d 回 / DragEnd %d 件（うち Dropped=True %d 件）',
      [NStart, NRefused, NDragEnd, NDroppedTrue]));
    WriteLn(Format('  データの要求: files %d 回 / text %d 回。ClipboardDataCancelled: files %d 回 / text %d 回',
      [FileProv.Requests, TextProv.Requests, FileProv.Cancelled, TextProv.Cancelled]));
    WriteLn(Format('  Drop*: DropBegin %d / DropFile %d / DropText %d / DropComplete %d。DropBegin から DropComplete の最大 %d ms',
      [NBegin, NFile, NText, NComplete, MaxDropMs]));
    WriteLn(Format('  StartDrag 成功の数 = DragEnd の数 = ClipboardDataCancelled の数: %s',
      [BoolToStr((NStart = NDragEnd) and (NStart = FileProv.Cancelled + TextProv.Cancelled), True)]));
    WriteLn(Format('  ドラッグ中のまま残っていない: %s', [BoolToStr(not Ctx.Video.Clipboard.IsDragging, True)]));
    if PMLPortalLastNonFatalError <> '' then
      WriteLn('  ポータルの見送った失敗: ', PMLPortalLastNonFatalError);
    WriteLn(Format('  wl_display_get_error: %d（0 ならプロトコル違反なし）',
      [wl_display_get_error(VB.Connection.Display)]));
    Win.Free;
  finally
    FreeAndNil(Ctx);
    FileProv.DropTransfer;
    FileProv.Free;
    TextProv.Free;
  end;
end.
