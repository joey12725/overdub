class_name GearSlot
extends RefCounted
## Equipment slots (types.ts GearSlot). ALL == OD.GEAR_SLOTS (prototype order).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

const HELMET: StringName = &"helmet"
const TOP: StringName = &"top"
const PANTS: StringName = &"pants"
const SHOES: StringName = &"shoes"
const MELEE: StringName = &"melee"
const RANGED: StringName = &"ranged"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	HELMET,
	TOP,
	PANTS,
	SHOES,
	MELEE,
	RANGED,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
