# core/ — the GDScript port of `prototype/src/core`: name map and rules

This file is **authoritative**. Every porter follows it literally, in parallel. If a name you need is
not here, pick one following the rules below, make sure no table here already uses it, and tell the
lead so it is added. Never rename anything listed here.

`core/` imports nothing outside `core/` (it may use `res://core/types/**` and the other `core/`
classes listed below). No Node, no scene tree, no randomness, no clock. `RefCounted` classes and
static functions only.

## 1. Rules

### Files and classes

- `prototype/src/core/foo.ts` → `core/foo.gd`; `core/enemies/foo.ts` → `core/enemies/foo.gd`;
  `core/weapons/foo.ts` → `core/weapons/foo.gd`. File names are snake_case
  (`bossMemory.ts` → `boss_memory.gd`).
- Each `.gd` has exactly one `class_name` (table in §3). A prototype module's **free functions and
  constants become `static func` / `const` on that class**; its exported classes are either that same
  class or an extra file listed in §3; its small helper interfaces become **inner classes** of the
  module's class (`ODGrid.RayHit`), unless §3 lists them as top-level classes (types used across many
  files are top-level).
- Names that collide with a Godot built-in or read ambiguously take an `OD` prefix: `OD` (types.ts
  constants), `ODTape`, `ODTime`, `ODGrid`, `ODSim`, `ODSignals`, `ODCore`, `ODResolve`, `ODJson`,
  `ODTest`. `Theme` → `LevelTheme`, `Screen` → `UiScreen` (Godot has `Theme`).
- GDScript has no module side effects. Prototype modules that register things at import time
  (`registerAbilityHandler('manualDesync', …)` in sim.ts, `registerSelfWeapons()` in
  weapons/index.ts, `registerProjectileArchetype(BOLT)` / `(SHOCK)`, the enemy registry) instead fill
  their registry lazily: the registry's getter calls a private `_ensure_defaults()` that registers
  the built-ins once (see §3 "Registries"). `ODCore.ensure_registered()` forces all of them; the game
  calls it once on the main thread before resolving on a worker thread.

### Functions

- `camelCase` → `snake_case`, **same argument order**, same defaults. `createSim(config)` →
  `ODSim.create_sim(config)`; `tapePhaseAt(tape, sub)` → `ODTime.tape_phase_at(tape, sub)`.
- `Pick<LevelDef, 'bpm'>` / `Pick<Tape, …>` parameters take the full class (`LevelDef`, `ODTape`).
- Optional trailing `out` parameters stay (`sample_pose_into(tape, tick, out)`); reuse scratch objects
  in hot paths instead of allocating.
- **Exceptions**: GDScript has none. A function that throws in the prototype returns `null` (or a
  documented failure value) and appends the message to a trailing `errors: Array[String] = []`
  parameter (`ODGrid.parse_grid(map, errors)`, `ODTape.from_dict(d, errors)`). Keep the prototype's
  message text.
- Closures / function-typed fields (`AbilityHandler`, behaviour hooks) become `Callable` or virtual
  methods on a base class (§3).

### Data and types

| TypeScript | GDScript |
|---|---|
| `number` | `float`, except fields documented as integers (ticks, substeps, counts, indices, tile `c`/`r`, hp) → `int` |
| `Vec2`, `{x, y}` | `Vector2` (sim axes). Tile cells `{c, r}` → `Vector2i(c, r)` |
| `TapeIndex` | `int` 0..3; optional/null → **-1** |
| `TapeSpeed` | `float` (0.5, 1.0, 2.0, 4.0); null (DeckView.speed) → **0.0** |
| `Float32Array` / `Uint8Array` | `PackedFloat32Array` (gives float32 rounding like `Math.fround`) / `PackedByteArray` |
| `T[]` | typed `Array[T]`; `number[]` → `Array[float]` (or `Array[int]` for integer data); hot numeric buffers → packed arrays |
| `Map<string, V>` / `Record<string, V>` | typed `Dictionary[String, V]` (Godot dictionaries iterate in insertion order, like JS Maps) |
| `Set<string>` | `Dictionary[String, bool]` (value always `true`) |
| ids (entity, signal, gear, level ids) | `String` |
| closed vocabularies (string unions) | `StringName` constants (§2) |
| `Math.fround(x)` | write into a `PackedFloat32Array`, or `PackedFloat32Array([x])[0]` |
| optional field | see "Optional fields" |

**Optional fields.** Where absence means a fixed default (`facing ?? 0`, `initial === true`), the
field just holds that default and `to_dict()` omits it at that value. Where absence changes behaviour
(`EnemyDef.hp`, `.beat`, `.arc`, `CoreDef.threshold`, `RangedWeaponDef.radius`/`minRange`,
`ActorSnap.spark`, `EnemySnap.shield`/`bossRecallAt`, `MechSnap.t`, `SimEvent.dir`/`power`,
`BossObservation.actions`, `CampaignLevelEntry.loot`) there is a `has_<field>: bool` next to it.
Optional objects are `null` (`EnemyDef.wake_when`, `GearItem.mods/melee/ranged/look`,
`SimConfig.live/boss_memory`, `ObjectiveDef.when_expr`). Optional strings are `""`, optional
TapeIndex `-1`, optional enums `-1`.

**Renamed fields** (GDScript keywords / global functions): `RangedWeaponDef.range` → `max_range`,
`ObjectiveDef.when` → `when_expr`, `SignalExpr {const}` → `value`, `ThemePalette.floor` →
`floor_color`. Every other field is the prototype name in snake_case
(`horizonBars` → `horizon_bars`, `maxHp` → `max_hp`, `stateT` → `state_t`).

**JSON.** Every class that is loaded from or saved to JSON (levels, gear, save data, tapes, sim
output for goldens) has `static func from_dict(d) -> T` and `func to_dict() -> Dictionary` using the
prototype's camelCase keys and string spellings, so prototype JSON loads unchanged. `from_dict` is
lenient (missing keys → defaults) except where it validates (tapes, signal expressions, level
entities: `errors` parameter). Use `ODJson` (core/types/od_json.gd) for reading values and
`ODJson.stringify()` for writing: Godot 4.4's `JSON.stringify` rounds nested floats to 15 digits.
`ODJson.deep_equal` / `first_difference` compare JSON values with int == float. Every data class has
`copy()` (deep unless documented) where the prototype copies.

### Determinism and performance

As docs/GODOT-PORT.md: no `randf`, no `Time`, no dictionary-order dependence beyond insertion order,
same evaluation order as the prototype. Avoid per-substep allocation; reuse scratch objects; cache
lookups (`OD.subs_per_local_tick` is cheap but call sites in loops should hoist it).

## 2. Unions and enums

Two closed sets that are compared in hot loops and stored compactly are **int enums on `OD`**, with
name helpers for JSON:

| TypeScript | GDScript | JSON helpers |
|---|---|---|
| `EndMode` | `OD.EndMode { STOP, REPEAT, REVERSE }` (fields typed `int`) | `OD.end_mode_name(m)`, `OD.end_mode_from_name(s)` (-1 if unknown), `OD.ALL_END_MODES`, `OD.END_MODE_NAMES` |
| `LifeState` | `OD.LifeState { ALIVE, REC_GHOST, GHOST }` | `OD.life_state_name`, `OD.life_state_from_name` |
| `SignalExpr` op | `SignalExpr.Op { SIG, NOT, AND, OR, XOR, CONST, BEAT }` | (see below) |

Every other string union is a class of `StringName` constants whose values are the prototype
spellings (`AnimState.LIGHT_WINDUP == &"lightWindup"`), with `ALL: Array[StringName]` in prototype
order and `static func has(v)`. Compare with `==` (StringName vs StringName is a pointer compare).

| TypeScript union | GDScript class (file) |
|---|---|
| `ActionKind` | `ActionKind` (core/types/action_kind.gd) — `ALL` is the SerializedTape kind-index order |
| `AnimState` | `AnimState` — `ALL == OD.ANIM_STATES`; tape `anim` byte i ⇔ `OD.ANIM_STATES[i]` |
| `GearSlot` | `GearSlot` — `ALL == OD.GEAR_SLOTS` |
| `AbilityId` | `AbilityId` |
| `MeleeWeaponDef.style` | `MeleeStyle` |
| `RangedArchetype` + `'bolt' \| 'shock'` (ProjectileArchetypeId) | `RangedArchetype` (`SELF` = the five self weapons) |
| `Theme` | `LevelTheme` |
| `EnemyType` | `EnemyType` |
| `EnemySnap['state']` / `EnemyStateName` | `EnemyStateName` |
| `EntityDef['kind']` | `EntityKind` |
| `DecorDef['type']` | `DecorType` |
| `ObjectiveDef['type']` | `ObjectiveType` |
| `TrackMusicDef['role']` | `MusicRole` |
| `MechSnap['kind']` | `MechKind` |
| `SimEventType` | `SimEventType` (open-ended: add members, never rename) |
| `FailReason` | `FailReason` (`&""` = none) |
| `SessionPhase`, `DeckStatus`, `SessionAction` | same names |
| `'death' \| 'desync' \| 'resync'` (DeckView.stateMarks kind, deckEvent extras) | `StateMarkKind` |
| `ViewMode`, `Screen`, `UiIntent['type']` | `ViewMode`, `UiScreen`, `UiIntentType` (game/contracts/) |
| small module-local unions (`BoundaryKind`, `RecallReason`, `HitVerdict`, `HitResponse.kind`, quality, tones…) | `StringName` constants on the owning class (`ODTime.BOUNDARY_WRAP`, `BossMemoryLib.REASON_DWELL`, `ProjectileArchetype.VERDICT_STOP`, `HitResponse.KIND_BLOCK`) |

**SignalExpr** (recursive union) is one class with an `op` tag: `{sig}` → `Op.SIG` + `sig`;
`{not}` → `Op.NOT` + `args[0]`; `{and}` / `{or}` → `args` (any length); `{xor}` → `args[0..1]`;
`{const}` → `Op.CONST` + `value`; `{beat:{every,from,to}}` → `Op.BEAT` + `every`, `from`, `to`.
Build with `SignalExpr.of_sig/of_not/of_and/of_or/of_xor/of_const/of_beat`; evaluate with
`ODSignals.eval_signal(expr, signals, master_beat)` and `match expr.op`.

**EntityDef** (discriminated union) is a base class `EntityDef` (`kind`, `id`) with subclasses
`EnemyDef, DoorDef, SwitchDef, PlateDef, BreakableDef, LaserDef, CoreDef, ExitDef, DecorDef`.
Narrow with `if e is DoorDef:` / `e as DoorDef` (or compare `e.kind`). Parse one with
`LevelDef.entity_from_dict(d, errors)`; `level.entities_of(EntityKind.DOOR)` filters in order.

**Other unions with payloads**: `ProjectileSnap.owner` / `ProjectileOwner` / `StrikeSource` →
explicit fields (`owner_tape: int = -1`, `owner_enemy: String = ""`, and for StrikeSource also
`env: String = ""`); `UiIntent` → one class with `type` + payload fields; `HitResponse` → class with
`kind` + `reason` + `strike`.

## 3. Name map

### types.ts → `core/types.gd` + `core/types/*.gd` (done; owned by the skeleton)

| TypeScript | GDScript class | file |
|---|---|---|
| constants `SUB_HZ, LOCAL_HZ, BEATS_PER_BAR, FRAME_SUBS, TAPE_COUNT, ALL_SPEEDS, ANIM_STATES, GEAR_SLOTS, TAPE_COLORS, TAPE_NAMES`, `subsPerLocalTick()` | `OD` (`OD.SUB_HZ`, `OD.subs_per_local_tick(speed) -> int`; plus `OD.TAPE_COLORS_RGB`, `OD.tape_color(i)`, `OD.tape_letter(i)`, `OD.is_speed(s)`) | core/types.gd |
| `Vec2` | `Vector2` | — |
| `PlayerInput` | `PlayerInput` | core/types/player_input.gd |
| `TapeEvent` | `TapeEvent` (+ `to_tuple`/`from_tuple` for SerializedTape) | core/types/tape_event.gd |
| `Tape` (+ `SerializedTape` as `to_dict`/`from_dict`) | `ODTape` | core/types/od_tape.gd |
| `TapePhase` | `TapePhase` (`dir: int` 1/-1/0) | core/types/tape_phase.gd |
| `StatMods` (also `Required<StatMods>`) | `StatMods` (fields default to identity) | core/types/stat_mods.gd |
| `MeleeSwingDef`, `MeleeWeaponDef`, `RangedWeaponDef` | same names | core/types/melee_swing_def.gd, melee_weapon_def.gd, ranged_weapon_def.gd |
| `GearItem`, `GearItem.look` | `GearItem`, `GearLook` | core/types/gear_item.gd, gear_look.gd |
| `Loadout` (`Record<GearSlot,string>`) | `Loadout` (`get_slot(slot)`, `set_slot(slot, id)`, `ids()`) | core/types/loadout.gd |
| `ResolvedLoadout` (`looks` → `Dictionary[StringName, GearLook]`) | `ResolvedLoadout` (`has_ability(id)`) | core/types/resolved_loadout.gd |
| `MapRows` | `Array[String]` | — |
| `SignalExpr` | `SignalExpr` | core/types/signal_expr.gd |
| `EntityDef` and the nine defs | `EntityDef`, `EnemyDef`, `DoorDef`, `SwitchDef`, `PlateDef`, `BreakableDef`, `LaserDef`, `CoreDef`, `ExitDef`, `DecorDef` | core/types/<snake>.gd |
| `ObjectiveDef` | `ObjectiveDef` (`when` → `when_expr`) | core/types/objective_def.gd |
| `TrackMusicDef`, `LevelMusicDef` | same | core/types/track_music_def.gd, level_music_def.gd |
| `LevelDef` (`hints` → `Dictionary[int, String]`, 1-based tape numbers) | `LevelDef` | core/types/level_def.gd |
| `ActorSnap`, `EnemySnap`, `ProjectileSnap`, `MechSnap`, `ObjectiveSnap`, `FrameSnapshot` | same (`FrameSnapshot.actor(tape)`, `.enemy(id)`, `.mech(id)`) | core/types/<snake>.gd |
| `SimEvent` | `SimEvent` (`SimEvent.make(sub, type, x, y).with_tape(i).with_id(s).with_dir(d).with_power(p).with_detail(s)`) | core/types/sim_event.gd |
| `Outcome` | `Outcome` | core/types/outcome.gd |
| `BossMemory`, `observed[]`, `samples[]`, `BossMemoryAction` | `BossMemory`, `BossObservation`, `BossSample`, `BossMemoryAction` | core/types/<snake>.gd |
| `SimConfig`, `SimConfig.live` | `SimConfig` (`copy()` shallow, `without_live()`, `deep_copy()`), `LiveTake` | core/types/sim_config.gd, live_take.gd |
| `ISim` | implemented by `ODSim` (no separate interface) | core/sim.gd |
| `Resolution` | `Resolution` (`frame_at_sub(sub)`) | core/types/resolution.gd |
| `DeckView`, `marks[]`, `stateMarks[]` | `DeckView`, `DeckMark`, `DeckStateMark` | core/types/<snake>.gd |
| `SessionView`, `SessionView.objective` | `SessionView`, `ObjectiveView` (extends ObjectiveSnap, adds `text`) | core/types/session_view.gd, objective_view.gd |
| `SaveData`, `SaveData['settings']` | `SaveData`, `SaveSettings` (`get_by_key`/`set_by_key` with prototype keys) | core/types/save_data.gd, save_settings.gd |
| JSON helpers | `ODJson` | core/types/od_json.gd |

### Module files (to be ported)

`[inner]` = inner class of the module class; everything else is a top-level `class_name`.

| Prototype file | GDScript file | class_name | Exported members (snake_case, statics unless noted) |
|---|---|---|---|
| core/time.ts | core/time.gd | `ODTime` | `ticks_per_beat, subs_per_beat, tape_ticks, horizon_subs, sub_to_beat, beat_to_sub, sub_to_seconds, subs_per_local_tick` (= `OD.subs_per_local_tick`), `local_tick_to_sub, sub_to_local_tick, traversal_subs, span_bars, tape_phase_at, tape_phase_into, collect_event_crossings, event_crossings, collect_boundaries`, `ALL_END_MODES` (= `OD.ALL_END_MODES`), `BOUNDARY_END/WRAP/TURN`; `[inner] EventCrossing, TapeBoundary` |
| core/grid.ts | core/grid.gd | `ODGrid` | class `Grid` itself; `TILE_WALL … TILE_RUNE`, `TILE_CHARS`, `is_floor_kind, parse_grid(map, errors) -> ODGrid` (null on MapParseError), `segment_box_dist2`; `[inner] MoveOpts, MoveResult, RayHit` |
| core/path.ts | core/path.gd | `Pathfinder` | class; `path_length`; `[inner] PathOpts, PathResult` |
| core/tape.ts | core/tape.gd | `TapeLib` | `anim_index, anim_from_index, wrap_angle, angle_delta, lerp_angle, sample_pose, sample_pose_into, sample_pose_at_sub, sample_pos_into, local_velocity_at, master_velocity_at, clone_tape` (= `tape.copy()`), `with_end_mode, tapes_equal, serialize_tape` (= `tape.to_dict()`), `deserialize_tape(s, errors)` (= `ODTape.from_dict`), `base64_from_bytes, bytes_from_base64`; `[inner] PoseSample, TapeRecorderInit` |
| core/tape.ts (class TapeRecorder) | core/tape_recorder.gd | `TapeRecorder` | class |
| core/player.ts | core/player.gd | `PlayerController` | class; `ACTIVE_ABILITIES, action_timing, melee_hit_window, dodge_iframe_window, ranged_launch_tick, effect_tick, interact_radius, run_speed, action_anim, idle_input`; `[inner] ActionTiming, TickWindow, PlayerPose, PlayerStepResult, PlayerStart` |
| core/signals.ts | core/signals.gd | `ODSignals` | `eval_signal(expr, signals: Dictionary[String, bool], master_beat)`, `in_beat_window, collect_signal_ids(expr, out: Dictionary[String, bool] = {})`, `is_timed_expr, format_signal_expr`. `SignalTable` = `Dictionary[String, bool]` |
| core/tuning.ts | core/tuning.gd | `Tuning` | `static var BASE: Tuning.BaseStats` (fields snake_case: `BASE.actor_radius`), `neutral_mods() -> StatMods` (`NEUTRAL_MODS` = `StatMods.new()`), `COLLISION_SKIN, DESYNC_PENETRATION_TOLERANCE, DAMAGE_UNIT, APPROACH_MIN, APPROACH_MAX, TUTORIAL_WALL_THRESHOLD, DEFAULT_CORE_THRESHOLD, KNOCKBACK_SECONDS, WALL_SLAM_STAGGER_PER_TILE, SHIELDER_WINDOW_BEATS, DRONE_KEEP_DISTANCE, ENEMY_SHOT_RADIUS, SELF_SHOT_RADIUS, ARC_PEAK_HEIGHT, ARC_MIN_BLAST`, `strike_approach, strike_momentum, swing_momentum, strike_damage, strike_knockback, strike_stagger`, `enemy_stats(type: StringName) -> Tuning.EnemyStats` (`ENEMY_STATS` as `static var ENEMY_STATS: Dictionary[StringName, Tuning.EnemyStats]`); `[inner] BaseStats, EnemyStats` |
| core/sim.ts | core/sim.gd | `ODSim` | class `Sim` (also the `World` interface: subsystems take `w: ODSim`); `create_sim(config) -> ODSim`, `register_ability_handler(id: StringName, handler: Callable)` where handler is `func(w: ODSim, self_actor: SelfActor, ev: TapeEvent, pass_dir: int) -> void`; ISim members as methods/properties: `config, sub, horizon_subs, tape_ticks, local_tick, done, step_local_tick(input), step_sub(), snapshot() -> FrameSnapshot, drain_events() -> Array[SimEvent], live_tape() -> ODTape, outcome() -> Outcome, threat_beats(look_ahead_beats := 8.0) -> Array[float]` |
| core/actors.ts | core/actors.gd | `SelfActor` | class; `OBSTRUCTION_RADIUS, STRIDE, is_obstructed, begin_desync, step_spark`; `[inner] SubWindow, ActiveSwing, ScheduledEffect, SparkState` |
| core/combat.ts | core/combat.gd | `Combat` | `apply_strike, melee_momentum, open_swing, in_swing_volume, resolve_swings, core_threshold, CORE_RADIUS` |
| core/combat.ts (types) | core/enemy_strike.gd, core/strike_source.gd, core/self_hit.gd, core/hit_response.gd | `EnemyStrike`, `StrikeSource`, `SelfHit`, `HitResponse` | owned by the combat porter. `EnemyStrike` optional `damage/knockback/stagger` → `has_*` flags, `melee: bool`. `HitResponse.KIND_APPLY/BLOCK/REPLACE` + `HitResponse.apply()`, `.block(reason)`, `.replace(strike)` |
| core/combat.ts (class) | core/combat_queue.gd | `CombatQueue` | class |
| core/mechanisms.ts | core/mechanisms.gd | `Mechanisms` | class; `DOOR_TRAVEL_SUBS`; per-kind state records as `[inner]` (`Mechanisms.DoorState`, …) |
| core/objective.ts | core/objective.gd | `ObjectiveTracker` | class; `tape_name(t)` ("Tape A"), `format_beat(w, sub)`, `build_outcome(w, tracker, level)`; `[inner] DeathRecord, DesyncRecord, ResyncRecord, WeakHitRecord, KillRecord` |
| core/objective.ts (class) | core/run_log.gd | `RunLog` | class |
| core/resolve.ts | core/resolve.gd | `ODResolve` | `resolve_encounter(config: SimConfig) -> Resolution` (ignores `config.live`) |
| core/projectiles.ts | core/projectiles.gd | `ProjectileSystem` | class; `register_projectile_archetype(a), get_projectile_archetype(id) -> ProjectileArchetype` (lazy defaults: BOLT, the five self weapons, SHOCK), `fly_straight, default_hit_enemy, spawn_bolt, BOLT_RANGE, BOLT_ENEMY_STAGGER` |
| core/projectiles.ts (types) | core/projectile.gd, core/spawn_spec.gd, core/projectile_archetype.gd | `Projectile`, `SpawnSpec`, `ProjectileArchetype` | owned by the projectiles porter. `ProjectileArchetype` is a base class with `id: StringName`, `VERDICT_STOP/PASS` and virtual hooks whose defaults are exactly the prototype's behaviour when the hook is absent: `launch(w, self_actor, ev, pass_dir) -> int` (default: launches nothing, returns 0), `step(w, p)` (no-op), `on_hit_enemy(w, p, e) -> StringName` (default `ProjectileSystem.default_hit_enemy`), `on_hit_self(w, p, self_actor)` (default `VERDICT_PASS`), `on_hit_wall(w, p, hit: ODGrid.RayHit)` (default `VERDICT_STOP`), `on_expire(w, p)` (no-op); callers invoke them unconditionally. `Projectile.struck` → `Dictionary[String, bool]`, `data` → `Dictionary[String, float]` |
| core/abilities.ts | core/abilities.gd | `Abilities` | `LOW_PROFILE_FACTOR, LOUDMOUTH_FACTOR, MANUAL_DESYNC_CAUSE, SLIDE_STRIKE_MUL, SLIDE_STRIKE_WINDOW_TICKS, BEAT_SIGHT_LOOKAHEAD_BEATS, effective_distance, manual_desync, slide_strike_factor, parry_projectiles, upcoming_attack_beats` |
| core/bossMemory.ts | core/boss_memory.gd | `BossMemoryLib` | `REMEMBERED_ACTIONS, BOSS_DWELL_RADIUS, BOSS_DWELL_BEATS, build_boss_memory(level, committed: Array[ODTape]) -> BossMemory, recall_candidates(memory) -> Array[BossMemoryLib.RecallCandidate]`, `REASON_DWELL/ATTACK`; `[inner] RecallCandidate` |
| core/index.ts | core/index.gd | `ODCore` | facade statics forwarding to the modules (`create_sim, resolve_encounter, build_boss_memory, recall_candidates, tape_phase_at, horizon_subs, tape_ticks, sub_to_beat, subs_per_beat, ticks_per_beat, beat_to_sub, span_bars, traversal_subs, register_enemy_behaviour, get_enemy_behaviour, registered_enemy_types, register_projectile_archetype, get_projectile_archetype, fly_straight, default_hit_enemy, register_ability_handler`) and `ensure_registered()` |
| core/enemies/types.ts | core/enemies/enemy_state.gd, core/enemies/enemy_behaviour.gd | `EnemyState`, `EnemyBehaviour` | `EnemyState` per the interface (`target: int = -1`, `path: Array[Vector2]`, `mem: Dictionary[String, Variant]`). `EnemyBehaviour` base class: `type: StringName`, `heavy_body: bool`, `hovering: bool`, virtual `init(w, e)`, `on_beat(w, e, beat)`, `step(w, e)`, `on_hit(w, e, strike) -> HitResponse` (default `HitResponse.apply()`), `on_death(w, e)`, `snapshot(w, e, snap)`; optional hooks default to no-ops (the framework calls them unconditionally) |
| core/enemies/registry.ts | core/enemies/registry.gd | `EnemyRegistry` | `register_enemy_behaviour(b), has_enemy_behaviour(type), get_enemy_behaviour(type) -> EnemyBehaviour, registered_enemy_types() -> Array[StringName]` (lazy defaults: the seven built-ins) |
| core/enemies/common.ts | core/enemies/common.gd | `EnemyCommon` | `ENEMY_REPLAN_SUBS, create_enemy_state, set_state, step_enemies, is_grid_sub, next_grid_sub, telegraph_subs, targetable, perceived_distance, nearest_target, self_by_index, walk_toward, apply_knockback, apply_stagger, describe_source, kill_enemy, enemy_snapshot` |
| core/enemies/grunt.ts | core/enemies/grunt.gd | `GruntBehaviour` (extends EnemyBehaviour) | `GRUNT_ARC, GRUNT_RECOVER_BEATS`; the prototype's `GRUNT` constant = `GruntBehaviour.new()` |
| core/enemies/stalker.ts | core/enemies/stalker.gd | `StalkerBehaviour` | `STALKER_ARC, STALKER_RECOVER_BEATS, STALKER_COMMIT_RANGE, melee_strike, farthest_target`; `MeleeProfile` → `[inner] StalkerBehaviour.MeleeProfile` |
| core/enemies/stalker.ts (`meleeChaser`) | core/enemies/melee_chaser.gd | `MeleeChaser` (extends EnemyBehaviour) | base implementing `on_beat`/`step` from a `StalkerBehaviour.MeleeProfile`; grunt-like chasers (stalker, brute, shielder) extend it. Owned by the stalker porter |
| core/enemies/turret.ts | core/enemies/turret.gd | `TurretBehaviour` | `TURRET_RECOVER_BEATS` |
| core/enemies/shielder.ts | core/enemies/shielder.gd | `ShielderBehaviour` | `SHIELDER_ARC, SHIELDER_RECOVER_BEATS, shield_window_subs, shield_down_at` |
| core/enemies/brute.ts | core/enemies/brute.gd | `BruteBehaviour` | `BRUTE_ARC, BRUTE_RECOVER_BEATS, BRUTE_POISE_MOMENTUM` |
| core/enemies/drone.ts | core/enemies/drone.gd | `DroneBehaviour` | `DRONE_KEEP_BAND, DRONE_RECOVER_BEATS, DRONE_OFFBEAT, hover_solid_at, hover_move, is_drone_fire_sub` |
| core/enemies/boss.ts | core/enemies/boss.gd | `BossBehaviour` | `BOSS_*` constants, `boss_phase_for, boss_attention`; the SHOCK archetype → core/enemies/shock_archetype.gd `ShockArchetype` (extends ProjectileArchetype), registered lazily by ProjectileSystem |
| core/weapons/common.ts | core/weapons/common.gd | `WeaponCommon` | `RANGED_EFFICIENCY, EDGE_MARGIN, shot_speed, shot_radius, pierce_count, self_shot, projectile_strike, detonate, hit_enemy_straight, hit_wall_straight, owner_tape, distance_to_edge` |
| core/weapons/index.ts | core/weapons/index.gd | `Weapons` | `self_weapons() -> Array[ProjectileArchetype]` (`SELF_WEAPONS`), `register_self_weapons()` |
| core/weapons/missile.ts | core/weapons/missile.gd | `MissileArchetype` (extends ProjectileArchetype) | `acquire_nearest_enemy` |
| core/weapons/pierce.ts | core/weapons/pierce.gd | `PierceArchetype` | — |
| core/weapons/phase.ts | core/weapons/phase.gd | `PhaseArchetype` | — |
| core/weapons/arc.ts | core/weapons/arc.gd | `ArcArchetype` | `arc_height, arc_blast` |
| core/weapons/burst.ts | core/weapons/burst.gd | `BurstArchetype` | `burst_headings` |
| (projectiles.ts BOLT) | core/bolt_archetype.gd | `BoltArchetype` | owned by the projectiles porter |

Note on `self`: GDScript reserves `self`. Prototype parameters named `self` become `self_actor`.

### Registries

| Registry | Owner | Lazily registers |
|---|---|---|
| `EnemyRegistry` | core/enemies/registry.gd | Grunt, Stalker, Turret, Shielder, Brute, Drone, Boss behaviours |
| `ProjectileSystem.get_projectile_archetype` | core/projectiles.gd | `BoltArchetype`, `Weapons.register_self_weapons()`, `ShockArchetype` |
| `ODSim.register_ability_handler` | core/sim.gd | `AbilityId.MANUAL_DESYNC` → `Abilities.manual_desync` |

### Content (`prototype/src/content` → `content/`)

| Prototype | GDScript file | class_name |
|---|---|---|
| (data loading; the prototype compiled data in) | content/data.gd | `ContentData` (done): `load_gear(errors) -> ContentData.GearCatalogue`, `load_level(id, errors) -> LevelDef`, `list_level_ids(include_extra := false, errors) -> Array[String]`, `load_campaign(errors) -> Array[LevelDef]` |
| content/index.ts (`LEVELS, SANDBOX, GEAR, BASE_LOADOUT, BASE_INVENTORY` + re-exports) | content/content.gd | `Content` — cached statics `levels()`, `sandbox()`, `gear() -> ContentData.GearCatalogue`, `base_loadout()`, `base_inventory()` |
| content/loadout.ts | content/loadout.gd | `LoadoutRules` — `is_additive_stat, identity_mods, combine_mods, resolve_loadout, describe_loadout, is_baseline, items_for_slot, sanitise_loadout, SLOT_LABEL, STAT_LABEL, ABILITY_TEXT` |
| content/validate.ts | content/validate.gd | `LevelValidator` — `is_problem, validate_level, validate_campaign` |

### Facades (`prototype/src/contracts.ts` → `game/contracts/`, done)

See docs/GODOT-PORT.md "Module facades": `WorldViewBase, RenderLayerBase, ActorLayerBase, FxLayerBase,
RenderCtx, ThemePalette, MusicReactive, PostControls, RenderFrame, MusicPulse, AudioBase,
TrackAudioState, UiBase, HudBase, UiIntent, UiIntentType, UiScreen, ViewMode, ButtonPrompt,
LoadoutScreenModel, CampaignScreenModel, CampaignLevelEntry, ResultsModel, Facades`.

### Tests

`ODTest` (tests/od_test.gd), runner tests/run_tests.gd. Golden suites live in `tests/goldens/` with
`test_*.gd` files beside their JSON.

## 4. Reserved class_names (do not reuse)

Taken now: `OD, ODJson, ODTape, PlayerInput, TapeEvent, TapePhase, StatMods, MeleeSwingDef,
MeleeWeaponDef, RangedWeaponDef, GearLook, GearItem, Loadout, ResolvedLoadout, SignalExpr, EntityDef,
EnemyDef, DoorDef, SwitchDef, PlateDef, BreakableDef, LaserDef, CoreDef, ExitDef, DecorDef,
ObjectiveDef, TrackMusicDef, LevelMusicDef, LevelDef, ActorSnap, EnemySnap, ProjectileSnap, MechSnap,
ObjectiveSnap, ObjectiveView, FrameSnapshot, SimEvent, Outcome, BossMemory, BossObservation,
BossSample, BossMemoryAction, LiveTake, SimConfig, Resolution, DeckView, DeckMark, DeckStateMark,
SessionView, SaveSettings, SaveData, ActionKind, AnimState, GearSlot, AbilityId, MeleeStyle,
RangedArchetype, LevelTheme, EnemyType, EnemyStateName, EntityKind, DecorType, ObjectiveType,
MusicRole, MechKind, SimEventType, FailReason, SessionPhase, DeckStatus, SessionAction, StateMarkKind,
ContentData, ODTest`, and the facade classes above.

Reserved for porters (exactly as in §3): `ODTime, ODGrid, Pathfinder, TapeLib, TapeRecorder,
PlayerController, ODSignals, Tuning, ODSim, SelfActor, Combat, EnemyStrike, StrikeSource, SelfHit,
HitResponse, CombatQueue, Mechanisms, ObjectiveTracker, RunLog, ODResolve, ProjectileSystem,
Projectile, SpawnSpec, ProjectileArchetype, BoltArchetype, Abilities, BossMemoryLib, ODCore,
EnemyState, EnemyBehaviour, EnemyRegistry, EnemyCommon, GruntBehaviour, StalkerBehaviour,
MeleeChaser, TurretBehaviour, ShielderBehaviour, BruteBehaviour, DroneBehaviour, BossBehaviour,
ShockArchetype, WeaponCommon, Weapons, MissileArchetype, PierceArchetype, PhaseArchetype,
ArcArchetype, BurstArchetype, Content, LoadoutRules, LevelValidator`.

Modules outside core (audio/, world/, actors/, fx/, ui/, game/) prefix new class_names with their area
when a name could be generic (`AudioDirector`, `WorldKit`, `HudDeck`, `GameSession`) and never take a
name from this list.

## 5. Foundation port notes (time, grid, path, tape, player, signals, tuning)

Appended by the foundation porter. Symbols the table in §3 did not fix, and the exact signatures:

- **ODTime**: `ticks_per_beat(level) -> float`, `subs_per_beat(level) -> float`, `tape_ticks(level) -> int`,
  `horizon_subs(level) -> int`, `traversal_subs(tape) -> int`, `local_tick_to_sub(speed, tick) -> float`,
  `sub_to_local_tick`, `sub_to_beat`, `beat_to_sub`, `sub_to_seconds`, `span_bars` -> float. Sub arguments
  are `float` (ints convert). `EventCrossing {event, index, sub: int, dir: int, traversal}` and
  `TapeBoundary {kind: StringName, sub: int, traversal, dir}` have `make(...)`. `SUBS_PER_TICK_1X`.
  `collect_event_crossings(tape, sub_a, sub_b, out: Array[ODTime.EventCrossing])`,
  `collect_boundaries(tape, sub_a, sub_b, out: Array[ODTime.TapeBoundary])` append to `out`.
- **ODGrid**: `ODGrid.new(cols, rows, tiles: PackedByteArray)`; validated `create(cols, rows, tiles, errors)`;
  `parse(map, errors, parse_error: ODGrid.MapParseError = null)` (also `parse_grid`, `from_level(level, errors,
  parse_error)`); `MapParseError {failed, message, c, r}` is filled instead of thrown. `revision` is a read-only
  property. Extras: `line_of_sight_xy(ax, ay, bx, by)` (64-bit; `line_of_sight(a: Vector2, b: Vector2)` goes
  through 32-bit Vector2), `fill_walk_mask(out)` (packed walkability mask with a 1-tile border, used by
  Pathfinder), `MOVE_STEP`, `MoveOpts.make(ignore_low)`, `_to_string()` (= prototype `toString`, via
  `to_string()`), and **`ODGrid.hypot(x, y)`**: Math.hypot exactly as V8 computes it. Use it wherever the
  prototype calls Math.hypot (naive `sqrt(x*x + y*y)` differs in the last bit for ~40% of inputs; Vector2
  `.length()` is 32-bit).
- **Pathfinder**: `Pathfinder.new(grid)`; `find_tile_path(...) -> Array[int]`, **empty = the prototype's null**;
  `find_path(sx, sy, tx, ty, opts: Pathfinder.PathOpts = null) -> Pathfinder.PathResult` (null when no
  route); `PathOpts.make(allow_partial := false, smooth := true).with_radius(r)` (`has_radius` false =
  `Tuning.BASE.spark_radius`); `PathResult {points: Array[Vector2], complete, cost}`; `component_of`,
  `has_route`, `has_route_between(a: Vector2, b: Vector2)`, `smooth(sx, sy, points, radius)`, `last_expanded`,
  `SQRT2`, `NDC`, `NDR`, static `path_length(sx, sy, points)`. `find_path` keeps waypoints 64-bit through
  smoothing and rounds to Vector2 only in the result, so its waypoint choice matches the prototype exactly.
- **TapeLib**: `XY {x, y}` (`XY.make(x, y)`) is the prototype's `{x, y}` out-parameter (Vector2 is a value
  type); `PoseSample extends XY` + `facing`, `anim: StringName` (`make_pose`, `equals`, `copy`).
  `sample_pos_into(tape, tick, out: XY)`, `local_velocity_at(tape, tick, out: XY = null) -> XY`,
  `master_velocity_at(tape, tick, dir: int, out: XY = null) -> XY`, `sample_pose_at_sub(tape, sub, out = null,
  phase_out: TapePhase = null)`. `TapeRecorderInit.make(index, speed, end_mode, ticks, x, y, facing, anim :=
  &"idle")`. `anim_index(anim) -> int` (-1 if not an AnimState). `bytes_from_base64(s, errors) ->
  PackedByteArray` (empty + error on bad input). `lerp_angle` shadows the global: call `TapeLib.lerp_angle`.
- **TapeRecorder**: `TapeRecorder.new(init)` / validated `create(init, errors)`; `push(x, y, facing, anim,
  errors := []) -> bool`, `add_event(ev, errors := []) -> bool` (false + prototype message instead of a throw);
  `recorded_ticks`, `complete` are read-only properties; `snapshot()`, `finish()` -> ODTape.
- **PlayerController**: `PlayerController.new(PlayerController.PlayerStart.make(x, y, facing := 0))`;
  `step(input, grid, loadout, life: int)` (OD.LifeState); read-only properties `tick`, `pose` (fresh
  `PlayerPose`), `action_kind` (&"" = none), `dodge_cooldown`, `ranged_cooldown`; `refresh_dodge()`.
  `action_timing(kind, loadout) -> ActionTiming` (int fields), `melee_hit_window` / `dodge_iframe_window`
  -> `TickWindow` or null, **`ranged_launch_tick` -> int, -1 = null**, `action_anim` -> &"" for null,
  `DT`, `PRESS_ORDER`.
- **ODSignals**: also `js_number(f)` (JS `String(n)` formatting for `format_signal_expr`).
- **Tuning**: `BaseStats` / `EnemyStats` (`EnemyStats.make(...)`) are inner classes; integer-valued base stats
  (`dodge_ticks`, `dodge_iframe_start`, `ranged_launch_delay`, `interact_ticks`, `input_buffer_ticks`,
  `spark_replan_subs`) are `int`; `EnemyStats.hp` is `int`; `strike_damage(...) -> int`. INF = Infinity.
- **Test helpers** (tests/helpers/): `TestLevels` (`OPEN_ROOM`, `default_music()`, `default_start(map)`,
  `make_level(partial: Dictionary = {})`, keys snake_case or camelCase) and `TestLoadout` (`base_melee()`,
  `base_missile()`, `base_loadout(patch: Dictionary = {})` with `mods` / `abilities` / `melee` / `ranged`).
  Both class_names are reserved.
- **Engine facts the port relies on** (measured on 4.4.1): packed arrays assigned to a variable share storage
  (writes through a local reach the member: copy with `duplicate()` / `slice()`); GDScript float literals and
  probably `String.to_float` / JSON parsing are not always correctly rounded (`1.414213562373095e200` lands one
  ulp off), so exact fixtures should carry doubles as base64 Float64 bytes; `ODJson.format_float` writes
  magnitudes below ~1e-16 as `0.0`; Godot's sin/cos/atan2/exp (C runtime) differ from V8's fdlibm in the last
  bit for some inputs.

## 6. Traps port notes (core/traps/, docs/TRAPS.md)

Port of `prototype/src/core/traps/` (system.ts, dart.ts, live.ts, tuning.ts) and the trap additions to
types.ts / sim.ts. Additive: a level with no trap entities builds `Traps` with `count == 0`, every entry
point returns at once, and all 140 pre-trap goldens still match bit for bit.

- **Types** (core/types/): `TrapDef` (base, extends EntityDef) and `SpikesDef`, `CrusherDef`,
  `ConveyorDef`, `FlameDef`, `DartDef`, `BumperDef`, `SensorDef`, `RelayDef`, `MagnetDef`, parsed by
  `LevelDef.entity_from_dict`. Optional numbers are NAN when absent (`TrapDef.has_num`, `num_or`), optional
  directions / modes `&""`, optional expressions null; `to_dict()` writes back only what was given.
  `SensorDef` keeps its ends as 64-bit `from_x/from_y/to_x/to_y` (not Vector2). `Dir4` (`N/E/S/W`,
  `dx`, `dy`, `angle`).
- **Enums**: `EntityKind.SPIKES..MAGNET` are listed in `EntityKind.TRAPS`, not in `ALL` (tests/test_skeleton.gd
  pins ALL at the nine classic kinds); `EntityKind.has()` accepts both, `is_trap()` the trap kinds.
  `MechKind` gains the nine kinds, likewise in `MechKind.TRAPS` and not in `ALL` (the skeleton test pins
  ALL at seven); `MechKind.has()` accepts both. `RangedArchetype.DART` (in ALL). `SimEventType.TRAP` = "trap"
  is NOT in ALL, exactly like the prototype's TRAP_EVENT: tests/fx/test_fx_routing.gd needs an fx route for
  every ALL member and fx/fx_catalog.gd is the fx engineer's. `SimEventType.has(&"trap")` is true, so a
  `trap` route can be added first and TRAP moved into ALL with it.
- **MechSnap** gains `warn`, `dir`, `reach`, `firing`, each with a `has_*` flag and a `with_*` builder.
- **Traps** (core/traps/traps.gd): `Traps.new(level, grid, signals)`, `count`, `init(w)` (idempotent; the
  sim calls it before and after `Mechanisms.init`), `sense(w)` (phase 3b), `step(w)` (phase 4b),
  `owner_at(c, r) -> String` ("crusher cr1" or ""), `live_carry(w, x, y, subs) -> bool` (result in
  `carry_x` / `carry_y`), `snapshot(sub) -> Array[MechSnap]`; statics `point_seg_dist`, `crusher_dir`.
  Per-trap state is the inner class `Traps.TrapState`. The telegraph's FutureSignals is a scratch
  Dictionary (copied from the signal table, relay outputs overwritten per forecast instant) owned by the
  Traps instance. No static state.
- **DartArchetype** (core/traps/dart_archetype.gd) is registered by `ProjectileSystem._ensure_defaults`;
  `DartArchetype.spawn_dart(w, launcher, x, y, dir, speed)`. Owner = the launcher id (`owner_enemy`).
- **TrapTuning** (core/traps/trap_tuning.gd): every constant of tuning.ts; `BUMPER_FLIGHT_SUBS` is the
  literal 43 (= round(0.18 * 240)).
- **PlayerController.displace(x, y)**: the public setter the porting notes ask for (float32-rounded
  position, velocity untouched); `ODSim.step_local_tick` calls it with `Traps.live_carry`'s result.
- **ODSim**: field `traps`; the six hooks of TRAPS.md "Hooks in sim.ts" (construction + double init,
  live carry before the controller, `sense` after dispatch, `step` after mechanisms, trap snapshots
  appended after `mechs.snapshot()`, `owner_at` fallback in the desync cause). tools/bench_resolve.gd's
  profiled substep calls `sense` / `step` too (timed with the mechanisms).
- **Not ported here**: the level validator's trap rules (prototype `src/content/validate.ts` and
  `tests/core/traps/validate.test.ts`, 7 tests) belong to `content/validate.gd`, outside core.
- Tests: tests/core/traps/ (trap_kit.gd helper; test_trap_hazards / movers / signals / scenarios: the
  prototype's 66 simulation tests plus 2 port additions). Goldens: 22 `trap-*` scenarios.
