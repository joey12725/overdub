extends ODTest
## WidgetMath: the gauge's numbers come from the sim's own functions (MOM-01..04), thresholds compare
## exactly like the sim (Scenario K), targets are picked by facing, failures are explained.

const F := preload("res://tests/ui_widgets/widget_fixtures.gd")

var L: ResolvedLoadout = null


func before_each() -> void:
	L = F.loadout()


# ───────────────────────────── momentum = the sim's formula ─────────────────────────────

func test_mom01_preview_matches_tuning_for_every_speed_and_motion() -> void:
	var dirs := [0.0, 0.7, -2.1]
	var vels := [Vector2.ZERO, Vector2(4.5, 0), Vector2(-3, 2), Vector2(1, -4)]
	for s: float in OD.ALL_SPEEDS:
		for d: float in dirs:
			for v: Vector2 in vels:
				for kind: StringName in [ActionKind.LIGHT, ActionKind.HEAVY]:
					var p := WidgetMath.preview_swing(L, kind, s, v.x, v.y, d)
					var sw: MeleeSwingDef = L.melee.heavy if kind == ActionKind.HEAVY else L.melee.light
					var want := Tuning.swing_momentum(sw, L.mods, s, v.x, v.y, d)
					assert_eq(p.momentum, want, "%s at %s dir %s v %s" % [kind, s, d, v])
					assert_eq(p.damage, Tuning.strike_damage(want, L.melee.damage_eff, L.mods.damage))


func test_mom01_standing_light_1x_deals_one_and_half_speed_none() -> void:
	assert_eq(WidgetMath.preview_swing(L, ActionKind.LIGHT, 1.0, 0, 0, 0).damage, 1)
	assert_eq(WidgetMath.preview_swing(L, ActionKind.LIGHT, 0.5, 0, 0, 0).damage, 0)


func test_mom03_running_into_the_swing_adds_running_away_subtracts() -> void:
	var into := WidgetMath.preview_swing(L, ActionKind.HEAVY, 1.0, Tuning.BASE.run_speed, 0, 0.0)
	var still := WidgetMath.preview_swing(L, ActionKind.HEAVY, 1.0, 0, 0, 0.0)
	var away := WidgetMath.preview_swing(L, ActionKind.HEAVY, 1.0, -Tuning.BASE.run_speed, 0, 0.0)
	assert_near(into.momentum, 3.0, 1e-9, "1x running heavy = 2 x 1.5")
	assert_near(still.momentum, 2.0, 1e-9)
	assert_near(away.momentum, 1.5, 1e-9, "approach clamps at -0.5")
	assert_near(into.full, into.momentum, 1e-9, "full run-in is the cap")
	assert_near(still.standing, 2.0, 1e-9)


func test_mom01_local_velocity_divides_master_velocity_by_tape_speed() -> void:
	var a := F.actor(0, 0, 0, 0.0, true)
	a.vx = 9.0
	a.vy = -2.0
	assert_vec_near(WidgetMath.local_velocity(a, 2.0), Vector2(4.5, -1.0), 1e-9)
	assert_vec_near(WidgetMath.local_velocity(a, 0.0), Vector2.ZERO, 1e-9)
	# At 2x a full-speed run in master space is a full-speed run in local space: approach 1, counted once.
	var lv := WidgetMath.local_velocity(a, 2.0)
	assert_near(Tuning.strike_approach(lv.x, 0.0, 0.0), 1.0, 1e-9)


func test_faster_tape_hits_harder_and_1x_mark_is_the_same_swing_at_1x() -> void:
	var p := WidgetMath.preview_swing(L, ActionKind.HEAVY, 2.0, 0, 0, 0)
	assert_near(p.momentum, 4.0, 1e-9)
	assert_near(p.at_1x, 2.0, 1e-9)


# ───────────────────────────── thresholds (Scenario K) ─────────────────────────────

func _gauge(speed: float, running: bool) -> WidgetMath.GaugeState:
	var a := F.actor(0, 4.6, 4.5, 0.0, true)
	if running:
		a.vx = Tuning.BASE.run_speed * speed
	var snap := FrameSnapshot.new()
	snap.actors.append(a)
	var speeds: Array[float] = [0.5, 1.0, 2.0, 4.0]
	return WidgetMath.gauge_state(a, speed, NAN, L, F.level(), snap, speeds)


func test_scenario_k_2x_running_heavy_breaks_tutorial_wall() -> void:
	var g := _gauge(2.0, true)
	assert_eq(g.target.kind, WidgetMath.KIND_BREAKABLE)
	assert_eq(g.target.id, "wall")
	assert_eq(g.target.threshold, Tuning.TUTORIAL_WALL_THRESHOLD)
	assert_true(g.heavy_meets, "6 >= 5")
	assert_false(g.light_meets)
	assert_eq(g.ticks.size(), 1)
	assert_eq(g.ticks[0].kind, WidgetMath.TICK_THRESHOLD)


func test_scenario_k_1x_running_heavy_fails_and_names_2x() -> void:
	var g := _gauge(1.0, true)
	assert_false(g.heavy_meets, "3 < 5")
	assert_false(g.heavy_can_meet)
	assert_eq(g.min_speed, 2.0)


func test_scenario_k_2x_standing_heavy_fails_but_run_in_would_do() -> void:
	var g := _gauge(2.0, false)
	assert_false(g.heavy_meets, "4 < 5")
	assert_true(g.heavy_can_meet, "full run-in 6 >= 5")


func test_threshold_comparison_is_inclusive_like_the_sim() -> void:
	assert_true(WidgetMath.meets(5.0, 5.0))
	assert_false(WidgetMath.meets(4.999999, 5.0))


func test_core_without_threshold_uses_sim_default() -> void:
	var c := CoreDef.new()
	assert_eq(WidgetMath.core_threshold(c), Tuning.DEFAULT_CORE_THRESHOLD)
	c.threshold = 3.5
	c.has_threshold = true
	assert_eq(WidgetMath.core_threshold(c), 3.5)


func test_pips_and_segments() -> void:
	assert_eq(WidgetMath.pip_slots(5.0), 5)
	assert_eq(WidgetMath.pip_slots(4.5), 5)
	assert_eq(WidgetMath.pip_slots(0.2), 1)
	assert_near(WidgetMath.force_pips(4.5), 4.5, 1e-9)
	assert_eq(WidgetMath.gauge_segments(3.0, 5.0), 6, "5 x 1.15 -> 6")
	assert_eq(WidgetMath.gauge_segments(1.0, 0.0), WidgetMath.MIN_SEGMENTS)
	assert_eq(WidgetMath.gauge_segments(100.0, 0.0), WidgetMath.MAX_SEGMENTS)
	assert_near(WidgetMath.gauge_fraction(3.0, 6), 0.5, 1e-9)
	assert_eq(WidgetMath.gauge_fraction(99.0, 6), 1.0)


func test_min_speed_for_threshold() -> void:
	var speeds: Array[float] = [4.0, 0.5, 1.0, 2.0]
	assert_eq(WidgetMath.min_speed_for(L, 5.0, speeds), 2.0)
	assert_eq(WidgetMath.min_speed_for(L, 2.5, speeds), 1.0)
	assert_eq(WidgetMath.min_speed_for(L, 100.0, speeds), 0.0)


# ───────────────────────────── hit-point bands (HEALTH-02) ─────────────────────────────

func test_health02_damage_ticks_agree_with_strike_damage_under_mods() -> void:
	var razor := TestLoadout.base_loadout({"mods": {"damage": 1.35}})
	for k: int in range(1, 7):
		var m := WidgetMath.momentum_for_damage(razor, k)
		assert_true(Tuning.strike_damage(m, razor.melee.damage_eff, razor.mods.damage) >= k, "k=%d enough" % k)
		assert_true(Tuning.strike_damage(m * 0.999, razor.melee.damage_eff, razor.mods.damage) < k, "k=%d minimal" % k)


func test_health02_brute_bands_and_hits() -> void:
	var a := F.actor(0, 3.0, 3.0, 0.0, true)
	a.vx = Tuning.BASE.run_speed
	var snap := FrameSnapshot.new()
	snap.actors.append(a)
	snap.enemies.append(F.enemy("b1", EnemyType.BRUTE, 4.0, 3.0, 3, 3))
	var speeds: Array[float] = [1.0]
	var lvl := LevelDef.new()
	var g := WidgetMath.gauge_state(a, 1.0, NAN, L, lvl, snap, speeds)
	assert_eq(g.target.kind, WidgetMath.KIND_ENEMY)
	assert_eq(g.target.hp, 3)
	var kinds: Array[StringName] = []
	for t: WidgetMath.Tick in g.ticks:
		kinds.append(t.kind)
	assert_eq(kinds, [WidgetMath.TICK_DAMAGE, WidgetMath.TICK_DAMAGE, WidgetMath.TICK_KILL, WidgetMath.TICK_SHOVE])
	assert_eq(g.heavy_hits, 1, "1x running heavy = 3 damage kills a brute")
	assert_eq(g.light_hits, 3, "1x running light 1.8 -> 1 damage -> 3 hits")


func test_hits_to_kill() -> void:
	assert_eq(WidgetMath.hits_to_kill(3, 1), 3)
	assert_eq(WidgetMath.hits_to_kill(3, 2), 2)
	assert_eq(WidgetMath.hits_to_kill(2, 5), 1)
	assert_eq(WidgetMath.hits_to_kill(2, 0), -1)


func test_boss_target_marks_stagger_line() -> void:
	var a := F.actor(0, 6.0, 3.6, -PI / 2.0, true)
	var snap := FrameSnapshot.new()
	snap.actors.append(a)
	snap.enemies.append(F.boss(40, 1))
	var speeds: Array[float] = [1.0]
	var g := WidgetMath.gauge_state(a, 2.0, NAN, L, LevelDef.new(), snap, speeds)
	assert_eq(g.target.kind, WidgetMath.KIND_BOSS)
	assert_eq(g.ticks.size(), 1)
	assert_eq(g.ticks[0].momentum, BossBehaviour.BOSS_STAGGER_MOMENTUM)
	assert_true(g.heavy_meets, "2x standing heavy = 4 staggers")


# ───────────────────────────── facing ─────────────────────────────

func test_pick_target_needs_facing_and_range() -> void:
	var lvl := F.level()
	# Wall tile (6,4) centre (6.5, 4.5).
	assert_eq(WidgetMath.pick_target(Vector2(5.0, 4.5), 0.0, 1.1, lvl, null).id, "wall")
	assert_eq(WidgetMath.pick_target(Vector2(5.0, 4.5), PI, 1.1, lvl, null).kind, WidgetMath.KIND_NONE, "facing away")
	assert_eq(WidgetMath.pick_target(Vector2(0.5, 4.5), 0.0, 1.1, lvl, null).kind, WidgetMath.KIND_NONE, "too far")


func test_pick_target_skips_broken_and_prefers_nearer_enemy() -> void:
	var lvl := F.level()
	var snap := FrameSnapshot.new()
	var m := MechSnap.new()
	m.id = "wall"
	m.kind = MechKind.BREAKABLE
	m.on = true
	snap.mechs.append(m)
	assert_eq(WidgetMath.pick_target(Vector2(5.0, 4.5), 0.0, 1.1, lvl, snap).kind, WidgetMath.KIND_NONE, "broken wall")
	m.on = false
	snap.enemies.append(F.enemy("g", EnemyType.GRUNT, 5.7, 4.5, 1, 1))
	assert_eq(WidgetMath.pick_target(Vector2(5.0, 4.5), 0.0, 1.1, lvl, snap).id, "g")
	snap.enemies[0].alive = false
	assert_eq(WidgetMath.pick_target(Vector2(5.0, 4.5), 0.0, 1.1, lvl, snap).id, "wall")


func test_gauge_hidden_without_live_self_or_loadout() -> void:
	var speeds: Array[float] = []
	assert_false(WidgetMath.gauge_state(null, 1.0, NAN, L, null, null, speeds).visible)
	assert_false(WidgetMath.gauge_state(F.actor(0, 0, 0, 0), 1.0, NAN, null, null, null, speeds).visible)


# ───────────────────────────── why a swing failed (MOM-01) ─────────────────────────────

func test_failure_info_reads_clang_details() -> void:
	var ev := SimEvent.make(10, SimEventType.CLANG, 6.5, 4.5).with_tape(1).with_power(3.0).with_detail("needs 5")
	var f := WidgetMath.failure_info(ev, 1, L)
	assert_true(f.valid)
	assert_eq(f.title, "CLANG")
	assert_eq(f.need, 5.0)
	assert_eq(f.had, 3.0)
	assert_true(f.line.contains("needs 5") and f.line.contains("had 3"), f.line)
	var weak := WidgetMath.failure_info(SimEvent.make(0, SimEventType.CLANG, 0, 0).with_tape(1).with_power(0.6).with_detail("momentum"), 1, L)
	assert_eq(weak.title, "NO DAMAGE")
	assert_near(weak.need, 1.0, 1e-9)
	assert_eq(WidgetMath.failure_info(SimEvent.make(0, SimEventType.CLANG, 0, 0).with_tape(1).with_detail("armour"), 1, L).title, "ARMOUR")
	assert_eq(WidgetMath.failure_info(SimEvent.make(0, SimEventType.CLANG, 0, 0).with_tape(1).with_detail("shield"), 1, L).title, "SHIELD")
	assert_eq(WidgetMath.failure_info(SimEvent.make(0, SimEventType.WHIFF, 0, 0).with_tape(1), 1, L).title, "WHIFF")
	assert_false(WidgetMath.failure_info(ev, 2, L).valid, "other tape")
	assert_false(WidgetMath.failure_info(SimEvent.make(0, SimEventType.HIT, 0, 0).with_tape(1), 1, L).valid)


func test_fmt_and_speed_label() -> void:
	assert_eq(WidgetMath.fmt(5.0), "5")
	assert_eq(WidgetMath.fmt(4.5), "4.5")
	assert_eq(WidgetMath.fmt(2.9999), "3")
	assert_eq(WidgetMath.speed_label(2.0), "2×")
	assert_eq(WidgetMath.speed_label(0.5), "0.5×")
