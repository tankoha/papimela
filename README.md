# papimela

**F**ree **Pa**scal com**p**lete si**m**ple direct**me**dia **la**yer —
a reimplementation of SDL3 in Object Pascal.

Not a binding. Not a wrapper. There is no code here that calls SDL's C API.

---

## English

### Why

SDL is remarkable. It has been carrying games and tools across every platform
that matters for nearly thirty years, and it does it in C.

What struck me, reading it, is that **SDL is object-oriented code written in C**.
`SDL_VideoDevice` is an object: it has state, and it has ninety-eight function
pointers hanging off it — that is a vtable, spelled out by hand. `SDL_Renderer`
has a driver with thirty-five entry points, which is an abstract base class.
Surfaces, textures, audio streams: all of them are objects, constructed and
destroyed through paired functions, with their internals hidden behind a
`void *internal`.

The design is object-oriented. The language just doesn't say so out loud.

So the question I wanted to answer was: what happens if you write the same
design in a language that *does* say it out loud?

### Why Object Pascal

C++ was the obvious answer and I didn't want it.

That's a taste, not an argument, and I'll admit it as such. C# would have been
perfectly fine — the object model is clean, the tooling is good, and most of
what follows would have been the same. I picked Object Pascal because it gives
me classes, interfaces, properties and exceptions without asking me to hold
several other things in my head at the same time, and because Free Pascal
compiles to a native binary that links against C libraries without ceremony.

For a project whose whole point is *restructuring*, the language mostly needs
to stay out of the way. Object Pascal does.

### What it actually is

Linux and Wayland only, core features only. The scope is deliberately narrow so
that the restructuring is the interesting part rather than the porting volume.

The god object is the thing being taken apart. `SDL_VideoDevice` — ninety-eight
function pointers, with `static SDL_VideoDevice *_this` dereferenced 456 times
across the codebase — becomes three abstract classes (`TPMLVideoBackend`,
`TPMLDisplayBackend`, `TPMLWindowBackend`) plus a capability set. Backends never
see the public window type; they identify windows by ID through a sink
interface. The ownership graph is expressed in the type system instead of in
comments.

One part is not a port at all. SDL's `SDL_EVENT_TEXT_EDITING` carries a single
selection range, which is enough for Latin scripts and not enough for Japanese:
when you convert 「今日の東京株式市場」 the IME splits it into clauses and
highlights the one you are editing, and SDL has nowhere to put that. papimela
talks to fcitx5 over D-Bus directly and carries **every clause boundary**, the
surrounding text, and delete-surrounding requests. This is verified against a
real keyboard, not just a test harness:

```
変換中: [なんか]<変なタイミングで>   （2 文節、[ ] が注目）
```

Wayland's `text-input-v3` cannot express this — it removed preedit styling — so
the D-Bus route is not an optimisation, it is the only way.

### State

Roughly 20,000 lines across 27 hand-written units and 21 generated Wayland
protocol units. Working: Wayland windows and rendering to `wl_shm`, the seat
(keyboard with xkb, pointer, touch, pointer constraints, cursor shapes),
the event queue, the IME path through fcitx5, pixel formats, surfaces, BMP,
blitters, and a headless video backend so tests can run without a display
server.

13 test programs, 352 assertions, all passing. CI runs a static analyser in its
strictest mode (one warning fails the build), checks that the class diagrams
still match the code, checks that every file's stated provenance matches the
design document, and runs the tests that don't need a screen.

Not done yet: the renderer, GL, audio, joystick, and everything in the design
document's later chapters.

### Building

```bash
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib src/PaPiMeLa.Core.pas
```

FPC 3.2.2. `docs/DESIGN.md` is the design; `docs/TEST-LOG.md` records what has
actually been run; `docs/DEFECTS.md` lists every defect found so far, fixed ones
included, because the ones already fixed are the ones most likely to come back.

### A closing thought

Having spent this long pulling a hand-rolled vtable apart and putting it back
together as a class hierarchy, I keep arriving at the same place.

**Surely we do need inheritance after all?**

---

## 日本語

### なぜ

SDL はすごい。三十年近く、あらゆるプラットフォームでゲームとツールを運び続けて
いて、しかもそれを C でやっている。

読んでいて感心したのは、**SDL が C で書かれたオブジェクト指向のコードだ**という
ことだった。`SDL_VideoDevice` はオブジェクトである。状態を持ち、98 個の関数
ポインタをぶら下げている。手で書いた vtable そのものだ。`SDL_Renderer` は
35 個の入口を持つドライバを従えていて、これは抽象基底クラスである。サーフェス、
テクスチャ、オーディオストリーム。どれも対になった関数で生成・破棄され、中身は
`void *internal` の向こうに隠されたオブジェクトだ。

設計はオブジェクト指向になっている。言語がそう言わないだけで。

だから確かめたくなった。同じ設計を、**そうだと言える言語**で書いたらどうなるのか。

### なぜ Object Pascal か

C++ が当然の答えで、それが嫌だった。

理屈ではなく好みである。そこは認める。C# でも別に良かった。オブジェクトモデルは
素直だし道具も揃っているし、この先に書くことの大半は同じになっただろう。
Object Pascal にしたのは、クラスとインターフェースとプロパティと例外を、
他のいろいろを同時に頭に置かずに使えるからで、Free Pascal がネイティブバイナリを
吐いて C のライブラリに素直にリンクするからだ。

**作り直すこと自体が目的**のプロジェクトでは、言語は邪魔をしないでいてくれれば
それでいい。Object Pascal は邪魔をしない。

### 実際のところ何なのか

Linux と Wayland だけ、コア機能だけ。範囲を意図的に狭くしてある。移植の分量では
なく作り直しの方を面白いところにしたいからだ。

分解の対象は god object である。`SDL_VideoDevice` は 98 個の関数ポインタを持ち、
`static SDL_VideoDevice *_this` がコード全体で 456 回参照されている。これを
3 つの抽象クラス（`TPMLVideoBackend` / `TPMLDisplayBackend` /
`TPMLWindowBackend`）と能力集合に分ける。バックエンドは公開層のウィンドウ型を
一切知らず、シンクインターフェース越しに ID でウィンドウを識別する。
所有関係はコメントではなく型で表す。

ひとつだけ、移植ですらない部分がある。SDL の `SDL_EVENT_TEXT_EDITING` が運べる
のは単一の選択範囲で、ラテン文字には足りるが日本語には足りない。
「今日の東京株式市場」を変換すると IME は文節に分け、編集中の文節を強調するが、
SDL にはそれを置く場所が無い。papimela は fcitx5 と D-Bus で直接話し、
**全文節の区切り**と周辺テキストと周辺削除要求を運ぶ。実際のキーボードで確認済み
である。

```
変換中: [なんか]<変なタイミングで>   （2 文節、[ ] が注目）
```

Wayland の `text-input-v3` ではこれは表現できない（preedit のスタイル指定が
削られている）。D-Bus 直結は最適化ではなく、唯一の道である。

### 現状

手書き 27 ユニットと生成した Wayland プロトコル 21 ユニット、およそ 2 万行。
動いているのは、Wayland のウィンドウと `wl_shm` への描画、シート（xkb を使った
キーボード、ポインタ、タッチ、ポインタ拘束、カーソル形状）、イベントキュー、
fcitx5 経由の IME、ピクセル形式、サーフェス、BMP、ブリッタ、そして表示サーバ
無しでテストを回すためのヘッドレスバックエンド。

テストは 13 本、352 アサーション、全て成功。CI は静的解析を最も厳しい設定で
回し（warning 1 件でビルドが落ちる）、クラス図がコードと食い違っていないかを
確かめ、各ファイルが名乗っている由来が設計書と一致するかを確かめ、画面の要らない
テストを実行する。

まだ無いもの: レンダラ、GL、オーディオ、ジョイスティック、設計書の後ろの章に
あるもの一式。

### ビルド

```bash
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib src/PaPiMeLa.Core.pas
```

FPC 3.2.2。`docs/DESIGN.md` が設計、`docs/TEST-LOG.md` が実際に何を走らせたかの
記録、`docs/DEFECTS.md` がこれまでに見つけた不具合の全件である。修正済みのものも
載せてあるのは、**一度直したものが一番戻ってきやすい**からだ。

### 最後に

手書きの vtable を分解してクラス階層に組み直す作業をこれだけ続けてきて、
いつも同じところに行き着く。

**やっぱり継承は必要では？**

---

## License

zlib, the same as SDL. See [LICENSE](LICENSE).

papimela does not contribute back to SDL: SDL states that it does not accept
AI-generated contributions, and parts of this project are AI-assisted. Bugs
found in SDL while reading it are recorded in `docs/DEFECTS.md` and not
reported upstream.

SDL には貢献を返さない。SDL は AI 生成物の貢献を受け付けない方針を明示しており、
このプロジェクトには AI の手が入っているためである。読んでいて見つけた SDL の
不具合は `docs/DEFECTS.md` に記録するだけで、上流には報告しない。
