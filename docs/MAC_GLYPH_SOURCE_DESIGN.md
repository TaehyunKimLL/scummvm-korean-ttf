# Mac renderer: where a hi-res glyph source goes — design, for decision

Status: **design only, awaiting a decision from you.** No engine code changed
by this document; see §9.

Synthesis of two investigations: `B2_MAC_RENDERER.md` (what the Mac data flow
is, measured) and `B2b_MAC_GLYPH_SOURCE.md` (where a hook belongs and what the
Mac path can actually deliver, measured). This document exists so the decision
can be made without reading both: it states the mechanism, the two live defects
found on the way, the options with their risks, and the exact verification each
option would have to pass.

Source references are line numbers at `7b0a8c9899f` (branch `hires-text`),
re-read against the tree while writing this. Build for this document:
worktree `repo/scummvm/.worktrees/t_2d387500_svm`, `ERRORS=0`, `make test`
**531 tests OK**.

---

## 1. What the card asked, and the one-line answer

> Should the Mac path get antialiasing / a replacement font, and if so, where
> does the hook go?

**Replacement typeface: yes, and the hook goes at
`CharsetRendererMac::printCharInternal`'s glyph source — not at the
compositor, and not at `_textSurface`.**
**Antialiasing: no. It is structurally unavailable on this path**, for two
independent reasons, both measured (§4).

Everything below is the evidence for those two sentences and the cost of
acting on them.

---

## 2. What `CharsetRendererMac::printChar` does today

`charset.cpp:1856` `printChar()` → doubles the coordinates
(`macLeft = 2 * _left`, `macTop = 2 * _top`, `charset.cpp:1877`) → then splits
three ways:

| condition | destination |
|---|---|
| `vs->number == kTextVirtScreen && GID_INDY3` (`charset.cpp:1917`) | `MacIndy3Gui::printCharToTextArea` (`macgui_indy3.cpp:1077`) — a private 448x47 `_textArea` (`macgui_indy3.cpp:943`) |
| Loom note names, `chr` 16..23 (`charset.cpp:1938`) | `printCharInternal(note, **-1**, ...)` — stencil-only redraw |
| everything else | `printCharInternal(chr, color, ...)` |

`printCharInternal` (`charset.cpp:2025`) draws every glyph **twice**, into two
different surfaces, for two different purposes:

```cpp
_font->drawChar(&_vm->_textSurface, chr, x, y, 0);            // charset.cpp:2059 — colour 0
...
if (color != -1) {
    color = getTextColor();
    ...
    _font->drawChar(_vm->_macScreen, chr, x,                  // charset.cpp:2079 — the real colour
                    y + 2 * _vm->_macScreenDrawOffset, color);
}
```

with a shadow pass above it that follows the same pattern (`charset.cpp:2041`
and `2046` for Loom, `2054`/`2055` for Indy 3), and a black-and-white branch
that stipples through `_glyphSurface` instead (`charset.cpp:2064-2077`).

`_macScreen` is a 640x400 or 640x480 CLUT8 surface
(`scumm.cpp:1335-1336`). It holds the picture the user sees, already doubled.
The glyph in it is the visible one. `_textSurface` gets the same glyph *shape*
in colour **0**, and is never displayed.

---

## 3. The difference between the colour-0 stencil and the real `_macScreen` glyph

This is the crux, and the point where the card's original premise was wrong.

### 3.1 On this path, the text plane is a stencil, and it is inverted

`ScummEngine::mac_drawStripToScreen()` (`gfx_mac.cpp:52`) is the only reader of
`_textSurface` here, and its whole decision is one comparison
(`gfx_mac.cpp:98-106`):

```cpp
if (ts[2 * w] == CHARSET_MASK_TRANSPARENCY)
    mac[2 * w] = pixels[w];
```

For each output pixel: **if the text plane says "no text here", copy the game
picture over `_macScreen`. Otherwise leave `_macScreen` alone.** It then hands
`_macScreen` to the backend (`gfx_mac.cpp:115`).

So on this path:

| value in `_textSurface` | meaning |
|---|---|
| `0` (what the renderer writes) | **occupied** — "text lives here, do not overwrite" |
| `CHARSET_MASK_TRANSPARENCY` (0xFD) | **empty** — copy the picture in |

`0` is not black, and it is not a colour at all. The engine says so itself at
`gfx_mac.cpp:138`:

> On Mac the text plane is a stencil rather than a glyph store: the box itself
> is already in `_macScreen`, and 0 here marks 'text lives here' so the
> compositor stops writing the picture over it.

This is the reverse of the DOS path, where the text plane holds *glyph colour
indices* and the compositor writes text **over** the background.

### 3.2 Measured: the colour write alone changes nothing

Read from source, this is an argument. It was measured, because it is the
load-bearing claim of the whole design (`B2_MAC_RENDERER.md` §"The stencil is
what survives", worktree `wt/mac-charset-probe` at `54b5b45c7a9`, target
`indy3-ega-mac`, 640x480, 1:1):

1. A probe after the first `drawChar` — 24 glyphs, two text colours:
   `ts_nonzero=0` every time, `ts_vals=[0]`, and `ts_ink` (60, 52) equals
   `mac_nonzero` (60, 52) from the colour pass. The two passes write the same
   shape, one in 0, one in the real colour.
2. The decisive experiment: in the **same binary**, gated on an ini key so the
   control is the same build and the same frame, draw 50+ duplicate glyphs
   into `_macScreen` 12px to the right, **leaving the stencil untouched**.

   ```
   band rows 395..445   ink_a=2055  ink_b=2055   band_diff_bbox=None
   ```

   Identical ink, empty diff bbox — **not one pixel changed.** The stencil
   still read 0xFD there, so the compositor wrote the picture over all of it.

**Conclusion: the stencil decides what survives; `_macScreen` alone decides
nothing.** Both writes are load-bearing.

### 3.3 So what happens if the layer is handed the stencil?

The card was opened on the premise that passing `_textSurface` to the layer
would **overwrite glyphs with colour 0** — visible damage. That is not what
happens, and the way it differs decides the design:

- `HiResText::drawChar()` writes the glyph body in `color`. On this path any
  non-0xFD value reads as merely "occupied": the index carries no colour
  meaning, so the replacement glyph's colour is **discarded**, not painted.
- It writes coverage into the parallel coverage plane — never read, because
  `gfx.cpp:757` (`if (_macScreen && _game.version <= 3) { mac_drawStripToScreen(...); return; }`)
  returns before the blending compositor.
- `_macScreen`, the surface actually displayed, still holds the **game's own**
  glyph, because nothing removed it.

Net result: the original Mac glyph, unchanged, with a differently shaped
stencil around it.

> **A hi-res hook at `_textSurface` on the Mac path would not corrupt anything.
> It would do nothing at all — visibly, silently nothing.**

That is *worse* for review than corruption: a draw counter would report
success while the screen never changed. It is the exact trap
`measuring-feature-effect.md` exists for, and §8 is the rule that follows
from it.

**Therefore the hook belongs at the renderer's glyph source. The compositor is
correct as written and needs no knowledge of replacement fonts: it keys a
stencil, and a stencil of a better-shaped glyph keys exactly as well as a
stencil of the original.**

---

## 4. What the Mac path can and cannot deliver

| want | available? | why |
|---|---|---|
| **replacement typeface** (Korean, or a better Latin face) | **yes** | `_macScreen` is CLUT8 and the glyph renderer writes palette indices into CLUT8. No format conversion. |
| **higher resolution** (a 2x cell) | **yes, already** | `_macScreen` is 640x400/480 and the renderer already works in doubled coordinates (`charset.cpp:1877`). A scale-2 font drops straight in. |
| **antialiasing** | **no** | two independent blocks, below. |

### 4a. Antialiasing has nowhere to go

**(i) There is no coverage plane on this path.** `scumm.cpp:1837` creates the
overlay with `_overlay.create(w, h, false)` — index plane only — and
`ScummHiResText::createCoverage()` (`hires_text.cpp:695`) returns early unless
`_config.alpha`. The probe observed `cov=(nil)` at the draw site. There is
physically nowhere to record partial coverage.

**(ii) Asking for alpha does not enable blending on Mac — it destroys the
screen.** Measured this session, alpha off vs alpha on, same fixture, same
timestamp (`harness/tools/b2frame.py`):

```
i3mac-s2/cap_t50.png    640x480  mean_lum= 72.190  colours=   7  peak=255
i3mac-s2a/cap_t50.png   640x480  mean_lum=  4.364  colours=  27  peak=192   <-- Mac
i3dos-s2/cap_t50.png    640x480  mean_lum= 46.717  colours= 110  peak=255
i3dos-s2a/cap_t50.png   640x480  mean_lum= 46.242  colours= 445  peak=255   <-- DOS control
```

Captures opened rather than trusted
(`captures/2026-09-08-b2glyphsrc/`):

- **DOS + alpha**: picture intact, text readable, colour count up 110 → 445 —
  blending working as intended.
- **Mac + alpha**: the Indy 3 notebook screen **repeated four times
  horizontally and rendered near-black.**

The 4x repeat names the cause. `scumm.cpp:1599` sees `wantsAlpha()` and
negotiates a 32bpp screen (log: `hi-res text blending into ABGR8888@4`), but
`mac_drawStripToScreen()` ends by handing the backend `_macScreen` **raw**
(`gfx_mac.cpp:115`), and `_macScreen` is CLUT8 — one byte per pixel into a
four-byte-per-pixel screen. Each row of indices is read as a quarter row of
ABGR, and low indices read as near-zero channels.

**This is a live defect today**, independent of replacement fonts: a user who
writes `alpha=true` in a map for a Mac game gets an unreadable screen with no
warning. The DOS control is what makes it Mac-specific rather than "blending
is broken".

### 4b. Scale 3 is silently discarded

`scumm.cpp:1474-1475` assigns the Mac multiplier **after** the hi-res block at
`scumm.cpp:1317`:

```
1317   if (_hiResText.enabled() && _game.version < 7) {
1318       if (_textSurfaceMultiplier <= 1)
1319           _textSurfaceMultiplier = _hiResText.scale();     // 3
1320       else if (...) warning("this platform already scales text by %d; ...");
...
1474   if (_game.id == GID_INDY3 || _game.id == GID_LOOM || (GID_MANIAC && _macGui))
1475       _textSurfaceMultiplier = 2;                          // overwritten, silently
```

The `i3mac-s3` run confirms the silence: the log carries
`hi-res text enabled: scale 3`, no warning, and the backend is 640x480 —
scale-2 Mac geometry. The FM-Towns case a few lines up *does* warn, only
because it runs after the platform set its multiplier and the Mac assignment
runs after the check. Every later consumer sees 2, so nothing is
misallocated — the only defect is the silence. Also a live defect today.

### 4c. The layer is loaded on Mac and never called — with a DOS control

Fixture `harness/b2fixture.py`: Mac game data symlinked beside a
`hires_text.map` with `[latin] enabled=true` (an English Mac game has no
double-byte text, so Latin routing is the only way to reach the layer).

| cell | started | layer enabled | fonts loaded | HRTEXT draws | backend |
|---|---|---|---|---|---|
| `i3mac-s2` | yes | 1 | 3 | **0** | 640x480 |
| `i3mac-s3` | yes | 1 | 3 | **0** | 640x480 |
| `loommac-s2` | yes | 1 | 3 | **0** | 640x480 |
| `i3dos-s2` | yes | 1 | 3 | **7** | 640x480 |

The last row is the control that makes the others readable: same map, same
fonts, same game, DOS renderer — and the layer draws. The census exemption for
`CharsetRendererMac` (`test/engines/scumm/hires_hook_census.h:48`) is therefore
true rather than assumed.

### 4d. Indy 3 Mac has three glyph sources, not one

1. `CharsetRendererMac::printCharInternal` — verb line and in-scene text.
2. `MacIndy3Gui::printCharToTextArea` (`macgui_indy3.cpp:1077`) — **dialogue**,
   into a private 448x47 `_textArea` (`macgui_indy3.cpp:943`) stamped wholesale
   by `mac_drawIndy3TextBox()` (`gfx_mac.cpp:118`). Routed at
   `charset.cpp:1917-1920`, so Indy 3 Mac dialogue never passes through
   `printCharInternal` at all.
3. `MacIndy3Gui::Widget::draw` — verb button labels, into `_verbGuiSurface`,
   which is `_macScreen->getSubArea(...)` (`macgui_indy3.cpp:900`), pushed
   straight through `copyRectToScreen`.

Sources 2 and 3 bypass the stencil **and** the charset renderer. A hook at
`printCharInternal` alone leaves Indy 3 Mac with three typefaces on one
screen. **Loom has neither split** — which is why the options below scope Loom
separately.

---

## 5. The recommended shape of a Mac implementation

Not a compositor change. `printCharInternal` asks `_font` — a
`Graphics::MacFONTFont` from the game's resource fork — for each glyph;
everything the hi-res layer offers is a different answer to that one question.

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

Four properties this design depends on:

- **Both calls must succeed or both must fall through.** A glyph in
  `_macScreen` but not the stencil is erased by the next background repaint
  (measured: zero pixels changed, §3.2); a glyph in the stencil but not
  `_macScreen` leaves a hole. Same paired-write hazard the overlay work already
  hit; same cure — one call that does both, not two callers who must remember.
- **`withCoverage=false` is required, not cosmetic.** The parameter already
  exists on `drawChar` (`hires_text.h:318-321`) for the v7 path: a caller whose
  surface is not composited through the coverage plane must not record
  coverage, or it is never cleared and goes on suppressing later strokes.
- **`color == -1` must stay stencil-only.** `charset.cpp:1938` redraws Loom's
  note glyphs through this same function precisely to touch the stencil alone.
  A layer call that ignores it draws notes onto the picture the original only
  re-stencilled.
- **The cell is knowable.** `getFontHeight()` returns
  `_font->getFontHeight() / 2`; the Loom draft capture measured 21 covered
  rows on the doubled cell. `CharsetRendererMac::setCurID` (`charset.cpp:1804`)
  is the natural place to report it, as `CharsetRendererV3::setCurID` already
  does (`charset.cpp:468`).

Harder than it looks in exactly four places: antialiasing is unavailable
(§4a); the `color == -1` path (above); Indy 3's two extra sources (§4d); and
black-and-white mode, where `_renderMode == kRenderMacintoshBW` stipples
through `_glyphSurface` (`charset.cpp:2064-2077`), which is allocated at
`font->getMaxCharWidth() x getFontHeight()` (`charset.cpp:1794`) — a larger
replacement glyph would clip there, and the layer would have to hand back a
bitmap rather than draw. Unverified: the detected target is `indy3-ega-mac`,
so only the colour branch has ever run.

---

## 6. Options, risks, verification

### A. Leave the renderer exempt; make the exemption honest and fix the two live defects

Replace the census reason with the measured mechanism; add the missing scale-3
warning at `scumm.cpp:1475`; make `alpha=true` on the Mac path **warn and
refuse** rather than negotiate a 32bpp screen `mac_drawStripToScreen` cannot
feed. Roughly a comment plus ten lines.

*Risk*: low — no new rendering path, and both changes are refusals.
*Verification*: rerun the §4c table with the DOS row as control; `i3mac-s3`
must now warn; `i3mac-s2a` must match the alpha-off capture rather than going
black — **checked by opening both captures**, not by mean luminance, which is
what made the defect look like success in the first place.

### B. Loom Mac only, aliased, scale 2

Loom has no text-box split and no verb GUI widgets, so `printCharInternal` is
the single point of entry and the paired write is containable. Skips B/W
(warn and fall through) and refuses alpha.

*Risk*: medium — the paired write is the failure mode, and it fails **silently**
(§3.3).
*Verification*: A/B the Loom draft screen (`harness/b2loomdistaff.sh`, capture
`captures/2026-09-08-b2glyphsrc/loommac-draft_t120.png`: "Throw" over the
twelve note boxes) against the same frame on a control build. The **"Throw"
label must change shape while the note glyphs stay identical** — one capture
that tests the hook and the `color == -1` path at once. Whole-frame diffs are
useless here (background animation dominates); compare the band, as
`harness/tools/b2band.py` does.

### C. Indy 3 Mac as well

Needs hooks in `printCharToTextArea` *and* the verb widget draw, each with its
own surface and coordinates.

*Risk*: high, and **partial completion looks worse than not starting**: one or
two of three sources replaced means two or three typefaces on one screen.
*Verification*: all three sources in one frame — verb line, dialogue box, verb
buttons — plus the §4c enablement table.

**Recommendation: A now; B as a separate card if Mac targets matter to the
upstream submission.** Not on effort: the Korean fan translations this work
exists for are all DOS, so B has no user today, and upstream review is easier
to win with an accurate exemption plus two real bug fixes than with an
unexercised second rendering path.

Note that A is not merely documentation — §4a and §4b are two user-visible
defects in the current hi-res work that stand whether or not B is ever built.

---

## 7. Decisions needed from you

1. **Is Mac in scope for the upstream submission at all?** If the answer is
   "DOS only", option A closes this line permanently and B/C are never opened.
   Everything else below only matters if Mac is in scope.
2. **A, B, or C?** (Recommendation: A now, B later if Mac matters.)
3. **Should the two defects in §4a/§4b be split into their own card?** They are
   independent of the replacement-font question and upstreamable on their own
   merits — a silent scale downgrade and a corrupted screen are bugs today.
4. **If B: is aliased Mac text acceptable?** Antialiasing needs a rework of the
   Mac compositor, a much larger change than B itself. B delivers a
   replacement typeface at 2x with hard edges.
5. **If C: is partial Indy 3 coverage acceptable as an intermediate state?**
   Hooking `printCharInternal` alone leaves the dialogue box and verb buttons
   in the original face.

---

## 8. The measurement rule this line of work follows

**A counter improving is not evidence. Open the capture.**

Three concrete reasons this is written as a rule rather than advice, all of
them from this Mac work:

- 50+ duplicate glyphs were provably written into the surface that is copied to
  the backend, and **the screen did not change by one pixel** (§3.2). Probing
  `_macScreen` writes alone would have read as success.
- Under `alpha=true` on Mac, `ALIVE=yes`, `assert/core=0`, a *higher* colour
  count (7 → 27) and a successfully negotiated 32bpp screen **all read as
  success**. The screen was four black copies of the picture (§4a).
- The first whole-frame A/B returned a diff bbox of 1988 pixels that was
  entirely background animation while the text band was byte-identical.
  Compare the band that holds the text, not the frame.

Two corollaries the harness enforces: every Mac cell has a DOS cell beside it
with the same map, fonts and game (without `i3dos-s2a` intact, "Mac goes black
under alpha" could equally have meant "blending is broken"); and byte-identical
captures are checked for, because the first Loom attempt produced five frames
with one md5 between them — the click never landed, and a timestamp is not
evidence that anything advanced.

---

## 9. Provenance and what this document did not do

- **No engine code was changed for this document.** The probes quoted in §3.2
  and §4c were added, measured and removed in earlier sessions
  (`grep -c 'B2PROBE\|B2MACDRAW\|KPROBE' engines/scumm/*.cpp` = 0, tree clean).
- Build check for this document: a throwaway worktree of `hires-text` at
  `7b0a8c9899f`, configured with `--disable-all-engines
  --enable-engine=scumm,scumm_7_8 --enable-release`, `ERRORS=0`,
  **`make test`: 531 tests OK**; the worktree was removed afterwards, so
  repeat it with `harness/b2docbuild.sh` on a fresh one rather than looking
  for that path.
- Unmeasured and named as such: black-and-white Mac mode has never been
  entered (`_glyphSurface` clipping unverified); v4+ Mac games (MI1, MI2,
  Indy 4, DOTT, Sam & Max) use `_macScreen` but **not** `CharsetRendererMac`
  and composite through `mac_drawBufferToScreen()` — nothing here transfers to
  them without re-measuring.

### Reproducing

```bash
cd ~/work/scummvm

# build + test any worktree with the sysroot toolchain
bash harness/b2docbuild.sh repo/scummvm/.worktrees/<name> /tmp/<logdir>

# the enablement table of §4c (the DOS row is the control)
python3 harness/b2fixture.py i3mac-s2 i3mac-s2a i3mac-s3 loommac-s2 \
                             i3dos-s2 i3dos-s2a
bash harness/b2cap.sh i3dos-s2 640 480 30 50
bash harness/b2cap.sh i3mac-s2a 640 480 30 50
python3 harness/tools/b2frame.py /tmp/b2fix/i3mac-s2/cap_t50.png \
                                 /tmp/b2fix/i3mac-s2a/cap_t50.png

# the stencil experiment of §3.2 (same binary, gated on an ini key)
SENDESC=0 bash harness/b2macprobe.sh gamedata/indy3macx ctl :587 /tmp/A 24
SENDESC=0 EXTRA_INI="kprobe3=true" \
  bash harness/b2macprobe.sh gamedata/indy3macx p :588 /tmp/B 24
python3 harness/tools/b2band.py /tmp/A_t24.png /tmp/B_t24.png 395 445

# Loom Mac past its difficulty menu, to the draft screen (the §6B fixture)
bash harness/b2loomdistaff.sh :593 /tmp/B2LD 25 45 70 95 120
python3 harness/tools/b2cell.py /tmp/B2LD_t120.png 296 366 200 232
```

Captures referenced above are committed under
`captures/2026-09-08-b2glyphsrc/` in the harness repo.
