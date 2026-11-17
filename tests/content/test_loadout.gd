extends ODTest
## Loadout resolution, the loadout summary and inventory helpers (APPAREL-01..03, APP-TEST-01/02,
## GEAR-04). Port of the loadout parts of prototype/tests/content/gear.test.ts, against
## data/gear.json.

const CLOTHING: Array[StringName] = [GearSlot.HELMET, GearSlot.TOP, GearSlot.PANTS, GearSlot.SHOES]


func _cat() -> ContentData.GearCatalogue:
	return CampaignData.gear()


func _base() -> Loadout:
	return CampaignData.base_loadout()


func _with(changes: Dictionary) -> Loadout:
	var lo := _base()
	for k: Variant in changes:
		lo.set_slot(StringName(k), changes[k])
	return lo


func _ids(items: Array[GearItem]) -> Array[String]:
	var out: Array[String] = []
	for it: GearItem in items:
		out.append(it.id)
	return out


func test_catalogue_loads() -> void:
	assert_true(_cat().items.size() >= 24, "data/gear.json has the catalogue")
	for slot: StringName in OD.GEAR_SLOTS:
		var it := _cat().get_item(_base().get_slot(slot))
		assert_true(it != null and it.slot == slot, String(slot))


func test_baseline_resolves_to_identity_all_multipliers_1_adds_0_no_abilities() -> void:
	var r := LoadoutRules.resolve_loadout(_base())
	assert_json_eq(r.mods.to_dict(true), LoadoutRules.identity_mods().to_dict(true))
	for k: String in StatMods.keys():
		assert_eq(r.mods.get_stat(k), 0.0 if k.ends_with("Add") else 1.0, k)
	assert_eq(r.abilities.size(), 0)
	assert_json_eq(r.loadout.to_dict(), _base().to_dict())
	assert_json_eq(r.melee.to_dict(), _cat().get_item(_base().melee).melee.to_dict())
	assert_json_eq(r.ranged.to_dict(), _cat().get_item(_base().ranged).ranged.to_dict())


func test_returns_weapon_copies_not_the_catalogue_objects() -> void:
	var r := LoadoutRules.resolve_loadout(_base())
	r.melee.light.impact = 99.0
	r.ranged.speed = 99.0
	assert_eq(_cat().get_item(_base().melee).melee.light.impact, 1.0)
	assert_ne(_cat().get_item(_base().ranged).ranged.speed, 99.0)


func test_multipliers_multiply_and_adds_add_across_slots() -> void:
	var top := _cat().get_item("ballast_puffer")  # moveSpeed 0.92, meleeImpact 1.25
	var shoes := _cat().get_item("grip_sprinters")  # moveSpeed 1.12, dodgeIframes 0.8
	var pants := _cat().get_item("parachute_pants")  # dodgeIframes 1.3, dodgeCooldown 1.2
	var r := LoadoutRules.resolve_loadout(_with({"top": top.id, "shoes": shoes.id, "pants": pants.id}))
	assert_near(r.mods.move_speed, top.mods.move_speed * shoes.mods.move_speed, 1e-10)
	assert_near(r.mods.dodge_iframes, shoes.mods.dodge_iframes * pants.mods.dodge_iframes, 1e-10)
	assert_near(r.mods.melee_impact, 1.25, 1e-10)
	var hoodie := LoadoutRules.resolve_loadout(_with({"top": "patchcord_hoodie"}))
	assert_near(hoodie.mods.interact_radius_add, 0.75, 1e-10)


func test_unions_abilities_without_duplicates() -> void:
	var r := LoadoutRules.resolve_loadout(_with({"helmet": "hush_hood", "top": "dropout_jacket", "shoes": "static_runners"}))
	var got: Array[String] = []
	for a: StringName in r.abilities:
		got.append(String(a))
	got.sort()
	assert_eq(got, ["lowProfile", "manualDesync", "phaseDodge"])


func test_unknown_wrong_slot_and_missing_ids_fall_back_to_baseline() -> void:
	var bad := Loadout.new()
	bad.helmet = "no_such_item"
	bad.top = "splice_blade"
	bad.melee = "mixtape_rocket"
	var r := LoadoutRules.resolve_loadout(bad)
	assert_json_eq(r.loadout.to_dict(), _base().to_dict())
	assert_eq(r.melee.style, MeleeStyle.BLADE)
	assert_eq(r.ranged.archetype, RangedArchetype.MISSILE)
	assert_json_eq(LoadoutRules.resolve_loadout(null).loadout.to_dict(), _base().to_dict())


func test_picks_the_equipped_weapons() -> void:
	var r := LoadoutRules.resolve_loadout(_with({"melee": "reel_lash", "ranged": "bass_drop"}))
	assert_eq(r.melee.style, MeleeStyle.WHIP)
	assert_eq(r.ranged.archetype, RangedArchetype.ARC)


func test_app_test_01_swapping_each_clothing_slot_changes_the_resolved_numbers_or_abilities() -> void:
	var base := LoadoutRules.resolve_loadout(_base())
	for slot: StringName in CLOTHING:
		var alternatives: Array[GearItem] = []
		for it: GearItem in _cat().items_in_slot(slot):
			if it.id != _base().get_slot(slot):
				alternatives.append(it)
		assert_true(alternatives.size() > 0, String(slot))
		for alt: GearItem in alternatives:
			var r := LoadoutRules.resolve_loadout(_with({String(slot): alt.id}))
			var changed := not ODJson.deep_equal(r.mods.to_dict(true), base.mods.to_dict(true)) or r.abilities.size() != base.abilities.size()
			assert_true(changed, "%s: %s" % [slot, alt.id])


func test_resolve_collects_gear_looks() -> void:
	for it: GearItem in _cat().items:
		if it.look == null:
			continue
		var r := LoadoutRules.resolve_loadout(_with({String(it.slot): it.id}))
		assert_true(r.looks.has(it.slot), it.id)
		return
	assert_true(true)


func test_describe_names_both_weapons_and_says_the_baseline_has_no_clothing_modifiers() -> void:
	var lines := LoadoutRules.describe_loadout(_base())
	var text := "\n".join(lines)
	assert_true(text.contains(_cat().get_item(_base().melee).name))
	assert_true(text.contains(_cat().get_item(_base().ranged).name))
	assert_true(text.to_lower().contains("no modifiers"))


func test_app_test_02_describe_reports_combined_stats_and_abilities_after_a_swap() -> void:
	var lines := LoadoutRules.describe_loadout(_with({"shoes": "spring_soles", "helmet": "click_visor", "top": "patchcord_hoodie"}))
	assert_has(lines, "Dodge distance +17%")  # 1.3 * 0.9 = 1.17
	assert_has(lines, "Dodge cooldown +20%")
	assert_has(lines, "Switch reach +0.75 tiles")
	var text := "\n".join(lines)
	assert_true(text.contains("beat ruler"), text)
	assert_false(text.to_lower().contains("no modifiers"))


func test_describe_weapon_lines_read_like_the_prototype() -> void:
	var lines := LoadoutRules.describe_loadout(_base())
	var m := _cat().get_item(_base().melee)
	assert_true(lines[0].begins_with("Melee: %s. " % m.name), lines[0])
	assert_true(lines[0].contains("-tile reach, ") and lines[0].contains("° arc, light ") and lines[0].ends_with(" s."), lines[0])
	assert_true(lines[1].begins_with("Ranged: "), lines[1])
	assert_true(lines[1].contains("tiles/s") and lines[1].ends_with(" s cooldown."), lines[1])


func test_every_clothing_swap_changes_the_description() -> void:
	var base := "\n".join(LoadoutRules.describe_loadout(_base()))
	for slot: StringName in CLOTHING:
		for alt: GearItem in _cat().items_in_slot(slot):
			if alt.id == _base().get_slot(slot):
				continue
			assert_ne("\n".join(LoadoutRules.describe_loadout(_with({String(slot): alt.id}))), base, alt.id)


func test_base_inventory_holds_exactly_the_baseline_items() -> void:
	var inv := CampaignData.base_inventory()
	inv.sort()
	var ids := _base().ids()
	ids.sort()
	assert_eq(inv, ids)


func test_items_for_slot_lists_baseline_first_then_owned_items_of_that_slot_only() -> void:
	var inv: Array[String] = ["reel_lash", "hush_hood", "nonsense", "reel_lash", "splice_blade"]
	assert_eq(_ids(LoadoutRules.items_for_slot(inv, GearSlot.MELEE)), ["splice_blade", "reel_lash"])
	var none: Array[String] = []
	assert_eq(_ids(LoadoutRules.items_for_slot(none, GearSlot.HELMET)), [_base().helmet])
	assert_eq(_ids(LoadoutRules.items_for_slot(inv, GearSlot.HELMET)), [_base().helmet, "hush_hood"])


func test_sanitise_keeps_valid_owned_picks() -> void:
	var inv := CampaignData.base_inventory()
	inv.append_array(["reel_lash", "hush_hood"])
	var lo := _with({"melee": "reel_lash", "helmet": "hush_hood"})
	assert_json_eq(LoadoutRules.sanitise_loadout(lo, inv).to_dict(), lo.to_dict())


func test_sanitise_repairs_unknown_unowned_wrong_slot_and_missing_entries() -> void:
	var bad := Loadout.new()
	bad.helmet = "feedback_crown"  # not owned
	bad.top = "amp_sledge"  # owned, wrong slot
	bad.pants = "ghost_pants"  # unknown
	bad.melee = "reel_lash"  # fine
	bad.ranged = "42"  # garbage
	# shoes missing
	var inv: Array[String] = ["reel_lash", "amp_sledge"]
	var out := LoadoutRules.sanitise_loadout(bad, inv)
	assert_json_eq(out.to_dict(), _with({"melee": "reel_lash"}).to_dict())
	var none: Array[String] = []
	assert_json_eq(LoadoutRules.sanitise_loadout(null, none).to_dict(), _base().to_dict())
	for slot: StringName in OD.GEAR_SLOTS:
		assert_eq(_cat().get_item(out.get_slot(slot)).slot, slot)


func test_is_baseline_and_stat_helpers() -> void:
	assert_true(LoadoutRules.is_baseline(_base().melee))
	assert_false(LoadoutRules.is_baseline("reel_lash"))
	assert_true(LoadoutRules.is_additive_stat("interactRadiusAdd"))
	assert_false(LoadoutRules.is_additive_stat("moveSpeed"))
	var a := StatMods.new()
	a.move_speed = 1.1
	a.interact_radius_add = 0.5
	var b := StatMods.new()
	b.move_speed = 2.0
	b.interact_radius_add = 0.25
	b.damage = NAN
	var list: Array[StatMods] = [a, null, b]
	var c := LoadoutRules.combine_mods(list)
	assert_near(c.move_speed, 2.2, 1e-12)
	assert_near(c.interact_radius_add, 0.75, 1e-12)
	assert_eq(c.damage, 1.0, "non-finite values are ignored")
