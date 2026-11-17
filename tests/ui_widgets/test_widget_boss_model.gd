extends ODTest
## WidgetBossModel: health and ghost bar, phase marks from BossBehaviour.boss_phase_for, armour,
## and the memory tell (HEALTH-03, BOSS-01..03, chapter 10 "Fairness").

const F := preload("res://tests/ui_widgets/widget_fixtures.gd")


func test_health03_phase_marks_are_where_the_sim_changes_phase() -> void:
	for mx: int in [40, 30, 7, 100]:
		var marks := WidgetBossModel.phase_marks_for(mx)
		assert_eq(marks.size(), 2, "max %d" % mx)
		for f: float in marks:
			var h := roundi(f * mx)
			assert_ne(BossBehaviour.boss_phase_for(h, mx), BossBehaviour.boss_phase_for(h + 1, mx), "boundary at %d/%d" % [h, mx])
		assert_true(marks[0] > marks[1], "descending")
	assert_eq(WidgetBossModel.phase_marks_for(40), [26.0 / 40.0, 13.0 / 40.0])


func test_health03_ghost_bar_holds_then_drains() -> void:
	var m := WidgetBossModel.new()
	m.update(F.boss(40, 1), 0.0, 0.0)
	assert_eq(m.frac, 1.0)
	m.update(F.boss(30, 1), 1.0, 0.0)
	assert_near(m.frac, 0.75, 1e-9)
	assert_eq(m.ghost, 1.0, "ghost keeps the lost chunk")
	m.advance(WidgetBossModel.GHOST_HOLD * 0.5)
	assert_eq(m.ghost, 1.0, "still holding")
	m.advance(WidgetBossModel.GHOST_HOLD)
	m.advance(0.1)
	assert_true(m.ghost < 1.0 and m.ghost > m.frac, "draining")
	for k in 40:
		m.advance(0.1)
	assert_eq(m.ghost, m.frac, "caught up")
	assert_true(m.hit_flash <= 0.0)


func test_phase_plates_and_armour() -> void:
	var m := WidgetBossModel.new()
	m.update(F.boss(40, 1), 0.0, 0.0)
	assert_eq(m.plates, 3)
	assert_eq(m.armour, WidgetBossModel.ARMOUR_GUARDED)
	assert_eq(m.attention, 0)
	var e := F.boss(20, 2)
	e.state = EnemyStateName.STAGGER
	m.update(e, 1.0, 0.0)
	assert_eq(m.phase, 2)
	assert_eq(m.plates, 2)
	assert_eq(m.armour, WidgetBossModel.ARMOUR_OPEN)
	assert_true(m.phase_flash > 0.0)
	var d := F.boss(0, 3)
	d.alive = false
	m.update(d, 2.0, 0.0)
	assert_eq(m.armour, WidgetBossModel.ARMOUR_BROKEN)
	assert_eq(m.plates, 0)


func test_boss02_memory_tell_names_the_cassette_and_landing_beat() -> void:
	var m := WidgetBossModel.new()
	m.update(F.boss(40, 1), 9.0, 0.0)
	assert_false(m.recalling)
	var ev: Array[SimEvent] = [SimEvent.make(0, SimEventType.BOSS_RECALL, 3, 6).with_id("archivist").with_tape(1).with_power(12.0).with_detail("dwell")]
	m.on_events(ev)
	m.update(F.boss(40, 1, 1), 10.5, 0.0)
	assert_true(m.recalling)
	assert_eq(m.recall_tape, 1)
	assert_eq(m.recall_reason, BossMemoryLib.REASON_DWELL)
	assert_eq(m.recall_land_beat, 12.0)
	assert_near(m.recall_beats_left, 1.5, 1e-9)
	assert_true(m.has_recall_at)
	assert_vec_near(m.recall_at, Vector2(3, 6), 1e-9)
	m.update(F.boss(40, 1), 12.5, 0.0)
	assert_false(m.recalling)
	assert_eq(m.recall_tape, -1)


func test_recall_without_event_estimates_landing_from_telegraph() -> void:
	var m := WidgetBossModel.new()
	m.update(F.boss(40, 1), 4.0, 0.0)
	m.update(F.boss(40, 1, 2), 5.0, 0.0) # state_t 0.25 of a 2-beat telegraph
	assert_near(m.recall_land_beat, 5.0 + 1.5, 1e-9)


func test_events_for_other_ids_are_ignored() -> void:
	var m := WidgetBossModel.new()
	m.update(F.boss(40, 1), 0.0, 0.0)
	var ev: Array[SimEvent] = [SimEvent.make(0, SimEventType.CLANG, 0, 0).with_id("someone_else").with_tape(0).with_detail("armour")]
	m.on_events(ev)
	assert_eq(m.clang_flash, 0.0)
	ev = [SimEvent.make(0, SimEventType.CLANG, 0, 0).with_id("archivist").with_tape(2).with_detail("armour")]
	m.on_events(ev)
	assert_true(m.clang_flash > 0.0)
	assert_eq(m.clang_tape, 2)


func test_remembered_tapes_from_memory() -> void:
	var m := WidgetBossModel.new()
	m.set_memory(F.memory([2, 0] as Array[int]))
	assert_eq(m.remembered, [0, 2])
	assert_eq(m.remembered_moments[0], 1, "one dwell each")
	m.set_memory(null)
	assert_eq(m.remembered.size(), 0)


func test_find_boss() -> void:
	var snap := FrameSnapshot.new()
	assert_eq(WidgetBossModel.find_boss(snap), null)
	snap.enemies.append(F.enemy("g", EnemyType.GRUNT, 0, 0, 1, 1))
	snap.enemies.append(F.boss(40, 1))
	assert_eq(WidgetBossModel.find_boss(snap).id, "archivist")
