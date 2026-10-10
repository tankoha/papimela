{
  test_properties — プロパティの表とヒントを検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 値の種類ごとの読み書き、空の名前、種類の上書き
    2. 種類をまたいで読むときの変換（文字列 → 数・小数・真偽、小数 → 文字列・数・真偽、
       数・真偽・ポインタ）。期待値は SDL 3.4.2 の実物で測った値（docs/TEST-LOG.md の
       使い捨て検証）。小数を文字列にするときの最後の桁の違いは PORT-NOTE にある
    3. ポインタの後始末（上書き・Clear・nil を置く・表を壊す）
    4. CopyTo（後始末付きのポインタは写さない、写し元を壊しても写し先は無事: D-54）
    5. Enumerate の順序、排他（2 スレッドで数え上げて失われない）
    6. ヒント: 優先度、呼び出しの順序と前後の値、Reset、環境変数（D-57）
    7. PMLStringBoolean / PMLStringInteger

  WHY:
    #6 の受け入れ検査。実装より先に書き、空の実装で落ちることを確かめてから渡す。

  実行前提: cthreads（uses の先頭）。環境変数は libc の setenv で置く（papimela は
  libc の getenv で読む）。
}
program test_properties;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils, Classes, Math,
  PaPiMeLa.Errors,
  PaPiMeLa.Threading,
  PaPiMeLa.Properties;

function setenv(AName, AValue: PAnsiChar; AOverwrite: LongInt): LongInt; cdecl; external 'c';
function unsetenv(AName: PAnsiChar): LongInt; cdecl; external 'c';

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

{ ---- 記録係（後始末・列挙・ヒントの呼び出しを並びで覚える） ---- }

type
  TRecorder = class
  public
    Log: TStringList;
    Tag: String;
    RemoveOther: TPMLHintCallback;   // 呼ばれたら外す呼び出し（nil なら何もしない）
    Hints: TPMLHints;
    constructor Create(const ATag: String);
    destructor Destroy; override;
    procedure Cleanup(AValue: Pointer);
    procedure Enum(AProps: TPMLProperties; const AName: String);
    procedure Hint(const AName: String; const AOld, ANew: TPMLHintValue);
  end;

constructor TRecorder.Create(const ATag: String);
begin
  inherited Create;
  Log := TStringList.Create;
  Tag := ATag;
end;

destructor TRecorder.Destroy;
begin
  Log.Free;
  inherited Destroy;
end;

procedure TRecorder.Cleanup(AValue: Pointer);
begin
  Log.Add('cleanup ' + IntToStr(PtrUInt(AValue)));
end;

procedure TRecorder.Enum(AProps: TPMLProperties; const AName: String);
begin
  Log.Add(AName);
end;

function Show(const AValue: TPMLHintValue): String;
begin
  if AValue.IsSet then
    Result := AValue.Value
  else
    Result := '(unset)';
end;

procedure TRecorder.Hint(const AName: String; const AOld, ANew: TPMLHintValue);
begin
  Log.Add(Format('%s %s: %s -> %s', [Tag, AName, Show(AOld), Show(ANew)]));
  if Assigned(RemoveOther) and (Hints <> nil) then
  begin
    Hints.RemoveCallback(AName, RemoveOther);
    RemoveOther := nil;
  end;
end;

function Joined(AList: TStringList): String;
begin
  Result := StringReplace(Trim(AList.Text), LineEnding, ' | ', [rfReplaceAll]);
end;

function Raises(AProc: TProcedure): Boolean;
begin
  Result := False;
  try
    AProc();
  except
    on E: EPMLArgument do
      Result := True;
  end;
end;

{ ---- 1. 読み書き ---- }

var
  GProps: TPMLProperties;
  GHints: TPMLHints;
  GRec  : TRecorder;

procedure SetEmptyName;
begin
  GProps.SetNumber('', 1);
end;

procedure SetEmptyString;
begin
  GProps.SetString('', 'x');
end;

procedure TestBasics;
var
  P: TPMLProperties;
  X: Integer;
begin
  WriteLn('1. 読み書き');
  P := TPMLProperties.Create;
  try
    P.SetPointer('p', @X);
    P.SetString('s', 'hello');
    P.SetNumber('n', -1234567890123);
    P.SetFloat('f', 1.25);
    P.SetBoolean('b', True);
    Check(P.GetPointer('p') = @X, 'ポインタ');
    Check(P.GetString('s') = 'hello', '文字列');
    Check(P.GetNumber('n') = -1234567890123, '数（64 ビット）');
    Check(P.GetFloat('f') = 1.25, '小数');
    Check(P.GetBoolean('b'), '真偽');
    Check((P.PropertyType('p') = TPMLPropertyType.Pointer_) and (P.PropertyType('s') = TPMLPropertyType.String_)
      and (P.PropertyType('n') = TPMLPropertyType.Number) and (P.PropertyType('f') = TPMLPropertyType.Float)
      and (P.PropertyType('b') = TPMLPropertyType.Boolean_), '種類');
    Check(P.Count = 5, '数は 5');
    Check(P.Has('s') and not P.Has('S'), '名前は大文字小文字を区別する');
    Check(not P.Has('zz') and (P.PropertyType('zz') = TPMLPropertyType.Invalid), '無い名前は Invalid');
    Check((P.GetNumber('zz', 7) = 7) and (P.GetString('zz', 'd') = 'd') and (P.GetFloat('zz', 2) = 2)
      and P.GetBoolean('zz', True) and (P.GetPointer('zz', @X) = @X), '無い名前は既定値');
    P.SetString('s', '');
    Check(P.Has('s') and (P.GetString('s', 'd') = ''), '空の文字列も値として置ける（SDL と同じ）');
    P.SetString('n', 'now a string');
    Check((P.PropertyType('n') = TPMLPropertyType.String_) and (P.Count = 5), '同じ名前に別の種類を置くと置き換わる');
    P.Clear('n');
    Check(not P.Has('n') and (P.Count = 4), 'Clear で消える');
    P.Clear('zz');
    Check(P.Count = 4, '無い名前の Clear は何もしない');
    P.SetPointer('p', nil);
    Check(not P.Has('p'), 'nil のポインタを置くと消える（SDL と同じ）');

    GProps := P;
    Check(Raises(@SetEmptyName) and Raises(@SetEmptyString), '空の名前で書くと EPMLArgument');
    Check((P.GetNumber('', 9) = 9) and not P.Has('') and (P.PropertyType('') = TPMLPropertyType.Invalid),
      '空の名前で読むと既定値');
  finally
    P.Free;
  end;
end;

{ ---- 2. 変換 ---- }

type
  TStrCase = record
    S: String;
    Num: Int64;
    Flt: Single;      // NaN は IsNaN で見る
    BoolT, BoolF: Boolean;
  end;

const
  // SDL 3.4.2 で測った値（文字列 → GetNumber / GetFloat / GetBoolean(True) / GetBoolean(False)）。
  STR_CASES: array[0..26] of TStrCase = (
    (S: '010';         Num: 8;   Flt: 10;   BoolT: False; BoolF: False),
    (S: '0x1F';        Num: 31;  Flt: 31;   BoolT: False; BoolF: False),
    (S: ' -12abc';     Num: -12; Flt: -12;  BoolT: True;  BoolF: True),
    (S: '+7';          Num: 7;   Flt: 7;    BoolT: True;  BoolF: True),
    (S: '99999999999999999999';  Num: High(Int64); Flt: 1e20;  BoolT: True; BoolF: True),
    (S: '-99999999999999999999'; Num: Low(Int64);  Flt: -1e20; BoolT: True; BoolF: True),
    (S: 'abc';         Num: 0;   Flt: 0;    BoolT: True;  BoolF: True),
    (S: '';            Num: 0;   Flt: 0;    BoolT: True;  BoolF: False),
    (S: '0x';          Num: 0;   Flt: 0;    BoolT: False; BoolF: False),
    (S: '08';          Num: 0;   Flt: 8;    BoolT: False; BoolF: False),
    (S: '1e3';         Num: 1;   Flt: 1000; BoolT: True;  BoolF: True),
    (S: '  2.5xyz';    Num: 2;   Flt: 2.5;  BoolT: True;  BoolF: True),
    (S: 'inf';         Num: 0;   Flt: Infinity;  BoolT: True; BoolF: True),
    (S: '-INFINITY';   Num: 0;   Flt: NegInfinity; BoolT: True; BoolF: True),
    (S: 'nan';         Num: 0;   Flt: NaN;  BoolT: True;  BoolF: True),
    (S: '0x10';        Num: 16;  Flt: 16;   BoolT: False; BoolF: False),
    (S: '.5';          Num: 0;   Flt: 0.5;  BoolT: True;  BoolF: True),
    (S: '5.';          Num: 5;   Flt: 5;    BoolT: True;  BoolF: True),
    (S: '1e';          Num: 1;   Flt: 1;    BoolT: True;  BoolF: True),
    (S: '1e+';         Num: 1;   Flt: 1;    BoolT: True;  BoolF: True),
    (S: #9#10' 3';     Num: 3;   Flt: 3;    BoolT: True;  BoolF: True),
    (S: 'true';        Num: 0;   Flt: 0;    BoolT: True;  BoolF: True),
    (S: 'FALSE';       Num: 0;   Flt: 0;    BoolT: False; BoolF: False),
    (S: '0';           Num: 0;   Flt: 0;    BoolT: False; BoolF: False),
    (S: '00';          Num: 0;   Flt: 0;    BoolT: False; BoolF: False),
    (S: 'no';          Num: 0;   Flt: 0;    BoolT: True;  BoolF: True),
    (S: '1.5e-2';      Num: 1;   Flt: 0.015; BoolT: True; BoolF: True));

function SameFloat(A, B: Single): Boolean;
begin
  if IsNaN(B) then
    Result := IsNaN(A)
  else
    Result := A = B;
end;

procedure TestConversions;
var
  P: TPMLProperties;
  I, Bad: Integer;
  C: TStrCase;
  N: Int64;
  F: Single;
  X: Integer;
begin
  WriteLn;
  WriteLn('2. 種類をまたいで読む（期待値は SDL 3.4.2 の実測）');
  P := TPMLProperties.Create;
  try
    Bad := 0;
    for I := Low(STR_CASES) to High(STR_CASES) do
    begin
      C := STR_CASES[I];
      P.SetString('s', C.S);
      N := P.GetNumber('s', -1);
      F := P.GetFloat('s', -1);
      if (N <> C.Num) or not SameFloat(F, C.Flt) or (P.GetBoolean('s', True) <> C.BoolT)
        or (P.GetBoolean('s', False) <> C.BoolF) then
      begin
        WriteLn(Format('  [INFO] [%s] -> %d / %g / %s / %s', [C.S, N, F,
          BoolToStr(P.GetBoolean('s', True), True), BoolToStr(P.GetBoolean('s', False), True)]));
        Inc(Bad);
      end;
    end;
    Check(Bad = 0, Format('文字列 → 数・小数・真偽の %d 通りが SDL と同じ', [Length(STR_CASES)]));

    P.SetFloat('f', 2.5);
    Check((P.GetString('f') = '2.500000') and (P.GetNumber('f') = 3) and P.GetBoolean('f'), '2.5 → "2.500000" / 3 / True');
    P.SetFloat('f', -2.5);
    Check((P.GetString('f') = '-2.500000') and (P.GetNumber('f') = -3), '-2.5 → "-2.500000" / -3（0 から遠い側へ丸める）');
    P.SetFloat('f', 0.5);
    Check(P.GetNumber('f') = 1, '0.5 → 1（Pascal の Round は 0 にする）');
    P.SetFloat('f', 1.4999999);
    Check((P.GetString('f') = '1.500000') and (P.GetNumber('f') = 1), '1.4999999 → "1.500000" / 1');
    P.SetFloat('f', 0.1);
    Check((P.GetString('f') = '0.100000') and (P.GetNumber('f') = 0), '0.1 → "0.100000" / 0');
    P.SetFloat('f', 3);
    Check(P.GetString('f') = '3.000000', '3 → "3.000000"');
    P.SetFloat('f', 1e-7);
    Check((P.GetString('f') = '0.000000') and (P.GetNumber('f') = 0) and P.GetBoolean('f'), '1e-7 → "0.000000" / 0 / True');
    P.SetFloat('f', 1e20);
    Check(P.GetNumber('f') = Low(Int64), '1e20 → 数は Low(Int64)（x86 の SDL と同じ）');
    P.SetFloat('f', Infinity);
    Check((P.GetString('f') = 'inf') and (P.GetNumber('f') = Low(Int64)), 'inf → "inf" / Low(Int64)');
    P.SetFloat('f', NegInfinity);
    Check(P.GetString('f') = '-inf', '-inf → "-inf"');
    P.SetFloat('f', NaN);
    Check((P.GetString('f') = 'nan') and (P.GetNumber('f') = Low(Int64)) and P.GetBoolean('f'), 'nan → "nan" / Low(Int64) / True');
    P.SetFloat('f', -0.0);
    Check((P.GetString('f') = '-0.000000') and not P.GetBoolean('f', True), '-0 → "-0.000000" / False');

    P.SetNumber('n', -42);
    Check((P.GetString('n') = '-42') and (P.GetFloat('n') = -42) and P.GetBoolean('n'), '数 -42 → "-42" / -42 / True');
    P.SetNumber('n', 0);
    Check(not P.GetBoolean('n', True), '数 0 → False');
    P.SetNumber('n', 16777217);
    Check(P.GetFloat('n') = 16777216, '数 16777217 → 小数 16777216');
    P.SetBoolean('b', True);
    Check((P.GetString('b') = 'true') and (P.GetNumber('b') = 1) and (P.GetFloat('b') = 1), '真 → "true" / 1 / 1');
    P.SetBoolean('b', False);
    Check((P.GetString('b') = 'false') and (P.GetNumber('b', 9) = 0), '偽 → "false" / 0');
    P.SetPointer('p', @X);
    Check((P.GetString('p', 'D') = 'D') and (P.GetNumber('p', -1) = -1) and (P.GetFloat('p', -1) = -1)
      and P.GetBoolean('p', True), 'ポインタは他の種類では読めない（既定値）');
    P.SetString('s', 'x');
    Check(P.GetPointer('s', Pointer($1234)) = Pointer($1234), '文字列はポインタとしては読めない（既定値）');
  finally
    P.Free;
  end;
end;

{ ---- 3. ポインタの後始末 ---- }

procedure TestCleanup;
var
  P: TPMLProperties;
  R: TRecorder;
begin
  WriteLn;
  WriteLn('3. ポインタの後始末');
  R := TRecorder.Create('');
  P := TPMLProperties.Create;
  try
    P.SetPointer('a', Pointer(1), @R.Cleanup);
    Check(R.Log.Count = 0, '置いただけでは呼ばない');
    P.SetPointer('a', Pointer(2), @R.Cleanup);
    Check(Joined(R.Log) = 'cleanup 1', '上書きすると前の値で 1 度呼ぶ');
    P.SetNumber('a', 5);
    Check(Joined(R.Log) = 'cleanup 1 | cleanup 2', '別の種類で上書きしても呼ぶ');
    P.SetPointer('b', Pointer(3), @R.Cleanup);
    P.Clear('b');
    Check(Joined(R.Log) = 'cleanup 1 | cleanup 2 | cleanup 3', 'Clear で呼ぶ');
    R.Log.Clear;
    P.SetPointer('c', nil, @R.Cleanup);
    Check((Joined(R.Log) = 'cleanup 0') and not P.Has('c'), 'nil を置くと nil で 1 度呼び、値は置かない（SDL と同じ）');
    R.Log.Clear;
    P.SetPointer('d', Pointer(4), @R.Cleanup);
    P.SetPointer('e', Pointer(5), @R.Cleanup);
    P.SetPointer('f', Pointer(6));
  finally
    P.Free;
  end;
  Check(Joined(R.Log) = 'cleanup 4 | cleanup 5', '表を壊すと残りの後始末を呼ぶ（後始末の無いものは呼ばない）');
  R.Free;
end;

{ ---- 4. CopyTo ---- }

procedure CopyToNil;
begin
  GProps.CopyTo(nil);
end;

procedure CopyToSelf;
begin
  GProps.CopyTo(GProps);
end;

procedure TestCopy;
var
  A, B: TPMLProperties;
  R: TRecorder;
  X: Integer;
begin
  WriteLn;
  WriteLn('4. CopyTo');
  R := TRecorder.Create('');
  A := TPMLProperties.Create;
  B := TPMLProperties.Create;
  try
    A.SetString('s', 'str');
    A.SetNumber('n', 12345);
    A.SetFloat('f', 0.25);
    A.SetBoolean('b', True);
    A.SetPointer('p', @X);
    A.SetPointer('pc', Pointer(7), @R.Cleanup);
    B.SetString('s', 'old');
    B.SetNumber('keep', 1);
    A.CopyTo(B);
    Check((B.GetString('s') = 'str') and (B.GetNumber('n') = 12345) and (B.GetFloat('f') = 0.25)
      and B.GetBoolean('b') and (B.GetPointer('p') = @X), '値を写す（同じ名前は上書き）');
    Check(B.Has('keep') and (B.Count = 6), '写し先の他の値は残る');
    Check(not B.Has('pc'), '後始末付きのポインタは写さない（SDL と同じ）');
    Check(A.GetString('n') = '12345', '写し元で数を文字列として読む');
    A.Free;
    A := nil;
    Check(B.GetString('n') = '12345', '写し元を壊しても写し先の値は無事（SDL は置き場を共有して壊れる: D-54）');
    Check(Joined(R.Log) = 'cleanup 7', '写し元の後始末は写し元を壊したときに 1 度だけ');
    GProps := B;
    Check(Raises(@CopyToNil) and Raises(@CopyToSelf), 'nil や自分自身へは EPMLArgument');
  finally
    A.Free;
    B.Free;
  end;
  Check(Joined(R.Log) = 'cleanup 7', '写し先を壊しても写し元の後始末は呼ばない');
  R.Free;
end;

{ ---- 5. 列挙と排他 ---- }

type
  TCounter = class(TPMLThread)
  public
    Props: TPMLProperties;
  protected
    function Run: Integer; override;
  end;

const
  COUNT_LOOPS = 20000;

function TCounter.Run: Integer;
var
  I: Integer;
begin
  for I := 1 to COUNT_LOOPS do
  begin
    Props.Lock;
    try
      Props.SetNumber('count', Props.GetNumber('count') + 1);
    finally
      Props.Unlock;
    end;
  end;
  Result := 0;
end;

procedure TestEnumerateAndLock;
var
  P: TPMLProperties;
  R: TRecorder;
  T1, T2: TCounter;
begin
  WriteLn;
  WriteLn('5. 列挙と排他');
  R := TRecorder.Create('');
  P := TPMLProperties.Create;
  try
    P.SetNumber('zeta', 1);
    P.SetNumber('alpha', 2);
    P.SetNumber('mid', 3);
    P.SetNumber('alpha', 4);
    P.Enumerate(@R.Enum);
    Check(Joined(R.Log) = 'zeta | alpha | mid', '入れた順に呼ぶ（上書きは順序を変えない）');
    P.Lock;
    P.Lock;
    P.Unlock;
    P.Unlock;
    Check(True, 'Lock は重ねられる');
    T1 := TCounter.Create('count1', True);
    T2 := TCounter.Create('count2', True);
    T1.Props := P;
    T2.Props := P;
    T1.Start;
    T2.Start;
    T1.WaitFor;
    T2.WaitFor;
    T1.Free;
    T2.Free;
    Check(P.GetNumber('count') = 2 * COUNT_LOOPS, Format('2 スレッドで %d 回ずつ数えて失われない（%d）',
      [COUNT_LOOPS, P.GetNumber('count')]));
  finally
    P.Free;
    R.Free;
  end;
end;

{ ---- 6. ヒント ---- }

procedure SetHintEmpty;
begin
  GHints.SetHint('', 'x');
end;

procedure ResetHintEmpty;
begin
  GHints.ResetHint('');
end;

procedure AddCallbackEmpty;
begin
  GHints.AddCallback('', @GRec.Hint);
end;

procedure AddCallbackNil;
begin
  GHints.AddCallback('PAPIMELA_TEST_A', nil);
end;

procedure TestHints;
const
  A = 'PAPIMELA_TEST_A';
  B = 'PAPIMELA_TEST_B';
  C = 'PAPIMELA_TEST_C';
var
  H: TPMLHints;
  R1, R2, RB: TRecorder;
  V: String;
begin
  WriteLn;
  WriteLn('6. ヒント（期待値は SDL 3.4.2 の実測。D-57 は papimela が直した所）');
  unsetenv(A);
  unsetenv(B);
  unsetenv(C);
  H := TPMLHints.Create;
  R1 := TRecorder.Create('1');
  R2 := TRecorder.Create('2');
  RB := TRecorder.Create('B');
  try
    R1.Hints := H;
    H.AddCallback(A, @R1.Hint);
    H.AddCallback(A, @R2.Hint);
    Check((Joined(R1.Log) = '1 PAPIMELA_TEST_A: (unset) -> (unset)') and (Joined(R2.Log) = '2 PAPIMELA_TEST_A: (unset) -> (unset)'),
      '足したらすぐ今の値で呼ぶ');
    R1.Log.Clear;
    R2.Log.Clear;
    // 呼ばれた順を 1 本の並びで見るため、R2 の記録も R1 に流す
    R2.Log.Free;
    R2.Log := R1.Log;
    try
      Check(H.SetHint(A, 'x'), 'Normal で置ける');
      Check(Joined(R1.Log) = '2 PAPIMELA_TEST_A: (unset) -> x | 1 PAPIMELA_TEST_A: (unset) -> x',
        '新しく足した呼び出しから順に、前後の値で呼ぶ');
      R1.Log.Clear;
      Check(H.SetHint(A, 'x') and (R1.Log.Count = 0), '同じ値は True だが呼ばない');
      Check(not H.SetHint(A, 'y', TPMLHintPriority.Default) and (H.GetHint(A) = 'x') and (R1.Log.Count = 0),
        '置いてある優先度より低い Default は False');
      Check(H.SetHint(A, 'z', TPMLHintPriority.Override) and (Joined(R1.Log) =
        '2 PAPIMELA_TEST_A: x -> z | 1 PAPIMELA_TEST_A: x -> z'), 'Override で置き換わる');
      R1.Log.Clear;
      Check(not H.SetHint(A, 'w') and (H.GetHint(A) = 'z'), 'Override の後の Normal は False');
      Check(H.ResetHint(A) and (Joined(R1.Log) = '2 PAPIMELA_TEST_A: z -> (unset) | 1 PAPIMELA_TEST_A: z -> (unset)'),
        'ResetHint で置いた値が消え、呼ぶ');
      Check((H.GetHint(A) = '') and not H.TryGetHint(A, V), 'Reset の後は置かれていない');
      R1.Log.Clear;
      Check(H.SetHint(A, 'v'), 'Reset で優先度も Default に戻る（Normal で置ける）');
      Check(not H.ResetHint('PAPIMELA_TEST_NOSUCH'), '一度も置いていない名前の Reset は False');

      R1.Log.Clear;
      H.RemoveCallback(A, @R1.Hint);
      H.SetHint(A, 'u');
      Check(Joined(R1.Log) = '2 PAPIMELA_TEST_A: v -> u', 'RemoveCallback した呼び出しは呼ばない');
      R1.Log.Clear;
      H.AddCallback(A, @R1.Hint);
      H.AddCallback(A, @R1.Hint);
      R1.Log.Clear;
      H.SetHint(A, 't');
      Check(Joined(R1.Log) = '1 PAPIMELA_TEST_A: u -> t | 2 PAPIMELA_TEST_A: u -> t',
        '同じ呼び出しを 2 度足しても 1 つ（先に外してから先頭に足す）');
      // 呼び出しの中で、次に呼ばれるはずの呼び出しを外す（SDL は外した後の領域を辿る）
      R1.Log.Clear;
      R1.RemoveOther := @R2.Hint;
      H.SetHint(A, 's');
      Check(Joined(R1.Log) = '1 PAPIMELA_TEST_A: t -> s | 2 PAPIMELA_TEST_A: t -> s',
        '呼び出しの中で他の呼び出しを外しても、その回は写しの並びどおり呼ぶ');
      R1.Log.Clear;
      H.SetHint(A, 'r');
      Check(Joined(R1.Log) = '1 PAPIMELA_TEST_A: s -> r', '外した呼び出しは次の回から呼ばない');
    finally
      R2.Log := nil;
    end;

    // 環境変数
    setenv(B, 'env', 1);
    H.AddCallback(B, @RB.Hint);
    Check((Joined(RB.Log) = 'B PAPIMELA_TEST_B: env -> env') and (H.GetHint(B) = 'env'), '環境変数が効いている値になる');
    RB.Log.Clear;
    Check(not H.SetHint(B, 'n') and (H.GetHint(B) = 'env') and (RB.Log.Count = 0), '環境変数があると Normal は False');
    Check(H.ResetHint(B), '呼び出しのある名前の Reset は True');
    Check(RB.Log.Count = 0, '効いている値が変わらない Reset では呼ばない（SDL は (null) -> env で呼ぶ: D-57）');
    Check(H.SetHint(B, 'o', TPMLHintPriority.Override) and (H.GetHint(B) = 'o'), 'Override は環境変数より強い');
    Check(Joined(RB.Log) = 'B PAPIMELA_TEST_B: env -> o', '前の値は効いていた環境変数（SDL は (null) と知らせる: D-57）');
    RB.Log.Clear;
    H.ResetHint(B);
    Check((Joined(RB.Log) = 'B PAPIMELA_TEST_B: o -> env') and (H.GetHint(B) = 'env'), 'Reset で環境変数に戻る');
    RB.Log.Clear;
    H.SetHint(B, 'env', TPMLHintPriority.Override);
    Check(RB.Log.Count = 0, '環境変数と同じ値を Override で置いても、効いている値は変わらないので呼ばない（D-57）');
    unsetenv(B);
    H.ResetHint(B);
    Check(Joined(RB.Log) = 'B PAPIMELA_TEST_B: env -> (unset)', '環境変数を消してから Reset すると、置いた値から「無し」へ');

    setenv(C, '', 1);
    Check(H.TryGetHint(C, V) and (V = ''), '空の環境変数は「空の値」（置かれていないのではない）');
    Check(H.GetBoolean(C, True) and not H.GetBoolean(C, False), '空の値の真偽は既定値');
    unsetenv(C);
    Check(not H.TryGetHint(C, V) and H.GetBoolean(C, True), '置かれていない名前の真偽は既定値');
    H.SetHint(C, 'false');
    Check(not H.GetBoolean(C, True), '"false" は False');

    // ResetHints
    RB.Log.Clear;
    H.RemoveCallback(A, @R1.Hint);
    H.RemoveCallback(A, @R2.Hint);
    H.SetHint(B, 'b1');
    H.SetHint(C, 'c1');
    H.ResetHints;
    Check((H.GetHint(A) = '') and (H.GetHint(B) = '') and (H.GetHint(C) = ''), 'ResetHints で全部消える');
    Check(Joined(RB.Log) = 'B PAPIMELA_TEST_B: (unset) -> b1 | B PAPIMELA_TEST_B: b1 -> (unset)', 'ResetHints も呼ぶ');

    GHints := H;
    GRec := RB;
    Check(Raises(@SetHintEmpty) and Raises(@ResetHintEmpty) and Raises(@AddCallbackEmpty) and Raises(@AddCallbackNil),
      '空の名前や nil の呼び出しは EPMLArgument');
    Check(H.GetHint('') = '', '空の名前を読むと ''''');
    H.RemoveCallback('', @RB.Hint);
    Check(True, '空の名前の RemoveCallback は何もしない');
  finally
    H.Free;
    R1.Free;
    R2.Free;
    RB.Free;
  end;
end;

{ ---- 7. 文字列の真偽・整数 ---- }

procedure TestStringHelpers;
const
  // 型を付けないと 0.01 は Extended で比べられ、Double の 0.01 と一致しない
  HUNDREDTH: Double = 0.01;
begin
  WriteLn;
  WriteLn('7. PMLStringBoolean / PMLStringInteger');
  Check(PMLStringBoolean('', True) and not PMLStringBoolean('', False), '空は既定値');
  Check(not PMLStringBoolean('0', True) and not PMLStringBoolean('0abc', True)
    and not PMLStringBoolean('false', True) and not PMLStringBoolean('FaLsE', True), '"0…" と "false" は False');
  Check(PMLStringBoolean('no', False) and PMLStringBoolean('1', False) and PMLStringBoolean('falsey', False)
    and PMLStringBoolean(' 0', False), 'それ以外は True（"falsey" も、空白で始まる " 0" も）');
  Check((PMLStringInteger('', 7) = 7) and (PMLStringInteger('abc', 7) = 7) and (PMLStringInteger(' 5', 7) = 7),
    '空・数字でも "-" でもない始まりは既定値');
  Check((PMLStringInteger('false', 7) = 0) and (PMLStringInteger('TRUE', 7) = 1), '"false" は 0、"true" は 1');
  Check((PMLStringInteger('-5', 7) = -5) and (PMLStringInteger('12abc', 7) = 12) and (PMLStringInteger('-', 7) = 0),
    '"-" か数字で始まれば atoi（"-" だけなら 0）');
  Check((PMLStrToInt64C('0x7fffffffffffffff') = High(Int64)) and (PMLStrToInt64C('-0x8000000000000000') = Low(Int64))
    and (PMLStrToInt64C('0X1f') = 31) and (PMLStrToInt64C('-010') = -8) and (PMLStrToInt64C('0x1g') = 1),
    'strtoll の端（16 進の上限・下限、大文字の X、負の 8 進、途中で止まる）');
  Check((PMLStrToFloatC('0x1.8p1') = 3) and (PMLStrToFloatC('1e-2') = HUNDREDTH) and (PMLStrToFloatC('-.5e1') = -5)
    and (PMLStrToFloatC('infinityx') = Infinity) and (PMLStrToFloatC('+') = 0), 'strtod の端（16 進の小数と p 指数など）');
end;

begin
  WriteLn('test_properties — プロパティの表とヒント');
  WriteLn;
  TestBasics;
  TestConversions;
  TestCleanup;
  TestCopy;
  TestEnumerateAndLock;
  TestHints;
  TestStringHelpers;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: プロパティの表とヒントが SDL の約束と papimela の直した所どおりに動く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
