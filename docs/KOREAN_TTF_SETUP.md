> **구형 문서.** `korean_ttf.map`/TrueType 로더 기준이며 현재 `hires-text` 브랜치는 `korean_ttf_map`을 읽지 않는다. 현행은 `HIRES_TEXT_SETUP.md`.

# CJK 고해상도 TTF 설정 설명서

ScummVM 한글·일본어·중국어 팬번역 텍스트를 TrueType 폰트로 2배/3배 해상도
렌더링하는 기능의 설정 문서입니다. 게임 그래픽은 원본 320×200 그대로 두고
텍스트 서피스만 확대합니다.

한 맵 파일에서 **비트맵 폰트 · TTF 폰트 · 번역 파일 · 인코딩**을 모두
지정합니다.

- 대상: SCUMM v0~v6 CJK 번역 (Maniac Mansion, Indy3/4, MI1/MI2 등)
- 브랜치: `hires-text-i18n`
- 소스: `engines/scumm/charset.cpp`, `engines/scumm/string.cpp`, `engines/scumm/scumm.cpp`

기본값은 전부 한국어라, 기존 한글 패치는 맵을 고치지 않아도 그대로
동작합니다.

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

설정 키 이름이 `korean_` 으로 시작하는 것은 이 기능이 한글 패치에서
출발했기 때문입니다. 지금은 CJK 전반에 쓰이지만 기존 사용자의 ini 가
깨지지 않도록 이름은 그대로 두었습니다.

**맵 파일만으로도 전부 설정할 수 있습니다.** ini 는 맵을 덮어쓸 때만
필요합니다.

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
  00.LFL ...            게임 데이터
  korean.trs            번역 파일       ([translation] file=)
  korean00.fnt          비트맵 폰트     ([bitmap] multi=)
  korean_ttf.map        ← 설정 없이 자동 발견
  fonts/
    neodgm.ttf          TTF            ([fonts] default=, 맵 기준 상대 경로)
```

파일 열기는 `Common::FSNode` + `createReadStream()`을 씁니다. `Common::File`은
등록된 게임 경로만 뒤져서 임의 경로를 못 엽니다.

---

## 3. 맵 파일 형식

INI 형식입니다. **키 이름에 점(`.`)을 쓰면 파서가 거부**하므로 밑줄을
씁니다 (`height_8`).

### 전체 예시

```ini
[hires]
scale=2
alpha=true

[encoding]
codepage=cp949

[bitmap]
multi=korean%02d.fnt
single=korean.fnt
glyphs=2350

[fonts]
default=fonts/NanumJangMiCe.ttf
bold=fonts/NanumJangMiCe.ttf
title=fonts/NanumJangMiCe.ttf

[sizes]
default=12pt
bold=12pt
title=16pt

[translation]
file=korean.trs

[latin]
enabled=false
font=fonts/NanumBarunGothic.ttf
bitmap=lat24.fnt
metrics=game

[shadow]
mode=game
offset=0
color=0

[render]
mode=string

[map]
height_8=bold
height_9=default
height_12=title
```

위 값은 모두 기본값이라, 한글 패치라면 `[fonts]` 와 `[map]` 만 있으면
됩니다. 나머지는 다른 언어이거나 파일 이름이 다를 때만 씁니다.

### `[hires]` — 해상도와 합성

```ini
[hires]
scale=2        ; 1~3. 1 이면 기능 전체가 꺼진다
alpha=true     ; 32bit 알파 안티에일리어싱. OpenGL 백엔드 필요
```

생략해도 `[fonts]` 에 폰트가 있으면 자동으로 2배가 켜집니다. TTF 는 고해상도
에서만 의미가 있기 때문입니다.

우선순위는 `korean_hires_scale` (ini) > `[hires] scale` > 폰트 존재 시 2배.

### `[encoding]` — 2바이트 문자 인코딩

```ini
[encoding]
codepage=cp949     ; sjis(cp932) | gbk(cp936) | uhc(cp949) | big5(cp950) | johab
```

생략하면 게임 언어로 판단합니다.

| 언어 | 기본 코드페이지 |
|---|---|
| 일본어 (JA_JPN) | cp932 (Shift-JIS) |
| 중국어 간체 (ZH_CHN) | cp936 (GBK) |
| 중국어 번체 (ZH_TWN) | cp950 (Big5) |
| 그 외 (한국어 포함) | cp949 (UHC) |

이 값은 두 곳에 쓰입니다 — TTF 글리프를 찾을 유니코드 변환, 그리고
비트맵 폰트의 글자 인덱스 계산.

### `[bitmap]` — 엔진 비트맵 폰트

번역 패치가 동봉하는 `.fnt` 파일의 이름과 글자 수입니다.

```ini
[bitmap]
multi=korean%02d.fnt   ; 번호가 붙은 세트 (charset 별로 하나씩, 최대 20개)
single=korean.fnt      ; 번호 파일이 하나도 없을 때 쓰는 단일 폰트
glyphs=2350            ; 파일에 든 글자 수
```

`glyphs` 는 코드페이지의 문자 집합과 맞아야 합니다 — 파일 크기 계산에
쓰이므로 틀리면 글리프가 어긋납니다.

| 문자 집합 | 글자 수 |
|---|---|
| KS X 1001 (한국어) | 2350 |
| JIS X 0208 (일본어) | 6879 |
| GB 2312 (중국어 간체) | 6763 |
| Big5 (중국어 번체) | 13053 |

`.fnt` 헤더는 4바이트 `[id, shadow, width, height]` 이고 그 뒤에 글리프
비트맵이 이어집니다.

### `[translation]` — 런타임 번역 파일

```ini
[translation]
file=korean.trs
```

`SCVMTRS ` 매직으로 시작하는 번역 번들입니다. 게임 리소스를 직접 고치지
않고 실행 중에 문자열을 갈아끼우는 방식으로, MI2·Indy3·Maniac Mansion 등이
이 형식을 씁니다.

MI1 한글 패치처럼 리소스를 직접 수정한 경우엔 이 파일이 없습니다.

### `[fonts]` — 역할별 TTF 폰트

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

## 5. 게임별 설정 예제

실제로 검증한 다섯 게임의 맵입니다. 폰트 높이는 동봉된 `.fnt` 헤더에서
읽은 실측값입니다.

### Maniac Mansion — v2, 2배

폰트가 `korean00.fnt` 8×8 하나뿐입니다. v2 는 스크립트가 8픽셀 고정 셀을
전제로 레이아웃을 잡으므로 **셀에 맞는 픽셀 폰트만** 쓸 수 있고, 문자열
단위 렌더링도 쓸 수 없습니다.

```ini
# korean_ttf.map — Maniac Mansion
[hires]
scale=2
alpha=true

[fonts]
default=fonts/neodgm.ttf

[sizes]
default=16          ; 8px 셀 x2 = 16px. neodgm 의 네이티브 크기

[render]
mode=char           ; v2 는 어차피 강제로 char

[map]
height_8=default
```

### Indy 3: Last Crusade — v3, 3배

폰트 2종(8×8, 9×9). v3 부터 가변폭 폰트와 문자열 단위 렌더링이 가능해
손글씨체를 쓸 수 있습니다.

```ini
# korean_ttf.map — Indy3
[hires]
scale=3
alpha=true

[fonts]
default=fonts/NanumJangMiCe.ttf

[sizes]
default=12pt        ; 3배에서 36px

[render]
mode=string

[map]
height_8=default
height_9=default
```

### Monkey Island 1 — v5, 3배

폰트 5종이고 높이가 8·9·12 세 가지입니다. 12px 짜리(`korean00`,
`korean04`)는 인트로 크레딧에 쓰이므로 title 역할을 줍니다.

**번역 파일이 없습니다** — MI1 한글 패치는 게임 리소스를 직접 수정한
방식이라 `[translation]` 이 필요 없습니다.

```ini
# korean_ttf.map — MI1
[hires]
scale=3
alpha=true

[fonts]
default=fonts/NanumJangMiCe.ttf
bold=fonts/NanumBarunGothicBold.ttf
title=fonts/NanumJangMiCe.ttf

[sizes]
default=12pt
bold=9pt            ; verb 영역은 작게
title=16pt          ; 크레딧

[render]
mode=string

[map]
height_8=bold       ; verb, 인벤토리
height_9=default    ; 대사
height_12=title     ; 크레딧
```

### Monkey Island 2 — v5, 3배

폰트 8종이지만 높이 집합은 MI1 과 같은 8·9·12 입니다. MI1 설정을 그대로
쓸 수 있고, 차이는 번역 파일이 있다는 점뿐입니다.

```ini
# korean_ttf.map — MI2
[hires]
scale=3
alpha=true

[fonts]
default=fonts/NanumJangMiCe.ttf

[sizes]
default=12pt
title=16pt

[translation]
file=korean.trs     ; 기본값이라 사실 생략 가능

[render]
mode=string

[map]
height_8=default
height_9=default
height_12=title
```

### Indy 4: Fate of Atlantis — v5, 3배

폰트 3종(8×8, 10×9, **16×16**). 16px 폰트는 이 게임에만 있습니다.

```ini
# korean_ttf.map — Indy4
[hires]
scale=3
alpha=true

[fonts]
default=fonts/NanumJangMiCe.ttf

[sizes]
default=12pt
title=16pt

[render]
mode=string

[map]
height_8=default
height_9=default
height_16=title     ; 이 게임에만 있는 큰 폰트
```

### 게임별 폰트 높이 요약

`[map]` 을 쓸 때 필요한 실측값입니다. 숫자는 `.fnt` 헤더의 height 이지
확대된 줄 상자가 아닙니다.

| 게임 | 엔진 | 폰트 수 | 높이 | 번역 파일 |
|---|---|---|---|---|
| Maniac Mansion | v2 | 1 | 8 | korean.trs |
| Indy3 | v3 | 2 | 8, 9 | korean.trs |
| MI1 | v5 | 5 | 8, 9, 12 | 없음 (리소스 직접 수정) |
| MI2 | v5 | 8 | 8, 9, 12 | korean.trs |
| Indy4 | v5 | 3 | 8, 9, 16 | korean.trs |

직접 확인하려면 `.fnt` 헤더 4바이트를 읽으면 됩니다 —
`[id, shadow, width, height]`:

```python
d = open('korean00.fnt','rb').read(4)
print(f"id={d[0]} shadow={d[1]} {d[2]}x{d[3]}")
```

3배에서 8px 폰트는 줄 상자가 24px 이 되므로, `height_24` 가 아니라
`height_8` 로 적어야 합니다.

### 여러 게임을 한 맵으로

버전별 섹션을 쓰면 파일 하나를 모든 게임 폴더에 복사해도 됩니다.

```ini
# korean_ttf.map — 공용
[hires]
scale=3
alpha=true

[hires:v2]
scale=2             ; v2 는 2배 (16px 픽셀 폰트에 맞춤)

[fonts]
default=fonts/NanumJangMiCe.ttf     ; v3+ 가변폭

[fonts:v2]
default=fonts/neodgm.ttf            ; v2 픽셀 폰트

[sizes]
default=12pt
title=16pt

[sizes:v2]
default=16

[render]
mode=string

[render:v2]
mode=char

[map]
height_8=default
height_9=default
height_12=title

[map:indy4]
height_16=title

[map:maniac]
height_8=default
```

---

## 6. 비트맵 폰트 굽기 (SVFN)

`.fnt` 를 확장한 SVFN 형식은 8비트 알파와 글자별 폭을 담는다. 굽는 쪽만
FreeType 을 쓰므로 **게임을 돌리는 빌드에 FreeType 이 없어도** 안티에일리어싱된
글자가 나온다. 형식은 `docs/FONT_FORMAT.md` 참조.

```bash
# 한글 2350자, 8bpp 알파, 32px 로 렌더해 24px 셀에 담기
python3 scripts/mkfont.py NanumJangMiCe.ttf han24.fnt \
        --size 32 --cell 24 --bpp 8

# 라틴 256자, 전각 글리프 (v0-v2 처럼 셀이 고정된 엔진용)
python3 scripts/mkfont.py ipag.ttf lat24.fnt \
        --size 32 --cell 24 --bpp 8 --latin --fullwidth
```

| 옵션 | 뜻 |
|---|---|
| `--size` | 글꼴을 몇 px 로 렌더할지 |
| `--cell` | 셀 크기. 손글씨처럼 잉크가 작은 글꼴은 `--size` 를 키우고 `--cell` 로 담는다 |
| `--bpp 1\|8` | 1 = 흑백, 8 = 알파 |
| `--latin` | 단일 바이트 폰트. 글리프 번호 = 문자 코드 |
| `--fullwidth` | 라틴을 전각 글리프로. 셀이 고정된 v0-v2 용 |
| `--fixed` | 라틴을 고정폭으로 |
| `--center` | 잉크를 셀 가운데로 (고정폭이면 기본) |
| `--variable` | 글자별 전진 폭 표를 넣는다 |

맵에서는 `[bitmap]` 과 `[latin] bitmap=` 으로 가리킨다.

```ini
[bitmap]
multi=han%02d.fnt

[latin]
enabled=true
bitmap=lat24.fnt
metrics=bitmap        ; 생략하면 게임 원본 폭 (줄바꿈 보존)
```

**전각 라틴은 일본어 글꼴에서 가져와야 한다.** 한국어 글꼴의 U+FF21 은
반각 글자에 여백만 붙인 것이라 셀 안에서 성겨 보인다. 실측 결과:

| 글꼴 | 전각 A 잉크 | 반각 A 잉크 | 계조 | 판정 |
|---|---|---|---|---|
| MiraeroNormal (한) | 12 | 12 | 2 | 반각+여백 |
| NotoSansCJK | 22 | 20 | 95 | 전각 아님 |
| unifont_jp | 22 | 12 | 2 | 전각이나 계단 |
| **IPA고딕** | **22** | **16** | **89** | **전각 + 안티에일리어싱** |

### v0~v2 의 제약

`CharsetRendererV2::getCharWidth()` 가 8 을 그대로 돌려주므로 **v2 에서는
`metrics=bitmap` 이 무시된다.** 스크립트가 8px 셀을 전제로 화면을 짜기
때문이고, 그래서 v2 는 `--fullwidth` 나 `--fixed` 로 구워 셀에 맞추는 것이
맞다. v3 이상은 두 방식 모두 동작한다.

---

## 7. 검증된 게임

| 게임 | 엔진 | 폰트 높이 | 비고 |
|---|---|---|---|
| Maniac Mansion | v2 | 8 | 고정 셀 (getCharWidth 8 고정) |
| Zak McKracken | v2 | 8 | 고정 셀 |
| Indiana Jones 3 | v3 | 8, 9 | 가변폭 가능 |
| **Loom CD** | **v4** | **8, 9** | |
| Monkey Island 1 | v5 | 11, 8, 9, 8, 13 | |
| Monkey Island 2 | v5 | 8, 9, 12 | |
| Indiana Jones 4 | v5 | 8, 9, 16 | |

폰트 높이는 게임 폴더의 `korean%02d.fnt` 헤더 4번째 바이트에 있다.
`scripts/bakeset.sh` 가 이 높이에 맞춰 SVFN 한 벌을 구워 준다.

```bash
scripts/bakeset.sh NanumJangMiCe.ttf ipag.ttf 3 out 8 9 16
# -> out/han08.fnt(24px 셀) han09.fnt(27px) han16.fnt(48px) + lat*
```

### 게임별 시작 관문

렌더링을 확인하려면 먼저 게임 화면까지 들어가야 하는데, 게임마다 막히는
지점이 다르다. 여기서 멈춘 것을 렌더러 문제로 오해하기 쉽다.

- **Monkey Island 2** — 보라색 화면에 상자 두 개. 왼쪽을 눌러야 넘어간다.
- **Loom CD** — ScummVM 의 CD 오디오 안내(모달) → 난이도 → 길드 심볼
  복사방지. 안내는 게임 폴더에 빈 `CDDA.SOU` 를 두면 건너뛴다.
  복사방지는 매뉴얼이 있어야 통과할 수 있다.
- **Indiana Jones 4** — 도입부 컷신이 길다. 세이브를 만들어 두고
  `--save-slot` 으로 건너뛰는 편이 빠르다.

## 8. 외곽선과 그림자

게임의 `_2byteShadow` 는 내장 비트맵 글꼴이 어떻게 그려졌는지를 말할 뿐이라,
글꼴을 갈아끼우면 맞지 않는다. `[shadow]` 로 덮어쓴다.

```ini
[shadow]
mode=outline      ; none | drop | outline | stroke | game
offset=2          ; 배율을 따르려면 생략
color=4           ; 팔레트 인덱스
```

| mode | 모양 |
|---|---|
| `none` | 없음 |
| `drop` | 오른쪽 아래로 한 벌 |
| `outline` | 여덟 방향 |
| `stroke` | 외곽선 + 왼쪽 아래 그림자 |
| `game` | 게임이 정한 대로 (기본) |

TTF · SVFN · 내장 비트맵 **모든 경로**에 적용된다.

**`color` 를 함께 지정하는 편이 좋다.** 그림자 색의 기본값은 0 인데 자막
배경도 검정인 경우가 많아, `mode` 만 바꾸면 아무 차이가 없어 보인다.

---

## 8. 다른 언어에 적용하기

한국어가 아닌 번역은 인코딩과 파일 이름을 알려주면 됩니다.

### 일본어 팬번역

```ini
[hires]
scale=2
alpha=true

[encoding]
codepage=cp932

[bitmap]
multi=japanese%02d.fnt
glyphs=6879         ; JIS X 0208

[fonts]
default=fonts/misaki_gothic.ttf

[sizes]
default=16

[translation]
file=japanese.trs

[render]
mode=char

[map]
height_8=default
```

### 중국어 번체

```ini
[encoding]
codepage=big5

[bitmap]
single=chinese.fnt
glyphs=13053

[fonts]
default=fonts/wqy-bitmapsong.ttf

[sizes]
default=16

[translation]
file=chinese.trs

[map]
height_8=default
```

### 중국어 간체

```ini
[encoding]
codepage=gbk

[bitmap]
multi=chinese%02d.fnt
glyphs=6763         ; GB 2312

[fonts]
default=fonts/wqy-zenhei.ttf

[sizes]
default=16
```

### 진입 조건

한국어(`KO_KOR`)는 예전처럼 언어만으로 이 경로에 들어옵니다. 다른 CJK
언어는 **맵 파일이 있어야** 들어옵니다:

- `korean_ttf_map` 설정이 있거나
- 게임 폴더에 `korean_ttf.map` 이 있거나

이렇게 한 이유는 일본어·중국어 정식 릴리스가 이미 엔진의 자체 CJK 모드로
잘 나오기 때문입니다. 맵을 두지 않으면 종전 동작 그대로입니다.

지원 언어는 `KO_KOR`, `JA_JPN`, `ZH_CHN`, `ZH_TWN` 네 가지이고, 엔진은
v0~v6 (그리고 Full Throttle) 입니다.

---

## 9. v0~v2 제약

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

## 10. 검증 방법

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

## 11. 알려진 제약

- **32bit 알파는 OpenGL 전용.** SurfaceSDL 백엔드는 지원 포맷이 모두
  2바이트 이하라 `korean_alpha_text=true`가 무시됩니다.
- **`INIFile::getKeys()` 널 역참조** — ScummVM 본체 버그입니다. 없는
  섹션을 조회하면 `getSection()`이 `nullptr`을 주는데 그대로 역참조합니다.
  우리 쪽은 `hasSection()` 선검사로 회피합니다.
- **인트로는 텍스트가 없습니다.** 타이틀 화면에서 대기하므로 Escape를
  몇 번 보내야(`"Escape@20,Escape@28"`) 대사가 나옵니다.
- `[latin] enabled=true`는 문장부호 위치가 어긋납니다. 전진폭은 게임
  비트맵, 글리프는 TTF 메트릭이라 근본적으로 충돌합니다.
