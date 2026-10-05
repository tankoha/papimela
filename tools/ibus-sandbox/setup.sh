#!/bin/sh
# setup.sh — IBus の検査に使う隔離環境（Ubuntu 24.04 の最小 rootfs + ibus + ibus-mozc + fpc）を作る
#
#   tools/ibus-sandbox/setup.sh
#
# 置き場所は $PAPIMELA_IBUS_SANDBOX（既定 ~/.cache/papimela/ibus-sandbox）。root も sudo も要らない
# （bwrap のユーザー名前空間で uid 0 に見せて apt を動かす）。ネットワークから ubuntu-base（約 30 MB）と
# パッケージを取ってくる。作り直すときは置き場所を消してから実行する。
set -eu
BASE=${PAPIMELA_IBUS_SANDBOX:-${XDG_CACHE_HOME:-$HOME/.cache}/papimela/ibus-sandbox}
TARBALL=ubuntu-base-24.04.5-base-amd64.tar.gz
URL=https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release
HERE=$(cd "$(dirname "$0")" && pwd)

mkdir -p "$BASE"
cd "$BASE"
if [ ! -f "$TARBALL" ]; then
  curl -sSfO "$URL/$TARBALL"
fi
curl -sSf -o SHA256SUMS "$URL/SHA256SUMS"
grep " \*$TARBALL\$" SHA256SUMS | sha256sum -c -

if [ ! -d root/usr ]; then
  mkdir -p root
  tar -xzf "$TARBALL" -C root --no-same-owner --exclude='./dev/*'
fi

asroot() {
  bwrap --bind "$BASE/root" / --dev /dev --proc /proc --tmpfs /tmp \
    --ro-bind /etc/resolv.conf /etc/resolv.conf \
    --unshare-user --unshare-pid --die-with-parent --uid 0 --gid 0 --share-net \
    --setenv HOME /root --setenv PATH /usr/sbin:/usr/bin:/sbin:/bin \
    --setenv DEBIAN_FRONTEND noninteractive \
    "$@"
}

# ユーザー名前空間では uid 0 しか写っていないので、dbus の postinst が launch-helper の
# 所有者を messagebus へ変えようとして失敗する（実測）。先に上書きの記録を置いて避ける。
mkdir -p root/usr/lib/dbus-1.0
asroot sh -c '
  dpkg-statoverride --list /usr/lib/dbus-1.0/dbus-daemon-launch-helper >/dev/null 2>&1 ||
    dpkg-statoverride --add root root 0755 /usr/lib/dbus-1.0/dbus-daemon-launch-helper
  apt-get -o APT::Sandbox::User=root update -qq
  apt-get -o APT::Sandbox::User=root install -y -qq --no-install-recommends \
    fpc ibus ibus-mozc dbus dbus-x11 >/tmp/apt.log 2>&1 || { tail -30 /tmp/apt.log; }
  # man-db の postinst も所有者の変更で失敗する。要らないので外す。
  dpkg -r --force-depends man-db >/dev/null 2>&1 || true
  dpkg --configure -a
  bad=$(dpkg -l | awk "NR > 5 && \$1 != \"ii\" { print \$2 }")
  if [ -n "$bad" ]; then echo "setup.sh: 構成が終わっていないパッケージ: $bad" >&2; exit 1; fi
  # mozc_server は root では動かないので、uid 1000 の利用者を作る（dbus-daemon が名前を引く）
  grep -q "^ime:" /etc/passwd || echo "ime:x:1000:1000:ime test:/tmp/home:/bin/sh" >> /etc/passwd
  grep -q "^ime:" /etc/group || echo "ime:x:1000:" >> /etc/group
  [ -s /var/lib/dbus/machine-id ] || dbus-uuidgen --ensure=/var/lib/dbus/machine-id
  ibus version
'
install -m 755 "$HERE/ibus-session" root/usr/local/bin/ibus-session
echo "setup.sh: できた（$BASE/root）。tools/ibus-sandbox/run.sh で使う"
