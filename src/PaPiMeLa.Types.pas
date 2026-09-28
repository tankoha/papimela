{
  PaPiMeLa.Types — 基本的な値型

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §8.3（幾何・色型）、§5.2（TPMLSubsystemTag）

  WHAT:
    サブシステムの識別タグと、IME 経路が必要とする最小の幾何型。

  NOT RESOLVED:
    本ユニットは第 11 章 #3 の一部にすぎない。色型（TPMLColor / TPMLFColor）、
    TPMLPoint / TPMLFPoint、演算子オーバーロード、レイアウト静的アサートは
    Video / Render 着手時に追加する。

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Types;

{$I papimela.inc}

interface

type
  // 例外がどの層で発生したかを示す。EPMLError の派生クラスが自分のタグを返す。
  TPMLSubsystemTag = (
    Core,
    Platform,
    Video,
    Render,
    Audio,
    Input,
    TextInput,
    IO,
    Threading,
    Events
  );

  TPMLRect = record
    X, Y, W, H: Integer;
    class function Make(AX, AY, AW, AH: Integer): TPMLRect; static; inline;
    function IsEmpty: Boolean; inline;
  end;

  TPMLKeyModifier = (Shift, Ctrl, Alt, Super, CapsLock, NumLock);
  TPMLKeyModifiers = set of TPMLKeyModifier;

  { IME にキーを渡すために必要な最小の情報。

    NOT RESOLVED:
      第 11 章 #13 / #14（Events）が TPMLKeyEventData の正式な定義を持つ。
      そこでは Scancode / Keycode / Repeat / Timestamp を含む完全な形になる。
      本レコードは IME 経路が先行実装されたための暫定版で、Events 着手時に
      Events 側へ移し、本ユニットからは取り除く。 }
  TPMLKeyEventData = record
    Keysym    : LongWord;        // X11 / XKB キーシム（Fcitx5 / IBus がこれで話す）
    Keycode   : LongWord;        // evdev + 8（X11 慣習）
    Modifiers : TPMLKeyModifiers;
    IsRelease : Boolean;
  end;

  TPMLSubsystemTagHelper = type helper for TPMLSubsystemTag
    function ToString: String;
  end;

implementation

class function TPMLRect.Make(AX, AY, AW, AH: Integer): TPMLRect;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.W := AW;
  Result.H := AH;
end;

function TPMLRect.IsEmpty: Boolean;
begin
  Result := (W <= 0) or (H <= 0);
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

end.
