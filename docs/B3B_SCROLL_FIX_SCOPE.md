# B3b — scrollEffect() hi-res fix: exact scope

Card `t_7273a0b0` (scope memo for `t_eb0aa253`, the implementation card).
Investigation and measurements are in `B3_SCROLL_EFFECT.md` (b1abd59); nothing
here is re-measured. Line numbers refer to `hires-text` at 57f93a86657.

## 1. What to change — the four blits, nothing else in the function

`engines/scumm/gfx.cpp`, `ScummEngine::scrollEffect(int dir)` (5069..5250).
Each case has the same shape:

```
moveScreen(...)                       // leave alone (already * m)
if (_townsScreen) { towns_... }       // leave alone
else {
    src = vs->getPixels(...);         // 320-wide CLUT8, real stride vs->pitch
    int vsPitch = vs->pitch;
    if (_macScreen) { mac_drawBufferToScreen(...) }   // leave alone
    else {
        int wd, ht, tx, ty = ...;     // game-pixel rectangle: correct as is
        if (_enableEGADithering) { memcpy -> _compositeBuf; src = ditherVGAtoEGA(...) }
        _system->copyRectToScreen(src, vsPitch * m, <dest>, <size>);   // <-- ONLY THIS LINE
    }
}
```

Lines to replace (one per direction):

| dir | line | current call | what is wrong |
|---|---|---|---|
| 0 up    | 5132 | `copyRectToScreen(src, vsPitch*m, tx,   ty*m, wd,   ht*m)` | pitch lies; width unscaled |
| 1 down  | 5166 | `copyRectToScreen(src, vsPitch*m, 0,    0,    wd*m, ht*m)` | pitch lies; no source magnification |
| 2 left  | 5203 | `copyRectToScreen(src, vsPitch*m, tx*m, 0,    wd*m, ht*m)` | same |
| 3 right | 5239 | `copyRectToScreen(src, vsPitch*m, 0,    0,    wd*m, ht*m)` | same |

Note dir 1 and dir 3 pass literal `0, 0` where `tx, ty` are also 0 — use
`tx, ty` in the replacement so all four read identically.

Everything else in the four cases — `wd/ht/tx/ty`, the loop bounds, the
`waitForTimer(delay, true)` — is in game pixels and correct. The only defect is
that the last line hands a 320-wide CLUT8 pointer to a backend that is
`m` times larger and, under alpha, a different pixel format.

## 2. Implementation direction

Replace each blit line with:

```
if (!hiResBlitStrip(src, vsPitch, tx, ty, wd, ht))
    _system->copyRectToScreen(src, vsPitch * m, <unchanged original args>);
```

The fallback keeps the upstream line byte-for-byte so `m == 1`, Mac-without-
hires (`m` forced to 2 at 5102), EGA dithering, and 16-bit game buffers are
untouched. `hiResBlitStrip` returns `false` for all of those.

`bool ScummEngine::hiResBlitStrip(const byte *src, int srcPitch, int tx, int ty, int wd, int ht)`
(new, gfx.cpp next to scrollEffect; declaration in scumm.h next to
`void scrollEffect(int dir);` at ~1562):

1. Guards, in this order, each returning `false`:
   - `!_hiResText.enabled() || _textSurfaceMultiplier <= 1` — at m == 1 the
     game buffer already is the screen; do not add a second path there.
     Use `_textSurfaceMultiplier`, not scrollEffect's local `m` (that local
     is forced to 2 for Mac and we are not touching Mac).
   - `_virtscr[kMainVirtScreen].format.bytesPerPixel != 1` — 16-bit game
     buffers (PC-Engine, Towns v3) are not palette indices.
   - `_enableEGADithering || _hercCGAScaleBuf` — see §4.
   - `outBpp = _outputPixelFormat.bytesPerPixel`; if `outBpp != 1` require
     `_hiResText.alphaActive()` (the palette cache is only maintained while
     blending is active — palette.cpp:1784) and `outBpp` in {2, 4}.
   - Destination rect `tx*m, ty*m, wd*m, ht*m` must lie inside
     `_system->getWidth() x _system->getHeight()`; otherwise `false`. Do not
     clip: a rect that does not fit means the scale assumption is wrong.
2. Allocate a private scratch `Common::Array<byte> buf(wd*m * ht*m * outBpp)`
   (see §3 for why not `_compositeBuf`).
3. Expand `wd x ht` source pixels at stride `srcPitch` (= `vs->pitch`, the
   real one, never `* m`) into `buf` at `m x m` per pixel, resolving indices
   through the existing sinks in `engines/scumm/hires_sinks.h`:
   - `outBpp == 1` → `HiResIndexSink(buf.begin())`
   - `outBpp == 2` → `HiResPalette16Sink(buf.begin(), _hiResText.paletteCache(), _outputPixelFormat)`
   - `outBpp == 4` → `HiResTrueColorSink((uint32*)buf.begin(), _hiResText.paletteCache(), _outputPixelFormat)`
   Feed the sink whole rows via `writeBackground(row, wd*m)`; each source row
   is expanded once and written `m` times. This is the picture-only half of
   `compositeText()`; put it in a header template (`engines/scumm/hires_scale.h`,
   `expandStrip<Sink>(sink, src, srcPitch, width, height, m)`) so a cxxtest can
   drive it with a capture sink without an engine.
4. `_system->copyRectToScreen(buf.begin(), wd*m*outBpp, tx*m, ty*m, wd*m, ht*m); return true;`

The row pitch passed to the backend is `wd * m * outBpp` — derived from the
strip we composed, never from `vs->pitch` and never from the screen width.
That is the same discipline as drawStripToScreen's alpha path at 848..850.

Text overlay: not composited here on purpose. The transition moves the picture;
the text surface is re-composited by the next `drawStripToScreen()` pass, same
as on the 1x path where `copyRectToScreen(src=vs->getPixels…)` also carries no
text.

## 3. `_compositeBuf`: do not reuse it

- It is sized `_screenWidth*m * _screenHeight*m * _outputPixelFormat.bytesPerPixel`
  (scumm.cpp:1950), so a full-screen strip would fit — but
- the EGA-dithering branch inside scrollEffect already writes the raw strip
  into `_compositeBuf` (5128, 5162, 5197, 5233) *before* the blit line, and
  `ditherVGAtoEGA()` reads it back into `_hercCGAScaleBuf`. Composing into the
  same buffer would clobber the dithered source if the guards were ever
  loosened; and
- `waitForTimer()` inside the loop runs `parseEvents()` + `updateScreen()`;
  an auxiliary redraw (`drawStripToScreen`) between steps would find the buffer
  holding a strip mid-write.

A per-call `Common::Array<byte>` of `wd*m*ht*m*outBpp` bytes is small: at 3x
32bpp a dir 2/3 strip is 24x600x4 = 57 KB, a dir 0/1 strip 960x24x4 = 92 KB.
The strip is never the full screen. Cheap for a transition of ~25–40 steps. If the implementer
prefers no per-step allocation, hoist one array to function scope in
scrollEffect and pass it in — still not `_compositeBuf`.

## 4. EGA dithering: how the conflict is avoided

`_enableEGADithering` (MI2/Loom-CD/Indy4 DOS with render mode EGA,
palette.cpp:246) rewrites the strip as 2x2 dither into `_hercCGAScaleBuf` and
doubles `pitch/x/y/wd/ht` in place via reference params. After that call the
`src` pointer is no longer `vs->getPixels` and `vsPitch` is already doubled.
`hiResBlitStrip` must therefore be gated off when `_enableEGADithering` is set
(guard in §2.1) so the existing `copyRectToScreen(src, vsPitch * m, ...)` runs
as before. Whether EGA-dither + hi-res m>1 is itself correct is unmeasured and
out of scope; the guard leaves it exactly as it is today.

`_hercCGAScaleBuf` non-null also covers `kRenderCGA_BW`/Hercules — same
treatment, same reason.

## 5. Do-not-touch list

| path | why |
|---|---|
| `moveScreen(0, ±step*m, vs->h*m)` / `moveScreen(±step*m, 0, vs->h*m)` (5110, 5144, 5178, 5214) | already scaled; also handles `_enableEGADithering` doubling and `_macScreen` offset internally (2010..) |
| `_townsScreen` branches (5112, 5146, 5180, 5216) and the `_enableSmoothScrolling` early return (5072) | separate renderer, no measurement |
| `_macScreen` branches → `mac_drawBufferToScreen` (5120, 5154, 5188, 5224) and the `m = 2` force at 5102 | separate renderer, no measurement; B2 card owns Mac |
| `_enableEGADithering` memcpy + `ditherVGAtoEGA` blocks | see §4; guard around them, don't edit them |
| `drawStripToScreen()` (724..1017) | source/dest coords differ in scrollEffect; not a substitute. Do not "fix" scrollEffect by calling it. |
| `wd/ht/tx/ty`, loop bounds, `step`, `delay`, `waitForTimer` | game-pixel arithmetic, correct |
| `dissolveEffect`, `transitionEffect` | not part of B3; leave for a separate card if they show the same defect |
| `_compositeBuf` allocation (scumm.cpp:452, 1950) | unchanged; we don't use it |
| `hires_sinks.h` sink classes | reuse as-is; do not add a variant |

## 6. Prior WIP on `wt/b3b-scrollfix` (d809073283d)

The preserved WIP already contains essentially this design:
`hiResBlitStrip()` + `hires_scale.h::expandStrip` + a cxxtest
(`test/engines/scumm/hires_scale.h`, 7 cases). Reuse it rather than
re-deriving. Before it can land it needs:

- **Probe removal** — all `// ---- B3 PROBE ----` blocks: `b3DumpFrameBuffer()`
  and its four call sites in gfx.cpp, the `B3SCROLL`/`B3BLIT` `debug()` lines,
  the `_b3Force*` members in scumm.h, and the `b3_force_scroll` block in
  scumm.cpp's main loop. `grep -n B3 engines/scumm/{gfx,scumm}.cpp scumm.h`
  must return 0 lines.
- One deviation to fix: the WIP reads `_system->getScreenFormat()` for
  `outFmt`; use `_outputPixelFormat` instead — it is the engine's own copy of
  the same value (scumm.cpp:1653) and is what `_compositeBuf` and the
  drawStripToScreen alpha path are sized against.
- dir 1 / dir 3 call sites: the WIP passes `tx, ty` to `hiResBlitStrip` — good
  — while the fallback keeps the literal `0, 0`. Fine; both are 0.
- Review that `hires_scale.h` is listed nowhere in `module.mk` (header-only,
  nothing to add) and that `test/module.mk:45` already globs
  `test/engines/scumm/*.h`, so the new test is picked up without a build
  change.
- `make test` baseline is 514 (B3 card) / 520 after T3 merged on `hires-text`.
  The WIP's 7 new cases should take the count to 527 if branched after T3,
  521 if the worktree is still on 14189a74ad4 (it is — rebase onto
  `hires-text` first, the branch point predates B5/T3).

## 7. Acceptance for the implementation card

- The four blit lines are the only lines changed inside the `switch`.
- `git diff` shows no change to any `moveScreen`, `_townsScreen`,
  `_macScreen`, or `ditherVGAtoEGA` line.
- `grep -c B3 engines/scumm/gfx.cpp engines/scumm/scumm.cpp engines/scumm/scumm.h` → 0.
- `make test` green with the expandStrip cases included.
- Visual close-out (captures, `b3force.sh` 2x/3x + control, `b3sheet.py`) is
  owned by the parent card `t_7ef8247f`, not by the implementation card.
