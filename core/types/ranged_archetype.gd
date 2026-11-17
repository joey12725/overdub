class_name RangedArchetype
extends RefCounted
## Projectile archetype ids. MISSILE..BURST are the self weapons (types.ts RangedArchetype, listed
## in SELF); BOLT and SHOCK are enemy-only archetypes that ProjectileSnap.archetype may also carry
## (projectiles.ts ProjectileArchetypeId).
##
## StringName constants; values are the prototype's string spellings (JSON uses them as-is).
## Never instantiated.

## Very slow; locks the nearest enemy once at launch, never retargets.
const MISSILE: StringName = &"missile"
## Fast; passes through several enemies.
const PIERCE: StringName = &"pierce"
## Passes walls.
const PHASE: StringName = &"phase"
## Lobbed over low cover; damages a small radius on landing.
const ARC: StringName = &"arc"
## Short-range spread.
const BURST: StringName = &"burst"
## Enemy shot (turret, drone).
const BOLT: StringName = &"bolt"
## Boss sweep shot.
const SHOCK: StringName = &"shock"
## Fired by a dart launcher trap (docs/TRAPS.md 5); its owner is the launcher's id.
const DART: StringName = &"dart"

## Every member, in prototype order.
const ALL: Array[StringName] = [
	MISSILE,
	PIERCE,
	PHASE,
	ARC,
	BURST,
	BOLT,
	SHOCK,
	DART,
]

const SELF: Array[StringName] = [
	MISSILE,
	PIERCE,
	PHASE,
	ARC,
	BURST,
]


## True when `value` is a member.
static func has(value: StringName) -> bool:
	return ALL.has(value)
