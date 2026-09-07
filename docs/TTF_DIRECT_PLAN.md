# Using a TrueType face directly

Status: **designed, not built.** The measurement behind it is in
`~/games/ttf_paths.py`; the numbers below are from that run.

## What works today, measured

Four ways of reaching a TrueType face, English MI2, same scene, colour count
in the subtitle band (4 = the original bitmap font, more = hi-res text):

| configuration | colours | hi-res on | glyphs baked |
|---|---|---|---|
| map with `[bitmap]` naming baked `.fnt` files | **129** | yes | n/a |
| map with `[fonts] default=<ttf>` | 4 | yes | **none** |
| `hires_text_font=<ttf>`, no map | 4 | yes | **none** |
| `hires_text_font=<ttf>` + map with `[shadow]` | 4 | yes | **none** |

Every TTF route fails the same way, and logs the same line:

    WARNING: SCUMM: hi-res TrueType font: no glyph set for this language

## The cause is one gate, not the four suspected

An earlier reading of this code in the same session concluded that a map
without a `[bitmap]` section is rejected outright, and that this was the
obstacle. **That was wrong.** The check warns and leaves the map loaded - the
working `[bitmap]` configuration above emits the very same warning and draws
fine.

The single blocker is the codepage switch in `ScummHiResText::bakeTtfFonts`:

```cpp
switch (_config.encoding) {
case Common::kWindows949:  hangulSyllables(cjk);      break;
case Common::kWindows932:  jisX0208(cjk);             break;
case Common::kWindows936:  chineseCodePage(936, cjk); break;
case Common::kWindows950:  chineseCodePage(950, cjk); break;
default:
    warning("...no glyph set for this language");
    return false;          // <- here
}

Common::Array<uint32> latin;
HiResFontBaker::latin1(latin);   // <- one line later, unconditionally
```

The function gives up on a non-CJK game one statement before it would have
built the Latin set that such a game needs. `latin1()` already exists and is
already called for every CJK game, because a Korean game still has to draw
ASCII. Nothing needs writing - the early return needs removing.

## Status

Steps 1 and 2 are **done** (`75e40c2681e`). Measured after:

| configuration | colours before | colours after | bakes |
|---|---|---|---|
| map with `[bitmap]` (baked `.fnt`) | 129 | 129 | n/a |
| map with `[fonts] default=<ttf>` | 4 | **104** | 1 |
| `hires_text_font=<ttf>`, no map | 4 | **104** | 1 |
| `hires_text_font=` + map with `[shadow]` | 4 | **104** | 1 |

The bake went from twenty rasterisations at a guessed 16x16 to one at the
measured 28x28, and a screenshot confirms the text is legible rather than
merely present.

### One defect, and one false alarm

**The letter spacing is too wide.** The advance still comes from the game's
own proportional metrics while the glyphs are now a TrueType face, so the two
disagree. `[render] metrics=font` exists for exactly this and is worth
measuring against.

**`[shadow]` was reported as not reaching the TTF path. That was wrong** - it
does reach it. The claim came from looking at a screenshot, which is the
mistake this project keeps making. Counting black pixels within 2px of the
red text ink settles it:

| configuration | text ink | outline ink |
|---|---|---|
| map with `[bitmap]`, `[shadow] mode=outline` | 669 | 1185 |
| `hires_text_font=` + map with `[shadow]` | 965 | **1026** |
| `hires_text_font=`, no map (so no `[shadow]`) | 965 | **0** |

A TTF face with a map decorates exactly as a baked font does; a face without
a map has nowhere to ask for a decoration, which is the real gap and is what
the defaults below address.

## Design

### The gate becomes a fallback

`bakeTtfFonts` keeps its CJK sets and stops treating their absence as
failure: a game whose codepage names no CJK set bakes the Latin set alone.
That is the whole change to make a TTF work for a European game.

### Bake against the game's own font, not a guess

Making the above work exposed the real structural problem. The bake happens
in `ScummEngine::setupScumm`, and the cell it bakes at comes from
`_2byteWidth`/`_2byteHeight` - the CJK font's metrics. A European game has no
CJK font, so there is nothing to measure, and the first attempt here supplied
a compiled-in 8x8.

Measured, that guess is wrong:

| game | charset the game selects | real cell | 8x8 guess bakes at |
|---|---|---|---|
| MI2 English | 7 | **14px** | 16px |
| MI2 Korean | 7 | **14px** | 16px |

and wrong in a second way: the loop bakes all twenty charset slots, so a run
that uses one charset rasterises the same face **twenty times**. The log
shows `20 fonts baked`, every one at `16x16`.

Both follow from the same cause - the bake runs before the game's fonts are
known. `_charset` is constructed further down in `setupScumm`, and the
charset resources are read later still, so at bake time the engine genuinely
cannot answer "how tall is charset 7".

So the fix is ordering, not arithmetic: **read the game's own charset first,
and bake to fit it.** The engine already has the hook - `setCurID` is where a
charset's `_fontHeight` becomes known, and it is also the moment the layer
learns a charset is about to be used. Baking there means:

- the cell is the game's real cell, whatever it is
- only charsets the game actually selects get baked
- a game that never selects charset 3 never pays for it

The cost of on-demand is a rasterising pause the first time a charset
appears. The Latin set is ~190 glyphs (`0x20`-`0x7E`, `0xA0`-`0xFF`), so this
is small - and it replaces twenty full bakes at start-up, not adds to them.

For CJK the calculus differs: those sets are thousands of glyphs, and a pause
mid-scene would be visible. Those keep their current start-up bake, which is
already correctly sized because `_2byteHeight` is known that early.

    Latin, ~190 glyphs   -> bake on first use of each charset, at its cell
    CJK, thousands       -> bake at start-up, as today

### Defaults move into the code

A face on its own currently implies `scale = 2, alpha = true`, decided at the
point where the config key is read. That is the right default and the wrong
place: it applies only when no map was found, so adding a map to set
`[shadow]` silently drops it - the third and fourth rows above differ in
exactly that way.

Defaults belong in one struct, applied before any source is consulted:

```cpp
struct HiResDefaults {
    int  scale       = 2;
    bool alpha       = true;
    HiResShadowMode shadow = kHiResShadowOutline;
    int  shadowOffset = 2;
    int  shadowColor  = 0;      // see the platform note below
};
```

with three sources layered over them, each overriding the last:

1. **compiled-in** — the struct above
2. **the map** — only keys the map actually names
3. **ConfMan** — only keys the user actually set

The layering has to be per key, not per source. Today `[shadow]` and
`hires_text_font` cannot be combined because the map and the config key are
treated as alternatives; per-key layering makes that combination the ordinary
case.

### Per-game defaults

Two games need different values, both already known:

- **FM-Towns**: the transparent index is 0, so an outline in colour 0 is
  invisible and colour 4 is the text colour, which the renderer skips. The
  default there is 8, measured earlier this session.
- **Indy 3 and Loom on Mac**: the text plane is a stencil, so a decoration
  drawn into it would mark the box present in the wrong places.

These are platform facts, not user preferences, so they belong beside the
platform code rather than in every map a translator writes.

## What this does not solve

A TTF has no pictograms. MI2's skull, DOTT's arrows and similar live in the
game's own charset, and `[glyphs]` exists to keep them. A TTF-only
configuration still needs the game font for those codes, which is why the
glyph-keeping machinery stays even when no `[bitmap]` font is named.

## Order of work

1. Remove the early return; bake Latin when no CJK set matches. One line, and
   the measurement above turns from 4 colours into a number like 129.
2. Introduce `HiResDefaults` and layer the three sources per key.
3. Move the FM-Towns and Mac values into platform defaults.
4. Document the resulting precedence in `HIRES_TEXT.md`.

Each step is separately measurable with `ttf_paths.py`, which prints the
colour count for all four configurations in one run.
