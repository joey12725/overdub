class_name MeleeWeaponDef
extends RefCounted
## A melee weapon (types.ts MeleeWeaponDef).

## Reach of the hit volume in tiles, measured from the actor centre.
var reach: float = 1.0
## Total arc of the hit volume in degrees, centred on the swing direction.
var arc_deg: float = 90.0
var light: MeleeSwingDef = MeleeSwingDef.new()
var heavy: MeleeSwingDef = MeleeSwingDef.new()
## Multiplier from momentum to damage.
var damage_eff: float = 1.0
## Multiplier from momentum to knockback distance.
var knockback_eff: float = 1.0
## Multiplier from momentum to stagger duration.
var stagger_eff: float = 1.0
## MeleeStyle.* - presentation + flavour only.
var style: StringName = MeleeStyle.BLADE


## Deep copy (loadout.ts cloneMelee).
func copy() -> MeleeWeaponDef:
	var o := MeleeWeaponDef.new()
	o.reach = reach
	o.arc_deg = arc_deg
	o.light = light.copy()
	o.heavy = heavy.copy()
	o.damage_eff = damage_eff
	o.knockback_eff = knockback_eff
	o.stagger_eff = stagger_eff
	o.style = style
	return o


static func from_dict(d: Dictionary) -> MeleeWeaponDef:
	var o := MeleeWeaponDef.new()
	o.reach = ODJson.num(d, "reach", 1.0)
	o.arc_deg = ODJson.num(d, "arcDeg", 90.0)
	o.light = MeleeSwingDef.from_dict(ODJson.dict(d, "light"))
	o.heavy = MeleeSwingDef.from_dict(ODJson.dict(d, "heavy"))
	o.damage_eff = ODJson.num(d, "damageEff", 1.0)
	o.knockback_eff = ODJson.num(d, "knockbackEff", 1.0)
	o.stagger_eff = ODJson.num(d, "staggerEff", 1.0)
	o.style = ODJson.sname(d, "style", MeleeStyle.BLADE)
	return o


func to_dict() -> Dictionary:
	return {
		"reach": reach,
		"arcDeg": arc_deg,
		"light": light.to_dict(),
		"heavy": heavy.to_dict(),
		"damageEff": damage_eff,
		"knockbackEff": knockback_eff,
		"staggerEff": stagger_eff,
		"style": String(style),
	}
