#!/bin/bash
# 게임의 .fnt 높이에 맞춰 SVFN 세트를 굽는다.
#
#   bakeset.sh <한글TTF> <라틴TTF> <배율> <출력디렉터리> <높이...>
#
# 예: bakeset.sh NanumJangMiCe.ttf ipag.ttf 3 out 8 9 12
#     -> out/han08.fnt (24px 셀), han09.fnt (27px), han12.fnt (36px)
set -eu

MK="$HOME/src/scummvm-korean-ttf/scripts/mkfont.py"
HAN=$1; LAT=$2; SCALE=$3; OUT=$4; shift 4

mkdir -p "$OUT"

for h in "$@"; do
  cell=$((h * SCALE))
  # 손글씨는 잉크가 명목 크기보다 작다. 4/3 배로 렌더해 셀에 담는다.
  size=$((cell * 4 / 3))
  printf 'height %2d -> cell %2d (render %2d)\n' "$h" "$cell" "$size"
  python3 "$MK" "$HAN" "$OUT/han$(printf '%02d' "$h").fnt" \
      --size "$size" --cell "$cell" --bpp 8 >/dev/null
  python3 "$MK" "$LAT" "$OUT/lat$(printf '%02d' "$h").fnt" \
      --size "$size" --cell "$cell" --bpp 8 --latin --fullwidth >/dev/null
done

echo "구운 파일:"
ls -la "$OUT"/*.fnt | awk '{printf "  %-28s %8.0f KB\n", $9, $5/1024}'
