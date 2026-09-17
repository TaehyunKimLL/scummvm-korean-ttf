# Font identity in SCI: why the current shape is wrong, and where it should go

Status: **design note**, written after Japanese support exposed the problem.
No code in this note is implemented yet.

Every claim is marked `[source]`, `[measured]` or `[unmeasured]`.

## The complaint, stated precisely

`[measured]` A language currently owns a font *number*:

```
graphics/cache.cpp:109   fontId == 1001 && getLanguage() == KO_KOR  -> GfxFontKorean
graphics/cache.cpp:112   fontId ==  900 && getLanguage() == JA_JPN  -> GfxFontSjis
graphics/text16.cpp:753  SetFont(1001)   // "this text looks Korean"
graphics/text16.cpp:781  SetFont(900)    // "this text looks Shift-JIS"
```

`[measured]` Fourteen sites in `engines/sci/graphics` mention 1001 or 900.
The consequences, each observed while adding Japanese:

**A game that does not use the magic number cannot have that language.**
KQ5's Japanese FM-TOWNS release ships fonts 0, 1, 4, 8, 9, 69, 600 and 999 -
every one a 128-glyph single-byte font - and **no font 900**. The SJIS path is
unreachable there by construction.

**A game that does use it loses its own font.** `SetFont(1001)` replaces
whatever font the script chose. KQ1 asks for four fonts at different heights
(0 at 8px, 4 at 9px, 300 at 12px, 999 at 8px); once the switch fires, that
distinction is gone for the rest of the string.

**One number cannot hold three scripts.** English, Korean and Japanese text
can appear in one game - Police Quest 2 PC-98 draws English and Japanese into
the same box - but 1001 means "the Korean font" and 900 means "the SJIS font".
There is no id that means "whatever this character needs".

## What a font id is actually being asked to carry

`[measured]` Three separate things, currently conflated:

1. **Which typeface the script wants.** A real SCI concept: font 4 is the
   small one, font 300 is the large one, and scripts pick deliberately.
2. **Which script system the text is in.** Not an SCI concept at all - the
   original interpreters inferred it from the bytes, exactly as
   `SwitchToFont1001OnKorean` does.
3. **Whether the glyphs bypass the normal blit.** `fontId = 1001` is always
   set together with `doubleByteMode = true`, which suppresses the screen
   update because hires glyphs go to the text plane. `[measured]` Dropping
   only the font switch and keeping the flag made Korean text render thin and
   then vanish - white pixels in the button row fell from 2652 to 1234. The
   two are not independent today.

Item 1 is legitimate. Item 2 belongs to the text, not the font. Item 3 is a
rendering property that `SciEngine::usesHiresDoubleByteText()` already
answers, and it should not be inferred from a font number.

## Direction: one font id, a set of faces behind it

`[unmeasured]` The font a caller names stays the font it gets. Behind that
single id sits a **set**: one face per script system, chosen per character by
coverage, not by language.

```
GfxFontSet (id 4)
  ├── resource face   font.004        U+0020..U+00FF   the game's own glyphs
  ├── DBCS face       korean.fnt      U+AC00..U+D7A3   when present
  └── Unicode face    sci.uni         whatever it holds
```

Lookup is "first face that has this code point", with the resource face first
so single-byte text stays byte-identical. `[measured]` That ordering rule is
not speculative - it is what the current adapter already does, and it is why
English metrics stayed intact: serving Latin from the Unicode bundle made
fonts of height 12 and 9 both report 8 and pushed menu text outside its
button.

What this removes:

- `SetFont(1001)` and `SetFont(900)`. A character that needs the DBCS face
  gets it without changing the caller's font. `SwitchToFont*` becomes
  "does this line contain double-byte text", which is what its callers at
  text16.cpp:463 and :479 already use it for - they discard the return value.
- The `fontId == 1001 && KO_KOR` pair in the cache. A face is added to the set
  when its file exists, with no language test.
- The language-keyed driver entry. `[measured]` That table needed a second row
  for `JA_JPN` purely because the row said `KO_KOR`; asked as "does this
  target render hires double-byte text" it needs one row.

`[unmeasured]` What it does NOT remove: the `doubleByteMode` screen-update
rule. That is a real property of drawing on the hires text plane. It should be
asked of the face that drew - "did this glyph go to the text plane" - rather
than inferred from the font number, but it stays.

### What `doubleByteMode` is actually standing in for

`[source]` The hardware answer is in text16.cpp's own comment, and it reframes
the flag entirely:

> the SJIS text is drawn in PC-9801 **text mode** and the **text mode layer is
> always displayed on top of the graphics layer**, so it can never get
> corrupted by graphics updates (with an emulator you can see how even the
> mouse cursor is drawn under the Japanese text). [...] we also need to prevent
> graphics updates for SJIS lines, since **we don't emulate the PC-9801 text
> mode layer** to that extent

`[source]` So on real PC-98 hardware Japanese text lives on a **separate
overlay plane** that graphics writes cannot touch. The original interpreter
therefore needs no suppression at all. `doubleByteMode` is ScummVM's
substitute for a layer it does not emulate: it protects the glyphs by skipping
the blit that would overwrite them.

`[source]` The driver layer already models a piece of this.
`PC98Gfx16ColorsDriver` carries `kFontStyleTextMode`, used only for PQ2,
because text-mode print takes its colour from a **system palette outside the
normal 16 colours** - `remapTextColor()` exists solely to translate that, bug
included.

`[measured]` This explains why the flag could not simply be dropped for the
Unicode path: SCVMUNI glyphs go to the hires text plane, which in ScummVM is
also unprotected, so they need the same substitute. Turning it off made Korean
text render and then vanish (button-row white pixels 2652 -> 1234).

### Why there is no overlay plane today, in code

`[measured]` `UpscaledGfxDriver::drawTextFontGlyph` writes glyphs **straight
into `_scaledBitmap`**, the same buffer the background is scaled into:

```c
byte *scb = _scaledBitmap + hiresDestY * _screenW * _srcPixelSize + ...;
_renderGlyph(scb, _screenW, src, pitch, hiresW, hiresH, transpColor);
updateScreen(hiresDestX, hiresDestY, hiresW, hiresH, ...);
```

`[measured]` and `copyRectToScreen` refills that same buffer from
`_currentBitmap` on every background update. One buffer, two writers, last
writer wins - which is exactly the corruption PC-98 hardware cannot suffer,
because there the text layer is a separate plane composited on top.

So `doubleByteMode` is not a CJK quirk at all. It is the consequence of
folding two hardware planes into one buffer.

### The end state this points at

`[unmeasured]` Give the driver a real text overlay: a second buffer the same
size as `_scaledBitmap`, written only by `drawTextFontGlyph`, composited over
the scaled background in `updateScreen`. Then:

- No suppression is needed for any language; `show && !doubleByteMode`
  collapses to `show`, and the flag disappears rather than being carried.
- Background updates stop needing to know that text exists, so the
  `usesHiresDoubleByteText()` pre-update in paint16.cpp goes away too.
- `[source]` The PQ2 layout differences the text16.cpp comment describes -
  the uncentred F1 headline, the copy-protection dialogs - come from ScummVM
  doing font switching and width measurement that the original interpreter did
  NOT do, precisely because it had the overlay. With a real overlay those
  workarounds become removable, and the comment's "could be done, but I don't
  see why we should" is answered: because it is what makes every other
  language work without special cases.

`[unmeasured]` Cost: one extra full-screen byte buffer per driver that renders
hires text, plus a composite step on update. Measure before adopting - the
composite runs on every screen update, not only on text.

`[unmeasured]` This is larger than FontSet and must be measured separately.
FontSet should therefore **carry** `doubleByteMode` rather than entrench it:
no new code should infer it from a font number, so that deleting it later
touches one place.

## Prior art in this tree, to build on rather than reinvent

`[source]` Branch `wt/f1-dbcsfont-src` already has commit `94b5143334c`,
"GRAPHICS: Share one glyph rasteriser between the Korean and SJIS fonts",
adding `graphics/dbcsfont.{h,cpp}` with `DBCSFontBase` and a unified
`DBCSDrawingMode`. Its own comment records the measurement that made the merge
safe: `FontKorean::kShadowMode` **is** `FontSJIS::kShadowRightMode`, same value
and same rendering, and Korean fonts never reach modes 3 or 4.

`[measured]` A stale `graphics/.deps/fontset.d` in this build tree names
`graphics/fontset.cpp` and `graphics/fontset.h`, so a `FontSet` existed here
before and was removed. `[unmeasured]` Its design is not recoverable from the
dependency file alone; the name should be reused only after finding that work,
because two different `FontSet`s would be worse than none.

## Sequence, each step closed by a measurement

`[unmeasured]` **1. Ask the rendering question directly.** Replace the
language tests in the driver table and in `paint16.cpp` with
`usesHiresDoubleByteText()`. Partly done - `paint16.cpp` already uses it.
Close: the driver table has one row instead of one per language, and all three
KQ1 configurations still render.

`[unmeasured]` **2. Introduce `GfxFontSet` implementing `GfxFont`.** Faces
ordered resource-first. Initially built for every id, holding only the
resource face, so behaviour cannot change. Close: the glyph request sequence
(see M8_CODEPOINT_PLAN.md) is byte-identical for English, Korean and Japanese.

`[unmeasured]` **3. Move the DBCS and Unicode faces into the set.** The cache
stops testing font numbers. Close: Korean and Japanese still render with
`korean.fnt`/`sci.uni` present, and the button-row white-pixel count stays at
2652 for Korean.

`[unmeasured]` **4. Delete `SetFont(1001)` / `SetFont(900)`.** `SwitchToFont*`
returns only "this line is double-byte". Close: KQ1 keeps using fonts 0, 4,
300 and 999 at their own heights - measured 8, 9, 12, 8 - while drawing
Korean, which is impossible today because the switch overwrites the id.

`[unmeasured]` **5. The real test of the design**: a game with no font 1001
and no font 900 renders Korean AND Japanese from a bundle. KQ1 is exactly that
game, so this is reachable now rather than hypothetical.

## The measurement that would have refuted this design — taken, and it holds

`[measured]` If any game requested font 1001 or 900 **for its own typeface**,
collapsing the number into a set would change that game's appearance. A probe
on `GfxText16::SetFont` logged every request across three KQ1 runs that differ
only in which bundle is present:

```
English  : font 4 x48   font 300 x33   font 0 x11        1001/900: NONE
Korean   : font 1001 x52  font 4 x24  font 300 x20  font 0 x11
Japanese : font  900 x59  font 4 x24  font 300 x22  font 0 x14
```

`[measured]` The same game, same scripts, same resources. The only difference
is the bundle, and the only new font id is the language marker. English never
asks for 1001 or 900 at all - **every one of those 52 and 59 requests is
manufactured by `SwitchToFont1001OnKorean` / `SwitchToFont900OnSjis`**, not by
the game.

`[measured]` The counts also show what the switch costs: it fires per line, so
a Korean run spends 52 font changes re-selecting a face the script never
asked for, and each one overwrites the script's own choice of font 4 or 300.

So 1001 and 900 carry no typeface meaning in this game, and a set keyed on the
id the script actually chose loses nothing.

`[unmeasured]` Still to check before the switch is deleted: the PC-98 Japanese
releases, which ship a real font 900 resource. There the number may be both a
marker and a face, and the sweep above should be repeated on one of them -
`gamedata` has PQ2 and SQ4 PC-98 targets.

## Probe note

`[source]` The probe must not call `EngineState::getCurrentCallOrigin()`.
Fonts are requested before any script is loaded and that call dereferences the
current script: it segfaulted the engine at startup, and the harness reported
only `NO_WINDOW`, which reads like a display problem rather than a crash in
the probe. `[measured]` Also, gating the probe on `ConfMan.hasKey(...)`
silently produced zero output - the key sat in the application domain while
the lookup ran against the game domain. An unconditional `debug()` is the
only form that reliably runs.
