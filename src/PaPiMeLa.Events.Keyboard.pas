{
  PaPiMeLa.Events.Keyboard — キーボードの状態機械の中身（押下状態・IME の返信待ち・キーコードの決め方）

  Origin : partially ported from SDL (src/events/SDL_keyboard.c)
           Scope: 押下状態の規則（押されていないキーの KeyUp は捨てる、押されているキーの
           KeyDown はリピートにする、フォーカスを失ったら押されているキーをすべて離す）、
           キーコードのオプション（SDL_HINT_KEYCODE_OPTIONS。hide_numpad のときのテンキーの
           読み替え）。SDL_SendKeyboardKeyInternal / SDL_ResetKeyboard /
           SDL_GetKeyFromScancode / SDL_KeycodeOptionsChanged に当たる。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #24

  WHAT:
    公開の TPMLKeyboardState（PaPiMeLa.Events。バックエンドが呼ぶ窓口）の中身。
    押下状態（IsDown）、修飾キー、フォーカスのあるウィンドウ、キーマップ、キーコードの
    オプションを持ち、IME の返信待ちのキー（TPMLDeferredKeyQueue）を届いた順に出す。

  WHY:
    PaPiMeLa.Events はクリーンルームのユニット。ここは SDL のソースを読んで写した部分
    なので、由来を分けるためにユニットを分けた。TPMLKeyboardState は PaPiMeLa.Events の
    implementation から TPMLKeyboardImpl を作って持ち、全ての呼び出しをここへ渡す。
    IME の返信待ちの列（TPMLDeferredKey / TPMLDeferredKeyQueue。D-47）は papimela 独自
    なので PaPiMeLa.Events に残してある。

  RESOLVED:
    - イベントキューへは TPMLEventQueue の公開メンバー（Push / PushSimple / KeyFilter）
      だけで届く
    - SDL から意図して変えた箇所（IME が消費したキーの扱い、KeyUp を KeyDown を出した
      キーにだけ出すこと）は各メソッドの PORT-NOTE に書いた

  NOT RESOLVED:
    - 仮想キーボードのスキャンコードの割り当て（PaPiMeLa.Events.Keymap の NOT RESOLVED を参照）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Events.Keyboard;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Properties,
  PaPiMeLa.Keycodes,
  PaPiMeLa.Events.Keymap,
  PaPiMeLa.Events;

type
  { TPMLKeyboardState の中身。

    WHAT:
      キーボードの状態機械の本体。公開側の TPMLKeyboardState の各メソッドはここへ渡す。

    WHY:
      由来が移植の部分を、クリーンルームの PaPiMeLa.Events から分けるため。

    PORT-NOTE: 押下状態の規則は SDL_keyboard.c の SDL_SendKeyboardKeyInternal と
    SDL_ResetKeyboard に従う。押されていないキーの KeyUp は捨てる。押されている
    キーの KeyDown はリピートにする。フォーカスを失ったら、押されているキーを
    すべて KeyUp にしてから WindowFocusLost を積む。こうしないと、別のウィンドウで
    離したキーがこちらでは押されたまま残る。

    KeyUp は KeyDown を出したキーにだけ出す（D-47）。IME は押すほうを消費しても
    離すほうは消費しないことが多い（fcitx5-mozc・ibus-mozc とも実測）。逆に
    KeyDown を出した後で離すほうが消費されても KeyUp は出す。アプリから見て
    押したまま残らないようにする。 }
  TPMLKeyboardImpl = class
  strict private
    FQueue     : TPMLEventQueue;
    FHints     : TPMLHints;
    FModifiers : TPMLKeyModifiers;
    FFocusedWindow: TPMLWindowID;
    FConsumed  : Integer;
    FDown      : array[TPMLScancode] of Boolean;
    FEmittedDown: array[TPMLScancode] of Boolean;   // KeyDown をアプリへ出した
    FDeferred  : TPMLDeferredKeyQueue;
    FNextTicket: LongWord;
    FKeymap    : TPMLKeymap;
    FKeycodeOptions: TPMLKeycodeOptions;
    procedure ReleaseAll(AWindowID: TPMLWindowID);
    procedure Emit(const AItem: TPMLDeferredKey; AWithText: Boolean);
    procedure Drain;
    // ヒント PAPIMELA_KEYCODE_OPTIONS の変更（SDL_KeycodeOptionsChanged）。
    procedure KeycodeOptionsChanged(const AName: String; const AOld, ANew: TPMLHintValue);
    // SDL_GetKeyFromScancode（key_event = true）。AModifiers は NumLock の判定に使う。
    function  KeyForScancode(AScancode: TPMLScancode; AModifiers: TPMLKeyModifiers): TPMLKeycode;
  public
    // AHints は nil でもよい（nil ならヒントを見ない）。借用で、所有しない。
    constructor Create(AQueue: TPMLEventQueue; AHints: TPMLHints);
    destructor Destroy; override;
    function  GetIsDown(AScancode: TPMLScancode): Boolean;
    procedure SendKey(AWindowID: TPMLWindowID; const AKey: TPMLKeyEventData;
      ADown: Boolean; const AText: String);
    procedure SendModifiers(AModifiers: TPMLKeyModifiers);
    procedure SendFocus(AWindowID: TPMLWindowID; AGained: Boolean);
    procedure SetKeymap(AKeymap: TPMLKeymap);
    procedure ResolveKey(ATicket: LongWord; AConsumed: Boolean);
    procedure FlushDeferred;
    procedure ExpireDeferred(ANowNS, ATimeoutNS: Int64);
    function  DeferredCount: Integer;
    property Keymap        : TPMLKeymap read FKeymap;
    property KeycodeOptions: TPMLKeycodeOptions read FKeycodeOptions write FKeycodeOptions;
    property Modifiers     : TPMLKeyModifiers read FModifiers;
    property FocusedWindow : TPMLWindowID read FFocusedWindow;
    property ConsumedCount : Integer read FConsumed;
  end;

implementation

constructor TPMLKeyboardImpl.Create(AQueue: TPMLEventQueue; AHints: TPMLHints);
begin
  inherited Create;
  FQueue := AQueue;
  FHints := AHints;
  // 配列が届くまでは空のキーマップ。空は既定（US 配列）と同じ意味になる。
  FKeymap := TPMLKeymap.Create;
  FKeycodeOptions := PML_DEFAULT_KEYCODE_OPTIONS;
  FDeferred := TPMLDeferredKeyQueue.Create;
  FNextTicket := 1;
  // SDL_InitKeyboard と同じ。ヒントを見て FKeycodeOptions を決める
  // （AddCallback はその場で 1 度呼ぶので、作った時点の値が入る）。
  if FHints <> nil then
    FHints.AddCallback(PML_HINT_KEYCODE_OPTIONS, @KeycodeOptionsChanged);
end;

destructor TPMLKeyboardImpl.Destroy;
begin
  // 何かを壊す前に外す（ヒントの変更がここへ届かないように）。
  if FHints <> nil then
    FHints.RemoveCallback(PML_HINT_KEYCODE_OPTIONS, @KeycodeOptionsChanged);
  FreeAndNil(FDeferred);
  FreeAndNil(FKeymap);
  inherited Destroy;
end;

function TPMLKeyboardImpl.GetIsDown(AScancode: TPMLScancode): Boolean;
begin
  Result := FDown[AScancode];
end;

procedure TPMLKeyboardImpl.KeycodeOptionsChanged(const AName: String;
  const AOld, ANew: TPMLHintValue);
begin
  // 置かれていないヒントの Value は ''（PMLParseKeycodeOptions は既定を返す）。
  FKeycodeOptions := PMLParseKeycodeOptions(ANew.Value);
end;

{ SDL_GetKeyFromScancode（key_event = true）。キーマップから決めた後に、hide_numpad なら
  テンキーのキーコードを置き換える。 }
function TPMLKeyboardImpl.KeyForScancode(AScancode: TPMLScancode;
  AModifiers: TPMLKeyModifiers): TPMLKeycode;
begin
  Result := FKeymap.KeyForEvent(AScancode, FKeycodeOptions);
  if TPMLKeycodeOption.HideNumpad in FKeycodeOptions then
    Result := PMLConvertNumpadKeycode(Result, TPMLKeyModifier.NumLock in AModifiers);
end;

function TPMLKeyboardImpl.DeferredCount: Integer;
begin
  Result := FDeferred.Count;
end;

procedure TPMLKeyboardImpl.SetKeymap(AKeymap: TPMLKeymap);
begin
  if (AKeymap = nil) or (AKeymap = FKeymap) then
    Exit;
  AKeymap.DetectLayout;
  FKeymap.Free;
  FKeymap := AKeymap;
  FQueue.PushSimple(TPMLEventKind.KeymapChanged, 0);
end;

{ 押されているキーをすべて離す（SDL_ResetKeyboard）。KeyUp は KeyDown を出した
  キーにだけ出す。IME には通さない。フォーカスを失う IME には別に NotifyFocus が届く。 }
procedure TPMLKeyboardImpl.ReleaseAll(AWindowID: TPMLWindowID);
var
  S: TPMLScancode;
  Ev: TPMLEvent;
begin
  for S := Low(TPMLScancode) to High(TPMLScancode) do
  begin
    FDown[S] := False;
    if FEmittedDown[S] then
    begin
      FEmittedDown[S] := False;
      FillChar(Ev.Key, SizeOf(Ev.Key), 0);
      Ev.Kind := TPMLEventKind.KeyUp;
      Ev.Timestamp := PMLNowNS;
      Ev.WindowID := AWindowID;
      Ev.Text := '';
      Ev.Segments := nil;
      Ev.Strings := nil;
      Ev.Key.Scancode := S;
      Ev.Key.Key := KeyForScancode(S, FModifiers);
      Ev.Key.Modifiers := FModifiers;
      FQueue.Push(Ev);
    end;
  end;
end;

procedure TPMLKeyboardImpl.SendModifiers(AModifiers: TPMLKeyModifiers);
begin
  FModifiers := AModifiers;
end;

procedure TPMLKeyboardImpl.SendFocus(AWindowID: TPMLWindowID; AGained: Boolean);
begin
  // IME にも伝える。フォーカスを失ったまま IME がこちらを注目し続けると、
  // 別アプリと二重にフォーカスを持つ状態になる。
  if Assigned(FQueue.KeyFilter) then
    FQueue.KeyFilter.NotifyFocus(AWindowID, AGained);

  if AGained then
  begin
    FFocusedWindow := AWindowID;
    FQueue.PushSimple(TPMLEventKind.WindowFocusGained, AWindowID);
  end
  else
  begin
    // 返信を待っているキーを先に出す（順序を保つ）。その後、離したキーの KeyUp は
    // フォーカスを失った後は届かないので、押されているキーを全部離す。
    FlushDeferred;
    ReleaseAll(AWindowID);
    if FFocusedWindow = AWindowID then
      FFocusedWindow := 0;
    FQueue.PushSimple(TPMLEventKind.WindowFocusLost, AWindowID);
  end;
end;

{ 結果の出たキー 1 つをアプリへ出す。

  押す: 消費されたら何も出さない。されなければ KeyDown と（あれば）TextInput。
  離す: KeyDown を出したキーなら、IME の結果によらず KeyUp を出す（D-47）。 }
procedure TPMLKeyboardImpl.Emit(const AItem: TPMLDeferredKey; AWithText: Boolean);
var
  Ev: TPMLEvent;
  Known: Boolean;
begin
  if AItem.Consumed then
    Inc(FConsumed);
  Known := AItem.Key.Scancode <> TPMLScancode.UNKNOWN;
  if AItem.Down then
  begin
    if AItem.Consumed then
      Exit;
    if Known then
      FEmittedDown[AItem.Key.Scancode] := True;
  end
  else if Known then
  begin
    if not FEmittedDown[AItem.Key.Scancode] then
      Exit;
    FEmittedDown[AItem.Key.Scancode] := False;
  end
  else if AItem.Consumed then
    Exit;

  FillChar(Ev.Key, SizeOf(Ev.Key), 0);
  if AItem.Down then
    Ev.Kind := TPMLEventKind.KeyDown
  else
    Ev.Kind := TPMLEventKind.KeyUp;
  Ev.Timestamp := PMLNowNS;
  Ev.WindowID := AItem.WindowID;
  Ev.Text := '';
  Ev.Segments := nil;
  Ev.Strings := nil;
  Ev.Key := AItem.Key;
  FQueue.Push(Ev);

  // IME が受け取らなかった印字可能キーは、こちらで確定文字列にする。
  if AItem.Down and AWithText and (AItem.Text <> '') then
  begin
    FillChar(Ev.Key, SizeOf(Ev.Key), 0);
    Ev.Kind := TPMLEventKind.TextInput;
    Ev.Timestamp := PMLNowNS;
    Ev.WindowID := AItem.WindowID;
    Ev.Text := AItem.Text;
    Ev.Segments := nil;
    Ev.Strings := nil;
    FQueue.Push(Ev);
  end;
end;

{ 先頭から、結果の出ているキーを順に出す。未解決のキーに当たったら止める。 }
procedure TPMLKeyboardImpl.Drain;
var
  Item: TPMLDeferredKey;
begin
  while FDeferred.PopResolved(Item) do
    Emit(Item, True);
end;

procedure TPMLKeyboardImpl.ResolveKey(ATicket: LongWord; AConsumed: Boolean);
begin
  if FDeferred.Resolve(ATicket, AConsumed) then
    Drain;
end;

procedure TPMLKeyboardImpl.FlushDeferred;
var
  Item: TPMLDeferredKey;
begin
  while FDeferred.Pop(Item) do
    if Item.Resolved then
      Emit(Item, True)
    else
    begin
      Item.Consumed := False;
      Emit(Item, False);
    end;
end;

procedure TPMLKeyboardImpl.ExpireDeferred(ANowNS, ATimeoutNS: Int64);
begin
  if FDeferred.Count = 0 then
    Exit;
  if FDeferred.ExpireBefore(ANowNS - ATimeoutNS) > 0 then
    Drain;
end;

{ §7.5 の経路。

  1. IME が有効なら、押下も解放も IME に通す（修飾キー単独押下もエンジンが
     モード切替に使うため通す）
  2. 結果がすぐ出れば（Consumed / PassThrough）、待っているキーが無い限りその場で出す
  3. Deferred（非同期の返信待ち）なら並べて、ResolveKey を待つ。待っているキーが
     あれば、すぐ結果の出たキーもその後ろに並べる（順序を保つ） }
procedure TPMLKeyboardImpl.SendKey(AWindowID: TPMLWindowID;
  const AKey: TPMLKeyEventData; ADown: Boolean; const AText: String);
var
  Item: TPMLDeferredKey;
  Filtered: TPMLKeyFilterResult;
  PrevModifiers: TPMLKeyModifiers;
begin
  // hide_numpad の NumLock は、SDL と同じくこのキーより前の状態（SDL の keyboard->modstate）で
  // 見る。バックエンドは SendModifiers で状態を先に伝える。
  PrevModifiers := FModifiers;
  FModifiers := AKey.Modifiers;
  Item.Key := AKey;

  // 押下状態。IME に通す前に更新する（消費されたキーも物理的には押されている）。
  if Item.Key.Scancode <> TPMLScancode.UNKNOWN then
  begin
    if ADown then
    begin
      if FDown[Item.Key.Scancode] then
        Item.Key.IsRepeat := True;
    end
    else if not FDown[Item.Key.Scancode] then
      // 押されていないキーの KeyUp は捨てる。フォーカスを失ったときに
      // ReleaseAll が離したキーの、実際の KeyUp がここへ来る。
      Exit;
    FDown[Item.Key.Scancode] := ADown;
    if Item.Key.Key = PMLK_UNKNOWN then
      Item.Key.Key := KeyForScancode(Item.Key.Scancode, PrevModifiers);
  end;

  Item.Ticket := FNextTicket;
  Inc(FNextTicket);
  if FNextTicket = 0 then
    FNextTicket := 1;
  Item.WindowID := AWindowID;
  Item.Down := ADown;
  Item.Text := AText;
  Item.SinceNS := PMLNowNS;
  Item.Resolved := True;
  Item.Consumed := False;

  if Assigned(FQueue.KeyFilter) and FQueue.KeyFilter.KeyFilterActive then
  begin
    Filtered := FQueue.KeyFilter.FilterKey(Item.Key, not ADown, Item.Ticket);
    case Filtered of
      TPMLKeyFilterResult.Consumed: Item.Consumed := True;
      TPMLKeyFilterResult.Deferred: Item.Resolved := False;
    else
    end;
  end;

  if Item.Resolved and (FDeferred.Count = 0) then
    Emit(Item, True)
  else
  begin
    FDeferred.Add(Item);
    Drain;
  end;
end;

end.
