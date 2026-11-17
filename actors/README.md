# actors/ — everything alive on screen

`actor_layer.gd` is the `ActorLayerBase` implementation that `Facades.instance_actor_layer()` loads.
The world view drives it: `load_level(ctx)` once per level, `update(frame, ctx)` every rendered
frame, `self_anchor(tape, frame)` for camera framing and fx.

| File | What |
|---|---|
| `actor_layer.gd` | the layer: four `SelfView`s, pooled `EnemyView`s and `ProjectileView`s, shared particles |
| `self_view.gd` | one self: Moxie, pose, state style, identity markers, gear, afterimages, swing trail, spark / tether / merge flash |
| `moxie_model.gd` | `MoxieModel`: what the code relies on in the Moxie model (bone names, clip binding, foot planting and smear arcs of the retargeted library, outfit zones, headgear seating, ranged-weapon frame, headphone glow) |
| `actor_options.gd` | `ActorOptions`: the readability options the layer honours (cassette colour set, high contrast, patterns, reduce flashing); the game calls `ActorOptions.apply_settings(settings)` |
| `enemy_view.gd`, `enemy_specs.gd` | one enemy and its readability layer (telegraph decal, aim, target line, pips, stagger, death, boss memory) |
| `projectile_view.gd` | one projectile per archetype, coloured by owner |
| `actor_rig.gd`, `clip_sampler.gd` | a model instance with exact clip sampling (seek, never playback) and the actor materials |
| `actor_interp.gd`, `actor_style.gd`, `moxie_anim.gd` | pure logic: interpolation, the state → style table, animation progress (tested in `tests/actors/`) |
| `actor_materials.gd`, `shaders/` | the actor shaders (cel body, ink hull, x-ray, hologram / phase / hollow twins, trails, flat markers) |
| `*_standin.gd`, `moxie_pose.gd`, `rig_builder.gd`, `actor_gear.gd` | clearly-temporary stand-ins used only while a model file is missing; built-in headgear shapes for helmets the wardrobe has no model for |

## Moxie

- Model `res://assets/models/moxie.glb`, any `Skeleton3D` inside it, bones by Godot's humanoid
  names (`RightHand`, `LeftHand`, `LeftLowerArm`, `UpperChest`, `Head`); the stand-in's names are
  fallbacks.
- Clips: the animation director's library (`FeelRig.LIBRARY_PATH`, 29 clips) is the one in use.
  It is baked onto her skeleton once per process (about 70 ms, cached) by `MoxieModel.feel_library`:
  `FeelRetarget.bake_library`, then `ground_feet` (lifts the hips per key so the lower ankle keeps
  the source clip's height above the floor: the bare retarget left her feet 1-3 cm under it
  whenever the knees bent) and `measure_arcs` (rewrites each swing's grip-arc metadata with the
  frame the weapon really has in her hand, so the smear sits on the real striking edge).
  `res://assets/anim/moxie_anims.res` and the .glb's own clips only fill in for a name the library
  lacks. `SelfView.clip_for(anim)` says which clip plays a state.
- Flavour clips have no anim state: `resync` plays for half a second when a desynced self merges,
  `win` when the objective is complete in the cinematic replay, `countin` while
  `actor_layer.set_flavour(SelfView.FLAVOUR_COUNTIN)` is set (the game sets it during the count-in
  and clears it with `&""`). They only ever replace idle on a living, synced self.
- Look: the model is one painted `body` and one `head` texture, so the cel ramp is gentle on
  textured materials (`ActorMaterials.TEXTURED_CEL_SOFT`) and her colours stay hers.
- Gear: melee weapon on `RightHand` in `FeelRig.weapon_attach_transform`'s grip frame (gauntlets on
  both fists), stowed on `UpperChest` between swings; ranged weapon on `LeftLowerArm`
  (`MoxieModel.ranged_attach_transform`), hiding the model's own wrist device; headgear from
  `Wardrobe.attach_headgear` fitted by `Wardrobe.head_fit`, then `MoxieModel.seat_headgear` (brow
  gear is tipped back on this head so a brim does not cover her face from the gameplay camera).
- Outfit: tops, pants and shoes recolour OUTFIT ZONES of the body texture
  (`MoxieModel.outfit_zones`, masks from `tools/moxie_regions.py`; docs/WARDROBE.md "Looks on a
  textured body"). The base loadout is the painted model and recolours nothing.
- Identity: a two-tier outline (thin ink line, then a wider hull in the cassette colour:
  `actor_ink.gdshader` -> `actor_outline.gdshader`), the floor ring in the cassette's own SHAPE
  (circle / triangle / square / plus, `AccessKit.ring_mesh`) over an ink backing, the letter badge
  and the headphone glow rings. Colours are `AccessKit.colors(ActorOptions.cassette_set)`. Never
  the outfit.

## Combat feel

The layer owns one `CombatFeel` (`actor_layer.feel`, docs/COMBAT-FEEL.md). Each frame, before any
body is posed, it is given the frame's sim events and snapshot. Then:

- a self reads `feel.self_fx(tape)`: while a hit is held it is drawn late (the swing clip is read
  back from a short history, so it freezes on the contact frame and catches up, even across a
  state change), its body is squashed / tilted / shuddered, and `feel.update_swing` draws the smear
  from the real weapon arc; the old hit-volume sector steps back to a faint read;
- an enemy reads `feel.enemy_fx(id)`: body drawn late along the knockback, `stagger` clip frozen
  during the hold, squash and tilt, the impact frame through its body shader (white, or the
  inverted frame: ink body, paper-white outline; nothing on a clang);
- tape speed for the per-speed treatment is measured from the playhead (ticks per wall second
  over `frame.world_rate`), snapped to 0.5 / 1 / 2 / 4;
- "reduce flashing" (`ActorOptions.reduce_flashing`): no body flash or inverted frame (a struck
  enemy's outline turns white instead), no camera punch, bursts capped small, no flicker on
  desync / i-frames, weaker chromatic split.

## X-ray

`shaders/actor_xray.gdshader` draws a flat silhouette only where something nearer than the actor's
own volume (a vertical cylinder, `ActorRig.update_xray(world_pos)` every frame) hides it, so her
pigtails behind her face never trigger it while a wall in front of her does.

## Screenshots

`bash tools/gd shot res://tools/shot_actors.gd -- <out_dir> [page ...]` (pages: anims, states,
enemies, enemies2, projectiles, weapons, portrait, closeup, cassettes, headgear, looks, feel,
speeds, clips1..clips5; warm and dark palette each, or add `warm` / `dark` for one).
`bash tools/gd script res://tools/probe_actors.gd` prints foot heights and smear-arc error per clip.
