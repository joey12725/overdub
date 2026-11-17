# Enemy family style: "ruin-security machines"

Every enemy in OVERDUB belongs to one family: **ancient security mechanisms of the ruins**, built
long ago from rune-inscribed dark metal and stone-like ceramic plating, later **retrofitted with
cassette-era music and time technology** — tape reels, record/playback heads, capstans, speaker
cones, VU meters, patch cables. They are machines, never people and never police: no faces, no
uniforms, no badges, no human hands or human posture. Each one has **exactly one glowing eye /
sensor**, which is where the player looks to read its state.

This file is the shared brief for everyone modelling enemies (`art/enemies/*.py`). Follow it; if
you need something it does not cover, extend it here rather than inventing locally.

## Shape language

- **Old shell, new guts.** The outer mass is heavy, chamfered ceramic/stone plating (big simple
  planes, generous bevels, a few cracks/chips cut as geometry) over dark inscribed metal. The
  retrofit is visibly *added on*: reels bolted to flanks, cables looping between parts, a speaker
  cone set into a chest, a tape head where a face would be. The silhouette must show both layers.
- **One eye.** A single emissive sensor (`eye_glow`) set in a dark metal socket so it reads as a dot
  of hot orange at game scale. Never two eyes, never a mouth.
- **Hazard markings** are the service paint of whoever retrofitted them: yellow/black diagonal
  bands (`hazard` + `hazard_dark`) modelled as split faces, on the parts that hurt (barrels,
  hammers, blades) and on service panels. They mark *danger zones*, so keep them off harmless parts.
- **Runes** are inlaid glowing grooves (`rune_glow`) cut into ceramic and metal — sparse lines and
  angular glyphs integrated with the panel seams, not stickers.
- **Read at 50–80 px per tile.** The game camera is orthographic, yaw 45°, pitch ~35°. Judge every
  model by its silhouette at that angle and size first: one dominant feature per type (turret =
  long barrel, brute = giant hammer arm, boss = tape reels and screen halo, …). Details are
  geometry, not texture: the game shades flat base colours with a toon ramp and ink outlines.
- **Proportions:** chunky, slightly top-heavy, low centre of mass for walkers, wide stances. Moxie
  is 1.6 tall; grunt ~1.3, stalker ~1.4 (to the tail tip; body ~0.9, low and forward-pitched),
  shielder ~1.45 (periscope eye over a ~1.2 shield), drone ~0.6 across hovering at ~1.2 (top
  ~1.45), turret ~1.1, brute ~2.0, boss ~3.2 (3×3 tile footprint).
- **Dominant feature per type (as built):** grunt = upright hazard-capped mallet carried in front +
  speaker chest; stalker = two long scythe blades held low in front + scorpion cable tail;
  shielder = curved door-slab shield with a speaker cone and teal projector ring; drone = big
  windowed tape reel on top + ducted rotor ring + emitter horn slung underneath.

## Palette and material vocabulary

Materials are named by part/role; the game styles by name (shader swap, tint, glow, recolour).
Emissive parts end in `_glow`. Use these names wherever the role matches so the game can treat the
family uniformly; add type-specific names only for genuinely new roles.

| Material | Base colour | Role |
|---|---|---|
| `ceramic` | `#c8bba3` | stone-like outer plating (main mass) |
| `ceramic_dark` | `#8f8270` | secondary plating, feet, plinths, weathered panels |
| `metal` | `#3a3744` | dark rune-inscribed metal frame/joints (slight violet, matches lower levels) |
| `metal_light` | `#6a6674` | pistons, axles, barrels, bolts |
| `brass` | `#c9962f` | retrofit hardware: bands, clamps, reel flanges, rims |
| `hazard` | `#ffbf1a` | hazard paint (yellow band) |
| `hazard_dark` | `#1e1c22` | hazard paint (black band) |
| `cable` | `#24222a` | patch cables, hoses, rubber |
| `tape` | `#4a2f1e` | magnetic tape (brown) on reels and strands |
| `speaker` | `#2c2a33` | speaker cones, grilles |
| `screen` | `#1b2a2e` | dead screen glass / bezels |
| `eye_glow` | `#ff6a1a` | THE single sensor; hot orange = enemy/danger hue, distinct from all four cassette colours. The game recolours it by state (telegraph white-hot, memory = tape colour for the boss). |
| `rune_glow` | `#58f0dc` | inlaid rune grooves (teal) |
| `meter_glow` | `#ffd04a` | VU meters, small indicator lamps (amber) |

Type-specific materials used so far: `blade` (`#d9dde4`, the stalker's bright steel scythe
blades), `shield_glow` (`#7ff4ff`, the shielder's projector ring on the `Shield` mesh).
Type-specific glow materials used so far: `charge_glow` (`#ff8a3a`, the telegraph charge part on
the `charge` bone of grunt/stalker/drone; turret muzzle charge), `core_glow`
(boss core behind its armour), `screen_glow` (boss memory screens). Keep the cassette colours
(`#ff4d6d`, `#ffd23f`, `#3ec5ff`, `#7dff6b`) out of enemy materials except where the game tints at
runtime.

## Rig and animation conventions

- Export contract: `docs/GODOT-PORT.md` (glb, metres = tiles, origin on the floor at the footprint
  centre, facing **+Z in Godot = −Y in Blender**). Armature object named `Rig`, a `root` bone at the
  origin. Mechanical parts are skinned rigidly (one bone per rigid part, weight 1.0); only soft
  parts (cables, bellows, tape strands) get blended weights, so plates never smear.
- Actions: `idle` (loop), `move` (loop; stationary types do a subtle scan), `telegraph` (1.0 s wind-up,
  scrubbed by the game with state progress, so it must read at every intermediate frame and end
  in the "about to strike" pose), `attack` (1.0 s: strike in the first ~30 %, recovery after),
  `stagger` (1.0 s, settles back to neutral), `death` (1.0 s, ends in a held collapsed pose). Loops
  start and end on the same pose. 30 fps.
- Bones the game drives directly (e.g. `aim`) are never keyed in any action, so a game-side rotation
  is never overwritten by the AnimationPlayer. Their rest pose points straight up (+Y in Godot), so
  yaw is a rotation about the bone's local Y.
- Telegraphs must be readable without colour: a big pose change (raise, coil, open, extend) plus a
  geometry "charge" (a glow part scaling up on its own bone), because material animation is not
  exported. Convention: that bone is named `charge` (grunt: ring on the mallet head; stalker:
  stinger tip; shielder: projector ring, inside `Shield`; drone: glow in the emitter horn).
- The eye lens sits on its own `eye` bone: `stagger` flickers it (scale) and `death` shrinks it to
  ~0, so the sensor visibly powers down even without material animation.
- The glTF exporter's forced sampling bakes EVERY bone into every action, including unkeyed ones;
  `common.export_glb()` therefore strips the channels of `common.GAME_DRIVEN_BONES` (`aim`) from
  the written .glb. Anyone exporting an `aim` bone another way must do the same.
- Bones named `reel.L` / `reel.R` are also game-driven *in addition to* their keys:
  `actors/enemy_view.gd` multiplies a continuous spin about the bone's **local X** onto them (the
  boss rewinds them hard during memory recall). Build them with the reel's axle along local X
  (`common2.AXLE_X_PREFIX` does this for turret/brute/boss) and key their own spin about X, or
  the game's spin makes the reel tumble off its axle.
- `death` ends with every part resting on the floor plane (Y ≈ 0, checked numerically), and parts
  may separate (heads, reels and shields drop off on their own bones).

## Sources and previews

Each type is one script `art/enemies/<type>.py` (shared helpers in the `common*.py` modules) that
rebuilds the model from nothing and exports `assets/models/enemies/<type>.glb`; previews go to
`art/previews/enemies/<type>/` (git-ignored).

`common.py` holds the shared toolkit (palette materials, bmesh part builders with
bevel/subdivision/solidify/mirror/boolean modifiers applied at bind, `bind()` = automatic weights +
rigid/soft corrective pass, the `Anim` key DSL in armature axes, `export_glb()`, Workbench preview
renders: turnaround, iso, 100/160 px thumbnails, iso/side contact sheets). Type scripts call
`common.run("<type>", build)`. Checks from outside Blender: `python art/enemies/common_check_glb.py
[type ...]` (contract checker: bones, materials, animation lengths and loop closure, `aim` never
animated, single front-facing eye, floor origin, weights, triangle budget, `reel.L`/`reel.R` axle on
local X, `telegraph` starting on the rest pose and `attack` starting on the telegraph's end pose).
Family line-up against a 1.6-unit banded scale bar (Moxie's height; a measuring staff, not a figure,
so it is never mistaken for a character): `blender -b --python art/enemies/common_lineup.py --
[type ...]` → `art/previews/enemies/lineup_family_{front,iso,iso_small}.png` (turret/brute/boss
line-up: `common2_lineup.py` → `lineup_{front,iso}.png`; pass all seven types to `common_lineup.py`
for the whole family in one image).

Quality-pass conventions for grunt/stalker/shielder/drone (`common.py`):

- **Smoothness floor.** Round forms are built with at least `ROUND_MIN` (24) segments (cylinders,
  lathes; tori 32×8; cables 12-sided), smooth-shaded with a 40° sharp angle. Counts of 8 or fewer
  are deliberate polygons (hex bolts/hubs, the shielder's octagonal pillar) and stay faceted.
- **Nothing thinner than ~0.03 across** (posts, pins, antennae, struts): thinner parts vanish or
  shimmer at 50–80 px per tile.
- **One-shots start on the rest pose.** In `Anim`, a bone whose first key is late starts from rest
  in a one-shot (loops wrap onto their first key), so `telegraph` builds from neutral when scrubbed.
- **Telegraph strip.** Each type's previews include `<type>_telegraph.png`: the wind-up at
  0/0.2/0.4/0.6/0.8/1.0 over the first frames of the attack, isometric, 400 px tiles — judge the
  wind-up there. `python art/enemies/common_before_after.py` composes
  `<type>/before_after.png` from `<type>/before/` (the preview set kept from before a pass).
