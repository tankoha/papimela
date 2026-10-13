{
  test_texture_kinds — テクスチャの種類（拡大の方式 PIXELART、パレット、YUV）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    1. 拡大の方式 PixelArt（SDL_SCALEMODE_PIXELART）。SDL のソフトウェアのレンダラと
       サーフェスの拡大は PIXELART を NEAREST と同じに扱う。papimela も同じ絵になる
    2. パレット（INDEX8。SDL_SetTexturePalette）。パレットの版、作れないもの、描く色、
       積んだ後の色の変更、共有、部分更新、サーフェスから（写しとカラーキー）。
       ドライバが INDEX8 を直接持つときと、レンダラの肩代わりの層を通るときの 2 通り
    （YUV の節は §3 の 3c で足す）

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

begin
  WriteLn('test_texture_kinds — テクスチャの種類');
  WriteLn;
  TestPixelArt;
  WriteLn;
  TestPalette;

  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: テクスチャの種類が SDL と同じ絵になる ===')
  else
  begin
    WriteLn('=== ', Failures, ' 件失敗 ===');
    Halt(1);
  end;
end.
