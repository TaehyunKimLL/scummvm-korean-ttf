#!/bin/bash
# Windows 배포본 만들기 (포터블 ZIP + NSIS 설치 파일).
#
#   ~/.local/mingw/dist.sh [버전]
#
# 산출물은 ~/games/dist/ 에 놓는다:
#   scummvm-kor-<버전>-win64.zip          압축만 풀면 되는 포터블
#   scummvm-kor-<버전>-win64-setup.exe    설치 프로그램
#
# 패키지 폴더(~/games/scummvm-win)는 package.sh 가 먼저 만들어 두어야 한다.

set -eu

VER="${1:-$(cd "$HOME/src/scummvm" && git describe --tags --always 2>/dev/null || echo dev)}"
PKG="$HOME/games/scummvm-win"
DIST="$HOME/games/dist"
STAGE="$DIST/stage/ScummVM-Kor"
NSIS_ROOT="$HOME/.local/nsis/root"

export PATH="$HOME/.local/mingw/root/usr/bin:$PATH"

[ -f "$PKG/scummvm.exe" ] || { echo "먼저 package.sh 를 돌려라" >&2; exit 1; }

rm -rf "$DIST/stage"
mkdir -p "$STAGE"

# 실행 파일과 라이브러리, 데이터만 (설치 파일 자신과 빌드 부산물은 제외)
cp "$PKG"/scummvm.exe "$STAGE/"
cp "$PKG"/*.dll "$STAGE/"
cp "$PKG"/*.dat "$STAGE/" 2>/dev/null || true
cp "$PKG"/*.zip "$STAGE/" 2>/dev/null || true
cp "$PKG"/*.tbl "$STAGE/" 2>/dev/null || true
cp "$PKG"/COPYING.txt "$STAGE/" 2>/dev/null || true
cp "$PKG"/KOREAN_TTF_SETUP.md "$STAGE/" 2>/dev/null || true
[ -d "$PKG/mmkor" ] && cp -r "$PKG/mmkor" "$STAGE/"

# 디버그 심볼 제거 (이미 되어 있으면 그대로 통과)
x86_64-w64-mingw32-strip --strip-all "$STAGE/scummvm.exe" 2>/dev/null || true
for d in "$STAGE"/*.dll; do
  x86_64-w64-mingw32-strip --strip-all "$d" 2>/dev/null || true
done

cat > "$STAGE/읽어보기.txt" <<'EOF'
ScummVM 한글 고해상도 TTF 빌드
==============================

압축을 푼 자리에서 scummvm.exe 를 실행하면 된다. 설치는 필요 없다.

한글 텍스트를 TrueType 폰트로 2배/3배 해상도에 그린다. 게임 그래픽은
원본 320x200 그대로 두고 텍스트만 확대하므로, 도트 그림은 상하지 않으면서
글자만 또렷해진다.

빠른 확인
---------
같이 들어 있는 mmkor 폴더가 예제다.

  scummvm.exe --path=mmkor --auto-detect

폴더 안의 korean_ttf.map 이 자동으로 읽히고, 그 안의 [hires] scale=2 가
2배 해상도를 켠다. 별도 설정은 필요 없다.

내 게임에 적용하기
------------------
게임 폴더에 korean_ttf.map 을 만들고 폰트를 넣는다:

  내게임/
    korean.trs, korean00.fnt, ...
    korean_ttf.map
    fonts/neodgm.ttf

korean_ttf.map:

  [hires]
  scale=2
  alpha=true

  [fonts]
  default=fonts/neodgm.ttf

  [sizes]
  default=16

  [map]
  height_8=default

자세한 내용은 KOREAN_TTF_SETUP.md 를 볼 것.

폰트 고르기
-----------
비트맵 폰트 셀에 맞는 크기여야 글자가 뭉개지지 않는다.

  2배: neodgm 16px, DOS고딕 16px
  3배: Galmuri11 24px

알파 안티에일리어싱(alpha=true)은 32bit 출력이 필요하므로 OpenGL 백엔드에서만
동작한다. 안 되면 자동으로 꺼지고 비트맵 폰트로 돌아간다.

라이선스
--------
ScummVM 은 GPL v3. COPYING.txt 참조.
동봉한 폰트는 각자의 라이선스를 따른다.
EOF

# 포터블 ZIP
ZIPNAME="scummvm-kor-${VER}-win64.zip"
( cd "$DIST/stage" && zip -qr9 "$DIST/$ZIPNAME" "ScummVM-Kor" )

# NSIS 설치 파일. 출력 이름은 .nsi 안에서 APPVERSION 으로 만든다.
if [ -x "$NSIS_ROOT/usr/bin/makensis" ] && [ -f "$PKG/scummvm-kor.nsi" ]; then
  cp "$PKG/scummvm-kor.nsi" "$STAGE/"
  if ( cd "$STAGE" && NSISDIR="$NSIS_ROOT/usr/share/nsis" \
         "$NSIS_ROOT/usr/bin/makensis" -DAPPVERSION="$VER" scummvm-kor.nsi \
         > "$DIST/nsis-$VER.log" 2>&1 ); then
    mv "$STAGE/scummvm-kor-${VER}-win64-setup.exe" "$DIST/" 2>/dev/null
    rm -f "$STAGE/scummvm-kor.nsi"
  else
    echo "NSIS 실패, $DIST/nsis-$VER.log 확인" >&2
  fi
fi

rm -rf "$DIST/stage"

echo
echo "배포본: $DIST"
ls -lh "$DIST"/scummvm-kor-${VER}-win64* 2>/dev/null | awk '{printf "  %-52s %s\n", $9, $5}'
