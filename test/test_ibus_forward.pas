{
  test_ibus_forward — IBus の ForwardKeyEvent（IME が「このキーをアプリへ渡せ」と返す）の規則

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. ForwardKeyEvent(u keyval, u keycode, u state) の引数の読み取り（作った D-Bus メッセージで）
    2. X の state（修飾キーのマスク）から修飾キーへの変換（PMLModifiersToXState の逆。全部の組み合わせで往復）
    3. 3 つの値をアプリへ出すキー（スキャンコード・押す/離す・確定文字列）にする規則
    4. 偽の IME が Sink.KeyForwarded で返したキーが、IME に通らずに KeyDown / TextInput / KeyUp
       として届くこと。届いた順、リピート、同じキーの離すほうが二重にならないこと

  WHY:
    SDL は ForwardKeyEvent を扱わない（SDL_ibus.c の IBus_MessageHandler は CommitText と
    プリエディットの信号だけ）。GTK / Qt の IBus モジュールはこれを受けて、アプリへキーイベントを
    差し込む。IME がキーを自分で消費したうえで別のキー（例: Backspace）をアプリへ渡したいとき、
    確定済みの文字をいじる IME（ibus-skk の一部の操作など）がこれを使う。ibus-mozc では来ない。
    本物のデーモンとの接着（信号の宛先と引数の型）は CI の test_ibus_live が見る。
    CI でも走る（libdbus はメッセージの組み立てと読み取りにだけ使い、どこにも繋がない）。

  実行前提: libdbus-1。
}
program test_ibus_forward;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Events,
  PaPiMeLa.Events.Keymap,
  PaPiMeLa.Keycodes,
  PaPiMeLa.Platform.DBus,
  PaPiMeLa.TextInput,
  PaPiMeLa.TextInput.Backend,
  PaPiMeLa.TextInput.IBus,
  PaPiMeLa.Core;

type
  { FilterKey で Answer を返し、渡された番号を覚える。Forward で IME が返したキーを Sink に渡す。 }
  TForwardIme = class(TPMLNullTextInputBackend)
  public
    Answer : TPMLKeyFilterResult;
    Tickets: array of LongWord;
    function  BackendName: String; override;
    function  Capabilities: TPMLTextInputCapabilities; override;
    function  FilterKey(const AKey: TPMLKeyEventData; AIsRelease: Boolean;
      ATicket: LongWord): TPMLKeyFilterResult; override;
    procedure Resolve(AIndex: Integer; AConsumed: Boolean);
    // IBus の信号 ForwardKeyEvent を受けたときと同じ道（値 → キー → Sink）。
    procedure Forward(AKeysym, AKeycode, AState: LongWord);
  end;

var
  Ime     : TForwardIme = nil;
  Ctx     : TPMLContext;
  Failures: Integer = 0;
  LastWindow: TPMLWindowID = 0;
  LastRepeat: Boolean = False;

function TForwardIme.BackendName: String;
begin
  Result := 'forward-ime';
end;

function TForwardIme.Capabilities: TPMLTextInputCapabilities;
begin
  Result := [TPMLTextInputCapability.KeyFilter];
end;

function TForwardIme.FilterKey(const AKey: TPMLKeyEventData; AIsRelease: Boolean;
  ATicket: LongWord): TPMLKeyFilterResult;
begin
  SetLength(Tickets, Length(Tickets) + 1);
  Tickets[High(Tickets)] := ATicket;
  Result := Answer;
end;

procedure TForwardIme.Resolve(AIndex: Integer; AConsumed: Boolean);
begin
  FSink.KeyResolved(Tickets[AIndex], AConsumed);
end;

procedure TForwardIme.Forward(AKeysym, AKeycode, AState: LongWord);
var
  K: TPMLKeyEventData;
  Down: Boolean;
  Text: String;
begin
  PMLIBusForwardedKey(AKeysym, AKeycode, AState, K, Down, Text);
  FSink.KeyForwarded(K, Down, Text);
end;

function MakeIme: TPMLTextInputBackend;
begin
  Ime := TForwardIme.Create;
  Result := Ime;
end;

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

{ 届いたイベントを短い記号の列にする。Da = a の KeyDown、Ua = KeyUp、[a] = TextInput。
  R は KeyDown がリピート。最後のキーイベントのウィンドウを LastWindow に覚える。 }
function Take: String;
var
  Ev: TPMLEvent;
begin
  Result := '';
  while Ctx.Events.Poll(Ev) do
    case Ev.Kind of
      TPMLEventKind.KeyDown:
        begin
          Result := Result + 'D' + Chr(Ev.Key.Key);
          if Ev.Key.IsRepeat then
            Result := Result + 'R';
          LastWindow := Ev.WindowID;
        end;
      TPMLEventKind.KeyUp:
        begin
          Result := Result + 'U' + Chr(Ev.Key.Key);
          LastWindow := Ev.WindowID;
        end;
      TPMLEventKind.TextInput: Result := Result + '[' + Ev.Text + ']';
    end;
end;

const
  EVDEV_A = 30;
  EVDEV_B = 48;
  EVDEV_C = 46;
  EVDEV_ENTER = 28;
  EVDEV_BACKSPACE = 14;
  EVDEV_SPACE = 57;
  RELEASE = LongWord(1) shl 30;

procedure PhysicalKey(AEvdev: LongWord; ADown: Boolean; const AText: String);
var
  K: TPMLKeyEventData;
begin
  FillChar(K, SizeOf(K), 0);
  K.Scancode := PMLScancodeFromEvdev(AEvdev);
  K.Raw := AEvdev + 8;
  Ctx.Events.Keyboard.SendKey(1, K, ADown, AText);
end;

procedure TestReadSignal;
var
  Conn: TPMLDBusConnection;
  Msg: PDBusMessage;
  W: TPMLDBusWriter;
  Sym, Code, State: LongWord;
begin
  WriteLn('1. ForwardKeyEvent の引数');
  Conn := TPMLDBusConnection.CreateOffline;
  try
    Msg := Conn.BeginCall('a.b', '/a', 'a.b', 'ForwardKeyEvent');
    try
      W := Conn.Writer(Msg);
      W.AddUInt32($FF08);
      W.AddUInt32(14);
      W.AddUInt32(RELEASE or 4);
      Check(PMLReadIBusForwardKey(Conn.Reader(Msg), Sym, Code, State), '3 つの u を読める');
      Check((Sym = $FF08) and (Code = 14) and (State = (RELEASE or 4)), '値が順に戻る');
    finally
      Conn.Unref(Msg);
    end;

    Msg := Conn.BeginCall('a.b', '/a', 'a.b', 'ForwardKeyEvent');
    try
      W := Conn.Writer(Msg);
      W.AddUInt32($61);
      W.AddUInt32(30);
      Check(not PMLReadIBusForwardKey(Conn.Reader(Msg), Sym, Code, State), '引数が足りなければ断る');
    finally
      Conn.Unref(Msg);
    end;

    Msg := Conn.BeginCall('a.b', '/a', 'a.b', 'ForwardKeyEvent');
    try
      W := Conn.Writer(Msg);
      W.AddUInt32($61);
      W.AddString('x');
      W.AddUInt32(0);
      Check(not PMLReadIBusForwardKey(Conn.Reader(Msg), Sym, Code, State), '型が違えば断る');
    finally
      Conn.Unref(Msg);
    end;
  finally
    Conn.Free;
  end;
end;

procedure TestModifiers;
var
  I: Integer;
  M, Back: TPMLKeyModifiers;
  Bad: Integer;
  Mod_: TPMLKeyModifier;
begin
  WriteLn;
  WriteLn('2. state → 修飾キー');
  Check(PMLXStateToModifiers(1) = [TPMLKeyModifier.Shift], '1 = Shift');
  Check(PMLXStateToModifiers(2) = [TPMLKeyModifier.CapsLock], '2 = CapsLock');
  Check(PMLXStateToModifiers(4) = [TPMLKeyModifier.Ctrl], '4 = Ctrl');
  Check(PMLXStateToModifiers(8) = [TPMLKeyModifier.Alt], '8 = Alt');
  Check(PMLXStateToModifiers(16) = [TPMLKeyModifier.NumLock], '16 = NumLock');
  Check(PMLXStateToModifiers(64) = [TPMLKeyModifier.Super], '64 = Super');
  Check(PMLXStateToModifiers(RELEASE or 32 or 128) = [], '離す印や、使わないマスク（Mod3・Mod5 など）は修飾キーにしない');
  Bad := 0;
  for I := 0 to 63 do
  begin
    M := [];
    for Mod_ := Low(TPMLKeyModifier) to High(TPMLKeyModifier) do
      if (I and (1 shl Ord(Mod_))) <> 0 then
        Include(M, Mod_);
    Back := PMLXStateToModifiers(PMLModifiersToXState(M));
    if Back <> M then
      Inc(Bad);
  end;
  Check(Bad = 0, Format('64 通りの組み合わせが PMLModifiersToXState と往復する（%d 通りがずれた）', [Bad]));
end;

procedure TestKeyConversion;
var
  K: TPMLKeyEventData;
  Down: Boolean;
  Text: String;
begin
  WriteLn;
  WriteLn('3. 3 つの値 → アプリへ出すキー');
  PMLIBusForwardedKey($61, EVDEV_A, 0, K, Down, Text);
  Check(Down and (Text = 'a'), 'a を押す: 押す・文字 a');
  Check((K.Keysym = $61) and (K.Raw = EVDEV_A + 8) and (K.Scancode = PMLScancodeFromEvdev(EVDEV_A)),
    'キーシム・Raw（evdev + 8）・スキャンコードが入る');
  Check((K.Modifiers = []) and (not K.IsRepeat) and (K.Key = 0),
    '修飾なし・リピートでない・Key は 0（キーマップから決めてもらう）');

  PMLIBusForwardedKey($61, EVDEV_A, RELEASE, K, Down, Text);
  Check((not Down) and (Text = ''), 'IBUS_RELEASE_MASK なら離す。文字なし');

  PMLIBusForwardedKey($41, EVDEV_A, 1, K, Down, Text);
  Check(Down and (Text = 'A') and (K.Modifiers = [TPMLKeyModifier.Shift]), 'Shift つきの A: 文字 A、修飾 Shift');

  PMLIBusForwardedKey($61, EVDEV_A, 4, K, Down, Text);
  Check(Down and (Text = '') and (K.Modifiers = [TPMLKeyModifier.Ctrl]), 'Ctrl つきなら文字なし');
  PMLIBusForwardedKey($61, EVDEV_A, 8, K, Down, Text);
  Check(Text = '', 'Alt つきなら文字なし');
  PMLIBusForwardedKey($61, EVDEV_A, 64, K, Down, Text);
  Check(Text = '', 'Super つきなら文字なし');
  PMLIBusForwardedKey($61, EVDEV_A, 2 or 16, K, Down, Text);
  Check(Text = 'a', 'CapsLock・NumLock だけなら文字は出す');

  PMLIBusForwardedKey($FF0D, EVDEV_ENTER, 0, K, Down, Text);
  Check(Down and (Text = '') and (K.Scancode = PMLScancodeFromEvdev(EVDEV_ENTER)), 'Enter: 文字なし');
  PMLIBusForwardedKey($FF08, EVDEV_BACKSPACE, 0, K, Down, Text);
  Check(Text = '', 'BackSpace: 文字なし');
  PMLIBusForwardedKey($20, EVDEV_SPACE, 0, K, Down, Text);
  Check(Text = ' ', 'スペースは文字 1 つ');
  PMLIBusForwardedKey($01003042, 0, 0, K, Down, Text);
  Check(Text = #$E3#$81#$82, 'Unicode キーシム（あ）は UTF-8 で 3 バイト');
  Check(K.Raw = 8, 'keycode が 0 でも Raw は 8（evdev 0 + 8）');
  PMLIBusForwardedKey($0, 5, 0, K, Down, Text);
  Check(Text = '', 'キーシム 0 は文字なし');
end;

procedure TestRouting;
var
  S: String;
  Before: Integer;
begin
  WriteLn;
  WriteLn('4. 偽の IME が返したキーが、IME に通らずに届く');
  Ctx.TextInput.Start(nil, nil);
  Ctx.Events.Keyboard.SendFocus(1, True);
  Ime.Answer := TPMLKeyFilterResult.PassThrough;
  Take;
  Before := Length(Ime.Tickets);

  Ime.Forward($61, EVDEV_A, 0);
  S := Take;
  Check(S = 'Da[a]', '押す: KeyDown と文字（' + S + '）');
  Check(LastWindow = 1, 'フォーカスのあるウィンドウへ出る');
  Ime.Forward($61, EVDEV_A, RELEASE);
  S := Take;
  Check(S = 'Ua', '離す: KeyUp（' + S + '）');
  Check(Length(Ime.Tickets) = Before, 'IME のフィルタには通さない（無限に返ってこない）');

  WriteLn;
  WriteLn('5. リピートと二重の KeyUp');
  Ime.Forward($61, EVDEV_A, 0);
  Ime.Forward($61, EVDEV_A, 0);
  S := Take;
  Check(S = 'Da[a]DaR[a]', '押したままもう一度押せばリピート（' + S + '）');
  Ime.Forward($61, EVDEV_A, RELEASE);
  Ime.Forward($61, EVDEV_A, RELEASE);
  S := Take;
  Check(S = 'Ua', '離すのは 1 度だけ。離したキーをもう一度離しても出さない（' + S + '）');

  WriteLn;
  WriteLn('6. IME が物理キーを消費して、同じキーを返す（普通の使い方）');
  Ime.Answer := TPMLKeyFilterResult.Consumed;
  PhysicalKey(EVDEV_B, True, 'b');
  Check(Take = '', '物理の押すほうは消費されて何も出ない');
  Ime.Forward($62, EVDEV_B, 0);
  S := Take;
  Check(S = 'Db[b]', '返ってきた押すほうが、アプリへ KeyDown と文字になる（' + S + '）');
  Ime.Forward($62, EVDEV_B, RELEASE);
  S := Take;
  Check(S = 'Ub', '返ってきた離すほうで KeyUp（' + S + '）');
  PhysicalKey(EVDEV_B, False, '');
  Check(Take = '', '後から来る物理の離すほうは、もう離してあるので出さない');

  WriteLn;
  WriteLn('7. 返信待ちのキーを追い越さない');
  Ime.Answer := TPMLKeyFilterResult.Deferred;
  PhysicalKey(EVDEV_C, True, 'c');
  Before := Length(Ime.Tickets);
  Ime.Forward($FF08, EVDEV_BACKSPACE, 0);
  Check(Take = '', '待っているキーがあれば、返ってきたキーもその後ろに並ぶ');
  Ime.Resolve(Before - 1, True);
  S := Take;
  Check(S = 'D' + Chr(PMLK_BACKSPACE), 'c が消費で解決すると、返ってきた BackSpace だけが出る（' + S + '）');
  Ime.Forward($FF08, EVDEV_BACKSPACE, RELEASE);
  S := Take;
  Check(S = 'U' + Chr(PMLK_BACKSPACE), 'BackSpace を離す（' + S + '）');
  Ime.Answer := TPMLKeyFilterResult.PassThrough;
  PhysicalKey(EVDEV_C, False, '');
  Take;

  WriteLn;
  WriteLn('8. フォーカスを失ったら、返ってきたキーも離す');
  Ime.Forward($61, EVDEV_A, 0);
  Take;
  Ctx.Events.Keyboard.SendFocus(1, False);
  S := Take;
  Check(S = 'Ua', '押したままのキーは KeyUp になる（' + S + '）');
  Check(Ctx.Events.DroppedCount = 0, 'イベントの取りこぼしなし');
end;

var
  Opts: TPMLContextOptions;
begin
  WriteLn('test_ibus_forward — IBus の ForwardKeyEvent');
  WriteLn;
  TestReadSignal;
  TestModifiers;
  TestKeyConversion;
  PMLRegisterTextInputBackend('forward-ime', 1, @MakeIme);
  Opts := TPMLContextOptions.Default;
  Opts.PreferredTextInput := 'forward-ime';
  Ctx := TPMLContext.Create([TPMLSubsystem.TextInput], Opts);
  try
    TestRouting;
  finally
    Ctx.Free;
  end;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: ForwardKeyEvent のキーがアプリへ釣り合って届く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
