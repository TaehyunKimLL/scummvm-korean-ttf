# The localization code in this tree: a census, and what a fork has to carry

Written for card I1. Engine read at `3ca65017f27` (branch `hires-text`),
upstream at `c81c8695a44` (2026-09-16), fork base `41ac2b31847`. Harness at
`harness/i1*.py`, `harness/i1*.sh` in this repo. Line numbers are only valid at
those commits — every script re-checks its own transcriptions and fails rather
than measuring a moved line.

Every claim below is one of three kinds and says which:

- **[source]** — a file:line in the engine. Static reachability only.
- **[measured]** — a number this card produced by running something.
- **[unmeasured]** — stated because it is load-bearing and nobody has checked it.

No engine code was changed. One probe was injected to prove the census bites
and was reverted; §8 shows the tree clean.

---

## Short answer

Four findings, in the order they change what we do next.

**1. "The localization code is poor" is 26 branches out of 146, not 146.**
Enumerated and classified exhaustively for Korean: **2 defects, 24 adoption
debt, 81 genuine quirks, 34 fan-translation contracts, 5 ours** — and the 81 are
correct code that must stay. **[measured]** §1. The actionable list is a sixth
of the population, and most of it is in engines this project has never opened.

**2. There is one real defect, and it is not Korean's.** `is2ByteCharacter()`
accepts lead bytes the glyph table has no rows for, and nothing between it and
the table bounds-checks the result. Korean reads **658 assigned EUC-KR
characters out of bounds**, up to 24 KB past a 75 KB table; Simplified Chinese
can reach **78 KB in front of** its table on malformed input. **[measured]**
§3. This is the class of finding S3 was — a small, self-contained, upstreamable
bug — and `harness/i1defect.py` is its executable form.

**3. FontKorean and FontSJIS are 6/15 methods byte-identical after normalising
the language name away; Big5Font shares one method out of seven.**
**[measured]** §4. So the abstraction question has a measured answer and it is
*two classes, not three*: a shared monochrome base under Korean and SJIS is
justified, and pulling Big5Font into it is not.

**4. The fork is cheap today and the reason is measurable.** 240 upstream
commits since our base touch **0** of our 65 added files and **2** of our 29
modified ones. **[measured]** §5. The ScummVM-Kor death mechanism does not
apply to a parallel layer; it applies to the 70 files carrying a `KO_KOR`
branch, which upstream touches ~19 times a month, and we modify **two** of
them.

And the negative finding that shapes §6: the gap really is adoption.
`Common::CodePage` has carried `kWindows949`, `kWindows932`, `kWindows936`,
`kWindows950` and `kJohab` the entire time, and **50 engines already use
`Common::CodePage` for something** — while every Korean lead-byte test in the
tree is still hand-rolled, in **7 separate copies of the same 0xB0..0xC8
range**. **[measured]** §2.

---

## 1. The census

`harness/i1census.py` enumerates every line under `engines/`, `graphics/`,
`common/`, `gui/`, `backends/`, `video/`, `image/` and `audio/` that names a
`Common::` language value, excluding detection tables (data describing *which
game is which*, not behaviour) and the unit tests. A line *branches* if the
value takes part in a test or a switch. **[measured]**

```
KO_KOR  sites=165  branch-sites=146  files=63
JA_JPN  sites=280  branch-sites=231  files=105
ZH_TWN  sites=336  branch-sites=308  files=75
ZH_CHN  sites=44   branch-sites=36   files=21
RU_RUS  sites=294  branch-sites=250  files=129   (enumerated only)
HE_ISR  sites=178  branch-sites=142  files=83    (enumerated only)
```

**Correcting the card's numbers.** The card carried KO 172/68, JA 307/114,
ZH_TWN 337/80, ZH_CHN 44/26, RU 353/150, HE 204/93. Those counts included the
`detection` files; excluding them and counting *branch* sites rather than all
mentions gives the table above. The card's ranking survives intact — **Korean
is the third-largest CJK case and the fourth-largest overall** — which is the
load-bearing part.

### 1.1 The classification

Every Korean branch site carries a class in `harness/i1classes.py`, keyed by
`(file, line)`. A site with no class fails the census; a classified line that
no longer names the language fails it too. **[measured]**

| class | KO | what it means |
|---|---:|---|
| **defect** | **2** | wrong behaviour today, with a measurement (§3) |
| **adoption** | **24** | hand-rolled where `Common::` already provides it (§2) |
| **quirk** | **81** | genuine game/platform/data difference; must stay |
| **fantrans** | **34** | fan-translation asset contract; removing it breaks patches on disk |
| **ours** | **5** | added by this fork |

JA/ZH are sampled to `engines/scumm`, `engines/sci` and `graphics/` — the three
trees this project touches — because the out-of-sample remainder (180 JA, 294
ZH_TWN, 27 ZH_CHN branch sites) is dominated by `kyra` and `director`, which no
card here will modify. The script labels those `unsampled` rather than
pretending they are classified. In sample: JA 49 quirk / 2 ours; ZH_TWN 11
quirk / 1 defect / 2 ours; ZH_CHN 5 quirk / 2 defect / 2 ours. **[measured]**

### 1.2 What the four classes look like

**quirk — the majority, and it is correct code.** The Korean Kyrandia release
really does need a taller menu (`staticres.cpp:1181` `menuItemYInc = 24`
against 20), a different chat box (`text_lok.cpp:341-343` `boxY2 = 155` against
153), 2px of extra letter spacing (`text.cpp:37`) and its own font id
(`FID_KOREAN_FNT`, 11 sites). None of that is removable by any abstraction; it
is the localization. **[source]**

**fantrans — the contract with assets people already have.** `korean.trs`
(`trs_bundle.h:47`), `KOREAN.FNT` (`kyra_hof.cpp:210`), font id 1001
(`cache.cpp:70`), `message.map` (`resource.cpp:3119`), `CREDITS.HAN`
(`sequences_lok.cpp:1250`), `HAN_NOTE.CPS` (`script_lok.cpp:1055`), and Grim's
md5 exemption for the Korean `local.lab` (`md5check.cpp:491`). Grim goes
further and *disables two renderers* for Korean (`grim.cpp:278-281`) — a
fan-translation constraint that costs every Korean player the shader and TinyGL
backends. **[source]**

**adoption — §2.**

**ours — 5 KO sites**, all in files we added, plus the S3 parser fix
(`lowercase.cpp:82,86`). We have added almost nothing to the shared surface.

---

## 2. The infrastructure exists; it is not adopted

`Common::CodePage` (`common/str-enc.h:30-60`) carries 24 values including
`kWindows949`, `kWindows932`, `kWindows936`, `kWindows950` and `kJohab`, plus
`convertToU32String` / `convertFromU32String` (`:71-72`) and
`convertUHCToUCS` (`:73`). **50 of the 146 engines already name a
`Common::CodePage`.** **[measured]**

And yet, `harness/i1cover.py` transcribes every hand-rolled double-byte test in
the tree, checks the transcription against the file, and measures each against
the real encoding as Python's codecs define it: **[measured]**

```
Korean (CP949): 17048 assigned double-byte code points
  symbols/jamo rows A1..AC   1996
  Hangul syllable rows B0..C8 4216
  Hanja rows CA..FD          4888
  UHC extension              8822

test                                              accept  reject     pct
graphics/korfont.cpp:35        checkKorCode         2350   14698   13.8%
engines/scumm/charset.h:48     checkKSCode          2350   14698   13.8%
engines/grim/font.h:55         isKoreanChar         2350   14698   13.8%
engines/sword1/text.cpp:355    isKoreanChar         2350   14698   13.8%
engines/sword2/maketext.cpp:709                     2350   14698   13.8%
engines/scumm/charset.h:67     is2ByteCharacter     4874   12174   28.6%
engines/sci/graphics/text16.cpp:741                 4216   12832   24.7%
engines/sci/graphics/text32.cpp:959                 4216   12832   24.7%
engines/hypno/wet/wet.cpp:646  (& 0x80)            17048       0  100.0%
engines/darkseed/tostext.cpp:78 (& 0x80)           17048       0  100.0%
```

**Five independent copies of the identical `0xB0..0xC8 && 0xA1..0xFE`
predicate**, in four engines and one shared file. Two more copies test only the
lead. Two engines test the high bit and accept everything.

Two things follow, and they are different:

1. **The duplication is the adoption gap.** The predicate is the same in five
   places because nothing offers it once. `Common::CodePage` gives the
   *conversion* but not a `isLeadByte(page, byte)`, which is the one piece
   genuinely missing — the same hole S3b found from the other end
   (`SCI_FONT_ENCODING.md`: the caller owns byte-pair assembly) and P1 found
   from the font end (`FORMAT_PROPOSAL.md` §6.1: `isDoubleByte` has no
   font-side source).
2. **13.8% is not a defect.** Those five sites gate a Wansung glyph table that
   genuinely only holds the 2350 syllables of rows B0..C8 — `korfont.cpp:424`
   indexes `((ch % 256) - 0xb0) * 94 + (ch / 256) - 0xa1`, so a Hanja character
   has no row. The test matches the data. It is the *other* eleven thousand
   characters being silently invisible that is the honest limitation, and that
   is a font-data problem, not a branch problem.

The clearest single instance of pure adoption debt:
`engines/wintermute/utils/string_util.cpp:119-150` maps eight European
languages onto their `kWindows125x` code pages and then has
`case Common::KO_KOR:` fall into `warning("Unsupported charset")` returning
cp1252 (`:145-150`) — while `Common::kWindows949` sits in the same enum it is
already importing. **[source]** Second instance:
`engines/darkseed/langtext.cpp:49-70` and `engines/darkseed/tostext.cpp:74-88`
each hand-roll the same `byte & 0x80 → (b1 << 8) | b2` packer into a
`U32String` — an engine that already includes `U32String` everywhere, filling
it with EUC-KR byte pairs instead of code points. **[source]** Third:
`engines/hypno/wet/hard.cpp:362-492` compiles **15 Korean UI strings into C++
as EUC-KR escapes** (`"\xb7\xa1\x9f\x71\xb7\xb3\x9d\x62:"` at `:370`) because
that engine has no string table at all. **[source]**

**So the document says it plainly: the gap is adoption, not missing
infrastructure — with one exception.** `Common::` has the conversions and does
not have a lead-byte predicate, and that single missing function is what all
seven copies are re-implementing.

---

## 3. The one measured defect

`harness/i1defect.py` transcribes both halves of SCUMM's double-byte path — 18
source assertions, all checked — and does the arithmetic. **[measured]**

The two halves:

```cpp
// engines/scumm/charset.h:63-70 — which lead bytes start a pair
static inline bool is2ByteCharacter(Common::Language lang, byte c) {
    if (lang == Common::JA_JPN)  return (c >= 0x80 && c <= 0x9F) || (c >= 0xE0 && c <= 0xFD);
    else if (lang == Common::KO_KOR) return (c >= 0xB0 && c <= 0xD0);
    else if (lang == Common::ZH_TWN || lang == Common::ZH_CHN) return (c >= 0x80);
    return false;
}

// engines/scumm/string.cpp:1265-1267 — the pair is packed, trail unchecked
if (is2ByteCharacter(_language, c)) {
    byte *buffer = _charsetBuffer + _charsetBufPos;
    c += *buffer++ * 256; //LE

// engines/scumm/charset.cpp:254, :318 — index, then unchecked pointer
idx = ((idx % 256) - 0xb0) * 94 + (idx / 256) - 0xa1;
return _2byteFontPtr + ((_2byteWidth + 7) / 8) * _2byteHeight * idx;
```

Measured against the allocation at `charset.cpp:174`:

```
KO_KOR   table 2350 glyphs x 32 bytes (16x16) = 75200 bytes
         leads accepted 0xB0..0xD0 (33)
         byte offsets  -5152 .. 99264
         reads BEFORE table:  5152 bytes
         reads AFTER  table: 24096 bytes
         assigned EUC-KR pairs with an accepted lead: 3008
         of those, reading out of bounds:              658
         first: CA A1 -> byte 78208 (table is 75200 bytes)
         lead rows out of bounds: CA CB CC CD CE CF D0

ZH_CHN   table 8178 glyphs x 24 bytes (12x12) = 196272 bytes
         leads accepted 0x80..0xFF (128)
         reads BEFORE table: 78312 bytes
         reads AFTER  table: 18072 bytes
         assigned GB2312 pairs out of bounds: 0

ZH_TWN   table 13630 glyphs x 30 bytes (16x15) = 408900 bytes
         reads BEFORE table: 2940 bytes
         assigned Big5 pairs out of bounds: 0
```

Read the three rows differently, because they are three different severities:

- **Korean is reachable with valid data.** `is2ByteCharacter` accepts leads up
  to **0xD0** while the table stops at **0xC8**. Rows CA..D0 are Hanja — real,
  assigned EUC-KR characters. **658 of them index past the end of the table**,
  the first by 3 KB and the worst by 24 KB. A translator who types a Hanja
  character into a `.trs` bundle gets a glyph read from whatever follows the
  allocation. This is not hypothetical input; it is ordinary Korean text.
- **Chinese is reachable only with malformed data.** `c >= 0x80` accepts 128
  leads where GB2312 and Big5 use far fewer, so a corrupt byte reaches 78 KB in
  front of the table. Every *assigned* character indexes in bounds. Lower
  severity, same missing check.
- **The fix is one bounds test at `charset.cpp:318`**, plus narrowing the
  Korean lead range from `0xD0` to `0xC8` to match the data the five other
  copies of the predicate already use (§2).

The lead-range half is a one-character change; the bounds test is three lines.
Neither needs a Korean game to verify — `harness/i1defect.py` is the test, and
it exits 1 today.

**Blame note.** `is2ByteCharacter` is `afef3d71cb82` (athrxx, 2020-09-23); the
ZH arm is `c740f96f6338` (trembyle, 2021-11-04). This is upstream code, six
years old, not fan-translation code. **[measured]**

---

## 4. FontKorean / FontSJIS / Big5Font: how alike, measured

`harness/i1fonts.py` extracts every declared method from the three headers,
normalises the language token away (Korean/SJIS/Big5 → X) so `FontKoreanBase`
and `FontSJISBase` compare as the same name, and then diffs the *bodies* of
every method the two monochrome bases share. **[measured]**

### 4.1 Interface

```
FontKorean   graphics/korfont.h  20 declared methods
FontSJIS     graphics/sjis.h     25
Big5Font     graphics/big5.h      7

FontKorean n FontSJIS:  19 of 20 / 25 share a normalised name
  of those, 16 have an IDENTICAL normalised signature
  the 3 that differ:
    createFont   ko: (const char *fontFile)   sjis: (Common::Platform = kPlatformUnknown)
    loadData     ko: (const char *fontFile)   sjis: ()
    constructor  ko: ()                       sjis: (Common::Platform)

only FontKorean: englishLoadData
only FontSJIS  : flipCharacter, getCharFMTChunk, loadBMPData,
                 makeFatCharacter, mapKANJIChar, toggleFatPrint

Big5Font n FontKorean: 1  (getFontHeight)
Big5Font n FontSJIS  : 1  (getFontHeight)
Big5Font methods     : drawBig5Char, drawReal, getFontHeight,
                       hasGlyphForBig5Char, loadPrefixedRaw, makeOutline, ctor
```

### 4.2 Implementation

```
method                      ko-len sjis-len    same
blitCharacter                  258     258    100%  <- identical
createOutline                  619     619    100%  <- identical
getFontHeight                  141     141    100%  <- identical
getMaxFontWidth                138     138    100%  <- identical
setDrawingMode                  99      99    100%  <- identical
toggleFlippedMode              111     111    100%  <- identical
drawChar                      2438    2725     93%
isASCII                         86     116     85%
getCharWidth                   178     132     83%
getCharDataDefault             337     469     47%
hasFeature                     145     513     34%
createFont                     213     551     31%
loadData                       457    1242     19%
getCharDataX                   231     282     18%
getCharData                    782      84     11%

6 of 15 byte-identical after normalising the language token
```

The split is clean and it is not arbitrary. **Everything that touches
*pixels* is identical; everything that touches *the file* diverges.**
`blitCharacter` and `createOutline` — the two functions that actually draw and
outline a 1-bit glyph — are the same 258 and 619 characters in both files.
`drawChar` is 93% the same, differing only where SJIS adds fat-print and flip.
`loadData` is 19% the same, because one reads a 4-byte header from a single
file and the other tries four ROM formats.

### 4.3 The recommendation

**A shared base under FontKorean and FontSJIS is justified; pulling Big5Font
into it is not.**

The smallest base that lets a fourth language in without a fourth parallel
class:

```cpp
// graphics/dbcsfont.h   (name illustrative)
class DBCSFontBase {
    // IDENTICAL in both today - move once, delete twice:
    void setDrawingMode(DrawingMode);       // 100%
    void toggleFlippedMode(bool);           // 100%
    uint getFontHeight() const;             // 100%
    uint getMaxFontWidth() const;           // 100%
    void createOutline(...) const;          // 100%
    template<typename C> void blitCharacter(...) const;  // 100%
    void drawChar(void*, uint16, int pitch, int bpp,
                  uint32 c1, uint32 c2, int maxW, int maxH) const;  // 93%

    // The three the subclass must supply - this is the whole extension point:
    virtual const uint8 *getCharData(uint16) const = 0;
    virtual bool hasFeature(int) const = 0;
    virtual bool loadData(const char *file) = 0;   // widened; SJIS takes none today
};
```

That is **seven method bodies deleted from one of the two files**, and a new
language becomes `getCharData` + `hasFeature` + `loadData` — three functions,
not a 455-line file. `setCharSpacing`/`setLineSpacing` are already no-op
defaults in both and come along free.

**Why Big5Font stays out.** It shares exactly one method name with either
(`getFontHeight`), it has no drawing-mode concept, no outline mode, no ASCII
half, and it stores per-glyph outlines in the glyph struct rather than
generating them (`big5.h:44-48`). Its `drawBig5Char` takes a
`(dest, ch, maxX, maxY, pitch, colour, outlineColour, outline, bpp)` signature
that has no counterpart. Forcing it under the base moves code around without
removing any. **This is the same test this project applied when it refused to
abstract two-case situations earlier — and here it gives a split answer, which
is why it was worth measuring rather than asserting.**

### 4.4 The SCI-side pair is a different answer

`GfxFontKorean` and `GfxFontSjis` share **6 of 6/7 methods with identical
signatures**, but their bodies are 30–66% alike and the divergence is entirely
*which screen entry point they call*: **[measured]**

```
method                  ko-len sjis-len    same
getResourceId               23      23    100%
isDoubleByte                88     104     66%     (0xA1..0xFE vs 0x81..0x9F/0xE0..0xEF)
getCharWidth               129      47     53%     (ko adds an SCI32 branch)
getHeight                  125      45     53%     (same)
draw                       145     811     30%     (putHangulChar vs putKanjiChar)
```

`GfxFontKorean` is 86 lines including licence. **Recommend against unifying
these two.** They are thin adapters over the `graphics/` classes §4.3 already
unifies; merging them would mean merging `putHangulChar` and `putKanjiChar`
(`screen.cpp:477-485` vs `:487-519`), and those genuinely differ —
`putKanjiChar` calls `_gfxDrv->remapTextColor()` (`screen.cpp:515`) and
`putHangulChar` does not, a difference `SCI0_PARSER_ASSESSMENT.md` §6 already
measured and explained.

---

## 5. Fork strategy, with the rebase cost

### 5.1 What the fork costs today

`harness/i1churn.sh`, engine at `3ca65017f27`, upstream at `c81c8695a44`:
**[measured]**

```
fork base   : 41ac2b31847  (2026-09-05)
our diff    : 94 files - 65 added, 29 modified, +16048/-161

upstream commits since base            : 240
  touching a file we ADD               :   0
  touching a file we MODIFY            :   2

upstream commits since base, by tree:
   10  engines/scumm     1  engines/sci     0  engines/agi     3  graphics

12-month upstream rate, by tree:
 12549  whole tree
   662  engines/scumm    75  engines/sci    23  engines/agi   195  graphics

the 29 files we modify, 12-month upstream churn:
    46  engines/scumm/scumm.cpp
    32  engines/scumm/module.mk
    25  engines/scumm/metaengine.cpp
    15  engines/scumm/scumm.h
    13  engines/sci/detection_tables.h
    11  engines/scumm/resource.cpp
     7  graphics/module.mk
     7  engines/scumm/dialogs.cpp
     ... 21 more, each <= 6
   148  TOTAL
```

**Two numbers decide the strategy.** 240 upstream commits produced **two**
collisions with us. Over a year the same files absorb **148** commits — call it
12 a month — and the five that matter are `scumm.cpp`, `module.mk`,
`metaengine.cpp`, `scumm.h` and `detection_tables.h`. Four of those five are
registration points, where a merge conflict is an added line next to an added
line, not a semantic conflict.

### 5.2 Why ScummVM-Kor died, and why this shape does not

The card's mechanism, re-measured here: upstream touches the 70 files carrying
a `KO_KOR` branch **237 times in 12 months, ~19/month**. **[measured]** A fork
that *modifies* those files carries that rate. **We modify two of them**
(`engines/scumm/charset.cpp`, `engines/scumm/charset.h`), and upstream touched
those two twice in a year.

ScummVM-Kor's shape was the opposite: it rewrote the shared text path in place.
The successor project's own README records the death and its consequence —
*"ScummVM-Kor은 이미 개발이 중단되어 더이상 Update가 되고 있지 않고 있었습니다"*
(ScummVM-Kor had already stopped development and was no longer being updated),
which is why V1-style Korean patches stopped working on EmuELEC and why that
author converted them to `korean.trs`
([british-choi/ScummVM-Kor-Trs](https://github.com/british-choi/ScummVM-Kor-Trs)).
The measured consequence in our census is still visible today:
`isKoreanMessageMap` exists in `resource.cpp:3118` only because a reviewer
asked for the scattered in-place tests to be named (see §5.4), and
`isScummvmKorTarget()` (`charset.cpp:48-53`) still gates whether the *whole
bundle loader* runs — the single gate that blocked Japanese `.trs` work in this
project until we replaced it with `getTrsBundleName(_language)`
(`trs_bundle.h:46-55`).

**And the successor fork is the positive control.** The same author maintains
`british-choi/scummvm` and ships builds tagged **v2.9.1** — i.e. he rebases onto
upstream *releases* rather than diverging. That fork survives with the same
Korean goal ScummVM-Kor had, and the difference is the merge cadence, not the
ambition.

### 5.3 The concrete policy

**Merge upstream monthly, on a fixed day, not "when needed".** 12 collisions a
month is a one-sitting merge; twelve months of them is the thing that kills a
fork. Monthly also keeps each merge inside one upstream release cycle, so a
break has one obvious suspect.

**The CI that proves a merge is clean** — all four exist in this tree already,
none needs writing:

1. `make test` — the CxxTest suites, and the ones that matter here are
   `test/engines/scumm/hires_hook_census.h` and
   `test/engines/sci/parser_lowercase.h`, which fail when a *new* renderer or a
   *new* language arm appears unaccounted. (This card did not build, so the
   suite's current pass count is **[unmeasured]** here; the branch's last
   recorded figure was 539.)
2. `harness/i1census.py` — exits 1 when upstream adds a language branch nobody
   has classified, and exits 1 when a merge moves a line we classified. This is
   the merge's early-warning system: a new `KO_KOR` branch upstream is exactly
   the kind of change that silently invalidates our assumptions.
3. `harness/i1defect.py` and `harness/i1cover.py` — both exit 1 if any
   transcribed source line moves, so a merge that reshapes `charset.cpp` is
   caught before anyone reads a rendering.
4. The A/B capture harness against a control build, which is what actually
   proves rendering is unchanged (`REGRESSION_HARNESS.md`).

**Cheap to carry (65 files, 0 collisions in 240 commits) — keep parallel:**
`graphics/hires_text/*`, `engines/scumm/hires_*`, `engines/scumm/trs_bundle.h`,
`engines/sci/parser/lowercase.*`, everything under `tools/korean/` and
`test/`. These are new files in new directories; upstream cannot conflict with
a file it does not have.

**Expensive (29 files) — minimise, and prefer registration to surgery:** of
the 29, **21 saw ≤6 upstream commits in a year** and 11 saw zero. The five
hot ones are registration points. The rule that follows: *when a change can be
a new file plus one registration line, make it that.* This is already what the
branch does — 65 added against 29 modified, deletions 1% — and the measurement
says keep doing it.

**The AGI work is the test case for this rule.** `wt/k6-agitrs-src` holds 9
unmerged commits, 26 files, +2567/-38 — 8 added, 18 modified. **[measured]** It
is the most invasive thing this project has built, and upstream touched
`engines/agi` **zero** times since our base and 23 times in a year. It is safe
to carry *and* the most likely candidate to be refactored toward the added-file
shape before anyone proposes it upstream.

### 5.4 What is shaped to land upstream, and the precedents

**Precedent 1 — upstream accepts this class of work for engines it implements.**
[scummvm/scummvm#2604](https://github.com/scummvm/scummvm/pull/2604), "SCI: Add
support for Korean fan translation" by wonst719, opened 2020-11-06 and merged
2020-11-08, explicitly "part of scummvm-kor merge project". The squashed base
commit `b7664c24dcc` (2020-10-28) is +2797/-16 across 17 files including the
whole of `graphics/korfont.{h,cpp}` and `graphics/cp949m.h`. **[measured]** sev-
said "Looks good to me" within hours; bluegr and sluicebox reviewed. sluicebox's
review comment is the reusable lesson:

> "I'd like to see the repeated message-map tests in resource.cpp moved into a
> function like isKoreanMessageMap() with a comment explaining why that needs to
> be handled differently. I spend a lot of time in resource.cpp, and as I'm sure
> you've noticed, it's understandably built up a lot of cryptic exceptions."

That is why `ResourceManager::isKoreanMessageMap()` exists at
`engines/sci/resource/resource.cpp:3118` with three call sites (`:880`, `:1982`,
`:1990`). **[source]** The review standard is *name the condition, explain why*,
not *avoid touching shared files* — and the same reviewer approved a 2797-line
addition in the same breath. Two more merged: `345771f574af` "SCUMM: Add
multi-font support for Korean fan translated games" (2020-11-02) and PR #4442
(SAGA Korean). **[measured]**

**Precedent 2 — the rejection was about ownership, not Korean.**
[scummvm/scummvm#5597](https://github.com/scummvm/scummvm/pull/5597), "AGS:
Support for Korean fan translations" by british-choi, opened and closed the same
day, 2024-01-07. tag2015: *"The AGS engine in ScummVM is based off the 3.6.0
branch of the upstream AGS interpreter … Generally we try to follow their
codebase to avoid diverging too much, maybe you could try opening a PR there"*.
The author answered "OK. I understand. I will try it." and closed it himself.
No technical objection was raised by anyone. **AGI, SCUMM and SCI are engines
ScummVM implements, so precedent 1 applies to all of our work and precedent 2
applies to none of it.**

**Ranked as upstream-landable, most to least ready:**

1. **The `is2ByteCharacter` bounds defect (§3).** Three lines, an executable
   test, affects three languages, no Korean asset needed to reproduce, and it is
   six-year-old upstream code. This is a bug report with a patch, not a feature.
2. **The S3 parser fold** (`lowercase.cpp`, already merged into our branch at
   `4397cc82fa6`). Self-contained, has a test with 2350 cases, and
   `SCI0_PARSER_ASSESSMENT.md` already argued it as a standalone upstream fix.
3. **The `DBCSFontBase` of §4.3.** A pure refactor that deletes seven duplicated
   method bodies and changes no behaviour, provable by A/B capture on the
   existing Japanese and Korean targets. Propose *after* 1 and 2, because it
   touches a file the Korean fan-translation community depends on.
4. **`getTrsBundleName()` generalising `isScummvmKorTarget()`**
   (`trs_bundle.h:46-74`). Turns a Korean-only gate into a per-language one and
   is the piece with the clearest reviewer story — but it changes bundle
   discovery for an existing community, so it needs the compatibility argument
   `FORMAT_PROPOSAL.md` §9 already contains.
5. **The hi-res text layer.** Large, new, and only after 1–4 have established a
   track record. `FORMAT_PROPOSAL.md` §8 already scoped the font-format half as
   an RFC rather than a patch.

**Not upstream-shaped:** anything under `tools/korean/`, the whole harness, and
the AGI semantic parser as currently written (§5.3).

---

## 6. What the infrastructure buys: the AI-translation pipeline, per engine

The user's stated goal is that once the infrastructure exists, AI-assisted
translation is easy. Four steps: **extract → translate → bundle → render.** The
blocker is different in each engine, and only one of the twelve cells is
genuinely missing.

| | SCUMM | AGI | SCI |
|---|---|---|---|
| **extract** | works — `harness/tools/jatrs.py` walks LECF/LFL and pulls translatable records from the game container [source] | works — `extract_msgs.py` reads LOGIC message sections, **2435 messages from SQ0** [measured, P1] | **missing for SCI0** — the text lives in TEXT resources, `harness/s1patch.py list` dumps them but nothing keys them |
| **translate** | out of scope here; the key question is settled — **14.0% of lines share their original text**, so the (room, script range) index is required [measured, P1] | settled — key is (logic, slot); **164 texts shared across 544 messages (22.3%)**, 0 collisions within one logic [measured, P1] | unsettled — no key has been proposed |
| **bundle** | works — `harness/tools/trslib.py` reads *and writes* SCVMTRS, and `jatrs.py` produces a complete `ja.trs` [source] | works — `.trs` reader landed on `wt/k6-agitrs-src` (`c7636fee10f`), version+encoding declared [measured, K6] | **works by a different route** — SCI0 patch files are extra files, originals untouched; proven end to end in S1/S2 |
| **render** | works for KO; JA/ZH work via the same path | works — K6 drew Korean AGI text from an external bundle with game files byte-identical [measured] | works — S2 drew Hangul in a real SCI0 game [measured] |

**The one missing step is SCI's extract-and-key.** Everything else is built.
Concretely, what SCI needs before an AI translation pipeline runs on it:

1. A TEXT/MESSAGE extractor with a stable key. `harness/s1patch.py` can already
   list and rewrite TEXT resources; what it lacks is the key discipline P1
   settled for the other two engines. SCI1+ has `RESOURCE.MSG` with a natural
   (module, noun, verb, cond, seq) tuple; SCI0 has bare TEXT resources whose
   only key is (resource number, string index). **[source]**
2. Nothing else. SCI0's *output* half is free (patch files), its font path is
   reachable (S2), and its parser no longer corrupts EUC-KR (S3).

**And the honest caveat about "easy".** The infrastructure makes the *mechanics*
easy. Three things it does not make easy, all measured elsewhere in this
project: 64.7% of SCUMM bundle records carry inline binary opcodes
(`FORMAT_PROPOSAL.md` §1.1), so a translator that treats records as text
corrupts them; SCUMM scripts size speech bubbles from the *original* widths
(`charset.cpp:1294` and the comment at `:1297-1300`), so a longer translation
overflows; and a Korean Hanja character in any of the three engines today reads
past the end of the glyph table (§3).

---

## 7. Ranked plan

### (i) Defects worth fixing now

1. **Bound the double-byte glyph index.** `engines/scumm/charset.cpp:318` plus
   narrowing `charset.h:67` from `0xD0` to `0xC8`. *Closes on:*
   `harness/i1defect.py` exiting 0, and the existing A/B captures for the
   Korean, Japanese and Chinese targets unchanged. Upstream-shaped (§5.4).
2. Nothing else qualifies. The census found 2 KO defects and they are the two
   halves of this one.

### (ii) Adoption work

3. **Add a lead-byte predicate to `Common::`** — `isLeadByte(CodePage, byte)`
   or equivalent — and route the 7 hand-rolled copies through it. This is the
   only genuinely missing piece of infrastructure (§2), and it is the same hole
   S3b and P1 each found from their own end. *Closes on:* `harness/i1cover.py`
   showing every site delegating, with the accept/reject counts unchanged
   per site (the point is to stop duplicating, not to change behaviour).
4. **`DBCSFontBase` under FontKorean and FontSJIS** (§4.3). *Closes on:* seven
   method bodies deleted, `harness/i1fonts.py` reporting 0 duplicated bodies
   between the two files, and A/B captures unchanged on both languages.
5. **Wintermute's `mapCodePage`** — `Common::kWindows949`/`932`/`936`/`950`
   instead of falling through to `warning()` + cp1252. Four lines, one engine,
   no Korean asset needed to justify it.

### (iii) Upstream-landable, in order

6. The §3 defect. 7. The S3 parser fold. 8. `DBCSFontBase`. 9.
`getTrsBundleName()`. 10. The hi-res layer, as an RFC. Rationale and reviewer
precedent in §5.4.

### (iv) Must stay as they are

- **The 81 quirk sites.** Korean Kyrandia's taller menus, Grim's renderer
  restriction, SCI's `UpscaledGfxDriver` row, FM-Towns' `putKanjiChar`
  reshaping. These are the localization, not debt.
- **The 34 fantrans sites.** `korean.trs`, `KOREAN.FNT`, font 1001,
  `message.map`, `CREDITS.HAN`, `HAN_NOTE.CPS`, the Grim md5 exemption.
  Removing any of them breaks patches users have on disk today.
- **The 13.8% coverage of the five `0xB0..0xC8` tests.** They match the glyph
  data. Widening them without widening the font is how §3 happened.
- **`GfxFontKorean` / `GfxFontSjis` as two classes** (§4.4).
- **The `.trs` header.** Measured impossible to version without a new magic
  (`FORMAT_PROPOSAL.md` §2.3).

---

## 8. Scope, and the probe

**No engine code changed.** The engine worktree is at its base commit with zero
modified files:

```
$ git -C repo/scummvm/.worktrees/t_ccb811ae log --oneline -1
3ca65017f27 Merge S3: the SCI parser no longer folds EUC-KR trail bytes
$ git -C repo/scummvm/.worktrees/t_ccb811ae status --short | wc -l
0
```

**Two probes were injected and both were reverted.** `harness/i1census.py` has
two failure modes and each was proven to bite: **[measured]**

1. An unaccounted branch — a `case Common::FI_FIN:` arm testing `KO_KOR` added
   to `engines/scumm/vars.cpp`. The census reported
   `*** UNCLASSIFIED *** engines/scumm/vars.cpp:675` and exited 1.
2. A moved line — a blank line inserted above the classified site. The census
   reported `*** MOVED *** engines/scumm/vars.cpp:669 classified quirk but the
   line no longer names KO_KOR` **and** two new unclassified sites, and exited 1.

Both reverted with `git checkout`; the clean run reports 0 unclassified, 0
stale, exit 0.

`harness/i1cover.py` and `harness/i1defect.py` carry the same guard by
construction: 10 and 18 transcribed source lines respectively, each checked
against the file, `*** SOURCE MOVED ***` and a non-zero exit if any has moved.

---

## 9. Reproducing every number here

```bash
cd ~/work/scummvm/.worktrees/t_ccb811ae/harness

python3 i1census.py              # §1     146/231/308/36/250/142, 0 unclassified
python3 i1census.py --list KO_KOR
python3 i1cover.py               # §2     17048 cp949 points, per-test coverage
python3 i1defect.py              # §3     exits 1; the defect, as a check
python3 i1fonts.py               # §4     6/15 identical, Big5 shares 1 of 7
bash    i1churn.sh               # §5     240 upstream, 0 vs added, 2 vs modified
bash    i1branches.sh            # §5.3   unmerged card branches
```

Every script derives the engine tree from its own location and accepts `I1ENG`
to override; none spells a card id.

---

## 10. Unmeasured, and load-bearing

1. **No Korean SCUMM, Kyrandia, Grim or Darkseed game has been run here.**
   Every §1 classification of those engines is source reading. The §3 defect is
   arithmetic on transcribed constants, not an observed crash — it says a read
   goes out of bounds, not that anyone has seen it corrupt a screen.
2. **Whether the 658 out-of-bounds Korean pairs occur in any shipped
   translation.** The 12 community `.trs` bundles are on disk
   (`FORMAT_PROPOSAL.md` §1.1); nobody has scanned them for leads in CA..D0.
   That scan is cheap and would upgrade §3 from "reachable" to "reached".
3. **The JA/ZH classification outside the sampled roots.** 501 branch sites in
   `kyra`, `director`, `sherlock` and others are enumerated but unclassified.
   The card permitted sampling; the conclusions about *proportions* are Korean's
   and should not be assumed to transfer.
4. **RU_RUS and HE_ISR are counted and nothing more.** 250 and 142 branch sites.
   Both are single-byte languages with different problems (Cyrillic code pages,
   BiDi — `common/unicode-bidi.cpp:136` already special-cases `HE_ISR`), and
   neither shares the double-byte machinery this document is about.
5. **That `DBCSFontBase` is behaviour-preserving.** §4.2 measures textual
   identity of six bodies, which is strong evidence and not proof; the A/B
   capture in the close condition is what would settle it.
