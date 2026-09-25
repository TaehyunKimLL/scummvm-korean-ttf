# Hi-res text over low-res graphics: the compositor

Status: **design, approved section by section on 2026-09-26. Not built.**
Written against `i18n` at `40fe861924`. It supersedes the re-apply
mechanism in `TEXT_PLANE.md` and resolves the SJIS items in
`PC98_TOWNS_TEXT.md` §5–6.

`[source]` = read in code (file:line at `40fe861924`). `[measured]` = observed
by running something. `[unmeasured]` = a claim this document has not yet
earned.

## Goal

A retina-like screen for SCI games. The low-res 8-bit paletted graphics are
integer-scaled 2× or 3× with no smoothing, and text is drawn at the scaled
resolution from a TrueType face with real alpha (anti-aliasing and
outlines). The final frame is 32-bit. Text is part of the picture: it goes
away exactly when the original game would have removed it, and at no
other time.

Success is:

- the same text path for UTF-8, cp949 and Shift-JIS games;
- a TTF face usable on any build, with pre-baked glyphs where FreeType is
  missing;
- an untranslated game, or any game with the option off, byte-identical
  to today.

## Decisions, and who made them

| # | Decision | Chosen | Rejected, and why |
|---|---|---|---|
| D1 | Who composites | **The engine first (B), a backend fast path later (C)** | Backend-only (A): only the OpenGL manager alpha-blends its overlay over the game (`opengl-graphics.cpp:817-852`). SurfaceSDL shows the overlay *instead of* the game (`surfacesdl-graphics.cpp:1293`), the overlay also holds the GUI, and it sits at window size, not on the game rect. |
| D2 | The final frame | **Derived and never written directly.** It is recomposed from two source layers for every dirty rect | Writing text into the final frame: the next graphics update of that rect erases it, and with alpha, re-applying text blends it over pixels that are already blended. |
| D3 | What the text layer *is* | **A hi-res extension of the visual plane.** Every visual-plane operation is applied to it | An always-on-top plane (PC-98 text VRAM): wrong for overlapping windows, where a lower window's text would show through the upper one. The exception is PQ2 PC-98, whose original did use text VRAM. |
| D4 | Text colour storage | **Coverage plus palette index**, resolved to a colour when composited, so fades apply to text | ARGB32 storage: text would not fade with the palette. Deferred until a multi-colour glyph needs it. |
| D5 | Font source | **TTF baked at load time via FreeType, with pre-baked coverage glyphs as the fallback** | Pre-baked only: a user could not simply drop in a TTF. |
| D6 | Layout | **In low-res units.** Widths reported to scripts and line breaks are integers at game resolution; glyphs are placed at hi-res precision within that box | Hi-res-native layout: the width reported to the script and the width drawn can disagree (the S7/S9 class of defect). Per-game proportional layout is a later option. |
| D7 | Configuration | **Player preferences in the ini and GUI; facts about the data in `hires_text.map`**, the same file name and format as SCUMM | A separate SCI file name: that would give translators two formats to learn. |
| D8 | Fullwidth Latin | **A `[glyphs]` range remap**, with `[latin] map=fullwidth` as shorthand | Needed for games whose font is 8×8. Fullwidth forms keep Latin legible at the CJK cell size. |

## 1. Components and ownership

```
GfxScreen (engine, game resolution)
 ├─ visual plane     CLUT8 320×200                          unchanged
 ├─ TextLayer        4 bytes/px at N× (below)               new; replaces _hiresTextPlane
 │    mirrors every visual-plane operation (§3); mode kFollowsVisual (default) | kTextVram (PQ2 PC-98)
 └─ dirty rects      as today, through displayRect() → driver

HiResCompositor (driver side, output resolution)            split out of UpscaledGfxDriver
 ├─ inputs: the N× scaled visual (_scaledBitmap), TextLayer, the driver's internal palette (+ palMods)
 ├─ compose(rect): colour-convert the scaled visual, blend the text layer over it
 └─ Sink ─ B: TrueColorSink → a 32bpp (or 16bpp) frame to OSystem   (default, every backend)
         └ C: LayerSink     → both layers to a backend that composites  (later)

GlyphSource (writes glyphs into TextLayer)
 ├─ TtfGlyphSource    FreeType; bakes the needed ranges at N× on load and caches them
 └─ BakedGlyphSource  a pre-baked coverage font (SCVMUNI extended with 8-bit coverage and a per-N glyph set)
```

- **Ownership rule.** The layers belong to the game-resolution side
  (`GfxScreen`), and composition and output belong to the driver. Only the
  compositor writes the final frame.
- **TextLayer is engine-free.** It is a plain class with no `g_sci`, unit
  testable like `ScriptStrings`.
- **Scale N** is 2 or 3 and comes from the option (§2). The driver's
  `scale2x` becomes a general N× scaler. The driver already carries
  `_hScaleMult`/`_vScaleMult` `[source]` `upscaled.cpp:35`, but the scaler
  and several `<< 1` paths assume 2.
- **Glyph faces join `GfxFontSet`.** `GfxText16` already hands the font
  layer a Unicode code point whatever the source encoding. `readChar()`
  decodes cp949 or cp932 via `getSciLanguageCodePage()`
  (`text16.cpp:806-815`), and `decodeUtf8Char()` handles UTF-8. So one TTF
  face serves UTF-8, cp949 and Shift-JIS games:

  ```
  option off:  [game font.NNN] [korean.fnt / SJIS.FNT] [.uni]             as today
  option on:   [game font.NNN] [TTF face, N×, coverage] [legacy face]     legacy face only for what the TTF lacks
  ```

- **Every existing double-byte draw becomes a TextLayer write.** That
  covers `putHangulChar`, `putKanjiChar` and the SCVMUNI face. PC-98
  styling (fat glyphs, 8-px alignment, PQ2 text colours) is applied once,
  when writing. Replay is a composite, not a re-render, so the SCI1 PC-98
  `assert(h == 16)` hazard (`PC98_TOWNS_TEXT.md` §5) cannot arise.

## 2. Configuration

Precedence: ini, then map, then built-in defaults. The one exception is
the encoding, which comes from detection (`ADGF_UTF8I18N`, or the language
code page). The map and ini may override it only as an escape hatch.

### 2.1 ini and GUI game options: the player's choices

| Key | GUI | Meaning |
|---|---|---|
| `hires_text` | checkbox **"Oversample Font for I18N"** | Master switch. Off means no map is read, no TTF is baked, and the game is byte-identical to today. |
| `hires_text_scale` | 2× / 3× | N. CJK defaults to 2. |
| `hires_text_alpha` | "Smooth text" | Coverage blending, or hard edges (coverage thresholded to 0/1). |
| `hires_text_font` | path | A player-chosen TTF; overrides the map's `default` face. |
| `hires_text_map` | — | A map other than `hires_text.map` in the game folder. |
| `hires_text_log` | — | Diagnostic: log each line drawn and which face drew each glyph. |

The option is offered only where it can work. `customizeGuiOptions()`
already scans the game folder (it does so for Hercules' `HERCMONO.DRV`)
`[source]` `detection_internal.cpp:114-178`. It adds a `GAMEOPTION_*` for
SCI0–SCI1.1 games that have a `hires_text.map`, a `.ttf` or a `.uni`
beside them. SCI32, Mac hi-res and Windows 256-colour KQ6 are excluded.

### 2.2 `hires_text.map`: shipped with a translation or font pack

INI format, same name and shared sections as SCUMM's map
(`engines/scumm/HIRES_TEXT_SETUP.md` on `hires-text`). `[font.N]` and the
`latin_*` keys are SCI-specific.

```ini
[hires]
scale=2                       ; the scale this font pack is built for

[fonts]                       ; face name -> file
default=NanumGothic.ttf
title=NanumMyeongjo.ttf
baked=korean.uni              ; used when the build has no FreeType

[font.4]                      ; per SCI font id: SCI fonts differ in height (KQ1: 8, 9, 12)
face=default
size=16                       ; pixel size at N×
baseline=+1                   ; vertical nudge, in game pixels
advance=cell                  ; cell (the legacy fixed cell) | game | font (later: proportional)
latin_face=default
latin_map=fullwidth

[font.300]
face=title
size=24
latin_map=none

[latin]                       ; single-byte text through a TTF too; default false keeps the invariant
enabled=true
face=default
map=fullwidth                 ; none | fullwidth  (shorthand for the [glyphs] rules below)
advance=game                  ; game | cell | font
size=14
baseline=0

[shadow]                      ; outline or drop shadow; colour is a palette index
mode=outline                  ; none | drop | outline | game
offset=1
color=0

[shadow:pc98]                 ; qualified sections win on their platform, as in SCUMM
color=8

[glyphs]                      ; applied to the code point before a face is chosen
0x21-0x7E=+0xFEE0             ; ASCII ! .. ~  ->  fullwidth ！ .. ～
0x20=0x3000                   ; space -> ideographic space
0x2026=keep                   ; leave this code to the original face
```

- **Remapping happens once, at the code point.** The order is: decode,
  apply `[glyphs]` (and `[latin] map`), then choose a face. This works the
  same for UTF-8, cp949 and SJIS.
- **Fullwidth and advance.**
  - `advance=game` keeps the game font's ASCII width and centres the
    fullwidth glyph in it, so the layout is unchanged.
  - `advance=cell` uses the double-byte cell. It looks like PC-98 text,
    but lines get longer. `kTextSize` reports the new width (D6), so
    windows follow. Coordinates a script hard-codes do not follow, and
    that risk belongs to whoever writes the map.
- **Invariant, relaxed on request only.** "Single-byte text is drawn by the
  game's own font" holds unless `[latin] enabled=true`.
- **One map drives both font sources.** The bake tool reads the same map
  to produce the `baked=` file, so runtime TTF and pre-baked glyphs come
  from one description.
- **Translation data stays out.** `text.NNN` and `sci-<lang>.str` are
  unchanged. The map says only how to draw.

## 3. Data flow

### 3.1 TextLayer pixel

```
byte 0  fg colour index      byte 1  fg coverage
byte 2  outline colour index byte 3  outline coverage
```

The two layers let a translucent fg edge over a translucent outline blend
correctly. Indices address the **driver's internal palette**. That space
already holds the game palette, the palette mods, and PQ2 PC-98's
out-of-palette text-mode colours (0x10+, `pc98_16col.cpp:192-219`), so none
needs a special case.

### 3.2 Composite, per dirty rect

```
dst = palette[scaled visual index]                 // today's _colorConv / _colorConvMod
if row has text:                                   // one bit per row, to skip text-free rows
    dst = lerp(dst, palette[outline index], outline coverage)
    dst = lerp(dst, palette[fg index],      fg coverage)
```

This extends the colour conversion the RGB path already does in
`UpscaledGfxDriver::updateScreen()` `[source]` `upscaled.cpp:168-182`.

### 3.3 Events

| Event | Visual plane | TextLayer | Screen |
|---|---|---|---|
| fill, window background, new picture | written | **cleared** in the rect | on the next show |
| view cel drawn | written | cleared under the cel's opaque pixels | on the next show |
| `bitsSave` (underbits) | saved | **saved with it** (a new mask bit) | — |
| `bitsRestore` | restored | **restored with it**, so text comes back | on the next show |
| text drawn | — | written | on the next show, as in DOS |
| `displayRect` / show | — | untouched | scaled and composited |
| palette change or fade | — | untouched | full recomposite; text fades with it |
| transition (`GfxTransitions`) | — | untouched | its `copyRectToScreen` calls composite, so text transitions with the picture |
| window disposed | restored | restored with its underbits | on the next show |
| restore game | reset | reset (`clearForRestoreGame`) | redrawn |

In `kTextVram` mode (PQ2 PC-98), the first four rows leave the TextLayer
untouched, and text is cleared only by the interpreter's own text clears.

The cursor is the backend's cursor, drawn on top, as in DOS. PQ2 PC-98
drew text over the cursor. That is not reproduced: it would require
drawing the cursor in the engine, and it is recorded as a known difference.

### 3.4 What this removes

These workarounds exist because glyphs lived only in the driver bitmap:

- `_hiresTextPlane` and its re-apply in `displayRect()` (`TEXT_PLANE.md`)
- the `needCJKFix` pre-update (`paint16.cpp:606`)
- the double-byte show-skips in `GfxText16` (upstream's SJIS lines, and the
  one `30eaf5eab3` fixed)

Each is removed in its own commit, with a capture before and after.

### 3.5 Output format and cost

- With the option on, the driver requests RGB output: 32bpp, or 16bpp when
  that is all the backend offers.
- On a CLUT8-only backend, alpha is off and coverage ≥ 50 % stamps the fg
  index, so the composite is still an index.
- At 3×, a frame is 960×600 ×4 bytes ≈ 2.3 MB. Dirty rects keep normal
  frames small. A palette fade recomposites everything every step. Rows
  without text cost exactly today's colour conversion. `[unmeasured]` cost
  on mobile.

## 4. Failure and fallback

The rule: **if the option is on and a prerequisite is missing, fall back
quietly to today's path.** Never a blank screen. Log each cause once.

| Situation | Behaviour |
|---|---|
| Build without FreeType | Use the map's `baked=` font. If there is none, behave as option-off and warn once. |
| TTF missing or unreadable | Fall through, in order: ini `hires_text_font` → map face → baked → legacy DBCS face → game font. One log line per step taken. |
| Glyph missing from the face | The next face in the `GfxFontSet` chain answers. Missing code points are logged once each, by number. |
| Map error | Unknown key or bad value: warn and use the default. The file is never rejected whole. |
| Backend has only CLUT8 | Hard-edged stamp (§3.5). |
| Game or mode unsupported (SCI32, Mac hi-res, Win256 KQ6) | Option not offered. If forced via ini: warn and ignore. |
| Another render mode selected (EGA, CGA, Hercules) | With the option on, the render mode is forced to default. This replaces the `KO_KOR`-only rule at `init.cpp:128`. |
| Option changed mid-game | Takes effect on restart, as a render mode does. The GUI says so. |
| Save and load | The TextLayer is not saved. Restore redraws the screen (as today). `[unmeasured]` whether SCI's save thumbnail comes from the composited frame; verify. |
| Underbits memory | At 3×, 36 bytes per game pixel, about 2.3 MB for a full-screen save. A flag skips storing text for rects that have none. |
| Cursor at 3× | The driver's cursor scaling assumes 2×. Generalise it to N. |

## 5. Verification

**Invariants (option off).**
- KQ1 English glyph sequence 273/273.
- Low-res frame buffer bit-identical to existing captures.
- LB1 cp949 patch unchanged.
- `make test` all pass.

**Unit tests** (engine-free classes):
- **Map parser:** sections, qualified sections, `[font.N]`, `[glyphs]`
  ranges and offsets, `fullwidth`.
- **Composite function:** a pure function of (background index, TextLayer
  pixel, palette) → ARGB, with golden values for translucent fg over
  translucent outline.
- **TextLayer:** fill, cel, save and restore semantics. Text reappears
  after a restore, and a lower window's text is hidden under an upper
  window's fill.

**Harness** (debug socket; waits on game state, never on time):

| Scenario | Check |
|---|---|
| KQ1 intro box, actor walks past | Text pixels in the composited frame hold over 60 frames (the 2242 metric of `TEXT_PLANE.md`). |
| Overlapping windows | The lower window's text is hidden by the upper window. New scenario. |
| Fade out | Text luminance falls in step with the background. |
| 2× vs 3× | Identical game-resolution layout, compared through `state` text and button rects. Pixel diff across scales is not meaningful. |
| SurfaceSDL vs OpenGL | Identical dumps: the engine composites (D1-B), so the backend must not matter. |
| FreeType build vs baked build | Byte-identical glyphs from the same map. |
| cp949 (KQ5/KQ6 upstream), SJIS (PC-98) with the option on | Needs a machine with the game data. `[unmeasured]` until then. |

**Baseline first.** Capture the current `_hiresTextPlane` behaviour on
every scenario above before any code moves, then A/B against it.

## 6. Build order

Each step lands on `i18n` through its own card worktree (`TREES.md`) and
passes the invariants before the next starts.

1. **TextLayer and compositor, with the glyph sources that exist today.**
   The legacy faces and SCVMUNI, coverage 0/255, at N = 2. Replace
   `_hiresTextPlane`, then remove the workarounds of §3.4 one at a time.
   This proves D2/D3/D4 before any font work.
2. **N = 3.** Generalise the scaler, cursor and `<< 1` paths.
3. **The option and driver selection.** `GAMEOPTION_*`, the
   `customizeGuiOptions` offer, and one predicate replacing the language
   rows at `init.cpp:95, :102, :128`. `usesHiresDoubleByteText()` becomes
   that predicate.
4. **The map parser and `[font.N]`/`[glyphs]`/`[latin]`/`[shadow]`.**
   Share SCUMM's parser if it can move to `graphics/`; otherwise mirror its
   keys exactly.
5. **TtfGlyphSource** (FreeType, baked on load) and the SCVMUNI coverage
   extension plus bake tool for `BakedGlyphSource`.
6. **cp949 and SJIS games through the TTF face**, with the PC-98 colour and
   alignment rules kept.
7. **Later, separately:**
   - C, the backend layer fast path
   - D6-b, proportional layout per game
   - D4-2, ARGB glyph storage
   - FM-Towns (`PC98_TOWNS_TEXT.md` §6.4)

## Open questions (to settle during implementation)

- Which face draws half-width katakana (SJIS 0xA1–0xDF) in PC-98 games.
  Not yet read in code.
- Whether any SCI game relies on graphics *not* erasing text that the
  mirror rules (§3.3) would erase, or the reverse. Found only by running
  games.
- Whether SCUMM's map parser and font baker (`graphics/hires_text/` on
  `hires-text`) can move to `graphics/` without dragging SCUMM
  dependencies. `i18n` does not contain them today.
- Cel drawing: clearing the TextLayer under opaque cel pixels needs a hook
  in the cel draw loop. The A1 census of SCI's direct buffer writes
  (`captures/2026-09-16/a1/`) is the list of places to cover. It must be
  re-checked against `i18n`, since it was taken on `hires-text`.
