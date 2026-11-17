extends ODTest
## Kernel: enemies, momentum and dodging (TEST-18..21, Scenario K, AI-01..07, MOM-01..06).
## Port of prototype/tests/core/kernel/combat.test.ts.

const S = preload("res://tests/helpers/script.gd")

# ───────────────────────────── enemy targeting (TEST-18, AI-01..04) ─────────────────────────────


func _target_level() -> LevelDef:
	var ents: Array[EntityDef] = [S.enemy("g1", EnemyType.GRUNT, 9.5, 5.5)]
	return TestLevels.make_level({"speeds": [1.0], "bars": 3, "start": Vector2(2.5, 5.5), "entities": ents})


func _tape_a() -> ODTape:
	return S.path_tape(0, 1.0, 360, [[0, 2.5, 5.5]])


## B walks up close to the grunt's flank early on.
func _tape_b() -> ODTape:
	return S.path_tape(1, 1.0, 360, [[0, 2.5, 5.5], [40, 8.5, 2.0]])


func test_TEST18_a_closer_self_changes_the_grunts_target_while_the_old_tapes_path_is_unchanged() -> void:
	var level: LevelDef = _target_level()
	var solo: Resolution = S.resolve(level, [_tape_a()])
	var both: Resolution = S.resolve(level, [_tape_a(), _tape_b()])
	var targets_solo: Dictionary = {}
	for f: FrameSnapshot in solo.frames:
		if f.enemies[0].target >= 0:
			targets_solo[f.enemies[0].target] = true
	assert_eq(targets_solo.keys(), [0])
	# Once B is nearer, the grunt switches to B on a beat boundary.
	var switched: FrameSnapshot = null
	for f: FrameSnapshot in both.frames:
		if f.enemies[0].target == 1:
			switched = f
			break
	assert_true(switched != null)
	if switched == null:
		return
	# (Frames are stored every 4 substeps; the decision is taken on the beat's first substep.)
	assert_true(switched.sub % 120 <= 4, "switched at sub %d" % switched.sub)
	# The grunt now walks toward B (north) instead of west.
	var g: EnemySnap = S.frame_exact(both.frames, 480).enemies[0]
	var gs: EnemySnap = S.frame_exact(solo.frames, 480).enemies[0]
	assert_true(g.y < gs.y - 0.5, "grunt y %f vs solo %f" % [g.y, gs.y])
	# Tape A did not re-aim or re-route: identical positions and facings.
	assert_eq(_path(both), _path(solo))


func _path(r: Resolution) -> Array:
	var out: Array = []
	for f: FrameSnapshot in r.frames:
		out.append([f.actors[0].x, f.actors[0].y, f.actors[0].facing])
	return out


func test_AI07_the_grunt_strikes_on_its_beat_grid_and_one_strike_kills_a_self() -> void:
	var solo: Resolution = S.resolve(_target_level(), [_tape_a()])
	var attacks: Array[SimEvent] = S.events_of(solo.events, SimEventType.ENEMY_ATTACK, -1, "g1")
	assert_true(attacks.size() > 0)
	if attacks.is_empty():
		return
	for a: SimEvent in attacks:
		assert_eq(a.sub % 240, 0)
	var tel: Array[SimEvent] = S.events_of(solo.events, SimEventType.ENEMY_TELEGRAPH, -1, "g1")
	assert_eq(tel[0].sub, attacks[0].sub - 60)
	var deaths: Array = []
	for e: SimEvent in S.events_of(solo.events, SimEventType.SELF_DEATH):
		deaths.append([e.tape, e.detail, e.sub])
	assert_eq(deaths, [[0, "struck by grunt g1", attacks[0].sub]])
	# A dead ghost is never targeted again (and never killed twice).
	var untargeted: bool = true
	for f: FrameSnapshot in solo.frames:
		if f.sub > attacks[0].sub + 4 and f.enemies[0].target >= 0:
			untargeted = false
	assert_true(untargeted)


func test_ties_between_equally_near_selves_go_to_the_lowest_tape_index() -> void:
	var twin: ODTape = _tape_a()
	twin.index = 2
	var res: Resolution = S.resolve(_target_level(), [twin, _tape_a()])
	assert_eq(res.frames[2].enemies[0].target, 0)

# ───────────────────────────── knockback changes later outcomes (TEST-19, MOM-05) ─────────────────────────────


func test_TEST19_alone_As_swing_whiffs_after_B_knocks_the_grunt_into_it_the_same_swing_kills() -> void:
	var ents: Array[EntityDef] = [S.enemy("g1", EnemyType.GRUNT, 6.0, 5.5, {"hp": 2, "wake": SignalExpr.of_const(false)})]
	var level: LevelDef = TestLevels.make_level({"speeds": [1.0], "bars": 1, "start": Vector2(1.5, 5.5), "entities": ents})
	# A swings west at a spot where the grunt is not (yet).
	var tape_a: ODTape = S.path_tape(
		0, 1.0, 120, [[0, 1.5, 5.5], [20, 1.5, 3.5], [50, 8.2, 3.5], [60, 8.2, 5.5]], [[90, ActionKind.LIGHT, PI]]
	)
	# B stands west of the grunt and knocks it east with a light swing.
	var tape_b: ODTape = S.path_tape(1, 1.0, 120, [[0, 1.5, 5.5], [30, 5.0, 5.5]], [[40, ActionKind.LIGHT, 0.0]])

	var solo: Resolution = S.resolve(level, [tape_a])
	assert_eq(S.events_of(solo.events, SimEventType.WHIFF, 0).size(), 1)
	assert_eq(S.events_of(solo.events, SimEventType.KILL).size(), 0)

	var both: Resolution = S.resolve(level, [tape_a, tape_b])
	assert_eq(S.events_of(both.events, SimEventType.HIT, 1).size(), 1)
	# The grunt really moved and stayed where it landed (it is asleep, so it does not walk back).
	var landed: EnemySnap = S.frame_exact(both.frames, 300).enemies[0]
	assert_true(landed.x > 6.9, "landed at %f" % landed.x)
	assert_eq(landed.hp, 1)
	var kill: Array = []
	for e: SimEvent in S.events_of(both.events, SimEventType.KILL, -1, "g1"):
		kill.append(e.tape)
	assert_eq(kill, [0])
	assert_eq(S.events_of(both.events, SimEventType.WHIFF, 0).size(), 0)

# ───────────────────────────── momentum (TEST-20, MOM-01..04) ─────────────────────────────


## One light swing at a tough sleeping grunt; returns what it did.
func _strike(speed: float, motion: String) -> Dictionary:
	var ents: Array[EntityDef] = [S.enemy("g1", EnemyType.GRUNT, 6.0, 5.5, {"hp": 10, "wake": SignalExpr.of_const(false)})]
	var level: LevelDef = TestLevels.make_level(
		{"speeds": [0.5, 1.0, 2.0], "bars": 1, "start": Vector2(5.0, 5.5), "entities": ents}
	)
	# Hit frame is 6 local ticks after the event. Approach speed 4.5 tiles per local second.
	var v: float = 4.5 / 60.0
	var path: Array
	if motion == "stand":
		path = [[0, 5.0, 5.5]]
	elif motion == "into":
		path = [[0, 5.0 - 26 * v, 5.5], [26, 5.0, 5.5]]
	else:
		path = [[0, 5.0 + 6 * v, 5.5], [20, 5.0 + 6 * v, 5.5], [26, 5.0, 5.5]]
	var tape: ODTape = S.path_tape(0, speed, 120, path, [[20, ActionKind.LIGHT, 0.0]])
	var res: Resolution = S.resolve(level, [tape])
	var hit: SimEvent = S.events_of(res.events, SimEventType.HIT)[0]
	var stagger: Array[SimEvent] = S.events_of(res.events, SimEventType.ENEMY_STAGGER)
	var end: EnemySnap = res.frames[res.frames.size() - 1].enemies[0]
	return {
		"momentum": hit.power,
		"damage": 10 - end.hp,
		"knockback": end.x - 6.0,
		"stagger": stagger[0].power if not stagger.is_empty() else 0.0,
		"clang": S.events_of(res.events, SimEventType.CLANG).size(),
	}


func test_TEST20_tape_speed_and_movement_into_the_strike_change_momentum_damage_knockback_and_stagger() -> void:
	var slow: Dictionary = _strike(0.5, "stand")
	var mid: Dictionary = _strike(1.0, "stand")
	var fast: Dictionary = _strike(2.0, "stand")
	var into: Dictionary = _strike(1.0, "into")
	var away: Dictionary = _strike(1.0, "away")
	assert_near(slow["momentum"], 0.6, 1e-5)
	assert_near(mid["momentum"], 1.2, 1e-5)
	assert_near(fast["momentum"], 2.4, 1e-5)
	assert_true(into["momentum"] > mid["momentum"])
	assert_true(away["momentum"] < mid["momentum"])
	# Damage: 0.5x standing does nothing (and says so), 1x one point, 2x two points.
	assert_eq([slow["damage"], mid["damage"], fast["damage"]], [0, 1, 2])
	assert_eq(slow["clang"], 1)
	assert_eq(mid["clang"], 0)
	# Knockback and stagger scale with momentum.
	for k: String in ["knockback", "stagger"]:
		assert_true(slow[k] < mid[k], k)
		assert_true(mid[k] < fast[k], k)
		assert_true(away[k] < mid[k], k)
		assert_true(into[k] > mid[k], k)
	assert_near(mid["knockback"], 1.2, 0.05)

# ───────────────────────────── dodge i-frames (TEST-21, COMBAT-04) ─────────────────────────────


func _dodge_level() -> LevelDef:
	# One shot only (beat 2), so the test is about that bolt.
	var ents: Array[EntityDef] = [S.enemy("t1", EnemyType.TURRET, 10.5, 5.5, {"facing": PI, "beat": [64, 2]})]
	return TestLevels.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(5.0, 5.5), "entities": ents})


func _stand(dodge_at: int = -1) -> ODTape:
	var evs: Array = [] if dodge_at < 0 else [[dodge_at, ActionKind.DODGE]]
	return S.path_tape(0, 1.0, 240, [[0, 5.0, 5.5]], evs)


func test_TEST21_a_bolt_arriving_inside_the_dodges_iframes_passes_through_outside_them_it_kills() -> void:
	var level: LevelDef = _dodge_level()
	var none: Resolution = S.resolve(level, [_stand()])
	var death: Array[SimEvent] = S.events_of(none.events, SimEventType.SELF_DEATH)
	assert_eq(death.size(), 1)
	if death.is_empty():
		return
	@warning_ignore("integer_division")
	var hit_tick: int = death[0].sub / 4
	# I-frames cover local ticks [dodge + 1, dodge + 11): start the dodge 4 ticks before contact.
	var dodged: Resolution = S.resolve(level, [_stand(hit_tick - 4)])
	assert_eq(S.events_of(dodged.events, SimEventType.SELF_DEATH).size(), 0)
	assert_eq(S.events_of(dodged.events, SimEventType.DODGE).size(), 1)
	# The bolt flew on and broke on the wall behind.
	var walled: bool = false
	for e: SimEvent in S.events_of(dodged.events, SimEventType.PROJECTILE_HIT):
		walled = walled or e.detail == "bolt:wall"
	assert_true(walled)
	var late: Resolution = S.resolve(level, [_stand(hit_tick - 30)])
	assert_eq(S.events_of(late.events, SimEventType.SELF_DEATH).size(), 1)


func test_a_recorded_dodge_gives_the_live_self_the_same_iframes() -> void:
	var take: TestScript.TakeResult = S.record_take(_dodge_level(), 0, 1.0, S.input_script().press(101, ActionKind.DODGE))
	var n: int = 0
	for f: FrameSnapshot in take.frames:
		if f.actors[0].iframes:
			n += 1
	assert_eq(n, 10)

# ───────────────────────────── momentum threshold wall (Scenario K) ─────────────────────────────


## Scenario K: one breakable wall in front of the exit.
func _wall_level() -> LevelDef:
	var ents: Array[EntityDef] = [S.breakable("w1", 8, 5, Tuning.TUTORIAL_WALL_THRESHOLD)]
	return TestLevels.make_level(
		{
			"speeds": [0.5, 1.0, 2.0],
			"bars": 2,
			"start": Vector2(1.5, 5.5),
			"entities": ents,
			"objective": S.objective(ObjectiveType.SIGNAL, "Break the wall", [], SignalExpr.of_sig("w1")),
		}
	)


## Record a run at the wall; press `button` when the self first reaches x >= 6.6 (running) or 20
## ticks after it reaches the wall (standing).
func _wall_take(speed: float, button: StringName, running: bool) -> Array:
	var level: LevelDef = _wall_level()
	var probe: ODSim = ODSim.create_sim(SimConfig.make(level, TestLoadout.base_loadout(), [], LiveTake.make(0, speed, OD.EndMode.STOP)))
	var run: TestScript.InputScript = S.input_script().run(0, 1000, 1, 0)
	var press_at: int = -1
	for t: int in probe.tape_ticks:
		probe.step_local_tick(run.input(t))
		var x: float = probe.snapshot().actors[0].x
		if running and x >= 6.6:
			press_at = t + 1
			break
		if not running and x >= 7.69:
			press_at = t + 20
			break
	assert_true(press_at > 0)
	var sc: TestScript.InputScript
	if running:
		sc = S.input_script().run(0, 1000, 1, 0).press(press_at, button, 0.0)
	else:
		sc = S.input_script().run(0, press_at - 15, 1, 0).press(press_at, button, 0.0)
	var take: TestScript.TakeResult = S.record_take(level, 0, speed, sc)
	return [take, S.resolve(level, [take.tape])]


func test_ScenarioK_a_1x_standing_light_clangs_and_the_outcome_says_how_much_momentum_was_missing() -> void:
	var tr: Array = _wall_take(1.0, ActionKind.LIGHT, false)
	var take: TestScript.TakeResult = tr[0]
	var res: Resolution = tr[1]
	var clang: Array[SimEvent] = S.events_of(take.events, SimEventType.CLANG, -1, "w1")
	assert_eq(clang.size(), 1)
	if clang.size() == 1:
		assert_near(clang[0].power, 1.2, 1e-5)
	assert_eq(S.events_of(res.events, SimEventType.BREAK).size(), 0)
	assert_false(res.outcome.win)
	var re := RegEx.create_from_string("Tape A's light at beat [\\d.]+ hit breakable wall w1 with momentum 1\\.2; it needs 5\\.")
	var found: bool = false
	for n: String in res.outcome.notes:
		found = found or re.search(n) != null
	assert_true(found, "notes: %s" % [res.outcome.notes])


func test_ScenarioK_a_1x_running_heavy_and_a_2x_standing_heavy_are_still_too_weak() -> void:
	var run_heavy: Resolution = _wall_take(1.0, ActionKind.HEAVY, true)[1]
	assert_eq(S.events_of(run_heavy.events, SimEventType.BREAK).size(), 0)
	assert_near(S.events_of(run_heavy.events, SimEventType.CLANG, -1, "w1")[0].power, 3.0, 1e-5)
	var stand_heavy: Resolution = _wall_take(2.0, ActionKind.HEAVY, false)[1]
	assert_eq(S.events_of(stand_heavy.events, SimEventType.BREAK).size(), 0)
	assert_near(S.events_of(stand_heavy.events, SimEventType.CLANG, -1, "w1")[0].power, 4.0, 1e-5)


func test_ScenarioK_a_2x_running_heavy_breaks_it_and_the_self_can_walk_through_the_gap() -> void:
	var tr: Array = _wall_take(2.0, ActionKind.HEAVY, true)
	var take: TestScript.TakeResult = tr[0]
	var res: Resolution = tr[1]
	var brk: Array[SimEvent] = S.events_of(res.events, SimEventType.BREAK, -1, "w1")
	assert_eq(brk.size(), 1)
	if brk.size() == 1:
		assert_near(brk[0].power, 6.0, 1e-5)
	assert_eq(S.events_of(take.events, SimEventType.BREAK, -1, "w1").size(), 1)
	assert_true(res.outcome.win)
	assert_true(take.frames[take.frames.size() - 1].actors[0].x > 9)
	assert_true(res.frames[res.frames.size() - 1].mech("w1").on)
