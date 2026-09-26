# Hi-res compositor, step 5 early: a TTF face through FreeType, rasterised on demand — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A player or translator points `hires_text_font=` at a `.ttf`/`.ttc`. On a FreeType build the engine rasterises each glyph the first time it is needed, at 8-bit coverage, and caches it. Load time stays near zero, and nobody runs a bake tool.

**Architecture:**
- `GfxFontUnicode` stops owning the SCVMUNI tables. It reads glyphs through an engine-free `UnicodeGlyphSource` interface with two implementations:
  - `ScvmuniGlyphSource`: today's file parser, moved.
  - `TtfGlyphSource`: FreeType via `Graphics::loadTTFFont`, a per-code-point cache, rasterises lazily.
- `GfxCache::loadUnicodeFont()` builds the TTF source when `hires_text_font` is set. Otherwise it keeps today's `.uni` search.
- The face set, text layer and compositor from step 1 are unchanged.

**Tech Stack:** C++ (ScummVM SCI, `graphics/fonts/ttf.h`, `USE_FREETYPE2`), CxxTest, Python harness.

**Spec:** `docs/i18n/HIRES_COMPOSITOR_DESIGN.md`: D5, §1 GlyphSource, §2.1 `hires_text_font`, §4. User decisions of 2026-09-26:
- Rasterise on demand and cache; rasterising everything at load is too slow.
- Real Korean text lives in the KS X 1001 2,350 syllables. Measured: KQ1-ko uses 868 distinct syllables, all inside the 2,350, and nothing else non-ASCII. So no prewarm and no repertoire list: any code point the face has is drawable.

## Global Constraints

- Engine work happens in the card worktree `~/work/scummvm/i18n/.worktrees/c2-freetype`, branch `wt/c2-freetype`, cut from `i18n`. The merge happens with the user at the end (`TREES.md`).
- **With no `hires_text_font` key, behaviour is byte-identical to today** for every game, including the `.uni` Korean ones. A/B against `runs/baseline-4a0f7f0e1c/intro-ko` must give 0 px.
- **Builds without FreeType** (`--disable-freetype2`): `TtfGlyphSource` compiles to a stub whose `create()` fails with an error string. The key is ignored with one warning.
- **Load-time work is bounded:** open the face, plus at most 32 probe rasterisations for the vertical fit. Nothing else is rasterised until drawn or measured.
- **Glyph geometry matches SCVMUNI:**
  - cell = pixel size (default 16);
  - a glyph is `cells × cellW` wide (cells = 2 if East Asian Width is W/F, else 1);
  - rows are `cellW*2` bytes (8 bpp coverage);
  - advNarrow = cellW/2, advWide = cellW (as `m7mkfont.py` writes).
- **Width comes from East Asian Width, not from the TTF advance.** The table is `/Users/juami/work/scummvm/runs/eaw_wide_runs.txt`: 122 inclusive `{first, last}` runs over U+0000..U+3FFFF, generated from Python `unicodedata` (Unicode 16.0). Copy it verbatim into the source as a sorted static array and binary-search it.
- **Vertical fit, as `m7mkfont.py` does it:**
  - Probe set: the fixed list `가각똠뷁힣ㄱㅎAgjyÅ|[]{}()「」『』…—°` (≤ 32 code points). Draw each at (0,0) on a 3·cell canvas and take the ink rows (coverage ≥ 40).
  - If `bottom - top > cellH`, retry at size−1, down to 6.
  - `yOffset = -top + max(0, (cellH - (bottom-top)) / 2)`.
- `make test` passes. Every new file starts with the ScummVM GPL header. Commit messages end with the session's attribution lines.
- The engine reads a font the player names and never ships one. The user's test font is Apple SD Gothic Neo (`/System/Library/Fonts/AppleSDGothicNeo.ttc`, face 0, macOS system font, local testing only).

## Review Focus

1. **Lazy means lazy.** Creating the source rasterises at most the probe set. `test_create_rasterises_only_probes` and `test_second_request_is_cached` pin it through a `rasterCount()` counter.
2. **A code point the face lacks** is a clean miss (`cells() == 0`). It is cached, so it is never retried (`test_missing_is_cached`), and the face set falls through to the next face.
3. **A `.ttc` collection** opens face 0 (`test_ttc_face0`, skipped where the macOS font is absent).
4. **Bad path or unreadable file:** one warning, then the `.uni` fallback, and the game still starts (Task 3 harness check).
5. **`isDoubleByte`/`getCharWidth` during layout** of a glyph never drawn: width comes from the EAW table, but existence needs one rasterisation (`TTFFont` has no public "has glyph"). That is acceptable and cached. `test_width_without_draw` pins the flag values.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `engines/sci/graphics/glyphsource.h` | new | `UnicodeGlyphSource` interface (engine-free) |
| `engines/sci/graphics/glyphsource_scvmuni.h/.cpp` | new | `ScvmuniGlyphSource`: parse an SCVMUNI buffer (moved out of `GfxFontUnicode::load`) |
| `engines/sci/graphics/glyphsource_ttf.h/.cpp` | new | `TtfGlyphSource`: FreeType, lazy, cached, plus the EAW table |
| `engines/sci/graphics/fontunicode.h/.cpp` | modify | hold a `UnicodeGlyphSource`; `load(filename)` builds a `ScvmuniGlyphSource`; add `setSource()` |
| `engines/sci/graphics/cache.cpp` | modify | `hires_text_font` → `TtfGlyphSource` |
| `engines/sci/module.mk` | modify | three new `.o` |
| `test/engines/sci/glyphsource.h` | new | unit tests for both sources |

## Interface (used by every task)

```cpp
// engines/sci/graphics/glyphsource.h
namespace Sci {
/** Where GfxFontUnicode gets glyphs: a packed file or a live TrueType face.
 *  Rows are stride cellWidth()*2 pixels at bitsPerPixel() (1, 2 or 8), the
 *  layout TextCompose::expandGlyphRow() reads. Non-const lookups because a
 *  source may rasterise and cache on first use. */
class UnicodeGlyphSource {
public:
	virtual ~UnicodeGlyphSource() {}
	virtual byte cellWidth() const = 0;
	virtual byte cellHeight() const = 0;
	virtual byte advanceNarrow() const = 0;
	virtual byte advanceWide() const = 0;
	virtual int bitsPerPixel() const = 0;
	/** 1 or 2 cells, or 0 when the source has no glyph for cp. */
	virtual int cells(uint32 cp) = 0;
	/** Packed row y of cp's glyph; only valid when cells(cp) > 0. */
	virtual const byte *row(uint32 cp, int y) = 0;
	/** For logs: glyphs in the file, or glyphs rasterised so far. */
	virtual uint32 glyphCount() const = 0;
};
}
```

---

### Task 1: The interface, and the SCVMUNI parser moves behind it

**Files:** create `glyphsource.h` and `glyphsource_scvmuni.h/.cpp`; modify `fontunicode.h/.cpp` and `module.mk`; test `test/engines/sci/glyphsource.h`.

**Produces:**
- `class ScvmuniGlyphSource : public UnicodeGlyphSource`
  - `static ScvmuniGlyphSource *create(Common::Array<byte> &&data, const Common::String &name, Common::String &error);`
    - Runs exactly today's validation from `GfxFontUnicode::load`: magic, version, flags (both-bits rejected), empty font, bounds, sorted table. The warning texts become `error` strings.
    - Returns null on failure.
  - `cells(cp)` = binary search, then the width byte; `row(cp,y)` = `_bitmaps + g*_bytesPerGlyph + y*_rowBytes`.
  - Cache the last looked-up cp→index pair so `cells()` then `row()` for the same cp does one search.
- `GfxFontUnicode`
  - Holds `Common::ScopedPtr<UnicodeGlyphSource> _source`.
  - `load(filename)` reads the file and calls `ScvmuniGlyphSource::create`. On failure it warns with the error and returns false; on success it prints the same debug line as today.
  - `void setSource(UnicodeGlyphSource *src, const Common::String &name)` takes ownership and marks the face loaded.
  - `findGlyph`, `hasGlyph`, `getCharWidth`, `isDoubleByte`, `getHeight`, `getCharHeight`, `draw` and `drawToBuffer` go through `_source`.
  - `coverageRow(int glyph, int y)` becomes `coverageRow(uint32 cp, int y)`; update `draw` and `drawToBuffer`.
  - `glyphCount()` and `bitsPerPixel()` forward to the source.

- [ ] **Step 1: tests** in `test/engines/sci/glyphsource.h`. Build tiny SCVMUNI buffers in the test:
  - cell 2×2, 3 glyphs (U+0041 narrow, U+AC00 wide, U+AC01 wide), 1 bpp, rowBytes = (2*2*1+7)/8 = 1;
  - one 8 bpp variant.

  Tests:
  - `test_parse_valid_1bpp` (cells 1/2/0 for A/가/B);
  - `test_row_bytes_1bpp` (a known pixel);
  - `test_parse_8bpp_row_is_coverage`;
  - `test_rejects_bad_magic`, `test_rejects_both_bpp_flags`, `test_rejects_unsorted`, `test_rejects_truncated_table` (each returns null with a non-empty error).
- [ ] **Step 2:** Run and confirm the tests fail. Then implement.
- [ ] **Step 3:** `make -j10`, and `make test` (438 + new, all pass).
- [ ] **Step 4:** A/B with the worktree binary:
  ```
  cd ~/work/scummvm && SCIGAME_BINARY=<worktree>/scummvm SCIGAME_EXTRA_INI='disable_dithering=true\nrgb_rendering=true' python3 harness/i18n/kq1_intro.py $PWD/gamedata/dist-ef8dc87f/kq1-ko $PWD/runs/p2t1 ko
  python3 harness/i18n/c1ab.py runs/baseline-4a0f7f0e1c/intro-ko runs/p2t1
  ```
  Expected: 0 px on all 4 frames. Also check `gamedata/kq1-ko8`, the 8 bpp font: it must load (`GfxFontUnicode: ... 8bpp` in `run.log`).
- [ ] **Step 5:** Commit: `SCI: GfxFontUnicode reads glyphs through a source, and SCVMUNI files are the first one`.

### Task 2: `TtfGlyphSource` — FreeType, lazy, cached

**Files:** create `glyphsource_ttf.h/.cpp`; modify `module.mk` and `test/engines/sci/glyphsource.h`.

**Produces:**
```cpp
class TtfGlyphSource : public UnicodeGlyphSource {
public:
	/** Opens face 0 of @p stream (the source keeps what FreeType needs), fits
	 *  the vertical offset from the probe set, rasterises nothing else.
	 *  Null + @p error when FreeType is unavailable or the face won't open. */
	static TtfGlyphSource *create(Common::SeekableReadStream *stream, DisposeAfterUse::Flag dispose,
	                              int pixelSize, Common::String &error);
	int bitsPerPixel() const override { return 8; }
	int cells(uint32 cp) override;
	const byte *row(uint32 cp, int y) override;
	uint32 glyphCount() const override;       // entries cached with ink
	uint32 rasterCount() const;               // FreeType renders so far (for tests)
	static bool isWide(uint32 cp);            // the EAW table
};
```

Implementation notes:
- `Graphics::loadTTFFont(stream, dispose, size, Graphics::kTTFSizeModeCharacter, 0, 0, Graphics::kTTFRenderModeLight)`. Check in `graphics/fonts/ttf.h`/`.cpp` whether it copies the stream or keeps it, and keep ownership right.
- Coverage from one render:
  - draw white on a zeroed 32 bpp `Graphics::ManagedSurface` (`createFormatARGB32()`) with `font->drawChar(&surf, cp, x, y, white)`;
  - read the channel that receives coverage. Read `renderGlyph<uint32>` in `ttf.cpp` to see whether alpha or colour carries it, and prove it in a test: a full pixel reads 255, background reads 0.
- Missing glyph: `TTFFont` exposes no "has glyph". A render with no ink for any code point other than U+0020, U+00A0, U+3000 counts as missing. Say so in a comment.
- Cache: `Common::HashMap<uint32, Entry>` with `Entry { byte cells; Common::Array<byte> cov; }`. Missing is `cells = 0` with an empty `cov`. `cov` is `cellH × cellW*2` bytes, drawn at `(0, yOffset)`.
- `cells(cp)` = `ensure(cp).cells`; `row()` points into the entry.
- Without FreeType (`#ifndef USE_FREETYPE2`): `create()` sets error = "this build has no FreeType" and returns null; `isWide` still works.

- [ ] **Step 1: tests** (all under `#ifdef USE_FREETYPE2`, except `isWide` and the stub test). Font: `/System/Library/Fonts/AppleSDGothicNeo.ttc`, `TS_SKIP` if absent.
  - `test_is_wide_table`: U+AC00, U+3000, U+FF21 and U+4E00 are wide; U+0041, U+2500 and U+00B0 are narrow; U+1F600 is wide.
  - `test_create_rasterises_only_probes`: after `create`, `rasterCount() <= 32` and `glyphCount() == 0`.
  - `test_second_request_is_cached`: `cells(0xAC00) == 2` raises `rasterCount` by 1; asking again, including `row()`, does not raise it.
  - `test_missing_is_cached`: pick a code point the face lacks (e.g. U+E000 private use, or a Linear B U+10000). `cells` is 0, and a second call does not render again.
  - `test_coverage_is_eight_bit`: for 가, some row byte is 255 and some intermediate value (1..254) exists; the anti-aliasing is real.
  - `test_ttc_face0`: `create` succeeds on the `.ttc`.
  - `test_width_without_draw`: `cells` of U+0041 = 1 and of U+AC01 = 2.
  - `#ifndef USE_FREETYPE2`: `test_no_freetype_stub` returns null with an error.
- [ ] **Step 2:** Run and confirm the tests fail. Implement. Run them again: all pass. `make test` is green.
- [ ] **Step 3:** Commit: `SCI: A TrueType glyph source that rasterises each glyph once, when first needed`.

### Task 3: `hires_text_font` wires it in, and the measurements

**Files:** modify `engines/sci/graphics/cache.cpp` (`loadUnicodeFont`).

- [ ] **Step 1:** In `loadUnicodeFont()`, before the `.uni` names:
  - If `ConfMan.hasKey("hires_text_font")`:
    - open the native path: `Common::FSNode(Common::Path(ConfMan.get("hires_text_font"), Common::Path::kNativeSeparator))`, then `createReadStream()`;
    - size = `hires_text_font_size`, default 16;
    - time `TtfGlyphSource::create` with `g_system->getMillis()`;
    - on success, `f->setSource(src, path)` and `debug(1, "SCI: hires_text_font %s opened at %dpx in %u ms", ...)`;
    - on failure, `warning("hires_text_font %s: %s; using the .uni fonts", ...)` once, and continue with the `.uni` names.
  - Rasterisation cost: have `TtfGlyphSource` accumulate the total time spent rendering, and log `debug(1, ...)` with glyph count and total ms when the source is destroyed (game exit). Capture it from `run.log`.
- [ ] **Step 2:** Build and test.
- [ ] **Step 3: Captures** (worktree binary; append `\nhires_text_font=/System/Library/Fonts/AppleSDGothicNeo.ttc` to `SCIGAME_EXTRA_INI` where the key is wanted):
  - With the key: `kq1_intro.py` on `dist-ef8dc87f/kq1-ko` → `runs/p2-ttf`. Record the open time and the rasterised-glyph count and time from `run.log`. Convert `intro_f45` with `harness/i18n/out2png.py` and count the distinct colours in the text box (expect ≫ 2). Save `shots/c2-ttf/kq1-ko-ttf_intro_f45_full.png` and a 4× crop.
  - Also run `kq1_tour.py` with the key, then record the glyph count after a longer session and the per-glyph mean render time.
  - Without the key: `c1ab.py runs/baseline-4a0f7f0e1c/intro-ko runs/p2-nokey` gives 0 px.
  - Bad path `hires_text_font=/nonexistent.ttc`: the game starts, `run.log` has one warning, and c1ab against the baseline gives 0 px.
  - English intro without the key: baseline `.bin` files identical, no `_layer.bin`.
- [ ] **Step 4:** Commit: `SCI: hires_text_font= opens a TrueType face and rasterises on demand` (with the measurements). Add a "Measured (step 5 early)" note to `HIRES_COMPOSITOR_DESIGN.md` §5 in the docs repo: open time, glyphs rasterised in intro and tour, total and mean render time, the colour count, the invariants. Commit there too.

## Out of scope

- `hires_text.map` / `[font.N]` sizes (step 4).
- GUI option (step 3).
- Disk cache of rasterised glyphs (only if the measurements call for it).
- Prewarming the 2,350.
- Outline/shadow.
- Proportional advance (D6-b).
- Scale 3.
