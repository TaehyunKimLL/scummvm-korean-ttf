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

INI format, parsed by one shared reader, `Graphics::HiResFontMap`
(`graphics/hires_text/font_map.{h,cpp}`), ported unmodified from SCUMM's
`hires-text` branch and then extended. SCUMM and SCI read the same file
format and the same parser; every existing SCUMM map still parses to the
same result (SCUMM's own tests pin this). `[font.N]` and the `latin_*`
keys are SCI-specific - SCUMM never reads them.

The file is `hires_text.map` in the game directory, or the path named by
the ini key `hires_text_map`. It is honoured only under the same scope
predicate as `hires_text_font` (SCI16, below SCI2, a CJK code page); on
any other game it produces one warning and is ignored. Unknown sections or
keys, and bad values, each produce one warning and use the default - the
file is never rejected whole.

Below is the subset SCI implements today (a full translator walkthrough,
with a worked KQ1-ko example, precedence, and the exact warning texts, is
`HIRES_TEXT_MAP.md`):

```ini
; face used by a [font.N] that names none
[hires]
; a [fonts] name, or a path ("face=" also works)
font=default
; pixels
size=16

; face name -> file; relative paths are taken against the directory
; holding this map
[fonts]
default=NanumGothic.ttf
latin=/System/Library/Fonts/Supplemental/AppleGothic.ttf

; defaults for every font id; a [font.N] key overrides its own
[latin]
; off | half | fullwidth | proportional
mode=proportional
; a [fonts] name for the Latin range ("face=" also works)
font=latin
; keep | fullwidth   (fullwidth mode only)
space=keep
; game | font        (proportional mode only)
metrics=game

; one SCI font id (Task 1: KQ1-ko's dialogue box is 300)
[font.4]
; "font=" also works
face=default
size=16
; overrides [latin] mode for this font id
latin=proportional
; "latin_face=" also works
latin_font=latin
latin_space=keep
metrics=font

; platform-qualified: wins over [font.0] on PC-98 only
[font.0:pc98]
latin=fullwidth
```

- **Precedence, per setting:** ini key (global) > `[font.N:<platform>]` >
  `[font.N]` > `[latin:<platform>]`/`[latin]` (or `[hires:<platform>]`/
  `[hires]` for face and size) > the built-in default. `<platform>` is
  `Common::getPlatformCode()` (e.g. `pc98`, `dos`); it is applied when the
  map is parsed, so a `[font.N]` the adapter reads later already holds the
  winner of its qualified/bare pair, key by key.
- **Defaults:** size 16, latin off, space keep, metrics game, no face - so
  a map (or no map at all) that says nothing about a font id reproduces
  today's behaviour exactly.
- **Face names resolve through `[fonts]`.** A name not in the table is
  treated as a path. A relative path from the map (a `[fonts]` entry or a
  path written as a face) is taken against the directory holding the map
  file: the game directory for its own `hires_text.map`, the map's
  directory for one named by `hires_text_map=` elsewhere. Ini paths
  (`hires_text_font`, `hires_text_latin_font`) are used exactly as given,
  unchanged from before the map existed.
- **`enabled=true` is a legacy alias**, kept for SCUMM-map compatibility:
  it means "the engine's current Latin behaviour" - for SCI that is
  `latin=proportional`, with metrics from the usual chain (`game` by
  default; SCUMM's own meaning is unchanged). It is decided per font id,
  as the last step before the default: a font id whose mode is set by
  `hires_text_latin`, its own `[font.N] latin=` or `[latin] mode=` keeps
  that mode, and every other font id gets proportional. SCUMM's `bitmap=` also implies `enabled` for SCUMM, but SCI
  has no bitmap Latin path: a map that sets only `bitmap=` gets one
  warning (`hires_text.map: [latin] bitmap= is SCUMM-only, ignored`) and
  no effect.
- **The ini keys are global overrides**, each beating every map setting:

  | ini key | overrides |
  |---|---|
  | `hires_text_font` | The face path, for every font id at once - beats `[font.N] face=` too, not only `[hires] font=` |
  | `hires_text_font_size` | size, for every font id (8..64) |
  | `hires_text_latin` | latin mode (`off`/`half`/`fullwidth`/`proportional`), for every font id |
  | `hires_text_latin_font` | the Latin-range face, for every font id |
  | `hires_text_latin_space` | space (`keep`/`fullwidth`), for every font id |
  | `hires_text_metrics` | metrics (`game`/`font`), for every font id |
  | `hires_text_map` | which map file is read, instead of `hires_text.map` |
  | `hires_text_log` | diagnostic: log each line and which face drew it |

  Because the ini keys are global, they cannot select a *different* value
  per font id - only the map can. A translation that wants font 300 drawn
  proportionally and font 0 fullwidth needs a map; the ini keys alone
  apply the same choice to every id.
- **Inline comments and `[glyphs]` ranges, stated once for both
  engines.** The shared parser drops a trailing comment from every key's
  value: a `;` preceded by a space or a tab ends the value there (what
  remains is trimmed again), so `color=0 ; DOS` parses as `0`; a `;` with
  anything else before it stays part of the value
  (`single=my;font.fnt`). `[glyphs]` (bare, qualified, or scoped -
  `[glyphs:cs1]`) also takes ranges: the key is `<code>-<code>` (each half
  hex `0x..` or decimal), the value `keep` or `+<offset>`, expanding into
  the same per-code override table a single entry fills, with a single
  code beating a range in its own section and a later range beating an
  earlier one for the codes they share. The exact warning texts, the
  bounds (a range past `0xFFFF`, a target past `U+10FFFF`, the
  131072-code-per-load limit) and a worked example are in
  `HIRES_TEXT_MAP.md`.
- **One table of sections, common versus engine-specific.** "Parsed"
  means the shared parser (`graphics/hires_text/font_map.cpp`) reads the
  key into `HiResTextConfig`, for both engines alike; "applies" means the
  engine's own adapter acts on the parsed value. Qualifiers stay
  engine-defined: SCUMM uses the game id and then `v<N>`; SCI uses the
  platform code.

  | Section / key | Parsed (shared) | SCUMM applies | SCI applies |
  |---|---|---|---|
  | `[hires] scale`, `alpha` | yes | yes | no (the compositor fixes scale; alpha by ini) |
  | `[hires] font=`/`face=`, `size=` | yes | no | yes |
  | `[encoding] codepage` | yes | yes | no (encoding comes from detection, §2) |
  | `[bitmap] multi`, `single` / `glyphs` | yes | yes / no | no |
  | `[fonts]` roles `default` / `bold`, `title` | yes | yes / no | — |
  | `[fonts]` as a name table | yes | no | yes |
  | `[sizes]` | yes | no | no |
  | `[render] metrics` / `mode` | yes | yes / no | no (per font: `[latin]`/`[font.N] metrics=`) |
  | `[latin] enabled`, `bitmap` | yes | yes (`bitmap=` implies `enabled`) | `enabled=true` is an alias; `bitmap=` warns |
  | `[latin] font`, `metrics` | yes | no | yes |
  | `[latin] mode`, `space` | yes | no | yes |
  | `[font.N]`, `[font.N:<platform>]` | yes | no | yes |
  | `[shadow] mode` (`none/drop/outline/stroke/game`), `offset`, `color` | yes | yes | no (later; `stroke` stays in the shared enum) |
  | `[glyphs]`, `[glyphs:<scope>]`, ranges | yes | yes (scopes `cs0..cs19`) | no (later) |
  | `[map] height_N` | yes | no | no |
  | `[translation] file` | yes | no | no (translation data stays out of the map, §2.2) |

  A section or key with "no" in both apply columns is parsed - so a map
  that already uses it for the other engine does not warn - but not yet
  acted on by either adapter. Per-glyph kerning/centring in proportional
  mode, GUI options for any of this, scale 3, and the legacy SJIS face are
  also out of scope; see the plan document's "Out of scope" list.

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

### 5.1 Measured (build order step 1, engine `89de6486dd`, harness `424b280`)

`[measured]` KQ1 intro, Korean, vs `runs/baseline-4a0f7f0e1c` (the shipped
1bpp `korean.uni`): **0 pixels differ on all 4 captured frames**
(`intro_f1`/`f20`/`f45`/`f60`), Task 5 and Task 6 combined. Task 5 alone
left 2040 px/frame (the first dialogue box's text surviving its window's
close, by design - Task 5's brief says not to merge it alone); Task 6's
underbits-carries-the-layer change brings that to 0.

`[measured]` KQ1 tour, Korean, same baseline: **0 pixels differ on 5 of 6
dumps** (`01_title`, `02_look`, `02b_inventory`, `02c_ring`,
`02d_unknown`). The sixth, `03_room2`, differs (716-3176 px depending on
the run) but the diff has zero overlap with any text-layer-covered pixel
- cross-checked against `03_room2_layer.bin`, which has 0 covered pixels
for that capture - and moves with ego's on-screen x position, not with
any code change. `03_room2` is a stale-baseline artifact: the baseline
was captured before harness commit `7e96abf` ("kq1_tour: wait for the
picture to stop before dumping room 2") added a `wait_idle(8)` ahead of
that dump, so the baseline and the current script settle the walk at
different real-time instants. Re-baselining would show 0 here too; it is
not evidence against the compositor.

`[measured]` English: byte-identical to baseline on every `.bin` file,
0 `_layer.bin` files present - the lowres bitmap font never allocates a
`TextLayer`, so the English path is provably untouched by this plan.

`[measured]` `make test`: **435/435**, both after Task 5+6 and reconfirmed
for this task.

`[measured]` Headless macOS capture format is RGB565
(`_out.txt`: `640 400 2 5 6 5 0 11 5 0 0`), not the 32-bit format §3.5
describes, even after build-order step "Upscaled drivers ask for a 32-bit
screen" (`64a775be92`) landed. Cause: on a real display macOS's default
graphics manager is OpenGL, whose `getSupportedFormats()` offers a 32bpp
format first and would pick up the new request immediately; under this
box's `SDL_VIDEODRIVER=dummy` OpenGL can't get a context, so ScummVM
falls back to `SurfaceSDL`, whose presentation surface/texture is
unconditionally `SDL_PIXELFORMAT_RGB565` (unmodified upstream code) and
which therefore never offers a 32bpp format to fall through to. This is a
capture-environment ceiling, not a code defect.

`[unmeasured]` The 32-bit output path. No 32bpp capture has run: every
screen capture above is RGB565. Only the unit tests cover it
(`test/engines/sci/textcompose.h`, ARGB golden values for the blend).

`[measured]` 8bpp coverage reaches the screen. KQ1 intro `intro_f45`,
Korean, two font variants over the same base (`dist-ef8dc87f/kq1-ko`)
built by `mkvariant.py`: `kq1-ko1` (`korean.uni` rebaked at `--bpp 1`) and
`kq1-ko8` (`korean.uni` rebaked at `--bpp 8`), both from **Apple SD
Gothic Neo (`AppleSDGothicNeo.ttc` face 0, Regular; macOS system font,
local testing only)** at size 16 (`m7mkfont.py`; the original TTF used
for the shipped font is unknown, so this is a controller-chosen
substitute, not the shipped font).
Distinct raw RGB565 pixel values inside the second dialogue box's text
area (hires crop `x∈[60,579) y∈[272,337)`, interior of the box, same
frame, same crop, both variants):

| Variant | bpp | Distinct colours in box |
|---|---|---|
| `kq1-ko1` | 1 | 2 |
| `kq1-ko8` | 8 | 71 |

2 colours is exactly glyph-ink vs box-fill, no antialiasing - expected of
a 1bpp mask. 71 colours is the ink/fill pair plus a spread of
intermediate blends at every glyph edge, visible in the enlarged crop PNGs
as soft anti-aliased strokes rather than a hard 1bpp stair-step - this is
8-bit coverage compositing correctly, not a fluke of one frame.

#### Final-review measurements (engine `89de6486dd`)

`[measured]` `./configure --disable-engine=sci32 --disable-freetype2`
builds clean.

`[measured]` CLUT8 output (`rgb_rendering=false`): on the title screen,
`_out.bin` equals the text layer's `fgIndex` on 1023/1023 covered pixels -
the >= 50% stamp writes exactly the layer's colour.

`[measured]` The slack residue the old re-apply plane needed a one-cell
margin for is gone: the Task 6 layer dump has no coverage at hi-res rows
104..106.

#### Final-review fixes (engine `22247361c7`..`2ea1869dc0`)

- F1 `[unit-tested]` An invert (menu title and dropdown highlight, button
  hilite, edit-control cursor) recolours hi-res text instead of erasing
  it: fillRect's invert swaps the pen/back indices in the layer, the SCI0
  XOR invert XORs them with 0x0f; the two invert loops write the visual
  pixel without clearing the layer. No KQ1-ko scenario inverts over
  hi-res text (its buttons, menu bar and dropdowns are English), so the
  unit tests carry it.
- F2 An upscaled driver accepts the text layer only when it scales exactly
  2x on both axes to a screen of the layer's size; Win256's 640x440
  (11/5 vertical) and 320x240 geometries refuse it instead of reading
  past the layer and aborting. The composite loop is also clipped to the
  layer.
- F3 Only the KO/JA `UpscaledGfx` instance asks for a 32-bit screen;
  Win256 and PC-98 keep the backend's default format, so an untranslated
  game's output format is unchanged.
- F4 `refreshHiresRect()` carries the palette mods and palette-mod map
  again, as the old `drawTextFontGlyph()` path did.
- F5 Every draw into the visual plane clears the text over it:
  `vectorPutPixel()`'s direct path (picture lines, fills, patterns),
  `putFontPixel()`'s non-upscaled and 640x400 branches and `dither()`
  now do what `putPixel()` does. `bitsRestore*()` still restores, and the
  Mac 480x300 writers are left alone (no driver composites there).
- F6 A movie frame removes the text inside its rect, as the original's
  frame blit into the framebuffer did; text outside the frame stays.
- F7 A driver that does not composite the layer (a non-upscaled driver,
  or an upscaled one that refused under F2) now logs one warning naming
  platform, render mode and display, the §4 quiet fallback plus a log
  line.

`[measured]` After the fixes: `make test` 438/438; KQ1 intro, Korean,
0 px on all 4 frames; KQ1 tour, Korean, 0 px on the 5 comparable frames
(one earlier run differed by 428-1288 px in a non-text scene region of the
driver's own scaled bitmap, outside any layer coverage, and did not
reproduce); English intro byte-identical on every `.bin`, no `_layer.bin`.

#### Measured (step 5 early: `hires_text_font=`, engine `95aa1b1348`)

`[measured]` `hires_text_font=` wired into `GfxCache::loadUnicodeFont()`:
opens the named face through `TtfGlyphSource::create()`, timed with
`g_system->getMillis()`, before falling back to the bundled `.uni` names.
Same font as the earlier 1bpp/8bpp measurement above, live rather than
pre-baked: **Apple SD Gothic Neo (`AppleSDGothicNeo.ttc` face 0)** at
16px.

| Scenario | Face open time | Glyphs rasterised by exit | Total render time | Mean ms/glyph |
|---|---|---|---|---|
| KQ1 intro, Korean (`kq1_intro.py`) | ~10 ms | 103 | ~3 ms | ≪ 1 (~0.03) |
| KQ1 tour, Korean (`kq1_tour.py`, longer session) | ~10 ms | 111 | ~3 ms | ≪ 1 (~0.03) |

The millisecond figures are order-of-magnitude only: `getMillis()` has
about 1 ms resolution and a single glyph render takes well under that, so
the total is a sum of mostly-zero deltas and the mean is approximate. The
glyph counts are exact.

The load-time budget of at most 32 renders (26 probes plus the bounded
vertical-fit retry) counts `TtfGlyphSource`'s own renders only.
`Graphics::loadTTFFont` also caches about 256 Latin-1 glyphs for each size
it opens, and a face that needs k fit retries opens k+1 sizes.

`[measured]` Distinct raw RGB565 colours in the second dialogue box's
text area, `intro_f45`, same crop as above (`x∈[60,579) y∈[272,337)`):
**71** - matching the pre-baked 8bpp variant's count exactly, as expected
since both rasterise the same face at the same size with 8-bit coverage.

`[measured]` Invariants:
- Without the key: **0 px** A/B (`c1ab.py`) against
  `runs/baseline-4a0f7f0e1c/intro-ko`.
- Bad path (`hires_text_font=/nonexistent.ttc`): the game still starts;
  `run.log` shows exactly one `hires_text_font` warning
  (`hires_text_font /nonexistent.ttc: does not exist; using the .uni
  fonts`), then falls through to the `.uni` fonts; **0 px** A/B
  against the same baseline.
- English intro without the key: all 16 baseline `.bin` files
  byte-identical, 0 `_layer.bin` files present.
- `make test`: **456/456** at the time; 458/458 after the review fixes
  below.

`[measured]` Behaviour after the final-review fixes (engine `8d9f303d55`):
- Scope: the key is read from the game's own domain only (not
  `[scummvm]`), and is honoured only below SCI2 for a CJK code page
  (949/932/936/950). Elsewhere one warning (`hires_text_font is ignored:
  ...`) and the `.uni` search as before; English KQ1 with the key set:
  16 `.bin` files byte-identical, no `_layer.bin`. Interim until the
  `hires_text` master switch (step 3).
- `hires_text_font_size`: parsed without `ConfMan.getInt` (which aborts on
  text); a non-numeric value or one outside 8..64 gives one warning and
  16. `TtfGlyphSource::create` itself refuses sizes outside 6..255.
- The retry callback is a small `FitProbe` interface; no standard-library
  header in engine code.
- A Korean game refuses a face whose seven Hangul probes draw no ink
  (`face has no Hangul glyphs`) and falls back to `.uni` with one warning;
  Arial on KQ1-ko gives 0 px A/B. Other CJK code pages have no such check
  yet.
- An empty value (`empty path`) or a directory (`is a directory`) gives
  exactly one warning and the `.uni` fonts; 0 px A/B.

### 5.2 Which font id draws which text (Task 1, `hires_text_log`)

`[measured]` A new diagnostic ini key, `hires_text_log` (game domain,
bool, no scope predicate of its own - it works on English games too), logs
one `debug(1, "hires_text: font %d line \"%s\" faces %s", ...)` line per
rendered line, plus one aggregate line per `GfxText16::Box()` call, with a
per-glyph tally of which face answered (`resource`/`legacy`/`unicode`/
`latin`). Driven over the debug socket across KQ1-ko, LB1 and SQ1 VGA
(English), a few screens into each (full logs and driver scripts:
`runs/c4-fontids.md`):

| Game | Text kind | Font id |
|---|---|---|
| KQ1-ko | Title/menu | 4 |
| KQ1-ko | Dialogue box | 300 |
| KQ1-ko | Status line / menu bar / parser echo | 0 |
| LB1 (English) | Title/menu/status | 0 |
| LB1 (English) | Dialogue box | 4 (also 1 for one message) |
| SQ1 VGA (English) | Menu buttons | 0 |
| SQ1 VGA (English) | Dialogue box | 4 |

Font 0 is the status-line/menu-bar/parser-echo face in every game
measured; font 4 is the dialogue-box face in both English games, but
KQ1-ko's dialogue box is font 300 instead (its font 4 is the title-menu
face) - confirming the plan's point that face choice is per font id and
per game, not a fixed convention across games. This table is what the
worked example in `HIRES_TEXT_MAP.md` is built on.

### 5.3 The map, per-font settings and proportional Latin (Tasks 2-4)

`[measured]` No map and no ini keys: KQ1-ko intro, **0 px** on all 4
frames against `runs/baseline-4a0f7f0e1c/intro-ko`, reconfirmed after each
of Tasks 2, 3 and 4 landed. Ini-only runs (`off`, `half`, fullwidth
keep/space) also matched their pre-map captures byte for byte (all 28
`.bin` files, each mode) once the map layer existed - the map adds, it
does not change.

`[measured]` **Map-driven equals ini-driven.** A `hires_text.map` naming
the same face and `[latin] mode=fullwidth face=latin`, with *no* hires ini
keys at all, reproduced the ini-driven fullwidth-keep capture with 0 of 28
`.bin` files differing.

`[measured]` **Per-font proof**, `gamedata/c4-perfont/hires_text.map`
(`[hires] font=default`, `[fonts] default=`/`latin=` the two faces,
`[latin] face=latin`, `[font.300] latin=fullwidth`, `[font.0] latin=half`)
against the KQ1-ko tour: font 300 (dialogue) drew fullwidth ("ｘｙｚｚｙ"
and fullwidth quotes, spaces kept), font 0 (status line, menu bar, parser
echo) drew half-width on the same screen, and font 4 (no section) stayed
off - three different Latin modes live at once from one map, each font id
answering only for itself:

![Dialogue box (font 300), fullwidth](img/hires_text_map/perfont-dialogue_crop.png)
![Status line (font 0), half](img/hires_text_map/perfont-status_crop.png)

Both faces (SD Gothic Neo, AppleGothic) were opened once each, although
three font ids used them - confirming the TTF and Unicode-bundle source
caches are keyed by (path, size[, Latin face, mode]), not by font id.

`[measured]` **`latin=proportional`, `metrics=game` keeps layout
identical to `off`.** Every `state()` text rect matched the `off` run
exactly (intro: 4 states/24 rects, 0 differ; tour: 7 states/52 rects, 0
differ), and the `hires_text_log` line texts were identical too, so line
breaks did not move. This is the point of `metrics=game`: new glyphs,
old geometry.

`[measured]` **`metrics=font` changes every box**, because the layout now
follows the TrueType face's own (narrower) advances, including on ASCII
spaces (proportional routes `U+0020` to the face, like `half` does). Only
one box actually re-wrapped to a different number of lines (font 300's
`02d_unknown`); every other box kept its line count but narrowed, since a
narrower Latin face setting needs a narrower box in most cases, not more
lines. A map can mix the two per font id
(`gamedata/c4-prop/hires_text.map`: `[latin] mode=proportional
metrics=game`, `[font.300] metrics=font`): the resulting dialogue rows
matched the metrics=font capture and the status rows matched the
metrics=game capture, in the same run.

![All five Latin modes, KQ1-ko font 300 dialogue box](img/hires_text_map/latin_modes.png)
![All five Latin modes, KQ1-ko font 0 status line](img/hires_text_map/latin_modes_status.png)

`[measured]` **A missing `[font.N] face=`** (`gamedata/c4-missing`,
`[font.300] face=/nonexistent/Missing.ttf`) gave one warning and font 300
fell back to the global face at its own size; nothing went blank.

`[measured]` **English + a map is still out of scope**: one warning
(`hires_text.map is ignored: the game's language has no hi-res CJK
text`), and all 16 `.bin` files stayed byte-identical to the English
baseline.

`[measured]` `make test`: 505/505 after the SCUMM parser port, 518/518
after the SCI extensions, 527/527 after the per-font-settings task, and
535/535 after proportional Latin landed - each build's own count, cited
in full in the task reports.

**Known limits, carried forward rather than fixed here** (space for a
future `space=` choice in proportional mode; metrics=game can look
letter-spaced with a narrow face in a wide game cell; metrics=font can
look cramped with a very narrow face): see "Known limits" in
`HIRES_TEXT_MAP.md`.

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
