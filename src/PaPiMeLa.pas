{
  PaPiMeLa — アンブレラ（uses PaPiMeLa 1 つで公開 API が揃う）

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §2.2、§11 #45

  WHAT:
    公開層のユニットの型・定数・関数を、この 1 つのユニットから使えるように
    並べ直す。あわせて PaPiMeLa.Backends を uses するので、papimela の持つ
    バックエンドが全部リンクされる。

      uses PaPiMeLa;

      var Ctx: TPMLContext;
      begin
        Ctx := TPMLContext.Create([TPMLSubsystem.Video]);
        ...

  WHY:
    Pong を書いたとき、アプリは papimela のユニットを 8 つ uses していた。
    どの型がどのユニットにあるかを使う側が覚える理由は無い。

  RESOLVED:
    - 並べ直しの中身（src/generated/umbrella_interface.inc と
      umbrella_implementation.inc）は tools/genumbrella.bb が公開層の
      ユニットの interface 部から作る。手で書くと、公開 API を足したときに
      ここへ足し忘れる。CI が `tools/genumbrella.bb --check` で古さを見る
    - 型は別名（TPMLContext = PaPiMeLa.Core.TPMLContext）。同じ型なので、
      個別のユニットを一緒に uses しても食い違わない
    - type helper は別名にできない（FPC が拒む。実測）。同じ対象への helper を
      元の helper から派生させて置く。派生した helper は元の機能を全部持つ
    - 関数は同じ引数（既定値も）で元を呼ぶだけの inline の関数を置く
    - バックエンドを書く人向けの API（PMLRegisterVideoBackend など）は
      並べない。登録済みの名前を問い合わせる関数（PMLVideoBackendNames など）
      は並べる
}
unit PaPiMeLa;

{$I papimela.inc}

interface

uses
  SysUtils, Classes,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core,
  PaPiMeLa.Events,
  PaPiMeLa.Events.Drop,
  PaPiMeLa.Events.Keymap,
  PaPiMeLa.Keycodes,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.Blit,
  PaPiMeLa.Surface.BMP,
  PaPiMeLa.IO,
  PaPiMeLa.Video,
  PaPiMeLa.Clipboard,
  PaPiMeLa.Atomic,
  PaPiMeLa.Threading,
  PaPiMeLa.Video.Backend,
  PaPiMeLa.Render,
  PaPiMeLa.TextInput,
  PaPiMeLa.TextInput.Backend,
  PaPiMeLa.Time,
  PaPiMeLa.App,
  PaPiMeLa.Backends;

{$I generated/umbrella_interface.inc}

implementation

{$I generated/umbrella_implementation.inc}

end.
