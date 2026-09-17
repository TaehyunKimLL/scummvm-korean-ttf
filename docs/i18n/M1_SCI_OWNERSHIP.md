# M1 — SCI's string-ownership boundary, measured

Where does a byte stop being the engine's business and become the game
script's? This card measures that line, because the user's i18n proposal —
layer 2 (the engine's internal representation) becomes `uint16` code points so
that 1 unit == 1 character — is only possible on the engine's side of it.

Engine read at `96ce757ba470ab93f58e3047284d28e30a7a4386` (branch
`hires-text`). **No engine code was changed, built or committed**: after every
measurement `git status --porcelain engines/` reports **0** lines **[measured]**.
No probe was inserted; the two numbers that would need one are named in
"Unmeasured, and load-bearing" at the end and are not claimed.

Scripts: `/tmp/i18n/scripts/{m1kernel,m1seg,m1owned,m1jobs,m1doccheck}.py`, run
together by `m1all.sh`. Outputs under `/tmp/i18n/out/`. Every file:line in this
document is transcribed inside one of those scripts together with a token that
must still be on that line; a rebase that moves the code makes the script exit 1
instead of letting this document go quietly wrong. The bites that prove this are
in "How to reproduce" at the end.

Claims are one of three kinds and say which:

- **[source]** — a file:line in the engine. Static reachability only.
- **[measured]** — a number this card produced by running something.
- **[unmeasured]** — stated because it is load-bearing and nobody has checked it.

---

## Short answer

| Question | Answer |
|---|---|
| **Q1** How many kernel ops carry game text, and how many expose bytes? | **50 ops. 49 of 50 expose byte semantics. 23 reachable from SCI16 (22 of 23 expose bytes), 49 from SCI32 (48 of 49).** Only `kSaid` is clean, and only because a Said block contains no characters. [measured] |
| **Q2** Which buffers are in script-visible memory? | **5 of 10 segment types can hold a string; 2 of those are addressable by the VM's own load/store opcodes** — `SEG_TYPE_LOCALS` (3, confirms S3b) and `SEG_TYPE_STACK` (4). All 7 `SegManager` string entry points speak BYTES. [measured] |
| **Q3** Which text is engine-owned end to end? | **2 of 6 sources.** Font resources and Said blocks. Message resources, text resources, menu strings and the vocab all leak bytes, a length, or a pointer into script memory. [measured] |
| **Q4** Byte==character sites, by job | **232 sites: ADVANCE 22, WRAP 30, CARET 90, TRUNCATE 31, COUNT 27, FOLD 25, DRAW 7.** [measured] |
| **Q5** Verdict | **(b), and narrower than (b) is usually meant.** Not everywhere — 49 kernel contracts forbid it. The presentation path can hold code points with the conversion at **6 named boundary functions**. See Q5. |

Two findings the card did not anticipate:

**The CARET job is the largest by a factor of three (90 of 232), and it is the
one job that cannot be fixed inside the engine.** `cursorPos` is not an engine
variable — it is read out of the control object's `cursor` selector
(`controls16.cpp:222`) and written back (`controls16.cpp:678`, and separately by
`kgraphics.cpp:948`) **[source]**. A script can read and write that number with
ordinary property opcodes. Changing its unit from bytes to code points changes a
value the game owns.

**SCI32's text measurement is already wrong for double-byte text, before any
conversion.** `GfxText32::getTextDimensions` assembles the double-byte pair at
`text32.cpp:713-714` and then measures it as
`font->getCharWidth((unsigned char)currentChar)` (`text32.cpp:752`) **[source]**
— the cast throws the trail byte away and charges the lead byte's width. The
height at `:753` has the same cast. This is a latent defect, not a consequence of
anything proposed here.

---

## Q1. The kernel string interface: 50 ops, 49 expose bytes

`m1kernel.py` builds the population from the kernel TABLE — the only
authoritative list of what a script can call — not from a grep for `kStr*`. Any
table entry whose implementation touches a string must carry a written
disposition naming which of five byte exposures its CONTRACT has, or the script
reports it unaccounted and exits 1.

```
LEN     the script receives or supplies a byte COUNT
INDEX   the script supplies a byte OFFSET into the string
BUFFER  the script supplies the destination, and its size is the script's
PTR     the script holds a reg_t into a segment it can reach another way
NONE    no byte crosses: engine-owned from the resource to the renderer
```

**[measured]** (`/tmp/i18n/out/m1kernel.txt`):

```
census: 50 kernel entries carry game text, 50 accounted, 0 unaccounted
  reachable from SCI16 : 23
  reachable from SCI32 : 49
  expose byte semantics: 49 of 50
  by kind: BUFFER 14  INDEX 11  LEN 13  NONE 1  PTR 35
  excluded, save/file i/o    : 20
  excluded, not game text    : 18
```

Per generation **[measured]**, from the same output:

| | ops | expose bytes | LEN | INDEX | BUFFER | PTR |
|---|---|---|---|---|---|---|
| SCI16 (SCI0/01/1/1.1) | 23 | **22** | 5 | 3 | 9 | 21 |
| SCI32 (SCI2+) | 49 | **48** | 13 | 11 | 13 | 34 |

The check bites twice, and both were demonstrated:

1. **A moved implementation.** Inserting one blank line into `kstring.cpp`
   makes it report **18** `*** MOVED ***` lines and exit 1
   **[measured]**; the clean tree exits 0.
2. **A new kernel op.** Adding a `kStrReverse` that reads and writes a script
   string, plus its table row, makes it report
   `*** UNACCOUNTED *** kStrReverse (16/32) ... has no disposition` and
   `census: 47 ... 1 unaccounted`, exit 1 **[measured]**.

### The table (the full 50, with per-op notes, is in `m1kernel.txt`)

The ops the card named, plus the three the regex could not find because they
delegate one function deeper (`kEditControl`, `kEditText`, `kInputText` — named
explicitly in the script's `DELEGATES`, or Q2 would have a hole):

| kernel op | sci | file:line | byte semantics | what code points would cost |
|---|---|---|---|---|
| `kStrLen` | 16/32 | `kstring.cpp:443` | **LEN+PTR** | returns `SegManager::strlen()`, a byte count (`seg_manager.cpp:852`). Scripts index and allocate with it. Must keep answering in bytes. |
| `kStrCpy` | 16/32 | `kstring.cpp:79` | **LEN+BUFFER+PTR** | `argv[2]` is a byte count; negative means `memcpy` of `-n` BYTES (`:81`). |
| `kStrCat` | 16/32 | `kstring.cpp:56` | **BUFFER+PTR** | writes back through `strcpy_` into a script-sized buffer. |
| `kStrAt` | 16/32 | `kstring.cpp:104` | **INDEX+PTR** | reads AND writes ONE byte at a script-chosen offset (`:118-151`). **The hardest site in the engine**: a script can assemble or dismantle a double-byte character one byte at a time and nothing can see it. |
| `kStrEnd` | 16/32 | `kstring.cpp:36` | **INDEX+PTR** | returns a pointer advanced by a byte count. |
| `kStrCmp` | 16/32 | `kstring.cpp:66` | **LEN** | `argc>2` gives a byte count to `strncmp`. |
| `kFormat` | 16/32 | `kstring.cpp:437` | **BUFFER+PTR** | `%Ns` padding is computed in BYTES (`:314-315`), so a double-byte argument is padded to half its visual width. Padding by code points changes every formatted line. |
| `kReadNumber` | 16/32 | `kstring.cpp:158` | PTR | ASCII digits only; safe to decode first. |
| `kParse` | 16/32 | `kparse.cpp:90` | PTR | read-only on the text. The one string kernel whose internal representation could change unobserved. |
| `kSaid` | 16/32 | `kparse.cpp:53` | **NONE** | a Said block is compiled bytecode holding vocabulary group numbers, not characters. Nothing to convert. |
| `kMessage` | 16/32 | `kstring.cpp:516` | **LEN+BUFFER+PTR** | subop SIZE returns `record.length+1` (`message.cpp:356`) — the number the script allocates with. Decoding at load changes it. |
| `kGetMessage` | 16/32 | `kstring.cpp:479` | **BUFFER+PTR** | `outputString` refuses when `str.size()+1 > maxSize` (`message.cpp:515`). |
| `kGetFarText` | 16/32 | `kstring.cpp:456` | **BUFFER+PTR** | on SCI1 Mac allocates `text.size()+1` dynmem bytes the SCRIPT frees. |
| `kTextSize` | 16 | `kgraphics.cpp:346` | BUFFER+PTR | string is read-only; results are pixels. Measurement itself could use code points. |
| `kDisplay` | 16/32 | `kgraphics.cpp:1272` | PTR | read-only. Conversion is possible at this boundary. |
| `kDrawControl` | 16/32 | `kgraphics.cpp:1045` | PTR | reads the `text` selector; the QfG workaround also WRITES back (`:1051`). |
| `kEditControl` | 16/32 | `controls16.cpp:238` | **INDEX+BUFFER+PTR** | reads the buffer, edits it, writes it back (`:634`); `cursor` is a byte offset (`:222`,`:678`), `max` a byte limit (`:223`). |
| `kEditText` | 32 | `controls32.cpp:205` | **INDEX+BUFFER+PTR** | `cursorCharPosition` indexes bytes (`:391` setChar, `:393` insertChar, `:407` deleteChar); result written with `SciArray::fromString`. |
| `kInputText` | 32 | `controls32.cpp:215` | **BUFFER+PTR** | same editor; `maxLength` in characters applied to bytes (`:387`). |
| `kStringNew` | 32 | `kstring.cpp:625` | **LEN** | `size` elements; for `kArrayTypeString` the element is `sizeof(char)` (`segment.h:487`). |
| `kStringGetChar` | 32 | `kstring.cpp:630` | **INDEX** | SCI32's `kStrAt`. |
| `kStringLength` | 32 | `kstring.cpp:671` | **LEN** | `.size()`, a byte count. |
| `kStringToUpperCase` | 32 | `kstring.cpp:826` | **BUFFER+PTR** | folds BYTE BY BYTE and writes back — rewrites trail bytes. Same defect `parserLowerCaseWord` was fixed for (`lowercase.cpp:109`). |
| `kStringToLowerCase` | 32 | `kstring.cpp:833` | **BUFFER+PTR** | same, folding down. |
| `kStringTrim` | 32 | `kstring.cpp:819` | **INDEX** | `SciArray::trim` (`segment.h:791-850`) walks raw bytes; `showChar` is one byte. |
| `kStringFormatAt` | 32 | `kstring.cpp:805` | **BUFFER+PTR** | `fromString` resizes to `string.size()+1` BYTES (`segment.h:868`). |
| `kArrayNew` | 32 | `klists.cpp:819` | **LEN** | the `+1` at `:823` is the NUL byte. |
| `kArrayGetElement` | 32 | `klists.cpp:842` | **INDEX** | `getAsID` on a string array returns one byte, **sign-extended** before SCI2.1mid (`segment.h:563-566`) — a lead byte `0xB0..0xC8` comes back NEGATIVE. |
| `kArraySetElements` | 32 | `klists.cpp:847` | **INDEX** | writes reg_t values into byte slots (`segment.h:596`). |
| `kArrayCopy` | 32 | `klists.cpp:881` | **INDEX+LEN** | indices and count in elements = bytes for strings. |
| `kArrayByteCopy` | 32 | `klists.cpp:921` | **INDEX+LEN** | the name is the contract. SCI3 only; unimplemented (`segment.h:785` `error`). |

**On "kSetSize / save-restore of strings", which the card asked for by that
name:** there is no `kSetSize` in SCI. The three things that name could mean
were all resolved **[source]**:

- **`SciArray::resize`** (`segment.h:522`) — reached from `kArrayNew`,
  `fromString`, and from `getAsID`/`setFromID`/`byteAt`/`charAt` under SCI3's
  auto-grow. Element counts, bytes for strings.
- **save/restore of strings** — `SciArray::saveLoadWithSerializer`
  (`savegame.cpp:780`) writes `_size` and then `s.syncBytes(_data, savedSize)`
  for `kArrayTypeByte`/`kArrayTypeString` (`savegame.cpp:804`). A code-point
  array would be a **save format change**. `LocalVariables::saveLoadWithSerializer`
  (`savegame.cpp:466`) syncs the reg_t array — which is where the SCI16 edit
  buffer lives, so SCI16 string state is saved as the reg_t words it occupies.
- **`GfxScreen::bitsSave`/`bitsRestore`** (`screen.cpp:547`, `:601`) — hands the
  game a hunk whose SIZE scripts allocate. Not text; already counted as SSCI by
  A1.

---

## Q2. Script-visible memory: 5 segment types hold strings, 2 are directly addressable

`m1seg.py` reads `enum SegmentType` out of `segment.h` so the population is the
engine's, and requires a disposition per type. It also checks each type's id
against the enum, so a renumbering is caught.

**[measured]** (`/tmp/i18n/out/m1seg.txt`):

```
segment type         id   string?  script sees dereference()
SEG_TYPE_SCRIPT      1    yes      indirect    engines/sci/engine/script.cpp:956
SEG_TYPE_CLONES      2    no       no          engines/sci/engine/segment.h:318
SEG_TYPE_LOCALS      3    yes      YES         engines/sci/engine/segment.cpp:132
SEG_TYPE_STACK       4    yes      YES         engines/sci/engine/segment.cpp:180
SEG_TYPE_LISTS       6    no       no          engines/sci/engine/segment.h:342
SEG_TYPE_NODES       7    no       no          engines/sci/engine/segment.h:329
SEG_TYPE_HUNK        8    no       no          engines/sci/engine/segment.h:355
SEG_TYPE_DYNMEM      9    yes      indirect    engines/sci/engine/segment.cpp:241
SEG_TYPE_ARRAY       11   yes      indirect    engines/sci/engine/segment.cpp:251
SEG_TYPE_BITMAP      13   no       no          engines/sci/engine/segment.h:1191

segments: 10 declared, 5 can hold a string, 2 are directly addressable by VM
          variable opcodes
```

The check bites: inserting one blank line into `segment.cpp` produces **4**
`*** MOVED ***` lines and exit 1 **[measured]**.

### S3b's `segtype=3` verified and extended

S3b measured the parser edit buffer at `segtype=3 ownerscript=996`
**[measured, S3b]**. `SEG_TYPE_LOCALS = 3` is still what `segment.h:64` says
**[measured, this card — the script asserts the id]**, and
`LocalVariables::dereference` (`segment.cpp:132-160`) is what makes a block of
reg_t words look like a byte string: `isRaw = false`, `maxSize` in BYTES
(`= (_locals.size() - offset/2) * 2`), and the odd-offset `skipByte` case
**[source]**.

Extended to the other string kinds:

- **`SEG_TYPE_STACK` (4)** is the same shape (`segment.cpp:180-192`) **[source]**.
  Temps and params address into it (`vm.cpp:567-568`), so a string built in a
  temp array is readable with `lat`/`lap` and writable with `sat`/`sap`.
- **`SEG_TYPE_SCRIPT` (1)** holds string literals compiled into the script;
  `dereference` hands back a **non-const raw pointer** over the whole resource
  buffer (`script.cpp:963-967`) **[source]**, so `kStrCpy`/`kStrAt` will write
  into it. A script reaches such a literal with `lofsa`/`lofss`
  (`vm.cpp:1197-1198`).
- **`SEG_TYPE_DYNMEM` (9)** — `raw = true` (`segment.cpp:241-247`). `kGetFarText`
  allocates here on SCI1 Mac and the SCRIPT frees it.
- **`SEG_TYPE_ARRAY` (11)** — SCI32. `isRaw` is true exactly for Byte and String
  arrays (`segment.cpp:255`) and `maxSize` is `byteSize()` (`segment.h:508`).

### The whole `SegManager` string API speaks bytes — 7 of 7

**[measured]**, each transcription checked:

| function | file:line | unit |
|---|---|---|
| `SegManager::dereference` | `seg_manager.cpp:582` | BYTES (`SegmentRef.maxSize` is a byte count for every segment type) |
| `SegManager::getString` | `seg_manager.cpp:876` | BYTES |
| `SegManager::strlen` | `seg_manager.cpp:852` | BYTES |
| `SegManager::strncpy` | `seg_manager.cpp:694` | BYTES — the raw path does `forwardCopy` of n bytes with **no bounds check** (`:703`) |
| `SegManager::memcpy` | `seg_manager.cpp:773` | BYTES (bounds-checked) |
| `getChar` | `seg_manager.cpp:637` | BYTES — extracts byte `offset` out of reg_t `offset/2`; this is the function that makes a LOCALS block a byte string |
| `setChar` | `seg_manager.cpp:657` | BYTES |

### And how a script reaches those words with no kernel call at all

`read_var` (`vm.cpp:121`), `write_var` (`vm.cpp:166`), reached from
`op_lag/lal/lat/lap` (`vm.cpp:1258`), `op_lsg/lsl/lst/lsp` (`vm.cpp:1274`), and
`op_lofsa/lofss` for static script data (`vm.cpp:1197`) **[source, all
transcriptions checked]**.

**This is the reason S3b's zero is a measurement and not a proof.** S3b counted
1,319 passes with 0 third-party reads mid-edit in Cascade Quest **[measured,
S3b]**. Nothing in the engine *prevents* a different game's script from reading
the same words with `lal`. The mechanism is present in every SCI game; only its
use was measured absent, in one game.

---

## Q3. Engine-owned text: 2 of 6 sources

`m1owned.py`; 28 transcriptions checked. The question per source is whether a
script can obtain the BYTES, the LENGTH, or a POINTER — leak any one and a
decode-at-load-time is observable.

**[measured]** (`/tmp/i18n/out/m1owned.txt`):

| text source | bytes | length | pointer | verdict |
|---|---|---|---|---|
| MESSAGE resources | yes | yes | no | **NOT engine-owned** |
| TEXT resources (`kResourceTypeText`) | yes | yes | no | **SPLIT** |
| FONT resources | no | no | no | **ENGINE-OWNED** |
| MENU strings | yes | yes | **yes** | **NOT engine-owned** |
| SAID blocks | no | no | yes | **ENGINE-OWNED (and not text)** |
| VOCAB resources | no | no | no | **ENGINE-OWNED, but writes back to script memory** |

```
sources: 6 examined, 3 engine-owned end to end, 3 leak bytes, length or a pointer
  decode-at-load is observation-free for : FONT resources, SAID blocks
  engine-owned but mutates script memory : VOCAB resources
```

The check bites: inserting one blank line into `menu.cpp` produces **6**
`*** MOVED ***` lines and exit 1 **[measured]**.

- **Message resources — NOT engine-owned.** Loaded at `message.cpp:84` with
  `record.length = Common::strnlen(...)` (`:85`), then copied INTO a script
  buffer by `outputString` (`:516`) after a byte fit test (`:515`); and
  `kMessage(SIZE)` hands the script `record.length + 1` (`:356`) **[source]**.
  Decoding at load changes both the bytes and that number. Possible only if the
  re-encode happens inside `outputString` and `messageSize` keeps answering in
  bytes. **There is a second hazard:** the substring workarounds cut a message
  at a byte index chosen in `workarounds.cpp` (`message.cpp:274,277`) — a fan
  translation that re-encodes a message invalidates those numbers silently.
- **Text resources — SPLIT.** `lookupText` (`kernel.cpp:889-940`) walks
  NUL-terminated records by byte (`:932`). The `kDisplay` path is engine-owned
  end to end. The `kGetFarText` path is not: it copies into a script buffer
  (`kstring.cpp:458`) and sizes dynmem by `text.size()+1` (`:456`). **Same
  resource, two contracts.**
- **Font resources — ENGINE-OWNED, and already free.** `scifont.cpp:208`
  loads; `:214` reads `_numChars`; `getCharWidth` (`:264`) and `getCharData`
  (`:273`) are indexed by a code the caller assembled. **No script can obtain
  the index or the glyph bytes.** This is the user's layer 3 and it can change
  today with nothing above it able to observe.
- **Menu strings — NOT engine-owned, and the worst case.** `kAddMenu` takes the
  content FROM a script segment (`kmenu.cpp:34`); `kernelAddEntry` rewrites
  bytes IN PLACE inside it (`menu.cpp:148,154,157,163,167` `setChar`), keeps a
  reg_t into the script's own buffer offset by a BYTE count (`:231-232`), and
  `kGetMenu` hands that pointer BACK to the script (`:346`); a script can also
  replace the text through `SCI_MENU_ATTRIBUTE_TEXT` (`:315`) **[source]**.
  Nothing here can be decoded at load because nothing here is loaded — it is
  script data.
- **Said blocks — engine-owned and not text.** `kparse.cpp:53` gets a raw
  pointer to a block of vocabulary GROUP NUMBERS; `said()` (`said.cpp:1006`)
  matches on them; `menu.cpp:491` does the same for menu accelerators. Nothing
  to decode.
- **Vocab — engine-owned, but it writes into the script's buffer.** The word
  list is never handed out. But `Vocabulary::checkAltInput`
  (`vocabulary.cpp:409`) takes the edit buffer and the byte cursor **by
  reference** and rewrites both (`:438-449`), while the player types; and
  `parserLowerCaseWord` (`lowercase.cpp:96`) folds through a 256-entry byte
  table (`:100,114`). So decoding the vocab requires decoding the INPUT, which
  comes from a script segment.

---

## Q4. 232 byte==character sites, split by job

A grand total decides nothing here; the seven jobs have completely different
costs. `m1jobs.py` classifies every site and requires a written disposition
naming the job and the cost. A site whose disposition claims a different job
than the pattern that matched is reported too.

**[measured]** (`/tmp/i18n/out/m1jobs.txt`):

```
census: 232 byte==character sites in the SCI text path, 232 accounted, 0 unaccounted
  by job: ADVANCE 22  WRAP 30  CARET 90  TRUNCATE 31  COUNT 27  FOLD 25  DRAW 7
```

Per file **[measured]**:

```
file                                        ADVA  WRAP  CARE  TRUN  COUN  FOLD  DRAW
graphics/text16.cpp                            7    19     0     0     0     0     3
graphics/text32.cpp                            5    10     0     0     0     0     4
graphics/controls16.cpp                        6     0    40     2     3     0     0
graphics/controls32.cpp                        4     1    17     1     1     0     0
graphics/menu.cpp                              0     0    16     5     0     6     0
engine/kstring.cpp                             0     0     0     0     5     6     0
engine/kgraphics.cpp                           0     0    10     4     1     0     0
engine/klists.cpp                              0     0     0     1     0     1     0
engine/seg_manager.cpp                         0     0     0     6     1     0     0
engine/segment.h                               0     0     0     2     2     0     0
engine/message.cpp                             0     0     0     2    14     0     0
parser/vocabulary.cpp                          0     0     7     8     0     8     0
parser/lowercase.cpp                           0     0     0     0     0     4     0
```

The check bites: adding to `text16.cpp` a function that walks a string
accumulating `getCharWidth((byte)*t)` makes it report
`ADVANCE engines/sci/graphics/text16.cpp:<the injected line> *** unaccounted for ***` and exit
1 **[measured]**; the clean tree exits 0.

**One row per site, with the disposition, is in `m1jobs.txt`** (847 lines). What
the split says:

### ADVANCE — 22 sites, and most are already code-point-shaped

`text16.cpp:268`, `:420`, `:541`, `:754`; `text32.cpp:309`, `:318`
**[source]** all call `getCharWidth(curChar)` where `curChar` is **already a
packed double-byte value**. What is byte-shaped is the *walk that produced it*,
not the call. The four `controls16.cpp` loops (`:146, :182, :194, :525, :549`)
already go through `GfxFont::decodeChar()` — S4/S9's work — and are the model.

Two exceptions worth naming: `controls16.cpp:528`
`getCharWidth(eventKey)` is genuinely byte-shaped (a single byte from the
event), and `text32.cpp:752-753`'s `(unsigned char)` cast is the pre-existing
SCI32 defect above.

### WRAP — 30 sites, and the count LEAVES the function

`GetLongest` returns a BYTE count that `Box()` then hands to `Width()` and
`Draw()` as a length (`text16.cpp:623,626,674,676`) **[source]** — so the unit
is a contract between three functions, not an internal. SCI32 is worse:
`getLongest` advances the CALLER's index (`text32.cpp:606,625,636,660,663`)
and `getTextCount` returns a byte count (`:877`) that `ScrollWindow` **stores**
in `_startsOfLines` (`controls32.cpp:833-834`) **[source]**.

### CARET — 90 sites, and this is the job that blocks (a)

`cursorPos` is a **script selector**, read at `controls16.cpp:222` and
`kgraphics.cpp:976`, written back at `controls16.cpp:678`, `:380`, `:560` and
`kgraphics.cpp:948` **[source]**. `kgraphics.cpp:945-948` even *clamps* the
script's cursor against a byte length and writes the clamped value back — the
engine changing a number the game owns, in bytes.

SCI32 is the same shape and has no character-aware step at all: left arrow is
`--editor.cursorCharPosition` (`controls32.cpp:329`), right arrow `++`
(`:336`), delete is `deleteChar(cursorCharPosition)` (`:407`), and the caret's
pixel position is `getTextWidth(editor.text, 0, editor.cursorCharPosition)`
(`controls32.cpp:435`) over a BYTE prefix — **the SCI32 twin of the S7/S9 defect, still
present** **[source]**.

`menu.cpp` contributes 16 CARET sites because the whole menu parser is byte
offsets into the script's string, and `:231-232` turns one of those offsets into
the pointer handed back to the script.

### TRUNCATE — 31 sites

The dangerous ones cut inside a character: `controls16.cpp:151` truncates a
list entry at `maxChars` BYTES; `kgraphics.cpp:993` and `:1009` step list
entries by a fixed BYTE stride taken from the `x` selector; `menu.cpp:245`
deletes one trailing byte. The six `seg_manager.cpp` `setChar` sites are the
write side of every non-raw string store.

### COUNT — 27 sites, 14 of them in `message.cpp`

Length used as a limit or an allocation size. `message.cpp` dominates because
every record carries `record.length` from the resource through `processString`
to `messageSize`, which is the number a script allocates with.

### FOLD — 25 sites

`kStringToUpperCase`/`ToLowerCase` (`kstring.cpp:825,832`) fold every byte
including trail bytes. `lowercase.cpp`'s 256-entry tables (`:30,:53`) already
carry this fork's lead-byte skip (`:109`) — precisely the kind of special case
the user's proposal is meant to delete.

### DRAW — 7 sites

The smallest job and already on the right side: `_font->draw(curChar, ...)`
(`text16.cpp:549,755`), `drawToBuffer` (`text32.cpp:308`). They take a packed
value the font indexes with. `drawTextRTL` casts to one byte
(`text32.cpp:518`) — Hebrew only, so the RTL path cannot draw double-byte text
**[source]**.

---

## Q5. Verdict: (b), with the boundary at six functions

**(a) everywhere — NO.** 49 of 50 kernel ops expose byte semantics
**[measured]**. 14 hand the script a buffer whose size the script chose, 11 take
a byte index, 13 return or take a byte count. The three that make (a) impossible
rather than merely expensive:

1. **`kStrAt`** (`kstring.cpp:104-153`) — a script reads and writes an
   individual byte at an offset it chose. There is no representation in which
   this works and a character is two units.
2. **`cursorPos` as a selector** (`controls16.cpp:222,678`;
   `kgraphics.cpp:976,948`) — the caret unit is a value the game stores. 90 of
   232 sites depend on it.
3. **`kMessage(SIZE)`** (`message.cpp:356`) — the script allocates from a byte
   count the engine reports. Change the count and the script allocates wrong.

**(c) not at all — NO, and the reason is the job split.** DRAW (7) and ADVANCE
(22) already take packed values; the fonts already own their encoding (Q3) and
`decodeChar()` already exists (`scifont.h`, S4). Nothing in the rendering path
requires bytes.

**(b) presentation path only — YES, and this is the answer.** The conversion is
possible for measure/wrap/draw, and *partially* for caret and input
composition: the engine may compose in code points internally, but must convert
back before touching `cursorPos` or the script's buffer.

### The boundary functions, named

Conversion happens at exactly these six. Everything above them may be
`uint16` code points; everything below stays bytes.

| # | boundary | file:line | direction | why here |
|---|---|---|---|---|
| 1 | `SegManager::getString` | `seg_manager.cpp:876` | bytes → code points | the single funnel every kernel entry that READS game text starts at. One decode here covers `kDisplay`, `kTextSize`, `kParse`, `kDrawControl`, `kAddMenu`, every SCI32 text op. |
| 2 | `SegManager::strncpy` / `strcpy_` | `seg_manager.cpp:694`, `:765` | code points → bytes | the single funnel every kernel entry that WRITES game text ends at. `kStrCpy`, `kStrCat`, `kFormat`, `kStrSplit`, `kGetFarText`, `kEditControl`'s write-back (`controls16.cpp:634`) all land here. |
| 3 | `SegManager::strlen` | `seg_manager.cpp:852` | must keep answering BYTES | `kStrLen` returns it verbatim; scripts index with it. Do **not** convert. Named as a boundary because it is the one that must NOT move. |
| 4 | `GfxControls16::kernelTexteditChange` | `controls16.cpp:221-680` | both, per call | reads the script's buffer at `:238`, writes it at `:634`, and reads/writes the `cursor` selector at `:222`/`:678`. The composer may hold code points **inside this function only**; the four values crossing its edges are bytes. |
| 5 | `GfxControls32::kernelEditText` / `kernelInputText` | `controls32.cpp:58`, `:211` | both | SCI32's twin: reads at `:61`/`:215`, writes back through `SciArray::fromString` at `:205`/`:308`. Same rule. |
| 6 | `MessageState::outputString` + `messageSize` | `message.cpp:506`, `:350` | code points → bytes, and a byte COUNT | decoded messages must re-encode here, and `messageSize` must keep reporting the encoded byte length or scripts allocate wrong. |

Two further constraints that are not boundaries but bound the design:

- **`SciArray` save format.** `savegame.cpp:804` syncs string arrays as raw
  bytes. A code-point `SciArray` is a save-game format change. Keep `SciArray`
  bytes **[source]**.
- **`Vocabulary::checkAltInput`** (`vocabulary.cpp:409`) reaches into the edit
  buffer and the byte cursor by reference. It is on the wrong side of boundary
  4 today and must either move inside it or be given code points.

### What (b) buys, in the measured numbers

| job | sites | under (b) |
|---|---|---|
| DRAW | 7 | already correct; unchanged |
| ADVANCE | 22 | already take packed values; the walks feeding them collapse to an index |
| WRAP | 30 | **fully convertible** — internal to `GetLongest`/`getLongest`, except the counts crossing to `Box`/`Width`/`Draw` and to `ScrollWindow::_startsOfLines`, which convert at the same call |
| FOLD | 25 | **fully convertible** — the 256-entry tables become functions and `lowercase.cpp:109`'s lead-byte skip disappears |
| CARET | 90 | **partially** — internal composition in code points, bytes at the selector. 3 sites (`controls16.cpp:222,678`, `kgraphics.cpp:948`) are the fence |
| TRUNCATE | 31 | **partially** — the cuts become character-safe; `maxChars`/`x`-selector strides stay bytes |
| COUNT | 27 | **not convertible** — every one is a length a script allocates or limits with |

So of 232 sites, **84 (DRAW+WRAP+FOLD+ADVANCE) convert cleanly**, **121
(CARET+TRUNCATE) convert internally with a byte fence**, and **27 (COUNT) cannot
convert at all** **[measured, from the per-job split]**.

---

## Found while counting, belongs on other cards

1. **SCI32 measures double-byte text wrong today.**
   `text32.cpp:752-753` casts an assembled pair to `(unsigned char)` before
   `getCharWidth`/`getCharHeight`. **[source]**, **[unmeasured]** — no SCI32
   game has been run here.
2. **The SCI32 caret has the S7/S9 defect and no character-aware step.**
   `controls32.cpp:329,336,407,435`. **[source]**, **[unmeasured]**.
3. **`kArrayGetElement` sign-extends** before SCI2.1mid (`segment.h:563-566`),
   so a lead byte `0xB0..0xC8` reaches the script NEGATIVE. **[source]**.
4. **Message substring workarounds are byte offsets into resource text**
   (`message.cpp:274,277`). A fan translation that re-encodes a message breaks
   them silently. **[source]**.
5. **`SegManager::strncpy`'s raw path has no bounds check** (`:703`) where
   `memcpy` right below it does (`:779`) — already noted in this fork's
   `controls16.cpp:619` comment. Engine robustness card. **[source]**.

---

## How to reproduce, and how each check bites

```
cd /tmp/i18n/scripts && ./m1all.sh          # all five, exit 0 on a clean tree
M1ENG=/path/to/scummvm ./m1all.sh           # against another checkout
```

**[measured]** on `96ce757ba47`:

```
m1kernel OK   m1seg OK   m1owned OK   m1jobs OK   m1doccheck OK   ALL_EXIT=0
```

A script that would still print a plausible answer after the source moved is
worthless, so each was made to fail on purpose against a throwaway copy of the
tree (the engine itself was never touched):

| script | injected | result |
|---|---|---|
| `m1kernel.py` | one blank line into `kstring.cpp` | **18** `*** MOVED ***`, exit 1 |
| `m1kernel.py` | a new `kStrReverse` kernel op + its table row | `*** UNACCOUNTED *** kStrReverse`, exit 1 |
| `m1seg.py` | one blank line into `segment.cpp` | **4** `*** MOVED ***`, exit 1 |
| `m1owned.py` | one blank line into `menu.cpp` | **6** `*** MOVED ***`, exit 1 |
| `m1jobs.py` | a function walking a string with `getCharWidth((byte)*t)` | `ADVANCE ... *** unaccounted for ***`, exit 1 |
| `m1doccheck.py` | a citation in a copy of this doc edited to a line past EOF | `past EOF (848 lines)`, exit 1 |
| `m1doccheck.py` | one blank line into `controls16.cpp` | **2** `*** MOVED ***` on the two `SELECTOR(cursor)` anchors, exit 1 |

`m1doccheck.py` checks this document rather than a script: it resolves all
**110** `file:line` citations across **23** files, and for **21** load-bearing
ones additionally requires (a) that the citation still appears in the document
at all, (b) that the cited line still contains a named token, and (c) that the
enclosing function is still the one the claim names. A citation edited out of
the prose fails as `*** GONE ***`, so a claim cannot be quietly removed from the
check's reach.

## Unmeasured, and load-bearing

1. **Whether any shipped SCI script actually uses `kStrAt` on game text.** The
   contract permits it and `kStrAt` has its own workaround table
   (`kStrAt_workarounds`), which suggests games do call it — but no game was
   run. This is the single number that would most change (a)'s verdict, and it
   needs a probe on `kStrAt` this card did not insert.
2. **Whether any script reads a string out of `SEG_TYPE_LOCALS` or
   `SEG_TYPE_STACK` with `lal`/`lat` outside the one game S3b measured.** The
   mechanism is present in every SCI game; only its absence in Cascade Quest is
   measured. A `LOCALREAD`-style probe across more games would close it.
3. **That the 84 cleanly-convertible sites really are clean.** Argued from the
   per-site dispositions, not demonstrated by a build — the rule of this card
   was read-only.
4. **Everything about SCI32 is static.** 49 of 50 kernel entries and 90 of the
   232 sites include SCI32 code this project has never executed.
