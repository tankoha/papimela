{
  test_messagebox — メッセージボックス（PaPiMeLa.MessageBox。zenity のバックエンド）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    zenity の代わりに test/fake-zenity/zenity（偽物。受けた引数を記録し、決めた出力と終了コードを返す）を
    PATH の先頭に置く。参照版 SDL の SDL_Zenity_ShowMessageBox に同じ場面を通した記録
    （test/messagebox_expected.inc。tools/messagebox-expect/gen.bb が作る。入力も記録に入っている）を読み、
    場面ごとに PMLShowMessageBox を動かして、zenity に渡った引数と結果（True/False と押されたボタンの ID）を比べる。
    場面は 40 通り: 種類のフラグ（2 つ指定や無指定は情報）、ボタン 0/1/3/8/9 個、題や本文が空、ボタンの文字が空、
    zenity の版による --icon と --icon-name、版が読めない、特殊な文字、日本語、出力が合わない・改行の数・
    同じ文字のボタン・大文字小文字、ウィンドウを閉じた（255）、終了コード。
    papimela の足した検査: Wayland のセッションかの判定、zenity が無いとき、数の上限の例外、押されたボタンの
    見分け、版の読み取りの単独、単純なメッセージボックス、出ている数。
}
program test_messagebox;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils, Classes, BaseUnix, ctypes,
  PaPiMeLa.Errors,
  PaPiMeLa.MessageBox;

{$I messagebox_expected.inc}

function setenv(AName, AValue: PChar; AOverwrite: cint): cint; cdecl; external 'c' name 'setenv';
function unsetenv(AName: PChar): cint; cdecl; external 'c' name 'unsetenv';

var
  Failures: Integer = 0;
  FakeDir, LogFile: String;

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

// 記録の \n と \\ を戻す
function Unescape(const AText: String): String;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '\') and (I < Length(AText)) then
    begin
      Inc(I);
      if AText[I] = 'n' then
        Result := Result + #10
      else
        Result := Result + AText[I];
    end
    else
      Result := Result + AText[I];
    Inc(I);
  end;
end;

function Escape(const AText: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(AText) do
    case AText[I] of
      #10: Result := Result + '\n';
      '\': Result := Result + '\\';
    else
      Result := Result + AText[I];
    end;
end;

procedure SetVar(const AName, AValue: String);
begin
  setenv(PChar(AName), PChar(AValue), 1);
end;

procedure SetupEnvironment;
begin
  SetVar('PATH', FakeDir + ':' + '/usr/bin:/bin');
  SetVar('FAKE_ZENITY_LOG', LogFile);
  // 判定を通す（Wayland のセッションとみなす）
  SetVar('WAYLAND_DISPLAY', 'wayland-test');
  unsetenv('XDG_SESSION_TYPE');
end;

// 偽の zenity が書いた引数（NUL 区切り）を行にする
function ReadLog: TStringList;
var
  F: TFileStream;
  Data, Cur: String;
  I, N: Integer;
begin
  Result := TStringList.Create;
  if not FileExists(LogFile) then
  begin
    Result.Add('A (none)');
    Exit;
  end;
  F := TFileStream.Create(LogFile, fmOpenRead);
  try
    SetLength(Data, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Data[1], F.Size);
  finally
    F.Free;
  end;
  Cur := '';
  N := 0;
  for I := 1 to Length(Data) do
    if Data[I] = #0 then
    begin
      Result.Add(Format('A %d %s', [N, Escape(Cur)]));
      Inc(N);
      Cur := '';
    end
    else
      Cur := Cur + Data[I];
end;

procedure RunRecord;
var
  I, J, Bad, Cases: Integer;
  Line, Name: String;
  Want, Mine: TStringList;
  Data: TPMLMessageBoxData;
  Flags: LongWord;
  Version, Output, ExitCode: String;
  Id: Integer;
  Ok: Boolean;
  Same: Boolean;
begin
  WriteLn('参照版 SDL の記録を 1 場面ずつ再現する');
  Want := TStringList.Create;
  Mine := TStringList.Create;
  Bad := 0;
  Cases := 0;
  try
    I := 0;
    while I <= High(MessageBoxExpected) do
    begin
      Line := MessageBoxExpected[I];
      if Copy(Line, 1, 2) <> 'C ' then
      begin
        Inc(I);
        Continue;
      end;
      Name := Copy(Line, 3, MaxInt);
      Inc(I);
      Data := Default(TPMLMessageBoxData);
      Version := '';
      Output := '';
      ExitCode := '0';
      Flags := 0;
      Want.Clear;
      // 入力と期待の行
      while (I <= High(MessageBoxExpected)) and (Copy(MessageBoxExpected[I], 1, 2) <> 'C ') do
      begin
        Line := MessageBoxExpected[I];
        Inc(I);
        case Line[1] of
          'F': Flags := StrToInt(Copy(Line, 3, MaxInt));
          'T': Data.Title := Unescape(Copy(Line, 3, MaxInt));
          'M': Data.Message := Unescape(Copy(Line, 3, MaxInt));
          'B':
          begin
            J := Length(Data.Buttons);
            SetLength(Data.Buttons, J + 1);
            Line := Copy(Line, 3, MaxInt);
            Data.Buttons[J].ButtonID := StrToInt(Copy(Line, 1, Pos(' ', Line) - 1));
            Data.Buttons[J].Text := Unescape(Copy(Line, Pos(' ', Line) + 1, MaxInt));
          end;
          'V': Version := Copy(Line, 3, MaxInt);
          'O': Output := Unescape(Copy(Line, 3, MaxInt));
          'X': ExitCode := Copy(Line, 3, MaxInt);
          'A', 'R': Want.Add(Line);
        end;
      end;
      if (Flags and $10) <> 0 then Include(Data.Flags, TPMLMessageBoxFlag.Error);
      if (Flags and $20) <> 0 then Include(Data.Flags, TPMLMessageBoxFlag.Warning);
      if (Flags and $40) <> 0 then Include(Data.Flags, TPMLMessageBoxFlag.Information);
      if (Flags and $80) <> 0 then Include(Data.Flags, TPMLMessageBoxFlag.ButtonsLeftToRight);
      if (Flags and $100) <> 0 then Include(Data.Flags, TPMLMessageBoxFlag.ButtonsRightToLeft);

      SetVar('FAKE_ZENITY_VERSION', Version);
      SetVar('FAKE_ZENITY_OUTPUT', Output);
      SetVar('FAKE_ZENITY_EXIT', ExitCode);
      DeleteFile(LogFile);
      Id := -1;
      try
        Ok := PMLShowMessageBox(Data, Id);
      except
        on EPMLError do
          Ok := False;
      end;
      Mine.Clear;
      Mine.AddStrings(ReadLog);
      Mine.Add(Format('R %s id=%d', [BoolToStr(Ok, 'True', 'False'), Id]));
      Same := Want.Text = Mine.Text;
      Inc(Cases);
      if not Same then
      begin
        Inc(Bad);
        for J := 0 to Want.Count - 1 do
          if (J >= Mine.Count) or (Want[J] <> Mine[J]) then
          begin
            WriteLn('    SDL      : ', Want[J]);
            if J < Mine.Count then
              WriteLn('    papimela : ', Mine[J])
            else
              WriteLn('    papimela : (終わり)');
            Break;
          end;
      end;
      Check(Same, '場面 ' + Name);
    end;
    Check(Cases >= 40, Format('%d 場面を比べた', [Cases]));
  finally
    Mine.Free;
    Want.Free;
  end;
end;

procedure TestMore;
var
  Data: TPMLMessageBoxData;
  Id, Major, Minor: Integer;
  Raised, Ok: Boolean;
  Log: TStringList;
begin
  WriteLn('papimela の足した検査');
  SetupEnvironment;
  SetVar('FAKE_ZENITY_VERSION', '3.44.0');
  SetVar('FAKE_ZENITY_EXIT', '1');

  // 版の読み取り
  Check(PMLParseZenityVersion('3.44.0', Major, Minor) and (Major = 3) and (Minor = 44), '3.44.0');
  Check(PMLParseZenityVersion('4', Major, Minor) and (Major = 4) and (Minor = 0), '4 は 4.0');
  Check(PMLParseZenityVersion(' 3.91.2 (extra)', Major, Minor) and (Major = 3) and (Minor = 91), '空白と後ろの文字は読み飛ばす');
  Check(not PMLParseZenityVersion('x3', Major, Minor), '数で始まらない');
  Check(not PMLParseZenityVersion('3.', Major, Minor), '副の版が無い');
  Check(not PMLParseZenityVersion('', Major, Minor), '空');
  Check(PMLParseZenityVersion('0.5', Major, Minor) and (Major = 0) and (Minor = 5), '0.5');

  // 押されたボタンの見分け
  Data := Default(TPMLMessageBoxData);
  SetLength(Data.Buttons, 2);
  Data.Buttons[0].ButtonID := 10; Data.Buttons[0].Text := 'Yes';
  Data.Buttons[1].ButtonID := 20; Data.Buttons[1].Text := 'No';
  Check(PMLZenityPickButton(Data, 'No'#10, Id) and (Id = 20), '改行つき');
  Check(PMLZenityPickButton(Data, 'Yes', Id) and (Id = 10), '改行なし');
  Check(not PMLZenityPickButton(Data, 'Maybe'#10, Id) and (Id = -1), '合わなければ -1');

  // Wayland のセッションかの判定
  SetVar('FAKE_ZENITY_OUTPUT', 'OK'#10);
  Data := Default(TPMLMessageBoxData);
  SetLength(Data.Buttons, 1);
  Data.Buttons[0].Text := 'OK';
  Data.Buttons[0].ButtonID := 5;
  unsetenv('WAYLAND_DISPLAY');
  SetVar('XDG_SESSION_TYPE', 'x11');
  Raised := False;
  try
    PMLShowMessageBox(Data, Id);
  except
    on EPMLUnsupported do Raised := True;
  end;
  Check(Raised, 'WAYLAND_DISPLAY が無く、セッションが x11 なら EPMLUnsupported');
  SetVar('XDG_SESSION_TYPE', 'Wayland');
  Check(PMLShowMessageBox(Data, Id) and (Id = 5), 'セッションが Wayland（大文字小文字を見ない）なら出る');
  unsetenv('XDG_SESSION_TYPE');
  Check(PMLShowMessageBox(Data, Id) and (Id = 5), '何も無ければ出る');
  SetVar('WAYLAND_DISPLAY', 'wayland-test');
  SetVar('XDG_SESSION_TYPE', 'x11');
  Check(PMLShowMessageBox(Data, Id) and (Id = 5), 'WAYLAND_DISPLAY があれば、セッションの種類は見ない');
  unsetenv('XDG_SESSION_TYPE');

  // zenity が無い
  SetVar('PATH', '/nonexistent-dir');
  Raised := False;
  try
    PMLShowMessageBox(Data, Id);
  except
    on EPMLUnsupported do Raised := True;
  end;
  Check(Raised, 'zenity が無ければ EPMLUnsupported');
  SetVar('PATH', FakeDir + ':/usr/bin:/bin');

  // ボタンが多すぎる
  SetLength(Data.Buttons, 9);
  Raised := False;
  try
    PMLShowMessageBox(Data, Id);
  except
    on EPMLArgument do Raised := True;
  end;
  Check(Raised, 'ボタンが 9 個なら EPMLArgument');
  Check(PMLMessageBoxCount = 0, '失敗しても出ている数は 0 に戻る');

  // 単純なメッセージボックス
  DeleteFile(LogFile);
  Ok := PMLShowSimpleMessageBox([TPMLMessageBoxFlag.Warning], 'Simple', 'Hello');
  Log := ReadLog;
  try
    Check(Ok and (Log.Count = 12) and (Log[5] = 'A 5 dialog-warning') and (Log[7] = 'A 7 Simple') and (Log[9] = 'A 9 Hello')
      and (Log[11] = 'A 11 OK'), '単純なメッセージボックスは OK 1 つ');
  finally
    Log.Free;
  end;
  Check(PMLMessageBoxCount = 0, '出ている数は 0');
end;

begin
  WriteLn('=== test_messagebox ===');
  FakeDir := ExtractFilePath(ExpandFileName(ParamStr(0))) + 'fake-zenity';
  if not FileExists(FakeDir + '/zenity') then
    FakeDir := ExpandFileName('test/fake-zenity');
  LogFile := IncludeTrailingPathDelimiter(GetTempDir(False)) + Format('pml-mb-%d.log', [fpGetPID]);
  Check(FileExists(FakeDir + '/zenity'), '偽の zenity がある: ' + FakeDir);
  SetupEnvironment;
  try
    RunRecord;
    TestMore;
  finally
    DeleteFile(LogFile);
  end;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: メッセージボックスが SDL と同じ引数と結果になる ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
