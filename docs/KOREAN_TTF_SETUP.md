# 한글 고해상도 TTF 설정 설명서

ScummVM 한글 팬번역 텍스트를 TrueType 폰트로 2배/3배 해상도 렌더링하는
기능의 설정 문서입니다. 게임 그래픽은 원본 320×200 그대로 두고 텍스트
서피스만 확대합니다.

- 대상: SCUMM v0~v6 한글 번역 (Maniac Mansion, Indy3/4, MI1/MI2 등)
- 브랜치: `hires-korean-strline`
- 소스: `engines/scumm/charset.cpp`, `engines/scumm/scumm.cpp`

---

## 1. scummvm.ini 설정 키

타겟 섹션(`[m1-str]` 같은)에 넣습니다. **명령행 플래그로는 전달되지
않습니다** — ScummVM이 알 수 없는 옵션으로 거부합니다.

| 키 | 형식 | 기본값 | 설명 |
|---|---|---|---|
| `korean_hires_scale` | 1~3 | `1` | 텍스트 서피스 배율. `1`이면 기능 전체가 꺼짐 |
| `korean_alpha_text` | bool | `false` | 32bit 알파 안티에일리어싱. OpenGL 백엔드 필수 |
| `korean_ttf_map` | 경로 | (없음) | 맵 파일. 절대/상대 모두 가능 |
| `korean_ttf_font` | 경로 | (없음) | 맵이 없을 때 쓰는 기본 폰트 |
| `korean_ttf_bold_font` | 경로 | = default | 맵이 없을 때 bold 역할 |
| `korean_ttf_title_font` | 경로 | = default | 맵이 없을 때 title 역할 |
| `korean_ttf_size` | 6~128 | (자동) | 모든 역할의 크기를 강제. 맵의 `[sizes]`보다 우선 |

관련 표준 키:

| 키 | 설명 |
|---|---|
| `aspect_ratio=false` | 200→240 종횡비 보정 끄기. **1:1 픽셀 검증 시 필수** |
| `path` | 게임 폴더. 상대 경로 해석의 기준점 |

### 최소 설정

```ini
[mm-kor]
gameid=maniac
engineid=scumm
path=/home/thkim/games/mmkor
language=ko
platform=pc
korean_hires_scale=2
korean_alpha_text=true
```

`korean_ttf_map`이 없으면 게임 폴더의 `korean_ttf.map`을 자동으로 찾습니다.

### 실제 사용 중인 타겟

```ini
[mm-multi]                 ; v2, 2배, 통합 맵
korean_hires_scale=2
korean_ttf_map=/home/thkim/games/mmkor/km_multi.map
korean_alpha_text=true
aspect_ratio=false

[i3-multi]                 ; v3, 3배
korean_hires_scale=3
korean_ttf_map=/home/thkim/games/indy3kor/km_multi.map
korean_alpha_text=true
aspect_ratio=false

[mm-rel]                   ; 상대 경로
korean_ttf_map=korean_ttf.map

[mm-auto]                  ; 자동 발견 (korean_ttf_map 키 없음)
korean_hires_scale=2
korean_alpha_text=true
```

---

## 2. 경로 해석 규칙

절대 경로 판별: 첫 글자가 `/` 또는 `\`, 혹은 두 번째 글자가 `:` (`C:\...`).

| 대상 | 상대 경로 기준 |
|---|---|
| `korean_ttf_map` | 게임 폴더 (`path` 키) |
| 맵 안의 `[fonts]` 경로 | **맵 파일이 있는 폴더** |
| `korean_ttf_font` 등 폴백 키 | 절대 경로만 |

덕분에 번역 패치가 폰트를 동봉하고 폴더째 옮겨도 동작합니다:

```
mmkor/
  00.LFL ...
  korean.trs
  korean00.fnt
  korean_ttf.map        ← 설정 없이 자동 발견
  fonts/
    neodgm.ttf          ← 맵에 "fonts/neodgm.ttf" 로 기재
```

파일 열기는 `Common::FSNode` + `createReadStream()`을 씁니다. `Common::File`은
등록된 게임 경로만 뒤져서 임의 경로를 못 엽니다.

---

## 3. 맵 파일 형식

INI 형식입니다. **키 이름에 점(`.`)을 쓰면 파서가 거부**하므로 밑줄을
씁니다 (`height_8`).

### 전체 예시

```ini
[fonts]
default=fonts/NanumJangMiCe.ttf
bold=fonts/NanumJangMiCe.ttf
title=fonts/NanumJangMiCe.ttf

[sizes]
default=12pt
bold=12pt
title=16pt

[latin]
enabled=false
font=fonts/NanumBarunGothic.ttf
metrics=bitmap

[render]
mode=string

[map]
height_8=bold
height_9=default
height_12=title
```

### `[fonts]` — 역할별 폰트

역할은 `default`, `bold`, `title` 셋입니다. `bold`/`title`을 생략하면
`default`를 씁니다.

### `[sizes]` — 역할별 크기

생략하면 줄 상자(`_2byteHeight × scale`)에 맞춰 자동 결정됩니다.

| 형식 | 뜻 |
|---|---|
| `24` | 정확히 24px |
| `12pt` | 현재 배율 기준 포인트. 2배면 24px, 3배면 36px |
| `16x2` | 32px로 렌더 후 2배 다운스케일 (슈퍼샘플) |

`16x2` 형식은 픽셀 폰트를 네이티브 그리드에 두면서 배수가 아닌 줄 상자에
맞출 때 씁니다.

우선순위: `korean_ttf_size` (ini) > `[sizes]` > 자동 맞춤.

### `[latin]` — 영문/기호 처리

```ini
[latin]
enabled=true        ; 1바이트 문자도 TTF 로 렌더 (기본 false)
font=<경로>          ; 생략 시 한글 폰트와 동일
metrics=ttf         ; 전진폭도 TTF 에서 가져옴 (기본 bitmap)
```

**기본값은 비활성**입니다. 켜면 영문도 TTF로 나오지만, 게임의 전진폭과
TTF 메트릭이 충돌해 문장부호 위치가 어긋납니다. 끄면 영문은 게임 내장
비트맵을 쓰고 한글만 TTF가 됩니다 — 한 화면에서 정상 공존합니다.

`metrics=ttf`는 v0~v2에서 무시됩니다 (고정 셀 유지).

### `[render]` — 렌더링 단위

```ini
[render]
mode=string     ; 문자열 단위 (기본은 글자 단위)
mode=char       ; 글자 단위
```

`string`은 줄 전체를 `drawString()`으로 한 번에 그립니다. 베이스라인과
커닝이 폰트에 맡겨져 문장부호 문제가 사라집니다. **v0~v2는 강제로
`char`** 입니다 — 문자열 모드는 폰트 자체 전진폭으로 배치해 고정 셀
그리드를 벗어납니다.

### `[map]` — 원본 높이 → 역할

```ini
[map]
height_8=bold
height_9=default
height_12=title
```

키의 숫자는 **원본 비트맵 폰트의 높이**(`.fnt` 헤더 4번째 바이트)입니다.
확대된 줄 상자가 아닙니다 — 3배에서 8px UI 폰트는 상자가 24px이라
title로 오인됩니다.

지정하지 않은 높이의 기본 규칙:
- `_2byteHeight >= 12` → title
- 줄 상자 >= 24 → bold
- 그 외 → default

---

## 4. 게임/버전별 섹션

한 맵 파일로 여러 게임을 처리합니다. 섹션 이름에 접미사를 붙이면
구체적인 쪽이 이깁니다:

```
[fonts:maniac]   게임 id      ← 가장 우선
[fonts:v2]       SCUMM 버전
[fonts]          공통          ← 가장 나중
```

`[fonts]`, `[sizes]`, `[latin]`, `[render]`, `[map]` 모두 지원합니다.

`[map]`만은 **덮어쓰기가 아니라 병합**입니다. 공통 섹션이 기본값을 주고
구체적 섹션이 개별 높이만 수정합니다.

### 통합 맵 예시

```ini
# v2 는 8px 고정 셀 -> 셀에 맞는 픽셀 폰트만 가능
# v3+ 는 가변폭 가능 -> 손글씨체 + 문자열 렌더링

[fonts]
default=fonts/NanumJangMiCe.ttf

[fonts:v2]
default=fonts/neodgm.ttf

[sizes]
default=12pt

[sizes:v2]
default=16

[render]
mode=string

[render:v2]
mode=char

[map]
height_8=bold
height_9=default
height_12=title

[map:v2]
height_8=default

[map:indy4]
height_16=title
```

검증 결과:

| 타겟 | gameid | version | 선택된 폰트 | 적용 섹션 |
|---|---|---|---|---|
| mm-multi | maniac | 2 | neodgm | `[fonts:v2]` |
| i3-multi | indy3 | 3 | NanumJangMiCe | `[fonts]` |
| i4-multi | atlantis | 5 | NanumJangMiCe | `[fonts]` |

---

## 5. 게임별 폰트 높이

`[map]` 작성에 필요한 원본 `_2byteHeight` 값입니다.

| 게임 | 엔진 | 높이 | 비고 |
|---|---|---|---|
| Maniac Mansion | v2 | 8 | 고정 셀 |
| Indy3 | v3 | 8, 9 | |
| MI1 | v5 | 11, 8, 9, 8, 13 | |
| MI2 | v5 | 8, 9, 12 | |
| Indy4 | v5 | 8, 9, 16 | 16px 은 이 게임만 |

확인 방법 — `.fnt` 헤더 4바이트가 `[id, shadow, width, height]`:

```python
d = open('korean00.fnt','rb').read(4)
print(f"id={d[0]} shadow={d[1]} {d[2]}x{d[3]}")
```

---

## 6. v0~v2 제약

`CharsetRendererV2::getCharWidth()`가 **무조건 8을 반환**하고 스크립트가
그 그리드를 전제로 레이아웃을 계산합니다. 따라서:

- `[render] mode=string` 무시 (강제 `char`)
- `[latin] metrics=ttf` 무시 (`getKorTtfCharWidth()`가 −1 반환)
- 전진폭 보정 금지 — 한글 한 글자가 8px 셀 하나이고, 2배면 16px입니다.
  16px 픽셀 폰트의 글리프 폭과 정확히 일치하므로 넓힐 필요가 없습니다.

셀에 맞는 폰트를 골라야 합니다. **눈이 아니라 계조 수로** 판단합니다 —
2면 안티에일리어싱이 없다는 뜻, 즉 그 크기가 폰트의 네이티브 비트맵입니다.

| 폰트 | 16px (2배) | 24px (3배) |
|---|---|---|
| neodgm | 3 | 19 |
| DOSGothic | 2 | 16 |
| Galmuri11 | 40 | 2 |
| NanumGothic | 151 | 190 |

→ 2배는 neodgm 또는 DOSGothic, 3배는 Galmuri11. 셋 다 KS X 1001 2350자를
빠짐없이 커버합니다.

측정 코드:

```python
from PIL import Image, ImageDraw, ImageFont
import numpy as np
fo = ImageFont.truetype(path, size)
im = Image.new('L', (size*8, size*2), 0)
ImageDraw.Draw(im).text((2,2), "한글날밝은빛", font=fo, fill=255)
print(len(np.unique(np.asarray(im))))   # 2 = 픽셀 완벽
```

---

## 7. 검증 방법

### 스케일된 스크린샷을 믿지 말 것

ScummVM은 내부 서피스를 창 크기에 맞춰 늘이거나 줄입니다. 320×200 게임은
종횡비 보정으로 세로가 240이 되고 가로도 함께 축소돼(640×400 → 533×400),
**정상 렌더링된 16px 글리프가 13.4px로 뭉개집니다.** 이걸 "글자가 겹친다"고
오판하기 쉽습니다.

### 1:1 픽셀 캡처

```bash
~/games/cap11.sh /tmp/OUT mm-multi :290 2 "Escape@20,Escape@28" 42
#              접두사     타겟     디스플레이 배율 키이벤트          시각
```

세 옵션으로 모든 스케일링을 끄고 Xvfb를 내부 해상도와 같게 만듭니다:

```
--no-aspect-ratio             200→240 보정 없음
--stretch-mode=pixel-perfect  정수배만
--scale-factor=1              추가 확대 없음
```

로그에 `Setting 640 x 400 -> 640 x 400`처럼 양쪽이 같아야 합니다. 다르면
그 캡처의 픽셀 측정값은 무효입니다.

### 프레임버퍼 덤프 (최종 근거)

`drawKorTtfChar()` 안에서 `_textSurface`를 PGM으로 직접 씁니다. 백엔드를
완전히 우회합니다.

```cpp
#include "common/file.h"   // fopen 은 forbidden.h 가 금지

static int dumpN = 0;
if (++dumpN == 40) {
    Common::DumpFile df;
    if (df.open("/tmp/textsurf.pgm")) {
        Common::String hdr = Common::String::format("P5\n%d %d\n255\n", dest.w, dest.h);
        df.write(hdr.c_str(), hdr.size());
        for (int yy = 0; yy < dest.h; ++yy)
            df.write(dest.getBasePtr(0, yy), dest.w);
        df.close();
    }
}
```

글자 시작 위치가 셀 그리드에 놓여야 합니다 (8px 셀, 2배면 16px 간격).
`cap11.sh` 결과가 이 덤프와 픽셀 단위로 일치함을 확인했습니다.

---

## 8. 알려진 제약

- **32bit 알파는 OpenGL 전용.** SurfaceSDL 백엔드는 지원 포맷이 모두
  2바이트 이하라 `korean_alpha_text=true`가 무시됩니다.
- **`INIFile::getKeys()` 널 역참조** — ScummVM 본체 버그입니다. 없는
  섹션을 조회하면 `getSection()`이 `nullptr`을 주는데 그대로 역참조합니다.
  우리 쪽은 `hasSection()` 선검사로 회피합니다.
- **인트로는 텍스트가 없습니다.** 타이틀 화면에서 대기하므로 Escape를
  몇 번 보내야(`"Escape@20,Escape@28"`) 대사가 나옵니다.
- `[latin] enabled=true`는 문장부호 위치가 어긋납니다. 전진폭은 게임
  비트맵, 글리프는 TTF 메트릭이라 근본적으로 충돌합니다.
