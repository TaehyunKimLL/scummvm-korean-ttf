# The SCI16 text path, and what it would take to move it off direct writes

Written for card A1 (`t_8ae5cfaa`), which asks how far SCI's Korean text path
is from the structure the SCUMM-side hi-res layer already has, and in what
order the gap could be closed. Engine read at `b46c6acbfdc` (branch
`hires-text`); harness at `harness/a1*` in this repo; captures under
`captures/2026-09-16/a1/`. Line numbers are only valid at that commit.

**No engine code is changed by this card.** One probe was injected to prove
the census bites and removed in the same turn; `git status engines/` is clean
and `harness/a1census.py` exits 0 against the tree as it stands.

Claims are one of three kinds and say which:

- **[source]** — a file:line in the engine. Static reachability only.
- **[measured]** — a number this card produced by running something.
- **[unmeasured]** — stated because it is load-bearing and nobody has checked it.

---

## Short answer

| Question | Answer |
|---|---|
| **A** How many direct-manipulation sites, and how many could stop? | **178 sites. 66 REPLACE, 64 PERF, 43 SSCI, 5 already-OWNER.** The 66 are not 66 edits — they are three subjects. [measured] |
| **B** Where should line-scoped state live? | **Conditional.** A render context is justified by four cases, but only for the three values S4–S9 actually disagreed about. A general one is overdesign. |
| **C** Can `DrawString` be made genuinely high-level? | **Possible, and cheaper than the card assumed — the 3-argument `DrawString` has ZERO callers.** [measured] |
| **D** Can the coordinate spaces be unified? | **Conditional. Two of the three conversions are exact and must stay; the third (`left & 0xFFC`) is lossy, moves 75% of glyph positions, and has no original interpreter behind it.** [measured] |
| **E** Order and scope | Five steps, three of them small. See the table at the end. |

Two findings were not anticipated by the card and change its plan.

**The first is C.** The card names `text16.h:66`
`DrawString(str, orgFontId, orgPenColor)` as evidence that "SCI already has
high-level entry points". It is dead code. `harness/a1entry.py` resolves every
call site of every text entry point in `engines/sci`, matching on argument
count so the two overloads are not confused, and reports **[measured]**:

```
GfxText16::DrawString  engines/sci/graphics/text16.cpp:444   [3 args]
    callers   : 0  (matched on 3 args)
        *** NO CALLERS - this entry point is dead code ***
```

A whole-tree search agrees: the only three-argument `DrawString(` in ScummVM
outside the AGS engine is the definition itself. So the "high-level entry
point already exists" premise is half false — the one-argument overload
(`text16.cpp:707`) is live with 5 callers, all in `menu.cpp`, and the
three-argument one can be **deleted** rather than fixed.

**The second is D.** The `>> 1` halving the card suspected of losing
information is exact for the double-byte glyphs and inexact for ASCII and for
the line height, and the mask nobody flagged — `left & 0xFFC` — is the one
that actually moves glyphs. Details under D.

---

## A. The census: 178 sites, and why the number alone decides nothing

`harness/a1census.py` enumerates the SCI16 text path — from the caller down to
the pixels, eight files listed explicitly rather than walked — and requires a
written disposition for every hit. A hit with no disposition is reported as
unaccounted and the script exits 1.

**[measured]** (`captures/2026-09-16/a1/a1-census.txt`):

```
census: 178 direct-manipulation sites in the SCI16 text path, 178 accounted, 0 unaccounted
  by kind:    AMBIENT 56  BUF 59  BYTEWALK 18  RAWCOPY 8  SPACE 37
  by verdict: OWNER 5  PERF 64  REPLACE 66  SSCI 43
```

The check bites. Injecting into `text16.cpp` a function that assembles a byte
pair and indexes `_displayScreen` makes it report
`181 sites, 178 accounted, 3 unaccounted` and **exit 1**
(`captures/2026-09-16/a1/a1-census-bite.txt`); the clean tree exits 0.

### The card's "15 sites" was counting one thing; this counts five

The card's estimate came from a grep for `getBasePtr/memcpy/memset/byte*`.
That finds the pixel writes and misses the three subjects that actually caused
S4, S6, S7 and S9. Splitting by kind is what makes the census decide anything:

| kind | n | what it is |
|---|---|---|
| `AMBIENT` | 56 | reads/writes the port's drawing state — pen position, font, colour — from the text path |
| `BUF` | 59 | writes or reads a pixel buffer through a raw pointer or index |
| `SPACE` | 37 | converts between low-res script space and hi-res display space |
| `BYTEWALK` | 18 | walks a text string as raw bytes, including double-byte assembly |
| `RAWCOPY` | 8 | `memcpy`/`memset`/`calloc` over a pixel buffer |

And by verdict:

| verdict | n | meaning |
|---|---|---|
| `REPLACE` | 66 | an abstraction can own this; the caller should stop knowing |
| `PERF` | 64 | direct access is the point — inner pixel loop; leave it |
| `SSCI` | 43 | reproduces the original interpreter's observable behaviour |
| `OWNER` | 5 | already on the correct side of an interface — the model, not the problem |

**The 64 PERF sites are the reason a blanket rewrite fails**, and they are
almost all in one place: `GfxScreen`'s `putPixel` family lives in `screen.h`
(`screen.h:256-428`) precisely so it inlines, and everything above it already
goes through it. `GfxFontFromResource::draw()` (`scifont.cpp:282`) writes
through `_screen->putFontPixel()` — it is *already* the abstracted form the
card asks for. The engine is not short of a pixel abstraction.

**The 43 SSCI sites are the second reason.** `bitsSave`/`bitsRestore`
(`screen.cpp:547`, `:601`) hand the game a raw hunk whose size scripts
allocate; `fontsjis.cpp:77`'s `left & 0xFFC` reproduces the PC-98 ROM's 40×25
text grid, and `fontsjis.cpp:72-77` says so in the code.

### What the 66 REPLACE sites actually are

Not 66 independent edits. Three subjects:

1. **56 AMBIENT** — the pen. Every text function reads and writes
   `_ports->_curPort->{curLeft, curTop, penClr, fontId, fontHeight, penMode,
   greyedOutput}` instead of being told them. `text16.cpp` touches `penClr`
   10 times, `curLeft` 10 times, `curTop` 8, `fontHeight` 7 **[measured, by
   the census's own counts]**. Six functions in `text16.cpp` and four in
   `controls16.cpp` open with a hand-written save/restore of the font id
   (`text16.cpp:205, 382, 449, 572, 699, 708`; `controls16.cpp:61, 137, 357,
   591`) **[source]**.
2. **8 BYTEWALK** — the pair assembly. `text16.cpp:214-216`, `:313-315`,
   `:350-353`, `:393-395`, `:515-517` **[source]**.
3. **2 SPACE** — `putHangulChar`/`putKanjiChar`'s `x << 1, y << 1`
   (`screen.cpp:484`, `:518`) **[source]**.

The other 10 BYTEWALK hits are `SSCI`: `SwitchToFont1001OnKorean`
(`text16.cpp:757`) sniffs bytes to decide *which font to load*, so there is no
font in scope to own the walk, and `GetLongest`'s CR/LF lookahead
(`text16.cpp:242`) asks about a line terminator, which is not a character in
any font's encoding.

---

## B. Line-scoped state: conditional, and narrower than "a render context"

The card asks whether an object holding `(font, coordinate space, destination
buffer)` for the duration of one line is justified, or overdesign, and notes
this project's own rule: two cases do not justify an abstraction.

**Verdict: conditional — justified for the three values the four defects
actually disagreed about, not for a general render context.**

### The four cases, and what each pair disagreed about

| card | the disagreement | the fix |
|---|---|---|
| S4 `de7a0137b0d` | *when* the low-res rect reaches the screen vs. when the driver draws glyphs into its own hi-res bitmap | push the rect **before** the text for driver-rendered text |
| S6 `f139d2bd2a7` | *which characters* the driver draws — S4's gate suppressed the update for the whole control, but the driver only renders the double-byte half | pass `Box()`'s `show` argument, which already encodes the distinction per line |
| S7 `e55cc1b0649` | *which font* measured the line: `texteditCursorDraw` used the control's font, `Box()` drew with font 1001 | `FontIdForLine()` — expose the answer `Box()` already computed |
| S9 `74025d41824` | *which font* again, at the next call in the same function | same query, applied to the advance as well |

Every one of these is two pieces of code independently re-deriving a fact
about **one line**, and disagreeing. That is four cases, not two, and they are
the same shape. The abstraction is justified.

**But the values in dispute are exactly three**, and "destination buffer" is
not among them — no SCI16 text site chooses a buffer; `GfxScreen` does, from
`_upscaledHires` and the driver. What the four cases disputed is:

- which font this line is drawn with (S7, S9),
- whether the driver draws this line's glyphs or the low-res buffer does
  (S4, S6),
- where the pen is, in which space (D, below).

So a context carrying `{fontId, drawnByDriver, penX/penY-in-a-named-space}` is
earned by measurement. One carrying a destination surface is not — that is the
SCUMM layer's shape being copied without its problem.

### Ask the code that already knows

S7's fix is the pattern to generalise before introducing any new mechanism:
`FontIdForLine()` (`text16.cpp:698-705`) exposes a fact `Box()` computed
internally and threw away. It is 8 lines. The same question is worth asking of
`drawnByDriver`: `Box()` already knows it per line — that is what its
`doubleByteMode` local is (`text16.cpp:574, 586`) — and no caller can see it.

---

## C. `DrawString`: possible, and one third of it is a deletion

The card asks whether a line-at-a-time draw (the SCUMM layer's "string mode")
is achievable in SCI, or whether SSCI's per-character semantics forbid it.

**Verdict: possible for the Korean path; forbidden for the PC-98 path;
and the entry point the card wanted to promote should be deleted instead.**

### What `a1entry.py` measured

**[measured]** (`captures/2026-09-16/a1/a1-entry.txt`), callers resolved
across all of `engines/sci`, matched on argument count, headers excluded:

| entry point | args | level | dbcs-aware | callers |
|---|---|---|---|---|
| `DrawString` `text16.cpp:444` | 3 | LINE | no | **0 — dead** |
| `DrawString` `text16.cpp:707` | 1 | LINE | no | 5 (all `menu.cpp`) |
| `DrawStatus` `text16.cpp:724` | 1 | **CHAR** | **no** | 1 |
| `Draw` `text16.cpp:504` | 5 | CHAR | yes | 5 |
| `Show` `text16.cpp:556` | 5 | LINE | no | 2 |
| `Box` `text16.cpp:568` | 6 | LINE | no | 12 |
| `Width` `text16.cpp:381` | 7 | CHAR | yes | 3 |
| `StringWidth` `text16.cpp:434` | 4 | LINE | no | 6 |
| `GetLongest` `text16.cpp:198` | 3 | CHAR | yes | 2 |
| `Size` `text16.cpp:448` | 5 | LINE | no | 2 |
| `macDraw` `text16.cpp:948` | 6 | CHAR | no | 3 |

Three things fall out of this table that prose had not:

1. **The card's premise is half wrong.** `text16.cpp:444` has no call site
   anywhere in ScummVM. Promoting it is not a refactor, it is reviving dead
   code; deleting it is strictly better and costs nothing.
2. **`Box` is the real line-level entry point**, with 12 callers — more than
   every other text entry point combined. Any line-scoped design belongs
   *there*, not on `DrawString`.
3. **`DrawStatus` walks characters and is not double-byte aware at all**
   (`text16.cpp:741-752`: `uint16 curChar = *text++;` with no `isDoubleByte`
   test) **[source]**. The status bar of a Korean fan translation therefore
   cannot draw Hangul — it will index the font with single bytes. That is a
   latent Korean defect this card found while counting, and it belongs on its
   own card. **[unmeasured]** — no capture of a Korean status bar was taken.

### Why a line-at-a-time draw is possible for Korean and not for PC-98

`Draw()` (`text16.cpp:504-554`) does four things per character, and only one
of them is per-character in substance:

```cpp
uint16 charWidth = _font->getCharWidth(curChar);
if (_ports->_curPort->penMode == 1) { ... _paint16->eraseRect(rect); }  // per char
_font->draw(curChar, top + curTop, left + curLeft, penClr, greyedOutput);
_ports->_curPort->curLeft += charWidth;
```

- The `penMode == 1` erase is per-character **by construction** — it clears
  exactly `charWidth` before drawing. A line-level call would have to erase
  the line's box instead, which is a different rect and therefore a different
  observable result when a glyph is narrower than its cell.
- The pipe-code handler (`text16.cpp:533-538`) can change font and pen colour
  **mid-string** in SCI1.1. A line handed whole to a font cannot honour that.

So the honest statement is per-path:

- **Korean (`GfxFontKorean`, `UpscaledGfxDriver`)**: a line-level draw is
  possible. The glyphs go to `_gfxDrv->drawTextFontGlyph()` one at a time
  (`screen.cpp:484`), and the driver composites into `_scaledBitmap`; batching
  a run of them changes no pixel, only the number of `updateScreen` calls.
  **[unmeasured]** — argued from the code, not demonstrated.
- **PC-98 (`GfxFontSjis`)**: also possible in principle, same shape, but the
  `_textAlignX` quantisation (`upscaled.cpp:149`) is applied per glyph and is
  8 there (`pc98_8col_sci0.cpp:46`), so a batched run would have to re-apply
  it per glyph anyway and nothing is gained. **[source]**
- **Any font with pipe codes in the string, or `penMode == 1`**: not
  possible without changing observable behaviour. **[source]**

**The alternative, since a full line-mode is blocked:** keep the per-character
loop and move only the *decoding* out of it, which is what `decodeChar()`
already does for `controls16.cpp` and does not yet for `text16.cpp`. That is
step 2 in section E.

---

## D. The coordinate spaces: two are exact, one is lossy and unjustified

The card asks whether `putHangulChar`'s `x << 1` and `GfxFontKorean`'s `>> 1`
cancel, or lose information. `harness/a1coord.cpp` links the engine tree's own
`libgraphics.a`, loads the real 42,304-byte `korean.fnt` a Korean fan
translation ships, and measures.

A note on how this measurement nearly went wrong, because it is the kind of
error that produces a confident wrong table: the first run used
`gamedata/ft-kor-hr/korean.fnt`, which is a **20-byte stub** another harness
keeps in order to deny the font on purpose. `FontKoreanWansung::loadData()`
reads its header, `read()`s a short buffer, checks only `err()`, and every
`getCharWidth()` then answers from the header — so the stub produced a
complete-looking table for a font with no glyphs in it. The harness now counts
glyphs with ink over the whole population and refuses to report below a
quarter coverage.

**[measured]** (`captures/2026-09-16/a1/a1-coord.txt`, font md5
`ddce598577fe6edff0bef68a63200378`):

```
glyphs with ink: 2350 of 2350 indexable syllables
font height    : 9  (hires)
max font width : 10 (hires)

Q1  >> 1 losslessness
  double-byte  : 2350 chars, width 10..10 hires, 0 odd
  single-byte  : 128 chars,  width 5..5 hires, 128 odd
  height       : 9 hires, ODD - >>1 rounds down

Q2  left & 0xFFC displacement
  syllable advance (lowres)   : 5   [getCharWidth>>1]
  positions moved by the mask : 2400 of 3200
  worst displacement          : 3 lowres px (6 hires)
  mixed ascii+hangul line     : 2400 of 3200 moved, worst 3 lowres

Q3  invertibility of (x & 0xFFC) << 1
  distinct lowres x in 0..319 : 320
  distinct hires results      : 80
  VERDICT                     : NOT invertible
```

### What each conversion costs

| conversion | site | verdict |
|---|---|---|
| `getCharWidth() >> 1` | `fontkorean.cpp:63-68` | **exact for Hangul** (all 2,350 widths are 10, even), **lossy for ASCII** (all 128 widths are 5, odd → 2) |
| `getHeight() >> 1` | `fontkorean.cpp:56-61` | **lossy** — height 9 is odd, so the line height is 4 where the glyph is 4.5 |
| `left & 0xFFC` | `fontkorean.cpp:76` | **lossy and unjustified — see below** |
| `x << 1, y << 1` | `screen.cpp:484` | exact, and the correct place for the conversion |
| `&= ~(_textAlignX - 1)` | `upscaled.cpp:149` | **a no-op on the Korean path** — the field is set from a constructor argument (`upscaled.cpp:33-34`) which the Korean factory passes as 1 |

So the card's suspicion that `x << 1` and `>> 1` "cancel each other" is
**wrong in an interesting way**: they do not meet. The `>> 1` is applied to
*metrics* and the `<< 1` to a *coordinate*, and between them sits a third
operation nobody flagged.

### `left & 0xFFC` is the one to remove, and it is not SSCI behaviour

`GfxFontKorean::draw()` masks the port-absolute low-res x before handing it to
`putHangulChar()`, clearing the low two bits — so a glyph can be pulled up to
3 low-res (6 hi-res) pixels left of where `Draw()` advanced the pen to. With a
syllable advance of 5, **2,400 of 3,200 swept positions are moved** (75%), and
a mixed ASCII+Hangul line — i.e. the parser prompt — is no better.

The mask was copied from the SJIS font, where `fontsjis.cpp:72-77` documents
it as reproducing the PC-98 ROM's 40×25 text grid. **Korean has no such
grid**: the Korean path runs `UpscaledGfxDriver`
(`init.cpp:95`, the `Common::KO_KOR` row), which the factory builds with an
alignment of 1 (`upscaled.cpp:193-195`), meaning the driver asks for no
alignment at all. So on
the Korean path this mask is the *only* quantisation and there is no original
interpreter behind it to preserve.

**Verdict for D: conditional.** The spaces can be normalised at one boundary
— `screen.cpp:484` is that boundary and is already correct — *provided*
`fontkorean.cpp:76`'s mask is removed first, because it destroys information
before the boundary is reached (Q3: 320 distinct x values collapse to 80).
Removing it is a visible change to Korean text and needs an A/B capture; it is
step 1 in section E.

---

## E. Order, scope, and what closes each step

Five steps. Three are small and pay immediately. Each names what could break
and the measurement that closes it.

| # | step | size | breaks if wrong | closes on |
|---|---|---|---|---|
| 1 | **Delete `DrawString(str, fontId, penColor)`** (`text16.cpp:444`, `text16.h:66`) | 4 lines | nothing — it has no callers | `a1entry.py` shows the overload gone; build + full test suite |
| 2 | **Remove `left & 0xFFC`** from `GfxFontKorean::draw()` (`fontkorean.cpp:76`) | 1 line | Korean glyph positions shift by up to 3 low-res px — *that is the point*, but it must be shown to improve, not merely change | A/B capture of an SCI0 Korean line against the control build, plus `a1coord.py` re-run showing `positions moved: 0`; SJIS untouched by construction (different class) |
| 3 | **Point `text16.cpp`'s five byte-pair walks at `GfxFont::decodeChar()`** (`:214-216, :313-315, :350-353, :393-395, :515-517`) | ~25 lines, 1 file | every SCI16 game's text, every language — this is the shared path | the default `decodeChar()` returns byte-for-byte what each site computes for a single-byte font (`scifont.h:65-68`), so English/Mac/`FromResource` are unchanged *by construction*; unit test over 0x00–0xFF plus the 2,350 syllables; A/B capture sweep for Japanese, which has a real override |
| 4 | **Expose `drawnByDriver` per line**, the way S7 exposed `FontIdForLine` | ~15 lines | nothing reads it yet; it is a query with no side effect | a unit test that the query agrees with `Box()`'s own `doubleByteMode` on a Korean, a Japanese and an English line |
| 5 | **A line render context** carrying `{fontId, drawnByDriver, pen}` and threaded through `Box` → `GetLongest`/`Width`/`Draw` | large, `text16.cpp` + `controls16.cpp` | all SCI16 text on all platforms | not startable before 3 and 4; closes on the full capture matrix (English, Japanese, Korean, Mac) plus the 540-test suite. **Do not start this until 1–4 have landed and held.** |

### Scope notes

- **Steps 1–4 are fork-local and independently upstreamable.** Step 1 is a
  dead-code deletion with a zero-caller proof. Step 3 is the change
  `SCI_FONT_ENCODING.md` §D1 called "option 3" and priced as needing an A/B
  sweep — that price has not changed, but `decodeChar()` now exists and is in
  use, so the diff is smaller than when that document was written.
- **Step 2 is Korean-only by class.** `GfxFontSjis` keeps its own mask and its
  own justification; nothing shared is touched.
- **Step 5 is not upstreamable as one patch** and should not be attempted as
  one. `I1_ASSESSMENT` measured that wonst719's long fork failed by
  accumulating exactly this kind of unsplit change.
- **SCI32 is out of scope throughout.** `text32.cpp` carries twin copies of
  the pair assembly (`text32.cpp:440-441`, per `SCI_FONT_ENCODING.md`'s D1
  census) and this project has never run an SCI32 game.

---

## Found while counting, belongs on other cards

1. **`DrawStatus` cannot draw Hangul.** `text16.cpp:741-752` walks single
   bytes with no `isDoubleByte` test, so a Korean fan translation's status bar
   indexes the font with lead bytes. **[source]**, **[unmeasured]** — no
   capture taken. Own card.
2. **The three-argument `DrawString` is dead**, along with `#if 0`'d
   `ShowString` (`text16.cpp:438-442`) and `ClearChar` (`text16.cpp:80-91`)
   beside it. A tidy-up card. **[measured]** for `DrawString`, **[source]**
   for the other two.
3. **`FontKoreanWansung::loadData()` accepts a truncated font silently**
   (`korfont.cpp:210-228`: reads the header, `read()`s, checks only `err()`).
   A 20-byte file loads and answers metrics. Engine-side robustness card.
   **[measured]** — this card hit it.

## Unmeasured, and load-bearing

1. **That batching the Korean glyph run changes no pixel.** Argued from
   `screen.cpp:484` and the driver's compositing; not demonstrated.
2. **What step 2's capture will actually show.** The mask's removal is
   measured as a *displacement*, not as an improvement in legibility — the
   user is the visual gate on Windows.
3. **Whether any SCI1 Korean fan translation drives these paths differently.**
   Everything here is read against the SCI0 path Cascade Quest exercises.
