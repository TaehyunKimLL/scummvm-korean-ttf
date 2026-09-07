# Compositor abstraction — plan

Status: **plan only.** Measured against `92501d05d15` with
`~/games/branch_diff.py` and `~/games/platform_gate.py`.

## Requirement

> 32비트 서피스 쓰는 부분을 추상화. 8bit 소스를 메소드를 통해 surface에 쓰면,
> 소스측은 타겟이 무엇인지 몰라도 동작해야 한다.

Source side: an 8-bit index plane plus an 8-bit coverage plane. Destination
side: whatever the platform ended up with. The source must not branch on it.

## What the measurement shows

`drawStripToScreen` has three composite branches. They differ **only in the
destination write**; the decision logic is identical:

| branch | line | decision | write |
|---|---|---|---|
| blended | 718 | transparent → bg; a==0/0xFF → fg; else mix | `*dstPtr++ = uint32` |
| CLUT8 scaled | 783 | transparent → bg; else fg | `*dstPtr++ = byte` |
| 16bpp | 802 | transparent → bg; else fg | `WRITE_UINT16` |

Reads across the section: game buffer 6, text plane 3, coverage 1,
palette 4 — one source shape, three sinks. That is exactly the shape an
abstraction fits.

The two platform compositors do **not** participate today:

| | reads coverage | uses paletteColor | checks alphaActive | real destination |
|---|---|---|---|---|
| `gfx.cpp` | yes | yes | yes | backend, 8/16/32bpp |
| `gfx_towns.cpp` | **no** | **no** | **no** | hardware layer 1, paletted |
| `gfx_mac.cpp` | **no** | **no** | **no** | `_macScreen`, CLUT8 |

So Mac and FM-Towns are not refused by a platform check — `scumm.cpp:1574`
gates alpha only on `version < 7`. They simply have no code that consumes
coverage. That is what this abstraction closes.

## Design

A sink interface that hides the destination format. One virtual call **per
span**, never per pixel.

```cpp
// engines/scumm/hires_sink.h
/**
 * Where composited pixels go.
 *
 * The source works in the game's own 8-bit indices plus 8-bit coverage. What
 * those become - a palette index, a 16-bit entry, a blended 32-bit colour -
 * is the sink's business, so the compositing rule is written once.
 */
class HiResSink {
public:
	virtual ~HiResSink() {}

	/// One run of background, no text over it.
	virtual void writeBackground(const byte *indices, int count) = 0;

	/// One run of text at full coverage.
	virtual void writeOpaque(const byte *indices, int count) = 0;

	/// One run of text partially covering the background beneath it.
	/// A sink that cannot blend rounds to whichever side it can render.
	virtual void writeBlended(const byte *fg, const byte *bg,
							  const byte *coverage, int count) = 0;
};
```

Three implementations, each holding only what its format needs:

- `HiResIndexSink` — writes bytes; `writeBlended` picks `coverage >= 128 ?
  fg : bg`, which is what a paletted destination can honestly do.
- `HiResPalette16Sink` — `_16BitPalette` lookup.
- `HiResTrueColorSink` — the current blend arithmetic.

The compositor keeps the decision logic and stops knowing the format:

```cpp
for (int w = 0; w < width * m; ++w) {
    const byte t = textRow[w];
    const byte a = covRow ? covRow[w] : 0;
    if (t == CHARSET_MASK_TRANSPARENCY || (t == 0 && a == 0))  bg run
    else if (!covRow || a == 0 || a == 0xFF)                   opaque run
    else                                                       blended run
}
```

Runs are accumulated and flushed, so the virtual call is amortised over a
span rather than paid per pixel.

## What this buys on Mac and FM-Towns

Both compositors get a sink instead of a hand-written inner loop:

- `gfx_mac.cpp` → `HiResIndexSink` over `_macScreen` (CLUT8).
- `gfx_towns.cpp` → `HiResIndexSink` over layer 1, `HiResPalette16Sink`
  when `_outputPixelFormat.bytesPerPixel == 2`.

They then consume coverage for the first time. Note honestly what that does
and does not give:

- **Hi-res glyphs: yes.** Both already run `_textSurfaceMultiplier = 2` and
  `_textSurface` is created at that size, so the pixels are already there.
- **True antialiasing: no, not on a paletted destination.** `writeBlended`
  can only threshold. Getting real blending needs `_macScreen` and the Towns
  layer promoted to 32bpp, which is a separate and much larger change.

This is worth stating in the commit message, because "Mac now supports
alpha" would be false.

## Invariant: the planes hold indices, never colours

Verified by measurement, and every sink must preserve it.

The overlay stores **palette indices** (`_textSurface`, CLUT8) and **alpha**
(`_coverage`, 8bpp). A 32-bit colour exists only for the duration of one
composite; nothing keeps it. `palette.cpp:1785` refreshes the index→colour
cache on every palette change, so a palette-only edit recolours text that was
drawn long before.

Proof: the same scene captured across a room fade.

| frame | background | text ink |
|---|---|---|
| 1 | `(128, 0, 176)` | `(195, 0, 0)` |
| 2 | `(59, 31, 70)` **faded** | `(195, 0, 0)` **unchanged** |

The background darkened while the glyphs kept their own palette entry. Had
the blend been baked to 32-bit at draw time there would be no original to
recompute from, and the text would have faded with it - or frozen.

This is why the sink interface takes **indices, not colours**:

```cpp
virtual void writeBlended(const byte *fg,        // palette indices
                          const byte *bg,        // palette indices
                          const byte *coverage,  // alpha
                          int count) = 0;
```

Each sink resolves indices through the palette itself, per frame. The same
holds for the FM-Towns work: promoting layer 1 to 16-bit changes the
*layer's pixel buffer*, while `_textSurface` stays CLUT8 and is converted
through `_16BitPalette` every frame.

A sink that cached resolved colours across frames would break this, and no
existing test would catch it - so the sink tests must include a
palette-change case.

## Mac: the plan was wrong

Measured after step 2, and it invalidates what steps 3-4 assumed.

I had Mac down as "like DOS, but writes to `_textSurface` in two places".
The data flow is actually **inverted**:

- `CharsetRendererMac::printChar` draws each glyph **twice** - once into
  `_textSurface` (always colour 0) and once into `_macScreen` (the real
  colour), at `charset.cpp:2019` and `2039`.
- `mac_drawStripToScreen` then writes the **game** pixel wherever the text
  plane reads `CHARSET_MASK_TRANSPARENCY`, and leaves `_macScreen` untouched
  elsewhere.

So on Mac `_textSurface` is a **stencil**, not a glyph store: it says "text
lives here", while the glyph pixels are already in `_macScreen`. The DOS path
is the opposite - there `_textSurface` *holds* the indices.

Consequences:

1. **A sink does not fit `mac_drawStripToScreen` as it stands.** The sink
   interface takes fg indices from the text plane; on Mac that plane has no
   colours in it. Passing it would write colour 0 everywhere there is text.

2. **Mac already renders text at 2x.** `_macScreen` is 640x480 CLUT8 and
   glyphs are drawn into it directly with a Mac font, one game pixel to a
   2x2 block. It is a hi-res text path that predates this one, with its own
   shadow handling (`charset.cpp:2001-2015`) and its own b/w dithering.

3. The `fillRect` calls I flagged at `gfx_mac.cpp:137/151` are stencil
   maintenance, not glyph drawing - they mark the Indy 3 text box present or
   absent. They still need a coverage counterpart if coverage ever becomes
   live on this path, but they are not the defect I described.

What Mac would actually gain from this work is **antialiasing** and
**replacement fonts**, not scale. Both require the glyph pixels to come from
the hi-res renderer instead of `_font->drawChar`, i.e. changing
`CharsetRendererMac::printChar`, not the compositor.

That is a larger and riskier change than steps 1-2, on a platform I cannot
test visually. Not attempted here; recorded so the next attempt starts from
the real data flow.

## FM-Towns: three coupled changes, and one of them is hardware emulation

Measured before attempting step 4.

Earlier I promoted layer 1 to 32767 colours, saw no change, and blamed the
`memcpy` in `towns_drawStripToScreen`. That was only half the story.

`transferRect` (`gfx_towns.cpp:643`) composites the two layers, and the
transparency rule lives inside it:

```cpp
if (sizeof(srcPixelType) == 1) {
    if (col || l->onBottom) { ... }   // index 0 is see-through
} else {
    *dst10a++ = col;                  // no test at all
}
```

An 8-bit source layer treats index 0 as transparent. A **16-bit source layer
has no transparency test** - every one of the four `uint16` instantiations
writes every pixel. A 16-bit text layer would therefore paint its whole
rectangle over the game picture, blanking it wherever no text was drawn.

So promoting the text layer needs three coupled changes:

1. `setupLayer(1, ..., 32767)` - the layer's bpp
2. the `memcpy` in `towns_drawStripToScreen` → `HiResPalette16Sink`
3. `transferRect`'s 16-bit path - a transparency key

(3) is the problem. That path is shared with **layer 0**, which is 16-bit in
exactly the output mode this would enable, and layer 0 must keep writing
every pixel. It cannot simply gain a key; it needs a per-layer flag, and the
flag changes an emulation of how the real FM-Towns hardware combined its
planes.

### What is actually available

The measurement that started this - FM-Towns showing 4 colours where DOS
showed 432 - has a simpler explanation than "the text layer is 8-bit":
`gfx.cpp:705` returns to `towns_drawStripToScreen` **before** the blended
path is ever reached. FM-Towns text is composited by code that predates the
hi-res layer and never consumes coverage.

Two honest options:

- **Solid hi-res text on FM-Towns**: let the Towns path use the text plane's
  indices through `HiResIndexSink`. Replacement fonts and shapes, no
  antialiasing. Needs (2) only, no hardware-emulation change.
- **Blended text on FM-Towns**: needs (1)+(2)+(3), including the per-layer
  transparency flag.

The first is worth doing and is a small change. The second should not be
attempted without an FM-Towns owner able to check that the dual-layer
emulation still matches the hardware - which I cannot do headless.

## Commit sequence

1. **Add `HiResSink` and the three implementations, with unit tests.** No
   caller yet. Tests assert each sink reproduces the byte-exact output the
   corresponding branch produces today.
2. **Rewrite `gfx.cpp`'s three branches to use sinks.** Behaviour must be
   bit-identical — verify by A/B capture, not by reading. This is the risky
   step and it is where a regression would hide.
3. **`gfx_mac.cpp` uses a sink.** First platform to gain hi-res text.
4. **`gfx_towns.cpp` uses a sink.** Second.
5. **Drop the 'this platform already scales text' warning** once 3 and 4
   prove the scale is honoured, and update the comment at `scumm.cpp:1296`
   which currently says lifting this needs the Towns path reworked — it
   will have been.

Steps 1-2 are behaviour-preserving. 3-5 are the feature.

## Measure before step 3

I have not yet verified that hi-res text is merely *unblended* on Mac/Towns
rather than *broken*. Before touching either compositor, run each with a map
at `scale=2` and capture: the game data is on disk (`mi1towns`, `mi2towns`,
`indy4towns`, `mi1segacd`), all English, so Latin fonts must be baked first
with `bake-mi2-en.py` as the template.

If they already draw hi-res glyphs unblended, steps 3-4 are smaller than
described and the warning at `scumm.cpp:1310` is simply wrong.

## Risk

Step 2 rewrites the loop that took three sessions to get right (the room-0
bug, the black-on-black bug). Mitigations: sinks land with tests first;
the A/B is the existing `check-mi2-saves-hr.py` plus `mi2-en-test.py`; and
the per-span flush keeps the pixel loop shape unchanged so the diff is
readable.
