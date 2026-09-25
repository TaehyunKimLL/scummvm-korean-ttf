# Where Japanese text lived: PC-98 and FM-Towns, the originals and ScummVM

Written 2026-09-26 against `i18n` at `40fe861924`. Question it answers: is
our hires text plane (`TEXT_PLANE.md`) the same thing the Japanese
hardware did, and may the legacy SJIS path (`GfxScreen::putKanjiChar`) go
through it?

`[source]` = read in the checkout (file:line). `[external]` = a cited web
source. `[inference]` = reasoned, not observed. `[unmeasured]` = nobody ran
it. No Japanese game was run for this document.

## Short answer

| Release | Where the original drew kanji | Graphics could erase it? | ScummVM upstream | Our plane would be |
|---|---|---|---|---|
| **PQ2 PC-98** (SCI0) | PC-98 **text VRAM**, a separate layer shown over graphics | **no** | glyph in the driver's 2× bitmap; erasable | **faithful** (a separate layer) |
| **QFG1 PC-98** (SCI01) | copied into the 4 **graphics** planes, inverted | yes | same as upstream PQ2 | *more* persistent than the original |
| **KQ5 / SQ4 PC-98** (SCI1) | driver opcode through the **GRCG** into graphics VRAM | yes | same; SCI1 "special" glyph renderer | more persistent than the original, and currently **crashes** the restore (below) |
| **KQ5 / Mother Goose FM-Towns** | undetermined | undetermined | no Towns driver; a PC-98 font | undetermined |

The PC-98 has a separate text layer. Only PQ2 used it. ScummVM emulates
the layer for no game.

## 1. The hardware

**PC-98.** Two µPD7220 display controllers, one for text and one for
graphics, each with its own memory, running in parallel so text overlays
graphics `[external]`
<https://scalibq.wordpress.com/2023/01/07/when-is-a-pc-not-a-pc-the-pc-98/>.
Graphics are four bit-planes; text VRAM holds character codes (JIS pairs
for kanji, drawn from the font ROM by the text GDC) plus attribute bytes:
3-bit colour, reverse, blink, underline, a "secret" hide bit `[external]`
<https://people.freebsd.org/~kato/pc98-arch.html>,
<https://note.com/kazushinakamura/n/n5859acc5d34d>.

Text is always shown **on top** of graphics. None of the sources above
states the priority in so many words. Upstream ScummVM does, from
emulator observation: *"the text mode layer is always displayed on top of
the graphics layer, so it can never get corrupted by graphics updates
(with an emulator you can see how even the mouse cursor is drawn under the
Japanese text)"* `[source]` `text16.cpp:645-648`.

So the user's model holds for the PC-98: **two layers, composited at
output; rewriting graphics cannot touch text.**

**FM-Towns.** No separate character memory is described. The hardware has
up to two overlaid graphics layers (two bitmaps, or sprites over a bitmap),
and modes can be mixed, e.g. a 320×200 32k-colour layer under a 640×480
16-colour layer, *"which allowed games to combine high-colour graphics with
high-resolution kanji text"* `[external]`
<https://handwiki.org/wiki/Engineering:FM_Towns>. The kanji come from a
font ROM.

So the Towns *can* keep text on its own layer, but that layer is a second
graphics layer, not a text mode. ScummVM's SCUMM engine emulates exactly
that: layer 0 graphics, layer 1 a 16-colour text layer at 2×, composited in
`TownsScreen::update` `[source]` `engines/scumm/scumm.cpp:2051-2052`,
`engines/scumm/gfx_towns.cpp:613`. Whether the Towns **SCI** interpreters
put kanji on the second layer is **undetermined**. No source found, and no
disassembly.

## 2. What each Sierra PC-98 interpreter did

From upstream's comment above `putKanjiChar` `[source]`
`screen.cpp:644-662`:

- **QFG (SCI0/SCI01).** Glyph data XORed with 0xff and copied into all four
  graphics planes: black on white, x divided by 4 with no bit shift, so
  text sits on byte boundaries (4 lowres pixels).
- **PQ2 (SCI0).** Text mode. Positions are text columns and rows, so x
  loses `& ~3` and y `& ~7` of precision (lowres).
- **SCI1 (KQ5, SQ4).** A gfx-driver opcode renders through the GRCG. In
  the 16-colour drivers the first and last 5 glyph rows are doubled
  horizontally ("fat"), the middle 6 drawn normally.

Which survive an actor walking over the text:

- PQ2: **survives**. Graphics cannot write text VRAM; text goes when the
  interpreter clears it. `[source]` + `[inference]`
- QFG and SCI1: **does not survive by itself**. The glyphs are in graphics
  VRAM but not in the interpreter's lowres visual buffer, so a redraw of
  that rect from the buffer overwrites them. Upstream implies as much when
  it skips the show for SJIS lines because those glyphs *"get rendered
  directly into the video memory"* `[source]` `text16.cpp:705-708`.
  `[inference]` Whether any of these games animates under text is
  `[unmeasured]`.

## 3. What ScummVM does today (upstream code)

**Driver per release** `[source]` `drivers/init.cpp`:

| Release | Row | Driver, config |
|---|---|---|
| PQ2 PC-98 | `:89` | `PC98Gfx16Colors`, 2 (text-mode style) |
| SCI01 PC-98 (QFG) | `:90` | `PC98Gfx16Colors`, 0 |
| SCI1 PC-98 (KQ5, SQ4) | `:91` | `PC98Gfx16Colors`, 1 (SCI1 style) |
| any of the above, render mode `pc98_8c` | `:84-86` | 8-colour variants |
| FM-Towns | **none** | falls to `GfxDefault` upstream |

All PC-98 drivers subclass `UpscaledGfxDriver`: fixed 640×400, and
`_scaledBitmap` is the only bitmap they keep `[source]`
`upscaled.cpp:30-32, 67`.

**Where kanji pixels land.** `putKanjiChar()` → `drawTextFontGlyph()` →
rendered straight into `_scaledBitmap`, x aligned with
`&= ~(_textAlignX - 1)` `[source]` `upscaled.cpp:151-157`, through a
per-style renderer:

- `renderPC98GlyphFat`: text-mode style (`pc98_16col.cpp:148`).
- `renderPC98GlyphSpecial`: SCI1 style, which begins
  `assert(h == 16)` (`pc98_16col.cpp:107-108`, selected at `:153`).

**Alignment.** 8 hires pixels for QFG and PQ2, 1 for SCI1
(`pc98_16col.cpp:236-245`, `pc98_8col_sci1.cpp:110`), and
`GfxFontSjis::draw` masks `left & 0xFFC` (`fontsjis.cpp:77`). **The y row
snap (`& ~7`) in the comment is not implemented anywhere.** `[source]`

**Colour.** QFG and SCI1 `remapTextColor()` always return 0 (black). PQ2
reproduces the original's red/green bit bug, uses blue for colour 0, and
maps into slots 0x10+, text-mode colours outside the game palette
`[source]` `pc98_16col.cpp:185-219`, `pc98_8col_sci0.cpp:128-150`.

**No SCI driver keeps a text layer.** Any lowres `copyRectToScreen`
re-renders its rect into `_scaledBitmap` (`upscaled.cpp:98-118, 191-196`)
and overwrites glyphs there. Upstream says so: *"we also need to prevent
graphics updates for SJIS lines, since we don't emulate the PC-9801 text
mode layer"* `[source]` `text16.cpp:647-649`. Its two mitigations are
skipping the show for double-byte lines, and a `bitsShow` before the text
in `kDisplay`. Nothing covers animation. So **upstream already loses PQ2's
kanji to a passing actor**, which the original never did, if PQ2 ever
animates under text. `[inference]`, `[unmeasured]`.

**FM-Towns.** Upstream has no SCI Towns graphics driver. `GfxFontSjis`
always loads the PC-98 font (`Graphics::FontSJIS::createFont(kPlatformPC98)`,
`fontsjis.cpp:38`), never the Towns ROM, and its constructor errors unless
the screen is upscaled or the driver renders text itself
(`fontsjis.cpp:35-36`). Since `9dc71ef701` (2024-08-06), a Japanese Towns
release gets `GfxDefault`, so upstream Towns KQ5 would abort on its first
switch to font 900. `[source]` + `[inference]`, not run. `FMT_FNT.ROM` is
read only by our `dump_towns_font` tool (`sci.cpp:344`).

## 4. Our text plane against these models

**Same as PC-98 text mode.** A separate store that graphics updates cannot
destroy. Its lifetime roughly matches the interpreter clearing text VRAM:
cleared at window disposal (`ports.cpp:540`), new picture
(`paint16.cpp:101`), restore (`screen.cpp:250`).

**Different:**

| | PC-98 text mode | our plane |
|---|---|---|
| composited | at output, every frame, by hardware | re-blitted into the same bitmap after each `displayRect()` (`screen.cpp:227-237`) |
| on top of | everything, **including the cursor** | only what goes through `displayRect()`; the cursor is on top of the text |
| owned by | the text GDC | `GfxScreen`, not the driver |
| position grid | text columns and rows | any hires pixel (`kHiresTextAlignX = 1`, `screen.h:306`) |
| colour | attribute byte, own palette | a stored index, already remapped; PQ2's 0x10+ colours survive, later palette changes are not re-applied |

So the plane is closer to the PC-98 than upstream is, but it is a
re-apply, not a compositor. The faithful shape would be SCUMM's Towns
shape: the driver keeps the text layer and composites it at output.

## 5. Routing `putKanjiChar` through the plane as it stands would break

`[source]` + `[inference]`:

1. **SCI1 PC-98 crashes.** `restoreHiresTextPlane()` replays the plane in
   one-row runs (`drawTextFontGlyph(..., rowW, 1, ...)`, `screen.cpp:630`).
   On an SCI1 PC-98 16-colour driver that reaches
   `renderPC98GlyphSpecial` → `assert(h == 16)`. **This is already
   reachable today** without touching `putKanjiChar`: a SCVMUNI font on an
   SCI1 PC-98 release sends its glyphs through `putHiresGlyphPersistent()`,
   and the first restore asserts. `[unmeasured]`
2. **Text-mode alignment shifts restored pixels.** With `_textAlignX = 8`
   the driver re-aligns each run's start (`x0 &= ~7`), moving restored
   pixels left of where they were drawn.
3. **The fat renderer runs twice.** The plane stores the raw glyph; the
   replay feeds it through the per-style renderer again. Stored pixels
   should be *post-render*, and replayed with a plain copy that bypasses
   the style.

All three share a cause: the plane replays through `drawTextFontGlyph()`,
which is a *glyph* renderer with per-platform styling, not a pixel copy.

## 6. What to do, in order

1. **Give the driver a raw-pixel entry point** for the replay (copy
   `0xff`-keyed pixels into `_scaledBitmap`, no alignment, no style), and
   make `restoreHiresTextPlane()` use it. Remember post-render pixels in
   the driver, not pre-render in `GfxScreen`. This fixes §5.1–3, including
   the crash the SCVMUNI path already has on SCI1 PC-98.
2. **Then decide per release whether kanji persist.** PQ2: yes, that is
   the original. QFG, KQ5 and SQ4: the original could lose text to
   graphics, so persisting is a deviation. It is harmless unless a game
   *relies* on graphics erasing text, and that is `[unmeasured]`. Measure
   before routing them.
3. **Longer term: composite at output.** Move the plane into
   `UpscaledGfxDriver` as a layer composited when the frame is presented,
   the way SCUMM's `TownsScreen` does. That gives "text over cursor" for
   PQ2 and removes the per-blit re-apply. It is a driver change upstream
   would review on its own.
4. **FM-Towns** needs its own card: which layer the Towns interpreters used
   (disassembly or an emulator), whether `JA_JPN` → `UpscaledGfx`
   (`init.cpp:102`, our `53d8f705c9`) is right for Towns releases, and the
   Towns ROM as a font source.

## Corrections this makes elsewhere

- `drivers/init.cpp:96-101` (our comment, `53d8f705c9`) says *"the PC98
  and FM-TOWNS entries above still win"*. There are no FM-Towns entries.
  The `JA_JPN` row is `kPlatformUnknown`, so Towns KQ5 and Mixed-Up Mother
  Goose now get `UpscaledGfx` where upstream gives `GfxDefault`. That is an
  untested behaviour change.
- `TEXT_PLANE.md` said `putKanjiChar` serves "the PC-98/FM-Towns ROM
  fonts". It serves the PC-98 font only.
- `screen.cpp:653`'s description of PQ2's `& ~7` y snap is not implemented
  in any driver.
