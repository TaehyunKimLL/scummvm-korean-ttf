# Hi-res 텍스트 설정 (현행)

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

`[latin] bitmap=hrlat%02d.fnt`는 게임이 0x20~0x7e를 원래 의미로 쓸 때만 넣는다.
DOTT 한글판은 0x5e(`^`)를 말줄임표로 쓰므로 넣으면 안 된다.

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
