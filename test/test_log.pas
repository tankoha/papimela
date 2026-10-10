{
  test_log — カテゴリと優先度で絞るログを検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. PAPIMELA_LOGGING（SDL_HINT_LOGGING と同じ書式）の解析。期待値は SDL 3.4.2 の実物で
       SDL_LOGGING を置いて測った表（docs/TEST-LOG.md の使い捨て検証）。papimela が直した
       行（D-55: 名前の先頭だけ比べる、D-56: DEBUG_INVOCATION で独自のカテゴリが ERROR の
       まま）は期待値を変え、名前に印を付けた
    2. papimela の既定（ABaseDefault。Context は MinimumLogLevel を渡す）
    3. ヒントが変わったら決め直す、環境変数、Free で呼び出しを外す
    4. SetPriorities / SetPriority / 独自のカテゴリ
    5. 絞り込み、末尾の改行、出力の差し替え、前置き、複数のスレッド
    6. 既定の出力（子のプロセスを作って標準エラーを読む）
    7. Context が Log・Hints・Properties を持つ
    8. Context を作る前のヒント（TPMLContextOptions.Hints。PAPIMELA_VIDEO・PAPIMELA_IME もヒントで選ぶ）

  WHY:
    #5 の受け入れ検査。実装より先に書き、空の実装で落ちることを確かめてから渡す。

  実行前提: cthreads（uses の先頭）。6. は自分自身を --emit で起動する。
}
program test_log;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils, Classes, Process,
  PaPiMeLa.Errors,
  PaPiMeLa.Threading,
  PaPiMeLa.Properties,
  PaPiMeLa.Log,
  PaPiMeLa.Core,
  PaPiMeLa.Backends;

function setenv(AName, AValue: PAnsiChar; AOverwrite: LongInt): LongInt; cdecl; external 'c';
function unsetenv(AName: PAnsiChar): LongInt; cdecl; external 'c';

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

const
  // 表の列: 組み込みの 0..9、独自の 1000 と -5
  CATS: array[0..11] of Integer = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 1000, -5);
  SDL_DEFAULT = '4 6 5 6 6 6 6 6 2 6 6 6';

function Row(ALog: TPMLLog): String;
var
  I: Integer;
begin
  Result := '';
  for I := Low(CATS) to High(CATS) do
  begin
    if I > 0 then
      Result := Result + ' ';
    Result := Result + IntToStr(Ord(ALog.GetPriority(CATS[I])));
  end;
end;

type
  THintCase = record
    Hint: String;
    Want: String;
    Note: String;   // '' なら SDL と同じ
  end;

const
  HINT_CASES: array[0..31] of THintCase = (
    (Hint: 'debug';                     Want: '3 3 3 3 3 3 3 3 3 3 3 3'; Note: ''),
    (Hint: '0';                         Want: '8 8 8 8 8 8 8 8 8 8 8 8'; Note: ''),
    (Hint: 'quiet';                     Want: '8 8 8 8 8 8 8 8 8 8 8 8'; Note: ''),
    (Hint: 'trace';                     Want: '1 1 1 1 1 1 1 1 1 1 1 1'; Note: ''),
    (Hint: '8';                         Want: SDL_DEFAULT;               Note: ''),
    (Hint: 'assert';                    Want: SDL_DEFAULT;               Note: ''),
    (Hint: '*=warn,app=debug';          Want: '3 5 5 5 5 5 5 5 5 5 5 5'; Note: ''),
    (Hint: 'app=debug,*=warn';          Want: '3 5 5 5 5 5 5 5 5 5 5 5'; Note: ''),
    (Hint: '*=debug';                   Want: '3 3 3 3 3 3 3 3 3 3 3 3'; Note: ''),
    (Hint: '5=debug';                   Want: '4 6 5 6 6 3 6 6 2 6 6 6'; Note: ''),
    (Hint: '5x=debug';                  Want: '4 6 5 6 6 3 6 6 2 6 6 6'; Note: ''),
    (Hint: '1000=debug';                Want: '4 6 5 6 6 6 6 6 2 6 3 6'; Note: ''),
    (Hint: '-1=debug';                  Want: SDL_DEFAULT;               Note: ''),
    (Hint: 'app=8';                     Want: SDL_DEFAULT;               Note: ''),
    (Hint: 'app=0';                     Want: '8 6 5 6 6 6 6 6 2 6 6 6'; Note: ''),
    (Hint: 'app=7';                     Want: '7 6 5 6 6 6 6 6 2 6 6 6'; Note: ''),
    (Hint: 'app=debug,';                Want: '3 6 5 6 6 6 6 6 2 6 6 6'; Note: ''),
    (Hint: 'app=debug,,video=trace';    Want: '3 6 5 6 6 6 6 6 2 6 6 6'; Note: ''),
    (Hint: 'garbage=debug,video=trace'; Want: '4 6 5 6 6 1 6 6 2 6 6 6'; Note: ''),
    (Hint: 'video=debug,app';           Want: '4 6 5 6 6 3 6 6 2 6 6 6'; Note: ''),
    (Hint: 'video=debugX';              Want: SDL_DEFAULT;               Note: ''),
    (Hint: 'app=info , video=debug';    Want: SDL_DEFAULT;               Note: ''),
    (Hint: 'app=info, video=debug';     Want: SDL_DEFAULT;               Note: ''),
    (Hint: 'APP=DEBUG';                 Want: '3 6 5 6 6 6 6 6 2 6 6 6'; Note: ''),
    (Hint: 'Video=Verbose,TEST=quiet,gpu=2'; Want: '4 6 5 6 6 2 6 6 8 2 6 6'; Note: ''),
    (Hint: '';                          Want: SDL_DEFAULT; Note: 'D-55: SDL は全部 8（空が quiet に一致）'),
    (Hint: 't';                         Want: SDL_DEFAULT; Note: 'D-55: SDL は全部 1（TRACE の先頭）'),
    (Hint: 'a=debug';                   Want: SDL_DEFAULT; Note: 'D-55: SDL は APP が 3'),
    (Hint: '=debug';                    Want: SDL_DEFAULT; Note: 'D-55: SDL は APP が 3'),
    (Hint: 'app=';                      Want: SDL_DEFAULT; Note: 'D-55: SDL は APP が 8'),
    (Hint: 'app=,video=debug';          Want: '4 6 5 6 6 3 6 6 2 6 6 6'; Note: 'D-55: SDL は APP が 8'),
    (Hint: 'video=t';                   Want: SDL_DEFAULT; Note: 'D-55: SDL は VIDEO が 1'));

{ ---- 記録係 ---- }

type
  TCapture = class
  public
    Lines: TStringList;
    Hits: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Output(ACategory: Integer; APriority: TPMLLogPriority; const AMessage: String);
    procedure HintSeen(const AName: String; const AOld, ANew: TPMLHintValue);
  end;

constructor TCapture.Create;
begin
  inherited Create;
  Lines := TStringList.Create;
end;

destructor TCapture.Destroy;
begin
  Lines.Free;
  inherited Destroy;
end;

procedure TCapture.Output(ACategory: Integer; APriority: TPMLLogPriority; const AMessage: String);
begin
  Lines.Add(Format('%d %d [%s]', [ACategory, Ord(APriority), AMessage]));
end;

procedure TCapture.HintSeen(const AName: String; const AOld, ANew: TPMLHintValue);
begin
  Inc(Hits);
end;

function Raises(AProc: TProcedure): Boolean;
begin
  Result := False;
  try
    AProc();
  except
    on E: EPMLArgument do
      Result := True;
  end;
end;

var
  GLog: TPMLLog;

{ ---- 1. ヒントの解析 ---- }

procedure TestHintParsing;
var
  H: TPMLHints;
  L: TPMLLog;
  I, Bad: Integer;
  C: THintCase;
  Got: String;
begin
  WriteLn('1. PAPIMELA_LOGGING の解析（SDL の既定。期待値は SDL 3.4.2 の実測）');
  H := TPMLHints.Create;
  L := TPMLLog.Create(H);
  try
    Check(Row(L) = SDL_DEFAULT, 'ヒントが無ければ SDL の既定（app=info,assert=warn,test=verbose,*=error）: ' + Row(L));
    Bad := 0;
    for I := Low(HINT_CASES) to High(HINT_CASES) do
    begin
      C := HINT_CASES[I];
      if C.Note <> '' then
        Continue;
      H.SetHint(PML_HINT_LOGGING, C.Hint);
      Got := Row(L);
      if Got <> C.Want then
      begin
        WriteLn(Format('  [INFO] "%s" -> %s（期待 %s）', [C.Hint, Got, C.Want]));
        Inc(Bad);
      end;
    end;
    Check(Bad = 0, 'SDL と同じ結果になる行がすべて一致する');
    for I := Low(HINT_CASES) to High(HINT_CASES) do
    begin
      C := HINT_CASES[I];
      if C.Note = '' then
        Continue;
      H.SetHint(PML_HINT_LOGGING, C.Hint);
      Got := Row(L);
      Check(Got = C.Want, Format('"%s" -> %s（%s）', [C.Hint, Got, C.Note]));
    end;
    H.ResetHint(PML_HINT_LOGGING);
    Check(Row(L) = SDL_DEFAULT, 'ヒントを消すと既定に戻る');

    setenv('DEBUG_INVOCATION', '1', 1);
    L.ResetPriorities;
    Check(Row(L) = '3 3 5 3 3 3 3 3 2 3 3 3',
      'DEBUG_INVOCATION=1: assert=warn,test=verbose,*=debug（SDL は独自のカテゴリが 6 のまま: D-56）: ' + Row(L));
    setenv('DEBUG_INVOCATION', '0', 1);
    L.ResetPriorities;
    Check(Row(L) = SDL_DEFAULT, 'DEBUG_INVOCATION=0 は無いのと同じ');
    setenv('DEBUG_INVOCATION', '', 1);
    L.ResetPriorities;
    Check(Row(L) = SDL_DEFAULT, 'DEBUG_INVOCATION が空なら無いのと同じ');
    unsetenv('DEBUG_INVOCATION');
  finally
    L.Free;
    H.Free;
  end;
end;

{ ---- 2. papimela の既定 ---- }

procedure TestBaseDefault;
var
  H: TPMLHints;
  L: TPMLLog;
begin
  WriteLn;
  WriteLn('2. papimela の既定（ABaseDefault）');
  H := TPMLHints.Create;
  L := TPMLLog.Create(H, TPMLLogPriority.Info);
  try
    Check(Row(L) = '4 4 4 4 4 4 4 4 4 4 4 4', 'Info を渡すと全部 Info（独自のカテゴリも）');
    H.SetHint(PML_HINT_LOGGING, 'video=debug');
    Check(Row(L) = '4 4 4 4 4 3 4 4 4 4 4 4', 'ヒントで決めたカテゴリだけ変わる');
    H.SetHint(PML_HINT_LOGGING, '*=warn');
    Check(Row(L) = '5 5 5 5 5 5 5 5 5 5 5 5', '"*" は残り全部');
    H.SetHint(PML_HINT_LOGGING, 'quiet');
    Check(Row(L) = '8 8 8 8 8 8 8 8 8 8 8 8', '"quiet" で全部黙る');
    H.ResetHint(PML_HINT_LOGGING);
    setenv('DEBUG_INVOCATION', '1', 1);
    L.ResetPriorities;
    Check(Row(L) = '3 3 3 3 3 3 3 3 3 3 3 3', 'DEBUG_INVOCATION なら Debug まで下げる');
    unsetenv('DEBUG_INVOCATION');
  finally
    L.Free;
    H.Free;
  end;
  L := TPMLLog.Create(nil, TPMLLogPriority.Error_);
  try
    Check(Row(L) = '6 6 6 6 6 6 6 6 6 6 6 6', 'ヒント無し（nil）でも作れる');
  finally
    L.Free;
  end;
end;

{ ---- 3. ヒントの変化・環境変数・Free ---- }

procedure TestHintLifecycle;
var
  H: TPMLHints;
  L: TPMLLog;
  Cap: TCapture;
begin
  WriteLn;
  WriteLn('3. ヒントの変化と環境変数');
  setenv(PML_HINT_LOGGING, 'render=trace', 1);
  H := TPMLHints.Create;
  Cap := TCapture.Create;
  try
    L := TPMLLog.Create(H);
    try
      Check(L.GetPriority(PML_LOG_CATEGORY_RENDER) = TPMLLogPriority.Trace, '環境変数 PAPIMELA_LOGGING を読む');
      Check(not H.SetHint(PML_HINT_LOGGING, 'render=info'), '環境変数があると Normal のヒントは置けない');
      H.SetHint(PML_HINT_LOGGING, 'render=info', TPMLHintPriority.Override);
      Check(L.GetPriority(PML_LOG_CATEGORY_RENDER) = TPMLLogPriority.Info, 'Override で置けば決め直す');
      unsetenv(PML_HINT_LOGGING);
      H.ResetHint(PML_HINT_LOGGING);
      Check(Row(L) = SDL_DEFAULT, 'Reset で既定に戻る');
      L.SetPriority(PML_LOG_CATEGORY_RENDER, TPMLLogPriority.Debug);
      H.SetHint(PML_HINT_LOGGING, 'video=warn');
      Check((L.GetPriority(PML_LOG_CATEGORY_RENDER) = TPMLLogPriority.Error_)
        and (L.GetPriority(PML_LOG_CATEGORY_VIDEO) = TPMLLogPriority.Warn),
        'ヒントが変わると、手で置いた優先度も含めて全部決め直す（SDL と同じ）');
    finally
      L.Free;
    end;
    // Log を壊した後もヒントを置ける。Log が呼び出しを外し忘れても、解放した領域を偶然読めて
    // しまうのでこの検査では捕まらない（変異で確かめた。docs/TEST-LOG.md の T-46）
    H.AddCallback(PML_HINT_LOGGING, @Cap.HintSeen);
    Cap.Hits := 0;
    H.SetHint(PML_HINT_LOGGING, 'app=trace');
    Check(Cap.Hits = 1, 'Log を Free した後もヒントを置け、残りの呼び出しが呼ばれる');
  finally
    H.Free;
    Cap.Free;
  end;
end;

{ ---- 4. 優先度を置く ---- }

procedure PrefixInvalid;
begin
  GLog.SetPriorityPrefix(TPMLLogPriority.Invalid, 'x');
end;

procedure PrefixQuiet;
begin
  GLog.SetPriorityPrefix(TPMLLogPriority.Quiet, 'x');
end;

procedure TestSetPriority;
var
  L: TPMLLog;
begin
  WriteLn;
  WriteLn('4. 優先度を置く');
  L := TPMLLog.Create(nil);
  try
    L.SetPriorities(TPMLLogPriority.Warn);
    Check(Row(L) = '5 5 5 5 5 5 5 5 5 5 5 5', 'SetPriorities は独自のカテゴリも含めて全部');
    L.SetPriority(1000, TPMLLogPriority.Debug);
    L.SetPriority(-5, TPMLLogPriority.Critical);
    L.SetPriority(3, TPMLLogPriority.Trace);
    Check(Row(L) = '5 5 5 1 5 5 5 5 5 5 3 7', '組み込みも独自のカテゴリも個別に置ける');
    Check(L.GetPriority(77) = TPMLLogPriority.Warn, '置いていない独自のカテゴリは既定の優先度');
    L.SetPriority(1000, TPMLLogPriority.Invalid);
    Check(L.GetPriority(1000) = TPMLLogPriority.Warn, '独自のカテゴリに Invalid を置くと既定に戻る');
    L.SetPriorities(TPMLLogPriority.Info);
    Check(Row(L) = '4 4 4 4 4 4 4 4 4 4 4 4', 'SetPriorities は個別に置いた独自のカテゴリも消す');
    L.ResetPriorities;
    Check(Row(L) = SDL_DEFAULT, 'ResetPriorities で既定に戻る');
  finally
    L.Free;
  end;
end;

{ ---- 5. 出力 ---- }

type
  TLogWorker = class(TPMLThread)
  public
    Log: TPMLLog;
    Index: Integer;
  protected
    function Run: Integer; override;
  end;

const
  WORKERS = 4;
  WORKER_LINES = 2000;

function TLogWorker.Run: Integer;
var
  I: Integer;
begin
  for I := 1 to WORKER_LINES do
    Log.Info(PML_LOG_CATEGORY_APPLICATION, Format('w%d %d', [Index, I]));
  Result := 0;
end;

function Joined(AList: TStringList): String;
begin
  Result := StringReplace(Trim(AList.Text), LineEnding, ' | ', [rfReplaceAll]);
end;

procedure TestOutput;
var
  L: TPMLLog;
  Cap: TCapture;
  M, D: TMethod;
  W: array[0..WORKERS - 1] of TLogWorker;
  I: Integer;
  Out: TPMLLogOutput;
begin
  WriteLn;
  WriteLn('5. 絞り込みと出力');
  Cap := TCapture.Create;
  L := TPMLLog.Create(nil);
  try
    Out := L.Output;
    M := TMethod(Out);
    Out := @L.DefaultOutput;
    D := TMethod(Out);
    Check((M.Code = D.Code) and (M.Data = D.Data), '作った時点の出力は DefaultOutput');
    L.Output := @Cap.Output;
    L.Log('hello');
    L.Info(PML_LOG_CATEGORY_VIDEO, 'dropped');
    L.Error(PML_LOG_CATEGORY_VIDEO, 'video error');
    L.Critical(PML_LOG_CATEGORY_VIDEO, 'video critical');
    L.Trace(PML_LOG_CATEGORY_APPLICATION, 'dropped');
    L.Debug(PML_LOG_CATEGORY_APPLICATION, 'dropped');
    L.Warn(PML_LOG_CATEGORY_APPLICATION, 'app warn');
    L.Verbose(PML_LOG_CATEGORY_TEST, 'test verbose');
    L.Trace(PML_LOG_CATEGORY_TEST, 'dropped');
    L.LogMessage(PML_LOG_CATEGORY_APPLICATION, TPMLLogPriority.Invalid, 'dropped');
    L.LogMessageFmt(5000, TPMLLogPriority.Error_, '%d-%s', [3, 'x']);
    Check(Joined(Cap.Lines) = '0 4 [hello] | 5 6 [video error] | 5 7 [video critical] | 0 5 [app warn] | 8 2 [test verbose] | 5000 6 [3-x]',
      '優先度がカテゴリの優先度より低い行だけを捨てる: ' + Joined(Cap.Lines));
    Cap.Lines.Clear;
    L.Log('a'#10);
    L.Log('b'#13#10);
    L.Log('c'#10#10);
    L.Log('d'#13);
    L.Log(#10);
    L.Log('');
    Check((Cap.Lines.Count = 6) and (Cap.Lines[0] = '0 4 [a]') and (Cap.Lines[1] = '0 4 [b]')
      and (Cap.Lines[2] = '0 4 [c'#10']') and (Cap.Lines[3] = '0 4 [d'#13']') and (Cap.Lines[4] = '0 4 []')
      and (Cap.Lines[5] = '0 4 []'), '末尾の LF を 1 つ（その前の CR も）落とす');
    Cap.Lines.Clear;
    L.Output := nil;
    L.Log('nowhere');
    Check(Cap.Lines.Count = 0, '出力が nil なら何もしない');
    L.Output := @Cap.Output;

    Check((L.PriorityPrefix(TPMLLogPriority.Warn) = 'WARNING: ') and (L.PriorityPrefix(TPMLLogPriority.Error_) = 'ERROR: ')
      and (L.PriorityPrefix(TPMLLogPriority.Critical) = 'ERROR: ') and (L.PriorityPrefix(TPMLLogPriority.Info) = '')
      and (L.PriorityPrefix(TPMLLogPriority.Invalid) = '') and (L.PriorityPrefix(TPMLLogPriority.Quiet) = ''),
      '既定の前置き（SDL と同じ）');
    L.SetPriorityPrefix(TPMLLogPriority.Warn, 'W> ');
    L.SetPriorityPrefix(TPMLLogPriority.Error_, '');
    L.SetPriorityPrefix(TPMLLogPriority.Info, 'I: ');
    Check((L.PriorityPrefix(TPMLLogPriority.Warn) = 'W> ') and (L.PriorityPrefix(TPMLLogPriority.Error_) = '')
      and (L.PriorityPrefix(TPMLLogPriority.Critical) = 'ERROR: ') and (L.PriorityPrefix(TPMLLogPriority.Info) = 'I: '),
      '前置きを置ける（空も「前置き無し」として置ける）');
    GLog := L;
    Check(Raises(@PrefixInvalid) and Raises(@PrefixQuiet), 'Invalid と Quiet の前置きは EPMLArgument');

    Cap.Lines.Clear;
    for I := 0 to WORKERS - 1 do
    begin
      W[I] := TLogWorker.Create('log' + IntToStr(I), True);
      W[I].Log := L;
      W[I].Index := I;
    end;
    for I := 0 to WORKERS - 1 do
      W[I].Start;
    for I := 0 to WORKERS - 1 do
    begin
      W[I].WaitFor;
      W[I].Free;
    end;
    Check(Cap.Lines.Count = WORKERS * WORKER_LINES, Format('%d スレッドから %d 行ずつ書いて、出力は 1 つずつ呼ばれる（%d 行）',
      [WORKERS, WORKER_LINES, Cap.Lines.Count]));
  finally
    L.Free;
    Cap.Free;
  end;
end;

{ ---- 6. 既定の出力 ---- }

procedure Emit;
var
  L: TPMLLog;
begin
  L := TPMLLog.Create(nil);
  try
    L.Error(PML_LOG_CATEGORY_VIDEO, 'boom'#10);
    L.Warn(PML_LOG_CATEGORY_APPLICATION, 'careful');
    L.Info(PML_LOG_CATEGORY_APPLICATION, 'plain');
    L.Info(PML_LOG_CATEGORY_VIDEO, 'dropped');
    L.SetPriorityPrefix(TPMLLogPriority.Info, 'I: ');
    L.Info(PML_LOG_CATEGORY_APPLICATION, 'prefixed');
  finally
    L.Free;
  end;
end;

procedure TestDefaultOutput;
var
  P: TProcess;
  Err, StdOut: TStringList;
begin
  WriteLn;
  WriteLn('6. 既定の出力（標準エラー）');
  Err := TStringList.Create;
  StdOut := TStringList.Create;
  P := TProcess.Create(nil);
  try
    P.Executable := ParamStr(0);
    P.Parameters.Add('--emit');
    P.Options := [poWaitOnExit, poUsePipes];
    P.Execute;
    Err.LoadFromStream(P.Stderr);
    StdOut.LoadFromStream(P.Output);
    Check(Joined(Err) = 'ERROR: boom | WARNING: careful | plain | I: prefixed',
      '「前置き + 本文」を 1 行ずつ: ' + Joined(Err));
    Check(StdOut.Count = 0, '標準出力には何も出さない');
  finally
    P.Free;
    Err.Free;
    StdOut.Free;
  end;
end;

{ ---- 7. Context ---- }

procedure TestContext;
var
  Ctx: TPMLContext;
  Opts: TPMLContextOptions;
begin
  WriteLn;
  WriteLn('7. Context が持つもの');
  unsetenv(PML_HINT_LOGGING);
  Ctx := TPMLContext.Create([]);
  try
    Check((Ctx.Log <> nil) and (Ctx.Hints <> nil) and (Ctx.Properties <> nil), 'Log・Hints・Properties がある');
    Check(Row(Ctx.Log) = '4 4 4 4 4 4 4 4 4 4 4 4', '既定は全部 Info（MinimumLogLevel の既定。backend の行が出る）');
    Ctx.Hints.SetHint(PML_HINT_LOGGING, 'video=error');
    Check(Ctx.Log.GetPriority(PML_LOG_CATEGORY_VIDEO) = TPMLLogPriority.Error_, 'Context のヒントで Log が決め直す');
    Ctx.Properties.SetNumber('x', 1);
    Check(Ctx.Properties.GetNumber('x') = 1, '大域のプロパティ（SDL_GetGlobalProperties）');
  finally
    Ctx.Free;
  end;
  Opts := TPMLContextOptions.Default;
  Opts.MinimumLogLevel := TPMLLogPriority.Warn;
  Ctx := TPMLContext.Create([], Opts);
  try
    Check(Row(Ctx.Log) = '5 5 5 5 5 5 5 5 5 5 5 5', 'MinimumLogLevel を Warn にすると全部 Warn');
  finally
    Ctx.Free;
  end;
end;

{ ---- 8. Context を作る前のヒント ---- }

function CreateRaises(ASubsystems: TPMLSubsystems; const AOptions: TPMLContextOptions): Boolean;
var
  Ctx: TPMLContext;
begin
  Result := False;
  try
    Ctx := TPMLContext.Create(ASubsystems, AOptions);
    Ctx.Free;
  except
    on E: EPMLUnsupported do
      Result := True;
  end;
end;

procedure TestHintsBeforeContext;
var
  Ctx: TPMLContext;
  Opts: TPMLContextOptions;
begin
  WriteLn;
  WriteLn('8. Context を作る前のヒント（TPMLContextOptions.Hints）');
  unsetenv(PML_HINT_LOGGING);
  unsetenv(PML_HINT_VIDEO);
  unsetenv(PML_HINT_IME);
  Opts := TPMLContextOptions.Default;
  Check(Opts.Hints.Count = 0, '既定では空');
  Opts.Hints.Add(PML_HINT_LOGGING, 'video=error');
  Opts.Hints.Add(PML_HINT_VIDEO, 'dummy');
  Check(Opts.Hints.Count = 2, 'Add で足せる');
  Ctx := TPMLContext.Create([TPMLSubsystem.Video], Opts);
  try
    Check(Ctx.Log.GetPriority(PML_LOG_CATEGORY_VIDEO) = TPMLLogPriority.Error_, 'ログはできた時点でヒントに従う');
    Check(Ctx.Hints.GetHint(PML_HINT_LOGGING) = 'video=error', '置いたヒントは Ctx.Hints から読める');
    Check(Ctx.Video.BackendName = 'dummy', 'PAPIMELA_VIDEO のヒントでビデオのバックエンドを選ぶ');
  finally
    Ctx.Free;
  end;

  // 環境変数もヒントとして読む（起動後に setenv で置いたものも見える）
  setenv(PML_HINT_VIDEO, 'nosuch', 1);
  Check(CreateRaises([TPMLSubsystem.Video], TPMLContextOptions.Default),
    '環境変数 PAPIMELA_VIDEO=nosuch を読んで断る（libc の getenv で読む）');
  Opts := TPMLContextOptions.Default;
  Opts.Hints.Add(PML_HINT_VIDEO, 'dummy');
  Check(CreateRaises([TPMLSubsystem.Video], Opts), 'Normal のヒントより環境変数が強い（SDL と同じ）');
  Opts := TPMLContextOptions.Default;
  Opts.Hints.Add(PML_HINT_VIDEO, 'dummy', TPMLHintPriority.Override);
  Ctx := TPMLContext.Create([TPMLSubsystem.Video], Opts);
  try
    Check(Ctx.Video.BackendName = 'dummy', 'Override のヒントは環境変数より強い');
  finally
    Ctx.Free;
  end;
  Opts := TPMLContextOptions.Default;
  Opts.PreferredVideo := 'dummy';
  Ctx := TPMLContext.Create([TPMLSubsystem.Video], Opts);
  try
    Check((Ctx.Video.BackendName = 'dummy') and (Ctx.Hints.GetHint(PML_HINT_VIDEO) = 'dummy'),
      'PreferredVideo は Override のヒントを置く近道（今までどおり環境変数より強い）');
  finally
    Ctx.Free;
  end;
  unsetenv(PML_HINT_VIDEO);

  Opts := TPMLContextOptions.Default;
  Opts.Hints.Add(PML_HINT_IME, 'none');
  Ctx := TPMLContext.Create([TPMLSubsystem.TextInput], Opts);
  try
    Check(Ctx.TextInput.BackendName = 'none', 'PAPIMELA_IME のヒントで IME のバックエンドを選ぶ');
  finally
    Ctx.Free;
  end;
  setenv(PML_HINT_IME, 'nosuch', 1);
  Check(CreateRaises([TPMLSubsystem.TextInput], TPMLContextOptions.Default), '環境変数 PAPIMELA_IME も読む');
  Opts := TPMLContextOptions.Default;
  Opts.PreferredTextInput := 'none';
  Ctx := TPMLContext.Create([TPMLSubsystem.TextInput], Opts);
  try
    Check(Ctx.TextInput.BackendName = 'none', 'PreferredTextInput も環境変数より強い');
  finally
    Ctx.Free;
  end;
  unsetenv(PML_HINT_IME);
end;

begin
  if ParamStr(1) = '--emit' then
  begin
    Emit;
    Exit;
  end;
  WriteLn('test_log — カテゴリと優先度で絞るログ');
  WriteLn;
  unsetenv(PML_HINT_LOGGING);
  unsetenv('DEBUG_INVOCATION');
  TestHintParsing;
  TestBaseDefault;
  TestHintLifecycle;
  TestSetPriority;
  TestOutput;
  TestDefaultOutput;
  TestContext;
  TestHintsBeforeContext;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: ログが SDL の約束と papimela の直した所どおりに絞って出す ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
