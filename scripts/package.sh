#!/bin/bash
# Windows 배포 패키지 구성.
#
#   ~/.local/mingw/package.sh [출력디렉터리]
#
# scummvm.exe 와 그것이 실제로 요구하는 DLL, 그리고 엔진 데이터를 한 폴더에
# 모은다. DLL 목록은 objdump 로 실행 파일에서 직접 읽어내고, 그 DLL 들이
# 다시 요구하는 것까지 재귀적으로 따라간다.

set -eu

OUT="${1:-$HOME/games/scummvm-win}"
BUILD="$HOME/src/scummvm-win"
SRC="$HOME/src/scummvm"
SYS="$HOME/.local/mingw/deps/sysroot/mingw64"
TC="$HOME/.local/mingw/root/usr"

export PATH="$HOME/.local/mingw/root/usr/bin:$PATH"
OBJDUMP=x86_64-w64-mingw32-objdump

if [ ! -f "$BUILD/scummvm.exe" ]; then
  echo "scummvm.exe 가 없다: $BUILD" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$BUILD/scummvm.exe" "$OUT/"

# DLL 을 재귀적으로 수집한다. 시스템 DLL(대문자로 시작하는 윈도우 기본
# 제공분)은 건너뛴다.
collect() {
  local target="$1"
  local dll
  for dll in $($OBJDUMP -p "$target" 2>/dev/null | sed -n 's/^\tDLL Name: //p'); do
    case "$dll" in
      KERNEL32.dll|USER32.dll|GDI32.dll|SHELL32.dll|ole32.dll|msvcrt.dll|\
      WINMM.dll|WINSPOOL.DRV|ADVAPI32.dll|IMM32.dll|OLEAUT32.dll|SETUPAPI.dll|\
      VERSION.dll|RPCRT4.dll|dwmapi.dll|d3d9.dll|OPENGL32.dll|WS2_32.dll|\
      CRYPT32.dll|bcrypt.dll|USERENV.dll|SHLWAPI.dll|CFGMGR32.dll)
        continue ;;
    esac
    [ -f "$OUT/$dll" ] && continue

    # sysroot 뿐 아니라 툴체인 쪽도 뒤진다. libgcc_s_seh-1 / libstdc++-6 /
    # libwinpthread-1 은 GCC 가 딸려 보내는 것이라 sysroot/bin 에 없다.
    local found=
    local dir
    for dir in "$SYS/bin" \
               "$TC/lib/gcc/x86_64-w64-mingw32/13-win32" \
               "$TC/x86_64-w64-mingw32/lib"; do
      if [ -f "$dir/$dll" ]; then found="$dir/$dll"; break; fi
    done

    if [ -n "$found" ]; then
      cp "$found" "$OUT/"
      collect "$found"
    else
      echo "  경고: $dll 을 찾지 못했다 ($target 이 요구)" >&2
    fi
  done
}
collect "$BUILD/scummvm.exe"

# 엔진 데이터. encoding.dat 이 없으면 CJK 가 조용히 꺼진다.
for f in "$SRC"/dists/engine-data/*.dat "$SRC"/dists/engine-data/*.tbl \
         "$SRC"/gui/themes/*.zip; do
  [ -f "$f" ] && cp "$f" "$OUT/" 2>/dev/null || true
done

echo "패키지: $OUT"
echo "  exe  : $(du -h "$OUT/scummvm.exe" | cut -f1)"
echo "  DLL  : $(ls "$OUT"/*.dll 2>/dev/null | wc -l) 개"
echo "  데이터: $(ls "$OUT"/*.dat "$OUT"/*.zip 2>/dev/null | wc -l) 개"
echo "  합계 : $(du -sh "$OUT" | cut -f1)"
