{
  test_render_window — ウィンドウへ描くレンダラを表示サーバ無しで検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    ダミービデオバックエンドのウィンドウに TPMLRenderer.CreateForWindow で
    レンダラを付け、描いた結果がフレームバッファに入ること、Present が
    ウィンドウへ届くこと、ウィンドウの大きさが変わったら描画先が追従すること、
    VSync の受け渡し、ウィンドウとレンダラの破棄の順序を確かめる。

  WHY:
    ウィンドウのフレームバッファは大きさが変わると作り直される。描画先を
    取り直さないと、解放済みの領域へ描くことになる（落ちるとは限らず、
    画面に何も出ないだけのこともある）。ここはそれを画素で捕まえる。
    Wayland 側の shm バッファと VSync は demo_render_window が実機で見る。

  実行前提: 無し。ダミーを明示的に選ぶ。
}
program test_render_window;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Events,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Dummy,
  PaPiMeLa.Render,
  PaPiMeLa.Core;

type
  { 破棄されたことを数えるためだけの派生。 }
  TProbeRenderer = class(TPMLRenderer)
  public
    destructor Destroy; override;
  end;

var
  Failures : Integer = 0;
  Destroyed: Integer = 0;

destructor TProbeRenderer.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
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

{ フレームバッファの (X, Y) の画素。XRGB8888 なので上位 8 ビットは捨てる。 }
function FramePixel(AWin: TPMLWindow; AX, AY: Integer): LongWord;
var
  P: Pointer;
  Pitch: Integer;
begin
  if not AWin.LockFramebuffer(P, Pitch) then
    Exit($DEADBEEF);
  Result := PLongWord(PByte(P) + PtrUInt(AY) * PtrUInt(Pitch) + PtrUInt(AX) * 4)^
            and $00FFFFFF;
end;

var
  Ctx   : TPMLContext;
  Opts  : TPMLContextOptions;
  Win, Win2: TPMLWindow;
  WB    : TPMLDummyWindowBackend;
  R, R2 : TPMLRenderer;
  Soft  : TPMLRenderer;
  S, RP, Img: TPMLSurface;
  Tex   : TPMLTexture;
  P     : Pointer;
  Pitch, W, H, Y: Integer;
  Format: TPMLPixelFormat;
  Same, Raised: Boolean;
  Ev    : TPMLEvent;
begin
  WriteLn('test_render_window — ウィンドウへ描くレンダラ');
  WriteLn;

  Opts := TPMLContextOptions.Create;
  Opts.PreferredVideo := 'dummy';
  Ctx := TPMLContext.Create([TPMLSubsystem.Video], Opts);
  try
    Win := Ctx.Video.CreateWindow(
      TPMLWindowOptions.Make('render window', 64, 48).Resizable);
    WB := Win.Backend as TPMLDummyWindowBackend;

    WriteLn('1. 生成');
    R := TPMLRenderer.CreateForWindow(Win);
    Check(R.DriverName = 'software', 'ドライバはソフトウェア');
    Check(R.Window = Win, 'レンダラからウィンドウが引ける');
    Check(R.Owner = Win, '所有者はウィンドウ');
    Check(Win.DependentCount = 1, 'ウィンドウに登録される');
    Check(R.GetOutputSize(W, H) and (W = 64) and (H = 48), '出力の大きさはウィンドウと同じ');

    Raised := False;
    try
      TPMLRenderer.CreateForWindow(Win, 'gles2');
    except
      on E: EPMLUnsupported do
        Raised := True;
    end;
    Check(Raised, '無いドライバの名前は EPMLUnsupported');
    Check(Win.DependentCount = 1, '失敗した生成はウィンドウに残らない');

    WriteLn;
    WriteLn('2. 描いて出す');
    R.DrawColor := TPMLColor.Make(10, 20, 30, 255);
    R.Clear;
    R.DrawColor := TPMLColor.Make(255, 0, 0, 255);
    R.FillRect(TPMLFRect.Make(8, 8, 16, 16));
    Check(WB.PresentCount = 0, 'Present までは画面へ出さない');
    R.Present;
    Check(WB.PresentCount = 1, 'Present でウィンドウの UpdateFramebuffer が呼ばれる');
    Check(Win.LockFramebuffer(P, Pitch, Format) and (Format = PML_PIXELFORMAT_XRGB8888),
      'フレームバッファの形式は XRGB8888');
    Check(FramePixel(Win, 0, 0) = $0A141E, '背景が入っている');
    Check(FramePixel(Win, 8, 8) = $FF0000, '矩形の左上が入っている');
    Check(FramePixel(Win, 23, 23) = $FF0000, '矩形の右下が入っている');
    Check(FramePixel(Win, 24, 24) = $0A141E, '矩形の外は背景のまま');

    RP := R.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    try
      Same := (RP.Width = 64) and (RP.Height = 48);
      if Same then
        for Y := 0 to 47 do
          if not CompareMem(PByte(RP.Pixels) + PtrUInt(Y) * PtrUInt(RP.Pitch),
                            PByte(P) + PtrUInt(Y) * PtrUInt(Pitch), 64 * 4) then
            Same := False;
      Check(Same, 'ReadPixels はフレームバッファと一致する');
    finally
      RP.Free;
    end;

    WriteLn;
    WriteLn('3. 大きさが変わったら描画先が追従する');
    // リサイズより前にテクスチャを作っておく。描画先が変わってもテクスチャは残る。
    Img := TPMLSurface.Create(2, 2, PML_PIXELFORMAT_XRGB8888);
    Img.FillRect(TPMLRect.Make(0, 0, 2, 2), TPMLColor.Make(0, 255, 0, 255));
    Tex := R.CreateTextureFromSurface(Img);
    Img.Free;

    Win.SetSize(80, 60);
    Ctx.Events.Pump(0);
    while Ctx.Events.Poll(Ev) do ;
    Check(R.GetOutputSize(W, H) and (W = 80) and (H = 60), '出力の大きさが新しい大きさになる');
    R.DrawColor := TPMLColor.Make(0, 0, 255, 255);
    R.Clear;
    R.DrawColor := TPMLColor.Make(255, 255, 255, 255);
    R.FillRect(TPMLFRect.Make(70, 50, 10, 10));
    R.RenderTexture(Tex, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(30, 30, 4, 4));
    R.Present;
    Check(Win.LockFramebuffer(P, Pitch) and (Pitch = 80 * 4), '新しいフレームバッファの行幅');
    Check(FramePixel(Win, 79, 0) = $0000FF, 'Clear は新しい全体を塗る');
    Check(FramePixel(Win, 79, 59) = $FFFFFF, '新しい右下の隅まで描ける');
    Check(FramePixel(Win, 33, 33) = $00FF00, 'リサイズ前に作ったテクスチャを描ける');

    // 描いてから Present までの間に大きくなった場合。積んだ時点のフレームバッファは
    // ダミーが解放しているので、実行時に取り直さない実装は解放済みの領域へ書く。
    // 実測では、その実装はこの区間で異常終了した（終了コード 217）。落ちなければ
    // 右下の隅が塗られずに FAIL になる。どちらでもテストは失敗する。
    // 縮む向きで確かめてはいけない。ヒープが同じ番地を返すことがあり、古い
    // 描画先へ書いた分が偶然新しい領域に見えてしまう（取り直さない実装でも通る）。
    // 大きくなる向きなら、新しい右下の隅は古い描画先の外にある。
    Win.SetSize(40, 30);
    R.DrawColor := TPMLColor.Make(0, 0, 0, 255);
    R.Clear;
    R.Present;
    R.DrawColor := TPMLColor.Make(255, 0, 255, 255);
    R.Clear;
    Win.SetSize(80, 60);
    R.Present;
    Check(FramePixel(Win, 0, 0) = $FF00FF, '積んだ後に大きくなっても新しい領域へ描く');
    Check(FramePixel(Win, 79, 59) = $FF00FF, '大きくなった後の右下の隅も塗られる');
    Check(WB.PresentCount = 4, 'Present の回数');

    WriteLn;
    WriteLn('4. VSync');
    R.VSync := 1;
    Check((R.VSync = 1) and (WB.VSync = 1), 'VSync 1 がウィンドウへ届く');
    R.VSync := 0;
    Check((R.VSync = 0) and (WB.VSync = 0), 'VSync 0 に戻せる');

    S := TPMLSurface.Create(8, 8, PML_PIXELFORMAT_XRGB8888);
    Soft := TPMLRenderer.CreateSoftware(S);
    Raised := False;
    try
      Soft.VSync := 1;
    except
      on E: EPMLUnsupported do
        Raised := True;
    end;
    Check(Raised and (Soft.VSync = 0), 'サーフェスへ描くレンダラの VSync 1 は EPMLUnsupported');
    Soft.Free;
    S.Free;

    WriteLn;
    WriteLn('5. 破棄の順序');
    R.Free;
    Check(Win.DependentCount = 0, 'レンダラを先に Free するとウィンドウの一覧から外れる');

    Destroyed := 0;
    R2 := TProbeRenderer.CreateForWindow(Win);
    // テクスチャを持たせたまま消す。テクスチャはレンダラと一緒に畳まれる。
    Img := TPMLSurface.Create(1, 1, PML_PIXELFORMAT_XRGB8888);
    R2.CreateTextureFromSurface(Img);
    Img.Free;
    Win.Free;
    Check(Destroyed = 1, 'ウィンドウを先に Free するとレンダラも消える');

    Win2 := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('left alive', 16, 16));
    TProbeRenderer.CreateForWindow(Win2);
    Check(Win2.DependentCount = 1, '2 つ目のウィンドウに登録される');
  finally
    Destroyed := 0;
    Ctx.Free;
  end;
  Check(Destroyed = 1, 'Context を破棄すると、残ったウィンドウのレンダラも消える');

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: ウィンドウへ描くレンダラが設計どおりに動く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
