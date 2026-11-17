class_name GearItem
extends RefCounted
## One piece of equipment (types.ts GearItem). Loaded from data/gear.json by ContentData.load_gear().

var id: String = ""
## GearSlot.*
var slot: StringName = GearSlot.HELMET
var name: String = ""
## One-line player-readable statement of the mechanical effect (APPAREL-03).
var effect: String = ""
## Flavour text.
var lore: String = ""
## Optional stat modifiers; null = none (identity).
var mods: StatMods = null
## Optional abilities (AbilityId.*); empty = none.
var abilities: Array[StringName] = []
## Melee weapon definition (melee slot items); null otherwise.
var melee: MeleeWeaponDef = null
## Ranged weapon definition (ranged slot items); null otherwise.
var ranged: RangedWeaponDef = null
## Presentation hints for the character model; null = none.
var look: GearLook = null
## Optional: the item's trade-off in plain words (WEAPON-02 "stated downside"); "" = absent, the UI
## then states the archetype's inherent trade-off.
var downside: String = ""


func has_ability(ability: StringName) -> bool:
	return abilities.has(ability)


func copy() -> GearItem:
	var o := GearItem.new()
	o.id = id
	o.slot = slot
	o.name = name
	o.effect = effect
	o.lore = lore
	o.mods = mods.copy() if mods != null else null
	o.abilities = abilities.duplicate()
	o.melee = melee.copy() if melee != null else null
	o.ranged = ranged.copy() if ranged != null else null
	o.look = look.copy() if look != null else null
	o.downside = downside
	return o


static func from_dict(d: Dictionary) -> GearItem:
	var o := GearItem.new()
	o.id = ODJson.string(d, "id")
	o.slot = ODJson.sname(d, "slot", GearSlot.HELMET)
	o.name = ODJson.string(d, "name")
	o.effect = ODJson.string(d, "effect")
	o.lore = ODJson.string(d, "lore")
	if d.get("mods") is Dictionary:
		o.mods = StatMods.from_dict(d["mods"])
	o.abilities = ODJson.snames(d.get("abilities"))
	if d.get("melee") is Dictionary:
		o.melee = MeleeWeaponDef.from_dict(d["melee"])
	if d.get("ranged") is Dictionary:
		o.ranged = RangedWeaponDef.from_dict(d["ranged"])
	if d.get("look") is Dictionary:
		o.look = GearLook.from_dict(d["look"])
	o.downside = ODJson.string(d, "downside")
	return o


func to_dict() -> Dictionary:
	var out := {"id": id, "slot": String(slot), "name": name, "effect": effect, "lore": lore}
	if mods != null:
		out["mods"] = mods.to_dict()
	if not abilities.is_empty():
		out["abilities"] = ODJson.snames_to_array(abilities)
	if melee != null:
		out["melee"] = melee.to_dict()
	if ranged != null:
		out["ranged"] = ranged.to_dict()
	if look != null:
		out["look"] = look.to_dict()
	if not downside.is_empty():
		out["downside"] = downside
	return out
