# テスト実行一覧

papimela で実行したテストの記録。日時は実測値（ファイルの mtime と git のコミット時刻、
および最終一括実行の時刻）に基づく。

最終一括実行: **2026-10-05、手元の実機**（自動テスト 23 本すべて成功、アサーション 724 件・失敗 0 件。`-B` で全部作り直して実行）。
クラウドで足した T-23〜T-26 と、#45（バックエンドの登録制）・F-7・論理解像度の後の手元専用の検査（T-01〜T-06、T-08、T-10、T-21、
T-22 の窓の区間）を、labwc・radeonsi・fcitx5-mozc の実機で初めて流した。どの行も件数は表のとおりで、
Wayland と fcitx を使うものは `video backend: wayland` / `text input backend: fcitx` が選ばれた（登録の付け忘れが無い）。
T-18 の計測も同日: 640x400 でソフトウェアは VSync あり 159.3 fps・なし 160.5〜160.8 fps（3 回）、GLES2 は VSync あり
200.2 fps・なし 21,890 fps、プロトコル違反 0。静的検査（rawpaco・checkorigin・図・`genumbrella.bb --check`）も通した。

以下はクラウドのセッション（2026-10-02〜05）の記録: T-23 を足し、T-19 と T-22 に検査を足した（20 本・639 件）。さらに T-24 を足し、T-11 に検査を足した（21 本・662 件）。さらに T-25 と T-26 を足した（23 本・724 件）。足した分と、CI で走る 9 本・T-19・T-22 のオフスクリーンの区間はクラウドの Ubuntu 24.04 で通した。手元専用の検査は追加後に流し直していない。
対話テストも 2026-10-05〜06 に持ち主が実機で流し、すべて想定どおりだった: T-07（文節と確定文字列が届く）、T-09（下の表に追記）、
Pong の操作（滑らか、CPU 約 22%、一時停止、大きさを変えたときの帯付きの追従、得点の文字、2 人対戦への切り替え）。

## 1. 実行可能テスト

| # | テスト | 目的 | 最終実行 | 結果 | 備考 |
|---|---|---|---|---|---|
| T-01 | `spikes/spike1_wayland` | `wl_proxy_marshal_flags` を FPC の `cdecl; varargs` で呼べるか。C → Pascal コールバック、外部データシンボル取り込み | 2026-09-28 22:33 | **PASS 10 / 0** | 初回はコンパイル不可（D-01）。修正後は一度も失敗していない |
| T-02 | `spikes/spike2_fcitx` | fcitx5 の D-Bus で文節区切り・周辺テキスト・周辺削除が取れるか | 2026-09-28 22:33 | **PASS 8 / 0** | 初回実行は 4 項目 FAIL（D-02）。**周辺削除はアサーションを置いていない**（下記 3 を参照） |
| T-03 | `test/test_fcitx_textinput` | papimela の公開 API（`TPMLContext` + イベントキュー）経由で文節情報が失われないか | 2026-09-28 22:33 | **PASS 18 / 0** | 21:44 時点ではメソッドポインタ版で PASS。21:57 にイベントキュー版へ全面改稿し再検証（D-05〜D-08 を経由） |
| T-04 | `test/test_wayland_protocols` | 生成したプロトコルバインディングが実機のコンポジタと通信できるか | 2026-09-28 22:33 | **PASS 24 / 0** | 自前構築した拡張プロトコルの記述子が受理され、`configure` イベントも到達 |
| T-05 | `test/test_wayland_window` | Wayland ビデオバックエンド。ウィンドウ生成、configure → ack_configure、wl_shm への描画、リサイズ通知 | 2026-09-28 22:49 | **PASS 19 / 0** | 実際にウィンドウが約 2 秒表示される。ディスプレイ 2 台を列挙、120 フレーム描画、最大化/復帰の往復も確認 |
| T-06 | `test/test_key_routing` | キーの IME 転送経路（§7.5）。消費されたキーが KeyDown にならないこと | 2026-10-06 | **PASS 18 / 0** | コンポジタへキーを注入できないため、シートが届けるのと同じ形の合成キーを `TPMLKeyboardState.SendKey` へ直接流す。実キーボード経由の確認は `test/demo_japanese_input`（対話）。2026-10-06 に「KeyDown を出さなかったキーの KeyUp も出さない」を足した（D-47。直す前は 14 件の KeyUp が出て落ちた）。合成キーにシートと同じスキャンコードを付けるよう直した（付けていなかったので KeyUp の規則が働く道を通っていなかった）。同日、「fcitx5 の動くデスクトップでは fcitx が選ばれる」を足した（#48。fcitx5 は IBus を装うので、IBus がそれを断らないと IBus が選ばれる。見分けを外すと落ちることを確かめた）。見分けを外した版を流した直後に 1 回だけ別の 1 件が落ち、続けて 5 回流しても再現しなかった（外した版が fcitx5 の IBus 互換の口に入力コンテキストを作った影響と見ている。原因は確かめていない） |
| T-07 | `test/demo_japanese_input`（**対話・人の操作**） | 実キーボードから fcitx5 を経て文節情報と確定文字列がアプリへ届くか。ウィンドウのフォーカス往復が IME に伝わるか | 2026-10-06 | **PASS 観測項目 6 / 6** | #45（fcitx の登録）と F-7 の後も 2026-10-06 に持ち主が確認。アサーションではなく人の目による確認。観測できたものを下表に残す。D-21・D-22・D-23 はこのデモで見つかった。**2026-10-06、`PAPIMELA_IME=wayland`（text-input-v3、#49）でも持ち主が操作し、日本語に切り替えて打鍵・変換・確定が想定どおりだった**。text-input-v3 では fcitx5 の入力コンテキストが英語（直接入力）から始まるので、最初は切り替えずに試して「スペースで変化なし」に見えた（想定どおり）。細目の観測（起動ログのバックエンド名、注目範囲の強調、候補ウィンドウの位置）は個別には報告を受けていない |
| T-08 | `test/test_pointer_constraints` | ポインタ拘束。能力への写像、要求の記録、そして**拘束の張り替えがプロトコルに違反しないこと** | 2026-09-29 | **PASS 23 / 0** | ロックと閉じ込めを同じシート・同じサーフェスに同時に作ると接続が切られるので、`wl_display_get_error` が終始 0 であることが張り替え順序の証明になる。拘束が**有効になる**かはカーソル位置に依存するため観測扱い（T-09 が担当）。D-24 はこのテストで見つかった |
| T-09 | `test/demo_pointer_constraints`（**対話・人の操作**） | カーソルをウィンドウ内に入れた状態でロック / 閉じ込め / 相対移動 / カーソル形状が実際に有効になるか | 2026-10-06 | **PASS 観測項目 5 / 5** | 人の目による確認。観測内容は下表。D-25〜D-28 はこのテストで見つかった（すべてデモ側の欠陥） |
| T-10 | `test/test_touch_cursor` | タッチの状態機械（移動量の算出、ウィンドウの引き継ぎ、取り消し）と cursor-shape-v1 の対応表・能力・切り替え | 2026-09-29 | **PASS 41 / 0** | タッチは合成入力。Wayland は移動量を送らず motion / up にウィンドウも付けないので、そこを埋める部分がタッチ対応の実体であり、ハードウェア無しで検証できる。**実機のタッチパネルは手元に無く未検証**。カーソル形状の実際の適用はカーソル位置に依存するため T-09 が担当 |
| T-11 | `test/test_dummy_video` | **表示サーバ無し**で公開 API（ウィンドウ生成・リサイズ・状態・フレームバッファ）が動くか | 2026-10-02 | **PASS 45 / 0** | `WAYLAND_DISPLAY` と `DISPLAY` を外して実行しても通る。**CI で走る実行テストの 1 本**。D-29 はこのテストを書いていて見つかった。2026-10-02 に Context のオプション（値型。F-7）の 5 件を足した: 既定値、`Default` を通さない変数も既定値になる（`Initialize` 演算子。外すと落ちる）、容量 0 は `EPMLArgument`（外すと落ちる）、作ったときの値が使われる、オプション無しの Create |
| T-12 | `test/test_pixels` | ピクセル形式の識別、マスクの導出、色 ↔ 画素値の往復 | 2026-09-29 | **PASS 52 / 0** | **表示サーバ不要。CI で走る。** マスクは SDL の 240 行の switch を「並びとレイアウトからの算出」に置き換えたので、13 形式のマスクを SDL の定義と直接比較し、さらに 8 ビット成分の 12 形式 x 6 色で往復一致を検査する。D-31 はこの往復検査で見つかった |
| T-13 | `test/test_io` | ストリーム。ファイルの往復、型付き読み書きのバイト順、既存メモリの参照、**小刻みにしか返さない相手からの読み切り** | 2026-09-30 | **PASS 31 / 0** | **表示サーバ不要。CI で走る。** 1 回 7 バイトしか返さないストリームを自前で用意して噛ませる。普通のファイルは要求どおり返すので、これが無いと SDL から引き継いだ回避策を通せない。D-32 はこの検査で見つかった |
| T-14 | `test/test_surface` | サーフェスの生成・所有・画素・変換・反転、共有の opt-in、BMP の往復 | 2026-09-30 | **PASS 45 / 0** | **表示サーバ不要。CI で走る。** BMP は書いて読み直して一致するかを見る。幅 13 の 24 ビット（行に詰め物が要る）と 32 ビットのアルファ付きの両方。加えて手で組んだ 8 ビットパレット BMP を読ませ、他のソフトが書いた並びも解けることを確認する |
| T-15 | `test/test_blit` | ブリッタ群。等倍転送・クリップ・合成モード・カラーキー・変調・拡大縮小・塗りつぶし | 2026-09-30 | **PASS 27 / 0** | **表示サーバ不要。CI で走る。** テスト側に独立した参照実装を書いて突き合わせる。転送はクリップ規則ごと別に書き下ろし、合成は浮動小数点で計算して ±1 まで許す。実装は「形式が同じなら行ごとに Move、違えば 1 画素ずつ」と分岐するので、**どちらの経路でも同じ絵になること**を見るのが要点 |
| T-16 | `test/test_render` | レンダラ。コマンドキュー（結合・状態の重複排除）、ソフトウェアドライバの描画、三角形のラスタライザ | 2026-09-30 | **PASS 50 / 0** | **表示サーバ不要。CI で走る。** 中心の検査は「同じ絵を 2 つの経路で描いて画素が完全一致するか」。ソフトウェアドライバの速い経路（矩形・ブリット）と、既定の変換で三角形に落とした経路を、半透明の合成で描き比べる。二重塗りも塗り残しも色の違いとして出るので、top-left 規則の誤りは必ず表に出る。**実装より先に書き、空の実装に対して 13 件落ちることを確かめてから** qwen に渡した。D-33 / D-34 はこの検査で見つかった。D-35 の修正で「Clear はビューポートの外も塗る」を 1 件足した。D-39 の修正で「解放するとキューが空になる」など 3 件を足した |
| T-17 | `test/test_render_window` | ウィンドウへ描くレンダラ。フレームバッファへの描画と Present、**ウィンドウの大きさが変わったときの描画先の取り直し**、VSync の受け渡し、ウィンドウとレンダラの破棄の順序 | 2026-09-30 | **PASS 30 / 0** | **表示サーバ不要。CI で走る。** ダミーのウィンドウで検査する。取り直しの検査は、取り直しを外した実装で**異常終了（終了コード 217）**することを `-B` で確かめた。縮む向きではヒープが同じ番地を返して偶然通るので、大きくなる向きで見ている。D-35 はこの検査を書いていて見つかった |
| T-18 | `test/demo_render_window`（実機のコンポジタ。人の操作は不要） | wl_shm バッファの使い回し（release）と、フレームコールバックによる VSync が実際に効くか | 2026-09-30 | **観測項目 5 / 5** | 数字で判定する。観測内容は下表 |
| T-19 | `examples/pong --selftest` | サンプルの Pong。コンピュータ同士の対戦を 60 秒ぶん再生し、盤面（球とパドルが盤面の外へ出ない、打ち返しと得点、サーブの回数）と描画（パドルと地の色、横長のウィンドウでの帯、一時停止の表示、得点の文字）を見る。キーボードのパドルが押下状態（`IsDown`）とスキャンコードで動くことも見る | 2026-10-02 | **PASS 19 / 0** | **表示サーバ不要。CI で走る。** 盤面の計算は固定の刻みと自前の乱数で決定的なので、毎回同じ試合（2 対 0、打ち返し 34 回）になる。heaptrc でリーク 0 件も確認した。書いてみて足りなかった API は `examples/README.md` の F-1〜F-8。2026-10-02 に論理解像度と DebugText へ書き換え、得点が文字で描かれていることの検査を 2 件足した（DebugText が何も描かないと落ちることを確かめた）。同日、Present が待たないとき（VSync を断られたとき、または受け付けても待たないとき）はフレームの残りを `DelayNS` で眠るようにした（F-6）。ダミーのビデオで遊ぶ側を 3 秒動かすと、CPU 時間は 3.00 秒（1 コアを使い切る）から 0.63 秒になった |
| T-20 | `test/test_keyboard` | スキャンコードとキーコード（既定の配置、名前、キーシム → Unicode）、押下状態の規則（リピート、押されていないキーの KeyUp、フォーカス喪失で全部離す）、キーマップ（AZERTY 型・ロシア語型の判定とキーイベントのキーコード）、**実際の配列 us / fr / de / ru** | 2026-09-30 | **PASS 77 / 0** | **表示サーバ不要。CI で走る。** 実際の配列は xkbcommon に名前で読ませて作るのでコンポジタが要らない（xkbcommon か xkeyboard-config が無い環境では飛ばす）。押下状態・french_numbers・D-36 の防御は、それぞれ外すと落ちることを `-B` で確かめた。heaptrc でリーク 0 件 |
| T-21 | `test/test_gl_window` | **OpenGL ES（EGL）でウィンドウに描く**。能力と断り方、コンテキストと 57 関数の取得、塗った色の読み戻し、SwapInterval 1 / 0 の速さ、最大化での面の大きさの追従、最小化・非表示で止まらないこと、破棄の順序、プロトコル違反 | 2026-10-01 | **PASS 25 / 0** | 実機のコンポジタと GPU が要るので**手元専用**。**実装（#33 / #39、Sonnet）より先に書き**、空の実装で落ちることを確かめてから渡した。200 Hz の画面で SwapInterval 1 は 200.7 fps、0 は約 32,000 fps、最小化中は 20.9 fps（合図が来ないので 1/20 秒で打ち切る）。D-37 はこの検査で見つかった |
| T-22 | `test/test_render_gles2` | **GPU（OpenGL ES 2.0）のドライバをソフトウェアのドライバと画素で比べる**。18 の場面（塗り、合成 5 種、12 枚の扇、頂点色、テクスチャの転送・変調・形式・部分更新、ビューポートとクリップ、点、線、**論理解像度・倍率・DebugText の 4 場面**）と、読み戻しの向き。ウィンドウの区間では既定のドライバの選び方、VSync、最大化、破棄の順序 | 2026-10-09 | **PASS 43 / 0**（llvmpipe ではオフスクリーンの区間 30 / 0） | オフスクリーンの区間は窓の無い GL（Mesa の surfaceless）で描くので**コンポジタが要らない。CI でも llvmpipe で走る**。手元では **radeonsi（GPU）と llvmpipe の 2 つの実装**で通した。**CI（Ubuntu 24.04、Mesa 25.2.8）では最初止まった**（D-40。FPC の浮動小数点の例外）。直した後、24.04 の環境（下の使い捨て検証）でも通した。塗り・転送・ビューポート・点・水平垂直の線は差 0、合成・頂点色・変調も最大差 1。斜めの線も両実装で差 0。2026-10-02 に足した論理解像度・倍率・DebugText の 4 場面は llvmpipe で最大差 0（クラウドの Ubuntu 24.04、Mesa 25.2.8。オフスクリーンの区間 24 件。窓の区間は手元で未実行）。**実装（#43、Sonnet）より先に書き**、空の実装で失敗することを確かめた（最初は「GL が無ければ飛ばす」になっていて、空の実装が飛ばされて通ってしまうのを直した）。SDL から外れた 2 箇所（線の端の延ばし量、テクセルの境目の寄せ）は、SDL の値に戻すと落ちることを確かめた。**2026-10-09（#41）に 3 場面と描画先の検査を足した**: 回す（90 度・反転・30 度）と平行四辺形、敷き詰めと 9 つ分け、描画先のテクスチャ（4 形式の描画先・合成・クリップ・描画先どうし）、描画先の読み戻し（出力より大きい描画先・BGRA の並び）、ウィンドウのレンダラの描画先の上下。radeonsi と llvmpipe の両方で最大差 0〜1。歯の確認（`-B`）: 頂点の色を入れ替えない、塗りの色を入れ替えない、シェーダが描画先の形式を見ない、描画先も上下を反転する、読み戻しの形式を RGBA に固定、読む範囲を出力の大きさで切る（最初は描画先が出力より小さくて見逃したので、大きい描画先にした）、FBO を張らない、X の形式のアルファを 1 にしない、の 8 通りがそれぞれ落ちる |
| T-23 | `test/test_render_logical` | **拡大率（Scale）・論理解像度（SetLogicalPresentation の 5 方式）・DebugText**。当てはめの矩形 10 通り（floor が効く値、整数倍が 1 倍未満になる値を含む）、塗り・ビューポート・クリップ・転送・点・線の変換、ウィンドウ座標との往復、文字の字形と色、ダミーのウィンドウの大きさの追従 | 2026-10-02 | **PASS 49 / 0** | **表示サーバ不要。CI で走る。** 期待する絵はテスト側で別に組み立て、全画素で比べる。字形はヘッダのコメントの絵から書き写した（生成器の表とは別の道筋）。閉じた枠は半透明で描き、二重塗りが色の差に出るようにした。**実装より先に書き、空の実装で 42 件が落ちる**ことを確かめた。歯の確認（`-B`）: SDL の字形の判定に戻す（D-42）、閉じた折れ線の始点の省略を外す、終点を描く規則を外す、ブレゼンハムの `d < 0` を `<=` に、IntegerScale の 1 倍の下限を外す、ビューポートやクリップに倍率を掛けない、文字の色を実行時に読む（D-43）の 7 通りがそれぞれ落ちる。最初は「終点を描く規則」を外しても通った（閉じた枠しか描いていなかった）ので、開いた折れ線の場面を足した。**SDL の実物との突き合わせ**は下の使い捨て検証 |
| T-24 | `test/test_time` | **待つ API**（`Delay` / `DelayNS` / `DelayPrecise`）。DelayPrecise の手順を偽の時計で動かして眠りの列と空回りの回数を SDL と比べる 5 場面、本物の時計で早く戻らないことと遅れ、待っている間の CPU 時間、1 ms ごとのシグナルで割り込まれても眠り切ること（EINTR）、`TPMLTimerService` から Context 無しで呼べること | 2026-10-02 | **PASS 18 / 0** | **表示サーバ不要。CI で走る。** **実装（#9、Sonnet）より先に書き**、空の実装で 12 件落ちることを確かめた。実装した Sonnet が検査の誤りを 2 つ指摘し、どちらも確かめて直した: 偽の時計の 1 場面で期待する眠りを 1 回多く書いていた（コメントの手順では 7 回）、`setitimer` へ `const` の record を渡してタイマーが動いていなかった（D-45）。歯の確認（`-B`）: EINTR で寝直さない、Delay が空回りで待つ、遅れの最大を測らない、短い眠りから遅れの分を引かない、2 つめの 1 ms ずつの眠りを外す、DelayPrecise が全部空回りする、の 6 通りがそれぞれ落ちる。観測: Delay(20) は 20.1 ms、DelayPrecise(3 ms) の遅れは中央値 0.000 ms・最大 0.09 ms、DelayPrecise(100 ms) の CPU 時間は 2.1 ms（クラウドの Ubuntu 24.04） |
| T-25 | `test/test_backends` | **バックエンドの登録とリンクの絞り込み**（#45）。`PaPiMeLa.Backends` を uses しないプログラムで、Wayland / Fcitx / GLES2 が実行ファイルに**リンクされていない**こと（クラス名を自分の実行ファイルから探す。探す文字列は実行時に組み立てる）、ビデオ・IME・レンダラの登録の規則（優先度、登録順、Connect を断ったら次、名前で指定したら他へ逃げない、大文字小文字、2 度目の登録、リンクされていない名前を断るときに使える名前と `PaPiMeLa.Backends` を添える） | 2026-10-02 | **PASS 29 / 0** | **表示サーバ不要。CI で走る。** **実装（Sonnet）より先に書き**、空の実装で 21 件落ちることを確かめた（最初は空の実装で例外が漏れて途中で止まったので、各検査が例外を失敗として数えるよう直した）。歯の確認（`-B`）: 優先度を無視する、名前を大文字小文字で区別する、2 度目の登録を許す、名前で指定したバックエンドが断ったら他へ逃げる、レンダラの Prefers を無視する、`PaPiMeLa.Video` が Wayland を uses し直す、の 6 通りがそれぞれ落ちる |
| T-26 | `test/test_umbrella` | **`uses PaPiMeLa` だけで書けること**と **`TPMLApplication`**（#45）。公開層の各ユニットから型・定数・関数・helper（別名にできないので派生で置く）を通し、全バックエンドが登録・リンクされること、アプリのループの約束（呼ぶ順、イベントが DoIterate より先、DoQuit は必ず 1 回、例外のときも DoQuit(Failure) を先に、WaitForEvents、RunMain が解放する） | 2026-10-02 | **PASS 33 / 0** | **表示サーバ不要。CI で走る。** 先に書き、アンブレラが空のうちはコンパイルできないこと、公開層を直接 uses した写しでは登録とアプリの 20 件が落ちることを確かめた。書いた検査の誤り 2 つ（ウィンドウを作ったときのイベントが Quit より先に並ぶ、空の配列の 0 番目を読む）は渡す前に直した。歯の確認（`-B`）: 例外のときに DoQuit を呼ばない、DoIterate をイベントより先に呼ぶ、DoQuit が Context を残す、の 3 通りがそれぞれ落ちる |
| T-27 | `test/test_textinput_v3` | **text-input-v3 の受信側の状態**（#49。`TPMLTextInputV3State`）。done までの保留と、done で届かなかった値を初期値に戻すこと、周辺削除 → 確定 → 変換中テキストの順、cursor_begin / cursor_end からの注目範囲と線のカーソル、周辺テキストの 4000 バイトの切り詰め（文字境界、カーソル / 選択を中央に）、周辺削除の文字数への換算（送ったテキストの上で）、変更の理由、入力の種類の写し方。**確定の後の周辺テキストを次の Pump で取り直すこと**（D-46。全バックエンド共通の `TPMLTextInputSystem` の振る舞い） | 2026-10-06 | **PASS 50 / 0** | **表示サーバ不要。CI で走る。** D-46 の 4 件は直す前のコードで 2 件落ちることを確かめてから直した。歯の確認（`-B`）: 確定を削除より先に流す、done の後で保留を戻さない、切り詰めの始まりを文字境界へ寄せない、leave で保留を捨てない、削除の始まりを切り下げる、変換中テキストが同じでも通知する、範囲のときも線のカーソルを描く、確定の後の変更理由を立てない、選択を中央に置かない / 常に選択の中央に置く、切り詰めの中央の位置をずらす、の 11 通りがそれぞれ落ちる。最初は切り詰めの検査に同じ字を並べたテキストを使っていて、どこを切り出しても中身が同じなので位置の誤りを見逃していた（全部違う字に直した） |
| T-28 | `test/test_wayland_textinput` | **text-input-v3 の手順を実機のコンポジタで**（#49）。オプションで 'wayland' を選べること、フォーカスが来たら enter を受けること、Start の後に enable / Stop の後に disable を送ること、再開、ウィンドウを消すと leave | 2026-10-06 | **PASS 12 / 0** | 実機のコンポジタが要るので**手元専用**（labwc 0.9.3、fcitx5 5.1.19 が動いている状態）。キーを打たないので変換そのものは見ない（それは T-07 のデモを `PAPIMELA_IME=wayland` で動かして見る） |
| T-29 | `test/test_ime_keys` | **IME の返信を待つキーの並び**（§7.5、#48 の土台）。返信の順番が入れ替わっても届いた順に出す、すぐ結果の出たキーも待っているキーを追い越さない、返信が来なければ 2 秒で打ち切る、フォーカスを失ったとき・セッションを止めたときは文字を出さずに流す、KeyUp は KeyDown を出したキーにだけ（D-47）、後から来た返信を捨てる | 2026-10-06 | **PASS 22 / 0** | **表示サーバ不要。CI で走る。** 返信を後で返す偽の IME を登録して動かす。歯の確認（`-B`）: 未解決の先頭を出す、すぐ結果の出たキーが追い越す、D-47 の規則を外す、離すほうが消費されたら KeyUp を出さない、流すときに文字も出す、打ち切った後に出さない、フォーカスを失っても流さない、一斉解放で KeyDown を出していないキーも離す、Stop で流さない、全部のキーに同じ番号を振る、の 10 通りがそれぞれ落ちる |
| T-30 | `test/test_ibus_model` | **IBus のバックエンドの、接続の要らない部分**（#48）。IBusText の書き込みと読み取りの往復と型名の検査、文節の規則（ibus-mozc の実測値 4 場面 + 実測していない並び 8 場面: Anthy 型の背景、属性なし、隙間、範囲外、ERROR、重なり、前景色）、アドレスファイルの候補の順と中身、fcitx5 が IBus を装ったアドレスの見分け（手元の実物の値）、文字単位の周辺削除の換算（D-48） | 2026-10-06 | **PASS 42 / 0** | **表示サーバ不要。CI で走る**（libdbus はメッセージの組み立てと読み取りにだけ使う）。歯の確認（`-B`）: 注目文節が無くても SINGLE を変換済みにする、背景を注目にしない、型名を見ない、前景色で分ける、ERROR を注目にする、範囲外を切り詰めない、DOUBLE を弱くする、Wayland の名前を最後にする、画面番号を残す、カーソルに接していない削除を消す（D-48）、の 10 通りがそれぞれ落ちる。型名の検査は最初、型名以外も壊れた例を使っていて型名を見なくても通った。型名だけ違う例と、同じ組み立てで型名を正しくすれば読めることの 2 件に直した |
| T-31 | `test/test_ibus_textinput` | **IBus のバックエンドを本物の ibus-mozc で通しで**（#48）。ローマ字を返信を待たずに続けて流す、変換・文節の移動・確定・破棄、消費されたキーが KeyDown / KeyUp にならない、消費されないキー、再変換（周辺テキスト → 周辺削除 → 変換中テキスト）、ibus-daemon を立て直しての再接続 | 2026-10-06 | **PASS 27 / 0** | `tools/ibus-sandbox/run.sh` の中（ibus 1.5.29、ibus-mozc 2.28.4715.102）。**CI でもランナーに ibus と ibus-mozc を入れて走る**。 2026-10-06 の CI（Ubuntu 24.04 のランナー）でも 27 件すべて通った。最初の実行で再接続以外は全部通った。再接続の 2 件は検査の側の誤り（待ちが再試行の間隔より短い、立て直したデーモンが親の sh と一緒に終わる）。歯の確認（`-B`）: HidePreeditText で消さない、繋ぎ直さない、返信の handled を捨てる、の 3 通りがそれぞれ落ちる |
| T-32 | `test/test_clipboard` | **クリップボードの公開窓口**（#32 の Clipboard、#38 の約束）。部品の無いビデオ（ダミー）でプロセスの中だけで持つ振る舞い（文字列、任意の MIME タイプ、配っていない MIME タイプでは提供者を呼ばない、置き換え・消去・終了で提供者に 1 回だけ知らせる、引数の検査、プライマリ選択は別）と、偽の部品で約束（部品の TextMimeTypes で配る、他のアプリの選択が見えたら手放して ClipboardUpdate、持ち主でないときは部品から受け取る、配っていないものは受け取りに行かない、フォーカスの無い間は持ち主でなくなっただけ、部品が断ったら EPMLVideoError、プライマリ選択の無い部品は EPMLUnsupported） | 2026-10-06 | **PASS 43 / 0** | **表示サーバ不要。CI で走る。** 歯の確認（`-B`）: 持ち主でも部品から受け取る、提供者に知らせない、他のアプリの選択が見えても手放さない、配っていない MIME タイプも読む（異常終了で落ちる）、プライマリ選択の印を落とす、持ち主でなくなっただけで ClipboardUpdate を積む、文字列の MIME タイプを最後のものにする、部品が断っても持ち主になる、終了で知らせない、プライマリ選択の無い部品で中に持つ、の 10 通りがそれぞれ落ちる。**`fpc -B` の落とし穴（D-34）をまた踏んだ**: 壊した版を戻した直後に `-B` 無しで作った別の検査が、古い .ppu（壊した版）で作られていて、配っていない MIME タイプが読めてしまった。作り直して消えた |
| T-33 | `test/test_protocol_types` | **生成したプロトコルの記述子の構造**（D-49）。コア以外の 20 ユニット・58 インターフェースについて、イベントで new_id を受ける引数の型が nil でないこと | 2026-10-06 | **PASS 1 / 0**（7 個のイベントを見る） | **表示サーバ不要。CI で走る**（libwayland-client を dlopen するだけで、コンポジタには繋がない）。直す前の生成物（HEAD の 20 ユニット）で作ると 7 件落ちることを確かめた。プロトコルを足したら一覧（uses と CheckInterface）を足す |
| T-34 | `test/test_wayland_clipboard` | **クリップボードとプライマリ選択を実機のコンポジタで**（#38）。papimela が置いて wl-paste が読む（文字列、1 MiB、0〜255 のバイトの任意の MIME タイプ）、自分の折り返しを他のアプリと取り違えない、消すと見えなくなる、wl-copy が置いて papimela が読む（文字列、任意の MIME タイプ、1 MiB）、入力の無いまま置き直して断られたら持ち主をやめる、プライマリ選択の行き来 | 2026-10-06 | **PASS 27 / 0** | **手元専用**（labwc 0.9.3、wl-clipboard 2.2.1）。**手元のクリップボードとプライマリ選択を書き換え、終わりに文字列だけ戻す**。実装（Sonnet）より先に書き、実装の無い状態で 18 件落ちることを確かめた。持ち主のふりを続ける誤り（断られても待ち続ける）を見つけて直させた後、断りの検出を外すと 3 件落ちることを確かめた（最初に試した外し方は弱く、別の経路で持ち主をやめて通ってしまった）。D-50（検査が止まってクリップボードを消した）を参照。2026-10-09 に D&D の受信（受け取りの関数を共通にした）の後で流し直して通った（クリップボードの文字列は前後で同じ）。Sonnet が同じ日に流した 3 回のうち 1 回は 6 件落ちた（256 バイトと 1 MiB の受け取り、断られた置き直し、プライマリ選択の読み取り）が、原因は特定できていない（変更は関数の切り出しだけ。デスクトップの他のクリップボードの監視との競合を疑っている） |
| T-35 | `test/test_threading` | **スレッドと同期の部品**（#8）と **RunOnMainThread**（#2）。再帰ミューテックス（他のスレッドから TryLock して確かめる、4 スレッド × 5 万回の取り合いで数が合う）、読み書きロックの共有と排他、セマフォと条件変数の起こし方と時間切れ（時計で測る）、Broadcast、ロックガード（スコープ・例外・コピー・Release で釣り合う）、スレッドの名前（15 バイトで切る）・戻り値・シグナルのマスク、優先度（Low = nice 19、High は RealtimeKit で -10）、RunOnMainThread（その場で動く・次の Pump で動く・待つ・待たない・例外のときに後ろを捨てない・Context が先に壊れたら False）、他のスレッドが積んだイベント | 2026-10-06 | **PASS 49 / 0** | **表示サーバ不要。CI で走る**（CI には RealtimeKit が無いので `PAPIMELA_RTKIT_OPTIONAL=1` で優先度を上げる 1 件だけ飛ばす）。手元では RLIMIT_NICE が 0 なので、High は RealtimeKit を通った。歯の確認（`-B`）: 再帰しない、条件変数・セマフォを CLOCK_REALTIME で待つ、ガードのコピーで取り直さない、ガードの Finalize で外さない、名前を切らない、シグナルを止めない、RealtimeKit に頼まない、戻り値を渡さない、時間切れを見ない、例外で後ろの呼び出しを捨てる、Context を壊すときに待つ側を起こさない、Pump で動かさない、メインスレッドでも積んで待つ、例外でも動いたことにする、の 15 通りがそれぞれ落ちる（止まる 5 通りは、検査の中の見張り（60 秒）が失敗として終わらせる。見張りは初め無く、外からの timeout で止めていた） |
| T-36 | `test/test_timer` | **タイマー**（#9。`Ctx.Timer.AddTimer` / `AddTimerNS` / `RemoveTimer`）。最初の Add までスレッドを立てない（/proc/self/task で数える）、50 ms × 530 ms の回数、最初の呼び出しの時刻、呼ばれるスレッド、番号と間隔を受け取る、0 を返せば止まる、戻り値で間隔を変える、ナノ秒の指定、番号が重ならない、期限の順、コールバックの中からの Remove / Add、例外を出したタイマーだけが止まる、破棄が走っているコールバックを待ち、破棄が始まってからは同じ周回で期限の来ていたものも呼ばない | 2026-10-06 | **PASS 29 / 0**（5 回続けて通る） | **表示サーバ不要。CI で走る。** 実装（Sonnet）より先に書き、空の実装で 19 件落ちることを確かめた。見張り（60 秒）入り。歯の確認（`-B`）: 並べない、Remove の印を見ない、破棄の印を見ない、例外でスレッドごと止まる、予定を前の予定から数える、スレッドを最初から立てる、止まったタイマーを一覧から外さない（解放済みを触って異常終了）、の 7 通りがそれぞれ落ちる。最初の版は「破棄の印を見ない」を見逃した（破棄が終わった後しか見ていなかった。しかも周回の始めの時刻のせいで、他のタイマーが期限前に見えて呼ばれなかった）。門のタイマーでスレッドを止めて、同じ周回に期限の来たタイマーを 2 つ並べる場面に直した |
| T-37 | `test/test_atomic` | **不可分操作・スピンロック・一度だけの初期化**（#7）。1 スレッドでの戻り値（Exchange / Add は前の値、CompareAndSwap、IncRef / DecRef、U32 が回る、ポインタ）、4 スレッド × 10 万回の取り合い（Add、CompareAndSwap の繰り返し、スピンロックが守る普通の変数、ポインタの CompareAndSwap で積んだ 4 万個が失われない、DecRef の True がちょうど 1 回）、スピンロックの待ち（他のスレッドが 100 ms 持つ）、TPMLInitState（4 スレッドが同時に呼んでも初期化・後始末は 1 スレッドだけ、他は済むまで待って結果が見える、失敗すればやり直す） | 2026-10-09 | **PASS 44 / 0**（5 回続けて通る） | **表示サーバ不要。CI で走る。** 実装（Sonnet）より先に書き、空の実装で 16 件落ちて取り合いで止まる（見張りが終わらせる）ことを確かめた。歯の確認（`-B`）: Add を不可分でなくする、Add が後の値を返す、DecRef の判定をずらす、U32 の CompareAndSwap がいつも置き換える、TryLock を不可分でなくする、Lock が待たない、ShouldInit が CompareAndSwap を使わない、ShouldInit が待たない、の 8 通りがそれぞれ落ちる。**見られないもの**: Load を普通の読み取りにする誤り、メモリバリアの抜け（x86_64 は CPU が順序を保つので、この検査では出ない。aarch64 の実機は手元に無い） |
| T-38 | `test/test_drop` | **ドラッグ＆ドロップの公開側**（#38。`Ctx.Events.Drop` と `PMLURIToLocalPath` / `PMLURIListToLocalPaths`）。イベントの順序（最初の 1 回だけ DropBegin、ファイル・テキストに最後の位置が載る、DropComplete で戻る、次の落としでまた DropBegin、ウィンドウごとに独立、無効にした種類は DropBegin も積まない）と、URI の変換表 17 通り（file:/// と file:/、localhost とこのマシンのホスト名を大文字小文字によらず受ける、他のホスト・他のスキームは捨てる、%20・%E3%81%82・%25、16 進でない escape と末尾の不完全な escape は残す、スキームの無い相対・絶対は捨てる）と text/uri-list（CRLF、注釈、空の行） | 2026-10-09 | **PASS 29 / 0**（3 回続けて通る） | **表示サーバ不要。CI で走る。** 実装（Sonnet）より先に書き、空の実装で 20 件落ちることを確かめた。歯の確認（`-B`）: DropBegin を積まない、位置を片方しか覚えない、DropComplete で戻さない、無効の確認を後にする、16 進の桁の重みを逆にする、ホスト名を大文字小文字で区別する、localhost を受けない、末尾の escape を捨てる、16 進でない escape の '%' を捨てる、スキームの無い文字列を受ける、の 10 通りがそれぞれ落ちる。「注釈の行を飛ばす」を外しても落ちないが、'#' で始まる行は `file:/` で始まらないので変換がどのみち捨てる（外から違いが見えない） |
| T-39 | `test/test_render_transform` | **回す・写す・敷き詰める・9 つに分ける**（#41。RenderTextureRotated / Affine / Tiled / 9Grid / 9GridTiled）。ソフトウェアのドライバの画素で: 反転（左右・上下・両方）、90 / 180 / 270 / -90 度、回転の中心、30 度と -45 度＋反転（SDL の頂点の式）、360 度は回さない経路、色とアルファの変調が頂点の色になる、拡大率 2、平行四辺形の 3 点、敷き詰めの端数（ちょうど表せる余り）・元の一部・倍率 0 は EPMLArgument、9 つ分けの縁 2・倍率 2 での小数の縁（切り上げ）・縁 0、9GridTiled と倍率 0 | 2026-10-09 | **PASS 26 / 0** | **表示サーバ不要。CI で走る。** 歯の確認（`-B`）: sin の符号、左右の反転、中心、変調、平行四辺形の角、空の矩形を全体と取り違える（CopyExact を外す）、縁の切り上げ（2 つの枝）、敷き詰めの端数の元、敷き詰めを引き伸ばしにする、の 9 通りがそれぞれ落ちる |
| T-40 | `test/test_render_target` | **描画先のテクスチャ**（#41。`RenderTarget`）。描画先へ描いてから写す、引数の検査（Target でないテクスチャ・他のレンダラのテクスチャは EPMLArgument、描画先の間の Present は EPMLArgument）、見え方（ビューポート・クリップ・拡大率・論理解像度）は描画先ごと、切り替えで積んだ命令を描き切る、描画先のテクスチャを消すと戻る、ウィンドウのレンダラでウィンドウ座標との変換は常にウィンドウの見え方、ウィンドウのフレームバッファへの転送 | 2026-10-09 | **PASS 21 / 0** | **表示サーバ不要（ダミーのビデオ）。CI で走る。** 歯の確認（`-B`）: 切り替えで描き切らない、見え方を入れ替えない、ソフトウェアのドライバが描画先を変えない、出力の大きさがウィンドウのまま、消しても描画先のまま（異常終了）、座標の変換が描画先の見え方を使う、ドライバの出力の大きさが描画先の大きさ、Access を確かめない、Present を許す、の 9 通りがそれぞれ落ちる |
| T-41 | `test/demo_drop`（**対話・人の操作**） | **ドラッグ＆ドロップの受信を実機で**（#38）。ファイルマネージャからのファイル、ターミナルやブラウザで選んだ文字列が、DropBegin → DropPosition → DropFile / DropText → DropComplete の順で届くか。プロトコル違反が無いか | 2026-10-09 | **PASS 観測項目 6 / 6** | 持ち主が labwc で 2 回に分けて確認（1 回目: 落とし 6 回、ファイル 3 回と文字列 3 回。2 回目: 3 回）。観測: (1) パスが元の名前のまま（`100%.txt`、`hello world.txt`、`日本語 ファイル.txt`）、(2) DropText に選んだ文字列、(3) DropBegin 6 / DropComplete 6 で対になり、落とし中のまま残らない、DropComplete の座標は最後の DropPosition と同じ、(4) `wl_display_get_error` 0。入ってきた位置の x が 639（640 幅のウィンドウの右端）で、座標はサーフェスの座標のまま。(5) 3 つのファイルを 1 回で落とすと、DropBegin 1 回、DropFile 3 件、DropComplete 1 回、(6) 落とさずにウィンドウの下の縁（y が 397〜399）から出ていくと、DropFile も DropText も無く DropComplete だけ（leave の経路。2 回）。2 回目も Begin 3 / Complete 3、`wl_display_get_error` 0 |

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

2026-10-05〜06 の再確認（#45 と F-7 の後。持ち主が操作し、出力はこちらで読んだ）:

| 観測項目 | 観測した内容 |
|---|---|
| 閉じ込め（G） | `閉じ込め（コンポジタが有効化）`。絶対座標が 0〜639 × 0〜399（ウィンドウの大きさ）で止まる |
| ロック（R） | 絶対座標が (519, 220) のまま相対移動だけが届く。R で戻すと、G が入っていれば閉じ込めへ戻る |
| 閉じ込め矩形（C） | 押すたびに 中央 160x120 → 1x1（ロックで代用。ポインタが止まる）→ 無し。グラブ無しでも効く（SDL の SDL_SetWindowMouseRect と同じ） |
| カーソル（H、S） | H は表示だけを切り替え、拘束の状態は変わらない。S でカーソルの形が 6〜7 回切り替わった |
| プロトコル違反 | `wl_display_get_error` は 0 |

最初の回に「H で小さな正方形に閉じ込められた」という報告があったが、H だけを押す再現では起きず、
出力でも H は表示の切り替えしかしていなかった。小さな正方形は C の 1 回目の動きなので、C が押されていたと考えている（断定はしていない）。

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
| C-10 | **アンブレラの生成**（`tools/genumbrella.bb`） — 公開層 16 ユニットの interface 部から `src/generated/umbrella_interface.inc` と `umbrella_implementation.inc` を作る | 2026-10-02 | **PASS** | 型 121（うち type helper 3 は派生で置く）、定数 339、関数 64。`--check` は CI で走り、古ければ落ちる（ファイルを 1 文字変えて落ちることを確かめた）。生成器を書いた Sonnet が型付き定数を足して止まることを確かめた。今の公開層に無いオーバーロードの枝は、こちらで Time に一時的に 2 つ足して生成し、`uses PaPiMeLa` から両方を呼べることを確かめた |
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
# アンブレラを作り直す（公開層の interface 部を変えたら）。
./tools/genumbrella.bb
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
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_time                 test/test_time.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_backends             test/test_backends.pas
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -otest/test_umbrella             test/test_umbrella.pas
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
env -u WAYLAND_DISPLAY -u DISPLAY ./test/test_time
env -u WAYLAND_DISPLAY -u DISPLAY ./test/test_backends
env -u WAYLAND_DISPLAY -u DISPLAY ./test/test_umbrella
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
