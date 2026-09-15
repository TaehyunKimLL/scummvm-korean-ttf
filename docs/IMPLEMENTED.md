# ScummVM hi-res text — what is implemented

Branch `hires-text`, measured at `7b0a8c9899f` against `upstream/master`:
**91 commits**, 233 files, +17067/−9207. Engine and graphics source alone:
175 files, +9354/−8337.

`make test`: **531 tests OK**. Engine builds with 0 errors.

The goal is an upstream contribution, so everything below is shaped by that:
no FreeType requirement at runtime, no behaviour change for existing
platforms, and every exemption written down rather than left implicit.

---

## What the feature is

Draw a game's text with a replacement font at 2× or 3× while the game's own
graphics stay at their native 320×200. The text surface is scaled; the
background is upscaled at composite time. This mirrors what ScummVM already
does for FM-Towns and PC98 Japanese, generalised so any language can use it.

Originally Korean-only (`korean_ttf_*` keys, `loadKorFont()`); now language
neutral (`hires_text_*` keys), with Korean as one case among several.

---

## 1. The font layer (`graphics/hires_text/`)

Engine-independent, so a second engine could use it without touching SCUMM.

| file | what it holds |
|---|---|
| `font_map.cpp/h` | the `.map` INI reader: `[fonts]`, `[sizes]`, `[latin]`, `[render]`, `[shadow]`, `[map]`, plus `:game` / `:vN` section narrowing |
| `bitmap_font.cpp/h` | SVFN reader — Unicode-indexed bitmap font, 1bpp or 8bpp coverage, optional per-glyph metrics |
| `glyph_renderer.cpp/h` | coverage-aware glyph rasteriser; decorations built from a dilation mask |
| `font_baker.cpp/h` | bakes a TrueType face into the above at start-up, against the game's own cell |

**SVFN**, the map-less bitmap format: magic `"SVFN"`, header
`<4sHHBBHHBBBBHIII` = magic, version, flags, bpp(1\|8), shadow, codepage,
count, cellW, cellH, ascent, r0, r1, metricsOff, dataOff, dataSize.
`flags & 1` means variable width; metrics are 4 bytes per glyph.

The old format's first byte is always 2, so the two coexist with no
ambiguity. **Baking needs FreeType; running does not** — verified by
md5-identical captures between a FreeType and a `--disable-freetype2` build.

### Font naming, without a map

A folder can carry several languages and the game's own language setting
picks. All names fit 8.3, because these files travel beside game data that
often sits on a FAT volume or inside an archive built by a DOS-era tool.

| name | holds |
|---|---|
| `hrkor%02d.fnt` | Korean double-byte (CP949) |
| `hrjpn%02d.fnt` | Japanese double-byte (CP932) |
| `hrchs%02d.fnt` | Simplified Chinese (CP936) |
| `hrcht%02d.fnt` | Traditional Chinese (CP950) |
| `hrlat%02d.fnt` | the single-byte Latin half, shared by all of them |
| `hires%02d.fnt` | the older language-neutral name, still read |

---

## 2. The SCUMM side (`engines/scumm/`)

| file | what it holds |
|---|---|
| `hires_text.cpp/h` | the layer's state, config, font selection, `drawChar()` / `advanceFor()` |
| `hires_overlay.cpp/h` | index plane + coverage plane kept in step; a split between them is made impossible by construction |
| `hires_sink.h`, `hires_sinks.h` | composite sinks — one per output format, picked by the screen's width |
| `hires_scale.h` | `expandStrip()` / `hiResBlitStrip()`, the scroll-effect magnifier |
| `trs_bundle.h` | `.trs` translation bundle reader, any language |

### Which renderers reach the layer

Enforced by `make test` (`test/engines/scumm/hires_hook_census.h`) and
reported by `devtools/scumm-hires-hook-census.py`. The two parse the same
table, so they cannot disagree.

**13 renderers: 7 reach the layer, 6 exempt, 0 unaccounted.**

| renderer | hook |
|---|---|
| `CharsetRendererClassic` | `printChar` |
| `CharsetRendererV3` | `printChar` |
| `CharsetRendererV7` | `draw2byte`, `drawCharV7` |
| `CharsetRendererTownsClassic` | `drawBitsN` |
| `CharsetRendererTownsV3` | `drawBits1` |
| `CharsetRendererV2` | inherited via `CharsetRendererV3::printChar` |
| `CharsetRendererPCE` | inherited via `CharsetRendererV3::printChar` |

Exempt, each with a recorded reason: `CharsetRenderer`,
`CharsetRendererCommon`, `CharsetRendererPC` (abstract),
`CharsetRendererNES` (NES tile font, single byte),
`CharsetRendererMac` (inverted stencil data flow — see §5),
`CharsetRendererNut` (v8/SMUSH; **open**).

### Composite paths

- **Paletted** — glyphs composited into CLUT8 at the scaled size.
- **True colour** (`hires_text_alpha=true`) — 8-bit coverage blended into a
  32bpp buffer. Requires the palette work in §4.
- **16bpp** — sink picked by the screen's width rather than assuming 32bpp;
  each game pixel repeated m times in the composite loop.
- **FM-Towns** — its own `drawBitsN` hook, with the banner's coverage saved
  alongside its indices.

---

## 3. Translation bundles (`.trs`)

`loadLanguageBundle()` reads `SCVMTRS ` magic plus a line table. Originally
Korean-only; now `getTrsBundleName()` returns `korean.trs` for `KO_KOR` and
`<language>.trs` otherwise — so Japanese is **`ja.trs`**, not `japanese.trs`.

Measured on identical FM-Towns MI2 data: `ja.trs` logs
`loadLanguageBundle: Loaded 8780 entries` and detects as Japanese;
`japanese.trs` logs nothing, detects as English, draws untouched English.

### Japanese bundle extraction (harness-side, not engine)

Nothing is translated — the text comes from the **official FM-Towns Japanese
releases**. English and Japanese were built from the same scripts, so the
container tree is identical and only text blocks differ:

| game | EN blocks | JA blocks | paths equal | text blocks differing |
|---|---|---|---|---|
| mi1 | 7195 | 7195 | 7195 | 958 |
| mi2 | 8615 | 8615 | 8615 | 1526 |
| loom | 3224 | 3224 | 3224 | 288 |
| zak | 2889 | 2889 | 2889 | 710 |

A block path is a stable key across the two releases, so `difflib` over the
same path yields English↔Japanese literal pairs, keyed on the English offset.
A single-release scanner cannot work: string *starts* are not recoverable
(76.1% at best) because 0xFF escapes carry 0x00 operands and there is no
framing marker.

Generated: mi1 4133 / mi2 6090 / loom 1172 / zak 1784 entries. The Dig is
excluded — `digja/DIG.LA1` is byte-identical to the English one and its text
lives in `VIDEO/LANGUAGE.BND`, a format the engine already reads.

`ja.trs` itself cannot be committed (derived from game data we do not own);
`harness/tools/jatrs_repro.py` regenerates all four and pins them by
size/md5/line-count, 8/8 green, failing 4/4 under defect injection.

---

## 4. Palette and transition work

True-colour composite means already-copied 32bpp pixels do not follow a
palette change. Fixed by marking all three virtual screens dirty after
updating the alpha palette, so the whole frame recomposites.

Also landed: restore the game palette when the ScummVM GUI closes; keep the
cursor paletted while text is blended; repaint the text band after clearing
it; retire hi-res text one virtual screen at a time; do not blend in games
that own the palette.

**Scroll effect** (`1d08eb6b75d`): `copyRectToScreen` was called with a
`vsPitch * m` stride over a 320-wide CLUT8 source, so the backend read m rows
at a time — direction 0 covered only the left 320 of 960, the other three
tiled. Now the strip is precomposed into an output-format surface and blitted
at its real pitch. `expandStrip()` declines (returns `false`, keeping the
original path) for `m == 1`, non-CLUT8, EGA dither, CGA/Hercules, alpha
inactive, or off-screen.

---

## 5. Platform findings

### FM-Towns / PC-Engine
Both hooked. PC-Engine inherits the V3 hook, and its 16bpp branch draws to
the VirtScreen. A 16bpp overrun in `_compositeBuf` was demonstrated with ASan
and fixed by picking the sink from the screen's width.

### Mac v3 — measured, deliberately not hooked
`CharsetRendererMac::printCharInternal()` draws each glyph **twice**: colour
**0** into `_textSurface`, the real colour into `_macScreen`. The compositor's
only test is `ts[...] == CHARSET_MASK_TRANSPARENCY` — if the text plane says
"empty", paint the picture over it. So `_textSurface` is an **inverted
stencil**, not a glyph store, and `_macScreen` alone decides nothing.

Measured: 50+ duplicate glyphs drawn into `_macScreen` with the stencil
untouched changed the screen by **exactly 0 pixels** (ink 2055 vs 2055, no
diff bbox). Anti-aliasing is impossible there — `withCoverage=false`, so the
coverage plane is never allocated (`cov=(nil)` observed).

A hook therefore belongs at the renderer's glyph source, writing **both**
passes. Recorded, not built. Also found: `scumm.cpp:1474` overwrites
`_textSurfaceMultiplier = 2` *after* the hi-res block at 1317, so **scale 3 is
silently ignored on Mac**.

### v7 (Full Throttle / The Dig / COMI)
`CharsetRendererV7::draw2byte` and `::drawCharV7` are hooked (`bed6b1ce00a`).
`printChar()`'s `error()` stub is **deliberate** — v7 is driven through the
`GlyphRenderer_v7` vtable and the inherited `CharsetRendererClassic::printChar`
is the v5 pipeline whose state v7 does not maintain. The stub was left alone.

SMUSH cutscene subtitles go through `NutRenderer::draw2byte` instead, which is
**not** hooked — that is the one open renderer.

v7 cannot be scaled: `_textSurfaceMultiplier` is gated on `version < 7` and so
is the whole `_textSurface` composite, so a v7 replacement set must be baked at
the game's own cell.

---

## 6. Correctness fixes found along the way

- **`drawBits1Kor` row guard** (`9f6f22b95cb`) — the guard bounded the row it
  was *asked for* (`drawTop`, passed unscaled by `printChar`'s last fallback)
  rather than the row the loop *writes* (`y1 + y + offsetY[i]`, already scaled).
  9 out-of-bounds writes → 0, confirmed under ASan against the engine's real
  loop. A second suspected defect in the same area was investigated and
  **refused**: the "row advance after a clipped column" counter was tautological
  and `pitch - width` is exact wherever the x guard drops nothing.
- **A blank replacement glyph is worse than no glyph.** The contract is
  "`drawChar` returns false, so the caller draws the original". A glyph that
  exists but is empty breaks it — SCUMM stores small pictures in the control-code
  range (The Dig's option sliders are a run of `0x0B`), and a Latin face baked
  from TrueType has ~68 blank cells right there. `glyphHasInk()` gates drawing
  and measuring together.
- Whole-multiple scale policy, with a diagnostic when a user-named scale does
  not fit the fonts.
- Latin glyphs placed on the CJK baseline; sub-pixel remainder of proportional
  advances carried.
- Nearest-font fallback when a charset has none.
- Config keys renamed (`korean_ttf_map` → `hires_text_map`, etc.); the old ones
  are read only to warn.

---

## 7. Tests

| file | covers |
|---|---|
| `test/graphics/hires_text_glyph_renderer.h` | 1137 lines — glyph shapes × decorations sweep |
| `test/graphics/hires_text_font_map.h` | 540 lines — map parsing, section narrowing |
| `test/graphics/hires_text_bitmap_font.h` | 419 lines — SVFN reading |
| `test/engines/scumm/hires_sink.h` | 244 lines — composite sinks |
| `test/engines/scumm/hires_scale.h` | 223 lines — scroll-effect magnifier |
| `test/engines/scumm/hires_scale_rule.h` | 102 lines — when expansion declines |
| `test/engines/scumm/trs_bundle.h` | 74 lines — bundle naming by language |
| `test/engines/scumm/hires_hook_census.h` | the renderer census, as a test |
| `test/engines/scumm/hires_overlay.h` | index/coverage plane invariants |

None require FreeType.

---

## 8. Documentation in-tree

- `engines/scumm/HIRES_TEXT.md` (250 lines) — what it does, config, ordering,
  glyphs a game drew itself, decorations, metrics, scaling, diagnostics
- `engines/scumm/HIRES_TEXT_SETUP.md` (425 lines) — the ini, the map, the fonts
- `engines/scumm/HIRES_TEXT_DECORATIONS.md` (161 lines) — outline/shadow and traps
- `graphics/hires_text/README.md` (171 lines) — the engine-independent layer
- `tools/korean/` (39 scripts) — font baking and the capture harness

---

## What is not done

1. **`NutRenderer::draw2byte`** — SMUSH cutscene subtitles, the one open
   renderer. The FT intro is served by this, which is why a `CharsetRendererV7`
   hook measured 0 calls there.
2. **Mac hook** — measured and designed (§5), not implemented. Loom Mac is the
   smallest viable target; Indy 3 Mac needs a second hook inside the Mac GUI's
   text area because its dialogue box bypasses `printCharInternal` entirely.
3. **Mac scale-3 warning** — currently silent.
4. **Japanese hi-res rendering is unverified.** The T4 captures prove the
   `.trs` path and the game's *own* FM-Towns font ROM; no `hrjpn%02d.fnt` set
   has been baked or captured. The naming convention and the FM-Towns hook are
   implemented but exercised only in Korean.
5. **Upstream hygiene** — 91 commits need splitting/ordering for submission,
   and `ENABLE_SCUMM_7_8` on/off both need a clean build.
