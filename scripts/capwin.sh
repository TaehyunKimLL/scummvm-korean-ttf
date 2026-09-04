#!/bin/bash
# Wine 에서 scummvm.exe 를 띄우고 스크린샷을 찍는다.
#
#   ~/games/capwin.sh <출력접두사> <디스플레이> <배율> <시각...>
# 예:
#   ~/games/capwin.sh /tmp/WIN :320 2 30 42
#
# 리눅스 빌드용 cap11.sh 와 같은 원칙: 창 스케일링을 모두 끄고 Xvfb 를
# 내부 해상도와 똑같이 만들어 1:1 픽셀을 얻는다.

set -u
PREFIX=$1; DISP=$2; SCALE=$3; shift 3
TIMES=("$@")

W=$((320 * SCALE))
H=$((200 * SCALE))
TAG=$(basename "$PREFIX")
PKG="$HOME/games/scummvm-win"

source "$HOME/.local/wine/env.sh" >/dev/null 2>&1

Xvfb "$DISP" -screen 0 "${W}x${H}x24" -nolisten tcp >/dev/null 2>&1 &
XVFB_PID=$!
sleep 2

cd "$PKG"
# Xvfb 에는 GPU 가 없다. OpenGL 백엔드는 DRI3 를 못 찾아 검은 화면이 되므로
# 소프트웨어 렌더링만 하는 surfacesdl 을 쓴다.
DISPLAY=$DISP wine scummvm.exe \
  --gfx-mode=${GFXMODE:-surfacesdl} --no-filtering \
  --no-aspect-ratio --stretch-mode=pixel-perfect --scale-factor=1 \
  --path=mmkor --auto-detect > "/tmp/run_$TAG.log" 2>&1 &
WINE_PID=$!

LAST=0
for t in "${TIMES[@]}"; do
  sleep $((t - LAST)); LAST=$t
  DISPLAY=$DISP xwd -root -silent > "/tmp/${TAG}_t${t}.xwd" 2>/dev/null
  python3 "$HOME/games/xwd2png.py" "/tmp/${TAG}_t${t}.xwd" "${PREFIX}_t${t}.png" 2>/dev/null \
    && echo "saved ${PREFIX}_t${t}.png ${W}x${H}"
  rm -f "/tmp/${TAG}_t${t}.xwd"
done

kill $WINE_PID 2>/dev/null
"$HOME/.local/wine/wine-11.16-staging-amd64/bin/wineserver" -k 2>/dev/null
kill $XVFB_PID 2>/dev/null; wait $XVFB_PID 2>/dev/null
echo DONE
