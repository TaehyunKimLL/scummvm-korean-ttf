# Hi-res text: one `hires_text.map` and one parser for SCUMM and SCI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SCUMM and SCI read `hires_text.map` with the same parser, byte for byte: `graphics/hires_text/font_map.{h,cpp}` and `test/graphics/hires_text_font_map.h` are identical on the SCI line (`i18n`) and the SCUMM line (`hires-text`). Two grammar changes land in that parser:
- **Inline comments.** Whitespace followed by `;` ends a value. A `;` with no whitespace before it stays in the value (`single=my;font.fnt`). This applies to every key the parser reads, for both engines, so the `color=0 ; DOS` example in SCUMM's setup guide finally does what it says.
- **`[glyphs]` ranges.** `0xNN-0xMM=+0xOFFS` (remap by an offset) and `0xNN-0xMM=keep`. They expand into the existing per-code override table. Single-code entries, scopes (`[glyphs:cs1]`) and qualified sections keep their meaning. SCUMM applies ranges at once, because it already applies the table. SCI parses them but does not apply `[glyphs]` yet.

**Architecture:**
- The parser changes are made **once**, on the SCI line: branch `wt/c5-parser`, cut from `wt/c4-map` (C4, open as PR #1 against `i18n`), worktree `~/work/scummvm/i18n/.worktrees/c5-parser`. They come with their tests.
- The three shared files are then **copied byte-identically** onto the SCUMM line: branch `wt/c5-scumm-map`, cut from `hires-text` (`7b0a8c9899`), worktree `~/work/scummvm/repo/scummvm/.worktrees/c5-scumm`. The copy brings the C4 extensions to SCUMM as well (`[font.N]`, `[latin] mode=/space=`, the `[fonts]` name table, the key aliases). They are all additive, and SCUMM reads none of them.
- On the SCUMM line, the adapter (`engines/scumm/hires_text.cpp`) is audited against the C4 parser field by field. The font baker's remap-target search becomes a hash lookup, so that a large range cannot stall a bake.
- The docs are reconciled on both sides: the SCUMM guides in the engine repo, `HIRES_TEXT_MAP.md` and `HIRES_COMPOSITOR_DESIGN.md` §2.2 in the docs repo.

**Decisions of 2026-09-26 (user, binding):**
1. The SCUMM side is its own branch off `hires-text` (`wt/c5-scumm-map`). The three shared files end up byte-identical between the two lines.
2. The shared parser strips inline comments (whitespace + `;`), on every key and for both engines. C4's docs ("inline comments stay in the value") are updated to the new rule.
3. `[glyphs]` gains range syntax in the shared parser. SCUMM consumes it; SCI consumption is **not** in this card.

**Decisions made in this plan (open points of the card):**
- **INI character limits** (`common/formats/ini-file.cpp`, identical on both lines):
  - A **key** may hold only alphanumerics and `-` `_` `.` space `:`. Anything else rejects the *whole file* (`Invalid key name`).
  - So `0x21-0x7E` is a legal key. `u+21-u+7E` is not, and it makes the whole map unreadable, exactly as a single `u+5e` key already does (`test_glyphs_key_may_not_use_u_plus_form`). Range endpoints are therefore hex `0x..` or decimal.
  - **Values** are not validated: the line splits at the first `=`, so `+`, `=` and `;` are all legal in a value.
  - Whole-line comments start with `;` or `#`, as before. Text after `]` on a section line is already ignored (`[glyphs:cs1] ; charset 1 only` works today).
- **Comment rule, exactly:**
  - INIFile has already trimmed the value.
  - The first `;` that is preceded by a space or a tab ends it, and the rest is trimmed again.
  - A value that *starts* with `;` is empty. Its `;` was preceded by whitespace in the line (`key= ; note`), and INIFile's trim removed that whitespace. No key the parser reads has a meaningful value starting with `;`.
  - `#` is not an inline comment marker.
  - The rule is the map's only. `scummvm.ini` is read by `ConfigManager`, which has no inline comments at all.
- **Range grammar:**
  - The key is `<code>-<code>`: the key contains a `-` and is split at the first one. Each half is trimmed, so `0x21 - 0x7E` works too, and each half is parsed by the existing `parseCodeValue()`. A key with a `-` is always a range key, since codes are never negative.
  - The value is `keep` or `+<n>`, where `<n>` is hex `0x..` or decimal (not `u+`: an offset is a distance, not a code point).
  - An absolute target on a range (`0x21-0x7E=u+FF01`) is refused, because it would draw 94 codes as one character.
  - `+<n>` is also accepted on a **single** code (`0x41=+0x20` is the same as `0x41=0x61`). Before C5 that line warned and was ignored, so it changes only a map that was already broken.
- **Bounds.** Each case below gives one warning and ignores the whole entry; the map still loads:
  - the range ends before it starts (`end < start`);
  - `end > 0xFFFF`, since game codes are at most double-byte (single codes keep their existing `0x10FFFF` cap);
  - `end + offset > 0x10FFFF`;
  - a malformed half (`0x21-`, `-0x7E`, `0x21-0x7E-0x80`, `0xzz-0x7E`);
  - an absolute or `u+` target on a range.

  `start == end` is a one-code range, and `+0` is allowed (an identity remap, not `keep`).
- **Table limit:** at most `0x20000` codes come from ranges per map load, summed over every glyph table (the common one and each scope). That is two full `0x0000-0xFFFF` ranges.
  - It matters because SCUMM builds up to 21 tables (`[glyphs]` plus `cs0..cs19`, `kMaxFonts = 20`), and each expanded code is a HashMap node.
  - A range that would go past the limit is ignored whole, with one warning. Ranges before it stay.
  - Single-code entries do not count against the limit.
- **Overlap and precedence** (the rule a translator can hold in their head: *specific beats general*):
  1. **Across sections: unchanged.** `[glyphs]` is read first, then each qualified section from the least specific to the most specific (`[glyphs:v5]`, then `[glyphs:monkey2]`). A later section overwrites an earlier one code by code, whether the entry is a range or a single code: a range in a qualified section beats a single code in the bare section. The scope tables (`[glyphs:csN]`) still beat the common table at lookup (`glyphOverride()`).
  2. **Within one section: single codes beat ranges**, whatever their line order. The section is read in two passes, all ranges first, then all single codes. `0x21-0x7E=+0xFEE0` followed or preceded by `0x5e=keep` leaves `0x5E` kept. That is the way to punch a hole in a range.
  3. **Between ranges in one section: the later line wins** for the codes they share. This is the same file-order rule a repeated single key already follows (`out[code] = ...` overwrites).
  4. Overlaps do not warn: a hole in a range and a narrower range over a wider one are both intended uses.

**Tech Stack:** C++ (`Common::INIFile`, `Common::HashMap`), CxxTest, macOS builds (`./configure` per worktree), the Python harness only on hpz2.

**Spec:** `docs/i18n/HIRES_COMPOSITOR_DESIGN.md` §2.2, `docs/i18n/HIRES_TEXT_MAP.md`, `runs/c5-scumm-map-inventory.md` (the SCUMM schema and the SCUMM/SCI side-by-side), `HIRES_COMPOSITOR_PLAN_3_MAP_PROPORTIONAL.md` (C4, the parser port and its extensions).

## Global Constraints

- **Progress on the board:** every subagent (impl, review, re-review, fix, final-review) posts a start and an end comment on kanban card `t_b9e705c3` (board `scummvm`): `hermes kanban --board scummvm comment --author <role> t_b9e705c3 "[<role> T<n>] start: ..."` / `"... end: <status>; <commits>; <tests>; report <path>"`. A failing comment command is noted in the report, not fatal.
- **Trees (`TREES.md`):**
  - Never edit `~/work/scummvm/i18n` (the base) or `~/work/scummvm/repo/scummvm`'s own checkout.
  - Nothing is checked out in the existing `c4-map` worktree.
  - The two card worktrees are created by the implementer, not by this plan:
    ```bash
    git -C ~/work/scummvm/i18n worktree add .worktrees/c5-parser -b wt/c5-parser wt/c4-map
    git -C ~/work/scummvm/repo/scummvm worktree add .worktrees/c5-scumm -b wt/c5-scumm-map hires-text
    ```
    Run `~/work/scummvm/harness/i18ntrees.sh` before each of them.
  - Merges happen with the user at the end. `wt/c5-parser` merges after PR #1 (`wt/c4-map`) does. `wt/c5-scumm-map` merges into `hires-text`.
- **Build (macOS). Each worktree configures itself**, since the object store is shared and the build tree is not:
  - SCI line: `./configure --disable-all-engines --enable-engine=sci`, as `c4-map` was. `USE_FREETYPE2` gets picked up automatically.
  - SCUMM line: `./configure --disable-all-engines --enable-engine=scumm,scumm_7_8`. Then `grep '^ENABLE_SCUMM = STATIC_PLUGIN' config.mk` must match, or `test/engines/scumm/*.h` is silently left out of `make test` (`test/module.mk`), and `grep '^USE_FREETYPE2 = 1' config.mk` must match (the baker test needs it).
  - Build with `make -j10`. Test with `PATH=/Users/juami/work/scummvm/runs/pybin:$PATH make test -j10`, which must pass with pristine output.
- **Byte identity is checked, not assumed:**
  ```bash
  git -C ~/work/scummvm/repo/scummvm diff --exit-code wt/c5-parser wt/c5-scumm-map -- \
      graphics/hires_text/font_map.h graphics/hires_text/font_map.cpp test/graphics/hires_text_font_map.h
  ```
  must print nothing and exit 0 at the end of Tasks 2 and 3. If a review changes the parser, the change is made on `wt/c5-parser` and copied again. It is never made on the SCUMM side first.
- **The shared parser stays engine-free:** `common/` only, no `ConfMan`, no engine types. Nothing SCUMM- or SCI-specific goes into the three shared files beyond what C4 already put there.
- **No map, or a map without whitespace-`;` values and without range keys: every `HiResTextConfig` field is the same as before C5.** The existing tests pin this, and exactly one assertion changes on purpose (Task 1, Step 3).
- **Unknown or bad input:** one warning per entry, and the default is used. The map is never rejected whole, except for INIFile's own syntax errors (unchanged).
- **No STL.** The ScummVM GPL header goes on every new source file (new test files follow the existing `test/graphics/hires_text_*.h`, which carry none). Commit messages end with exactly:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01HaZ452x9dK6wjToh3cZ3Cf
  ```
- Every subagent posts a start and an end comment on kanban card t_b9e705c3 (board scummvm), format in the card's Protocol comment.
- **No SCUMM game data exists on this Mac.** `gamedata/` holds SCI games only, and hpz2 is not reachable over ssh from here. Runtime SCUMM checks are Task 5: **optional, and run by the user**. Tasks 1–4 must not depend on them.

## Map syntax added by this plan

```ini
[shadow]
color=0            ; DOS - now parses as 0 (before C5: the value was "0            ; DOS", a warning, color unset)

[bitmap]
; no whitespace before ';': part of the value
single=my;font.fnt

[glyphs]
; ASCII to the fullwidth forms block
0x21-0x7E=+0xFEE0
; but the caret stays the game's own ellipsis: a single code beats a range in the same section
0x5e=keep
; a whole block left to the game's font
0x80-0x9F=keep
; single code, offset form (same as 0x41=0x61)
0x41=+0x20

[glyphs:cs1]
; the scope table still wins for charset 1
0x21-0x2F=keep
```

New parser warnings (prefix `HiResText:`, as all parser warnings):
- `glyph range '<key>' is not <code>-<code>, ignoring`
- `glyph range '<key>' ends before it starts, ignoring`
- `glyph range '<key>' goes past 0xFFFF, ignoring`
- `glyph range <key>: '<value>' is neither 'keep' nor '+<offset>', ignoring`
- `glyph <key>: '<value>' goes past U+10FFFF, ignoring` (a range's end, or a single code, plus its offset)
- `glyph range '<key>' would take the map past 131072 range codes, ignoring`

The existing single-code warnings keep their exact text.

## What parses differently, and for which maps

**Under C4's parser alone (the copy in Task 2, before C5's two rules):** no field SCUMM reads changes.
- The C4 diff against `hires-text` (`git diff hires-text wt/c4-map -- graphics/hires_text/font_map.*`) is additive, apart from 3 lines inside `[latin] enabled=`. Those lines only add the new `latinEnabledSet`/`latinEnabledValue` fields; `legacy.latinEnabled` is assigned exactly as before.
- SCUMM's adapter reads only the fields listed in Task 2, Step 3.
- The C4 fields fill in from a SCUMM map, but SCUMM never reads them: `fontFaces` (from `[fonts]`), `latinFont`/`latinFontSet` (from `[latin] font=`, which the legacy path also still reads), `latinMetrics` (from `[latin] metrics=`, where `ttf` is an alias of `font`), and `legacy.latinEnabledSet`/`Value`.
- **New warnings** a SCUMM map could now trigger: `invalid [hires] size`, `[latin] mode ... is not off, half, fullwidth or proportional`, `[latin] space ... is not keep or fullwidth`, and any `[font.<x>]` section: `does not name a font id` / `is not written as [font.N]` / `has no key`. No known SCUMM map uses these names.

**Under C5's rules:** only maps with whitespace-`;` values or with range keys change. Every other map parses to the same config. Known SCUMM maps:

| Map | Before C5 | After C5 |
|---|---|---|
| `HIRES_TEXT_SETUP.md` "Per-game sections": `color=0 ; DOS` / `[shadow:fmtowns] color=8 ; ...` | warning, `shadowColorSet=false` (pinned by C4's `test_existing_scumm_maps_unchanged`) | `0` on DOS, `8` on FM-Towns, as documented |
| `HIRES_TEXT.md` `[glyphs]` example (`0x5e = keep ; an ellipsis ...`, 3 lines + `[glyphs:cs1]`) | every line warns (`neither 'keep' nor a code point`), table empty | applied as documented |
| `HIRES_TEXT.md` / `HIRES_TEXT_DECORATIONS.md` `[shadow]` example (`mode=outline ; none \| ...`) | `mode` silently falls to `game` (the else branch has no warning); `offset`/`color` warn | `outline`, `2`, `8` as documented |
| `HIRES_TEXT_SETUP.md` full example, `[fonts]`/`[sizes]` example, `graphics/hires_text/README.md` example | own-line comments only | unchanged |
| any map with a `<code>-<code>` key in `[glyphs]` | `'<key>' is not a character code, ignoring` | applied |
| real maps on hpz2 (`~/games/*/hires_text.map`), not visible from here | unknown | listed by Task 5, Step 1 |

**SCI:** no local map contains a whitespace-`;` value (`grep -n '[[:space:]];' gamedata/c4-*/hires_text.map runs/c4fx-mapdir/hires_text.map` prints nothing), and no SCI test string does. SCI does not read `[glyphs]`. So SCI's output cannot change, and the SCI adapter needs no change.

## Review Focus

1. **Byte identity.** The `git diff --exit-code wt/c5-parser wt/c5-scumm-map -- <3 files>` above is empty, and it was produced by `git checkout wt/c5-parser -- <files>`, not by retyping.
2. **The comment rule is applied at every read site, not just in `getKey()`.** The value loops are `readGlyphSection`, `readFaceTable`, the `[map] height_` loop, and `readFontIdSections` through `getKey`/`getKeyEither`. There is one test per reader.
3. **The only existing assertion that changes** is the `[shadow]` inline-comment one in `test_existing_scumm_maps_unchanged`. Every other test from `hires-text` (32) and C4 (11) passes unedited. Check with `git diff wt/c4-map wt/c5-parser -- test/graphics/hires_text_font_map.h`: additions plus that one hunk.
4. **Range precedence and bounds** match the decisions above, including the 131072-code limit and "single beats range in the same section, whatever the line order".
5. **The baker's output is unchanged:** `applyGlyphOverrides()` returns the same code list in the same order for every input, and it only got faster.

---

### Task 1: The shared parser learns inline comments and `[glyphs]` ranges (SCI line)

**Worktree:** `~/work/scummvm/i18n/.worktrees/c5-parser`, branch `wt/c5-parser` off `wt/c4-map` (`c9b5c65a8e`).

**Files:** modify `graphics/hires_text/font_map.{h,cpp}` and `test/graphics/hires_text_font_map.h`. No other file.

**Design:**
- **Comment stripping.** Add `Common::String stripInlineComment(const Common::String &raw)` to the anonymous namespace of `font_map.cpp`. It truncates at the first `;` whose preceding character is `' '` or `'\t'`, then trims; a value whose first character is `;` becomes empty. Call it:
  - in `getKey()` and `getKeyEither()`, on success, so that every single-key read in `loadFromStream()` and `readFontIdSections()` is covered;
  - on `it->value` in `readGlyphSection()`, `readFaceTable()` and the `[map]` `height_` loop.
- **Comment text.** Update the class comment in `font_map.h` ("Comments occupy their own lines; inline comments are not supported.") to state the rule. The `[glyphs]` example comment in `loadFromStream()` becomes true as written.
- **Ranges.** Rework `readGlyphSection()` as two passes per section name, keeping today's section order:
  - pass 1: range keys (the key contains `-`), in file order;
  - pass 2: single keys, in file order, parsed exactly as today, plus the `+<n>` value form.

  Helpers:
  - `bool parseGlyphRange(const Common::String &key, uint32 &start, uint32 &end)`: split at the first `-`, trim, `parseCodeValue()` each half; a further `-` or an empty half fails.
  - `bool parseGlyphOffset(const Common::String &value, uint32 &offset)`: the value starts with `+`, and the rest is `0x..` or decimal, not `u+`.

  Constants `kMaxGlyphRangeCode = 0xFFFF`, `kMaxGlyphRangeCodes = 0x20000`. A `uint &rangeBudget` goes through every `readGlyphSection()` call of one `loadFromStream()`. The public API does not change.

- [ ] **Step 1: Tests first** (in `test/graphics/hires_text_font_map.h`):
  - `test_inline_comment_ends_a_value`: `[shadow] color=0 ; DOS`, a tab before `;`, and `scale=2;` with no space. For the last, the value is `2;`: a warning, and the default is kept.
  - `test_semicolon_without_whitespace_stays`: `[bitmap] single=my;font.fnt` gives `my;font.fnt`; `[fonts] default=a;b.ttf` gives the path `/games/demo/a;b.ttf`.
  - `test_value_that_is_only_a_comment_is_empty`: `[bitmap] single= ; none` gives an empty `bitmapSingle`; `[shadow] color= ; x` warns and leaves the colour unset.
  - `test_inline_comment_every_reader`: one key through each read path:
    - `[hires] scale` (getKey);
    - `[latin] face=` (getKeyEither);
    - `[fonts] latin=` (face table);
    - `[glyphs] 0x5e = keep ; ...`;
    - `[map] height_12 = title ; ...`;
    - `[font.4] size=16 ; ...` and `[font.4] latin=half ; ...`.
  - `test_scumm_doc_examples_now_parse_as_written`: the `[glyphs]`/`[glyphs:cs1]` block of `engines/scumm/HIRES_TEXT.md` and the `[shadow]` block of `HIRES_TEXT_DECORATIONS.md`, verbatim, parse to the values their comments describe. Scopes are `cs0`, `cs1`.
  - `test_glyph_range_offset`: `0x21-0x7E=+0xFEE0` gives 94 entries, `0x21→0xFF01` and `0x7E→0xFF5E`; `0x20` and `0x7F` are absent. Also with decimal endpoints and with spaces around `-`.
  - `test_glyph_range_keep`.
  - `test_glyph_single_offset`: `0x41=+0x20` equals `0x41=0x61`.
  - `test_glyph_single_beats_range_in_its_section`: `0x5e=keep` before the range, then after it; `0x5E` is kept both times.
  - `test_glyph_later_range_wins_overlap`.
  - `test_glyph_qualified_range_beats_bare_single`: bare `0x41=keep`, and qualified `[glyphs:monkey2] 0x40-0x42=+0x20`, so `0x41` is remapped.
  - `test_glyph_range_in_scope`: `[glyphs:cs1] 0x21-0x2F=keep` applies to scope 1 only; the common table is untouched.
  - `test_glyph_range_bounds`: nothing is recorded for any of these, and `parse()` still returns true:
    - `0x7E-0x21=keep`;
    - `0x0-0x10000=keep`;
    - `0xFFF0-0xFFFF=+0x100001`;
    - `0x21-0x7E=u+FF01`;
    - `0x21-0x7E=+u+10`;
    - `0x21-=keep`;
    - `-0x7E=keep` (INIFile accepts it: `-` is a legal key character);
    - `0x21-0x7E-0x80=keep`;
    - `0xzz-0x7E=keep`.
  - `test_glyph_range_limit`: `[glyphs] 0x0-0xFFFF=keep`, `[glyphs:cs0] 0x0-0xFFFF=keep`, `[glyphs:cs1] 0x41-0x41=keep`. The third range is refused, and the first two are intact.
  - `test_glyph_range_key_is_legal_ini`: `0x21-0x7E=keep` loads. `u+21-u+7E=keep` rejects the whole map, the same pin as `test_glyphs_key_may_not_use_u_plus_form`.
- [ ] **Step 2:** Run `make test` and confirm the new tests fail (and nothing else fails).
- [ ] **Step 3:** Implement. Change the one intended assertion in `test_existing_scumm_maps_unchanged`. Its `[shadow]`/`[shadow:fmtowns]` example now gives `shadowColorSet` with `0` unqualified and `8` for `fmtowns`. Rewrite the comment above it (it currently says INIFile keeps the `; ...`).
- [ ] **Step 4:** Run `make -j10` and `PATH=/Users/juami/work/scummvm/runs/pybin:$PATH make test -j10`. All pass, including `test/engines/sci/*` unchanged. `git diff wt/c4-map -- test/graphics/hires_text_font_map.h` shows additions plus the one hunk. Check SCI: `grep -n '[[:space:]];' ~/work/scummvm/gamedata/c4-*/hires_text.map ~/work/scummvm/runs/c4fx-mapdir/hires_text.map` prints nothing.
- [ ] **Step 5:** Commit (two commits are fine, one per rule):
  - `GRAPHICS: hires_text.map values end at a whitespace-preceded ';'`
  - `GRAPHICS: hires_text.map [glyphs] takes code ranges: keep, or +offset`

### Task 2: The SCUMM line takes the shared parser byte for byte

**Worktree:** `~/work/scummvm/repo/scummvm/.worktrees/c5-scumm`, branch `wt/c5-scumm-map` off `hires-text` (`7b0a8c9899`).

**Files:**
- replace `graphics/hires_text/font_map.{h,cpp}` and `test/graphics/hires_text_font_map.h` (a copy, not an edit);
- modify `graphics/hires_text/font_baker.cpp`, which exists on the SCUMM line only;
- create `test/graphics/hires_text_font_baker.h`;
- modify `engines/scumm/hires_text.{h,cpp}` only if the Step 3 audit finds a reason (none is expected).

- [ ] **Step 1: Baseline.** Configure as in Global Constraints and check `ENABLE_SCUMM`/`USE_FREETYPE2` in `config.mk`. Run `make -j10` and `make test` on the untouched branch, and record the pass/fail counts. A test that already fails on macOS is recorded and left alone: it is not this card's to fix. It is then expected to fail identically after Step 2.
- [ ] **Step 2: Copy.**
  - `git checkout wt/c5-parser -- graphics/hires_text/font_map.h graphics/hires_text/font_map.cpp test/graphics/hires_text_font_map.h`, then the byte-identity `git diff --exit-code` from Global Constraints.
  - The copy compiles unmodified: its dependencies (`common/hash-str.h`, `String::findFirstOf`, `hasPrefixIgnoreCase`, `Common::INIFile`) are identical on both lines (`git diff --stat hires-text wt/c4-map -- common/str.h common/str-base.h common/hash-str.h common/hashmap.h common/formats/ini-file.*` is empty).
  - `graphics/module.mk` already lists `hires_text/font_map.o`, and `font_baker.h`/`glyph_renderer.h` include `font_map.h` for enums that did not change.
  - Build and test. The 32 `hires-text` parser tests, the 11 C4 tests and the Task 1 tests all run here, since the file is the same.
- [ ] **Step 3: Adapter audit** (reading, not writing). Every `HiResTextConfig` field that SCUMM reads (`git grep` over `engines/` and `graphics/hires_text/` outside `font_map.*`), and what C4/C5 did to its parsing:

  | field | read at (`hires_text.cpp`) | C4 | C5 |
  |---|---|---|---|
  | `scale`, `alpha` | 1050-1102, 1387-1409, 698 | unchanged | comment rule |
  | `encoding` | 1142, 1302, 1504 | unchanged | comment rule |
  | `bitmapPattern`, `bitmapSingle` | 163-212, 973-985, 1353, 1430-1441 | unchanged | comment rule (a `;` with no whitespace stays in a file name) |
  | `legacy.latinBitmapName` | 232, 973-996, 1432-1443 | unchanged | comment rule |
  | `legacy.latinEnabled` | written only (989, 995, 1232) | still set by `enabled=` and `bitmap=` exactly as before; the new `latinEnabledSet/Value` are not read | — |
  | `ttfPath[kHiResRoleDefault]` | 1378-1379 | unchanged (`[fonts]` roles still go through `resolvePath`; the name table is separate) | comment rule |
  | `metricsSource` | 601, 1414-1424 (the ini wins) | unchanged | comment rule |
  | `shadowMode/Offset/Color(Set)` | 532-534 | unchanged | comment rule |
  | `glyphOverride()`, `glyphOverrides`, `scopedGlyphOverrides` | 484, 608, 1167-1172 | unchanged | ranges and `+n`, expanded into the same tables |

  **Parsed, but SCUMM applies none of them** (for the docs, Task 3): `[sizes]`, `[fonts] bold/title`, `[render] mode`, `[map] height_*`, `[translation] file`, `[latin] font/metrics`, `[bitmap] glyphs`, `scaleFromMap/alphaFromMap/encodingFromMap`. **SCI-only fields** (C4) that SCUMM also does not read: `hiresFace/Size`, `latinMode/Space/Font/Metrics`, `fontFaces`, `fontIds`, `legacy.latinEnabledSet/Value`.

  If the audit finds a SCUMM read of a field whose parsing changed beyond this table, stop and report before changing the adapter. Expected result: **no adapter change**, and the table goes into the commit message.
- [ ] **Step 4: Baker cost with ranges.** `HiResFontBaker::applyGlyphOverrides()` searches `kept` linearly for each remap target: O(remaps × codes).
  - That is harmless for single entries, but a `0x21-0x7E=+0xFEE0` range is 94 searches over about 2,500 codes, per charset baked, and a large DBCS range is 30k+ over 30k+.
  - Replace the inner search with a `Common::HashMap<uint32, bool>` of the codes already in `kept`. Append targets in the same iteration order, so the result is identical.
  - Test first, in `test/graphics/hires_text_font_baker.h` (guarded `#ifdef USE_FREETYPE2`, like `font_baker.cpp`):
    - `test_keep_drops_codes`;
    - `test_remap_target_appended_once` (two codes remapped to one target);
    - `test_range_expanded_table`: parse `0x21-0x7E=+0xFEE0` and `0x5e=keep` with `HiResFontMap::loadFromStream`, then apply to `latin1()`. `0x5E` is gone, the 94 fullwidth targets less `0xFF3E` are present once each, and the list equals the pre-change function's output (the test captures the expected list from a small, hand-written case).
  - Measure one worst case before and after (a full `0x8140-0xFEFE` remap over `hangulSyllables()`), and note both times in the commit message.
- [ ] **Step 5:** Run `make -j10` and `make test`. Everything the baseline passed still passes, and the new tests pass. Re-check byte identity.
- [ ] **Step 6:** Commits:
  - `GRAPHICS: Bring the shared hi-res text map parser back from the i18n line` (the copy; the body names `wt/c5-parser` and its hash, and holds the Step 3 table);
  - `GRAPHICS: The font baker finds remap targets by hash, not by scan`.

### Task 3: SCUMM docs follow the parser (engine repo, SCUMM line)

**Worktree:** as Task 2. **Files:** `engines/scumm/HIRES_TEXT_SETUP.md`, `engines/scumm/HIRES_TEXT.md`, `engines/scumm/HIRES_TEXT_DECORATIONS.md`, `graphics/hires_text/README.md`.

- [ ] **Step 1: `HIRES_TEXT_SETUP.md`:**
  - Under "The map file", state the comment rule (whitespace + `;` ends a value; `a;b` stays; own-line `;`/`#` comments as before). The existing "Per-game sections" example (`color=0 ; DOS`) now works. Say so, and warn that a shipped map that had such a line changes behaviour: it now applies the value it always meant.
  - Add range syntax to `[glyphs]`: `0x21-0x7E=+0xFEE0`, `0x80-0x9F=keep`, `+n` on a single code, the precedence rules (single beats range in its section; later range wins; qualified section and `[glyphs:csN]` as before), the bounds, the 131072 limit, and why the key cannot use `u+` (the whole map is rejected).
  - **Fix the `scummvm.ini` example.** It uses inline `; ...` comments, which `ConfigManager` does not strip: `hires_text=false ; the off switch` is not `false`. Use `#` comments on their own lines, and say that the inline rule is the map's, not the ini's.
  - In the `[latin]`, `[fonts]`/`[sizes]` and `[translation]` sections, say plainly which keys SCUMM parses but does not apply (Task 2, Step 3 list), instead of implying they work.
  - Add a short "Shared with SCI" note: the same parser. The `[font.N]`, `[hires] font=/size=` and `[latin] mode=/space=` keys belong to SCI; SCUMM ignores them, but a bad value there still warns. Point to `HIRES_TEXT_MAP.md` in the docs repo.
- [ ] **Step 2: `HIRES_TEXT.md` / `HIRES_TEXT_DECORATIONS.md`:**
  - Their map examples with inline comments now parse as written, so leave them and add one sentence pointing to the rule.
  - `HIRES_TEXT.md`'s `hires_text_metrics=... ; ...` lines are `scummvm.ini`: rewrite them with own-line `#` comments.
  - Update "Verification": SCUMM tests now exist under `test/engines/scumm/`, the map parser is shared, and byte identity is checked with the command in this plan.
- [ ] **Step 3: `graphics/hires_text/README.md`:** replace "comments must occupy their own lines" with the rule, and add the range syntax to its `[glyphs]` paragraph.
- [ ] **Step 4:** Commit: `SCUMM: document inline map comments, [glyphs] ranges, and what the shared map parser leaves to SCI`. Re-check byte identity: no doc edit may touch the three shared files.

### Task 4: One map, two engines: reconcile the docs repo

**Repo:** `~/work/scummvm/docs`. **Files:** `docs/i18n/HIRES_TEXT_MAP.md`, `docs/i18n/HIRES_COMPOSITOR_DESIGN.md` §2.2.

- [ ] **Step 1: `HIRES_TEXT_MAP.md`:**
  - Replace "**Inline comments are not supported**" with the new rule. The own-line examples stay as they are: they are still valid, and own-line comments remain the clearest style.
  - Move "`[glyphs]` remap ranges" out of "Not yet implemented": the parser reads them, and a bad range warns on SCI too, since the parser is shared. SCI does not *apply* `[glyphs]` yet.
  - Add the six range warnings to "The shared map parser" warning list.
- [ ] **Step 2: `HIRES_COMPOSITOR_DESIGN.md` §2.2.** Drop the "Comments go on their own line: the INI reader keeps an inline ..." lines from the example, and replace the "Out of scope for now" bullet with one table of sections, common versus engine-specific:

  | Section / key | Parsed (shared) | SCUMM applies | SCI applies |
  |---|---|---|---|
  | `[hires] scale`, `alpha` | yes | yes | no (the compositor fixes scale; alpha by ini) |
  | `[hires] font=`/`face=`, `size=` | yes | no | yes |
  | `[encoding] codepage` | yes | yes | no (encoding comes from detection, §2) |
  | `[bitmap] multi`, `single` / `glyphs` | yes | yes / no | no |
  | `[fonts]` roles `default` / `bold`, `title` | yes | yes / no | — |
  | `[fonts]` as a name table | yes | no | yes |
  | `[sizes]` | yes | no | no |
  | `[render] metrics` / `mode` | yes | yes / no | no (per font: `[latin]`/`[font.N] metrics=`) |
  | `[latin] enabled`, `bitmap` | yes | yes (`bitmap=` implies `enabled`) | `enabled=true` is an alias; `bitmap=` warns |
  | `[latin] font`, `metrics` | yes | no | yes |
  | `[latin] mode`, `space` | yes | no | yes |
  | `[font.N]`, `[font.N:<platform>]` | yes | no | yes |
  | `[shadow] mode` (`none/drop/outline/stroke/game`), `offset`, `color` | yes | yes | no (later; `stroke` stays in the shared enum) |
  | `[glyphs]`, `[glyphs:<scope>]`, ranges | yes | yes (scopes `cs0..cs19`) | no (later) |
  | `[map] height_N` | yes | no | no |
  | `[translation] file` | yes | no | no (translation data stays out of the map, §2.2) |

  Qualifiers stay engine-defined. SCUMM uses the game id and then `v<N>`; SCI uses the platform code. Also state the comment rule and the range syntax once, and point to `HIRES_TEXT_MAP.md` for the warnings.
- [ ] **Step 3:** Commit in the docs repo (do not push): `docs/i18n: one hires_text.map for SCUMM and SCI: inline comments, [glyphs] ranges, common vs engine sections`.

### Task 5 (optional, run by the user on hpz2): SCUMM at run time

No SCUMM game data exists on the Mac, and ssh to hpz2 is not permitted from the agent. The user runs this task, or skips it; nothing above depends on it.

- [ ] **Step 1: Which real maps change.** Run
  ```bash
  grep -nE '[[:space:]];|^[[:space:]]*(0x[0-9A-Fa-f]+|[0-9]+)[[:space:]]*-' ~/games/*/hires_text.map
  ```
  plus any map named by `hires_text_map=` in `~/.config/scummvm/scummvm.ini`. Each hit is a map whose parse changes. Every other map parses exactly as before.
- [ ] **Step 2:** On hpz2, add the worktree for `wt/c5-scumm-map`, configure it per `TREES.md` (`--enable-engine=scumm,scumm_7_8,sci,agi`), and run `make -j32 && make test`.
- [ ] **Step 3:** Run `~/games/regress.sh` with that worktree's binary (the harness defaults to the main checkout: override it, per `TREES.md`), and compare with `rgdiff.py` against the `hires-text` baseline. **Expected:** zero changed targets, except the targets whose maps Step 1 listed. For each of those, the change is the one the map's inline comment describes (e.g. an outline colour appears).
- [ ] **Step 4 (optional):** A range on a real game: MI2-kor with `0x21-0x7E=+0xFEE0` in `[glyphs]` draws its Latin text from the fullwidth block, and `0x5e=keep` still shows the game's ellipsis. Crop and keep the capture next to the regression output.

## Out of scope

- SCI applying `[glyphs]` (ranges or single codes) and `[shadow]`: a later card.
- Moving SCUMM onto `[font.N]` per-charset sections, or renaming `metrics=`.
- Honouring the SCUMM keys that are parsed but not applied (`[sizes]`, `[fonts] bold/title`, `[latin] font`, `[translation]`, ...). This card only documents them honestly.
- Inline comments in `scummvm.ini` (`ConfigManager`).
- `u+` keys (an INIFile limitation; relaxing `isValidChar` would affect every INI in ScummVM).
