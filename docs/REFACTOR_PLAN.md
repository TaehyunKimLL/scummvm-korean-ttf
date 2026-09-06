# SCUMM CJK 텍스트 경로 리팩토링 방안 (한국어 + 일본어 + 중국어)

측정일: 2026-09-05, 기준 커밋 `c073bf93` (fork/hires-text-i18n)

## 0. 전제: upstream 기여가 최종 목표

이 전제가 아래 모든 판단의 기준이다. 확인한 사실:

- `origin` = github.com/scummvm/scummvm 이 이미 등록돼 있고,
  `origin/master`(`2c542815`) 대비 **우리 커밋 41개**가 앞서 있다.
- upstream이 앞선 커밋은 **0개** — 아직 리베이스 부채가 없다. 지금이
  정리하기 가장 싼 시점이다.
- 변경 규모: `engines/scumm` 12파일, **+2647 / -93**.
  charset.cpp 28회, scumm.h 20회, gfx.cpp 14회 수정.
- `CONTRIBUTING.md`: 코딩 스타일 / 이식성 / 커밋 메시지 규약 / GPLv3+.

### 즉시 고쳐야 할 것 (리팩토링과 무관)

**~~`encoding.dat` 179KB 바이너리가 커밋 `4ff470d3`에 섞여 들어갔다.~~
→ 2026-09-05 제거 완료.**

`dists/engine-data/encoding.dat`의 바이트 동일 중복본이며, 런타임 테스트
편의로 리포지토리 루트에 복사한 것이 실수로 커밋됐다. upstream PR에서는
즉시 거절 사유였다.

처리 내역:

```sh
git branch -f backup/pre-encdat-c073bf93 HEAD      # 안전장치
cp encoding.dat /tmp/encoding.dat.keep             # 런타임 사본 보존
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f \
  --index-filter 'git rm --cached --ignore-unmatch -q encoding.dat' \
  --prune-empty -- origin/master..HEAD
git push --force-with-lease=refs/heads/hires-text-i18n:c073bf93 \
  fork hires-text-i18n
```

검증 결과:

| 항목 | 결과 |
|---|---|
| 작업 브랜치 히스토리의 `encoding.dat` | 0 커밋 |
| 백업 브랜치와의 diff | `encoding.dat` **단 1개** — 소스 무변경 |
| 커밋 수 | 41 → 41 (보존) |
| `dists/engine-data/encoding.dat` | 유지 |
| 빌드 | EXIT=0, 에러 0 |
| 런타임 (`--detect` 한국어 타깃) | 정상 |
| 원격 `fork/hires-text-i18n` | `c073bf93` → `5ed2bfd6` |

재발 방지: `.git/info/exclude`에 `/encoding.dat` 추가. `.gitignore`가
아닌 이유는 그 파일이 upstream과 동일해야 PR에 불필요한 diff가 안 생기기
때문이다. 로컬 런타임 사본은 복원해 두었고 git 이 무시함을 확인했다.

**주의**: 히스토리가 재작성되었으므로 이 브랜치의 다른 체크아웃이 있다면
`git reset --hard fork/hires-text-i18n` 로 맞춰야 한다. 백업 브랜치
`backup/pre-encdat-c073bf93` 는 단계 0(히스토리 재구성)까지 끝난 뒤 지운다.

### upstream 관점에서 41개 커밋의 문제

지금 히스토리는 **개발 과정의 기록**이지 리뷰용 시리즈가 아니다.
`769a66b1`(advance 도입) → `bda1618d`(wrapping에도 적용) →
`2200a7aa`(비트맵도 advance) → `c073bf93`(advance 불일치 수정) 처럼
같은 주제를 네 번에 걸쳐 고친다. 리뷰어는 최종 상태만 보면 되는데
중간 상태를 다 읽어야 한다.

**즉, 리팩토링과 별개로 "히스토리 재구성"이 반드시 필요하다.**
그리고 이 둘은 순서가 있다: **재구성이 먼저다.** 리팩토링을 먼저 하면
재구성 대상이 그만큼 늘어난다.

---

## 1. 범위 재정의

앞선 초안은 우리 한국어 hi-res 코드(분기 78개)만 봤다. 사용자 지시에 따라
**upstream CJK 전체**로 범위를 넓혀 다시 측정했다.

| 대상 | 심볼 출현 | 조건 분기 |
|---|---|---|
| 우리 한국어 hi-res | 356줄 / 14파일 | 78 |
| **upstream CJK 포함 전체** | **약 660줄 / 25파일** | **274** |

upstream CJK 심볼 상위:

| 심볼 | 출현 |
|---|---|
| `kPlatformFMTowns` | 162 |
| `_useCJKMode` | 70 |
| `kPlatformSegaCD` | 62 |
| `_2byteWidth` / `_2byteHeight` | 44 / 44 |
| `_townsScreen` | 41 |
| `_2byteMulti*` | 39 |
| `_cjkFont` | 31 |
| `kPlatformPCEngine` | 30 |
| `_isIndy4Jap` | 19 |

분기 274개의 분포: charset.cpp 77, gfx_gui.cpp 44, string.cpp 28,
script_v5.cpp 27, gfx.cpp 26, 나머지 파일들 72.

## 2. 지금 존재하는 CJK "모드" 전수

`loadCJKFont()` (charset.cpp:108) 한 함수 안에 서로 다른 폰트 체계가
if/else if 사슬로 들어 있다. 이것이 문제의 중심이다.

| # | 조건 | 글리프 출처 | 셀(W×H) | textScale | newLine |
|---|---|---|---|---|---|
| 1 | Rebel1 + SegaCD | SMUSH 자막 폰트 | — | 1 | — |
| 2 | `isHiResTextTarget()` (우리) | .fnt / SVFN / TTF | 맵/헤더 | 1~3 | 0xFE |
| 3 | v≤5 + FMTowns + JA | **FMT_FNT.ROM** (FontSJIS) | ROM | **2** | 0 |
| 4 | Loom + PCEngine + JA | **pce.cdbios** (FontSJIS) | 12×12 | 1 | 0 |
| 5 | MI1 SegaCD JA / Indy4 JA | 게임 리소스(지연 로드) | 16×16 | 1 | 0x5F |
| 6 | KO_KOR | korean.fnt | 헤더에서 읽음 | 1 | 0xFE/0xFF |
| 7 | v≥7 JA | japanese.fnt / kanji16 | 16×16 | 1 | 0xFE |
| 8 | v≥7 ZH_TWN | chinese.fnt | 16×15 | 1 | 0x21 |
| 9 | v≥3 ZH_CHN | chinese_gb16x12.fnt | 12×12 | 1 | 0x21 |

여기에 렌더러 계층이 직교로 얹힌다: `CharsetRendererV3` / `Classic` /
`TownsV3` / `TownsClassic` / `PCE` / `Mac` / `NUT` / `V7`.

**모드 9종 × 렌더러 8종**이 암묵적으로 곱해지는 구조다. 분기 274개는
이 곱을 코드 곳곳에서 손으로 다시 푸는 데서 나온다.

## 3. 진단 — 원인은 분기 개수가 아니다

이번 세션에서 잡은 버그 5건은 전부 "같은 개념을 두 곳에서 다르게 계산"이었다.
CJK 전체로 넓혀 보면 같은 패턴이 upstream에도 있다.

**(a) 대용 변수 — `_textSurfaceMultiplier`가 3가지를 뜻함**

- "텍스트 서피스가 몇 배인가" (모드 2, 3)
- "FM-Towns 640×480 모드인가" (모드 3에서만 2)
- "배너 vs 버퍼가 2배 폭인가" ← `drawPixel()`이 이렇게 읽어서 **힙 오버런**

모드 3(FM-Towns 일본어)과 모드 2(우리 hi-res)가 같은 변수를 다른 의미로
쓰기 때문에, 한쪽을 고치면 다른 쪽이 깨진다. `0548aacc`가 그 사례다.

**(b) advance 계약이 렌더러마다 제각각**

같은 "2바이트 문자 폭"을 네 곳이 다르게 답한다:

| 위치 | 2바이트 답 |
|---|---|
| `Classic::getCharWidth` | `_2byteWidth / 2` |
| `V3::getCharWidth` | `_2byteWidth / 2` |
| `TownsClassic::getCharWidth` | `8` (+게임별 보정) |
| `getStringWidth` (KO/ZH_TWN) | `_2byteWidth + 1` |
| `V3::printChar` (수정 전) | `_2byteWidth` |

`c073bf93`이 마지막 두 줄의 불일치였다. 나머지 조합도 같은 위험을 안고 있다.

**(c) 인코딩 판정이 복사돼 있음**

`is2ByteCharacter()`가 `charset.h:60`과 `string_v7.h:47`에 **글자 그대로
중복**되어 있다. 한쪽만 고치면 조용히 갈라진다. 별도로 `checkSJISCode()`가
4곳에서 쓰인다.

**(d) 좌표계가 암묵적** — 게임(320) / 화면(320×scale) / 방(+xstart)이
같은 `int`로 섞인다. MI2 다리 버그, 마우스 3배 버그가 여기서 나왔다.

## 4. 제안하신 설계에 대한 판단

### 함수 포인터 + `#define` 래핑 — 권하지 않음

- 렌더러 vtable이 **이미** 있다. fp 테이블을 병렬로 두면 디스패치가 이중화돼
  "이 글리프를 실제로 그린 코드"를 찾기가 더 어려워진다.
- `#define`으로 감싸면 GDB에서 심볼이 사라진다. 이번 진단의 결정타가
  브레이크포인트 + `_textSurface` 덤프였는데 그 능력을 잃는다.
- upstream 리베이스가 사실상 불가능해진다. FM-Towns/PCE/SegaCD 코드는
  upstream이 계속 고치는 영역이라 특히 위험하다.

### 상속 확장 — 부분적으로만

한국어 로직이 V3와 Classic **양쪽**에 필요해서 `CharsetRendererKorHiRes`를
새로 파면 다중상속이나 코드 중복이 된다. 렌더러 계층은 그대로 두고,
**모드 데이터를 렌더러 밖으로 빼는** 방향이 맞다.

### "초기화에서 전부 확정" — 정확한 지적

원인 (a)와 (d)가 정확히 이걸로 사라진다. 다만 *함수 바인딩*이 아니라
**값·정책의 단일 출처**다. 아래 A단계가 그것이다.

## 5. 방안 — `CJKTextMode` 하나로 9개 모드를 서술

### 단계 A: 모드 서술 구조체 (핵심)

`loadCJKFont()`의 if/else if 사슬을 **표를 채우는 코드**로 바꾼다.
채우고 나면 이후 모든 코드는 묻지 않고 읽기만 한다.

```cpp
struct CJKTextMode {
    // --- 정체 ---
    enum GlyphSource { kNone, kSystemRom, kGameResource, kBitmapFnt,
                       kSvfnBitmap, kTrueType };
    GlyphSource source   = kNone;
    Common::Language lang = Common::UNK_LANG;
    Common::CodePage codePage = Common::kCodePageInvalid;

    // --- 배율: 용도별로 분리한다. 이게 (a) 해결 ---
    int  textScale     = 1;   // 텍스트 서피스 배율
    int  outputScale   = 1;   // 백엔드 화면 배율
    int  cursorScale   = 1;   // 커서 확대율
    bool bannerIsWide  = false; // 배너 vs 가 2배 폭으로 할당됐나

    // --- 셀 기하 ---
    int  cellW = 0, cellH = 0;   // 글리프 박스 (구 _2byteWidth/_2byteHeight)
    int  advance2byte = 0;       // 2바이트 진행폭 — (b) 해결
    int  advance1byte = -1;      // -1 = 게임 폭 테이블 사용
    int  sideBearing  = 0;       // KO/ZH_TWN 의 +1

    // --- 동작 ---
    byte newLineChar  = 0;
    bool shadow       = false;
    bool alphaText    = false;   // 32bpp 커버리지 합성
    bool latinThroughFont = false;
    bool metricsFromFont  = false;
};
```

**(b) 해결의 핵심**: `advance2byte`를 여기서 확정한다. `getCharWidth()`,
`getStringWidth()`, `printChar()`가 전부 이 값을 읽는다. 서로 다른 답이
나올 수 없다.

**(a) 해결의 핵심**: `drawPixel()`은 `_textSurfaceMultiplier == 2` 대신
`mode.bannerIsWide`를 본다. FM-Towns 일본어와 우리 hi-res가 같은 변수를
다투지 않는다.

기존 멤버는 별칭으로 남긴다 (`_2byteWidth` → `_cjk.cellW`). upstream
코드를 한 번에 다 고치지 않아도 되고, 단계적으로 옮길 수 있다.

**검증**: `loadCJKFont()` 끝에 모드 전체를 찍는 로그를 넣고, 아래 12개
조합에서 표를 뜬다. 리팩토링 전후 표가 같으면 동작도 같다.

| 확인 대상 | 모드 |
|---|---|
| MM/Zak 한국어 1x·2x·3x | 2 |
| Indy3/Indy4 한국어 3x | 2 |
| MI1/MI2 한국어 3x | 2 |
| Loom DOS CD 한국어 | 2 |
| **Loom FM-Towns 한국어** | 2 (mult=1 확인됨) |
| **Loom FM-Towns 일본어** | **3** (mult=2) |
| **Loom PC-Engine 일본어** | **4** |
| **MI1 SegaCD 일본어 / Indy4 일본어** | **5** |
| Dig/COMI 일본어·중국어 | 7/8 |

일본어 데이터는 `~/Loom (Multi-Platform).zip` 에 FM-Towns·TG16 이 있고,
`/tmp/ScummVM-Kor-Trs` 에 한국어 번역이 있다. 모드 3·4를 **실제로 돌려서**
확인할 수 있다 — 이번에 FM-Towns 한국어로 이미 해봤다.

### 단계 B: 인코딩 판정 일원화

`is2ByteCharacter()` 중복 2곳 + `checkSJISCode()` 를 하나로 모은다.

```cpp
// engines/scumm/cjk.h
bool isLeadByte(const CJKTextMode &m, byte c);
uint16 makeCodePoint(const CJKTextMode &m, byte hi, byte lo);
```

`string_v7.h` 의 사본을 지우고 이걸 부른다. 위험 낮음, 이득 확실.

### 단계 C: advance 단일 진입점

```cpp
int ScummEngine::charAdvance(uint16 chr, const CharsetRenderer *cr) const;
```

- `getStringWidth()`는 이 함수를 더하기만 한다.
- `printChar()`는 이만큼 `_left`를 옮긴다.
- FM-Towns/PCE 의 특수 폭(8, +1, `_curId==2`)도 이 안에 흡수한다.

**검증**: GDB 덤프 A/B (`~/games/tsdump.sh`). 리팩토링 전후 13개 대사
지점의 잉크 열 수·덩어리 수·시작 간격이 **완전히 동일**해야 한다.
이번에 통한 방법이고, 일본어 모드에도 그대로 쓸 수 있다.

### 단계 D: 좌표 변환 봉인

```cpp
Common::Point toTextSurface(int gameX, int gameY) const;
Common::Point toGameFromBackend(int bx, int by) const;
Common::Rect  textSurfaceBand(const VirtScreen *vs) const;
```

`* _textSurfaceMultiplier` 가 흩어진 115곳 중 좌표 계산인 것을 이 셋으로
바꾼다. FM-Towns 경로도 같은 함수를 쓰게 되어 두 모드가 통일된다.

### 단계 E: 파일 분해 (로직 변경 없음)

- `charset_cjk_font.cpp` — 모드 판정/폰트 로딩/SVFN/맵 파싱
- `charset_cjk_draw.cpp` — 글리프 렌더 (TTF/SVFN/비트맵/FontSJIS)
- `charset.cpp` — upstream 원본에 가깝게 유지

### 단계 F: 출력 대상(프레임버퍼) 추상화 — 가치 큼, 위험도 높음

측정: 출력/버퍼 심볼 **약 480줄 / 12파일**.
`_textSurface` 146, `_virtscr` 142, `_macScreen` 53, `_townsScreen` 48,
`_korAlphaSurface` 33, `copyRectToScreen` 32, `_compositeBuf` 24.

`drawStripToScreen()` 한 함수가 **204줄**이고 그 안에 출력 경로가 6갈래다:

| 경로 | 조건 | 목적지 | 텍스트 합성 방식 |
|---|---|---|---|
| Mac v≤3 | `_macScreen && version<=3` | `_macScreen` | `_textSurface` 2배 좌표 |
| Mac v>3 | `_macScreen && version>3` | `mac_drawBufferToScreen` | 이미 합성된 버퍼 |
| FM-Towns | `kPlatformFMTowns` | `TownsScreen` 레이어 1 | 레이어 합성기가 처리 |
| 한국어 hi-res | `isKoreanHiRes()` | `_compositeBuf` | `compositeHiResText()` |
| NES | `kPlatformNES` | 백엔드 직접 | 스트립 보정 |
| 기본 | — | `_compositeBuf` | 컬러키 8/16bpp 루프 |

**세 경로를 나란히 읽으면 같은 일을 한다는 게 드러난다:**

```
mac_drawStripToScreen : vs->getPixels(x,top) + _textSurface(x*2, y*2)      -> _macScreen
towns_drawStripToScreen: vs->getPixels(srcX,srcY) + _textSurface(srcX*m, ..*m) -> TownsScreen layer
compositeHiResText     : src                  + _textSurface(x*m, y*m)      -> _compositeBuf
```

전부 **"게임 픽셀 + 배율 보정된 텍스트 서피스 → 목적지"** 다. 목적지와
배율만 다르다. 그런데 배율 보정이 세 곳에 각각 적혀 있어서, 우리가 3배를
도입했을 때 한 곳만 고치면 나머지가 조용히 어긋났다.

**이미 절반은 추상화되어 있다.** `TownsScreen`(gfx.h:563)이 레이어 합성기다:
`setupLayer(layer, w, h, scaleW, scaleH, numCol, pal)`, `getLayerPixels()`,
`addDirtyRect()`, `update()`. 즉 upstream이 FM-Towns 한 곳에만 적용한
개념을 전체로 넓히는 것이 이 단계다.

```cpp
// 게임 그래픽 레이어 + 텍스트 레이어를 받아 백엔드로 내보내는 대상
class ScummOutput {
public:
    virtual ~ScummOutput() {}
    // 게임 픽셀 스트립 하나를 텍스트 레이어와 합성해 출력
    virtual void blitStrip(const VirtScreen *vs, int x, int y,
                           int width, int height) = 0;
    virtual void setPalette(const byte *pal, int first, int num) = 0;
    virtual void updateScreen() = 0;
    // 텍스트 레이어의 기하 — 지금 흩어진 * m 을 여기로 모은다
    virtual int  textScale() const = 0;
    virtual Graphics::Surface &textSurface() = 0;
};

class PlainOutput   : public ScummOutput;  // 기본 CLUT8/16bpp
class ScaledOutput  : public ScummOutput;  // 한국어 hi-res (+ 알파)
class TownsOutput   : public ScummOutput;  // TownsScreen 위임
class MacOutput     : public ScummOutput;  // _macScreen
class NESOutput     : public ScummOutput;  // 스트립 보정
```

`drawStripToScreen()`은 전처리(EGA 디더/CGA 후처리/정렬)만 남기고
합성·출력은 `_output->blitStrip()` 한 줄로 위임한다. 204줄이 40줄쯤 된다.

**이 단계가 막았을 버그**
- 배너 힙 오버런: 배너 폭 판정이 `TownsOutput`에만 있었을 것.
- 커서 미배율: `cursorScale`이 output에 속하므로 v2 경로도 자동 적용.
- MI2 다리 대사 실종: 좌표 변환이 output 한 곳뿐이라 `xstart` 혼동 불가.

**하지만 위험도가 가장 높다.** 이유:
1. `drawStripToScreen`은 **모든 게임의 모든 프레임**이 지나간다. 회귀
   범위가 CJK가 아니라 SCUMM 전체(v0~v8, HE 포함)다.
2. `_compositeBuf`는 스크롤·전환효과·커서가 공유한다
   (`scroll-palette-regression.md` 참조). 소유권을 output으로 옮기면
   그 경로도 같이 봐야 한다.
3. HE 엔진(`heversion>=60`)이 별도 규칙으로 이 버퍼를 쓴다.
4. ARM/M68K 어셈블리 최적화 경로(`asmDrawStripToScreen`)가 있다.

따라서 **F는 마지막에, 그리고 두 조각으로 나눠서** 한다.

- **F1 (저위험)**: `blitStrip()` 인터페이스만 만들고 **기본 경로 하나만**
  옮긴다. Towns/Mac/NES는 기존 함수를 그대로 호출하는 얇은 래퍼로 둔다.
  → 구조는 생기고 동작은 안 바뀐다.
- **F2 (고위험)**: 한국어 hi-res와 Towns를 실제 `ScummOutput` 구현으로
  이관. 이때 `textScale()`이 단일 출처가 되어 `* m` 중복이 사라진다.
- **F3 (선택)**: Mac/NES 이관. upstream 병합을 노린다면 보류 권장.

## 6. 순서와 위험도

upstream 기여가 목표이므로 **히스토리 재구성(단계 0)이 맨 앞**이다.

권장: **0 → B → A → E → F1 → D → C → (F2)**

| 단계 | 내용 | 위험 | 검증 | upstream 제출 |
|---|---|---|---|---|
| **0** | encoding.dat 제거 + 41커밋 재구성 | 낮음 | 빌드 + 회귀 | — (준비) |
| B | 인코딩 판정 통합 | 낮음 | 빌드 + 회귀 캡처 | **PR 1 후보** |
| A | CJKTextMode 도입 | 중간 | 12조합 모드 표 대조 | PR 3 |
| E | 파일 분해 | 낮음 | 빌드 + 회귀 캡처 | PR 3에 포함 |
| F1 | ScummOutput 인터페이스 + 기본 경로 | 낮음 | 전 게임 회귀 캡처 | 별도 PR |
| D | 좌표 변환 3함수 | 중간 | 회귀 + 클릭 프로브 | PR 3 |
| C | advance 일원화 | 높음 | GDB 덤프 A/B | PR 3 |
| F2 | hi-res·Towns output 이관 | 가장 높음 | 전 게임 + GDB 덤프 | **보류** |

### 단계 0: 히스토리 재구성 (리팩토링보다 먼저)
41개 커밋을 주제별로 묶어 리뷰 가능한 시리즈로 만든다.

1. `encoding.dat` 를 히스토리에서 제거.
2. 같은 주제의 수정을 원 커밋에 squash.
   예: advance 관련 4개(`769a66b1` `bda1618d` `2200a7aa` `c073bf93`)를
   하나로. 커서 관련 4개(`a8f6c85d` `00e67e56` `220cd59d` `2d4bfd76`)도
   묶는다.
3. 목표 형태 (대략 8~12 커밋):
   - hi-res 텍스트 모드 기반 (surface, 합성, 스케일)
   - CJK 비트맵 폰트 로딩 + 폰트 맵
   - TrueType 렌더링
   - SVFN 확장 비트맵 포맷
   - alpha 합성
   - advance/metrics
   - 커서 스케일
   - 입력 좌표 변환

**주의**: 재구성 후 각 커밋에서 빌드가 되는지 확인해야 한다
(`git rebase --exec 'make -j32'`). upstream은 bisect 가능성을 요구한다.

### upstream 제출 전략

한 번에 41커밋 + 2647줄 PR을 던지면 리뷰가 불가능하다. 쪼갠다.

- **PR 1 (선행, 독립)**: 단계 B — `is2ByteCharacter()` 중복 제거.
  우리 기능과 무관한 순수 정리라 단독으로 받아들여질 가능성이 높고,
  리뷰어와 관계를 트는 용도로도 좋다.
- **PR 2 (버그 수정만)**: 이번 세션에서 잡은 것 중 **upstream에도 있는**
  버그. 예: `drawPixel()` 배너 힙 오버런은 FM-Towns 조건에서도 이론상
  발생 가능한지 확인 후 분리 제출.
- **PR 3 (본체)**: hi-res CJK 텍스트 기능. 단계 0 재구성 결과를 그대로
  올린다. 사전에 메일링 리스트(scummvm-devel)에 설계 의도를 알리고
  피드백을 받는 것이 관례다.
- **F2는 보류**: `drawStripToScreen` 재구조화는 SCUMM 전체에 영향을
  주므로 우리 기능 PR과 섞으면 둘 다 막힌다. PR 3이 병합된 뒤 별도
  주제로 제안한다.

### upstream 관례상 반드시 지킬 것

- 커밋 제목: `SCUMM: <동사로 시작하는 명령문>` (이미 지키고 있음).
- 코딩 스타일: 탭 들여쓰기, `_camelCase` 멤버 (지키고 있음).
- **이식성**: `#ifdef USE_FREETYPE2` 없는 빌드에서도 컴파일/동작해야
  한다. SVFN 경로가 이미 그 대비다 — 회귀 스위트에 no-FreeType 빌드
  (`~/src/scummvm-noft`)를 반드시 포함한다.
- 기존 플랫폼(FM-Towns/PCE/SegaCD/Mac) 동작 불변 증명이 필요하다.
  단계 A의 12조합 모드 표가 그 증거가 된다.

## 7. 하지 말아야 할 것

- **한 번에 전부.** 모드 9종 × 렌더러 8종 조합이라 회귀 없이 큰 변경을
  하면 어느 조합이 깨졌는지 못 찾는다.
- **upstream 함수 시그니처 변경.** FM-Towns/PCE/SegaCD 는 upstream이
  활발히 고치는 영역이다.
- **`#define` 래핑.** GDB 진단 능력 상실.
- **분기 개수를 목표로 삼기.** 274 → 150 이 되어도 대용 변수가 남으면
  같은 버그가 또 난다.

## 8. 선행 조건 — 회귀 안전망

지금은 캡처가 수동이다. **B 이후, A 이전에** 갖춘다.

1. `~/games/regress.sh` — 한국어 8타깃 + **일본어 모드 3·4·5** 고정
   지점 캡처 후 기준 해시 대조.
2. GDB 덤프 기준선 — Loom FM-Towns 한국어 13지점 `.bin` 보관 (이미 있음:
   `/tmp/TSPRE`, `/tmp/TSFIX`). 일본어도 같은 방식으로 확보.
3. 프로브 3종을 스위트에 포함: `banprobe.sh`(배너 크래시),
   `curstripe.sh`(커서), 클릭 좌표 프로브.

**이 안전망 없이 C단계에 들어가면 안 된다.**

## 9. 열려 있는 결정 사항

1. ~~upstream 기여 목표인가?~~ **확정: 목표다.** 단계 0(히스토리 재구성)이
   선행되고, A는 별칭 전략을 쓰며, F2/F3는 본체 PR 병합 후로 미룬다.
2. **일본어 게임 데이터 확보 범위** — Loom FM-Towns/TG16 은 있다. Indy4 JA,
   MI1 SegaCD JA 는 없다. 모드 5는 정적 분석만 가능하다.
   upstream 제출 시 "미검증 플랫폼"을 PR 본문에 명시해야 한다.
3. **모드 1(Rebel1 SegaCD)** 은 SMUSH 경로라 이 구조에 넣을지 별도 판단
   필요.
4. **메일링 리스트 사전 논의 시점** — 단계 0 완료 후, A 착수 전이 적절.
   설계를 바꾸라는 피드백이 오면 A~F 계획 자체가 달라진다.

## 10. 다음 행동

바로 시작할 수 있는 것, 위험 낮은 순:

1. **`encoding.dat` 히스토리 제거** — 단독으로 가능, 즉시.
2. **회귀 안전망 구축** (`regress.sh` + no-FreeType 빌드 포함).
   단계 0의 재구성이 동작을 안 깼는지 증명하려면 이게 먼저 있어야 한다.
3. **단계 0 히스토리 재구성** — 41 → 8~12 커밋.
4. 단계 B 착수 및 PR 1 제출.
