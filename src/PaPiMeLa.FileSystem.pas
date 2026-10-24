{
  PaPiMeLa.FileSystem — パスとファイルシステム

  Origin : ported from SDL (src/filesystem/SDL_filesystem.c, src/filesystem/unix/SDL_sysfilesystem.c,
           src/filesystem/posix/SDL_sysfsops.c)
           Scope: SDL_GetBasePath / GetExePath（/proc/self/exe）、SDL_GetPrefPath（XDG_DATA_HOME）、
           SDL_GetUserFolder（xdg-user-dirs の user-dirs.dirs の読み取り。xdg-user-dir-lookup.c を写したもの）、
           SDL_GetCurrentDirectory、SDL_EnumerateDirectory、SDL_CreateDirectory（親も作る）、SDL_RemovePath、
           SDL_RenamePath、SDL_CopyFile、SDL_GetPathInfo、SDL_GlobDirectory（ワイルドカードの照合、
           大文字小文字を見ない比べ）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.7、§11 #65

  WHAT:
    静的クラス TPMLFileSystem。失敗は例外（EPMLIOError。errno つき）にする。見つからないことが普通の問い合わせ
    （BasePath・ExeName・GetPathInfo）だけ、空文字列か False を返す。

  RESOLVED:
    - SDL はベースのパス・ユーザーのフォルダ・実行ファイルの名前を覚えて const char * で返す。ここでは String で返す
      ので覚えない（環境変数を変えると次の呼び出しから変わる）
    - XDG_DATA_HOME が空の文字列で設定されているとき、SDL は文字列の前の 1 バイトを読む（未定義）。ここでは
      XDG の約束どおり、設定していないのと同じに扱う（PORT-NOTE(bug): 上流の不具合 D-83）
    - ファイルの時刻はナノ秒（SDL_Time）。作成の時刻は、Linux には無いので ctime（状態の変更）を使う（SDL と同じ）
    - Glob のパターンは String なので「無い」は別の関数にした（パターン無しで全部）。空のパターンは何にも合わない

  NOT RESOLVED:
    - Android・iOS の相対パスの解釈、Ubuntu Touch のアプリ ID、assets:// は移植しない（Linux だけ）
    - SDL_GLOB_GITIGNORE は SDL にも無い

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2007 Red Hat, Inc.（xdg-user-dir-lookup.c の写し。MIT）
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.FileSystem;

{$I papimela.inc}

interface

uses
  SysUtils, Classes, BaseUnix, Unix,
  PaPiMeLa.Errors,
  PaPiMeLa.IO,
  PaPiMeLa.Unicode.CaseFold;

type
  // ユーザーのフォルダ（SDL_Folder）。SavedGames と Screenshots は XDG に無い
  TPMLUserFolder = (Home, Desktop, Documents, Downloads, Music, Pictures, PublicShare, SavedGames,
    Screenshots, Templates, Videos);

  // パスの種類（SDL_PathType）
  TPMLPathType = (None, RegularFile, Directory, Other);

  // パスの情報（SDL_PathInfo）。時刻は 1970 年からのナノ秒
  TPMLPathInfo = record
    PathType  : TPMLPathType;
    Size      : UInt64;
    CreateTime: Int64;
    ModifyTime: Int64;
    AccessTime: Int64;
  end;

  // 列挙の途中の答え（SDL_EnumerationResult）。Continue で続け、Success で成功のまま止め、Failure で失敗として止める
  TPMLEnumerationResult = (Continue, Success, Failure);

  { 列挙の通知（SDL_EnumerateDirectoryCallback）。ADirName は列挙している場所（終わりに / が 1 つ）、
    AName はその中の名前（. と .. は来ない）。 }
  TPMLEnumerateCallback = function(const ADirName, AName: String): TPMLEnumerationResult of object;

  TPMLGlobFlag = (CaseInsensitive);
  TPMLGlobFlags = set of TPMLGlobFlag;

  TPMLFileSystem = class sealed
  public
    { 実行ファイルのあるフォルダ（終わりに /）。分からなければ ''（SDL_GetBasePath）。 }
    class function BasePath: String; static;
    // 実行ファイルの名前。分からなければ ''（SDL_GetExeName）。
    class function ExeName: String; static;
    { アプリが設定を置くフォルダ（SDL_GetPrefPath）。$XDG_DATA_HOME か $HOME/.local/share の下の
      AOrg/AApp/ を作って返す（終わりに /。AOrg は空でもよい）。作れなければ EPMLIOError。 }
    class function PrefPath(const AOrg, AApp: String): String; static;
    { ユーザーのフォルダ（終わりに /。SDL_GetUserFolder）。無ければ EPMLIOError、XDG に無い種類は EPMLUnsupported。 }
    class function UserFolder(AFolder: TPMLUserFolder): String; static;
    // 今のフォルダ（終わりに /）。
    class function CurrentDirectory: String; static;

    { フォルダの中を列挙する（SDL_EnumerateDirectory）。開けなければ EPMLIOError。ACallback が Failure を
      返したら False、Success で止めたか最後まで来たら True。順番は決まっていない。 }
    class function EnumerateDirectory(const APath: String; ACallback: TPMLEnumerateCallback): Boolean; static;
    // フォルダを作る（親も作る。もうあれば成功）。作れなければ EPMLIOError。
    class procedure CreateDirectory(const APath: String); static;
    // 消す（ファイルか空のフォルダ。無ければ成功）。消せなければ EPMLIOError。
    class procedure RemovePath(const APath: String); static;
    class procedure RenamePath(const AOldPath, ANewPath: String); static;
    // ファイルを写す（行き先は上書き）。失敗したら EPMLIOError（途中までの行き先は残る）。
    class procedure CopyFile(const AOldPath, ANewPath: String); static;
    // パスの情報（SDL_GetPathInfo）。無い・調べられなければ False。シンボリックリンクは先へ進む
    class function GetPathInfo(const APath: String; out AInfo: TPMLPathInfo): Boolean; static;
    { フォルダの下を探す（SDL_GlobDirectory）。パターンは * と ? だけで、/ には合わない。結果は APath からの相対で、
      順番は決まっていない。AFlags に CaseInsensitive があれば大文字小文字を見ない（Unicode の畳み込み）。 }
    class function Glob(const APath, APattern: String; AFlags: TPMLGlobFlags = []): TStringArray; static;
    // パターン無し: 下にあるもの全部。
    class function GlobAll(const APath: String): TStringArray; static;
  end;

// ワイルドカードの照合（SDL の WildcardMatch。* と ? だけ。/ には合わない）。AMatchedToDir は、
// 途中の / まで合ったので、そのフォルダの中へ降りるとよいか。
function PMLWildcardMatch(const APattern, AText: String; out AMatchedToDir: Boolean): Boolean;

implementation

function Errno: Integer;
begin
  Result := fpGetErrno;
end;

procedure RaiseIO(const AMessage: String; AErrno: Integer; const AOperation: String);
begin
  raise EPMLIOError.CreateNative(AMessage + ': ' + SysErrorMessage(AErrno), AErrno, AOperation);
end;

{ ---- 実行ファイル ---- }

function ReadSymLink(const APath: String): String;
var
  Buf: array of Char;
  Len: Integer;
  R: TSsize;
begin
  Result := '';
  Len := 64;
  while True do
  begin
    SetLength(Buf, Len);
    R := fpReadLink(PChar(APath), @Buf[0], Len);
    if R < 0 then
      Exit('');                // リンクでない・読めない
    if R < Len then
    begin
      SetString(Result, PChar(@Buf[0]), R);
      Exit;
    end;
    Len := Len * 2;
  end;
end;

function GetExePath: String;
begin
  Result := '';
  if fpAccess('/proc', F_OK) = 0 then
  begin
    Result := ReadSymLink('/proc/self/exe');
    if Result = '' then
      Result := ReadSymLink(Format('/proc/%d/exe', [fpGetPID]));
  end;
end;

class function TPMLFileSystem.BasePath: String;
var
  Path: String;
  P: Integer;
begin
  Path := GetExePath;
  if Path = '' then
    Exit('');
  P := LastDelimiter('/', Path);
  Result := Copy(Path, 1, P);     // 名前を落として / を残す
end;

class function TPMLFileSystem.ExeName: String;
var
  Path: String;
  P: Integer;
begin
  Path := GetExePath;
  if Path = '' then
    Exit('');
  P := LastDelimiter('/', Path);
  Result := Copy(Path, P + 1, MaxInt);
end;

{ ---- 環境変数 ---- }

// libc の getenv。FPC の fpGetEnv は起動時の環境の写しを見るので、setenv で変えたあとの値が見えない
function c_getenv(AName: PChar): PChar; cdecl; external 'c' name 'getenv';

// 設定されているか（空でも設定されていれば True）
function EnvIsSet(const AName: String; out AValue: String): Boolean;
var
  P: PChar;
begin
  P := c_getenv(PChar(AName));
  Result := P <> nil;
  if Result then
    AValue := P
  else
    AValue := '';
end;

{ ---- 設定のフォルダ ---- }

class function TPMLFileSystem.PrefPath(const AOrg, AApp: String): String;
var
  Env, Prepend, Path: String;
  I: Integer;
  HaveEnv: Boolean;
  Mode: TMode;
begin
  Mode := &700;
  HaveEnv := EnvIsSet('XDG_DATA_HOME', Env) and (Env <> '');     // 空は設定していないのと同じ（D-83）
  if not HaveEnv then
  begin
    // $HOME/.local/share/Game Name 2
    if not EnvIsSet('HOME', Env) then
      raise EPMLIOError.Create('neither XDG_DATA_HOME nor HOME environment is set');
    Prepend := '/.local/share/';
  end
  else
    Prepend := '/';
  if (Env <> '') and (Env[Length(Env)] = '/') then
    Delete(Prepend, 1, 1);
  if AOrg <> '' then
    Path := Env + Prepend + AOrg + '/' + AApp + '/'
  else
    Path := Env + Prepend + AApp + '/';

  // 途中のフォルダを作っていく（先頭の / は飛ばす）
  for I := 2 to Length(Path) do
    if Path[I] = '/' then
      if (fpMkdir(Copy(Path, 1, I - 1), Mode) <> 0) and (Errno <> ESysEEXIST) then
        raise EPMLIOError.CreateNative(Format('Couldn''t create directory ''%s'': ''%s''',
          [Copy(Path, 1, I - 1), SysErrorMessage(Errno)]), Errno, 'mkdir');
  Result := Path;
end;

{ ---- ユーザーのフォルダ ---- }

// xdg-user-dir-lookup.c の xdg_user_dir_lookup_with_fallback（フォールバックは無し）。無ければ ''。
function XdgUserDirLookup(const AType: String; out AFound: Boolean): String;
var
  Home, ConfigHome, ConfigFile, Content, Line, UserDir: String;
  Chunks: array of String;
  I, N, Start, P: Integer;
  Relative: Boolean;
  F: TFileStream;
begin
  Result := '';
  AFound := False;
  if not EnvIsSet('HOME', Home) then
    Exit;
  if EnvIsSet('XDG_CONFIG_HOME', ConfigHome) and (ConfigHome <> '') then
    ConfigFile := ConfigHome + '/user-dirs.dirs'
  else
    ConfigFile := Home + '/.config/user-dirs.dirs';
  try
    F := TFileStream.Create(ConfigFile, fmOpenRead or fmShareDenyNone);
  except
    on EFOpenError do
      Exit;
  end;
  try
    SetLength(Content, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Content[1], F.Size);
  finally
    F.Free;
  end;

  // fgets(buffer, 512) と同じに、改行までか 511 文字ごとに区切る
  N := 0;
  Start := 1;
  while Start <= Length(Content) do
  begin
    I := Start;
    while (I <= Length(Content)) and (I - Start < 511) do
    begin
      Inc(I);
      if Content[I - 1] = #10 then
        Break;
    end;
    SetLength(Chunks, N + 1);
    Chunks[N] := Copy(Content, Start, I - Start);
    Inc(N);
    Start := I;
  end;

  UserDir := '';
  for I := 0 to N - 1 do
  begin
    Line := Chunks[I];
    if (Line <> '') and (Line[Length(Line)] = #10) then
      Delete(Line, Length(Line), 1);
    P := 1;
    while (P <= Length(Line)) and (Line[P] in [' ', #9]) do
      Inc(P);
    if Copy(Line, P, 4) <> 'XDG_' then
      Continue;
    Inc(P, 4);
    if Copy(Line, P, Length(AType)) <> AType then
      Continue;
    Inc(P, Length(AType));
    if Copy(Line, P, 4) <> '_DIR' then
      Continue;
    Inc(P, 4);
    while (P <= Length(Line)) and (Line[P] in [' ', #9]) do
      Inc(P);
    if (P > Length(Line)) or (Line[P] <> '=') then
      Continue;
    Inc(P);
    while (P <= Length(Line)) and (Line[P] in [' ', #9]) do
      Inc(P);
    if (P > Length(Line)) or (Line[P] <> '"') then
      Continue;
    Inc(P);
    Relative := False;
    if Copy(Line, P, 6) = '$HOME/' then
    begin
      Inc(P, 6);
      Relative := True;
    end
    else if (P > Length(Line)) or (Line[P] <> '/') then
      Continue;
    if Relative then
      UserDir := Home + '/'
    else
      UserDir := '';
    while (P <= Length(Line)) and (Line[P] <> '"') do
    begin
      if (Line[P] = '\') and (P < Length(Line)) then
        Inc(P);
      UserDir := UserDir + Line[P];
      Inc(P);
    end;
    AFound := True;
    Result := UserDir;
  end;
end;

function XdgUserDir(const AType: String; out AFound: Boolean): String;
var
  Home: String;
begin
  Result := XdgUserDirLookup(AType, AFound);
  if AFound then
    Exit;
  if not EnvIsSet('HOME', Home) then
    Exit('');
  // 昔からの互換: デスクトップだけは $HOME/Desktop
  if AType = 'DESKTOP' then
  begin
    AFound := True;
    Exit(Home + '/Desktop');
  end;
  Result := '';
end;

class function TPMLFileSystem.UserFolder(AFolder: TPMLUserFolder): String;
var
  Param, Home: String;
  Found: Boolean;
begin
  case AFolder of
    TPMLUserFolder.Home:
    begin
      if not EnvIsSet('HOME', Home) then
        raise EPMLIOError.Create('No $HOME environment variable available');
      Exit(Home + '/');
    end;
    TPMLUserFolder.Desktop: Param := 'DESKTOP';
    TPMLUserFolder.Documents: Param := 'DOCUMENTS';
    TPMLUserFolder.Downloads: Param := 'DOWNLOAD';
    TPMLUserFolder.Music: Param := 'MUSIC';
    TPMLUserFolder.Pictures: Param := 'PICTURES';
    TPMLUserFolder.PublicShare: Param := 'PUBLICSHARE';
    TPMLUserFolder.SavedGames: raise EPMLUnsupported.Create('Saved Games folder unavailable on XDG');
    TPMLUserFolder.Screenshots: raise EPMLUnsupported.Create('Screenshots folder unavailable on XDG');
    TPMLUserFolder.Templates: Param := 'TEMPLATES';
    TPMLUserFolder.Videos: Param := 'VIDEOS';
  end;
  Result := XdgUserDir(Param, Found);
  if not Found then
    raise EPMLIOError.Create('XDG directory not available');
  Result := Result + '/';
end;

class function TPMLFileSystem.CurrentDirectory: String;
var
  Buf: array of Char;
  Len: Integer;
begin
  Len := 64;
  while True do
  begin
    SetLength(Buf, Len);
    if fpGetCwd(@Buf[0], Len - 1) <> nil then
      Break;
    if Errno = ESysERANGE then
    begin
      Len := Len * 2;
      Continue;
    end;
    RaiseIO('getcwd failed', Errno, 'getcwd');
  end;
  Result := PChar(@Buf[0]);
  // 終わりに / が要る
  if (Result = '') or (Result[Length(Result)] <> '/') then
    Result := Result + '/';
end;

{ ---- フォルダの操作 ---- }

class function TPMLFileSystem.EnumerateDirectory(const APath: String; ACallback: TPMLEnumerateCallback): Boolean;
var
  PathWithSep, Name: String;
  D: PDir;
  E: PDirent;
  R: TPMLEnumerationResult;
  L: Integer;
begin
  if APath <> '' then
    PathWithSep := APath + '/'
  else
    PathWithSep := APath;
  // 終わりの / を 1 つにする（呼び出し側が足していても）
  L := Length(PathWithSep);
  while (L > 1) and (PathWithSep[L] = '/') and (PathWithSep[L - 1] = '/') do
  begin
    Delete(PathWithSep, L, 1);
    Dec(L);
  end;
  D := fpOpenDir(PathWithSep);
  if D = nil then
    RaiseIO('Can''t open directory', Errno, 'opendir');
  R := TPMLEnumerationResult.Continue;
  try
    E := fpReadDir(D^);
    while (R = TPMLEnumerationResult.Continue) and (E <> nil) do
    begin
      Name := PChar(@E^.d_name[0]);
      if (Name <> '.') and (Name <> '..') then
        R := ACallback(PathWithSep, Name);
      if R = TPMLEnumerationResult.Continue then
        E := fpReadDir(D^);
    end;
  finally
    fpCloseDir(D^);
  end;
  Result := R <> TPMLEnumerationResult.Failure;
end;

// 1 段だけ作る。もうフォルダがあれば成功（SDL_SYS_CreateDirectory）。失敗は errno を返す。0 が成功
function SysCreateDirectory(const APath: String): Integer;
var
  St: Stat;
begin
  if fpMkdir(APath, &770) = 0 then
    Exit(0);
  Result := Errno;
  if Result = ESysEEXIST then
    if (fpStat(APath, St) = 0) and fpS_ISDIR(St.st_mode) then
      Result := 0;
end;

class procedure TPMLFileSystem.CreateDirectory(const APath: String);
var
  Err, I: Integer;
  Parents: String;
  Ch: Char;
begin
  Err := SysCreateDirectory(APath);
  if (Err <> 0) and (APath <> '') then
  begin
    // 親が無いのかもしれない
    Parents := APath;
    // 終わりの / が邪魔かもしれないので落とす
    if Parents[Length(Parents)] = '/' then
    begin
      Delete(Parents, Length(Parents), 1);
      Err := SysCreateDirectory(Parents);
    end;
    if Err <> 0 then
    begin
      for I := 1 to Length(Parents) do
      begin
        Ch := Parents[I];
        if (Ch = '/') and (I = 1) then
          Continue;                // ルートだけ
        if Ch = '/' then
        begin
          // (すでにフォルダとして有れば失敗しない)
          Err := SysCreateDirectory(Copy(Parents, 1, I - 1));
          if Err <> 0 then
            Break;               // 親を作れないなら、あきらめる
        end;
      end;
      // 最後の機会
      Err := SysCreateDirectory(Parents);
    end;
  end;
  if Err <> 0 then
    RaiseIO('Can''t create directory', Err, 'mkdir');
end;

class procedure TPMLFileSystem.RemovePath(const APath: String);
var
  R, Err: Integer;
begin
  // C の remove(): ファイルは unlink、フォルダは rmdir
  R := fpUnlink(APath);
  if R < 0 then
  begin
    Err := Errno;
    if Err = ESysEISDIR then
    begin
      R := fpRmDir(APath);
      Err := Errno;
    end;
  end
  else
    Err := 0;
  if R < 0 then
  begin
    if Err = ESysENOENT then
      Exit;               // もう無い。成功
    RaiseIO('Can''t remove path', Err, 'remove');
  end;
end;

class procedure TPMLFileSystem.RenamePath(const AOldPath, ANewPath: String);
begin
  if fpRename(AOldPath, ANewPath) < 0 then
    RaiseIO('Can''t rename path', Errno, 'rename');
end;

class procedure TPMLFileSystem.CopyFile(const AOldPath, ANewPath: String);
var
  Input, Output: TPMLFileStream;
  Buffer: array[0..4095] of Byte;
  N: Integer;
begin
  Input := TPMLFileStream.Create(AOldPath, TPMLFileMode.Read);
  try
    Output := TPMLFileStream.Create(ANewPath, TPMLFileMode.Write);
    try
      N := Input.Read(Buffer, SizeOf(Buffer));
      while N > 0 do
      begin
        Output.WriteBuffer(Buffer, N);
        N := Input.Read(Buffer, SizeOf(Buffer));
      end;
    finally
      Output.Free;
    end;
  finally
    Input.Free;
  end;
end;

class function TPMLFileSystem.GetPathInfo(const APath: String; out AInfo: TPMLPathInfo): Boolean;
var
  St: Stat;
begin
  AInfo := Default(TPMLPathInfo);
  if fpStat(APath, St) < 0 then
    Exit(False);
  if fpS_ISREG(St.st_mode) then
  begin
    AInfo.PathType := TPMLPathType.RegularFile;
    AInfo.Size := UInt64(St.st_size);
  end
  else if fpS_ISDIR(St.st_mode) then
  begin
    AInfo.PathType := TPMLPathType.Directory;
    AInfo.Size := 0;
  end
  else
  begin
    AInfo.PathType := TPMLPathType.Other;
    AInfo.Size := UInt64(St.st_size);
  end;
  // 作成の時刻は Linux に無いので、状態の変更の時刻（ctime）
  AInfo.CreateTime := Int64(St.st_ctime) * 1000000000 + St.st_ctime_nsec;
  AInfo.ModifyTime := Int64(St.st_mtime) * 1000000000 + St.st_mtime_nsec;
  AInfo.AccessTime := Int64(St.st_atime) * 1000000000 + St.st_atime_nsec;
  Result := True;
end;

{ ---- Glob ---- }

function CharAt(const AText: String; AIndex: Integer): Char; inline;
begin
  if (AIndex >= 1) and (AIndex <= Length(AText)) then
    Result := AText[AIndex]
  else
    Result := #0;
end;

function PMLWildcardMatch(const APattern, AText: String; out AMatchedToDir: Boolean): Boolean;
var
  SIdx, PIdx, SBack, PBack: Integer;
  SCh, PCh, SChBack: Char;
  HaveBack: Boolean;
begin
  SIdx := 1;
  PIdx := 1;
  SBack := 0;
  PBack := 0;
  SChBack := #0;
  HaveBack := False;
  SCh := CharAt(AText, SIdx);
  PCh := CharAt(APattern, PIdx);
  while SCh <> #0 do
  begin
    if PCh = '*' then
    begin
      SBack := SIdx;
      Inc(PIdx);
      PBack := PIdx;
      HaveBack := True;
      SChBack := SCh;
      PCh := CharAt(APattern, PIdx);
    end
    else if PCh = SCh then
    begin
      if PCh = '/' then
        HaveBack := False;
      Inc(SIdx);
      Inc(PIdx);
      SCh := CharAt(AText, SIdx);
      PCh := CharAt(APattern, PIdx);
    end
    else if (PCh = '?') and (SCh <> '/') then
    begin
      Inc(SIdx);
      Inc(PIdx);
      SCh := CharAt(AText, SIdx);
      PCh := CharAt(APattern, PIdx);
    end
    else if (not HaveBack) or (SChBack = '/') then
    begin
      // 合わなかった。* の中で / の上でなければ続けられるが、そうでなければ失敗
      AMatchedToDir := False;
      Exit(False);
    end
    else
    begin
      // * の中。合わせる文字列を 1 つ進めて、もう一度
      Inc(SBack);
      SIdx := SBack;
      PIdx := PBack;
      SChBack := SCh;
      SCh := CharAt(AText, SIdx);
      PCh := CharAt(APattern, PIdx);
    end;
  end;
  // 終わりの * は何にも合わなくてよい
  while PCh = '*' do
  begin
    Inc(PIdx);
    PCh := CharAt(APattern, PIdx);
  end;
  // 文字列が終わって、パターンが / で止まったなら、そのフォルダへ降りるべき
  AMatchedToDir := PCh = '/';
  Result := PCh = #0;
end;

type
  TGlobState = class
  public
    Pattern   : String;
    HavePattern: Boolean;
    Flags     : TPMLGlobFlags;
    BaseDirLen: Integer;
    Entries   : TStringList;
    function OnEntry(const ADirName, AName: String): TPMLEnumerationResult;
  end;

function TGlobState.OnEntry(const ADirName, AName: String): TPMLEnumerationResult;
var
  FullPath, Subject, SubPath: String;
  Matched, MatchedToDir: Boolean;
  Info: TPMLPathInfo;
begin
  FullPath := ADirName + AName;
  if HavePattern then
  begin
    if TPMLGlobFlag.CaseInsensitive in Flags then
      Subject := PMLCaseFoldUTF8(FullPath)
    else
      Subject := FullPath;
    // 基準のフォルダの分は飛ばして照合する
    Matched := PMLWildcardMatch(Pattern, Copy(Subject, BaseDirLen + 1, MaxInt), MatchedToDir);
  end
  else
  begin
    Matched := True;
    MatchedToDir := True;
  end;
  if Matched then
  begin
    SubPath := Copy(FullPath, BaseDirLen + 1, MaxInt);
    Entries.Add(SubPath);
  end;
  Result := TPMLEnumerationResult.Continue;
  if MatchedToDir then
    if TPMLFileSystem.GetPathInfo(FullPath, Info) and (Info.PathType = TPMLPathType.Directory) then
      if not TPMLFileSystem.EnumerateDirectory(FullPath, @Self.OnEntry) then
        Result := TPMLEnumerationResult.Failure;
end;

function GlobImpl(const APath: String; HavePattern: Boolean; const APattern: String;
  AFlags: TPMLGlobFlags): TStringArray;
var
  Path: String;
  State: TGlobState;
  I: Integer;
begin
  Path := APath;
  // 終わりの / を落とす（パターンの照合を乱さないため）
  while (Length(Path) > 1) and (Path[Length(Path)] in ['/', '\']) do
    Delete(Path, Length(Path), 1);
  if not HavePattern then
    AFlags := AFlags - [TPMLGlobFlag.CaseInsensitive];

  State := TGlobState.Create;
  try
    State.HavePattern := HavePattern;
    State.Flags := AFlags;
    if HavePattern then
    begin
      if TPMLGlobFlag.CaseInsensitive in AFlags then
        State.Pattern := PMLCaseFoldUTF8(APattern)
      else
        State.Pattern := APattern;
    end;
    State.BaseDirLen := 0;
    if Path <> '' then
    begin
      if (Path = '/') or (Path = '\') then
        State.BaseDirLen := 1
      else
        State.BaseDirLen := Length(Path) + 1;      // 足す / の分
    end;
    State.Entries := TStringList.Create;
    try
      TPMLFileSystem.EnumerateDirectory(Path, @State.OnEntry);
      SetLength(Result, State.Entries.Count);
      for I := 0 to State.Entries.Count - 1 do
        Result[I] := State.Entries[I];
    finally
      State.Entries.Free;
    end;
  finally
    State.Free;
  end;
end;

class function TPMLFileSystem.Glob(const APath, APattern: String; AFlags: TPMLGlobFlags): TStringArray;
begin
  Result := GlobImpl(APath, True, APattern, AFlags);
end;

class function TPMLFileSystem.GlobAll(const APath: String): TStringArray;
begin
  Result := GlobImpl(APath, False, '', []);
end;

end.
