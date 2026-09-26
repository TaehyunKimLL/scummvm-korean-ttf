# The big-bang branch: what it would change, in what order, and what proves it

> **Status 2026-09-26: §2 A (branch strategy) is superseded.** The work did not
> continue on `hires-text`. A new line, `i18n`, was cut from upstream/master
> (see `i18n/TREES.md`), and `hires-text` was merged into it (`91cffbd25a`) and
> frozen as a record. The engine order (§4) and the proofs (§6) still apply,
> on `i18n`.

Written for card B0 (`t_7a5dbbf2`), which asks for a branch plan rather than
an implementation: which branch, in what order, proving what. Engine read at
`943cda2bcff` (branch `hires-text`), upstream at `c81c8695a44`, fork base
`41ac2b31847`. Harness at `harness/b0*.py` in the harness repo; captures under
`captures/2026-09-16/b0/`. Line numbers are only valid at that commit — the
four tools re-check their own transcriptions and fail rather than measure a
moved line.

**No engine code is changed by this card.** One probe was injected into
`engines/saga/font.cpp` to prove `b0dbcs.py` bites and reverted in the same
turn; §7 shows the tree clean.

Claims are one of three kinds and say which:

- **[source]** — a file:line in the engine. Static reachability only.
- **[measured]** — a number this card produced by running something.
- **[unmeasured]** — stated because it is load-bearing and nobody has checked it.

---

## Short answer

| | Question | Answer |
|---|---|---|
| **A** | Branch strategy | **Branch from `hires-text`, not upstream.** `hires-text` merges cleanly into upstream/master *today* with zero conflicts across 240 commits **[measured]**, so the usual reason to restart from upstream does not apply. Keep `hires-text` as the user's test build; the big-bang work lands on it through merges, one step per merge. |
| **B** | The three abstractions | **One of the three is earned, one is earned in a smaller shape than its name, and one is not earned at all.** `Font`/`FontSet` is earned — 5 engines hold a private lead-byte test and 4 hold a private pair assembly **[measured]**. "Hires Hicolor Surface" is **not** — the two surfaces disagree on all four properties that would let one class serve both, and neither is hicolor **[measured]**. `String` is **not** — the byte array is the game's own resource format, not a porting shortcut. |
| **C** | Engine order | **SCI first, then SCUMM, then queen, then touche; kyra, saga, sword1, agos and agi are out of the first branch.** SCI is the only engine where the *caller* assembles the pair, which makes it the one engine where the abstraction's shape is visible in the diff rather than assumed. |
| **D** | Relation to A1's five steps | **Includes, does not replace.** A1's steps 1–4 are B1/B2 here, unchanged and still first. A1's step 5 (a line render context) is **not** in this branch — the measurement that would justify it is not in. |
| **E** | Proof of safety | **Three tiers, and only three engines can reach the top one.** 3 of 9 engines are provable by capture here; 1 of 9 is provable by a direct probe with no engine at all; the other 5 get a compile plus the F1 glyph dump plus a written argument, and the plan says so rather than pretending otherwise **[measured]**. |

And the finding that most changes the card's framing:

**The parent session's per-engine table was wrong in both directions, and the
correction narrows the branch.** It counted `Common::KO_KOR`-style language
branches (which undercounts: saga and sword1 carry complete Korean paths gated
on a *font file*, not on the language enum, so an enum-keyed census reports
them as zero) and byte-level text manipulations (which overcounts: most are
opcode dispatch and filename handling). Counting the five *jobs* a text path
must do instead gives a population of 45 cells, of which **4 engines do no
double-byte work at all** and can only be *prepared* for it, not fixed
**[measured]**, §1.

---

## 1. The population, recounted: five jobs, not one number

`harness/b0dbcs.py` replaces the byte-manipulation count. A text path that
must handle a character wider than a byte has to answer five questions, and an
engine "has a private copy" of a job when it answers that question itself:

```
LEAD    decide whether a byte starts a two-byte character
PAIR    assemble the two bytes into one value
WIDTH   answer how wide that value is
DRAW    draw it
WRAP    decide where a line may break
```

**[measured]** (`captures/2026-09-16/b0/b0-dbcs.txt`):

```
engine       LEAD     PAIR    WIDTH     DRAW     WRAP
scumm         own      own      own      own      own
sci           own   caller      own      own      own
kyra          own      own      own      own      own
agi          none     none    fixed      own      own
agos         none     none      own      own      own
saga          own      own      own      own      own
queen        none     none      own      own      own
sword1        own      own      own      own      own
touche       none     none      own      own      own

own             5        4        8        9        9
none            4        4        0        0        0
```

The check bites twice and each was demonstrated:

1. **An engine with no disposition.** Adding `sword2` to the population makes
   it report `*** UNACCOUNTED *** engine sword2 has no disposition` and exit 1
   (`b0dbcs-bite1.txt`). So an engine someone adds to the branch later cannot
   join the table silently.
2. **A moved source line.** Inserting one blank line into
   `DefaultFont::getStringWidth` makes it report **two** `*** MOVED ***` lines
   for saga and exit 1 (`b0dbcs-bite2.txt`). The clean tree exits 0 with 37
   transcriptions checked.

### 1.1 What the table says that the count did not

**Four engines have no double-byte path at all** — agi, agos, queen, touche.
For them there is nothing to "clean up"; there is only work to *add*. This is
the single largest correction to the card's premise: the branch cannot be
described as tidying similar code in nine places, because in four of the nine
the code does not exist.

**Two engines were invisible to the enum-keyed census.** saga's
`getStringWidth` gates its double-byte arm on `isCJK = _chineseFont ||
_koreanFont` (`engines/saga/font.cpp:517`) **[source]** — the *font object*,
never the language — and sword1 gates on a Korean `.clu` being present
(`engines/sword1/resman.cpp:146`) **[source]**. Both carry complete Korean
rendering. A census keyed on `Common::KO_KOR` reports both as zero, which is
exactly what the parent session's table did.

**One engine has the defect the abstraction is named after.** SCI is the only
`caller` in the PAIR column: the caller reads a byte, asks the font
`isDoubleByte()`, and then does the font's arithmetic itself
(`engines/sci/graphics/text16.cpp:216`) **[source]**. Every other engine at
least keeps the assembly in the layer that owns the font.

**And one engine holds the same job twice.** kyra's `Screen::fetchChar`
(`engines/kyra/graphics/screen.cpp:1668`, `:1671`) assembles the pair against
the *current font's type*, and `TextDisplayer::getCharLength`
(`engines/kyra/text/text.cpp:64`) assembles it again with its own
`JA_JPN || KO_KOR` test rather than calling `fetchChar` **[source]**. Two
answers to one question inside one engine is the same shape as S4↔S7 — the
defect this whole branch is a response to — and it is already present in an
engine nobody here has touched.

### 1.2 So is the code "similar"?

Partly, and the split is informative. **The LEAD job genuinely is duplicated**:
I1 measured five byte-identical copies of the `0xB0..0xC8 && 0xA1..0xFE`
predicate plus two lead-only copies **[measured, I1 §2]**, and `b0dbcs.py`
attributes them to their engines. **The WIDTH, DRAW and WRAP jobs are not
similar in any useful sense** — nine engines, nine different font formats,
nine different destination surfaces. queen indexes a 256-entry width table
(`engines/queen/display.cpp:1022`); touche asserts `chr >= 32 && chr < 32 + _fontSize`
(`engines/touche/graphics.cpp:74`); saga's is a per-glyph tracking value; SCUMM's is a
`CharsetRenderer` virtual with 13 subclasses **[source]**.

That asymmetry is what makes the branch plan the shape it is: **the shared
thing is the encoding, not the rendering.** Steps B3 and B4 below unify the
encoding across nine engines because it really is one thing nine times; the
rendering is left alone in eight of them.

---

## 2. A. Branch strategy

### 2.1 Branch from `hires-text`

The reason usually given for restarting from upstream is that a long fork has
drifted. Measured, this one has not:

**[measured]** `git merge-tree` of `hires-text` against `upstream/master` over
the 240 commits since the fork base produces **0 conflicts**. The branch also
carries 128 files, 79 added and 49 modified (+20285/−605) **[measured]**, and
I1 measured those 240 upstream commits touching **0** of our added files and
**2** of our modified ones **[measured, I1 §5.1]**.

So branching from upstream would discard a clean, current, merge-ready branch
in order to avoid a merge cost that has been measured at zero. Branch from
`hires-text`.

### 2.2 `hires-text` stays the user's test build

It is where the Windows cross-build comes from and where every user-verified
commit lives. Each big-bang step merges *into* it when its own gate is green,
which is what the S-chain already does — `943cda2bcff` is a merge of
`wt/s10-curtests-src`, not a rebase.

### 2.3 What the big-bang branch actually costs, per step

This is the number the card asked for and the reason the branch is affordable.
`harness/b0fork.py` measures, per file each step would touch, how many upstream
commits landed on it in the last 12 months and how many distinct authors that
was.

**[measured]** (`captures/2026-09-16/b0/b0-fork.txt`):

```
B1 decodeChar into text16                    4 upstream commits / 12 months
B2 drop the Korean quantisation              0
B3 a lead-byte predicate in Common           0
B4 route the private predicates through it   0
B5 DBCSFontBase under the graphics fonts     2
B6 the engine text paths, one at a time     15

all steps: 21 upstream commits across every file the plan touches
```

Read that against the whole tree's rate: I1 measured **12,549** upstream
commits in 12 months **[measured, I1 §5.1]**. The files this branch edits
absorb **21** of them. `common/str-enc.{h,cpp}` — the file the "shared
infrastructure" step adds to — has had **zero** upstream commits in a year,
and so have `graphics/korfont.cpp`, `engines/sword1/text.cpp`,
`engines/saga/font.cpp`, `engines/grim/font.h` and `engines/queen/display.cpp`
**[measured]**.

**This inverts the card's own framing, and it should be said plainly: the
big-bang branch is NOT more expensive to carry than the parallel layer.** The
parallel layer is cheap because upstream never touches new files; this branch
is cheap because upstream barely touches the *old* files either. The
expensive files in this project are the registration points —
`engines/scumm/scumm.cpp` at 46 commits/year, `module.mk` at 32
**[measured, I1 §5.1]** — and this plan touches none of them.

The check bites: naming a file that does not exist (`common/leadbyte.h`) makes
it report `*** MISSING ***` and exit 1 (`b0fork-bite.txt`). A plan written from
memory fails rather than reading plausibly.

### 2.4 Which pieces are independently upstreamable

Marked per step in §5. Three of the six are, and B3+B4 together are the
strongest upstream story this project has produced — they delete duplication
rather than adding a feature, and I1 already established the reviewer
precedent: sluicebox's standard on PR #2604 was *name the condition, explain
why*, not *avoid touching shared files* **[measured, I1 §5.4]**.

### 2.5 Merge cadence

Unchanged from I1 §5.3: merge upstream monthly on a fixed day. The new thing
this branch adds is that **`b0dbcs.py`, `b0fork.py`, `b0surface.py` and
`b0reach.py` all fail on a moved line**, so a merge that reshapes any file
this plan depends on is caught by the harness before anyone reads a rendering.

---

## 3. B. The three abstractions, and which are earned

The user named three. Measured, they are not three equal candidates.

### 3.1 Hires Hicolor Surface — **not earned, and the name is wrong twice**

`harness/b0surface.py` compares the SCUMM text plane against the SCI scaled
bitmap on the four properties that decide whether one class can serve both.

**[measured]** (`captures/2026-09-16/b0/b0-surface.txt`):

| property | SCUMM | SCI |
|---|---|---|
| planes | **2** — index + optional coverage (`engines/scumm/hires_overlay.cpp:31`, `:116`) | **1** — a flat `new byte[...]` (`engines/sci/graphics/drivers/upscaled.cpp:64`) |
| format | CLUT8, deliberately (`engines/scumm/hires_overlay.cpp:31`) | `_srcPixelSize` bytes, and **1** on the Korean path (`engines/sci/graphics/drivers/default.cpp:118`, called with no format at `engines/sci/graphics/screen.cpp:195`) |
| scale | 1..3, user's choice (`engines/scumm/hires_text.cpp:1393`) | **fixed 2**, in the constructor (`engines/sci/graphics/drivers/upscaled.cpp:35`) |
| owner | the **engine** (`engines/scumm/hires_overlay.h:63`) | the **driver** (`engines/sci/graphics/drivers/upscaled.cpp:41`) |
| entry | per glyph, writing into a public `Surface&` (`engines/scumm/hires_overlay.h:95`) | per glyph, through `drawTextFontGlyph()` (`engines/sci/graphics/drivers/upscaled.cpp:147`) |

Four properties, four disagreements. And two corrections to the name:

1. **Neither is hicolor.** Both are CLUT8. SCUMM's is CLUT8 *on purpose* — the
   planes store palette indices so a later palette change recolours text drawn
   long before (`engines/scumm/hires_overlay.h:43-47`) **[source]**, which is the mechanism
   the MI2 night-island fade bug turned on. SCI's is CLUT8 because
   `GfxScreen` calls `initScreen()` with no pixel format (`engines/sci/graphics/screen.cpp:195`)
   **[source]**. Hicolor appears only at the *output* end of SCUMM's
   compositor, where `HiResPalette16Sink` and `HiResTrueColorSink` resolve
   indices per frame (`engines/scumm/gfx.cpp:829-841`) **[source]** — and that is a sink, not
   a surface.
2. **SCI's side is already abstracted.** `drawTextFontGlyph()` takes a
   rasterised glyph and hi-res coordinates; the caller never touches the
   destination. A1 said the same thing about SCI's pixel writes: the engine is
   not short of a pixel abstraction **[measured, A1 §A]**.

**Verdict: do not build it.** The hi-colour case the card asks for — "our alpha
text path needs it" — is real but it is SCUMM's, it already exists as
`HiResSink` with three implementations, and SCI cannot use it because SCI has
no coverage plane to blend from. Giving SCI antialiased text is a real card;
it is *adding a second plane to `UpscaledGfxDriver`*, not extracting a shared
surface class.

**The honest counter-argument, recorded:** `HiResOverlay::bandFor()`
(`engines/scumm/hires_overlay.h:159`) is a genuine shared rule — coordinate conversion
between a virtual screen and a scaled plane — that SCI re-derives as
`x << 1, y << 1` (`engines/sci/graphics/screen.cpp:484`) plus `getRealCoords()` (`engines/sci/graphics/drivers/upscaled.cpp:143`)
**[source]**. That is two cases of one rule, which by this project's own
standard is not yet an abstraction.

### 3.2 Font / FontSet — **earned, in the LEAD+PAIR shape only**

The measurement is in §1: five private LEAD answers, four private PAIR answers,
and I1's five byte-identical copies of one predicate. That is the duplication
the card is looking for and it is real.

What it is *not* is a `FontSet`. The card asks whether
`FontKoreanWansung`-holding-Hangul-and-English (`graphics/korfont.h:190-218`) **[source]**
means SCI should stop switching fonts. It does not follow:

- `SwitchToFont1001OnKorean` (`engines/sci/graphics/text16.cpp:762`) decides **which font resource
  to load**, by sniffing bytes before any font exists **[source]**. S3b already
  ruled this out of font ownership for exactly that reason — *there is no font
  yet when it runs* **[measured, S3b §D1]**.
- Font 1001 is a **fan-translation asset contract**: it is the id the Korean
  patches on users' disks ship (`engines/sci/graphics/cache.cpp:70`) **[source]**, and I1 classified
  34 such contracts as must-stay **[measured, I1 §1.1]**.

So the earned abstraction is the one F1 already built —
`Graphics::DBCSFontBase` (`graphics/dbcsfont.h:55`), which owns the drawing
modes, the 1-bit blitter and the outline builder, and asks a language for
`getCharData` + `hasFeature` + `isASCII` + `getASCIIWidth` **[source]** — plus
**one new virtual it does not yet have**: the lead-byte predicate. That is
B3/B4/B5.

`GfxFont::decodeChar()` (`engines/sci/graphics/scifont.h:65`) is the SCI-side half and already
exists, with five live call sites in `controls16.cpp` **[source]**. B1 is
finishing what S4 started.

### 3.3 String — **not earned, and the reason is per engine**

The card asks why text paths do not use `Common::U32String`, given 329 files
already do. Measured per engine in this population: **[measured]**

```
scumm 23 files   sci 16   kyra 5   saga 5   sword1 4   agi 3   agos 3
queen 2   touche 2
```

and inspecting them: in agi, queen, sword1 and saga the U32String uses are
`canLoadGameStateCurrently(Common::U32String *msg)`, save-slot descriptions and
translated GUI messages **[source]**. **Not one is in a text path.** So the
number is not evidence of adoption; it is evidence that the GUI and the
metaengine already use it and the text paths do not.

Three reasons they do not, and they are different reasons:

1. **The byte array is the game's resource format.** SCUMM's translated text
   arrives as `korean.trs` records that are 64.7% inline binary opcodes
   **[measured, P1 §1.1]**; converting to U32String and back would have to
   preserve those byte-for-byte.
2. **The bytes go back into the game.** SCI's edit control holds the player's
   input in script 996's own local-variable block (`segtype=3`) **[measured,
   S3b M1]**, which the game then hands to `kParse`. A code-point buffer would
   have to be re-encoded before the game could read it — which S3b's M2 showed
   is exact and cheap, but it is a conversion at a boundary, not a change of
   representation throughout.
3. **Nobody has tried.** kyra, saga, queen, touche, agos have no reason beyond
   inertia, and three of them have no double-byte path to convert.

**Verdict: out of this branch.** A U32String text path is a fourth branch after
the encoding is unified, and its first engine should be touche — the only one
whose renderer is callable without an engine instance (§6), so the conversion
can be proven byte-for-byte by a probe.

---

## 4. C. Engine order

**SCI, then SCUMM, then queen, then touche. Stop there for this branch.**

| # | engine | why here | what it decides |
|---|---|---|---|
| 1 | **sci** | the only `caller` in the PAIR column (§1) — the defect the abstraction is named after is visible in this engine and nowhere else; and `decodeChar()` already exists with 5 call sites **[source]** | the interface. Whatever `decodeChar` looks like after B1 is what the other eight engines get. |
| 2 | **scumm** | the largest text path (5,594 lines across three files **[measured]**), the one with game data, a harness, and a user who tests it on Windows | whether the interface survives 13 `CharsetRenderer` subclasses. If it does not, better to learn it here than in an engine nobody can run. |
| 3 | **queen** | no double-byte path at all, and its WIDTH job is a single 256-entry byte-indexed table (`engines/queen/display.cpp:1022`) **[source]** | whether *adding* the capability to a clean engine is small. This is the cheapest possible test of the "new language costs three functions" claim. |
| 4 | **touche** | the only engine whose renderer is static and takes a destination pointer (`engines/touche/graphics.h:39`) **[measured]**, so it is provable with no engine instance | whether the change can be proven byte-for-byte without a game. |

**Why not start with the most complex.** The card asks. SCUMM is the most
complex and it is *second*, not first, because SCI is where the interface's
shape is already half-built and where the defect is diagnosable. Starting with
SCUMM would mean designing the interface against 13 subclasses before any of it
had been exercised once.

**Why kyra is out despite being large.** kyra has 15 CJK branches and 566
byte-level manipulations by the parent session's count, which made it look like
the second-biggest prize. It is out because: no game data here, no way to run
it, and — the finding in §1.1 — it already contains an S4-shaped defect (two
copies of PAIR disagreeing). Fixing that is a real card and it should be its
own, opened with a measurement, not folded into a nine-engine sweep.

**Why saga, sword1, agos and agi are out.** saga and sword1 carry font-gated
Korean paths that no test here can exercise; agos has no double-byte path and
nothing separable (`AGOSEngine::doOutput` is a method on the engine class
**[measured]**); agi's Korean work lives on `wt/k6-agitrs-src` with 11 unmerged
commits and should land on its own terms first.

---

## 5. D. Relation to A1's five steps, and the step list

**The big bang INCLUDES A1's steps 1–4 and EXCLUDES its step 5.**

A1 ordered five steps for SCI and said step 5 must not start until 1–4 have
landed and held **[measured, A1 §E]**. That condition is kept. Steps 1–4 are
B1 and B2 below, unchanged.

A1's step 5 — a line render context carrying `{fontId, drawnByDriver, pen}` —
is **not in this branch**, and the reason is a measurement, not caution: A1
justified it on four cases (S4, S6, S7, S9) that all disagreed about *one
line's font or driver ownership* **[measured, A1 §B]**. Every one of those four
is SCI. A render context justified by four SCI defects is an SCI change, and
this branch is about the thing nine engines share. Folding it in would make the
branch's subject two things at once, which is the commit message needing the
word "also".

### The steps

| # | step | files | upstream churn | gate | upstreamable alone |
|---|---|---|---|---|---|
| **B1** | Point `text16.cpp`'s five byte-pair walks at `GfxFont::decodeChar()` (`:216, :315, :353, :395, :517`), and delete the dead 3-argument `DrawString` (`engines/sci/graphics/text16.h:66`) | 4 | 4 commits/yr | `a1entry.py` shows the overload gone; `a1census.py` BYTEWALK REPLACE count drops from 8; full test suite; A/B capture on Cascade Quest + a Japanese SCI target | **yes** — S3b priced this as "option 3" and A1 as step 3 |
| **B2** | Remove `left & 0xFFC` from `GfxFontKorean::draw()` (`engines/sci/graphics/fontkorean.cpp:76`) | 1 | 0 | `a1coord` re-run showing `positions moved: 0`; A/B capture of an SCI0 Korean line; **user's eye on Windows** — this moves glyphs by design | **yes**, Korean-only by class |
| **B3** | Add `Common::isLeadByte(CodePage, byte)` beside the conversions that already exist (`common/str-enc.h:73`) | 2 | 0 | unit test over 0x00–0xFF × the five code pages, against Python's codecs; `i1cover.py` accept/reject counts unchanged per site | **yes** — I1 ranked this as the only genuinely missing piece of `Common::` infrastructure |
| **B4** | Route the seven private lead-byte copies through it (`graphics/korfont.cpp:35`, `engines/scumm/charset.h:48`+`:67`, `engines/grim/font.h:55`, `engines/sword1/text.cpp:355`, `engines/sword2/maketext.cpp:709`, `engines/saga/font.cpp:521`) | 6 | 0 | `i1cover.py` showing every site delegating **with its accept/reject count unchanged** — the point is to stop duplicating, not to change behaviour; and I1's bounds defect fixed in the same step, since `0xB0..0xD0` vs `0xB0..0xC8` is exactly what the shared predicate settles | **yes**, and it carries a bug fix |
| **B5** | Widen `DBCSFontBase` (`graphics/dbcsfont.h:55`) to own the lead-byte question as well | 6 | 2 | `f1dump.sh` byte-identical before and after — the 2.85 GB glyph dump F1 already built — **after extending `f1glyphdump.cpp` to include `graphics/big5.h`, which it does not today** **[measured]**; `i1fonts.py` reporting 0 duplicated bodies | **yes**, after B3/B4 |
| **B6** | The engine text paths, in the §4 order: sci → scumm → queen → touche | 9 | 15 | per engine, the §6 tier its reachability allows | **no** — one engine at a time, each its own card |

**B6 is four cards, not one.** Each engine gets its own card with its own
closing measurement. The branch is finished when SCI and SCUMM are converted
and unchanged by capture; queen and touche are the demonstration that a new
language is cheap, and they are allowed to slip.

### First commit, concretely

Branch name: **`wt/b1-decodechar`**, cut from `hires-text`.

First commit: *"SCI: let the font decode its own characters in text16"* — the
five `decodeChar()` call sites, plus the `DrawString` deletion, plus a unit
test extending `test/engines/sci/font_decodechar.h` (10 tests today) to cover
the `text16` path. First card: **B1** as written above.

The `DrawString` deletion rides with B1 rather than getting its own commit
because it is four lines with a zero-caller proof **[measured, A1 §C]** and
both changes are in the same function neighbourhood; splitting them would cost
a build cycle for no reviewability.

---

## 6. E. What proves safety

The card is right that this is what decides the branch. `harness/b0reach.py`
measures what each engine's text path needs in order to be *called*, because
that is what determines which proof is available.

**[measured]** (`captures/2026-09-16/b0/b0-reach.txt`):

```
engine   reach   entry point                  data?  site
touche   free    Graphics::drawString16       no     engines/touche/graphics.h:39
saga     vm      DefaultFont::draw            no     engines/saga/font.h:200
queen    vm      Display::drawText            no     engines/queen/display.h:43
sword1   vm      Text::makeTextSprite         no     engines/sword1/text.h:50
kyra     vm      Screen::drawChar             no     engines/kyra/graphics/screen.h:640
agos     engine  AGOSEngine::doOutput         no     engines/agos/charset.cpp:64
scumm    vm      CharsetRenderer::printChar   yes    engines/scumm/charset.h:109
sci      vm      GfxText16::Draw              yes    engines/sci/graphics/text16.h:47
agi      engine  TextMgr::charAttrib          yes    engines/agi/text.h:84

free 1   vm 6   engine 2
game folders on disk: 58
provable by capture here: scumm, sci, agi
provable only by probe or by reading: touche, saga, queen, sword1, kyra, agos

Font coverage from F1's glyph dump (harness/probes/f1glyphdump.cpp):
   graphics/korfont.h     FontKorean   dumped=yes
   graphics/sjis.h        FontSJIS     dumped=yes
   graphics/big5.h        Big5Font     dumped=NO
```

### 6.1 The three tiers

**Tier 1 — golden dump, no game.** F1's precedent: link the tree's own
`libgraphics.a` into a probe and dump every glyph × every drawing mode × both
bit depths, then compare bytes. 2.85 GB, byte-identical, and it needs no game
and no OSystem beyond the test suite's null one (`harness/f1dump.sh`)
**[source]**. This covers **B5 completely**, because B5's whole subject is the
three `graphics/` font classes the dump already enumerates. It also covers
**touche entirely** — its renderer is static and takes `uint8 *dst, int
dstPitch` (`engines/touche/graphics.h:39`) **[measured]**, so a probe can call
`drawString16()` into a buffer with no engine at all.

**This is the tier to design for.** It is the only one that measures the whole
population rather than a scene.

**Tier 2 — capture against a control build.** scumm, sci, agi. Game data on
disk, `b4ab.sh`/`sceneab.sh` already built, and the traps already written down:
`hires_text_scale=1` is not a control (the map is still found), the two sides
are not pixel-diffable at different scales, and a shape difference is not a
pixel count **[skill: scummvm-korean-hires-ttf]**. B1, B2 and B6's first two
engines close here.

**Tier 3 — compile plus the shared-font dump plus a written argument.** kyra,
saga, queen, sword1, agos. They cannot be run here. What they *can* get:

- a build with the branch applied (catches the majority of B3/B4 breakage,
  because the change is a predicate's call site);
- **tier 1 coverage of the fonts they share**: `graphics/korfont.h` serves
  SCUMM, SCI, SAGA and sword1's Korean, and `graphics/sjis.h` serves SCUMM,
  SCI, KYRA and SAGA's Japanese — both are dumped by
  `harness/probes/f1glyphdump.cpp` today. **`graphics/big5.h` is NOT**: the
  probe includes `korfont.h` and `sjis.h` and nothing else **[measured]**, so
  SAGA's and KYRA's Chinese has no tier-1 coverage and B5 must add it. So for
  these five engines the *font* half of the change is proven for two languages
  out of three, and the engine half is not proven at all;
- a unit test on the predicate itself, which is where their behaviour actually
  changes in B4;
- an explicit statement in the commit that no runtime evidence exists.

**The rule this card sets: a step whose engines are all tier 3 does not land
without a tier-1 dump covering the shared code it touches.** B4 qualifies
(its shared code is the predicate, unit-testable); B6 for kyra/saga/sword1
does not, which is why they are out of the branch (§4).

### 6.2 The golden dump for the text path, and what it cannot do

The card asks for a dump-and-compare device for the whole text path, on F1's
model. Designed:

**Dump:** for each (engine-reachable renderer, font, drawing mode), a
rasterisation of a fixed character population into a fixed-size buffer, plus
the per-character advance the renderer reported. Advance *and* pixels, because
S7/S9's defect was a measure/draw disagreement that pixels alone would show as
"the text moved".

**Compare:** bytes, before and after, per cell.

**What it covers:** everything below the font interface — tier 1 — and touche.

**What it cannot cover, and this is the limitation to state rather than paper
over:** the six `vm` and `engine` engines' *layout*. Where a line breaks, where
the pen starts, which font a line is drawn with — the S4/S6/S7/S9 class of
defect — lives above the font and needs the engine running. For scumm/sci/agi
that is tier 2. For kyra/saga/sword1/agos/queen it is **[unmeasured]** and the
branch must say so.

**Reuse, concretely:** `f1dump.sh` already builds a probe against the tree's
own libraries with the engine's real compile flags, and `f1flags.mk` exists
because grepping `config.mk` drops SDL's include path **[source]**. A text-path
dump is that script with a different probe source. Nothing new is needed on the
build side.

---

## 7. Scope, and the probe

**No engine code changed.** The engine worktrees are clean:

```
$ git -C repo/scummvm status --short engines/
(empty)
$ git -C repo/scummvm/.worktrees/t_ae8fa12a status --short
(empty)
```

**One probe was injected and reverted.** A blank line inserted into
`DefaultFont::getStringWidth` (`engines/saga/font.cpp:510`) in the
`t_ae8fa12a` worktree, to prove `b0dbcs.py`'s transcription check bites. It
reported two `*** MOVED ***` lines for saga and exited 1
(`captures/2026-09-16/b0/b0dbcs-bite2.txt`); reverted with `git checkout`, and
the clean run exits 0 with 37 transcriptions checked.

`b0fork.py`'s bite is non-invasive — a file name that does not exist — and
`b0surface.py` / `b0reach.py` carry the same transcription guard by
construction (11 and 9 pinned lines).

---

## 8. Reproducing every number here

```bash
cd ~/work/scummvm/.worktrees/t_7a5dbbf2/harness
B0ENG=~/work/scummvm/repo/scummvm python3 b0dbcs.py      # §1  the five jobs
B0ENG=~/work/scummvm/repo/scummvm python3 b0fork.py      # §2.3 churn per step
B0ENG=~/work/scummvm/repo/scummvm python3 b0surface.py   # §3.1 the two surfaces
B0ENG=~/work/scummvm/repo/scummvm python3 b0reach.py     # §6  reachability
```

Each derives the engine tree from its own location and accepts `B0ENG` to
override; none spells a card id.

---

## 9. Where the measurement argues against the user's instruction

The card asks for this section explicitly, and there are two places.

**1. "Hires Hicolor Surface" should not be built.** §3.1. Four properties, four
disagreements, and neither surface is hicolor. The real request underneath it —
antialiased text in SCI — is a different change (give `UpscaledGfxDriver` a
coverage plane) and deserves its own card with its own measurement.

**2. "Nine engines" is four.** §1.1. Four of the nine have no double-byte path
to clean up, and of the five that do, two (kyra, saga) cannot be run here at
all and one (sword1) is a single 440-line file. The branch that is actually
supported by measurement converts **sci and scumm**, adds the capability to
**queen and touche** as proof the interface is cheap, and leaves the rest as
cards.

Neither is a reason not to do the branch. Both narrow it to the part that has
an order and a means of proof — which is the condition the card itself set.

## 10. Unmeasured, and load-bearing

1. **That B1's five call-site conversions change no pixel.** Argued from
   `decodeChar()`'s behaviour-preserving default (`engines/sci/graphics/scifont.h:65`) and from S4
   having already used it in `controls16.cpp` without a capture regression; not
   demonstrated across the Japanese and Mac SCI paths.
2. **That the layout half of the text path is unchanged for the five tier-3
   engines.** §6.2. There is no way to measure it here and the branch must say
   so in every commit that touches them.
3. **What B2's capture will show.** A1 left this open and it stays open: the
   mask's removal is measured as a displacement, not as an improvement. The
   user is the visual gate.
4. **Whether kyra's two PAIR copies actually disagree in practice.** §1.1
   establishes they are two independent answers to one question; nobody has
   found an input where `fetchChar` and `getCharLength` differ. That is a card,
   and it starts with the measurement.
5. **Whether `Common::isLeadByte` can express all seven predicates.** B3
   assumes one function with a `CodePage` argument covers them; two of the
   seven test only the lead byte and two accept any high-bit byte
   **[measured, I1 §2]**, so the signature may need a second form.
