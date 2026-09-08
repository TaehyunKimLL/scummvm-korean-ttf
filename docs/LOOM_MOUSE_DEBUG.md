# Loom mouse-coordinate issue — RESOLVED (config, not engine)

User report 2026-09-06: clicks landed off-target in Loom on the Windows build
(scummvm-kor-d0e65e8b-win64).

Cause per user: the target was still pointing at the **old-format map**
(`korean_ttf.map`, TrueType-era sections). Switching to the regenerated
`hires_text.map` fixed it. Not an engine bug; no source change made.

Why an old map can move clicks: with an old map the legacy loader draws the
text while the new layer only supplies the scale, so the multiplier the input
path divides by and the surface the game actually laid out on can disagree.
`~/games/fontcheck.sh` flags this as `scale set but new=0` / "map is OLD
TrueType format".

Prevention: any Loom target (`loom-kor`, `loom-3x`) that still carries
`korean_ttf_map=korean_ttf.map` should be moved to `hires_text_map=...` or
the key dropped so `hires_text.map` is auto-discovered.

Save validation results (current Linux build, map-free original data) remain
valid as text-rendering fixtures: `/home/thkim/games/loom-save-verified/`,
saves `loom-vga-ko.s01`–`.s04`, all load and show Korean labels/dialogue.

Open, unrelated: log prints `Setting 640 x 480` with aspect_ratio=false —
probably GUI-launcher sizing, not investigated since the click issue is closed.
