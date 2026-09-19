# M11 — moving the string boundary from the renderer to the kernel ops

`[source]` = read in code. `[measured]` = observed by running something.
`[unmeasured]` = a claim this document has not yet earned.

## What this reverses, and why

M8 concluded (`M8_CODEPOINT_PLAN.md`, "What M6 measured, and what it
licenses"):

> the *display* path may become code points, but the *script-visible* path
> must keep byte semantics, because at least one real game walks dialogue
> bytes. So the conversion boundary must sit between "what scripts
> manipulate" and "what the renderer draws" — not at the kernel op layer.

That conclusion was correct for what it was deciding: whether the renderer
could go to code points without touching the VM. It could, and it did
(stages 1-4, `readChar()`, `GfxFontSet`). What it left behind is the cost of
putting the boundary there:

`[measured]` The boundary is `lookupText()` encoding UTF-8 into the game's
code page (`kernel.cpp:955`). Any character the code page cannot represent
is dropped there, silently: a Thai character with a glyph in the font never
reaches the renderer — not a box, not a substitute, nothing. So the engine
is "Unicode for whatever cp949 can already say", which is not Unicode.

`[measured]` Trying to skip the encode — hand UTF-8 straight through — blanked
every button on KQ1's title screen. `readChar()` decoded the UTF-8 correctly
(`ed 94 84 → U+D504`, all four syllables right), but `GetLongest` advances by
`curCharBytes == 2` and returns a **byte count** that `Width()` and `Draw()`
consume as `while (len--)`. A 3-byte syllable was walked as 1 byte + 2 stray
continuation bytes. The `curCharBytes == 2` checks are four, and two of them
are not advances but "is this a multi-byte character" predicates for Kanji
line-splitting — this is not a one-line generalisation.

So the M8 boundary has a ceiling (the code page) and the next step down
(UTF-8 through the renderer) hits the byte-count contract. The user's
direction is to move the boundary further in: **make the string ops
themselves speak characters.**

## The direction, stated exactly

Not "change the heap to `uint32`". The heap layout is not ours:

`[source]` A SCI string lives in one of two shapes (`segment.h:38`,
`seg_manager.cpp:637`):

```
raw       byte[]     static strings inside a script resource — the same
                     buffer as the bytecode, addressed by the bytecode
reg_t[]   16-bit     dynamic strings — two bytes per cell, unpacked by
                     getChar()/setChar() on odd/even offset
```

Script bytecode computes heap addresses assuming this layout. Savegames
serialise it. A `uint32` cell would move every address a script has
compiled in. That door is closed.

What is open: **the meaning of "i" in the string ops.** `kStrLen(s)` today
returns bytes-to-NUL. `kStrAt(s, i)` returns the i-th byte. If the heap
holds UTF-8 — which is NUL-safe, so `strlen`, `strcpy`, `strcat` need no
change at all — then the ops that *index* can index by code point:

```
op        today                     proposed
kStrLen   bytes to NUL              code points to NUL
kStrAt    i-th byte (read/write)    i-th code point, as uint32
kStrCmp   bytewise                  bytewise — UTF-8 preserves code point order
kStrCpy   bytewise                  bytewise — unchanged
kFormat   %s copies bytes           %s copies bytes; %-Ns pads by code point
```

The heap stays bytes. `getChar`/`setChar` stay. Savegames stay. The decoder
is the one `readChar()` already uses, so the seam count stays at one.

## The wall this has to clear: SCI0

`[measured]` M4, on a SCI0 game: 6,906 `kStrAt` reads and 14,120 `kStrCmp`
calls on tainted text, from one script doing a glossary substring search.
`[measured]` M6, on KQ1 (SCI1): `kStrAt = 0`, `kStrCmp = 0`.

A SCI0 script that calls `kStrAt(s, 3)` expecting the fourth byte, and gets
the fourth code point, is broken. So the semantic change cannot be global.

Gate it on the translation being loaded. An untranslated game keeps byte
semantics to the last op — and that is the property upstream will ask to
see proven, not asserted: **every existing game must behave identically.**

## Measurements that decide the plan — none taken yet

These are the things that, if they come out the wrong way, change or kill
the plan. Each names what it would take to refute the approach.

### M11-1 `[unmeasured]` Does any script do arithmetic on what kStrAt/kStrLen return?

If a script computes `kStrLen(s) * 8` for a pixel width, or uses
`kStrAt`'s value as a table index, then code-point semantics silently
change layout or lookups. M4/M6 counted the *calls*; they did not follow
the *values*.

Method: taint the return value of `kStrAt` and `kStrLen` in the VM and
report where it flows — into `kStrCpy`/`kFormat` (fine), into arithmetic
opcodes (`add`, `mul`, `lsl`, index into `lofsa` tables — NOT fine).
Run LB1 through the copy-protection and into Act I; run KQ1 through
`m11save.sh`. Report per-op sink counts.

Refutes the plan if: arithmetic sinks > 0 on translated text in a game we
ship.

### M11-2 `[unmeasured]` Does UTF-8's extra length overflow a script buffer?

`[measured]` KQ1's bundle is 141,194 B in UTF-8 vs 99,665 B in cp949
(+42 %); LB1's 368,990 vs 263,753 (+40 %). Longest single string: 647 B
UTF-8 vs 456 B cp949. `kFormat`'s working buffer is 4096 B
(`kstring.cpp:232`), so that is fine.

What is not known: the size of the **script-side** buffer `kStrCpy` and
`kFormat` write into. A script that declared `[buf 40]` for a 39-byte
cp949 line receives 55 bytes of UTF-8 and overwrites whatever follows.

Method: in `kStrCpy` and `kFormat`'s final `strcpy_`, log
`(dest maxSize, bytes written)` when the source came from a translation.
Any `written >= maxSize` is an overflow. Same two play sessions.

Refutes the plan if: any overflow. Then either the bundle needs a length
budget per string, or those ops need a code-point-aware truncate.

### M11-3 `[unmeasured]` Is `%-Ns` width in kFormat bytes or characters?

`[source]` `kstring.cpp:319` computes `extralen = strLength - slen` where
`slen = tempsource.size()` — bytes. A right-aligned score table with
Korean labels already pads wrong under cp949 (2 bytes, 1 cell); under
UTF-8 it is worse (3 bytes, 1 cell).

Method: grep the two bundles for `%-` and `%<digit>` in **source** strings
(the format string is the game's, not the translation's). Count how many
formats carry a width, and whether the substituted argument is ever a
translated string.

Refutes nothing on its own; decides whether `kFormat` needs a code-point
pad. If zero width-formats hit translated arguments, it is out of scope.

### M11-4 `[unmeasured]` What does the renderer need once the heap is UTF-8?

`GetLongest` returns bytes and `Draw(from, len)` consumes bytes. That
contract can stay — bytes are a fine unit for "where does this line
start" — if the *walk* inside each function advances by `curCharBytes`
instead of 1-or-2, and the two "is this multi-byte" predicates become
`curCharBytes > 1`. Then `from`/`len` stay bytes and nothing outside
`text16.cpp` changes.

Method: after M11-1..3 clear, make that change and re-run the M8 wrap
baseline (`harness/i18n/baselines/m8_wrap_ko.tsv`, 170 lines). The
baseline is in bytes; a correct UTF-8 walk produces the **same glyph
sequence** with **different byte counts** (n=12 instead of n=8 for a
four-syllable label). Compare glyph sequences, not n.

Refutes the change if: glyph sequence differs anywhere.

## What is NOT in scope

- Changing the heap cell size. Closed above.
- `kSaid` / the parser. It matches word ids from the vocabulary, never
  string bytes; translated input is a separate problem (`scummvm-llm-text-parser`).
- SCI32 (`text32.cpp`). It has its own text path; verify it still builds
  both ways, do not port it in this pass.

## Sequence

1. M11-1, M11-2, M11-3 — probes, two sessions each, numbers into this file.
2. Decide. If M11-1 has arithmetic sinks or M11-2 has overflows, the plan
   changes before any product code moves.
3. Gate: `SciEngine::stringsAreUnicode()` = translation loaded. Single
   predicate, like `usesHiresDoubleByteText()`.
4. `kStrLen`, `kStrAt` code-point semantics behind the gate. Unit tests
   for both, on hand-built UTF-8, with the gate on and off.
5. `lookupText()` stops encoding when the gate is on.
6. M11-4: `text16.cpp` walk by `curCharBytes`. Glyph-sequence gate.
7. Prove the invariant: every untranslated game's glyph sequence and
   `kStr*` return values are identical before and after. That is the
   evidence for upstream.

Step 6 is the risky one — it is where the earlier experiment blanked the
screen. Steps 3-5 are additive behind a gate and cannot reach an
untranslated game.
