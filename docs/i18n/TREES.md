# The i18n fork's tree layout

One rule, and it is not negotiable:

> **`~/work/scummvm/i18n` is a BASE. Nobody works in it.**
> Every card gets its own worktree under `~/work/scummvm/i18n/.worktrees/<id>`.

## Why this file exists

The rule was already written down (skill `scummvm-engine-localization`, step 1b)
and was broken anyway on the fork's first two cards: C1 (`Graphics::FontSet`)
and M4 (the SCI taint measurement) were both given
`workspace: dir:/home/thkim/work/scummvm/i18n`. They collided — M4 had eleven
engine files and two new probe sources uncommitted while C1 was adding
`graphics/fontset.*` to the same checkout. C1 had to be blocked and its work
salvaged by hand out of the dirty tree.

Two writers in one checkout cannot be bisected apart, and reverting either
takes the other with it. The cost is not hypothetical: a worker editing the
shared tree has already destroyed a parent session's uncommitted work once on
this project.

## The layout

**2026-09-26: one line.** `hires-text` was merged into `i18n` (merge
`91cffbd25a`, both engines built together, 654 unit tests, SCI and SCUMM frames
identical before and after at run time: `runs/merge-hires-report.md` in the
harness repo). `hires-text` is frozen. Every card, SCUMM included, now opens
its worktree off `i18n`.

```
~/work/scummvm/
  repo/scummvm          the OLD line, branch hires-text. FROZEN since
                        2026-09-26: merged into i18n (91cffbd25a) and kept
                        only as a record. No new work lands on it.
                        Its own .worktrees/ holds the old cards.
  i18n                  THE line, branch i18n, cut from upstream/master; it
                        carries SCI and SCUMM hi-res text since the merge.
                        BASE ONLY. Build it to check the baseline; never edit.
  i18n/.worktrees/<id>  one per card. This is where work happens.
```

Both trees share one object store (`repo/scummvm/.git`) because `i18n` was
added with `git worktree add`, so a branch is visible from either side and
cherry-picking between the lines is free.

## Opening a card

```bash
cd ~/work/scummvm/i18n
git worktree add .worktrees/<card-id> -b wt/<short-name> i18n
```

Then the kanban card's workspace is
`dir:/home/thkim/work/scummvm/i18n/.worktrees/<card-id>` — never the base.

Each worktree needs its **own** `configure`; the object tree is shared but the
build tree is not:

```bash
cd ~/work/scummvm/i18n/.worktrees/<card-id>
export PATH=$HOME/.local/sysroot/usr/bin:$PATH
export PKG_CONFIG_PATH=$HOME/.local/sysroot/usr/lib/x86_64-linux-gnu/pkgconfig
export LD_LIBRARY_PATH=$HOME/.local/sysroot/usr/lib/x86_64-linux-gnu
./configure --disable-all-engines --enable-engine=scumm,scumm_7_8,sci,agi \
  --with-sdl-prefix=$HOME/.local/sysroot/usr --enable-release
make -j32 && make test
```

**A harness run inside a worktree must be pointed at THAT worktree's binary.**
The scripts default to the main checkout, so forgetting the override fails
silently by measuring the wrong build — which has happened here before.

## Closing a card

Merge the branch into `i18n`, then remove the worktree:

```bash
cd ~/work/scummvm/i18n
git merge --no-ff wt/<short-name>
git worktree remove .worktrees/<card-id>
git branch -d wt/<short-name>
```

## Checks

`~/work/scummvm/harness/i18ntrees.sh` fails when the base is dirty, when two
worktrees are on the same branch, or when a worktree's build points at another
tree's binary. Run it before opening a card and before believing a measurement.

## C11 (2026-09-27): the `wt/c11-*` branches are merged and gone

Every C11 task branch was merged into `i18n` with `git merge --no-ff`
after review and the invariant runs (the C8 ledger's standing ruling), its
worktree removed and the branch deleted. None is left locally or on the
remote; the merge commits are the record:

| Merge on `i18n` | Branch | C11 task |
|---|---|---|
| `fffc7c12f8` | `wt/c11-glyph-model` | T1 Unicode properties, per-glyph metrics, `TH_THA`/`VI_VNM` |
| `591c28a379` | `wt/c11-layout` | T2 shared layout stage on code points |
| `0c055ff327` | `wt/c11-map-coverage` | T3 map face chains, `[font.N] bitmap=`, `[layout]`, coverage |
| `ab23d34c32` | `wt/c11-scumm-metrics` | T6 SCUMM per-glyph metrics, per-charset faces |
| `6ef770b7d5` | `wt/c11-sci` | T5 SCI language-neutral text |
| `8c429b035e` | `wt/c11-scumm-utf8` | T7 SCUMM UTF-8 `<lang>.trs` |
| `e5759a8e70` | `wt/c11-thai-fit` | T3b Thai below-base marks and the TrueType fit |
| `3b06411178` | `wt/c11-grim` | T9 Grim `grim.<lang>.tab` |
| `1c23b1ee32` | `wt/c11-t3c` | T3c stacking-mark gate, SCUMM coverage escapes |
| `da78ab38fc` | `wt/c11-ags` | T8 AGS UTF-8 translations, map fonts, shared wrapping |

Interleaved on the same line: C10 `404b8aff50` (32-bit SurfaceSDL
screen), C8 T7 `6afdae3f3e`, C8 T9 `fb18b10ec2`, C8 T3 `8ffcbb540c`, C12
`89c7ae7316`. T10 (the matrix and these docs) had no engine branch: it
measured the merged `i18n` `da78ab38fc` from scratch worktrees that were
removed afterwards (`c11-ref-t10` = `6afdae3f3e`, the last `i18n` commit
before C11 merged, with C10; `c11-t10-ft`/`c11-t10-noft` = `da78ab38fc`
for `make test` with and without FreeType).

Worktrees still present under `i18n/.worktrees/` are reference builds
only, not open cards: `c6-test` (`91cffbd25a`, the C6 i18n build),
`c6-bis-good`/`c6-bis-bad` (the C6 SCUMM bisect pair) and `c8-ref`
(`3741a11e83`). The upstream reference is
`repo/scummvm/.worktrees/c6-upstream` (`503d074778`).
