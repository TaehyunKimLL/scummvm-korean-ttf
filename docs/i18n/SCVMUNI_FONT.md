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

Against a bundle built from Noto Sans CJK at 16 px:

```
version=1 bpp=1 cell=16x16 glyphs=12248
no blank glyphs: OK
width flags match Unicode EAW: OK
bitmap re-render: 307 checked, 0 mismatched  OK
RESULT: PASS
```

Coverage of that bundle: hangul 11,172/11,172 · symbols 542/546 ·
full-width 90/94 · punctuation 165/184 · jamo 93/94. Hanja are available via
`--ranges hanja` but excluded by default — 20,992 glyphs would add ~1.3 MB for
characters most translations never use.

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
