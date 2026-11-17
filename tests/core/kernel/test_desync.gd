extends ODTest
## Kernel: desynchronisation and the recovery spark (TEST-13..17, Scenarios I and J, DESYNC-01..08).
## Port of prototype/tests/core/kernel/desync.test.ts.
##
## Port note: ActorSnap.spark is a Vector2 (float32 in Godot), so spark-speed bounds read from
## snapshots allow 1e-5 tiles of rounding where the prototype allowed 1e-9.

const S = preload("res://tests/helpers/script.gd")
const T: int = 480
const SPARK_EPS: float = 1e-5


## Corridor with a door and (optionally) a detour above it:
##
##          0         1
##          01234567890123
##     r0   ##############
##     r1   #............#      detour corridor (solid wall when `detour` is false)
##     r2   #S##########.#      S switch "sw" (1.5, 2.5); the right-hand gap is wall when `detour` is false
##     r3   #@.....D....E#      @ start (1.5, 3.5); D door "d1" (7, 3), open unless sw is on; E exit
##     r4   ##############
func _corridor(detour: bool) -> LevelDef:
	var ents: Array[EntityDef] = [
		S.switch_def("sw", 1.5, 2.5),
		S.door("d1", [Vector2i(7, 3)], SignalExpr.of_not(SignalExpr.of_sig("sw"))),
		S.exit_def("exit", 12, 3, 1, 1),
	]
	var map: Array[String] = [
		"##############",
		"#............#" if detour else "##############",
		"#.##########.#" if detour else "#.############",
		"#............#",
		"##############",
	]
	return TestLevels.make_level(
		{
			"speeds": [1.0],
			"bars": 4,
			"map": map,
			"start": Vector2(1.5, 3.5),
			"entities": ents,
			"objective": S.objective(ObjectiveType.REACH, "Reach the end"),
		}
	)


## Tape A walks the corridor at 3 tiles/s from the start to the far end and waits there.
func _runner() -> ODTape:
	return S.path_tape(0, 1.0, T, [[0, 1.5, 3.5], [220, 12.5, 3.5]])


## Tape B flips the switch at local tick `close_at` (and again at `reopen_at`, if given).
func _switcher(close_at: int, reopen_at: int = -1) -> ODTape:
	var evs: Array = [[close_at, ActionKind.INTERACT]]
	if reopen_at >= 0:
		evs.append([reopen_at, ActionKind.INTERACT])
	return S.path_tape(1, 1.0, T, [[0, 1.5, 3.5]], evs)


func _spark_track(res: Resolution, tape: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for f: FrameSnapshot in res.frames:
		var a: ActorSnap = f.actor(tape)
		if a.has_spark:
			out.append(Vector3(f.sub, a.spark.x, a.spark.y))
	return out


func _xy0(r: Resolution) -> Array:
	var out: Array = []
	for f: FrameSnapshot in r.frames:
		out.append([f.actors[0].x, f.actors[0].y])
	return out


func _has_note(r: Resolution, pattern: String) -> bool:
	var re := RegEx.create_from_string(pattern)
	for n: String in r.outcome.notes:
		if re.search(n) != null:
			return true
	return false

# ───────────────────────────── desync on obstruction (TEST-13, TEST-14, Scenario I) ─────────────────────────────


func test_TEST13_a_door_closed_across_a_living_tape_desyncs_it_its_projection_keeps_the_recording() -> void:
	var level: LevelDef = _corridor(true)
	var solo: Resolution = S.resolve(level, [_runner()])
	assert_eq(S.events_of(solo.events, SimEventType.DESYNC).size(), 0)
	var res: Resolution = S.resolve(level, [_runner(), _switcher(5)])
	var desyncs: Array[SimEvent] = S.events_of(res.events, SimEventType.DESYNC, 0)
	assert_eq(desyncs.size(), 1)
	if desyncs.is_empty():
		return
	assert_eq(desyncs[0].detail, "blocked by door d1")
	# DESYNC-01: the projection follows its exact recorded performance.
	assert_eq(_xy0(res), _xy0(solo))
	# While desynced the self is shown with a spark and is not synced.
	var during: ActorSnap = TestScript.frame_at(res, desyncs[0].sub + 9).actors[0]
	assert_false(during.synced)
	assert_true(during.has_spark)
	assert_eq(during.life, OD.LifeState.ALIVE)


func test_TEST14_ScenarioI_the_spark_takes_the_open_detour_at_finite_speed_and_resyncs_on_catch_up() -> void:
	var level: LevelDef = _corridor(true)
	var res: Resolution = S.resolve(level, [_runner(), _switcher(5)])
	var d: SimEvent = S.events_of(res.events, SimEventType.DESYNC, 0)[0]
	var r: Array[SimEvent] = S.events_of(res.events, SimEventType.RESYNC, 0)
	assert_eq(r.size(), 1)
	if r.is_empty():
		return
	var track: Array[Vector3] = _spark_track(res, 0)
	# Finite speed: never more than spark_speed per master second between frames.
	var max_step: float = (Tuning.BASE.spark_speed / OD.SUB_HZ) * 4 + SPARK_EPS
	for i: int in range(1, track.size()):
		var step: float = Vector2(track[i].y - track[i - 1].y, track[i].z - track[i - 1].z).length()
		if not assert_true(step <= max_step, "spark step %f at sub %d" % [step, int(track[i].x)]):
			break
	# It really went round: the detour row (y < 2) was visited.
	var went_round: bool = false
	for p: Vector3 in track:
		went_round = went_round or p.z < 2
	assert_true(went_round)
	# No instant overlap-only recovery: the projection is clear of the door long before the resync.
	var clear_of_door: int = -1
	for f: FrameSnapshot in res.frames:
		if f.actors[0].x > 8.5:
			clear_of_door = f.sub
			break
	assert_true(r[0].sub > clear_of_door + 0.5 * OD.SUB_HZ)
	# The detour is ~20 tiles: the spark cannot have made it faster than its speed allows.
	assert_true(float(r[0].sub - d.sub) / OD.SUB_HZ > 18.0 / Tuning.BASE.spark_speed)
	var end: ActorSnap = res.frames[res.frames.size() - 1].actors[0]
	assert_true(end.synced)
	assert_false(end.has_spark)
	assert_true(_has_note(res, "Tape A desynced at beat [\\d.]+ \\(blocked by door d1\\); its spark caught up at beat"), "notes: %s" % [res.outcome.notes])
	assert_true(res.outcome.win)


func test_ScenarioI_reopening_the_direct_route_lets_the_spark_catch_up_sooner_than_the_detour() -> void:
	var level: LevelDef = _corridor(true)
	var detour_only: int = S.events_of(S.resolve(level, [_runner(), _switcher(5)]).events, SimEventType.RESYNC, 0)[0].sub
	var reopened: int = S.events_of(S.resolve(level, [_runner(), _switcher(5, 150)]).events, SimEventType.RESYNC, 0)[0].sub
	assert_true(reopened < detour_only, "reopened %d vs detour %d" % [reopened, detour_only])

# ───────────────────────────── blocked recovery (TEST-15, DESYNC-03) ─────────────────────────────


func test_DESYNC03_with_no_route_the_spark_never_catches_up_and_nothing_teleports_or_kills_it() -> void:
	var level: LevelDef = _corridor(false)
	var res: Resolution = S.resolve(level, [_runner(), _switcher(5)])
	assert_eq(S.events_of(res.events, SimEventType.DESYNC, 0).size(), 1)
	assert_eq(S.events_of(res.events, SimEventType.RESYNC, 0).size(), 0)
	var end: ActorSnap = res.frames[res.frames.size() - 1].actors[0]
	assert_false(end.synced)
	assert_eq(end.life, OD.LifeState.ALIVE)
	# The spark waits on its own side of the door.
	assert_true(end.spark.x < 7)
	# Alive but desynced: a survivor that cannot hold the exit.
	assert_has(res.outcome.survivors, 0)
	assert_false(res.outcome.objective_complete)
	assert_true(_has_note(res, "its spark never caught up"))
	assert_true(_has_note(res, "ended the run desynced"))


func test_TEST15_another_tape_reopening_the_blocked_route_lets_the_spark_recover() -> void:
	var level: LevelDef = _corridor(false)
	var res: Resolution = S.resolve(level, [_runner(), _switcher(5, 300)])
	var reopen: Array[SimEvent] = []
	for e: SimEvent in S.events_of(res.events, SimEventType.DOOR, -1, "d1"):
		if e.detail == "open":
			reopen.append(e)
	assert_eq(reopen.size(), 1)
	var r: Array[SimEvent] = S.events_of(res.events, SimEventType.RESYNC, 0)
	assert_eq(r.size(), 1)
	if r.size() == 1 and reopen.size() == 1:
		assert_true(r[0].sub > reopen[0].sub)
	assert_true(res.frames[res.frames.size() - 1].actors[0].synced)
	assert_true(res.outcome.win)

# ───────────────────────────── desynced selves are harmless and invulnerable (TEST-16) ─────────────────────────────


## Open room; a low barrier at (6, 5) that tape A's recording stands on.
func _barrier_level(with_barrier: bool, with_turret: bool) -> LevelDef:
	var ents: Array[EntityDef] = []
	if with_turret:
		ents.append(S.enemy("t1", EnemyType.TURRET, 10.5, 5.5, {"facing": PI}))
	ents.append(S.enemy("g1", EnemyType.GRUNT, 7.4, 6.3, {"wake": SignalExpr.of_const(false)}))
	var map: Array[String] = [
		"############",
		"#..........#",
		"#..........#",
		"#..........#",
		"#..........#",
		"#.....=....#" if with_barrier else "#..........#",
		"#..........#",
		"#..........#",
		"#..........#",
		"############",
	]
	var targets: Array[String] = ["g1"]
	return TestLevels.make_level(
		{
			"speeds": [1.0],
			"bars": 2,
			"map": map,
			"start": Vector2(2.5, 5.5),
			"entities": ents,
			"objective": S.objective(ObjectiveType.ELIMINATE, "Destroy the grunt", targets),
		}
	)


## A walks onto the low barrier (impossible in this world: desync) and swings at the grunt from there.
func _tape_a16() -> ODTape:
	return S.path_tape(0, 1.0, 240, [[0, 2.5, 5.5], [40, 6.5, 5.5]], [[120, ActionKind.LIGHT, atan2(0.8, 0.9)]])


## C stands still at the start, behind A in the turret's lane.
func _tape_c16() -> ODTape:
	return S.path_tape(2, 1.0, 240, [[0, 2.5, 5.5]])


func test_TEST16_a_desynced_swing_deals_no_damage_and_a_bolt_passes_through_the_desynced_projection() -> void:
	var res: Resolution = S.resolve(_barrier_level(true, true), [_tape_a16(), _tape_c16()])
	assert_eq(S.events_of(res.events, SimEventType.DESYNC, 0).size(), 1)
	assert_eq(S.events_of(res.events, SimEventType.RESYNC, 0).size(), 0)
	assert_eq(S.events_of(res.events, SimEventType.HIT).size(), 0)
	assert_eq(S.events_of(res.events, SimEventType.KILL).size(), 0)
	# The turret ignores A and shoots C straight through A's projection.
	var shots: Array[SimEvent] = S.events_of(res.events, SimEventType.ENEMY_SHOT, -1, "t1")
	assert_true(shots.size() > 0)
	for s: SimEvent in shots:
		assert_eq(s.tape, 2)
	var deaths: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.SELF_DEATH):
		deaths.append(e.tape)
	assert_eq(deaths, [2])
	var end: FrameSnapshot = res.frames[res.frames.size() - 1]
	assert_eq([end.actors[0].life, end.actors[0].synced], [OD.LifeState.ALIVE, false])
	assert_true(end.enemy("g1").alive)


func test_TEST16_control_the_same_swing_synced_destroys_the_grunt() -> void:
	var res: Resolution = S.resolve(_barrier_level(false, false), [_tape_a16()])
	assert_eq(S.events_of(res.events, SimEventType.DESYNC).size(), 0)
	var kills: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.KILL, -1, "g1"):
		kills.append(e.tape)
	assert_eq(kills, [0])

# ───────────────────────────── the wall-and-turret case (TEST-17, Scenario J) ─────────────────────────────


## The wall-and-turret teaching case (Scenario J):
##
##          0         1
##          0123456789012345
##     r0   ################
##     r1   #S.............#     S switch "sw" (1.5, 1.5); @ start (2.5, 1.5)
##     r2   #..............#
##     r3   #####D######...#     D door "d1" (5, 3), open unless sw is on; the gap at c 12..14 is the detour
##     r4   #..............#
##     r5   #..............#     T turret t1 (8.5, 5.0), aim arc: the western half-plane
##     r6   ################
func _turret_level(detour: bool) -> LevelDef:
	var ents: Array[EntityDef] = [
		S.switch_def("sw", 1.5, 1.5),
		S.door("d1", [Vector2i(5, 3)], SignalExpr.of_not(SignalExpr.of_sig("sw"))),
		S.enemy("t1", EnemyType.TURRET, 8.5, 5.0, {"facing": PI, "arc": PI}),
	]
	var map: Array[String] = [
		"################",
		"#..............#",
		"#..............#",
		"#####.######...#" if detour else "#####.##########",
		"#..............#",
		"#..............#",
		"################",
	]
	var targets: Array[String] = ["t1"]
	return TestLevels.make_level(
		{
			"speeds": [1.0],
			"bars": 4,
			"map": map,
			"start": Vector2(2.5, 1.5),
			"entities": ents,
			"objective": S.objective(ObjectiveType.ELIMINATE, "Destroy the turret", targets),
		}
	)


## Tape A: through the door, a pause in the turret's lane, round to its rear, then a strike.
func _crosser(strike_at: int) -> ODTape:
	return S.path_tape(
		0,
		1.0,
		T,
		[[0, 2.5, 1.5], [60, 5.5, 1.5], [120, 5.5, 4.5], [130, 6.5, 4.5], [200, 6.5, 4.5], [260, 9.6, 4.4], [270, 9.6, 5.0]],
		[[strike_at, ActionKind.LIGHT, PI]]
	)


## Tape B closes the door just before A reaches it.
func _doorman() -> ODTape:
	return S.path_tape(1, 1.0, T, [[0, 2.5, 1.5]], [[5, ActionKind.INTERACT]])


func test_TEST17_without_desync_the_turret_kills_the_crossing_tape_in_its_lane() -> void:
	var res: Resolution = S.resolve(_turret_level(true), [_crosser(400)])
	var details: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.SELF_DEATH, 0):
		details.append(e.detail)
	assert_eq(details, ["shot by turret t1"])
	assert_eq(S.events_of(res.events, SimEventType.KILL).size(), 0)
	assert_false(res.outcome.win)


func test_ScenarioJ_desync_protects_the_crossing_the_spark_detours_the_tape_resyncs_behind_the_turret_and_breaks_it() -> void:
	var res: Resolution = S.resolve(_turret_level(true), [_crosser(400), _doorman()])
	var d: Array[SimEvent] = S.events_of(res.events, SimEventType.DESYNC, 0)
	var r: Array[SimEvent] = S.events_of(res.events, SimEventType.RESYNC, 0)
	assert_eq(d.size(), 1)
	assert_eq(r.size(), 1)
	if d.size() != 1 or r.size() != 1:
		return
	assert_eq(S.events_of(res.events, SimEventType.SELF_DEATH).size(), 0)
	# Not one shot was fired at the desynced projection.
	var at_a: int = 0
	for e: SimEvent in S.events_of(res.events, SimEventType.ENEMY_SHOT):
		if e.tape == 0 and e.sub > d[0].sub and e.sub < r[0].sub:
			at_a += 1
	assert_eq(at_a, 0)
	# The resync happened before the strike, and the strike destroyed the turret.
	var kill: Array[SimEvent] = S.events_of(res.events, SimEventType.KILL, -1, "t1")
	var tapes: Array = []
	for e: SimEvent in kill:
		tapes.append(e.tape)
	assert_eq(tapes, [0])
	if kill.size() == 1:
		assert_true(r[0].sub < kill[0].sub)
	assert_true(res.outcome.win)


func test_TEST17_if_the_spark_has_not_caught_up_the_desynced_strike_cannot_hurt_the_turret() -> void:
	var res: Resolution = S.resolve(_turret_level(false), [_crosser(400), _doorman()])
	assert_eq(S.events_of(res.events, SimEventType.DESYNC, 0).size(), 1)
	assert_eq(S.events_of(res.events, SimEventType.RESYNC, 0).size(), 0)
	assert_eq(S.events_of(res.events, SimEventType.KILL).size(), 0)
	assert_eq(S.events_of(res.events, SimEventType.SELF_DEATH, 0).size(), 0)
	assert_false(res.outcome.objective_complete)
	assert_eq(res.outcome.survivors, [0, 1])

# ───────────────────────────── repeat cuts and the spark ─────────────────────────────


func test_a_repeat_cut_teleports_the_projection_but_the_spark_has_to_travel() -> void:
	var level: LevelDef = _corridor(false)
	# A 2x repeat runner: it desyncs at the closed door, then its projection cuts back to the start.
	var fast: ODTape = S.path_tape(0, 2.0, T, [[0, 1.5, 3.5], [220, 12.5, 3.5]], [], OD.EndMode.REPEAT)
	var res: Resolution = S.resolve(level, [fast, _switcher(2)])
	var cut: int = T * 2
	var wraps: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.TAPE_WRAP, 0):
		wraps.append(e.sub + 1)
	assert_has(wraps, cut)
	var before: ActorSnap = S.frame_exact(res.frames, cut - 4).actors[0]
	var after: ActorSnap = S.frame_exact(res.frames, cut).actors[0]
	assert_false(before.synced)
	assert_eq(after.x, 1.5, "the projection is back at the start")
	# The spark did not jump with it: it moved at most its speed in those 4 substeps.
	assert_true(
		(after.spark - before.spark).length() <= (Tuning.BASE.spark_speed / OD.SUB_HZ) * 4 + SPARK_EPS,
		"spark moved %f" % (after.spark - before.spark).length()
	)
	# It then walks back along the corridor and resyncs with the new traversal.
	var r: Array[SimEvent] = S.events_of(res.events, SimEventType.RESYNC, 0)
	assert_true(r.size() > 0)
	if not r.is_empty():
		assert_true(r[0].sub > cut)
