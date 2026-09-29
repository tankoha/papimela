{
  PaPiMeLa.Types — 基本的な値型

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §8.3（幾何型）、§7.3（IME の値型）、§5.2（TPMLSubsystemTag）

  WHAT:
    サブシステムの識別タグ、幾何型、および IME の変換中テキストを表す値型。

  WHY:
    IME の値型をここに置くのは、イベントレコード（PaPiMeLa.Events）と公開モデル
    （PaPiMeLa.TextInput）の両方が参照するため。Events が TextInput を参照すると
    循環するので、共有される値型だけを下層に降ろしてある。

  NOT RESOLVED:
    本ユニットは第 11 章 #3 の一部。色型（TPMLColor / TPMLFColor）、TPMLPoint、
    演算子オーバーロード、レイアウト静的アサートは Video / Render 着手時に追加する。
    文節の色情報（IBus の foreground / background）も IBus 着手時に追加する。

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Types;

{$I papimela.inc}

interface

uses
  PaPiMeLa.Unicode;

type
  TPMLSubsystemTag = (
    Core, Platform, Video, Render, Audio, Input, TextInput, IO, Threading, Events
  );

  TPMLWindowID = LongWord;

  // 公開 API に specialize 構文を出さないための名前付き動的配列（§8.5）。
  TPMLStringArray = array of String;

  TPMLRect = record
    X, Y, W, H: Integer;
    class function Make(AX, AY, AW, AH: Integer): TPMLRect; static; inline;
    function IsEmpty: Boolean; inline;
  end;


  { 8 ビット 4 成分の色。並びは R, G, B, A で固定する。

    ピクセル形式（TPMLPixelFormat）が持つ並びとは独立で、変換は
    PaPiMeLa.Pixels の MapRGBA / GetRGBA が行う。ここは「色そのもの」の型。 }
  TPMLColor = record
    R, G, B, A: Byte;
    class function Make(AR, AG, AB: Byte; AA: Byte = 255): TPMLColor; static; inline;
    // $RRGGBB または $AARRGGBB。8 桁でなければ A は 255 にする。
    class function FromHex(AValue: LongWord; AHasAlpha: Boolean = False): TPMLColor; static;
    class function White: TPMLColor; static; inline;
    class function Black: TPMLColor; static; inline;
    class function Transparent: TPMLColor; static; inline;
    function Equals(const AOther: TPMLColor): Boolean; inline;
  end;
  TPMLColors = array of TPMLColor;

  { 0..1 の浮動小数点色。レンダラと色空間変換で使う。 }
  TPMLFColor = record
    R, G, B, A: Single;
    class function Make(AR, AG, AB: Single; AA: Single = 1.0): TPMLFColor; static; inline;
    class function FromColor(const AColor: TPMLColor): TPMLFColor; static; inline;
    function ToColor: TPMLColor;
  end;

  TPMLKeyModifier = (Shift, Ctrl, Alt, Super, CapsLock, NumLock);
  TPMLKeyModifiers = set of TPMLKeyModifier;

  // IME にキーを通したときの判定。Deferred は非同期返信待ち（§7.5）。
  TPMLKeyFilterResult = (Consumed, PassThrough, Deferred);

  // ---- IME（§7.3）

  // 文節の状態。かな漢字変換の下線表示を描き分けるために使う。
  TPMLSegmentState = (Unconverted, Converted, Focused);

  // バックエンドが報告した生の下線種別。State の根拠として保持する。
  TPMLUnderlineStyle = (None, Single, Double, Low, Error);

  TPMLCompositionSegment = record
    StartByte, EndByte: Integer;   // 変換中テキスト内の UTF-8 バイト範囲 [Start, End)
    StartChar, EndChar: Integer;   // 同じ範囲をコードポイント単位で
    State             : TPMLSegmentState;
    Underline         : TPMLUnderlineStyle;
    function TextOf(const AWhole: String): String;
  end;
  TPMLCompositionSegments = array of TPMLCompositionSegment;

  TPMLComposition = record
    Text                  : String;
    Segments              : TPMLCompositionSegments;
    CursorByte, CursorChar: Integer;   // -1 = 非表示
    FocusedSegment        : Integer;   // Segments の添字。-1 = なし
    SegmentsReliable      : Boolean;   // False = バックエンドが文節を提供しない
    function IsEmpty: Boolean;
    procedure Clear;
    // 文節のバイト範囲と State から、コードポイント位置と FocusedSegment を埋める。
    procedure Finalize;
  end;

  // TPMLEvent の固定部に載る変換中テキストの付随情報。
  TPMLTextEditingData = record
    CursorByte, CursorChar          : Integer;
    SelectionStartChar              : Integer;   // SDL 互換の単一範囲
    SelectionLengthChars            : Integer;
    FocusedSegment                  : Integer;
    SegmentsReliable                : Boolean;
  end;

  TPMLDeleteSurroundingData = record
    BeforeBytes, AfterBytes: Integer;
    BeforeChars, AfterChars: Integer;
  end;

  TPMLSubsystemTagHelper = type helper for TPMLSubsystemTag
    function ToString: String;
  end;

implementation

class function TPMLRect.Make(AX, AY, AW, AH: Integer): TPMLRect;
begin
  Result.X := AX; Result.Y := AY; Result.W := AW; Result.H := AH;
end;

function TPMLRect.IsEmpty: Boolean;
begin
  Result := (W <= 0) or (H <= 0);
end;

function TPMLCompositionSegment.TextOf(const AWhole: String): String;
begin
  if (EndByte <= StartByte) or (StartByte < 0) or (EndByte > Length(AWhole)) then
    Exit('');
  Result := Copy(AWhole, StartByte + 1, EndByte - StartByte);
end;

function TPMLComposition.IsEmpty: Boolean;
begin
  Result := Text = '';
end;

procedure TPMLComposition.Clear;
begin
  Text := '';
  Segments := nil;
  CursorByte := -1;
  CursorChar := -1;
  FocusedSegment := -1;
  SegmentsReliable := False;
end;

procedure TPMLComposition.Finalize;
var
  I: Integer;
begin
  FocusedSegment := -1;
  for I := 0 to High(Segments) do
  begin
    Segments[I].StartChar := UTF8ByteToCharOffset(Text, Segments[I].StartByte);
    Segments[I].EndChar   := UTF8ByteToCharOffset(Text, Segments[I].EndByte);
    if (FocusedSegment < 0) and (Segments[I].State = TPMLSegmentState.Focused) then
      FocusedSegment := I;
  end;
  if CursorByte >= 0 then
    CursorChar := UTF8ByteToCharOffset(Text, CursorByte)
  else
    CursorChar := -1;
end;

function TPMLSubsystemTagHelper.ToString: String;
begin
  case Self of
    TPMLSubsystemTag.Core      : Result := 'Core';
    TPMLSubsystemTag.Platform  : Result := 'Platform';
    TPMLSubsystemTag.Video     : Result := 'Video';
    TPMLSubsystemTag.Render    : Result := 'Render';
    TPMLSubsystemTag.Audio     : Result := 'Audio';
    TPMLSubsystemTag.Input     : Result := 'Input';
    TPMLSubsystemTag.TextInput : Result := 'TextInput';
    TPMLSubsystemTag.IO        : Result := 'IO';
    TPMLSubsystemTag.Threading : Result := 'Threading';
    TPMLSubsystemTag.Events    : Result := 'Events';
  else
    Result := 'Unknown';
  end;
end;


{ TPMLColor }

class function TPMLColor.Make(AR, AG, AB: Byte; AA: Byte): TPMLColor;
begin
  Result.R := AR;
  Result.G := AG;
  Result.B := AB;
  Result.A := AA;
end;

class function TPMLColor.FromHex(AValue: LongWord; AHasAlpha: Boolean): TPMLColor;
begin
  Result.R := Byte(AValue shr 16);
  Result.G := Byte(AValue shr 8);
  Result.B := Byte(AValue);
  if AHasAlpha then
    Result.A := Byte(AValue shr 24)
  else
    Result.A := 255;
end;

class function TPMLColor.White: TPMLColor;
begin
  Result := TPMLColor.Make(255, 255, 255, 255);
end;

class function TPMLColor.Black: TPMLColor;
begin
  Result := TPMLColor.Make(0, 0, 0, 255);
end;

class function TPMLColor.Transparent: TPMLColor;
begin
  Result := TPMLColor.Make(0, 0, 0, 0);
end;

function TPMLColor.Equals(const AOther: TPMLColor): Boolean;
begin
  Result := (R = AOther.R) and (G = AOther.G)
        and (B = AOther.B) and (A = AOther.A);
end;

{ TPMLFColor }

class function TPMLFColor.Make(AR, AG, AB: Single; AA: Single): TPMLFColor;
begin
  Result.R := AR;
  Result.G := AG;
  Result.B := AB;
  Result.A := AA;
end;

class function TPMLFColor.FromColor(const AColor: TPMLColor): TPMLFColor;
begin
  Result.R := AColor.R / 255.0;
  Result.G := AColor.G / 255.0;
  Result.B := AColor.B / 255.0;
  Result.A := AColor.A / 255.0;
end;

{ 0..1 の範囲外は切り詰める。レンダラの計算結果がはみ出すことがある。 }
function TPMLFColor.ToColor: TPMLColor;

  function Clamp8(AValue: Single): Byte;
  begin
    if AValue <= 0 then
      Result := 0
    else if AValue >= 1 then
      Result := 255
    else
      Result := Byte(Round(AValue * 255.0));
  end;

begin
  Result.R := Clamp8(R);
  Result.G := Clamp8(G);
  Result.B := Clamp8(B);
  Result.A := Clamp8(A);
end;

end.
