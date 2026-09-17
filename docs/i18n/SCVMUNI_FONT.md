# SCVMUNI — a Unicode bitmap font container for SCI

Status: **implemented and verified**. Builder `harness/i18n/m7mkfont.py`,
independent checker `harness/i18n/m7check.py`, reader
`engines/sci/graphics/fontunicode.{h,cpp}`.

## The problem this exists to solve

`[source]` The Korean font ScummVM already supports is `SCVMSJIS`, read by
`graphics/korfont.cpp`. Its glyph lookup is:

```c
uint16 uc = ConvertKSToUCS2(c);
const uint offset = (uc - 0xAC00) * 32;
```

`[measured]` That indexing can only address the Unicode hangul syllables
block, `U+AC00..U+D7A3`. The KQ1 patch font `korean.fnt` declares exactly
11,184 16×16 glyphs, matching that block. There is no slot for anything else.

`[source]` This is why `Graphics::checkKorCode()` accepts only lead bytes
`0xB0..0xC8` — the pre-composed syllable rows of KS X 1001. The narrow gate is
not an oversight, it is a **guard that matches the font's real capability**.
Widening it alone would compute a negative offset:

`[measured]` For characters a translator plausibly types, `uc - 0xAC00` is:

| character | code point | offset | result |
|---|---|---|---|
| 「 corner bracket | U+300C | −31,732 | out of bounds |
| 王 hanja | U+738B | −14,453 | out of bounds |
| Ａ full-width | U+FF21 | +21,281 | out of bounds |
| ㄱ standalone jamo | U+3131 | −31,439 | out of bounds |
| ℃ degree sign | U+2103 | −35,581 | out of bounds |
| 가 | U+AC00 | 0 | valid |
| 힣 | U+D7A3 | +11,171 | valid |

`[measured]` The user-visible consequence, reproduced on screen: a SCITRS
bundle whose first entry was `「한자王子」 ※표시 ＡＢＣ ㄱㄴㄷ ℃ 정상음절`
renders as a **completely empty blue box**, while the three untouched buttons
render Korean correctly. The font switch never happens, so the single-byte
font receives EUC-KR bytes one at a time and draws nothing.

`[measured]` Text using only pre-composed syllables is unaffected: all 41,529
double-byte characters across the 1,786 KQ1 translation entries fall inside
`0xB0..0xC8`. The defect is invisible until a translator uses punctuation.

## Format

All integers little-endian. Header is 36 bytes.

```
offset size  field
0x00   8     magic        "SCVMUNI\0"
0x08   2     version      = 1
0x0A   2     flags        bit0: 2bpp antialiased, else 1bpp
0x0C   1     cellWidth    px
0x0D   1     cellHeight   px
0x0E   1     advanceNarrow
0x0F   1     advanceWide
0x10   4     glyphCount
0x14   4     codepointTableOffset   glyphCount x uint32, ASCENDING
0x18   4     widthTableOffset       glyphCount x uint8, 1 or 2 cells
0x1C   4     bitmapOffset           glyphCount x bytesPerGlyph
0x20   4     reserved
```

`bytesPerGlyph = ((cellWidth * 2 * bpp + 7) / 8) * cellHeight`. Every glyph
uses the two-cell stride regardless of its own width, so one row length serves
both and the reader needs no per-glyph branch.

### Design decisions, and why

**Explicit sorted code point table, not arithmetic.** The representable set
becomes whatever the font was built with, in any script. Lookup is a binary
search; an absent glyph is a clean miss that the caller can detect, not a wild
read. The reader verifies the table is sorted at load rather than trusting the
producer, because an unsorted table would make the binary search return wrong
glyphs silently.

**Width from Unicode East Asian Width, not from the TTF advance.**
`[measured]` Noto Sans CJK at 16 px reports an advance of 14.72 for 가 and
16.00 for 「 — the hangul syllable is *narrower* than the punctuation. No
advance threshold separates wide from narrow reliably. `unicodedata.
east_asian_width() in ("W", "F")` classifies both correctly, and the checker
re-verifies every flag against that property.

**Baseline derived from measured ink, not from font metrics.**
`[measured]` Noto Sans CJK at pixel size 16 reports ascent 19 + descent 5 =
24, so drawing on the advertised baseline clips glyphs against a 16 px cell —
the first version of this builder produced a 「 missing its horizontal stroke.
The builder now measures the actual ink bounding box over a sample, shrinks
the point size until the ink fits the cell, and centres what remains.

**Glyphs the TTF cannot draw are dropped, not stored blank.** A blank slot
renders as an empty box with no way for the caller to notice. A missing entry
is detectable via `hasGlyph()`.

## Verification

`[measured]` `m7check.py` re-reads a bundle without using the writer's code
and checks: table sorted and unique, file size exactly matches the declared
layout, no glyph is blank, every width flag agrees with Unicode EAW, and
sampled glyph bitmaps match a fresh PIL render pixel for pixel.

Against the Korean bundle with hanja, built from Noto Sans CJK at 16 px:

```
version=1 bpp=1 cell=16x16 glyphs=17763
no blank glyphs: OK
width flags match Unicode EAW: OK
bitmap re-render: 302 checked, 0 mismatched  OK
RESULT: PASS
```

The checker duplicates the builder's threshold and ink-box measurement, so
those two constants are stated in both files and must be changed together;
a mismatch shows up as bitmap mismatches rather than silently passing.

## Hanja and kanji: derive the set from the code page

`[measured]` The first version of the builder offered hanja only as
`--ranges hanja` = `U+4E00..U+9FFF`, 20,992 glyphs, excluded by default. That
was wrong in both directions, and **Japanese does not work without it at all**
— a language written in kanji cannot render from a hangul-syllable font.

`[measured]` The right set is the game's own code page repertoire, enumerated
from the codec rather than guessed as a block:

```
Shift-JIS (cp932)   9,370 code points   kanji  6,682   kana 177
EUC-KR/UHC (cp949) 17,144 code points   hanja  4,620   kana 169  hangul 11,172
```

The two hanja sets are different characters, and each is a fraction of the
20,992-glyph block — so a block range is simultaneously too large and the
wrong contents. `--ranges sjis` / `uhc` / `gbk` / `big5` build exactly what the
encoding can express.

Resulting bundles at 16 px, 1 bpp:

```
Japanese  --ranges sjis                           9,353 glyphs    645 KB
Korean    --ranges latin,...,uhc                 17,763 glyphs  1,224 KB
Korean    --ranges latin,...  (no hanja)         12,248 glyphs    846 KB
```

## Two rasterisation bugs that changed one character into another

`[measured]` **The 1bpp threshold must be ~40, not 128.** At 16 px a CJK face
draws a thin vertical stroke as faint as **grey 47** — well below the
midpoint. Thresholding at 128 deleted it. The hanja 王 lost both vertical
strokes and rendered as three horizontal bars, i.e. as 三: not a degraded
glyph but a *different character*, on screen, legibly wrong.

`[measured]` **The ink box must be measured by rendering, not from
`getbbox()`.** For 王 at 16 px `getbbox` reports height 16 while the actual
raster is **20 rows**, so a bbox-derived fit clipped the bottom stroke. The
builder now renders each sample into a 3×cell canvas and scans for ink.

`[measured]` **Sample across the whole requested set, not its prefix.** The
first few hundred code points are Latin, which never exercises the tall CJK
forms that decide the fit — so the original `codepoints[:400]` probe measured
the one part of the font that could not reveal the problem.

Fixing all three also improved coverage measurably, because glyphs previously
rejected as blank now survive: full-width 90→94, punctuation 165→177,
symbols 542→546.

Coverage of the Korean bundle with hanja: hangul 11,172/11,172 · hanja
4,620 · symbols 546/546 · full-width 94/94 · punctuation 177/184 · jamo 93/94.

`[measured]` Reader-side unit tests live in `test/engines/sci/translation.h`
(SCITRS key rules) and are wired into `make test` via `test/module.mk`:
409/409 pass, up from 403. The suite was confirmed to actually bite by
deliberately breaking whitespace collapsing — exactly the four normalisation
assertions failed, then passed again on restore.

## What is not done

`[unmeasured]` `GfxFontUnicode` is implemented, unit-tested at the container
level and compiled into the engine, but **not yet wired into the text
renderer**. `GfxText16` still routes Korean through `GfxFontKorean`, so the
empty-box defect above persists at runtime until the code-point text path
exists to feed it. That wiring is the remaining step, and it is the same seam
as the internal representation change: `GfxFont` takes `uint16 chr`, which
cannot carry a code point above U+FFFF and today carries a packed EUC-KR pair
instead.
