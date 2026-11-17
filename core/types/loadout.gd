class_name Loadout
extends RefCounted
## Item ids per slot (types.ts Loadout = Record<GearSlot, string>). Every slot always holds an item
## (baseline gear cannot be unequipped to empty); "" only appears in a not-yet-sanitised loadout.

var helmet: String = ""
var top: String = ""
var pants: String = ""
var shoes: String = ""
var melee: String = ""
var ranged: String = ""


static func make(p_helmet: String, p_top: String, p_pants: String, p_shoes: String, p_melee: String, p_ranged: String) -> Loadout:
	var l := Loadout.new()
	l.helmet = p_helmet
	l.top = p_top
	l.pants = p_pants
	l.shoes = p_shoes
	l.melee = p_melee
	l.ranged = p_ranged
	return l


## Item id in `slot` (GearSlot.*); "" for an unknown slot.
func get_slot(slot: StringName) -> String:
	match slot:
		GearSlot.HELMET:
			return helmet
		GearSlot.TOP:
			return top
		GearSlot.PANTS:
			return pants
		GearSlot.SHOES:
			return shoes
		GearSlot.MELEE:
			return melee
		GearSlot.RANGED:
			return ranged
	return ""


## Put item `id` in `slot` (GearSlot.*); unknown slots are ignored.
func set_slot(slot: StringName, id: String) -> void:
	match slot:
		GearSlot.HELMET:
			helmet = id
		GearSlot.TOP:
			top = id
		GearSlot.PANTS:
			pants = id
		GearSlot.SHOES:
			shoes = id
		GearSlot.MELEE:
			melee = id
		GearSlot.RANGED:
			ranged = id


## Ids in GearSlot.ALL order (Object.values(loadout) in the prototype).
func ids() -> Array[String]:
	return [helmet, top, pants, shoes, melee, ranged]


func copy() -> Loadout:
	return Loadout.make(helmet, top, pants, shoes, melee, ranged)


func equals(o: Loadout) -> bool:
	return helmet == o.helmet and top == o.top and pants == o.pants and shoes == o.shoes and melee == o.melee and ranged == o.ranged


## Missing slots read as "" (Partial<Loadout> in the prototype's sanitiseLoadout).
static func from_dict(d: Dictionary) -> Loadout:
	return Loadout.make(
		ODJson.string(d, "helmet"), ODJson.string(d, "top"), ODJson.string(d, "pants"),
		ODJson.string(d, "shoes"), ODJson.string(d, "melee"), ODJson.string(d, "ranged"))


func to_dict() -> Dictionary:
	return {"helmet": helmet, "top": top, "pants": pants, "shoes": shoes, "melee": melee, "ranged": ranged}
