#!/bin/bash
# Windows (x86_64) 크로스 빌드 환경.
#
#   source ~/.local/mingw/env.sh
#
# 구성:
#   ~/.local/mingw/root      apt 에서 푼 MinGW-w64 GCC 13 툴체인 (sudo 불필요)
#   ~/.local/mingw/deps/sysroot/mingw64
#                            SDL2 공식 mingw 릴리스 + MSYS2 에서 가져온
#                            freetype / ogg / vorbis / flac / mad
#
# 주의: 컴파일러 이름에 -win32 접미사가 붙는다 (posix 스레드 변형이 아님).

MINGW_ROOT="$HOME/.local/mingw/root/usr"
MINGW_SYS="$HOME/.local/mingw/deps/sysroot/mingw64"

export PATH="$MINGW_ROOT/bin:$PATH"

# configure 가 찾는 표준 이름으로 심볼릭 링크를 만들어 둔다
mkdir -p "$HOME/.local/mingw/bin"
for t in gcc g++ cpp c++; do
  if [ ! -e "$HOME/.local/mingw/bin/x86_64-w64-mingw32-$t" ]; then
    ln -sf "$MINGW_ROOT/bin/x86_64-w64-mingw32-$t-win32" \
           "$HOME/.local/mingw/bin/x86_64-w64-mingw32-$t" 2>/dev/null
  fi
done
export PATH="$HOME/.local/mingw/bin:$PATH"

# 크로스 빌드에서는 LIBDIR 을 반드시 지정해야 호스트 .pc 를 섞지 않는다
export PKG_CONFIG_LIBDIR="$MINGW_SYS/lib/pkgconfig"
export PKG_CONFIG_PATH="$MINGW_SYS/lib/pkgconfig"
export MINGW_SYS

echo "MinGW 환경 준비됨"
echo "  컴파일러: $(command -v x86_64-w64-mingw32-g++)"
echo "  sysroot : $MINGW_SYS"
