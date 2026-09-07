# Build and test setup

Everything needed to rebuild, package and verify this fork on a fresh shell.
Written because two things in here are silent traps: the cross-compiler is not
on `PATH` by default, and Wine is **not installed on this machine** despite an
earlier note claiming a runtime smoke test had passed.

## Trees

| path | what |
|---|---|
| `~/src/scummvm` | the source, and the native (Linux) build |
| `~/src/scummvm-win` | a separate build directory for the Windows cross-build |
| `~/src/scummvm-korean-ttf/docs` | plans and findings |
| `~/games` | harnesses, game data, `dist/` |

`scummvm-win` holds only build output — it configures against
`/home/thkim/src/scummvm`, so a source edit is picked up by both builds with no
copying.

## Native build and unit tests

```bash
cd ~/src/scummvm
make -j24
make test                                # 506 tests
```

cxxtest ships inside the source tree (`test/cxxtest/bin/cxxtestgen`), so
nothing extra is needed on `PATH` — the `export PATH="$HOME/.local/bin:$PATH"`
that appears in this project's older command lines is a leftover and does
nothing.

### The portability build

Upstream must build without FreeType, so check that separately before
proposing anything that touches the TTF path:

```bash
mkdir /tmp/noft && cd /tmp/noft
~/src/scummvm/configure --disable-freetype2 --disable-all-engines --enable-engine=scumm
make -j24
```

A real `#else` behind `USE_FREETYPE2` is what this proves. Last run: 0 errors.

## Windows cross-build

**The toolchain is not on `PATH`.** Without this export the build stops with
`Error 127` / `command not found`, which reads like a makefile problem and is
not:

```bash
export PATH="$HOME/.local/mingw/bin:$HOME/.local/mingw/root/usr/bin:$PATH"
```

Compiler: `x86_64-w64-mingw32-g++ (GCC) 13-win32`.

### Rebuilding

```bash
cd ~/src/scummvm-win
export PATH="$HOME/.local/mingw/bin:$HOME/.local/mingw/root/usr/bin:$PATH"
make -j24                                # ~85 MB scummvm.exe
```

### Reconfiguring from scratch

Only needed if `config.mk` is lost or a dependency moves. This is the exact
line the current tree was configured with:

```bash
cd ~/src/scummvm-win
export PATH="$HOME/.local/mingw/bin:$HOME/.local/mingw/root/usr/bin:$PATH"
SYSROOT=$HOME/.local/mingw/deps/sysroot/mingw64
PKG_CONFIG_LIBDIR=$SYSROOT/lib/pkgconfig \
~/src/scummvm/configure \
  --host=x86_64-w64-mingw32 \
  --disable-all-engines --enable-engine=scumm,scumm_7_8 \
  --enable-release \
  --with-sdl-prefix=$SYSROOT \
  --with-freetype2-prefix=$SYSROOT \
  --with-ogg-prefix=$SYSROOT --with-vorbis-prefix=$SYSROOT \
  --with-flac-prefix=$SYSROOT --with-mad-prefix=$SYSROOT \
  --with-zlib-prefix=$SYSROOT
```

`--enable-engine=scumm,scumm_7_8` matters: the v7/v8 games are a separate
engine flag, and both on/off must build for upstream.

### Packaging

```bash
cd ~/games
export PATH="$HOME/.local/mingw/bin:$HOME/.local/mingw/root/usr/bin:$PATH"
python3 stage-win.py                     # -> dist/scummvm-kor-<sha>-win64/
cd dist && zip -qr scummvm-kor-<sha>-win64.zip scummvm-kor-<sha>-win64
sha256sum scummvm-kor-<sha>-win64.zip
```

`stage-win.py` reads the short SHA from the source tree, so commit first or the
directory is named after the previous build. Expect **60 files**: 21 DLLs, 34
data files, `scummvm.exe`.

## Verifying a Windows build

**Wine is not installed here.** `which wine` returns nothing, so "it starts and
renders" cannot be checked on this machine — that is the user's job on real
Windows. An earlier note in this project claimed a Wine smoke test had passed;
it was wrong and should not be repeated.

What static inspection does establish:

```bash
cd ~/games
export PATH="$HOME/.local/mingw/bin:$HOME/.local/mingw/root/usr/bin:$PATH"
python3 dllcheck.py dist/scummvm-kor-<sha>-win64     # every import resolves
python3 winverify.py                                 # PE format + feature strings
```

`winverify.py` greps the shipped binary for strings **only the new code
emits**, which is what proves the feature reached the artefact rather than a
stale object being relinked. Edit the version near the top when the SHA
changes. Current expectations:

```
ok  FM-Towns/16-bit alpha activation
ok  v7 fallback
ok  TTF map warning
ok  TTF latin-only bake
ok  TTF on-demand bake
ok  layer startup
ok  platform scale gate
map keys: shadow, outline, stroke, glyphs, bitmap
```

A `MISSING` row means either the feature did not ship **or** the string was
renamed — check the source before assuming the build is broken. That happened
once here: `no glyph set for this language` was correctly gone, and its
replacement had been dropped by a refactor.

Use GNU `strings`, not `x86_64-w64-mingw32-strings`, which cannot read PE.

## Runtime harnesses (Linux)

These drive the real engine under Xvfb. They need a different environment
again — the SDL/X utilities live in a second sysroot:

```bash
export PATH="$HOME/.local/sysroot/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/sysroot/usr/lib/x86_64-linux-gnu"
export SDL_AUDIODRIVER=dummy
source ~/games/xvfb.sh
xvfb_start 1400 1000        # 1400x1000 or larger, or a 2x window is downscaled
export DISPLAY=$DISP
```

`xvfb.sh` picks a free display rather than a fixed number, so two harnesses can
run at once without capturing each other's windows.

### The three that matter

| script | what it answers |
|---|---|
| `towns_ab.py <tag>` | FM-Towns control vs hi-res vs DOS reference |
| `baseline.py <tag>` + `baseline_cmp.py <a> <b>` | did any scene's pixels move |
| `ttf_paths.py <tag>` | which TTF configurations actually draw |

Expected `towns_ab.py`: Towns control **4–10** colours, Towns hi-res **31**,
DOS **202**. A number outside that is a regression, not noise.

`baseline_cmp.py` matches frames by content, not by index — the harness shoots
on a timer, so two runs produce different frame counts and positional
comparison is meaningless. Run the same binary twice first to get the noise
floor; measured spreads are 96–5753 px depending on the scene.

### Running the game directly

A game must be launched **by target name**, not from the launcher, or the
engine never starts and every log is empty:

```
scummvm --config=run.ini -d1 --gfx-mode=opengl --no-filtering \
        --no-aspect-ratio --stretch-mode=pixel-perfect --scale-factor=1 <target>
```

and the config needs `engineid=scumm` alongside `gameid=`, plus
`extrapath=/home/thkim/src/scummvm/dists/engine-data`. Missing `engineid` is
the failure that looks like a broken build.

**`-d1` is required for any hi-res diagnostic**: every one of them is
`debug(1, ...)`, so without it the log is silent and the code looks dead. Check
`grep -c 'hi-res text enabled'` before concluding anything from an absent
marker.

## Game data

| path | what |
|---|---|
| `~/games/mi2kor` | Korean MI2 |
| `~/games/mi2towns` | English MI2, used as the FM-Towns and DOS base |
| `~/games/mi2-en-hr2` | baked `.fnt` set for English MI2 |
| `~/games/dott`, `dott-kor-hr` | DOTT |

Harnesses symlink game data into a scratch directory rather than copying it,
and write the map there — which is also how a configuration is denied an input
on purpose (omit the map, omit the `hr*` fonts) to prove which code path runs.
