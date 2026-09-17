# What a correct i18n design must make impossible

The old work is discarded as code. This file is what survives it: **twelve
defects that were each found the hard way, restated as conditions a design
must satisfy.** They are the only thing the abandoned branch produced that a
rewrite cannot re-derive cheaply — every one cost between a day and a week,
and several were found only after a wrong diagnosis had been committed and
reverted.

The rule this file sets:

> A proposed design is **rejected** until it answers, for every row of §1, why
> that defect cannot occur in it. "We would be careful there" is not an
> answer. The answer must be structural: the code that would contain the
> defect does not exist, or cannot be written, or fails a test that ships.

The reason for the rule is the observation that motivated the rewrite: the
defects did not arrive as a list. They arrived one at a time, each looking
like the last remaining special case. Six of the twelve were discovered
*after* the previous one had been declared fixed, in the same subsystem.

Sources: kanban board `scummvm`, cards S2–S10 and K1–K6; docs
`SCI_TEXT_ARCHITECTURE.md` (A1), `SCI_FONT_ENCODING.md` (S3b),
`I18N_ASSESSMENT.md` (I1), `BIGBANG_PLAN.md` (B0). Engine line numbers refer
to branch `hires-text`, which is retained for archaeology.

---

## 1. The twelve, and what actually caused each

`REPR` = a defect that a code-point internal representation removes outright.
`OWN` = a defect about *who owns a line's rendering state*, which no change of
representation touches. The split is the single most important thing in this
file, and it is measured, not guessed: A1's census of the SCI16 text path
found 178 direct-manipulation sites, of which **56 are AMBIENT** — the text
path reading and writing the port's pen position, font and colour.

| # | card | the defect, as observed | root cause | class |
|---|---|---|---|---|
| 1 | S3 | 25 of 2350 Hangul syllables became *different* syllables before parser lookup | `tokenizeString()` lower-cased the trail byte of a double-byte pair — FOLD applied per byte | REPR |
| 2 | K5 | a 14-syllable line wrapped a 40-column box to 3 lines and cut a character in half | `stringWordWrap()` counted bytes — WRAP applied per byte | REPR |
| 3 | S9 | the text cursor would not advance past a Hangul syllable | cursor advance measured per byte, and the font charged 0 for every EUC-KR byte — CARET applied per byte | REPR |
| 4 | K2 | the prompt showed 10 cells for a 4-syllable buffer | `displayText()` walked UTF-8 byte-wise — DRAW applied per byte | REPR |
| 5 | S3b | the parser prompt could not hold a Korean syllable | the buffer was sized in bytes against a maxChars the script supplied | REPR (at a script boundary — see §3) |
| 6 | S4 | Hangul typed into the edit control did not appear | the control's own screen update erased the glyphs it had just drawn; a gate was added to suppress it | OWN |
| 7 | S6 | with #6's gate, *English* stopped appearing | the gate suppressed the update for the whole control, but only double-byte glyphs are driver-rendered; single-byte text still needed the push | OWN |
| 8 | S7 | Hangul drawn correctly, then four columns of the first syllable eaten | `texteditCursorDraw()` measured with the control's font while `Box()` drew the line with font 1001 — **two answers to "which font is this line?"** | OWN |
| 9 | S9(b) | same root cause as #8, rediscovered independently while #8 was in flight; the commit was dropped as a duplicate | same | OWN |
| 10 | S8 | the Han/Yeong key worked on Linux and not on Windows | SDL has no `SDLK_` name for `SDL_SCANCODE_LANG1`, so the key arrived as `KEYCODE_INVALID`; right-Alt only matched because X11 maps that physical key to `Alt_R` | neither — input plumbing |
| 11 | S5 | a mode indicator placed in the edit control was invisible exactly when needed | the control is entered ~1550 times per session but redraws only when the text changed — zero times on a bare toggle | OWN |
| 12 | B4/misc | a replacement glyph that exists but is **blank** erased the game's own picture | the contract is "return false and the caller draws the original"; an empty glyph claims the character was handled | OWN (font/caller contract) |

**Five REPR, six OWN, one neither.**

This is the correction to the premise. The stated diagnosis — "byte == char in
an engine where characters are two bytes" — explains rows 1–5 completely and
rows 6–12 not at all. Rows 6, 7, 8, 9 are one defect found four times: *a line
has no single owner of its font and its update.* Rows 11 and 12 are the same
shape at a different scale.

A rewrite that fixes only REPR will produce a clean, correct, code-point text
path — and then rediscover rows 6–9 in it, because nothing in a change of
representation says which font draws a line.

---

## 2. Invariants

Each is derived from the rows above and must be checkable. "Checkable" means a
test in the tree or a probe that a harness runs, not a review comment.

### I1. One character is one unit, everywhere above the resource boundary

Kills rows 1–4. Nothing above the decode boundary may index text by byte, take
a byte length, or test a byte for being a lead byte.

- **Check:** a grep-class census, in the style of `harness/b0dbcs.py`, that
  enumerates the text path and requires a written disposition per site, exiting
  non-zero on an unaccounted one. The old one found 178 sites in SCI and 51 in
  AGI with 0 unaccounted; the new one must reach **0 sites needing a
  disposition at all** above the boundary.
- **Corollary:** the unit is **uint32**, not uint16. UTF-16 breaks I1 on its own
  terms at the first supplementary character, which reintroduces exactly the
  "if it is two units, do this" shape the rewrite exists to delete.
  `Common::U32String` already exists and 329 files use it.

### I2. A line's rendering state is one value, produced once

Kills rows 6–9, 11. Whatever answers "which font, which pen, which colour,
who pushes it to the screen" must be a single object computed once per line
and passed to every consumer — measure, draw, cursor, update.

- **Check:** no consumer may re-derive any of those values. Structurally: the
  measuring function and the drawing function take the *same* parameter, and
  there is no accessor that recomputes it. A test that draws a mixed
  ASCII+Hangul line and asserts measure and draw agree on the font id for
  every column.
- This is A1's step 5, which A1 deferred and B0 excluded. The measurement in §1
  says it is not deferrable: it is the majority of the defects, and the only
  one the old work never structurally fixed — S7 added `FontIdForLine()`, which
  is the right answer applied at one call site.

### I3. The font owns its encoding and reports what it does not have

Kills row 12. A font is asked for a code point and answers with a glyph, an
advance, and a truthful "I do not have this." A caller never inspects bytes to
decide which font to use, and never receives a blank glyph in place of "no".

- **Check:** `hasGlyph(cp)` and a rendering path where "has glyph but zero ink"
  is either impossible or explicitly distinguished from "no glyph".

### I4. Width is a question, never an assumption

The user's own stated caveat. Once a character is a code point, its width is
per character. Every cell-count, column arithmetic and fixed-8 in the layout
path either asks the font or declares itself a fixed-cell context.

- **Check:** an enumeration of fixed-width assumptions classified as (a) needs a
  real width, (b) may stay a cell count because the font declares a fixed cell,
  (c) is a game-visible contract that must not change. Class (c) is the
  dangerous one: AGI's 40×25 grid and SCI's script-supplied `maxChars` are
  contracts with the *game*, not with us.

### I5. The byte boundary is named, narrow, and exact

Where the game's own scripts observe bytes, conversion happens — at named
functions, not scattered. Row 5 lives here.

- **Known hard point, measured:** the SCI parser edit buffer is **script 996's
  own locals block** (`segtype=3` = `SEG_TYPE_LOCALS`), so a script can read
  its bytes with `lag`/`lal` without any kernel call. S3b instrumented 1319
  passes through the control and measured **0 third-party reads mid-edit** —
  both outside accesses were at the final pass (`kStrLen`, then `kParse`). So
  the boundary is real but it is *narrow*, and that measurement is what makes
  a code-point internal buffer viable there.
- **Known easy point, measured:** `Common::String::encodeWindows949()`
  round-trips all 2350 KS X 1001 syllables with **0 errors**. The reverse table
  does not need building.

### I6. The unchanged case is proven, not argued

Every past fix that held was one where "English is unchanged" was a
measurement. The ones that wasted time were the ones where it was an argument.

- **Check:** two binaries differing only in the change, driven through the same
  frames, pixel-identical. Precedents that worked: S3 (4/4 frames identical),
  S9 (53/53), K5 (57378 wrap cases through both loops, 0 differ).

---

## 3. What is carried forward, and what is not

**Not carried: all of it, as code.** `hires-text` stays as a branch. Nothing
is cherry-picked into the new tree by default; a piece may be re-derived if a
measurement asks for it.

**Carried: the measurements.** These were expensive and remain true of
*upstream* code, so they apply unchanged to a tree cut from master:

| measurement | value | where |
|---|---|---|
| SCI16 text path, direct-manipulation sites | 178, of which 56 AMBIENT | A1 |
| SCI `DrawString(str, fontId, penColor)` | **dead code**, 0 callers | A1 |
| `left & 0xFFC` in the Korean font draw | lossy; moves 75% of glyph positions; no original interpreter behind it | A1 |
| SCI edit buffer location | script 996 locals, `segtype=3` | S3b |
| third-party reads of the edit buffer mid-edit | 0 of 1319 passes | S3b |
| codepoint → EUC-KR converter | exists, exact, 2350/2350 | S3b |
| AGI text call sites | 51 classified, 10 broken, all one defect (`_inputString` is a byte buffer + 3 sites using `strlen` for width) | K5 |
| per-engine DBCS jobs (LEAD/PAIR/WIDTH/DRAW/WRAP) | SCI is the only engine where the **caller** assembles the pair | B0 |
| identical copies of the lead-byte predicate | 5 byte-identical, +2 lead-only | I1 |
| lead-byte bounds disagreement | `0xB0..0xC8` vs `0xB0..0xD0` between copies | I1 |
| upstream churn on the files this touches | 21 commits/12mo, against 12549 tree-wide | B0 |

**Carried: §1 and §2 of this file.** They are the acceptance criteria.

---

## 4. The one thing this file cannot answer yet

Whether the conversion is (a) wholesale, (b) presentation-path only with a
byte boundary at the script interface, or (c) impossible — per engine. That is
being measured. If the answer for SCI is (b), the rewrite's scope shrinks
substantially, because the interface's shape is then dictated by the game's
scripts rather than by our legacy, and starting from a clean tree buys less
than it appears to.

AGI's answer is likely (a) and K5 already contains the evidence: the ten
broken sites are one defect and the census concluded that a byte→U32String
conversion of the engine's string storage is what they all want.
