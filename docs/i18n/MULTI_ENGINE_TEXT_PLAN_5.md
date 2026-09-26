# Unicode, TTF and 8-bit alpha text for SCUMM, AGS, Grim and Sword1/2 — Implementation Plan

> **Superseded by `I18N_TEXT_PLAN_6.md` for T4/T5/T8/T10/T11** (card C11, `t_2780d454`, 2026-09-27). The user reframed the goal as an i18n environment - only the text is localised, and swapping the UTF-8 translation makes any language (Japanese, Thai, ...) render with the same engine code and map - so the Korean-specific shape of those tasks is replaced: T4 (SCUMM per-font/proportional) becomes plan 6 Task 6 with per-glyph metrics and combining marks; T5 (SCUMM UTF-8) becomes Task 7 with `<lang>.trs`, a body BOM (a `korean.trs` cannot begin with `EF BB BF`, it begins with `SCVMTRS `) and the shared layout stage; T8 (AGS map) becomes Tasks 3 and 8; T10 (Sword) is dropped; T11 (matrix) becomes Task 10 with ja/th columns. T1, T2 and T6 (merged) and T3, T7, T9 (running) stand as written. Design: `I18N_TEXT_DESIGN.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the engines the Korean fan patches (`kortrs/`) need, beyond SCI, draw text from a TrueType face or an 8-bit coverage bitmap font, look glyphs up by Unicode code point, accept UTF-8 input, and keep reading the legacy CP949/EUC-KR files the patches ship. With no new key and no new file, every game stays byte-identical to upstream.

**Spec:** `docs/i18n/MULTI_ENGINE_TEXT_DESIGN.md` (this card's design; §-references below point there), `HIRES_COMPOSITOR_DESIGN.md` (SCI's path, the model), `HIRES_TEXT_MAP.md` (the map), `DEBUG_SOCKET.md`, `TREES.md`. Evidence: `runs/c6-report-{A,C,D}.md`, `runs/c6-tools/README.md` (harness repo).

**Architecture:**
- The engine-free glyph code moves from `engines/sci/graphics/` to `graphics/hires_text/` (namespace `Graphics`) and gains an SVFN adapter and a Korean code-page helper (Task 1). Every later task builds on it.
- The SCI debug socket becomes engine-neutral in `gui/`, so AGS, Grim and Sword can be driven headless to their Korean text (Task 2).
- SCUMM moves from bake-at-load to the lazy shared sources, gets per-glyph advance and UTF-8 input (Tasks 3-5).
- AGS gets an EUC-KR text format, the patches' `extfntN.wfn`, and map-driven TTF/SVFN fonts (Tasks 6-8).
- Grim draws Korean TTF lines with alpha on TinyGL and shaders (Task 9). Sword1/2 route Korean glyphs through the shared source, hard-edged (Task 10, optional). Task 11 is the regression matrix and the docs.

**Decisions of 2026-09-26 (user, binding):**
1. AGS, Sword1/2, Grim and **SCUMM** are in scope; **SCUMM goes first.** SCUMM reaches parity with SCI's glyph side: live FreeType with a lazy per-code-point cache, the 8bpp bitmap source, Unicode input, CP949 legacy input still working.
2. SCUMM tasks build on C7 (`t_e9516789`, `wt/c7-erase`: the `restoreCharsetBg` erase fix for `babb7a17d4`).
3. Implementers and reviewers run on Opus 5.5. The commit trailer is the one in Global Constraints.

**Decisions made in this plan (design §3):**
- Shared glyph interface = SCI's `UnicodeGlyphSource`, moved, not re-invented (E1).
- The 8-bit alpha bitmap format for every engine gaining one here is **SVFN** (E2); SCI keeps SCVMUNI.
- Bytes stay bytes inside each engine; code points (UTF-32) start at the glyph interface. Per engine: SCUMM CP949 or UTF-8 (opt-in); AGS UTF-8 (native) or **EUC-KR** (legacy `.tra`); Grim CP949 or UTF-8 (BOM/map); Sword CP949 (E3, §3.1).
- Compositing per engine: SCUMM keeps `HiResOverlay`; AGS and Grim blend directly (true colour); Sword stamps hard edges, no alpha (E4, §5).
- Legacy patch files are read as shipped (E6). AGS Korean `.tra` detection is on by default (`text_encoding=auto`) — open question 1 lets the user flip it to opt-in.

**Tech Stack:** C++ (`Common::` containers only), CxxTest (`make test`), FreeType through `Graphics::loadTTFFont`, the C6 headless tools (SDL dummy, frame hashes), macOS builds per worktree.

## Global Constraints

- **Progress on the board:** every subagent (impl, review, re-review, fix, final-review) posts a start and an end comment on kanban card `t_b46cb319` (board `scummvm`):
  `hermes kanban --board scummvm comment --author <role> t_b46cb319 "[<role> C8-T<n>] start: ..."` and `"[<role> C8-T<n>] end: <status>; <commits>; <tests>; report <path>"`. A failing comment command is noted in the report, not fatal.
- **Models:** implementers and reviewers run on Opus 5.5.
- **Trees (`TREES.md`):**
  - Never edit `~/work/scummvm/i18n` (the base) or `~/work/scummvm/repo/scummvm`'s own checkout (frozen `hires-text`).
  - Each task opens its own worktree under `~/work/scummvm/i18n/.worktrees/<id>` on branch `wt/c8-<name>` (named per task), created by the implementer:
    ```bash
    git -C ~/work/scummvm/i18n worktree add .worktrees/<id> -b wt/c8-<name> <base>
    ```
  - `<base>` is `i18n` once the task's prerequisites are merged into it; before that, the prerequisite branch named in the task. Merges into `i18n` happen with the user, `merge --no-ff`, worktree removed afterwards. Nothing is pushed without the user.
  - `harness/i18ntrees.sh` needs bash 4 (`/opt/homebrew/bin/bash`), not macOS bash 3.
- **Build (macOS).** Each worktree configures itself:
  ```bash
  ./configure --disable-all-engines --enable-engines=scumm,scumm_7_8,sci,ags,sword1,sword2,grim --enable-freetype2
  grep -E '^(ENABLE_SCUMM|ENABLE_SCI|ENABLE_AGS|ENABLE_GRIM|ENABLE_SWORD1|ENABLE_SWORD2) = STATIC_PLUGIN' config.mk | wc -l   # 6
  grep '^USE_FREETYPE2 = 1' config.mk
  make -j10
  PATH=/Users/juami/work/scummvm/runs/pybin:$PATH make test -j10
  ```
  `make test` must pass with pristine output. Record the test count in every report (`i18n` baseline: count it once at `91cffbd25a` in Task 1, Step 1).
  AGS needs `brew install mad`. A task that touches `USE_FREETYPE2` code also builds once with `--disable-freetype2` and reports it clean.
- **Reference binaries** (`runs/c6-builds-ready`): upstream `503d074778` = `/Users/juami/work/scummvm/repo/scummvm/.worktrees/c6-upstream/scummvm`; i18n `91cffbd25a` = `/Users/juami/work/scummvm/i18n/.worktrees/c6-test/scummvm`. The C8 build of the task under test is `B=<worktree>/scummvm`.
- **Captures:** `runs/c6-tools/c6add.sh`, `c6cap.sh`, `seqcmp.py`, `sheet.py` (read-only; copy to change). `c6cap.sh` already passes `--extrapath=<c6-test>/dists/engine-data` (`encoding.dat`). Each comparison is three runs: **b** (task build), **u** (upstream or the named reference), **u2** (the reference again, noise check). Delete `frames/` after hashing. Output under `/Users/juami/work/scummvm/runs/c8/<task>/<game>/<run>/`.
- **The invariant, everywhere:** a run with no `hires_text.map`, no new ini key and none of the legacy Korean files of design E6 gives frames IDENTICAL-PREFIX to the reference (`seqcmp.py`), with u vs u2 as the noise check. A task that breaks it does not merge.
- **The shared parser** (`graphics/hires_text/font_map.*`) stays engine-free (`common/` only, no `ConfMan`). Only Task 8 changes it (`[font.N] bitmap=`), with tests, and SCUMM's and SCI's existing map tests pass unedited.
- **Unknown or bad input** (map keys, ini values, font files): one warning per cause, the default is used, never a blank screen, never a crash on a patch file (every offset in a font file is checked against the data present).
- **No STL** in new code (`Common::Array`, `Common::HashMap`, `Common::String`); in `engines/ags` use the engine's own containers as surrounding code does, no new `<vector>`/`<map>` includes. The ScummVM GPL header on every new source file (new test headers follow the existing `test/graphics/hires_text_*.h`, which carry none).
- **Commits** end with exactly:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01HaZ452x9dK6wjToh3cZ3Cf
  ```
  Commit subjects use the ScummVM prefixes (`GRAPHICS:`, `SCUMM:`, `AGS:`, `GRIM:`, `SWORD1:`, `SWORD2:`, `SCI:`, `GUI:`, `TEST:`).
- **Upstreaming** (constraint on upstream PRs only, not on the fork): upstream `AI-GUIDELINES.md` applies, and the fork's inherited `.github/workflows/check-commit-authors.yml` closes PRs whose commits carry an AI co-author trailer. Do not touch that workflow; the user handles it. AGS changes would also need AGS upstream first.
- **Reports** go to `/Users/juami/work/scummvm/runs/c8/T<n>-report.md` with `[source]`/`[measured]`/`[unmeasured]` tags and exact commands.

## Review Focus

1. **Byte identity with nothing new present** — the invariant runs exist for every engine the task touches, u vs u2 is clean, and the diff was produced by capture, not argued.
2. **Code points at the glyph interface, bytes elsewhere.** No engine VM string becomes UTF-32; each decoder is one function with a unit test that includes the escape bytes of that engine (SCUMM `0xFF`/`0xFE`, `@`, `^`, `\`; AGS `[`).
3. **Legacy files are parsed defensively.** `extfntN.wfn` offsets, SVFN headers, `.laf.txt` lines, `bsNk.fnt` sizes: truncated or corrupt input gives a warning and the old path, never an out-of-bounds read (tests with truncated files).
4. **The moved SCI code is moved, not changed** (`git diff -M` shows renames plus namespace edits), and SCI's KQ1-ko capture is 0 px.
5. **Scope gates are exact**: AGS EUC-KR only for a Korean `.tra` without an `encoding` option (or an explicit key); Grim's renderer change only for TTF fonts; Sword's adapter returns today's bytes when no map exists.
6. **No per-frame work added to untouched paths** (e.g. a HashMap lookup per character in AGS ASCII games).

---

### Task 1: Shared glyph sources in `graphics/hires_text/`

**Worktree:** `~/work/scummvm/i18n/.worktrees/c8-glyphsrc`, branch `wt/c8-glyphsrc` off `i18n` (`91cffbd25a`).

**Files:**
- Move (`git mv`, then edit namespace/includes): `engines/sci/graphics/glyphsource.h` → `graphics/hires_text/glyph_source.h`; `glyphsource_ttf.{h,cpp}` → `glyph_source_ttf.{h,cpp}`; `glyphsource_scvmuni.{h,cpp}` → `glyph_source_scvmuni.{h,cpp}`; `glyphsource_routed.{h,cpp}` → `glyph_source_routed.{h,cpp}`; `textcompose.{h,cpp}` → `text_compose.{h,cpp}` (with `TextPixel`, which `textlayer.h` then includes); `latinadvance.{h,cpp}` → `latin_advance.{h,cpp}` (`latinAdvanceGamePx()`, used by SCUMM in Task 4).
- New: `graphics/hires_text/glyph_source_svfn.{h,cpp}`, `graphics/hires_text/codepage_kr.{h,cpp}`.
- Modify: `graphics/module.mk`, `engines/sci/module.mk`, every SCI include site (`fontunicode.*`, `fontset.*`, `cache.cpp`, `textlayer.*`, `drivers/upscaled.cpp`, ...: `grep -rln 'glyphsource\|textcompose' engines/sci`).
- Tests: `test/engines/sci/glyphsource.h` → `test/graphics/hires_text_glyph_source.h`, `test/engines/sci/textcompose.h` → `test/graphics/hires_text_text_compose.h`, `test/engines/sci/latinadvance.h` → `test/graphics/hires_text_latin_advance.h` (content unchanged but for namespace); new `test/graphics/hires_text_svfn_source.h`, `test/graphics/hires_text_codepage_kr.h`.

**Interfaces:**
```cpp
namespace Graphics {
class UnicodeGlyphSource;                 // unchanged API (cellWidth, cellHeight, advanceNarrow, advanceWide,
                                          // bitsPerPixel, cells(cp), row(cp, y), advance(cp), glyphCount)
class TtfGlyphSource : public UnicodeGlyphSource {
public: static TtfGlyphSource *create(Common::SeekableReadStream *stream, DisposeAfterUse::Flag dispose,
                                      int pixelSize, Common::String &error, bool requireHangul = false);
};
class SvfnGlyphSource : public UnicodeGlyphSource {
public:
	/** Takes ownership of @p font when dispose is YES. Same row layout as TtfGlyphSource
	 *  (stride cellWidth()*2 px at bitsPerPixel()), so TextCompose::expandGlyphRow reads it. */
	SvfnGlyphSource(HiResBitmapFont *font, DisposeAfterUse::Flag dispose);
	int advance(uint32 cp) override;       // the SVFN per-glyph advance, 0 without a metrics table
	int bearingX(uint32 cp) const;         // SVFN bearingX, for proportional placement
};
namespace KoreanCodePage {
bool isEucKrPair(byte hi, byte lo);        // both in 0xA1..0xFE
int ksx1001HangulIndex(byte hi, byte lo);  // (hi-0xB0)*94 + (lo-0xA1) for hi 0xB0..0xC8, lo 0xA1..0xFE; else -1
int ksx1001HangulIndexOf(uint32 cp);       // reverse, via a table built once from U32String(pair, kWindows949); -1 if none
uint32 decodeEucKrPair(byte hi, byte lo);  // code point, or 0 when the pair is not in the table
}
}
```

- [ ] **Step 1: Baseline.** In a fresh `i18n` build (`c6-test` worktree is fine), run `make test` and record the count N0. Capture KQ1-ko intro with the SCI harness as in `HIRES_COMPOSITOR_DESIGN.md` §5.1 (`kq1_intro.py`, baseline `runs/baseline-4a0f7f0e1c/intro-ko`) and confirm 0 px.
- [ ] **Step 2: Tests first.**
  - `test_svfn_source_matches_bitmap_font`: a 3-glyph 8bpp SVFN v2 built in memory with `HiResFontBaker::bake()` (FreeType builds) or hand-written bytes (both builds: a hand-written 1bpp and 8bpp v2 file of 3 glyphs U+0041, U+AC00, U+D7A3); every `row(cp, y)` byte equals `glyphData(index)` for that row, `cells()` is 1 for U+0041 and 2 for U+AC00, 0 for U+0042; `advance()` equals the metrics table's advance.
  - `test_svfn_source_truncated_file`: the same file cut at 20, 40 and N-1 bytes loads as nothing (`HiResBitmapFont::load` false) and the adapter is never built.
  - `test_ksx1001_index`: `ksx1001HangulIndex(0xB0,0xA1)==0`, `(0xC8,0xFE)==2349`, `(0xB0,0xA0)==-1`, `(0xC9,0xA1)==-1`; `ksx1001HangulIndexOf(0xAC00)==0` (가), `(0xD79D)==2349` (힝, pair `C8 FE`), `(0xB9E4)==788` (매, pair `B8 C5`), `(0xD7A3)==-1` (힣 is not in KS X 1001); `decodeEucKrPair(0xB0,0xA1)==0xAC00`; `isEucKrPair(0xE9,0x62)==false` (é + b).
  - The moved SCI tests keep every assertion.
- [ ] **Step 3:** `make test`: the new tests fail to build or fail; nothing else fails.
- [ ] **Step 4: Implement.** `git mv` first and commit the pure move (`GRAPHICS: Move SCI's Unicode glyph sources to graphics/hires_text`), then the namespace/include edits in a second commit so `git diff -M` reviews cleanly, then SVFN and code-page helpers in a third.
- [ ] **Step 5: Verify.**
  - `make test`: N0 + new tests, all pass. `--disable-freetype2` build clean.
  - SCI: KQ1-ko intro 0 px on all 4 frames vs `runs/baseline-4a0f7f0e1c/intro-ko`; English intro all 16 `.bin` byte-identical, no `_layer.bin`.
  - SCUMM: C6 MI1 UTE `--boot-param=117` capture b vs the `c6-test` binary: IDENTICAL-PREFIX (SCUMM code untouched; this checks the link).
- [ ] **Step 6: Commit** (three commits as in Step 4), report `runs/c8/T1-report.md`.

### Task 2: An engine-neutral debug socket and text probes

**Worktree:** `.worktrees/c8-socket`, branch `wt/c8-debugsocket` off `i18n`. Independent of Task 1; may run in parallel.

**Files:** new `gui/debugsocket.{h,cpp}` (transport, recorder, the engine-neutral commands), `gui/module.mk`; modify `gui/debugger.{h,cpp}` (open the socket from `onFrame()` when the game domain has `debug_socket=`), `engines/sci/debugsocket.{h,cpp}` (keeps only SCI's `state`/`wait <cond>`/`buttons`/layer `dump` as a registered extension), `engines/ags/console.{h,cpp}` (`ags_say`), `harness`-side: a copy of `scigame.py`'s client as `runs/c6-tools/sock.py` (harness repo, not the engine).

**Interfaces:**
```cpp
namespace GUI {
class DebugSocketExtension {                 // an engine adds commands the generic socket does not know
public:
	virtual ~DebugSocketExtension() {}
	virtual bool handle(const Common::String &cmd, const Common::StringArray &args, Common::String &reply) = 0;
};
class DebugSocket {                          // one per Debugger; opened by Debugger::onFrame()
public:
	static DebugSocket *open(Debugger *console, const Common::String &path);  // null + one warning on failure
	void setExtension(DebugSocketExtension *ext);
	void poll();                              // every 256th onFrame(), as today
};
}
```
Generic commands (exact spelling, one line in, reply then a line `.`): `key <keycode> [ascii] [flags]`, `click <x> <y> [r]`, `move <x> <y>` (game coordinates, pushed through `g_system->getEventManager()->pushEvent`), `wait frames <n>`, `dump <path>` (the screen as `g_system->lockScreen()` gives it: raw bytes + a `<path>.txt` with `w h bpp format`), `save <slot>` / `load <slot>` (`Engine::saveGameState`/`loadGameState`), and every console command as before. AGS: `ags_say <font> <key-substring|#n>` finds the first `.tra` entry whose key contains the substring (or entry n in load order) and calls `DisplayAtY(-1, text)` with that font as the speech font for the call.

- [ ] **Step 1: Tests first.** `test/gui/debugsocket.h` (new; add `test/gui/*.h` to `test/module.mk` if absent): the command tokenizer (`click 10 20 r` → 3 args), the reply framing (`.` line, a reply line that is itself `.` is escaped as `..`), `wait frames 3` counting three `onFrame()` calls. No sockets in unit tests.
- [ ] **Step 2: Implement** the split; SCI's file loses everything the generic one has.
- [ ] **Step 3: Verify.**
  - SCI: `kq1_tour.py` five captures byte-identical to the pre-change run (`DEBUG_SOCKET.md`: 5 of 5 byte-identical across runs) and `kq1_intro.py` 0 px.
  - AGS 5 Days (`gamedata/kortrs/5days`, `--language=ko`): through the socket, `wait frames 120`, `ags_say 0 #10`, `wait frames 5`, `dump`. The dump shows a text box (mojibake before Task 6/7 — that is the point: the probe reaches the renderer).
  - Without `debug_socket=` in the ini: MI1 UTE boot 117 and 5 Days (no `--language`) captures IDENTICAL-PREFIX vs the `c6-test` binary.
- [ ] **Step 4: Commit** (`GUI: Make the debug socket engine-neutral`, `SCI: Keep only SCI state commands in the debug socket`, `AGS: Add ags_say console command`), report.

### Task 3: SCUMM draws from the shared glyph sources (TTF lazy, SVFN adapted)

**Worktree:** `.worktrees/c8-scumm-src`, branch `wt/c8-scumm-glyphs` off `i18n` with Task 1 and C7 merged (before that: off `wt/c8-glyphsrc` with `git merge --no-ff wt/c7-erase`).

**Files:** `engines/scumm/hires_text.{h,cpp}`, `engines/scumm/charset.cpp` (only if `drawChar`/`advanceFor` signatures move), `test/engines/scumm/hires_glyph_source.h` (new).

**Design:**
- `ScummHiResText` holds `Common::HashMap<Common::String, Graphics::UnicodeGlyphSource *>` keyed `"<path>@<px>"`; `fontFor(charsetId)` becomes `sourceFor(charsetId, bool latin)` returning a source. `[bitmap]` SVFN files load into `SvfnGlyphSource`; a TTF (ini `hires_text_font` > map `[fonts] default`) opens once per pixel size through `TtfGlyphSource::create(..., requireHangul = (encoding == kWindows949 || kJohab))`.
- Pixel size per charset: `game cell height × scale` (today's bake cell), unchanged in this task; `drawChar()` reads rows through `TextCompose::expandGlyphRow()` into the existing coverage plane.
- `bakeCharset()`/`bakeTtfFonts()` are deleted from the start-up path; `HiResFontBaker` stays (offline tool + tests).
- Warnings: `hires_text.cpp:1354` fires only when the map names neither `[bitmap]` fonts nor a TTF face; when a CJK code page is active and `Common::U32String("\xb0\xa1", kWindows949)` does not decode to U+AC00, one warning: `SCUMM: encoding.dat not found (pass --extrapath to dists/engine-data); CJK glyphs disabled`.

- [ ] **Step 1: Tests first.**
  - `test_svfn_path_equals_old_path`: for a 2-glyph SVFN (U+AC00, U+0041, 8bpp, cell 16×16), the coverage `drawChar()` writes through the new source equals, byte for byte, the coverage the old `HiResBitmapFont` path wrote (keep a copy of the old blit as a test helper).
  - `test_ttf_source_shared_per_size`: two charsets with the same cell open one `TtfGlyphSource`; `rasterCount()` after drawing "가가" is probes + 1.
  - `test_map_without_bitmap_but_ttf_does_not_warn` (check via a warning counter hook or by asserting the predicate function `mapNamesNoFonts(config, ttfPath)`).
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.**
  - `make test` pass; `--disable-freetype2` clean.
  - Hi-res off: C6 group A, all seven games (`mi1ute` boot 117, `mi2ute` boot 8999, `indy3vga`, `indy4cd`, `loomcd`, `loomtowns` boot 1, `samnmax` with `subtitles=true`), b vs the C7 build (`wt/c7-erase`): IDENTICAL-PREFIX, u vs u2 clean.
  - SVFN map: the C6-B `runs/c6/B` fonts/maps for `ft`, `mm2`, `zakt` (`runs/c6/B/run*.sh`), b vs C7 build: IDENTICAL-PREFIX.
  - TTF map (`ft.ttf`, `zak2.ttf` configs of `runs/c6/B`): frames may change; report glyphs rasterised and the start-up time before/after (`hires_text_log`, `getMillis()` around `loadFonts()`), and a crop.
  - hpz2 regress (user-run, optional): list the command in the report.
- [ ] **Step 4: Commit** (`SCUMM: Draw hi-res text from shared glyph sources`, `SCUMM: Warn clearly when encoding.dat is missing`), report.

### Task 4: SCUMM per-font faces and proportional advance

**Worktree:** `.worktrees/c8-scumm-prop`, branch `wt/c8-scumm-latin` off `wt/c8-scumm-glyphs`.

**Files:** `engines/scumm/hires_text.{h,cpp}`, `engines/scumm/charset.cpp` (advance call sites at `:490, :497, :770, :1012, :1081, :1301, :2249`), `test/engines/scumm/hires_latin_advance.h` (new), `engines/scumm/HIRES_TEXT.md` (the SCUMM guide), `docs/i18n/HIRES_TEXT_MAP.md` table (docs repo, same task, separate commit there).

**Design:** SCUMM now applies `[hires] font`/`size`, `[fonts]` as a name table, `[font.N] face`/`size`/`bitmap` with **N = charset id 0..19**, and `[latin] mode`/`font`/`metrics`/`space` with SCI's meanings (`HIRES_TEXT_MAP.md`). `metrics=font` advances each glyph by SCI's rule, `latinAdvanceGamePx()` (the face's advance divided by scale, rounded up; the game width when the face gives none), and centres a glyph narrower than its game cell under `metrics=game` instead of left-aligning it. MI2: `engines/scumm/HIRES_TEXT.md` gains an MI2 example map that keeps `0x5c=keep`, `0x60=keep` (C6 finding).

- [ ] **Step 1: Tests first.** `test_font_n_is_charset_id` (`[font.2] size=24` changes charset 2 only); `test_metrics_font_advance` (SCUMM gives the same game advances as SCI's `latinAdvanceGamePx(kHiResMetricsFont, game, face, scale)`, pinned in `test/engines/sci/latinadvance.h:44-54`, moved to `test/graphics/` in Task 1: face 13 at scale 2 → 7, face 9 → 5, face 0 or negative → the game width; SCUMM's own sub-pixel carry in `advanceFor(..., int *carry)` stays for `metrics=game`); `test_metrics_game_centres_narrow_glyph` (a 10-px glyph in a 16-px cell is placed at x+3); `test_mi2_keeps_5c_60` (that example map, verbatim: `glyphOverride(0x5c)` is keep, `0x60` keep).
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.** Hi-res off: group A IDENTICAL-PREFIX vs C7 build. Existing SVFN maps with none of the new keys: IDENTICAL-PREFIX vs Task 3's build. `metrics=font` on MI1 UTE boot 117 with AppleSDGothicNeo (face 0, local only) at `[hires] size=24`: crop of a verb line before/after; the letter-spaced look is gone (report the mean gap between syllables in hi-res px, before vs after).
- [ ] **Step 4: Commit** (`SCUMM: Apply per-charset faces and proportional advance from hires_text.map`), docs commit in the docs repo, report.

### Task 5: SCUMM UTF-8 text

**Worktree:** `.worktrees/c8-scumm-utf8`, branch `wt/c8-scumm-utf8` off `wt/c8-scumm-latin`.

**Files:** `engines/scumm/string.cpp` (`:1265, :1542, :1698, :1916, :1981`), `engines/scumm/string_v7.cpp` (`:79, :136, :168`), `engines/scumm/charset.cpp` (`:708, :714` and the scanners of `getStringWidth`/`addLinebreaks`), `engines/scumm/scumm.h` (the helper), the `korean.trs` reader (`grep -n 'getTrsBundleName' engines/scumm/*.cpp`), `test/engines/scumm/text_char_length.h` (new).

**Design:**
- `int ScummEngine::textCharLength(const byte *p, const byte *end) const`: UTF-8 → 1..4 by lead byte (a stray continuation byte → 1); otherwise exactly today's `is2ByteCharacter(_language, *p) ? 2 : 1` (and the KS check where the site used `checkKSCode`). The page is UTF-8 when `ini text_encoding=utf8`, or the map's `[encoding] codepage=utf8`, or `korean.trs` begins with `EF BB BF` (BOM stripped on load).
- Every listed site calls it. No site changes when the page is not UTF-8 (the helper is the old expression).
- **Buffer audit first:** a table in the report of every fixed-size text buffer reachable from translated text (`_charsetBuffer`, the actor talk buffer, verb name slots, `_msgPtrToAdd` targets, save descriptions), its size, and the worst case at 3 bytes/syllable. Any that can overflow gets a bound check that truncates at a character boundary (`textCharLength`), never mid-character.
- Hi-res **off** with a UTF-8 trs: the bundle is transcoded to CP949 at load (`U32String(utf8).encode(kWindows949)`); a character with no CP949 form becomes `?` and is logged once by code point.

- [ ] **Step 1: Tests first.** `test_utf8_lengths` (`"A"`→1, `"가"` = `EA B0 80`→3, `"😀"`→4, `0x80`→1); `test_escape_bytes_never_inside_utf8` (for every code point U+0080..U+FFFF encoded as UTF-8, no byte is `0xFE`, `0xFF`, `@`, `^`, `\`, `` ` ``); `test_non_utf8_page_is_old_expression` (for every lead byte 0x00..0xFF under KO/JA/ZH languages, the helper equals the old `is2ByteCharacter` result); `test_trs_utf8_to_cp949` (a two-entry UTF-8 bundle with BOM transcodes to the CP949 bytes of the same text).
- [ ] **Step 2: Implement** (audit table first, in the report).
- [ ] **Step 3: Verify.** Group A (CP949 trs) IDENTICAL-PREFIX vs Task 4's build, hi-res on and off. A UTF-8 copy of MI1 UTE's `korean.trs` (converted by a script in `runs/c8/T5/`), hi-res on, boot 117: frames IDENTICAL-PREFIX to the CP949 run with the same map (same glyphs, same layout); hi-res off: IDENTICAL-PREFIX to the CP949 hi-res-off run.
- [ ] **Step 4: Commit** (`SCUMM: Accept UTF-8 translation text`), report.

### Task 6: AGS EUC-KR text format

**Worktree:** `.worktrees/c8-ags-euckr`, branch `wt/c8-ags-euckr` off `i18n` with Task 1 merged (before that: off `wt/c8-glyphsrc`). Needs Task 2 for Step 3's probe (merge `wt/c8-debugsocket` into the verification build only if not yet in `i18n`).

**Files:** `engines/ags/lib/allegro/unicode.{h,cpp}` (`U_EUCKR`, a new `utypes[]` entry), `engines/ags/engine/ac/translation.cpp` (`init_translation()`, `close_translation()`), `engines/ags/engine/main/config.cpp` (read `text_encoding`), `engines/ags/shared/font/wfn_font_renderer.cpp` (`GetTextWidth/Height/RenderText` already use `ugetxc`: code points ≥ 256 return the empty glyph, as today under UTF-8), `test/module.mk` (an `ENABLE_AGS` block: `TESTS += $(srcdir)/test/engines/ags/*.h`, `TEST_LIBS += engines/ags/libags.a`), `test/engines/ags/euckr.h` (new).

**Design:** `#define U_EUCKR AL_ID('E','U','K','R')`. `euckr_getx`: if `isEucKrPair(p[0], p[1])` and `decodeEucKrPair()` is non-zero, consume 2 and return the code point; else consume 1 and return the byte. `euckr_setc(s, c)`: `c < 256` → 1 byte; else `U32String(c).encode(kWindows949)` if it gives an EUC-KR pair, else `?`. `width`/`cwidth`/`isok` accordingly. Selection in `init_translation()` after the `.tra` loads: `StrOptions["encoding"]` set → today's rule. Else `text_encoding` (`auto` default): `euc-kr`/`cp949` → `U_EUCKR`; `utf8` → `U_UTF8`; `ascii` → `U_ASCII`; `auto` → `U_EUCKR` iff the translation name equals `korean` case-insensitively, else `U_ASCII`. Log: `Translation initialized: korean (format: euc-kr)`.

- [ ] **Step 1: Tests first** (`test/engines/ags/euckr.h`; if linking `libags.a` into the test runner is impractical (MAD and the AGS globals), put the four `euckr_*` functions in a globals-free `engines/ags/lib/allegro/unicode_euckr.{h,cpp}` and link only that object, and say so in the report): `getx` over `"\xb0\xa1" "A" "\xe9" "b"` yields U+AC00, 0x41, 0xE9, 0x62; `setc(0xAC00)` writes `B0 A1`; `setc(0xD7A3)` writes `?` (not EUC-KR); `ustrlen("\xb0\xa1\xb0\xa2")==2`; a lone `0xB0` at the end yields 0xB0 and terminates.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.**
  - Invariant: 5 Days, Primordia, Shardlight, Winter's Night without `--language=ko`: IDENTICAL-PREFIX vs upstream (u, u2).
  - Blackwell Deception and Epiphany (`agsfntN.ttf` patches) with `--language=ko`: socket `ags_say` on a known entry (the first entry with a high byte in `Korean.tra`, found by `runs/c8/T6/trakeys.py` = the design's decoder), `dump`, crop shows Korean. Report the log line `format: euc-kr`.
  - 5 Days with `--language=ko`: the mojibake of `shots/c6/5days.png` becomes blank glyph slots (base WFN has no Hangul; Task 7 fills them) — report both crops.
  - A full scan of all 14 `.tra` files for runs of more than 40 bytes without a space (the line-break check the design defers here); list any.
- [ ] **Step 4: Commit** (`AGS: Add an EUC-KR text format for legacy Korean translations`), report.

### Task 7: AGS reads the patches' `extfntN.wfn`

**Worktree:** `.worktrees/c8-ags-extfnt`, branch `wt/c8-ags-extfnt` off `wt/c8-ags-euckr`.

**Files:** `engines/ags/shared/font/wfn_font.{h,cpp}` (`ReadExtFromFile()`, `GetChar(uint32 cp)`), `engines/ags/shared/font/wfn_font_renderer.{h,cpp}` (open `extfnt<N>.wfn`, `GetFontHeight()`, metrics), `test/engines/ags/wfn_ext.h` (new).

**Design:** format `[measured]` (design §2.2): 15-byte signature `WGT Font File  `, `uint32` LE table address, glyph records as in WFN (`uint16` width, `uint16` height, 1bpp rows padded to a byte), then `uint32` LE offsets, one per glyph; accepted only when the table holds exactly 2350 entries (anything else: one warning, extension ignored). Every offset checked (`off + 4 <= tableAddr`, pixel data inside the file) as `ReadFromFile()` does. `GetChar(cp)`: `cp < 256` → base table; else `idx = ksx1001HangulIndexOf(cp)`, `idx >= 0 && ext loaded` → ext glyph; else empty. Height for metrics: `max(base max height, ext glyph 0 height)`. No change to `split_lines()`.

- [ ] **Step 1: Tests first.** A generated 2350-glyph ext file (8×8 glyph 0 = all ink, rest 1-px) in memory: `GetChar(0xAC00)` has width 8, height 8; `GetChar(0x41)` is the base glyph; a file with 2349 entries is refused; a file truncated inside the offset table is refused; an offset pointing past the data yields the empty glyph for that entry only. Plus the real file: `kortrs/5 Days a Stranger (Windows)/extfnt0.wfn` loads 2350 glyphs (skip the test when the file is absent).
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.**
  - Invariant runs of Task 6 still IDENTICAL-PREFIX (no extfnt in an unpatched dir).
  - 5 Days `--language=ko`: the C6 intro capture shows Korean where it showed mojibake; plus `ags_say` crops at font 0/1/2.
  - Unbound, Convergence, Winter's Night, Primordia, KQ1 VGA, SQ2 VGA: `ags_say` on one entry each, crop; list the fonts each ships vs the fonts `ags_say` used.
  - Shardlight: both `agsfnt0.wfn` and a 1-byte `agsfnt0.ttf` ship; report which renderer AGS picks and whether Korean shows.
- [ ] **Step 4: Commit** (`AGS: Read extfntN.wfn Korean glyph extensions`), report.

### Task 8: AGS fonts from `hires_text.map` (TTF override, SVFN with alpha)

**Worktree:** `.worktrees/c8-ags-map`, branch `wt/c8-ags-map` off `wt/c8-ags-extfnt`.

**Files:** `graphics/hires_text/font_map.{h,cpp}` + `test/graphics/hires_text_font_map.h` (`[font.N] bitmap=`), new `engines/ags/shared/font/hires_font_config.{h,cpp}` (reads the map with qualifier = game id), new `engines/ags/shared/font/svfn_font_renderer.{h,cpp}`, `engines/ags/shared/font/fonts.cpp` (`load_font_size()`: choose the renderer per font from the config), `engines/ags/shared/font/ttf_font_renderer.cpp` (load from an explicit path), `test/engines/ags/svfn_renderer.h`.

**Design:**
- Parser: `HiResFontIdSettings` gains `Common::Path bitmap; bool bitmapSet;` read from `[font.N] bitmap=` (relative to the map). SCUMM and SCI tests pass unedited.
- Font N with `[font.N] bitmap=` → `SvfnFontRenderer`; with `face=` (or ini `hires_text_font`) → `TTFFontRenderer` on that path at `size` (default: the game's size for font N); else today's `agsfnt`/`extfnt`.
- `SvfnFontRenderer::RenderText()`: per pixel, `c = coverage`; 16/32-bit destination and `[hires] alpha` (default true) → `dst = TextCompose::blend(dst, colour, c)` per channel; else `c >= 128` → `putpixel(colour)`. Width = sum of SVFN advances.
- Scope: the map is read only when the game dir has `hires_text.map` or ini `hires_text_map`; otherwise `fonts.cpp` is on today's path without a HashMap lookup per glyph.

- [ ] **Step 1: Tests first.** Parser `test_font_n_bitmap_key`; `SvfnFontRenderer` into a 4×1 32-bit bitmap: coverage 0/64/128/255 of white over black gives 0x00/0x40/0x80/0xFF per channel (`blend()` rounding); the same into an 8-bit bitmap gives 0/0/colour/colour; `GetTextWidth("가A")` = the two SVFN advances.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.**
  - Invariant runs IDENTICAL-PREFIX; SCUMM and SCI map tests unchanged.
  - 5 Days with a map `[font.0] face=<AppleSDGothicNeo.ttc face 0, local only> size=12` and `[font.1] bitmap=` an SVFN baked from the same face at 12 px with `m7mkfont.py`/`HiResFontBaker` (script in `runs/c8/T8/`): `ags_say` crops; distinct colours inside the text box for extfnt (1bpp) vs SVFN 8bpp vs TTF (the SCI §5.1 measure; expect 2 vs many).
  - Blackwell 1 (32-bit) vs 5 Days (16-bit): both blend (report the output format from `dump`'s `.txt`).
- [ ] **Step 4: Commit** (`GRAPHICS: hires_text.map [font.N] bitmap=`, `AGS: Fonts from hires_text.map: TTF override and SVFN coverage fonts`), report.

### Task 9: Grim Korean TTF text with alpha on TinyGL and shaders

**Worktree:** `.worktrees/c8-grim`, branch `wt/c8-grim-alpha` off `i18n` with Task 1 merged (before that: off `wt/c8-glyphsrc`).

**Files:** `engines/grim/grim.cpp` (`:277` restriction), `engines/grim/font.{h,cpp}` (`FontTTF::render()`, `.svfn` via `.laf.txt`, UTF-8 BOM in `localize.cpp`), `engines/grim/gfx_tinygl.cpp` (`createTextObject`/`drawTextObject` for TTF fonts), `engines/grim/gfx_opengl_shaders.cpp` (same), `engines/grim/localize.cpp`.

**Design:** for a `FontTTF` (and an SVFN-backed font) `render()` fills an ARGB8888 surface: RGB = the requested `color`, alpha = coverage (draw the string in white onto a transparent surface, then move the red channel into alpha); TinyGL uploads it without a colour key and blits with `TGL_SRC_ALPHA, TGL_ONE_MINUS_SRC_ALPHA` (already enabled in `drawTextObject`); shaders use the texture's alpha. Bitmap `.laf` fonts and the legacy OpenGL path are unchanged. `.laf.txt` naming `x.svfn <px>` → `SvfnGlyphSource`; with no FreeType and a TTF named, one warning and the bitmap `.laf` (today: null font).

- [ ] **Step 1: Tests first** — `test/engines/grim/` does not exist; put the pure part in `graphics/hires_text/text_compose` (`coverageToArgb(src, dst, color)`) with a test in `test/graphics/hires_text_text_compose.h`: coverage 0/128/255 with colour (10,20,30) → ARGB (0,10,20,30)/(128,…)/(255,…).
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.**
  - English Grim is not on this Mac; the invariant is Korean Grim on **TinyGL** b vs itself before the change is impossible (upstream refuses TinyGL for Korean). So: (a) unit test; (b) `gamedata/kortrs/grim` Korean, `--renderer=software` (TinyGL), 120 s capture: the intro plays and Korean subtitles appear — `sheet.py` + crop; (c) the same data with `language=en` forced and `grim.tab`: b vs upstream TinyGL, IDENTICAL-PREFIX (only TTF fonts changed; English uses bitmap `.laf`).
  - If the intro shows no subtitle in 120 s: socket `lua_do` to call the game's subtitle test or `jump` to a set with dialogue; record the commands.
- [ ] **Step 4: Commit** (`GRIM: Draw TTF text with alpha on TinyGL and shaders, allow them for Korean`), report.

### Task 10 (optional): Sword1/2 Korean glyphs through a shared source

**Worktree:** `.worktrees/c8-sword`, branch `wt/c8-sword-glyphs` off `i18n` with Task 1 merged.

**Files:** `engines/sword1/text.{h,cpp}` (`copyWChar`, `wCharWidth`, `isKoreanChar`), `engines/sword2/maketext.{h,cpp}` (the Korean branch of `copyChar`/`wcharWidth`/`isKoreanChar`), new `engines/sword1/korean_glyphs.{h,cpp}` shared by both engines through `graphics/hires_text/glyph_source_*` (no new format), `test/graphics/hires_text_sword_stamp.h` for the pure stamp function.

**Design:** default source = an adapter over the appended `bsNk.fnt` block (index = `ksx1001HangulIndex`, pixels copied as they are: LETTER/BORDER bytes preserved). With `hires_text.map` `[hires] font=` (a `[fonts]` name or a path; a path ending `.svfn` loads through `SvfnGlyphSource`) and `[hires] size=`: glyphs stamped by `stampHardEdged(coverage, w, h, dst, pitch, letterCol, borderCol)`: coverage ≥ 128 → `LETTER_COL`, the 8-neighbour ring of those pixels that is < 128 and `dst == 0` → `BORDER_COL`. Width = 20 unless `size` given (then the face's advance, capped at 26 px height).

- [ ] **Step 1: Tests first.** The stamp on a 3×3 single-ink-pixel glyph gives 1 LETTER and 8 BORDER; the adapter returns the exact 20×26 bytes of glyph 0 of a synthetic `bsNk.fnt`.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.** BS2 (`gamedata/kortrs/bs2`, detected `sword2-win-ko`): no map, 90 s capture, b vs upstream IDENTICAL-PREFIX; then `texttest` through the socket shows Korean identical to upstream's `texttest` dump; with a map naming AppleSDGothicNeo at 24 px: a `texttest` crop. BS1: blocked (data), unit tests only.
- [ ] **Step 4: Commit** (`SWORD1: SWORD2: Draw Korean glyphs through a shared glyph source`), report.

### Task 11: Regression matrix and docs

**Worktree:** docs repo (`~/work/scummvm/docs`) for the docs; no engine worktree (captures use the merged build, `i18n` after the user merged Tasks 1-10).

**Files (docs repo):** `docs/i18n/MULTI_ENGINE_TEXT_DESIGN.md` (a `[measured]` section per engine, like `HIRES_COMPOSITOR_DESIGN.md` §5.1), `docs/i18n/HIRES_TEXT_MAP.md` (the applies table of design §6 and a worked AGS example on 5 Days), `docs/i18n/TREES.md` (the `wt/c8-*` branches' fate).

- [ ] **Step 1:** Full C6 matrix on the merged build vs upstream `503d074778`: every C6 group A, C, D game without the Korean trigger (IDENTICAL-PREFIX expected), then with it (expected changes listed per game with a crop). Table in the design doc.
- [ ] **Step 2:** Update the docs; one commit per file group, with the trailer.
- [ ] **Step 3:** Post the matrix path on the card.

## Out of scope

- Hi-res (supersampled) text for AGS; AGS text stays at native resolution.
- Sword1/2 anti-aliasing (needs a compositor over the 8bpp screen).
- Replacing SCUMM's `HiResOverlay` with SCI's `TextLayer`.
- The fork's AGS "break Korean anywhere" line rule and its KQ1-3 GUID list (design §7.2).
- Grim remaster, EMI (`monkey4`, not built), SCUMM HE.
- Games with no data here: 30minutes, Lamplight City, Zak2 fan game (unit tests only), BS1 Korean at run time.

## Order and dependencies

```
T1 glyphsrc ──┬─ T3 scumm-glyphs ── T4 scumm-latin ── T5 scumm-utf8
(C7 ──────────┘)
T2 debugsocket (parallel with T1) ──┐
T1 ── T6 ags-euckr ── T7 ags-extfnt ── T8 ags-map      (T6-T8 verification needs T2)
T1 ── T9 grim-alpha                                     (needs T2 only for the lua_do fallback)
T1 ── T10 sword-glyphs (optional)
all ── T11 matrix + docs
```
