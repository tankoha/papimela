{
  test_umbrella — uses PaPiMeLa 1 つで書けること、TPMLApplication（#45）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    このプログラムは SysUtils と PaPiMeLa しか uses しない。
    1. アンブレラ経由で、公開層の各ユニットの型・定数・関数・helper が使える
       （コンパイルが通ることが半分の検査。残りは値を見る）
    2. アンブレラを uses すればバックエンドが全部リンクされ、登録される
    3. TPMLApplication のループの約束: 呼ぶ順、結果の扱い、DoQuit を必ず呼ぶ、
       例外のとき、WaitForEvents、RunMain

  WHY:
    #45 の受け入れ検査。実装より先に書いた。アンブレラの中身は生成器が
    作るので、ここで全部の名前を並べることはしない（生成器の --check が
    公開層との食い違いを見る）。各ユニットから少なくとも 1 つずつと、
    別名にできない type helper（派生で置く）を必ず通す。

  実行前提: 無し。ビデオはダミーを名前で選ぶ。
}
program test_umbrella;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, Classes, StrUtils,
  PaPiMeLa;

var
  Failures: Integer = 0;

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

function Has(const ANames: TStringArray; const AName: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(ANames) do
    if ANames[I] = AName then
      Exit(True);
end;

function DummyOptions: TPMLContextOptions;
begin
  Result := TPMLContextOptions.Default;
  Result.PreferredVideo := 'dummy';
end;

{ ---- 1. アンブレラ経由の API ---- }

procedure TestApi;
var
  Ctx: TPMLContext;
  Win: TPMLWindow;
  R: TPMLRenderer;
  S: TPMLSurface;
  Ms: TMemoryStream;
  Raised: Boolean;
  O: TPMLContextOptions;
  T0: UInt64;
  Ev: TPMLEvent;
begin
  WriteLn('1. アンブレラ経由の API');
  // Keycodes と Events.Keymap（type helper は派生で置いてある）
  Check(TPMLScancode.UP.Name = 'Up', 'TPMLScancode.UP.Name（helper）');
  Check(PMLK_RETURN.Name = 'Return', 'PMLK_RETURN.Name（helper）');
  Check(PMLScancodeFromName('W') = TPMLScancode.W, 'PMLScancodeFromName（関数）');
  // Types
  Check(TPMLColor.Make(1, 2, 3).G = 2, 'TPMLColor.Make（record のメソッド）');
  Check(TPMLFRect.Make(0, 0, 2, 3).H = 3, 'TPMLFRect.Make');
  // Errors と Core
  O := TPMLContextOptions.Default;
  O.EventQueueCapacity := 0;
  Raised := False;
  try
    TPMLContext.Create([], O).Free;
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'EPMLArgument を捕まえられる（例外の別名）');
  // Time
  T0 := TPMLTimerService.TicksNS;
  PMLDelay(2);
  Check(TPMLTimerService.TicksNS - T0 >= 2 * PML_NS_PER_MS, 'PMLDelay と PML_NS_PER_MS（関数と定数）');

  Ctx := TPMLContext.Create([TPMLSubsystem.Video], DummyOptions);
  try
    // Video
    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('umbrella', 40, 20).Resizable);
    // Render（スコープ付き列挙の値も別名から引ける）
    R := TPMLRenderer.CreateForWindow(Win, 'software');
    R.SetLogicalPresentation(20, 10, TPMLLogicalPresentation.Letterbox);
    R.BlendMode := TPMLBlendMode.None;
    R.DrawColor := TPMLColor.Make(0, 0, 0);
    R.Clear;
    R.DrawColor := TPMLColor.Make(255, 255, 255);
    R.DebugText(0, 0, 'A');
    // Pixels と Surface
    S := R.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    try
      Check((S.Width = 40) and (PMLPixelFormatName(S.Format) <> ''),
        'ReadPixels と PMLPixelFormatName');
      Check(S.ReadPixel(4, 0).R = 255, 'DebugText が 2 倍で描かれている（A の 1 行目）');
      // Surface.BMP と IO
      Ms := TMemoryStream.Create;
      try
        PMLSaveBMP(Ms, S);
        Check(Ms.Size > 54, 'PMLSaveBMP');
      finally
        Ms.Free;
      end;
    finally
      S.Free;
    end;
    // Events
    // ウィンドウを作ったときのイベントが先に並んでいるので、Quit まで読み進める。
    Ctx.Events.PushSimple(TPMLEventKind.Quit);
    Raised := False;
    while Ctx.Events.Poll(Ev) do
      if Ev.Kind = TPMLEventKind.Quit then
        Raised := True;
    Check(Raised, 'イベントの種類（TPMLEventKind.Quit）');
    Win.Free;
  finally
    Ctx.Free;
  end;
  WriteLn;
end;

{ ---- 2. バックエンド ---- }

procedure TestBackends;
var
  F: TFileStream;
  Img: String;
begin
  WriteLn('2. アンブレラでバックエンドが全部入る');
  Check(Has(PMLVideoBackendNames, 'wayland') and Has(PMLVideoBackendNames, 'dummy'),
    'ビデオ: wayland と dummy');
  Check((Length(PMLVideoBackendNames) >= 2) and (PMLVideoBackendNames[0] = 'wayland')
    and (PMLVideoBackendNames[High(PMLVideoBackendNames)] = 'dummy'),
    '既定で最初に試すのは wayland、dummy は最後');
  Check(Has(PMLTextInputBackendNames, 'fcitx'), 'IME: fcitx');
  Check(Has(PMLRenderDriverNames, 'gles2') and Has(PMLRenderDriverNames, 'software'),
    'レンダラ: gles2 と software');
  F := TFileStream.Create(ParamStr(0), fmOpenRead or fmShareDenyNone);
  try
    SetLength(Img, F.Size);
    F.ReadBuffer(Img[1], F.Size);
  finally
    F.Free;
  end;
  Check(Pos(ReverseString('dnekcaBoediVdnalyaWLMPT'), Img) > 0,
    'Wayland のビデオが実行ファイルにリンクされている');
  WriteLn;
end;

{ ---- 3. TPMLApplication ---- }

type
  TScript = (Normal, InitFails, IterateRaises, QuitByEvent, WaitMode);

  TTestApp = class(TPMLApplication)
  protected
    function  DoInit(const AArgs: TStringArray): TPMLAppResult; override;
    function  DoIterate: TPMLAppResult; override;
    function  DoEvent(const AEvent: TPMLEvent): TPMLAppResult; override;
    procedure DoQuit(AResult: TPMLAppResult); override;
  public
    destructor Destroy; override;
  end;

var
  Script     : TScript;
  Log        : String;       // 呼ばれた順
  Iterations : Integer;
  QuitResult : TPMLAppResult;
  QuitCalls  : Integer;
  ContextAfterQuit: Boolean;  // DoQuit の後に Context が残っていたか
  Destroyed  : Integer;
  GotArgs    : String;
  UserKind   : TPMLEventKind;

function TTestApp.DoInit(const AArgs: TStringArray): TPMLAppResult;
begin
  Log := Log + 'init ';
  GotArgs := String.Join(',', AArgs);
  Context := TPMLContext.Create([TPMLSubsystem.Video], DummyOptions);
  UserKind := Context.Events.RegisterUserEvents(1);
  if Script = TScript.InitFails then
    Exit(TPMLAppResult.Failure);
  // 最初の DoIterate より前に DoEvent へ届くはずのイベント
  Context.Events.PushSimple(UserKind);
  if Script = TScript.WaitMode then
    Context.Events.PushSimple(TPMLEventKind.Quit);
  Result := TPMLAppResult.Continue;
end;

function TTestApp.DoIterate: TPMLAppResult;
begin
  Inc(Iterations);
  Log := Log + 'iter ';
  Result := TPMLAppResult.Continue;
  case Script of
    TScript.Normal:
      if Iterations = 3 then
        Result := TPMLAppResult.Success;
    TScript.IterateRaises:
      if Iterations = 2 then
        raise EPMLArgument.Create('boom');
    TScript.QuitByEvent:
      if Iterations = 2 then
        Context.Events.PushSimple(TPMLEventKind.Quit);
  else
  end;
  if Iterations > 50 then
    Result := TPMLAppResult.Failure;   // 止まらない実装で検査が回り続けないように
end;

function TTestApp.DoEvent(const AEvent: TPMLEvent): TPMLAppResult;
begin
  if AEvent.Kind = UserKind then
    Log := Log + 'user '
  else if AEvent.Kind = TPMLEventKind.Quit then
    Log := Log + 'quit-event ';
  // 既定の扱い（Quit で Success）を確かめるため、継承元に任せる
  Result := inherited DoEvent(AEvent);
end;

procedure TTestApp.DoQuit(AResult: TPMLAppResult);
begin
  Inc(QuitCalls);
  QuitResult := AResult;
  Log := Log + 'quit ';
  inherited DoQuit(AResult);
  ContextAfterQuit := Context <> nil;
end;

destructor TTestApp.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;

procedure Reset(AScript: TScript);
begin
  Script := AScript;
  Log := '';
  Iterations := 0;
  QuitResult := TPMLAppResult.Continue;
  QuitCalls := 0;
  ContextAfterQuit := True;
  GotArgs := '';
end;

function RunScript(AScript: TScript; AWait: Boolean = False): Integer;
var
  App: TTestApp;
begin
  Reset(AScript);
  App := TTestApp.Create;
  try
    App.WaitForEvents := AWait;
    Result := App.Run(['a', 'b']);
  finally
    App.Free;
  end;
end;

procedure TestApplication;
var
  Code: Integer;
  Raised: Boolean;
  Before: Integer;
begin
  WriteLn('3. TPMLApplication');

  Code := RunScript(TScript.Normal);
  Check(Code = 0, 'DoIterate が Success を返したら終了コード 0');
  Check(Log = 'init user iter iter iter quit ',
    '呼ぶ順: init → イベント → iter を 3 回 → quit（' + Log + '）');
  Check(GotArgs = 'a,b', 'DoInit に引数が渡る（' + GotArgs + '）');
  Check((QuitCalls = 1) and (QuitResult = TPMLAppResult.Success), 'DoQuit は 1 回、Success で');
  Check(not ContextAfterQuit, 'DoQuit の既定は Context を Free して nil に戻す');

  Code := RunScript(TScript.InitFails);
  Check(Code = 1, 'DoInit が Failure なら終了コード 1');
  Check(Log = 'init quit ', 'DoInit が失敗したら DoIterate を呼ばず DoQuit（' + Log + '）');
  Check(QuitResult = TPMLAppResult.Failure, 'DoQuit には Failure が渡る');
  Check(not ContextAfterQuit, '失敗しても DoInit で作った Context は片付く');

  Raised := False;
  try
    RunScript(TScript.IterateRaises);
  except
    on E: EPMLArgument do
      Raised := E.Message = 'boom';
  end;
  Check(Raised, 'DoIterate の例外は Run の外へ投げ直される');
  Check((QuitCalls = 1) and (QuitResult = TPMLAppResult.Failure),
    '例外のときも DoQuit(Failure) を先に呼ぶ（' + Log + '）');

  Code := RunScript(TScript.QuitByEvent);
  Check(Code = 0, 'Quit のイベントで終わる（DoEvent の既定は Quit で Success）');
  Check(Log = 'init user iter iter quit-event quit ',
    'Quit は次の周のイベントとして届き、DoIterate はもう呼ばれない（' + Log + '）');

  Code := RunScript(TScript.WaitMode, True);
  Check((Code = 0) and (Iterations = 0),
    'WaitForEvents なら DoIterate を呼ばずにイベントで回る（' + Log + '）');
  Check(Log = 'init user quit-event quit ', '届いた順に DoEvent（' + Log + '）');

  Reset(TScript.Normal);
  Before := Destroyed;
  Code := TPMLApplication.RunMain(TTestApp);
  Check((Code = 0) and (Iterations = 3), 'RunMain は作って回して終了コードを返す');
  Check(Destroyed = Before + 1, 'RunMain は作ったアプリを解放する');
  WriteLn;
end;

begin
  WriteLn('test_umbrella — uses PaPiMeLa だけで書く');
  WriteLn;
  TestApi;
  TestBackends;
  TestApplication;
  if Failures = 0 then
    WriteLn('=== 結論: uses PaPiMeLa 1 つで公開 API とバックエンドと TPMLApplication が揃う ===')
  else
  begin
    WriteLn(Format('=== 結論: %d 件失敗 ===', [Failures]));
    Halt(1);
  end;
end.
