# A translation bundle standard and a font standard: what we already have, and what is missing

Written for card P1. Engine read at `faf6cc842c8` (branch `hires-text`), with
one leg run against `c7636fee10f` (branch `wt/k6-agitrs-src`, the only build
carrying both engines and the AGI bundle reader). Harness at `harness/p1*.py`,
`harness/p1*.sh` in this repo. Line numbers are only valid at those commits.

Every claim below is one of three kinds and says which:

- **[source]** — a file:line in the engine. Static reachability only.
- **[measured]** — a number this card produced by running something.
- **[unmeasured]** — stated because it is load-bearing and nobody has checked it.

No engine code was changed. One probe was injected to prove a check bites and
was reverted; §7 says so and shows the tree clean.

---

## Short answer

The user asked for three things. Measured against what is already in the tree,
they are not three pieces of new work:

| asked for | status |
|---|---|
| a new extension / standard for translation bundles that declares its own encoding | **half exists.** AGI's bundle already declares version and encoding; SCUMM's declares nothing and cannot be made to without a new magic. The measured reason is in §2.3. |
| a font format of our own | **exists, and is already versioned and engine-independent.** SVFN, `graphics/hires_text/bitmap_font.cpp:34`. The honest answer is that this is a documentation-and-relocation job, not a format job. §4 |
| a dedicated loader, plus re-ordering glyphs to the engine's encoding | **the re-ordering exists** and costs 0.29 ms and 18.8 KB per font. The *loader* is the real gap, and it is one adapter class with one genuinely missing method. §5, §6 |

The single most useful finding is negative, and it kills the obvious design:

> **A version field cannot be added to the existing SCUMM `.trs` header.**
> Every byte after the magic is already data, and every candidate sentinel was
> fed to the real loader: two of them kill the engine outright, one loads as an
> empty bundle, and only a **different magic** lets the game start. **[measured]**, §2.3

---

## 1. What is on disk today

### 1.1 The bundles

`harness/p1trs.py` parses every `*.trs` in the community collection the way
`ScummEngine::loadLanguageBundle()` does (`engines/scumm/string.cpp:2359-2420`).
**[measured]**

```
files named *.trs / *.TRS: 48
SCUMM SCVMTRS bundles:     12
other files with a .trs name: 36
totals: 42548 lines, 4931 script ranges, 3794660 bytes over 12 bundles
```

Two corrections to the record the card carried in:

- It is **12 bundles, not 13.** The 13th (`Blackwell Unbound (GOG.com)/korean.trs`)
  begins `Photo 1/` — it is an AGS translation, a different engine's format that
  happens to share the name. **[measured]**
- The other 36 are SMUSH subtitle scripts (`#define ` / `\r\n#define`), which are
  not bundles at all. A standard that claimed the `.trs` extension would be
  claiming a name three unrelated formats already use. **[measured]**

The bodies are CP949, but they are **not text**. `harness/p1trsesc.py`:
**[measured]**

```
translated records examined:            42548
records containing a 0xFF SCUMM escape: 27531
records that fail CP949 as stored:      27540
records that fail CP949 after escapes are stripped: 122
```

64.7% of records carry binary SCUMM opcodes inline. So "the bundle body is
CP949" is false as stated: it is CP949 text **interleaved with engine opcodes
whose operands are arbitrary bytes**. Any proposal that says "declare the
encoding and decode the body" has to carve out the escapes first — this is a
real constraint on a UTF-8 move, and §3 measures what it costs.

### 1.2 The fonts

`harness/p1fonthdr.py` dumps the SVFN header of every `.fnt` under
`gamedata/` and `fonts/`. **[measured]**

```
SVFN fonts found: 141   non-SVFN .fnt files: 52
by version:  [(1, 141)]
by codepage: [('-(latin1)', 58), ('cp932', 10), ('cp949', 73)]
```

**Every font on disk is version 1.** Version 2 exists in the reader
(`bitmap_font.cpp:40-44`) and the in-engine baker writes it
(`font_baker.cpp:98` writes version 2, `:111` the cmap offset), but nothing has
ever shipped one. That matters for §4: the format's newer half is unexercised
by any file a user has.

---

## 2. The bundle standard

### 2.1 The key question, measured on both engines

This is the part the card said not to hand-wave. Both engines' keys were
measured against their own real data by `harness/p1key.py`. **[measured]**

```
SCUMM  12 bundles, 42548 lines, 762 rooms, 4931 script ranges
       5952 lines (14.0%) share their ORIGINAL text with another line
       in the same bundle

AGI    2435 messages, 2055 distinct English strings, 75 logics
       164 texts used by more than one (logic, slot), covering 544
       messages (22.3%)
       within a single logic, 0 messages share text with a sibling
```

The 544 the card quoted reproduces exactly. But the SCUMM number alone does not
settle anything, because "two lines share an English string" does not prove they
need different translations. `harness/p1scummkey.py` asks the question that does:
**[measured]**

```
groups of lines sharing one original text: 1723
  of those, groups whose translations are NOT all identical: 218 (607 lines)
  => 12.7% of duplicate-text groups genuinely need the room/script index
raw table sorted by original text (heuristic #3 needs this): 12 of 12 bundles
script ranges: 4931, ranges whose indexed order is not sorted by text: 0
```

So the honest statement of the key problem is:

- **AGI cannot use a text key.** 544 messages (22.3%) would collapse onto 164
  translations. Its `(logic, slot)` key is exact and free — the engine already
  holds both numbers at the call site.
- **SCUMM cannot use a text key either, but only barely**: 607 lines across 218
  groups in 12 shipped bundles genuinely receive different translations for the
  same English. That is 1.4% of all lines. It is small, and it is not zero, and
  a format that loses it silently mistranslates those 607 lines.
- **SCUMM has no alternative key available.** A SCUMM string is an inline
  literal in a script; there is no stable number to name it by. This is the
  asymmetry: AGI's key is a property of the game data, SCUMM's is a property of
  the *moment* (`_currentRoom` and `vm.slot[_currentScript]`,
  `string.cpp:2464-2473`). **[source]**

**Therefore a single key does not exist, and the choice is not between AGI's
key and SCUMM's — it is between carrying both and not having a standard.**

### 2.2 What that means for a header

A cross-engine bundle must therefore carry a **key kind** in its header, and
each engine supplies the key it can produce:

| engine | key kind | supplied from |
|---|---|---|
| AGI | `(logic, slot)` u16 pair | `print()` opcode operands, already in hand [source] |
| SCUMM | original text + `(room, scriptKey)` | `_currentRoom`, `vm.slot[_currentScript].where/number` (`string.cpp:2464-2473`) [source] |
| SCI | **unknown** | not measured by this card; SCI0 translation today is a resource patch, not a bundle (`SCI0_PARSER_ASSESSMENT.md`) [unmeasured] |

That is two key kinds, not one, and a reviewer will reasonably ask whether a
"standard" with two key kinds is a standard. My answer in §8 is that it is —
but only if the second one is added when a second engine needs it, not now.

### 2.3 The measurement that kills the in-place upgrade

Can the existing SCUMM header declare a version or an encoding? The header is
`'SCVM' 'TRS '` and then immediately a u16 line count (`string.cpp:2359-2369`),
so any new field has to occupy a value the current loader will not mistake for
data. **[source]**

`harness/p1hdrprobe.py` builds each candidate as a real file, puts it in a copy
of a real game directory, and runs the engine. **[measured]**

```
candidate       exit   loaded  started  fault
ok           timeout        1      yes  -
agitag       timeout        -       NO  ERROR: Invalid language bundle file!
zero         timeout        0      yes  -
sentinel     timeout        -       NO  ERROR: Invalid language bundle file!
newmagic     timeout        -      yes  -
truncated         -6        -       NO  Assertion `idx < _numTranslatedLines' failed
```

`started` is the column that matters and is the one that a naive probe gets
wrong. `error()` is `NORETURN` (`common/textconsole.h:87`), so a rejected bundle
**kills the engine instance** and ScummVM drops back to its launcher — the
process is still alive at the timeout either way. The probe therefore keys on
`allocResTypeData`, which only a surviving engine emits. **[source]** + **[measured]**

Read off that table:

- **`AGI1` variant tag → the game does not start.** This is not hypothetical:
  it is what AGI ships today, and `harness/p1cross.sh` reproduces it end to end
  — a user with both engines and one bundle directory, feeding the AGI bundle to
  SCUMM, gets `Assertion 'idx < _numTranslatedLines' failed` and an abort.
  **[measured]** The two formats already share both the magic and the file name,
  deliberately (`engines/scumm/trs_bundle.h`, and the AGI twin at
  `c7636fee10f:engines/agi/trs_bundle.h`), so this collision is reachable today.
- **A sentinel line count does not work either.** `0xFFFF` fails the same way.
  `0` is worse than failing: the game starts, `_existLanguageFile` becomes true
  at `string.cpp:2367`, and the bundle is silently empty — nothing is
  translated and nothing is reported.
- **Only a different magic lets the game start.** `newmagic` is the single
  candidate where the old loader declines cleanly at `string.cpp:2363` and the
  game runs untranslated.

**This is the measured answer to "name the extension".** The extension is not
the interesting decision; the *magic* is. A new format must not begin
`SCVMTRS `, because the one existing variant that does already aborts a shipped
engine.

The good news for the other direction: **AGI handles the collision correctly
today.** Fed a SCUMM bundle, it declines with a diagnosable message and plays on
— `AGI: 'korean.trs' is a '' bundle, not an AGI one`, then
`the game's own text will be used`. **[measured]** The AGI loader checks its
variant tag before trusting anything (`c7636fee10f:trs_bundle.cpp:75-82`). The
difference is that AGI was written knowing SCUMM's format existed; SCUMM was not.

### 2.4 Proposed layout

Extension **`.trb`** (translation bundle), magic **`TRBUNDL1`**. Both chosen so
that no existing loader is handed the file at all: the SCUMM loader is name-gated
on `korean.trs` / `<lang>.trs` (`engines/scumm/trs_bundle.h`), so a different
extension means the §2.3 crash is unreachable by construction, and the magic
differs so that even a renamed file declines cleanly.

Every field below is justified by something measured above; nothing is included
"for future use".

```
offset size  field           justified by
------ ----  --------------  ---------------------------------------------------
     0    8  magic           "TRBUNDL1". §2.3: a new magic is the ONLY header
                             change that leaves shipped SCUMM loaders working.
     8    2  formatVersion   1. §1.2: SVFN needed a second version within one
                             year of shipping; assume this will too.
    10    2  encoding        0 = UTF-8, else a Windows code page number.
                             §3 measures why a reader must know this rather
                             than sniff: 0 of 12 bundles are ambiguous between
                             CP949 and UTF-8, but the failure mode when wrong
                             is mojibake, not an error.
    12    2  keyKind         1 = (u16,u16) numeric pair; 2 = text + context.
                             §2.1: the two engines' keys are genuinely
                             different and neither can be dropped.
    14    2  flags           bit 0: body holds engine escape opcodes.
                             §1.1: 27531 of 42548 SCUMM records do; an AGI
                             record never does. A consumer that decodes the
                             body as text must know which it is holding.
    16    4  lineCount       u32, not u16. §1.1: the largest real bundle is
                             9099 lines, but IJFOA is 9099 of a 42548 total
                             and a merged multi-language bundle would exceed
                             u16 immediately.
    20    4  langCode        4 ASCII bytes, e.g. "ko  ". §6.1: today the
                             LANGUAGE IS IN THE FILE NAME, which is why
                             ja.trs works and japanese.trs silently does not
                             (IMPLEMENTED.md §3). Putting it in the file makes
                             that failure diagnosable.
    24    4  keyTableOff     absolute offsets, checked against the file size on
    28    4  keyTableSize    load. Both AGI's loader and SVFN's already do this
    32    4  bodyOff         (c7636fee10f:trs_bundle.cpp:96-113 and
    36    4  bodySize        bitmap_font.cpp:151-164); neither format trusts a
                             shipped file.
    40    8  reserved        zero.
------ ----
    48       end of header
```

Key table, `keyKind == 1` (AGI): `lineCount` entries of
`u16 logic, u16 slot, u32 bodyOffset`, sorted by `(logic, slot)`, exactly the
shape AGI already writes and binary-searches (`c7636fee10f:trs_bundle.cpp:118-131`).

Key table, `keyKind == 2` (SCUMM): `lineCount` entries of
`u32 originalOffset, u32 translatedOffset, u8 room, u8 pad, u16 scriptKeyIndex`,
plus the room/script range index SCUMM already carries. This is deliberately a
re-encoding of the existing structure rather than a redesign: §2.1 measured
that its three-heuristic search is *used*, and 12 of 12 bundles already satisfy
both orderings it requires.

Where the code lives: **`common/`**, not `graphics/`. A translation bundle has
nothing to do with drawing, and the file's only dependencies are
`Common::SeekableReadStream`, `Common::Path` and `Common::Language` — which is
already true of both existing implementations.

---

## 3. Should SCUMM's bundles move to UTF-8?

The user's suggestion, and the tempting argument for it is that the render path
is already code-point based: `legacyGlyphIndex()` decodes the font's code page
into a code-point map (`bitmap_font.cpp:330-352`) and `glyphIndex(uint32)` is
the lookup (`:354`). So the bytes in the bundle look like a private detail of
the loader. **[source]**

They are not. `harness/p1utf8.py` takes the real translated strings, re-encodes
them as UTF-8, and runs the **engine's own** character walker over both —
`is2ByteCharacter()` at `engines/scumm/charset.h:63`, whose KO_KOR branch is the
hardcoded test `c >= 0xB0 && c <= 0xD0`, called from `string.cpp:1265`, `:1542`,
`:1698` and `string_v7.cpp:79`, `:136`, `:168`. **[source]** + **[measured]**

```
translated strings with non-ASCII text: 11910
characters they really contain:         197967

the engine's own walker over the CP949 bytes stored today:
    198015 characters counted, 9 strings mis-framed
the same walker over the SAME text as UTF-8:
    382335 characters counted, 11910 strings mis-framed
```

**Every single non-ASCII string breaks.** The engine counts 382335 characters
where there are 197967, because a UTF-8 lead byte `0xEA`–`0xED` is not in
`0xB0..0xD0` and every continuation byte is counted as its own character. Line
breaking, cursor advance and the escape scanner all sit on that walker.

So the answer to "can we move SCUMM's bundles to UTF-8 now" is **no, not as an
isolated change** — it is not a bundle change at all, it is a change to six
call sites in the engine's text layout, and those six sites serve Japanese and
Chinese as well as Korean. That is exactly the shape of work the standing rule
says must not change existing-platform behaviour.

Ranked, as the card asks:

- **(A) leave the existing bundles alone — recommended.** 12 community files,
  42548 lines, zero work, zero risk. The conversion already happens at the font
  boundary and costs 0.29 ms once per font (§5).
- **(B) add a version field to the existing header — rejected on measurement.**
  §2.3: there is no value that both declares a version and leaves shipped
  loaders working.
- **(C) a new format with a new magic and extension — the proposal in §2.4,
  but not now.** It is worth doing when a *second* consumer needs it. Today the
  only consumer that would benefit is a bundle writer that does not exist.

---

## 4. The font standard: document it, do not change it

SVFN already is a standard, and already satisfies most of what the user asked
for:

- it is **engine-independent** — `graphics/hires_text/`, used by SCUMM through
  an `#include` at `engines/scumm/hires_text.cpp:35` and owned by nothing under
  `engines/` **[source]**
- it is **versioned** — `kMaxVersion = 2` (`bitmap_font.cpp:44`), with a
  length-extended header (`kHeaderSize` 32, `kHeaderSizeV2` 36, `:36`/`:41`)
- it **declares its own encoding** — the header's code page field, read at
  `:129` and mapped at `:225-245`
- it is **unambiguous against the engine's own fonts** — those start with a
  length byte that is always 2 (`:31-33`), so the magic distinguishes them.
  `harness/p1fonthdr.py` confirms it on real files: 52 non-SVFN `.fnt` files,
  49 of them starting `0x02`. **[measured]**

### 4.1 Does version 2 need to be adopted?

This is the one real format decision, and it has an arithmetic answer per font.
A v2 font replaces the code-page ordering with an 8-byte-per-glyph code point
table (`kCmapEntrySize`, `:53`), which pays for itself only through the
code-page holes it can then drop.

`harness/p1unreach.py` finds the holes. **[measured]**

```
hrjpn00.fnt  codepage 932, 6879 glyphs
  reachable:            6024
  byte pair does not decode / decodes to U+FFFD:  846
  code point already claimed by a lower index:      9
```

`harness/p1blank.py` prices them: those 846 slots are stored as blank cells and
**0 of them hold ink**, so they are pure padding — 216576 bytes, **12.3% of that
file**. **[measured]** The Korean fonts have no holes at all (0 of 2350).

`harness/p1v2cost.py` then computes the conversion over all 141 fonts:
**[measured]**

```
total v1 119519436 bytes -> v2 119304304 bytes (-215132, -0.2%)
fonts that would GROW: 131, shrink: 10, unchanged: 0
```

**So version 2 should not be adopted wholesale.** It is right for the ten CP932
fonts and wrong for the other 131, which is precisely what a *per-font* choice
is for — and the format already supports exactly that, because the reader
accepts both versions and `glyphIndex()` branches on which table is present
(`:359-367`). Nothing needs to change. The recommendation is to **bake CJK fonts
with holes as v2 and everything else as v1**, and to note that no v2 file has
ever shipped, so the first one to do so is exercising an untested path — the
round-trip is covered by `test/graphics/hires_text_bitmap_font.h` but not by any
file a user has. **[measured]** + **[unmeasured]**

### 4.2 What "our own font format" would still need before it is a standard

Three gaps, none of them format changes:

1. **It lives in `graphics/hires_text/`, a directory named after one feature.**
   A format two engines read should be `graphics/` proper, next to the other
   font classes. This is a move, not a redesign.
2. **The written spec is in two places and neither is normative** —
   `graphics/hires_text/README.md:90-113` and `IMPLEMENTED.md:38-45`.
   The byte layout in §2.4's style should exist for SVFN too, in the tree.
3. **The baker is split.** `tools/korean/mkfont.py` writes v1;
   `graphics/hires_text/font_baker.cpp` writes v2. Two writers for one format
   is how a format drifts. **[source]**

---

## 5. Re-ordering glyphs to the engine's encoding: it exists, and here is its cost

The card asks what this means precisely, and whether it is a load-time transform
or a file rewrite. Measured: **it is a load-time transform, it already exists,
and it is cheap.**

`legacyGlyphIndex()` (`bitmap_font.cpp:330-352`) builds a code point → glyph map
once per font, on the first lookup, by walking every glyph index, turning it
into a byte pair with `legacyIndexToBytes()` (`:259-296`), and decoding that
pair through `Common::U32String`. `harness/p1cmap.cpp` links the engine's own
`libgraphics.a` and measures it on the real files. **[measured]**

```
gamedata/sq0/hrkor16.fnt   2350 glyphs, cp949, 1bpp 16x16
  first lookup (builds the map): 0.292 ms -> U+AC00 = glyph 0
  111720 further lookups: 1.005 ms total, 9.0 ns each
  glyphs reachable by SOME BMP code point: 2350 of 2350
  map entries: 2350, 18800 bytes at 8 bytes per entry

fonts/hrjpn16/hrjpn00.fnt  6879 glyphs, cp932, 8bpp 16x16
  first lookup (builds the map): 0.332 ms -> U+AC00 = glyph -1
  glyphs reachable by SOME BMP code point: 6024 of 6879 (855 unreachable)
  map entries: 6024, 48192 bytes at 8 bytes per entry

gamedata/mi2kor/hrlat00.fnt  256 glyphs, latin1
  first lookup: 0.000 ms   (single-byte fonts index by the byte itself, :341)
```

**0.29 ms and 18.8 KB for a Korean font; 0.33 ms and 48 KB for a Japanese one,
paid once per font, per run.** A steady-state lookup is 9 ns. There is no
performance argument for a file rewrite, and the 855 unreachable CP932 glyphs
are a *bake* artefact (§4.1), not a lookup one — 846 are Shift-JIS holes the
face never filled and 9 are genuine duplicate mappings
(e.g. glyph 1207 at `8790` → U+2252, already glyph 159). **[measured]**

The one thing worth saying in the document that the code does not say: this
transform depends on `encoding.dat` being reachable at run time, and without it
**every CJK lookup returns −1** — the map comes back empty and is poisoned with
a sentinel so it is not rebuilt per character (`:344-348`). That is a deployment
dependency of the font format, and a format specification should state it.
**[source]**

---

## 6. The dedicated loader, and what SCI would need

### 6.1 What a GfxFont-style engine binds to

`harness/p1sciadapt.py` enumerates every virtual on `GfxFont`
(`engines/sci/graphics/scifont.h:37-49`) and writes a disposition for each
against `HiResBitmapFont`. It is a census: a new virtual with no written reason
fails it. **[measured]**

```
7 virtuals, 7 accounted, 0 unaccounted

  getResourceId  <- nothing                the adapter holds the id it was
                                           constructed with (fontkorean.cpp:45-47)
  getHeight      <- cellHeight()           direct
  getCharWidth   <- glyphMetrics().advance direct, once uint16 -> code point
  getCharHeight  <- glyphMetrics().height  direct
  draw           <- glyphData() + renderer needs a blit target; GfxFontKorean
                                           goes through GfxScreen::putHangulChar
                                           (fontkorean.cpp:70-73)
  drawToBuffer   <- glyphData()            direct blit; the simpler SCI32 path
  isDoubleByte   <- ***nothing***          not a font question in SVFN
```

Injecting an eighth virtual makes it report `8 virtuals, 7 accounted, 1
unaccounted` and exit 1; the injection was reverted (§7). **[measured]**

**Six of the seven are mechanical. The seventh is the whole problem.**
`isDoubleByte(uint16 chr)` asks "is this byte a lead byte", which is a question
about the caller's *encoding*, and SVFN has no answer because it is indexed by
code point and has no bytes. This is the same finding S3b reached from the other
end — the caller owns byte-pair assembly (`text16.cpp:214-216`) — arrived at
here by asking what a font could supply.

So the two cards meet at a single statement: **an SVFN-backed `GfxFont` is
straightforward except that `isDoubleByte` has no font-side source, and
therefore whoever adds that adapter must also decide where SCI's byte→code-point
conversion happens.** S3b already recommends the minimal version of that
decision (one `decodeChar()` virtual with a behaviour-preserving default, used
only by `controls16.cpp`), and nothing measured here contradicts it.

### 6.2 What the loader looks like

`GfxFontSvfn : public GfxFont`, constructed with a file name and the code page
the *caller* speaks, holding a `Graphics::HiResBitmapFont` and a decoder. The
existing Korean path is untouched: `GfxCache::getFont()` picks `GfxFontKorean`
for `fontId == 1001 && language == KO_KOR` (`cache.cpp:70-71`) and a third
branch alongside it adds a case without changing one. **[source]**

That is the same shape as every other Korean hook in SCI —
`if (language == KO_KOR)` at `cache.cpp:70`, `text16.cpp:462`, `:478`,
`paint16.cpp:595` — which is what a reviewer prefers over a new abstraction,
and matches the guidance recorded on S3b.

---

## 7. Scope, and what this card did not do

**No engine behaviour changed.** The engine worktree is at its base commit with
zero modified files:

```
$ git -C repo/scummvm/.worktrees/t_03f8c10c log --oneline -1
faf6cc842c8 Merge Z1: retire hi-res text on the single-buffered screens too
$ git -C repo/scummvm/.worktrees/t_03f8c10c status --short | wc -l
0
```

One probe was written and removed: an extra virtual was injected into
`engines/sci/graphics/scifont.h` to prove `harness/p1sciadapt.py` fails on an
unaccounted method (it reported `8 virtuals, 7 accounted, 1 unaccounted`, exit
1), then reverted with `git checkout`. The clean run reports 7/7/0 and exit 0.
**[measured]**

**This card does not block S4.** Nothing here is a precondition for SCI Korean
input: §3 concerns SCUMM bundles, which SCI does not read, and §6 describes an
adapter S4 does not need if it follows S3b's recommendation.

---

## 8. Ranked recommendation

### Adopt now, inside this project

1. **Nothing to the bundle format.** §3 measured that a UTF-8 move breaks all
   11910 non-ASCII strings through `charset.h:63`, and §2.3 measured that the
   header has no room for a version. The current split — SCUMM CP949, AGI UTF-8,
   each declaring what it can — is the correct state, not a defect to fix.
2. **Bake CJK fonts that have code-page holes as SVFN v2.** §4.1: 12.3% of the
   Japanese font is padding a v2 file would not carry. This is a change to the
   baking tool, not to the format or any engine.
3. **Write the SVFN byte layout into the tree** as a normative spec, and move
   the format out of `hires_text/` when a second engine consumes it. §4.2.
4. **State `encoding.dat` as a runtime dependency of the font format.** §5.

### Standalone upstream RFC, with its own reviewer

5. **The `.trb` bundle standard of §2.4.** It is a genuinely new file format
   affecting three engines and an existing fan-translation community's assets.
   The measured findings that make it RFC-shaped rather than patch-shaped:
   two irreducible key kinds (§2.1), a magic collision that already aborts a
   shipped engine (§2.3), and bodies that are not pure text (§1.1).
6. **A shared `GfxFont` adapter for SVFN** (§6), which is only worth proposing
   after S4 has shown SCI needs it. Adding an adapter for a font nobody has
   asked SCI to load is the abstraction-before-the-third-case mistake.

### Explicitly rejected

7. **Adding a version or encoding field to the existing `.trs` header.**
   Measured impossible without a new magic (§2.3); the one variant that tries
   (`AGI1`) aborts SCUMM today (`harness/p1cross.sh`).
8. **Converting all 141 fonts to SVFN v2.** Measured to cost bytes on 131 of
   them and save on 10 (§4.1).

---

## 9. Compatibility

| asset | effect of everything recommended above |
|---|---|
| the 12 community CP949 `.trs` files | **unchanged and unread by any new code.** Recommendation 1 is to make no change. If §2.4's `.trb` is ever built, it uses a different extension and a different magic, so the SCUMM loader is never handed one — measured as the only candidate that lets the game start (§2.3). |
| the 36 SMUSH `.TRS` subtitle files | unaffected; they were never bundles. A `.trb` extension also stops a future standard from claiming a name they already use. |
| the AGS `Blackwell Unbound/korean.trs` | unaffected, and now correctly excluded from the count (§1.1). |
| AGI's `korean.trs` (ours) | unchanged. Already declares version and encoding and already declines a SCUMM bundle diagnosably — measured (§2.3). |
| the 141 SVFN fonts baked today | **all still load.** Recommendation 2 changes what a *future* bake writes; the reader has accepted both versions since `kMaxVersion = 2`, and `glyphIndex()` branches on which table the file carries (`:359-367`). |
| SCUMM, FM-Towns, PC-Engine, Mac rendering | untouched. No engine file is modified by any now-work recommendation. |
| the 2020 SCI Korean fan translation | untouched. §6.2's adapter is an added branch in `GfxCache::getFont()`, not a replacement of `GfxFontKorean`. |

---

## Appendix: reproducing every number here

```
python3 harness/p1trs.py            # 12 bundles, 42548 lines, 4931 ranges
python3 harness/p1trsesc.py         # 27531 records carry SCUMM escapes
python3 harness/p1key.py            # SCUMM 14.0% dup text; AGI 544 / 22.3%
python3 harness/p1scummkey.py       # 218 groups (607 lines) need the index
python3 harness/p1utf8.py           # 11910 of 11910 strings break under UTF-8
python3 harness/p1hdrspace.py       # what the loader computes per candidate
python3 harness/p1hdrprobe.py       # what the loader DOES per candidate
bash    harness/p1cross.sh          # each engine given the other's bundle
python3 harness/p1fonthdr.py        # 141 SVFN fonts, all version 1
python3 harness/p1unreach.py        # 846 Shift-JIS holes + 9 duplicates
python3 harness/p1blank.py          # those holes are 12.3% of the file
python3 harness/p1v2cost.py         # v2 costs bytes on 131 of 141 fonts
bash    harness/p1build.sh          # build the libs p1cmap links against
bash    harness/p1cmap.sh           # 0.29 ms / 18.8 KB per font, 9 ns a lookup
python3 harness/p1sciadapt.py       # GfxFont census: 7 virtuals, 1 with no source
python3 harness/p1check.py          # every file:line cited above still resolves
```
