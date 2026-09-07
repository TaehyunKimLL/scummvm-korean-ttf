# Making the compiler enforce the two-plane invariant

Status: **proposed.** Motivated by having missed the same class of bug twice
in one session, both times after an audit that reported the sites were clean.

## The problem

The overlay owns two planes that must move together: an index plane and a
coverage plane. Nothing enforces that. `_textSurface` is a plain
`Graphics::Surface &`, so any code can write indices directly:

```cpp
byte *mask = (byte *)_textSurface.getBasePtr(x, y);
fill(mask, _textSurface.pitch, CHARSET_MASK_TRANSPARENCY, w, h, 1);
```

and coverage is left behind. On FM-Towns that is not merely stale - the
compositor decides on the pair, so an orphaned partial coverage byte blends
palette entry 0 into the picture.

Two audits missed sites of exactly this shape:

| audit | claimed | actually missed |
|---|---|---|
| `4fb7670c254` | "six are FM-Towns paths ... left alone" | 4 sites in `restoreBackground` |
| after review | fixed `restoreBackground` | 2 more in `drawBox` |

The second miss happened *while fixing the first*, which is the signal that
the method is wrong. Grep finds occurrences; it cannot find the site written
next week.

## Why `const` is not enough

The obvious move - hand out `const Graphics::Surface &` - does not work,
because the existing idiom casts:

```cpp
byte *mask = (byte *)_textSurface.getBasePtr(x, y);   // const_cast, silently
```

A C-style cast performs `const_cast`, so every current write site would keep
compiling unchanged. `const` documents the intent and enforces nothing.

## The proposal: remove the member, keep only methods

Make the two planes unreachable and expose the operations instead. The
compiler then rejects a raw write because **the member does not exist**, which
no cast can work around.

### What the engine actually does with it

Measured across `engines/scumm`: 7 distinct members, 68 accesses.

| member | uses | what it is really asking |
|---|---|---|
| `pitch` | 20 | walking rows to read the mask |
| `getBasePtr` | 18 | a row pointer, mostly to read |
| `h` | 11 | bounds |
| `fillRect` | 7 | **a write** |
| `w` | 5 | bounds |
| `format` | 4 | always CLUT8 |
| `getPixels` | 3 | "is there a plane at all" |

So the writes are a small minority, and they are the whole problem.

### The interface

```cpp
class HiResOverlay {
public:
    // Reads: the mask is genuinely read pixel-by-pixel in hot loops, so
    // these stay cheap and direct.
    const byte *indexRow(int y) const;
    int   width()  const;
    int   height() const;
    bool  active() const;

    // Writes: every one of them touches both planes.
    void clear(int top, int height, byte transparent);
    void clear(const Common::Rect &r, byte transparent);
    void fillIndices(const Common::Rect &r, byte index);   // keeps coverage in step
    void saveState();
    void restoreState();
};
```

`fillIndices` is the one that fixes the `backColor` case: it fills the index
plane with a colour that is *not* a transparency key, and drops coverage,
because a hand-written index has no antialiasing to describe.

### Migration, in the order that keeps each step provable

1. **Add the methods, change nothing else.** Unit tests for each; no callers.
2. **Convert the 17 write sites** to the methods. This is where the coverage
   bugs disappear as a class rather than one at a time. Measurable: FM-Towns
   and DOS captures unchanged at each step.
3. **Convert the reads** to `indexRow`/`width`/`height`. Mechanical, and the
   hot loops keep their raw row pointers.
4. **Delete `_textSurface`.** From here a new raw write does not compile.

Steps 1-3 leave behaviour identical; step 4 is what makes the guarantee
permanent, and it is the only step that cannot be partially done.

### The cost

`charset.cpp` reads the mask per pixel while drawing. Those loops must keep a
row pointer rather than calling a method per pixel - `indexRow(y)` returns one,
so the inner loop is unchanged and only the setup moves.

`Gdi::drawStripToScreen` and the Towns blit read both planes together; they
should take the overlay rather than two surfaces, which also removes the
"did I pass the matching pair?" question at those call sites.

## What this does not solve

A write through a row pointer obtained from `indexRow` is still possible - the
pointer is `const`, but the same cast trick applies. The difference is that it
becomes a *deliberate* act with a `const_cast` visible in the diff, rather than
the ordinary idiom the codebase already uses everywhere.
