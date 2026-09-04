#!/bin/bash
# cap11.sh - 1:1 픽셀 캡처 (창 스케일링 없음)
#
# ScummVM 은 기본적으로 내부 서피스를 창 크기에 맞춰 늘이거나 줄인다.
# 320x200 게임은 종횡비 보정으로 세로가 240 이 되고, 그 과정에서 가로도
# 축소되어 (예: 640x400 -> 533x400) 글리프가 뭉개진다. 그 상태를 캡처해
# 보면 멀쩡한 렌더링도 "글자가 겹친다"고 오판하게 된다.
#
# 이 스크립트는 세 옵션으로 스케일링을 완전히 끄고, Xvfb 를 내부 해상도와
# 똑같이 만들어 1:1 픽셀을 얻는다:
#   --no-aspect-ratio           세로 200->240 보정 끄기
#   --stretch-mode=pixel-perfect 정수배만 허용
#   --scale-factor=1            추가 확대 없음
#
# 사용법:
#   cap11.sh <출력접두사> <타겟> <디스플레이> <스케일> [키이벤트] <시각...>
# 예:
#   ~/games/cap11.sh /tmp/OUT mm-neo :290 2 "Escape@20,Escape@28" 42
#
# 스케일 2 이면 640x400, 3 이면 960x600 으로 Xvfb 를 띄운다.

set -u
PREFIX=$1; TARGET=$2; DISP=$3; SCALE=$4; KEYS=$5; shift 5
TIMES=("$@")

W=$((320 * SCALE))
H=$((200 * SCALE))
TAG=$(basename "$PREFIX")

export SDL_AUDIODRIVER=dummy
export LD_LIBRARY_PATH=$HOME/.local/sysroot/usr/lib/x86_64-linux-gnu

Xvfb "$DISP" -screen 0 "${W}x${H}x24" -nolisten tcp >/dev/null 2>&1 &
XVFB_PID=$!
sleep 2

DISPLAY=$DISP $HOME/src/scummvm/scummvm \
  --gfx-mode=opengl --no-filtering \
  --no-aspect-ratio --stretch-mode=pixel-perfect --scale-factor=1 \
  "$TARGET" > "/tmp/run_$TAG.log" 2>&1 &
SCUMM_PID=$!

# 키 이벤트: "Escape@20,Return@28" 형식 (초 단위)
if [ -n "$KEYS" ] && [ "$KEYS" != "none" ]; then
  (
    for kv in ${KEYS//,/ }; do
      key=${kv%@*}; at=${kv#*@}
      sleep_until=$at
      while [ "$(date +%s)" -lt 0 ]; do :; done
      sleep "$sleep_until" 2>/dev/null
      DISPLAY=$DISP xdotool search --sync --onlyvisible --class scummvm key "$key" 2>/dev/null
    done
  ) &
fi

LAST=0
for t in "${TIMES[@]}"; do
  sleep $((t - LAST)); LAST=$t
  DISPLAY=$DISP xwd -root -silent > "/tmp/${TAG}_t${t}.xwd" 2>/dev/null
  python3 "$HOME/games/xwd2png.py" "/tmp/${TAG}_t${t}.xwd" "${PREFIX}_t${t}.png" 2>/dev/null \
    && echo "saved ${PREFIX}_t${t}.png ${W}x${H} (1:1)"
  rm -f "/tmp/${TAG}_t${t}.xwd"
done

kill $SCUMM_PID 2>/dev/null; wait $SCUMM_PID 2>/dev/null
kill $XVFB_PID 2>/dev/null; wait $XVFB_PID 2>/dev/null
echo DONE
