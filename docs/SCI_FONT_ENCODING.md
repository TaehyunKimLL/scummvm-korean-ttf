# SCI fonts and who owns the encoding

Written for card S3b (`t_15097372`), whose job is to settle the two open S4
questions by measurement and to design the font-owned-encoding change the user
asked for. Engine read and run at `faf6cc842c8` (branch `hires-text`); harness
at `harness/s3b*` in this repo. Line numbers are only valid at that commit.

**No engine code is changed by this card.** The M1 measurement needed probes;
they were removed, and `harness/s3bclean.sh` is the check that says so — it
reports `dirty files: 0`, `probe sources: 0`, `ERRORS=0`, 483 tests OK.

Every claim below is one of three kinds and says which:

- **[source]** — a file:line in the engine. Static reachability only.
- **[measured]** — a number this card produced by running something.
- **[unmeasured]** — stated because it is load-bearing and nobody has checked it.

The file:line citations are not maintained by hand. `harness/s3bcheck.py`
extracts all 34 of them, resolves each against the engine tree, and fails if
one is past EOF or names an identifier that is not in the function enclosing
the cited line — so a rebase that shifts line numbers breaks the check instead
of quietly making this document wrong. **[measured]** 34 checked, all resolve;
corrupting two citations makes it report both and exit 1.

---

## Short answer

| Question | Answer |
|---|---|
| **M1** Do scripts read the edit buffer mid-edit? | **No.** 1,319 passes through the control, 0 third-party reads before submission. Design **(a)** wins. [measured] |
| **M2** Is there a codepoint → EUC-KR converter? | **Yes, and it is exact.** `kWindows949` round-trips all 2,350 syllables with 0 errors. No table needs building. [measured] |
| **D1** Should the font own the encoding? | **Yes in principle, and S4 should adopt only the smallest slice of it.** The full change touches 40 sites across SCI16 *and* SCI32 and is a standalone upstream proposal. [measured census] |

The surprise is M2. The card expected a reverse table might have to be built by
inverting the forward one; it does not — `String::encodeWindows949()` already
builds exactly that inversion, lazily, at `str-enc.cpp:611-632`. The work is
zero.

The second surprise is in D1's census: **`SwitchToFont1001OnKorean` and the
byte-pair assembly both exist twice**, once in `text16.cpp` for SCI16 and again
in `text32.cpp` for SCI32. Any font-owned-encoding refactor has two copies to
make, which is a large part of why the maximal version is an upstream card and
not an S4 task.

---

## M1. Nothing reads the edit buffer while the player is typing

### What was instrumented

Four probe points, all removed afterwards:

| Probe | Where | Catches |
|---|---|---|
| `EDIT-ENTER` / `EDIT-LEAVE` | `controls16.cpp:172`, `:314` | the window in which the control itself owns the buffer |
| `DEREF` | `SegManager::dereference()`, `seg_manager.cpp:582` | every engine-side read or write of that heap object |
| `KCALL` | `callKernelFunc()`, `vm.cpp:319` | every kernel call handed that pointer as an argument |
| `LOCALREAD` | `read_var()`, `vm.cpp:121` | a script reading the buffer's words directly, with no kernel call at all |

The fourth probe exists because of a real hole in the first three. The buffer
is **not** in a dynmem segment: **[measured]** `EDIT-ENTER seq=1 ref=0009:0000
segtype=3 ownerscript=996 maxChars=45 words=0..22` — `segtype=3` is
`SEG_TYPE_LOCALS` (`segment.h:64`), i.e. it is script 996's own local-variable
block. A script can therefore read its bytes with `lag`/`lal`
(`vm.cpp:1267-1281`) and never touch `dereference()` or a kernel call. Without
probe four, "0 reads" would have been an artefact of looking in the wrong
place.

An access is classified **inside** the control iff it falls between an
`EDIT-ENTER` and its matching `EDIT-LEAVE`; anything else is a third party.
`harness/s3bm1.py` does that classification and **refuses to report** if the
ENTER and LEAVE counts disagree — the failure mode where a probe format change
silently reclassifies every access as "inside".

### The run

`harness/s3bm1.sh` drives Cascade Quest to its parser prompt under Xvfb, types
one character per 1.2 s, idles 8 s with the text entered but unsubmitted,
backspaces, then submits. The typing is real and visible:
`captures/2026-09-16/s3b/s3b-m1-typed-open-door.png` shows `Enter Input:` with
`open door` in the field.

**[measured]** (`captures/2026-09-16/s3b/s3b-m1-submit.txt`):

```
EDIT-ENTER     : 1319          EDIT-LEAVE : 1319
buffer states, in order:
  seq 1     [6f]                       'o'
  seq 74    [6f 70]                    'op'
  ...
  seq 608   [6f 70 65 6e 20 64 6f 6f 72]  'open door'
  seq 1213  [6f 70 65 6e 20 64 6f 6f]     'open doo'   <- backspace

dereferences INSIDE  kernelTexteditChange : 1328  (all from Dialog::handleEvent)
dereferences OUTSIDE kernelTexteditChange :    2
kernel calls OUTSIDE, mid-edit            :    0
kernel calls OUTSIDE, at submission       :    2
    kStrLen at seq 1319 from script 979, User::export 2
    kParse  at seq 1319 from script 996, User::handleEvent
local/global reads of the buffer's words  :    0
```

Both third-party accesses are at **seq 1319 — the final pass**, i.e. the Enter
keystroke. `kParse` is the submission itself (`kparse.cpp:90` does
`getString(stringpos)` and hands it to `tokenizeString()`); `kStrLen` is the
script checking the line is non-empty immediately before parsing it. Nothing
reads the buffer at any of the 1,318 earlier passes.

### The control run, which is what makes this trustworthy

A count of zero is worth little unless a variant that *should* also be zero is
zero for the same reason, and a variant that should be non-zero is non-zero.
`SUBMIT=0` types `look tree`, waits 10 s, and **never presses Enter**:

**[measured]** (`captures/2026-09-16/s3b/s3b-m1-nosubmit.txt`):

```
EDIT-ENTER : 2144   EDIT-LEAVE : 2144
dereferences OUTSIDE : 0        kernel calls OUTSIDE : 0
```

2,144 passes through the control, text sitting in the heap the whole time, and
**not one** third-party access. The submitted run's 2 accesses appear exactly
when Enter is pressed and not before. The two runs together say the probe is
live (it fires on the submission) and the mid-edit count is a real zero, not a
probe that was never wired up.

A counter answers the other way a zero can lie — a probe on a path that never
executes. **[measured]** `EDIT-LEAVE seq=1319 ... vartype g=7702 l=290
t=100516 p=27732`: `read_var()` ran 136,931 times during the run, so the
function the `LOCALREAD` probe sits in was thoroughly exercised; it simply
never saw an index inside the buffer's word range.

### What this decides

**Design (a) is correct: keep EUC-KR in the game heap while editing, and swap
it for English on Enter.** [measured]

The risk that made (b) — an engine-side shadow buffer — worth considering was a
script reading Korean bytes mid-edit and mis-handling them. That script does
not exist in this game. The one script that reads the buffer, `User::handleEvent`
in script 996, reads it *only* at submission, which under the confirmed design
is after the semantic parser has already replaced the Korean with English. It
never sees a Korean byte.

Two honest limits on that conclusion:

1. **[measured on one game.]** Cascade Quest is the only SCI0 game here. A
   different game could poll its input line — nothing in the engine prevents
   it. The probe set is cheap to re-run against any new game and
   `harness/s3bm1.sh` takes a game directory through `GAME=`.
2. **[unmeasured]** Whether the same holds on SCI1 Korean fan translations.
   They share the edit control (`kernel_tables.h:1079`) but have their own
   scripts.

Neither limit changes the recommendation, because (a) is also strictly less
engine surface than (b): if a future game does poll mid-edit, that game gets a
workaround entry, not a redesign.

---

## M2. The converter exists, it is exact, and it is already an inverted table

### The answer to the question as asked

`common/str-enc.h:73` has `convertUHCToUCS(high, low)` — EUC-KR → Unicode. The
card asked whether the reverse exists or has to be built. **It exists**:
`String::encodeWindows949()` (`str-enc.cpp:603-661`) is reached from
`U32String::encode(kWindows949)` via `encodeInternal()` (`str-enc.cpp:1154`),
which is what `convertFromU32String(str, page)` (`str-enc.h:72`) calls.

And it is built the way the card guessed one would have to be built —
`str-enc.cpp:611-632` walks the forward table and inverts it into a
`uint16[0x10000]` on first use:

```cpp
// str-enc.cpp:625-627
uint16 unicode = windows949ConversionTable[highidx * 0xb2 + lowidx];
rt[unicode] = (high << 8) | low;
```

So the work is not "write a reverse table"; it is "call the function".

### The measurement

`harness/s3bm2.cpp` is linked against **the engine tree's own**
`common/libcommon.a` and the test suite's null OSystem, so what it exercises is
the code the engine links, not a Python model of it. Run by
`harness/s3bm2.sh`; `encoding.dat` md5 `f2e88b2faec499a4914c3a0bcffc7db1`.

**[measured]** (`captures/2026-09-16/s3b/s3b-m2-roundtrip.txt`):

```
population      : 2350   (lead 0xB0..0xC8 x trail 0xA1..0xFE)
decoded         : 2350
uhc mismatches  : 0      (encode/decode agrees with convertUHCToUCS on all)
encode errorchar: 0
roundtrip ok    : 2350
VERDICT         : kWindows949 round-trips all 2350 syllables
```

The population is exactly the rectangle `FontKoreanWansung::getCharData()` can
index — `((ch % 256) - 0xb0) * 94 + (ch / 256) - 0xa1` (`korfont.cpp:424`). All
2,350 survive `EUC-KR → codepoint → EUC-KR` byte-identically, and the two
independent decode routes (`decodeWindows949` and `convertUHCToUCS`) agree on
every one.

### Three further measurements that change the S4 design

**[measured]**

```
compat jamo U+3131..U+3163 : 51 of 51 encode to 2 bytes
modern jamo U+1100..U+1112 :  0 of 19 encode to 2 bytes
U+AC00..U+D7A3 (all 11172) : 11172 of 11172 encode to 2 bytes
   of those, inside the SCI font's index range : 2350
   of those, OUTSIDE it (encodes, no glyph)    : 8822
```

Three consequences, all load-bearing for S4:

1. **`kWindows949` is UHC, not plain Wansung.** It encodes all 11,172 modern
   syllables. The SCI font draws 2,350 of them. **A composer that emits any
   syllable will produce 8,822 code points that encode fine and then index
   outside the font's 25×94 grid.** S4 must range-check against the font, not
   against the converter — the converter will not tell it no. This corrects the
   natural reading of `SCI0_PARSER_ASSESSMENT.md` §3, which treated EUC-KR
   encodability and font coverage as the same boundary.
2. **Compatibility jamo encode; modern jamo do not.** A composer holding a
   half-typed syllable must express it as U+3131..U+3163 (compat) rather than
   U+1100..U+1112 (conjoining). AGI's `hangul.cpp` already works in code
   points, so this is a choice at the adapter, not a rewrite.
3. **Those compat jamo still have no glyph**, because 0xA4xx is outside
   0xB0..0xC8 — S1 §3 measured that and it holds. So a half-composed syllable
   encodes, and draws as garbage. S4 needs its own glyph source for the
   composing state, exactly as K3 did for AGI.

**Where the conversion should happen: the SCI-side adapter, not the composer**
(option (b) in the S4 comment thread). The measurement supports it: the
converter is one call, it is exact, and `engines/agi/hangul.cpp` stays
untouched and code-point-based. Nothing here argues for teaching the automaton
about EUC-KR.

---

## D1. Font-owned encoding: the design, and how much of it S4 should take

### The user's observation is correct, and here is the census

`harness/s3bd1.py` enumerates every site in the SCI engine (plus the two
`graphics/` fonts it uses) that knows something about an encoding, classifies
it, and **requires a written disposition for each one**. A site with no
disposition is reported as unaccounted and the script exits 1.

**[measured]** (`captures/2026-09-16/s3b/s3b-d1-census.txt`):

```
census: 40 encoding-aware sites, 40 accounted, 0 unaccounted
  PAIR   3   assembles a double-byte code point from two bytes
  STEP   6   advances or measures a text pointer by byte
  SNIFF 23   tests raw byte values to decide a language
  INDEX  8   converts a packed code point into a glyph row/column
```

The check bites: injecting one extra `c |= (*(const byte *)(p + 1)) << 8;` into
an unrelated file (`graphics/palette.cpp`) makes it report
`41 sites, 40 accounted, 1 unaccounted` and exit 1. Clean tree exits 0.

### The three PAIR sites, which are the actual defect

```cpp
// text16.cpp:215-216   GetLongest
curChar = (*(const byte *)textPtr);
if (_font->isDoubleByte(curChar))
    curChar |= (*(const byte *)(textPtr + 1)) << 8;

// text16.cpp:516-517   Draw            (same shape, advances text++)
// text32.cpp:440-441   SCI32 drawText  (same shape again)
```

The caller reads a byte, asks the font a yes/no question, and then does the
font's arithmetic itself. Contrast the SCUMM-side font this project already
built: `bitmap_font.h:101` `Common::CodePage codePage()` and
`bitmap_font.cpp:354` `int glyphIndex(uint32 codepoint)` — the caller passes a
code point and the font resolves it through its own cmap.

### The design

One new virtual on `GfxFont` (`scifont.h:36-48`), with a default that preserves
today's behaviour exactly:

```cpp
// scifont.h - proposed
/// Decode one character from a byte string in THIS font's encoding.
/// Returns the packed value the font's own draw()/getCharWidth() expect,
/// and writes the number of bytes consumed to *bytesRead.
virtual uint16 decodeChar(const char *text, int *bytesRead) {
    *bytesRead = 1;
    return *(const byte *)text;          // every single-byte font, unchanged
}
```

and one override in each double-byte font:

```cpp
// fontkorean.cpp / fontsjis.cpp - proposed
uint16 GfxFontKorean::decodeChar(const char *text, int *bytesRead) {
    uint16 lead = *(const byte *)text;
    if (isDoubleByte(lead) && text[1]) {
        *bytesRead = 2;
        return lead | ((*(const byte *)(text + 1)) << 8);
    }
    *bytesRead = 1;
    return lead;
}
```

Call sites that stop knowing the encoding, named exactly:

| Site | Today | After |
|---|---|---|
| `text16.cpp:214-216` `GetLongest` | read byte, test, OR in trail | `decodeChar(textPtr, &n)` |
| `text16.cpp:515-517` `Draw` | same, with `text++`/`len--` | `decodeChar(text, &n); text += n; len -= n;` |
| `text16.cpp:313-315, 350-353, 393-395` | three more copies inside `Width`/`CodeProcessing` | same |
| `text32.cpp:440-441, 588-589, 713-714` | the SCI32 twins | same |
| `controls16.cpp:108, 128, 137, 272` | `getCharWidth((byte)text[i])` per byte | `decodeChar` then `getCharWidth`, which is also the S4 fix |

What does **not** move, and the reason matters:

- **`SwitchToFont1001OnKorean`** (`text16.cpp:735`, and its SCI32 copy at
  `text32.cpp:954`) sniffs bytes to decide *which font to load*. It cannot be
  font-owned — there is no font yet when it runs. It stays a caller
  responsibility under any design. [source]
- **`korfont.cpp:424`, `fontsjis.cpp:54`, `screen.cpp:477/487`** are already
  inside the font or take an already-packed value. They are the model, not the
  problem.
- **`vocabulary.cpp:727-739`** (the S3 tokenizer defect) is a *parser* byte
  loop with no font in scope at all. Font-owned encoding does not fix S3; S3
  stays its own card.

So of 40 encoding-aware sites, the design removes encoding knowledge from
**9** (3 PAIR + 6 STEP), leaves 23 SNIFF sites that are font *selection*, and
leaves 8 INDEX sites that already live in the right place.

### Ranked options, and what S4 should actually adopt

**Option 1 — S4 takes nothing from D1.** Fix the four `controls16.cpp` loops
in place with `isDoubleByte()`, as `SCI0_PARSER_ASSESSMENT.md` §2 proposed.
Smallest diff, touches one file, changes no shared interface.
*Cost:* adds a tenth site that knows the encoding, in the file this card was
opened to clean up.

**Option 2 — S4 adds `decodeChar()` and uses it only in `controls16.cpp`.
← recommended.**
One new virtual with a behaviour-preserving default, one override in
`GfxFontKorean`, and the four textedit loops call it. `text16.cpp` and
`text32.cpp` are not touched, so every existing platform's text rendering is
byte-identical by construction — the default returns exactly what
`*(const byte *)text` returned before, and nothing else calls the new method.
*Why this one:* it is barely larger than option 1, it puts the new code on the
right side of the interface, and it leaves the upstream-sized change as a
separate reviewable patch instead of smuggling it in under a Korean-input card.
Testable without a GUI: `decodeChar` over a byte string is a unit test.

**Option 3 — convert `text16.cpp` too.** Six more call sites, all in the SCI16
text path that every SCI0/SCI1 game uses.
*Cost:* the behaviour-unchanged claim stops being structural and starts needing
an A/B capture sweep across the English, Japanese and Korean paths. Real work,
and none of it advances Korean input.

**Option 4 — convert `text32.cpp` as well, and unify the two
`SwitchToFont1001OnKorean` copies.** This is the whole change the user
described. It touches SCI32, which this project has never run.
*Cost:* needs an SCI32 reviewer and SCI32 regression evidence. Out of scope
here by a wide margin.

**Recommendation: S4 adopts option 2. Options 3+4 become a standalone upstream
proposal** — "SCI: let the font decode its own characters" — carrying the
census output as its justification and a before/after capture set per affected
language as its evidence. That card is not blocked on anything in the K/S
chain and can be proposed independently, exactly like S3.

### The standing rule, and how option 2 satisfies it structurally

Existing-platform behaviour must not change. Option 2 satisfies that without
needing a capture sweep to prove it, which is the reason to prefer it over 3:

- `GfxFont::decodeChar()`'s default is `*bytesRead = 1; return *(const byte *)text;`
  — identical to what every current caller computes for a single-byte font.
- Only `GfxFontKorean` overrides it, and only `controls16.cpp` calls it.
- Therefore no Japanese, Mac, or `FromResource` path can observe the change:
  `GfxFontSjis` keeps its own `isDoubleByte` (`fontsjis.cpp:53`) and its callers
  in `text16.cpp` are untouched.

A test asserting the default's byte-for-byte equivalence over 0x00..0xFF, plus
the `GfxFontKorean` override over the 2,350 syllables M2 enumerated, is enough
to close it.

---

## What this card did not do

- **No engine code changed.** `harness/s3bclean.sh`: `dirty files: 0`,
  `probe sources: 0`, `ERRORS=0`, 483 tests OK at `faf6cc842c8`.
- **Probes removed.** `engines/sci/s3bprobe.{h,cpp}` and their four call sites
  existed only for M1. The cleanup script also removes the stale
  `s3bprobe.o` a probed build leaves behind — it found one the first time it
  ran, which is why that step is in the script rather than in a sentence here.
- **M1 is one game.** See the two limits under M1.
- **Nothing about rendering the composing state.** M2 establishes that compat
  jamo encode and have no glyph; supplying those glyphs is S4's problem and is
  explicitly out of scope here.

## Unmeasured, and load-bearing

1. **Whether an SCI1 Korean fan translation's scripts poll the edit buffer.**
   M1's answer is measured on SCI0 Cascade Quest only.
2. **Whether `decodeChar()`'s default is genuinely free at every existing call
   site.** Argued structurally above from the code; not yet demonstrated by a
   capture, because no such call site exists until S4 writes one.
3. **What the 8,822 out-of-font syllables should do.** M2 measures that they
   encode without error; what S4 renders for them — refuse the keystroke, draw
   a box, or fall back — is an unanswered design question, and the first one
   a Korean player will hit.
