class_name RangedWeaponDef
extends RefCounted
## A ranged weapon (types.ts RangedWeaponDef).

## RangedArchetype.* (one of RangedArchetype.SELF).
var archetype: StringName = RangedArchetype.MISSILE
## Projectile speed in tiles per MASTER second. Missiles are deliberately very slow (WEAPON-02).
var speed: float = 0.0
## Maximum travel distance in tiles (missile: lifetime distance). Prototype key "range" (renamed
## because `range` is a GDScript global function).
var max_range: float = 0.0
## Momentum delivered on hit (feeds the same damage/knockback/stagger model as melee).
var impact: float = 0.0
## Local ticks the firing actor is committed (cannot act).
var commit: float = 0.0
## Local ticks before another shot may be fired.
var cooldown: float = 0.0
## How many enemies one projectile can pass through (pierce). 0 = stops at first hit.
var pierce: int = 0
## Projectile ignores walls/closed doors (phase).
var passes_walls: bool = false
## Lobbed: ignores low cover and enemies in flight, damages a small radius on landing (arc).
var lobbed: bool = false
## Projectiles per shot (burst) and the total spread in degrees.
var count: int = 1
var spread_deg: float = 0.0
## Homing turn rate in radians per master second (missile). 0 = flies straight.
var turn_rate: float = 0.0
## Blast radius in tiles on impact (0 = single target).
var blast: float = 0.0
## Optional: collision radius of each projectile in tiles. has_radius false = the sim's default.
var radius: float = 0.0
var has_radius: bool = false
## Optional, lobbed weapons: the shell never lands closer than this many tiles from the launcher.
## has_min_range false = no minimum.
var min_range: float = 0.0
var has_min_range: bool = false


## Deep copy (loadout.ts cloneRanged).
func copy() -> RangedWeaponDef:
	var o := RangedWeaponDef.new()
	o.archetype = archetype
	o.speed = speed
	o.max_range = max_range
	o.impact = impact
	o.commit = commit
	o.cooldown = cooldown
	o.pierce = pierce
	o.passes_walls = passes_walls
	o.lobbed = lobbed
	o.count = count
	o.spread_deg = spread_deg
	o.turn_rate = turn_rate
	o.blast = blast
	o.radius = radius
	o.has_radius = has_radius
	o.min_range = min_range
	o.has_min_range = has_min_range
	return o


static func from_dict(d: Dictionary) -> RangedWeaponDef:
	var o := RangedWeaponDef.new()
	o.archetype = ODJson.sname(d, "archetype", RangedArchetype.MISSILE)
	o.speed = ODJson.num(d, "speed")
	o.max_range = ODJson.num(d, "range")
	o.impact = ODJson.num(d, "impact")
	o.commit = ODJson.num(d, "commit")
	o.cooldown = ODJson.num(d, "cooldown")
	o.pierce = ODJson.integer(d, "pierce")
	o.passes_walls = ODJson.boolean(d, "passesWalls")
	o.lobbed = ODJson.boolean(d, "lobbed")
	o.count = ODJson.integer(d, "count", 1)
	o.spread_deg = ODJson.num(d, "spreadDeg")
	o.turn_rate = ODJson.num(d, "turnRate")
	o.blast = ODJson.num(d, "blast")
	o.has_radius = ODJson.is_number(d.get("radius"))
	o.radius = ODJson.num(d, "radius")
	o.has_min_range = ODJson.is_number(d.get("minRange"))
	o.min_range = ODJson.num(d, "minRange")
	return o


func to_dict() -> Dictionary:
	var out := {
		"archetype": String(archetype),
		"speed": speed,
		"range": max_range,
		"impact": impact,
		"commit": commit,
		"cooldown": cooldown,
		"pierce": pierce,
		"passesWalls": passes_walls,
		"lobbed": lobbed,
		"count": count,
		"spreadDeg": spread_deg,
		"turnRate": turn_rate,
		"blast": blast,
	}
	if has_radius:
		out["radius"] = radius
	if has_min_range:
		out["minRange"] = min_range
	return out
