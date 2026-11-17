extends ODTest
## Shielder (Scenario A, AI-05): the shield recharges instantly; only a hit from a DIFFERENT self
## inside the window after another self popped it does anything. One self alone can never kill it.
##
## Timing: bpm 120 -> 120 substeps per beat; window SHIELDER_WINDOW_BEATS beats. A 1x light event on
## tick t connects on substep (t + 6) * 4 (baseline windup 6 ticks).
## Port of prototype/tests/core/enemies/shielder.test.ts.

const K = preload("res://tests/core/enemies/test_enemy_kit.gd")
const SPB: int = 120
const WINDOW: float = Tuning.SHIELDER_WINDOW_BEATS * SPB


# Asleep so it stands still and never strikes back: the rule under test is the shield alone.
func _shielder(o: Dictionary = {"asleep": true}) -> EnemyDef:
	return K.enemy("sh", EnemyType.SHIELDER, 6, 5, o)


func _level() -> LevelDef:
	return K.make_level({"speeds": [0.5, 1.0, 2.0], "bars": 2, "start": Vector2(4.9, 5), "entities": [_shielder()]})


## A self standing beside the shielder (west for A, east for B) swinging at it on the given ticks.
func _striker(index: int, ticks: Array, kind: StringName = ActionKind.LIGHT, speed: float = 1.0) -> ODTape:
	var west: bool = index % 2 == 0
	var x: float = 4.9 if west else 7.1
	var dir: float = 0.0 if west else PI
	var evs: Array = []
	for t: Variant in ticks:
		evs.append([int(t), kind, dir])
	return K.path_tape(index, speed, 240, [[0, x, 5]], evs)


func _connect(tick: int) -> int:
	return (tick + 6) * 4


func _pairs(evs: Array[SimEvent], with_detail: bool = false) -> Array:
	var out: Array = []
	for e: SimEvent in evs:
		out.append([e.sub, e.tape, e.detail] if with_detail else [e.sub, e.tape])
	return out


func test_ScenarioA_the_window_is_a_readable_fraction_of_a_bar_stated_in_beats() -> void:
	assert_true(Tuning.SHIELDER_WINDOW_BEATS > 0.0)
	assert_true(Tuning.SHIELDER_WINDOW_BEATS <= 1.0)
	assert_eq(WINDOW, SPB * Tuning.SHIELDER_WINDOW_BEATS)
	assert_eq(float(ShielderBehaviour.shield_window_subs(ODSim.create_sim(SimConfig.make(_level(), K.base_loadout(), [])))), WINDOW)


func test_AI05_one_self_alone_can_never_hurt_it_whatever_it_swings() -> void:
	var lights := K.resolve(_level(), [_striker(0, [10, 14, 18, 22, 40, 60, 80, 100])])
	assert_eq(K.events_of(lights.events, SimEventType.HIT, -1, "sh").size(), 0)
	var clangs := K.events_of(lights.events, SimEventType.CLANG, -1, "sh")
	for c: SimEvent in clangs:
		assert_eq(c.detail, "shield")
	assert_eq(clangs.size(), 8)
	var end := K.last_frame(lights).enemies[0]
	assert_eq(end.hp, 2)
	assert_true(end.alive)
	# A 2x heavy (momentum 4) is no better on its own.
	var heavy := K.resolve(_level(), [_striker(0, [10, 50, 90, 130, 170], ActionKind.HEAVY, 2.0)])
	assert_eq(K.events_of(heavy.events, SimEventType.HIT, -1, "sh").size(), 0)
	assert_eq(K.last_frame(heavy).enemies[0].hp, 2)
	assert_true(K.last_frame(heavy).enemies[0].alive)


func test_ScenarioA_a_hit_from_a_second_self_inside_the_window_lands_the_shield_is_back_at_once() -> void:
	# A pops on tick 30, B follows 3 ticks later (12 substeps): damage. A swings again right after,
	# still inside the old window: the shield is already back up, so that hit only pops it again.
	var res := K.resolve(_level(), [_striker(0, [30, 36]), _striker(1, [33])])
	assert_eq(_pairs(K.events_of(res.events, SimEventType.HIT, -1, "sh")), [[_connect(33), 1]])
	assert_eq(_pairs(K.events_of(res.events, SimEventType.CLANG, -1, "sh"), true), [
		[_connect(30), 0, "shield"],
		[_connect(36), 0, "shield"],
	])
	var end := K.last_frame(res).enemies[0]
	assert_eq(end.hp, 1)
	assert_true(end.alive)


func test_MOM05_two_coordinated_pairs_kill_it_the_landed_hit_shoves_it_so_the_pair_reforms() -> void:
	# B's landed hit knocks it 1 tile toward A; a third self C waiting further west supplies the
	# second follow-up after A pops it again.
	var c := K.path_tape(2, 1.0, 240, [[0, 3.9, 5]], [[63, ActionKind.LIGHT, 0.0]])
	var res := K.resolve(_level(), [_striker(0, [30, 60]), _striker(1, [33]), c])
	var hit_tapes: Array = []
	for h: SimEvent in K.events_of(res.events, SimEventType.HIT, -1, "sh"):
		hit_tapes.append(h.tape)
	assert_eq(hit_tapes, [1, 2])
	var kill_tapes: Array = []
	for k: SimEvent in K.events_of(res.events, SimEventType.KILL, -1, "sh"):
		kill_tapes.append(k.tape)
	assert_eq(kill_tapes, [2])
	assert_true(res.outcome.win)


func test_ScenarioA_a_follow_up_outside_the_window_only_pops_the_shield_again() -> void:
	var late: int = int((WINDOW + 20) / 4)  # ticks after A's hit
	var res := K.resolve(_level(), [_striker(0, [30]), _striker(1, [30 + late])])
	assert_eq(K.events_of(res.events, SimEventType.HIT, -1, "sh").size(), 0)
	assert_eq(K.events_of(res.events, SimEventType.CLANG, -1, "sh").size(), 2)


func test_AI05_a_follow_up_by_the_same_self_that_popped_it_never_counts() -> void:
	var res := K.resolve(_level(), [_striker(0, [30, 33, 36])])
	assert_eq(K.events_of(res.events, SimEventType.HIT, -1, "sh").size(), 0)


func test_ScenarioA_two_selves_striking_on_the_same_substep_is_the_classic_two_hit_kill() -> void:
	var res := K.resolve(_level(), [_striker(0, [30], ActionKind.HEAVY), _striker(1, [30], ActionKind.HEAVY)])
	# 1x standing heavy = momentum 2 = 2 damage: the follow-up alone kills a 2-hp shielder.
	var clang_tapes: Array = []
	for c: SimEvent in K.events_of(res.events, SimEventType.CLANG, -1, "sh"):
		clang_tapes.append(c.tape)
	assert_eq(clang_tapes, [0])
	assert_eq(_pairs(K.events_of(res.events, SimEventType.KILL, -1, "sh")), [[(30 + 16) * 4, 1]])


func test_ScenarioA_the_snapshot_shows_the_shield_down_only_during_the_window() -> void:
	var res := K.resolve(_level(), [_striker(0, [30])])
	var pop: int = _connect(30)
	var before := K.frame_at(res, pop - 4).enemies[0]
	assert_true(before.has_shield and before.shield, "up before the pop")
	assert_false(K.frame_at(res, pop + 4).enemies[0].shield, "down in the window")
	assert_true(K.frame_at(res, pop + int(WINDOW) + 8).enemies[0].shield, "back up after it")


func test_AI05_non_self_hits_clang_off_without_popping_the_shield() -> void:
	var lvl := K.make_level({
		"speeds": [1.0],
		"bars": 2,
		"start": Vector2(2, 2),
		"entities": [_shielder(), K.enemy("t1", EnemyType.TURRET, 10, 5, {"facing": PI})],
	})
	# The self hides behind the shielder from the turret (the shielder is in the bolt's lane).
	var res := K.resolve(lvl, [K.path_tape(0, 1.0, 240, [[0, 2, 5]])])
	assert_true(K.events_of(res.events, SimEventType.CLANG, -1, "sh").size() > 0, "bolts clang")
	assert_eq(K.events_of(res.events, SimEventType.HIT, -1, "sh").size(), 0)
	var always_up := true
	for f: FrameSnapshot in res.frames:
		if not (f.enemies[0].has_shield and f.enemies[0].shield):
			always_up = false
	assert_true(always_up, "shield never popped")


func test_AI01_awake_it_walks_at_the_nearest_self() -> void:
	var lvl := K.make_level({"speeds": [1.0], "bars": 1, "start": Vector2(2, 5), "entities": [_shielder({})]})
	var near := K.path_tape(1, 1.0, 120, [[0, 9, 5]])
	var far := K.path_tape(0, 1.0, 120, [[0, 2, 5]])
	var res := K.resolve(lvl, [far, near])
	var f := K.frame_at(res, SPB)
	assert_eq(f.enemies[0].target, 1)
	assert_true(f.enemies[0].x > 6.5)
