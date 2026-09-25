# The hires text plane — why Korean text stopped vanishing under actors

Status: **implemented** in `c7106971bd` on `i18n`. Code:
`engines/sci/graphics/screen.{h,cpp}` (`_hiresTextPlane`,
`rememberHiresGlyph`, `restoreHiresTextPlane`, `clearHiresTextPlane`),
invalidation in `graphics/ports.cpp` and `graphics/paint16.cpp`.
Two follow-ups in the same area: `9f1b59448d` (status line) and
`30eaf5eab3` (single-byte glyphs in a double-byte box).

`[source]` = read in code. `[measured]` = observed by running something.
`[unmeasured]` = a claim this document has not yet earned.

## The defect

Double-byte text in SCI — the legacy `korean.fnt` and `SJIS.FNT` faces and
the SCVMUNI Unicode face alike — does not go through the lowres frame
buffer. (The fix below covers the Korean and SCVMUNI faces, not SJIS; see
§"Not covered".) `[source]` It is rasterised into a 16×16 scratch glyph and handed to
the upscaled driver's `drawTextFontGlyph()`, which writes it straight into
the driver's own 2× bitmap. That is how a 16-pixel hangul fits in an
8-pixel lowres cell.

Nothing the engine owns remembered those pixels. The next lowres update
covering the same area is scaled 2× into the same bitmap and overwrites
them. In a game, the usual such update is an actor walking past the text
box.

`[measured]` With GDB on the driver's bitmap (`harness/i18n/scifbdump.sh`),
KQ1's intro box, frames counted from the box being drawn, black pixels in
its second text row:

```
                           frame 1   frame 60
SCVMUNI face                  2242       1352
legacy korean.fnt face        2048       1334
```

The closing words disappeared syllable by syllable, right to left,
following the actor's dirty rect.

This is what PC-98 games never had to solve. Their text lived in a separate
text-mode layer the graphics could not touch; `doubleByteMode` exists
because ScummVM does not emulate that layer (`DESIGN.md`, §"The font set").
The plane is the missing layer, reduced to the one property that mattered:
text survives the graphics under it.

## The mechanism

```
hires glyph draw                     lowres update (any)
putHiresGlyphPersistent()            GfxScreen::displayRect()
   │                                    │
   ├─► rememberHiresGlyph()             ├─► blit lowres rect, 2x, to driver
   │     write into _hiresTextPlane     │     (overwrites glyphs there)
   │                                    │
   └─► driver->drawTextFontGlyph()      └─► restoreHiresTextPlane(rect)
                                              re-blit the plane's set pixels
```

- **The plane.** One byte per hires pixel, `2·width × 2·height` of the
  display, `0xff` = no glyph (the driver's own convention for an unset
  pixel). Allocated on the first hires glyph, so a game that never draws
  one never pays for it.
- **Write.** The SCVMUNI face (`fontunicode.cpp:216`) and the legacy
  Korean face (`GfxScreen::putHangulChar()`, `screen.cpp:515`) draw through
  `putHiresGlyphPersistent()`, which records the glyph in the plane and then
  draws it. The legacy SJIS face does **not**; see §"Not covered".
- **Re-apply.** `displayRect()` is the one funnel every lowres update
  passes through, so the plane is re-applied there, after the blit, over
  the same rectangle. The animation loop, `kGraph` redraws and window
  disposal all go through it, so none needs its own hook. The re-blit
  sends runs of set pixels, row by row, because a plane row is mostly
  `0xff` and the driver call has per-call overhead.

`[measured]` With the plane: 2242 → 2318 black pixels over the same 60
frames (SCVMUNI), 2048 → 2064 (legacy face).

## Where the plane is cleared — the part that decided whether it worked

The plane must forget a glyph exactly when the text it belongs to goes
away, and not before. `[measured]` The obvious places were wrong:

- `GfxScreen::bitsRestore()` and `GfxPaint16::fillRect()` look like "the
  area was repainted". They are also the animation loop erasing and
  restoring each actor's cel every frame. Clearing there wiped the glyphs
  of a box the actor merely walked past: 576 clears in one intro, text
  still draining.

The text's lifetime is the window's lifetime. The plane is cleared:

| When | Where | Why there |
|---|---|---|
| a window is disposed | `GfxPorts::removeWindow()` (`ports.cpp:540`), over the window's `restoreRect` | the text belonged to that window |
| a new picture replaces the screen | `GfxPaint16::kernelDrawPicture()` (`paint16.cpp:101`), when not `addToFlag` | `[measured]` without it, four title-menu lines were painted back over the first room |
| a game is restored | `GfxScreen::clearForRestoreGame()` | the screen is reset wholesale |

**The clear reaches one glyph cell past the rect.** `[measured]` A window
is sized from the font's lowres height (12 rows for KQ1), while a hires
glyph cell is 16 hires rows = 8 lowres, and the last line starts near the
bottom edge. After the intro window was disposed, hires rows 314–316 — three
rows under its `restoreRect` — still held 218 glyph pixels and were painted
back over the scene. `clearHiresTextPlane(rect)` therefore widens the rect
by `kHiresGlyphCellSize` (16) on every side. A neighbouring box's glyphs
that fall in the margin are drawn again by that box's own next redraw.
`[unmeasured]` whether any game redraws a neighbouring box late enough for
that to be visible.

## Not covered: the legacy SJIS face

`[source]` `GfxScreen::putKanjiChar()` (`screen.cpp:637`), the path for
`SJIS.FNT` and the PC-98/FM-Towns ROM fonts, still calls
`drawTextFontGlyph()` directly. Its glyphs never enter the plane, so a
Japanese release drawn through the legacy face should drain under a passing
actor the same way Korean did. `[unmeasured]` No Japanese game was run
against this commit.

It is not a one-line switch. The PC-98 drivers align hires glyphs
themselves (QFG to 4-pixel lowres boundaries, PQ2 to text-mode columns and
rows; see the comment above `putKanjiChar`), while the plane records at
`kHiresTextAlignX = 1`. Remembering a kanji glyph at the unaligned position
would re-apply it a few pixels off from where the driver drew it. Covering
this face means taking the alignment from the driver, not assuming it.

A Japanese game drawn through a SCVMUNI font set *is* covered, because that
face goes through `putHiresGlyphPersistent()`.

## Invariants

- **A game that draws no hires glyph is untouched.** The plane is never
  allocated; every hook starts with a null check. `[measured]` English KQ1:
  lowres frame buffer bit-identical at frames 1, 40 and 105 of the intro
  box.
- **The Korean LB1 fan patch** (cp949, legacy face) unchanged. `[measured]`
- The scale is fixed at 2 (`_hiresScaleX/_hiresScaleY`), because every
  driver that can draw a hires glyph is `UpscaledGfxDriver`, which doubles
  both axes. A driver with another scale would need the plane sized from
  it. `[source]`

## The two fixes that came with it

**Status line (`9f1b59448d`).** `GfxText16::DrawStatus()` drew one glyph
per byte. With UTF-8 in the heap, a hangul syllable is three bytes and came
out as three wrong glyphs. `[measured]` KQ1's menu title was mojibake in
the status line while `Draw()`, which already used `readChar()`, drew the
same text correctly. It now walks by `readChar()`; a one-byte character
takes the path it always did.

**ASCII in a double-byte box (`30eaf5eab3`).** In the hires paths, double-
byte glyphs go to the driver and single-byte ones into the lowres buffer,
where only a `bitsShow` puts them on screen. `GfxText16::Box()` skipped
that show in double-byte mode. That was right for the PC-98 interpreter,
whose ASCII also went to video memory, and it left every ASCII run in a
Korean window unshown. `[measured]` KQ1's reply to an unknown word: the
lowres buffer held `xyzzy`, the screen showed a gap exactly its width. The
show now happens in both modes. The plane re-applies the hires glyphs the
show's blit passes over, so nothing is lost the other way.

## Relation to the SCUMM overlay

SCUMM's hi-res text keeps its own planes (`engines/scumm/hires_overlay.*`),
owned by the engine and composited per frame. This one is smaller: one
plane, owned by `GfxScreen`, re-applied rather than composited. B0
(`BIGBANG_PLAN.md` §3.1) measured the two surfaces as disagreeing on all
four properties a shared class would need. The plane does not change that
verdict; it adds the one piece of memory SCI was missing, where SCI already
funnels its updates.
