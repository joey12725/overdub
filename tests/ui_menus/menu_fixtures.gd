extends RefCounted
## Fixtures for the menu suites (port of prototype tests/ui-menus/fixtures.ts). Loaded with preload;
## no class_name so it never collides with game classes.


class Recorder:
	extends RefCounted
	var intents: Array[UiIntent] = []
	var emit: Callable

	func _init() -> void:
		# A bound method, not a lambda: a lambda would hold this object and leak it in a cycle.
		emit = _record

	func _record(i: UiIntent) -> void:
		intents.append(i)

	## describe() of every intent so far.
	func descs() -> Array[String]:
		var out: Array[String] = []
		for i in intents:
			out.append(i.describe())
		return out

	func last() -> UiIntent:
		return intents.back() if not intents.is_empty() else null


## Mutable int counter usable from lambdas (lambdas capture locals by value).
class Counter:
	extends RefCounted
	var n: int = 0
	var bump: Callable

	func _init() -> void:
		bump = _bump

	func _bump() -> void:
		n += 1


static func level(index: int, over: Dictionary = {}) -> LevelDef:
	var l := LevelDef.new()
	l.id = "L%d" % (index + 1)
	# Campaign levels carry 1-based indices (data/levels/README.md); `index` is the path position.
	l.index = index + 1
	l.name = "Level %d" % (index + 1)
	l.tagline = "Tagline %d" % (index + 1)
	l.theme = LevelTheme.UPPER
	l.bpm = 120
	l.bars = 4
	l.horizon_bars = 8
	l.max_tapes = 2
	l.speeds.assign([1.0, 2.0])
	l.map.assign(["###", "#.#", "###"])
	l.start = Vector2(1.5, 1.5)
	for k: String in over:
		match k:
			"loot":
				l.loot.assign(over[k])
			"speeds":
				l.speeds.assign(over[k])
			"end_modes":
				l.end_modes.assign(over[k])
			_:
				l.set(k, over[k])
	return l


static func campaign(cleared_count: int, total: int = 5) -> CampaignScreenModel:
	var m := CampaignScreenModel.new()
	var current := mini(cleared_count, total - 1)
	for i in total:
		var lv := level(i, {"loot": ["boots"] if i == 0 else []})
		m.levels.append(CampaignLevelEntry.make(lv, i < cleared_count, i <= current))
	m.current = current
	return m


static func swing(windup: float, active: float, recover: float, impact: float, move_mul: float) -> MeleeSwingDef:
	var s := MeleeSwingDef.new()
	s.windup = windup
	s.active = active
	s.recover = recover
	s.impact = impact
	s.move_mul = move_mul
	return s


static func blade() -> MeleeWeaponDef:
	var m := MeleeWeaponDef.new()
	m.reach = 1.2
	m.arc_deg = 110
	m.light = swing(6, 4, 10, 1, 0.4)
	m.heavy = swing(18, 5, 18, 2.2, 0.2)
	m.damage_eff = 1
	m.knockback_eff = 1
	m.stagger_eff = 1
	m.style = MeleeStyle.BLADE
	return m


static func maul() -> MeleeWeaponDef:
	var m := MeleeWeaponDef.new()
	m.reach = 1.5
	m.arc_deg = 150
	m.light = swing(12, 5, 16, 1.4, 0.3)
	m.heavy = swing(30, 6, 24, 3.2, 0.1)
	m.damage_eff = 0.8
	m.knockback_eff = 1.6
	m.stagger_eff = 1.2
	m.style = MeleeStyle.BLUNT
	return m


static func missile() -> RangedWeaponDef:
	var r := RangedWeaponDef.new()
	r.archetype = RangedArchetype.MISSILE
	r.speed = 2.5
	r.max_range = 18
	r.impact = 1.2
	r.commit = 12
	r.cooldown = 90
	r.pierce = 0
	r.count = 1
	r.turn_rate = PI
	return r


static func rail() -> RangedWeaponDef:
	var r := missile()
	r.archetype = RangedArchetype.PIERCE
	r.speed = 22
	r.max_range = 12
	r.pierce = 3
	r.turn_rate = 0
	r.cooldown = 45
	r.commit = 8
	r.impact = 0.9
	return r


static func item(id: String, slot: StringName, name: String, effect: String, lore: String = "") -> GearItem:
	var g := GearItem.new()
	g.id = id
	g.slot = slot
	g.name = name
	g.effect = effect
	g.lore = lore
	return g


static func mods(d: Dictionary) -> StatMods:
	return StatMods.from_dict(d)


static func gear() -> Array[GearItem]:
	var hood := item("hood", GearSlot.HELMET, "Hood", "Enemies think you are farther away.", "quiet")
	hood.abilities.assign([AbilityId.LOW_PROFILE])
	var glide := item("glide", GearSlot.PANTS, "Glide", "Momentum +25%.")
	glide.mods = mods({"momentumRetention": 1.25, "accel": 0.9})
	var boots := item("boots", GearSlot.SHOES, "Boots", "Faster dodge.")
	boots.mods = mods({"dodgeCooldown": 0.8, "moveSpeed": 1.1})
	var bl := item("blade", GearSlot.MELEE, "Blade", "Baseline.")
	bl.melee = blade()
	var ma := item("maul", GearSlot.MELEE, "Maul", "Big knockback.")
	ma.melee = maul()
	var mi := item("missile", GearSlot.RANGED, "Missile", "Slow homing.")
	mi.ranged = missile()
	var ra := item("rail", GearSlot.RANGED, "Rail", "Pierces.")
	ra.ranged = rail()
	return [
		item("cap", GearSlot.HELMET, "Cap", "No special effect."),
		hood,
		item("crop", GearSlot.TOP, "Crop", "No special effect."),
		item("cargo", GearSlot.PANTS, "Cargo", "No special effect."),
		glide,
		item("kicks", GearSlot.SHOES, "Kicks", "No special effect."),
		boots,
		bl,
		ma,
		mi,
		ra,
	]


static func find(items: Array[GearItem], id: String) -> GearItem:
	for g in items:
		if g.id == id:
			return g
	return null


static func base_loadout() -> Loadout:
	return Loadout.make("cap", "crop", "cargo", "kicks", "blade", "missile")


static func loadout_model(inventory: Array[GearItem] = [], loadout: Loadout = null, summary: Array[String] = []) -> LoadoutScreenModel:
	var m := LoadoutScreenModel.new()
	m.inventory = inventory if not inventory.is_empty() else gear()
	m.loadout = loadout if loadout != null else base_loadout()
	m.summary = summary
	m.fresh.assign(["boots"])
	return m


static func results(has_next: bool = true, next_id: String = "") -> ResultsModel:
	var m := ResultsModel.new()
	m.level = level(2, {"max_tapes": 3})
	var o := Outcome.new()
	o.win = true
	o.objective_complete = true
	o.survivors.assign([0])
	o.notes.assign(["Tape A held the plate."])
	m.outcome = o
	m.tapes_used = 2
	m.loot.assign([gear()[1]])
	m.has_next = has_next
	m.next_id = next_id
	return m


static func entry_ids(entries: Array[MenuEntry]) -> Array[String]:
	var out: Array[String] = []
	for e in entries:
		out.append(e.id)
	return out
