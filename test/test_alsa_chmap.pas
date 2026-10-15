{
  test_alsa_chmap — ALSA のチャンネルの並びの交渉（SDL の alsa_chmap_cfg の写し）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    偽の ALSA 関数（snd_pcm_query_chmaps / set_chmap / free_chmaps）に 36 の場面を与え、
    PMLAlsaNegotiateChannelMap の結果を、SDL の alsa_chmap_cfg を同じ偽の関数で動かした結果と比べる:
    戻り値（入れた / 次のチャンネル数 / 失敗）、snd_pcm_set_chmap を呼んだ回数と入れた並び、入れ替えの表。
    場面: 問い合わせが nil、ステレオの固定・対・VAR・逆順・重複・NA の詰め物、1〜8 チャンネル、6 チャンネルの
    後ろ・横・両方・どちらも無い、入れ替え、順番どおりの並びを入れ替えが要る並びより先に選ぶ、VAR、入れる失敗。
    また、問い合わせの結果を必ず 1 度解放する（SDL は成功した道で解放しない）。

  WHY:
    オーディオの残りの #58（Audio.Alsa）の受け入れ検査。この機械のハードウェアでは通らない道
    （入れ替え、6 チャンネル、VAR）を試す。ALSA の実物もハードウェアも要らない（CI で走る）。
    期待値は tools/alsa-parity/genchmap.bb が SDL のソースから関数を切り出して C で動かして作る。
}
program test_alsa_chmap;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, Classes, ctypes,
  PaPiMeLa.Errors,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Platform.Alsa,
  PaPiMeLa.Audio.Alsa;

{$I alsa_chmap_expected.inc}

var
  Failures: Integer = 0;
  // 偽の ALSA の状態
  FakeQueries: PPSndPcmChmapQuery = nil;
  FakeSetResult: Integer = 0;
  SetCalled: Integer = 0;
  FreeCalled: Integer = 0;
  SetPos: array[0..15] of cuint;
  SetN: Integer = 0;

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

function FakeQuery(APcm: PSndPcm): PPSndPcmChmapQuery; cdecl;
begin
  Result := FakeQueries;
end;

procedure FakeFree(AMaps: PPSndPcmChmapQuery); cdecl;
begin
  Inc(FreeCalled);
end;

function FakeSet(APcm: PSndPcm; AMap: PSndPcmChmap): cint; cdecl;
var
  I: Integer;
begin
  Inc(SetCalled);
  SetN := AMap^.Channels;
  for I := 0 to SetN - 1 do
    SetPos[I] := PMLAlsaChmapPos(AMap, I);
  Result := FakeSetResult;
end;

function FakeStrerror(AErr: cint): PChar; cdecl;
begin
  Result := 'fake error';
end;

{ 'type:pos,pos;type:pos,pos' から、NULL で終わる問い合わせの配列を作る。各問い合わせの後ろに
  0 の cuint を 4 つ置く（SDL の側と同じ）。 }
function BuildQueries(const AText: String; out AStorage: Pointer): PPSndPcmChmapQuery;
var
  Parts, PL: TStringList;
  I, J, Total: Integer;
  Q: PCUInt;
  Arr: PPSndPcmChmapQuery;
  Offsets: array of PtrInt;
  Body: String;
begin
  AStorage := nil;
  if AText = '-' then
    Exit(nil);
  Parts := TStringList.Create;
  PL := TStringList.Create;
  try
    Parts.Delimiter := ';';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := AText;
    Total := 0;
    Offsets := nil;
    SetLength(Offsets, Parts.Count);
    for I := 0 to Parts.Count - 1 do
    begin
      Offsets[I] := Total;
      Body := Copy(Parts[I], Pos(':', Parts[I]) + 1, MaxInt);
      PL.Clear;
      PL.Delimiter := ',';
      PL.StrictDelimiter := True;
      PL.DelimitedText := Body;
      Inc(Total, (2 + PL.Count + 4) * SizeOf(cuint));
    end;
    AStorage := GetMem(Total + (Parts.Count + 1) * SizeOf(Pointer));
    FillChar(AStorage^, Total + (Parts.Count + 1) * SizeOf(Pointer), 0);
    Arr := PPSndPcmChmapQuery(PtrUInt(AStorage) + PtrUInt(Total));
    for I := 0 to Parts.Count - 1 do
    begin
      Q := PCUInt(PtrUInt(AStorage) + PtrUInt(Offsets[I]));
      Q[0] := cuint(StrToInt(Copy(Parts[I], 1, Pos(':', Parts[I]) - 1)));
      Body := Copy(Parts[I], Pos(':', Parts[I]) + 1, MaxInt);
      PL.Clear;
      PL.Delimiter := ',';
      PL.StrictDelimiter := True;
      PL.DelimitedText := Body;
      Q[1] := cuint(PL.Count);
      for J := 0 to PL.Count - 1 do
        Q[2 + J] := cuint(StrToInt(PL[J]));
      Arr[I] := PSndPcmChmapQuery(Q);
    end;
    Result := Arr;
  finally
    PL.Free;
    Parts.Free;
  end;
end;

procedure RunCase(const C: TChmapCase);
var
  API: TPMLAlsaAPI;
  Storage: Pointer;
  Swizzle: TPMLChannelMap;
  Installed: TPMLAlsaPositions;
  Outcome: TPMLAlsaChmapOutcome;
  Raised: Boolean;
  Msg: String;
  I: Integer;
  SameInstalled, SameSwizzle: Boolean;
  WantStatus: Integer;
  Got: String;
begin
  FillChar(API, SizeOf(API), 0);
  API.pcm_query_chmaps := @FakeQuery;
  API.pcm_free_chmaps := @FakeFree;
  API.pcm_set_chmap := @FakeSet;
  API.strerror := @FakeStrerror;

  FakeQueries := BuildQueries(C.Queries, Storage);
  FakeSetResult := C.SetResult;
  SetCalled := 0;
  FreeCalled := 0;
  SetN := 0;
  FillChar(SetPos, SizeOf(SetPos), 0);
  Swizzle := nil;
  FillChar(Installed, SizeOf(Installed), 0);
  Raised := False;
  Msg := '';
  Outcome := TPMLAlsaChmapOutcome.Installed;
  try
    Outcome := PMLAlsaNegotiateChannelMap(API, nil, C.Chans, Swizzle, Installed);
  except
    on E: EPMLAudioError do
    begin
      Raised := True;
      Msg := E.Message;
    end;
  end;

  // 戻り値
  if C.Status < 0 then
  begin
    Check(Raised and (Msg = 'ALSA: failed to install channel map: fake error'),
      C.Name + ': 入れるのに失敗して例外（' + Msg + '）');
  end
  else
  begin
    WantStatus := C.Status;
    if Raised then
      Got := '例外 ' + Msg
    else if Outcome = TPMLAlsaChmapOutcome.Installed then
      Got := '入れた'
    else
      Got := '次のチャンネル数';
    Check((not Raised) and ((Outcome = TPMLAlsaChmapOutcome.Installed) = (WantStatus = 0)),
      Format('%s: 戻り値 %d（%s）', [C.Name, WantStatus, Got]));
  end;
  // set_chmap の回数と入れた並び
  SameInstalled := (SetCalled = C.SetCalled) and (SetN = Length(C.Installed));
  if SameInstalled then
    for I := 0 to High(C.Installed) do
      if Integer(SetPos[I]) <> C.Installed[I] then
        SameInstalled := False;
  Check(SameInstalled, Format('%s: snd_pcm_set_chmap %d 回、入れた並び %d 個', [C.Name, C.SetCalled, Length(C.Installed)]));
  // 入れ替えの表
  if C.Status < 0 then
    SameSwizzle := True
  else
  begin
    SameSwizzle := Length(Swizzle) = Length(C.Swizzle);
    if SameSwizzle then
      for I := 0 to High(C.Swizzle) do
        if Swizzle[I] <> C.Swizzle[I] then
          SameSwizzle := False;
  end;
  Check(SameSwizzle, Format('%s: 入れ替えの表 %d 個', [C.Name, Length(C.Swizzle)]));
  // 問い合わせの結果は、nil でなければ必ず 1 度解放する（SDL は成功した道で解放しない）
  if FakeQueries = nil then
    Check(FreeCalled = 0, C.Name + ': nil の問い合わせは解放しない')
  else
    Check(FreeCalled = 1, Format('%s: 問い合わせの結果を 1 度解放する（%d）', [C.Name, FreeCalled]));
  if Storage <> nil then
    FreeMem(Storage);
end;

var
  I: Integer;

begin
  WriteLn('=== test_alsa_chmap ===');
  for I := 0 to High(ChmapCases) do
    RunCase(ChmapCases[I]);
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: チャンネルの並びの交渉が SDL の alsa_chmap_cfg と同じ結果になる ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
