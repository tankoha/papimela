{
  test_yuv_hd — I444 と P010（SDL_PIXELFORMAT_I444 / SDL_PIXELFORMAT_P010）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    参照版 SDL に I444 と P010 を通した結果（test/yuv_hd_expected.inc。tools/yuv-hd-expect/gen.bb が作る）と、
    papimela の結果を場面ごとに突き合わせる:
    1. 大きさ（SDL_CalculateYUVSize）。I444 は 3 平面 w*h*3、P010 は 16 ビットの Y と色差
    2. YUV から RGB への変換の値。I444 は ARGB8888 へ、P010 は XBGR2101010 へ。5 つの色空間 x 3 つの大きさ
    3. I444 のテクスチャ（ソフトウェアのレンダラの肩代わり）: 詰めた画素での更新、平面ごとの更新、Lock、
       矩形つきの更新。描いた絵のハッシュ
    4. 断るもの: P010 のテクスチャ（SDL のソフトウェアのレンダラも作れない）、I444 に UpdateNV、
       I444 の部分の Lock、NV12 に UpdateYUV
    5. papimela の足した検査: 形式の判定（PMLIsYUVFormat は I444 を含み P010 を含まない）、P010 から
       ほかの形式への変換は無い（EPMLArgument）、色空間を選べないものは断る

  WHY:
    §3 の 2「残してあるテクスチャのもの」の I444 / P010 の受け入れ検査。表示サーバは要らない。
    GLES2 のドライバの I444 は test_render_gles2 のオフスクリーンの節にある。

  SDL との違い（意図したもの）:
    - 8 ビットの値は範囲の内側に収めて比べる（範囲の外は SDL のスカラー版が回り込み、papimela は飽和させる。D-62）
    - 色空間を変換できないときは作るときに断る（SDL は更新のときに断る）
    - エラーの文面は種類で比べない。投げるかどうかだけ比べる
}
program test_yuv_hd;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, StrUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.YUV,
  PaPiMeLa.Render,
  PaPiMeLa.Render.Software;

{$I yuv_hd_expected.inc}

type
  TSpace = record
    Name : String;
    Space: TPMLColorspace;
  end;

var
  Failures: Integer = 0;
  Lcg: LongWord = 1;
  Target: TPMLSurface;
  R: TPMLRenderer;

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

function Spaces(AIndex: Integer): TSpace;
begin
  case AIndex of
    0: begin Result.Name := 'bt601l'; Result.Space := PML_COLORSPACE_BT601_LIMITED; end;
    1: begin Result.Name := 'jpeg'; Result.Space := PML_COLORSPACE_JPEG; end;
    2: begin Result.Name := 'bt709l'; Result.Space := PML_COLORSPACE_BT709_LIMITED; end;
    3: begin Result.Name := 'bt709f'; Result.Space := PML_COLORSPACE_BT709_FULL; end;
  else
    begin Result.Name := 'bt2020f'; Result.Space := PML_COLORSPACE_BT2020_FULL; end;
  end;
end;

const
  SizeW: array[0..2] of Integer = (7, 16, 40);
  SizeH: array[0..2] of Integer = (5, 4, 6);

{ ---- SDL の側 (yuv_cases.c) と同じ部品 ---- }

function Nx: LongWord;
begin
  Lcg := Lcg * 1103515245 + 12345;
  Result := Lcg shr 16;
end;

function Y8: Byte;
begin
  Result := Byte(70 + (Nx mod 80));
end;

function C8: Byte;
begin
  Result := Byte(96 + (Nx and 63));
end;

procedure FillI444(P: PByte; AW, AH: Integer; ASeed: LongWord);
var
  I: Integer;
begin
  Lcg := ASeed;
  for I := 0 to AW * AH - 1 do
    P[I] := Y8;
  for I := 0 to 2 * AW * AH - 1 do
    P[AW * AH + I] := C8;
end;

function Fnv(P: PByte; ALen: PtrInt; AHash: LongWord): LongWord;
var
  I: PtrInt;
begin
  Result := AHash;
  for I := 0 to ALen - 1 do
  begin
    Result := Result xor P[I];
    Result := Result * 16777619;
  end;
end;

function Hex(AValue: LongWord): String;
begin
  Result := IntToHex(AValue, 8);
end;

{ 期待の表に、この行がそのまま入っているか。 }
function Has(const ALine: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(YUVHDExpected) do
    if YUVHDExpected[I] = ALine then
      Exit(True);
end;

{ ALine から最後の語（ハッシュ）を除いた先頭と同じ行を探して返す（失敗の表示用）。 }
function Wanted(const ALine: String): String;
var
  Head: String;
  I: Integer;
begin
  Head := Copy(ALine, 1, RPos(' ', ALine));
  Result := '(場面が無い)';
  for I := 0 to High(YUVHDExpected) do
    if Copy(YUVHDExpected[I], 1, Length(Head)) = Head then
      Exit(YUVHDExpected[I]);
end;

procedure Same(const ALine: String);
begin
  Check(Has(ALine), ALine + '   (SDL: ' + Wanted(ALine) + ')');
end;

{ 描いた絵のハッシュ（SDL の側の render_hash と同じ。AW x AH の 1:1）。 }
function RenderHash(T: TPMLTexture; AW, AH: Integer): LongWord;
var
  Y: Integer;
begin
  R.DrawColor := TPMLColor.Make(10, 20, 30, 255);
  R.Clear;
  R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, AW, AH));
  R.Present;
  Result := 2166136261;
  for Y := 0 to AH - 1 do
    Result := Fnv(PByte(Target.Pixels) + Y * Target.Pitch, AW * 4, Result);
end;

function NewTexture(AFormat: TPMLPixelFormat; ASpace: TPMLColorspace; AW, AH: Integer): TPMLTexture;
begin
  Result := R.CreateTexture(AFormat, TPMLTextureAccess.Streaming, AW, AH, ASpace);
  Result.BlendMode := TPMLBlendMode.None;
end;

{ ---- 場面 ---- }

procedure TestSizes;
const
  Ws: array[0..3] of Integer = (7, 8, 1, 40);
  Hs: array[0..3] of Integer = (5, 6, 1, 6);
var
  I, F: Integer;
  Size: PtrUInt;
  Pitch: Integer;
  Fmt: TPMLPixelFormat;
  Name: String;
begin
  WriteLn('1 大きさ（SDL_CalculateYUVSize）');
  for F := 0 to 1 do
  begin
    if F = 0 then
    begin
      Fmt := PML_PIXELFORMAT_I444;
      Name := 'I444';
    end
    else
    begin
      Fmt := PML_PIXELFORMAT_P010;
      Name := 'P010';
    end;
    for I := 0 to 3 do
    begin
      Size := 0;
      Pitch := 0;
      if PMLCalculateYUVSize(Fmt, Ws[I], Hs[I], Size, Pitch) then
        Same(Format('Z %s %d %d %d %d', [Name, Ws[I], Hs[I], Size, Pitch]))
      else
        Check(False, Format('%s %dx%d の大きさを返す', [Name, Ws[I], Hs[I]]));
    end;
  end;
end;

procedure TestConvert;
var
  S, Z, W, H, I: Integer;
  Size: PtrUInt;
  Pitch: Integer;
  Src, Dst: TBytes;
  Sp: TSpace;
begin
  WriteLn('2 変換の値（5 つの色空間 x 3 つの大きさ）');
  for S := 0 to 4 do
    for Z := 0 to 2 do
    begin
      Sp := Spaces(S);
      W := SizeW[Z];
      H := SizeH[Z];
      // I444 -> ARGB8888
      PMLCalculateYUVSize(PML_PIXELFORMAT_I444, W, H, Size, Pitch);
      SetLength(Src, Size);
      SetLength(Dst, W * H * 4);
      FillChar(Src[0], Size, 0);
      FillChar(Dst[0], Length(Dst), 0);
      FillI444(@Src[0], W, H, 5 + S * 3 + Z);
      PMLConvertYUVToARGB8888(W, H, PML_PIXELFORMAT_I444, Sp.Space, @Src[0], Pitch, @Dst[0], W * 4);
      Same(Format('C I444 %s %d %d %s', [Sp.Name, W, H, Hex(Fnv(@Dst[0], Length(Dst), 2166136261))]));
      // P010 -> XBGR2101010（値は 16 ビットの全域）
      PMLCalculateYUVSize(PML_PIXELFORMAT_P010, W, H, Size, Pitch);
      SetLength(Src, Size);
      SetLength(Dst, W * H * 4);
      FillChar(Src[0], Size, 0);
      FillChar(Dst[0], Length(Dst), 0);
      Lcg := 11 + S * 7 + Z;
      for I := 0 to Size div 2 - 1 do
        PWord(@Src[0])[I] := Word(Nx and $FFFF);
      PMLConvertP010ToXBGR2101010(W, H, Sp.Space, @Src[0], Pitch, @Dst[0], W * 4);
      Same(Format('C P010 %s %d %d %s', [Sp.Name, W, H, Hex(Fnv(@Dst[0], Length(Dst), 2166136261))]));
    end;
end;

procedure TestTexture;
var
  S, Z, W, H, Pitch, LockPitch: Integer;
  Size: PtrUInt;
  Buf, A, B: TBytes;
  T: TPMLTexture;
  P: PByte;
  Sp: TSpace;
  Rc: TPMLRect;
  I: Integer;
begin
  WriteLn('3 I444 のテクスチャ');
  for S := 0 to 4 do
    for Z := 0 to 2 do
    begin
      Sp := Spaces(S);
      W := SizeW[Z];
      H := SizeH[Z];
      PMLCalculateYUVSize(PML_PIXELFORMAT_I444, W, H, Size, Pitch);
      SetLength(Buf, Size);
      FillChar(Buf[0], Size, 0);
      FillI444(@Buf[0], W, H, 40 + S + Z);
      // 詰めた画素
      T := NewTexture(PML_PIXELFORMAT_I444, Sp.Space, W, H);
      try
        T.Update(TPMLRect.Make(0, 0, 0, 0), @Buf[0], Pitch);
        Same(Format('T packed %s %d %d %s', [Sp.Name, W, H, Hex(RenderHash(T, W, H))]));
      finally
        T.Free;
      end;
      // 平面ごと
      T := NewTexture(PML_PIXELFORMAT_I444, Sp.Space, W, H);
      try
        T.UpdateYUV(TPMLRect.Make(0, 0, 0, 0), @Buf[0], W, @Buf[W * H], W, @Buf[2 * W * H], W);
        Same(Format('T planar %s %d %d %s', [Sp.Name, W, H, Hex(RenderHash(T, W, H))]));
      finally
        T.Free;
      end;
      // Lock
      T := NewTexture(PML_PIXELFORMAT_I444, Sp.Space, W, H);
      try
        P := T.Lock(TPMLRect.Make(0, 0, 0, 0), LockPitch);
        Move(Buf[0], P^, Size);
        T.Unlock;
        Same(Format('T lock %s %d %d %d %s', [Sp.Name, W, H, LockPitch, Hex(RenderHash(T, W, H))]));
      finally
        T.Free;
      end;
    end;

  // 矩形つきの更新。平面の区切りが矩形の位置とずれるので、全部の値を 96..159 にする
  W := 16;
  H := 4;
  PMLCalculateYUVSize(PML_PIXELFORMAT_I444, W, H, Size, Pitch);
  SetLength(A, Size);
  SetLength(B, Size);
  Lcg := 71;
  for I := 0 to Size - 1 do
    A[I] := C8;
  Lcg := 72;
  for I := 0 to Size - 1 do
    B[I] := C8;
  Rc := TPMLRect.Make(3, 1, 9, 2);
  T := NewTexture(PML_PIXELFORMAT_I444, PML_COLORSPACE_BT709_LIMITED, W, H);
  try
    T.Update(TPMLRect.Make(0, 0, 0, 0), @A[0], W);
    T.UpdateYUV(Rc, @B[1 * W + 3], W, @B[W * H + 1 * W + 3], W, @B[2 * W * H + 1 * W + 3], W);
    Same(Format('T planar_rect bt709l %d %d %s', [W, H, Hex(RenderHash(T, W, H))]));
  finally
    T.Free;
  end;
  T := NewTexture(PML_PIXELFORMAT_I444, PML_COLORSPACE_BT709_LIMITED, W, H);
  try
    T.Update(TPMLRect.Make(0, 0, 0, 0), @A[0], W);
    T.Update(Rc, @B[1 * W + 3], W);
    Same(Format('T packed_rect bt709l %d %d %s', [W, H, Hex(RenderHash(T, W, H))]));
  finally
    T.Free;
  end;
end;

{ 行の幅に余りがある詰めた画素と平面ごと（全体の更新。行ごとに写す道）。 }
procedure TestPitch;
var
  Buf: TBytes;
  I: Integer;
  T: TPMLTexture;
  W, H, Pitch: Integer;
begin
  WriteLn('3b 行の幅に余り');
  W := 16;
  H := 4;
  Pitch := 21;
  SetLength(Buf, Pitch * H * 3);
  Lcg := 91;
  for I := 0 to High(Buf) do
    Buf[I] := C8;
  T := NewTexture(PML_PIXELFORMAT_I444, PML_COLORSPACE_BT709_LIMITED, W, H);
  try
    T.Update(TPMLRect.Make(0, 0, 0, 0), @Buf[0], Pitch);
    Same(Format('T packed_pitch bt709l %d %d %s', [W, H, Hex(RenderHash(T, W, H))]));
  finally
    T.Free;
  end;
  T := NewTexture(PML_PIXELFORMAT_I444, PML_COLORSPACE_BT709_LIMITED, W, H);
  try
    T.UpdateYUV(TPMLRect.Make(0, 0, 0, 0), @Buf[0], Pitch, @Buf[Pitch * H], Pitch, @Buf[2 * Pitch * H], Pitch);
    Same(Format('T planar_pitch bt709l %d %d %s', [W, H, Hex(RenderHash(T, W, H))]));
  finally
    T.Free;
  end;
end;

{ 例外が出るか。SDL の側は '<場面> <文面>' か '<場面> ok'。 }
procedure ExpectRaise(const AName: String; ARaised: Boolean);
var
  I: Integer;
  Want: String;
begin
  Want := '(場面が無い)';
  for I := 0 to High(YUVHDExpected) do
    if Copy(YUVHDExpected[I], 1, Length(AName) + 3) = 'E ' + AName + ' ' then
      Want := Copy(YUVHDExpected[I], Length(AName) + 4, MaxInt);
  Check(ARaised = (Want <> 'ok'), AName + ' は' + BoolToStr(ARaised, '断る', '通る') + '（SDL: ' + Want + '）');
end;

procedure TestRefusals;
var
  T: TPMLTexture;
  Buf: array[0..399] of Byte;
  Raised: Boolean;
  P: Pointer;
  Pitch: Integer;
  Dst: array[0..399] of Byte;
begin
  WriteLn('4 断るもの');
  FillChar(Buf, SizeOf(Buf), 0);
  Raised := False;
  try
    T := NewTexture(PML_PIXELFORMAT_P010, PML_COLORSPACE_BT709_LIMITED, 8, 6);
    T.Free;
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  ExpectRaise('create_p010', Raised);

  T := NewTexture(PML_PIXELFORMAT_I444, PML_COLORSPACE_BT709_LIMITED, 8, 6);
  try
    Raised := False;
    try
      T.UpdateNV(TPMLRect.Make(0, 0, 0, 0), @Buf[0], 8, @Buf[0], 8);
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    ExpectRaise('nv_on_i444', Raised);
    Raised := False;
    try
      P := T.Lock(TPMLRect.Make(0, 0, 4, 4), Pitch);
      T.Unlock;
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    ExpectRaise('lock_partial', Raised);
  finally
    T.Free;
  end;

  T := NewTexture(PML_PIXELFORMAT_NV12, PML_COLORSPACE_BT709_LIMITED, 8, 6);
  try
    Raised := False;
    try
      T.UpdateYUV(TPMLRect.Make(0, 0, 0, 0), @Buf[0], 8, @Buf[0], 4, @Buf[0], 4);
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    ExpectRaise('yuv_on_nv12', Raised);
  finally
    T.Free;
  end;

  // 面での P010 -> XBGR2101010 は通る（SDL も通る）
  FillChar(Dst, SizeOf(Dst), 0);
  Raised := False;
  try
    PMLConvertP010ToXBGR2101010(4, 4, PML_COLORSPACE_BT709_LIMITED, @Buf[0], 8, @Dst[0], 16);
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  ExpectRaise('p010_to_xbgr', Raised);
end;

procedure TestExtras;
var
  Size: PtrUInt;
  Pitch: Integer;
  Buf: array[0..399] of Byte;
  Dst: array[0..399] of Byte;
  Raised: Boolean;
begin
  WriteLn('5 papimela の足した検査');
  Check(PMLIsYUVFormat(PML_PIXELFORMAT_I444), 'PMLIsYUVFormat は I444 を含む（肩代わりの層が扱える）');
  Check(not PMLIsYUVFormat(PML_PIXELFORMAT_P010), 'PMLIsYUVFormat は P010 を含まない（SDL のソフトウェアのレンダラも作れない）');
  Check(PMLIsYUVFormat(PML_PIXELFORMAT_IYUV) and PMLIsYUVFormat(PML_PIXELFORMAT_YUY2) and PMLIsYUVFormat(PML_PIXELFORMAT_NV21),
    '既存の 7 形式は変わらない');
  Check(not PMLIsYUVFormat(PML_PIXELFORMAT_ARGB8888), 'ARGB8888 は YUV でない');
  Check(not PMLCalculateYUVSize(PML_PIXELFORMAT_I0FL, 4, 4, Size, Pitch)
    and not PMLCalculateYUVSize(PML_PIXELFORMAT_I4FL, 4, 4, Size, Pitch),
    'I0FL / I4FL の大きさはまだ返さない（このユニットの範囲外）');

  FillChar(Buf, SizeOf(Buf), 0);
  FillChar(Dst, SizeOf(Dst), 0);
  Raised := False;
  try
    PMLConvertYUVToARGB8888(4, 4, PML_PIXELFORMAT_P010, PML_COLORSPACE_BT709_LIMITED, @Buf[0], 8, @Dst[0], 16);
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'P010 を ARGB8888 に直す道は無い（EPMLArgument）。P010 は XBGR2101010 だけ');
  Raised := False;
  try
    PMLConvertP010ToXBGR2101010(4, 4, PML_COLORSPACE_BT2020_LIMITED, @Buf[0], 8, @Dst[0], 16);
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'P010 の変換は、行列を選べない色空間（BT.2020 の限定範囲）を断る');
  Raised := False;
  try
    R.CreateTexture(PML_PIXELFORMAT_I444, TPMLTextureAccess.Streaming, 4, 4, PML_COLORSPACE_SRGB).Free;
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'I444 のテクスチャは、変換できない色空間を作るときに断る');
  Raised := False;
  try
    R.CreateTexture(PML_PIXELFORMAT_I444, TPMLTextureAccess.Target, 4, 4, PML_COLORSPACE_BT709_FULL).Free;
  except
    on E: EPMLArgument do
      Raised := True;
  end;
  Check(Raised, 'I444 は描画先にできない');
end;

begin
  WriteLn('=== test_yuv_hd ===');
  Target := TPMLSurface.Create(48, 8, PML_PIXELFORMAT_ARGB8888);
  R := TPMLRenderer.CreateSoftware(Target);
  try
    TestSizes;
    TestConvert;
    TestTexture;
    TestPitch;
    TestRefusals;
    TestExtras;
  finally
    FreeAndNil(R);
    FreeAndNil(Target);
  end;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: I444 と P010 の大きさ・変換・テクスチャが SDL と同じ値・絵・断り方になる ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
