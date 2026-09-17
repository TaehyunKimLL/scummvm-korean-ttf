# M8 — moving SCI text to code points: the plan before the code

Status: **plan, not implemented.** Written before touching `GfxText16` because
a refactor of the text path needs its shape agreed first.

Every claim is marked `[source]`, `[measured]` or `[unmeasured]`.

## The seam, precisely

`[source]` `GfxFont` (engines/sci/graphics/scifont.h) is the whole interface:

```c
virtual bool isDoubleByte(uint16 chr);
virtual byte getCharWidth(uint16 chr);
virtual byte getCharHeight(uint16 chr);
virtual void draw(uint16 chr, int16 top, int16 left, byte color, bool greyed);
virtual void drawToBuffer(uint16 chr, ..., byte *buffer, int16 w, int16 h);
```

`[measured]` `uint16 chr` appears 45 times across `engines/sci/graphics`, with
49 call sites of the five methods. Three implementations exist:
`GfxFontFromResource` (SCI's own bitmap fonts), `GfxFontKorean`, `GfxFontSjis`,
plus the new `GfxFontUnicode`.

`[measured]` What travels in that `uint16` today is **not a character**. It is
a packed byte pair, assembled at 8 sites:

```
text16.cpp:216, 315, 353, 395, 517      curChar |= next_byte << 8
text32.cpp:441, 589, 714                currentChar |= *text++ << 8
```

`[source]` The canonical form is `text16.cpp:214`:

```c
curChar = (*(const byte *)textPtr);
if (_font->isDoubleByte(curChar)) {
    curChar |= (*(const byte *)(textPtr + 1)) << 8;
```

So the lead byte is in the low half and the trail byte in the high half —
byte order reversed relative to the encoding. `GfxFontKorean::getCharData`
then does `checkKorCode(c % 256, c / 256)` to undo it. Nothing outside the
font layer knows what those bits mean.

## Why this blocks the goal

`[measured]` `uint16` cannot hold a code point above U+FFFF, so no
astral-plane character is representable at all.

`[measured]` More immediately: because the value is an encoding-specific byte
pair, the *font* must know the encoding. That is exactly the coupling that
produced the empty-box defect in `SCVMUNI_FONT.md` — `checkKorCode()` gates on
EUC-KR lead-byte ranges, and the glyph array is indexed by arithmetic that
only works for one Unicode block.

`[measured]` Meanwhile the translation container is already Unicode: SCITRS
stores UTF-8 and `Translation::translate()` returns `Common::U32String`. The
engine currently throws that away — `lookupText()` calls
`.encode(getSciLanguageCodePage())` to get bytes back, because everything
downstream expects bytes.

## What M6 measured, and what it licenses

`[measured]` In a full KQ1 session: `kStrAt=0`, `kStrCmp=0`, `kStrLen=20`, and
all 20 `kStrLen` calls came from `DEdit::setSize` and the parser's
`::export 2`, operating on player-typed ASCII. Zero byte operations touched
resource text.

`[measured]` In M4's SCI0 game the opposite held: 6,906 `kStrAt` reads and
14,120 `kStrCmp` calls on tainted text, from one script doing a glossary
substring search.

`[source]` Together these say: the *display* path may become code points,
but the *script-visible* path must keep byte semantics, because at least one
real game walks dialogue bytes. So the conversion boundary must sit between
"what scripts manipulate" and "what the renderer draws" — not at the kernel
op layer, and not at the font layer.

## Plan

### Stage 1 — widen the type without changing behaviour — **DONE** `aa41e7c180a`

`[measured]` The five `GfxFont` methods and all four implementations now take
`uint32`. The value is unchanged - still a packed byte pair, still decoded the
same way by each font. 39 insertions, 39 deletions, all of them the type.

`[measured]` **The closing condition had to change, and this matters for every
later stage.** "Pixel-identical capture" is not achievable with this harness:
two runs of one unchanged build differ by up to 7,722 pixels, because
character animation phase varies with wall-clock timing. Screenshot equality
cannot decide whether a text-path refactor is behaviour-preserving.

`[measured]` What does decide it: the **glyph request sequence**. A probe
logged every `(character, top, left)` triple passed to
`GfxFontFromResource::draw` and `GfxFontKorean::draw` over a full play
session, before and after the change.

```
Korean via SCITRS : 1076 glyphs, sequence byte-for-byte IDENTICAL
English           : 1412 before vs 1425 after
```

`[measured]` The English difference is harness non-determinism, not a
regression - re-running the *same* post-change build produced 1412,
alternating with 1425. The Korean sequence is the evidence that counts: it is
the path that exercises double-byte characters, and it did not move.

`[measured]` Built and tested with `ENABLE_SCI32` on as well, which compiles
`text32.cpp`'s three packing sites and the SCI32 font paths that the default
configuration omits. 0 errors, 409/409 tests, both ways. Note that the default
config in this tree has SCI32 **off**, so SCI32 code is not covered unless
explicitly enabled - a trap for later stages.

**Use the glyph sequence, not screenshots, as the gate for stages 2-4.**

### Stage 2 — introduce an explicit representation tag

`[unmeasured]` The problem with stage 1 alone is that a `uint32` holding a
packed EUC-KR pair and a `uint32` holding U+AC00 are indistinguishable. Add a
narrow type so the compiler separates them:

```c
struct SciChar {
    uint32 value;
    bool isCodePoint;   // false: legacy packed byte pair
};
```

`[unmeasured]` Fonts then declare which they accept. `GfxFontUnicode` takes
code points only; `GfxFontKorean`/`GfxFontSjis` take packed pairs only;
`GfxFontFromResource` takes single bytes. A mismatch is a compile-time or
assert-time failure instead of a wrong glyph.

Close with: an assert that fires if a font receives the wrong kind, exercised
by a unit test.

### Stage 3 — decode once, at text entry

`[unmeasured]` `GfxText16`'s iteration currently re-derives characters from
bytes at 5 separate sites. Replace them with one decoder that turns the
incoming string into a `Common::Array<SciChar>` once, chosen by
`getSciLanguageCodePage()` — the boundary that already exists. The five sites
become array indexing.

`[unmeasured]` This is where the SCITRS `U32String` stops being re-encoded:
`lookupText()` can hand code points straight through, and the
`.encode(codePage)` call remains only for the script-visible path that M4
showed must keep bytes.

Close with: the empty-box case from `SCVMUNI_FONT.md` renders correctly —
`「한자王子」 ※표시 ＡＢＣ ㄱㄴㄷ ℃ 정상음절` drawn with real glyphs, verified
by screenshot, with the three control buttons unchanged.

### Stage 4 — wire GfxFontUnicode into GfxText16

`[unmeasured]` Only now is this possible: the renderer speaks code points and
`GfxFontUnicode` consumes them. `SwitchToFont1001OnKorean` is replaced by
"if a SCVMUNI font is loaded and has a glyph for this code point, use it".

Close with: KQ1 Korean rendering via SCVMUNI with no `korean.fnt` present,
plus `glyph-warn: 0`, plus the M6 probe re-run showing parser byte ops
unchanged at 20 — proving the script path was not disturbed.

## Risks, named

`[measured]` **SCI32 shares this interface.** `text32.cpp` has 3 of the 8
packing sites. `ENABLE_SCI32` builds must be verified both on and off; the
tree currently builds with it on.

`[unmeasured]` **`GfxFontFromResource` is the common case.** Every Western SCI
game uses it, so a regression there breaks every game the engine supports.
Stage 1's pixel-identical gate exists specifically to catch that.

`[unmeasured]` **Width and line-breaking arithmetic is byte-oriented.**
`GetLongest`, `Width`, `StringWidth` count characters to compute wrapping;
`[measured]` `text16.cpp` calls `SwitchToFont1001OnKorean` from 3 of those
paths (lines 463, 479, 585). If a code point advances the cursor by a
different amount than the byte pair did, text wraps differently — a visible
regression that the pixel-identical gate will catch but only if the captures
include wrapped multi-line text.

`[unmeasured]` **Upstream portability.** The goal is an upstream
contribution, so no stage may depend on FreeType (`USE_FREETYPE2` is
optional) and all four stages must build with `ENABLE_SCI32` both ways.

## What decides whether stage 3 is safe — baseline now captured

`[measured]` The gate measurement has been taken. `GetLongest` was wrapped so
every line the wrapping code produces logs its character count, resulting
pixel width and the `maxWidth` it was fitting into. Captured over the same
`m6play.sh` session used for M6:

```
harness/i18n/baselines/m8_wrap_ko.tsv   170 lines (Korean via SCITRS)
harness/i18n/baselines/m8_wrap_en.tsv   186 lines (English control)
```

`[measured]` The Korean baseline genuinely exercises wrapping rather than
short labels: 28 of its 170 lines exceed 20 characters and 35 come within 10%
of their `maxWidth`, including lines such as `n=46 w=184 max=192` and
`n=44 w=176 max=192` where the wrap point is actually being chosen. Width per
character ranges 4.00 to 8.00 (median 6.09), i.e. the sample mixes
single-byte and double-byte runs.

`[measured]` Menu entries confirm the arithmetic is byte-counted today:
`n=8 w=32` for a four-syllable Korean label - 8 bytes, 4 glyphs, 32 px at 8 px
per half-width cell.

Stage 3 is therefore gated: re-run `m6play.sh` with the same probe after the
rewrite and diff against these files. Identical sequences mean wrapping is
unchanged. Any difference means the code-point path advances the cursor
differently and the arithmetic needs porting, not just the type - and the
diff names the exact line where it first diverges.

`[source]` Probe commit `aeffec35ad5`, removed in the commit that follows it;
the baselines are committed in the harness repository so the comparison
survives the probe's removal.
