{
  test_ime_keys — IME の返信を待つキーの並び（§7.5）を表示サーバ無しで検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    返信を後で返す偽の IME を登録し、TPMLKeyboardState.SendKey にキーを流して、
    アプリへ届くイベントの並びを見る。返信の順番が入れ替わっても届いた順に出すこと、
    すぐ結果の出たキーも待っているキーを追い越さないこと、返信が来なければ打ち切る
    こと、フォーカスを失ったときとセッションを止めたときは文字を出さずに流すこと、
    KeyDown を出したキーにだけ KeyUp を出すこと（D-47）。

  WHY:
    IBus はキーごとに返信を待つ（同期で待つと IME が遅いときにアプリが止まる）。
    待っている間も次のキーは来るので、並べ方を誤ると文字が入れ替わる。実機の IME
    では返信の順番を変えられないので、ここで偽の IME を使って全部の組み合わせを見る。

  実行前提: 無し。
}
program test_ime_keys;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Events,
  PaPiMeLa.Events.Keymap,
  PaPiMeLa.TextInput,
  PaPiMeLa.TextInput.Backend,
  PaPiMeLa.Core;

type
  { FilterKey で Answer を返し、渡された番号を覚える。後で Resolve で答える。 }
  TAsyncIme = class(TPMLNullTextInputBackend)
  public
    Answer : TPMLKeyFilterResult;
    Tickets: array of LongWord;
    function  BackendName: String; override;
    function  Capabilities: TPMLTextInputCapabilities; override;
    function  FilterKey(const AKey: TPMLKeyEventData; AIsRelease: Boolean;
      ATicket: LongWord): TPMLKeyFilterResult; override;
    // AIndex 番目に受けたキーに答える。
    procedure Resolve(AIndex: Integer; AConsumed: Boolean);
  end;

var
  Ime     : TAsyncIme = nil;
  Ctx     : TPMLContext;
  Failures: Integer = 0;

function TAsyncIme.BackendName: String;
begin
  Result := 'async-ime';
end;

function TAsyncIme.Capabilities: TPMLTextInputCapabilities;
begin
  Result := [TPMLTextInputCapability.KeyFilter];
end;

function TAsyncIme.FilterKey(const AKey: TPMLKeyEventData; AIsRelease: Boolean;
  ATicket: LongWord): TPMLKeyFilterResult;
begin
  SetLength(Tickets, Length(Tickets) + 1);
  Tickets[High(Tickets)] := ATicket;
  Result := Answer;
end;

procedure TAsyncIme.Resolve(AIndex: Integer; AConsumed: Boolean);
begin
  FSink.KeyResolved(Tickets[AIndex], AConsumed);
end;

function MakeIme: TPMLTextInputBackend;
begin
  Ime := TAsyncIme.Create;
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

{ 届いたイベントを短い記号の列にする。Da = a の KeyDown、Ua = KeyUp、[a] = TextInput、
  L = WindowFocusLost。 }
function Take: String;
var
  Ev: TPMLEvent;
begin
  Result := '';
  while Ctx.Events.Poll(Ev) do
    case Ev.Kind of
      TPMLEventKind.KeyDown: Result := Result + 'D' + Chr(Ev.Key.Key);
      TPMLEventKind.KeyUp:   Result := Result + 'U' + Chr(Ev.Key.Key);
      TPMLEventKind.TextInput: Result := Result + '[' + Ev.Text + ']';
      TPMLEventKind.WindowFocusLost: Result := Result + 'L';
    end;
end;

const
  EVDEV: array['a'..'h'] of LongWord = (30, 48, 46, 32, 18, 33, 34, 35);

procedure Key(C: Char; ADown: Boolean);
var
  K: TPMLKeyEventData;
  Text: String;
begin
  FillChar(K, SizeOf(K), 0);
  K.Scancode := PMLScancodeFromEvdev(EVDEV[C]);
  K.Raw := EVDEV[C] + 8;
  Text := '';
  if ADown then
    Text := C;
  Ctx.Events.Keyboard.SendKey(1, K, ADown, Text);
end;

var
  Opts: TPMLContextOptions;
  S   : String;
  Consumed0: Integer;
begin
  WriteLn('test_ime_keys — IME の返信を待つキーの並び');
  WriteLn;
  PMLRegisterTextInputBackend('async-ime', 1, @MakeIme);
  Opts := TPMLContextOptions.Default;
  Opts.PreferredTextInput := 'async-ime';
  Ctx := TPMLContext.Create([TPMLSubsystem.TextInput], Opts);
  try
    Ctx.TextInput.Start(nil, nil);
    Ime.Answer := TPMLKeyFilterResult.Deferred;
    Consumed0 := Ctx.Events.Keyboard.ConsumedCount;

    WriteLn('1. 返信の順番が入れ替わっても、届いた順に出す');
    Key('a', True);
    Key('b', True);
    Check(Take = '', '返信が来るまでは何も出さない');
    Check(Ctx.Events.Keyboard.DeferredCount = 2, '2 つ待っている');
    Check((Length(Ime.Tickets) = 2) and (Ime.Tickets[0] <> Ime.Tickets[1]),
      'キーごとに違う番号が IME に渡る');
    Ime.Resolve(1, False);
    Check(Take = '', 'b が先に解決しても、a を待つ');
    Ime.Resolve(0, True);
    S := Take;
    Check(S = 'Db[b]', 'a（消費）が解決すると、b の KeyDown と文字が出る（' + S + '）');
    Check(Ctx.Events.Keyboard.DeferredCount = 0, '待ちは空');

    WriteLn;
    WriteLn('2. KeyUp は KeyDown を出したキーにだけ出す（D-47）');
    Key('a', False);
    Key('b', False);
    Ime.Resolve(3, True);
    Ime.Resolve(2, False);
    S := Take;
    Check(S = 'Ub', '押すほうが消費された a の KeyUp は出さず、b は離すほうが消費されても出す（' + S + '）');
    Check(not Ctx.Events.Keyboard.IsDown[PMLScancodeFromEvdev(EVDEV['a'])],
      '押下状態は物理的な状態（a は離れている）');

    WriteLn;
    WriteLn('3. すぐ結果の出たキーも、待っているキーを追い越さない');
    Key('c', True);                                   // 番号 4: 待つ
    Ime.Answer := TPMLKeyFilterResult.PassThrough;
    Key('d', True);                                   // 番号 5: すぐ素通し
    Check(Take = '', 'd は結果が出ていても c を待つ');
    Ime.Resolve(4, False);
    S := Take;
    Check(S = 'Dc[c]Dd[d]', 'c が解決すると c、d の順（' + S + '）');
    Ime.Answer := TPMLKeyFilterResult.Consumed;
    Key('c', False);
    Key('d', False);
    S := Take;
    Check(S = 'UcUd', '待ちが無ければ、すぐ結果の出たキーはその場で出る（' + S + '）');

    WriteLn;
    WriteLn('4. 返信が来なければ打ち切って、消費されなかったものとして出す');
    Ime.Answer := TPMLKeyFilterResult.Deferred;
    Key('e', True);                                   // 番号 8
    Ctx.Events.Keyboard.ExpireDeferred(PMLNowNS, Int64(10) * 1000 * 1000 * 1000);
    Check(Take = '', '打ち切りの時間より前なら待ち続ける');
    Ctx.Events.Keyboard.ExpireDeferred(PMLNowNS + Int64(3) * 1000 * 1000 * 1000,
      Int64(2) * 1000 * 1000 * 1000);
    S := Take;
    Check(S = 'De[e]', '時間を過ぎたら KeyDown と文字を出す（' + S + '）');
    Ime.Resolve(8, True);
    Check((Take = '') and (Ctx.Events.Keyboard.DeferredCount = 0), '後から来た返信は捨てる');
    Ime.Answer := TPMLKeyFilterResult.PassThrough;
    Key('e', False);
    Check(Take = 'Ue', 'e を離す');

    WriteLn;
    WriteLn('5. フォーカスを失ったら、待っているキーを文字なしで出してから離す');
    Ime.Answer := TPMLKeyFilterResult.Deferred;
    Key('f', True);
    Ctx.Events.Keyboard.SendFocus(1, False);
    S := Take;
    Check(S = 'DfUfL', 'KeyDown（文字なし）→ KeyUp → WindowFocusLost（' + S + '）');
    Key('f', False);
    Check(Take = '', '実際の KeyUp は捨てる（もう離してある）');

    WriteLn;
    WriteLn('6. セッションを止めたら、待っているキーを文字なしで出す');
    Ctx.TextInput.Start(nil, nil);
    Key('g', True);
    Check(Take = '', '待っている');
    Ctx.TextInput.Stop;
    S := Take;
    Check(S = 'Dg', 'Stop で KeyDown だけ出る（' + S + '）');
    Key('h', True);
    S := Take;
    Check(S = 'Dh[h]', 'セッションが無ければ IME を通らない（' + S + '）');

    WriteLn;
    WriteLn('7. 数');
    Check(Ctx.Events.Keyboard.ConsumedCount - Consumed0 = 4,
      Format('消費されたのは a の押す・b の離す・c d の離す の 4 回（%d）',
        [Ctx.Events.Keyboard.ConsumedCount - Consumed0]));
    Check(Ctx.Events.DroppedCount = 0, 'イベントの取りこぼしなし');
  finally
    Ctx.Free;
  end;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: IME の返信を待つキーが届いた順に、釣り合った KeyDown / KeyUp で出る ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
