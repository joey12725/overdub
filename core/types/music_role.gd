class_name MusicRole
extends RefCounted
## TrackMusicDef.role (types.ts).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

const BASS: StringName = &"bass"
const DRUMS: StringName = &"drums"
const MELODY: StringName = &"melody"
const CHORD: StringName = &"chord"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	BASS,
	DRUMS,
	MELODY,
	CHORD,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
