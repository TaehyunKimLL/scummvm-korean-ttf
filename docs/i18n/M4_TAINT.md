# M4 — Does any SCI script do byte arithmetic on TRANSLATABLE text?

Measurement card M4. Method: taint the bytes that a fan translation would
replace, at the point the engine copies them into script-visible memory, then
report every script-visible byte operation whose operand range intersects
tainted bytes.

Probe commit: **d819c9acf51** (`SCI: M4 measurement probe — taint resource
text, report byte-op sinks`), removed in the follow-up commit so branch `i18n`
ends clean.

Every claim below is marked `[source]` (read from the code), `[measured]`
(produced by a run whose artefacts are named) or `[unmeasured]`.

---

## 0. The question, and the shortest answer

M1 (`M1_SCI_OWNERSHIP.md`) concluded SCI cannot convert its internal text to
code points because 49 of 50 kernel ops that carry game text expose byte
semantics to the game script.

The counter-argument: those kernel ops are called by the game's ORIGINAL
scripts on the game's OWN strings. A fan translation replaces the TEXT/MESSAGE
resources — the dialogue. Nobody writes a script that does byte arithmetic on
translated dialogue. So the two sets may be **disjoint**, and if the overlap is
empty the byte fence is only needed at the parser/edit-control boundary.

**The sets are not disjoint. [measured]** In one SCI0 game, driven for one
session, a game script read **6,906 individual bytes out of resource-loaded
dialogue** via `kStrAt`, and compared tainted dialogue **14,120 times** via
`kStrCmp`. Both survived a content re-verification (see §2.3).

But the *shape* of that overlap matters more than its existence, and it is
narrower than M1's conclusion implies — see §5 and §7.

---

## 1. Taint sources: where translatable bytes enter script-visible memory

Found by reading every writer into a script buffer, not by trusting the card's
list. `[source]`

| Entry point | File:line | Mechanism |
|---|---|---|
| `kGetFarText` | `kstring.cpp:447` | `lookupText()` → `strcpy_` into a script buffer |
| `MessageState::outputString` | `message.cpp:506` | MESSAGE record → `strcpy_` / `SciArray::fromString` |
| `kFormat` | `kstring.cpp:256` | format string and/or `%s` operand from a TEXT resource → `strcpy_` to dest |
| `kDisplay` | `kgraphics.cpp:1264` | `lookupText()`; draws directly, does **not** hand bytes to the script |
| `Kernel::lookupText` | `kernel.cpp:889` | the common TEXT-resource reader under all of the above |
| `kStrSplit` | `kstring.cpp:593` | propagates whatever its source was |

`kDisplay` with a resource id is the interesting one: the bytes go
resource → engine → screen and the script never holds them. It is counted
separately as `IMMEDIATE`. `[source]`

Taint propagates through `kStrCpy` and `kStrCat` (src tainted ⇒ dest tainted)
and is *cleared* when a clean value overwrites a tainted range — 161 untaint
events fired, so the tracker is not simply accumulating. `[measured]`

### Coverage: a run where nothing was tainted would prove nothing

```
RESLOAD  TEXTres      reads=185  bytes=1848      # resource text read by the engine
TAINTSRC kGetFarText  events=185 bytes=2033      # copied into script-visible memory
TAINTSRC TOTAL        events=185 bytes=2033  untaint_events=161
```
`[measured]` — 185 distinct taint events, 2,033 tainted bytes. The run is not
empty, so its negative results (§4) are meaningful.

`kMessage`/`outputString` fired **zero** times: Cascade Quest is SCI0 and uses
TEXT resources, not MESSAGE resources. The MESSAGE path is therefore
**instrumented but unexercised**. `[unmeasured]`

---

## 2. Method, and three ways it was wrong first

Each of these was a real defect in this probe that produced plausible but
false numbers. They are recorded because the corrected numbers are only
trustworthy if the corrections are visible.

**2.1 A gated probe proves nothing.** The probe is unconditional — no
`getenv`, no debug channel. A `getenv`-gated probe silently never runs when the
launcher does not export to the child, and the experiment then "proves" the
null result.

**2.2 The VM stack is recycled.** Cascade Quest hands `kGetFarText` a
**VM-stack** address as its destination buffer (`segtype=4`). Stack memory is
reused by every later frame, so taint left on a dead frame makes an unrelated
later buffer read as TAINTED. Two defences: taint at or above the live stack
pointer is pruned before each kernel call (38 ranges / 788 bytes pruned
`[measured]`), and —

**2.3 — every TAINTED verdict is content-verified.** Each tainted range stores
the first 23 bytes written into it; a TAINTED verdict survives only if a
re-read of memory still matches. `STALEREJECT hits=0` `[measured]` — no hit in
the final run was a recycled-memory artefact. This is what makes §0's numbers
usable.

**2.4 An unknown-length operand must use the string length.** Using the
segment's *remaining size* makes any buffer near the start of an 8 KB segment
intersect every tainted range in it and read TAINTED regardless of content.
Fixed to use `strlen`+1; this alone moved `kStrCmp` from 20,120 TAINTED /
0 CLEAN to a split that tracks content.

**2.5 The probe crashed the process and the run still looked clean.** A
file-scope `TaintTracker` destructor runs from `exit()` after ScummVM's memory
pool is gone: `pure virtual method called`, `exit_code 134`, core dumped —
*after* the game had finished and the report had been written. Fixed by
leaking the instance. Verified: `exit_code 0`, `grep -c 'assert|core dumped|
Segmentation' = 0`. `[measured]`

Build gate on every run: `make -j32 2>&1 | grep -cE ' error'` = 0 and the
binary timestamp newer than the edit. `make test`: 412/425 pass; the 13
failures are all in `test/graphics/fontset.h`, an **untracked file from an
unrelated card** present in this worktree, and are not caused by this probe.
`[measured]`

---

## 3. What was driven, and the coverage bound

Harness: `harness/i18n/m4taint.sh` (Xvfb, `xdotool windowfocus`, per-phase
report snapshots). Artefacts in `/tmp/m4run/`: 13 PNG frames,
`report_final.txt`, `run.log`, `status.txt`.

Reached `[measured]`: intro text boxes; the parser prompt with five phrases
typed a character at a time and submitted; the inventory key; save with a typed
description; restore; ego movement on the numeric keypad.

**Coverage bound — stated plainly. The run visited exactly ONE room:
`ROOMS_VISITED 1 : 528(x1)`. [measured]** The card asked for at least one full
scene transition and this run did not achieve one; every TAINTED count in this
document therefore comes from a single room's scripts. Two earlier attempts to
force a transition failed and are recorded because the failure mode is
instructive: typed compass words ("north", "go north") are not how an SCI0 game
moves the ego, and the plain **arrow keys open the menu bar** rather than
walking (visible in the capture — File/Action/Speed/Sound dropped down, ego
unmoved). The numeric keypad is the correct input and was used in the final
run, but the ego still did not cross a room edge within the driving window.

This bounds generalisation: the finding is *a script in room 528 of one fan
game*, not *scripts in general*. It does **not** weaken the refutation itself —
one confirmed TAINTED `kStrAt` on resource text is sufficient to refute a
disjointness claim, and there are 6,906 of them — but it does mean the
*frequency* and *distribution* figures describe one room.

Phases observed: `boot`, `parser_submit`, `editcontrol`, `save`, `restore`.

---

## 4. Results per sink

TAINTED = operand intersects content-verified resource-derived text.
SCRIPTLIT = operand lives in a SCRIPT segment (a literal compiled into the
script; a translation of TEXT/MESSAGE resources does not change it).
CLEAN = script-built memory. IMMEDIATE = not a pointer (a number or a TEXT
resource id). `[measured]`

| Sink | TAINTED | SCRIPTLIT | CLEAN | IMMEDIATE |
|---|---:|---:|---:|---:|
| `kStrCmp` | **14120** | 0 | 840 | 0 |
| `kStrAt_read` | **6906** | 0 | 910 | 0 |
| `kStrCpy_dest` | **161** | 0 | 22 | 0 |
| `kStrLen` | **160** | 0 | 14 | 0 |
| `kEditControl_text` | 0 | 0 | 1725 | 0 |
| `kStrCpy_src` | 0 | 183 | 0 | 0 |
| `kFormat_fmt` | 0 | 10 | 0 | 0 |
| `kFormat_dest` | 0 | 0 | 10 | 0 |
| `kParse` | 0 | 0 | 7 | 0 |
| `kDisplay_ptr` | 0 | 6 | 0 | 0 |
| `kSaveGame_desc` | 0 | 0 | 0 | 1 |
| **TOTAL** | | | | **25075 calls** |

**`kStrAt_write` never fired. [measured]** In this run no script *wrote* a byte
into any string, tainted or not. M1's decisive example — a script writing one
byte at a script-chosen offset into game text — was **not observed**.

### The raw VM path is clean, and this is a useful negative

```
VMVAR reads=31750  reads_tainted=0   writes=2836  writes_tainted=0
```
`[measured]` Over 31,750 global/local variable reads and 2,836 writes through
`read_var`/`write_var` — the `lag`/`lal`/`lsg` path S3b established exists in
every SCI game — **not one touched a tainted byte range.** Scripts reach
dialogue bytes through kernel ops, not by reading the words directly.

Consequence: a byte fence can live **inside the kernel ops** and does not need
to cover the raw VM variable path. That is the difference between a bounded
change and an impossible one.

### SCI32 sinks

`kStringGetChar`, `kStringSetChar`, `kArrayGetElement`, `kArraySetElements`,
`kArrayCopy`, `kArrayByteCopy`, `kArrayFill`, `kStringCompare`,
`kStringLength`, `kStringToInteger`, `kStringTo{Upper,Lower}Case` are
instrumented and compiled in, but Cascade Quest is SCI0 so **none of them
executed**. Zero coverage, stated honestly. `[unmeasured]`

---

## 5. What the script is actually doing — the classification that matters

The raw counts say "scripts index dialogue bytes", which would be fatal to a
code-point path. The exemplars say something narrower.

The pattern in the log is a left-to-right walk:

```
STRATWALK maxoff=162 step1=6640 stepN=90   kStrAt_read  script 979, export 0, localCall 127b
```
`[measured]` — 6,640 of 6,730 `kStrAt` offsets on tainted text advanced by
**exactly one** from the previous offset, reaching offset 162 of a 163-byte
string. That is a sequential scan, not random indexing.

And at each offset it compares. The needles `[measured]`:

```
NEEDLE 637  needlelen=4  n=5   needle=[slab]          export 0, localCall 127b
NEEDLE 637  needlelen=4  n=5   needle=[Fred]          export 0
NEEDLE 628  needlelen=5  n=6   needle=[serac]         export 0
NEEDLE 619  needlelen=6  n=7   needle=[beacon]        export 0
NEEDLE 610  needlelen=7  n=8   needle=[gaitors]       export 0
NEEDLE 601  needlelen=8  n=9   needle=[fumarole]      export 0
NEEDLE 601  needlelen=8  n=9   needle=[crampons]      export 0
NEEDLE 592  needlelen=9  n=10  needle=[tree<SP>well]  export 0
NEEDLE 574  needlelen=11 n=12  needle=[bergschrund]   export 0
NEEDLE 565  needlelen=12 n=13  needle=[Mountaineers]  export 0
```

Those ten needles are **exactly, and in full, the ten glossary terms of TEXT
resource 701** — verified by decoding `RESOURCE.001` directly: `text.701`
contains 20 NUL-separated entries forming 10 term/definition pairs, and the
term set matches the runtime needle set exactly. `[measured]`

So, answering the three questions put to this measurement:

- **Against a word or a single character?** Against a **word** — a
  multi-byte glossary keyword, with `kStrCmp`'s length argument `n` set to
  needle length + 1. Single-character needles also occur but are a small
  minority (24 distinct, ≤14 hits each: `.` and `:` — sentence and label
  delimiters).
- **Stop at first hit, or walk the whole string?** It walks the **whole
  string** — `maxoff=162` on a 163-byte string, and the per-string hit counts
  are uniform across all ten needles (565–637), i.e. every term is tried at
  every offset.
- **Which script/export?** All of it: **script 979, export 0 (and export 2),
  local call 0x127b, room 528.** `DISTINCT_TAINTED_ORIGINS 9`, and every one
  is script 979. `[measured]` Script 979 is a high-numbered (global/utility)
  script, consistent with a shared text-services routine rather than room
  logic.

**Classification: this is a substring search over dialogue for glossary
keywords** — the game scanning its own narration to decide which words to
offer a "what does this mean?" definition for. Export 2 does the same against
a different haystack, with needles that are progressive suffixes of
`"...er Input:"`, i.e. the same scan applied to a label string.

This is emphatically **not** word wrap (needles are words, not spaces), and
**not** arbitrary indexing (99% single-byte steps). It is one routine
implementing `strstr` in SCI script because SCI has no `strstr` kernel op.

Why this matters for the verdict: a substring search is **re-encodable**. A
code-point dialogue path can serve it if the fence re-encodes at `kStrAt` and
`kStrCmp` — the script's contract is "give me the byte at N and compare N
bytes", and a fence that answers in the game's byte encoding satisfies it
without the script knowing. That is materially cheaper than "scripts randomly
index dialogue and the representation can never change".

But it is also **not free**, and it is exactly the overlap the disjointness
hypothesis said would be empty.

---

## 6. Static pass: how far does this generalise?

One SCI0 fan game is not the SCI corpus. The only in-tree evidence about real
Sierra scripts is `workarounds.cpp`, where every entry exists because a shipped
script did something the engine had to special-case. Tool:
`harness/i18n/m4static.py`. `[source]`

17 byte-semantic kernel ops examined; 7 have workaround tables, 28 entries
total:

| Op | Entries | Games, and what the script was doing |
|---|---:|---|
| `kStrAt` | 2 | Castle of Dr. Brain `robotJokes::animateOnce`; Island of Dr. Brain `childBreed::changeState` — **both puzzle logic, neither dialogue** |
| `kStrCpy` | 1 | Mixed-Up Mother Goose `talkScript::changeState` — missing dest parameter; the source is then used directly in `kDisplay`, i.e. **dialogue** |
| `kStrLen` | 1 | QFG2 `export 21` — length of a **parser response** at the WIT |
| `kReadNumber` | 3 | Hoyle3 / Casino Nick `dominoes.opt`; SCI Tetris high-score — **numbers, not dialogue** |
| `kDisplay` | 11 | Longbow demo title cards, PQ2, SQ3, SQ4, QFG1, Island of Dr. Brain — **dialogue, but drawn, not byte-addressed** |
| `kArrayFill` | 8 | Phantasmagoria `SaveManager::*`, PQ4 `Str::callKernel` — **save-slot bookkeeping** |
| `kArraySetElements` | 2 | GK1, Phantasmagoria `Str::callKernel` — string-class internals |
| `kStrCat`, `kStrCmp`, `kStrEnd`, `kFormat`, `kStrSplit`, `kMessage`, `kGetFarText`, `kStringGetChar`, `kArrayCopy`, `kArrayByteCopy` | 0 | no shipped script ever needed a fix-up here |

**How to read this, in both directions.** An entry proves a shipped Sierra
script *called* that op with wrong arguments; it does **not** prove the operand
was dialogue. Absence of a table proves only that no shipped script passed that
op arguments the engine had to repair — it is **not** evidence the op is
unused. `kStrCmp` has no table and fired 14,960 times in this one run.
`[source]`

What it does support: the two `kStrAt` entries in the whole SCI corpus are both
Dr. Brain puzzle logic, neither dialogue — which is weak evidence *for* the
disjointness hypothesis in shipped Sierra games, and directly against extending
this measurement's finding to them. Cascade Quest is a **fan game** (2004–2006,
Phil Fortier), and its glossary-scan routine is exactly the kind of thing a
hobbyist adds that Sierra's own scripts did not have.

**Generalisation, precisely:**
- Generalises: the *mechanism* is available to every SCI game — `kStrAt` +
  `kStrCmp` over a `kGetFarText` buffer needs no engine cooperation. `[source]`
- Does **not** generalise: the *frequency and purpose* measured here are one
  routine, in one room, of one fan game. `[measured]` + `[unmeasured]`
- Unmeasured for shipped Sierra titles entirely: no Sierra SCI game was run
  (none on this machine). M1's unmeasured item #1 — "whether any *shipped* SCI
  script uses kStrAt on game text" — **remains unmeasured.** `[unmeasured]`

---

## 7. Verdict

**(ii) with a qualification, not (i) and not (iii).**

The sets **overlap**, so the user's structural argument is refuted as stated —
in this game a script does byte arithmetic on precisely the bytes a translation
replaces. `[measured]` The numbers:

- 6,906 TAINTED `kStrAt` byte reads; 14,120 TAINTED `kStrCmp`; 160 TAINTED
  `kStrLen`; 161 TAINTED `kStrCpy_dest`.
- 0 stale rejects — every one content-verified.
- 1,064 distinct tainted strings touched; 9 distinct calling origins, all
  script 979.
- 185 taint events / 2,033 tainted bytes of coverage, so the run is not empty.

But M1's conclusion is **too strong in one specific way, and the data narrows
it**:

**Ops that MUST keep byte semantics** (measured to operate on translatable
text, at script-chosen byte positions):
1. `kStrAt` — read form. Confirmed, 6,906 hits. The write form was **not**
   observed but must be fenced on the same buffer for symmetry.
2. `kStrCmp` — with an explicit length `n`. Confirmed, 14,120 hits; `n` is a
   byte count chosen by the script.
3. `kStrLen` — confirmed, 160 hits; the scan's loop bound.
4. `kStrCpy` — dest form, confirmed 161 hits (the scan copies substrings out).

**Ops this data frees** (carry translatable text but never expose a
script-chosen byte offset into it):
5. `kDisplay` — 6 hits, all SCRIPTLIT or IMMEDIATE; bytes go to the screen, the
   script never indexes them.
6. `kFormat` — dest always CLEAN, format string always SCRIPTLIT/IMMEDIATE.
7. `kGetFarText` — a source, not a sink; it hands over a whole string.
8. **The raw VM variable path** — 31,750 reads, 0 tainted. M1 did not list this
   as a boundary function; this measurement confirms it need not be one.

So relative to M1's six boundary functions, this data **removes** `kDisplay`
and `kFormat` from the must-fence set, **confirms** `kStrAt`, and **adds**
`kStrCmp`-with-length and `kStrLen`, which M1 treated as less critical than
`cursorPos` and `kMessage(SIZE)` — neither of which fired here `[unmeasured]`.

**Consequence for the design.** A code-point dialogue path is **not** refuted,
but it cannot have its fence only at the parser/edit-control boundary. Because
the measured overlap is a *sequential substring search* rather than arbitrary
indexing (§5), a fence that re-encodes to the game's byte encoding at the four
ops above satisfies the script's contract without the script noticing. The
fence is narrower than "every kernel op" and wider than "the parser boundary
only" — it is those four ops, plus whatever `kStringGetChar`/`kArrayByteCopy`
turn out to do in SCI32, which this run could not touch.

**The measurement that would decide the remaining question** — whether shipped
Sierra games share this shape or whether it is a fan-game idiom — is this same
probe run against a real Sierra SCI0/SCI1 title (KQ4, SQ3, LSL2 …) through a
dialogue-heavy scene. If `kStrAt` TAINTED stays at 0 there, the byte fence
could be narrowed to fan games and the disjointness hypothesis would hold for
the commercial corpus, which is the corpus a translation project actually
targets. That run needs game data not present on this machine. `[unmeasured]`

---

## 8. Artefacts

| What | Where |
|---|---|
| Probe (this commit) | `d819c9acf51`, removed in the follow-up commit |
| Probe source | `engines/sci/engine/taint.{h,cpp}` + instrumentation in 11 files |
| Runtime harness | `harness/i18n/m4taint.sh` |
| Control run (unprobed binary) | `harness/i18n/m4ctl.sh` |
| Crash bisect harness | `harness/i18n/m4gdb.sh` |
| Static workaround pass | `harness/i18n/m4static.py` |
| Run artefacts | `/tmp/m4run/report_final.txt`, 13 PNG frames, `run.log` |
| Report format | `/tmp/sci_taint_report.txt`, written via `Common::DumpFile` |
