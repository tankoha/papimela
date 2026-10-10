{
  PaPiMeLa.Platform.DocumentPortal — xdg-desktop-portal の FileTransfer（ファイルの受け渡しの鍵）

  Origin : partially ported from SDL (src/core/linux/SDL_dbus.c)
           Scope: SDL_DBus_DocumentsPortalRetrieveFiles（鍵からパスの並びを受け取る呼び出し）。
           鍵を作る側（TPMLPortalFileTransfer。StartTransfer / AddFiles / StopTransfer）は
           SDL に無く、papimela が portal の仕様から書いた。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #71

  WHAT:
    ドラッグ＆ドロップやクリップボードで、application/vnd.portal.filetransfer の中身
    （鍵の文字列）とファイルのパスを行き来させる。
      - PMLPortalRetrieveFiles: 受け取った鍵を、このアプリから見えるパスにする
      - TPMLPortalFileTransfer: 渡したいファイルの鍵を作り、受け取られるまで持つ
    仕様: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.FileTransfer.html

  WHY:
    Flatpak などのサンドボックスでは、相手のファイルのパス（text/uri-list）がこちらから
    見えない。Documents ポータルを通すと、見えるパス（/run/user/.../doc/...）にしてくれる。
    サンドボックスの外のアプリどうしでは、元のパスがそのまま返る（2026-10-09 実測）。

  RESOLVED（2026-10-09 に手元の xdg-document-portal で実測）:
    - 受け取り（PMLPortalRetrieveFiles）は呼び出しごとに専用の接続を開く。例外は投げず、
      失敗は False（APaths は nil）。鍵の末尾の NUL・空白は捨てる
    - 鍵を作る側（TPMLPortalFileTransfer）は、開けないファイルを EPMLArgument、
      ポータル・バス・libdbus が無いのを EPMLUnsupported にする。ファイルの fd は
      AddFiles のあとすぐ閉じる
    - Destroy の StopTransfer の失敗は握り潰さず PMLPortalLastNonFatalError に残す
    - 鍵は作った接続が開いている間だけ有効。busctl のように呼び出しごとに接続が変わると
      AddFiles が AccessDenied になる。TPMLPortalFileTransfer は接続を持ち続ける
    - 受け取りは別の接続からでよい。ポータルの既定（autostop）では 1 回受け取ると鍵は無効になり、
      2 回目は AccessDenied（Invalid transfer）

  NOT RESOLVED:
    - 書き込みの許可（options の writable）は使っていない

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.DocumentPortal;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.DBus;

const
  // ポータル経由のファイルの受け渡しの MIME タイプ。中身は鍵の文字列（NUL で終わることがある）。
  PML_PORTAL_FILETRANSFER_MIME = 'application/vnd.portal.filetransfer';

{ 鍵 AKey のファイルのパスを受け取る（FileTransfer.RetrieveFiles）。
  1 つ以上受け取れたら True。鍵が無効・ポータルが無い・セッションバスに繋がらない・
  D-Bus のライブラリが無い、は False（例外は投げない）。AKey の末尾の NUL は無視する。 }
function PMLPortalRetrieveFiles(const AKey: String; out APaths: TStringArray): Boolean;

{ 例外にせず見送った失敗（StopTransfer など）の、最後の 1 件の説明。無ければ ''。 }
function PMLPortalLastNonFatalError: String;

type
  { 渡したいファイルの鍵を作って持つ（FileTransfer.StartTransfer と AddFiles）。

    WHAT:
      Create でセッションバスに自分の接続を開き、APaths のファイルを開いて
      ポータルに渡し、鍵を Key に置く。Destroy で StopTransfer を送り、接続を閉じる。
      AAutoStop = False（既定）なら、鍵は Destroy まで何度でも受け取れる。True なら
      最初の 1 回で無効になる（ポータルの既定の autostop）。

    WHY:
      ドラッグでは、落とし先だけでなく、ポインタが通りかかったアプリも中身を読む
      （2026-10-10 実測: demo_drag から demo_drop へ運ぶ途中で、別のアプリが
      text/uri-list・text/plain・ポータルの鍵を順に読み、鍵を使い切った。落とし先の
      demo_drop は無効な鍵を受け取り、text/uri-list へ戻った）。そのため既定は
      autostop を切り、ドラッグが終わったとき（DragEnd）に捨てて無効にする。

    使い方: ドラッグのデータの提供者が application/vnd.portal.filetransfer を求められたら
    Key を渡す。ドラッグが終わったら（DragEnd）捨てる。

    APaths が空・開けないファイルがある、は EPMLArgument。ポータルが無い・セッションバスに
    繋がらない・D-Bus のライブラリが無い、は EPMLUnsupported。 }
  TPMLPortalFileTransfer = class
  strict private
    FConn: TPMLDBusConnection;
    FKey : String;
  public
    constructor Create(const APaths: array of String; AAutoStop: Boolean = False);
    destructor Destroy; override;
    property Key: String read FKey;
  end;

implementation

uses
  BaseUnix;

const
  PORTAL_SERVICE = 'org.freedesktop.portal.Documents';
  PORTAL_PATH    = '/org/freedesktop/portal/documents';
  PORTAL_IFACE   = 'org.freedesktop.portal.FileTransfer';

var
  GLastNonFatalError: String = '';

function PMLPortalLastNonFatalError: String;
begin
  Result := GLastNonFatalError;
end;

{ 鍵の末尾の NUL・空白・改行を捨てる（パイプで受け取った鍵は NUL で終わることがある）。 }
function CleanKey(const AKey: String): String;
var
  N: Integer;
begin
  N := Length(AKey);
  while (N > 0) and (AKey[N] in [#0, #9, #10, #13, ' ']) do
    Dec(N);
  Result := Copy(AKey, 1, N);
end;

{ PORT-NOTE: SDL_DBus_DocumentsPortalRetrieveFiles。SDL は共有のセッション接続で呼び、
  戻りを NULL 終端の文字列の並びにする。こちらは呼び出しごとに専用の接続を開き
  （受け取りは作った接続でなくてよいことを実測済み）、TStringArray で返す。 }
function PMLPortalRetrieveFiles(const AKey: String; out APaths: TStringArray): Boolean;
var
  Conn: TPMLDBusConnection;
  Msg, Reply: PDBusMessage;
  W, Opts: TPMLDBusWriter;
  Rd, Sub: TPMLDBusReader;
  Key: String;
  Paths: TStringArray;
begin
  APaths := nil;
  Result := False;
  Key := CleanKey(AKey);
  if Key = '' then
    Exit;
  Paths := nil;
  try
    Conn := TPMLDBusConnection.Create;
    try
      Msg := Conn.BeginCall(PORTAL_SERVICE, PORTAL_PATH, PORTAL_IFACE, 'RetrieveFiles');
      try
        W := Conn.Writer(Msg);
        W.AddString(Key);
        Opts := W.OpenArray('{sv}');
        W.Close(Opts);
        Reply := Conn.Send(Msg);
        try
          Rd := Conn.Reader(Reply);
          Sub := Rd.Recurse;
          while not Sub.AtEnd do
          begin
            SetLength(Paths, Length(Paths) + 1);
            Paths[High(Paths)] := Sub.AsString;
            Sub.Next;
          end;
        finally
          Conn.Unref(Reply);
        end;
      finally
        Conn.Unref(Msg);
      end;
    finally
      Conn.Free;
    end;
    if Length(Paths) > 0 then
    begin
      APaths := Paths;
      Result := True;
    end;
  except
    on E: Exception do
    begin
      // 受け取れないのは普通のこと（鍵が古い・ポータルが無い）。呼び出し側は False で
      // text/uri-list に戻る。理由だけ残しておく。
      GLastNonFatalError := 'RetrieveFiles: ' + E.Message;
      APaths := nil;
      Result := False;
    end;
  end;
end;

{ TPMLPortalFileTransfer }

constructor TPMLPortalFileTransfer.Create(const APaths: array of String; AAutoStop: Boolean);
var
  FDs: array of LongInt;
  I: Integer;
  Msg, Reply: PDBusMessage;
  W, Arr, Opts, Entry, Value: TPMLDBusWriter;
begin
  inherited Create;
  FConn := nil;
  FKey := '';
  if Length(APaths) = 0 then
    raise EPMLArgument.Create('TPMLPortalFileTransfer needs at least one path');
  // 先にファイルを開く。1 つでも開けなければ、ポータルには触らない。
  SetLength(FDs, Length(APaths));
  for I := 0 to High(FDs) do
    FDs[I] := -1;
  try
    for I := 0 to High(APaths) do
    begin
      FDs[I] := FpOpen(APaths[I], O_RDONLY);
      if FDs[I] < 0 then
        raise EPMLArgument.CreateFmt('TPMLPortalFileTransfer: cannot open %s', [APaths[I]]);
    end;
    // 鍵は作った接続が開いている間だけ有効なので、接続は Destroy まで持つ。
    try
      FConn := TPMLDBusConnection.Create;
      Msg := FConn.BeginCall(PORTAL_SERVICE, PORTAL_PATH, PORTAL_IFACE, 'StartTransfer');
      try
        W := FConn.Writer(Msg);
        Opts := W.OpenArray('{sv}');
        // autostop は既定で true。切るときだけ送る。
        if not AAutoStop then
        begin
          Entry := Opts.OpenDictEntry;
          Entry.AddString('autostop');
          Value := Entry.OpenVariant('b');
          Value.AddBoolean(False);
          Entry.Close(Value);
          Opts.Close(Entry);
        end;
        W.Close(Opts);
        Reply := FConn.Send(Msg);
      finally
        FConn.Unref(Msg);
      end;
      try
        FKey := FConn.Reader(Reply).ExpectString;
      finally
        FConn.Unref(Reply);
      end;
      Msg := FConn.BeginCall(PORTAL_SERVICE, PORTAL_PATH, PORTAL_IFACE, 'AddFiles');
      try
        W := FConn.Writer(Msg);
        W.AddString(FKey);
        Arr := W.OpenArray('h');
        for I := 0 to High(FDs) do
          Arr.AddUnixFD(FDs[I]);
        W.Close(Arr);
        Opts := W.OpenArray('{sv}');
        W.Close(Opts);
        Reply := FConn.Send(Msg);
      finally
        FConn.Unref(Msg);
      end;
      FConn.Unref(Reply);
    except
      on E: Exception do
      begin
        FreeAndNil(FConn);
        FKey := '';
        raise EPMLUnsupported.Create('the document portal is not available: ' + E.Message);
      end;
    end;
  finally
    for I := 0 to High(FDs) do
      if FDs[I] >= 0 then
        FpClose(FDs[I]);
  end;
end;

destructor TPMLPortalFileTransfer.Destroy;
var
  Msg: PDBusMessage;
  W: TPMLDBusWriter;
begin
  if (FConn <> nil) and (FKey <> '') then
  begin
    try
      Msg := FConn.BeginCall(PORTAL_SERVICE, PORTAL_PATH, PORTAL_IFACE, 'StopTransfer');
      try
        W := FConn.Writer(Msg);
        W.AddString(FKey);
        FConn.Unref(FConn.Send(Msg));
      finally
        FConn.Unref(Msg);
      end;
    except
      on E: Exception do
        GLastNonFatalError := 'StopTransfer: ' + E.Message;
    end;
  end;
  FConn.Free;
  inherited Destroy;
end;

end.
