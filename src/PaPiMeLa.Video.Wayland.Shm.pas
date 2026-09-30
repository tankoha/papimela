{
  PaPiMeLa.Video.Wayland.Shm — wl_shm のバッファ 1 枚

  Origin : partially ported from SDL (src/video/wayland/SDL_waylandshmbuffer.c)
           Scope: 共有メモリのファイルを作ってすぐ unlink し、fd だけを
           コンポジタへ渡す手順。プールとバッファの作り方。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.2、§11 #39

  WHAT:
    wl_shm_pool 1 つと wl_buffer 1 枚、その mmap した中身をまとめたもの。
    wl_buffer.release を受けて「コンポジタがまだ読んでいるか」（Busy）を持つ。

  WHY:
    コンポジタは commit されたバッファを、release を送るまで読むことがある。
    読まれている最中のバッファへ書くと、画面に描きかけの絵が出る。
    SDL は release を無視している（buffer_handle_release は何もしない）。
    SDL がこのバッファを使うのはカーソルと 1 画素のバッファで、一度書いたら
    書き換えないからである。papimela はソフトウェアレンダラの表示に使い、
    毎フレーム書き換えるので、release を数える必要がある。

  RESOLVED:
    - 1 枚ごとにプールを 1 つ持つ。大きさが変わったら作り直す（プールの
      resize で使い回すより単純で、大きさが変わるのはウィンドウのリサイズ時だけ）
    - 共有メモリのファイルは XDG_RUNTIME_DIR に作って即 unlink する。
      SDL は memfd_create を優先するが、FPC 3.2.2 の RTL にはその系統番号が無い
    - release の配送先キューは呼び出し側が決める（EventQueue 引数）。
      バッファを作った直後、まだ attach していないうちに付け替えるので、
      release が別のキューへ届く隙は無い

  NOT RESOLVED:
    - memfd_create と封印（F_SEAL_SHRINK）は使っていない
    - posix_fallocate による事前確保をしていない。/run/user が満杯だと
      mmap した領域への書き込みで SIGBUS になりうる

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Wayland.Shm;

{$I papimela.inc}

interface

uses
  SysUtils, BaseUnix,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Platform.Wayland.Protocols.Wayland;

type
  { wl_shm のバッファ 1 枚。形式は XRGB8888 固定（wl_shm が必ず対応する 2 形式の 1 つ）。 }
  TPMLWaylandShmBuffer = class(Twl_buffer_listener)
  strict private
    FPool  : Pwl_shm_pool;
    FBuffer: Pwl_buffer;
    FPixels: Pointer;
    FSize  : PtrUInt;
    FWidth, FHeight, FStride: Integer;
    FBusy  : Boolean;
  public
    { AEventQueue が nil でなければ、release をそのキューへ配送させる。 }
    constructor Create(AShm: Pwl_shm; AWidth, AHeight: Integer;
      AEventQueue: Pwl_event_queue);
    destructor Destroy; override;

    procedure release(AProxy: Pwl_buffer); override;

    { attach して commit する直前に呼ぶ。release が来るまで Busy になる。 }
    procedure MarkBusy;

    property Buffer: Pwl_buffer read FBuffer;
    property Pixels: Pointer read FPixels;
    property Width : Integer read FWidth;
    property Height: Integer read FHeight;
    property Stride: Integer read FStride;
    property Busy  : Boolean read FBusy;
  end;

{ 共有メモリのファイルを作り、ASize バイトに伸ばして fd を返す。
  ファイル名は既に消してある。失敗したら EPMLVideoError。 }
function PMLCreateShmFile(ASize: PtrUInt): cint;

implementation

const
  // FPC 3.2.2 の RTL には無い。Linux ではどのアーキテクチャでも 1。
  FD_CLOEXEC = 1;

function PMLCreateShmFile(ASize: PtrUInt): cint;
var
  Dir, Path: String;
  Attempt: Integer;
begin
  Dir := GetEnvironmentVariable('XDG_RUNTIME_DIR');
  if Dir = '' then
    Dir := '/tmp';

  Result := -1;
  for Attempt := 0 to 15 do
  begin
    Path := Format('%s/papimela-shm-%d-%d', [Dir, FpGetpid, Random(1000000)]);
    Result := FpOpen(PAnsiChar(Path), O_RDWR or O_CREAT or O_EXCL, &600);
    if Result >= 0 then
      Break;
  end;
  if Result < 0 then
    raise EPMLVideoError.CreateNative('failed to create a shm file', FpGetErrno, 'wayland');
  // 子プロセスへ漏らさない。O_CLOEXEC も FPC 3.2.2 の BaseUnix に無いので後から付ける。
  FpFcntl(Result, F_SETFD, FD_CLOEXEC);
  // 名前はすぐ消す。残すとプロセスが落ちたときに /run/user にごみが溜まる。
  FpUnlink(PAnsiChar(Path));

  if FpFtruncate(Result, ASize) <> 0 then
  begin
    FpClose(Result);
    raise EPMLVideoError.CreateNative('ftruncate on the shm file failed',
      FpGetErrno, 'wayland');
  end;
end;

{ TPMLWaylandShmBuffer }

constructor TPMLWaylandShmBuffer.Create(AShm: Pwl_shm; AWidth, AHeight: Integer;
  AEventQueue: Pwl_event_queue);
var
  FD: cint;
begin
  inherited Create;
  if (AShm = nil) or (AWidth <= 0) or (AHeight <= 0) then
    raise EPMLVideoError.CreateNative('invalid shm buffer request', 0, 'wayland');
  FWidth := AWidth;
  FHeight := AHeight;
  FStride := AWidth * 4;
  FSize := PtrUInt(FStride) * PtrUInt(AHeight);

  FD := PMLCreateShmFile(FSize);
  try
    FPixels := Fpmmap(nil, FSize, PROT_READ or PROT_WRITE, MAP_SHARED, FD, 0);
    if (FPixels = nil) or (FPixels = Pointer(-1)) then
    begin
      FPixels := nil;
      raise EPMLVideoError.CreateNative('mmap on the shm file failed',
        FpGetErrno, 'wayland');
    end;
    FPool := wl_shm_create_pool(AShm, FD, LongInt(FSize));
  finally
    FpClose(FD);   // プールが fd を複製して持つので、ここで閉じてよい
  end;

  FBuffer := wl_shm_pool_create_buffer(FPool, 0, FWidth, FHeight, FStride,
    WL_SHM_FORMAT_XRGB8888);
  if FBuffer = nil then
    raise EPMLVideoError.CreateNative('wl_shm_pool.create_buffer failed', 0, 'wayland');
  // まだ attach していないので、release はこの時点では届きようがない。
  if AEventQueue <> nil then
    wl_proxy_set_queue(Pwl_proxy(FBuffer), AEventQueue);
  wl_buffer_add_listener_object(FBuffer, Self);
end;

destructor TPMLWaylandShmBuffer.Destroy;
begin
  // Busy のうちに壊したとき表示がどうなるかはプロトコルが決めていない。
  // 呼び出し側は、サーフェスごと畳むとき以外は Busy でないものだけを壊す。
  if FBuffer <> nil then
    wl_buffer_destroy(FBuffer);
  if FPool <> nil then
    wl_shm_pool_destroy(FPool);
  if FPixels <> nil then
    Fpmunmap(FPixels, FSize);
  inherited Destroy;
end;

procedure TPMLWaylandShmBuffer.release(AProxy: Pwl_buffer);
begin
  FBusy := False;
end;

procedure TPMLWaylandShmBuffer.MarkBusy;
begin
  FBusy := True;
end;

end.
