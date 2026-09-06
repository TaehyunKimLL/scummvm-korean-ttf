# Hi-res 텍스트 — master 위 재구축 설계 (v2)

작성: 2026-09-05. 기준 `origin/master` = `41ac2b31847`.
원본(복사 출처) = `ref/hires-text-i18n` = `1b95ef0968d` (fork 에 푸시됨).

## 0. 목표 (사용자 확정)

1. **CJK 뿐 아니라 라틴 문자에도** 고해상도 폰트를 적용한다.
2. **SCUMM 외 다른 엔진(SCI, AGI 등)** 에도 같은 방식으로 확장한다.
3. 최종적으로 upstream 기여.
4. **유니코드(UTF-8/16) 기반으로 확장 가능**해야 한다. 기존 KSC5601 번역은 계속 지원.
5. **가변폭(variable width) 폰트** 지원.
6. **"1바이트 라틴 / 2바이트 CJK" 라는 DBCS 가정을 최대한 걷어낸다.**
7. **알파 블렌딩되는 비트맵 폰트** 지원.
8. **TTF 를 못 쓰는 플랫폼에서도 미려한 폰트** — FreeType 없이도 anti-aliased 글꼴.

4·5·6 은 **하나의 인터페이스 결정**으로 수렴한다: 공용층은 코드포인트를
받고, 바이트 해석은 어댑터 경계에서 끝난다. 7·8 도 하나로 수렴한다: 8bpp
커버리지 비트맵 폰트. 아래 §4-1, §4-2 에서 다룬다.

목표 1·2 가 설계의 뼈대를 바꾼다. v1 설계(`CJKHiResState`, `cjk_*.cpp`)는
이름부터 틀렸다 — CJK 가 아니라 **hi-res text** 가 주어다. 그리고 엔진
디렉터리(`engines/scumm/`) 안에 두면 SCI 가 쓸 수 없다.

## 1. 실측 — 원본은 얼마나 엔진 독립적인가

핵심 질문: "SCI 로 확장"이 다시 짜는 일인가, 옮기는 일인가.

원본 `charset.cpp` 신규 함수 13개(969줄)의 SCUMM 전용 심볼 의존도를 셌다
(`_virtscr`, `VirtScreen`, `_charset`, `_gdi`, `_currentRoom`, `_game.` 등):

| 함수 | 줄 | SCUMM 심볼 | 판정 |
|---|---|---|---|
| `loadKorTtfMap` (맵 파서) | 218 | 2 | 공용층 |
| `drawKorTtfChar` (TTF 렌더) | 218 | **0** | 공용층 |
| `Pick` (맵 섹션 선택) | 115 | 0 | 공용층 |
| `drawSvfnGlyph` (SVFN 렌더) | 98 | **0** | 공용층 |
| `loadKorTtfConfig` | 68 | 0 | 공용층 |
| `parseSvfnHeader` | 64 | 0 | 공용층 |
| `korTtfRunAppend` | 48 | 1 | 공용층 |
| `getKorTtfCharWidth` | 48 | 1 | 공용층 |
| `loadKorTtfFont` | 31 | 1 | 공용층 |
| `loadSvfnLatin` | 26 | 0 | 공용층 |
| `getSvfnWidth` | 20 | 0 | 공용층 |
| `resolveKorTtfPath` | 11 | 0 | 공용층 |

**13개 전부 0~2회.** 폰트 로딩과 글리프 렌더는 이미 사실상 엔진 독립적이다.
`ScummEngine::` 멤버로 선언돼 있을 뿐이다.

반면 `gfx.cpp` 추가분 344줄은 SCUMM 심볼 **43회** — `VirtScreen`, `xstart`,
`topline`, `camera` 에 결합돼 있다. 이건 엔진 어댑터다.

**결론**: 두 층이 명확히 갈린다.

```
공용층 (969줄)  ─ 폰트 로딩, 맵 파싱, 글리프 → 서피스 렌더.  엔진 무관.
어댑터 (344줄)  ─ 서피스 → 화면 합성, 좌표 변환, 수명 관리.  엔진마다 다름.
```

다중 엔진 확장 = 공용층은 **한 번**, 어댑터는 **엔진마다**.

## 2. 다른 엔진의 현재 텍스트 구조 (실측)

| 엔진 | 폰트 추상화 | 이미 있는 CJK | 배율 개념 |
|---|---|---|---|
| **SCUMM** | `CharsetRenderer` 계층 8종 | 모드 9종 (`loadCJKFont`) | `_textSurfaceMultiplier` |
| **SCI** | `GfxFont` 가상 클래스 (`getCharWidth/draw/drawToBuffer/isDoubleByte`) | **`GfxFontKorean`, `GfxFontSjis` 이미 존재** — `cache.cpp:71` 에서 폰트 ID 별 선택 | `GfxScreenUpscaledMode` (480×300, 640×400) |
| **AGI** | `GfxFont` 단일 클래스, `_fontData` 비트맵 포인터 | 없음 | 없음 |

SCI 가 가장 좋은 두 번째 대상이다:
- `GfxFont` 가 이미 가상 인터페이스라 `GfxFontHiRes : public GfxFont` 하나 더 넣으면 된다
- `GfxFontKorean` 이 있어 "한국어 폰트를 어떻게 붙였나"의 upstream 관례가 코드로 남아 있다
- `_upscaledHires` 가 이미 있어 배율 서피스 개념을 새로 만들 필요가 없다

AGI 는 가장 단순하지만(폰트 = 8×8 비트맵 포인터 하나) 배율 서피스가 없어
어댑터를 처음부터 짜야 한다. SCI 뒤에 한다.

## 3. 라틴 — 무엇이 달라지나

원본에 라틴 처리가 **이미 부분적으로 있다**: `_korTtfLatin`(10회),
`svfnLatin`(18회), 맵의 `[latin]` 섹션(8회). "한국어 게임에서 라틴 글자가
섞일 때"를 위한 것이라 **한국어 게임에서만** 켜진다.

목표 1 은 이것을 뒤집는다: **영어판 게임에서도** hi-res 폰트를 쓴다.
설계에 미치는 영향:

1. **게이트가 언어가 아니라 설정**이 된다. `isHiResText()` 는
   `_language == KO_KOR` 을 보지 않는다. 폰트 맵이 있으면 켜진다.
2. **코드포인트 경로 하나**를 쓴다. 라틴도 UTF-8에서는 여러 바이트일 수 있다.
   바이트 폭으로 문자 종류나 폰트를 선택하지 않는다. 구형 `[latin]` 옵션은
   호환 데이터로 격리하고 신규 API의 문자 분류 기준으로 삼지 않는다.
3. **회귀 대조군이 바뀐다.** 지금 `en-*` 타깃은 "우리 코드가 닿지 않는 대조군"
   이었다. 라틴 hi-res 가 켜지면 `en-*` 도 변경 대상이 된다. **`en-*-plain`
   (hi-res 끔) 타깃을 따로 둬야** 대조군이 유지된다.
4. **게임 원본 폰트의 메트릭 존중.** 영어 게임은 폰트마다 글자 폭이 다르다
   (가변폭). hi-res 폰트가 원본 advance 를 따르지 않으면 대사가 말풍선을
   넘친다. 원본의 `[latin] metrics=bitmap` 옵션이 이 문제를 이미 알고 있었다.

## 4. 새 파일 구조

```
graphics/hires_text/                  ★ 공용층. 엔진 무관.
  font_map.cpp/.h                     폰트 맵(.map) 파서       ← loadKorTtfMap, Pick, resolveKorTtfPath
  font_svfn.cpp/.h                    SVFN 비트맵 포맷         ← parseSvfnHeader, loadSvfnLatin, getSvfnWidth
  font_ttf.cpp/.h                     FreeType 래핑 (#ifdef)   ← loadKorTtfFont, getKorTtfCharWidth
  glyph_renderer.cpp/.h               글리프 → Surface         ← drawKorTtfChar, drawSvfnGlyph, run 배치
  hires_text.h                        HiResTextConfig 구조체   ← loadKorTtfConfig

engines/scumm/
  hires_text_scumm.cpp/.h             ★ SCUMM 어댑터.  VirtScreen 합성, 수명, 커서/마우스 배율
  charset.cpp                         훅 몇 줄. upstream 원본에 가깝게
  gfx.cpp                             합성 호출 지점만

engines/sci/graphics/
  fonthires.cpp/.h                    ★ SCI 어댑터.  GfxFontHiRes : public GfxFont  (2차)

engines/agi/
  (3차, 별도 설계)
```

`graphics/` 에 두는 근거: `graphics/fonts/` 에 이미 `bdf`, `macfont`,
`dosfont`, `freetype` 등 엔진 무관 폰트 코드가 있다. upstream 관례와 일치한다.

### 공용층 인터페이스

**공용 렌더링의 기본 입력은 Unicode scalar value (`uint32`)다.**
바이트 인코딩은 어댑터 책임이다. 이것만으로 모든 문자의 조판이 해결되지는
않는다. 결합문자·커닝·양방향·복합문자는 향후 glyph run/cluster 계층이 필요하다.
아래 렌더 API는 초안이며 G1에 구현된 API가 아니다.

```cpp
// graphics/hires_text/hires_text.h
namespace Graphics {

struct HiResTextConfig {
	int    scale;          // 1..3
	bool   alpha;          // 커버리지 서피스 사용
	uint8  shadowMode;
	int8   shadowOffset;
	Common::String mapPath;
	Common::CodePage sourceEncoding;   // 게임 문자열의 인코딩. 어댑터가 씀, 공용층은 안 봄
};

// 글리프 하나의 메트릭. 가변폭의 단위.
struct GlyphMetrics {
	int16 advance;     // 펜이 다음 글자로 이동할 거리 (scale 배 픽셀)
	int16 bearingX;    // 펜 위치에서 글리프 비트맵 왼쪽 끝까지
	int16 bearingY;    // 베이스라인에서 비트맵 위 끝까지
	uint8 width, height;
};

class HiResFontSet {
public:
	bool load(const HiResTextConfig &cfg, const Common::FSNode &gameDir);
	void free();

	// 유니코드 코드포인트 하나를 dst 에 그린다.
	// 반환값은 advance. 가변폭이면 글리프마다 다르다.
	int drawGlyph(uint32 cp, Surface &dst, Surface *coverage,
	              int penX, int baselineY, byte color, int fontId);

	bool metrics(uint32 cp, int fontId, GlyphMetrics &out) const;
	int  fontHeight(int fontId) const;
	int  fontAscent(int fontId) const;
	bool has(uint32 cp, int fontId) const;
};

} // namespace Graphics
```

### 4-1. 인코딩 — 어댑터 경계에서 코드포인트로 (목표 4·6)

**원본의 한계 (실측)**: `charset.cpp:609`

```cpp
const int idx = (chr < 256) ? chr : get2byteCharIndex(chr);
```

글리프 인덱스가 **KSC5601 바이트 산술**(`(hi-0xB0)*94 + lo-0xA1`)로 직접
계산된다. 폰트 파일에 "이 글리프가 어느 문자인가"를 말하는 테이블이 없다.
그래서 UTF-8 문자열을 넣을 방법이 없고, 라틴은 `chr < 256` 이라는
DBCS 가정으로 갈라진다.

**새 구조**:

```
게임 바이트열 ──▶ [어댑터: 디코더] ──▶ uint32 코드포인트 ──▶ [공용층: 글리프 조회 + 렌더]
                  ▲ 여기서만 인코딩을 안다
```

- **디코더는 어댑터에 있다.** SCUMM 은 `_language`/설정에서 `sourceEncoding`
  을 정하고, `Common::U32String(bytes, sourceEncoding)` 로 코드포인트를 얻는다.
  ScummVM 에 이미 `decodeWindows949/932/936/950/Johab/UTF8` 이 있다
  (`common/str-enc.cpp`). 변환 테이블은 재사용하되 엔진별 제어 토큰, 길이,
  잘못된 입력 처리 및 원본 바이트 오프셋 추적은 어댑터에서 구현·검증해야 한다.
- **KSC5601 번역은 그대로 된다.** `sourceEncoding = kWindows949` 로 디코드하면
  기존 `korean.trs` 바이트가 유니코드 코드포인트로 나온다. 폰트 조회는
  코드포인트로 하니 폰트 파일이 KSC 순서든 유니코드 순서든 상관없다.
- **UTF-8 선택 문법은 `[encoding] codepage=utf8`** 이다. 파서는 이 설정을
  읽지만 번역 입력 지원은 별도 S 단계다. 한 줄 설정만으로 엔진이 UTF-8을
  처리하지는 않는다. UTF-16은 LE/BE·BOM·surrogate pair·길이 명시 버퍼를
  지원해야 하며 NUL 종료 바이트 문자열에 직접 넣지 않는다. G1에는 미구현.
- **폰트 파일에 코드포인트 → 글리프 인덱스 테이블(cmap)이 들어간다.**
  SVFN v2 헤더에 cmap 오프셋을 추가한다. 기존 v1 파일은 헤더 codepage와
  어댑터가 지정한 실제 배열 순서(라틴/한글 등)를 확인해 매핑을 합성한다.
  모든 v1을 KSC5601로 간주하면 라틴·일본어 폰트가 깨진다.

**제어 토큰을 버리지 않는다.** 유효한 UTF-8에 FE/FF가 없다는 사실만으로
SCUMM 문자열 전체가 안전해지는 것은 아니다. 엔진 버전별 opcode와 길이·바이너리
인수를 먼저 식별하고, 텍스트 구간만 디코드하며 토큰 순서와 위치를 보존한다.
SJIS의 trail byte가 `@`일 수도 있으므로 전체 바이트열에서 `@`를 제거해서도
안 된다. UTF-16 입력은 별도 컨테이너 경계에서 디코드한다.

**DBCS 가정이 남는 곳**: upstream 자체 코드(`is2ByteCharacter`,
`_2byteWidth`, `checkSJISCode`)는 건드리지 않는다. 우리 공용층·어댑터
안에서만 가정을 없앤다. upstream 경로는 R1 처럼 정리만 한다.

### 4-2. 가변폭 + 알파 비트맵 — SVFN v2 (목표 5·7·8)

**원본에 이미 절반이 있다 (실측)**: `parseSvfnHeader()` 가 `bpp = 1 | 8`,
`flags & 1 = variable`, 글리프당 4바이트 `metrics` 를 읽는다. 즉 SVFN v1 은
**이미 8bpp 커버리지 + 글리프별 advance 를 담을 수 있다.** 목표 7·8 의
데이터 포맷은 존재한다. 부족한 건 셋이다:

| 부족 | v1 | v2 |
|---|---|---|
| 문자 매핑 | 없음 (KSC 순서 암묵) | **cmap 테이블** (코드포인트 → 인덱스) |
| 메트릭 | advance 만 (4바이트 중 1) | advance, bearingX, bearingY, width |
| 글리프 크기 | 전부 `cellW×cellH` 고정 | 글리프별 `width×height` (여백 안 저장) |

**미려한 폰트를 TTF 없이 (목표 8)**: SVFN v2 8bpp 는 **TTF 를 오프라인에서
렌더한 결과를 저장한 것**이다. FreeType 은 폰트를 굽는 도구(`tools/`) 에만
필요하고, 런타임 ScummVM 은 8bpp 픽셀을 읽어 알파 블렌딩만 한다. 따라서:

- Windows/Linux/macOS 데스크톱: TTF 직접 (FreeType) 또는 SVFN
- FreeType 없는 빌드: 동일 크기·힌팅·합성 조건에서 같은 글리프 커버리지 재현 목표.
  CLUT8 전용 출력은 RGB와 같은 계조를 보장하지 못하므로 양자화/디더 정책이 필요.
- 래스터라이즈 비용은 줄지만 파일 I/O·메모리·캐시 비용은 별도로 측정한다.

**결론: SVFN v2 가 주 포맷, TTF 는 편의 기능.** 원본은 반대였다(TTF 주,
SVFN 은 "TTF 없을 때 대체"). 순서를 뒤집는다. 이렇게 하면 no-FreeType 빌드가
2등 시민이 아니라 기준 구성이 된다 — upstream 이식성 요구와 정확히 맞는다.

**가변폭의 어댑터 측 함정 — 게임 원본 메트릭과의 충돌**: 게임 스크립트는
원본 폰트 폭으로 줄바꿈 위치와 말풍선 크기를 정한다. hi-res 폰트가 다른
advance 를 쓰면 텍스트가 상자를 넘친다. 원본의 `[latin] metrics=bitmap`은 **비트맵 폰트 자체의 advance**를 선택하며,
`ttf`는 TTF 쪽만 선택한다. 둘을 같은 스위치로 합치면 기존 맵 동작이 바뀐다.
신규 `[render] metrics=font|game`은 모든 문자에 적용하는 어댑터 정책이다:

```
metrics=font   폰트의 advance를 사용 (명시적 선택)
metrics=game   게임의 advance를 사용 (안전한 기본값; 측정/줄바꿈/출력에 동일 적용)
```

공용층은 두 값을 다 제공하고(`GlyphMetrics.advance` vs 어댑터가 아는 게임 폭),
어느 걸 쓸지는 어댑터가 정한다.

**엔진이 아는 것**: `HiResFontSet` 하나와 `Surface` 두 개(텍스트, 커버리지),
그리고 자기 문자열의 인코딩.
**엔진이 하는 것**: 바이트 → 코드포인트 디코드, 그 서피스를 자기 화면에
합성. 그게 어댑터다.

### SCUMM 어댑터

```cpp
// engines/scumm/hires_text_scumm.h
struct ScummHiResText {
	Graphics::HiResTextConfig cfg;
	Graphics::HiResFontSet    fonts;
	Graphics::Surface         text;       // 기존 _textSurface 역할
	Graphics::Surface         coverage;   // 기존 _korAlphaSurface
	Common::Rect              dirty, keep;

	bool enabled() const { return cfg.scale > 1 || fonts.loaded(); }

	// 바이트열 → 코드포인트. 인코딩을 아는 유일한 곳.
	// SCUMM 제어코드(0xFE/0xFF/@)는 호출자가 이미 걷어냈다고 가정.
	uint32 decodeNext(const byte *&p, const byte *end) const;

	// 이 문자에 어떤 advance 를 쓸지 — 폰트 것인가 게임 것인가
	int advanceFor(uint32 cp, int gameFontWidth, int fontId) const;

	void clearBand(const VirtScreen *vs);   // 스코프 클리어 (MI2 동사 교훈)
	void composite(VirtScreen *vs, int x, int w, int top, int bottom, byte *dst);
};
```

`ScummEngine`에는 어댑터 상태 하나를 둔다. 위 API는 구현 전 초안이다.
디코더는 인코딩마다 동작하며 Unicode 경로가 `is2ByteCharacter`에 의존해서는
안 된다. 활성화는 배율 OR 폰트 로드 여부가 아닌 명시적 정책·백엔드 지원·
리소스 로딩 성공을 함께 확인해야 한다.

## 5. 이름

`Korean`/`Kor`/`CJK` 접두 전부 → `HiRes`. 주어가 언어가 아니라 해상도다.

| 원본 | 새 이름 |
|---|---|
| `isKoreanHiRes()` | `_hiRes.enabled()` |
| `_koreanHiResScale` | `_hiRes.cfg.scale` |
| `_korAlphaSurface` | `_hiRes.coverage` |
| `loadKorTtfMap` | `Graphics::HiResFontMap::load` |
| `drawKorTtfChar` | `Graphics::HiResFontSet::drawGlyph` |
| `korean_hires_scale` (설정) | `hires_text_scale` |
| `korean_alpha_text` | `hires_text_alpha` |
| `korean_ttf_map` | `hires_text_map` |

설정키는 `korean_*` 호환 별칭을 단독 커밋으로.

## 6. 커밋 시리즈

### R — upstream 정리 (기능 없음)
- **R1** `is2ByteCharacter` 단일화 — 완료 (`fork/r1-is2byte`)
- **R2** `clearTextSurface(vs)` 스코프 — 조건부

### G — 공용층 (`graphics/hires_text/`). 어느 엔진도 아직 안 씀
| # | 내용 | 원본 | 검증 |
|---|---|---|---|
| G1 | `HiResTextConfig` + 폰트 맵 파서 (GlyphMetrics는 G2) | `loadKorTtfMap`, `Pick`, `resolveKorTtfPath` | 단위 테스트 — 맵 파싱 |
| G2 | **SVFN v2 로더** — cmap, 글리프별 메트릭·크기. v1 은 실제 codepage/배열 순서로 cmap 합성 | `parseSvfnHeader`, `loadSvfnLatin` | 단위 테스트 — v1/v2 헤더, cmap 조회 |
| G3 | 8bpp 커버리지 글리프 렌더러 (SVFN) — **주 경로** | `drawSvfnGlyph` | 단위 테스트 — 알려진 글리프 픽셀, 알파 값 |
| G4 | TTF 로더 + 렌더 (`#ifdef USE_FREETYPE2`) — 편의 경로 | `loadKorTtfFont`, `drawKorTtfChar` | 양쪽 빌드. no-FreeType 에서 G1~G3 만으로 완전 동작 |
| G5 | `tools/svfn_bake` — TTF → SVFN v2 굽기 (FreeType 은 여기서만 필수) | 신규 | 구운 파일을 G2 로더가 읽는지 |

**G3 가 G4 앞이다.** 원본과 순서를 뒤집었다. no-FreeType 이 기준 구성이다.

G 시리즈는 **엔진 회귀에 영향이 0** 이어야 한다. 아무도 호출하지 않으니까.
그래서 ScummVM 의 `test/` 단위 테스트 프레임워크로 검증한다. 이게 upstream
리뷰에서 "이 코드가 맞다"를 보이는 가장 싼 방법이다.

### S — SCUMM 어댑터
| # | 내용 | 회귀 기대 |
|---|---|---|
| S1 | `ScummHiResText` 구조체 + 설정 읽기 + `enabled()` | 0 |
| S2 | **`decodeNext()`** — 바이트→코드포인트. KSC5601 먼저, `is2ByteCharacter` 호출을 여기 하나로 | 0 (아직 안 그림) |
| S3 | 텍스트 서피스 배율 + 합성 훅 | hi-res 타깃만 변화 |
| S4 | 글리프 그리기 훅 (`CharsetRenderer` → `_hiRes.fonts.drawGlyph(cp)`) | 한국어 타깃 변화 |
| S5 | **가변폭** — `advanceFor()`, `metrics=font/game` 정책 | 자막 줄바꿈 확인 |
| S6 | **라틴 경로** — 영어판에서 hi-res 켜기 | `en-*` 변화, `en-*-plain` 0 |
| S7 | 알파 합성 | alpha 타깃 |
| S8 | **UTF-8 입력** — `sourceEncoding=kUtf8`, 제어코드 선처리 | UTF-8 `.trs` 테스트 파일 |
| S9 | 텍스트 수명 (`clearBand`, room 전환, keep) | MI2 동사 유지 |
| S10 | 커서/마우스 배율 | 측정 |
| S11 | GUI 저장/복원, 세이브 | F5 메뉴 |
| S12 | 설정키 호환 별칭 | 기존 ini 부팅 |

### C — SCI 어댑터 (S 완료 후)
| # | 내용 |
|---|---|
| C1 | `GfxFontHiRes : public GfxFont` — `GfxFontKorean` 을 본떠 `cache.cpp` 에 등록 |
| C2 | `_upscaledHires` 와 배율 연동 |
| C3 | SCI 회귀 타깃 구축 (SCI 게임 데이터 필요) |

### A — AGI 어댑터 (C 완료 후, 별도 설계)

## 7. 검증 절차 (커밋마다 고정)

```
1. 빌드 v7/v8 on              ~/src/scummvm
2. 빌드 v7/v8 off             /tmp/svm-r1
3. 빌드 no-FreeType           ~/src/scummvm-noft      (G3 이후)
4. 단위 테스트                 make test               (G 시리즈)
5. 회귀 캡처                   regress.sh              (S 시리즈)
6. 프레임 덤프 A/B             fbdump.sh + fbview.py --diff
7. 대조군 0 변화               ja-* 6종 + en-*-plain
```

7 이 upstream 증거다. **라틴 hi-res 도입 뒤에는 `en-*-plain` 이 대조군**이다.

## 8. 하지 않을 것

- fp 테이블 / `#define` — GDB 심볼 보존
- `drawStripToScreen` 재구조화 — 본체 병합 후
- v7/v8 (`string_v7.cpp`) 수정 — 검증 얇음
- **AGI 를 SCI 전에** — 배율 인프라가 없어 비용이 크다

## G1 구현 상태 (2026-09-05)

- 브랜치 `hires-text`: master `41ac2b31847` → R1 `2ea6270e615` → G1 `d8bf38f6262`.
- G1은 맵 파서만 구현. 엔진 연결·폰트 로더·Unicode 번역 입력·렌더링은 아직 없음.
- 신규 26개 포함 전체 429개 테스트 통과: 기존 FreeType 구성 및 별도
  `~/build/scummvm-hires-g1-noft`의 모든 엔진/FreeType 비활성 구성.
- Linux 전체 빌드 및 `scummvm --version` 실행 성공. Windows 빌드하지 않음.
- 기존 `[latin]` 옵션을 호환 구조체로 격리. 신규 `[render] metrics=font|game`은
  바이트 폭에 무관하다. 숫자 범위/오버플로 검증 및 사용자 배율 적용 전 논리 크기 보존.
- 실제 파서 API/예제: 소스 `graphics/hires_text/README.md`. 위 렌더 API는 후속 설계 초안.
- 다음 G2: SVFN 로더·Unicode cmap·글리프별 메트릭 및 기존 배열 순서 호환.

## 9. 다음 행동

1. `origin/master` 에서 `hires-text` 브랜치 생성
2. R1 체리픽
3. **G1** — `graphics/hires_text/font_map.cpp` + 단위 테스트. 엔진 무관임을
   빌드로 증명 (SCUMM 을 끄고도 컴파일돼야 한다)
4. G2~G4
5. S1 부터

G1 이 끝나면 "공용층이 정말 엔진 독립인가"가 빌드 결과로 나온다.
`--disable-all-engines` 로 빌드해서 `graphics/hires_text/` 가 컴파일되면 증명이다.
