{
  PaPiMeLa.Events.Keymap — スキャンコードとキーコードの対応、キーの名前

  Origin : partially ported from SDL (src/events/SDL_keymap.c, src/events/SDL_keyboard.c,
           src/events/SDL_keysym_to_keycode.c, src/events/imKStoUCS.c,
           src/video/wayland/SDL_waylandevents.c)
           Scope: 既定（US 配列）のキー配置、キーマップを引く順序（Shift で見つからなければ
           修飾なし、それも無ければ既定）、キーイベントのキーコードの決め方
           （french_numbers / latin_letters）、キーの名前と名前からの逆引き、
           キーシムから Unicode とキーコードを求める手順。表は PaPiMeLa.Keycodes.Tables。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.6、§11 #24

  WHAT:
    TPMLKeymap（スキャンコード → キーコード。配列ごとに 1 つ）と、それを使わない
    既定の対応・名前の関数。TPMLScancode / TPMLKeycode の型ヘルパ（Name）。

  WHY:
    キーイベントのキーコードは「今の配列で、そのキーに書いてある文字」。
    AZERTY なら Q の位置のキーは 'a' になる。これを決めるのがキーマップで、
    Wayland ではシートが xkb のキーマップから作って TPMLKeyboardState へ渡す。

  RESOLVED:
    - SDL のキーマップは修飾キーの組み合わせごとに表を持つが、ここでは「修飾なし」と
      「Shift」の 2 段だけを持つ。キーイベントのキーコードと名前の大文字化に使うのは
      この 2 段だけで（SDL_GetKeyFromScancode は key_event のとき修飾を捨てる）、
      AltGr などの段は使い道が無いため
    - 空のキーマップは SDL の NULL キーマップと同じ意味になる（全部既定へ落ちる）
    - キーイベントのキーコードの決め方は SDL の既定（SDL_HINT_KEYCODE_OPTIONS =
      "french_numbers,latin_letters"）と同じ。非ラテン配列（ロシア語など）では
      文字キーが US 配列の文字になり、フランス語配列の数字の段は数字になる
    - imKStoUCS の範囲 0x58a〜0x58f は表の先頭より手前を引く（上流の不具合 D-36）。
      ここでは表の先頭より前を引かず 0 を返す

  NOT RESOLVED:
    - hide_numpad（テンキーのキーコードを数字にする）は未実装
    - 仮想キーボード（スキャンコードの無いキー）に予約スキャンコードを割り当てる
      処理（SDL_GetKeymapNextReservedScancode）は未実装。そのキーは UNKNOWN になる
    - AltGr / Level5 / CapsLock の段は持たない

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Events.Keymap;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Keycodes;

type
  { キーイベントのキーコードの決め方。SDL_HINT_KEYCODE_OPTIONS にあたる。 }
  TPMLKeycodeOption = (
    FrenchNumbers,   // 数字の段が記号の配列（AZERTY）では、数字の段を数字にする
    LatinLetters     // 文字キーがラテン文字でない配列では、US 配列の文字にする
  );
  TPMLKeycodeOptions = set of TPMLKeycodeOption;

const
  PML_DEFAULT_KEYCODE_OPTIONS = [TPMLKeycodeOption.FrenchNumbers,
                                 TPMLKeycodeOption.LatinLetters];

type
  { 1 つの配列のキーマップ。「修飾なし」と「Shift」の 2 段を持つ。 }
  TPMLKeymap = class
  strict private
    type
      TReverseEntry = record
        Key     : TPMLKeycode;
        Scancode: TPMLScancode;
        Shifted : Boolean;
      end;
    var
      FKeys   : array[Boolean, TPMLScancode] of TPMLKeycode;
      FHas    : array[Boolean, TPMLScancode] of Boolean;
      FReverse: array of TReverseEntry;
      FFrenchNumbers, FLatinLetters, FThai: Boolean;
    function FindReverse(AKey: TPMLKeycode): Integer;
  public
    { 1 項目を登録する。SDL_SetKeymapEntry と同じく、逆引きには「修飾が少ないもの、
      同じなら先に登録したもの」を残す。 }
    procedure SetEntry(AScancode: TPMLScancode; AShifted: Boolean; AKey: TPMLKeycode);
    { 配列の性質を調べる（SDL_SetKeymap の判定）。登録を終えてから呼ぶ。 }
    procedure DetectLayout;

    { SDL_GetKeymapKeycode。Shift の段が無ければ修飾なしの段、それも無ければ既定。 }
    function KeyFromScancode(AScancode: TPMLScancode; AShifted: Boolean): TPMLKeycode;
    { SDL_GetKeymapScancode。見つからなければ既定の配置で逆引きする。 }
    function ScancodeFromKey(AKey: TPMLKeycode; out AShifted: Boolean): TPMLScancode;
    { キーイベントに載せるキーコード（SDL_GetKeyFromScancode の key_event = true）。 }
    function KeyForEvent(AScancode: TPMLScancode;
      AOptions: TPMLKeycodeOptions = PML_DEFAULT_KEYCODE_OPTIONS): TPMLKeycode;

    { SDL_GetKeyName。文字キーは、そのキーに刻まれている大文字の名前になる。 }
    function KeyName(AKey: TPMLKeycode): String;
    { SDL_GetKeyFromName。1 文字ならその文字（大文字は小文字のキーへ戻す）、
      それ以外はキーの名前として引く。大文字小文字は区別しない。 }
    function KeyFromName(const AName: String): TPMLKeycode;

    property FrenchNumbers: Boolean read FFrenchNumbers;
    property LatinLetters : Boolean read FLatinLetters;
    property Thai         : Boolean read FThai;
  end;

  TPMLScancodeHelper = type helper for TPMLScancode
    { スキャンコードの名前（SDL_GetScancodeName）。名前の無いものは空文字列。 }
    function Name: String;
  end;

  TPMLKeycodeHelper = type helper for TPMLKeycode
    { 既定（US 配列）でのキーの名前。配列に従った名前は TPMLKeymap.KeyName。 }
    function Name: String;
  end;

{ 既定（US 配列）の対応。SDL_GetDefaultKeyFromScancode / SDL_GetDefaultScancodeFromKey。 }
function PMLDefaultKeyFromScancode(AScancode: TPMLScancode; AShifted: Boolean): TPMLKeycode;
function PMLDefaultScancodeFromKey(AKey: TPMLKeycode; out AShifted: Boolean): TPMLScancode;

{ SDL_GetScancodeFromName。大文字小文字は区別しない。無ければ UNKNOWN。 }
function PMLScancodeFromName(const AName: String): TPMLScancode;

{ X11 / XKB のキーシムを Unicode にする（SDL_KeySymToUcs4）。文字でなければ 0。 }
function PMLKeysymToUcs4(AKeysym: LongWord): LongWord;

{ キーマップに登録するキーコードを、そのキーのキーシムから決める。
  SDL_GetKeyCodeFromKeySym と、Wayland のキーマップ作成（Wayland_KeymapIterator）の
  「それでも決まらなければ」の部分を合わせたもの。 }
function PMLKeymapKeycode(AKeysym: LongWord; AScancode: TPMLScancode;
  AShifted: Boolean): TPMLKeycode;

{ evdev のキーコード（Wayland が送る値。xkb のキーコード - 8）をスキャンコードにする。 }
function PMLScancodeFromEvdev(AEvdevCode: LongWord): TPMLScancode;

implementation

uses
  PaPiMeLa.Keycodes.Tables;

function UCS4ToUTF8(ACode: LongWord): String;
begin
  if ACode < $80 then
    Result := Chr(ACode)
  else if ACode < $800 then
    Result := Chr($C0 or (ACode shr 6)) + Chr($80 or (ACode and $3F))
  else if ACode < $10000 then
    Result := Chr($E0 or (ACode shr 12)) + Chr($80 or ((ACode shr 6) and $3F))
            + Chr($80 or (ACode and $3F))
  else
    Result := Chr($F0 or (ACode shr 18)) + Chr($80 or ((ACode shr 12) and $3F))
            + Chr($80 or ((ACode shr 6) and $3F)) + Chr($80 or (ACode and $3F));
end;

{ ---- 既定の対応 ---- }

function PMLDefaultKeyFromScancode(AScancode: TPMLScancode; AShifted: Boolean): TPMLKeycode;
var
  I: Integer;
begin
  if AScancode < TPMLScancode.A then
    Exit(PMLK_UNKNOWN);

  if AScancode < TPMLScancode.Digit1 then
  begin
    if AShifted then
      Exit(TPMLKeycode(Ord('A') + Ord(AScancode) - Ord(TPMLScancode.A)))
    else
      Exit(TPMLKeycode(Ord('a') + Ord(AScancode) - Ord(TPMLScancode.A)));
  end;

  if AScancode < TPMLScancode.CAPSLOCK then
  begin
    I := Ord(AScancode) - Ord(TPMLScancode.Digit1);
    if AShifted then
      Exit(PML_SHIFTED_DEFAULT_SYMBOLS[I])
    else
      Exit(PML_NORMAL_DEFAULT_SYMBOLS[I]);
  end;

  // 印字できないキー。SDL の switch を表にしたもの。
  for I := 0 to High(PML_DEFAULT_KEYS) do
    if PML_DEFAULT_KEYS[I].Scancode = AScancode then
      Exit(PML_DEFAULT_KEYS[I].Keycode);
  Result := PMLK_UNKNOWN;
end;

function PMLDefaultScancodeFromKey(AKey: TPMLKeycode; out AShifted: Boolean): TPMLScancode;
var
  I: Integer;
begin
  AShifted := False;
  if AKey = PMLK_UNKNOWN then
    Exit(TPMLScancode.UNKNOWN);

  if (AKey and PMLK_EXTENDED_MASK) <> 0 then
  begin
    for I := 0 to High(PML_EXTENDED_DEFAULT_SYMBOLS) do
      if PML_EXTENDED_DEFAULT_SYMBOLS[I].Keycode = AKey then
        Exit(PML_EXTENDED_DEFAULT_SYMBOLS[I].Scancode);
    Exit(TPMLScancode.UNKNOWN);
  end;

  if (AKey and PMLK_SCANCODE_MASK) <> 0 then
  begin
    I := Integer(AKey and not PMLK_SCANCODE_MASK);
    if I > Ord(High(TPMLScancode)) then
      Exit(TPMLScancode.UNKNOWN);
    Exit(TPMLScancode(I));
  end;

  if (AKey >= PMLK_A) and (AKey <= PMLK_Z) then
    Exit(TPMLScancode(Ord(TPMLScancode.A) + Integer(AKey - PMLK_A)));

  if (AKey >= Ord('A')) and (AKey <= Ord('Z')) then
  begin
    AShifted := True;
    Exit(TPMLScancode(Ord(TPMLScancode.A) + Integer(AKey) - Ord('A')));
  end;

  for I := 0 to High(PML_NORMAL_DEFAULT_SYMBOLS) do
    if AKey = PML_NORMAL_DEFAULT_SYMBOLS[I] then
      Exit(TPMLScancode(Ord(TPMLScancode.Digit1) + I));

  for I := 0 to High(PML_SHIFTED_DEFAULT_SYMBOLS) do
    if AKey = PML_SHIFTED_DEFAULT_SYMBOLS[I] then
    begin
      AShifted := True;
      Exit(TPMLScancode(Ord(TPMLScancode.Digit1) + I));
    end;

  if AKey = PMLK_DELETE then
    Exit(TPMLScancode.DELETE);

  Result := TPMLScancode.UNKNOWN;
end;

function PMLScancodeFromName(const AName: String): TPMLScancode;
var
  S: TPMLScancode;
begin
  Result := TPMLScancode.UNKNOWN;
  if AName = '' then
    Exit;
  for S := Low(TPMLScancode) to High(TPMLScancode) do
    if (PML_SCANCODE_NAMES[S] <> '') and SameText(AName, PML_SCANCODE_NAMES[S]) then
      Exit(S);
end;

{ ---- キーシム ---- }

{ PORT-NOTE: imKStoUCS.c の範囲判定は `keysym > Above && keysym < Below` で、
  表は Base から始まる。範囲 0x589 < keysym < 0x5ff だけは Above + 1 < Base で、
  0x58a〜0x58f が表の先頭より手前を引く（符号なしの引き算が桁あふれして
  範囲外を読む。D-36）。ここでは Base より前を 0 にする。 }
function PMLKeysymToUcs4(AKeysym: LongWord): LongWord;
var
  I: Integer;
  R: TPMLKeysymUcsRange;
begin
  // Unicode キーシム（0x01000000 + コードポイント）
  if (AKeysym and $FF000000) = $01000000 then
    Exit(AKeysym and $00FFFFFF);
  // Latin-1 はキーシムとコードポイントが一致する
  if (AKeysym > 0) and (AKeysym < $100) then
    Exit(AKeysym);

  for I := 0 to High(PML_KEYSYM_UCS_RANGES) do
  begin
    R := PML_KEYSYM_UCS_RANGES[I];
    if (AKeysym > R.Above) and (AKeysym < R.Below) then
    begin
      if (AKeysym < R.Base) or (Integer(AKeysym - R.Base) >= R.Count) then
        Exit(0);
      Exit(PML_KEYSYM_UCS_DATA[R.Offset + Integer(AKeysym - R.Base)]);
    end;
  end;
  Result := 0;
end;

function PMLKeymapKeycode(AKeysym: LongWord; AScancode: TPMLScancode;
  AShifted: Boolean): TPMLKeycode;
var
  I: Integer;
begin
  // SDL_GetKeyCodeFromKeySym: 文字 → 拡張キーの表 → スキャンコードの既定
  Result := TPMLKeycode(PMLKeysymToUcs4(AKeysym));
  if Result = PMLK_UNKNOWN then
    for I := 0 to High(PML_KEYSYM_KEYCODES) do
      if PML_KEYSYM_KEYCODES[I].Keysym = AKeysym then
        Exit(PML_KEYSYM_KEYCODES[I].Keycode);
  if Result = PMLK_UNKNOWN then
    Result := PMLDefaultKeyFromScancode(AScancode, AShifted);

  // Wayland_KeymapIterator: それでも決まらなければ、制御キーは文字のキーコード、
  // それ以外はスキャンコードに印を付けたもの。
  if Result = PMLK_UNKNOWN then
    case AScancode of
      TPMLScancode.RETURN   : Result := PMLK_RETURN;
      TPMLScancode.ESCAPE   : Result := PMLK_ESCAPE;
      TPMLScancode.BACKSPACE: Result := PMLK_BACKSPACE;
      TPMLScancode.DELETE   : Result := PMLK_DELETE;
    else
      if AScancode <> TPMLScancode.UNKNOWN then
        Result := TPMLKeycode(Ord(AScancode)) or PMLK_SCANCODE_MASK;
    end;
end;

function PMLScancodeFromEvdev(AEvdevCode: LongWord): TPMLScancode;
begin
  if AEvdevCode > High(PML_LINUX_SCANCODES) then
    Exit(TPMLScancode.UNKNOWN);
  Result := PML_LINUX_SCANCODES[AEvdevCode];
end;

{ ---- TPMLKeymap ---- }

function TPMLKeymap.FindReverse(AKey: TPMLKeycode): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FReverse) do
    if FReverse[I].Key = AKey then
      Exit(I);
  Result := -1;
end;

procedure TPMLKeymap.SetEntry(AScancode: TPMLScancode; AShifted: Boolean;
  AKey: TPMLKeycode);
var
  I: Integer;
begin
  FKeys[AShifted, AScancode] := AKey;
  FHas[AShifted, AScancode] := True;

  // 逆引き。既にあるものの方が修飾が少なければ（または同じなら）残す。
  I := FindReverse(AKey);
  if I < 0 then
  begin
    SetLength(FReverse, Length(FReverse) + 1);
    I := High(FReverse);
  end
  else if (not FReverse[I].Shifted) or AShifted then
    Exit;
  FReverse[I].Key := AKey;
  FReverse[I].Scancode := AScancode;
  FReverse[I].Shifted := AShifted;
end;

procedure TPMLKeymap.DetectLayout;

  function IsDigit(AKey: TPMLKeycode): Boolean;
  begin
    Result := (AKey >= Ord('0')) and (AKey <= Ord('9'));
  end;

var
  S: TPMLScancode;
  K: TPMLKeycode;
begin
  // 数字の段が「修飾なしで記号、Shift で数字」なら AZERTY 型
  FFrenchNumbers := True;
  for S := TPMLScancode.Digit1 to TPMLScancode.Digit0 do
    if IsDigit(KeyFromScancode(S, False)) or not IsDigit(KeyFromScancode(S, True)) then
    begin
      FFrenchNumbers := False;
      Break;
    end;

  // A〜D のどれかが Latin-1 ならラテン文字の配列。タイ文字ならタイ語の配列
  FThai := False;
  FLatinLetters := False;
  for S := TPMLScancode.A to TPMLScancode.D do
  begin
    K := KeyFromScancode(S, False);
    if K <= $FF then
    begin
      FLatinLetters := True;
      Break;
    end;
    if (K >= $0E00) and (K <= $0E7F) then
    begin
      FThai := True;
      Break;
    end;
  end;
end;

function TPMLKeymap.KeyFromScancode(AScancode: TPMLScancode; AShifted: Boolean): TPMLKeycode;
begin
  if AShifted and FHas[True, AScancode] then
    Exit(FKeys[True, AScancode]);
  if FHas[False, AScancode] then
    Exit(FKeys[False, AScancode]);
  Result := PMLDefaultKeyFromScancode(AScancode, AShifted);
end;

function TPMLKeymap.ScancodeFromKey(AKey: TPMLKeycode; out AShifted: Boolean): TPMLScancode;
var
  I: Integer;
begin
  I := FindReverse(AKey);
  if I < 0 then
    Exit(PMLDefaultScancodeFromKey(AKey, AShifted));
  AShifted := FReverse[I].Shifted;
  Result := FReverse[I].Scancode;
end;

{ PORT-NOTE: SDL_GetKeyFromScancode（key_event = true）と SDL_GetCurrentKeymap。
  タイ語の配列と、latin_letters が有効でラテン文字でない配列では、キーマップを
  使わず既定（US 配列）にする。french_numbers が有効で AZERTY 型なら、数字の段は
  Shift の段を使う。 }
function TPMLKeymap.KeyForEvent(AScancode: TPMLScancode;
  AOptions: TPMLKeycodeOptions): TPMLKeycode;
var
  UseDefault, Shifted: Boolean;
begin
  UseDefault := FThai
    or ((TPMLKeycodeOption.LatinLetters in AOptions) and not FLatinLetters);
  Shifted := (TPMLKeycodeOption.FrenchNumbers in AOptions) and not UseDefault
    and FFrenchNumbers
    and (AScancode >= TPMLScancode.Digit1) and (AScancode <= TPMLScancode.Digit0);
  if UseDefault then
    Result := PMLDefaultKeyFromScancode(AScancode, Shifted)
  else
    Result := KeyFromScancode(AScancode, Shifted);
end;

function TPMLKeymap.KeyName(AKey: TPMLKeycode): String;
var
  I: LongWord;
  S: TPMLScancode;
  Shifted: Boolean;
  Capital: TPMLKeycode;
begin
  if (AKey and PMLK_SCANCODE_MASK) <> 0 then
  begin
    I := AKey and not PMLK_SCANCODE_MASK;
    if I > LongWord(Ord(High(TPMLScancode))) then
      Exit('');
    Exit(PML_SCANCODE_NAMES[TPMLScancode(I)]);
  end;

  if (AKey and PMLK_EXTENDED_MASK) <> 0 then
  begin
    I := AKey and not PMLK_EXTENDED_MASK;
    if (I > 0) and (I - 1 <= LongWord(High(PML_EXTENDED_KEY_NAMES))) then
      Exit(PML_EXTENDED_KEY_NAMES[I - 1]);
    Exit('');
  end;

  case AKey of
    PMLK_RETURN   : Exit(PML_SCANCODE_NAMES[TPMLScancode.RETURN]);
    PMLK_ESCAPE   : Exit(PML_SCANCODE_NAMES[TPMLScancode.ESCAPE]);
    PMLK_BACKSPACE: Exit(PML_SCANCODE_NAMES[TPMLScancode.BACKSPACE]);
    PMLK_TAB      : Exit(PML_SCANCODE_NAMES[TPMLScancode.TAB]);
    PMLK_SPACE    : Exit(PML_SCANCODE_NAMES[TPMLScancode.SPACE]);
    PMLK_DELETE   : Exit(PML_SCANCODE_NAMES[TPMLScancode.DELETE]);
  end;

  // キーコードは修飾なしの文字だが、名前はキーに刻まれた文字（普通は大文字）。
  if (AKey > $7F) or ((AKey >= Ord('a')) and (AKey <= Ord('z'))) then
  begin
    S := ScancodeFromKey(AKey, Shifted);
    if (S <> TPMLScancode.UNKNOWN) and not Shifted then
    begin
      Capital := KeyFromScancode(S, True);
      if (Capital > $7F) or ((Capital >= Ord('A')) and (Capital <= Ord('Z'))) then
        AKey := Capital;
    end;
  end;
  Result := UCS4ToUTF8(AKey);
end;

function TPMLKeymap.KeyFromName(const AName: String): TPMLKeycode;
var
  B: Byte;
  Key: LongWord;
  S: TPMLScancode;
  Shifted: Boolean;
  I: Integer;
begin
  if AName = '' then
    Exit(PMLK_UNKNOWN);

  // 1 文字の UTF-8 なら、その文字がキーコード
  B := Ord(AName[1]);
  Key := 0;
  if B >= $F0 then
  begin
    if Length(AName) = 4 then
      Key := (LongWord(B and $07) shl 18) or (LongWord(Ord(AName[2]) and $3F) shl 12)
          or (LongWord(Ord(AName[3]) and $3F) shl 6) or LongWord(Ord(AName[4]) and $3F);
  end
  else if B >= $E0 then
  begin
    if Length(AName) = 3 then
      Key := (LongWord(B and $0F) shl 12) or (LongWord(Ord(AName[2]) and $3F) shl 6)
          or LongWord(Ord(AName[3]) and $3F);
  end
  else if B >= $C0 then
  begin
    if Length(AName) = 2 then
      Key := (LongWord(B and $1F) shl 6) or LongWord(Ord(AName[2]) and $3F);
  end
  else if Length(AName) = 1 then
    Key := B;

  if Key <> 0 then
  begin
    // 名前は刻まれた文字（大文字）なので、Shift の段にあれば修飾なしのキーへ戻す
    S := ScancodeFromKey(TPMLKeycode(Key), Shifted);
    if (S <> TPMLScancode.UNKNOWN) and Shifted then
      Key := KeyFromScancode(S, False);
    Exit(TPMLKeycode(Key));
  end;

  for I := 0 to High(PML_EXTENDED_KEY_NAMES) do
    if SameText(AName, PML_EXTENDED_KEY_NAMES[I]) then
      Exit(TPMLKeycode(I + 1) or PMLK_EXTENDED_MASK);

  // SDL と同じく、名前から引いたスキャンコードを今のキーマップで引く
  Result := KeyFromScancode(PMLScancodeFromName(AName), False);
end;

{ ---- 型ヘルパ ---- }

function TPMLScancodeHelper.Name: String;
begin
  Result := PML_SCANCODE_NAMES[Self];
end;

function TPMLKeycodeHelper.Name: String;
var
  Empty: TPMLKeymap;
begin
  // 空のキーマップは既定（US 配列）と同じ意味になる
  Empty := TPMLKeymap.Create;
  try
    Result := Empty.KeyName(Self);
  finally
    Empty.Free;
  end;
end;

end.
