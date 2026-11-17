class_name SessionPhase
extends RefCounted
## SessionView.phase (types.ts SessionPhase).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

## Level briefing / first look.
const BRIEFING: StringName = &"briefing"
## Choosing tape speed and end behaviour for the next take.
const SETUP: StringName = &"setup"
## "five, six, seven, eight".
const COUNTIN: StringName = &"countin"
## Live take in progress.
const RECORDING: StringName = &"recording"
## Watching the combined result of the takes so far at true master speed (skippable).
const REVIEW: StringName = &"review"
## Retry take / commit and advance / reset the whole attempt.
const DECISION: StringName = &"decision"
## Locked, non-interactive true-speed performance of a winning attempt (CINE-01..05).
const CINEMATIC: StringName = &"cinematic"
## Level cleared; loot and next-level prompt.
const RESULTS: StringName = &"results"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	BRIEFING,
	SETUP,
	COUNTIN,
	RECORDING,
	REVIEW,
	DECISION,
	CINEMATIC,
	RESULTS,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
