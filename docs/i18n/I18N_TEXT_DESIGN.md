# An i18n text environment: any language by swapping the translation

Status: **built and merged, 2026-09-27: `i18n` `da78ab38fc` carries C11 T1-T9, T3b, T3c. The matrix on the merged build is §9 `[measured]`, what it does not do is §10.** Originally a design addendum, card C11 (`t_2780d454`);
written against `i18n` at `bee83518ad` (C8 T1, T2, T6 merged; C8 T3, T7, T9
and C10 running on their own worktrees). Its tasks are in
`I18N_TEXT_PLAN_6.md`, which replaces plan 5's T4, T5, T8, T10 and T11.

It builds on `HIRES_COMPOSITOR_DESIGN.md` (SCI's compositor and glyph
sources), `MULTI_ENGINE_TEXT_DESIGN.md` (C8: SCUMM, AGS, Grim, Sword),
`HIRES_TEXT_MAP.md` (the shared map) and `SCRIPT_STRINGS.md` (SCI's
`sci-<lang>.str`). It does not restart them.

`[source]` = read in code (file:line at `bee83518ad` unless another tree is
named). `[measured]` = observed by running or decoding something, with the
command or file named. `[unmeasured]` = a claim this document has not yet
earned.

## Goal

The user's reframe (2026-09-27, binding), verbatim:

> "Korean 패치가 아니라 i18n 환경을 만들고 텍스트만 지역화 하는 것을 원한다.
> 대사만 바꾸면 일본어든 태국어던 상관없이."

The fork builds an **i18n environment**. Only the text is localised: a
translator supplies UTF-8 text (and, if the game's fonts lack the script, a
font), and the same engine code and the same `hires_text.map` draw it,
whether it is Korean, Japanese or Thai. Concretely:

1. **Text** is UTF-8, found by the language code the player picks
   (`language=` in the ini, `--language=`), in a file named after that code.
2. **Glyphs** are looked up by code point, placed by **per-glyph advance and
   bearing**, with **zero-width combining marks** stacked on their base.
3. **Line breaking** follows the script, not the language setting: spaces,
   CJK any-character breaking with kinsoku, and a Thai fallback rule, all in
   **one shared layout stage** that every engine calls.
4. **Fonts** come from a fallback chain in the map, checked against the
   code points the loaded translation actually uses.

The Korean fan-patch formats (CP949 `korean.trs`, EUC-KR `.tra`,
`extfntN.wfn`, `korean.fnt`, KS X 1001 tables, `grim.ko.tab`, `bsNk.fnt`) are
**legacy compatibility**: they keep working exactly as they do on `i18n`
today, gated on their own files and code pages, and nothing new is designed
around them.

Two invariants:

- **C6:** with no translation, no map and no new key, every game is
  byte-identical to upstream (`runs/c6-tools/seqcmp.py`, IDENTICAL-PREFIX,
  u vs u2 noise check).
- **Legacy:** every shipped Korean patch renders exactly as it does on the
  build the task started from (KQ1-ko intro 0 px; MI1 UTE CP949
  IDENTICAL-PREFIX; 5 Days and Deception `ags_say` crops byte-identical).

## Out of scope (first pass)

- **RTL and bidi** (Hebrew, Arabic, Persian): excluded by the user. No RTL
  or bidi work at all; the existing upstream Hebrew hacks
  (`ScummEngine::reverseIfNeeded()`, `string.cpp:2525`; AGS
  `RightToLeft`) are untouched and not extended.
- **Complex shaping** (Devanagari, Khmer, Myanmar, Arabic joining; OpenType
  GSUB/GPOS in general): needs HarfBuzz, which ScummVM's `configure` does not
  offer (`grep -ci harfbuzz configure` = 0) `[measured]`. Scripts that only
  need **precomposed characters** (Vietnamese in NFC, Latin, Cyrillic,
  Greek) or **zero-width combining marks on a base** (Thai, Lao) are in.
- **Dictionary line breaking** for Thai/Lao/Khmer (ICU-style word lists):
  future; the first pass uses a character-class fallback (§4.3).
- **Typing** translated text (AGS text boxes, SCI edit controls, save names):
  display only.
- **Sword1/2**: their Korean is a resource replacement (`korean.clu` +
  `bsNk.fnt`); there is no text-override format to put another language in,
  so no i18n path exists to generalise. Plan 5's T10 is dropped (§7).
- **TTC face selection** (`file.ttc#2`): `Graphics::loadTTFFont()` opens face
  0 only (`graphics/fonts/ttf.h:107`, no index parameter) `[source]`. The
  harness extracts a face into a `.ttf` instead (plan Task 4).

## 1. i18n vs l10n review of the existing implementation

For each component on `i18n` today: is it **i18n** (works for any language
once text and fonts are supplied) or **l10n-only** (hard-wired to Korean or
CJK), why, and what would make it i18n.

| # | Component | Class | Why (evidence) | What makes it i18n (task) |
|---|---|---|---|---|
| R1 | SCI `TextLayer` + upscaled compositor (`textlayer.*`, `drivers/upscaled.cpp`) | **i18n** | ARGB coverage plane keyed by pixel, not by script; draws whatever the glyph source returns `[source]` | Nothing in the plane. Its **entry gate** is l10n: the upscaled driver is chosen by language rows `KO_KOR`/`JA_JPN` (`drivers/init.cpp:95-102`) and `getRenderMode()` special-cases `KO_KOR` (`init.cpp:125`) → gate on "a hi-res translation is active" (T5) |
| R2 | `GfxText16::readChar()` / `Width()` | **i18n (UTF-8), legacy (code page)** | UTF-8 decoded by the same `decodeUtf8Char()` the string ops use when `heapStringsAreUtf8()` (`text16.cpp:944`); code-page pairs via `isDoubleByte()` | Width sums `getCharWidth()` per character: combining marks get a cell each (R6) → per-glyph metrics (T1, T5) |
| R3 | `GfxText16::GetLongest()` line breaking | **l10n** | Breaks at the last space, else splits the word at width; kinsoku only for 2-byte **Shift-JIS packed pairs** (`text16.cpp:360-420`, tables at `:209-219`); the UTF-8 path "takes the plain word-split" - no kinsoku, and can split before a combining mark | Replace the UTF-8 branch by the shared layout stage (T2, T5); keep the SJIS branch verbatim for PC-98 releases |
| R4 | `SwitchToFont1001OnKorean()` / `SwitchToFont900OnSjis()` | **l10n legacy** | Byte patterns of KS X 1001 / SJIS leads (`text16.cpp:979-1070`); the UTF-8 branches already ask "any cp ≥ 0x80" | Keep; the UTF-8 branch is already language-neutral |
| R5 | `isJapaneseNewLine()` (PQ2 `\n`) | **l10n legacy** | `JA_JPN` + backslash escapes, PQ2 PC-98 only (`text16.cpp:1075`) | Keep |
| R6 | `UnicodeGlyphSource` cell model (`cells(cp)` ∈ {1,2} from East Asian Width) | **i18n lookup, l10n metrics** | Lookup is by code point (good). Metrics assume a CJK grid: `advanceNarrow`/`advanceWide`, no bearing, glyph origin at column 0 (`glyph_source.h`, `glyph_source_ttf.cpp:487`) so ink left of the origin is clipped `[source]`; a Thai mark gets a whole narrow cell | Per-glyph `GlyphMetrics` (advance, origin column, combining) with the cell model as the default for wide glyphs (T1) |
| R7 | `TtfGlyphSource::create(..., requireHangul)` and its probe set | **l10n** | Probe set = Hangul + Latin + CJK quotes (`glyph_source_ttf.cpp:228-237`); the only coverage check is "has Hangul"; the vertical fit ignores Thai above/below marks | Coverage and fit from the translation's own code points (T3) |
| R8 | `ScvmuniGlyphSource` (SCVMUNI) | **i18n repertoire, l10n metrics** | Any code point, but fixed narrow/wide cells and no per-glyph metrics (`SCVMUNI_FONT.md`) | Keep as a CJK format; non-CJK bitmap fonts use SVFN (per-glyph advance/bearing) |
| R9 | `SvfnGlyphSource` (SVFN v2) | **i18n** | Code-point table, per-glyph advance and bearing (`glyph_source_svfn.h`, C8 T1) | Expose bearing through `GlyphMetrics` (T1) |
| R10 | `RoutedGlyphSource` + `[latin]` modes (half / fullwidth / proportional) | **mechanism i18n, modes l10n** | Routing between two sources is generic; the modes are CJK typography (fullwidth remap to U+FF01.., fullwidth space) `[source]` `glyph_source_routed.h:39-56` | Generalise routing into an N-face fallback chain (T3); modes stay as options, default off |
| R11 | `latinAdvanceGamePx()` | **i18n rule, applied to ASCII only** | Face advance → game px, rounded up (`latin_advance.h`) | Apply to every non-wide, non-combining code point (T1, T5, T6) |
| R12 | `hires_text.map` parser (`font_map.*`) | **mostly i18n** | Faces by name/path, sizes, per-font-id sections; `[encoding] codepage=` names legacy pages; `[latin]` is CJK-centric; no fallback chain, no `bitmap=` | `face=` chains, `[font.N] bitmap=`, `[layout]` (T3); `[encoding]` stays legacy |
| R13 | SCI ini gates (`cache.cpp:56-71 hiresTextFontApplies()`) | **l10n** | `hires_text_*` and the map are honoured only for code pages 949/932/936/950 `[source]`; a Thai or Japanese-UTF-8 translation on an English release gets "the game's language has no hi-res CJK text" | Gate on "a UTF-8 translation is loaded" or a legacy CJK page (T5) |
| R14 | `ADGF_UTF8I18N` (`detection.h:52-64`) | **l10n in practice** | The UTF-8 decision is a detection-entry flag matched by the MD5 of a patched `text.000` (`detection_tables.h:1681-1688`); a Japanese `text.000` has another MD5, fails that entry, and is detected as English | Also accept the translation's own manifest: `sci-<lang>.str` present for the chosen language (T5); the flag stays for known entries |
| R15 | `sci-<lang>.str` (`ScriptStrings`) | **i18n** | Named by `Common::getLanguageCode(getLanguage())` (`sci.cpp:316`, `translation.cpp:34`), UTF-8 by definition | Needs language codes for Thai/Vietnamese (R37) |
| R16 | `SciEngine::getLanguage()` ini override | **i18n** | `language=` beats detection (`sci.cpp:1087`) | - |
| R17 | `usesHiresDoubleByteText()` | **l10n** | True for `KO_KOR`, the Text.MAP overlay, PQ2 PC-98 (`sci.cpp:1016-1027`) | Also true when `heapStringsAreUtf8()` (T5) |
| R18 | SCUMM `ScummHiResText::decodeNext()` / `charLength()` | **i18n** | Decodes UTF-8 or a named code page to a code point (`hires_text.cpp:1461-1530`) | Moves into the shared decoder (T2) |
| R19 | SCUMM `defaultEncodingFor(language)` | **l10n legacy** | KO/JA/ZH → CP949/932/936/950 (`hires_text.cpp:1266`) | Keep for legacy bundles; a UTF-8 bundle overrides it (T7) |
| R20 | SCUMM bake-at-load (`bakeCharset()`, `HiResFontBaker::hangulSyllables()`/`chineseCodePage()`) | **l10n** | Bakes the KS X 1001 / GB / Big5 repertoire of the language's code page (`hires_text.cpp:1143-1153`) - a Thai or Japanese-UTF-8 translation gets nothing baked | Removed from start-up by C8 T3 (lazy sources, running) |
| R21 | SCUMM `advanceFor()` | **l10n** | Glyphs sit in the game's fixed cell; TTF text looks letter-spaced (C6 finding) | Per-glyph advance (T6, was plan 5 T4) |
| R22 | SCUMM `loadCJKFont()`, `isScummvmKorTarget()`, `drawBits1Kor()`, `korean.fnt` | **l10n legacy** | `_language == KO_KOR` etc. (`charset.cpp:48-160`) | Keep; a UTF-8 bundle does not enter these paths (T7) |
| R23 | SCUMM `addLinebreaks()` | **l10n** | CJK: every `chr & 0x80` is a 2-byte char of `_2byteWidth`; Korean "break anywhere" via `checkKSCode()` (`charset.cpp:686-750`) | UTF-8 text uses the shared layout stage (T7); the byte path stays for legacy |
| R24 | SCUMM `is2ByteCharacter()` scanners (`string.cpp:1265,1542,1698`, `string_v7.cpp:79,136,168`) | **l10n** | DBCS lead-byte tests by language | `textCharLength()` (UTF-8 or the old expression) (T7) |
| R25 | SCUMM josa / verb glue (`string.cpp:1805-1990`) | **l10n by nature** | Korean grammar (postposition variants), not rendering | Keep, Korean-only; other languages do not need it |
| R26 | SCUMM `.trs` naming (`trs_bundle.h:46-73`) | **i18n** | `<code>.trs` for every language; `korean.trs` kept for Korean | The format has no encoding field (`string.cpp:2360-2366`): add a UTF-8 marker (T7) |
| R27 | AGS `U_EUCKR` (C8 T6, `unicode_euckr.*`, `translation.cpp:61-82`) | **l10n legacy** | Gated on a `.tra` named `korean` with no `encoding` option | Keep as is |
| R28 | AGS native `U_UTF8` + `.tra encoding=utf-8` | **i18n** | Upstream AGS 3.x; renderers iterate code points with `ugetxc()` (`translation.cpp:136-141`) | Already the primary path |
| R29 | AGS `WFNFontRenderer` + `extfntN.wfn` (C8 T7) | **l10n legacy** | 1-byte glyph table; the extension is indexed by KS X 1001 Hangul order | Keep; UTF-8 text uses TTF/SVFN fonts from the map (T8) |
| R30 | AGS `TTFFontRenderer` (alfont) | **i18n glyphs, game-bound fonts** | FreeType by code point, but only `agsfntN.ttf` of the game | Fonts per translation from the map (T8, was plan 5 T8) |
| R31 | AGS `split_lines()` (`fonts.cpp:343`) | **half i18n** | Breaks at the last space, else "display as much as possible" at the previous character - char-wrapping for ja by accident, no kinsoku, may split before a Thai mark | Shared layout stage for non-ASCII formats (T8) |
| R32 | Grim `grim.ko.tab` / FontTTF CP949 / `isKoreanChar` split | **l10n legacy** | `KO_KOR` names the file and the decoder (`localize.cpp:43,58`, `font.cpp:443-470`, `textobject.cpp:221`) | Keep for `grim.ko.tab`; generalise file naming to `grim.<code>.tab` (T9) |
| R33 | Grim UTF-16LE tab → `_isUtf8` + `setupTextReal<U32String>` | **i18n** | Already a code-point array per line (`localize.cpp:109-116`, `textobject.cpp:331`); but the word split appends `-` except for Chinese (`textobject.cpp:248`) | Accept a UTF-8 BOM; shared layout stage (T9) |
| R34 | Grim renderer restriction for Korean (`grim.cpp:277`) | **l10n** | Removes TinyGL/shaders for `KO_KOR` | C8 T9 (running) lifts it |
| R35 | Sword1/2 Korean (`korean.clu`, `bsNk.fnt`, `isKoreanChar()`) | **l10n** | Resource replacement; no text override format | Out of scope (§7) |
| R36 | `graphics/hires_text/codepage_kr.*` | **l10n legacy helper** | KS X 1001 tables for the legacy formats | Keep |
| R37 | `Common::Language` | **l10n gap** | No Thai, no Vietnamese in the enum (`common/language.h:43-84`) `[measured]`: `language=th` parses to `UNK_LANG`, so `th.trs`, `sci-th.str` and AGS `--language=th` cannot be named | Append `TH_THA` ("th") and `VI_VNM` ("vi") (T1) |
| R38 | Debug socket (`gui/debugsocket.*`, C8 T2) | **i18n** | Engine-neutral commands, `ags_say` by key or index | - |
| R39 | Harness (`runs/c6-tools`, `harness/i18n/kq1_*.py`, `m12mkpatch.py`) | **i18n tools, l10n data** | Tools are text-agnostic; every baseline is Korean or English | ja/th sample data and baselines (T4) |

Counts (39 components): **i18n 9** (R1, R9, R15, R16, R18, R26, R28, R33,
R38); **mixed 9** (R2, R6, R8, R10, R11, R12, R30, R31, R39: a generic
mechanism with CJK-only metrics, gates or data); **l10n 21**, of which **9
stay as legacy compatibility** (R4, R5, R19, R22, R25, R27, R29, R32, R36),
**1 is out of scope** (R35 Sword) and **11 are generalised** (R3, R7, R13,
R14, R17, R21, R23, R24, R37 by C11; R20 and R34 by the running C8 T3 and T9).

## 2. Audit of language-specific sites

The grep of the brief,

```
git grep -n -i -E 'hangul|ksx1001|kWindows949|cp949|949|932|936|950|johab|korean|fullwidth|kinsoku|is2ByteCharacter|checkKSCode|requireHangul|eucKr|EUCKR|latin' -- \
  graphics/hires_text engines/sci/graphics engines/sci/detection.h engines/scumm/hires_text.* \
  engines/scumm/charset.cpp engines/scumm/string.cpp engines/scumm/string_v7.cpp \
  'engines/ags/lib/allegro/unicode*' engines/ags/engine/ac/translation.cpp engines/ags/shared/font \
  engines/grim/localize.cpp engines/grim/font.cpp engines/grim/grim.cpp gui/
```

gives **1,000 lines** at `bee83518ad` `[measured]`; most are comments and the
`[latin]` option plumbing (`cache.cpp` 103, `font_map.cpp` 95,
`hirestextsettings.cpp` 45). `gui/` hits are theme SVG/credits text and
`debugsocket.cpp`'s comment: none is a text-path assumption. Grouped by
site (one row per decision, not per line):

| # | Site | Assumption | Class | Replacement (exact) | Task |
|---|---|---|---|---|---|
| A1 | `engines/sci/graphics/cache.cpp:56-71` `hiresTextFontApplies()` | hi-res keys only for code pages 949/932/936/950 | GENERALISE | `applies = (SCI16) && (g_sci->heapStringsAreUtf8() \|\| isLegacyCjkPage(page))`; message "no translation and no CJK code page" | T5 |
| A2 | `cache.cpp:345` `requireHangul = page == kWindows949` | a Korean game needs Hangul in its face | GENERALISE | `CoverageReport r = checkCoverage(chain, g_sci->translationCodePoints())`; one warning naming the count and first 5 missing (§4.4); legacy `requireHangul` kept only when no UTF-8 translation is loaded | T3, T5 |
| A3 | `cache.cpp:514-604` `korean.fnt` / `GfxFontKorean` / font 1001 | legacy Korean font | KEEP | gated on `korean.fnt` existing, as today | - |
| A4 | `cache.cpp:101-384`, `hirestextsettings.*` `hires_text_latin*` | CJK Latin aesthetics | KEEP (option) | unchanged; default off; the gate A1 decides when they are read | - |
| A5 | `engines/sci/detection.h:52-64` `ADGF_UTF8I18N` | UTF-8 ⇔ an MD5-matched entry | GENERALISE | `heapStringsAreUtf8() = !overlay && (flag \|\| (languageForced && _scriptStrings.isPresent()))` - the `sci-<lang>.str` is the manifest (§4.1) | T5 |
| A6 | `engines/sci/sci.cpp:1016-1027` `usesHiresDoubleByteText()` | hi-res plane ⇔ KO / overlay / PQ2-98 | GENERALISE | `\|\| heapStringsAreUtf8()` | T5 |
| A7 | `drivers/init.cpp:95-102` driver rows `KO_KOR`, `JA_JPN`; `:125` `getRenderMode()` | upscaled driver by language | GENERALISE | one row matched by predicate `g_sci->usesHiresDoubleByteText()` (new column `kHiresText`); the KO/JA rows stay for byte-identity of their games | T5 |
| A8 | `text16.cpp:209-219, 360-420` SJIS kinsoku tables | SJIS packed pairs | KEEP (legacy) | code-page path untouched; the shared table (§4.3) is the SCI01 table converted to code points | T2 |
| A9 | `text16.cpp:442-450` UTF-8 word split | no kinsoku, may split before a mark | GENERALISE | `Graphics::TextLayout::fitLine()` on a `TextRun` (§3) | T5 |
| A10 | `text16.cpp:979-1070` font 1001/900 switches | KS X 1001/SJIS byte patterns | KEEP | UTF-8 branches unchanged | - |
| A11 | `text16.cpp:1075` `isJapaneseNewLine()` | PQ2 `\n` | KEEP | - | - |
| A12 | `text16.cpp:311,473,607` `0xFF20` fullwidth `@` break | SQ4 Japanese | KEEP | also recognised as a control unit by SCI's decoder (§3.3) | T5 |
| A13 | `fontunicode.cpp:240-290`, `fontset.cpp:74-251` width = cells × narrow | CJK grid for every non-ASCII glyph | GENERALISE | `advanceGame(cp)`: wide → cells rule (today); combining → 0; other → `latinAdvanceGamePx(kHiResMetricsFont, gameW, m.advance, scale)` (§4.2) | T1, T5 |
| A14 | `fontunicode.cpp:106`, `screen.cpp:495` `putHangulChar` coordinates | legacy face | KEEP | - | - |
| A15 | `text32.cpp:344,800,954` SCI32 Korean switch | GK1 Korean | KEEP | SCI32 stays out (A1) | - |
| A16 | `graphics/hires_text/glyph_source_ttf.cpp:228-237,376` Hangul probes, `requireHangul` | Korean coverage; fit ignores marks | GENERALISE | `create(stream, dispose, px, error, const uint32 *fitProbes = nullptr, uint fitProbeCount = 0)`; `requireHangul` becomes a legacy wrapper that passes the old probe set and checks it | T1, T3 |
| A17 | `glyph_source_ttf.cpp:474-487` origin at column 0; `cells = isWide ? 2 : 1` | no negative bearing, all glyphs in cells | GENERALISE | render at `originX = pad` (§4.2); `metrics(cp, GlyphMetrics&)` | T1 |
| A18 | `glyph_source_ttf.cpp:174` `isWide()` (EAW table) | - | KEEP, moved | `Graphics::Unicode::isWide()` in `unicode_props.*`; `TtfGlyphSource::isWide()` forwards | T1 |
| A19 | `glyph_source_routed.*`, `text_compose` `latinFullwidth()` | fullwidth remap | KEEP (option) + GENERALISE routing | `FallbackGlyphSource(Array<UnicodeGlyphSource*>)` for chains; Routed stays for `[latin]` | T3 |
| A20 | `font_map.cpp:179-189` `parseCodePage()` | legacy pages | KEEP | `utf8` stays accepted | - |
| A21 | `bitmap_font.cpp:226-317` SVFN v1 code-page index | legacy v1 | KEEP | v2 is code-point indexed | - |
| A22 | `font_baker.cpp:163-195` `hangulSyllables()`, `chineseCodePage()` | bake repertoire by page | KEEP (offline tool) / REMOVE from start-up | start-up bake removed by C8 T3; the baker also takes a `CodePointSet` from a translation (§4.4) | C8 T3, T3 |
| A23 | `codepage_kr.*` | KS X 1001 | KEEP | - | - |
| A24 | `engines/scumm/hires_text.cpp:58-65, 1266-1280` `defaultEncodingFor()` | language ⇒ page | KEEP (legacy) | a UTF-8 bundle sets `kUtf8` first (§4.1) | T7 |
| A25 | `hires_text.cpp:1143-1153` `bakeCharset` repertoires | Hangul / GB / Big5 | REMOVE | C8 T3 (running) | C8 T3 |
| A26 | `hires_text.cpp:1319, 1396, 1408` `korean_ttf_map`, `korean_hires_scale`, `korean_alpha_text` | old Korean ini names | KEEP (deprecated aliases, warn) | - | - |
| A27 | `hires_text.cpp:1461-1530` `charLength()`/`decodeNext()` | - (already generic) | GENERALISE (move) | `Graphics::CodePageTextDecoder` / `Utf8TextDecoder` in `text_layout.*` | T2, T7 |
| A28 | `charset.cpp:48` `isScummvmKorTarget()`, `:60-240` `loadCJKFont()`/`loadKorFont()` | KO ⇒ korean.fnt | KEEP | not entered for a UTF-8 bundle (`_textUtf8` short-circuits `loadCJKFont()` to the hi-res layer) | T7 |
| A29 | `charset.cpp:686-750` `addLinebreaks()` CJK + Korean break-anywhere | DBCS, KS X 1001 | KEEP (legacy) + GENERALISE | `_textUtf8` → `addLinebreaksLayout()` on the shared stage; byte path unchanged otherwise | T7 |
| A30 | `charset.cpp:760-770` `getCharWidth()` → `advanceFor()` | cell width | GENERALISE | per-glyph advance from `GlyphMetrics` (§4.2) | T6 |
| A31 | `charset.cpp:779, 992-1743` `drawBits1Kor`, `_sjisCurChar` | legacy | KEEP | - | - |
| A32 | `string.cpp:1265, 1542, 1698`, `string_v7.cpp:79, 136, 168` `is2ByteCharacter()` | DBCS | GENERALISE | `int ScummEngine::textCharLength(const byte *p, const byte *end) const` = UTF-8 length when `_textUtf8`, else the old expression | T7 |
| A33 | `string.cpp:1805-1990` josa / `checkKSCode` | Korean grammar | KEEP (Korean-only by nature) | not reached unless `isScummvmKorTarget()` | - |
| A34 | `string.cpp:2108-2114` Dig language.tab `h`/`j`/`c` lines | original data | KEEP | - | - |
| A35 | `string.cpp:2536-2544` `getDialogCodePage()` | language ⇒ page | KEEP + GENERALISE | `_textUtf8` → `kUtf8` | T7 |
| A36 | `trs_bundle.h:46-73` `korean.trs` special case | Korean name | KEEP | `<code>.trs` for all others; needs TH/VI codes (A45) | T1 |
| A37 | `engines/ags/lib/allegro/unicode_euckr.*`, `unicode.cpp:58`, `unicode.h:34-36` | EUC-KR | KEEP | - | - |
| A38 | `translation.cpp:61-82` `select_legacy_tra_uformat()` `korean` ⇒ EUC-KR | legacy | KEEP | a `.tra` with `encoding=utf-8` never reaches it | - |
| A39 | `ags/shared/font/wfn_font*` extfnt (C8 T7, running) | KS X 1001 index | KEEP | - | C8 T7 |
| A40 | `ags/shared/font/fonts.cpp:343` `split_lines()` | spaces, else previous char | GENERALISE | non-ASCII `uformat` → `Graphics::TextLayout::breakLines()` with an AGS `LayoutMetrics` over `get_text_width_outlined()`; ASCII path unchanged | T8 |
| A41 | `engines/grim/localize.cpp:43, 58` `grim.ko.tab` | KO name | GENERALISE | `grim.<code>.tab` for the forced language when present, `grim.ko.tab` kept | T9 |
| A42 | `localize.cpp:92-120` magic switch | no UTF-8 BOM | GENERALISE | `EF BB BF` → strip, `_isUtf8 = true` | T9 |
| A43 | `grim/font.cpp:443-470` `KO_KOR` ⇒ CP949 | legacy | KEEP | only when the tab is not UTF-8 | T9 |
| A44 | `grim.cpp:277` renderer restriction | Korean ⇒ OpenGL | REMOVE | C8 T9 (running) | C8 T9 |
| A45 | `common/language.{h,cpp}` | no Thai, no Vietnamese | GENERALISE | append `TH_THA {"th","th_TH","Thai"}`, `VI_VNM {"vi","vi_VN","Vietnamese"}` after `ZH_TWN` (no renumbering) | T1 |

Counts (45 sites, one primary class each): **KEEP 23** (A3, A4, A8, A10,
A11, A12, A14, A15, A18 (moved), A20, A21, A23, A24, A26, A28, A31, A33, A34,
A36, A37, A38, A39, A43); **GENERALISE 19** (A1, A2, A5, A6, A7, A9, A13,
A16, A17, A19, A27, A29, A30, A32, A35, A40, A41, A42, A45; A19, A29 and A35
keep their legacy half); **REMOVE 3** (A22's start-up half, A25, A44 - the
last two are C8 T3 and T9, already running).

## 3. The text unit: one shared layout stage on code points

### 3.1 Decision

The user's intent (2026-09-27): "금칙 처리등을 일관되게 처리하려고
1문자=1단위(uint32)등을 쓰려고 했다. UTF-8 이라도 줄바꿈 처리등을 제네랄하게
처리할 수 있다면 OK" - one character = one uint32 unit so kinsoku and line
breaking are handled consistently; UTF-8 storage is fine if breaking and
measuring are general.

**Decision L1: storage stays bytes; layout runs on a code-point array.**
A shared stage in `graphics/hires_text/text_layout.{h,cpp}` decodes an
engine string **once per layout call** into a `TextRun` (uint32 code points
plus the byte offset of each), runs breaking, measuring and line assembly on
that array, and hands back line spans **mapped to byte offsets**. Engines
keep bytes in their VMs, buffers and saves (plan 5's E3 stands); every engine
shares **one** breaker, **one** kinsoku table and **one** test suite.

Why not UTF-8 in-place iteration: every engine already iterates bytes in
place, and that is exactly what produced four different break rules (SCI
space/SJIS-kinsoku, SCUMM DBCS + Korean anywhere, AGS previous-char, Grim
Korean pair + dash). Breaking needs look-behind and look-ahead by *character*
(kinsoku: "not before `」`", "not after `「`"; Thai: "not after a leading
vowel", "not before a mark"), which on UTF-8 bytes means re-decoding
backwards - SCI's SJIS kinsoku walks back two bytes at a time and only works
because SJIS pairs are fixed-width (`text16.cpp:363-367` says so) `[source]`.
On an array it is `cp[i-1]`, `cp[i+1]`. Why not UTF-32 in the VM: plan 5 E3
(every buffer and save changes).

**Where in-place stays:** the legacy byte paths (SCI SJIS kinsoku, SCUMM
CP949 `addLinebreaks`, AGS ASCII `split_lines`, Grim `grim.ko.tab`) keep
their code, because the Legacy invariant is byte-identity and the new stage
would change break positions in edge cases. Grim needs no new decode step:
its UTF-8 path already builds a `U32String` per line (`textobject.cpp:331`)
`[source]`, so it wraps it in a `TextRun` without re-decoding.

**Cost:** one `Common::Array<uint32>` + `Array<uint32>` offsets + `Array<byte>`
flags per laid-out string, reused as members to avoid per-call allocation.
SCI calls `GetLongest()` once per line per `Size()`/`Draw()`; a 300-byte
dialogue string decodes in O(n) each time. `[unmeasured]`: the per-call
time; T5 measures `GetLongest()` total ms over the KQ1-ko intro before/after
and must stay within 10 %.

### 3.2 Interface

```cpp
namespace Graphics {

/** Flags of one unit of a TextRun. */
enum TextUnitFlags {
	kUnitControl   = 1 << 0,  ///< an engine escape: opaque, zero width, never split
	kUnitNewline   = 1 << 1,  ///< forces a line break after this unit
	kUnitSpace     = 1 << 2,  ///< a break opportunity that is dropped at a line end
	kUnitCombining = 1 << 3,  ///< Unicode Mn/Me: zero advance, attaches to the previous base
	kUnitWide      = 1 << 4   ///< East Asian Wide/Fullwidth
};

/** cp value of a control unit; the engine's escape code is in the bytes. */
static const uint32 kControlUnit = 0xFFFFFFFFu;

/** Turns engine bytes into units. Engines subclass it to recognise escapes. */
class TextDecoder {
public:
	virtual ~TextDecoder() {}
	/**
	 * Decode the unit at p (p < end). Returns the bytes it spans, >= 1, never
	 * past end. Sets cp (kControlUnit for an escape) and flags (kUnitControl,
	 * kUnitNewline); the run adds kUnitSpace/kUnitCombining/kUnitWide itself.
	 */
	virtual int decode(const byte *p, const byte *end, uint32 &cp, byte &flags) const = 0;
};

/** UTF-8; an invalid or truncated sequence is one unit of U+FFFD, 1 byte. */
class Utf8TextDecoder : public TextDecoder { ... };

/** A legacy code page (SCUMM's charLength() rule, moved from hires_text.cpp:1461). */
class CodePageTextDecoder : public TextDecoder {
public:
	explicit CodePageTextDecoder(Common::CodePage page);
	...
};

class TextRun {
public:
	/** Decode [text, text+len) with dec. Clears the run first; keeps capacity. */
	void decode(const byte *text, uint32 len, const TextDecoder &dec);
	/** Build from code points already decoded (Grim); offsets are unit indices. */
	void assign(const Common::U32String &text);
	uint32 size() const;
	uint32 cp(uint32 i) const;
	byte flags(uint32 i) const;
	/** Byte offset of unit i; byteOffset(size()) is the total length. */
	uint32 byteOffset(uint32 i) const;
private:
	Common::Array<uint32> _cp, _offset;
	Common::Array<byte> _flags;
};

/** What the engine measures with, in its layout units (game px). */
class LayoutMetrics {
public:
	virtual ~LayoutMetrics() {}
	/** Advance of cp; 0 for combining marks and control units. */
	virtual int advance(uint32 cp) = 0;
	/** Width of units [from, to). Default: sum of advance(). AGS overrides
	 *  (outline, kerning); SCI and SCUMM use the default. */
	virtual int width(const TextRun &run, uint32 from, uint32 to);
	/** Width of [from, i+1) given widthSoFar = width of [from, i). fitLine()
	 *  keeps a running width through it, so a line costs O(L) advance() calls.
	 *  Default: widthSoFar + advance(cp(i)), unchanged for control units and
	 *  combining marks. Non-additive metrics (AGS: outline, kerning) override
	 *  it with width(run, from, i + 1). Not const, like advance()/width(). */
	virtual int extend(const TextRun &run, uint32 from, uint32 i, int widthSoFar);
};

enum HangulBreak { kHangulBreakWord = 0, kHangulBreakAny = 1 };

struct BreakRules {
	HangulBreak hangul;       ///< word: Hangul breaks at spaces (like Latin); any: like CJK ideographs
	bool kinsoku;             ///< apply the shared kinsoku table (§4.3)
	bool thaiFallback;        ///< Thai syllable-segment breaks (§4.3, C16)
	BreakRules() : hangul(kHangulBreakWord), kinsoku(true), thaiFallback(true) {}
};

struct LineSpan {
	uint32 first, end;        ///< units drawn on this line: [first, end), trailing spaces excluded
	uint32 next;              ///< first unit of the next line (after dropped spaces / the newline)
	uint32 byteStart, byteEnd, byteNext;  ///< the same three, as byte offsets
	int width;                ///< ink width: width() of [first, end) minus the spaces and escapes at its end
	bool forced;              ///< ended by a kUnitNewline unit
	bool emergency;           ///< no break opportunity fitted: split at a cluster boundary
};

namespace TextLayout {
/** Whether a line may end between unit i-1 and unit i (0 < i < size). */
bool canBreakBefore(const TextRun &run, uint32 i, const BreakRules &rules);
/** Not between a base and its combining marks, never inside a control unit sequence. */
bool isClusterBoundary(const TextRun &run, uint32 i);
/** The longest line starting at from that fits maxWidth (at least one cluster). */
LineSpan fitLine(const TextRun &run, uint32 from, int maxWidth, LayoutMetrics &m, const BreakRules &rules);
/** All lines. */
void breakLines(const TextRun &run, int maxWidth, LayoutMetrics &m, const BreakRules &rules,
                Common::Array<LineSpan> &out);
}

} // namespace Graphics
```

`fitLine()` is SCI's `GetLongest()` contract (returns where the line ends and
where the next begins); `breakLines()` is AGS's and Grim's; SCUMM's
`addLinebreaks()` calls `fitLine()` repeatedly and writes its own `0x0D`
at `byteEnd` (the existing space-replacement or `memmove` insert).

The legacy (CP949) Korean path of `addLinebreaks()` inserts its breaks with
`insertLinebreak()` (C13): the string length grows by one per insert and an
insert that would run past the caller's buffer is refused (the line then
breaks at its last space, or stays long). Before C13 the second insert
overwrote the terminating NUL and the third dropped the last character;
legacy frames changed only for lines with two or more inserts, which were
corrupt before. The same fix is prepared for upstream
(`runs/c13/upstream.patch`, not sent).

### 3.3 Escapes that must survive decoding

Each engine's decoder turns its escapes into `kControlUnit` units that span
exactly the escape's bytes, so they are never split, never measured, and
come back at the same byte offsets:

| Engine | Escapes (source) | Unit |
|---|---|---|
| SCUMM v4-6 | `0xFF`/`0xFE` + code (+2 arg bytes for 10, 12, 13, 14, 21) (`charset.cpp:640-672`); `@` (skipped); `_newLineCharacter` | control; codes 1 (newline) and 8 (verb next line) also `kUnitNewline`; `@` a zero-width control |
| SCUMM HE ≥ 72 | `@`/`0x7F` + letter sequences (`charset.cpp:630-640`) | control (HE stays out of scope for UTF-8; decoder exists for completeness) |
| SCI16 | `\|c1\|`-style codes via `CodeProcessing()` for SCI1.1 (`text16.cpp:289-294`); `0x0D`, `0x0A`, `0x0D 0x0A`; `0xFF20` (A12) | codes: control spanning to the closing `\|`; line ends: `kUnitNewline` |
| AGS | `[` = newline unless `\[` (resolved by `unescape_script_string()` before `split_lines()`, `fonts.cpp:355`) | `\n` after unescape → `kUnitNewline` |
| Grim | `\n` in the message | `kUnitNewline` |

UTF-8 never contains a byte < 0x80 inside a multi-byte sequence and never
contains `0xFE`/`0xFF` `[source]` (RFC 3629), so the escape scan is
unambiguous for UTF-8, unlike CP949 whose trail bytes include `0x5C` and
`0x60` (the MI2 case, `MULTI_ENGINE_TEXT_DESIGN.md` §3.1).

## 4. The language-neutral pipeline, per layer

### 4.1 (a) Translation text: UTF-8, named by the language code

Selection is always by the language the player picks (`language=` in the
game's ini domain or `--language=`), through `Common::getLanguageCode()`;
Thai and Vietnamese need A45. Per engine:

| Engine | UTF-8 translation file | How it is marked UTF-8 | Legacy recognised as |
|---|---|---|---|
| SCI16 | TEXT resources as `text.NNN` patch files (UTF-8 inside, `m12mkpatch.py`) + `sci-<lang>.str` (`SCRIPT_STRINGS.md`) | **manifest = `sci-<lang>.str` for the forced language** (may hold only comments); or the `ADGF_UTF8I18N` entry (KQ1-ko). KQ1-ko's `text.000` has no BOM: it starts `83 00 22 ec b5 9c` `[measured]` (`xxd gamedata/kq1-ko1/text.000`), so a BOM rule would miss the existing data | `Text.MAP`/`Text.Res` overlay (CP949), or a detected `KO_KOR`/`JA_JPN` entry without the flag (CP949/SJIS resources) |
| SCUMM (v1-v6, FT) | `<code>.trs` (`ja.trs`, `th.trs`; `korean.trs` stays the Korean name) | **the body starts with `EF BB BF`** (the three bytes after the room table, before the first string; no entry points at them) or ini `text_encoding=utf8`. The `SCVMTRS ` magic is at byte 0 `[measured]` (`xxd korean.trs`), so the BOM cannot be the file's first bytes | no BOM: `defaultEncodingFor(language)` (CP949 for Korean). An unmarked body that validates as UTF-8 with ≥ 1 multi-byte sequence logs one hint: "looks like UTF-8; add a BOM or text_encoding=utf8" |
| AGS | `<name>.tra` compiled per language (the AGS editor's `.trs` → `.tra`), selected by `[language] translation=` in `acsetup.cfg` or `--language=` (description lower-cased, `config.cpp:332-345`) | the `.tra`'s own `ext_sopts` `encoding=utf-8` (upstream AGS, `translation.cpp:132-141`) | no `encoding` option + name `korean` → EUC-KR (C8 T6) |
| Grim | `grim.<code>.tab` (`grim.ja.tab`), for the forced language | `EF BB BF` at the start (new) or the existing UTF-16LE `FF FE` (`localize.cpp:109`) | `grim.ko.tab` without BOM → CP949 as today |

SCI's manifest rule in code (`sci.cpp:1029`):

```cpp
bool SciEngine::heapStringsAreUtf8() const {
	if (_textOverlay.isLoaded())
		return false;                                   // legacy CP949 overlay
	if (_gameDescription->flags & ADGF_UTF8I18N)
		return true;                                    // known entries (KQ1-ko)
	return ConfMan.hasKey("language") && _scriptStrings.isPresent();  // the manifest
}
```

Today a table with zero entries is *not* loaded: `_loaded =
!_entries.empty()` (`engine/translation.cpp:104`) `[source]`. T5 adds
`ScriptStrings::isPresent()` (the file was found and parsed, entries or not)
and the manifest rule asks that, so a translation whose scripts need no
string can ship a comments-only `sci-<lang>.str`.

**At load, every engine collects the translation's code-point set**
(`Graphics::CodePointSet`, §4.4): SCI from the `text.NNN` patches and the
`.str`; SCUMM from the bundle body; AGS from the `.tra` values; Grim from the
tab values. It feeds the coverage check and the vertical fit.

### 4.2 (b) Glyphs: per-glyph advance, bearing and combining marks

Code points at the glyph interface already hold (C8 T1). What changes is
**metrics**. The cell model (`cells(cp)` ∈ {1,2}) becomes the default for
East-Asian-Wide glyphs only; everything else is placed by the face.

```cpp
namespace Graphics {
struct GlyphMetrics {
	int16 advance;     ///< source px; 0 for a combining mark
	int16 originX;     ///< column of the pen origin inside row(cp, y); ink may lie left of it
	bool combining;    ///< Unicode::isCombining(cp)
	bool wide;         ///< Unicode::isWide(cp)
};
class UnicodeGlyphSource {
	...
	/** false when the source has no glyph for cp. Default: from cells()/advance(), originX 0. */
	virtual bool metrics(uint32 cp, GlyphMetrics &m);
};
namespace Unicode {
bool isWide(uint32 cp);        ///< moved from TtfGlyphSource (EAW W/F, Unicode 16.0 table)
bool isCombining(uint32 cp);   ///< general category Mn or Me (generated table, same script)
bool isThaiBase(uint32 cp);    ///< U+0E01..U+0E2E, U+0E40..U+0E44 (leading vowels), U+0E4F..U+0E5B
bool isThaiLeadingVowel(uint32 cp);  ///< U+0E40..U+0E44
bool kinsokuNoStart(uint32 cp);
bool kinsokuNoEnd(uint32 cp);
}
}
```

**The Thai marks.** `[measured]` (`python3 unicodedata`, categories Mn/Me/Mc
in U+0E00-0E7F): U+0E31, U+0E34-U+0E3A, U+0E47-U+0E4E - exactly the brief's
set. `[measured]` with Pillow's BASIC layout (plain FreeType, one glyph at a
time, no shaping, `ImageFont.Layout.BASIC`), 24 px; the rendering is reproduced by plan Task 4's `test_c11.py`:

| Face | Base U+0E01 advance | Mark U+0E48 advance / bbox left | Renders "ที่นี่ไม่มีใครอยู่ น้ำ กำ" per glyph |
|---|---|---|---|
| Sukhumvit Set (`/System/Library/Fonts/SukhumvitSet.ttc`, faces 0-5 = Thin..Bold) | 14 | **0 / -4** (U+0E34: 0 / -12; U+0E38 below: 0 / -5) | **correct**, tone mark over upper vowel included |
| Thonburi (`Thonburi.ttc`) | 14 | 12 / 0 | **wrong**: marks drawn as spacing glyphs with dotted circles (relies on AAT shaping) |
| Hiragino Sans W3 | 24 (notdef) | 24 (notdef) | no Thai at all |

So a face designed for per-glyph placement (zero-advance marks with negative
left bearing) needs **no shaping** for Thai; the engine must (1) not clip ink
left of the origin and (2) not advance for a mark.

**Rendering (T1).** `TtfGlyphSource::ensure()` asks
`getBoundingBox(cp)` first. A glyph whose ink starts at or right of its
origin (`left >= 0`: every Hangul, kana, kanji and Latin glyph of the faces
measured) is drawn exactly as today, origin at column 0, `originX = 0` - so
its row bytes do not change and KQ1-ko stays 0 px. A glyph with ink left of
its origin (a Thai mark, `left` = -4..-12 at 24 px) is drawn with its origin
at column `originX = min(-left, cellWidth)`, inside the same
`cellWidth * 2` row; nothing is clipped. The row layout and stride are
unchanged, so `TextCompose::expandGlyphRow()`, SCVMUNI and SVFN keep theirs.
SVFN reports `originX = max(0, -bearingX)` the same way. A drawer that does
not yet read `originX` draws such a glyph `originX` px to the right of where
it belongs (today it draws it clipped), which is why every engine task below
adopts `metrics()`.

**Placement (every engine).** Pen `x` in source px; for glyph `cp` with
metrics `m`:

- `m.combining`: draw at `anchorX - m.originX`, where `anchorX` is the pen
  position **after** the previous base (`baseX + baseAdvance`), and do not
  advance. The mark's own negative bearing puts it over the base, as the
  face designer intended. Several marks in a row share the same anchor
  (U+0E35 + U+0E48 in "ที่" measured correct in Sukhumvit).
- else: draw at `x - m.originX`, then `x += advance`.

In game px (SCI and SCUMM lay out in low-res units), the advance of a
non-wide glyph is `latinAdvanceGamePx(kHiResMetricsFont, gameW, m.advance,
scale)` (the existing rule, `latin_advance.h`); a wide glyph keeps today's
cell rule (so Hangul and kanji keep their grid and KQ1-ko stays 0 px); a
combining mark is 0. The hi-res `anchorX` is kept **in source px** by the
drawer (not recomputed from rounded game px), so a mark lands where the face
puts it regardless of rounding.

- **SCI:** `GfxFontUnicode::getCharWidth(cp)` returns the game-px rule
  above; `drawChar()` keeps `_lastBaseHiresX`/`_lastBaseAdvance` and places a
  combining glyph against them. `GfxText16::Draw()` needs no change: it
  already calls `drawChar()` per character and adds `getCharWidth()`, which
  is 0 for a mark.
- **SCUMM:** `ScummHiResText::advanceFor()` returns the same game-px rule;
  `drawChar()` keeps the anchor in the overlay's hi-res coordinates (T6).
- **AGS:** TTF through alfont: `[unmeasured]` whether alfont honours a
  negative `bitmap_left` for zero-advance glyphs; T8 measures it on
  "ที่นี่" and, if it clips, draws UTF-8 text through the map's
  `TtfGlyphSource` instead of alfont (the `SvfnFontRenderer` path of plan 5
  T8 generalised to any `UnicodeGlyphSource`).
- **Grim:** `Graphics::TTFFont::drawString()` places each glyph at
  `x + glyph.xOffset` (`ttf.cpp:731`) and advances by `glyph.advance`
  (`ttf.cpp:830`), i.e. already per-glyph with bearing `[source]`; Sukhumvit
  marks then work unchanged `[unmeasured]` (T9 captures it).

**Vietnamese** in NFC is precomposed (U+1EA0..U+1EF9): ordinary non-wide
glyphs, no marks needed. A translator's NFD text (base + U+0300..U+0323)
goes through the combining path; stacked diacritics may collide without
GPOS mark-to-mark `[unmeasured]` - the sample generator writes NFC.

### 4.3 (c) Line breaking per script

One rule set, by **character class**, not by the language setting
(`TextLayout::canBreakBefore(run, i)` between `a = cp[i-1]` and `b = cp[i]`):

1. Never inside a cluster: not before a combining mark, not inside a control
   unit sequence. **Escapes** (control units that are not newlines): never a
   break right after one; a break before a run of them is judged between the
   unit before the run and the first unit after it. So an escape glued to
   the front of a word moves to the next line with it (`hello <E>world` →
   `hello` / `<E>world`); in *space, escapes, space, text* the only
   opportunity is before the text, so the escapes stay at the **end** of the
   previous line (`hello <E> world` → `hello <E>` / `world`) and the spaces
   around them hang: the line fits on, and `LineSpan::width` reports, its
   ink width. Escapes at the end of the text stay on the last line. Rendering
   is in order, so an escape's state (colour) still reaches the glyphs after
   it. An escape is on a line alone only if the text after it does not fit
   even as an emergency split.
2. After a space run (`kUnitSpace`: U+0020, U+3000; not U+00A0): yes; the
   spaces are dropped at the line end (`LineSpan::next`).
3. **Kinsoku** (`rules.kinsoku`): not before `kinsokuNoStart(b)`, not after
   `kinsokuNoEnd(a)`. The table is **SCI's**, converted to code points
   `[measured]` (decoding `text16_shiftJIS_punctuation_SCI01` as CP932):
   `ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶー、。」』！？`
   (U+3041 3043 3045 3047 3049 3063 3083 3085 3087 308E 30A1 30A3 30A5 30A7
   30A9 30C3 30E3 30E5 30E7 30EE 30F5 30F6 30FC 3001 3002 300D 300F FF01
   FF1F), plus the closing brackets and marks JIS X 4051 adds
   (`）］｝〕〉》】・：；，．々ゝゞヽヾ` and ASCII `) ] } , . ! ? : ;` when
   the previous unit is wide); no-end: `（［｛「『〔〈《【` and ASCII `( [ {`
   before a wide unit.
4. **Ideographic** (`kUnitWide`): a break is allowed before and after any
   wide unit (kanji, kana, fullwidth forms, CJK punctuation; Hangul only when
   `rules.hangul == kHangulBreakAny`).
5. **Thai syllable segments** (`rules.thaiFallback`, C16): inside a Thai
   run a break is allowed only between syllable-ish segments. The segmenter
   (`isThaiSegmentStart()`) needs no dictionary: it starts from Thai
   Character Clusters (never after เ แ โ ใ ไ; never before a mark, a
   following vowel, ๆ or ฯ; never inside the spelled vowels เ-ือ, เ-ีย, ัว,
   ออ, รร) and merges clusters into syllables by final consonants, initial
   pairs (กร หม อย …), silent letters under ์ and inherent-vowel syllables.
   Every break it allows is also a TCC boundary, so a wrong guess only moves
   the break to another cluster edge. ๆ never starts a line, even after a
   space; ฯ may after a space (the title ฯพณฯ). Segments are cached per
   decoded run (1 byte per unit), so a line lays out in linear time. On the
   1878 KQ1-th strings at widths 13-40 the breaks that fall inside a
   syllable went from 18952 to 1481; what is left needs a dictionary
   (เด|เวนทรี, ตอบส|นอง; the known misreads are in runs/c16/report.md).
   Dictionary breaking (ICU/libthai word lists) is the next step. Lao keeps
   no rule of its own yet.
6. Otherwise no opportunity (Latin letters inside a word, Hangul under
   `word`).

`fitLine()`: extend while `width(first, i) <= maxWidth`; end at the last
opportunity; if none, **emergency**: the last cluster boundary that fits (at
least one cluster per line, as SCI's "split the very first word").

Per engine, what changes:

| Engine | Where it wraps today | Change | Rules |
|---|---|---|---|
| SCI16 | `GfxText16::GetLongest()` (`text16.cpp:253-455`), called by `Size()`/`Draw()`/`DrawString()` | UTF-8 branch (`heapStringsAreUtf8()`) → `fitLine()` on a member `TextRun`; returns `byteNext - byteStart` as the char count and trailing-space skip as today. Code-page branch untouched | `hangul=word` (keeps KQ1-ko: SCI already breaks it at spaces), kinsoku on, Thai on |
| SCUMM | `CharsetRenderer::addLinebreaks()` (`charset.cpp:617-755`); width via `getStringWidth()` (`:500`) | `_textUtf8` → `addLinebreaksLayout()`: decode with a SCUMM `TextDecoder` (escapes of §3.3), `fitLine()` repeatedly, write `0x0D` at `byteEnd` (replacing the space if `byteNext > byteEnd`, else insert with the existing `memmove` and bound check). `getStringWidth()` sums `LayoutMetrics::advance()` for UTF-8 | `hangul=any` (the Korean patches' own rule, so a UTF-8 `ko.trs` breaks where the CP949 `korean.trs` does), kinsoku on, Thai on |
| AGS | `split_lines()` (`fonts.cpp:343`) | when `get_uformat() != U_ASCII`: `breakLines()` with an `AgsLayoutMetrics::width()` = `get_text_width_outlined()` of the byte range (keeps AGS's outline arithmetic and the `wii -= 1` quirk); `U_ASCII` path untouched (no per-frame cost for ASCII games) | `hangul=word` (T6 measured all 14 Korean `.tra`s wrap at spaces: no Korean run > 40 bytes without a space, `runs/c8/T6/scan40.txt`), kinsoku on, Thai on |
| Grim | `TextObject::setupTextReal<U32String>` (`textobject.cpp:205-265`) | `_isUtf8` → `TextRun::assign(msg)` + `breakLines()`; no `-` inserted on an emergency split of a wide or Thai run (the Chinese exception generalised) | `hangul=word`, kinsoku on, Thai on |

### 4.4 (d) TTF coverage against the translation's own code points

`requireHangul` (A2, A16) is replaced by:

```cpp
namespace Graphics {
class CodePointSet {                      // sorted, unique
public:
	void addUtf8(const char *s, uint32 len);
	void addU32(const Common::U32String &s);
	uint32 size() const;
	/** Up to n code points spread across the set (every size/n-th, plus the first
	 *  of each 128-block present), non-ASCII first. Deterministic. */
	void sample(uint n, Common::Array<uint32> &out) const;
};
struct CoverageReport {
	uint32 sampled, missing;
	Common::Array<uint32> firstMissing;   ///< up to 5, ascending
	uint32 spacingMarks;                  ///< combining cps the face gives a non-zero advance
};
/** Rasterises (and so caches) each sampled cp through src->metrics(). */
CoverageReport checkCoverage(UnicodeGlyphSource *src, const Common::Array<uint32> &sample);
}
```

At font set-up, with a translation loaded, each engine samples 64 code points
of its `CodePointSet` and checks the chain. One warning per face:

```
hires text: <face> lacks 17 of 64 sampled characters of the translation
(U+0E48 U+0E49 U+0E4A U+0E4B U+0E4C ...); they fall back to <next face | the game's font>
```

and, when `spacingMarks > 0` (the Thonburi case):

```
hires text: <face> draws combining marks as spacing glyphs (it needs
shaping); choose a face with zero-width marks, e.g. Sukhumvit Set
```

Fallback per engine: SCI → next face in the chain, then the `.uni` bundle,
then the game's font (as `cache.cpp:343-360` does today for a failed face);
SCUMM → next face, then the game charset; AGS → next map font, then the
game's own renderer (a missing glyph is empty); Grim → none (warning only).

The same sample is appended to the vertical-fit probe set (`create(...,
fitProbes)`), so Thai above/below marks and Japanese brackets are inside the
cell. `[unmeasured]`: the fit change for KQ1-ko - its sample is Hangul +
ASCII, all already in the old probe set's extremes, so the fit should not
move; T5 verifies 0 px.

Cost: 64 rasterisations at start-up, which are then cached (they are glyphs
the game will draw). C8 T3 measures ms/glyph; `[unmeasured]` here.

### 4.5 (e) Fonts: the map stays, chains are added

- `hires_text.map` stays the one file. **`face=` (in `[hires]`, `[font.N]`)
  accepts a comma-separated chain** of `[fonts]` names or paths; lookup goes
  to the first face that has the code point (`FallbackGlyphSource`). One map
  can then cover Korean, Japanese and Thai, so swapping the translation needs
  no map edit:

  ```ini
  [hires]
  face=ko, ja, th
  [fonts]
  ko=/System/Library/Fonts/AppleSDGothicNeo.ttc
  ja=/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc
  th=sukhumvit-text.ttf      ; face 2 of SukhumvitSet.ttc, extracted (T4)
  ```

- **`[font.N] bitmap=`** (plan 5 T8's parser change) moves here, parsed for
  every engine.
- **`[layout]`** (new): `hangul=word|any`, `kinsoku=on|off`, `thai=on|off`,
  defaults per engine as in §4.3. Only a translator who wants the other
  convention writes it.
- **`[latin]` modes and the fullwidth remap** are Korean/Japanese aesthetics:
  kept as options, **default off**, names unchanged (renaming would break
  every existing map; the guide describes them as "ASCII routing").
- **`[encoding] codepage=`** stays for legacy text only; a UTF-8 translation
  (§4.1) overrides it.
- TTC faces: face 0 only (Out of scope); `ttc2ttf.py` extracts others.

### 4.6 (f) ini keys: gated on "a translation is loaded"

| Engine | Today | After |
|---|---|---|
| SCI | `hires_text_*` honoured only for CJK code pages (A1) | honoured when `heapStringsAreUtf8()` or a legacy CJK page; warning text "no translation and no CJK code page" |
| SCUMM | honoured whenever the hi-res layer is on (`hires_text=false` turns it off) | unchanged; plus `text_encoding=utf8` (forces UTF-8 for an unmarked bundle) |
| AGS | `text_encoding` (C8 T6) | unchanged; map read only when present (plan 5 T8 scope rule) |
| Grim | none | none (`.laf.txt` names faces) |

## 5. Test languages and data

Sample text is **machine-produced sample phrases** generated by scripts in
the harness repo (`runs/c11/mkjatext.py`, `mkthtext.py`): no real
translation is needed or claimed. Each script maps every source string of
the game to a phrase drawn from a fixed list of real Japanese/Thai sentences
(game-like: "扉は固く閉ざされている。", "ここには何もない。", "ประตูถูกล็อกไว้แน่น",
"ไม่มีอะไรอยู่ที่นี่") chosen deterministically by the source string's hash,
so a given screen always shows the same text and captures are repeatable.
Every list includes the stress cases: a Japanese line with `」` and `。`
landing at a line end (kinsoku), long kanji runs without spaces, a Thai line
with stacked marks (ที่, น้ำ, ปี่ with an ascender consonant), leading
vowels (เ, ไ) and no spaces for > 40 characters.

| Game | Legacy data here | ja / th data (T4) | Fonts |
|---|---|---|---|
| SCI KQ1 (DOS remake) | `gamedata/kq1-ko1` = `kq1-ko8`: English volumes + 113 UTF-8 `text.NNN` + `sci-ko.str` + `korean.uni` `[measured]` | `runs/c11/kq1-ja/`, `kq1-th/`: the English files + `text.NNN` rewritten with `harness/i18n/m12mkpatch.py`, `sci-ja.str`/`sci-th.str` from `sci-ko.str`'s keys, `hires_text.map` (chain), ini `language=ja`/`th` | Hiragino Sans W3 (ja), Sukhumvit Set "Text" (th, extracted), AppleSDGothicNeo (ko) |
| SCUMM MI1 UTE | `kortrs/mi1ute/.../korean.trs` (SCVMTRS, CP949) | `runs/c11/mktrs.py`: reads `korean.trs`, keeps its index/room table and original strings, replaces each translated string by the sample phrase, writes `ja.trs`/`th.trs` with the body BOM (§4.1), and `ko.trs` = the CP949 bundle transcoded to UTF-8 (the equivalence test) | as above |
| AGS 5 Days a Stranger | `kortrs/5days/korean.tra` (EUC-KR, keys = English source strings) | `runs/c11/mktra.py` (writer next to `runs/c8/T6/trakeys.py`'s reader: `AGSTranslation` header, game id block, "Avis Durgan" encryption, `ext_sopts` with `encoding=utf-8`): `japanese.tra`, `thai.tra` with the same keys; no AGS editor or `trac` needed | map `[font.0..2] face=` chain; 5 Days' own fonts are WFN |
| Grim | `kortrs/grim` (`grim.ko.tab`, `GRIM.TAB`, D2Coding + `.laf.txt`) | `grim.ja.tab`, `grim.th.tab` (UTF-8 BOM, `GRIM.TAB`'s keys) + `.laf.txt` naming Hiragino / Sukhumvit | as above |

`[measured]` for the fonts: Hiragino Sans W3 face 0 renders the Japanese
sample per glyph correctly (fullwidth punctuation advance = pixel size, 26 at
26 px); Sukhumvit Set face 0 is "Thin", face 2 "Text" (Pillow `getname()`),
so T4 extracts face 2.

**Verification = headless captures with crops per language** (the C6 method:
`c6cap.sh`, `seqcmp.py`, `sheet.py`, `crop.py`; the debug socket for AGS
`ags_say` and SCI `kq1_intro.py`/`kq1_tour.py`), plus:

- the **C6 invariant**: no translation → IDENTICAL-PREFIX to upstream
  `503d074778`, u vs u2 clean;
- the **Legacy invariant** (Goal);
- the **equivalence test**: MI1 UTE with `ko.trs` (UTF-8) vs `korean.trs`
  (CP949), same map → IDENTICAL-PREFIX.

## 6. Decisions

| # | Decision | Chosen | Rejected, and why |
|---|---|---|---|
| I1 | Text unit for layout | Code-point `TextRun` per layout call, bytes in storage (§3) | UTF-8 in-place per engine: four rule sets today, look-behind needs backward decoding; UTF-32 in VMs: plan 5 E3 |
| I2 | Metrics | `GlyphMetrics` per glyph; cells only for EAW-wide | Cells for all: a Thai mark gets a cell; face advance for all: moves KQ1-ko's Hangul off its grid (Legacy invariant) |
| I3 | Combining marks | zero advance + the face's negative bearing, anchored to the previous base in source px | shaping (HarfBuzz): not in ScummVM; per-font PUA Thai repositioning tables: font-specific, and Sukhumvit needs none `[measured]` |
| I4 | Line breaking | one class-based rule set (§4.3) with per-engine defaults for Hangul | per-language rules: the language setting says nothing about mixed text (Japanese lines with English names) |
| I5 | Thai breaking | syllable-ish fallback | dictionary: large data, a later card |
| I6 | Coverage | sample of the translation's own code points | Hangul probes: language-specific; rasterising the whole set: thousands of glyphs at start-up |
| I7 | UTF-8 marker | SCI: `sci-<lang>.str` manifest; SCUMM: body BOM; AGS: `ext_sopts encoding`; Grim: file BOM | content sniffing alone: CP949 pairs can form valid UTF-8 (`detection.h:57-62` explains the C2..C8 + A1..BF case) |
| I8 | Fonts | map chains (`face=a, b, c`) | a per-language map: the user's "same map" goal |
| I9 | Language codes | append `TH_THA`, `VI_VNM` to `Common::Language` | a string tag outside `Common::Language`: every loader already names files by `getLanguageCode()` |
| I10 | Scope | RTL, shaping, Sword out | - |

## 7. What happens to plan 5's remaining tasks

| Plan 5 | Fate |
|---|---|
| T3 SCUMM lazy sources (running) | unchanged; C11 T6 builds on it |
| **T4** SCUMM per-font faces, proportional advance | **folded into C11 T6** (per-glyph metrics for every non-wide glyph, not only Latin) |
| **T5** SCUMM UTF-8 | **folded into C11 T7** (`<code>.trs`, body BOM - plan 5's "trs begins with `EF BB BF`" is impossible, the file begins with `SCVMTRS `; shared layout stage; `textCharLength()`; buffer audit kept) |
| T7 AGS extfnt (running) | unchanged, legacy |
| **T8** AGS map fonts | **folded into C11 T3 (parser `bitmap=`) and C11 T8** (UTF-8 primary, chains, layout stage) |
| T9 Grim alpha (running) | unchanged; C11 T9 builds on it |
| **T10** Sword (optional) | **dropped**: Korean-only resource replacement, no i18n path (Out of scope) |
| **T11** matrix + docs | **replaced by C11 T10** (adds ja/th columns) |

## 8. Risks

1. **The KQ1-ko 0 px check under I2.** Non-wide, non-ASCII code points in
   KQ1-ko's text (e.g. `…` U+2026 is EAW-ambiguous → narrow) change advance
   from a half cell to the face's advance. `[unmeasured]` whether the intro
   contains any; T5 reports every changed frame with a crop and the code
   points involved; the user accepts or T5 restricts the rule to non-CJK
   scripts.
2. **alfont and negative bearing** (AGS, §4.2) `[unmeasured]`; fallback path
   named.
3. **SCUMM buffers** at 3 bytes/char (Thai with marks: up to 3 code points
   per cell) - plan 5 T5's buffer audit is kept in C11 T7.
4. **`language=ja` on a non-Japanese SCUMM release** enters no JA branch for
   DOS MI1 (`loadCJKFont()` requires FM-Towns/SegaCD/v7 for JA,
   `charset.cpp:74-110`) `[source]`, but other `_language == JA_JPN` sites
   exist; T7 lists them and gates the ones reachable with `_textUtf8`.
5. **SCI detection with a foreign `text.000`**: falls to the English entry,
   which is intended (the manifest decides UTF-8); a game whose English
   entry lists `text.000` with an MD5 would not detect at all
   `[unmeasured]` - T5 checks KQ1's entries.
6. **Thai quality without shaping** depends on the face (Thonburi fails,
   Sukhumvit works `[measured]`); the spacing-mark warning names the problem.
7. **Upstream divergence**: `Common::Language` additions touch `common/`;
   kept to two appended entries.

## 9. Measured: the C11 matrix on the merged `i18n` (T10) `[measured]`

**Builds.** **b** = merged `i18n` `da78ab38fc` (`~/work/scummvm/i18n/scummvm`,
everything of C11 T1-T9, T3b, T3c, C8 T3/T7/T9, C10, C12). **u/u2** =
upstream `503d074778`. **r/r2** = the pre-C11 `i18n` `6afdae3f3e` (the last
commit before C11 T1 merged; it has C10's 32-bit screen and C8 T6/T7), built
for this matrix in `.worktrees/c11-ref-t10`. All configured
`--enable-engine=scumm,scumm_7_8,sci,ags,grim --enable-freetype2`. Method:
`runs/c6-tools/c6cap.sh` + `seqcmp.py` (distinct-frame sequences, IDENT =
IDENTICAL-PREFIX), all runs of one row in parallel, frames deleted after
hashing; SCI and AGS through the debug socket (`kq1_intro.py`,
`kq1_tour.py`, `ags_say`). Runs and logs: `runs/c11/T10/` (harness repo),
one `.txt` per row; the full report is `runs/c11/T10-report.md`. Where
upstream cannot be the reference - C10 changes every 32-bit AGS game's
frames, and upstream cannot load the Grim Korean data - the reference is
the pre-C11 build **r**, and the row says so. Japanese and Thai text is
**machine-produced sample text** (§5); no claim of translation quality.

**`make test`** (`c11-t10-ft`/`c11-t10-noft` worktrees at `da78ab38fc`,
`SCUMMVM_TEST_KORTRS`/`SCUMMVM_TEST_I18N_DATA` set): **884 tests OK with
FreeType, 884 OK without** (`--disable-freetype2`; 17 FreeType-only tests
report `TS_SKIP`, 1 with FreeType: the AGS `wfn_ext` real-data test finds no
`5 Days a Stranger (Windows)/extfnt0.wfn` under `kortrs`). No build warning
in C11 code; the three non-OpenGL warnings (`text16.cpp` `doubleByteMode`,
`room.cpp` shadowing) are in the pre-C11 build too.

### 9.1 Matrix

| Row | none (C6 invariant) | ko legacy (vs r) | ko UTF-8 | ja | th |
|---|---|---|---|---|---|
| **SCI** KQ1 | frame-locked intro: 16/16 dumps = `baseline-4a0f7f0e1c/intro-en`, 20/20 = r. `c6cap` 40 s: b-u DIVERGE@117, u-u2 @116, r-r2 @116 (SCI timing; the fork differed from upstream before C11 too) | KQ1-ko intro **0 px** f1/f20/f45/f60 vs baseline, 28/28 dumps = r; tour 6/6 dumps 0 px (03_room2 716 px = the known stale-baseline moat; r 3176 px). LB1 Korean b-r IDENT 100/100 (r-r2 @98) | KQ1-ko is the UTF-8 case (`ADGF_UTF8I18N`): same as the legacy column | intro 4/4, tour 7/7, kinsoku reply 1/1 `_layer` dumps = T5; sheet `shots/c11/matrix/sci-kq1-ja.png` | differs from T5 by design (T3b: the face shrinks so marks fit); the marks reply = T3b fix1 1/1; `sci-kq1-th.png` |
| **SCUMM** MI1 UTE | IDENT 161 vs u, u-u2 IDENT | hi-res off IDENT 162 (b-u and b-r); C6 TTF map IDENT 165 | `ko.trs` hi-res off = CP949 `korean.trs` IDENT 162/162; hi-res on DIVERGE@1 (per-glyph vs the CP949 cell: the T7 ruling), both = T7's own captures 165/165 | boot 117 IDENT 164/164 vs T7; opening 100 s timing-bound (b vs b2 DIVERGE@84; 322/362 unique frames shared with T7); `scumm-mi1-ja.png` | smaller than T7 by design (T3b); opening vs T3b fix1 @44 = b vs b2 @44; `scumm-mi1-th.png` |
| SCUMM group A | MI2 IDENT 121, Indy4 IDENT 542, Loom CD IDENT 167, S&M IDENT 702; Loom Towns @749 = u-u2 @749; Indy3 noise (b-u @295, u-u2 @187, b-b2 @161..186) | MI2 123, Indy4 545, Loom CD 170, S&M 719 IDENT (b-u too); Indy3 noise (b-r @186, b-b2 @216); Loom Towns @252 = r-r2 @263 | - | - | - |
| SCUMM group B | MM1 IDENT 220, MM2 395, Zak2 346; Zak Towns IDENT but for a second ScummVM splash (version string) late in the run: with it dropped, b-r 268/268 IDENT; **FT: see 9.2** | MM1 230, MM2 385, Zak2 347, FT 764 IDENT (b-u too); maps: svfn-ft 766, svfn-mm2 385, ttf-mm2 385, ttf-zak2 348 IDENT vs r | - | - | - |
| **AGS** 5 Days | IDENT 58 vs u and r | `ags_say` fonts 0/1/2 crops IDENTICAL to T8 fix1 (= T8 round 0; font 2 = C8 T7 IDENTICAL-565) | - (no UTF-8 Korean `.tra` here) | 9/9 `ags_say` crops IDENTICAL to T8 fix1; `ags-5days-ja.png` | font 2 IDENTICAL; fonts 0/1 now smaller: the T3b fit reaching AGS after the merge (T8 fix1 logged `lacks ... U+0E39`; the merged build does not); `ags-5days-th.png`, before/after `ags-5days-th-t8-vs-merged.png` |
| AGS C/D, 32-bit | Blackwell 1-4, Primordia, Shardlight, Winter's Night, KQ1 VGA, SQ2 VGA: DIVERGE@1 vs upstream (C10, pre-C11), **IDENT vs r** (442, 490, 286, 45, 406, 528, 486, 2, 2), r-r2 and u-u2 IDENT; Blackwell 5 IDENT 84 vs u (stalls on both) | Deception, Epiphany `ags_say` crops IDENTICAL to T8 fix1 (C8 crops IDENTICAL-565) | - | - | - |
| **Grim** | 120 s TinyGL: the only early difference is a second ScummVM splash (version string, at the 640x480 switch); with it dropped b-u DIVERGE@525, b-b2 @435, u-r2 @434: noise | r cannot identify the Korean data (no fallback detection before T9), so vs T9's captures: DIVERGE@408, 1659/1666 unique frames shared = T9's noise floor (408) | unmeasured (no UTF-8 `grim.ko.tab`) | vs T9: @402, 1664/1670 shared (T9's own reruns @1144); `grim-ja.png` | vs T9: @220, 1667/1669 shared (T9's own reruns @220); `grim-th.png` |

Korean legacy crops on one page: `shots/c11/matrix/ags-korean-legacy.png`.

### 9.2 Findings

1. **No C11 regression found.** Every row is IDENTICAL-PREFIX to its
   reference or diverges exactly where the reference diverges from itself.
2. **Full Throttle (and any SCUMM v7 game) crashes at start in a
   non-CJK language on every fork build** - b, r and the C6 build
   `91cffbd25a` alike; upstream runs (222 distinct frames in 30 s). Crash
   report: `IMuseDigital::setAudioNames` on a null `_imuseDigital`, from
   `ScummEngine_v7::readIndexBlock` <- `readIndexFile` <-
   `peekGameCharsetHeight` <- `ScummEngine::init` (`scumm.cpp:1293`). The
   fork's `peekGameCharsetHeight()` (commit `583aa2a8af` "SCUMM: Give a
   non-CJK game a font height to scale against", hires-text line, before
   C6) reads the index before iMuse Digital exists. The C6 runs used
   `language=ko`, where `_useCJKMode` skips the peek, so C6 never saw it.
   Pre-C11; needs its own card.
3. **AGS Thai is drawn smaller after the merge.** T8 was built before T3b;
   on the merged line the TrueType fit that keeps Thai below-base marks
   inside the cell (T3b) applies to AGS fonts too, so 5 Days' fonts 0/1
   draw Thai smaller and #225 now fits one line. Intended by T3b's ruling
   ("Thai text gets smaller"); a map `size=` sets the size explicitly.
4. **Grim Thai, sample #675** (`grim-th.png`, frame 675): a wrapped line
   reaches the screen's right edge; it is not cut. Grim measures lines
   with per-character kerned widths only (T9 concern 4).

### 9.3 The `[unmeasured]` items of §4 and §8, resolved

| Item | Result |
|---|---|
| §4.2 alfont with a negative `bitmap_left` | **clips and misplaces** Thai marks (T8, `shots/c11/5days-th-alfont-measure.png`); a UTF-8 translation with combining marks and an alfont TTF font logs a hint to name the fonts in a map |
| §4.2 Grim with Sukhumvit | marks sit on their bases through `TTFFont`'s `xOffset`, right-aligned to the base stem, not GPOS-stacked (T9) |
| §4.2 Vietnamese NFD | **still unmeasured**: no Vietnamese data |
| §4.4 / §8.1 the fit and per-glyph advance for KQ1-ko | 0 px (T5, T3b and again here); per-glyph advance is gated on a translation, so legacy `.uni` widths are unchanged |
| §4.4 start-up cost of the coverage sample | raster counts measured (MI1-th: 92 probe rasters within a budget of 96, T3b); milliseconds still unmeasured |
| §8.3 SCUMM buffers | T7's buffer audit table; every buffer bounded on the UTF-8 path |
| §8.4 `language=ja` on DOS MI1 | 28 `_language ==` sites listed, the reachable ones gated (T7) |
| §8.5 SCI detection with a foreign `text.000` | KQ1 ja/th detect as the English entry, the manifest turns UTF-8 on (T5) |
| §8.6 Thai quality without shaping | Sukhumvit correct, Thonburi warned (T5); ำ after a tone mark sits beside it, not stacked |

## 10. Known limitations (as merged)

What the merged line does **not** do, or does differently from this design;
each was ruled on or accepted during T1-T9 (`progress.md` of plan 6):

- **No shaping, no RTL, no dictionary breaking** (Out of scope). Thai
  breaks between syllable-ish units and may split words; stacked marks are
  placed by the face's bearings only (ำ after a tone mark sits beside it);
  Thonburi-like faces that rely on shaping draw marks as spacing glyphs
  (warned).
- **Thai is drawn smaller** than the cell size asked for when the face is
  fitted to the game's line (SCI, SCUMM, AGS without `size=`): about 0.75x,
  so the marks fit the game's line pitch (T3b ruling). Game-px rounding
  leaves small gaps in Thai on SCI (advances round to 2 hi-res px).
- **UTF-8 Korean on SCUMM with hi-res on is spaced per glyph**, not on the
  CP949 `.fnt` cell; it breaks lines where the CP949 bundle does (2000/2000
  in the unit test) but is not pixel-identical (T7 ruling). Korean josa/verb
  glue is not generalised: UTF-8 bundles drop the glue codes.
- **SCUMM UTF-8 bundles** only on the v1-v6 PC renderers; HE, v7/v8,
  FM-Towns, PCE, SegaCD, NES and Mac ignore one with a warning. Code points
  above U+FFFF become U+FFFD; the game's own font draws every non-ASCII code
  point as `?` when no face has it; untranslated game bytes that are not
  valid UTF-8 pass through as the game's own glyph (U+F700 + byte).
- **SCUMM `noteTranslatedString`** and the decoder share `escapeArgBytes`
  (T3c); `FF <newline>` still ends a line differently in `textEnd` and
  `scummTextLength` for Sega CD / Indy4-JA (unreachable with UTF-8).
- **SCI:** the manifest rule means a stray `sci-<lang>.str` turns the UTF-8
  path on for that language; Windows SCI1.1 and KQ6 hi-res take their own
  driver with no text plane (the translation's glyphs are not shown, one
  warning); PQ2's JA `\n` escape is not a newline for the UTF-8 layout;
  faces of one chain are fitted separately (no shared baseline);
  `[font.N] bitmap=` is parsed but unused on SCI.
- **AGS:** the layout stage runs for a UTF-8 translation, an EUC-KR
  translation or active map fonts; a `.tra` that fails to open still counts
  as a translation (upstream quirk); the ini `hires_text_font` alone makes
  the map fonts active; on AGS `[font.N] face=` beats `hires_text_font`
  (SCI/SCUMM: the ini key wins); EUC-KR patches inherit the layout stage's
  edge cases (emergency split, trailing spaces - their probes are
  unchanged); characters a chain lacks fall back to the game font one at a
  time (kerning lost); TTF + `extfntN` keeps the TTF's height.
- **Grim:** no map, no chain and no coverage check (design §4.4 said
  "warning only"; not implemented): one face per `.laf.txt`; the retail
  game only; a forced language without its `grim.<lang>.tab` is not
  identified at all, so the "missing table" warning is unreachable; UTF-16
  official tables keep the old breaker; a UTF-8 `grim.ko.tab` is
  unmeasured; OpenGL shaders unmeasured (no headless GL).
- **TTC files** open face 0 only (extract others with `ttc2ttf.py`).
- **Vietnamese** (`vi` is a language code now) has no sample data; NFD
  diacritic stacking is unmeasured.
- **Pre-C11, found here:** SCUMM v7 in a non-CJK language crashes at start
  (§9.2 item 2).
