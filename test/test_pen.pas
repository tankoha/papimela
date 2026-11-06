{
  test_pen — ペンの状態機械（Ctx.Events.Pen。PaPiMeLa.Events.Pen）を SDL_pen.c の実物と突き合わせる（T-87）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    検査がバックエンドの役（偽の機器）をして、TPMLPenState の窓口を叩く。手順と期待値は
    test/test_pen_cases.inc（tools/pen-expect/gen.bb が参照版の SDL の SDL_pen.c に同じ手順を通して作る）。
    手順ごとに、出たイベント（ペン・合成したマウスとタッチ）と問い合わせの答えを並び順に比べる。場面:
      register   登録と ID・FindByHandle・GetDeviceType・GetStatus、知らない ID、外す（近接 out）
      proximity  近接の in / out（同じなら出さない）、即時と保留、Pump の保留の出し方・取り消し、
                 窓が消えた保留、近接 out で押下中のボタンを離す
      touch      触れる・離す・消しゴムの切り替え、移動（同じ座標は出さない）、7 軸、ボタン 1〜5 と範囲の外
      two_pens   2 本のペン。触れている 1 本だけがマウスとタッチを出す。RemoveAll
      hints      PAPIMELA_PEN_MOUSE_EVENTS / PAPIMELA_PEN_TOUCH_EVENTS の 4 通り、窓 0 では合成しない
      disabled   SetEnabled でペンのイベントを切ったときの合成（SDL は種類ごとに違う）
    papimela の座標は窓の座標のまま（SDL のタッチの正規化を、期待値の側で戻してある）。

  WHY:
    ペンの規則は「変わったときだけ出す」「どのペンが触れているか」「保留した近接 out」の組み合わせで、
    読みから手で期待値を作ると取りこぼす。SDL の実物に同じ手順を通した結果を正とする。

  実行前提: 無し（表示サーバも機器も要らない）。
  検査を先に書いた。骨組み（空の実装）で落ちることを確かめてから実装する（docs/TEST-LOG.md の T-87）。
}
program test_pen;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  cthreads,
  SysUtils, Classes, TypInfo,
  PaPiMeLa.Types,
  PaPiMeLa.Properties,
  PaPiMeLa.Events,
  PaPiMeLa.Core;

{$I test_pen_cases.inc}
{$I pen_expect.inc}

const
  MaxPens = 16;

type
  { 偽のバックエンドの持ち物: ペンの番号 → ID、消した窓、RemoveAll の知らせ。 }
  TFakeBackend = class
  public
    PenIDs   : array[0..MaxPens - 1] of TPMLPenID;
    Handles  : array[0..MaxPens - 1] of Byte;   // 番号ごとの Handle（番地が違えばよい）
    Destroyed: array[0..2] of Boolean;
    Other    : TStringList;                     // R / C の行
    constructor Create;
    destructor Destroy; override;
    function  HandleOf(ASlot: Integer): Pointer;
    function  SlotOfHandle(AHandle: Pointer): Integer;
    function  WindowExists(AWindowID: TPMLWindowID): Boolean;
    procedure Removed(AID: TPMLPenID; AHandle: Pointer);
  end;

var
  Backend: TFakeBackend;

constructor TFakeBackend.Create;
begin
  inherited Create;
  Other := TStringList.Create;
end;

destructor TFakeBackend.Destroy;
begin
  Other.Free;
  inherited Destroy;
end;

function TFakeBackend.HandleOf(ASlot: Integer): Pointer;
begin
  Result := @Handles[ASlot];
end;

function TFakeBackend.SlotOfHandle(AHandle: Pointer): Integer;
var
  I: Integer;
begin
  for I := 0 to MaxPens - 1 do
    if AHandle = @Handles[I] then
      Exit(I);
  Result := -1;
end;

function TFakeBackend.WindowExists(AWindowID: TPMLWindowID): Boolean;
begin
  Result := not ((AWindowID <= 2) and Destroyed[AWindowID]);
end;

procedure TFakeBackend.Removed(AID: TPMLPenID; AHandle: Pointer);
begin
  Other.Add(Format('R removed %d %d', [SlotOfPen(AID), SlotOfHandle(AHandle)]));
end;

function SlotOfPen(AID: TPMLPenID): Integer;
var
  I: Integer;
begin
  if AID = 0 then
    Exit(0);
  for I := 1 to MaxPens - 1 do
    if Backend.PenIDs[I] = AID then
      Exit(I);
  Result := 99;
end;

function PenOf(ASlot: Integer): TPMLPenID;
begin
  if (ASlot >= 1) and (ASlot < MaxPens) then
    Result := Backend.PenIDs[ASlot]
  else
    Result := 0;
end;

function CapsOf(AMask: LongWord): TPMLPenCapabilities;
var
  C: TPMLPenCapability;
begin
  Result := [];
  for C := Low(TPMLPenCapability) to High(TPMLPenCapability) do
    if (AMask and (LongWord(1) shl Ord(C))) <> 0 then
      Include(Result, C);
end;

{ 1 つの手順を行う。AExpected は status の答えを値で比べるのに使う。 }
procedure RunStep(Ctx: TPMLContext; const AStep: String; const AExpected: TStringArray);
var
  T: TStringArray;
  Op: String;
  Info: TPMLPenInfo;
  P: Integer;
  Axes: TPMLPenAxes;
  Flags: TPMLPenInputFlags;
  Kind: Integer;
  V: String;
begin
  T := Tokens(AStep);
  Op := Tok(T, 0);
  P := TokInt(T, 1);
  if Op = 'add' then
  begin
    FillChar(Info, SizeOf(Info), 0);
    Info.Subtype := TPMLPenSubtype(TokInt(T, 4));
    Info.DeviceType := TPMLPenDeviceType(TokInt(T, 5) + 1);   // SDL の INVALID = -1 から
    Info.Capabilities := CapsOf(TokInt(T, 6));
    Info.MaxTilt := TokSingle(T, 7);
    Info.WacomID := TokInt(T, 8);
    Info.NumButtons := TokInt(T, 9);
    Backend.PenIDs[P] := Ctx.Events.Pen.AddDevice('pen', TokInt(T, 3), Info,
      Backend.HandleOf(P), TokInt(T, 2) <> 0);
  end
  else if Op = 'remove' then
    Ctx.Events.Pen.RemoveDevice(TokInt(T, 2), PenOf(P))
  else if Op = 'removeall' then
    Ctx.Events.Pen.RemoveAll(@Backend.Removed)
  else if Op = 'touch' then
    Ctx.Events.Pen.SendTouch(PenOf(P), TokInt(T, 2), TokInt(T, 3) <> 0, TokInt(T, 4) <> 0)
  else if Op = 'motion' then
    Ctx.Events.Pen.SendMotion(PenOf(P), TokInt(T, 2), TokSingle(T, 3), TokSingle(T, 4))
  else if Op = 'axis' then
    Ctx.Events.Pen.SendAxis(PenOf(P), TokInt(T, 2), TPMLPenAxis(TokInt(T, 3)), TokSingle(T, 4))
  else if Op = 'button' then
    Ctx.Events.Pen.SendButton(PenOf(P), TokInt(T, 2), Byte(TokInt(T, 3)), TokInt(T, 4) <> 0)
  else if Op = 'prox' then
    Ctx.Events.Pen.SendProximity(PenOf(P), TokInt(T, 2), TokInt(T, 3) <> 0, TokInt(T, 4) <> 0)
  else if Op = 'pending' then
    Ctx.Events.Pen.SendPendingProximity
  else if Op = 'hint' then
  begin
    if TokInt(T, 2) <> 0 then V := '1' else V := '0';
    if Tok(T, 1) = 'mouse' then
      Ctx.Hints.SetHint(PML_HINT_PEN_MOUSE_EVENTS, V)
    else
      Ctx.Hints.SetHint(PML_HINT_PEN_TOUCH_EVENTS, V);
  end
  else if Op = 'enable' then
  begin
    Kind := GetEnumValue(TypeInfo(TPMLEventKind), Tok(T, 1));
    Ctx.Events.SetEnabled(TPMLEventKind(Kind), TokInt(T, 2) <> 0);
  end
  else if Op = 'destroywin' then
    Backend.Destroyed[P] := True
  else if Op = 'status' then
  begin
    Flags := Ctx.Events.Pen.GetStatus(PenOf(P), Axes);
    Backend.Other.Add(StatusLine(AExpected, P, Flags, Axes));
  end
  else if Op = 'devtype' then
    Backend.Other.Add(Format('R devtype %d %d', [P, Ord(Ctx.Events.Pen.GetDeviceType(PenOf(P))) - 1]))
  else if Op = 'find' then
    Backend.Other.Add(Format('R find %d %d', [P, SlotOfPen(Ctx.Events.Pen.FindByHandle(Backend.HandleOf(P)))]))
  else
    Check(False, '知らない手順: ' + AStep);
end;

procedure RunCases;
var
  I, J: Integer;
  Ctx: TPMLContext;
  Rec: TPenRecorder;
  Scene, Step: String;
  Expected: TStringArray;
begin
  Ctx := nil;
  Rec := TPenRecorder.Create;
  try
    I := 0;
    while I <= High(PenCases) do
    begin
      if Copy(PenCases[I], 1, 2) = 'N ' then
      begin
        // 場面ごとに Context を作り直す（SDL 側も初期化し直している）。
        if Ctx <> nil then
        begin
          Ctx.Events.RemoveWatch(Rec);
          FreeAndNil(Ctx);
        end;
        FreeAndNil(Backend);
        Backend := TFakeBackend.Create;
        Scene := Copy(PenCases[I], 3, MaxInt);
        WriteLn(Scene);
        Ctx := TPMLContext.Create([]);
        Ctx.Events.Pen.WindowExists := @Backend.WindowExists;
        Ctx.Events.AddWatch(Rec);
        Inc(I);
        Continue;
      end;
      Step := Copy(PenCases[I], 3, MaxInt);
      Expected := nil;
      J := I + 1;
      while (J <= High(PenCases)) and (Copy(PenCases[J], 1, 2) <> 'S ')
        and (Copy(PenCases[J], 1, 2) <> 'N ') do
      begin
        SetLength(Expected, Length(Expected) + 1);
        Expected[High(Expected)] := PenCases[J];
        Inc(J);
      end;
      Rec.Clear;
      Backend.Other.Clear;
      RunStep(Ctx, Step, Expected);
      CompareStep(Scene, Step, Expected, Rec.Events, Backend.Other);
      Ctx.Events.FlushAll;
      I := J;
    end;
  finally
    if Ctx <> nil then
    begin
      Ctx.Events.RemoveWatch(Rec);
      Ctx.Free;
    end;
    Rec.Free;
    FreeAndNil(Backend);
  end;
end;

{ 期待値の表に無い、papimela の窓口だけの確かめ。 }
procedure TestFacade;
var
  Ctx: TPMLContext;
  Info: TPMLPenInfo;
  A, B: TPMLPenID;
  H1, H2: Byte;
begin
  WriteLn('facade');
  Ctx := TPMLContext.Create([]);
  try
    FillChar(Info, SizeOf(Info), 0);
    Info.Subtype := TPMLPenSubtype.Pen;
    Check(Ctx.Events.Pen.Count = 0, '初めはペンが無い');
    A := Ctx.Events.Pen.AddDevice('', 0, Info, @H1, False);
    B := Ctx.Events.Pen.AddDevice('b', 0, Info, @H2, False);
    Check((A <> 0) and (B <> 0) and (A <> B), 'ID は 0 でなく、ペンごとに違う');
    Check(Ctx.Events.Pen.Count = 2, '2 本つながっている');
    Ctx.Events.Pen.RemoveDevice(0, A);
    Check(Ctx.Events.Pen.Count = 1, '外すと 1 本');
    Check(Ctx.Events.Pen.FindByHandle(@H2) = B, '残ったペンは Handle で引ける');
    Ctx.Events.Pen.RemoveAll(nil);
    Check(Ctx.Events.Pen.Count = 0, 'RemoveAll（呼び出し先 nil）で全部外れる');
    // Pump は保留の近接 out を出す（SDL_PumpEventMaintenance）。
    A := Ctx.Events.Pen.AddDevice('c', 1, Info, @H1, True);
    Ctx.Events.FlushAll;
    Ctx.Events.Pen.SendProximity(A, 1, False, False);
    Check(not Ctx.Events.Peek(TPMLEventKind.PenProximityOut), '保留の近接 out はすぐには出ない');
    Ctx.Events.Pump(0);
    Check(Ctx.Events.Peek(TPMLEventKind.PenProximityOut), 'Pump で保留の近接 out が出る');
  finally
    Ctx.Free;
  end;
end;

begin
  CaseFmt := DefaultFormatSettings;
  CaseFmt.DecimalSeparator := '.';
  WriteLn('=== test_pen ===');
  RunCases;
  CheckStepCount(158);
  TestFacade;
  WriteLn;
  WriteLn(Format('PASS %d / FAIL %d', [Passes, Failures]));
  if Failures = 0 then
    WriteLn('=== 結論: ペンの状態機械が SDL_pen.c と同じイベントを出す ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
