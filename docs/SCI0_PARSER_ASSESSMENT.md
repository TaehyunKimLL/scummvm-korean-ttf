# SCI0 and the Korean parser work: what transfers

Written for card S1. Engine read and run at `59db2f40` (branch `hires-text`);
harness scripts at `harness/s1*.py`, `harness/s1*.sh` in this repo. Line
numbers are only valid at that commit.

Every claim below is one of three kinds and says which:

- **[source]** — a file:line in the engine. Static reachability only.
- **[measured]** — a number this card produced by running something.
- **[unmeasured]** — stated because it is load-bearing and nobody has checked
  it.

---

## Short answer

**SCI0 is a better target than AGI was, and a worse one than the presence of
`GfxFontKorean` suggests.** The rendering machinery is real and already wired
for Korean, but it is wired for *SCI1-era Korean fan translations*, and three
of the four things a Korean SCI0 would need are missing in ways that are
engine work, not data work:

| K-chain piece | SCI0 status |
|---|---|
| Hangul rendering | **present and reachable**, but only for a game the detection table calls `KO_KOR` [source] |
| said() room filter | **present and richer than AGI's** — 772 said() specs over 256 vocab groups in a real SCI0 game [measured] |
| Semantic parser over the dictionary | **transfers with the dictionary rebuilt**, format is a near-twin of WORDS.TOK [measured] |
| Korean *input* | **absent, and worse than AGI's** — the text control is byte-indexed and the tokenizer corrupts EUC-KR [measured] |
| Translated text without touching originals | **works today**, proven end to end [measured] |

The interesting finding is the last row and the one above it. The *output*
half of a Korean SCI0 is nearly free — a patch file translated the intro box
of a real SCI0 game with the originals untouched, first try. The *input* half
is blocked by a defect that is 8 lines of engine code and would break nothing
if fixed.

---

## Test data: we now have an SCI0 game

There was none in `gamedata/`. There is now:

```
https://downloads.scummvm.org/frs/demos/sci/fangame/Cascade_Quest_Demo.zip
-> gamedata/sci0cascade
```

Freeware, no purchase. **[measured]** ScummVM detects it as
`sci:sci-fanmade / "Cascade Quest (DOS/English)"` from the table row at
`detection_tables.h:6792`, and it runs: the intro box and the parser prompt
both drew under `builds/sci0/scummvm`
(`harness/s1detect.sh`, `harness/s1sci0run.sh`; captures `/tmp/s1en/t7.png`).

Its resources, read the way `readResourceMapSCI0()` reads them
(`resource.cpp:1853-1900`) — `harness/s1sci0inv.py`: **[measured]**

```
view 210 | pic 79 | script 132 | text 113 | sound 18
vocab 9  | font 7 | cursor 3   | patch 6
577 map entries, every resource uncompressed
vocab: 0, 900, 901, 994..999      font: 0, 1, 3, 4, 8, 9, 999
message resources: 0
```

It is a parser game with a full SCI0 dictionary, which is exactly the shape
the card wanted. The one caveat: it is a **demo**, so its dictionary (1,600
words / 749 groups) is smaller than a shipped Sierra SCI0 title's, and its
scripts are a subset. Conclusions about *structure* hold; conclusions about
*size* are a lower bound.

---

## 1. Does the Korean font path reach an SCI0 game?

**Yes structurally, no in practice, and the gate is the detection table — not
the font id.** [source]

The card guessed the block would be `fontId == 1001` being an SCI1-era
convention. It is not. Three separate things have to line up, and only one of
them is about 1001:

**a. The language comes from the detection row, and cannot be overridden.**
`SciEngine::getLanguage()` returns `_gameDescription->language`
(`sci.cpp:834`) — the md5-matched table row, not a config key. Every Korean
branch tests it. `AdvancedMetaEngineDetectionBase::detectGame()` *rejects* a
row whose language disagrees with the configured one
(`advancedDetector.cpp:772-774`), so `language=ko` in the config does not
promote an English row; it demotes it.

**[measured]** `harness/s1detect.sh` on the SCI0 game, with and without
`language=ko` in the config: both print
`sci:sci-fanmade  Cascade Quest (DOS/English)`. The key changes nothing.

And the fallback detector cannot produce Korean either:
`determineGameLanguage()` (`metaengine.cpp:514-570`) reads the `#X` splitter
out of `text.000` via `charToScummVMLanguage()` (`metaengine.cpp:401-419`),
whose cases are F/S/I/G/J/P — **there is no 'K'**. Same for the SCI-side
enum: `kLanguage` (`sci.h:125-132`) has no Korean value at all.

So: **a Korean SCI0 game requires a detection-table row.** That is the
structural answer, and it is a one-line row, not an engine change.

**b. Font 1001 is never requested by the script — the engine forces it.**
This is the part the card's premise had backwards. `GfxText16::Box()`,
`Size()` and `Draw()` each call `SwitchToFont1001OnKorean()`
(`text16.cpp:463, 479, 585`), which **sniffs the string for EUC-KR bytes and
calls `SetFont(1001)` itself** (`text16.cpp:735-754`). The game's own scripts
never mention 1001. A Korean SCI0 game would get font 1001 for free the moment
its language is `KO_KOR` and its text holds Korean bytes.

**c. The 640x400 is the *driver*, not `_upscaledHires`.** This corrects
`SCI_AGI_ASSESSMENT.md`, which reads the Korean path as writing into an
upscaled display screen through `_upscaledWidthMapping[]`. It does not.
`GfxScreen`'s constructor sets `_upscaledHires` away from `DISABLED` **only
for Macintosh** (`screen.cpp:56-67`); a DOS Korean game leaves it
`GFX_SCREEN_UPSCALED_DISABLED` and the mapping arrays zeroed
(`screen.cpp:113-120`). The scaling comes from a driver row:

```cpp
// drivers/init.cpp:95 — the whole Korean graphics story, in one line
{ kRenderDefault, kPlatformUnknown, SCI_VERSION_0_EARLY, SCI_VERSION_1_1,
  GID_ALL, Common::KO_KOR, kUnused, INITPROCS1(UpscaledGfx), 0 },
```

`UpscaledGfxDriver` keeps its own 640x400 `_scaledBitmap`, scales the game
picture 2x into it (`upscaled.cpp:186-191`), and `drawTextFontGlyph()` writes
the glyph into it unscaled at `x<<1, y<<1` (`upscaled.cpp:147-153`). **That
row already spans `SCI_VERSION_0_EARLY`**, so the driver half needs no change
for SCI0 whatsoever.

The coupling worth knowing: `_hiresGlyphBuffer` is allocated **only** when
`_gfxDrv->driverBasedTextRendering()` (`screen.cpp:150-151`), which is true
for `UpscaledGfxDriver` and false for the default one
(`gfxdriver_intern.h:45, 104`). `GfxFontKorean`'s constructor does **not**
check this, unlike `GfxFontSjis` which errors out (`fontsjis.cpp:35-37`). So
font 1001 with a non-upscaled driver is `memset(nullptr, 0xff, 256)`. It is
safe today only because init.cpp:95 makes the two co-occur.

---

## 2. Text input: same `EditControl`, and it is byte-indexed

**[source]** SCI0 and SCI1 share one path. `EditControl` is kernel 0x19 in
the default table (`kernel_tables.h:1079`) and maps to `kEditControl`
(`kernel_tables.h:701`) → `GfxControls16::kernelTexteditChange()`
(`controls16.cpp:160`). No SCI0/SCI1 split anywhere in it.

The AGI blocker holds here too, and then some.

**Keystrokes arrive as one byte.** `EventManager::getScummVMEvent()` sets
`input.character = ev.kbd.ascii` (`event.cpp:317`); `>= 0x80` is remapped
through `codePageMap88591ToDOS[]` and is *dropped entirely* unless the game's
font 0 has more than 0x80 glyphs (`event.cpp:334-341`, `_fontIsExtended` from
`detectFontExtended()`, `resource.cpp:2816`). There is no `EVENT_TEXTINPUT`
and no IME — same finding as K1.

**The control inserts one byte per keypress and measures per byte:**

```cpp
// controls16.cpp:241 — a code point above 255 cannot arrive
} else if (eventKey > 31 && eventKey < 256 && textSize < maxChars) {
// controls16.cpp:270-272 — width summed one BYTE at a time
while (*textPtr)
    textWidth += _text16->_font->getCharWidth((byte)*textPtr++);
// controls16.cpp:126-128 — cursor x likewise
for (int16 i = 0; i < curPos; i++)
    textWidth += _text16->_font->getCharWidth((unsigned char)text[i]);
```

So a two-byte Korean syllable is two cursor positions, two width lookups, and
one backspace deletes half of it. This is the same class of defect K2 fixed in
AGI by widening `_prompt` to `uint32[42]` — but **SCI's buffer is a
`Common::String` in engine memory that is written back to the game's own heap**
(`_segMan->strcpy_(textReference, text.c_str())`, `controls16.cpp:295`), so
widening it is not available. A composer would have to emit EUC-KR bytes into
that string and then teach the three loops above to step by
`_font->isDoubleByte()`. That is the SCI counterpart of K2, and it is smaller
than K2 was.

**SCI has its own remap table, and it is unreachable here.**
`Vocabulary::checkAltInput()` (`vocabulary.cpp:397-449`) does exactly what an
IME does — substring replacement over the input buffer, driven by data — and
is called from the edit control (`controls16.cpp:255, 286`). It was added for
Japanese romaji input (`11d9f1ec543`, 2010). It is gated three ways
(`vocabulary.cpp:398-403`): `vocab.913` must exist, `SELECTOR(parseLang)` must
exist, and `parseLang` must not be 1.

**[measured]** In the SCI0 game (`harness/s1sci0said.py`): `vocab.913`
**absent**, and `vocab.997` lists 401 selectors of which `parseLang`,
`printLang`, `subtitleLang` are all **ABSENT**. That is not this game being
odd — `parseLang` is in `sci1Selectors[]` (`static_selectors.cpp:57`), added
at index 83, and `checkStaticSelectorNames()` only appends that block when
`getSciVersion() > SCI_VERSION_01` (`static_selectors.cpp:188`).

**So `checkAltInput()` is structurally unreachable in SCI0.** Two independent
gates, both version-intrinsic. That is a real structural answer, and it is
*specific*: the mechanism exists, SCI0 just predates the selector it keys on.
Reaching it would mean relaxing the `parseLang` gate, which is a behaviour
change for every SCI1 game and needs its own justification.

---

## 3. The tokenizer corrupts EUC-KR, and it is 8 lines

This is the defect the card did not anticipate and the most useful thing here.

`Vocabulary::tokenizeString()` (`vocabulary.cpp:722-771`) lower-cases **every**
byte of the input through a 256-entry table, including the trail byte of a
double-byte character:

```cpp
// vocabulary.cpp:737-739
if (Common::isAlnum(c) || (c == '-' && wordLen) || (c >= 0x80)) {
    currentWord[wordLen] = lcMap[c];
```

`c >= 0x80` was added so high-byte languages pass through — but `lcMap[]` is
not the identity up there. **[measured]** (`harness/s1euckr.py`, which parses
the table out of `vocabulary.cpp` rather than transcribing it):

```
lowerCaseMap: 34 of 256 byte values are remapped
  in 0x80..0xFF: 80->87 8E->84 8F->86 90->82 92->91 99->94 9A->81 A5->A4
EUC-KR lead 0xB0..0xC8: 2350 syllables
syllables altered by lowerCaseMap: 25
  B0A5 갈 -> B0A4 갇    B5A5 데 -> B5A4 덮    C0A5 웹 -> C0A4 웸
  B8A5 른 -> B8A4 륵    BFA5 엠 -> BFA4 엘    C7A5 표 -> C7A4 푄
  ... 25 in total, one per lead byte row
```

One trail-byte value (`0xA5`) is folded onto `0xA4`, silently turning 25
common syllables — 갈 른 데 엠 표 웹 among them — into different ones before
lookup. The Russian path already dodges this with a second table
(`lowerCaseMap866`, selected at `vocabulary.cpp:731-732`); the fix for Korean
is the same shape: **don't fold the trail byte of a double-byte lead**. That
is an 8-line change and is the single highest-value defect found by this card.

The other tokenizer fact, in the same measurement: the Korean fan translations
do **not** use the `#K` language splitter. `SwitchToFont1001OnKorean()` tests
`languageSplitter != 0x6b23` (`text16.cpp:737`) and then sniffs raw bytes —
and `charToLanguage()` (`state.cpp:203-220`) has no 'K' case, so a `#K` prefix
could never be parsed anyway. Korean SCI text is stored as bare EUC-KR.

### The font branch only sees 29% of EUC-KR

**[measured]** `SwitchToFont1001OnKorean()` fires only on lead bytes
`0xB0..0xC8` (`text16.cpp:741`), matching `checkKorCode()`
(`graphics/korfont.cpp:28-38`):

```
EUC-KR double-byte code points that decode: 8225
outside lead 0xB0..0xC8: 5875 (71%)
  e.g. compat jamo    ㄱㄲㄳㄴㄵㄶㄷㄸㄹㄺㄻㄼ
  e.g. fullwidth latin ！＂＃＄％＆＇（）＊＋，
  e.g. hanja           伽佳假價加
```

This is not just the sniff branch being narrow — **the font has no glyphs
there either.** `FontKoreanWansung::getCharData()` indexes
`((ch % 256) - 0xb0) * 94 + (ch / 256) - 0xa1` (`korfont.cpp:416`), i.e. the
same 25 rows of 94, so the 2,350 syllables are all there is.

A line of *only* jamo, fullwidth punctuation or hanja never switches to font
1001 and draws as garbage in the game's own font. For a composer this matters
directly: **partial Hangul composition states are jamo**, in the `0xA4` row.
Whatever draws a half-typed syllable at the prompt cannot use this font at
all, and must supply its own glyphs — as K3 did for AGI.

---

## 4. Where SCI0 text lives, and translating it without touching originals

**SCI0 has no `RESOURCE.MSG`.** [source] The message path is SCI1+:
`kGetMessage` (`kstring.cpp:476`) against `kResourceTypeMessage`, and the
Korean loader special-cases `message.map` (`resource.cpp:3118-3119`). SCI0
text is in two places instead:

- **TEXT resources**, NUL-separated strings indexed by order, fetched by
  `Kernel::lookupText()` (`kernel.cpp:888-920`) for `kDisplay`
  (`kgraphics.cpp:1275`) and `kGetFarText` (`kstring.cpp:447`).
- **`SCI_OBJ_STRINGS` blocks inside SCRIPT resources**
  (`script.cpp:294-336`).

**[measured]** In the SCI0 game (`harness/s1sci0said.py`):

```
displayable text total: 85,084 bytes
  76,586 in 113 TEXT resources   (90%)
   8,498 in 768 in-script strings (10%)
```

So 90% of the text is in a resource type that **patch files can replace
whole**, and the remaining 10% lives inside scripts, where a translation would
have to patch the script resource (offsets shift; the string block is
length-prefixed per block, `script.cpp:273`).

### Proven: a translated SCI0 game with the originals untouched

`readResourcePatches()` picks up a loose `<type>.<nnn>` file from the game
directory (`resource.cpp:1804-1806`) and `processPatch()` reads a 2-byte
header before the payload (`resource.cpp:1619-1629`,
`kResourceHeaderSize = 2` at `resource.h:51`). `harness/s1patch.py` writes
one. RESOURCE.MAP and RESOURCE.001 are **symlinked read-only** into the run
directory; only the patch file is added.

**[measured]** Three runs, same binary, same game, differing only in
`text.901` (`harness/s1box.py` locates the message window by grey-row count
and reports ink per text line):

| run | `text.901` first line | lines in box | ink, line 1 |
|---|---|---|---|
| `/tmp/s1en` | unpatched: `"The setting:"` | 5 | 568 |
| `/tmp/s1ascii` | `"PATCHED-ASCII-OK:"` | 5 | **1136** |
| `/tmp/s1patch` | `"한글 시험입니다"` (EUC-KR) | **4** | — |

The ASCII row is the proof the mechanism works: `/tmp/s1en/t7.png` reads
`The setting:` and `/tmp/s1ascii/t7.png` reads `PATCHED-ASCII-OK:` in the same
box above the same unchanged paragraph, from the same read-only resource
files. (The ink difference, 568 → 1136, is the replacement being longer and
all-caps, not a rendering change.) No original file was modified.

The three captures and both patch files are archived at
`captures/2026-09-16/s1sci0/` (`s1en-`, `s1ascii-`, `s1patch-text901-*.png`,
`text.901.ascii`, `text.901.euckr`), so the table above can be re-checked
against the images rather than against this prose.

The Korean row is the proof the *rendering* half is not free. The line is not
merely blank — **the box is one line shorter**, so the engine laid it out and
drew nothing. The log says why: **[measured]** 14 `font.1 is missing glyph N`
warnings, N in 177..232, which are exactly the EUC-KR bytes of the Korean
string being drawn one at a time through the game's own font. Font 1001 was
never selected, because `getLanguage()` is `EN_ANY` — see §1a. The two halves
are consistent: the patch delivered the bytes, and the language gate withheld
the font.

**This is the shape of the first implementation card**, and it is a small one:
a `KO_KOR` detection row + a patch set, with nothing else changed, should make
that line draw in Hangul.

---

## 5. Does the semantic parser transfer?

**Yes, and the room filter transfers better than it did for AGI.**

**[measured]** `harness/s1sci0said.py` walks `vocab.000` the way
`loadParserWords()` does (`vocabulary.cpp:91-193`) and the SCRIPT blocks the
way `identifyOffsets()` does (`script.cpp:338-382`):

```
vocab.000: 1,600 words, 749 distinct groups
said() specs: 772, in 69 of 132 scripts
said word tokens: 1,807 — 1,807 (100%) resolve to a vocab group or a magic id
distinct said groups used: 256 of 749
```

Compare K1's AGI numbers on Space Quest 0: 1,957 words / 407 groups, 5,645
said() calls in 56 logics, **6 out-of-range (0.1%)**. SCI0's said tokens
resolve at 100% here, because the said block is length-structured rather than
scanned for an opcode — no drift risk of the kind `gen_opcodes.py` exists to
avoid.

What is **reused** unchanged:
- The whole offline pipeline: model2vec static embeddings, int8 quantisation,
  role separation (verb/noun), IDF damping, the reverse-direction gap filling.
  None of it knows what an engine is.
- The room-filter *idea*, one-to-one: SCI's said spec is per-script just as
  AGI's is per-logic, and the choke point is a single function.

What must be **rebuilt**:
- The dictionary reader. `vocab.000` is prefix-compressed like WORDS.TOK but
  not identically: an alphabet index of 26 uint16 then `len`-prefixed entries
  whose bytes are masked `& 0x7F` with the high bit terminating, then three
  bytes packing an 11-bit group *and a class* (`vocabulary.cpp:139-180`).
  AGI has no class field. **[measured]** the mask means **every stored word is
  7-bit ASCII** — confirmed, all 1,600 — so a Korean word cannot be added to
  `vocab.000` at all. The K-chain's expansion table must therefore live
  outside the resource, exactly as `agisem.dat` does.
- The runtime hook point: `Vocabulary::lookupWord()` (`vocabulary.cpp:452`),
  called from `tokenizeString()` (`vocabulary.cpp:748`) when the exact match
  fails — structurally the same place as AGI's
  `parseUsingDictionary()` fallback, and the same rule applies (never
  override an exact parse).
- The room's said set. `Script::_offsetLookupArray` already holds every said
  spec with `SCI_SCR_OFFSET_TYPE_SAID` (`script.cpp:344`), so the engine has
  *already indexed* what K4 had to walk bytecode for. The collection point is
  script load, not parse time — same lesson as K4's `newRoom()`.

One SCI-specific bonus: `Vocabulary::lookupWord()` already has a
**language-specific prefix hook**, `lookupWordPrefix()`
(`vocabulary.cpp:531-580`), added for Hebrew and gated on
`getLanguage() == HE_ISR`. A Korean ending-stripper is the same shape at the
same call site.

---

## 6. The PC-98 traps do NOT apply to the Korean path

The card asked whether Hangul shares `putKanjiChar()`'s limits. **It does
not**, and the reason is the driver table. [source]

- **Glyph reshaping.** The "first and last 5 rows scaled, middle 6 not"
  behaviour is `renderPC98GlyphFat` / `renderPC98GlyphSpecial`, installed only
  by the PC-98 drivers (`pc98_16col.cpp:148,153`, `pc98_8col_sci0.cpp:88`,
  `pc98_8col_sci1.cpp:156`). A `KO_KOR` game gets plain `UpscaledGfxDriver`,
  whose `_renderGlyph` is the straight transparency-keyed copy
  (`upscaled.cpp:44-58, 73`). No reshaping.
- **`remapTextColor()`** is likewise only in `putKanjiChar`
  (`screen.cpp:514`); `putHangulChar` does not call it (`screen.cpp:477-485`).

**Correcting `SCI_AGI_ASSESSMENT.md`:** it states `_hiresGlyphBuffer` is
"256 bytes, which is 16x16 at 1bpp" and that an 8bpp coverage glyph does not
fit. The buffer is `new byte[16 * 16]()` (`screen.cpp:151`) and
`FontKorean::drawChar`'s `bpp` parameter is **bytes** per pixel, not bits
(`graphics/korfont.h:110`), called with `1` (`screen.cpp:483`). So it is
already **16x16 at one byte per pixel** and an 8-bit glyph *does* fit.

The real limits are different and worth stating correctly:

1. **Size, not depth.** 256 bytes is 16x16. A 24x24 hi-res glyph overruns it.
2. **Coverage is not blending.** `renderGlyph` copies bytes and skips the
   transparent key (`upscaled.cpp:44-58`); values between 0 and 255 would land
   in the display screen as *palette indices*, not as alpha. So an antialiased
   glyph cannot go through this path — a replacement font must be a 1-bit
   stencil expanded to 0/colour, which is what `blitCharacter()` already does
   (`korfont.cpp:119-141`). This is the same distinction the user drew on the
   SCUMM side: 8-bit-per-pixel and 8-bit-alpha are not the same thing.
3. **4-pixel horizontal snap.** `GfxFontKorean::draw()` passes
   `left & 0xFFC` (`fontkorean.cpp:74`) — the low 2 bits of the *low-res* x
   are cleared, so every Hangul glyph snaps to a 4-low-res-pixel column.
   `UpscaledGfxDriver` itself imposes none (`_textAlignX = 1`,
   `upscaled.cpp:194` → `hiresDestX &= ~0`, `upscaled.cpp:149`). Whether that
   snap is deliberate or inherited from the PC-98 comment is **[unmeasured]**.

---

## What a replacement font would take (question 3)

**A fourth subclass is genuinely all it takes, for the glyph source.**
`GfxFont` is abstract with four virtuals (`scifont.h:36-48`) and
`GfxCache::getFont()` picks the subclass in one place
(`cache.cpp:64-79`). `GfxFontKorean` is 86 lines including licence.

A `GfxFontHiRes` owning a `Graphics::HiResBitmapFont` would answer
`getCharWidth()` from metrics and draw via a `putHiResChar()` sibling of
`putHangulChar()`. What it must respect, from §6: 1bpp stencil only, ≤16x16
cell unless `_hiresGlyphBuffer` grows, and `getHeight()`/`getCharWidth()`
must return **low-res** values for SCI < 2 (`fontkorean.cpp:58-70` does
`>> 1`), because the callers lay out in low-res coordinates and the driver
doubles.

What that does **not** get you, and is the reason this is not the first card:
none of §1a (detection), §2 (input), §3 (tokenizer) is a font problem.

---

## Verdict

**Open an implementation chain — but the first card is not a font card, and
not a parser card.**

Ranked, with what each would close:

1. **S2: make one SCI0 game Korean on screen.**
   A `KO_KOR` detection row for `sci0cascade` + the `text.901` EUC-KR patch
   already written. *Closes on:* `harness/s1box.py` reporting **5** lines in
   the intro box with line 1 inked, against the 4 measured today, and zero
   `font.N is missing glyph` warnings in the log. This is the smallest change
   that converts every §1 source claim into a measurement, and it exercises
   the driver row, the font-1001 sniff, `putHangulChar`, and the patch route
   in one run. If it fails, everything below is premature.

2. **S3: stop the tokenizer corrupting EUC-KR.**
   Don't fold the trail byte of a double-byte lead in
   `Vocabulary::tokenizeString()`. *Closes on:* a test asserting all 25
   syllables `harness/s1euckr.py` lists survive a round trip, plus the SCI1
   Korean games' behaviour unchanged. Small, self-contained, and arguably an
   upstream bug fix independent of this project.

3. **S4: Korean text input in `kernelTexteditChange`.**
   A composer emitting EUC-KR into the control's string, and `isDoubleByte()`
   stepping in the three byte loops (`controls16.cpp:126, 270, 241`).
   *Closes on:* a composed run and a literal run producing identical bytes in
   the game's heap string — the K4 counterfactual, which does not need a GUI.

4. **S5: the semantic parser at `lookupWord()`.** Only after 1–3; without
   input there is nothing to parse, and without 3 the input is corrupt.

**Not recommended:** porting `graphics/hires_text/` to SCI. §6 says a
replacement font must be a ≤16x16 1bpp stencil to pass through
`drawTextFontGlyph`, which is what `korean.fnt` already is. The hi-res layer's
value is proportional metrics, coverage antialiasing and TTF baking — all
three of which this path discards. A SCI hi-res font is a real card, but it
needs `_hiresGlyphBuffer` and the driver entry point widened first, and that
is a separate argument to make upstream.

**Do not bundle any of this with the SCUMM submission.** Unchanged from
`SCI_AGI_ASSESSMENT.md`'s recommendation, and the reasons have only got
stronger: S3 is a plausible standalone upstream bug fix with its own reviewer.

---

## Unmeasured, and load-bearing

1. **No Korean SCI game has ever been run here**, SCI0 or SCI1. Every claim
   about what `GfxFontKorean` actually draws is source reading. The font
   itself is available — `gamedata/ft-kor-hr/korean.fnt`, md5
   `271b4b34a1828214b7ba76a38cd074cc`, a Wansung-format file whose header
   reads 16x16 with shadow flag 9 — so S2 is not blocked on locating it, but
   whether `FontKorean::createFont()` accepts *that* file in an SCI context is
   untested.
2. **SCI0's `Box()` line breaking with double-byte text.**
   `GetLongest()` does handle `isDoubleByte()` (`text16.cpp:215-216,
   287-291`), which is more than SCUMM's `stringWordWrap()` did — but it was
   written for SJIS and the PC-98 special case at `text16.cpp:305-310` is
   Japanese-specific. Whether Korean wraps correctly is untested.
3. **Whether the 4-pixel x snap (`left & 0xFFC`) is needed off PC-98.**
4. **Demo-sized data.** All §5 numbers come from a demo. A shipped SCI0 title
   (KQ4, SQ3, LSL3) will have a larger dictionary and more said() specs; the
   structure should hold, the magnitudes will not.
