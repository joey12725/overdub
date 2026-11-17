extends ODTest
## Fixed-path campaign (LEVEL-08, LEVEL-09), loot (GEAR-04) and between-level loadouts (GEAR-03).
## Port of prototype/tests/game/campaign.test.ts.

const LOOT_1: Array[String] = ["reel_lash", "hush_hood"]
const LOOT_2: Array[String] = ["needle_rail"]


func _path() -> Array[LevelDef]:
	var none: Array[String] = []
	var out: Array[LevelDef] = []
	out.append(TestLevels.make_level({"id": "l2", "index": 2, "name": "Third", "loot": none}))
	out.append(TestLevels.make_level({"id": "l0", "index": 0, "name": "First", "loot": LOOT_1}))
	out.append(TestLevels.make_level({"id": "l1", "index": 1, "name": "Second", "loot": LOOT_2}))
	return out


func _ids(items: Array[GearItem]) -> Array[String]:
	var out: Array[String] = []
	for it: GearItem in items:
		out.append(it.id)
	return out


func test_orders_the_path_by_index_and_opens_only_the_first_level_on_a_fresh_save() -> void:
	var c := GameCampaign.new(_path(), GameSave.fresh_save())
	var ids: Array[String] = []
	for l: LevelDef in c.levels:
		ids.append(l.id)
	assert_eq(ids, ["l0", "l1", "l2"])
	assert_eq([c.is_unlocked("l0"), c.is_unlocked("l1"), c.is_unlocked("l2")], [true, false, false])
	assert_eq(c.current_index(), 0)
	assert_false(c.begin_level("l1"))
	assert_false(c.is_unlocked("nope"))


func test_level_08_09_clearing_a_level_opens_the_next_cleared_levels_stay_replayable() -> void:
	var c := GameCampaign.new(_path(), GameSave.fresh_save())
	c.record_clear("l0")
	assert_eq([c.is_unlocked("l0"), c.is_unlocked("l1"), c.is_unlocked("l2")], [true, true, false])
	assert_eq(c.current_index(), 1)
	c.record_clear("l1")
	c.record_clear("l2")
	assert_true(c.all_cleared())
	assert_eq(c.current_index(), 2)
	for id: String in ["l0", "l1", "l2"]:
		assert_true(c.begin_level(id), id)
	assert_eq(c.next_level("l0").id, "l1")
	assert_true(c.next_level("l2") == null)


func test_gear_04_awards_loot_once_on_the_first_clear_only() -> void:
	var c := GameCampaign.new(_path(), GameSave.fresh_save())
	var first := c.record_clear("l0")
	assert_true(first.first_clear)
	assert_eq(_ids(first.loot), LOOT_1)
	for id: String in LOOT_1:
		assert_has(c.save.inventory, id)
	var size := c.save.inventory.size()
	var again := c.record_clear("l0")
	assert_false(again.first_clear)
	assert_eq(again.loot.size(), 0)
	assert_eq(c.save.inventory.size(), size)
	assert_eq(c.save.cleared, ["l0"])
	# The loadout screen marks the new items once.
	assert_eq(c.loadout_model(true).fresh, LOOT_1)
	assert_eq(c.loadout_model().fresh.size(), 0)


func test_gear_03_loadout_changes_only_between_levels_only_to_owned_items_of_the_right_slot() -> void:
	var base := CampaignData.base_loadout()
	var c := GameCampaign.new(_path(), GameSave.fresh_save())
	assert_false(c.equip(GearSlot.MELEE, "reel_lash"), "not owned yet")
	c.record_clear("l0")
	assert_false(c.equip(GearSlot.HELMET, "reel_lash"), "wrong slot")
	assert_false(c.equip(GearSlot.MELEE, "no_such_item"))
	assert_true(c.begin_level("l1"))
	assert_false(c.equip(GearSlot.MELEE, "reel_lash"), "locked during an attempt")
	assert_eq(c.save.loadout.melee, base.melee)
	c.end_level()
	assert_true(c.equip(GearSlot.MELEE, "reel_lash"))
	assert_eq(c.save.loadout.melee, "reel_lash")
	assert_json_eq(c.resolved_loadout().melee.to_dict(), CampaignData.gear().get_item("reel_lash").melee.to_dict())
	# Baseline gear is always available to swap back to.
	assert_true(c.equip(GearSlot.MELEE, base.melee))


func test_builds_the_campaign_screen_model() -> void:
	var c := GameCampaign.new(_path(), GameSave.fresh_save())
	c.record_clear("l0")
	var m := c.campaign_model()
	assert_eq(m.current, 1)
	var rows: Array = []
	for e: CampaignLevelEntry in m.levels:
		rows.append([e.level.id, e.cleared, e.unlocked])
	assert_eq(rows, [["l0", true, true], ["l1", false, true], ["l2", false, false]])
	assert_true(m.levels[0].has_loot)
	assert_eq(_ids(m.levels[0].loot), LOOT_1)
	assert_false(m.levels[1].has_loot)


func test_sanitises_a_save_it_is_handed() -> void:
	var save := GameSave.fresh_save()
	save.loadout.melee = "reel_lash"
	var c := GameCampaign.new(_path(), save)
	assert_eq(c.save.loadout.melee, CampaignData.base_loadout().melee)


func test_loadout_model_lists_owned_items_per_slot_with_a_summary() -> void:
	var c := GameCampaign.new(_path(), GameSave.fresh_save())
	c.record_clear("l0")
	var m := c.loadout_model()
	var ids := _ids(m.inventory)
	assert_has(ids, "reel_lash")
	assert_has(ids, "hush_hood")
	assert_eq(ids.size(), OD.GEAR_SLOTS.size() + LOOT_1.size())
	assert_true(m.summary.size() >= 2)
	assert_json_eq(m.loadout.to_dict(), c.save.loadout.to_dict())


func test_settings_are_validated_and_replace_save_ends_the_gear_lock() -> void:
	var c := GameCampaign.new(_path(), GameSave.fresh_save())
	var st := SaveSettings.new()
	st.music = 3.0
	st.av_offset_ms = -999
	c.set_settings(st)
	assert_eq(c.save.settings.music, 1.0)
	assert_eq(c.save.settings.av_offset_ms, -GameSave.AV_OFFSET_LIMIT)
	c.begin_level("l0")
	assert_eq(c.active_level, "l0")
	c.replace_save(GameSave.fresh_save())
	assert_eq(c.active_level, "")
