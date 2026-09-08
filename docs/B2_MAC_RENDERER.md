# B2 — The Mac renderer, and what a hi-res replacement would have to be there

Status: investigation only. No engine code changed. Everything below is
measured on this tree unless it says otherwise.

Measured at `14189a74ad4` (worktree `wt/b2-mac`), 2026-09-08.


## The question

`CharsetRendererMac` has an entry in the hi-res hook census' exemption table
(`test/engines/scumm/hires_hook_census.h`), with the reason:

> draws every glyph twice and uses `_textSurface` as a stencil; see the notes
> on the inverted Mac data flow

That is a placeholder, not a decision. This card is the decision: what the Mac
data flow actually is, what a replacement font would have to hook, and whether
it is worth doing.


## What the Mac renderer does

`CharsetRendererMac::printCharInternal()` (`engines/scumm/charset.cpp:2007`)
draws each glyph **twice**, into two different surfaces, for two different
purposes:

```cpp
_font->drawChar(&_vm->_textSurface, chr, x, y, 0);          // colour 0
...
_font->drawChar(_vm->_macScreen, chr, x, y + 2 * _vm->_macScreenDrawOffset,
                color);                                     // the real colour
```

`_macScreen` is a 640x400 (or 640x480) CLUT8 surface allocated in
`scumm.cpp:1335`. It holds the picture the user sees, already doubled.
The glyph in it is the visible one.

`_textSurface` gets the *same glyph shape* written with colour **0**. Nothing
ever displays that copy. Its only reader is the compositor.

### The compositor reads it as a stencil, inverted

`ScummEngine::mac_drawStripToScreen()` (`engines/scumm/gfx_mac.cpp:52`) is the
whole of it:

```cpp
if (ts[2 * w] == CHARSET_MASK_TRANSPARENCY)
    mac[2 * w] = pixels[w];
```

For each output pixel: **if the text plane says "no text here", copy the game
picture over it. Otherwise leave `_macScreen` alone.** The glyph is already in
`_macScreen`; the text plane exists only to stop the background erasing it.

This is the reverse of every other SCUMM path. On the DOS path
(`gfx.cpp:724` onward) the text plane holds *glyph colour indices* and the
compositor writes text **over** the background. On Mac it holds a *stencil*
and the compositor writes background **around** text drawn elsewhere.

The engine states this itself, at `gfx_mac.cpp:138`:

> On Mac the text plane is a stencil rather than a glyph store: the box itself
> is already in `_macScreen`, and 0 here marks 'text lives here' so the
> compositor stops writing the picture over it.

So `0` is not black. On this path `0` means *occupied*, and
`CHARSET_MASK_TRANSPARENCY` (0xFD) means *empty*.

### Why the hook cannot simply be added

The card's premise was that handing the stencil to the layer writes colour 0
over every glyph. The measurement is worse than that, and in a more useful
way: it is not that the layer would *damage* the stencil, it is that **drawing
into the stencil produces nothing visible at all**.

`HiResText::drawChar()` writes a glyph body in `color` and its coverage into
the parallel coverage plane. Put that in `_textSurface` on the Mac path and:

- the body colour is read by `mac_drawStripToScreen` as "not
  `CHARSET_MASK_TRANSPARENCY`", i.e. simply "occupied", and discarded — the
  index carries no colour meaning on this path;
- the coverage plane is never read, because `mac_drawStripToScreen` returns
  before the blending compositor (`gfx.cpp:756`, `if (_macScreen && version
  <= 3) { mac_drawStripToScreen(...); return; }`);
- `_macScreen`, which is the surface that is actually displayed, still holds
  the game's own glyph, because nothing removed it.

The result is the original Mac glyph, unchanged, with a slightly different
stencil shape around it. A replacement font that appears to do nothing.

**So the hook does not belong at `_textSurface` on this path. It belongs at
`_macScreen`, which means it belongs in the renderer, not the compositor.**


## The stencil is what survives — measured, not inferred

The section above was read from the compositor's source. It is now measured,
which matters because it was the one load-bearing claim in this document that
had not been. Measured at `54b5b45c7a9` in worktree `wt/mac-charset-probe`
(`.worktrees/t_14a6ae8c_svm`), ERRORS=0, `make test` 531 tests OK, probes
removed afterwards (`grep -c KPROBE engines/scumm/{charset,gfx_mac}.cpp` = 0,
tree clean).

Target `indy3-ega-mac`, auto-detected from `gamedata/indy3macx` into a private
ini; 640x480 Xvfb, 1:1 capture.

### 1. The text plane really does receive nothing but 0

A probe immediately after the first `drawChar`, counting the cell it just
wrote in both surfaces:

```
KPROBE chr=66('B') x=256 y=310 color=14 cell=9x15
       ts_ink=60 ts_nonzero=0 ts_vals=[0] mac_ink=0
       tsSurf=640x400 mult=2 macScr=640x480 off=20 cov=(nil)
KPROBE chr=65('A') ... ts_ink=52 ts_nonzero=0 ts_vals=[0] ...
```

24 glyphs across two text colours (6 and 14): `ts_nonzero` is 0 every time and
the only value ever written is 0. `cov=(nil)` is the coverage plane — never
allocated on this path, because `_overlay.create(..., withCoverage=false)`
(`scumm.cpp:1837`) and `createCoverage()` returns early unless `_config.alpha`
(`hires_text.cpp:698`). There is physically nowhere to put antialiasing, which
is the hard constraint in "Four things that are genuinely harder" #1, now
observed rather than deduced.

After the colour pass, the same cell in `_macScreen`:

```
KPROBE2 chr=66('B') color=14 cell=9x15 mac_cells=135 mac_nonzero=60 mac_vals=[0 14]
KPROBE2 chr=65('A') color=14 cell=9x15 mac_cells=135 mac_nonzero=52 mac_vals=[0 14]
```

`mac_nonzero` (60, 52) equals `ts_ink` (60, 52) exactly — the two passes write
the same glyph shape, one in 0, one in the real colour.

### 2. A colour write with no stencil behind it never reaches the screen

The decisive experiment. In the *same* binary, after the colour pass, draw the
identical glyph 12px to the right **into `_macScreen` only**, leaving the
stencil untouched; gate it on an ini key so the control is the same build and
the same frame.

```
control: KPROBE3 gate=0
probe:   KPROBE3 gate=1
         KPROBE3 dup #1  chr=84 at x=156(+12) y=350 color=6
         KPROBE3 dup #50 chr=82 at x=278(+12) y=370 color=6
```

The gate is confirmed on and at least 50 duplicate glyphs were written into
the surface that is copied to the backend. The screen, over the copyright line
that those glyphs sit on:

```
band rows 395..445  ink_a=2055 ink_b=2055  band_diff_bbox=None
```

**Identical ink, empty diff bbox — not one pixel changed.** The stencil still
read 0xFD at those positions, so the compositor wrote the picture over them
and the colour was discarded.

This is the inverse of the failure the hook would cause, and it proves the
same mechanism: on this path the stencil decides what survives, and
`_macScreen` alone decides nothing. Both writes are load-bearing, which is why
the paired-write requirement in "The shape it wants" is not a stylistic
preference.

### Two traps this measurement walked into first

- **A frame counter or an ink total would have said the opposite.** Fifty-plus
  glyphs were provably drawn into the displayed surface and the display did not
  change. Probing `_macScreen` alone would have read as success.
- **Whole-frame diffs are useless here.** The first A/B returned diff bbox
  `(10,327,616,391)`, 1988 pixels — all background animation, while the text
  band was byte-identical. Compare the band that holds the text
  (`harness/tools/b2band.py`), not the frame.
- `getenv()` cannot gate a probe: it does not reach the child process. Gate on
  an ini key through `ConfMan` **and log that the gate is on** — without
  `KPROBE3 gate=1` and `dup #50` in the log, "no difference" would have been
  worthless.


## Measurements

Build: `.worktrees/t_2dc52340`, `ERRORS=0`, `make test` below.

### The layer engages, and draws nothing

Fixture (`harness/b2fixture.py`): the Mac game data symlinked into a throwaway
directory beside a `hires_text.map` with `[latin] enabled=true` and the
`hrlat%02d.fnt` faces from `indy3kor`. An English Mac game has no double-byte
text at all, so Latin routing is the only way to reach the layer.

| cell | started | layer enabled | fonts loaded | HRTEXT draws | backend |
|---|---|---|---|---|---|
| `i3mac-off` | yes | 0 | 0 | 0 | 640x480 |
| `i3mac-s2` | yes | **1** | 3 | **0** | 640x480 |
| `i3mac-s3` | yes | **1** | 3 | **0** | 640x480 |
| `loommac-s2` | yes | **1** | 3 | **0** | 640x480 |
| `loommac-s3` | yes | **1** | 3 | **0** | 640x480 |
| `i3dos-s2` | yes | 1 | 3 | **1** | 640x480 |

The last row is the control that makes the others readable: the *same* map,
the *same* fonts, the *same* game, on the DOS renderer — and the layer draws.
On Mac it loads everything and is never called.

`HRTEXT=0` alone would be ambiguous ("maybe no text was drawn"). A probe in
`CharsetRendererMac::printCharInternal` settles it:

```
B2MACDRAW=12   HRTEXT=0
B2MACDRAW chr=83 color=9 shadow=0 x=278 y=136 curId=0 fontH=23
          tsW=640 tsH=400 mult=2 hires=1
```

Twelve real glyphs drawn — the "STANDARD / PRACTICE / EXPERT" difficulty menu,
confirmed on the capture `/tmp/b2fix/loommac-s2/cap_t50.png` — with the hi-res
layer enabled (`hires=1`) and offered none of them. This is the census
exemption being true rather than assumed.

### Scale 3 is silently discarded

The Mac branch at `scumm.cpp:1474` assigns the multiplier **after** the hi-res
block at `scumm.cpp:1317`:

```
line 1317   if (_hiResText.enabled() && _game.version < 7)
line 1319       _textSurfaceMultiplier = _hiResText.scale();     // 3
...
line 1474   if (_game.id == GID_INDY3 || _game.id == GID_LOOM || ...)
line 1475       _textSurfaceMultiplier = 2;                      // overwritten
```

Probe on that line, `hires_text_scale=3`:

```
B2PROBE mac overwrite: mult 3 -> 2 (hires scale 3 enabled 1)
```

The user's requested scale is overwritten with no warning. Contrast the
FM-Towns case a few lines up, which *does* warn
(`"this platform already scales text by %d; ignoring the hi-res scale of %d"`)
— it warns because it runs *after* the platform set its own multiplier, and
the Mac assignment runs after the check. Every later consumer
(`_overlay.create` at 1837, `_compositeBuf` at 1950) sees 2, so nothing is
misallocated; the only defect is the silence.


## What a Mac implementation would have to be

Not a compositor change. The compositor is correct and does not need to know
about replacement fonts at all — it is keying a stencil, and a stencil of a
better-shaped glyph works exactly as well as a stencil of the original.

The change is at the renderer's **glyph source**. `printCharInternal` asks
`_font` — a `Graphics::MacFONTFont` from the game's resource fork — for each
glyph. Everything the hi-res layer offers on Mac is a different answer to that
one question.

### The shape it wants

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
		                              color, shadowColor, 0))
			_font->drawChar(_vm->_macScreen, chr, x, y + ..., color);
	}
}
```

Both calls must succeed or both must fall through. A glyph that draws into
`_macScreen` but not the stencil is erased by the next background repaint; a
glyph in the stencil but not `_macScreen` leaves a hole. This is the same
paired-write hazard the overlay work already ran into, and the same cure
applies: one call that does both, not two callers who must remember.

### Four things that are already true and make this cheaper than it looks

1. **The Mac surface is already 2x.** `_macScreen` is 640x400 and the renderer
   already works in doubled coordinates (`macLeft = 2 * _left`,
   `charset.cpp:1861`). A scale-2 font drops straight in; no new scaling
   arithmetic.

2. **The engine already has the grid.** `getFontHeight()` returns
   `_font->getFontHeight() / 2` and the probe measured `fontH=23` for Loom's
   font 0, i.e. a 23px doubled cell. That is the number `noteGameCharset()`
   wants, and `CharsetRendererMac::setCurID` is the natural place to report it
   — the same place `CharsetRendererV3::setCurID` reports it today
   (`charset.cpp:464`).

3. **`_macScreen` is CLUT8.** The glyph renderer writes palette indices into
   CLUT8 surfaces; that is exactly what it is for. No format conversion.

4. **The stencil is shape-only.** It needs no colour and no coverage, so the
   second call is strictly simpler than the first — a 1-bit dilation of the
   glyph, which is what `drawStencil` above would be.

### Four things that are genuinely harder

1. **Antialiasing has nowhere to go.** `_macScreen` is paletted and the
   compositor is a binary key. A partially covered pixel can be neither
   expressed in the stencil (it is occupied or it is not) nor blended in the
   picture (the blending compositor is never reached — `gfx.cpp:756` returns
   first). So Mac gets a **replacement typeface at 2x, aliased**. That is a
   real gain — the Mac fonts are the game's own bitmaps, and a Korean or
   larger Latin face is otherwise impossible there — but `alpha=true` cannot
   be honoured and should warn rather than silently do nothing.

2. **Loom's note-name hack redraws through the same function.**
   `charset.cpp:1915` calls `printCharInternal(note, -1, ...)` with
   `color = -1` to touch *only* the stencil. Any hook has to preserve that:
   `color == -1` means stencil-only, and a layer call that ignores it would
   draw notes onto the picture that the original only re-stencilled.

3. **Indy 3's text box bypasses the renderer entirely.** When
   `vs->number == kTextVirtScreen && _game.id == GID_INDY3`, `printChar`
   routes to `_macGui->printCharToTextArea()` (`charset.cpp:1902`) — a
   different surface owned by the Mac GUI, stamped wholesale by
   `mac_drawIndy3TextBox()` (`gfx_mac.cpp:118`). Dialogue in Indy 3 Mac is
   therefore **not** reachable from `printCharInternal` at all. A complete
   Indy 3 Mac implementation needs a second hook inside the Mac GUI's text
   area, or it replaces the verb line and leaves the dialogue box alone —
   which would look worse than doing neither. Loom has no such split.

4. **B/W mode dithers per pixel.** `_renderMode == kRenderMacintoshBW` draws
   the glyph into `_glyphSurface`, then stipples it onto `_macScreen`
   (`charset.cpp:2046`). A replacement glyph would have to go through the same
   stipple, so the layer would need to hand back a bitmap rather than draw
   directly — a third code path.


## Recommendation

Three options, in the order I would rank them.

**A. Leave it exempt, but make the exemption honest.** Replace the census
reason with what was measured: the visible glyph goes to `_macScreen`, the
text plane is an inverted stencil, and a hook belongs at the renderer's glyph
source. Add the missing scale-3 warning so a user asking for 3 is told they
got 2. Cost: a comment and roughly five lines. This is the whole of the card's
stated close condition.

**B. Loom Mac only, aliased, scale 2.** Loom has no text-box split, so
`printCharInternal` is the single point of entry, and the paired write is
containable. Skips B/W mode (warn and fall through) and refuses `alpha=true`.
This is the smallest change that actually puts a replacement font on a Mac
screen.

**C. Indy 3 Mac as well.** Needs the second hook inside
`MacGuiImpl::printCharToTextArea` and its own coordinate handling. I would not
start this until B is on a real screen and judged.

I recommend **A now**, and B as a separate card if the Mac targets matter to
the upstream submission. The reason to prefer A is not effort: it is that the
Korean fan translations this work exists for are all DOS, so B has no user
today, and upstream review is easier to win with an accurate exemption than
with an unexercised second rendering path.

An honest note on scope: I did not verify B by building it. The claims above
about *what would happen* if the layer were hooked into `_textSurface` are
read from the compositor's source — but the mechanism they rest on **is** now
measured: see "The stencil is what survives". A colour write into `_macScreen`
with no matching stencil was confirmed to reach the screen not at all. What
remains unbuilt is the replacement-font hook itself, not the reasoning about
why it must be paired.

Still unmeasured, and worth naming:

- **Loom was not captured.** `gamedata/loommacx` exists; only Indy 3 was run in
  the stencil measurement. Loom's `color == -1` note-name path
  (`charset.cpp:1915`) updates the stencil *only*, and that asymmetry under a
  hook is untested.
- **B/W mode was never entered.** The detected target is `indy3-ega-mac`, so
  only the colour branch of `mac_drawStripToScreen` ran. `_glyphSurface` is
  allocated at `font->getMaxCharWidth() x getFontHeight()`, so a larger
  replacement glyph may clip there — unverified.
- **v4+ Mac games are a different path.** MI1/MI2/Indy4/DOTT/Sam & Max Mac use
  `_macScreen` but not `CharsetRendererMac`, and composite through
  `mac_drawBufferToScreen()` (`gfx.cpp:1009`). None of this document transfers
  to them without re-measuring.


## Reproducing

```bash
# fixture + the enablement table
python3 ~/work/scummvm/harness/b2fixture.py

# drive one cell under Xvfb and capture 1:1
bash ~/work/scummvm/harness/b2cap.sh loommac-s2 640 480 30 50 65
```

For the stencil measurement specifically (no fixture needed — it uses the
game's own Mac fonts and a private ini, so it cannot disturb the shared one):

```bash
cd ~/work/scummvm
# control and probe, same binary, gated on an ini key
SENDESC=0 bash harness/b2macprobe.sh gamedata/indy3macx ctl :587 /tmp/A 24
SENDESC=0 EXTRA_INI="kprobe3=true" \
  bash harness/b2macprobe.sh gamedata/indy3macx p :588 /tmp/B 24

# compare the band that holds the text, not the whole frame
python3 harness/tools/b2band.py /tmp/A_t24.png /tmp/B_t24.png 395 445
```

`b2macprobe.sh` adds the game to a throwaway ini itself and prints the target
it detected, so a run that measured a different target cannot pass unnoticed.
`SENDESC=0` suppresses the Escape keystrokes; with them the Indy 3 intro skips
past the copyright line before t=24.

`b2cap.sh` prints `ALIVE=`, `B2MACDRAW=`, `HRTEXT=` and
`hi-res font=` separately, so a run that died, a run that drew no text and a
run whose layer was never loaded cannot be confused with one another.

The `B2MACDRAW` / `B2PROBE` probes quoted above are not in the tree — they were
added, measured, and removed by restoring pre-probe copies
(`grep -c 'B2PROBE\|B2MACDRAW' engines/scumm/*.cpp` = 0). To repeat the glyph
count, reinstate a `debug(1, ...)` at the top of
`CharsetRendererMac::printCharInternal` and run with `-d1`.
