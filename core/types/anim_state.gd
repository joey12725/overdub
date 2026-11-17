class_name AnimState
extends RefCounted
## Pose animation states (types.ts AnimState). ALL is index order: tape anim byte i == ALL[i]
## (identical to OD.ANIM_STATES).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

const IDLE: StringName = &"idle"
const RUN: StringName = &"run"
const LIGHT_WINDUP: StringName = &"lightWindup"
const LIGHT_ACTIVE: StringName = &"lightActive"
const LIGHT_RECOVER: StringName = &"lightRecover"
const HEAVY_WINDUP: StringName = &"heavyWindup"
const HEAVY_ACTIVE: StringName = &"heavyActive"
const HEAVY_RECOVER: StringName = &"heavyRecover"
const DODGE: StringName = &"dodge"
const RANGED: StringName = &"ranged"
const INTERACT: StringName = &"interact"
## A 'stop' tape that has run out holds this pose.
const STOPPED: StringName = &"stopped"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	IDLE,
	RUN,
	LIGHT_WINDUP,
	LIGHT_ACTIVE,
	LIGHT_RECOVER,
	HEAVY_WINDUP,
	HEAVY_ACTIVE,
	HEAVY_RECOVER,
	DODGE,
	RANGED,
	INTERACT,
	STOPPED,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
