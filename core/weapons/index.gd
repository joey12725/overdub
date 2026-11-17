class_name Weapons
extends RefCounted
## The player's ranged weapon archetypes (WEAPON-01..03). Port of prototype/src/core/weapons/index.ts.
## One file per archetype; every behaviour reads its numbers from the equipped RangedWeaponDef.
##
## GDScript has no import-time side effects: the prototype registered the five archetypes when the
## module loaded; here ProjectileSystem.get_projectile_archetype() calls register_self_weapons()
## lazily the first time its registry is read (core/README.md "Registries").

static var _self_weapons: Array[ProjectileArchetype] = []


## SELF_WEAPONS: the five self weapon archetypes, in the prototype's order
## [MISSILE, PIERCE, PHASE, ARC, BURST]. Built once; the same instances on every call.
static func self_weapons() -> Array[ProjectileArchetype]:
	if _self_weapons.is_empty():
		_self_weapons = [
			MissileArchetype.new(),
			PierceArchetype.new(),
			PhaseArchetype.new(),
			ArcArchetype.new(),
			BurstArchetype.new(),
		]
	return _self_weapons


## (Re-)register the built-in weapon archetypes, e.g. after a test replaced one.
static func register_self_weapons() -> void:
	for a: ProjectileArchetype in self_weapons():
		ProjectileSystem.register_projectile_archetype(a)
