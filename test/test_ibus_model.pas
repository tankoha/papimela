{
  test_ibus_model — IBus バックエンドの、接続の要らない部分を検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    IBusText の書き込みと読み取りの往復（型名の検査を含む）、属性から文節を作る
    規則（spikes/spike3_ibus.pas で ibus-mozc から採った値をそのまま入れる）、
    アドレスファイルの探し方と中身の読み方、fcitx5 が IBus を装ったアドレスの
    見分け方、文字単位の周辺削除の換算。

  WHY:
    実機の IME（隔離環境の ibus-mozc）は特定の並びしか出さない。境目の重なり、
    隙間、範囲外、ERROR の下線のような並びはここで作って見る。CI でも走る
    （libdbus はメッセージの組み立てと読み取りにだけ使い、どこにも繋がない）。

  実行前提: libdbus-1（無ければ失敗にする。CI の Ubuntu には入っている）。
}
program test_ibus_model;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Platform.DBus,
  PaPiMeLa.TextInput.Backend,
  PaPiMeLa.TextInput.IBus;

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

function Attr(AType, AValue, AStart, AEnd: LongWord): TPMLIBusAttribute;
begin
  Result.AttrType := AType;
  Result.Value := AValue;
  Result.StartChar := AStart;
  Result.EndChar := AEnd;
end;

function MakeText(const S: String; const A: array of TPMLIBusAttribute): TPMLIBusText;
var
  I: Integer;
begin
  Result.Text := S;
  SetLength(Result.Attributes, Length(A));
  for I := 0 to High(A) do
    Result.Attributes[I] := A[I];
end;

const
  U = IBUS_ATTR_TYPE_UNDERLINE;
  FG = IBUS_ATTR_TYPE_FOREGROUND;
  BG = IBUS_ATTR_TYPE_BACKGROUND;
  SINGLE = IBUS_ATTR_UNDERLINE_SINGLE;
  DOUBLE = IBUS_ATTR_UNDERLINE_DOUBLE;

{ 文節を「開始-終了(バイト):状態」の並びにする。状態は u / c / F。 }
function Desc(const C: TPMLComposition): String;
var
  I: Integer;
  S: Char;
begin
  Result := '';
  for I := 0 to High(C.Segments) do
  begin
    case C.Segments[I].State of
      TPMLSegmentState.Unconverted: S := 'u';
      TPMLSegmentState.Converted:   S := 'c';
    else
      S := 'F';
    end;
    Result := Result + Format('%d-%d:%s ', [C.Segments[I].StartByte, C.Segments[I].EndByte, S]);
  end;
  Result := Trim(Result);
end;

{ 文節が隙間なく Text 全体を覆っているか（§7.4 の不変条件）。 }
function Covers(const C: TPMLComposition): Boolean;
var
  I, P: Integer;
begin
  P := 0;
  for I := 0 to High(C.Segments) do
  begin
    if C.Segments[I].StartByte <> P then
      Exit(False);
    if C.Segments[I].EndByte <= C.Segments[I].StartByte then
      Exit(False);
    P := C.Segments[I].EndByte;
  end;
  Result := P = Length(C.Text);
end;

procedure TestRoundTrip;
var
  Conn: TPMLDBusConnection;
  Msg: PDBusMessage;
  W, V, S, D, L, LD: TPMLDBusWriter;
  T, Back: TPMLIBusText;
  Ok: Boolean;
  Pass: Integer;
begin
  WriteLn('1. IBusText の往復');
  Conn := TPMLDBusConnection.CreateOffline;
  try
    T := MakeText('私の名前は', [Attr(U, DOUBLE, 0, 2), Attr(BG, $D1EAFF, 0, 2),
      Attr(FG, 0, 0, 2), Attr(U, SINGLE, 2, 5)]);
    Msg := Conn.BeginCall('a.b', '/a', 'a.b', 'M');
    try
      W := Conn.Writer(Msg);
      PMLWriteIBusText(W, T);
      W.AddUInt32(7);
      Ok := PMLReadIBusText(Conn.Reader(Msg), Back);
      Check(Ok, '書いたものを読める');
      Check(Back.Text = '私の名前は', '文字列が戻る');
      Check((Length(Back.Attributes) = 4) and (Back.Attributes[1].AttrType = BG)
        and (Back.Attributes[1].Value = $D1EAFF) and (Back.Attributes[3].StartChar = 2)
        and (Back.Attributes[3].EndChar = 5), '属性 4 つが型・値・範囲ごと戻る');
    finally
      Conn.Unref(Msg);
    end;

    T := MakeText('', []);
    Msg := Conn.BeginCall('a.b', '/a', 'a.b', 'M');
    try
      W := Conn.Writer(Msg);
      PMLWriteIBusText(W, T);
      Check(PMLReadIBusText(Conn.Reader(Msg), Back) and (Back.Text = '')
        and (Length(Back.Attributes) = 0), '空の文字列・属性なしも往復する');
    finally
      Conn.Unref(Msg);
    end;

    // 型名が違う variant は読まない（SDL_ibus.c の型名の比較の誤りを繰り返さない）。
    // 手で組み立て、型名以外は正しく書く（他が壊れていると、型名を見なくても断れてしまう）。
    // 同じ組み立てで型名を正しくすれば読めることも見て、落ちた理由が型名だと裏付ける。
    for Pass := 0 to 1 do
    begin
      Msg := Conn.BeginCall('a.b', '/a', 'a.b', 'M');
      try
        W := Conn.Writer(Msg);
        V := W.OpenVariant('(sa{sv}sv)');
        S := V.OpenStruct;
        if Pass = 0 then
          S.AddString('IBusTex')
        else
          S.AddString('IBusText');
        D := S.OpenArray('{sv}');
        S.Close(D);
        S.AddString('x');
        D := S.OpenVariant('(sa{sv}av)');
        L := D.OpenStruct;
        L.AddString('IBusAttrList');
        LD := L.OpenArray('{sv}');
        L.Close(LD);
        LD := L.OpenArray('v');
        L.Close(LD);
        D.Close(L);
        S.Close(D);
        V.Close(S);
        W.Close(V);
        if Pass = 0 then
          Check(not PMLReadIBusText(Conn.Reader(Msg), Back), '型名 "IBusTex" は断る')
        else
          Check(PMLReadIBusText(Conn.Reader(Msg), Back) and (Back.Text = 'x'),
            '同じ組み立てで型名が "IBusText" なら読める');
      finally
        Conn.Unref(Msg);
      end;
    end;

    Msg := Conn.BeginCall('a.b', '/a', 'a.b', 'M');
    try
      Conn.Writer(Msg).AddString('not a variant');
      Check(not PMLReadIBusText(Conn.Reader(Msg), Back), 'variant でなければ断る');
    finally
      Conn.Unref(Msg);
    end;
  finally
    Conn.Free;
  end;
  WriteLn;
end;

procedure TestSegments;
var
  C: TPMLComposition;
begin
  WriteLn('2. 文節の規則（ibus-mozc の実測値）');
  // 変換前の読み: 全体に SINGLE。
  C := TPMLIBusSegmenter.Build(MakeText('かんじ', [Attr(U, SINGLE, 0, 3)]), 3);
  Check(Desc(C) = '0-9:u', '読み「かんじ」は全体が未変換（' + Desc(C) + '）');
  Check((C.Segments[0].Underline = TPMLUnderlineStyle.Single) and (C.CursorByte = 9)
    and (C.CursorChar = 3), '下線 Single、カーソルは末尾（9 バイト = 3 文字）');
  Check(C.SegmentsReliable and (C.FocusedSegment = -1), '文節は信頼できる、注目文節は無い');

  // 変換後、1 文節。
  C := TPMLIBusSegmenter.Build(MakeText('感じ', [Attr(U, DOUBLE, 0, 2),
    Attr(BG, $D1EAFF, 0, 2), Attr(FG, 0, 0, 2)]), 0);
  Check((Desc(C) = '0-6:F') and (C.FocusedSegment = 0), '「感じ」は 1 つの注目文節');

  // 変換後、2 文節（注目が前）。
  C := TPMLIBusSegmenter.Build(MakeText('私の名前は', [Attr(U, DOUBLE, 0, 2),
    Attr(BG, $D1EAFF, 0, 2), Attr(FG, 0, 0, 2), Attr(U, SINGLE, 2, 5)]), 0);
  Check(Desc(C) = '0-6:F 6-15:c', '「私の|名前は」: 注目と変換済み（' + Desc(C) + '）');
  Check(C.FocusedSegment = 0, '注目文節は 0 番');

  // → で注目を後ろへ。
  C := TPMLIBusSegmenter.Build(MakeText('私の名前は', [Attr(U, SINGLE, 0, 2),
    Attr(U, DOUBLE, 2, 5), Attr(BG, $D1EAFF, 2, 5), Attr(FG, 0, 2, 5)]), 2);
  Check(Desc(C) = '0-6:c 6-15:F', '注目を移すと前が変換済み・後ろが注目（' + Desc(C) + '）');
  Check((C.FocusedSegment = 1) and (C.CursorByte = 6) and (C.CursorChar = 2),
    '注目文節は 1 番、カーソルは注目文節の先頭');
  Check((C.Segments[0].StartChar = 0) and (C.Segments[0].EndChar = 2)
    and (C.Segments[1].StartChar = 2) and (C.Segments[1].EndChar = 5), '文字位置も埋まる');
  WriteLn;

  WriteLn('3. 文節の規則（実測していない並び）');
  // Anthy 型: 全体に SINGLE、注目は背景だけで示す。
  C := TPMLIBusSegmenter.Build(MakeText('あいうえお', [Attr(U, SINGLE, 0, 5),
    Attr(BG, $FF, 0, 2)]), 0);
  Check(Desc(C) = '0-6:F 6-15:c', '全体 SINGLE + 背景 0..2 → 注目と変換済み（' + Desc(C) + '）');

  C := TPMLIBusSegmenter.Build(MakeText('あいう', []), 3);
  Check((Desc(C) = '0-9:u') and C.SegmentsReliable,
    '属性が無ければ全体が 1 つの未変換文節（文節の数は信頼できる）');

  // 隙間: 属性の無い区間は未変換で埋める。
  C := TPMLIBusSegmenter.Build(MakeText('あいうえお', [Attr(U, SINGLE, 0, 1),
    Attr(U, DOUBLE, 3, 5)]), 0);
  Check(Desc(C) = '0-3:c 3-9:u 9-15:F', '隙間は未変換で埋まる（' + Desc(C) + '）');
  Check(C.Segments[1].Underline = TPMLUnderlineStyle.None, '隙間の下線は None');

  // 範囲外と逆向きの属性。
  C := TPMLIBusSegmenter.Build(MakeText('あいう', [Attr(U, SINGLE, 1, 99),
    Attr(U, DOUBLE, 2, 1)]), 99);
  Check(Desc(C) = '0-3:u 3-9:u', '範囲外は切り詰め、逆向きは捨てる（' + Desc(C) + '）');
  Check(C.CursorByte = 9, '範囲外のカーソルは末尾');

  // ERROR は注目にしない。
  C := TPMLIBusSegmenter.Build(MakeText('abc', [Attr(U, IBUS_ATTR_UNDERLINE_ERROR, 0, 1),
    Attr(BG, 1, 0, 1), Attr(U, SINGLE, 1, 3)]), 0);
  Check((Desc(C) = '0-1:u 1-3:u') and (C.Segments[0].Underline = TPMLUnderlineStyle.Error),
    'ERROR は未変換（背景があっても注目にしない）（' + Desc(C) + '）');

  // 重なり: 境目が揃わない 2 つの下線は分割する。重なった所は強いほう。
  C := TPMLIBusSegmenter.Build(MakeText('abcd', [Attr(U, SINGLE, 0, 3),
    Attr(U, DOUBLE, 2, 4)]), 0);
  Check(Desc(C) = '0-2:c 2-3:F 3-4:F', '重なりは分割し、重なった区間は DOUBLE（' + Desc(C) + '）');

  // 前景色の境目では分けない。
  C := TPMLIBusSegmenter.Build(MakeText('abcd', [Attr(U, SINGLE, 0, 4), Attr(FG, 1, 1, 2)]), 0);
  Check(Desc(C) = '0-4:u', '前景色の境目では分けない');

  C := TPMLIBusSegmenter.Build(MakeText('', [Attr(U, SINGLE, 0, 1)]), 0);
  Check(C.IsEmpty and (Length(C.Segments) = 0), '空の文字列は空の変換中テキスト');

  Check(Covers(TPMLIBusSegmenter.Build(MakeText('あいうえお', [Attr(U, SINGLE, 1, 2),
    Attr(BG, 0, 3, 4), Attr(U, DOUBLE, 4, 5)]), 0)), '文節は隙間なく全体を覆う');
  WriteLn;
end;

procedure TestAddress;
var
  N: TStringArray;
  Addr: String;
  Pid: Integer;
begin
  WriteLn('4. アドレスファイル（ibus-daemon 1.5.29 の実測）');
  N := PMLIBusAddressFileCandidates('/c', 'm', 'wayland-0', ':0');
  Check((Length(N) = 2) and (N[0] = '/c/ibus/bus/m-unix-wayland-0') and (N[1] = '/c/ibus/bus/m-unix-0'),
    'Wayland と X の両方があれば unix-wayland-0 → unix-0');
  N := PMLIBusAddressFileCandidates('/c/', 'm', '', 'host:3.1');
  Check((Length(N) = 2) and (N[0] = '/c/ibus/bus/m-host-3') and (N[1] = '/c/ibus/bus/m-unix-0'),
    'DISPLAY=host:3.1 は host-3（画面番号は落とす）');
  N := PMLIBusAddressFileCandidates('/c', 'm', '', '');
  Check((Length(N) = 1) and (N[0] = '/c/ibus/bus/m-unix-0'), 'どちらも無ければ unix-0');

  Check(PMLIBusParseAddressFile('# This file is created by ibus-daemon'#10 +
    'IBUS_ADDRESS=unix:path=/tmp/cache/ibus/dbus-x,guid=1'#10'IBUS_DAEMON_PID=21679'#10, Addr, Pid)
    and (Addr = 'unix:path=/tmp/cache/ibus/dbus-x,guid=1') and (Pid = 21679),
    'IBUS_ADDRESS と IBUS_DAEMON_PID を読む');
  Check(not PMLIBusParseAddressFile('# only a comment'#10, Addr, Pid), 'アドレスが無ければ False');

  WriteLn;
  WriteLn('5. fcitx5 が IBus を装ったアドレス（手元の実物の値）');
  Check(PMLIBusIsFcitxEmulation(
    'unix:path=/run/user/1000/bus,fcitx_random_string=4bfdbf60afff4a66b46376360bd11775', ''),
    'アドレスに fcitx_random_string があれば fcitx5');
  Check(PMLIBusIsFcitxEmulation('unix:path=/run/user/1000/bus', 'fcitx5'#10),
    'デーモンのプロセス名が fcitx5 なら fcitx5');
  Check(not PMLIBusIsFcitxEmulation('unix:path=/tmp/cache/ibus/dbus-x,guid=1', 'ibus-daemon'#10),
    '本物の ibus-daemon は断らない');
  WriteLn;
end;

procedure TestDelete;
var
  D: TPMLDeleteSurroundingData;
begin
  WriteLn('6. 文字単位の周辺削除の換算（IBus と Fcitx で共有）');
  // ibus-mozc の再変換: 「漢字を」の「漢字」を選択（カーソル 2）→ (-2, 2)。
  D := PMLDeleteSurroundingFromChars('漢字を', 2, -2, 2);
  Check((D.BeforeChars = 2) and (D.BeforeBytes = 6) and (D.AfterChars = 0) and (D.AfterBytes = 0),
    '(-2, 2) はカーソルの前 2 文字 = 6 バイト');
  D := PMLDeleteSurroundingFromChars('aあb', 1, -1, 3);
  Check((D.BeforeChars = 1) and (D.BeforeBytes = 1) and (D.AfterChars = 2) and (D.AfterBytes = 4),
    'カーソルをまたぐ範囲は前後に分ける');
  D := PMLDeleteSurroundingFromChars('abc', 1, -5, 3);
  Check((D.BeforeChars = 0) and (D.AfterChars = 0), '先頭より前で終わる範囲は何も消さない');
  D := PMLDeleteSurroundingFromChars('abc', 1, -3, 9);
  Check((D.BeforeChars = 1) and (D.AfterChars = 2), 'テキストの外へはみ出す分は切り捨てる');
  D := PMLDeleteSurroundingFromChars('abcde', 3, -3, 1);
  Check((D.BeforeChars = 0) and (D.AfterChars = 0) and (D.BeforeBytes = 0),
    'カーソルに接していない範囲（先頭の 1 文字だけ）は消さない');
  D := PMLDeleteSurroundingFromChars('abcde', 3, 1, 1);
  Check((D.BeforeChars = 0) and (D.AfterChars = 0), 'カーソルの 1 文字先からの範囲も消さない');
  D := PMLDeleteSurroundingFromChars('abcde', 3, 0, 0);
  Check((D.BeforeChars = 0) and (D.AfterChars = 0), '長さ 0 は何も消さない');
  WriteLn;
end;

begin
  WriteLn('test_ibus_model — IBus バックエンドの接続の要らない部分');
  WriteLn;
  TestRoundTrip;
  TestSegments;
  TestAddress;
  TestDelete;
  if Failures = 0 then
    WriteLn('=== 結論: IBusText・文節の規則・アドレス・周辺削除が実測と設計どおりに動く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
