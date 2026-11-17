class_name MeleeStyle
extends RefCounted
## MeleeWeaponDef.style: presentation and flavour only.
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

const BLADE: StringName = &"blade"
const BLUNT: StringName = &"blunt"
const WHIP: StringName = &"whip"
const GAUNTLET: StringName = &"gauntlet"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	BLADE,
	BLUNT,
	WHIP,
	GAUNTLET,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
