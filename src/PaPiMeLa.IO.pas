{
  PaPiMeLa.IO — ストリーム

  Origin : partially ported from SDL (src/io/SDL_iostream.c)
           Scope: fd 実装の回避策に関する知見のみ。read / write が要求より
           少ないバイト数を返したときに残りを読み直すこと。構造は本設計に従い、
           FPC の TStream をそのまま第一級の抽象として使う。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.7、§11 #64

  WHAT:
    TPMLFileStream（短い読み書きを埋める THandleStream 派生）、
    TPMLMemoryStream（既存のメモリを複製せずに読む）、
    型付きの読み書き、ファイル全体の読み書き。

  WHY:
    SDL_IOStream は 5 つのコールバックを持つ独自の抽象だが、その 5 つは
    TStream の Read / Write / Seek / Size にそのまま対応する。papimela は
    独自の抽象を作らず、公開 API はすべて TStream を受け取る。
    こうすると FPC の既存のストリーム（TMemoryStream、TResourceStream、
    圧縮ストリーム）をそのまま渡せる。

  RESOLVED:
    - **EINTR の再試行は FPC の RTL が既に行っている。** sysutils の FileRead /
      FileWrite が ESysEINTR の間ループする。SDL がここで持っている回避策の
      半分は移植する必要が無かった
    - 残る半分、「要求より少ないバイト数が返る」への対処は RTL に無いので
      こちらで埋める

  NOT RESOLVED:
    - 非ブロッキング（EAGAIN）は扱わない。SDL は NOT_READY という状態を
      持っているが、TStream には対応する概念が無い。必要になったら
      別のストリーム種別として足す
    - メモリマップ（mmap）経由の読み取りは未実装。大きなファイルを
      何度も読む場面が出てから考える

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.IO;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Types,
  PaPiMeLa.Errors;

type
  TPMLFileMode = (Read, Write, ReadWrite, Append);

  { ファイル。

    THandleStream との違いは Read / Write が「要求した分を読み切る / 書き切る」
    ところ。下の層が少ないバイト数を返しても、終端かエラーになるまで繰り返す。

    PORT-NOTE: SDL_iostream.c の fd_read / fd_write が同じことをしている。
    SDL は 1 回だけ読み直すが、こちらは読み切るまで繰り返す。パイプのように
    小刻みに届く相手では 1 回では足りないことがある。 }
  TPMLFileStream = class(THandleStream)
  strict private
    FPath: String;
  public
    // 開けなければ EPMLIOError。errno が例外の NativeCode に入る。
    constructor Create(const APath: String; AMode: TPMLFileMode = TPMLFileMode.Read);
    destructor Destroy; override;
    function Read(var ABuffer; ACount: LongInt): LongInt; override;
    function Write(const ABuffer; ACount: LongInt): LongInt; override;
    property Path: String read FPath;
  end;

  { 既存のメモリを複製せずに読むストリーム。

    TMemoryStream は必ず自前の領域へ複製する。埋め込み資源や mmap した領域を
    そのまま解釈したい場面ではそれが無駄になるので、参照するだけの種別を置く。
    書き込みはできない。 }
  TPMLMemoryStream = class(TCustomMemoryStream)
  public
    constructor Create(APtr: Pointer; ASize: PtrInt);
    function Write(const ABuffer; ACount: LongInt): LongInt; override;
  end;

// ---- 型付きの読み書き
//
// クラスヘルパにしないのは、FPC では同じ型に対して見えるヘルパが 1 つだけで、
// アプリが自分のヘルパを定義すると papimela 側が隠れてしまうため。

// 足りなければ EPMLIOError。部分的に読めた状態で返すことはない。
function PMLReadU8(AStream: TStream): Byte;
function PMLReadU16LE(AStream: TStream): Word;
function PMLReadU32LE(AStream: TStream): LongWord;
function PMLReadU16BE(AStream: TStream): Word;
function PMLReadU32BE(AStream: TStream): LongWord;
function PMLReadS16LE(AStream: TStream): SmallInt;
function PMLReadS32LE(AStream: TStream): LongInt;

procedure PMLWriteU8(AStream: TStream; AValue: Byte);
procedure PMLWriteU16LE(AStream: TStream; AValue: Word);
procedure PMLWriteU32LE(AStream: TStream; AValue: LongWord);
procedure PMLWriteU16BE(AStream: TStream; AValue: Word);
procedure PMLWriteU32BE(AStream: TStream; AValue: LongWord);

// 要求した分を読み切る。足りなければ EPMLIOError（何バイト読めたかを含む）。
procedure PMLReadExactly(AStream: TStream; var ABuffer; ACount: LongInt);
procedure PMLWriteExactly(AStream: TStream; const ABuffer; ACount: LongInt);

// 現在位置から終端まで。空なら長さ 0 の配列。
function PMLReadAll(AStream: TStream): TBytes;

// ---- ファイル全体

function PMLLoadFile(const APath: String): TBytes;
procedure PMLSaveFile(const APath: String; const AData: TBytes);
// テキストとして読む。UTF-8 とみなす。BOM があれば取り除く。
function PMLLoadTextFile(const APath: String): String;

implementation

uses
  BaseUnix;

const
  // Size が分からないストリームを読むときに伸ばす単位。
  CHUNK_SIZE = 1024 * 1024;

{ TPMLFileStream }

function OpenPath(const APath: String; AMode: TPMLFileMode): THandle;
begin
  case AMode of
    TPMLFileMode.Read     : Result := FileOpen(APath, fmOpenRead or fmShareDenyNone);
    TPMLFileMode.Write    : Result := FileCreate(APath);
    TPMLFileMode.ReadWrite: begin
                              Result := FileOpen(APath, fmOpenReadWrite or fmShareDenyNone);
                              if Result = THandle(-1) then
                                Result := FileCreate(APath);
                            end;
    TPMLFileMode.Append   : begin
                              Result := FileOpen(APath, fmOpenWrite or fmShareDenyNone);
                              if Result = THandle(-1) then
                                Result := FileCreate(APath)
                              else
                                FileSeek(Result, 0, fsFromEnd);
                            end;
  else
    Result := THandle(-1);
  end;
end;

constructor TPMLFileStream.Create(const APath: String; AMode: TPMLFileMode);
var
  H: THandle;
begin
  H := OpenPath(APath, AMode);
  if H = THandle(-1) then
    raise EPMLIOError.CreateNative(
      Format('could not open "%s"', [APath]), fpGetErrno, 'open');
  inherited Create(H);
  FPath := APath;
end;

destructor TPMLFileStream.Destroy;
begin
  if Handle <> THandle(-1) then
    FileClose(Handle);
  inherited Destroy;
end;

{ 要求した分を読み切る。

  0 が返ったら終端なのでそこで止める。負が返ったらエラーなので、
  それまでに読めた分を返す（呼び出し側が短い結果で気づける）。 }
function TPMLFileStream.Read(var ABuffer; ACount: LongInt): LongInt;
var
  Done, Got: LongInt;
  P: PByte;
begin
  Result := 0;
  if ACount <= 0 then
    Exit;
  P := @ABuffer;
  Done := 0;
  while Done < ACount do
  begin
    Got := inherited Read(P[Done], ACount - Done);
    if Got <= 0 then
      Break;
    Inc(Done, Got);
  end;
  Result := Done;
end;

function TPMLFileStream.Write(const ABuffer; ACount: LongInt): LongInt;
var
  Done, Put: LongInt;
  P: PByte;
begin
  Result := 0;
  if ACount <= 0 then
    Exit;
  P := @ABuffer;
  Done := 0;
  while Done < ACount do
  begin
    Put := inherited Write(P[Done], ACount - Done);
    if Put <= 0 then
      Break;
    Inc(Done, Put);
  end;
  Result := Done;
end;

{ TPMLMemoryStream }

constructor TPMLMemoryStream.Create(APtr: Pointer; ASize: PtrInt);
begin
  inherited Create;
  if ASize < 0 then
    ASize := 0;
  // SetPointer は TCustomMemoryStream の protected。領域は借りるだけで解放しない。
  SetPointer(APtr, ASize);
end;

function TPMLMemoryStream.Write(const ABuffer; ACount: LongInt): LongInt;
begin
  Result := 0;
  raise EPMLIOError.Create('TPMLMemoryStream is read-only');
end;

{ ---- 型付きの読み書き ---- }

{ 要求した分を読み切る。

  1 回の Read で足りなくても、終端かエラーになるまで繰り返す。
  パイプのように小刻みにしか返さない相手からでも、データがある限り読み切れる。
  それでも足りなければ例外にする（部分的に読めた状態では返さない）。 }
procedure PMLReadExactly(AStream: TStream; var ABuffer; ACount: LongInt);
var
  Done, Got: LongInt;
  P: PByte;
begin
  if ACount <= 0 then
    Exit;
  P := @ABuffer;
  Done := 0;
  while Done < ACount do
  begin
    Got := AStream.Read(P[Done], ACount - Done);
    if Got <= 0 then
      Break;
    Inc(Done, Got);
  end;
  if Done <> ACount then
    raise EPMLIOError.Create(
      Format('expected %d bytes but got %d', [ACount, Done]));
end;

procedure PMLWriteExactly(AStream: TStream; const ABuffer; ACount: LongInt);
var
  Done, Put: LongInt;
  P: PByte;
begin
  if ACount <= 0 then
    Exit;
  P := @ABuffer;
  Done := 0;
  while Done < ACount do
  begin
    Put := AStream.Write(P[Done], ACount - Done);
    if Put <= 0 then
      Break;
    Inc(Done, Put);
  end;
  if Done <> ACount then
    raise EPMLIOError.Create(
      Format('expected to write %d bytes but wrote %d', [ACount, Done]));
end;

function PMLReadU8(AStream: TStream): Byte;
begin
  PMLReadExactly(AStream, Result, 1);
end;

{ リトルエンディアンの 16 ビット。

  バイト単位で組み立てるのは、実行環境のエンディアンに依らせないため。
  papimela の初回スコープはリトルエンディアンだけだが、ファイル形式の
  読み書きで環境依存の記述を混ぜたくない。 }
function PMLReadU16LE(AStream: TStream): Word;
var
  B: array[0..1] of Byte;
begin
  PMLReadExactly(AStream, B, 2);
  Result := Word(B[0]) or (Word(B[1]) shl 8);
end;

function PMLReadU32LE(AStream: TStream): LongWord;
var
  B: array[0..3] of Byte;
begin
  PMLReadExactly(AStream, B, 4);
  Result := LongWord(B[0]) or (LongWord(B[1]) shl 8)
         or (LongWord(B[2]) shl 16) or (LongWord(B[3]) shl 24);
end;

function PMLReadU16BE(AStream: TStream): Word;
var
  B: array[0..1] of Byte;
begin
  PMLReadExactly(AStream, B, 2);
  Result := (Word(B[0]) shl 8) or Word(B[1]);
end;

function PMLReadU32BE(AStream: TStream): LongWord;
var
  B: array[0..3] of Byte;
begin
  PMLReadExactly(AStream, B, 4);
  Result := (LongWord(B[0]) shl 24) or (LongWord(B[1]) shl 16)
         or (LongWord(B[2]) shl 8) or LongWord(B[3]);
end;

function PMLReadS16LE(AStream: TStream): SmallInt;
begin
  Result := SmallInt(PMLReadU16LE(AStream));
end;

function PMLReadS32LE(AStream: TStream): LongInt;
begin
  Result := LongInt(PMLReadU32LE(AStream));
end;

procedure PMLWriteU8(AStream: TStream; AValue: Byte);
begin
  PMLWriteExactly(AStream, AValue, 1);
end;

procedure PMLWriteU16LE(AStream: TStream; AValue: Word);
var
  B: array[0..1] of Byte;
begin
  B[0] := Byte(AValue);
  B[1] := Byte(AValue shr 8);
  PMLWriteExactly(AStream, B, 2);
end;

procedure PMLWriteU32LE(AStream: TStream; AValue: LongWord);
var
  B: array[0..3] of Byte;
begin
  B[0] := Byte(AValue);
  B[1] := Byte(AValue shr 8);
  B[2] := Byte(AValue shr 16);
  B[3] := Byte(AValue shr 24);
  PMLWriteExactly(AStream, B, 4);
end;

procedure PMLWriteU16BE(AStream: TStream; AValue: Word);
var
  B: array[0..1] of Byte;
begin
  B[0] := Byte(AValue shr 8);
  B[1] := Byte(AValue);
  PMLWriteExactly(AStream, B, 2);
end;

procedure PMLWriteU32BE(AStream: TStream; AValue: LongWord);
var
  B: array[0..3] of Byte;
begin
  B[0] := Byte(AValue shr 24);
  B[1] := Byte(AValue shr 16);
  B[2] := Byte(AValue shr 8);
  B[3] := Byte(AValue);
  PMLWriteExactly(AStream, B, 4);
end;

{ 現在位置から終端まで読む。

  Size が分かるストリームは残りを一度に確保する。分からない（パイプ等）場合は
  区切りごとに伸ばしながら読む。 }
{ 現在位置から終端まで読む。

  Size が分かるストリームは残りを一度に確保してから読み切る。**確保してから
  1 回読むだけでは足りない。** Size は「残りがどれだけあるか」を言うだけで、
  1 回の Read がそれを全部返す保証はない。

  Size が 0 を返すストリーム（パイプ等）は、読めなくなるまで伸ばしながら読む。 }
function PMLReadAll(AStream: TStream): TBytes;
var
  Remaining: Int64;
  Done, Got, Room: LongInt;
begin
  Result := nil;
  Done := 0;
  Remaining := AStream.Size - AStream.Position;

  if Remaining > 0 then
  begin
    if Remaining > High(LongInt) then
      raise EPMLIOError.Create('stream is too large to read into memory');
    SetLength(Result, Remaining);
    while Done < Remaining do
    begin
      Got := AStream.Read(Result[Done], LongInt(Remaining) - Done);
      if Got <= 0 then
        Break;
      Inc(Done, Got);
    end;
    if Done <> Remaining then
      SetLength(Result, Done);
    Exit;
  end;

  // Size を当てにできないストリーム。区切りごとに伸ばす。
  repeat
    if Length(Result) - Done < CHUNK_SIZE then
      SetLength(Result, Done + CHUNK_SIZE);
    Room := Length(Result) - Done;
    Got := AStream.Read(Result[Done], Room);
    if Got > 0 then
      Inc(Done, Got);
  until Got <= 0;
  SetLength(Result, Done);
end;

function PMLLoadFile(const APath: String): TBytes;
var
  S: TPMLFileStream;
begin
  S := TPMLFileStream.Create(APath, TPMLFileMode.Read);
  try
    Result := PMLReadAll(S);
  finally
    S.Free;
  end;
end;

procedure PMLSaveFile(const APath: String; const AData: TBytes);
var
  S: TPMLFileStream;
begin
  S := TPMLFileStream.Create(APath, TPMLFileMode.Write);
  try
    if Length(AData) > 0 then
      PMLWriteExactly(S, AData[0], Length(AData));
  finally
    S.Free;
  end;
end;

function PMLLoadTextFile(const APath: String): String;
var
  Data: TBytes;
  Start: Integer;
begin
  Data := PMLLoadFile(APath);
  Start := 0;
  // UTF-8 BOM。付いたまま返すと先頭の比較が必ず外れる。
  if (Length(Data) >= 3) and (Data[0] = $EF) and (Data[1] = $BB)
  and (Data[2] = $BF) then
    Start := 3;
  SetLength(Result, Length(Data) - Start);
  if Length(Result) > 0 then
    Move(Data[Start], Result[1], Length(Result));
end;

end.
