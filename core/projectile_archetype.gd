class_name ProjectileArchetype
extends RefCounted
## A projectile archetype (prototype core/projectiles.ts ProjectileArchetype), keyed by `id` and
## registered with ProjectileSystem.register_projectile_archetype.
##
## Every hook's default is exactly the prototype's behaviour when the hook is absent, and the
## framework calls every hook unconditionally:
##   launch(w, self_actor, ev, pass_dir) -> int  SELF weapons only. Called by
##                         ProjectileSystem.launch_from_self, the single dispatch point of a self's
##                         recorded 'ranged' event, at the weapon's launch tick, only when the self can
##                         act (alive or recording ghost, synced; Scenario F). Spawn projectiles with
##                         `w.projectiles.spawn(w, spec)` and return how many were spawned; the
##                         framework emits the 'fire' event when > 0. Default: launches nothing (0).
##   step(w, p)            Default: ProjectileSystem.fly_straight(w, p) (the prototype's straight
##                         flight when an archetype has no step). Override for homing, lobbing...;
##                         an override may call fly_straight itself.
##   on_hit_enemy(w, p, e) -> VERDICT_*   Default: ProjectileSystem.default_hit_enemy (deliver
##                         p.momentum as an EnemyStrike, stop unless it can pierce).
##   on_hit_self(w, p, s) -> VERDICT_*    Default: VERDICT_PASS (no friendly fire; OPEN-10).
##   on_hit_wall(w, p, hit: ODGrid.RayHit) -> VERDICT_*   Default: VERDICT_STOP. (PASS = keep flying.)
##                         `hit` is scratch owned by the projectile system: read it, do not keep it.
##   on_expire(w, p)       Range exhausted (e.g. an arc shell landing). Default: nothing.
##
## Archetype objects are shared by every sim (possibly on a worker thread): keep per-projectile data
## in `p.data` / `p.struck`, never on the archetype.

const VERDICT_STOP: StringName = &"stop"
const VERDICT_PASS: StringName = &"pass"

## RangedArchetype.*
var id: StringName = &""


func launch(_w: ODSim, _self_actor: SelfActor, _ev: TapeEvent, _pass_dir: int) -> int:
	return 0


func step(w: ODSim, p: Projectile) -> void:
	ProjectileSystem.fly_straight(w, p)


func on_hit_enemy(w: ODSim, p: Projectile, e: EnemyState) -> StringName:
	return ProjectileSystem.default_hit_enemy(w, p, e)


func on_hit_self(_w: ODSim, _p: Projectile, _self_actor: SelfActor) -> StringName:
	return VERDICT_PASS


func on_hit_wall(_w: ODSim, _p: Projectile, _hit: ODGrid.RayHit) -> StringName:
	return VERDICT_STOP


func on_expire(_w: ODSim, _p: Projectile) -> void:
	pass
