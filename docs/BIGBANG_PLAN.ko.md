# 빅뱅 브랜치: 무엇을, 어떤 순서로 바꾸며, 무엇이 그것을 증명하는가

> **상태 2026-09-26: §2 A(브랜치 전략)는 대체되었다.** 작업은 `hires-text`에서
> 이어지지 않았다. upstream/master에서 새 라인 `i18n`을 잘랐고(`i18n/TREES.md`),
> `hires-text`는 그 안으로 병합(`91cffbd25a`)된 뒤 기록용으로 동결되었다. 엔진
> 순서(§4)와 증명(§6)은 `i18n` 위에서 그대로 유효하다.

구현이 아니라 브랜치 계획을 요구하는 카드 B0(`t_7a5dbbf2`)를 위해 썼다. 어느
브랜치에서, 어떤 순서로, 무엇을 증명하는가. 엔진은 `943cda2bcff`(브랜치
`hires-text`) 기준으로 읽었고, upstream은 `c81c8695a44`, 포크 베이스는
`41ac2b31847`이다. 하네스는 하네스 저장소의 `harness/b0*.py`, 캡처는
`captures/2026-09-16/b0/` 아래에 있다. 줄 번호는 그 커밋에서만 유효하다 — 네
도구는 각자 자신의 전사를 다시 확인하며, 옮겨진 줄을 측정하는 대신 실패한다.

**이 카드는 엔진 코드를 전혀 바꾸지 않는다.** `b0dbcs.py`가 실제로 문다는 것을
증명하기 위해 `engines/saga/font.cpp`에 프로브 하나를 주입했다가 같은 턴에
되돌렸다. §7이 트리가 깨끗함을 보인다.

주장은 세 종류 중 하나이며, 어느 것인지 명시한다:

- **[source]** — 엔진의 file:line. 정적 도달 가능성만.
- **[measured]** — 이 카드가 무언가를 실행해서 만들어낸 수치.
- **[unmeasured]** — 하중을 받는데도 아무도 확인하지 않았기에 명시한다.

---

## 짧은 답

| | 질문 | 답 |
|---|---|---|
| **A** | 브랜치 전략 | **upstream이 아니라 `hires-text`에서 브랜치를 딴다.** `hires-text`는 *오늘* 240개 커밋에 걸쳐 충돌 0으로 upstream/master에 깨끗하게 머지된다 **[measured]**. 따라서 upstream에서 다시 시작할 통상적인 이유가 적용되지 않는다. `hires-text`는 사용자의 테스트 빌드로 유지한다. 빅뱅 작업은 머지를 통해, 머지 한 번에 한 단계씩 그 위에 올라온다. |
| **B** | 세 가지 추상화 | **셋 중 하나는 정당화되고, 하나는 제 이름보다 작은 형태로만 정당화되며, 하나는 전혀 정당화되지 않는다.** `Font`/`FontSet`은 정당화된다 — 5개 엔진이 리드바이트 판정을 사적으로 들고 있고, 4개 엔진이 페어 조립을 사적으로 들고 있다 **[measured]**. "Hires Hicolor Surface"는 **아니다** — 두 서피스는 한 클래스가 둘 다 감당하게 해줄 네 속성 전부에서 불일치하고, 둘 다 하이컬러도 아니다 **[measured]**. `String`도 **아니다** — 바이트 배열은 게임 자신의 리소스 포맷이지 포팅 지름길이 아니다. |
| **C** | 엔진 순서 | **SCI 먼저, 그다음 SCUMM, 그다음 queen, 그다음 touche. kyra, saga, sword1, agos, agi는 첫 브랜치에서 빠진다.** SCI는 *호출자*가 페어를 조립하는 유일한 엔진이며, 그래서 추상화의 형태가 가정이 아니라 diff에 드러나는 유일한 엔진이다. |
| **D** | A1의 다섯 단계와의 관계 | **포함하되 대체하지 않는다.** A1의 1–4단계가 여기서는 B1/B2이며, 변경 없이 여전히 먼저다. A1의 5단계(줄 렌더 컨텍스트)는 이 브랜치에 **없다** — 그것을 정당화할 측정이 들어와 있지 않다. |
| **E** | 안전성의 증명 | **티어는 셋이고, 최상위 티어에 닿을 수 있는 엔진은 셋뿐이다.** 9개 중 3개는 여기서 캡처로 증명 가능하고, 9개 중 1개는 엔진 없이 직접 프로브로 증명 가능하다. 나머지 5개는 컴파일과 F1 글리프 덤프와 서술된 논증을 받으며, 계획은 아닌 척하는 대신 그렇다고 말한다 **[measured]**. |

그리고 카드의 프레이밍을 가장 크게 바꾸는 발견:

**부모 세션의 엔진별 표는 양쪽 방향 모두로 틀렸고, 그 정정은 브랜치를 좁힌다.**
그 표는 `Common::KO_KOR` 식의 언어 분기를 셌고(이는 과소 계수다: saga와
sword1은 언어 enum이 아니라 *폰트 파일*에 게이트된 완전한 한국어 경로를 들고
있어서, enum을 키로 한 센서스는 이들을 0으로 보고한다), 바이트 수준 텍스트
조작을 셌다(이는 과대 계수다: 대부분은 opcode 디스패치와 파일명 처리다). 대신
텍스트 경로가 반드시 해야 하는 다섯 가지 *작업*을 세면 모집단은 45개 셀이 되고,
그중 **4개 엔진은 2바이트 작업을 전혀 하지 않으며** 고칠 수 없고 오직 *준비*만
시킬 수 있다 **[measured]**, §1.

---

## 1. 모집단 재집계: 하나의 숫자가 아니라 다섯 가지 작업

`harness/b0dbcs.py`가 바이트 조작 카운트를 대체한다. 한 바이트보다 넓은 문자를
처리해야 하는 텍스트 경로는 다섯 가지 질문에 답해야 하며, 엔진이 그 질문에 스스로
답할 때 그 작업의 "사적 사본을 가진다"고 한다:

```
LEAD    decide whether a byte starts a two-byte character
PAIR    assemble the two bytes into one value
WIDTH   answer how wide that value is
DRAW    draw it
WRAP    decide where a line may break
```

**[measured]** (`captures/2026-09-16/b0/b0-dbcs.txt`):

```
engine       LEAD     PAIR    WIDTH     DRAW     WRAP
scumm         own      own      own      own      own
sci           own   caller      own      own      own
kyra          own      own      own      own      own
agi          none     none    fixed      own      own
agos         none     none      own      own      own
saga          own      own      own      own      own
queen        none     none      own      own      own
sword1        own      own      own      own      own
touche       none     none      own      own      own

own             5        4        8        9        9
none            4        4        0        0        0
```

이 검사는 두 번 물며, 각각을 실제로 보였다:

1. **성향이 지정되지 않은 엔진.** 모집단에 `sword2`를 추가하면
   `*** UNACCOUNTED *** engine sword2 has no disposition`을 보고하고 1로 종료한다
   (`b0dbcs-bite1.txt`). 그러므로 나중에 누군가 브랜치에 엔진을 추가해도 조용히
   표에 낄 수 없다.
2. **옮겨진 소스 줄.** `DefaultFont::getStringWidth`에 빈 줄 하나를 넣으면 saga에
   대해 `*** MOVED ***`를 **두 줄** 보고하고 1로 종료한다(`b0dbcs-bite2.txt`).
   깨끗한 트리는 전사 37건을 확인하고 0으로 종료한다.

### 1.1 그 표가 말하고 카운트는 말하지 못한 것

**네 엔진은 2바이트 경로가 아예 없다** — agi, agos, queen, touche. 이들에게는
"정리할" 것이 없고 *추가할* 일만 있다. 이것이 카드의 전제에 대한 가장 큰 정정이다.
아홉 곳의 비슷한 코드를 정돈하는 일로 이 브랜치를 설명할 수 없다. 아홉 중 넷에서는
그 코드가 존재하지 않기 때문이다.

**두 엔진은 enum을 키로 한 센서스에 보이지 않았다.** saga의 `getStringWidth`는
2바이트 분기를 `isCJK = _chineseFont || _koreanFont`
(`engines/saga/font.cpp:517`)에 게이트하고 **[source]** — 언어가 아니라 *폰트
객체*다 — sword1은 한국어 `.clu`의 존재에 게이트한다
(`engines/sword1/resman.cpp:146`) **[source]**. 둘 다 완전한 한국어 렌더링을
들고 있다. `Common::KO_KOR`를 키로 한 센서스는 둘 다 0으로 보고하는데, 부모
세션의 표가 한 일이 정확히 그것이다.

**한 엔진은 추상화의 이름이 가리키는 바로 그 결함을 갖고 있다.** SCI는 PAIR 열에서
유일한 `caller`다. 호출자가 바이트를 읽고, 폰트에 `isDoubleByte()`를 묻고, 그런
다음 폰트의 산술을 스스로 한다(`engines/sci/graphics/text16.cpp:216`)
**[source]**. 다른 모든 엔진은 최소한 조립을 폰트를 소유한 레이어 안에 둔다.

**그리고 한 엔진은 같은 작업을 두 번 들고 있다.** kyra의 `Screen::fetchChar`
(`engines/kyra/graphics/screen.cpp:1668`, `:1671`)는 *현재 폰트의 타입*에 대고
페어를 조립하고, `TextDisplayer::getCharLength`
(`engines/kyra/text/text.cpp:64`)는 `fetchChar`를 호출하는 대신 자신의
`JA_JPN || KO_KOR` 판정으로 다시 조립한다 **[source]**. 한 엔진 안에서 한 질문에
두 개의 답이 있다는 것은 S4↔S7과 같은 형태 — 이 브랜치 전체가 대응하려는 그
결함 — 이며, 여기 누구도 손대지 않은 엔진에 이미 존재한다.

### 1.2 그래서 코드는 "비슷한가"?

부분적으로 그렇고, 그 갈라짐이 시사적이다. **LEAD 작업은 진짜로 중복이다**: I1은
`0xB0..0xC8 && 0xA1..0xFE` 술어의 바이트 단위로 동일한 사본 다섯 개와 리드바이트만
보는 사본 두 개를 측정했고 **[measured, I1 §2]**, `b0dbcs.py`는 그것들을 각
엔진에 귀속시킨다. **WIDTH, DRAW, WRAP 작업은 쓸모 있는 의미에서 전혀 비슷하지
않다** — 아홉 엔진, 아홉 가지 폰트 포맷, 아홉 가지 목적지 서피스. queen은
256항 폭 테이블을 인덱싱하고(`engines/queen/display.cpp:1022`), touche는
`chr >= 32 && chr < 32 + _fontSize`를 단언하며(`engines/touche/graphics.cpp:74`),
saga의 것은 글리프별 트래킹 값이고, SCUMM의 것은 서브클래스 13개를 가진
`CharsetRenderer` 가상 함수다 **[source]**.

그 비대칭이 브랜치 계획을 지금의 형태로 만든다: **공유되는 것은 인코딩이지
렌더링이 아니다.** 아래 B3와 B4 단계는 아홉 엔진에 걸쳐 인코딩을 통일한다. 그것은
실제로 한 가지 것이 아홉 번 있는 경우이기 때문이다. 렌더링은 그중 여덟에서
그대로 둔다.

---

## 2. A. 브랜치 전략

### 2.1 `hires-text`에서 브랜치를 딴다

upstream에서 다시 시작하는 이유로 보통 드는 것은 오래된 포크가 표류했다는
것이다. 측정해 보면 이 포크는 그렇지 않다:

**[measured]** 포크 베이스 이후 240개 커밋에 대해 `hires-text`를
`upstream/master`와 `git merge-tree`한 결과는 **충돌 0**이다. 이 브랜치는 또한
128개 파일, 79개 추가와 49개 수정(+20285/−605)을 담고 있고 **[measured]**, I1은
그 240개 upstream 커밋이 우리가 추가한 파일 중 **0**개, 수정한 파일 중 **2**개를
건드렸다고 측정했다 **[measured, I1 §5.1]**.

그러므로 upstream에서 브랜치를 따는 것은, 0으로 측정된 머지 비용을 피하려고
깨끗하고 최신이며 머지 준비가 된 브랜치를 버리는 일이다. `hires-text`에서
브랜치를 딴다.

### 2.2 `hires-text`는 사용자의 테스트 빌드로 남는다

Windows 크로스빌드가 나오는 곳이고, 사용자가 검증한 커밋이 모두 사는 곳이다.
각 빅뱅 단계는 자신의 게이트가 초록일 때 그리로 머지해 *들어간다*. S-체인이 이미
하고 있는 방식이다 — `943cda2bcff`는 `wt/s10-curtests-src`의 머지이지 리베이스가
아니다.

### 2.3 빅뱅 브랜치의 실제 비용, 단계별로

이것이 카드가 요구한 수치이자 브랜치를 감당할 만하게 만드는 이유다.
`harness/b0fork.py`는 각 단계가 건드릴 파일별로, 지난 12개월간 그 파일에 떨어진
upstream 커밋 수와 그것이 몇 명의 서로 다른 작성자였는지를 측정한다.

**[measured]** (`captures/2026-09-16/b0/b0-fork.txt`):

```
B1 decodeChar into text16                    4 upstream commits / 12 months
B2 drop the Korean quantisation              0
B3 a lead-byte predicate in Common           0
B4 route the private predicates through it   0
B5 DBCSFontBase under the graphics fonts     2
B6 the engine text paths, one at a time     15

all steps: 21 upstream commits across every file the plan touches
```

이를 트리 전체의 속도에 대고 읽어라: I1은 12개월간 upstream 커밋 **12,549**건을
측정했다 **[measured, I1 §5.1]**. 이 브랜치가 편집하는 파일들은 그중 **21**건을
흡수한다. "공유 인프라" 단계가 추가해 들어갈 파일인 `common/str-enc.{h,cpp}`는
1년간 upstream 커밋이 **0**건이었고, `graphics/korfont.cpp`,
`engines/sword1/text.cpp`, `engines/saga/font.cpp`, `engines/grim/font.h`,
`engines/queen/display.cpp`도 마찬가지다 **[measured]**.

**이는 카드 자신의 프레이밍을 뒤집으며, 분명히 말해야 한다: 빅뱅 브랜치는 병렬
레이어보다 유지 비용이 더 비싸지 않다.** 병렬 레이어가 싼 것은 upstream이 새
파일을 절대 건드리지 않기 때문이고, 이 브랜치가 싼 것은 upstream이 *기존* 파일도
거의 건드리지 않기 때문이다. 이 프로젝트에서 비싼 파일은 등록 지점들이다 —
`engines/scumm/scumm.cpp`가 연 46커밋, `module.mk`가 32
**[measured, I1 §5.1]** — 그리고 이 계획은 그중 어느 것도 건드리지 않는다.

이 검사도 문다: 존재하지 않는 파일(`common/leadbyte.h`)을 지정하면
`*** MISSING ***`를 보고하고 1로 종료한다(`b0fork-bite.txt`). 기억에 의존해 쓴
계획은 그럴듯하게 읽히는 대신 실패한다.

### 2.4 어느 조각이 단독으로 upstream 가능한가

§5에서 단계별로 표시했다. 여섯 중 셋이 가능하며, B3+B4를 합친 것은 이 프로젝트가
만들어낸 가장 강한 upstream 스토리다 — 기능을 추가하는 게 아니라 중복을 지우고,
I1이 이미 리뷰어 선례를 세워 두었다: PR #2604에서 sluicebox의 기준은 *조건을
명시하고 이유를 설명하라*였지 *공유 파일을 건드리지 말라*가 아니었다
**[measured, I1 §5.4]**.

### 2.5 머지 주기

I1 §5.3에서 변경 없음: 정해진 요일에 매달 upstream을 머지한다. 이 브랜치가
새로 더하는 것은 **`b0dbcs.py`, `b0fork.py`, `b0surface.py`, `b0reach.py`가 모두
옮겨진 줄에서 실패한다**는 점이다. 따라서 이 계획이 의존하는 파일의 형태를 바꾸는
머지는 누가 렌더링을 읽기도 전에 하네스가 잡아낸다.

---

## 3. B. 세 가지 추상화, 그리고 어느 것이 정당화되는가

사용자는 셋을 지목했다. 측정해 보면 이들은 동등한 세 후보가 아니다.

### 3.1 Hires Hicolor Surface — **정당화되지 않으며, 이름은 두 군데 틀렸다**

`harness/b0surface.py`는 한 클래스가 둘 다 감당할 수 있는지를 결정하는 네 속성에
대해 SCUMM 텍스트 평면과 SCI 스케일 비트맵을 비교한다.

**[measured]** (`captures/2026-09-16/b0/b0-surface.txt`):

| 속성 | SCUMM | SCI |
|---|---|---|
| 평면 | **2** — 인덱스 + 선택적 커버리지 (`engines/scumm/hires_overlay.cpp:31`, `:116`) | **1** — 평평한 `new byte[...]` (`engines/sci/graphics/drivers/upscaled.cpp:64`) |
| 포맷 | CLUT8, 의도적으로 (`engines/scumm/hires_overlay.cpp:31`) | `_srcPixelSize` 바이트, 그리고 한국어 경로에서는 **1** (`engines/sci/graphics/drivers/default.cpp:118`, `engines/sci/graphics/screen.cpp:195`에서 포맷 없이 호출됨) |
| 배율 | 1..3, 사용자 선택 (`engines/scumm/hires_text.cpp:1393`) | 생성자에서 **고정 2** (`engines/sci/graphics/drivers/upscaled.cpp:35`) |
| 소유자 | **엔진** (`engines/scumm/hires_overlay.h:63`) | **드라이버** (`engines/sci/graphics/drivers/upscaled.cpp:41`) |
| 진입 | 글리프 단위, 공개 `Surface&`에 기록 (`engines/scumm/hires_overlay.h:95`) | 글리프 단위, `drawTextFontGlyph()`를 통해 (`engines/sci/graphics/drivers/upscaled.cpp:147`) |

네 속성, 네 개의 불일치. 그리고 이름에 대한 정정 둘:

1. **둘 다 하이컬러가 아니다.** 둘 다 CLUT8이다. SCUMM의 것은 *일부러* CLUT8이다 —
   평면들이 팔레트 인덱스를 저장하므로 나중의 팔레트 변경이 한참 전에 그려진
   텍스트의 색을 다시 칠한다(`engines/scumm/hires_overlay.h:43-47`) **[source]**.
   MI2 밤섬 페이드 버그가 켠 메커니즘이 그것이다. SCI의 것이 CLUT8인 이유는
   `GfxScreen`이 픽셀 포맷 없이 `initScreen()`을 호출하기
   때문이다(`engines/sci/graphics/screen.cpp:195`) **[source]**. 하이컬러는
   SCUMM 컴포지터의 *출력* 끝에서만 나타나며, 거기서 `HiResPalette16Sink`와
   `HiResTrueColorSink`가 프레임마다 인덱스를 해석한다
   (`engines/scumm/gfx.cpp:829-841`) **[source]** — 그리고 그것은 싱크이지
   서피스가 아니다.
2. **SCI 쪽은 이미 추상화되어 있다.** `drawTextFontGlyph()`는 래스터화된 글리프와
   고해상도 좌표를 받고, 호출자는 목적지를 전혀 건드리지 않는다. A1도 SCI의 픽셀
   쓰기에 대해 같은 말을 했다: 이 엔진은 픽셀 추상화가 모자란 게 아니다
   **[measured, A1 §A]**.

**판정: 만들지 마라.** 카드가 요구하는 하이컬러 사례 — "우리 알파 텍스트 경로가
그것을 필요로 한다" — 는 실재하지만 그것은 SCUMM의 것이고, 이미 구현 셋을 가진
`HiResSink`로 존재하며, SCI는 블렌딩할 커버리지 평면이 없어서 쓸 수 없다. SCI에
안티에일리어스 텍스트를 주는 것은 진짜 카드다. 그것은 *`UpscaledGfxDriver`에 두
번째 평면을 더하는 일*이지 공유 서피스 클래스를 추출하는 일이 아니다.

**정직한 반론, 기록해 둔다:** `HiResOverlay::bandFor()`
(`engines/scumm/hires_overlay.h:159`)는 진짜 공유 규칙이다 — 가상 화면과 스케일된
평면 사이의 좌표 변환 — 그리고 SCI는 이를 `x << 1, y << 1`
(`engines/sci/graphics/screen.cpp:484`)과
`getRealCoords()`(`engines/sci/graphics/drivers/upscaled.cpp:143`)로 다시 유도한다
**[source]**. 그것은 한 규칙의 두 사례이고, 이 프로젝트 자신의 기준으로는 아직
추상화가 아니다.

### 3.2 Font / FontSet — **정당화된다, 단 LEAD+PAIR 형태로만**

측정은 §1에 있다: 사적인 LEAD 답 다섯, 사적인 PAIR 답 넷, 그리고 I1이 찾은 한
술어의 바이트 단위로 동일한 사본 다섯. 그것이 카드가 찾는 중복이고, 실재한다.

그것이 *아닌* 것은 `FontSet`이다. 카드는 한글과 영문을 함께 들고 있는
`FontKoreanWansung`(`graphics/korfont.h:190-218`) **[source]** 이 SCI가 폰트
전환을 그만둬야 함을 뜻하는지 묻는다. 그렇게 따라오지 않는다:

- `SwitchToFont1001OnKorean`(`engines/sci/graphics/text16.cpp:762`)은 **어떤 폰트
  리소스를 로드할지**를, 폰트가 존재하기도 전에 바이트를 킁킁거려 결정한다
  **[source]**. S3b는 정확히 그 이유로 이것을 폰트 소유권에서 배제했다 —
  *실행될 때 아직 폰트가 없다* **[measured, S3b §D1]**.
- 폰트 1001은 **팬 번역 에셋 계약**이다. 사용자 디스크의 한국어 패치가 배포하는
  id이며(`engines/sci/graphics/cache.cpp:70`) **[source]**, I1은 그런 계약 34개를
  유지 필수로 분류했다 **[measured, I1 §1.1]**.

그래서 정당화되는 추상화는 F1이 이미 만든 것이다 —
`Graphics::DBCSFontBase`(`graphics/dbcsfont.h:55`). 이 클래스는 드로잉 모드,
1비트 블리터, 아웃라인 빌더를 소유하고 언어에 `getCharData` + `hasFeature` +
`isASCII` + `getASCIIWidth`를 묻는다 **[source]** — 여기에 **아직 없는 가상 함수
하나**를 더한다: 리드바이트 술어. 그것이 B3/B4/B5다.

`GfxFont::decodeChar()`(`engines/sci/graphics/scifont.h:65`)는 SCI 쪽 절반이며
이미 존재하고, `controls16.cpp`에 살아 있는 호출 지점이 다섯 개 있다 **[source]**.
B1은 S4가 시작한 것을 끝내는 일이다.

### 3.3 String — **정당화되지 않으며, 이유는 엔진마다 다르다**

카드는 이미 329개 파일이 쓰고 있는데 왜 텍스트 경로는 `Common::U32String`을 쓰지
않는지 묻는다. 이 모집단에서 엔진별로 측정하면: **[measured]**

```
scumm 23 files   sci 16   kyra 5   saga 5   sword1 4   agi 3   agos 3
queen 2   touche 2
```

그리고 들여다보면, agi, queen, sword1, saga에서 U32String 사용처는
`canLoadGameStateCurrently(Common::U32String *msg)`, 저장 슬롯 설명,
번역된 GUI 메시지다 **[source]**. **단 하나도 텍스트 경로에 있지 않다.** 그러니
그 숫자는 채택의 증거가 아니라, GUI와 메타엔진이 이미 쓰고 있고 텍스트 경로는
쓰지 않는다는 증거다.

쓰지 않는 이유는 셋이고, 서로 다른 이유다:

1. **바이트 배열이 게임의 리소스 포맷이다.** SCUMM의 번역 텍스트는 64.7%가
   인라인 바이너리 opcode인 `korean.trs` 레코드로 도착한다
   **[measured, P1 §1.1]**. U32String으로 변환했다가 되돌리려면 그것들을 바이트
   단위로 보존해야 한다.
2. **바이트가 게임으로 되돌아간다.** SCI의 편집 컨트롤은 플레이어 입력을 스크립트
   996 자신의 지역 변수 블록(`segtype=3`)에 담고 **[measured, S3b M1]**, 게임은
   그것을 `kParse`에 넘긴다. 코드포인트 버퍼는 게임이 읽기 전에 다시 인코딩되어야
   한다 — S3b의 M2가 그 변환이 정확하고 싸다고 보였지만, 그것은 경계에서의
   변환이지 표현 전반의 변경이 아니다.
3. **아무도 시도하지 않았다.** kyra, saga, queen, touche, agos는 관성 말고는
   이유가 없고, 그중 셋은 변환할 2바이트 경로 자체가 없다.

**판정: 이 브랜치에서 제외.** U32String 텍스트 경로는 인코딩이 통일된 뒤의 네 번째
브랜치이며, 그 첫 엔진은 touche여야 한다. 엔진 인스턴스 없이 렌더러를 호출할 수
있는 유일한 엔진이므로(§6), 변환을 프로브로 바이트 단위로 증명할 수 있다.

---

## 4. C. 엔진 순서

**SCI, 그다음 SCUMM, 그다음 queen, 그다음 touche. 이 브랜치는 거기서 멈춘다.**

| # | 엔진 | 왜 여기인가 | 무엇을 결정하는가 |
|---|---|---|---|
| 1 | **sci** | PAIR 열의 유일한 `caller`(§1) — 추상화의 이름이 가리키는 결함이 이 엔진에서만 보인다. 그리고 `decodeChar()`가 호출 지점 5개와 함께 이미 존재한다 **[source]** | 인터페이스. B1 이후 `decodeChar`가 어떤 모습이든 그것이 나머지 여덟 엔진이 받는 것이다. |
| 2 | **scumm** | 가장 큰 텍스트 경로(세 파일에 걸쳐 5,594줄 **[measured]**), 게임 데이터와 하네스, 그리고 Windows에서 테스트하는 사용자가 있는 엔진 | 인터페이스가 `CharsetRenderer` 서브클래스 13개를 견디는지. 견디지 못한다면, 아무도 돌릴 수 없는 엔진보다 여기서 배우는 편이 낫다. |
| 3 | **queen** | 2바이트 경로가 전혀 없고, WIDTH 작업이 256항 바이트 인덱스 테이블 하나다(`engines/queen/display.cpp:1022`) **[source]** | 깨끗한 엔진에 능력을 *추가하는* 일이 작은지. "새 언어는 함수 세 개 값" 주장에 대한 가능한 가장 싼 시험이다. |
| 4 | **touche** | 렌더러가 static이고 목적지 포인터를 받는 유일한 엔진이라(`engines/touche/graphics.h:39`) **[measured]** 엔진 인스턴스 없이 증명 가능하다 | 게임 없이 변경을 바이트 단위로 증명할 수 있는지. |

**왜 가장 복잡한 것부터 시작하지 않는가.** 카드가 묻는다. SCUMM이 가장 복잡하지만
첫째가 아니라 *둘째*다. SCI가 인터페이스의 형태가 이미 절반쯤 지어져 있고 결함을
진단할 수 있는 곳이기 때문이다. SCUMM으로 시작한다면 인터페이스가 한 번도
행사되기 전에 서브클래스 13개에 대고 설계해야 한다.

**kyra가 크면서도 빠지는 이유.** kyra는 부모 세션의 집계로 CJK 분기 15개와 바이트
수준 조작 566개를 가져서 두 번째로 큰 상처럼 보였다. 빠지는 이유는: 여기 게임
데이터가 없고, 돌릴 방법이 없고, 그리고 — §1.1의 발견 — 이미 S4 형태의 결함(서로
불일치하는 PAIR 사본 둘)을 품고 있다. 그것을 고치는 일은 진짜 카드이며, 아홉 엔진
훑기에 접혀 들어가는 대신 측정으로 열리는 자기 자신의 카드가 되어야 한다.

**saga, sword1, agos, agi가 빠지는 이유.** saga와 sword1은 여기 어떤 테스트도
행사할 수 없는 폰트 게이트 한국어 경로를 들고 있다. agos는 2바이트 경로가 없고
분리 가능한 것도 없다(`AGOSEngine::doOutput`은 엔진 클래스의 메서드다
**[measured]**). agi의 한국어 작업은 머지되지 않은 커밋 11개와 함께
`wt/k6-agitrs-src`에 살아 있고 자기 조건으로 먼저 착륙해야 한다.

---

## 5. D. A1의 다섯 단계와의 관계, 그리고 단계 목록

**빅뱅은 A1의 1–4단계를 포함하고 5단계를 제외한다.**

A1은 SCI에 대해 다섯 단계를 정렬했고, 1–4가 착륙해 버틸 때까지 5단계를 시작해서는
안 된다고 했다 **[measured, A1 §E]**. 그 조건을 지킨다. 1–4단계가 아래의 B1과
B2이며, 변경 없다.

A1의 5단계 — `{fontId, drawnByDriver, pen}`을 나르는 줄 렌더 컨텍스트 — 는
**이 브랜치에 없다**. 이유는 신중함이 아니라 측정이다: A1은 그것을 *한 줄의 폰트
또는 드라이버 소유권*에 대해 모두 불일치하는 네 사례(S4, S6, S7, S9)로 정당화했다
**[measured, A1 §B]**. 그 넷은 전부 SCI다. SCI 결함 넷으로 정당화된 렌더
컨텍스트는 SCI 변경이며, 이 브랜치의 주제는 아홉 엔진이 공유하는 것이다. 접어
넣으면 브랜치의 주제가 한꺼번에 둘이 되는데, 그것은 커밋 메시지에 "also"라는
단어가 필요해지는 경우다.

### 단계들

| # | 단계 | 파일 | upstream 변경량 | 게이트 | 단독 upstream 가능 |
|---|---|---|---|---|---|
| **B1** | `text16.cpp`의 바이트 페어 순회 다섯 곳을 `GfxFont::decodeChar()`로 향하게 하고(`:216, :315, :353, :395, :517`), 죽은 3인자 `DrawString`을 삭제한다(`engines/sci/graphics/text16.h:66`) | 4 | 4 commits/yr | `a1entry.py`가 오버로드가 사라졌음을 보인다. `a1census.py`의 BYTEWALK REPLACE 개수가 8에서 내려간다. 전체 테스트 스위트. Cascade Quest + 일본어 SCI 대상에 대한 A/B 캡처 | **예** — S3b가 이를 "option 3"으로, A1이 3단계로 값 매겼다 |
| **B2** | `GfxFontKorean::draw()`에서 `left & 0xFFC`를 제거한다(`engines/sci/graphics/fontkorean.cpp:76`) | 1 | 0 | `a1coord` 재실행이 `positions moved: 0`을 보인다. SCI0 한국어 줄의 A/B 캡처. **Windows에서 사용자의 눈** — 이 변경은 설계상 글리프를 움직인다 | **예**, 클래스 단위로 한국어 전용 |
| **B3** | 이미 존재하는 변환들 옆에 `Common::isLeadByte(CodePage, byte)`를 추가한다(`common/str-enc.h:73`) | 2 | 0 | 0x00–0xFF × 다섯 코드페이지에 대한 유닛 테스트를 Python codecs에 대조. `i1cover.py`의 사이트별 accept/reject 개수 불변 | **예** — I1은 이것을 `Common::` 인프라에서 진짜로 빠진 유일한 조각으로 꼽았다 |
| **B4** | 사적인 리드바이트 사본 일곱 개를 그것으로 경유시킨다(`graphics/korfont.cpp:35`, `engines/scumm/charset.h:48`+`:67`, `engines/grim/font.h:55`, `engines/sword1/text.cpp:355`, `engines/sword2/maketext.cpp:709`, `engines/saga/font.cpp:521`) | 6 | 0 | `i1cover.py`가 모든 사이트가 **accept/reject 개수를 그대로 유지한 채** 위임함을 보인다 — 요점은 중복을 멈추는 것이지 동작을 바꾸는 게 아니다. 그리고 I1의 경계 결함을 같은 단계에서 고친다. `0xB0..0xD0` 대 `0xB0..0xC8`은 공유 술어가 정리하는 바로 그것이다 | **예**, 게다가 버그 수정을 싣고 간다 |
| **B5** | `DBCSFontBase`(`graphics/dbcsfont.h:55`)를 넓혀 리드바이트 질문도 소유하게 한다 | 6 | 2 | `f1dump.sh`가 전후로 바이트 단위 동일 — F1이 이미 만든 2.85 GB 글리프 덤프 — **단 `f1glyphdump.cpp`를 `graphics/big5.h`까지 포함하도록 확장한 뒤. 오늘은 포함하지 않는다** **[measured]**. `i1fonts.py`가 중복 본문 0을 보고 | **예**, B3/B4 이후 |
| **B6** | 엔진 텍스트 경로를 §4 순서로: sci → scumm → queen → touche | 9 | 15 | 엔진별로, 도달 가능성이 허용하는 §6 티어 | **아니오** — 한 번에 한 엔진, 각각이 자기 카드 |

**B6는 카드 하나가 아니라 넷이다.** 각 엔진이 자기 카드와 자기 마감 측정을 갖는다.
브랜치는 SCI와 SCUMM이 전환되고 캡처로 불변임이 확인될 때 끝난다. queen과 touche는
새 언어가 싸다는 시연이며, 밀려도 된다.

### 첫 커밋, 구체적으로

브랜치 이름: **`wt/b1-decodechar`**, `hires-text`에서 자른다.

첫 커밋: *"SCI: let the font decode its own characters in text16"* — `decodeChar()`
호출 지점 다섯 개, `DrawString` 삭제, 그리고 `text16` 경로를 덮도록
`test/engines/sci/font_decodechar.h`(오늘 테스트 10개)를 확장하는 유닛 테스트.
첫 카드: 위에 쓴 대로 **B1**.

`DrawString` 삭제가 자기 커밋을 갖는 대신 B1에 실려 가는 이유는, 호출자 0 증명이
붙은 네 줄이고 **[measured, A1 §C]** 두 변경이 같은 함수 근방에 있기 때문이다.
쪼개면 리뷰 가능성에 아무 이득 없이 빌드 사이클만 든다.

---

## 6. E. 무엇이 안전성을 증명하는가

이것이 브랜치를 결정한다는 카드의 말은 옳다. `harness/b0reach.py`는 각 엔진의
텍스트 경로가 *호출되기* 위해 무엇을 필요로 하는지 측정한다. 그것이 어떤 증명이
가능한지를 결정하기 때문이다.

**[measured]** (`captures/2026-09-16/b0/b0-reach.txt`):

```
engine   reach   entry point                  data?  site
touche   free    Graphics::drawString16       no     engines/touche/graphics.h:39
saga     vm      DefaultFont::draw            no     engines/saga/font.h:200
queen    vm      Display::drawText            no     engines/queen/display.h:43
sword1   vm      Text::makeTextSprite         no     engines/sword1/text.h:50
kyra     vm      Screen::drawChar             no     engines/kyra/graphics/screen.h:640
agos     engine  AGOSEngine::doOutput         no     engines/agos/charset.cpp:64
scumm    vm      CharsetRenderer::printChar   yes    engines/scumm/charset.h:109
sci      vm      GfxText16::Draw              yes    engines/sci/graphics/text16.h:47
agi      engine  TextMgr::charAttrib          yes    engines/agi/text.h:84

free 1   vm 6   engine 2
game folders on disk: 58
provable by capture here: scumm, sci, agi
provable only by probe or by reading: touche, saga, queen, sword1, kyra, agos

Font coverage from F1's glyph dump (harness/probes/f1glyphdump.cpp):
   graphics/korfont.h     FontKorean   dumped=yes
   graphics/sjis.h        FontSJIS     dumped=yes
   graphics/big5.h        Big5Font     dumped=NO
```

### 6.1 세 가지 티어

**티어 1 — 골든 덤프, 게임 없음.** F1의 선례: 트리 자신의 `libgraphics.a`를
프로브에 링크해 모든 글리프 × 모든 드로잉 모드 × 양쪽 비트 깊이를 덤프하고
바이트를 비교한다. 2.85 GB, 바이트 단위로 동일하며, 게임도 필요 없고 테스트
스위트의 널 OSystem 외의 OSystem도 필요 없다(`harness/f1dump.sh`) **[source]**.
이것이 **B5를 완전히** 덮는다. B5의 주제 전체가 그 덤프가 이미 열거하는
`graphics/` 폰트 클래스 셋이기 때문이다. 또한 **touche 전체**를 덮는다 — 그
렌더러는 static이고 `uint8 *dst, int dstPitch`를 받으므로
(`engines/touche/graphics.h:39`) **[measured]**, 프로브가 엔진 없이
`drawString16()`을 버퍼에 대고 호출할 수 있다.

**이것이 설계 목표로 삼을 티어다.** 장면 하나가 아니라 모집단 전체를 측정하는
유일한 티어다.

**티어 2 — 컨트롤 빌드에 대한 캡처.** scumm, sci, agi. 게임 데이터가 디스크에
있고, `b4ab.sh`/`sceneab.sh`가 이미 만들어져 있으며, 함정도 이미 적혀 있다:
`hires_text_scale=1`은 컨트롤이 아니고(맵은 여전히 발견된다), 배율이 다른 두 쪽은
픽셀 diff가 불가능하며, 모양의 차이는 픽셀 수가 아니다
**[skill: scummvm-korean-hires-ttf]**. B1, B2, 그리고 B6의 첫 두 엔진이 여기서
마감된다.

**티어 3 — 컴파일 + 공유 폰트 덤프 + 서술된 논증.** kyra, saga, queen, sword1,
agos. 여기서는 돌릴 수 없다. 이들이 *받을 수 있는* 것은:

- 브랜치를 적용한 빌드(B3/B4 파손의 대부분을 잡는다. 변경이 술어의 호출
  지점이기 때문이다);
- **이들이 공유하는 폰트에 대한 티어 1 커버리지**: `graphics/korfont.h`는
  SCUMM, SCI, SAGA, sword1의 한국어를 담당하고, `graphics/sjis.h`는 SCUMM, SCI,
  KYRA, SAGA의 일본어를 담당하며, 둘 다 오늘
  `harness/probes/f1glyphdump.cpp`가 덤프한다. **`graphics/big5.h`는 아니다**:
  프로브는 `korfont.h`와 `sjis.h`만 포함하고 그 외에는 없다 **[measured]**.
  따라서 SAGA와 KYRA의 중국어는 티어 1 커버리지가 전혀 없고 B5가 그것을 추가해야
  한다. 그래서 이 다섯 엔진에 대해 변경의 *폰트* 절반은 세 언어 중 둘에 대해
  증명되고, 엔진 절반은 전혀 증명되지 않는다;
- 술어 자체에 대한 유닛 테스트. B4에서 이들의 동작이 실제로 바뀌는 지점이 거기다;
- 런타임 증거가 없다는 명시적 문장을 커밋에 담는 것.

**이 카드가 세우는 규칙: 소속 엔진이 전부 티어 3인 단계는, 자신이 건드리는 공유
코드를 덮는 티어 1 덤프 없이는 착륙하지 않는다.** B4는 자격이 있다(공유 코드가
술어이며 유닛 테스트 가능하다). kyra/saga/sword1에 대한 B6는 자격이 없고, 그것이
이들이 브랜치에서 빠진 이유다(§4).

### 6.2 텍스트 경로용 골든 덤프, 그리고 그것이 할 수 없는 일

카드는 F1의 모델을 따라 텍스트 경로 전체에 대한 덤프-비교 장치를 요구한다. 설계:

**덤프:** (엔진에서 도달 가능한 렌더러, 폰트, 드로잉 모드) 조합마다, 고정된 문자
모집단을 고정 크기 버퍼에 래스터화한 결과와 렌더러가 보고한 문자별 advance.
픽셀만이 아니라 advance *와* 픽셀 둘 다다. S7/S9의 결함은 측정/그리기 불일치였고,
픽셀만으로는 "텍스트가 움직였다"로만 보였을 것이기 때문이다.

**비교:** 셀 단위로, 전후의 바이트.

**덮는 것:** 폰트 인터페이스 아래의 모든 것 — 티어 1 — 그리고 touche.

**덮을 수 없는 것, 그리고 이것은 덮어 가리는 대신 명시해야 할 한계다:** `vm`과
`engine` 엔진 여섯의 *레이아웃*. 줄이 어디서 끊기는지, 펜이 어디서 시작하는지,
한 줄이 어떤 폰트로 그려지는지 — S4/S6/S7/S9 부류의 결함 — 은 폰트 위에 살고
엔진이 돌아야 한다. scumm/sci/agi에게 그것은 티어 2다. kyra/saga/sword1/agos/queen
에게는 **[unmeasured]**이며 브랜치는 그렇다고 말해야 한다.

**재사용, 구체적으로:** `f1dump.sh`는 이미 엔진의 실제 컴파일 플래그로 트리 자신의
라이브러리에 대고 프로브를 빌드하며, `config.mk`를 grep하면 SDL의 include 경로가
빠지기 때문에 `f1flags.mk`가 존재한다 **[source]**. 텍스트 경로 덤프는 프로브
소스만 다른 그 스크립트다. 빌드 쪽에 새로 필요한 것은 없다.

---

## 7. 범위, 그리고 프로브

**엔진 코드는 바뀌지 않았다.** 엔진 워크트리는 깨끗하다:

```
$ git -C repo/scummvm status --short engines/
(empty)
$ git -C repo/scummvm/.worktrees/t_ae8fa12a status --short
(empty)
```

**프로브 하나를 주입했다가 되돌렸다.** `b0dbcs.py`의 전사 검사가 문다는 것을
증명하기 위해 `t_ae8fa12a` 워크트리의 `DefaultFont::getStringWidth`
(`engines/saga/font.cpp:510`)에 빈 줄 하나를 넣었다. saga에 대해
`*** MOVED ***`를 두 줄 보고하고 1로 종료했으며
(`captures/2026-09-16/b0/b0dbcs-bite2.txt`), `git checkout`으로 되돌렸고,
깨끗한 실행은 전사 37건을 확인하고 0으로 종료한다.

`b0fork.py`의 물기는 비침습적이며 — 존재하지 않는 파일 이름 — `b0surface.py` /
`b0reach.py`는 구조상 같은 전사 가드를 갖는다(핀 고정된 줄이 각각 11개와 9개).

---

## 8. 여기 모든 수치의 재현

```bash
cd ~/work/scummvm/.worktrees/t_7a5dbbf2/harness
B0ENG=~/work/scummvm/repo/scummvm python3 b0dbcs.py      # §1  the five jobs
B0ENG=~/work/scummvm/repo/scummvm python3 b0fork.py      # §2.3 churn per step
B0ENG=~/work/scummvm/repo/scummvm python3 b0surface.py   # §3.1 the two surfaces
B0ENG=~/work/scummvm/repo/scummvm python3 b0reach.py     # §6  reachability
```

각 도구는 자신의 위치에서 엔진 트리를 유도하고 `B0ENG`로 덮어쓰기를 받는다.
어느 것도 카드 id를 적지 않는다.

---

## 9. 측정이 사용자의 지시에 반대하는 지점

카드가 이 절을 명시적으로 요구했고, 두 군데가 있다.

**1. "Hires Hicolor Surface"는 만들면 안 된다.** §3.1. 네 속성, 네 개의 불일치,
그리고 두 서피스 모두 하이컬러가 아니다. 그 밑에 깔린 진짜 요구 — SCI의
안티에일리어스 텍스트 — 는 다른 변경이며(`UpscaledGfxDriver`에 커버리지 평면을
주는 일), 자기 측정을 가진 자기 카드를 받을 자격이 있다.

**2. "아홉 엔진"은 넷이다.** §1.1. 아홉 중 넷은 정리할 2바이트 경로가 없고, 경로가
있는 다섯 중 둘(kyra, saga)은 여기서 아예 돌릴 수 없으며 하나(sword1)는 440줄짜리
파일 하나다. 실제로 측정이 뒷받침하는 브랜치는 **sci와 scumm**을 전환하고,
인터페이스가 싸다는 증명으로 **queen과 touche**에 능력을 추가하며, 나머지는
카드로 남긴다.

둘 중 어느 것도 브랜치를 하지 말라는 이유는 아니다. 둘 다 브랜치를 순서와 증명
수단이 있는 부분으로 좁힐 뿐이며, 그것이 카드 자신이 세운 조건이다.

## 10. 측정되지 않았고, 하중을 받는 것

1. **B1의 호출 지점 다섯 개 전환이 픽셀을 바꾸지 않는다는 것.**
   `decodeChar()`의 동작 보존 기본값(`engines/sci/graphics/scifont.h:65`)과, S4가
   이미 `controls16.cpp`에서 캡처 회귀 없이 그것을 썼다는 사실로 논증했다.
   일본어와 Mac SCI 경로 전반에 대해서는 시연되지 않았다.
2. **티어 3 엔진 다섯에 대해 텍스트 경로의 레이아웃 절반이 불변이라는 것.**
   §6.2. 여기서 측정할 방법이 없으며, 브랜치는 이들을 건드리는 모든 커밋에서
   그렇다고 말해야 한다.
3. **B2의 캡처가 무엇을 보일 것인가.** A1이 이것을 열어 두었고 여전히 열려 있다.
   마스크 제거는 개선이 아니라 변위로 측정된다. 사용자가 시각적 게이트다.
4. **kyra의 두 PAIR 사본이 실제로 불일치하는가.** §1.1은 그것들이 한 질문에 대한
   독립적인 두 답임을 확립한다. `fetchChar`와 `getCharLength`가 달라지는 입력을
   아무도 찾지 못했다. 그것은 카드이며, 측정으로 시작한다.
5. **`Common::isLeadByte`가 일곱 술어 전부를 표현할 수 있는가.** B3는 `CodePage`
   인자를 가진 함수 하나가 그것들을 덮는다고 가정한다. 일곱 중 둘은 리드바이트만
   검사하고 둘은 상위 비트가 선 바이트를 전부 받아들이므로
   **[measured, I1 §2]**, 시그니처에 두 번째 형태가 필요할 수 있다.
