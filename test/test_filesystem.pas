{
  test_filesystem — パスとファイルシステム、大文字小文字の畳み込み（PaPiMeLa.FileSystem、PaPiMeLa.Unicode.CaseFold）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 畳み込み: SDL_CaseFoldUnicode を 0〜0x10FFFF の全コードポイントに通した記録（test/casefold_expected.inc。
       tools/filesystem-expect/gen.bb が作る）と PMLCaseFoldCodepoint を突き合わせる。UTF-8 の読み進めも突き合わせる
       （SDL の不具合 D-82 の行は、papimela の正しい値で別に確かめる）。
    2. フォルダの操作: 参照版 SDL に同じ操作を通した記録（test/filesystem_expected.inc）と、TPMLFileSystem の結果を
       行ごとに突き合わせる: Glob（* と ? / と大文字小文字を見ない比べ・基準のパスの終わりの / ・
       無いフォルダ）、列挙（成功/失敗で止める・終わりの / の整理）、情報、作る（親も・もうあれば成功・ファイルが邪魔）、
       消す（無くても成功・空でないフォルダは失敗）、名前を変える、写す（4096 を跨ぐ大きさ・上書き）、今のフォルダ。
    3. 環境変数の場面: HOME・XDG_DATA_HOME・XDG_CONFIG_HOME と user-dirs.dirs を変えて、ユーザーのフォルダ 11 種と
       設定のフォルダを突き合わせる（引用符・エスケープ・最後の行が勝つ・511 文字を越える行・ファイルの無い場合）。
    4. papimela の足した検査: 実行ファイルの場所と名前、環境変数が空で設定されたとき（D-83）、ワイルドカード照合の単独、
       畳み込みの文字列、UTF-8 の正しい読み方（D-82）。
}
program test_filesystem;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils, Classes, BaseUnix, ctypes,
  PaPiMeLa.Errors,
  PaPiMeLa.FileSystem,
  PaPiMeLa.Unicode.CaseFold;

{$I casefold_expected.inc}
{$I filesystem_expected.inc}

function setenv(AName, AValue: PChar; AOverwrite: cint): cint; cdecl; external 'c' name 'setenv';
function unsetenv(AName: PChar): cint; cdecl; external 'c' name 'unsetenv';

var
  Failures: Integer = 0;
  Base: String;
  Mine: TStringList;

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

function IntList(const AValues: array of Integer): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AValues) do
    Result := Result + Format(' %x', [AValues[I]]);
end;

{ ---- 1. 畳み込み ---- }

procedure TestCaseFold;
var
  Want: TStringList;
  I, N, FoldedCount, Bad, P: Integer;
  Line: String;
  Parts: TStringList;
  CP: LongWord;
  Folded: TPMLFoldedCodepoints;
  Seen: array of Boolean;
  Bytes, Got: String;
  Pos_: Integer;
  Cp2: LongWord;
begin
  WriteLn('大文字小文字の畳み込み（SDL_CaseFoldUnicode と同じ）');
  Parts := TStringList.Create;
  Parts.Delimiter := ' ';
  Parts.StrictDelimiter := True;
  SetLength(Seen, $110000);
  FoldedCount := 0;
  Bad := 0;
  try
    // 記録にある（畳み込みのある）コードポイント
    for I := 0 to High(CaseFoldExpected) do
    begin
      Line := CaseFoldExpected[I];
      if Copy(Line, 1, 2) <> 'F ' then
        Continue;
      Parts.DelimitedText := Line;
      CP := StrToInt('$' + Parts[1]);
      N := PMLCaseFoldCodepoint(CP, Folded);
      Seen[CP] := True;
      Inc(FoldedCount);
      if (N <> StrToInt(Parts[2])) or (Folded[0] <> StrToInt('$' + Parts[3]))
      or ((N > 1) and (Folded[1] <> StrToInt('$' + Parts[4])))
      or ((N > 2) and (Folded[2] <> StrToInt('$' + Parts[5]))) then
      begin
        Inc(Bad);
        if Bad <= 3 then
          WriteLn('    ', Line, ' papimela n=', N, ' ', IntToHex(Folded[0], 1));
      end;
    end;
    // 記録に無いコードポイントは畳み込まれない（全範囲）
    for CP := 0 to $10FFFF do
      if not Seen[CP] then
      begin
        N := PMLCaseFoldCodepoint(CP, Folded);
        if (N <> 1) or (Folded[0] <> CP) then
        begin
          Inc(Bad);
          if Bad <= 3 then
            WriteLn('    U+', IntToHex(CP, 4), ' は SDL では畳み込まれない');
        end;
      end;
    Check(FoldedCount >= 1500, Format('畳み込みのあるコードポイント %d 件', [FoldedCount]));
    Check(Bad = 0, Format('0〜10FFFF の全部が SDL と同じ（食い違い %d 件）', [Bad]));

    // UTF-8 の読み進め
    Bad := 0;
    N := 0;
    for I := 0 to High(CaseFoldExpected) do
    begin
      Line := CaseFoldExpected[I];
      if Copy(Line, 1, 2) = 'U ' then
      begin
        Parts.DelimitedText := Line;
        Bytes := Parts[1];
        SetLength(Got, 0);
        Got := '';
        for P := 0 to Length(Bytes) div 2 - 1 do
          Got := Got + Chr(StrToInt('$' + Copy(Bytes, P * 2 + 1, 2)));
        Pos_ := 1;
        Cp2 := PMLStepUTF8(Got, Pos_);
        Bytes := '';
        while Cp2 <> 0 do
        begin
          Bytes := Bytes + ' ' + LowerCase(IntToHex(Cp2, 1));
          Cp2 := PMLStepUTF8(Got, Pos_);
        end;
        Inc(N);
        Got := Copy(Line, Pos('=', Line) + 2, MaxInt);
        if Trim(Got) <> Trim(Bytes) then
        begin
          Inc(Bad);
          WriteLn('    ', Line, ' papimela=', Bytes);
        end;
      end;
    end;
    Check((N >= 15) and (Bad = 0), Format('UTF-8 の読み進め %d 件が SDL と同じ（食い違い %d）', [N, Bad]));
  finally
    Parts.Free;
  end;
end;

{ ---- 4. 畳み込みの文字列、D-82 ---- }

procedure TestCaseFoldMore;
var
  P: Integer;
  S: String;
begin
  WriteLn('畳み込みの文字列と UTF-8（papimela の検査）');
  Check(PMLCaseFoldUTF8('Hello World.TXT') = 'hello world.txt', '英字');
  Check(PMLCaseFoldUTF8('Äpfel') = 'äpfel', 'Ä は ä');
  Check(PMLCaseFoldUTF8('Straße') = 'strasse', 'ß は ss（2 文字になる）');
  Check(PMLCaseFoldUTF8('ΣΊΣΥΦΟΣ') = 'σίσυφοσ', 'ギリシャ文字');
  Check(PMLCaseFoldUTF8('') = '', '空');
  S := #$F0#$A0#$80#$80;                 // U+20000
  P := 1;
  Check(PMLStepUTF8(S, P) = $20000, 'U+20000 を正しく読む（SDL は U+FFFD にする。D-82）');
  S := #$F3#$A0#$80#$80;                 // U+E0000
  P := 1;
  Check(PMLStepUTF8(S, P) = $E0000, 'U+E0000 を正しく読む（SDL は U+C0000 にする。D-82）');
  S := 'a';
  P := 5;
  Check(PMLStepUTF8(S, P) = 0, '範囲外は 0');
  S := '';
  PMLAppendCodepointUTF8(S, $20AC);
  PMLAppendCodepointUTF8(S, $1F600);
  PMLAppendCodepointUTF8(S, $110000);
  Check(S = #$E2#$82#$AC#$F0#$9F#$98#$80, 'UTF-8 への書き出し（範囲外は足さない）');
end;

{ ---- 2. フォルダの操作 ---- }

procedure L(const AText: String);
var
  S: String;
begin
  // 作業のフォルダを <T> に
  S := StringReplace(AText, Base, '<T>', [rfReplaceAll]);
  Mine.Add(S);
end;

procedure Mkd(const ARel: String);
begin
  fpMkdir(Base + '/' + ARel, &777);
end;

procedure Mkf(const ARel, AContent: String);
var
  F: TFileStream;
begin
  F := TFileStream.Create(Base + '/' + ARel, fmCreate);
  try
    if AContent <> '' then
      F.WriteBuffer(AContent[1], Length(AContent));
  finally
    F.Free;
  end;
end;

procedure Mkl(const ATarget, ARel: String);
begin
  fpSymlink(PChar(ATarget), PChar(Base + '/' + ARel));
end;

function ByteCompare(List: TStringList; A, B: Integer): Integer;
var
  SA, SB: String;
  I, N: Integer;
begin
  SA := List[A];
  SB := List[B];
  N := Length(SA);
  if Length(SB) < N then
    N := Length(SB);
  for I := 1 to N do
    if SA[I] <> SB[I] then
      Exit(Ord(SA[I]) - Ord(SB[I]));
  Result := Length(SA) - Length(SB);
end;

function SortedBytes(AList: TStringList): String;
var
  Copy_: TStringList;
  I: Integer;
begin
  Copy_ := TStringList.Create;
  try
    Copy_.Assign(AList);
    Copy_.CustomSort(@ByteCompare);
    Result := '';
    for I := 0 to Copy_.Count - 1 do
      Result := Result + Copy_[I] + ';';
  finally
    Copy_.Free;
  end;
end;

procedure GlobCase(const ARelBase: String; AHasPattern: Boolean; const APattern: String; AFlags: Integer);
var
  Path, Pat, R: String;
  Items: TStringList;
  Arr: TStringArray;
  I: Integer;
  Flags: TPMLGlobFlags;
begin
  Path := Base;
  if ARelBase <> '' then
    Path := Path + '/' + ARelBase;
  if AHasPattern then
    Pat := APattern
  else
    Pat := '(null)';
  Flags := [];
  if AFlags <> 0 then
    Flags := [TPMLGlobFlag.CaseInsensitive];
  try
    if AHasPattern then
      Arr := TPMLFileSystem.Glob(Path, APattern, Flags)
    else
      Arr := TPMLFileSystem.GlobAll(Path);
  except
    on EPMLIOError do
    begin
      L(Format('G %s | %s | %d -> NULL (count 0)', [ARelBase, Pat, AFlags]));
      Exit;
    end;
  end;
  Items := TStringList.Create;
  try
    for I := 0 to High(Arr) do
      Items.Add(Arr[I]);
    R := SortedBytes(Items);
    L(Format('G %s | %s | %d -> %d: %s', [ARelBase, Pat, AFlags, Length(Arr), R]));
  finally
    Items.Free;
  end;
end;

type
  TEnumRecorder = class
  public
    Dirs: String;
    Names: TStringList;
    N, StopAfter, FailAfter: Integer;
    constructor Create;
    destructor Destroy; override;
    function OnEntry(const ADirName, AName: String): TPMLEnumerationResult;
  end;

constructor TEnumRecorder.Create;
begin
  inherited Create;
  Names := TStringList.Create;
end;

destructor TEnumRecorder.Destroy;
begin
  Names.Free;
  inherited Destroy;
end;

function TEnumRecorder.OnEntry(const ADirName, AName: String): TPMLEnumerationResult;
begin
  if N = 0 then
    Dirs := ADirName;
  Names.Add(AName);
  Inc(N);
  if (StopAfter > 0) and (N >= StopAfter) then
    Exit(TPMLEnumerationResult.Success);
  if (FailAfter > 0) and (N >= FailAfter) then
    Exit(TPMLEnumerationResult.Failure);
  Result := TPMLEnumerationResult.Continue;
end;

procedure EnumCase(const ARel: String; AStop, AFail: Integer);
var
  Rec: TEnumRecorder;
  Ok: Boolean;
  Dir_: String;
begin
  Rec := TEnumRecorder.Create;
  try
    Rec.StopAfter := AStop;
    Rec.FailAfter := AFail;
    try
      Ok := TPMLFileSystem.EnumerateDirectory(Base + ARel, @Rec.OnEntry);
    except
      on EPMLIOError do
        Ok := False;
    end;
    if Rec.N > 0 then
      Dir_ := Rec.Dirs
    else
      Dir_ := '-';
    if (AStop > 0) or (AFail > 0) then
      L(Format('E %s stop=%d fail=%d -> %d, n=%d dir=%s', [ARel, AStop, AFail, Ord(Ok), Rec.N, Dir_]))
    else
      L(Format('E %s -> %d, n=%d dir=%s names=%s', [ARel, Ord(Ok), Rec.N, Dir_, SortedBytes(Rec.Names)]));
  finally
    Rec.Free;
  end;
end;

function TypeName(AType: TPMLPathType): String;
begin
  case AType of
    TPMLPathType.RegularFile: Result := 'file';
    TPMLPathType.Directory: Result := 'dir';
    TPMLPathType.Other: Result := 'other';
  else
    Result := 'none';
  end;
end;

procedure InfoCase(const ARel: String);
var
  Info: TPMLPathInfo;
begin
  if TPMLFileSystem.GetPathInfo(Base + '/' + ARel, Info) then
    L(Format('I %s -> %s size=%d times=%d', [ARel, TypeName(Info.PathType), Info.Size,
      Ord((Info.CreateTime > 0) and (Info.ModifyTime > 0) and (Info.AccessTime > 0))]))
  else
    L(Format('I %s -> fail', [ARel]));
end;

procedure DoOp(const ATag, ALabel: String; AOk: Boolean);
begin
  L(Format('%s %s -> %d', [ATag, ALabel, Ord(AOk)]));
end;

function TryCreateDir(const APath: String): Boolean;
begin
  Result := True;
  try
    TPMLFileSystem.CreateDirectory(APath);
  except
    on EPMLIOError do
      Result := False;
  end;
end;

function TryRemove(const APath: String): Boolean;
begin
  Result := True;
  try
    TPMLFileSystem.RemovePath(APath);
  except
    on EPMLIOError do
      Result := False;
  end;
end;

function TryRename(const A, B: String): Boolean;
begin
  Result := True;
  try
    TPMLFileSystem.RenamePath(A, B);
  except
    on EPMLIOError do
      Result := False;
  end;
end;

function TryCopy(const A, B: String): Boolean;
begin
  Result := True;
  try
    TPMLFileSystem.CopyFile(A, B);
  except
    on E: Exception do
      Result := False;
  end;
end;

procedure Ops;
var
  Big: String;
  I: Integer;
  F: TFileStream;

  procedure CD(const ARel: String);
  begin
    DoOp('CD', ARel, TryCreateDir(Base + '/' + ARel));
  end;
  procedure RM(const ARel: String);
  begin
    DoOp('RM', ARel, TryRemove(Base + '/' + ARel));
  end;
  procedure RN(const AO, AN: String);
  begin
    DoOp('RN', AO + ' ' + AN, TryRename(Base + '/' + AO, Base + '/' + AN));
  end;
  procedure CP(const AO, AN: String);
  begin
    DoOp('CP', AO + ' ' + AN, TryCopy(Base + '/' + AO, Base + '/' + AN));
  end;

begin
  Mkd('a'); Mkd('a/c'); Mkd('empty'); Mkd('sub dir'); Mkd('ß'); Mkd('Dir');
  Mkf('a/b.txt', 'hello'); Mkf('a/B.TXT', 'HELLO!'); Mkf('a/c/d.txt', 'd'); Mkf('a/c/E.md', '# e');
  Mkf('ß/ss.txt', 's'); Mkf('Äpfel.txt', 'a'); Mkf('äpfel.TXT', 'b'); Mkf('x.y', 'xy'); Mkf('.hidden', 'h');
  Mkf('sub dir/f', 'f'); Mkf('Dir/File.TXT', 'F'); Mkf('Dir/file.txt', 'f');
  Mkl('a/b.txt', 'flink');

  GlobCase('', False, '', 0);
  GlobCase('', True, '*', 0);
  GlobCase('', True, '*/', 0);
  GlobCase('', True, '*.txt', 0);
  GlobCase('', True, '*.txt', 1);
  GlobCase('', True, '*.TXT', 0);
  GlobCase('', True, 'a/*', 0);
  GlobCase('', True, 'a/*/*', 0);
  GlobCase('', True, 'a/*.TXT', 1);
  GlobCase('', True, '?', 0);
  GlobCase('', True, '??', 0);
  GlobCase('', True, 'x.?', 0);
  GlobCase('', True, 'a?b.txt', 0);
  GlobCase('', True, 'a/?.txt', 0);
  GlobCase('', True, '*/d.txt', 0);
  GlobCase('', True, '*/*/d.txt', 0);
  GlobCase('', True, '**', 0);
  GlobCase('', True, 'a/**', 0);
  GlobCase('', True, '.*', 0);
  GlobCase('', True, '*d.txt', 0);
  GlobCase('', True, '*.md', 0);
  GlobCase('', True, '', 0);
  GlobCase('', True, 'a', 0);
  GlobCase('', True, 'a/', 0);
  GlobCase('', True, 'a/c', 0);
  GlobCase('', True, '[ab]', 0);
  GlobCase('', True, 'sub*', 0);
  GlobCase('', True, 'sub?dir/*', 0);
  GlobCase('', True, 'ÄPFEL.TXT', 1);
  GlobCase('', True, 'ÄPFEL.TXT', 0);
  GlobCase('', True, 'ä*', 1);
  GlobCase('', True, 'SS/SS.TXT', 1);
  GlobCase('', True, 'ß/*', 0);
  GlobCase('', True, 'ß/*', 1);
  GlobCase('', True, 'dir/file.txt', 1);
  GlobCase('', True, 'DIR/*', 1);
  GlobCase('', True, 'DIR/*', 0);
  GlobCase('', True, '*', 1);
  GlobCase('', False, '', 1);
  GlobCase('a', False, '', 0);
  GlobCase('a', True, '*', 0);
  GlobCase('a', True, 'c/*', 0);
  GlobCase('a', True, '*.txt', 1);
  GlobCase('a/', True, '*', 0);
  GlobCase('a//', True, '*', 0);
  GlobCase('a/c', True, '*', 0);
  GlobCase('missing', True, '*', 0);
  GlobCase('x.y', True, '*', 0);
  GlobCase('empty', False, '', 0);
  GlobCase('flink', False, '', 0);

  EnumCase('', 0, 0);
  EnumCase('/a', 0, 0);
  EnumCase('/a/', 0, 0);
  EnumCase('/a//', 0, 0);
  EnumCase('/a/c', 0, 0);
  EnumCase('/empty', 0, 0);
  EnumCase('/a', 1, 0);
  EnumCase('/a', 0, 1);
  EnumCase('/a', 0, 99);
  EnumCase('/missing', 0, 0);
  EnumCase('/x.y', 0, 0);
  EnumCase('/sub dir', 0, 0);

  InfoCase('a'); InfoCase('a/b.txt'); InfoCase('x.y'); InfoCase('flink'); InfoCase('empty'); InfoCase('missing');
  InfoCase('a/'); InfoCase('a/b.txt/');

  CD('n1/n2/n3');
  CD('n1/n2/n3');
  CD('t1/t2/');
  CD('t1/t2//');
  CD('a');
  CD('x.y');
  CD('x.y/z');
  CD('a/b.txt/q');
  CD('p/q/r/s/t/u');
  InfoCase('n1/n2/n3'); InfoCase('t1/t2'); InfoCase('p/q/r/s/t/u');
  DoOp('CD', 'empty', TryCreateDir(''));
  DoOp('CD', 'slash', TryCreateDir('/'));

  RM('x.y');
  RM('x.y');
  RM('empty');
  RM('a');
  RM('n1/n2/n3');
  RM('missing/deep');
  RM('flink');
  InfoCase('a/b.txt'); InfoCase('x.y'); InfoCase('empty'); InfoCase('n1/n2');

  RN('a/B.TXT', 'a/renamed.txt');
  RN('missing', 'gone');
  RN('a/c', 'a/c2');
  RN('a/b.txt', 'a/c2/d.txt');
  RN('Dir', 'a/c2/Dir');
  InfoCase('a/renamed.txt'); InfoCase('a/B.TXT'); InfoCase('a/c2/d.txt'); InfoCase('a/c2/Dir/File.TXT');

  CP('a/c2/d.txt', 'copy1.txt');
  CP('a/c2/d.txt', 'copy1.txt');
  CP('a/renamed.txt', 'copy1.txt');
  CP('missing', 'copy2.txt');
  CP('a/c2/d.txt', 'missing/dir/copy3.txt');
  CP('a', 'copy4');
  CP('empty_none', 'copy5');
  InfoCase('copy1.txt'); InfoCase('copy2.txt');
  SetLength(Big, 20000);
  for I := 1 to 20000 do
    Big[I] := Chr(Ord('A') + (I - 1) mod 26);
  F := TFileStream.Create(Base + '/big.bin', fmCreate);
  try
    F.WriteBuffer(Big[1], 20000);
  finally
    F.Free;
  end;
  CP('big.bin', 'big2.bin');
  InfoCase('big2.bin');

  fpChdir(Base);
  L('CWD ' + TPMLFileSystem.CurrentDirectory);
end;

{ ---- 3. 環境変数の場面 ---- }

const
  StdDirs =
    '# comment'#10 +
    'XDG_DESKTOP_DIR="$HOME/Desktop"'#10 +
    'XDG_DOWNLOAD_DIR="$HOME/Downloads"'#10 +
    'XDG_TEMPLATES_DIR="$HOME/Templates"'#10 +
    'XDG_PUBLICSHARE_DIR="$HOME/Public"'#10 +
    'XDG_DOCUMENTS_DIR="$HOME/Documents"'#10 +
    'XDG_MUSIC_DIR="$HOME/Music"'#10 +
    'XDG_PICTURES_DIR="$HOME/Pictures"'#10 +
    'XDG_VIDEOS_DIR="$HOME/Videos"'#10;
  OddDirs =
    '  '#9'XDG_DESKTOP_DIR  =  "/abs/desk top"'#10 +
    'XDG_DOWNLOAD_DIR="$HOME/Down\"loads"'#10 +
    'XDG_MUSIC_DIR="relative/music"'#10 +
    'XDG_PICTURES_DIR=$HOME/NoQuotes'#10 +
    'XDG_VIDEOS_DIR="$HOME/First"'#10 +
    'XDG_VIDEOS_DIR="$HOME/Last"'#10 +
    'XDG_DOCUMENTS_DIR="$HOME/Docs" trailing'#10 +
    'XDG_TEMPLATES_DIR="$HOME/Tmpl\\x"'#10 +
    'XDG_PUBLICSHARE_DIR_EXTRA="$HOME/Nope"'#10 +
    'XDG_DESKTOPX_DIR="$HOME/Nope"'#10 +
    'XDG_MUSIC_DIR="/bad';

type
  TEnvCase = record
    Name, Home, XdgData, XdgConfig: String;
    HomeSet, DataSet, ConfigSet: Boolean;
    Dirs: Integer;      // 0 なし、1 標準、2 変わったもの、3 長い行
  end;

const
  EnvCases: array[0..11] of TEnvCase = (
    (Name: 'std'; Home: '@T/home'; XdgData: ''; XdgConfig: ''; HomeSet: True; DataSet: False; ConfigSet: False; Dirs: 1),
    (Name: 'std-xdgdata'; Home: '@T/home'; XdgData: '@T/data'; XdgConfig: ''; HomeSet: True; DataSet: True; ConfigSet: False; Dirs: 1),
    (Name: 'std-xdgdata-slash'; Home: '@T/home'; XdgData: '@T/data/'; XdgConfig: ''; HomeSet: True; DataSet: True; ConfigSet: False; Dirs: 1),
    (Name: 'std-xdgconfig'; Home: '@T/home'; XdgData: ''; XdgConfig: '@T/cfg'; HomeSet: True; DataSet: False; ConfigSet: True; Dirs: 1),
    (Name: 'std-home-slash'; Home: '@T/home/'; XdgData: ''; XdgConfig: ''; HomeSet: True; DataSet: False; ConfigSet: False; Dirs: 1),
    (Name: 'nofile'; Home: '@T/home'; XdgData: ''; XdgConfig: ''; HomeSet: True; DataSet: False; ConfigSet: False; Dirs: 0),
    (Name: 'odd'; Home: '@T/home'; XdgData: ''; XdgConfig: ''; HomeSet: True; DataSet: False; ConfigSet: False; Dirs: 2),
    (Name: 'long'; Home: '@T/home'; XdgData: ''; XdgConfig: ''; HomeSet: True; DataSet: False; ConfigSet: False; Dirs: 3),
    (Name: 'nohome'; Home: ''; XdgData: ''; XdgConfig: ''; HomeSet: False; DataSet: False; ConfigSet: False; Dirs: 0),
    (Name: 'nohome-xdgdata'; Home: ''; XdgData: '@T/data'; XdgConfig: ''; HomeSet: False; DataSet: True; ConfigSet: False; Dirs: 0),
    (Name: 'emptyhome'; Home: ''; XdgData: ''; XdgConfig: ''; HomeSet: True; DataSet: False; ConfigSet: False; Dirs: 0),
    (Name: 'emptyconfig'; Home: '@T/home'; XdgData: ''; XdgConfig: ''; HomeSet: True; DataSet: False; ConfigSet: True; Dirs: 0));

  FolderNames: array[TPMLUserFolder] of String = ('home', 'desktop', 'documents', 'downloads', 'music',
    'pictures', 'publicshare', 'savedgames', 'screenshots', 'templates', 'videos');

procedure SetEnv_(const AName, AValue: String; ASet: Boolean);
begin
  if ASet then
    setenv(PChar(AName), PChar(StringReplace(AValue, '@T', Base, [rfReplaceAll])), 1)
  else
    unsetenv(PChar(AName));
end;

procedure EnvScene(const C: TEnvCase);
var
  Content, FileName: String;
  F: TFileStream;
  Folder: TPMLUserFolder;
  I, K: Integer;
  R: String;
  Prefs: array[0..3, 0..1] of String;
begin
  Prefs[0, 0] := 'Org';    Prefs[0, 1] := 'App';
  Prefs[1, 0] := '';       Prefs[1, 1] := 'App2';
  Prefs[2, 0] := 'My Org'; Prefs[2, 1] := 'My App 3';
  Prefs[3, 0] := 'o/rg';   Prefs[3, 1] := 'a/pp';
  SetEnv_('HOME', C.Home, C.HomeSet);
  SetEnv_('XDG_DATA_HOME', C.XdgData, C.DataSet);
  SetEnv_('XDG_CONFIG_HOME', C.XdgConfig, C.ConfigSet);
  Mkd('home'); Mkd('data'); Mkd('cfg'); Mkd('.cfgdummy');
  case C.Dirs of
    1: Content := StdDirs;
    2: Content := OddDirs;
    3:
    begin
      Content := 'XDG_DESKTOP_DIR="$HOME/';
      for K := 1 to 600 do
        Content := Content + 'x';
      Content := Content + '"'#10'XDG_MUSIC_DIR="$HOME/AfterLong"'#10;
    end;
  else
    Content := '';
  end;
  if C.Dirs > 0 then
  begin
    if C.ConfigSet and (C.XdgConfig <> '') then
      FileName := Base + '/cfg/user-dirs.dirs'
    else
    begin
      fpMkdir(Base + '/home/.config', &777);
      FileName := Base + '/home/.config/user-dirs.dirs';
    end;
    F := TFileStream.Create(FileName, fmCreate);
    try
      F.WriteBuffer(Content[1], Length(Content));
    finally
      F.Free;
    end;
  end;
  L('ENV ' + C.Name);
  for Folder := Low(TPMLUserFolder) to High(TPMLUserFolder) do
  begin
    try
      R := TPMLFileSystem.UserFolder(Folder);
    except
      on EPMLIOError do R := 'NULL';
      on EPMLUnsupported do R := 'NULL';
    end;
    L(Format('UF %s -> %s', [FolderNames[Folder], R]));
  end;
  for I := 0 to 3 do
  begin
    try
      R := TPMLFileSystem.PrefPath(Prefs[I, 0], Prefs[I, 1]);
    except
      on EPMLIOError do R := 'NULL';
    end;
    L(Format('PP ''%s'' ''%s'' -> %s', [Prefs[I, 0], Prefs[I, 1], R]));
    if R <> 'NULL' then
      L(Format('PP exists %d', [Ord(DirectoryExists(R))]));
  end;
end;

procedure RemoveTree(const APath: String);
var
  SR: TSearchRec;
begin
  if FindFirst(APath + '/*', faAnyFile or faSymLink, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') then
          if ((SR.Attr and faDirectory) <> 0) and ((SR.Attr and faSymLink) = 0) then
            RemoveTree(APath + '/' + SR.Name)
          else
            fpUnlink(APath + '/' + SR.Name);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
  fpRmDir(APath);
end;

function NewWorkDir(const ATag: String): String;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) + Format('pml-fs-%s-%d', [ATag, fpGetPID]);
  RemoveTree(Result);
  ForceDirectories(Result);
end;

procedure RunEnvScenes;
var
  I: Integer;
  Saved: String;
begin
  for I := 0 to High(EnvCases) do
  begin
    Saved := Base;
    Base := NewWorkDir('env' + IntToStr(I));
    try
      EnvScene(EnvCases[I]);
    finally
      RemoveTree(Base);
      Base := Saved;
    end;
  end;
end;

{ 記録の行を場面（ops と ENV 名）ごとに切って比べる }
procedure CompareRecord;
var
  Want: TStringList;
  I, Start: Integer;
  Names: TStringList;
  Block: TStringList;

  procedure CutBlocks(ASource: TStrings; ANames: TStringList; ABlocks: TList);
  var
    K: Integer;
    B: TStringList;
  begin
    B := TStringList.Create;
    ANames.Add('ops');
    ABlocks.Add(B);
    for K := 0 to ASource.Count - 1 do
    begin
      if Copy(ASource[K], 1, 4) = 'ENV ' then
      begin
        B := TStringList.Create;
        ANames.Add(ASource[K]);
        ABlocks.Add(B);
      end;
      B.Add(ASource[K]);
    end;
  end;

var
  WantNames, MineNames: TStringList;
  WantBlocks, MineBlocks: TList;
  J, K: Integer;
  W, M: TStringList;
  Same: Boolean;
begin
  WriteLn('SDL の記録との突き合わせ（場面ごと）');
  Want := TStringList.Create;
  WantNames := TStringList.Create;
  MineNames := TStringList.Create;
  WantBlocks := TList.Create;
  MineBlocks := TList.Create;
  try
    for I := 0 to High(FilesystemExpected) do
      Want.Add(FilesystemExpected[I]);
    CutBlocks(Want, WantNames, WantBlocks);
    CutBlocks(Mine, MineNames, MineBlocks);
    Check(WantNames.Text = MineNames.Text, Format('場面の並びが SDL と同じ（%d 場面）', [WantNames.Count]));
    for I := 0 to WantNames.Count - 1 do
    begin
      K := MineNames.IndexOf(WantNames[I]);
      Same := K >= 0;
      if Same then
      begin
        W := TStringList(WantBlocks[I]);
        M := TStringList(MineBlocks[K]);
        if W.Text <> M.Text then
        begin
          Same := False;
          for J := 0 to W.Count - 1 do
            if (J >= M.Count) or (W[J] <> M[J]) then
            begin
              WriteLn('    SDL      : ', Copy(W[J], 1, 220));
              if J < M.Count then
                WriteLn('    papimela : ', Copy(M[J], 1, 220))
              else
                WriteLn('    papimela : (終わり)');
              Break;
            end;
          if (J >= W.Count) and (M.Count > W.Count) then
            WriteLn('    余分な行 papimela: ', M[W.Count]);
        end;
      end;
      Check(Same, '場面 ' + WantNames[I] + ' が SDL と同じ記録になる');
    end;
  finally
    for I := 0 to WantBlocks.Count - 1 do
      TObject(WantBlocks[I]).Free;
    for I := 0 to MineBlocks.Count - 1 do
      TObject(MineBlocks[I]).Free;
    WantBlocks.Free;
    MineBlocks.Free;
    WantNames.Free;
    MineNames.Free;
    Want.Free;
  end;
end;

{ ---- 実行ファイルと、papimela の足した検査 ---- }

function ReadSymLinkText(const APath: String): String;
var
  Buf: array[0..4095] of Char;
  R: TSsize;
begin
  R := fpReadLink(PChar(APath), @Buf[0], SizeOf(Buf));
  if R <= 0 then
    Result := ''
  else
    SetString(Result, PChar(@Buf[0]), R);
end;

procedure TestMore;
var
  Exe: String;
  A, B: Boolean;
  S: String;
begin
  WriteLn('papimela の足した検査');
  // 実行ファイルの場所と名前
  Exe := ReadSymLinkText('/proc/self/exe');
  Check((Exe <> '') and (TPMLFileSystem.BasePath = Copy(Exe, 1, LastDelimiter('/', Exe))), '基準のパスは実行ファイルのフォルダ（終わりに /）');
  Check(TPMLFileSystem.ExeName = Copy(Exe, LastDelimiter('/', Exe) + 1, MaxInt), '実行ファイルの名前');
  Check(TPMLFileSystem.ExeName = 'test_filesystem', '名前は test_filesystem');
  // ワイルドカード照合の単独
  Check(PMLWildcardMatch('*.txt', 'a.txt', A) and not A, '*.txt は a.txt に合う');
  Check(not PMLWildcardMatch('*.txt', 'a/b.txt', A), '* は / に合わない');
  Check(PMLWildcardMatch('a/*', 'a/b', A), 'a/* は a/b に合う');
  Check(not PMLWildcardMatch('a/b', 'a', A) and A, 'a/b は a に合わないが、a は降りるべきフォルダ');
  Check(not PMLWildcardMatch('a/b', 'a/', A) , 'a/b は a/ に合わない');
  Check(PMLWildcardMatch('', '', A), '空と空は合う');
  // 空で設定された XDG_DATA_HOME は設定していないのと同じ（D-83）
  SetEnv_('HOME', Base + '/home', True);
  SetEnv_('XDG_DATA_HOME', '', True);
  ForceDirectories(Base + '/home');
  S := TPMLFileSystem.PrefPath('O', 'A');
  Check(S = Base + '/home/.local/share/O/A/', '空の XDG_DATA_HOME は $HOME/.local/share を使う: ' + S);
  SetEnv_('XDG_DATA_HOME', '', False);
  // HOME も無ければ失敗
  SetEnv_('HOME', '', False);
  B := False;
  try
    TPMLFileSystem.PrefPath('O', 'A');
  except
    on EPMLIOError do B := True;
  end;
  Check(B, 'HOME も XDG_DATA_HOME も無ければ EPMLIOError');
  // 保存されたゲームとスクリーンショットは XDG に無い
  B := False;
  try
    TPMLFileSystem.UserFolder(TPMLUserFolder.SavedGames);
  except
    on EPMLUnsupported do B := True;
  end;
  Check(B, 'SavedGames は EPMLUnsupported');
end;

begin
  WriteLn('=== test_filesystem ===');
  TestCaseFold;
  TestCaseFoldMore;
  Mine := TStringList.Create;
  Base := NewWorkDir('ops');
  try
    Ops;
    RunEnvScenes;
    CompareRecord;
    SetEnv_('HOME', Base, True);
    TestMore;
  finally
    fpChdir('/');
    RemoveTree(Base);
    Mine.Free;
  end;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: ファイルシステムと畳み込みが SDL と同じ記録になる ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
