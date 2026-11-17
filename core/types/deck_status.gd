class_name DeckStatus
extends RefCounted
## DeckView.status (types.ts DeckStatus).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

## Level does not offer this cassette.
const UNAVAILABLE: StringName = &"unavailable"
## Not recorded yet.
const EMPTY: StringName = &"empty"
## Being configured for the next take.
const ARMED: StringName = &"armed"
const RECORDING: StringName = &"recording"
## Recorded but not yet committed (awaiting decision).
const PENDING: StringName = &"pending"
const COMMITTED: StringName = &"committed"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	UNAVAILABLE,
	EMPTY,
	ARMED,
	RECORDING,
	PENDING,
	COMMITTED,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
