{
  test_documents_portal — Documents ポータルの FileTransfer（鍵とパスの行き来）を実物で検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. セッションバスに繋がらないとき（子のプロセスで DBUS_SESSION_BUS_ADDRESS を壊す）:
       PMLPortalRetrieveFiles は False、TPMLPortalFileTransfer.Create は EPMLUnsupported
    2. 引数: ファイルが無い・開けないのは EPMLArgument
    3. 鍵を作って受け取る: 名前に空白・日本語・% のある 3 つのファイルが、順のまま元のパスで
       返る。既定では 2 回目も受け取れ、AAutoStop = True なら 2 回目は False。
       末尾に NUL の付いた鍵も受け付ける
    4. 作った側を先に捨てると、鍵は無効
    5. 無効な鍵・空の鍵・ファイルの無い鍵は False（例外にしない）。末尾の改行も受け付ける

  WHY:
    D&D の受信の document-portal の枝（Flatpak などのサンドボックス）と、送り側が鍵を
    渡す経路。どちらもこのユニットを通るので、ポータルの実物で約束を確かめる。

  実行前提: セッションバスと xdg-document-portal（org.freedesktop.portal.Documents）。
    無い環境で飛ばしてよいときは PAPIMELA_PORTAL_OPTIONAL=1（既定では失敗にする）。
}
program test_documents_portal;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, BaseUnix,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.DBus,
  PaPiMeLa.Platform.DocumentPortal;

function setenv(AName, AValue: PAnsiChar; AOverwrite: LongInt): LongInt; cdecl; external 'c';

var
  Failures: Integer = 0;
  Dir: String;
  Files: array[0..2] of String;

procedure Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
    WriteLn('  [PASS] ', ALabel)
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(Failures);
  end;
  Flush(Output);
end;

function Join(const A: TStringArray): String;
var
  S: String;
begin
  Result := '';
  for S in A do
  begin
    if Result <> '' then
      Result := Result + ' | ';
    Result := Result + S;
  end;
end;

procedure MakeFiles;
var
  I: Integer;
  T: TextFile;
begin
  Dir := GetTempDir(False) + 'papimela-portal-' + IntToStr(FpGetPid) + '/';
  ForceDirectories(Dir);
  Files[0] := Dir + 'hello world.txt';
  Files[1] := Dir + '日本語 ファイル.txt';
  Files[2] := Dir + '100%.txt';
  for I := 0 to High(Files) do
  begin
    AssignFile(T, Files[I]);
    Rewrite(T);
    WriteLn(T, I);
    CloseFile(T);
  end;
end;

procedure RemoveFiles;
var
  F: String;
begin
  for F in Files do
    DeleteFile(F);
  RemoveDir(Dir);
end;

{ 子のプロセスで、セッションバスの番地を壊して呼ぶ。libdbus は番地を最初の接続で
  覚えるので、親で D-Bus を使う前に分ける。終了コード: 0 = 両方とも約束どおり。 }
procedure TestNoBus;
var
  Pid: TPid;
  Status: cint;
  Paths: TStringArray;
  Code: Integer;
  T: TPMLPortalFileTransfer;
begin
  WriteLn('1. セッションバスに繋がらない（子のプロセス）');
  Flush(Output);
  Pid := FpFork;
  if Pid = 0 then
  begin
    setenv('DBUS_SESSION_BUS_ADDRESS', 'unix:path=/nonexistent/papimela-no-bus', 1);
    Code := 0;
    try
      if PMLPortalRetrieveFiles('123', Paths) then
        Code := Code or 1;
    except
      Code := Code or 2;
    end;
    try
      T := TPMLPortalFileTransfer.Create([Files[0]]);
      T.Free;
      Code := Code or 4;
    except
      on E: EPMLUnsupported do ;  // rawpaco:ignore RAWPACO-DEFENSE-001 — これが約束
      on E: Exception do
        Code := Code or 8;
    end;
    FpExit(Code);
  end;
  FpWaitPid(Pid, @Status, 0);
  Code := wexitstatus(Status);
  Check(Code and 3 = 0, Format('PMLPortalRetrieveFiles は例外にせず False（子の結果 %d）', [Code]));
  Check(Code and 12 = 0, Format('TPMLPortalFileTransfer.Create は EPMLUnsupported（子の結果 %d）', [Code]));
  WriteLn;
end;

{ ファイルを 1 つも足さない鍵を、自分の接続で作る（TPMLPortalFileTransfer は 0 個を断るので）。
  鍵は AConn が開いている間だけ有効。 }
function EmptyTransferKey(out AConn: TPMLDBusConnection): String;
var
  M, R: PDBusMessage;
  W, D: TPMLDBusWriter;
begin
  AConn := TPMLDBusConnection.Create;
  M := AConn.BeginCall('org.freedesktop.portal.Documents', '/org/freedesktop/portal/documents',
    'org.freedesktop.portal.FileTransfer', 'StartTransfer');
  try
    W := AConn.Writer(M);
    D := W.OpenArray('{sv}');
    W.Close(D);
    R := AConn.Send(M);
    try
      Result := AConn.Reader(R).ExpectString;
    finally
      AConn.Unref(R);
    end;
  finally
    AConn.Unref(M);
  end;
end;

function RaisesArg(const APaths: array of String): Boolean;
var
  T: TPMLPortalFileTransfer;
begin
  Result := False;
  try
    T := TPMLPortalFileTransfer.Create(APaths);
    T.Free;
  except
    on E: EPMLArgument do
      Result := True;
  end;
end;

procedure TestTransfer;
var
  Got: Boolean;
  T: TPMLPortalFileTransfer;
  Paths: TStringArray;
  K: String;
  C: TPMLDBusConnection;
begin
  WriteLn('2. 引数');
  Check(RaisesArg([]), 'ファイルが無いのは EPMLArgument');
  Check(RaisesArg([Files[0], Dir + 'no-such-file']), '開けないファイルがあれば EPMLArgument');
  WriteLn;

  WriteLn('3. 鍵を作って受け取る');
  T := TPMLPortalFileTransfer.Create(Files);
  try
    Check(T.Key <> '', '鍵がある（' + T.Key + '）');
    // Check の引数（ラベルの Join）は呼び出しより先に評価されるので、先に受け取っておく。
    Got := PMLPortalRetrieveFiles(T.Key, Paths);
    Check(Got and (Length(Paths) = 3)
      and (Paths[0] = Files[0]) and (Paths[1] = Files[1]) and (Paths[2] = Files[2]),
      '3 つのファイルが順のまま元のパスで返る（' + Join(Paths) + '）');
    Check(PMLPortalRetrieveFiles(T.Key, Paths) and (Length(Paths) = 3),
      '2 回目も受け取れる（既定は autostop を切る。ドラッグでは通りがかった相手も読む）');
  finally
    T.Free;
  end;
  T := TPMLPortalFileTransfer.Create([Files[1]]);
  try
    Check(PMLPortalRetrieveFiles(T.Key + #0, Paths) and (Length(Paths) = 1) and (Paths[0] = Files[1]),
      '末尾に NUL の付いた鍵（パイプで受け取ったまま）も受け付ける');
  finally
    T.Free;
  end;
  WriteLn;

  T := TPMLPortalFileTransfer.Create([Files[2]]);
  try
    Check(PMLPortalRetrieveFiles(T.Key + #10, Paths) and (Length(Paths) = 1) and (Paths[0] = Files[2]),
      '末尾に改行の付いた鍵も受け付ける');
  finally
    T.Free;
  end;
  WriteLn;

  T := TPMLPortalFileTransfer.Create([Files[0]], True);
  try
    Check(PMLPortalRetrieveFiles(T.Key, Paths) and (Length(Paths) = 1),
      'AAutoStop = True でも 1 回目は受け取れる');
    Check(not PMLPortalRetrieveFiles(T.Key, Paths) and (Length(Paths) = 0),
      'AAutoStop = True なら 2 回目は False（1 回で無効）');
  finally
    T.Free;
  end;
  WriteLn;

  WriteLn('4. 作った側を先に捨てる');
  T := TPMLPortalFileTransfer.Create([Files[0]]);
  K := T.Key;
  T.Free;
  Check(not PMLPortalRetrieveFiles(K, Paths), '捨てたあとの鍵は無効');
  WriteLn;

  WriteLn('5. 無効な鍵');
  K := EmptyTransferKey(C);
  try
    Check((K <> '') and not PMLPortalRetrieveFiles(K, Paths) and (Length(Paths) = 0),
      'ファイルの無い鍵（受け取りは成功するが 0 個）は False');
  finally
    C.Free;
  end;
  Check(not PMLPortalRetrieveFiles('papimela-not-a-key', Paths) and (Length(Paths) = 0),
    '無効な鍵は False（例外にしない）');
  Check(not PMLPortalRetrieveFiles('', Paths), '空の鍵は False');
  WriteLn;
end;

function PortalPresent: Boolean;
var
  C: TPMLDBusConnection;
begin
  Result := False;
  try
    C := TPMLDBusConnection.Create;
    try
      Result := C.NameHasOwner('org.freedesktop.portal.Documents');
    finally
      C.Free;
    end;
  except
    on E: Exception do
      WriteLn('  [INFO] セッションバスに繋がらない: ', E.Message);
  end;
end;

begin
  WriteLn('test_documents_portal — Documents ポータルの FileTransfer');
  WriteLn;
  MakeFiles;
  try
    TestNoBus;
    if not PortalPresent then
    begin
      if GetEnvironmentVariable('PAPIMELA_PORTAL_OPTIONAL') = '1' then
      begin
        WriteLn('  [SKIP] org.freedesktop.portal.Documents が無い');
        Exit;
      end;
      Check(False, 'org.freedesktop.portal.Documents がセッションバスにある');
    end
    else
      TestTransfer;
  finally
    RemoveFiles;
  end;
  if Failures = 0 then
    WriteLn('=== 結論: 鍵とパスが Documents ポータルを通って約束どおりに行き来する ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
