# 게임 옵션 UI와 "간단 모드" 설계

조사일 2026-09-06, 소스 `hires-text` @ `ef95aaca144`. 코드 변경 없음 — 조사와 제안만.

## 1. ScummVM 게임 옵션 UI가 제공하는 것

`engines/scumm/metaengine.cpp`, `dialogs.cpp` 기준.

### 1-a. `ExtraGuiOption` 체크박스 (`metaengine.h:70`)

```cpp
struct ExtraGuiOption { label; tooltip; configOption; defaultState; groupId; groupLeaderId; };
```

- **bool 체크박스 하나만** 만든다. 슬라이더·팝업·경로 입력 없음.
- `ScummMetaEngine::getExtraGuiOptions(target)` (`metaengine.cpp:950`)에서 gameid/platform/
  language/`guioptions` 문자열로 노출 여부를 정한다. 예: `comiObjectLabelsOption`은 `gameid=="comi"`
  일 때만, `enableCOMISong`은 `language != en`일 때만.
- `registerDefaultSettings`가 기본값을 ConfMan에 등록한다.
- 저장은 `ScummGameOptionsWidget::save()` → `ConfMan.setBool(configOption, ...)`.

### 1-b. 게임별 커스텀 위젯

`buildEngineOptionsWidget` (`metaengine.cpp:680`)이 **gameid로 분기해서 커스텀 위젯을 돌려주면
1-a 목록은 표시되지 않는다**:

| 조건 | 위젯 | 부품 |
|---|---|---|
| `loom` VGA | `LoomVgaGameOptionsWidget` | 슬라이더 + 체크박스 |
| `loom` EGA | `LoomEgaGameOptionsWidget` | 팝업(overture) + 체크박스 |
| `monkey` CD/Towns/Sega | `MI1CdGameOptionsWidget` | 슬라이더 |
| Mac 판 (indy3/loom/monkey/monkey2/atlantis) | `MacGameOptionsWidget` | 여러 체크박스 |
| 그 외 | `ScummGameOptionsWidget` | 1-a 목록 |

**함의**: `ExtraGuiOption`만 추가하면 Loom VGA/EGA, MI1 CD, Mac 판에서는 안 보인다. 우리 테스트
셋에 Loom VGA ko, MI1 ko가 있으므로 이 경로로는 부족하다.

### 1-c. 엔진 옵션에 파일 선택기는 없다

`engines/*/dialogs.cpp`에서 `BrowserDialog`/경로 위젯 사용 0건. 전역 옵션(`gui/options.cpp`)에만
있다. 엔진 탭에서 TTF 경로를 고르게 하려면 새 패턴이다 — upstream 리뷰 부담이 크다.

### 1-d. 현재 hi-res 관련 GUI 노출: 없음

`hires_text*` 키를 읽는 GUI 코드는 없다. 전부 ini 수동 편집.

## 2. GUI 제안

### 2-a. 최소안 — 체크박스 하나 (`hires_text`)

```cpp
static const ExtraGuiOption enableHiResText = {
    _s("Hi-res text"),
    _s("Draw translated text with the larger fonts shipped in the game folder (hires_text.map)"),
    "hires_text", true, 0, 0 };
```

노출 조건: `language ∈ {ko, ja, zh-cn, zh-tw}` **또는** 게임 폴더에 `hires_text.map` 존재.
후자는 `getExtraGuiOptions`에서 `ConfMan.get("path", target)`로 FSNode 확인 — 다른 옵션들이
하지 않는 파일 접근이지만 비용은 stat 하나.

엔진 쪽: `loadConfig()`에 `if (ConfMan.hasKey("hires_text") && !ConfMan.getBool("hires_text")) { _enabled=false; return; }`.
**이것이 현재 없는 "끄기" 스위치를 만든다** (HIRES_TEXT_SETUP.md §5).

배율·알파는 맵이 정한다. GUI는 On/Off만. 여기까지가 upstream에 낼 만한 범위.

### 2-b. 확장안 — 커스텀 위젯

`HiResTextOptionsWidget : ScummOptionsContainerWidget`에 체크박스 + 팝업(Auto/1x/2x/3x) + 알파
체크박스. `LoomEgaGameOptionsWidget`의 팝업 패턴을 그대로 쓴다. 단 1-b 때문에 기존 커스텀
위젯 4종에도 같은 부품을 끼워야 한다 → `createHiResTextWidgets(boss, layout)` 헬퍼로 공유.
Loom VGA/MI1 CD 다이얼로그 레이아웃(`gui/themes/*.stx`)도 같이 수정. 범위가 커서 2-a 이후.

## 3. "간단 모드" — 맵 없이 고정 파일 이름

목표: 번역자가 맵을 쓰지 않고 폰트 파일만 떨어뜨리면 되게.

### 3-a. 탐색 순서 (제안)

```
1. hires_text=false                      → 끔 (무조건)
2. hires_text_map=<path>                 → 그 맵
3. <game>/hires_text.map                 → 그 맵
4. <game>/hires%02d.fnt 또는 hires.fnt   → 간단 모드 (bitmap)
5. hires_text_font=<path.ttf>            → 간단 모드 (TTF, FreeType 필수)
6. 없음                                  → 끔
```

4·5는 `hires_text=true`(또는 GUI 체크)일 때만. 폴더에 파일이 있다고 자동으로 켜지는 건 3까지 —
맵은 번역자가 의도를 적은 것이고, 낱개 `.fnt`는 실수로 남아 있을 수 있다.

### 3-b. 간단 모드의 기본값

| 항목 | 값 | 근거 |
|---|---|---|
| scale | `cellHeight(hires00.fnt) / charsetHeight(0)` 반올림, 1~3 클램프 | 폰트가 자기 배율을 말한다 |
| alpha | 폰트 bpp==8 | 8bpp는 알파용으로 구운 것 |
| encoding | language 기반 (지금과 동일) | |
| metrics | `game` | 안전 기본 |
| latin | `hires_latin%02d.fnt` 있으면 사용 | DOTT 같은 예외는 파일을 안 넣으면 됨 |

내부적으로는 `HiResFontConfig`를 채워서 **맵 경로와 같은 코드**로 흘려보낸다. 파서 우회 아님.

### 3-c. TTF 직접 지정

```ini
hires_text=true
hires_text_font=/path/NanumGothic.ttf
hires_text_scale=2        ; 생략 시 2
```

- 크기 = charset 높이 × scale, charset마다 래스터. `HiResTtfGlyphSource`(G4)가 이미 있다.
- `USE_FREETYPE2` 없는 빌드: 경고 후 끔. 이식성 원칙상 TTF는 편의 기능이고 bitmap이 정식.
- 배포용은 `mkfont.py`로 구워서 3-a-4 형태로 넣는 것을 권장. 문서에 명시.

### 3-d. upstream 관점

- 2-a + 3-a-1(`hires_text` 마스터 스위치)은 작은 독립 커밋 → 먼저.
- 3-a-4(고정 이름 bitmap)는 `loadConfig()`에 30줄 정도, 새 파일 형식 없음 → 다음.
- 3-c(TTF)는 FreeType 조건부 + 시작 시 래스터 비용 → 마지막, 별도 PR 가능.
- 2-b(커스텀 위젯)는 테마 파일까지 건드림 → 기능 안정 후.

## 4. 현재 코드에서 확인된 사실 (설계 근거)

- `hires_text.cpp:762` `_enabled = haveMap && (scale>1 || bitmap named)` — 맵 없으면 절대 안 켜짐,
  맵 있으면 못 끔.
- `hires_text.cpp:731-744` 사용자 키가 맵보다 우선 — 간단 모드 기본값도 같은 자리에서 덮어쓰면 된다.
- `glyph_source.h:118` `HiResTtfGlyphSource`는 `USE_FREETYPE2` 조건부로 이미 컴파일된다.
- `metaengine.cpp:1066` `registerDefaultSettings`는 `getExtraGuiOptions("")`를 돌리므로 새 옵션의
  기본값 등록은 자동.
