class_name DartArchetype
extends ProjectileArchetype
## The 'dart' projectile fired by dart launcher traps (prototype core/traps/dart.ts; docs/TRAPS.md
## "Dart launcher").
##
## A dart is an enemy bolt with no owner to blame and no target: straight flight (the default step),
## stopped by walls, closed doors, unbroken breakables and extended crushers (anything that blocks
## shots), over low barriers. It kills the first vulnerable self it touches unless that self is
## inside dodge i-frames (it then flies on through and never re-tests that self), passes through dead
## ghosts, the recording ghost and desynced projections, and strikes the first living enemy it meets
## for DART_DAMAGE with a short stagger and no knockback.
##
## Its owner is the launcher's id (Projectile.owner_enemy, snapshot `owner: {enemy: <launcher id>}`)
## because a projectile has no trap owner; no enemy has that id (one id namespace), so nothing is
## excluded from its contacts. Registered by ProjectileSystem with the other built-in archetypes.


func _init() -> void:
	id = RangedArchetype.DART


func on_hit_self(w: ODSim, p: Projectile, self_actor: SelfActor) -> StringName:
	if not self_actor.vulnerable:
		return VERDICT_PASS
	if self_actor.in_iframes(w.s):
		p.struck["self:%d" % self_actor.index] = true
		return VERDICT_PASS
	w.combat.hit_self(SelfHit.make(self_actor, "shot by dart launcher %s" % _launcher_id(p), p.x, p.y, p.dir))
	return VERDICT_STOP


func on_hit_enemy(w: ODSim, p: Projectile, e: EnemyState) -> StringName:
	p.struck["enemy:%s" % e.id] = true
	w.combat.strike_enemy(
		e,
		(
			EnemyStrike.make(StrikeSource.of_env("dart launcher %s" % _launcher_id(p)), "dart", 1.0, p.dir, e.x, e.y)
			.with_damage(TrapTuning.DART_DAMAGE)
			.with_knockback(0.0)
			.with_stagger(TrapTuning.HAZARD_STAGGER)
		)
	)
	return VERDICT_STOP


static func _launcher_id(p: Projectile) -> String:
	return p.owner_enemy if p.owner_tape < 0 else "?"


## Spawn one dart at (x, y) flying along `dir` (radians) at `speed` tiles per master second
## (traps/dart.ts spawnDart).
static func spawn_dart(w: ODSim, launcher: String, x: float, y: float, dir: float, speed: float) -> Projectile:
	var spec := SpawnSpec.make(-1, launcher, RangedArchetype.DART, x, y, dir, speed, TrapTuning.DART_RADIUS, TrapTuning.DART_RANGE)
	spec.momentum = 1.0
	spec.set_hits_selves(true)
	spec.hits_enemies = true
	return w.projectiles.spawn(w, spec)
