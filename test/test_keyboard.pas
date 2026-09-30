{
  test_keyboard — スキャンコード、キーコード、キーマップ、押下状態

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 既定（US 配列）のスキャンコード ↔ キーコード
    2. スキャンコードとキーの名前、名前からの逆引き
    3. キーシム → Unicode（上流の不具合 D-36 の範囲で落ちないこと）
    4. 押下状態の規則（リピート、押されていないキーの KeyUp、フォーカス喪失）
    5. 合成したキーマップ（AZERTY 型、ロシア語型）でのキーイベントのキーコード
    6. **実際の配列**（us / fr / de / ru）を xkbcommon で読み込んで作ったキーマップ

  WHY:
    Pong を書いて分かった不足（examples/README.md の F-1〜F-3）を埋めた部分の検査。
    6 はコンポジタを要らない。xkbcommon は配列の名前からキーマップを作れるので、
    手元に無い配列（フランス語、ドイツ語、ロシア語）の振る舞いも見られる。
    xkbcommon か配列のデータ（xkeyboard-config）が無い環境では 6 を飛ばす。

  実行前提: 無し（6 は libxkbcommon と xkeyboard-config があれば行う）。
}
program test_keyboard;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Events,
  PaPiMeLa.Keycodes,
  PaPiMeLa.Events.Keymap,
  PaPiMeLa.Platform.XKB,
  PaPiMeLa.Core;

var
  Failures: Integer = 0;
  Ctx: TPMLContext;

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

function Hex(AValue: LongWord): String;
begin
  Result := '$' + IntToHex(AValue, 1);
end;

{ ---- 4 で使う: キーを流してイベントを集める ---- }

type
  TSeen = record
    Kind    : TPMLEventKind;
    Scancode: TPMLScancode;
    Key     : TPMLKeycode;
    IsRepeat: Boolean;
  end;

var
  Seen: array of TSeen;

procedure Drain;
var
  Ev: TPMLEvent;
begin
  SetLength(Seen, 0);
  while Ctx.Events.Poll(Ev) do
  begin
    SetLength(Seen, Length(Seen) + 1);
    Seen[High(Seen)].Kind := Ev.Kind;
    if Ev.Kind in [TPMLEventKind.KeyDown, TPMLEventKind.KeyUp] then
    begin
      Seen[High(Seen)].Scancode := Ev.Key.Scancode;
      Seen[High(Seen)].Key := Ev.Key.Key;
      Seen[High(Seen)].IsRepeat := Ev.Key.IsRepeat;
    end;
  end;
end;

procedure Send(AScancode: TPMLScancode; ADown: Boolean);
var
  K: TPMLKeyEventData;
begin
  FillChar(K, SizeOf(K), 0);
  K.Scancode := AScancode;
  Ctx.Events.Keyboard.SendKey(1, K, ADown, '');
end;

{ ---- 5 で使う: 合成キーマップ ---- }

function FrenchLike: TPMLKeymap;
const
  // AZERTY の数字の段。修飾なしは記号、Shift で数字。
  Row: array[0..9] of LongWord = ($26, $E9, $22, $27, $28, $2D, $E8, $5F, $E7, $E0);
var
  I: Integer;
begin
  Result := TPMLKeymap.Create;
  Result.SetEntry(TPMLScancode.Q, False, Ord('a'));
  Result.SetEntry(TPMLScancode.Q, True, Ord('A'));
  Result.SetEntry(TPMLScancode.A, False, Ord('q'));
  Result.SetEntry(TPMLScancode.A, True, Ord('Q'));
  for I := 0 to 9 do
  begin
    Result.SetEntry(TPMLScancode(Ord(TPMLScancode.Digit1) + I), False, Row[I]);
    Result.SetEntry(TPMLScancode(Ord(TPMLScancode.Digit1) + I), True,
      Ord('0') + ((I + 1) mod 10));
  end;
end;

function RussianLike: TPMLKeymap;
begin
  Result := TPMLKeymap.Create;
  Result.SetEntry(TPMLScancode.A, False, $0444);   // ф
  Result.SetEntry(TPMLScancode.B, False, $0438);   // и
  Result.SetEntry(TPMLScancode.C, False, $0441);   // с
  Result.SetEntry(TPMLScancode.D, False, $0432);   // в
end;

{ ---- 6 ---- }

procedure CheckRealLayouts;
var
  X: TPMLXKBState;
  M: TPMLKeymap;
  Shifted: Boolean;

  function Load(const ALayout: String): Boolean;
  begin
    Result := X.LoadKeymapFromNames(ALayout);
    if not Result then
      WriteLn('  [SKIP] 配列 "', ALayout, '" を読み込めない（xkeyboard-config が無い？）');
  end;

begin
  if not PMLXKBLoad then
  begin
    WriteLn('  [SKIP] libxkbcommon が無いので実際の配列は検査しない');
    Exit;
  end;
  X := TPMLXKBState.Create;
  try
    if Load('us') then
    begin
      M := X.BuildKeymap;
      try
        M.DetectLayout;
        Check(M.KeyForEvent(TPMLScancode.W) = PMLK_W, 'us: W の位置は w');
        Check(M.KeyForEvent(TPMLScancode.Digit1) = PMLK_1, 'us: 数字の段は数字');
        Check(M.KeyFromScancode(TPMLScancode.Digit1, True) = PMLK_EXCLAIM, 'us: Shift+1 は !');
        Check(M.LatinLetters and not M.FrenchNumbers, 'us: ラテン文字、AZERTY 型ではない');
        Check(M.KeyForEvent(TPMLScancode.RETURN) = PMLK_RETURN, 'us: Return');
        Check(M.KeyForEvent(TPMLScancode.UP) = PMLK_UP, 'us: 上矢印');
        Check(M.KeyForEvent(TPMLScancode.F1) = PMLK_F1, 'us: F1');
        Check(M.KeyForEvent(TPMLScancode.LSHIFT) = PMLK_LSHIFT, 'us: 左 Shift');
        Check(M.KeyForEvent(TPMLScancode.KP_1) = PMLK_KP_1,
          'us: テンキーの 1 は KP_1（文字の 1 ではない）');
        Check(M.KeyName(PMLK_W) = 'W', 'us: w のキーの名前は W');
      finally
        M.Free;
      end;
    end;

    if Load('fr') then
    begin
      M := X.BuildKeymap;
      try
        M.DetectLayout;
        Check(M.KeyForEvent(TPMLScancode.Q) = PMLK_A, 'fr: Q の位置は a');
        Check(M.KeyForEvent(TPMLScancode.A) = PMLK_Q, 'fr: A の位置は q');
        Check(M.KeyForEvent(TPMLScancode.W) = PMLK_Z, 'fr: W の位置は z');
        Check(M.FrenchNumbers, 'fr: AZERTY 型と判定される');
        Check(M.KeyFromScancode(TPMLScancode.Digit1, False) = PMLK_AMPERSAND,
          'fr: 数字の段の修飾なしは &');
        Check(M.KeyForEvent(TPMLScancode.Digit1) = PMLK_1,
          'fr: キーイベントでは数字の段が数字になる（french_numbers）');
        Check(M.KeyForEvent(TPMLScancode.Digit1, []) = PMLK_AMPERSAND,
          'fr: french_numbers を外せば & のまま');
        Check(M.ScancodeFromKey(PMLK_A, Shifted) = TPMLScancode.Q,
          'fr: a を打つキーは Q の位置');
        Check(M.KeyName(PMLK_A) = 'A', 'fr: a のキーの名前は A');
      finally
        M.Free;
      end;
    end;

    if Load('de') then
    begin
      M := X.BuildKeymap;
      try
        M.DetectLayout;
        Check(M.KeyForEvent(TPMLScancode.Y) = PMLK_Z, 'de: Y の位置は z');
        Check(M.KeyForEvent(TPMLScancode.Z) = PMLK_Y, 'de: Z の位置は y');
        Check(not M.FrenchNumbers, 'de: AZERTY 型ではない');
      finally
        M.Free;
      end;
    end;

    if Load('ru') then
    begin
      M := X.BuildKeymap;
      try
        M.DetectLayout;
        Check(M.KeyFromScancode(TPMLScancode.A, False) = $0444,
          'ru: A の位置の文字は ф（U+0444）');
        Check(not M.LatinLetters, 'ru: ラテン文字の配列ではないと判定される');
        Check(M.KeyForEvent(TPMLScancode.A) = PMLK_A,
          'ru: キーイベントでは US 配列の a になる（latin_letters）');
        Check(M.KeyForEvent(TPMLScancode.A, []) = $0444,
          'ru: latin_letters を外せば ф');
      finally
        M.Free;
      end;
    end;
  finally
    X.Free;
    PMLXKBUnload;
  end;
end;

var
  Shifted: Boolean;
  I: Integer;
  AllMatch, Released: Boolean;
  K: TPMLKeyEventData;
  S: TPMLScancode;
  Plain: TPMLKeymap;
begin
  WriteLn('test_keyboard — スキャンコード、キーコード、キーマップ、押下状態');
  WriteLn;

  WriteLn('1. 既定（US 配列）の対応');
  Check(PMLDefaultKeyFromScancode(TPMLScancode.W, False) = PMLK_W, 'W → w');
  Check(PMLDefaultKeyFromScancode(TPMLScancode.W, True) = Ord('W'), 'Shift + W → W');
  Check(PMLDefaultKeyFromScancode(TPMLScancode.Digit1, False) = PMLK_1, '1 → 1');
  Check(PMLDefaultKeyFromScancode(TPMLScancode.Digit1, True) = PMLK_EXCLAIM, 'Shift + 1 → !');
  Check(PMLDefaultKeyFromScancode(TPMLScancode.UP, False) = PMLK_UP, '上矢印');
  Check(PMLDefaultKeyFromScancode(TPMLScancode.F12, False) = PMLK_F12, 'F12');
  Check(PMLDefaultKeyFromScancode(TPMLScancode.KP_ENTER, False) = PMLK_KP_ENTER, 'テンキーの Enter');
  Check(PMLDefaultKeyFromScancode(TPMLScancode.UNKNOWN, False) = PMLK_UNKNOWN, 'UNKNOWN → 0');
  Check((PMLDefaultScancodeFromKey(Ord('W'), Shifted) = TPMLScancode.W) and Shifted,
    '大文字 W は Shift + W');
  Check((PMLDefaultScancodeFromKey(PMLK_EXCLAIM, Shifted) = TPMLScancode.Digit1) and Shifted,
    '! は Shift + 1');
  Check(PMLDefaultScancodeFromKey(PMLK_UP, Shifted) = TPMLScancode.UP, 'PMLK_UP → 上矢印');
  AllMatch := True;
  for S := TPMLScancode.A to TPMLScancode.Z do
    if PMLDefaultScancodeFromKey(PMLDefaultKeyFromScancode(S, False), Shifted) <> S then
      AllMatch := False;
  Check(AllMatch, 'A〜Z はスキャンコード → キーコード → スキャンコードで戻る');
  Check(PMLScancodeFromEvdev(17) = TPMLScancode.W, 'evdev 17（KEY_W）→ W');
  Check(PMLScancodeFromEvdev(103) = TPMLScancode.UP, 'evdev 103（KEY_UP）→ 上矢印');
  Check(PMLScancodeFromEvdev(100000) = TPMLScancode.UNKNOWN, '表の外の evdev → UNKNOWN');

  WriteLn;
  WriteLn('2. 名前');
  Check(TPMLScancode.W.Name = 'W', 'スキャンコード W の名前');
  Check(TPMLScancode.UP.Name = 'Up', '上矢印の名前は Up');
  Check(TPMLScancode(2).Name = '', '値の無いスキャンコードの名前は空');
  Check(PMLScancodeFromName('up') = TPMLScancode.UP, '名前から引く（大文字小文字を区別しない）');
  Check(PMLK_W.Name = 'W', 'キー w の名前は刻まれた大文字 W');
  Check(PMLK_RETURN.Name = 'Return', 'Return');
  Check(PMLK_UP.Name = 'Up', '印の付いたキーはスキャンコードの名前');
  Check(PMLK_LEFT_TAB.Name = 'LeftTab', '拡張キーの名前');
  Plain := TPMLKeymap.Create;
  try
    Check(Plain.KeyFromName('W') = PMLK_W, '名前 W → キー w');
    Check(Plain.KeyFromName('Up') = PMLK_UP, '名前 Up → 上矢印');
    Check(Plain.KeyFromName('LeftTab') = PMLK_LEFT_TAB, '拡張キーの名前から引く');
  finally
    Plain.Free;
  end;

  WriteLn;
  WriteLn('3. キーシム → Unicode');
  Check(PMLKeysymToUcs4($61) = $61, 'Latin-1 はそのまま');
  Check(PMLKeysymToUcs4($6C1) = $430, 'Cyrillic_a（0x6c1）→ U+0430');
  Check(PMLKeysymToUcs4($1000430) = $430, 'Unicode キーシム');
  Check(PMLKeysymToUcs4($20AC) = $20AC, 'EuroSign');
  Check(PMLKeysymToUcs4($FF0D) = 0, 'Return のキーシムは文字ではない');
  AllMatch := True;
  for I := $58A to $58F do
    if PMLKeysymToUcs4(I) <> 0 then
      AllMatch := False;
  Check(AllMatch, '0x58a〜0x58f は 0（SDL は表の手前を読む。D-36）');
  Check(PMLKeysymToUcs4($590) = $6F0, 'その直後の 0x590 は正しく引ける');

  WriteLn;
  WriteLn('4. 押下状態');
  Ctx := TPMLContext.Create([]);
  try
    Drain;
    Send(TPMLScancode.W, True);
    Drain;
    Check(Ctx.Events.Keyboard.IsDown[TPMLScancode.W], 'W が押されている');
    Check((Length(Seen) = 1) and (Seen[0].Kind = TPMLEventKind.KeyDown)
      and (Seen[0].Scancode = TPMLScancode.W) and (Seen[0].Key = PMLK_W)
      and not Seen[0].IsRepeat, 'KeyDown にスキャンコードとキーコードが載る');

    Send(TPMLScancode.W, True);
    Drain;
    Check((Length(Seen) = 1) and Seen[0].IsRepeat, '押したまま来た KeyDown はリピート');

    Send(TPMLScancode.W, False);
    Drain;
    Check(not Ctx.Events.Keyboard.IsDown[TPMLScancode.W], '離すと押されていない');
    Check((Length(Seen) = 1) and (Seen[0].Kind = TPMLEventKind.KeyUp), 'KeyUp が来る');

    Send(TPMLScancode.W, False);
    Drain;
    Check(Length(Seen) = 0, '押されていないキーの KeyUp は捨てる');

    Send(TPMLScancode.A, True);
    Send(TPMLScancode.LSHIFT, True);
    Drain;
    Ctx.Events.Keyboard.SendFocus(1, False);
    Drain;
    Check(not Ctx.Events.Keyboard.IsDown[TPMLScancode.A]
      and not Ctx.Events.Keyboard.IsDown[TPMLScancode.LSHIFT],
      'フォーカスを失うと全部離される');
    Released := (Length(Seen) = 3)
      and (Seen[0].Kind = TPMLEventKind.KeyUp) and (Seen[0].Scancode = TPMLScancode.A)
      and (Seen[1].Kind = TPMLEventKind.KeyUp) and (Seen[1].Scancode = TPMLScancode.LSHIFT)
      and (Seen[2].Kind = TPMLEventKind.WindowFocusLost);
    Check(Released, 'KeyUp が 2 つ、その後に WindowFocusLost');
    Send(TPMLScancode.A, False);
    Drain;
    Check(Length(Seen) = 0, '離した後で届いた本物の KeyUp は捨てる');

    FillChar(K, SizeOf(K), 0);
    K.Keysym := $61;
    Ctx.Events.Keyboard.SendKey(1, K, True, '');
    Drain;
    Check((Length(Seen) = 1) and (Seen[0].Scancode = TPMLScancode.UNKNOWN),
      'スキャンコードの分からないキーも KeyDown にはなる');

    WriteLn;
    WriteLn('5. 合成したキーマップ');
    Ctx.Events.Keyboard.SetKeymap(FrenchLike);
    Drain;
    Check((Length(Seen) = 1) and (Seen[0].Kind = TPMLEventKind.KeymapChanged),
      'キーマップを替えると KeymapChanged');
    Check(Ctx.Events.Keyboard.Keymap.FrenchNumbers, 'AZERTY 型と判定される');
    Send(TPMLScancode.Q, True);
    Send(TPMLScancode.Q, False);
    Send(TPMLScancode.Digit1, True);
    Send(TPMLScancode.Digit1, False);
    Drain;
    Check((Length(Seen) = 4) and (Seen[0].Key = PMLK_A),
      'Q の位置のキーイベントは a');
    Check((Length(Seen) = 4) and (Seen[2].Key = PMLK_1),
      '数字の段は数字（french_numbers）');
    Ctx.Events.Keyboard.KeycodeOptions := [];
    Send(TPMLScancode.Digit1, True);
    Send(TPMLScancode.Digit1, False);
    Drain;
    Check((Length(Seen) = 2) and (Seen[0].Key = PMLK_AMPERSAND),
      'french_numbers を外すと &');
    Check(Ctx.Events.Keyboard.Keymap.KeyName(PMLK_A) = 'A', 'a のキーの名前は A');
    Ctx.Events.Keyboard.KeycodeOptions := PML_DEFAULT_KEYCODE_OPTIONS;

    Ctx.Events.Keyboard.SetKeymap(RussianLike);
    Drain;
    Check(not Ctx.Events.Keyboard.Keymap.LatinLetters, 'ロシア語型はラテン文字ではない');
    Send(TPMLScancode.A, True);
    Send(TPMLScancode.A, False);
    Drain;
    Check((Length(Seen) = 2) and (Seen[0].Key = PMLK_A),
      'A の位置は US 配列の a（latin_letters）');
  finally
    Ctx.Free;
  end;

  WriteLn;
  WriteLn('6. 実際の配列（xkbcommon。コンポジタは要らない）');
  CheckRealLayouts;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: キーの位置と意味が SDL と同じ規則で決まる ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
