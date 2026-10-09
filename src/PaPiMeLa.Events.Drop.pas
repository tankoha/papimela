{
  PaPiMeLa.Events.Drop — ドラッグ＆ドロップのイベントの並べ方と、URI からローカルのパスへの変換

  Origin : ported from SDL (src/events/SDL_dropevents.c, src/SDL_utils.c)
           Scope: SDL_SendDrop（DropBegin を落とし始めに 1 回、最後の位置、DropComplete で戻す）、
           SDL_URIToLocal と SDL_URIDecode。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #38

  WHAT:
    公開の TPMLDropState（PaPiMeLa.Events。バックエンドが呼ぶ窓口）の中身と、
    text/uri-list の 1 行・全体をローカルのパスにする関数。

  WHY:
    PaPiMeLa.Events はクリーンルームのユニット。ここは SDL のソースを読んで写した部分
    なので、由来を分けるためにユニットを分けた。TPMLDropState は PaPiMeLa.Events の
    implementation から TPMLDropImpl を作って持ち、Send* をここへ渡す。

  RESOLVED:
    - 最後の位置はウィンドウごとに持つ（SDL は関数内の static で 1 つだけ）
    - SDL から意図して変えた箇所は各関数の PORT-NOTE に書いた（スキームの無い文字列、
      注釈の行、不完全な escape、ホストの後ろの "/"）

  NOT RESOLVED:
    - Windows のドライブ文字（file:///C:/...）の扱い。Linux だけなので不要

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Events.Drop;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Events;

type
  { 落とし中のウィンドウ 1 つ分。最後に受けた DropPosition の位置を持つ。 }
  TPMLDropWindow = record
    WindowID: TPMLWindowID;
    X, Y    : Single;
  end;

  { TPMLDropState の中身。

    WHAT:
      落とし中のウィンドウだけを並べる。一覧に載っていること自体が「落とし中」。

    WHY:
      SDL は window->is_dropping と、関数内の static な最後の位置を使う。papimela は
      ウィンドウの構造体に状態を足せない（バックエンドが持つ）ので、状態機械の側に持つ。
      落とし終わったウィンドウは一覧から外すので、ウィンドウの ID が増えても一覧は
      落とし中の数より大きくならない。 }
  TPMLDropImpl = class
  public
    Windows: array of TPMLDropWindow;
    function  IndexOf(AWindowID: TPMLWindowID): Integer;
    function  Add(AWindowID: TPMLWindowID): Integer;
    procedure RemoveAt(AIndex: Integer);
  end;

{ SDL_SendDrop。TPMLDropState の 4 つの Send* の共通部分。 }
procedure PMLSendDrop(AQueue: TPMLEventQueue; AImpl: TPMLDropImpl; AKind: TPMLEventKind;
  AWindowID: TPMLWindowID; const AText: String; AX, AY: Single);

{ URI（text/uri-list の 1 行）をローカルのファイルのパスにする（SDL_URIToLocal）。
  file:///a、file:/a、file://localhost/a、file://<このマシンのホスト名>/a を /a にし、
  %xx を元のバイトに戻す（%xx が 16 進でなければそのまま残す）。他のスキーム、他のホスト、
  スキームの無い文字列は False。ホスト名は大文字小文字を区別しない。 }
function PMLURIToLocalPath(const AURI: String; out APath: String): Boolean;
{ text/uri-list の中身をローカルのパスの並びにする。行は CR / LF で分け、空の行と
  '#' で始まる注釈の行（RFC 2483）は飛ばし、ローカルでない URI は捨てる。 }
function PMLURIListToLocalPaths(const AList: String): TStringArray;

implementation

uses
  Unix;

function TPMLDropImpl.IndexOf(AWindowID: TPMLWindowID): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Windows) do
    if Windows[I].WindowID = AWindowID then
      Exit(I);
  Result := -1;
end;

function TPMLDropImpl.Add(AWindowID: TPMLWindowID): Integer;
begin
  Result := Length(Windows);
  SetLength(Windows, Result + 1);
  Windows[Result].WindowID := AWindowID;
  Windows[Result].X := 0;
  Windows[Result].Y := 0;
end;

procedure TPMLDropImpl.RemoveAt(AIndex: Integer);
var
  I: Integer;
begin
  for I := AIndex to High(Windows) - 1 do
    Windows[I] := Windows[I + 1];
  SetLength(Windows, Length(Windows) - 1);
end;

procedure PushDropEvent(AQueue: TPMLEventQueue; AKind: TPMLEventKind;
  AWindowID: TPMLWindowID; const AText: String; AX, AY: Single);
var
  Ev: TPMLEvent;
begin
  Ev := Default(TPMLEvent);
  Ev.Kind := AKind;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := AWindowID;
  Ev.Text := AText;
  Ev.Drop.X := AX;
  Ev.Drop.Y := AY;
  AQueue.Push(Ev);
end;

{ SDL_SendDrop。 }
procedure PMLSendDrop(AQueue: TPMLEventQueue; AImpl: TPMLDropImpl; AKind: TPMLEventKind;
  AWindowID: TPMLWindowID; const AText: String; AX, AY: Single);
var
  I: Integer;
begin
  // 種類が無効なら DropBegin も積まない（SDL は SDL_EventEnabled を最初に見る）。
  if not AQueue.GetEnabled(AKind) then
    Exit;

  I := AImpl.IndexOf(AWindowID);
  if I < 0 then
  begin
    // 落とし始め。この 1 回だけ DropBegin を積む。位置は 0。
    PushDropEvent(AQueue, TPMLEventKind.DropBegin, AWindowID, '', 0, 0);
    I := AImpl.Add(AWindowID);
  end;

  if AKind = TPMLEventKind.DropPosition then
  begin
    AImpl.Windows[I].X := AX;
    AImpl.Windows[I].Y := AY;
  end;
  PushDropEvent(AQueue, AKind, AWindowID, AText, AImpl.Windows[I].X, AImpl.Windows[I].Y);

  // 落とし終わり。落とし中と位置を戻す。
  if AKind = TPMLEventKind.DropComplete then
    AImpl.RemoveAt(I);
end;

{ 16 進の 1 桁。 }
function HexDigitValue(AChar: Char; out AValue: Integer): Boolean;
begin
  Result := True;
  case AChar of
    '0'..'9': AValue := Ord(AChar) - Ord('0');
    'a'..'f': AValue := Ord(AChar) - Ord('a') + 10;
    'A'..'F': AValue := Ord(AChar) - Ord('A') + 10;
  else
    Result := False;
    AValue := 0;
  end;
end;

{ ASCII だけ大文字小文字を区別しない比較（SDL_strncasecmp）。 }
function SameAsciiText(const A, B: String): Boolean;
var
  I: Integer;
  CA, CB: Char;
begin
  Result := Length(A) = Length(B);
  if not Result then
    Exit;
  for I := 1 to Length(A) do
  begin
    CA := A[I];
    CB := B[I];
    if (CA >= 'A') and (CA <= 'Z') then
      CA := Chr(Ord(CA) + 32);
    if (CB >= 'A') and (CB <= 'Z') then
      CB := Chr(Ord(CB) + 32);
    if CA <> CB then
      Exit(False);
  end;
end;

{ %xx を元のバイトに戻す（SDL_URIDecode）。

  WHAT:
    16 進でない %xx はそのまま残す。'%' の直後の文字が '%' のときも、その '%' は
    新しい始まりとして扱わず、そのまま書く（SDL と同じ）。

  PORT-NOTE: 末尾で終わる不完全な escape（"%" や "%4"）を、SDL は黙って捨てるように
  読める（ループを抜けるとき di が 0 でなければ書き出す処理が無い。未確認）。
  papimela はそのまま残す。
  PORT-NOTE: %00 は SDL が C の文字列に書くので、そこで文字列が終わる。同じ振る舞いに
  するため、最初の NUL で打ち切る。 }
function URIDecode(const ASource: String): String;
var
  RI, Di, Decode, V: Integer;
  C: Char;
  P: Integer;
begin
  Result := '';
  Di := 0;
  Decode := 0;
  for RI := 1 to Length(ASource) do
  begin
    C := ASource[RI];
    if Di = 0 then
    begin
      if C = '%' then
      begin
        Decode := 0;
        Di := 1;
      end
      else
        Result := Result + C;
    end
    else if HexDigitValue(C, V) then
    begin
      // Di = 1 が上位の桁、Di = 2 が下位の桁。
      Decode := Decode or (V shl ((2 - Di) * 4));
      if Di = 2 then
      begin
        Result := Result + Chr(Decode);
        Di := 0;
      end
      else
        Inc(Di);
    end
    else
    begin
      // 16 進でない。'%'、読み済みの 16 進（あれば）、いまの文字をそのまま書く。
      Result := Result + Copy(ASource, RI - Di, Di + 1);
      Di := 0;
    end;
  end;
  if Di > 0 then
    Result := Result + Copy(ASource, Length(ASource) - Di + 1, Di);
  P := Pos(#0, Result);
  if P > 0 then
    SetLength(Result, P - 1);
end;

{ SDL_URIToLocal。

  PORT-NOTE: SDL は "file:/" で始まらず ":/" も含まない文字列を、相対のパスとして
  受け付ける（出力を作るときに src-- で先頭の 1 つ前を読む。未確認）。papimela は
  "file:/" で始まらない文字列をすべて False にする。スキームの大文字小文字は SDL と
  同じく区別する（"FILE:///a" は False）。
  PORT-NOTE: ホスト名の検査の条件 src[2] != '/' は、1 文字のホスト名（"file://a/x"）を
  検査から外す。意図は "///" を除くことのようだが、その場合は local の判定で済んでいる
  ので、この条件は 1 文字のホスト名にだけ効く。SDL と同じに写した（不具合かどうかは
  未確認）。
  PORT-NOTE(bug): ホスト名の後ろが "/" で始まる（"file://localhost//a"）と、SDL は先頭の
  "/" を 1 つ落とすので "a"（相対のパス）になる（未確認）。ホストの後ろは常に絶対の
  パスなので、papimela は "/" を足して "//a" にする。 }
function PMLURIToLocalPath(const AURI: String; out APath: String): Boolean;
var
  Rest, Host: String;
  Local, AfterHost: Boolean;
  HostEnd: Integer;
begin
  APath := '';
  Result := False;
  if Copy(AURI, 1, 6) <> 'file:/' then
    Exit;
  Rest := Copy(AURI, 7, MaxInt);

  Local := (Rest = '') or (Rest[1] <> '/') or ((Length(Rest) >= 2) and (Rest[2] = '/'));

  AfterHost := False;
  // ホスト名があれば見る。ホスト名は大文字小文字を区別しない（RFC 3986）。
  if (not Local) and ((Length(Rest) < 3) or (Rest[3] <> '/')) then
  begin
    HostEnd := Pos('/', Copy(Rest, 2, MaxInt));
    if HostEnd > 0 then
    begin
      Host := Copy(Rest, 2, HostEnd - 1);
      if SameAsciiText(Host, GetHostName) or SameAsciiText(Host, 'localhost') then
      begin
        Rest := Copy(Rest, HostEnd + 2, MaxInt);
        Local := True;
        AfterHost := True;
      end;
    end;
  end;

  if not Local then
    Exit;
  // Rest が "/" で始まるなら先頭の 1 つを落とし、そうでなければ "/" を足す
  // （SDL の src++ / src-- に当たる。後者は "file:/" の最後の "/" を指し直している）。
  // ホストの後ろは上の PORT-NOTE(bug) のとおり、常に "/" を足す。
  if (not AfterHost) and (Rest <> '') and (Rest[1] = '/') then
    Delete(Rest, 1, 1)
  else
    Rest := '/' + Rest;
  APath := URIDecode(Rest);
  Result := True;
end;

function PMLURIListToLocalPaths(const AList: String): TStringArray;
var
  I, Start: Integer;
  Line, Path: String;

  procedure TakeLine;
  begin
    Line := Copy(AList, Start, I - Start);
    // 空の行と注釈の行（RFC 2483）は飛ばす。
    if (Line <> '') and (Line[1] <> '#') and PMLURIToLocalPath(Line, Path) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Path;
    end;
  end;

begin
  Result := nil;
  Start := 1;
  for I := 1 to Length(AList) do
    if (AList[I] = #13) or (AList[I] = #10) then
    begin
      TakeLine;
      Start := I + 1;
    end;
  I := Length(AList) + 1;
  TakeLine;
end;

end.
