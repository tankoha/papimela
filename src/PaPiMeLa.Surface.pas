{
  PaPiMeLa.Surface — CPU 上のピクセル面

  Origin : ported from SDL (src/video/SDL_surface.c)
           Scope: サーフェスの所有モデル（ピクセルを自前で持つか借りるか）、
           クリップ矩形の交差規則、カラーキーと変換の扱い。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.4、§11 #28

  WHAT:
    幅・高さ・ピッチ・形式を持つピクセルの矩形と、それに対する読み書き・
    複製・形式変換・反転。

  WHY:
    テクスチャやウィンドウへ上げる前の画像はここに置く。BMP の読み込み先でも
    あり、ソフトウェアレンダラの描画先でもある。

  RESOLVED:
    - ピクセルは自前で確保するか、外から借りるかのどちらか。借りている間は
      解放しない（OwnsPixels が False）
    - ピッチは 4 バイト境界へ切り上げる。SDL と同じで、行の先頭を揃えた方が
      後段のブリッタが書きやすい
    - 共有は COM インターフェース IPMLSurface で opt-in する（§8.4）。
      CreateShared で作ったものだけが参照カウントで生き、_Release で消える。
      既定の TPMLSurface は参照カウントしない

  NOT RESOLVED:
    - ブリット（Blit / BlitScaled / FillRect / Flip の高速版）は第 11 章 #29。
      ここにある Convert は 1 画素ずつ回す素直な実装で、速度は #29 が担当する
    - RLE 圧縮（SDL_RLEaccel.c）は未実装。MustLock は常に False を返す
    - 色空間（Colorspace）と PremultiplyAlpha は未実装

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Surface;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Pixels;

type
  TPMLSurface = class;

  { 共有の opt-in（§8.4）。

    papimela の既定は参照カウント無しだが、サーフェスだけは複数の持ち主が
    同じピクセルを見たい場面がある（テクスチャ生成とファイル保存など）。
    CreateShared で作ったものは、この窓口を通す限り最後の参照が消えたときに
    自動で解放される。 }
  IPMLSurface = interface(IInterface)
    ['{6D3F1A82-59C4-4E07-B1D8-3A7E2F49C605}']
    function GetSurface: TPMLSurface;
    property Surface: TPMLSurface read GetSurface;
  end;

  TPMLFlipMode = (None, Horizontal, Vertical);

  TPMLSurface = class(TPMLOwnedObject, IPMLSurface)
  strict private
    FFormat    : TPMLPixelFormat;
    FDetails   : TPMLPixelFormatDetails;
    FWidth     : Integer;
    FHeight    : Integer;
    FPitch     : Integer;
    FPixels    : Pointer;
    FOwnsPixels: Boolean;
    FPalette   : TPMLPalette;
    FOwnsPalette: Boolean;
    FClipRect  : TPMLRect;
    FColorKey  : LongWord;
    FHasColorKey: Boolean;
    FColorMod  : TPMLColor;
    FAlphaMod  : Byte;
    FBlendMode : TPMLBlendMode;
    FLockCount : Integer;
    // 共有（CreateShared）で生成したときだけ 0 以上になる。-1 = 共有しない。
    FRefCount  : LongInt;

    function  GetPixelAddr(AX, AY: Integer): Pointer; inline;
    procedure SetClipRect(const AValue: TPMLRect);
    function  GetMustLock: Boolean;
  protected
    // IInterface。FRefCount が -1 のもの（既定）は参照カウントしない。
    function QueryInterface(constref AIID: TGUID; out AObj): HResult; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function _AddRef: LongInt; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function _Release: LongInt; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function GetSurface: TPMLSurface;
  public
    { 新しいピクセルを確保する。中身は 0 で埋める。 }
    constructor Create(AWidth, AHeight: Integer; AFormat: TPMLPixelFormat);
    { 既存のピクセルを借りる。解放しない。APitch が 0 なら幅から算出する。 }
    constructor CreateFrom(APixels: Pointer; AWidth, AHeight, APitch: Integer;
      AFormat: TPMLPixelFormat);
    { 参照カウントで共有できるサーフェスを作る。戻り値の参照が最後に消えたとき
      に解放される。TPMLSurface としては Free してはならない。 }
    class function CreateShared(AWidth, AHeight: Integer;
      AFormat: TPMLPixelFormat): IPMLSurface;
    destructor Destroy; override;

    // RLE が入るまで常に False。呼んでも害はない。
    procedure Lock;
    procedure Unlock;

    // 範囲外は無視する（読み取りは黒、書き込みは何もしない）。
    function  ReadPixel(AX, AY: Integer): TPMLColor;
    procedure WritePixel(AX, AY: Integer; const AColor: TPMLColor);
    // 生の画素値。形式を知っている呼び出し側向け。
    function  ReadRaw(AX, AY: Integer): LongWord;
    procedure WriteRaw(AX, AY: Integer; AValue: LongWord);

    function  MapRGBA(AR, AG, AB, AA: Byte): LongWord;
    function  MapColor(const AColor: TPMLColor): LongWord;

    // 矩形をひとつの色で埋める。クリップ矩形と交差した範囲だけ書く。
    procedure FillRect(const ARect: TPMLRect; const AColor: TPMLColor);
    procedure Fill(const AColor: TPMLColor);

    // 同じ内容の新しいサーフェスを返す。呼び出し側が Free する。
    function  Duplicate: TPMLSurface;
    // 別の形式へ変換した新しいサーフェスを返す。呼び出し側が Free する。
    function  Convert(AFormat: TPMLPixelFormat): TPMLSurface;
    // その場で反転する。
    procedure Flip(AMode: TPMLFlipMode);

    // パレットを差し替える。AOwned なら破棄時に一緒に解放する。
    procedure SetPalette(APalette: TPMLPalette; AOwned: Boolean);

    procedure SetColorKey(AEnabled: Boolean; AKey: LongWord);
    function  HasColorKey: Boolean;

    property Format   : TPMLPixelFormat read FFormat;
    property Details  : TPMLPixelFormatDetails read FDetails;
    property Width    : Integer read FWidth;
    property Height   : Integer read FHeight;
    property Pitch    : Integer read FPitch;
    property Pixels   : Pointer read FPixels;
    property OwnsPixels: Boolean read FOwnsPixels;
    property Palette  : TPMLPalette read FPalette;
    property ClipRect : TPMLRect read FClipRect write SetClipRect;
    property ColorKey : LongWord read FColorKey;
    property ColorMod : TPMLColor read FColorMod write FColorMod;
    property AlphaMod : Byte read FAlphaMod write FAlphaMod;
    property BlendMode: TPMLBlendMode read FBlendMode write FBlendMode;
    property MustLock : Boolean read GetMustLock;
  end;

// 幅と形式から 4 バイト境界へ切り上げたピッチを返す。
function PMLPitchFor(AWidth: Integer; AFormat: TPMLPixelFormat): Integer;

implementation

function PMLPitchFor(AWidth: Integer; AFormat: TPMLPixelFormat): Integer;
var
  Bpp: Integer;
begin
  if AWidth <= 0 then
    Exit(0);
  Bpp := PMLBytesPerPixel(AFormat);
  if Bpp <= 0 then
    Bpp := 1;
  Result := AWidth * Bpp;
  // 4 バイト境界へ切り上げる。行の先頭が揃っている方がブリッタが書きやすい。
  Result := (Result + 3) and not 3;
end;

{ TPMLSurface }

constructor TPMLSurface.Create(AWidth, AHeight: Integer; AFormat: TPMLPixelFormat);
var
  Bytes: PtrUInt;
begin
  inherited Create(nil, nil);
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EPMLArgument.CreateFmt('surface size must be positive (%d x %d)',
      [AWidth, AHeight]);
  FFormat := AFormat;
  PMLGetPixelFormatDetails(AFormat, FDetails);
  if FDetails.BytesPerPixel = 0 then
    raise EPMLUnsupported.CreateFmt('pixel format %s cannot back a surface',
      [PMLPixelFormatName(AFormat)]);

  FWidth := AWidth;
  FHeight := AHeight;
  FPitch := PMLPitchFor(AWidth, AFormat);
  Bytes := PtrUInt(FPitch) * PtrUInt(AHeight);
  GetMem(FPixels, Bytes);
  FillChar(FPixels^, Bytes, 0);
  FOwnsPixels := True;
  FClipRect := TPMLRect.Make(0, 0, FWidth, FHeight);
  FColorMod := TPMLColor.White;
  FAlphaMod := 255;
  FRefCount := -1;
end;

constructor TPMLSurface.CreateFrom(APixels: Pointer;
  AWidth, AHeight, APitch: Integer; AFormat: TPMLPixelFormat);
begin
  inherited Create(nil, nil);
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EPMLArgument.CreateFmt('surface size must be positive (%d x %d)',
      [AWidth, AHeight]);
  if APixels = nil then
    raise EPMLArgument.Create('CreateFrom needs a pixel pointer');
  FFormat := AFormat;
  PMLGetPixelFormatDetails(AFormat, FDetails);
  FWidth := AWidth;
  FHeight := AHeight;
  if APitch > 0 then
    FPitch := APitch
  else
    FPitch := PMLPitchFor(AWidth, AFormat);
  FPixels := APixels;
  FOwnsPixels := False;
  FClipRect := TPMLRect.Make(0, 0, FWidth, FHeight);
  FColorMod := TPMLColor.White;
  FAlphaMod := 255;
  FRefCount := -1;
end;

class function TPMLSurface.CreateShared(AWidth, AHeight: Integer;
  AFormat: TPMLPixelFormat): IPMLSurface;
var
  S: TPMLSurface;
begin
  S := TPMLSurface.Create(AWidth, AHeight, AFormat);
  // ここから参照カウントで生きる。戻り値の代入で 1 になる。
  S.FRefCount := 0;
  Result := S;
end;

destructor TPMLSurface.Destroy;
begin
  if FOwnsPixels and (FPixels <> nil) then
    FreeMem(FPixels);
  FPixels := nil;
  if FOwnsPalette then
    FreeAndNil(FPalette);
  inherited Destroy;
end;

{ ---- IInterface。共有 opt-in（§8.4） ---- }

function TPMLSurface.QueryInterface(constref AIID: TGUID; out AObj): HResult; cdecl;
begin
  if GetInterface(AIID, AObj) then
    Result := 0
  else
    Result := HResult($80004002);   // E_NOINTERFACE
end;

{ FRefCount が -1 の間は参照カウントしない。

  既定のサーフェスをインターフェース変数に入れても寿命が変わらないようにする
  ためで、これが papimela の「参照カウントは opt-in」の実体である（§8.4）。 }
function TPMLSurface._AddRef: LongInt; cdecl;
begin
  if FRefCount < 0 then
    Exit(-1);
  Result := InterLockedIncrement(FRefCount);
end;

function TPMLSurface._Release: LongInt; cdecl;
begin
  if FRefCount < 0 then
    Exit(-1);
  Result := InterLockedDecrement(FRefCount);
  if Result = 0 then
    Destroy;
end;

function TPMLSurface.GetSurface: TPMLSurface;
begin
  Result := Self;
end;

{ ---- 画素 ---- }

function TPMLSurface.GetMustLock: Boolean;
begin
  // RLE が入るまで常に False。SDL は RLE 圧縮中のサーフェスで True を返す。
  Result := False;
end;

procedure TPMLSurface.Lock;
begin
  Inc(FLockCount);
end;

procedure TPMLSurface.Unlock;
begin
  if FLockCount > 0 then
    Dec(FLockCount);
end;

function TPMLSurface.GetPixelAddr(AX, AY: Integer): Pointer;
begin
  Result := PByte(FPixels) + PtrUInt(AY) * PtrUInt(FPitch)
          + PtrUInt(AX) * PtrUInt(FDetails.BytesPerPixel);
end;

procedure TPMLSurface.SetClipRect(const AValue: TPMLRect);
var
  X2, Y2: Integer;
begin
  // サーフェスの外へははみ出させない。交差を取る。
  FClipRect.X := AValue.X;
  FClipRect.Y := AValue.Y;
  if FClipRect.X < 0 then
    FClipRect.X := 0;
  if FClipRect.Y < 0 then
    FClipRect.Y := 0;
  X2 := AValue.X + AValue.W;
  Y2 := AValue.Y + AValue.H;
  if X2 > FWidth then
    X2 := FWidth;
  if Y2 > FHeight then
    Y2 := FHeight;
  FClipRect.W := X2 - FClipRect.X;
  FClipRect.H := Y2 - FClipRect.Y;
  if FClipRect.W < 0 then
    FClipRect.W := 0;
  if FClipRect.H < 0 then
    FClipRect.H := 0;
end;

function TPMLSurface.ReadRaw(AX, AY: Integer): LongWord;
var
  P: PByte;
begin
  Result := 0;
  if (AX < 0) or (AY < 0) or (AX >= FWidth) or (AY >= FHeight) then
    Exit;
  P := GetPixelAddr(AX, AY);
  case FDetails.BytesPerPixel of
    1: Result := P^;
    2: Result := PWord(P)^;
    // 3 バイトはリトルエンディアンで下位から詰まっている。
    3: Result := LongWord(P[0]) or (LongWord(P[1]) shl 8) or (LongWord(P[2]) shl 16);
    4: Result := PLongWord(P)^;
  end;
end;

procedure TPMLSurface.WriteRaw(AX, AY: Integer; AValue: LongWord);
var
  P: PByte;
begin
  if (AX < 0) or (AY < 0) or (AX >= FWidth) or (AY >= FHeight) then
    Exit;
  P := GetPixelAddr(AX, AY);
  case FDetails.BytesPerPixel of
    1: P^ := Byte(AValue);
    2: PWord(P)^ := Word(AValue);
    3: begin
         P[0] := Byte(AValue);
         P[1] := Byte(AValue shr 8);
         P[2] := Byte(AValue shr 16);
       end;
    4: PLongWord(P)^ := AValue;
  end;
end;

function TPMLSurface.ReadPixel(AX, AY: Integer): TPMLColor;
begin
  if (AX < 0) or (AY < 0) or (AX >= FWidth) or (AY >= FHeight) then
    Exit(TPMLColor.Black);
  Result := PMLGetColor(ReadRaw(AX, AY), FDetails, FPalette);
end;

procedure TPMLSurface.WritePixel(AX, AY: Integer; const AColor: TPMLColor);
begin
  WriteRaw(AX, AY, MapColor(AColor));
end;

function TPMLSurface.MapRGBA(AR, AG, AB, AA: Byte): LongWord;
begin
  Result := PMLMapRGBA(FDetails, FPalette, AR, AG, AB, AA);
end;

function TPMLSurface.MapColor(const AColor: TPMLColor): LongWord;
begin
  Result := PMLMapColor(FDetails, FPalette, AColor);
end;

{ 矩形を埋める。

  PORT-NOTE: SDL_FillSurfaceRect 相当。速度を狙った実装（行単位の memset や
  32 ビット単位の書き込み）は第 11 章 #29 が持つ。ここは 1 画素ずつ回す。 }
procedure TPMLSurface.FillRect(const ARect: TPMLRect; const AColor: TPMLColor);
var
  X, Y, X1, Y1, X2, Y2: Integer;
  Raw: LongWord;
begin
  X1 := ARect.X;
  Y1 := ARect.Y;
  X2 := ARect.X + ARect.W;
  Y2 := ARect.Y + ARect.H;
  // クリップ矩形と交差した範囲だけ書く。
  if X1 < FClipRect.X then
    X1 := FClipRect.X;
  if Y1 < FClipRect.Y then
    Y1 := FClipRect.Y;
  if X2 > FClipRect.X + FClipRect.W then
    X2 := FClipRect.X + FClipRect.W;
  if Y2 > FClipRect.Y + FClipRect.H then
    Y2 := FClipRect.Y + FClipRect.H;
  if (X1 >= X2) or (Y1 >= Y2) then
    Exit;

  Raw := MapColor(AColor);
  for Y := Y1 to Y2 - 1 do
    for X := X1 to X2 - 1 do
      WriteRaw(X, Y, Raw);
end;

procedure TPMLSurface.Fill(const AColor: TPMLColor);
begin
  FillRect(TPMLRect.Make(0, 0, FWidth, FHeight), AColor);
end;

function TPMLSurface.Duplicate: TPMLSurface;
var
  Y: Integer;
  RowBytes: PtrUInt;
begin
  Result := TPMLSurface.Create(FWidth, FHeight, FFormat);
  RowBytes := PtrUInt(FWidth) * PtrUInt(FDetails.BytesPerPixel);
  // ピッチが違うことがあるので行ごとに写す。
  for Y := 0 to FHeight - 1 do
    Move(GetPixelAddr(0, Y)^, Result.GetPixelAddr(0, Y)^, RowBytes);
  Result.FClipRect := FClipRect;
  Result.FColorKey := FColorKey;
  Result.FHasColorKey := FHasColorKey;
  Result.FColorMod := FColorMod;
  Result.FAlphaMod := FAlphaMod;
  Result.FBlendMode := FBlendMode;
  if FPalette <> nil then
    Result.SetPalette(FPalette, False);
end;

{ 別の形式へ変換する。

  1 画素ずつ色に戻してから書き直す。形式の組み合わせに依らず必ず正しく、
  往復の検査もしやすい。速い経路（同じ並びなら memcpy、8888 同士ならシフトだけ）
  は第 11 章 #29 が持つ。 }
function TPMLSurface.Convert(AFormat: TPMLPixelFormat): TPMLSurface;
var
  X, Y: Integer;
begin
  Result := TPMLSurface.Create(FWidth, FHeight, AFormat);
  for Y := 0 to FHeight - 1 do
    for X := 0 to FWidth - 1 do
      Result.WritePixel(X, Y, ReadPixel(X, Y));
end;

procedure TPMLSurface.Flip(AMode: TPMLFlipMode);
var
  X, Y: Integer;
  Tmp: LongWord;
begin
  case AMode of
    TPMLFlipMode.Horizontal:
      for Y := 0 to FHeight - 1 do
        for X := 0 to (FWidth div 2) - 1 do
        begin
          Tmp := ReadRaw(X, Y);
          WriteRaw(X, Y, ReadRaw(FWidth - 1 - X, Y));
          WriteRaw(FWidth - 1 - X, Y, Tmp);
        end;
    TPMLFlipMode.Vertical:
      for Y := 0 to (FHeight div 2) - 1 do
        for X := 0 to FWidth - 1 do
        begin
          Tmp := ReadRaw(X, Y);
          WriteRaw(X, Y, ReadRaw(X, FHeight - 1 - Y));
          WriteRaw(X, FHeight - 1 - Y, Tmp);
        end;
  end;
end;

procedure TPMLSurface.SetPalette(APalette: TPMLPalette; AOwned: Boolean);
begin
  if FOwnsPalette and (FPalette <> nil) and (FPalette <> APalette) then
    FreeAndNil(FPalette);
  FPalette := APalette;
  FOwnsPalette := AOwned;
end;

procedure TPMLSurface.SetColorKey(AEnabled: Boolean; AKey: LongWord);
begin
  FHasColorKey := AEnabled;
  if AEnabled then
    FColorKey := AKey
  else
    FColorKey := 0;
end;

function TPMLSurface.HasColorKey: Boolean;
begin
  Result := FHasColorKey;
end;

end.
