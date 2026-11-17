extends ODTest
## Guided missile: one-time nearest-target acquisition at launch, no retargeting, launch gating
## (MISSILE-02..04, WEAPON-02, NEW-03, TEST-22, Scenario F).
## Port of prototype/tests/core/weapons/missile.test.ts.

var SLEEP: SignalExpr = SignalExpr.of_const(false)

const LAUNCH_TICK: int = 60
## Tape A launches 4 ticks after its press (sub 256).
const LAUNCH_SUB: int = (LAUNCH_TICK + 4) * 4


func _grunt(id: String, x: float, y: float, hp: int = 5) -> EnemyDef:
	return TestScript.enemy(id, EnemyType.GRUNT, x, y, {"hp": hp, "wake": SLEEP})


## Tape A: stands at (2.5, 5.5) and fires east at local tick 60.
func _tape_a() -> ODTape:
	return TestScript.path_tape(0, 1.0, 480, [[0, 2.5, 5.5]], [[LAUNCH_TICK, ActionKind.RANGED, 0.0]])


## A self standing at (x, y) with one heavy swing along `dir` at local tick `tick`.
func _pusher(index: int, x: float, y: float, tick: int, dir: float) -> ODTape:
	return TestScript.path_tape(index, 1.0, 480, [[0, x, y]], [[tick, ActionKind.HEAVY, dir]])


## g1 starts nearest to A (≈4.47 tiles); g2 (5 tiles) is the one later cassettes shove around.
func _level() -> LevelDef:
	return TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.5, 5.5), "entities": [_grunt("g1", 6.5, 3.5), _grunt("g2", 7.5, 5.5)]})


## Every missile snapshot with the frame's sub: [[sub, ProjectileSnap], ...].
func _missile_frames(res: Resolution) -> Array:
	var out: Array = []
	for f: FrameSnapshot in res.frames:
		for p: ProjectileSnap in f.projectiles:
			if p.archetype == RangedArchetype.MISSILE:
				out.append([f.sub, p])
	return out


## Distinct missile locks in first-seen order ("" = none).
func _lock_of(res: Resolution) -> Array:
	var out: Array = []
	for mp: Array in _missile_frames(res):
		var t: String = (mp[1] as ProjectileSnap).target_id
		if not out.has(t):
			out.append(t)
	return out


func _tape_hits(res: Resolution, id: String, tape: int) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in TestScript.events_of(res.events, SimEventType.HIT, -1, id):
		if e.tape == tape:
			out.append(e)
	return out


func _enemy(f: FrameSnapshot, id: String) -> EnemySnap:
	for e: EnemySnap in f.enemies:
		if e.id == id:
			return e
	return null

# ───────────────────────────── Scenario F / TEST-22 / NEW-03 ─────────────────────────────


func test_scenario_f_test22_alone_the_missile_locks_the_nearest_enemy_and_strikes_it() -> void:
	var res := TestScript.resolve(_level(), [_tape_a()])
	assert_eq(_lock_of(res), ["g1"], "lock")
	var hits: Array = []
	for e: SimEvent in TestScript.events_of(res.events, SimEventType.HIT, -1, "g1"):
		hits.append([e.tape, e.detail])
	assert_eq(hits, [[0, "missile"]], "g1 hits")
	assert_eq(TestScript.events_of(res.events, SimEventType.HIT, -1, "g2").size(), 0, "g2 untouched")


func test_scenario_f_new03_the_same_launch_picks_another_enemy_when_a_later_tape_moves_it_closer_first() -> void:
	# B heavy-swings g2 two tiles west (to x 5.5, 3 tiles from A) long before A's launch.
	var b := _pusher(1, 8.6, 5.5, 10, PI)
	var res := TestScript.resolve(_level(), [_tape_a(), b])
	var push := _tape_hits(res, "g2", 1)
	assert_true(push.size() > 0 and push[0].sub < LAUNCH_SUB, "B pushes g2 before the launch")
	assert_near(_enemy(TestScript.frame_at(res, LAUNCH_SUB), "g2").x, 5.5, 5e-4, "g2 at x 5.5")
	# Same tape A, same launch instant and direction: the world chose the target.
	var fires: Array = []
	for e: SimEvent in TestScript.events_of(res.events, SimEventType.FIRE):
		fires.append([e.sub, e.tape, e.dir])
	assert_eq(fires, [[LAUNCH_SUB, 0, 0.0]], "fire")
	assert_eq(_lock_of(res), ["g2"], "lock")
	var details: Array = []
	for e: SimEvent in _tape_hits(res, "g2", 0):
		details.append(e.detail)
	assert_eq(details, ["missile"], "A's hits on g2")
	assert_eq(TestScript.events_of(res.events, SimEventType.HIT, -1, "g1").size(), 0, "g1 untouched")


func test_missile03_after_launch_it_never_retargets_even_when_another_enemy_becomes_nearer() -> void:
	# C shoves g2 two tiles west shortly after the launch: g2 is then much nearer the missile than g1.
	var c := _pusher(2, 8.6, 5.5, LAUNCH_TICK + 2, PI)
	var res := TestScript.resolve(_level(), [_tape_a(), c])
	var pushed := _tape_hits(res, "g2", 2)
	assert_true(pushed.size() > 0 and pushed[0].sub > LAUNCH_SUB, "C pushes g2 after the launch")
	var later: Array = []
	for mp: Array in _missile_frames(res):
		if int(mp[0]) >= pushed[0].sub + 60:
			later = mp
			break
	assert_true(not later.is_empty(), "missile still flying 60 subs after the push")
	var lp: ProjectileSnap = later[1]
	var f := TestScript.frame_exact(res.frames, int(later[0]))
	var d := func(id: String) -> float:
		var e := _enemy(f, id)
		var dx := e.x - lp.x
		var dy := e.y - lp.y
		return sqrt(dx * dx + dy * dy)
	assert_true(float(d.call("g2")) < float(d.call("g1")), "g2 nearer the missile than g1")
	assert_eq(_lock_of(res), ["g1"], "lock")
	assert_eq(_tape_hits(res, "g1", 0).size(), 1, "A hits g1")
	assert_eq(_tape_hits(res, "g2", 0).size(), 0, "A never hits g2")


func test_missile03_when_its_target_dies_first_it_flies_straight_on_and_never_switches() -> void:
	# g1 has 1 hp here and B kills it with a swing while the missile is on its way.
	var lv := TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.5, 5.5), "entities": [_grunt("g1", 6.5, 3.5, 1), _grunt("g2", 9.5, 8.5)]})
	var b := TestScript.path_tape(1, 1.0, 480, [[0, 7.4, 3.5]], [[LAUNCH_TICK + 10, ActionKind.LIGHT, PI]])
	var res := TestScript.resolve(lv, [_tape_a(), b])
	var kill: SimEvent = TestScript.events_of(res.events, SimEventType.KILL, -1, "g1")[0]
	assert_eq(kill.tape, 1, "B kills g1")
	assert_true(kill.sub > LAUNCH_SUB, "after the launch")
	var after: Array[ProjectileSnap] = []
	for mp: Array in _missile_frames(res):
		if int(mp[0]) > kill.sub + OD.FRAME_SUBS:
			after.append(mp[1])
	assert_true(after.size() > 10, "missile keeps flying")
	var dirs: Dictionary[String, bool] = {}
	var locked := true
	for p: ProjectileSnap in after:
		if p.target_id != "g1":
			locked = false
		dirs["%.9f" % p.dir] = true
	assert_true(locked, "lock stays on g1")
	assert_eq(dirs.size(), 1, "flies straight")
	assert_eq(_tape_hits(res, "g2", 0).size(), 0, "never hits g2")


func test_missile_turns_no_faster_than_its_turn_rate() -> void:
	# Fire away from the only enemy so the missile has to turn round.
	var lv := TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(5.5, 5.5), "entities": [_grunt("g1", 2.5, 5.5)]})
	var tape := TestScript.path_tape(0, 1.0, 480, [[0, 5.5, 5.5]], [[10, ActionKind.RANGED, 0.0]])
	var res := TestScript.resolve(lv, [tape])
	var ps := _missile_frames(res)
	var max_step: float = (TestLoadout.base_missile().turn_rate * OD.FRAME_SUBS) / OD.SUB_HZ + 1e-9
	var worst := 0.0
	for i in range(1, ps.size()):
		var d: float = (ps[i][1] as ProjectileSnap).dir - (ps[i - 1][1] as ProjectileSnap).dir
		while d > PI:
			d -= 2.0 * PI
		while d < -PI:
			d += 2.0 * PI
		worst = maxf(worst, absf(d))
	assert_true(worst <= max_step, "max turn per frame %f <= %f" % [worst, max_step])
	assert_eq(TestScript.events_of(res.events, SimEventType.HIT, -1, "g1").size(), 1, "still hits g1")


func test_missile03_ties_go_to_the_enemy_placed_first_and_with_no_enemy_it_flies_straight() -> void:
	var tie := TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.5, 5.5), "entities": [_grunt("b", 5.5, 7.5), _grunt("a", 5.5, 3.5)]})
	assert_eq(_lock_of(TestScript.resolve(tie, [_tape_a()])), ["b"], "tie lock")
	var empty := TestScript.resolve(TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.5, 5.5)}), [_tape_a()])
	var ps := _missile_frames(empty)
	assert_true(ps.size() > 0, "missile flies")
	var straight := true
	for mp: Array in ps:
		var p: ProjectileSnap = mp[1]
		if not (p.target_id.is_empty() and p.dir == 0.0 and absf(p.y - 5.5) < 1e-9):
			straight = false
	assert_true(straight, "no lock, recorded heading, straight line")

# ───────────────────────────── launch gating ─────────────────────────────


func test_scenario_f_a_dead_playback_ghost_launches_nothing_the_recording_ghost_only_in_its_take() -> void:
	var lv := TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.5, 5.5), "entities": [TestScript.enemy("t1", EnemyType.TURRET, 9.5, 5.5, {"facing": PI})]})
	var take := TestScript.record_take(lv, 0, 1.0, TestScript.input_script().aim(0, 480, 0.0).press(150, ActionKind.RANGED, 0.0))
	var death: SimEvent = TestScript.events_of(take.events, SimEventType.SELF_DEATH, 0)[0]
	assert_true(death.sub < 150 * 4, "dies before the press")
	# In its own take the recording ghost's missile flies and kills the turret (GHOST-03).
	assert_eq(TestScript.events_of(take.events, SimEventType.FIRE, 0).size(), 1, "take fires")
	var killers: Array = []
	for e: SimEvent in TestScript.events_of(take.events, SimEventType.KILL, -1, "t1"):
		killers.append(e.tape)
	assert_eq(killers, [0], "take kills the turret")
	# Under playback the self dies at the same moment and its ghost fires nothing.
	var res := TestScript.resolve(lv, [take.tape])
	var deaths: Array = []
	for e: SimEvent in TestScript.events_of(res.events, SimEventType.SELF_DEATH, 0):
		deaths.append(e.sub)
	assert_eq(deaths, [death.sub], "same death")
	assert_eq(TestScript.events_of(res.events, SimEventType.FIRE).size(), 0, "no fire")
	var none_self := true
	for f: FrameSnapshot in res.frames:
		for p: ProjectileSnap in f.projectiles:
			if p.owner_tape >= 0:
				none_self = false
	assert_true(none_self, "no self projectile")
	assert_eq(TestScript.events_of(res.events, SimEventType.KILL, -1, "t1").size(), 0, "turret survives")


func test_scenario_f_a_desynced_self_launches_nothing() -> void:
	# A wall at column 5 with a door at (5, 5): the tape walks through the doorway, then fires.
	var map: Array[String] = []
	var n := TestLevels.OPEN_ROOM.size()
	for r in n:
		var row: String = TestLevels.OPEN_ROOM[r]
		map.append(row if r == 0 or r == n - 1 else row.substr(0, 5) + ("." if r == 5 else "#") + row.substr(6))
	var tape := TestScript.path_tape(0, 1.0, 480, [[0, 2.5, 5.5], [40, 7.5, 5.5]], [[60, ActionKind.RANGED, 0.0]])
	var cells: Array[Vector2i] = [Vector2i(5, 5)]
	var lv := func(open: bool) -> LevelDef:
		return TestLevels.make_level({"speeds": [1.0], "bars": 4, "map": map, "start": Vector2(2.5, 5.5), "entities": [TestScript.door("d1", cells, SignalExpr.of_const(open)), _grunt("g1", 9.5, 5.5)]})
	var shut := TestScript.resolve(lv.call(false), [tape])
	assert_eq(TestScript.events_of(shut.events, SimEventType.DESYNC, 0).size(), 1, "desyncs at the door")
	assert_eq(TestScript.events_of(shut.events, SimEventType.RESYNC, 0).size(), 0, "never resyncs")
	assert_eq(TestScript.events_of(shut.events, SimEventType.FIRE).size(), 0, "no fire")
	var empty := true
	for f: FrameSnapshot in shut.frames:
		if f.projectiles.size() > 0:
			empty = false
	assert_true(empty, "no projectiles")
	var open := TestScript.resolve(lv.call(true), [tape])
	assert_eq(TestScript.events_of(open.events, SimEventType.FIRE, 0).size(), 1, "fires through the open door")


func test_play06_a_reverse_pass_fires_again_with_the_recorded_direction_and_can_hurt_again() -> void:
	var lv := TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.5, 5.5), "entities": [_grunt("g1", 9.5, 5.5, 9)]})
	var tape := TestScript.path_tape(0, 1.0, 120, [[0, 2.5, 5.5]], [[20, ActionKind.RANGED, 0.0]], OD.EndMode.REVERSE)
	var res := TestScript.resolve(lv, [tape], TestLoadout.base_loadout({"ranged": {"archetype": RangedArchetype.PIERCE, "speed": 20.0, "range": 12.0, "pierce": 0, "turn_rate": 0.0}}))
	var fires := TestScript.events_of(res.events, SimEventType.FIRE)
	assert_true(fires.size() >= 2, "fires at least twice (%d)" % fires.size())
	var all_zero := true
	for e: SimEvent in fires:
		if e.dir != 0.0:
			all_zero = false
	assert_true(all_zero, "recorded direction every time")
	# Every shot with time to arrive before the horizon (≈ 7 tiles at 20 tiles/s) hurts again (PLAY-06).
	var arrived := 0
	for e: SimEvent in fires:
		if e.sub + 0.5 * OD.SUB_HZ < res.horizon_subs:
			arrived += 1
	assert_true(arrived >= 2, "at least two arrive")
	assert_eq(TestScript.events_of(res.events, SimEventType.HIT, -1, "g1").size(), arrived, "each arrival hits")
