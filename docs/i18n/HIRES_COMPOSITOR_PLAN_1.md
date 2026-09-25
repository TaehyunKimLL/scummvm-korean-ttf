# Hi-res compositor, step 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hi-res SCI text becomes an 8-bit-coverage text layer that the upscaled driver alpha-blends over the scaled graphics into a 32-bit (or 16-bit) frame. The re-apply plane (`_hiresTextPlane`) goes away.

**Architecture:** `TextLayer` holds per hi-res pixel a foreground and an outline (palette index, 8-bit coverage). It follows the visual plane: pixel writes clear it, and underbits save/restore carry it. `UpscaledGfxDriver::updateScreen()` blends it over the colour-converted scaled bitmap on every update. Glyphs from the SCVMUNI face (now also 8 bpp) and the legacy Korean face are written into the layer, not stamped into the driver bitmap. The legacy SJIS face (`putKanjiChar`) is untouched in this step.

**Tech Stack:** C++ (ScummVM SCI engine, `Graphics::PixelFormat`), CxxTest unit tests (`make test`), Python harness (`harness/i18n`, debug socket dumps), PIL.

**Spec:** `docs/i18n/HIRES_COMPOSITOR_DESIGN.md`, this is build-order step 1. Also read `TEXT_PLANE.md` (what is being replaced), `PC98_TOWNS_TEXT.md` §5 (why SJIS is excluded here), and `TREES.md` (where work happens).

## Global Constraints

- Work only in a card worktree: `~/work/scummvm/i18n/.worktrees/c1-compositor`, branch `wt/c1-compositor`, cut from `i18n`. Never edit `~/work/scummvm/i18n` itself. Close with `git merge --no-ff` into `i18n` (`TREES.md`).
- Harness changes are committed in the harness repo (`~/work/scummvm`); plan and doc changes go in the docs repo (`~/work/scummvm/docs`).
- **An untranslated game, or any game that never draws a hi-res glyph, is byte-identical.** The layer is never allocated and no new code runs (spec §5 invariants).
- **Single-byte text is still drawn by the game's own font.** No change to `GfxFontSet` face order.
- Scale N is 2 in this step. Do not generalise the scaler.
- Output: 32 bpp or 16 bpp gets alpha blending. With CLUT8 output (rgb rendering off), coverage ≥ 128 stamps the index (spec §3.5).
- `make test` passes. The build succeeds with `--disable-freetype2` and with SCI32 both enabled and disabled (`--disable-engine=sci32` variant check once at the end).
- New classes `TextLayer` and `TextCompose` must not use `g_sci`, `GfxScreen` or any engine state, so the unit tests link without the engine (the `ScriptStrings` precedent).
- Commit messages follow the repo style (`SCI: ...`), carry the measurement, and end with the session's attribution lines.

## Review Focus

1. **Window over window.** When a window opens over another window's hi-res text, that text must disappear under it and reappear when the upper window closes, because the underbits restore carries the layer. Pinned by the Task 1 test `test_save_restore_brings_text_back` and the Task 6 harness check.
2. **Greyed (disabled) text** keeps the engine's checkerboard. Pinned by the Task 2 test `test_expand_row_greyed_checkerboard`.
3. **Palette change while text is up** (a fade). The text is re-blended with the new palette and follows it. Pinned by the Task 2 test `test_compose_follows_palette`.
4. **CLUT8 output** (rgb rendering off). Text must still be visible, as stamped indices, not vanish. Pinned by the Task 2 test `test_stamp_span` and the Task 4 check.
5. **A game that never draws hi-res text** allocates nothing and runs no new code. Pinned by the Task 5 English check: no `_layer.bin` in the dump, and the `_low.bin` dumps equal the baseline.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `engines/sci/graphics/textlayer.h/.cpp` | new | `TextPixel`, `TextLayer`: storage, glyph write, clear, save/restore. Engine-free. |
| `engines/sci/graphics/textcompose.h/.cpp` | new | `TextCompose`: coverage expansion from 1/2/8 bpp rows (with greying), blend, compose span into a pixel format, CLUT8 stamp. Engine-free. |
| `engines/sci/module.mk` | modify | add the two `.o` files |
| `test/engines/sci/textlayer.h`, `test/engines/sci/textcompose.h` | new | unit tests (picked up by the `test/engines/sci/*.h` wildcard in `test/module.mk:61`) |
| `engines/sci/graphics/drivers/gfxdriver.h` | modify | `setTextLayer()`, `refreshHiresRect()` defaults |
| `engines/sci/graphics/drivers/gfxdriver_intern.h`, `upscaled.cpp` | modify | hold the layer; compose in `updateScreen()` |
| `engines/sci/graphics/fontunicode.h/.cpp` | modify | 8 bpp SCVMUNI; draw coverage into the layer |
| `engines/sci/graphics/screen.h/.cpp` | modify | own the `TextLayer`; `putHiresCoverageGlyph()`; mirror `putPixel` and bits save/restore; remove `_hiresTextPlane` |
| `engines/sci/graphics/ports.cpp`, `paint16.cpp` | modify | stop clearing on window removal; clear on new picture via the layer |
| `engines/sci/debugsocket.cpp` | modify | dump `_layer.bin` and the backend frame `_out.bin` + `_out.txt` |
| `harness/i18n/scigame.py` | modify (harness repo) | macOS headless, `SCIGAME_EXTRA_INI`, socket-path length check |
| `harness/i18n/m7mkfont.py`, `m7check.py` | modify (harness repo) | `--bpp 8` |
| `harness/i18n/c1ab.py` | new (harness repo) | A/B: old `_scaled`+`_pal` vs new `_out` |

---

### Task 0: Harness runs headless on macOS

The baseline in `runs/baseline-4a0f7f0e1c/` was taken through a scratch wrapper. This task makes the harness itself do what the wrapper did, so every later capture is reproducible from the repo.

**Files:**
- Modify: `harness/i18n/scigame.py` (harness repo), function `SciGame.launch`

**Interfaces:**
- Produces: `SciGame.launch(..., headless=None)`. When `headless is None` and `Xvfb` is not on PATH, it behaves as `headless=True`. The environment variable `SCIGAME_EXTRA_INI` (literal `\n` separators) is appended to the game section. On `sys.platform == "darwin"` headless runs set `SDL_RENDER_DRIVER=software`. `launch` raises `ValueError` if the UNIX socket path is 104 bytes or longer.

- [ ] **Step 1: Add the behaviour**

In `launch`, before `os.makedirs(...)`:

```python
        if headless is None and os.name != "nt" and not shutil.which("Xvfb"):
            # No X server on this machine (macOS): the capture comes from the
            # engine's own `dump`, so nothing needs a display.
            headless = True
        env_extra = os.environ.get("SCIGAME_EXTRA_INI", "")
        if env_extra:
            extra_ini = extra_ini + env_extra.replace("\\n", "\n") + "\n"
```

After `sock_path` is computed:

```python
        if not win and len(sock_path.encode()) >= 104:
            # sun_path is 104 bytes on macOS (108 on Linux); a longer path is
            # silently truncated by bind() and the client never finds it.
            raise ValueError("socket path too long (%d bytes): %s" % (len(sock_path.encode()), sock_path))
```

In the `if headless:` branch of the env setup:

```python
                if sys.platform == "darwin":
                    # sdl2-compat over SDL3: the dummy driver has no accelerated
                    # renderer; the software one works, and with rgb_rendering
                    # the 640x400 upscaled mode switches cleanly.
                    env.setdefault("SDL_RENDER_DRIVER", "software")
```

- [ ] **Step 2: Verify against the baseline**

```bash
cd ~/work/scummvm
SCIGAME_EXTRA_INI='disable_dithering=true\nrgb_rendering=true' \
  python3 harness/i18n/kq1_intro.py $PWD/gamedata/dist-ef8dc87f/kq1-ko $PWD/runs/t0-intro-ko ko
for f in $(cd runs/baseline-4a0f7f0e1c/intro-ko && ls *.bin); do cmp -s runs/baseline-4a0f7f0e1c/intro-ko/$f runs/t0-intro-ko/$f || echo DIFF $f; done
```

Expected: the state line is printed, and there is no `DIFF` line (24/24 identical).

- [ ] **Step 3: Commit (harness repo)**

```bash
git add harness/i18n/scigame.py
git commit -m "scigame: headless when there is no Xvfb, SCIGAME_EXTRA_INI, and a socket-path length check"
```

---

### Task 1: TextLayer

**Files:**
- Create: `engines/sci/graphics/textlayer.h`, `engines/sci/graphics/textlayer.cpp`
- Modify: `engines/sci/module.mk` (add `graphics/textlayer.o` next to `graphics/text16.o`)
- Test: `test/engines/sci/textlayer.h`

**Interfaces:**
- Produces (namespace `Sci`):
  - `struct TextPixel { byte fgIndex; byte fgCoverage; byte outlineIndex; byte outlineCoverage; };` (4 bytes, `static_assert`ed)
  - `class TextLayer`
    - `TextLayer(uint16 width, uint16 height, uint16 scale)`, where width and height are hi-res and scale is hi-res pixels per low-res pixel.
    - `uint16 width() const; uint16 height() const; uint16 scale() const;`
    - `bool isEmpty() const;`
    - `bool rowHasText(uint16 y) const;`
    - `const TextPixel *row(uint16 y) const;`
    - `void putGlyph(int16 hx, int16 hy, const byte *coverage, int16 w, int16 h, byte fgIndex);` Coverage 0 leaves the pixel alone; any other value overwrites fg index and coverage.
    - `void clear();`
    - `void clearLowresRect(const Common::Rect &lowres);`
    - `void clearLowresPixel(int16 x, int16 y);`
    - `uint32 saveSize(const Common::Rect &lowres) const;` The upper bound `save()` writes.
    - `void save(const Common::Rect &lowres, byte *&out) const;`
    - `void restore(const Common::Rect &lowres, const byte *&in);`

- [ ] **Step 1: Write the failing test**

`test/engines/sci/textlayer.h`:

```cpp
#include <cxxtest/TestSuite.h>

#include "common/rect.h"
#include "sci/graphics/textlayer.h"

class SciTextLayerTestSuite : public CxxTest::TestSuite {
public:
	static Common::Array<byte> fill(int w, int h, byte v) {
		Common::Array<byte> a;
		a.resize(w * h);
		for (uint i = 0; i < a.size(); i++)
			a[i] = v;
		return a;
	}

	void test_new_layer_is_empty() {
		Sci::TextLayer l(8, 4, 2);
		TS_ASSERT(l.isEmpty());
		TS_ASSERT(!l.rowHasText(0));
		TS_ASSERT_EQUALS(l.row(3)[7].fgCoverage, 0);
	}

	void test_put_glyph_writes_nonzero_coverage_only() {
		Sci::TextLayer l(8, 4, 2);
		const byte cov[4] = { 0, 128, 255, 0 };   // 4x1
		l.putGlyph(2, 1, cov, 4, 1, 15);
		TS_ASSERT(!l.isEmpty());
		TS_ASSERT(l.rowHasText(1));
		TS_ASSERT(!l.rowHasText(0));
		TS_ASSERT_EQUALS(l.row(1)[2].fgCoverage, 0);
		TS_ASSERT_EQUALS(l.row(1)[3].fgCoverage, 128);
		TS_ASSERT_EQUALS(l.row(1)[3].fgIndex, 15);
		TS_ASSERT_EQUALS(l.row(1)[4].fgCoverage, 255);
	}

	void test_put_glyph_clips_to_the_layer() {
		Sci::TextLayer l(4, 2, 2);
		Common::Array<byte> cov = fill(4, 4, 255);
		l.putGlyph(2, -1, cov.begin(), 4, 4, 1);   // hangs off right and top
		TS_ASSERT_EQUALS(l.row(0)[3].fgCoverage, 255);
		TS_ASSERT_EQUALS(l.row(0)[1].fgCoverage, 0);
	}

	void test_clear_lowres_rect_clears_scaled_block() {
		Sci::TextLayer l(8, 8, 2);
		Common::Array<byte> cov = fill(8, 8, 255);
		l.putGlyph(0, 0, cov.begin(), 8, 8, 1);
		l.clearLowresRect(Common::Rect(1, 1, 2, 3));   // hires x 2..3, y 2..5
		TS_ASSERT_EQUALS(l.row(2)[2].fgCoverage, 0);
		TS_ASSERT_EQUALS(l.row(5)[3].fgCoverage, 0);
		TS_ASSERT_EQUALS(l.row(1)[2].fgCoverage, 255);
		TS_ASSERT_EQUALS(l.row(6)[2].fgCoverage, 255);
		TS_ASSERT_EQUALS(l.row(2)[4].fgCoverage, 255);
	}

	void test_clear_lowres_pixel() {
		Sci::TextLayer l(4, 4, 2);
		Common::Array<byte> cov = fill(4, 4, 255);
		l.putGlyph(0, 0, cov.begin(), 4, 4, 1);
		l.clearLowresPixel(1, 0);
		TS_ASSERT_EQUALS(l.row(0)[2].fgCoverage, 0);
		TS_ASSERT_EQUALS(l.row(1)[3].fgCoverage, 0);
		TS_ASSERT_EQUALS(l.row(0)[1].fgCoverage, 255);
	}

	void test_save_restore_brings_text_back() {
		// Window over window: save the lower window's area, the upper
		// window fills it (clear), closing the upper window restores it.
		Sci::TextLayer l(8, 8, 2);
		Common::Array<byte> cov = fill(8, 8, 200);
		l.putGlyph(0, 0, cov.begin(), 8, 8, 9);
		const Common::Rect r(0, 0, 4, 4);
		Common::Array<byte> mem;
		mem.resize(l.saveSize(r));
		byte *w = mem.begin();
		l.save(r, w);
		TS_ASSERT(w <= mem.end());
		l.clearLowresRect(r);
		TS_ASSERT_EQUALS(l.row(3)[3].fgCoverage, 0);
		const byte *rd = mem.begin();
		l.restore(r, rd);
		TS_ASSERT_EQUALS(rd, (const byte *)w);
		TS_ASSERT_EQUALS(l.row(3)[3].fgCoverage, 200);
		TS_ASSERT_EQUALS(l.row(3)[3].fgIndex, 9);
	}

	void test_restore_of_an_empty_save_clears() {
		Sci::TextLayer l(8, 8, 2);
		const Common::Rect r(0, 0, 2, 2);
		Common::Array<byte> mem;
		mem.resize(l.saveSize(r));
		byte *w = mem.begin();
		l.save(r, w);                 // nothing there
		Common::Array<byte> cov = fill(4, 4, 255);
		l.putGlyph(0, 0, cov.begin(), 4, 4, 1);
		const byte *rd = mem.begin();
		l.restore(r, rd);             // restores "no text"
		TS_ASSERT_EQUALS(l.row(0)[0].fgCoverage, 0);
	}
};
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ~/work/scummvm/i18n/.worktrees/c1-compositor
./configure --disable-all-engines --enable-engine=sci   # once per worktree
make test 2>&1 | tail -5     # `python` must resolve to python3 (cxxtestgen's shebang)
```

Expected: a compile error, `sci/graphics/textlayer.h: No such file`.

- [ ] **Step 3: Write the implementation**

`engines/sci/graphics/textlayer.h`:

```cpp
#ifndef SCI_GRAPHICS_TEXTLAYER_H
#define SCI_GRAPHICS_TEXTLAYER_H

#include "common/array.h"
#include "common/rect.h"
#include "common/scummsys.h"

namespace Sci {

/** One hi-res pixel of text: a foreground and an outline, each a palette
 *  index plus 8-bit coverage. Colour is resolved when composited, so text
 *  follows palette changes the way the original's indexed text did. */
struct TextPixel {
	byte fgIndex;
	byte fgCoverage;
	byte outlineIndex;
	byte outlineCoverage;
};

/**
 * Hi-res text as part of the visual plane (HIRES_COMPOSITOR_DESIGN.md D3):
 * whatever the game does to a low-res visual pixel it does to the scale x
 * scale block here - a pixel write clears it, underbits save and restore
 * carry it. Nothing here knows about the engine, so it is unit tested
 * alone.
 */
class TextLayer {
public:
	TextLayer(uint16 width, uint16 height, uint16 scale);

	uint16 width() const { return _width; }
	uint16 height() const { return _height; }
	uint16 scale() const { return _scale; }

	/** No row has ever held text since the last clear(). Cheap: callers on
	 *  hot paths test this first. */
	bool isEmpty() const { return !_any; }
	/** Conservative: true if the row may hold text. */
	bool rowHasText(uint16 y) const { return _rowFlags[y] != 0; }
	const TextPixel *row(uint16 y) const { return &_pixels[(uint32)y * _width]; }

	/** Coverage 0 leaves a pixel alone; any other value sets fg index and
	 *  coverage. Clipped to the layer. */
	void putGlyph(int16 hx, int16 hy, const byte *coverage, int16 w, int16 h, byte fgIndex);

	void clear();
	void clearLowresRect(const Common::Rect &lowres);
	void clearLowresPixel(int16 x, int16 y) { if (_any) clearLowresRect(Common::Rect(x, y, x + 1, y + 1)); }

	/** Upper bound of what save() writes for this rect. */
	uint32 saveSize(const Common::Rect &lowres) const;
	/** A flag byte, then the block's pixels if the flag is 1. */
	void save(const Common::Rect &lowres, byte *&out) const;
	void restore(const Common::Rect &lowres, const byte *&in);

private:
	Common::Rect toHires(const Common::Rect &lowres) const;

	uint16 _width, _height, _scale;
	bool _any;
	Common::Array<TextPixel> _pixels;
	Common::Array<byte> _rowFlags;
};

} // End of namespace Sci

#endif
```

`engines/sci/graphics/textlayer.cpp` (keep the GPL header block used by every file in `engines/sci`):

```cpp
#include "sci/graphics/textlayer.h"

namespace Sci {

static_assert(sizeof(TextPixel) == 4, "TextPixel is saved raw into underbits");

TextLayer::TextLayer(uint16 width, uint16 height, uint16 scale)
	: _width(width), _height(height), _scale(scale), _any(false) {
	_pixels.resize((uint32)width * height);
	_rowFlags.resize(height);
	clear();
}

void TextLayer::clear() {
	TextPixel none = { 0, 0, 0, 0 };
	for (uint i = 0; i < _pixels.size(); i++)
		_pixels[i] = none;
	for (uint i = 0; i < _rowFlags.size(); i++)
		_rowFlags[i] = 0;
	_any = false;
}

Common::Rect TextLayer::toHires(const Common::Rect &lowres) const {
	Common::Rect r(lowres.left * _scale, lowres.top * _scale, lowres.right * _scale, lowres.bottom * _scale);
	r.clip(Common::Rect(0, 0, _width, _height));
	return r;
}

void TextLayer::putGlyph(int16 hx, int16 hy, const byte *coverage, int16 w, int16 h, byte fgIndex) {
	for (int16 gy = 0; gy < h; gy++) {
		const int y = hy + gy;
		if (y < 0 || y >= _height)
			continue;
		TextPixel *dst = &_pixels[(uint32)y * _width];
		bool wrote = false;
		for (int16 gx = 0; gx < w; gx++) {
			const byte c = coverage[gy * w + gx];
			const int x = hx + gx;
			if (!c || x < 0 || x >= _width)
				continue;
			dst[x].fgIndex = fgIndex;
			dst[x].fgCoverage = c;
			wrote = true;
		}
		if (wrote) {
			_rowFlags[y] = 1;
			_any = true;
		}
	}
}

void TextLayer::clearLowresRect(const Common::Rect &lowres) {
	if (!_any)
		return;
	const Common::Rect r = toHires(lowres);
	TextPixel none = { 0, 0, 0, 0 };
	for (int y = r.top; y < r.bottom; y++)
		for (int x = r.left; x < r.right; x++)
			_pixels[(uint32)y * _width + x] = none;
}

uint32 TextLayer::saveSize(const Common::Rect &lowres) const {
	const Common::Rect r = toHires(lowres);
	return 1 + (uint32)r.width() * r.height() * sizeof(TextPixel);
}

void TextLayer::save(const Common::Rect &lowres, byte *&out) const {
	const Common::Rect r = toHires(lowres);
	bool any = false;
	for (int y = r.top; y < r.bottom && !any; y++)
		any = rowHasText(y);
	*out++ = any ? 1 : 0;
	if (!any)
		return;
	for (int y = r.top; y < r.bottom; y++) {
		const uint32 n = r.width() * sizeof(TextPixel);
		memcpy(out, &_pixels[(uint32)y * _width + r.left], n);
		out += n;
	}
}

void TextLayer::restore(const Common::Rect &lowres, const byte *&in) {
	const Common::Rect r = toHires(lowres);
	const byte flag = *in++;
	if (!flag) {
		clearLowresRect(lowres);
		return;
	}
	for (int y = r.top; y < r.bottom; y++) {
		const uint32 n = r.width() * sizeof(TextPixel);
		memcpy(&_pixels[(uint32)y * _width + r.left], in, n);
		in += n;
		_rowFlags[y] = 1;
	}
	_any = true;
}

} // End of namespace Sci
```

Add `graphics/textlayer.o \` to `MODULE_OBJS` in `engines/sci/module.mk`, keeping alphabetical order within the `graphics/` block.

- [ ] **Step 4: Run to verify it passes**

```bash
make test 2>&1 | grep -E 'Running cxxtest|OK!|Failed'
```

Expected: `Running cxxtest tests (428 tests)` then `OK!`. That is 421 + 7.

- [ ] **Step 5: Commit**

```bash
git add engines/sci/graphics/textlayer.h engines/sci/graphics/textlayer.cpp engines/sci/module.mk test/engines/sci/textlayer.h
git commit -m "SCI: A text layer that follows the visual plane, as a unit-tested class"
```

---

### Task 2: TextCompose — coverage, blend, compose, stamp

**Files:**
- Create: `engines/sci/graphics/textcompose.h`, `engines/sci/graphics/textcompose.cpp`
- Modify: `engines/sci/module.mk` (add `graphics/textcompose.o`)
- Test: `test/engines/sci/textcompose.h`

**Interfaces:**
- Consumes: `Sci::TextPixel` (Task 1).
- Produces (namespace `Sci::TextCompose`):
  - `byte expandCoverage(const byte *row, int x, int bpp);` bpp 1 → 0/255, 2 → 0/85/170/255, 8 → the byte.
  - `void expandGlyphRow(byte *dstCoverage, const byte *row, int width, int bpp, bool greyed, int screenY, int screenX0);` With greyed set, pixels where `screenY % 2 == (screenX0 + x) % 2` become 0 (the engine's checkerboard).
  - `inline byte blend(byte dst, byte src, byte a)` returns `(dst * (255 - a) + src * a + 127) / 255`.
  - `void composeSpan(byte *dst, const Graphics::PixelFormat &fmt, const TextPixel *text, int count, const byte *paletteRGB);` dst holds `count` pixels in `fmt` (2 or 4 bytes). Outline is blended first, then fg.
  - `void stampSpan(byte *dstIndex, const TextPixel *text, int count);` For CLUT8: fg coverage ≥ 128 writes fgIndex; otherwise outline coverage ≥ 128 writes outlineIndex.

- [ ] **Step 1: Write the failing test**

`test/engines/sci/textcompose.h`:

```cpp
#include <cxxtest/TestSuite.h>

#include "graphics/pixelformat.h"
#include "sci/graphics/textcompose.h"
#include "sci/graphics/textlayer.h"

class SciTextComposeTestSuite : public CxxTest::TestSuite {
public:
	static Graphics::PixelFormat argb() { return Graphics::PixelFormat(4, 8, 8, 8, 8, 16, 8, 0, 24); }
	static Graphics::PixelFormat rgb565() { return Graphics::PixelFormat(2, 5, 6, 5, 0, 11, 5, 0, 0); }

	void test_expand_coverage_1_2_8_bpp() {
		const byte one[1] = { 0xA0 };            // 1010 0000
		TS_ASSERT_EQUALS(Sci::TextCompose::expandCoverage(one, 0, 1), 255);
		TS_ASSERT_EQUALS(Sci::TextCompose::expandCoverage(one, 1, 1), 0);
		const byte two[1] = { 0x1B };            // 00 01 10 11
		TS_ASSERT_EQUALS(Sci::TextCompose::expandCoverage(two, 0, 2), 0);
		TS_ASSERT_EQUALS(Sci::TextCompose::expandCoverage(two, 1, 2), 85);
		TS_ASSERT_EQUALS(Sci::TextCompose::expandCoverage(two, 2, 2), 170);
		TS_ASSERT_EQUALS(Sci::TextCompose::expandCoverage(two, 3, 2), 255);
		const byte eight[2] = { 7, 200 };
		TS_ASSERT_EQUALS(Sci::TextCompose::expandCoverage(eight, 1, 8), 200);
	}

	void test_expand_row_greyed_checkerboard() {
		const byte eight[4] = { 255, 255, 255, 255 };
		byte out[4];
		Sci::TextCompose::expandGlyphRow(out, eight, 4, 8, true, 10, 3);
		// screenY 10 is even: pixel x is dropped where (3 + x) is even.
		TS_ASSERT_EQUALS(out[0], 255);   // 3 odd
		TS_ASSERT_EQUALS(out[1], 0);     // 4 even
		TS_ASSERT_EQUALS(out[2], 255);
		TS_ASSERT_EQUALS(out[3], 0);
		Sci::TextCompose::expandGlyphRow(out, eight, 4, 8, false, 10, 3);
		TS_ASSERT_EQUALS(out[1], 255);
	}

	void test_blend_endpoints_and_middle() {
		TS_ASSERT_EQUALS(Sci::TextCompose::blend(10, 200, 0), 10);
		TS_ASSERT_EQUALS(Sci::TextCompose::blend(10, 200, 255), 200);
		TS_ASSERT_EQUALS(Sci::TextCompose::blend(0, 255, 128), 128);
	}

	void test_compose_outline_then_fg_argb() {
		byte pal[768] = { 0 };
		pal[3 * 1 + 0] = 255;                              // index 1 red
		pal[3 * 2 + 0] = pal[3 * 2 + 1] = pal[3 * 2 + 2] = 255;   // index 2 white
		const Graphics::PixelFormat f = argb();
		uint32 px = f.RGBToColor(0, 0, 0);
		Sci::TextPixel t = { 2, 128, 1, 255 };             // half white over full red outline
		Sci::TextCompose::composeSpan((byte *)&px, f, &t, 1, pal);
		byte r, g, b;
		f.colorToRGB(px, r, g, b);
		TS_ASSERT_EQUALS(r, 255);
		TS_ASSERT_EQUALS(g, 128);
		TS_ASSERT_EQUALS(b, 128);
	}

	void test_compose_skips_uncovered_pixels_rgb565() {
		byte pal[768] = { 0 };
		const Graphics::PixelFormat f = rgb565();
		uint16 px[2] = { (uint16)f.RGBToColor(80, 160, 240), (uint16)f.RGBToColor(80, 160, 240) };
		const uint16 before = px[1];
		Sci::TextPixel t[2] = { { 0, 255, 0, 0 }, { 0, 0, 0, 0 } };
		Sci::TextCompose::composeSpan((byte *)px, f, t, 2, pal);
		TS_ASSERT_EQUALS(px[0], (uint16)f.RGBToColor(0, 0, 0));
		TS_ASSERT_EQUALS(px[1], before);
	}

	void test_compose_follows_palette() {
		byte palA[768] = { 0 }, palB[768] = { 0 };
		palA[3 * 5 + 1] = 255;          // index 5 green in A
		palB[3 * 5 + 2] = 255;          // index 5 blue in B
		const Graphics::PixelFormat f = argb();
		Sci::TextPixel t = { 5, 255, 0, 0 };
		uint32 a = f.RGBToColor(0, 0, 0), b = a;
		Sci::TextCompose::composeSpan((byte *)&a, f, &t, 1, palA);
		Sci::TextCompose::composeSpan((byte *)&b, f, &t, 1, palB);
		TS_ASSERT_EQUALS(a, f.RGBToColor(0, 255, 0));
		TS_ASSERT_EQUALS(b, f.RGBToColor(0, 0, 255));
	}

	void test_stamp_span() {
		byte idx[3] = { 7, 7, 7 };
		Sci::TextPixel t[3] = { { 3, 200, 0, 0 }, { 3, 100, 4, 255 }, { 3, 100, 4, 100 } };
		Sci::TextCompose::stampSpan(idx, t, 3);
		TS_ASSERT_EQUALS(idx[0], 3);
		TS_ASSERT_EQUALS(idx[1], 4);
		TS_ASSERT_EQUALS(idx[2], 7);
	}
};
```

- [ ] **Step 2: Run to verify it fails**

Run: `make test 2>&1 | tail -3`
Expected: a compile error, `sci/graphics/textcompose.h: No such file`.

- [ ] **Step 3: Write the implementation**

`engines/sci/graphics/textcompose.h`:

```cpp
#ifndef SCI_GRAPHICS_TEXTCOMPOSE_H
#define SCI_GRAPHICS_TEXTCOMPOSE_H

#include "common/scummsys.h"
#include "graphics/pixelformat.h"

namespace Sci {

struct TextPixel;

/** The arithmetic of hi-res text, free of engine state so it is tested alone
 *  (HIRES_COMPOSITOR_DESIGN.md §3.2). */
namespace TextCompose {

byte expandCoverage(const byte *row, int x, int bpp);
void expandGlyphRow(byte *dstCoverage, const byte *row, int width, int bpp, bool greyed, int screenY, int screenX0);

inline byte blend(byte dst, byte src, byte a) {
	return (byte)(((uint32)dst * (255 - a) + (uint32)src * a + 127) / 255);
}

void composeSpan(byte *dst, const Graphics::PixelFormat &fmt, const TextPixel *text, int count, const byte *paletteRGB);
void stampSpan(byte *dstIndex, const TextPixel *text, int count);

} // End of namespace TextCompose
} // End of namespace Sci

#endif
```

`engines/sci/graphics/textcompose.cpp`:

```cpp
#include "common/endian.h"
#include "sci/graphics/textcompose.h"
#include "sci/graphics/textlayer.h"

namespace Sci {
namespace TextCompose {

byte expandCoverage(const byte *row, int x, int bpp) {
	switch (bpp) {
	case 1:
		return (row[x >> 3] & (0x80 >> (x & 7))) ? 255 : 0;
	case 2:
		return ((row[x >> 2] >> (6 - ((x & 3) * 2))) & 3) * 85;
	default:
		return row[x];
	}
}

void expandGlyphRow(byte *dstCoverage, const byte *row, int width, int bpp, bool greyed, int screenY, int screenX0) {
	for (int x = 0; x < width; x++) {
		byte c = expandCoverage(row, x, bpp);
		// The engine's checkerboard for disabled text: drop every other pixel.
		if (greyed && (screenY % 2) == ((screenX0 + x) % 2))
			c = 0;
		dstCoverage[x] = c;
	}
}

static void blendRGB(byte &r, byte &g, byte &b, const byte *pal, byte index, byte a) {
	r = blend(r, pal[index * 3 + 0], a);
	g = blend(g, pal[index * 3 + 1], a);
	b = blend(b, pal[index * 3 + 2], a);
}

void composeSpan(byte *dst, const Graphics::PixelFormat &fmt, const TextPixel *text, int count, const byte *paletteRGB) {
	const int bpp = fmt.bytesPerPixel;
	for (int i = 0; i < count; i++, dst += bpp) {
		const TextPixel &t = text[i];
		if (!t.fgCoverage && !t.outlineCoverage)
			continue;
		uint32 c = (bpp == 2) ? READ_UINT16(dst) : READ_UINT32(dst);
		byte r, g, b;
		fmt.colorToRGB(c, r, g, b);
		if (t.outlineCoverage)
			blendRGB(r, g, b, paletteRGB, t.outlineIndex, t.outlineCoverage);
		if (t.fgCoverage)
			blendRGB(r, g, b, paletteRGB, t.fgIndex, t.fgCoverage);
		c = fmt.RGBToColor(r, g, b);
		if (bpp == 2)
			WRITE_UINT16(dst, c);
		else
			WRITE_UINT32(dst, c);
	}
}

void stampSpan(byte *dstIndex, const TextPixel *text, int count) {
	for (int i = 0; i < count; i++) {
		if (text[i].fgCoverage >= 128)
			dstIndex[i] = text[i].fgIndex;
		else if (text[i].outlineCoverage >= 128)
			dstIndex[i] = text[i].outlineIndex;
	}
}

} // End of namespace TextCompose
} // End of namespace Sci
```

- [ ] **Step 4: Run to verify it passes**

Run: `make test 2>&1 | grep -E 'Running cxxtest|OK!|Failed'`
Expected: 435 tests (428 + 7), `OK!`.

- [ ] **Step 5: Commit**

```bash
git add engines/sci/graphics/textcompose.h engines/sci/graphics/textcompose.cpp engines/sci/module.mk test/engines/sci/textcompose.h
git commit -m "SCI: Coverage expansion, alpha blend and CLUT8 stamp for hi-res text"
```

---

### Task 3: SCVMUNI at 8 bpp — reader and builder

**Files:**
- Modify: `engines/sci/graphics/fontunicode.h/.cpp` (`load` flags, `pixelSet`, `drawToBuffer`, and later Task 5's `draw`)
- Modify: `harness/i18n/m7mkfont.py`, `harness/i18n/m7check.py` (harness repo)

**Interfaces:**
- Consumes: `TextCompose::expandCoverage` (Task 2).
- Produces: SCVMUNI `flags` bit1 means 8 bpp (bit0 still means 2 bpp; both set is rejected). `GfxFontUnicode::_bitsPerPixel` ∈ {1, 2, 8}. `GfxFontUnicode::coverageRow(int glyph, int y) const` returns `const byte *` (the packed row, for `expandGlyphRow`). `m7mkfont.py --bpp 8`.

- [ ] **Step 1: Builder writes 8 bpp**

In `m7mkfont.py`, change `choices=(1, 2)` to `choices=(1, 2, 8)`. Change the header write (line 240) to:

```python
    out += struct.pack("<HH", VERSION, {1: 0, 2: 1, 8: 2}[bpp])
```

and in the glyph loop (after the `if bpp == 1:` block):

```python
                elif bpp == 8:
                    # Full coverage, no threshold: the compositor blends it.
                    glyph[y * rowBytes + x] = v
```

(`rowBytes = (strideBits * bpp + 7) // 8` already gives one byte per pixel at 8 bpp.) Keep the existing 2 bpp branch as `else:`.

Update the header comment (line 20) to `bit0: 2bpp, bit1: 8bpp coverage (else 1bpp)`. Update the header reads in `m7mkfont.py` (line 263) and `m7check.py` (line 24) to:

```python
    bpp = 8 if (flags & 2) else (2 if (flags & 1) else 1)
```

In both show/verify loops add an `elif bpp == 8:` branch (`on = d[base + y * rb + x]`, and for display `" .:#"[min(3, v >> 6)]`).

- [ ] **Step 2: Build a font and verify it**

```bash
cd ~/work/scummvm
python3 harness/i18n/m7mkfont.py --ttf <a Hangul TTF> --size 16 --bpp 8 --out /tmp/ko8.uni
python3 harness/i18n/m7check.py /tmp/ko8.uni | head -3
```

Expected: `version=1 bpp=8 cell=...`, and the checker's EAW check passes. For the TTF use the one that built `gamedata/dist-ef8dc87f/kq1-ko/korean.uni`, found in `harness/i18n/*.sh` or the dist build notes. If it cannot be identified, use a system Hangul face (`/System/Library/Fonts/AppleSDGothicNeo.ttc` is not a .ttf; prefer a `.ttf`/`.otf` under `~/work/scummvm/fonts`) and record which one in the commit message.

- [ ] **Step 3: Reader accepts 8 bpp**

In `GfxFontUnicode::load` replace `_bitsPerPixel = (flags & 1) ? 2 : 1;` with:

```cpp
	if ((flags & 3) == 3) {
		warning("GfxFontUnicode: %s sets both 2bpp and 8bpp", filename.c_str());
		_data.clear();
		return false;
	}
	_bitsPerPixel = (flags & 2) ? 8 : ((flags & 1) ? 2 : 1);
```

Replace the body of `pixelSet` with:

```cpp
	const byte *row = _bitmaps + (uint32)glyph * _bytesPerGlyph + (uint32)y * _rowBytes;
	return TextCompose::expandCoverage(row, x, _bitsPerPixel) != 0;
```

and add `#include "sci/graphics/textcompose.h"`. Add the accessor to the header (public):

```cpp
	/** The packed row y of glyph g, for TextCompose::expandGlyphRow(). */
	const byte *coverageRow(int glyph, int y) const {
		return _bitmaps + (uint32)glyph * _bytesPerGlyph + (uint32)y * _rowBytes;
	}
	int bitsPerPixel() const { return _bitsPerPixel; }
```

- [ ] **Step 4: Build and test**

```bash
make -j10 && make test 2>&1 | grep -E 'Running cxxtest|OK!|Failed'
```

Expected: the build succeeds, 435 tests `OK!`. The 1/2 bpp decode is covered by `test_expand_coverage_1_2_8_bpp`.

- [ ] **Step 5: Commit both repos**

```bash
git add engines/sci/graphics/fontunicode.h engines/sci/graphics/fontunicode.cpp
git commit -m "SCI: Read 8-bit coverage SCVMUNI fonts"
cd ~/work/scummvm && git add harness/i18n/m7mkfont.py harness/i18n/m7check.py
git commit -m "m7mkfont: --bpp 8, full coverage for the compositor"
```

---

### Task 4: The driver composites the layer

**Files:**
- Modify: `engines/sci/graphics/drivers/gfxdriver.h`
- Modify: `engines/sci/graphics/drivers/gfxdriver_intern.h` (class `UpscaledGfxDriver`)
- Modify: `engines/sci/graphics/drivers/upscaled.cpp` (`updateScreen`)
- Modify: `engines/sci/debugsocket.cpp` (`dumpBuffers`)

**Interfaces:**
- Consumes: `TextLayer`, `TextCompose::composeSpan`, `TextCompose::stampSpan`.
- Produces:
  - `virtual void GfxDriver::setTextLayer(const TextLayer *layer) {}`
  - `virtual void GfxDriver::refreshHiresRect(const Common::Rect &hires) {}`, which re-presents that rect (composite included).
  - `UpscaledGfxDriver` overrides both.
  - Dumps gain `<prefix>_out.bin` (the backend screen, raw) with `<prefix>_out.txt` (`w h bpp rBits gBits bBits aBits rShift gShift bShift aShift`). (`_layer.bin` comes with Task 5, which adds the screen's accessor.)

- [ ] **Step 1: Declare**

In `gfxdriver.h`, add `namespace Sci { class TextLayer; }` via a forward declaration near the top, and in `class GfxDriver` (public):

```cpp
	/** Hi-res text the driver blends over the scaled picture on every update
	 *  (HIRES_COMPOSITOR_DESIGN.md). Only upscaled drivers use it. */
	virtual void setTextLayer(const TextLayer *layer) {}
	/** Present a hi-res rect again, text included, without re-scaling it. */
	virtual void refreshHiresRect(const Common::Rect &hires) {}
```

In `UpscaledGfxDriver` (public) add the two overrides, and (private) `const TextLayer *_textLayer;` plus `Common::Array<byte> _stampBuffer;`. Initialise `_textLayer(nullptr)` in the protected constructor's init list.

- [ ] **Step 2: Implement in `upscaled.cpp`**

Add `#include "sci/graphics/textcompose.h"` and `#include "sci/graphics/textlayer.h"`. Then:

```cpp
void UpscaledGfxDriver::setTextLayer(const TextLayer *layer) {
	_textLayer = layer;
}

void UpscaledGfxDriver::refreshHiresRect(const Common::Rect &hires) {
	Common::Rect r(hires);
	r.clip(Common::Rect(0, 0, _screenW, _screenH));
	if (!r.isEmpty())
		updateScreen(r.left, r.top, r.width(), r.height(), nullptr, nullptr);
}
```

In `updateScreen`, between the conversion `if/else` and `g_system->copyRectToScreen(...)`:

```cpp
	// Hi-res text is blended here, over pixels just converted from the
	// scaled bitmap, which itself never holds text. So any update of any
	// rect re-derives text and picture together and nothing can erase one
	// with the other (HIRES_COMPOSITOR_DESIGN.md D2).
	if (_textLayer && !_textLayer->isEmpty()) {
		if (_pixelSize > 1) {
			for (int y = 0; y < h; y++) {
				if (!_textLayer->rowHasText(destY + y))
					continue;
				TextCompose::composeSpan(buff + y * pitch, _format, _textLayer->row(destY + y) + destX, w, _currentPalette);
			}
		} else {
			// CLUT8 output: no room for a blend; stamp coverage >= 50%.
			if (buff == scb) {
				_stampBuffer.resize((uint32)w * h);
				for (int y = 0; y < h; y++)
					memcpy(&_stampBuffer[y * w], scb + y * _screenW, w);
				buff = _stampBuffer.begin();
				pitch = w;
			}
			for (int y = 0; y < h; y++) {
				if (_textLayer->rowHasText(destY + y))
					TextCompose::stampSpan(buff + y * pitch, _textLayer->row(destY + y) + destX, w);
			}
		}
	}
```

`_currentPalette` is 256×3 RGB and allocated whenever `_pixelSize > 1` (`default.cpp:149`).

- [ ] **Step 3: Dump the frame the backend shows**

In `DebugSocket::dumpBuffers`, after the `_scaled` block:

```cpp
	// What the player sees: the backend screen after the driver's composite.
	if (Graphics::Surface *s = g_system->lockScreen()) {
		if (f.open(Common::Path(prefix + "_out.bin"))) {
			for (int y = 0; y < s->h; y++)
				f.write((const byte *)s->getBasePtr(0, y), s->w * s->format.bytesPerPixel);
			f.close();
		} else ok = false;
		const Graphics::PixelFormat &pf = s->format;
		if (f.open(Common::Path(prefix + "_out.txt"))) {
			f.writeString(Common::String::format("%d %d %d %d %d %d %d %d %d %d %d\n", s->w, s->h, pf.bytesPerPixel,
				8 - pf.rLoss, 8 - pf.gLoss, 8 - pf.bLoss, 8 - pf.aLoss, pf.rShift, pf.gShift, pf.bShift, pf.aShift));
			f.close();
		}
		g_system->unlockScreen();
	}
```

(Include `graphics/surface.h`.)

- [ ] **Step 4: Build, test, and check nothing changed yet**

Nothing sets a layer yet, so behaviour must be unchanged:

```bash
make -j10 && make test 2>&1 | grep -E 'Running cxxtest|OK!'
cd ~/work/scummvm
SCIGAME_EXTRA_INI='disable_dithering=true\nrgb_rendering=true' python3 harness/i18n/kq1_intro.py $PWD/gamedata/dist-ef8dc87f/kq1-ko $PWD/runs/t4-intro-ko ko
for f in $(cd runs/baseline-4a0f7f0e1c/intro-ko && ls *.bin); do cmp -s runs/baseline-4a0f7f0e1c/intro-ko/$f runs/t4-intro-ko/$f || echo DIFF $f; done
```

Run the capture with the worktree's binary. `scigame.py` uses `SRC=~/work/scummvm/i18n`, so pass `binary=` or temporarily point `SRC` at the worktree. `TREES.md` warns that measuring the wrong build fails silently. Expected: `OK!`, no `DIFF` (the new `_out.*` files are extra and not compared).

- [ ] **Step 5: Commit**

```bash
git add engines/sci/graphics/drivers/gfxdriver.h engines/sci/graphics/drivers/gfxdriver_intern.h engines/sci/graphics/drivers/upscaled.cpp engines/sci/debugsocket.cpp
git commit -m "SCI: The upscaled driver blends a text layer over each update, and the debug socket dumps what the backend shows"
```

---

### Task 5: GfxScreen owns the layer; glyphs go into it

**Files:**
- Modify: `engines/sci/graphics/screen.h/.cpp`
- Modify: `engines/sci/graphics/fontunicode.cpp` (`draw`)
- Modify: `engines/sci/graphics/paint16.cpp:101` (new-picture clear)
- Modify: `engines/sci/debugsocket.cpp` (`_plane.bin` → `_layer.bin`)
- Create: `harness/i18n/c1ab.py` (harness repo)

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `void GfxScreen::putHiresCoverageGlyph(const byte *coverage, int16 w, int16 h, int16 x, int16 y, byte color);` x and y are low-res, as for `putHiresGlyph`.
  - `const TextLayer *GfxScreen::textLayer() const;` (null until first use)
  - `void GfxScreen::clearTextLayer();`
  - `void GfxScreen::clearTextLayer(const Common::Rect &lowres);`
  - Removed: `_hiresTextPlane`, `rememberHiresGlyph`, `restoreHiresTextPlane`, `clearHiresTextPlane(*)`, `putHiresGlyphPersistent`, `hiresTextPlane()`.

- [ ] **Step 1: Screen side**

In `screen.h` replace the `_hiresTextPlane` member and its helpers with:

```cpp
	/** Hi-res text, a hi-res extension of the visual plane. Allocated on the
	 *  first hi-res glyph; a game that never draws one pays nothing. */
	TextLayer *_textLayer;
	TextLayer *ensureTextLayer();
```

and the public API listed under **Produces**. In `screen.cpp`:

```cpp
TextLayer *GfxScreen::ensureTextLayer() {
	if (!_textLayer) {
		_textLayer = new TextLayer(_displayWidth * 2, _displayHeight * 2, 2);
		_gfxDrv->setTextLayer(_textLayer);
	}
	return _textLayer;
}

void GfxScreen::putHiresCoverageGlyph(const byte *coverage, int16 w, int16 h, int16 x, int16 y, byte color) {
	TextLayer *l = ensureTextLayer();
	// The colour is used as given, as the old putHiresGlyphPersistent() path
	// did: remapTextColor() belongs to putKanjiChar (PC-98 text mode) and
	// returns 0 on QFG/SCI1 PC-98 drivers, so applying it here would change
	// what a SCVMUNI font draws on those releases.
	l->putGlyph(x << 1, y << 1, coverage, w, h, color);
	// Shown at once, as the old direct-to-driver draw was: callers that
	// relied on that (kDisplay's Box) keep working unchanged.
	_gfxDrv->refreshHiresRect(Common::Rect(x << 1, y << 1, (x << 1) + w, (y << 1) + h));
}

void GfxScreen::clearTextLayer() {
	if (_textLayer)
		_textLayer->clear();
}

void GfxScreen::clearTextLayer(const Common::Rect &lowres) {
	if (_textLayer)
		_textLayer->clearLowresRect(lowres);
}
```

Set `_textLayer = nullptr` in the constructor. In the destructor call `_gfxDrv->setTextLayer(nullptr)` and then `delete _textLayer;`. The driver is destroyed after the screen: check the `~GfxScreen` order and keep the reset before any delete. Replace the `clearHiresTextPlane()` call in `clearForRestoreGame()` with `clearTextLayer();`. In `displayRect()` delete the `_hiresTextPlane` re-apply block, so the method is just the `_gfxDrv->copyRectToScreen(...)` call.

`putHangulChar`: after `commonFont->drawChar(...)` renders into `_hiresGlyphBuffer` (0xff = unset), convert it and call the new path instead of `putHiresGlyphPersistent`:

```cpp
	byte cov[16 * 16];
	const int gh = commonFont->getFontHeight();
	for (int i = 0; i < charWidth * gh; i++)
		cov[i] = (_hiresGlyphBuffer[i] != 0xff) ? 255 : 0;
	putHiresCoverageGlyph(cov, charWidth, gh, x, y, color);
```

(Read the lines just above the existing call to confirm the buffer pitch is `charWidth`. It is passed as the pitch to the old call.) Delete `putHiresGlyphPersistent`, `rememberHiresGlyph`, `restoreHiresTextPlane`, both `clearHiresTextPlane` overloads, `_hiresRestoreRow`, `kHiresTextAlignX` and `kHiresGlyphCellSize`, unless still referenced by `putKanjiChar` (it uses `putHiresGlyph`, which stays).

- [ ] **Step 2: The SCVMUNI face writes coverage**

In `GfxFontUnicode::draw`, replace the scratch-fill loop and the `putHiresGlyphPersistent` call with:

```cpp
	_glyphScratch.resize((uint)w * _cellHeight);
	byte *cov = _glyphScratch.begin();
	for (int y = 0; y < _cellHeight; y++)
		TextCompose::expandGlyphRow(cov + y * w, coverageRow(g, y), w, _bitsPerPixel, greyedOutput, top + y, left);
	_screen->putHiresCoverageGlyph(cov, w, _cellHeight, left, top, color);
```

Keep the explanatory comment about why double-byte text is not written as low-res pixels, and update its last paragraph to name the text layer.

- [ ] **Step 3: New picture, window removal, dumps**

- `paint16.cpp:101`: `_screen->clearHiresTextPlane();` → `_screen->clearTextLayer();` (comment unchanged).
- `ports.cpp:540`: delete `_screen->clearHiresTextPlane(pWnd->restoreRect);` and its comment for now. Task 6 makes the underbits restore bring back what was beneath. **Until Task 6 lands, a closed window's text would stay; do not merge Task 5 alone.**
- `debugsocket.cpp`: replace the `_plane.bin` block with:

```cpp
		if (const TextLayer *tl = scr->textLayer()) {
			if (f.open(Common::Path(prefix + "_layer.bin"))) {
				for (uint16 y = 0; y < tl->height(); y++)
					f.write(tl->row(y), (uint32)tl->width() * sizeof(TextPixel));
				f.close();
			}
		}
```

- [ ] **Step 4: Build and test**

```bash
make -j10 && make test 2>&1 | grep -E 'Running cxxtest|OK!|Failed'
```

Expected: builds, 435 `OK!`. If `grep -rn 'HiresTextPlane\|hiresTextPlane\|putHiresGlyphPersistent' engines/sci` returns anything, fix it before continuing.

- [ ] **Step 5: Write the A/B script (harness repo)**

`harness/i18n/c1ab.py`:

```python
#!/usr/bin/env python3
"""c1ab.py - old re-apply plane vs new compositor, as the player sees them.

    c1ab.py <baseline_dir> <new_dir>

For every <name>_scaled.bin in baseline_dir (old build: glyphs stamped into
the CLUT8 scaled bitmap, colours from <name>_pal.bin) there must be a
<name>_out.bin in new_dir (new build: the backend frame, format in
<name>_out.txt). Both become RGB and are compared pixel by pixel. With a
1 bpp font every glyph pixel has coverage 255, so the two must be equal.
Exit 1 on any difference; print the rows that differ.
"""
import os
import sys


def old_rgb(d, name):
    idx = open(os.path.join(d, name + "_scaled.bin"), "rb").read()
    pal = open(os.path.join(d, name + "_pal.bin"), "rb").read()
    return [tuple(pal[i * 3:i * 3 + 3]) for i in idx]


def new_rgb(d, name):
    w, h, bpp, rb, gb, bb, ab, rs, gs, bs, as_ = map(int, open(os.path.join(d, name + "_out.txt")).read().split())
    raw = open(os.path.join(d, name + "_out.bin"), "rb").read()
    out = []
    for i in range(w * h):
        v = int.from_bytes(raw[i * bpp:(i + 1) * bpp], sys.byteorder)
        def ch(bits, sh):
            x = (v >> sh) & ((1 << bits) - 1)
            return (x << (8 - bits)) | (x >> (2 * bits - 8)) if bits < 8 else x
        out.append((ch(rb, rs), ch(gb, gs), ch(bb, bs)))
    return out, w


def main():
    base, new = sys.argv[1], sys.argv[2]
    bad = 0
    for f in sorted(os.listdir(base)):
        if not f.endswith("_scaled.bin"):
            continue
        name = f[:-len("_scaled.bin")]
        a = old_rgb(base, name)
        b, w = new_rgb(new, name)
        diff = [i for i in range(min(len(a), len(b))) if a[i] != b[i]]
        rows = sorted(set(i // w for i in diff))
        print("%-20s %6d pixels differ%s" % (name, len(diff), (" rows %d..%d" % (rows[0], rows[-1])) if rows else ""))
        bad += len(diff) > 0
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
```

The palette in `_pal.bin` is 8-bit per channel (`copyCurrentPalette`). Channel expansion in `new_rgb` must match how the backend widened the palette colours. If 32 bpp is used (the usual case), `bits == 8` and there is no expansion.

- [ ] **Step 6: Run the A/B**

```bash
cd ~/work/scummvm
export SCIGAME_EXTRA_INI='disable_dithering=true\nrgb_rendering=true'
python3 harness/i18n/kq1_intro.py $PWD/gamedata/dist-ef8dc87f/kq1-ko $PWD/runs/t5-intro-ko ko
python3 harness/i18n/c1ab.py runs/baseline-4a0f7f0e1c/intro-ko runs/t5-intro-ko
```

Use the worktree binary, as in Task 4. Expected: every frame `0 pixels differ`, exit 0. `korean.uni` in `dist-ef8dc87f/kq1-ko` is 1 bpp (flags 0), so the composite must reproduce the old stamps exactly. If rows differ, dump both as PNGs (`scifb2png.py` for the old side) and look before changing anything. Do not commit until this passes.

- [ ] **Step 7: English is untouched**

```bash
python3 harness/i18n/kq1_intro.py $PWD/gamedata/dist-ef8dc87f/kq1-en $PWD/runs/t5-intro-en
ls runs/t5-intro-en | grep -c _layer.bin   # expect 0
for f in $(cd runs/baseline-4a0f7f0e1c/intro-en && ls *.bin); do cmp -s runs/baseline-4a0f7f0e1c/intro-en/$f runs/t5-intro-en/$f || echo DIFF $f; done
```

Expected: `0` and no `DIFF` (Review Focus 5).

- [ ] **Step 8: Commit (do not merge yet; Task 6 completes the semantics)**

```bash
git add -A engines/sci
git commit -m "SCI: Hi-res glyphs go into the text layer; the re-apply plane goes"
cd ~/work/scummvm && git add harness/i18n/c1ab.py && git commit -m "c1ab: compare the old plane's frames with the compositor's"
```

---

### Task 6: The layer follows the visual plane

**Files:**
- Modify: `engines/sci/graphics/screen.h` (`putPixel`, inline)
- Modify: `engines/sci/graphics/screen.cpp` (`bitsGetDataSize`, `bitsSave`, `bitsRestore`)
- Modify: `harness/i18n/kq1_tour.py` (harness repo): one new dump

**Interfaces:**
- Consumes: `TextLayer::clearLowresPixel`, `saveSize`, `save`, `restore`.
- Produces: the underbits of a `GFX_SCREEN_MASK_VISUAL` save carry the layer. Format: after the existing visual data, if `_textLayer` existed at size time, `TextLayer::save` output (flag + block); if not, a single `0` byte. `bitsRestore` reads it back symmetrically.

- [ ] **Step 1: Pixel writes clear text**

In `putPixel` (the `GFX_SCREEN_MASK_VISUAL` branch, `screen.h`), after `_visualScreen[offset] = color;`:

```cpp
			if (_textLayer && !_textLayer->isEmpty())
				_textLayer->clearLowresPixel(x, y);
```

`screen.h` then needs `#include "sci/graphics/textlayer.h"`. This is the hot path, so it costs nothing when the layer is null or empty.

- [ ] **Step 2: Underbits carry the layer**

`bitsGetDataSize`, inside `if (mask & GFX_SCREEN_MASK_VISUAL)`:

```cpp
		byteCount += _textLayer ? _textLayer->saveSize(rect) : 1;
```

`bitsSave`, at the end of the visual block:

```cpp
		if (_textLayer)
			_textLayer->save(rect, memoryPtr);
		else
			*memoryPtr++ = 0;
```

`bitsRestore`: replace the comment block at the top of the visual branch with a short one saying the layer is restored with the pixels it belongs to. Then at the end of the visual branch:

```cpp
		if (_textLayer)
			_textLayer->restore(rect, memoryPtr);
		else
			memoryPtr++;
```

`bitsSave`/`bitsRestore` take `byte *memoryPtr` / `const byte *memoryPtr` by value, and the existing helpers advance a reference. Follow the same pattern: the layer calls take `byte *&`.

- [ ] **Step 3: Build and test**

```bash
make -j10 && make test 2>&1 | grep -E 'Running cxxtest|OK!|Failed'
```

- [ ] **Step 4: Harness: text survives, windows hide and restore it**

Run the intro A/B again (Task 5 Step 6) and the tour:

```bash
python3 harness/i18n/kq1_intro.py $PWD/gamedata/dist-ef8dc87f/kq1-ko $PWD/runs/t6-intro-ko ko
python3 harness/i18n/c1ab.py runs/baseline-4a0f7f0e1c/intro-ko runs/t6-intro-ko
python3 harness/i18n/kq1_tour.py $PWD/gamedata/dist-ef8dc87f/kq1-ko $PWD/runs/t6-tour-ko ko
python3 harness/i18n/c1ab.py runs/baseline-4a0f7f0e1c/tour-ko runs/t6-tour-ko
```

Expected: 0 pixels differ on all intro frames, and on every tour frame that reached the same game state. `kq1_tour` still loses room 1's first key about 1 run in 3 (the wall-clock tick race, separate work). Retry up to three times and compare only a completed run. If a tour frame differs, find its rows first. The windows-over-text frames (`02b_inventory`, `02c_ring`) are where a Task 6 bug would show.

- [ ] **Step 5: Commit, merge**

```bash
git add engines/sci/graphics/screen.h engines/sci/graphics/screen.cpp
git commit -m "SCI: Underbits and pixel writes carry the text layer, as they carry the visual plane"
cd ~/work/scummvm/i18n && git merge --no-ff wt/c1-compositor -m "Merge wt/c1-compositor: hi-res text through a compositor"
git worktree remove .worktrees/c1-compositor && git branch -d wt/c1-compositor
```

Merge only if Tasks 4–6 checks all passed. The commit messages carry the A/B numbers.

---

### Task 7: 8-bit alpha on screen

**Files:**
- Create: `gamedata/kq1-ko8/`, a variant of `dist-ef8dc87f/kq1-ko` with an 8 bpp `korean.uni` (Task 3 output). Build it with `harness/tools/mkvariant.py` so the other files are links (`GAMEDATA.md`).
- Modify: none in the engine.

- [ ] **Step 1: Build the variant and capture**

```bash
cd ~/work/scummvm
python3 harness/tools/mkvariant.py kq1-ko8 --from dist-ef8dc87f/kq1-ko --add /tmp/ko8.uni
mv gamedata/kq1-ko8/ko8.uni gamedata/kq1-ko8/korean.uni   # if mkvariant keeps the name
python3 harness/i18n/kq1_intro.py $PWD/gamedata/kq1-ko8 $PWD/runs/t7-intro-ko8 ko
```

Check the path conventions of `mkvariant.py` (it may expect names relative to `gamedata/`) before running.

- [ ] **Step 2: Show it**

Convert `runs/t7-intro-ko8/intro_f45_out.bin` to PNG with a few lines of PIL, reusing `c1ab.new_rgb`. Crop the text box (rows 270..360 at 2×) and look at the edges: intermediate tones must appear between glyph and box colours. Count the distinct colours inside the box: 1 bpp gives 2, 8 bpp must give well over 2. Record the number.

- [ ] **Step 3: Record**

Add a short "Measured" section to `docs/i18n/HIRES_COMPOSITOR_DESIGN.md` §5 in the docs repo: the A/B result (0 px), the English invariant, the tour result, and the 8 bpp colour count. Commit in the docs repo.

---

## Out of scope for this plan (later plans, spec §6)

- Scale 3 (build-order step 2).
- The "Oversample Font for I18N" option and driver-selection predicate (step 3).
- `hires_text.map` (step 4).
- Runtime FreeType (step 5).
- SJIS/PC-98 through the layer (step 6). `putKanjiChar` and its `needCJKFix` pre-update stay as they are.
- The event clock for the harness.
- Removing the `needCJKFix` pre-update for non-PC-98 games. With the layer it is redundant but harmless, so measure it separately.
