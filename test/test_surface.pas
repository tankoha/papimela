{
  test_surface — サーフェスと BMP の読み書き

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    サーフェスの生成・所有・画素の読み書き・変換・反転と、BMP の往復を確認する。

  WHY:
    サーフェスは「ピクセルを誰が持っているか」で振る舞いが変わる。自前で確保した
    場合と外から借りた場合で解放の扱いが違い、間違えると二重解放か漏れになる。
    そこを検査で押さえる。

    BMP は**書いて読み直して一致するか**を見る。ヘッダの版、行の詰め物、
    上下の向きのどれかを間違えると、往復で必ず壊れる。加えて
    他のソフトが書いた並びも読めるよう、手で組んだバイト列も読ませる。

  実行前提: 無し。一時ファイルを作って消す。
}
program test_surface;

{$mode objfpc}{$H+}
{$scopedenums on}
{$interfaces corba}

uses
  SysUtils, Classes,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.BMP;

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

// 市松模様を描く。往復の検査に使う。位置ごとに違う色にするのが要点で、
// 行や列がずれれば必ず気づける。
procedure PaintPattern(ASurface: TPMLSurface);
var
  X, Y: Integer;
begin
  for Y := 0 to ASurface.Height - 1 do
    for X := 0 to ASurface.Width - 1 do
      ASurface.WritePixel(X, Y,
        TPMLColor.Make(Byte(X * 8), Byte(Y * 8), Byte((X + Y) * 4), 255));
end;

function SamePixels(A, B: TPMLSurface; AIgnoreAlpha: Boolean): Boolean;
var
  X, Y: Integer;
  CA, CB: TPMLColor;
begin
  Result := False;
  if (A.Width <> B.Width) or (A.Height <> B.Height) then
    Exit;
  for Y := 0 to A.Height - 1 do
    for X := 0 to A.Width - 1 do
    begin
      CA := A.ReadPixel(X, Y);
      CB := B.ReadPixel(X, Y);
      if AIgnoreAlpha then
      begin
        CA.A := 255;
        CB.A := 255;
      end;
      if not SameColor(CA, CB) then
        Exit;
    end;
  Result := True;
end;

var
  S, S2, S3: TPMLSurface;
  Shared   : IPMLSurface;
  Borrowed : array[0..(16 * 16) - 1] of LongWord;
  Path     : String;
  Mem      : TMemoryStream;
  C        : TPMLColor;
  Raised   : Boolean;
  X, Y     : Integer;
begin
  WriteLn('test_surface — サーフェスと BMP');
  WriteLn;

  Path := GetTempDir(False) + 'papimela-test-surface.bmp';

  WriteLn('1. 生成と所有');
  S := TPMLSurface.Create(16, 9, PML_PIXELFORMAT_ARGB8888);
  try
    Check((S.Width = 16) and (S.Height = 9), '要求した大きさになる');
    Check(S.Pitch = 16 * 4, 'ピッチは幅 * 4 バイト');
    Check(S.OwnsPixels, '自前でピクセルを持つ');
    Check(S.Pixels <> nil, 'ピクセルが確保されている');
    Check(S.Details.BytesPerPixel = 4, '形式の詳細が入っている');
    Check(S.ReadPixel(0, 0).A = 0, '生成直後は 0 で埋まっている');
    // 3 バイト形式のピッチは 4 の倍数へ切り上げる。
    S2 := TPMLSurface.Create(5, 2, PML_PIXELFORMAT_BGR24);
    try
      Check(S2.Pitch = 16, '幅 5 の 24 ビットはピッチ 16（4 バイト境界）');
    finally
      S2.Free;
    end;
  finally
    S.Free;
  end;

  // 借りたピクセルは解放してはならない。解放すれば次の使用で壊れる。
  for X := 0 to High(Borrowed) do
    Borrowed[X] := $FF204060;
  S := TPMLSurface.CreateFrom(@Borrowed[0], 16, 16, 16 * 4,
    PML_PIXELFORMAT_ARGB8888);
  try
    Check(not S.OwnsPixels, '借りたピクセルは所有しない');
    Check(S.ReadPixel(0, 0).R = $20, '借りた内容が読める');
    S.WritePixel(0, 0, TPMLColor.Make(1, 2, 3, 4));
  finally
    S.Free;
  end;
  Check(Borrowed[0] = $04010203, '書き込みが元の配列に反映されている');

  WriteLn;
  WriteLn('2. 画素の読み書きとクリップ');
  S := TPMLSurface.Create(8, 8, PML_PIXELFORMAT_ARGB8888);
  try
    S.WritePixel(3, 4, TPMLColor.Make(10, 20, 30, 40));
    Check(SameColor(S.ReadPixel(3, 4), TPMLColor.Make(10, 20, 30, 40)),
      '書いた色が読める');
    // 範囲外は落ちずに無視する。
    S.WritePixel(-1, 0, TPMLColor.White);
    S.WritePixel(8, 0, TPMLColor.White);
    Check(S.ReadPixel(-1, 0).A = 255, '範囲外の読み取りは黒（不透明）');

    S.Fill(TPMLColor.Make(0, 0, 0, 255));
    S.ClipRect := TPMLRect.Make(2, 2, 3, 3);
    S.FillRect(TPMLRect.Make(0, 0, 8, 8), TPMLColor.Make(255, 0, 0, 255));
    Check(S.ReadPixel(0, 0).R = 0, 'クリップ矩形の外は塗られない');
    Check(S.ReadPixel(2, 2).R = 255, 'クリップ矩形の中は塗られる');
    Check(S.ReadPixel(4, 4).R = 255, 'クリップ矩形の右下端も塗られる');
    Check(S.ReadPixel(5, 5).R = 0, 'クリップ矩形の 1 つ外は塗られない');

    // クリップ矩形はサーフェスの外へはみ出さない。
    S.ClipRect := TPMLRect.Make(-5, -5, 100, 100);
    Check((S.ClipRect.X = 0) and (S.ClipRect.Y = 0)
      and (S.ClipRect.W = 8) and (S.ClipRect.H = 8),
      'はみ出したクリップ矩形はサーフェスと交差させる');
  finally
    S.Free;
  end;

  WriteLn;
  WriteLn('3. 複製・変換・反転');
  S := TPMLSurface.Create(16, 8, PML_PIXELFORMAT_ARGB8888);
  try
    PaintPattern(S);

    S2 := S.Duplicate;
    try
      Check(SamePixels(S, S2, False), '複製の内容が一致する');
      Check(S2.OwnsPixels, '複製は自前でピクセルを持つ');
      S2.WritePixel(0, 0, TPMLColor.White);
      Check(S.ReadPixel(0, 0).R <> 255, '複製を書き換えても元に影響しない');
    finally
      S2.Free;
    end;

    // 8 ビット成分同士の変換は情報が落ちない。
    S2 := S.Convert(PML_PIXELFORMAT_ABGR8888);
    try
      Check(S2.Format = PML_PIXELFORMAT_ABGR8888, '要求した形式になる');
      Check(SamePixels(S, S2, False), '並びが違っても色は保たれる');
      S3 := S2.Convert(PML_PIXELFORMAT_ARGB8888);
      try
        Check(SamePixels(S, S3, False), '往復して元に戻る');
      finally
        S3.Free;
      end;
    finally
      S2.Free;
    end;

    // アルファを落とす変換では A が 255 になる。
    S2 := S.Convert(PML_PIXELFORMAT_BGR24);
    try
      Check(S2.ReadPixel(1, 1).A = 255, 'アルファの無い形式では A が 255');
      Check(SamePixels(S, S2, True), 'RGB は保たれる');
    finally
      S2.Free;
    end;

    C := S.ReadPixel(0, 0);
    S.Flip(TPMLFlipMode.Horizontal);
    Check(SameColor(S.ReadPixel(15, 0), C), '左右反転で端が入れ替わる');
    S.Flip(TPMLFlipMode.Horizontal);
    Check(SameColor(S.ReadPixel(0, 0), C), '二度反転すると戻る');
    S.Flip(TPMLFlipMode.Vertical);
    Check(SameColor(S.ReadPixel(0, 7), C), '上下反転で端が入れ替わる');
  finally
    S.Free;
  end;

  WriteLn;
  WriteLn('4. 共有の opt-in');
  S := TPMLSurface.Create(4, 4, PML_PIXELFORMAT_ARGB8888);
  try
    // 既定のサーフェスはインターフェース変数に入れても寿命が変わらない。
    Shared := S;
    Shared := nil;
    Check(S.Width = 4, '既定のサーフェスは参照が消えても生きている');
  finally
    S.Free;
  end;

  Shared := TPMLSurface.CreateShared(4, 4, PML_PIXELFORMAT_ARGB8888);
  Check(Shared.Surface.Width = 4, '共有サーフェスを作れる');
  Shared.Surface.WritePixel(0, 0, TPMLColor.White);
  Check(Shared.Surface.ReadPixel(0, 0).R = 255, '共有サーフェスに書ける');
  // 参照が消えれば解放される。ここで落ちなければ二重解放も漏れもない。
  Shared := nil;
  Check(True, '最後の参照が消えても落ちない');

  WriteLn;
  WriteLn('5. BMP の往復（24 ビット）');
  S := TPMLSurface.Create(13, 7, PML_PIXELFORMAT_BGR24);   // 幅を 4 の倍数にしない
  try
    PaintPattern(S);
    PMLSaveBMPFile(Path, S);
    Check(FileExists(Path), 'BMP を書き出せる');
    S2 := PMLLoadBMPFile(Path);
    try
      Check((S2.Width = 13) and (S2.Height = 7), '大きさが往復する');
      // 幅 13 の 24 ビットは行が 39 バイトで、4 バイト境界まで詰め物が要る。
      Check(SamePixels(S, S2, True), '詰め物のある幅でも内容が往復する');
    finally
      S2.Free;
    end;
  finally
    S.Free;
  end;

  WriteLn;
  WriteLn('6. BMP の往復（32 ビット・アルファあり）');
  S := TPMLSurface.Create(5, 3, PML_PIXELFORMAT_ARGB8888);
  try
    for Y := 0 to S.Height - 1 do
      for X := 0 to S.Width - 1 do
        S.WritePixel(X, Y, TPMLColor.Make(Byte(X * 50), Byte(Y * 80),
          Byte(255 - X * 40), Byte(X * 60)));
    Mem := TMemoryStream.Create;
    try
      PMLSaveBMP(Mem, S);
      Mem.Position := 0;
      S2 := PMLLoadBMP(Mem);
      try
        Check(SamePixels(S, S2, False), 'アルファも含めて往復する');
        Check(S2.Details.HasAlpha, '読み戻した形式がアルファを持つ');
      finally
        S2.Free;
      end;
    finally
      Mem.Free;
    end;
  finally
    S.Free;
  end;

  WriteLn;
  WriteLn('7. 他のソフトが書いた形の BMP を読む');
  // 手で組んだ 8 ビットパレット BMP。2x2、下から上。
  // 行は 4 バイト境界なので 1 行 4 バイト（うち 2 バイトが詰め物）。
  Mem := TMemoryStream.Create;
  try
    Mem.WriteBuffer(PAnsiChar('BM')^, 2);
    Mem.Position := Mem.Size;
    // fileSize / reserved / dataOffset（14 + 40 + 4 色 * 4 = 70）
    Mem.WriteDWord(NtoLE(LongWord(78)));
    Mem.WriteDWord(0);
    Mem.WriteDWord(NtoLE(LongWord(70)));
    Mem.WriteDWord(NtoLE(LongWord(40)));      // ヘッダの大きさ
    Mem.WriteDWord(NtoLE(LongWord(2)));       // 幅
    Mem.WriteDWord(NtoLE(LongWord(2)));       // 高さ（正 = 下から上）
    Mem.WriteWord(NtoLE(Word(1)));            // プレーン数
    Mem.WriteWord(NtoLE(Word(8)));            // ビット数
    Mem.WriteDWord(0);                        // BI_RGB
    Mem.WriteDWord(0);                        // 画像の大きさ
    Mem.WriteDWord(0);
    Mem.WriteDWord(0);
    Mem.WriteDWord(NtoLE(LongWord(4)));       // 使った色数
    Mem.WriteDWord(0);
    // パレット 4 色。BMP のパレットはバイト順が B, G, R, 未使用なので、
    // リトルエンディアンの DWORD として書くと $00RRGGBB の並びになる。
    Mem.WriteDWord(NtoLE(LongWord($00000000)));   // 0 = 黒
    Mem.WriteDWord(NtoLE(LongWord($00FF0000)));   // 1 = 赤
    Mem.WriteDWord(NtoLE(LongWord($0000FF00)));   // 2 = 緑
    Mem.WriteDWord(NtoLE(LongWord($000000FF)));   // 3 = 青
    // 画素。下の行から書く。
    Mem.WriteByte(2); Mem.WriteByte(3); Mem.WriteByte(0); Mem.WriteByte(0);
    Mem.WriteByte(0); Mem.WriteByte(1); Mem.WriteByte(0); Mem.WriteByte(0);

    Mem.Position := 0;
    S := nil;
    S := PMLLoadBMP(Mem);
    try
      Check((S.Width = 2) and (S.Height = 2), 'パレット BMP の大きさ');
      Check(S.Palette <> nil, 'パレットが読み込まれている');
      // ファイルでは下の行が先なので、上の行は後から読んだ 0, 1 になる。
      Check(SameColor(S.ReadPixel(0, 0), TPMLColor.Make(0, 0, 0)),
        '上段左は黒（下から上の順を解けている）');
      Check(SameColor(S.ReadPixel(1, 0), TPMLColor.Make(255, 0, 0)),
        '上段右は赤');
      Check(SameColor(S.ReadPixel(0, 1), TPMLColor.Make(0, 255, 0)),
        '下段左は緑');
      Check(SameColor(S.ReadPixel(1, 1), TPMLColor.Make(0, 0, 255)),
        '下段右は青');
    finally
      S.Free;
    end;
  finally
    Mem.Free;
  end;

  WriteLn;
  WriteLn('8. 壊れた入力');
  Mem := TMemoryStream.Create;
  try
    Mem.WriteBuffer(PAnsiChar('XX')^, 2);
    Mem.Position := 0;
    Raised := False;
    try
      S := PMLLoadBMP(Mem);
      S.Free;
    except
      on E: EPMLError do
        Raised := True;
    end;
    Check(Raised, 'BMP でないものは例外');
  finally
    Mem.Free;
  end;

  WriteLn;
  WriteLn('9. 後始末');
  Check(DeleteFile(Path), '一時ファイルを消せる');

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn('=== 結論: サーフェスと BMP が設計どおり ===');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Format('=== 失敗 %d 件 ===', [Failures]));
    ExitCode := 1;
  end;
end.
