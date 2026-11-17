class_name BurstArchetype
extends ProjectileArchetype
## Short-range burst (WEAPON-03): `def.count` straight pellets fanned evenly across `def.spreadDeg`
## degrees, centred on the recorded direction (the outermost pellets fly at ±spread/2). Each pellet
## is its own projectile with the weapon's full impact, short range and ordinary collision (stops at
## the first enemy, wall or closed door), so a close target can take several pellets.
## Port of prototype/src/core/weapons/burst.ts (the prototype's BURST = BurstArchetype.new()).


func _init() -> void:
	id = RangedArchetype.BURST


## Headings of a burst's pellets, in launch (spawn) order from one edge of the fan to the other.
## (`count` is an int in the port, so the prototype's Math.floor is a no-op.)
static func burst_headings(dir: float, count: int, spread_deg: float) -> Array[float]:
	var n := count if count >= 1 else 1
	if n == 1:
		return [dir]
	var spread := (spread_deg * PI) / 180.0
	var out: Array[float] = []
	for i in n:
		# Float division as in JS: (spread * i) / (n - 1) must not truncate.
		out.append(TapeLib.wrap_angle(dir - spread / 2.0 + (spread * float(i)) / float(n - 1)))
	return out


func launch(w: ODSim, self_actor: SelfActor, ev: TapeEvent, pass_dir: int) -> int:
	var def: RangedWeaponDef = w.loadout.ranged
	var headings := burst_headings(ev.dir, def.count, def.spread_deg)
	for h: float in headings:
		w.projectiles.spawn(w, WeaponCommon.self_shot(w, self_actor, RangedArchetype.BURST, h, pass_dir))
	return headings.size()


func on_hit_enemy(w: ODSim, p: Projectile, e: EnemyState) -> StringName:
	return WeaponCommon.hit_enemy_straight(w, p, e)


func on_hit_wall(w: ODSim, p: Projectile, hit: ODGrid.RayHit) -> StringName:
	return WeaponCommon.hit_wall_straight(w, p, hit.x, hit.y)
