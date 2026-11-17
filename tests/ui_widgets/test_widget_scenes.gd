extends ODTest
## Every widget scene loads, takes fake snapshot data without script errors, and the loot reveal's
## prompt emits its signal (GEAR-02, APPAREL-02). Drawing itself is checked by tools/shot_widgets.gd.

const F := preload("res://tests/ui_widgets/widget_fixtures.gd")
const SIZE := Vector2(1600, 900)

var nodes: Array[Node] = []


func after_each() -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()
	await tree().process_frame


func _mount(path: String) -> Control:
	var c := (load(path) as PackedScene).instantiate() as Control
	tree().root.add_child(c)
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = Vector2.ZERO
	c.size = SIZE
	nodes.append(c)
	return c


func _snap() -> FrameSnapshot:
	var s := FrameSnapshot.new()
	s.beat = 10.5
	var live := F.actor(0, 4.6, 4.5, 0.0, true)
	live.vx = 9.0
	s.actors.append(live)
	var ghost := F.actor(1, 40.0, 4.0, 0.0)
	ghost.life = OD.LifeState.GHOST
	s.actors.append(ghost)
	var des := F.actor(2, -20.0, 30.0, 0.0)
	des.synced = false
	des.has_spark = true
	des.spark = Vector2(-18.0, 28.0)
	s.actors.append(des)
	s.enemies.append(F.enemy("brute", EnemyType.BRUTE, 8.0, 7.0, 2, 3))
	var sh := F.enemy("shielder", EnemyType.SHIELDER, 3.0, 2.0, 2, 2)
	sh.has_shield = true
	sh.shield = true
	s.enemies.append(sh)
	var tur := F.enemy("turret", EnemyType.TURRET, 60.0, -30.0, 1, 1)
	tur.state = EnemyStateName.TELEGRAPH
	tur.state_t = 0.6
	s.enemies.append(tur)
	s.enemies.append(F.boss(31, 2, 1))
	return s


func test_every_scene_loads_with_the_right_class() -> void:
	var expect := {
		"res://ui/widgets/boss_bar.tscn": "WidgetBossBar",
		"res://ui/widgets/momentum_gauge.tscn": "WidgetMomentumGauge",
		"res://ui/widgets/threshold_badges.tscn": "WidgetThresholdBadges",
		"res://ui/widgets/offscreen_indicators.tscn": "WidgetOffscreenIndicators",
		"res://ui/widgets/threat_ticks.tscn": "WidgetThreatTicks",
		"res://ui/widgets/loot_reveal.tscn": "WidgetLootReveal",
		"res://ui/widgets/world_overlay.tscn": "WidgetWorldOverlay",
	}
	for path: String in expect:
		var c := _mount(path)
		assert_true(c != null, path)
		assert_eq((c.get_script() as Script).get_global_name(), expect[path], path)
		assert_eq(c.mouse_filter, Control.MOUSE_FILTER_STOP if path.contains("loot") else Control.MOUSE_FILTER_IGNORE, path)
	await tree().process_frame


func test_world_overlay_runs_a_frame_of_everything() -> void:
	var o := _mount("res://ui/widgets/world_overlay.tscn") as WidgetWorldOverlay
	await tree().process_frame
	o.load_level(F.level(), F.loadout(), F.memory([0, 1] as Array[int]))
	o.set_projector(F.flat_projector())
	o.set_bottom_inset(180.0)
	var events: Array[SimEvent] = [
		SimEvent.make(0, SimEventType.CLANG, 6.5, 4.5).with_tape(0).with_power(3.0).with_detail("needs 5"),
		SimEvent.make(0, SimEventType.SWING, 40, 4).with_tape(1),
		SimEvent.make(0, SimEventType.BOSS_RECALL, 3, 6).with_id("archivist").with_tape(1).with_power(12.0).with_detail("attack"),
	]
	o.update_frame(_snap(), F.view(SessionPhase.RECORDING, 0, 2.0), events)
	for k in 3:
		await tree().process_frame
	assert_true(o.gauge.state.visible, "gauge shows while recording")
	assert_eq(o.gauge.state.target.id, "wall")
	assert_true(o.gauge.state.heavy_meets, "2x running heavy breaks the wall")
	assert_true(o.boss_bar.model.recalling)
	assert_eq(o.boss_bar.model.recall_tape, 1)
	assert_true(o.boss_bar.top_inset() > 0.0)
	assert_true(o.offscreen.clusters.size() >= 2, "ghost to the right, desynced self + spark and turret elsewhere")
	# Cinematic hides the in-world helpers, keeps the boss bar.
	o.update_frame(_snap(), F.view(SessionPhase.CINEMATIC, -1), [] as Array[SimEvent])
	assert_false(o.badges.visible)
	assert_false(o.gauge.state.visible)
	assert_true(o.boss_bar.model.present)


func test_badges_report_reach_and_needed_speed() -> void:
	var view := F.view(SessionPhase.RECORDING, 0, 1.0)
	var snap := _snap()
	var list := WidgetThresholdBadges.build_badges(F.level(), F.loadout(), snap, view, F.flat_projector(Vector2(0, 0), 40.0), SIZE)
	var by_id := {}
	for b: Dictionary in list:
		by_id[b["id"]] = b
	assert_true(by_id.has("wall") and by_id.has("core") and by_id.has("weak"))
	assert_eq(by_id["wall"]["slots"], 5)
	assert_false(by_id["wall"]["met"], "1x run-in heavy 3 < 5")
	assert_eq(by_id["wall"]["min_speed"], 2.0)
	assert_true(by_id["weak"]["met"], "3 >= 1.5")
	assert_true(by_id["core"]["met"])
	assert_true(by_id.has("brute"), "multi-hit enemy gets pips")
	assert_true(by_id["shielder"]["shield"])
	assert_false(by_id.has("archivist"), "boss uses the bar, not pips")
	# No live self (review): requirement only.
	var review := WidgetThresholdBadges.build_badges(F.level(), F.loadout(), snap, F.view(SessionPhase.REVIEW, -1), F.flat_projector(Vector2(0, 0), 40.0), SIZE)
	for b: Dictionary in review:
		if b["kind"] != WidgetMath.KIND_ENEMY:
			assert_eq(b["reach"], -1.0)


func test_threat_ticks_take_a_view() -> void:
	var t := _mount("res://ui/widgets/threat_ticks.tscn") as WidgetThreatTicks
	t.size = Vector2(800, 14)
	t.set_track(40.0, 720.0, 64.0)
	var v := F.view()
	v.beat = 10.0
	v.threat_beats = [10.5, 12.0, 30.0]
	t.set_view(v)
	await tree().process_frame
	assert_eq(t.ticks.size(), 3)
	assert_near(t.ticks[0].x, 40.0 + 10.5 / 64.0 * 720.0, 1e-6)


func test_gear02_loot_reveal_plays_and_emits_choice() -> void:
	var lr := _mount("res://ui/widgets/loot_reveal.tscn") as WidgetLootReveal
	await tree().process_frame
	var got: Array = []
	var finished := [false]
	lr.choice_made.connect(func(now: bool, ids: PackedStringArray) -> void: got.append([now, ids]))
	lr.reveal_finished.connect(func() -> void: finished[0] = true)
	var owned: Array = ["click_visor"]
	lr.show_loot(F.items(), LevelTheme.LOWER, owned)
	assert_eq(lr.new_flags, [true, false, true], "NEW unless owned before")
	assert_true(lr.duration() > 2.0)
	lr.seek(WidgetLootReveal.T_OPEN + 0.01)
	assert_true(lr.lid_open(lr.t) > 0.9)
	assert_false(lr.finished)
	lr.skip()
	assert_true(lr.finished)
	assert_true(finished[0])
	assert_true(lr._prompt.visible)
	for i: int in 3:
		assert_true(lr.card_progress(i, lr.t) >= 1.0)
	lr._btn_now.pressed.emit()
	lr._btn_later.pressed.emit()
	assert_eq(got.size(), 1, "one choice only")
	assert_eq(got[0][0], true)
	assert_eq(Array(got[0][1]), ["amp_sledge", "click_visor", "slick_sliders"])
	await tree().process_frame


func test_loot_reveal_with_nothing_offers_continue() -> void:
	var lr := _mount("res://ui/widgets/loot_reveal.tscn") as WidgetLootReveal
	await tree().process_frame
	var got: Array = []
	lr.choice_made.connect(func(now: bool, ids: PackedStringArray) -> void: got.append([now, ids.size()]))
	lr.show_loot([] as Array[GearItem])
	lr.skip()
	assert_false(lr._btn_now.visible)
	lr._btn_later.pressed.emit()
	assert_eq(got, [[false, 0]])
	await tree().process_frame


func test_gauge_failure_flash_from_events() -> void:
	var g := _mount("res://ui/widgets/momentum_gauge.tscn") as WidgetMomentumGauge
	g.setup(F.level(), F.loadout())
	g.update_gauge(_snap(), F.view(SessionPhase.RECORDING, 0, 1.0), F.flat_projector())
	var ev: Array[SimEvent] = [SimEvent.make(0, SimEventType.CLANG, 6.5, 4.5).with_tape(0).with_power(3.0).with_detail("needs 5")]
	g.on_events(ev)
	assert_true(g._fail != null and g._fail.title == "CLANG")
	await tree().process_frame
	# Not recording: hidden.
	g.update_gauge(_snap(), F.view(SessionPhase.REVIEW, -1), F.flat_projector())
	assert_false(g.state.visible)
