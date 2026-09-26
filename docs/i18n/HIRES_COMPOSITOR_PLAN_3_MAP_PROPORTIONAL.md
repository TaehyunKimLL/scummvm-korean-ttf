# Hi-res text: `hires_text.map` per font id, and proportional Latin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A translator or font pack ships `hires_text.map` beside the game and sets, per SCI font id, which TrueType face draws it, at what size, and how Latin is drawn:
- `off` / `half` / `fullwidth` (already built);
- **`proportional`**, a new mode, whose advance comes from either the **game** font or the TrueType **font**.

The player's ini keys still override.

**Architecture:**
- SCUMM's map parser (`Graphics::HiResFontMap`, ported from `hires-text` and extended) reads the map. The engine-free SCI adapter `resolveFontSettings()` answers precedence-resolved questions per font id: ini beats map beats built-in default, and a `[x:platform]` section beats `[x]`.
- `GfxCache` turns those answers into one resolved `FontSettings` per font id, which each `GfxFontSet` carries, instead of today's global latin mode.
- Proportional mode routes ASCII to the TrueType face (as `half` does), but each character's advance is:
  - the game font's own width for that character (`metrics=game`, so layout is identical to the original); or
  - the TrueType advance rounded to game pixels (`metrics=font`).

**Decisions of 2026-09-26 (after the C5 inventory, `runs/c5-scumm-map-inventory.md`):**
- **Port, don't rewrite.** SCUMM's `graphics/hires_text/font_map.{h,cpp}` (branch `hires-text`) depends only on `common/`. It is ported to `i18n` unmodified, with its tests, and extended for SCI. There will be one parser.
- The advance source is named **`metrics=`** (SCUMM's existing key), with values `game`/`font`; `hires_text_metrics` is the ini key.
- **`[latin]` keeps SCUMM's keys** (`enabled`, `bitmap`, `font`, `metrics`) and gains `mode=` and `space=`. `font=` accepts a face name from `[fonts]` or a path. `enabled=true` is a legacy alias meaning "the engine's current Latin behaviour" (SCI: `mode=proportional` with `metrics=game`; SCUMM: unchanged).
- Additions must be backward compatible: every existing SCUMM map parses to the same `HiResTextConfig` as before (SCUMM's tests keep passing).

**Tech Stack:** C++ (ScummVM SCI, `common/formats/ini-file.h`), CxxTest, Python harness.

**Spec:** `docs/i18n/HIRES_COMPOSITOR_DESIGN.md`: §2.2 (`hires_text.map`, `[fonts]`, `[font.N]`, `[latin]`, qualified sections, precedence), D6 (layout in game units; D6-b proportional later, now), D7, D8. User decisions of 2026-09-26:
- Latin modes are settings, and fullwidth/half must stay selectable.
- Proportional must be selectable, with its advance source chosen per font in the map: `game` or `font`.

Measured context (`runs/fontcensus/REPORT.md`):
- Every Sierra font is variable-width. Font 0 (8 px high, mean width 6.9) is squarish; fonts 4 and 999 (9 and 8 px high, mean 4.8) are narrow; font 300 is the 12 px title face.
- The choice is therefore per font id, not per game.

## Global Constraints

- Engine work goes in a card worktree `~/work/scummvm/i18n/.worktrees/c4-map`, branch `wt/c4-map`, cut from `i18n` at `a2b958c11f`. The merge happens with the user at the end (`TREES.md`).
- **No map and no ini keys: output is byte-identical to today.** With only the existing ini keys (`hires_text_font`, `hires_text_font_size`, `hires_text_latin*`), behaviour is also byte-identical to today: the map layer adds, it does not change.
- Scope predicate unchanged: SCI16, a CJK code page, and keys read from the game's own domain. The map is honoured only under the same predicate; otherwise one warning.
- The map file is `hires_text.map` in the game directory, or the path in ini `hires_text_map`, in INI syntax. Unknown section or key, or a bad value: one warning each, default used, and the file is never rejected whole (spec §4).
- **Precedence per setting:**
  1. ini key (global) wins over everything;
  2. then `[font.N:<platform>]`, then `[font.N]`;
  3. then `[latin:<platform>]` / `[latin]` (or `[hires:<platform>]` / `[hires]` for face and size);
  4. then the built-in default.

  `<platform>` is ScummVM's platform code (`Common::getPlatformCode()`, e.g. `pc98`, `dos`).
- Engine-free code (the ported `Graphics::HiResFontMap`/`HiResTextConfig`, the SCI adapter `resolveFontSettings`, the advance helpers) do not use `g_sci`, `ConfMan` or `GfxScreen`. `GfxCache` feeds them.
- No STL. The ScummVM GPL header goes on new files. Commit messages end with exactly:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01HaZ452x9dK6wjToh3cZ3Cf
  ```
- `make test` passes, with pristine output.

## Map syntax implemented in this plan (subset of spec §2.2)

```ini
[hires]
font=default                 ; face name used when a [font.N] names none
size=16

[fonts]                      ; face name -> file (relative paths: the game directory)
default=NanumGothic.ttf
latin=/System/Library/Fonts/Supplemental/AppleGothic.ttf

[latin]                      ; defaults for every font id
mode=off                     ; off | half | fullwidth | proportional
face=latin                   ; face name for the Latin range (absent: the font's own face)
space=keep                   ; keep | fullwidth   (fullwidth mode only)
metrics=game                 ; game | font        (proportional mode only; SCUMM's existing key)

[font.4]                     ; one SCI font id
face=default
size=16
latin=proportional           ; overrides [latin] mode for this font
latin_face=latin
latin_space=keep
metrics=font

[font.0:pc98]                ; platform-qualified: wins over [font.0] on PC-98
latin=fullwidth
```

The ini keys map onto the same settings as global overrides:

| ini key | setting |
|---|---|
| `hires_text_font` | `[fonts] default` path and `[hires] font=default` |
| `hires_text_font_size` | size |
| `hires_text_latin` | mode |
| `hires_text_latin_font` | latin face path |
| `hires_text_latin_space` | space |
| `hires_text_metrics` | metrics (SCUMM's existing ini key, `game`/`font`) |

`[shadow]`, `[glyphs]`, `baseline=` and `[hires] scale` are out of scope. They are parsed and ignored, with no warning, because they are known future keys.

## Review Focus

1. **The map is absent, or present but empty:** byte-identical (A/B 0 px).
2. **`metrics=game` keeps layout identical:** the same line breaks and box rects as `off` (compare `state` text rects).
3. **The same face at the same size named by two font ids** opens one `TtfGlyphSource`, not two. Sources are cached per (path, size).
4. **A map naming a missing face file:** one warning, and that font id falls back to the ini/default face or `.uni`. Nothing goes blank.
5. **A platform-qualified section** wins only on its platform (unit test with two platforms).

---

### Task 1: `hires_text_log`, and which font ids draw the dialogue

**Files:** modify `engines/sci/graphics/text16.cpp` and `engines/sci/graphics/cache.cpp`.

- [ ] **Step 1:** Add the ini key `hires_text_log` (game domain, bool). When true, `GfxText16::Box`, `Draw` and `DrawStatus` emit `debug(1, "hires_text: font %d line \"%s\" faces %s", fontId, text, faceSummary)`. `faceSummary` counts glyphs per face kind (resource / legacy / unicode / latin), gathered while drawing the line. Keep it cheap: a flag cached at font-cache resolution, no per-char ConfMan.
- [ ] **Step 2:** Build and test. With the key absent, confirm byte-identical output (KQ1-ko intro A/B vs `runs/baseline-4a0f7f0e1c/intro-ko`: 0 px).
- [ ] **Step 3: Measure.** Run the KQ1-ko intro + tour, the LB1 English intro (`_x/lb1/.../(DOS)`, gameid `laurabow`, to the first dialogue if reachable), and the SQ1 VGA English intro, each with `hires_text_log=true` and `hires_text_font` set so the font set path runs. On English games the scope predicate refuses the key, so for those runs log the font id without the TTF: make logging independent of the scope predicate. Tabulate the font ids per text kind (title/menu, dialogue box, status line, parser echo) into `runs/c4-fontids.md`.
- [ ] **Step 4:** Commit: `SCI: hires_text_log names the font id and face that draw each line`.

### Task 2: Port SCUMM's map parser, then extend it for SCI (engine-free)

**Files:**
- Port unmodified from branch `hires-text` (`git -C ~/work/scummvm/repo/scummvm show hires-text:<path>`): `graphics/hires_text/font_map.h`, `graphics/hires_text/font_map.cpp`, `test/graphics/hires_text_font_map.h`. Add `hires_text/font_map.o` to `graphics/module.mk`. Carry the ScummVM headers as they are.
- Then modify the ported `font_map.{h,cpp}` additively, and extend the ported test file.
- SCI adapter: create `engines/sci/graphics/hirestextsettings.h/.cpp` (engine-free: no `g_sci`/`ConfMan`).

**Additions to the shared config (`HiResTextConfig`), all optional; absent means today's behaviour:**
- `[latin] mode=off|half|fullwidth|proportional` and `[latin] space=keep|fullwidth` (new fields; `enabled=true` stays a legacy alias the adapter interprets).
- `[latin] font=` accepts a `[fonts]` face name as well as a path.
- `[fonts]` names beyond SCUMM's roles are stored as a name→path table; SCUMM's role lookup is unchanged.
- **Per-id sections `[font.N]`** (and `[font.N:<qualifier>]`), stored as a table `id → { face, size, latin, latin_font, latin_space, metrics }`, each field with a "set" flag. SCUMM ignores the table.
- Qualified-section precedence uses the parser's existing qualifier mechanism; reuse it for `[font.N:<platform>]`.

**SCI adapter produces:**
```cpp
namespace Sci {
enum LatinMode { kLatinOff, kLatinHalf, kLatinFullwidth, kLatinProportional }; // textlatin.h: append kLatinProportional, don't renumber
struct FontSettings { Common::String facePath; int size; LatinMode latin;
	Common::String latinFacePath; bool fullwidthSpace; Graphics::HiResMetricsSource metrics; };
struct HiresTextOverrides { /* one field + has-flag per ini key: hires_text_font, _font_size, _latin, _latin_font, _latin_space, hires_text_metrics */ };
/** Precedence: ini > [font.N:<platform>] > [font.N] > [latin:<platform>]/[latin] (or [hires] for face/size) > default. */
FontSettings resolveFontSettings(const Graphics::HiResTextConfig &map, bool mapLoaded, int fontId,
                                 const HiresTextOverrides &ini, const Common::Path &gameDir);
}
```
Defaults: size 16, latin off, space keep, metrics game, no face. A face name resolves through `[fonts]`; relative paths resolve against the game directory.

- [ ] **Step 1:** Port the three files unmodified. Build, and check that `make test` passes, including SCUMM's ported map tests. Commit: `GRAPHICS: Bring the hi-res text map parser from the hires-text line`.
- [ ] **Step 2: tests first** for the additions:
  - Parser (`test/graphics/hires_text_font_map.h`):
    - `test_latin_mode_and_space_parse`;
    - `test_font_id_sections_parse`;
    - `test_font_id_qualified_section_wins_for_its_qualifier`;
    - `test_latin_font_accepts_face_name`;
    - `test_existing_scumm_maps_unchanged` (feed the map examples from SCUMM's `HIRES_TEXT_SETUP.md` and assert the same fields as before);
    - `test_bad_values_warn_and_default`.
  - SCI adapter (`test/engines/sci/hirestextsettings.h`):
    - `test_empty_map_defaults`;
    - `test_font_section_overrides_latin_section`;
    - `test_platform_section_wins_on_its_platform_only`;
    - `test_ini_overrides_map`;
    - `test_enabled_true_means_proportional_game`;
    - `test_relative_face_path_joins_game_dir`.
- [ ] **Step 3:** Run and confirm the tests fail. Implement. Run them again; all pass.
- [ ] **Step 4:** Commit: `GRAPHICS: The hi-res text map learns per-font sections and Latin modes, and SCI resolves them`.

### Task 3: Per-font settings drive the font sets

**Files:** modify `engines/sci/graphics/cache.{h,cpp}`, `fontset.{h,cpp}`, `text16.{h,cpp}` (latin mode now per font), and `fontunicode.*` if needed.

- [ ] **Step 1:** `GfxCache` loads the map once, under the scope predicate: game-dir `hires_text.map` or ini `hires_text_map`, via `Graphics::HiResFontMap::loadFromStream` with qualifiers `{<platform>}`, with warnings emitted once each.
  - Build `HiresTextOverrides` from today's ini keys, plus `hires_text_metrics`.
  - For each font id when its set is created, call `resolveFontSettings()` and keep the `FontSettings` in the set.
  - TTF sources come from a small cache keyed by (path, size). Build a `RoutedGlyphSource` when `latinFacePath` differs. On a failed open: one warning per path, then fall back as today (the ini face, then `.uni`).
- [ ] **Step 2:** Replace the global latin mode reads (`getLatinMode()` / `getLatinSpaceFullwidth()` and `GfxText16`'s cached copies) with the current font set's settings. `GfxText16` must refresh them whenever the font changes (`SetFont`/`GetFont`).
- [ ] **Step 3:** Invariants:
  - With no map, only today's ini keys, and every combination previously captured, the output is byte-identical to the `c3` captures: re-run `off`, `half` with AppleGothic, and `fullwidth` keep/space, and compare with `runs/c3f-*` / `runs/c3-*`, all `.bin`.
  - With no keys at all, A/B 0 px against the baseline.
- [ ] **Step 4:** A map-driven run equals the ini-driven run for the same global settings. Write a map with `[fonts] default=AppleSDGothicNeo.ttc`, `latin=AppleGothic.ttf`, and `[latin] mode=fullwidth face=latin`. Its output must be byte-identical to the ini-only fullwidth capture.
- [ ] **Step 5:** Per-font proof. Use a map with `[font.0] latin=fullwidth` and `[font.4] latin=half`, choosing ids by Task 1's table so both appear on one screen. Capture and describe which text got which mode.
- [ ] **Step 6:** Commit: `SCI: every font id gets its own hi-res settings from hires_text.map`.

### Task 4: `latin=proportional`, `metrics=game|font`

**Files:**
- modify `engines/sci/graphics/glyphsource.h` (add `virtual int advance(uint32 cp) { return 0; }`: advance in hi-res pixels, 0 = unknown);
- modify `glyphsource_ttf.{h,cpp}` (store FreeType's advance per cached glyph and return it);
- modify `glyphsource_routed.*` (forward);
- modify `fontunicode.*`, `fontset.*` and `text16.*`;
- create the pure helper `engines/sci/graphics/latinadvance.h/.cpp`;
- test `test/engines/sci/latinadvance.h`.

**Behaviour:**
- **Routing:** ASCII U+0020..U+007E goes to the TrueType face, as in half mode. There is no remap.
- **Advance** for an ASCII character `c` in font `f`:
  - `metrics=game`: `gameFont->getCharWidth(c)` in game pixels, from font f's own resource face. Layout is then identical to `off`.
  - `metrics=font`: `max(1, round(ttfAdvanceHires(c) / 2))` game pixels. If the source cannot say (0), use `game`.
- **Drawing:** the TrueType glyph is drawn with its origin at the start of the advance box. It is not centred, and its own bearing is kept. Ink may extend past the box, as in any proportional font. `drawToBuffer` does the same.
- `getCharWidth` (layout) and the draw advance must use the same helper, so measuring and drawing agree.
- **Pure helper:** `int latinAdvanceGamePx(Graphics::HiResMetricsSource metrics, int gameWidth, int ttfAdvanceHires, int scale)`.

- [ ] **Step 1: tests (pure helper):**
  - game mode returns gameWidth;
  - font mode rounds half up (e.g. 13 hi-res at scale 2 → 7);
  - font mode with 0 falls back to gameWidth;
  - never returns 0 for a positive input.

  Plus a `TtfGlyphSource` test (skipped without the macOS font): `advance('i') < advance('m')`, and both > 0.
- [ ] **Step 2:** Implement. Run make and make test.
- [ ] **Step 3: Captures** (KQ1-ko, SD Gothic Neo, AppleGothic as the latin face):
  - `proportional` + `metrics=game`: every `state` text rect equals the `off` run (layout identical). PNG crops of the intro box and look/unknown.
  - `proportional` + `metrics=font`: PNG crops. Report the line-break differences against `off`.
  - Compare both visually with `half` and `fullwidth` in one sheet `shots/c4/latin_modes.png` (off / half / fullwidth / proportional-game / proportional-font, same box).
- [ ] **Step 4:** Commit: `SCI: hires_text latin=proportional, advancing by the game font or by the TrueType face`.

### Task 5: Docs

- [ ] **Step 1:** In the docs repo:
  - update `HIRES_COMPOSITOR_DESIGN.md` §2.2 to the syntax actually implemented (plus the ini key table, `hires_text_metrics`, and the SCUMM-compatible `[latin]` additions);
  - record in §5 the Task 1 font-id table and the Task 4 captures;
  - write a translator-facing `docs/i18n/HIRES_TEXT_MAP.md`: a complete annotated example for KQ1-ko, precedence, the modes with pictures (link the shots), and the warnings to expect.

  Commit.

## Out of scope

- `[glyphs]` remap ranges, `[shadow]`, `baseline=` (spec §2.2, later).
- GUI options (spec step 3).
- Scale 3.
- Per-glyph centring or kerning in proportional mode.
- The SJIS legacy face.
