{
  PaPiMeLa.Log — カテゴリと優先度で絞るログ

  Origin : ported from SDL (src/SDL_log.c)
           Scope: カテゴリごとの優先度の表と、それを SDL_HINT_LOGGING の書式で
           決め直す手順（ResetPriorities と、その解析）、優先度ごとの前置き、
           出力の関数の差し替え、末尾の改行を落とすこと。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #5

  WHAT:
    TPMLLog（SDL_Log* 系）。Context が 1 つ持つ（Context.Log）。ヒント
    PML_HINT_LOGGING（PAPIMELA_LOGGING）を見ていて、変われば優先度を決め直す。

  WHY:
    SDL は優先度の表と出力の関数を大域に持つ。papimela はこのオブジェクトの
    フィールドに持つ。

  RESOLVED:
    - 優先度の数の値は SDL_LogPriority と同じ。Quiet は SDL_LOG_PRIORITY_COUNT
      （ヒントの "quiet" と "0"。何も通さない）
    - カテゴリは Integer。0..18 は組み込み（PML_LOG_CATEGORY_*）、それ以外（負の数も）は
      アプリの独自のカテゴリで、個別に置かなければ「既定の優先度」
    - ヒントで決まらなかったカテゴリの優先度は、作るときの ABaseDefault で決める。
      Invalid なら SDL と同じ既定。Context は TPMLContextOptions.MinimumLogLevel（既定 Info）
      を渡すので、papimela の既定では全部のカテゴリが Info から出る（SDL は APP 以外 ERROR）
    - ヒントの名前と優先度の名前は、大文字小文字を区別せずに全体で比べる。SDL は先頭だけ
      比べるので、"a=debug" が APP に、空の値が "quiet" に一致する（D-55）
    - DEBUG_INVOCATION のとき、独自のカテゴリも Debug にする。SDL は ERROR のまま（D-56）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Log;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Threading,
  PaPiMeLa.Properties;

const
  PML_LOG_CATEGORY_APPLICATION = 0;
  PML_LOG_CATEGORY_ERROR       = 1;
  PML_LOG_CATEGORY_ASSERT      = 2;
  PML_LOG_CATEGORY_SYSTEM      = 3;
  PML_LOG_CATEGORY_AUDIO       = 4;
  PML_LOG_CATEGORY_VIDEO       = 5;
  PML_LOG_CATEGORY_RENDER      = 6;
  PML_LOG_CATEGORY_INPUT       = 7;
  PML_LOG_CATEGORY_TEST        = 8;
  PML_LOG_CATEGORY_GPU         = 9;
  // 10..18 は SDL が将来のために取ってある。アプリの独自のカテゴリはこれから後。
  PML_LOG_CATEGORY_CUSTOM      = 19;

type
  // 数の値は SDL_LogPriority と同じ。Quiet は SDL_LOG_PRIORITY_COUNT（何も通さない）。
  TPMLLogPriority = (Invalid, Trace, Verbose, Debug, Info, Warn, Error_, Critical, Quiet);

  // ログの 1 行を受け取る。Log の排他を持ったまま呼ばれる（同時には 1 つだけ）。
  TPMLLogOutput = procedure(ACategory: Integer; APriority: TPMLLogPriority;
    const AMessage: String) of object;

  { ログ（SDL_Log* 系）。どのスレッドから使ってもよい。

    優先度が、そのカテゴリの優先度より低い行は捨てる。残った行は末尾の改行
    （LF、その前の CR も）を 1 つ落として Output へ渡す。Output が nil なら何もしない。 }
  TPMLLog = class sealed
  strict private
    FLock          : TPMLMutex;          // 優先度の表
    FOutputLock    : TPMLMutex;          // 出力の関数と前置き
    FHints         : TPMLHints;          // 借りている。nil ならヒントを読まない
    FBaseDefault   : TPMLLogPriority;
    FPriorities    : array[0..PML_LOG_CATEGORY_CUSTOM - 1] of TPMLLogPriority;
    FCustomCats    : array of Integer;           // 個別に置いた独自のカテゴリ
    FCustomPrios   : array of TPMLLogPriority;   // FCustomCats と同じ並び
    FDefaultPrio   : TPMLLogPriority;            // それ以外の独自のカテゴリ
    FPrefixes      : array[TPMLLogPriority] of String;
    FPrefixSet     : array[TPMLLogPriority] of Boolean;
    FOutput        : TPMLLogOutput;
    procedure HintChanged(const AName: String; const AOld, ANew: TPMLHintValue);
    // SDL_LOGGING の書式の文字列で、Invalid の欄を埋める（ParseLogPriorities）。
    procedure ParsePriorities(const AHint: String);
    function  GetOutput: TPMLLogOutput;
    procedure SetOutput(AValue: TPMLLogOutput);
  public
    { AHints の PML_HINT_LOGGING を見る（AHints は Log より長生きしなければならない。
      nil ならヒントを読まない）。作った時点で ResetPriorities をする。
      ABaseDefault: ヒントで決まらなかったカテゴリの優先度（ResetPriorities の注）。 }
    constructor Create(AHints: TPMLHints;
      ABaseDefault: TPMLLogPriority = TPMLLogPriority.Invalid);
    destructor Destroy; override;

    // SDL_SetLogPriorities。全部のカテゴリ（独自のものも）を APriority にする。
    procedure SetPriorities(APriority: TPMLLogPriority);
    // SDL_SetLogPriority。独自のカテゴリに Invalid を置くと「既定の優先度」に戻る。
    procedure SetPriority(ACategory: Integer; APriority: TPMLLogPriority);
    // SDL_GetLogPriority。
    function  GetPriority(ACategory: Integer): TPMLLogPriority;
    { SDL_ResetLogPriorities。全部を Invalid にしてからヒントを読み、残った Invalid を埋める。
      - ABaseDefault が Invalid（SDL と同じ）: APP は Info、ASSERT は Warn、TEST は Verbose、
        他は Error_、独自のカテゴリも Error_
      - ABaseDefault がそれ以外: 全部 ABaseDefault
      環境変数 DEBUG_INVOCATION が空でなく '0' で始まらなければ、上で Info と Error_ と
      ABaseDefault になるところを、Debug より高ければ Debug にする。 }
    procedure ResetPriorities;

    // SDL_SetLogPriorityPrefix。APriority が Invalid か Quiet なら EPMLArgument。
    procedure SetPriorityPrefix(APriority: TPMLLogPriority; const APrefix: String);
    { 行の前に付ける文字列。置いていなければ Warn は 'WARNING: '、Error_ と Critical は
      'ERROR: '、他は ''。Invalid と Quiet は ''。 }
    function  PriorityPrefix(APriority: TPMLLogPriority): String;

    // SDL_Log（APP、Info）。
    procedure Log(const AMessage: String);
    procedure Trace(ACategory: Integer; const AMessage: String);
    procedure Verbose(ACategory: Integer; const AMessage: String);
    procedure Debug(ACategory: Integer; const AMessage: String);
    procedure Info(ACategory: Integer; const AMessage: String);
    procedure Warn(ACategory: Integer; const AMessage: String);
    procedure Error(ACategory: Integer; const AMessage: String);
    procedure Critical(ACategory: Integer; const AMessage: String);
    // SDL_LogMessage。
    procedure LogMessage(ACategory: Integer; APriority: TPMLLogPriority;
      const AMessage: String);
    procedure LogMessageFmt(ACategory: Integer; APriority: TPMLLogPriority;
      const AFmt: String; const AArgs: array of const);

    // 既定の出力（SDL_GetDefaultLogOutputFunction）。標準エラーへ「前置き + 本文」の 1 行。
    procedure DefaultOutput(ACategory: Integer; APriority: TPMLLogPriority;
      const AMessage: String);
    // 出力の関数。作った時点では DefaultOutput。nil にすると何も出さない。
    property  Output: TPMLLogOutput read GetOutput write SetOutput;
  end;

implementation

uses
  StrUtils;

const
  DEFAULT_CATEGORY = -1;
  CATEGORY_NAMES: array[0..9] of String = ('APP', 'ERROR', 'ASSERT', 'SYSTEM', 'AUDIO', 'VIDEO', 'RENDER', 'INPUT', 'TEST', 'GPU');
  PRIORITY_NAMES: array[TPMLLogPriority] of String = ('', 'TRACE', 'VERBOSE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'CRITICAL', '');

function c_getenv(AName: PAnsiChar): PAnsiChar; cdecl; external 'c' name 'getenv';

function DebugInvocation: Boolean;
var
  P: PAnsiChar;
begin
  P := c_getenv('DEBUG_INVOCATION');
  Result := (P <> nil) and (P^ <> #0) and (P^ <> '0');
end;

function LeadingNumber(const S: String): Integer;
var
  I, Len: Integer;
  N: Integer;
begin
  I := 1;
  Len := Length(S);
  N := 0;
  while (I <= Len) and (S[I] in ['0'..'9']) do
  begin
    N := N * 10 + Ord(S[I]) - Ord('0');
    if N > 100000000 then
    begin
      N := 100000000;
      Break;
    end;
    Inc(I);
  end;
  Result := N;
end;

{ PORT-NOTE(bug): SDL の ParseLogCategory / ParseLogPriority は SDL_strncasecmp で「書いた側の長さ」
  しか比べないので、名前の先頭と合えば一致し（"a" が APP、"t" が TRACE）、空は必ず一致する
  （空の値が "quiet" になり、SDL_LOGGING= で全部が黙る。D-55）。papimela は全体で比べ、空は一致させない。 }
function ParseCategory(const S: String; out ACategory: Integer): Boolean;
var
  I: Integer;
begin
  ACategory := 0;
  if S = '' then
  begin
    Result := False;
    Exit;
  end;
  if (S[1] in ['0'..'9']) then
  begin
    ACategory := LeadingNumber(S);
    Result := True;
    Exit;
  end;
  if S[1] = '*' then
  begin
    ACategory := DEFAULT_CATEGORY;
    Result := True;
    Exit;
  end;
  for I := 0 to 9 do
  begin
    if SameText(S, CATEGORY_NAMES[I]) then
    begin
      ACategory := I;
      Result := True;
      Exit;
    end;
  end;
  Result := False;
end;

function ParsePriority(const S: String; out APriority: TPMLLogPriority): Boolean;
var
  N: Integer;
  P: TPMLLogPriority;
begin
  APriority := TPMLLogPriority.Invalid;
  if S = '' then
  begin
    Result := False;
    Exit;
  end;
  if (S[1] in ['0'..'9']) then
  begin
    N := LeadingNumber(S);
    if N = 0 then
    begin
      APriority := TPMLLogPriority.Quiet;
      Result := True;
      Exit;
    end;
    if (N >= 1) and (N <= 7) then
    begin
      APriority := TPMLLogPriority(N);
      Result := True;
      Exit;
    end;
  end;
  if SameText(S, 'quiet') then
  begin
    APriority := TPMLLogPriority.Quiet;
    Result := True;
    Exit;
  end;
  for P := TPMLLogPriority.Trace to TPMLLogPriority.Critical do
    if SameText(S, PRIORITY_NAMES[P]) then
    begin
      APriority := P;
      Result := True;
      Exit;
    end;
  Result := False;
end;

{ TPMLLog }

constructor TPMLLog.Create(AHints: TPMLHints; ABaseDefault: TPMLLogPriority);
var
  P: TPMLLogPriority;
begin
  inherited Create;
  FLock := TPMLMutex.Create;
  FOutputLock := TPMLMutex.Create;
  FHints := AHints;
  FBaseDefault := ABaseDefault;
  FOutput := @DefaultOutput;
  for P := Low(TPMLLogPriority) to High(TPMLLogPriority) do
  begin
    FPrefixes[P] := '';
    FPrefixSet[P] := False;
  end;
  if FHints <> nil then
    FHints.AddCallback(PML_HINT_LOGGING, @HintChanged)
  else
    ResetPriorities;
end;

destructor TPMLLog.Destroy;
begin
  if FHints <> nil then
    FHints.RemoveCallback(PML_HINT_LOGGING, @HintChanged);
  FOutputLock.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TPMLLog.HintChanged(const AName: String; const AOld, ANew: TPMLHintValue);
begin
  ResetPriorities;
end;

procedure TPMLLog.ParsePriorities(const AHint: String);
var
  Start, Sep, Comma: Integer;
  CatText, ValText: String;
  Cat: Integer;
  P: TPMLLogPriority;
begin
  if Pos('=', AHint) = 0 then
  begin
    if ParsePriority(AHint, P) then
      SetPriorities(P);
    Exit;
  end;
  Start := 1;
  repeat
    Sep := PosEx('=', AHint, Start);
    if Sep = 0 then
      Break;
    Comma := PosEx(',', AHint, Sep);
    CatText := Copy(AHint, Start, Sep - Start);
    if Comma > 0 then
      ValText := Copy(AHint, Sep + 1, Comma - Sep - 1)
    else
      ValText := Copy(AHint, Sep + 1, MaxInt);
    if ParseCategory(CatText, Cat) and ParsePriority(ValText, P) then
    begin
      if Cat = DEFAULT_CATEGORY then
      begin
        for Cat := Low(FPriorities) to High(FPriorities) do
          if FPriorities[Cat] = TPMLLogPriority.Invalid then
            FPriorities[Cat] := P;
        FDefaultPrio := P;
      end
      else
        SetPriority(Cat, P);
    end;
    if Comma = 0 then
      Break;
    Start := Comma + 1;
  until False;
end;

procedure TPMLLog.SetPriorities(APriority: TPMLLogPriority);
var
  I: Integer;
begin
  FLock.Lock;
  try
    SetLength(FCustomCats, 0);
    SetLength(FCustomPrios, 0);
    FDefaultPrio := APriority;
    for I := Low(FPriorities) to High(FPriorities) do
      FPriorities[I] := APriority;
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLLog.SetPriority(ACategory: Integer; APriority: TPMLLogPriority);
var
  I: Integer;
begin
  FLock.Lock;
  try
    if (ACategory >= 0) and (ACategory < PML_LOG_CATEGORY_CUSTOM) then
      FPriorities[ACategory] := APriority
    else
    begin
      I := 0;
      while (I < Length(FCustomCats)) and (FCustomCats[I] <> ACategory) do
        Inc(I);
      if I < Length(FCustomCats) then
        FCustomPrios[I] := APriority
      else
      begin
        SetLength(FCustomCats, Length(FCustomCats) + 1);
        SetLength(FCustomPrios, Length(FCustomPrios) + 1);
        FCustomCats[High(FCustomCats)] := ACategory;
        FCustomPrios[High(FCustomPrios)] := APriority;
      end;
    end;
  finally
    FLock.Unlock;
  end;
end;

function TPMLLog.GetPriority(ACategory: Integer): TPMLLogPriority;
var
  I: Integer;
begin
  FLock.Lock;
  try
    if (ACategory >= 0) and (ACategory < PML_LOG_CATEGORY_CUSTOM) then
      Result := FPriorities[ACategory]
    else
    begin
      Result := TPMLLogPriority.Invalid;
      I := 0;
      while (I < Length(FCustomCats)) and (FCustomCats[I] <> ACategory) do
        Inc(I);
      if I < Length(FCustomCats) then
        Result := FCustomPrios[I];
      if Result = TPMLLogPriority.Invalid then
        Result := FDefaultPrio;
    end;
  finally
    FLock.Unlock;
  end;
end;

{ PORT-NOTE: SDL_ResetLogPriorities はログの排他を持ったまま SDL_GetHint を呼び、ヒントの側は
  自分の排他を持ったまま SDL_LoggingChanged（ここ）を呼ぶ。2 つのスレッドが逆の順で排他を取ると
  止まり得るので、papimela はヒントを読んでからログの排他を取る。 }
procedure TPMLLog.ResetPriorities;
var
  HintText: String;
  HasHint, InDebug: Boolean;
  Base: TPMLLogPriority;
  I: Integer;
begin
  HasHint := (FHints <> nil) and FHints.TryGetHint(PML_HINT_LOGGING, HintText);
  InDebug := DebugInvocation;
  FLock.Lock;
  try
    SetLength(FCustomCats, 0);
    SetLength(FCustomPrios, 0);
    FDefaultPrio := TPMLLogPriority.Invalid;
    for I := Low(FPriorities) to High(FPriorities) do
      FPriorities[I] := TPMLLogPriority.Invalid;
    if HasHint then
      ParsePriorities(HintText);

    if FBaseDefault <> TPMLLogPriority.Invalid then
    begin
      // papimela の既定（Context の MinimumLogLevel）
      Base := FBaseDefault;
      if InDebug and (Base > TPMLLogPriority.Debug) then
        Base := TPMLLogPriority.Debug;
      if FDefaultPrio = TPMLLogPriority.Invalid then
        FDefaultPrio := Base;
      for I := Low(FPriorities) to High(FPriorities) do
        if FPriorities[I] = TPMLLogPriority.Invalid then
          FPriorities[I] := Base;
      Exit;
    end;

    // SDL と同じ既定
    if FDefaultPrio = TPMLLogPriority.Invalid then
    begin
      // PORT-NOTE(bug): SDL は DEBUG_INVOCATION でも ERROR のままで、ヘッダの「*=debug と同じ」と
      // 食い違い、独自のカテゴリだけ Debug にならない（D-56）。
      if InDebug then
        FDefaultPrio := TPMLLogPriority.Debug
      else
        FDefaultPrio := TPMLLogPriority.Error_;
    end;
    for I := Low(FPriorities) to High(FPriorities) do
    begin
      if FPriorities[I] <> TPMLLogPriority.Invalid then
        Continue;
      if I = PML_LOG_CATEGORY_ASSERT then
        FPriorities[I] := TPMLLogPriority.Warn
      else if I = PML_LOG_CATEGORY_TEST then
        FPriorities[I] := TPMLLogPriority.Verbose
      else if InDebug then
        FPriorities[I] := TPMLLogPriority.Debug
      else if I = PML_LOG_CATEGORY_APPLICATION then
        FPriorities[I] := TPMLLogPriority.Info
      else
        FPriorities[I] := TPMLLogPriority.Error_;
    end;
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLLog.SetPriorityPrefix(APriority: TPMLLogPriority; const APrefix: String);
begin
  if (APriority = TPMLLogPriority.Invalid) or (APriority = TPMLLogPriority.Quiet) then
    raise EPMLArgument.Create('no prefix for this log priority');
  FOutputLock.Lock;
  try
    FPrefixes[APriority] := APrefix;
    FPrefixSet[APriority] := True;
  finally
    FOutputLock.Unlock;
  end;
end;

function TPMLLog.PriorityPrefix(APriority: TPMLLogPriority): String;
begin
  FOutputLock.Lock;
  try
    if (APriority = TPMLLogPriority.Invalid) or (APriority = TPMLLogPriority.Quiet) then
      Result := ''
    else if FPrefixSet[APriority] then
      Result := FPrefixes[APriority]
    else
    begin
      case APriority of
        TPMLLogPriority.Warn: Result := 'WARNING: ';
        TPMLLogPriority.Error_, TPMLLogPriority.Critical: Result := 'ERROR: ';
        else
          Result := '';
      end;
    end;
  finally
    FOutputLock.Unlock;
  end;
end;

procedure TPMLLog.Log(const AMessage: String);
begin
  LogMessage(PML_LOG_CATEGORY_APPLICATION, TPMLLogPriority.Info, AMessage);
end;

procedure TPMLLog.Trace(ACategory: Integer; const AMessage: String);
begin
  LogMessage(ACategory, TPMLLogPriority.Trace, AMessage);
end;

procedure TPMLLog.Verbose(ACategory: Integer; const AMessage: String);
begin
  LogMessage(ACategory, TPMLLogPriority.Verbose, AMessage);
end;

procedure TPMLLog.Debug(ACategory: Integer; const AMessage: String);
begin
  LogMessage(ACategory, TPMLLogPriority.Debug, AMessage);
end;

procedure TPMLLog.Info(ACategory: Integer; const AMessage: String);
begin
  LogMessage(ACategory, TPMLLogPriority.Info, AMessage);
end;

procedure TPMLLog.Warn(ACategory: Integer; const AMessage: String);
begin
  LogMessage(ACategory, TPMLLogPriority.Warn, AMessage);
end;

procedure TPMLLog.Error(ACategory: Integer; const AMessage: String);
begin
  LogMessage(ACategory, TPMLLogPriority.Error_, AMessage);
end;

procedure TPMLLog.Critical(ACategory: Integer; const AMessage: String);
begin
  LogMessage(ACategory, TPMLLogPriority.Critical, AMessage);
end;

procedure TPMLLog.LogMessage(ACategory: Integer; APriority: TPMLLogPriority;
  const AMessage: String);
var
  M: String;
begin
  if APriority < GetPriority(ACategory) then
    Exit;
  M := AMessage;
  if (Length(M) > 0) and (M[Length(M)] = #10) then
  begin
    SetLength(M, Length(M) - 1);
    if (Length(M) > 0) and (M[Length(M)] = #13) then
      SetLength(M, Length(M) - 1);
  end;
  FOutputLock.Lock;
  try
    if Assigned(FOutput) then
      FOutput(ACategory, APriority, M);
  finally
    FOutputLock.Unlock;
  end;
end;

procedure TPMLLog.LogMessageFmt(ACategory: Integer; APriority: TPMLLogPriority;
  const AFmt: String; const AArgs: array of const);
begin
  if APriority < GetPriority(ACategory) then
    Exit;
  LogMessage(ACategory, APriority, Format(AFmt, AArgs));
end;

procedure TPMLLog.DefaultOutput(ACategory: Integer; APriority: TPMLLogPriority;
  const AMessage: String);
begin
  WriteLn(ErrOutput, PriorityPrefix(APriority) + AMessage);
  Flush(ErrOutput);
end;

function TPMLLog.GetOutput: TPMLLogOutput;
begin
  FOutputLock.Lock;
  try
    Result := FOutput;
  finally
    FOutputLock.Unlock;
  end;
end;

procedure TPMLLog.SetOutput(AValue: TPMLLogOutput);
begin
  FOutputLock.Lock;
  try
    FOutput := AValue;
  finally
    FOutputLock.Unlock;
  end;
end;

end.
