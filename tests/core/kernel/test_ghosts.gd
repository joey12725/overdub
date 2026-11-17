extends ODTest
## Kernel: death, ghosts and survival (TEST-07..12, TEST-23, TEST-24, Scenarios C and D).
## Port of prototype/tests/core/kernel/ghosts.test.ts.

const S = preload("res://tests/helpers/script.gd")


## The rescue room (Scenario C):
##
##          0         1
##          012345678901
##     r0   ############
##     r1   #.L...#....#     L  lever (2.5, 1.5)
##     r2   #..g..#....#     g  grunt g1, asleep (3.0, 2.55)
##     r3   #..@..D....#     @  start (3.0, 3.5)    D door "gate" (6, 3), opened by the lever
##     r4   #T....#....#     T  turret t1 (1.5, 4.5)
##     r5   ############
func _rescue_room(gate_open_when: SignalExpr = null) -> LevelDef:
	var ents: Array[EntityDef] = [
		S.enemy("t1", EnemyType.TURRET, 1.5, 4.5),
		S.enemy("g1", EnemyType.GRUNT, 3.0, 2.55, {"wake": SignalExpr.of_const(false)}),
		S.switch_def("lever", 2.5, 1.5),
		S.door("gate", [Vector2i(6, 3)], gate_open_when if gate_open_when != null else SignalExpr.of_sig("lever")),
	]
	var map: Array[String] = ["############", "#.....#....#", "#.....#....#", "#..........#", "#.....#....#", "############"]
	var targets: Array[String] = ["g1"]
	return TestLevels.make_level(
		{
			"speeds": [1.0, 2.0],
			"bars": 4,
			"map": map,
			"start": Vector2(3.0, 3.5),
			"entities": ents,
			"objective": S.objective(ObjectiveType.ELIMINATE, "Destroy the grunt", targets),
		}
	)


## Tape A: stands at the start (the turret kills it early), then - as a ghost - strikes, flips the
## lever and walks through the door.
func _tape_a_script() -> TestScript.InputScript:
	return (
		S.input_script()
		.aim(0, 480, -PI / 2)
		.press(100, ActionKind.LIGHT, -PI / 2)
		.run(130, 150, -0.3, -1)
		.press(160, ActionKind.INTERACT)
		.run(175, 200, 0.55, 1)
		.run(200, 300, 1, 0)
	)


func _details(evs: Array[SimEvent]) -> Array:
	var out: Array = []
	for e: SimEvent in evs:
		out.append(e.detail)
	return out


func _tapes(evs: Array[SimEvent]) -> Array:
	var out: Array = []
	for e: SimEvent in evs:
		out.append(e.tape)
	return out


func _has_note(r: Resolution, pattern: String) -> bool:
	var re := RegEx.create_from_string(pattern)
	for n: String in r.outcome.notes:
		if re.search(n) != null:
			return true
	return false

# ───────────────────────────── ghosts while recording (TEST-07..09) ─────────────────────────────


func test_TEST07_dying_does_not_end_the_take_the_self_continues_as_a_recording_ghost() -> void:
	var take: TestScript.TakeResult = S.record_take(_rescue_room(), 0, 1.0, _tape_a_script())
	var deaths: Array[SimEvent] = S.events_of(take.events, SimEventType.SELF_DEATH)
	assert_eq(deaths.size(), 1)
	if deaths.is_empty():
		return
	assert_eq(deaths[0].detail, "shot by turret t1")
	assert_true(take.sim.done)
	assert_eq(take.tape.ticks, take.sim.tape_ticks)
	var last: ActorSnap = take.frames[take.frames.size() - 1].actors[0]
	assert_eq(last.life, OD.LifeState.REC_GHOST)
	assert_true(last.live)
	# It kept moving after death (it walked to the lever and through the door).
	var at_death: ActorSnap = null
	for f: FrameSnapshot in take.frames:
		if f.sub > deaths[0].sub:
			at_death = f.actors[0]
			break
	assert_true(Vector2(last.x - at_death.x, last.y - at_death.y).length() > 2)


func test_TEST08_the_recording_ghost_is_still_blocked_by_a_closed_door() -> void:
	var blocked: LevelDef = _rescue_room(SignalExpr.of_const(false))
	var t: TestScript.TakeResult = S.record_take(blocked, 0, 1.0, _tape_a_script())
	assert_eq(S.events_of(t.events, SimEventType.SELF_DEATH).size(), 1)
	var max_x: float = -INF
	for f: FrameSnapshot in t.frames:
		max_x = maxf(max_x, f.actors[0].x)
	assert_true(max_x < 6 - 0.29, "max x %f" % max_x)
	assert_eq(t.frames[t.frames.size() - 1].actors[0].life, OD.LifeState.REC_GHOST)


func test_TEST09_the_recording_ghost_strikes_and_flips_a_switch_in_its_own_provisional_run() -> void:
	var take: TestScript.TakeResult = S.record_take(_rescue_room(), 0, 1.0, _tape_a_script())
	var deaths: Array[SimEvent] = S.events_of(take.events, SimEventType.SELF_DEATH)
	var kills: Array[SimEvent] = S.events_of(take.events, SimEventType.KILL, -1, "g1")
	assert_eq(kills.size(), 1)
	if kills.size() != 1 or deaths.is_empty():
		return
	assert_eq(kills[0].tape, 0)
	assert_true(kills[0].sub > deaths[0].sub)
	assert_eq(_details(S.events_of(take.events, SimEventType.INTERACT, -1, "lever")), ["on"])
	assert_eq(_details(S.events_of(take.events, SimEventType.DOOR, -1, "gate")), ["open"])
	# It walked through the door it opened.
	assert_true(take.frames[take.frames.size() - 1].actors[0].x > 7)
	# And it could not be hurt again: one death only, even though the turret kept its lane.
	assert_eq(take.outcome.survivors, [])

# ───────────────────────────── ghosts on playback (TEST-10, TEST-11, Scenario C) ─────────────────────────────


func test_TEST10_ScenarioC_replayed_the_tape_dies_again_and_its_later_strike_and_switch_have_no_effect() -> void:
	var level: LevelDef = _rescue_room()
	var take: TestScript.TakeResult = S.record_take(level, 0, 1.0, _tape_a_script())
	var res: Resolution = S.resolve(level, [take.tape])
	assert_eq(S.events_of(res.events, SimEventType.SELF_DEATH, 0).size(), 1)
	assert_eq(S.events_of(res.events, SimEventType.KILL).size(), 0)
	assert_eq(S.events_of(res.events, SimEventType.INTERACT).size(), 0)
	# The door the recording ghost opened stays shut for the whole run.
	var shut: bool = true
	for f: FrameSnapshot in res.frames:
		shut = shut and not f.mech("gate").on
	assert_true(shut)
	# The ghost still follows the recorded path exactly, through the closed door.
	for f: FrameSnapshot in take.frames:
		var g: FrameSnapshot = S.frame_exact(res.frames, f.sub)
		if g != null and not assert_eq([g.actors[0].x, g.actors[0].y], [f.actors[0].x, f.actors[0].y], "sub %d" % f.sub):
			break
	var last: ActorSnap = res.frames[res.frames.size() - 1].actors[0]
	assert_eq(last.life, OD.LifeState.GHOST)
	assert_true(last.x > 7)
	assert_false(res.outcome.win)
	assert_eq(res.outcome.reason, FailReason.OBJECTIVE)
	assert_true(_has_note(res, "Tape A died at beat [\\d.]+: shot by turret t1"), "notes: %s" % [res.outcome.notes])


func test_TEST11_when_another_tape_prevents_the_fatal_hit_the_later_recorded_actions_become_effective() -> void:
	var level: LevelDef = _rescue_room()
	var take: TestScript.TakeResult = S.record_take(level, 0, 1.0, _tape_a_script())
	# Tape B (2x) runs at the turret and destroys it before its first shot.
	var take_b: TestScript.TakeResult = S.record_take(
		level,
		1,
		2.0,
		S.input_script().run(0, 9, -1.5, 1).press(9, ActionKind.LIGHT, atan2(1, -1.5)).run(30, 60, 1, -1),
		[take.tape]
	)
	assert_eq(S.events_of(take_b.events, SimEventType.KILL, -1, "t1").size(), 1)
	var res: Resolution = S.resolve(level, [take.tape, take_b.tape])
	assert_eq(S.events_of(res.events, SimEventType.KILL, -1, "t1").size(), 1)
	assert_eq(S.events_of(res.events, SimEventType.SELF_DEATH).size(), 0)
	assert_eq(_tapes(S.events_of(res.events, SimEventType.KILL, -1, "g1")), [0])
	assert_eq(S.events_of(res.events, SimEventType.INTERACT, -1, "lever").size(), 1)
	assert_eq(S.events_of(res.events, SimEventType.DESYNC).size(), 0)
	var last: FrameSnapshot = res.frames[res.frames.size() - 1]
	assert_true(last.mech("gate").on)
	assert_true(res.outcome.win)
	assert_eq(res.outcome.survivors, [0, 1])

# ───────────────────────────── a clean take killed at a new time (TEST-12, Scenario D) ─────────────────────────────


## Scenario D room:
##
##          0         1
##          01234567890123
##     r0   ##############
##     r1   #.....L.......#    L lamp switch (6.5, 1.5)
##     r2   #.G...........#    G gate switch (2.5, 2.5)
##     r3   #.......######
##     r4   #.@.....D...T#     @ start (2.5, 4.5); D door "door" (8, 4); T turret (12.5, 4.5)
##     r5   #.......######
##     r6   #.............#
##     r7   ##############
func _scenario_d() -> LevelDef:
	var ents: Array[EntityDef] = [
		S.switch_def("gate", 2.5, 2.5),
		S.switch_def("lamp", 6.5, 1.5),
		S.door("door", [Vector2i(8, 4)], SignalExpr.of_sig("gate")),
		S.enemy("t1", EnemyType.TURRET, 12.5, 4.5, {"facing": PI}),
	]
	var map: Array[String] = [
		"##############",
		"#............#",
		"#............#",
		"#.......######",
		"#............#",
		"#.......######",
		"#............#",
		"##############",
	]
	return TestLevels.make_level(
		{
			"speeds": [1.0],
			"bars": 4,
			"map": map,
			"start": Vector2(2.5, 4.5),
			"entities": ents,
			"objective": S.objective(ObjectiveType.SIGNAL, "Open the gate", [], SignalExpr.of_sig("gate")),
		}
	)


## Tape A: walks into the corridor in front of the door, waits, then goes to flip the lamp.
func _tape_a_d() -> ODTape:
	return S.path_tape(0, 1.0, 480, [[0, 2.5, 4.5], [60, 6.0, 4.5], [440, 6.0, 4.5], [460, 6.3, 2.3]], [[470, ActionKind.INTERACT]])


## Tape B: steps up to the gate switch late and opens the door, exposing A's corridor.
func _tape_b_d() -> ODTape:
	return S.path_tape(1, 1.0, 480, [[0, 2.5, 4.5], [30, 2.5, 3.0]], [[300, ActionKind.INTERACT]])


func test_ScenarioD_alone_tape_A_survives_and_lights_the_lamp() -> void:
	var solo: Resolution = S.resolve(_scenario_d(), [_tape_a_d()])
	assert_eq(S.events_of(solo.events, SimEventType.SELF_DEATH).size(), 0)
	assert_eq(_details(S.events_of(solo.events, SimEventType.INTERACT, -1, "lamp")), ["on"])


func test_TEST12_ScenarioD_with_B_opening_the_door_A_dies_late_keeps_moving_as_a_ghost_and_its_later_switch_does_not_count() -> void:
	var level: LevelDef = _scenario_d()
	var solo: Resolution = S.resolve(level, [_tape_a_d()])
	var res: Resolution = S.resolve(level, [_tape_a_d(), _tape_b_d()])
	var deaths: Array[SimEvent] = S.events_of(res.events, SimEventType.SELF_DEATH, 0)
	assert_eq(deaths.size(), 1, "never killed twice")
	if deaths.size() != 1:
		return
	assert_eq(deaths[0].detail, "shot by turret t1")
	assert_true(deaths[0].sub > 300 * 4, "after B opened the door at local tick 300")
	assert_true(deaths[0].sub < 440 * 4, "while A still waited in the lane")
	# Movement continues exactly.
	var p1: Array = []
	var p2: Array = []
	for f: FrameSnapshot in res.frames:
		p1.append([f.actors[0].x, f.actors[0].y])
	for f: FrameSnapshot in solo.frames:
		p2.append([f.actors[0].x, f.actors[0].y])
	assert_eq(p1, p2)
	# The lamp interaction after death does not count.
	assert_eq(S.events_of(res.events, SimEventType.INTERACT, -1, "lamp").size(), 0)
	assert_false(res.frames[res.frames.size() - 1].mech("lamp").on)
	# The other tape carries on: B opened the gate and survives; the attempt is won by B.
	assert_eq(S.events_of(res.events, SimEventType.INTERACT, 1, "gate").size(), 1)
	assert_eq(res.outcome.survivors, [1])
	assert_true(res.outcome.win)
	assert_eq(res.frames[res.frames.size() - 1].actors[0].life, OD.LifeState.GHOST)

# ───────────────────────────── survivors (TEST-23, TEST-24) ─────────────────────────────


## Open room with an always-on laser across row 2 and a sleeping grunt to destroy.
func _survival_room() -> LevelDef:
	var ents: Array[EntityDef] = [
		S.laser("beam", Vector2(1.5, 2.5), Vector2(10.5, 2.5), SignalExpr.of_const(true)),
		S.enemy("g1", EnemyType.GRUNT, 8.0, 7.5, {"wake": SignalExpr.of_const(false)}),
	]
	return TestLevels.make_level(
		{
			"speeds": [1.0],
			"bars": 2,
			"start": Vector2(2.5, 5.5),
			"entities": ents,
			"objective": S.objective(ObjectiveType.ELIMINATE, "Destroy the grunt"),
		}
	)


func _walk_into_laser(index: int, x: float) -> ODTape:
	return S.path_tape(index, 1.0, 240, [[0, 2.5, 5.5], [40, x, 5.5], [90, x, 2.5]])


func _kill_grunt(index: int, then_die: bool) -> ODTape:
	var path: Array = [[0, 2.5, 5.5], [60, 7.0, 7.5]]
	if then_die:
		path.append([100, 7.0, 7.5])
		path.append([160, 7.0, 2.5])
	return S.path_tape(index, 1.0, 240, path, [[70, ActionKind.LIGHT, 0.0]])


func test_TEST23_three_selves_die_and_one_survivor_completes_the_objective_the_attempt_is_won() -> void:
	var res: Resolution = S.resolve(
		_survival_room(), [_walk_into_laser(0, 3.5), _walk_into_laser(1, 5.5), _walk_into_laser(2, 9.5), _kill_grunt(3, false)]
	)
	var deaths: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.SELF_DEATH):
		deaths.append([e.tape, e.detail])
	assert_eq(deaths, [[0, "burned by laser beam"], [1, "burned by laser beam"], [2, "burned by laser beam"]])
	assert_true(res.outcome.objective_complete)
	assert_eq(res.outcome.survivors, [3])
	assert_true(res.outcome.win)
	assert_eq(res.outcome.reason, &"")


func test_TEST24_the_objective_completed_with_no_survivor_is_not_a_win() -> void:
	var res: Resolution = S.resolve(_survival_room(), [_walk_into_laser(0, 3.5), _kill_grunt(1, true)])
	assert_true(res.outcome.objective_complete)
	assert_eq(res.outcome.survivors, [])
	assert_false(res.outcome.win)
	assert_eq(res.outcome.reason, FailReason.NO_SURVIVOR)
	var found: bool = false
	for n: String in res.outcome.notes:
		found = found or n.begins_with("No self survived")
	assert_true(found)
	var obj: ObjectiveSnap = res.frames[res.frames.size() - 1].objective
	assert_eq([obj.complete, obj.survivors], [true, 0])
