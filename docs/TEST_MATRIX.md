# ScummVM 한국어 hi-res 테스트 체크리스트

마지막 갱신: 2026-09-05 / HEAD `2d290814`

축이 7개라 전조합은 1440가지다. 전수는 무의미하므로 **축 하나씩 흔드는
대표 조합**만 돌린다. 한 게임을 여러 설정으로 반복하는 것이 핵심이다.

---

## 1. 미해결 문제

| # | 증상 | 게임 | 상태 | 다음 할 일 |
|---|---|---|---|---|
| A | LucasFilm 로고 뒤 섬 이미지가 검게 나옴 | MI2 | **해결 `2d290814`** | alpha true-color 팔레트 페이드에서 전체 dirty 필요 |
| B | 난이도 화면 한글이 그려졌다 지워짐 | MI2 | **해결 `beb6ed43`** | `ignoreCharsetMask` 글자를 clear에서 보존 |
| C | v2 겹침이 정말 고쳐졌는지 미확정 | Zak | 재현 안 됨 | 대사 있는 장면에서 확인 |
| D | `scrollEffect` 4방향 배율 미보정 | v5 전반 | **보류** | hi-res 도달 0건. v5 스크롤 전환 나오면 재개 |
| E | v7 게임은 hi-res 합성에서 제외 | Full Throttle | 무해 판정 | v7 지원 시 재검토 |
| F | Windows 실제 화면 미검증 | 전체 | 환경 제약 | GPU 있는 환경 필요 |

## 2. 축과 대표 조합

| 축 | 값 |
|---|---|
| 폰트 소스 | TTF(FreeType) / SVFN 8bpp / SVFN 1bpp / 게임 원본(순정) |
| 라틴 | 게임 비트맵 / SVFN 반각 / TTF 라틴 |
| 합성 | 알파 32bpp(OpenGL 필수) / CLUT8 컬러키 |
| 배율 | 1(=순정 대조) / 2 / 3 |
| 렌더 | char / string |
| 그림자 | game / none / drop / outline / stroke |
| 폭 | 고정 / 가변(flags bit0) |

**대조군을 반드시 함께 돌린다.** `*-vanilla` 타겟(맵 없음, hi-res 꺼짐)이
"우리 회귀 vs 원래 그런 동작"을 가르는 유일한 수단이다. Indy3 잔상 때
이것 하나로 결론이 뒤집혔다.

## 3. 게임별 매트릭스

### MI2 (v5, 폰트 높이 8/9/12 → 셀 24/27/36)

| 타겟 | 폰트 | 합성 | 배율 | 확인할 것 |
|---|---|---|---|---|
| `mi2-plain` | 게임 원본 | - | 1 | **대조군**. 로고→섬 전환이 순정에서 정상인가 |
| `mi2-svfn` | SVFN 8bpp | 알파 | 3 | 문제 A/B 재현 |
| `m2-alpha` | TTF | 알파 | 3 | TTF 경로에서도 같은가 |
| `m2-noalpha` | TTF | CLUT8 | 3 | 알파가 원인인지 가름 |
| `m2-str` | TTF | 알파 | 3 | string 렌더 |

### Zak / Maniac (v2, 고정 8px 그리드)

| 타겟 | 폰트 | 합성 | 배율 | 확인할 것 |
|---|---|---|---|---|
| `zak-vanilla` | 게임 원본 | - | 1 | **대조군** |
| `zak-kor` | TTF | 알파 | 2 | 회귀 기준 79.7 |
| `zak-aa` | SVFN 8bpp | 알파 | 2 | 안티에일리어싱 |
| `zak-svfn` | SVFN 1bpp | 알파 | 2 | 1bpp 경로 |
| `zak-sh{non,dro,out,str}` | SVFN | 알파 | 2 | 그림자 4종 |
| `zak-shred` | SVFN | 알파 | 2 | `color=4` — 그림자가 보이는지 |
| `mm-bare` | 게임 원본 | 알파 | 1 | 회귀 기준 47.5 |

v0~v2는 `CharsetRendererV2::getCharWidth()`가 8 고정이라 **가변폭이 안 먹는다.**
스크립트가 8px 그리드에 의존하므로 이게 정답이다.

### Indy3 (v3, 높이 8/9)

| 타겟 | 폰트 | 폭 | 배율 | 확인할 것 |
|---|---|---|---|---|
| `i3-vanilla` | 게임 원본 | - | 1 | **대조군**. 잔상 판정에 결정적이었음 |
| `i3-multi` | TTF | 고정 | 3 | 회귀 기준 32.2 (±0.4) |
| `i3-var` | SVFN 8bpp | **가변** | 3 | 자간, verb 잔상 |
| `i3-jm` | SVFN | 고정 | 3 | 장미체 |
| `i3-latg` / `i3-latf` | - | - | - | 라틴 게임비트맵 vs 폰트 |

### Indy4 (v5, 높이 8/9/16 → 셀 24/27/48)

| 타겟 | 폰트 | 폭 | 배율 | 확인할 것 |
|---|---|---|---|---|
| `i4-multi` | TTF | 고정 | 3 | 회귀 기준 22.6 |
| `i4-var` | SVFN 8bpp | 가변 | 3 | 커서 배율(2배 30×30 → 3배 45×43) |
| `i4-2x` | SVFN | 가변 | 2 | 2배와 3배 비교 |

### Loom CD (v4)

| 타겟 | 확인할 것 |
|---|---|
| `loom-kor` | 방 전환 디졸브. **`dissolveEffect(1,1)`은 Loom만** — 정렬 함정이 여기 있었다 |

### Day of the Tentacle (v6, DOS Floppy Korean)

| 타겟 | 폰트 | 배율 | 확인할 것 |
|---|---|---|---|
| `dott-kor` | 원본 한글 비트맵 8개 | 1 | V2 리소스 수정형 대조군: 인트로 대사, 동사/문장줄, 대화 선택, 메뉴 |

- 데이터: `/home/thkim/games/dott/Day Of the Tentacle (DOS Floppy)`
- 현재 바이너리 탐지: `Day of the Tentacle (Floppy/DOS/Korean)`.
- 사용자 한글 출력 확인. `korean.trs` / `tentacle.dat` 없이 리소스에 한글 포함.
- 원본 폰트 높이: 8/11/12/18/27. `korean06.fnt`는 없으므로 번호가 연속이라고 가정하지 않는다.
- `dott-kor-hr`: 별도 디렉터리에 NanumGothic 2x 맵/폰트 생성. 4개 프레임에서 배경/팔레트 동일, charset 2/5/6 대체 출력 확인. **미통과**: 0x5e 말줄임표의 Unicode 매핑과 원본 비트맵 fallback 배율 문제. 상세: `/home/thkim/games/dott-ft-regression/REPORT.md`.
- `dott-kor` 원본은 map-free로 유지한다. 인트로 외 UI 회귀는 아직 미검증.
- 새 기준 캡처 필요: 이전 타깃 목록의 결과를 새 목록과 직접 비교하지 않는다.
- 개별 프레임 비교: `bash ~/games/fbcompare.sh <binA> <binB> <frame> dott-kor`.
- 실행 확인: `bash ~/games/smoke-target.sh dott-kor <output-dir>` (타깃별 임시 설정, 생존/로그/캡처 보존).

### Full Throttle (v7, DOS Version A Korean)

| 타겟 | 폰트 | 배율 | 확인할 것 |
|---|---|---|---|
| `ft-kor` | 원본 한글 9x9 비트맵 | 1 | v7 대사/메뉴, SMUSH 영상 자막, 전환 — hi-res 지원 여부와 분리 |

- 영어 원본: `/home/thkim/games/ft-en`; 한국어 적용본: `/home/thkim/games/ft-kor`.
- 원본 ZIP: `/home/thkim/games/dl/full-throttle-dos.zip` (262665469 bytes, ZIP CRC 통과).
- 패치: `british-choi/ScummVM-Kor-Trs/Full Throttle (DOS)`, Revision 2. `korean.trs` (`SCVMTRS `), `korean.fnt`, DATA/VIDEO 영상 자막.
- 탐지: `Full Throttle (Version A/Korean)`. 구 전용 실행기의 V1 `.dat`가 아니라 현재 ScummVM용 변환 패치다.
- `ft-kor-hr`: 1x 대체 맵/폰트 2개 생성·로딩 확인. SMUSH 100/200/300/400 출력·팔레트가 대조군과 동일하지만 HRTEXT 0건 — 새 렌더러 미연결. v7 배율 확대는 현재 소스가 차단한다.
- `bash ~/games/smoke-target.sh ft-kor <output-dir>`로 실행 확인. 전체 플레이/전투 회귀는 별도. 상세: `/home/thkim/games/dott-ft-regression/REPORT.md`.

## 4. 회귀 기준값

`cap11.sh` t=30, 평균 밝기. ±1.0 넘으면 회귀 의심.

| 타겟 | 기준 |
|---|---|
| mm-bare | 47.5 |
| zak-kor | 79.7 |
| i3-multi | 32.2 (±0.4) |
| i4-multi | 22.6 |

## 5. 매번 확인할 것

수정할 때마다 이 순서를 지킨다. 이 세션에서 어긴 항목마다 오판이 나왔다.

1. **빌드 에러 0 확인 후 캡처.** `ERRORS=$(wc -l < /tmp/berr.txt)` + 바이너리
   타임스탬프. 실패한 빌드로 캡처해 멀쩡한 수정을 두 번 롤백했다.
2. **프로세스가 살아남았는지 확인.** 계측 카운터만 보고 성공으로 판정했다가
   assert 크래시를 놓쳤다. `exit=134`는 SIGABRT다.
3. **대조군과 나란히.** `*-vanilla` 없이는 회귀인지 원래 동작인지 모른다.
4. **회귀 4종 통과.**
5. **화면을 직접 본다.** 픽셀 카운트가 스크린샷과 어긋나면 카운트가 틀렸다.

## 6. 스크립트

| 스크립트 | 용도 |
|---|---|
| `cap11.sh` | 1:1 정수배 캡처 — **간격 측정은 이것만** |
| `caploadv.sh` | 세이브 로드 후 캡처 |
| `loomrun2.sh` | 생존 확인 포함 실행 (`ALIVE=`, `crash_msg=`) |
| `disgdb.sh` / `disab.sh` | GDB 브레이크포인트 A/B |
| `dbggfx.sh` | gfx.cpp만 `-g -O0` 재컴파일 |
| `scrprobe.sh` | 게임 진행시켜 특정 경로 도달 확인 |
| `mksave.sh` | Alt+숫자 퀵세이브 |
| `bakeset.sh` | 폰트 세트 굽기 |
| `capwin.sh` / `winprobe.sh` | Wine 실행 |

세이브는 `~/.local/share/scummvm/saves/<target>.s0N` (`~/.config` 아님).
