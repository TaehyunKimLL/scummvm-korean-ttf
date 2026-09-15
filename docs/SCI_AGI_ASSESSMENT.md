# SCI and AGI: does the SCUMM hi-res text work transfer?

Read at `59db2f40` (branch `hires-text`), 2026-09-15. Static reading of the
engines plus the shape of the SCUMM layer as built. **No runtime measurement
was done in either engine** — everything below is source reachability, and
line numbers are only valid at this commit.

Short answer: **SCI needs almost none of it and AGI cannot use any of it.**
For opposite reasons, and both reasons are structural rather than a matter of
effort.

---

## Why the question is not "port the layer"

The SCUMM work is three separable things, and the engines want different
subsets:

| piece | what it is | engine-independent? |
|---|---|---|
| `graphics/hires_text/` | font map reader, SVFN bitmap format, glyph renderer, TTF baker | **yes** — already lives outside `engines/` |
| the hooks | `drawChar()` offered at each charset renderer | no, SCUMM-shaped |
| the composite | scaled `_textSurface`, sinks per output format, overlay planes | no, and this is the bulk of it |

A port is not "move the layer"; it is "decide which of the three the target
engine is missing". SCI is missing only the first. AGI is missing something
more basic than all three.

---

## SCI

### It already has the architecture SCUMM had to build

The single hardest thing in the SCUMM work was getting a scaled text surface
composited over an unscaled game picture. **SCI has had that since PC-98
support.** `GfxScreen` carries an upscaled display screen and a coordinate
mapping:

```
engines/sci/graphics/screen.h:44-46
    GFX_SCREEN_UPSCALED_DISABLED = 0,
    GFX_SCREEN_UPSCALED_480x300  = 1,
    GFX_SCREEN_UPSCALED_640x400  = 2
engines/sci/graphics/screen.h:244-245
    _upscaledHeightMapping[], _upscaledWidthMapping[]
```

and the hi-res glyph path writes straight into it, taking low-res caller
coordinates and shifting them itself:

```cpp
// screen.cpp:477 — the comment is the whole design
// We put hires Hangul chars onto upscaled background, so we need to adjust
// coordinates. Caller coordinates are low-res ones.
void GfxScreen::putHangulChar(Graphics::FontKorean *commonFont, int16 x, int16 y, ...)
    _gfxDrv->drawTextFontGlyph(_hiresGlyphBuffer, charWidth, x << 1, y << 1, ...);
```

`putKanjiChar()` (screen.cpp:487) is the same shape for SJIS, `putMacChar()`
(screen.cpp:473) for hi-res Mac fonts. Three hi-res glyph paths already
coexist with the low-res picture.

**So the composite half of the SCUMM work has no SCI counterpart to write.**

### And it already has the hook point

SCI resolves fonts through an abstract class with exactly the method a
replacement layer needs:

```cpp
// scifont.h:37
class GfxFont {
    virtual bool isDoubleByte(uint16 chr);
    virtual byte getCharWidth(uint16 chr);
    virtual void draw(uint16 chr, int16 top, int16 left, byte color, bool greyedOutput);
    virtual void drawToBuffer(...);   // SCI2/2.1
};
```

and selects the implementation in one place:

```cpp
// cache.cpp:68-77
if ((fontId == 1001) && (g_sci->getLanguage() == Common::KO_KOR))
    _cachedFonts[fontId] = new GfxFontKorean(_screen, fontId);
else if ((fontId == 900) && (g_sci->getLanguage() == Common::JA_JPN))
    _cachedFonts[fontId] = new GfxFontSjis(_screen, fontId);
else
    _cachedFonts[fontId] = new GfxFontFromResource(_resMan, _screen, fontId);
```

A replacement font in SCI is **a fourth subclass and one more branch here**.
Not a hook offered at every renderer, not a parallel surface, not a sink per
output format. `GfxFontKorean` (fontkorean.cpp, ~90 lines including licence)
is the template, and it is small because `GfxScreen` does the hard part.

Korean text is already routed into font 1001 automatically by
`SwitchToFont1001OnKorean()` (text16.cpp:735), which sniffs the string.

### What SCI would actually gain

Only the **font source**. `Graphics::FontKorean` (graphics/korfont.h:42) reads
a fixed bitmap format; it has no coverage plane, no per-glyph metrics, no
TrueType baking. Our `graphics/hires_text/` has all three and is already
engine-independent.

Concretely: a `GfxFontHiRes : public GfxFont` that owns a
`Graphics::HiResBitmapFont`, answers `getCharWidth()` from its metrics, and
draws through `GfxScreen::putHangulChar()`'s sibling. The map reader, the
SVFN format, and the naming convention (`hrkor`/`hrjpn`/`hrchs`/`hrcht`)
transfer unchanged because none of them know what SCUMM is.

### What would NOT transfer

- **Every composite fix.** The palette-collision fix (`ab2e0440019`), the sink
  selection, `HiResOverlay`, the scroll-effect magnifier — all of those exist
  because SCUMM composites a `_textSurface` itself. SCI's driver writes the
  glyph into the display screen directly; there is no second plane to keep in
  step and no colour key to collide with.
- **`_2byteShadow` and `resolveShadow()`.** SCI decorations are per-font
  resource data, not a global engine field.
- **The scale policy.** SCUMM's `_textSurfaceMultiplier` has no SCI analogue;
  SCI's upscale is a screen mode (`640x400`), chosen at init, not a text
  multiplier. `hires_text_scale` would be meaningless — the scale is 2 because
  the screen mode says so.

### Unmeasured, and load-bearing if anyone tries this

1. **SCI32 is a different renderer.** `text32.cpp` and `drawToBuffer()` are
   the SCI2/2.1 path and were not read for this note. Do not assume the
   `GfxFont` subclass story holds there.
2. **The `_gfxDrv` indirection.** `putHangulChar` goes through a graphics
   driver (`drawTextFontGlyph`), and the PC-98 drivers do their own scaling —
   `putKanjiChar`'s comment describes SCI1 drivers that scale the first and
   last 5 rows of a glyph but not the middle 6. A replacement font on those
   drivers may be reshaped by the driver. Measure before designing.
3. **`_hiresGlyphBuffer` is 256 bytes** (`memset(..., 0xff, 256)`), which is
   16x16 at 1bpp. An 8bpp coverage glyph does not fit it. That buffer, and
   `drawTextFontGlyph`'s signature, are the real porting boundary.

---

## AGI

### The text grid is the coordinate system

AGI does not merely use a fixed cell — it **measures the screen in cells**:

```cpp
// graphics.cpp:349-356
void GfxMgr::translateFontPosToDisplayScreen(int16 &x, int16 &y) const {
    x *= _displayFontWidth;
    y *= _displayFontHeight;
}
void GfxMgr::translateDisplayPosToFontScreen(int16 &x, int16 &y) const {
    x /= _displayFontWidth;
    y /= _displayFontHeight;
}
```

Scripts address text by column and row; the engine multiplies. Dialog boxes,
menus, the status line and the input line are all laid out in that grid
(`getFontRectForDisplayScreen()`, graphics.cpp:369). A proportional or
larger-celled replacement font does not "look wrong" — it **moves every text
coordinate in the game**, including the ones scripts compare against.

### Its hi-res mode is a font swap, not a scaler

AGI does have a 640x400 mode, and this is the part most likely to mislead:

```cpp
// graphics.cpp:154-164
if (_font->isFontHires() || forceHires) {
    _upscaledHires = DISPLAY_UPSCALED_640x400;
    _displayScreenWidth = 640;  _displayScreenHeight = 400;
    _displayFontWidth = 16;     _displayFontHeight = 16;
```

The condition is `_font->isFontHires()`. The screen is upscaled **because the
font is 16x16**, not the other way round. And the glyph loop reads that size
straight from the font with no scale factor anywhere:

```cpp
// graphics.cpp:1222-1226
bool  fontIsHires = _font->isFontHires();
int16 fontHeight  = fontIsHires ? 16 : FONT_DISPLAY_HEIGHT;
int16 fontWidth   = fontIsHires ? 16 : FONT_DISPLAY_WIDTH;
int16 fontBytesPerCharacter = fontIsHires ? 32 : FONT_BYTES_PER_CHARACTER;
```

So AGI supports exactly two cells, 8x8 and 16x16, hardcoded, 1bpp, and the
mode follows the font. There is no separate text surface and no composite
step: `drawCharacterOnDisplay()` writes pixels into the display screen and
calls `copyDisplayRectToScreen()`.

### There is no CJK support to extend

`grep -i 'korean|hangul|cp949|sjis|cjk' engines/agi/` returns **nothing**.
The font is a single `const uint8 *_fontData` indexed as
`character * fontBytesPerCharacter` — a byte is a glyph. There is no
double-byte concept anywhere in the engine, so "replace the CJK font" has no
subject.

### What a CJK AGI would actually require

Not a font layer. In order: a double-byte-aware string walk, a text grid that
can hold a 16-wide cell in a game laid out for 8, and a decision about what
happens to every script that positions text by column. That is an engine
feature, and the replacement-font work would be the last and smallest step of
it.

**AGI is out of scope for this project.** The one piece that transfers is
`tools/korean/mkfont.py`, which could bake an 8x8 or 16x16 1bpp set — but
since AGI has no double-byte path to draw them with, that is a font for a
consumer that does not exist.

---

## Recommendation

**Do neither as part of the SCUMM upstream submission.** Both are separate
contributions with separate reviewers, and bundling them weakens the SCUMM
patch set — which is already 94 commits and needs splitting rather than
growing.

If one is ever picked up, **SCI, and only after a measurement pass**:

1. Confirm `GfxFontKorean`'s path is reachable in a real Korean SCI fan
   translation (we have never run one).
2. Measure what `drawTextFontGlyph` does to a glyph on each PC-98 driver
   before assuming a replacement survives it.
3. Decide the `_hiresGlyphBuffer` question — 8bpp coverage needs a wider
   buffer and a driver entry point that accepts it, or the SCI port is
   1bpp-only. A 1bpp-only SCI port is still worth having; it just should be
   proposed as one rather than discovered halfway.

The reusable asset in both cases is `graphics/hires_text/`, which is why it
was built outside `engines/`. That decision is now paying: a SCI port would
consume it as a library and add ~100 lines of SCI-shaped glue, with none of
the composite work repeating.
