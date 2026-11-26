#!/usr/bin/env bash
# Cuts Noto Sans KR down to what Korean and English posts use: Latin,
# punctuation, jamo and the 2,350 Hangul syllables of KS X 1001 (from about
# 2.8 MB to about 0.5 MB per weight). Rarer syllables fall back to the
# system's Korean font, or on the web to Noto Sans KR loaded on demand.
#
# Needs fonttools (pip install fonttools). Run from the repository root with
# the full fonts from https://fonts.google.com/noto/specimen/Noto+Sans+KR in
# a folder given as the first argument.
set -euo pipefail
src="${1:?folder with the full NotoSansKR-*.ttf}"
out=app/assets/fonts
text=$(mktemp)
python3 -c "
import sys
sys.stdout.write(''.join(chr(c) for c in range(0xAC00, 0xD7A4) if len(chr(c).encode('euc-kr', 'ignore')) == 2))
" > "$text"
common='U+0020-007E,U+00A0-00FF,U+2000-206F,U+20A9,U+2190-2193,U+2460-24FF,U+3000-303F,U+3131-318E,U+FF01-FF5E'
for w in Regular Medium Bold; do
  pyftsubset "$src/NotoSansKR-$w.ttf" --unicodes="$common" --text-file="$text" \
    --no-hinting --layout-features='*' --output-file="$out/NotoSansKR-$w.ttf"
done
rm "$text"
ls -l "$out"/NotoSansKR-*.ttf
