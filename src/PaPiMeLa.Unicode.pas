{
  PaPiMeLa.Unicode — UTF-8 のバイト位置とコードポイント位置の相互変換

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §7.3（バイトと文字の二重表現）

  WHAT:
    Pascal の String は UTF-8 バイト列だが、IBus / Fcitx はコードポイント単位で
    位置を表す。イベントには両方を載せるため、その変換を提供する。

  WHY:
    アプリに変換コードを書かせないため。papimela 側で一度だけ変換する。

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Unicode;

{$I papimela.inc}

interface

// 先頭バイトかどうか。継続バイトは 10xxxxxx。
function IsUTF8Lead(AByte: Byte): Boolean; inline;

// AText 全体のコードポイント数。
function UTF8CodePointCount(const AText: String): Integer;

// コードポイント位置 → バイトオフセット（0 起点）。範囲外は端にクランプする。
function UTF8CharToByteOffset(const AText: String; ACharIndex: Integer): Integer;

// バイトオフセット → コードポイント位置（0 起点）。継続バイトを指した場合は
// その文字の先頭として数える。
function UTF8ByteToCharOffset(const AText: String; AByteOffset: Integer): Integer;

// AByteOffset を文字境界へ丸める（後方へ）。
function UTF8FloorToCharBoundary(const AText: String; AByteOffset: Integer): Integer;

implementation

function IsUTF8Lead(AByte: Byte): Boolean;
begin
  Result := (AByte and $C0) <> $80;
end;

function UTF8CodePointCount(const AText: String): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(AText) do
    if IsUTF8Lead(Byte(AText[I])) then
      Inc(Result);
end;

function UTF8CharToByteOffset(const AText: String; ACharIndex: Integer): Integer;
var
  I, Seen: Integer;
begin
  if ACharIndex <= 0 then
    Exit(0);
  Seen := 0;
  for I := 1 to Length(AText) do
    if IsUTF8Lead(Byte(AText[I])) then
    begin
      if Seen = ACharIndex then
        Exit(I - 1);
      Inc(Seen);
    end;
  Result := Length(AText);
end;

function UTF8ByteToCharOffset(const AText: String; AByteOffset: Integer): Integer;
var
  I, Limit: Integer;
begin
  Result := 0;
  if AByteOffset <= 0 then
    Exit;
  Limit := AByteOffset;
  if Limit > Length(AText) then
    Limit := Length(AText);
  for I := 1 to Limit do
    if IsUTF8Lead(Byte(AText[I])) then
      Inc(Result);
  // 継続バイトを指していた場合、その文字はまだ完了していないので 1 戻す。
  if (Limit >= 1) and (Limit < Length(AText)) and (not IsUTF8Lead(Byte(AText[Limit + 1]))) then
    Dec(Result);
end;

function UTF8FloorToCharBoundary(const AText: String; AByteOffset: Integer): Integer;
begin
  Result := AByteOffset;
  if Result <= 0 then
    Exit(0);
  if Result > Length(AText) then
    Result := Length(AText);
  while (Result > 0) and (Result < Length(AText)) and (not IsUTF8Lead(Byte(AText[Result + 1]))) do
    Dec(Result);
end;

end.
