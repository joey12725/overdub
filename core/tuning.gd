class_name Tuning
extends RefCounted
## Every gameplay constant in one place (port of prototype/src/core/tuning.ts).
##
## Units are explicit in each name's doc comment. "Local" quantities belong to a self's own tape clock
## (they feel identical at every tape speed, TIME-02); "master" quantities belong to the shared world.
## Values are first-pass tuning (TIME-05, OPEN-09, OPEN-12, OPEN-13 leave them to playtesting); the
## combat targets from docs/ARCHITECTURE.md are asserted by tests/core/foundation/test_tuning.gd so a
## retune that breaks them fails loudly.
##
## Pure data plus the momentum model's arithmetic. Never instantiated.

# ───────────────────────────── base actor stats ─────────────────────────────

## Base (unmodified) stats of a self. Gear multiplies these through `ResolvedLoadout.mods`
## (see `StatMods`: multipliers unless the key ends in `Add`). The content module should resolve
## loadouts against these, never against literals of its own. Treat as read-only.
class BaseStats:
	extends RefCounted
	## Collision radius of a self, tiles. Under 0.5 so a 1-tile corridor is comfortable.
	var actor_radius: float = 0.3
	## Top running speed, tiles per local second.
	var run_speed: float = 4.5
	## Acceleration toward the input direction, tiles per local second².
	var accel: float = 42.0
	## Braking with no input (and when reversing), tiles per local second².
	var decel: float = 34.0
	## Exponential decay rate (per local second) of velocity perpendicular to the input direction.
	## Divided by `momentumRetention`, so retention gear makes turns carry more sideways drift.
	var turn_damping: float = 16.0
	## Exponential decay rate (per local second) of speed above the current cap (after a dodge, a swing slowdown).
	var overspeed_decay: float = 9.0
	## How quickly the body turns to face its movement direction, radians per local second.
	var facing_turn_rate: float = 28.0
	## Speeds below this (tiles per local second) animate as idle rather than run.
	var run_anim_threshold: float = 0.4

	## Dodge length, local ticks. Constant across gear so the dash reads the same; distance scales speed.
	var dodge_ticks: int = 14
	## Dodge travel distance, tiles (scaled by mods.dodgeDistance).
	var dodge_distance: float = 2.4
	## First i-frame tick, as an offset from the dodge's start tick.
	var dodge_iframe_start: int = 1
	## I-frame window length, local ticks (scaled by mods.dodgeIframes).
	var dodge_iframes: float = 10.0
	## Ticks after the dodge ends before another may start (scaled by mods.dodgeCooldown).
	var dodge_cooldown: float = 22.0
	## Fraction of run speed carried out of a dodge along the dash direction.
	var dodge_exit_speed: float = 0.85

	## Movement multiplier while committed to a ranged shot.
	var ranged_move_mul: float = 0.5
	## Ticks from the ranged event to the projectile launch (clamped to the weapon's commit).
	var ranged_launch_delay: int = 4

	## Interaction commitment, local ticks.
	var interact_ticks: int = 10
	## Movement multiplier during an interaction.
	var interact_move_mul: float = 0.4
	## Interaction reach from the actor centre, tiles (mods.interactRadiusAdd is added).
	var interact_radius: float = 1.2

	## A press that cannot start yet is remembered this many local ticks (so presses in recovery are not dropped).
	var input_buffer_ticks: int = 8

	## Recovery spark speed, tiles per MASTER second (DESYNC-02: faster than running, not instant).
	var spark_speed: float = 7.5
	## Spark radius for path smoothing / wall clearance, tiles.
	var spark_radius: float = 0.2
	## Spark resyncs when within this distance of the projection with a clear line (DESYNC-05), tiles.
	var resync_tolerance: float = 0.35
	## Minimum time between spark re-plans, master substeps (re-planning also happens on any grid change).
	var spark_replan_subs: int = 24

	## Momentum bonus fraction for running fully into a strike (MOM-03).
	var approach_bonus: float = 0.5
	## Maximum knockback distance, tiles (scaled by mods.knockbackCap).
	var knockback_cap: float = 3.0


## The base stats (tuning.ts BASE). Shared; never mutate.
static var BASE: BaseStats = BaseStats.new()


## Fresh mutable identity modifier set (tuning.ts neutralMods(); NEUTRAL_MODS is StatMods.new(), whose
## fields default to the identity: 1 for multipliers, 0 for `...Add` keys).
static func neutral_mods() -> StatMods:
	return StatMods.new()

# ───────────────────────────── collision ─────────────────────────────

## Collision resolution leaves circles this far outside walls. Tapes store positions as float32
## (~4e-6 tiles of precision on a 40-tile map); the skin keeps a recorded wall-hugging pose from
## rounding into the wall and spuriously desyncing on playback.
const COLLISION_SKIN: float = 1e-3

## Penetration the kernel should forgive before calling a recorded position "inside solid geometry"
## (DESYNC trigger). Smaller than any meaningful obstruction, larger than float32 noise.
const DESYNC_PENETRATION_TOLERANCE: float = 0.02

# ───────────────────────────── momentum model (MOM-01..06) ─────────────────────────────

## Momentum per point of damage. With the baseline weapon (light impact 1.2, damageEff 1) a 1×
## standing light deals floor(1.2) = 1 (kills a 1-hit enemy) and a 0.5× one floor(0.6) = 0.
const DAMAGE_UNIT: float = 1.0

## Approach factor bounds: running away still delivers half the swing, running in at most doubles the bonus term.
const APPROACH_MIN: float = -0.5
const APPROACH_MAX: float = 1.0

## Momentum a tutorial breakable needs. A 2× running heavy (2 × 2 × 1.5 = 6) breaks it; a 1× running
## heavy (3) and a 2× standing heavy (4) do not (architecture tuning target; Scenario K).
const TUTORIAL_WALL_THRESHOLD: float = 5.0

## Default momentum a core needs when CoreDef.threshold is omitted (a 1× standing light suffices).
const DEFAULT_CORE_THRESHOLD: float = 1.0


## Normalised approach: how much of the self's local velocity points along the swing (MOM-03).
## Normalised by BASE.runSpeed (not the loadout's run speed) so faster shoes do add momentum until the cap.
static func strike_approach(local_vx: float, local_vy: float, swing_dir: float) -> float:
	var along := local_vx * cos(swing_dir) + local_vy * sin(swing_dir)
	var a := along / BASE.run_speed
	return APPROACH_MIN if a < APPROACH_MIN else (APPROACH_MAX if a > APPROACH_MAX else a)


## Effective momentum of a strike. `tape_speed` appears exactly once: it is the master-time conversion
## of both the swing and the body velocity (MOM-01, "do not count tape speed twice").
## `approach_bonus_mod` is mods.approachBonus (multiplies BASE.approachBonus).
static func strike_momentum(impact: float, melee_impact_mod: float, tape_speed: float, approach: float, approach_bonus_mod: float = 1.0) -> float:
	return impact * melee_impact_mod * tape_speed * (1.0 + BASE.approach_bonus * approach_bonus_mod * approach)


## Momentum of a recorded melee swing, from the event's recorded velocity and direction.
## `mods` supplies melee_impact and approach_bonus.
static func swing_momentum(swing: MeleeSwingDef, mods: StatMods, tape_speed: float, local_vx: float, local_vy: float, dir: float) -> float:
	return strike_momentum(swing.impact, mods.melee_impact, tape_speed, strike_approach(local_vx, local_vy, dir), mods.approach_bonus)


## Damage points from momentum (never negative).
static func strike_damage(momentum: float, damage_eff: float, damage_mod: float) -> int:
	var d := floorf((momentum * damage_eff * damage_mod) / DAMAGE_UNIT + 1e-9)
	# JS keeps a float (and NaN > 0 is false); clamp before the int conversion so inf/NaN stay sane.
	if not (d > 0.0):
		return 0
	return int(minf(d, 1e15))


## Knockback distance, tiles, capped. Immovable targets (mass INF) get 0.
static func strike_knockback(momentum: float, knockback_eff: float, knockback_mod: float, knockback_cap_mod: float, enemy_mass: float) -> float:
	if not (enemy_mass > 0.0) or is_inf(enemy_mass):
		return 0.0
	var k := (momentum * knockback_eff * knockback_mod) / enemy_mass
	var cap := BASE.knockback_cap * knockback_cap_mod
	return 0.0 if k < 0.0 else (cap if k > cap else k)


## Stagger duration in master seconds. Unstaggerable targets (poise INF) get 0.
static func strike_stagger(momentum: float, stagger_eff: float, stagger_mod: float, enemy_poise: float) -> float:
	if not (enemy_poise > 0.0) or is_inf(enemy_poise):
		return 0.0
	var s := (momentum * stagger_eff * stagger_mod) / enemy_poise
	return s if s > 0.0 else 0.0

# ───────────────────────────── knockback motion ─────────────────────────────

## Knockback is applied as a slide over this many master seconds (MOM-05: enemies really move).
const KNOCKBACK_SECONDS: float = 0.18
## Hitting a wall during knockback converts remaining distance into this much extra stagger (master s per tile).
const WALL_SLAM_STAGGER_PER_TILE: float = 0.25

# ───────────────────────────── enemies ─────────────────────────────

## Per-type enemy numbers (tuning.ts EnemyStats). Treat as read-only.
class EnemyStats:
	extends RefCounted
	## Damage points to kill (EnemyDef.hp overrides).
	var hp: int = 1
	## Knockback divisor. INF = immovable.
	var mass: float = 1.0
	## Stagger divisor. INF = never staggers.
	var poise: float = 1.0
	## Body radius, tiles.
	var radius: float = 0.3
	## Walk speed, tiles per master second (0 = stationary).
	var speed: float = 0.0
	## Default attack grid in master beats.
	var every: float = 2.0
	var offset: float = 0.0
	## Reach of a melee strike / max range of a shot, tiles.
	var reach: float = 1.0
	## Telegraph length before an attack lands, master beats (AI-04 legibility).
	var telegraph_beats: float = 0.5
	## Projectile speed for ranged enemies, tiles per master second (0 for melee enemies).
	var shot_speed: float = 0.0

	static func make(p_hp: int, p_mass: float, p_poise: float, p_radius: float, p_speed: float, p_every: float, p_offset: float, p_reach: float, p_telegraph_beats: float, p_shot_speed: float) -> EnemyStats:
		var s := EnemyStats.new()
		s.hp = p_hp
		s.mass = p_mass
		s.poise = p_poise
		s.radius = p_radius
		s.speed = p_speed
		s.every = p_every
		s.offset = p_offset
		s.reach = p_reach
		s.telegraph_beats = p_telegraph_beats
		s.shot_speed = p_shot_speed
		return s


## Enemy roster numbers (AI-01..07, HEALTH-02). One-hit enemies have hp 1; the brute takes 3
## standing 1× lights but one 1× running heavy (floor(2 × 1.5) = 3), which is the momentum lesson.
## Keyed by EnemyType.*, in prototype order. Shared; never mutate.
static var ENEMY_STATS: Dictionary[StringName, EnemyStats] = {
	EnemyType.GRUNT: EnemyStats.make(1, 1.0, 2.0, 0.32, 2.2, 2.0, 0.0, 0.9, 0.5, 0.0),
	EnemyType.STALKER: EnemyStats.make(1, 0.8, 1.5, 0.3, 3.6, 2.0, 1.0, 0.9, 0.5, 0.0),
	EnemyType.TURRET: EnemyStats.make(1, INF, INF, 0.4, 0.0, 2.0, 0.0, 12.0, 1.0, 6.0),
	EnemyType.SHIELDER: EnemyStats.make(2, 1.2, 2.5, 0.35, 1.8, 4.0, 0.0, 0.9, 0.75, 0.0),
	EnemyType.BRUTE: EnemyStats.make(3, 3.0, 6.0, 0.5, 1.4, 4.0, 2.0, 1.4, 1.5, 0.0),
	EnemyType.DRONE: EnemyStats.make(2, 0.7, 1.5, 0.3, 2.5, 2.0, 1.0, 8.0, 0.5, 5.0),
	EnemyType.BOSS: EnemyStats.make(40, 8.0, 20.0, 0.9, 1.8, 4.0, 0.0, 2.2, 2.0, 5.0),
}


## Stats of an enemy type (ENEMY_STATS[type]); null for an unknown type.
static func enemy_stats(type: StringName) -> EnemyStats:
	return ENEMY_STATS.get(type, null)


## Shielder: a second hit must land within this many master beats of the first (shield recharges instantly otherwise).
const SHIELDER_WINDOW_BEATS: float = 1.0
## Drone: preferred distance it keeps from its target, tiles.
const DRONE_KEEP_DISTANCE: float = 5.0
## Enemy bolt collision radius, tiles.
const ENEMY_SHOT_RADIUS: float = 0.15
## Self projectile collision radius, tiles.
const SELF_SHOT_RADIUS: float = 0.15
## Arc (lobbed) shots: peak height in tiles for presentation, and landing blast if the weapon's is 0.
const ARC_PEAK_HEIGHT: float = 1.5
const ARC_MIN_BLAST: float = 0.6
