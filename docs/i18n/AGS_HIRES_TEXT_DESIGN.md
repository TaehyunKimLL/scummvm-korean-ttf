# Hi-res text for AGS: text twins over an N× frame

Status: **implemented, merged 0e3148bd89; OpenGL check pending (C30).**
Originally written as a design against `i18n` at `d73eba2426`. It extends
`HIRES_COMPOSITOR_DESIGN.md` (SCI) and `MULTI_ENGINE_TEXT_DESIGN.md`
§2.2/§7.2 (AGS) to the case that document left out of scope ("hi-res
supersampled text for AGS", line 62). See "Results" below for what changed
between this design and the merged code, and for the T7 measurements.

`[source]` = read in code (file:line at `d73eba2426`, paths relative to
`engines/ags/` unless given in full). `[measured]` = observed by running
something. `[unmeasured]` = a claim this document has not yet earned.

## Goal

AGS draws translated text at the game's own resolution. 5 Days a Stranger
runs at 320×240 (a 320×200 game, letterboxed, 16-bit) `[measured]`
`runs/c14/cap5days-ja/run.log` ("Game native resolution: 320 x 240 (16 bit)
letterbox-by-design"), so Thai at 9-11 px is legible only zoomed in and CJK
is cramped (`shots/c14/5days-{ja,zh,th}-sheet.png`,
`runs/c14/5days-capture-report.md`, verdict "th: PASS, with the same size
caveat").

Success is:

- the game's pictures integer-scaled N× (2 or 3) with no smoothing, and the
  text the map's fonts draw rendered at N× from the same faces, with real
  alpha;
- **everything at game resolution unchanged**: line breaks, box sizes,
  positions, widths reported to scripts, and every pixel a script, plugin,
  screenshot or save game can read;
- a game without a map, or with `scale` 1, byte-identical to today.

## Decisions

| # | Decision | Chosen | Rejected, and why |
|---|---|---|---|
| G1 | Output size | **The display mode is N× the native size**, through AGS's own render-frame scaling (`GameScaling`), so the mouse is unscaled by code that already exists | Engine-side ad-hoc scaling: would duplicate `Mouse::WindowToGame()` (`engine/device/mouse_w32.cpp:95-96,109-110,151`) |
| G2 | Where hi-res text lives | **A "text twin" per text-bearing bitmap**: an N× 32-bit copy of the bitmap with its text redrawn at N× (approach C) | One screen-space text layer (approach B): AGS text is baked into bitmaps that move, fade, stretch and sit under other GUIs and the cursor (§3); a layer on top breaks every one of those |
| G3 | The game-res bitmap | **Still drawn exactly as today**, native text included | Drawing text only into the twin: scripts, plugins, screenshots and saves read the game-res pixels (§1.3) |
| G4 | Composition | **In `ScummVMRendererGraphicsDriver`**: the native frame is rendered as today; the N× frame is the native frame upscaled, with the draw list replayed at N× from the first twin onward | Rendering every frame at N× from the start: the room stage writes into camera surfaces and plugin-visible stage buffers at native size (`ali_3d_scummvm.cpp:270-338,395-455`) |
| G5 | Layout | **Game-res only.** The N× pass redraws the same strings at N× pen positions derived from the game-res pen positions | N×-native layout: widths drawn and widths the game measured would disagree (the S7/S9 class of defect, `HIRES_COMPOSITOR_DESIGN.md` D6) |
| G6 | Which text | **Engine-built text only** in v1: speech, Display boxes, text overlays, GUI labels/buttons/list boxes/text boxes, built-in dialog options, the speech top bar | Script-drawn text (`DrawingSurface.DrawString` into sprites or backgrounds): stays native in v1 (§4, task T8) |
| G7 | Colour depth | **16- and 32-bit games**; 8-bit games stay native with one warning | 8-bit: needs index+coverage twins so palette fades reach the text (SCI's D4); none of the patch games is 8-bit (`MULTI_ENGINE_TEXT_DESIGN.md` line 235) |
| G8 | Configuration | **`[hires] scale=`** (already parsed by the shared reader) plus ini `hires_text_scale`, default 1 (off) | Automatic scale: changes the window of every game that ships a map |

## 1. How AGS draws text today

### 1.1 The one primitive, and what the map changes

- `wouttextxy()` `[source]` `shared/font/fonts.cpp:422-439` adds the font's
  `YOffset` and calls the font's renderer `RenderText()` straight into an
  Allegro `BITMAP` at game resolution.
- `wouttext_outline()` `[source]` `engine/ac/display.cpp:555-569` is the entry
  almost every caller uses: an outline (a second font drawn at the same
  point, or `wouttextxy_AutoOutline()` `display.cpp:476-553`, which draws the
  text into a stencil and stamps it around the pen) and then the text.
  `wouttext_aligned()` `display.cpp:571-579` centres or right-aligns first.
- With `hires_text.map`, `load_font_size()` `fonts.cpp:482-495` hands font N
  to `GlyphFontRenderer` (C11 T8). Its faces are opened at one size,
  `plan.size × SizeMultiplier` or the game font's height
  (`glyph_font_renderer.cpp:129`); `RenderText()` (`:242-254`) decodes code
  points and `GlyphTextDrawer::drawText()` (`glyph_font_draw.cpp:67-131`)
  blends coverage into the destination: 16/32-bit with alpha
  (`blendPixel()` `:47-65`), 8-bit or transparent-without-alpha by
  thresholding at 128 (`:59`, `:74`). A character the faces lack is drawn by
  the game's own renderer (`GameFallback::drawChar()` `:289`).
- Line breaking: `split_lines()` `fonts.cpp:403-419` goes through the shared
  layout stage (`split_lines_layout()` `:373-390`) for translations and
  mapped fonts. Widths are `get_text_width_outlined()` at game resolution.

So the only thing that is "resolution" in AGS text is the destination
bitmap. Everything upstream of `RenderText()` - layout, widths, pen
positions, colours - is resolution-free input we can replay.

### 1.2 Who calls it, and into which bitmap

| Text | Built by | Destination bitmap | Reaches the screen as |
|---|---|---|---|
| Speech, `Display()`, text overlays, `SayBackground` | `create_textual_image()` `display.cpp:70-221`, via `display_main()` `:224` and `Overlay_SetText()` `engine/ac/overlay.cpp:64-86` | a fresh transparent bitmap (`display.cpp:150-151`), or the text window GUI's (`draw_text_window()` `:718-758`) | an overlay: `SetImage()` stores it as an **owned dynamic sprite** (`engine/ac/screen_overlay.cpp:66-77`), `construct_overlays()` `draw.cpp:1993-2045` makes its DDB |
| Speech top bar (character name) | `draw_text_window_and_bar()` `display.cpp:761-798` | a new bitmap replacing the window (`:767-772`), text at `:789` | part of the same overlay |
| GUI labels, buttons, list boxes | `GUI::DrawTextAligned*()` `shared/gui/gui_main.cpp:721-729`, from `gui_label.cpp:106`, `gui_button.cpp:450`, `gui_listbox.cpp:202`; text boxes `gui_textbox.cpp:74` | the whole GUI's bitmap: the software driver draws controls into it (`draw_controls_as_textures` is false without accelerated transforms, `draw.cpp:1761-1763`; `gui.DrawWithControls()` `:1805`, `gui_main.cpp:262-310`) | the GUI's DDB, z-sorted with overlays (`draw.cpp:1831-1848`) |
| Translucent GUI controls | `DrawWithControls()` draws the control into a temp bitmap and alpha-blends it in (`gui_main.cpp:288-295`) | a temporary | blended into the GUI bitmap |
| Built-in dialog options | `write_dialog_options()` `engine/ac/dialog.cpp:318-365` | the options bitmap | a DDB of a sub-bitmap, passed as `render_graphics(extraBitmap)` (`dialog.cpp:793-815`, `draw.cpp:2235-2260`), drawn after the UI stage |
| Custom dialog option rendering | the game's script, through `DrawingSurface` (`dialog.cpp:635-654`) | the options bitmap | as above |
| `DrawingSurface.DrawString(Wrapped)` | `engine/ac/drawing_surface.cpp:310-345` | a dynamic sprite, the room background, or the custom dialog surface | wherever the script puts that sprite |
| `RawPrint` | `engine/ac/global_drawing_surface.cpp:130-165` | the room background | the room stage |
| Plugin `DrawText` | `plugins/ags_plugin.cpp:176-182` | the stage back buffer (`GetStageBackBuffer()`) | directly in the frame |
| Engine dialogs (save/restore) | `engine/gui/my_label.cpp:50`, `my_listbox.cpp:99`, `my_push_button.cpp:64`, `my_textbox.cpp:53-56` | their window bitmap | as a GUI |
| FPS counter | `draw.cpp:1722-1723` | its own bitmap | engine overlay |

### 1.3 What else reads those bitmaps

This is why G3 keeps the game-res text:

- An overlay's image is a dynamic sprite; `Overlay.Graphic` returns its
  number to the script (`overlay.cpp:122-127`) and scripts can draw it
  elsewhere.
- Overlays may be stretched (`scaleWidth/scaleHeight`,
  `screen_overlay.h:86`, `Overlay_SetScaledSize()` `overlay.cpp:175`), made
  translucent (`transparency` `:90`), re-ordered (`zorder` `:89`) and, in the
  room layer, cropped by walk-behinds (`draw.cpp:2026-2033`).
- Saves store overlays by sprite number (`screen_overlay.cpp:139-157`,
  `kOverSvgVersion_36108` "use dynamic sprites" `screen_overlay.h:71`).
- `DynamicSprite.CreateFromScreenShot`, save thumbnails and plugins read the
  native virtual screen (`GetCopyOfScreenIntoBitmap()`
  `ali_3d_scummvm.cpp:682-699`, `GetMemoryBackBuffer()` `:643-645`,
  `GetStageBackBuffer()` `:668-670`).

## 2. How the ScummVM AGS driver presents a frame

- ScummVM has **one** AGS driver, the software one
  (`engine/gfx/gfx_driver_factory.cpp` registers only `"ScummVM"`):
  `RequiresFullRedrawEachFrame()` false, `HasAcceleratedTransform()` false
  (`ali_3d_scummvm.h:167-168`). So the renderer is always the software
  path, whether the backend is SurfaceSDL or OpenGL - the backend only
  receives a finished frame.
- The virtual screen is native size (`CreateVirtualScreen()`
  `ali_3d_scummvm.cpp:148-162`). `RenderToBackBuffer()` (`:371-456`) walks
  nested sprite batches; each sprite is blitted with its own mode
  (`RenderSpriteBatch()` `:458-502`: opaque blit, alpha blend with optional
  global alpha, legacy transparency, the `DRAWENTRY_TINT` screen tint, and
  `nullptr` entries that run plugin hooks).
- `Present()` (`:536-632`) copies the virtual screen to the ScummVM screen,
  converting 32-bit ARGB to the screen's order (`copySurface()` `:504-534`,
  which asserts equal size). It does **not** use the render frame.
- The display mode is always the game size: `precalc_screen_size()` returns
  `game_size` under `AGS_PLATFORM_SCUMMVM`
  (`engine/main/graphics_mode.cpp:186-188`), and `set_gfx_mode()`
  (`lib/allegro/gfx.cpp:46-53`) → `AGSEngine::setGraphicsMode()`
  (`ags.cpp:306-313`) → `initGraphics(w, h, format)`.
- 5 Days is 16-bit and SurfaceSDL gave it an RGB565 hardware screen
  `[measured]` (`runs/c14/cap5days-ja/run.log`: "SurfaceSDL: 320x240
  hardware screen in SDL_PIXELFORMAT_RGB565"). C10's policy
  (`backends/graphics/surfacesdl/surfacesdl-hwformat.h`,
  `wantHwScreen32()`) gives a 32-bit hardware screen as soon as the game
  asks for a 4-byte format.
- Fades are drawn on the native virtual screen: hi-colour fades blend a
  colour over it and call `Present()` per step (`highcolor_fade_in/out()`
  `:707-771`); 8-bit fades step the palette (`__fade_from_range()`
  `:786-808`).

### 2.1 AGS's own "hi-res" features, and why none of them is the answer (approach A)

| Feature | What it is | Why it does not give hi-res text |
|---|---|---|
| Legacy hi-res games / data resolution | `GetDataUpscaleMult()`, `IsLegacyHiRes()`, `IsDataInNativeCoordinates()` (`shared/ac/game_setup_struct_base.h:185-215`); `FFLG_SIZEMULTIPLIER` fonts (`shared/ac/game_setup_struct.cpp:87-88`) | A property of the compiled game: script coordinates, room masks, sprite sizes and font metrics change with it. Forcing it on a 320×200 game changes what scripts see |
| Render sprites at screen resolution | `OPT_RENDERATSCREENRES` (`shared/ac/game_struct_defines.h:85`), `usetup.RenderAtScreenRes` (`engine/main/config.cpp:311`) → `RenderSpritesAtScreenResolution()` (`draw.cpp:2059`) | A no-op in the ScummVM driver (`ali_3d_scummvm.h:231`), and upstream only scales sprite textures in hardware drivers; text is already baked into game-res bitmaps by then |
| Display mode larger than native (render frame) | `graphics_mode_update_render_frame()` (`graphics_mode.cpp:480-504`) sets `GameScaling` from native size to the render destination; the mouse is unscaled through it (`mouse_w32.cpp:95-96,109-110,151`) | Only scales the finished frame. **But it is the plumbing G1 reuses**: making the display mode N× costs one line in `precalc_screen_size()` and keeps the mouse right |

A therefore contributes the display plumbing; the text itself needs C.

## 3. Approaches

| | A: AGS renders at N× | B: side list of text draws, composited on top | C: text twins, composited in the driver (**chosen**) |
|---|---|---|---|
| What is recorded | nothing | (screen x, y, font, colour, string) per draw | per text-bearing bitmap: its draws, and an N× twin built from them |
| Script-drawn text into sprites | changes pixels scripts read | cannot follow a sprite (moves, scales, rotates, copies) | stays native in v1; a twin can follow an untransformed sprite later (T8) |
| Alpha / transparency (`Overlay.Transparency`, GUI `Transparency`, 32-bit alpha windows) | ok | the layer does not know the bitmap's alpha | the twin is drawn with the same DDB alpha and blend mode |
| Z-order: a GUI, overlay or cursor above the text | ok | text drawn over everything | exact: the twin sits in the draw list where the bitmap was |
| Fades, screen tint | ok | text not faded or tinted | tint: replayed at N× (`DRAWENTRY_TINT`); fades: frames during a fade are the native frame upscaled (§5.4) |
| Stretched overlays (`Overlay.Width`) | ok | wrong size | the twin is stretched to N× the stretch size |
| Save games | changes | nothing saved | nothing saved; after a restore a surviving text overlay shows native text until it is re-created (§5.6) |
| Box sizes and line breaks | change (fonts measured at another size) | unchanged | unchanged: layout is game-res only (G5) |
| Cost | whole game at N× | a pass per frame | an upscale per frame, plus replay of the draw list's tail at N× |
| OpenGL vs SurfaceSDL | — | — | the same: the engine hands a finished N× frame to either backend |

B's recording idea survives inside C: the records are kept per bitmap, not
per screen.

## 4. Components

```
game-res side (unchanged pixels)                  N× side (new)
────────────────────────────────                  ─────────────────────────────────
create_textual_image / GUI / dialog options
   │ wouttext_outline(ds, …)  ── TextCapture ──►  records: {font, colour, outline, string,
   │ (draws native text as today)                          pen x/y, clip, pre-pixels, post-pixels}
   ▼                                              TextTwin::build(ds, records, N)
game-res Bitmap  ─────────────────────────────►   N× ARGB twin = upscale(ds without its text)
   │                                                           + records redrawn at N×
   ▼                                                           (GlyphFontRenderer at N×)
sync_object_texture → ALSoftwareBitmap  ◄──── SetHiResTwin(twin)
   │
ScummVMRendererGraphicsDriver
   RenderToBackBuffer(): native frame, as today; from the first twin on,
                         snapshot the native frame and record the tail of the draw list
   Present():            N× frame = upscale(snapshot) + tail replayed at N×
                         (twins 1:1, other sprites upscaled, same blend modes)
                         → initGraphics(W×N, H×N, 32-bit)
```

### 4.1 TextCapture (engine-free, unit-testable)

A scope opened by a construction path around one destination bitmap:
`TextCapture cap(ds); … cap.finish()`. While a scope is open for `ds`,
`wouttext_outline()` (and the `my_*` engine dialogs' `wouttextxy()` calls)
records one entry **if the text font's current renderer is
`GlyphFontRenderer`** (a font the map does not name, or one a plugin
replaced through `font_replace_renderer()` `fonts.cpp:144-158`, is left
native):

- the arguments (font, colour, outline font or auto-outline thickness and
  style, string after `ApplyTextDirection`, pen x/y, the bitmap's clip);
- the text rect (text width × font surface extent, grown by the outline
  thickness), and the bitmap's pixels in that rect **before** and **after**
  the native draw.

`finish()` decides which entries are valid, walking them last to first on a
copy of the bitmap: an entry is valid only if the copy's pixels in its rect
still equal its "after" pixels, in which case the "before" pixels are put
back. Anything drawn over the text later (a disabled-control stipple, a
control above a label, a blob) makes that entry and every earlier entry it
covered invalid, and they stay native - never a hi-res glyph over something
that was drawn on top of it. The copy, with valid entries removed, is the
text-free picture.

### 4.2 TextTwin

`build()`: convert the text-free picture to 32-bit ARGB (magenta or alpha 0
→ transparent), nearest-upscale N×, and redraw each valid entry at N×
(§4.3). The twin is always 32-bit so antialiased edges over a transparent
background keep their alpha, which a 16-bit game's own bitmap cannot (it
thresholds at 128, `glyph_font_draw.cpp:59`).

Memory (arithmetic): a 300×100 speech box at 2× is 600×200×4 = 480 KB.

### 4.3 N× glyphs

`GlyphFontRenderer` gains `RenderTextScaled(text, font, dst, x, y, colour, N)`:

- A second glyph chain per (font, N), opened lazily at `fd->Size × N` with
  the same faces, gamma and fit probes (`glyph_font_renderer.cpp:123-148`,
  `SetTranslationSample()` `:157-207`).
- **Pen positions come from the game-res pass**: each cluster starts at N ×
  its game-res pen position; the glyph shape is the N× face's; a combining
  mark is placed against its base with the N× metrics. The line therefore
  covers exactly N× the box it covered at game resolution (G5).
- Vertical: the N× cell is aligned so its baseline falls at N × the game-res
  baseline (the faces' fit can differ by a pixel from N × the small cell).
- A character the faces lack (the game's WFN draws it natively) is drawn at
  game resolution into a scratch cell and nearest-upscaled: it looks as it
  does today.
- Outlines: an outline font is redrawn the same way if it is also mapped,
  else upscaled; auto-outline runs the same stencil algorithm at N× with
  thickness × N.

### 4.4 Attaching twins

| Path | Scope | Twin attached to |
|---|---|---|
| `create_textual_image()` (speech, Display, text overlays, top bar) | the final `text_window_ds` (the top bar replaces the bitmap, `display.cpp:767-772`, so the scope moves with it) | the overlay: a side table keyed by the owned sprite number, dropped by `ResetImage()` / `free_dynamic_sprite()` (`screen_overlay.cpp:50-56`) |
| `GUIMain::DrawWithControls()` (software GUIs) | the GUI bitmap; translucent controls (`gui_main.cpp:288-295`) record nothing | `_GP(guibg)[index]`, rebuilt when the GUI is redrawn (`draw.cpp:1802-1817`) |
| `write_dialog_options()` | the options bitmap | the sub-bitmap DDB made at `dialog.cpp:793` |
| engine dialogs `my_*` | their window bitmap | as a GUI |

`sync_object_texture()` (`draw.cpp:828-850`) passes the twin to the DDB
through a new `IDriverDependantBitmap::SetHiResTwin()` (a no-op default in
`engine/gfx/ddb.h:39`, implemented by `ALSoftwareBitmap`,
`ali_3d_scummvm.h:59-111`).

A twin is **ignored** (the native bitmap is drawn and upscaled) when the
sprite sits in a batch that is not offset-only - the room camera batches,
which is where room-layer overlays (`Overlay.CreateRoomTextual`) are drawn
and cropped by walk-behinds (`draw.cpp:2026-2033`) - or when the software
path has transformed the image (`transform_sprite()` `draw.cpp:2025` for a
flipped copy; a plain stretch is handled, §5.2).

## 5. Composition in the driver

### 5.1 Display size

When the scale N ≥ 2 is active (§6):

- `precalc_screen_size()` returns `game_size × N`
  (`graphics_mode.cpp:186-188`); the render frame becomes N× through the
  existing `kFrame_Round` path (`get_game_frame_from_screen_size()`
  `:158-184`) and `GameScaling` handles the mouse.
- `SetDisplayMode()` (`ali_3d_scummvm.cpp:109-138`) asks for a 32-bit format
  whatever the game's depth, which also selects C10's 32-bit hardware screen
  on SurfaceSDL.
- The virtual screen stays native (`CreateVirtualScreen()` unchanged), so
  every native consumer of §1.3 is unchanged.

### 5.2 Per frame

1. `RenderToBackBuffer()` runs as today.
2. In `RenderSpriteBatch()`, the first time a DDB with a usable twin is
   about to be drawn, copy the native target (the whole virtual screen) as
   the **snapshot**, and from then on append every entry to the **tail**:
   the DDB, its final position (sprite + batch offset), alpha, blend mode,
   stretch size, the batch clip, tint entries and plugin-hook entries.
3. `Present()`:
   - no twin this frame: the N× frame is the native frame converted to
     32-bit and nearest-upscaled;
   - otherwise: upscale the snapshot, then replay the tail at N×. A twin is
     blitted 1:1 at (N·x, N·y) (or stretched to N× its stretch size); any
     other sprite is drawn from a cached N× 32-bit copy (keyed by the DDB and
     its bitmap, dropped on `UpdateDDBFromBitmap()` `:260-264` and
     `DestroyDDB()`), with the same blend (`set_alpha_blender`,
     `kArgbToRgbBlender` with global alpha, `DrawSpriteWithTransparency`,
     `LitBlendBlt` for the tint - the calls of `:469-499`) and the clip × N;
   - a plugin-hook entry in the tail cannot be replayed at N×: the native
     frame is kept from just before and just after the hook, and the pixels
     the hook changed are upscaled into the N× frame at that point (one log
     line per plugin).
   - Shake (`xoff/yoff`) and flip (`:536-556`) apply to the N× frame with
     offsets × N.
4. The N× frame goes to the screen with `copySurface()`'s dirty-rect diff
   (`:504-534`), generalised to the N× size.

The mouse cursor is a sprite in its own batch after the UI
(`draw.cpp:2112-2117`), so it is in the tail and stays above the text.

### 5.3 What is identical by construction

- The native virtual screen, every game-res bitmap, every script-visible
  width and height: nothing in AGS's own code path is skipped.
- Outside the rectangles of valid twin records, the N× frame is exactly the
  nearest upscale of the native frame (the replay draws the same pixels,
  scaled).

### 5.4 Fades and transitions

`highcolor_fade_in/out()` and `BoxOutEffect()` present native frames they
built themselves; those frames are upscaled without replay, so text shown
during a fade is the native text for the fade's duration. A speech box is
rarely up during a fade; SCI's compositor has the same compromise for
transitions.

### 5.5 Cost `[unmeasured]`

- A frame without text: 320×240 → 640×480 is 307,200 output pixels of
  conversion and copy, then `copySurface()`'s per-pixel compare, 4× today's.
  At 3× (960×720), 9×.
- A frame with text: one native snapshot, plus the tail at N× (overlays,
  GUIs, the cursor - a few sprites).
- A twin is built when its bitmap is rebuilt: once per speech line, once per
  GUI change. A label bound to `@OVERHOTSPOT@` changes as the mouse moves,
  so its GUI's twin rebuilds then; measure.

### 5.6 Save and load

Nothing new is saved and the save format is unchanged. A text overlay that
survives a restore (`SayBackground`, a custom text overlay) is restored from
its sprite with no twin and shows native text until the game re-creates
it. Blocking speech never survives a restore. Save thumbnails are made from
the native frame, as today.

## 6. Configuration

| Key | Where | Meaning |
|---|---|---|
| `[hires] scale=` | `hires_text.map` | N, 1..3 (the shared reader's range, `graphics/hires_text/font_map.cpp:34,982-990`). Already parsed for every engine; AGS starts applying it |
| `hires_text_scale` | ini (game domain) | overrides the map, 1..3 |
| `[hires] alpha=` | map | unchanged meaning; also governs the twins' glyph edges |
| `[hires] face=`, `size=`, `[font.N] …` | map | unchanged; the N× chain is opened at `size × N` |

- Default N = 1: no N× screen, no twins, today's code path exactly
  (Ruling R1 in §9).
- N ≥ 2 is honoured only when the map (or ini) names at least one font
  (`HiResFontConfig::active()`, `hires_font_config.h:78`), the game is
  16/32-bit, and the backend offers a 32-bit format; otherwise one warning
  and N = 1.
- The `MULTI_ENGINE_TEXT_DESIGN.md` / `HIRES_TEXT_MAP.md` tables should gain
  an AGS column entry: `[hires] scale` — "yes (C23): display N×, text twins".
- A translation pack enables it by adding `scale=2` to its map's `[hires]`
  (the C14 maps written by `harness/i18n/c14/apply.py` would).

## 7. Failure and fallback

| Situation | Behaviour |
|---|---|
| 8-bit game | N = 1, one warning (G7) |
| No 32-bit screen format | N = 1, one warning |
| Font not mapped, or replaced by a plugin | no record; the text is native, upscaled |
| Face fails to open at `size × N` (`TtfGlyphSource` range) | that font's records stay native; one warning per font |
| Something drawn over the text after it | those records invalid (§4.1); native there |
| Twin in a room batch, or a transformed overlay | twin ignored; native |
| Plugin hook in the tail | native delta upscaled (§5.2) |
| Fade / box-out | native frames upscaled (§5.4) |

## 8. Verification

**Invariants.**

1. N = 1 (and no map): frames byte-identical to base `d73eba2426` for 5
   Days English and a Blackwell English game - two base runs compared too,
   for timing noise (COMMON_BRIEF rule).
2. N = 2 against N = 1, same scenario: the **native** virtual screen is
   byte-identical (needs a new debug-socket command, `ags_dump_native
   <path>`, since `dump` reads `lockScreen()` - `DEBUG_SOCKET.md` line 81).
   This is the "line breaks and box sizes unchanged" check.
3. N = 2: outside every valid record's rect × N, the N× dump equals the
   nearest upscale of the native dump, pixel for pixel.
4. `make test` passes.

**Unit tests** (engine-free):

- `TextCapture`: before/after restore gives the exact text-free picture;
  an entry overdrawn later is invalid, and so is an earlier entry it covers;
  clip is honoured.
- `GlyphTextDrawer` at N×: every covered pixel of a line lies inside N× its
  game-res text rect; the pen of each cluster is N × its game-res pen; a
  Thai mark stays over its base (`test/engines/ags/glyph_renderer.h`
  exists to extend).
- Scale config: map/ini precedence and range (1..3), fallback to 1.

**Captures** (`harness/i18n/c14/smoke.py` flow: `ags_say`, `key Return`,
`wait frames 10`, `dump`, plus `ags_dump_native`):

| Scenario | Check |
|---|---|
| 5 Days ja/zh/th, the six C14 lines (`tra:45, 6, 17, 23, 294` + title) at N = 2 | invariants 2-3; text legible at 1:1 (Thai marks stacked, no tofu); every hi-res text pixel inside 2× the native box; no overflow |
| same at N = 3 | as above; frame time |
| Blackwell Unbound (kor-trs, 320×240 32-bit) with a map naming a Korean face | Sierra speech with portrait, `Display`, dialog options (built-in), hotspot label GUI; click an option at 2× (mouse unscaling) |
| Blackwell Unbound, no map, N = 2 in ini | warning "scale needs a mapped font", N = 1, identical to base |
| 5 Days English, map with `scale=2` and faces | English text in the face at 2×; native frame identical to N = 1 |
| Fade out while a background speech overlay is up | no crash; frames during fade are native-upscaled |
| Save with `SayBackground` up, restore | native text on the restored overlay, then hi-res once re-created |
| SurfaceSDL vs OpenGL backend | identical dumps (the engine composes) |
| Frame time, N = 1/2/3 | recorded in the report `[measured]` |

## 9. Rulings

- **R1: default scale 1** — an N× window is a visible change the player did
  not ask for; translation packs opt in with `scale=2`. Cost if wrong: one
  line in each shipped map.
- **R2: pen positions from the game-res pass (grid-locked)** — guarantees
  the box and line breaks; glyph spacing may look slightly uneven at N×
  because the game-res pen rounds to whole pixels. Cost if wrong: a later
  sub-pixel pen (26.6 advances scaled to fit the same extent) inside the
  same box.
- **R3: 32-bit twins and a 32-bit N× frame for 16-bit games** — keeps AA
  over transparent speech; costs a 16→32 conversion per frame.
- **R4: script-drawn text stays native in v1** — the before/after record
  would work on an untransformed dynamic sprite too, but sprites get
  rotated, resized, tinted and copied by script; T8 decides after v1 is
  measured.
- **R5: the driver interface gains `SetHiResTwin()`** — a ScummVM-only
  divergence in `ddb.h`; the alternative (a side table keyed by DDB
  pointer) risks stale pointers when DDBs are recycled
  (`recycle_ddb_sprite()` `draw.cpp:808-825`).

## 10. Implementation plan

Each task in its own worktree commit series, captures before and after.

| Task | Content | Test first |
|---|---|---|
| **T1** Config | `HiResFontConfig::scale()` from `[hires] scale` and ini `hires_text_scale`; the §6 gates; warnings | unit: precedence, range, gates |
| **T2** N× display | `precalc_screen_size()` × N; 32-bit display format; `Present()` upscales native → N× (no twins yet); shake/flip × N; `ags_dump_native` console/socket command | invariant 1 (N = 1), invariant 3 with no text; mouse hit-test at 2× |
| **T3** N× glyphs | `GlyphFontRenderer::RenderTextScaled()`, lazy N× chains, grid-locked pens, fallback upscale, outline font and auto-outline at N× | unit: extents and pens (§8) |
| **T4** TextCapture + TextTwin | engine-free classes, before/after validity, text-free restore, twin build | unit: §8 TextCapture cases |
| **T5** Capture hooks | scopes in `create_textual_image()` (incl. top bar), `DrawWithControls()`, `write_dialog_options()`, `my_*`; twin side table for overlays; `SetHiResTwin()` via `sync_object_texture()` and the dialog-options DDB | 5 Days ja: records made, native frame unchanged (invariant 2) |
| **T6** Driver replay | snapshot + tail recording in `RenderSpriteBatch()`; N× replay in `Present()` with blend modes, stretch, clip, tint; N× sprite cache; plugin-hook delta; room batches ignore twins | invariants 2-3 on the §8 scenarios |
| **T7** Captures and measurements | the §8 table, frame times, report + shots `shots/c23/` | — |
| **T8** (later) | script `DrawingSurface` text on untransformed dynamic sprites; custom dialog-option surfaces; 8-bit index+coverage twins; a GUI checkbox | decided after T7 |

T1-T4 are independent of each other; T5 needs T3-T4; T6 needs T2 and T5.

## 11. Open questions

1. Default scale when a map names faces but no `scale=`: stay 1 (R1), or 2
   for games up to 400 px wide?
2. Is native text for script-drawn strings (custom dialog-option rendering,
   `DrawingSurface.DrawString`) acceptable for v1 (R4)? Which Blackwell
   screens use them is `[unmeasured]`.
3. Offer N ≥ 2 at all for 640-wide games (Blackwell Deception 640×480,
   Epiphany 640×400 `[measured]` in C6 run logs)? 2× gives 1280×960.
4. Is a ScummVM-only method on `IDriverDependantBitmap` (R5) acceptable, given
   upstream-patch candidates are cut from this tree?

## Results

Built in three stages (`runs/c23/stage1-report.md`, `stage2-report.md`,
`stage3-report.md`), merged into `i18n` at `0e3148bd89`. `make test`: 988
tests OK. Every open question above was answered during implementation and
review; the rest of this section records the answers.

**The open questions, answered:**

- **Q1 (default scale).** Stays **1**: a map (or ini) that names no
  `scale=`/`hires_text_scale` gets N=1, byte-identical to before this card,
  whatever faces it names. `hires_text_scale` alone (no map, plus
  `hires_text_font`) still counts as "a mapped font" for the gate.
- **Q2 (script-drawn text, R4).** Stayed native for v1, as designed.
  Custom dialog-option rendering (`DrawingSurface` into the options
  surface) also stays native - it is script-drawn, not engine-built, so it
  is out of scope the same way. T8 (script-drawn text on untransformed
  dynamic sprites, 8-bit twins, a GUI checkbox) was not picked up.
- **Q3 (640-wide games).** Allowed. 5 Days a Stranger (320×240, scale 2 →
  640×480) and Blackwell Unbound (320×240, Korean face) were both captured
  at N=2 with no code path that excludes wider games; nothing in T1-T6
  gates on game width.
- **Q4 (`SetHiResTwin()`, R5).** Kept: `IDriverDependantBitmap` gained
  `SetHiResTwin(std::shared_ptr<HiResTwin>)`, a ScummVM-only addition (a
  no-op default, implemented by `ALSoftwareBitmap`). No alternative (a side
  table keyed by DDB pointer) was needed; the review accepted the pointer
  key for the twin registry itself (see rulings below).

**Other rulings that held, or were added, during implementation:**

- **No `scale=` and no `hires_text_scale` → N=1**, with zero measurable
  per-frame cost: every new code path is gated on `_G(hiresTextScale) > 1`
  or on `hires_text_twins()` returning null. N=1 frames stayed
  byte-identical to the pre-C23 base (`51eba95d4e`) through every stage.
- **N ≥ 2 needs a mapped font, a 16- or 32-bit game and a 32-bit screen
  format**; otherwise one warning ("hires text scale N needs a mapped
  font ...; using 1") and N=1. 8-bit games are refused outright (G7).
- **Invariant 3 (outside the text rects, the N× frame equals the upscaled
  native frame) is exact by construction**, not just "usually true": after
  the tail replay, every pixel outside the union of that frame's text
  rects × N is overwritten with the *final* native frame, upscaled
  (`HiResKeepNativeOutsideText()`, added during stage 3 to close an
  Important review finding about 16-bit translucent GUIs and tints
  differing from native by rounding). Verified with a 16-bit
  translucent-GUI-plus-tint scene: invariant 3 held in both the buggy and
  the fixed binary, but the fix makes it hold by construction rather than
  by luck.
- **The `data:`-style bundled-font path was not needed for C23** - it ships
  separately as C29.

**T7 measurements (`runs/c23/stage3-report.md`):**

- **Built-in dialog options, save/restore, shake, flip, fades**: all
  exercised at N=2 on 5 Days a Stranger and Blackwell Unbound; invariant 3
  held in every captured frame, including mid-shake and mid-flip frames.
- **OpenGL at N=2: not run.** SDL dummy video cannot open an OpenGL
  context, and a real display on the test machine never reached a game
  frame within 90 s. Nothing in the C23 code is OpenGL-specific - it only
  touches `initGraphics` (N× size, 32bpp), `copyRectToScreen`/
  `updateScreen` and `lockScreen` - but the pixel format path (GL commonly
  offers RGBA8888/ABGR8888, not ARGB) and texture size at N=3 are
  unmeasured. This is left for **card C30**.
- **Frame times** (mean ms/frame over 400 frames, SurfaceSDL, SDL dummy
  video): render (`RenderToBackBuffer`, includes snapshot/tail recording)
  stays under 1 ms at N=1-3 for both games measured. `present` (upscale +
  replay + `updateScreen()`) is noisy because it includes the backend
  blit, but the most expensive scene measured - a 16-bit tint over
  translucent GUIs at N=2 - cost about 13 ms/frame, still well under a
  25 ms (40 fps) budget. The native-outside-text overwrite
  (`HiResKeepNativeOutsideText`) is one extra full-frame pass at N² pixels
  per composed frame, included in those numbers.
- **Aspect-ratio correction** (SurfaceSDL and OpenGL) only corrects
  320×200 and 640×400 outputs (plus the EGA/Hercules sizes). A 320×200
  game keeps 4:3 correction at N=2 (640×400) but loses it at N=3
  (960×600); a 640×400 game loses it at N=2 (1280×800). Games at other
  native sizes (5 Days and Blackwell are both 320×240) are unaffected
  either way. Recommend N=2, not N=3, for 320×200 games when
  `aspect_ratio` is on.

**New AGS debug-socket commands** (see `DEBUG_SOCKET.md`): `ags_dump_native`,
`ags_render_text`, `ags_hires_rects`, `ags_frame_times` and `ags_call`.
