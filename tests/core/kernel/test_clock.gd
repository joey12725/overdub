extends ODTest
## Kernel: one clock, recording vs playback, take management and determinism
## (TEST-01..06, full determinism, record -> resolve reproduction).
## Port of prototype/tests/core/kernel/clock.test.ts.

const S = preload("res://tests/helpers/script.gd")


func _busy_level() -> LevelDef:
	var ents: Array[EntityDef] = [
		S.enemy("g1", EnemyType.GRUNT, 9.5, 2.5),
		S.enemy("t1", EnemyType.TURRET, 10.5, 8.5, {"facing": PI}),
		S.switch_def("sw", 4.5, 2.5),
		S.door("d1", [Vector2i(7, 5)], SignalExpr.of_sig("sw")),
		S.plate("p1", 5, 7),
	]
	return TestLevels.make_level({"speeds": [0.5, 1.0, 2.0], "bars": 2, "start": Vector2(2.5, 5.5), "entities": ents})


func _busy_script() -> TestScript.InputScript:
	return (
		S.input_script()
		.run(0, 25, 0.6, -1)
		.press(26, ActionKind.INTERACT)
		.run(30, 70, 1, 0.3)
		.press(72, ActionKind.LIGHT, 0.0)
		.run(80, 110, -0.4, 1)
		.press(112, ActionKind.DODGE)
		.run(120, 160, 1, 0)
		.press(165, ActionKind.HEAVY, -0.5)
		.run(200, 240, 0, -1)
	)


func _sim(level: LevelDef, tapes: Array[ODTape], live: LiveTake) -> ODSim:
	return ODSim.create_sim(SimConfig.make(level, TestLoadout.base_loadout(), tapes, live))


func _xy(f: FrameSnapshot, i: int = 0) -> Array:
	return [f.actors[i].x, f.actors[i].y]


# ───────────────────────────── clock (TEST-01, TEST-02) ─────────────────────────────


func test_TEST01_the_recording_allowance_is_the_same_at_every_speed_the_world_advances_1_over_s_as_far() -> void:
	var level: LevelDef = TestLevels.make_level({"speeds": [0.5, 1.0, 2.0, 4.0], "bars": 1})
	var results: Array[Dictionary] = []
	for speed: float in [0.5, 1.0, 2.0, 4.0]:
		var take: TestScript.TakeResult = S.record_take(level, 0, speed, S.input_script().run(0, 1000, 1, 0))
		results.append(
			{"speed": speed, "ticks": take.sim.local_tick, "sub": take.sim.sub, "done": take.sim.done, "tape_ticks": take.tape.ticks}
		)
	var t: int = results[0]["ticks"]
	assert_eq(t, 120)
	for r: Dictionary in results:
		assert_eq(r["ticks"], t)
		assert_eq(r["tape_ticks"], t)
		assert_true(r["done"])
		assert_eq(r["sub"], t * OD.subs_per_local_tick(r["speed"]))
	# A 2x take sees half as much world as a 1x take; a 0.5x take twice as much (TIME-03).
	assert_eq(int(results[2]["sub"]) * 2, results[1]["sub"])
	assert_eq(results[0]["sub"], int(results[1]["sub"]) * 2)


func test_TEST02_a_2x_take_lands_on_a_plate_at_the_same_master_substep_in_recording_and_in_true_speed_replay() -> void:
	var ents: Array[EntityDef] = [S.plate("p1", 7, 5)]
	var level: LevelDef = TestLevels.make_level(
		{
			"speeds": [1.0, 2.0],
			"bars": 1,
			"start": Vector2(2.5, 5.5),
			"entities": ents,
			"objective": S.objective(ObjectiveType.SIGNAL, "Stand on the plate", [], SignalExpr.of_sig("p1")),
		}
	)
	var take: TestScript.TakeResult = S.record_take(level, 0, 2.0, S.input_script().run(0, 1000, 1, 0))
	var rec_plate: Array = []
	for e: SimEvent in S.events_of(take.events, SimEventType.PLATE):
		rec_plate.append([e.sub, e.detail])
	assert_true(rec_plate.size() > 0)
	var res: Resolution = S.resolve(level, [take.tape])
	var rep_plate: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.PLATE):
		rep_plate.append([e.sub, e.detail])
	assert_eq(rep_plate, rec_plate)
	# Every recorded frame is reproduced exactly at the same master substep.
	var compared: int = 0
	for f: FrameSnapshot in take.frames:
		var g: FrameSnapshot = S.frame_exact(res.frames, f.sub)
		if g == null:
			continue
		assert_eq(_xy(g), _xy(f))
		compared += 1
	assert_true(compared > 50, "compared %d frames" % compared)
	assert_true(res.outcome.objective_complete)


# ───────────────────────────── takes (TEST-03..06) ─────────────────────────────


func test_TEST03_the_next_take_starts_at_beat_zero_with_the_earlier_tape_at_its_start() -> void:
	var level: LevelDef = _busy_level()
	var first: TestScript.TakeResult = S.record_take(level, 0, 1.0, _busy_script())
	var sim: ODSim = _sim(level, [first.tape], LiveTake.make(1, 2.0, OD.EndMode.STOP))
	var snap: FrameSnapshot = sim.snapshot()
	assert_eq(snap.sub, 0)
	assert_eq(snap.beat, 0.0)
	var a: ActorSnap = snap.actor(0)
	assert_eq(a.phase.tick, 0.0)
	# level.start is a Vector2 (float32), i.e. Math.fround of the prototype's start.
	assert_eq([a.x, a.y], [level.start.x, level.start.y])
	# The world is reconstructed from its initial state (the grunt is back where it started).
	var g: EnemySnap = snap.enemy("g1")
	assert_eq([g.x, g.y, g.alive], [9.5, 2.5, true])


func test_TEST04_earlier_tapes_are_simulated_while_recording_unrecorded_cassettes_do_not_appear() -> void:
	var level: LevelDef = _busy_level()
	var first: TestScript.TakeResult = S.record_take(level, 0, 1.0, _busy_script())
	var sim: ODSim = _sim(level, [first.tape], LiveTake.make(1, 1.0, OD.EndMode.STOP))
	var sc: TestScript.InputScript = _busy_script()
	for t: int in 40:
		sim.step_local_tick(sc.input(t))
	var snap: FrameSnapshot = sim.snapshot()
	var who: Array = []
	for a: ActorSnap in snap.actors:
		who.append([a.tape, a.live])
	assert_eq(who, [[0, false], [1, true]])
	# Tape A is where its own recording put it at this master substep.
	var fa: FrameSnapshot = S.frame_exact(first.frames, snap.sub)
	assert_eq(_xy(snap), _xy(fa))


func test_TEST05_retrying_a_take_replaces_it_and_leaves_the_committed_tape_untouched() -> void:
	var level: LevelDef = _busy_level()
	var first: TestScript.TakeResult = S.record_take(level, 0, 1.0, _busy_script())
	var take_b1: TestScript.TakeResult = S.record_take(
		level, 1, 1.0, S.input_script().run(0, 30, 1, -0.5).press(40, ActionKind.INTERACT), [first.tape]
	)
	var take_b2: TestScript.TakeResult = S.record_take(level, 1, 1.0, S.input_script().run(0, 30, 0, 1), [first.tape])
	var r1: Resolution = S.resolve(level, [first.tape, take_b1.tape])
	var r2: Resolution = S.resolve(level, [first.tape, take_b2.tape])
	var path1: Array = []
	var path2: Array = []
	for f: FrameSnapshot in r1.frames:
		path1.append(_xy(f))
	for f: FrameSnapshot in r2.frames:
		path2.append(_xy(f))
	assert_eq(path2, path1)
	# Nothing of the discarded take survives in the new run: only tape B2 plays as cassette B.
	var tapes: Array = []
	for a: ActorSnap in r2.frames[0].actors:
		tapes.append(a.tape)
	assert_eq(tapes, [0, 1])
	assert_eq(S.events_of(r2.events, SimEventType.INTERACT, 1).size(), 0)


func test_TEST06_after_a_reset_the_encounter_contains_no_earlier_cassette_at_all() -> void:
	var level: LevelDef = _busy_level()
	var sim: ODSim = _sim(level, [], LiveTake.make(0, 1.0, OD.EndMode.STOP))
	assert_eq(sim.snapshot().actors.size(), 1)
	assert_eq(sim.snapshot().actors[0].tape, 0)
	var res: Resolution = ODResolve.resolve_encounter(SimConfig.make(level, TestLoadout.base_loadout(), []))
	var all_empty: bool = true
	for f: FrameSnapshot in res.frames:
		all_empty = all_empty and f.actors.is_empty()
	assert_true(all_empty)
	# Frames: substep 0, every FRAME_SUBS, and the final substep.
	assert_eq(res.frames[0].sub, 0)
	assert_eq(res.frames[res.frames.size() - 1].sub, res.horizon_subs)
	@warning_ignore("integer_division")
	assert_eq(res.frames.size(), res.horizon_subs / 4 + 1)
	var spaced: bool = true
	for i: int in res.frames.size():
		spaced = spaced and res.frames[i].sub == i * 4
	assert_true(spaced)
	assert_eq(res.outcome.survivors, [])

# ───────────────────────────── determinism ─────────────────────────────


func test_two_sims_with_the_same_config_and_inputs_produce_deep_equal_snapshots_at_every_step() -> void:
	var level: LevelDef = _busy_level()
	var tape_a: ODTape = S.record_take(level, 0, 2.0, _busy_script()).tape
	var s1: ODSim = _sim(level, [tape_a], LiveTake.make(1, 1.0, OD.EndMode.REVERSE))
	var s2: ODSim = _sim(level, [tape_a], LiveTake.make(1, 1.0, OD.EndMode.REVERSE))
	var sc: TestScript.InputScript = _busy_script()
	assert_json_eq(s2.snapshot().to_dict(), s1.snapshot().to_dict())
	var ok: bool = true
	for t: int in s1.tape_ticks:
		s1.step_local_tick(sc.input(t))
		s2.step_local_tick(sc.input(t))
		ok = ODJson.deep_equal(s2.snapshot().to_dict(), s1.snapshot().to_dict(), 0.0) and ok
		ok = ODJson.deep_equal(S.dicts(s2.drain_events()), S.dicts(s1.drain_events()), 0.0) and ok
		if not ok:
			fail("diverged at local tick %d" % t)
			break
	assert_true(ok)
	assert_true(TapeLib.tapes_equal(s2.live_tape(), s1.live_tape()))
	var r1: Resolution = S.resolve(level, [tape_a, s1.live_tape()])
	var r2: Resolution = S.resolve(level, [tape_a, s2.live_tape()])
	assert_json_eq(r2.to_dict(), r1.to_dict())


func test_snapshots_are_plain_data_that_later_steps_never_mutate() -> void:
	var sim: ODSim = _sim(_busy_level(), [], LiveTake.make(0, 1.0, OD.EndMode.STOP))
	var sc: TestScript.InputScript = _busy_script()
	for t: int in 30:
		sim.step_local_tick(sc.input(t))
	var snap: FrameSnapshot = sim.snapshot()
	var before: Dictionary = snap.to_dict()
	for t: int in range(30, 120):
		sim.step_local_tick(sc.input(t))
	assert_json_eq(snap.to_dict(), before)


func test_recording_a_take_and_resolving_it_reproduces_the_same_positions_kills_and_deaths() -> void:
	var level: LevelDef = _busy_level()
	var take: TestScript.TakeResult = S.record_take(level, 0, 1.0, _busy_script())
	var res: Resolution = S.resolve(level, [take.tape])
	# The busy script walks into the turret's lane and dies part-way: the comparison covers both the
	# alive part (everything identical) and the ghost part (positions identical; the recording
	# ghost's provisional effects are allowed to differ, Scenario C).
	var death: Array[SimEvent] = S.events_of(take.events, SimEventType.SELF_DEATH)
	assert_eq(death.size(), 1)
	if death.size() != 1:
		return
	var death_sub: int = death[0].sub
	var compared: int = 0
	for f: FrameSnapshot in take.frames:
		var g: FrameSnapshot = S.frame_exact(res.frames, f.sub)
		if g == null:
			continue
		if not assert_json_eq(S.dicts(g.actors), S.actors_as_playback(f), 0.0, "actors at sub %d" % f.sub):
			break
		if f.sub <= death_sub:
			assert_json_eq(S.dicts(g.enemies), S.dicts(f.enemies), 0.0, "enemies at sub %d" % f.sub)
			assert_json_eq(S.dicts(g.mechs), S.dicts(f.mechs), 0.0, "mechs at sub %d" % f.sub)
			assert_json_eq(S.dicts(g.projectiles), S.dicts(f.projectiles), 0.0, "projectiles at sub %d" % f.sub)
		compared += 1
	assert_eq(compared, take.frames.size())
	for type: StringName in [
		SimEventType.KILL,
		SimEventType.SELF_DEATH,
		SimEventType.INTERACT,
		SimEventType.DOOR,
		SimEventType.ENEMY_SHOT,
		SimEventType.HIT,
		SimEventType.SWING
	]:
		assert_eq(_keys(res.events, type, death_sub), _keys(take.events, type, death_sub), "event type %s" % type)


func _keys(events: Array[SimEvent], type: StringName, until: int) -> Array:
	var out: Array = []
	for e: SimEvent in S.events_of(events, type):
		if e.sub <= until:
			out.append("%d:%s:%s:%s" % [e.sub, e.type, e.id, str(e.tape) if e.tape >= 0 else ""])
	return out


func test_a_take_that_survives_is_reproduced_exactly_kills_included() -> void:
	var ents: Array[EntityDef] = [
		S.enemy("g1", EnemyType.GRUNT, 6.5, 5.5),
		S.switch_def("sw", 3.5, 4.5),
		S.door("d1", [Vector2i(9, 5)], SignalExpr.of_sig("sw")),
	]
	var calm: LevelDef = TestLevels.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(2.5, 5.5), "entities": ents})
	# Wait for the grunt to walk in, then strike it as it arrives (1x standing light kills a grunt).
	var sc: TestScript.InputScript = (
		S.input_script().press(2, ActionKind.INTERACT).aim(0, 400, 0).press(80, ActionKind.LIGHT, 0.0).run(120, 160, 1, 0)
	)
	var take: TestScript.TakeResult = S.record_take(calm, 0, 1.0, sc)
	assert_eq(S.events_of(take.events, SimEventType.KILL).size(), 1)
	assert_eq(S.events_of(take.events, SimEventType.SELF_DEATH).size(), 0)
	var res: Resolution = S.resolve(calm, [take.tape])
	for f: FrameSnapshot in take.frames:
		var g: FrameSnapshot = S.frame_exact(res.frames, f.sub)
		var ok: bool = assert_json_eq(S.dicts(g.actors), S.actors_as_playback(f), 0.0, "actors at %d" % f.sub)
		ok = assert_json_eq(S.dicts(g.enemies), S.dicts(f.enemies), 0.0, "enemies at %d" % f.sub) and ok
		ok = assert_json_eq(S.dicts(g.mechs), S.dicts(f.mechs), 0.0, "mechs at %d" % f.sub) and ok
		if not ok:
			break
	assert_eq(_kill_rows(res.events), _kill_rows(take.events))
	assert_true(res.outcome.win)


func _kill_rows(events: Array[SimEvent]) -> Array:
	var out: Array = []
	for e: SimEvent in S.events_of(events, SimEventType.KILL):
		out.append([e.sub, e.id, e.tape])
	return out


func test_build_boss_memory_samples_each_committed_tape_once_per_master_beat() -> void:
	var level: LevelDef = _busy_level()
	var take: TestScript.TakeResult = S.record_take(level, 2, 2.0, _busy_script(), [], null, OD.EndMode.REPEAT)
	var committed: Array[ODTape] = [take.tape]
	var mem: BossMemory = ODCore.build_boss_memory(level, committed)
	assert_eq(mem.observed.size(), 1)
	assert_eq(mem.observed[0].tape, 2)
	var beats: int = level.horizon_bars * 4
	assert_eq(mem.observed[0].samples.size(), beats + 1)
	var s0: BossSample = mem.observed[0].samples[0]
	assert_eq([s0.beat, s0.x, s0.y], [0, level.start.x, level.start.y])
