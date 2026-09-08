# Review these shell scripts and Python tools for correctness bugs.

They are a test harness for ScummVM: they launch the emulator under Xvfb,
capture frames, dump memory via GDB, and compare builds to detect rendering
regressions. Correctness matters more than style, because a broken harness
does not fail loudly - it produces a clean-looking "no difference" result and
the real regression ships.

## What to look for, in priority order

1. **Silent failure.** A command that fails but the script carries on and
   reports success. Missing exit-status checks, output that is never verified,
   `2>/dev/null` hiding the reason something is empty. Two real examples from
   this codebase:
   - a GDB script referenced a struct member that no longer existed, so GDB
     aborted the whole script and produced zero dumps; the comparison then
     reported "same=0 diff=0", which read as a pass.
   - a helper was passed a bare filename where it expected a path, matched
     nothing, recompiled nothing, and exited 0.

2. **Shared mutable state between concurrent runs.** Fixed paths under /tmp,
   fixed X display numbers, fixed window names. Two runs then share one file or
   one X server and capture each other's output. Some of this was just fixed
   (`mktemp` for GDB scripts, `xvfb.sh` for display allocation) - check whether
   any remain, including in scripts not obviously concurrent.

3. **Empty or partial results treated as valid.** Zero files compared, an
   empty capture, a save that does not exist, a window that was never found.
   Each should be reported distinctly from "compared and identical".

4. **Race conditions.** Waiting a fixed number of seconds for something to be
   ready, rather than polling for readiness. Killing a process without waiting
   for it. Reading a file another process is still writing.

5. **Quoting and word splitting** where a path could contain a space, and
   unquoted `$@`/`$*`.

## Context you need

- Everything runs headless under Xvfb; there is no window manager, so
  `xdotool windowactivate` fails and `windowfocus` must be used.
- SDL takes the X11 window class from argv[0], so a binary copied to
  /tmp/svm-work has class "svm-work" - searching for "scummvm" finds nothing.
  `find_window()` in `xvfb.sh` looks up the first mapped child of the root
  instead.
- ScummVM needs `extrapath` pointing at `dists/engine-data` or Korean text
  silently decodes to U+FFFD, which looks like a font bug rather than a
  configuration one.
- `~/.config/scummvm/scummvm.ini` is never edited in place; the scripts copy it
  to a temporary and patch the copy (`inifix.py`).

## What NOT to report

- Style, naming, shellcheck-level nitpicks that cannot cause a wrong result.
- Suggestions to rewrite in another language or restructure wholesale.
- Missing `set -e` as a blanket recommendation; several of these scripts
  deliberately continue past a failing target to test the others.

## Output

For each finding: the file, the line or function, what goes wrong, and what
the symptom would look like to someone using the tool. Order by how likely the
bug is to produce a wrong conclusion rather than an obvious crash. If a script
is fine, do not pad the review by saying so.
