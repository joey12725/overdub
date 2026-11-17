# Generated model sheets — Moxie

Production model sheets of Moxie, generated with the image model (`bash tools/img edit`, gpt-image-2.6-sunburst) from
`docs/reference/R01-moxie-concept.png` (R01 wins on palette: dark jacket with yellow lining, light crop top, triangle
mark on the headphones) with `R02-moxie-sheet.png` as the turnaround guide. The front view was generated first and
passed as an input to every later view. Flat mid-grey background, even lighting, no cast shadows.

Made by candidate E (`art/moxie_e/`, scripts `sheet_tools.py`, `gen_sheets_batch2.sh`, `s9_finalize.py`). Any artist
may use them. The `wardrobe/` and `weapons/` folders here belong to other artists.

## Body (A-pose, 1152x1536, figure 1400 px tall = 1.6 m, feet on row 1480)

All five A-pose views are normalised to the same canvas: head-to-toe height 1400 px, feet on row 1480, body axis on
column 576 in the front/back views. 1 px = 1.143 mm.

| File | View |
|---|---|
| `moxie_front.png` | strict orthographic front, A-pose (arms ~35-40 degrees from the body, palms down) |
| `moxie_back.png` | back |
| `moxie_left.png` | her left side (she faces the left of the picture) |
| `moxie_right.png` | her right side |
| `moxie_threequarter.png` | three-quarter front |
| `moxie_threequarter_back.png` | three-quarter back (not normalised to the canvas) |
| `moxie_tpose_front.png` | T-pose, front |
| `moxie_tpose_back.png` | T-pose, back (raw 1672x941, not normalised) |
| `moxie_turnaround_sheet.png` | front / three-quarter / left / back / right side by side |
| `cut/moxie_*.png` | the same normalised views with the background removed (RGBA) — these are what the 3D pipeline reads |
| `consistency_overlay.png` | silhouette overlay used for the consistency check below |

Consistency check (`python art/moxie_e/sheet_tools.py check`, silhouettes compared after mirroring):
front vs back IoU 0.894, left vs right IoU 0.818; row-width profile correlation 0.993 (front/back) and 0.987
(left/right). Heights agree by construction (normalised). The remaining disagreement is hair spikes, the hanging
straps, and the left/right sleeves (her right sleeve carries the chevrons).

## Head (`head/`, 1536x1024 each, all drawn at the same scale and position)

| File | View |
|---|---|
| `moxie_head_front.png` | orthographic front, neutral |
| `moxie_head_left.png` | left profile, neutral |
| `moxie_head_threequarter.png` | three-quarter, neutral |
| `moxie_head_back.png` | back |
| `moxie_head_grin_front.png`, `moxie_head_grin_left.png`, `moxie_head_grin_threequarter.png` | her grin |
| `moxie_head_hairback_front.png`, `moxie_head_hairback_left.png` | FACE-SHAPE variant: headphones removed and the hair pulled flat off the face, so the cranium, cheekbones, jaw, chin, ears and neck outline are unobstructed. Registered pixel-for-pixel with the neutral front / left views (same eyes, same chin). Use these to model or check the face shape. |
| `moxie_hair_study.png` | hair only on a blank head: front, three-quarter, side, back |
| `moxie_head_sheet.png` | all of the above tiled |

Head sheet to body sheet: head pixel (u, v) maps to body-sheet pixel (341 + u / 3.26, 75 + v / 3.26); 1 head px = 0.351 mm.

## Gear (`gear/`)

| File | Content |
|---|---|
| `moxie_gear_headphones_walkman.png` | headphones (front, side, three-quarter) and the belt Walkman (front, side, back) |
| `moxie_gear_wearables.png` | wrist device (top, side), headphones, jacket, belt rig, pants, boots. This one carries printed labels (the model added them; they are spelled correctly). |

## Known inconsistencies between views

- The yellow triangle hair clip is on her RIGHT side (front view). The left-profile head sheet also shows one on her left.
- The front and back sheets draw the headphone cups slightly turned, so a triangle mark is visible from the front and the back as well as from the side.
- Belt gear differs in small details between views (count of cartridges, strap buckles). The front view is the reference.
- `work/` holds every raw generation (rejected takes included), the crops of R01/R02 used as inputs, and gridded copies used for picking joint landmarks.
