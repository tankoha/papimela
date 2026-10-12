{
  test_texture_kinds — テクスチャの種類（拡大の方式 PIXELART、パレット、YUV）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 拡大の方式 PixelArt（SDL_SCALEMODE_PIXELART）。SDL のソフトウェアのレンダラと
       サーフェスの拡大は PIXELART を NEAREST と同じに扱う。papimela も同じ絵になる
    （パレットと YUV の節は §3 の 3b / 3c で足す）

  WHY:
    §3 の 3（テクスチャの種類）の受け入れ検査。表示サーバは要らない。GPU のドライバの分は
    test_render_gles2 のオフスクリーンの節にある。
}
program test_texture_kinds;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.Blit,
  PaPiMeLa.Render;

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

function DiffCount(A, B: TPMLSurface): Integer;
var
  X, Y: Integer;
begin
  Result := 0;
  for Y := 0 to A.Height - 1 do
    for X := 0 to A.Width - 1 do
      if A.ReadRaw(X, Y) <> B.ReadRaw(X, Y) then
        Inc(Result);
end;

function Checker: TPMLSurface;
var
  X, Y: Integer;
begin
  Result := TPMLSurface.Create(6, 5, PML_PIXELFORMAT_ARGB8888);
  for Y := 0 to 4 do
    for X := 0 to 5 do
      Result.WritePixel(X, Y, TPMLColor.Make(Byte(X * 40), Byte(Y * 50), Byte(((X + Y) mod 2) * 255), 255));
end;

{ 6x5 の模様を 2.5 倍・1.7 倍に引き伸ばして描いた絵。 }
function RenderScaled(AMode: TPMLScaleMode): TPMLSurface;
var
  Img: TPMLSurface;
  R: TPMLRenderer;
  T: TPMLTexture;
begin
  Result := TPMLSurface.Create(40, 30, PML_PIXELFORMAT_ARGB8888);
  Img := Checker;
  R := TPMLRenderer.CreateSoftware(Result);
  try
    T := R.CreateTextureFromSurface(Img);
    T.ScaleMode := AMode;
    R.DrawColor := TPMLColor.Black;
    R.Clear;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(1, 1, 15, 12.5));
    R.RenderTexture(T, TPMLFRect.Make(1, 1, 4, 3), TPMLFRect.Make(18, 2, 6.8, 5.1));
    R.Present;
  finally
    R.Free;
    Img.Free;
  end;
end;

procedure TestPixelArt;
var
  N, P, SN, SP, Img: TPMLSurface;
begin
  WriteLn('1. 拡大の方式 PixelArt');
  Check(Ord(TPMLScaleMode.PixelArt) = 2, 'PixelArt は 3 つ目の方式（SDL_SCALEMODE_PIXELART と同じ並び）');
  N := RenderScaled(TPMLScaleMode.Nearest);
  P := RenderScaled(TPMLScaleMode.PixelArt);
  try
    Check(DiffCount(N, P) = 0, 'ソフトウェアのレンダラでは PixelArt は Nearest と同じ絵（SDL と同じ）');
  finally
    N.Free;
    P.Free;
  end;
  Img := Checker;
  SN := TPMLSurface.Create(20, 20, PML_PIXELFORMAT_ARGB8888);
  SP := TPMLSurface.Create(20, 20, PML_PIXELFORMAT_ARGB8888);
  try
    PMLBlitScaled(Img, TPMLRect.Make(0, 0, 0, 0), SN, TPMLRect.Make(0, 0, 17, 13), TPMLScaleMode.Nearest);
    PMLBlitScaled(Img, TPMLRect.Make(0, 0, 0, 0), SP, TPMLRect.Make(0, 0, 17, 13), TPMLScaleMode.PixelArt);
    Check(DiffCount(SN, SP) = 0, 'サーフェスの拡大の転送でも PixelArt は Nearest と同じ');
  finally
    Img.Free;
    SN.Free;
    SP.Free;
  end;
end;

begin
  WriteLn('test_texture_kinds — テクスチャの種類');
  WriteLn;
  TestPixelArt;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: テクスチャの種類が SDL と同じ絵になる ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
