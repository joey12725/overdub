class_name AbilityId
extends RefCounted
## Discrete abilities granted by gear (types.ts AbilityId). The sim, HUD or renderer keys
## behaviour off these ids.
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

## Ability button toggles this self into desync on demand.
const MANUAL_DESYNC: StringName = &"manualDesync"
## Enemy targeting rules treat this loadout's selves as farther away than they are.
const LOW_PROFILE: StringName = &"lowProfile"
## Enemy targeting rules treat this loadout's selves as nearer than they are.
const LOUDMOUTH: StringName = &"loudmouth"
## HUD draws upcoming enemy attack beats on the master ruler.
const BEAT_SIGHT: StringName = &"beatSight"
## Laser hazards do not kill.
const LASER_PROOF: StringName = &"laserProof"
## Standing still on a pressure plate counts double / holds heavy plates.
const HEAVY_STEP: StringName = &"heavyStep"
## Dodge passes through enemies and low barriers.
const PHASE_DODGE: StringName = &"phaseDodge"
## Ending a dodge into a strike adds momentum.
const SLIDE_STRIKE: StringName = &"slideStrike"
## Heavy attacks reflect projectiles that are inside the swing arc.
const PARRY: StringName = &"parry"
## A melee kill refunds the dodge cooldown.
const KILL_REFRESH: StringName = &"killRefresh"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	MANUAL_DESYNC,
	LOW_PROFILE,
	LOUDMOUTH,
	BEAT_SIGHT,
	LASER_PROOF,
	HEAVY_STEP,
	PHASE_DODGE,
	SLIDE_STRIKE,
	PARRY,
	KILL_REFRESH,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
