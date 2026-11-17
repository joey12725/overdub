class_name ViewMode
extends RefCounted
## Renderer view mode (contracts.ts ViewMode).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

## Player is in control: readability first.
const RECORD: StringName = &"record"
## Watching a non-winning combined run.
const REVIEW: StringName = &"review"
## Winning performance: cinematic camera + music-linked flourishes (CINE-03, MUSIC-13).
const CINEMATIC: StringName = &"cinematic"
## Calm framing behind menus / briefing.
const IDLE: StringName = &"idle"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	RECORD,
	REVIEW,
	CINEMATIC,
	IDLE,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
