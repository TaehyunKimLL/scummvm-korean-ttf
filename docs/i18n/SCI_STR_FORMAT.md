# sci-<lang>.str — the script-string side table (format spec)

Status: **format confirmed** (card t_d6070817, 2026-10-05). The reader
`ScriptStrings` (engines/sci/engine/translation.{h,cpp}) and the writer
`harness/i18n/m12mkstr.py` already implement the base format, landed in
`93cfc53ff84` "SCI: Reduce the translation bundle to a (script, id) side
table" on branch `i18n`. This document pins the grammar and key rules
exactly, and lists the parser hardening (section 6) that the base
implementation does not yet do. Supersedes the lookup half of
`SCITRS_FORMAT.md`.

## 1. What the table is for

A fan translation replaces TEXT resources with `text.NNN` patch files; the
engine needs no help for those. A string inside a script's own string block
cannot be patched: the code reaches it by absolute offset (`lofsa`), so a
longer translation shifts every later string and offset. Those strings are
substituted at run time from this table, keyed by where they live.

`[measured]` KQ1 (1991 remake): 93 such strings reach the screen and are in
no TEXT resource. `/tmp/kq1patch/sci-ko.str` built by m12mkstr.py holds 92
entries (one string is identical in Korean and English and the writer skips
it). It covers 8 scripts — 0: 56, 997: 19, 990: 7, 605: 3, 994: 3, 995: 2,
1: 1, 996: 1 — with 0 room-qualified lines, 0 duplicate keys, 0 tabs and
0 `\n` escapes in text, no BOM, no CR.

## 2. File

| | |
|---|---|
| Name | `sci-<lang>.str` in the game directory. `<lang>` is `Common::getLanguageCode(getLanguage())`, e.g. `sci-ko.str`. |
| Encoding | UTF-8, no BOM (a BOM is tolerated, see 6). |
| Line end | LF; CRLF and lone CR also accepted (`SeekableReadStream::readLine(handleCR=true)` maps them to LF). |

**Decision: the name stays `sci-<lang>.str`, not `sci.str`.** The card text
said `sci.str`; the language suffix lets one directory carry several tables
while detection (not the file) picks one, and the file does not have to
declare its language. A table's mere presence (`isPresent()`, even with
zero entries) is also what marks the game's TEXT resources as UTF-8
(`SciEngine::_utf8Manifest`), so the name is part of the contract.

## 3. Grammar

```
file    = { line LF }
line    = blank | comment | entry
blank   = ""                         ; empty after CR stripping
comment = "#" { any }                ; '#' must be the first byte
entry   = num TAB num [ TAB num ] TAB text
num     = digit { digit }            ; decimal, value 0..65534
text    = { any-but-LF }             ; UTF-8, may contain TAB, may be empty
```

Fields, in order: `script` (script resource number), `id` (string id within
the script), optional `room`, `text` (the translation).

`id` is the index `Script::identifyOffsets()` assigns to the script's
strings at load, the same value `SegManager::stringKey()` reports at
display and `--dump_script_strings` prints as `SCRSTR<TAB>script<TAB>id<TAB>text`.
It is not a byte offset, so it survives a different string-block layout as
long as the order of strings in the script is unchanged.

### Disambiguating the optional room

After `script TAB id TAB`, the next field is a room **iff it is one or more
ASCII digits immediately followed by another TAB**. Otherwise the text
starts there and runs to the end of the line, tabs included.

| Line | Parsed as |
|---|---|
| `995␉4␉You are carrying nothing!` | (995, 4, any) → text |
| `14␉2␉5␉some text` | (14, 2, room 5) → text |
| `0␉7␉12` | (0, 7, any) → `"12"` (digits, but no TAB after) |
| `0␉7␉12␉` | (0, 7, room 12) → `""` |
| `0␉7␉a␉b` | (0, 7, any) → `"a␉b"` |

Consequence: a translation that is all digits AND contains a tab cannot be
written without a room. The writer never emits a tab inside text
(m12mkstr.py maps TAB → space), so this cannot happen in a generated file.

### Escapes

Exactly one: the two bytes `\n` in text become a newline (0x0A). Every
other backslash is literal. There is no way to write a literal backslash
followed by `n`; `[measured]` no KQ1 script string contains a backslash, so
no escape for the backslash itself is added (would change existing files'
meaning for no measured need).

## 4. Key and lookup rules

Key = (script, id, room), room ∈ 0..65534 or "any" (stored as 0xFFFF =
`Key::kAnyRoom`). Packed losslessly into a `uint64` (`placeId`), so no two
keys share a slot.

1. **Uniqueness.** At most one entry per (script, id, room). A line with a
   room and a line without one for the same (script, id) are different keys
   and coexist.
2. **When room may be omitted.** Omit it unless the same (script, id) must
   read differently in different rooms. An omitted room means "every room".
   The writer omits it by default; `--room N` stamps every line.
3. **Resolution** for a display in room R:
   (script, id, R) if present, else (script, id, any), else no translation
   (the original bytes are drawn).
4. A room-qualified entry never answers outside its room, and never answers
   a lookup that has no room.
5. `lookup()` returns false — never an empty string — for "no entry"; an
   entry with empty text returns true with `""` (translated to nothing).

## 5. Reader API (as implemented, kept)

```cpp
class ScriptStrings {
public:
    struct Key { uint16 script, id, room; static const uint16 kAnyRoom = 0xFFFF; bool isSet() const; };
    bool load(const Common::String &languageCode);          // opens sci-<lang>.str
    bool loadFromStream(Common::SeekableReadStream &in);    // the parser (section 7)
    bool isLoaded() const;    // >= 1 entry
    bool isPresent() const;   // file found and well-formed, entries or not
    uint entryCount() const;
    void collectTexts(Common::Array<Common::String> &out) const;
    bool lookup(const Key &key, Common::String &out) const;
    // D2/D3 buffer tagging, unchanged:
    void tagBuffer(uint32 buffer, const Key &key, const Common::String &text);
    Key  keyOf(uint32 buffer, const Common::String &text) const;
    static uint32 bufferId(uint16 segment, uint16 offset);
};
```

New, for section 6: the line parser is split out as a pure static function
so each edge case is unit-testable without a stream:

```cpp
enum LineKind { kLineSkip, kLineEntry, kLineError };
/** Parse one line (CR already stripped). On kLineError @p error says why. */
static LineKind parseLine(const Common::String &line, Key &key,
                          Common::String &text, const char *&error);
```

## 6. Edge cases: specified behaviour vs. 93cfc53ff84

| # | Input | Specified | Today | Change? |
|---|---|---|---|---|
| E1 | empty line | skip | skip | — |
| E2 | `#...` | skip | skip | — |
| E3 | ` #...` / whitespace-only | error (not a comment; no silent guess) | no TAB: rejected (too few fields); with TABs: atoi → script 0, a garbage key | **yes** |
| E4 | CRLF / CR | same as LF | same | — |
| E5 | UTF-8 BOM on line 1 | strip it | first key gets script 0 (atoi of `EF BB BF 9..`) | **yes** |
| E6 | fewer than 3 fields | reject table, warn with line no. | same | — |
| E7 | non-digit or empty script/id | reject table | atoi → 0, silently | **yes** |
| E8 | number > 65534 | reject table | truncated to uint16, silently | **yes** |
| E9 | duplicate key | warn `line A duplicates line B`, **later line wins** | later wins, silently | **yes (warning only)** |
| E10 | empty text | entry, translates to "" | same | — |
| E11 | tab inside text | kept literally | same | — |
| E12 | `\n` | newline | same | — |
| E13 | invalid UTF-8 in text | not checked by the parser; writer guarantees UTF-8 | same | — |
| E14 | file has only comments | present, not loaded | same | — |

Rationale for "reject the whole table" (E3, E6–E8): a wrong key does not
fail visibly — it draws a translation in the wrong place, or none where one
was expected. A malformed file is a broken build of the table; rejecting it
whole with a line number is how it gets noticed, and the game falls back to
the shipped text (SCITRS rule 4 kept). Duplicates (E9) are not malformed —
later-wins lets someone append a fix to a generated file — so they warn
only.

## 7. Parser pseudocode (target ~40 lines of C++)

```
loadFromStream(in):
    clear entries; loaded = present = false
    seen = HashMap<uint64, uint>            // placeId -> first line no.
    lineNo = 0
    while not in.eos():
        line = in.readLine(); lineNo++
        if lineNo == 1 and line starts with EF BB BF: drop 3 bytes      # E5
        switch parseLine(line, key, text, error):
            kLineSkip:  continue
            kLineError: warning("ScriptStrings: line %u: %s", lineNo, error)
                        return false                                     # E3 E6 E7 E8
            kLineEntry:
                id = placeId(key.script, key.id, key.room)
                if seen.contains(id):                                    # E9
                    warning("ScriptStrings: line %u duplicates line %u", lineNo, seen[id])
                seen[id] = lineNo
                entries[id] = unescape(text)                             # E12
    present = true; loaded = !entries.empty(); return loaded

parseLine(line, key, text, error):
    if line.empty() or line[0] == '#': return kLineSkip                  # E1 E2
    p = 0
    if !readNum(line, p, key.script) or line[p] != TAB: error="bad script"; return kLineError
    p++
    if !readNum(line, p, key.id) or line[p] != TAB: error="bad id"; return kLineError
    p++
    key.room = kAnyRoom
    q = p; r = 0
    if readNum(line, q, r) and q < len and line[q] == TAB:              # room rule
        key.room = r; p = q + 1
    text = line.substr(p)                                                # E10 E11
    return kLineEntry

readNum(line, &p, &out):  // >= 1 ASCII digits, value <= 65534; advances p
    start = p; v = 0
    while p < len and isDigit(line[p]): v = v*10 + digit; p++; if v > 65534: return false
    out = v; return p > start
```

Note on the room probe: `readNum` failing on a value > 65534 there just
means "not a room", and the digits become text (consistent with the
disambiguation rule — a room must be a valid room).

Error strings are `const char *` literals: no allocation on the error path,
and the unit tests can compare them.

### Tests to add (test/engines/sci/translation.h, 11 today)

- `test_bom_is_stripped` — `"\xEF\xBB\xBF" "995\t4\tx\n"` → Key(995,4) found.
- `test_non_numeric_key_rejects_the_table` — `"99a\t4\tx\n"`, `"\t4\tx\n"`.
- `test_key_over_65534_rejects_the_table` — `"70000\t4\tx\n"`, `"1\t65535\tx\n"`.
- `test_indented_line_rejects_the_table` — `" #c\n"`.
- `test_duplicate_key_later_line_wins` — two `995\t4\t…` lines → second text.
- `test_digits_then_tab_is_a_room_but_digits_alone_are_text` (extends the
  existing all-digits test with `0\t7\t12\t` → room 12, text "").

## 8. Differences from SCITRS

| | SCITRS (m5mktrs.py, pre-93cfc53ff84) | sci-<lang>.str |
|---|---|---|
| Key | FNV-1a 32 of the *normalised English text*, `(resource, index)` only as a hint | exact (script, id[, room]) |
| Ambiguity | two places sharing an English line got one translation | each place is its own key; room splits further |
| Container | binary: header, langEntry[], entries sorted by hash, bucket table, deduplicated string pool | text, one line per entry |
| Languages | N per file, chosen by code in the header | one per file, chosen by file name |
| Covers | TEXT resources + (planned) script strings | script strings only; TEXT goes through `text.NNN` patches (m12mkpatch.py) |
| Reader | ~353 lines (structural checks, normaliser, hash, bucket walk) | 151 lines total incl. D2/D3 tagging |
| Editable | rebuild with the tool | any text editor; diffable in git |
| Malformed | rejected whole | rejected whole (E3, E6–E8) |

## 9. Migration path

1. **Done** (`93cfc53ff84`): reader replaced; SCITRS hash/bucket/pool and
   normaliser deleted; 11 parser/tagging tests; KQ1 `kq1_tour` ko captures
   (look/inventory/ring/unknown) Korean.
2. **Generate**: `harness/i18n/m12scrstr.sh <out> <gamedir>` dumps
   `scrstr.tsv` (SCRSTR lines) for the English game and for a game with the
   translation's script dump; `harness/i18n/m12mkstr.py --en … --tr …
   --out <gamedir>/sci-ko.str` writes the table (skips untranslated and
   unchanged rows, maps TAB → space and newline → `\n`).
3. **TEXT resources**: `harness/i18n/m12mkpatch.py` writes `text.NNN`
   UTF-8 patches; no table entry needed.
4. **Retire SCITRS tooling**: `harness/i18n/m5mktrs.py` (282 lines) and
   `m5fmt.py` stay only as history for SCITRS_FORMAT.md's measurements;
   mark them deprecated in their docstring, do not delete while that
   document cites them. Existing `sci.trs` files are ignored by the engine
   (nothing opens that name since 93cfc53ff84).
5. **Harden the parser** (section 6, E3/E5/E7/E8/E9) with the tests in 7.

## 10. Impact on the decomposed follow-up cards

The auto-decomposition of t_af4042b4 (2026-10-05) was made from its
original card text, which predates `93cfc53ff84`. Measured state:

- t_5d532068 "translation.cpp 712 → <300": already **151** lines (was 353
  before 93cfc53ff84). Remaining real work = section 6 hardening + tests.
- t_29084e3d "write m12mkstr.py": **exists** (75 lines, `harness/i18n/`),
  output matches section 3; produced the 92-entry KQ1 table. Remaining =
  deprecate m5mktrs.py docstring (step 9.4); optionally have m12mkstr.py
  refuse to write a key twice (it cannot today: input is a dict).
