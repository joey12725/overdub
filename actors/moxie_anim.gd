class_name MoxieAnim
extends RefCounted
## Animation-progress rules for a self (prototype render/actors/pose.ts animDurationTicks /
## animProgress, plus the Godot clip mapping of the asset contract). Pure: unit-tested.
##
## Timed animations are scrubbed by the tape's own LOCAL tick, never free-run: tape speed changes how
## long a swing occupies master time but not its shape (TIME-03), and on a reverse pass the state is
## entered at its recorded end, so progress runs backwards and the motion visibly rewinds.
##
## Clips (docs/GODOT-PORT.md asset contract): loops `idle` (2.0 s), `run` (0.6 s, two steps),
## `stopped` (held pose); one-shots normalised to exactly 1.0 s: `light` and `heavy` (wind-up is the
## first 40 %, the hit 40-60 %, recovery the last 40 %), `dodge`, `ranged`, `interact`, `death`.

const CLIP_IDLE: StringName = &"idle"
const CLIP_RUN: StringName = &"run"
const CLIP_STOPPED: StringName = &"stopped"
const CLIP_LIGHT: StringName = &"light"
const CLIP_HEAVY: StringName = &"heavy"
const CLIP_DODGE: StringName = &"dodge"
const CLIP_RANGED: StringName = &"ranged"
const CLIP_INTERACT: StringName = &"interact"
const CLIP_DEATH: StringName = &"death"
const ALL_CLIPS: Array[StringName] = [CLIP_IDLE, CLIP_RUN, CLIP_STOPPED, CLIP_LIGHT, CLIP_HEAVY, CLIP_DODGE, CLIP_RANGED, CLIP_INTERACT, CLIP_DEATH]

const IDLE_SECONDS: float = 2.0
const RUN_SECONDS: float = 0.6
## Fractions of the melee clips (asset contract): wind-up 0-0.4, hit 0.4-0.6, recovery 0.6-1.0.
const WINDUP_END: float = 0.4
const ACTIVE_END: float = 0.6

## Local ticks of actions whose length is not on the loadout (prototype tuning.ts BASE).
const DODGE_TICKS: int = 14
const INTERACT_TICKS: int = 10
## Wall seconds the death transition takes before the ghost reading takes over.
const DEATH_SECONDS: float = 0.7
## Reference run speed, tiles per LOCAL second (tuning.ts BASE.runSpeed): normalises the run blend.
const RUN_SPEED: float = 4.5
## Tiles covered by one full run cycle (two steps) at full speed.
const STRIDE_TILES: float = RUN_SPEED * RUN_SECONDS


## player.ts ticksOf: timings are rounded to whole local ticks.
static func ticks_of(v: float) -> int:
	return roundi(v) if v > 0.0 else 0


## Local ticks a timed state lasts under the loadout; 0 for cyclic / held states.
static func duration_ticks(anim: StringName, melee: MeleeWeaponDef, ranged: RangedWeaponDef) -> int:
	match anim:
		AnimState.LIGHT_WINDUP:
			return maxi(1, ticks_of(melee.light.windup))
		AnimState.LIGHT_ACTIVE:
			return maxi(1, ticks_of(melee.light.active))
		AnimState.LIGHT_RECOVER:
			return maxi(1, ticks_of(melee.light.recover))
		AnimState.HEAVY_WINDUP:
			return maxi(1, ticks_of(melee.heavy.windup))
		AnimState.HEAVY_ACTIVE:
			return maxi(1, ticks_of(melee.heavy.active))
		AnimState.HEAVY_RECOVER:
			return maxi(1, ticks_of(melee.heavy.recover))
		AnimState.DODGE:
			return DODGE_TICKS
		AnimState.RANGED:
			return maxi(1, ticks_of(ranged.commit))
		AnimState.INTERACT:
			return INTERACT_TICKS
	return 0


## Progress 0..1 through a timed state entered at `entry_tick`, at playhead `tick`, moving in
## direction `dir` (+1 / -1 / 0). On a reverse pass (dir -1) the state was entered at its recorded
## end, so progress runs from 1 down to 0.
static func progress(entry_tick: float, tick: float, dir: int, duration: int) -> float:
	if duration <= 0:
		return 0.0
	var t := ActorMath.clamp01(absf(tick - entry_tick) / float(duration))
	return 1.0 - t if dir == -1 else t


## The clip that plays an anim state.
static func clip_for(anim: StringName) -> StringName:
	match anim:
		AnimState.RUN:
			return CLIP_RUN
		AnimState.STOPPED:
			return CLIP_STOPPED
		AnimState.LIGHT_WINDUP, AnimState.LIGHT_ACTIVE, AnimState.LIGHT_RECOVER:
			return CLIP_LIGHT
		AnimState.HEAVY_WINDUP, AnimState.HEAVY_ACTIVE, AnimState.HEAVY_RECOVER:
			return CLIP_HEAVY
		AnimState.DODGE:
			return CLIP_DODGE
		AnimState.RANGED:
			return CLIP_RANGED
		AnimState.INTERACT:
			return CLIP_INTERACT
	return CLIP_IDLE


## Normalised clip position 0..1 for a timed state at progress `t` (the 40/20/40 melee split; the
## other one-shots map 1:1). Cyclic states return `t` unchanged.
static func clip_fraction(anim: StringName, t: float) -> float:
	var u := ActorMath.clamp01(t)
	match anim:
		AnimState.LIGHT_WINDUP, AnimState.HEAVY_WINDUP:
			return WINDUP_END * u
		AnimState.LIGHT_ACTIVE, AnimState.HEAVY_ACTIVE:
			return WINDUP_END + (ACTIVE_END - WINDUP_END) * u
		AnimState.LIGHT_RECOVER, AnimState.HEAVY_RECOVER:
			return ACTIVE_END + (1.0 - ACTIVE_END) * u
	return u


## Run cycle position 0..1 from distance travelled (tiles). Feet stay planted at any speed; on a
## reverse pass the distance runs backwards, so the cycle rewinds too.
static func run_fraction(distance: float) -> float:
	var f := fmod(distance / STRIDE_TILES, 1.0)
	return f + 1.0 if f < 0.0 else f


## Weight of the run clip against idle for a local-time speed (tiles per local second).
static func run_weight(local_speed: float) -> float:
	return ActorMath.smooth(0.08, 0.55, local_speed / RUN_SPEED)


static func is_melee(anim: StringName) -> bool:
	return anim == AnimState.LIGHT_WINDUP or anim == AnimState.LIGHT_ACTIVE or anim == AnimState.LIGHT_RECOVER \
		or anim == AnimState.HEAVY_WINDUP or anim == AnimState.HEAVY_ACTIVE or anim == AnimState.HEAVY_RECOVER


static func is_heavy(anim: StringName) -> bool:
	return anim == AnimState.HEAVY_WINDUP or anim == AnimState.HEAVY_ACTIVE or anim == AnimState.HEAVY_RECOVER


## True for the states whose clip is scrubbed by progress (everything but idle/run/stopped).
static func is_timed(anim: StringName) -> bool:
	return anim != AnimState.IDLE and anim != AnimState.RUN and anim != AnimState.STOPPED
