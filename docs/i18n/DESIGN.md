# SCI Unicode text: design

The shape of the change as it stands at `ef8dc87fb2`, 45 commits on
`upstream/master` (merge base `503d0747781`), +4,645 / −118 across 56
files. The M-series documents (`M1` … `M11`) record how each decision was
reached and what was measured; this one records what the result *is*, so
that a reader can judge the design without replaying the history.

The previous revision of this document described `dc527920d79`, when
translations came from a text-keyed bundle (`sci.trs`). That bundle was
retired in `93cfc53ff8`; §"What SCITRS was, and why it went" says why.
Measurements quoted below that were taken with the bundle say so.

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

The goal is a text path and a font format that are **language-neutral** —
UTF-8 text, one font format indexed by code point — and an engine path where
the language is a property of the data, not a branch in the renderer. The
renderer half of that goal is met. The gate half is not, since `93cfc53ff8`;
see §"Open: the gates name Korean again".

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
F  this branch           text.NNN patches     UTF-8      *.uni beside         MD5 of a patch file
                         beside the game,                the game             (added here)
                         + sci-<lang>.str
                         for script strings
```

Two structural facts fall out of the table:

**A and C need no engine knowledge of the language.** A single-byte code
page plus the game's own font is renderer-neutral: the bytes index the
glyphs directly. That is why 21 Russian translations landed upstream with
detection entries and nothing else.

**B, D and E do.** A double-byte code page plus a font the game did not
ship means `getLanguage()` chooses a rendering path — which font id to
switch to, whether to set `doubleByteMode`, whether the hires plane needs
refreshing. Most `== KO_KOR` / `== JA_JPN` tests this branch removed came
from that necessity, and `SwitchToFont900OnSjis` (B) is where the "font id
means a language" pattern began.

F is in the second family. At `dc527920d79` it replaced the language gate
with a data gate ("a bundle is loaded"). Since `93cfc53ff8` its text arrives
the way C's and E's does — as patch files the resource manager has always
loaded — and the engine learns the text is UTF-8 from the detection entry,
which names a language. F is now E's shape with UTF-8 in place of cp949,
plus one side table for the strings a patch cannot reach.

## The design in one picture

```
  text.NNN patch files (UTF-8)          sci-<lang>.str (UTF-8)
  replace whole TEXT resources          (script, id[, room]) -> text
        │                                     │
        ▼                                     │
  ResourceManager (kSourcePatch)              │   kStrCpy tags the stack
        │                                     │   buffer a script string
        ▼                                     │   is copied into
  lookupText() / heap strings ─── key ────────┤
        │                                     ▼
        └──────────────► strSplitLanguage()  ── table hit: UTF-8 out
                         (every string on its way to the screen)
                                   │
                                   ▼
                         GfxText16::readChar()
                         one decoder, chosen by heapStringsAreUtf8()
                                   │  uint32 code point
                                   ▼
                         GfxFontSet  [resource face][legacy DBCS face][Unicode face]
                                   │  first face that covers the code point
                                   ▼
                         glyph on the hires text plane (TEXT_PLANE.md)
```

Three properties fall out of this shape:

1. **One decoder.** `readChar()` in the renderer and `decodeUtf8Char()` in
   the string ops are the same function. "How many characters" and "where
   does the next one start" cannot disagree. `DrawStatus()` was the last
   byte-walker (`9f1b59448d`).
2. **One seam.** The only place the game's code page is still named in the
   draw path is `GfxFontSet::toEncodedPair()` (`fontset.cpp:62`), which
   re-encodes a code point for a legacy `korean.fnt`/`SJIS.FNT` face. It
   disappears when those faces do.
3. **Two gates.** `usesHiresDoubleByteText()` (how glyphs reach the screen)
   and `heapStringsAreUtf8()` (what a heap byte means). An untranslated game
   never enters the new path. Both are currently spelled in terms of
   `KO_KOR`; see §"Open".

## The data

### UTF-8 TEXT patches — what a translator ships

A Sierra fan translation replaces TEXT resources with `text.NNN` patch
files, each replacing one resource whole. `[source]` The engine has loaded
these since before this branch (`processPatch`, `kSourcePatch`); the only
new thing is that the strings inside may be UTF-8 (`1baecbadab`).
`harness/i18n/m12mkpatch.py` writes them from a translation TSV.

`[measured]` KQ1 with 106 UTF-8 `text.NNN` files and no other translation
data: 106/106 patches load, the opening box renders in Hangul with the same
glyphs as the earlier bundle build, missing glyph 0.

### The script-string table — what a patch cannot reach (`SCRIPT_STRINGS.md`)

A string inside a script's own string block — an inventory name, a parser
reply, "You are carrying nothing!" — is referenced by absolute offset
(`lofsa`). A longer translation would shift every following string and
every offset into them, so it cannot be patched. `[measured]` KQ1 has 93
such strings that reach the screen and appear in no TEXT resource.

Those, and only those, come from `sci-<lang>.str`, a tab-separated UTF-8
file keyed by **where the string lives**: (script, string id), optionally
qualified by room. The id is the one `Script::identifyOffsets()` assigns at
load, which `SegManager::stringKey()` reports at display and the
`script_strings` console command dumps, so a table built from the dump is
found without a second numbering. `<lang>` is the ScummVM code of the
detected language; the file carries no language of its own.

### SCVMUNI — the font (`SCVMUNI_FONT.md`)

A bitmap font with an explicit sorted code-point table. `[source]` Lookup
is a binary search; a miss is a clean "no glyph", not an out-of-range read.
Width is a per-glyph flag (narrow/wide) derived from Unicode East Asian
Width at build time, so a fullwidth Ａ and a halfwidth A each take the
cells they should. `GfxCache` looks for `sci.uni`, `korean.uni`,
`towns.uni` beside the game, in that order.

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

### The detection table — how the engine learns the language

A fan patch carries no statement of its language, and detection keys off
the very files it overwrote. The answer is the one upstream already uses
for the Russian LB1 and the Korean KQ6: an MD5 entry in
`detection_tables.h`.

- **LB1 Korean** (in-place, cp949, `edec8f56e65`). `[measured]` Without it,
  the game detected as DOS/English and dropped every double-byte lead byte —
  268 "missing glyph" warnings per boot, no text on screen.
- **KQ1 Korean** (UTF-8 patches, `1baecbadab`). The entry lists every file
  the English entry lists plus `text.000`, so the detector — which picks the
  entry matching the most files — prefers it exactly when the patch is
  present. `[measured]` The same volumes detect as Korean with the patch and
  English without it.

`getLanguage()` consults, in order: the legacy Korean overlay
(`Text.MAP` present → `KO_KOR`), `ConfMan["language"]`, then detection
(`sci.cpp:1057`). The ConfMan step is the escape hatch for a patch not yet
in the table.

### What SCITRS was, and why it went

From `48cd90f5` to `93cfc53ff8` translations came from `sci.trs`: UTF-8
strings keyed by an FNV-1a hash of the whitespace-normalised **English
source text**, with a `(resource, index)` hint to break ties, and a header
declaring the bundle's language. `SCITRS_FORMAT.md` specifies it and is
kept as a record.

Keying by text was chosen so a patch built against one English release
would work against another (`[measured]` LB1: 6,231 of 6,246 strings
matched by text across different volume layouts). Two findings removed the
reason for it:

1. **TEXT resources need no engine lookup at all.** A patch file *is* the
   translation, and the resource manager already loads it. Looking up a
   TEXT string by its English text to find its translation was a detour
   around a mechanism that already existed.
2. **Script strings need an exact key, and they have one.** Once
   `identifyOffsets()` numbered them (`768d3043a8`), `(script, id)` named a
   string exactly. Text keys are guesswork when two places share a line
   (`[measured]` LB1: 86 such groups, 277 entries).

With both gone, the hash, the normaliser and the source-text pool were
dead weight: `translation.cpp` 353 → 143 lines, `translation.h` 183 → 144.
The bundle's declared language went with it, and that is the cost recorded
in §"Open".

## Where translation happens

Before `98f7d923fb` the table was consulted in three places, each with its
own idea of the key. Now there is one: **`strSplitLanguage()`**, which
every string passes through on its way to the screen (`kDisplay`,
`kDrawControl`, `kTextSize`, the menu bar, a window title). Callers pass
the key of where the string came from; a hit returns the UTF-8 translation
and skips the `%J`/`%G` splitter.

The key is found one of two ways `[source]`:

- **Direct pointer into a script's string block** —
  `SegManager::stringKey()` maps the offset back to `(script, id)`.
- **Stack buffer** — a script string usually reaches the screen as a stack
  buffer the script `kStrCpy`'d it into. `kStrCpy` (full-length copies
  only) records `buffer → (key, text written, current room)`, and
  `ScriptStrings::keyOf()` answers only while the buffer still holds that
  text, so a reused buffer yields no key rather than a wrong one.
  `[measured]` KQ1, inventory and two parser replies: 28 display lookups,
  0 stale tags.

`kFormat` is the one caller that translates *before* `strSplitLanguage`:
once `"The %s looks like any other %s."` has been formatted, the result is
a dynamic buffer with no key. It translates the format string and each
`%s` argument by their own keys, then formats.

The two callers that ask `getSciLanguageString()` for English by name —
`file.cpp` for a filename, `workarounds.cpp` for an object name — never
reach `strSplitLanguage()` and so are never translated, without a special
case.

## The font set

`GfxFontSet` (`fontset.h`, `fontset.cpp`) is the design's centre of
gravity. It answers one question the engine used to answer wrongly:
**what is a font id?**

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
because for a game that ships `korean.fnt` and no `.uni` they are the only
route to it, and removing them would break those releases to tidy the new
path.

## The string boundary — and where it moved

This is the decision that took two attempts, and the reason deserves the
space. The measurements in this section were taken at `dc527920d79`, with
the bundle as the source of translated text; the argument does not depend
on where the text comes from, only on the heap holding UTF-8.

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
layer intact and is reported as missing by number. (The Japanese and Thai
halves of this cannot be re-run on the current path; see §"Open".)

The UTF-8 patch path adds one more exposure the bundle did not have: TEXT
resources are now UTF-8 *in the heap from the start*, not only at display.
`[unmeasured]` whether a Sierra script scans a TEXT resource string with
`kStrAt` before displaying it; M11's KQ1/LB1 measurement covered strings
reached through the bundle, and the UTF-8 patch build has not been
re-measured.

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

`seg_manager.cpp:609` refuses a cell-wise read of an odd-aligned pointer
outright (`Unaligned pointer read … return nullptr`). UTF-16 wins no row.
UTF-8 assumes nothing about the heap, which is the property that let it
go in behind a gate with every untranslated game byte-identical.

### Why not a string table outside the heap

SCI32 does exactly this: `SciArray` (`segment.h:429`, `kArrayTypeString`)
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
matters. Scripts carry the *original* pointer, arithmetic and all, and
`strSplitLanguage()` consults the engine-side table (`sci-<lang>.str`) at
the moment of display. For script strings the heap is a conduit the script
does not read.

## Hires glyphs survive the scene (`TEXT_PLANE.md`)

Double-byte text — legacy Korean and SJIS faces and the SCVMUNI face alike —
is drawn straight into the upscaled driver's bitmap, which nothing the
engine owns remembers. The next lowres update of the same area — an actor
walking past the box — erased it. `[measured]` KQ1 intro box, second text
row: 2242 black pixels at frame 1, 1352 at frame 60, the words vanishing
syllable by syllable along the actor's dirty rect.

`GfxScreen` now keeps a hires **text plane**: written by every glyph the
SCVMUNI and legacy Korean faces draw (not yet the legacy SJIS face — its
PC-98 drivers align glyphs themselves), re-applied after every lowres blit
in `displayRect()`, cleared when
the window that drew it is disposed, when a new picture replaces the
screen, and on restore (`c7106971bd`). `[measured]` 2242 → 2318 over the
same 60 frames. A game that never draws a hires glyph never allocates it.

## Driving the game for measurement (`DEBUG_SOCKET.md`)

Every measurement after `501160d04b` is taken through a debug socket
(`debug_socket=` in the game's config; UNIX socket, or a named pipe on
Windows) that runs console commands between ticks, synthesises input, and
blocks on conditions on game state (`wait room == 5`, `wait text "..."`)
rather than on the clock. `debug_record=` writes what a human player does
as state plus input, and `harness/i18n/rec2script.py` turns it into a
replay script. `[measured]` The KQ1 inventory tour: four minutes of
xdotool-and-sleep became 13 seconds, five captures byte-identical across
runs. None of it runs unless one of the two keys is set.

## Invariants — what may not be traded away

Stated so a proposal that is clean and wrong can be recognised.

- **An untranslated game is byte-identical.** Both gates are false; no new
  code runs. `[measured]` KQ1 English glyph sequence 273/273 identical;
  lowres frame buffer bit-identical at frames 1, 40 and 105 of the intro
  box with the text plane in; Korean LB1 patch (cp949) unchanged.
- **Single-byte text is drawn by the game's own font.** The resource face
  is first in every set. `[measured]` Violating this moved English text.
- **A character the layer cannot draw reaches the original path.** A set
  with no covering face falls back to the first face, matching what the
  engine did before a set existed.
- **Builds without FreeType, and with `ENABLE_SCI32` both ways.**
  `[measured]` Every commit on the branch up to `dc527920d79`;
  `[unmeasured]` since.
- **`make test` passes.** 420 at `93cfc53ff8` (per its message); 17 of those
  are this work: 10 for the script-string table
  (`test/engines/sci/translation.h`), 7 for the decoder
  (`test/engines/sci/utf8.h`).

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

## Open

### The gates name Korean again

`[source]` Since `93cfc53ff8`:

```
usesHiresDoubleByteText()  = Text.MAP overlay loaded
                             || getLanguage() == KO_KOR
                             || (PC-98 && PQ2)                  sci.cpp:1015
heapStringsAreUtf8()       = getLanguage() == KO_KOR
                             && !Text.MAP overlay loaded        sci.cpp:1028
```

At `dc527920d79` both were "a bundle is loaded". With the bundle gone
nothing in the data says "this heap is UTF-8", so the gate fell back to the
language. The consequence: **a UTF-8 patch in any language other than
Korean is walked as the game's code page.** A Japanese or Thai `text.NNN`
set, detected correctly, would reach `readChar()` with
`heapStringsAreUtf8()` false. The Japanese and Thai results quoted in
§"The string boundary" were taken through the bundle and cannot be
reproduced on the current path.

The fix wants a data signal again, and the detection entry is the natural
carrier: a flag on the entry ("this game's TEXT resources are UTF-8") that
`heapStringsAreUtf8()` reads, instead of inferring it from `KO_KOR`. That is
what "the language is a property of the data" meant, and a detection flag
is already how upstream marks per-entry facts. Not done; not measured.

### Room qualifiers apply to buffered strings only

`[source]` A key gets its room number only in `kStrCpy`'s tag
(`kstring.cpp:94`). A script string displayed through a direct pointer is
keyed by `SegManager::stringKey()`, which leaves the room at "any" — so a
room-specific entry never matches it and the any-room entry (if present)
answers. `[unmeasured]` whether any KQ1 string that needs a room qualifier
reaches the screen by a direct pointer.

### The SJIS face is outside the text plane

`[source]` `putKanjiChar()` (`screen.cpp:637`) still draws straight to the
driver, so a Japanese release on `SJIS.FNT` or a ROM font should lose text
under a passing actor as Korean did before `c7106971bd`. `[unmeasured]`
Details and why it is not a one-line change: `TEXT_PLANE.md`.

### Tooling not in any repository

`93cfc53ff8` cites `harness/i18n/p3ab.sh` for its with/without-table
measurement, and the 93-entry `sci-ko.str` it used. Neither the script nor
a table builder is committed to the harness repository. The table format is
simple enough to write by hand from `script_strings` output, but the
measurement is not reproducible from the repositories as they stand.

## For upstream review

The history is 45 commits. Eight are four probe-and-remove pairs (M4, M6,
M8, M11), each an exact revert (`git diff <probe>~1 <remove> --stat --
engines/` is empty), so the measurements are reproducible at a hash and the
branch ends clean. Two more are a change and its revert (the font language
tag), kept so the reasoning is on record.

Five commits (`48cd90f5`, `52babdcc`, `41c5c03a`, `768d3043`, `98f7d923`)
build machinery that `93cfc53ff8` then
reduces. They carry measurements the later commits rely on, so the history
keeps them; an upstream submission will likely want them squashed into the
side-table shape they ended in.

The debug socket and recorder (`dc22819e`, `501160d0`, `56d56df7`,
`ef8dc87f`, and the driver half of `683ddd1b`) are test tooling, not
localisation. They belong in their own submission.

The order a reviewer will want is the order the M-documents were written:
`M1` (what SCI text ownership looks like), `M4`/`M6` (do scripts touch
text bytes — a fan game does, Sierra's do not), `M8` (the first boundary
and its ceiling), `M10` (the font set), `M11` (the second boundary). Each
names what would have refuted it.
