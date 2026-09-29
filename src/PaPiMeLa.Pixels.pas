{
  PaPiMeLa.Pixels — ピクセル形式、パレット、色と画素値の相互変換

  Origin : ported from SDL (src/video/SDL_pixels.c, include/SDL3/SDL_pixels.h)
           Scope: 形式識別子のビット配置と 67 個の定数値、マスクの導出規則、
           MapRGBA / GetRGBA の丸め方。構造は本設計に従い、SDL の巨大な
           switch は (order, layout) からの算出に置き換えた。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.4、§11 #27

  WHAT:
    TPMLPixelFormat（形式識別子）、TPMLPixelFormatDetails（マスクとシフト）、
    TPMLPalette、そして色 ↔ 画素値の変換。

  WHY:
    形式識別子は「種別・並び・レイアウト・ビット数・バイト数」を 1 つの 32 ビット
    整数に詰めたもので、値そのものが情報を持つ。SDL と同じ値をそのまま使うのは、
    外部（GL、Vulkan、wl_shm）との対応表が世の中に既にあるため。

  RESOLVED:
    - 定数 67 個は SDL のヘッダから機械的に写した。手で書き写していない
    - マスクは SDL のような形式ごとの switch ではなく、パックド形式は
      (並び, レイアウト) から算出する。配列形式とインデックス形式だけ個別に扱う
    - 値型で返す。SDL はライブラリ内のハッシュ表にキャッシュした構造体への
      ポインタを返すが、papimela は 24 バイトの record を返すだけで済ませる

  NOT RESOLVED:
    - FourCC（YUV）形式は識別だけで、マスクも変換も持たない。SDL も
      マスクは 0 にしている。変換は第 11 章 #42 の YUV と一緒に扱う
    - 色空間（TPMLColorspace）は未実装。HDR と YUV の範囲指定が要るまで置く
    - 10 ビット形式（XRGB2101010 等）は識別と算出はできるが、
      MapRGBA / GetRGBA は 8 ビット成分での入出力しか持たない

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Pixels;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base;

type
  { 形式識別子。ビット配置は以下のとおり（SDL と同じ）。

      bit 28      : 1 = 通常形式、0 = FourCC または UNKNOWN
      bit 24..27  : 種別（TPMLPixelType）
      bit 20..23  : 並び（パックド / 配列 / ビットマップで意味が変わる）
      bit 16..19  : レイアウト（TPMLPackedLayout。パックド形式のみ）
      bit 8..15   : 1 画素のビット数
      bit 0..7    : 1 画素のバイト数 }
  TPMLPixelFormat = type LongWord;

  TPMLPixelType = (
    Unknown, Index1, Index4, Index8, Packed8, Packed16, Packed32,
    ArrayU8, ArrayU16, ArrayU32, ArrayF16, ArrayF32, Index2
  );

  // パックド形式の成分の並び。X は未使用ビット。
  TPMLPackedOrder = (
    None, XRGB, RGBX, ARGB, RGBA, XBGR, BGRX, ABGR, BGRA
  );

  // 配列形式の成分の並び。
  TPMLArrayOrder = (
    ArrayNone, ArrayRGB, ArrayRGBA, ArrayARGB, ArrayBGR, ArrayBGRA, ArrayABGR
  );

  // パックド形式の各成分のビット幅。
  TPMLPackedLayout = (
    LayoutNone, Layout332, Layout4444, Layout1555, Layout5551, Layout565,
    Layout8888, Layout2101010, Layout1010102
  );

  { 形式からマスクとシフトを割り出した結果。値型。

    Rbits 等は成分のビット幅。8 ビットより狭い成分（565 など）を 0..255 へ
    伸ばすときに使う。 }
  TPMLPixelFormatDetails = record
    Format        : TPMLPixelFormat;
    BitsPerPixel  : Byte;
    BytesPerPixel : Byte;
    RMask, GMask, BMask, AMask: LongWord;
    RShift, GShift, BShift, AShift: Byte;
    RBits, GBits, BBits, ABits    : Byte;
    function HasAlpha: Boolean; inline;
  end;

  { インデックス形式の色表。所有者はサーフェス、または nil（アプリ）。 }
  TPMLPalette = class sealed(TPMLOwnedObject)
  strict private
    FColors: TPMLColors;
    function  GetCount: Integer;
    function  GetColor(AIndex: Integer): TPMLColor;
    procedure SetColor(AIndex: Integer; const AValue: TPMLColor);
  public
    // ACount は 2 の冪でなくてもよいが、形式のビット数に足りる必要がある。
    constructor Create(AContextRef: TObject; AOwner: TPMLObject; ACount: Integer);
    // 範囲外の添字は無視する。部分更新のために先頭位置を取る。
    procedure SetColors(const AColors: array of TPMLColor; AFirst: Integer = 0);
    // 全要素を白の不透明にする。生成直後の既定でもある。
    procedure Reset;
    property Count: Integer read GetCount;
    property Colors[AIndex: Integer]: TPMLColor read GetColor write SetColor; default;
  end;

const
  PML_PIXELFORMAT_UNKNOWN = TPMLPixelFormat(0);

  PML_PIXELFORMAT_INDEX1LSB    = TPMLPixelFormat($11100100);
  PML_PIXELFORMAT_INDEX1MSB    = TPMLPixelFormat($11200100);
  PML_PIXELFORMAT_INDEX2LSB    = TPMLPixelFormat($1C100200);
  PML_PIXELFORMAT_INDEX2MSB    = TPMLPixelFormat($1C200200);
  PML_PIXELFORMAT_INDEX4LSB    = TPMLPixelFormat($12100400);
  PML_PIXELFORMAT_INDEX4MSB    = TPMLPixelFormat($12200400);
  PML_PIXELFORMAT_INDEX8       = TPMLPixelFormat($13000801);
  PML_PIXELFORMAT_RGB332       = TPMLPixelFormat($14110801);
  PML_PIXELFORMAT_XRGB4444     = TPMLPixelFormat($15120C02);
  PML_PIXELFORMAT_XBGR4444     = TPMLPixelFormat($15520C02);
  PML_PIXELFORMAT_XRGB1555     = TPMLPixelFormat($15130F02);
  PML_PIXELFORMAT_XBGR1555     = TPMLPixelFormat($15530F02);
  PML_PIXELFORMAT_ARGB4444     = TPMLPixelFormat($15321002);
  PML_PIXELFORMAT_RGBA4444     = TPMLPixelFormat($15421002);
  PML_PIXELFORMAT_ABGR4444     = TPMLPixelFormat($15721002);
  PML_PIXELFORMAT_BGRA4444     = TPMLPixelFormat($15821002);
  PML_PIXELFORMAT_ARGB1555     = TPMLPixelFormat($15331002);
  PML_PIXELFORMAT_RGBA5551     = TPMLPixelFormat($15441002);
  PML_PIXELFORMAT_ABGR1555     = TPMLPixelFormat($15731002);
  PML_PIXELFORMAT_BGRA5551     = TPMLPixelFormat($15841002);
  PML_PIXELFORMAT_RGB565       = TPMLPixelFormat($15151002);
  PML_PIXELFORMAT_BGR565       = TPMLPixelFormat($15551002);
  PML_PIXELFORMAT_RGB24        = TPMLPixelFormat($17101803);
  PML_PIXELFORMAT_BGR24        = TPMLPixelFormat($17401803);
  PML_PIXELFORMAT_XRGB8888     = TPMLPixelFormat($16161804);
  PML_PIXELFORMAT_RGBX8888     = TPMLPixelFormat($16261804);
  PML_PIXELFORMAT_XBGR8888     = TPMLPixelFormat($16561804);
  PML_PIXELFORMAT_BGRX8888     = TPMLPixelFormat($16661804);
  PML_PIXELFORMAT_ARGB8888     = TPMLPixelFormat($16362004);
  PML_PIXELFORMAT_RGBA8888     = TPMLPixelFormat($16462004);
  PML_PIXELFORMAT_ABGR8888     = TPMLPixelFormat($16762004);
  PML_PIXELFORMAT_BGRA8888     = TPMLPixelFormat($16862004);
  PML_PIXELFORMAT_XRGB2101010  = TPMLPixelFormat($16172004);
  PML_PIXELFORMAT_XBGR2101010  = TPMLPixelFormat($16572004);
  PML_PIXELFORMAT_ARGB2101010  = TPMLPixelFormat($16372004);
  PML_PIXELFORMAT_ABGR2101010  = TPMLPixelFormat($16772004);
  PML_PIXELFORMAT_RGB48        = TPMLPixelFormat($18103006);
  PML_PIXELFORMAT_BGR48        = TPMLPixelFormat($18403006);
  PML_PIXELFORMAT_RGBA64       = TPMLPixelFormat($18204008);
  PML_PIXELFORMAT_ARGB64       = TPMLPixelFormat($18304008);
  PML_PIXELFORMAT_BGRA64       = TPMLPixelFormat($18504008);
  PML_PIXELFORMAT_ABGR64       = TPMLPixelFormat($18604008);
  PML_PIXELFORMAT_RGB48_FLOAT  = TPMLPixelFormat($1A103006);
  PML_PIXELFORMAT_BGR48_FLOAT  = TPMLPixelFormat($1A403006);
  PML_PIXELFORMAT_RGBA64_FLOAT = TPMLPixelFormat($1A204008);
  PML_PIXELFORMAT_ARGB64_FLOAT = TPMLPixelFormat($1A304008);
  PML_PIXELFORMAT_BGRA64_FLOAT = TPMLPixelFormat($1A504008);
  PML_PIXELFORMAT_ABGR64_FLOAT = TPMLPixelFormat($1A604008);
  PML_PIXELFORMAT_RGB96_FLOAT  = TPMLPixelFormat($1B10600C);
  PML_PIXELFORMAT_BGR96_FLOAT  = TPMLPixelFormat($1B40600C);
  PML_PIXELFORMAT_RGBA128_FLOAT = TPMLPixelFormat($1B208010);
  PML_PIXELFORMAT_ARGB128_FLOAT = TPMLPixelFormat($1B308010);
  PML_PIXELFORMAT_BGRA128_FLOAT = TPMLPixelFormat($1B508010);
  PML_PIXELFORMAT_ABGR128_FLOAT = TPMLPixelFormat($1B608010);

  // FourCC（YUV 等）。識別のみで、マスクも変換も持たない。
  PML_PIXELFORMAT_YV12         = TPMLPixelFormat($32315659);
  PML_PIXELFORMAT_IYUV         = TPMLPixelFormat($56555949);
  PML_PIXELFORMAT_YUY2         = TPMLPixelFormat($32595559);
  PML_PIXELFORMAT_UYVY         = TPMLPixelFormat($59565955);
  PML_PIXELFORMAT_YVYU         = TPMLPixelFormat($55595659);
  PML_PIXELFORMAT_NV12         = TPMLPixelFormat($3231564E);
  PML_PIXELFORMAT_NV21         = TPMLPixelFormat($3132564E);
  PML_PIXELFORMAT_I444         = TPMLPixelFormat($34343449);
  PML_PIXELFORMAT_P010         = TPMLPixelFormat($30313050);
  PML_PIXELFORMAT_I0FL         = TPMLPixelFormat($4C463049);
  PML_PIXELFORMAT_I4FL         = TPMLPixelFormat($4C463449);
  PML_PIXELFORMAT_EXTERNAL_OES = TPMLPixelFormat($2053454F);
  PML_PIXELFORMAT_MJPG         = TPMLPixelFormat($47504A4D);

  { バイト配列として見たときの並びに対する別名。

    リトルエンディアン専用。papimela の初回スコープは Linux の x86_64 / ARM で、
    どちらもリトルエンディアンなので分岐を置いていない。ビッグエンディアンを
    足すときはここを ENDIAN_BIG の条件コンパイルで分ける。 }
  PML_PIXELFORMAT_RGBA32 = PML_PIXELFORMAT_ABGR8888;
  PML_PIXELFORMAT_ARGB32 = PML_PIXELFORMAT_BGRA8888;
  PML_PIXELFORMAT_BGRA32 = PML_PIXELFORMAT_ARGB8888;
  PML_PIXELFORMAT_ABGR32 = PML_PIXELFORMAT_RGBA8888;
  PML_PIXELFORMAT_RGBX32 = PML_PIXELFORMAT_XBGR8888;
  PML_PIXELFORMAT_XRGB32 = PML_PIXELFORMAT_BGRX8888;
  PML_PIXELFORMAT_BGRX32 = PML_PIXELFORMAT_XRGB8888;
  PML_PIXELFORMAT_XBGR32 = PML_PIXELFORMAT_RGBX8888;

// ---- 形式識別子の読み取り（値のビットを見るだけ。表は引かない）

function PMLPixelFlag(AFormat: TPMLPixelFormat): LongWord; inline;
function PMLPixelType(AFormat: TPMLPixelFormat): TPMLPixelType; inline;
// 並びの意味は種別で変わる。パックドなら TPMLPackedOrder、配列なら TPMLArrayOrder。
function PMLPixelOrder(AFormat: TPMLPixelFormat): LongWord; inline;
function PMLPixelLayout(AFormat: TPMLPixelFormat): TPMLPackedLayout; inline;
function PMLBitsPerPixel(AFormat: TPMLPixelFormat): Integer; inline;
// 1 画素のバイト数。FourCC は 1 か 2 を返す（YUY2 系は 2）。
function PMLBytesPerPixel(AFormat: TPMLPixelFormat): Integer;

function PMLIsPixelFormatIndexed(AFormat: TPMLPixelFormat): Boolean;
function PMLIsPixelFormatPacked(AFormat: TPMLPixelFormat): Boolean;
function PMLIsPixelFormatArray(AFormat: TPMLPixelFormat): Boolean;
function PMLIsPixelFormatAlpha(AFormat: TPMLPixelFormat): Boolean;
function PMLIsPixelFormatFourCC(AFormat: TPMLPixelFormat): Boolean; inline;
function PMLIsPixelFormatFloat(AFormat: TPMLPixelFormat): Boolean;
function PMLIsPixelFormat10Bit(AFormat: TPMLPixelFormat): Boolean;

// 'PML_PIXELFORMAT_' を外した短い名前。未知の形式は 16 進で返す。
function PMLPixelFormatName(AFormat: TPMLPixelFormat): String;

// ---- マスクと変換

// 形式からマスク・シフト・ビット幅を割り出す。
// False = マスクを持たない形式（FourCC、インデックス、UNKNOWN）。
// False でも Format / BitsPerPixel / BytesPerPixel は埋まる。
function PMLGetPixelFormatDetails(AFormat: TPMLPixelFormat;
  out ADetails: TPMLPixelFormatDetails): Boolean;

function PMLGetPixelFormatForMasks(ABitsPerPixel: Integer;
  ARMask, AGMask, ABMask, AAMask: LongWord): TPMLPixelFormat;

// 色 → 画素値。パレットがあればインデックス形式で最も近い色の番号を返す。
function PMLMapRGB(const ADetails: TPMLPixelFormatDetails; APalette: TPMLPalette;
  AR, AG, AB: Byte): LongWord;
function PMLMapRGBA(const ADetails: TPMLPixelFormatDetails; APalette: TPMLPalette;
  AR, AG, AB, AA: Byte): LongWord;
function PMLMapColor(const ADetails: TPMLPixelFormatDetails; APalette: TPMLPalette;
  const AColor: TPMLColor): LongWord; inline;

// 画素値 → 色。アルファを持たない形式では A に 255 が入る。
procedure PMLGetRGB(APixel: LongWord; const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette; out AR, AG, AB: Byte);
procedure PMLGetRGBA(APixel: LongWord; const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette; out AR, AG, AB, AA: Byte);
function PMLGetColor(APixel: LongWord; const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette): TPMLColor;

implementation

{ TPMLPixelFormatDetails }

function TPMLPixelFormatDetails.HasAlpha: Boolean;
begin
  Result := AMask <> 0;
end;


function PMLPixelFlag(AFormat: TPMLPixelFormat): LongWord; inline;
begin
  Result := (AFormat shr 28) and $0F;
end;

function PMLPixelType(AFormat: TPMLPixelFormat): TPMLPixelType; inline;
begin
  Result := TPMLPixelType((AFormat shr 24) and $0F);
end;

function PMLPixelOrder(AFormat: TPMLPixelFormat): LongWord; inline;
begin
  Result := (AFormat shr 20) and $0F;
end;

function PMLPixelLayout(AFormat: TPMLPixelFormat): TPMLPackedLayout; inline;
begin
  Result := TPMLPackedLayout((AFormat shr 16) and $0F);
end;

function PMLBitsPerPixel(AFormat: TPMLPixelFormat): Integer; inline;
begin
  Result := (AFormat shr 8) and $FF;
end;

function PMLBytesPerPixel(AFormat: TPMLPixelFormat): Integer;
begin
  if PMLIsPixelFormatFourCC(AFormat) then
  begin
    if (AFormat = PML_PIXELFORMAT_YUY2) or (AFormat = PML_PIXELFORMAT_UYVY) or
       (AFormat = PML_PIXELFORMAT_YVYU) then
      Result := 2
    else
      Result := 1;
  end
  else
    Result := AFormat and $FF;
end;

function PMLIsPixelFormatIndexed(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := (not PMLIsPixelFormatFourCC(AFormat)) and
             ((PMLPixelType(AFormat) = TPMLPixelType.Index1) or
              (PMLPixelType(AFormat) = TPMLPixelType.Index2) or
              (PMLPixelType(AFormat) = TPMLPixelType.Index4) or
              (PMLPixelType(AFormat) = TPMLPixelType.Index8));
end;

function PMLIsPixelFormatPacked(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := (not PMLIsPixelFormatFourCC(AFormat)) and
             ((PMLPixelType(AFormat) = TPMLPixelType.Packed8) or
              (PMLPixelType(AFormat) = TPMLPixelType.Packed16) or
              (PMLPixelType(AFormat) = TPMLPixelType.Packed32));
end;

function PMLIsPixelFormatArray(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := (not PMLIsPixelFormatFourCC(AFormat)) and
             ((PMLPixelType(AFormat) = TPMLPixelType.ArrayU8) or
              (PMLPixelType(AFormat) = TPMLPixelType.ArrayU16) or
              (PMLPixelType(AFormat) = TPMLPixelType.ArrayU32) or
              (PMLPixelType(AFormat) = TPMLPixelType.ArrayF16) or
              (PMLPixelType(AFormat) = TPMLPixelType.ArrayF32));
end;

function PMLIsPixelFormatAlpha(AFormat: TPMLPixelFormat): Boolean;
var
  Order: LongWord;
begin
  if PMLIsPixelFormatPacked(AFormat) then
  begin
    Order := PMLPixelOrder(AFormat);
    Result := (Order = Ord(TPMLPackedOrder.ARGB)) or
             (Order = Ord(TPMLPackedOrder.RGBA)) or
             (Order = Ord(TPMLPackedOrder.ABGR)) or
             (Order = Ord(TPMLPackedOrder.BGRA));
  end
  else if PMLIsPixelFormatArray(AFormat) then
  begin
    Order := PMLPixelOrder(AFormat);
    Result := (Order = Ord(TPMLArrayOrder.ArrayARGB)) or
             (Order = Ord(TPMLArrayOrder.ArrayRGBA)) or
             (Order = Ord(TPMLArrayOrder.ArrayABGR)) or
             (Order = Ord(TPMLArrayOrder.ArrayBGRA));
  end
  else
    Result := False;
end;

function PMLIsPixelFormatFourCC(AFormat: TPMLPixelFormat): Boolean; inline;
begin
  Result := (AFormat <> 0) and (PMLPixelFlag(AFormat) <> 1);
end;

function PMLIsPixelFormatFloat(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := (not PMLIsPixelFormatFourCC(AFormat)) and
             ((PMLPixelType(AFormat) = TPMLPixelType.ArrayF16) or
              (PMLPixelType(AFormat) = TPMLPixelType.ArrayF32));
end;

function PMLIsPixelFormat10Bit(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := (not PMLIsPixelFormatFourCC(AFormat)) and
             (PMLPixelType(AFormat) = TPMLPixelType.Packed32) and
             ((PMLPixelLayout(AFormat) = TPMLPackedLayout.Layout2101010) or
              (PMLPixelLayout(AFormat) = TPMLPackedLayout.Layout1010102));
end;

function PMLPixelFormatName(AFormat: TPMLPixelFormat): String;
begin
  case AFormat of
    PML_PIXELFORMAT_UNKNOWN: Result := 'UNKNOWN';
    PML_PIXELFORMAT_INDEX1LSB: Result := 'INDEX1LSB';
    PML_PIXELFORMAT_INDEX1MSB: Result := 'INDEX1MSB';
    PML_PIXELFORMAT_INDEX2LSB: Result := 'INDEX2LSB';
    PML_PIXELFORMAT_INDEX2MSB: Result := 'INDEX2MSB';
    PML_PIXELFORMAT_INDEX4LSB: Result := 'INDEX4LSB';
    PML_PIXELFORMAT_INDEX4MSB: Result := 'INDEX4MSB';
    PML_PIXELFORMAT_INDEX8: Result := 'INDEX8';
    PML_PIXELFORMAT_RGB332: Result := 'RGB332';
    PML_PIXELFORMAT_XRGB4444: Result := 'XRGB4444';
    PML_PIXELFORMAT_XBGR4444: Result := 'XBGR4444';
    PML_PIXELFORMAT_XRGB1555: Result := 'XRGB1555';
    PML_PIXELFORMAT_XBGR1555: Result := 'XBGR1555';
    PML_PIXELFORMAT_ARGB4444: Result := 'ARGB4444';
    PML_PIXELFORMAT_RGBA4444: Result := 'RGBA4444';
    PML_PIXELFORMAT_ABGR4444: Result := 'ABGR4444';
    PML_PIXELFORMAT_BGRA4444: Result := 'BGRA4444';
    PML_PIXELFORMAT_ARGB1555: Result := 'ARGB1555';
    PML_PIXELFORMAT_RGBA5551: Result := 'RGBA5551';
    PML_PIXELFORMAT_ABGR1555: Result := 'ABGR1555';
    PML_PIXELFORMAT_BGRA5551: Result := 'BGRA5551';
    PML_PIXELFORMAT_RGB565: Result := 'RGB565';
    PML_PIXELFORMAT_BGR565: Result := 'BGR565';
    PML_PIXELFORMAT_RGB24: Result := 'RGB24';
    PML_PIXELFORMAT_BGR24: Result := 'BGR24';
    PML_PIXELFORMAT_XRGB8888: Result := 'XRGB8888';
    PML_PIXELFORMAT_RGBX8888: Result := 'RGBX8888';
    PML_PIXELFORMAT_XBGR8888: Result := 'XBGR8888';
    PML_PIXELFORMAT_BGRX8888: Result := 'BGRX8888';
    PML_PIXELFORMAT_ARGB8888: Result := 'ARGB8888';
    PML_PIXELFORMAT_RGBA8888: Result := 'RGBA8888';
    PML_PIXELFORMAT_ABGR8888: Result := 'ABGR8888';
    PML_PIXELFORMAT_BGRA8888: Result := 'BGRA8888';
    PML_PIXELFORMAT_XRGB2101010: Result := 'XRGB2101010';
    PML_PIXELFORMAT_XBGR2101010: Result := 'XBGR2101010';
    PML_PIXELFORMAT_ARGB2101010: Result := 'ARGB2101010';
    PML_PIXELFORMAT_ABGR2101010: Result := 'ABGR2101010';
    PML_PIXELFORMAT_RGB48: Result := 'RGB48';
    PML_PIXELFORMAT_BGR48: Result := 'BGR48';
    PML_PIXELFORMAT_RGBA64: Result := 'RGBA64';
    PML_PIXELFORMAT_ARGB64: Result := 'ARGB64';
    PML_PIXELFORMAT_BGRA64: Result := 'BGRA64';
    PML_PIXELFORMAT_ABGR64: Result := 'ABGR64';
    PML_PIXELFORMAT_RGB48_FLOAT: Result := 'RGB48_FLOAT';
    PML_PIXELFORMAT_BGR48_FLOAT: Result := 'BGR48_FLOAT';
    PML_PIXELFORMAT_RGBA64_FLOAT: Result := 'RGBA64_FLOAT';
    PML_PIXELFORMAT_ARGB64_FLOAT: Result := 'ARGB64_FLOAT';
    PML_PIXELFORMAT_BGRA64_FLOAT: Result := 'BGRA64_FLOAT';
    PML_PIXELFORMAT_ABGR64_FLOAT: Result := 'ABGR64_FLOAT';
    PML_PIXELFORMAT_RGB96_FLOAT: Result := 'RGB96_FLOAT';
    PML_PIXELFORMAT_BGR96_FLOAT: Result := 'BGR96_FLOAT';
    PML_PIXELFORMAT_RGBA128_FLOAT: Result := 'RGBA128_FLOAT';
    PML_PIXELFORMAT_ARGB128_FLOAT: Result := 'ARGB128_FLOAT';
    PML_PIXELFORMAT_BGRA128_FLOAT: Result := 'BGRA128_FLOAT';
    PML_PIXELFORMAT_ABGR128_FLOAT: Result := 'ABGR128_FLOAT';
    PML_PIXELFORMAT_YV12: Result := 'YV12';
    PML_PIXELFORMAT_IYUV: Result := 'IYUV';
    PML_PIXELFORMAT_YUY2: Result := 'YUY2';
    PML_PIXELFORMAT_UYVY: Result := 'UYVY';
    PML_PIXELFORMAT_YVYU: Result := 'YVYU';
    PML_PIXELFORMAT_NV12: Result := 'NV12';
    PML_PIXELFORMAT_NV21: Result := 'NV21';
    PML_PIXELFORMAT_I444: Result := 'I444';
    PML_PIXELFORMAT_P010: Result := 'P010';
    PML_PIXELFORMAT_I0FL: Result := 'I0FL';
    PML_PIXELFORMAT_I4FL: Result := 'I4FL';
    PML_PIXELFORMAT_EXTERNAL_OES: Result := 'EXTERNAL_OES';
    PML_PIXELFORMAT_MJPG: Result := 'MJPG';
  else
    Result := Format('$%.8x', [LongWord(AFormat)]);
  end;
end;


{ マスクからシフト量とビット幅を数える。SDL_InitPixelFormatDetails と同じ方法。 }
procedure SplitMask(AMask: LongWord; out AShift, ABits: Byte);
var
  M: LongWord;
begin
  AShift := 0;
  ABits := 0;
  if AMask = 0 then
    Exit;
  M := AMask;
  while (M and 1) = 0 do
  begin
    Inc(AShift);
    M := M shr 1;
  end;
  while (M and 1) <> 0 do
  begin
    Inc(ABits);
    M := M shr 1;
  end;
end;

{ 形式からマスク・シフト・ビット幅を割り出す。

  WHAT:
    パックド形式はレイアウトが「並び順に見た各成分のビット幅」を、並びが
    「どの位置がどの成分か」を決める。この 2 つから算出する。

  WHY:
    SDL は形式ごとの switch（約 240 行）で書いているが、値が規則的なので表を
    引く必要が無い。規則を 1 箇所に書けば、形式が増えても直さずに済む。

  RESOLVED:
    - 3 成分のレイアウト（332 / 565）には X の枠が無い。並びの X を先に
      取り除いてから幅を割り当てる

  PORT-NOTE: SDL_GetMasksForPixelFormat 相当。結果が SDL と一致することは
  test_pixels がマスクの直接比較と色の往復で検査している。FourCC のビット数の
  扱い（YUY2 系だけ 32 ビット扱い）は SDL の振る舞いをそのまま継いでいる。 }
function PMLGetPixelFormatDetails(AFormat: TPMLPixelFormat;
  out ADetails: TPMLPixelFormatDetails): Boolean;
const
  // レイアウトごとの、並び順に見た各成分のビット幅。
  LayoutWidths: array[TPMLPackedLayout] of array[0..3] of Byte = (
    (0, 0, 0, 0),        // LayoutNone
    (3, 3, 2, 0),        // 332
    (4, 4, 4, 4),        // 4444
    (1, 5, 5, 5),        // 1555
    (5, 5, 5, 1),        // 5551
    (5, 6, 5, 0),        // 565
    (8, 8, 8, 8),        // 8888
    (2, 10, 10, 10),     // 2101010
    (10, 10, 10, 2)      // 1010102
  );
  // レイアウトが持つ成分の数。3 なら X の枠が無い。
  LayoutCount: array[TPMLPackedLayout] of Byte = (0, 3, 4, 4, 4, 3, 4, 4, 4);
  // 並びごとの成分。0 = X（捨てる）、1 = R、2 = G、3 = B、4 = A。
  OrderComponents: array[TPMLPackedOrder] of array[0..3] of Byte = (
    (0, 0, 0, 0),        // None
    (0, 1, 2, 3),        // XRGB
    (1, 2, 3, 0),        // RGBX
    (4, 1, 2, 3),        // ARGB
    (1, 2, 3, 4),        // RGBA
    (0, 3, 2, 1),        // XBGR
    (3, 2, 1, 0),        // BGRX
    (4, 3, 2, 1),        // ABGR
    (3, 2, 1, 4)         // BGRA
  );
var
  Layout : TPMLPackedLayout;
  OrderIx: LongWord;
  Widths : array[0..3] of Byte;
  Comps  : array[0..3] of Byte;
  Masks  : array[1..4] of LongWord;   // 添字は成分番号（1 = R 〜 4 = A）
  Count  : Byte;
  I, J, Shift: Integer;
begin
  FillChar(ADetails, SizeOf(ADetails), 0);
  ADetails.Format := AFormat;
  ADetails.BitsPerPixel := Byte(PMLBitsPerPixel(AFormat));
  ADetails.BytesPerPixel := Byte(PMLBytesPerPixel(AFormat));

  // マスクを持たない形式。ビット数までは埋めてあるので、呼び出し側は False でも
  // BytesPerPixel を使える。
  if (AFormat = PML_PIXELFORMAT_UNKNOWN)
  or PMLIsPixelFormatFourCC(AFormat)
  or PMLIsPixelFormatIndexed(AFormat) then
    Exit(False);

  FillChar(Masks, SizeOf(Masks), 0);

  if PMLIsPixelFormatPacked(AFormat) then
  begin
    Layout := PMLPixelLayout(AFormat);
    OrderIx := PMLPixelOrder(AFormat);
    if OrderIx > LongWord(Ord(High(TPMLPackedOrder))) then
      Exit(False);
    Count := LayoutCount[Layout];
    if Count = 0 then
      Exit(False);
    Widths := LayoutWidths[Layout];
    Comps := OrderComponents[TPMLPackedOrder(OrderIx)];

    // 3 成分のレイアウトには X の枠が無いので、並びから X を抜いて詰める。
    // これをしないと RGB565 の R に G の幅が付いてしまう。
    if Count = 3 then
    begin
      J := 0;
      for I := 0 to 3 do
        if Comps[I] <> 0 then
        begin
          Comps[J] := Comps[I];
          Inc(J);
        end;
      for I := J to 3 do
        Comps[I] := 0;
    end;

    // 成分は上位ビットから順に並ぶ。末尾から幅を足していけばシフト量になる。
    Shift := 0;
    for I := Count - 1 downto 0 do
    begin
      if (Comps[I] <> 0) and (Widths[I] <> 0) then
        Masks[Comps[I]] := ((LongWord(1) shl Widths[I]) - 1) shl Shift;
      Inc(Shift, Widths[I]);
    end;
  end
  else if (PMLPixelType(AFormat) = TPMLPixelType.ArrayU8)
      and (ADetails.BytesPerPixel = 3) then
  begin
    // RGB24 / BGR24。バイト配列なので、リトルエンディアンでは先頭バイトが
    // 最下位になる。
    case PMLPixelOrder(AFormat) of
      LongWord(Ord(TPMLArrayOrder.ArrayRGB)):
        begin
          Masks[1] := $000000FF;
          Masks[2] := $0000FF00;
          Masks[3] := $00FF0000;
        end;
      LongWord(Ord(TPMLArrayOrder.ArrayBGR)):
        begin
          Masks[1] := $00FF0000;
          Masks[2] := $0000FF00;
          Masks[3] := $000000FF;
        end;
    else
      Exit(False);
    end;
  end
  else
    // 16 ビット成分や浮動小数点の配列形式は 32 ビットのマスクで表せない。
    Exit(False);

  ADetails.RMask := Masks[1];
  ADetails.GMask := Masks[2];
  ADetails.BMask := Masks[3];
  ADetails.AMask := Masks[4];
  SplitMask(ADetails.RMask, ADetails.RShift, ADetails.RBits);
  SplitMask(ADetails.GMask, ADetails.GShift, ADetails.GBits);
  SplitMask(ADetails.BMask, ADetails.BShift, ADetails.BBits);
  SplitMask(ADetails.AMask, ADetails.AShift, ADetails.ABits);
  Result := True;
end;

function PMLGetPixelFormatForMasks(ABitsPerPixel: Integer;
  ARMask, AGMask, ABMask, AAMask: LongWord): TPMLPixelFormat;
begin
  if (ABitsPerPixel = 32) and (ARMask = $00FF0000) and (AGMask = $0000FF00) and
     (ABMask = $000000FF) and (AAMask = $FF000000) then
    Result := PML_PIXELFORMAT_ARGB8888
  else if (ABitsPerPixel = 32) and (ARMask = $00FF0000) and (AGMask = $0000FF00) and
         (ABMask = $000000FF) and (AAMask = 0) then
    Result := PML_PIXELFORMAT_XRGB8888
  else if (ABitsPerPixel = 32) and (ARMask = $000000FF) and (AGMask = $0000FF00) and
         (ABMask = $00FF0000) and (AAMask = $FF000000) then
    Result := PML_PIXELFORMAT_ABGR8888
  else if (ABitsPerPixel = 32) and (ARMask = $000000FF) and (AGMask = $0000FF00) and
         (ABMask = $00FF0000) and (AAMask = 0) then
    Result := PML_PIXELFORMAT_XBGR8888
  else if (ABitsPerPixel = 32) and (ARMask = $FF000000) and (AGMask = $00FF0000) and
         (ABMask = $0000FF00) and (AAMask = $000000FF) then
    Result := PML_PIXELFORMAT_RGBA8888
  else if (ABitsPerPixel = 32) and (ARMask = $0000FF00) and (AGMask = $00FF0000) and
         (ABMask = $FF000000) and (AAMask = $000000FF) then
    Result := PML_PIXELFORMAT_BGRA8888
  else if (ABitsPerPixel = 24) and (ARMask = $000000FF) and (AGMask = $0000FF00) and
         (ABMask = $00FF0000) and (AAMask = 0) then
    Result := PML_PIXELFORMAT_RGB24
  else if (ABitsPerPixel = 24) and (ARMask = $00FF0000) and (AGMask = $0000FF00) and
         (ABMask = $000000FF) and (AAMask = 0) then
    Result := PML_PIXELFORMAT_BGR24
  else if (ABitsPerPixel = 16) and (ARMask = $F800) and (AGMask = $07E0) and
         (ABMask = $001F) and (AAMask = 0) then
    Result := PML_PIXELFORMAT_RGB565
  else if (ABitsPerPixel = 16) and (ARMask = $001F) and (AGMask = $07E0) and
         (ABMask = $F800) and (AAMask = 0) then
    Result := PML_PIXELFORMAT_BGR565
  else if (ABitsPerPixel = 16) and (ARMask = $7C00) and (AGMask = $03E0) and
         (ABMask = $001F) and (AAMask = 0) then
    Result := PML_PIXELFORMAT_XRGB1555
  else if (ABitsPerPixel = 16) and (ARMask = $0F00) and (AGMask = $00F0) and
         (ABMask = $000F) and (AAMask = $F000) then
    Result := PML_PIXELFORMAT_ARGB4444
  else if (ABitsPerPixel = 8) and (ARMask = 0) and (AGMask = 0) and
         (ABMask = 0) and (AAMask = 0) then
    Result := PML_PIXELFORMAT_INDEX8
  else
    Result := PML_PIXELFORMAT_UNKNOWN;
end;

{ 8 ビットの値を幅 ABits の成分へ縮める。 }
function NarrowTo(AValue: Byte; ABits: Byte): LongWord; inline;
begin
  if ABits = 0 then
    Result := 0
  else if ABits >= 8 then
    // 10 ビット成分は上位へ寄せ、空いた下位に上位ビットを複製して埋める。
    Result := (LongWord(AValue) shl (ABits - 8)) or (LongWord(AValue) shr (16 - ABits))
  else
    Result := LongWord(AValue) shr (8 - ABits);
end;

{ 幅 ABits の成分を 8 ビットへ伸ばす。

  (v * 255) div (2^bits - 1) を使う。1 ビットや 2 ビットの成分でも端が
  きちんと 0 と 255 になり、ビット複製のような場合分けが要らない。 }
function WidenFrom(AValue: LongWord; ABits: Byte): Byte; inline;
var
  MaxV: LongWord;
begin
  if ABits = 0 then
    Exit(0);
  if ABits >= 8 then
    Exit(Byte(AValue shr (ABits - 8)));
  MaxV := (LongWord(1) shl ABits) - 1;
  Result := Byte((AValue * 255 + MaxV div 2) div MaxV);
end;

{ パレットの中で (R, G, B) に最も近い色の添字を返す。

  PORT-NOTE: SDL_MapRGB と同じ二乗距離。差は Integer で取る。Byte のまま
  引くと桁が回り込む。 }
function NearestInPalette(APalette: TPMLPalette; AR, AG, AB: Byte): LongWord;
var
  I, Best, Dist, DR, DG, DB: Integer;
  C: TPMLColor;
begin
  Result := 0;
  Best := High(Integer);
  for I := 0 to APalette.Count - 1 do
  begin
    C := APalette.Colors[I];
    DR := Integer(AR) - Integer(C.R);
    DG := Integer(AG) - Integer(C.G);
    DB := Integer(AB) - Integer(C.B);
    Dist := DR * DR + DG * DG + DB * DB;
    if Dist < Best then
    begin
      Best := Dist;
      Result := LongWord(I);
      if Dist = 0 then
        Exit;
    end;
  end;
end;

function PMLMapRGB(const ADetails: TPMLPixelFormatDetails; APalette: TPMLPalette;
  AR, AG, AB: Byte): LongWord;
begin
  Result := PMLMapRGBA(ADetails, APalette, AR, AG, AB, 255);
end;

{ 色を画素値にする。

  成分ごとに幅へ縮めてからシフトして重ねる。途中の値は LongWord で持つ。
  Byte に入れるとシフトした時点で桁が落ちる（32 ビット形式で必ず壊れる）。 }
function PMLMapRGBA(const ADetails: TPMLPixelFormatDetails; APalette: TPMLPalette;
  AR, AG, AB, AA: Byte): LongWord;
begin
  if Assigned(APalette) then
    Exit(NearestInPalette(APalette, AR, AG, AB));

  Result := 0;
  if ADetails.RMask <> 0 then
    Result := Result or ((NarrowTo(AR, ADetails.RBits) shl ADetails.RShift) and ADetails.RMask);
  if ADetails.GMask <> 0 then
    Result := Result or ((NarrowTo(AG, ADetails.GBits) shl ADetails.GShift) and ADetails.GMask);
  if ADetails.BMask <> 0 then
    Result := Result or ((NarrowTo(AB, ADetails.BBits) shl ADetails.BShift) and ADetails.BMask);
  if ADetails.AMask <> 0 then
    Result := Result or ((NarrowTo(AA, ADetails.ABits) shl ADetails.AShift) and ADetails.AMask);
end;

function PMLMapColor(const ADetails: TPMLPixelFormatDetails; APalette: TPMLPalette;
  const AColor: TPMLColor): LongWord;
begin
  Result := PMLMapRGBA(ADetails, APalette, AColor.R, AColor.G, AColor.B, AColor.A);
end;

procedure PMLGetRGB(APixel: LongWord; const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette; out AR, AG, AB: Byte);
var
  A: Byte;
begin
  PMLGetRGBA(APixel, ADetails, APalette, AR, AG, AB, A);
end;

{ 画素値を色にする。

  アルファを持たない形式では AA に 255 を入れる。SDL も同じで、
  「不透明として扱う」が呼び出し側にとって扱いやすい。 }
procedure PMLGetRGBA(APixel: LongWord; const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette; out AR, AG, AB, AA: Byte);
var
  C: TPMLColor;
begin
  if Assigned(APalette) then
  begin
    if APixel < LongWord(APalette.Count) then
      C := APalette.Colors[APixel]
    else
      C := TPMLColor.Black;
    AR := C.R;
    AG := C.G;
    AB := C.B;
    AA := C.A;
    Exit;
  end;

  if ADetails.RMask <> 0 then
    AR := WidenFrom((APixel and ADetails.RMask) shr ADetails.RShift, ADetails.RBits)
  else
    AR := 0;
  if ADetails.GMask <> 0 then
    AG := WidenFrom((APixel and ADetails.GMask) shr ADetails.GShift, ADetails.GBits)
  else
    AG := 0;
  if ADetails.BMask <> 0 then
    AB := WidenFrom((APixel and ADetails.BMask) shr ADetails.BShift, ADetails.BBits)
  else
    AB := 0;
  if ADetails.AMask <> 0 then
    AA := WidenFrom((APixel and ADetails.AMask) shr ADetails.AShift, ADetails.ABits)
  else
    AA := 255;
end;

function PMLGetColor(APixel: LongWord; const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette): TPMLColor;
begin
  PMLGetRGBA(APixel, ADetails, APalette, Result.R, Result.G, Result.B, Result.A);
end;

constructor TPMLPalette.Create(AContextRef: TObject; AOwner: TPMLObject; ACount: Integer);
begin
  inherited Create(AContextRef, AOwner);
  if ACount < 1 then
    ACount := 1;
  SetLength(FColors, ACount);
  Reset;
end;

function TPMLPalette.GetCount: Integer;
begin
  Result := Length(FColors);
end;

function TPMLPalette.GetColor(AIndex: Integer): TPMLColor;
begin
  if (AIndex >= 0) and (AIndex < Length(FColors)) then
    Result := FColors[AIndex]
  else
    Result := TPMLColor.White;
end;

procedure TPMLPalette.SetColor(AIndex: Integer; const AValue: TPMLColor);
begin
  if (AIndex >= 0) and (AIndex < Length(FColors)) then
    FColors[AIndex] := AValue;
end;

procedure TPMLPalette.SetColors(const AColors: array of TPMLColor; AFirst: Integer);
var
  i, j: Integer;
begin
  if AFirst >= 0 then
  begin
    i := AFirst;
    j := 0;
    while (i < Length(FColors)) and (j < Length(AColors)) do
    begin
      FColors[i] := AColors[j];
      Inc(i);
      Inc(j);
    end;
  end;
end;

procedure TPMLPalette.Reset;
var
  i: Integer;
begin
  for i := 0 to Length(FColors) - 1 do
    FColors[i] := TPMLColor.White;
end;

end.
