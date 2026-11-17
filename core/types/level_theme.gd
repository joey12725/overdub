class_name LevelTheme
extends RefCounted
## Depth theme of a level (types.ts Theme; renamed because Godot has a Theme class).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

const UPPER: StringName = &"upper"
const MID: StringName = &"mid"
const LOWER: StringName = &"lower"
const CORE: StringName = &"core"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	UPPER,
	MID,
	LOWER,
	CORE,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
