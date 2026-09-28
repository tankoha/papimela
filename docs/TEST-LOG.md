# テスト実行一覧

papimela で実行したテストの記録。日時は実測値（ファイルの mtime と git のコミット時刻、
および最終一括実行の時刻）に基づく。

最終一括実行: **2026-09-28 22:49**（5 本すべて成功、アサーション 79 件・失敗 0 件）

## 1. 実行可能テスト

| # | テスト | 目的 | 最終実行 | 結果 | 備考 |
|---|---|---|---|---|---|
| T-01 | `spikes/spike1_wayland` | `wl_proxy_marshal_flags` を FPC の `cdecl; varargs` で呼べるか。C → Pascal コールバック、外部データシンボル取り込み | 2026-09-28 22:33 | **PASS 10 / 0** | 初回はコンパイル不可（D-01）。修正後は一度も失敗していない |
| T-02 | `spikes/spike2_fcitx` | fcitx5 の D-Bus で文節区切り・周辺テキスト・周辺削除が取れるか | 2026-09-28 22:33 | **PASS 8 / 0** | 初回実行は 4 項目 FAIL（D-02）。**周辺削除はアサーションを置いていない**（下記 3 を参照） |
| T-03 | `test/test_fcitx_textinput` | papimela の公開 API（`TPMLContext` + イベントキュー）経由で文節情報が失われないか | 2026-09-28 22:33 | **PASS 18 / 0** | 21:44 時点ではメソッドポインタ版で PASS。21:57 にイベントキュー版へ全面改稿し再検証（D-05〜D-08 を経由） |
| T-04 | `test/test_wayland_protocols` | 生成したプロトコルバインディングが実機のコンポジタと通信できるか | 2026-09-28 22:33 | **PASS 24 / 0** | 自前構築した拡張プロトコルの記述子が受理され、`configure` イベントも到達 |
| T-05 | `test/test_wayland_window` | Wayland ビデオバックエンド。ウィンドウ生成、configure → ack_configure、wl_shm への描画、リサイズ通知 | 2026-09-28 22:49 | **PASS 19 / 0** | 実際にウィンドウが約 2 秒表示される。ディスプレイ 2 台を列挙、120 フレーム描画、最大化/復帰の往復も確認 |

### T-04 が決定的である理由

拡張プロトコルの `wl_interface` 記述子（メッセージ表、シグネチャ文字列、`types` 配列プール）は
生成器が自前で組む。1 バイトでも違えばコンポジタはプロトコルエラーを返して接続を切る。
`xdg_surface.configure` と `xdg_toplevel.configure` が届き、`wl_display_get_error` が終始 0 で
あることが、記述子の正しさの証明になっている。

## 2. コンパイル検証

| # | 対象 | 最終実行 | 結果 | 備考 |
|---|---|---|---|---|
| C-01 | `src/` の全ユニット（Types / Errors / Unicode / Core.Base / Core / Events / Platform.DynLib / Platform.DBus / Platform.Wayland.Client / TextInput 系 3 本 / Video 系 5 本） | 2026-09-28 22:49 | **PASS** | 全 19 ユニット。到達過程で D-03〜D-08、D-19 を修正 |
| C-02 | `tools/wlscan-pas` | 2026-09-28 22:24 | **PASS** | — |
| C-03 | 生成プロトコル 21 ユニット（9230 行） | 2026-09-28 22:24 | **PASS 21 / 21** | 初回は 9 / 21 が失敗（D-10〜D-12）。§9.2 が挙げる XML のうち、`reference/SDL/wayland-protocols/` にあるものすべて |
| C-04 | **rawpaco 静的解析（激辛モード `--fail-on=warning`）** — `src` / `src/generated` / `test` / `spikes` / `tools` の全 Pascal ファイル | 2026-09-29 | **PASS 指摘 0 件** | 導入初回は 2 件の指摘（D-20）。修正後は 0 件。`.github/workflows/lint.yml` で push / pull_request ごとに走る |

## 3. アサーションを置いていない項目

意図的に検証していない、または環境の都合で検証できていないもの。**失敗ではなく未検証**として扱う。

| 項目 | 状況 | 理由 |
|---|---|---|
| 周辺削除（`DeleteSurroundingText`）の実受信 | **未観測** | 経路は実装済みで、fcitx5 のインターフェースにシグナルが存在することは introspect で確認済み。ただし mozc が発火させる条件（再変換など）を通常の入力では満たさない。機構の欠如ではない |
| GNOME (mutter) / KDE (kwin) での IME 直結 | **未検証** | 検証環境は labwc (wlroots) のみ。mutter / kwin は IME クライアントを一元管理する設計なので別途確認が必要（設計書 §10 項目 2） |
| fcitx5-anthy / fcitx5-chinese-addons のフラグ対応 | **未検証** | 文節状態のマッピング規則は fcitx5-mozc でのみ実測（設計書 §10 項目 1） |
| IBus 経路 | **未実装** | バックエンド自体が未実装（第 11 章 #48） |
| **キーボード / ポインタ / タッチの入力イベント** | **未実装** | Wayland のシート（`wl_seat` の `wl_keyboard` / `wl_pointer` / `wl_touch`）が未実装（第 11 章 #37）。`wl_seat` は束縛しているが中身が無いため、`KeyDown` / `MouseMotion` 等のイベントは一切発生しない。T-05 がユーザー操作で閉じられないのもこのため（時間で終了する） |
| ウィンドウのフルスクリーン / 不透明度 / グラブ / ヒットテスト | **未実装** | 対応する能力と一緒に追加する |
| GL / Vulkan / レンダラ / クリップボード / カーソル | **未実装** | 第 11 章 #33、#38、#39、#41、#67 |
| `TPMLEvent` の `Finalize` コスト測定 | **未実施** | サイズは実測済み（72 バイト）。ベンチマークは残課題（設計書 §10 項目 9） |
| CI でのヘッドレス実行 | **未整備** | `weston --backend=headless` + fcitx5 を CI で起動する構成は未着手（第 11 章 #70） |

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
fpc -O1 -gl spikes/spike1_wayland.pas && fpc -O1 -gl spikes/spike2_fcitx.pas
./spikes/spike1_wayland && ./spikes/spike2_fcitx
./test/test_fcitx_textinput && ./test/test_wayland_protocols && ./test/test_wayland_window
```

実行前提: Wayland セッション、fcitx5 稼働、日本語エンジン（mozc）が利用可能であること。
T-02 と T-03 は IME の状態を変更する（`Controller1.Activate` を呼ぶ）ため、実行後に
入力メソッドがアクティブになっている場合がある。
