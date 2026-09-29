#!/usr/bin/env bash
# check-diagrams.sh — 図と実装の乖離を検出する
#
# Origin : original work (clean-room design; not derived from SDL sources)
# Design : docs/diagrams/ の方針「実装済みのものだけを描く」を機械的に担保する
#
# 検査は 2 つ:
#   1. 英語版（正）と日本語版の Mermaid ブロックがバイト単位で同一であること
#   2. 図に出てくる型がすべて src/ に実在すること
#
# 2 は「図が古くなった」ことしか検出できない（実装にあって図に無いものは検出しない）。
# 図は実装の部分集合でよいという方針なので、これで足りる。

set -euo pipefail

cd "$(dirname "$0")/.."

DIAG=docs/diagrams
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0

extract_mermaid() {
  LC_ALL=C awk '/^```mermaid$/{f=1} f{print} /^```$/{if(f&&!/mermaid/)f=0}' "$1"
}

echo "1. 英語版と日本語版の Mermaid ブロックの同一性"
for en in "$DIAG"/*.md; do
  case "$en" in
    *_jp.md) continue ;;
  esac
  base=$(basename "$en" .md)
  jp="$DIAG/${base}_jp.md"
  if [ ! -f "$jp" ]; then
    printf '  NG   %s に対応する日本語版がない\n' "$base"
    fail=$((fail + 1))
    continue
  fi
  extract_mermaid "$en" > "$TMP/en.txt"
  extract_mermaid "$jp" > "$TMP/jp.txt"
  if cmp -s "$TMP/en.txt" "$TMP/jp.txt"; then
    printf '  OK   %s\n' "$base"
  else
    printf '  NG   %s の図が英日で一致しない\n' "$base"
    diff "$TMP/en.txt" "$TMP/jp.txt" | head -20 || true
    fail=$((fail + 1))
  fi
done

echo
echo "2. 図に出てくる型が実装に存在するか"
LC_ALL=C grep -ahoE '^    class [A-Za-z0-9_]+' "$DIAG"/*.md \
  | LC_ALL=C sed 's/    class //' | sort -u > "$TMP/names.txt"

missing=0
total=0
while read -r name; do
  [ -z "$name" ] && continue
  # TObject は RTL の型なので対象外
  [ "$name" = "TObject" ] && continue
  total=$((total + 1))
  if ! LC_ALL=C grep -qahE "^  $name *= *(class|interface|record|\()" \
       src/*.pas src/generated/*.pas; then
    printf '  NG   %s が実装に無い\n' "$name"
    missing=$((missing + 1))
  fi
done < "$TMP/names.txt"

printf '  検査 %s 型 / 実装に無いもの %s 件\n' "$total" "$missing"
fail=$((fail + missing))

echo
if [ "$fail" -eq 0 ]; then
  echo "=== 図と実装は整合している ==="
  exit 0
fi
printf '=== 不整合 %s 件 ===\n' "$fail"
exit 1
