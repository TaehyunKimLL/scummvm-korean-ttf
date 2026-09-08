# B3 — `scrollEffect()` at hi-res: measured, and the "0 hits" verdict is wrong

Card `t_09e04465`. The earlier judgement was that `scrollEffect()` is upstream
code the hi-res layer never reaches (measured 0 hits across three v5 games), so
its unscaled `copyRectToScreen` calls were deliberately left alone.

**That verdict does not hold.** The function is reached by Indy 4's own scripts
and all four directions render corrupt at scale 3.

## What the earlier measurement missed

The hit count was taken from ordinary play. Reaching `scrollEffect()` needs a
room transition whose `SO_ROOM_FADE` operand is 130..133, and those are a small
minority: in `indy4kor` 51 of 172 fades, in `mi2kor` 5 of 63. Nothing in the
scenes captured earlier used one.

`harness/tools/scrollrooms.py` decodes the operand and resolves the *room
number* through the LECF's `LOFF` directory, so the answer is a debugger
command rather than a file offset:

```
$ scrollrooms.py gamedata/indy4kor
effect 130 (dir3 right): 14 sites, rooms 20 32 40 46 55 82 86 88 95
effect 131 (dir2 left):  15 sites, rooms 20 39 46 55 67 82 85 87 95
effect 132 (dir1 down):  12 sites, rooms 14 20 40 52 56 87 88 95
effect 133 (dir0 up):    10 sites, rooms 20 21 30 41 61 85 86 95

$ scrollrooms.py gamedata/mi2kor
effect 132 (dir1 down):  2 sites, rooms 58
effect 133 (dir0 up):    3 sites, rooms 58 63
```

Confirmed at runtime — `room 30` then `room 22` in Indy 4 fires it every time:

```
B3ROOMFADE room=30 word=0x0085 effect=133 effect2=0
B3FADEIN   effect=133 -> scrollEffect(0) room=22
B3SCROLL   dir=0 m=3 vs=320x200 pitch=320 vsBpp=1 outBpp=4 hires=1 alpha=1
```

Directions 2 and 3 are reachable per the table but sit behind script conditions
that no short run satisfied, so they were fired with a temporary hook
(`b3_force_scroll`) present in the **same binary** as the control, per the
skill's rule about scripting a rare stimulus.

## The defect

Each direction ends in a blit whose scaling is only half applied. The probe
prints the declared pitch next to the source's real one:

| dir | call | declared srcPitch | real src stride | dest rect |
|---|---|---|---|---|
| 0 up | `copyRectToScreen(src, vsPitch*m, tx, ty*m, wd, ht*m)` | 960 | 320 | 320x24 |
| 1 down | `(src, vsPitch*m, 0, 0, wd*m, ht*m)` | 960 | 320 | 960x24 |
| 2 left | `(src, vsPitch*m, tx*m, 0, wd*m, ht*m)` | 960 | 320 | 24x600 |
| 3 right | `(src, vsPitch*m, 0, 0, wd*m, ht*m)` | 960 | 320 | 24x600 |

`src` is `vs->getPixels(...)` — the game's own 320-wide CLUT8 buffer. Two
independent faults follow, and they differ per direction:

- **The stride lies.** Telling the backend the source rows are `vsPitch * m`
  bytes apart when they are `vsPitch` makes it sample every m-th row of the
  game buffer, and read past the end once the strip is tall.
- **The rectangle is inconsistently scaled.** dir 0 scales the height but not
  the width, so the strip covers only the leftmost third of a 960-wide
  backend; dirs 1/2/3 scale both, so a 320-wide source is stretched to a
  960-wide destination with no magnification, tiling or reading garbage.

Neither the source magnification nor the CLUT8 -> 32bpp conversion happens at
all, which is the same class of defect as the legacy scroll path recorded in
`references/scroll-palette-regression.md`: **the scale has to be present on
both the source and the destination**, and `copyRectToScreen` supplies neither.

## Evidence

Frames are the backend framebuffer dumped inside the effect (`lockScreen` ->
PPM), not screenshots, so nothing depends on capture timing.

Contact sheet, control left / hi-res right, one row per direction:
`/tmp/b3_sheet.png` (regenerate with `harness/tools/b3sheet.py`).

| dir | control (m=1, hi-res inputs denied, `grep -c 'hi-res font'` = **0**) | hi-res 3x |
|---|---|---|
| 0 up | one coherent scene sliding | new strip in the bottom-left third only, sheared and tiled |
| 1 down | coherent | incoming top strip tiled ~12x horizontally |
| 2 left | coherent | right half is RGB noise |
| 3 right | coherent | left half is RGB noise |

Column measurement of the incoming strip (`harness/tools/b3strip.py`), dir 0:

```
hi-res 3x   bottom 24 rows changed cols 0..319   (320 of 960 = 33%)
control     bottom  8 rows changed cols 0..319   (320 of 320 = 100%)
```

33% is exactly the unscaled `wd` on a 3x backend — the arithmetic and the
picture agree.

The control is a real control: `harness/tools/b3ctrl2.py` symlinks the game
data **without** `hires_text.map` and the `hr*.fnt` faces and writes a private
ini, because `hires_text_scale=1` would still find the map in the game folder.

## Status

Not fixed here — this card is investigation only, and the fix is the same shape
as the legacy scroll repair: precompose an incoming surface in the output
format, then move the backend rows using their own pitch. Source and
destination coordinates differ, so `drawStripToScreen()` is not a substitute.

## Tools added

| path | what |
|---|---|
| `harness/tools/scrollrooms.py` | which ROOM sets which scroll effect (via `LOFF`) |
| `harness/b3run.sh` | drive a target through the debugger, private ini + savepath, console-open gate |
| `harness/b3runini.sh` | same with an explicit ini/target (the control) |
| `harness/b3force.sh` | fire one direction deterministically at a chosen frame |
| `harness/tools/b3ctrl2.py` | build a true control: hi-res inputs denied |
| `harness/tools/b3frames.py`, `b3strip.py`, `b3ascii.py`, `b3sheet.py` | read the dumps |
| `harness/tools/b3console.py` | gate: was the debugger console actually open |
| `harness/b3build.sh`, `b3test.sh` | build / build+test in this worktree |

## Two harness traps this run hit

- **The first two runs typed into a console that never opened** and reported
  `B3SCROLL=0`, which reads identically to "the effect never fires" — the
  question being asked. `b3console.py` now tests the capture for the console's
  pale band and retries, and the count is printed as `CONSOLE_OPENED=n/N`.
- **The runs wrote their autosave onto the shared fixture** (`State saved as
  'i4-multi.s00'`), which would eventually have moved the scene the next run
  starts from. Every harness here now uses a private `savepath`.
