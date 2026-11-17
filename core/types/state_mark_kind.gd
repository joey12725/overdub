class_name StateMarkKind
extends RefCounted
## DeckStateMark.kind (types.ts DeckView.stateMarks[].kind); also the extra kinds UiBase.deck_event
## accepts besides ActionKind.
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

const DEATH: StringName = &"death"
const DESYNC: StringName = &"desync"
const RESYNC: StringName = &"resync"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	DEATH,
	DESYNC,
	RESYNC,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
