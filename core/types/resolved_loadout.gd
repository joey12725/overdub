class_name ResolvedLoadout
extends RefCounted
## A loadout resolved into the numbers and flags the sim consumes (types.ts ResolvedLoadout).
## Built by LoadoutRules.resolve_loadout (content/loadout.gd).

var loadout: Loadout = Loadout.new()
## Every stat present (Required<StatMods>).
var mods: StatMods = StatMods.new()
## AbilityId.* of all equipped items, de-duplicated, in slot order.
var abilities: Array[StringName] = []
var melee: MeleeWeaponDef = MeleeWeaponDef.new()
var ranged: RangedWeaponDef = RangedWeaponDef.new()
## Presentation hints of the equipped items by slot (GearSlot.* -> GearLook), so the renderer can
## show equipped clothing (APPAREL-03). A slot without an entry draws Moxie's baseline look.
var looks: Dictionary[StringName, GearLook] = {}


func has_ability(ability: StringName) -> bool:
	return abilities.has(ability)


func copy() -> ResolvedLoadout:
	var o := ResolvedLoadout.new()
	o.loadout = loadout.copy()
	o.mods = mods.copy()
	o.abilities = abilities.duplicate()
	o.melee = melee.copy()
	o.ranged = ranged.copy()
	for slot: StringName in looks:
		o.looks[slot] = looks[slot].copy()
	return o


static func from_dict(d: Dictionary) -> ResolvedLoadout:
	var o := ResolvedLoadout.new()
	o.loadout = Loadout.from_dict(ODJson.dict(d, "loadout"))
	o.mods = StatMods.from_dict(ODJson.dict(d, "mods"))
	o.abilities = ODJson.snames(d.get("abilities"))
	o.melee = MeleeWeaponDef.from_dict(ODJson.dict(d, "melee"))
	o.ranged = RangedWeaponDef.from_dict(ODJson.dict(d, "ranged"))
	var lk := ODJson.dict(d, "looks")
	for slot: StringName in GearSlot.ALL:
		if lk.get(String(slot)) is Dictionary:
			o.looks[slot] = GearLook.from_dict(lk[String(slot)])
	return o


func to_dict() -> Dictionary:
	var out := {
		"loadout": loadout.to_dict(),
		"mods": mods.to_dict(true),
		"abilities": ODJson.snames_to_array(abilities),
		"melee": melee.to_dict(),
		"ranged": ranged.to_dict(),
	}
	if not looks.is_empty():
		var lk := {}
		for slot: StringName in GearSlot.ALL:
			if looks.has(slot):
				lk[String(slot)] = looks[slot].to_dict()
		out["looks"] = lk
	return out
