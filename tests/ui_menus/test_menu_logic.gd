extends ODTest
## Screen logic: focus movement per screen and the intent each action emits (port of prototype
## tests/ui-menus/logic.test.ts; LEVEL-08/09, APPAREL-03, GEAR-03/04, APP-TEST-02).

const F := preload("res://tests/ui_menus/menu_fixtures.gd")

const UP := UiBase.NAV_UP
const DOWN := UiBase.NAV_DOWN
const LEFT := UiBase.NAV_LEFT
const RIGHT := UiBase.NAV_RIGHT
const ACCEPT := UiBase.NAV_ACCEPT
const BACK := UiBase.NAV_BACK


class Flag:
	extends RefCounted
	var on: bool = false


func _press(host: MenuHost, cmds: Array[StringName]) -> void:
	for c in cmds:
		host.navigate(c)


func _times(cmd: StringName, n: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in n:
		out.append(cmd)
	return out


# ───────────────────────────── title ─────────────────────────────

func test_title_with_progress_continue_first_new_asks_before_erasing() -> void:
	var r := F.Recorder.new()
	var logic := MenuTitleLogic.new(r.emit, func() -> bool: return true)
	var host := MenuHost.new(logic)
	assert_eq(F.entry_ids(host.entries), ["continue", "new", "loadout", "settings", "quit"])
	assert_eq(host.focus, "continue")
	host.navigate(ACCEPT)
	assert_eq(r.descs(), ["openCampaign"])

	host.navigate(DOWN)
	host.navigate(ACCEPT)
	assert_true(logic.confirming_new)
	# Lands on the safe choice so a double press cannot erase.
	assert_eq(host.focus, "new-no")
	host.navigate(BACK)
	assert_false(logic.confirming_new)
	assert_eq(host.focus, "new")
	assert_eq(r.intents.size(), 1)

	_press(host, [ACCEPT, RIGHT, ACCEPT])
	assert_eq(r.descs().slice(1), ["eraseSave", "openCampaign"])


func test_title_without_progress_new_goes_straight_to_the_path() -> void:
	var r := F.Recorder.new()
	var host := MenuHost.new(MenuTitleLogic.new(r.emit, func() -> bool: return false))
	assert_eq(F.entry_ids(host.entries), ["new", "loadout", "settings", "quit"])
	assert_eq(host.focus, "new")
	host.navigate(ACCEPT)
	assert_eq(r.descs(), ["openCampaign"])


func test_title_jumps_to_continue_when_the_save_arrives() -> void:
	var progress := Flag.new()
	var host := MenuHost.new(MenuTitleLogic.new(func(_i: UiIntent) -> void: pass, func() -> bool: return progress.on))
	assert_eq(host.focus, "new")
	progress.on = true
	host.refresh()
	assert_eq(host.focus, "continue")


func test_title_loadout_settings_quit_emit_their_intents() -> void:
	var r := F.Recorder.new()
	var host := MenuHost.new(MenuTitleLogic.new(r.emit, func() -> bool: return false))
	_press(host, [DOWN, ACCEPT, DOWN, ACCEPT, DOWN, ACCEPT])
	assert_eq(r.descs(), ["openLoadout", "openSettings", String(MenuTitleLogic.QUIT_GAME)])


func test_title_quit_can_be_omitted() -> void:
	var host := MenuHost.new(MenuTitleLogic.new(func(_i: UiIntent) -> void: pass, func() -> bool: return false, false))
	assert_eq(F.entry_ids(host.entries), ["new", "loadout", "settings"])


# ───────────────────────────── campaign ─────────────────────────────

func test_level_08_focuses_next_uncleared_level_and_walks_vertically() -> void:
	var r := F.Recorder.new()
	var logic := MenuCampaignLogic.new(r.emit)
	logic.set_model(F.campaign(2))
	var host := MenuHost.new(logic)
	assert_eq(host.focus, "level:L3")
	host.navigate(UP)
	assert_eq(host.focus, "level:L2")
	_press(host, [UP, UP])
	assert_eq(host.focus, "back")
	host.navigate(RIGHT)
	assert_eq(host.focus, "loadout")


func test_level_09_cleared_levels_replay_locked_levels_refuse() -> void:
	var r := F.Recorder.new()
	var logic := MenuCampaignLogic.new(r.emit)
	logic.set_model(F.campaign(2))
	var host := MenuHost.new(logic)
	_press(host, [UP, ACCEPT])
	assert_eq(r.descs(), ["playLevel:L2"])
	_press(host, [DOWN, DOWN])
	assert_eq(host.focus, "level:L4")
	host.navigate(ACCEPT)
	assert_eq(r.intents.size(), 1)
	assert_eq(logic.locked_pokes, 1)
	assert_eq(logic.last_poked, "level:L4")


func test_campaign_right_reaches_loadout_back_returns_to_title() -> void:
	var r := F.Recorder.new()
	var logic := MenuCampaignLogic.new(r.emit)
	logic.set_model(F.campaign(1))
	var host := MenuHost.new(logic)
	host.navigate(RIGHT)
	assert_eq(host.focus, "loadout")
	_press(host, [ACCEPT, BACK])
	assert_eq(r.descs(), ["openLoadout", "openTitle"])


func test_campaign_on_show_refocuses_the_next_level() -> void:
	var logic := MenuCampaignLogic.new(func(_i: UiIntent) -> void: pass)
	logic.set_model(F.campaign(1))
	var host := MenuHost.new(logic)
	_press(host, [UP, UP])
	assert_eq(host.focus, "back")
	logic.on_show()
	host.refresh()
	assert_eq(host.focus, "level:L2")


func test_campaign_nodes_carry_tapes_speeds_modes_status_hide_unfound_loot() -> void:
	var model := F.campaign(1, 3)
	model.levels[0].loot.assign([F.gear()[6]])
	model.levels[0].has_loot = true
	model.levels[2].level = F.level(2, {"theme": LevelTheme.CORE, "max_tapes": 4, "speeds": [0.5, 1.0, 2.0, 4.0],
		"end_modes": [OD.EndMode.STOP, OD.EndMode.REVERSE], "loot": ["x"]})
	var nodes := MenuModels.campaign_nodes(model)
	assert_eq(nodes.map(func(n: MenuModels.CampaignNode) -> String: return n.status), ["cleared", "next", "locked"])
	assert_eq(nodes[0].loot_count, 1)
	assert_true(nodes[0].loot_found)
	assert_eq(nodes[0].loot_items.size(), 1)
	assert_eq([nodes[0].loot_items[0].name, nodes[0].loot_items[0].slot, nodes[0].loot_items[0].effect], ["Boots", "SHOES", "Faster dodge."])
	assert_eq(nodes[2].loot_items.size(), 0)
	assert_false(nodes[2].loot_found)
	assert_eq(nodes[2].speeds, ["½×", "1×", "2×", "4×"])
	assert_eq(nodes[2].end_modes, ["Stop", "Reverse"])
	assert_true(nodes[2].final)
	assert_eq(nodes[2].max_tapes, 4)
	assert_eq(nodes[2].depth, "03")
	assert_eq(nodes[2].theme_label, "The core")


# ───────────────────────────── loadout ─────────────────────────────

class LoadoutSetup:
	extends RefCounted
	var r: RefCounted
	var logic: MenuLoadoutLogic
	var host: MenuHost
	var left: RefCounted


func _loadout_setup() -> LoadoutSetup:
	var s := LoadoutSetup.new()
	var rec := F.Recorder.new()
	var left := F.Counter.new()
	s.r = rec
	s.left = left
	s.logic = MenuLoadoutLogic.new(rec.emit, left.bump)
	s.logic.set_model(F.loadout_model())
	s.logic.on_show()
	s.host = MenuHost.new(s.logic)
	return s


func test_apparel_03_six_slots_in_order_then_done() -> void:
	var s := _loadout_setup()
	var col0: Array[MenuEntry] = []
	for e in s.host.entries:
		if e.col == 0:
			col0.append(e)
	col0.sort_custom(func(a: MenuEntry, b: MenuEntry) -> bool: return a.row < b.row)
	assert_eq(F.entry_ids(col0), ["slot:helmet", "slot:top", "slot:pants", "slot:shoes", "slot:melee", "slot:ranged", "done"])
	assert_eq(s.host.focus, "slot:helmet")


func test_loadout_browsing_slots_previews_accept_enters_list_on_equipped() -> void:
	var s := _loadout_setup()
	_press(s.host, [DOWN, DOWN])
	assert_eq(s.host.focus, "slot:pants")
	assert_eq(s.logic.active_slot, GearSlot.PANTS)
	s.host.navigate(ACCEPT)
	assert_true(s.logic.in_list)
	assert_eq(s.host.focus, "item:cargo")


func test_gear_03_equip_emits_intent_repick_emits_nothing() -> void:
	var s := _loadout_setup()
	var r: F.Recorder = s.r
	s.host.navigate(ACCEPT)
	assert_eq(s.host.focus, "item:cap")
	s.host.navigate(ACCEPT)
	assert_eq(r.intents.size(), 0)
	s.host.navigate(DOWN)
	assert_eq(s.host.focus, "item:hood")
	s.host.navigate(ACCEPT)
	assert_eq(r.descs(), ["equip:helmet=hood"])
	assert_eq(r.last().slot, GearSlot.HELMET)


func test_loadout_list_keeps_cursor_at_ends_left_and_back_return() -> void:
	var s := _loadout_setup()
	var left: F.Counter = s.left
	_press(s.host, _times(DOWN, 5))
	assert_eq(s.host.focus, "slot:ranged")
	s.host.navigate(RIGHT)
	assert_eq(s.host.focus, "item:missile")
	s.host.navigate(UP)
	assert_eq(s.host.focus, "item:missile")
	_press(s.host, [DOWN, DOWN])
	assert_eq(s.host.focus, "item:rail")
	s.host.navigate(LEFT)
	assert_eq(s.host.focus, "slot:ranged")
	_press(s.host, [RIGHT, BACK])
	assert_eq(s.host.focus, "slot:ranged")
	assert_false(s.logic.in_list)
	assert_eq(left.n, 0)
	s.host.navigate(BACK)
	assert_eq(left.n, 1)


func test_loadout_done_leaves() -> void:
	var s := _loadout_setup()
	var left: F.Counter = s.left
	_press(s.host, _times(DOWN, 6))
	assert_eq(s.host.focus, "done")
	s.host.navigate(ACCEPT)
	assert_eq(left.n, 1)


func test_app_test_02_view_marks_equipped_fresh_and_reflects_change() -> void:
	var before := MenuModels.loadout_view(F.loadout_model(), GearSlot.SHOES)
	var rows := before.items.map(func(i: MenuModels.ItemRow) -> Array: return [i.item.id, i.equipped, i.fresh])
	assert_eq(rows, [["kicks", true, false], ["boots", false, true]])
	var shoes_before: MenuModels.SlotView = before.slots[3]
	assert_eq(shoes_before.slot, GearSlot.SHOES)
	assert_true(shoes_before.has_fresh)
	assert_eq(shoes_before.equipped.effect, "No special effect.")
	var lo := F.base_loadout()
	lo.shoes = "boots"
	var summary: Array[String] = ["Boots: Faster dodge."]
	var after := MenuModels.loadout_view(F.loadout_model([], lo, summary), GearSlot.SHOES)
	var shoes: MenuModels.SlotView = after.slots[3]
	assert_eq(shoes.equipped.effect, "Faster dodge.")
	assert_eq(after.summary, ["Boots: Faster dodge."])
	# Categories stay distinct: each slot tile keeps its own title.
	var titles := {}
	for sv in after.slots:
		titles[sv.title] = true
	assert_eq(titles.size(), 6)
	# The other slots' effects are unchanged by a shoe swap.
	assert_eq((after.slots[2] as MenuModels.SlotView).equipped.id, "cargo")


func test_loadout_open_slot_on_empty_slot_does_not_enter_a_list() -> void:
	var logic := MenuLoadoutLogic.new(func(_i: UiIntent) -> void: pass, func() -> void: pass)
	var inv: Array[GearItem] = []
	for g in F.gear():
		if g.slot != GearSlot.TOP:
			inv.append(g)
	logic.set_model(F.loadout_model(inv))
	logic.open_slot(GearSlot.TOP)
	assert_false(logic.in_list)
	assert_eq(logic.active_slot, GearSlot.TOP)


# ───────────────────────────── settings ─────────────────────────────

class SettingsSetup:
	extends RefCounted
	var r: RefCounted
	var logic: MenuSettingsLogic
	var host: MenuHost
	var left: RefCounted


func _settings_setup() -> SettingsSetup:
	var s := SettingsSetup.new()
	var rec := F.Recorder.new()
	var left := F.Counter.new()
	s.r = rec
	s.left = left
	s.logic = MenuSettingsLogic.new(rec.emit, left.bump)
	var st := SaveSettings.new()
	st.master = 0.5
	st.music = 1.0
	st.av_offset_ms = 0
	s.logic.set_model(st)
	s.host = MenuHost.new(s.logic)
	return s


func _setting_intents(r: F.Recorder) -> Array:
	var out := []
	for i in r.intents:
		out.append([i.type, i.key, i.value])
	return out


func test_settings_volumes_nudge_by_5_percent_and_clamp() -> void:
	var s := _settings_setup()
	_press(s.host, [RIGHT, LEFT, LEFT, DOWN, RIGHT])
	assert_eq(_setting_intents(s.r), [
		["setting", "master", 0.55],
		["setting", "master", 0.5],
		["setting", "master", 0.45],
	])


func test_settings_av_offset_steps_5ms_and_clamps() -> void:
	var s := _settings_setup()
	var r: F.Recorder = s.r
	_press(s.host, _times(DOWN, 3))
	assert_eq(s.host.focus, "avOffsetMs")
	s.host.navigate(LEFT)
	assert_eq([r.last().key, r.last().value], ["avOffsetMs", -5])
	s.logic.set_value("avOffsetMs", 9999)
	assert_eq(s.logic.settings.av_offset_ms, MenuSettingsLogic.AV_OFFSET_MAX)
	assert_eq(MenuSettingsLogic.format_setting("avOffsetMs", -15.0), MenuFormat.MINUS + "15 ms")
	assert_eq(MenuSettingsLogic.format_setting("master", 0.55), "55%")


func test_settings_toggles_flip_on_accept_and_left_right() -> void:
	var s := _settings_setup()
	_press(s.host, _times(DOWN, 4))
	assert_eq(s.host.focus, "screenShake")
	_press(s.host, [ACCEPT, DOWN, RIGHT])
	assert_eq(_setting_intents(s.r), [["setting", "screenShake", false], ["setting", "patterns", true]])


func test_settings_quality_cycles_auto_high_low() -> void:
	var s := _settings_setup()
	_press(s.host, _times(DOWN, 6))
	assert_eq(s.host.focus, "quality")
	_press(s.host, [ACCEPT, RIGHT, RIGHT, LEFT])
	assert_eq(_setting_intents(s.r), [
		["setting", "quality", "high"],
		["setting", "quality", "low"],
		["setting", "quality", "auto"],
		["setting", "quality", "low"],
	])
	assert_eq(s.logic.quality, "low")


func test_settings_erase_save_needs_confirm_defaulting_to_keep() -> void:
	var s := _settings_setup()
	var r: F.Recorder = s.r
	_press(s.host, _times(DOWN, MenuSettingsLogic.setting_rows().size()))
	assert_eq(s.host.focus, "erase")
	s.host.navigate(ACCEPT)
	assert_eq(s.host.focus, "erase-no")
	s.host.navigate(ACCEPT)
	assert_false(s.logic.confirming_erase)
	assert_eq(r.intents.size(), 0)
	_press(s.host, [ACCEPT, RIGHT, ACCEPT])
	assert_eq(r.descs(), ["eraseSave"])
	assert_eq(s.host.focus, "erase")


func test_settings_back_cancels_confirm_first_then_leaves() -> void:
	var s := _settings_setup()
	var left: F.Counter = s.left
	_press(s.host, _times(DOWN, MenuSettingsLogic.setting_rows().size()))
	_press(s.host, [ACCEPT, BACK])
	assert_eq(left.n, 0)
	s.host.navigate(BACK)
	assert_eq(left.n, 1)


func test_settings_echo_replaces_optimistic_values() -> void:
	var s := _settings_setup()
	s.logic.nudge("music", -1)
	assert_near(s.logic.settings.music, 0.95, 1e-9)
	var st := SaveSettings.new()
	st.music = 0.3
	s.logic.set_model(st)
	assert_near(s.logic.settings.music, 0.3, 1e-9)


func test_settings_mouse_value_snaps_and_emits_only_changes() -> void:
	var s := _settings_setup()
	var r: F.Recorder = s.r
	s.logic.set_value("master", 0.512)
	s.logic.set_value("master", 0.49)
	assert_eq(r.intents.size(), 0, "0.512 and 0.49 both snap to the current 0.5")
	s.logic.set_value("music", 1.7)
	assert_eq(r.intents.size(), 0, "music already at the 1.0 ceiling")
	s.logic.set_value("sfx", 0.33)
	assert_eq([r.last().key, r.last().value], ["sfx", 0.35])


# ───────────────────────────── pause ─────────────────────────────

func test_pause_resume_restart_settings_quit_no_loadout() -> void:
	var r := F.Recorder.new()
	var logic := MenuPauseLogic.new(r.emit)
	logic.on_show()
	var host := MenuHost.new(logic)
	assert_eq(F.entry_ids(host.entries), ["resume", "restart", "settings", "quit"])
	_press(host, [ACCEPT, DOWN, ACCEPT, DOWN, DOWN, ACCEPT])
	assert_eq(r.descs(), ["resume", "session:resetAll", "resume", "session:quit"])


func test_pause_settings_open_inside_overlay_and_back_returns() -> void:
	var r := F.Recorder.new()
	var logic := MenuPauseLogic.new(r.emit)
	logic.on_show()
	var host := MenuHost.new(logic)
	_press(host, [DOWN, DOWN, ACCEPT])
	assert_eq(logic.sub, MenuPauseLogic.SUB_SETTINGS)
	assert_eq(host.focus, "master")
	_press(host, [RIGHT, BACK])
	assert_eq(logic.sub, MenuPauseLogic.SUB_MENU)
	assert_eq(host.focus, "settings")
	assert_eq(_setting_intents(r), [["setting", "master", 0.85]])
	host.navigate(BACK)
	assert_eq(r.last().type, UiIntentType.RESUME)


# ───────────────────────────── results ─────────────────────────────

func test_results_next_uses_next_id_else_continues() -> void:
	var r := F.Recorder.new()
	var logic := MenuResultsLogic.new(r.emit)
	logic.set_model(F.results(true, "L4"))
	var host := MenuHost.new(logic)
	assert_eq(F.entry_ids(host.entries), ["next", "replay", "path", "loadout"])
	assert_eq(host.focus, "next")
	_press(host, [ACCEPT, RIGHT, ACCEPT, RIGHT, ACCEPT, RIGHT, ACCEPT])
	assert_eq(r.descs(), ["playLevel:L4", "playLevel:L3", "session:continue", "openLoadout"])
	logic.set_model(F.results())
	host.refresh()
	host.navigate(ACCEPT)
	assert_eq(r.last().describe(), "session:continue")


func test_results_without_next_focus_starts_on_path() -> void:
	var logic := MenuResultsLogic.new(func(_i: UiIntent) -> void: pass)
	logic.set_model(F.results(false))
	var host := MenuHost.new(logic)
	assert_eq(F.entry_ids(host.entries), ["replay", "path", "loadout"])
	assert_eq(host.focus, "path")


func test_results_view_tapes_notes_and_loot_effect_lines() -> void:
	var v := MenuModels.results_view(F.results())
	assert_eq(v.title, "LEVEL CLEARED")
	assert_eq(v.tapes_used, 2)
	assert_eq(v.max_tapes, 3)
	assert_eq(v.depth, "03")
	assert_eq(v.notes, ["Tape A held the plate."])
	assert_eq(v.loot.size(), 1)
	assert_eq([v.loot[0].name, v.loot[0].slot, v.loot[0].effect, v.loot[0].lore],
		["Hood", "HELMET / HEADGEAR", "Enemies think you are farther away.", "quiet"])
	var fail := F.results()
	fail.outcome.win = false
	assert_eq(MenuModels.results_view(fail).title, "ATTEMPT ENDED")


# ───────────────────────────── ending & routing ─────────────────────────────

func test_ending_offers_path_and_title() -> void:
	var r := F.Recorder.new()
	var host := MenuHost.new(MenuEndingLogic.new(r.emit))
	_press(host, [ACCEPT, RIGHT, ACCEPT])
	assert_eq(r.descs(), ["openCampaign", "openTitle"])


func test_loadout_and_settings_return_where_they_were_opened() -> void:
	assert_eq(MenuController.return_intent(UiScreen.TITLE).type, UiIntentType.OPEN_TITLE)
	assert_eq(MenuController.return_intent(&"").type, UiIntentType.OPEN_TITLE)
	assert_eq(MenuController.return_intent(UiScreen.CAMPAIGN).type, UiIntentType.OPEN_CAMPAIGN)
	assert_eq(MenuController.return_intent(UiScreen.RESULTS).type, UiIntentType.OPEN_CAMPAIGN)
