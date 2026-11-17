class_name MissileArchetype
extends ProjectileArchetype
## Guided missile (MISSILE-01..04, WEAPON-02, NEW-02, NEW-03, TEST-22, Scenario F).
## Port of prototype/src/core/weapons/missile.ts (the prototype's MISSILE = MissileArchetype.new()).
##
##   - Deliberately very slow: it flies at the weapon's own (low) speed, which leaves the battlefield
##     time to change before it arrives (WEAPON-02).
##   - At launch it acquires the nearest living enemy exactly once, by straight-line distance from
##     the launch point; ties go to the enemy placed first in the level (entity order), so the choice
##     is deterministic (MISSILE-03 leaves ties open). Line of sight is not required: the missile
##     steers, and walls simply stop it if they are in the way. Sleeping enemies are living enemies.
##   - It then turns toward that one target at most `turnRate` radians per master second and never
##     retargets: not when another enemy becomes nearer, not when its target dies. With a dead or
##     absent target it flies straight on until it hits something or its range runs out.
##   - It strikes whatever enemy it actually touches first (the lock steers it; it does not make it
##     pass through other bodies). Blocked by walls and closed doors unless the weapon data says it
##     passes walls. No enemy at launch: it flies straight along the recorded direction.
##   - The recorded direction is the initial heading on every pass, including a reverse pass (the
##     requirements leave reverse behaviour open; a re-fired shot is a fresh shot with its recorded
##     aim, like a re-fired swing; PLAY-06).
##   - The missile is a world object: it keeps flying if its launcher later dies or desyncs (left
##     open by the requirements; nothing about the launch is undone).


func _init() -> void:
	id = RangedArchetype.MISSILE


## The nearest living enemy to (x, y); ties go to entity order. Null when none is alive.
static func acquire_nearest_enemy(w: ODSim, x: float, y: float) -> EnemyState:
	var best: EnemyState = null
	var best_d := INF
	for e: EnemyState in w.enemies:
		if not e.alive:
			continue
		# Math.hypot: ODGrid.hypot reproduces V8 bit for bit, so near-ties break as in the prototype.
		var d := ODGrid.hypot(e.x - x, e.y - y)
		if d < best_d:
			best_d = d
			best = e
	return best


func launch(w: ODSim, self_actor: SelfActor, ev: TapeEvent, pass_dir: int) -> int:
	var spec := WeaponCommon.self_shot(w, self_actor, RangedArchetype.MISSILE, ev.dir, pass_dir)
	var target := acquire_nearest_enemy(w, self_actor.pose.x, self_actor.pose.y)
	if target != null:
		spec.target_id = target.id
	spec.data["turnRate"] = maxf(0.0, w.loadout.ranged.turn_rate)
	w.projectiles.spawn(w, spec)
	return 1


func step(w: ODSim, p: Projectile) -> void:
	var turn: float = float(p.data.get("turnRate", 0.0)) / OD.SUB_HZ
	if not p.target_id.is_empty() and turn > 0.0:
		var t: EnemyState = w.enemy_by_id(p.target_id)
		# MISSILE-03: the lock is never moved to another enemy; a dead target just stops the homing.
		if t != null and t.alive:
			var want := atan2(t.y - p.y, t.x - p.x)
			var d := TapeLib.angle_delta(p.dir, want)
			p.dir = TapeLib.wrap_angle(want if absf(d) <= turn else p.dir + signf(d) * turn)
	ProjectileSystem.fly_straight(w, p)


func on_hit_enemy(w: ODSim, p: Projectile, e: EnemyState) -> StringName:
	return WeaponCommon.hit_enemy_straight(w, p, e)


func on_hit_wall(w: ODSim, p: Projectile, hit: ODGrid.RayHit) -> StringName:
	return WeaponCommon.hit_wall_straight(w, p, hit.x, hit.y)
