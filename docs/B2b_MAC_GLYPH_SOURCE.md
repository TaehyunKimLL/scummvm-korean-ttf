# B2b — Antialiasing and a replacement font on the Mac path: where the hook goes

Status: investigation and design only. No engine code changed. Everything
below is measured on this tree unless it says otherwise.

Measured at `7b0a8c9899f` (branch `hires-text`), 2026-09-08. `make test`: 531
tests OK. `git status` in `repo/scummvm`: no tracked file modified.

Companion to `B2_MAC_RENDERER.md`, which established *what the Mac data flow
is*. This card answers the next question: given that flow, **where does a
replacement font hook go, and what does the Mac path actually get out of it?**

The premise this card was opened with was that handing the layer the stencil
"writes colour 0 over every glyph". That premise is wrong, and the way it is
wrong decides the design — see "Why the compositor is the wrong place" below.


## 1. What the Mac path is being asked to deliver

Three things are wanted from a hi-res hook, and they are not equally
available here. Naming them separately matters, because two of them are
achievable on this path and one is not.

| want | available on Mac? | why |
|---|---|---|
| **replacement typeface** (Korean, or a better Latin face) | **yes** | `_macScreen` is CLUT8 and the glyph renderer writes palette indices into CLUT8. No format conversion. |
| **higher resolution** (a 2x cell) | **yes, already** | `_macScreen` is 640x400/480 and the renderer already works in doubled coordinates (`macLeft = 2 * _left`, `charset.cpp:1861`). |
| **antialiasing** | **no** | measured below: there is no coverage plane on this path, and the compositor that would read one is never reached. |

The third row is the one worth being blunt about, because "antialiasing" is
in this card's title. On the Mac path it is not a matter of effort. It is
structurally unavailable, for two independent reasons that would each have to
be removed on their own.


## 2. The current shape, in one paragraph

`CharsetRendererMac::printCharInternal()` (`charset.cpp:2025`) draws each
glyph **twice**:

```cpp
_font->drawChar(&_vm->_textSurface, chr, x, y, 0);          // colour 0
...
_font->drawChar(_vm->_macScreen, chr, x, y + 2 * _vm->_macScreenDrawOffset,
                color);                                     // the real colour
```

`_macScreen` holds the picture the user sees. `_textSurface` gets the same
glyph *shape* in colour 0 and is never displayed; its only reader is
`mac_drawStripToScreen()` (`gfx_mac.cpp:52`), which keys on it:

```cpp
if (ts[2 * w] == CHARSET_MASK_TRANSPARENCY)
    mac[2 * w] = pixels[w];
```

For each output pixel: if the text plane says "no text here", copy the game
picture over it; otherwise leave `_macScreen` alone. The glyph is already in
`_macScreen`; the text plane exists only to stop the background erasing it.
So on this path `0` means *occupied* and `CHARSET_MASK_TRANSPARENCY` (0xFD)
means *empty* — the inverse of the DOS path, where the text plane holds glyph
colour indices and the compositor writes text **over** the background.


## 3. Why the compositor is the wrong place to hook — and why the card's
   stated reason was not the real one

The card's premise: pass the stencil to the layer and the layer writes colour
0 over every glyph, damaging them.

That is not what happens, and the difference is the whole design. `B2_MAC_RENDERER.md`
established the mechanism by measurement (same binary, gated on an ini key, 50+
duplicate glyphs written into `_macScreen` with the stencil untouched → screen
diff of **exactly zero** pixels, ink 2055 vs 2055, empty bbox). The consequence:

**A hi-res hook at `_textSurface` on the Mac path would not corrupt anything.
It would do nothing at all — visibly, silently nothing.**

Trace it through:

- `HiResText::drawChar()` writes the glyph body in `color` into the
  destination surface. On this path that destination is the stencil, where
  `mac_drawStripToScreen` reads any non-`0xFD` value as merely "occupied".
  The index carries no colour meaning here, so the replacement glyph's colour
  is discarded.
- It writes coverage into the parallel coverage plane — which is never read,
  because `mac_drawStripToScreen` returns before the blending compositor ever
  runs (`gfx.cpp:756`: `if (_macScreen && version <= 3) { mac_drawStripToScreen(...); return; }`).
- `_macScreen`, the surface actually displayed, still holds the **game's own**
  glyph, because nothing removed it.

Net result: the original Mac glyph, unchanged, with a slightly different
stencil shape around it. A replacement font that appears to be ignored.

That failure mode — silent no-op rather than visible corruption — is worse for
review than the one the card assumed, because a counter-based check would
report success. It is exactly the trap `measuring-feature-effect.md` is about.

**Therefore the hook belongs at the renderer's glyph source, not at the
compositor.** The compositor is correct as written and needs no knowledge of
replacement fonts: it keys a stencil, and a stencil of a better-shaped glyph
keys exactly as well as a stencil of the original.


## 4. Measured on this tree, this session

The enablement table in `B2_MAC_RENDERER.md` was measured on a worktree that
no longer exists. Since the whole design rests on it, it was re-run against
the current binary (`repo/scummvm/scummvm` at `7b0a8c9899f`).

Fixture (`harness/b2fixture.py`): the Mac game data symlinked into a throwaway
directory beside a `hires_text.map` with `[latin] enabled=true` and the
`hrlat%02d.fnt` faces from `indy3kor`. An English Mac game has no double-byte
text, so Latin routing is the only way to reach the layer at all.

| cell | started | layer enabled | fonts loaded | HRTEXT draws | backend |
|---|---|---|---|---|---|
| `i3mac-s2` | yes | 1 | 3 | **0** | 640x480 |
| `i3mac-s3` | yes | 1 | 3 | **0** | 640x480 |
| `loommac-s2` | yes | 1 | 3 | **0** | 640x480 |
| `i3dos-s2` | yes | 1 | 3 | **7** | 640x480 |

The last row is the control that makes the others readable: the *same* map,
the *same* fonts, the *same* game, on the DOS renderer — and the layer draws.
On Mac it loads everything and is never called.

`HRTEXT=0` alone would be ambiguous ("maybe no text was drawn"), so the
captures were opened rather than trusted:

- `i3dos-s2` at t=50 (`captures/2026-09-08-b2glyphsrc/i3dos-s2_t50.png`) —
  the DOS control, with the verb line and dialogue drawn in the smooth
  replacement face. Log: `HRTEXT charset=0 font=0 cell=16x16 "PushPullGive
  OpenCloseLookWalk to..."`, i.e. the layer naming the exact strings it drew.
- `i3mac-s2` at t=50 (`i3mac-s2_t50.png`) — the same map and fonts on the Mac
  build, `HRTEXT=0`, and the screen shows the game's own Mac font.

So the exemption in the hook census is true rather than assumed: on the Mac
path the layer is loaded, enabled, and never offered a character.

### 4a. Antialiasing has nowhere to go — two independent blocks

**(i) There is no coverage plane.** `_overlay.create(..., withCoverage=false)`
(`scumm.cpp:1837`) and `createCoverage()` returns early unless `_config.alpha`
(`hires_text.cpp:698`). The earlier session's probe observed `cov=(nil)` at
the draw site. There is physically nowhere to record partial coverage.

**(ii) Asking for alpha on this path does not enable blending — it destroys
the screen.** This is new, and it is the sharpest result of this session.

Cells `i3mac-s2a` and `i3dos-s2a` are the same fixtures with `alpha=true`:

```
i3mac-s2a  |  hi-res text enabled: scale 2, alpha on ...
           |  hi-res text blending into ABGR8888@4
i3dos-s2a  |  hi-res text enabled: scale 2, alpha on ...
           |  HRTEXT=7
```

Frame statistics (`harness/tools/b2frame.py`), alpha off vs alpha on, same
timestamp:

```
i3mac-s2/cap_t50.png    640x480  mean_lum= 72.190  colours=    7  peak=255
i3mac-s2a/cap_t50.png   640x480  mean_lum=  4.364  colours=   27  peak=192   <-- Mac
i3dos-s2/cap_t50.png    640x480  mean_lum= 46.717  colours=  110  peak=255
i3dos-s2a/cap_t50.png   640x480  mean_lum= 46.242  colours=  445  peak=255   <-- DOS
```

Opening the captures rather than reading the numbers:

- **DOS + alpha** (`i3dos-s2a-alpha_t50.png`): picture intact, text readable,
  colour count *up* (110 → 445) exactly as blending should do.
- **Mac + alpha** (`i3mac-s2a-alpha_t50.png`): the Indy 3 "Translation notes"
  notebook, **repeated four times horizontally and rendered near-black**.

The four-fold horizontal repeat is the tell. `scumm.cpp:1599` sees
`wantsAlpha()` and negotiates a 32bpp screen (`ABGR8888@4`, confirmed in the
log), but `mac_drawStripToScreen()` ends by handing the backend `_macScreen`
raw:

```cpp
_system->copyRectToScreen(_macScreen->getBasePtr(...), _macScreen->pitch, ...);
```

`_macScreen` is CLUT8 — one byte per pixel — and the screen is now four bytes
per pixel. Each row of index bytes is read as a quarter-row of ABGR pixels,
which is precisely the 4x horizontal repeat seen, and low palette indices read
as near-zero channel values, which is the near-black. The Mac compositor never
learned about the blended path because it returns before reaching it.

This is a **live defect**, not merely a design constraint: a user who puts
`alpha=true` in a map for a Mac game today gets an unreadable screen with no
warning. The DOS control proves it is Mac-specific rather than blending being
broken generally.

### 4b. Scale 3 is silently discarded

`scumm.cpp:1474` assigns the Mac multiplier **after** the hi-res block at
`scumm.cpp:1317`:

```
line 1317   if (_hiResText.enabled() && _game.version < 7)
line 1318       if (_textSurfaceMultiplier <= 1)
line 1319           _textSurfaceMultiplier = _hiResText.scale();     // 3
...
line 1474   if (_game.id == GID_INDY3 || _game.id == GID_LOOM || ...)
line 1475       _textSurfaceMultiplier = 2;                          // overwritten
```

The `i3mac-s3` run above confirms the silence: the log carries
`hi-res text enabled: scale 3` and **no warning**, and the backend is
640x480 — the scale-2 Mac geometry. Contrast the FM-Towns case a few lines up,
which *does* warn ("this platform already scales text by %d; ignoring the
hi-res scale of %d"); it warns only because it runs after the platform set its
own multiplier, and the Mac assignment runs after the check. Every later
consumer sees 2, so nothing is misallocated — the only defect is the silence.

### 4c. Loom Mac reaches the distaff, and its stencil-only path is real

`B2_MAC_RENDERER.md` listed "Loom was not captured" as unmeasured, because
Escape does not dismiss Loom's difficulty menu and earlier runs never got past
it. `harness/b2loomdistaff.sh` clicks STANDARD instead, and reaches the draft
screen (`captures/2026-09-08-b2glyphsrc/loommac-draft_t120.png`): the twelve
note-staff boxes with **"Throw"** drawn above them.

That capture contains both Loom Mac glyph paths in one frame. "Throw" is
ordinary `printCharInternal` text; the note glyphs beside it are the
`color == -1` stencil-only redraw at `charset.cpp:1915`. Measured cell of the
drawn text (`harness/tools/b2cell.py`, window x=296..366):

```
ink rows 200..220  height=21  total=336
```

A 21-row covered cell in a doubled surface — consistent with
`getFontHeight()` returning `_font->getFontHeight() / 2` and the earlier
probe's `fontH=23` doubled cell. That is the box a replacement glyph has to
fit, and it is the number `noteGameCharset()` would need.

### 4d. A third glyph source exists that neither document had named

Indy 3 Mac has **three** places glyphs reach `_macScreen`, not two:

1. `CharsetRendererMac::printCharInternal` — verb line and in-scene text.
2. `MacIndy3Gui::printCharToTextArea` (`macgui_indy3.cpp:1077`) — dialogue,
   drawn into a private 448x47 `_textArea` and stamped wholesale by
   `mac_drawIndy3TextBox()` (`gfx_mac.cpp:118`). `printChar` routes here when
   `vs->number == kTextVirtScreen && _game.id == GID_INDY3`
   (`charset.cpp:1902`), so **Indy 3 Mac dialogue never passes through
   `printCharInternal` at all**.
3. `MacIndy3Gui::Widget::draw` (`macgui_indy3.cpp:320-348`) — the verb button
   labels, drawn with `kIndy3VerbFontBold`/`Outline` into `_verbGuiSurface`,
   which is `_macScreen->getSubArea(...)` (`macgui_indy3.cpp:900`, with
   `MacGuiImpl::_surface(_vm->_macScreen)` at `macgui_impl.cpp:55`), and
   pushed by `copyDirtyRectsToScreen()` straight through
   `_system->copyRectToScreen` (`macgui_indy3.cpp:1972`).

Source 3 matters for scoping: it bypasses the stencil **and** the charset
renderer entirely. A hook at `printCharInternal` alone leaves Indy 3 Mac with
a replacement font on some text and the original font on the verb buttons and
the dialogue box — three typefaces on one screen. Loom has neither split.


## 5. The shape a Mac implementation wants

Not a compositor change. The change is at the renderer's **glyph source**:
`printCharInternal` asks `_font` — a `Graphics::MacFONTFont` from the game's
resource fork — for each glyph, and everything the layer offers is a different
answer to that one question.

```cpp
void CharsetRendererMac::printCharInternal(int chr, int color, bool shadow,
                                           int x, int y) {
	...
	// stencil: the layer's glyph shape, in colour 0, as now
	if (!_vm->_hiResText.drawStencil(_vm->_textSurface, chr, _curId, x, y))
		_font->drawChar(&_vm->_textSurface, chr, x, y, 0);

	if (color != -1) {
		color = getTextColor();
		// the visible glyph, into _macScreen
		if (!_vm->_hiResText.drawChar(*_vm->_macScreen, chr, _curId,
		                              x, y + 2 * _vm->_macScreenDrawOffset,
		                              color, shadowColor, 0,
		                              nullptr, /*withCoverage=*/false))
			_font->drawChar(_vm->_macScreen, chr, x, y + ..., color);
	}
}
```

**Both calls must succeed or both must fall through.** A glyph in `_macScreen`
but not the stencil is erased by the next background repaint (measured: zero
pixels changed); a glyph in the stencil but not `_macScreen` leaves a hole.
This is the same paired-write hazard the overlay work already hit, and the
same cure applies: one call that does both, not two callers who must remember.

Note `withCoverage=false`: the parameter already exists on `drawChar`
(`hires_text.h:321`) for exactly this reason on the v7 path — a caller whose
surface is not composited through the coverage plane must not record coverage,
or it is never cleared and goes on suppressing later strokes.

### Four things that make this cheaper than it looks

1. **The Mac surface is already 2x.** A scale-2 font drops straight in; no new
   scaling arithmetic.
2. **The grid is knowable.** `getFontHeight()` returns
   `_font->getFontHeight() / 2`; measured 21 covered rows on the doubled cell
   (§4c). `CharsetRendererMac::setCurID` is the natural place to report it, as
   `CharsetRendererV3::setCurID` already does (`charset.cpp:464-468`).
3. **`_macScreen` is CLUT8**, which is what the glyph renderer writes. No
   format conversion.
4. **The stencil is shape-only** — no colour, no coverage. The second call is
   strictly simpler than the first: a 1-bit dilation of the glyph.

### Four things that are genuinely harder

1. **Antialiasing cannot be had** (§4a): no coverage plane, the blending
   compositor is unreachable, and requesting it today corrupts the screen. Mac
   gets a **replacement typeface at 2x, aliased**. That is still a real gain —
   the Mac fonts are the game's own bitmaps, and a Korean face is otherwise
   impossible there — but `alpha=true` must be **refused with a warning**, not
   silently ignored, and today it is neither.
2. **Loom's note-name hack redraws through the same function.**
   `charset.cpp:1915` calls `printCharInternal(note, -1, ...)` to touch *only*
   the stencil. A hook must preserve that: `color == -1` means stencil-only,
   and a layer call that ignores it draws notes onto the picture that the
   original only re-stencilled. Now capturable (§4c).
3. **Indy 3 has two further glyph sources** (§4d), so "Indy 3 Mac support"
   means three hooks, not one, or it means visibly mixed typefaces.
4. **B/W mode dithers per pixel.** `_renderMode == kRenderMacintoshBW` draws
   into `_glyphSurface`, then stipples onto `_macScreen`
   (`charset.cpp:2062-2077`). A replacement glyph must go through the same
   stipple, so the layer would have to hand back a bitmap rather than draw
   directly — a third code path. `_glyphSurface` is sized
   `font->getMaxCharWidth() x getFontHeight()` (`charset.cpp:1794`), so a
   larger replacement glyph would clip there. Unverified: the detected target
   is `indy3-ega-mac`, so only the colour branch has ever run.


## 6. Options

**A. Leave it exempt, make the exemption honest, and fix the two silent
defects.** Replace the census reason with the measured mechanism; add the
missing scale-3 warning; make `alpha=true` on the Mac path warn and refuse
rather than negotiate a 32bpp screen the Mac compositor cannot feed. Roughly
a comment plus ten lines.
*Risk*: low — no new rendering path. *Verification*: rerun the §4 table (the
DOS row is the control); `i3mac-s3` must now warn; `i3mac-s2a` must match the
alpha-off capture instead of going black.

**B. Loom Mac only, aliased, scale 2.** Loom has no text-box split and no verb
GUI widgets, so `printCharInternal` is the single point of entry and the
paired write is containable. Skips B/W (warn and fall through) and refuses
alpha.
*Risk*: medium — the paired write is the failure mode, and it fails silently.
*Verification*: A/B the draft-screen capture from §4c against the same frame
on a control build; the "Throw" label must change shape while the note glyphs
stay identical, which simultaneously tests the hook and the `color == -1`
path. Whole-frame diffs are useless here (background animation dominates);
compare the band, as `harness/tools/b2band.py` does.

**C. Indy 3 Mac as well.** Needs hooks in `printCharToTextArea` *and* the verb
widget draw, each with its own coordinate handling and its own surface.
*Risk*: high, and partial completion looks worse than not starting: one or two
of three sources replaced means two typefaces on screen at once.
I would not start this until B is on a real screen and judged.

**Recommendation: A now; B as a separate card if Mac targets matter to the
upstream submission.** The reason to prefer A is not effort — it is that the
Korean fan translations this work exists for are all DOS, so B has no user
today, and upstream review is easier to win with an accurate exemption plus
two real bug fixes than with an unexercised second rendering path.

Note that A is not merely documentation: §4a and §4b are two user-visible
defects (silent scale downgrade, screen corruption under `alpha=true`) that
this investigation found and that stand independently of whether B is ever
built.


## 7. Decisions needed from the user

1. **Is Mac in scope for the upstream submission at all?** If the answer is
   "DOS only", option A closes this line of work permanently and B/C are never
   opened. Everything below only matters if Mac is in scope.
2. **Option A, B, or C?** (Recommendation: A now, B later if Mac matters.)
3. **Should the two defects in §4a/§4b be split into their own card?** They
   are independent of the replacement-font question and are arguably
   upstreamable on their own merits — a silent scale downgrade and a corrupted
   screen are bugs in the current hi-res work regardless of Mac font support.
4. **If B: is aliased text acceptable on Mac?** Antialiasing is unavailable
   without reworking the Mac compositor, which is a much larger change than B
   itself. B delivers a replacement typeface at 2x with hard edges.
5. **If C: is partial Indy 3 coverage acceptable as an intermediate state?**
   Hooking `printCharInternal` alone leaves the dialogue box and verb buttons
   in the original face — three typefaces on one screen.


## 8. Measurement rules this followed

- Every screen claim above was made by **opening the capture**, not by reading
  a counter. The alpha result is the case in point: `ALIVE=yes`,
  `assert/core=0`, a *higher* colour count (7 → 27) and a successfully
  negotiated 32bpp screen all read as success. The screen was black.
- Every Mac cell has a DOS cell beside it with the same map, fonts and game.
  Without `i3dos-s2a` intact, "Mac goes black under alpha" could equally have
  meant "blending is broken".
- `HRTEXT=0` is reported next to `hi-res font=` and `ALIVE=`, so a run that
  died, a run that drew no text, and a run whose layer never loaded cannot be
  confused with one another.
- Byte-identical captures are checked for: the first Loom attempt produced
  five frames with one md5 between them, i.e. the click never landed. A
  timestamp is not evidence that anything advanced.


## 9. Reproducing

```bash
cd ~/work/scummvm

# the enablement table (add/remove cells by name; the DOS row is the control)
python3 harness/b2fixture.py i3mac-s2 i3mac-s2a i3mac-s3 loommac-s2 \
                             i3dos-s2 i3dos-s2a

# drive one cell under Xvfb and capture 1:1
bash harness/b2cap.sh i3dos-s2 640 480 30 50
bash harness/b2cap.sh i3mac-s2a 640 480 30 50

# whole-frame comparison for the alpha A/B
python3 harness/tools/b2frame.py /tmp/b2fix/i3mac-s2/cap_t50.png \
                                 /tmp/b2fix/i3mac-s2a/cap_t50.png

# Loom Mac past its difficulty menu, to the draft screen
bash harness/b2loomdistaff.sh :593 /tmp/B2LD 25 45 70 95 120
python3 harness/tools/b2cell.py /tmp/B2LD_t120.png 296 366 200 232

# the test suite, with the sysroot toolchain on PATH
bash harness/b2maketest.sh
```

`b2fixture.py` and `b2cap.sh` take the binary from `$BIN` and refuse to run if
it is missing, rather than producing a table of empty logs that reads as "the
layer drew nothing" — the failure mode that made the previous table
unreproducible once its worktree was deleted.

Captures referenced above are committed under
`captures/2026-09-08-b2glyphsrc/`.
