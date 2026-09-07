# Outline and shadow with alpha blending — reference implementations

Collected while trying to make `[shadow] mode=outline` visible on FM-Towns.
The renderer draws the stroke, the tests pass, and the screen shows nothing:
297 black pixels against the original's 11416.

## What ScummVM already does (graphics/sjis.cpp)

`FontSJISBase::drawChar` is the closest reference in the tree, and it does
**not** stroke by redrawing the glyph at offsets. It builds a separate
outline mask first:

```cpp
uint8 outline[18 * 18];
if (_drawMode == kOutlineMode) {
    memset(outline, 0, sizeof(outline));
    createOutline(outline, glyphSource, width, height);
}
...
blitCharacter(outline,      w + 2, h + 2, dst,            pitch, c2);  // stroke
blitCharacter(glyphSource,  w,     h,     dst + pitch + 1, pitch, c1); // body
```

`createOutline` (sjis.cpp:153) dilates the glyph by OR-ing each row into
three adjacent rows and shifting horizontally:

```cpp
const uint8 b1 = mask | (mask >> 1) | (mask >> 2);
const uint8 b2 = (mask << 7) | ((mask << 6) & 0xC0);
line1[x] |= b1;  line2[x] |= b1;  line3[x] |= b1;
```

Three properties matter:

1. **The outline is a mask, not the glyph.** It is computed by dilation, so
   it is solid wherever any nearby glyph pixel exists - it has no coverage of
   its own to inherit.
2. **It is drawn as one blit before the body**, not as 8 offset copies that
   fight each other over the coverage plane.
3. **It is 1-bit.** These are bitmap fonts; the question of a half-covered
   stroke never arises.

## What SDL_ttf does

Two paths, both of which avoid the problem rather than solving it:

- `TTF_SetFontOutline(n)` uses FreeType's `FT_Stroker` on the **outline**
  (the vector contour) before rasterising, then renders that as a separate
  glyph. The stroke gets its own antialiased coverage, independent of the
  body's.
- The common recipe renders the text **twice into two surfaces** - once with
  the stroked font in the outline colour, once with the plain font in the
  text colour - and blits the outline surface first.

Either way the stroke is a **separate rendering** with its own alpha, then
composited under the body. It is never derived from the body's coverage.

## Why my approach cannot work

`glyph_renderer.cpp` draws the decoration by re-blitting the same glyph at
offsets into the same coverage plane. That means:

- the stroke inherits the body's antialiased edges, so it is semi-transparent
  exactly where it should be solid;
- forcing it opaque (my change) makes the *coverage* solid but leaves the
  colour written to the index plane, where FM-Towns masks it with `& 0x0f`
  and the shadow colour 0 reads back as transparent;
- 8 offset copies overwrite each other's coverage, so the "don't replace a
  stronger pixel" rule ends up arbitrating between strokes rather than
  between stroke and body.

The measurement that shows this cleanly: baking the outline into the TTF with
Pillow's `stroke_width` raised the font's opaque bytes 10760 → 27262 and the
on-screen red ink 6036 → 10729, with black unchanged at 375. A single
coverage channel cannot express two colours, so a baked stroke becomes
**fatter body ink**, not an outline.

## The shape a correct fix has

Following sjis.cpp:

1. Build a dilation mask from the glyph once - solid, no coverage inherited.
2. Write the stroke colour through that mask into the index plane, with
   coverage 0xFF, **before** the body.
3. Write the body normally on top, coverage as-is.

The stroke must be laid down in a single pass so no two decoration pixels
compete, and the platform's transparent key has to be honoured: on FM-Towns
index 0 means transparent, so a black outline needs a non-zero index that
maps to black in `_textPalette`, not index 0.

That last point is why the outline is invisible even now, and it is a map
authoring question as much as a code one.
