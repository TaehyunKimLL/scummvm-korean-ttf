# CJK 리팩토링 검증용 게임 데이터 — 현황

최종 갱신: 2026-09-05

## 확보 완료 — CJK 코드 경로를 실제로 타는 타깃

`scummvm --detect` 로 **일본어/한국어 판정을 실측 확인**한 것만 적는다.

| 타깃 디렉터리 | 탐지 결과 | CJK 모드 | loadCJKFont 분기 |
|---|---|---|---|
| `~/games/indy4ja` | Indy4 (**FM-TOWNS/Japanese**) | **모드 5** | `_isIndy4Jap` — 리소스 지연로드 |
| `~/games/mi1ja` | MI1 (**FM-TOWNS/Japanese**) | **모드 3** | FontSJIS, `GID_MONKEY` + `_curId==2` |
| `~/games/mi2ja` | MI2 (**FM-TOWNS/Japanese**) | **모드 3** | FontSJIS, `sjisFontHeightM2` |
| `~/games/loomja` | Loom (**FM-TOWNS/Japanese**) | **모드 3** | FontSJIS v3 |
| `~/games/loomtg16ja` | Loom (**PC-Engine/Japanese**) | **모드 4** | pce.cdbios FontSJIS |
| `~/games/loomtowns` | Loom (FM-TOWNS/**Korean**) | 모드 6 | 우리 한국어 경로 |

**FM-Towns 일본어판 zip 에는 `FMT_FNT.ROM`(262144 B)이 동봉돼 있다.**
모드 3 은 이 폰트 롬이 있어야 `FontSJIS::createFont()` 가 성공한다.

이로써 **모드 3 / 4 / 5 / 6 을 전부 실행 검증할 수 있다.**
앞선 문서에서 "모드 5 는 정적 분석만 가능" 이라 적은 제약이 해소됐다.

## 미확보

| 모드 | 대상 | 상태 |
|---|---|---|
| 5 (SegaCD JA) | MI1 Sega CD 일본어 | 컬렉션에 **영어판만** 존재. Indy4 JA 로 같은 분기를 검증하므로 **차단 요소 아님** |
| 7 (v7 JA) | The Dig 일본어 | 컬렉션에 없음 (영/불/독/이/스만) |
| 8 (ZH_TWN) | 중국어 번체 | 컬렉션에 없음 |
| 9 (ZH_CHN) | 중국어 간체 | 컬렉션에 없음 |
| 1 (Rebel1 SegaCD) | — | SMUSH 경로. 별도 판단 |

모드 7/8/9 는 `string_v7.cpp` 의 별도 렌더러다. upstream PR 본문에
"미검증" 으로 명시하고, 해당 코드 경로는 **건드리지 않는 것**이 안전하다.

## 비CJK 대조군 (지우지 말 것)

영어판이라 CJK 분기는 안 타지만 `TownsScreen` 레이어 경로를 타므로,
단계 F1(`ScummOutput`) 회귀에서 "CJK 무관 회귀" 검출용으로 쓴다.

`~/games/` 의 `mi1towns` `mi1segacd` `mi2towns` `indy3towns` `indy4towns`
`zaktowns` `loomtg16` (전부 FM-TOWNS/SegaCD/PC-Engine **영어판**)

## 다운로드 방법 — archive.org 대용량 zip 부분 추출

`The_Complete_ScummVM_Collection_v2` 는 **106 GB 단일 zip** 이다.
전체를 받을 필요 없이 ZIP64 중앙 디렉터리를 읽어 필요한 항목만 뽑는다.
`~/games/iafetch.py` 가 그 구현이다.

```sh
python3 ~/games/iafetch.py --list-ja                 # 일본어 항목 목록
python3 ~/games/iafetch.py --get 'Loom (FM Towns, Japanese)' -o ~/games/dl/x.zip
```

### 주의: `view_archive.php` 다운로드 링크는 신뢰할 수 없다

archive.org 의 파일 목록 HTML 은 **연속 공백을 하나로 축약해서** 보여준다.
실제 zip 내부 이름이

```
Indiana Jones and the Fate of Atlantis  (FM Towns, Japanese).zip
                                      ^^ 공백 2개
```

인데 HTML 은 공백 1개로 표시한다. 그 링크로 받으면 서버측 `unzip` 이
`exit status: 11`(파일 없음) 로 실패하고, **2.4 KB 짜리 HTML 오류 페이지가
`.zip` 확장자로 저장된다**. 크기 확인 없이 진행하면 조용히 깨진다.

→ 반드시 **중앙 디렉터리에서 읽은 실제 이름**을 쓰고, 받은 뒤
   `file`/크기로 검증할 것. `iafetch.py` 는 둘 다 자동으로 한다.

## 판별 도구

```sh
~/games/cjkscan.sh                  # ~/*.zip 안의 모든 판본을 md5 로 CJK 판정
~/games/cjkscan.sh "Dig, The*.zip"  # 특정 아카이브만
```

`engines/scumm/scumm-md5.h` 와 대조하므로 ScummVM 자신의 판정과 동일하다.

### 교훈: 크기로 판단하지 말 것

MI2 FM-Towns 영어판과 일본어판은 `MONKEY2.000` 크기가 **둘 다 11135 B**다.
Indy3 도 영/일 모두 `00.LFL` 7552 B. **md5 로만 판정해야 한다.**

## 사용자 업로드 아카이브 (`~/*.zip`) 검사 결과

6개 아카이브 46개 판본 전수 검사 — **CJK 적중 0건, 전부 영어판**.
"Multi-Platform" 컬렉션은 플랫폼 모음이지 언어 모음이 아니다.
(Dig 는 업로드 중이었음)
