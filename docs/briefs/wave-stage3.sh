#!/bin/sh
# WAV の 3 段目の依頼文を組み立てて標準出力へ出す（docs/briefs/wave-stage3.md の説明を参照）。
# リポジトリの根から実行する。reference/SDL が要る（docs/ORIGIN.md）。
set -eu
C=reference/SDL/src/audio/SDL_wave.c
[ -f "$C" ] || { echo "wave-stage3.sh: $C が無い。docs/ORIGIN.md の手順で reference/SDL を用意すること" >&2; exit 1; }
# 指示と仕様（先頭の HTML のコメントは除く）
sed '1,/^-->$/d' docs/briefs/wave-stage3.md
echo
echo '# CODING STYLE'
echo
cat docs/CODING-STYLE.md
echo
echo '# STARTING UNIT (src/PaPiMeLa.Audio.Wave.pas at commit 0a1515f; stage 3 is the empty functions)'
echo
git show 0a1515f:src/PaPiMeLa.Audio.Wave.pas
echo
echo '# SDL SOURCE (src/audio/SDL_wave.c, the parts that stage 3 ports)'
echo
# ADPCM_DecoderState と MS の型、WaveAdjustToFactValue、MS / IMA の 12 関数。
# 行番号ではなく関数名で切る（参照版を上げても動くように）。
awk '
  /^typedef struct ADPCM_DecoderState/ { p = 1 }
  /^#ifdef SDL_WAVE_DEBUG_LOG_FORMAT/  { p = 0 }
  /^static Sint64 WaveAdjustToFactValue/ { p = 1 }
  /^static bool MS_ADPCM_CalculateSampleFrames/ { p = 1 }
  p { print }
  /^static bool IMA_ADPCM_Decode\(/ { q = 1 }
  q && /^}/ { exit }
' "$C"
