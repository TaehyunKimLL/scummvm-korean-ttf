# `hires_text.map`: a translator's and font-pack author's guide

This is the file a Korean/Japanese/Chinese SCI translation or a hi-res
font pack ships to control how ScummVM's SCI engine draws replacement
(TrueType) text over a game's own bitmap fonts. It is read by SCI16 games
in a CJK code page only (Windows 949/932/936/950), below SCI2 - the same
scope as the `hires_text_font` ini key. On any other game the map is
ignored, with one warning.

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
not supported** - `color=0 ; DOS` keeps the `; DOS` as part of the value
and fails to parse. Put comments on their own line instead, above the key
they describe, as every example on this page does.

**Relative paths in the map are the map's own.** A `[fonts]` entry, or a
path written in place of a face name (`face=`, `latin_font=`, ...), that
is not absolute is taken against the directory holding the map file. For
the game directory's own `hires_text.map` that is the game directory; for
a map named by `hires_text_map=` elsewhere, fonts can sit beside that map.
The ini keys `hires_text_font` and `hires_text_latin_font` are not map
paths: they are used exactly as given, as they always were.

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
   game, no separate Latin face (the main face draws everything).

So a map that names nothing for a font id reproduces today's behaviour
for it exactly - the map only ever adds settings, never a game-wide
override; an ini key is the only thing that can override every font id at
once.

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
| `[fonts]` | *name*`=`*file* | Face name -> file, referenced by `font=`/`face=`/`latin_font=`/`latin_face=` elsewhere. Case-insensitive names; relative paths are taken against the directory holding the map |
| `[latin]` | `mode=` | `off` \| `half` \| `fullwidth` \| `proportional` - the default for every font id |
| `[latin]` | `font=` (or `face=`) | Face for the Latin range; absent means the font's own face draws it |
| `[latin]` | `space=` | `keep` \| `fullwidth` (fullwidth mode only) |
| `[latin]` | `metrics=` | `game` \| `font` (proportional mode only) |
| `[font.N]` | `face=` (or `font=`) | Face for this font id |
| `[font.N]` | `size=` | Pixel size for this font id |
| `[font.N]` | `latin=` | Overrides `[latin] mode=` for this font id |
| `[font.N]` | `latin_font=` (or `latin_face=`) | Overrides `[latin] font=` for this font id |
| `[font.N]` | `latin_space=` | Overrides `[latin] space=` for this font id |
| `[font.N]` | `metrics=` | Overrides `[latin] metrics=` for this font id |

`[font.N]` must be written exactly that way - a numeric id, `[font.4]`,
optionally `[font.4:pc98]`. `[font.04]` or `[font.4:]` (an empty
qualifier) are rejected with a warning, not silently treated as `[font.4]`.

**Not yet implemented**, though a map that already has them for SCUMM
will not warn: `[shadow]`, `[glyphs]` remap ranges, `baseline=`, and
`[hires] scale=` beyond what the compositor already fixes. Per-glyph
kerning/centring in proportional mode and the legacy SJIS face are also
not implemented yet.

### The ini keys, and what they override

| ini key | Overrides |
|---|---|
| `hires_text_font` | The face path, for every font id (beats `[font.N] face=` too, not only `[fonts] default`/`[hires] font=`) |
| `hires_text_font_size` | The size, for every font id (8..64) |
| `hires_text_latin` | The Latin mode (`off`/`half`/`fullwidth`/`proportional`), for every font id |
| `hires_text_latin_font` | The Latin-range face, for every font id |
| `hires_text_latin_space` | The space handling (`keep`/`fullwidth`), for every font id |
| `hires_text_metrics` | The metrics source (`game`/`font`), for every font id |
| `hires_text_map` | Which map file is read, instead of `hires_text.map` |
| `hires_text_log` | Diagnostic: logs each line drawn and which face drew each glyph (used to build the font-id table above) |

These are meant for a player overriding a translation's choices (or for
testing), not for the translation itself - a map is the only way to give
different font ids different settings.

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

Each of these gives exactly one warning per offending key or section (not
one per line drawn), and the affected setting falls back to whatever the
next step in the precedence chain says - never to a blank screen.
