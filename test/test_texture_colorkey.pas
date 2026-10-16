{
  test_texture_colorkey — サーフェスからテクスチャを作るときのカラーキー・変調・ブレンド（SDL_CreateTextureFromSurface）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    SDL（参照版）のソフトウェアのレンダラに SDL_CreateTextureFromSurface を通した結果
    （test/texture_colorkey_expected.inc。tools/texture-colorkey-expect/gen.bb が作る）と、papimela の結果を
    場面ごとに突き合わせる: テクスチャの形式、ブレンドモード、色の変調、アルファの変調、
    描いた絵（ハッシュ。テクスチャのブレンドのままと、ブレンド無しの 2 通り）。
    1. 17 の形式（8888 の各並び・24 ビット・565・4444・1555・332・INDEX8）の、カラーキー無しと有り
    2. 変調（色・アルファ。合成を通した絵は丸めが SDL と 1 違うので D-44、ブレンド無しの絵で比べる）とブレンドモード（ADD・MOD）の引き継ぎ。カラーキーがあれば Blend に上書きされる
    3. アルファのあるサーフェスのカラーキー（キーと RGB が同じなら、元のアルファに関わらず透明にする）

  WHY:
    §3 の 2（カラーキー）の受け入れ検査。表示サーバは要らない。

  SDL との違い（意図したもの）:
    - サーフェスの既定のブレンドモードは、papimela では None（SDL はアルファのある形式なら Blend）。
      テクスチャを作るときは、BlendMode を一度も書いていないサーフェスを SDL と同じに扱う
      （BlendModeAssigned）。
}
program test_texture_colorkey;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Render,
  PaPiMeLa.Render.Software;

{$I texture_colorkey_expected.inc}

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

var
  Target: TPMLSurface;
  R: TPMLRenderer;

function Fnv(P: PByte; ALen: Integer): LongWord;
var
  I: Integer;
begin
  Result := 2166136261;
  for I := 0 to ALen - 1 do
  begin
    Result := Result xor P[I];
    Result := Result * 16777619;
  end;
end;

{ 描いた絵のハッシュ（SDL の側の render_hash と同じ）。 }
function RenderHash(T: TPMLTexture; AW, AH: Integer): LongWord;
var
  Y: Integer;
begin
  R.DrawColor := TPMLColor.Make(10, 20, 30, 255);
  R.Clear;
  R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, AW, AH));
  R.Present;
  Result := 2166136261;
  for Y := 0 to Target.Height - 1 do
    Result := Fnv(PByte(Target.Pixels) + Y * Target.Pitch, Target.Width * 4) xor (Result * 16777619);
end;

{ 形式は「アルファがあるか」で比べる。SDL のソフトウェアのレンダラは ARGB8888 と XRGB8888 しか持たず、
  ほかの形式を肩代わりするが、papimela のドライバは RGB 系を直接持つ。カラーキーが決めるのはアルファの有無。 }
function FormatClass(const AName: String; AFormat: TPMLPixelFormat): String;
var
  D: TPMLPixelFormatDetails;
begin
  if Pos('_key', AName) = 0 then
    Exit('-');
  if PMLIsPixelFormatIndexed(AFormat) then
    Exit('INDEX8');
  PMLGetPixelFormatDetails(AFormat, D);
  if D.HasAlpha then
    Result := 'alpha'
  else
    Result := 'opaque';
end;

function Expected(const AName: String): String;
var
  I: Integer;
  P: Integer;
begin
  // _key の場面だけ形式の種類を比べる。ほかの場面はドライバの対応形式の違いなので比べない。
  for I := 0 to High(ColorKeyExpected) do
    if Copy(ColorKeyExpected[I], 1, Length(AName) + 1) = AName + ' ' then
    begin
      Result := ColorKeyExpected[I];
      P := Pos(' ', Result);
      if Pos('_key', AName) = 0 then
        Result := Copy(Result, 1, P) + '-' + Copy(Result, Pos(' blend=', Result), MaxInt)
      else if Copy(Result, P + 1, 4) = 'ARGB' then
        Result := Copy(Result, 1, P) + 'alpha' + Copy(Result, Pos(' blend=', Result), MaxInt)
      else if Copy(Result, P + 1, 4) = 'XRGB' then
        Result := Copy(Result, 1, P) + 'opaque' + Copy(Result, Pos(' blend=', Result), MaxInt);
      Exit;
    end;
  Result := '(場面が無い)';
end;

function BlendNumber(AMode: TPMLBlendMode): Integer;
begin
  case AMode of
    TPMLBlendMode.None:     Result := 0;
    TPMLBlendMode.Blend:    Result := 1;
    TPMLBlendMode.Add:      Result := 2;
    TPMLBlendMode.Modulate: Result := 4;
    TPMLBlendMode.Multiply: Result := 8;
  else
    Result := -1;
  end;
end;

{ サーフェスからテクスチャを作り、SDL の側の emit と同じ行にして突き合わせる。 }
procedure Emit(const AName: String; S: TPMLSurface; ARoundsDiffer: Boolean = False);
var
  T: TPMLTexture;
  H1, H2: LongWord;
  Props, Got, Want: String;
begin
  T := R.CreateTextureFromSurface(S);
  try
    Props := Format('%s blend=%d cmod=%d,%d,%d amod=%d', [FormatClass(AName, T.Format),
      BlendNumber(T.BlendMode), T.ColorMod.R, T.ColorMod.G, T.ColorMod.B, T.AlphaMod]);
    H1 := RenderHash(T, 4, 3);
    T.BlendMode := TPMLBlendMode.None;
    H2 := RenderHash(T, 4, 3);
    Got := Format('%s %s %.8X %.8X', [AName, Props, H1, H2]);
  finally
    T.Free;
  end;
  Want := Expected(AName);
  if ARoundsDiffer then
  begin
    // 変調つきの合成は、丸めが SDL と 1 違う（D-44）。ブレンド無しの絵は比べる。
    Got := Copy(Got, 1, Length(Got) - 17) + Copy(Got, Length(Got) - 7, 8);
    Want := Copy(Want, 1, Length(Want) - 17) + Copy(Want, Length(Want) - 7, 8);
  end;
  Check(Got = Want, Got + ' (SDL: ' + Want + ')');
end;

const
  Cols: array[0..3] of TPMLColor = (
    (R: 255; G: 0; B: 0; A: 255), (R: 0; G: 255; B: 0; A: 255),
    (R: 0; G: 0; B: 255; A: 255), (R: 255; G: 255; B: 0; A: 255));

{ 4x3 の絵。画素 (x, y) は色 (x + y) mod 4。INDEX8 はパレット。 }
function MakeSurface(AFormat: TPMLPixelFormat): TPMLSurface;
var
  X, Y: Integer;
  Pal: TPMLPalette;
begin
  Result := TPMLSurface.Create(4, 3, AFormat);
  if PMLIsPixelFormatIndexed(AFormat) then
  begin
    Pal := TPMLPalette.Create(nil, nil, 4);
    for X := 0 to 3 do
      Pal[X] := Cols[X];
    Result.SetPalette(Pal, True);
    for Y := 0 to 2 do
      for X := 0 to 3 do
        PByte(Result.Pixels)[Y * Result.Pitch + X] := (X + Y) mod 4;
  end
  else
    for Y := 0 to 2 do
      for X := 0 to 3 do
        Result.WritePixel(X, Y, Cols[(X + Y) mod 4]);
end;

type
  TFmt = record
    Name: String;
    Format: TPMLPixelFormat;
  end;

const
  Fmts: array[0..16] of TFmt = (
    (Name: 'argb8888'; Format: PML_PIXELFORMAT_ARGB8888), (Name: 'xrgb8888'; Format: PML_PIXELFORMAT_XRGB8888),
    (Name: 'abgr8888'; Format: PML_PIXELFORMAT_ABGR8888), (Name: 'xbgr8888'; Format: PML_PIXELFORMAT_XBGR8888),
    (Name: 'bgra8888'; Format: PML_PIXELFORMAT_BGRA8888), (Name: 'bgrx8888'; Format: PML_PIXELFORMAT_BGRX8888),
    (Name: 'rgba8888'; Format: PML_PIXELFORMAT_RGBA8888), (Name: 'rgbx8888'; Format: PML_PIXELFORMAT_RGBX8888),
    (Name: 'rgb24'; Format: PML_PIXELFORMAT_RGB24), (Name: 'bgr24'; Format: PML_PIXELFORMAT_BGR24),
    (Name: 'rgb565'; Format: PML_PIXELFORMAT_RGB565), (Name: 'argb4444'; Format: PML_PIXELFORMAT_ARGB4444),
    (Name: 'xrgb4444'; Format: PML_PIXELFORMAT_XRGB4444), (Name: 'argb1555'; Format: PML_PIXELFORMAT_ARGB1555),
    (Name: 'xrgb1555'; Format: PML_PIXELFORMAT_XRGB1555), (Name: 'rgb332'; Format: PML_PIXELFORMAT_RGB332),
    (Name: 'index8'; Format: PML_PIXELFORMAT_INDEX8));

var
  S: TPMLSurface;
  I: Integer;
  Key: LongWord;
begin
  Target := TPMLSurface.Create(8, 8, PML_PIXELFORMAT_ARGB8888);
  R := TPMLRenderer.CreateSoftware(Target);
  try
    WriteLn('--- 17 の形式（カラーキー無しと有り）');
    for I := 0 to High(Fmts) do
    begin
      S := MakeSurface(Fmts[I].Format);
      try
        Emit(Fmts[I].Name + '_plain', S);
        if PMLIsPixelFormatIndexed(Fmts[I].Format) then
          Key := 0
        else
          Key := S.MapColor(TPMLColor.Make(255, 0, 0, 255));
        S.SetColorKey(True, Key);
        Emit(Fmts[I].Name + '_key', S);
      finally
        S.Free;
      end;
    end;

    WriteLn('--- 変調とブレンドモードの引き継ぎ');
    S := MakeSurface(PML_PIXELFORMAT_XRGB8888);
    try
      S.ColorMod := TPMLColor.Make(200, 150, 100);
      S.AlphaMod := 128;
      S.BlendMode := TPMLBlendMode.Add;
      Emit('xrgb8888_mods_add', S);
      S.SetColorKey(True, S.MapColor(TPMLColor.Make(255, 0, 0, 255)));
      Emit('xrgb8888_mods_add_key', S, True);
    finally
      S.Free;
    end;
    S := MakeSurface(PML_PIXELFORMAT_ARGB8888);
    try
      S.BlendMode := TPMLBlendMode.None;
      Emit('argb8888_blend_none', S);
      S.BlendMode := TPMLBlendMode.Modulate;
      S.ColorMod := TPMLColor.Make(90, 200, 255);
      Emit('argb8888_blend_mod', S, True);
    finally
      S.Free;
    end;
    S := MakeSurface(PML_PIXELFORMAT_RGB24);
    try
      Emit('rgb24_default', S);
      S.BlendMode := TPMLBlendMode.Blend;
      Emit('rgb24_blend', S);
    finally
      S.Free;
    end;

    WriteLn('--- アルファのあるサーフェスのカラーキー');
    S := MakeSurface(PML_PIXELFORMAT_ARGB8888);
    try
      S.WritePixel(1, 0, TPMLColor.Make(255, 0, 0, 100));
      S.SetColorKey(True, S.MapColor(TPMLColor.Make(255, 0, 0, 255)));
      Emit('argb8888_key_alpha_differs', S);
    finally
      S.Free;
    end;
  finally
    R.Free;
    Target.Free;
  end;

  WriteLn;
  if Failures = 0 then
    WriteLn('All tests passed.')
  else
  begin
    WriteLn(Failures, ' test(s) FAILED.');
    Halt(1);
  end;
end.
