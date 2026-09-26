# Hi-res compositor, step 5 early: a TTF face through FreeType — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A translator or player points `hires_text_font=` at a `.ttf`/`.ttc`. On a FreeType build the engine bakes it at load time into the in-memory 8-bit coverage font the compositor already draws, so nobody runs a bake tool.

**Architecture:** At game start, `GfxCache::loadUnicodeFont()` checks the ini key first. It rasterises a fixed repertoire with `Graphics::loadTTFFont()` into a byte buffer laid out exactly like an 8 bpp SCVMUNI file. It hands that buffer to `GfxFontUnicode`, whose parser is split out of `load()` so it accepts a buffer. From there the face set, text layer and compositor from step 1 run unchanged. Without the key, or without FreeType, the `.uni` search runs as today.

**Tech Stack:** C++ (ScummVM SCI, `graphics/fonts/ttf.h`, `USE_FREETYPE2`), CxxTest, Python harness (`harness/i18n`).

**Spec:** `docs/i18n/HIRES_COMPOSITOR_DESIGN.md`: D5 (TTF baked at load time via FreeType, pre-baked coverage as fallback), §1 GlyphSource, §2.1 `hires_text_font`, §4 fallback table. This plan brings forward the TTF half of build-order step 5. Scale stays 2 (step 2), and the option/driver predicate (step 3) and `hires_text.map` (step 4) are not needed here.

## Global Constraints

- Engine work happens in a card worktree `~/work/scummvm/i18n/.worktrees/c2-freetype` on branch `wt/c2-freetype`, cut from `i18n`. The merge happens with the user at the end (`TREES.md`).
- **With no `hires_text_font` key, behaviour is byte-identical to today**, for every game including the Korean ones.
- **Builds without FreeType** (`--disable-freetype2`): the key is ignored with one warning and the `.uni` search runs. All new FreeType code sits behind `#ifdef USE_FREETYPE2`.
- **The baked buffer is a valid SCVMUNI v1 8 bpp image** that `GfxFontUnicode`'s parser accepts unchanged:
  - magic `SCVMUNI\0`, version 1, flags `2` (8 bpp);
  - cellW = cellH = pixel size, advNarrow = cellW/2, advWide = cellW;
  - sorted code points, width flags 1/2, stride `cellW*2` bytes per row.
- **The same repertoire, width rule and vertical fit as `harness/i18n/m7mkfont.py`**:
  - default ranges `latin,latin1,hangul,jamo,punct,fullwidth,symbols`;
  - wide = East Asian Width W/F (table in Task 2);
  - a glyph the face lacks is skipped;
  - if the ink box of a probe sample is taller than the cell, reduce the size until it fits;
  - yOffset = `-top + max(0, (cellH - (bottom - top)) / 2)`;
  - ink threshold 40.
- Pixel size comes from `hires_text_font_size`, default 16.
- `make test` passes. Every new file starts with the ScummVM GPL header. Commit messages end with the session's attribution lines.
- Font files are the player's. The engine reads the path given and never ships a font. The user's test font is Apple SD Gothic Neo (`/System/Library/Fonts/AppleSDGothicNeo.ttc`, face 0, macOS system font, local testing only).

## Review Focus

1. **A `.ttc` collection**: FreeType opens face 0. `test_bake_ttc_face0` pins it on macOS, and the test skips where the file does not exist.
2. **A code point the face lacks** is absent from the table, not a blank box. `test_bake_skips_missing_glyphs` (U+AC00 present, a Private Use code point absent).
3. **Startup cost**: roughly 12k glyphs are rasterised once. Log the bake time. The Task 3 check records it and flags anything over 2 s.
4. **Bad path or unreadable file**: one warning, then the `.uni` fallback, and the game still starts. Pinned by the Task 3 harness check with a missing path.
5. **The ini key on a non-CJK game**: the bundle still loads for any game (existing behaviour of `loadUnicodeFont`). Nothing new; the Task 3 English check confirms byte-identical output when the key is absent.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `engines/sci/graphics/fontttfbake.h/.cpp` | new | `bakeScvmuniFromTtf(stream, pixelSize, out, log)`: FreeType raster → SCVMUNI 8 bpp buffer. Engine-free (no `g_sci`); whole body behind `USE_FREETYPE2`. |
| `engines/sci/graphics/fontunicode.h/.cpp` | modify | split `load(filename)` into file read + `loadFromBuffer(Common::Array<byte> &&, const Common::String &name)` |
| `engines/sci/graphics/cache.cpp` | modify | `loadUnicodeFont()`: `hires_text_font` first (FreeType), then the `.uni` names |
| `engines/sci/module.mk` | modify | add `graphics/fontttfbake.o` |
| `test/engines/sci/fontttfbake.h` | new | unit tests (skipped without FreeType or without the system font) |

---

### Task 1: `GfxFontUnicode` parses from a buffer

**Files:** Modify `engines/sci/graphics/fontunicode.h/.cpp`.

**Interfaces:**
- Produces: `bool GfxFontUnicode::loadFromBuffer(Common::Array<byte> &&data, const Common::String &name);`. It takes ownership of `data` and runs today's validation and parsing (everything in `load()` after the file read, with `filename` replaced by `name` in messages). `load(filename)` becomes: open, read into an array, `return loadFromBuffer(Common::move(arr), filename);`.

- [ ] **Step 1:** Refactor as described. No behaviour change: same warnings, same debug line.
- [ ] **Step 2:** Run `make -j10` and `make test` (438 pass). Run the KQ1-ko intro capture with the base build rules (`SCIGAME_BINARY=<worktree>/scummvm SCIGAME_EXTRA_INI='disable_dithering=true\nrgb_rendering=true' python3 harness/i18n/kq1_intro.py $PWD/gamedata/dist-ef8dc87f/kq1-ko $PWD/runs/p2t1 ko`). Then `python3 harness/i18n/c1ab.py runs/baseline-4a0f7f0e1c/intro-ko runs/p2t1`. Expected: 0 px on 4 frames.
- [ ] **Step 3:** Commit: `SCI: Let the SCVMUNI face parse a buffer, not only a file`.

### Task 2: Bake a TTF into an SCVMUNI 8 bpp buffer

**Files:** Create `engines/sci/graphics/fontttfbake.h/.cpp` and `test/engines/sci/fontttfbake.h`. Modify `engines/sci/module.mk`.

**Interfaces:**
- Produces:
  ```cpp
  namespace Sci {
  /** Rasterise the m7mkfont default repertoire from a TrueType/OpenType face
   *  (face 0 of a collection) into an SCVMUNI v1 8 bpp image. Returns false
   *  (and says why in @p error) when FreeType is unavailable or the face
   *  cannot be opened. @p stream is read, not kept. */
  bool bakeScvmuniFromTtf(Common::SeekableReadStream &stream, int pixelSize,
                          Common::Array<byte> &out, Common::String &error);
  }
  ```

**Algorithm.** This ports `m7mkfont.build()` at bpp 8. Read `harness/i18n/m7mkfont.py` `build()` alongside.

1. Repertoire: the union of these ranges, sorted and deduplicated:
   ```
   0x0020-0x007E, 0x00A0-0x00FF, 0xAC00-0xD7A3, 0x3131-0x318E,
   0x2010-0x203B, 0x3000-0x303F, 0x2500-0x254B, 0xFF01-0xFF5E,
   0x2100-0x214F, 0x2190-0x21FF, 0x25A0-0x25FF, 0x2600-0x26FF, 0x00B0-0x00B1
   ```
2. Wide (EAW W/F) inside that repertoire is exactly these runs (Unicode 16.0, generated from Python `unicodedata`). Everything else is narrow:
   ```
   {0x25FD,0x25FE},{0x2614,0x2615},{0x2630,0x2637},{0x2648,0x2653},{0x267F,0x267F},
   {0x268A,0x268F},{0x2693,0x2693},{0x26A1,0x26A1},{0x26AA,0x26AB},{0x26BD,0x26BE},
   {0x26C4,0x26C5},{0x26CE,0x26CE},{0x26D4,0x26D4},{0x26EA,0x26EA},{0x26F2,0x26F3},
   {0x26F5,0x26F5},{0x26FA,0x26FA},{0x26FD,0x26FD},{0x3000,0x303E},{0x3131,0x318E},
   {0xAC00,0xD7A3},{0xFF01,0xFF5E}
   ```
3. Open the face with `Graphics::loadTTFFont(stream-copy, DisposeAfterUse::YES, size, Graphics::kTTFSizeModeCharacter, 0, 0, Graphics::kTTFRenderModeLight)`. Copy the stream into a `Common::MemoryReadStream` you own if the API keeps it. Check `graphics/fonts/ttf.h` for ownership.
4. Rendering one glyph: draw into a `Graphics::ManagedSurface` in an 8-bit-alpha-capable format. Use a 32 bpp ARGB surface (`Graphics::PixelFormat::createFormatARGB32()`) cleared to transparent, draw white with `font->drawChar(&surf, cp, x, y, whiteColor)`, and read the alpha channel as coverage.
   - Check how `TTFFont` blends on a 4-byte surface (`renderGlyph<uint32>` in `ttf.cpp`). If it writes colour, not alpha, use a black background and read one colour channel as coverage.
   - Prove the choice in a unit test: a solid glyph pixel reads 255, and background reads 0.
5. Vertical fit, as m7mkfont does:
   - Take a probe sample of every `max(1, n/250)`-th code point, skipping spaces.
   - Measure the ink rows (coverage ≥ 40) of each probe drawn at (0,0) on a 3·cell canvas.
   - If `bottom - top > cellH`, retry at size−1 down to 6 until it fits.
   - Then `yOffset = -top + max(0, (cellH - (bottom-top)) / 2)`.
6. Per code point:
   - Render at (0, yOffset) into a `cellW*2 × cellH` coverage buffer.
   - Skip the code point if the face has no glyph for it. `TTFFont` has no public "has glyph", so a glyph with no ink that is not U+0020/U+3000 counts as missing. Say so in a comment.
   - Store coverage bytes as they are: no threshold at 8 bpp, which matches m7mkfont's `glyph[...] = v`.
7. Header, exactly as m7mkfont writes it:
   - `SCVMUNI\0`, then `<H version=1><H flags=2>`, `<B cellW><B cellH><B cellW/2><B cellW>`, `<I count>`, `<I cpOff=36><I wOff=36+4n><I bmOff=wOff+n>`, `<I 0>`;
   - then the cp table (LE uint32), the width bytes, and the bitmaps.

- [ ] **Step 1: tests first** (`test/engines/sci/fontttfbake.h`, whole suite under `#ifdef USE_FREETYPE2`, otherwise one test that asserts `bake` returns false with a non-empty error):
  - `test_bake_header_is_scvmuni_8bpp`: bake the macOS font (skip if `/System/Library/Fonts/AppleSDGothicNeo.ttc` is missing, e.g. `if (!Common::File::exists(...)) { TS_SKIP(...); }`, or use `Common::FSNode`). Check magic, version 1, flags 2, cell 16/16, adv 8/16, and that offsets are consistent with the count.
  - `test_bake_ttc_face0`: count > 11000 (the Hangul syllables are present).
  - `test_bake_skips_missing_glyphs`: U+AC00 is in the table and U+E000 is not. U+E000 is not in the repertoire anyway, so also assert that every table entry has some ink or is U+0020/U+3000.
  - `test_bake_width_flags`: U+AC00 → 2, U+0041 → 1, U+FF21 → 2, U+2500 → 1.
  - `test_bake_is_parseable`: feed the buffer to the same checks `GfxFontUnicode::loadFromBuffer` does. If that needs a `GfxScreen`, validate the header and tables in the test directly.
  - `test_bake_matches_m7mkfont_tables`: if `/tmp/ko8.uni` from `m7mkfont --bpp 8` of the same font exists, the code-point table and width flags are identical. Skip if absent. Bitmaps may differ, because PIL and ScummVM set up FreeType differently; do not compare them.
- [ ] **Step 2:** Run the tests and confirm they fail (missing header).
- [ ] **Step 3:** Implement. Keep FreeType specifics inside the `.cpp`; the header has no FreeType includes.
- [ ] **Step 4:** Run the tests; all pass. Also build with `--disable-freetype2` in a scratch copy, or confirm by reading `config.mk`, that the file compiles to the stub.
- [ ] **Step 5:** Commit: `SCI: Bake a TrueType face into an 8-bit SCVMUNI image at load time`.

### Task 3: `hires_text_font` wires it in

**Files:** Modify `engines/sci/graphics/cache.cpp` (`loadUnicodeFont`).

- [ ] **Step 1:** Change `loadUnicodeFont()`. Before the `.uni` names:
  - If `ConfMan.hasKey("hires_text_font")`:
    - `#ifdef USE_FREETYPE2`:
      - open the path (`Common::FSNode(Common::Path(ConfMan.get("hires_text_font"), Common::Path::kNativeSeparator)).createReadStream()`);
      - size = `ConfMan.hasKey("hires_text_font_size") ? ConfMan.getInt(...) : 16`;
      - time the call and bake;
      - on success, `f->loadFromBuffer(...)` and `debug(1, "SCI: hires_text_font %s baked: %u glyphs at %dpx in %u ms", ...)`;
      - on any failure, `warning()` once with the reason and fall through to the `.uni` names.
    - `#else`: `warning("hires_text_font needs a build with FreeType; ignored")`.
- [ ] **Step 2:** Build and test.
- [ ] **Step 3: Captures** (run from `~/work/scummvm`, with `SCIGAME_BINARY` pointing at the worktree binary):
  - With the key: `SCIGAME_EXTRA_INI='disable_dithering=true\nrgb_rendering=true\nhires_text_font=/System/Library/Fonts/AppleSDGothicNeo.ttc'` → `kq1_intro.py gamedata/dist-ef8dc87f/kq1-ko runs/p2-ttf ko`. Convert `intro_f45_out` to PNG with `harness/i18n/out2png.py`, count the distinct colours in the text box as Task 7 of plan 1 did (expect ≫ 2), and record the bake time from `run.log`.
  - Without the key: `c1ab.py runs/baseline-4a0f7f0e1c/intro-ko runs/p2-nokey` gives 0 px (the byte-identical invariant).
  - Bad path: `hires_text_font=/nonexistent.ttf`. The game starts, `run.log` has one warning, and the text uses `korean.uni` (compare to baseline: 0 px).
  - English intro: baseline `.bin` files identical, no `_layer.bin`.
- [ ] **Step 4:** Save `shots/c2-ttf/kq1-ko-ttf_intro_f45_full.png` and a 4× crop next to plan 1's `kq1-ko8` crop, for the user.
- [ ] **Step 5:** Commit: `SCI: hires_text_font= bakes a TrueType face at start-up` (with the measured bake time and colour count). Add a short "Measured (step 5 early)" note to `HIRES_COMPOSITOR_DESIGN.md` §5 in the docs repo.

## Out of scope

- `hires_text.map` and `[font.N]` sizes (step 4).
- GUI option (step 3).
- Hanja via the cp949 repertoire (a later range option).
- Proportional advances (D6-b).
- Outline/shadow.
- Scale 3.
