{
  PaPiMeLa.MessageBox — メッセージボックス（zenity）

  Origin : partially ported from SDL (src/video/SDL_video.c, src/video/wayland/SDL_waylandmessagebox.c,
           src/dialog/unix/SDL_zenitymessagebox.c)
           Scope: SDL_ShowMessageBox / SDL_ShowSimpleMessageBox / SDL_GetMessageBoxCount、Wayland の
           ShowMessageBox の判定（Wayland のセッションか）、SDL_Zenity_ShowMessageBox（zenity の引数の組み立て、
           版による --icon と --icon-name の違い、押されたボタンの見分け）、zenity の版の読み取り。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #40

  WHAT:
    zenity を子プロセスとして動かして、メッセージボックスを出す。ビデオを始める前でも使える（SDL と同じ）。
    押されたボタンの ID を返す。ウィンドウを閉じただけなら False。

  RESOLVED:
    - 失敗の伝え方: zenity が無い・動かせない・ボタンが多すぎる・Wayland のセッションでない、は例外
      （EPMLUnsupported・EPMLArgument）。ウィンドウを閉じた（zenity が 255）は False（SDL も false を返す）
    - 押されたボタンが分からないとき（出力がどのボタンの文字とも合わない）、AButtonID は -1 のまま True
      （SDL は書き換えない）
    - 色の組み合わせ（colorScheme）、ボタンの並び（左から右・右から左）、既定のボタンの印、親のウィンドウは
      zenity では使えないので無視する（SDL と同じ）
    - 子プロセスは、今の環境（libc の environ。setenv で変えた分も）を渡し、実行ファイルは PATH から探す

  NOT RESOLVED:
    - SDL_ShowMessageBox がする、マウスの捕捉・相対モードを解く、カーソルを出す、キーボードの状態をリセット、
      元のウィンドウを前に出す、は移植しない（ビデオの状態を触るため。必要なら Video の側で包む）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.MessageBox;

{$I papimela.inc}

interface

uses
  SysUtils, Classes, Process, BaseUnix,
  PaPiMeLa.Errors;

type
  TPMLMessageBoxFlag = (Error, Warning, Information, ButtonsLeftToRight, ButtonsRightToLeft);
  TPMLMessageBoxFlags = set of TPMLMessageBoxFlag;

  TPMLMessageBoxButtonFlag = (ReturnKeyDefault, EscapeKeyDefault);
  TPMLMessageBoxButtonFlags = set of TPMLMessageBoxButtonFlag;

  // ボタン 1 つ（SDL_MessageBoxButtonData）。ButtonID は押されたときに返す値
  TPMLMessageBoxButton = record
    Flags   : TPMLMessageBoxButtonFlags;
    ButtonID: Integer;
    Text    : String;
  end;

  // メッセージボックス（SDL_MessageBoxData。色の組み合わせと親のウィンドウは zenity で使わないので持たない）
  TPMLMessageBoxData = record
    Flags  : TPMLMessageBoxFlags;
    Title  : String;
    Message: String;
    Buttons: array of TPMLMessageBoxButton;
  end;

const
  // 持てるボタンの数の上限（zenity のバックエンドの MAX_BUTTONS）
  PML_MESSAGEBOX_MAX_BUTTONS = 8;

{ メッセージボックスを出して、押されたボタンの ID を AButtonID に入れる（SDL_ShowMessageBox）。
  ウィンドウを閉じただけなら False。AButtonID は、ボタンが分からなければ -1。 }
function PMLShowMessageBox(const AData: TPMLMessageBoxData; out AButtonID: Integer): Boolean;

{ ボタンが OK 1 つのメッセージボックス（SDL_ShowSimpleMessageBox）。閉じただけでも False。 }
function PMLShowSimpleMessageBox(AFlags: TPMLMessageBoxFlags; const ATitle, AMessage: String): Boolean;

// 今出ているメッセージボックスの数（SDL_GetMessageBoxCount）。
function PMLMessageBoxCount: Integer;

{ zenity の引数（argv[0] の zenity を含む）を組み立てる（SDL_Zenity_ShowMessageBox の前半）。
  AMajor・AMinor は zenity の版。ボタンが多すぎれば EPMLArgument。検査用に公開した。 }
function PMLZenityMessageBoxArguments(const AData: TPMLMessageBoxData; AMajor, AMinor: Integer): TStringArray;

{ zenity --version の出力から版を読む（parse_zenity_version）。読めなければ False。 }
function PMLParseZenityVersion(const AText: String; out AMajor, AMinor: Integer): Boolean;

{ zenity の出力から押されたボタンの ID を探す。最後の改行から後ろを捨て、ボタンの文字と同じものを探す。
  なければ False。 }
function PMLZenityPickButton(const AData: TPMLMessageBoxData; const AOutput: String; out AButtonID: Integer): Boolean;

implementation

var
  GMessageBoxCount: LongInt = 0;

var
  c_environ: PPChar; external name '__environ';
function c_getenv(AName: PChar): PChar; cdecl; external 'c' name 'getenv';

function PMLMessageBoxCount: Integer;
begin
  Result := GMessageBoxCount;
end;

{ ---- 引数 ---- }

// SDL_strtol(…, 10) の先頭の数。数が無ければ AEnd = AStart
function ReadInt(const AText: String; AStart: Integer; out AEnd: Integer): Integer;
var
  I: Integer;
  Neg: Boolean;
  V: Int64;
begin
  I := AStart;
  while (I <= Length(AText)) and (AText[I] in [#9..#13, ' ']) do
    Inc(I);
  Neg := False;
  if (I <= Length(AText)) and (AText[I] in ['+', '-']) then
  begin
    Neg := AText[I] = '-';
    Inc(I);
  end;
  AEnd := AStart;
  V := 0;
  if (I > Length(AText)) or not (AText[I] in ['0'..'9']) then
    Exit(0);
  while (I <= Length(AText)) and (AText[I] in ['0'..'9']) do
  begin
    if V < High(Integer) then
      V := V * 10 + (Ord(AText[I]) - 48);
    Inc(I);
  end;
  AEnd := I;
  if Neg then
    V := -V;
  Result := Integer(V);
end;

function PMLParseZenityVersion(const AText: String; out AMajor, AMinor: Integer): Boolean;
var
  E, Start, Tmp: Integer;
begin
  AMajor := 0;
  AMinor := 0;
  Tmp := ReadInt(AText, 1, E);
  if (Tmp = 0) and (E = 1) then
    Exit(False);                 // 主の版が読めない
  AMajor := Tmp;
  if (E <= Length(AText)) and (AText[E] = '.') then
  begin
    Start := E + 1;
    Tmp := ReadInt(AText, Start, E);
    if (Tmp = 0) and (E = Start) then
      Exit(False);               // 副の版が読めない（"3." や "3.x"）
    AMinor := Tmp;
  end
  else
    AMinor := 0;
  Result := True;
end;

function PMLZenityMessageBoxArguments(const AData: TPMLMessageBoxData; AMajor, AMinor: Integer): TStringArray;
var
  Args: TStringArray;
  N, I: Integer;

  procedure Add(const AValue: String);
  begin
    SetLength(Args, N + 1);
    Args[N] := AValue;
    Inc(N);
  end;

begin
  if Length(AData.Buttons) > PML_MESSAGEBOX_MAX_BUTTONS then
    raise EPMLArgument.CreateFmt('Too many buttons (%d max allowed)', [PML_MESSAGEBOX_MAX_BUTTONS]);
  Args := nil;
  N := 0;
  Add('zenity');
  Add('--question');
  Add('--switch');
  Add('--no-wrap');
  Add('--no-markup');
  // zenity 3.90 で --icon-name が無くなった（知らせなしに）。名前を選ぶ
  if (AMajor > 3) or ((AMajor = 3) and (AMinor >= 90)) then
    Add('--icon')
  else
    Add('--icon-name');
  // 種類が 1 つだけ指定されているときだけ。2 つ以上や無指定は情報
  if (AData.Flags * [TPMLMessageBoxFlag.Error, TPMLMessageBoxFlag.Warning, TPMLMessageBoxFlag.Information])
    = [TPMLMessageBoxFlag.Error] then
    Add('dialog-error')
  else if (AData.Flags * [TPMLMessageBoxFlag.Error, TPMLMessageBoxFlag.Warning, TPMLMessageBoxFlag.Information])
    = [TPMLMessageBoxFlag.Warning] then
    Add('dialog-warning')
  else
    Add('dialog-information');
  if AData.Title <> '' then
  begin
    Add('--title');
    Add(AData.Title);
  end
  else
    Add('--title=');
  if AData.Message <> '' then
  begin
    Add('--text');
    Add(AData.Message);
  end
  else
    Add('--text=');
  for I := 0 to High(AData.Buttons) do
    if AData.Buttons[I].Text <> '' then
    begin
      Add('--extra-button');
      Add(AData.Buttons[I].Text);
    end
    else
      Add('--extra-button=');
  if Length(AData.Buttons) = 0 then
    Add('--extra-button=OK');
  Result := Args;
end;

function PMLZenityPickButton(const AData: TPMLMessageBoxData; const AOutput: String; out AButtonID: Integer): Boolean;
var
  Text: String;
  I, P: Integer;
begin
  Result := False;
  AButtonID := -1;
  Text := AOutput;
  // 最後の改行から後ろを捨てる（zenity が足す）
  P := LastDelimiter(#10, Text);
  if P > 0 then
    SetLength(Text, P - 1);
  for I := 0 to High(AData.Buttons) do
    if Text = AData.Buttons[I].Text then
    begin
      AButtonID := AData.Buttons[I].ButtonID;
      Exit(True);
    end;
end;

{ ---- 子プロセス ---- }

// PATH から実行ファイルを探す（libc の getenv。setenv で変えた PATH も見る）。無ければ ''
function FindExecutable_(const AName: String): String;
var
  P: PChar;
  Dirs: TStringList;
  I: Integer;
  Cand: String;
begin
  Result := '';
  if Pos('/', AName) > 0 then
  begin
    if fpAccess(AName, X_OK) = 0 then
      Result := AName;
    Exit;
  end;
  P := c_getenv('PATH');
  if P = nil then
    Exit;
  Dirs := TStringList.Create;
  try
    Dirs.StrictDelimiter := True;
    Dirs.Delimiter := ':';
    Dirs.DelimitedText := P;
    for I := 0 to Dirs.Count - 1 do
    begin
      if Dirs[I] = '' then
        Cand := AName
      else
        Cand := IncludeTrailingPathDelimiter(Dirs[I]) + AName;
      if (fpAccess(Cand, X_OK) = 0) and FileExists(Cand) then
        Exit(Cand);
    end;
  finally
    Dirs.Free;
  end;
end;

{ 子プロセスを動かして標準出力を集める。起動できなければ False。AExitCode は終了コード。 }
function RunCapture(const AArgs: TStringArray; out AOutput: String; out AExitCode: Integer): Boolean;
var
  Proc: TProcess;
  Exe: String;
  I: Integer;
  Env: PPChar;
  Buf: array[0..4095] of Byte;
  N: LongInt;
  Sink: array[0..4095] of Byte;
begin
  AOutput := '';
  AExitCode := -1;
  Exe := FindExecutable_(AArgs[0]);
  if Exe = '' then
    Exit(False);
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := Exe;
    for I := 1 to High(AArgs) do
      Proc.Parameters.Add(AArgs[I]);
    // 今の環境を渡す（FPC が起動時に写した環境ではなく、libc の environ）
    Env := c_environ;
    while (Env <> nil) and (Env^ <> nil) do
    begin
      Proc.Environment.Add(Env^);
      Inc(Env);
    end;
    Proc.Options := [poUsePipes];
    try
      Proc.Execute;
    except
      on E: EProcess do
        Exit(False);
    end;
    // 標準出力を読み切り、標準エラーは捨てる
    repeat
      N := Proc.Output.Read(Buf, SizeOf(Buf));
      if N > 0 then
        AOutput := AOutput + Copy(PChar(@Buf[0]), 1, N);
      if Proc.Stderr.NumBytesAvailable > 0 then
        Proc.Stderr.Read(Sink, SizeOf(Sink));
    until (N <= 0) and not Proc.Running;
    while Proc.Running do
      Sleep(1);
    // ExitStatus は waitpid の生の値。上の 8 ビットが終了コード、下の 7 ビットが 0 でなければ信号で終わった
    if (Proc.ExitStatus and $7F) = 0 then
      AExitCode := (Proc.ExitStatus shr 8) and $FF
    else
      AExitCode := -1;
    Result := True;
  finally
    Proc.Free;
  end;
end;

function GetZenityVersion(out AMajor, AMinor: Integer): Boolean;
var
  Args: TStringArray;
  Output: String;
  Code: Integer;
begin
  SetLength(Args, 2);
  Args[0] := 'zenity';
  Args[1] := '--version';
  if not RunCapture(Args, Output, Code) then
    Exit(False);
  Result := PMLParseZenityVersion(Output, AMajor, AMinor);
end;

{ ---- 公開 ---- }

// Wayland の判定（Wayland_ShowMessageBox）。Wayland のセッションでなければ EPMLUnsupported
procedure RequireWaylandSession;
var
  Session: PChar;
begin
  if c_getenv('WAYLAND_DISPLAY') = nil then
  begin
    Session := c_getenv('XDG_SESSION_TYPE');
    if (Session <> nil) and not SameText(Session, 'wayland') then
      raise EPMLUnsupported.Create('Not on a wayland display');
  end;
end;

function PMLShowMessageBox(const AData: TPMLMessageBoxData; out AButtonID: Integer): Boolean;
var
  Major, Minor, Code: Integer;
  Args: TStringArray;
  Output: String;
begin
  AButtonID := -1;
  InterlockedIncrement(GMessageBoxCount);
  try
    RequireWaylandSession;
    Args := nil;
    Major := 0;
    Minor := 0;
    if Length(AData.Buttons) > PML_MESSAGEBOX_MAX_BUTTONS then
      raise EPMLArgument.CreateFmt('Too many buttons (%d max allowed)', [PML_MESSAGEBOX_MAX_BUTTONS]);
    // zenity の版が分からないと、使う引数を選べない
    if not GetZenityVersion(Major, Minor) then
      raise EPMLUnsupported.Create('No message system available (zenity not found or its version unreadable)');
    Args := PMLZenityMessageBoxArguments(AData, Major, Minor);
    if not RunCapture(Args, Output, Code) then
      raise EPMLUnsupported.Create('No message system available (could not run zenity)');
    if (Code < 0) or (Code = 255) then
      Exit(False);                // ウィンドウを閉じた
    PMLZenityPickButton(AData, Output, AButtonID);
    Result := True;
  finally
    InterlockedDecrement(GMessageBoxCount);
  end;
end;

function PMLShowSimpleMessageBox(AFlags: TPMLMessageBoxFlags; const ATitle, AMessage: String): Boolean;
var
  Data: TPMLMessageBoxData;
  Id: Integer;
begin
  Data := Default(TPMLMessageBoxData);
  Data.Flags := AFlags;
  Data.Title := ATitle;
  Data.Message := AMessage;
  SetLength(Data.Buttons, 1);
  Data.Buttons[0].Flags := [TPMLMessageBoxButtonFlag.ReturnKeyDefault, TPMLMessageBoxButtonFlag.EscapeKeyDefault];
  Data.Buttons[0].ButtonID := 0;
  Data.Buttons[0].Text := 'OK';
  Result := PMLShowMessageBox(Data, Id);
end;

end.
