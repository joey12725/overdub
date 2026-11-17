class_name EntityKind
extends RefCounted
## EntityDef.kind discriminator (types.ts EntityDef union).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

const ENEMY: StringName = &"enemy"
const DOOR: StringName = &"door"
const SWITCH: StringName = &"switch"
const PLATE: StringName = &"plate"
const BREAKABLE: StringName = &"breakable"
const LASER: StringName = &"laser"
const CORE: StringName = &"core"
const EXIT: StringName = &"exit"
const DECOR: StringName = &"decor"
## Traps and automated machinery (docs/TRAPS.md; TrapDef subclasses, simulated by Traps).
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
	ENEMY,
	DOOR,
	SWITCH,
	PLATE,
	BREAKABLE,
	LASER,
	CORE,
	EXIT,
	DECOR,
]

## The nine trap kinds, in prototype order (types.ts TrapDef). Kept out of ALL, which lists the
## classic entity kinds the pre-trap consumers (and tests/test_skeleton.gd) enumerate; use
## has() / is_trap() to accept every kind.
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


## True when `value` is a member (a classic kind or a trap kind).
static func has(value: StringName) -> bool:
	return ALL.has(value) or TRAPS.has(value)


## True for an entity kind simulated by Traps (traps/system.ts isTrapKind).
static func is_trap(value: StringName) -> bool:
	return TRAPS.has(value)
