class_name DlgGate
extends RefCounted
## When each overlay may appear (INTEGRATION.md "Never open a box during countin, recording, review
## or cinematic"). Node-free.

## Phases in which a dialogue box must never be open.
const BOX_BLOCKED: Array[StringName] = [
	SessionPhase.COUNTIN,
	SessionPhase.RECORDING,
	SessionPhase.REVIEW,
	SessionPhase.CINEMATIC,
]
## Phases in which a queued "first" (firstDeath...) may play: the next calm moment after a take.
const FIRSTS_ALLOWED: Array[StringName] = [
	SessionPhase.DECISION,
	SessionPhase.SETUP,
	SessionPhase.RESULTS,
]
## Phases in which barks are allowed (they are non-blocking; the cinematic is left clean).
const BARKS_ALLOWED: Array[StringName] = [
	SessionPhase.SETUP,
	SessionPhase.COUNTIN,
	SessionPhase.RECORDING,
	SessionPhase.REVIEW,
	SessionPhase.DECISION,
	SessionPhase.CINEMATIC,
	SessionPhase.RESULTS,
]


## `phase` "" means "not in a level" (menus, ending screen): boxes are allowed.
static func box_allowed(phase: StringName) -> bool:
	return not BOX_BLOCKED.has(phase)


static func first_allowed(phase: StringName) -> bool:
	return FIRSTS_ALLOWED.has(phase)


static func bark_allowed(phase: StringName) -> bool:
	return BARKS_ALLOWED.has(phase)
