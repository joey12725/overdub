class_name Dir4
extends RefCounted
## A cardinal direction of a trap (types.ts Dir4; docs/TRAPS.md "Directions").
##
## `n` points toward row 0 of the map array (-y), `e` toward higher columns (+x), `s` toward higher
## rows (+y), `w` toward lower columns (-x). StringName constants; values are the prototype's string
## spellings (JSON uses them as-is). Never instantiated.

const N: StringName = &"n"
const E: StringName = &"e"
const S: StringName = &"s"
const W: StringName = &"w"

## Every member, in prototype order.
const ALL: Array[StringName] = [N, E, S, W]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)


## Column step of a direction (traps/system.ts dirVec(dir).x).
static func dx(dir: StringName) -> int:
	match dir:
		E:
			return 1
		W:
			return -1
	return 0


## Row step of a direction (traps/system.ts dirVec(dir).y).
static func dy(dir: StringName) -> int:
	match dir:
		S:
			return 1
		N:
			return -1
	return 0


## Angle in radians, atan2(y, x) (traps/system.ts dirAngle): n -PI/2, e 0, s PI/2, w PI.
static func angle(dir: StringName) -> float:
	match dir:
		N:
			return -PI / 2.0
		S:
			return PI / 2.0
		W:
			return PI
	return 0.0
