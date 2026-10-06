{
  test_wayland_clipboard — クリップボードとプライマリ選択を実機のコンポジタで確かめる

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    papimela が置いたものを他のアプリ（wl-paste）が読めること、他のアプリ（wl-copy）が
    置いたものを papimela が読めること、を文字列・大きなデータ・任意の MIME タイプ・
    プライマリ選択で見る。自分の置いたものの折り返しを「他のアプリ」と取り違えないこと、
    消したら他のアプリから見えなくなること。

  WHY:
    クリップボードの受け渡しはパイプで、相手が読む（書く）のを待つ。片方が
    イベントを回していないと止まる、大きいと途中で切れる、といった誤りは
    実際に別のプロセスとやり取りして初めて分かる。

  実行前提: Wayland セッション（labwc で確認）、wl-clipboard（wl-copy / wl-paste）。
            作ったウィンドウにキーボードのフォーカスが来ること（選択を置くにも、他の
            アプリの選択を受け取るにも要る）。
            **手元のクリップボードとプライマリ選択を書き換える。** 始めに文字列を
            取っておき、終わりに戻す（文字列以外の中身は戻らない）。
}
program test_wayland_clipboard;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Classes, Process,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Clipboard,
  PaPiMeLa.Core,
  PaPiMeLa.Backends;

type
  TProvider = class(TObject, IPMLClipboardDataProvider)
  public
    Data     : TBytes;
    Asked    : Integer;
    Cancelled: Integer;
    function  GetClipboardData(const AMimeType: String; out AData: TBytes): Boolean;
    procedure ClipboardDataCancelled;
  end;

var
  Ctx     : TPMLContext;
  Failures: Integer = 0;
  Focused : Boolean = False;
  Updates : String = '';

function TProvider.GetClipboardData(const AMimeType: String; out AData: TBytes): Boolean;
begin
  Inc(Asked);
  AData := Copy(Data);
  Result := True;
end;

procedure TProvider.ClipboardDataCancelled;
begin
  Inc(Cancelled);
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

procedure Drain;
var
  Ev: TPMLEvent;
begin
  while Ctx.Events.Poll(Ev) do
    case Ev.Kind of
      TPMLEventKind.WindowFocusGained: Focused := True;
      TPMLEventKind.WindowFocusLost:   Focused := False;
      TPMLEventKind.ClipboardUpdate:
        begin
          if Ev.Clipboard.Owner then Updates := Updates + 'o' else Updates := Updates + 'x';
          if Ev.Clipboard.PrimarySelection then Updates := Updates + 'p';
          Updates := Updates + ' ';
        end;
    end;
end;

procedure PumpFor(AMs: Integer);
var
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + QWord(AMs);
  repeat
    Ctx.Events.Pump(10);
    Drain;
  until GetTickCount64 >= Deadline;
end;

{ 外のコマンドを動かし、終わるまでイベントを回し続ける（相手は papimela がデータを
  書くのを待つので、ここで止まって待つと両方が止まる）。標準出力は溜まると相手が
  止まるので、回しながら読む。標準入力に AInput を渡す（空なら閉じるだけ）。 }
function RunPumping(const AExe: String; const AArgs: array of String;
  const AInput: String; out AOutput: String; ATimeoutMs: Integer = 10000): Integer;
var
  P: TProcess;
  Buf: array[0..65535] of Byte;
  N: Integer;
  Deadline: QWord;
  Out: TMemoryStream;
  S: String;
begin
  AOutput := '';
  P := TProcess.Create(nil);
  Out := TMemoryStream.Create;
  try
    P.Executable := AExe;
    for S in AArgs do
      P.Parameters.Add(S);
    P.Options := [poUsePipes];
    P.Execute;
    if AInput <> '' then
      P.Input.WriteBuffer(AInput[1], Length(AInput));
    P.CloseInput;
    Deadline := GetTickCount64 + QWord(ATimeoutMs);
    repeat
      Ctx.Events.Pump(5);
      Drain;
      while P.Output.NumBytesAvailable > 0 do
      begin
        N := P.Output.Read(Buf, SizeOf(Buf));
        if N <= 0 then
          Break;
        Out.WriteBuffer(Buf, N);
      end;
    until (not P.Running) or (GetTickCount64 > Deadline);
    if P.Running then
    begin
      P.Terminate(124);
      Result := 124;
    end
    else
      Result := P.ExitStatus;
    // 終わった後は溜まっている分だけ読む。EOF までは待たない: wl-copy は裏に回った子が
    // 標準出力を握ったままなので、EOF は来ない（実測。待つと止まる）。
    while P.Output.NumBytesAvailable > 0 do
    begin
      N := P.Output.Read(Buf, SizeOf(Buf));
      if N <= 0 then
        Break;
      Out.WriteBuffer(Buf, N);
    end;
    SetLength(AOutput, Out.Size);
    if Out.Size > 0 then
      Move(Out.Memory^, AOutput[1], Out.Size);
  finally
    Out.Free;
    P.Free;
  end;
end;

{ wl-copy は自分で裏に回ってデータを配り続ける。終わるのを待ってから、選択が
  papimela に届くまで回す。 }
function ExternalCopy(const AArgs: array of String; const AInput: String): Boolean;
var
  O: String;
begin
  Updates := '';
  Result := RunPumping('wl-copy', AArgs, AInput, O) = 0;
  PumpFor(300);
end;

function BytesOf(const S: String): TBytes;
begin
  SetLength(Result, Length(S));
  if Length(S) > 0 then
    Move(S[1], Result[0], Length(S));
end;

function StrOf(const B: TBytes): String;
begin
  SetLength(Result, Length(B));
  if Length(B) > 0 then
    Move(B[0], Result[1], Length(B));
end;

var
  Opts: TPMLContextOptions;
  Win : TPMLWindow;
  C   : TPMLClipboard;
  P   : TProvider;
  Saved, SavedPrimary, O, Big, Bin: String;
  HadSaved, HadSavedPrimary: Boolean;
  D   : TBytes;
  I   : Integer;
  Mimes: String;
begin
  WriteLn('test_wayland_clipboard — クリップボードを実機で');
  WriteLn;
  Opts := TPMLContextOptions.Default;
  Opts.PreferredVideo := 'wayland';
  Ctx := TPMLContext.Create([TPMLSubsystem.Video], Opts);
  P := TProvider.Create;
  // 手元の選択を取っておく（wl-paste は papimela と関係なく動くので、ここは待たない）。
  HadSaved := RunCommand('wl-paste', ['-n'], Saved, [], swoNone);
  HadSavedPrimary := RunCommand('wl-paste', ['-p', '-n'], SavedPrimary, [], swoNone);
  try
    WriteLn('1. 準備');
    Check(TPMLVideoCapability.Clipboard in Ctx.Video.Capabilities, '能力 Clipboard がある');
    Check(TPMLVideoCapability.PrimarySelection in Ctx.Video.Capabilities,
      '能力 PrimarySelection がある（labwc は primary-selection を広告する）');
    C := Ctx.Video.Clipboard;
    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('clipboard', 240, 80));
    for I := 1 to 100 do
    begin
      PumpFor(20);
      if Focused then
        Break;
    end;
    Check(Focused, 'ウィンドウにフォーカスが来た');
    PumpFor(200);

    WriteLn;
    WriteLn('2. papimela が置き、wl-paste が読む');
    Updates := '';
    C.Text := 'papimela クリップボード ✓';
    Check(RunPumping('wl-paste', ['-n'], '', O) = 0, 'wl-paste が終わった');
    Check(O = 'papimela クリップボード ✓', '文字列が渡る: "' + O + '"');
    RunPumping('wl-paste', ['--list-types'], '', Mimes);
    // 上の文字列が渡っていなければ、一覧は手元の別のアプリのもの。それで通さない。
    Check((O = 'papimela クリップボード ✓') and (Pos('text/plain;charset=utf-8', Mimes) > 0) and (Pos('UTF8_STRING', Mimes) > 0),
      '文字列の MIME タイプを配る: ' + StringReplace(Mimes, #10, ' ', [rfReplaceAll]));
    PumpFor(200);
    Check((O = 'papimela クリップボード ✓') and C.IsOwner and (Pos('x', Updates) = 0),
      '自分の置いたものの折り返しを他のアプリと取り違えない（' + Trim(Updates) + '）');

    Big := '';
    SetLength(Big, 1024 * 1024);
    for I := 1 to Length(Big) do
      Big[I] := Chr(Ord('a') + (I mod 26));
    C.Text := Big;
    Check((RunPumping('wl-paste', ['-n'], '', O) = 0) and (O = Big),
      Format('1 MiB の文字列が切れずに渡る（%d バイト）', [Length(O)]));

    Bin := '';
    for I := 0 to 255 do
      Bin := Bin + Chr(I);
    P.Data := BytesOf(Bin);
    C.SetData(['application/x-papimela-test'], P);
    Check((RunPumping('wl-paste', ['-t', 'application/x-papimela-test'], '', O) = 0) and (O = Bin),
      Format('任意の MIME タイプで 0〜255 のバイトが渡る（%d バイト）', [Length(O)]));
    Check(P.Asked >= 1, '提供者が呼ばれた');

    WriteLn;
    WriteLn('3. 消す（他のアプリが置く前に。置いた後は下の 4 の終わりを参照）');
    C.Text := 'to be cleared';
    C.Clear;
    PumpFor(200);
    Check(RunPumping('wl-paste', ['-n'], '', O) <> 0, '消したら wl-paste は何も読めない（"' + O + '"）');
    WriteLn;
    WriteLn('4. wl-copy が置き、papimela が読む');
    Check(ExternalCopy([], 'from outside 外から'), 'wl-copy が置いた');
    Check(Pos('x', Updates) > 0, 'ClipboardUpdate（他のアプリ）が届く: ' + Trim(Updates));
    Check(not C.IsOwner and (P.Cancelled = 1), '持ち主でなくなり、提供者に知らせる');
    Check(C.HasText and (C.Text = 'from outside 外から'), '文字列を受け取る: "' + C.Text + '"');

    Check(ExternalCopy(['-t', 'image/x-papimela'], Bin), 'wl-copy が任意の MIME タイプで置いた');
    Check(C.HasData('image/x-papimela'), 'MimeTypes に相手の MIME タイプがある: ' +
      String.Join(',', C.MimeTypes));
    Check(C.GetData('image/x-papimela', D) and (StrOf(D) = Bin),
      Format('0〜255 のバイトを受け取る（%d バイト）', [Length(D)]));

    Check(ExternalCopy([], Big), 'wl-copy が 1 MiB を置いた');
    O := C.Text;
    Check(O = Big, Format('1 MiB を切れずに受け取る（%d バイト）', [Length(O)]));

    // 他のアプリが置いた後、こちらに入力（キー・ボタン）が無いまま置き直すと、コンポジタは
    // 黙って断る（labwc で実測。断ったという知らせは来ない）。持ち主のふりを続けないこと:
    // 断られたと分かったら持ち主でなくなり、他のアプリの選択を読み続ける。
    Updates := '';
    C.Text := 'set without fresh input';
    PumpFor(500);
    Check(not C.IsOwner, '入力の無いまま置き直して断られたら、持ち主でなくなる');
    Check(C.Text = Big, '断られた後も他のアプリの選択（1 MiB）を読む');
    Check((RunPumping('wl-paste', ['-n'], '', O) = 0) and (O = Big),
      'wl-paste から見ても他のアプリの選択のまま');

    WriteLn;
    WriteLn('5. プライマリ選択');
    C.PrimarySelectionText := 'papimela primary';
    Check((RunPumping('wl-paste', ['-p', '-n'], '', O) = 0) and (O = 'papimela primary'),
      'papimela が置き、wl-paste -p が読む: "' + O + '"');
    Check(ExternalCopy(['-p'], 'primary from outside'), 'wl-copy -p が置いた');
    Check(C.HasPrimarySelectionText and (C.PrimarySelectionText = 'primary from outside'),
      'wl-copy -p が置いたものを読む: "' + C.PrimarySelectionText + '"');
    Check(C.Text = Big, 'プライマリ選択はクリップボードと別');


    Win.Free;
  finally
    // 手元の選択を戻す。wl-copy は裏で配り続ける（いつもの wl-copy と同じ）。
    if HadSaved then
      RunCommand('wl-copy', ['--', Saved], O, [], swoNone)
    else
      RunCommand('wl-copy', ['--clear'], O, [], swoNone);
    if HadSavedPrimary then
      RunCommand('wl-copy', ['-p', '--', SavedPrimary], O, [], swoNone)
    else
      RunCommand('wl-copy', ['-p', '--clear'], O, [], swoNone);
    Ctx.Free;
    P.Free;
  end;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: クリップボードとプライマリ選択が他のアプリと行き来する ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
