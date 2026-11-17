class_name EnemyBehaviour
extends RefCounted
## Enemy framework contract (prototype core/enemies/types.ts EnemyBehaviour; AI-01..07).
##
## HOW TO ADD AN ENEMY TYPE
##   1. Create `core/enemies/<type>.gd` with a class extending EnemyBehaviour (see grunt.gd /
##      turret.gd) that sets `type` in `_init` and overrides the hooks it needs.
##   2. Add it to the table in registry.gd (or call EnemyRegistry.register_enemy_behaviour before
##      creating a sim).
##   3. Put its numbers in Tuning.ENEMY_STATS; EnemyDef.beat / hp override per placement.
##
## The framework (EnemyCommon, driven by ODSim) owns everything shared, so a behaviour only makes
## decisions:
##   - wake-up (EnemyDef.wake_when), knockback integration with wall collision (MOM-05), stagger
##     timing, death, beat bookkeeping and snapshots;
##   - per substep, for an awake, alive enemy that is neither staggered nor sliding from knockback:
##       on_beat(w, e, beat)   once on every master beat boundary (sub % subs-per-beat == 0), first;
##       step(w, e)            every substep (movement, telegraph -> attack progression).
##   - on_hit(w, e, strike) may veto or rewrite incoming momentum (shields, armour, boss phases);
##     the default applies the strike normally (Combat.apply_strike).
##   - snapshot(w, e, snap) fills type-specific EnemySnap extras (shield, boss_phase, boss_recall...).
##   - forecast_attack_subs(w, e, at, end_sub, out) (port addition, see below) reports the
##     behaviour's own upcoming attack instants for the 'beatSight' forecast.
##
## Every hook has a default that is exactly the prototype's behaviour when the hook is absent, and the
## framework calls every hook unconditionally.
##
## Determinism rules every behaviour must keep: no randomness, decisions only from world state, ties
## broken by lowest tape index / entity order, attacks landing on the beat grid (AI-07; use
## EnemyCommon.is_grid_sub / next_grid_sub). Dead ghosts, recording ghosts and desynced selves are
## never targets (EnemyCommon.targetable). Behaviours are shared by every sim (one instance per type,
## possibly on a worker thread): keep per-run data in EnemyState (fields or `mem`), never on the
## behaviour object.

## EnemyType.*
var type: StringName = &""
## Bodies of this type hold 'heavy' pressure plates.
var heavy_body: bool = false
## Bodies of this type fly: they never press plates, and only walls and closed doors (projectile
## solidity) count as solid for them, so a door closing elsewhere never shoves one hovering over void.
var hovering: bool = false


## Called once when the run starts (after the framework filled the state).
func init(_w: ODSim, _e: EnemyState) -> void:
	pass


## Called on every master beat boundary, before `step`, while awake and able to act.
func on_beat(_w: ODSim, _e: EnemyState, _beat: int) -> void:
	pass


## Called every substep while awake and able to act.
func step(_w: ODSim, _e: EnemyState) -> void:
	pass


## Incoming strike hook. Default: apply normally.
func on_hit(_w: ODSim, _e: EnemyState, _strike: EnemyStrike) -> HitResponse:
	return HitResponse.apply()


## Called after the enemy died.
func on_death(_w: ODSim, _e: EnemyState) -> void:
	pass


## Fill type-specific snapshot fields.
func snapshot(_w: ODSim, _e: EnemyState, _snap: EnemySnap) -> void:
	pass


## 'beatSight' forecast hook (port addition; not in the prototype).
##
## Append to `out` the master substeps in [at, end_sub] at which THIS enemy's own attacks could land,
## judged from the current world state (a forecast, not a simulation: the live take's future input is
## unknown), and return true. `at` is the instant the forecast is made (ODSim.sub); `e` is alive and
## awake. Duplicates and order do not matter (the caller sorts and de-duplicates).
##
## Return false (the default) to let Abilities.upcoming_attack_beats use its generic rule instead:
## a telegraphing enemy's committed instant plus every grid instant it could still telegraph for while
## it is "engaged" (has a live target, or a self is inside its reach in line of sight).
##
## A behaviour that overrides this knows its own rules (who it may target, how far it can walk before
## a telegraph must start, recovery after a strike, aim arcs) and so gives a sharper forecast.
func forecast_attack_subs(_w: ODSim, _e: EnemyState, _at: int, _end_sub: int, _out: Array[int]) -> bool:
	return false
