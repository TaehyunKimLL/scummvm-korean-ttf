# sci-&lt;lang&gt;.str — translations for the strings a patch cannot reach

Status: **implemented** at `93cfc53ff8` on `i18n`, replacing SCITRS
(`SCITRS_FORMAT.md`). Reader `engines/sci/engine/translation.{h,cpp}`
(class `ScriptStrings`), 10 unit tests in `test/engines/sci/translation.h`.
No writer is committed; see §"Building a table".

`[source]` = read in code. `[measured]` = observed by running something.
`[unmeasured]` = a claim this document has not yet earned.

## Where it fits

A SCI fan translation has two halves, and they take two different routes:

| Text lives in | Example | How it is translated |
|---|---|---|
| a TEXT resource | room descriptions, most parser replies | a `text.NNN` patch file replacing the resource whole, UTF-8 inside. The resource manager has always loaded these; the engine needs no table. Writer: `harness/i18n/m12mkpatch.py`. |
| a script's own string block | inventory names, some replies, the title, "You are carrying nothing!" | **this table** |

The second row cannot be patched. `[source]` A script reaches its strings by
absolute offset (`lofsa`, `vm.cpp:1197`), so a translation longer than the
original would shift every string after it, and every offset the bytecode
holds into them. `[measured]` KQ1: 1,786 strings in TEXT resources, 258 in
scripts, of which 93 reach the screen and appear in no TEXT resource.

## The file

`sci-<lang>.str` in the game directory, where `<lang>` is the ScummVM
language code of the **detected** language (`Common::getLanguageCode()`:
`ko`, `ja`, `th`, ...). The file declares no language; the detection entry
chooses the file. A directory can hold one table per language.

UTF-8, one entry per line, fields separated by a single TAB:

```
script <TAB> id <TAB> text
script <TAB> id <TAB> room <TAB> text
```

- `script` — script resource number, decimal.
- `id` — the string's id within that script: the number
  `Script::identifyOffsets()` gives it at load, first string = 1. This is
  what the dump below prints and what `SegManager::stringKey()` reports at
  run time, so no second numbering exists.
- `room` — optional. The entry then applies only while
  `EngineState::currentRoomNumber()` is that room. An entry without a room
  applies anywhere, and loses to a room-specific one in that room.
- `text` — the translation, to the end of the line. It may contain TABs.
  `\n` is a newline; nothing else is escaped.

Lines that are empty or start with `#` are skipped.

`[source]` Field parsing (`translation.cpp`, `loadFromStream`): the first
two fields end at a TAB. The third is taken as a room **only if it is all
digits and another TAB follows it**; otherwise the text starts there. So a
translation that is itself all digits (`995<TAB>7<TAB>1991`) is text, not a
room — pinned by `test_text_that_is_all_digits_is_still_text`.

A line with fewer than two TABs rejects the **whole table** with a warning
(`sci-ko.str is malformed, ignored`), rather than loading the lines around
it. A later line for the same place overwrites an earlier one.

Example (the first line is KQ1's; the other two show the shape only):

```
# KQ1, Korean
995	4	소지품이 없습니다
996	2	명령을 입력하세요
300	12	5	이 방에서만 쓰이는 번역
```

## How a string is found at run time

`[source]` Translation happens in one place, `SciEngine::strSplitLanguage()`
(`engine/state.cpp`), which every string passes through on its way to the
screen. The caller passes a key; a hit returns the table's text as UTF-8
and skips the `%J`/`%G` language splitter.

The key comes from one of two places:

1. **A pointer into a script's string block.** `SegManager::stringKey()`
   turns the offset back into `(script, id)` via
   `Script::stringIdAtOffset()`. A pointer *inside* a string (a script's
   `str + 5`) maps to the containing string's id. Room is left as "any".
2. **A stack buffer.** Most script strings reach `kDisplay` /
   `kDrawControl` after the script `kStrCpy`'d them into a buffer, and a
   buffer does not say where its contents came from. So `kStrCpy` — the
   plain, full-length form only — records `buffer → (script, id, current
   room, text copied)`. At display, `keyOf(buffer, text)` returns the key
   only if the buffer still holds that exact text; a reused buffer gives no
   key rather than a wrong one. `[measured]` KQ1 inventory and two parser
   replies: 28 display lookups, 0 stale tags.

`kFormat` translates its format string and each `%s` argument by their own
keys *before* formatting, because the formatted result is a new buffer
with no key.

Consequence of (1) vs (2): **a room-specific entry only matches strings
that arrive through a tagged buffer.** A string displayed by direct pointer
is keyed with room "any", so only an any-room entry answers it.
`[unmeasured]` whether this matters for any shipped game.

## Building a table

Set `dump_script_strings=true` in the game's config section and start the
game. At startup the engine loads every script and logs one line per string
(`debug()` with no level, so no `-d` flag is needed; the lines go to the
console/log):

```
SCRSTR	995	4	You are carrying nothing!
...
SCRSTR-TOTAL	<n> strings in <m> scripts
```

Drop the `SCRSTR<TAB>` prefix and the remaining `script<TAB>id<TAB>text` is
already a valid table line; replace the English with the translation and
delete the lines that should stay English. The dump turns `\r` and `\n`
into `\n` and a TAB into a space, so a string containing `\r` does not
round-trip exactly. `[unmeasured]` whether any SCI string displays
differently for `\r` vs `\n`.

Not every dumped string is display text. Object names, selectors and
file names are in string blocks too. Translating an object name is harmless
unless the game compares it, but `workarounds.cpp` and `file.cpp` ask for
the English by name and never go through the table anyway (`DESIGN.md`,
§"Where translation happens").

**Not in any repository:** the 93-entry `sci-ko.str` used to measure
`93cfc53ff8`, the script that built it, and `harness/i18n/p3ab.sh` that ran
the with/without comparison. The format is simple enough to write by hand
from the dump.

## What the table is responsible for

`[measured]` at `93cfc53ff8`, KQ1 with Korean `text.NNN` patches, the same
sequence run with `sci-ko.str` present and moved aside:

```
inventory   with: "소지품이 없습니다"   without: "You are carrying nothing!"
table loads 92 entries; TEXT-resource replies are Korean in both runs
```

The two runs differ in one file, so what changes between them is exactly
what the table owns.

## Why keyed by place, not by English text

SCITRS keyed by the English source text so that a patch built against one
release would survive another. For script strings that turned out to be
the wrong trade:

- The same English line legitimately translates differently in different
  places (`[measured]` LB1: 86 groups, 277 entries). A text key needs a
  tie-breaker; a place key does not.
- A place key is exact and costs a HashMap lookup. The hash, normaliser and
  source-text pool that text keys needed were 210 lines of
  `translation.cpp`.

The cost: a table is tied to the script numbering of the release it was
built from. A release whose scripts differ needs its own dump and table.
The dump makes that a mechanical step, not a translation step.

## Gates

The table is loaded whenever `sci-<lang>.str` exists for the detected
language (`sci.cpp:316`), and is consulted regardless of language. Whether
the translated text is then *decoded* as UTF-8 is decided separately by
`heapStringsAreUtf8()`, which is currently true only for `KO_KOR`. A
`sci-ja.str` would load and be looked up, and its UTF-8 would be walked as
Shift-JIS. See `DESIGN.md` §"Open: the gates name Korean again".
