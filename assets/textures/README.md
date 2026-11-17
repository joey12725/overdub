# assets/textures - world art

Painted 2D art the 3D kit cannot give: graffiti, floor decals and signage, rune glyphs, background plates and tape art.
This file covers `graffiti/`, `decals/`, `backdrops/` and `tape/` (`patterns/` and `wardrobe/` belong to other owners).
It is written by `art/world_art/readme.py`; do not edit it by hand.

Source of record: `art/world_art/jobs.py` holds every prompt (model gpt-image-2.6-sunburst through `tools/img`);
`art/world_art/process.py` trims, pads, checks alpha, exports, and builds the contact sheets in `art/world_art/contact/`
(each set on warm stone and on dark metal). Raw model output is in `art/world_art/raw/`, rejected takes in
`raw/_rejected/`. To add or redo a piece: add or change its job, delete its raw file, then run
`python -I art/world_art/jobs.py <name>`, then `process.py`, then `readme.py`.

Conventions for everything with alpha: straight (not premultiplied) alpha, the subject trimmed and centred on a fixed
canvas with a clear margin, and the colour of fully transparent pixels bled outward from the paint so filtering and
mipmaps do not pull in a fringe. Import with mipmaps on and repeat off.

## graffiti/ (71 pieces, 768x768, alpha)

Spray paint on transparent. Project with a `Decal` using albedo only, so it takes the surface's cel lighting (ART-03:
it is paint, not light - do not make it emissive). `world/world_graffiti.gd` already finds these: a decor's `variant`
is lower-cased and stripped to letters and digits, and a file whose name matches the same way replaces the procedural
tag (`"ROLL TAPE"` -> `roll_tape.png`, `"+1"` -> `1.png`, `"3/4"` -> `34.png`, `"A/B"` -> `ab.png`,
`"5 6 7 8"` -> `5678.png`). An empty variant picks any file here from the seed. A piece does not fill its square:
wide tags sit in a horizontal band, so size the decal by its width.

Level variants with no painted file (they fall back to the procedural tag): `<<`.

| file | size | use |
|---|---|---|
| `graffiti/1.png` | 768x768 alpha | level tag, variant `+1` (level 04) |
| `graffiti/1_bar_2_bar.png` | 768x768 alpha | level tag, variant `1 BAR 2 BAR` (level 08) |
| `graffiti/2_keys.png` | 768x768 alpha | level tag, variant `2 KEYS` (level 05) |
| `graffiti/2_of_me.png` | 768x768 alpha | level tag, variant `2 OF ME` (level 03) |
| `graffiti/34.png` | 768x768 alpha | level tag, variant `3/4` (level 11) |
| `graffiti/5.png` | 768x768 alpha | level tag, variant `5` (level 10) |
| `graffiti/5678.png` | 768x768 alpha | count-in tag 5-6-7-8! - also level variant `5 6 7 8` |
| `graffiti/ab.png` | 768x768 alpha | level tag, variant `A/B` (level 10) |
| `graffiti/after_you.png` | 768x768 alpha | level tag, variant `AFTER YOU` (level 03) |
| `graffiti/again.png` | 768x768 alpha | scrawl AGAIN! |
| `graffiti/again_again.png` | 768x768 alpha | level tag, variant `AGAIN AGAIN` (level 08) |
| `graffiti/amp.png` | 768x768 alpha | level tag, variant `AMP` (level 06) |
| `graffiti/arrow.png` | 768x768 alpha | arrow pointing right (rotate the decal to aim it) |
| `graffiti/arrow_down.png` | 768x768 alpha | arrow pointing down with chevrons |
| `graffiti/ask_twice.png` | 768x768 alpha | level tag, variant `ASK TWICE` (level 04) |
| `graffiti/bolt.png` | 768x768 alpha | lightning bolt |
| `graffiti/boombox.png` | 768x768 alpha | boombox |
| `graffiti/cassette.png` | 768x768 alpha | cassette |
| `graffiti/crown.png` | 768x768 alpha | crowned headphones, yellow |
| `graffiti/dead_air.png` | 768x768 alpha | level tag, variant `DEAD AIR` (level 05) |
| `graffiti/dock.png` | 768x768 alpha | level tag, variant `DOCK` (level 06) |
| `graffiti/down.png` | 768x768 alpha | level tag, variant `DOWN` (level 09) |
| `graffiti/dub.png` | 768x768 alpha | bubble tag |
| `graffiti/far_one_first.png` | 768x768 alpha | level tag, variant `FAR ONE FIRST` (level 06) |
| `graffiti/flat_rate.png` | 768x768 alpha | level tag, variant `FLAT RATE` (level 10) |
| `graffiti/ghost.png` | 768x768 alpha | ghost with echo outline (ghost takes) |
| `graffiti/ghost_me.png` | 768x768 alpha | level tag, variant `GHOST ME` (level 07) |
| `graffiti/headphones.png` | 768x768 alpha | headphones with cable |
| `graffiti/heart.png` | 768x768 alpha | dripping heart |
| `graffiti/hiss.png` | 768x768 alpha | tag with static squiggle |
| `graffiti/hot_side.png` | 768x768 alpha | level tag, variant `HOT SIDE` (level 09) |
| `graffiti/keep_it.png` | 768x768 alpha | level tag, variant `KEEP IT` (level 12) |
| `graffiti/kept.png` | 768x768 alpha | level tag, variant `KEPT` (level 11) |
| `graffiti/list_only.png` | 768x768 alpha | level tag, variant `LIST ONLY` (level 04) |
| `graffiti/long_way.png` | 768x768 alpha | level tag, variant `LONG WAY` (level 03) |
| `graffiti/look_away.png` | 768x768 alpha | level tag, variant `LOOK AWAY` (level 11) |
| `graffiti/loop.png` | 768x768 alpha | tag with loop arrow |
| `graffiti/loud.png` | 768x768 alpha | tag with shout lines - also level variant `LOUD` |
| `graffiti/mains.png` | 768x768 alpha | level tag, variant `MAINS` (level 07) |
| `graffiti/mind_the_teeth.png` | 768x768 alpha | level tag, variant `MIND THE TEETH` (level 08) |
| `graffiti/mind_yr_head.png` | 768x768 alpha | level tag, variant `MIND YR HEAD` (level 10) |
| `graffiti/mox.png` | 768x768 alpha | Moxie's signature tag (R03/R04) - also level variant `MOX` |
| `graffiti/moxie_was_here.png` | 768x768 alpha | scrawl, two lines |
| `graffiti/no_skips.png` | 768x768 alpha | scrawl |
| `graffiti/off_air.png` | 768x768 alpha | level tag, variant `OFF AIR` (level 07) |
| `graffiti/on_air.png` | 768x768 alpha | level tag, variant `ON AIR` (level 05) |
| `graffiti/on_file.png` | 768x768 alpha | level tag, variant `ON FILE` (level 11) |
| `graffiti/one.png` | 768x768 alpha | level tag, variant `ONE` (level 12) |
| `graffiti/overdub.png` | 768x768 alpha | title tag with crown |
| `graffiti/play.png` | 768x768 alpha | tag with play triangle |
| `graffiti/rec.png` | 768x768 alpha | tag with record dot - also level variant `REC` |
| `graffiti/reel.png` | 768x768 alpha | tape reel unspooling |
| `graffiti/rewind.png` | 768x768 alpha | tag with rewind triangles |
| `graffiti/roll_tape.png` | 768x768 alpha | level tag, variant `ROLL TAPE` (level 12) |
| `graffiti/run_it.png` | 768x768 alpha | level tag, variant `RUN IT` (level 02) |
| `graffiti/side_b.png` | 768x768 alpha | tag |
| `graffiti/skull.png` | 768x768 alpha | skull in headphones |
| `graffiti/smiley.png` | 768x768 alpha | the X-eyed smiley (R03/R04), pink |
| `graffiti/smiley_violet.png` | 768x768 alpha | X-eyed smiley, tongue out, violet |
| `graffiti/splat.png` | 768x768 alpha | plain paint burst, no drawing (filler, layering) |
| `graffiti/star.png` | 768x768 alpha | scribble star, pink |
| `graffiti/star_yellow.png` | 768x768 alpha | scribble star with small stars, yellow |
| `graffiti/take_4.png` | 768x768 alpha | tag, circled 4 |
| `graffiti/tally.png` | 768x768 alpha | tally of five (counting takes) |
| `graffiti/three.png` | 768x768 alpha | level tag, variant `THREE` (level 12) |
| `graffiti/two.png` | 768x768 alpha | level tag, variant `TWO` (level 12) |
| `graffiti/wait_4_ur_spark.png` | 768x768 alpha | level tag, variant `WAIT 4 UR SPARK` (level 07) |
| `graffiti/warning.png` | 768x768 alpha | hand-drawn warning triangle |
| `graffiti/wave.png` | 768x768 alpha | audio waveform |
| `graffiti/x.png` | 768x768 alpha | circled X (marks a spot) |
| `graffiti/x2.png` | 768x768 alpha | level tag, variant `x2` (level 02) |

## decals/ (24 pieces, alpha)

Floor markings and overlays for the ruins' technology, drawn straight top-down. Square pieces are 512x512, wide pieces
1024x512, bands 1024x256. The two bands run off the left and right edges so they can be butted end to end; they are not
seamless tiles, so overlap them or alternate flips. Coloured pieces are final colour; the bay rings A-D are white so
the game tints them with the tape colour. Moss, leaves and cracks suit the upper and mid themes; scorches go anywhere.

| file | size | use |
|---|---|---|
| `decals/bay_01.png` | 512x512 alpha | numbered bay marking |
| `decals/bay_02.png` | 512x512 alpha | numbered bay marking |
| `decals/bay_03.png` | 512x512 alpha | numbered bay marking |
| `decals/bay_04.png` | 512x512 alpha | numbered bay marking |
| `decals/bay_a.png` | 512x512 alpha | tape bay ring A, WHITE: tint #ff4d6d |
| `decals/bay_b.png` | 512x512 alpha | tape bay ring B, WHITE: tint #ffd23f |
| `decals/bay_c.png` | 512x512 alpha | tape bay ring C, WHITE: tint #3ec5ff |
| `decals/bay_d.png` | 512x512 alpha | tape bay ring D, WHITE: tint #7dff6b |
| `decals/crack_a.png` | 512x512 alpha | branching crack, dark ink lines |
| `decals/crack_b.png` | 512x512 alpha | impact crack, spiderweb |
| `decals/do_not_stand.png` | 512x512 alpha | no-standing stencil for trap tiles (crossed boots, no lettering) |
| `decals/exit.png` | 1024x512 alpha | EXIT stencil with arrow, signal green (exit pad approach) |
| `decals/hazard_chevrons.png` | 1024x512 alpha | row of five chevrons pointing right (conveyors, movers, direction of travel) |
| `decals/hazard_stripe.png` | 1024x256 alpha | yellow/black hazard band, edge to edge horizontally (platform lips, door sills) |
| `decals/keep_clear.png` | 512x512 alpha | KEEP CLEAR trap stencil (crushers, laser lanes) |
| `decals/lane_arrow.png` | 512x512 alpha | straight lane arrow, points up; rotate the decal |
| `decals/lane_arrow_turn.png` | 512x512 alpha | lane arrow turning right |
| `decals/leaves.png` | 512x512 alpha | scatter of fallen leaves |
| `decals/moss_a.png` | 512x512 alpha | moss clump overlay (upper / mid floors and wall bases) |
| `decals/moss_b.png` | 1024x512 alpha | moss along a seam, horizontal |
| `decals/scorch_a.png` | 512x512 alpha | round blast scorch (soft alpha) |
| `decals/scorch_b.png` | 1024x512 alpha | long burn streak (laser drag) |
| `decals/worn_line.png` | 1024x256 alpha | worn off-white boundary line, edge to edge |
| `decals/worn_paint_yellow.png` | 512x512 alpha | worn-away yellow paint patch (ageing over any floor) |

## decals/runes/ (7 sheets, plus 40 single glyphs)

An invented angular alphabet, pure white on transparent with the shape in alpha: tint with the albedo / modulate colour
and drive emission from the same texture to make it glow (cyan, magenta or violet in the lower themes; a dark carved
tint or yellow paint in the upper ones). `glyphs/rune_00.png` to `rune_39.png` are the forty glyphs, one per 128x128
file, in atlas order; `process.py` checks that no two overlap by more than 72 percent, mirrored or not.
`musicviz/mv_glyphs.gd` falls back to procedural glyphs when no sheet is found here.

| file | size | use |
|---|---|---|
| `decals/runes/rune_glyphs_atlas.png` | 1024x640 alpha | the forty glyphs, 8 x 5 cells of 128 px (glyph i = column i % 8, row i // 8); see rune_glyphs_atlas.json |
| `decals/runes/rune_ring.png` | 512x512 alpha | sixteen glyphs round a double ring (floor seal, exit pad, core floor) |
| `decals/runes/rune_strip_h_01.png` | 1024x128 alpha | eight glyphs between rails, horizontal (wall bands, console fascias) |
| `decals/runes/rune_strip_h_02.png` | 1024x128 alpha | as above, different text |
| `decals/runes/rune_strip_h_03.png` | 1024x128 alpha | as above, different text |
| `decals/runes/rune_strip_v_01.png` | 128x1024 alpha | eight glyphs between rails, vertical (pillars, door jambs) |
| `decals/runes/rune_strip_v_02.png` | 128x1024 alpha | as above, different text |

## backdrops/ (4 plates, 1536x1024, opaque)

One soft, low-contrast plate per depth theme. `world/world_view.gd` loads `backdrops/<theme>.png` behind the diorama
by itself. The centre is kept calm and detail sits at the edges. `art/world_art/contact/backdrop_test_<theme>.png`
shows each one behind a kit diorama.

| file | size | use |
|---|---|---|
| `backdrops/core.png` | 1536x1024 opaque | theme `core` (level 12): the time-machine chamber, soft violet core glow |
| `backdrops/lower.png` | 1536x1024 opaque | theme `lower` (levels 08-11): near-black depths, faint distant neon and runes |
| `backdrops/mid.png` | 1536x1024 opaque | theme `mid` (levels 05-07): machine well, light shafts into teal-violet gloom |
| `backdrops/upper.png` | 1536x1024 opaque | theme `upper` (levels 01-04): golden sky through broken vaults, distant overgrown ruins |

## tape/ (8 pieces) and tape/stickers/ (9 pieces)

J-cards are 1024x1536 opaque covers for the four tapes (tape select, pause and results screens, the tape rack). Labels
are 1024x640 with alpha, to sit on a cassette shell in the HUD. Stickers are 1024x512 with alpha, die-cut with a white
border, for HUD states and hit / sync effects (pop them in with a little rotation and scale).

| file | size | use |
|---|---|---|
| `tape/jcard_a.png` | 1024x1536 opaque | J-card cover with Moxie, tape A #ff4d6d |
| `tape/jcard_b.png` | 1024x1536 opaque | J-card cover with Moxie, tape B #ffd23f |
| `tape/jcard_c.png` | 1024x1536 opaque | J-card cover with Moxie, tape C #3ec5ff |
| `tape/jcard_d.png` | 1024x1536 opaque | J-card cover with Moxie, tape D #7dff6b |
| `tape/label_a.png` | 1024x640 alpha | cassette shell label A (the window cut-out is transparent) |
| `tape/label_b.png` | 1024x640 alpha | cassette shell label B |
| `tape/label_c.png` | 1024x640 alpha | cassette shell label C |
| `tape/label_d.png` | 1024x640 alpha | cassette shell label D |

| file | size | use |
|---|---|---|
| `tape/stickers/5678.png` | 1024x512 alpha | 5 6 7 8 count-in in the four tape colours |
| `tape/stickers/clang.png` | 1024x512 alpha | CLANG! impact burst (parry / block effect) |
| `tape/stickers/commit.png` | 1024x512 alpha | COMMIT with tick |
| `tape/stickers/desync.png` | 1024x512 alpha | DESYNC, glitch-split |
| `tape/stickers/rec.png` | 1024x512 alpha | REC with record dot (recording state) |
| `tape/stickers/resync.png` | 1024x512 alpha | RESYNC with lock-in ticks |
| `tape/stickers/retry.png` | 1024x512 alpha | RETRY with loop arrow |
| `tape/stickers/take.png` | 1024x512 alpha | TAKE (put the take number beside it in the HUD font) |
| `tape/stickers/wipe.png` | 1024x512 alpha | WIPE with smear (erase a take) |
