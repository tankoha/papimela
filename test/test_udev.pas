{
  test_udev — libudev による入力機器の列挙（PaPiMeLa.Platform.Udev）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    今ある機器に対する不変条件を見る（機器の中身は環境で違うので、SDL の記録とは比べない。SDL の参照版は
    libudev のヘッダが無い環境では udev を使わない作りになる）:
      - libudev が無ければ、それが分かる（EPMLPlatformLibrary）。CI の環境にあれば以下を行う
      - Scan が、機器ファイル（/dev/…）のパスと 0 でない種類で、足された通知を出す
      - 通知の順番は、2 回の Scan で同じ
      - /dev/input/event* の通知は、GetProductInfo が同じ種類を返す（権限が無くても stat と udev だけで引ける）
      - 何も溜まっていないときの Poll はすぐ戻る。コールバックを外すと通知が止まる
    機器の種類は、ID_INPUT_xxx が無い機器のために /sys の capabilities から決める部分（PMLUdevParseCaps と
    PMLEvdevGuessDeviceClass）を test_evdev が見ている。
}
program test_udev;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, Classes,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.Evdev,
  PaPiMeLa.Platform.Udev;

type
  TRecorder = class
  public
    Lines: TStringList;
    procedure OnDevice(AEvent: TPMLUdevDeviceEvent; AClass: Integer; const APath: String);
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

procedure TRecorder.OnDevice(AEvent: TPMLUdevDeviceEvent; AClass: Integer; const APath: String);
begin
  Lines.Add(Format('%d %d %s', [Ord(AEvent), AClass, APath]));
end;

procedure Run;
var
  U: TPMLUdev;
  R1, R2: TRecorder;
  I, Eq, Added, Bad: Integer;
  ID: TPMLInputID;
  Cl: Integer;
  Driver, Path: String;
  Parts: TStringList;
  AllDev, AllClass: Boolean;
  T0: QWord;
begin
  if not TPMLUdev.IsAvailable then
  begin
    WriteLn('libudev が無い環境: 飛ばす');
    Check(True, 'libudev が無い');
    Exit;
  end;
  U := TPMLUdev.Create;
  R1 := TRecorder.Create;
  R2 := TRecorder.Create;
  Parts := TStringList.Create;
  try
    R1.Lines := TStringList.Create;
    R2.Lines := TStringList.Create;
    U.AddCallback(@R1.OnDevice);
    U.Scan;
    Added := R1.Lines.Count;
    WriteLn(Format('  （足された通知 %d 件）', [Added]));
    AllDev := True;
    AllClass := True;
    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := True;
    for I := 0 to Added - 1 do
    begin
      Parts.DelimitedText := R1.Lines[I];
      if Copy(Parts[2], 1, 5) <> '/dev/' then
        AllDev := False;
      if (Parts[0] <> '0') or (StrToInt(Parts[1]) = 0) then
        AllClass := False;
    end;
    Check(AllDev, '通知のパスは機器ファイル');
    Check(AllClass, '足された通知の種類は 0 でない');

    U.AddCallback(@R2.OnDevice);
    U.Scan;
    Check(R2.Lines.Count = Added, '2 回目の Scan は同じ数の通知（コールバック 2 つぶん）');

    Eq := 0;
    Bad := 0;
    for I := 0 to Added - 1 do
    begin
      Parts.DelimitedText := R1.Lines[I];
      Path := Parts[2];
      if Copy(Path, 1, 16) = '/dev/input/event' then
      begin
        FillChar(ID, SizeOf(ID), 0);
        Cl := 0;
        if U.GetProductInfo(Path, ID, Cl, Driver) and (Cl = StrToInt(Parts[1])) then
          Inc(Eq)
        else
          begin
            WriteLn('    食い違い: ', R1.Lines[I], ' → ', Cl);
            Inc(Bad);
          end;
      end;
    end;
    Check(Bad = 0, Format('input の機器 %d 台は GetProductInfo の種類が通知と同じ', [Eq]));

    FillChar(ID, SizeOf(ID), 0);
    Cl := 0;
    Check(not U.GetProductInfo('/dev/null-no-such-node', ID, Cl, Driver), '無い機器ファイルは False');
    Check(not U.GetProductInfo('/etc/passwd', ID, Cl, Driver), '機器ファイルでないものは False');
    Check(U.GetProductSerial('/etc/passwd') = '', '機器ファイルでないもののシリアルは空');

    T0 := GetTickCount64;
    U.Poll;
    Check(GetTickCount64 - T0 < 500, '何も溜まっていない Poll はすぐ戻る');

    U.DelCallback(@R2.OnDevice);
    R1.Lines.Clear;
    R2.Lines.Clear;
    U.Scan;
    Check((R1.Lines.Count = Added) and (R2.Lines.Count = 0), 'コールバックを外すと通知が止まる');
  finally
    Parts.Free;
    R1.Lines.Free;
    R2.Lines.Free;
    R1.Free;
    R2.Free;
    U.Free;
  end;
end;

begin
  WriteLn('=== test_udev ===');
  Run;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: libudev の列挙と問い合わせが機器に対して矛盾しない ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
