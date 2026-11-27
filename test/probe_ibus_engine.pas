{
  probe_ibus_engine — IBus のエンジンが送ってくるプリエディットの属性・候補・ForwardKeyEvent を記録する（診断。検査ではない）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    環境変数 PROBE_KEYS のキーの並びを打って、そのたびに届いたイベント（TextEditing の文節、
    TextEditingCandidates、KeyDown / KeyUp、TextInput）と、バックエンドが覚えた生の記録
    （PreeditLog: UpdatePreeditText ごとの文字列と属性 型:値:開始-終了、LookupLog: 候補の信号、
    ForwardedKeyCount）を表示する。いつも終了コード 0（記録するだけで、合否を持たない）。
    キーの書き方: 小文字 = そのキー、大文字 = Shift つき、<SP> <RET> <BS> <ESC> <TAB>。

  WHY:
    ibus-mozc 以外のエンジン（ibus-anthy・ibus-skk・ibus-libpinyin・ibus-hangul など）が
    プリエディットにどの属性（下線・背景・前景）を付けるかは未実測だった（設計 §10 項目 1）。
    TPMLIBusSegmenter の規則が mozc の形だけに合わせてあるなら、他のエンジンで文節が崩れる。
    本物のエンジンに打たせて、生の値を見てから規則を直し、検査にする。

  実行前提: ibus-session の中で、IBUS_ENGINE に使うエンジンを指定して（例: IBUS_ENGINE=anthy）。
}
program probe_ibus_engine;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Properties,
  PaPiMeLa.Events,
  PaPiMeLa.Events.Keymap,
  PaPiMeLa.TextInput,
  PaPiMeLa.Core,
  PaPiMeLa.TextInput.IBus,
  PaPiMeLa.Backends;

type
  TFakeEditor = class(TObject, IPMLTextInputClient)
  public
    function GetSurroundingText(out AText: String;
      out ACursorByte, AAnchorByte: Integer): Boolean;
    function GetCursorRect: TPMLRect;
  end;

function TFakeEditor.GetSurroundingText(out AText: String;
  out ACursorByte, AAnchorByte: Integer): Boolean;
begin
  AText := '';
  ACursorByte := 0;
  AAnchorByte := 0;
  Result := True;
end;

function TFakeEditor.GetCursorRect: TPMLRect;
begin
  Result := TPMLRect.Make(100, 200, 2, 18);
end;

const
  EVDEV: array['a'..'z'] of LongWord = (
    30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50,
    49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44);

var
  Ctx: TPMLContext;
  Editor: TFakeEditor;

function SegState(S: TPMLSegmentState): String;
begin
  Result := IntToStr(Ord(S));
end;

procedure Show(const Ev: TPMLEvent);
var
  I: Integer;
  S: String;
begin
  case Ev.Kind of
    TPMLEventKind.TextEditing:
      begin
        S := '';
        for I := 0 to High(Ev.Segments) do
          S := S + Format(' (%d-%d st=%s ul=%d)', [Ev.Segments[I].StartChar, Ev.Segments[I].EndChar,
            SegState(Ev.Segments[I].State), Ord(Ev.Segments[I].Underline)]);
        WriteLn(Format('    編集中 [%s]%s 注目=%d', [Ev.Text, S, Ev.Edit.FocusedSegment]));
      end;
    TPMLEventKind.TextEditingCandidates:
      begin
        S := '';
        for I := 0 to High(Ev.Strings) do
          S := S + ' [' + Ev.Strings[I] + ']';
        WriteLn(Format('    候補 選択=%d%s', [Ev.Edit.FocusedSegment, S]));
      end;
    TPMLEventKind.TextInput: WriteLn('    確定 [', Ev.Text, ']');
    TPMLEventKind.KeyDown: WriteLn(Format('    KeyDown sym=%x raw=%d', [Ev.Key.Keysym, Ev.Key.Raw]));
    TPMLEventKind.KeyUp: WriteLn(Format('    KeyUp sym=%x raw=%d', [Ev.Key.Keysym, Ev.Key.Raw]));
  end;
end;

procedure Settle(AMs: Integer = 600);
var
  Start: QWord;
  Ev: TPMLEvent;
begin
  Start := GetTickCount64;
  repeat
    Ctx.Events.Pump(10);
    while Ctx.Events.Poll(Ev) do
      Show(Ev);
  until ((Ctx.Events.Keyboard.DeferredCount = 0) and (GetTickCount64 - Start >= 150))
    or (GetTickCount64 - Start >= QWord(AMs));
  Ctx.Events.Pump(50);
  while Ctx.Events.Poll(Ev) do
    Show(Ev);
end;

procedure Tap(AKeysym, AEvdev: LongWord; AShift: Boolean; const AText: String);
var
  K: TPMLKeyEventData;
begin
  FillChar(K, SizeOf(K), 0);
  K.Keysym := AKeysym;
  K.Raw := AEvdev + 8;
  K.Scancode := PMLScancodeFromEvdev(AEvdev);
  if AShift then
    K.Modifiers := [TPMLKeyModifier.Shift];
  Ctx.Events.Keyboard.SendKey(1, K, True, AText);
  Ctx.Events.Keyboard.SendKey(1, K, False, '');
end;

procedure TypeKeys(const AKeys: String);
var
  I: Integer;
  C: Char;
  Name: String;
begin
  I := 1;
  while I <= Length(AKeys) do
  begin
    C := AKeys[I];
    if C = '<' then
    begin
      Name := Copy(AKeys, I, Pos('>', Copy(AKeys, I, Length(AKeys))));
      Inc(I, Length(Name));
      WriteLn('  キー ', Name);
      if Name = '<SP>' then Tap($20, 57, False, ' ')
      else if Name = '<RET>' then Tap($FF0D, 28, False, '')
      else if Name = '<BS>' then Tap($FF08, 14, False, '')
      else if Name = '<ESC>' then Tap($FF1B, 1, False, '')
      else if Name = '<TAB>' then Tap($FF09, 15, False, '')
      else WriteLn('  （知らないキー: ', Name, '）');
    end
    else
    begin
      Inc(I);
      WriteLn('  キー ', C);
      if C in ['a'..'z'] then
        Tap(Ord(C), EVDEV[C], False, C)
      else if C in ['A'..'Z'] then
        Tap(Ord(C), EVDEV[Chr(Ord(C) + 32)], True, C)
      else
        WriteLn('  （知らないキー: ', C, '）');
    end;
    Settle;
  end;
end;

var
  Opts: TPMLContextOptions;
  Session: TPMLTextInputSession;
  IB: TPMLIBusTextInputBackend;
  Keys: String;
begin
  Keys := GetEnvironmentVariable('PROBE_KEYS');
  WriteLn('=== probe_ibus_engine: エンジン=', GetEnvironmentVariable('IBUS_ENGINE'), ' キー=', Keys);
  Opts := TPMLContextOptions.Default;
  Opts.PreferredTextInput := 'ibus';
  Opts.Hints.Add(PML_HINT_IME_IMPLEMENTED_UI, 'composition,candidates');
  try
    Ctx := TPMLContext.Create([TPMLSubsystem.TextInput], Opts);
  except
    on E: EPMLError do
    begin
      WriteLn('Context を作れない: ', E.Message);
      Exit;
    end;
  end;
  Editor := TFakeEditor.Create;
  try
    IB := Ctx.TextInput.BackendInstance as TPMLIBusTextInputBackend;
    Session := Ctx.TextInput.Start(nil, Editor as IPMLTextInputClient);
    Session.NotifyCursorRectChanged;
    Settle(500);
    TypeKeys(Keys);
    WriteLn;
    WriteLn('--- PreeditLog（文字列 { 型:値:開始-終了 } cursor）');
    Write(IB.PreeditLog);
    WriteLn('--- LookupLog');
    WriteLn(IB.LookupLog);
    WriteLn('--- ForwardKeyEvent を受けた数: ', IB.ForwardedKeyCount);
    WriteLn('--- 最後の致命的でない誤り: [', IB.LastNonFatalError, ']');
    Session.ResetComposition;
    Settle(200);
  finally
    FreeAndNil(Ctx);
    FreeAndNil(Editor);
  end;
end.
