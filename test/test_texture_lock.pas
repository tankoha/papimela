{
  test_texture_lock — テクスチャの Lock / Unlock / LockToSurface（SDL_LockTexture 系）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    SDL（参照版）のソフトウェアのレンダラに SDL_LockTexture などを通した結果（test/texture_lock_expected.inc。
    tools/texture-lock-expect/gen.bb が作る）と、papimela の結果を場面ごとに突き合わせる:
    返すピッチ、部分の Lock の位置、Unlock の後に描いた絵（ハッシュ）、エラー。
    1. RGB 系（ARGB8888・BGR24・RGB24・ABGR8888）の全体と部分。RGB565 は入れない（SDL の高速なブリット SDL_blit_N と papimela のブリットで、5・6 ビットの拡張の丸めが違う。HANDOFF §8）
    2. パックされた YUV（YUY2・UYVY・YVYU）の全体と部分
    3. 平面の YUV（IYUV・YV12・NV12・NV21）は全体の Lock だけ（部分は断る）
    4. INDEX8（パレット）の全体と部分。ドライバが持つ場合（直接）と、持たない場合（肩代わり）
    5. LockToSurface: 切り取り、サーフェスの大きさ・ピッチ・形式、パレット
    6. 静的・描画先のテクスチャは Lock できない。二重の Lock と、Lock せずの Unlock
    7. papimela の足した検査: 矩形がテクスチャの外、描画の最中の Lock、レンダラが先に消えた後

  WHY:
    §3 の 2（テクスチャの Lock / Unlock）の受け入れ検査。表示サーバは要らない。GPU のドライバの分は
    test_render_gles2 のオフスクリーンの節にある。

  SDL との違い（意図したもの）:
    - 矩形がテクスチャの外なら EPMLArgument（SDL は確かめず、置き場の外を指す）
    - YUV のテクスチャはサーフェスにできない（SDL は YUV のサーフェスを作れる）
    - エラーの文面は種類で比べる（SDL の関数名は付けない）
}
program test_texture_lock;

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

{$I texture_lock_expected.inc}

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

{ ---- SDL の側と同じ部品 ---- }

var
  Lcg: LongWord = 1;
  // YUV の値は範囲の内側（96..159）に収める（D-62。SDL のスカラー版は範囲の外を回り込み、papimela は飽和させる）
  YuvSafe: Boolean = False;

function Nx: Byte;
begin
  Lcg := Lcg * 1103515245 + 12345;
  Result := Byte(Lcg shr 16);
  if YuvSafe then
    Result := 96 + (Result and 63);
end;

procedure Fill(P: PByte; APitch, ARowBytes, ARows: Integer; ASeed: LongWord);
var
  X, Y: Integer;
begin
  Lcg := ASeed;
  for Y := 0 to ARows - 1 do
    for X := 0 to ARowBytes - 1 do
      P[Y * APitch + X] := Nx;
end;

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

type
  TKind = (Direct, Fallback);

  { INDEX8 を持てないドライバ。肩代わりの層を通すための検査用。 }
  TNoIndexDriver = class(TPMLSoftwareRenderDriver)
  public
    function SupportsTextureFormat(AFormat: TPMLPixelFormat): Boolean; override;
  end;

function TNoIndexDriver.SupportsTextureFormat(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := inherited SupportsTextureFormat(AFormat) and not PMLIsPixelFormatIndexed(AFormat);
end;

var
  Target: TPMLSurface;
  R: TPMLRenderer;

procedure NewRenderer(AKind: TKind);
begin
  FreeAndNil(R);
  FreeAndNil(Target);
  Target := TPMLSurface.Create(8, 8, PML_PIXELFORMAT_ARGB8888);
  if AKind = TKind.Direct then
    R := TPMLRenderer.CreateSoftware(Target)
  else
    R := TPMLRenderer.Create(TNoIndexDriver.Create(Target));
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

{ 文面は種類で比べる。 }
function Kind(const S: String): String;
begin
  if Pos('must be streaming', S) > 0 then
    Result := 'not streaming'
  else if Pos('full surface locks', S) > 0 then
    Result := 'full lock only'
  else if (Pos('is invalid', S) > 0) or (Pos('does not overlap', S) > 0) then
    Result := 'empty rect'
  else if Pos('Unsupported YUV', S) > 0 then
    Result := 'unsupported yuv'
  else
    Result := S;
end;

function Expected(const AName: String): String;
var
  I: Integer;
  S: String;
begin
  for I := 0 to High(LockExpected) do
  begin
    S := LockExpected[I];
    if (Copy(S, 1, Length(AName) + 1) = AName + ' ') then
    begin
      Result := S;
      // エラーの文面を種類にする
      if Pos(' err ', S) > 0 then
        Result := Copy(S, 1, Pos(' err ', S) + 4) + Kind(Copy(S, Pos(' err ', S) + 5, MaxInt));
      Exit;
    end;
  end;
  Result := '(場面が無い)';
end;

procedure Same(const AName, AGot: String);
var
  Want: String;
begin
  Want := Expected(AName);
  Check(AGot = Want, AName + ': ' + AGot + ' (SDL: ' + Want + ')');
end;

{ ---- 場面 ---- }

procedure SceneRgb(const AName: String; AFormat: TPMLPixelFormat; AW, AH, ABpp: Integer;
  ARect: TPMLRect);
var
  T: TPMLTexture;
  Full, P: PByte;
  Pitch, FullPitch: Integer;
  RW, RH: Integer;
begin
  T := R.CreateTexture(AFormat, TPMLTextureAccess.Streaming, AW, AH);
  try
    T.BlendMode := TPMLBlendMode.None;   // 合成の丸めは SDL と 1 違う（D-44）ので、写すだけにする
    YuvSafe := (AFormat = PML_PIXELFORMAT_YUY2) or (AFormat = PML_PIXELFORMAT_UYVY) or (AFormat = PML_PIXELFORMAT_YVYU);
    P := T.Lock(TPMLRect.Make(0, 0, 0, 0), Pitch);
    Fill(P, Pitch, AW * ABpp, AH, 7);
    T.Unlock;
    Full := T.Lock(TPMLRect.Make(0, 0, 0, 0), FullPitch);
    T.Unlock;
    P := T.Lock(ARect, Pitch);
    if ARect.IsEmpty then
    begin
      RW := AW;
      RH := AH;
    end
    else
    begin
      RW := ARect.W;
      RH := ARect.H;
    end;
    Fill(P, Pitch, RW * ABpp, RH, 99);
    T.Unlock;
    Same(AName, Format('%s ok %d %d %.8X', [AName, Pitch, P - Full, RenderHash(T, AW, AH)]));
  finally
    YuvSafe := False;
    T.Free;
  end;
end;

procedure SceneErrors;
var
  T: TPMLTexture;
  Raised: Boolean;
  Msg: String;
  P: Pointer;
  Pitch: Integer;
  S: TPMLSurface;
begin
  T := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Static, 4, 4);
  try
    Raised := False;
    Msg := '';
    try
      P := T.Lock(TPMLRect.Make(0, 0, 0, 0), Pitch);
    except
      on E: EPMLArgument do
      begin
        Raised := True;
        Msg := E.Message;
      end;
    end;
    if Raised then
      Same('static_lock', 'static_lock err ' + Kind(Msg))
    else
      Same('static_lock', 'static_lock ok');
    T.Unlock;
    Same('static_unlock', 'static_unlock ok');
    Raised := False;
    Msg := '';
    try
      S := T.LockToSurface(TPMLRect.Make(0, 0, 0, 0));
    except
      on E: EPMLArgument do
      begin
        Raised := True;
        Msg := E.Message;
      end;
    end;
    if Raised then
      Same('tosurf_static', 'tosurf_static err ' + Kind(Msg))
    else
      Same('tosurf_static', 'tosurf_static ok');
  finally
    T.Free;
  end;
  T := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Target, 4, 4);
  try
    Raised := False;
    Msg := '';
    try
      P := T.Lock(TPMLRect.Make(0, 0, 0, 0), Pitch);
    except
      on E: EPMLArgument do
      begin
        Raised := True;
        Msg := E.Message;
      end;
    end;
    if Raised then
      Same('target_lock', 'target_lock err ' + Kind(Msg))
    else
      Same('target_lock', 'target_lock ok');
  finally
    T.Free;
  end;
end;

procedure ScenePlanar(const AName: String; AFormat: TPMLPixelFormat);
var
  T: TPMLTexture;
  P: PByte;
  Pitch: Integer;
  Raised: Boolean;
  Msg: String;
begin
  T := R.CreateTexture(AFormat, TPMLTextureAccess.Streaming, 6, 4);
  YuvSafe := True;
  try
    P := T.Lock(TPMLRect.Make(0, 0, 0, 0), Pitch);
    Fill(P, 0, 36, 1, 21);
    T.Unlock;
    Same(AName + '_full', Format('%s_full ok %d 0 %.8X', [AName, Pitch, RenderHash(T, 6, 4)]));
    Raised := False;
    Msg := '';
    try
      T.Lock(TPMLRect.Make(0, 0, 4, 4), Pitch);
      T.Unlock;
    except
      on E: EPMLArgument do
      begin
        Raised := True;
        Msg := E.Message;
      end;
    end;
    if Raised then
      Same(AName + '_partial', AName + '_partial err ' + Kind(Msg))
    else
      Same(AName + '_partial', AName + '_partial ok');
    P := T.Lock(TPMLRect.Make(0, 0, 6, 4), Pitch);
    T.Unlock;
    Same(AName + '_fullrect', Format('%s_fullrect ok %d', [AName, Pitch]));
  finally
    YuvSafe := False;
    T.Free;
  end;
end;

function NewPalette256: TPMLPalette;
var
  Colors: array[0..255] of TPMLColor;
  I: Integer;
begin
  for I := 0 to 255 do
    Colors[I] := TPMLColor.Make(Byte(I * 3), Byte(255 - I), Byte(I * 7), 255);
  Result := TPMLPalette.Create(nil, nil, 256);
  Result.SetColors(Colors);
end;

procedure SceneIndex8;
var
  T: TPMLTexture;
  Pal: TPMLPalette;
  Full, P: PByte;
  Pitch, FullPitch: Integer;
begin
  Pal := NewPalette256;
  T := R.CreateTexture(PML_PIXELFORMAT_INDEX8, TPMLTextureAccess.Streaming, 6, 4);
  try
    T.SetPalette(Pal);
    Full := T.Lock(TPMLRect.Make(0, 0, 0, 0), FullPitch);
    Fill(Full, FullPitch, 6, 4, 5);
    T.Unlock;
    Same('index8_full', Format('index8_full ok %d 0 %.8X', [FullPitch, RenderHash(T, 6, 4)]));
    P := T.Lock(TPMLRect.Make(2, 1, 3, 2), Pitch);
    Same('index8_rect_pos', Format('index8_rect_pos %d %d', [Pitch, P - Full]));
    Fill(P, Pitch, 3, 2, 77);
    T.Unlock;
    Same('index8_rect', Format('index8_rect ok %d %.8X', [Pitch, RenderHash(T, 6, 4)]));
  finally
    T.Free;
    Pal.Free;
  end;
end;

procedure SceneToSurface;
var
  T, TI, TY: TPMLTexture;
  Full: PByte;
  FullPitch, Y: Integer;
  S: TPMLSurface;
  Pal: TPMLPalette;
  Raised: Boolean;
  Msg: String;
begin
  T := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Streaming, 6, 5);
  try
    T.BlendMode := TPMLBlendMode.None;
    Full := T.Lock(TPMLRect.Make(0, 0, 0, 0), FullPitch);
    Fill(Full, FullPitch, 24, 5, 7);
    T.Unlock;
    Full := T.Lock(TPMLRect.Make(0, 0, 0, 0), FullPitch);
    T.Unlock;
    S := T.LockToSurface(TPMLRect.Make(1, 1, 3, 2));
    Same('tosurf_rect', Format('tosurf_rect %d %d %d %d %d', [S.Width, S.Height, S.Pitch, S.Format,
      PByte(S.Pixels) - Full]));
    for Y := 0 to S.Height - 1 do
      FillChar((PByte(S.Pixels) + Y * S.Pitch)^, S.Width * 4, $7F);
    T.Unlock;
    Same('tosurf_rect_hash', Format('tosurf_rect_hash %.8X', [RenderHash(T, 6, 5)]));
    S := T.LockToSurface(TPMLRect.Make(-1, -1, 4, 4));
    Same('tosurf_clip', Format('tosurf_clip %d %d %d', [S.Width, S.Height, PByte(S.Pixels) - Full]));
    T.Unlock;
    S := T.LockToSurface(TPMLRect.Make(0, 0, 0, 0));
    Same('tosurf_full', Format('tosurf_full %d %d %d', [S.Width, S.Height, S.Pitch]));
    T.Unlock;
    Raised := False;
    Msg := '';
    try
      T.LockToSurface(TPMLRect.Make(10, 10, 2, 2));
    except
      on E: EPMLArgument do
      begin
        Raised := True;
        Msg := E.Message;
      end;
    end;
    if Raised then
      Same('tosurf_outside', 'tosurf_outside err ' + Kind(Msg))
    else
      Same('tosurf_outside', 'tosurf_outside ok');
  finally
    T.Free;
  end;
  // インデックス形式: サーフェスはテクスチャのパレットを持つ
  Pal := TPMLPalette.Create(nil, nil, 16);
  TI := R.CreateTexture(PML_PIXELFORMAT_INDEX8, TPMLTextureAccess.Streaming, 4, 4);
  try
    TI.SetPalette(Pal);
    S := TI.LockToSurface(TPMLRect.Make(0, 0, 0, 0));
    Same('tosurf_index8', Format('tosurf_index8 %d %d %d palette=%d', [S.Width, S.Height, S.Pitch,
      Ord(S.Palette = Pal)]));
    TI.Unlock;
  finally
    TI.Free;
    Pal.Free;
  end;
  // YUV はサーフェスにできない（SDL はできる。意図した違い）
  TY := R.CreateTexture(PML_PIXELFORMAT_IYUV, TPMLTextureAccess.Streaming, 4, 4);
  try
    Raised := False;
    try
      TY.LockToSurface(TPMLRect.Make(0, 0, 0, 0));
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    Check(Raised, 'tosurf_iyuv: YUV のテクスチャはサーフェスにできない（EPMLArgument。SDL は ok 4 4 4）');
  finally
    TY.Free;
  end;
end;

procedure SceneDouble;
var
  T: TPMLTexture;
  A, B: Pointer;
  PA, PB: Integer;
begin
  T := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Streaming, 4, 4);
  try
    A := T.Lock(TPMLRect.Make(0, 0, 0, 0), PA);
    B := T.Lock(TPMLRect.Make(0, 0, 0, 0), PB);
    Same('double_lock', Format('double_lock %d %d', [Ord(A = B), Ord(PA = PB)]));
    T.Unlock;
    T.Unlock;
    Same('double_unlock', 'double_unlock ok');
  finally
    T.Free;
  end;
end;

{ papimela の足した検査。 }
procedure SceneExtras;
var
  T: TPMLTexture;
  P: PByte;
  Pitch: Integer;
  Raised: Boolean;
  Hash1, Hash2: LongWord;
  I: Integer;
begin
  T := R.CreateTexture(PML_PIXELFORMAT_ARGB8888, TPMLTextureAccess.Streaming, 4, 4);
  try
    // 矩形が外に出る
    Raised := False;
    try
      T.Lock(TPMLRect.Make(2, 2, 4, 4), Pitch);
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    Check(Raised, '矩形がテクスチャの外に出るのは EPMLArgument');
    Raised := False;
    try
      T.Lock(TPMLRect.Make(-1, 0, 2, 2), Pitch);
    except
      on E: EPMLArgument do
        Raised := True;
    end;
    Check(Raised, '矩形の左が負なのも EPMLArgument');

    // 描画を積んだまま Lock しても、積んだ描画は Lock の前の中身で描かれる（先に吐き出す）
    P := T.Lock(TPMLRect.Make(0, 0, 0, 0), Pitch);
    for I := 0 to 15 do
      PLongWord(P)[I] := $FFFF0000;
    T.Unlock;
    R.DrawColor := TPMLColor.Make(0, 0, 0, 255);
    R.Clear;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 4, 4));
    P := T.Lock(TPMLRect.Make(0, 0, 0, 0), Pitch);
    for I := 0 to 15 do
      PLongWord(P)[I] := $FF00FF00;
    T.Unlock;
    R.Present;
    Hash1 := Target.ReadRaw(0, 0);
    Check(Hash1 = $FFFF0000, Format('積んだ描画は Lock の前の赤で描かれる（%.8X）', [Hash1]));
    R.DrawColor := TPMLColor.Make(0, 0, 0, 255);
    R.Clear;
    R.RenderTexture(T, TPMLFRect.Make(0, 0, 0, 0), TPMLFRect.Make(0, 0, 4, 4));
    R.Present;
    Hash2 := Target.ReadRaw(0, 0);
    Check(Hash2 = $FF00FF00, Format('Unlock の後に積んだ描画は緑で描かれる（%.8X）', [Hash2]));
  finally
    T.Free;
  end;
end;

procedure RunKind(AKind: TKind);
begin
  NewRenderer(AKind);
  SceneRgb('argb_full', PML_PIXELFORMAT_ARGB8888, 6, 5, 4, TPMLRect.Make(0, 0, 0, 0));
  SceneRgb('argb_rect', PML_PIXELFORMAT_ARGB8888, 6, 5, 4, TPMLRect.Make(1, 2, 3, 2));
  SceneRgb('argb_corner', PML_PIXELFORMAT_ARGB8888, 6, 5, 4, TPMLRect.Make(5, 4, 1, 1));
  SceneRgb('bgr24_rect', PML_PIXELFORMAT_BGR24, 6, 5, 3, TPMLRect.Make(1, 2, 3, 2));
  SceneRgb('rgb24_full', PML_PIXELFORMAT_RGB24, 5, 3, 3, TPMLRect.Make(0, 0, 0, 0));
  SceneRgb('abgr8888_rect', PML_PIXELFORMAT_ABGR8888, 6, 5, 4, TPMLRect.Make(1, 2, 3, 2));
  SceneRgb('yuy2_rect', PML_PIXELFORMAT_YUY2, 6, 4, 2, TPMLRect.Make(2, 1, 2, 2));
  SceneRgb('uyvy_full', PML_PIXELFORMAT_UYVY, 6, 4, 2, TPMLRect.Make(0, 0, 0, 0));
  SceneRgb('yvyu_rect', PML_PIXELFORMAT_YVYU, 6, 4, 2, TPMLRect.Make(4, 2, 2, 1));
  SceneErrors;
  ScenePlanar('iyuv', PML_PIXELFORMAT_IYUV);
  ScenePlanar('yv12', PML_PIXELFORMAT_YV12);
  ScenePlanar('nv12', PML_PIXELFORMAT_NV12);
  ScenePlanar('nv21', PML_PIXELFORMAT_NV21);
  SceneIndex8;
  SceneToSurface;
  SceneDouble;
  SceneExtras;
end;

begin
  WriteLn('=== test_texture_lock ===');
  WriteLn('-- ドライバが INDEX8 を直接持つレンダラ');
  RunKind(TKind.Direct);
  WriteLn('-- INDEX8 を持たないレンダラ（肩代わりの層）');
  RunKind(TKind.Fallback);
  FreeAndNil(R);
  FreeAndNil(Target);
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: Lock / Unlock / LockToSurface が SDL と同じ絵・ピッチ・位置・エラーになる ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
