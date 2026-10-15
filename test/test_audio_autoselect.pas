{
  test_audio_autoselect — バックエンドの自動選択で、バックエンドが身を引ける（AcceptForAutoSelection）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    偽のバックエンド 3 つ（優先度 1000 の fake-refuse、999 の fake-ok、998 の fake-last）を登録する。
    fake-refuse は自動選択のときだけ断る（SDL の優先するブートストラップに対応）。
    1. 名前を指定しない: fake-refuse に聞き（1 回）、断られたら DeinitializeStart と Deinitialize を
       呼んで壊し、fake-ok を使う。fake-last は作られない
    2. 名前で求める（'fake-refuse'）: 聞かずに使う
    3. 'fake-refuse,fake-ok': 名前で求めたものは、並べた順に聞かずに試す
    4. 聞いたときに例外を投げるバックエンドも、断ったことにして次へ進む
    5. 知らない名前は、名前を含むエラー

  WHY:
    PipeWire が動いていても音のサーバが別の道（PulseAudio など）のとき、次のバックエンドへ譲るため
    （PipeWire 自身の判断は test_audio_pipewire の自動選択の場面）。ALSA・PulseAudio・PipeWire の
    実物は要らない（CI で走る）。
}
program test_audio_autoselect;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  cthreads,
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Log,
  PaPiMeLa.Core,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Backend,
  PaPiMeLa.Audio;

type
  TFakeBackend = class(TPMLAudioBackend)
  public
    constructor Create(ACore: TPMLAudioCore); override;
    procedure DeinitializeStart; override;
    procedure Deinitialize; override;
    destructor Destroy; override;
  end;

  TRefuse = class(TFakeBackend)
  public
    function Name: String; override;
    function AcceptForAutoSelection: Boolean; override;
  end;

  TOk = class(TFakeBackend)
  public
    function Name: String; override;
  end;

  TLast = class(TFakeBackend)
  public
    function Name: String; override;
  end;

  TThrows = class(TFakeBackend)
  public
    function Name: String; override;
    function AcceptForAutoSelection: Boolean; override;
  end;

var
  Failures: Integer = 0;
  Created, Asked, DeinitStart, Deinit, Destroyed: array[0..3] of Integer;
  // 0 refuse、1 ok、2 last、3 throws

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

function KindOf(AObj: TFakeBackend): Integer;
begin
  if AObj is TRefuse then Result := 0
  else if AObj is TOk then Result := 1
  else if AObj is TLast then Result := 2
  else Result := 3;
end;

constructor TFakeBackend.Create(ACore: TPMLAudioCore);
begin
  inherited Create(ACore);
  FCapabilities := [TPMLAudioBackendCapability.OnlyHasDefaultPlaybackDevice,
    TPMLAudioBackendCapability.OnlyHasDefaultRecordingDevice, TPMLAudioBackendCapability.HasRecordingSupport];
  Inc(Created[KindOf(Self)]);
end;

procedure TFakeBackend.DeinitializeStart;
begin
  Inc(DeinitStart[KindOf(Self)]);
end;

procedure TFakeBackend.Deinitialize;
begin
  Inc(Deinit[KindOf(Self)]);
end;

destructor TFakeBackend.Destroy;
begin
  Inc(Destroyed[KindOf(Self)]);
  inherited Destroy;
end;

function TRefuse.Name: String;
begin
  Result := 'fake-refuse';
end;

function TRefuse.AcceptForAutoSelection: Boolean;
begin
  Inc(Asked[0]);
  Result := False;
end;

function TOk.Name: String;
begin
  Result := 'fake-ok';
end;

function TLast.Name: String;
begin
  Result := 'fake-last';
end;

function TThrows.Name: String;
begin
  Result := 'fake-throws';
end;

function TThrows.AcceptForAutoSelection: Boolean;
begin
  Result := False;
  Inc(Asked[3]);
  raise Exception.Create('cannot tell');
end;

function MakeRefuse(ACore: TPMLAudioCore): TPMLAudioBackend;
begin
  Result := TRefuse.Create(ACore);
end;

function MakeOk(ACore: TPMLAudioCore): TPMLAudioBackend;
begin
  Result := TOk.Create(ACore);
end;

function MakeLast(ACore: TPMLAudioCore): TPMLAudioBackend;
begin
  Result := TLast.Create(ACore);
end;

function MakeThrows(ACore: TPMLAudioCore): TPMLAudioBackend;
begin
  Result := TThrows.Create(ACore);
end;

procedure Reset;
begin
  FillChar(Created, SizeOf(Created), 0);
  FillChar(Asked, SizeOf(Asked), 0);
  FillChar(DeinitStart, SizeOf(DeinitStart), 0);
  FillChar(Deinit, SizeOf(Deinit), 0);
  FillChar(Destroyed, SizeOf(Destroyed), 0);
end;

function NewContext(const APreferred: String): TPMLContext;
var
  Opts: TPMLContextOptions;
begin
  Opts := TPMLContextOptions.Default;
  Opts.PreferredAudio := APreferred;
  Opts.MinimumLogLevel := TPMLLogPriority.Critical;
  Result := TPMLContext.Create([TPMLSubsystem.Audio], Opts);
end;

procedure Scenario1;
var
  Ctx: TPMLContext;
begin
  WriteLn('-- 名前を指定しない: 断られたら次へ');
  Reset;
  Ctx := NewContext('');
  try
    Check(Ctx.Audio.BackendName = 'fake-ok', 'fake-ok が選ばれる（' + Ctx.Audio.BackendName + '）');
    Check(Asked[0] = 1, 'fake-refuse には 1 回だけ聞く');
    Check((DeinitStart[0] = 1) and (Deinit[0] = 1) and (Destroyed[0] = 1),
      '断ったバックエンドは DeinitializeStart・Deinitialize を 1 度ずつ呼んで壊す');
    Check(Created[2] = 0, 'fake-last は作られない');
  finally
    Ctx.Free;
  end;
  Check((DeinitStart[1] = 1) and (Deinit[1] = 1) and (Destroyed[1] = 1), '使ったバックエンドも最後に片付く');
end;

procedure Scenario2;
var
  Ctx: TPMLContext;
begin
  WriteLn('-- 名前で求める: 聞かずに使う');
  Reset;
  Ctx := NewContext('fake-refuse');
  try
    Check(Ctx.Audio.BackendName = 'fake-refuse', 'fake-refuse が選ばれる（' + Ctx.Audio.BackendName + '）');
    Check(Asked[0] = 0, '聞かない');
  finally
    Ctx.Free;
  end;
  Reset;
  Ctx := NewContext('fake-refuse,fake-ok');
  try
    Check(Ctx.Audio.BackendName = 'fake-refuse', '並べた順に試し、最初のものを聞かずに使う（' + Ctx.Audio.BackendName + '）');
    Check(Asked[0] = 0, '聞かない');
  finally
    Ctx.Free;
  end;
end;

procedure Scenario3;
var
  Ctx: TPMLContext;
begin
  WriteLn('-- 聞いたときに例外を投げたら断ったことにする');
  PMLRegisterAudioBackend('fake-throws', 1001, @MakeThrows);
  Reset;
  Ctx := NewContext('');
  try
    Check(Ctx.Audio.BackendName = 'fake-ok', '例外を投げた fake-throws と断った fake-refuse の次の fake-ok（' + Ctx.Audio.BackendName + '）');
    Check((Asked[3] = 1) and (Destroyed[3] = 1), 'fake-throws には 1 回聞いて壊す');
    Check(Asked[0] = 1, 'fake-refuse にも聞く');
  finally
    Ctx.Free;
  end;
end;

procedure Scenario4;
var
  Raised: Boolean;
  Msg: String;
  Ctx: TPMLContext;
begin
  WriteLn('-- 知らない名前');
  Reset;
  Raised := False;
  Msg := '';
  Ctx := nil;
  try
    Ctx := NewContext('nonexistent-backend');
  except
    on E: Exception do
    begin
      Raised := True;
      Msg := E.Message;
    end;
  end;
  Ctx.Free;
  Check(Raised and (Pos('nonexistent-backend', Msg) > 0), '知らない名前は、名前を含むエラー: ' + Copy(Msg, 1, 60));
end;

begin
  WriteLn('=== test_audio_autoselect ===');
  PMLRegisterAudioBackend('fake-refuse', 1000, @MakeRefuse);
  PMLRegisterAudioBackend('fake-ok', 999, @MakeOk);
  PMLRegisterAudioBackend('fake-last', 998, @MakeLast);
  Scenario1;
  Scenario2;
  Scenario3;
  Scenario4;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: 自動選択のときだけバックエンドが身を引け、名前で求めたときは聞かない ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
