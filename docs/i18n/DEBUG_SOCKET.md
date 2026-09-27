# The debug socket and recorder — driving a game on state, not on the clock

Status: **implemented** on `i18n`. Engine side:
`engines/sci/debugsocket.{h,cpp}`, hooks in `console.cpp`, `kgraphics.cpp`,
`kevent.cpp`, `text16.cpp`, `controls16.cpp`, `transitions.cpp`,
`drivers/upscaled.cpp`, plus a small `GUI::Debugger` extension. Client side:
`harness/i18n/scigame.py` (library), `harness/i18n/rec2script.py`
(recording → script), `harness/i18n/kq1_tour.py` / `kq1_intro.py`
(examples).

| Commit | What |
|---|---|
| `683ddd1be0` | driver: map a game mouse position back to backend coordinates; copy out the scaled bitmap |
| `dc22819ecf` | `GUI::Debugger`: an output sink and a public way to run a command line |
| `501160d04b` | the socket, input synthesis, `state`, `wait`, `dump` |
| `56d56df7e1` | Windows: a named pipe instead of a UNIX socket |
| `ef8dc87fb2` | the recorder, `debug_record=` / `record` |

This is **test tooling**, not localisation. It lives on the i18n branch
because every measurement after `501160d04b` was taken through it. For
upstream it is its own submission (`DESIGN.md`, §"For upstream review").

**C8 Task 2 (branch `wt/c8-debugsocket`, not yet merged): the socket is
engine-neutral.** The transport, recorder, console fallback and the input
commands moved to `gui/debugsocket.{h,cpp}` (`GUI::DebugSocket`); the wire
protocol is `gui/debugsocket-protocol.{h,cpp}` (unit-tested,
`test/gui/debugsocket.h`). `GUI::Debugger::onFrame()` opens it, so every
engine with a debugger has it. SCI keeps its state commands as a
`GUI::DebugSocketExtension` (`engines/sci/debugsocket.*`); AGS adds the
console command `ags_say`. The generic client is `harness/i18n/sock.py`.
See §"Engine-neutral socket" below; the SCI sections after it still hold.

`[source]` = read in code. `[measured]` = observed by running something.
`[unmeasured]` = a claim this document has not yet earned.

## Why it exists

A driver script that sleeps N seconds after a click lands on a different
animation cel every run, so comparing two runs measures timing, not
rendering. `[measured]` The KQ1 inventory tour: four minutes of xdotool
and sleep, captures that differed run to run. The same tour through the
socket: 13 seconds, no sleep, five captures byte-identical across runs.

## Engine-neutral socket (C8 T2)

### Turning it on, per game

`[source]` `Debugger::onFrame()` looks at the config **once**, on its first
call, and only in the running game's own domain
(`ConfMan.getActiveDomain()`, via `DebugSocketProtocol::gameDomainKey()`).
A `debug_socket=` or `debug_record=` under `[scummvm]` is ignored, so it
cannot open a socket in every game. `[measured]` 5 Days with both keys under
`[scummvm]` only: no socket file, no `DebugSocket` log line, frames
IDENTICAL-PREFIX to the reference. Without either key, a later frame costs
one bool test. A socket that fails to open logs one warning and is not
retried; `debug_socket_failed` is gone.

### Build switch: `USE_DEBUG_SOCKET`

`configure --disable-debug-socket` (default: enabled on `darwin*`,
`linux*`, `*bsd*`, `dragonfly*`, `solaris*`, `haiku*`, `mingw*`, `cygwin*`
hosts, disabled on every other port: consoles, handhelds, emscripten, mint,
os2 ... which may lack `sys/un.h`/`AF_UNIX`). Off, only the transport is
left out: `debug_socket=` logs `DebugSocket: not built on this platform`
and is ignored; the recorder and the protocol code still build.
`[measured]` The macOS `--disable-debug-socket` build is warning-free in
`gui/debugsocket.*` and gives that warning.

### Generic commands

```
key <name>|<keycode> [ascii] [flags]
                      a name as in the SCI list below, or one character;
                      a longer all-digit word is a keycode
type <text>           one key per character
click <x> <y> [r]     game coordinates (an extension may map them)
move <x> <y>
wait frames <n>       OK after n more Debugger::onFrame() calls (for most
                      engines: n screen updates). n must be 0..100000000;
                      anything else is an error reply, not a wait
dump <path>           g_system->lockScreen() as it is: raw rows at <path>,
                      "w h bits format" at <path>.txt (format =
                      PixelFormat::toString(), e.g. "RGB565@2", or CLUT8),
                      the palette at <path>.pal when CLUT8
save <slot>, load <slot>
record [<path>]
<any console command>
```

**Every number is checked** (`DebugSocketProtocol::parse*`, unit-tested
in `test/gui/debugsocket.h`): decimal digits only, so a `-` or a stray
letter is an error reply and nothing reaches the game.

| Argument | Accepted |
|---|---|
| `click`/`move` x, y | `0 <= x < g_system->getWidth()`, `0 <= y < getHeight()`; checked again after an extension maps them (SCI: lowres → hires backend). A mouse event off the screen can reach engine code that indexes a buffer by it. `click`'s third argument is `r` or absent. |
| `key` keycode | one character is always that key (`key 5` = the 5 key); a longer all-digit word is a keycode `1 .. KEYCODE_LAST-1` |
| `key` ascii, flags | only after a keycode; ascii `0..65535`, flags a subset of the `KBD_*` bits (`0..127`) |
| `wait frames` n | `0..100000000` |
| `save`/`load` slot | `0..999` |

`[measured]` Through the socket on 5 Days: `click -1 5`, `click 320 10`
(320x240 screen), `move 10 x`, `key -5`, `key 13 -1`, `key 13 13 128`,
`key Return 13`, `save -1`, `load x`, `wait frames -1` each got an error
reply; `move 319 239` got `OK`. SCI's own commands (`hold`, `walk`,
`step`, `timeout`, `get`) are not covered by this and still parse with
`atoi`.

An extension's commands are tried first, so SCI's `dump`, `wait <cond>`
and `timeout` replace the generic ones there. Keys go out one per poll, at
least 40 ms apart, the key-up on a later poll, through
`g_system->getEventManager()->pushEvent()`; an extension can hold them back
(`inputReady()`, SCI: `listening()`).

**`save`/`load` wait for a safe point.** `onFrame()` runs inside the
backend's `updateScreen()` (`surfacesdl-graphics.cpp`, `opengl-graphics.cpp`)
for every engine but SCI, which is no place to write or restore a game.
The request is kept, no further command is read, and a
`Common::EventSource` the socket registers runs it at the next
`EventManager::pollEvent()`, where the global main menu saves too. There
`canSaveGameStateCurrently()` / `canLoadGameStateCurrently()` decide; a
refusal is retried at later polls for 5 s, then the reply is
`FAIL cannot save now[: reason]`. Otherwise the reply is `OK`, or
`FAIL <code> <description>` with the `Common::Error`. What `OK` means is
the engine's: AGS's `saveGameState()`/`loadGameState()` return
`kNoError` whatever happens, SCI's `loadGameState()` only schedules the
restore (so `load` of a missing slot also says `OK`). `[measured]` SCI
refuses unless the game option `gmm_save_enabled=true` is in the ini (a
hand-written harness ini lacks it); with it, KQ1 saved from room 1. 5 Days
refused (`cannot save now`) at the points tried. Before C8, SCI's `save`
bypassed these checks.

### Framing: dot-stuffing

A reply line that starts with `.` is sent with one more `.` in front (as
SMTP does), so a line that is itself `.` goes out as `..` and cannot end
the reply. Clients drop the first `.` of any line starting with `..`
(`scigame.py`, `sock.py`). An empty reply is the `.` line alone.

### Transport details kept from the SCI socket

- **unlink before bind.** `listen()` deletes whatever is at the path before
  binding: a socket file left by a killed run would otherwise make every
  later bind fail. The path is the user's own config value; point it at a
  file you own (the harness uses `<run dir>/debug.sock`).
- **EAGAIN spin on write.** A reply is written with blocking semantics on a
  non-blocking socket: on `EAGAIN` the loop retries at once, so a client
  that stops reading stalls the game until it reads again. Replies are
  small and the clients read until `.`, so this has not been seen;
  `[unmeasured]` with a large reply to a stuck client.

### AGS: `ags_say <font> <key-substring|#n>`

The first `.tra` entry whose source key contains the substring (or entry n,
0-based, in file order) is shown with `DisplayAtY(-1, text)` at the next
game loop (`check_debug_keys()`), in font `<font>` as both normal and speech
font for the call. `[measured]` 5 Days `--language=ko`: `wait frames 120`,
`ags_say 0 #40`, `wait frames 5`, `dump` shows a text box with the Korean
line (as mojibake until the EUC-KR/`extfnt` work).

### AGS hi-res text at N× (C23): `ags_dump_native`, `ags_render_text`, `ags_hires_rects`, `ags_frame_times`, `ags_call`

Card C23 (`AGS_HIRES_TEXT_DESIGN.md`, merged `0e3148bd89`) draws AGS's
mapped text at N× (`[hires] scale=`/`hires_text_scale`) over an N×-upscaled
game frame. These commands support it:

- **`ags_dump_native <path>`** - the native (game-resolution) frame last
  presented, in the generic `dump` format (raw rows at `<path>`, `w h bits
  format` at `<path>.txt`, a palette at `<path>.pal` for 8-bit games). This
  is the frame scripts, plugins, screenshots and saves see - at N≥2 the
  socket's own `dump` reads the N× screen instead. It also writes the
  screen of that same moment to `<path>.screen` (and `<path>.screen.txt`),
  and the reply ends with `| <count> <x0,y0,x1,y1>...`, the N× text rects
  of that frame, as `ags_hires_rects` reports them - so a single call gives
  the native frame, the screen and the rects of one moment together.
- **`ags_render_text <font> <scale> <path.png> <text|#n>`** - a probe,
  independent of the game's own drawing: `text` (or translation entry `n`,
  0-based) rendered with the game's outline setting into one PNG, the
  game-resolution line nearest-upscaled on top and the N× line
  (`scale` 1-3) below it, white on dark blue.
- **`ags_hires_rects`** - the screen rects (native pixels, `x0,y0,x1,y1`,
  exclusive) of the N× text drawn in the last presented frame; empty at
  scale 1 or when no twin was drawn. Used to check that the N× frame is the
  native one upscaled everywhere outside those rects (invariant 3 in
  `AGS_HIRES_TEXT_DESIGN.md` §8).
- **`ags_frame_times [reset|on|off]`** - mean milliseconds per frame of
  `RenderToBackBuffer()` and `Present()` (N× composition included), of the
  native-patch copy/compare (plugin hooks and own-surface batch blits while
  a twin is on screen) and of building text twins, since the last reset.
  The timers run automatically at scale ≥ 2; at scale 1 they only run after
  `ags_frame_times on` (and stop again on `off`). `ags_frame_times reset`
  zeroes the counters without changing whether they run.
- **`ags_call <tint r g b | shake delay amount length | flip n | fadeout
  speed | fadein speed | guitrans gui percent | dialog n | saybg char
  <key|#n>>`** - a test driver: runs one game function from the next game
  loop (as `ags_say` does), for scenarios a game does not reach by itself
  (a fade, a shake, a screen flip, a translucent GUI, a built-in dialog, a
  background `Say`). Every argument is checked in the game's own range
  before the call runs, and a bad one gets a `FAIL` reply rather than the
  game's own `quit()` (an out-of-range `tint`/`flip`/`shake`/`guitrans`
  value) or an endless loop (`fadeout`/`fadein` with `speed` ≤ 0 on an
  8-bit game). `shake` needs `delay` ≥ 2; `delay` 1 ends the game with a
  script error and is refused.
- At N≥2, `click`/`move` take **screen** (N×) coordinates; AGS's own mouse
  unscaling maps them back to the game.

## Turning it on (SCI, before C8)

Nothing runs unless one of two keys is in the game's config section
(`console.cpp:288`):

| Key | Effect |
|---|---|
| `debug_socket=PATH` | POSIX: listen on the UNIX socket `PATH`. Windows: `\\.\pipe\PATH`, a named pipe. One client at a time. |
| `debug_record=PATH` | Start recording to `PATH` at launch. Works without `debug_socket`, so a human can just play. |

If opening fails, the engine logs it, sets `debug_socket_failed` in the
config, and does not retry.

## Protocol

One line in = one command. The reply is the command's output followed by a
line holding a single `.`. Every existing console command works
(`room`, `vo ego`, `script_strings 995`, ...), because the socket is a
`GUI::Debugger::OutputSink` on the console.

`[source]` The socket is read from `Console::onFrame()`, which the backend
calls from `DefaultEventManager::pollEvent()` (`default-events.cpp:244`) and
from `updateScreen()` in the SDL and OpenGL graphics managers. Only every
256th call actually polls (`kPollInstructions`). The comment on that
constant in `debugsocket.h` says `onFrame()` fires once per VM instruction;
the call sites say once per event poll or screen update. So a command runs
when the game polls events or presents a frame, never inside a kernel
call. Game ticks (`kAnimate`, via `Console::tick()`) drive the frame
counter and `wait` evaluation.

### Commands the socket adds

```
key <name>            press and release: Return, Escape, Tab, F1..F12,
                      Up/Down/Left/Right, KP_1..KP_9, or one character
type <text>           one key per character
click <x> <y> [r]     mouse button at LOWRES x,y (r = right button)
move <x> <y>          move the mouse (lowres)
state                 one line of JSON (below)
dump <prefix>         raw buffers: <prefix>_low.bin (lowres),
                      <prefix>_scaled.bin (composited hires frame),
                      <prefix>_plane.bin (text plane, if allocated),
                      <prefix>_pal.bin (palette)
timeout <frames>      how long a wait may take (default 600 ticks)
wait <cond> [&&|| <cond>]   reply OK when the condition holds, TIMEOUT otherwise
record [<path>]       start recording there; no argument stops
```

Keys are handed over **one at a time**, each held until the game has polled
for keyboard events since it was queued. `[measured]` Two failures made
this necessary. A text-edit control reads one key per `kGetEvent`, so a
burst in one frame lost all but the first. And a key sent during a picture
transition was dropped, because `GfxTransitions::updateScreen()` discards
every pending event.

Click coordinates are lowres. The driver maps them to backend coordinates
(`683ddd1be0`). `[measured]` Before that, a click at 205,163 on the 640×400
Korean driver read back as 102,81.

### `state`

One JSON object: `room`, `ego` (`x`, `y`, `view`, `loop`, `cel`), `score`,
`frame`, `windows`, `texts` (drawn this frame, with screen rects),
`buttons` (labels with screen rects, so a script clicks by label, not by
guessed pixel), `input` (the parser line is live, and its content),
`listening`, `idle`.

Two fields took measurement to get right:

- **`listening`** is false from a screen transition until the room's
  first `kGetEvent` after it. A transition discards queued input, so a key
  sent in that window is lost.
- **`input`** is measured in event polls, not ticks. The edit control is
  modal and there is no `kAnimate` while it is up.

### `wait` conditions

```
room <op> N           ego.x <op> N          ego.y <op> N
ego in X0 Y0 X1 Y1    windows <op> N        global N <op> V
sel <obj> <selector> <op> V                 frames N        idle N
input                 noinput               listening [N]
text <substring>      seen <substring>      button <label>  inputText <exact>
```

`<op>` is one of `== != < <= > >=`. `<obj>` is `ego`, `room`, or any
object name the segment manager knows.

- `text` holds if a text **containing** the substring was drawn *since the
  wait began*. `seen` holds if it is anywhere in the recent text log.
- **`text` and `seen` take the rest of the line**, quotes included, because
  game strings contain spaces and quotes (`"xyzzy."`). They must therefore
  be the last condition on the line. `wait room == 5 && text Hello` works;
  `wait text Hello && room == 5` waits for the text `Hello && room == 5`.
- `idle N` means N unchanged display samples *since the wait began*, not
  "the screen has been still for N". Otherwise `wait ... || idle N` returned
  before the walk it was pacing had started.
- A wait also has a wall-clock deadline, for when ticks stop coming.

## Recording

`debug_record=PATH`, or `record PATH` over the socket, writes one line per
tick where the state changed and one per input event, carrying the state it
arrived in (`ef8dc87fb2`):

```
S <TAB> {state}
E <TAB> key <keycode> <ascii> <flags> <TAB> {state}
E <TAB> click <x> <y> ... <TAB> {state}
```

The file is flushed per line and written to `PATH.tmp`, renamed on close,
so a run that crashed still leaves a readable `.tmp`.

`[measured]` Three things the recorder had to get right:

- **Observer priority.** An `EventObserver` at `DefaultEventManager`'s own
  priority sees nothing, because that one queues every event and returns
  true. The recorder registers at priority 5, ahead of its 0
  (`debugsocket.cpp:193`), and never eats an event.
- **Click position comes from the event.** `getMousePos()` still holds the
  position from before the click.
- **JSON-escape the state's strings.** Swapping quotes for apostrophes made
  a generated script wait for text the game never drew (`"xyzzy."`).

### `rec2script.py`

Turns a recording into a `scigame.py` driver script. For each event it emits
the **weakest** condition that tells that moment apart from the one before,
and discards the player's timing:

```
room changed           -> g.wait_room(N)
a new text was drawn   -> g.wait_text("...")
parser line opened     -> g.wait_input()        closed -> g.wait_noinput()
window count changed   -> g.wait_windows(N)
ego moved and stopped  -> g.wait_ego_in(x-4, y-4, x+4, y+4)
nothing above          -> g.wait_idle(3)        (commented: the only guess)
```

`[measured]` A KQ1 session of 23 events: 22 state waits, no timing
fallbacks, replays in 10 seconds; two replays produce 23 byte-identical
frame dumps.

## Windows

`debug_socket=NAME` opens `\\.\pipe\NAME` (`56d56df7e1`). The pipe is
overlapped, so the connect is asynchronous and `PeekNamedPipe` answers
"anything to read?" without blocking the VM loop. `[measured]` The first
attempt used `PIPE_NOWAIT`, and the client's own `WriteFile` never returned.

The Python client (`scigame._PipeConn`) uses one raw `CreateFile` handle
through ctypes, with a reader thread. A Python file object deadlocked
because its buffer lock is held for the whole blocking read.

`[measured]` Under Wine with a Windows Python client: the KQ1 tour's five
captures are byte-identical to the Linux run's, three runs of three.

## Paths on a new machine

`scigame.py` hard-codes `~/work/scummvm/harness` and
`~/work/scummvm/i18n` (the layout in `TREES.md`). A harness run against a
card's worktree has to be pointed at that worktree's binary, as `TREES.md`
warns.

## Cost when off

C8: `Debugger::onFrame()` reads the game domain once and caches the answer
(§"Turning it on, per game"); the paragraph below describes the SCI socket
before that.

`[source]` The engine hooks (`text16.cpp:584`, `animate.cpp:650`,
`kevent.cpp:46`, `kgraphics.cpp:932`, `controls16.cpp:174`,
`transitions.cpp:169`) call into `Console`, whose `note*()`/`tick()` do
nothing without a socket. `Console::onFrame()` without a socket still
checks up to three config keys (`debug_socket_failed`, `debug_socket`,
`debug_record`) on each call, meaning each event poll and screen update,
before it can decide there is nothing to do. `[unmeasured]` whether that is
visible. Caching "neither key is set" at engine start would remove it.
