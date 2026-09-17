# M6 — where byte arithmetic actually happens in SCI1

Measured on King's Quest 1 (1991 SCI1 remake, detection-table entry), engine
built from branch `i18n`. Every claim below is marked `[measured]`,
`[source]` or `[unmeasured]`.

This note answers one question that decides the internal-representation work:
**if SCI text becomes code points instead of bytes, what breaks?**

## What was instrumented

`[source]` Probe commit `0acfe9b2358`, removed in the commit that follows it.
It counted every call to the three kernel ops that expose byte
semantics to scripts — `kStrAt`, `kStrCmp`, `kStrLen` — and recorded, per call,
the calling script origin and whether the operand contained a byte >= 0x80.
A byte >= 0x80 is the lead or trail byte of a double-byte Korean character, so
"high byte present" is a direct test of *does this operation touch translated
text*.

The probe was unconditional — no `getenv` gate — and reported from
`~SciEngine`, so it cannot silently fail to run.

## Run

`[measured]` `harness/i18n/m6play.sh`, driving the real game: title → click
into the game proper → ten parser commands typed and submitted (`look`,
`look at castle`, `look at moat`, `inventory`, `get rock`, `open door`,
`talk to guard`, `climb tree`, `swim`, `xyzzy`) → sixteen movement steps
producing scene transitions → the save dialog.

Two builds of the same binary, differing only in the game directory:

- `/tmp/kq1en` — pristine English resources, no translation present
- `/tmp/kq1trs` — same resources plus `sci.trs` (1,786 SCITRS entries) and
  `korean.fnt`; the game renders Korean, confirmed by screenshot

## Result

`[measured]` Identical in both runs:

```
kStrAt=0  (high=0)
kStrCmp=0 (high=0)
kStrLen=20 (high=0)
```

`[measured]` All twenty `kStrLen` calls, with origin:

```
DEdit::setSize   10 calls   high-byte operands: 0
::export 2       10 calls   high-byte operands: 0
```

`[measured]` The operand of every one of those calls was a string the player
had just typed:

```
'l' 'look'   'c' 'climb tree'   'g' 'get rock'   'i' 'inventory'
'o' 'open door'   's' 'swim'   't' 'talk to guard'   'x' 'xyzzy'
```

Each command appears twice: once as its first keystroke (`DEdit::setSize`
measuring the edit control as the character is typed) and once complete
(`::export 2`, the parser receiving the submitted line).

The paired single letters are what prove the commands really executed — the
probe observed the edit control growing keystroke by keystroke. A run where
the input never reached the game would show neither.

## What this means

`[measured]` In SCI1 KQ1, script-visible byte arithmetic and translatable text
are **disjoint**. Byte operations exist, they run on every parser command, and
they operate exclusively on **player input** — never on resource-derived text.
Across a full session of play, zero byte operations touched a translated
string.

`[measured]` This matches what M4 predicted from the SCI0 side but did not
observe directly: M4 found Cascade Quest performing 6,906 `kStrAt` reads and
14,120 `kStrCmp` calls on tainted text, all of them from one script doing a
glossary substring search. KQ1 does none of that. The two games are at
opposite ends of the same axis, and the difference is what each game's scripts
choose to do, not what the engine permits.

`[source]` Consequence for the internal representation: the fence between
code points and bytes belongs at the **parser / edit-control boundary**, not
inside every kernel op. `SciEngine::getSciLanguageCodePage()` and the encode
call in `lookupText()` are that boundary in the current tree — dialogue text
can move to code points while parser input stays bytes, and these measurements
say nothing in KQ1 would notice.

## Limits — stated plainly

`[unmeasured]` **One game is not the corpus.** This is KQ1 SCI1 only. M4
covered one SCI0 fan game. Two games, two engine generations, no Sierra SCI1
title other than KQ1.

`[measured]` **KQ1 does not exercise the dangerous path at all.** A zero count
cannot distinguish "this game never does byte arithmetic on text" from "the
run never reached the code that would". The twenty parser hits prove the probe
works and the instrumented ops do fire, so the zero for `kStrAt` and `kStrCmp`
is a real zero for this session — but a different scene, or a puzzle this run
did not reach, could still differ.

`[measured]` **The save dialog did not test what it was meant to.** ScummVM
substitutes its own GUI, so no game script handled the typed save name. A game
that formats its own save descriptions is untested here.

`[unmeasured]` **Cascade Quest's pattern is the counter-example that matters.**
M4 showed a script scanning dialogue byte by byte for glossary keywords. Any
SCI game doing that needs its text kept in the game's own encoding at that
point. A code-point dialogue path must therefore keep the ability to hand a
script bytes in the game encoding — which the current `lookupText()` boundary
does.

## Verdict

`[measured]` For KQ1 SCI1: the evidence supports the position that byte
arithmetic and translatable text are disjoint, and that a code-point dialogue
path with a fence only at the parser boundary is viable **for this game**.

`[unmeasured]` For SCI generally: undecided, and one specific measurement
would decide it — run this same probe across the Sierra SCI1 titles with
`kStrAt`/`kStrCmp` origins logged, and check whether any non-parser script
origin appears with a high-byte operand. That is a mechanical run of
`m6play.sh` against more game directories; the instrument already exists in
commit history.
