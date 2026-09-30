{
  test_dummy_video — 表示サーバ無しで公開 API を検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    ダミービデオバックエンドで TPMLVideoSystem / TPMLWindow / イベントキューを
    動かし、ウィンドウ生成・リサイズ・状態変化・フレームバッファが設計どおりに
    振る舞うことを確認する。

  WHY:
    他の自動テストはすべて実機のコンポジタに繋がるため CI で走らせられない。
    このテストだけは WAYLAND_DISPLAY が無くても通るので、公開 API の退行は
    CI で捕まえられる（第 11 章 #70）。

    逆に言うと、ここで検査できるのは**バックエンドに依存しない部分だけ**である。
    Wayland のプロトコル手順は T-04 / T-05 / T-08 が実機で見ている。

  実行前提: 無し。WAYLAND_DISPLAY が設定されていても PAPIMELA_VIDEO=dummy で
            ダミーを選ぶ。
}
program test_dummy_video;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Dummy,
  PaPiMeLa.Core;

var
  Ctx     : TPMLContext;
  Win     : TPMLWindow;
  Failures: Integer = 0;
  // Sink から届いたイベントの数
  NResized  : Integer = 0;
  NPixelSize: Integer = 0;
  NState    : Integer = 0;
  LastW, LastH: Integer;

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

procedure Drain;
var
  Ev: TPMLEvent;
begin
  Ctx.Events.Pump(0);
  while Ctx.Events.Poll(Ev) do
    case Ev.Kind of
      TPMLEventKind.WindowResized:
        begin
          Inc(NResized);
          LastW := Ev.Window.Data1;
          LastH := Ev.Window.Data2;
        end;
      TPMLEventKind.WindowPixelSizeChanged:
        Inc(NPixelSize);
      TPMLEventKind.WindowMaximized,
      TPMLEventKind.WindowMinimized,
      TPMLEventKind.WindowRestored,
      TPMLEventKind.WindowShown,
      TPMLEventKind.WindowHidden:
        Inc(NState);
    end;
end;

var
  Pixels  : Pointer;
  Pitch   : Integer;
  Row     : PLongWord;
  Display : TPMLDisplay;
  Mode    : TPMLDisplayMode;
  WB      : TPMLDummyWindowBackend;
  Opts    : TPMLContextOptions;
begin
  WriteLn('test_dummy_video — 表示サーバ無しでの公開 API');
  WriteLn;

  // 実機の Wayland セッションで走らせてもダミーを選ばせる。環境変数ではなく
  // オプションで指定するので、呼び出し方に左右されない。
  Opts := TPMLContextOptions.Create;
  try
    Opts.PreferredVideo := 'dummy';
    Ctx := TPMLContext.Create([TPMLSubsystem.Video], Opts);
  finally
    Opts.Free;   // 呼び出し側の持ち物。Context は保持しない
  end;

  try
    WriteLn('1. バックエンドの選択');
    Check(Ctx.Video.BackendName = 'dummy', 'PAPIMELA_VIDEO=dummy でダミーが選ばれる');
    Check(Ctx.Video.Backend is TPMLDummyVideoBackend, '型もダミー');
    Check(TPMLVideoCapability.SoftwareFramebuffer in Ctx.Video.Capabilities,
      'ソフトウェアフレームバッファの能力がある');
    Check(not (TPMLVideoCapability.RelativeMouse in Ctx.Video.Capabilities),
      '持っていない能力は立っていない');

    WriteLn;
    WriteLn('2. ディスプレイ');
    Check(Length(Ctx.Video.Displays) = 1, 'ディスプレイが 1 台');
    Display := Ctx.Video.PrimaryDisplay;
    Check(Display <> nil, '主ディスプレイが取れる');
    Check(Display.Name = 'dummy-display-0', '名前が付いている');
    // PAPIMELA_DUMMY_SIZE を設定していないので既定値になる。CI で毎回同じ値が
    // 出ることが大事なので、そこをアサーションにしている。
    Check((Display.Bounds.W = 1280) and (Display.Bounds.H = 720),
      '既定の大きさは 1280x720 で固定');
    Mode := Display.DesktopMode;
    Check((Mode.Width = 1280) and (Mode.Height = 720), 'デスクトップモードも一致する');
    Check(Mode.RefreshRate > 0, 'リフレッシュレートが入っている');

    WriteLn;
    WriteLn('3. ウィンドウ生成');
    Win := Ctx.Video.CreateWindow(
      TPMLWindowOptions.Make('dummy window', 320, 240).Resizable);
    WB := Win.Backend as TPMLDummyWindowBackend;
    Drain;
    Check(Win.ID <> 0, 'ウィンドウ ID が振られる');
    Check((Win.Width = 320) and (Win.Height = 240), '要求した大きさになる');
    Check(WB.Title = 'dummy window', 'タイトルがバックエンドへ届く');
    Check(WB.Visible, '既定で可視');
    Check(TPMLWindowFlag.Resizable in Win.Flags, '生成時のフラグが残る');

    Win.Title := 'renamed';
    Check(WB.Title = 'renamed', 'タイトルを変えられる');

    WriteLn;
    WriteLn('4. フレームバッファ');
    Check(Win.LockFramebuffer(Pixels, Pitch), 'フレームバッファを取れる');
    Check(Pixels <> nil, 'ポインタが nil でない');
    Check(Pitch = 320 * 4, 'ピッチは幅 * 4');
    // 実際に書けること。壊れていれば segfault する。
    Row := PLongWord(Pixels);
    Row[0] := $11223344;
    Row[320 * 240 - 1] := $55667788;
    Check(Row[0] = $11223344, '先頭に書ける');
    Check(Row[320 * 240 - 1] = $55667788, '末尾に書ける');
    Win.UpdateFramebuffer;
    Check(True, 'UpdateFramebuffer は表示先が無くても落ちない');

    WriteLn;
    WriteLn('5. リサイズ');
    NResized := 0;
    NPixelSize := 0;
    Win.SetSize(640, 480);
    Drain;
    Check(NResized = 1, 'WindowResized が 1 回届く');
    Check(NPixelSize = 1, 'WindowPixelSizeChanged も 1 回届く');
    Check((LastW = 640) and (LastH = 480), 'イベントに新しい大きさが載る');
    Check((Win.Width = 640) and (Win.Height = 480), '公開層の大きさも追従する');
    Check(Win.LockFramebuffer(Pixels, Pitch), 'リサイズ後もフレームバッファを取れる');
    Check(Pitch = 640 * 4, 'ピッチが新しい幅に追従する');

    // 同じ大きさを指定しても何も起きないこと。
    NResized := 0;
    Win.SetSize(640, 480);
    Drain;
    Check(NResized = 0, '同じ大きさなら通知しない');

    WriteLn;
    WriteLn('6. 状態の変化');
    NState := 0;
    Win.Maximize;
    Drain;
    Check(TPMLWindowFlag.Maximized in Win.Flags, '最大化が Flags に入る');
    Win.Restore;
    Drain;
    Check(not (TPMLWindowFlag.Maximized in Win.Flags), '復帰で最大化が消える');
    // D-24 の再発検知。バックエンドの状態通知が生成時のフラグを消さないこと。
    Check(TPMLWindowFlag.Resizable in Win.Flags,
      '状態変化のあとも生成時の Resizable が残る');
    Check(NState > 0, '状態変化のイベントが届く');

    Win.Hide;
    Drain;
    Check(not WB.Visible, '非表示にできる');
    Win.Show;
    Drain;
    Check(WB.Visible, '再表示できる');

    WriteLn;
    WriteLn('7. 後始末');
    Win.Free;
    Drain;
    Check(Length(Ctx.Video.Windows) = 0, 'ウィンドウ一覧から消える');
    Check(Ctx.Events.DroppedCount = 0, 'イベントの取りこぼしなし');
  finally
    FreeAndNil(Ctx);
  end;
  WriteLn('  [PASS] Context 破棄');

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn('=== 結論: 表示サーバ無しで公開 API が動く ===');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('=== 失敗 %d 件 ===', [Failures]));
    ExitCode := 1;
  end;
end.
