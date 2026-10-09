{
  test_render_target — 描画先のテクスチャ（SetRenderTarget、#41）を検証する

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    Access = Target のテクスチャへ描き、それを転送元にしてウィンドウ側へ描けること、
    見え方（ビューポート・クリップ・拡大率・論理解像度）が描画先ごとに別であること、
    出力の大きさ（GetOutputSize はウィンドウ側、GetCurrentOutputSize は描画先）、
    描画先の間の ReadPixels と Present、引数の検査、描画先のテクスチャを消したら
    ウィンドウ側へ戻ること、切り替える前に積んだ描画が前の描画先に描かれること、
    ウィンドウの座標との変換が描画先によらずウィンドウ側の見え方で行われること。

  WHY:
    描画先は見え方の入れ替えとドライバの描画先の差し替えの両方が要る。片方だけでも
    1 枚目の絵はそれらしく見えるので、入れ替えの往復と、積んだ描画の行き先を
    別々に確かめる。

  実行前提: 無し（ソフトウェアのドライバ。ウィンドウはダミーのビデオ）。
}
program test_render_target;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Video,
  PaPiMeLa.Video.Dummy,
  PaPiMeLa.Render,
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

function Same(const A, B: TPMLColor): Boolean;
begin
  Result := (A.R = B.R) and (A.G = B.G) and (A.B = B.B);
end;

function ColorStr(const C: TPMLColor): String;
begin
  Result := Format('%d,%d,%d', [C.R, C.G, C.B]);
end;

function SameRect(const A: TPMLRect; AX, AY, AW, AH: Integer): Boolean;
begin
  Result := (A.X = AX) and (A.Y = AY) and (A.W = AW) and (A.H = AH);
end;

const
  RED  : TPMLColor = (R: 255; G: 0; B: 0; A: 255);
  GREEN: TPMLColor = (R: 0; G: 255; B: 0; A: 255);
  BLUE : TPMLColor = (R: 0; G: 0; B: 255; A: 255);
  GRAY : TPMLColor = (R: 40; G: 40; B: 40; A: 255);
  WHITE: TPMLColor = (R: 255; G: 255; B: 255; A: 255);

procedure TestDrawIntoTarget;
var
  Out_: TPMLSurface;
  R: TPMLRenderer;
  T, Plain: TPMLTexture;
  W, H: Integer;
  P: TPMLSurface;
  Raised: Boolean;
begin
  WriteLn('1. 描画先へ描いて、それを転送する');
  Out_ := TPMLSurface.Create(32, 24, PML_PIXELFORMAT_XRGB8888);
  R := TPMLRenderer.CreateSoftware(Out_);
  try
    T := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Target, 8, 6);
    Check(R.RenderTarget = nil, '最初の描画先はサーフェス（nil）');
    R.RenderTarget := T;
    Check(R.RenderTarget = T, '描画先をテクスチャにできる');
    Check(R.GetCurrentOutputSize(W, H) and (W = 8) and (H = 6), 'GetCurrentOutputSize は描画先の大きさ（8x6）');
    Check(R.GetOutputSize(W, H) and (W = 32) and (H = 24), 'GetOutputSize は出力の大きさのまま（32x24）');
    R.DrawColor := RED;
    R.Clear;
    R.DrawColor := GREEN;
    R.FillRect(TPMLFRect.Make(2, 1, 3, 2));
    P := R.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    try
      Check((P.Width = 8) and (P.Height = 6) and Same(P.ReadPixel(0, 0), RED) and Same(P.ReadPixel(3, 2), GREEN),
        'ReadPixels は描画先（テクスチャ）を読む');
    finally
      P.Free;
    end;
    Raised := False;
    try
      R.Present;
    except
      on E: EPMLArgument do Raised := True;
    end;
    Check(Raised, '描画先がテクスチャの間の Present は EPMLArgument');

    R.RenderTarget := nil;
    R.DrawColor := GRAY;
    R.Clear;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(4, 4, 16, 12));
    R.Present;
    Check(Same(Out_.ReadPixel(0, 0), GRAY) and Same(Out_.ReadPixel(4, 4), RED)
      and Same(Out_.ReadPixel(8, 6), GREEN) and Same(Out_.ReadPixel(13, 9), GREEN)
      and Same(Out_.ReadPixel(14, 10), RED) and Same(Out_.ReadPixel(19, 15), RED)
      and Same(Out_.ReadPixel(20, 16), GRAY),
      'テクスチャに描いた絵を 2 倍で転送できる: ' + ColorStr(Out_.ReadPixel(8, 6)));

    WriteLn;
    WriteLn('2. 引数の検査');
    Plain := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Static, 4, 4);
    Raised := False;
    try
      R.RenderTarget := Plain;
    except
      on E: EPMLArgument do Raised := True;
    end;
    Check(Raised and (R.RenderTarget = nil), 'Access = Target でないテクスチャは EPMLArgument');
  finally
    R.Free;
    Out_.Free;
  end;
  WriteLn;
end;

procedure TestViews;
var
  Out_: TPMLSurface;
  R: TPMLRenderer;
  T, U: TPMLTexture;
  LW, LH: Integer;
  Mode: TPMLLogicalPresentation;
begin
  WriteLn('3. 見え方は描画先ごと');
  Out_ := TPMLSurface.Create(40, 30, PML_PIXELFORMAT_XRGB8888);
  R := TPMLRenderer.CreateSoftware(Out_);
  try
    T := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Target, 10, 10);
    U := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Target, 12, 8);
    R.Viewport := TPMLRect.Make(5, 5, 20, 10);
    R.ClipRect := TPMLRect.Make(6, 6, 4, 4);
    R.Scale := TPMLFPoint.Make(2, 2);
    R.SetLogicalPresentation(20, 15, TPMLLogicalPresentation.Letterbox);

    R.RenderTarget := T;
    R.GetLogicalPresentation(LW, LH, Mode);
    Check(R.Viewport.IsEmpty and not R.ClipEnabled and (R.Scale.X = 1) and (R.Scale.Y = 1)
      and (Mode = TPMLLogicalPresentation.Disabled),
      '新しい描画先は自分の見え方（ビューポート無し、クリップ無し、倍率 1、論理解像度無し）');
    R.Viewport := TPMLRect.Make(1, 2, 3, 4);
    R.Scale := TPMLFPoint.Make(3, 3);
    R.RenderTarget := U;
    Check(R.Viewport.IsEmpty and (R.Scale.X = 1), '別の描画先もそれぞれ自分の見え方');
    R.RenderTarget := nil;
    R.GetLogicalPresentation(LW, LH, Mode);
    Check(SameRect(R.Viewport, 5, 5, 20, 10) and R.ClipEnabled and SameRect(R.ClipRect, 6, 6, 4, 4)
      and (R.Scale.X = 2) and (LW = 20) and (LH = 15) and (Mode = TPMLLogicalPresentation.Letterbox),
      'ウィンドウ側へ戻すと、ウィンドウ側の見え方が戻る');
    R.RenderTarget := T;
    Check(SameRect(R.Viewport, 1, 2, 3, 4) and (R.Scale.X = 3), 'テクスチャへ戻すと、テクスチャの見え方が戻る');

    // 描画先の見え方で描かれる: ビューポート (1,2) と倍率 3 なら (1,1) は描画先の (4,5)
    R.Viewport := TPMLRect.Make(0, 0, 0, 0);
    R.Scale := TPMLFPoint.Make(1, 1);
    R.DrawColor := BLUE;
    R.Clear;
    R.Viewport := TPMLRect.Make(1, 2, 9, 8);
    R.Scale := TPMLFPoint.Make(2, 2);
    R.DrawColor := WHITE;
    R.FillRect(TPMLFRect.Make(1, 1, 1, 1));
    R.RenderTarget := nil;
    R.RenderTarget := T;
    R.Viewport := TPMLRect.Make(0, 0, 0, 0);
    R.Scale := TPMLFPoint.Make(1, 1);
    R.Flush;
    R.RenderTarget := nil;
    R.DrawColor := GRAY;
    R.Viewport := TPMLRect.Make(0, 0, 0, 0);
    R.ClipRect := TPMLRect.Make(0, 0, 0, 0);
    R.Scale := TPMLFPoint.Make(1, 1);
    R.SetLogicalPresentation(0, 0, TPMLLogicalPresentation.Disabled);
    R.Clear;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 10, 10));
    R.Present;
    // ビューポートの原点も倍率で写る（SDL3 と同じ）: ビューポート (1,2) x 2 = (2,4)。そこに
    // (1,1) x 2 = (2,2) を足して、描画先の (4, 6) から 2x2
    Check(Same(Out_.ReadPixel(4, 6), WHITE) and Same(Out_.ReadPixel(5, 7), WHITE)
      and Same(Out_.ReadPixel(3, 6), BLUE) and Same(Out_.ReadPixel(6, 8), BLUE)
      and Same(Out_.ReadPixel(4, 5), BLUE),
      '描画先のビューポートと倍率で描かれる（ウィンドウ側の見え方は使わない）');
  finally
    R.Free;
    Out_.Free;
  end;
  WriteLn;
end;

procedure TestQueueAndDestroy;
var
  Out_: TPMLSurface;
  R: TPMLRenderer;
  T: TPMLTexture;
  P: TPMLSurface;
begin
  WriteLn('4. 切り替える前に積んだ描画・描画先の破棄');
  Out_ := TPMLSurface.Create(16, 16, PML_PIXELFORMAT_XRGB8888);
  R := TPMLRenderer.CreateSoftware(Out_);
  try
    T := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Target, 4, 4);
    R.DrawColor := GRAY;
    R.Clear;                      // 積むだけ（まだ描かない）
    R.RenderTarget := T;          // ここで描き切ってから切り替える
    R.DrawColor := RED;
    R.Clear;
    R.RenderTarget := nil;
    R.Present;
    Check(Same(Out_.ReadPixel(10, 10), GRAY), '切り替える前に積んだ Clear はサーフェスに描かれる');
    P := nil;
    R.RenderTarget := T;
    try
      P := R.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
      Check(Same(P.ReadPixel(1, 1), RED), '切り替えた後の Clear はテクスチャに描かれる');
    finally
      P.Free;
    end;
    T.Free;
    Check(R.RenderTarget = nil, '描画先のテクスチャを消すと描画先はサーフェスへ戻る');
    R.DrawColor := BLUE;
    R.Clear;
    R.Present;
    Check(Same(Out_.ReadPixel(0, 0), BLUE), '戻った後の描画はサーフェスに描かれる');
  finally
    R.Free;
    Out_.Free;
  end;
  WriteLn;
end;

procedure TestWindow;
var
  Ctx: TPMLContext;
  Opts: TPMLContextOptions;
  Win: TPMLWindow;
  R: TPMLRenderer;
  T: TPMLTexture;
  A, B: TPMLFPoint;
  W, H: Integer;
  P: TPMLSurface;
begin
  WriteLn('5. ウィンドウへ描くレンダラ');
  Opts := TPMLContextOptions.Default;
  Opts.PreferredVideo := 'dummy';
  Ctx := TPMLContext.Create([TPMLSubsystem.Video], Opts);
  try
    Win := Ctx.Video.CreateWindow(TPMLWindowOptions.Make('target', 64, 48));
    R := TPMLRenderer.CreateForWindow(Win);
    R.SetLogicalPresentation(32, 24, TPMLLogicalPresentation.Letterbox);
    A := R.RenderCoordinatesFromWindow(40, 30);
    T := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Target, 8, 8);
    R.RenderTarget := T;
    R.Scale := TPMLFPoint.Make(4, 4);
    B := R.RenderCoordinatesFromWindow(40, 30);
    Check((A.X = B.X) and (A.Y = B.Y),
      Format('ウィンドウの座標との変換はウィンドウ側の見え方（%g,%g と %g,%g）', [A.X, A.Y, B.X, B.Y]));
    Check((R.Scale.X = 4) and (R.RenderTarget = T), '変換の後も描画先の見え方のまま');
    R.DrawColor := GREEN;
    R.Clear;
    R.RenderTarget := nil;
    Check(R.GetOutputSize(W, H) and (W = 64) and (H = 48), 'ウィンドウの出力の大きさ');
    R.DrawColor := GRAY;
    R.Clear;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 8, 8));
    // 論理画面 32x24 を 64x48 に 2 倍で置くので、(0,0)-(8,8) は (0,0)-(16,16) の画素
    P := R.ReadPixels(TPMLRect.Make(0, 0, 0, 0));
    try
      Check(Same(P.ReadPixel(5, 5), GREEN) and Same(P.ReadPixel(15, 15), GREEN)
        and Same(P.ReadPixel(16, 16), GRAY),
        'ウィンドウのフレームバッファへ、描画先に描いた絵を論理画面の倍率で転送する: ' +
        ColorStr(P.ReadPixel(5, 5)));
    finally
      P.Free;
    end;
    R.Present;
  finally
    Ctx.Free;
  end;
  WriteLn;
end;

begin
  WriteLn('test_render_target — 描画先のテクスチャ');
  WriteLn;
  TestDrawIntoTarget;
  TestViews;
  TestQueueAndDestroy;
  TestWindow;
  if Failures = 0 then
    WriteLn('=== 結論: 描画先のテクスチャが SDL の約束どおりに動く ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
