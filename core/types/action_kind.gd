class_name ActionKind
extends RefCounted
## Recorded action kinds (types.ts ActionKind).
## ALL is in serialisation order: a SerializedTape event tuple stores ALL.find(kind).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

const LIGHT: StringName = &"light"
const HEAVY: StringName = &"heavy"
const DODGE: StringName = &"dodge"
const RANGED: StringName = &"ranged"
const INTERACT: StringName = &"interact"
## Gear ability button (e.g. manual desync).
const ABILITY: StringName = &"ability"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	LIGHT,
	HEAVY,
	DODGE,
	RANGED,
	INTERACT,
	ABILITY,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
