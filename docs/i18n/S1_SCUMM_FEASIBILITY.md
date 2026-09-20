# S1 — can SCUMM take the same route SCI took?

`[source]` = read in code. `[measured]` = observed by running something.
`[unmeasured]` = a claim this document has not earned.

Probe commits `ec4195a58e1` and `d4c5f353d0b`, removed exactly in
`e47b685c497` (`git diff ec4195a58e1~1 e47b685c497 --stat -- engines/` is
empty). Branch `wt/s1-scumm` off `hires-text` at `96ce757ba47`. Every run
exited with `ALIVE=yes` and `CRASHMARKS=0`; the clean tree after the revert
builds with 0 errors and passes 559 tests.

Tools, all committed:

| tool | answers |
|---|---|
| `harness/s1run.sh` | drives one target under the probe, reports survival next to the counts |
| `harness/tools/s1sum.py` | aggregates the logs into the three answers |
| `harness/tools/s1census.py` | static census of every byte-walk site; **exits 1 on an unaccounted-for site** |
| `harness/tools/s1trs.py` | reads a `.trs` bundle: size, UTF-8 growth, inline escapes |
| `harness/tools/s1port.py` | counts how much of a file names an engine-specific symbol |

Runs: 9 sessions over 7 targets — `mm-bare` (v2), `zak-kor` (v2),
`i3-multi` (v3), `loom-kor` (v4), `mi2-ctrl` (v5), `i4-var` (v5),
`ft-kor` (v7). Logs in `runs/s1final/`.

---

## The short answer

SCI's "B" direction was: **patch the text where it already lives, in UTF-8,
and let one decoder in the renderer read it.** For SCUMM that decomposes into
three separate answers, and they are not the same answer.

| | SCI | SCUMM `[measured]` |
|---|---|---|
| Q1 translation hook | `getSciLanguageString`, one place | **already exists** — `translateText()`, and it is *better placed* than SCI's was |
| Q1 can the data be patched in place | yes, `text.NNN` resources | **no — 41 of 96 displayed strings are inline in a script resource**, and v0-v2 additionally pack a flag into bit 7 |
| Q2 do scripts index string bytes | KQ1 0, LB1 0, one fan game 6,906 | **309 in a shipped Sierra game** (Indy4 `script145`), but **0 of them on translated text** |
| Q3 does the renderer take code points | needed `readChar()` | **`printChar(int)` is already wide, but it is handed a packed pair, not a code point** — 490 of 599 distinct values were above 0xFF |

So: the *hook* question is already solved on this branch and is better than
SCI's starting point. The *data* question is answered **no** for SCUMM — the
resource-patch route SCI took does not exist here — which means the existing
`.trs` runtime-substitution mechanism is not a legacy to be replaced, it is
the only mechanism available and it should be *generalised* instead.

---

## Q1 — is the translation hook already there, and can the data be patched?

### The hook: yes, and it is placed better than SCI's was

`[source]` `string.cpp:1593`, inside `ScummEngine::convertMessageToString()`:

```cpp
if (_game.version >= 7 || hasTranslationBundle()) {
    translateText(msg, transBuf, sizeof(transBuf));
    src = transBuf;
}
```

`[measured]` Every displayed string in all nine runs passed through this one
function — `convertCalls` was non-zero in every run and the distinct-text
count matched the sum of the classified sites. There are three other
`translateText()` call sites (`resource.cpp:1359` for `rtString` loads,
`dialogs.cpp:559` for the GUI), and `ScummEngine_v7::translateText()`
overrides it for the `/TAG/` scheme while delegating to the base when a
bundle is present (`string.cpp:2222`).

This is structurally what SCI card D3 had to *build* — SCI's translation
points were scattered and D3 collected them into `getSciLanguageString`.
SCUMM already has the funnel, and it sits at a better place: **after** the
resource is loaded and **before** any escape processing, so it sees the
string exactly as the script meant it.

`[source]` The key it uses is the original English text plus a
`(room, script, where)` context, resolved by three heuristics in
`translateText()` (`string.cpp:2456`) — which is the same shape as SCITRS's
source-key-plus-position-hint, arrived at independently.

### The data: no, and for two separate reasons

`[measured]` Where the 96 distinct displayed strings physically lived:

```
rtVerb              45   46.9%   (of which 32 carry a high byte)
rtScript            23   24.0%   (3 with a high byte)
SCRIPT_STREAM_V2    18   18.8%
rtString             4    4.2%
rtRoom               1    1.0%
UNKNOWN              5    5.2%   (engine-owned buffers: the quit prompt)

inline in a script resource : 41   (rtScript + SCRIPT_STREAM_V2)
in a replaceable resource   : 50   (rtVerb + rtString + rtRoom)
```

**Reason one: 43% of displayed text is inside a script resource.** `rtScript`
hits carry a byte offset into the script body — e.g. Indy3's
`rtScript 2.1 off=770 size=1214 "Hello Marcus!"`. That is the same shape as
SCI's `lofsa` problem, and it closes the same door: a script computes the
address, so changing the string's length moves every address after it.
SCI card P3 reached the identical conclusion for its script-embedded strings
and routed them to a runtime side table. SCUMM's share is much larger.

**Reason two, and this one is specific to SCUMM: v0-v2 have no spare byte
values at all.** `[source]` `script_v2.cpp:374`:

```cpp
while ((c = fetchScriptByte())) {
    insertSpace = (c & 0x80) != 0;
    c &= 0x7f;
```

Bit 7 of every text byte in a v0-v2 script means *append a space after this
character*. `[measured]` On `zak-kor`, a 31-byte line carried **6** bytes
with bit 7 set; across the v2 runs every measured line used it. So the high
half of the byte range is not merely occupied by a code page — it is
**structurally unavailable**, and no 8-bit encoding, UTF-8 included, can be
stored there. That is why the Korean v0-v2 patches use a `.trs` bundle and
not rewritten resources, and it is not a choice anyone can revisit.

`[measured]` The `UNKNOWN` figure needs one correction that the raw counts
get wrong: a v0-v2 line is seen **twice** — once as it is unpacked from the
script stream, and again when the assembled stack buffer reaches
`convertMessageToString`, where it belongs to no resource. 18 of the 23
original `UNKNOWN` hits were exactly that re-entry (paired by content;
`s1sum.py` folds them). The 5 that remain are genuine engine-owned strings —
the quit prompt from `getStaticResString`.

### Cost of the UTF-8 that a patch would have to hold

`[measured]` `s1trs.py` over the six shipped Korean bundles and FT:

| game | lines | cp949 | UTF-8 | growth | inline escapes |
|---|---|---|---|---|---|
| Maniac Mansion | 1,024 | 23,134 B | 30,127 B | +30.2% | 192 in 12% of lines |
| Zak | 1,737 | 37,340 B | 50,096 B | +34.2% | 346 in 16% |
| Indy3 | 2,143 | 56,951 B | 78,938 B | +38.6% | 282 in 12% |
| Loom | 1,150 | 39,801 B | 54,638 B | +37.3% | 344 in 22% |
| MI2 | 8,780 | 103,172 B | 112,502 B | +9.0% | 20,795 in **83%** |
| Indy4 | 9,099 | 148,578 B | 156,523 B | +5.3% | 20,448 in **79%** |
| Full Throttle | 3,515 | 42,299 B | 44,181 B | +4.4% | 6,523 in **67%** |

Two things fall out that a size figure alone hides:

- The growth is +4% to +39%, not the uniform +40% SCI measured, because the
  later games' lines are mostly *escape bytes and English*, not hangul.
- **`0xFF <code> [args]` escapes are interleaved with the characters in the
  same byte stream**, 75 KB of them in MI2 alone. Any re-encoding has to
  carry them through as raw binary. A naive whole-line `cp949 → UTF-8`
  decode fails on 83% of MI2's lines, and the first version of `s1trs.py`
  reported exactly that before it was taught to split the runs — a counting
  mistake worth recording, because "7,282 of 8,780 lines are not cp949"
  looked like a corrupt bundle and was not.

---

## Q2 — do scripts index string bytes? Yes — and it does not matter

SCI's wall was `kStrAt`: if a script takes the i-th *byte*, UTF-8 breaks it.
SCUMM's equivalents `[source]`:

- v5 `o5_stringOps` sub-op 3 (set string char) and 4 (get string char)
  — `script_v5.cpp:3076` / `:3092`, a raw `ptr[b]` on an `rtString`.
- v6+ `readArray`/`writeArray` on a `kStringArray` — `script_v6.cpp:394`.

`[measured]`

```
                        calls   on translated text
o5 getStringChar         309            0
o5 setStringChar           0            0
readArray(kStringArray)    0            0
```

All 309 come from **one script**: Indy4 room 5, `script145`, reading two
170-byte strings. The progression settles what it is doing:

```
progression getStringChar str=31: n=155  step+1=154  other=0  -> SCAN
progression getStringChar str=30: n=154  step+1=153  other=0  -> SCAN
bytes taken that were a double-byte lead: 0
```

Two parallel left-to-right scans over two equal-length buffers, advancing by
exactly 1, on text with no high bytes. That is a character-by-character
compare of an input against an expected answer — Indy4's copy-protection
dialogue — not dialogue manipulation.

This is the mirror image of SCI's M11-1 result, and the *opposite* reading of
the same number. M11 found 0 calls in shipped games and 6,906 in a fan game,
and concluded shipped games are safe. SCUMM has 309 in a shipped LucasArts
game — and it is still safe, because the operand is never translated text.
`[measured]` 0 of 309 bytes taken were a double-byte lead.

`[unmeasured]` Nine sessions over seven games. Other games, and the rest of
Indy4, are not covered. The *bound* is: SCUMM's string ops are reachable and
are used, so a byte-semantics change cannot be global — it would need the
same translation gate SCI built (`stringsAreUnicode()`).

### The one that is actually ours

`[source]` The census found a byte scan that is **in the engine, not in a
script**: `addMessageToStack` (`string.cpp:1906` and `:1973`) walks a
finished message *backward* looking for the last hangul pair, to choose the
Korean postposition (은/는, 이/가):

```cpp
for (int i = len; i > 1; i--) {
    byte k1 = ptr[i - 2];
    byte k2 = ptr[i - 1];
    if (checkKSCode(k1, k2)) { ... }
}
```

This is SCUMM's own `kStrAt`, and unlike a script's it is ours to change. A
UTF-8 heap invalidates it: "two bytes back" is not "one character back" in
UTF-8. It is ~15 lines and has exactly one purpose, so it converts cleanly —
but it must be on the list, and nothing in the source says so today.

---

## Q3 — does the renderer take code points?

**The signature is already wide. The value is not a code point.**

`[source]` `charset.h:112` `printChar(int chr)`, `:124`
`getCharWidth(uint16 chr)`. `[measured]` What actually arrives:

```
site                    distinct values   above 0xFF
CHARSET_1.v3                  311            281
TextRenderer_v7.2byte         161            161
drawString                    121             48
TextRenderer_v7.1byte           6              0
                              ---            ---
                              599            490
```

`[source]` But the value above 0xFF is a **packed byte pair**, assembled at
the call site (`string.cpp:1267` `c += *buffer++ * 256`, and the v7
equivalent `(byte)str[i] + 256 * (byte)str[i+1]`) — and packed *lead byte
low*, which the hires layer documents because feeding the decoder the other
order yields plausible-but-wrong Hanja rather than a visible failure
(`hires_text.cpp:557`).

So the shape is exactly SCI's `SwitchToFont900OnSjis` problem named in the
card, and M11-4's second cause: a byte pattern decides the rendering path.

### How many sites, and can they be one decoder?

`s1census.py` enumerates the whole population and demands a reason for each
entry, so a site added next year is *unaccounted for* until someone writes
one. Current standing total, checked into the tree:

```
S1CENSUS total=50 advance=13 pack=3 scan=2 predicate=16 recv=16 unaccounted=0
```

- **13 ADVANCE** — decide how many bytes the walk consumes. These are the
  sites a UTF-8 walk must change (1..4 bytes, not 1-or-2). SCI's M11-4 had
  **four**. SCUMM has thirteen, spread over `getStringWidth`, `addLinebreaks`,
  `CHARSET_1`, `drawString` and the two v7 walks — which is the direct answer
  to the card's "how many byte walks are there": **thirteen, and they are the
  GetLongest-equivalent plus three more copies of it.**
- **3 PACK** — where two bytes become the renderer's value, plus the v0-v2
  bit-7 packing.
- **16 RECV** — consumers that read `chr >= 256` to mean "CJK". They do not
  walk anything, but every one breaks if the value above 255 becomes a code
  point instead of a pair. This is the count that decides whether the change
  is mechanical, and it is the reason a `readChar()` alone does not finish
  the job here.
- **2 SCAN**, **16 PREDICATE** — as above.

The census was proved to bite: injecting a plausible new site
(`static bool s1FakeNewSite(int chr) { return chr >= 0x80 && chr <= 0xFE; }`)
into a copy of `charset.cpp` moved it to `unaccounted=1`, exit 1.

### What already exists, and is better than SCI's equivalent

`[source]` **The one-place decoder the card asks about is already written**,
in this branch's hi-res layer: `ScummHiResText::decodeNext()`
(`hires_text.cpp:1500`) turns a packed pair into a `uint32` code point using
`Common::U32String(bytes, page)`, and `glyphIndexFor()` feeds it to a font
indexed by code point. It has three callers.

That means SCUMM's *glyph lookup* is already code-point based for hi-res
text. What is not converted is everything **before** it — the 13 advances and
the 16 receivers still speak packed pairs, so the decode happens at the last
possible moment instead of the first.

---

## The fonts and bundles: two formats that should be one

The card asks whether SCVMUNI and the SCITRS bundles can be shared. Measured
rather than judged:

`[measured]` `s1port.py` on the two code-point font loaders:

```
SCI   engines/sci/graphics/fontunicode.{cpp,h}   334 code lines, 21 SCI-specific (6%)
SCUMM graphics/hires_text/bitmap_font.{cpp,h}    329 code lines,  0 engine-specific (0%)
```

`[source]` They are two different formats solving the same problem:

| | magic | index | lives in |
|---|---|---|---|
| SCVMUNI | `SCVMUNI\0` | sorted code-point table, binary search | `engines/sci/` |
| SVFN v2 | `SVFN` | code-point table added in v2 (`kCmapOffField`) | `graphics/hires_text/` |

**SVFN is already in `graphics/`, already engine-neutral, and already
code-point-indexed at version 2.** SCVMUNI is a second format with the same
capability sitting inside one engine. The convergence is therefore not "can
SCUMM use SCI's font" — it is that SCI's font loader should move to
`graphics/` or adopt SVFN v2, and 94% of it is already portable code.

For the bundles: SCITRS is keyed by source text with a `(resource, index)`
hint; SCUMM's `.trs` is keyed by source text with a `(room, script)` hint.
`[source]` Both resolve a collision by comparing the source. They are the
same design reached twice. `[unmeasured]` Whether one reader can serve both
formats — that is a card, not a measurement.

---

## What this licenses

1. **Do not port the "B" resource-patch direction to SCUMM.** `[measured]`
   43% of displayed text is inline in a script resource, and v0-v2 have no
   free byte values at all. The `.trs` runtime-substitution path is not
   legacy — it is the only route, and the hook for it already exists and is
   well placed.
2. **The Unicode work that *does* transfer is Q3, and it is bigger here.**
   13 advances and 16 receivers against SCI's four. The decoder itself is
   already written (`decodeNext`); what is missing is moving it from the
   glyph lookup to the walk.
3. **Q2 is not a blocker but is not zero either.** Gate any byte-semantics
   change on the bundle being loaded, exactly as SCI did, and convert the
   engine's own backward hangul scan in `addMessageToStack` at the same time.
4. **The font formats should converge on SVFN v2**, not on SCVMUNI, because
   SVFN already lives in `graphics/` with zero engine-specific lines.

`[unmeasured]`, and stated so nobody infers coverage that was not there:
nine sessions, seven targets, no HE game, no v8 (COMI), no SegaCD/PC-Engine
target, and `loom-v4` and `i4-v5` reached **zero** renderer calls — their Q3
columns say nothing. The Q1 ratio is over strings a player would see in the
first two minutes of each game, not over the corpus; the `.trs` figures in
the table above are the corpus-level complement.
