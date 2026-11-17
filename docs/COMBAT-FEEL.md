# OVERDUB — animation library and combat feel

Owner: animation / combat feel. Code: `feel/**`, `tools/combat_lab.gd`, `tools/combat_lab/**`,
`tests/feel/**`. Art: `art/anim/**` (sources), `assets/anim/library/**` (shipped), previews in
`art/previews/anim/`.

Everything here is **presentation only**. The simulation is deterministic and the music is locked
to it, so nothing in `feel/` pauses, scales or reads a clock, uses randomness, or touches a sim
class (`tests/feel/test_feel_logic.gd` scans the sources for exactly that).

## 1. Principles

1. **Anticipation is reached early and then hangs.** Every attack eases *out* into its wind-up pose
   and holds it, so even the two-tick wind-up of `speaker_knuckles` shows one clean "about to"
   frame. The strike itself is a `snap` (t³ or t⁵): almost all the travel happens in the last
   frames before 0.40.
2. **The contact pose sits exactly at clip fraction 0.40**, weapon on the target line, weight
   already forward. The hit window (0.40–0.60) is overshoot; recovery holds the follow-through for
   a beat before returning to guard.
3. **Hips lead, chest follows, arm and weapon arrive last.** The free arm counter-swings; the head
   stays on the target while the torso winds. Heavies commit the whole body (step-in, deep drop,
   or, for the uppercut, leaving the floor).
4. **Every style has its own line** so silhouettes never repeat from the isometric camera: blade
   slashes right-to-left, shiv jabs down the facing line (heavy: a backhand rip the other way),
   sledge swings from the hips (heavy: overhead smash), whip cracks overhand (heavy: a lasso turn
   first), gauntlet throws a straight (heavy: rising uppercut), glaive sweeps 200° (heavy: a full
   spinning sweep).
5. **Hit-stop is a visual lag, never a pause.** A held body is *drawn late*: frozen at the contact
   frame for `hold` seconds, then caught up over `catch_up` seconds (ease-out). The lag is always
   ≥ 0 and returns to exactly 0. Squash, tilt and jitter live on the held frame.
6. **Momentum is legible at a glance.** Five tiers scale every channel together (hold, flash,
   burst size and line count, shake, punch, squash, tilt, dust). A clang is the odd one out on
   purpose: no white flash, a grey drooping cross and a broken ring that does not expand, and the
   *attacker* holds longer than on a light hit — the weapon stops dead on the target.
7. **Tape speed changes the treatment, not just the rate.** 0.5× holds longer, drags a deep long
   smear with a dark core; 2× and 4× hold shorter, chop the smear into echo blades and throw
   whole-body afterimages through the hit window.
8. **Everything is a pure function of (clip, fraction).** Smears are built from the weapon's real
   arc stored in the clip, so they are exact when scrubbed, at any frame rate, and mirrored when a
   tape plays backwards.

## 2. The animation library

`res://assets/anim/library/moxie_anims.res` — an `AnimationLibrary` of 29 clips on Godot's
`SkeletonProfileHumanoid` bones (tracks `Rig:<Bone>`, rotations in profile reference-pose space,
plus a `Rig:Hips` position track in profile scale, hips rest height 0.75).

| Clip | Length | Notes |
|---|---|---|
| `idle` | 2.0 s loop | four beats at 120 bpm: popped hip, head nod and toe tap on the beat, one breath |
| `run` | 0.6 s loop | two steps, 24° lean, real flight phase, blade trailing; left foot strikes at 0 |
| `stopped` | 1.0 s loop | the held "paused tape" stance (static) |
| `countin` | 1.0 s loop | two beats bouncing in guard |
| `light`, `heavy` | 1.0 s | fallbacks (identical to the blade clips) |
| `light_<style>`, `heavy_<style>` | 1.0 s | `blade, shiv, blunt, whip, gauntlet, polearm` |
| `dodge` | 1.0 s | low scissoring dash that lands in a braking skid |
| `ranged`, `ranged_<archetype>` | 1.0 s | `missile, pierce, phase, arc, burst`; launch at `od_fire` |
| `interact` | 1.0 s | step-in left palm press, contact at 0.50 |
| `death` | 1.0 s | jolt, stagger back, buckle, knees, down |
| `win` | 1.0 s | gather, weapon thrust overhead, held |
| `resync` | 1.0 s | three stepped glitch frames, hard snap wide, settle |

**Melee contract.** Wind-up 0–0.40, hit 0.40–0.60, recovery 0.60–1.0. The game maps state
progress onto those thirds using the weapon's real ticks, so each clip's keys are placed against
its own weapon's ratio (`data/gear.json`, windup/active/recover):

| Style | Item | Light | Heavy |
|---|---|---|---|
| blade | `splice_blade` | 6/4/10 | 16/5/20 |
| shiv | `stylus_shiv` | 3/3/6 | 9/4/12 |
| blunt | `amp_sledge` (two-handed) | 12/5/18 | 28/6/32 |
| whip | `reel_lash` | 9/3/14 | 18/4/22 |
| gauntlet | `speaker_knuckles` (worn, both fists) | 2/3/5 | 7/4/14 |
| polearm | `vinyl_glaive` (two-handed) | 10/6/14 | 20/8/24 |

`gear.json`'s `melee.style` is coarser than this (three items say `blade`); use
`FeelRig.style_for(item_id)` and `FeelRig.melee_clip(heavy, style, has_clip)`, which fall back to
`light` / `heavy`. `FeelRig.ranged_clip(archetype, has_clip)` does the same for ranged.

**Metadata on each `Animation`** (read with `FeelRig.arc_at(anim, frac)`):
`od_grip`, `od_w`, `od_e` (per-frame grip position, weapon +Y direction, edge +Z direction, model
space on the 1.6-unit reference body, hips at `od_hip_height` = 0.84), `od_lgrip` (left palm),
`od_style`, `od_melee`, `od_fire`.

**Sources and rebuild.**

```
python -I art/anim/bake.py                                   # clips.py -> art/anim/baked/moxie_clips.json
bash tools/gd script res://assets/anim/library/build_library.gd   # json -> moxie_anims.res
blender --background --threads 6 --python art/anim/build.py -- export          # mannequin.glb
blender --background --threads 6 --python art/anim/build.py -- render <dir> [filter]
python -I art/anim/sheets.py <dir> art/previews/anim          # contact sheets (iso, side, in-game size)
blender --background --threads 6 --python art/anim/build.py -- blend           # actions in a .blend for hand polish
```

`art/anim/od_rig.py` is the animation rig: the neutral T-pose humanoid (profile bone names) and
the IK/FK control solver (hips, chest, head, IK hands with poles and grip orientation, a left hand
that can grip the right hand's shaft, IK feet with heel/toe roll, root spin). `art/anim/clips.py`
holds every clip as keyed control poses. Clips are entirely hand-keyed; no third-party animation
data is included, so there is no licence entry.

**Retargeting.** A model imported through Godot's own retarget (BoneMap, "overwrite axis") matches
the profile and can use the library directly (`FeelRetarget.matches_profile(skel)`). Any other
humanoid — raw Blender bone axes, A-pose arms, missing bones, the old lower-case placeholder names
— is served by `FeelRetarget.bake_library(lib, skel, FeelRetarget.alias_for(skel))`, called once
at load. Verified on the mannequin, `assets/models/moxie.glb` and candidates a, b and c.

**Weapon attachment.** `BoneAttachment3D` on the hand bone, weapon child transform =
`FeelRig.weapon_attach_transform(skel, hand_bone, right, worn)` (derived from the hand's global
rest, so bone axes do not matter; it places the grip in the palm, not the wrist). For
`speaker_knuckles` show `Gauntlet_R` on the right hand and `Gauntlet_L` on the left with
`worn = true`. Two-handed styles need nothing extra: the left hand is keyed onto the shaft.

## 3. The CombatFeel API

```gdscript
var feel := CombatFeel.new()            # add under the render root
feel.setup(camera)
feel.shake_callable = ctx.shake         # Callable(magnitude 0..1)
feel.solid_at = func(x, y): return grid.is_solid(x, y)     # sim coords; enables wall slams
feel.height_at = ctx.surface_height     # optional floor height
```

| Call | When |
|---|---|
| `track_self(tape, node, tint, speed, style, weapon_len, body_scale)` | a self appears or its loadout / speed changes |
| `track_enemy(id, node, radius, height)` / `untrack_enemy(id)` | an enemy appears / is freed |
| `update(events, snap, dt)` | once per rendered frame, **before** posing bodies; `dt` is wall time |
| `self_fx(tape)` / `enemy_fx(id)` → `FeelSubject` | while posing: `lag`, `frozen`, `pos`/`has_pos`, `apply(base)`, `flash`, `invert` |
| `update_swing(tape, anim, shown_frac, play_dir, heavy, base)` | every frame a self is in a melee state |
| `hide_swing(tape)` | every other frame |
| `clear()` | level change |
| `camera_offset()` | if the view applies the punch itself (`drive_camera = false`) |

Signals: `impact(tier, at, dir)`, `near_miss(tape, at)`, `wall_slam(id, at, tier)` — hooks for
audio and extra fx. Switches: `enable_shake`, `enable_ghosts`, `auto_flash`, `drive_camera`.

Events consumed: `HIT`, `CLANG`, `KILL`, `BREAK`, `PROJECTILE_HIT`, `SELF_DEATH`, `ENEMY_ATTACK`
(near-miss test against selves with `iframes`). `HIT` + `CLANG` on the same enemy in one batch is
presented once, as a clang; a lone `CLANG` (shield, tough breakable) is also a clang. A `HIT`
without a `CLANG` did damage and is never presented below tier 1 (`FeelTune.hit_tier`). Dodge
afterimages come from `ActorSnap.anim == DODGE`; knockback dust, skid marks, landings and wall
slams come from watching the enemy's snapshot position after a hit.

Pieces: `FeelTune` (all numbers, pure), `FeelHold` (the lag maths, pure), `FeelSubject` (per-body
state), `FeelSmear` (arc ribbon), `FeelBursts` (pooled impact quads and decals), `FeelGhosts`
(afterimages), `FeelRig` (names, attachment, arc sampling), `FeelRetarget`.

## 4. Integration steps

**Actor layer (`actors/`):**

1. Load `FeelRig.LIBRARY_PATH`; if `not FeelRetarget.matches_profile(skel)`, replace it with
   `FeelRetarget.bake_library(lib, skel, FeelRetarget.alias_for(skel))`; hand it to
   `ActorClipSampler.add_library(lib, true)`.
2. Pick melee clips with `FeelRig.melee_clip(heavy, FeelRig.style_for(item_id), sampler.has_clip)`
   and ranged with `FeelRig.ranged_clip(archetype, sampler.has_clip)`. Fraction: wind-up state
   progress × 0.4, active 0.4 + progress × 0.2, recover 0.6 + progress × 0.4.
3. Attach weapons with `FeelRig.weapon_attach_transform` (section 2).
4. Each frame, after `feel.update(...)`:
   ```gdscript
   var fx := feel.self_fx(tape)                       # or enemy_fx(id)
   var p := fx.pos if fx.has_pos else Vector2(snap.x, snap.y)
   var shown_tick := local_tick - FeelHold.lag_ticks(fx.lag, ticks_per_second)
   # pose from shown_tick, then:
   node.transform = fx.apply(base_transform_at(p))
   feel.update_swing(tape, sampler.clip_animation(clip), shown_frac, play_dir, heavy, base)
   ```
   `ticks_per_second` is 60 × tape speed × world rate; `play_dir` is −1 on a reversed tape.
   Enemies: scrub `stagger` / `death` late by `fx.lag` the same way.
5. Call `track_self` with the cassette colour, the tape speed and
   `weapon_len` = the weapon's `Tip` marker Y (for `reel_lash` use `reach × 0.72`).

**Fx / view layer:** create the node, set the three callables, call `update` once per frame with
the frame's events and snapshot, call `clear()` on level change. Flash uses
`material_overlay` on the body's meshes and skips meshes that already have one; if the actor
layer uses the overlay slot (x-ray), set `auto_flash = false` and read `fx.flash` / `fx.invert`.
The camera punch drives `Camera3D.h_offset` / `v_offset` only.

**Status: wired.** `actors/actor_layer.gd` owns the `CombatFeel` and does all of the above
(`actors/README.md`, "Combat feel"). Differences from the steps as written: the body flash goes
through the actor body shader (`auto_flash = false`, `feel.flash_of(fx)`), dodge afterimages are
the actor layer's own (`dodge_ghosts = false`), a held swing is read back from a history of what
was shown rather than by subtracting lag ticks (so the hold survives a state change), the grip
arcs are re-measured on the shipping skeleton at load (`MoxieModel.measure_arcs`), and
`reduce_flashing` removes the flash, inverted frame and camera punch and caps the bursts.

**Requests outside my paths** (for the integration engineer):

- `docs/GODOT-PORT.md` names `res://assets/anim/moxie_anims.res`; the shipped library is
  `res://assets/anim/library/moxie_anims.res`. Either point the loader at it or copy it; a copy
  drops nothing, the metadata travels with the resource.
- `reel_lash`: the `lash_00..09` chain is not driven by the clips. For the crack to read, the
  actor layer should aim the chain along `FeelRig.arc_at(anim, frac)[1]` with a per-bone delay.
- `vinyl_glaive`: spin `Disc` during the hit window.

## 5. Tuning tables (`feel/feel_tune.gd`)

Tiers by momentum: 0 clang (< 1 or any CLANG), 1 light (1–2), 2 solid (2–4), 3 heavy (4–8),
4 crush (≥ 8).

| | clang | light | solid | heavy | crush |
|---|---|---|---|---|---|
| Victim hold (s) | 0.050 | 0.045 | 0.075 | 0.110 | 0.150 |
| Attacker hold (s) | 0.075 | 0.030 | 0.055 | 0.085 | 0.120 |
| Catch-up (s) | 0.110 | 0.060 | 0.090 | 0.120 | 0.160 |
| Flash frames (first one inverted from heavy up) | none | 1 | 2 | 2 | 3 |
| Shake (0–1) | 0.03 | 0.10 | 0.22 | 0.42 | 0.70 |
| Camera punch (tiles) | 0 | 0.035 | 0.075 | 0.135 | 0.21 |
| Burst diameter (tiles) | 0.85 | 0.95 | 1.4 | 2.0 | 2.9 |
| Impact lines | 4 | 7 | 10 | 15 | 22 |
| Burst life (s) | 0.30 | 0.16 | 0.20 | 0.26 | 0.34 |
| Squash | 0.03 | 0.12 | 0.20 | 0.30 | 0.40 |
| Recoil tilt (°) | 2 | 9 | 15 | 22 | 30 |
| Dust puffs per tile of slide | 0 | 2 | 3 | 4 | 5 |

| Tape speed | 0.5× | 1× | 2× | 4× |
|---|---|---|---|---|
| Hold scale | 1.4 | 1.0 | 0.7 | 0.5 |
| Shake / punch scale | 0.85 | 1.0 | 1.15 | 1.3 |
| Smear span scale | 1.7 | 1.0 | 0.85 | 0.75 |
| Smear weight | 1.35 | 1.0 | 0.9 | 0.8 |
| Echo blades in the smear | 0 | 0 | 3 | 5 |
| Body afterimages per swing | 0 | 0 | 2 | 4 |

| Style | Smear span (clip fraction, light, 1×) | Ribbon starts at (fraction of weapon length) | Look |
|---|---|---|---|
| blade | 0.11 | 0.18 | clean cut |
| shiv | 0.07 | 0.10 | clean cut |
| blunt | 0.13 | 0.62 | thick slab |
| whip | 0.15 | 0.55 | thin wavering line |
| gauntlet | 0.08 | fist | cone on the knuckles |
| polearm | 0.13 | 0.55 | wide sweep |

Heavies smear 1.3× longer. Smears show only between clip fractions 0.30 and 0.70. Dodge
afterimages: one every 0.035 s, each living 0.26 s. Near miss: enemy attack within 1.7 tiles of a
self in i-frames. Wall slam: a slide that ends faster than 3 tiles/s against `solid_at`.

## 6. The combat lab

```
bash tools/gd shot res://tools/combat_lab.gd <out_dir> [set=core|all|special] [style=..] [kind=..]
     [speed=..] [model=auto|mannequin|moxie|<res path>] [enemy=grunt] [reverse=1] [frames=0]
```

Default output `%TEMP%/overdub_combat_lab`: `<exchange>/f_NNN.png` (every frame, labelled with
frame number, offset from contact, momentum, tier, damage, knockback) and `strip_<exchange>.png`
(two frames before contact to six after). It drives a scripted stand-in for the sim that emits the
same events with real numbers from `core/tuning.gd` and `data/gear.json`, and poses bodies exactly
as section 4 describes. Wall exchanges are shot from the opposite corner so the wall is behind
the action. `reverse=1` rewinds the clip and smear only; the hit is still fired at the forward
timing, so use it to judge the pose and smear, not the exchange.

## 7. Tests

`bash tools/gd test feel` — 20 tests: tier mapping and monotonicity, real weapon momenta across
tiers, table shapes and escalation, clang rules, tape-speed differences, hold-lag bounds /
continuity / exact return to zero, re-hit never rewinds, lag in ticks, smear envelope and range
(forward and reversed), clip naming and catalogue coverage, grip frames, the source scan that
keeps `feel/` off simulation time, and that `CombatFeel` never mutates events or snapshots.

## 8. What I would still improve

- The clips are hand-keyed on a procedural control rig, with linear / eased interpolation between
  key poses. There is no mocap base and no in-Blender control rig for an animator; the `blend`
  export gives baked actions to polish, but changes made there do not flow back into `clips.py`.
- Secondary motion (pigtails, jacket, the whip's lash, the glaive disc) is not animated here.
- `heavy_blunt` over-reaches the left arm by up to 11 % on a few wind-up frames (the solver
  clamps it; the hand slides slightly on the shaft).
- Fast-tape echo blades can leave a detached chunk at the tail of a sledge smear during the hold.
- The heavy and crush bursts are large enough to cover the attacker for two or three frames at
  point-blank range.
- Enemy hit reactions are deformation (squash, tilt, jitter, flash) layered on the enemy's own
  `stagger` clip; there are no per-enemy-type reaction poses.
- Only the grunt was staged in the lab; the larger enemies need their `radius` / `height` tuned.
- Contact sheets in `art/previews/anim/` cover forward play; reverse and off-speed were judged in
  the lab on blade, blunt and whip only.
