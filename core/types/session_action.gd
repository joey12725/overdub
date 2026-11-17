class_name SessionAction
extends RefCounted
## Session actions (types.ts SessionAction).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

## Leave briefing.
const START: StringName = &"start"
const SPEED_UP: StringName = &"speedUp"
const SPEED_DOWN: StringName = &"speedDown"
const CYCLE_END_MODE: StringName = &"cycleEndMode"
## Begin count-in.
const RECORD: StringName = &"record"
## Skip review playback.
const SKIP: StringName = &"skip"
## End a failing playback early (REC-08).
const END_ATTEMPT: StringName = &"endAttempt"
## Discard the current take, keep committed tapes (REC-04).
const RETRY_TAKE: StringName = &"retryTake"
## Commit the take and move to the next cassette.
const COMMIT: StringName = &"commit"
## Wipe every cassette (REC-05).
const RESET_ALL: StringName = &"resetAll"
## Results -> campaign.
const CONTINUE: StringName = &"continue"
const QUIT: StringName = &"quit"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	START,
	SPEED_UP,
	SPEED_DOWN,
	CYCLE_END_MODE,
	RECORD,
	SKIP,
	END_ATTEMPT,
	RETRY_TAKE,
	COMMIT,
	RESET_ALL,
	CONTINUE,
	QUIT,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
