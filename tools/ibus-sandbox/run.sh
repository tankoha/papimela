#!/bin/sh
# run.sh — IBus の隔離環境（setup.sh で作ったもの）で、リポジトリを /work に見せてコマンドを動かす
#
#   tools/ibus-sandbox/run.sh <コマンド...>
#
# uid 1000 で動かす（mozc_server は root では起動しない。実測）。PID の名前空間を分けるので、
# 終わると中で立てた ibus-daemon / mozc_server も消える。ネットワークの名前空間は共有する。
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
ROOT=${PAPIMELA_IBUS_SANDBOX:-${XDG_CACHE_HOME:-$HOME/.cache}/papimela/ibus-sandbox}/root
if [ ! -x "$ROOT/usr/bin/ibus-daemon" ]; then
  echo "run.sh: $ROOT が無い。先に tools/ibus-sandbox/setup.sh を実行する" >&2
  exit 2
fi
exec bwrap --bind "$ROOT" / --dev /dev --proc /proc --tmpfs /tmp \
  --ro-bind /etc/resolv.conf /etc/resolv.conf \
  --bind "$REPO" /work --chdir /work \
  --unshare-user --unshare-pid --die-with-parent --uid 1000 --gid 1000 --share-net \
  --setenv HOME /tmp/home --setenv PATH /usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  --unsetenv WAYLAND_DISPLAY --unsetenv DISPLAY --unsetenv DBUS_SESSION_BUS_ADDRESS \
  --unsetenv XDG_RUNTIME_DIR --unsetenv XDG_CONFIG_HOME --unsetenv XDG_CACHE_HOME \
  --unsetenv GTK_IM_MODULE --unsetenv QT_IM_MODULE --unsetenv XMODIFIERS \
  /usr/local/bin/ibus-session "$@"
