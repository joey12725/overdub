class_name ShockArchetype
extends ProjectileArchetype
## 'shock' - the boss sweep's ring segments (prototype core/enemies/boss.ts SHOCK; BOSS-03,
## HEALTH-03). Like a bolt against selves (kills the vulnerable, passes through i-frames, dead
## ghosts and desynced selves) but it never touches enemies (spawned with hits_enemies = false);
## walls stop it (the default on_hit_wall). Registered lazily by ProjectileSystem (the prototype
## registered it when boss.ts loaded).


func _init() -> void:
	id = RangedArchetype.SHOCK


func on_hit_self(w: ODSim, p: Projectile, self_actor: SelfActor) -> StringName:
	if not self_actor.vulnerable:
		return VERDICT_PASS
	if self_actor.in_iframes(w.s):
		p.struck["self:%d" % self_actor.index] = true
		return VERDICT_PASS
	var owner: String = p.owner_enemy if not p.owner_enemy.is_empty() else "?"
	w.combat.hit_self(SelfHit.make(self_actor, "swept by boss %s" % owner, p.x, p.y, p.dir))
	return VERDICT_STOP
