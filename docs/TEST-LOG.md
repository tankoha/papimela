# テスト実行一覧

papimela で実行したテストの記録。日時は実測値（ファイルの mtime と git のコミット時刻、
および最終一括実行の時刻）に基づく。

最終一括実行: **2026-09-29**（自動テスト 9 本すべて成功、アサーション 197 件・失敗 0 件）。
対話テスト T-07 / T-09 も同日に別途実行し、観測項目をすべて確認した。

## 1. 実行可能テスト

| # | テスト | 目的 | 最終実行 | 結果 | 備考 |
|---|---|---|---|---|---|
| T-01 | `spikes/spike1_wayland` | `wl_proxy_marshal_flags` を FPC の `cdecl; varargs` で呼べるか。C → Pascal コールバック、外部データシンボル取り込み | 2026-09-28 22:33 | **PASS 10 / 0** | 初回はコンパイル不可（D-01）。修正後は一度も失敗していない |
| T-02 | `spikes/spike2_fcitx` | fcitx5 の D-Bus で文節区切り・周辺テキスト・周辺削除が取れるか | 2026-09-28 22:33 | **PASS 8 / 0** | 初回実行は 4 項目 FAIL（D-02）。**周辺削除はアサーションを置いていない**（下記 3 を参照） |
| T-03 | `test/test_fcitx_textinput` | papimela の公開 API（`TPMLContext` + イベントキュー）経由で文節情報が失われないか | 2026-09-28 22:33 | **PASS 18 / 0** | 21:44 時点ではメソッドポインタ版で PASS。21:57 にイベントキュー版へ全面改稿し再検証（D-05〜D-08 を経由） |
| T-04 | `test/test_wayland_protocols` | 生成したプロトコルバインディングが実機のコンポジタと通信できるか | 2026-09-28 22:33 | **PASS 24 / 0** | 自前構築した拡張プロトコルの記述子が受理され、`configure` イベントも到達 |
| T-05 | `test/test_wayland_window` | Wayland ビデオバックエンド。ウィンドウ生成、configure → ack_configure、wl_shm への描画、リサイズ通知 | 2026-09-28 22:49 | **PASS 19 / 0** | 実際にウィンドウが約 2 秒表示される。ディスプレイ 2 台を列挙、120 フレーム描画、最大化/復帰の往復も確認 |
| T-06 | `test/test_key_routing` | キーの IME 転送経路（§7.5）。消費されたキーが KeyDown にならないこと | 2026-09-29 10:01 | **PASS 16 / 0** | コンポジタへキーを注入できないため、シートが届けるのと同じ形の合成キーを `TPMLKeyboardState.SendKey` へ直接流す。実キーボード経由の確認は `test/demo_japanese_input`（対話） |
| T-07 | `test/demo_japanese_input`（**対話・人の操作**） | 実キーボードから fcitx5 を経て文節情報と確定文字列がアプリへ届くか。ウィンドウのフォーカス往復が IME に伝わるか | 2026-09-29 | **PASS 観測項目 6 / 6** | アサーションではなく人の目による確認。観測できたものを下表に残す。D-21・D-22・D-23 はこのデモで見つかった |
| T-08 | `test/test_pointer_constraints` | ポインタ拘束。能力への写像、要求の記録、そして**拘束の張り替えがプロトコルに違反しないこと** | 2026-09-29 | **PASS 23 / 0** | ロックと閉じ込めを同じシート・同じサーフェスに同時に作ると接続が切られるので、`wl_display_get_error` が終始 0 であることが張り替え順序の証明になる。拘束が**有効になる**かはカーソル位置に依存するため観測扱い（T-09 が担当）。D-24 はこのテストで見つかった |
| T-09 | `test/demo_pointer_constraints`（**対話・人の操作**） | カーソルをウィンドウ内に入れた状態でロック / 閉じ込め / 相対移動 / カーソル形状が実際に有効になるか | 2026-09-29 | **PASS 観測項目 5 / 5** | 人の目による確認。観測内容は下表。D-25〜D-28 はこのテストで見つかった（すべてデモ側の欠陥） |
| T-10 | `test/test_touch_cursor` | タッチの状態機械（移動量の算出、ウィンドウの引き継ぎ、取り消し）と cursor-shape-v1 の対応表・能力・切り替え | 2026-09-29 | **PASS 41 / 0** | タッチは合成入力。Wayland は移動量を送らず motion / up にウィンドウも付けないので、そこを埋める部分がタッチ対応の実体であり、ハードウェア無しで検証できる。**実機のタッチパネルは手元に無く未検証**。カーソル形状の実際の適用はカーソル位置に依存するため T-09 が担当 |
| T-11 | `test/test_dummy_video` | **表示サーバ無し**で公開 API（ウィンドウ生成・リサイズ・状態・フレームバッファ）が動くか | 2026-09-29 | **PASS 38 / 0** | `WAYLAND_DISPLAY` と `DISPLAY` を外して実行しても通る。**CI で走る唯一の実行テスト**。D-29 はこのテストを書いていて見つかった |

### T-04 が決定的である理由

拡張プロトコルの `wl_interface` 記述子（メッセージ表、シグネチャ文字列、`types` 配列プール）は
生成器が自前で組む。1 バイトでも違えばコンポジタはプロトコルエラーを返して接続を切る。
`xdg_surface.configure` と `xdg_toplevel.configure` が届き、`wl_display_get_error` が終始 0 で
あることが、記述子の正しさの証明になっている。

### T-07 で実際に観測したもの

自動化できない部分（コンポジタへキーを注入できない、IME の変換結果は辞書に依存する）を
人が操作して確認する。2026-09-29 の実行で観測できたのは以下。

| 観測項目 | 観測した内容 |
|---|---|
| キーマップの受信 | `wl_keyboard.keymap` から xkb キーマップを読み込めた。実行中にコンポジタが再送した場合も再読み込みしている |
| 変換中テキストの逐次更新 | ローマ字が仮名へ変わる過程が `TextEditing` として 1 打鍵ごとに届く（`ｎ` → `な` → `なｎ` → `なん`） |
| **複数文節** | `[なんか]<変なタイミングで>`（2 文節）、`[では]<ここでニューヨーク株式市場の様子を見てみましょう>`（2 文節）。§7.8 のフラグ規則（`HighLight` → `Focused`、`Underline` のみ → `Converted`）が実機の fcitx5-mozc で成立した |
| 確定文字列 | `TextInput` として届き、アプリのバッファに連結される。最終バッファは打った文と一致した |
| キーの消費 | 変換中の 105 キーすべてが IME に消費され、素通りした `KeyDown` は 0 件。§7.5 の契約が実キーボードでも保たれている |
| **フォーカスの往復** | 入力中に別ウィンドウへ移り戻る操作を 4 回。`フォーカスを喪失（IME にも FocusOut）` と `取得（IME にも FocusIn）` が毎回対で記録された（D-22・D-23 の修正の確認） |

別の実行では Backspace の扱いも確認している。変換中は IME が消費し、確定後のバッファに
対しては素通りして `KeyDown` になる。素通りしたキーの keysym は `$FF08`（BackSpace）と
`$FFE1`（Shift_L）だけだった。

### T-09 で実際に観測したもの

拘束もカーソル形状も、`wl_pointer.enter` を受けている（カーソルがウィンドウ上にある）
ことが前提になる。カーソルをプログラムから動かす手段が無いので、ここは人が操作する。

| 観測項目 | 観測した内容 |
|---|---|
| 閉じ込め（confined_pointer） | `グラブ: True` → `閉じ込め（要求のみ・まだ有効でない）` → `閉じ込め（コンポジタが有効化）`。2 段階になるのは、こちらが作ったあとコンポジタが `confined` を返すため。リスナーが届いている証拠になる |
| ロック（locked_pointer） | `相対モード: True` → `ロック（要求のみ）` → `ロック（コンポジタが有効化）＋相対ポインタ` |
| **ロック中に絶対座標が止まる** | 相対移動が 340 件届く間、`abs=(383, 152)` が一切動かず `rel` だけが変化した。ロック中は `wl_pointer.motion` が来ないという前提どおり。累計 `(-169.0, 60.6)` |
| **張り替えでプロトコル違反が出ない** | 閉じ込め ⇄ 解除を 10 回以上、相対モード ⇄ 解除を 6 回、さらに閉じ込め → ロックの往復を実機で行って `wl_display_get_error` は 0 のまま。ロックと閉じ込めの排他規則が保たれている |
| カーソル形状（cursor-shape-v1） | `S` キーで `カーソル形状: テキスト` に切り替わり、実際の見た目も変わった。`wl_display_get_error` は 0 |

観測できなかったもの: **タッチ**（パネルが無い）。

## 2. コンパイル検証

| # | 対象 | 最終実行 | 結果 | 備考 |
|---|---|---|---|---|
| C-01 | `src/` の全ユニット（Types / Errors / Unicode / Core.Base / Core / Events / Platform.DynLib / Platform.DBus / Platform.Wayland.Client / Platform.XKB / TextInput 系 3 本 / Video 系 8 本） | 2026-09-29 | **PASS** | 全 21 ユニット。到達過程で D-03〜D-08、D-19 を修正 |
| C-02 | `tools/wlscan-pas` | 2026-09-28 22:24 | **PASS** | — |
| C-03 | 生成プロトコル 21 ユニット（9230 行） | 2026-09-28 22:24 | **PASS 21 / 21** | 初回は 9 / 21 が失敗（D-10〜D-12）。§9.2 が挙げる XML のうち、`reference/SDL/wayland-protocols/` にあるものすべて |
| C-04 | **rawpaco 静的解析（激辛モード `--fail-on=warning`）** — `src` / `src/generated` / `test` / `spikes` / `tools` の全 Pascal ファイル | 2026-09-29 | **PASS 指摘 0 件** | 導入初回は 2 件の指摘（D-20）。修正後は 0 件。`.github/workflows/lint.yml` で push / pull_request ごとに走る |
| C-05 | **図と実装の整合性検査**（`tools/check-diagrams.sh`） — 英日の Mermaid ブロック同一性、図に出てくる型 51 個の実在 | 2026-09-29 | **PASS 不整合 0 件** | `.github/workflows/lint.yml` で push ごとに走る |
| C-06 | **Origin 行と設計書の突き合わせ**（`tools/checkorigin.bb`） — 第11章の由来列との一致、移植部分の SDL 著作権表示の有無 | 2026-09-29 | **PASS 不一致 0 件** | 導入初回は 10 件の不一致（D-30）。`.github/workflows/lint.yml` で push ごとに走る |

## 3. アサーションを置いていない項目

意図的に検証していない、または環境の都合で検証できていないもの。**失敗ではなく未検証**として扱う。

| 項目 | 状況 | 理由 |
|---|---|---|
| 周辺削除（`DeleteSurroundingText`）の実受信 | **未観測** | 経路は実装済みで、fcitx5 のインターフェースにシグナルが存在することは introspect で確認済み。ただし mozc が発火させる条件（再変換など）を通常の入力では満たさない。機構の欠如ではない |
| GNOME (mutter) / KDE (kwin) での IME 直結 | **未検証** | 検証環境は labwc (wlroots) のみ。mutter / kwin は IME クライアントを一元管理する設計なので別途確認が必要（設計書 §10 項目 2） |
| fcitx5-anthy / fcitx5-chinese-addons のフラグ対応 | **未検証** | 文節状態のマッピング規則は fcitx5-mozc でのみ実測（設計書 §10 項目 1） |
| IBus 経路 | **未実装** | バックエンド自体が未実装（第 11 章 #48） |
| **実キーボードからの日本語入力** | **対話で検証済み（アサーションは無い）** | T-07 として 2026-09-29 に観測済み。自動化は残課題で、コンポジタへキーを注入できないため CI に載せるには `weston --backend=headless` + キー注入の仕組みが要る（第 11 章 #70） |
| **タッチパネルからの実入力** | **未検証** | `wl_touch` の受け取りと `TPMLTouchState` は実装済みで、T-10 が合成入力で検査している。検証環境にタッチパネルが無いため、`wl_touch` のイベントが実際に届く経路は通していない。`shape` / `orientation` は未対応 |
| ポインタ拘束の自動化 | **手動のみ** | 有効化には `wl_pointer.enter` が必要で、カーソルをプログラムから動かす手段が無い。T-09（対話）で実機確認済み。CI に載せるには `weston --backend=headless` + ポインタ注入が要る（第 11 章 #70） |
| ウィンドウのフルスクリーン / 不透明度 / アイコン / ヒットテスト / キーボードグラブ | **未実装** | 対応する能力と一緒に追加する |
| GL / Vulkan / レンダラ / クリップボード / 任意ピクセルのカーソル | **未実装** | 第 11 章 #33、#38、#39、#41、#67。カーソルはシステム形状のみ実装済みで、`wl_shm` の共通部品（#39）が入ってから任意ピクセル版を足す |
| `TPMLEvent` の `Finalize` コスト測定 | **未実施** | サイズは実測済み（72 バイト）。ベンチマークは残課題（設計書 §10 項目 9） |
| CI でのヘッドレス実行 | **一部整備済み** | ダミーバックエンド（#34）で T-11 が CI で走るようになった。ただし CI で検査できるのは**バックエンドに依存しない公開 API だけ**で、Wayland のプロトコル手順（T-04/T-05/T-08/T-10）と IME（T-02/T-03/T-06）はローカル専用のまま。そこまで CI へ載せるには `weston --backend=headless` + fcitx5 の起動が要る（第 11 章 #70 の残り） |

## 4. 使い捨ての事前検証（恒久化していない）

方式判断のためスクラッチパッドで実行し、結論だけを設計に反映したもの。コードは残していない。

| 検証 | 日時 | 結論 |
|---|---|---|
| `fcl-xml`（DOM / XMLRead）で `wayland.xml` を読めるか | 2026-09-28 22:0x | 読める。`root=protocol children=24` |
| `varargs` を手続き変数型に付けてコンパイルできるか | 同日 | できる |
| dlopen した関数ポインタ経由の `varargs` 呼び出しが実際に動くか | 同日 | 動く（globals 57 件を受信）。この結果により `wl_proxy_marshal_array_flags` による回避を不要と判断した |
| `wayland-scanner` の出力との照合（シグネチャ、`types` プール配置、destructor フラグ） | 同日 | 生成器のセマンティクスを確定。`bind` の `usun`、`since` の数字接頭辞、NULL 前置の長さ算出規則を確認 |

## 5. 再現方法

```bash
cd papimela
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_fcitx_textinput   test/test_fcitx_textinput.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_wayland_protocols test/test_wayland_protocols.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_wayland_window    test/test_wayland_window.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_key_routing     test/test_key_routing.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/demo_japanese_input  test/demo_japanese_input.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_pointer_constraints test/test_pointer_constraints.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_touch_cursor        test/test_touch_cursor.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_dummy_video          test/test_dummy_video.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/demo_pointer_constraints test/demo_pointer_constraints.pas
fpc -O1 -gl spikes/spike1_wayland.pas && fpc -O1 -gl spikes/spike2_fcitx.pas
./spikes/spike1_wayland && ./spikes/spike2_fcitx
./test/test_fcitx_textinput && ./test/test_wayland_protocols && ./test/test_wayland_window
./test/test_key_routing && ./test/test_pointer_constraints && ./test/test_touch_cursor

# 表示サーバが無くても通る唯一のテスト（CI で走るのはこれ）。
env -u WAYLAND_DISPLAY -u DISPLAY ./test/test_dummy_video

# T-07（対話）。ウィンドウをクリックしてフォーカスし、日本語を打つ。
# 途中で別ウィンドウへ移って戻ると、フォーカスの往復が IME に伝わることも確認できる。
./test/demo_japanese_input 60

# T-09（対話）。カーソルをウィンドウの中に入れて G / R / C / S / H で切り替える。
./test/demo_pointer_constraints 60
```

実行前提: Wayland セッション、fcitx5 稼働、日本語エンジン（mozc）が利用可能であること。
T-02 と T-03 は IME の状態を変更する（`Controller1.Activate` を呼ぶ）ため、実行後に
入力メソッドがアクティブになっている場合がある。
