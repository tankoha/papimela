{
  demo_drop — ドラッグ＆ドロップの受信を実際の操作で確認する対話デモ

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    ウィンドウを開き、届いた DropBegin / DropPosition / DropFile / DropText /
    DropComplete を 1 件ずつ、種類・ウィンドウ・座標・文字列つきで出す。
    ウィンドウを閉じるか、指定の秒数が経つと、件数の要約を出して終わる。

  WHY:
    ドラッグ＆ドロップは別のアプリが送り手で、人の操作が要る。test_drop が確かめるのは
    イベントの順序と URI の変換までで、Wayland のデータデバイスとの受け渡し
    （enter / motion / drop / leave、MIME の選択、パイプでの受け取り）は
    ここで実際に落として確かめる。

  使い方:
    ./test/demo_drop [秒数]        既定は 60 秒

    ウィンドウを出したら、次を順に試す。
      1. ファイルマネージャからファイルを 1 つ、ウィンドウへドラッグして落とす。
         DropBegin → DropPosition（動かすたびに何件も）→ DropFile → DropComplete の順に出て、
         DropFile のパスが落としたファイルと同じ（名前に空白や日本語があっても元の文字）。
      2. ファイルを複数選んで落とす。DropFile が 1 つずつ、選んだ数だけ出る。
         DropBegin は 1 回、DropComplete も 1 回。
      3. ブラウザやターミナルで文字列を選んで、ウィンドウへドラッグして落とす。
         DropText が出る（複数行なら行ごとに 1 件）。
      4. ファイルや文字列をウィンドウの上へ持ってきて、落とさずにウィンドウの外へ出す
         （または Escape で取り消す）。DropBegin → DropPosition → DropComplete が出て、
         DropFile も DropText も出ない。
      5. 落とした直後にもう一度落とす。DropBegin がまた 1 回出る（前の落とし終わりで戻っている）。
      6. ブラウザのリンクを落とす。ローカルのファイルではないので DropFile は出ず、
         DropBegin → DropPosition → DropComplete だけが出る（SDL も同じ）。
    座標はウィンドウの左上が (0, 0)。ウィンドウの隅に近づけて、数値が隅に合うかも見る。
    DropComplete の座標は、その落としの最後の DropPosition と同じ。
    落としている間は、ウィンドウの色が明るくなる。

    Escape かウィンドウを閉じる操作で、秒数より前に終わる。
}
program demo_drop;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Events,
  PaPiMeLa.Platform.XKB,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Wayland,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Core;

var
  Ctx     : TPMLContext;
  Win     : TPMLWindow;
  VB      : TPMLWaylandVideoBackend;
  Running : Boolean = True;
  Seconds : Integer = 60;
  NBegin, NPosition, NFile, NText, NComplete: Integer;
  Files   : array of String;
  Texts   : array of String;

function Paint: Boolean;
var
  Pixels: Pointer;
  Pitch, X, Y: Integer;
  Row: PLongWord;
  Base: LongWord;
begin
  Result := Win.LockFramebuffer(Pixels, Pitch);
  if not Result then
    Exit;
  // 落としている間は明るく、そうでなければ暗い緑。
  if Ctx.Events.Drop.IsDropping(Win.ID) then
    Base := $306090
  else
    Base := $205020;
  for Y := 0 to Win.Height - 1 do
  begin
    Row := PLongWord(PByte(Pixels) + PtrUInt(Y) * PtrUInt(Pitch));
    for X := 0 to Win.Width - 1 do
      Row[X] := Base + LongWord((X * 48) div Win.Width);
  end;
  Win.UpdateFramebuffer;
end;

procedure HandleEvents;
var
  Ev: TPMLEvent;
begin
  while Ctx.Events.Poll(Ev) do
    case Ev.Kind of
      TPMLEventKind.DropBegin:
        begin
          Inc(NBegin);
          WriteLn(Format('  DropBegin     窓=%d', [Ev.WindowID]));
        end;
      TPMLEventKind.DropPosition:
        begin
          Inc(NPosition);
          WriteLn(Format('  DropPosition  窓=%d  x=%.1f y=%.1f',
            [Ev.WindowID, Ev.Drop.X, Ev.Drop.Y]));
        end;
      TPMLEventKind.DropFile:
        begin
          Inc(NFile);
          SetLength(Files, Length(Files) + 1);
          Files[High(Files)] := Ev.Text;
          WriteLn(Format('  DropFile      窓=%d  x=%.1f y=%.1f  "%s"',
            [Ev.WindowID, Ev.Drop.X, Ev.Drop.Y, Ev.Text]));
        end;
      TPMLEventKind.DropText:
        begin
          Inc(NText);
          SetLength(Texts, Length(Texts) + 1);
          Texts[High(Texts)] := Ev.Text;
          WriteLn(Format('  DropText      窓=%d  x=%.1f y=%.1f  "%s"',
            [Ev.WindowID, Ev.Drop.X, Ev.Drop.Y, Ev.Text]));
        end;
      TPMLEventKind.DropComplete:
        begin
          Inc(NComplete);
          WriteLn(Format('  DropComplete  窓=%d  x=%.1f y=%.1f',
            [Ev.WindowID, Ev.Drop.X, Ev.Drop.Y]));
        end;
      TPMLEventKind.KeyDown:
        if Ev.Key.Keysym = XKB_KEY_Escape then
          Running := False;
      TPMLEventKind.WindowCloseRequested:
        Running := False;
    end;
end;

var
  Opts    : TPMLWindowOptions;
  Deadline: UInt64;
  I       : Integer;
  Dropping: Boolean;
  LastDropping: Boolean = False;
  Painted: Boolean = False;
  LastW: Integer = 0;
  LastH: Integer = 0;
begin
  if ParamCount >= 1 then
    Seconds := StrToIntDef(ParamStr(1), 60);

  WriteLn('demo_drop — ドラッグ＆ドロップの受信を実際の操作で試す');
  WriteLn;
  WriteLn('  ウィンドウへ次のものをドラッグして、届いたイベントを見てください。');
  WriteLn('    1. ファイルマネージャから ファイル 1 つ');
  WriteLn('    2. 同じく 複数のファイル');
  WriteLn('    3. ブラウザやターミナルで選んだ 文字列');
  WriteLn('    4. 落とさずにウィンドウの上を通って 外へ出す（取り消しも）');
  WriteLn(Format('  Escape かウィンドウを閉じるか、%d 秒で終わります。', [Seconds]));
  WriteLn;

  Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
  try
    VB := Ctx.Video.Backend as TPMLWaylandVideoBackend;
    WriteLn(Format('  ビデオ: %s', [Ctx.Video.BackendName]));
    WriteLn(Format('  能力: Clipboard=%s（データデバイスの有無。ドロップもこれを使う）',
      [BoolToStr(TPMLVideoCapability.Clipboard in Ctx.Video.Capabilities, True)]));
    if not (TPMLVideoCapability.Clipboard in Ctx.Video.Capabilities) then
    begin
      WriteLn('  このコンポジタは wl_data_device_manager を持たないので何も試せません。');
      Exit;
    end;

    Opts := TPMLWindowOptions.Make('papimela — drop (ここへドラッグ)', 640, 400).Resizable;
    Win := Ctx.Video.CreateWindow(Opts);
    WriteLn(Format('  ウィンドウ ID=%d', [Win.ID]));
    WriteLn;

    Deadline := Ctx.Timer.TicksNS + UInt64(Seconds) * 1000000000;
    while Running and (Ctx.Timer.TicksNS < Deadline) do
    begin
      // 色が変わるときと大きさが変わるときだけ描く（毎回描くと CPU を使い切る）。
      Dropping := Ctx.Events.Drop.IsDropping(Win.ID);
      // まだ描けていないとき（最初の configure の前）は、描けるまで毎回試す。
      if (not Painted) or (Dropping <> LastDropping) or (Win.Width <> LastW)
        or (Win.Height <> LastH) then
      begin
        Painted := Paint;
        LastDropping := Dropping;
        LastW := Win.Width;
        LastH := Win.Height;
      end;
      Ctx.Events.Pump(16);
      HandleEvents;
    end;

    WriteLn;
    WriteLn('=== 結果 ===');
    WriteLn(Format('  DropBegin %d 件 / DropPosition %d 件 / DropFile %d 件 / DropText %d 件 / DropComplete %d 件',
      [NBegin, NPosition, NFile, NText, NComplete]));
    for I := 0 to High(Files) do
      WriteLn(Format('  ファイル %d: %s', [I + 1, Files[I]]));
    for I := 0 to High(Texts) do
      WriteLn(Format('  テキスト %d: %s', [I + 1, Texts[I]]));
    WriteLn(Format('  DropBegin と DropComplete の数が合う: %s（落とし始めと終わりが対になる）',
      [BoolToStr(NBegin = NComplete, True)]));
    WriteLn(Format('  落とし中のまま残っていない: %s',
      [BoolToStr(not Ctx.Events.Drop.IsDropping(Win.ID), True)]));
    WriteLn(Format('  wl_display_get_error: %d（0 ならプロトコル違反なし）',
      [wl_display_get_error(VB.Connection.Display)]));
    Win.Free;
  finally
    FreeAndNil(Ctx);
  end;
end.
