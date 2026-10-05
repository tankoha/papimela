# 引き継ぎ資料

新しいセッションは、`CLAUDE.md` の次にこれを読む。最終更新: 2026-10-05（#45 のコミット `31d4d09` の次）。

> **2026-10-05 の手元のセッションで**: クラウドの作業（ブランチ `claude/zen-mayer-sjyn3o`）を**早送りで `master` に入れた**
> （持ち主の判断）。§5.1 の手元の検査のうち自動で判定できるものはすべて通った（23 本・724 件、`docs/TEST-LOG.md` の冒頭）。
> 対話の確認（`demo_japanese_input`、`demo_pointer_constraints`、Pong）も 2026-10-06 に持ち主が済ませ、すべて想定どおりだった
> （`docs/TEST-LOG.md` の冒頭と T-09 の節）。**手元の確認は残っていない。** 次は §3 の候補と §8 の保留中の判断へ。

## 1. 今どこにいるか

| 項目 | 状態 |
|---|---|
| リポジトリ | https://github.com/tankoha/papimela（公開、Issues 有効）。手元のセッションは `master` に直接 push、クラウドのセッションは指定のブランチへ push して、手元で早送りマージする |
| CI | 緑。rawpaco 激辛、checkorigin、アンブレラの古さ（`genumbrella.bb --check`）、図の検査、表示サーバ無しのテスト 12 本、Pong の自己検査、GLES2 と ソフトウェアのドライバの画素比較（llvmpipe）。ジョブ 60 分・GLES2 の手順 5 分の時間制限つき |
| テスト | 23 本、724 件、すべて成功（`docs/TEST-LOG.md`。2026-10-05 に手元の実機で全部流し直した） |
| 不具合 | 45 件。うち上流 SDL の 4 件（D-18、D-36、D-38、D-42）は未報告（方針は `CLAUDE.md`） |
| 規模 | 手書き 42 ユニット + 生成（Wayland プロトコル 21、キーボードの表 2、EGL / GLES2 の定数 2、DebugText の字形 1、アンブレラ 2）。約 3 万行 |

### 動いているもの

Wayland のウィンドウ（xdg-shell、configure の往復、最大化・最小化、隠す・出す）、シート
（xkb のキーボード、ポインタ、タッチ、ポインタ拘束、カーソル形状）、キーボードの状態と
SDL と同じ値のスキャンコード・キーコード（配列ごとのキーマップ）、イベントキュー、
fcitx5 経由の IME（全文節・周辺テキスト・周辺削除）、ピクセル形式、サーフェス、BMP、
ブリッタ、レンダラ（ソフトウェアと OpenGL ES 2.0。どちらもウィンドウへ VSync つき。拡大率、論理解像度 5 方式、
ウィンドウ座標との変換、DebugText）、
EGL の GL コンテキスト、ヘッドレスのダミーのビデオ、待つ API（Delay / DelayNS / DelayPrecise）、
バックエンドの登録（`PaPiMeLa.Backends`）、アンブレラ（`uses PaPiMeLa`）、`TPMLApplication`、サンプルの Pong。

### 設計書第 11 章の進み具合

済み（一部を含む）: #1–4、#10、#12–17（#17 の `.GL` は未）、#22、#24（`Events.Keymap`。押下状態は
`PaPiMeLa.Events` の `TPMLKeyboardState`）、#25 の一部（マウスとタッチの状態機械は `PaPiMeLa.Events`）、
#26–29、#31–37（#32 の `.Clipboard` は未）、#39、#41–43（#41 の残りは描画先テクスチャ、回転、9-grid / タイル）、
#45、#46、#47、#48、#49、#50、#64、#70。

未着手: #5–8（Log、Properties、Atomic、Threading）、#9 Time のタイマー（待つ API は済み）、#11、#18–21、#23、#30、#38、#40、#44、
#51–63（オーディオ、ジョイスティック、ゲームパッド、ハプティクス）、#65–69。

## 2. 前のセッション（2026-10-02〜05）でしたこと

クラウドのセッション。4 つのコミット（すべて `claude/zen-mayer-sjyn3o`）:

| コミット | 内容 | 担当 | 検査 |
|---|---|---|---|
| `d6970e5` | **論理解像度（5 方式）・拡大率・ウィンドウ座標との変換・DebugText**（#41、F-4 / F-5）。字形の生成器 `tools/gendebugfont.bb`。Pong を書き換え | Opus | T-23（49 件）を先に書いた。**SDL を実際に作って同じ 26 場面を描き、画素で比べた**（20 場面一致、残りは理由が分かっている）。GLES2 との比較に 4 場面 |
| `fa46f49` | 合成の丸めのコメントの誤りを直した（D-44） | Opus | — |
| `8835f76` | **待つ API**（`PaPiMeLa.Time`：Delay / DelayNS / DelayPrecise、#9 の一部、F-6）と **Context のオプションを record に**（F-7） | Time は Sonnet、F-7 は Opus | T-24（18 件）、T-11 に 5 件 |
| `31d4d09` | **バックエンドの登録・`PaPiMeLa.Backends`・アンブレラ `PaPiMeLa`・`TPMLApplication`**（#45） | Sonnet（interface と検査は Opus） | T-25（29 件）、T-26（33 件） |

見つけた不具合: D-42（SDL の DebugText が U+00BE〜U+00FF を「字形無し」で描く。SDL を作って実測）、
D-43（ソフトウェアのドライバがテクスチャの変調色を実行時に読んでいた）、D-44（上の丸めのコメント）、
D-45（検査で `setitimer` へ `const` の record を渡し、C に NULL が届いていた。Sonnet が strace で発見）。

このセッションで分かったこと・やり方:

- **SDL の実物を作って比べる**のが強い。表示サーバ無しで静的に作れる（§5）。手で求めた期待値の誤り
  （ブレゼンハムの辿り方）と、ヘッダのコメントの誤り（字形の絵が左右逆）も、実物で決着した
- **Sonnet は検査の誤りも見つけてくる**（#9 で 2 件、#45 でコメントの入れ子 1 件）。言われたら
  鵜呑みにせず、自分で辿り直して確かめてから直す（今回は 3 件とも正しかった）
- 突然変異（わざと誤りを入れて検査が落ちるか）を毎回やった。#41 で 9 通り、#9 で 6 通り、#45 で 9 通り。
  **1 つ目で歯の無い検査が見つかった**（終点を描く規則。閉じた枠しか描いていなかった）
- FPC の実測: record の `class operator Initialize` は 3.2.2 で効く（ただし「初期化されていない」の警告は出る）。
  **type helper は別名にできない**（派生させて置く）。cdecl の `const` の record は値渡しになる
- アンブレラの導入で、**具象バックエンドは uses したものだけが使える**ようになった。手元専用の
  プログラムは必要なものを uses しているか、実行ファイルのクラス名で確かめた（`demo_render_window` の
  gles2 が壊れるところだったのを直した）

## 3. 次の候補（おすすめ順）

1. **クリップボード（#38、Medium）**。IME は IBus（#48）・text-input-v3（#49）とも 2026-10-06 に済んだ。
   IME の残り: 埋め込み候補（`TextEditingCandidates`）、IBus の ForwardKeyEvent、ibus-anthy など他のエンジンの属性の実測、GNOME / KDE での IBus 直結（§7.5 の要検証）。IBus の検査環境は `tools/ibus-sandbox/`（ibus + ibus-mozc を入れた Ubuntu 24.04 の最小 rootfs を bwrap で隔離。デスクトップの fcitx5 と混ざらない）。実測の結果は `spikes/RESULTS.md` のスパイク 3
2. **Threading（#8、High）**: これが済むと #9 のタイマー（`AddTimer`）と `RunOnMainThread` に進める
3. **レンダラの残り（#41）**: 描画先テクスチャ（SetRenderTarget。テクスチャごとの view が要るので、
   今レンダラに直接持っている拡大率・論理解像度のフィールドを record にまとめるところから）、回転、9-grid / タイル
4. **オーディオ（#51 以降）**: 大きな段階。PipeWire から

済んだもの（2026-10-02）: 論理解像度と DebugText（F-4 / F-5）、待つ API（F-6、#9 の一部）、
Context のオプションを値型に（F-7）、アンブレラ・バックエンドの登録・TPMLApplication（#45）。
Pong もすべて書き換え、今は `uses SysUtils, Math, PaPiMeLa` だけで書ける。

## 4. 定着した進め方

- **担当**: 第 11 章の難易度列のとおり。Low は qwen2.5-coder:14b（手元の ollama）、Medium は
  Sonnet のサブエージェント、High は Opus。詳しい手順は `CLAUDE.md`
- **検査を先に書く**: 公開 API・interface 部・受け入れ検査をこちらで書き、空の実装で失敗する
  ことを確かめてから実装に渡す（qwen にも Sonnet にも）
- **検査の歯を確かめる**: 誤りをわざと戻して落ちることを `fpc -B` で確かめる。縮む向きの
  検査はヒープが同じ番地を返して偶然通ることがある（T-17）。解放済みの領域は偶然元の値を
  保つことがあるので、画素ではなく状態（キューが空になったか等）で見る（D-39）
- **大きな表は生成器で**: 手でも qwen でも写さない。件数を元と突き合わせる
- **実測してから書く**: 記憶や推測で断定しない。違ったら訂正を記録に残す
  （`docs/DEFECTS.md`、`docs/TEST-LOG.md` の使い捨て検証）
- コミットはこちらが作り、`master` へ push、CI を最後まで見る（クラウドのセッションでは指定された
  ブランチへ）。コミットの末尾は `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- **SDL の挙動を写すときは、写した結果を SDL の実物と画素で比べる**（§5 の作り方。比べる場面は
  `docs/TEST-LOG.md` の使い捨て検証にある）

## 5. 検査の流し方

表示サーバ無しで通るもの（CI と同じ）:

```bash
for t in test_dummy_video test_pixels test_io test_surface test_blit test_render test_render_window test_render_logical test_time test_keyboard test_textinput_v3 test_ime_keys test_ibus_model test_backends test_umbrella; do
  fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/$t test/$t.pas && ./test/$t
done
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -oexamples/pong examples/pong.pas && ./examples/pong --selftest
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_render_gles2 test/test_render_gles2.pas
env -u WAYLAND_DISPLAY LIBGL_ALWAYS_SOFTWARE=1 ./test/test_render_gles2   # Mesa の EGL が要る
```

**手元専用**（Wayland セッション、GPU、fcitx5 が要る。クラウドでは走らない）:
`test_wayland_protocols`、`test_wayland_window`、`test_pointer_constraints`、`test_touch_cursor`、
`test_fcitx_textinput`、`test_key_routing`、`test_wayland_textinput`、`test_gl_window`、`test_render_gles2` のウィンドウの区間、
スパイク 2 本、対話のデモ（`demo_japanese_input`、`demo_pointer_constraints`、`demo_render_window`）。

**IBus の隔離環境**（`tools/ibus-sandbox/setup.sh` を一度。CI でも同じ検査がランナーの上で走る）:
`tools/ibus-sandbox/run.sh sh -c 'mkdir -p /tmp/lib && fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FU/tmp/lib -o/tmp/t test/test_ibus_textinput.pas && /tmp/t'`

### 5.1 手元で流す検査（2026-10-05〜06 に手元で流した。自動の分も対話の分もすべて合格）

前回手元で流したのは 2026-10-02 の朝（`1ae1bdd` の時点）。その後の変更で手元専用の検査に効くもの:
**バックエンドの選び方が登録制になった**（#45。全部のプログラムに効く）、Context のオプション（F-7）、
レンダラの論理解像度・拡大率（描画の座標の通り道が変わった）、`TPMLTimerService` の class 関数化。

```bash
cd papimela && mkdir -p lib
B='fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib'
# 0. 表示サーバ無しの分（CI と同じ。手元の新しい Mesa でも通るか）
for t in test_dummy_video test_pixels test_io test_surface test_blit test_render test_render_window test_render_logical test_time test_keyboard test_textinput_v3 test_ime_keys test_ibus_model test_backends test_umbrella; do
  $B -otest/$t test/$t.pas && ./test/$t | tail -1
done
# 1. 実機の Wayland（自動判定。最後の行が「結論」で終わればよい）
for t in test_wayland_protocols test_wayland_window test_pointer_constraints test_touch_cursor test_gl_window test_render_gles2; do
  $B -otest/$t test/$t.pas && ./test/$t | tail -1
done
# 2. fcitx5（fcitx5-mozc を起動しておく）
for t in test_fcitx_textinput test_key_routing; do $B -otest/$t test/$t.pas && ./test/$t | tail -1; done
# 3. スパイク
$B -ospikes/spike1_wayland spikes/spike1_wayland.pas && ./spikes/spike1_wayland | tail -1
$B -ospikes/spike2_fcitx spikes/spike2_fcitx.pas && ./spikes/spike2_fcitx | tail -1
# 4. 計測と対話のデモ
$B -otest/demo_render_window test/demo_render_window.pas
./test/demo_render_window 5 vsync 640x400 software
./test/demo_render_window 5 novsync 640x400 software
./test/demo_render_window 5 vsync 640x400 gles2       # #45 で GLES2 を明示的にリンクするよう直した
$B -otest/demo_japanese_input test/demo_japanese_input.pas && ./test/demo_japanese_input 30
$B -otest/demo_pointer_constraints test/demo_pointer_constraints.pas && ./test/demo_pointer_constraints 60
$B -oexamples/pong examples/pong.pas && ./examples/pong
```

見るところ:

| 対象 | 確かめること | 関わる変更 |
|---|---|---|
| どのプログラムも | 起動時のログが `video backend: wayland`（`dummy` ではない）、IME を使うものは `text input backend: fcitx`。「not available」「no ... registered」で断られたら uses の付け忘れ | #45 |
| `test_render_gles2` | 窓の区間まで通る（GL のウィンドウで既定のドライバが `gles2` に選ばれる）。オフスクリーンは radeonsi でも 24 件 | #45 の登録、#41 の 4 場面 |
| `demo_render_window` | 3 通りとも動く。vsync で画面の 200 Hz 前後、novsync でそれより速い。`gles2` が「not available」にならない | #45 |
| `demo_japanese_input` | 変換中の文節と確定文字列が届く（T-07 と同じ） | #45（fcitx の登録）、F-7 |
| Pong | ウィンドウの大きさを変えると帯付きで追従する、得点が文字で出る、P で一時停止の文字が出る、VSync で滑らか、CPU が 1 コアを使い切らない（`top` で見る） | #41 論理解像度・DebugText、F-6 |

結果は `docs/TEST-LOG.md` の各行（最終実行の日付と件数）へ。落ちたら `docs/DEFECTS.md` へ。

静的検査:

```bash
../rawpaco/src/rawpaco --fail-on=warning src/*.pas src/generated/*.pas test/*.pas spikes/*.pas tools/*.pas examples/*.pas
./tools/checkorigin.bb
./tools/check-diagrams.sh
```

### CI だけで起きることを手元で再現する

CI は Ubuntu 24.04（Mesa 25.2.8、LLVM 20）。手元が新しいと再現しないことがある（D-40）。
root 無しで 24.04 を作れる:

```bash
D=<作業用のディレクトリ>
curl -sSfO https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.5-base-amd64.tar.gz
mkdir -p $D/root && tar -xzf ubuntu-base-24.04.5-base-amd64.tar.gz -C $D/root --no-same-owner --exclude='./dev/*'
bwrap --bind $D/root / --dev /dev --proc /proc --tmpfs /tmp --ro-bind /etc/resolv.conf /etc/resolv.conf \
  --bind "$PWD" /work --unshare-user --uid 0 --gid 0 --share-net --unsetenv WAYLAND_DISPLAY \
  sh -c 'apt-get -o APT::Sandbox::User=root update && apt-get -o APT::Sandbox::User=root install -y fpc libegl1 libgles2 libegl-mesa0 libgl1-mesa-dri'
```

man-db などの設定は所有者の切り替えで失敗するが、`dpkg -r --force-depends man-db` と
`dpkg --configure -a` で検査には足りる状態になる。bwrap は呼ぶたびに `/tmp` を空にするので、
ユニットの出力先は毎回作る。

## 6. 作業環境

| もの | 場所・備考 |
|---|---|
| FPC | 3.2.2（CI も同じ） |
| rawpaco | `../rawpaco`（https://github.com/tankoha/rawpaco。`make` で作る）。CI は `main` を取る |
| SDL のソース | `reference/SDL`（gitignore 済み）。版と取り直し方は `docs/ORIGIN.md` |
| Babashka | 生成器と checkorigin と qwen-gen が使う |
| SDL の実物 | 移植の結果を SDL と画素で比べるときに作る。表示サーバ無しで静的に作れる: `cmake -G Ninja -S reference/SDL -B <作業用> -DSDL_UNIX_CONSOLE_BUILD=ON -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF` に、使わないもの（`-DSDL_AUDIO=OFF` など）を足す。`SDL_CreateSoftwareRenderer` でサーフェスへ描けば比べられる（`docs/TEST-LOG.md` の使い捨て検証） |
| qwen | 手元の ollama の `qwen2.5-coder:14b`。呼び出しは `tools/qwen-gen.bb`。**クラウドには無い**ので、Low の作業は手元に戻るか、Sonnet に回す |
| クラウドのセッション | 毎回まっさらな Ubuntu 24.04（root）。最初に揃える: `apt-get install -y fpc libegl1 libgles2 libegl-mesa0 libgl1-mesa-dri`、`git clone https://github.com/tankoha/rawpaco.git ../rawpaco && make -C ../rawpaco`、`docs/ORIGIN.md` の手順で `reference/SDL`、Babashka は `curl -sSL https://raw.githubusercontent.com/babashka/babashka/master/install \| bash`。SDL の実物を作るなら `cmake ninja-build` も（入っていた）。GitHub の CI の状態は `https://api.github.com/repos/tankoha/papimela/actions/runs?head_sha=<コミット>` で読める |
| 手元の機械 | labwc（Wayland）、画面 DP-3 2560x1080 200 Hz、Radeon RX 9070 + 内蔵 Raphael、Mesa 26.0.8、Ubuntu 26.04、fcitx5-mozc |

## 7. 落とし穴（詳しくは `docs/DEFECTS.md` の「傾向」）

- Pascal は**識別子の大文字小文字を区別しない**（`px` と `PX`、`KEY_g` と `KEY_G` は同じ名前）
- **`and` は `or` より、`or` は比較より先に結合する**。比較はすべて括弧で閉じる
- **同じ秒に書き戻したソースは再コンパイルされない**ことがある。差し替えて比べるときは `fpc -B`
- FPC は**値を指定した列挙を配列の添字に使えない**。予約語の名前は `&END` のように書ける
- **FPC は浮動小数点の例外を有効にしている**。C のライブラリを呼ぶときは無効が前提（D-40）
- `eglGetError` は読むと消える（D-38）。Mesa の `eglGetProcAddress` は無い `gl*` 関数にも番地を返す
- xdg-shell でアンマップしたら configure をやり直す（D-37）
- `Check(条件, Format(…))` の `Format` は条件より先に評価される
- `perl -0pi` の置換は、アンカーの字下げが 1 つ違うだけで合わない。`or die` で失敗を知る
- 「環境が無ければ飛ばす」検査は、空の実装を通してしまう
- **具象バックエンドは uses したものだけが使える**（#45）。Wayland や fcitx や GLES2 を使うプログラムは `PaPiMeLa`（アンブレラ）か `PaPiMeLa.Backends` を uses する。忘れると実行時に「登録されていない」と断られる（コンパイルは通る）
- 公開層の interface 部を変えたら `tools/genumbrella.bb` で作り直す（CI の `--check` が落ちる）。type helper は別名にできない
- C の関数へ構造体を渡すときは `const` の record でなくポインタで宣言する（cdecl の `const` は値渡しになる。D-45）
- レンダラは描画を**積んでから実行する**。積んだ後に変えられる値（テクスチャの変調色など）は積むときに写す（D-43。D-39 も同じ隙間）

## 8. 保留中の判断（利用者に聞く）

- SDL の不具合 D-36、D-38、D-42 を README の「SDL にバグ報告を返すべきか」の節に足すか（今は D-18 だけ）
- ソフトウェアのブリッタの半透明の丸めが SDL と 1 違う（SDL は切り捨てで `0x9f`、papimela は四捨五入で `0xa0`。D-44）。
  SDL に揃えるか。揃えるなら T-15 の参照実装と T-22 の許容差も見直す
- GL を使うと浮動小数点の例外が無効になること（D-40）を README にも書くか
- Sonnet が挙げた SDL の怪しい点 3 つ（スワップ間隔が全体で 1 つ、EGL 1.5 をちょうど 1.5 で判定、
  面が無いときに成功を返す MakeCurrent）は**まだ確かめていない**。確かめるまで不具合一覧に載せない
- D-40 の「止まる」側の仕組み（llvmpipe の作業スレッドで例外が起きる）は推測のまま
