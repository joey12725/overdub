class_name LoadoutRules
extends RefCounted
## Loadout resolution (port of prototype/src/content/loadout.ts): turns six equipped item ids into the
## numbers and flags the sim consumes, plus the player-readable summary the loadout screen shows
## (APPAREL-03, APP-TEST-02).
##
## Robustness policy: content and saves can drift apart (an item renamed between builds, a hand-edited
## save). Nothing here fails on bad ids; anything unknown or in the wrong slot falls back to that
## slot's baseline item, which is always owned and always viable (GEAR-04, APP-TEST-03).
##
## Every function takes an optional catalogue (default: CampaignData.gear(), i.e. data/gear.json) so
## tests can run against a hand-built one.

## The StatMods keys in canonical order (combining and describing), prototype spelling.
static var STAT_KEYS: Array[String] = StatMods.keys()

const SLOT_LABEL: Dictionary[StringName, String] = {
	GearSlot.HELMET: "Headgear",
	GearSlot.TOP: "Top",
	GearSlot.PANTS: "Pants",
	GearSlot.SHOES: "Shoes",
	GearSlot.MELEE: "Melee",
	GearSlot.RANGED: "Ranged",
}

## Player-readable name of each stat, used in combined summaries.
const STAT_LABEL: Dictionary[String, String] = {
	"moveSpeed": "Run speed",
	"accel": "Acceleration",
	"momentumRetention": "Speed kept through turns and actions",
	"dodgeDistance": "Dodge distance",
	"dodgeIframes": "Dodge invulnerability",
	"dodgeCooldown": "Dodge cooldown",
	"meleeImpact": "Melee momentum",
	"damage": "Damage",
	"knockback": "Knockback",
	"knockbackCap": "Maximum knockback distance",
	"stagger": "Stagger",
	"approachBonus": "Run-in strike bonus",
	"sparkSpeed": "Recovery spark speed",
	"interactRadiusAdd": "Switch reach",
	"projectileSpeed": "Projectile speed",
	"rangedCooldown": "Ranged cooldown",
}

## Player-readable statement of each ability, used in combined summaries and tooltips.
const ABILITY_TEXT: Dictionary[StringName, String] = {
	AbilityId.MANUAL_DESYNC: "Ability button: desync on purpose.",
	AbilityId.LOW_PROFILE: "Enemies treat you as farther away than you are.",
	AbilityId.LOUDMOUTH: "Enemies treat you as nearer than you are.",
	AbilityId.BEAT_SIGHT: "Enemy attack beats are marked on the beat ruler.",
	AbilityId.LASER_PROOF: "Lasers cannot kill you.",
	AbilityId.HEAVY_STEP: "Standing still holds heavy plates and counts double on normal ones.",
	AbilityId.PHASE_DODGE: "Dodges pass through enemies and low barriers.",
	AbilityId.SLIDE_STRIKE: "Striking out of a dodge adds momentum.",
	AbilityId.PARRY: "Heavy swings reflect projectiles inside the arc.",
	AbilityId.KILL_REFRESH: "A melee kill refreshes your dodge.",
}

const ARCHETYPE_TEXT: Dictionary[StringName, String] = {
	RangedArchetype.MISSILE: "Homing missile, locks the nearest enemy once",
	RangedArchetype.PIERCE: "Piercing shot",
	RangedArchetype.PHASE: "Passes through walls",
	RangedArchetype.ARC: "Lobbed over low cover",
	RangedArchetype.BURST: "Short-range spread",
}


static func _cat(catalogue: ContentData.GearCatalogue) -> ContentData.GearCatalogue:
	return catalogue if catalogue != null else CampaignData.gear()


## True for keys that add rather than multiply (name ends in `Add`, per types.ts StatMods).
static func is_additive_stat(key: String) -> bool:
	return key.ends_with("Add")


## A fresh StatMods with every key at its identity value.
static func identity_mods() -> StatMods:
	return StatMods.new()


## Combine any number of StatMods (null entries allowed): multipliers multiply, `*Add` keys add.
## Non-finite values are ignored so one bad data entry cannot poison the whole loadout.
static func combine_mods(list: Array[StatMods]) -> StatMods:
	var out := identity_mods()
	for mods: StatMods in list:
		if mods == null:
			continue
		for key: String in STAT_KEYS:
			var v: float = mods.get_stat(key)
			if is_nan(v) or is_inf(v):
				continue
			if is_additive_stat(key):
				out.set_stat(key, out.get_stat(key) + v)
			else:
				out.set_stat(key, out.get_stat(key) * v)
	return out


## The item a slot should hold for `id`: the item itself if it exists and fits the slot, else the
## slot's baseline.
static func _item_for_slot(cat: ContentData.GearCatalogue, slot: StringName, id: String) -> GearItem:
	var found := cat.get_item(id)
	if found != null and found.slot == slot:
		return found
	return cat.get_item(cat.base_loadout.get_slot(slot))


## Resolve a loadout into sim-ready numbers. Unknown ids, wrong-slot ids and empty slots (null = all
## empty) fall back to the baseline item for that slot. Weapon defs are copies, so the sim may hold
## or adjust them without touching the catalogue. `looks` collects each item's GearLook (port
## addition: the renderer dresses Moxie from it).
static func resolve_loadout(loadout: Loadout, catalogue: ContentData.GearCatalogue = null) -> ResolvedLoadout:
	var cat := _cat(catalogue)
	var r := ResolvedLoadout.new()
	var items: Array[GearItem] = []
	for slot: StringName in OD.GEAR_SLOTS:
		var it := _item_for_slot(cat, slot, loadout.get_slot(slot) if loadout != null else "")
		items.append(it)
		r.loadout.set_slot(slot, it.id if it != null else "")
	var mods: Array[StatMods] = []
	for it: GearItem in items:
		if it == null:
			continue
		mods.append(it.mods)
		for a: StringName in it.abilities:
			if not r.abilities.has(a):
				r.abilities.append(a)
		if it.look != null:
			r.looks[it.slot] = it.look.copy()
	r.mods = combine_mods(mods)
	var melee_item: GearItem = items[OD.GEAR_SLOTS.find(GearSlot.MELEE)]
	var ranged_item: GearItem = items[OD.GEAR_SLOTS.find(GearSlot.RANGED)]
	# A melee/ranged item missing its weapon def would be a catalogue bug; fall back rather than crash.
	var melee: MeleeWeaponDef = melee_item.melee if melee_item != null and melee_item.melee != null else null
	if melee == null:
		var base_m := cat.get_item(cat.base_loadout.melee)
		melee = base_m.melee if base_m != null and base_m.melee != null else MeleeWeaponDef.new()
	var ranged: RangedWeaponDef = ranged_item.ranged if ranged_item != null and ranged_item.ranged != null else null
	if ranged == null:
		var base_r := cat.get_item(cat.base_loadout.ranged)
		ranged = base_r.ranged if base_r != null and base_r.ranged != null else RangedWeaponDef.new()
	r.melee = melee.copy()
	r.ranged = ranged.copy()
	return r


# ─────────────────────────────── player-facing text ───────────────────────────────


## JS Math.round (half up toward +infinity).
static func _js_round(v: float) -> float:
	return floorf(v + 0.5)


## Format a number with at most `digits` decimals and no trailing zeros (String(Number(v.toFixed(d)))).
static func _num(v: float, digits: int = 2) -> String:
	var p := pow(10.0, digits)
	var r := _js_round(absf(v) * p) / p * signf(v)
	if r == 0.0:
		return "0"
	return String.num(r, digits)


static func _seconds(local_ticks: float) -> String:
	return "%s s" % _num(local_ticks / 60.0)


static func _stat_line(key: String, value: float) -> String:
	var label: String = STAT_LABEL.get(key, key)
	if is_additive_stat(key):
		var rounded := _js_round(value * 100.0) / 100.0
		if rounded == 0.0:
			return ""
		return "%s %s%s tiles" % [label, "+" if rounded > 0.0 else "-", _num(absf(rounded))]
	var pct := int(_js_round((value - 1.0) * 100.0))
	if pct == 0:
		return ""
	return "%s %s%d%%" % [label, "+" if pct > 0 else "-", absi(pct)]


## Player-readable combined effect lines for the loadout screen (APPAREL-03). Order: the two weapons,
## then every stat the loadout moves away from baseline, then granted abilities. Weapon numbers
## already include the loadout's projectile-speed and ranged-cooldown modifiers.
static func describe_loadout(loadout: Loadout, catalogue: ContentData.GearCatalogue = null) -> Array[String]:
	var cat := _cat(catalogue)
	var r := resolve_loadout(loadout, cat)
	var lines: Array[String] = []

	var melee_item := cat.get_item(r.loadout.melee)
	var m := r.melee
	var light_ticks := m.light.windup + m.light.active + m.light.recover
	var heavy_ticks := m.heavy.windup + m.heavy.active + m.heavy.recover
	lines.append("Melee: %s. %s-tile reach, %s° arc, light %s, heavy %s." % [
		melee_item.name if melee_item != null else r.loadout.melee,
		_num(m.reach), _num(m.arc_deg, 0), _seconds(light_ticks), _seconds(heavy_ticks)])

	var ranged_item := cat.get_item(r.loadout.ranged)
	var g := r.ranged
	var speed := g.speed * r.mods.projectile_speed
	var cooldown := g.cooldown * r.mods.ranged_cooldown
	lines.append("Ranged: %s. %s, %s tiles/s, %s-tile range, %s cooldown." % [
		ranged_item.name if ranged_item != null else r.loadout.ranged,
		ARCHETYPE_TEXT.get(g.archetype, String(g.archetype)), _num(speed, 1), _num(g.max_range, 1), _seconds(cooldown)])

	var stat_lines: Array[String] = []
	for key: String in STAT_KEYS:
		var line := _stat_line(key, r.mods.get_stat(key))
		if line != "":
			stat_lines.append(line)
	lines.append_array(stat_lines)
	for a: StringName in r.abilities:
		lines.append(ABILITY_TEXT.get(a, String(a)))
	if stat_lines.is_empty() and r.abilities.is_empty():
		lines.append("Clothing: no modifiers. The plain kit.")
	return lines


# ─────────────────────────────── inventory helpers ───────────────────────────────


## True when `id` names a baseline item; baseline items are owned implicitly and can never be lost.
static func is_baseline(id: String, catalogue: ContentData.GearCatalogue = null) -> bool:
	return _cat(catalogue).base_loadout.ids().has(id)


## Owned items for one slot, in catalogue order, baseline first. The baseline item is always
## included even when the inventory list omits it, so a slot can never be left empty. Unknown ids and
## duplicates in the inventory are ignored.
static func items_for_slot(inventory: Array[String], slot: StringName, catalogue: ContentData.GearCatalogue = null) -> Array[GearItem]:
	var cat := _cat(catalogue)
	var out: Array[GearItem] = []
	var base := cat.get_item(cat.base_loadout.get_slot(slot))
	if base != null:
		out.append(base)
	for it: GearItem in cat.items:
		if it.slot == slot and (base == null or it.id != base.id) and inventory.has(it.id):
			out.append(it)
	return out


## Repair a loadout so every slot holds an owned item of the right slot. Anything missing, unknown,
## unowned or in the wrong slot becomes that slot's baseline. Safe on hand-edited or stale saves.
static func sanitise_loadout(loadout: Loadout, inventory: Array[String], catalogue: ContentData.GearCatalogue = null) -> Loadout:
	var cat := _cat(catalogue)
	var base_ids := cat.base_loadout.ids()
	var out := Loadout.new()
	for slot: StringName in OD.GEAR_SLOTS:
		var id := loadout.get_slot(slot) if loadout != null else ""
		var it := cat.get_item(id)
		var ok := it != null and it.slot == slot and (inventory.has(it.id) or base_ids.has(it.id))
		out.set_slot(slot, it.id if ok else cat.base_loadout.get_slot(slot))
	return out
