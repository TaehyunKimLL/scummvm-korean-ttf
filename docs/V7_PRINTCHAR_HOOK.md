# The V7 printChar() stub, and where a hi-res hook actually belongs

Card t_c20b052f. Investigation only — no engine code was changed.
Source read at `repo/scummvm` commit `3dda66a0815` (branch `hires-text`).
Every line number below is from that commit; re-check before using one.

Games in scope: Full Throttle, The Dig, COMI (v8 reaches the same
`TextRenderer_v7` through a different glyph renderer).


## 1. What the stub is

```cpp
// engines/scumm/charset.h:340
class CharsetRendererV7 : public CharsetRendererClassic, public GlyphRenderer_v7 {
    void printChar(int, bool) override {
        error("CharsetRendererV7::printChar(): Unexpected call to deprecated function");
    }
```

`CharsetRendererNut` (charset.h:359) carries the identical stub.

Provenance: `0256e92c250` ("SCUMM7/8 - reorganize font rendering - second
part") introduced it, `2e249f1d009` reworded it. The commit that introduced
it is the one that moved v7/v8 text off the character-at-a-time path
entirely; the same commit deleted the `_game.version >= 7` branches from
`CHARSET_1()` in string.cpp. The stub is the residue of that removal.


## 2. The invariant it protects

`CharsetRendererV7` inherits from `CharsetRendererClassic`, and
`CharsetRendererClassic::printChar()` (charset.cpp:1140-1299) is a v5-shaped
routine. It reads and writes a large amount of engine state that v7 does not
maintain and does not want touched:

| what `CharsetRendererClassic::printChar` does | why v7 must not |
|---|---|
| `_vm->findVirtScreen(_top)` and bails if null (1152) | v7 positions text from `BlastText`/clipRect, not from `_top` |
| advances `_left`, `_top`, `_str` (1194-1298) | v7 does its own line layout in `TextRenderer_v7::drawString` |
| sets `_hasMask` / `_textScreenID` (1235-1238) | v7 erases text with `restoreBlastTexts`/`removeBlastTexts`, not the charset mask |
| `markRectAsDirty` per glyph (1230) | v7 marks one rect per blast text (string_v7.cpp:533) |
| Indy4-JAP kerning, SegaCD dialogue clipping, Amiga `_drawScreen` (1224-1264) | v5-era per-platform fixes with no v7 meaning |
| `printCharIntern` → HE / two-buffer / `_textSurface` branch (1301+) | v7 draws into the VirtScreen the caller handed it |

So the stub is not "printChar is broken for v7". It is: **there is exactly
one text pipeline per engine generation, and calling the other one silently
corrupts the caret/dirty/mask state of the one in use.** `error()` converts
that silent corruption into an immediate, attributable abort. It is a
type-system substitute — C++ cannot express "this base method is not part of
my interface", so the author expressed it at run time.

Bypassing the inherited hook is therefore *design*, not oversight: v7's
entry point is a different virtual interface on the same object.
`CharsetRendererV7` multiply-inherits `GlyphRenderer_v7` (charset_v7.h:39)
and it is *that* vtable the engine calls. `setupCharsetRenderer()` wires both
ends explicitly:

```cpp
// engines/scumm/scumm.cpp:2130
} else if (_game.version == 7) {
    CharsetRendererV7 *c7 = new CharsetRendererV7(this);
    _charset = c7;          // for setCurID/getFontHeight/getStringWidth
    createTextRenderer(c7); // as the glyph source for TextRenderer_v7
}
```

`_charset` still exists for v7 and is still used — but only for charset
selection and metrics, never for drawing.


## 3. The actual v7 call path

```
ScummEngine_v7::displayDialog()                string_v7.cpp:654
  -> addSubtitleToQueue()                      :627   (bytes only, no drawing)
ScummEngine_v7::drawBlastTexts()               string_v7.cpp:471
  _charset->setCurID(bt.charset)               :481   <- hi-res layer IS told here
  memcpy(_charsetColorMap, _charsetData[...])  :484
  -> TextRenderer_v7::drawStringWrap()         :502
     or TextRenderer_v7::drawString()          :516
        buffer = vs->getPixels(0, _screenTop)  <- kMainVirtScreen, 320-wide CLUT8
        pitch  = vs->pitch
        -> drawSubstring()                     string_v7.cpp:148
           is2ByteCharacter(_lang, str[i])
             ? _gr->draw2byte(...)             -> CharsetRendererV7::draw2byte   charset.cpp:2082
             : _gr->drawCharV7(...)            -> CharsetRendererV7::drawCharV7  charset.cpp:2105
  markRectAsDirty(vs->number, bt.rect)         :533
ScummEngine_v7::removeBlastTexts()             :548  -> restoreBackground(rect)
```

Second entry point, same renderer: `drawTextImmediately()` (string_v7.cpp:451)
and the GUI (`gfx_gui.cpp:1334-1342`).

Third, and **out of scope**: SMUSH/INSANE cutscene subtitles go through
`SmushFont` (smush/smush_font.h:32), a *different* `GlyphRenderer_v7`
backed by `NutRenderer`. FT's in-game dialogue does not use it.

Measurement is a separate walk of the same string:
`TextRenderer_v7::getStringWidth()` (string_v7.cpp:48) uses
`_gr->getCharWidth()` for single-byte and the **cached** `_2byteCharWidth +
_spacing` for double-byte. Both feed centring (`drawString`:215) and word
wrap (`drawStringWrap`).


## 4. Why FT currently gets nothing, in three independent places

All three must be answered; fixing only the hook produces no visible change.

**(a) No hook.** `draw2byte` reads `_vm->get2byteCharPtr(chr)` and blits the
game's 1bpp bitmap itself (charset.cpp:2084-2101). `drawCharV7` unpacks the
game font at `_fontPtr` bpp (2127-2147). Neither offers the character to
`_hiResText.drawChar()`. This is exactly the `if (double_byte) { draw from
ROM; return; }` shape the hook census exists to catch, and
`test/engines/scumm/hires_hook_census.h:56` already records it as a
knowing exemption.

**(b) No scaled surface.** `scumm.cpp:1317` gates the multiplier on
`_game.version < 7`, so for FT `_textSurfaceMultiplier` stays 1 and
`scumm.cpp:1323` warns that a scale > 1 cannot be honoured.

**(c) No compositing step.** `drawStripToScreen()` puts the whole
text-surface composite inside `if (_game.version < 7)` (gfx.cpp:774);
v7 falls through to a bare `copyRectToScreen` (gfx.cpp:1016). Anything
written into `_textSurface` for a v7 game is never read.

FT *is* admitted by the Korean gates — `isScummvmKorTarget()`
(charset.cpp:48) is `KO_KOR && (version < 7 || GID_FT)`, and `loadKorFont()`
runs with `_useMultiFont = true` (charset.cpp:191). So the Korean fonts load
and `_useCJKMode` is true; only the drawing never reaches them. That
mismatch is precisely the "nominally supported for weeks while drawing
nothing of yours" failure the census was built for.


## 5. Recommended design

### 5.1 Hook points — two, not one, and never `printChar`

Leave the `printChar` stub exactly as it is. Add the hook to the two methods
the v7 pipeline actually calls:

- `CharsetRendererV7::draw2byte()` — charset.cpp:2082
- `CharsetRendererV7::drawCharV7()` — charset.cpp:2105

Both already appear in the census's `kDrawing[]` list
(`hires_hook_census.h:66-69`), so the test recognises a hook placed there
and the `CharsetRendererV7` entry in `kExempt` can then be deleted.

Shape, in both:

```cpp
int CharsetRendererV7::draw2byte(byte *buffer, Common::Rect &clipRect,
                                 int x, int y, int pitch, int16 col, uint16 chr) {
    if (_vm->_hiResText.drawChar(<dest>, chr, _curId, <x'>, <y'>,
                                 (byte)col, _shadowColor, _vm->_2byteShadow))
        return getCharWidth(chr);          // see 5.3 — one advance, both paths
    ... existing bitmap blit unchanged ...
}
```

The `drawChar` contract already supports this: it returns false for a glyph
the replacement font does not cover (hires_text.cpp:452, :463) and for
`kHiResGlyphKeep` overrides (:443), so a character the font misses is drawn
exactly as it is today. That fallback is what keeps the change safe.

### 5.2 Which surface — the decision that must be made before coding

`drawChar()` needs a `Graphics::Surface &`. The v7 path has a raw `byte*` +
pitch, not a Surface, and it points into the game's own 320-wide VirtScreen.
Two options:

**Option A — 1x into the game buffer (recommended first step).**
Wrap the incoming `buffer`/`pitch` in a temporary `Graphics::Surface` with
`w = clipRect.right`, `h = clipRect.bottom - y`, CLUT8, and draw at scale 1.
No change to `_textSurfaceMultiplier`, no change to `drawStripToScreen`,
`removeBlastTexts`'s existing `restoreBackground` still erases correctly.
Buys: replacement glyph *shapes* (a proper TTF-baked Hangul instead of the
9px `korean%02d.fnt` bitmap) at the game's own resolution. Does **not** buy
2x/3x.

**Option B — scaled overlay.** Requires lifting the `version < 7` gates at
scumm.cpp:1317 and gfx.cpp:774 and teaching the v7 blit path to composite
`_textSurface`. That is a much larger change: it also has to answer
`removeBlastTexts`'s erase (which today restores the game buffer, and would
then need to clear the overlay too — the same class of bug as the
`clearTextSurface()`/`markRectAsDirty` pairing in `startScene()`), plus the
`_screenTop` offset that `drawBlastTexts` already applies to the buffer
pointer.

**Do A first and land it; open a separate card for B.** They are separable,
A is measurable on its own, and B's risk is entirely in gfx.cpp rather than
charset.cpp.

### 5.3 Advance and `getCharWidth` — the invariant that will bite

v7 measures and draws in two separate walks of the string, and they must
agree or centred lines drift and wrapped lines break in the wrong place.
There are currently **three** places a double-byte advance is decided:

1. `CharsetRendererV7::draw2byte` returns `_origWidth + _cjkSpacing`
   (charset.cpp:2102), where `_origWidth = _vm->_2byteWidth`.
2. `CharsetRendererV7::getCharWidth` returns `_vm->_2byteWidth + _cjkSpacing`
   (charset.cpp:2155) — but nothing calls it for double-byte, because…
3. …`TextRenderer_v7::getStringWidth` uses its own cached
   `_2byteCharWidth + _spacing` (string_v7.cpp:80).

**That cache is a live trap.** `TextRenderer_v7`'s constructor snapshots
`vm->_2byteWidth` (string_v7.cpp:37) at `createTextRenderer()` time —
which is inside `setupCharsetRenderer()` (scumm.cpp:1832), i.e. *after*
`loadCJKFont()` but *before* any charset is selected. With
`_useMultiFont` (which FT Korean uses), `_2byteWidth` is reassigned per
charset in `CharsetRendererCommon::setCurID` (charset.cpp:380-397), and the
cached value stays at whichever font loaded first. Measuring and drawing can
therefore already disagree today, before any hi-res change. Verify this on
real FT Korean data before designing around it — if it reproduces, it is its
own bug and its own card.

Rules for the implementer:

- Route **all three** through `_hiResText.advanceFor(chr, _curId, gameWidth)`.
  Its default (`metrics=game`) returns `gameWidth` unchanged, so a map that
  does not ask for proportional metrics leaves v7 layout bit-identical.
- Do **not** use the `carry` parameter at scale 1 (Option A): the carry
  exists because a scaled font measures in surface pixels while the engine
  positions in game pixels. At m == 1 there is no remainder and passing a
  carry only risks drift. Reserve it for Option B.
- If the `_2byteCharWidth` cache proves stale, fix it by calling
  `_gr->getCharWidth(chr)` for the double-byte case too (making item 2 live)
  rather than by re-caching — one source of truth.

### 5.4 clipRect

`draw2byte` explicitly ignores `clipRect` ("I am aware of not doing anything
with the clipRect here", charset.cpp:2083) and is safe today only because
every glyph is exactly `_2byteWidth` wide. A replacement glyph is not
constrained to that. `HiResGlyphRenderer::drawGlyph` clips against the
destination surface's `w`/`h` (glyph_renderer.cpp:170-179, :196-208), so
sizing the wrapper Surface from `clipRect` in Option A gives clipping for
free — but only if it is sized from `clipRect`, not from `_screenWidth`.
State that explicitly in the patch.

### 5.5 What must NOT change

- `printChar()` keeps its `error()` stub. Nothing in this design routes v7
  through it, and removing it would re-open the state corruption of §2.
- `CharsetRendererNut` (v8/SMUSH) and `SmushFont` stay untouched and stay in
  `kExempt` — separate renderers, separate card.
- Every v0-v6 path: `CharsetRendererClassic::printChar` (charset.cpp:1269),
  `CharsetRendererV3::printChar` (:1033), the Towns `drawBits*` hooks.
  The v7 work adds call sites; it must not edit those.
- The `advanceFor` default must stay "return `gameWidth`", so a game with no
  map is byte-identical.
- Non-Korean v7 (English FT/Dig/COMI) must be provably unaffected: the hook
  short-circuits on `!_enabled || !_fontsLoaded` (hires_text.cpp:432).


## 6. Risks, and the tests that close them

| risk | how it shows | check |
|---|---|---|
| Hook drawn but never composited (Option B, or A done into the wrong buffer) | text unchanged on screen, `HRTEXT` log non-zero | must be a **glyph-shape** diff against a `NOHIRES=1` control, not a counter |
| Measure/draw disagree (§5.3) | centred lines off-centre, wrap in wrong place, glyphs touching | capture a long centred FT line at 1:1 (`cap11.sh`) vs control; compare glyph start columns |
| Stale `_2byteCharWidth` cache | same, but present *before* the change | reproduce on FT Korean first; if present it is a pre-existing bug — separate card |
| `clipRect` ignored with a wider glyph | last glyph of a line bleeds past the box | draw a line that ends exactly at `clipRect.right` |
| Erase path misses the new ink | ghost text after the subtitle clears | run a talk-then-walk scene; diff the frame after `removeBlastTexts` against the pre-talk frame |
| v5 regression from touching shared `CharsetRendererClassic` state | MI2/Indy4 text moves | A/B a v5 target against a control binary, same save, same frame |
| English v7 changed | any diff at all | FT/Dig English A/B must be pixel-identical |

Suite gates that must be green, and one that must be *updated*:

- `make test` — re-read the current total before quoting it; it was 520 at
  the last `.trs` card and this memo did not build. Adding the hook makes
  `hires_hook_census.h:56` (`CharsetRendererV7` exemption) **wrong**; the
  test `test_no_exemption_outlives_its_renderer` will not catch that, but
  the honest change is to delete that `kExempt` entry and add
  `"CharsetRendererV7"` to `kHooked[]` in
  `test_the_known_hooks_are_still_wired_up` (:525). The census total in the
  commit message changes accordingly.
- Both build configurations, per the upstream-contribution constraint:
  `--enable-engine=scumm,scumm_7_8` **and** without `scumm_7_8`. Everything
  touched here is inside `#ifdef ENABLE_SCUMM_7_8`, so the second build is
  the one that catches a stray reference.
- No-FreeType build: the hook itself is FreeType-free (baked `.fnt`), but
  confirm.


## 7. Patch plan (one card each)

1. **A1 — wrap the destination.** Helper turning
   (`buffer`, `pitch`, `clipRect`) into a CLUT8 `Graphics::Surface`.
   Alone, no behaviour change. close: builds both configs, 520 tests.
2. **A2 — hook `draw2byte`.** Replacement Hangul at 1x for FT Korean.
   close: glyph-shape diff vs `NOHIRES=1` control at a fixed FT dialogue
   frame; English FT pixel-identical.
3. **A3 — hook `drawCharV7`.** Latin through the same layer, gated on the
   map's `[latin] enabled`. close: as A2, plus `[latin] enabled=false`
   leaves Latin byte-identical.
4. **A4 — unify the advance.** `advanceFor` in all three width sites;
   resolve or card off the `_2byteCharWidth` cache. close: centred-line
   glyph-start columns match the control under `metrics=game`.
5. **A5 — census.** Delete the `CharsetRendererV7` exemption, add it to
   `kHooked`. close: `make test` green with the new total in the message.
6. **B — scaled v7 overlay.** Separate card; do not start before A lands.

The `close:` on every card above is a picture or a column measurement, not a
counter — `HRTEXT > 0` was already shown once in this project to read
identically before and after a change that did nothing.
