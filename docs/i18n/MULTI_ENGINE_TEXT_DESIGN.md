# Unicode, TTF and 8-bit alpha text beyond SCI: SCUMM, AGS, Grim, Sword1/2

Status: **design, 2026-09-26, card C8 (`t_b46cb319`). Not built.**
Written against `i18n` at `91cffbd25a` (SCUMM + SCI hi-res text, one line).
Its tasks are in `MULTI_ENGINE_TEXT_PLAN_5.md`.

`[source]` = read in code (file:line at `91cffbd25a` unless another tree is
named). `[measured]` = observed by running or decoding something.
`[unmeasured]` = a claim this document has not yet earned.

## Goal

The Korean fan patches in `TaehyunKimLL/scummvm-kor-trs` (`kortrs/`) cover
five engines. SCI has the full path (`HIRES_COMPOSITOR_DESIGN.md`): a TrueType
face rasterised on demand, an 8-bit coverage bitmap font as the fallback,
Unicode code points from the text decoder to the glyph, and an alpha
composite. The other engines have pieces of it or none of it. This design
gives each of them the smallest change that reaches the same three
properties:

1. **TTF**: a `.ttf` named by the player or the patch draws the text, through
   ScummVM's FreeType (`Graphics::loadTTFFont`), with glyphs rasterised on
   first use and cached.
2. **8-bit alpha bitmap fonts**: a pre-baked coverage font draws the same
   shapes in a build without FreeType.
3. **Unicode text**: glyph lookup is by code point (UTF-32 inside), the input
   may be UTF-8, and the legacy CP949/EUC-KR bytes the shipped patches use keep
   working.

And one invariant, as for SCI: **with no new key and no new file, every game
runs byte-identical to upstream.** The proof is the C6 method: the same
headless capture on the new build and on upstream, frame sequences compared
with `runs/c6-tools/seqcmp.py`.

## 1. Scope and order

| # | Engine | Korean patches | Value to Korean players | Risk | Decision |
|---|---|---|---|---|---|
| 1 | **SCUMM** | 12 (MI1/MI2 UTE, Indy3/4, Loom ×2, S&M, FT, MM ×2, Zak ×2) | High. Korean works today through bake-at-load bitmaps; TTF glyphs look letter-spaced, no UTF-8 | Medium: many byte-scanning sites for UTF-8 | **In, first** (user decision, 2026-09-26) |
| 2 | **AGS** | 13 (Blackwell 1-5, Primordia, Shardlight, Lamplight City, 5 Days a Stranger, 30minutes, Winter's Night, KQ1 VGA, SQ2 VGA, Zak2 fan game) | **Highest.** On official ScummVM none of them shows Korean: `.tra` loads, glyphs are missing or garbled | Low-medium: a new text format, gated to Korean translations | **In, second** |
| 3 | **Grim** | 1 | Medium. Korean works upstream, but only on the legacy OpenGL renderer | Low: text render path of one language | **In, third** |
| 4 | **Sword1/Sword2** | 2 | Low. Korean works upstream with KS X 1001 bitmaps at 640×480 | Low for glyph sources; high for alpha (8bpp screen) | **In, last and optional**: glyph sources and hard edges only; alpha deferred |

Why this order besides the user's decision:

- **SCUMM** already has the compositor (`HiResOverlay` + sink) and the map; it
  lacks the live glyph source and Unicode input. The work there also moves the
  shared pieces out of `engines/sci`, which every later engine uses.
- **AGS** gives the most games per line of code. All seven AGS patch games the
  C6 run could start are true-colour `[measured]` (`runs/c6/*/run.log`,
  "Game native resolution": Blackwell 1-3 and Winter's Night 320×240 or
  320×200 32-bit, Blackwell 4 640×480 32-bit, Blackwell 5 640×400 32-bit,
  5 Days 320×240 16-bit), so no compositor is needed: glyphs blend straight
  into the game bitmap.
- **Grim** is one render function per renderer. It matters most on platforms
  that have no legacy OpenGL, which is where the patch author's audience
  (EmuELEC, Android) plays `[unmeasured]`.
- **Sword1/2** gain little: their Korean already works, and the only visible
  improvement (anti-aliasing) needs a compositor over an 8bpp paletted screen,
  which is SCI-sized work for two games.

Not in scope: hi-res supersampled text for AGS (text stays at the game's
native resolution); the Grim remaster; Sword1/2 alpha; AGS games with no data
here (30minutes, Lamplight City, Zak2 fan game) beyond unit tests.

## 2. What each engine does today

### 2.1 SCUMM

- **Screen:** 8bpp virtual screens; hi-res text on `i18n` goes to a separate
  `HiResOverlay` (index plane + coverage plane) that the sink composites into
  a 32bpp (or 16bpp) output when `alphaActive()` `[source]`
  `engines/scumm/hires_overlay.h`, `hires_text.h:130`.
- **Fonts:** the game's charsets, `korean.fnt`/`koreanNN.fnt` (legacy 1bpp),
  SVFN bitmap fonts named by `hires_text.map` `[bitmap]`, or a TTF baked into
  SVFN at start-up per charset by `HiResFontBaker`
  (`hires_text.cpp:1126 bakeCharset()`), for the 2350 KS X 1001 syllables plus
  Latin-1 `[source]`.
- **Encoding:** bytes. DBCS boundaries are found by
  `is2ByteCharacter()`/`checkKSCode()` at about ten sites
  (`string.cpp:1265, 1542, 1698, 1916, 1981`, `string_v7.cpp:79, 136, 168`,
  `charset.cpp:708, 714`) `[source]`. The hi-res path decodes to a code point
  once, in `ScummHiResText::decodeNext()` (`hires_text.cpp:1500`), with the
  map's `[encoding] codepage` (utf8 included, `charLength()` at `:1461`), but
  the engine's own scanners around it only know CP949/932/936/950 lead bytes.
- **C6 findings to fold in** (coordinator, 2026-09-26): TTF glyphs sit small
  in fixed game cells, so text looks letter-spaced; a TTF-only map warns
  "names no [bitmap] fonts ... will not use it" (`hires_text.cpp:1354`) though
  it does use it; without `--extrapath` to `encoding.dat` the bake silently
  drops the Hangul block; MI2 needs 0x5C/0x60 kept as the game's own glyphs.
  C7 (`t_e9516789`, `wt/c7-erase`) fixes the text-erase regression from
  `babb7a17d4`; the SCUMM tasks here start from that fix.

### 2.2 AGS

- **Screen:** the game's own colour depth (8, 16 or 32 bit) at native
  resolution; text is drawn into an Allegro `BITMAP` by a font renderer
  `[source]` `engines/ags/shared/font/fonts.cpp`.
- **Fonts:** `WFNFontRenderer` reads `agsfntN.wfn` only (1bpp, 16-bit offset
  table, glyph = byte code) `[source]` `wfn_font_renderer.cpp:124`,
  `wfn_font.cpp`. `TTFFontRenderer` reads `agsfntN.ttf` only through alfont,
  which sits on ScummVM's FreeType `[source]` `ttf_font_renderer.cpp:121`,
  `lib/alfont/alfont.cpp:41`. alfont has an anti-aliased path
  (`alfont_textout_aa`) for true-colour games.
- **Encoding:** Allegro's `uformat`: `U_ASCII` (one byte = one char) or
  `U_UTF8`. The game's option `OPT_GAMETEXTENCODING == 65001` or a `.tra`
  string option `encoding=utf-8` selects UTF-8
  (`engine/main/engine.cpp:530`, `engine/ac/translation.cpp:108`) `[source]`.
  Renderers iterate with `ugetxc()`, so under `U_UTF8` they already receive
  code points. **AGS 3.x UTF-8 is therefore already supported**; what is
  missing is a legacy Korean format and Korean glyphs.
- **The Korean patches** `[measured]` (`kortrs/*/[Kk]orean.tra` decrypted, 14
  files): no `ext_sopts` block, so no `encoding` option; every translated
  value with a high byte decodes as CP949; 1,076,913 double-byte characters,
  of which all but 24 are KS X 1001 Hangul (lead `0xB0-0xC8`, trail
  `0xA1-0xFE`). The 24 others are a handful of UHC-only syllables (`떄`, `뿝`)
  and Windows-1252 bytes (`“ ” …`, `é`) followed by ASCII, in Primordia and
  Lamplight City. Lamplight City has 371 keys (English source strings) with
  high bytes: keys are in the game's single-byte encoding.
- **The fonts they ship:** `extfntN.wfn` (12 games) - `[measured]` a WFN with
  a **32-bit** table address and exactly 2350 entries (5 Days `extfnt0.wfn`:
  table at 0xDC63, (65819-56419)/4 = 2350), i.e. the KS X 1001 Hangul block in
  code order; `agsfntN.ttf` Korean faces (Deception, Epiphany, Lamplight City;
  Shardlight ships 1-byte `agsfnt0.ttf` stubs next to `agsfnt0.wfn`).
- **Why they fail on official ScummVM** `[measured]` (C6 group C/D): the
  `.tra` loads (`Translation initialized: korean (format: presume ASCII)`),
  but `extfnt` is read nowhere in `engines/ags`, so 5 Days shows mojibake from
  the Latin `agsfnt` WFN; the TTF games get CP949 bytes as single Latin-1
  characters.
- **The patch author's fork** (`british-choi/scummvm`, branch `ags_kor`
  `6c3430ec98`, and `branch-2-9-1` `60cbee22d2`, `01a6d7d1b7`, `edfb7dca90`)
  `[source]` via `gh api`: `WFNFont::ReadExtFntFromFile()` (the 32-bit WFN),
  a `ksx1001` Allegro format that returns `hi<<8|lo`, `alfont` converting that
  pair with `Common::convertUHCToUCS()`, `GetFontHeight()` returning the first
  Hangul glyph's height, a "Korean breaks anywhere" rule in `split_lines()`,
  and a KQ1-3 remake GUID list that hides the translation from the game's own
  language menu. The README says the upstream PR was closed because AGS
  upstream would have to take it first.

### 2.3 Grim

- **Screen:** 3D renderers (legacy OpenGL, OpenGL shaders, TinyGL). A text
  line is rendered into a `Graphics::Surface` by `Font::render()` and uploaded
  as a texture or TinyGL blit image `[source]` `gfx_opengl.cpp:1417`,
  `gfx_tinygl.cpp:1023`.
- **Korean upstream** `[source]`: `grim.ko.tab` replaces `grim.tab`
  (`localize.cpp:58`); for each `.laf` font a `<name>.laf.txt` names a TTF and
  a pixel size (`resource.cpp:400`, `font.cpp:358`);
  `FontTTF::render()` decodes CP949 to `U32String` and draws with
  `Graphics::TTFFont` in white 0xFFFFFFFF over a colour key (`font.cpp:452`);
  **`grim.cpp:277` removes the shader and TinyGL renderers for Korean.** The
  patch ships D2Coding TTFs and four `.laf.txt` files.
- The probable reason for the exclusion `[unmeasured]`: TinyGL uploads the
  line with a colour key, so anti-aliased edge pixels blended into the key
  colour survive as coloured fringes, and the fixed white ignores the text
  colour.

### 2.4 Sword1 / Sword2

- **Screen:** 640×480 CLUT8, text built into a sprite (`FrameHeader`) with
  `LETTER_COL`/`BORDER_COL` pixels and drawn by the sprite blitter
  `[source]` `sword1/text.cpp:111-150`, `sword2/maketext.cpp`.
- **Korean upstream** `[source]`: `korean.clu` replaces the text cluster;
  `bs1k.fnt`/`bs2k.fnt` (2350 glyphs, 20×26, 8bpp in the game's
  LETTER/BORDER colours) is appended to the font resource
  (`sword1/resman.cpp:277`, `sword2/resman.cpp:315`); `isKoreanChar()` accepts
  lead `0xB0-0xC8`, trail `0xA1-0xFE`; width fixed at 20.
- **C6** `[measured]`: BS2 detects Korean and runs identically on both builds
  (text appears after the 90 s capture window); BS1 needs the original
  Windows CD release (`scripts.clu` 1087240 B), the eXo copy is the
  re-release, so Korean BS1 cannot be verified here.

## 3. Decisions

| # | Decision | Chosen | Rejected, and why |
|---|---|---|---|
| E1 | Shared glyph interface | **Move `UnicodeGlyphSource` and its sources (`TtfGlyphSource`, `ScvmuniGlyphSource`, `RoutedGlyphSource`) and `TextCompose` from `engines/sci/graphics` to `graphics/hires_text/`**, namespace `Graphics`; add `SvfnGlyphSource` over `HiResBitmapFont` | A second TTF cache per engine: the SCI one already has the lazy cache, EAW widths, the vertical fit and the Hangul probe, all unit-tested (`test/engines/sci/glyphsource.h`) |
| E2 | 8-bit alpha bitmap format | **SVFN** (`graphics/hires_text/bitmap_font.*`) for every engine that gains a bitmap font here | SCVMUNI: fixed narrow/wide cells, reader in `engines/sci`, no per-glyph metrics - AGS text is proportional. SVFN already lives in `graphics/`, carries 1bpp or 8bpp, per-glyph advance/bearing, a v2 code-point table (any repertoire, not tied to a code page), and has a baker (`font_baker.*`) usable at run time and offline. SCI keeps reading SCVMUNI and can read SVFN for free through `SvfnGlyphSource`. |
| E3 | Text representation | **Bytes in the engine, UTF-32 code points at the glyph interface**, per engine below | UTF-32 through the VMs: every string op, buffer and savegame would change |
| E4 | Compositing | **Per engine** (§5): SCUMM keeps `HiResOverlay`; AGS and Grim blend directly (true colour); Sword stamps hard edges | One compositor for all: AGS and Grim already draw in true colour; Sword's 8bpp screen needs SCI-sized work for two games |
| E5 | Config | **`hires_text.map` (shared parser) + a few ini keys**, sections applied per engine (§6) | Per-engine files: a second format for translators to learn (SCI D7) |
| E6 | Legacy patch files | **Read as shipped**: AGS `extfntN.wfn` and CP949 `.tra`, Grim `.laf.txt`, Sword `bsNk.fnt` | Asking translators to convert: the patches are the reason for the card |
| E7 | Default behaviour | **Byte-identical unless a new key, a map, or a legacy Korean file of E6 that upstream ignores is present** | A global switch: AGS Korean patches must work with the files they ship |

### 3.1 Unicode per engine

| Engine | Input accepted | Inside | Why |
|---|---|---|---|
| SCUMM | CP949 (default, as today) or **UTF-8** (opt-in: map `[encoding] codepage=utf8`, or a UTF-8 BOM on `korean.trs`) | bytes in the VM; code points from `decodeNext()` on | SCUMM strings carry `0xFF`/`0xFE` escapes and ASCII control codes (`@`, `^`, `\`). UTF-8 never contains `0xFE`/`0xFF` and never has an ASCII byte inside a multi-byte character, so it is **safer** than CP949, whose trail bytes include `0x5C` and `0x60` (the MI2 case). UTF-32 in the VM would change every buffer and save. |
| AGS | UTF-8 (native AGS, `.tra` `encoding=utf-8`) or **EUC-KR** (legacy `.tra` with no encoding option, Korean) | bytes; code points from `ugetxc()` | AGS already does UTF-8; the legacy form needs one more Allegro text format whose getter returns **Unicode code points**, so every renderer (WFN+ext, TTF, SVFN) is keyed by code point. The fork's `hi<<8|lo` packing is rejected: it pushes code-page knowledge into each renderer. |
| Grim | CP949 (`grim.ko.tab`, as today); UTF-8 when the file starts with a UTF-8 BOM or the map says `codepage=utf8` | `U32String` per line | already decodes per line (`font.cpp:443-470`) |
| Sword1/2 | CP949 (KS X 1001 pairs, as today) | code point at glyph lookup | text is fixed resource data in `korean.clu`; no one writes new text for it |

**EUC-KR, not full CP949, for AGS.** `[measured]` Primordia and Lamplight City
values contain Windows-1252 bytes followed by ASCII (`é` + `b`). CP949's trail
range includes `0x41-0x5A`/`0x61-0x7A`, so a CP949 scanner would glue them
into UHC syllables. EUC-KR requires both bytes in `0xA1-0xFE`, which covers
KS X 1001 Hangul, symbols and Hanja and leaves every Windows-1252-plus-ASCII
pair alone. The cost is two UHC-only syllables across all 14 files (`떄`,
`뿝`), drawn as two single bytes; the load logs them once.

## 4. Shared code

### 4.1 What moves to `graphics/hires_text/`

| From (`engines/sci/graphics/`) | To (`graphics/hires_text/`) | Notes |
|---|---|---|
| `glyphsource.h` | `glyph_source.h` | `Graphics::UnicodeGlyphSource`, unchanged API |
| `glyphsource_ttf.{h,cpp}` | `glyph_source_ttf.{h,cpp}` | `Graphics::TtfGlyphSource`, lazy per-code-point cache, `create(stream, dispose, pixelSize, error, requireHangul)` |
| `glyphsource_scvmuni.{h,cpp}` | `glyph_source_scvmuni.{h,cpp}` | reader only; the format doc stays `SCVMUNI_FONT.md` |
| `glyphsource_routed.{h,cpp}` | `glyph_source_routed.{h,cpp}` | Latin routing |
| `textcompose.{h,cpp}` | `text_compose.{h,cpp}` | `blend()`, `expandGlyphRow()`, `composeSpan()`, `stampSpan()`; `TextPixel` moves with it |
| `latinadvance.{h,cpp}` | `latin_advance.{h,cpp}` | `latinAdvanceGamePx()`, the proportional advance rule SCUMM adopts |
| — | `glyph_source_svfn.{h,cpp}` (new) | `SvfnGlyphSource` adapts `HiResBitmapFont` (1/8bpp, per-glyph metrics) to the interface |
| — | `codepage_kr.{h,cpp}` (new) | `isEucKrPair(hi, lo)`, `ksx1001Index(hi, lo)` (0..2349 or -1), `ksx1001FromCodePoint(cp)` (reverse table built once from `Common::U32String(..., kWindows949)`) |

Stays in SCI: `TextLayer` (its mirror rules are SCI's screen model),
`GfxFontUnicode*`, `GfxFontSet`, `fontset` routing, `textlatin`. SCI includes
the moved headers; the tests move to `test/graphics/hires_text_glyph_source.h`
and `test/graphics/hires_text_text_compose.h` unchanged in content.

### 4.2 What stays per engine

Which font id is which face, layout (widths reported to the game, line
breaks), when text is erased, and where the composite happens. Each engine
has one adapter: `ScummHiResText` (exists), `AGS3::HiResFontConfig` (new,
`engines/ags/shared/font/hires_font_config.*`), a few lines in Grim's
`FontTTF`, and `Sword1::Text`/`Sword2::FontRenderer` glyph hooks.

## 5. Compositing per engine

| Engine | Where glyphs go | Alpha | 8bpp case |
|---|---|---|---|
| SCUMM | `HiResOverlay` (index + coverage), composited by the SCUMM sink into 32/16bpp | yes, as today | coverage ≥ 50 % stamps the index (the sink's CLUT8 rule, unchanged) |
| AGS | straight into the destination `BITMAP` at game resolution | yes in 16/32-bit games: `dst = lerp(dst, textColour, coverage)` per pixel (SVFN), alfont AA (TTF) | coverage ≥ 50 % → the text colour index. None of the measured patch games is 8-bit. |
| Grim | the line surface becomes ARGB with alpha = coverage, colour = the text colour; TinyGL/shaders blit with blending instead of a colour key | yes | n/a (3D, true colour) |
| Sword1/2 | the text sprite, as today: coverage ≥ 50 % → `LETTER_COL`, a one-pixel dilation ring → `BORDER_COL` | **no** (deferred) | this is the 8bpp case |

**Why SCUMM does not adopt SCI's `TextLayer` now.** `HiResOverlay` already
stores what `TextLayer` stores for a single colour (index + coverage), and its
erase rules follow SCUMM's `_textSurface`/charset mask - the hard part, just
fixed again by C7. Swapping the plane would re-open that for no visible gain.
What SCUMM takes from SCI is the glyph side (sources, lazy TTF, proportional
advance) and the arithmetic (`TextCompose::blend()`), so the golden values
are shared. A later card may unify the planes.

## 6. `hires_text.map` for these engines

One file name, one parser (`graphics/hires_text/font_map.*`, byte-identical
rules of C5). Qualifiers stay engine-defined: SCUMM game id then `vN`, SCI
platform code, **AGS the game id** (`5daysastranger`), **Sword `sword1`/
`sword2`**, **Grim none**. Only one parser change: `[font.N]` learns
`bitmap=` (an SVFN file, relative to the map), parsed for everyone.

```ini
; AGS: 5 Days a Stranger, beside korean.tra and extfnt*.wfn
[encoding]
; the legacy .tra encoding when the .tra names none (default for a Korean .tra)
codepage=euc-kr
[hires]
; blend coverage in 16/32-bit games (default true when a map is present)
alpha=true
[fonts]
default=NanumGothic.ttf
[font.0]
face=default
size=12
[font.1]
; an SVFN coverage font instead of a TTF
bitmap=korean12.svfn
```

| Section / key | SCUMM applies | SCI applies | AGS applies | Grim applies | Sword applies |
|---|---|---|---|---|---|
| `[encoding] codepage` | yes (+ `utf8` now drives the byte scanners) | no | yes: `euc-kr`/`cp949` (legacy `.tra`), `utf8`, `ascii` (off) | yes: `utf8` for `grim.ko.tab` | no |
| `[hires] font`/`size` | **yes (new)** | yes | yes: every font id with no `[font.N]` | no (`.laf.txt` stays the per-font file) | yes: the Korean face; a path ending `.svfn` loads as SVFN |
| `[hires] alpha` | yes | no | yes | no (always blends) | no (hard edges) |
| `[fonts]` name table | **yes (new)** | yes | yes | no | yes |
| `[font.N] face`/`size` | **yes (new), N = charset id 0..19** | yes, N = SCI font id | yes, N = AGS font number | no | no |
| `[font.N] bitmap` (new) | yes | parsed, not applied (later) | yes | no | no |
| `[latin] mode`/`font`/`metrics`/`space` | **yes (new)** | yes | no (AGS fonts are proportional already) | no | no |
| `[glyphs]` + ranges | yes | no | no | no | no |

The shared parser already maps `euc-kr`, `ksc5601`, `cp949` and `uhc` to one
value (`kWindows949`, `graphics/hires_text/README.md`); AGS reads any of them
as the strict EUC-KR format of §3.1, since that is the only safe reading of
`.tra` data (Windows-1252 bytes next to ASCII).

Everything else keeps its row in `HIRES_COMPOSITOR_DESIGN.md` §2.2.
Precedence per setting, for every engine: ini key > `[font.N:<qual>]` >
`[font.N]` > `[hires:<qual>]`/`[hires]` > built-in default. Unknown keys warn
once and use the default; the map is never rejected whole.

### 6.1 ini keys

The existing `hires_text_font`, `hires_text_font_size`, `hires_text_map`,
`hires_text_log` get the same meaning in AGS and Sword (game domain only);
Grim keeps its `.laf.txt` files. One new key: `text_encoding` (AGS, SCUMM): `auto` (default) | `euc-kr`
| `cp949` | `utf8` | `ascii`, overriding detection and the map.

## 7. Per engine: the smallest change

### 7.1 SCUMM

- (a) **TTF**: `ScummHiResText` keeps one `TtfGlyphSource` per (path, pixel
  size) and draws from it lazily; `bakeCharset()`/`HiResFontBaker` leave the
  start-up path (the baker stays for the offline tool and its tests). The
  pixel size per charset is `[font.N] size` > `[hires] size` > the game cell ×
  scale, and the glyph is fitted to the cell as `TtfGlyphSource` does for SCI.
- (b) **8-bit bitmap**: SVFN files named by `[bitmap]` or `[font.N] bitmap`
  go through `SvfnGlyphSource`: same pixels as today, one code path.
- (c) **Unicode**: one engine helper, `ScummEngine::textCharLength(const byte
  *p, const byte *end)`, answers "how many bytes is this character" from the
  text code page (the map's, or CP949/932/936/950 from the language as now).
  Each `is2ByteCharacter()`/`checkKSCode()` boundary site calls it; with no
  UTF-8 page it returns exactly what the old test did. A UTF-8 `korean.trs`
  with the hi-res path **off** is transcoded to CP949 at load
  (`U32String::encode(kWindows949)`, lossless for Hangul), so the legacy
  `korean.fnt` path still draws it.
- **Proportional**: `[latin] mode=proportional` and `[render] metrics=font`
  advance each glyph by the face's own advance (SCI's `latinAdvanceGamePx()`, `textlatin.h`), so
  a TTF no longer looks letter-spaced in the game's cell.
- **Warnings**: the "names no [bitmap] fonts" warning is not printed when the
  map (or ini) names a TTF face; a missing `encoding.dat` gives one warning
  naming `--extrapath`, and the Hangul probe refuses a face that draws no
  Hangul, as for SCI.
- **MI2**: the SCUMM guide gains an MI2 map example keeping `0x5c=keep`,
  `0x60=keep`; a test pins it.

### 7.2 AGS

- (c) **EUC-KR text format** in `engines/ags/lib/allegro/unicode.cpp`: a new
  `U_EUCKR` entry in `utypes[]`. `getc`/`getx` return the Unicode code point
  of a KS X 1001 pair (both bytes `0xA1-0xFE`) and the byte itself otherwise;
  `setc` writes a code point back as a pair (reverse table) or one byte;
  `width`/`cwidth` are 2 for a pair. `init_translation()`
  (`translation.cpp:108`) selects it when the `.tra` has no `encoding` option
  **and** (`text_encoding=euc-kr`, or the map says so, or `text_encoding=auto`
  and the translation name is `korean` case-insensitively). Keys are left in
  the game's encoding (Lamplight City). `close_translation()` restores as
  today.
- (b1) **`extfntN.wfn`**: `WFNFont::ReadExtFromFile()` reads the 32-bit WFN
  variant into a second table; `WFNFontRenderer::LoadFromDiskEx()` opens
  `extfnt<N>.wfn` after `agsfnt<N>.wfn`. Glyph lookup is by code point:
  `< 256` → the base table as today; otherwise
  `ksx1001FromCodePoint(cp)` → the extension table when it holds 2350 glyphs.
  The font's height (`GetFontHeight()`, `FontMetrics`) becomes the larger of
  the base and the first Hangul glyph, so lines do not overlap.
- (b2) **SVFN**: `SvfnFontRenderer` (`engines/ags/shared/font/svfn_font_renderer.*`)
  implements `IAGSFontRendererInternal` over `SvfnGlyphSource`; it is chosen
  for font N when the map names `[font.N] bitmap=`.
- (a) **TTF**: `TTFFontRenderer` already works; the change is that a map's
  `[font.N] face=`/`size=` (or `hires_text_font`) makes font N load that path
  instead of `agsfnt<N>.ttf`/`.wfn`, with AA on when `[hires] alpha` is true and
  the game is 16/32-bit. alfont under `U_EUCKR` receives code points from
  `ugetx`; it already maps code points through FreeType's Unicode charmap.
- **Not taken from the fork**: the "break anywhere" rule (the patches put
  spaces between words, so AGS's whitespace wrapping holds - `[measured]` on
  the decoded samples only; a full scan for over-long unbroken runs is part of
  the AGS task); the KQ1-3 GUID list
  (it changes game behaviour and belongs to a translation, not the engine).

### 7.3 Grim

- `grim.cpp:277`: the renderer restriction is removed.
- `FontTTF::render()` for a TTF font produces an ARGB surface (alpha =
  coverage, RGB = the requested colour) and the TinyGL and shader renderers
  blit it with alpha blending instead of the colour key; the legacy OpenGL
  path is left as is. Korean and English TTF lines share the path; bitmap
  `.laf` fonts do not change.
- `.laf.txt` may name an `.svfn`; `FontTTF` then draws from
  `SvfnGlyphSource`, which is also the answer for a build without FreeType
  (today: a null `_font` and a crash) `[source]` `font.cpp:420-429`.
- `grim.ko.tab` with a UTF-8 BOM (or map `codepage=utf8`) decodes as UTF-8.

### 7.4 Sword1 / Sword2

- The Korean glyph lookup (`copyWChar()`, `wCharWidth()`,
  `FontRenderer::isKoreanChar()` and neighbours) goes through a
  `UnicodeGlyphSource`: by default an adapter over the appended
  `bs1k.fnt`/`bs2k.fnt` block (same pixels, KS X 1001 index), or a TTF/SVFN
  named by the map's `[hires] font=` (a `.svfn` path loads as SVFN) and
  `size=`. A TTF/SVFN glyph is stamped hard-edged: coverage ≥ 128 →
  `LETTER_COL`, the one-pixel ring around it → `BORDER_COL`, which is the
  look of the shipped font. Width stays 20 unless the map sets `size`.
- No alpha. No encoding change.

## 8. Compatibility

| Case | Required result | Proof |
|---|---|---|
| Any game, no map, no new ini key, no Korean legacy file | byte-identical frames to upstream | C6 capture, `seqcmp.py` i18n-C8 vs upstream `503d074778`: IDENTICAL-PREFIX, u vs u2 noise check |
| SCUMM Korean, no map | identical to `i18n` + C7 (the legacy `korean.fnt` path is untouched) | C6 group A captures, before vs after |
| SCUMM Korean, SVFN map (the hpz2 regress set) | identical glyph pixels (`SvfnGlyphSource` = old `HiResBitmapFont` path) | hpz2 regress baseline (user-run), plus a unit test comparing both paths' coverage |
| SCI | identical (only file moves) | KQ1-ko intro 0 px vs `runs/baseline-4a0f7f0e1c`, `make test` count |
| AGS, English or no translation | identical | C6 group C/D captures without `--language=ko` |
| AGS, Korean `.tra`, no extfnt/map | **changes on purpose**: mojibake becomes blanks (WFN base lacks Hangul) or Korean (TTF games) | frame diff expected; screenshot |
| AGS, Korean `.tra` + `extfntN.wfn` | Korean | screenshot; `ags_say` probe |
| Grim English | identical per renderer | TinyGL capture vs upstream |
| Grim Korean on legacy OpenGL | identical | not capturable headless `[unmeasured]`; the OpenGL path is not edited |
| Sword1/2, no map | identical (adapter returns the same bytes) | BS2 capture vs upstream; unit test on the adapter |

## 9. Verification method

- **Headless captures** with `runs/c6-tools/` (`c6add.sh`, `c6cap.sh`,
  `seqcmp.py`, `sheet.py`), both binaries built with
  `--enable-engines=scumm,scumm_7_8,sci,ags,sword1,sword2,grim --enable-freetype2`.
- **Games with data here** (`gamedata/kortrs/`): SCUMM `mi1ute mi2ute
  indy3vga indy4cd loomcd loomtowns samnmax` (patched), `mmv1 mmv2 zaktowns
  zakv2 ft` (unpatched copies); AGS `5days blackwell2-unbound
  blackwell3-convergence blackwell4-deception blackwell5-epiphany primordia
  shardlight kq1vga sq2vga winter` (Blackwell 1 is the wrong version: `.tra`
  game-ID mismatch); Grim `grim`; Sword `bs2` (BS1 is the re-release, Korean
  refuses to start). **No data**: 30minutes, Lamplight City, Zak2 fan game,
  BS1 original CD. hpz2 holds the SCUMM Korean regress set (user-run).
- **Reaching Korean text in mouse-driven games.** A capture without input
  shows title art. Three probes, in order of preference:
  1. **The debug socket, made engine-neutral** (`gui/debugsocket.*`, from
     `engines/sci/debugsocket.cpp`): `click x y`, `key`, `wait frames N`,
     `dump`, `save`/`load` work for every engine's console; SCI keeps its
     state commands as an extension. Deterministic: waits on frames, not
     wall time (`DEBUG_SOCKET.md`).
  2. **Engine text probes on the console**: AGS `ags_say <font> <key|#n>`
     looks a string up in the loaded `.tra` (by key substring or entry
     number) and shows it through `Display()`, so the real renderer draws
     Korean in the real game on frame one; Sword2's existing `texttest`;
     Grim's `lua_do`/`jump`.
  3. **Boot params and saves**: SCUMM `--boot-param` (C6: MI1 117, MI2
     8999, Loom Towns 1), Sword1/2 `boot_param`; `debug_record=` keeps a
     recorded session for replay.
- **Glyph-quality measure** (as SCI §5.1): distinct colours inside a text
  crop, 1bpp vs 8bpp vs TTF, and the glyph and raster counts from
  `hires_text_log`.

## 10. Risks

- **SCUMM UTF-8 buffer sizes** `[unmeasured]`: a Hangul syllable is 3 bytes in
  UTF-8 against 2 in CP949. Fixed buffers (`_charsetBuffer`, actor talk
  strings, verb names, save descriptions) may truncate. The UTF-8 task starts
  with an audit table of every fixed-size text buffer and its worst case.
- **AGS `U_EUCKR` and script string functions** `[unmeasured]`: AGS scripts
  that index translated strings by byte (`String.Chars[]`, `Length`) now see
  2-byte characters as one - the same semantics AGS gives UTF-8 games. Old
  games (AGS 2.7x, Blackwell 1-2) were written for single-byte text; the
  fork shipped the same semantics for years without reports, which is weak
  evidence.
- **AGS verification depth**: without the socket probe, only title screens
  are reachable; the task order puts the probe before the AGS tasks.
- **Grim**: no headless OpenGL here, so the legacy-OpenGL Korean path is
  unverifiable; it is not edited.
- **Moving SCI files** breaks nothing only if every include and the tests
  move together; the SCI invariant capture is the gate.
- **Upstreaming**: upstream's `AI-GUIDELINES.md` and the fork CI's
  `check-commit-authors.yml` (closes PRs whose commits carry an AI
  co-author trailer) constrain anything sent upstream, not the fork. AGS
  changes would also have to go to AGS upstream first (patch author's
  experience).

## Open questions

- Whether the AGS Korean `.tra` auto-detection (name `korean`, no encoding
  option) should be on by default (this design) or opt-in by ini key. On by
  default changes upstream's output for exactly one input, which upstream
  renders as mojibake.
- Whether Sword1/2 alpha (a compositor over the 8bpp screen) is ever worth a
  card.
- Data for 30minutes, Lamplight City, the Zak2 fan game and the original BS1
  CD.

## 11. Measured: the C8 matrix (plan 5 T11, done by C11 T10)

Plan 5's T11 (the matrix over groups A, C and D with and without the Korean
trigger) was replaced by C11 T10, which ran it on the merged `i18n`
`da78ab38fc` together with the Japanese and Thai columns. The table, runs
and crop sheets are in `I18N_TEXT_DESIGN.md` §9; in short `[measured]`:

- **Without the Korean trigger** (no translation, no map; the C6
  invariant): SCUMM groups A and B IDENTICAL-PREFIX to upstream
  `503d074778` or diverging only where upstream diverges from itself
  (Indy3, Loom Towns); AGS 5 Days IDENTICAL to upstream; the 32-bit AGS
  games (Blackwell 1-4, Primordia, Shardlight, Winter's Night, KQ1 VGA,
  SQ2 VGA) differ from upstream from frame 1 because of C10's 32-bit
  screen and are IDENTICAL to the pre-C11 `i18n` `6afdae3f3e`; Grim within
  noise.
- **With the Korean trigger** (the shipped patches): SCUMM group A with
  hi-res off IDENTICAL to both upstream and the pre-C11 build (the C6
  erase regression is gone since C7), the C6/C8 TTF and SVFN maps
  IDENTICAL to the pre-C11 build; AGS `ags_say` crops of 5 Days (fonts 0-2),
  Deception and Epiphany IDENTICAL to C11 T8 (and to C8 T7 in RGB565);
  Grim `grim.ko.tab` within T9's noise floor.
- **Found:** SCUMM v7 (Full Throttle) in a non-CJK language crashes at
  start on every fork build since the hires-text line's
  `peekGameCharsetHeight()` (`583aa2a8af`); upstream runs. Pre-C11, not a
  C8/C11 change (`I18N_TEXT_DESIGN.md` §9.2).
