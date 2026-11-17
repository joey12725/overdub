extends ODTest
## Gear / weapon / level text formatting (port of prototype tests/ui-menus/format.test.ts;
## APPAREL-03, WEAPON-01..04).

const F := preload("res://tests/ui_menus/menu_fixtures.gd")
const M := MenuFormat.MINUS


func _rows(rows: Array[MenuFormat.StatRow]) -> Dictionary:
	var out := {}
	for r in rows:
		out[r.label] = r.value
	return out


func _cmp(rows: Array[MenuFormat.CompareRow]) -> Dictionary:
	var out := {}
	for r in rows:
		out[r.label] = r
	return out


func _cmp_list(rows: Array[MenuFormat.CompareRow]) -> Array:
	var out := []
	for r in rows:
		out.append([r.label, r.from, r.to, r.dir])
	return out


func test_apparel_03_six_slots_distinct_titles_kinds_short_codes() -> void:
	var titles := {}
	var kinds := {}
	var shorts := {}
	for slot in GearSlot.ALL:
		var l := MenuFormat.slot_label(slot)
		titles[l.title] = true
		kinds[l.kind] = true
		shorts[l.short] = true
		assert_false(l.touches.is_empty(), "slot %s states what it touches" % slot)
	assert_eq(GearSlot.ALL.size(), 6)
	assert_eq(titles.size(), 6)
	assert_eq(kinds.size(), 6)
	assert_eq(shorts.size(), 6)


func test_apparel_03_plain_category_names() -> void:
	assert_eq(MenuFormat.slot_label(GearSlot.HELMET).title, "HELMET / HEADGEAR")
	assert_eq(MenuFormat.slot_label(GearSlot.TOP).title, "TOP")
	assert_eq(MenuFormat.slot_label(GearSlot.PANTS).title, "PANTS")
	assert_eq(MenuFormat.slot_label(GearSlot.SHOES).title, "SHOES")
	assert_eq(MenuFormat.slot_label(GearSlot.MELEE).title, "MELEE")
	assert_eq(MenuFormat.slot_label(GearSlot.RANGED).title, "RANGED")


func test_number_formatting() -> void:
	assert_eq(MenuFormat.num(1.5), "1.5")
	assert_eq(MenuFormat.num(2), "2")
	assert_eq(MenuFormat.num(0.125, 2), "0.13")
	assert_eq(MenuFormat.num(150, 0), "150")
	assert_eq(MenuFormat.pct(1.1), "+10%")
	assert_eq(MenuFormat.pct(0.85), M + "15%")
	assert_eq(MenuFormat.pct(1), "±0%")
	assert_eq(MenuFormat.ticks_to_seconds(6), "0.1 s")
	assert_eq(MenuFormat.ticks_to_seconds(60), "1 s")
	assert_eq(MenuFormat.speed_label(0.5), "½×")
	assert_eq(MenuFormat.speed_label(4), "4×")
	assert_eq(MenuFormat.speed_label(1), "1×")
	assert_eq(MenuFormat.end_mode_label(OD.EndMode.REVERSE), "Reverse")
	assert_eq(MenuFormat.theme_label(LevelTheme.LOWER), "Inscribed depths")


func test_mod_lines_state_non_neutral_mods_in_plain_language() -> void:
	var m := F.mods({"moveSpeed": 1.1, "dodgeCooldown": 0.8, "interactRadiusAdd": 0.75, "damage": 1})
	assert_eq(MenuFormat.mod_lines(m), ["Run speed +10%", "Dodge cooldown " + M + "20%", "Interact reach +0.75 tiles"])
	assert_eq(MenuFormat.mod_lines(null), [])


func test_weapon_04_melee_rows() -> void:
	var rows := _rows(MenuFormat.melee_stat_rows(F.maul()))
	assert_eq(rows["Style"], "Blunt")
	assert_eq(rows["Reach"], "1.5 tiles")
	assert_eq(rows["Arc"], "150°")
	assert_eq(rows["Light"], "0.2 s windup · 0.08 s hit · 0.27 s recover (0.55 s total at 1×)")
	assert_eq(rows["Heavy"], "0.5 s windup · 0.1 s hit · 0.4 s recover (1 s total at 1×)")
	assert_eq(rows["Impact"], "light 1.4 · heavy 3.2")
	assert_eq(rows["Knockback"], "1.6× (very high)")
	assert_eq(rows["Damage"], "0.8× (low)")
	assert_eq(rows["Stagger"], "1.2× (high)")


func test_weapon_01_03_ranged_rows() -> void:
	var missile := _rows(MenuFormat.ranged_stat_rows(F.missile()))
	assert_eq(missile["Type"], "Homing missile")
	assert_eq(missile["Speed"], "2.5 tiles/s (very slow)")
	assert_eq(missile["Range"], "18 tiles")
	assert_eq(missile["Homing"], "180°/s turn, one lock at launch")
	var rail := _rows(MenuFormat.ranged_stat_rows(F.rail()))
	assert_eq(rail["Speed"], "22 tiles/s (fast)")
	assert_eq(rail["Pierce"], "passes through 3 enemies")
	assert_false(rail.has("Homing"))
	var mortar := F.missile()
	mortar.archetype = RangedArchetype.ARC
	mortar.lobbed = true
	mortar.blast = 1.2
	mortar.has_min_range = true
	mortar.min_range = 3
	mortar.turn_rate = 0
	var mrows := _rows(MenuFormat.ranged_stat_rows(mortar))
	assert_has(mrows, "Trajectory")
	assert_has(mrows, "Blast")
	assert_eq(mrows.get("Min range"), "never lands closer than 3 tiles")


func test_weapon_02_every_ranged_weapon_states_a_downside() -> void:
	var d := MenuFormat.ranged_downside(F.missile())
	assert_true(d.to_lower().contains("slow"), d)
	assert_true(d.contains("long cooldown (1.5 s)"), d)
	assert_true(MenuFormat.ranged_downside(F.rail()).to_lower().contains("straight"))
	assert_eq(MenuFormat.ranged_downside(F.rail(), "Custom."), "Custom.")
	var rows := _rows(MenuFormat.item_detail_rows(F.find(F.gear(), "rail")))
	assert_has(rows, "Downside")
	# Enemy-only archetypes still format without errors.
	var bolt := F.rail()
	bolt.archetype = RangedArchetype.BOLT
	assert_eq(MenuFormat.archetype_name(RangedArchetype.BOLT), "Bolt")
	assert_false(_rows(MenuFormat.ranged_stat_rows(bolt)).is_empty())


func test_weapon_headline() -> void:
	var g := F.gear()
	assert_eq(MenuFormat.weapon_headline(F.find(g, "blade")), "Blade · reach 1.2 · 110° arc · light 0.1 s windup")
	assert_eq(MenuFormat.weapon_headline(F.find(g, "missile")), "Homing missile · 2.5 tiles/s · 18 tiles")
	assert_eq(MenuFormat.weapon_headline(g[0]), "")


func test_item_detail_rows_cover_mods_and_abilities() -> void:
	var g := F.gear()
	var boots := _rows(MenuFormat.item_detail_rows(F.find(g, "boots")))
	assert_eq(boots["Run speed"], "+10%")
	assert_eq(boots["Dodge cooldown"], M + "20%")
	var hood := _rows(MenuFormat.item_detail_rows(F.find(g, "hood")))
	assert_eq(hood["Low profile"], "Enemies treat you as farther away than you are.")


func test_melee_comparison() -> void:
	var a := F.item("a", GearSlot.MELEE, "A", "")
	a.melee = F.maul()
	var b := F.item("b", GearSlot.MELEE, "B", "")
	b.melee = F.blade()
	var by := _cmp(MenuFormat.compare_items(a, b))
	assert_eq((by["Light windup"] as MenuFormat.CompareRow).dir, 1)
	assert_eq((by["Light impact"] as MenuFormat.CompareRow).dir, -1)
	var reach: MenuFormat.CompareRow = by["Reach"]
	assert_eq([reach.from, reach.to, reach.dir], ["1.5 tiles", "1.2 tiles", -1])
	assert_eq((by["Knockback"] as MenuFormat.CompareRow).dir, -1)
	assert_eq((by["Damage"] as MenuFormat.CompareRow).dir, 1)


func test_ranged_comparison_lower_cooldown_is_better() -> void:
	var g := F.gear()
	var by := _cmp(MenuFormat.compare_items(F.find(g, "missile"), F.find(g, "rail")))
	assert_eq((by["Cooldown"] as MenuFormat.CompareRow).dir, 1)
	assert_eq((by["Speed"] as MenuFormat.CompareRow).dir, 1)
	assert_eq((by["Range"] as MenuFormat.CompareRow).dir, -1)
	var t: MenuFormat.CompareRow = by["Type"]
	assert_eq([t.from, t.to, t.dir], ["Homing missile", "Piercing shot", 0])


func test_apparel_comparison_lists_only_changes() -> void:
	var g := F.gear()
	assert_eq(_cmp_list(MenuFormat.compare_items(F.find(g, "cargo"), F.find(g, "glide"))), [
		["Acceleration", "±0%", M + "10%", -1],
		["Momentum kept on turns", "±0%", "+25%", 1],
	])
	var shoe := _cmp(MenuFormat.compare_items(F.find(g, "kicks"), F.find(g, "boots")))
	assert_eq((shoe["Dodge cooldown"] as MenuFormat.CompareRow).dir, 1)
	assert_eq(_cmp_list(MenuFormat.compare_items(g[0], g[1])), [["Low profile", "—", "gained", 1]])
	assert_eq(_cmp_list(MenuFormat.compare_items(g[1], g[0])), [["Low profile", "yes", "lost", -1]])


func test_real_catalogue_formats_every_item() -> void:
	var errors: Array[String] = []
	var cat := ContentData.load_gear(errors)
	if not assert_true(cat != null, "gear.json loads: %s" % [errors]):
		return
	for it in cat.items:
		var rows := MenuFormat.item_detail_rows(it)
		if it.melee != null or it.ranged != null:
			assert_false(rows.is_empty(), "%s has mechanics rows" % it.id)
			assert_false(MenuFormat.weapon_headline(it).is_empty(), "%s has a headline" % it.id)
		for r in rows:
			assert_false(r.value.is_empty(), "%s / %s has a value" % [it.id, r.label])
	# Every ranged weapon in the catalogue states a downside (WEAPON-02).
	for it in cat.items_in_slot(GearSlot.RANGED):
		assert_false(MenuFormat.ranged_downside(it.ranged, it.downside).is_empty(), it.id)
