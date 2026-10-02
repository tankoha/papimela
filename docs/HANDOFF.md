# 引き継ぎ資料

新しいセッションは、`CLAUDE.md` の次にこれを読む。最終更新: 2026-10-02（論理解像度と DebugText のコミット）。

## 1. 今どこにいるか

| 項目 | 状態 |
|---|---|
| リポジトリ | https://github.com/tankoha/papimela（公開、Issues 有効、`master` に直接 push） |
| CI | 緑。rawpaco 激辛、checkorigin、図の検査、表示サーバ無しのテスト 8 本、Pong の自己検査、GLES2 と ソフトウェアのドライバの画素比較（llvmpipe）。ジョブ 60 分・GLES2 の手順 5 分の時間制限つき |
| テスト | 21 本、662 件、すべて成功（`docs/TEST-LOG.md`。手元専用の検査は 662 件に数えているが、追加後は流し直していない） |
| 不具合 | 45 件。うち上流 SDL の 4 件（D-18、D-36、D-38、D-42）は未報告（方針は `CLAUDE.md`） |
| 規模 | 手書き 39 ユニット + 生成（Wayland プロトコル 21、キーボードの表 2、EGL / GLES2 の定数 2、DebugText の字形 1）。約 3 万行 |

### 動いているもの

Wayland のウィンドウ（xdg-shell、configure の往復、最大化・最小化、隠す・出す）、シート
（xkb のキーボード、ポインタ、タッチ、ポインタ拘束、カーソル形状）、キーボードの状態と
SDL と同じ値のスキャンコード・キーコード（配列ごとのキーマップ）、イベントキュー、
fcitx5 経由の IME（全文節・周辺テキスト・周辺削除）、ピクセル形式、サーフェス、BMP、
ブリッタ、レンダラ（ソフトウェアと OpenGL ES 2.0。どちらもウィンドウへ VSync つき。拡大率、論理解像度 5 方式、
ウィンドウ座標との変換、DebugText）、
EGL の GL コンテキスト、ヘッドレスのダミーのビデオ、待つ API（Delay / DelayNS / DelayPrecise）、サンプルの Pong。

### 設計書第 11 章の進み具合

済み（一部を含む）: #1–4、#10、#12–17（#17 の `.GL` は未）、#22、#24（`Events.Keymap`。押下状態は
`PaPiMeLa.Events` の `TPMLKeyboardState`）、#25 の一部（マウスとタッチの状態機械は `PaPiMeLa.Events`）、
#26–29、#31–37（#32 の `.Clipboard` は未）、#39、#41–43（#41 の残りは描画先テクスチャ、回転、9-grid / タイル）、
#46、#47、#50、#64、#70。

未着手: #5–8（Log、Properties、Atomic、Threading）、#9 Time のタイマー（待つ API は済み）、#11、#18–21、#23、#30、#38、#40、#44、
#45、#48、#49、#51–63（オーディオ、ジョイスティック、ゲームパッド、ハプティクス）、#65–69。

## 2. 次の候補（おすすめ順）

1. **アンブレラ（#45、Medium）**: `uses PaPiMeLa` 1 つで公開 API が揃うように。Pong は今 papimela のユニットを 8 つ `uses` している
2. **クリップボード（#38、Medium）**、**IBus（#48、High）と text-input-v3（#49、High）**: IME は papimela の看板。
   fcitx5 以外の利用者に届く
3. **Threading（#8、High）**: これが済むと #9 のタイマー（`AddTimer`）と `RunOnMainThread` に進める
4. **レンダラの残り（#41）**: 描画先テクスチャ（SetRenderTarget。テクスチャごとの view が要るので、
   今レンダラに直接持っている拡大率・論理解像度のフィールドを record にまとめるところから）、回転、9-grid / タイル
5. **オーディオ（#51 以降）**: 大きな段階。PipeWire から

済んだもの（2026-10-02）: 論理解像度と DebugText（F-4 / F-5）、待つ API（F-6、#9 の一部）、
Context のオプションを値型に（F-7）。Pong もすべて書き換えた。

## 3. 定着した進め方

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
- コミットはこちらが作り、`master` へ push、CI を最後まで見る。コミットの末尾は
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## 4. 検査の流し方

表示サーバ無しで通るもの（CI と同じ）:

```bash
for t in test_dummy_video test_pixels test_io test_surface test_blit test_render test_render_window test_render_logical test_time test_keyboard; do
  fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/$t test/$t.pas && ./test/$t
done
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -oexamples/pong examples/pong.pas && ./examples/pong --selftest
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_render_gles2 test/test_render_gles2.pas
env -u WAYLAND_DISPLAY LIBGL_ALWAYS_SOFTWARE=1 ./test/test_render_gles2   # Mesa の EGL が要る
```

**手元専用**（Wayland セッション、GPU、fcitx5 が要る。クラウドでは走らない）:
`test_wayland_protocols`、`test_wayland_window`、`test_pointer_constraints`、`test_touch_cursor`、
`test_fcitx_textinput`、`test_key_routing`、`test_gl_window`、`test_render_gles2` のウィンドウの区間、
スパイク 2 本、対話のデモ（`demo_japanese_input`、`demo_pointer_constraints`、`demo_render_window`）。

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

## 5. 作業環境

| もの | 場所・備考 |
|---|---|
| FPC | 3.2.2（CI も同じ） |
| rawpaco | `../rawpaco`（https://github.com/tankoha/rawpaco。`make` で作る）。CI は `main` を取る |
| SDL のソース | `reference/SDL`（gitignore 済み）。版と取り直し方は `docs/ORIGIN.md` |
| Babashka | 生成器と checkorigin と qwen-gen が使う |
| SDL の実物 | 移植の結果を SDL と画素で比べるときに作る。表示サーバ無しで静的に作れる: `cmake -G Ninja -S reference/SDL -B <作業用> -DSDL_UNIX_CONSOLE_BUILD=ON -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF` に、使わないもの（`-DSDL_AUDIO=OFF` など）を足す。`SDL_CreateSoftwareRenderer` でサーフェスへ描けば比べられる（`docs/TEST-LOG.md` の使い捨て検証） |
| qwen | 手元の ollama の `qwen2.5-coder:14b`。呼び出しは `tools/qwen-gen.bb`。**クラウドには無い**ので、Low の作業は手元に戻るか、Sonnet に回す |
| 手元の機械 | labwc（Wayland）、画面 DP-3 2560x1080 200 Hz、Radeon RX 9070 + 内蔵 Raphael、Mesa 26.0.8、Ubuntu 26.04、fcitx5-mozc |

## 6. 落とし穴（詳しくは `docs/DEFECTS.md` の「傾向」）

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
- C の関数へ構造体を渡すときは `const` の record でなくポインタで宣言する（cdecl の `const` は値渡しになる。D-45）
- レンダラは描画を**積んでから実行する**。積んだ後に変えられる値（テクスチャの変調色など）は積むときに写す（D-43。D-39 も同じ隙間）

## 7. 保留中の判断（利用者に聞く）

- SDL の不具合 D-36、D-38、D-42 を README の「SDL にバグ報告を返すべきか」の節に足すか（今は D-18 だけ）
- ソフトウェアのブリッタの半透明の丸めが SDL と 1 違う（SDL は切り捨てで `0x9f`、papimela は四捨五入で `0xa0`。D-44）。
  SDL に揃えるか。揃えるなら T-15 の参照実装と T-22 の許容差も見直す
- GL を使うと浮動小数点の例外が無効になること（D-40）を README にも書くか
- Sonnet が挙げた SDL の怪しい点 3 つ（スワップ間隔が全体で 1 つ、EGL 1.5 をちょうど 1.5 で判定、
  面が無いときに成功を返す MakeCurrent）は**まだ確かめていない**。確かめるまで不具合一覧に載せない
- D-40 の「止まる」側の仕組み（llvmpipe の作業スレッドで例外が起きる）は推測のまま
