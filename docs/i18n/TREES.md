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

```
~/work/scummvm/
  repo/scummvm          the OLD line, branch hires-text, 103 commits of it.
                        Kept for archaeology and for the user's test builds.
                        Its own .worktrees/ holds the old cards.
  i18n                  the NEW line, branch i18n, cut from upstream/master.
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
