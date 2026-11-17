class_name MechKind
extends RefCounted
## MechSnap.kind (types.ts).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

const DOOR: StringName = &"door"
const SWITCH: StringName = &"switch"
const PLATE: StringName = &"plate"
const BREAKABLE: StringName = &"breakable"
const LASER: StringName = &"laser"
const CORE: StringName = &"core"
const EXIT: StringName = &"exit"
## Trap snapshots (docs/TRAPS.md "Snapshot fields"), listed after the classic mechanisms.
const SPIKES: StringName = &"spikes"
const CRUSHER: StringName = &"crusher"
const CONVEYOR: StringName = &"conveyor"
const FLAME: StringName = &"flame"
const DART: StringName = &"dart"
const BUMPER: StringName = &"bumper"
const SENSOR: StringName = &"sensor"
const RELAY: StringName = &"relay"
const MAGNET: StringName = &"magnet"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	DOOR,
	SWITCH,
	PLATE,
	BREAKABLE,
	LASER,
	CORE,
	EXIT,
]

## The nine trap snapshot kinds, in prototype order. Kept out of ALL, which lists the classic
## mechanisms the pre-trap consumers (and tests/test_skeleton.gd) enumerate; has() accepts both.
const TRAPS: Array[StringName] = [
	SPIKES,
	CRUSHER,
	CONVEYOR,
	FLAME,
	DART,
	BUMPER,
	SENSOR,
	RELAY,
	MAGNET,
]


## True when `value` is a member (a classic mechanism or a trap kind).
static func has(value: StringName) -> bool:
	return ALL.has(value) or TRAPS.has(value)
