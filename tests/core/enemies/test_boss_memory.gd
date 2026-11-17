extends ODTest
## Boss memory (BOSS-01, BOSS-02): what build_boss_memory records from committed tapes and how
## recall_candidates reads it. bpm 120 -> 30 local ticks per beat at 1x.
## Port of prototype/tests/core/enemies/bossMemory.test.ts.

const K = preload("res://tests/core/enemies/test_enemy_kit.gd")


func _level() -> LevelDef:
	return K.make_level({"speeds": [1.0, 2.0], "bars": 1, "horizon_bars": 2, "start": Vector2(2, 2)})


func _actions(o: BossObservation) -> Array:
	var out: Array = []
	for a: BossMemoryAction in o.actions:
		out.append([a.beat, String(a.kind)])
	return out


func test_BOSS01_is_the_module_the_core_index_exports() -> void:
	var t := K.path_tape(0, 1.0, 120, [[0, 2, 2]])
	var a := BossMemoryLib.build_boss_memory(_level(), [t])
	var b := ODCore.build_boss_memory(_level(), [t])
	assert_json_eq(b.to_dict(), a.to_dict())


func test_BOSS01_samples_every_committed_tape_at_each_whole_master_beat_in_cassette_order() -> void:
	var b := K.path_tape(1, 1.0, 120, [[0, 2, 2], [60, 8, 2]])
	var a := K.path_tape(0, 2.0, 120, [[0, 2, 2]])
	var mem := BossMemoryLib.build_boss_memory(_level(), [b, a])
	var order: Array = []
	for o: BossObservation in mem.observed:
		order.append([o.tape, o.speed])
	assert_eq(order, [[0, 2], [1, 1]])
	# Horizon 2 bars = 8 beats -> samples for beats 0..8.
	assert_eq(mem.observed[1].samples.size(), 9)
	assert_json_eq(mem.observed[1].samples[1].to_dict(), {"beat": 1, "x": 5, "y": 2})
	assert_json_eq(mem.observed[1].samples[8].to_dict(), {"beat": 8, "x": 8, "y": 2}, 0.0, "a 'stop' tape holds its end")


func test_BOSS02_records_attack_attempts_with_end_behaviour_applied_never_dodges_or_interacts() -> void:
	var evs: Array = [[30, ActionKind.LIGHT, 0.0], [45, ActionKind.DODGE, 0.0], [60, ActionKind.INTERACT, 0.0], [90, ActionKind.HEAVY, 0.0]]
	var t := K.path_tape(0, 1.0, 120, [[0, 2, 2], [120, 6, 2]], evs, OD.EndMode.REPEAT)
	var mem := BossMemoryLib.build_boss_memory(_level(), [t])
	# One traversal = 4 beats; the 8-beat horizon replays it once.
	assert_eq(_actions(mem.observed[0]), [[1, "light"], [3, "heavy"], [5, "light"], [7, "heavy"]])
	assert_near(mem.observed[0].actions[0].x, 3.0, 1e-9)
	assert_near(mem.observed[0].actions[0].y, 2.0, 1e-9)
	var rt := t.copy()
	rt.end_mode = OD.EndMode.REVERSE
	var rev := BossMemoryLib.build_boss_memory(_level(), [rt])
	# Backward pass: the heavy (tick 90) fires again at beat 4 + 1, the light at beat 4 + 3.
	assert_eq(_actions(rev.observed[0]), [[1, "light"], [3, "heavy"], [5, "heavy"], [7, "light"]])


func test_BOSS01_is_plain_data_building_it_twice_gives_equal_memories() -> void:
	var t := K.path_tape(2, 1.0, 120, [[0, 2, 2]], [[10, ActionKind.LIGHT]])
	var one := BossMemoryLib.build_boss_memory(_level(), [t])
	var two := BossMemoryLib.build_boss_memory(_level(), [t])
	assert_json_eq(one.to_dict(), two.copy().to_dict())
	assert_json_eq(BossMemory.from_dict(one.to_dict()).to_dict(), one.to_dict(), 0.0, "round-trips as JSON")


func _cands(c: Array[BossMemoryLib.RecallCandidate], full: bool) -> Array:
	var out: Array = []
	for x: BossMemoryLib.RecallCandidate in c:
		if full:
			out.append([String(x.reason), x.beat, x.last_beat, x.x, x.y])
		else:
			out.append([x.tape, String(x.reason), x.beat])
	return out


func test_BOSS02_finds_dwells_of_at_least_BOSS_DWELL_BEATS_beats_a_long_wait_is_one_dwell() -> void:
	# Moves for 2 beats, waits 2 beats (a dwell), runs, then waits out the horizon (another one).
	var t := K.path_tape(0, 1.0, 240, [[0, 2, 2], [60, 8, 2], [120, 8, 2], [150, 8, 7]])
	var lvl := K.make_level({"speeds": [1.0], "bars": 2, "horizon_bars": 3, "start": Vector2(2, 2)})
	var c := BossMemoryLib.recall_candidates(BossMemoryLib.build_boss_memory(lvl, [t]))
	assert_eq(_cands(c, true), [["dwell", 2, 4, 8, 2], ["dwell", 5, 12, 8, 7]])
	assert_eq(BossMemoryLib.BOSS_DWELL_BEATS, 2)


func test_BOSS02_turns_attacks_into_moments_on_the_nearest_whole_beat_ordered_by_beat_cassette_attack_first() -> void:
	var a := K.path_tape(1, 1.0, 240, [[0, 2, 2], [240, 10, 2]], [[50, ActionKind.HEAVY]])
	var b := K.path_tape(0, 1.0, 240, [[0, 2, 2], [240, 2, 8]], [[64, ActionKind.LIGHT]])
	var lvl := K.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(2, 2)})
	var c := BossMemoryLib.recall_candidates(BossMemoryLib.build_boss_memory(lvl, [a, b]))
	assert_eq(_cands(c, false), [[0, "attack", 2], [1, "attack", 2]])


func test_BOSS02_attack_before_dwell_on_the_same_beat_and_cassette() -> void:
	# A self that waits from beat 0 and swings on beat 0: both moments start on beat 0.
	var t := K.path_tape(0, 1.0, 240, [[0, 2, 2]], [[0, ActionKind.LIGHT]])
	var lvl := K.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(2, 2)})
	var c := BossMemoryLib.recall_candidates(BossMemoryLib.build_boss_memory(lvl, [t]))
	assert_eq(_cands(c, false), [[0, "attack", 0], [0, "dwell", 0]])


func test_BOSS01_no_memory_means_no_moments() -> void:
	assert_eq(BossMemoryLib.recall_candidates(null).size(), 0)
	assert_eq(BossMemoryLib.recall_candidates(BossMemory.new()).size(), 0)
