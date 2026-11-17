class_name ObjectiveType
extends RefCounted
## ObjectiveDef.type (types.ts).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

## Every enemy (or those listed in targets) is dead.
const ELIMINATE: StringName = &"eliminate"
## An alive + synced self is inside the exit when the horizon ends.
const REACH: StringName = &"reach"
## Every core (or those in targets) is activated.
const ACTIVATE: StringName = &"activate"
## The boss is dead.
const BOSS: StringName = &"boss"
## Custom: `when_expr` latches true at any point of the run.
const SIGNAL: StringName = &"signal"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	ELIMINATE,
	REACH,
	ACTIVATE,
	BOSS,
	SIGNAL,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
