# Hi-res text: restructuring review synthesis

Two external reviewers (claude, agy) were given the source, the engine call
sites, and the four design defects found this week. Every claim below was
re-checked against the tree before being kept — three were wrong and are
recorded as such.

## Verified findings, by value

### 1. Format-string hole — FIXED (commit 5a552b5efe3)

`hires_text.cpp:237` passed `[latin] bitmap=` from the map file straight to
`Common::String::format`. `expandFontPattern()` exists to prevent exactly
this and the CJK branch used it; the Latin branch did not.

Reproduced before the fix:

| map value | result |
|---|---|
| `lat%s%s%s%s.fnt` | **SIGSEGV** |
| `lat%n.fnt` | **SIGABRT** |
| `100%.fnt` | invalid conversion (benign-looking name) |

After: all three exit cleanly, valid patterns still load. Harness:
`~/games/fmtstr-test.py`.

### 2. Dead code — confirmed, ~600 lines

`HiResTtfGlyphSource` is **never instantiated anywhere**, and the
source-based `HiResGlyphRenderer::drawGlyph` overload has **no caller**
(the only `drawGlyph` calls in the tree are the `(font, index)` overload
plus unrelated engines). Verified with `~/games/check_dead.py`.

Parsed-but-unread config fields, all confirmed to appear only in
`font_map.cpp/.h` (plus tests): `ttfStringMode`, `bitmapGlyphs`,
`translationName`, `scaleFromMap`, `alphaFromMap`, `encodingFromMap`,
`latinTtfPath`, `latinTtfMetrics`, `latinBitmapMetrics`, `heightRoles`,
`kHiResRoleBold`, `kHiResRoleTitle`.

Each dead map key becomes a compatibility promise on merge.

### 3. Encapsulation leaks — confirmed

- `gfx.cpp:718-726` takes `_hiResText.coverage()` as a raw `Surface *` into
  a hand-written blend loop.
- `palette.cpp:1789` and `scumm.cpp:4556` call
  `CursorMan.replaceCursorPalette(_hiResText.paletteRGB(), ...)`.

### 4. Layering — `font_map` is in the wrong directory

It parses an INI and touches no `Graphics::` type. Worse, the dependency
runs backwards: `glyph_renderer.h` includes `font_map.h` only to get
`HiResShadowMode`, which is a rendering concept.

Claude's placement suggestion is the strongest single upstream argument:
`bitmap_font` + `glyph_renderer` + `font_baker` belong in
**`graphics/fonts/`** alongside `bdf.h`, `winfont.h`, `ttf.h` — "a new font
format next to the four existing ones" is a far easier ask than "a new
five-file subsystem directory".

## Reviewer claims that were WRONG

- **agy: "FreeType guards are missing".** `bakeTtfFonts` is already wrapped
  in `#ifdef USE_FREETYPE2` with a real `#else return false`. Settled by
  building: `configure --disable-freetype2 && make -j24` produced a 41 MB
  binary with **0 errors**.
- **agy: `VirtScreen::clearRegion()` calling `_vm->_hiResOverlay`.**
  `VirtScreen` is a `struct` deriving `Graphics::Surface` with **no engine
  pointer**; that code cannot compile. It does already have a `clear()`,
  which is a better hook than the proposal assumed.
- **agy: decorator overriding `drawChar(VirtScreen*, uint16, int, int)`.**
  That signature does not exist. The real interception point is inside
  `printChar(int, bool)`, implemented separately by `CharsetRendererV3` and
  `CharsetRendererClassic`.

## The owner's proposal, assessed

> Stop deciding per-case whether the overlay follows the game. Make the
> `memset` a named `clearFrameBuffer()`-style operation, and use a hook or
> subclass so a drawn character always reaches the overlay.

**Both halves are right in principle, and upstream already agrees** —
`charset.cpp:36` carries a standing TODO saying the charset renderers should
not be touching `_textSurface` and the virtual screens directly.

Measured asymmetry that proves the point: **3 glyph-write sites** versus
**8 raw virtual-screen wipes**, and only 5 overlay clears that do not line
up one-to-one with those 8. That mismatch is exactly the defect class that
produced the room-0 bug.

Corrections to the proposal, from checking the tree:

- The clear primitive should hang off **`VirtScreen`**, which already has
  `clear()` — but `VirtScreen` has no engine pointer, so the overlay hookup
  cannot live inside it as agy wrote. Either pass the overlay in, or keep the
  pairing in a thin `ScummEngine::clearVirtScreen(vs, rect)`.
- The 8 wipe sites are **not all the same event** (room reset, charset-bg
  restore, save/load, GUI). They likely want two primitives, not one.
- The drawing hook must wrap **`printChar`**, not `drawChar`.

Claude dissents on one point worth weighing: do **not** move `_textSurface`
into a layer-owned object, because the game's own `printCharIntern` draws
into it — the fallback path needs it engine-owned. Pull in *compositing* and
*lifetime* responsibility instead, and leave ownership where it is.

## Commit order (merged view, deletions first)

1. ~~format-string fix~~ — **done**, `5a552b5efe3`
2. delete `glyph_source.*`, the unused overload, dead config fields
3. header hygiene: break renderer→parser include, move `HiResShadowMode`,
   `struct`→`class`, doubled include, stranded doc comments
4. config: drop `korean_*` aliases, register keys in the metaengine, gate
   `hires_text_dump_baked`, split logging into one `HiResTextLog` member
5. file moves: `bitmap_font`/`glyph_renderer`/`font_baker` →
   `graphics/fonts/`; `font_map` → `engines/scumm/hires_text/`
6. `resolveGlyph()` shared by `drawChar`/`advanceFor`, `decodeGameChar()`,
   `mergedOverrides()` — with a test asserting measuring and drawing agree
7. shadow mode: pass `HiResShadowMode` from `charset.cpp`, so defect 1 is
   structurally impossible
8. `retireHiResText(vs)` as the sole owner of overlay lifetime — defect 2
9. `composite()` moves the blend loop into the layer; `coverage()` and
   `paletteColor()` go private
10. the `printChar` hook, `setScreenFormat()`, `setBakeCell`/`setLayoutGrid`
    rename, `loadFontSet()`

Steps 1-5 are pure subtraction and placement: a coherent first PR, and the
part that decides whether a reviewer engages at all.

## Keep as-is (both reviewers agreed)

- The decline-and-fall-through contract at all six call sites.
- Baking TTF into the bitmap format at load, so one glyph pipeline exists at
  run time — this is why the no-FreeType build costs nothing.
- `HiResBitmapFont::load` as a self-validating reader with bounds checks.
- The map's qualifier mechanism (opaque strings, no SCUMM naming leaks).
- The per-scope glyph table.
- Per-screen scoping of `clearTextSurface(vs)` — the half of the lifetime
  invariant that was never broken.
