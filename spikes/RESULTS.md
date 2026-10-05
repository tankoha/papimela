# スパイク検証結果

実装前に潰すべきブロッカー 2 件の検証結果。`docs/DESIGN.md` 10 章の項目 2 と 5 はこれで解決した。

## 検証環境

| 項目 | 値 |
|---|---|
| FPC | 3.2.2 (x86_64-linux) |
| セッション | Wayland (`XDG_SESSION_TYPE=wayland`) |
| コンポジタ | labwc (wlroots ベース) |
| libwayland-client | 1.24.0 |
| IME | fcitx5（**IBus ではない**）。`GTK_IM_MODULE=fcitx`、mozc が `DefaultIM` |

---

## スパイク 1: `wl_proxy_marshal_flags` の varargs 呼び出し

`spikes/spike1_wayland.pas` — **全項目 PASS**

libwayland-client の生成スタブは可変長引数関数 `wl_proxy_marshal_flags` を呼ぶ。これを FPC から呼べなければ、Wayland プロトコルバインディングの生成方式を根本から変える必要があった。

### 結果

| 検証項目 | 結果 |
|---|---|
| `cdecl; varargs` で `marshal_flags` を呼ぶ（可変長引数が NULL 1 個） | PASS — `wl_display_get_registry` 相当が成功 |
| 同（uint32 + 文字列 + uint32 + NULL の混在） | PASS — `wl_registry_bind` 相当が成功、bind した proxy の version も期待値 |
| C から Pascal の `cdecl` コールバックが呼ばれる | PASS — registry の `global` イベントを 56 件受信 |
| libwayland の `wl_interface` データシンボル取り込み | PASS |
| `marshal_flags` が返した proxy からの二段目の marshal | PASS — `wl_compositor_create_surface` 相当が成功、roundtrip でプロトコルエラーなし |
| 解放（`wl_proxy_destroy` / `wl_display_disconnect`） | PASS — クラッシュなし |

### 設計への反映

- **`wl_proxy_marshal_array_flags` による回避は不要**。生成器は C の生成コードと同じ形（`marshal_flags` 直接呼び出し）を出力してよい。
- FPC の構文的な注意点: 外部データシンボルの宣言に `cdecl` を付けると構文エラーになる。`var X: T; external LIB name 'X';` と書く（`cdecl` なし）。

### 付随して分かったこと

- labwc は `zwp_text_input_manager_v3` v1 を広告している。
- `xdg_wm_base` があるのでウィンドウ作成は可能。

---

## スパイク 2: fcitx5 D-Bus 経路で 3 要件を検証

`spikes/spike2_fcitx.pas` — **主要項目 PASS**

fcitx5 の入力コンテキストは D-Bus 接続に紐づいて破棄されるため、`gdbus` のような一発起動のツールでは検証できない。接続を保持する単一プロセスが必要で、FPC + libdbus-1 で書いた（`PaPiMeLa.Platform.DBus` の先行実装にもなる）。

### 結果

| 要件 | 結果 |
|---|---|
| **全文節の区切り** | **PASS**。`UpdateFormattedPreedit(a(si), i)` の配列要素が文節に 1 対 1 で対応する |
| **注目文節の判別** | **PASS**。注目文節は `HighLight (16)`、非注目文節は `Underline (8)` |
| **周辺テキスト** | **PASS**。`SetSurroundingText(s, u, u)` が受理された |
| **周辺削除** | 未観測。`DeleteSurroundingText(i, u)` はインターフェースに存在するが、mozc が発火させる条件（再変換など）を満たしていない。機構の欠如ではない |

「わたしのなまえ」をローマ字入力してスペースで変換した実際の受信内容:

```
文節[0] "私の"  flags=16 (HighLight)   ← 注目文節
文節[1] "名前"  flags=8  (Underline)   ← 非注目文節
全体="私の名前" 文節数=2 cursor=0
```

もう一度スペースを押すと第 1 文節の候補が変わり、`HighLight` の位置は保たれた。

```
文節[0] "わたしの"  flags=16 (HighLight)
文節[1] "名前"      flags=8  (Underline)
```

### 設計に反映すべき実測値

1. **`UpdateFormattedPreedit` の cursor は UTF-8 バイトオフセット**（文字単位ではない）。「わたしのなまえ」= 7 文字 = 21 バイトで `cursor=21`、「わたし」で `cursor=9`。7.2 の表で Fcitx5 を「文字単位」としていたのは preedit については誤り。バイト・文字の二重表現（7.3）はこの変換のために必要。
2. **`FormattedPreedit (16)` の宣言が必須**。これが無いと文節に分かれた形では届かない。papimela は `Preedit (2) | FormattedPreedit (16) | SurroundingText (64) = 82` を常に宣言する。
3. **手順の順序が重要**。`SetCurrentIM` はフォーカス中のコンテキストに作用するので `FocusIn` を先に行う。さらに **fcitx5 は既定で「非アクティブ」状態**（`keyboard-us` が担当）で始まるため `Controller1.Activate()` が必要。これを忘れると `ProcessKeyEvent` が常に `false` を返し、IME が動いていないように見える。
4. `Controller1.State()` が `0`（非アクティブ）/ `2`（アクティブ）を返すので、アクティベート状態の確認に使える。
5. **`SetCursorRectV2(i,i,i,i,d)`** の第 5 引数がスケール値。Wayland のグローバル座標が取れない問題を回避できる（10 章項目 4）。
6. キー 1 個につき `UpdateFormattedPreedit` は 1 回だけ。冗長な通信はない。
7. ローマ字の未確定部分は全角英字で表示される（"わｔ" など）。アプリ側で特別な処理は不要。

### ブロッカー「IBus 直結と text-input-v3 の競合」について

**競合は起きなかった。** `zwp_text_input_manager_v3` を bind せずに D-Bus 直結する構成で、キーは `wl_keyboard` から通常どおり届き、IME とのやりとりは D-Bus で完結する。text-input-v3 は加算的な機能で、`text_input` オブジェクトを作らなければコンポジタは通常のクライアントとして扱う。

ただし検証したのは **labwc (wlroots) のみ**。GNOME (mutter) と KDE (kwin) は mutter/kwin が IME クライアントを一元管理する設計なので、別途確認が必要（10 章項目 2）。

---

## スパイク 3: IBus（ibus-mozc）の属性と通知の並び（2026-10-06）

`spikes/spike3_ibus.pas`。papimela の `PaPiMeLa.Platform.DBus` で IBus の私設バスに繋ぎ、キーを返信を待たずに送って、
返信と通知の並びと `IBusText` の属性を記録した。デスクトップの fcitx5 と混ざらないよう、Ubuntu 24.04 の最小 rootfs に
ibus 1.5.29 と ibus-mozc 2.28.4715.102 を入れ、bwrap で隔離して動かした（`tools/ibus-sandbox/`）。

### 結果

| 項目 | 結果 |
|---|---|
| (a) 接続 | アドレスファイル `$XDG_CONFIG_HOME/ibus/bus/<machine-id>-<host>-<display>` から `IBUS_ADDRESS` を読み、`dbus_connection_open_private` + `dbus_bus_register` で繋がる。**machine-id は `/var/lib/dbus/machine-id` が先**（`/etc/machine-id` と値が違う環境で、ファイル名は前者だった）。`DISPLAY=:0` なら `unix-0` |
| (b) 非同期 | `dbus_connection_send` の通し番号と、返信の `reply_serial` で突き合わせられる。返信は送った順に届いた。**同じキーの通知（UpdatePreeditText など）は返信より先に届く** |
| (b) 離す | mozc は**キーを離すイベントを一度も消費しなかった**（押すほうを消費したキーでも `handled=false`） |
| (c) 変換前 | 読み全体に下線 SINGLE（type=1 value=1）だけ。カーソルは末尾（文字数） |
| (c) 変換後 | 注目文節に下線 DOUBLE（value=2）+ 背景（type=3、$D1EAFF）+ 前景（type=2、$000000）。**注目していない変換済みの文節は下線 SINGLE だけ**で、変換前の読みと同じ。カーソルは注目文節の先頭 |
| (c) 文節の移動 | → で注目が移り、DOUBLE と色も移る。範囲は文字（コードポイント）単位 |
| (d) 確定 | `CommitText` の直後に `HidePreeditText`。空の `UpdatePreeditText` は来ない。変換の破棄（Escape 2 回）も `HidePreeditText` だけ |
| (d) 周辺テキスト | `SetSurroundingText(v IBusText, u cursor, u anchor)` は受理された（位置は文字単位）。mozc は**キーごとに** `RequireSurroundingText` を送ってくる |
| (d) 周辺削除 | 「漢字を」の「漢字」を選択（cursor 2、anchor 0）して変換キーで再変換すると、`DeleteSurroundingText(i -2, u 2)`（カーソルからの相対位置と長さ、文字単位）→ 注目文節「漢字」の `UpdatePreeditText` → 返信、の順に届いた。選択が無いと何も起きない |
| ForwardKeyEvent | この手順では一度も来なかった |

### 設計に反映すべき実測値

- **文節の状態の規則を直す**: 下線 SINGLE だけでは「変換済み」と「未変換」を区別できない（mozc はどちらも SINGLE）。
  注目文節（DOUBLE、または SINGLE + 背景）が 1 つでもあれば他の SINGLE は `Converted`、無ければ全部 `Unconverted`
- 変換中テキストの消滅は `HidePreeditText` でも起きる（確定の後、破棄）。これを空の変換中テキストとして扱う
- 離すキーは消費されない前提で、押すほうを消費したキーの KeyUp を流さない仕組みが要る（押されていないキーの KeyUp は
  `TPMLKeyboardState` が捨てるので、押すほうを KeyDown にしなければ足りる。§7.5 で確かめる）
- `RequireSurroundingText` に毎回答えると、同じ周辺テキストを毎キー送ることになる。前に送ったものと同じなら送らない
- mozc は root では動かない（`mozc_server` が何も出さずに終了コード 255）。隔離環境は uid 1000 で動かす

---

## 優先順位への影響

設計書は IBus バックエンドを先に実装する前提だったが、**Fcitx5 バックエンドを先に実装するほうが合理的**。

- 開発機で実際に動いているのは fcitx5 であり、この経路は実測で全要件が通っている
- fcitx5 は `ibusfrontend` アドオンで `/org/freedesktop/IBus` も公開しているため、IBus 経路の実装も後で同じ環境でテストできる
- IBus の属性 → 文節状態のマッピング（10 章項目 1）は未実測のまま残っており、IBus を先にすると未知が 1 つ増える

## 再現方法

```bash
cd spikes && fpc -O1 -gl spike1_wayland.pas && ./spike1_wayland
cd spikes && fpc -O1 -gl spike2_fcitx.pas && ./spike2_fcitx
```

スパイク 2 は Wayland セッションと fcitx5 + 日本語エンジン（mozc）の稼働が前提。

スパイク 3 は隔離環境の中で動かす（`tools/ibus-sandbox/README.md`）:

```bash
tools/ibus-sandbox/run.sh sh -c 'fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FU/tmp/lib -o/tmp/spike3_ibus spikes/spike3_ibus.pas && /tmp/spike3_ibus'
```
