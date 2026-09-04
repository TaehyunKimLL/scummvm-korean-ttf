# ScummVM 한글 고해상도 TTF 렌더링

SCUMM 엔진의 한글 팬번역 텍스트를 TrueType 폰트로 2배·3배 해상도에 그린다.
게임 그래픽은 원본 320×200 그대로 두고 텍스트 서피스만 확대하므로, 도트
그림은 상하지 않으면서 글자만 또렷해진다.

FM-Towns·PC98 일본어 모드가 쓰던 접근을 한글에 맞춰 가져온 것이다: 텍스트
레이어를 높은 해상도로 유지하고 배경은 합성 시점에 업스케일한다.

## 무엇이 달라지나

원본은 한글을 8×8 또는 12×12 비트맵에 욱여넣는다. 획이 뭉개져 글자를
알아보기 어렵고, 확대하면 계단만 커진다. 이 패치는 같은 자리에 TrueType
글리프를 그린다.

- 텍스트 서피스만 2×/3× — 게임 화면은 네이티브 해상도 유지
- 32bit 알파 안티에일리어싱 (OpenGL 백엔드)
- 글자 단위 / 문자열 단위 렌더링 선택
- 게임·엔진 버전별 폰트 설정을 맵 파일 하나로

## 지원 범위

| 게임 | 엔진 | 상태 |
|---|---|---|
| Monkey Island 1 | v5 | 확인 |
| Monkey Island 2 | v5 | 확인 |
| Indiana Jones 4: Fate of Atlantis | v5 | 확인 |
| Indiana Jones 3: Last Crusade | v3 | 확인 |
| Maniac Mansion | v2 | 확인 (고정 셀, 픽셀 폰트만) |

v0~v2 는 스크립트가 8픽셀 고정 셀을 전제로 레이아웃을 잡으므로 그 셀에
맞는 픽셀 폰트만 쓸 수 있다. v3 이상은 가변폭 폰트도 된다.

## 빠른 시작

게임 폴더에 `korean_ttf.map` 을 놓고 폰트를 넣으면 끝이다. ScummVM 설정은
건드릴 필요가 없다.

```
내게임/
  korean.trs, korean00.fnt, ...
  korean_ttf.map
  fonts/neodgm.ttf
```

`korean_ttf.map`:

```ini
[hires]
scale=2
alpha=true

[fonts]
default=fonts/neodgm.ttf

[sizes]
default=16

[map]
height_8=default
```

맵은 게임 폴더에서 자동으로 발견되고, `[hires] scale` 이 해상도를 정한다.
폰트 경로는 맵 파일 기준 상대 경로라 폴더째 옮겨도 동작한다.

전체 설정은 [docs/KOREAN_TTF_SETUP.md](docs/KOREAN_TTF_SETUP.md) 참조.

## 폰트 고르기

비트맵 셀에 맞는 크기여야 글자가 뭉개지지 않는다. 눈으로 고르지 말고
계조 수를 재라 — 2 면 안티에일리어싱이 없다는 뜻, 즉 그 크기가 폰트의
네이티브 비트맵이다.

| 폰트 | 16px (2배) | 24px (3배) |
|---|---|---|
| neodgm | 3 | 19 |
| DOS고딕 | 2 | 16 |
| Galmuri11 | 40 | 2 |
| 나눔고딕 | 151 | 190 |

→ 2배는 neodgm 이나 DOS고딕, 3배는 Galmuri11. 셋 다 KS X 1001 2350자를
빠짐없이 담고 있다.

가변폭이 가능한 v3 이상에서는 손글씨체도 쓸 만하다.

## 소스

패치는 ScummVM 포크의 브랜치에 있다:

  https://github.com/TaehyunKimLL/scummvm/tree/hires-korean-ttf

`patches/` 에 같은 내용이 `git format-patch` 형식으로 들어 있다:

```bash
git clone https://github.com/scummvm/scummvm.git
cd scummvm
git am /path/to/patches/*.patch
```

건드린 파일은 7개, 1414줄이다. 주로 `engines/scumm/charset.cpp` 와
`engines/scumm/gfx.cpp`.

## 빌드

리눅스에서 윈도우 실행 파일을 만드는 스크립트가 `scripts/` 에 있다.
sudo 없이 사용자 홈에 툴체인을 푸는 방식이다.

```bash
source scripts/env.sh      # MinGW-w64 + SDL2/FreeType/OGG sysroot
./scripts/package.sh       # scummvm.exe + DLL 수집
./scripts/dist.sh 1.0      # 포터블 ZIP + NSIS 설치 파일
```

`scripts/fixpc.py` 는 MSYS2 패키지의 `.pc` prefix 를 고친다. MSYS2 는
`/mingw64` 에 설치된다고 가정하고 만들어져 있어 그대로는 못 쓴다.

## 검증

**스케일된 스크린샷을 믿지 마라.** ScummVM 은 내부 서피스를 창 크기에 맞춰
늘이거나 줄인다. 320×200 게임은 종횡비 보정으로 세로가 240 이 되고 가로도
함께 축소되어(640×400 → 533×400), 정상 렌더링된 16px 글리프가 13.4px 로
뭉개진다. 이걸 "글자가 겹친다"고 오판하기 쉽다.

`scripts/cap11.sh` 는 모든 스케일링을 끄고 Xvfb 를 내부 해상도와 똑같이
만들어 1:1 픽셀을 얻는다:

```bash
./scripts/cap11.sh /tmp/OUT mm-kor :290 2 "Escape@20" 42
```

로그에 `Setting 640 x 400 -> 640 x 400` 처럼 양쪽이 같은지 확인할 것.
다르면 그 캡처의 픽셀 측정값은 무효다.

## 라이선스

ScummVM 과 같은 GPL v3.

동봉한 폰트는 각자의 라이선스를 따른다. neodgm 은 SIL OFL, Galmuri 도
SIL OFL 이다.
