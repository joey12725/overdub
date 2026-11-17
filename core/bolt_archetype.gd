class_name BoltArchetype
extends ProjectileArchetype
## The enemy 'bolt' (prototype core/projectiles.ts BOLT): straight, blocked by walls and closed doors
## but not low barriers, kills the first vulnerable self it touches unless that self is inside dodge
## i-frames (it then flies on through; TEST-21). It never hurts dead ghosts, the recording ghost or
## desynced selves (passes through them). It also strikes other enemies it meets, so knocking an
## enemy into a turret's lane matters (MOM-05, Scenario E).


func _init() -> void:
	id = RangedArchetype.BOLT


func on_hit_self(w: ODSim, p: Projectile, self_actor: SelfActor) -> StringName:
	if not self_actor.vulnerable:
		return VERDICT_PASS
	if self_actor.in_iframes(w.s):
		# Dodged: the bolt flies on through and never re-tests this self (TEST-21).
		p.struck["self:%d" % self_actor.index] = true
		return VERDICT_PASS
	var owner: EnemyState = w.enemy_by_id(p.owner_enemy) if p.owner_tape < 0 else null
	var who: String = "%s %s" % [owner.type, owner.id] if owner != null else "a bolt"
	w.combat.hit_self(SelfHit.make(self_actor, "shot by %s" % who, p.x, p.y, p.dir))
	return VERDICT_STOP


func on_hit_enemy(w: ODSim, p: Projectile, e: EnemyState) -> StringName:
	p.struck["enemy:%s" % e.id] = true
	var src: StrikeSource = StrikeSource.of_enemy(p.owner_enemy) if p.owner_tape < 0 else StrikeSource.of_tape(p.owner_tape)
	w.combat.strike_enemy(
		e,
		(
			EnemyStrike.make(src, "bolt", 1.0, p.dir, e.x, e.y)
			.with_damage(1.0)
			.with_knockback(0.0)
			.with_stagger(ProjectileSystem.BOLT_ENEMY_STAGGER)
		)
	)
	return VERDICT_STOP
