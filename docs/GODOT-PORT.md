# OVERDUB — the Godot build

The shipped game is a **Godot 4.4.1 (standard, GDScript)** project at the repo root, with models
made and rigged in **Blender 4.5**. `prototype/` is the earlier TypeScript/Three.js build: it is the
executable reference for the rules (649 passing tests) and the source the simulation is ported from.
It is not shipped. `docs/ARCHITECTURE.md` still defines the design and every resolved decision;
this file defines how that design is laid out in Godot.

## Tools (this machine)

| Tool | Path |
|---|---|
| Godot (console, for headless runs) | `C:\Users\joeya\.t3\tools\godot\godot_console.exe` |
| Godot (windowed editor / game) | `C:\Users\joeya\.t3\tools\godot\godot.exe` |
| Blender | `C:\Users\joeya\.t3\tools\blender-4.5.16-windows-x64\blender.exe` |
| Prototype tests | `cd prototype && npx vitest run` |

- Headless script run: `godot_console.exe --headless --path <repo> -s res://tests/run_tests.gd -- <filter>`
- Import assets after adding files: `godot_console.exe --headless --path <repo> --import`
- Blender script run: `blender.exe --background --python art/<script>.py -- <args>`
- Several engineers share this checkout. Godot's `.godot/` import cache is shared: if an import or
  run fails on a file you do not own, wait a few seconds and retry before concluding anything.
- **Always run Godot through the wrapper**, which serialises access to the shared cache:
  `bash tools/gd test [filter]`, `bash tools/gd import`, `bash tools/gd script res://x.gd -- args`,
  `bash tools/gd shot res://x.gd` (windowed, for screenshots), `bash tools/gd raw <args>`.
- Regenerate the data files from the prototype: `cd prototype && npx vite-node scripts/export-data.ts`.

## Project settings

`project.godot` (owned by the skeleton; ask the lead for changes): application "OVERDUB", main scene
`res://game/main.tscn`, 1600×900 window, stretch `canvas_items` / aspect `expand`, Forward+. Both
physics engines are set to `Dummy`: the simulation owns all collision, and nothing may depend on
Godot physics (no bodies, areas or physics ray queries — use `ODGrid` or plain math, e.g. a
floor-plane intersection for picking). No autoloads yet (the game engineer adds what is needed).
GDScript warnings: `untyped_declaration` and `inference_on_variant` are warnings, so a stray one
never breaks another engineer's run; the defaults that stay errors (native method override,
`@onready` misuse) are real bugs. Headless runs do not print warnings; check your files in the
editor. File logging is on: the test runner reads the log to catch runtime script errors.
`.uid` files that Godot 4.4 writes next to scripts belong in the repo.

## Layout

```
project.godot
core/            deterministic simulation (GDScript port of prototype/src/core). No Node, no scene
                 tree, no randomness, no clock. RefCounted classes and static functions only.
content/         loaders for data/, loadout resolution, level validation
data/            gear.json, levels/*.json  (plain data shared with the prototype's formats)
audio/           Harmonograph port, music director, sample instruments, quantised SFX
game/            session state machine, input, save, campaign, main scene, app wiring
game/contracts/  module facade base classes + presentation data classes (see "Module facades")
world/           level construction from the kit, camera, lighting, mechanisms' visuals
actors/          Moxie, enemies, projectiles, state visuals
fx/              particles, music-linked visuals, cinematic flourishes
feel/            combat feel: hit-hold, squash, smears, impact frames (docs/COMBAT-FEEL.md)
cinema/          the director that plans the winning replay's shots (docs/CINEMATIC.md); the world
                 view owns a CinemaDirector and the app hands it the plan on a win
musicviz/        music displays mounted in the world by world/world_music_viz.gd (docs/MUSICVIZ.md)
replay/          kept winning performances and "watch again" (replay/README.md)
ui/hud/  ui/menus/   Control scenes
shaders/         shared toon / outline / state shaders
assets/models/   .glb exported from Blender     assets/audio/  generated instrument samples
art/             Blender Python sources for every model (ignored by Godot)
tests/           headless test suites + goldens exported from the prototype
tools/           dev scripts (screenshots, benchmarks)
```

Only `game/` wires modules together. `core/` imports nothing outside `core/`.

## GDScript conventions

- Static typing everywhere: typed vars, typed params, typed returns, typed arrays
  (`Array[ActorSnap]`, `PackedFloat32Array`). No `Variant` in hot paths.
- One `class_name` per file for anything used across files. `core/README.md` holds the authoritative
  TypeScript → GDScript name map (types, files, functions) and every porter follows it. Names that
  would collide with a Godot built-in or read ambiguously get an `OD` prefix (`ODTape`, `ODGrid`,
  `ODSim`).
- Port file-for-file and function-for-function: `prototype/src/core/foo.ts` → `core/foo.gd`,
  `camelCase` → `snake_case`, same argument order, same constants (`SUB_HZ = 240`, `LOCAL_HZ = 60`,
  `FRAME_SUBS = 4`). Keep the prototype's comments that explain a rule or cite a requirement id.
- TypeScript interfaces become small `RefCounted` data classes with typed fields; string unions
  become `StringName` constants or enums as the name map states; `Float32Array` becomes
  `PackedFloat32Array` (which also gives the prototype's float32 rounding for tape samples).
- The shared data classes already exist in `core/types.gd` (`OD`: constants, `OD.EndMode`,
  `OD.LifeState`, `OD.subs_per_local_tick`) and `core/types/*.gd` (one class per types.ts interface,
  each with `copy()` and, where the data is JSON, `from_dict()`/`to_dict()` in the prototype's
  camelCase keys). Read core/README.md §1-2 for how optional fields, ids, unions, `SignalExpr` and
  `EntityDef` are represented before writing code that touches them.
- Determinism rules from the prototype hold: no `randf`, no `Time`, no dictionary-order dependence
  (iterate arrays, or sorted keys), same evaluation order as the prototype.
- Performance matters in `core/`: GDScript is far slower than JS. Avoid per-substep allocation,
  reuse scratch objects, prefer packed arrays, cache lookups. Target: resolving a 16-bar, 120 bpm,
  four-tape encounter with 6 enemies in under 3 seconds on this machine (it runs on a worker thread
  behind a "rewinding tape" beat).

## Tests

`tests/run_tests.gd` is a minimal headless runner (a `SceneTree` script): it loads every
`tests/**/test_*.gd`, runs each `test_*` method, prints failures with context and exits non-zero on
failure. Suites extend `tests/od_test.gd` (assert helpers). Requirement ids stay in test names.

- `bash tools/gd test` runs everything; `bash tools/gd test <filter>` runs the suites whose
  `res://` path contains `<filter>` (`bash tools/gd test core/` or `test skeleton`).
- A suite is `extends ODTest`; the runner instantiates it, then for every method named `test_*` (in
  declaration order) calls `before_each()`, the test and `after_each()` (the hooks are optional),
  awaiting each, so tests may `await tree().process_frame`.
- Output: one `FAIL <suite> :: <test> - <message>` line per failed assertion, then a summary. Exit code
  0 only when at least one test ran and nothing failed. A suite that fails to load (parse/compile
  error in it or in a script it uses, wrong base class, no tests) is a failure, not a skip.
- A runtime script error while a test runs (null access, bad call) fails that test: the runner reads
  the engine log. A test that pushes errors on purpose calls `expect_engine_errors()` first. A test
  that makes no assertion fails.
- `ODTest` API (all return `bool`, true when passed): `assert_true(c, msg)`, `assert_false`,
  `assert_eq(actual, expected, msg)` (JSON-style: `1 == 1.0`, String == StringName, deep arrays and
  dictionaries; objects by identity), `assert_ne`, `assert_near(a, b, eps, msg)`,
  `assert_vec_near(a, b, eps, msg)`, `assert_array_eq(a, b, msg, eps)`, `assert_json_eq(a, b, eps, msg)`,
  `assert_has(container, item, msg)`, `fail(msg)`; helpers `load_json(path)`, `tree()`.
- Godot's `==` is type-strict for containers (`[1] == [1.0]` is false); use `assert_eq` /
  `ODJson.deep_equal` for JSON-shaped data.

Goldens: `tests/goldens/*.json` are exported from the prototype
(`prototype/scripts/export-goldens.ts`) — scripted scenarios with expected events and sampled
snapshots. The Godot port must reproduce them (positions within 1e-3 tiles, identical event
sequences); that is the proof the port preserved the rules. Load them with the types' `from_dict()`
and compare typed values, or compare `to_dict()` output with `assert_json_eq`: `to_dict()` omits
optional fields at their absent-default (`startFacing: 0`, `bossRecall: false`), so strip those
before comparing raw prototype JSON.

## Data

`data/` holds the prototype's content as plain JSON in exactly the TypeScript shapes, written by
`prototype/scripts/export-data.ts` (`cd prototype && npx vite-node scripts/export-data.ts`):

| File | Shape |
|---|---|
| `data/gear.json` | `{ "version": 1, "items": GearItem[] (catalogue order), "baseLoadout": Loadout }` |
| `data/levels/<id>.json` | one `LevelDef` |
| `data/levels/index.json` | `{ "version": 1, "levels": [ids in campaign order], "extra": [off-path ids] }` |

`content/data.gd` (`ContentData`) loads them into the typed classes: `load_gear(errors)` →
`ContentData.GearCatalogue` (`items`, `by_id`, `base_loadout`, `get_item(id)`, `items_in_slot(slot)`,
`base_inventory()`), `load_level(id, errors)` → `LevelDef`, `list_level_ids(include_extra, errors)`,
`load_campaign(errors)` → `Array[LevelDef]` sorted by index. Each returns null / skips and appends
reasons to `errors` on a missing or malformed file. Level designers may author new levels directly
as JSON in `data/levels/` (add the id to `index.json`). The export preset must include `data/*.json`
as non-resource files.

## Asset contract (Blender → Godot)

- Units: 1 Blender metre = 1 Godot unit = 1 tile. Y up in Godot. A model's origin is on the floor at
  its footprint centre. Characters face **+Z** in Godot at rest.
- Export: glTF binary (`.glb`), meshes + armature + animations as separate named actions, no
  cameras or lights, materials with base colours only (Godot applies the toon shader). Keep each
  character under about 25k triangles; kit pieces far less.
- Material names are the styling hook (Godot swaps shaders and tints by name). Emissive parts use a
  material whose name ends in `_glow`.
- Every source is a Blender Python script under `art/` that rebuilds the `.glb` from scratch and can
  render preview stills (`art/previews/`, git-ignored) for review.

**Moxie** — `assets/models/moxie.glb`. About 1.6 units tall, anime proportions matching
`docs/reference/R01-moxie-concept.png` and the turnaround in `R02-moxie-sheet.png`. She is being
rebuilt to a much higher standard by a dedicated team; code must rely only on what follows.

- Skeleton `Skeleton3D` named `Rig`, rest pose a clean T-pose, using **Godot's
  `SkeletonProfileHumanoid` bone names** (`Hips, Spine, Chest, UpperChest, Neck, Head,
  LeftShoulder, LeftUpperArm, LeftLowerArm, LeftHand, RightShoulder, RightUpperArm, RightLowerArm,
  RightHand, LeftUpperLeg, LeftLowerLeg, LeftFoot, LeftToes, RightUpperLeg, RightLowerLeg,
  RightFoot, RightToes`, plus the profile's finger bones), so any humanoid animation library
  (Mixamo, Quaternius, KayKit, mocap) retargets onto her. Extra non-profile bones (pigtails,
  jacket, straps) are allowed and are driven by secondary motion, never by gameplay clips.
- Attachments: melee weapon on `RightHand`, wrist device on `LeftLowerArm` (use `BoneAttachment3D`).
- Animations live in `res://assets/anim/moxie_anims.res` (an `AnimationLibrary`) with these names:
  loops `idle`, `run`, `stopped`; one-shots normalised to exactly 1.0 s so the game can scrub them
  by state progress: `light` and `heavy` (wind-up is the first 40%, the hit 40-60%, recovery the
  last 40%), `dodge`, `ranged`, `interact`, `death`. Until that file exists, fall back to any
  animations inside the glb, then to a static pose.
- Material names are not fixed: discover them at load. Tint hooks, when present, are materials
  whose names start with `top`, `pants`, `shoes`; emissive parts end in `_glow`.

**Melee weapons** — `assets/models/weapons/<item id>.glb` for `splice_blade, stylus_shiv,
amp_sledge, reel_lash, speaker_knuckles, vinyl_glaive`; origin at the grip, business end along +Y.

**Enemies** — `assets/models/enemies/<type>.glb` for `grunt, stalker, turret, shielder, brute,
drone, boss`. Armature `Rig`; animations `idle` (loop), `move` (loop), `telegraph` (1.0 s,
scrubbed), `attack` (1.0 s), `stagger` (1.0 s), `death` (1.0 s). The turret and drone have an `aim`
bone the game rotates. The shielder has a separate mesh object `Shield`; the boss has mesh objects
`Armor_1`, `Armor_2`, `Armor_3` that the game hides as phases advance. A "ruin-security machine"
family that fits ancient ruins retrofitted with music and time technology.

**Environment kit** — `assets/models/kit/<name>.glb`, listed in `assets/models/kit/manifest.json`:
`{ "pieces": { "<name>": { "file": "...", "themes": ["upper","mid","lower","core"], "size": [x,y,z] } } }`.
Tile pieces are 1×1 in X/Z with the walkable surface at Y = 0. Required names:

- floors: `floor_solid, floor_cracked, floor_grate, floor_overgrown, floor_rune`
- structure: `wall`, `wall_top_a`, `wall_top_b`, `wall_cut` (low cutaway for camera-side walls),
  `barrier_low`, `cliff_skirt`, `edge_trim`
- mechanisms: `door` (mesh objects `Frame` and `Panel`; the game slides `Panel`), `switch`
  (`Base`, `Lever`), `plate` (`Base`, `Pad`), `breakable` plus `breakable_chunks` (separate chunk
  objects), `laser_emitter`, `core` (`Shell`, `Heart`), `exit_pad`
- decor, one per `DecorDef.type` (graffiti is a decal the game draws; the rest are models):
  `vines, bush, crate, barrel, pipe, console, generator, vent, arch, rubble, chest, neon,
  rune_panel, wave_screen, cable, lamp, time_machine`

Where the upper look (warm masonry, overgrowth) and the lower look (dark rune-inscribed metal,
neon) differ in shape, provide `<name>__upper` and `<name>__lower`; the game picks by theme, falls
back to the unsuffixed name, then to a plain box.

## Presentation

Orthographic isometric camera (yaw 45°, pitch about 35°). Cel shading: a shared toon
`ShaderMaterial` with stepped lighting and an inverted-hull ink outline pass; glow through
`WorldEnvironment`. Selves are the same Moxie told apart by cassette colour (outline, floor ring,
headphone glow). State looks as in `docs/ARCHITECTURE.md`: recording ghost, playback ghost,
desynced projection and recovery spark must never be confused. Camera-side walls use `wall_cut` and
occluded actors get an x-ray silhouette, so nothing important is ever hidden.

## Module facades

`prototype/src/contracts.ts` is ported to `game/contracts/`. Each presentation module implements one
base class at a **fixed path**, so the game engineer can instance it without coordination
(`Facades.instance_*()` returns the do-nothing base while a file does not exist yet, so the game
runs from day one; a file with the wrong base class is reported with `push_error`).

| Implementer provides | Root / script extends | Instanced by |
|---|---|---|
| `res://world/world_view.tscn` | `WorldViewBase` (Node3D) | game: `Facades.instance_world_view()` |
| `res://actors/actor_layer.gd` | `ActorLayerBase` (RenderLayerBase, Node3D) | world view: `attach_layers()` |
| `res://fx/fx_layer.gd` | `FxLayerBase` (RenderLayerBase, Node3D) | world view: `attach_layers()` |
| `res://audio/audio.tscn` | `AudioBase` (Node) | game: `Facades.instance_audio()` |
| `res://ui/ui_root.tscn` | `UiBase` (Control) | game: `Facades.instance_ui()` |
| `res://ui/hud/hud.tscn` | `HudBase` (Control) | ui root: `attach_hud()` |

The layer scripts and scene roots need no `class_name` (they are loaded by path); give helper scripts
module-prefixed class_names (core/README.md §4).

**WorldViewBase** (contracts.ts `IRenderer`): `load_level(level, loadout)`, `render(frame: RenderFrame)`,
`screen_up_in_world() -> Vector2` (sim axes), `screen_to_world(viewport_pos: Vector2) -> Vector2`
(floor point, sim axes), `set_quality(WorldViewBase.QUALITY_LOW|QUALITY_HIGH)`,
`set_screen_shake(enabled)`, `dispose()`; signal `level_loaded(level)`. Hooks the layers reach through
`RenderCtx`: `request_shake(magnitude)`, `request_focus(x, y, weight)`, `surface_height(x, y)`.
Provided plumbing: `attach_layers()`, `new_ctx(level, loadout) -> RenderCtx` (fresh `LevelRoot`
child), `_load_layers(ctx)` (call at the end of `load_level`), `_update_layers(frame)` (call in
`render`). Scene convention (prototype render/layer.ts): 1 tile = 1 unit, sim (x, y) → scene
(X = x, Z = y), Y up, floor top at Y = 0; `RenderCtx.to_scene/to_sim/heading_to_yaw` do the mapping
(a +Z-facing model rotated by `heading_to_yaw(dir)` faces sim heading `dir`).

**RenderCtx** (layer.ts `RenderCtx`): `view, camera: Camera3D, palette: ThemePalette, level, loadout,
root: Node3D, toon_material: ShaderMaterial, toon_ramp: Texture2D, quality, music_reactive:
Array[MusicReactive], post: PostControls, bounds: AABB (scene units), time, screen_shake_enabled`;
`shake(m)`, `focus(x, y, w)`, `surface_height(x, y)`.

**RenderLayerBase** (layer.ts `RenderLayer`), extended by `ActorLayerBase` / `FxLayerBase`:
`load_level(ctx)`, `update(frame, ctx)`, `dispose()`. The world view adds each layer as its child;
layers put per-level nodes under themselves or `ctx.root`. The fx layer owns the modulation of
`ctx.music_reactive` (each `MusicReactive.set_level(level)`, 1 = as built) and drives `ctx.post`
(`chromatic`/`flash` are kicks the world view decays; `saturation`/`vignette` are held values).

**RenderFrame**: `snap, prev: FrameSnapshot, alpha, dt, mode (ViewMode.*), events: Array[SimEvent],
world_rate, music: MusicPulse, active (tape or -1)`. **MusicPulse**: `beat, beat_pulse, bar_pulse,
levels, pitches (PackedFloat32Array of 4), chord`.

**AudioBase** (contracts.ts `IAudio`): `unlock()`, `load_level(level)`,
`set_transport(master_beat, rate, playing)`, `set_tracks(tracks: Array[TrackAudioState])` (4),
`on_events(events: Array[SimEvent])`, `count_in(n)` (5..8), `ui(kind)` (`AudioBase.UI_*`),
`set_mode(mode)` (`AudioBase.MODE_*`), `set_volumes(master, music, sfx)`, `pulse() -> MusicPulse`
(cheap; silent defaults), `dispose()`. **TrackAudioState**: `present, speed, life (OD.LifeState),
synced, transport`.

**UiBase** (contracts.ts `IUi`): signal `intent(i: UiIntent)`; `show_screen(UiScreen.*)`,
`update_hud(view: SessionView, pulse: MusicPulse)`, `set_campaign(CampaignScreenModel)`,
`set_loadout(LoadoutScreenModel)`, `set_results(ResultsModel)`, `set_settings(SaveSettings)`,
`toast(text, tone)` (`UiBase.TONE_*`), `deck_event(tape, kind)` (ActionKind.* or StateMarkKind.*),
`navigate(dir)` (`UiBase.NAV_*`), `set_device(UiBase.DEVICE_KEYBOARD|DEVICE_GAMEPAD)`,
`set_bindings(prompts: Dictionary[StringName, ButtonPrompt])` (SessionAction / ActionKind → prompt),
`set_hold_progress(0..1)`, `dispose()`. The base instances the HUD (`attach_hud()`, call in `_ready`),
shows it on `play`/`pause`, forwards `update_hud, deck_event, set_device, set_bindings,
set_hold_progress` and `patterns` to it, and turns its `action` signal into session intents; menu
code overrides the rest (calling `super` where the base does something). The game adds the UI root
on a `CanvasLayer` above the world.

**HudBase** (prototype ui/hud `Hud`): signal `action(session_action)`; `update_hud(view, pulse)`,
`deck_event(tape, kind)`, `set_device(device)`, `set_bindings(prompts)`, `set_hold_progress(p)`,
`set_patterns(enabled)`.

**UiIntent** (contracts.ts `UiIntent` union): `type` (`UiIntentType.*`) plus `action`, `id`,
`slot`, `key` (SaveSettings key in prototype spelling), `value` (float or bool); constructors
`UiIntent.session(action)`, `.simple(type)`, `.play_level(id)`, `.equip(slot, id)`,
`.setting(key, value)`. Screen models: `LoadoutScreenModel {inventory, loadout, summary, fresh}`,
`CampaignScreenModel {levels: Array[CampaignLevelEntry], current}`,
`CampaignLevelEntry {level, cleared, unlocked, loot, has_loot}`,
`ResultsModel {level, outcome, tapes_used, loot, has_next, next_id}`.

The input facade (contracts.ts `IInput`) is internal to `game/` and owned by the game engineer.

## Asset contract addendum: Weapons

Source: `art/weapons/` (`build.py` rebuilds every glb; `melee.py`, `ranged.py`, `projectiles.py` hold
the models; `check_glb.py` verifies the files without Blender; `check_weapons.gd` verifies them in
Godot; `hand.py` + `sheets.py` make the previews in `art/previews/weapons/`). Concept sheets:
`docs/reference/generated/weapons/<id>.png`. This supersedes the one-line "Melee weapons" entry above.

Common rules: units are tiles (Moxie = 1.6). Flat base colours only, no textures or UVs (stickers
are geometry). Materials are shared by name across all weapons: `weapon_main` (the item's
`look.color`), `weapon_accent` (Moxie yellow), `weapon_accent2` (magenta), `weapon_metal`,
`weapon_steel`, `weapon_dark`, `weapon_black`, `weapon_grip`, `weapon_wood`, `weapon_tape`,
`weapon_copper`, `weapon_paper`, and emissives `weapon_glow` (cyan), `weapon_hot_glow` (orange),
`weapon_pink_glow`, `weapon_violet_glow`, `weapon_green_glow`; enemy shots use `bolt_glow`,
`bolt_dark`, `shock_glow`, `shock_dark`. No animations, cameras or lights in any file. Marker nodes
are plain `Node3D`s at the scene root (find them with `find_child`).

### Melee — `assets/models/weapons/<item id>.glb`

Frame: origin at the centre of the (main) grip, a cylinder along Y that the fist closes round;
business end **+Y**; cutting edge / striking face toward **+Z**; thin axis X. Markers: `Grip`
(origin), `Tip` (farthest striking point), `TrailStart` → `TrailEnd` (the two ends of the striking
edge: stretch the smear ribbon between them), `Grip2` (off hand, two-handed weapons). The current
attach code puts the weapon at the hand bone origin, which is the wrist: move it about 0.07 along
the hand bone (the palm) or the grip sits in the wrist.

| id | mesh nodes | tris | size X × Y × Z | Y extent (butt..top) | Tip | TrailStart → TrailEnd | anim style | silhouette intent |
|---|---|---|---|---|---|---|---|---|
| `splice_blade` | `Weapon` | 3888 | 0.07 × 1.05 × 0.26 | -0.245..0.805 | (0, 0.805, -0.052) | (0, 0.160, 0.074) → (0, 0.775, -0.012) | blade | broad single-edged short sword, straight yellow spine, deep belly, 45° splice-cut tip, wide splicing-block guard; the balanced baseline |
| `stylus_shiv` | `Weapon` | 2640 | 0.09 × 0.57 × 0.07 | -0.142..0.432 | (0, 0.432, 0.023) | (0, 0.275, 0.020) → (0, 0.432, 0.023) | shiv (thrust; reverse grip also reads) | a tone arm: fat counterweight pommel, yellow gimbal ring, hair-thin arm and needle with a pink glow point; the lightest, thinnest thing she owns |
| `amp_sledge` | `Weapon` | 7078 | 0.30 × 1.44 × 0.63 | -0.351..1.091 | (0, 0.890, 0.272) | (0, 0.755, 0.270) → (0, 1.025, 0.270) | blunt (two-handed, `Grip2` at y 0.36) | a 0.27 × 0.29 × 0.48 amp head across a scaffold pole: by far the most mass, all of it at the far end; steel strike plate at +Z, glowing valves in a cage at -Z |
| `reel_lash` | `Weapon`, `LashRig`/`Lash` (skinned) | 4596 | 0.15 × 2.40 × 0.25 | -0.142..2.255 | (0, 2.255, 0.010) | (0, 1.150, 0.044) → (0, 2.255, 0.010) | whip | a small hand reel and then 1.9 units of tape: the longest, narrowest line in the game |
| `speaker_knuckles` | `Gauntlet_R`, `Gauntlet_L` | 2650 each | 0.13 × 0.21 × 0.14 | -0.105..0.101 | (0, 0.098, 0.004) | (0, 0.094, -0.050) → (0, 0.094, 0.060) | gauntlet | a round pink driver cone over each fist; no length at all |
| `vinyl_glaive` | `Weapon`, `Disc` | 7536 | 0.09 × 2.01 × 0.60 | -0.560..1.450 | (0, 1.343, 0.380) | (0, 1.000, 0.410) → (0, 1.450, 0.150) | polearm (two-handed, `Grip2` at y -0.30) | taller than Moxie: a 0.6-wide record on a broom handle, a lollipop that sweeps |

- `reel_lash`: `Lash` is skinned to `LashRig` (a `Skeleton3D` after import), bones `lash_00` …
  `lash_09`, a single chain, each 0.18 long (the last 0.295, carrying the steel leader clip), bone Y
  along the tape. Rest shape: out along +Y from `LashRoot` (0, 0.34, 0.04) with a shallow S in the
  YZ plane and one full twist of the ribbon so it shows from any camera. Animate the bones for the
  crack; scaling `LashRig` in Y is acceptable for reach changes. `Tip`/`TrailEnd` mark the REST
  tip; for a live trail follow the tail of `lash_09`.
- `speaker_knuckles`: both gauntlets are in one file, both at the origin. Their frame is the FIST,
  not a held grip: origin at the centre of the closed fist, **+Y along the hand bone** (wrist →
  knuckles, the punch direction), **+Z = back of the hand**, thumb side -X on `Gauntlet_R` and +X on
  `Gauntlet_L`. Parent `Gauntlet_R` to the right hand and `Gauntlet_L` to the left hand, each 0.075
  along the hand bone, and do not apply the "weapon points forward" rotation used for held weapons.
  The wrist strap ring has an inner radius of 0.035.
- `vinyl_glaive`: `Disc` is a separate node whose origin is the spindle (0, 1.15, 0.15) (also
  marked by `DiscAxis`); spin it about its local X. Radius 0.30.
- `amp_sledge` and `vinyl_glaive` are over the 6k-triangle guideline (7.1k, 7.5k).

### Ranged — `assets/models/weapons/<item id>.glb`

All five are worn on the LEFT forearm. Frame: origin (`Mount`) on the TOP surface of the forearm
about 60% of the way from elbow to wrist; **+Z toward the hand = direction of fire**; **+Y away
from the arm**; the forearm axis runs along Z at y = -0.036. Each file includes its own bracer: a
full ring round the arm, inner radius 0.039, from z -0.07 to 0.045, so it replaces (do not stack it
on) the `wrist_device` mesh. Attach to `LeftLowerArm` so that Z lies along the bone and choose the
roll about the bone so +Y points up in the `ranged` pose. `Muzzle` is where shots spawn; its +Z is
the launch direction.

| id | mesh nodes | tris | size X × Y × Z | Muzzle | archetype → projectile | silhouette intent |
|---|---|---|---|---|---|---|
| `mixtape_rocket` | `Weapon`, `Round` | 4124 | 0.18 × 0.26 × 0.33 | (0, 0.092, 0.215) | missile → `missile.glb` | short, boxy, heavy: an open coral cassette well with the fat rocket lying in it, deck door flipped up behind. Hide `Round` while the weapon recharges |
| `needle_rail` | `Weapon` | 4392 | 0.13 × 0.26 × 0.56 | (0, 0.045, 0.450) | pierce → `pierce.glb` | twin rails reaching 0.45 past the mount with a cyan line between, copper coils, a spiked needle wheel on top: the longest and thinnest |
| `bleed_emitter` | `Weapon` | 3550 | 0.15 × 0.24 × 0.29 | (0, 0.082, 0.210) | phase → `phase.glb` | two tape heads facing across a gap and a horn of three widening violet rings: round, hollow, eerie |
| `bass_drop` | `Weapon` | 3378 | 0.16 × 0.32 × 0.31 | (0, 0.181, 0.096), +Z tilted 40° up | arc → `arc.glb` | a fat mortar tube tilted 40° up with a subwoofer cone for a breech: the only one that leaves the line of the arm |
| `static_spray` | `Weapon` | 3930 | 0.27 × 0.31 × 0.37 | (0, 0.052, 0.230) | burst → `burst.glb` | a cyan boombox, speakers up, with a yellow fan nozzle 0.25 wide carrying five emitters at -20..20°: wide and short |

### Projectiles — `assets/models/projectiles/<archetype>.glb`

One mesh node `Projectile`, origin at the centre of the collision circle, nose **+Z**, +Y up;
markers `Nose` and `Tail` (trail / exhaust anchor).

| file | tris | size X × Y × Z | look |
|---|---|---|---|
| `missile` | 1336 | 0.20 × 0.12 × 0.37 | cassette shell, yellow squashed nose, pink tip, four yellow fins, `weapon_hot_glow` flame |
| `pierce` | 276 | 0.05 × 0.04 × 0.58 | phonograph-needle lance with a cyan sleeve |
| `phase` | 980 | 0.31 × 0.23 × 0.34 | violet glow orb in A/B brackets with three echo rings trailing |
| `arc` | 1548 | 0.22 × 0.22 × 0.22 | squat bass canister, speaker cone forward, green glow ring (spin about X as it tumbles) |
| `burst` | 52 | 0.08 × 0.11 × 0.15 | cyan spark shard, instance five |
| `bolt` | 216 | 0.15 × 0.13 × 0.32 | enemy shot: `bolt_glow` (#ff6a1a) shard in a dark collar with three vanes |
| `shock` | 288 | 0.55 × 0.08 × 0.25 | boss shockwave shot: a 100° crescent of the expanding ring (radius 0.34), convex toward +Z, toothed |

## Asset contract addendum: Traps

Source: `art/traps/` (`traps.py` holds the models and every number below as a named constant;
`traplib.py` the shared helpers, built on `art/kit/`; `build_traps.py` rebuilds the glbs, merges the
manifest and renders `art/previews/traps/`; `check_traps.py` verifies the files without Blender;
`check_traps.gd` verifies them in Godot). Rules and snapshot fields: `docs/TRAPS.md`.

```
blender --background --threads 6 --python art/traps/build_traps.py -- [--pieces a,b] [--sheet] [--diorama]
python art/traps/check_traps.py --verbose
bash tools/gd script res://art/traps/check_traps.gd
```

Common rules:

- Files are `assets/models/kit/trap_<name>__upper.glb` and `__lower.glb` (`trap_dart_bolt.glb` has
  one look). Manifest keys follow the kit: `trap_<name>__upper|mid|lower|core` and plain
  `trap_<name>` (upper). Each manifest entry also carries `kind`, `objects`, `placement` and the
  numbers below, so code can read them instead of hard-coding.
- Coordinates below are Godot local space, 1 unit = 1 tile, floor at y = 0. **A directional trap
  acts along +Z at rest**: yaw the whole piece with `RenderCtx.heading_to_yaw(snap.dir)`.
- Floor traps: origin at the centre of their cell. Wall-mounted machines (crusher, flame, dart):
  origin at the centre of the **wall tile** they sit in; the unit hangs off that tile's +Z face and
  the first lane cell is centred at z = +1.
- Every file is a flat list of `MeshInstance3D`s under the scene root (no skeleton, no animations,
  no rest rotation). Each moving part is its own object whose origin is its pivot, exported in the
  SAFE pose. All motion is one translation or one scale per part, set from the snapshot.
- Flat base colours, no textures. Only the conveyor's `Belt` and `Arrows` carry meaningful UVs.
- Hazard language: yellow (`paint_yellow`) chevrons on `hazard_dark` point along the direction of
  action; diagonal stripes with no direction mean "danger on this tile".
- Glow materials (drive emission energy by name; none uses a cassette colour):

| material | colour | drive with |
|---|---|---|
| `warn_glow` | #FF6A1E | `warn` 0..1 linearly while off; full while `on` (spikes, crusher, flame); dim when safe |
| `heat_glow` | #FF8A2A | flame throat: `on` |
| `pilot_glow` | #4C7CFF | flame pilot: always lit; flare with `warn` |
| `flame_glow`, `flame_core_glow` | #FF7A1A, #FFE08A | the `Jet` stand-in mesh |
| `pip_glow` | #F2ECFF | dart pips (shown / hidden per pip) |
| `muzzle_glow` | #FFF4D0 | dart `Flash` |
| `dart_glow` | #F4EEFF | the dart bolt |
| `sensor_glow`, `beam_glow` | #CFE4FF | sensor lens / beam: steady, brighter while `on` |
| `relay_glow` | #FF9A2E | relay lamp and ticks |
| `magnet_glow`, `magnet_ring_glow` | #B060FF | coil: `on`; ring: faint always, brighter while `on` |
| `run_glow` | #FFE7A0 | conveyor edge lines: `on` |
| `accent_glow`, `neon_cyan_glow`, `rune_glow` | kit colours | decoration, always lit |

Per trap (`t`, `on`, `warn`, `dir`, `reach`, `firing` are `MechSnap` fields):

**Spikes** — `trap_spikes` (1 x 1 floor overlay, y -0.04..0.03; ~3.3k tris). Objects: `Base` (plate
with 16 holes on a 4 x 4 grid at x, z = -0.3 + 0.2 i, hazard border, a `warn_glow` collar round every
hole), `Spikes` (16 steel spikes, pivot (0, -0.02, 0) at the spike roots).
`Spikes.scale.y` = 0.02 down (rest; tips below the rim) .. 1 raised (tips at y = 0.62). Drive:
`scale.y = 1` when `on` (snap up in <= 2 frames, drop over ~0.1 s); while off, `0.02 + 0.1 * warn`
plus a shiver; collars' `warn_glow` = `warn`.

**Crusher (piston)** — `trap_crusher` when the snapshot has `dir` (1 x 1 x 1.86 housing that
**replaces the wall piece** on the tile behind `cells[0]`; ~2.5k tris). Objects: `Housing`, `Head`
(the striking block, 0.88 wide, 1.3 tall, 0.45 deep; pivot (0, 0, 0.53) = centre of its front face
at floor level), `Ram` (the body behind the head, a featureless 1-unit-long bar along +Z; pivot
(0, 0, 0.05)). Travel is along +Z only:
`Head.position.z = 0.53 + t * (cells - 0.05)` (home 0.53; extended `cells + 0.48`, i.e. 2 cm short
of the far end of the last cell), `Ram.scale.z = Head.position.z - 0.35` (rest 0.18). `cells` is the
number of lane cells. Lamps on the housing: `warn_glow` = `warn`, full while `on`.
`trap_crusher_lane` (object `Lane`, one per lane cell, same yaw): rails, `warn_glow` strips and two
floor chevrons pointing along the stroke.

**Crusher (overhead stamper)** — `trap_crusher_stamper` when the snapshot has no `dir` (one cell,
any yaw; 1 x 2.57 x 1; ~3.1k tris). Objects: `Frame` (four posts, gantry, floor target ring in
`warn_glow`), `Head` (0.82 square, 0.8 tall; pivot (0, 1.3, 0) = centre of its sole), `Ram` (rod,
1 unit long along -Y; pivot (0, 2.1, 0) under the gantry). Travel is along Y only:
`Head.position.y = 1.3 - t * 1.28` (home 1.3, down 0.02), `Ram.scale.y = 1.35 - Head.position.y`
(rest 0.05).

**Conveyor** — `trap_conveyor`, one per cell, +Z = current travel direction (re-yaw on reversal;
1 x 1 floor overlay, y -0.04..0.10; ~900 tris). Objects: `Frame` (side rails with chevrons,
`run_glow` edge lines), `Belt` (the tread surface, top at y = 0.05), `Arrows` (three big chevrons
on the belt, material `belt_arrow`), `End_Back` / `End_Front` (end lips), `Roller_Back` /
`Roller_Front` (drums, radius 0.062, pivots (0, 0.035, -0.435) and (0, 0.035, +0.435), axis X).
Show `End_Back` + `Roller_Back` only on the first cell of a run and `End_Front` + `Roller_Front`
only on the last; hide them elsewhere.
**UVs** (`Belt` and `Arrows`, identical mapping): U = 0..1 across the belt from -X to +X (x = -0.392
.. +0.392); **V = z + 0.5**, 0 at the upstream edge, 1 at the downstream edge, so 1 V = 1 tile and
adjacent cells tile seamlessly. To run the belt, subtract `distance_travelled_in_tiles` from V in
the shader (`UV.y - offset`, wrapped) for both objects, using the real belt speed in tiles per
master second; spin the rollers about X by `distance / 0.062` radians. Stopped (`on` false): freeze
the offset and dim `run_glow`.

**Flame jet** — `trap_flame` on the nozzle's wall tile (0.64 x 0.46, protrudes to z = 0.845; ~1.3k
tris). Objects: `Body`, `Nozzle` (pivot (0, 0.26, 0.66) on the jet axis; recoil / shake it along Z),
`Pilot` (blue pilot flame, pivot (0, 0.142, 0.8); scale it up with `warn`), `Jet` (optional stand-in
for the fire: 1 unit long along +Z from the nozzle mouth, pivot (0, 0.26, 0.845)). Drive: hide `Jet`
unless `on`; `Jet.scale.z = reach - 0.345` so it ends exactly `reach` tiles from the wall face;
`heat_glow` lit while `on`. A particle jet may replace `Jet`: emit from its pivot along +Z.
`trap_flame_lane` (object `Lane`, one per tile of `reach`, including while off): scorch marks,
`warn_glow` strips = `warn`, chevron edges. Add / remove lane tiles as `reach` changes.

**Dart launcher** — `trap_dart` on the launcher's wall tile (0.52 x 0.57, protrudes to z = 0.745;
842 tris). Objects: `Body`, `Muzzle` (slotted sleeve, pivot (0, 0.3, 0.66); recoil
`position.z = 0.66 - 0.04` while `firing`), `Shutter` (yellow hazard plate, pivot (0, 0.396,
0.7345); `position.y` = 0.396 open (rest, parked above the slot) .. 0.301 closed (over the slot)
when `on` is false), `Flash` (muzzle flash, pivot (0, 0.3, 0.745); visible only while `firing`),
`Pip_01` .. `Pip_08` (progress lamps in a row on the hood, left to right from -X; show `Pip_i` when
`t >= i / 8`; all hidden when `on` is false).
`trap_dart_lane` (object `Lane`, one per lane tile): thin scored line with small chevrons.
`trap_dart_bolt.glb` (object `Dart`, 56 tris, 0.08 x 0.08 x 0.3, origin at its centre, point +Z):
the `'dart'` projectile; fly it at y = 0.30.

**Bumper** — `trap_bumper`, +Z = launch direction (1 x 1 floor overlay; ~1.4k tris). Objects: `Base`
(plate with a well, chevron strips), `Pad` (round plate with the launch arrow, pivot (0, 0, 0)),
`Spring` (coil, 1 unit tall along +Y, pivot (0, -0.02, 0)). Travel along Y:
`Pad.position.y = 0.20 * t` (`t` runs 1 -> 0 after firing), `Spring.scale.y = 0.04 + Pad.position.y`
(rest 0.04).

**Beam sensor** — `trap_sensor` (0.16 square, 0.43 tall; 376 tris). Place one at `from` with +Z
toward `to`, and one at `to` facing back with its `Beam` hidden. Objects: `Post`, `Lens` (lens and
cap lamp, `sensor_glow`; pivot (0, 0.32, 0.068)), `Beam` (optional stand-in: a dashed pale line 1
unit long along +Z at y = 0.32, pivot (0, 0.32, 0.08)). Drive: `Beam.scale.z = reach`; brighten
`sensor_glow` / `beam_glow` while `on`. Never draw it as a solid or red line (that is a laser).

**Relay** — `trap_relay` (0.29 square box, 0.26 tall; 812 tris), origin on the surface under it
(floor, or a wall top at y = 1.6). Objects: `Body`, `Lamp` (dome, pivot (0, 0.19, 0)), `Tick_01` ..
`Tick_08` (progress ring round the lamp; `Tick_01` starts at the back (-Z) and they run clockwise
seen from above). Drive: lamp dark at rest, blinking while armed (`warn` = 1), solid while `on`;
show `Tick_i` when armed and `t >= i / 8`, hide all otherwise.

**Magnet** — `trap_magnet` (disc radius 0.36, 0.14 tall; ~1.3k tris), origin on the floor at the
magnet's point. Objects: `Base` (disc with inward-pointing chevrons and a horseshoe emblem), `Coil`
(`magnet_glow` ring, pivot (0, 0.05, 0)), `Ring` (thin floor ring of radius 1, pivot (0, 0, 0)).
Drive: `Ring.scale.x = Ring.scale.z = radius` (from the entity def; the snapshot does not carry it);
`magnet_glow` lit while `on`; for the contracting-rings effect, instance / animate `Ring` scaling
from `radius` toward 0.3.

Snapshot field -> part, in one table:

| kind | field | part |
|---|---|---|
| spikes | `on`, `warn` | `Spikes.scale.y`; `warn_glow` |
| crusher | `t`, `dir` present | `Head.position.z`, `Ram.scale.z` (`trap_crusher`); `warn` -> `warn_glow` |
| crusher | `t`, no `dir` | `Head.position.y`, `Ram.scale.y` (`trap_crusher_stamper`) |
| conveyor | `on`, `dir` | piece yaw; `Belt` / `Arrows` UV.y scroll; roller spin; `run_glow` |
| flame | `on`, `reach`, `warn` | `Jet` visibility and `scale.z`; number of lane tiles; `heat_glow`, `warn_glow`, `Pilot` scale |
| dart | `t`, `firing`, `on` | `Pip_NN` visibility; `Muzzle.position.z`, `Flash`; `Shutter.position.y` |
| bumper | `t`, `dir` | `Pad.position.y`, `Spring.scale.y`; piece yaw |
| sensor | `reach`, `on` | `Beam.scale.z`; `sensor_glow`, `beam_glow` |
| relay | `on`, `warn`, `t` | `Lamp` emission; `Tick_NN` visibility |
| magnet | `on` | `magnet_glow`, `magnet_ring_glow` |
