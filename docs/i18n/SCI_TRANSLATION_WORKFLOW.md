# SCI 게임 번역 절차 (LB1 한국어화 기준)

Laura Bow 1 (The Colonel's Bequest, SCI0, DOS 1.000.046) 한국어판을 만든
과정을 다른 SCI 게임에도 쓸 수 있게 정리한 문서. 결과물은 이 포크의 UTF-8
번역 형식(`text.NNN` + `sci-<lang>.str` + `hires_text.map`)이다.

- 도구: harness 저장소 `harness/i18n/lb1/` (이름은 lb1이지만 SCI0 공통).
- 작업 파일: `runs/lb1-sheet/` (시트, 번역 청크), `runs/c43/` (스크립트 분류),
  `runs/c42/` (패키지와 검증 스크린샷).
- 관련 문서: [SCRIPT_STRINGS.md](SCRIPT_STRINGS.md) (`sci-<lang>.str` 형식),
  [HIRES_TEXT_MAP.md](HIRES_TEXT_MAP.md) (TTF 글꼴 지정),
  [SCITRS_FORMAT.md](SCITRS_FORMAT.md) (기존 한글판 `sci.trs`, 폐기된 형식).

## 전체 흐름

```
영문 게임 ─┬─ sciext.py ──────────── TEXT/SCRIPT 원본
           └─ dump_script_strings ── SCRSTR 로그 (스크립트 문자열 id)
                       │
                  mklb1sheet.py ──── 번역 시트 (xlsx → Google Sheet)
                       │  + 기존 번역(sci.trs) 정렬
                       │  + 배경 조사 → 지침(BRIEF)
                  lb1split.py ────── 방 단위 청크 8개
                       │  Sonnet 에이전트 8개 병렬
                  시트에 병합 + check()
                       │
     classify_strings.py (디컴파일 스크립트로 SCRIPT 탭 분류)
                       │
     mklb1pkg.py (+ lb1buffers.py 고정 버퍼 검사) ── 패키지
                       │
     게임 내 검증 (lb1verify.py) → zip + sha256 배포
```

## 1. 대상 버전 확정

- `RESOURCE.MAP` 크기·md5, 게임 내 버전 문자열(LB1: `1.000.046`)을 적어 둔다.
  번역 패키지는 이 버전에만 맞는다(README에 md5를 적는다).
- SCI0인지 SCI01/SCI1-early인지 확인한다. 맵 형식과 압축 방식이 다르다.
- [sluicebox/sci-scripts](https://github.com/sluicebox/sci-scripts)에 같은
  버전의 디컴파일 스크립트가 있는지 본다(LB1은 `cb-dos-1.000.046`). 8단계와
  9단계는 이것이 있어야 정확하다.
- 게임 폴더에 Sierra 패치 파일(`TEXT.NNN`, `SCRIPT.NNN`)이 있는지 본다.
  있으면 볼륨 안의 같은 리소스보다 우선한다(LB1: `TEXT.052`, `SCRIPT.052`).

## 2. TEXT 리소스 추출

```
python3 harness/i18n/lb1/sciext.py <gamedir> <outdir> text script
```

- 6바이트 맵(SCI0 계열). 볼륨 번호의 비트 위치는 SCI0이 26,
  SCI01/SCI1-early가 28인데, 실제로 존재하는 `RESOURCE.00N` 파일로 자동 판별한다.
  처음에 이것을 고정값으로 두었다가 리소스가 엉뚱하게 풀렸다.
- 압축: 0 없음, 1 SCI0 LZW(LSB 우선), 2는 SCI0이면 Huffman이고 이후 버전에서는
  LZW1(MSB 우선, early change). 엔진 `decompressor.cpp`를 옮긴 것.
- 출력은 헤더 없는 원본 페이로드(`text.NNN`). 패치 파일은 2바이트 헤더
  (`83 00` TEXT, `82 00` SCRIPT)가 붙어 있으니 떼고 읽는다.

## 3. 스크립트 문자열 id 얻기

스크립트 안의 문자열(인벤토리 이름, 일부 대사, 타이틀)은 패치할 수 없어서
`sci-<lang>.str` 표로 바꾼다. id는 엔진이 `Script::identifyOffsets()`로 매기는
번호여야 하므로 **엔진으로 덤프한다**. 직접 파싱하지 않는다.

```ini
[g]
gameid=laurabow
dump_script_strings=true
```

게임을 한 번 실행하면 로그에 `SCRSTR<TAB>script<TAB>id<TAB>text` 줄이 나온다
(LB1: 2,362줄, `runs/lb1-sheet/dump.log`).

## 4. 번역 시트 만들기

```
venv/bin/python harness/i18n/lb1/mklb1sheet.py <gamedir> <extracted> dump.log LB1_translation.xlsx
```

- 탭: `안내` (작업 규칙), `TEXT` (키 `text.NNN#i`, 빈 문자열 제외, LB1 6,247행),
  `SCRIPT` (키 `script#id`, 2,361행).
- 원문은 cp437로 읽는다. 줄바꿈은 두 글자 `\n`, 제어 문자는 `\xNN`으로
  이스케이프한다. openpyxl은 제어 문자가 셀에 들어가면
  `IllegalCharacterError`를 낸다.
- 열: 서식 지정자(`%s %d` …), 같은 원문 중복 수, 상태 드롭다운
  (미번역/번역/검수완료/번역 안 함).
- Google Drive 커넥터는 큰 파일을 올리지 못하므로 xlsx는 사람이 직접 올린다.

## 5. 기존 번역 정렬 (있으면)

LB1은 옛 한글판 `sci.trs`(SCITRS, CP949)가 있었다. 리소스/인덱스로 원문과
맞춰 `lb1_ko_existing.json`(6,231쌍)을 만들고 시트에 `기존 번역` 열로 넣었다.
기존 번역은 **어투와 용어를 고정하는 기준**으로 쓰고, 그대로 믿지 않는다
(오역과 누락이 섞여 있다).

## 6. 배경 조사와 번역 지침

번역기에 주는 지침 파일을 먼저 만든다(`harness/i18n/lb1/lb1_brief.md`).
LB1 지침에 넣은 것:

- 게임 배경: 1925년 루이지애나 섬의 저택, 추리극, 막(Act) 구성.
- **인물과 관계**: 표기를 고정한다(Lillian → 릴리안). 이름에 성을 덧붙이거나
  바꾸지 않는다. 친족 호칭은 가계도를 조사해서 정한다. 대령은 릴리안의
  외삼촌이고, 에델은 루디·글로리아의 고모다.
- **인물별 말투**: 누가 반말/존댓말을 쓰는지, 특징적인 말버릇
  (글로리아의 dahling → "달링"). 사투리와 외국 억양은 흉내 내는 정도를 정한다
  (피피의 프랑스 억양은 흉내 내지 않고 해요체, 셀리의 남부 사투리는 가벼운
  사투리 어미).
- **용어집**: 아이템과 장소 이름. 인벤토리 이름은 여러 문장에서 되풀이된다.
- **문체**: 서술은 해라체. "당신"은 쓰지 않는다. UI와 안내는 "~하세요".
- **형식 규칙**: 서식 지정자, `\n` 개수, 앞뒤 공백, 따옴표 짝을 원문과 똑같이.

## 7. 기계 번역

### 7a. 로컬 Qwen 시험 (참고용)

```
lb1mt.py in.xlsx out.xlsx --existing lb1_ko_existing.json --prompt lb1_prompt.md \
         --workers 3 --cache mt_cache.json
```

측정 결과(100행 표본 검수, `audit_sample.tsv`):

| 엔진 | 결과 |
|---|---|
| spark qwen3.8-flash-next | 심각한 오류 약 4%(뜻 반대 1건, text.299에서 25행 영어로 되돌아감), 사소한 오류 약 13% |
| pc qwen3.8-27b | 한자·중국어 섞임 |

그대로 쓸 수 없다고 판단해서 Claude 배치 번역으로 바꿨다.

### 7b. Sonnet 배치 번역 (채택)

```
lb1split.py LB1_translation_full.xlsx sonnet/ 8
```

- 방(리소스 번호) 경계로 8개 청크 `in_NN.jsonl` (`{"key","res","en","old"}`).
  같은 방의 대사가 한 청크에 있어야 앞뒤 맥락이 이어진다.
- Sonnet 서브에이전트 8개를 동시에 돌린다. 각각 지침을 읽고
  `out_NN.jsonl`을 **입력과 같은 순서, 같은 줄 수**로 쓴다:
  `{"key","ko","why"}`. `why`는 `keep`/`term`/`style`/`fix`/`new` 중 하나이고,
  `fix`이면 무엇이 틀렸는지 `note`에 한 줄로 적는다.
- 각 에이전트는 끝내기 전에 줄 수, 키 순서, 형식 규칙을 스스로 검사한다.
- 결과를 시트의 `Sonnet 번역 / Sonnet 처리 / Sonnet 메모` 열에 병합하고
  `lb1mt.check()`로 다시 검사해서 `Sonnet 점검` 열에 적는다.
  검사 항목: 서식 지정자, `\n` 수, 앞뒤 공백, 한자, "당신".
- LB1: 6,338행 처리, 그중 1,029행이 기존 번역의 오역 수정(`fix`).
- 짧은 응답("Okay.", "Huh?")은 일괄로 손대지 않고 나중에 따로 본다.

## 8. 스크립트 문자열 분류

SCRIPT 탭의 문자열 대부분은 화면에 나오지 않는다(객체 이름, 파일 이름,
비교용 키). 잘못 번역하면 로직이 깨진다. 디컴파일 스크립트에서 각 문자열이
어디에 쓰이는지 보고 분류한다.

```
classify_strings.py --dump dump.log --src <sci-scripts>/src --rules lb1_string_rules.tsv --out lb1_script_strings.tsv
apply_classes.py <in.xlsx> lb1_script_strings.tsv new_translations.tsv <out.xlsx>
```

- `DISPLAY`: 화면에 나온다. 번역한다.
- `INTERNAL`: 객체 이름, 비교 키 등. `번역 안 함`.
- 위험 표시(`REWRITTEN`, `PARSER`): 화면에 나오지만 표에 넣으면 안 되는 것.
  예를 들어 스크립트가 실행 중에 이 버퍼에 다른 TEXT를 `Format`으로 덮어쓰는
  인벤토리 이름, 파서 입력줄에 미리 채워 넣는 단어. 이런 행은 `번역 안 함`으로
  두고 TEXT 쪽 번역이 버퍼에 들어가게 한다.
- 규칙은 `lb1_string_rules.tsv`에 근거(스크립트 파일과 줄)와 함께 적는다.
  게임마다 새로 써야 한다.

## 9. 고정 버퍼 검사

UTF-8 한글은 글자당 3바이트다. 화면에서는 짧아도 바이트로는 길어져서
스크립트가 잡아 둔 고정 크기 버퍼를 넘칠 수 있다.

- `lb1buffers.py`가 `(Format @buf …)`, `(Format (obj name:) …)`, `Printf`,
  `Print`를 찾아 버퍼 크기와 번역의 UTF-8 길이 + NUL을 비교한다.
  `mklb1pkg.py --check`가 이것을 호출한다.
- 실제 사고: 버전 문자열이 50바이트 버퍼를 넘쳐서 부팅 중에 멈췄다.
  회사 이름을 영어로 두어 해결했다. `text.000#3/#7`(인벤토리 이름)은
  "빈 크래커통", "장전 총 "처럼 줄였다.
- 버퍼를 넓히는 엔진 쪽 방법(표시 시점 치환)은 보류 중이다.

## 10. 패키지 빌드

```
mklb1pkg.py --xlsx LB1_translation_full_c43.xlsx --out pkg/
mklb1pkg.py --xlsx LB1_translation_full_c43.xlsx --out pkg/ --check
```

- `text.NNN`: 원문과 다른 문자열이 있는 리소스마다 하나. 원래 NUL 목록을 그대로
  두고 비어 있지 않은 문자열만 바꾼다(빈 번역이면 영어). UTF-8 NFC, 헤더 `83 00`.
  LB1: 225개.
- `sci-ko.str`: 상태가 번역/검수완료/미번역이고 번역이 원문과 다른 SCRIPT 행.
  LB1: 91개. 이 파일이 있으면 UTF-8 게임으로 인식된다.
- `OVERRIDES`: 시트로는 알 수 없는, 스크립트 사정 때문에 바꿔야 하는 문자열.
- `hires_text.map`: `hires_text_log=true`로 게임을 돌려 쓰이는 글꼴 id를 모두
  찾은 뒤 id마다 TTF를 지정한다. LB1 설정:

  | 글꼴 id | 쓰임 | 설정 |
  |---|---|---|
  | 0 | 상태줄, 메뉴, 파서, 시스템 대화상자 | 나눔고딕 Bold |
  | 1, 4 | 대사와 서술 상자 | 고운바탕 Bold, size=18, baseline=0 |
  | 8 | 인트로 인물 이름(공백으로 줄 맞춤) | size=18, metrics=game |
  | 40, 41 | 자막과 막 제목(원래 글꼴이 18px) | size=22/28, cell=glyph |

- `README.ko.txt`: 대상 버전과 md5, 설치 방법(`language=ko`,
  `rgb_rendering=true`), 글꼴 라이선스(OFL), 기존 번역자 크레딧.

## 11. 게임 안에서 검증

```ini
language=ko
rgb_rendering=true
hires_text_log=true
```

- **`rgb_rendering=true`가 없으면 TTF 알파 블렌딩이 보이지 않는다.** SCI 화면이
  256색(CLUT8)이면 반투명 가장자리를 표현할 수 없다. OpenGL 그래픽 모드로
  바꿔도 이 설정이 꺼져 있으면 효과가 없다.
- 복사 방지 화면: 스크립트 414의 locals에서 정답 표를 읽어 자동으로 푼다
  (`lb1lib.solve_protection`).
- `lb1verify.py`는 인트로를 넘기고 1막 대사, look, 인벤토리, 모르는 단어,
  F5 저장 창, 상태줄을 캡처한다. 결과는 한 장짜리 모음 이미지로 확인한다.
- 좌표 주의: 제어/우선순위 평면 덤프는 화면 행 기준이다.
  그림 y = 화면 y − 10(상태줄 높이).

## 12. 배포

- zip과 `.sha256`을 hpz2 `~/work/scummvm/dist/`에 올린다
  (예: `LB1_Korean_UTF8_20260928.zip`).
- Windows 빌드에는 exe 옆에 포터블 `scummvm.ini`
  (`extrapath=.`, `rgb_rendering=true`)를 넣는다.

## 번역 품질 체크리스트 (LB1에서 실제로 나온 것)

- **같은 단어의 다른 뜻**: "crank"는 욕이 아니라 인벤토리 아이템(크랭크)이다.
  스크립트나 방 맥락으로 확인한다.
- **친족 호칭**: 고모/외삼촌/외숙모를 원작 설정으로 확인한다.
- **조사**: 이름 뒤 "는(은)" 같은 형태가 남는 경우(예: "릴리안는(은)").
  `%s` 뒤 조사는 받침을 모르므로 문장을 바꾸거나 "은(는)" 형식으로 통일한다.
- **서술의 2인칭**: 서술문에서 너/네를 쓴 행이 134개 남아 있다. 정리 대상.
- **형식**: 따옴표 짝, 쉼표 중복(`text.031#27`), `\n` 위치.
- **메뉴 막대**는 스크립트 문자열이 아니라 엔진/리소스 경로가 달라서
  아직 영어로 나온다.

## 남은 일 (LB1)

- F5 저장 창과 상태줄 표시 확인.
- `text.031#31` 오역, "릴리안는(은)" 조사.
- 메뉴 막대 한글화.
- 고정 버퍼 우회(표시 시점 치환): 보류.
