extends ODTest
## Kernel: end-of-tape behaviour against a world that keeps going (TEST-25, TEST-26, PLAY-05/06).
## Port of prototype/tests/core/kernel/tapemodes.test.ts.

const S = preload("res://tests/helpers/script.gd")
## Master substeps per traversal of a 2x tape of 120 ticks.
const TRAV: int = 120 * 2


## 1 bar of recording, horizon 2 bars: a 2x tape traverses four times (Scenario G).
func _level() -> LevelDef:
	var ents: Array[EntityDef] = [
		S.switch_def("sw", 5.5, 1.5),
		# Never fires inside the horizon; four hit points so it can take more than one swing.
		S.enemy("t1", EnemyType.TURRET, 6.8, 2.5, {"hp": 4, "beat": [1000, 999]}),
	]
	return TestLevels.make_level({"speeds": [0.5, 1.0, 2.0], "bars": 1, "start": Vector2(2.5, 5.5), "entities": ents})


func _short_tape(end_mode: int) -> ODTape:
	return S.path_tape(
		0, 2.0, 120, [[0, 2.5, 5.5], [60, 5.5, 2.5]], [[70, ActionKind.INTERACT], [80, ActionKind.LIGHT, 0.0]], end_mode
	)


func _details(evs: Array[SimEvent]) -> Array:
	var out: Array = []
	for e: SimEvent in evs:
		out.append(e.detail)
	return out


func _actor_at(res: Resolution, sub: int) -> ActorSnap:
	return S.frame_exact(res.frames, sub).actors[0]


func test_TEST25_repeat_cuts_straight_back_to_its_start_and_plays_again_the_encounter_is_not_reset() -> void:
	var res: Resolution = S.resolve(_level(), [_short_tape(OD.EndMode.REPEAT)])
	assert_eq(res.horizon_subs, 4 * TRAV)
	var wraps: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.TAPE_WRAP, 0):
		wraps.append(e.sub + 1)
	assert_eq(wraps, [TRAV, 2 * TRAV, 3 * TRAV])
	for k: int in range(1, 4):
		assert_near(_actor_at(res, k * TRAV - 4).x, 5.5, 1e-5, "just before the cut: at the far end")
		var cut: ActorSnap = _actor_at(res, k * TRAV)
		assert_eq([cut.x, cut.y], [2.5, 5.5], "cut, not a walk back")
		assert_eq(cut.phase.traversal, k)
	# Every traversal's events fire again against the current world: the switch toggles each time.
	assert_eq(_details(S.events_of(res.events, SimEventType.INTERACT, -1, "sw")), ["on", "off", "on", "off"])
	# The turret is not revived between traversals: 2 + 2 damage kills it on the second pass, and
	# the later passes' swings find nothing.
	assert_eq(S.events_of(res.events, SimEventType.HIT, -1, "t1").size(), 2)
	assert_eq(S.events_of(res.events, SimEventType.KILL, -1, "t1").size(), 1)
	assert_eq(S.events_of(res.events, SimEventType.WHIFF, 0).size(), 2)
	assert_false(res.frames[res.frames.size() - 1].enemies[0].alive)


func test_TEST26_reverse_runs_recorded_actions_backward_while_the_world_keeps_evolving_forward() -> void:
	var res: Resolution = S.resolve(_level(), [_short_tape(OD.EndMode.REVERSE)])
	var turns: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.TAPE_TURN, 0):
		turns.append([e.sub + 1, e.detail])
	assert_eq(turns, [[TRAV, "backward"], [2 * TRAV, "forward"], [3 * TRAV, "backward"]])
	# The backward pass retraces the path: mirrored around the turn.
	var d: int = 4
	while d <= TRAV:
		var a: ActorSnap = _actor_at(res, TRAV - d)
		var b: ActorSnap = _actor_at(res, TRAV + d)
		if not (assert_near(b.x, a.x, 1e-5) and assert_near(b.y, a.y, 1e-5)):
			break
		d += 4
	assert_eq(_actor_at(res, TRAV + 4).phase.dir, -1)
	# The switch is moved back on the backward pass (on -> off), then on again, then off again.
	var toggles: Array[SimEvent] = S.events_of(res.events, SimEventType.INTERACT, -1, "sw")
	assert_eq(_details(toggles), ["on", "off", "on", "off"])
	# The backward crossing of tick 70 happens (120 - 70) local ticks after the turn.
	assert_eq(toggles[1].sub, TRAV + 50 * 2)
	# A backward swing is a fresh swing: it hurts again (it never heals).
	var hits: Array[SimEvent] = S.events_of(res.events, SimEventType.HIT, -1, "t1")
	assert_eq(hits.size(), 2)
	assert_true(hits[1].sub > TRAV)
	assert_eq(S.events_of(res.events, SimEventType.KILL, -1, "t1").size(), 1)


func test_a_stop_tape_holds_its_final_pose_and_stays_a_physical_living_survivor() -> void:
	var r: Resolution = S.resolve(_level(), [_short_tape(OD.EndMode.STOP)])
	var ends: Array = []
	for e: SimEvent in S.events_of(r.events, SimEventType.TAPE_END, 0):
		ends.append(e.sub + 1)
	assert_eq(ends, [TRAV])
	var last: ActorSnap = r.frames[r.frames.size() - 1].actors[0]
	assert_eq([last.x, last.y], [5.5, 2.5])
	assert_json_eq(last.phase.to_dict(), {"tick": 120, "dir": 0, "traversal": 1, "ended": true})
	assert_eq(S.events_of(r.events, SimEventType.INTERACT).size(), 1)
	assert_eq(r.outcome.survivors, [0])
