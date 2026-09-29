{
  test_blit — ブリッタ群

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    等倍転送・拡大縮小・塗りつぶしを、テスト側に別に書いた素直な実装と
    突き合わせる。

  WHY:
    ブリッタは「速いが読みにくい経路」と「遅いが明らかに正しい経路」が
    同じ結果を出すべき場所である。papimela の実装は形式が同じなら行ごとに
    Move し、そうでなければ 1 画素ずつ回すという分岐を持つので、
    **分岐のどちら側でも同じ絵になること**を機械的に確かめる必要がある。

    合成の式は浮動小数点で別に計算して突き合わせる。実装は 8 ビット整数の
    近似で計算しているので、丸めの差として ±1 まで許す。式そのものを
    取り違えていれば差はもっと大きく出る。

    クリップは**転送先で切った分だけ転送元をずらす**のが要点で、逆順にすると
    絵が横にずれる。負の座標から転送して確かめる。

  実行前提: 無し。
}
program test_blit;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.Blit;

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

procedure Note(const AText: String);
begin
  WriteLn('  [観測] ', AText);
end;

function SameColor(const A, B: TPMLColor): Boolean;
begin
  Result := (A.R = B.R) and (A.G = B.G) and (A.B = B.B) and (A.A = B.A);
end;

// 位置ごとに違う色。行や列が 1 つずれれば必ず気づける。
procedure Paint(S: TPMLSurface; ASeed: Integer);
var
  X, Y: Integer;
begin
  for Y := 0 to S.Height - 1 do
    for X := 0 to S.Width - 1 do
      S.WritePixel(X, Y, TPMLColor.Make(
        Byte(X * 11 + ASeed), Byte(Y * 13 + ASeed),
        Byte(X * 7 + Y * 5 + ASeed), Byte(200)));
end;

function SamePixels(A, B: TPMLSurface): Boolean;
var
  X, Y: Integer;
begin
  Result := False;
  if (A.Width <> B.Width) or (A.Height <> B.Height) then
    Exit;
  for Y := 0 to A.Height - 1 do
    for X := 0 to A.Width - 1 do
      if not SameColor(A.ReadPixel(X, Y), B.ReadPixel(X, Y)) then
        Exit;
  Result := True;
end;

{ ---- テスト側の参照実装 ----

  papimela の実装とは独立に、素直に書いたもの。速度は考えない。
  クリップの規則もここで別に書き下ろす。 }

procedure RefBlit(ASrc: TPMLSurface; ASrcRect: TPMLRect;
  ADst: TPMLSurface; ADstRect: TPMLRect);
var
  SX, SY, DX, DY, W, H, X, Y, Cut: Integer;
begin
  if ASrcRect.IsEmpty then
  begin
    SX := 0; SY := 0; W := ASrc.Width; H := ASrc.Height;
  end
  else
  begin
    SX := ASrcRect.X; SY := ASrcRect.Y; W := ASrcRect.W; H := ASrcRect.H;
  end;
  DX := ADstRect.X;
  DY := ADstRect.Y;

  // 転送元の外を落とす
  if SX < 0 then begin Inc(DX, -SX); Inc(W, SX); SX := 0; end;
  if SY < 0 then begin Inc(DY, -SY); Inc(H, SY); SY := 0; end;
  W := Min(W, ASrc.Width - SX);
  H := Min(H, ASrc.Height - SY);

  // 転送先のクリップで切り、切った分だけ転送元をずらす
  if DX < ADst.ClipRect.X then
  begin
    Cut := ADst.ClipRect.X - DX;
    Inc(SX, Cut); Inc(DX, Cut); Dec(W, Cut);
  end;
  if DY < ADst.ClipRect.Y then
  begin
    Cut := ADst.ClipRect.Y - DY;
    Inc(SY, Cut); Inc(DY, Cut); Dec(H, Cut);
  end;
  W := Min(W, ADst.ClipRect.X + ADst.ClipRect.W - DX);
  H := Min(H, ADst.ClipRect.Y + ADst.ClipRect.H - DY);
  if (W <= 0) or (H <= 0) then
    Exit;

  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
      ADst.WritePixel(DX + X, DY + Y, ASrc.ReadPixel(SX + X, SY + Y));
end;

// 合成を浮動小数点で計算する。実装の 8 ビット整数とは別の道筋。
function RefBlend(const ASrc, ADst: TPMLColor; AMode: TPMLBlendMode): TPMLColor;
var
  SR, SG, SB, SA, DR, DG, DB, DA, IA: Double;

  function B(AValue: Double): Byte;
  begin
    Result := Byte(Round(Max(0, Min(255, AValue * 255))));
  end;

begin
  SR := ASrc.R / 255; SG := ASrc.G / 255; SB := ASrc.B / 255; SA := ASrc.A / 255;
  DR := ADst.R / 255; DG := ADst.G / 255; DB := ADst.B / 255; DA := ADst.A / 255;
  IA := 1 - SA;
  case AMode of
    TPMLBlendMode.None:
      Result := ASrc;
    TPMLBlendMode.Blend:
      begin
        Result.R := B(SR * SA + DR * IA);
        Result.G := B(SG * SA + DG * IA);
        Result.B := B(SB * SA + DB * IA);
        Result.A := B(SA + DA * IA);
      end;
    TPMLBlendMode.Add:
      begin
        Result.R := B(SR * SA + DR);
        Result.G := B(SG * SA + DG);
        Result.B := B(SB * SA + DB);
        Result.A := ADst.A;
      end;
    TPMLBlendMode.Modulate:
      begin
        Result.R := B(SR * DR);
        Result.G := B(SG * DG);
        Result.B := B(SB * DB);
        Result.A := ADst.A;
      end;
    TPMLBlendMode.Multiply:
      begin
        Result.R := B(SR * DR + DR * IA);
        Result.G := B(SG * DG + DG * IA);
        Result.B := B(SB * DB + DB * IA);
        Result.A := ADst.A;
      end;
  end;
end;

function NearColor(const A, B: TPMLColor; ATolerance: Integer): Boolean;
begin
  Result := (Abs(Integer(A.R) - Integer(B.R)) <= ATolerance)
        and (Abs(Integer(A.G) - Integer(B.G)) <= ATolerance)
        and (Abs(Integer(A.B) - Integer(B.B)) <= ATolerance)
        and (Abs(Integer(A.A) - Integer(B.A)) <= ATolerance);
end;

var
  Src, Dst, Ref, Tmp: TPMLSurface;
  Mode     : TPMLBlendMode;
  CS, CD, CA, CB: TPMLColor;
  X, Y, Bad, Worst, Diff: Integer;
  OK       : Boolean;
begin
  WriteLn('test_blit — ブリッタ群');
  WriteLn;

  WriteLn('1. 等倍転送（同じ形式。行ごとに Move する速い経路）');
  Src := TPMLSurface.Create(16, 12, PML_PIXELFORMAT_ARGB8888);
  Dst := TPMLSurface.Create(20, 16, PML_PIXELFORMAT_ARGB8888);
  Ref := TPMLSurface.Create(20, 16, PML_PIXELFORMAT_ARGB8888);
  try
    Paint(Src, 3);
    Dst.Fill(TPMLColor.Make(9, 9, 9, 255));
    Ref.Fill(TPMLColor.Make(9, 9, 9, 255));

    Check(PMLBlit(Src, TPMLRect.Make(0, 0, 0, 0), Dst, TPMLRect.Make(2, 3, 0, 0)),
      '転送できた');
    RefBlit(Src, TPMLRect.Make(0, 0, 0, 0), Ref, TPMLRect.Make(2, 3, 0, 0));
    Check(SamePixels(Dst, Ref), '参照実装と一致する');
    // 触っていないところが変わっていないことも見る。
    Check(SameColor(Dst.ReadPixel(0, 0), TPMLColor.Make(9, 9, 9, 255)),
      '転送先の外は変わらない');
  finally
    Src.Free; Dst.Free; Ref.Free;
  end;

  WriteLn;
  WriteLn('2. 形式が違う転送（1 画素ずつの経路）');
  Src := TPMLSurface.Create(16, 12, PML_PIXELFORMAT_ARGB8888);
  Dst := TPMLSurface.Create(20, 16, PML_PIXELFORMAT_ABGR8888);
  Ref := TPMLSurface.Create(20, 16, PML_PIXELFORMAT_ABGR8888);
  try
    Paint(Src, 5);
    Dst.Fill(TPMLColor.Make(1, 2, 3, 255));
    Ref.Fill(TPMLColor.Make(1, 2, 3, 255));
    PMLBlit(Src, TPMLRect.Make(0, 0, 0, 0), Dst, TPMLRect.Make(1, 1, 0, 0));
    RefBlit(Src, TPMLRect.Make(0, 0, 0, 0), Ref, TPMLRect.Make(1, 1, 0, 0));
    Check(SamePixels(Dst, Ref), '並びが違っても参照実装と一致する');
  finally
    Src.Free; Dst.Free; Ref.Free;
  end;

  WriteLn;
  WriteLn('3. クリップ（転送先で切った分だけ転送元をずらす）');
  Src := TPMLSurface.Create(8, 8, PML_PIXELFORMAT_ARGB8888);
  Dst := TPMLSurface.Create(8, 8, PML_PIXELFORMAT_ARGB8888);
  Ref := TPMLSurface.Create(8, 8, PML_PIXELFORMAT_ARGB8888);
  try
    Paint(Src, 0);
    Dst.Fill(TPMLColor.Black);
    Ref.Fill(TPMLColor.Black);
    // 負の位置へ置く。左上が切られ、転送元は (3, 2) から始まるはず。
    PMLBlit(Src, TPMLRect.Make(0, 0, 0, 0), Dst, TPMLRect.Make(-3, -2, 0, 0));
    RefBlit(Src, TPMLRect.Make(0, 0, 0, 0), Ref, TPMLRect.Make(-3, -2, 0, 0));
    Check(SamePixels(Dst, Ref), '負の位置でも参照実装と一致する');
    // ずれていれば必ずここが違う。転送先 (0,0) には転送元 (3,2) が来る。
    Check(SameColor(Dst.ReadPixel(0, 0), Src.ReadPixel(3, 2)),
      '切られた分だけ転送元がずれている');

    // 転送先のクリップ矩形でも同じことが起きる。
    Dst.Fill(TPMLColor.Black);
    Ref.Fill(TPMLColor.Black);
    Dst.ClipRect := TPMLRect.Make(2, 2, 4, 4);
    Ref.ClipRect := TPMLRect.Make(2, 2, 4, 4);
    PMLBlit(Src, TPMLRect.Make(0, 0, 0, 0), Dst, TPMLRect.Make(0, 0, 0, 0));
    RefBlit(Src, TPMLRect.Make(0, 0, 0, 0), Ref, TPMLRect.Make(0, 0, 0, 0));
    Check(SamePixels(Dst, Ref), 'クリップ矩形でも参照実装と一致する');
    Check(SameColor(Dst.ReadPixel(2, 2), Src.ReadPixel(2, 2)),
      'クリップ矩形の左上に転送元の同じ位置が来る');
    Check(SameColor(Dst.ReadPixel(1, 1), TPMLColor.Black),
      'クリップ矩形の外は書かれない');

    // まったく重ならない場合。
    Dst.ClipRect := TPMLRect.Make(0, 0, 8, 8);
    Check(not PMLBlit(Src, TPMLRect.Make(0, 0, 0, 0), Dst,
      TPMLRect.Make(100, 100, 0, 0)), '範囲外なら False');
  finally
    Src.Free; Dst.Free; Ref.Free;
  end;

  WriteLn;
  WriteLn('4. 合成モード（浮動小数点の参照式と突き合わせる）');
  Bad := 0;
  Worst := 0;
  for Mode := Low(TPMLBlendMode) to High(TPMLBlendMode) do
  begin
    for X := 0 to 255 do
    begin
      CS := TPMLColor.Make(Byte(X), Byte(255 - X), Byte(X * 3), Byte(X));
      CD := TPMLColor.Make(Byte(255 - X), Byte(X), Byte(X * 5), Byte(200));
      CA := PMLBlendColor(CS, CD, Mode);
      CB := RefBlend(CS, CD, Mode);
      if not NearColor(CA, CB, 1) then
        Inc(Bad);
      Diff := Max(Max(Abs(Integer(CA.R) - Integer(CB.R)),
                      Abs(Integer(CA.G) - Integer(CB.G))),
                  Max(Abs(Integer(CA.B) - Integer(CB.B)),
                      Abs(Integer(CA.A) - Integer(CB.A))));
      if Diff > Worst then
        Worst := Diff;
    end;
  end;
  Check(Bad = 0, '5 モード x 256 通りが参照式と一致する（許容 ±1）');
  Note(Format('最大の差 %d（丸めの違いのみ）', [Worst]));

  // 代表的な値を直接確かめる。式の取り違えは中間値でなく端で出やすい。
  CS := TPMLColor.Make(255, 0, 0, 255);
  CD := TPMLColor.Make(0, 0, 255, 255);
  Check(SameColor(PMLBlendColor(CS, CD, TPMLBlendMode.Blend),
    TPMLColor.Make(255, 0, 0, 255)), '不透明の Blend は転送元そのもの');
  CS.A := 0;
  Check(SameColor(PMLBlendColor(CS, CD, TPMLBlendMode.Blend),
    TPMLColor.Make(0, 0, 255, 255)), '完全透明の Blend は転送先のまま');

  WriteLn;
  WriteLn('5. 合成つきの転送');
  Src := TPMLSurface.Create(4, 4, PML_PIXELFORMAT_ARGB8888);
  Dst := TPMLSurface.Create(4, 4, PML_PIXELFORMAT_ARGB8888);
  try
    Src.Fill(TPMLColor.Make(255, 0, 0, 128));
    Dst.Fill(TPMLColor.Make(0, 0, 255, 255));
    Src.BlendMode := TPMLBlendMode.Blend;
    PMLBlit(Src, TPMLRect.Make(0, 0, 0, 0), Dst, TPMLRect.Make(0, 0, 0, 0));
    CA := Dst.ReadPixel(1, 1);
    CB := RefBlend(TPMLColor.Make(255, 0, 0, 128),
                   TPMLColor.Make(0, 0, 255, 255), TPMLBlendMode.Blend);
    Check(NearColor(CA, CB, 1), '半透明を重ねた結果が参照式と一致する');
  finally
    Src.Free; Dst.Free;
  end;

  WriteLn;
  WriteLn('6. カラーキーと変調');
  Src := TPMLSurface.Create(4, 4, PML_PIXELFORMAT_ARGB8888);
  Dst := TPMLSurface.Create(4, 4, PML_PIXELFORMAT_ARGB8888);
  try
    Src.Fill(TPMLColor.Make(10, 20, 30, 255));
    Src.WritePixel(1, 1, TPMLColor.Make(255, 0, 255, 255));   // これを透明扱いに
    Src.SetColorKey(True, Src.MapColor(TPMLColor.Make(255, 0, 255, 255)));
    Dst.Fill(TPMLColor.Make(7, 7, 7, 255));
    PMLBlit(Src, TPMLRect.Make(0, 0, 0, 0), Dst, TPMLRect.Make(0, 0, 0, 0));
    Check(SameColor(Dst.ReadPixel(0, 0), TPMLColor.Make(10, 20, 30, 255)),
      'カラーキー以外は転送される');
    Check(SameColor(Dst.ReadPixel(1, 1), TPMLColor.Make(7, 7, 7, 255)),
      'カラーキーの画素は転送先を残す');

    // 色の変調。半分に落とせば結果も半分になる。
    Src.SetColorKey(False, 0);
    Src.Fill(TPMLColor.Make(200, 100, 50, 255));
    Src.ColorMod := TPMLColor.Make(128, 255, 0, 255);
    Dst.Fill(TPMLColor.Black);
    PMLBlit(Src, TPMLRect.Make(0, 0, 0, 0), Dst, TPMLRect.Make(0, 0, 0, 0));
    CA := Dst.ReadPixel(0, 0);
    Check((Abs(Integer(CA.R) - 100) <= 1) and (CA.G = 100) and (CA.B = 0),
      Format('ColorMod が効く（R=%d G=%d B=%d）', [CA.R, CA.G, CA.B]));
  finally
    Src.Free; Dst.Free;
  end;

  WriteLn;
  WriteLn('7. 拡大縮小');
  Src := TPMLSurface.Create(2, 2, PML_PIXELFORMAT_ARGB8888);
  Dst := TPMLSurface.Create(4, 4, PML_PIXELFORMAT_ARGB8888);
  try
    Src.WritePixel(0, 0, TPMLColor.Make(255, 0, 0, 255));
    Src.WritePixel(1, 0, TPMLColor.Make(0, 255, 0, 255));
    Src.WritePixel(0, 1, TPMLColor.Make(0, 0, 255, 255));
    Src.WritePixel(1, 1, TPMLColor.Make(255, 255, 0, 255));
    Dst.Fill(TPMLColor.Black);
    Check(PMLBlitScaled(Src, TPMLRect.Make(0, 0, 0, 0), Dst,
      TPMLRect.Make(0, 0, 4, 4)), '2 倍に拡大できた');
    // 2 倍なので 2x2 の塊になる。角と中央を確かめる。
    OK := SameColor(Dst.ReadPixel(0, 0), Src.ReadPixel(0, 0))
      and SameColor(Dst.ReadPixel(1, 1), Src.ReadPixel(0, 0))
      and SameColor(Dst.ReadPixel(2, 0), Src.ReadPixel(1, 0))
      and SameColor(Dst.ReadPixel(0, 2), Src.ReadPixel(0, 1))
      and SameColor(Dst.ReadPixel(3, 3), Src.ReadPixel(1, 1));
    Check(OK, '2 倍拡大は 2x2 の塊になる');
  finally
    Src.Free; Dst.Free;
  end;

  // 縮小では両端が使われること。左上の角から逆算すると右端と下端が落ちる。
  Src := TPMLSurface.Create(4, 1, PML_PIXELFORMAT_ARGB8888);
  Dst := TPMLSurface.Create(2, 1, PML_PIXELFORMAT_ARGB8888);
  try
    for X := 0 to 3 do
      Src.WritePixel(X, 0, TPMLColor.Make(Byte(X * 60), 0, 0, 255));
    PMLBlitScaled(Src, TPMLRect.Make(0, 0, 0, 0), Dst, TPMLRect.Make(0, 0, 2, 1));
    // 画素の中心から逆算するので、標本は転送元の 1 と 3 になる。
    Check(SameColor(Dst.ReadPixel(0, 0), Src.ReadPixel(1, 0)),
      '縮小の左は転送元の 1 番目を採る（中心から逆算）');
    Check(SameColor(Dst.ReadPixel(1, 0), Src.ReadPixel(3, 0)),
      '縮小の右は転送元の 3 番目を採る');
  finally
    Src.Free; Dst.Free;
  end;

  WriteLn;
  WriteLn('8. 塗りつぶし');
  Dst := TPMLSurface.Create(9, 5, PML_PIXELFORMAT_ARGB8888);
  Ref := TPMLSurface.Create(9, 5, PML_PIXELFORMAT_ARGB8888);
  try
    Dst.Fill(TPMLColor.Black);
    Ref.Fill(TPMLColor.Black);
    Check(PMLFillRect(Dst, TPMLRect.Make(1, 1, 6, 3),
      TPMLColor.Make(10, 200, 30, 255)), '塗れた');
    // 参照実装は 1 画素ずつ。
    for Y := 1 to 3 do
      for X := 1 to 6 do
        Ref.WritePixel(X, Y, TPMLColor.Make(10, 200, 30, 255));
    Check(SamePixels(Dst, Ref), '参照実装と一致する');
    Check(SameColor(Dst.ReadPixel(0, 0), TPMLColor.Black), '外は変わらない');
    Check(SameColor(Dst.ReadPixel(7, 1), TPMLColor.Black), '右隣も変わらない');

    // 3 バイト形式でも行ごとの写しが正しいこと。
    Tmp := TPMLSurface.Create(7, 3, PML_PIXELFORMAT_BGR24);
    try
      PMLFillRect(Tmp, TPMLRect.Make(0, 0, 7, 3), TPMLColor.Make(1, 2, 3, 255));
      OK := True;
      for Y := 0 to 2 do
        for X := 0 to 6 do
          if not SameColor(Tmp.ReadPixel(X, Y), TPMLColor.Make(1, 2, 3, 255)) then
            OK := False;
      Check(OK, '24 ビット形式でも全画素が塗られる');
    finally
      Tmp.Free;
    end;

    Check(not PMLFillRect(Dst, TPMLRect.Make(50, 50, 4, 4), TPMLColor.White),
      '範囲外なら False');
  finally
    Dst.Free; Ref.Free;
  end;

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn('=== 結論: ブリッタが参照実装と一致する ===');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('=== 失敗 %d 件 ===', [Failures]));
    ExitCode := 1;
  end;
end.
