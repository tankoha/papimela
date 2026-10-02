{
  test_backends — バックエンドの登録と、リンクされるものの絞り込み（#45）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    このプログラムは PaPiMeLa.Backends を uses しない。具象バックエンドは
    ダミーのビデオ（PaPiMeLa.Video.Dummy）だけを uses する。そのうえで
    1. 登録されているのはダミーだけで、Wayland / Fcitx / GLES2 は
       **実行ファイルにリンクされていない**こと
    2. 名前を指定したときと、しないときの選び方（優先度、登録順、
       Connect に失敗したら次、大文字小文字、同じ名前の 2 度目の登録）
    3. リンクされていない名前を指定したら、何が使えるかを添えて断ること
    を、ビデオ・IME・レンダラの 3 つの登録で確かめる。

  WHY:
    設計 §2.1 は「公開層は具象バックエンドを uses しない。どれを持つかは
    アプリの uses が決める」と決めている。#45 より前は公開層が Wayland と
    Fcitx と GLES2 を直接 uses していて、ダミーしか使わない検査にも全部が
    リンクされていた。リンクされたかどうかは、クラス名が実行ファイルに
    入っているかで見る（クラス名は RTTI として必ず入る）。探す文字列を
    ソースにそのまま書くと、その文字列自体が実行ファイルに入ってしまう
    ので、実行時に組み立てる。

  実行前提: 無し。
}
program test_backends;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Classes, StrUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Events,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Dummy,
  PaPiMeLa.TextInput,
  PaPiMeLa.TextInput.Backend,
  PaPiMeLa.Render,
  PaPiMeLa.Render.Software,
  PaPiMeLa.Core;

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

function Joined(const ANames: TStringArray): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ANames) do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + ANames[I];
  end;
end;

{ ---- 1. リンクされているもの ---- }

var
  ExeImage: String = '';

function ExeContains(const AText: String): Boolean;
var
  F: TFileStream;
begin
  if ExeImage = '' then
  begin
    F := TFileStream.Create(ParamStr(0), fmOpenRead or fmShareDenyNone);
    try
      SetLength(ExeImage, F.Size);
      if F.Size > 0 then
        F.ReadBuffer(ExeImage[1], F.Size);
    finally
      F.Free;
    end;
  end;
  Result := Pos(AText, ExeImage) > 0;
end;

procedure TestLinkage;
begin
  WriteLn('1. リンクされているもの（PaPiMeLa.Backends を uses しない）');
  // 探す名前は逆さに書いて実行時に戻す（ソースの文字列が実行ファイルに入らないように）。
  Check(ExeContains(ReverseString('dnekcaBoediVymmuDLMPT')),
    '確かめ方の確認: uses したダミーのクラス名は実行ファイルにある');
  Check(not ExeContains(ReverseString('dnekcaBoediVdnalyaWLMPT')),
    'Wayland のビデオはリンクされていない');
  Check(not ExeContains(ReverseString('dnekcaBtupnItxeTxticFLMPT')),
    'Fcitx の IME はリンクされていない');
  Check(not ExeContains(ReverseString('revirDredneR2SELGLMPT')),
    'GLES2 のレンダラはリンクされていない');
  Check(Joined(PMLVideoBackendNames) = 'dummy',
    '登録されたビデオはダミーだけ: ' + Joined(PMLVideoBackendNames));
  Check(Joined(PMLTextInputBackendNames) = '',
    '登録された IME は無い: "' + Joined(PMLTextInputBackendNames) + '"');
  Check(Joined(PMLRenderDriverNames) = 'software',
    'レンダラは software だけ: ' + Joined(PMLRenderDriverNames));
  WriteLn;
end;

{ ---- 2. ビデオの登録 ---- }

type
  { ダミーに名前を付け替え、Connect の成否を選べるようにしたもの。 }
  TFakeVideo = class(TPMLDummyVideoBackend)
  public
    FakeName: String;
    Accept  : Boolean;
    function BackendName: String; override;
    function Connect(ASink: IPMLVideoSink): Boolean; override;
  end;

var
  Tried: String = '';     // Connect を試した順

function TFakeVideo.BackendName: String;
begin
  Result := FakeName;
end;

function TFakeVideo.Connect(ASink: IPMLVideoSink): Boolean;
begin
  Tried := Tried + FakeName + ' ';
  Result := Accept and inherited Connect(ASink);
end;

function MakeFake(AContextRef: TObject; AOwner: TPMLObject; const AName: String;
  AAccept: Boolean): TPMLVideoBackend;
var
  F: TFakeVideo;
begin
  F := TFakeVideo.Create(AContextRef, AOwner);
  F.FakeName := AName;
  F.Accept := AAccept;
  Result := F;
end;

function FactoryHighRefuses(AContextRef: TObject; AOwner: TPMLObject;
  AQueue: TPMLEventQueue): TPMLVideoBackend;
begin
  Result := MakeFake(AContextRef, AOwner, 'high', False);
end;

function FactoryMidFirst(AContextRef: TObject; AOwner: TPMLObject;
  AQueue: TPMLEventQueue): TPMLVideoBackend;
begin
  Result := MakeFake(AContextRef, AOwner, 'mid-first', True);
end;

function FactoryMidSecond(AContextRef: TObject; AOwner: TPMLObject;
  AQueue: TPMLEventQueue): TPMLVideoBackend;
begin
  Result := MakeFake(AContextRef, AOwner, 'mid-second', True);
end;

function NewContext(ASubsystems: TPMLSubsystems; const AVideo, AIme: String): TPMLContext;
var
  O: TPMLContextOptions;
begin
  O := TPMLContextOptions.Default;
  O.PreferredVideo := AVideo;
  O.PreferredTextInput := AIme;
  Result := TPMLContext.Create(ASubsystems, O);
end;

{ 例外を「失敗」として数え、後ろの検査を続ける（空の実装でも全部の結果を見る）。 }
function TryContext(ASubsystems: TPMLSubsystems; const AVideo, AIme: String;
  const ALabel: String): TPMLContext;
begin
  Result := nil;
  try
    Result := NewContext(ASubsystems, AVideo, AIme);
  except
    on E: Exception do
      Check(False, ALabel + '（' + E.ClassName + ': ' + E.Message + '）');
  end;
end;

procedure TestVideo;
var
  Ctx: TPMLContext;
  Raised: Boolean;
  Msg: String;
begin
  WriteLn('2. ビデオの登録');
  Ctx := TryContext([TPMLSubsystem.Video], '', '', 'Context を作れる');
  if Ctx <> nil then
  try
    Check(Ctx.Video.BackendName = 'dummy', '名前を指定しなければ、登録されたダミーを選ぶ');
  finally
    Ctx.Free;
  end;

  Raised := False;
  Msg := '';
  try
    NewContext([TPMLSubsystem.Video], 'wayland', '').Free;
  except
    on E: Exception do
    begin
      Raised := E is EPMLUnsupported;
      Msg := E.ClassName + ': ' + E.Message;
    end;
  end;
  Check(Raised, 'リンクされていない wayland を指定すると EPMLUnsupported');
  Check((Pos('dummy', Msg) > 0) and (Pos('PaPiMeLa.Backends', Msg) > 0),
    '断るときに、使える名前と PaPiMeLa.Backends を添える: ' + Msg);

  // 優先度: high(100、Connect を断る) → mid-first(50) → mid-second(50) → dummy
  PMLRegisterVideoBackend('mid-first', 50, @FactoryMidFirst);
  PMLRegisterVideoBackend('high', 100, @FactoryHighRefuses);
  PMLRegisterVideoBackend('mid-second', 50, @FactoryMidSecond);
  Check(Joined(PMLVideoBackendNames) = 'high,mid-first,mid-second,dummy',
    '試す順は優先度の大きい順、同じなら登録順（ダミーは最後）: ' + Joined(PMLVideoBackendNames));
  Check(PMLFindVideoBackend('MID-SECOND') = @FactoryMidSecond, '名前は大文字小文字を区別しない');
  Check(PMLFindVideoBackend('nothing') = nil, '無い名前は nil');

  Tried := '';
  Ctx := TryContext([TPMLSubsystem.Video], '', '', 'Context を作れる');
  if Ctx <> nil then
  try
    Check(Ctx.Video.BackendName = 'mid-first',
      'Connect を断った high を飛ばし、次の mid-first を選ぶ: ' + Ctx.Video.BackendName);
    Check(Tried = 'high mid-first ', '試した順: ' + Tried);
  finally
    Ctx.Free;
  end;

  Tried := '';
  Ctx := TryContext([TPMLSubsystem.Video], 'Mid-Second', '', 'Context を作れる');
  if Ctx <> nil then
  try
    Check((Ctx.Video.BackendName = 'mid-second') and (Tried = 'mid-second '),
      '名前を指定すれば、それだけを試す（大文字小文字は区別しない）: ' + Tried);
  finally
    Ctx.Free;
  end;

  Raised := False;
  try
    NewContext([TPMLSubsystem.Video], 'high', '').Free;
  except
    on E: Exception do
      Raised := E is EPMLVideoError;
  end;
  Check(Raised, '指定した名前が Connect を断れば EPMLVideoError（他へ逃げない）');

  Raised := False;
  try
    PMLRegisterVideoBackend('DUMMY', 1, @FactoryMidFirst);
  except
    on E: Exception do
      Raised := E is EPMLArgument;
  end;
  Check(Raised, '同じ名前（大文字小文字違い）の 2 度目の登録は EPMLArgument');
  WriteLn;
end;

{ ---- 3. IME の登録 ---- }

type
  TFakeIme = class(TPMLNullTextInputBackend)
  public
    function BackendName: String; override;
  end;

function TFakeIme.BackendName: String;
begin
  Result := 'fake-ime';
end;

function FactoryFakeIme: TPMLTextInputBackend;
begin
  Result := TFakeIme.Create;
end;

procedure TestTextInput;
var
  Ctx: TPMLContext;
  Raised: Boolean;
  Msg: String;
begin
  WriteLn('3. IME の登録');
  Ctx := TryContext([TPMLSubsystem.TextInput], '', '', 'Context を作れる');
  if Ctx <> nil then
  try
    Check(Ctx.TextInput.BackendName = 'none', '何も登録されていなければ none');
  finally
    Ctx.Free;
  end;

  Raised := False;
  Msg := '';
  try
    NewContext([TPMLSubsystem.TextInput], '', 'fcitx').Free;
  except
    on E: Exception do
    begin
      Raised := E is EPMLUnsupported;
      Msg := E.ClassName + ': ' + E.Message;
    end;
  end;
  Check(Raised and (Pos('PaPiMeLa.Backends', Msg) > 0),
    'リンクされていない fcitx を指定すると EPMLUnsupported: ' + Msg);

  PMLRegisterTextInputBackend('fake-ime', 10, @FactoryFakeIme);
  Check(Joined(PMLTextInputBackendNames) = 'fake-ime', '登録した名前が並ぶ');
  Ctx := TryContext([TPMLSubsystem.TextInput], '', '', 'Context を作れる');
  if Ctx <> nil then
  try
    Check(Ctx.TextInput.BackendName = 'fake-ime', '登録したものを none より先に選ぶ');
  finally
    Ctx.Free;
  end;
  Ctx := TryContext([TPMLSubsystem.TextInput], '', 'none', 'Context を作れる');
  if Ctx <> nil then
  try
    Check(Ctx.TextInput.BackendName = 'none', 'none は名前で指定できる');
  finally
    Ctx.Free;
  end;
  WriteLn;
end;

{ ---- 4. レンダラの登録 ---- }

type
  TFakeDriver = class(TPMLWindowSoftwareRenderDriver)
  public
    function Name: String; override;
  end;

var
  PreferFake: Boolean = False;

function TFakeDriver.Name: String;
begin
  Result := 'fake-gpu';
end;

function FakeDriverPrefers(AWindow: TPMLWindow): Boolean;
begin
  Result := PreferFake;
end;

function FakeDriverFactory(AWindow: TPMLWindow): TPMLRenderDriver;
begin
  Result := TFakeDriver.Create(AWindow);
end;

function TryRenderer(AWin: TPMLWindow; const AName: String): TPMLRenderer;
begin
  Result := nil;
  try
    Result := TPMLRenderer.CreateForWindow(AWin, AName);
  except
    on E: Exception do
      Check(False, 'レンダラを作れる（' + E.ClassName + ': ' + E.Message + '）');
  end;
end;

function DriverOf(AR: TPMLRenderer): String;
begin
  if AR = nil then
    Result := '(無し)'
  else
    Result := AR.DriverName;
end;

procedure TestRender;
var
  Ctx: TPMLContext;
  Win: TPMLWindow;
  R: TPMLRenderer;
  Raised: Boolean;
  Msg: String;
begin
  WriteLn('4. レンダラの登録');
  Ctx := TryContext([TPMLSubsystem.Video], 'dummy', '', 'Context を作れる');
  if Ctx <> nil then
  try
    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('render', 32, 24));

    Raised := False;
    Msg := '';
    try
      TPMLRenderer.CreateForWindow(Win, 'gles2');
    except
      on E: Exception do
      begin
        Raised := E is EPMLUnsupported;
        Msg := E.ClassName + ': ' + E.Message;
      end;
    end;
    Check(Raised and (Pos('software', Msg) > 0) and (Pos('PaPiMeLa.Backends', Msg) > 0),
      'リンクされていない gles2 を指定すると、使える名前を添えて断る: ' + Msg);

    PMLRegisterRenderDriver('fake-gpu', 10, @FakeDriverPrefers, @FakeDriverFactory);
    Check(Joined(PMLRenderDriverNames) = 'fake-gpu,software',
      '名前の並びは登録したもの、最後に software: ' + Joined(PMLRenderDriverNames));

    PreferFake := False;
    R := TryRenderer(Win, '');
    Check(DriverOf(R) = 'software', '登録したドライバが選ばないと言えば software');
    R.Free;

    PreferFake := True;
    R := TryRenderer(Win, '');
    Check(DriverOf(R) = 'fake-gpu', '選ぶと言えば登録したドライバ');
    R.Free;

    PreferFake := False;
    R := TryRenderer(Win, 'FAKE-GPU');
    Check(DriverOf(R) = 'fake-gpu', '名前で指定すれば、選ぶかどうかに関わらず使う');
    R.Free;

    R := TryRenderer(Win, 'software');
    Check(DriverOf(R) = 'software', 'software は名前で指定できる');
    R.Free;
    Win.Free;
  finally
    Ctx.Free;
  end;
  WriteLn;
end;

begin
  WriteLn('test_backends — バックエンドの登録と、リンクされるもの');
  WriteLn;
  TestLinkage;
  TestVideo;
  TestTextInput;
  TestRender;
  if Failures = 0 then
    WriteLn('=== 結論: 使うバックエンドはアプリの uses で決まり、登録の規則どおりに選ばれる ===')
  else
  begin
    WriteLn(Format('=== 結論: %d 件失敗 ===', [Failures]));
    Halt(1);
  end;
end.
