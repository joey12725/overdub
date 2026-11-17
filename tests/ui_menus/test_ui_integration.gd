extends ODTest
## The interface integration on res://ui/ui_root.tscn: the Field Guide from the campaign screen and
## the pause menu, "watch again" replays, the loot moment's equip intents, the accessibility / story
## settings rows, the dialogue layer and world-widget mounts, the HUD's resolving beat, coach-mark
## anchors and the generated art lookups.

const F := preload("res://tests/ui_menus/menu_fixtures.gd")

var ui: UiBase
var rec: F.Recorder


func before_each() -> void:
	ui = Facades.instance_ui()
	rec = F.Recorder.new()
	ui.intent.connect(rec.emit)
	tree().root.add_child(ui)
	var guard := 0
	while not ui.is_node_ready() and guard < 10:
		await tree().process_frame
		guard += 1
	ui.set_settings(SaveSettings.new())
	ui.set_campaign(F.campaign(2))
	ui.set_loadout(F.loadout_model())


func after_each() -> void:
	if is_instance_valid(ui):
		ui.dispose()
		ui.queue_free()
	await tree().process_frame


func _menus() -> MenuController:
	return ui.get("menus") as MenuController


func _codex() -> Codex:
	var c := Codex.new()
	c.load_unlocked(["grunt", "stalker"])
	return c


func _labels(n: Node, out: Array[String]) -> Array[String]:
	for c in n.get_children():
		if c is Label and (c as Label).is_visible_in_tree():
			out.append((c as Label).text)
		_labels(c, out)
	return out


func test_layers_mount_in_order_hud_dialogue_menus() -> void:
	assert_true(ui.get_child(0) == ui.hud, "HUD at the bottom")
	var dl: Variant = ui.get("dialogue")
	assert_true(dl is DialogueLayer, "dialogue layer mounted")
	assert_eq((dl as Node).get_index(), 1, "dialogue just above the HUD")
	assert_true((dl as Node).get_index() < _menus().get_index(), "dialogue below the menus")
	var overlay: Variant = ui.hud.get("world_overlay")
	assert_true(overlay is WidgetWorldOverlay, "world widgets mounted in the HUD")
	assert_eq((overlay as Node).get_index(), 0, "world widgets under the dock")


func test_field_guide_from_campaign_and_back() -> void:
	ui.call("set_codex", _codex())
	ui.show_screen(UiScreen.CAMPAIGN)
	var m := _menus()
	assert_true(m.definition().has("guide"), "campaign offers the Field Guide")
	ui.navigate(UiBase.NAV_UP)
	ui.navigate(UiBase.NAV_UP)
	ui.navigate(UiBase.NAV_UP)
	assert_eq(m.focus, "back")
	ui.navigate(UiBase.NAV_RIGHT)
	ui.navigate(UiBase.NAV_RIGHT)
	assert_eq(m.focus, "guide")
	ui.navigate(UiBase.NAV_ACCEPT)
	assert_true(m.codex_open(), "guide open")
	assert_eq(m.focus, "entry:grunt", "opens on the first page met")
	var texts := _labels(m.current_node, [])
	assert_has(texts, "???", "pages not met yet are blank")
	assert_has(texts, "GRUNT")
	ui.navigate(UiBase.NAV_BACK)
	assert_false(m.codex_open())
	assert_eq(ui.screen, UiScreen.CAMPAIGN, "the game's screen never changed")
	assert_eq(m.focus, "guide", "back lands on the guide button")
	assert_eq(rec.intents.size(), 0, "browsing the guide emits nothing")


func test_field_guide_from_pause_opens_on_a_page() -> void:
	ui.call("set_codex", _codex())
	ui.show_screen(UiScreen.PLAY)
	ui.show_screen(UiScreen.PAUSE)
	var m := _menus()
	assert_eq(F.entry_ids(m.definition().entries), ["resume", "restart", "settings", "guide", "quit"])
	ui.call("open_codex", "stalker")
	assert_eq(m.focus, "entry:stalker")
	assert_true(ui.hud.visible, "the HUD stays mounted under the guide")
	ui.navigate(UiBase.NAV_BACK)
	assert_eq(m.screen, UiScreen.PAUSE)
	assert_eq(m.focus, "guide")


func test_watch_again_emits_a_replay_intent_for_kept_takes_only() -> void:
	ui.call("set_replays", {"L1": {"ok": true}, "L2": {"ok": false, "note": "gear changed"}})
	ui.show_screen(UiScreen.CAMPAIGN)
	var m := _menus()
	assert_true(m.definition().has("watch:L1"))
	assert_false(m.definition().has("watch:L2"), "an out-of-date replay is not offered")
	ui.navigate(UiBase.NAV_UP)
	ui.navigate(UiBase.NAV_UP)
	assert_eq(m.focus, "level:L1")
	ui.navigate(UiBase.NAV_RIGHT)
	assert_eq(m.focus, "watch:L1")
	ui.navigate(UiBase.NAV_ACCEPT)
	assert_eq(rec.intents.size(), 1)
	assert_eq(rec.last().type, MenuCampaignLogic.INTENT_WATCH_REPLAY)
	assert_eq(rec.last().id, "L1")


func test_loot_moment_equip_now_emits_equip_then_loadout() -> void:
	var r := F.results(true, "L4")
	ui.set_results(r)
	ui.show_screen(UiScreen.RESULTS)
	assert_true(_menus().get("loot_reveal") is WidgetLootReveal)
	ui.navigate(UiBase.NAV_ACCEPT)
	ui.navigate(UiBase.NAV_ACCEPT)
	var it: GearItem = r.loot[0]
	assert_eq(rec.descs(), ["equip:%s=%s" % [it.slot, it.id], "openLoadout"])


func test_accessibility_and_story_rows_emit_settings() -> void:
	ui.show_screen(UiScreen.SETTINGS)
	var m := _menus()
	for key: String in ["highContrast", "reduceFlashing", "shakeScale", "textScale", "voices", "barks", "coachMarks", "patterns", "cassettePalette"]:
		assert_true(m.definition().has(key), "settings row %s" % key)
	var logic := m.settings_logic
	logic.set_value("reduceFlashing", true)
	logic.set_value("barks", false)
	logic.nudge("shakeScale", 1)
	logic.nudge("textScale", 1)
	assert_eq(rec.descs(), ["setting:reduceFlashing=true", "setting:barks=false", "setting:shakeScale=0.4", "setting:textScale=1.15"])
	assert_eq(logic.value_of("barks"), false)
	# The UI applies what it owns at once: the HUD holds its lamps still, barks stop.
	assert_true(bool(ui.hud.get("reduce_flashing")))
	var dl: DialogueLayer = ui.get("dialogue")
	assert_false(dl.barks_enabled)
	assert_near(UiPalette.text_scale, 1.15, 1e-6)
	logic.set_value("textScale", 1.0)
	assert_near(UiPalette.text_scale, 1.0, 1e-6)


func test_hold_mode_and_voice_volume_rows_reach_the_hud_and_the_game() -> void:
	ui.show_screen(UiScreen.SETTINGS)
	var m := _menus()
	assert_true(m.definition().has("holdMode"), "settings row holdMode")
	assert_true(m.definition().has("voiceVolume"), "settings row voiceVolume")
	var logic := m.settings_logic
	assert_false(bool(ui.hud.get("press_twice")))
	logic.set_value("holdMode", "press")
	assert_true(bool(ui.hud.get("press_twice")), "the HUD shows the press-twice confirm text")
	assert_near(float(logic.value_of("voiceVolume")), 1.0, 1e-6)
	logic.nudge("voiceVolume", -1)
	assert_eq(rec.descs(), ["setting:holdMode=press", "setting:voiceVolume=0.95"])
	assert_eq(MenuSettingsLogic.format_setting("voiceVolume", 0.95), "95%")
	# The game's echo is authoritative (a saved "press" reaches the HUD on boot).
	var st := SaveSettings.new()
	ui.set_settings(st)
	assert_false(bool(ui.hud.get("press_twice")))
	st.hold_mode = "press"
	st.voice_volume = 0.4
	ui.set_settings(st)
	assert_true(bool(ui.hud.get("press_twice")))
	assert_near(float(logic.value_of("voiceVolume")), 0.4, 1e-6)
	ui.set_settings(SaveSettings.new())


func test_pause_field_guide_opens_on_the_page_hinted_after_a_failed_run() -> void:
	ui.call("set_codex", _codex())
	ui.call("set_codex_hint", "stalker")
	ui.show_screen(UiScreen.PLAY)
	ui.show_screen(UiScreen.PAUSE)
	var m := _menus()
	m.pause_logic._open_codex.call()
	assert_true(m.codex_open())
	assert_eq(m.focus, "entry:stalker", "the page for what stopped the run")
	ui.navigate(UiBase.NAV_BACK)
	# No hint: the guide opens where it was last read; the campaign button never uses the hint.
	ui.call("set_codex_hint", "")
	m.codex_logic.selected = "grunt"
	m.pause_logic._open_codex.call()
	assert_eq(m.focus, "entry:grunt")
	ui.navigate(UiBase.NAV_BACK)


func test_hud_resolving_beat_replaces_the_review_banner() -> void:
	ui.show_screen(UiScreen.PLAY)
	var v := GameSessionView.new()
	v.phase = SessionPhase.REVIEW
	v.level = F.level(1)
	v.resolving = true
	v.resolve_progress = 0.5
	v.status_text = GameSessionView.RESOLVING_TEXT
	v.actions = [SessionAction.SKIP]
	ui.update_hud(v, MusicPulse.new())
	await tree().process_frame
	var banner := ui.hud.get("banner") as HudBanner
	assert_true(banner.is_resolving())
	assert_true(banner.visible)
	assert_eq(banner.zones().size(), 0, "no SKIP chip while the take is still being lined up")


func test_controls_strip_anchors_gameplay_prompts_while_recording() -> void:
	ui.show_screen(UiScreen.PLAY)
	var v := SessionView.new()
	v.phase = SessionPhase.RECORDING
	v.level = F.level(1)
	v.active = 0
	v.horizon_beats = 32.0
	v.decks[0].status = DeckStatus.RECORDING
	v.decks[0].speed = 1.0
	ui.update_hud(v, MusicPulse.new())
	await tree().process_frame
	await tree().process_frame
	var r: Rect2 = ui.hud.call("anchor_rect", "prompt:light", {})
	assert_true(r.has_area(), "light prompt anchor on screen")
	var lane: Rect2 = ui.hud.call("anchor_rect", "ruler.lane:0", {})
	assert_true(lane.has_area(), "ruler lane anchor")
	assert_true(lane.position.y > r.position.y, "the strip sits above the dock")


func test_generated_art_is_found() -> void:
	assert_true(UiArt.key_art() != null, "title key art")
	assert_true(UiArt.logo() != null, "wordmark")
	assert_true(UiArt.ending_card() != null, "ending card")
	for t: StringName in [LevelTheme.UPPER, LevelTheme.MID, LevelTheme.LOWER, LevelTheme.CORE]:
		assert_true(UiArt.chapter_card(t) != null, "chapter card %s" % t)
	for slot: StringName in GearSlot.ALL:
		assert_true(UiArt.slot_icon(slot) != null, "slot glyph %s" % slot)
	assert_true(UiArt.gear_icon("splice_blade") != null)
	assert_true(UiArt.action_icon(ActionKind.HEAVY) != null)
	assert_true(UiArt.tape_icon("desync") != null)
	assert_true(UiArt.nine("toast", 0.5) != null)
	assert_true(UiArt.pattern_mask(2) != null, "cassette pattern mask")
	assert_true(UiArt.gear_icon("no_such_item") == null)
