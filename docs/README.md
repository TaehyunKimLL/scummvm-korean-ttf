# 문서 색인

이 폴더는 **작업 기록**입니다 — 조사, 계획, 측정 결과. 배포되지 않습니다.

**사용자용 설명서는 여기가 아니라 소스 트리 안에 있습니다:**

| 문서 | 대상 | 내용 |
|---|---|---|
| `scummvm/engines/scumm/HIRES_TEXT_SETUP.md` | **사용자·번역자** | ini 키, 맵 문법, 폰트 굽기, GUI 체크박스, 진단표 |
| `scummvm/engines/scumm/HIRES_TEXT.md` | 개발자 | 엔진 쪽 구조 |
| `scummvm/engines/scumm/HIRES_TEXT_DECORATIONS.md` | 개발자·번역자 | 외곽선·그림자, 플랫폼별 함정 |

소스 트리에 두는 이유는 upstream 기여 시 코드와 함께 가야 하기 때문입니다.

## 이 폴더의 문서

### 현행

| 파일 | 내용 |
|---|---|
| `BUILD_AND_TEST.md` | 빌드·테스트 환경. mingw PATH, Wine 부재, 하네스 사용법 |
| `TTF_DIRECT_PLAN.md` | TTF 직접 사용 — 1·2단계 완료, 나머지 설계 |
| `PLANE_ENCAPSULATION_PLAN.md` | 두 평면을 컴파일러가 강제하게 만드는 계획 |
| `OVERLAY_PLAN.md` | 오버레이 추상화 (완료, 커밋 표 포함) |
| `COMPOSITOR_PLAN.md` | 싱크 추상화 (완료, Mac 전제 오류 정정 포함) |
| `TEST_GAME.md` | 합성 게임 리소스 실험 — 검출·인덱스까지 성공, 미완 |
| `GUI_HIRES_TOGGLES.md` | GUI 체크박스 두 개 — 조사·측정·구현 결과 |

### 측정 기록

`ALPHA_PALETTE_CASES.md`, `GLYPH_AUDIT.md`, `MI2_VERB_LOSS.md`,
`FONT_FORMAT.md`, `OUTLINE_REFERENCES.md`, `NEEDED_GAME_DATA.md`,
`REGRESSION_HARNESS.md`

### 옛 문서 — 그대로 따라하면 동작하지 않음

| 파일 | 왜 |
|---|---|
| `KOREAN_TTF_SETUP.md` (892줄) | `korean_ttf_font`, `korean_ttf_size`, `korean_ttf_bold_font`, `korean_ttf_title_font`, `[map]` 섹션이 전부 제거됨 |
| `HIRES_TEXT_SETUP.md` (이 폴더) | 소스 트리 쪽 같은 이름 문서의 이전 요약본 |
| `REBUILD_DESIGN.md`, `REBUILD_PROGRESS.md`, `REFACTOR_PLAN.md`, `RESTRUCTURING_REVIEW.md`, `GUI_OPTIONS_DESIGN.md` | 당시 계획. 이후 구현되며 달라진 부분 있음 |

`GUI_OPTIONS_DESIGN.md`는 특히 주의 — "hi-res 관련 GUI 노출: 없음"이라고
적혀 있지만 체크박스 두 개가 이미 구현됐습니다.
