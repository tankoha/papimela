# 引き継ぎ資料

新しいセッションは、`CLAUDE.md` の次にこれを読む。最終更新: 2026-10-14（オーディオの 1 段目の後半、ストリームのコミットと同時）。

> **2026-10-14 の手元のセッションで**: §3 の 3b（パレット、INDEX8）と 3c（YUV。YV12 / IYUV / NV12 / NV21 / YUY2 / UYVY / YVYU）を
> 済ませ、テクスチャの種類（§3 の 1）は終わった。README の上流の不具合に D-58〜D-61 を載せた（持ち主の判断）。SDL の不具合を
> 4 つ見つけた（D-60〜D-63）。表示サーバ無しの 28 本（1243 件）と T-22（llvmpipe・radeonsi・窓）は全部通る。
> 続けてオーディオに入り、**1 段目（音声の変換・周波数の変換・キュー・ストリーム。表示サーバも音の装置も要らない）を済ませた**
> （SDL の不具合 D-64・D-65）。表示サーバ無しの 30 本（1286 件）が全部通る。**手元の対話の確認は残っていない。**
> 次は §3 の 1 のオーディオの 2 段目（中核 `SDL_audio.c` と Dummy）から。

## 1. 今どこにいるか

| 項目 | 状態 |
|---|---|
| リポジトリ | https://github.com/tankoha/papimela（公開、Issues 有効）。手元のセッションは `master` に直接 push、クラウドのセッションは指定のブランチへ push して、手元で早送りマージする |
| CI | 緑。rawpaco 激辛、checkorigin、アンブレラの古さ（`genumbrella.bb --check`）、図の検査、表示サーバ無しのテスト 30 本、Pong の自己検査、GLES2 と ソフトウェアのドライバの画素比較（llvmpipe）。ジョブ 60 分・GLES2 の手順 5 分の時間制限つき |
| テスト | 表示サーバ無しの 30 本・1286 件はすべて成功（2026-10-14 に手元で `-B` で作り直して全部流した）。手元専用と対話の検査は `docs/TEST-LOG.md` の各行 |
| 不具合 | 65 件。うち上流 SDL の 17 件は未報告（D-53 は SDL 自身が FIXME で知っている。他の 16 件は報告するかを検討中。方針は `CLAUDE.md`） |
| 規模 | 手書き 56 ユニット（`src/*.pas`）+ 生成（Wayland プロトコル 21、キーボードの表 2、EGL / GLES2 の定数 2、DebugText の字形 1、音声のチャンネル数の変換と周波数の変換の係数 2、アンブレラ 2）。約 4.2 万行 |

### 動いているもの

Wayland のウィンドウ（xdg-shell、configure の往復、最大化・最小化、隠す・出す）、シート
（xkb のキーボード、ポインタ、タッチ、ポインタ拘束、カーソル形状）、キーボードの状態と
SDL と同じ値のスキャンコード・キーコード（配列ごとのキーマップ）、イベントキュー、
IME（fcitx5・IBus・text-input-v3。全文節・周辺テキスト・周辺削除）、ピクセル形式、サーフェス、BMP、
ブリッタ、レンダラ（ソフトウェアと OpenGL ES 2.0。どちらもウィンドウへ VSync つき。拡大率、論理解像度 5 方式、
ウィンドウ座標との変換、DebugText、回転・反転・平行四辺形・敷き詰め・9 つ分け、描画先テクスチャ、パレットのテクスチャ（INDEX8）、YUV のテクスチャ（7 形式、色空間））、
クリップボードとプライマリ選択、ドラッグ＆ドロップ（受信と、こちらから始めるドラッグ。Flatpak 向けの document-portal も）、
EGL の GL コンテキスト（スワップ間隔はコンテキストごと）、ヘッドレスのダミーのビデオ、待つ API・タイマー・スレッド・不可分操作、
**ログ（`Ctx.Log`）・ヒント（`Ctx.Hints`、`PAPIMELA_LOGGING` など）・プロパティの表（`TPMLProperties`、`Ctx.Properties`）**、
バックエンドの登録（`PaPiMeLa.Backends`）、アンブレラ（`uses PaPiMeLa`）、`TPMLApplication`、サンプルの Pong。

### 設計書第 11 章の進み具合

済み（一部を含む）: #1–10、#12–17（#17 の `.GL` は未）、#22、#24（`Events.Keymap`。押下状態は
`PaPiMeLa.Events` の `TPMLKeyboardState`）、#25 の一部（マウスとタッチの状態機械は `PaPiMeLa.Events`）、
#26–29、#31–39、#41–43（#41 の残りはテクスチャの Lock）、
#45、#46、#47、#48、#49、#50、#64、#68（YUV から ARGB8888 への変換だけ）、#70、#71。

未着手: #11、#18–21、#23、#30、#40、#44、
#51–63（オーディオ、ジョイスティック、ゲームパッド、ハプティクス）、#65–67、#69。

## 2. 前のセッション（2026-10-14、手元）でしたこと

| 内容 | 担当 | 検査 |
|---|---|---|
| パレットの版（`TPMLPalette.Version`）、共通の層（`TPMLTexture.SetPalette`、`TPMLTexturePalette`、ドライバの 4 つの仮想メソッド、`PrepareTexture`、肩代わり）、ソフトウェアのドライバ、サーフェスから作る経路、DebugText を INDEX8 に | Opus | T-49 に 3b の節（先に書き、空の実装で 42 件落ちた。変異 18 通り） |
| GLES2 のドライバのパレット（GL_LUMINANCE の添字、256x1 の写し、シェーダ 4 つ） | Sonnet（依頼文・検査・見直しは Opus） | T-22 にパレットの場面と GPU だけの確かめ 3 件（変異 3 通り + 同値の 1 つ） |
| README の上流の不具合に D-58〜D-61 を載せた | Opus | — |
| 色空間（`TPMLColorspace`、SDL と同じ値）、YUV の共通の層（`UpdateYUV` / `UpdateNV`、`CreateTexture` の色空間、肩代わり） | Opus | T-49 に 3c の節（先に書き、空の実装で落ちた。変異 15 通り） |
| `PaPiMeLa.Surface.YUV`（#68。YUV から ARGB8888 への変換、YUV の平面の置き場。yuv2rgb の BSD 3 条項を `LICENSE` に足した） | qwen が下書き、Opus が直した（直した箇所は DESIGN #68） | T-49 の 3c。SDL の 105 通りの出力と全バイトを突き合わせた（TEST-LOG の使い捨て検証） |
| GLES2 のドライバの YUV（平面ごとのテクスチャ、行列は SDL の値、シェーダ 6 つ） | Sonnet（依頼文・検査・見直しは Opus） | T-22 に YUV の場面と GPU だけの確かめ 2 件（変異 5 通り） |

見つけた SDL の不具合: D-60（参照版だけ。カラーキーつきの INDEX8 のサーフェスからテクスチャを作ると、サーフェスのパレットが書き換わる。
3.4.2 では起きない）、D-61（前のパレットを共有するテクスチャがあると、パレットを替える前に積んだ描画まで新しい色になる）、
D-62（YUV から RGB のスカラー版が範囲の外の値を回り込ませる。x86 では幅 32 未満と右端の列）、D-63（NV12 / NV21 の全体の更新が
行の幅を見ない。3.4.2 は IYUV / YV12 も）。
期待値と不具合は、参照版の SDL を表示サーバ無しで静的に作って測った（`docs/TEST-LOG.md` の使い捨て検証。手元には X11 の
開発用ヘッダが無いので `-DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=OFF -DSDL_OPENGL=OFF -DSDL_OPENGLES=OFF` も要る）。
3.4.2 と比べるときは `git -C reference/SDL fetch --depth 1 origin tag release-3.4.2` でタグを取る（`SDL_render.c` は 489 行違う）。

このセッションで分かったこと・やり方:

- **SDL 3.4.2 と参照版で振る舞いが違う所がある**（サーフェスからのパレットは 3.4.2 が写し、参照版が共有）。システムの SDL で
  測る前に、該当箇所の `git diff release-3.4.2` を見る
- SDL でも INDEX1 / 2 / 4 のテクスチャは作れない（`palette_surface` の 8 ビット未満の枝は通らない）。papimela のサーフェスは
  1 画素 1 バイト未満の画素を読み書きできない（`ReadRaw` が何もしない）
- **Sonnet が挙げた「頼んだ範囲の外の疑い」が本物だった**（D-61。papimela の共通の層にも同じ穴があり、直した）。依頼文で
  「疑いは結論を出さずに書く」と頼むと拾える
- サブエージェントが `lib/` を `-B` で作り直している間は、自分の作り直しを別の置き場（`-FUlib2` など。使ったら消す）にする
- 変異の検査で、歯の無い検査が 1 つ見つかった（部分更新の直前に色を変えていて、写し直しが別の理由で起きていた）。場面の順番も歯に効く。
  3c でも同じ形が出た（UpdateYUV の確かめの前に、期待どおりの絵がテクスチャに残っていた）。**確かめの前に別の絵で入れ替える**
- **SDL の実物の出力を全部書き出して突き合わせる**のが効いた（YUV。固定の LCG の入力を C と Pascal の両方で作る）。違いが出たら
  「SDL の値が正しいか」をまず手で計算する（D-62 はそれで分かった）。`SDL_CPU_FEATURE_MASK=-sse2,...` で SDL の SIMD を切れる
- qwen の下書きは、仕様に計算式を括弧まで書いても、平面の行き先・位置の半分化・未定義の変数を誤った。表（係数）は自分で計算して
  そのまま写させた（合っていた）
- 新しい検査のプログラムを足したら、`.gitignore` に実行ファイルの名前も足す（`test/test_audio_convert` を一度誤ってコミットした）
- アンブレラに新しいユニットを足すときは、`tools/genumbrella.bb` の一覧と **`src/PaPiMeLa.pas` の uses の両方**。`--check` は uses を見ない
  （T-26 が落ちて気づく）
- GLES2 の YUV は、補間なしのとき色差を「輝度のテクセル n の n div 2 番」に寄せる（SDL の GPU の経路は奇数の大きさでソフトウェアと
  違う色差を引く。papimela はドライバ間で同じ絵にする。DESIGN #43）

## 3. 次の候補（おすすめ順）

持ち主の決めた順（2026-10-12）: ヒントを使う側 → テクスチャの種類 → オーディオ。ヒントを使う側は 2026-10-13、テクスチャの種類は 2026-10-13〜14 に済んだ（下）。

1. **オーディオ（#51 以降）**: 進行中。PipeWire（#56）は中核（#51）・変換（#52）・キュー（#53）・Dummy（#55）の上に乗るので、依存の順に 3 段で進める:
   - **1 段目は済んだ（2026-10-14）**: 音声の形式・チャンネル数・並び・音量の変換と周波数の変換（`PaPiMeLa.Audio.Convert`、T-50）、
     キュー（`PaPiMeLa.Audio.Queue`）、ストリーム（`PaPiMeLa.Audio.Stream`。`TPMLAudioStream`、`PMLConvertAudioSamples`。T-51）。
     期待値は参照版の SDL の出力の FNV-1a の定数表。周波数の変換は SDL の SIMD を切った値に合わせる（x86 の SDL は 1 フレームの計算を
     SSE で行い、足し算の順番が違う）。係数の表は `tools/genresampler.bb` が SDL のコードを C で動かして作る
   - **2 段目が次**: 中核（`SDL_audio.c`、#51）。ストリームの `bound_device`・`simplified`・作成と破棄の知らせ（全ストリームの一覧）は
     Sonnet が SDL の場所に日本語の注記で残してある。それを埋める形で、デバイスへの結び付け・混ぜる処理（`SDL_mixer.c` の SDL_MixAudio、
     #53 の `.Audio.Mixer`）・デバイススレッド・hotplug のイベントを足す
   - 2 段目の範囲: 中核（`SDL_audio.c`、#51。物理・論理デバイス、デバイススレッド、bind、混ぜる、hotplug のイベント）と Dummy（#55）。
     Dummy で表示サーバ無しに検査する
   - **3 段目**: PipeWire（`audio/pipewire/SDL_pipewire.c`、#56）。ヘッダの翻訳は C の sizeof / offsetof を実測して合わせる、
     SPA の pod の組み立て（SDL はインラインの関数を使う）を写す、`pw_thread_loop` とデバイススレッド、hotplug。
     手元の実機（PipeWire 1.6.2）で鳴らす対話の検査を作る
   - 浮動小数の変換は、範囲の外の値で SDL の SSE2 版とスカラー版の結果が割れる（D-64・D-65）。期待値の入力は範囲の中に置く
2. 残してあるテクスチャのもの: テクスチャの Lock / Unlock（`SDL_LockTexture`。Streaming のテクスチャ。YUV は SDL_SW_LockYUVTexture）、
   I444 / P010 などの YUV、サーフェスから作るときのカラーキー（INDEX8 のほかは見ていない）、ソフトウェアのレンダラの Linear が
   実は Nearest（`PMLBlitScaled` が方式を使わない。SDL は補間する）
3. IME の残り: 埋め込み候補（`TextEditingCandidates`）、IBus の ForwardKeyEvent、ibus-anthy など他のエンジンの属性の実測、GNOME / KDE での IBus 直結（§7.5 の要検証）。IBus の検査環境は `tools/ibus-sandbox/`（ibus + ibus-mozc を入れた Ubuntu 24.04 の最小 rootfs を bwrap で隔離。デスクトップの fcitx5 と混ざらない）。実測の結果は `spikes/RESULTS.md` のスパイク 3

済んだもの（2026-10-14）: **テクスチャの種類**。3b パレット（INDEX8）と 3c YUV（7 形式、色空間）。§2 の表。

済んだもの（2026-10-13）: **ヒントを使う側**。A（KEYCODE_OPTIONS と hide_numpad、APP_ID、RENDER_DRIVER / RENDER_VSYNC、
EGL_LIBRARY / OPENGL_LIBRARY。下の層からは `ContextServices` で Context の土台に届く）と B（THREAD_PRIORITY_POLICY と
実時間・D-58 の直し、IME_IMPLEMENTED_UI（papimela の既定は composition）、QUIT_ON_LAST_WINDOW_CLOSE、NO_SIGNAL_HANDLERS、
EVENT_LOGGING。SDL から写した規則は `PaPiMeLa.Events.Quit`（#72））。T-47・T-48。C（ダブルクリック、タッチとマウス、
スクリーンセーバー、libdecor など）は機能そのものが先に要る。**キーボードの状態を `PaPiMeLa.Events.Keyboard`
（一部移植、#24）に分けた**（`PaPiMeLa.Events` はクリーンルームに戻った。公開 API は同じ）。

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
for t in test_dummy_video test_pixels test_io test_surface test_blit test_render test_render_window test_render_logical test_render_transform test_render_target test_time test_keyboard test_textinput_v3 test_ime_keys test_ibus_model test_clipboard test_drop test_drag_source test_protocol_types test_atomic test_threading test_timer test_backends test_umbrella test_properties test_log test_hints test_texture_kinds test_audio_convert test_audio_stream; do
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
for t in test_dummy_video test_pixels test_io test_surface test_blit test_render test_render_window test_render_logical test_time test_keyboard test_textinput_v3 test_ime_keys test_ibus_model test_clipboard test_protocol_types test_atomic test_threading test_timer test_backends test_umbrella test_properties test_log test_hints test_texture_kinds test_audio_convert test_audio_stream; do
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

- **テクスチャのパレットは借り物**（`SetPalette(P)`。`AOwned` を True にすると持たせられる）。借りたパレットは使うテクスチャより
  長く生かす。サーフェスから作ったテクスチャは写しを持つので、サーフェスを先に消してよい
- パレットの外の添字は、どのドライバでも白（SDL のソフトウェアのレンダラと同じ。GLES2 の写しは白で始める）

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

2026-10-14 に片付いたもの: README の「上流 SDL の不具合」に D-58〜D-61 を載せた（持ち主の判断）。

2026-10-13 に片付いたもの: `PaPiMeLa.Events` の由来の食い違い（キーボードの状態を `PaPiMeLa.Events.Keyboard` に分けた。持ち主の判断）。

2026-10-10 に片付いたもの: README に D-36・D-38・D-42 と浮動小数点の例外（D-40）を載せた。同日、D-53〜D-57 と「現状」の数字も載せた。Context を作る前のヒントは `TPMLContextOptions.Hints` に置く形にして、実装した。D-44 の丸めは四捨五入のまま。
Sonnet の疑い 3 つを確かめた（D-53 は本物で papimela を直した、残り 2 つは不具合ではない）。Log の既定は今の見え方を保つ
（`MinimumLogLevel` = Info で全部のカテゴリ。SDL は APP 以外 ERROR）。
