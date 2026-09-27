# `hires_text.map`: a translator's and font-pack author's guide

This is the file a translation or a hi-res font pack ships to control how
ScummVM draws replacement (TrueType or SVFN) text over a game's own bitmap
fonts. The same file and the same parser serve every engine that has the
path (C11, `I18N_TEXT_DESIGN.md`); what each engine reads is in its own
section below:

- **SCI16** (below SCI2): when the game's text is a UTF-8 translation
  (`sci-<lang>.str` present, or the KQ1-ko detection entry) or a legacy CJK
  code page (949/932/936/950) - the same scope as the `hires_text_font` ini
  key. On any other SCI game the map is ignored, with one warning.
- **SCUMM** v1-v6 with the hi-res text layer on.
- **AGS**, when the game directory has `hires_text.map` or the ini names
  one (`hires_text_map=`).
- **Grim** does not read the map: a translation names one face per game
  font in `<font>.laf.txt` (see "Localising a game with a UTF-8 text file"
  below).

Anyone localising a game should start at "Localising a game with a UTF-8
text file" and "One map, three languages"; the rest of the page is the
reference.

For the surrounding architecture (the text compositor, the TextLayer, why
this exists at all) see `HIRES_COMPOSITOR_DESIGN.md`. This page is only
about the map file: its syntax, precedence, the modes it can select, and
the warnings a bad map produces.

## Where it lives

- `hires_text.map` in the game's own directory, or
- the file named by the ini key `hires_text_map` (game domain).

An empty `hires_text_map=` names nothing (one warning, no map is used,
the game directory's own `hires_text.map` is *not* tried instead). A
missing file, a directory, or text that does not parse as INI each give
one warning and the map is ignored entirely - the game still starts and
draws with whatever the ini keys and built-in defaults say.

It is plain INI syntax (`common/formats/ini-file.h`): `[section]` headers,
`key=value` lines, `;` comments on their own line. **Inline comments are
also supported now, on every key the parser reads:** a `;` preceded by a
space or a tab ends the value there (the rest is dropped, and what is left
is trimmed again), so `color=0 ; DOS` parses as `0`. A `;` with anything
else before it stays part of the value - `single=my;font.fnt` keeps its
`;`. The one edge case outside "a value with a whitespace-`;` parses as
before": `key=;x` also reads as empty, even though nothing in that raw
line has whitespace before the `;` - the semicolon sits at the very start
of the value, and that alone ends it, the same as `key= ; note` does once
the leading space is trimmed away. `#` is never an inline comment marker,
and this rule is the map's own - `scummvm.ini` (read by `ConfigManager`)
has no inline comments at all. Comments still read best on their own line,
above the key they describe, and every own-line example on this page
keeps doing exactly that.

**Relative paths in the map are the map's own.** A `[fonts]` entry, or a
path written in place of a face name (`face=`, `latin_font=`, ...), that
is not absolute is taken against the directory holding the map file. For
the game directory's own `hires_text.map` that is the game directory; for
a map named by `hires_text_map=` elsewhere, fonts can sit beside that map.
The ini keys `hires_text_font` and `hires_text_latin_font` are not map
paths: they are used exactly as given, as they always were.

## Localising a game with a UTF-8 text file

Since C11 (`I18N_TEXT_DESIGN.md`) the engines below take a translation as
**UTF-8 text in a file named by the language code**, and draw it in any
script the fonts cover - Korean, Japanese, Thai - with the same engine code
and the same map. Only the text file changes between languages. The
language is the one the player picks (`language=` in the game's ini domain
or `--language=`); its code is ScummVM's (`ko`, `ja`, `th`, `vi`, ...).
Korean fan patches in their old formats (CP949 `korean.trs`, EUC-KR
`korean.tra`, CP949 `grim.ko.tab`, the SCI `.uni` bundle) keep working as
before; they are legacy formats, not the model for a new translation.

| Engine | Text file(s) | What marks it UTF-8 | Fonts |
|---|---|---|---|
| **SCI16** | the game's TEXT resources as `text.NNN` patch files with UTF-8 strings (`harness/i18n/m12mkpatch.py`), plus `sci-<lang>.str` for strings compiled into scripts (`SCRIPT_STRINGS.md`) | **`sci-<lang>.str` present for the chosen language** - the manifest; it may hold only comments when no script string needs translating. KQ1-ko is also recognised by its detection entry | `hires_text.map` in the game directory: `[hires] face=` (a chain), per font id `[font.N]`; then an optional `.uni` bundle; then the game's font |
| **SCUMM** v1-v6 (PC renderers) | `<lang>.trs` (`ja.trs`, `th.trs`, `ko.trs`; Korean also finds the legacy `korean.trs`) - the `SCVMTRS` bundle with UTF-8 strings (`harness/i18n/c11/mktrs.py` writes one on an existing bundle's index) | **`EF BB BF` at the start of the string body** (after the room table; the file itself starts with `SCVMTRS `), or ini `text_encoding=utf8`. An unmarked body that looks like UTF-8 logs one hint | `hires_text.map`: `[hires] face=` chain, `[font.N]` per charset, `[font.N] bitmap=` SVFN; after the chain, the game's charset (which draws non-ASCII characters as `?`) |
| **AGS** | `<name>.tra` compiled from the AGS editor's `.trs` (`harness/i18n/c11/mktra.py` writes one without the editor), selected by `[language] translation=` in `acsetup.cfg` or `--language=` | the `.tra`'s own `ext_sopts` option **`encoding=utf-8`** (upstream AGS). Without it, a file named `korean` is read as EUC-KR (legacy) | `hires_text.map` (see "AGS (C11 T8)"): `[font.N] face=` chains or `[font.N] bitmap=` SVFN per AGS font; otherwise the game's own fonts |
| **Grim** (retail, not remastered) | `grim.<lang>.tab` beside `GRIM.TAB`, same keys (`harness/i18n/c11/mkgrimtab.py`); the data dir needs `gfupd101.exe` | **`EF BB BF` as the file's first bytes** (text starts at byte 3). Without it, `grim.ko.tab` is the legacy CP949 table | one `<font>.laf.txt` per game font, one line `"<face file> <N>px"` (e.g. `ComicSans18.laf.txt`: `hiragino-w3.ttc 17px`); no chain, no map |

What to expect, and what to check:

- **Detection.** SCI and SCUMM detect the original game as before. Grim
  with a forced language whose `grim.<lang>.tab` exists is accepted by a
  fork-only fallback detection; without the file the game is not
  identified at all. AGS needs nothing.
- **Fonts: one map for every language.** Name the faces once as a chain,
  `face=ko, ja, th`; each character is drawn by the first face that has it
  ("One map, three languages" below). Pick a face inside a TTC with
  `path.ttc#N` (C21). For Thai
  choose a face whose marks have zero advance and a negative bearing
  (Sukhumvit Set; **not** Thonburi, which needs shaping).
- **Coverage warnings.** With a UTF-8 translation, SCI, SCUMM and AGS
  sample 64 of the translation's own characters and check every face of
  the chain: one warning per face, e.g.
  `hires text: <face> lacks 54 of 54 sampled characters of the translation
  (U+0E01 U+0E02 ...); they fall back to the game's font`, and
  `hires text: <face> draws combining marks as spacing glyphs (it needs
  shaping); choose a face with zero-width marks, e.g. Sukhumvit Set`. A
  warning that names the last face means those characters will not show.
  Grim does not check coverage and has no fallback face: a character
  its face lacks is drawn as that face draws a missing glyph.
- **What counts as "the face has it" (C24).** A face has a code point only
  if it draws ink for it, or - for a space (`U+0020`, `U+00A0`, `U+3000`,
  or any other Unicode space separator the face gives a non-zero advance)
  - if it advances for it. A face that outlines only some of a translation's
  syllables (for example a Korean font limited to the 2350 KS X 1001
  syllables) is fine as the first face of a chain: every syllable it draws
  nothing for falls to the next face, exactly as a missing glyph does. A
  bitmap-only face that FreeType reports as non-scalable (an embedded strike,
  not an outline) opens only at its one built-in pixel size; at any other
  size it is skipped with a warning, and the chain (or the game's font)
  draws instead. The coverage check itself never counts a space or a
  zero-width/format character (soft hyphen, ZWSP, ZWJ, variation
  selectors, Hangul fillers, ...) as missing, so the warning text only ever
  names letters, marks and other visible characters - even though such a
  character still falls through the chain if no face in it actually draws
  it.
- **Line breaking** is the shared rule set: at spaces, before and after
  kana/kanji (kinsoku: no line starts with `。` `」` and similar, none ends
  with `「`), between Thai syllables (no dictionary; a word may be split),
  never inside a character with its marks. `[layout]` in the map changes
  the defaults (`hangul=word|any`, `kinsoku=on|off`, `thai=on|off`). Grim
  has no map and so always uses the defaults.
- **Size.** Thai stacks marks above and below the base, taller than a
  Latin or Hangul line. When the face is fitted to the game's line cell
  (SCI, SCUMM, and AGS without `size=`), it is opened smaller so the marks
  fit (about 0.75x); a map `size=` sets the size explicitly.
- **Not supported:** right-to-left scripts, scripts that need shaping
  (Arabic, Indic), dictionary line breaking (Thai words may split),
  typing translated text into the game's parser.

## One map, three languages

One `hires_text.map`, shipped once, serves a Korean, a Japanese and a Thai
translation of the same game. Swapping the translation file is the only
change; the map is not edited. This is the map the C11 captures used
(`harness/i18n/c11/maps/universal.map`; macOS system paths, for testing -
ship your own faces beside the map and name them relative to it):

```ini
[hires]
; a chain: each character is drawn by the first face that has it
face=ko, ja, th

[fonts]
ko=/System/Library/Fonts/AppleSDGothicNeo.ttc
ja=/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc
; face 2 ("Text") of SukhumvitSet.ttc; face 0 is "Thin"
th=/System/Library/Fonts/Supplemental/SukhumvitSet.ttc#2
```

With a Japanese translation, kana and kanji that AppleSDGothicNeo has are
drawn by it, and the rest fall through to Hiragino (the coverage check
logs how many: "AppleSDGothicNeo.ttc lacks 6 of 63 ... they fall back to
ヒラギノ角ゴシック W3.ttc"). Put `ja` first to have Japanese drawn by the
Japanese face. With the Thai translation both CJK faces lack every Thai
character and Sukhumvit draws them. The same file works on:

- **SCI** (KQ1): as is.
- **SCUMM** (MI1 UTE): add `scale=2` to `[hires]` (without a scale the
  text is drawn at 8 px). Since C17 a map whose fonts carry coverage (a face
  or an 8 bpp bitmap) blends without `alpha=true`; write `alpha=false` for
  hard edges. v7 games cannot blend and stay keyed. A game whose
  charsets differ in height should give sizes per charset with
  `[font.N] size=`.
- **AGS** (5 Days a Stranger): add `[font.0]`, `[font.1]`, `[font.2]`
  sections with the same `face=ko, ja, th`, or rely on `[hires] face=`,
  which AGS also applies to fonts without a section.

Per-engine captures of this map with the three translations are in
`I18N_TEXT_DESIGN.md` §9.

### Face chains, `[font.N] bitmap=` and `[layout]` (every engine)

- **`face=` is a face or a comma-separated chain**, in `[hires]` and in
  `[font.N]` (`font=` is the same key). Each entry is a `[fonts]` name or
  a path (relative paths are the map's own).
- **The bare-name rule.** A value **without a comma** is one face, taken
  as a `[fonts]` name or else as a path, as before chains existed - so
  `face=Osaka` alone opens a file called `Osaka` in the map's directory.
  **Inside a chain** an entry that is not a `[fonts]` name counts as a
  path only if it contains `/`, `\` or `.`; a bare extension-less name
  there (`face=ko, Osaka`) is dropped with one warning ("[hires] face
  'Osaka' is no [fonts] name and no path, dropping it from the chain"),
  and an empty entry (`face=ko,,ja`) is skipped with one warning. Name
  faces in `[fonts]` and chain the names.
- **After the chain** comes the engine's own fallback: SCI the `.uni`
  bundle (presented in the chain's cell), then the game's font; SCUMM the
  game's charset; AGS the game's own font N, character by character.
- **Faces in one chain are fitted separately**, each to the same cell;
  two faces on one line may not share a baseline exactly.
- **`[font.N] bitmap=`** names an SVFN font for font/charset N, relative
  to the map. SCUMM tries it before the faces; AGS draws it instead of any
  face. SCI parses the key but does not use it.
- **`[layout]`** (optionally `[layout:<gameid>]`): `hangul=word|any`,
  `kinsoku=on|off`, `thai=on|off`. Defaults: SCI `word/on/on`, SCUMM
  `any/on/on` (the Korean patches' own rule), AGS `word/on/on`. An unknown
  key or a bad value is one warning and keeps the default. It applies to a
  UTF-8 translation (and, on AGS, to EUC-KR text and to map fonts); legacy
  code-page text keeps the engine's own breaker.

## A complete, worked example: KQ1-ko

KQ1-ko draws three kinds of text, each its own SCI font id (found with the
diagnostic `hires_text_log` ini key; see `HIRES_COMPOSITOR_DESIGN.md`
§5.2 for how):

| Font id | What it draws |
|---|---|
| `0` | Status line, menu bar, parser echo ("득점: 0 of 158", "File", "look") |
| `4` | Title screen and its menu ("게임시작", "이어서 계속하기") |
| `300` | Dialogue and narration boxes - the text players spend the most time reading |

Here is a map that was built and verified against exactly this game (the
face paths are macOS system fonts, used for local testing; ship your own
TTFs alongside the map instead):

```ini
[hires]
; the face for a [font.N] section that names no face of its own
font=default

; face name -> file. Relative paths are taken against the directory
; that holds this map file.
[fonts]
default=/System/Library/Fonts/AppleSDGothicNeo.ttc
latin=/System/Library/Fonts/Supplemental/AppleGothic.ttf

; the default for every font id below, unless overridden
[latin]
; draw the Latin range in the "latin" face, not "default"
face=latin

; the dialogue box: most text, so fullwidth reads best
[font.300]
; "xyzzy" becomes "ｘｙｚｚｙ", same cell width as before
latin=fullwidth

; the status line / menu bar / parser echo: short, narrow font
[font.0]
; "0 of 158" draws in AppleGothic at its own narrow width
latin=half

; font 4 (title/menu) has no [font.N] section here, so it stays off -
; its Latin text (none, in KQ1-ko - the title screen is already Korean)
; is drawn by the game's own font, as if there were no map at all.
```

With this map and *no* `hires_text_latin*` ini keys at all, font 300 and
font 0 draw in two different Latin modes from one file - something the
ini keys alone cannot do, since they apply the same mode to every font id.
This is the exact map used for the per-font-id captures below.

A second worked example, this time for proportional Latin (see "Modes"
below for what that means): give every font id `metrics=game` (identical
line breaks to today) except the dialogue box, which switches to the
TrueType face's own advances:

```ini
[latin]
mode=proportional
face=latin
; the default for every font id: keep today's layout
metrics=game

[font.300]
; the dialogue box alone follows AppleGothic's own widths
metrics=font
```

## Precedence

Every setting (face, size, Latin mode, Latin face, space handling,
metrics) is resolved independently, in this order, most specific first:

1. **The matching ini key** (`hires_text_font`, `hires_text_font_size`,
   `hires_text_latin`, `hires_text_latin_font`, `hires_text_latin_space`,
   `hires_text_metrics`) - global, and wins over the map entirely for
   that setting, on every font id at once.
2. **`[font.N:<platform>]`**, then **`[font.N]`** - settings for one SCI
   font id. `<platform>` is ScummVM's platform code (`pc98`, `dos`, ...);
   the qualified section wins only on that platform, key by key, so a
   `[font.0]` and a `[font.0:pc98]` can each set different keys and both
   apply.
3. **`[latin:<platform>]`/`[latin]`** for Latin mode, Latin face, space
   and metrics; **`[hires:<platform>]`/`[hires]`** for the face and size
   a `[font.N]` did not itself name.
4. **The built-in default**: size 16, Latin off, space keep, metrics
   game, no separate Latin face (the main face draws everything). **On
   SCUMM this last one differs** (C31, C34, C36): with no metrics key at
   all and a TrueType face, the built-in default is to step every glyph
   (wide and Latin) by the face's own advance, not by the game's cell -
   see "Wide and Latin glyphs step by the face by default" in the SCUMM
   section below for the exact rule and how to opt back into the game's
   cell.

So a map that names nothing for a font id reproduces today's behaviour
for it exactly on SCI - the map only ever adds settings, never a
game-wide override; an ini key is the only thing that can override every
font id at once. On SCUMM, naming nothing still selects the game's own
font entirely (no map, no change at all); it is the presence of a
TrueType face with no metrics key that now steps by the face rather than
the cell.

One legacy shorthand, kept for compatibility with SCUMM maps: `[latin]
enabled=true` means "the engine's usual Latin behaviour", which for SCI is
`latin=proportional` (its metrics follow the usual chain, so `game`
unless a `metrics=` says otherwise). It is decided per font id, as the
last step before the default: a font id whose mode is set by the ini key
`hires_text_latin`, by its own `[font.N] latin=`, or by `[latin] mode=`
takes that mode; every other font id gets proportional. So one
`[font.4] latin=off` turns font 4 off and leaves the alias in force for
the rest. SCUMM's `bitmap=` key also implies `enabled` on
SCUMM, but SCI has no bitmap Latin path - a map with only `bitmap=` gets
one warning and no effect (see "Warnings" below).

## Sections and keys

| Section | Key | Meaning |
|---|---|---|
| `[hires]` | `font=` (or `face=`) | The face a `[font.N]` that names none falls back to - a `[fonts]` name, or a path |
| `[hires]` | `size=` | Pixel size, same fallback role |
| `[hires]` | `pixel=` (C28) | Design size (in px) of a pixel-grid font; fallback role, same as `size=` - see "Pixel-locked fonts" below |
| `[fonts]` | *name*`=`*file* | Face name -> file, referenced by `font=`/`face=`/`latin_font=`/`latin_face=` elsewhere. Case-insensitive names; relative paths are taken against the directory holding the map |
| `[latin]` | `mode=` | `off` \| `half` \| `fullwidth` \| `proportional` - the default for every font id |
| `[latin]` | `font=` (or `face=`) | Face for the Latin range; absent means the font's own face draws it |
| `[latin]` | `space=` | `keep` \| `fullwidth` (fullwidth mode only) |
| `[latin]` | `metrics=` | `game` \| `font` (proportional mode only) |
| `[font.N]` | `face=` (or `font=`) | Face for this font id |
| `[font.N]` | `size=` | Pixel size for this font id |
| `[font.N]` | `pixel=` (C28) | Design size (in px) of a pixel-grid font for this font id, overriding `[hires] pixel=` |
| `[font.N]` | `latin=` | Overrides `[latin] mode=` for this font id |
| `[font.N]` | `latin_font=` (or `latin_face=`) | Overrides `[latin] font=` for this font id |
| `[font.N]` | `latin_space=` | Overrides `[latin] space=` for this font id |
| `[font.N]` | `metrics=` | Overrides `[latin] metrics=` for this font id |
| `[font.N]` | `mirror=` (C27, SCUMM only) | `true` \| `false` \| `horizontal` \| `vertical` \| `both` - draw this font id's glyphs flipped; see "Mirrored charsets" below |

`[font.N]` must be written exactly that way - a numeric id, `[font.4]`,
optionally `[font.4:pc98]`. `[font.04]` or `[font.4:]` (an empty
qualifier) are rejected with a warning, not silently treated as `[font.4]`.

### The same keys on SCUMM (C11 T6)

SCUMM (v1-v6, hi-res text layer) reads the keys of the table above with the
same meanings, with these differences
(`engines/scumm/HIRES_TEXT.md`, "Per-charset faces and per-glyph placement"):

| Key | SCUMM |
|---|---|
| `[font.N]` | `N` is the SCUMM **charset id**, 0..19 (not an SCI font id) |
| `[font.N] bitmap=` | an SVFN for that charset, relative to the map, tried before its faces |
| `[hires] face=`, `[font.N] face=` | a face or a comma-separated chain; the first face with the character draws it, then the game's font. Else `[fonts] default=`; the ini `hires_text_font` overrides all |
| `[hires] size=`, `[font.N] size=` | the characters' pixel size (as SCI); without one, the face is opened at the game cell times the scale, its line filling the cell (as before). `[hires] size=` applies to every charset: a game whose charsets have different cell heights (MI1's 16-px sentence line beside its dialogue) should use `[font.N] size=` per charset |
| `[latin] mode=`, `[font.N] latin=` | `off`/`half`/`fullwidth`/`proportional` as on SCI; the **default is `proportional`** (SCUMM always drew ASCII with the replacement); `[latin] enabled=false` means `off` |
| `[latin] metrics=`, `[font.N] metrics=` | `game` = the game's cell width for this charset's Latin range, `font` = the older explicit proportional path (`latinAdvanceGamePx()` of the face's advance, with carry). `[font.N] metrics=` also sets wide glyphs for that charset; the ini `hires_text_metrics` wins over both |
| `[render] metrics=` | `game` restores the game's cell for **every** glyph (wide and Latin) that a metrics key would otherwise steer to the face - see "Wide and Latin glyphs step by the face by default" below |

**Wide and Latin glyphs step by the face by default (C31, C34, C36).** With
a TrueType face and **no metrics key at all** - none of the ini
`hires_text_metrics`, `[render] metrics=`, `[font.N] metrics=` or
`[latin] metrics=` - every glyph the face draws (a wide CJK syllable since
C31, and ASCII `0x21`-`0x7E` since C34/C36) advances by that face's own
advance, rounded up to game pixels for wide glyphs and rounded half up for
Latin, and is drawn at the pen rather than centred in the game's cell.
This is now the default **everywhere a TrueType face is used**: a legacy
CP949/EUC-KR patch, a UTF-8 translation, and the game's own untranslated
text (English included) all step by the face the same way. A combining
mark still advances 0 and is drawn against the previous base. Bitmap
(SVFN) faces, and any face a `[glyphs]` entry or `[latin] mode=` other
than `proportional` routes around, are unaffected and always keep the
game's cell. A `pixel=` face (C28) is a TrueType face too, so it steps by
its own (grid-locked) advance the same way.

- **The space** advances by the face as well, *unless* the game is laying
  that charset out on a legacy CJK patch's cells (a Korean or Chinese
  `.fnt`/`.trs`/`.tra` patch under CP949, or the same cells read from a
  patch's headers for a UTF-8 translation, C31) - there the space keeps
  the game's own width, because it is also the word gap the CJK patches
  were designed around. `[latin] space=fullwidth` also keeps the game's
  space regardless.
- **The way back to the old, game-cell spacing** is any explicit metrics
  key: ini `hires_text_metrics=game`, `[render] metrics=game`,
  `[font.N] metrics=game`, or `[latin] metrics=game`. Each of these
  reproduces the pre-C31/C34/C36 layout exactly, including the Korean
  patches' cell-plus-one-pixel gap. `[latin] metrics=font` still means the
  older explicit proportional path (the same face-stepping idea, but with
  a rounding carry and gated the old way); it is unchanged by these cards.
- **Missing game glyphs are drawn.** A code point the game's own charset
  has no bitmap for (MI1's charset 6 lacks `,` and `.`) used to measure and
  draw as nothing; when it steps by the face it is now measured *and*
  drawn, in a box as wide as its face step. `[render] metrics=game` (or
  any other explicit metrics key) keeps the old "invisible" behaviour.
- **Latin drawn by the face drops the game glyph's own per-glyph
  y-offset**, so ASCII sits on one baseline the way ordinary TrueType text
  does, instead of inheriting the bitmap font's per-glyph baseline wobble
  (some charsets nudge `,`/`p`/`g`/`j` down by one game pixel). An explicit
  metrics key keeps the old placement, descender wobble included.
- **A mirrored charset (C27) that stays on the game's own font** is
  unaffected by any of this, whatever the metrics keys say.
- **FM-Towns and the SCUMM V2 renderer keep the game's widths** for Latin
  even with no metrics key: their `getCharWidth()` never asks the hi-res
  layer, so measuring and drawing would otherwise disagree. A TTF map for
  such a target should still set `[render] metrics=game` explicitly to
  make the intent clear.
- **A map without a metrics key changes line breaks and box sizes** for
  *every* existing SCUMM map that names a TrueType face, English included -
  the shipped `korean-default.map`, `mi1-styled.map` and
  `scumm-2x-neodgm.map` all rewrap. A map for an English (or any
  untranslated) game that must keep the original's exact line breaks needs
  `[render] metrics=game`.
- **Known limits.** Each glyph rounds its own step up (or half up, for
  Latin) with no carry between glyphs, so at 3x/4x scale a syllable or
  letter can sit up to (scale-1) output px looser than the older
  carry-based `metrics=font` path gave; visible only at 3x and above.
  FM-Towns Japanese (SJIS) measures with a fixed width while drawing takes
  the face step, so a centred FM-Towns Japanese line can sit off-centre by
  `(cell - step) x n / 2`; use `[render] metrics=game` there too.

With a translation loaded, each face is checked against 64 of its code
points (one warning per face). A SCUMM map with none of `[hires]
face/size/pixel`, `[font.N]` and `[latin] mode/space` is read exactly as
before.

**UTF-8 over a legacy CJK patch reads only the patch's font headers
(C31).** When a UTF-8 translation (`ko.trs`, a Chinese `.trs`, ...) plays
next to a legacy Korean/Chinese patch's own font files
(`korean0N.fnt`/`korean.fnt`/`chinese_gb16x12.fnt`), SCUMM reads just
those files' headers - cell size, shadow mode, line height, the Korean
`+1` gap - to lay the UTF-8 text out on the same grid the CP949 text uses;
it never loads the patch's own glyphs (the TrueType face chain draws the
glyphs). The result is that **a CP949 patch and a UTF-8 translation using
the same map and the same faces are pixel-identical** wherever hi-res text
is on. Without such a patch beside it, a UTF-8 translation lays out purely
by the face's own metrics.

**Centred text breaks Hangul (and other wide-script text) at spaces by
default**, matching the CP949 patches' own rule, but **only while hi-res
text is enabled** - with hi-res text off, centred UTF-8 text keeps its
older "break anywhere" rule, so a map that turns hi-res text off leaves
line breaking exactly as it always was. `[layout] hangul=any` restores
the "break anywhere" rule with hi-res on.

**Not yet implemented**, though a map that already has them for SCUMM
will not warn: `baseline=`, and `[hires] scale=` beyond what the
compositor already fixes. Per-glyph kerning/centring in proportional
mode and the legacy SJIS face are also not implemented yet.

**`[glyphs]` is parsed, but not yet applied on SCI.** The shared parser
(`graphics/hires_text/font_map.cpp`) reads single codes, `keep`, ranges
(`0x21-0x7E=+0xFEE0`), scopes (`[glyphs:cs1]`) and qualified sections the
same way for both engines, so a bad entry - including a bad range - gives
the same warning on an SCI map as it would on a SCUMM one (see "Warnings
to expect" below). SCI just does not act on the resulting table yet: every
game still draws its own glyphs for the codes a `[glyphs]` section covers.

### Outline and shadow: `[shadow]` (SCUMM v1-v6, C19)

The outline is built from the glyph's coverage, whatever the source (TrueType,
an 8 bpp bitmap, a 1 bpp patch font), so it works the same for Korean,
Japanese and Thai. By default it is round and antialiased, 0.75 x scale wide
(1.5 output pixels at 2x). On a blended 32-bit screen it goes on a layer of its
own under the text, so the text's antialiased edge sits on the outline with no
seam. On a keyed 8-bit screen (v7, `alpha=false`, FM-Towns, Mac v3) it is
solid. Every length is in output pixels.

```ini
[shadow]
mode=game           ; game (default) | none | drop | outline | stroke
color=0             ; outline colour (palette index)
width=1.5           ; outline radius in output px, to a quarter (0..8)
style=round         ; round | square | legacy (the pre-C19 binary look)
offset=2            ; shadow distance; also the width when width= is absent
shadow=-1,1         ; a shadow of the outline at dx,dy output px; none = off
shadow_color=0      ; defaults to color
shadow_alpha=60     ; 0..100 on a blended screen; keyed: >= 50 solid, else none
```

`mode=game` follows the game. With a kor-trs v1-v6 patch that is byte 1 of the
charset's `korean%02d.fnt`, where `s` is the scale:

| byte | patch renderer | hi-res layer |
|---|---|---|
| 1 | none | none |
| 0, 4 and up | 8-direction outline | round outline, 0.75 x s wide |
| 2 | drop (1,1) | drop of the glyph's coverage by s/2, rounded up |
| 3 | outline + lower-left | the outline plus a copy moved (-s/2, +s/2) |

A game with no patch font (English, a UTF-8 translation) draws nothing under
`mode=game`. v7 (Full Throttle, The Dig, COMI) draws no decoration.

Existing maps change look: an `offset=N` map now gets a round N px outline
instead of the old square ring; `style=legacy` brings the old one back, without
the gaps it had above 1 px. Engine-side detail:
`engines/scumm/HIRES_TEXT_DECORATIONS.md` and `graphics/hires_text/README.md`
("Decoration (C19)").

### Mirrored charsets: `mirror=` (SCUMM, C27)

MI1 (v4/v5), MI2 (v5) and Loom CD store charset 3 (used for the dazed
dialogue in MI1's Fettucini brothers' tent, room 51) turned half a turn:
every glyph is the normal one flipped both across and down, and the
strings themselves are stored back to front, so the game draws them left
to right and the whole line reads upside down when the screen is the
right way up. The Korean UTE patch ships its own cs3 Hangul font turned
the same way, with its `korean.trs` line reversed by syllable.

- **By default such a charset keeps the game's own font**, flipped as the
  game always draws it - a map that touches nothing else reproduces the
  original (and the Korean patch) pixel for pixel.
- **`[font.N] face=`, `mirror=` or `bitmap=`** asks for the replacement
  face instead; it is drawn flipped too (as the game's own font is)
  unless `mirror=false` says otherwise.
- **`mirror=`** takes `true` (reproduce the game: half a turn for
  MI1/MI2/Loom CD's charset 3, horizontal for a charset the engine's table
  does not know), `false`/`off`/`no`/`0`/`none`, or a mode directly:
  `horizontal`, `vertical`, `both`/`rotate`. Each glyph is flipped inside
  its own advance box, in the string's stored order - nothing is
  reordered. A combining mark flips together with its base.
- **UTF-8 text is the one exception**: on a mirrored charset it always
  takes the replacement face, flipped, because the game's own font has no
  glyph for anything past ASCII (it would draw `?`).
- **A translation for a mirrored charset must store the line already
  reversed, by grapheme cluster** (a base followed by its own marks, not
  code point by code point) - exactly as the Korean patch reverses its
  Hangul syllables. Whole-line reversal at draw time is not implemented.
- **A `[font.N]` section holding only `mirror=`** does not by itself
  switch that font id to per-glyph placement (unlike `face=`, `size=` or
  `pixel=`).
- Verified against real game data on MI1/MI2 UTE and Loom CD only; a wrong
  table entry for another release only keeps that charset on the game's
  own font, which is harmless.

### Erasing hi-res text on single-buffered screens (SCUMM, C32)

SCUMM's verb area, MI1's dialogue-choice lines and the v0-v2 text screen
are drawn straight into a **single-buffered** virtual screen: the game
erases old text there by painting over the same buffer, not by swapping
buffers. Since hi-res glyphs are drawn to the overlay instead of that
buffer, the engine traces every hi-res glyph drawn on such a screen (its
game cell and its inked area) and erases the traced glyphs whenever the
game paints over the area their cell sits in - the moment a menu closes,
verbs come back, or one dialogue choice replaces another. This is the
third place hi-res text is erased, alongside `restoreCharsetBg()`
(ordinary removable text) and the kept-text retirement on the main screen.
Nothing about this is configurable from the map; it applies whenever the
hi-res layer is on. The original GUI's own drawing (menus, the pause
banner) saves and restores the traced-glyph records the same way it saves
and restores the overlay's pixels, so text under a temporarily-opened menu
comes back correctly once the menu closes.

### A face inside a font collection: `path.ttc#N` (C21)

Any TrueType path a map names (`[fonts]`, `[hires] face=`, `[font.N] face=`,
SCUMM's `hires_text_font`) may end in `#N` to pick face N of a `.ttc`/`.otc`
collection. A file whose full name exists is used as it is, so a literal `#`
in a file name still works; otherwise the digits after the last `#` of the
file name pick the face (0..65535), and relative paths still resolve against
the map. A face the file does not have gives a warning and is skipped like a
missing file, and the chain carries on. Size fitting, the coverage check and
every glyph use the chosen face. Works on SCUMM, SCI and AGS; Grim font
descriptors name files inside the game and do not take it.

Face numbers on macOS: AppleSDGothicNeo 0 Regular, 2 Medium, 4 SemiBold,
6 Bold; SukhumvitSet 0 Thin, 2 Text; Hiragino Sans W3 is face 0 of its file.
No extraction step (ttc2ttf.py) is needed any more.

### Pixel-locked fonts: `pixel=` (C28)

`size=` and the plain line fit both **fit** a face to the cell: they pick
whatever pixel size makes the face's line, or a fixed probe set of glyphs,
match the target height, which usually lands on a size a pixel font was not
drawn at - a Galmuri or Neo둥근모 face shrunk or grown off its grid looks
blurred or clipped instead of crisp. `pixel=<D>` says instead "this face is
a pixel font designed at `D` px": the chain's **first** face opens at the
largest multiple of `D` that fits the cell (or `D` itself in a smaller
cell), with **no fit at all** - not to the line, not to a probe set, not to
the translation's sample - and is drawn from the line's top in whole
pixels, so its grid is never fractional.

| Mode | Pixel size chosen | Layout cell | Fits to |
|---|---|---|---|
| Line fit (no `size=`, no `pixel=`) | `round(upm x cell / (winAscent+winDescent))` | the game's own cell | the line |
| `size=N` | whatever makes the probe set (Hangul, `A g j y Å`, brackets, CJK quotes) fit N rows | **becomes N** (`size=` changes the layout cell, not just the raster) | the probe set |
| `pixel=D` | the largest multiple of D that fits the cell (D itself in a smaller cell) | the game's cell (unchanged) | nothing - no probe, no line, no translation sample |

- `[hires] pixel=` applies to every font id; `[font.N] pixel=` overrides it
  for one. `[hires] size=`/`[font.N] size=` still work together with
  `pixel=`: on SCUMM, `size=` (if also given) sets the cell `pixel=` grids
  into instead of the game's own cell x scale; on SCI it is the cell
  outright (default 16); on AGS it is the cell before the size multiplier.
- **Only the chain's first face is opened as a pixel face.** The faces
  behind it are ordinary fallbacks, fitted to the same cell as usual - a
  chain such as `face=galmuri, sukhumvit` does not try to grid-lock
  Sukhumvit.
- **A face named only by the ini key `hires_text_font` (no map, or a map
  that does not name that face) is never a pixel face**, even when
  `[hires] pixel=` is set: `pixel=` only ever applies to a face the map
  itself names. When SCI falls back from a `[font.N] face=` that failed to
  open to the font id shared by every font, that shared face still takes
  `[hires] pixel=` if the map sets it.
- **SCUMM, SCI and AGS read `pixel=`; Grim does not.**
- **AGS at N x (`[hires] scale=`/`hires_text_scale`, C23).** The N x pass
  opens the pixel face at exactly N times the 1x face's own ppem (not N
  times the design size fit into the N x cell), so the N x glyphs line up
  pixel-for-pixel with the N x pens - `pixel=10` in a 15 px cell opens at
  10 ppem at 1x and exactly 20 ppem at 2x.
- **Recommended design sizes** for the fonts bundled with ScummVM (see
  "Bundled fonts" below): Galmuri7 8, Galmuri9 10, Galmuri11 (Bold) 12,
  Neo둥근모 16. A pixel font whose own line is taller than the cell it is
  asked to fit keeps its ppem exactly, and is shifted down by whole rows
  (never fractional) until its Hangul and `A g j y` ink fits; nothing about
  a too-small cell shrinks the face.
- **No auto-detection.** ScummVM cannot tell a pixel font from an ordinary
  TrueType face on its own (`Graphics::Font` exposes neither the outline's
  coordinate grid nor whether the face is an embedded bitmap strike without
  reading outlines at load time, past the engine's probe budget) - `pixel=`
  must be set by the map.
- **Baking a pixel font's full Unicode repertoire.** `tools/korean/mkfont.py
  --unicode <ranges>` writes a version-2 SVFN keyed by code point instead of
  by code page (`ascii`, `latin1`, `hangul` = all 11172 syllables, `jamo`,
  `cjk-punct`, `ksx1001` = the 2350 KS X 1001 syllables, `kana`, `thai`, or
  raw hex ranges); a code point the face draws no ink for (including one
  that renders identically to its `.notdef`) is left out, so the chain
  falls back for it instead of baking a blank cell.

### Bundled fonts and maps: `data:` paths (C29)

ScummVM ships a small set of free (OFL) fonts and four example maps in the
tree, at `dists/engine-data/hires_text/` - `fonts/<family>/` and `maps/`.
A map (or an ini path key) can name one of them without knowing where the
data directory ended up, with the `data:` prefix:

```ini
[fonts]
ko=data:hires_text/fonts/nanumgothic/NanumGothic-Bold.ttf
```

- **The prefix is case-sensitive** (`data:`, not `Data:`) and is recognised
  anywhere a path is otherwise accepted: `[fonts]` entries, a bare `face=`/
  `latin_font=`/`bitmap=` path, and the ini keys `hires_text_map` and
  `hires_text_font` (SCUMM). SCI and AGS, which used to open
  `hires_text_map=` with a raw file path, now also resolve a `data:` value
  in it - so `hires_text_map=data:hires_text/maps/korean-default.map` works
  in **SCUMM, SCI and AGS** alike. A `#N` face-collection suffix (previous
  section) still works after a `data:` path.
- **A `data:` path may not be absolute and may not contain a `..`
  component** - it names a file shipped with ScummVM, not an arbitrary path
  on disk. A value that breaks this rule is refused with one warning and
  no folder is searched; write an ordinary relative or absolute path
  instead.
- **Search order.** The name after `data:` is looked for, in this exact
  order, stopping at the first root that has the file:
  1. the **command-line** `--extrapath`;
  2. the **game's own** `extrapath` (its ini domain);
  3. the **global** `extrapath` (`[scummvm]`);
  4. the **dev default** - in a non-release build run from a source tree,
     `dists/engine-data/` is put in the session domain automatically, so
     `data:` finds the bundled fonts with no extra setup;
  5. the **ScummVM data directory** (`DATA_PATH`, compiled in) - where
     `make install-data` puts a copy, at `<datadir>/hires_text/`.

  A file present in more than one root is taken from the first root that
  has it. When no root has the file, the value is used as-is (so it still
  fails to open, the normal way) and one warning is logged first:
  `HiResText: 'data:X' is not in the extrapath or the ScummVM data
  directory`.
- **From a source tree**, run with `--extrapath=dists/engine-data` (or rely
  on the dev-default root above).
- **Packaging gap.** Only the POSIX `make install`/`install-data` carries
  `hires_text/` into the installed tree. The macOS `.app` bundle,
  dist-generic and the other port packages do **not** ship it, and `data:`
  does not search the bundle's Resources folder. On those builds, copy
  `hires_text/` somewhere and point `extrapath` at the folder that holds
  it.

#### Bundled fonts

All are unmodified upstream files, OFL 1.1 licensed; the licence text and
full attribution (copyright holder, designer, Reserved Font Names, source
URL) is in `dists/engine-data/hires_text/fonts/FONTS.md`, one entry per
family - read it before shipping a translation that uses one of these.

| Family | File(s) | Licence | Use | Design size |
|---|---|---|---|---|
| NanumGothic | `nanumgothic/NanumGothic-{Regular,Bold}.ttf` | OFL 1.1, Nanum RFNs | Default Korean face: **Bold** for blended (alpha) text at 2x (SCUMM v5/v6, SCI, AGS); **Regular** for keyed 8-bit text. All 11172 Hangul syllables, no Hanja | - |
| Galmuri7 | `galmuri/Galmuri7.ttf` | OFL 1.1, no RFN | Pixel font, 10 px cells | 8 px |
| Galmuri9 | `galmuri/Galmuri9.ttf` | OFL 1.1, no RFN | Pixel font, Full Throttle's 12 px cell, keyed at 1x | 10 px |
| Galmuri11 Bold | `galmuri/Galmuri11-Bold.ttf` | OFL 1.1, no RFN | Pixel font, 16 px cells (Regular cut not shipped, >5 MB) | 12 px |
| Neo둥근모 (NeoDunggeunmo) | `neodgm/neodgm.ttf` | OFL 1.1, Neo둥근모 RFNs | Keyed SCUMM v5/v6 text at 2x, DOS-era pixel look | 16 px |
| Black Han Sans | `blackhansans/BlackHanSans-Regular.ttf` | OFL 1.1, no RFN | Korean heavy display face (chapter cards, credits). 2581 syllables (KS X 1001's 2350 plus 231) - chain a full-coverage face after it |
| Coustard | `coustard/Coustard-Black.ttf` | OFL 1.1, no RFN | Latin heavy serif display face (`latin_font=` beside Black Han Sans) |
| Nanum Myeongjo Bold | `nanummyeongjo/NanumMyeongjo-Bold.ttf` | OFL 1.1, Nanum RFNs | Korean serif (light display text, e.g. MI1/MI2 verb charset). All 11172 syllables |
| EB Garamond | `ebgaramond/EBGaramond-VF.ttf` | OFL 1.1, no RFN | Latin old-style serif (`latin_font=` beside Nanum Myeongjo). Variable font |
| Nanum Pen Script | `nanumpenscript/NanumPenScript-Regular.ttf` | OFL 1.1, Nanum RFNs | Korean handwriting (notes, e.g. Blackwell). All 11172 syllables |
| Caveat | `caveat/Caveat-VF.ttf` | OFL 1.1, no RFN | Latin handwriting (`latin_font=` beside Nanum Pen Script). Variable font |

- **OFL renaming rule.** Every font here is shipped unmodified. Under the
  OFL, a *modified* version - a subset, a baked SVFN/bitmap conversion, a
  hinted or re-encoded copy - must **not** keep a Reserved Font Name. So a
  baked bitmap font built from NanumGothic, Nanum Myeongjo, Nanum Pen
  Script or Neo둥근모 (all of which carry RFNs) needs a new name; Galmuri,
  Black Han Sans, Coustard, EB Garamond and Caveat have no RFN and may keep
  their name even when subset or baked.
- **Variable-font weight caveat.** EB Garamond (weight axis 400-800) and
  Caveat (400-700) are shipped as their single variable-font file, but
  ScummVM's FreeType loader opens only the **default instance, Regular
  400** - there is no map key yet to pick a bolder instance. If a design
  needs EB Garamond or Caveat at a heavier weight, that weight is not
  reachable through the map; use a different face for now.
- **Two files were renamed from their upstream names**, bytes unchanged:
  `EBGaramond[wght].ttf` -> `EBGaramond-VF.ttf`, `Caveat[wght].ttf` ->
  `Caveat-VF.ttf` (square brackets are awkward in map files and Makefile
  wildcards).

#### Example maps (`dists/engine-data/hires_text/maps/`)

| Map | For | What it does |
|---|---|---|
| `korean-default.map` | SCUMM v5/v6, SCI, AGS - a starting point for any Korean translation | `scale=2, alpha=true`, NanumGothic Bold via `data:`, blended |
| `ft-keyed-galmuri9.map` | Full Throttle (SCUMM v7) Korean, keyed 1x | Galmuri9 at its 10 px design size, `cp949`, no `size=` (a size key would shrink it off its pixel grid) |
| `scumm-2x-neodgm.map` | SCUMM v5/v6 Korean, keyed 2x, DOS look | Neo둥근모 held at `size=16` per charset (its design size) |
| `mi1-styled.map` | The Secret of Monkey Island (UTE) Korean | Per-charset styled faces - Black Han Sans + Coustard for the heavy display charset, Nanum Myeongjo Bold + EB Garamond for the light-serif charset, NanumGothic Bold elsewhere |

Copy one into a game folder as `hires_text.map`, or point
`hires_text_map=data:hires_text/maps/<name>.map` at it directly; a map
loaded this way should use `data:` for its own font paths too, since its
folder is the data folder, not the game's.

### Heavier text: a heavier face, or `[hires] gamma=` (C20)

Thin faces look grey once text is blended over an outline (MI2 Korean in
Apple SD Gothic Neo Regular). The recommended Korean face is **NanumGothic
Bold** (Naver, OFL, all 11172 syllables drawn; chosen in C22 from the
공유마당 free-font board): heavier than Apple SD Gothic Neo Bold at game sizes
(mean text level 205 against 189) with dense syllables still open. It ships
with ScummVM (see "Bundled fonts and maps" above) as
`data:hires_text/fonts/nanumgothic/NanumGothic-Bold.ttf` - use that path
instead of a local copy where the target build has the bundled fonts
available. It has no Hanja; for text with Hanja use Noto Sans KR Bold.
Beware free fonts that map all 11172 syllables but draw only 2350 (many
municipal fonts do): the missing ones come out blank. On macOS without
extra fonts, AppleSDGothicNeo.ttc face 6 is Bold, which C20 measured as the
best default for Korean (mean text level 190 against Regular's 171, and
dense syllables such as 췄 떡 밥 stay open):

```ini
[fonts]
ko=/System/Library/Fonts/AppleSDGothicNeo.ttc#6
th=/System/Library/Fonts/Supplemental/SukhumvitSet.ttc#2
```

Apple's fonts may not be redistributed, so this is for local maps.

For a script whose only face is light, `[hires] gamma=` (0.5 to 4, default
1 = off) raises TrueType coverage as `255 * (c/255)^(1/gamma)` when a glyph
is rasterised; coverage below 4 is left alone. It applies to the whole face
chain on SCUMM, SCI and AGS; Grim and SVFN or baked bitmap fonts ignore it.
Outlines widen with the body (about +0.23 px at 2.2), and on a keyed
(8-bit) screen more pixels cross the ink cut, so keyed text gets heavier.
Omitting the key leaves every existing map byte-identical.

### SCI with a UTF-8 translation (C11 T5)

On SCI16 the map (and the `hires_text_*` ini keys) apply when the game's
text is a **UTF-8 translation** or the game is in a legacy CJK code page
(949/932/936/950); the game's language does not decide it. A UTF-8
translation is recognised by:

- a detection entry marked UTF-8 (KQ1-ko), or
- **`sci-<lang>.str` present in the game directory for the chosen
  language** - the translation's manifest; it may hold only comments.
  The rule also asks for `language=` in the game's ini domain, but a game
  added through the launcher always has one (the detected language), so
  in practice **the manifest alone decides**: a stray `sci-en.str` beside
  an English game turns the UTF-8 path on for it. Name the file for the
  language the translation is in, and set `language=` to that language.

With a translation loaded:

| Key | SCI |
|---|---|
| `[hires] face=`, `[font.N] face=` | a face or a comma-separated chain; the first face with the character draws it, then the `.uni` bundle (presented in the faces' cell), then the game's font. Each face is checked against 64 of the translation's code points: one warning per face naming what it lacks, or that it draws combining marks as spacing glyphs |
| `[hires] size=`, `[font.N] size=` | as before; font ids with the same chain at different sizes get separate chains |
| `[layout] hangul=`, `kinsoku=`, `thai=` | line breaking of the translation: defaults `word`, `on`, `on` (SCI always broke Hangul at spaces) |

Glyphs beyond ASCII are placed by their own metrics: a glyph the face keeps
in two cells (Hangul, kana, kanji) keeps the cell rule, a combining mark
advances 0 and is drawn against the previous base, any other glyph
advances by the face's own advance. A game **without** a translation (a
legacy Korean or Japanese release, a `.uni` bundle) keeps the cell widths
of its fonts to the pixel.

**Where there is no text plane.** The UTF-8 path needs the upscaled
graphics driver (the text plane). The driver table still matches platform
rows first, as it does for Korean today: a UTF-8 translation of a Windows
SCI1.1 release, or of KQ6 on DOS with hi-res graphics on, takes that
platform's own driver, which has no text plane - its glyphs are not shown
(one warning: "the graphics driver for this game ... does not composite
the text layer"). Use the DOS release, or turn hi-res graphics off.

### AGS (C11 T8)

AGS reads the map only when the game directory has `hires_text.map` or the
ini names one with `hires_text_map=`; its sections are qualified by the game
id (`[font.0:5daysastranger]` before `[font.0]`). `N` in `[font.N]` is the
AGS font number. Without a map and without `hires_text_font`, every font is
the game's own (`agsfntN.ttf`/`.wfn`, plus a Korean patch's `extfntN.wfn`).

| Key | AGS |
|---|---|
| `[font.N] bitmap=` | an SVFN font for font N, relative to the map; wins over every face |
| `[font.N] face=`, ini `hires_text_font`, `[hires] face=`, `[fonts] default=` | in this order, the first that is set: a face or a comma-separated chain; the first face with the character draws it, then the game's own font N (character by character, so a run the chain lacks loses the game font's kerning) |
| `[font.N] size=`, ini `hires_text_font_size`, `[hires] size=` | pixels; without one, the game font's height |
| `[hires] alpha=` | default `true`: coverage is blended into 16/32-bit games; `false` (and 8-bit games) draw a pixel where coverage is at least half |
| `[hires] scale=`, ini `hires_text_scale` | N, 1-3, default 1 (off). Draws the game's mapped text at N× over an N×-upscaled game frame; see "AGS hi-res text at N× (`[hires] scale=`, C23)" below |
| `[layout] hangul=`, `kinsoku=`, `thai=` | line breaking, defaults `word`, `on`, `on`. Breaking goes through the shared layout stage only for a UTF-8 translation, an EUC-KR (Korean patch) translation, or while the map names fonts; an English or native UTF-8 game without either keeps AGS's own breaking |

With a UTF-8 translation, each face is checked against 64 of its code points
(one warning per face). A translation with combining marks (Thai) whose
game fonts are TTFs drawn by alfont gets one hint to add a map: alfont clips
the marks above the line and places them after their base.

Details worth knowing on AGS (C11 T8 review, `[source]` in
`engines/ags/shared/font/hires_font_plan.cpp` and
`engines/ags/engine/ac/translation.cpp`):

- **The face order is `[font.N] bitmap=` > `[font.N] face=` > ini
  `hires_text_font` > `[hires] face=` > `[fonts] default=`.** So on AGS,
  unlike SCI and SCUMM, a map's own `[font.N] face=` beats the ini key.
  The unit tests pin each step alone and `[fonts] default=` alone; the
  pair `[hires] face=` + `[fonts] default=` in one map is not covered by a
  test (the code takes `[hires] face=`).
- **What turns the map fonts on** (and with them the shared line
  breaking of UTF-8 text): a map with any `[font.N]` section, a non-empty
  `[hires] face=`, or `[fonts] default=` - **or the ini key
  `hires_text_font` alone, with no map at all**. A native UTF-8 game (no
  translation) with only that ini key therefore breaks its lines with the
  shared stage, not AGS's own loop.
- **A `.tra` that fails to open still counts as "a translation is
  loaded"** for that gate: AGS sets the translation name before it opens
  the file and does not clear it on failure (upstream behaviour, kept).
  Only a native UTF-8 game is affected (it then breaks lines with the
  shared stage); an ASCII game is not, and its text is unchanged.

### AGS hi-res text at N× (`[hires] scale=`, C23)

Full design and results: `AGS_HIRES_TEXT_DESIGN.md` (card C23, merged
`0e3148bd89`).

- **`[hires] scale=` (map) or `hires_text_scale` (ini), 1-3, default 1.**
  N=1 is today's behaviour exactly, byte-identical, at no measurable cost.
  N≥2 shows the display at N× the game's native size (AGS's own render-frame
  scaling; the mouse is unscaled by existing code) and draws the map's
  mapped text - speech, `Display()` boxes, text overlays, GUI
  labels/buttons/list boxes/text boxes, and the built-in dialog options -
  at N× from the same faces, with real alpha. A game whose text is not
  mapped, or whose map names no `scale=`, is unaffected.
- **Needs a mapped font, a 16- or 32-bit game, and a 32-bit screen format**;
  otherwise one warning ("hires text scale N needs a mapped font ...;
  using 1") and N stays 1. 8-bit games always stay at N=1.
- **Everything at game resolution is unchanged**: line breaks, box sizes,
  pen positions, and every pixel a script, plugin, screenshot or save game
  reads. The N× pass redraws the same strings at N× the game-resolution pen
  positions; layout itself never runs at N×.
- **What stays native (upscaled), in v1:** script-drawn text
  (`DrawingSurface.DrawString(Wrapped)`, `RawPrint`), custom dialog-option
  rendering done by the game's own script, stretched or flipped overlays,
  and room-layer overlays (`Overlay.CreateRoomTextual`, cropped by
  walk-behinds). A character the map's faces lack is drawn by the game's
  own font and upscaled, as always.
- **Aspect-ratio correction** (SurfaceSDL and OpenGL) only corrects
  320×200 and 640×400 *output* sizes (plus the EGA/Hercules sizes). A
  320×200 game keeps 4:3 correction at N=2 (640×400) but loses it at N=3
  (960×600); a 640×400 game loses correction at N=2 (1280×800) already.
  Games at other native sizes (320×240, 640×480, ...) are not affected by
  `scale=` either way. Prefer N=2 over N=3 for a 320×200 game when
  `aspect_ratio` is on.
- N≥2 is allowed for 640-wide games; 2× gives a 1280-wide window.
- **OpenGL at N≥2 is now measured (C30) and matches SurfaceSDL.** On Mesa
  llvmpipe the GL screen presents as ARGB8888 (no `copySurface` swizzle),
  frame times at N=1..3 are in the same range as SurfaceSDL, and native
  frames, invariant 3 (outside the text rects, the N× frame is the
  upscaled native frame) and the real pointer all matched SurfaceSDL at
  N=1..3. The RGBA/ABGR GL pixel-format path remains unmeasured.
- **A backend that refuses the N× mode falls back to 1× (C33).** Before
  C33 a refused mode (for example a GPU whose texture-size limit is below
  the requested N× resolution) aborted the game with an error dialog. Since
  C33, `AGSEngine::setGraphicsMode()` tries the N× size and, on a size or
  format refusal, falls back to the native size with one console warning
  ("hires text: the backend refused the WxH display; running at the
  game's WxH (scale 1)") instead of aborting - verified on both
  SurfaceSDL and OpenGL by forcing a refusal. `Present()`'s own
  size-mismatch fallback (§G above) is unchanged and still covers a later,
  mid-game mode change.
- **Debug commands** (see `DEBUG_SOCKET.md`): `ags_dump_native`,
  `ags_render_text`, `ags_hires_rects`, `ags_frame_times`, `ags_call`.

### `[glyphs]` ranges

A range remaps or keeps many codes in one line, instead of one `[glyphs]`
entry per code:

```ini
[glyphs]
; ASCII to the fullwidth forms block, all at once
0x21-0x7E=+0xFEE0
; the caret in that range stays the game's own ellipsis
0x5e=keep
; a whole block left to the game's font
0x80-0x9F=keep
; a single code, offset form - same as 0x41=0x61
0x41=+0x20
```

- The key is `<code>-<code>`: each half is hex `0x..` or decimal (never
  `u+` - a range key can only ever be a plain code range, since
  `Common::INIFile` rejects a `u+` key, and the whole map with it, exactly
  as a single `u+`-keyed entry already does).
- The value is `keep` (leave the whole range untouched) or `+<n>` (remap
  every code in the range by the same offset; `n` is `0x..` or decimal,
  never `u+` - an offset is a distance, not a code point).
- `+<n>` also works on a single code: `0x41=+0x20` is the same as
  `0x41=0x61`.
- **Bounds**, each one warns and ignores just that one entry: a range must
  not end before it starts (`end < start`); its end must not exceed
  `0xFFFF`, since game codes are at most double-byte (a single code's
  target keeps its own `U+10FFFF` cap); `end + offset` must not exceed
  `U+10FFFF`; a malformed half (`0x21-`, `-0x7E`, `0x21-0x7E-0x80`,
  `0xzz-0x7E`) is rejected the same way. A range cannot take an absolute
  (`u+`) target - `0x21-0x7E=u+FF01` is refused, because it would draw 94
  different codes as one glyph.
- **Table limit:** ranges may add at most 131072 codes per map load,
  counted over the common table and every scope together (two full
  `0x0000-0xFFFF` ranges' worth). A range that would cross the limit is
  ignored whole, with one warning; ranges earlier in the file still apply.
  Single-code entries never count against this limit.
- **Precedence**, most specific wins:
  1. **Across sections, unchanged:** a qualified section (`[glyphs:cs1]`)
     beats the bare `[glyphs]` section for the codes it names, whether the
     entry is a range or a single code.
  2. **Within one section, a single code always beats a range that covers
     it, whatever order the lines are written in** - that is how
     `0x5e=keep` above punches a hole in the `0x21-0x7E` range next to it,
     even though it comes after it.
  3. **Between two ranges in the same section, the later line wins** for
     the codes they share.
  4. Overlaps never warn: a hole punched in a range and a narrower range
     layered over a wider one are both intended uses.

The exact warning text for each bound and for the table limit is in
"Warnings to expect" below.

### The ini keys, and what they override

| ini key | Overrides |
|---|---|
| `hires_text_font` | The face path, for every font id. On **SCI and SCUMM** it beats `[font.N] face=` too, not only `[fonts] default`/`[hires] font=`. On **AGS** it does not: `[font.N] bitmap=` and `[font.N] face=` win over it, and it wins over `[hires] face=` and `[fonts] default=` (see "AGS (C11 T8)"). On AGS the key alone (no map file) also turns the map-font renderer on, and with it the shared line breaking of UTF-8 text |
| `hires_text_font_size` | The size, for every font id (8..64) |
| `hires_text_latin` | The Latin mode (`off`/`half`/`fullwidth`/`proportional`), for every font id |
| `hires_text_latin_font` | The Latin-range face, for every font id |
| `hires_text_latin_space` | The space handling (`keep`/`fullwidth`), for every font id |
| `hires_text_metrics` | The metrics source (`game`/`font`), for every font id |
| `hires_text_map` | Which map file is read, instead of `hires_text.map` |
| `hires_text_scale` | **AGS only (C23).** The display/text scale N (1-3), overriding `[hires] scale=`; see "AGS hi-res text at N× (`[hires] scale=`, C23)" above |
| `hires_text_log` | Diagnostic: logs each line drawn and which face drew each glyph (used to build the font-id table above) |

These are meant for a player overriding a translation's choices (or for
testing), not for the translation itself - a map is the only way to give
different font ids different settings.

#### Display key: `hw_screen_32bpp`

| ini key | Effect |
|---|---|
| `hw_screen_32bpp` | `true`: ScummVM's *SDL Surface* graphics mode (`--gfx-mode=surfacesdl`, SDL2 or SDL3) presents through a 32-bit screen for every game, instead of a 16-bit RGB565 one. Default `false` |

This key is not a map override and is not SCI-specific. It belongs to the
display backend and can go in a game's section or in `[scummvm]`. You
usually do not need it. A game that asks for 32-bit colour already gets the
32-bit screen. That includes Korean/Japanese SCI with `rgb_rendering`, SCUMM
with `hires_text_alpha` and 32-bit AGS games. Set it when a 16-bit or
paletted game should skip the 5/6/5-bit rounding, e.g. for colour-exact
screenshots or frame dumps. Its visible effect is small: palette colours
are up to 7/255 per channel more accurate. The OpenGL graphics mode (the
default on most desktops) is always 32-bit and ignores the key. Details:
`HIRES_COMPOSITOR_DESIGN.md` §5.4.

## Modes, with pictures

All five captures below are the same KQ1-ko dialogue box and status line
(`02d_unknown`), with only the Latin mode changed, at 2x.

![All five Latin modes, KQ1-ko font 300 dialogue box](img/hires_text_map/latin_modes.png)
![All five Latin modes, KQ1-ko font 0 status line](img/hires_text_map/latin_modes_status.png)

- **`off`** - the game's own bitmap font draws the Latin text (`xyzzy`),
  exactly as today. Default when a font id has no map entry at all.
- **`half`** - ASCII is routed to the replacement TrueType face, at that
  face's own narrow advance, same as the CJK glyphs' "half-width" role.
  Layout is unaffected because CJK games' own Latin glyphs are already
  narrow.
- **`fullwidth`** - ASCII is remapped to the Unicode fullwidth-forms block
  and drawn at the same (wide) cell CJK characters use, so a run of Latin
  text lines up with the surrounding Hangul/Kanji/Hanja - "xyzzy" becomes
  "ｘｙｚｚｙ". `space=fullwidth` also remaps the space character to the
  wide ideographic space (U+3000); `space=keep` (the default) leaves
  spaces at their normal width, which is why the boxes above show narrow
  gaps between fullwidth letters.
- **`proportional`, `metrics=game`** - ASCII is routed to the TrueType
  face (as `half` is), but each character advances by the *game font's
  own* width for that character, not the TrueType face's. Line breaks and
  box sizes come out pixel-identical to `off` - this is the mode to reach
  for when the map should change only how glyphs look, never where they
  fall.
- **`proportional`, `metrics=font`** - the same routing, but each
  character advances by the TrueType face's own (rounded-to-game-pixel)
  width. Layout now follows the replacement face, which usually means
  narrower text and smaller boxes than the original - see "Known limits"
  below for what that looks like in practice.

The per-font-id map from the worked example above draws font 300
(dialogue) fullwidth and font 0 (status line) half **in the same run**,
each font id answering independently:

![Dialogue box (font 300), fullwidth](img/hires_text_map/perfont-dialogue_crop.png)
![Status line (font 0), half](img/hires_text_map/perfont-status_crop.png)

## Known limits

- **No `space=` choice for proportional mode yet.** Proportional routes
  `U+0020` to the replacement face just as `half` does, so its advance -
  not the game font's space width - is what widens or narrows every gap.
  A future `space=` option (e.g. "keep the game's own space width" even
  in proportional mode) is not implemented.
- **`metrics=game` with a wide game cell and a narrow replacement face
  can look letter-spaced.** The replacement glyph is drawn small inside
  an advance box sized for the original (often wider) game glyph, so text
  like "x y z z y" can look loosely spaced even though the layout itself
  is byte-identical to `off`. This is inherent to asking for unchanged
  layout with new glyphs - a narrower map face will always sit more
  loosely in the original's cells.
- **`metrics=font` with a very narrow replacement face can look
  cramped.** With AppleGothic (used for the captures above), the space
  advance is only about 2 game pixels, so consecutive words can nearly
  close up. Because layout now follows the map face, *every* box's width
  changes from the original - not just the ones with long Latin runs -
  since even all-Korean lines contain ASCII spaces that now advance
  differently.
- **Per-glyph kerning or centring in proportional mode is not
  implemented.** Each glyph is placed at its own advance's origin, with
  the face's own bearing kept (so overhang into the next glyph's box is
  possible, as the face intends) - there is no additional centring or
  kerning pass.

## Warnings to expect

Two components emit warnings, with different prefixes. Every one is
"warn once and use the default" - a bad map or a bad ini value never
blanks the screen or aborts the game.

**The SCI adapter and cache** (`engines/sci/graphics/cache.cpp`), no
`HiResText:` prefix - these are about ini keys, scope, and face files:

- `hires_text_font is ignored: <why>` / `hires_text_latin is ignored:
  hires_text_font is not in effect` / `hires_text.map is ignored: <why>` -
  the game is out of scope (SCI32, or not a CJK code page). `<why>` is
  `SCI32 games do not support it yet` or `the game's language has no
  hi-res CJK text`.
- `hires_text_latin is ignored: hires_text_font is not in effect` - also
  in scope, once per run: one of the ini keys `hires_text_latin`,
  `hires_text_latin_font`, `hires_text_latin_space` or
  `hires_text_metrics` (even `hires_text_metrics` alone) is set, and a
  font id ends up with no live TrueType face (none named by the ini key or
  the map, or the one named failed to open). When that font id's Latin
  mode comes from the map rather than from `hires_text_latin`, the
  `hires_text.map: font <id> has a Latin mode ...` warning below is given
  for it instead.
- `hires_text_map: empty path; no map is used` - `hires_text_map=` was
  set to an empty value.
- `hires_text.map <path>: <error>; ignoring it` - `<error>` is one of
  `does not exist`, `is a directory`, `could not open the file`, or
  `is not a valid map`. `is not a valid map` follows the INI reader's own
  warning (`common/formats/ini-file.cpp`), which names the line:
  `INIFile::loadFromStream: missing ] in line <n>`,
  `INIFile::loadFromStream: Invalid character '<c>' occurred in section
  name in line <n>`, `Invalid section name: <name>`,
  `INIFile::loadFromStream: Key/value pair found outside a section in line
  <n>` or `Invalid key name: <key>`. A line with no `=` gets `Config file
  buggy: Junk found in line <n>: '<line>'` and is skipped; it does not
  reject the map.
- `hires_text_font: empty path; using the .uni fonts` /
  `hires_text_latin_font: empty path; the main face draws Latin text` -
  the corresponding ini key was set to an empty value.
- `hires_text_font_size '<value>' is not a number from 8 to 64; ignoring
  it`
- `hires_text_latin '<value>' is not off, half, fullwidth or
  proportional; using off`
- `hires_text_latin_space '<value>' is not keep or fullwidth; using keep`
- `hires_text_metrics '<value>' is not game or font; ignoring it`
- `hires_text_font <path>: <error>; using <fallback>` /
  `hires_text_latin_font <path>: <error>; <fallback>` - a named face
  file (from the ini key, `[hires]`, or a `[font.N] face=`/`latin_font=`)
  could not be opened. `<error>` is `empty path`, `does not exist`, `is a
  directory` or `could not open the file`; `<fallback>` names the next
  face tried (the global face, then the `.uni` fonts) or, for a Latin
  face, says the main face draws that text instead. Nothing goes blank -
  the font id falls back, it is never skipped.
- `hires_text.map: font <id> has a Latin mode but no TrueType face; the
  game's font draws its Latin text` - a font id asked for a Latin mode
  but has no live TrueType face at all (its own face failed and there is
  no fallback either).
- `hires_text.map: [latin] bitmap= is SCUMM-only, ignored` - the legacy
  SCUMM key `[latin] bitmap=` was set; SCI has no bitmap Latin path.

**The shared map parser** (`graphics/hires_text/font_map.cpp`), prefixed
`HiResText:` - these are about the map's own INI syntax, shared with
SCUMM:

- `HiResText: [<section>] does not name a font id, ignoring it` - a
  `[font.<something not a number>]` section.
- `HiResText: [<section>] is not written as [font.N] or
  [font.N:<platform>], ignoring it` - e.g. `[font.04]` or `[font.4:]`
  (an empty qualifier after the colon).
- `HiResText: [<section>] has no key '<key>', ignoring it` - an unknown
  key inside a `[font.N]` section (a typo, usually).
- `HiResText: [<section>] invalid size '<value>', ignoring`
- `HiResText: [<section>] latin '<value>' is not off, half, fullwidth or
  proportional, ignoring`
- `HiResText: [<section>] latin_space '<value>' is not keep or
  fullwidth, ignoring`
- `HiResText: [<section>] metrics '<value>' is not game or font,
  ignoring`
- `HiResText: invalid [hires] size '<value>', ignoring`
- `HiResText: [latin] mode '<value>' is not off, half, fullwidth or
  proportional, ignoring`
- `HiResText: [latin] space '<value>' is not keep or fullwidth, ignoring`
- `HiResText: invalid legacy enabled '<value>', ignoring` - `[latin]
  enabled=` is not `true`, `false` or a number.
- `HiResText: unknown legacy metrics '<value>', ignoring` - `[latin]
  metrics=` is not `game`, `font`, `ttf` or `bitmap`.

`[glyphs]` range keys (`<code>-<code>`), same prefix, same "warn once and
use the default" rule - the whole entry is ignored, the rest of the map
still loads:

- `HiResText: glyph range '<key>' is not <code>-<code>, ignoring`
- `HiResText: glyph range '<key>' ends before it starts, ignoring`
- `HiResText: glyph range '<key>' goes past 0xFFFF, ignoring`
- `HiResText: glyph range <key>: '<value>' is neither 'keep' nor
  '+<offset>', ignoring`
- `HiResText: glyph <key>: '<value>' goes past U+10FFFF, ignoring` - a
  range's end (plus its offset), or a single code's `+<offset>` target
- `HiResText: glyph range '<key>' would take the map past 131072 range
  codes, ignoring`

Each of these gives exactly one warning per offending key or section (not
one per line drawn), and the affected setting falls back to whatever the
next step in the precedence chain says - never to a blank screen.
