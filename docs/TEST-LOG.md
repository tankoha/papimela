# テスト実行一覧

papimela で実行したテストの記録。日時は実測値（ファイルの mtime と git のコミット時刻、
および最終一括実行の時刻）に基づく。

最終一括実行: **2026-10-02**（自動テスト 19 本すべて成功、アサーション 584 件・失敗 0 件。`-B` で全部作り直して実行）。
同日、T-23 を足し、T-19 と T-22 に検査を足した（20 本・639 件）。足した分と、CI で走る 9 本・T-19・T-22 のオフスクリーンの区間はクラウドの Ubuntu 24.04 で通した。手元専用の検査は追加後に流し直していない。
対話テスト T-07 / T-09 と、実機での計測 T-18 も同日に別途実行し、観測項目をすべて確認した。

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
| T-11 | `test/test_dummy_video` | **表示サーバ無し**で公開 API（ウィンドウ生成・リサイズ・状態・フレームバッファ）が動くか | 2026-09-29 | **PASS 40 / 0** | `WAYLAND_DISPLAY` と `DISPLAY` を外して実行しても通る。**CI で走る実行テストの 1 本**。D-29 はこのテストを書いていて見つかった |
| T-12 | `test/test_pixels` | ピクセル形式の識別、マスクの導出、色 ↔ 画素値の往復 | 2026-09-29 | **PASS 52 / 0** | **表示サーバ不要。CI で走る。** マスクは SDL の 240 行の switch を「並びとレイアウトからの算出」に置き換えたので、13 形式のマスクを SDL の定義と直接比較し、さらに 8 ビット成分の 12 形式 x 6 色で往復一致を検査する。D-31 はこの往復検査で見つかった |
| T-13 | `test/test_io` | ストリーム。ファイルの往復、型付き読み書きのバイト順、既存メモリの参照、**小刻みにしか返さない相手からの読み切り** | 2026-09-30 | **PASS 31 / 0** | **表示サーバ不要。CI で走る。** 1 回 7 バイトしか返さないストリームを自前で用意して噛ませる。普通のファイルは要求どおり返すので、これが無いと SDL から引き継いだ回避策を通せない。D-32 はこの検査で見つかった |
| T-14 | `test/test_surface` | サーフェスの生成・所有・画素・変換・反転、共有の opt-in、BMP の往復 | 2026-09-30 | **PASS 45 / 0** | **表示サーバ不要。CI で走る。** BMP は書いて読み直して一致するかを見る。幅 13 の 24 ビット（行に詰め物が要る）と 32 ビットのアルファ付きの両方。加えて手で組んだ 8 ビットパレット BMP を読ませ、他のソフトが書いた並びも解けることを確認する |
| T-15 | `test/test_blit` | ブリッタ群。等倍転送・クリップ・合成モード・カラーキー・変調・拡大縮小・塗りつぶし | 2026-09-30 | **PASS 27 / 0** | **表示サーバ不要。CI で走る。** テスト側に独立した参照実装を書いて突き合わせる。転送はクリップ規則ごと別に書き下ろし、合成は浮動小数点で計算して ±1 まで許す。実装は「形式が同じなら行ごとに Move、違えば 1 画素ずつ」と分岐するので、**どちらの経路でも同じ絵になること**を見るのが要点 |
| T-16 | `test/test_render` | レンダラ。コマンドキュー（結合・状態の重複排除）、ソフトウェアドライバの描画、三角形のラスタライザ | 2026-09-30 | **PASS 50 / 0** | **表示サーバ不要。CI で走る。** 中心の検査は「同じ絵を 2 つの経路で描いて画素が完全一致するか」。ソフトウェアドライバの速い経路（矩形・ブリット）と、既定の変換で三角形に落とした経路を、半透明の合成で描き比べる。二重塗りも塗り残しも色の違いとして出るので、top-left 規則の誤りは必ず表に出る。**実装より先に書き、空の実装に対して 13 件落ちることを確かめてから** qwen に渡した。D-33 / D-34 はこの検査で見つかった。D-35 の修正で「Clear はビューポートの外も塗る」を 1 件足した。D-39 の修正で「解放するとキューが空になる」など 3 件を足した |
| T-17 | `test/test_render_window` | ウィンドウへ描くレンダラ。フレームバッファへの描画と Present、**ウィンドウの大きさが変わったときの描画先の取り直し**、VSync の受け渡し、ウィンドウとレンダラの破棄の順序 | 2026-09-30 | **PASS 30 / 0** | **表示サーバ不要。CI で走る。** ダミーのウィンドウで検査する。取り直しの検査は、取り直しを外した実装で**異常終了（終了コード 217）**することを `-B` で確かめた。縮む向きではヒープが同じ番地を返して偶然通るので、大きくなる向きで見ている。D-35 はこの検査を書いていて見つかった |
| T-18 | `test/demo_render_window`（実機のコンポジタ。人の操作は不要） | wl_shm バッファの使い回し（release）と、フレームコールバックによる VSync が実際に効くか | 2026-09-30 | **観測項目 5 / 5** | 数字で判定する。観測内容は下表 |
| T-19 | `examples/pong --selftest` | サンプルの Pong。コンピュータ同士の対戦を 60 秒ぶん再生し、盤面（球とパドルが盤面の外へ出ない、打ち返しと得点、サーブの回数）と描画（パドルと地の色、横長のウィンドウでの帯、一時停止の表示、得点の文字）を見る。キーボードのパドルが押下状態（`IsDown`）とスキャンコードで動くことも見る | 2026-10-02 | **PASS 19 / 0** | **表示サーバ不要。CI で走る。** 盤面の計算は固定の刻みと自前の乱数で決定的なので、毎回同じ試合（2 対 0、打ち返し 34 回）になる。heaptrc でリーク 0 件も確認した。書いてみて足りなかった API は `examples/README.md` の F-1〜F-8。2026-10-02 に論理解像度と DebugText へ書き換え、得点が文字で描かれていることの検査を 2 件足した（DebugText が何も描かないと落ちることを確かめた） |
| T-20 | `test/test_keyboard` | スキャンコードとキーコード（既定の配置、名前、キーシム → Unicode）、押下状態の規則（リピート、押されていないキーの KeyUp、フォーカス喪失で全部離す）、キーマップ（AZERTY 型・ロシア語型の判定とキーイベントのキーコード）、**実際の配列 us / fr / de / ru** | 2026-09-30 | **PASS 77 / 0** | **表示サーバ不要。CI で走る。** 実際の配列は xkbcommon に名前で読ませて作るのでコンポジタが要らない（xkbcommon か xkeyboard-config が無い環境では飛ばす）。押下状態・french_numbers・D-36 の防御は、それぞれ外すと落ちることを `-B` で確かめた。heaptrc でリーク 0 件 |
| T-21 | `test/test_gl_window` | **OpenGL ES（EGL）でウィンドウに描く**。能力と断り方、コンテキストと 57 関数の取得、塗った色の読み戻し、SwapInterval 1 / 0 の速さ、最大化での面の大きさの追従、最小化・非表示で止まらないこと、破棄の順序、プロトコル違反 | 2026-10-01 | **PASS 25 / 0** | 実機のコンポジタと GPU が要るので**手元専用**。**実装（#33 / #39、Sonnet）より先に書き**、空の実装で落ちることを確かめてから渡した。200 Hz の画面で SwapInterval 1 は 200.7 fps、0 は約 32,000 fps、最小化中は 20.9 fps（合図が来ないので 1/20 秒で打ち切る）。D-37 はこの検査で見つかった |
| T-22 | `test/test_render_gles2` | **GPU（OpenGL ES 2.0）のドライバをソフトウェアのドライバと画素で比べる**。18 の場面（塗り、合成 5 種、12 枚の扇、頂点色、テクスチャの転送・変調・形式・部分更新、ビューポートとクリップ、点、線、**論理解像度・倍率・DebugText の 4 場面**）と、読み戻しの向き。ウィンドウの区間では既定のドライバの選び方、VSync、最大化、破棄の順序 | 2026-10-02 | **PASS 35 / 0** | オフスクリーンの区間は窓の無い GL（Mesa の surfaceless）で描くので**コンポジタが要らない。CI でも llvmpipe で走る**。手元では **radeonsi（GPU）と llvmpipe の 2 つの実装**で通した。**CI（Ubuntu 24.04、Mesa 25.2.8）では最初止まった**（D-40。FPC の浮動小数点の例外）。直した後、24.04 の環境（下の使い捨て検証）でも通した。塗り・転送・ビューポート・点・水平垂直の線は差 0、合成・頂点色・変調も最大差 1。斜めの線も両実装で差 0。2026-10-02 に足した論理解像度・倍率・DebugText の 4 場面は llvmpipe で最大差 0（クラウドの Ubuntu 24.04、Mesa 25.2.8。オフスクリーンの区間 24 件。窓の区間は手元で未実行）。**実装（#43、Sonnet）より先に書き**、空の実装で失敗することを確かめた（最初は「GL が無ければ飛ばす」になっていて、空の実装が飛ばされて通ってしまうのを直した）。SDL から外れた 2 箇所（線の端の延ばし量、テクセルの境目の寄せ）は、SDL の値に戻すと落ちることを確かめた |
| T-23 | `test/test_render_logical` | **拡大率（Scale）・論理解像度（SetLogicalPresentation の 5 方式）・DebugText**。当てはめの矩形 10 通り（floor が効く値、整数倍が 1 倍未満になる値を含む）、塗り・ビューポート・クリップ・転送・点・線の変換、ウィンドウ座標との往復、文字の字形と色、ダミーのウィンドウの大きさの追従 | 2026-10-02 | **PASS 49 / 0** | **表示サーバ不要。CI で走る。** 期待する絵はテスト側で別に組み立て、全画素で比べる。字形はヘッダのコメントの絵から書き写した（生成器の表とは別の道筋）。閉じた枠は半透明で描き、二重塗りが色の差に出るようにした。**実装より先に書き、空の実装で 42 件が落ちる**ことを確かめた。歯の確認（`-B`）: SDL の字形の判定に戻す（D-42）、閉じた折れ線の始点の省略を外す、終点を描く規則を外す、ブレゼンハムの `d < 0` を `<=` に、IntegerScale の 1 倍の下限を外す、ビューポートやクリップに倍率を掛けない、文字の色を実行時に読む（D-43）の 7 通りがそれぞれ落ちる。最初は「終点を描く規則」を外しても通った（閉じた枠しか描いていなかった）ので、開いた折れ線の場面を足した。**SDL の実物との突き合わせ**は下の使い捨て検証 |

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

### T-18 で実際に観測したもの

検証環境は labwc、画面は DP-3（2560x1080、**200 Hz**）。VSync が効いているかは
「描画が画面より速く終わる大きさ」で比べないと分からない。640x400 では描画そのものが
約 157 fps しか出ず、VSync の有無で差が出なかった（待つ前に次の合図が来ている）。
最大化・復帰・最小化の 3 行は、同じレンダラを使う使い捨ての計測プログラム
（スクラッチパッド。恒久化していない）で、各段階 1.5 秒ずつ取った数字である。

| 観測項目 | 観測した内容 |
|---|---|
| **VSync で画面のリフレッシュに揃う** | 160x100、VSync あり: 4.0 秒で 801 フレーム、**平均 200.2 fps**。VSync なし: 9222 フレーム、平均 2305.3 fps |
| **release を待ってバッファを使い回す** | VSync ありでは shm バッファは累計 1 枚（コンポジタが次のフレームまでに release を返す）。VSync なしでは 2 枚目が作られ、それ以上は増えなかった |
| 大きさの変更 | 最大化（2560x1022）→ 復帰（200x120）で、それぞれ新しい大きさのバッファが 1 枚ずつ作られ、描画も追従した。最大化中も 199.1 fps |
| **隠れたウィンドウで止まらない** | 最小化するとフレームコールバックが来なくなり、毎フレーム上限の 1/20 秒で打ち切って**ちょうど 20.0 fps**（1.5 秒で 30 回打ち切り）。SDL の GLES 経路と同じ振る舞い |
| **GPU のドライバ**（`demo_render_window … gles2`） | 同じ場面を 640x400、VSync なしで: ソフトウェア 161.4 fps、**GLES2 21,807.9 fps**（約 135 倍）。VSync ありの GLES2 は 200.5 fps。Sonnet の計測では 16x16 のテクスチャ付き四角形 2,000 個を 1 フレームで約 2,700 fps（毎秒 550 万個） |
| プロトコル違反なし | どの段階でも `wl_display_get_error` は 0 |

## 2. コンパイル検証

| # | 対象 | 最終実行 | 結果 | 備考 |
|---|---|---|---|---|
| C-01 | `src/` の全ユニット（Types / Errors / Unicode / Core.Base / Core / Events / Events.Keymap / IO / Pixels / Platform 系 7 本 / TextInput 系 3 本 / Video 系 12 本 / Surface 系 3 本 / Render 系 4 本） | 2026-10-01 | **PASS** | 全 38 ユニット（ほかに生成したキーボードの表 2 本、C-07）。到達過程で D-03〜D-08、D-19 を修正 |
| C-02 | `tools/wlscan-pas` | 2026-09-28 22:24 | **PASS** | — |
| C-03 | 生成プロトコル 21 ユニット（9230 行） | 2026-09-28 22:24 | **PASS 21 / 21** | 初回は 9 / 21 が失敗（D-10〜D-12）。§9.2 が挙げる XML のうち、`reference/SDL/wayland-protocols/` にあるものすべて |
| C-04 | **rawpaco 静的解析（激辛モード `--fail-on=warning`）** — `src` / `src/generated` / `test` / `spikes` / `tools` / `examples` の全 Pascal ファイル | 2026-10-02 | **PASS 指摘 0 件** | 導入初回は 2 件の指摘（D-20）。修正後は 0 件。`.github/workflows/lint.yml` で push / pull_request ごとに走る |
| C-05 | **図と実装の整合性検査**（`tools/check-diagrams.sh`） — 英日の Mermaid ブロック同一性、図に出てくる型 51 個の実在 | 2026-10-02 | **PASS 不整合 0 件** | `.github/workflows/lint.yml` で push ごとに走る |
| C-06 | **Origin 行と設計書の突き合わせ**（`tools/checkorigin.bb`） — 第11章の由来列との一致、移植部分の SDL 著作権表示の有無 | 2026-10-02 | **PASS 不一致 0 件** | 第 11 章のユニット 93 件に対して 61 ファイルを検査。導入初回は 10 件の不一致（D-30）。`.github/workflows/lint.yml` で push ごとに走る |
| C-07 | **キーボードの表の生成**（`tools/genscancodes.bb`） — SDL のソースから `PaPiMeLa.Keycodes` と `.Keycodes.Tables` を作る | 2026-09-30 | **PASS** | スキャンコード 249、キーコード 257（SDLK_ の定義 259 から 2 つのマスクを除く）、evdev 表 768（注釈の番号と並びを突き合わせる）、名前 247、既定キー 175、Unicode 範囲 20（1525 項目）。大文字小文字だけが違う名前が無いことも検査する（D-09 系）。**imKStoUCS.c の範囲の食い違い（D-36）を警告する**。reference/SDL が要るので CI では走らせない |
| C-09 | **DebugText の字形の生成**（`tools/gendebugfont.bb`） — SDL の `SDL_render_debug_font.h` から `src/generated/debug_font.inc` を作る | 2026-10-02 | **PASS** | 190 字形・1520 バイト。字形の数、並び（33..126、161..255、印）、**各バイトの値と同じ行のコメントの絵の一致**を確かめ、合わなければ止まる。初回は最後の字形（字形の無い文字の印）で止まった。この字形だけコメントの絵が左右逆に書かれている。SDL で実際に描いて値のほうが正しいことを確かめ、生成器に例外として名前で書いた。テストの側もこの字形を絵から写していて誤っていたので直した |
| C-08 | **EGL / GLES2 の定数の生成**（`tools/genkhronos.bb`） — Khronos のヘッダから `src/generated/egl_constants.inc` と `gles2_constants.inc` を作る | 2026-10-01 | **PASS** | egl.h の数値定数 163 と、SDL が使う eglext.h の 20、gl2.h の 303 と gl2ext.h の 4。拡張の一覧にあってヘッダに無い名前があれば止まる。大文字小文字の衝突も検査する |

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
| Vulkan / デスクトップ GL のレンダラ / クリップボード / 任意ピクセルのカーソル | **未実装** | 第 11 章 #38、#44、#67。**GPU のレンダラ（GLES2）は実装済み**（T-22）。レンダラはソフトウェアのみ。`wl_shm` のバッファ（#39 の shm 側）は入ったので、任意ピクセルのカーソルはこれを使って足せる |
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
| SDL の `SDL_KeySymToUcs4`（imKStoUCS.c）と xkbcommon の `xkb_keysym_to_utf32` は同じか | 2026-09-30 | **違う。** C で両方を全キーシム（1〜0xFFFF と Unicode キーシム）で呼び比べ、588 個が食い違った（SDL は 0x59x のペルシア数字や 0x68x の拡張キリル文字などの古いキーシムも文字にするが、xkbcommon は 0 を返す。逆に 0xFFxx の制御キーとテンキーの 27 個は、xkbcommon だけが文字（制御文字を含む）にする）。xkbcommon で代用せず、SDL の表を移植すると決めた。この比較の途中で SDL 側が 0x58a で異常終了し、D-36 が見つかった |
| 移植した `PMLKeysymToUcs4` は SDL の C と同じ値を返すか | 同日 | **全件一致**。1〜0xFFFF（D-36 の 6 個を除く）と Unicode キーシム 512 個、計 66,041 個で差分 0。D-36 の 6 個は 0 を返す |
| qwen が C の宣言から書いた GLES2 の関数表（57 個）は正しいか | 2026-10-01 | **全件一致**。型の対応表で C の戻り値と引数の型の並びを Pascal に写し、qwen の出力と突き合わせた（名前の A 接頭辞、予約語、大文字小文字の重複も見る）。検査側の歯は、引数の順序・戻り値・予約語の誤りを 1 つずつ入れて 3 件とも検出することで確かめた |
| EGL と GLES2 の結合は動くか（コンポジタ無し） | 同日 | **動く**。Mesa の surfaceless（`EGL_PLATFORM_SURFACELESS_MESA`）でディスプレイを作り、窓の無い GLES コンテキストを現在にして 57 関数がすべて取れた。GL_RENDERER は radeonsi（内蔵 GPU）、OpenGL ES 3.2 Mesa 26.0.8。GLES2 レンダラをヘッドレスで検査する足場になる |
| Mesa の eglGetProcAddress は無い名前に nil を返すか | 同日 | **返さない**（Sonnet の実測をこちらでも確認）。glvnd の libEGL は `gl` で始まる名前なら何でも番地を返す。そこでコア関数は libGLESv2 から直接引き、拡張の接尾辞（KHR、EXT、OES…）の付いた名前だけ eglGetProcAddress に任せた |
| eglGetError は読むと消えるか | 同日 | **消える**。ネイティブウィンドウに nil を渡して eglCreateWindowSurface を失敗させ、1 回目 `EGL_BAD_NATIVE_WINDOW`、2 回目 `EGL_SUCCESS`。D-38 の根拠 |
| CI（Ubuntu 24.04）の Mesa を手元で動かせるか | 同日 | **動かせる**。Ubuntu 公式の最小 rootfs（`ubuntu-base-24.04.5-base-amd64.tar.gz`、SHA256 照合済み）をスクラッチパッドに展開し、bwrap（root 不要。`/dev/dri` は見えない）の中で apt により fpc と CI と同じ Mesa のパッケージを入れた（man-db など所有者の切り替えが要るものだけ失敗するが、検査には関係しない）。CI だけで止まった GLES2 の検査が、ここで再現した（D-40）|
| C の GL の実装は FPC の浮動小数点の例外の設定とぶつかるか | 同日 | **ぶつかる**。上の環境（Mesa 25.2.8、LLVM 20）で EGL を一歩ずつ呼ぶと、例外が有効（FPC の既定）ならコンテキストの作成で `EInvalidOp`、無効なら llvmpipe でコンテキストができ 57 関数もそろった。手元の Mesa 26 / LLVM 21 ではたまたま起きない |
| 論理解像度・倍率・DebugText を SDL の実物と画素で比べる | 2026-10-02 | **26 場面中 20 場面が全画素一致**。SDL（`reference/SDL` の版）を表示サーバ無しで静的に作り（`SDL_UNIX_CONSOLE_BUILD`）、80x40 のサーフェスへのソフトウェアレンダラで同じ場面を描いて比べた。当てはめの矩形 10 通りは SDL の `SDL_GetRenderLogicalPresentationRect` と全一致。残り 6 場面の差はすべて説明がつく: (1) 半透明の合成の丸め（3 場面。形は一致、色が 1 だけ違う。SDL は `0x9f`、papimela は `0xa0`。SDL は切り捨て、papimela は四捨五入。ソフトウェアのブリッタの既存の差で、今回の変更ではない。D-44）、(2) 小数の矩形の塗り（倍率 1.5）。SDL のソフトウェアドライバは x と幅を別々に切り捨てる。papimela は「中心が入る画素」を塗り、三角形の経路と GLES2 に揃えている（T-16 の設計どおりの逸脱）、(3) 小数の頂点の三角形（論理 7x3、11.4 倍）で辺の 1 画素の差、(4) 小数倍（2.35 倍）の DebugText。SDL は PIXELART、papimela は Nearest（PIXELART が無い）。整数倍では文字も全一致。**D-42 もここで実測した**: SDL は é（U+E9）と ¾（U+BE）を字形の無い文字の印で描き、½（U+BD）は正しく描く |

## 5. 再現方法

```bash
cd papimela
# キーボードの表を作り直す（reference/SDL が要る。出力は src/generated/ へ）。
./tools/genscancodes.bb
# EGL / GLES2 の定数を作り直す（同じく reference/SDL が要る）。
./tools/genkhronos.bb
# DebugText の字形を作り直す（同じく reference/SDL が要る）。
./tools/gendebugfont.bb
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_fcitx_textinput   test/test_fcitx_textinput.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_wayland_protocols test/test_wayland_protocols.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_wayland_window    test/test_wayland_window.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_key_routing     test/test_key_routing.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/demo_japanese_input  test/demo_japanese_input.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_pointer_constraints test/test_pointer_constraints.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_touch_cursor        test/test_touch_cursor.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_dummy_video          test/test_dummy_video.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_pixels               test/test_pixels.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_io                   test/test_io.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_surface              test/test_surface.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_blit                 test/test_blit.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_render               test/test_render.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_render_window        test/test_render_window.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_render_logical       test/test_render_logical.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_keyboard             test/test_keyboard.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_gl_window            test/test_gl_window.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_render_gles2         test/test_render_gles2.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/demo_render_window        test/demo_render_window.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -oexamples/pong               examples/pong.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/demo_pointer_constraints test/demo_pointer_constraints.pas
fpc -O1 -gl spikes/spike1_wayland.pas && fpc -O1 -gl spikes/spike2_fcitx.pas
./spikes/spike1_wayland && ./spikes/spike2_fcitx
./test/test_fcitx_textinput && ./test/test_wayland_protocols && ./test/test_wayland_window
./test/test_key_routing && ./test/test_pointer_constraints && ./test/test_touch_cursor
./test/test_gl_window   # GPU と EGL が要る

# 表示サーバが無くても通るテスト（CI で走るのはこの 10 本）。
env -u WAYLAND_DISPLAY -u DISPLAY ./test/test_dummy_video
env -u WAYLAND_DISPLAY -u DISPLAY ./test/test_pixels
env -u WAYLAND_DISPLAY -u DISPLAY ./test/test_io
env -u WAYLAND_DISPLAY -u DISPLAY ./test/test_surface
env -u WAYLAND_DISPLAY -u DISPLAY ./test/test_blit
env -u WAYLAND_DISPLAY -u DISPLAY ./test/test_render
env -u WAYLAND_DISPLAY -u DISPLAY ./test/test_render_window
env -u WAYLAND_DISPLAY -u DISPLAY ./test/test_render_logical
env -u WAYLAND_DISPLAY -u DISPLAY ./test/test_keyboard
env -u WAYLAND_DISPLAY -u DISPLAY ./examples/pong --selftest
env -u WAYLAND_DISPLAY -u DISPLAY LIBGL_ALWAYS_SOFTWARE=1 ./test/test_render_gles2   # llvmpipe

# T-18（実機のコンポジタ）。小さいウィンドウで VSync の有無を比べる。
./test/demo_render_window 4 vsync 160x100
./test/demo_render_window 4 novsync 160x100

# T-07（対話）。ウィンドウをクリックしてフォーカスし、日本語を打つ。
# 途中で別ウィンドウへ移って戻ると、フォーカスの往復が IME に伝わることも確認できる。
./test/demo_japanese_input 60

# T-09（対話）。カーソルをウィンドウの中に入れて G / R / C / S / H で切り替える。
./test/demo_pointer_constraints 60
```

実行前提: Wayland セッション、fcitx5 稼働、日本語エンジン（mozc）が利用可能であること。
T-02 と T-03 は IME の状態を変更する（`Controller1.Activate` を呼ぶ）ため、実行後に
入力メソッドがアクティブになっている場合がある。
