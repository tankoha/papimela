{
  test_texture_kinds — テクスチャの種類（拡大の方式 PIXELART、パレット、YUV）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 拡大の方式 PixelArt（SDL_SCALEMODE_PIXELART）。SDL のソフトウェアのレンダラと
       サーフェスの拡大は PIXELART を NEAREST と同じに扱う。papimela も同じ絵になる
    2. パレット（INDEX8。SDL_SetTexturePalette）。パレットの版、作れないもの、描く色、
       積んだ後の色の変更、共有、部分更新、サーフェスから（写しとカラーキー）。
       ドライバが INDEX8 を直接持つときと、レンダラの肩代わりの層を通るときの 2 通り
    3. YUV（YV12 / IYUV / NV12 / NV21 / YUY2 / UYVY / YVYU）。大きさ、色空間、5 つの色空間の変換の値、
       飽和（D-62）、7 形式が同じ絵になること（奇数の大きさ、行の幅の余り）、部分の更新、
       UpdateYUV と UpdateNV、誤り

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
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.Blit,
  PaPiMeLa.Surface.YUV,
  PaPiMeLa.Render,
  PaPiMeLa.Render.Software;

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

{ ---- 2. パレット（INDEX8） ----

  期待値は参照版の SDL（docs/ORIGIN.md の版）をソフトウェアのレンダラで描かせて取った
  （docs/TEST-LOG.md の使い捨て検証）。合成の式の丸めは SDL と 1 違う（D-44）ので、
  合成のある場面は「同じ色の ARGB8888 のテクスチャと同じ絵」で比べる。

  どの場面も 2 通りのレンダラで流す。Direct はドライバが INDEX8 を直接持つ（ソフトウェアの
  ドライバ）。Fallback は INDEX8 を断るドライバで、レンダラの肩代わりの層（ARGB8888 の
  テクスチャへ写して描く。SDL の texture->native）を通る。 }

type
  { INDEX8 を持てないドライバ。肩代わりの層を通すための検査用。 }
  TNoIndexDriver = class(TPMLSoftwareRenderDriver)
  public
    function SupportsTextureFormat(AFormat: TPMLPixelFormat): Boolean; override;
  end;

  TRendererKind = (Direct, Fallback);
  TKindProc = procedure(AKind: TRendererKind);

function TNoIndexDriver.SupportsTextureFormat(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := not PMLIsPixelFormatIndexed(AFormat);
end;

const
  KindName: array[TRendererKind] of String = ('直接', '肩代わり');
  Background: LongWord = $FF102030;
  // 添字 4・200・255 はパレット（4 色）の外。SDL のソフトウェアのレンダラは白で描く。
  Indices: array[0..7] of Byte = (0, 1, 2, 3, 4, 200, 255, 1);

var
  PalColors: array[0..3] of TPMLColor;

function NewRenderer(AKind: TRendererKind; ATarget: TPMLSurface): TPMLRenderer;
begin
  if AKind = TRendererKind.Direct then
    Result := TPMLRenderer.CreateSoftware(ATarget)
  else
    Result := TPMLRenderer.Create(TNoIndexDriver.Create(ATarget));
  Result.DrawColor := TPMLColor.Make($10, $20, $30);
  Result.Clear;
end;

function NewPalette: TPMLPalette;
begin
  Result := TPMLPalette.Create(nil, nil, 4);
  Result.SetColors(PalColors);
end;

{ 添字の絵を、パレットで色に直した ARGB8888 のテクスチャ（比べる相手）。 }
function ArgbTwin(R: TPMLRenderer; const AIdx: array of Byte; AW, AH: Integer;
  APal: TPMLPalette): TPMLTexture;
var
  S: TPMLSurface;
  I: Integer;
  C: TPMLColor;
begin
  S := TPMLSurface.Create(AW, AH, PML_PIXELFORMAT_ARGB8888);
  try
    for I := 0 to AW * AH - 1 do
    begin
      if AIdx[I] < APal.Count then
        C := APal[AIdx[I]]
      else
        C := TPMLColor.White;
      S.WritePixel(I mod AW, I div AW, C);
    end;
    Result := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Static, AW, AH);
    Result.Update(TPMLRect.Make(0, 0, 0, 0), S.Pixels, S.Pitch);
  finally
    S.Free;
  end;
end;

function NewIndexed(R: TPMLRenderer; const AIdx: array of Byte; AW, AH: Integer): TPMLTexture;
begin
  Result := R.CreateTexture(PML_PIXELFORMAT_INDEX8, TPMLTextureAccess.Static, AW, AH);
  Result.Update(TPMLRect.Make(0, 0, 0, 0), @AIdx[0], AW);
end;

function RowEquals(S: TPMLSurface; AY: Integer; const AExpect: array of LongWord): Boolean;
var
  X: Integer;
begin
  Result := True;
  for X := 0 to High(AExpect) do
    if S.ReadRaw(X, AY) <> AExpect[X] then
    begin
      WriteLn(Format('      (%d, %d) = %.8x, expected %.8x', [X, AY, S.ReadRaw(X, AY), AExpect[X]]));
      Result := False;
    end;
end;

procedure TestPaletteObject;
var
  P: TPMLPalette;
  V: LongWord;
begin
  WriteLn('2.1 パレットの版');
  P := TPMLPalette.Create(nil, nil, 4);
  try
    Check(P.Version = 1, '作った直後の版は 1（SDL_CreatePalette と同じ）');
    V := P.Version;
    P[2] := TPMLColor.Make(1, 2, 3);
    Check(P.Version <> V, '1 色を変えると版が進む');
    V := P.Version;
    P.SetColors([TPMLColor.Black], 1);
    Check(P.Version <> V, 'SetColors で版が進む');
    V := P.Version;
    P.Reset;
    Check(P.Version <> V, 'Reset で版が進む');
    V := P.Version;
    P[9] := TPMLColor.Black;
    Check(P.Version = V, '範囲外の添字は何も変えず、版も進まない');
  finally
    P.Free;
  end;
end;

procedure TestPaletteErrors(AKind: TRendererKind);
var
  Out: TPMLSurface;
  R: TPMLRenderer;
  T, A: TPMLTexture;
  Big: TPMLPalette;
  Raised: Boolean;
begin
  WriteLn('2.2 作れないもの・描けないもの（', KindName[AKind], '）');
  Out := TPMLSurface.Create(16, 4, PML_PIXELFORMAT_ARGB8888);
  R := NewRenderer(AKind, Out);
  Big := TPMLPalette.Create(nil, nil, 257);
  try
    Raised := False;
    try
      R.CreateTexture(PML_PIXELFORMAT_INDEX4LSB, TPMLTextureAccess.Static, 4, 1);
    except
      on E: Exception do Raised := E is EPMLArgument;
    end;
    Check(Raised, 'INDEX4 のテクスチャは作れない（SDL も 1 画素 1 バイト未満の形式を断る）');
    Raised := False;
    try
      R.CreateTexture(PML_PIXELFORMAT_INDEX8, TPMLTextureAccess.Target, 4, 4);
    except
      on E: Exception do Raised := E is EPMLArgument;
    end;
    Check(Raised, 'INDEX8 は描画先にできない');
    A := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Static, 4, 4);
    Raised := False;
    try
      A.SetPalette(Big);
    except
      on E: Exception do Raised := E is EPMLArgument;
    end;
    Check(Raised, 'インデックス形式でないテクスチャにはパレットを付けられない');
    T := NewIndexed(R, Indices, 8, 1);
    Check(T.Palette = nil, '作った直後はパレットが無い');
    Raised := False;
    try
      T.SetPalette(Big);
    except
      on E: Exception do Raised := E is EPMLArgument;
    end;
    Check(Raised and (T.Palette = nil), '257 色のパレットは付けられない');
    Raised := False;
    try
      R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 8, 1));
    except
      on E: Exception do Raised := E is EPMLRenderError;
    end;
    Check(Raised, 'パレットの無い INDEX8 を描くと EPMLRenderError（SDL は「Texture doesn''t have a palette」）');
  finally
    R.Free;
    Big.Free;
    Out.Free;
  end;
end;

procedure TestPaletteDraw(AKind: TRendererKind);
var
  Out, Twin: TPMLSurface;
  R, R2: TPMLRenderer;
  T, A, T2: TPMLTexture;
  P: TPMLPalette;
  Q: TPMLPalette;
  M: TPMLScaleMode;
  Part: array[0..1] of Byte;
  Idx2: array[0..3] of Byte = (0, 1, 2, 1);

  procedure Both(ABlend: TPMLBlendMode);
  begin
    T.BlendMode := ABlend;
    A.BlendMode := ABlend;
  end;

begin
  WriteLn('2.3 描く（', KindName[AKind], '）');
  Out := TPMLSurface.Create(16, 8, PML_PIXELFORMAT_ARGB8888);
  Twin := TPMLSurface.Create(16, 8, PML_PIXELFORMAT_ARGB8888);
  P := NewPalette;
  R := NewRenderer(AKind, Out);
  R2 := NewRenderer(AKind, Twin);
  try
    T := NewIndexed(R, Indices, 8, 1);
    T.SetPalette(P);
    Check(T.Palette = P, 'Palette は付けたパレットを返す');
    Check(T.BlendMode = TPMLBlendMode.None, 'INDEX8 の既定の合成は None（SDL と同じ）');
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 8, 1));
    R.Present;
    Check(RowEquals(Out, 0, [$FFFF0000, $FF00FF00, $800000FF, $00FFFF00,
      $FFFFFFFF, $FFFFFFFF, $FFFFFFFF, $FF00FF00]),
      '合成なしの 1:1 はパレットの色がそのまま入る。範囲外の添字は白（SDL と同じ値）');

    // 合成・変調・拡大・回転は、同じ色の ARGB8888 のテクスチャと同じ絵になる。
    A := ArgbTwin(R2, Indices, 8, 1, P);
    Both(TPMLBlendMode.Blend);
    R.Clear;
    R2.Clear;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 8, 1));
    R2.RenderTexture(A, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 8, 1));
    T.ColorMod := TPMLColor.Make(128, 255, 64);
    T.AlphaMod := 128;
    A.ColorMod := T.ColorMod;
    A.AlphaMod := 128;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(8, 0, 8, 1));
    R2.RenderTexture(A, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(8, 0, 8, 1));
    T.ColorMod := TPMLColor.White;
    T.AlphaMod := 255;
    A.ColorMod := TPMLColor.White;
    A.AlphaMod := 255;
    R.Present;
    R2.Present;
    Check(DiffCount(Out, Twin) = 0, 'Blend と変調は ARGB8888 のテクスチャと同じ絵');
    A.Free;

    // 積んだ後に色を変える（SDL の FlushRenderCommandsIfPaletteNeeded）
    Both(TPMLBlendMode.None);
    R.Clear;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 8, 1));
    P[0] := TPMLColor.Make(10, 20, 30);
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(8, 0, 8, 1));
    R.Present;
    Check((Out.ReadRaw(0, 0) = $FFFF0000) and (Out.ReadRaw(8, 0) = $FF0A141E),
      '色を変える前に積んだ描画は前の色、後に積んだ描画は新しい色（SDL と同じ）');
    R.Clear;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 8, 1));
    P[0] := TPMLColor.Make(40, 50, 60);
    R.Present;
    Check(Out.ReadRaw(0, 0) = $FF0A141E,
      '最後に描いた後で色を変えても、積んであった描画は前の色のまま（SDL と同じ）');
    R.Clear;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 8, 1));
    R.Present;
    Check(Out.ReadRaw(0, 0) = $FF28323C, '次に描くと新しい色になる');
    P.SetColors(PalColors);
    R.Clear;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 8, 1));
    R.Present;

    // 部分更新（パレットは変えずに。肩代わりでも添字の変更だけで写し直す）
    Part[0] := 3;
    Part[1] := 3;
    T.Update(TPMLRect.Make(2, 0, 2, 1), @Part[0], 2);
    R.Clear;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 8, 1));
    R.Present;
    Check(RowEquals(Out, 0, [$FFFF0000, $FF00FF00, $00FFFF00, $00FFFF00, $FFFFFFFF]),
      '部分更新した添字が描かれる');
    T.Update(TPMLRect.Make(0, 0, 0, 0), @Indices[0], 8);

    // 拡大の方式と回転（三角形の経路）
    T2 := NewIndexed(R, Idx2, 2, 2);
    T2.SetPalette(P);
    A := ArgbTwin(R2, Idx2, 2, 2, P);
    for M := Low(TPMLScaleMode) to High(TPMLScaleMode) do
    begin
      if M = TPMLScaleMode.Linear then
        Continue;     // ソフトウェアのドライバの Linear は Nearest（§3 の 4）。GPU は test_render_gles2
      T2.ScaleMode := M;
      A.ScaleMode := M;
      R.Clear;
      R2.Clear;
      R.RenderTexture(T2, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 7, 7));
      R2.RenderTexture(A, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 7, 7));
      R.RenderTextureRotated(T2, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(8, 0, 4, 4), 90);
      R2.RenderTextureRotated(A, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(8, 0, 4, 4), 90);
      R.Present;
      R2.Present;
      Check(DiffCount(Out, Twin) = 0, Format('拡大（%d）と回転は ARGB8888 のテクスチャと同じ絵', [Ord(M)]));
    end;
    Check((Out.ReadRaw(8, 0) <> Background) and (Out.ReadRaw(10, 0) = $FFFF0000)
      and (Out.ReadRaw(8, 3) = $FF00FF00), '90 度の回転の角の色（SDL と同じ配置）');

    // 2 つのテクスチャで 1 つのパレットを共有する
    T.SetPalette(nil);
    Check(T.Palette = nil, 'nil で外せる');
    P[1] := TPMLColor.Make(1, 2, 3);
    T2.ScaleMode := TPMLScaleMode.Nearest;
    R.Clear;
    R.RenderTexture(T2, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 2, 2));
    R.Present;
    Check(Out.ReadRaw(1, 0) = $FF010203, '片方から外しても、もう片方は描けて、色の変更も効く');
    T.SetPalette(P);
    R.Clear;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 8, 1));
    R.RenderTexture(T2, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(8, 0, 2, 2));
    R.Present;
    Check((Out.ReadRaw(1, 0) = $FF010203) and (Out.ReadRaw(9, 0) = $FF010203),
      '付け直すと、共有したパレットの今の色で描く');

    // 積んだ後にパレットを替える。前のパレットは T2 も使っているので残る（D-61）
    Q := TPMLPalette.Create(nil, nil, 4);
    try
      Q[0] := TPMLColor.Make(0, 0, 255);
      P[0] := TPMLColor.Make(255, 0, 0);
      R.Clear;
      R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 8, 1));
      T.SetPalette(Q);
      R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(8, 0, 8, 1));
      R.Present;
      Check((Out.ReadRaw(0, 0) = $FFFF0000) and (Out.ReadRaw(8, 0) = $FF0000FF),
        'パレットを替える前に積んだ描画は前のパレットで描く（参照版の SDL は、前のパレットを別のテクスチャが共有していると新しい色で描く。D-61）');
      T.SetPalette(P);
    finally
      Q.Free;
    end;
    A.Free;
  finally
    R.Free;
    R2.Free;
    P.Free;
    Out.Free;
    Twin.Free;
  end;
end;

procedure TestPaletteFromSurface(AKind: TRendererKind);
var
  Out: TPMLSurface;
  R: TPMLRenderer;
  S: TPMLSurface;
  SP: TPMLPalette;
  T: TPMLTexture;
  I: Integer;
begin
  WriteLn('2.4 サーフェスから（', KindName[AKind], '）');
  Out := TPMLSurface.Create(16, 4, PML_PIXELFORMAT_ARGB8888);
  R := NewRenderer(AKind, Out);
  S := TPMLSurface.Create(4, 1, PML_PIXELFORMAT_INDEX8);
  SP := NewPalette;
  S.SetPalette(SP, True);
  for I := 0 to 3 do
    S.WriteRaw(I, 0, I);
  try
    T := R.CreateTextureFromSurface(S);
    Check(T.Format = PML_PIXELFORMAT_INDEX8, 'パレットつきの INDEX8 のサーフェスは INDEX8 のテクスチャになる');
    Check((T.Palette <> nil) and (T.Palette <> SP) and (T.Palette.Count = 4),
      'パレットは写しを持つ（SDL 3.4.2 と同じ。参照版は共有する。下の D-60 を参照）');
    SP[0] := TPMLColor.Make(1, 2, 3);
    FreeAndNil(S);     // サーフェスを消しても描ける
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 4, 1));
    R.Present;
    Check(RowEquals(Out, 0, [$FFFF0000, $FF00FF00, $800000FF, $00FFFF00]),
      'サーフェスのパレットを後で変えても、サーフェスを消しても、作ったときの色で描く');

    // カラーキー: キーの色を透明にして Blend にする。サーフェスのパレットは変えない（D-60）
    S := TPMLSurface.Create(4, 1, PML_PIXELFORMAT_INDEX8);
    SP := NewPalette;
    SP[2] := TPMLColor.Make(0, 0, 255);
    S.SetPalette(SP, True);
    for I := 0 to 3 do
      S.WriteRaw(I, 0, I);
    S.SetColorKey(True, 1);
    T := R.CreateTextureFromSurface(S);
    Check(T.BlendMode = TPMLBlendMode.Blend, 'カラーキーつきは Blend（SDL と同じ）');
    Check(T.Palette[1].A = 0, 'テクスチャのパレットでキーの色が透明になる');
    Check(SP[1].A = 255, 'サーフェスのパレットは書き換えない（参照版の SDL は書き換える。D-60）');
    R.Clear;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 4, 1));
    R.Present;
    Check(RowEquals(Out, 0, [$FFFF0000, $FF102030, $FF0000FF]), 'キーの画素は描かれない');

    // パレットの無い INDEX8 のサーフェスは、今までどおり ARGB8888 に直して作る
    FreeAndNil(S);
    S := TPMLSurface.Create(4, 1, PML_PIXELFORMAT_INDEX8);
    T := R.CreateTextureFromSurface(S);
    Check(T.Format = PML_PIXELFORMAT_ARGB8888, 'パレットの無い INDEX8 のサーフェスは ARGB8888 のテクスチャになる');
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 4, 1));
    R.Present;
  finally
    S.Free;
    R.Free;
    Out.Free;
  end;
end;

{ 1 つの節で思わぬ例外が出ても、失敗に数えて次の節へ進む。 }
procedure Guard(AProc: TKindProc; AKind: TRendererKind);
begin
  try
    AProc(AKind);
  except
    on E: Exception do
      Check(False, '思わぬ例外: ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure TestPalette;
var
  K: TRendererKind;
begin
  PalColors[0] := TPMLColor.Make(255, 0, 0, 255);
  PalColors[1] := TPMLColor.Make(0, 255, 0, 255);
  PalColors[2] := TPMLColor.Make(0, 0, 255, 128);
  PalColors[3] := TPMLColor.Make(255, 255, 0, 0);
  TestPaletteObject;
  for K := Low(TRendererKind) to High(TRendererKind) do
  begin
    Guard(@TestPaletteErrors, K);
    Guard(@TestPaletteDraw, K);
    Guard(@TestPaletteFromSurface, K);
  end;
end;

{ ---- 3. YUV（YV12 / IYUV / NV12 / NV21 / YUY2 / UYVY / YVYU） ----

  期待値は参照版の SDL をソフトウェアのレンダラで描かせて取った（docs/TEST-LOG.md の使い捨て検証）。
  ソフトウェアのレンダラは YUV を持たないので、どれもレンダラの肩代わりの層（ARGB8888 へ直す）を通る。

  絵は「論理の YUV」（Y は画素ごと、U と V は 2x2 の区画ごと）から各形式に詰めて作る。4:2:2 の形式は
  同じ区画の色を 2 行で使うので、どの形式でも同じ絵になるはず。 }

type
  TYUVImage = record
    W, H, CW, CH: Integer;
    Y, U, V: TBytes;
  end;

const
  YUVFormats: array[0..6] of TPMLPixelFormat = (
    PML_PIXELFORMAT_YV12, PML_PIXELFORMAT_IYUV, PML_PIXELFORMAT_NV12, PML_PIXELFORMAT_NV21,
    PML_PIXELFORMAT_YUY2, PML_PIXELFORMAT_UYVY, PML_PIXELFORMAT_YVYU);

var
  Lcg: LongWord;

function NextByte: Byte;
begin
  Lcg := Lcg * 1103515245 + 12345;
  Result := Byte(Lcg shr 16);
end;

function MakeYUV(AW, AH: Integer; ASeed: LongWord): TYUVImage;
var
  I: Integer;
begin
  Result.W := AW;
  Result.H := AH;
  Result.CW := (AW + 1) div 2;
  Result.CH := (AH + 1) div 2;
  SetLength(Result.Y, AW * AH);
  SetLength(Result.U, Result.CW * Result.CH);
  SetLength(Result.V, Result.CW * Result.CH);
  Lcg := ASeed;
  for I := 0 to High(Result.Y) do
    Result.Y[I] := NextByte;
  for I := 0 to High(Result.U) do
  begin
    Result.U[I] := NextByte;
    Result.V[I] := NextByte;
  end;
end;

function IsPacked422(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := (AFormat = PML_PIXELFORMAT_YUY2) or (AFormat = PML_PIXELFORMAT_UYVY)
    or (AFormat = PML_PIXELFORMAT_YVYU);
end;

{ 論理の YUV を AFormat の詰めた画素にする。APitch は Y の行の幅（0 なら詰める）。
  平面の形式の U・V の行の幅は SDL と同じく (APitch + 1) div 2。 }
function PackYUV(const AImg: TYUVImage; AFormat: TPMLPixelFormat; var APitch: Integer): TBytes;
var
  X, Y, CP, Base, I, YB: Integer;
  YV, UV: Byte;
  Q: array[0..3] of Byte;
begin
  Result := nil;
  if IsPacked422(AFormat) then
  begin
    if APitch = 0 then
      APitch := AImg.CW * 4;
    SetLength(Result, APitch * AImg.H);
    FillChar(Result[0], Length(Result), 0);
    for Y := 0 to AImg.H - 1 do
      for X := 0 to AImg.CW - 1 do
      begin
        Base := Y * APitch + X * 4;
        I := (Y div 2) * AImg.CW + X;
        YV := AImg.Y[Y * AImg.W + X * 2];
        if X * 2 + 1 < AImg.W then
          YB := AImg.Y[Y * AImg.W + X * 2 + 1]
        else
          YB := 0;
        if AFormat = PML_PIXELFORMAT_YUY2 then
        begin
          Q[0] := YV; Q[1] := AImg.U[I]; Q[2] := YB; Q[3] := AImg.V[I];
        end
        else if AFormat = PML_PIXELFORMAT_UYVY then
        begin
          Q[0] := AImg.U[I]; Q[1] := YV; Q[2] := AImg.V[I]; Q[3] := YB;
        end
        else
        begin
          Q[0] := YV; Q[1] := AImg.V[I]; Q[2] := YB; Q[3] := AImg.U[I];
        end;
        Move(Q[0], Result[Base], 4);
      end;
    Exit;
  end;
  if APitch = 0 then
    APitch := AImg.W;
  CP := (APitch + 1) div 2;
  if (AFormat = PML_PIXELFORMAT_NV12) or (AFormat = PML_PIXELFORMAT_NV21) then
    CP := 2 * CP;
  if (AFormat = PML_PIXELFORMAT_NV12) or (AFormat = PML_PIXELFORMAT_NV21) then
    SetLength(Result, APitch * AImg.H + CP * AImg.CH)
  else
    SetLength(Result, APitch * AImg.H + 2 * CP * AImg.CH);
  FillChar(Result[0], Length(Result), 0);
  for Y := 0 to AImg.H - 1 do
    Move(AImg.Y[Y * AImg.W], Result[Y * APitch], AImg.W);
  Base := APitch * AImg.H;
  for Y := 0 to AImg.CH - 1 do
    for X := 0 to AImg.CW - 1 do
    begin
      I := Y * AImg.CW + X;
      if AFormat = PML_PIXELFORMAT_IYUV then
      begin
        Result[Base + Y * CP + X] := AImg.U[I];
        Result[Base + CP * AImg.CH + Y * CP + X] := AImg.V[I];
      end
      else if AFormat = PML_PIXELFORMAT_YV12 then
      begin
        Result[Base + Y * CP + X] := AImg.V[I];
        Result[Base + CP * AImg.CH + Y * CP + X] := AImg.U[I];
      end
      else
      begin
        if AFormat = PML_PIXELFORMAT_NV12 then
          UV := AImg.U[I]
        else
          UV := AImg.V[I];
        Result[Base + Y * CP + X * 2] := UV;
        if AFormat = PML_PIXELFORMAT_NV12 then
          Result[Base + Y * CP + X * 2 + 1] := AImg.V[I]
        else
          Result[Base + Y * CP + X * 2 + 1] := AImg.U[I];
      end;
    end;
end;

{ AFormat のテクスチャに AImg を詰めて入れ、1:1 で描いた絵（呼び出し側が Free）。 }
function DrawYUV(const AImg: TYUVImage; AFormat: TPMLPixelFormat; AColorspace: TPMLColorspace;
  APitch: Integer = 0): TPMLSurface;
var
  R: TPMLRenderer;
  T: TPMLTexture;
  Buf: TBytes;
begin
  Result := TPMLSurface.Create(AImg.W, AImg.H, PML_PIXELFORMAT_ARGB8888);
  R := TPMLRenderer.CreateSoftware(Result);
  try
    T := R.CreateTexture(AFormat, TPMLTextureAccess.Static, AImg.W, AImg.H, AColorspace);
    Buf := PackYUV(AImg, AFormat, APitch);
    T.Update(TPMLRect.Make(0, 0, 0, 0), @Buf[0], APitch);
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 0, 0));
    R.Present;
  finally
    R.Free;
  end;
end;

function RowsEqual(S: TPMLSurface; const AExpect: array of LongWord): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to High(AExpect) do
    if S.ReadRaw(I mod S.Width, I div S.Width) <> AExpect[I] then
    begin
      WriteLn(Format('      (%d, %d) = %.8x, expected %.8x', [I mod S.Width, I div S.Width,
        S.ReadRaw(I mod S.Width, I div S.Width), AExpect[I]]));
      Result := False;
    end;
end;

function FixedImage: TYUVImage;
const
  Ys: array[0..7] of Byte = (16, 81, 145, 235, 128, 60, 200, 30);
begin
  Result.W := 4;
  Result.H := 2;
  Result.CW := 2;
  Result.CH := 1;
  SetLength(Result.Y, 8);
  Move(Ys[0], Result.Y[0], 8);
  SetLength(Result.U, 2);
  SetLength(Result.V, 2);
  Result.U[0] := 90;
  Result.U[1] := 200;
  Result.V[0] := 240;
  Result.V[1] := 60;
end;

function FlatImage(AW, AH: Integer; AY, AU, AV: Byte): TYUVImage;
begin
  Result.W := AW;
  Result.H := AH;
  Result.CW := (AW + 1) div 2;
  Result.CH := (AH + 1) div 2;
  SetLength(Result.Y, AW * AH);
  SetLength(Result.U, Result.CW * Result.CH);
  SetLength(Result.V, Result.CW * Result.CH);
  FillChar(Result.Y[0], Length(Result.Y), AY);
  FillChar(Result.U[0], Length(Result.U), AU);
  FillChar(Result.V[0], Length(Result.V), AV);
end;

procedure TestYUVBasics;
var
  Size: PtrUInt;
  Pitch, I: Integer;
  Kind: TPMLYCbCrType;
  Ok: Boolean;
begin
  WriteLn('3.1 形式・大きさ・色空間');
  Ok := True;
  for I := 0 to High(YUVFormats) do
    if not PMLIsYUVFormat(YUVFormats[I]) then
      Ok := False;
  Check(Ok and not PMLIsYUVFormat(PML_PIXELFORMAT_P010) and PMLIsYUVFormat(PML_PIXELFORMAT_I444)
    and not PMLIsYUVFormat(PML_PIXELFORMAT_ARGB8888), '変換できる YUV は 8 形式（7 形式 + I444。P010 は持たない）');
  Check(PMLCalculateYUVSize(PML_PIXELFORMAT_IYUV, 7, 5, Size, Pitch) and (Size = 59) and (Pitch = 7),
    'IYUV 7x5 は 59 バイト、行の幅 7（SDL_CalculateYUVSize と同じ）');
  Check(PMLCalculateYUVSize(PML_PIXELFORMAT_NV21, 7, 5, Size, Pitch) and (Size = 59) and (Pitch = 7),
    'NV21 7x5 は 59 バイト、行の幅 7');
  Check(PMLCalculateYUVSize(PML_PIXELFORMAT_YUY2, 7, 5, Size, Pitch) and (Size = 80) and (Pitch = 16),
    'YUY2 7x5 は 80 バイト、行の幅 16');
  Check(not PMLCalculateYUVSize(PML_PIXELFORMAT_ARGB8888, 7, 5, Size, Pitch), 'YUV でなければ False');
  Check(PMLYCbCrTypeOf(PML_COLORSPACE_JPEG, Kind) and (Kind = TPMLYCbCrType.BT601Full)
    and PMLYCbCrTypeOf(PML_COLORSPACE_BT601_FULL, Kind) and (Kind = TPMLYCbCrType.BT601Full)
    and PMLYCbCrTypeOf(PML_COLORSPACE_BT601_LIMITED, Kind) and (Kind = TPMLYCbCrType.BT601Limited)
    and PMLYCbCrTypeOf(PML_COLORSPACE_BT709_FULL, Kind) and (Kind = TPMLYCbCrType.BT709Full)
    and PMLYCbCrTypeOf(PML_COLORSPACE_BT709_LIMITED, Kind) and (Kind = TPMLYCbCrType.BT709Limited)
    and PMLYCbCrTypeOf(PML_COLORSPACE_BT2020_FULL, Kind) and (Kind = TPMLYCbCrType.BT2020Full),
    '色空間から変換の種類を選ぶ（JPEG と BT.601 の全範囲は同じ）');
  Check(not PMLYCbCrTypeOf(PML_COLORSPACE_BT2020_LIMITED, Kind) and not PMLYCbCrTypeOf(PML_COLORSPACE_SRGB, Kind),
    'BT.2020 の限定範囲と SRGB は選べない（SDL と同じ）');
  Check(PMLDefaultColorspace(PML_PIXELFORMAT_NV12) = PML_COLORSPACE_BT601_LIMITED,
    'YUV の既定の色空間は BT.601 の限定範囲');
end;

procedure TestYUVValues;
const
  Names: array[0..4] of String = ('BT.601 限定', 'JPEG', 'BT.709 限定', 'BT.709 全', 'BT.2020 全');
  // 参照版の SDL（SDL 3.4.2 も同じ）で 4x2 の IYUV を描いた値。BT.601 限定と BT.709 限定の (3, 0) の青は
  // 表の外へ出る値で、幅 4 では SDL のスカラー版が回り込んで 00 になる（D-62）。ここは SSE2 版の値（FF）
  Expect: array[0..4, 0..7] of LongWord = (
    ($FFB20000, $FFFE0000, $FF2AB2FF, $FF94FFFF, $FFFF3736, $FFE60000, $FF6BF2FF, $FF002BA1),
    ($FFAD0000, $FFEE0D0D, $FF31A9FF, $FF8BFFFF, $FFFF3C3C, $FFD90000, $FF68E0FF, $FF00369D),
    ($FFC90000, $FFFF1800, $FF1CABFF, $FF86FFFF, $FFFF5033, $FFFC0000, $FF5DECFF, $FF0024A8),
    ($FFC00000, $FFFF230A, $FF25A3FF, $FF7FFDFF, $FFFF5239, $FFEC0E00, $FF5CDAFF, $FF0030A3),
    ($FFB40000, $FFF51609, $FF2DABFF, $FF87FFFF, $FFFF4538, $FFE00100, $FF64E2FF, $FF0038A6));
var
  Spaces: array[0..4] of TPMLColorspace;
  S: TPMLSurface;
  Img: TYUVImage;
  Buf: TBytes;
  Direct: array[0..7] of LongWord;
  I, J, Pitch: Integer;
  Ok: Boolean;
begin
  WriteLn('3.2 変換の値（5 つの色空間）');
  Spaces[0] := PML_COLORSPACE_BT601_LIMITED;
  Spaces[1] := PML_COLORSPACE_JPEG;
  Spaces[2] := PML_COLORSPACE_BT709_LIMITED;
  Spaces[3] := PML_COLORSPACE_BT709_FULL;
  Spaces[4] := PML_COLORSPACE_BT2020_FULL;
  Img := FixedImage;
  for I := 0 to 4 do
  begin
    S := DrawYUV(Img, PML_PIXELFORMAT_IYUV, Spaces[I]);
    try
      Check(RowsEqual(S, Expect[I]), Names[I] + ' は SDL と同じ値（レンダラで描く）');
    finally
      S.Free;
    end;
    Pitch := 0;
    Buf := PackYUV(Img, PML_PIXELFORMAT_IYUV, Pitch);
    FillChar(Direct[0], SizeOf(Direct), 0);
    PMLConvertYUVToARGB8888(4, 2, PML_PIXELFORMAT_IYUV, Spaces[I], @Buf[0], Pitch, @Direct[0], 16);
    Ok := True;
    for J := 0 to 7 do
      if Direct[J] <> Expect[I, J] then
        Ok := False;
    Check(Ok, Names[I] + ' は PMLConvertYUVToARGB8888 でも同じ値');
  end;

  // 表の外へ出る値（D-62）。SDL のスカラー版は回り込んで、明るすぎる赤が 0、暗すぎる青が 255 になる。
  S := DrawYUV(FlatImage(2, 2, 235, 128, 240), PML_PIXELFORMAT_IYUV, PML_COLORSPACE_BT709_LIMITED);
  try
    Check(RowsEqual(S, [$FFFFC5FF, $FFFFC5FF, $FFFFC5FF, $FFFFC5FF]),
      'Y=235・Cr=240（BT.709 限定）の赤は 255 に飽和する（SDL のスカラー版は 0。D-62）');
  finally
    S.Free;
  end;
  S := DrawYUV(FlatImage(2, 2, 16, 16, 128), PML_PIXELFORMAT_IYUV, PML_COLORSPACE_BT601_LIMITED);
  try
    Check(RowsEqual(S, [$FF002B00, $FF002B00, $FF002B00, $FF002B00]),
      'Y=16・Cb=16（BT.601 限定）の青は 0 に飽和する（SDL のスカラー版は 255。D-62）');
  finally
    S.Free;
  end;
end;

procedure TestYUVFormats;
var
  Big, Small: TYUVImage;
  Ref, S: TPMLSurface;
  I, X, Y, Bad: Integer;
begin
  WriteLn('3.3 7 形式が同じ絵になる（偶数・奇数の大きさ、行の幅に余りがあるとき）');
  Big := MakeYUV(8, 6, 7);
  // 7x5 は 8x6 の左上を切り出したもの（U と V は同じ 4x3）
  Small.W := 7;
  Small.H := 5;
  Small.CW := 4;
  Small.CH := 3;
  SetLength(Small.Y, 35);
  for Y := 0 to 4 do
    Move(Big.Y[Y * 8], Small.Y[Y * 7], 7);
  Small.U := Copy(Big.U);
  Small.V := Copy(Big.V);
  Ref := DrawYUV(Big, PML_PIXELFORMAT_IYUV, PML_COLORSPACE_BT709_LIMITED);
  try
    for I := 0 to High(YUVFormats) do
    begin
      S := DrawYUV(Big, YUVFormats[I], PML_COLORSPACE_BT709_LIMITED);
      try
        Check(DiffCount(S, Ref) = 0, PMLPixelFormatName(YUVFormats[I]) + ' 8x6 は IYUV と同じ絵');
      finally
        S.Free;
      end;
      S := DrawYUV(Small, YUVFormats[I], PML_COLORSPACE_BT709_LIMITED);
      try
        Bad := 0;
        for Y := 0 to 4 do
          for X := 0 to 6 do
            if S.ReadRaw(X, Y) <> Ref.ReadRaw(X, Y) then
              Inc(Bad);
        Check(Bad = 0, PMLPixelFormatName(YUVFormats[I]) + ' 7x5（奇数）は 8x6 の左上と同じ絵（端の列と行）');
      finally
        S.Free;
      end;
      S := DrawYUV(Big, YUVFormats[I], PML_COLORSPACE_BT709_LIMITED, 20);
      try
        Check(DiffCount(S, Ref) = 0, PMLPixelFormatName(YUVFormats[I]) + ' 行の幅に余り（20 バイト）があっても同じ絵');
      finally
        S.Free;
      end;
    end;
  finally
    Ref.Free;
  end;
end;

{ 部分の更新と、平面ごとの更新。A で全体を入れてから B の一部で書き換えた絵は、A と B を
  合わせた論理の絵（C）を全体で入れた絵と同じ。 }
procedure TestYUVUpdates;
var
  A, B, C, D, Sub: TYUVImage;
  Out, Ref: TPMLSurface;
  R: TPMLRenderer;
  T: TPMLTexture;
  Buf: TBytes;
  F, X, Y, Pitch: Integer;
  Fmt: TPMLPixelFormat;
  Raised: Boolean;
  UV: TBytes;
begin
  WriteLn('3.4 部分の更新・平面ごとの更新・誤り');
  A := MakeYUV(8, 6, 11);
  B := MakeYUV(8, 6, 12);
  D := MakeYUV(8, 6, 13);
  // 書き換える矩形 (2, 2, 4, 2)。Y はその画素、U と V は区画 (1, 1)・(2, 1)
  C := A;
  C.Y := Copy(A.Y);
  C.U := Copy(A.U);
  C.V := Copy(A.V);
  for Y := 2 to 3 do
    for X := 2 to 5 do
      C.Y[Y * 8 + X] := B.Y[Y * 8 + X];
  for X := 1 to 2 do
  begin
    C.U[1 * 4 + X] := B.U[1 * 4 + X];
    C.V[1 * 4 + X] := B.V[1 * 4 + X];
  end;
  // B の矩形の部分だけの論理の絵（4x2、区画 2x1）
  Sub.W := 4;
  Sub.H := 2;
  Sub.CW := 2;
  Sub.CH := 1;
  SetLength(Sub.Y, 8);
  for Y := 0 to 1 do
    Move(B.Y[(Y + 2) * 8 + 2], Sub.Y[Y * 4], 4);
  SetLength(Sub.U, 2);
  SetLength(Sub.V, 2);
  for X := 0 to 1 do
  begin
    Sub.U[X] := B.U[4 + 1 + X];
    Sub.V[X] := B.V[4 + 1 + X];
  end;
  for F := 0 to High(YUVFormats) do
  begin
    Fmt := YUVFormats[F];
    Ref := DrawYUV(C, Fmt, PML_COLORSPACE_YUV_DEFAULT);
    Out := TPMLSurface.Create(8, 6, PML_PIXELFORMAT_ARGB8888);
    R := TPMLRenderer.CreateSoftware(Out);
    try
      T := R.CreateTexture(Fmt, TPMLTextureAccess.Streaming, 8, 6);
      Pitch := 0;
      Buf := PackYUV(A, Fmt, Pitch);
      T.Update(TPMLRect.Make(0, 0, 0, 0), @Buf[0], Pitch);
      Pitch := 0;
      Buf := PackYUV(Sub, Fmt, Pitch);
      T.Update(TPMLRect.Make(2, 2, 4, 2), @Buf[0], Pitch);
      R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 0, 0));
      R.Present;
      Check(DiffCount(Out, Ref) = 0, PMLPixelFormatName(Fmt) + ' の部分の更新 (2, 2, 4, 2)');

      // 次の確かめの前に、別の絵（D）で全体を入れ替えておく。前の確かめの絵が残っていると、
      // 更新されない平面があっても気づけない
      Pitch := 0;
      Buf := PackYUV(D, Fmt, Pitch);
      T.Update(TPMLRect.Make(0, 0, 0, 0), @Buf[0], Pitch);

      if (Fmt = PML_PIXELFORMAT_IYUV) or (Fmt = PML_PIXELFORMAT_YV12) then
      begin
        T.UpdateYUV(TPMLRect.Make(0, 0, 0, 0), @A.Y[0], 8, @A.U[0], 4, @A.V[0], 4);
        T.UpdateYUV(TPMLRect.Make(2, 2, 4, 2), @Sub.Y[0], 4, @Sub.U[0], 2, @Sub.V[0], 2);
        R.Clear;
        R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 0, 0));
        R.Present;
        Check(DiffCount(Out, Ref) = 0, PMLPixelFormatName(Fmt) + ' の UpdateYUV（全体と部分）');
      end;
      if (Fmt = PML_PIXELFORMAT_NV12) or (Fmt = PML_PIXELFORMAT_NV21) then
      begin
        SetLength(UV, 4 * 3 * 2);
        for X := 0 to 11 do
          if Fmt = PML_PIXELFORMAT_NV12 then
          begin
            UV[X * 2] := A.U[X];
            UV[X * 2 + 1] := A.V[X];
          end
          else
          begin
            UV[X * 2] := A.V[X];
            UV[X * 2 + 1] := A.U[X];
          end;
        T.UpdateNV(TPMLRect.Make(0, 0, 0, 0), @A.Y[0], 8, @UV[0], 8);
        for X := 0 to 1 do
          if Fmt = PML_PIXELFORMAT_NV12 then
          begin
            UV[X * 2] := Sub.U[X];
            UV[X * 2 + 1] := Sub.V[X];
          end
          else
          begin
            UV[X * 2] := Sub.V[X];
            UV[X * 2 + 1] := Sub.U[X];
          end;
        T.UpdateNV(TPMLRect.Make(2, 2, 4, 2), @Sub.Y[0], 4, @UV[0], 4);
        R.Clear;
        R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 0, 0));
        R.Present;
        Check(DiffCount(Out, Ref) = 0, PMLPixelFormatName(Fmt) + ' の UpdateNV（全体と部分）');
      end;
    finally
      R.Free;
      Out.Free;
      Ref.Free;
    end;
  end;

  // 誤り
  Out := TPMLSurface.Create(8, 6, PML_PIXELFORMAT_ARGB8888);
  R := TPMLRenderer.CreateSoftware(Out);
  try
    Raised := False;
    try
      R.CreateTexture(PML_PIXELFORMAT_NV12, TPMLTextureAccess.Target, 8, 6);
    except
      on E: Exception do Raised := E is EPMLArgument;
    end;
    Check(Raised, 'YUV は描画先にできない');
    Raised := False;
    try
      R.CreateTexture(PML_PIXELFORMAT_P010, TPMLTextureAccess.Static, 8, 6);
    except
      on E: Exception do Raised := E is EPMLArgument;
    end;
    Check(Raised, 'P010 は作れない（SDL のソフトウェアのレンダラも作れない）');
    Raised := False;
    try
      R.CreateTexture(PML_PIXELFORMAT_IYUV, TPMLTextureAccess.Static, 8, 6, PML_COLORSPACE_SRGB);
    except
      on E: Exception do Raised := E is EPMLArgument;
    end;
    Check(Raised, 'YUV の色空間に SRGB は使えない');
    T := R.CreateTexture(PML_PIXELFORMAT_NV12, TPMLTextureAccess.Static, 8, 6);
    Check(T.Colorspace = PML_COLORSPACE_BT601_LIMITED, '色空間を決めなければ BT.601 の限定範囲');
    Raised := False;
    try
      T.UpdateYUV(TPMLRect.Make(0, 0, 0, 0), @A.Y[0], 8, @A.U[0], 4, @A.V[0], 4);
    except
      on E: Exception do Raised := E is EPMLArgument;
    end;
    Check(Raised, 'NV12 に UpdateYUV は使えない');
    T := R.CreateTexture(PML_PIXELFORMAT_IYUV, TPMLTextureAccess.Static, 8, 6);
    Raised := False;
    try
      T.UpdateNV(TPMLRect.Make(0, 0, 0, 0), @A.Y[0], 8, @A.U[0], 8);
    except
      on E: Exception do Raised := E is EPMLArgument;
    end;
    Check(Raised, 'IYUV に UpdateNV は使えない');
    T := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Static, 8, 6);
    Check(T.Colorspace = PML_COLORSPACE_SRGB, 'ARGB8888 の既定の色空間は SRGB');
    // 平面の外は切る（SDL と同じ）。全部外なら何もしない
    T := R.CreateTexture(PML_PIXELFORMAT_IYUV, TPMLTextureAccess.Static, 8, 6);
    Raised := False;
    try
      T.UpdateYUV(TPMLRect.Make(20, 20, 4, 4), @A.Y[0], 8, @A.U[0], 4, @A.V[0], 4);
    except
      on E: Exception do Raised := True;
    end;
    Check(not Raised, 'テクスチャの外だけの UpdateYUV は何もしない');
  finally
    R.Free;
    Out.Free;
  end;
end;

type
  TPlainProc = procedure;

procedure GuardPlain(AProc: TPlainProc);
begin
  try
    AProc;
  except
    on E: Exception do
      Check(False, '思わぬ例外: ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure TestYUV;
begin
  GuardPlain(@TestYUVBasics);
  GuardPlain(@TestYUVValues);
  GuardPlain(@TestYUVFormats);
  GuardPlain(@TestYUVUpdates);
end;

begin
  WriteLn('test_texture_kinds — テクスチャの種類');
  WriteLn;
  TestPixelArt;
  WriteLn;
  TestPalette;
  WriteLn;
  TestYUV;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: テクスチャの種類が SDL と同じ絵になる ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
