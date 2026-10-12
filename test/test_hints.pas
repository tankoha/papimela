{
  test_hints — ヒントを使う側（SDL のヒントのうち papimela の機能に効くもの）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. どの部品からも Context の土台（ContextServices）に届く。Context 無しで作った物は nil
    2. AppID（SDL_GetAppID）: ヒント → FLATPAK_ID → 実行ファイルの名前
    3. PAPIMELA_KEYCODE_OPTIONS（SDL_HINT_KEYCODE_OPTIONS）と hide_numpad の置き換え
    4. PAPIMELA_RENDER_DRIVER（カンマ区切りで順に試す）と PAPIMELA_RENDER_VSYNC
    5. EGL のライブラリ名（PAPIMELA_EGL_LIBRARY が渡る先の PMLEGLLoad）
    6〜10.（B）スレッドの方針、IME の UI、最後のウィンドウで Quit、SIGINT / SIGTERM、イベントのログ

  WHY:
    §3 の 1（ヒントを使う側）の A の受け入れ検査。実装より先に書き、空の実装で落ちることを
    確かめてから渡す。表示サーバは要らない（ダミーのビデオ）。5. は Mesa の EGL が要る
    （CI にもある）。ヒントがウィンドウの GL に届くことは test_gl_window（手元）で見る。

  実行前提: cthreads（uses の先頭）。環境変数は libc の setenv で置く。
}
program test_hints;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils, Classes, BaseUnix, UnixType,
  PaPiMeLa,
  PaPiMeLa.Events.Keymap,
  PaPiMeLa.Events.Quit,
  PaPiMeLa.Platform.EGL,
  PaPiMeLa.TextInput.Backend,
  PaPiMeLa.TextInput.Fcitx,
  PaPiMeLa.TextInput.IBus;

function setenv(AName, AValue: PAnsiChar; AOverwrite: LongInt): LongInt; cdecl; external 'c';
function unsetenv(AName: PAnsiChar): LongInt; cdecl; external 'c';

var
  Failures: Integer = 0;
  Ctx: TPMLContext;

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

function DummyContext(ASubsystems: TPMLSubsystems): TPMLContext;
var
  Opts: TPMLContextOptions;
begin
  Opts := TPMLContextOptions.Default;
  Opts.PreferredVideo := 'dummy';
  Result := TPMLContext.Create(ASubsystems, Opts);
end;

{ ---- 1. ContextServices ---- }

procedure TestServices;
var
  Surf: TPMLSurface;
  Win: TPMLWindow;
begin
  WriteLn('1. ContextServices');
  Ctx := DummyContext([TPMLSubsystem.Video]);
  try
    Check(Ctx.ContextServices = Ctx, 'Context 自身は自分');
    Check(Ctx.Events.ContextServices = Ctx, 'イベントのキューから Context に届く');
    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('services', 64, 48));
    Check(Win.ContextServices = Ctx, 'ウィンドウから Context に届く');
    Check(Win.Backend.ContextServices = Ctx, 'ウィンドウのバックエンドから Context に届く');
    Check(Win.ContextServices.Hints = Ctx.Hints, 'そこからヒントが読める');
    Win.Free;
  finally
    Ctx.Free;
  end;
  Surf := TPMLSurface.Create(4, 4, PML_PIXELFORMAT_XRGB8888);
  try
    Check(Surf.ContextServices = nil, 'Context 無しで作った物は nil');
  finally
    Surf.Free;
  end;
end;

{ ---- 2. AppID ---- }

procedure TestAppID;
begin
  WriteLn;
  WriteLn('2. AppID（SDL_GetAppID）');
  unsetenv(PML_HINT_APP_ID);
  unsetenv('FLATPAK_ID');
  Ctx := DummyContext([]);
  try
    Check(Ctx.AppID = ApplicationName, '何も無ければ実行ファイルの名前: ' + Ctx.AppID);
    setenv('FLATPAK_ID', 'org.example.Flat', 1);
    Check(Ctx.AppID = 'org.example.Flat', '次に環境変数 FLATPAK_ID');
    Ctx.Hints.SetHint(PML_HINT_APP_ID, 'org.example.Hint');
    Check(Ctx.AppID = 'org.example.Hint', 'ヒントがあればそれ');
    Ctx.Hints.SetHint(PML_HINT_APP_ID, '');
    Check(Ctx.AppID = 'org.example.Flat', '空のヒントは無いのと同じ（SDL と同じ）');
    unsetenv('FLATPAK_ID');
  finally
    Ctx.Free;
  end;
end;

{ ---- 3. キーコードの決め方 ---- }

var
  Keys: array of TPMLKeycode;

procedure Drain;
var
  Ev: TPMLEvent;
begin
  SetLength(Keys, 0);
  while Ctx.Events.Poll(Ev) do
    if Ev.Kind = TPMLEventKind.KeyDown then
    begin
      SetLength(Keys, Length(Keys) + 1);
      Keys[High(Keys)] := Ev.Key.Key;
    end;
end;

function PressKey(AScancode: TPMLScancode): TPMLKeycode;
var
  K: TPMLKeyEventData;
begin
  Drain;
  FillChar(K, SizeOf(K), 0);
  K.Scancode := AScancode;
  Ctx.Events.Keyboard.SendKey(1, K, True, '');
  Ctx.Events.Keyboard.SendKey(1, K, False, '');
  Drain;
  if Length(Keys) = 1 then
    Result := Keys[0]
  else
    Result := PMLK_UNKNOWN;
end;

function Opts(const AHint: String): TPMLKeycodeOptions;
begin
  Ctx.Hints.SetHint(PML_HINT_KEYCODE_OPTIONS, AHint);
  Result := Ctx.Events.Keyboard.KeycodeOptions;
end;

procedure TestKeycodeOptions;
const
  ALL_OPTS = [TPMLKeycodeOption.HideNumpad, TPMLKeycodeOption.FrenchNumbers,
              TPMLKeycodeOption.LatinLetters];
begin
  WriteLn;
  WriteLn('3. PAPIMELA_KEYCODE_OPTIONS');
  unsetenv(PML_HINT_KEYCODE_OPTIONS);
  Ctx := DummyContext([]);
  try
    Check(Ctx.Events.Keyboard.KeycodeOptions = PML_DEFAULT_KEYCODE_OPTIONS, 'ヒントが無ければ既定（french_numbers,latin_letters）');
    Check(Opts('none') = [], '"none" で全部外す');
    Check(Opts('hide_numpad') = [TPMLKeycodeOption.HideNumpad], '"hide_numpad" だけ');
    Check(Opts('hide_numpad,french_numbers,latin_letters') = ALL_OPTS, '3 つ全部');
    Check(Opts('french_numbers, latin_letters') = PML_DEFAULT_KEYCODE_OPTIONS, '空白を挟んでもよい');
    Check(Opts('hide_numpad,none') = [], '"none" は他より強い（SDL と同じ）');
    Check(Opts('nonexistent,hide_numpad') = [TPMLKeycodeOption.HideNumpad],
      '語は丸ごと比べる（SDL は部分一致なので "nonexistent" で全部外れる）');
    Check(Opts('') = PML_DEFAULT_KEYCODE_OPTIONS, '空は既定（SDL と同じ）');
    Opts('none');
    Ctx.Hints.ResetHint(PML_HINT_KEYCODE_OPTIONS);
    Check(Ctx.Events.Keyboard.KeycodeOptions = PML_DEFAULT_KEYCODE_OPTIONS, 'ヒントを消すと既定に戻る');

    // hide_numpad の置き換え（SDL_ConvertNumpadKeycode）
    Check(PressKey(TPMLScancode.KP_4) = PMLK_KP_4, '既定ではテンキーの 4 は KP_4');
    Opts('hide_numpad');
    Ctx.Events.Keyboard.SendModifiers([TPMLKeyModifier.NumLock]);
    Check(PressKey(TPMLScancode.KP_4) = PMLK_4, 'hide_numpad で NumLock なら 4');
    Ctx.Events.Keyboard.SendModifiers([]);
    Check(PressKey(TPMLScancode.KP_4) = PMLK_LEFT, 'hide_numpad で NumLock でなければ ←');
    Check(PressKey(TPMLScancode.KP_ENTER) = PMLK_RETURN, 'テンキーの Enter は Return（NumLock に依らない）');
    Check(PressKey(TPMLScancode.KP_PERIOD) = PMLK_DELETE, 'NumLock でなければ . は Delete');
    Check(PressKey(TPMLScancode.Digit4) = PMLK_4, 'テンキーでないキーは変わらない');
    Check((PMLConvertNumpadKeycode(PMLK_KP_PLUSMINUS, False) = PMLK_PLUSMINUS)
      and (PMLConvertNumpadKeycode(PMLK_KP_0, True) = PMLK_0)
      and (PMLConvertNumpadKeycode(PMLK_KP_0, False) = PMLK_INSERT)
      and (PMLConvertNumpadKeycode(PMLK_A, False) = PMLK_A), 'PMLConvertNumpadKeycode の端');
    Ctx.Events.Keyboard.KeycodeOptions := [];
    Check(PressKey(TPMLScancode.KP_4) = PMLK_KP_4, 'KeycodeOptions を直接置いてもよい');
  finally
    Ctx.Free;
  end;
end;

{ ---- 4. レンダラのドライバと VSync ---- }

function MakeRenderer(AWin: TPMLWindow; const AName: String; out AError: String): TPMLRenderer;
begin
  AError := '';
  Result := nil;
  try
    Result := TPMLRenderer.CreateForWindow(AWin, AName);
  except
    on E: EPMLError do
      AError := E.ClassName;
  end;
end;

procedure TestRenderHints;
var
  Win: TPMLWindow;
  R: TPMLRenderer;
  Err: String;
begin
  WriteLn;
  WriteLn('4. PAPIMELA_RENDER_DRIVER と PAPIMELA_RENDER_VSYNC');
  unsetenv(PML_HINT_RENDER_DRIVER);
  unsetenv(PML_HINT_RENDER_VSYNC);
  Ctx := DummyContext([TPMLSubsystem.Video]);
  try
    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('render', 64, 48));
    try
      R := MakeRenderer(Win, '', Err);
      Check((R <> nil) and (R.DriverName = 'software') and (R.VSync = 0), 'ヒントが無ければ今までどおり（software、VSync 0）');
      R.Free;

      Ctx.Hints.SetHint(PML_HINT_RENDER_DRIVER, 'nosuch');
      R := MakeRenderer(Win, '', Err);
      Check((R = nil) and (Err = 'EPMLUnsupported'), '知らない名前だけなら EPMLUnsupported: ' + Err);
      R.Free;
      Ctx.Hints.SetHint(PML_HINT_RENDER_DRIVER, 'nosuch,software');
      R := MakeRenderer(Win, '', Err);
      Check((R <> nil) and (R.DriverName = 'software'), 'カンマ区切りで順に試す（知らない名前は飛ばす）');
      R.Free;
      Ctx.Hints.SetHint(PML_HINT_RENDER_DRIVER, 'gles2,software');
      R := MakeRenderer(Win, '', Err);
      Check((R <> nil) and (R.DriverName = 'software'),
        '作れなかったドライバ（GL でないウィンドウの gles2）は飛ばして次へ: ' + Err);
      R.Free;
      Ctx.Hints.SetHint(PML_HINT_RENDER_DRIVER, 'gles2');
      R := MakeRenderer(Win, '', Err);
      Check((R = nil) and (Err = 'EPMLUnsupported'),
        'どれも作れなければ、最後に作れなかったドライバの例外をそのまま（GL でないウィンドウの gles2 は EPMLUnsupported）: ' + Err);
      R.Free;
      R := MakeRenderer(Win, 'nosuch,SOFTWARE', Err);
      Check((R <> nil) and (R.DriverName = 'software'), '引数の名前もカンマ区切りで、大文字小文字を区別しない');
      R.Free;
      Ctx.Hints.ResetHint(PML_HINT_RENDER_DRIVER);

      Ctx.Hints.SetHint(PML_HINT_RENDER_VSYNC, '1');
      R := MakeRenderer(Win, '', Err);
      Check((R <> nil) and (R.VSync = 1), 'PAPIMELA_RENDER_VSYNC=1 で作った時点から VSync 1');
      R.Free;
      Ctx.Hints.SetHint(PML_HINT_RENDER_VSYNC, 'false');
      R := MakeRenderer(Win, '', Err);
      Check((R <> nil) and (R.VSync = 0), '"false" は 0');
      R.Free;
      Ctx.Hints.SetHint(PML_HINT_RENDER_VSYNC, 'yes');
      R := MakeRenderer(Win, '', Err);
      Check((R <> nil) and (R.VSync = 1), '真偽の読み方は PMLStringBoolean（"yes" は 1）');
      R.Free;
    finally
      Win.Free;
    end;
  finally
    Ctx.Free;
  end;
end;

{ ---- 5. EGL のライブラリ名 ---- }

procedure TestEGLLibrary;
var
  Ok: Boolean;
begin
  WriteLn;
  WriteLn('5. EGL のライブラリ名（PMLEGLLoad）');
  Ok := PMLEGLLoad('/nonexistent/libEGL.so.1');
  Check(not Ok, '読めない名前を渡すと False（既定へは逃げない。SDL と同じ）');
  if Ok then
    PMLEGLUnload;
  Ok := PMLEGLLoad('libEGL.so.1');
  Check(Ok, '名前を渡して読める');
  if Ok then
    PMLEGLUnload;
  Ok := PMLEGLLoad('');
  Check(Ok, '空なら既定の名前');
  if Ok then
    PMLEGLUnload;
end;

{ ---- 6. スレッドの方針（B1。実時間そのものは test_thread_realtime） ---- }

type
  TLowWorker = class(TPMLThread)
  public
    Ok: Boolean;
    Nice: Integer;
    Policy: TPMLSchedPolicy;
  protected
    function Run: Integer; override;
  end;

function TLowWorker.Run: Integer;
begin
  Ok := Ctx.SetCurrentThreadPriority(TPMLThreadPriority.Low);
  Nice := TPMLThread.CurrentNiceValue;
  Policy := TPMLThread.CurrentSchedPolicy;
  Result := 0;
end;

procedure TestThreadPolicy;
const
  O = TPMLSchedPolicy.Other;
  RR = TPMLSchedPolicy.RR;
  FF = TPMLSchedPolicy.FIFO;
var
  W: TLowWorker;
begin
  WriteLn;
  WriteLn('6. スレッドの方針（PAPIMELA_THREAD_PRIORITY_POLICY など）');
  Check((PMLThreadSchedPolicy(TPMLThreadPriority.Low, '', False, O) = O)
    and (PMLThreadSchedPolicy(TPMLThreadPriority.High, '', False, O) = O)
    and (PMLThreadSchedPolicy(TPMLThreadPriority.TimeCritical, '', False, O) = O),
    'ヒントが無ければ、どの優先度も Other（Linux の SDL と同じ）');
  Check((PMLThreadSchedPolicy(TPMLThreadPriority.TimeCritical, '', True, O) = RR)
    and (PMLThreadSchedPolicy(TPMLThreadPriority.High, '', True, O) = O),
    'FORCE_REALTIME_TIME_CRITICAL なら TimeCritical だけ RR');
  Check((PMLThreadSchedPolicy(TPMLThreadPriority.Normal, 'rr', False, O) = RR)
    and (PMLThreadSchedPolicy(TPMLThreadPriority.Low, 'fifo', False, O) = FF)
    and (PMLThreadSchedPolicy(TPMLThreadPriority.TimeCritical, 'other', True, O) = O),
    '"rr" / "fifo" / "other" はそれに決める（FORCE より強い）');
  Check((PMLThreadSchedPolicy(TPMLThreadPriority.High, 'current', False, FF) = FF)
    and (PMLThreadSchedPolicy(TPMLThreadPriority.High, 'current', True, O) = O),
    '"current" は今の方針のまま');
  Check((PMLThreadSchedPolicy(TPMLThreadPriority.High, 'bogus', False, FF) = O)
    and (PMLThreadSchedPolicy(TPMLThreadPriority.TimeCritical, 'bogus', True, O) = RR),
    '知らない値は既定の決め方');
  Check((PMLRealtimePriority(TPMLThreadPriority.Low, 20) = 1)
    and (PMLRealtimePriority(TPMLThreadPriority.Normal, 20) = 10)
    and (PMLRealtimePriority(TPMLThreadPriority.High, 20) = 15)
    and (PMLRealtimePriority(TPMLThreadPriority.TimeCritical, 20) = 20)
    and (PMLRealtimePriority(TPMLThreadPriority.High, 99) = 74),
    '実時間の優先度（Low 1、Normal 半分、High 3/4、TimeCritical 上限）');
  Ctx := DummyContext([]);
  try
    W := TLowWorker.Create('lowprio', True);
    try
      W.Start;
      W.WaitFor;
      Check(W.Ok and (W.Nice = 19) and (W.Policy = O),
        Format('Ctx.SetCurrentThreadPriority(Low) は nice 19・Other（%d）', [W.Nice]));
    finally
      W.Free;
    end;
  finally
    Ctx.Free;
  end;
end;

{ ---- 7. IME の UI（B2） ---- }

procedure TestImeUI;
const
  C = TPMLImeUIElement.Composition;
  D = TPMLImeUIElement.Candidates;
begin
  WriteLn;
  WriteLn('7. PAPIMELA_IME_IMPLEMENTED_UI');
  Check(PMLParseImeImplementedUI('') = [C], '空は composition（papimela の既定。SDL は none）');
  Check((PMLParseImeImplementedUI('none') = []) and (PMLParseImeImplementedUI('0') = []), '"none" と "0" は空');
  Check(PMLParseImeImplementedUI('composition, Candidates') = [C, D], '語を分け、空白と大文字小文字を無視');
  Check(PMLParseImeImplementedUI('candidates') = [D], '"candidates" だけ');
  Check(PMLParseImeImplementedUI('composition,none') = [], '"none" は他より強い');
  Check((PMLFcitxCapabilities([C]) = 82) and (PMLFcitxCapabilities([]) = 64)
    and (PMLFcitxCapabilities([D]) = 64),
    'fcitx5: composition なら 82（今まで送っていた値）、無ければ周辺テキストの 64 だけ');
  Check((PMLIBusCapabilities([C]) = 41) and (PMLIBusCapabilities([]) = 40),
    'IBus: composition なら 41（今まで送っていた値）、無ければ FOCUS と周辺テキストの 40');
end;

{ ---- 8. 最後のウィンドウを閉じる要求で Quit（B3） ---- }

function DrainKinds: String;
var
  Ev: TPMLEvent;
begin
  Result := '';
  while Ctx.Events.Poll(Ev) do
    if Ev.Kind in [TPMLEventKind.WindowCloseRequested, TPMLEventKind.Quit] then
    begin
      if Result <> '' then
        Result := Result + ',';
      if Ev.Kind = TPMLEventKind.Quit then
        Result := Result + 'Quit'
      else
        Result := Result + 'Close';
    end;
end;

procedure TestQuitOnLastWindow;
var
  W1, W2, W3: TPMLWindow;
begin
  WriteLn;
  WriteLn('8. PAPIMELA_QUIT_ON_LAST_WINDOW_CLOSE');
  Ctx := DummyContext([TPMLSubsystem.Video]);
  try
    W1 := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('w1', 32, 32));
    W2 := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('w2', 32, 32));
    DrainKinds;
    Ctx.Video.WindowCloseRequested(W1.ID);
    Check(DrainKinds = 'Close', '他に見えているウィンドウがあれば Quit は出ない');
    W1.Free;
    DrainKinds;
    Ctx.Video.WindowCloseRequested(W2.ID);
    Check(DrainKinds = 'Close,Quit', '最後のウィンドウなら閉じる要求の後に Quit（既定 1）');
    W3 := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('w3', 32, 32));
    W3.Hide;
    DrainKinds;
    Ctx.Video.WindowCloseRequested(W2.ID);
    Check(DrainKinds = 'Close,Quit', '隠れたウィンドウは数えない');
    Ctx.Hints.SetHint(PML_HINT_QUIT_ON_LAST_WINDOW_CLOSE, '0');
    Ctx.Video.WindowCloseRequested(W2.ID);
    Check(DrainKinds = 'Close', 'ヒントが 0 なら Quit は出ない');
    W3.Free;
    W2.Free;
  finally
    Ctx.Free;
  end;
end;

{ ---- 9. SIGINT / SIGTERM（B4） ---- }

var
  OwnHits: Integer;

procedure OwnHandler(ASig: cint); cdecl;
begin
  Inc(OwnHits);
end;

function HandlerOf(ASig: cint): Pointer;
var
  Act: SigActionRec;
begin
  FillChar(Act, SizeOf(Act), 0);
  FpSigAction(ASig, nil, @Act);
  Result := Pointer(Act.sa_handler);
end;

function HasQuit(AContext: TPMLContext): Boolean;
var
  Ev: TPMLEvent;
begin
  Result := False;
  AContext.Events.Pump(0);
  while AContext.Events.Poll(Ev) do
    if Ev.Kind = TPMLEventKind.Quit then
      Result := True;
end;

procedure TestSignals;
var
  Ctx2: TPMLContext;
  Opts: TPMLContextOptions;
  Act: SigActionRec;
begin
  WriteLn;
  WriteLn('9. SIGINT / SIGTERM（PAPIMELA_NO_SIGNAL_HANDLERS）');
  Check((HandlerOf(SIGINT) = Pointer(SIG_DFL)) and (HandlerOf(SIGTERM) = Pointer(SIG_DFL)), '前提: 始めは既定の手続き');
  Ctx := DummyContext([]);
  Ctx2 := DummyContext([]);
  try
    Check((HandlerOf(SIGINT) <> Pointer(SIG_DFL)) and (HandlerOf(SIGTERM) <> Pointer(SIG_DFL)),
      'Context を作ると SIGINT と SIGTERM に手続きを置く');
    Check(not HasQuit(Ctx), 'シグナルが無ければ Quit は出ない');
    if HandlerOf(SIGINT) <> Pointer(SIG_DFL) then
    begin
      FpKill(FpGetPid, SIGINT);
      Check(HasQuit(Ctx), 'SIGINT を受けると次の Pump で Quit');
      Check(HasQuit(Ctx2), '同じプロセスの他の Context にも Quit');
      Check(not HasQuit(Ctx), '1 回のシグナルで Quit は 1 回');
      FpKill(FpGetPid, SIGTERM);
      Check(HasQuit(Ctx), 'SIGTERM でも Quit');
    end;
    Ctx2.Free;
    Ctx2 := nil;
    Check(HandlerOf(SIGINT) <> Pointer(SIG_DFL), 'まだ Context が残っていれば手続きはそのまま');
  finally
    Ctx2.Free;
    Ctx.Free;
  end;
  Check((HandlerOf(SIGINT) = Pointer(SIG_DFL)) and (HandlerOf(SIGTERM) = Pointer(SIG_DFL)),
    '最後の Context を壊すと既定の手続きに戻す');

  Opts := TPMLContextOptions.Default;
  Opts.PreferredVideo := 'dummy';
  Opts.Hints.Add(PML_HINT_NO_SIGNAL_HANDLERS, '1');
  Ctx := TPMLContext.Create([], Opts);
  try
    Check(HandlerOf(SIGINT) = Pointer(SIG_DFL), 'PAPIMELA_NO_SIGNAL_HANDLERS=1 なら手続きを置かない');
  finally
    Ctx.Free;
  end;

  // アプリが自分の手続きを置いていれば触らない
  FillChar(Act, SizeOf(Act), 0);
  Act.sa_handler := SigActionHandler(@OwnHandler);
  FpSigAction(SIGINT, @Act, nil);
  Ctx := DummyContext([]);
  try
    Check(HandlerOf(SIGINT) = Pointer(@OwnHandler), 'アプリの手続きはそのまま');
    FpKill(FpGetPid, SIGINT);
    Check((OwnHits = 1) and not HasQuit(Ctx), 'アプリの手続きが呼ばれ、Quit は出ない');
  finally
    Ctx.Free;
  end;
  Check(HandlerOf(SIGINT) = Pointer(@OwnHandler), 'Context を壊してもアプリの手続きは残す');
  FillChar(Act, SizeOf(Act), 0);
  Act.sa_handler := SigActionHandler(SIG_DFL);
  FpSigAction(SIGINT, @Act, nil);
end;

{ ---- 10. イベントのログ（B5） ---- }

type
  TLogCapture = class
  public
    Lines: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Output(ACategory: Integer; APriority: TPMLLogPriority; const AMessage: String);
    function Count(const APrefix: String): Integer;
  end;

constructor TLogCapture.Create;
begin
  inherited Create;
  Lines := TStringList.Create;
end;

destructor TLogCapture.Destroy;
begin
  Lines.Free;
  inherited Destroy;
end;

procedure TLogCapture.Output(ACategory: Integer; APriority: TPMLLogPriority; const AMessage: String);
begin
  Lines.Add(AMessage);
end;

function TLogCapture.Count(const APrefix: String): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Lines.Count - 1 do
    if Copy(Lines[I], 1, Length(APrefix)) = APrefix then
      Inc(Result);
end;

procedure TestEventLogging;
var
  Cap: TLogCapture;
  Ev: TPMLEvent;

  procedure PushBoth;
  begin
    Cap.Lines.Clear;
    Ctx.Events.PushSimple(TPMLEventKind.KeyDown, 1);
    Ctx.Events.PushSimple(TPMLEventKind.MouseMotion, 1);
    while Ctx.Events.Poll(Ev) do ;
  end;

begin
  WriteLn;
  WriteLn('10. PAPIMELA_EVENT_LOGGING');
  Check((PMLEventLoggingVerbosity('') = 0) and (PMLEventLoggingVerbosity('2') = 2)
    and (PMLEventLoggingVerbosity('7') = 3) and (PMLEventLoggingVerbosity('-1') = 0)
    and (PMLEventLoggingVerbosity('x') = 0) and (PMLEventLoggingVerbosity('1abc') = 1),
    '値の読み方（atoi して 0..3 に収める）');
  Check(PMLEventLogged(TPMLEventKind.KeyDown, 1) and not PMLEventLogged(TPMLEventKind.MouseMotion, 1)
    and PMLEventLogged(TPMLEventKind.MouseMotion, 2) and not PMLEventLogged(TPMLEventKind.KeyDown, 0)
    and not PMLEventLogged(TPMLEventKind.FingerMotion, 1),
    '1 では動きの多いものを出さず、2 で全部');
  FillChar(Ev, SizeOf(Ev), 0);
  Ev.Kind := TPMLEventKind.KeyDown;
  Ev.WindowID := 7;
  Check(Copy(PMLEventDescription(Ev), 1, 7) = 'KeyDown', '説明は種類の名前で始まる: ' + PMLEventDescription(Ev));
  Ctx := DummyContext([]);
  Cap := TLogCapture.Create;
  try
    Ctx.Log.Output := @Cap.Output;
    PushBoth;
    Check(Cap.Count('papimela EVENT: ') = 0, 'ヒントが無ければ出さない');
    Ctx.Hints.SetHint(PML_HINT_EVENT_LOGGING, '1');
    PushBoth;
    Check((Cap.Count('papimela EVENT: KeyDown') = 1) and (Cap.Count('papimela EVENT: MouseMotion') = 0),
      '1: 積んだときに "papimela EVENT: " で出す。マウスの移動は出さない');
    Ctx.Hints.SetHint(PML_HINT_EVENT_LOGGING, '2');
    PushBoth;
    Check((Cap.Count('papimela EVENT: KeyDown') = 1) and (Cap.Count('papimela EVENT: MouseMotion') = 1),
      '2: マウスの移動も出す');
    Ctx.Hints.ResetHint(PML_HINT_EVENT_LOGGING);
    PushBoth;
    Check(Cap.Count('papimela EVENT: ') = 0, 'ヒントを消すと出さない');
    Ctx.Log.Output := @Ctx.Log.DefaultOutput;
  finally
    Ctx.Free;
    Cap.Free;
  end;
end;

begin
  WriteLn('test_hints — ヒントを使う側');
  WriteLn;
  TestServices;
  TestAppID;
  TestKeycodeOptions;
  TestRenderHints;
  TestEGLLibrary;
  TestThreadPolicy;
  TestImeUI;
  TestQuitOnLastWindow;
  TestSignals;
  TestEventLogging;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: SDL のヒントが papimela の機能に SDL と同じ約束で効く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
