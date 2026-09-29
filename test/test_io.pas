{
  test_io — ストリームと型付きの読み書き

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    ファイルの往復、型付き読み書きのバイト順、既存メモリを参照するストリーム、
    そして「要求より少ないバイト数しか返さない相手」から読み切れることを確認する。

  WHY:
    SDL から引き継いだ回避策は短い読み書きへの対処だけで、それが効いているかは
    普通のファイルでは分からない（ファイルは要求どおり返すため）。
    **わざと小刻みにしか返さないストリームを噛ませて検査する。**

    バイト順は実行環境のエンディアンに依らずに組み立てているので、
    書いた結果のバイト列そのものを検査する。

  実行前提: 無し。一時ファイルを作って消す。
}
program test_io;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Classes,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.IO;

type
  { 1 回につき最大 ADrip バイトしか返さないストリーム。

    パイプやソケットの振る舞いを机上で再現する。これが無いと
    TPMLFileStream の「読み切る」処理を通せない。 }
  TDripStream = class(TStream)
  strict private
    FData : TBytes;
    FPos  : Integer;
    FDrip : Integer;
    FCalls: Integer;
  public
    constructor Create(const AData: TBytes; ADrip: Integer);
    function Read(var ABuffer; ACount: LongInt): LongInt; override;
    function Write(const ABuffer; ACount: LongInt): LongInt; override;
    function Seek(const AOffset: Int64; AOrigin: TSeekOrigin): Int64; override;
    property Calls: Integer read FCalls;
  end;

constructor TDripStream.Create(const AData: TBytes; ADrip: Integer);
begin
  inherited Create;
  FData := AData;
  FDrip := ADrip;
end;

function TDripStream.Read(var ABuffer; ACount: LongInt): LongInt;
begin
  Inc(FCalls);
  Result := Length(FData) - FPos;
  if Result > ACount then
    Result := ACount;
  if Result > FDrip then
    Result := FDrip;
  if Result <= 0 then
    Exit(0);
  Move(FData[FPos], ABuffer, Result);
  Inc(FPos, Result);
end;

function TDripStream.Write(const ABuffer; ACount: LongInt): LongInt;
begin
  Result := 0;
end;

function TDripStream.Seek(const AOffset: Int64; AOrigin: TSeekOrigin): Int64;
begin
  case AOrigin of
    soBeginning: FPos := AOffset;
    soCurrent  : Inc(FPos, AOffset);
    soEnd      : FPos := Length(FData) + AOffset;
  end;
  Result := FPos;
end;

var
  Failures: Integer = 0;

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

procedure Note(const AText: String);
begin
  WriteLn('  [観測] ', AText);
end;

function BytesOf(const AValues: array of Byte): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Length(AValues));
  for I := 0 to High(AValues) do
    Result[I] := AValues[I];
end;

function SameBytes(const A, B: TBytes): Boolean;
var
  I: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
    Exit;
  for I := 0 to High(A) do
    if A[I] <> B[I] then
      Exit(False);
end;

var
  Path   : String;
  Data   : TBytes;
  Back   : TBytes;
  Mem    : TMemoryStream;
  Drip   : TDripStream;
  RO     : TPMLMemoryStream;
  FS     : TPMLFileStream;
  Buf    : array[0..63] of Byte;
  Got    : LongInt;
  Raised : Boolean;
  I      : Integer;
  Text   : String;
begin
  WriteLn('test_io — ストリームと型付きの読み書き');
  WriteLn;

  Path := GetTempDir(False) + 'papimela-test-io.bin';

  WriteLn('1. ファイルの往復');
  SetLength(Data, 1000);
  for I := 0 to High(Data) do
    Data[I] := Byte(I * 7 + 3);
  PMLSaveFile(Path, Data);
  Check(FileExists(Path), 'ファイルができる');
  Back := PMLLoadFile(Path);
  Check(SameBytes(Data, Back), '書いた内容がそのまま読める（1000 バイト）');

  // 空のファイルも扱えること。境界で落ちやすい。
  PMLSaveFile(Path, nil);
  Back := PMLLoadFile(Path);
  Check(Length(Back) = 0, '空のファイルは長さ 0 で返る');

  WriteLn;
  WriteLn('2. 開けない場合');
  Raised := False;
  try
    FS := TPMLFileStream.Create(GetTempDir(False) + 'papimela-no-such-dir/x.bin',
      TPMLFileMode.Read);
    FS.Free;
  except
    on E: EPMLIOError do
      Raised := True;
  end;
  Check(Raised, '存在しないパスは EPMLIOError');

  WriteLn;
  WriteLn('3. 型付きの読み書き（バイト列を直接検査する）');
  Mem := TMemoryStream.Create;
  try
    PMLWriteU8(Mem, $AB);
    PMLWriteU16LE(Mem, $1234);
    PMLWriteU16BE(Mem, $1234);
    PMLWriteU32LE(Mem, $DEADBEEF);
    PMLWriteU32BE(Mem, $DEADBEEF);
    Check(Mem.Size = 1 + 2 + 2 + 4 + 4, '書いた長さが合う');

    SetLength(Back, Mem.Size);
    Mem.Position := 0;
    Mem.ReadBuffer(Back[0], Mem.Size);
    // LE は下位バイトが先、BE は上位バイトが先。
    Check(SameBytes(Back, BytesOf([$AB,
                                   $34, $12,
                                   $12, $34,
                                   $EF, $BE, $AD, $DE,
                                   $DE, $AD, $BE, $EF])),
      'バイト列が期待どおり（LE / BE の並び）');

    Mem.Position := 0;
    Check(PMLReadU8(Mem) = $AB, 'U8 を読み戻せる');
    Check(PMLReadU16LE(Mem) = $1234, 'U16LE を読み戻せる');
    Check(PMLReadU16BE(Mem) = $1234, 'U16BE を読み戻せる');
    Check(PMLReadU32LE(Mem) = $DEADBEEF, 'U32LE を読み戻せる');
    Check(PMLReadU32BE(Mem) = $DEADBEEF, 'U32BE を読み戻せる');

    // 符号付きは最上位ビットが立つ値で確かめる。
    Mem.Position := 0;
    Mem.Size := 0;
    PMLWriteU16LE(Mem, $FFFF);
    PMLWriteU32LE(Mem, $FFFFFFFF);
    Mem.Position := 0;
    Check(PMLReadS16LE(Mem) = -1, 'S16LE は符号付きで返る');
    Check(PMLReadS32LE(Mem) = -1, 'S32LE は符号付きで返る');

    // 足りない場合は例外。部分的に読めた状態で返さない。
    Mem.Position := Mem.Size;
    Raised := False;
    try
      PMLReadU32LE(Mem);
    except
      on E: EPMLIOError do
        Raised := True;
    end;
    Check(Raised, '終端で読むと EPMLIOError');
  finally
    Mem.Free;
  end;

  WriteLn;
  WriteLn('4. 小刻みにしか返さない相手から読み切る');
  // SDL から引き継いだ回避策が効いているかを見る唯一の経路。
  SetLength(Data, 300);
  for I := 0 to High(Data) do
    Data[I] := Byte(I);
  Drip := TDripStream.Create(Data, 7);   // 1 回 7 バイトずつしか返さない
  try
    SetLength(Back, 300);
    // まず素の Read は 7 バイトしか返さないことを確かめる（前提の確認）。
    Got := Drip.Read(Back[0], 300);
    Check(Got = 7, '素の Read は 7 バイトしか返さない');

    Drip.Position := 0;
    PMLReadExactly(Drip, Back[0], 300);
    Check(SameBytes(Data, Back), 'PMLReadExactly が小刻みでも読み切る');

    // 本当に足りないときだけ例外にする。
    Drip.Position := 0;
    Raised := False;
    try
      PMLReadExactly(Drip, Back[0], 301);
    except
      on E: EPMLIOError do
        Raised := True;
    end;
    Check(Raised, '足りなければ EPMLIOError');

    Drip.Position := 0;
    Back := PMLReadAll(Drip);
    Check(Length(Back) = 300, 'PMLReadAll は小刻みでも全部読み切る');
    Check(SameBytes(Data, Back), '読み切った内容が一致する');
    Note(Format('Read の呼び出し回数 %d（7 バイトずつなので 40 回以上）',
      [Drip.Calls]));
  finally
    Drip.Free;
  end;

  // TPMLFileStream 自身の読み切りも確かめる。ファイルは普通 1 回で返すので、
  // ここでは「要求より大きい読み取りが終端で止まる」ことを見る。
  SetLength(Data, 100);
  for I := 0 to High(Data) do
    Data[I] := Byte(I);
  PMLSaveFile(Path, Data);
  FS := TPMLFileStream.Create(Path, TPMLFileMode.Read);
  try
    Got := FS.Read(Buf, SizeOf(Buf));
    Check(Got = SizeOf(Buf), 'ファイルから要求どおり読める');
    Check(Buf[0] = 0, '先頭の値が合う');
    Check(Buf[63] = 63, '末尾の値が合う');
    // 残りは 36 バイトしかないので、64 を要求しても 36 で止まる。
    Got := FS.Read(Buf, SizeOf(Buf));
    Check(Got = 36, '終端では読めた分だけ返る');
    Got := FS.Read(Buf, SizeOf(Buf));
    Check(Got = 0, '終端を超えると 0');
  finally
    FS.Free;
  end;

  WriteLn;
  WriteLn('5. 既存メモリを参照するストリーム');
  SetLength(Data, 4);
  Data[0] := $11; Data[1] := $22; Data[2] := $33; Data[3] := $44;
  RO := TPMLMemoryStream.Create(@Data[0], 4);
  try
    Check(RO.Size = 4, '長さが合う');
    Check(PMLReadU32LE(RO) = $44332211, '内容を読める');
    // 複製していないので、元の配列を書き換えると見える値も変わる。
    Data[0] := $99;
    RO.Position := 0;
    Check(PMLReadU8(RO) = $99, '複製せず元の領域を参照している');
    Raised := False;
    try
      RO.Write(Data[0], 1);
    except
      on E: EPMLIOError do
        Raised := True;
    end;
    Check(Raised, '書き込みは EPMLIOError');
  finally
    RO.Free;
  end;

  WriteLn;
  WriteLn('6. テキストの読み込み');
  PMLSaveFile(Path, BytesOf([$EF, $BB, $BF, Ord('a'), Ord('b'), Ord('c')]));
  Text := PMLLoadTextFile(Path);
  Check(Text = 'abc', 'UTF-8 BOM を取り除く');
  PMLSaveFile(Path, BytesOf([Ord('x'), Ord('y')]));
  Check(PMLLoadTextFile(Path) = 'xy', 'BOM が無ければそのまま');

  WriteLn;
  WriteLn('7. 後始末');
  Check(DeleteFile(Path), '一時ファイルを消せる');

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn('=== 結論: ストリームが設計どおり動く ===');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('=== 失敗 %d 件 ===', [Failures]));
    ExitCode := 1;
  end;
end.
