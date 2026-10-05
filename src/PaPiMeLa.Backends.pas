{
  PaPiMeLa.Backends — 具象バックエンドを全部リンクする

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §2.1、§11 #45

  WHAT:
    中身は uses だけ。並べたユニットはそれぞれの initialization で自分を
    登録する（PMLRegisterVideoBackend など）。アプリがこのユニット（または
    アンブレラの PaPiMeLa）を uses すると、papimela の持つバックエンドが
    全部使えるようになる。

  WHY:
    公開層（PaPiMeLa.Video など）が具象バックエンドを uses すると、使わない
    バックエンドまでリンクされる（設計 §2.1）。どれを持つかはアプリが決める。
    Wayland だけ、ダミーだけ、といった絞り込みは、このユニットの代わりに
    個別のユニットを uses すればよい。

  RESOLVED:
    - 試す順は各ユニットが登録する優先度で決まる。ここで並べる順は関係ない
    - ソフトウェアのレンダラと IME 無し（'none'）は登録の外で、公開層が常に持つ
}
unit PaPiMeLa.Backends;

{$I papimela.inc}

interface

uses
  PaPiMeLa.Video.Wayland,       // ビデオ 'wayland'
  PaPiMeLa.Video.Dummy,         // ビデオ 'dummy'（表示サーバ無し。既定では最後）
  PaPiMeLa.TextInput.Fcitx,     // IME 'fcitx'
  PaPiMeLa.TextInput.WaylandTI,  // IME 'wayland'（text-input-v3。Fcitx に繋がらないとき）
  PaPiMeLa.Render.GLES2;        // レンダラ 'gles2'

implementation

end.
