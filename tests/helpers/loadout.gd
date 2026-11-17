class_name TestLoadout
extends RefCounted
## Test helper: a baseline ResolvedLoadout built from core/tuning.gd only, so core tests never
## depend on content/. The weapons are the plain baselines the tuning targets are written for.
## Port of prototype/tests/helpers/loadout.ts.


## Plain baseline melee weapon (light 6/4/10 ticks, heavy 16/5/18 ticks). A fresh object each call
## (the prototype's BASE_MELEE constant).
static func base_melee() -> MeleeWeaponDef:
	var m := MeleeWeaponDef.new()
	m.reach = 1.1
	m.arc_deg = 110.0
	m.light = _swing(6, 4, 10, 1.2, 0.5)
	m.heavy = _swing(16, 5, 18, 2, 0.25)
	m.damage_eff = 1.0
	m.knockback_eff = 1.0
	m.stagger_eff = 1.0
	m.style = MeleeStyle.BLADE
	return m


## Plain homing missile: very slow, locks once at launch (WEAPON-02, MISSILE-03). A fresh object each
## call (the prototype's BASE_MISSILE constant).
static func base_missile() -> RangedWeaponDef:
	var r := RangedWeaponDef.new()
	r.archetype = RangedArchetype.MISSILE
	r.speed = 2.5
	r.max_range = 14.0
	r.impact = 1.2
	r.commit = 12.0
	r.cooldown = 45.0
	r.pierce = 0
	r.passes_walls = false
	r.lobbed = false
	r.count = 1
	r.spread_deg = 0.0
	r.turn_rate = 2.5
	r.blast = 0.0
	return r


static func _swing(windup: float, active: float, recover: float, impact: float, move_mul: float) -> MeleeSwingDef:
	var s := MeleeSwingDef.new()
	s.windup = windup
	s.active = active
	s.recover = recover
	s.impact = impact
	s.move_mul = move_mul
	return s


## A fresh baseline loadout; `patch` overrides individual mods, abilities or weapon fields
## (prototype LoadoutPatch):
##   {"mods": {"moveSpeed": 1.5}}                      StatMods keys, camelCase or snake_case
##   {"abilities": [AbilityId.PHASE_DODGE]}
##   {"melee": {"reach": 2, "light": {"windup": 3}}}   partial weapon; swings patch field by field
##   {"ranged": {"commit": 20, "range": 9}}            "range" (or "max_range") is RangedWeaponDef.max_range
static func base_loadout(patch: Dictionary = {}) -> ResolvedLoadout:
	var lo := ResolvedLoadout.new()
	lo.loadout = Loadout.make("base-helmet", "base-top", "base-pants", "base-shoes", "base-melee", "base-missile")
	lo.mods = Tuning.neutral_mods()
	var mods: Dictionary = patch.get("mods", {})
	for k: Variant in mods:
		var key := String(k)
		if StatMods.KEY_TO_FIELD.has(key):
			lo.mods.set_stat(key, mods[k])
		else:
			_set_field(lo.mods, key, mods[k], "mods")
	lo.abilities.assign(patch.get("abilities", []))
	lo.melee = base_melee()
	var melee: Dictionary = patch.get("melee", {})
	for k: Variant in melee:
		var key := String(k).to_snake_case()
		if (key == "light" or key == "heavy") and melee[k] is Dictionary:
			var sw: MeleeSwingDef = lo.melee.get(key)
			var sd: Dictionary = melee[k]
			for sk: Variant in sd:
				_set_field(sw, String(sk).to_snake_case(), sd[sk], "melee." + key)
		else:
			_set_field(lo.melee, key, melee[k], "melee")
	lo.ranged = base_missile()
	var ranged: Dictionary = patch.get("ranged", {})
	for k: Variant in ranged:
		var key := String(k).to_snake_case()
		_set_field(lo.ranged, "max_range" if key == "range" else key, ranged[k], "ranged")
	return lo


static func _set_field(obj: Object, key: String, value: Variant, where: String) -> void:
	var field := key.to_snake_case()
	if not (field in obj):
		push_error("base_loadout: %s has no field '%s'" % [where, key])
		return
	obj.set(field, value)
