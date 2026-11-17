class_name PhaseArchetype
extends ProjectileArchetype
## Wall-penetrator (WEAPON-03, NEW-05): a straight shot that passes through walls, closed doors and
## unbroken breakables, and stops at the first enemy it touches (unless the weapon data gives it
## pierce). The map edge is the one thing it does not cross: it ends there with a 'projectileHit'
## detailed 'phase:edge', so a shot never wanders outside the level.
## Port of prototype/src/core/weapons/phase.ts (the prototype's PHASE = PhaseArchetype.new()).
##
## Passing walls is this archetype's rule; it is always on for 'phase' whatever `passesWalls` says,
## and no other archetype gets it unless its own weapon data asks for it (NEW-05).


func _init() -> void:
	id = RangedArchetype.PHASE


func launch(w: ODSim, self_actor: SelfActor, ev: TapeEvent, pass_dir: int) -> int:
	var spec := WeaponCommon.self_shot(w, self_actor, RangedArchetype.PHASE, ev.dir, pass_dir)
	spec.passes_walls = true
	w.projectiles.spawn(w, spec)
	return 1


func step(w: ODSim, p: Projectile) -> void:
	var step_len: float = p.speed / OD.SUB_HZ
	var edge := WeaponCommon.distance_to_edge(w.grid, p.x, p.y, p.dir) - WeaponCommon.EDGE_MARGIN
	if edge >= step_len:
		ProjectileSystem.fly_straight(w, p)
		return
	ProjectileSystem.fly_straight(w, p, edge if edge > 0.0 else 0.0)
	if not p.alive:
		return
	p.alive = false
	w.emit(SimEvent.make(0, SimEventType.PROJECTILE_HIT, p.x, p.y).with_tape(WeaponCommon.owner_tape(p)) \
		.with_dir(p.dir).with_detail("phase:edge"))


func on_hit_enemy(w: ODSim, p: Projectile, e: EnemyState) -> StringName:
	return WeaponCommon.hit_enemy_straight(w, p, e)
