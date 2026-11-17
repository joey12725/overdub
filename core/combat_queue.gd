class_name CombatQueue
extends RefCounted
## The damage-resolution queue (prototype core/combat.ts CombatQueue; COMBAT-01..04, HEALTH-01).
##
## Everything that hurts something is queued during a substep and applied together in the damage
## phase (ODSim substep order step 7), so hits that land on the same substep are simultaneous (a self
## and a grunt that strike each other on the same substep both die) and the order systems run in
## never decides who wins a trade.
##
## Entry points: `hit_self(SelfHit)` is how enemy weapons kill selves; `strike_enemy(e, EnemyStrike)`
## is how melee and projectile archetypes deliver momentum.

var _self_hits: Array[SelfHit] = []
var _strike_enemies: Array[EnemyState] = []
var _strikes: Array[EnemyStrike] = []
var _dying: Array[SelfActor] = []


func hit_self(hit: SelfHit) -> void:
	_self_hits.append(hit)


func strike_enemy(enemy: EnemyState, strike: EnemyStrike) -> void:
	_strike_enemies.append(enemy)
	_strikes.append(strike)


## Apply everything queued this substep. Vulnerability is judged once, before anything applies.
func resolve(w: ODSim) -> void:
	if _self_hits.is_empty() and _strikes.is_empty():
		return
	# Snapshot who was vulnerable when the substep's hits landed, so a self killed by one hit is not
	# reported dead twice and mutual kills on the same substep both happen.
	var dying: Array[SelfActor] = _dying
	dying.clear()
	var laser_proof: bool = w.loadout.has_ability(AbilityId.LASER_PROOF)
	for h: SelfHit in _self_hits:
		var s: SelfActor = h.self_actor
		if dying.has(s) or not s.vulnerable:
			continue
		if s.in_iframes(w.s):
			continue
		if h.laser and laser_proof:
			continue
		dying.append(s)
		Combat._kill_self(w, s, h)
	# Like the prototype's for-of over a growing array: a strike queued while applying (an on_death
	# hook striking a neighbour) is applied in this same pass; self hits queued now are dropped.
	var i: int = 0
	while i < _strikes.size():
		Combat.apply_strike(w, _strike_enemies[i], _strikes[i])
		i += 1
	_self_hits.clear()
	_strike_enemies.clear()
	_strikes.clear()
	dying.clear()
