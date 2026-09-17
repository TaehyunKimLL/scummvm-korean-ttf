# The i18n plan, decided by measurement

Three measurements were run against the engine (M1 SCI ownership, M2 AGI
ownership, M3 the font layer) and two more against a clean `upstream/master`
tree with none of our code in it (`i18nfonts.py`, `i18nfontset.py`). This is
what they decided.

Documents: `i18n/M1_SCI_OWNERSHIP.md`, `i18n/M2_AGI_OWNERSHIP.md`,
`i18n/M3_FONT_LAYER.md`. Scripts: `harness/i18n/`, `harness/i18nfonts.py`,
`harness/i18nfontset.py`. Every script re-checks its transcribed file:line and
exits 1 on a moved line; each was bite-tested.

Tree: `~/work/scummvm/i18n`, branch `i18n`, cut from `upstream/master`
`503d0747781`. Build ERRORS=0, 403 tests OK.

---

## The four findings that decide the design

### 1. SCI cannot convert wholesale. AGI can.

**[measured, M1]** Of the 50 kernel ops that carry game text, **49 expose byte
semantics to the script** — a byte length, a byte index, a script-sized buffer,
or a pointer into a segment the script can read with `lal`/`lag`. Only `kSaid`
is clean, and only because a Said block holds vocabulary group numbers rather
than characters.

Three make a whole-engine conversion impossible rather than merely expensive:

- `kStrAt` (`kstring.cpp:104-153`) — the script **reads and writes one byte** at
  an offset it chose.
- `cursorPos` as a script selector (`controls16.cpp:222`, `:678`,
  `kgraphics.cpp:948`) — 90 of 232 byte==char sites depend on it.
- `kMessage(SIZE)` (`message.cpp:356`) — the byte count the script allocates from.

So SCI is **(b): the presentation path only, with a byte fence at the script
interface.** Of 232 sites: 84 convert cleanly, 121 convert internally behind
the fence, 27 cannot convert at all.

**[measured, M2]** AGI is the opposite. It owns every string it holds; the only
script-readable text is one `char[25][40]` table plus the ego-word array, and
nothing is ever written back into a resource. Exactly **one** opcode argument
is a length the script chose — `get.string`'s `maxLen` — and Sierra's original
meaning for it was **cells**, which the byte implementation gets wrong today.

AGI converts at load time. Four byte boundaries remain: the save file, the
game-id/save-description identifiers, `get.num`'s `atoi`, and the parser
dictionary.

### 2. The fixed-width problem is AGI's, not SCI's

This was the user's own stated caveat and the measurement inverts where it
lands. **[measured, M3]** 83 fixed-width sites: 34 genuinely need a per-character
width, 24 may stay cell counts, 25 are game-visible contracts. The decisive
split is inside the 34: **15 already ask the font — all of them SCI.**

SCI's font resource stores a width per glyph (`scifont.cpp:244`), so SCI has
essentially no fixed-width problem. AGI is nothing but one: a byte times a
fixed stride (`graphics.cpp:1230`), with the width chosen *before* the
character is known (`:1224`), and 12 of its 15 sites use a byte count as a
width.

But **[measured, M2]** the 40×25 grid is the cheap part, not the expensive one:
AGI never asks a character how wide it is — `charCurPos.column++`
(`text.cpp:393`) is the entire layout model — and `_displayFontWidth` is a
screen mode, not a per-character property. A uniformly wider cell moves no
coordinate.

### 3. Shift-JIS and Big5 are not round-trippable. CP949 is.

**[measured, M3]** by linking against the tree's own `libcommon.a`, and
independently reproduced here with Python's codecs, which agree:

| encoding | pairs | distinct code points | aliases |
|---|---|---|---|
| CP949 | 17048 | 17048 | **0** |
| EUC-KR | 8225 | 8225 | **0** |
| CP932 (SJIS) | 9604 | 9206 | **398** |
| Big5 | 13710 | 13706 | **4** |

For Japanese, bytes → code point → bytes **is not the identity**. This is the
single hardest constraint on the design and it is why the byte fence is not
optional even where the ownership would allow one: **the original bytes must be
kept alongside the code points** wherever they will be handed back.

Korean is free. This is also why Korean is the first language to convert.

### 4. `encoding.dat` failing is silent

**[measured, M3]** Remove it and every CJK conversion returns 0 decoded
characters with one warning: **text disappears rather than erroring.** Any
design that decodes at load time must fail loudly here.

---

## What the fork does, in order

The approach is the user's: **do not touch the existing Hangul/SJIS paths.**
Add a code-point font beside them. This makes I6 (prove the unchanged case)
nearly free, because the old path is still there and still the control.

One correction to the shape: the new font must be a **`Graphics::Font`
subclass**, not a third root class. Upstream's `Graphics::Font` is already
indexed by `uint32` (`font.h:140`, `:214`) with `drawString(U32String)` and
**`wordWrapText(U32String)`** (`:330`), and has 53 subclasses. Inheriting gets
the wrap, the string width and the bounding box for free — the same wrap K5
hand-fixed in AGI. A separate root would make three hierarchies where two
already cost us.

```
Graphics::Font                    uint32-indexed, upstream, 53 subclasses
  └ Graphics::FontSet   NEW       per-character delegation within one line
      ├ the game's own font       unchanged
      └ CP949 / SJIS glyph source NEW; korfont.h etc. untouched
```

**The FontSet is not an invention.** kyra ships it: `MultiSubsetFont`
(`screen.h:435`) asks each subset and takes the first that answers, with `-1`
meaning "not mine" (`screen.cpp:4121-4124`), on a `hasGlyphForCharacter()`
contract (`screen.h:284`). `Big5Font::hasGlyphForBig5Char` (`big5.h:39`) is the
same idea. An engine shipping Chinese, Japanese and Korean already does this.

**And a FontSet is what structurally kills the S7 defect class.**
**[measured, `i18nfontset.py`]** In upstream SCI, the caret measures through a
*global* current font: `_text16->_font->getCharWidth(...)`
(`controls16.cpp:128`, `:137`) while the caller mutates that global around the
draw (`:441`, `:443`, `:444`). **24 `SetFont()` calls mutate it; 39 sites read
through it** (text16 15, text32 13, controls16 7, controls32 4). S7 was two of
those 39 seeing different moments. With one font object that delegates per
character there is no "which font is this line" to disagree about — the code
that contains the defect cannot be written.

The only reason the font is ever swapped is a raw byte sniff —
`SwitchToFont1001OnKorean` (`text16.cpp:735`) tests `0xB0..0xC8` by hand and
calls `SetFont(1001)` (`:747`), from 10 call sites. The FontSet removes the
reason, not just the symptom.

### The cards

| # | card | closes on |
|---|---|---|
| **C1** | `Graphics::FontSet`: a `Graphics::Font` that delegates per code point, with `hasGlyph()` and a truthful "not mine". No engine wired to it. | unit tests over delegation, missing glyphs and fallback order; a blank-but-present glyph must be distinguishable from absent |
| **C2** | A CP949 glyph source as a `Graphics::Font`, indexed by code point. Existing `FontKorean*` untouched. | 2350 syllables render; byte-identical against the existing path's stencils |
| **C3** | AGI: decode at load, `U32String` internally, the four byte boundaries named. | English pixel-identical over the K5 corpus; Korean renders; the 40×25 grid does not move |
| **C4** | SCI: the byte fence at the six named boundary functions, presentation path in code points. | `getString`/`strncpy`/`strlen` contracts pinned by test; English pixel-identical; the 10 `SwitchToFont*` call sites gone |

AGI is first because M2 says it converts wholesale and SCI does not. C1+C2 come
first because both engines need them and neither needs the other.

### Not in this branch

- **I2 beyond the font.** A FontSet removes the *font* half of the ambient
  state. The pen position and colour (A1's 56 AMBIENT sites) remain.
- **Japanese round-tripping.** The 398 CP932 aliases need the original bytes
  carried alongside. Design it in C1's interface; do not solve it yet.
- **SCI32.** M1 found two defects there that exist today and are not ours:
  `getTextDimensions` casts an assembled double-byte pair to `(unsigned char)`
  before measuring (`text32.cpp:752-753`), and the SCI32 caret has the S7/S9
  defect with no character-aware step (`controls32.cpp:329`, `:336`, `:407`,
  `:435`).

---

## Two things the measurements say we were wrong about

1. **K5 concluded AGI needed no wholesale conversion** — "one buffer and three
   length measurements". M2 measured 25 COUNT + 20 TRUNCATE + 43 CARET sites,
   because K5's population only counted *calls* of the four grid-drawing
   functions and missed the menu layer, the inventory columns and the save-slot
   list entirely.

2. **uint16 is the wrong width.** UTF-16 is not one unit per character outside
   the BMP, which reintroduces the defect class in miniature. `Common::U32String`
   exists and 767 files in the clean tree use it. K2 already chose `uint32` for
   the AGI prompt, so uint16 would narrow a decision already made.
