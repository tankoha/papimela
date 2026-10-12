{
  test_hints — ヒントを使う側（SDL のヒントのうち papimela の機能に効くもの）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. どの部品からも Context の土台（ContextServices）に届く。Context 無しで作った物は nil
    2. AppID（SDL_GetAppID）: ヒント → FLATPAK_ID → 実行ファイルの名前
    3. PAPIMELA_KEYCODE_OPTIONS（SDL_HINT_KEYCODE_OPTIONS）と hide_numpad の置き換え
    4. PAPIMELA_RENDER_DRIVER（カンマ区切りで順に試す）と PAPIMELA_RENDER_VSYNC
    5. EGL のライブラリ名（PAPIMELA_EGL_LIBRARY が渡る先の PMLEGLLoad）

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
  SysUtils,
  PaPiMeLa,
  PaPiMeLa.Events.Keymap,
  PaPiMeLa.Platform.EGL;

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

begin
  WriteLn('test_hints — ヒントを使う側');
  WriteLn;
  TestServices;
  TestAppID;
  TestKeycodeOptions;
  TestRenderHints;
  TestEGLLibrary;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: SDL のヒントが papimela の機能に SDL と同じ約束で効く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
