class_name ProjectileSnap
extends RefCounted
## One projectile at one instant (types.ts ProjectileSnap).

var id: int = 0
## Owner (types.ts owner: { tape } | { enemy }): exactly one of these is set.
## Firing self's tape index, or -1 when an enemy fired it.
var owner_tape: int = -1
## Firing enemy's id, or "" when a self fired it.
var owner_enemy: String = ""
## RangedArchetype.* (including BOLT / SHOCK).
var archetype: StringName = RangedArchetype.BOLT
var x: float = 0.0
var y: float = 0.0
## Visual height above the floor (arc shots).
var z: float = 0.0
var dir: float = 0.0
## Missile only: id of the locked target; "" = none.
var target_id: String = ""


func is_self_owned() -> bool:
	return owner_tape >= 0


func copy() -> ProjectileSnap:
	var o := ProjectileSnap.new()
	o.id = id
	o.owner_tape = owner_tape
	o.owner_enemy = owner_enemy
	o.archetype = archetype
	o.x = x
	o.y = y
	o.z = z
	o.dir = dir
	o.target_id = target_id
	return o


static func from_dict(d: Dictionary) -> ProjectileSnap:
	var o := ProjectileSnap.new()
	o.id = ODJson.integer(d, "id")
	var owner := ODJson.dict(d, "owner")
	o.owner_tape = ODJson.integer(owner, "tape", -1)
	o.owner_enemy = ODJson.string(owner, "enemy")
	o.archetype = ODJson.sname(d, "archetype", RangedArchetype.BOLT)
	o.x = ODJson.num(d, "x")
	o.y = ODJson.num(d, "y")
	o.z = ODJson.num(d, "z")
	o.dir = ODJson.num(d, "dir")
	o.target_id = ODJson.string(d, "targetId")
	return o


func to_dict() -> Dictionary:
	var out := {
		"id": id,
		"owner": {"tape": owner_tape} if owner_tape >= 0 else {"enemy": owner_enemy},
		"archetype": String(archetype),
		"x": x,
		"y": y,
		"z": z,
		"dir": dir,
	}
	if not target_id.is_empty():
		out["targetId"] = target_id
	return out
