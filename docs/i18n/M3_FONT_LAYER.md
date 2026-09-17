# M3: the font layer in SCI and AGI, and what "the font owns its encoding,
# indexed by Unicode code point" would actually require

Written for card M3. Engine read at `96ce757ba47` (branch `hires-text`);
scripts at `/tmp/i18n/scripts/m3*.py`, `m3conv.{cpp,sh}`, `m3all.sh`. Line
numbers are only valid at that commit.

**No engine code was read-write.** `~/work/scummvm/repo/scummvm` is untouched:
`git diff --stat HEAD` is empty and the only untracked entries are the two that
were already there (`.worktrees/`, `encoding.dat`). Nothing was built into the
engine tree — `m3conv.sh` links against object files the tree had already built
and writes its binary to `/tmp`. **[measured]**

Every claim below is one of three kinds and says which:

- **[source]** — a file:line in the engine. Static reachability only.
- **[measured]** — a number one of the scripts here produced by running.
- **[unmeasured]** — stated because it is load-bearing and nobody has checked it.

The file:line citations are not maintained by hand. The three census scripts
extract all **181** of them, resolve each against the engine tree, and fail if a
cited line no longer contains the token it is quoted for — so a rebase breaks
the check instead of quietly making this document wrong. **[measured]** 181
checked, 0 problems; pointing the `DBCSFontBase` row at line 9999 of
`graphics/dbcsfont.h` makes `m3fonts.py` report `*** MOVED *** ... line 9999
past EOF (166 lines)` and exit 1, and restoring it returns exit 0.

`m3docbite.py` does the same for **this document's own** citations, which are a
superset of the scripts' — every `file:line` written in prose or in a table is
extracted, resolved against the tree, and reported if the file is gone or the
line is past EOF. **[measured]** 118 distinct engine citations, 0 problems; adding one
bogus line number makes it print `*** BAD ***` and exit 1.

```
$ bash /tmp/i18n/scripts/m3all.sh
### m3fonts   transcribed source lines checked: 74   problems: 0
### m3fixed   transcribed source lines checked: 83   problems: 0
### m3lead    transcribed source lines checked: 24   problems: 0
### m3conv    (built and ran against common/libcommon.a)
overall: OK
```

---

## Short answer

| Question | Answer |
|---|---|
| **Q1** How many font classes, and can any of them say "no glyph"? | **21 classes** reachable from SCI + AGI. **9 of 21** can report a missing glyph to the caller. AGI has no font *object* at all in the relevant sense — its lookup lives in the graphics manager. **[measured]** |
| **Q2** Can they all be indexed by code point? | **No. 7 of 21 are BLOCKED** — their glyph index is derived from the encoded bytes by a piecewise map with hand-tuned corrections, not invertible without re-encoding. 5 are DIRECT, 9 need a converter. **[measured]** |
| **Q3** The fixed-width problem. | **83 sites. (a) 34 need a per-character width, (b) 24 may stay cell counts, (c) 25 are game-visible contracts.** The number that decides the size of the work is the **19** (a)-sites that do *not* already ask the font — **4 in SCI, 15 in AGI**. SCI was proportional from the start; AGI is a grid from top to bottom. **[measured]** |
| **Q4** Is the conversion boundary there? | **Yes for CP949/SJIS/Big5/Latin-1, absent for CP437.** CP949 round-trips **17,048 of 17,048** decodable pairs with 0 errors. `encoding.dat` is **required at runtime** and without it every CJK conversion returns 0 — silently, after one warning. **[measured]** |
| **Q5** The smallest change? | **Make `GfxFont::decodeChar()` the only way SCI16/SCI32 walk a string** — it already exists and already has 5 call sites. It removes **9** call-site lead-byte tests and leaves **15** sites asking byte questions for reasons a font cannot answer. **38%**. **[measured]** |

The two findings that matter most:

1. **SCI does not have a fixed-width problem; AGI is nothing but one.** SCI's
   font resource stores a width per glyph (`scifont.cpp:244`) and every
   measurement path already asks per character — 15 of 19 SCI (a)-sites are
   already correct. AGI's glyph lookup is `character * fontBytesPerCharacter`
   (`graphics.cpp:1230`) with the width chosen before the character is even
   looked at (`graphics.cpp:1224`). **[source]** The user's caveat is right, and
   it is an AGI caveat.

2. **The blocked classes are all Japanese.** `FontTowns`, `FontPC98`,
   `FontPCEngine` and `FontSjisSVM` derive their glyph index from Shift-JIS
   lead/trail arithmetic containing literal corrections with no closed form
   (`sjis.cpp:182-184`). `FontKoreanSVM` by contrast already converts EUC-KR to
   Unicode and indexes by `uc - 0xAC00` (`korfont.cpp:189`) — **it is already a
   code-point-indexed font wearing a byte-indexed interface.** **[source]**

---

## Q1. Every font class reachable from SCI and AGI

`m3fonts.py` enumerates them and answers the four questions as data. Full
output: `/tmp/i18n/m3fonts.txt`. **[measured]** 21 classes, 74 citations, 0
problems.

### The table

| class | reachable from | glyph lookup keyed by | width decided by | knows an encoding? | can say "no glyph"? |
|---|---|---|---|---|---|
| `Sci::GfxFont` | SCI base | `uint16 chr`, meaning undefined here | `getCharWidth(uint16)` | **yes** — `decodeChar()` is the only encoding knowledge on the interface (`scifont.h:65`) | no |
| `Sci::GfxFontFromResource` | every single-byte SCI game | `uint16` used as a direct index into `_chars[]` | **per character**, `_chars[chr].width` (`scifont.cpp:244`) | none | **yes** — `chr >= _numChars` warns and draws nothing (`scifont.cpp:283-287`) |
| `Sci::GfxFontKorean` | font 1001, KO_KOR | packed lead-low / trail-high | delegates, then `>>1` below SCI32 (`fontkorean.cpp:63`) | **yes** — `isDoubleByte` + `decodeChar` | logs `NO GLYPH` and draws anyway (`fontkorean.cpp:83-88`) |
| `Sci::GfxFontSjis` | font 900, JA_JPN | same packing | delegates, `>>1` | **yes** — its own private ranges (`fontsjis.cpp:53`) | no |
| `Sci::GfxMacFontManager` | Mac SCI1/1.1 controls | `Graphics::Font::getCharWidth(uint32)` | `Graphics::Font`, per char | none | no |
| `Graphics::FontKorean` | SCI, SCUMM, KYRA | `uint16 ch`, "little endian" (`korfont.h:99`) | `getCharWidth(uint16)` | the class name | no, `drawChar` returns void |
| `Graphics::FontKoreanBase` | via FontKorean | `uint16`, split by `isASCII` | ASCII half or full cell (`dbcsfont.cpp:80`) | `isASCII` is Wansung-specific | no |
| `Graphics::FontKoreanSVM` | `korean.fnt` | **`(codepoint - 0xAC00)`** (`korfont.cpp:189`) | inherited cell | **yes, and it converts** (`korfont.cpp:41`) | **yes** — `checkKorCode` fails → 0 |
| `Graphics::FontKoreanWansung` | `KOREAN#.FNT` | `((ch%256)-0xb0)*94 + (ch/256)-0xa1` (`korfont.cpp:243`) | inherited cell; `english.fnt` has its own | the index arithmetic *is* the encoding | **yes** — range-checked, returns nullptr |
| `Graphics::FontSJIS` | SCI, SCUMM, KYRA | `uint16 ch` | `getCharWidth(uint16)` | name only | no |
| `Graphics::FontSJISBase` | via FontSJIS | `uint16`, split by `isASCII` | ASCII width **fixed at 8** (`sjis.h:197`) | half-width katakana 0xA1..0xDF count as single byte (`sjis.cpp:142`) | no |
| `Graphics::FontTowns` | `FMT_FNT.ROM` | `getCharFMTChunk()`, a 90-line chunk/base walk (`sjis.cpp:164`) | inherited cell | SJIS row structure, hardcoded | **yes** |
| `Graphics::FontPC98` | `FONT.ROM` | `hiblock*192` + 3-way trail split (`sjis.cpp:374`) | inherited cell | SJIS layout, hardcoded | **yes** |
| `Graphics::FontPCEngine` | `pce.cdbios` | a 45-entry SJIS range table (`sjis.cpp:418`) | inherited cell (12x12) | the table entries *are* SJIS ranges | **yes** |
| `Graphics::FontSjisSVM` | `SJIS.FNT` | `mapKANJIChar()` → `base*0xBC + index` (`sjis.cpp:608`) | inherited cell | SJIS, applied to the two bytes | **yes** — `base == -1` |
| `Graphics::DBCSFontBase` | under Korean **and** SJIS | `uint16` handed to the subclass | ASCII half or cell (`dbcsfont.cpp:80`) | **none, by design** | warns, draws nothing (`dbcsfont.cpp:180`) |
| `Graphics::Big5Font` | sky, darkseed, sherlock — **not sci/agi** | `_chineseTraditionalIndex[ch & 0x7fff]` (`big5.cpp:89`) | `kChineseTraditionalWidth = 16`, constant (`big5.h:43`) | the 0x8000 bit is the caller's marker | **yes, explicitly** — `hasGlyphForBig5Char` (`big5.h:39`) |
| `Graphics::HiResBitmapFont` | SCUMM hires_text; **not wired to sci/agi** | **`glyphIndex(uint32 codepoint)`** (`bitmap_font.h:108`) | `GlyphMetrics::advance`, or the cell | **yes** — `codePage()` (`bitmap_font.h:101`) | **yes** — `hasGlyph()` (`bitmap_font.h:110`) |
| `Agi::GfxFont` | AGI, all games | **nothing** — it hands out a raw table pointer (`font.cpp:128`) | **nobody** — no width function on this class | none | no |
| `Agi::GfxMgr` glyph loop | AGI, the actual lookup | `getFontData() + character * fontBytesPerCharacter` (`graphics.cpp:1230`) | `FONT_DISPLAY_WIDTH`, chosen before the char is known (`graphics.cpp:1224`) | none | no — every byte 0..255 indexes inside the table by construction |
| `Graphics::DosFont` | AGI fallback + 5 engines | byte value × 8 (`dosfont.h:41`) | 8, by the array's stride | CP437 by provenance, stated nowhere | no |

**[source]** for every row; **[measured]** for the counts.

### The three things this table says

**AGI has no font class in the sense SCI does.** `Agi::GfxFont` (`font.h:27`)
loads a byte array and hands out the base pointer; the *only* glyph lookup in
AGI is 12 lines inside `GfxMgr::drawCharacterOnDisplay`
(`graphics.cpp:1219-1230`). There is no `getCharWidth` anywhere in AGI's font
layer to override. **[source]**

**9 of 21 can report a missing glyph, and only 2 of those return it as a
value.** `Big5Font::hasGlyphForBig5Char` (`big5.h:39`) and
`HiResBitmapFont::hasGlyph` (`bitmap_font.h:110`). The other seven return a
null pointer that only the font's own drawing code sees, so the answer reaches
a warning (`dbcsfont.cpp:180`) and never the caller. **[measured]**

**`GfxFontKorean` knows it has no glyph and draws it anyway.**
`fontkorean.cpp:83-88` explicitly tests the 0xB0..0xC8 × 0xA1..0xFE rectangle,
logs `NO GLYPH`, and then calls `putHangulChar` regardless. **[source]** That is
the missing-glyph *policy* question the S3b card left open, sitting in the code
as a debug print.

---

## Q2. The code-point-indexed interface, concretely

### What already exists on our branch

Two of the three pieces are already here.

**`Graphics::DBCSFontBase` (`graphics/dbcsfont.h:55`, commit `94b5143334c`,
confirmed an ancestor of HEAD).** What it gives us: the drawing modes, the 1-bit
blitter, the outline builder and the cell/ASCII width split are shared and
*encoding-free* — the class asks a subclass four questions (`getCharData`,
`hasFeature`, `isASCII`, `getASCIIWidth`) and knows nothing about bytes.
**[source]** What is missing: `getCharData(uint16 c)` takes the *packed encoded
value*, the same `uint16` the caller assembled. Widening it to `uint32
codepoint` is one signature change in the base — and five rewrites in the
subclasses, four of which are the BLOCKED ones.

**`Sci::GfxFont::decodeChar()` (`engines/sci/graphics/scifont.h:65`).** What it
gives us: a font-owned byte→packed-value decoder with a behaviour-preserving
default, already overridden in `GfxFontKorean` (`fontkorean.cpp:70`) and already
live at **5 call sites in `controls16.cpp`** (`:146`, `:182`, `:194`, `:525`,
`:549`). **[measured]** What is missing: it decodes *to the font's own packing*,
not to a code point. It solves "how many bytes is this character" and not "which
character is it". `GfxFontSjis` does not override it, so the Japanese path still
does the assembly at the call site.

### The interface

```cpp
// proposed, in the shape HiResBitmapFont already has
class CodePointFont {
public:
    /// Glyph index for a code point, or -1. The ONE method the others rest on.
    virtual int  glyphIndex(uint32 cp) const = 0;
    bool hasGlyph(uint32 cp) const { return glyphIndex(cp) >= 0; }

    /// Pen advance for a code point. A fixed-cell font returns cellWidth().
    virtual int  advance(uint32 cp) const = 0;

    /// The font's opinion of its own geometry.
    virtual int  cellWidth()  const = 0;
    virtual int  cellHeight() const = 0;
    virtual int  ascent()     const = 0;
    /// False => every advance() equals cellWidth(); a caller may lay out on a
    /// grid. This is the declaration Q3 needs and HiResBitmapFont already has.
    virtual bool isProportional() const = 0;

    /// What to draw for a code point with no glyph: 0 for "draw nothing".
    virtual uint32 fallback(uint32 cp) const { return 0; }

    virtual const byte *glyphData(int index) const = 0;
};
```

`HiResBitmapFont` implements all of it today except `fallback()`
(`bitmap_font.h:97,101,108,110,113,120`). **[source]** That is why it is the
reference and not a proposal.

### How each existing class would implement it

**DIRECT — the interface is a rename of what the class already does (5).**

| class | how |
|---|---|
| `HiResBitmapFont` | it *is* the interface; only `fallback()` is new |
| `Graphics::FontKoreanSVM` | already computes `uc = ConvertKSToUCS2(c)` then indexes `(uc - 0xAC00)`. Delete the first step and take `uc` as the argument. `glyphIndex` = `cp - 0xAC00` bounds-checked; `hasGlyph` = that bounds check, which `checkKorCode` is standing in for today (`korfont.cpp:187-193`) |
| `Graphics::DBCSFontBase` | widen `getCharData(uint16)` → `getCharData(uint32)` and `isASCII(uint16)` → `isASCII(uint32)`. `advance()` = the existing `getCharWidthIntern` (`dbcsfont.cpp:80`); `isProportional()` = `false` for every current subclass |
| `Sci::GfxFont` | the base's defaults already return 0/false; `decodeChar` becomes `decode(text, &n) -> uint32 codepoint` |
| `Sci::GfxMacFontManager` | `Graphics::Font` is already `uint32`-indexed (`graphics/font.h:140`) |

**CONVERT — implementable, but needs codepoint→bytes first (9).**
`GfxFontFromResource`, `GfxFontKorean`, `GfxFontSjis`, `FontKorean`,
`FontKoreanBase`, `FontKoreanWansung`, `FontSJIS`, `FontSJISBase`, `Big5Font`.

Each of these has a byte-derived index that *is* invertible, because the
inversion already exists in `Common::` (Q4) or in the class:

- `FontKoreanWansung::glyphIndex(cp)` = encode `cp` to CP949, then
  `((lead)-0xb0)*94 + (trail)-0xa1`, with the same range check
  (`korfont.cpp:243-245`). Costs one `U32String::encode()` per lookup or one
  cached map. **[source]**
- `GfxFontFromResource::glyphIndex(cp)` = the font resource has no cmap at all,
  so it needs a declared code page like SVFN's — `HiResBitmapFont` solves
  exactly this with `legacyGlyphIndex()` (`bitmap_font.cpp:308`), building the
  map by walking every legal byte pair once and decoding it. **[source]**
- `Big5Font::glyphIndex(cp)` = encode to Big5, set 0x8000, index
  `_chineseTraditionalIndex` — which is already a sparse map built at load
  (`big5.cpp:89`), i.e. the invertible case done properly.

**BLOCKED — the index is derived from the encoded bytes in a way that is not
invertible from a code point without re-encoding first (7).**

| class | why |
|---|---|
| `Graphics::FontTowns` | `getCharFMTChunk` (`sjis.cpp:164`) classifies the lead byte into KANA/KANJI/EKANJI, computes a base from `s - ((s+1) % 32)`, then applies **two literal corrections** with no closed form (`sjis.cpp:182-184`) and a seven-case switch with per-case `cr` offsets. There is no function from a code point to this index; there is only "encode to SJIS and run the walk" |
| `Graphics::FontPC98` | piecewise on both bytes (`sjis.cpp:365`, `:374`), with three disjoint trail-byte ranges mapping into one contiguous block |
| `Graphics::FontPCEngine` | a 45-entry table of SJIS ranges scanned linearly (`sjis.cpp:418`) |
| `Graphics::FontSjisSVM` | `mapKANJIChar` (`sjis.cpp:608`): `base = fB - 0x81` with a 0x40 hole, `index = sB - 0x40` with a 0x3F hole |
| `Agi::GfxFont` | there is no index. It returns a table pointer (`font.cpp:128`) |
| `Agi::GfxMgr` glyph loop | `character * fontBytesPerCharacter` (`graphics.cpp:1230`) — a byte times a fixed stride. A code point above 0xFF has nowhere to come from |
| `Graphics::DosFont` | `256 * 8` bytes, index = byte (`dosfont.h:41`) |

**The honest reading of "BLOCKED".** None of the four Japanese fonts are
*impossible*; they are impossible *without re-encoding*. Each one becomes
`glyphIndex(cp) { encode cp to SJIS; run the existing walk; }`. What the word
marks is that the class cannot be turned inside out — the arithmetic cannot be
rewritten as a code-point function, so a code-point font wrapping them is a
*converter plus the old code*, not a simplification. The three AGI/DOS entries
are blocked in the stronger sense: there is no index to invert.

**[unmeasured]** Whether `encode(cp) → run the walk` is fast enough to do per
glyph, or needs a cached map like `legacyGlyphIndex()`'s. Nobody has profiled
it.

---

## Q3. The fixed-width problem — the user's caveat, counted

`m3fixed.py`. Full output: `/tmp/i18n/m3fixed.txt`. **[measured]** 83 sites, 83
citations, 0 problems.

The classification rule is written into the script before the sites are, so it
is applied rather than decided per case:

- **(a)** the site computes a **position or extent** by advancing or summing
  over a string's characters. Two characters of different widths make it wrong.
- **(b)** the site converts cell units to pixels with one constant, or lays out
  a grid. Correct for as long as the font **declares** a fixed cell — exactly
  what `HiResBitmapFont::isProportional()` already expresses
  (`bitmap_font.h:97`).
- **(c)** a number the game's own scripts or shipped data can see. Changing what
  it **means** breaks games whatever the font does.

### The counts

```
            a-done   a-todo        b        c    total
sci             15        4        9        9       37
agi              0       15       15       16       46
both            15       19       24       25       83

collapsed to the three classes Q3 asked for:
  (a) genuinely needs a per-character width : 34
  (b) may stay a cell count                 : 24
  (c) game-visible contract                 : 25
```

`a-done` / `a-todo` splits class (a) by whether the site **already asks the font
per character**. That split is the finding.

### SCI: 15 of 19 (a)-sites are already correct

SCI has been proportional since SCI0. The proof is not an argument, it is the
font format: `GfxFontFromResource` reads a width **per glyph** out of the
resource (`scifont.cpp:244`) and `getCharWidth` returns `_chars[chr].width`
(`scifont.cpp:264-265`). **[source]** A fixed-width SCI font does not exist.

The whole measurement path follows from that:

| site | what it does |
|---|---|
| `text16.cpp:268` | `GetLongest` sums `_font->getCharWidth()` |
| `text16.cpp:271` | and breaks on a **pixel** comparison, not a column |
| `text16.cpp:420` | `Width()` sums the same |
| `text16.cpp:541,550` | `Draw()` measures and advances the pen by that width |
| `text16.cpp:623,626,636` | `Box()` = GetLongest → Width → centre, all in pixels |
| `controls16.cpp:146,182,194` | list width and caret, through `decodeChar` |
| `text32.cpp:318,752` | SCI32's own copies |

**[source]**

The four SCI `a-todo` sites, which are the real work:

1. **`text16.cpp:754`** — `DrawStatus()` walks **bytes** with no `isDoubleByte`
   and no `decodeChar`, so each half of a double-byte character is charged its
   own width. **[source]**
2. **`text16.cpp:198`** — `GetLongest` returns a value called `charCount` that
   is a **byte** count: it is incremented twice for a double-byte character
   (`:286-290`) and handed to `Width()` and `Draw()` as their `len`. One unit is
   not one character anywhere on this path.
3. **`text16.cpp:392`** and **4. `text16.cpp:514`** — `Width()`'s and `Draw()`'s
   `while (len--)` loops, which decrement `len` a second time inside the
   double-byte arm to compensate.

Sites 2–4 are the same defect seen three times: the engine's internal "length"
unit is a byte, which is precisely what layer (2) of the user's proposal —
uint16 Unicode, 1 unit == 1 character — would fix, and which **the font layer
cannot fix on its own.**

### AGI: 15 of 15 (a)-sites are wrong the moment a character is not 8px

Zero AGI sites ask a font for a width, because there is nothing to ask
(Q1). Every one of them advances by a constant or uses a **byte count as a
width**:

| site | what it assumes |
|---|---|
| `text.cpp:393` | **the site.** Drawing a character advances the cursor by exactly one cell. A 16px Hangul syllable on an 8px grid overwrites the next cell |
| `text.cpp:375` | backspace moves back exactly one cell |
| `graphics.cpp:1191` | `drawStringOnDisplay` advances the pen by the cell per **byte** |
| `text.cpp:1218` | `stringWordWrap` measures a word as `curReadPos - wordStartPos` — bytes as a width |
| `text.cpp:1231` | and splits a long word by **byte position**, which can split a character |
| `text.cpp:1251` | the box width it reports is that byte count, and `text.cpp:559` turns it into pixels |
| `text.cpp:666`, `:946` | status line and prompt right-align by `strnlen` |
| `inv.cpp:69`, `:75`, `:102` | inventory columns from `strlen` |
| `menu.cpp:146`, `:149`, `:468` | menu fit test and drawn width from `textLen` bytes |
| `systemui.cpp:869` | a dialog button's width = `strlen(text) * cell` |

**[source]**

### (b): 24 sites that may stay cell counts — if the font declares it

These are correct for **any** fixed cell, including a 16px one. AGI already
proves it: `graphics.cpp:159` sets `_displayFontWidth = 16` for hires and every
cell→pixel conversion (`graphics.cpp:350`, `:370`) follows without change.
**[source]** What they need is not per-character widths; it is a font that says
whether its cell is honest — `isProportional()`.

SCI's (b) sites are all heights: `_curPort->fontHeight` is set once per font
(`text16.cpp:77`) and used as a row pitch by the list control
(`controls16.cpp:124`) and the menus (`menu.cpp:639`, `:734`). **Height is
already a font declaration, not a per-character question,** which is why the
same problem does not exist vertically.

Two (b) entries deserve naming because they are assumptions, not conversions:
`GfxFontKorean::getHeight()` and `getCharWidth()` do `>> 1` (`fontkorean.cpp:60`,
`:63`) — the hires cell is assumed to be **exactly twice** the lores one. True
for 16×16 over 8×8 and for nothing else. `GfxFontSjis` has the identical copy
(`fontsjis.cpp:61`). **[source]**

### (c): 25 game-visible contracts

The ones that constrain the design hardest:

- **AGI's 40×25 grid is an API, not a layout choice.** `FONT_COLUMN_CHARACTERS`
  = 40 and `FONT_ROW_CHARACTERS` = 25 (`text.h:68-69`); `display(row, col)` is
  an AGI opcode and `charPos_Clip` (`text.cpp:113`) clips what a script passed.
  A script that writes at column 30 must still land at column 30.
- **`TEXT_STRING_MAX_SIZE` = 40** (`text.h:74`) is enforced against the
  script's own `maxLen` in `get.string` (`op_cmd.cpp:2009`), and the buffers
  behind it are **42 bytes** (`text.h:171`, `:201`).
- **SCI's `max` selector** is read by the kernel (`kgraphics.cpp:943`) and the
  edit control (`controls16.cpp:223`) and compared against `text.size()` —
  **bytes** — in both the Korean (`controls16.cpp:363`) and ASCII
  (`controls16.cpp:486`) paths. The script allocated those bytes.
- **`left & 0xFFC`** (`fontkorean.cpp:90`, `fontsjis.cpp:77`). Before drawing,
  x is snapped **down to a 4-pixel boundary**. This is a hard obstacle to
  proportional double-byte text in SCI and it is deliberate — the SJIS copy
  explains it as PC-98 text-mode cell placement. **[source]**

### The answer to the caveat

The user's caveat is correct and it is **not symmetric**. In SCI, making
characters code points costs **4 sites** plus the byte-length unit problem,
because the engine already asks the font for every width. In AGI it costs
**15 sites** — 3 that advance by a constant and **12 that use a byte count as
a width**, which no font change reaches at all — they need a measuring function that does not exist yet.
The (b) class, **24 sites**, stays correct for free provided the font declares
`isProportional() == false`; the (c) class, **25 sites**, must keep meaning
exactly what it means today.

---

## Q4. Conversion infrastructure: what exists, what is missing, what it costs

`m3conv.cpp`, built against the engine tree's **own** `common/libcommon.a` and
the test suite's null OSystem by `m3conv.sh`, so this measures the code the
engine links. `encoding.dat` md5 `f2e88b2faec499a4914c3a0bcffc7db1`, 179,670
bytes. Full output: `/tmp/i18n/m3conv.txt`. **[measured]**

### What exists

`common/str-enc.h:30-61` declares 23 `CodePage` values including `kWindows949`,
`kWindows932`, `kWindows936`, `kWindows950`, `kJohab`, `kISO8859_1` and
`kDos850`, with `kLatin1 = kISO8859_1` and `kBig5 = kWindows950` as aliases.
`convertToU32String` / `convertFromU32String` (`str-enc.h:71-72`) are the
two-directional boundary, and `convertUHCToUCS(high, low)` (`str-enc.h:73`) is
the direct EUC-KR decoder `FontKoreanSVM` already uses. **[source]**

### Both directions, measured over each encoding's own byte rectangle

```
encoding   population   decoded   distinct-cp   roundtrip   encode-errors
CP949         23940      17048       17048        17048         0
SJIS          23436       7724        7326         7326         0
Big5          16999      16460       13493        13492         1
Latin-1         256        256          -            256         0
CP850           256        256          -            256         0
CP437        NOT PRESENT in Common::CodePage   (common/str-enc.h:30-61)

the sub-rectangle FontKoreanWansung::getCharData() can index:
KS-glyph       2350       2350        2350         2350         0
```

**[measured]**

Reading it:

- **CP949 is exact in both directions.** 17,048 decodable pairs, 17,048 distinct
  code points, 17,048 byte-identical round trips, zero error characters. The
  2,350-syllable sub-rectangle S3b measured is reproduced here exactly, which is
  the cross-check between the two cards.
- **SJIS decodes 7,724 pairs to 7,326 distinct code points** — 398 pairs are
  *aliases*, two byte sequences for one character. Every one of the 7,326 round
  trips, so the inverse is well-defined; it just is not a bijection on bytes.
  **A boundary that converts bytes → codepoint → bytes will not always return
  the bytes it was given for Japanese.** [measured]
- **Big5 has 2,967 aliased pairs and exactly one code point that does not
  round-trip to two bytes.** `encodeWindows950` transliterates
  (`str-enc.cpp:1157` passes `transliterate = true`), so an unmappable point
  becomes something else rather than failing.
- **Latin-1 is total and free.** All 256 bytes, all round-trip, no file needed —
  it is a compiled-in `kLatin1ConversionTable[128]` (`enc-internal.h:38`).

### What is missing

**CP437.** There is no enumerator for it. `Common::CodePage` carries `kDos850`,
`kDos862` and `kDos866` (`str-enc.h:50-52`) and not 437 — and CP437 is exactly
what AGI's fallback font is: `Graphics::DosFont::fontData_PCBIOS`
(`dosfont.h:41`), 256×8 bytes in PC-BIOS order. **[source]** So the one engine
whose font layer is *entirely* a code page has no `CodePage` for it. Adding it
is a 128-entry `static const uint16[]` beside the other five in
`common/enc-internal.h`, ~256 bytes of rodata, no load-time cost, and
`encodeOneByte` / `decodeOneByte` (`str-enc.cpp:1069`, `:1089`) pick it up with
no other change. **[unmeasured]** whether anything else in the tree wants it.

### Table-driven vs algorithmic, and the cost

| | mechanism | where | cost |
|---|---|---|---|
| CP949, SJIS, Big5, GBK, Johab | **table**, loaded from disk | `loadCJKTable` (`str-enc.cpp:107`), called from `loadCJKTables` (`:137`) | **168,810 bytes** of forward tables resident after load (932: 18,048 · 949: 44,856 · 950: 27,946 · johab: 30,080 · 936: 47,880) |
| the reverse of each | **table**, built lazily by inverting the forward one | `encodeWindows949` (`str-enc.cpp:611-632`) and its four twins | **131,072 bytes each** (`uint16[0x10000]`), allocated on the first `encode()` for that page |
| Latin-1, CP850, CP866, the Windows-125x set, MacRoman, ASCII | **table**, compiled in | `getConversionTable` (`str-enc.cpp:982`) | 128 × `uint16` = 256 bytes each, in rodata |
| the reverse of those | **prefix tree**, built lazily | `getReverseConversionTable` (`str-enc.cpp:1048`) | a 48-pointer level-1 plus up to 48 × 256-byte level-2 nodes, per page |
| UTF-8 / UTF-16 | **algorithmic** | `decodeUTF8` (`str-enc.cpp:40`), `decodeUTF16Template` (`:916`) | none |
| `convertUHCToUCS` | table lookup into the 949 table | `str-enc.cpp:320` | shares the 44,856 bytes above |

**Nothing about CJK is algorithmic.** Every code-point↔bytes step for the three
encodings Q4 names goes through a table read from `encoding.dat`.

### Load time

**[measured]** `loadCJKTables()` via the first conversion, 5 runs with
`releaseCJKTables()` between: **min 0.09 ms, mean 0.11 ms, max 0.19 ms** on this
machine, warm cache. It reads all five tables eagerly (`str-enc.cpp:167-175`),
not on demand — so a game that only needs Korean still pays for Japanese,
Chinese and Johab. 169 KB and a tenth of a millisecond.

### Is `encoding.dat` required at runtime, and what happens without it

**Yes, required — and the failure is silent after one warning.**

`loadCJKTables()` opens `encoding.dat` through `SearchMan`
(`str-enc.cpp:142`). On failure it prints `"encoding.dat is not found. Support
for CJK is disabled"` **once** and returns with every table pointer null
(`:143-144`). It also rejects a bad magic (`:152-155`) and a wrong version
(`:162-165`) the same way. `cjk_tables_loaded` is set to `true` **before** the
open (`:140`), so it never retries.

Measured with the file removed:

```
=== WITHOUT encoding.dat ===
CP949      population=23940   decoded=0   roundtrip=0
SJIS       population=23436   decoded=0   roundtrip=0
Big5       population=16999   decoded=0   roundtrip=0
Latin-1    population=256     decoded=256 roundtrip=256
KS-glyph   population=2350    decoded=0   roundtrip=0
```

**[measured]** Every CJK conversion returns zero characters. The decoders emit
`invalidCode` for each pair (`str-enc.cpp:250-256`) and `encodeWindows949`
substitutes `errorChar` when the reverse table is null (`str-enc.cpp:642-646`).
stderr during the run: **empty** — the one warning goes through ScummVM's
`warning()`, which the null OSystem swallows; a player sees text disappear, not
an error. Latin-1 is unaffected because its table is compiled in.

This is the same dependency `FORMAT_PROPOSAL.md` §5 records for SVFN
(`bitmap_font.cpp:344-348`: an empty legacy map is poisoned with a sentinel so
it is not rebuilt per character), reached here from the other end.
**Any codepoint↔game-encoding boundary in this tree is a deployment
dependency on a 176 KB data file.**

---

## Q5. The smallest font-layer change, and what it does not solve

`m3lead.py`. Full output: `/tmp/i18n/m3lead.txt`. **[measured]** 24 citations,
0 problems.

### The change

**Make `GfxFont::decodeChar()` the only way SCI16 and SCI32 walk a string, and
give `GfxFontSjis` the override it lacks.**

It is the smallest because the virtual already exists (`scifont.h:65`), already
has a behaviour-preserving default, is already overridden in `GfxFontKorean`
(`fontkorean.cpp:70`), and already has 5 live call sites in `controls16.cpp`.
Nothing new is designed; the remaining callers are converted to the existing
one. **[source]**

### What it removes: 9 call sites

```
engines/sci/graphics/text16.cpp:215   GetLongest: read byte, ask yes/no, OR in the trail
engines/sci/graphics/text16.cpp:314   GetLongest, PC-9801 overhang
engines/sci/graphics/text16.cpp:351   GetLongest, punctuation seek-back
engines/sci/graphics/text16.cpp:394   Width()
engines/sci/graphics/text16.cpp:516   Draw()
engines/sci/graphics/text32.cpp:440   SCI32 drawText
engines/sci/graphics/text32.cpp:588   SCI32 getTextWidth
engines/sci/graphics/text32.cpp:662   SCI32 line splitter
engines/sci/graphics/text32.cpp:713   SCI32 fourth copy
```

**sci16 5, sci32 4, agi 0.** **[measured]** AGI is zero because AGI never asks
the question — it cannot (Q1/Q3). The change has nothing to delete there; it has
something to add.

`text16.cpp:351` is worth naming: it `error()`s out — kills the game — if the
byte it walked back to is not a lead byte. That is a *guess about alignment*
enforced by an abort, and `decodeChar` walking forward from a boundary removes
the guess.

### What it does NOT solve: 15 sites

| category | n | the reason a font cannot answer |
|---|---|---|
| **font-selection** | 3 | `SwitchToFont1001OnKorean` (`text16.cpp:763`), `SwitchToFont900OnSjis` (`text16.cpp:786`), and SCI32's copy (`text32.cpp:954`) sniff bytes to decide **which font to load**. There is no font in scope yet. S3b ruled this out of font ownership for exactly this reason; B0 §3.2 agrees |
| **layout** | 2 | AGI's `character * fontBytesPerCharacter` (`graphics.cpp:1230`) and `charCurPos.column++` (`text.cpp:393`). A proportional code-point font makes these *wrong*, not right |
| **wrapping** | 2 | `GetLongest` returns a byte count (`text16.cpp:198`) and remembers the break point as a byte offset (`text16.cpp:293`); AGI measures a word in bytes (`text.cpp:1218`). A font does not decide where lines may break, and for a language with no spaces it has no opinion at all |
| **caret** | 3 | `stepCharLeft` / `stepCharRight` (`dbcs.h:96`, `:111`) re-parse the **whole string from a known boundary**, because an EUC-KR trail byte is byte-for-byte indistinguishable from a lead byte. That is a property of the bytes in the buffer, not of the font, and it survives any font change (`controls16.cpp:424`) |
| **game-byte-arithmetic** | 5 | the control's `max` compared against `text.size()` in bytes (`controls16.cpp:363`, `:486`); a list entry truncated to `maxChars` **bytes**, which can cut a character in half before any font sees it (`controls16.cpp:151`); the **parser's own** lead-byte predicate with no font in scope (`lowercase.cpp:85`); the composer testing encoded bytes for drawability (`koreaninput.cpp:59`) |

**9 removed, 15 unaffected: the font-layer change addresses 38% of the
byte-level questions this tree asks about double-byte text.** **[measured]**

One entry in that table *is* solved by the Q2 interface rather than by
`decodeChar`: `koreaninput.cpp:59` reimplements the 0xB0..0xC8 × 0xA1..0xFE
rectangle to ask whether a composed syllable is drawable, because
`encodeWindows949` is UHC and will happily produce 8,822 syllables the font has
no glyph for (S3b M2, reproduced by this card's CP949 measurement: 17,048
encodable, 2,350 in the glyph rectangle). **A font-side `hasGlyph(uint32)` —
the one thing only 2 of 21 classes offer today — deletes it.** That is the
strongest single argument for Q2's interface over Q5's minimal change.

---

## What this card did not do

- **No engine code changed, none built, none committed.**
  `git diff --stat HEAD` empty; only the two pre-existing untracked entries.
- **Nothing measured at runtime in a game.** Every SCI/AGI number here is
  static reachability plus a citation check. The only executed measurement is
  `m3conv`, and it exercises `Common::`, not a text path.
- **AGI's Korean branches are not on HEAD.** `engines/agi/hangul.cpp` and the
  wide-font work exist on `wt/k3-agifont-src` and friends, which are **not**
  ancestors of `hires-text`. **[measured]** The AGI numbers above are for
  upstream AGI as this branch carries it. K3's shape is quoted where it
  answers a Q2 question — `GfxFont::getWideGlyph(uint32 codePoint)` and
  `drawCharacterOnDisplay(uint32)` with a background-fill fallback for a
  missing glyph — because it is the existing proof that AGI *can* take a code
  point, but it is a different branch.
- **No SCI32 anything was run.** This project has never executed SCI32; the 4
  SCI32 sites are static citations.

## Unmeasured, and load-bearing

1. **Whether `glyphIndex(cp) = encode(cp); run the old walk` is fast enough per
   glyph** for the four BLOCKED Japanese fonts, or needs the cached-map
   treatment `legacyGlyphIndex()` uses. Nobody has profiled it.
2. **What the 12 AGI byte-count-as-width sites should become.** They need a
   measuring function AGI does not have. Whether that is "ask the font per
   character" or "keep the grid and make the wide font exactly 2 cells" is
   undecided, and it is the decision that determines whether AGI's (c) contracts
   survive.
3. **Whether `left & 0xFFC` (`fontkorean.cpp:90`) can be removed for Korean.**
   The comment inherited from the SJIS copy explains it as PC-98 text-mode
   placement, which Korean has no equivalent of — but no capture exists showing
   what dropping it does.
4. **Whether SJIS's 398 aliased byte pairs matter.** Measured that bytes →
   codepoint → bytes is not the identity for them; unmeasured whether any
   Japanese game's data contains the non-canonical member of a pair.
5. **Whether anything besides AGI wants a `kDos437`.** The absence is measured;
   the demand is not.

## How to re-run

```bash
bash /tmp/i18n/scripts/m3all.sh          # everything; exit 1 if a citation moved
python3 /tmp/i18n/scripts/m3docbite.py   # this document's own 118 citations
python3 /tmp/i18n/scripts/m3fonts.py     # Q1/Q2  21 classes, 74 citations
python3 /tmp/i18n/scripts/m3fixed.py     # Q3     83 sites,   83 citations
python3 /tmp/i18n/scripts/m3lead.py      # Q5     24 sites,   24 citations
bash    /tmp/i18n/scripts/m3conv.sh      # Q4     builds against libcommon.a, runs twice
```

`M3ENG=/path/to/tree` points any of them at a different worktree. All four are
read-only on the engine.
