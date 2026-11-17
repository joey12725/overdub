class_name EnemyType
extends RefCounted
## Enemy types (types.ts EnemyType).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

## Walks at the NEAREST living self and strikes on the beat. 1 hit.
const GRUNT: StringName = &"grunt"
## Hunts the FARTHEST living self. 1 hit, fast.
const STALKER: StringName = &"stalker"
## Stationary; fires at the nearest self in line of sight on its beat grid.
const TURRET: StringName = &"turret"
## Shield recharges instantly: needs a second hit inside a short window.
const SHIELDER: StringName = &"shielder"
## Heavy: 3 hits, strong knockback resistance, slow telegraphed slam.
const BRUTE: StringName = &"brute"
## Hovering ranged unit that keeps distance and fires on off-beats. 2 hits.
const DRONE: StringName = &"drone"
## Outside-the-loop boss with a health bar and cross-recording memory.
const BOSS: StringName = &"boss"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	GRUNT,
	STALKER,
	TURRET,
	SHIELDER,
	BRUTE,
	DRONE,
	BOSS,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
