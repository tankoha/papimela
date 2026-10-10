# 引き継ぎ資料

新しいセッションは、`CLAUDE.md` の次にこれを読む。最終更新: 2026-10-10（#5 Log・#6 Properties とヒントのコミット `84fd159` の次）。

> **2026-10-10 の手元のセッションで**: §8 の保留中の判断を持ち主に聞いて片付け（README に SDL の不具合 3 件と浮動小数点の
> 例外を足した、D-44 の丸めは四捨五入のまま、Sonnet の疑い 3 つを実物で確かめた）、見つかった D-53（スワップ間隔）を
> papimela 側で直し、#5・#6 を入れた。表示サーバ無しの 26 本はすべて通り、手元専用は GL の 3 本だけ流し直した
> （`docs/TEST-LOG.md` の冒頭）。**手元の対話の確認は残っていない。** 次は §3 の候補と §8 の保留中の判断へ。

## 1. 今どこにいるか

| 項目 | 状態 |
|---|---|
| リポジトリ | https://github.com/tankoha/papimela（公開、Issues 有効）。手元のセッションは `master` に直接 push、クラウドのセッションは指定のブランチへ push して、手元で早送りマージする |
| CI | 緑。rawpaco 激辛、checkorigin、アンブレラの古さ（`genumbrella.bb --check`）、図の検査、表示サーバ無しのテスト 26 本、Pong の自己検査、GLES2 と ソフトウェアのドライバの画素比較（llvmpipe）。ジョブ 60 分・GLES2 の手順 5 分の時間制限つき |
| テスト | 表示サーバ無しの 26 本・1043 件はすべて成功（2026-10-10 に手元で作り直して全部流した）。手元専用と対話の検査は `docs/TEST-LOG.md` の各行 |
| 不具合 | 57 件。うち上流 SDL の 9 件は未報告（D-53 は SDL 自身が FIXME で知っている。他の 8 件は報告するかを検討中。方針は `CLAUDE.md`） |
| 規模 | 手書き 52 ユニット（`src/*.pas`）+ 生成（Wayland プロトコル 21、キーボードの表 2、EGL / GLES2 の定数 2、DebugText の字形 1、アンブレラ 2）。約 4.2 万行 |

### 動いているもの

Wayland のウィンドウ（xdg-shell、configure の往復、最大化・最小化、隠す・出す）、シート
（xkb のキーボード、ポインタ、タッチ、ポインタ拘束、カーソル形状）、キーボードの状態と
SDL と同じ値のスキャンコード・キーコード（配列ごとのキーマップ）、イベントキュー、
IME（fcitx5・IBus・text-input-v3。全文節・周辺テキスト・周辺削除）、ピクセル形式、サーフェス、BMP、
ブリッタ、レンダラ（ソフトウェアと OpenGL ES 2.0。どちらもウィンドウへ VSync つき。拡大率、論理解像度 5 方式、
ウィンドウ座標との変換、DebugText、回転・反転・平行四辺形・敷き詰め・9 つ分け、描画先テクスチャ）、
クリップボードとプライマリ選択、ドラッグ＆ドロップ（受信と、こちらから始めるドラッグ。Flatpak 向けの document-portal も）、
EGL の GL コンテキスト（スワップ間隔はコンテキストごと）、ヘッドレスのダミーのビデオ、待つ API・タイマー・スレッド・不可分操作、
**ログ（`Ctx.Log`）・ヒント（`Ctx.Hints`、`PAPIMELA_LOGGING` など）・プロパティの表（`TPMLProperties`、`Ctx.Properties`）**、
バックエンドの登録（`PaPiMeLa.Backends`）、アンブレラ（`uses PaPiMeLa`）、`TPMLApplication`、サンプルの Pong。

### 設計書第 11 章の進み具合

済み（一部を含む）: #1–10、#12–17（#17 の `.GL` は未）、#22、#24（`Events.Keymap`。押下状態は
`PaPiMeLa.Events` の `TPMLKeyboardState`）、#25 の一部（マウスとタッチの状態機械は `PaPiMeLa.Events`）、
#26–29、#31–39、#41–43（#41 の残りは YUV・パレット・PIXELART などのテクスチャの種類）、
#45、#46、#47、#48、#49、#50、#64、#70、#71。

未着手: #11、#18–21、#23、#30、#40、#44、
#51–63（オーディオ、ジョイスティック、ゲームパッド、ハプティクス）、#65–69。

## 2. 前のセッション（2026-10-10、手元）でしたこと

| コミット | 内容 | 担当 | 検査 |
|---|---|---|---|
| `2572a2d` | README に SDL の不具合 3 件（D-36、D-38、D-42）と、GL で浮動小数点の例外が無効になること（D-40）を載せた。D-44 は四捨五入のまま（持ち主の判断） | Opus | — |
| `57c42f1` | Sonnet の疑い 3 つを SDL の実物で確かめた。スワップ間隔が全体で 1 つ（**D-53**）は本物、EGL 1.5 の判定と面無しの MakeCurrent は不具合ではない | Opus | 使い捨て検証 |
| `1c17b36` | **スワップ間隔をコンテキストごとに**（D-53。持ち主の判断）。途中で、Wayland の Restore が最小化を解けないことを測って確かめた | Opus | T-21 に 7 件（先に書き、直す前に 4 件落ちた。変異 3 通り） |
| `84fd159` | **Log（#5）・Properties とヒント（#6）**。Context が Log・Hints・Properties を持つ。SDL の誤り 4 つ（D-54〜D-57）を見つけ、papimela では直した | API・検査・Context への組み込みは Opus、実装は qwen を Opus が直した（解析 3 関数は書き直し） | T-45（95 件）、T-46（46 件）。空の実装で 75 件・42 件落ちた。変異 19 通り（18 通りが捕まる） |

このセッションで分かったこと・やり方:

- **SDL の実物は、作らなくても手元にある**: Ubuntu 26.04 に SDL 3.4.2 の共有ライブラリ（`/usr/lib/x86_64-linux-gnu/libSDL3.so.0`）
  が入っている。cmake も ninja も無いが、`reference/SDL/include` のヘッダで C を書き、その .so に直接リンクすれば呼べる
  （`gcc -I reference/SDL/include x.c /usr/lib/x86_64-linux-gnu/libSDL3.so.0`）。比べる前に、該当の関数が参照版と同じ中身かを
  `git -C reference/SDL fetch --depth=1 origin refs/tags/release-3.4.2` と `git diff FETCH_HEAD HEAD -- <ファイル>` で確かめる
- 検査の期待値を **SDL の実物で測った表**から取ると、移植で直すべき誤り（D-54〜D-57）が自然に見つかる。測る前に読んで
  気づいた誤りも、測ってから記録した
- qwen の実装は今回も読んでから直した（`CLAUDE.md` の qwen の節に実例を足した）。検査を先に書いていたので、どこが
  誤りかがすぐ分かった

## 3. 次の候補（おすすめ順）

1. **ヒントを使う側（小さい）**: ヒントは Context を作る前から置ける（`TPMLContextOptions.Hints`、2026-10-10）。
   `PAPIMELA_VIDEO` / `PAPIMELA_IME` もヒントで選ぶようになった。次は SDL のヒントのうち papimela に効くもの
   （THREAD_PRIORITY_POLICY の実時間スケジューリングなど）を足すこと。既存のコードの `FLastNonFatalError` のような
   「黙って覚える」所を `Ctx.Log` へ流すのも、ここでできる
2. **オーディオ（#51 以降）**: 大きな段階。PipeWire から
3. **レンダラのテクスチャの種類（#41 / #43）**: YUV、パレット（INDEX8）、PIXELART の拡大。描画先テクスチャ・回転・9-grid / タイルは 2026-10-09 に済んだ
4. IME の残り: 埋め込み候補（`TextEditingCandidates`）、IBus の ForwardKeyEvent、ibus-anthy など他のエンジンの属性の実測、GNOME / KDE での IBus 直結（§7.5 の要検証）。IBus の検査環境は `tools/ibus-sandbox/`（ibus + ibus-mozc を入れた Ubuntu 24.04 の最小 rootfs を bwrap で隔離。デスクトップの fcitx5 と混ざらない）。実測の結果は `spikes/RESULTS.md` のスパイク 3

済んだもの（2026-10-10、2 つ目）: Log（#5）・Properties とヒント（#6）、スワップ間隔をコンテキストごとに（D-53）。§2 の表。

済んだもの（2026-10-10）: ドラッグを始める側（`Ctx.Video.Clipboard.StartDrag`。SDL に無い papimela 独自の API。T-42、対話の `demo_drag` は T-44）と
 document-portal（`PaPiMeLa.Platform.DocumentPortal`。鍵からパス、パスから鍵。T-43 は手元専用）。ドラッグで渡すポータルの鍵は
通りがかったアプリも読むので、autostop を切った（D-51）。

済んだもの（2026-10-09）: D&D の受信（#38。T-38、対話の `demo_drop` は T-41。6 項目とも持ち主が確認）、レンダラの回転・平行四辺形・敷き詰め・9 つ分け（T-39）と
描画先テクスチャ（T-40。ソフトウェアと GLES2。GLES2 は T-22 に 3 場面）。SDL_SendDrop と SDL_URIToLocal を写した部分は
`PaPiMeLa.Events.Drop` に分けた（`PaPiMeLa.Events` はクリーンルームなので、移植の部分を混ぜない）。

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
for t in test_dummy_video test_pixels test_io test_surface test_blit test_render test_render_window test_render_logical test_render_transform test_render_target test_time test_keyboard test_textinput_v3 test_ime_keys test_ibus_model test_clipboard test_drop test_drag_source test_protocol_types test_atomic test_threading test_timer test_backends test_umbrella test_properties test_log; do
  fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/$t test/$t.pas && ./test/$t
done
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -oexamples/pong examples/pong.pas && ./examples/pong --selftest
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_render_gles2 test/test_render_gles2.pas
env -u WAYLAND_DISPLAY LIBGL_ALWAYS_SOFTWARE=1 ./test/test_render_gles2   # Mesa の EGL が要る
```

**手元専用**（Wayland セッション、GPU、fcitx5 が要る。クラウドでは走らない）:
`test_wayland_protocols`、`test_wayland_window`、`test_pointer_constraints`、`test_touch_cursor`、
`test_fcitx_textinput`、`test_key_routing`、`test_wayland_textinput`、`test_wayland_clipboard`（**手元のクリップボードを書き換え、終わりに文字列だけ戻す**。必ず `timeout 300` で）、`test_gl_window`、`test_render_gles2` のウィンドウの区間、
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
for t in test_dummy_video test_pixels test_io test_surface test_blit test_render test_render_window test_render_logical test_time test_keyboard test_textinput_v3 test_ime_keys test_ibus_model test_clipboard test_protocol_types test_atomic test_threading test_timer test_backends test_umbrella test_properties test_log; do
  $B -otest/$t test/$t.pas && ./test/$t | tail -1
done
# 1. 実機の Wayland（自動判定。最後の行が「結論」で終わればよい）
for t in test_wayland_protocols test_wayland_window test_pointer_constraints test_touch_cursor test_gl_window test_render_gles2 test_documents_portal; do
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
$B -otest/demo_drop test/demo_drop.pas && ./test/demo_drop 60          # ファイルマネージャやブラウザからドラッグして落とす（見方はファイルの頭）
$B -otest/demo_drag test/demo_drag.pas && ./test/demo_drag 60          # 左半分・右半分から外へドラッグする（見方はファイルの頭）
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
| SDL の実物（手元） | **作らなくても使える**: システムの SDL 3.4.2（`/usr/lib/x86_64-linux-gnu/libSDL3.so.0`）に、`reference/SDL/include` のヘッダで書いた C を直接リンクする（§2）。参照版と中身が違わないかを `git diff` で確かめてから比べる。SDL3 は起動時の環境を写して持つので、環境変数は起動時に渡す（途中の `setenv` は見えない） |
| SDL の実物（作る） | 移植の結果を SDL と画素で比べるときに作る。表示サーバ無しで静的に作れる: `cmake -G Ninja -S reference/SDL -B <作業用> -DSDL_UNIX_CONSOLE_BUILD=ON -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF` に、使わないもの（`-DSDL_AUDIO=OFF` など）を足す。`SDL_CreateSoftwareRenderer` でサーフェスへ描けば比べられる（`docs/TEST-LOG.md` の使い捨て検証） |
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
- **変異の検査の後は `-B` で作り直す**。元に戻したソースが同じ秒に書き戻されると、最後の変異の `.ppu` が残り、正しいものが落ちる（2026-10-10 に T-45 / T-46 で踏んだ。D-34 と同じ）
- x86_64 の FPC では、型の無い小数の定数（`0.01`）は Extended で比べられる。Double の値と `=` で比べるなら型付きの定数にする
- FPC の `Format('%.6f')` は C の `%f` とちょうど半分の丸めと -0・inf・nan の書き方が違う（`docs/TEST-LOG.md` の使い捨て検証）
- Wayland の `Restore` は最小化を解けない（xdg-shell に要求が無い）。最小化した窓にはフレームの合図が来ないので、GL の `SwapGL` は 1/20 秒ごとの打ち切りで進む。最小化の後に速さを測る検査は新しい窓で測る
- ヒントの呼び出しはヒントの排他を持ったまま来る。呼び出しの中で別の排他を取る部品は、自分からヒントを読むときに逆の順にならないようにする（`TPMLLog.ResetPriorities` の PORT-NOTE）

## 8. 保留中の判断（利用者に聞く）

- 読んだだけで確かめていない SDL の怪しい点（確かめるまで不具合一覧に載せない。D-57 の補足）: 知らせの中で次の知らせを
  外すと解放した要素を辿る、`SDL_ResetLogPriorities` とヒントの知らせが逆の順で排他を取る
- SDL の X11 の GLX の経路では、作った直後のスワップ間隔が 1 だった（SDL の「既定で VSync 無し」が効いていない。
  D-53 の確認の途中で見た。追っていない。papimela は X11 を持たないので急がない）
- D-40 の「止まる」側の仕組み（llvmpipe の作業スレッドで例外が起きる）は推測のまま

2026-10-10 に片付いたもの: README に D-36・D-38・D-42 と浮動小数点の例外（D-40）を載せた。同日、D-53〜D-57 と「現状」の数字も載せた。Context を作る前のヒントは `TPMLContextOptions.Hints` に置く形にして、実装した。D-44 の丸めは四捨五入のまま。
Sonnet の疑い 3 つを確かめた（D-53 は本物で papimela を直した、残り 2 つは不具合ではない）。Log の既定は今の見え方を保つ
（`MinimumLogLevel` = Info で全部のカテゴリ。SDL は APP 以外 ERROR）。
