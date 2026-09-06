# Palette cases that alpha blending must survive

Alpha blending changes what the screen *is*. In the normal path the engine
hands the backend palette indices and a palette; the backend does the lookup,
and changing the palette re-colours a frame that was already copied. In alpha
mode the composite buffer holds **true colour**, so the lookup happens in our
code, once, when the pixel is written. Anything that used to work by changing
the palette afterwards silently stops working.

This is not theory. The original implementation carries a comment about
exactly this, and names the scene that exposed it:

> A paletted backend can brighten an already copied frame by changing its
> palette. Korean alpha-text mode outputs true-color pixels, so a palette fade
> only changes our lookup table; every affected pixel has to be recomposited.
> Otherwise only later dirty rectangles (typically a subtitle line) appear in
> the new colours while the rest of the screen stays black. **MI2's intro
> island after the LucasFilm logo hits exactly that path.**

The failure mode is nasty: text looks right, so the bug reads as "the
background is black" rather than "the text layer broke".

## Implementation status (S5)

Done:

- **32bpp negotiation** — asks `getSupportedFormats()` for a 4-byte format,
  keeps CLUT8 in the list as a fallback, and turns blending off with a warning
  when the display cannot supply one. No backend name appears in the test.
  Measured: `opengl` -> `ABGR8888@4`, `surface` -> `CLUT8` + warning, both
  keep running.
- **Palette cache** (`updatePaletteCache`) — case 1. `setPalette()` now feeds
  our own `uint32[256]` instead of the backend, marks all three virtual
  screens dirty, and refreshes the cursor palette.
- **The blend itself** — a separate path in `drawStripToScreen()`, so the
  existing keying paths are untouched.

Verified since:

- **Case 3 (colour cycling) and case 1 (fades)** — `~/games/palverify.sh`
  captures across a room change and reports how much the screen changes each
  second. Measured: 881, 1182, 239, 841, 220, 855, 2676 changed pixels. The
  screen moves when the palette does, which is what recompositing looks like;
  a broken build would show a static picture.
- **Case 7 (GUI return)** — `~/games/guiverify.sh`. Screen after closing the
  menu differs from before by **0.2%**, against 16.9% while it was open.
- **Case 8 (kept region)** — handled by `clearTextSurface()`, which S3 already
  extended to wipe the coverage surface; `restoreCharsetBg()` calls it.

Still unverified: cases 2, 4, 5 (transition effects, palManipulate, shadow
palettes).

### Two different menus, and why that cost an hour

`guiverify.sh` reported "the screen did not restore" four runs in a row, with
byte-identical captures. The palette code was fine. SCUMM defaults to the
**game's own menu** (`isUsingOriginalGUI()`), drawn by game script - F5 opens
it but only its own "Play" button closes it, and synthetic keypresses do not
reach it under a bare Xvfb. The test was measuring a menu that never closed.

The two paths are genuinely different:

| menu | how it changes colours | where it is handled |
|---|---|---|
| game's own (default) | `setPalColor()` + `updatePalette()` | already goes through the blended `setPalette()` |
| ScummVM GUI (`original_gui=false`) | GUI owns the palette and cursor | `pauseEngineIntern()` |

So the game menu needed no work at all, and the fix belongs only on the
ScummVM GUI path. Set `original_gui=false` to test that one.

### The stride bug this cost

The first blended frame came out tiled three times across and sheared. It read
like a blending failure; it was not. `copyRectToScreen()` was handed
`width * bytesPerPixel` when the composite buffer actually holds `width * m`
pixels per row, so the backend read each row a third of the way into the next.

Worth remembering as a shape: **geometry wrong = stride; colour wrong =
palette.** The two failures look alike on a first glance at a screenshot and
have nothing to do with each other.

## The cases

### 1. Fades in and out — `fadeIn()` / `fadeOut()`, `palette.cpp`

The engine fades by rewriting the palette, not by touching pixels. In alpha
mode every affected pixel must be recomposited, so `setPalette()` has to mark
all three virtual screens dirty and return early instead of calling the
backend's palette manager.

**Check:** any room change. The screen should fade, not jump from black to lit
with only the subtitle line correct.

### 2. Transition effects — `transitionEffect()`, `dissolveEffect()`, `scrollEffect()`

`gfx.cpp:4387` onwards. Six transition effects plus dissolve and scroll. These
move or reveal blocks of the screen; with a text overlay in play, the overlay
must move with them or stay put, consistently.

**Check:** `fadeIn(effect)` with each of the six effects; MI2 uses several.

### 3. Colour cycling — `cyclePalette()`, `palette.cpp:736`

Runs continuously in rooms with animated colour (water, torches). It rewrites
palette entries every frame. In alpha mode that means recompositing every
frame, which is also the performance question: cycling plus a full-screen
recomposite is the worst case.

**Check:** a room with cycling; watch for both wrong colour and frame rate.

### 4. `palManipulate()` — `palette.cpp:822`/`875`/`911`

Gradual palette interpolation over N frames, used for lighting changes. Same
issue as cycling but time-limited.

### 5. Shadow and darkened palettes — `setShadowPalette()`, `darkenPalette()`

`palette.cpp:935`/`965`/`1052`. v5+ games use these for characters in shadow.
They add *derived* palette entries, so the alpha lookup table needs them too.

### 6. The mouse cursor — `cursor.cpp`

Two distinct problems, both fixed in the original:

- Cursor data stays palette indices even when the screen is 32bpp. Declaring
  it in the screen format makes the backend read indices as true colour, so it
  must be declared CLUT8 and given its own palette copy via
  `CursorMan.replaceCursorPalette(_korAlphaPaletteRGB, 0, 256)`.
- The backend screen is `_textSurfaceMultiplier` times the game's, so a cursor
  handed over at native size appears a half or a third too small. It has to be
  replicated into m x m blocks.

**Check:** the cursor at scale 2 and 3, and its colour after a fade.

### 7. The GUI and the Mac GUI — `_macGui->setPaletteDirty()`

Opening the engine menu (F5) and returning has to restore both the palette and
the cursor palette. The original calls `replaceCursorPalette` again after a GUI
for this reason.

### 8. Room changes with a kept region

`gfx.cpp:1524` keeps a sub-area of the alpha surface across a room change
(`keepAlpha.copyFrom(...)`). Getting this wrong leaves glyph coverage from the
previous room blended into the new one.

## How often this actually happens (measured)

Counted in `updatePalette()` over 60 seconds of MI2 Korean, walking between
rooms and in and out of the menu (`~/games/palcases.sh`):

```
palette updates logged: 166
  full-ish (span>=200):   2
  partial  (9..199):     54
  narrow   (span<=8):   110    <- colour cycling
  rooms touched: [0, 7]
```

The shape of this matters more than the total:

- **110 of 166 are narrow** - a handful of entries, over and over. That is
  colour cycling running continuously, not a one-off event.
- Only **2** were near-full-palette, and those were the initial load and the
  room change.

The original implementation marks **all three virtual screens dirty on every
palette change**, regardless of span. That is correct but it turns 110 small
cycling updates into 110 full-screen recomposites in a minute. This is the
performance case to watch, and it is measurable: count recomposited pixels per
second against the same run with alpha off.

A narrower fix - recompositing only the pixels whose palette entries actually
changed - is possible because `_palDirtyMin`/`_palDirtyMax` say which entries
they were. Worth doing only if the measurement says so.

## What to measure, not eyeball

A palette bug at scale looks like "slightly wrong colour", which eyes forgive.
Compare against a control build with `rgdiff.py`, and when a difference shows
up, dump the frame and compare the actual RGB the composite produced against
the palette entry it should have used.

`_korAlphaPalette` is a `uint32[256]` cache built with
`_outputPixelFormat.RGBToColor()`. If a case is broken, that table and the
frame disagree — which is checkable, unlike an impression of the colour.
