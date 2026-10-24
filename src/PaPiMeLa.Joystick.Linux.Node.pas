{
  PaPiMeLa.Joystick.Linux.Node — Linux の入力機器の窓口（機器のファイルと、機器の見つけ方）

  Origin : ported from SDL (src/joystick/linux/SDL_sysjoystick.c, src/core/linux/SDL_evdev.c)
           Scope: /dev/input の機器の開閉・ioctl・読み取り・ff_effect の書き込み、機器ファイルの一覧と
           ディレクトリの更新時刻、js の番号の引き方（get_event_joystick_index）、抜き差しの監視
           （udev と inotify）、コンテナの判定。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #60

  WHAT:
    ジョイスティックのバックエンド（PaPiMeLa.Joystick.Linux）が OS に触る所を、2 つの抽象にした:
      TPMLEvdevNode  開いた機器 1 台（SDL の fd）
      TPMLEvdevHost  機器の一覧・開く・監視（SDL の open / scandir / stat / udev / inotify）
    本物（TPMLRealEvdevHost）は /dev/input を使う。検査は、同じ抽象の偽物（test/test_joystick_linux.pas）で
    機器の能力と入力を作り、権限や実機が無くてもバックエンドの中身を通す。

  WHY:
    /dev/input/event* は input グループが要り、実機のゲームパッドを CI で用意できない。SDL の C は fd を直接
    使うので差し込めないが、papimela は抽象を挟んで、能力の判定・軸の補正・ハット・割り当て・ランブルを
    実機なしで通す。

  RESOLVED:
    - 読み取りは非ブロック。ENODEV は Gone で伝える（SDL と同じに、外すのは次の Detect まで待つ）
    - 監視は、udev があれば udev、無ければ inotify、それも無ければ呼び出し側が 3 秒ごとに一覧を見る（SDL と同じ）
    - コンテナ（flatpak・snap）では udev を使わない（SDL_GetSandbox の相当）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Joystick.Linux.Node;

{$I papimela.inc}

interface

uses
  SysUtils, Classes, BaseUnix, Unix, ctypes,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.Evdev,
  PaPiMeLa.Platform.Udev;

type
  TPMLInputEventArray = array of TPMLInputEvent;

  { 開いた機器 1 台（fd）。 }
  TPMLEvdevNode = class abstract
  public
    { EVIOCGBIT。AEvent が 0 ならイベントの種類、それ以外はその種類のコードのビット。ABitCount はビットの数
      （PMLBitsLength で大きさが決まる）。失敗は False。 }
    function  GetBits(AEvent, ABitCount: Integer; out ABits: TPMLBits): Boolean; virtual; abstract;
    // EVIOCGPROP。新しい仕組みなので失敗してよい。
    function  GetProps(out ABits: TPMLBits): Boolean; virtual; abstract;
    function  GetID(out AID: TPMLInputID): Boolean; virtual; abstract;
    // EVIOCGNAME。
    function  GetName(out AName: String): Boolean; virtual; abstract;
    // JSIOCGNAME。旧 js の機器だけ成功する。
    function  GetJsName(out AName: String): Boolean; virtual; abstract;
    function  GetAbsInfo(AAxis: Integer; out AInfo: TPMLInputAbsInfo): Boolean; virtual; abstract;
    // EVIOCGKEY。今押されているキーのビット。
    function  GetKeyState(out ABits: TPMLBits): Boolean; virtual; abstract;
    { 読み取り（非ブロック）。読めた数を返す。何も無ければ 0。機器が外れていたら -1 で Gone が True。 }
    function  ReadEvents(var ABuffer: TPMLInputEventArray): Integer; virtual; abstract;
    { ff_effect を書き込む（EVIOCSFF。AEffect.ID が -1 なら新しく割り当てられ、ID が書き戻る）。失敗は False で Error に理由。 }
    function  UploadEffect(var AEffect: TPMLFFEffect): Boolean; virtual; abstract;
    function  RemoveEffect(AID: Integer): Boolean; virtual; abstract;
    // 効果を始める（EV_FF の input_event を write）。
    function  PlayEffect(AID: Integer): Boolean; virtual; abstract;
    function  Gone: Boolean; virtual; abstract;
    function  Writable: Boolean; virtual; abstract;
    function  Error: String; virtual; abstract;
  end;

  // 抜き差しの通知。AClass は udev のときの機器の種類（足されたとき）、inotify では -1。
  TPMLHotplugKind = (Added, Removed);
  TPMLHotplugCallback = procedure(AKind: TPMLHotplugKind; AClass: Integer; const APath: String) of object;
  TPMLHotplugMethod = (None, Udev, Inotify);

  { 機器の一覧・開く・監視。 }
  TPMLEvdevHost = class abstract
  public
    // 機器を開く。開けなければ nil。
    function  OpenNode(const APath: String; AWritable: Boolean): TPMLEvdevNode; virtual; abstract;
    // 機器ファイルの番号（stat の st_rdev）。無ければ False。
    function  DeviceNumber(const APath: String; out ADevNum: QWord): Boolean; virtual; abstract;
    // /dev/input の名前の一覧（event 番号の並びは問わない）。
    function  ListInputDirectory: TStringArray; virtual; abstract;
    // /dev/input の更新時刻（秒）。見られなければ False。
    function  InputDirectoryMTime(out AMTime: Int64): Boolean; virtual; abstract;
    // /sys の event の機器に付いた jsN の番号（get_event_joystick_index）。無ければ -1。
    function  JsIndexForEvent(AEvent: Integer): Integer; virtual; abstract;
    { 監視を始める。使った方法を返す（AUseUdev が False なら udev は試さない）。通知は ACallback へ。 }
    function  StartHotplug(AUseUdev: Boolean; ACallback: TPMLHotplugCallback): TPMLHotplugMethod; virtual; abstract;
    // 今ある機器を通知させる（udev の Scan）。
    procedure ScanHotplug; virtual; abstract;
    // 溜まった通知を処理する（udev の Poll、inotify の読み取り）。
    procedure PollHotplug; virtual; abstract;
    procedure StopHotplug; virtual; abstract;
    { udev から ID・種類・ドライバを引く。udev を使っていなければ False。 }
    function  ProductInfo(const APath: String; var AID: TPMLInputID; var AClass: Integer;
      out ADriver: String): Boolean; virtual; abstract;
    function  ProductSerial(const APath: String): String; virtual; abstract;
    // コンテナの中か（SDL_GetSandbox ≠ NONE）。
    function  Sandboxed: Boolean; virtual; abstract;
    // ミリ秒の時計（3 秒ごとの一覧の見直しに使う）。
    function  TicksMS: UInt64; virtual; abstract;
  end;

  { 本物。/dev/input を使う。 }
  TPMLRealEvdevHost = class(TPMLEvdevHost)
  strict private
    FUdev       : TPMLUdev;
    FInotifyFd  : cint;
    FCallback   : TPMLHotplugCallback;
    procedure UdevEvent(AEvent: TPMLUdevDeviceEvent; AClass: Integer; const APath: String);
  public
    constructor Create;
    destructor Destroy; override;
    function  OpenNode(const APath: String; AWritable: Boolean): TPMLEvdevNode; override;
    function  DeviceNumber(const APath: String; out ADevNum: QWord): Boolean; override;
    function  ListInputDirectory: TStringArray; override;
    function  InputDirectoryMTime(out AMTime: Int64): Boolean; override;
    function  JsIndexForEvent(AEvent: Integer): Integer; override;
    function  StartHotplug(AUseUdev: Boolean; ACallback: TPMLHotplugCallback): TPMLHotplugMethod; override;
    procedure ScanHotplug; override;
    procedure PollHotplug; override;
    procedure StopHotplug; override;
    function  ProductInfo(const APath: String; var AID: TPMLInputID; var AClass: Integer;
      out ADriver: String): Boolean; override;
    function  ProductSerial(const APath: String): String; override;
    function  Sandboxed: Boolean; override;
    function  TicksMS: UInt64; override;
  end;

implementation

const
  O_CLOEXEC   = $80000;      // aarch64 / x86_64 の値
  IN_NONBLOCK = $800;
  IN_CLOEXEC  = $80000;
  IN_CREATE   = $100;
  IN_DELETE   = $200;
  IN_ATTRIB   = $4;
  IN_MOVED_FROM = $40;
  IN_MOVED_TO   = $80;
  IN_MOVE       = IN_MOVED_FROM or IN_MOVED_TO;

function inotify_init1(AFlags: cint): cint; cdecl; external 'c' name 'inotify_init1';
function inotify_add_watch(AFd: cint; APath: PChar; AMask: cuint32): cint; cdecl; external 'c' name 'inotify_add_watch';

type
  TRealEvdevNode = class(TPMLEvdevNode)
  strict private
    FFd      : cint;
    FWritable: Boolean;
    FGone    : Boolean;
    FError   : String;
    function IoctlBits(ARequest: culong; ASize: Integer; out ABits: TPMLBits): Boolean;
  public
    constructor Create(AFd: cint; AWritable: Boolean);
    destructor Destroy; override;
    function  GetBits(AEvent, ABitCount: Integer; out ABits: TPMLBits): Boolean; override;
    function  GetProps(out ABits: TPMLBits): Boolean; override;
    function  GetID(out AID: TPMLInputID): Boolean; override;
    function  GetName(out AName: String): Boolean; override;
    function  GetJsName(out AName: String): Boolean; override;
    function  GetAbsInfo(AAxis: Integer; out AInfo: TPMLInputAbsInfo): Boolean; override;
    function  GetKeyState(out ABits: TPMLBits): Boolean; override;
    function  ReadEvents(var ABuffer: TPMLInputEventArray): Integer; override;
    function  UploadEffect(var AEffect: TPMLFFEffect): Boolean; override;
    function  RemoveEffect(AID: Integer): Boolean; override;
    function  PlayEffect(AID: Integer): Boolean; override;
    function  Gone: Boolean; override;
    function  Writable: Boolean; override;
    function  Error: String; override;
  end;

{ TRealEvdevNode }

constructor TRealEvdevNode.Create(AFd: cint; AWritable: Boolean);
begin
  inherited Create;
  FFd := AFd;
  FWritable := AWritable;
end;

destructor TRealEvdevNode.Destroy;
begin
  if FFd >= 0 then
    fpClose(FFd);
  inherited Destroy;
end;

function TRealEvdevNode.IoctlBits(ARequest: culong; ASize: Integer; out ABits: TPMLBits): Boolean;
begin
  SetLength(ABits, ASize);
  FillChar(ABits[0], ASize, 0);
  Result := fpIOCtl(FFd, ARequest, @ABits[0]) >= 0;
end;

function TRealEvdevNode.GetBits(AEvent, ABitCount: Integer; out ABits: TPMLBits): Boolean;
var
  Size: Integer;
begin
  Size := PMLBitsLength(ABitCount);
  Result := IoctlBits(PMLEVIOCGBIT(AEvent, Size), Size, ABits);
end;

function TRealEvdevNode.GetProps(out ABits: TPMLBits): Boolean;
var
  Size: Integer;
begin
  Size := PMLBitsLength(INPUT_PROP_MAX + 1);
  Result := IoctlBits(PMLEVIOCGPROP(Size), Size, ABits);
end;

function TRealEvdevNode.GetID(out AID: TPMLInputID): Boolean;
begin
  FillChar(AID, SizeOf(AID), 0);
  Result := fpIOCtl(FFd, PMLEVIOCGID, @AID) >= 0;
end;

function TRealEvdevNode.GetName(out AName: String): Boolean;
var
  Buf: array[0..127] of Char;
begin
  FillChar(Buf, SizeOf(Buf), 0);
  Result := fpIOCtl(FFd, PMLEVIOCGNAME(SizeOf(Buf)), @Buf[0]) >= 0;
  if Result then
    AName := PChar(@Buf[0])
  else
    AName := '';
end;

function TRealEvdevNode.GetJsName(out AName: String): Boolean;
var
  Buf: array[0..127] of Char;
  R: cint;
begin
  FillChar(Buf, SizeOf(Buf), 0);
  R := fpIOCtl(FFd, PMLJSIOCGNAME(SizeOf(Buf)), @Buf[0]);
  Result := R > 0;
  if Result then
    AName := PChar(@Buf[0])
  else
    AName := '';
end;

function TRealEvdevNode.GetAbsInfo(AAxis: Integer; out AInfo: TPMLInputAbsInfo): Boolean;
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
  Result := fpIOCtl(FFd, PMLEVIOCGABS(AAxis), @AInfo) >= 0;
end;

function TRealEvdevNode.GetKeyState(out ABits: TPMLBits): Boolean;
var
  Size: Integer;
begin
  Size := PMLBitsLength(KEY_MAX + 1);
  Result := IoctlBits(PMLEVIOCGKEY(Size), Size, ABits);
end;

function TRealEvdevNode.ReadEvents(var ABuffer: TPMLInputEventArray): Integer;
var
  N: TSsize;
begin
  N := fpRead(FFd, ABuffer[0], Length(ABuffer) * SizeOf(TPMLInputEvent));
  if N > 0 then
    Exit(N div SizeOf(TPMLInputEvent));
  if (N < 0) and (fpGetErrno = ESysENODEV) then
  begin
    FGone := True;
    Exit(-1);
  end;
  Result := 0;
end;

function TRealEvdevNode.UploadEffect(var AEffect: TPMLFFEffect): Boolean;
begin
  Result := fpIOCtl(FFd, PMLEVIOCSFF, @AEffect) >= 0;
  if not Result then
    FError := SysErrorMessage(fpGetErrno);
end;

function TRealEvdevNode.RemoveEffect(AID: Integer): Boolean;
begin
  Result := fpIOCtl(FFd, PMLEVIOCRMFF, Pointer(PtrInt(AID))) >= 0;
end;

function TRealEvdevNode.PlayEffect(AID: Integer): Boolean;
var
  E: TPMLInputEvent;
begin
  FillChar(E, SizeOf(E), 0);
  E.EventType := EV_FF;
  E.Code := AID;
  E.Value := 1;
  Result := fpWrite(FFd, E, SizeOf(E)) >= 0;
  if not Result then
    FError := SysErrorMessage(fpGetErrno);
end;

function TRealEvdevNode.Gone: Boolean;
begin
  Result := FGone;
end;

function TRealEvdevNode.Writable: Boolean;
begin
  Result := FWritable;
end;

function TRealEvdevNode.Error: String;
begin
  Result := FError;
end;

{ TPMLRealEvdevHost }

constructor TPMLRealEvdevHost.Create;
begin
  inherited Create;
  FInotifyFd := -1;
end;

destructor TPMLRealEvdevHost.Destroy;
begin
  StopHotplug;
  inherited Destroy;
end;

function TPMLRealEvdevHost.OpenNode(const APath: String; AWritable: Boolean): TPMLEvdevNode;
var
  Fd: cint;
  Rw: Boolean;
begin
  Rw := False;
  Fd := -1;
  if AWritable then
  begin
    // 読み書きで開けば、ランブルができる。開けなければ読むだけで開く（イベントは取れる）
    Fd := fpOpen(APath, O_RDWR or O_CLOEXEC);
    Rw := Fd >= 0;
  end;
  if Fd < 0 then
    Fd := fpOpen(APath, O_RDONLY or O_CLOEXEC);
  if Fd < 0 then
    Exit(nil);
  fpFcntl(Fd, F_SETFL, O_NONBLOCK);
  Result := TRealEvdevNode.Create(Fd, Rw);
end;

function TPMLRealEvdevHost.DeviceNumber(const APath: String; out ADevNum: QWord): Boolean;
var
  St: Stat;
begin
  Result := fpStat(APath, St) = 0;
  if Result then
    ADevNum := St.st_rdev
  else
    ADevNum := 0;
end;

function TPMLRealEvdevHost.ListInputDirectory: TStringArray;
var
  D: PDir;
  E: PDirent;
  N: Integer;
begin
  Result := nil;
  D := fpOpenDir('/dev/input');
  if D = nil then
    Exit;
  try
    N := 0;
    E := fpReadDir(D^);
    while E <> nil do
    begin
      SetLength(Result, N + 1);
      Result[N] := PChar(@E^.d_name[0]);
      Inc(N);
      E := fpReadDir(D^);
    end;
  finally
    fpCloseDir(D^);
  end;
end;

function TPMLRealEvdevHost.InputDirectoryMTime(out AMTime: Int64): Boolean;
var
  St: Stat;
begin
  Result := fpStat('/dev/input', St) = 0;
  if Result then
    AMTime := St.st_mtime
  else
    AMTime := 0;
end;

function TPMLRealEvdevHost.JsIndexForEvent(AEvent: Integer): Integer;
var
  D: PDir;
  E: PDirent;
  Name: String;
begin
  Result := -1;
  D := fpOpenDir(Format('/sys/class/input/event%d/device', [AEvent]));
  if D = nil then
    Exit;
  try
    E := fpReadDir(D^);
    while E <> nil do
    begin
      Name := PChar(@E^.d_name[0]);
      if Copy(Name, 1, 2) = 'js' then
        Result := StrToIntDef(Copy(Name, 3, MaxInt), 0);
      E := fpReadDir(D^);
    end;
  finally
    fpCloseDir(D^);
  end;
end;

procedure TPMLRealEvdevHost.UdevEvent(AEvent: TPMLUdevDeviceEvent; AClass: Integer; const APath: String);
begin
  if not Assigned(FCallback) then
    Exit;
  if AEvent = TPMLUdevDeviceEvent.Added then
    FCallback(TPMLHotplugKind.Added, AClass, APath)
  else
    FCallback(TPMLHotplugKind.Removed, AClass, APath);
end;

function TPMLRealEvdevHost.Sandboxed: Boolean;
begin
  // flatpak と snap（SDL_GetSandbox の相当）
  Result := FileExists('/.flatpak-info') or (GetEnvironmentVariable('SNAP') <> '');
end;

function TPMLRealEvdevHost.TicksMS: UInt64;
begin
  Result := GetTickCount64;
end;

function TPMLRealEvdevHost.StartHotplug(AUseUdev: Boolean; ACallback: TPMLHotplugCallback): TPMLHotplugMethod;
begin
  FCallback := ACallback;
  Result := TPMLHotplugMethod.None;
  if AUseUdev and TPMLUdev.IsAvailable then
  begin
    try
      FUdev := TPMLUdev.Create;
      FUdev.AddCallback(@UdevEvent);
      Exit(TPMLHotplugMethod.Udev);
    except
      on EPMLPlatformLibrary do
        FUdev := nil;      // udev が使えなければ inotify へ
    end;
  end;
  FInotifyFd := inotify_init1(IN_NONBLOCK or IN_CLOEXEC);
  if FInotifyFd >= 0 then
  begin
    // 作られた直後は読めない権限なので、あとで udev が権限を変える（IN_ATTRIB）のも見る
    if inotify_add_watch(FInotifyFd, '/dev/input', IN_CREATE or IN_DELETE or IN_MOVE or IN_ATTRIB) < 0 then
    begin
      fpClose(FInotifyFd);
      FInotifyFd := -1;
    end
    else
      Result := TPMLHotplugMethod.Inotify;
  end;
end;

procedure TPMLRealEvdevHost.ScanHotplug;
begin
  if FUdev <> nil then
    FUdev.Scan;
end;

procedure TPMLRealEvdevHost.PollHotplug;
var
  Buf: array[0..4095] of Byte;
  N: TSsize;
  Pos_, NameLen: Integer;
  Mask: cuint32;
  Name: String;
begin
  if FUdev <> nil then
  begin
    FUdev.Poll;
    Exit;
  end;
  if FInotifyFd < 0 then
    Exit;
  N := fpRead(FInotifyFd, Buf[0], SizeOf(Buf));
  Pos_ := 0;
  // struct inotify_event { int wd; uint32 mask; uint32 cookie; uint32 len; char name[]; }
  while (N > 0) and (Pos_ + 16 <= N) do
  begin
    Mask := PCardinal(@Buf[Pos_ + 4])^;
    NameLen := PCardinal(@Buf[Pos_ + 12])^;
    if NameLen > 0 then
    begin
      Name := PChar(@Buf[Pos_ + 16]);
      if (Mask and (IN_CREATE or IN_MOVED_TO or IN_ATTRIB)) <> 0 then
        UdevEvent(TPMLUdevDeviceEvent.Added, -1, '/dev/input/' + Name)
      else if (Mask and (IN_DELETE or IN_MOVED_FROM)) <> 0 then
        UdevEvent(TPMLUdevDeviceEvent.Removed, -1, '/dev/input/' + Name);
    end;
    Inc(Pos_, 16 + NameLen);
  end;
end;

procedure TPMLRealEvdevHost.StopHotplug;
begin
  if FInotifyFd >= 0 then
  begin
    fpClose(FInotifyFd);
    FInotifyFd := -1;
  end;
  if FUdev <> nil then
  begin
    FUdev.DelCallback(@UdevEvent);
    FreeAndNil(FUdev);
  end;
end;

function TPMLRealEvdevHost.ProductInfo(const APath: String; var AID: TPMLInputID; var AClass: Integer;
  out ADriver: String): Boolean;
begin
  ADriver := '';
  if FUdev = nil then
    Exit(False);
  Result := FUdev.GetProductInfo(APath, AID, AClass, ADriver);
end;

function TPMLRealEvdevHost.ProductSerial(const APath: String): String;
begin
  if FUdev = nil then
    Result := ''
  else
    Result := FUdev.GetProductSerial(APath);
end;

end.
