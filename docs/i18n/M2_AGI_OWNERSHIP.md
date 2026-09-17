# M2 — AGI string ownership, and whether AGI's text can become code points

Card M2. Read at `96ce757ba470ab93f58e3047284d28e30a7a4386` (branch `hires-text`),
plus the unmerged AGI Korean chain `wt/k1-agi-rebase` … `wt/k6-agitrs-src` and
`wt/s9-agikeymap-src`. **The engine tree was not modified, built or committed
to** — every claim below is a read, a `git show`, or a run of
`/tmp/i18n/scripts/m2agi.py`, which also only reads.

Every line number in this document is transcribed into `m2agi.py` together with
the text it is quoted as saying. **If a line moves, that script fails rather
than silently measuring a different line** — the `b0dbcs.py` / `a1census.py`
contract. Closing run, against the tree as read: **[measured]**

```
transcriptions: 177 ok, 0 moved
census: 155 sites in AGI's text path, 155 accounted, 0 unaccounted
  by job: ADVANCE 20  WRAP 32  CARET 43  TRUNCATE 20  COUNT 25  FOLD 6  DRAW 9
rc=0
```

Both halves were proven to bite by `/tmp/i18n/scripts/m2bite.sh`, which runs
them against a *copy* of the engine tree **[measured]**:

```
bite 1 (a cited line moved):  rc=1
      127 of 177 lines still read as quoted
    MOVED lines: 50
bite 2 (a new undocumented site):  rc=1
      engines/agi/inv.cpp:260  *** unaccounted for ***
control (untouched tree):  rc=0
M2_BITE_OK
```

| bite | injected | result |
|---|---|---|
| a line moves | one blank line inserted at `text.cpp:100` of a *copy* | `127 of 177 lines still read as quoted`, 50 MOVED, `rc=1` |
| a new undocumented site | one `19 - (strlen(name) / 2)` added to a *copy* of `inv.cpp` | `engines/agi/inv.cpp:260 *** unaccounted for ***`, `rc=1` |

**Verdict up front: YES, with four named byte boundaries (R1–R4 in §Q4).** AGI
owns essentially
all of its text, and the two places it does not own are the two places bytes
must survive. The conversion is smaller than SCUMM's or SCI's would be, and the
40-column grid turns out to be the *cheap* part, not the expensive one — because
AGI never asks a character how wide it is.

---

## Q1. Where every piece of AGI text comes from

Seven sources. For each: who allocates, who owns, and whether the game script
can ever read it back.

### 1.1 LOGIC-embedded messages — engine-allocated, engine-owned, **not** handed back as text

The message section sits inside the LOGIC resource, after the bytecode
**[source]**:

```
logic.cpp:39   uint16 bytecodeSize = READ_LE_UINT16(logic.data);
logic.cpp:47   uint8 messageCount = logic.data[messageSectionPos];
```

If the resource was not LZW-compressed, the string block is **decrypted in
place** with an 11-byte repeating XOR key **[source]**:

```
logic.cpp:56    decrypt(logic.data + stringsPos, stringsSize);
global.cpp:311  void AgiEngine::decrypt(uint8 *mem, int len) {
global.cpp:315      *(mem + i) ^= *(key + (i % 11));
agi.h:93        #define CRYPT_KEY_SIERRA    "Avis Durgan"
```

This matters for the layering: **decryption is byte-oriented and must happen
before any code-point conversion**, because the ciphertext is not text. The XOR
is over the whole string block, not per string.

Ownership: the engine `calloc`s a pointer array and points each entry *into the
resource's own bytes* **[source]**:

```
logic.cpp:66   logic.texts = (const char **)calloc(1 + logic.numTexts, sizeof(char *));
logic.cpp:80   logic.texts[i] = (const char *)(logic.data + stringOffset);
logic.cpp:103  free(logic.data);
logic.cpp:105  free(logic.texts);
```

So `logic.texts[i]` is a **borrowed pointer into `logic.data`**, and its
lifetime is the resource's. There are 15 reads of `texts[...]` in the engine
**[measured]**, and every one is a *display or a copy* — `print`, `display`,
`set.menu`, `set.string`, `set.game.id`, `set.cursor.char`, `get.string`'s
lead-in, `get.num`'s lead-in, `%m`/`%g` in `format.string`, and the debug
console. **No opcode hands a LOGIC message pointer back to the script as
data**; the closest is `set.string`, which *copies* it into the string table
(§1.5).

### 1.2 words.tok parser vocabulary — engine-allocated, engine-owned, never displayed

```
words.h:48    Common::HashMap<byte, Common::Array<WordEntry>> _dictionary;
words.h:34    Common::String word;
words.cpp:112 str[k++] = (c ^ 0x7F) & 0x7F;      // the per-word 0x7F obfuscation
words.cpp:124 newWord.word = Common::String(str, k);
words.cpp:126 _dictionary[str[0]].push_back(newWord);
words.cpp:160 _dictionary[(byte)newWord.word[0]].push_back(newWord);   // .extended
```

Owned by `Words`, `Common::String` by value. **The vocabulary is never drawn.**
It is matched against player input and produces a `uint16 id`; `said()` compares
ids, not text **[source, op_test.cpp:186-188]**. The hash map is *keyed on the
first byte* (`_dictionary[str[0]]`), which is a lookup index, not a display
concern.

The one exception is the matched-word text, which *is* handed back:

```
words.cpp:368  _egoWords[wordCount].word = Common::String(userInputPtr + foundWordPos, foundWordLen);
words.cpp:399  return _egoWords[wordNr].word.c_str();
```

reachable from the script via `word.to.string` (§Q2) and `%w`.

### 1.3 Object names (OBJECT file) — **copied out**, engine-owned

The file is decrypted with the same key, names are read out of a scratch buffer,
and **the buffer is freed** — the names survive as `Common::String` by value
**[source]**:

```
objects.cpp:101  calloc(1, flen + 32)
objects.cpp:40   decrypt(mem, flen);
objects.cpp:65   _objects[i].name = (const char *)mem + offset;   // implicit copy into Common::String
objects.cpp:108  free(mem);
agi.h:310        Common::String name;
objects.cpp:133  return _objects[objectNr].name.c_str();
```

This is the **only** AGI text source that is copied rather than borrowed, and it
is therefore the easiest to convert. Handed back to the script? Only through
`%0` in `format.string` (`text.cpp:1343`), i.e. as *rendered text*, never as a
string the script can index.

### 1.4 Inventory item names — **the same strings, not a second source**

```
inv.cpp:63   inventoryEntry.name = _vm->objectName(objectNr);
```

`InventoryEntry::name` is a `const char *` **[source, inv.h:31]** borrowed from
the object table, plus one engine literal for the empty case
(`getInventoryTextNothing()`, `inv.cpp:100`). There is no inventory string
storage.

### 1.5 The script string table — engine-allocated, **script-owned in effect**, and the one that is handed back

```
agi.h:83    #define MAX_STRINGS                24         // MAX_STRINGS + 1 used for get.num
agi.h:84    #define MAX_STRINGLEN              40
agi.h:411   char strings[MAX_STRINGS + 1][MAX_STRINGLEN]; /**< strings */
agi.cpp:839 const char *AgiGame::getString(int number) {
agi.cpp:857 Common::strlcpy(strings[number], str, MAX_STRINGLEN);
```

A flat `25 x 40` byte array inside `AgiGame`. **This is the only text the script
both writes and reads**, and it is the decisive object for Q4, for two reasons:

1. `setString` is the single write path — `set.string`, `word.to.string` and
   `get.string` all funnel through it — and it **clips at 40 bytes**.
2. It is **serialised raw into the save file** **[source]**:
   ```
   saveload.cpp:219  out->write(_game.getString(i), MAX_STRINGLEN);
   saveload.cpp:571  in->read(_game.strings[i], MAX_STRINGLEN);
   ```
   25 slots × 40 bytes, no length prefix. A change of representation here is a
   change of save format.

### 1.6 Player input — two engine-owned buffers, one of which reaches the script

```
text.h:171  byte  _prompt[42];          // the parser prompt line
text.h:172  byte  _promptPrevious[42];
text.h:201  byte  _inputString[42];     // get.string / get.num / the system UI's edit line
```

Keys arrive as `event.kbd.ascii` and are dropped above 0xFF **[source]**:

```
keyboard.cpp:133  key = event.kbd.ascii;
keyboard.cpp:208  if ((key) && (key <= 0xFF)) {
```

`_prompt` goes to the parser and is *never* returned to the script as text — it
becomes word ids. `_inputString` **is** returned, verbatim:

```
op_cmd.cpp:2050  vm->_game.setString(stringDestNr, (char *)textMgr->_inputString);
```

so the chain is: keystroke → `_inputString[42]` → `strings[n][40]` → script.

### 1.7 Hardcoded engine strings — engine-owned, never script-visible

27 `const char *` members in `SystemUI` **[measured]**, assigned from 114 string
literals across en/ru/he/fr/Amiga/AtariST/Mac variants **[measured]**:

```
systemui.h:129    const char *_textStatusScore;
systemui.cpp:42   _textStatusScore = "Score:%v3 of %v7";
systemui.cpp:59   _textInventoryYouAreCarrying = "You are carrying:";
```

They are pointers to `.rodata`; nothing frees or copies them. They pass through
`stringPrintf()` (the status line does, `text.cpp:662`) and then `displayText()`.
Plus one formatted literal in `cmdVersion` (`op_cmd.cpp:1818`).

### 1.8 Summary table

| source | allocated by | owned by | lifetime | handed back to script? |
|---|---|---|---|---|
| LOGIC messages | `logic.cpp:66` (pointer array); bytes are the resource's | engine, borrowed into resource | until `unloadLogic` | no — only copied by `set.string` |
| words.tok | `Common::String` in `WordEntry` | `Words::_dictionary` | engine lifetime | no (ids only) |
| matched ego words | `words.cpp:368` | `Words::_egoWords` | until next parse | **yes**, via `word.to.string` / `%w` |
| OBJECT names | copy at `objects.cpp:65`, scratch freed at `:108` | `AgiEngine::_objects` | engine lifetime | only rendered, via `%0` |
| inventory names | — (borrowed from OBJECT) | object table | object table's | no |
| string table | static array `agi.h:411` | `AgiGame` | game lifetime, **saved to disk** | **yes** — read and written |
| prompt / input line | static arrays `text.h:171,201` | `TextMgr` | game lifetime | `_inputString` **yes**, `_prompt` no |
| engine literals | `.rodata` | — | program | no |

**The finding: AGI owns all of it.** Nothing is memory-mapped from a script
heap, nothing is written back into a resource, and the only script-visible text
is one 25×40 byte table plus the ego-word array.

---

## Q2. Which opcodes expose BYTE semantics

14 opcode table entries take an `s` (message/string) parameter **[measured]**;
the ones whose *contract* is a count or an index are below.

| opcode | site | is the number a byte count/index? | what changes under code points |
|---|---|---|---|
| `set.string(n, m)` | `opcodes.cpp:294`, `op_cmd.cpp:2136-2140` | **no argument is a length** — but the copy clips at `MAX_STRINGLEN` (`agi.cpp:857`) | nothing to the script; the *clip* becomes a 40-**unit** clip, which holds more Korean. Observable only for text that could not previously exist |
| `format.string` = `stringPrintf` | `text.cpp:1304` | see below | see below |
| — `%v<n>` and `%v<n>\|<w>` | `text.cpp:1318-1339` | **yes, a character width.** `sprintf_s(z,"%015i",…)` then `i = 15 - i` picks a fixed-width slice of the 15-digit string | digits are ASCII, so the slice is identical under any representation. **Safe.** |
| — `%s<n>` | `text.cpp:1355` | no | recursive `stringPrintf` of a string-table slot |
| — `%m<n>` | `text.cpp:1360` | no | recursive on a LOGIC message |
| — `%0<n>` | `text.cpp:1343` | no | object name |
| — `%w<n>` | `text.cpp:1351` | no | ego word |
| — `%g<n>` | `text.cpp:1347` | no | logic-0 message |
| `get.string(d, m, row, col, maxLen)` | `opcodes.cpp:295`, `op_cmd.cpp:1999-2050` | **yes — `parameter[4]` is the whole question.** Clamped to 40 (`op_cmd.cpp:2009`), passed to `stringEdit` (`:2046`), enforced as a *byte index bound* (`text.cpp:1126`), asserted (`text.cpp:1046`), and used directly as a **column** in RTL (`text.cpp:1040`) | Sierra's `maxLen` is **cells** (it also sizes the edit field). Under code points `_inputStringMaxLen` becomes a unit count = a cell count, which is *more* faithful to the original interpreter than the current byte bound. The only re-encoding is at `op_cmd.cpp:2050`, into the byte string table |
| `get.num(m, v)` | `opcodes.cpp:298`, `op_cmd.cpp:2059-2096` | **yes, implicitly**: `stringEdit(3)` — three cells — and `atoi((char *)_inputString)` | `atoi` needs bytes. Trivial: the buffer is digits by construction (`text.cpp:1149` only accepts `'0'..'9'` in GETNUMBER mode). Convert-to-ASCII at the `atoi` |
| `compare.strings(s1, s2)` | `opcodes.cpp:172`, `op_test.cpp:199-284` | **yes, three times**: 40-byte scratch copies (`:234`), `strlen` for the fold loop (`:241`, `:262`), and a **per-byte `tolower`** (`:256`) | the fold is the risk. `tolower` on a trail byte in `'A'..'Z'` corrupts it. Under code points the loop becomes per-unit and `tolower` applies only below 0x80 — a **strict improvement**, and byte-identical for ASCII |
| `right.posn` / `posn` / `center.posn` | `opcodes.cpp:168, 175, 174` | **no.** These are *screen-object* (sprite) coordinate tests (`op_test.cpp:212`, `:295`), not text | unaffected. Named in the card because the AGI names suggest text; they are not |
| `word.to.string(n, w)` | `opcodes.cpp:296`, `op_cmd.cpp:657-661` | no argument is a count; the result inherits the 40-byte clip | the ego word arrives from `words.cpp:368` as bytes cut out of the player's input. Needs the same conversion as `get.string` |
| `set.game.id(m)` | `op_cmd.cpp:1760` | **yes, 8 bytes** | **genuine byte contract.** The id is matched against save-file names, never drawn. Must stay bytes |
| `set.simple(n)` | `op_cmd.cpp:973` | **yes**, `sizeof(automaticSaveDescription)` | a save-file description; byte contract at the filesystem boundary |
| `parse(n)` | `op_cmd.cpp:1127` | no | string table → `stringPrintf` → parser |
| `print(m)` / `print.v` | `opcodes.cpp:281-282`, `op_cmd.cpp:2199` | no | `messageBox` → `stringPrintf` → `stringWordWrap` |
| `print.at(m, row, col, width)` | `opcodes.cpp:331`, `op_cmd.cpp:2222-2230` | **yes — `width` is a COLUMN COUNT.** Becomes `wanted_Text_Width` (`text.cpp:416`) and then `maxWidth` in the wrap (`text.cpp:519, 527`) | this is *already* cells and the engine *already* mis-measures it in bytes. Code points make it correct |
| `display(row, col, m)` | `opcodes.cpp:283`, `op_cmd.cpp:2143` | row/col are **cells** (`text.cpp:240-245`); the wrap is hardcoded to 40 (`text.cpp:252`) | cells throughout; unaffected |
| `set.cursor.char(m)` | `opcodes.cpp:288`, `op_cmd.cpp:2104` | **yes: `*texts[textNr]` — the FIRST BYTE of a message** | a one-code-point read instead; a multi-byte cursor character is currently impossible |
| `set.menu(m)` / `set.menu.item(m,n)` | `opcodes.cpp:336-337`, `op_cmd.cpp:1782, 1795` | no argument, but the menu layer measures with `String::size()` (`menu.cpp:85, 133`) and *truncates by character* against a 40-column bar (`menu.cpp:93-95`) | the whole menu geometry is byte-length-as-column; see Q3 COUNT |
| `status.line.on` | `opcodes.cpp:292`, `op_cmd.cpp:690` | no argument; `statusDraw` right-aligns with `strnlen` (`text.cpp:666`) | byte length used as a column |
| `configure.screen(g,p,s)` | `op_cmd.cpp:1821` | rows only | unaffected |

**The short version of Q2:** exactly **one** opcode argument is a length the
script chose — `get.string`'s `maxLen` — and its original meaning is *cells*,
which the byte implementation gets wrong. Everything else that is a count is
either a fixed-width numeric slice (`%v`, ASCII-safe), a column count the engine
already wants in cells (`print.at`'s width), or a genuine byte boundary
(`set.game.id`, `set.simple`, the save file).

---

## Q3. Every byte==character assumption, by job

155 sites, all accounted for **[measured]**; the full list with per-site notes is
the output of `/tmp/i18n/scripts/m2agi.py`. Counts:

```
ADVANCE 20   WRAP 32   CARET 43   TRUNCATE 20   COUNT 25   FOLD 6   DRAW 9
```

The jobs are chosen so that the cost of each is different. **The grid arithmetic
the card asks about is ADVANCE + WRAP + the COUNT sites**, and it is enumerated
completely below.

### ADVANCE (20) — the caret moves one cell per character

| site | line | note |
|---|---|---|
| `text.h:68` | `#define FONT_ROW_CHARACTERS 25` | the grid's rows |
| `text.h:69` | `#define FONT_COLUMN_CHARACTERS 40` | **the number** — a cell count that byte lengths are compared against everywhere |
| `text.cpp:112` | `CLIP<int16>(row, 0, FONT_ROW_CHARACTERS - 1)` | `charPos_Clip` |
| `text.cpp:113` | `CLIP<int16>(column, 0, FONT_COLUMN_CHARACTERS - 1)` | same, columns |
| `text.cpp:372` | `if (charCurPos.column)` | backspace: is there a cell to the left |
| `text.cpp:373` | `charCurPos.column--` | backspace = exactly one cell |
| `text.cpp:375` | `charCurPos.column = (FONT_COLUMN_CHARACTERS - 1)` | backspace wraps to the previous row's last cell |
| `text.cpp:378` | `clearBlock(row, column, row, column, …)` | erase exactly one cell |
| `text.cpp:384` | `if (charCurPos.row < (FONT_ROW_CHARACTERS - 1))` | CR/LF |
| `text.cpp:386` | `charCurPos.column = _reset_Column` | CR/LF to the margin |
| `text.cpp:393` | `charCurPos.column++` | **the advance.** One column per character, no width asked |
| `text.cpp:394` | `if (charCurPos.column <= (FONT_COLUMN_CHARACTERS - 1))` | auto-wrap at 40 |
| `text.cpp:706` | `clearBlock(row, 0, row, FONT_COLUMN_CHARACTERS - 1, …)` | clear a grid row |
| `text.cpp:950` | `charPos_Set(_promptRow, FONT_COLUMN_CHARACTERS - 1)` | RTL caret at the right edge |
| `menu.cpp:46` | `_setupMenuColumn = FONT_COLUMN_CHARACTERS - 2` | RTL menu bar origin |
| `menu.cpp:103` | `menuEntry->column -= menuEntry->textLen` | RTL column from a byte length |
| `menu.cpp:111` | `_setupMenuColumn += menuEntry->textLen + 1` | next title's column from the previous byte length |
| `menu.cpp:113` | `_setupMenuColumn -= menuEntry->textLen + 1` | RTL half |
| `menu.cpp:149` | `(FONT_COLUMN_CHARACTERS - 1) - menuItemEntry->textLen` | drop-down pushed left by a byte length |
| `menu.cpp:152` | `curMenuEntry->column + curMenuEntry->textLen - menuItemEntry->textLen` | RTL drop-down alignment over byte lengths |

`text.cpp:393` is the load-bearing one and it is **already correct under code
points**: AGI never asks how wide a character is, it advances one column. That
is the B0 `WIDTH=fixed` finding, restated as an advantage.

### WRAP (32) — the box geometry

All 32 are in two places: `stringWordWrap()` (`text.cpp:1182-1288`) and
`drawMessageBox()`'s consumption of its two output numbers.

| site | line | note |
|---|---|---|
| `text.h:72` | `#define HEIGHT_MAX 20` | the wrap's line ceiling |
| `text.cpp:1184` | `int16 boxWidth = 0` | widest line, in cells |
| `text.cpp:1186` | `int16 lineWidth = 0` | current line width, in cells |
| `text.cpp:1188` | `int16 lineWidthLeft = maxWidth` | cells left on this line |
| **`text.cpp:1218`** | `int16 wordLen = curReadPos - wordStartPos` | **the defect in one line**: a BYTE difference used as a CELL count for the rest of the function |
| `text.cpp:1220` | `if (wordLen >= lineWidthLeft)` | break decision: bytes vs cells |
| `text.cpp:1224` | `if (wordLen)` | leading-space skip |
| `text.cpp:1227` | `wordLen--` | …adjusts the count |
| `text.cpp:1231` | `if (wordLen > maxWidth)` | over-long word test |
| **`text.cpp:1233`** | `curReadPos = curReadPos - (wordLen - maxWidth)` | **subtracts a CELL count from a BYTE offset** — the line that cuts a sequence in half |
| `text.cpp:1234` | `wordLen = maxWidth` | truncates a byte length to a cell count |
| `text.cpp:1239-1242`, `1260-1263`, `1276-1277` | `boxWidth`/`lineWidth`/`lineWidthLeft` bookkeeping (11 sites) | cells |
| `text.cpp:1245`, `1266` | `if (boxHeight >= HEIGHT_MAX)` | the 20-line ceiling |
| `text.cpp:1250` | `memcpy(…, wordLen)` | copies `wordLen` **bytes** using the number just compared against a cell budget |
| `text.cpp:1251` | `lineWidth += wordLen` | adds bytes to a cell total |
| `text.cpp:1252` | `lineWidthLeft -= wordLen` | subtracts bytes from a cell budget |
| `text.cpp:1253` | `curWritePos += wordLen` | byte write cursor — correct as bytes |
| `text.cpp:1282` | `*calculatedWidthPtr = boxWidth` | the cell width handed to the caller |
| `text.cpp:543` | `startingRow = ((HEIGHT_MAX - textSize_Height - 1) / 2) + 1` | vertical centring from the line count |
| `text.cpp:551` | `(FONT_COLUMN_CHARACTERS - textSize_Width) / 2` | **horizontal centring**: a byte count here puts a Korean box off-centre and off-screen |
| `text.cpp:559` | `(textSize_Width * FONT_VISUAL_WIDTH) + 10` | box pixel width = cells × 4 |
| `text.cpp:561` | `(textPos.column * FONT_VISUAL_WIDTH) - 5` | box pixel x from the cell column |

The four call sites that hand `maxWidth` in are **all cell counts already**:
`text.cpp:252` (hardcoded 40), `text.cpp:517` (default 30), `text.cpp:527`
(from `print.at`'s `width` argument), `op_cmd.cpp:2034` and `:2075` (40 for
`get.string`/`get.num` lead-ins).

### CARET (43) — an index that is also a column

43 sites across `_prompt`/`_promptPrevious` (`text.h:171-172`, 17 sites in
`text.cpp:779-991`) and `_inputString` (`text.h:201`, 24 sites in
`text.cpp:71-1158`). The invariant is stated by the code rather than by a type:
`_promptCursorPos` and `_inputStringCursorPos` are simultaneously the array
index, the number of characters typed, and the screen column. Representative:

| site | line | note |
|---|---|---|
| `text.cpp:877` | `_prompt[_promptCursorPos] = newKey` | one accepted key = one slot = one cell |
| `text.cpp:844` | `_promptCursorPos--` | backspace is a single decrement |
| `text.cpp:917` | `promptKeyPress(_promptPrevious[_promptCursorPos])` | echo.line replays one slot at a time |
| `text.cpp:1152` | `_inputString[_inputStringCursorPos] = newKey` | the same, in the buffer K2 did **not** widen |
| `text.cpp:1040` | `charPos_Set(row, stringMaxLen + 2 - _inputStringCursorPos)` | RTL: **the opcode's `maxLen` used directly as a column** |
| `text.cpp:1061`, `1092`, `1158` | `for (i = 0; i < _inputStringCursorPos; i++) displayCharacter(0x08)` | RTL redraw backs up one cell per stored unit |

### TRUNCATE (20) — clip to a maximum

| site | line | byte contract? |
|---|---|---|
| `agi.h:84` | `#define MAX_STRINGLEN 40` | **the table's unit** |
| `agi.h:411` | `char strings[MAX_STRINGS + 1][MAX_STRINGLEN]` | flat, and written straight to the save file |
| `agi.cpp:857` | `Common::strlcpy(strings[number], str, MAX_STRINGLEN)` | **the table's only write** — every script string clips here |
| `text.h:74` | `#define TEXT_STRING_MAX_SIZE 40` | serves *both* a cell limit (`get.string`) and a byte budget (the prompt) |
| `op_cmd.cpp:2009-2010` | `if (stringMaxLen > TEXT_STRING_MAX_SIZE) stringMaxLen = …` | the clamp |
| `text.cpp:828` | `maxChars = TEXT_STRING_MAX_SIZE - 4` | prompt budget inside a dialogue |
| `text.cpp:830` | `maxChars = TEXT_STRING_MAX_SIZE - strlen(getString(0))` | **40 minus the BYTE length of the script's prompt prefix** — both halves are meant to be cells |
| `text.cpp:875` | `if (maxChars > _promptCursorPos)` | a byte budget compared against a cell index |
| `text.cpp:1001-1002` | `strncpy((char *)_inputString, text, sizeof(_inputString))` | byte clamp on a 42-byte buffer |
| `text.cpp:1046` | `assert(_inputStringCursorPos <= stringMaxLen)` | the byte index vs the opcode's limit |
| `text.cpp:1126` | `if (_inputStringMaxLen > _inputStringCursorPos)` | `get.string`'s limit as a byte bound |
| `text.cpp:312`, `1381` | `strlcpy(…, 2000)` | **genuine byte contracts** on byte buffers |
| `menu.cpp:93, 95` | `while (textLen && curColumnEnd > 40) text.deleteLastChar()` | cuts a title *by character* until the BAR fits 40 cells — the loop is already character-wise, the measurement is not |
| `op_cmd.cpp:973` | `strncpy(automaticSaveDescription, …)` | **genuine** — filesystem boundary |
| `op_cmd.cpp:1760` | `strlcpy(state->id, …, 8)` | **genuine** — matched against save files, never drawn |
| `systemui.cpp:694` | `strncpy(description, …, SYSTEMUI_SAVEDGAME_DESCRIPTION_LEN)` | **genuine** — save metadata |

### COUNT (25) — measure a string in order to place it

This is the category the K5 census called "three length measurements"; measured
here it is **25 sites**, because the menu layer alone has 16.

| site | line | note |
|---|---|---|
| `text.cpp:666` | `FONT_COLUMN_CHARACTERS - strnlen(statusTextPtr, 40) - 1` | RTL status line right-alignment |
| `text.cpp:905`, `913` | `strlen((char *)_promptPrevious)` | echo.line |
| `text.cpp:946` | `FONT_COLUMN_CHARACTERS - 2 - strnlen(_prompt, 40)` | RTL prompt placement |
| `text.cpp:1014` | `strlen((const char *)_inputString)` | `stringEdit` measures the pre-set text in bytes and then echoes it one byte per cell |
| `menu.cpp:85`, `92`, `107`, `133`, `139`, `140`, `146`, `211`, `213`, `218`, `238`, `245`, `253`, `262` | `text.size()` / `textLen` arithmetic (14 sites) | every menu title and item width, the widest-item calculation that becomes the drop-down's pixel width, and the Atari ST space-padding loop |
| `menu.cpp:692`, `714` | `mouseColumn < (column + textLen)` | **the mouse hit-test**: the clickable width is the byte length |
| `inv.cpp:69` | `column -= strnlen(name, FONT_COLUMN_CHARACTERS)` | right-hand inventory column = 39 − the object name's byte length |
| `inv.cpp:75` | `FONT_COLUMN_CHARACTERS - 1 - strnlen(name, 40)` | RTL mirror |
| `inv.cpp:102` | `column = 19 - (strlen(name) / 2)` | centring by half a byte length |
| `systemui.cpp:600` | `strlen(actualDescription)` | the saved-game slot list |

### FOLD (6) — normalise before comparing

All six in `compare.strings` (`op_test.cpp:234-283`): two 40-byte scratch
buffers, two byte-clipped copies, two `strlen`s, and the per-byte
`tolower`/punctuation-strip loop at `:256` and `:277`. This is the only
case-folding in AGI's text path. (`words.cpp:337` `toLowercase()` and
`words.cpp:454`'s CP866→Latin transliteration fold the *parser* input, which is
not display text.)

### DRAW (9) — one unit becomes pixels

| site | line | note |
|---|---|---|
| `text.cpp:391` | `_gfx->drawCharacter(row, column, character, …)` | one byte → one glyph at one cell. **The single text→pixel boundary** |
| `text.cpp:1030` | `displayCharacter(_inputString[_inputStringCursorPos])` | the get.string echo, byte by byte |
| `graphics.cpp:1230` | `fontData = _font->getFontData() + character * fontBytesPerCharacter` | **the byte==glyph identity**: a byte index into a 256-entry table |
| `graphics.cpp:370-371` | `Common::Rect(width * _displayFontWidth, …)` | a cell rect becomes a pixel rect |
| `menu.cpp:468` | `(maxItemTextLen * FONT_VISUAL_WIDTH) + 8` | the drop-down's **pixel** width is a byte count × 4 |
| `menu.cpp:471` | `(itemEntry->column - 1) * FONT_VISUAL_WIDTH` | its pixel x |
| `systemui.cpp:869`, `875` | `strlen(buttonText) * getDisplayFontWidth()` | Apple IIgs / Amiga button pixel widths |

### What the fixed 40-column grid actually costs

**Less than the SCI_AGI_ASSESSMENT note assumed, and the reason is measurable.**

AGI measures the screen in cells **[source]**:

```
graphics.cpp:350  x *= _displayFontWidth;
graphics.cpp:355  x /= _displayFontWidth;
graphics.cpp:370  Common::Rect displayRect(width * _displayFontWidth, height * _displayFontHeight);
```

and `_displayFontWidth` is **not per character** — it is a screen mode:

```
graphics.cpp:154  if (_font->isFontHires() || forceHires) {
graphics.cpp:159      _displayFontWidth = 16;
```

`putFontPixelOnDisplay()` (`graphics.cpp:474-497`) then **pixel-doubles an 8×8
glyph** in 640x400 and writes a 16×16 one straight through. So the grid stays
40×25 in **both** modes; the cell simply gets bigger, uniformly, for all
characters.

Therefore: **a variable-width character would break AGI, but a uniformly wider
one does not.** The cost of the 40-column grid under a code-point conversion is
not arithmetic — it is that **Latin text on a Korean screen is drawn at 16px
and looks fat**, and that a 40-cell line holds 40 Hangul syllables where the
English original held 40 Latin letters, i.e. roughly **2.5× more meaning per
line** and a translation that must be written to fit. That is a translator
constraint, not an engine defect. **[source, measured against K3's commit
message and the `isFontHires()` gate]**

---

## Q4. The verdict

**Yes. AGI can hold its internal text as code points from resource-load time,
with byte re-encoding at exactly three boundaries.**

The three reasons it is possible, in order of weight:

1. **AGI owns every string** (Q1). There is no script heap holding text, nothing
   writes back into a resource, and the *only* script-readable text is the
   `25 × 40` table plus the ego-word array. Compare SCI, where the edit
   control's text lives in script 996's own local-variable block **[measured,
   BIGBANG_PLAN §3.3]** — AGI has no equivalent.
2. **Nothing asks a character its width** (Q3, ADVANCE). `charCurPos.column++`
   is the whole layout model. B0's `WIDTH=fixed` was recorded as a limitation;
   for this conversion it is the enabling property.
3. **There is exactly one text→pixel boundary** — `text.cpp:391` into
   `graphics.cpp:1230`. Nine DRAW sites total, and seven of them are geometry
   rather than glyphs.

### The internal type

`Common::U32String` **[recommendation, not measured]**, or a private
`uint16` array if the 42-slot fixed buffers are kept as arrays. `uint16` is
sufficient for AGI's target repertoires (BMP covers Hangul syllables, Kana,
CJK Unified, CP866, CP858, Windows-1255) and halves the footprint of the
`25 × 40` table; `U32String` is what `Common::` already provides and what
`promptGetUtf8()`/`promptSetFromUtf8()` on `wt/k2-promptbuf-src` already
convert through. **The card asked for uint16; the honest answer is that either
works and `U32String` costs nothing that matters at these sizes** (25×40 units
= 4 KB at 32 bits).

Note the precedent already on the branch: K2 chose `uint32 _prompt[42]`
**[source, `45516bb90d5`]**, so a `uint16` decision would be a *narrowing* of a
choice already made and should be justified separately rather than assumed.

### Conversion points — decode at load

| # | site | from | to |
|---|---|---|---|
| C1 | `logic.cpp:80` — **after** `decrypt()` at `:56` | resource bytes, game code page | code points, per message, owned by the engine (the pointer array becomes an array of strings) |
| C2 | `objects.cpp:65` — after `decrypt()` at `:40` | scratch bytes | code points; **already a copy**, so this is a one-line change |
| C3 | `words.cpp:124`, `:160` | dictionary bytes | **do not convert.** The vocabulary is matched, never drawn; keeping bytes keeps the hash key (`_dictionary[str[0]]`) and the 0x7F de-obfuscation intact |
| C4 | `systemui.cpp:42-211` (114 literals) | ASCII/Latin-1/CP866/Win-1255/CP858 literals | code points, at construction. These are the only strings whose encoding is *implicit in the source file* |
| C5 | `keyboard.cpp:133`, `:208` | `event.kbd.ascii`, capped at 0xFF | a code point. **The cap at `:208` is what currently makes Korean input impossible**; K2/K1 route around it |
| C6 | `c7636fee10f` `logic.cpp` trs hook | UTF-8 bundle strings | code points at bundle load — see Q5 |

### Re-encoding points — the byte contracts that must survive

| # | site | why it must stay bytes |
|---|---|---|
| R1 | `saveload.cpp:219`, `:571` | **the save format.** 25 × 40 raw bytes, no length prefix. Either re-encode at write/read, or bump the save version. This is the single hardest constraint, and it is a format decision, not a text decision |
| R2 | `op_cmd.cpp:1760` `set.game.id` (8 bytes), `op_cmd.cpp:973` `set.simple`, `systemui.cpp:694` save description | filesystem / save-metadata identifiers. Matched, never drawn |
| R3 | `op_cmd.cpp:2093` `atoi((char *)_inputString)` | `get.num`. Digits only by construction (`text.cpp:1149`); a 4-byte ASCII scratch |
| R4 | `words.cpp` parser entry (`parseUsingDictionary`) | the dictionary stays bytes (C3), so player input is re-encoded to the game code page on the way in. **This is the boundary the K1 semantic parser already sits on** |

### What is *not* blocked, and one thing that changes behaviour

Not blocked: the wrap (all 32 WRAP sites become correct by construction — a unit
count *is* a cell count), the caret (43 CARET sites become correct *by type*
rather than by convention), the menu and inventory layout (25 COUNT sites become
`size()` on a code-point string), the fold (`op_test.cpp:256` becomes per-unit
and `tolower` applies below 0x80 only).

**Changes behaviour, and must be stated:** `MAX_STRINGLEN` becomes 40 *units*
rather than 40 *bytes*. For ASCII this is bit-identical. For anything else the
table holds more text than before — which is a change no shipped game can
observe, because no shipped game can put a multi-byte character there. The
Flag Quest out-of-bounds version probe (`agi.cpp:843-849`) reads
`getString(56)` and compares it to `".917"`; that is ASCII and a fixed literal,
so it is unaffected **[source]**.

**The one real risk, named:** `text.cpp:830`,
`maxChars = TEXT_STRING_MAX_SIZE - strlen(getString(0))`. The prompt budget is
40 minus the script's prompt prefix. Under code points both terms are units and
the arithmetic is *more* correct — but the number reaching this line came from
`strings[0]`, which a script wrote. If R1 keeps `strings[]` as bytes for save
compatibility, this subtraction mixes a unit budget with a byte length again.
**Recommendation: convert `strings[]` to units and re-encode only in
`saveload.cpp`.** Anything else reintroduces the defect at the one place the
script and the screen meet.

---

## Q5. What the K-chain already does, and what the layering does to it

`git branch -a` shows the AGI Korean work as an unmerged chain of worktree
branches, `wt/k1-agi-rebase` → `wt/k6-agitrs-src`, plus `wt/s9-agikeymap-src`
on top **[measured]**. `git log hires-text..wt/s9-agikeymap-src` is **9 engine
commits** (the BIGBANG_PLAN's "11 unmerged commits" counts the two merges)
**[measured]**. `git diff --stat wt/k3-agifont-src wt/k4-e2e-src` is **empty** —
K4 produced verification, not code **[measured]**.

| card | commit | what it is | disposition |
|---|---|---|---|
| **K1** | `48e16d07c58` | semantic parser, Hangul composer, said() scanner (`hangul.cpp`, `semantic.cpp`, `saidscan.cpp`, 1096 lines) | **leave alone.** An input method and a vocabulary resolver. Orthogonal to storage: it consumes key events and produces word ids. The composer already emits code points, so it fits the layering unchanged |
| **K1** | `79fceef661f`, `18872c7b75e` | OOV fallback, room-scoped said() collection | **leave alone.** Parser-side; the dictionary stays bytes (C3) |
| **K2** | `45516bb90d5` | **`_prompt`/`_promptPrevious` widened to `uint32[42]`**, plus `promptLength()`, `promptGetUtf8()`, `promptSetFromUtf8()`, `promptInsertCodePoint()`, `promptMaxChars()` | **SUBSUME.** This *is* the proposal, applied to one buffer. The layering generalises it to `_inputString[42]` (which the commit message explicitly says it left as bytes) and to `strings[]`. Its five helpers become the generic boundary codec rather than prompt-specific methods |
| **K2** | `15f6c4501d8` | Hangul composition at the prompt | **leave alone**, and it gets simpler: it currently composes into a code-point buffer that then converts to UTF-8 for the parser; under the layering the conversion is the R4 boundary and is shared |
| **K3** | `aa3ed024e52` | second glyph source: `GfxFont::getWideGlyph(uint32)`, `hasWideFont()`, `fontHasWideGlyphs()`, the `character > 0xFF` branch in `drawCharacterOnDisplay`, UTF-8 decoding in `displayText()` | **REPLACE the dispatch, KEEP the loader.** "A font that owns its own encoding" means `GfxFont` answers for *any* code point, not that the caller branches on `> 0xFF` (`graphics.cpp` diff at `:1241`). The `HiResBitmapFont` consumption and the 16×16/32-byte cell validation survive verbatim. The `decodeUtf8` gate in `displayText()` **disappears entirely** — there is nothing to decode once the string is already code points, and with it goes the Russian/Hebrew hazard the commit message documents |
| **K5** | `293fb64383b` | `decodeCharacter()`, `measureCells()`, wrap counting cells; 22 unit cases + 57378 corpus cases identical **[measured, K5_WORDWRAP.md §3]** | **REPLACE.** Under code points `measureCells()` is `size()` and `decodeCharacter()` does not exist. All 32 WRAP sites become correct without a decoder. **Its test corpus must be kept** — 9563 messages × 6 widths over 10 games is the strongest English-unchanged evidence on the branch and is exactly the gate the conversion needs |
| **K6** | `b092ce76484` | `agi_trs_hardcode` developer probe: four Korean strings injected into SQ0 logic 5 | **leave alone / delete.** A dev aid that served its purpose |
| **K6** | `c7636fee10f` | `.trs` bundle reader (`trs_bundle.{h,cpp}`, 342 lines), keyed on `(logic, slot)`, UTF-8, hooked at `logic.cpp` after `decodeLogic`'s message table | **SUBSUME — and it becomes conversion point C6.** This is already the "script/resource encoding" layer the proposal asks for: the file declares its encoding in the header, the language comes from the file name, and the loader refuses a malformed bundle. The only change is that it decodes UTF-8 → code points at load instead of storing `const char *`. Its header comment currently justifies UTF-8 by "the text path decodes UTF-8 and the glyph lookup takes a code point" — under the layering that justification becomes "the loader decodes once", which is strictly better |
| **S9** | `a9fe2374373` | Han/Yeong as a keymap action rather than right-Alt; 203-line unit test | **leave alone.** A backend key-event concern, below the text path entirely |

**Nothing in the K chain is invalidated.** Two commits are replaced by something
smaller (K3's dispatch branch, K5's decoder), two are generalised (K2's buffer,
K6's loader), and five are untouched. That is the shape you want from a
layering: it should make the special cases disappear, not make the existing
work wrong.

**One thing the K chain measured that this card should not re-argue:** K5's
census found "10 broken sites" and concluded AGI does *not* need a wholesale
conversion, because "the drawing walk already handles code points, the wrap now
does too, and what remains is one buffer and three length measurements"
**[source, K5_WORDWRAP.md §7]**. Measured here with a wider net, "three length
measurements" is **25 COUNT sites plus 20 TRUNCATE sites plus 43 CARET sites**
**[measured]**. K5's conclusion was correct *for K5's population* (calls of the
four functions that put text on the grid); it undercounts the layout arithmetic
that never calls them — the whole menu layer, the inventory columns, the save
slot list. **The disagreement is about scope, not about facts**, and it is worth
stating in the card that proposes the conversion, because K5 is the document
upstream would be pointed at.

---

## What was NOT measured

1. **Nothing was run.** No build, no capture, no game. Every claim here is
   source reachability plus the transcription check. `[unmeasured]`: that a
   converted AGI renders anything at all.
2. **preagi** (`engines/agi/preagi/`, Mickey/Troll/Winnie) was excluded from the
   population. It has its own text paths and is not part of the AGI text path
   proper. `[unmeasured]`
3. **`loader_v1.cpp` / `loader_gal*.cpp`** — the Apple II, Coco3 and Gold Rush
   Amiga loaders have their own `loadObjects`/`loadWords` entry points
   (`loader_v1.cpp:358, 373`). They funnel into the same `AgiEngine::loadObjects`
   and `Words::loadDictionary_v1`, so C2/C3 cover them, but the *v1 dictionary
   format* (`words.cpp:40-67`) was read and not traced against a real v1 game.
   `[unmeasured]`
4. **The save-format decision (R1)** is stated as a constraint, not solved. Two
   options exist (re-encode at the boundary; bump the version) and choosing
   needs a compatibility policy this card does not own. `[unmeasured]`
5. **`uint16` vs `U32String`.** Argued from footprint and from what
   `Common::` already provides, not measured. K2 already chose `uint32`.
   `[unmeasured]`
6. **RTL.** Hebrew and the `isLanguageRTL()` branches were transcribed and
   classified but not reasoned about as a combination — an RTL *and* wide-font
   game is a case no one has. `[unmeasured]`

---

## The scripts

`/tmp/i18n/scripts/m2agi.py` — run with no arguments to check
`~/work/scummvm/repo/scummvm`, or pass a tree.

```
python3 /tmp/i18n/scripts/m2agi.py [engine-tree]
```

Exit 0 only when all 177 transcriptions still read as quoted **and** all census
hits carry a written JOB disposition. It opens files for reading and writes
nothing.

`/tmp/i18n/scripts/m2bite.sh` — proves `m2agi.py` can fail, by injecting a
moved line and an undocumented site into a **copy** of the engine tree and
requiring `rc=1` from each, plus `rc=0` from the untouched tree.

```
bash /tmp/i18n/scripts/m2bite.sh [engine-tree]
```

Neither script writes to the engine tree. Verified after every run in this
card: `git status --porcelain` in `~/work/scummvm/repo/scummvm` reports only
the two pre-existing untracked entries (`.worktrees/`, `encoding.dat`)
**[measured]**.
