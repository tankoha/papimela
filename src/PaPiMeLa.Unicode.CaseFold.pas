{
  PaPiMeLa.Unicode.CaseFold — UTF-8 の読み進めと、大文字小文字の畳み込み

  Origin : partially ported from SDL (src/stdlib/SDL_string.c, src/stdlib/SDL_casefolding.h)
           Scope: StepUTF8（SDL_StepUTF8。不正な並びは U+FFFD 1 つにして 1 バイト進む）、
           SDL_CaseFoldUnicode（コードポイントを、小文字への畳み込み 1〜3 個にする）、
           SDL_GlobDirectory の CaseFoldUtf8String（文字列全体を畳み込んで UTF-8 に戻す）。
           畳み込みの表は SDL_casefolding.h を tools/gencasefold.bb が写した（Unicode の CaseFolding.txt の
           C と S の対応）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #74

  WHAT:
    ファイルの名前の大文字小文字を見ない比べ（PaPiMeLa.FileSystem の Glob）の土台。ドイツ語の ß → ss のように
    1 文字が 2〜3 文字になる畳み込みも持つ。

  RESOLVED:
    - 4 バイトの UTF-8 の 2 バイト目のマスクを 0x3F にした。SDL は 0x1F で、U+20000 以上（CJK 拡張 B など）を
      不正として U+FFFD にする（PORT-NOTE(bug): 上流の不具合 D-82）。畳み込みの表にこの範囲は無いので、
      畳み込みの結果は SDL と変わらない
    - 畳み込みの表は、SDL の 4 つの表（1_16・2_16・3_16・1_32）を 1 つの整列した配列にして二分探索する
      （SDL はハッシュ。引いた結果は同じで、検査が全コードポイントで確かめる）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Unicode.CaseFold;

{$I papimela.inc}

interface

uses
  SysUtils;

const
  // 不正な並びを置き換える文字（SDL_INVALID_UNICODE_CODEPOINT）
  PML_INVALID_CODEPOINT = $FFFD;

type
  TPMLFoldedCodepoints = array[0..2] of LongWord;

{ AText の APos（1 起点）から 1 つ読んで、コードポイントを返し、APos を進める。終わり（APos が範囲外）は 0 で
  APos は進めない。不正な並びは U+FFFD で 1 バイト進む（SDL_StepUTF8）。 }
function PMLStepUTF8(const AText: String; var APos: Integer): LongWord;

{ コードポイントを小文字へ畳み込む（SDL_CaseFoldUnicode）。畳み込んだ数（1〜3）を返し、AFolded の先頭から入れる。
  畳み込みの無い文字はそのまま 1 つ。 }
function PMLCaseFoldCodepoint(ACodepoint: LongWord; out AFolded: TPMLFoldedCodepoints): Integer;

{ コードポイントを UTF-8 の文字列に足す。0x10FFFF を超えるものは足さない。 }
procedure PMLAppendCodepointUTF8(var AText: String; ACodepoint: LongWord);

{ 文字列全体を畳み込んで返す（CaseFoldUtf8String）。 }
function PMLCaseFoldUTF8(const AText: String): String;

implementation

type
  TCaseFoldEntry = record
    From: LongWord;
    Count: Byte;
    To0, To1, To2: LongWord;
  end;

{$I generated/casefold_tables.inc}

function PMLStepUTF8(const AText: String; var APos: Integer): LongWord;
var
  Len, Octet, B1, B2, B3: LongWord;
  R: LongWord;
  Remaining: Integer;
begin
  Len := Length(AText);
  if (APos < 1) or (APos > Integer(Len)) then
    Exit(0);
  Octet := Ord(AText[APos]);
  Remaining := Integer(Len) - APos + 1;
  if Octet = 0 then
    Exit(0);         // C の文字列の終わり。進めない
  if (Octet and $80) = 0 then
  begin
    Inc(APos);
    Exit(Octet);
  end
  else if ((Octet and $E0) = $C0) and (Remaining >= 2) then
  begin
    B1 := Ord(AText[APos + 1]);
    if (B1 and $C0) = $80 then
    begin
      R := ((Octet and $1F) shl 6) or (B1 and $3F);
      if R >= $80 then          // 冗長な符号は不正
      begin
        Inc(APos, 2);
        Exit(R);
      end;
    end;
  end
  else if ((Octet and $F0) = $E0) and (Remaining >= 3) then
  begin
    B1 := Ord(AText[APos + 1]);
    B2 := Ord(AText[APos + 2]);
    if ((B1 and $C0) = $80) and ((B2 and $C0) = $80) then
    begin
      R := ((Octet and $0F) shl 12) or ((B1 and $3F) shl 6) or (B2 and $3F);
      if R >= $800 then
        if (R < $D800) or (R > $DFFF) then     // サロゲートは不正
        begin
          Inc(APos, 3);
          Exit(R);
        end;
    end;
  end
  else if ((Octet and $F8) = $F0) and (Remaining >= 4) then
  begin
    B1 := Ord(AText[APos + 1]);
    B2 := Ord(AText[APos + 2]);
    B3 := Ord(AText[APos + 3]);
    if ((B1 and $C0) = $80) and ((B2 and $C0) = $80) and ((B3 and $C0) = $80) then
    begin
      // PORT-NOTE(bug): SDL は B1 を 0x1F でマスクして上位 1 ビットを落とす（U+20000 以上が不正になる。D-82）
      R := ((Octet and $07) shl 18) or ((B1 and $3F) shl 12) or ((B2 and $3F) shl 6) or (B3 and $3F);
      if R >= $10000 then
      begin
        Inc(APos, 4);
        Exit(R);
      end;
    end;
  end;
  // 不正な 1 バイト: 置き換えの文字にして進む
  Inc(APos);
  Result := PML_INVALID_CODEPOINT;
end;

function PMLCaseFoldCodepoint(ACodepoint: LongWord; out AFolded: TPMLFoldedCodepoints): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  AFolded[0] := ACodepoint;
  AFolded[1] := 0;
  AFolded[2] := 0;
  Result := 1;
  if ACodepoint < 128 then
  begin
    if (ACodepoint >= Ord('A')) and (ACodepoint <= Ord('Z')) then
      AFolded[0] := Ord('a') + (ACodepoint - Ord('A'));
    Exit;
  end;
  Lo := 0;
  Hi := High(CaseFoldTable);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) shr 1;
    if CaseFoldTable[Mid].From < ACodepoint then
      Lo := Mid + 1
    else if CaseFoldTable[Mid].From > ACodepoint then
      Hi := Mid - 1
    else
    begin
      AFolded[0] := CaseFoldTable[Mid].To0;
      AFolded[1] := CaseFoldTable[Mid].To1;
      AFolded[2] := CaseFoldTable[Mid].To2;
      Exit(CaseFoldTable[Mid].Count);
    end;
  end;
end;

procedure PMLAppendCodepointUTF8(var AText: String; ACodepoint: LongWord);
begin
  if ACodepoint < $80 then
    AText := AText + Chr(ACodepoint)
  else if ACodepoint < $800 then
    AText := AText + Chr((ACodepoint shr 6) or $C0) + Chr((ACodepoint and $3F) or $80)
  else if ACodepoint < $10000 then
    AText := AText + Chr((ACodepoint shr 12) or $E0) + Chr(((ACodepoint shr 6) and $3F) or $80)
      + Chr((ACodepoint and $3F) or $80)
  else if ACodepoint <= $10FFFF then
    AText := AText + Chr((ACodepoint shr 18) or $F0) + Chr(((ACodepoint shr 12) and $3F) or $80)
      + Chr(((ACodepoint shr 6) and $3F) or $80) + Chr((ACodepoint and $3F) or $80);
end;

function PMLCaseFoldUTF8(const AText: String): String;
var
  Pos_, N, I: Integer;
  CP: LongWord;
  Folded: TPMLFoldedCodepoints;
begin
  Result := '';
  Pos_ := 1;
  CP := PMLStepUTF8(AText, Pos_);
  while CP <> 0 do
  begin
    N := PMLCaseFoldCodepoint(CP, Folded);
    for I := 0 to N - 1 do
      PMLAppendCodepointUTF8(Result, Folded[I]);
    CP := PMLStepUTF8(AText, Pos_);
  end;
end;

end.
