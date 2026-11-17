class_name FailReason
extends RefCounted
## Outcome.reason (types.ts FailReason). &"" = no reason (a win).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

const OBJECTIVE: StringName = &"objective"
const NO_SURVIVOR: StringName = &"noSurvivor"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	OBJECTIVE,
	NO_SURVIVOR,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
