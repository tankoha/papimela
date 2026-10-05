# IBus の隔離環境

IBus のバックエンド（#48）とスパイク 3 を、デスクトップの IME（手元では fcitx5）と混ぜずに動かすための環境。
Ubuntu 24.04 の最小 rootfs に ibus と ibus-mozc と fpc を入れ、bwrap で隔離する。root も sudo も要らない。

```bash
tools/ibus-sandbox/setup.sh                 # 一度だけ。~/.cache/papimela/ibus-sandbox に作る
tools/ibus-sandbox/run.sh ibus engine       # → mozc-jp
tools/ibus-sandbox/run.sh sh -c 'mkdir -p /tmp/lib && fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FU/tmp/lib -o/tmp/spike3_ibus spikes/spike3_ibus.pas && /tmp/spike3_ibus'
```

`run.sh` はリポジトリを `/work` に見せ、そこで `ibus-session` 経由でコマンドを動かす。`ibus-session` は
セッションバスと ibus-daemon を立て、エンジンを mozc-jp にしてから引数のコマンドを動かす。
中の `/tmp` は毎回空なので、コンパイルの中間ファイルは `/tmp/lib` に置く（手元の `lib/` と混ぜない）。

## 実測で分かった、この形にしている理由

| 事柄 | 対処 |
|---|---|
| `mozc_server` は root では起動しない（何も出さずに終了コード 255） | uid 1000 で動かす。dbus-daemon が名前を引くので rootfs の `/etc/passwd` に `ime` を足す |
| ibus-mozc は既定で直接入力から始まる（`active_on_launch: False`） | `ibus-session` が設定ファイルを置いて `True` にする |
| `ibus engine mozc-jp` は成功しても終了コード 1（setxkbmap が無い） | 読み返して確かめる |
| IBus のアドレスファイルの名前は `/var/lib/dbus/machine-id` を先に使う（`/etc/machine-id` と違う値のとき） | setup.sh が前者を作る。バックエンドも同じ順で探す |
| ユーザー名前空間では uid 0 しか写らず、dbus と man-db の postinst が所有者の変更で失敗する | dbus は先に `dpkg-statoverride` を置く。man-db は外す |
| PID の名前空間を分けないと、中で立てた ibus-daemon や mozc_server が bwrap の終了後もホストに残る | `--unshare-pid --die-with-parent` |

ネットワークの名前空間は共有している（setup の apt に要る。run では要らないが、分けると
抽象ソケットの扱いが変わるので確かめてから分ける）。
