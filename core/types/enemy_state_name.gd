class_name EnemyStateName
extends RefCounted
## EnemySnap.state / EnemyState.state (types.ts EnemySnap['state'], enemies/types.ts EnemyStateName).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

const ASLEEP: StringName = &"asleep"
const IDLE: StringName = &"idle"
const MOVE: StringName = &"move"
const TELEGRAPH: StringName = &"telegraph"
const ATTACK: StringName = &"attack"
const STAGGER: StringName = &"stagger"
const DEAD: StringName = &"dead"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	ASLEEP,
	IDLE,
	MOVE,
	TELEGRAPH,
	ATTACK,
	STAGGER,
	DEAD,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
