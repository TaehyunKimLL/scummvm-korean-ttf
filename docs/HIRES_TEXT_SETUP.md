# Hi-res 텍스트 설정 (현행)

> **현행 문서는 소스 트리 안에 있습니다: `engines/scumm/HIRES_TEXT_SETUP.md`.**
> 그쪽이 코드에서 직접 확인한 전체 레퍼런스이고 GUI 체크박스도 다룹니다.
> 이 파일은 그 이전 요약이라 `korean_ttf` 키를 아직 언급합니다.


`KOREAN_TTF_SETUP.md`는 구형(TrueType 로더, `korean_ttf.map`) 문서다. 현재
브랜치(`hires-text`, 커밋 `ef95aaca144` 이후)는 이 문서를 따른다.

## 한 줄 요약

게임 폴더에 `hires_text.map`과 `hr%02d.fnt`를 넣으면 켜진다. ini 키는 덮어쓸 때만 필요하다.

## 1. 파일

| 파일 | 위치 | 역할 |
|---|---|---|
| `hires_text.map` | 게임 폴더 (또는 `hires_text_map=` 경로) | 배율·인코딩·폰트 이름 |
| `hr00.fnt` … `hrNN.fnt` | 게임 폴더 | 게임 charset 번호별 SVFN 폰트. 없는 번호는 가장 가까운 것으로 대체 |
| `hrlat00.fnt` … | 게임 폴더 | (선택) 라틴 전용. `[latin] bitmap=` 로 지정 |

폰트는 `scripts/mkfont.py`로 TTF에서 굽는다. FreeType 없는 빌드도 같은 결과를 낸다.

```sh
# 원본 charset 높이 9px, 2배 → 18px 셀
python3 scripts/mkfont.py NanumGothic.ttf hr01.fnt --size 18 --codepage 949 --bpp 8 --variable
```

## 2. 최소 맵

```ini
[hires]
scale=2
alpha=true
[encoding]
codepage=cp949
[bitmap]
multi=hr%02d.fnt
glyphs=2350
[render]
metrics=game
```

`[latin] bitmap=hrlat%02d.fnt`를 넣으면 0x20~0x7e도 대체 폰트로 그린다. 예전에는
DOTT처럼 0x5e(`^`)를 말줄임표로 쓰는 번역에서 이걸 빼야 했지만, 지금은 `[glyphs]`로
예외만 지정하면 되므로 넣어도 된다 (아래 참조).

## 2-1. `[glyphs]` — 게임이 다른 그림을 그리는 코드

게임 폰트는 문자 집합이 아니다. LucasArts 게임은 Latin-1의 `^` 자리에 말줄임표를,
`_`와 DEL 자리에 화살표를 넣었고, MI2는 대화 선택지 앞의 **해골** 불릿을 `0x07`에
둔다 — 라틴 폰트에는 아예 없는 자리다.

지정하지 않으면 단순히 잘못 그려지는 게 아니라 **아예 사라진다**. hi-res 레이어가
"내가 그렸다"고 보고해서, 원본을 그렸을 폴백이 실행되지 않기 때문이다.

```ini
[glyphs]
0x5e = keep        ; 캐럿이 아니라 말줄임표
0x07 = keep        ; 대화 선택지 해골 불릿
0x7f = u+2192      ; 대체 폰트의 다른 코드포인트로 그리기

[glyphs:cs1]       ; charset 1 에만 적용
0x5f = keep
```

- `keep` = 폰트를 고르기 **전에** 물러나므로 게임 원본 글리프가 그려진다. 폭 계산
  (`advanceFor`)도 같이 물러나서 줄 배치가 원본 그대로 유지된다.
- `u+XXXX` = 대체 폰트에서 그 코드포인트를 그린다. 굽는 목록에도 자동 추가된다.
- **charset별로 다르다.** `0x5f`는 대화 charset에서 왼쪽 화살표지만 다른 charset에선
  진짜 언더스코어다. `[glyphs:csN]`으로 좁히지 않으면 언더스코어가 깨진다.

키는 `0x5e` / `94` / `u+2192` 다 되지만, **`Common::INIFile`이 키 이름에 `+`를 허용하지
않아** 맵 전체가 거부된다. 값으로는 `u+2192`가 되고, 키는 `0x7f`로 써야 한다.

### 게임별 실측 목록

`~/games/charscan.py`·`charrender.py`·`lflrender.py`로 원본 charset을 덤프해 확인한 값:

| 코드 | 실제 그림 | MI1 | MI2 | Loom | DOTT |
|---|---|---|---|---|---|
| `0x5e` | 말줄임표 (전 charset) | O | O | O | O |
| `0x07` | 해골 불릿 | - | O (cs0) | - | O |
| `0x5f` | 왼쪽 화살표 (대화 charset만) | cs2/cs4 | cs1 | cs2/cs4 | cs1/cs4 |
| `0x7f` | 오른쪽 화살표 | cs2/cs4 | cs1 | cs2/cs4 | O |

`0x81/0x82/0x83/0x88/0xfa`는 전 게임에서 그냥 CP437 악센트 문자다 — 조치 불필요.

주의: MI2 해골은 **charset 0에서 그려지는데 주변 텍스트는 charset 1**이다. 그래서
`[glyphs:cs1]`에 넣으면 발동하지 않는다. 어느 코드가 문제인지는 추측하지 말고
`hires_text_log=true`로 `HRTEXT` 줄을 보면 `\u0007`처럼 그대로 찍힌다.

## 3. scummvm.ini 키 (맵을 덮어쓸 때)

| 키 | 값 | 설명 |
|---|---|---|
| `hires_text_map` | 경로 | 맵 파일. 상대 경로는 게임 폴더 기준 |
| `hires_text_scale` | 1~3 | 맵의 `scale`보다 우선 |
| `hires_text_alpha` | bool | 맵의 `alpha`보다 우선 |
| `hires_text_metrics` | `game`/`font` | 가변폭 폰트가 자기 폭으로 배치할지 |
| `hires_text_log` | bool | 그린 문자열마다 `HRTEXT` 로그 |

구형 `korean_hires_scale`, `korean_alpha_text`는 아직 읽는다.
**`korean_ttf_map`, `korean_ttf.map`은 읽지 않는다** — 경고만 나온다.

명령행으로는 못 넘긴다. 타깃 섹션에 넣는다.

## 4. 켜졌는지 확인

```sh
scummvm -d1 <target> 2>&1 | grep -E "hi-res|HRTEXT"
```

- `hi-res map read` + `hi-res text enabled` + `hi-res font N <-` 세 줄이 다 있어야 켜진 것.
- `hi-res text enabled`가 없으면 원본 경로로 그린다.
- `names no [bitmap] fonts` 경고 = 구형 맵. `~/games/prepare-*-maps.py`나 `makemaps.py`로 다시 생성.

`~/games/fontcheck.sh <target>`이 이걸 한 번에 해준다.

## 5. 끄기

현재는 **폴더에 `hires_text.map`이 있으면 ini로 끌 수 없다.** `hires_text_scale=1`은 배율만
내리고 대체 폰트는 계속 쓴다. 끄려면 파일을 빼거나 `hires_text_map=`을 존재하지 않는 경로로
준다(경고 후 꺼짐). 마스터 스위치 `hires_text=false`는 예정 — `GUI_OPTIONS_DESIGN.md` 참조.

## 6. 게임별 메모

| 게임 | 배율 | 비고 |
|---|---|---|
| MM/Zak (v2) | 2 | 8px 고정 그리드. `--fixed --fullwidth` 라틴 |
| Indy3 (v3) | 3 | 높이 8/9. `metrics=font` 시 자간 변화 확인 |
| Loom VGA (v4) | 2 | 구형 맵이면 클릭 좌표가 어긋난다 |
| MI1/MI2/Indy4 (v5) | 3 | 높이 8/9/12(/16) |
| DOTT (v6) | 2 | `[latin]` 넣지 말 것 (0x5e 말줄임표) |
| FT/Dig (v7) | **1** | 배율 확대 차단. SMUSH 자막은 미지원 |
| FM-Towns 전 게임 | — | 배율 무시. 폰트 교체만 |
