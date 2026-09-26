# An i18n text environment (any language by swapping the translation) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** swapping the UTF-8 translation makes any language render — Korean, Japanese, Thai — with the same engine code and the same `hires_text.map`. Glyphs are placed by per-glyph advance and bearing with zero-width combining marks; lines are broken by one shared, script-aware layout stage on code points; fonts come from a map chain checked against the translation's own code points. The Korean fan-patch formats keep working as legacy compatibility. With no translation, every game stays byte-identical to upstream.

**Spec:** `docs/i18n/I18N_TEXT_DESIGN.md` (this card's design addendum; §-references below point there). Background: `MULTI_ENGINE_TEXT_DESIGN.md` + `MULTI_ENGINE_TEXT_PLAN_5.md` (C8), `HIRES_COMPOSITOR_DESIGN.md`, `HIRES_TEXT_MAP.md`, `SCRIPT_STRINGS.md`, `DEBUG_SOCKET.md`, `TREES.md`. Ledger of C8: `~/work/scummvm/i18n/.superpowers/sdd/MULTI_ENGINE_TEXT_PLAN_5/progress.md`.

**Card:** C11, kanban `t_2780d454` (board `scummvm`).

**Architecture:**
- Shared, engine-free (`graphics/hires_text/`): Unicode properties and per-glyph metrics with combining marks (Task 1); the layout stage — decode once to a code-point `TextRun`, break and measure there, map back to bytes (Task 2); the map's face chains, `[font.N] bitmap=`, `[layout]`, and the coverage check that replaces `requireHangul` (Task 3).
- Test data for Japanese and Thai, generated in the harness (Task 4), in parallel with Tasks 1-3.
- Each engine adopts the shared pieces: SCI (Task 5), SCUMM metrics (Task 6) then SCUMM UTF-8 bundles (Task 7), AGS (Task 8), Grim (Task 9). Task 10 is the matrix and the docs.

**Decisions of 2026-09-27 (user, binding):**
1. The goal is an i18n environment: only the text is localised; any language by swapping the UTF-8 translation. Korean patch formats are legacy compatibility, not the design.
2. RTL is excluded: no RTL or bidi work at all.
3. The existing implementation is reviewed as i18n vs l10n (design §1) and the audit (design §2) drives the tasks.
4. One character = one uint32 unit for layout, so kinsoku and breaking are consistent; UTF-8 storage is fine because breaking/measuring run on the decoded array (design §3).
5. Implementers and reviewers run on Opus 5.5. The commit trailer is the one in Global Constraints.

**Decisions made in this plan (design §6):** I1 code-point `TextRun` per layout call, bytes in storage; I2 per-glyph metrics, cells only for East-Asian-Wide; I3 combining marks = zero advance + the face's negative bearing, anchored in source px; I4 class-based breaking with per-engine Hangul defaults; I5 Thai syllable-ish fallback; I6 coverage from a sample of the translation's code points; I7 UTF-8 markers per engine (SCI `sci-<lang>.str` manifest, SCUMM body BOM, AGS `encoding=utf-8`, Grim file BOM); I8 face chains in the map; I9 `TH_THA`/`VI_VNM` appended to `Common::Language`; I10 RTL, shaping and Sword out.

**Replaces from plan 5:** T4 → Task 6; T5 → Task 7; T8 → Tasks 3 and 8; T10 → dropped; T11 → Task 10. Plan 5's T3, T7, T9 and side card C10 keep running unchanged.

**Tech Stack:** C++ (`Common::` containers only), CxxTest (`make test`), FreeType through `Graphics::loadTTFFont`, the C6 headless tools, the debug socket, Python 3 + Pillow in the harness, macOS builds per worktree.

## Global Constraints

- **Progress on the board:** every subagent (impl, review, re-review, fix, final-review) posts a start and an end comment on kanban card `t_2780d454`:
  `hermes kanban --board scummvm comment --author <role> t_2780d454 "[<role> C11-T<n>] start: ..."` and `"[<role> C11-T<n>] end: <status>; <commits>; <tests>; report <path>"`. A failing comment command is noted in the report, not fatal.
- **Models:** implementers and reviewers run on Opus 5.5.
- **Trees (`TREES.md`):**
  - Never edit `~/work/scummvm/i18n` (the base) or `~/work/scummvm/repo/scummvm`'s own checkout (frozen `hires-text`).
  - Each task opens its own worktree under `~/work/scummvm/i18n/.worktrees/c11-<name>` on branch `wt/c11-<name>`, created by the implementer:
    ```bash
    git -C ~/work/scummvm/i18n worktree add .worktrees/c11-<name> -b wt/c11-<name> <base>
    ```
  - `<base>` is `i18n` once the task's prerequisites are merged into it; before that, the prerequisite branch named in the task (merge a second prerequisite with `git merge --no-ff`). Merges into `i18n` follow the C8 ledger's standing ruling (after review and the invariant runs, `merge --no-ff`, worktree removed). Nothing is pushed without that ruling.
  - `harness/i18ntrees.sh` needs bash 4 (`/opt/homebrew/bin/bash`).
- **Build (macOS).** Each worktree configures itself (ScummVM spells it `--enable-engine=`):
  ```bash
  ./configure --disable-all-engines --enable-engine=scumm,scumm_7_8,sci,ags,grim --enable-freetype2
  grep -E '^(ENABLE_SCUMM|ENABLE_SCI|ENABLE_AGS|ENABLE_GRIM) = STATIC_PLUGIN' config.mk | wc -l   # 4
  grep '^USE_FREETYPE2 = 1' config.mk
  make -j10
  PATH=/Users/juami/work/scummvm/runs/pybin:$PATH make test -j10
  ```
  `make test` must pass with pristine output. Record the count in every report (baseline: `i18n` `bee83518ad` configured scumm,scumm_7_8,sci,ags = 686 OK per the C8 ledger; count it again at the task's base, with grim, in Step 1). A task that touches `USE_FREETYPE2` code also builds once with `--disable-freetype2` and reports it clean. AGS needs `brew install mad`.
- **Reference binaries:** upstream `503d074778` = `/Users/juami/work/scummvm/repo/scummvm/.worktrees/c6-upstream/scummvm`. The **base build** of a task is a build of its `<base>` commit (reuse `c8-ref` or build one in `.worktrees/c11-ref-<task>`); the task build is `B=<worktree>/scummvm`. If C10 (32-bit SurfaceSDL screen) is merged when a task starts, both builds contain it; never compare a C10 build to a non-C10 build.
- **Captures:** `runs/c6-tools/c6add.sh`, `c6cap.sh`, `seqcmp.py`, `sheet.py`, `crop.py` (read-only; copy to change). SCI: `harness/i18n/kq1_intro.py`, `kq1_tour.py`, `scigame.py`. AGS: `runs/c8/T6/say.sh`. Each comparison is three runs: **b** (task build), **u** (reference), **u2** (reference again, noise check). Delete `frames/` after hashing. Output under `/Users/juami/work/scummvm/runs/c11/T<n>/<game>/<run>/`.
- **The C6 invariant:** a run with no translation, no `hires_text.map`, no new ini key and none of the legacy Korean files gives frames IDENTICAL-PREFIX to upstream (`seqcmp.py`), u vs u2 clean. A task that breaks it does not merge.
- **The Legacy invariant:** every shipped Korean patch renders as on the task's base build: KQ1-ko intro 0 px (vs `runs/baseline-4a0f7f0e1c/intro-ko` and vs base), `kq1_tour.py` 5 of 5 identical; MI1 UTE with `korean.trs` boot 117 IDENTICAL-PREFIX; 5 Days `korean.tra` and Deception `ags_say` crops byte-identical; Grim `grim.ko.tab` 120 s IDENTICAL-PREFIX. Only the engine a task touches is checked.
- **Engine-free shared code:** `graphics/hires_text/*` uses `common/` and `graphics/` only (no `ConfMan`, no engine headers). The shared parser changes only in Task 3, with tests; SCUMM's and SCI's existing map tests pass unedited.
- **Unknown or bad input** (map keys, ini values, font files, translation files): one warning per cause, the default is used, never a blank screen, never a crash (every offset in a file is checked against the data present; invalid UTF-8 is U+FFFD, one byte).
- **No per-frame cost on untouched paths:** a game without a translation takes none of the new code per character (e.g. AGS `U_ASCII` `split_lines()` and SCI's code-page `GetLongest()` branch are unchanged).
- **No STL** in new code (`Common::Array`, `Common::HashMap`, `Common::String`, `Common::U32String`); in `engines/ags` use the engine's own containers as surrounding code does. The ScummVM GPL header on every new source file (new test headers follow `test/graphics/hires_text_*.h`, which carry none).
- **Commits** end with exactly:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01HaZ452x9dK6wjToh3cZ3Cf
  ```
  Subjects use the ScummVM prefixes (`COMMON:`, `GRAPHICS:`, `SCUMM:`, `SCI:`, `AGS:`, `GRIM:`, `TEST:`). Harness commits use `harness:`/`c11:`.
- **Upstreaming** (constraint on upstream PRs only): upstream `AI-GUIDELINES.md` applies; the fork's `.github/workflows/check-commit-authors.yml` closes PRs with AI co-author trailers — do not touch it. AGS changes would need AGS upstream first.
- **Sample text is machine-produced** (design §5): reports say so; no claim of translation quality.
- **Reports** go to `/Users/juami/work/scummvm/runs/c11/T<n>-report.md` with `[source]`/`[measured]`/`[unmeasured]` tags and exact commands.

## Review Focus

1. **Byte identity with nothing new present** (C6) and **legacy identity** (Legacy invariant) — runs exist for every engine touched, u vs u2 clean, diffs produced by capture, not argued.
2. **One layout implementation.** No engine re-implements kinsoku, Thai rules or cluster boundaries; engines supply a `TextDecoder` (their escapes) and `LayoutMetrics` (their widths) only. Escapes survive decode at the same byte offsets (unit tests per engine decoder with its escape bytes: SCUMM `0xFF`/`0xFE` + args, `@`; SCI `|c|` codes, `0x0D 0x0A`, `0xFF20`; AGS `\n` after unescape).
3. **Language-neutral gates.** No new code tests `KO_KOR`, `JA_JPN` or a CJK code page to decide the *new* path; the new path is chosen by the translation's marker (design §4.1). Legacy paths keep their language tests, untouched.
4. **Combining marks** never advance, never start a line, never get separated from their base, and are drawn against the base's source-px anchor (tests with U+0E17 U+0E35 U+0E48).
5. **Coverage warnings** fire once per face with counts and code points; the spacing-mark warning names the face; no warning without a translation.
6. **Byte/char confusion**: every byte offset from a `LineSpan` lands on a character boundary; no buffer write past its bound (SCUMM audit).

---

### Task 1: Unicode properties, per-glyph metrics and language codes

**Worktree:** `.worktrees/c11-glyphs`, branch `wt/c11-glyph-model` off `i18n` (`bee83518ad` or later). Independent of the running C8 T3/T7/T9 (they do not edit these files); may run in parallel with them and with Task 4.

**Files:**
- New: `graphics/hires_text/unicode_props.{h,cpp}` (tables generated by `harness/i18n/c11/gen_unicode_props.py` from Python's `unicodedata`, Unicode version printed in the header comment), `test/graphics/hires_text_unicode_props.h`, `test/graphics/hires_text_glyph_metrics.h`.
- Modify: `graphics/hires_text/glyph_source.h` (`GlyphMetrics`, `metrics()`), `glyph_source_ttf.{h,cpp}` (`originX`, `metrics()`, `isWide()` forwards to `Unicode::isWide()`), `glyph_source_svfn.{h,cpp}` and `glyph_source_scvmuni.{h,cpp}` (`metrics()`), `glyph_source_routed.{h,cpp}` (forward `metrics()` to the routed source), `graphics/module.mk`, `common/language.{h,cpp}` (append `TH_THA`, `VI_VNM` after `ZH_TWN`).

**Interfaces:**
```cpp
namespace Graphics {
struct GlyphMetrics {
	int16 advance;     // source px; 0 for a combining mark
	int16 originX;     // column of the pen origin inside row(cp, y); 0 unless ink lies left of the origin
	bool combining;    // Unicode::isCombining(cp)
	bool wide;         // Unicode::isWide(cp)
};
class UnicodeGlyphSource {
public:
	// ... existing API unchanged ...
	/** false when the source has no glyph for cp. Default implementation:
	 *  cells(cp) == 0 -> false; advance = combining ? 0 : (advance(cp) ? advance(cp) : cells(cp) * advanceNarrow());
	 *  originX = 0. */
	virtual bool metrics(uint32 cp, GlyphMetrics &m);
};
namespace Unicode {
bool isWide(uint32 cp);              // EAW W or F (moved table)
bool isCombining(uint32 cp);         // general category Mn or Me
bool isThaiBase(uint32 cp);          // U+0E01..U+0E2E, U+0E40..U+0E44, U+0E4F..U+0E5B
bool isThaiLeadingVowel(uint32 cp);  // U+0E40..U+0E44
bool isThaiFollowingVowel(uint32 cp);// U+0E30, U+0E32, U+0E33, U+0E45
bool kinsokuNoStart(uint32 cp);      // design §4.3 rule 3 (SCI01 table as code points + JIS X 4051 closers)
bool kinsokuNoEnd(uint32 cp);        // design §4.3 rule 3 openers
}
}
// common/language.h: ..., ZH_TWN, TH_THA, VI_VNM, UNK_LANG = -1
// common/language.cpp g_languages[]: { "th", "th_TH", "Thai", TH_THA }, { "vi", "vi_VN", "Vietnamese", VI_VNM } (alphabetical by code)
```
`TtfGlyphSource::ensure()`: `Common::Rect box = _font->getBoundingBox(cp)`; `originX = box.left < 0 ? MIN<int>(-box.left, cellWidth) : 0`; render with `renderCoverage(_font, cp, originX, _yOffset, surf)`; everything else as today. A glyph with `box.left >= 0` produces the same row bytes as before.

- [ ] **Step 1: Baseline.** Build `<base>`; `make test` count N0; KQ1-ko intro 0 px vs `runs/baseline-4a0f7f0e1c/intro-ko` (`harness/i18n/kq1_intro.py`, as `HIRES_COMPOSITOR_DESIGN.md` §5.1).
- [ ] **Step 2: Tests first.**
  - `test_is_combining_thai`: exactly U+0E31, U+0E34..U+0E3A, U+0E47..U+0E4E are combining in U+0E00..U+0E7F (the design's measured set); U+0E33 and U+0E01 are not; U+0300 and U+0301 are; U+AC00 and U+0041 are not.
  - `test_is_wide_moved`: `Unicode::isWide()` equals the old `TtfGlyphSource::isWide()` for every cp in 0..0x10FFFF (the old table kept as a test fixture copy for this one test).
  - `test_kinsoku_tables`: every code point of SCI's `text16_shiftJIS_punctuation_SCI01` decoded as CP932 (the 29 listed in design §4.3) is `kinsokuNoStart`; `「` U+300C is `kinsokuNoEnd` and not NoStart; `あ` is neither.
  - `test_thai_classes`: `isThaiLeadingVowel(0x0E40)`, `!isThaiBase(0x0E48)`, `isThaiFollowingVowel(0x0E33)`.
  - `test_default_metrics_from_cells`: a stub source with cells 2 for U+AC00 and 1 for U+0041 and advanceNarrow 8 gives advance 16 / 8, originX 0; for U+0E48 (cells 1) gives advance 0, combining true.
  - `test_ttf_metrics_origin` (FreeType builds, font available): a face whose U+0E48 has negative left bearing (Sukhumvit extracted by Task 4 if present, else skip with a message): `originX > 0`, `advance == 0`, row has ink in columns `< originX`; U+0E01 has `originX == 0` and the same row bytes as `row()` before the change (fixture captured in Step 1 from the base build's source).
  - `test_language_codes`: `parseLanguage("th") == TH_THA`, `getLanguageCode(VI_VNM) == "vi"`, `parseLanguage("ko") == KO_KOR` unchanged.
- [ ] **Step 3:** `make test`: the new tests fail to build or fail; nothing else fails.
- [ ] **Step 4: Implement.** Generator script first (committed in the harness repo, output committed in the engine), then the moves, then `metrics()`.
- [ ] **Step 5: Verify.**
  - `make test`: N0 + new, all pass; `--disable-freetype2` clean.
  - Legacy: KQ1-ko intro 0 px, `kq1_tour.py` 5 of 5 identical vs base build.
  - C6: English KQ1 (`gamedata/King's Quest 1 ...`) intro, MI1 UTE English (no `korean.trs`) boot 117: IDENTICAL-PREFIX vs upstream.
  - The launcher's language list shows Thai and Vietnamese (screenshot not required; `--list-...` or a unit assertion suffices).
- [ ] **Step 6: Commit** (`COMMON: Add Thai and Vietnamese language codes`, `GRAPHICS: Unicode properties for hi-res text layout`, `GRAPHICS: Per-glyph metrics with bearing and combining marks in glyph sources`), report `runs/c11/T1-report.md`.

### Task 2: The shared layout stage (`TextRun`, decoders, `TextLayout`)

**Worktree:** `.worktrees/c11-layout`, branch `wt/c11-layout` off `wt/c11-glyph-model` (or `i18n` once Task 1 is merged). May run in parallel with Task 3.

**Files:** new `graphics/hires_text/text_layout.{h,cpp}`, `test/graphics/hires_text_text_layout.h`; `graphics/module.mk`.

**Interfaces:** exactly design §3.2 (`TextUnitFlags`, `kControlUnit`, `TextDecoder`, `Utf8TextDecoder`, `CodePageTextDecoder`, `TextRun`, `LayoutMetrics`, `HangulBreak`, `BreakRules`, `LineSpan`, `TextLayout::canBreakBefore/isClusterBoundary/fitLine/breakLines`), plus `bool emergency;` in `LineSpan` (the line ended without a break opportunity; Grim uses it for its dash). `CodePageTextDecoder` takes SCUMM's `charLength()` rule verbatim (`engines/scumm/hires_text.cpp:1461-1500`) and decodes the pair with `Common::U32String(bytes, page)`; SCUMM keeps its own copy until Task 7 switches it.

Rules (design §4.3), in this order in `canBreakBefore(run, i)` with `a = cp[i-1]`, `b = cp[i]`:
1. `false` if `b` is combining, or `a`/`b` is a control unit that is not a newline.
2. `true` if `a` is a space unit and `b` is not.
3. kinsoku: `false` if `kinsokuNoStart(b)` or `kinsokuNoEnd(a)`.
4. `true` if `a` or `b` is wide (Hangul syllables U+AC00..U+D7A3 and jamo only when `hangul == kHangulBreakAny`).
5. Thai: `true` if `isThaiBase(b) && !isThaiLeadingVowel(a) && !isThaiFollowingVowel(b)` and `a` is Thai or a mark on Thai.
6. `false`.

`fitLine()`: accumulate `width(run, from, i)`; stop at the first unit whose inclusion exceeds `maxWidth`; end at the last `i` with `canBreakBefore` true (or a newline, `forced`); none → the last cluster boundary that fits, `emergency = true`, at least one cluster. Trailing space units are excluded from `[first, end)` and skipped into `next`.

- [ ] **Step 1: Tests first.**
  - Decode: `"A가ที่😀"` → cps `41 AC00 E17 E35 E48 1F600`, byte offsets `0 1 4 7 10 13`, total 17; `"\xE0\x80"` → one U+FFFD of 1 byte then U+FFFD; `CodePageTextDecoder(kWindows949)` on `B0 A1 41` → lengths 2,1 (skip the code-point assertion when `encoding.dat` is absent, as C8 T1's cross-check does).
  - An escape decoder fixture (`FF 0A x y` = one control unit of 4 bytes; `FF 01` = control + newline): offsets preserved; `fitLine` never ends inside it.
  - Latin: `"the door is locked"`, metrics 1 per cp, width 10 → lines `"the door"`, `"is locked"`; `next` skips the space.
  - Japanese kinsoku: `"ここには何もない。「扉」は閉じている。"` with width such that `。` would start line 2 → it stays on line 1's end (line 1 one unit wider than width is **not** allowed: the break moves one unit earlier instead) — assert no line starts with a `kinsokuNoStart` cp and no line ends with `「`.
  - Thai: `"ที่นี่ไม่มีใครอยู่"` with marks width 0 and bases width 1: no line starts with a combining mark or a following vowel, no line ends with `ไ`/`เ`; every `LineSpan.byteStart` is a UTF-8 lead byte.
  - Hangul: `"가나다 라마바"`, `kHangulBreakWord` breaks only at the space; `kHangulBreakAny` breaks between syllables.
  - Emergency: `"Supercalifragilistic"` width 5 → `emergency` true, lines of 5.
  - Newline: a newline unit forces `forced = true` even when the line fits.
  - `breakLines` concatenation of `[byteStart, byteEnd)` plus dropped spaces reproduces the input bytes.
- [ ] **Step 2:** `make test`: new tests fail; nothing else fails.
- [ ] **Step 3: Implement** (members of `TextRun` reused across `decode()` calls: `clear()` keeps capacity).
- [ ] **Step 4: Verify.** `make test` pass; no engine file touched (`git diff --stat <base>` shows `graphics/` and `test/` only); a micro-benchmark in the test log: `breakLines` on a 300-byte Japanese string ×1000 (report ms) `[measured]`.
- [ ] **Step 5: Commit** (`GRAPHICS: Add a shared text layout stage on code points`), report.

### Task 3: Map face chains, `[font.N] bitmap=`, `[layout]`, and coverage

**Worktree:** `.worktrees/c11-map`, branch `wt/c11-map-coverage` off `wt/c11-glyph-model` (or `i18n` once Task 1 is merged). Parallel with Task 2 (disjoint files).

**Files:** `graphics/hires_text/font_map.{h,cpp}`, new `graphics/hires_text/glyph_source_fallback.{h,cpp}`, new `graphics/hires_text/coverage.{h,cpp}`, `graphics/hires_text/glyph_source_ttf.{h,cpp}` (`create()` fit probes, legacy wrapper), `test/graphics/hires_text_font_map.h` (new tests appended; existing assertions unedited), new `test/graphics/hires_text_coverage.h`, `graphics/module.mk`.

**Interfaces:**
```cpp
namespace Graphics {
// font_map.h
struct HiResFontIdSettings {
	// ... existing ...
	Common::Array<Common::Path> faceChain;   // face=a, b, c (each a [fonts] name or path, resolved); faceChain[0] == facePath
	Common::Path bitmap; bool bitmapSet;     // [font.N] bitmap= (SVFN, relative to the map)
};
struct HiResLayoutSettings {
	HangulBreak hangul; bool hangulSet;
	bool kinsoku; bool kinsokuSet;
	bool thai; bool thaiSet;
};
// HiResTextConfig gains: HiResLayoutSettings layout;   ([layout] hangul=word|any, kinsoku=on|off, thai=on|off)

// glyph_source_fallback.h
class FallbackGlyphSource : public UnicodeGlyphSource {
public:
	/** Asks each source in order; the first with cells(cp) > 0 answers. Cell size = sources[0]'s. */
	FallbackGlyphSource(const Common::Array<UnicodeGlyphSource *> &sources, DisposeAfterUse::Flag dispose);
	// cells/row/advance/metrics forwarded to the answering source; glyphCount = sum
};

// coverage.h — design §4.4
class CodePointSet { public: void addUtf8(const char *s, uint32 len); void addU32(const Common::U32String &s);
                     void add(uint32 cp); uint32 size() const; bool contains(uint32 cp) const;
                     void sample(uint n, Common::Array<uint32> &out) const; };
struct CoverageReport { uint32 sampled, missing; Common::Array<uint32> firstMissing; uint32 spacingMarks; };
CoverageReport checkCoverage(UnicodeGlyphSource *src, const Common::Array<uint32> &sample);
/** The one-line warnings of design §4.4, or empty when nothing is missing. */
Common::String coverageWarning(const Common::String &faceName, const CoverageReport &r, const Common::String &fallbackName);

// glyph_source_ttf.h
static TtfGlyphSource *create(Common::SeekableReadStream *stream, DisposeAfterUse::Flag dispose, int pixelSize,
                              Common::String &error, const uint32 *extraFitProbes, uint extraFitProbeCount);
static TtfGlyphSource *create(Common::SeekableReadStream *stream, DisposeAfterUse::Flag dispose, int pixelSize,
                              Common::String &error, bool requireHangul = false);   // legacy, unchanged behaviour
}
```
`extraFitProbes` are appended to the fixed probe set for the vertical fit only (up to 64); with none, the fit is today's.

- [ ] **Step 1: Tests first.**
  - Parser: `face=ko, ja, th` with `[fonts]` names → `faceChain` of 3 resolved paths; a single `face=` value → chain of 1 equal to `facePath` (existing behaviour); an unknown name in the chain → one warning, that entry dropped; `[font.3] bitmap=x.svfn` → `bitmapSet`, path relative to the map; `[layout] hangul=any` → set; `hangul=sideways` → one warning, default.
  - `FallbackGlyphSource` with two stub sources (A has U+AC00, B has U+0E01): `cells(0xAC00)` from A, `cells(0x0E01)` from B, `cells(0x3042) == 0`.
  - `CodePointSet`: `addUtf8("가가A")` → size 2; `sample(64)` of a 1000-cp set is deterministic, 64 long, non-ASCII first, contains the first cp of each 128-block present.
  - `checkCoverage` with a stub lacking U+0E48 and U+0E49 over a sample of 10 → `missing 2`, `firstMissing {0x0E48, 0x0E49}`; a stub whose U+0E48 metrics give `advance 12` → `spacingMarks 1`; `coverageWarning()` text matches design §4.4 exactly.
  - `create(..., requireHangul=true)` on a Latin-only face still fails with "face has no Hangul glyphs" (legacy unchanged; FreeType builds with a face available, else skip).
  - SCUMM's and SCI's existing map tests: unedited, pass.
- [ ] **Step 2:** `make test`: new tests fail; nothing else fails.
- [ ] **Step 3: Implement.** Parser first (one commit), then fallback + coverage (second).
- [ ] **Step 4: Verify.** `make test` pass; `--disable-freetype2` clean; Legacy: KQ1-ko intro 0 px (no engine change, checks the link); C6: MI1 UTE English boot 117 IDENTICAL-PREFIX vs upstream.
- [ ] **Step 5: Commit** (`GRAPHICS: hires_text.map face chains, [font.N] bitmap= and [layout]`, `GRAPHICS: Font fallback chains and translation coverage checks`), report.

### Task 4: Japanese and Thai sample data, writers and fonts (harness)

**Worktree:** none in the engine. Harness repo `~/work/scummvm` (`harness/i18n/c11/`, tracked); generated game data under `runs/c11/data/` (not committed: derived from game files). Starts immediately; parallel with Tasks 1-3.

**Files (harness):** `harness/i18n/c11/phrases_ja.txt`, `phrases_th.txt` (≥ 60 real sentences each, NFC, game-like, including the stress cases of design §5), `mktext.py` (shared: `phrase_for(source_bytes, lang)` = list[hash % n], deterministic; `--check` validates UTF-8/NFC/stress presence), `mkkq1.py` (from `gamedata/kq1-ko1`: rewrite every `text.NNN` through `harness/i18n/m12mkpatch.py` with the phrase for the English source string of the same resource/index; `sci-<lang>.str` with `sci-ko.str`'s keys), `mktrs.py` (SCVMTRS reader/writer: keeps index, room table and original strings of `korean.trs`, replaces translated strings, writes the body BOM; `--transcode` writes `ko.trs` = the CP949 bundle as UTF-8 with the BOM), `mktra.py` (AGS `.tra` writer mirroring `engines/ags/shared/game/tra_file.cpp` `WriteTraData()`: `AGSTranslation` signature, game id/name block from `korean.tra`, dictionary with the same keys, `ext_sopts` with `encoding=utf-8`, "Avis Durgan" encryption; reads back with `runs/c8/T6/trakeys.py`), `mkgrimtab.py` (`grim.<lang>.tab`, UTF-8 BOM, keys of `GRIM.TAB`), `ttc2ttf.py` (extracts face N of a TTC into a standalone TTF: copies that face's table directory and tables, recomputes offsets and `head.checkSumAdjustment`), `maps/universal.map` (the chain map of design §4.5 with absolute macOS paths + `runs/c11/data/fonts/sukhumvit-text.ttf`), `README.md` (one command per dataset).

**Outputs (`runs/c11/data/`):** `kq1-ja/`, `kq1-th/` (symlinks to the English KQ1 volumes + generated `text.NNN`, `sci-<lang>.str`, `hires_text.map`), `mi1-ja/`, `mi1-th/`, `mi1-ko8/` (symlinks to MI1 UTE + `ja.trs`/`th.trs`/`ko.trs`), `5days-ja/`, `5days-th/` (symlinks + `japanese.tra`/`thai.tra` + `hires_text.map` naming fonts 0-2), `grim-ja/`, `grim-th/` (symlinks to `kortrs/grim` LABs + `grim.<lang>.tab` + `.laf.txt` files naming the faces), `fonts/sukhumvit-text.ttf`, and `ini/*.ini` (a game domain per dataset with `language=`, `path=`, `debug_socket=` where needed).

- [ ] **Step 1: Tests first** (Python `unittest` in `harness/i18n/c11/test_c11.py`): `mktrs.py` round trip (write → read → same index/room table/original strings; translated strings equal the phrases); `mktra.py` output read by `trakeys.py` gives the same keys as `korean.tra` and `encoding=utf-8`; `ttc2ttf.py` output opens in Pillow with `getname() == ('Sukhumvit Set', 'Text')` and renders "ที่นี่ไม่มีใครอยู่" pixel-identical to `ImageFont.truetype(SukhumvitSet.ttc, 24, index=2)`; `mktext.py --check` passes for both phrase files (stress cases present, all NFC).
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.** `python3 -m unittest harness/i18n/c11/test_c11.py` pass; `du -sh runs/c11/data` reported; `head` of one generated `text.000` (`xxd`) and one `sci-ja.str` line in the report; the counts of translated entries per dataset.
- [ ] **Step 4: Commit** (harness repo: `c11: Japanese/Thai sample data generators, .trs/.tra/.tab writers, ttc2ttf`), report `runs/c11/T4-report.md`.

### Task 5: SCI — language-neutral gates, coverage, per-glyph advance, shared breaking

**Worktree:** `.worktrees/c11-sci`, branch `wt/c11-sci` off `i18n` with Tasks 1-3 merged (before that: off `wt/c11-layout` with `git merge --no-ff wt/c11-map-coverage`). Needs Task 4's `kq1-ja`/`kq1-th` for Step 4.

**Files:** `engines/sci/sci.{h,cpp}` (`heapStringsAreUtf8()`, `usesHiresDoubleByteText()`, `translationCodePoints()`), `engines/sci/engine/translation.{h,cpp}` (`isPresent()`), `engines/sci/graphics/cache.{h,cpp}` (gate, coverage, chains), `engines/sci/graphics/drivers/init.cpp` (driver row + `getRenderMode()`), `engines/sci/graphics/text16.{h,cpp}` (UTF-8 `GetLongest()` → `fitLine()`), `engines/sci/graphics/fontunicode.{h,cpp}`, `engines/sci/graphics/fontset.{h,cpp}` (advance rule, combining anchor), `test/engines/sci/translation.h`, new `test/engines/sci/i18n_gates.h`.

**Interfaces:**
```cpp
// sci.h
bool heapStringsAreUtf8() const;            // design §4.1 manifest rule
const Graphics::CodePointSet &translationCodePoints();   // lazily: TEXT resources from patch files + script-string table
// engine/translation.h
bool isPresent() const;                     // file found and parsed, even with zero entries
// graphics/cache.cpp (file-static, exposed for tests via a header in engines/sci/graphics/)
bool hiresTextApplies(SciVersion v, Common::CodePage page, bool utf8Translation, Common::String &why);
// graphics/fontunicode.h
static int16 gameAdvance(const Graphics::GlyphMetrics &m, int gameNarrow, int gameWide, int scale);
	// wide -> the cell rule of today (gameWide / gameNarrow as cells); combining -> 0;
	// else latinAdvanceGamePx(kHiResMetricsFont, gameNarrow, m.advance, scale)
// graphics/text16.h
class SciTextDecoder : public Graphics::TextDecoder { ... };   // UTF-8 + |c| codes (SCI1.1) + 0x0D/0x0A + 0xFF20
class SciLayoutMetrics : public Graphics::LayoutMetrics { ... };  // getCharWidth() of the current _font
```
Gate: `hiresTextApplies = v < SCI_VERSION_2 && (utf8Translation || page ∈ {949, 932, 936, 950})`; why-text "no translation and no CJK code page" / "SCI32 games do not support it yet". Driver: one new row `{kRenderDefault, kPlatformUnknown, SCI_VERSION_0_EARLY, SCI_VERSION_1_1, GID_ALL, UNK_LANG, ..., UpscaledGfx}` taken first when `g_sci->usesHiresDoubleByteText()` (a predicate check before the table walk), KO/JA rows kept. `getRenderMode()`: `lang == KO_KOR || g_sci->heapStringsAreUtf8()`. `GetLongest()`: `if (heapStringsAreUtf8() && !_useEarlyGetLongestTextCalculations)` → `fitLine()` with `BreakRules` from the map's `[layout]` (defaults `hangul=word`, kinsoku on, Thai on); else the existing code verbatim.

- [ ] **Step 1: Tests first.**
  - `test_script_strings_comments_only_is_present`: a stream of `# only a comment\n` → `isPresent()` true, `isLoaded()` false, `entryCount()` 0; a missing file → both false.
  - `test_hires_text_applies`: (SCI1.1, Latin1, utf8=false) → false with the why-text; (SCI1.1, Latin1, true) → true; (SCI1.1, 949, false) → true; (SCI2, 949, true) → false.
  - `test_game_advance`: wide U+AC00 at gameNarrow 4 / wide 8 → 8 (today's value); combining → 0; U+0E01 face advance 14 at scale 2 → 7; U+0E33 advance 25, scale 2 → 13.
  - `test_fitline_matches_getlongest_on_kq1ko`: for every string of `gamedata/kq1-ko1/text.*` (skip when absent) at max widths 120, 160, 200 (game px) with KQ1-ko's font-300 widths recorded in a fixture (widths per cp from the base build via `hires_text_log`, or a fixed 4/8 px rule for the test), the new UTF-8 `GetLongest()` count equals the old code's count, string by string; list any difference in the failure message.
  - `test_sci_decoder_escapes`: `"|c1|가\r\nA"` → control(4 bytes), U+AC00, newline(2 bytes), U+0041.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify (Legacy + C6).**
  - `make test` pass; `--disable-freetype2` clean.
  - Legacy: KQ1-ko (`gamedata/kq1-ko1`) intro 0 px vs `runs/baseline-4a0f7f0e1c/intro-ko` and vs base build; `kq1_tour.py` 5 of 5 identical vs base; LB1 Korean and KQ5 PC-98 (legacy code-page paths) boot capture IDENTICAL-PREFIX vs base. If any KQ1-ko frame differs (design Risk 1), report every changed frame with a crop and the code points involved; do not merge until the controller rules.
  - C6: English KQ1 (no `language=`, no map) intro IDENTICAL-PREFIX vs upstream, u vs u2 clean.
  - Cost: total ms in `GetLongest()` over the KQ1-ko intro (`g_system->getMillis()` accumulator behind `hires_text_log`), base vs task, ≤ +10 %.
- [ ] **Step 4: Verify (ja / th).** `runs/c11/data/kq1-ja` and `kq1-th` with `ini/kq1-ja.ini` (`language=ja`, map = `universal.map`): detection reports English KQ1, the log shows `SCI: script string table active` or `present`, the upscaled driver, and the coverage lines. Captures: `kq1_intro.py` (4 frames) and `kq1_tour.py` (5 stops) for each; `sheet.py` + crops of: a dialogue box with a kinsoku case (no line starts with `。` or `」`), a Thai box with stacked marks (ที่, น้ำ), the status line. Coverage: run `kq1-th` with a map whose chain is Hiragino only → one "lacks N of 64" warning naming Thai code points; with Thonburi → the spacing-mark warning.
- [ ] **Step 5: Commit** (`SCI: Decide hi-res text by the translation, not the code page`, `SCI: Per-glyph advance and combining marks in Unicode fonts`, `SCI: Break UTF-8 text with the shared layout stage`), report.

### Task 6: SCUMM per-glyph metrics, per-charset faces and chains (folds plan 5 T4)

**Worktree:** `.worktrees/c11-scumm-metrics`, branch `wt/c11-scumm-metrics` off `i18n` with C8 T3 (`wt/c8-scumm-glyphs`, running) and Tasks 1 and 3 merged (before that: off `wt/c8-scumm-glyphs` with `git merge --no-ff wt/c11-glyph-model wt/c11-map-coverage`).

**Files:** `engines/scumm/hires_text.{h,cpp}`, `engines/scumm/charset.cpp` (advance call sites: `grep -n advanceFor engines/scumm/charset.cpp`; plan 5 listed `:490, :497, :770, :1012, :1081, :1301, :2249` at `91cffbd25a`), `engines/scumm/HIRES_TEXT.md`, new `test/engines/scumm/hires_glyph_advance.h`; docs repo `docs/i18n/HIRES_TEXT_MAP.md` (separate commit there).

**Design:** SCUMM applies `[hires] face/size`, `[fonts]`, `[font.N] face/size/bitmap` with **N = charset id 0..19**, face chains (`FallbackGlyphSource`), and `[latin]` with SCI's meanings (plan 5 T4, kept). Advance per glyph: `advanceFor(chr, charsetId, gameWidth, carry)` → for a code point with `GlyphMetrics m`: wide → today's cell rule; combining → 0; otherwise `latinAdvanceGamePx(metrics, gameWidth, m.advance, scale)` when the face gives an advance (`metrics=font`, default for non-ASCII non-wide), and ASCII follows `[latin]` exactly as plan 5 T4 specified (off → the game's width). `drawChar()` keeps `_anchorX` (overlay px, after the previous base) and draws a combining glyph at `_anchorX - m.originX` without moving the pen. Coverage: at `loadFonts()`, when a bundle is loaded, sample 64 code points of the bundle's translated strings (decoded with the bundle's page) and warn per face (design §4.4). MI2: `HIRES_TEXT.md` gains the MI2 example map that keeps `0x5c=keep`, `0x60=keep`.

- [ ] **Step 1: Tests first.** `test_font_n_is_charset_id` (`[font.2] size=24` changes charset 2 only); `test_metrics_font_advance` (same values as `test/graphics/hires_text_latin_advance.h`: face 13 at scale 2 → 7, face 9 → 5, face 0 → the game width); `test_wide_keeps_cell` (U+AC00 at a 16-px cell, scale 2 → today's value, byte-identical to the base build's `advanceFor`); `test_combining_zero_advance` (U+0E48 → 0, pen unchanged, the glyph's coverage lands left of the pen by `originX`); `test_metrics_game_centres_narrow_glyph` (a 10-px glyph in a 16-px cell at x+3); `test_mi2_keeps_5c_60`; `test_chain_answers_by_coverage` (a two-face chain draws U+0E01 from the second face).
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.**
  - `make test` pass; `--disable-freetype2` clean.
  - C6: group A (`mi1ute` boot 117, `mi2ute` boot 8999, `indy3vga`, `indy4cd`, `loomcd`, `loomtowns` boot 1, `samnmax` `subtitles=true`), no translation, hi-res off: IDENTICAL-PREFIX vs upstream.
  - Legacy: MI1 UTE `korean.trs` + the C6-B SVFN maps (`runs/c6/B` `ft`, `mm2`, `zakt`) with none of the new keys: IDENTICAL-PREFIX vs the C8 T3 build.
  - `metrics=font` on MI1 UTE Korean boot 117 with AppleSDGothicNeo at `[hires] size=24`: crop before/after; report the mean gap between syllables in hi-res px (the letter-spacing C6 finding).
- [ ] **Step 4: Commit** (`SCUMM: Per-glyph advance, per-charset faces and font chains from hires_text.map`), docs commit, report.

### Task 7: SCUMM UTF-8 `<lang>.trs` and shared breaking (folds plan 5 T5)

**Worktree:** `.worktrees/c11-scumm-utf8`, branch `wt/c11-scumm-utf8` off `wt/c11-scumm-metrics` with Task 2 merged in (`git merge --no-ff wt/c11-layout` if not yet in `i18n`). Needs Task 4's `mi1-*` data.

**Files:** `engines/scumm/scumm.h` (`_textUtf8`, `textCharLength()`), `engines/scumm/string.cpp` (`loadLanguageBundle()` BOM detection + `CodePointSet`; sites `:1265, :1542, :1698`; `getDialogCodePage()`), `engines/scumm/string_v7.cpp` (`:79, :136, :168`), `engines/scumm/charset.cpp` (`loadCJKFont()` short-circuit, `addLinebreaks()` → `addLinebreaksLayout()` when `_textUtf8`, `getStringWidth()`), `engines/scumm/hires_text.{h,cpp}` (`decodeNext()` uses `Graphics::Utf8TextDecoder`/`CodePageTextDecoder`; `ScummTextDecoder` with the escapes of design §3.3), new `test/engines/scumm/text_char_length.h`, `test/engines/scumm/trs_utf8.h`.

**Interfaces:**
```cpp
// scumm.h
bool _textUtf8;                                                  // set by loadLanguageBundle()
int textCharLength(const byte *p, const byte *end) const;        // UTF-8 1..4 by lead (stray continuation -> 1) when _textUtf8,
                                                                 // else exactly is2ByteCharacter(_language, *p) ? 2 : 1 (checkKSCode where the site used it)
// trs_bundle.h
bool trsBodyIsUtf8(const byte *body, uint32 size);               // body starts EF BB BF
// charset.h
void addLinebreaksLayout(int a, byte *str, int pos, int maxwidth, int bufSize);
class ScummTextDecoder : public Graphics::TextDecoder { public: ScummTextDecoder(int version, bool he, byte newLineChar); ... };
```
Rules: `_textUtf8` = body BOM, or ini `text_encoding=utf8` for an unmarked bundle (unmarked + valid UTF-8 with a multi-byte sequence → one hint). With `_textUtf8`: `loadCJKFont()` does not enter `loadKorFont()`/the JA/ZH branches (the hi-res layer draws); `_useCJKMode` stays false; `getDialogCodePage()` → `kUtf8`; `addLinebreaksLayout()` uses `fitLine()` with `hangul=any` (the Korean patches' rule) unless the map's `[layout]` says otherwise, writes `0x0D` at `byteEnd` (replacing a space when `byteNext > byteEnd`, else `memmove`-insert bounded by `bufSize`, truncating at a character boundary). Hi-res **off** with a UTF-8 bundle: the language's legacy page if it has one (ko → CP949, ja → CP932, zh → 936/950: transcode at load, unmappable → `?`, logged once by code point); otherwise (th, vi, ...) one warning "a UTF-8 translation needs hi-res text (hires_text.map or hires_text_font)" and text drawn as `?`. The josa/verb-glue code (`string.cpp:1805-1990`) stays reachable only through `isScummvmKorTarget()` with CP949 (Korean grammar is not generalised).

**Buffer audit first:** a table in the report of every fixed-size buffer reachable from translated text (`_charsetBuffer`, the actor talk buffer, verb name slots, `_msgPtrToAdd` targets, `addLinebreaks()` insert room, save descriptions), its size, and the worst case at 3 bytes per code point with up to 2 marks per base (Thai). Any that can overflow gets a bound check that truncates at a `textCharLength()` boundary.

Also list every `_language == Common::JA_JPN` / `KO_KOR` / `ZH_*` site (`grep -n '_language ==' engines/scumm/*.cpp`) and state for each whether it is reachable with `_textUtf8` on DOS MI1/MI2/Indy/Loom; gate the reachable ones on `!_textUtf8` (design Risk 4).

- [ ] **Step 1: Tests first.** `test_utf8_lengths` (`"A"`→1, `EA B0 80`→3, `F0 9F 98 80`→4, `0x80`→1); `test_escape_bytes_never_inside_utf8` (every U+0080..U+FFFF encoded: no byte is `0xFE`, `0xFF`, `@`, `^`, `\`, `` ` ``); `test_non_utf8_is_old_expression` (every lead 0x00..0xFF under KO/JA/ZH: equals `is2ByteCharacter`); `test_trs_body_bom` (a two-entry SCVMTRS with body BOM → `_textUtf8`; without → false; with `text_encoding=utf8` → true); `test_scumm_decoder_escapes` (`FF 0A x y`, `FF 01`, `@` → control units, offsets kept); `test_linebreaks_layout_matches_cp949` (for the first 200 entries of MI1 UTE `korean.trs` (skip when absent), `addLinebreaksLayout()` on the UTF-8 transcode breaks at the same character positions as `addLinebreaks()` on the CP949 bytes, at the game's line widths).
- [ ] **Step 2: Implement** (audit table first, in the report).
- [ ] **Step 3: Verify.**
  - C6: group A no translation IDENTICAL-PREFIX vs upstream (hi-res on and off).
  - Legacy: MI1 UTE `korean.trs` (CP949) boot 117 hi-res on and off IDENTICAL-PREFIX vs Task 6's build.
  - Equivalence: `mi1-ko8` (`ko.trs` UTF-8 from `mktrs.py --transcode`, `language=ko`, same map) vs the CP949 run: IDENTICAL-PREFIX, hi-res on; hi-res off: IDENTICAL-PREFIX to the CP949 hi-res-off run.
  - ja/th: `mi1-ja`, `mi1-th` (`language=ja`/`th`, `universal.map`) boot 117 + the opening conversation (`c6cap.sh` frames 0-900): `sheet.py` and crops of a verb line, a two-line subtitle with a kinsoku case, a Thai line with stacked marks; the log shows the coverage lines and no "encoding.dat" error.
- [ ] **Step 4: Commit** (`SCUMM: Accept UTF-8 translation bundles in any language`, `SCUMM: Break UTF-8 text with the shared layout stage`), report.

### Task 8: AGS — UTF-8 primary, map fonts with chains, shared breaking (folds plan 5 T8)

**Worktree:** `.worktrees/c11-ags`, branch `wt/c11-ags` off `i18n` with C8 T7 (`wt/c8-ags-extfnt`, running) and Tasks 1-3 merged. Needs Task 4's `5days-*` data and C8 T2's socket (merged).

**Files:** new `engines/ags/shared/font/hires_font_config.{h,cpp}` (reads the map with qualifier = game id; `[font.N] face` chain / `bitmap` / `size`), new `engines/ags/shared/font/glyph_font_renderer.{h,cpp}` (an `IAGSFontRenderer` over any `Graphics::UnicodeGlyphSource`: TTF chain or SVFN), `engines/ags/shared/font/fonts.cpp` (`load_font_size()` renderer choice; `split_lines()` layout branch), `engines/ags/engine/ac/translation.cpp` (collect the `.tra` values' `CodePointSet` when `U_UTF8`), `test/engines/ags/glyph_renderer.h`, `test/engines/ags/split_lines_layout.h`.

**Design:**
- Font N with `[font.N] bitmap=` → `GlyphFontRenderer` over `SvfnGlyphSource`; with `face=` (a chain) or ini `hires_text_font` → `GlyphFontRenderer` over a `FallbackGlyphSource` of `TtfGlyphSource`s at `size` (default: the game's size for font N); else today's `agsfnt`/`extfnt` renderers. The map is read only when the game dir has `hires_text.map` or the ini names `hires_text_map`.
- `GlyphFontRenderer::RenderText()`: per glyph, `metrics()`; combining glyphs against the anchor (design §4.2); coverage `c`: 16/32-bit destination and `[hires] alpha` (default true) → `dst = TextCompose::blend(dst, colour, c)`; 8-bit → `c >= 128` → `putpixel(colour)`. `GetTextWidth()` = sum of advances (0 for marks).
- alfont (`agsfntN.ttf` of the game, no map): `[unmeasured]` negative bearing. Measure it in Step 3 on "ที่นี่" with Sukhumvit as `agsfnt0.ttf` in a scratch copy; if the mark is clipped or advanced, UTF-8 translations with a `.ttf` game font but no map get a one-line log hint to add a map (no alfont change).
- `split_lines()`: `if (get_uformat() != U_ASCII)` → `TextRun::decode` (UTF-8 or EUC-KR decoder), `breakLines()` with `AgsLayoutMetrics::width()` = `get_text_width_outlined()` on the byte range (keeps the `wii -= 1` quirk and outline arithmetic), `hangul=word`; lines added from `[byteStart, byteEnd)`; `max_lines` and the `"..."` rule unchanged. `U_ASCII` path byte-for-byte unchanged.

- [ ] **Step 1: Tests first.** Coverage blend into a 4×1 32-bit bitmap: 0/64/128/255 of white over black → 0x00/0x40/0x80/0xFF; 8-bit → 0/0/colour/colour; `GetTextWidth("가A")` = the two advances; `GetTextWidth("ที่")` = the advance of U+0E17 only. `split_lines` layout branch (link only the pure adapter if the AGS globals make `libags.a` impractical, as C8 T6 did with `unicode_euckr.*`, and say so): a Japanese string never starts a line with `。`; the ASCII branch is not entered for `U_UTF8`.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.**
  - C6: 5 Days, Primordia, Shardlight, Winter's Night without a translation: IDENTICAL-PREFIX vs upstream.
  - Legacy: 5 Days `korean.tra` + extfnt, Deception (`agsfnt3.ttf`): `ags_say` crops byte-identical vs the C8 T7 build (`runs/c8/T6/say.sh`).
  - ja/th: `5days-ja`, `5days-th` (`thai.tra`, `--language=th` now resolves via `TH_THA` → description "thai"; `japanese.tra` via `--language=ja`): log `Translation initialized: thai (format: utf-8)`; `ags_say` at fonts 0/1/2 on three entries each (one long enough to wrap): crops; distinct colours inside the text box (blend check); a two-line Japanese box with a kinsoku case.
  - alfont measurement above, crop, `[measured]`.
- [ ] **Step 4: Commit** (`AGS: Fonts from hires_text.map: glyph-source renderer with chains and coverage alpha`, `AGS: Break non-ASCII text with the shared layout stage`), report.

### Task 9: Grim — `grim.<lang>.tab`, UTF-8 BOM, shared breaking

**Worktree:** `.worktrees/c11-grim`, branch `wt/c11-grim` off `i18n` with C8 T9 (`wt/c8-grim-alpha`, running) and Task 2 merged. Needs Task 4's `grim-*` data.

**Files:** `engines/grim/localize.cpp` (file name, BOM), `engines/grim/font.cpp` (`FontTTF` decodes CP949 only when the tab is not UTF-8: `KO_KOR && !g_grim->_isUtf8`), `engines/grim/textobject.cpp` (`setupTextReal<U32String>` → `TextRun::assign()` + `breakLines()`), `test/graphics/hires_text_text_layout.h` (a Grim-shaped case: dash rule).

**Design:** `Localizer`: `lang = ConfMan language (forced) or the detected language`; for Grim (not remaster, not demo) try `grim.<code>.tab` first when `lang != EN`, then `grim.ko.tab` for `KO_KOR`, then `grim.tab` (today's order preserved when no `grim.<code>.tab` exists). Magic `EF BB BF` → strip 3 bytes, `_isUtf8 = true`, parse as the plain-text case. Breaking: `hangul=word`, kinsoku and Thai on; `-` appended only when `LineSpan::emergency` and both sides of the split are Latin letters (replaces the Chinese exception at `textobject.cpp:248`).

- [ ] **Step 1: Tests first.** In the shared layout test: emergency split of `"abcdefgh"` → `emergency` true (Grim adds `-`); of `"ここには何もない"` → break opportunities exist, `emergency` false (no dash); a Thai run → `emergency` false. A pure helper `bool Grim::stripUtf8Bom(const char *&data, int32 &size)` tested in `test/engines/grim/localize.h` if the test runner can link it, else in the report as `[source]` only.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.**
  - Legacy: `gamedata/kortrs/grim` Korean (`grim.ko.tab`), TinyGL, 120 s: IDENTICAL-PREFIX vs the C8 T9 build.
  - C6-like: the same data with `language=en` (`GRIM.TAB`): IDENTICAL-PREFIX vs upstream TinyGL.
  - ja/th: `grim-ja`, `grim-th` (`language=ja`/`th`, `.laf.txt` → Hiragino / Sukhumvit), TinyGL and OpenGL shaders: the intro subtitles (socket `lua_do` fallback as in C8 T9 if none appear in 120 s): crops with a wrapped line; Thai marks placed (Grim's `TTFFont::drawString()` already applies bearing, design §4.2 `[unmeasured]` → now measured).
- [ ] **Step 4: Commit** (`GRIM: Load grim.<lang>.tab and UTF-8 tables for any language`, `GRIM: Break UTF-8 text with the shared layout stage`), report.

### Task 10: Matrix and docs

**Worktree:** docs repo (`~/work/scummvm/docs`) for the docs; captures on the merged `i18n` (Tasks 1-9 and C8 T3/T7/T9 merged).

**Files (docs repo):** `docs/i18n/I18N_TEXT_DESIGN.md` (a `[measured]` section per engine: the matrix, crops, and the `[unmeasured]` items of design §4 and §8 resolved), `docs/i18n/HIRES_TEXT_MAP.md` (chains, `bitmap=`, `[layout]`, a worked "one map, three languages" example), `docs/i18n/SCRIPT_STRINGS.md` (the manifest rule replaces "currently true only for KO_KOR"), `docs/i18n/TREES.md` (`wt/c11-*` fate), `docs/i18n/MULTI_ENGINE_TEXT_DESIGN.md` §11 (C8 matrix, plan 5 T11's content: groups A, C, D with and without the Korean trigger).

- [ ] **Step 1:** Full matrix on the merged build vs upstream `503d074778`: rows = SCI KQ1, SCUMM MI1 UTE (+ group A for C6), AGS 5 Days (+ Primordia, Shardlight, Winter's Night for C6), Grim; columns = none (C6, IDENTICAL-PREFIX expected), ko legacy (Legacy invariant, vs the pre-C11 `i18n` build), ko UTF-8 (SCI KQ1-ko, SCUMM `ko.trs`), ja, th (crops). Table in the design doc, each cell with its run path.
- [ ] **Step 2:** Update the docs; one commit per file group, with the trailer.
- [ ] **Step 3:** Post the matrix path on `t_2780d454`.

## Out of scope

- RTL and bidi (user decision); complex shaping (HarfBuzz); dictionary line breaking (Thai/Lao/Khmer); input of translated text.
- Sword1/2 (plan 5 T10 dropped: resource-level Korean, no text override format).
- TTC face selection in `loadTTFFont()` (harness extracts faces).
- Hi-res supersampled text for AGS; SCUMM `HiResOverlay` → SCI `TextLayer` unification; SCUMM HE; Grim remaster/EMI; SCI32.
- Generalising SCUMM's Korean josa/verb glue (Korean grammar, not rendering).

## Order and dependencies

```
T1 glyph-model ──┬── T2 layout ──────────────┬── T5 sci ─────────────────────────┐
(parallel with   └── T3 map-coverage ────────┤                                   │
 C8 T3/T7/T9, C10)                           ├── T6 scumm-metrics ── T7 scumm-utf8 ┤
T4 sample data (harness, from the start) ────┤   (needs C8 T3 merged)             │
                                             ├── T8 ags (needs C8 T7 merged) ─────┤
                                             └── T9 grim (needs C8 T9 merged) ────┴── T10 matrix + docs
```

- Tasks 1 and 4 start now. Tasks 2 and 3 run in parallel after Task 1.
- Task 5 needs 2 + 3 (+ 4 for Step 4). Task 6 needs 1 + 3 + C8 T3. Task 7 needs 6 + 2. Task 8 needs 1-3 + C8 T7. Task 9 needs 2 + C8 T9. Tasks 5, 6-7, 8, 9 touch disjoint engines and may run in parallel (expect `test/module.mk` conflicts only).
- C10 (32-bit SurfaceSDL screen) is independent in code; it only constrains which builds are compared (Global Constraints).
