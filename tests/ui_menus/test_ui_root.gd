extends ODTest
## res://ui/ui_root.tscn as the game uses it: built through Facades, models pushed with set_*, screens
## shown with show_screen, driven with navigate() and the pointer path. Checks that every screen
## builds, focus is visible on exactly the focused entry, the HUD mounts on play / pause, intents
## leave through the `intent` signal, and the six slots and weapon numbers are on screen (APPAREL-03,
## WEAPON-04).

const F := preload("res://tests/ui_menus/menu_fixtures.gd")

var ui: UiBase
var rec: F.Recorder


func before_each() -> void:
	ui = Facades.instance_ui()
	rec = F.Recorder.new()
	ui.intent.connect(rec.emit)
	tree().root.add_child(ui)
	# When this suite runs first, the runner is still inside SceneTree._initialize and the root is not
	# ready yet, so _ready (which mounts the HUD) only runs once the tree starts processing.
	var guard := 0
	while not ui.is_node_ready() and guard < 10:
		await tree().process_frame
		guard += 1


func after_each() -> void:
	if is_instance_valid(ui):
		ui.dispose()
		ui.queue_free()
	await tree().process_frame


func _menus() -> MenuController:
	return ui.get("menus") as MenuController


func _labels(n: Node, out: Array[String]) -> Array[String]:
	for c in n.get_children():
		if c is Label and (c as Label).is_visible_in_tree():
			out.append((c as Label).text)
		_labels(c, out)
	return out


func _focused_ids() -> Array[String]:
	var out: Array[String] = []
	var m := _menus()
	if m.current_node == null:
		return out
	for item in m.nav_items_of(m.current_node):
		if item.focused and not out.has(item.nav_id):
			out.append(item.nav_id)
	return out


func _push_models() -> void:
	ui.set_settings(SaveSettings.new())
	ui.set_campaign(F.campaign(2))
	ui.set_loadout(F.loadout_model())
	ui.set_results(F.results(true, "L4"))


func test_ui_root_is_provided_and_extends_ui_base() -> void:
	assert_true(Facades.is_provided(Facades.UI_ROOT_SCENE))
	assert_true(ui is UiBase)
	assert_true(ui.get_script().resource_path == "res://ui/ui_root.gd")
	assert_true(ui.hud != null, "attach_hud() ran in _ready")
	# Identity check through assert_true: a failing assert_eq on Nodes would var_to_str a whole tree.
	var first := ui.get_child(0) if ui.get_child_count() > 0 else null
	assert_true(first == ui.hud, "the HUD sits below menus and toasts (child 0 is %s)" % (first.name if first != null else "none"))


func test_every_screen_builds_and_shows_visible_focus() -> void:
	_push_models()
	for s: StringName in [UiScreen.TITLE, UiScreen.CAMPAIGN, UiScreen.LOADOUT, UiScreen.SETTINGS, UiScreen.PAUSE, UiScreen.RESULTS, UiScreen.ENDING]:
		ui.show_screen(s)
		await tree().process_frame
		var m := _menus()
		assert_true(m.visible, "%s: menu layer visible" % s)
		assert_true(m.current_node != null, "%s: built" % s)
		assert_false(m.focus.is_empty(), "%s: something is focused" % s)
		assert_eq(_focused_ids(), [m.focus], "%s: exactly the focused entry shows the focus look" % s)
		# Every menu entry has something on screen to click.
		for e in m.definition().entries:
			assert_false(m.nav_items(e.id).is_empty(), "%s: entry %s has a control" % [s, e.id])


func test_hud_shows_on_play_and_pause_only_and_navigate_is_ignored_on_play() -> void:
	_push_models()
	ui.show_screen(UiScreen.TITLE)
	assert_false(ui.hud.visible)
	ui.show_screen(UiScreen.PLAY)
	assert_true(ui.hud.visible)
	assert_false(_menus().visible)
	ui.navigate(UiBase.NAV_ACCEPT)
	ui.navigate(UiBase.NAV_BACK)
	assert_eq(rec.intents.size(), 0, "no menu reacts on play")
	ui.show_screen(UiScreen.PAUSE)
	assert_true(ui.hud.visible, "the decks stay readable under the pause overlay")
	ui.show_screen(UiScreen.RESULTS)
	assert_false(ui.hud.visible)


func test_title_keyboard_and_pointer_emit_the_same_intents() -> void:
	_push_models()
	ui.show_screen(UiScreen.TITLE)
	assert_eq(_menus().focus, "continue")
	ui.navigate(UiBase.NAV_ACCEPT)
	assert_eq(rec.descs(), ["openCampaign"])
	# Pointer: hover then click on the Loadout button, through the nav item's own signals.
	var items := _menus().nav_items("loadout")
	assert_eq(items.size(), 1)
	var b: MenuNavItem = items[0]
	b.hovered.emit("loadout")
	assert_eq(_menus().focus, "loadout")
	b.clicked.emit("loadout")
	assert_eq(rec.descs(), ["openCampaign", "openLoadout"])


func test_pause_restart_and_quit_and_mid_take_note() -> void:
	_push_models()
	var view := SessionView.new()
	view.level = F.level(1)
	view.phase = SessionPhase.RECORDING
	ui.show_screen(UiScreen.PLAY)
	ui.update_hud(view, MusicPulse.new())
	ui.show_screen(UiScreen.PAUSE)
	var texts := _labels(_menus().current_node, [])
	assert_has(texts, "No tactical pause: the take in progress goes back to setup.")
	assert_has(texts, "Level 2")
	assert_has(texts, "Loadout is locked for this attempt — change gear between levels.")
	ui.navigate(UiBase.NAV_DOWN)
	ui.navigate(UiBase.NAV_ACCEPT)
	assert_eq(rec.descs(), ["session:resetAll", "resume"])


func test_apparel_03_loadout_screen_shows_all_six_slots_and_effects() -> void:
	_push_models()
	ui.show_screen(UiScreen.LOADOUT)
	var texts := _labels(_menus().current_node, [])
	for slot in GearSlot.ALL:
		assert_has(texts, MenuFormat.slot_label(slot).title, "slot %s is labelled" % slot)
	# Equipped names and their effects are on the tiles; the six pins mark the doll.
	for id in ["Cap", "Crop", "Cargo", "Kicks", "Blade", "Missile"]:
		assert_has(texts, id)
	for short in ["HEAD", "TOP", "LEGS", "FEET", "MEL", "RNG"]:
		assert_has(texts, short)
	assert_has(texts, "No special effect.")
	assert_eq(_menus().nav_items("slot:melee").size(), 2, "slot tile + doll pin")


func test_weapon_04_details_show_real_numbers_and_comparison() -> void:
	_push_models()
	ui.show_screen(UiScreen.LOADOUT)
	for k in 4:
		ui.navigate(UiBase.NAV_DOWN)
	assert_eq(_menus().focus, "slot:melee")
	ui.navigate(UiBase.NAV_ACCEPT)
	assert_eq(_menus().focus, "item:blade")
	ui.navigate(UiBase.NAV_DOWN)
	assert_eq(_menus().focus, "item:maul")
	var texts := _labels(_menus().current_node, [])
	assert_has(texts, "0.2 s windup · 0.08 s hit · 0.27 s recover (0.55 s total at 1×)")
	assert_has(texts, "1.6× (very high)")
	assert_has(texts, "COMPARED WITH BLADE")
	assert_has(texts, "1.5 tiles  ▲")
	ui.navigate(UiBase.NAV_ACCEPT)
	assert_eq(rec.descs(), ["equip:melee=maul"])


func test_weapon_details_show_the_delivered_model_and_apparel_does_not() -> void:
	var errors: Array[String] = []
	var cat := ContentData.load_gear(errors)
	assert_true(cat != null, "gear catalogue loads: %s" % [errors])
	if cat == null:
		return
	var m := LoadoutScreenModel.new()
	m.inventory = cat.items.duplicate()
	m.loadout = cat.base_loadout.copy()
	ui.set_settings(SaveSettings.new())
	ui.set_loadout(m)
	ui.show_screen(UiScreen.LOADOUT)
	# Walk to the melee slot from the top (the screen reopens on the slot browsed last).
	for k in GearSlot.ALL.size():
		ui.navigate(UiBase.NAV_UP)
	assert_eq(_menus().focus, "slot:helmet")
	var details := _menus().current_node.find_child("DetailsSlot", true, false)
	assert_true(details.find_child("WeaponStage", true, false) == null, "apparel details have no weapon stage")
	for k in 4:
		ui.navigate(UiBase.NAV_DOWN)
	assert_eq(_menus().focus, "slot:melee")
	var melee_id := m.loadout.melee
	var has_model := ResourceLoader.exists(MenuModelStage.weapon_paths(melee_id)[0])
	details = _menus().current_node.find_child("DetailsSlot", true, false)
	var stage := details.find_child("WeaponStage", true, false)
	assert_eq(stage != null, has_model, "weapon stage present exactly when %s.glb exists" % melee_id)

	_push_models()
	ui.show_screen(UiScreen.LOADOUT)
	var lo := F.base_loadout()
	lo.shoes = "boots"
	ui.set_loadout(F.loadout_model([], lo))
	await tree().process_frame
	var texts := _labels(_menus().current_node, [])
	assert_has(texts, "Boots")
	assert_has(texts, "Faster dodge.")


func test_settings_slider_and_quality_chip_emit_setting_intents() -> void:
	_push_models()
	ui.show_screen(UiScreen.SETTINGS)
	var m := _menus()
	m.setting_set("music", 0.42)
	m.setting_set("quality", "low")
	assert_eq(rec.descs().size(), 2)
	assert_eq([rec.intents[0].key, rec.intents[0].value], ["music", 0.4])
	assert_eq([rec.intents[1].key, rec.intents[1].value], ["quality", "low"])
	assert_eq(m.focus, "quality")
	var texts := _labels(m.current_node, [])
	assert_has(texts, "40%")


func test_results_actions_and_loot_lines() -> void:
	_push_models()
	ui.show_screen(UiScreen.RESULTS)
	var texts := _labels(_menus().current_node, [])
	assert_has(texts, "LEVEL CLEARED")
	assert_has(texts, "Enemies think you are farther away.")
	assert_has(texts, "▸ Tape A held the plate.")
	# Fresh loot opens the chest moment over the results first: accept skips it, back is "later".
	var reveal: Variant = _menus().get("loot_reveal")
	assert_true(reveal is WidgetLootReveal, "the loot reveal is up over the results")
	ui.navigate(UiBase.NAV_ACCEPT)
	ui.navigate(UiBase.NAV_BACK)
	assert_eq(rec.intents.size(), 0, "LATER emits nothing")
	assert_true(_menus().get("loot_reveal") == null, "the reveal closed")
	ui.navigate(UiBase.NAV_ACCEPT)
	assert_eq(rec.descs(), ["playLevel:L4"])


func test_campaign_locked_level_refuses_and_cleared_level_replays() -> void:
	_push_models()
	ui.show_screen(UiScreen.CAMPAIGN)
	assert_eq(_menus().focus, "level:L3")
	var texts := _labels(_menus().current_node, [])
	assert_has(texts, "LOCKED")
	assert_has(texts, "CLEARED · REPLAY")
	assert_has(texts, "NEXT")
	ui.navigate(UiBase.NAV_DOWN)
	ui.navigate(UiBase.NAV_ACCEPT)
	assert_eq(rec.intents.size(), 0)
	ui.navigate(UiBase.NAV_UP)
	ui.navigate(UiBase.NAV_UP)
	ui.navigate(UiBase.NAV_ACCEPT)
	assert_eq(rec.descs(), ["playLevel:L2"])


func test_loadout_back_returns_where_it_was_opened() -> void:
	_push_models()
	ui.show_screen(UiScreen.TITLE)
	ui.show_screen(UiScreen.LOADOUT)
	ui.navigate(UiBase.NAV_BACK)
	ui.show_screen(UiScreen.CAMPAIGN)
	ui.show_screen(UiScreen.SETTINGS)
	ui.navigate(UiBase.NAV_BACK)
	assert_eq(rec.descs(), ["openTitle", "openCampaign"])


func test_toasts_stack_to_four() -> void:
	for i in 6:
		ui.toast("toast %d" % i, UiBase.TONE_GOOD if i % 2 == 0 else UiBase.TONE_INFO)
	var toasts := ui.get("toasts") as MenuToasts
	assert_eq(toasts.texts(), ["toast 2", "toast 3", "toast 4", "toast 5"])


func test_device_switch_changes_prompts() -> void:
	_push_models()
	ui.show_screen(UiScreen.TITLE)
	assert_has(_labels(_menus().current_node, []), "Esc")
	ui.set_device(UiBase.DEVICE_GAMEPAD)
	var texts := _labels(_menus().current_node, [])
	assert_has(texts, "D-pad")
	assert_has(texts, "B")
