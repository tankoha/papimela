{
  PaPiMeLa.Surface.Blit — サーフェス間の転送と塗りつぶし

  Origin : ported from SDL (src/video/SDL_blit.c, SDL_blit_N.c, SDL_blit_A.c,
           SDL_blit_copy.c, SDL_blit_slow.c, SDL_fillrect.c, SDL_stretch.c)
           Scope: クリップの取り方、カラーキーと合成の適用順、拡大縮小の
           標本点の決め方、合成モードごとの式。SIMD は落とし、スカラー版のみ。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.4、§11 #29

  WHAT:
    矩形から矩形へ画素を写す。形式が違えば変換し、カラーキーと合成モードと
    色の変調を適用する。等倍と拡大縮小の両方。

  WHY:
    サーフェスの Convert は 1 画素ずつ色に戻して書き直す素直な実装で、
    正しいが遅い。ここは同じ結果をもっと速く出すための場所である。

  RESOLVED:
    - 形式が同じで合成もカラーキーも無いときは、行ごとに Move する
      （SDL_blit_copy.c と同じ考え）
    - それ以外は 1 画素ずつ。合成の式は TPMLBlendMode の定義どおり
    - クリップは転送元と転送先の両方で取る。先に転送先で切ってから、
      切られた分だけ転送元の開始位置をずらす。逆順にすると端がずれる

  NOT RESOLVED:
    - RLE 圧縮（SDL_RLEaccel.c）は未実装。TPMLSurface 側にも入っていない
    - 回転（SDL_rotate.c）は未実装。レンダラの RenderTextureRotated が
      要るようになってから入れる
    - 拡大縮小は最近傍のみ。線形補間は未実装
    - SIMD は移植しない（設計 §9.5）。スカラー版だけを置く

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Surface.Blit;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface;

{ 等倍の転送。

  ASrcRect が空なら転送元の全体、ADstRect が空なら転送先の (0,0) へ置く。
  ADstRect の幅と高さは使わない（等倍なので転送元の大きさで決まる）。
  戻り値 False = クリップの結果、書くところが無かった。 }
function PMLBlit(ASrc: TPMLSurface; const ASrcRect: TPMLRect;
  ADst: TPMLSurface; const ADstRect: TPMLRect): Boolean;

{ 拡大縮小つきの転送。ADstRect の幅と高さへ引き伸ばす。 }
function PMLBlitScaled(ASrc: TPMLSurface; const ASrcRect: TPMLRect;
  ADst: TPMLSurface; const ADstRect: TPMLRect;
  AMode: TPMLScaleMode = TPMLScaleMode.Nearest): Boolean;

{ 矩形を 1 色で塗る。転送先のクリップ矩形で切る。 }
function PMLFillRect(ADst: TPMLSurface; const ARect: TPMLRect;
  const AColor: TPMLColor): Boolean;

{ 2 つの色を合成モードに従って合成する。

  転送の内側で使うが、検査から直接呼べるよう公開している。
  ARGB は 0..255。計算は 8 ビットのまま行い、丸めは四捨五入に寄せる。 }
function PMLBlendColor(const ASrc, ADst: TPMLColor;
  AMode: TPMLBlendMode): TPMLColor;

implementation

{ ---- 合成 ---- }

// a * b / 255 を四捨五入で。SDL の MULT_DIV_255 と同じ狙い。
function Mul255(A, B: Integer): Integer; inline;
begin
  Result := A * B + 128;
  Result := (Result + (Result shr 8)) shr 8;
end;

function ClampByte(AValue: Integer): Byte; inline;
begin
  if AValue <= 0 then
    Result := 0
  else if AValue >= 255 then
    Result := 255
  else
    Result := Byte(AValue);
end;

function PMLBlendColor(const ASrc, ADst: TPMLColor;
  AMode: TPMLBlendMode): TPMLColor;
var
  InvA: Integer;
begin
  case AMode of
    TPMLBlendMode.None:
      Result := ASrc;

    TPMLBlendMode.Blend:
      begin
        InvA := 255 - ASrc.A;
        Result.R := ClampByte(Mul255(ASrc.R, ASrc.A) + Mul255(ADst.R, InvA));
        Result.G := ClampByte(Mul255(ASrc.G, ASrc.A) + Mul255(ADst.G, InvA));
        Result.B := ClampByte(Mul255(ASrc.B, ASrc.A) + Mul255(ADst.B, InvA));
        Result.A := ClampByte(ASrc.A + Mul255(ADst.A, InvA));
      end;

    TPMLBlendMode.Add:
      begin
        Result.R := ClampByte(Mul255(ASrc.R, ASrc.A) + ADst.R);
        Result.G := ClampByte(Mul255(ASrc.G, ASrc.A) + ADst.G);
        Result.B := ClampByte(Mul255(ASrc.B, ASrc.A) + ADst.B);
        Result.A := ADst.A;
      end;

    TPMLBlendMode.Modulate:
      begin
        Result.R := ClampByte(Mul255(ASrc.R, ADst.R));
        Result.G := ClampByte(Mul255(ASrc.G, ADst.G));
        Result.B := ClampByte(Mul255(ASrc.B, ADst.B));
        Result.A := ADst.A;
      end;

    TPMLBlendMode.Multiply:
      begin
        InvA := 255 - ASrc.A;
        Result.R := ClampByte(Mul255(ASrc.R, ADst.R) + Mul255(ADst.R, InvA));
        Result.G := ClampByte(Mul255(ASrc.G, ADst.G) + Mul255(ADst.G, InvA));
        Result.B := ClampByte(Mul255(ASrc.B, ADst.B) + Mul255(ADst.B, InvA));
        Result.A := ADst.A;
      end;
  else
    Result := ASrc;
  end;
end;

{ 転送元の色に変調（ColorMod / AlphaMod）をかける。 }
function ApplyMod(const AColor: TPMLColor; ASrc: TPMLSurface): TPMLColor; inline;
begin
  Result.R := Byte(Mul255(AColor.R, ASrc.ColorMod.R));
  Result.G := Byte(Mul255(AColor.G, ASrc.ColorMod.G));
  Result.B := Byte(Mul255(AColor.B, ASrc.ColorMod.B));
  Result.A := Byte(Mul255(AColor.A, ASrc.AlphaMod));
end;

// 変調が恒等なら 1 画素ずつの処理を省ける。
function ModIsIdentity(ASrc: TPMLSurface): Boolean; inline;
begin
  Result := (ASrc.ColorMod.R = 255) and (ASrc.ColorMod.G = 255)
        and (ASrc.ColorMod.B = 255) and (ASrc.AlphaMod = 255);
end;

{ ---- クリップ ---- }

{ 転送元と転送先の矩形を、両方のクリップに収まるよう切り詰める。

  WHAT:
    ASX / ASY / ADX / ADY / AW / AH を、実際に転送する範囲へ書き換える。

  WHY:
    **先に転送先で切ってから、切られた分だけ転送元をずらす**必要がある。
    逆順にすると、転送先の左端で切られたときに転送元の開始位置が動かず、
    絵が横にずれる。

  戻り値 False = 何も転送しない。 }
function ClipPair(ASrc: TPMLSurface; var ASX, ASY: Integer;
  ADst: TPMLSurface; var ADX, ADY: Integer; var AW, AH: Integer): Boolean;
var
  Cut: Integer;
  DClipX2, DClipY2: Integer;
begin
  Result := False;

  // 転送元の範囲外を落とす。
  if ASX < 0 then
  begin
    Inc(ADX, -ASX);
    Dec(AW, -ASX);
    ASX := 0;
  end;
  if ASY < 0 then
  begin
    Inc(ADY, -ASY);
    Dec(AH, -ASY);
    ASY := 0;
  end;
  if ASX + AW > ASrc.Width then
    AW := ASrc.Width - ASX;
  if ASY + AH > ASrc.Height then
    AH := ASrc.Height - ASY;

  // 転送先のクリップ矩形で切る。切った分だけ転送元をずらす。
  DClipX2 := ADst.ClipRect.X + ADst.ClipRect.W;
  DClipY2 := ADst.ClipRect.Y + ADst.ClipRect.H;

  if ADX < ADst.ClipRect.X then
  begin
    Cut := ADst.ClipRect.X - ADX;
    Inc(ASX, Cut);
    Inc(ADX, Cut);
    Dec(AW, Cut);
  end;
  if ADY < ADst.ClipRect.Y then
  begin
    Cut := ADst.ClipRect.Y - ADY;
    Inc(ASY, Cut);
    Inc(ADY, Cut);
    Dec(AH, Cut);
  end;
  if ADX + AW > DClipX2 then
    AW := DClipX2 - ADX;
  if ADY + AH > DClipY2 then
    AH := DClipY2 - ADY;

  Result := (AW > 0) and (AH > 0);
end;

{ ---- 等倍の転送 ---- }

{ 形式が同じで、合成もカラーキーも変調も無い場合の速い経路。

  PORT-NOTE: SDL_blit_copy.c と同じ考え。行の先頭から幅ぶんをまとめて写す。
  ピッチが違っても行ごとに写すので問題ない。 }
procedure BlitRaw(ASrc: TPMLSurface; ASX, ASY: Integer;
  ADst: TPMLSurface; ADX, ADY, AW, AH: Integer);
var
  Y, Bpp: Integer;
  SP, DP: PByte;
begin
  Bpp := ASrc.Details.BytesPerPixel;
  for Y := 0 to AH - 1 do
  begin
    SP := PByte(ASrc.Pixels) + PtrUInt(ASY + Y) * PtrUInt(ASrc.Pitch)
        + PtrUInt(ASX) * PtrUInt(Bpp);
    DP := PByte(ADst.Pixels) + PtrUInt(ADY + Y) * PtrUInt(ADst.Pitch)
        + PtrUInt(ADX) * PtrUInt(Bpp);
    Move(SP^, DP^, PtrUInt(AW) * PtrUInt(Bpp));
  end;
end;

{ 1 画素ずつ写す経路。変換・カラーキー・変調・合成をここで行う。

  PORT-NOTE: SDL_blit_slow.c 相当。SDL は形式の組み合わせごとに特化した
  関数を持つが、ここは 1 本にまとめてある。特化は必要になってから足す。 }
procedure BlitSlow(ASrc: TPMLSurface; ASX, ASY: Integer;
  ADst: TPMLSurface; ADX, ADY, AW, AH: Integer);
var
  X, Y: Integer;
  Raw : LongWord;
  C, D: TPMLColor;
  UseKey, UseMod: Boolean;
  Mode: TPMLBlendMode;
begin
  UseKey := ASrc.HasColorKey;
  UseMod := not ModIsIdentity(ASrc);
  Mode := ASrc.BlendMode;

  for Y := 0 to AH - 1 do
    for X := 0 to AW - 1 do
    begin
      Raw := ASrc.ReadRaw(ASX + X, ASY + Y);
      // カラーキーに一致する画素は書かない。合成より先に判定する。
      if UseKey and (Raw = ASrc.ColorKey) then
        Continue;
      C := PMLGetColor(Raw, ASrc.Details, ASrc.Palette);
      if UseMod then
        C := ApplyMod(C, ASrc);
      if Mode <> TPMLBlendMode.None then
      begin
        D := ADst.ReadPixel(ADX + X, ADY + Y);
        C := PMLBlendColor(C, D, Mode);
      end;
      ADst.WritePixel(ADX + X, ADY + Y, C);
    end;
end;

// 速い経路を使える条件。ひとつでも外れたら 1 画素ずつになる。
function CanCopyRaw(ASrc, ADst: TPMLSurface): Boolean; inline;
begin
  Result := (ASrc.Format = ADst.Format)
        and (ASrc.BlendMode = TPMLBlendMode.None)
        and (not ASrc.HasColorKey)
        and ModIsIdentity(ASrc)
        and (ASrc.Details.BytesPerPixel > 0);
end;

function PMLBlit(ASrc: TPMLSurface; const ASrcRect: TPMLRect;
  ADst: TPMLSurface; const ADstRect: TPMLRect): Boolean;
var
  SX, SY, DX, DY, W, H: Integer;
begin
  Result := False;
  if (ASrc = nil) or (ADst = nil) then
    Exit;

  if ASrcRect.IsEmpty then
  begin
    SX := 0;
    SY := 0;
    W := ASrc.Width;
    H := ASrc.Height;
  end
  else
  begin
    SX := ASrcRect.X;
    SY := ASrcRect.Y;
    W := ASrcRect.W;
    H := ASrcRect.H;
  end;
  DX := ADstRect.X;
  DY := ADstRect.Y;

  if not ClipPair(ASrc, SX, SY, ADst, DX, DY, W, H) then
    Exit;

  if CanCopyRaw(ASrc, ADst) then
    BlitRaw(ASrc, SX, SY, ADst, DX, DY, W, H)
  else
    BlitSlow(ASrc, SX, SY, ADst, DX, DY, W, H);
  Result := True;
end;

{ ---- 拡大縮小 ---- }

{ 最近傍で引き伸ばす。

  標本点は転送先の画素の**中心**から逆算する。左上の角から逆算すると、
  縮小したときに右端と下端の画素が使われなくなる。

  PORT-NOTE: SDL_stretch.c の最近傍経路と同じ考え。SDL は固定小数点で
  刻むが、ここは 1 画素ごとに割り算する。速度が要るようになったら刻みへ直す。 }
function PMLBlitScaled(ASrc: TPMLSurface; const ASrcRect: TPMLRect;
  ADst: TPMLSurface; const ADstRect: TPMLRect;
  AMode: TPMLScaleMode): Boolean;
var
  SX, SY, SW, SH: Integer;
  DX, DY, DW, DH: Integer;
  X, Y, TX, TY, SrcX, SrcY: Integer;
  X1, Y1, X2, Y2: Integer;
  Raw: LongWord;
  C, D: TPMLColor;
  UseKey, UseMod: Boolean;
  Mode: TPMLBlendMode;
begin
  Result := False;
  if (ASrc = nil) or (ADst = nil) then
    Exit;

  if ASrcRect.IsEmpty then
  begin
    SX := 0;
    SY := 0;
    SW := ASrc.Width;
    SH := ASrc.Height;
  end
  else
  begin
    SX := ASrcRect.X;
    SY := ASrcRect.Y;
    SW := ASrcRect.W;
    SH := ASrcRect.H;
  end;
  DX := ADstRect.X;
  DY := ADstRect.Y;
  DW := ADstRect.W;
  DH := ADstRect.H;
  if (SW <= 0) or (SH <= 0) or (DW <= 0) or (DH <= 0) then
    Exit;

  // 転送先のクリップ矩形と交差した範囲だけ回す。転送元の座標は毎回
  // 転送先の位置から逆算するので、ここでずらす必要はない。
  X1 := DX;
  Y1 := DY;
  X2 := DX + DW;
  Y2 := DY + DH;
  if X1 < ADst.ClipRect.X then
    X1 := ADst.ClipRect.X;
  if Y1 < ADst.ClipRect.Y then
    Y1 := ADst.ClipRect.Y;
  if X2 > ADst.ClipRect.X + ADst.ClipRect.W then
    X2 := ADst.ClipRect.X + ADst.ClipRect.W;
  if Y2 > ADst.ClipRect.Y + ADst.ClipRect.H then
    Y2 := ADst.ClipRect.Y + ADst.ClipRect.H;
  if (X1 >= X2) or (Y1 >= Y2) then
    Exit;

  UseKey := ASrc.HasColorKey;
  UseMod := not ModIsIdentity(ASrc);
  Mode := ASrc.BlendMode;

  for Y := Y1 to Y2 - 1 do
  begin
    TY := Y - DY;
    // 画素の中心（TY + 0.5）を転送元へ写す。整数で書くと (2*TY+1)*SH / (2*DH)。
    SrcY := SY + ((2 * TY + 1) * SH) div (2 * DH);
    if SrcY >= SY + SH then
      SrcY := SY + SH - 1;
    for X := X1 to X2 - 1 do
    begin
      TX := X - DX;
      SrcX := SX + ((2 * TX + 1) * SW) div (2 * DW);
      if SrcX >= SX + SW then
        SrcX := SX + SW - 1;

      Raw := ASrc.ReadRaw(SrcX, SrcY);
      if UseKey and (Raw = ASrc.ColorKey) then
        Continue;
      C := PMLGetColor(Raw, ASrc.Details, ASrc.Palette);
      if UseMod then
        C := ApplyMod(C, ASrc);
      if Mode <> TPMLBlendMode.None then
      begin
        D := ADst.ReadPixel(X, Y);
        C := PMLBlendColor(C, D, Mode);
      end;
      ADst.WritePixel(X, Y, C);
    end;
  end;
  Result := True;
end;

{ ---- 塗りつぶし ---- }

{ 矩形を 1 色で塗る。

  PORT-NOTE: SDL_fillrect.c 相当。画素の大きさごとに書き方を分け、
  4 バイトの場合は行の先頭で 1 行ぶん作ってから次の行へ Move する。 }
function PMLFillRect(ADst: TPMLSurface; const ARect: TPMLRect;
  const AColor: TPMLColor): Boolean;
var
  X1, Y1, X2, Y2, X, Y, W, Bpp: Integer;
  Raw: LongWord;
  P, FirstRow: PByte;
begin
  Result := False;
  if ADst = nil then
    Exit;

  X1 := ARect.X;
  Y1 := ARect.Y;
  X2 := ARect.X + ARect.W;
  Y2 := ARect.Y + ARect.H;
  if X1 < ADst.ClipRect.X then
    X1 := ADst.ClipRect.X;
  if Y1 < ADst.ClipRect.Y then
    Y1 := ADst.ClipRect.Y;
  if X2 > ADst.ClipRect.X + ADst.ClipRect.W then
    X2 := ADst.ClipRect.X + ADst.ClipRect.W;
  if Y2 > ADst.ClipRect.Y + ADst.ClipRect.H then
    Y2 := ADst.ClipRect.Y + ADst.ClipRect.H;
  if (X1 >= X2) or (Y1 >= Y2) then
    Exit;

  Raw := ADst.MapColor(AColor);
  Bpp := ADst.Details.BytesPerPixel;
  W := X2 - X1;

  // 最初の 1 行だけ画素単位で作り、残りの行はその行を写す。
  for X := X1 to X2 - 1 do
    ADst.WriteRaw(X, Y1, Raw);
  FirstRow := PByte(ADst.Pixels) + PtrUInt(Y1) * PtrUInt(ADst.Pitch)
            + PtrUInt(X1) * PtrUInt(Bpp);
  for Y := Y1 + 1 to Y2 - 1 do
  begin
    P := PByte(ADst.Pixels) + PtrUInt(Y) * PtrUInt(ADst.Pitch)
       + PtrUInt(X1) * PtrUInt(Bpp);
    Move(FirstRow^, P^, PtrUInt(W) * PtrUInt(Bpp));
  end;
  Result := True;
end;

end.
