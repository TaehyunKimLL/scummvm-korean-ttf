# GUI: hi-res on/off and alpha on/off

The proposal: two checkboxes in the game options tab — hi-res text, and font
alpha blending — and consult the map only when hi-res is on.

Measured before designing, because the earlier survey in
`GUI_OPTIONS_DESIGN.md` was written at `ef95aaca144` and the code has moved
since.

## What already exists

**The hi-res checkbox is implemented.** `metaengine.cpp` carries

```cpp
static const ExtraGuiOption enableHiResText = {
    _s("Hi-res text"),
    _s("Draw text with the larger fonts a translation ships in the game "
       "folder (hires_text.map). Has no effect when there are none."),
    "hires_text", true, 0, 0 };
```

gated by `targetHasHiResText(target)`, which returns true when
`hires_text_map` or `hires_text_font` is configured, or when the game folder
holds `hires_text.map`, `hires.fnt`, or `hires00..02.fnt`. Every other game's
dialog is untouched.

So one of the three asks is done. The other two are not.

## What the switch costs today

Run with `hires_text=false`, English MI2, a map and eight baked fonts in the
folder:

```
=== hires_text on ===
  hi-res map read: '.../hires_text.map' (found in the game folder)
  hi-res text enabled: scale 2, alpha on, metrics font
  hi-res Latin font 0 <- hrlat00.fnt: 16x16 cell, 8 bpp, 256 glyphs
  ... 8 fonts loaded

=== hires_text off ===
  hi-res map read: '.../hires_text.map' (found in the game folder)
  hi-res text switched off by the user (hires_text=false)
```

**The map is parsed either way; the fonts are not loaded.** So the waste is
one ini parse, not eight font loads — the ordering question is about clarity,
not speed, and any commit should say so rather than claim a performance win.

The order in `loadConfig` is:

    hires_text_map / korean_ttf_map   -> resolve the path
    HiResFontMap::load                -> parse it
    probeSimpleFonts                  -> the map-less form
    hires_text_font                   -> a TrueType face
    _enabled = ...                    -> decide
    hires_text=false                  -> undo the decision

## Proposal

### 1. Check the switch first

Move the `hires_text=false` test to the top of `loadConfig` and return. The
map, the font probe and the face resolution then do not happen at all.

The reason to do this is not the ini parse. It is that a disabled feature
which still reads files can still produce warnings — `names no [bitmap]
fonts`, `is not a usable hi-res font`, the format-string diagnostics — about
a configuration the user has switched off. A player who turns the feature off
to stop it complaining should stop hearing from it.

Risk: `ConfMan.hasKey("hires_text")` is read before anything else initialises
it. It is a plain ini key with a default registered by
`registerDefaultSettings`, so it is available at that point — but the commit
should be measured, not assumed.

### 2. An alpha checkbox

```cpp
static const ExtraGuiOption enableHiResAlpha = {
    _s("Antialias hi-res text"),
    _s("Blend the larger fonts into the picture. Turn this off for the "
       "sharper, original look, or if the text looks wrong on this game."),
    "hires_text_alpha", true, 0, 0 };
```

exposed under the same `targetHasHiResText(target)` condition.

`hires_text_alpha` already exists as an ini key and already outranks the map,
so this is a checkbox over machinery that works — no engine change beyond
registering the option.

Two things to get right:

- **The default must follow the map, not the checkbox.** A translation that
  ships 8bpp fonts asks for alpha; one that ships 1bpp does not. An
  `ExtraGuiOption` has a single compiled-in default, and if that default is
  written to the ini on first run it overrides what the map asked for. The
  existing `hires_text` option has the same shape and gets away with it
  because `true` is also what the map path wants; alpha does not have that
  luxury.

  The honest form is a three-state setting — follow the map, force on, force
  off — which `ExtraGuiOption` cannot express. Either use a custom widget
  (see below) or leave alpha to the ini.

- **Alpha off is not free on FM-Towns.** That platform's blending path is
  what makes its text layer 16-bit; with alpha off it returns to the keyed
  path. That is the original behaviour and correct, but it means the checkbox
  changes more than antialiasing there, and the tooltip should not promise
  "just sharper".

### 3. What blocks a fuller dialog

`buildEngineOptionsWidget` dispatches on gameid, and a custom widget
**replaces** the `ExtraGuiOption` list rather than adding to it:

| game | widget |
|---|---|
| Loom VGA / EGA | `LoomVgaGameOptionsWidget` / `LoomEgaGameOptionsWidget` |
| MI1 CD / Towns / Sega | `MI1CdGameOptionsWidget` |
| Mac editions | `MacGameOptionsWidget` |
| everything else | `ScummGameOptionsWidget` |

So a checkbox added to the list does not appear for Loom or MI1 CD — both in
the Korean test set. A scale popup or a three-state alpha control needs a
shared helper called from all five widgets, plus theme layout changes in
`gui/themes/*.stx`.

That is a much larger change than the two checkboxes, and it is why alpha as
a plain `ExtraGuiOption` is worth doing only if the map-default problem above
is acceptable.

## Order

1. Move the switch to the top of `loadConfig`. Small, independently
   verifiable: turning the feature off should produce no hi-res log lines at
   all, where today it produces one.
2. Decide alpha's default semantics before adding the checkbox. If
   "follow the map" is required, it needs a custom widget and belongs after.
