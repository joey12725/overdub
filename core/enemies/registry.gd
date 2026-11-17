class_name EnemyRegistry
extends RefCounted
## Enemy-type registry (prototype core/enemies/registry.ts). One entry per EnemyType; each behaviour
## lives in its own file and extends EnemyBehaviour (core/enemies/enemy_behaviour.gd).
##
## To add a type: append its behaviour to `_builtin()` (or call register_enemy_behaviour before
## creating a sim). A level that places an enemy whose type has no registered behaviour fails loudly
## when the sim is created (ODSim.create_sim returns null with "No enemy behaviour registered for type
## '<type>'"), rather than spawning an inert body.
##
## GDScript has no module side effects, so the table is filled lazily on first read (as the prototype
## also did). ODCore.ensure_registered() forces it; the game calls that once on the main thread before
## resolving on a worker thread, after which the table is only read.
##
## FOR BEHAVIOUR AUTHORS (roster engineer) - hooks every behaviour may override (EnemyBehaviour):
##   init, on_beat, step, on_hit, on_death, snapshot   - as the prototype's EnemyBehaviour.
##   forecast_attack_subs(w, e, at, end_sub, out: Array[int]) -> bool
##       Port addition for the 'beatSight' HUD forecast (Abilities.upcoming_attack_beats). Append the
##       master substeps in [at, end_sub] where this enemy's OWN next attacks could land, judged from
##       the current state only, and return true. Return false (the base default) to keep the generic
##       forecast (telegraph instant + every reachable grid instant while engaged). Good forecasts
##       respect: a telegraph already committed (e.attack_sub), the telegraph length (an instant g is
##       only possible if g - telegraph >= at and the enemy is not staggered / sliding then), recovery
##       after a strike (e.state_end while in 'attack'), who the behaviour may target (range, line of
##       sight, aim arc, perceived distance) and how far it can walk before the telegraph must start.
##       GruntBehaviour and TurretBehaviour implement it; stalker / shielder / brute / drone / boss
##       should too, following the same pattern.

static var _registry: Dictionary[StringName, EnemyBehaviour] = {}
static var _filled: bool = false
static var _overrides: Array[EnemyBehaviour] = []


static func _builtin() -> Array[EnemyBehaviour]:
	return [
		GruntBehaviour.new(),
		TurretBehaviour.new(),
		StalkerBehaviour.new(),
		ShielderBehaviour.new(),
		BruteBehaviour.new(),
		DroneBehaviour.new(),
		BossBehaviour.new(),
	]


static func _table() -> Dictionary[StringName, EnemyBehaviour]:
	if not _filled:
		_filled = true
		for b: EnemyBehaviour in _builtin():
			_registry[b.type] = b
		for b: EnemyBehaviour in _overrides:
			_registry[b.type] = b
		_overrides.clear()
	return _registry


## Fill the table now (ODCore.ensure_registered).
static func ensure_defaults() -> void:
	_table()


## Register (or replace) the behaviour for an enemy type.
static func register_enemy_behaviour(b: EnemyBehaviour) -> void:
	if _filled:
		_registry[b.type] = b
	else:
		_overrides.append(b)


static func has_enemy_behaviour(type: StringName) -> bool:
	return _table().has(type)


## The behaviour for a type. For an unregistered type: null, and the prototype's error message is
## appended to `errors` (the prototype threw; see module doc).
static func get_enemy_behaviour(type: StringName, errors: Array[String] = []) -> EnemyBehaviour:
	var b: EnemyBehaviour = _table().get(type)
	if b == null:
		errors.append("No enemy behaviour registered for type '%s' (core/enemies/registry.gd)" % type)
	return b


## Registered types, for tools and validators (built-ins in prototype order, then additions).
static func registered_enemy_types() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _table().keys():
		out.append(k)
	return out
