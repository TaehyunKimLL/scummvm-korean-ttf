# The fork's actual subject: ScummVM has two font hierarchies

Measured on a tree cut from `upstream/master` at `503d0747781` with no code of
ours in it (`~/work/scummvm/i18n`, branch `i18n`). Reproduce with:

```bash
cd ~/work/scummvm/harness && python3 i18nfonts.py     # exits 1 on a moved line
```

The script pins ten source facts and re-checks each; corrupting one makes it
print two `*** FAIL ***` lines and exit 1.

---

## The finding

**Upstream already has the code-point text layer this project was going to
build.** `Graphics::Font` is indexed by `uint32 chr` throughout —
`getCharWidth(uint32)` (`graphics/font.h:140`), `drawChar(Surface*, uint32,
...)` (`:214`), `getBoundingBox`, `getKerningOffset` — and its string-level
API is `Common::U32String`: `drawString`, `getStringWidth`, and
**`wordWrapText`** (`graphics/font.h:330`). 53 classes subclass it. 767 files
in the tree use `U32String`.

**And there is a second, unrelated font hierarchy for CJK.** `FontKorean`
(`graphics/korfont.h:42`), `FontSJIS` (`graphics/sjis.h:64`) and `Big5Font`
(`graphics/big5.h:32`) are three independent root classes. They are indexed by
**`uint16 ch`, an encoded byte pair, not a code point**
(`korfont.h:98`, `sjis.h:131`), and they draw into a raw `void *dst` with an
explicit pitch and bpp rather than onto a `Surface`.

**[measured]**

```
Graphics::Font subclasses (code-point indexed) : 53
FontSJIS/FontKorean/Big5 subclasses (byte-pair):  8
classes in BOTH hierarchies                    :  0
```

Zero. The two hierarchies do not meet anywhere. There is no adapter in
`graphics/`, no common base, no conversion. Which means **every engine that
wants CJK text bridges the two itself, at its own call sites** — and that
bridge is exactly where the lead-byte tests live.

**[measured]** engines naming a CJK font type at all: **9 of 127**.

```
25 kyra    25 sci    17 saga    12 darkseed    9 scumm
 5 sherlock  4 sky   4 mm       3 agos
```

SCI shows both halves of the bridge in two adjacent functions of one file:

```cpp
// engines/sci/graphics/screen.cpp:473
void GfxScreen::putMacChar(const Graphics::Font *commonFont, ..., uint16 chr, byte color) {
    commonFont->drawChar(&_displayScreenSurface, chr, x, y, color);   // code-point font, one line
}
// engines/sci/graphics/screen.cpp:477
void GfxScreen::putHangulChar(Graphics::FontKorean *commonFont, ..., uint16 chr, byte color) {
    memset(_hiresGlyphBuffer, 0xff, 256);                             // byte-pair font, nine lines
    uint16 charWidth = commonFont->getCharWidth(chr);
    commonFont->drawChar(_hiresGlyphBuffer, chr, charWidth, 1, color, 0, -1, -1);
    _gfxDrv->drawTextFontGlyph(_hiresGlyphBuffer, charWidth, x << 1, y << 1, ...);
}
```

Same job, same file, two unrelated interfaces — and the second one is where the
scratch buffer, the hardcoded 256, the `x << 1` and the manual width all come
from. The caller assembles the pair upstream of it:

```cpp
// engines/sci/graphics/text16.cpp:215
if (_font->isDoubleByte(curChar))
    curChar |= (*(const byte *)(textPtr + 1)) << 8;
```

---

## What this changes about the plan

**The fork's subject is not "add a code-point representation to ScummVM".** It
is **"there are two font hierarchies and the CJK one is on the wrong side of
the line"**. That is a much smaller, much better-defined change than a rewrite,
and it is the root of the defect class:

- `Graphics::Font::wordWrapText()` already wraps a `U32String` correctly, by
  character. K5's byte-counting word wrap existed because AGI could not reach
  it.
- `getCharWidth(uint32)` already answers per character. S9's cursor
  arithmetic broke because the Korean font answers per *byte pair* and charges
  0 for a byte.
- A `Graphics::Font` draws onto a `Surface`. The raw-buffer `drawChar(void*,
  pitch, bpp, maxW, maxH)` of the CJK hierarchy is what forces every caller to
  own a scratch buffer and its bounds — the shape behind the blank-glyph and
  clipping defects.

So the first move of the fork is concrete and testable: **make the CJK fonts
`Graphics::Font` subclasses indexed by code point.** The conversion tables
already exist and are already exact — `Common::CodePage` carries
`kWindows949`, `kWindows932`, `kWindows950`, `kWindows936`
(`common/str-enc.h:41-44`), and S3b measured `encodeWindows949()` round-tripping
all 2350 KS X 1001 syllables with 0 errors.

**19 `isDoubleByte`-class tests exist in the tree, 14 in SCI and 5 in SCUMM,
plus 32 raw byte-range predicates** — that is the population the bridge
removal has to reach zero on, above the font layer.

---

## What it does not change

Invariant **I2** of `I18N_ACCEPTANCE.md` — a line's font, pen and update owner
must be one value produced once — is untouched by any of this. Six of the
twelve recorded defects are I2, and a unified font hierarchy does not supply
it. It remains the second of the two root causes.
