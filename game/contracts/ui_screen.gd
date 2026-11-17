class_name UiScreen
extends RefCounted
## UI screens (contracts.ts Screen; renamed for clarity).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

const TITLE: StringName = &"title"
const CAMPAIGN: StringName = &"campaign"
const LOADOUT: StringName = &"loadout"
const SETTINGS: StringName = &"settings"
const PLAY: StringName = &"play"
const PAUSE: StringName = &"pause"
const RESULTS: StringName = &"results"
const ENDING: StringName = &"ending"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	TITLE,
	CAMPAIGN,
	LOADOUT,
	SETTINGS,
	PLAY,
	PAUSE,
	RESULTS,
	ENDING,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
