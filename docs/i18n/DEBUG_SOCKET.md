# The SCI debug socket and recorder — driving a game on state, not on the clock

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

`[source]` = read in code. `[measured]` = observed by running something.
`[unmeasured]` = a claim this document has not yet earned.

## Why it exists

A driver script that sleeps N seconds after a click lands on a different
animation cel every run, so comparing two runs measures timing, not
rendering. `[measured]` The KQ1 inventory tour: four minutes of xdotool
and sleep, captures that differed run to run. The same tour through the
socket: 13 seconds, no sleep, five captures byte-identical across runs.

## Turning it on

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

`[source]` The engine hooks (`text16.cpp:584`, `animate.cpp:650`,
`kevent.cpp:46`, `kgraphics.cpp:932`, `controls16.cpp:174`,
`transitions.cpp:169`) call into `Console`, whose `note*()`/`tick()` do
nothing without a socket. `Console::onFrame()` without a socket still
checks up to three config keys (`debug_socket_failed`, `debug_socket`,
`debug_record`) on each call, meaning each event poll and screen update,
before it can decide there is nothing to do. `[unmeasured]` whether that is
visible. Caching "neither key is set" at engine start would remove it.
