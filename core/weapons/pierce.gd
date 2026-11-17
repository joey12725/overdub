class_name PierceArchetype
extends ProjectileArchetype
## Piercing shot (WEAPON-03, NEW-04): a fast straight shot that keeps going through up to
## `def.pierce` enemies, striking each one once, and stops at the next one, at a wall or closed door,
## or when its range runs out. Lining enemies up along its path is the puzzle.
## Port of prototype/src/core/weapons/pierce.ts (the prototype's PIERCE = PierceArchetype.new()).
##
## Piercing is this weapon's data, not a property every shot inherits: every straight archetype reads
## `def.pierce`, and the shipped non-piercing weapons set it to 0 (NEW-04, NEW-05).


func _init() -> void:
	id = RangedArchetype.PIERCE


func launch(w: ODSim, self_actor: SelfActor, ev: TapeEvent, pass_dir: int) -> int:
	w.projectiles.spawn(w, WeaponCommon.self_shot(w, self_actor, RangedArchetype.PIERCE, ev.dir, pass_dir))
	return 1


func on_hit_enemy(w: ODSim, p: Projectile, e: EnemyState) -> StringName:
	return WeaponCommon.hit_enemy_straight(w, p, e)


func on_hit_wall(w: ODSim, p: Projectile, hit: ODGrid.RayHit) -> StringName:
	return WeaponCommon.hit_wall_straight(w, p, hit.x, hit.y)
