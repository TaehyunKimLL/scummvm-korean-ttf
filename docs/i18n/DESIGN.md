# SCI Unicode text: design

The shape of the change as it stands at `dc527920d79`, 30 commits on
`upstream/master`, +2,925 / −86 across 34 files. The M-series documents
(`M1` … `M11`) record how each decision was reached and what was measured;
this one records what the result *is*, so that a reader can judge the
design without replaying the history.

`[source]` = read in code. `[measured]` = observed by running something.
`[unmeasured]` = a claim this document has not yet earned.

## What problem this solves

SCI games store text as bytes in the game's own code page and index glyphs
by those bytes. A Korean fan translation therefore ships cp949 bytes and a
font indexed as `code point − 0xAC00` — which can never draw anything
outside the hangul syllable block: no 「 」, no Ａ Ｂ, no ㄱ ㄴ, no ℃.
`[measured]` KQ1's Korean menu came up with blank boxes for exactly those.

The same shape repeats per language: a Shift-JIS font reachable only through
font id 900, a cp949 font only through 1001, and `GfxText16` deciding which
to switch to by pattern-matching lead bytes. Adding a language meant adding
another font id, another byte pattern, another `getLanguage() == X` in every
place the last one was.

The goal is a translation format and a font format that are
**language-neutral** — one bundle format, one font format, indexed by code
point — and an engine path where the language is a property of the data,
not a branch in the renderer.

## Where this sits among the ways SCI text has been localised

Six shapes exist in the wild. `[source]` for all: `detection_tables.h`
(language counts), `state.cpp:223` (splitter), `text_overlay.h:32`
(overlay), `graphics/sjis.cpp` (ROM fonts).

```
                          text lives in        encoding   font from            language known by
A  Sierra Latin          the resources        cp437      the game's font.NNN  MD5
   (53 DE, 42 FR, 28 ES, 16 IT, 2 PT)
   multilingual variant  same, after %G/%F..  cp437      the game's font.NNN  printLang selector
B  Sierra Japanese       same, after %J       Shift-JIS  hardware ROM;        MD5 + printLang
   (12: PC-98, FM-Towns)                                 ScummVM ships SJIS.FNT
C  Russian fan (21)      resources rewritten  cp866      resources rewritten  MD5 + Translate.RU
D  Korean fan, overlay   Text.MAP/Text.Res    cp949      korean.fnt           the overlay's presence
   (KQ1, KQ5, SQ1, ...)  beside the game
E  Korean fan, in-place  resources rewritten  cp949      korean.fnt           MD5 (added here)
   (LB1)
F  this branch           sci.trs beside       UTF-8      *.uni beside         the bundle's header
                         the game                        the game
```

Two structural facts fall out of the table:

**A and C need no engine knowledge of the language.** A single-byte code
page plus the game's own font is renderer-neutral: the bytes index the
glyphs directly. That is why 21 Russian translations landed upstream with
detection entries and nothing else.

**B, D and E do.** A double-byte code page plus a font the game did not
ship means `getLanguage()` chooses a rendering path — which font id to
switch to, whether to set `doubleByteMode`, whether the hires plane needs
refreshing. Every `== KO_KOR` / `== JA_JPN` this branch removed came from
that necessity, and `SwitchToFont900OnSjis` (B) is where the "font id
means a language" pattern began.

F is in the second family but replaces the language gate with a **data
gate**: `heapStringsAreUtf8()` is "a bundle is loaded", not "the game is
Korean". The renderer asks what the bytes are, not where the game is
from. D is F's direct ancestor — same overlay-beside-the-game shape,
generalised from one code page and one font to any code point.

## The design in one picture

```
   sci.trs (UTF-8, keyed by original English)
        │
        ▼
   lookupText()  ──── translation hit ────►  UTF-8 bytes into the VM heap
        │                                          │
        │ miss                                     │
        ▼                                          ▼
   game's own bytes (cp437 / cp949 / cp932)   kStrLen / kStrAt count
        │                                     code points (gated)
        │                                          │
        └────────────────┬─────────────────────────┘
                         ▼
              GfxText16::readChar()
              one decoder, chosen by heapStringsAreUtf8()
                         │
                         ▼  uint32 code point
              GfxFontSet  [resource face][legacy DBCS face][Unicode face]
                         │  first face that covers the code point
                         ▼
              glyph on the hires text plane
```

Three properties fall out of this shape, and the rest of the document is
about them:

1. **One decoder.** `readChar()` in the renderer and `decodeUtf8Char()` in
   the string ops are the same function. "How many characters" and "where
   does the next one start" cannot disagree.
2. **One seam.** The only place the game's code page is still named is
   `GfxFontSet::toEncodedPair()`, which re-encodes a code point for a legacy
   `korean.fnt`/`SJIS.FNT` face. It disappears when those faces do.
3. **Two gates, both data-driven.** `usesHiresDoubleByteText()` (how glyphs
   reach the screen) and `heapStringsAreUtf8()` (what a heap byte means).
   Both are true iff a bundle is loaded. An untranslated game never enters
   the new path.

## The three formats

### SCITRS — the translation bundle (`docs/i18n/SCITRS_FORMAT.md`)

UTF-8 strings keyed by the **original text**, not by resource position.
`[source]` `translation.cpp`: FNV-1a over the whitespace-normalised source,
bucketed, then a string compare on hit so a collision costs a comparison
and never a wrong answer.

Why keyed by text: a Korean patch built against one English release must
work against another. `[measured]` LB1's Korean patch was built on a
different volume layout than the English DOS release we have; keyed by
`(resource, index)` it would match nothing, keyed by text it matched 6,231
of 6,246 strings.

Why the `(resource, index)` hint exists anyway: the same English line
legitimately has different translations in different places.
`[measured]` LB1 has 86 such groups, 277 entries. The hint picks the right
one; a miss falls back to the first match and warns once per source
(`52babdcc004`, with a test that fails if the hint is ignored).

Why one file for all languages: the bundle declares its own language in its
header. The engine reads it, never assumes it.

### SCVMUNI — the font (`docs/i18n/SCVMUNI_FONT.md`)

A bitmap font with an explicit sorted code-point table. `[source]` Lookup
is a binary search; a miss is a clean "no glyph", not an out-of-range read.
Width is a per-glyph flag (narrow/wide) derived from Unicode East Asian
Width at build time, so a fullwidth Ａ and a halfwidth A each take the
cells they should.

Why not a TTF at run time: upstream ScummVM builds without FreeType on
several platforms. A pre-rasterised bitmap needs no library and renders
identically everywhere.

Why not extend `korean.fnt`: its index *is* the arithmetic
`code point − 0xAC00`. There is no table to extend.

The header has four reserved bytes at offset 32. They are zero. A language
tag was tried there (`951104b7691`) and reverted (`7a7212314bb`): the
detection table already answers "which language is this game", and a
file-format field is a compatibility promise that every future builder
must honour.

### The detection table — for patches that ship no bundle

A fan patch that rewrites the game's own resources in place carries no
statement of its language, and detection keys off the very files it
overwrote. `[measured]` The Korean LB1 detected as DOS/English and dropped
every double-byte lead byte — 268 "missing glyph" warnings per boot, no text
on screen.

The answer is the one upstream already uses for the Russian LB1 and the
Korean KQ6: an MD5 entry in `detection_tables.h` (`edec8f56e65`). Two
lines. The user configures nothing.

`getLanguage()` still consults, in order: the legacy Korean overlay, the
bundle's declared language, `ConfMan["language"]`, then detection. The
ConfMan step is the escape hatch for a patch not yet in the table.

## The font set

`GfxFontSet` (`fontset.h`, 150 lines; `fontset.cpp`, 222) is the design's
centre of gravity. It answers one question the engine used to answer
wrongly: **what is a font id?**

`[source]` A font id in SCI is a typeface the *script* chose — font 4 is
the small one, font 300 the large one. It is not a language. The engine had
nonetheless grown two ids that mean a language (1001, 900), reached by
`GfxText16` switching to them when the bytes looked foreign.
`[measured]` KQ1 Korean: 52 requests for font 1001, every one manufactured
by the switch, none by the game — and each switch threw away the height the
script had asked for, collapsing faces of 8, 9 and 12 pixels to one.

A set keeps the id the script asked for and picks the face per character:

```
font 4  →  [ resource face font.004 ] [ korean.fnt ] [ korean.uni ]
```

The order is the contract. `[measured]` Putting the Unicode face first
changed every English string's metrics — faces of 12 and 9 both reported
8 — and pushed menu text outside its button. The resource face goes first
so single-byte text is drawn by exactly the glyphs the game shipped, and a
later face only answers for a code point nothing before it covers.

What the set does **not** decide: whether glyphs bypass the normal blit.
That is `doubleByteMode`, which belongs to the driver — it exists because
ScummVM does not emulate the PC-98 text-mode plane — and nothing in the set
infers it from a font id.

The legacy switches (`SwitchToFont1001OnKorean`, `SwitchToFont900OnSjis`)
survive. `[measured]` With a set present they fire zero times. They stay
because for a game that ships `korean.fnt` and no bundle they are the only
route to it, and removing them would break those releases to tidy the new
path.

## The string boundary — and where it moved

This is the decision that took two attempts, and the reason deserves the
space.

**First attempt (M8):** convert to code points at `lookupText()`. Encode
the UTF-8 translation back to the game's code page; downstream sees bytes
SCI expects. It worked, and it had a ceiling: any character the code page
cannot represent is dropped at that step. `[measured]` A Thai letter with a
glyph in the font never reached the renderer — not a box, nothing. "Unicode
for whatever cp949 can already say" is not Unicode.

**Second attempt (M11):** hand UTF-8 to the heap unencoded. Three things had
to be true for that to be safe, and each was measured before code moved
(`M11_STRING_OPS.md`):

- Scripts never do arithmetic on what `kStrLen`/`kStrAt` return for
  translated text. `[measured]` In KQ1 and LB1, translated text never
  reaches those ops at all. (The 6,906 `kStrAt` reads M4 found were a fan
  game.)
- UTF-8's +40 % never overflows a script buffer. `[measured]` Tightest fit
  seen: 8,028 bytes available, 8 needed.
- No `%-Ns` width format takes a translated argument. `[measured]` One
  width format in both bundles; it pads a number.

With those cleared, the heap holds UTF-8, `kStrLen`/`kStrAt` count code
points behind the gate, and `GfxText16` walks with the same decoder.
`[measured]` Glyph sequences for KQ1 English, Korean and Japanese are
identical to the pre-change baseline in (code point, top, left); the Thai
letter is drawn; a code point above U+FFFF (U+1F600) reaches the font
layer intact and is reported as missing by number.

What did **not** move: the heap cell layout. Script bytecode computes
addresses assuming bytes; savegames serialise them. `uint32` cells would
move every address a script has compiled in. That door is closed and the
document says so.

### Why UTF-8 and not UTF-16, given 16-bit heap cells

The cell is 16 bits, so a UTF-16 code unit looks like a natural fit. It
is not, for four reasons, each `[source]` unless marked:

```
                        UTF-8                UTF-16
cell alignment          none needed          required; [measured] 51 % of
                                             KQ1's 1,786 strings start at
                                             an odd byte (SegmentRef::skipByte)
NUL safety              yes                  no - 'A' is 41 00, and the
                                             byte-wise strlen stops there
raw vs reg_t paths      one                  two - script-resource strings
                                             are byte[], not cells
variable length         1..4 bytes           1..2 units (surrogates), so
                                             kStrAt decodes either way
kStrLen/Cpy/Cat         unchanged            rewritten per storage kind
```

`seg_manager.cpp:608` refuses a cell-wise read of an odd-aligned pointer
outright (`Unaligned pointer read … return nullptr`). UTF-16 wins no row.
UTF-8 assumes nothing about the heap, which is the property that let it
go in behind a gate with every untranslated game byte-identical.

### Why not a string table outside the heap

SCI32 does exactly this: `SciArray` (`segment.h:409`, `kArrayTypeString`)
holds string bodies engine-side and the heap carries handles, created and
manipulated through the `kString` kernel call. It is the right shape for
SCI32 and the natural place to carry UTF-8 there.

SCI16 cannot, because Sierra did not build it that way. `[source]`
Strings live inside the script resource, in the same buffer as the
bytecode (`SCI_OBJ_STRINGS`), and scripts obtain their address by an
*opcode* — `lofsa` loads a constant offset into the script segment
(`vm.cpp:1197`) — not by a kernel call the engine could intercept.
Scripts then do arithmetic on that pointer: `reg_t::operator+` on a
`SEG_TYPE_SCRIPT` pointer returns `offset + n` (`vm_types.cpp:81`), and
`str + 5` means "the sixth byte". A handle plus five means nothing.
Moving SCI16 strings out of the heap would change what `lofsa` and
pointer addition mean for every SCI16 game.

What this branch does instead has the same effect for the case that
matters. `[measured]` (M11) Scripts never touch translated text through
any string op; they carry the *original* English pointer, arithmetic and
all, and `lookupText()` consults the engine-side table (`sci.trs`) at the
moment of display. The heap is a conduit the script does not read.

## Invariants — what may not be traded away

Stated so a proposal that is clean and wrong can be recognised.

- **An untranslated game is byte-identical.** Both gates are false; no new
  code runs. `[measured]` KQ1 English glyph sequence 273/273 identical;
  Korean LB1 patch (cp949, no bundle) unchanged.
- **Single-byte text is drawn by the game's own font.** The resource face
  is first in every set. `[measured]` Violating this moved English text.
- **A character the layer cannot draw reaches the original path.** A set
  with no covering face falls back to the first face, matching what the
  engine did before a set existed.
- **Builds without FreeType, and with `ENABLE_SCI32` both ways.**
  `[measured]` Every commit on the branch.
- **`make test` passes.** 420 at `dc527920d79`; 17 of those are this work
  (10 for the bundle, 7 for the decoder).

## What is deliberately not done

- **Kinsoku for UTF-8 Japanese.** The PC-98 line-start punctuation block
  walks back two bytes at a time and re-validates with `isDoubleByte()`; it
  is correct only for a fixed-width code page and is skipped for UTF-8. A
  translated Japanese line can start with 。. `[unmeasured]` how often.
- **`kStrAt` writes into UTF-8.** Replacing a 1-byte character with a
  3-byte one in place would move every byte after it. Writes keep byte
  semantics and warn. `[measured]` No shipped game does this.
- **SCI32.** `text32.cpp` has its own text path. It builds; it is not
  ported. When it is, the shape differs: SCI32 strings are `SciArray`
  objects reached through `kString`, so UTF-8 belongs in
  `kArrayTypeString` and the code-point semantics go into the `kString`
  sub-ops (substring, insert, ...), not into a heap walk.
- **The parser.** `kSaid` matches word ids from the vocabulary, never
  string bytes. Translated *input* is a separate problem
  (`scummvm-llm-text-parser`).
- **Removing the legacy faces.** `korean.fnt`/`SJIS.FNT` still load and
  still draw for games that ship them. `toEncodedPair()` is the one seam
  that knows the code page, and it is the one that goes when they do.

## For upstream review

The history is 30 commits. Eight are four probe-and-remove pairs, each an
exact revert (`git diff <probe>~1 <remove> --stat -- engines/` is empty),
so the measurements are reproducible at a hash and the branch ends clean.
Two more are a change and its revert (the font language tag), kept so the
reasoning is on record. The remaining twenty each carry their measurement
in the message.

The order a reviewer will want is the order the M-documents were written:
`M1` (what SCI text ownership looks like), `M4`/`M6` (do scripts touch
text bytes — a fan game does, Sierra's do not), `M8` (the first boundary
and its ceiling), `M10` (the font set), `M11` (the second boundary). Each
names what would have refuted it.
