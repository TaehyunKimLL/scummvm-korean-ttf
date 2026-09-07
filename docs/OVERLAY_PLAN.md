# Overlay abstraction — plan

Status: **implemented.** Four commits, measured at each step.

| # | commit | what |
|---|---|---|
| 1 | `307cbd41723` | `HiResOverlay` + 13 tests, no caller |
| 2 | `087538fbfa8` | the index plane's memory moves in; `_textSurface` becomes a reference |
| 3 | `e25d8dcc42b` | the coverage plane moves in; the hi-res layer borrows the overlay |
| 4 | `c4542520f6b` | the GUI saves and restores both planes — the bug this was for |
| 5 | `4fb7670c254` | `clearTextSurface` delegates; the Mac stencil pair gains coverage |

Plus `eaa89c1d211`, which names the FM-Towns transparent value rather than
leaving it a bare `0` at four sites.

### What the audit found

Before folding the clears in, every bare `fillRect(0)` on the text plane was
checked rather than assumed — the Mac mistake had already been made once:

| site | verdict |
|---|---|
| `gfx.cpp:357`, `2537`, `4647` | FM-Towns paths, writing that platform's own key |
| `script_v4.cpp:127`, `script_v5.cpp:2501` | FM-Towns, same |
| `scumm.cpp:4403` | FM-Towns, same |
| `gfx_mac.cpp:137` | Mac stencil: `0` marks the Indy 3 box **present** |
| `gfx_mac.cpp:151` | Mac stencil: `0xFD` marks it **absent** |

None was a bug. What they shared was that none touched coverage, which is why
the Mac pair was the only one that needed changing.

The LOOM wipe in the GUI kept its own rectangle: it is scoped to the main
virtual screen, which can be narrower than the plane, so the band overload
would have cleared too much.

### How step 2 avoided a mass edit

`_textSurface` is read and written at 48 sites across six files. Rewriting
them in the same commit as the ownership change would make a rendering
regression impossible to bisect, so the member became a **reference** to
`_overlay.index()`. Every site compiles and behaves identically; only the
memory moved. Tests: 491/491, and English MI2 frames hash identically across
the change.

### What the round-trip test caught

Reintroducing the old behaviour - saving the index plane alone - fails the
GUI round-trip test in four places. That is the check that the fix in step 4
is real rather than incidental.

Original plan follows.

## Corrections from the compositor work

Three assumptions in the original plan turned out to be wrong. They are
recorded here because they change what steps 3 and 4 can be.

**The transparent key is platform-specific.** `gfx.cpp:1520` clears the plane
to `0` on FM-Towns and to `CHARSET_MASK_TRANSPARENCY` everywhere else, and
`gfx_towns.cpp` never mentions the constant at all. Any `clear()` the overlay
grows has to carry the key, not assume `0xFD`.

**Mac does not store glyphs in the plane.** `CharsetRendererMac::printChar`
draws each glyph twice - into `_textSurface` in colour 0 and into
`_macScreen` in the real colour (`charset.cpp:2019`, `2039`) - and
`mac_drawStripToScreen` writes the *game* pixel wherever the plane reads
transparent. So on Mac the plane is a **stencil**, the inverse of the DOS
arrangement. The `fillRect` calls at `gfx_mac.cpp:137/151` are stencil
maintenance, not the defect the plan claimed.

**The two planes are already correctly paletted.** Indices are what is
stored; colours are resolved per frame. Verified with a forced fade: the
background darkened to 40% while the text kept its own palette entry, in both
the original and the hi-res build. An overlay abstraction must not cache
resolved colours - see `COMPOSITOR_PLAN.md`.

## The problem, stated precisely

The hi-res overlay is two parallel planes:

| plane | owner | format | why |
|---|---|---|---|
| `ScummEngine::_textSurface` | engine | CLUT8 | the game's own `printCharIntern` draws into it, so it cannot move |
| `ScummHiResText::_coverage` | the layer | CLUT8 (8bpp coverage) | antialiasing; absent means stencil |

They must agree on size, lifetime and contents. Today they agree because
someone wrote the calls next to each other:

```cpp
scumm.cpp:518   _textSurface.free();
scumm.cpp:519   _hiResText.freeCoverage();

scumm.cpp:1810  _textSurface.create(w * m, h * m, CLUT8);
scumm.cpp:1815  _hiResText.createCoverage(_textSurface.w, _textSurface.h);
```

Nothing prevents writing one without the other. That is the same defect
shape as the room-0 bug (`babb7a17d43`).

## A real instance of the defect, found while measuring

`gfx_gui.cpp` saves and restores the overlay around the GUI:

```
1436  _tempTextSurface = malloc(_textSurface.pitch * _textSurface.h);
1455  memcpy(_tempTextSurface, _textSurface.getBasePtr(0, 0), ...);   // index only
1481  memset(_textSurface.getBasePtr(0, y), 0xFD, w);                 // index only
1494  memcpy(_textSurface.getBasePtr(0, 0), _tempTextSurface, ...);   // index only
```

**The coverage plane is never saved, cleared or restored here.** After a GUI
open/close with alpha on, coverage describes glyphs the index plane no longer
has. Not yet reproduced on screen — it needs a save/load or options dialog
over live subtitles — but it is the same class as the two bugs already fixed
and should be a test case, not a discovery.

## Measured surface area

- **create**: 2 sites (must stay paired)
- **free**: 3 sites
- **clear**: 5 sites (`gfx.cpp` ×2, `room.cpp`, `saveload.cpp`, `scumm.cpp`)
- **glyph writes**: 3 sites (`charset.cpp` 1019, 1255, 2252)
- **reads**: 16 sites across `gfx.cpp` (8), `gfx_gui.cpp` (3), `gfx_mac.cpp`,
  `gfx_towns.cpp` (2), `charset.cpp`

The 16 reads are the constraint. Most are legitimate consumers of the index
plane (compositing, Mac and Towns paths, the GUI stamp) and must keep
working unchanged.

## Design

One object owns **both planes' lifetime and clearing**. It does **not** own
the pixels' users: the index plane stays reachable, because the fallback
path and four platform paths draw from and read it.

```cpp
// engines/scumm/hires_overlay.h
class HiResOverlay {
public:
	/// Both planes, always the same size. Coverage only when alpha is on.
	void create(int w, int h, bool withCoverage);
	void free();

	/// Retire a band of both planes together. height < 0 means to the bottom.
	void clear(int top = 0, int height = -1);

	/// The plane the game's own renderer draws into. Engine-owned by
	/// necessity: printCharIntern() and the Mac/Towns paths write here.
	Graphics::Surface &index() { return _index; }
	const Graphics::Surface &index() const { return _index; }

	/// Null when alpha is off, which is the signal to key rather than blend.
	Graphics::Surface *coverage() { return _coverage.getPixels() ? &_coverage : nullptr; }

	/// Save/restore both planes as a unit, for the GUI stamp.
	bool saveState();
	void restoreState();

private:
	Graphics::Surface _index;
	Graphics::Surface _coverage;
	byte *_saved;          ///< both planes, one allocation
};
```

Key decisions:

1. **`create`/`free`/`clear` take both planes or neither.** The pairing that
   is currently a convention becomes the only thing callable.
2. **`index()` stays public and mutable.** Hiding it would break the
   fallback invariant. This is deliberately *not* full encapsulation — the
   goal is lifetime safety, not information hiding.
3. **`saveState`/`restoreState` replace the `_tempTextSurface` malloc**, and
   cover coverage, which fixes the `gfx_gui.cpp` gap by construction.
4. **The compositor is not moved in this change.** `gfx.cpp`'s blend loop
   keeps reading both planes. Moving it is a separate step with its own
   risk; bundling them makes the diff unreviewable.

## Commit sequence

Each step builds, passes 470 tests, and keeps the Korean MI2 A/B identical.

1. **Add `HiResOverlay`, hold the existing `_textSurface` inside it.**
   `ScummEngine::_textSurface` becomes a reference or accessor to
   `_overlay.index()`. Pure mechanical rename; no behaviour change. This is
   the big diff (16 read sites) and it is the risky one — do it alone.

2. **Move coverage into it.** `createCoverage`/`freeCoverage`/`clearCoverage`
   leave `ScummHiResText`; the layer asks the engine's overlay for the
   coverage surface when drawing. `create`/`free` become single calls.

3. **Fold `clearTextSurface` into `HiResOverlay::clear`.** The five clear
   sites keep their per-screen band arithmetic — that scoping is correct and
   was never the bug — but can no longer clear one plane alone.

4. **Replace `_tempTextSurface` with `saveState`/`restoreState`.** Fixes the
   GUI/coverage gap. Ship with a test that opens the GUI over drawn text and
   asserts both planes agree afterwards.

Steps 1–3 are behaviour-preserving. Step 4 is a bug fix and should say so.

## What this does NOT do

- Does not move `_textSurface` ownership out of the engine (would break the
  fallback).
- Does not touch the compositor, the charset renderers, or the drawing hook.
- Does not address the 8 raw `memset(screenBuf, ...)` wipe sites — that is
  the separate "one entry point for wipes" change, and it should come after
  this one, because it will want to call `_overlay.clear()`.

## Risk

Step 1 touches 16 read sites across five files, including the FM-Towns and
Mac paths that cannot be tested here. Mitigation: keep the accessor name and
type identical so those sites change by one token, and diff the generated
assembly for `gfx_towns.o`/`gfx_mac.o` before and after — unchanged output
proves the rename was mechanical.
