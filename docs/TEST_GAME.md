# A fabricated game for testing

Status: **partial — detection and index parsing work, resource loading does
not.** Scripts are `~/games/mkgame.py` and `~/games/mkchar.py`.

## Why

Every check of the compositor, the overlay and the decorations this session
ran a real game under Xvfb: MI2, DOTT, Loom. That makes the checks slow
(20+ seconds each), non-deterministic — they race a wall clock and sometimes
capture two frames where five were asked for — and dependent on game data
that cannot be shipped or put in CI.

88 unit tests already exist and none of them need a game, because they cover
pure code: font parsing, glyph rendering, map parsing, the overlay, the
sinks. What they cannot reach is everything that hangs off `ScummEngine`.

## What is out of reach, and why

Every interesting function is a `ScummEngine` method:

| function | owner |
|---|---|
| `drawStripToScreen` | ScummEngine |
| `towns_drawStripToScreen` | ScummEngine |
| `mac_drawStripToScreen` | ScummEngine |
| `restoreCharsetBg` | ScummEngine |
| `clearTextSurface` | ScummEngine |
| `saveSurfacesPreGUI` | ScummEngine |

`ScummEngine` needs an `OSystem`, a `DetectorResult`, and inherits `Engine`.
It is not constructible in a cxxtest binary. So the choice is either to make
a game the engine will load, or to keep extracting free functions —
`compositeText` was extracted that way and is now testable.

## How far the fabricated game gets

Detection accepts it. The detector has a fuzzy-match branch for unknown MD5s
("PART 2" in `detection_internal.h`), so a directory only has to match a
filename pattern from `gameFilenamesTable`:

```
scumm:monkey2   Monkey Island 2: LeChuck's Revenge   /home/thkim/games/testgame
```

The index parses end to end — all eight blocks — and the engine reads back a
room name that exists only in the fabricated file:

```
Reading index block of type 'RNAM', size 19
Room 1: 'test-room'
Reading index block of type 'MAXS', size 26
...
readResTypeList(Charset): 2 entries
```

Then it aborts:

```
common/array.h:275: Assertion `idx < _size' failed
```

The resource counts declared in MAXS and the directories disagree with what
`allocateArrays` set up. That is a bug in the generator, not a wall.

## Corrections made while getting this far

Three format details were wrong on the first attempt, each found by running
the engine rather than by reading:

- **Index blocks are TAG then size**, the opposite order from data blocks
  (`resource.cpp:308`). Symptom: `Bad ID 0013`.
- **v5 MAXS has nine uint16 fields**, not fifteen
  (`ScummEngine_v5::readMAXS`, `resource.cpp:1285`). Symptom:
  `Bad ID 1000200`.
- **The filename must match `gameFilenamesTable`** — `monkey2.%03d`, not an
  arbitrary name. Symptom: not detected at all.

## What it would buy, if finished

Unit tests for the paths that currently need Xvfb:

- the room-0 overlay lifetime bug (`wipedGameBuffer`) — a scripted room
  change instead of a boot menu
- the GUI coverage round trip, against the real `saveSurfacesPreGUI` rather
  than against `HiResOverlay` directly
- FM-Towns layer compositing, by setting the platform in the detector result
- `[glyphs] keep` — a fabricated charset can carry a pictogram at a known
  code, which is far more direct than hunting for the skull in MI2

## What it would not buy

Anything about how a *real* game drives the engine: charset switching
mid-scene, the interaction with SMUSH, the verb strip. A fabricated game
tests the engine's reaction to inputs we choose, which is a smaller thing
than testing a game.

## Next step

Fix the array bounds: make the MAXS counts, the directory entry counts and
`allocateArrays` agree. Then add a script resource so the game can be told to
print a line, which is the point where hi-res text becomes testable.
