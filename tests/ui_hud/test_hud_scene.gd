extends ODTest
## The HUD scene (res://ui/hud/hud.tscn) end to end: it loads through the facade, renders every
## phase without script errors, reports its bottom inset, keeps the playfield >= 70% while
## recording, and turns clicks on its own controls into HudBase.action (UI-01..07, NEW-07..11).

const SIZE := Vector2(1600, 900)

var hud: HudBase = null
var actions: Array[StringName] = []
var insets: Array[float] = []


func before_each() -> void:
	actions.clear()
	insets.clear()
	hud = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as HudBase
	tree().root.add_child(hud)
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.position = Vector2.ZERO
	hud.size = SIZE
	hud.action.connect(func(a: StringName) -> void: actions.append(a))
	hud.connect("bottom_inset_changed", func(px: float) -> void: insets.append(px))


func after_each() -> void:
	if hud != null:
		hud.queue_free()
		hud = null
	await tree().process_frame


func _level() -> LevelDef:
	var L := LevelDef.new()
	L.name = "Test Level"
	L.bpm = 120.0
	L.bars = 8
	L.horizon_bars = 16
	L.max_tapes = 4
	L.speeds = [0.5, 1.0, 2.0, 4.0]
	L.end_modes = [OD.EndMode.STOP, OD.EndMode.REPEAT, OD.EndMode.REVERSE]
	L.objective.text = "Break the core"
	L.briefing = ["One idea at a time."]
	return L


func _view(phase: StringName, active: int) -> SessionView:
	var v := SessionView.new()
	v.phase = phase
	v.level = _level()
	v.active = active
	v.horizon_beats = 64.0
	v.speeds = [0.5, 1.0, 2.0, 4.0]
	v.end_modes = [OD.EndMode.STOP, OD.EndMode.REPEAT, OD.EndMode.REVERSE]
	v.objective.text = "Break the core"
	for i in 4:
		v.decks[i].status = DeckStatus.EMPTY
	if active >= 0:
		var d := v.decks[active]
		d.status = DeckStatus.ARMED
		d.speed = 2.0
		d.end_mode = OD.EndMode.REPEAT
		d.span_bars = 4.0
	return v


func _frames(n: int = 2) -> void:
	for k in n:
		await tree().process_frame


func _zone_center(p: HudPanel, action: StringName, enabled_only: bool = true) -> Vector2:
	for z: Array in p.zones():
		if z[1] == action and (z[3] or not enabled_only):
			return (z[0] as Rect2).get_center()
	return Vector2(-1, -1)


func test_hud_scene_extends_hudbase_and_is_provided() -> void:
	assert_true(Facades.is_provided(Facades.HUD_SCENE), "hud.tscn exists at the facade path")
	assert_true(hud is HudBase)
	assert_true(hud.has_method("bottom_inset"))
	assert_true(hud.has_signal("bottom_inset_changed"))
	await _frames()


func test_every_phase_renders_without_errors() -> void:
	for ph: StringName in SessionPhase.ALL:
		var v := _view(ph, 1 if ph != SessionPhase.BRIEFING else 0)
		v.count = 6 if ph == SessionPhase.COUNTIN else 0
		if ph == SessionPhase.DECISION:
			v.outcome = Outcome.new()
			v.outcome.notes = ["Tape B died at master beat 9"]
			v.actions = [SessionAction.RETRY_TAKE, SessionAction.COMMIT, SessionAction.RESET_ALL]
		hud.update_hud(v, MusicPulse.new())
		await _frames(2)
		var visible_decks := 0
		for i in 4:
			var d := hud.get_node("Deck%s" % OD.TAPE_NAMES[i]) as Control
			if d.visible:
				visible_decks += 1
		if ph == SessionPhase.RESULTS:
			assert_eq(visible_decks, 0, "results hides the HUD")
			assert_eq(hud.call("bottom_inset"), 0.0)
		else:
			assert_eq(visible_decks, 4, "four decks in %s (NEW-07)" % ph)
			assert_true((hud.get_node("Ruler") as Control).visible, "ruler visible in %s (UI-01, NEW-09)" % ph)
	for d: StringName in [&"Setup", &"Briefing", &"Decision", &"CountIn", &"Banner", &"Objective"]:
		assert_true(hud.has_node(NodePath(d)))


func test_bottom_inset_reported_and_playfield_kept_while_recording() -> void:
	hud.update_hud(_view(SessionPhase.SETUP, 0), MusicPulse.new())
	await _frames()
	var setup_inset: float = hud.call("bottom_inset")
	assert_true(setup_inset > 0.0)
	var v := _view(SessionPhase.RECORDING, 0)
	v.decks[0].status = DeckStatus.RECORDING
	hud.update_hud(v, MusicPulse.new())
	await _frames()
	var rec_inset: float = hud.call("bottom_inset")
	assert_true(rec_inset <= SIZE.y * 0.3, "recording inset %s <= 30%%" % rec_inset)
	assert_true(rec_inset < setup_inset, "decks compact while recording")
	assert_true(insets.size() >= 2, "bottom_inset_changed fired")
	assert_near(insets[insets.size() - 1], rec_inset, 0.5)
	# Every deck sits inside the inset band.
	for i in 4:
		var d := hud.get_node("Deck%s" % OD.TAPE_NAMES[i]) as Control
		assert_true(d.position.y >= SIZE.y - rec_inset - 0.5)


func test_setup_clicks_emit_session_actions() -> void:
	var v := _view(SessionPhase.SETUP, 1)
	v.actions = [SessionAction.SPEED_UP, SessionAction.SPEED_DOWN, SessionAction.CYCLE_END_MODE, SessionAction.RECORD]
	hud.update_hud(v, MusicPulse.new())
	await _frames(3)
	var setup := hud.get_node("Setup") as HudPanel
	assert_true(setup.visible, "setup surface shown on the active deck")
	var rec := _zone_center(setup, SessionAction.RECORD)
	assert_true(rec.x >= 0.0, "record button is clickable")
	setup.click_at(rec)
	assert_eq(actions, [SessionAction.RECORD])
	actions.clear()
	# 2x -> 0.5x is two steps down; 2x -> 4x one step up.
	var downs := 0
	var ups := 0
	for z: Array in setup.zones():
		if not z[3]:
			continue
		if z[1] == SessionAction.SPEED_DOWN:
			downs = maxi(downs, z[2])
		if z[1] == SessionAction.SPEED_UP:
			ups = maxi(ups, z[2])
	assert_eq(downs, 2)
	assert_eq(ups, 1)
	for z: Array in setup.zones():
		if z[1] == SessionAction.SPEED_DOWN and z[2] == 2 and z[3]:
			setup.click_at((z[0] as Rect2).get_center())
	assert_eq(actions, [SessionAction.SPEED_DOWN, SessionAction.SPEED_DOWN])
	# Nothing outside a control takes the mouse.
	assert_false(setup._has_point(Vector2(1, 1)))


func test_disabled_actions_do_not_emit() -> void:
	var v := _view(SessionPhase.DECISION, 1)
	v.decks[1].status = DeckStatus.PENDING
	v.actions = [SessionAction.RETRY_TAKE, SessionAction.RESET_ALL]
	hud.update_hud(v, MusicPulse.new())
	await _frames(3)
	var dec := hud.get_node("Decision") as HudPanel
	assert_true(dec.visible)
	var commit := _zone_center(dec, SessionAction.COMMIT, false)
	assert_true(commit.x >= 0.0, "commit is drawn")
	assert_eq(dec.click_at(commit), &"", "commit not offered: no action")
	var retry := _zone_center(dec, SessionAction.RETRY_TAKE)
	assert_eq(dec.click_at(retry), SessionAction.RETRY_TAKE)
	assert_eq(actions, [SessionAction.RETRY_TAKE])
	hud.set_hold_progress(0.5)
	assert_near(dec.hold_progress, 0.5, 1e-6)


func test_device_and_bindings_reach_prompts() -> void:
	hud.update_hud(_view(SessionPhase.SETUP, 0), MusicPulse.new())
	await _frames()
	var setup := hud.get_node("Setup") as HudPanel
	assert_eq(setup.prompt(SessionAction.RECORD).binding.key, "Space")
	hud.set_device(HudBase.DEVICE_GAMEPAD)
	assert_eq(setup.prompt(SessionAction.RECORD).binding.key, "A")
	var b: Dictionary[StringName, ButtonPrompt] = {SessionAction.RECORD: ButtonPrompt.make("RT", ButtonPrompt.STYLE_SHOULDER)}
	hud.set_bindings(b)
	assert_eq(setup.prompt(SessionAction.RECORD).binding.key, "RT")
	await _frames()


func test_deck_reels_follow_reel_rate_and_transport() -> void:
	var v := _view(SessionPhase.REVIEW, -1)
	for i in 4:
		var d := v.decks[i]
		d.status = DeckStatus.COMMITTED
		d.speed = 1.0
		d.end_mode = OD.EndMode.REPEAT
		d.span_bars = 8.0
	v.decks[0].transport = 1
	v.decks[0].reel_rate = 1.0
	v.decks[1].transport = 1
	v.decks[1].reel_rate = 2.0
	v.decks[2].transport = -1
	v.decks[2].reel_rate = 1.0
	v.decks[3].transport = 0
	v.decks[3].reel_rate = 0.0
	hud.update_hud(v, MusicPulse.new())
	await _frames()
	var decks: Array[HudDeck] = []
	for i in 4:
		decks.append(hud.get_node("Deck%s" % OD.TAPE_NAMES[i]) as HudDeck)
	var before: Array[float] = []
	for d: HudDeck in decks:
		before.append(d.reel_angle())
	for d: HudDeck in decks:
		d.advance(0.05)
	var delta: Array[float] = []
	for i in 4:
		delta.append(wrapf(decks[i].reel_angle() - before[i], -PI, PI))
	assert_true(delta[0] > 0.0, "1x spins forward")
	assert_near(delta[1], 2.0 * delta[0], 1e-4, "2x spins twice as fast (NEW-10)")
	assert_near(delta[2], -delta[0], 1e-4, "reverse spins backward")
	assert_eq(delta[3], 0.0, "stopped is still")
	hud.deck_event(2, StateMarkKind.DEATH)
	hud.deck_event(9, ActionKind.LIGHT) # out of range: ignored
	await _frames()


func test_update_before_ready_is_applied() -> void:
	var h2 := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as HudBase
	h2.update_hud(_view(SessionPhase.SETUP, 2), MusicPulse.new())
	tree().root.add_child(h2)
	h2.set_anchors_preset(Control.PRESET_TOP_LEFT)
	h2.size = SIZE
	await _frames()
	assert_true((h2.get_node("Setup") as Control).visible)
	assert_true(float(h2.call("bottom_inset")) > 0.0)
	h2.queue_free()


func test_reset_all_confirm_text_follows_the_hold_mode() -> void:
	var v := _view(SessionPhase.DECISION, 1)
	v.decks[1].status = DeckStatus.PENDING
	v.actions = [SessionAction.RETRY_TAKE, SessionAction.RESET_ALL]
	hud.update_hud(v, MusicPulse.new())
	await _frames(3)
	var dec := hud.get_node("Decision") as HudDecision
	var reset: HudModel.DecisionOption = HudModel.decision_options(v.actions, 1)[2]
	assert_eq(dec.confirm_text(), "HOLD TO CONFIRM")
	hud.set_hold_progress(0.5)
	assert_eq(dec.confirm_text(), "KEEP HOLDING…")
	hud.set_hold_progress(0.0)
	# Press-twice mode (accessibility): arm on the first press, act on the second.
	hud.call("set_hold_mode", true)
	assert_true(dec.press_twice)
	assert_eq(dec.confirm_text(), "PRESS TWICE TO CONFIRM")
	assert_true(dec._detail(reset).begins_with("PRESS TWICE TO CONFIRM — "))
	hud.set_hold_progress(1.0)
	assert_eq(dec.confirm_text(), "PRESS AGAIN TO CONFIRM", "armed by the first press")
	assert_true(dec._detail(reset).begins_with("PRESS AGAIN TO CONFIRM — "), "shown on the reset option")
	await _frames(2)
	# Setup has no reset button: the banner pill carries the confirm text while armed.
	var s := _view(SessionPhase.SETUP, 1)
	s.actions = [SessionAction.RECORD, SessionAction.RESET_ALL]
	hud.update_hud(s, MusicPulse.new())
	await _frames(2)
	var banner := hud.get_node("Banner") as HudBanner
	assert_eq(banner.reset_confirm_text(), "PRESS AGAIN TO CONFIRM")
	hud.set_hold_progress(0.0)
	assert_eq(banner.reset_confirm_text(), "", "nothing pending: the usual setup pill")
	s.actions = [SessionAction.RECORD]
	hud.update_hud(s, MusicPulse.new())
	hud.set_hold_progress(1.0)
	assert_eq(banner.reset_confirm_text(), "", "reset not offered: no confirm text")
	await _frames(2)


func test_reading_text_follows_the_text_size_option() -> void:
	var v := _view(SessionPhase.DECISION, 1)
	v.decks[1].status = DeckStatus.PENDING
	v.outcome = Outcome.new()
	v.outcome.notes = ["Tape B died at master beat 9: struck by grunt g1.", "Objective not complete: Break the core."]
	v.actions = [SessionAction.RETRY_TAKE, SessionAction.RESET_ALL]
	hud.update_hud(v, MusicPulse.new())
	await _frames(3)
	var dec := hud.get_node("Decision") as HudPanel
	var base_h := dec.size.y
	var base_fs := dec.ts(10.0)
	hud.call("set_text_scale", 1.5)
	await _frames(2)
	assert_eq(dec.ts(10.0), 15)
	assert_true(dec.size.y > base_h + 1.0, "the decision card grows with its text (%s -> %s)" % [base_h, dec.size.y])
	hud.call("set_text_scale", 1.0)
	await _frames(2)
	assert_eq(dec.ts(10.0), base_fs)
	assert_near(dec.size.y, base_h, 0.5)
