# assets/ui/art — key art and interface art

Generated with `gpt-image-2.6-sunburst` (prompts: `art/ui_art/PROMPTS.md`), cleaned and exported by the
scripts in `art/ui_art/`. Style anchors: `docs/reference/R01-moxie-concept.png` (Moxie), R03/R04
(environments), `HUD-wireframe.png` (cassette deck). Palette = `UiPalette`: yellow `#ffd23f`, ink
`#1b1714`, paper `#f4ecd8`, pink `#ff4fa3`; tapes red `#ff4d6d`, yellow `#ffd23f`, blue `#3ec5ff`,
green `#7dff6b`.

Rebuild / check (PIL + numpy only, a few seconds each):

    python -I art/ui_art/build_logo.py     # logo/
    python -I art/ui_art/build_ui.py       # ui/ + ui/slices.json
    python -I art/ui_art/build_art.py      # keyart/, cards/, doll/
    python -I art/ui_art/verify_all.py     # sizes, alpha, slice margins (exit 1 on failure)
    python -I art/ui_art/verify_ui.py      # stretch test on dark + busy grounds
    python -I art/ui_art/sheets.py         # contact sheets + mock-ups in art/ui_art/sheets/

Godot import: keep the defaults (`fix_alpha_border` on, filter linear). Textures are straight
(non-premultiplied) alpha. Everything is authored for the 1600x900 canvas at 1:1.

## logo/ — OVERDUB logotype (transparent, spelling checked O-V-E-R-D-U-B on each)

| file | size | use |
|---|---|---|
| `overdub_logo_wordmark.png` | 2165x717 | **Primary.** Horizontal graffiti wordmark, the O is a tape reel. Master. |
| `overdub_logo_wordmark_1024.png` | 1024x384 | Same, on a fixed canvas — title screen (shown about 520 px wide in the mock-up). |
| `overdub_logo_cassette.png` | 1534x1026 | **Secondary.** Word sprayed across a tilted cassette sticker. Master; splash, pause header. |
| `overdub_logo_cassette_1024.png` | 1024x704 | Same on a fixed canvas (can replace the procedural `MenuArt.paint_logo`). |
| `overdub_logo_stacked.png` | 1222x1225 | OVER / DUB stacked around a cassette window — square placements. |
| `alt/overdub_logo_angular.png` | 2179x706 | Alternate kept for reference (80s angular). Not for shipping screens. |
| `overdub_mark_512/256/128/64.png` | square | Compact mark (the reel-O). Window icon, save-slot stamp, loading spinner. |

## keyart/ — title screen (opaque RGB, wordless)

| file | size | use |
|---|---|---|
| `title_1600x900.png` | 1600x900 | **Use this on the 16:9 title screen.** The 3:2 painting fitted to height; the dark left side is extended by 250 px, so x 0..560 is quiet dark space for the menu. |
| `title_1536x1024.png` | 1536x1024 | Master 3:2, left third empty. Do not centre-crop it to 16:9 (cuts her hair and boots). |
| `title_1024x1536.png` | 1024x1536 | Portrait variant; the top third is calm sky and ruins for the logo. |

Moxie stands on the right at the lip of the shaft with the four echoes (red, yellow, blue, green) behind her.

## cards/ — chapter cards and ending (opaque RGB 1536x1024, wordless; add titles in engine)

| file | theme |
|---|---|
| `chapter_1_upper_ruins.png` | `LevelTheme.UPPER` — sunlit overgrown sandstone |
| `chapter_2_the_middle.png` | `LevelTheme.MID` — cavern, last daylight, first machinery |
| `chapter_3_neon_depths.png` | `LevelTheme.LOWER` — rune metal, magenta and cyan neon |
| `chapter_4_time_machine.png` | `LevelTheme.CORE` — the reel-to-reel time machine |
| `ending.png` | Ending card: gate open, headphones down, cassette raised, the four echoes beside her; nothing is shown beyond the light. |
| `ending_alt_approach.png` | Lead-in beat: she walks toward the opening gate (no echoes). Cross-fade into `ending.png`. |

In the four chapter cards Moxie is small, lower right, seen from behind; the upper-left is the calmest
area for a title. Show with `STRETCH_KEEP_ASPECT_COVERED`; a 16:9 centre crop is safe for these.

## ui/ — interface pieces (transparent RGBA)

Machine-readable copy of everything below: `ui/slices.json`. Margins are **pixels in the texture**, in
the order left, top, right, bottom — use them as `patch_margin_*` on `NinePatchRect` or
`texture_margin_*` on `StyleBoxTexture`. Axis stretch mode *Stretch* or *Tile* both work: the edge
bands are exactly constant along their length. The stretchable middle of every texture is 16 px.

| file | size | L | T | R | B | notes |
|---|---|---|---|---|---|---|
| `panel.png` | 80x80 | 32 | 32 | 32 | 32 | Dark inked panel, off-white sticker edge. Min 64x64. Opaque fill; use `modulate.a` for glass. |
| `button_normal.png` | 86x86 | 34 | 30 | 36 | 40 | Yellow, black slab shadow. Min 70x70; drawn for 86 px height. Ink text. |
| `button_hover.png` | 86x86 | 34 | 30 | 36 | 40 | Pale face, pink slab (also for keyboard focus). |
| `button_pressed.png` | 86x86 | 34 | 30 | 36 | 40 | Face moved down-right onto the slab, darker. Shift the label by (+4, +4). |
| `button_disabled.png` | 86x86 | 34 | 30 | 36 | 40 | Grey face, faint slab. |
| `name_tab.png` | 60x60 | 22 | 20 | 22 | 24 | Yellow tag without shadow: a speaker tab that sizes to the name, chips, tags. |
| `dialogue_box.png` | 299x123 | 247 | 71 | 36 | 36 | Dialogue box with a fixed speaker tab built into the top-left cell (name area about x 38..228, y 14..50). Min 283x107. Body text starts below y 60. For long names use `panel.png` + `name_tab.png`. |
| `tooltip.png` | 106x90 | 56 | 30 | 34 | 44 | Paper bubble, pink shadow, tail in the bottom-left cell (tip at about x 27 on the bottom edge). Ink text. Flip horizontally for a right-hand tail. |
| `toast.png` | 132x95 | 84 | 0 | 32 | 0 | **3-slice, fixed height 95.** Do not stretch vertically (the hazard-striped cap would smear). Text starts at x 78. |
| `progress_track.png` | 72x36 | 28 | 0 | 28 | 0 | **3-slice, fixed height 36.** Empty track. |
| `progress_fill.png` | 72x36 | 28 | 0 | 28 | 0 | White fill on the same canvas as the track (already inset): draw at the same origin with width = max(56, value x track width) and tint with the tape colour. With `TextureProgressBar` turn on `nine_patch_stretch` and use these margins. |
| `ruler_strip.png` | 512x96 | – | – | – | – | Master-ruler texture, cream masking tape. **Tile horizontally** (seamless). One tile = one bar of 4 beats, 128 px per beat, ticks at x 64, 192, 320, 448; the tall tick at x 64 is the downbeat. To put beat 0 at screen x0, start the texture at x0 − 64·scale. Scale non-uniformly to match the HUD beat width. |
| `ruler_strip_dark.png` | 512x96 | – | – | – | – | Same geometry, charcoal with cream ticks. |
| `cassette_shell.png` | 640x410 | – | – | – | – | Cassette shell, blank cream label, **transparent window**. Not sliced; scale uniformly. Window rect (x, y, w, h) = 143, 174, 353, 74. Blank label rect = 44, 45, 551, 252 (clear writing band y 60..160). |
| `cassette_shell_red/yellow/blue/green.png` | 640x410 | – | – | – | – | Same shell with the label tinted to the four tape colours. |
| `cassette_reel.png` | 256x256 | – | – | – | – | Tape pack + hub, pivot (128, 128), six-fold symmetric. Draw **behind** the shell, clipped to the window rect, centred on (228, 211) and (411, 211) in shell pixels. Scale 0.45..0.8 to show how much tape is on each side; rotate for transport. |
| `cassette_hub.png` | 134x134 | – | – | – | – | Hub only, same pixel scale as the reel (radius 65), pivot (67, 67). At 0.5 scale it fits the window height. |

Draw order for a cassette: card panel, reels (clipped to the window), shell, label text.

## doll/ — loadout paper doll (transparent RGBA, all 480x880 = 2 x `MenuArt.DOLL_BOX`)

| file | use |
|---|---|
| `moxie_doll.png` | Flat cut-paper Moxie, front view, A-pose (follows `docs/reference/generated/moxie_front.png`). |
| `moxie_doll_silhouette.png` | Same outline as a charcoal silhouette with a paper die-cut edge (locked or empty state). |
| `moxie_doll_regions.png` | Region id map, one flat colour per slot. For picking, sample the pixel under the cursor. |
| `region_head`, `region_torso`, `region_legs`, `region_feet`, `region_right_hand`, `region_left_wrist` `.png` | White mask of one region on the full canvas: overlay with `modulate` set to the accent colour at about 0.5 alpha to highlight the hovered slot. |
| `moxie_doll_regions.json` | Per region: id, map colour, bounding `rect` [x, y, w, h] and label `anchor` [x, y] in canvas pixels. |

Regions (x, y, w x h in canvas px): head 108, 33, 265x157 · torso 79, 190, 320x182 · legs 112, 345,
239x367 · feet 130, 712, 212x134 · right_hand (screen left) 9, 332, 93x114 · left_wrist (screen right)
378, 330, 94x117.

## Checked

`verify_all.py` passes on all 48 PNGs: exact sizes, RGB for paintings, RGBA with transparent canvas
corners for cut-outs, slice margins inside the texture, and the stretch bands of every sliced piece
are pixel-constant. Everything was looked at on dark, on magenta and over the kit dioramas:
`art/ui_art/sheets/contact_sheet.png`, `contact_alpha_magenta.png`, `ui_stretch_dark.png`,
`ui_stretch_busy.png`, `mock_title.png`, `mock_hud_busy.png`.

## Known shortfalls

- The doll follows the generated model sheet (twin ponytails); the key art follows R01 (single side ponytail).
- Doll regions are cut with straight boxes over the figure, not hand-traced; the torso/legs split at the belt is approximate.
- `title_1600x900.png` gets its extra left 250 px from a mirrored blur: fine under a menu, not as bare art.
- Chapter 2 sits close to chapter 1 in layout (staircase and awning again, darker and enclosed).
- Hover, pressed and disabled buttons are derived from the normal one in code (recolour and shift), not separately drawn.
- The cassette window is small (74 px tall at 640 wide), so the reels read as two partial discs. There is no glass-glare layer.
- Logos are raster only; the largest masters are about 2100 px wide.
- Nothing is wired into `ui/hud` or `ui/menus` yet; those still draw procedurally.
