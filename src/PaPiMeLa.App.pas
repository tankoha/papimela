{
  PaPiMeLa.App — アプリケーションのループ（TPMLApplication）

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §6.5、§11 #45

  WHAT:
    初期化・1 回ぶんの処理・イベント・終了の 4 つを上書きするだけで
    アプリが書ける土台。ループは Run が回す:

      DoInit → 繰り返し（イベントを全部 DoEvent へ、DoIterate） → DoQuit

    どれかが Continue 以外を返したら止まり、DoQuit にその結果を渡す。
    Run の戻り値は終了コード（Success = 0、Failure = 1）。

  WHY:
    SDL のメインコールバック（SDL_AppInit / AppIterate / AppEvent / AppQuit）
    にあたる。Linux / Wayland ではアプリがループを持てるので必須ではないが、
    将来ループをプラットフォームが持つ環境（Android、Emscripten）を足すとき、
    Run の中身を差し替える場所になる。TPMLContext を自分で作ってループを
    書くこともそのままできる。

  RESOLVED:
    - DoInit の既定は Video だけの Context を作る。オプションを変えたい
      アプリは上書きして Context に入れる
    - DoEvent の既定は Quit と WindowCloseRequested で Success、他は Continue。
      設計 §6.5 は「Dispatcher に渡す」としていたが、Dispatcher はまだ無い
    - DoQuit の既定は Context を Free する
    - 例外が出たら DoQuit(Failure) を呼んでから投げ直す（後始末を飛ばさない）
    - WaitForEvents = True なら DoIterate を呼ばず、イベントが来るまで眠る
      （ツールのように、入力が無ければ何もしないアプリ向け）
}
unit PaPiMeLa.App;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Events,
  PaPiMeLa.Core;

type
  TPMLAppResult = (Continue, Success, Failure);

  TPMLApplication = class;
  TPMLApplicationClass = class of TPMLApplication;

  TPMLApplication = class
  strict private
    FContext      : TPMLContext;
    FWaitForEvents: Boolean;
  protected
    function  DoInit(const AArgs: TStringArray): TPMLAppResult; virtual;
    function  DoIterate: TPMLAppResult; virtual;
    function  DoEvent(const AEvent: TPMLEvent): TPMLAppResult; virtual;
    procedure DoQuit(AResult: TPMLAppResult); virtual;
  public
    constructor Create; virtual;
    destructor Destroy; override;

    // 引数を渡して回す。戻り値は終了コード（Success = 0、Failure = 1）。
    function  Run(const AArgs: TStringArray): Integer; overload;
    // プロセスの引数（ParamStr(1) 以降）で回す。
    function  Run: Integer; overload;
    { AClass を作って Run し、解放して終了コードを返す。
        begin
          ExitCode := TPMLApplication.RunMain(TMyApp);
        end. }
    class function RunMain(AClass: TPMLApplicationClass): Integer;

    // DoInit で作る。DoQuit の既定が Free して nil に戻す。
    property Context: TPMLContext read FContext write FContext;
    property WaitForEvents: Boolean read FWaitForEvents write FWaitForEvents;
  end;

implementation

constructor TPMLApplication.Create;
begin
  inherited Create;
end;

destructor TPMLApplication.Destroy;
begin
  FreeAndNil(FContext);
  inherited Destroy;
end;

function TPMLApplication.DoInit(const AArgs: TStringArray): TPMLAppResult;
begin
  FContext := TPMLContext.Create([TPMLSubsystem.Video]);
  Result := TPMLAppResult.Continue;
end;

function TPMLApplication.DoIterate: TPMLAppResult;
begin
  Result := TPMLAppResult.Continue;
end;

function TPMLApplication.DoEvent(const AEvent: TPMLEvent): TPMLAppResult;
begin
  if (AEvent.Kind = TPMLEventKind.Quit)
    or (AEvent.Kind = TPMLEventKind.WindowCloseRequested) then
    Result := TPMLAppResult.Success
  else
    Result := TPMLAppResult.Continue;
end;

procedure TPMLApplication.DoQuit(AResult: TPMLAppResult);
begin
  FreeAndNil(FContext);
end;

function TPMLApplication.Run(const AArgs: TStringArray): Integer;
var
  State: TPMLAppResult;
  Ev: TPMLEvent;
begin
  // DoQuit は 1 回だけ。例外のときも、ここを通らずに先に呼んでから投げ直す。
  try
    State := DoInit(AArgs);
    while State = TPMLAppResult.Continue do
    begin
      // たまったイベントを全部 DoEvent へ。Continue 以外が返ったらそこで止める。
      while (State = TPMLAppResult.Continue) and FContext.Events.Poll(Ev) do
        State := DoEvent(Ev);
      if State <> TPMLAppResult.Continue then
        Break;
      if FWaitForEvents then
      begin
        // False は起こされただけ（イベントは無い）。ループへ戻る。
        if FContext.Events.Wait(Ev) then
          State := DoEvent(Ev);
      end
      else
        State := DoIterate;
    end;
  except
    DoQuit(TPMLAppResult.Failure);
    raise;
  end;
  DoQuit(State);
  if State = TPMLAppResult.Success then
    Result := 0
  else
    Result := 1;
end;

function TPMLApplication.Run: Integer;
var
  Args: TStringArray;
  I: Integer;
begin
  Args := nil;
  SetLength(Args, ParamCount);
  for I := 1 to ParamCount do
    Args[I - 1] := ParamStr(I);
  Result := Run(Args);
end;

class function TPMLApplication.RunMain(AClass: TPMLApplicationClass): Integer;
var
  App: TPMLApplication;
begin
  App := AClass.Create;
  try
    Result := App.Run;
  finally
    App.Free;
  end;
end;

end.
