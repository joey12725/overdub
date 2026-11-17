extends ODTest
## The outside-the-loop boss (BOSS-01..03, HEALTH-03, AI-07).
##
## bpm 120 -> 120 substeps per beat. A 1x tape advances 4 substeps per local tick, a 2x tape 2.
## Baseline heavy: windup 16 ticks, so a heavy pressed on tick t connects on substep (t + 16) * m.
## Port of prototype/tests/core/enemies/boss.test.ts.

const K = preload("res://tests/core/enemies/test_enemy_kit.gd")
const SPB: int = 120


func _fight(level: LevelDef, tapes: Array[ODTape], memory: BossMemory = null) -> Resolution:
	return K.resolve(level, tapes, K.base_loadout(), memory)


func _tapes_of(evs: Array[SimEvent]) -> Array:
	var out: Array = []
	for e: SimEvent in evs:
		out.append(e.tape)
	return out


func _first(evs: Array[SimEvent], detail: String) -> SimEvent:
	for e: SimEvent in evs:
		if e.detail == detail:
			return e
	return null


# ───────────────────────────── coordination (BOSS-03) ─────────────────────────────

func _armour_level() -> LevelDef:
	return K.make_level({
		"speeds": [1.0, 2.0],
		"bars": 2,
		"start": Vector2(4.7, 5),
		"entities": [K.enemy("b1", EnemyType.BOSS, 6, 5, {"facing": PI, "hp": 16})],
		"objective": ObjectiveType.BOSS,
	})


## A holds its attention: the nearest self, right in front of it (west).
func _holder(ticks: int = 240) -> ODTape:
	return K.path_tape(0, 1.0, ticks, [[0, 4.7, 5]])


## B stands behind it (east) and lands 2x heavies on its back (momentum 4 = 4 damage each).
func _striker(index: int = 1) -> ODTape:
	var evs: Array = []
	for t: int in [40, 80, 120, 160]:
		evs.append([t, ActionKind.HEAVY, PI])
	return K.path_tape(index, 2.0, 240, [[0, 7.9, 5]], evs)


func test_BOSS03_a_coordinated_plan_beats_it_one_self_holds_its_eye_another_strikes_its_back() -> void:
	var res := K.resolve(_armour_level(), [_holder(), _striker()])
	var hits := K.events_of(res.events, SimEventType.HIT, -1, "b1")
	assert_eq(_tapes_of(hits), [1, 1, 1, 1])
	assert_eq(_tapes_of(K.events_of(res.events, SimEventType.KILL, -1, "b1")), [1])
	var phases: Array = []
	for p: SimEvent in K.events_of(res.events, SimEventType.BOSS_PHASE, -1, "b1"):
		phases.append(p.power)
	assert_eq(phases, [2, 3])
	assert_true(res.outcome.win)
	assert_eq(res.outcome.survivors, [0, 1])
	# The health bar reads as a fraction (objective progress), phase by phase.
	if hits.size() == 4:
		var f1 := K.frame_at(res, hits[1].sub + 2).enemies[0]
		assert_eq([f1.hp, f1.boss_phase], [8, 2])
		var f2 := K.frame_at(res, hits[2].sub + 2).enemies[0]
		assert_eq([f2.hp, f2.boss_phase], [4, 3])


func test_BOSS03_one_self_alone_can_never_hurt_it_whoever_is_alone_holds_its_attention() -> void:
	var res := K.resolve(_armour_level(), [_striker(0)])
	assert_eq(K.events_of(res.events, SimEventType.HIT, -1, "b1").size(), 0)
	var clangs := K.events_of(res.events, SimEventType.CLANG, -1, "b1")
	assert_true(clangs.size() > 0)
	for c: SimEvent in clangs:
		assert_eq(c.detail, "armour")
	assert_eq(K.last_frame(res).enemies[0].hp, 16)
	assert_false(res.outcome.win)
	# And it fights back: the lone self is cleaved on the bar grid.
	var death: SimEvent = K.events_of(res.events, SimEventType.SELF_DEATH)[0]
	assert_eq(death.detail, "struck by boss b1")
	assert_eq(death.sub % (4 * SPB), 0)


func test_BOSS03_the_self_holding_its_attention_is_blocked_even_with_a_partner_so_is_a_frontal_hit() -> void:
	# A (nearest) also swings; only B's back hits land.
	var swinging := K.path_tape(0, 1.0, 240, [[0, 4.7, 5]], [[20, ActionKind.HEAVY, 0.0]])
	var res := K.resolve(_armour_level(), [swinging, _striker()])
	var a_clangs: Array = []
	for c: SimEvent in K.events_of(res.events, SimEventType.CLANG, 0, "b1"):
		a_clangs.append(c.detail)
	assert_eq(a_clangs, ["armour"])
	assert_eq(K.events_of(res.events, SimEventType.HIT, 0, "b1").size(), 0)
	# B striking from the FRONT (same side as A, but farther) is armour too.
	var front := K.path_tape(1, 2.0, 240, [[0, 4.3, 5.6]], [[40, ActionKind.HEAVY, atan2(5 - 5.6, 6 - 4.3)]])
	var res2 := K.resolve(_armour_level(), [_holder(), front])
	assert_eq(K.events_of(res2.events, SimEventType.HIT, -1, "b1").size(), 0)
	var details: Array = []
	for c: SimEvent in K.events_of(res2.events, SimEventType.CLANG, -1, "b1"):
		details.append(c.detail)
	assert_eq(details, ["armour"])


func test_HEALTH03_its_phases_follow_the_health_bar() -> void:
	var out: Array = []
	for hp: int in [16, 11, 10, 6, 5, 1]:
		out.append(BossBehaviour.boss_phase_for(hp, 16))
	assert_eq(out, [1, 1, 2, 2, 3, 3])


# ───────────────────────────── phases and base pattern (HEALTH-03, AI-07) ─────────────────────────────

func _phase_level() -> LevelDef:
	return K.make_level({
		"speeds": [1.0, 2.0],
		"bars": 4,
		"start": Vector2(4.7, 5),
		"entities": [K.enemy("b1", EnemyType.BOSS, 6, 5, {"facing": PI, "hp": 12})],
		"objective": ObjectiveType.BOSS,
	})


func _base_telegraphs(res: Resolution) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for t: SimEvent in K.events_of(res.events, SimEventType.ENEMY_TELEGRAPH, -1, "b1"):
		if t.detail != "recall":
			out.append(t)
	return out


func test_AI07_phase_1_attacks_once_a_bar_with_a_cleave_telegraphed_two_beats_ahead() -> void:
	var res := K.resolve(_phase_level(), [_holder(480)])
	var tels := _base_telegraphs(res)
	assert_true(tels.size() > 0)
	assert_eq([tels[0].sub, tels[0].detail], [2 * SPB, "cleave"])
	var attacks := K.events_of(res.events, SimEventType.ENEMY_ATTACK, -1, "b1")
	assert_eq([attacks[0].sub, attacks[0].detail], [4 * SPB, "cleave"])
	assert_eq(K.events_of(res.events, SimEventType.BOSS_PHASE).size(), 0)
	for t: SimEvent in tels:
		assert_ne(t.detail, "sweep")


func test_HEALTH03_phase_2_adds_the_sweep_phase_3_attacks_every_two_beats() -> void:
	# Two back hits (4 each): 12 -> 8 (phase 2) -> 4 (phase 3).
	var evs: Array = [[40, ActionKind.HEAVY, PI], [80, ActionKind.HEAVY, PI]]
	var striker := K.path_tape(1, 2.0, 480, [[0, 7.9, 5]], evs)
	var res := K.resolve(_phase_level(), [_holder(480), striker])
	var phases := K.events_of(res.events, SimEventType.BOSS_PHASE, -1, "b1")
	var pd: Array = []
	for p: SimEvent in phases:
		pd.append([p.power, p.detail])
	assert_eq(pd, [[2, "phase 2"], [3, "phase 3"]])
	var hit_subs: Array = []
	for h: SimEvent in K.events_of(res.events, SimEventType.HIT, -1, "b1"):
		hit_subs.append(h.sub)
	var phase_subs: Array = []
	for p: SimEvent in phases:
		phase_subs.append(p.sub)
	assert_eq(phase_subs, hit_subs)
	if phases.size() < 2:
		return
	var tels: Array[SimEvent] = []
	for t: SimEvent in _base_telegraphs(res):
		if t.sub > phases[1].sub:
			tels.append(t)
	assert_true(tels.size() >= 3)
	# Phase 3: one attack every 2 beats, alternating strike and sweep.
	var sweep_seen := false
	var strike_seen := false
	for i: int in range(tels.size()):
		if i > 0:
			assert_eq(tels[i].sub - tels[i - 1].sub, 2 * SPB)
		sweep_seen = sweep_seen or tels[i].detail == "sweep"
		strike_seen = strike_seen or tels[i].detail == "cleave" or tels[i].detail == "volley"
	assert_true(sweep_seen and strike_seen, "sweeps and strikes")
	# Every landing is on a whole beat (AI-07).
	for a: SimEvent in K.events_of(res.events, SimEventType.ENEMY_ATTACK, -1, "b1"):
		assert_eq(a.sub % SPB, 0)
	# The sweep is a ring of shockwave shots.
	var sweep := _first(K.events_of(res.events, SimEventType.ENEMY_ATTACK, -1, "b1"), "sweep")
	assert_true(sweep != null)
	if sweep != null:
		var n := 0
		for p: ProjectileSnap in K.frame_at(res, sweep.sub + 4).projectiles:
			if p.archetype == RangedArchetype.SHOCK:
				n += 1
		assert_true(n > 8, "%d shock shots in flight" % n)


# ───────────────────────────── memory (BOSS-01, BOSS-02) ─────────────────────────────

# A pillar (column 10, rows 5..7) between the boss and A's waiting spot.
const PILLAR: Array[String] = [
	"################",
	"#..............#",
	"#..............#",
	"#..............#",
	"#..............#",
	"#.........#....#",
	"#.........#....#",
	"#.........#....#",
	"#..............#",
	"#..............#",
	"#..............#",
	"################",
]
const SPOT: Vector2 = Vector2(13.5, 6.5)
const LAND_SUB: int = 3 * SPB  # A's dwell starts on beat 2; the strike lands on its second beat
const START_SUB: int = LAND_SUB - int(BossBehaviour.BOSS_RECALL_TELEGRAPH_BEATS) * SPB


func _mem_level() -> LevelDef:
	return K.make_level({
		"map": PILLAR,
		"speeds": [1.0, 2.0],
		"bars": 2,
		"start": Vector2(3.5, 2.5),
		"entities": [K.enemy("b1", EnemyType.BOSS, 7, 6.5, {"facing": 0.0, "hp": 20})],
		"objective": ObjectiveType.BOSS,
	})


## Tape A (committed) runs round the pillar and waits behind it from beat 2 on.
func _tape_a() -> ODTape:
	return K.path_tape(0, 1.0, 240, [[0, 3.5, 2.5], [30, 13.5, 2.5], [60, SPOT.x, SPOT.y]])


func _memory() -> BossMemory:
	return BossMemoryLib.build_boss_memory(_mem_level(), [_tape_a()])


## Tape B stands behind the boss (west, while it looks east at A's spot) and strikes east.
func _tape_b() -> ODTape:
	return K.path_tape(1, 1.0, 240, [[0, 3.5, 2.5], [25, 5.2, 6.5]], [[60, ActionKind.HEAVY, 0.0]])


func test_BOSS01_first_take_no_memory_only_the_base_pattern_the_pillar_shelters_A() -> void:
	var res := _fight(_mem_level(), [_tape_a()])
	assert_eq(K.events_of(res.events, SimEventType.BOSS_RECALL).size(), 0)
	var never := true
	for f: FrameSnapshot in res.frames:
		if f.enemies[0].boss_recall:
			never = false
	assert_true(never, "bossRecall never set")
	assert_eq(K.events_of(res.events, SimEventType.SELF_DEATH).size(), 0)


func test_BOSS02_with_memory_it_preempts_the_remembered_dwell_telegraphed_then_struck() -> void:
	var res := _fight(_mem_level(), [_tape_a()], _memory())
	var recalls: Array = []
	for r: SimEvent in K.events_of(res.events, SimEventType.BOSS_RECALL, -1, "b1"):
		recalls.append([r.sub, r.tape, r.power, r.detail, r.x, r.y])
	assert_eq(recalls, [[START_SUB, 0, 3, "dwell", SPOT.x, SPOT.y]])
	var tel := _first(K.events_of(res.events, SimEventType.ENEMY_TELEGRAPH, -1, "b1"), "recall")
	assert_true(tel != null and tel.sub == START_SUB, "recall telegraph at its start")
	# The telegraph starts while A is still on its way (beat 1): it is pre-emption, not reaction.
	var early: ActorSnap = K.frame_at(res, START_SUB).actors[0]
	assert_true(ODGrid.hypot(early.x - SPOT.x, early.y - SPOT.y) > BossBehaviour.BOSS_RECALL_RADIUS + 1.0)
	# The snapshot marks the whole commitment so the renderer can draw it as memory.
	var during := K.frame_at(res, START_SUB + 8).enemies[0]
	assert_eq(during.state, EnemyStateName.TELEGRAPH)
	assert_true(during.boss_recall)
	assert_eq(during.boss_recall_tape, 0)
	assert_true(during.has_boss_recall_at)
	assert_vec_near(during.boss_recall_at, SPOT, 1e-6)
	assert_false(K.frame_at(res, START_SUB - 8).enemies[0].boss_recall)
	var death := K.events_of(res.events, SimEventType.SELF_DEATH, 0)
	assert_eq(death.size(), 1)
	if death.size() == 1:
		assert_eq(death[0].sub, LAND_SUB)
		assert_eq(death[0].detail, "struck by boss b1 (remembering Tape A)")
	var atk := _first(K.events_of(res.events, SimEventType.ENEMY_ATTACK, -1, "b1"), "recall")
	assert_true(atk != null)
	if atk != null:
		assert_eq([atk.sub, atk.x, atk.y, atk.tape], [LAND_SUB, SPOT.x, SPOT.y, 0])


func test_BOSS03_later_tapes_exploit_its_commitment_while_it_punishes_As_old_spot_B_hits_its_back() -> void:
	var blind := _fight(_mem_level(), [_tape_a(), _tape_b()])
	var aware := _fight(_mem_level(), [_tape_a(), _tape_b()], _memory())
	var hit_sub: int = (60 + 16) * 4
	# Without memory B is the nearest self, so B holds its attention: armour.
	var bc: Array = []
	for c: SimEvent in K.events_of(blind.events, SimEventType.CLANG, 1, "b1"):
		bc.append([c.sub, c.detail])
	assert_eq(bc, [[hit_sub, "armour"]])
	assert_eq(K.events_of(blind.events, SimEventType.HIT, -1, "b1").size(), 0)
	# With memory its attention is on A's remembered spot: B's hit lands.
	var ah: Array = []
	for h: SimEvent in K.events_of(aware.events, SimEventType.HIT, 1, "b1"):
		ah.append(h.sub)
	assert_eq(ah, [hit_sub])
	assert_eq(K.frame_at(aware, hit_sub + 4).enemies[0].hp, 18)


func test_BOSS02_a_strong_back_hit_during_the_telegraph_cancels_the_memory_strike() -> void:
	# 2x heavy: momentum 4 >= BOSS_STAGGER_MOMENTUM, connects on substep (100 + 16) * 2 = 232.
	var guard := K.path_tape(1, 2.0, 240, [[0, 3.5, 2.5], [50, 5.2, 6.5]], [[100, ActionKind.HEAVY, 0.0]])
	var res := _fight(_mem_level(), [_tape_a(), guard], _memory())
	assert_eq(K.events_of(res.events, SimEventType.BOSS_RECALL).size(), 1)
	var hits := K.events_of(res.events, SimEventType.HIT, 1, "b1")
	assert_true(hits.size() > 0 and hits[0].sub == 232, "the guard's hit lands on 232")
	assert_eq(K.events_of(res.events, SimEventType.ENEMY_STAGGER, -1, "b1").size(), 1)
	assert_true(_first(K.events_of(res.events, SimEventType.ENEMY_ATTACK, -1, "b1"), "recall") == null, "no recall strike")
	assert_eq(K.events_of(res.events, SimEventType.SELF_DEATH, 0).size(), 0)
	assert_false(K.frame_at(res, 240).enemies[0].boss_recall)


func test_BOSS02_remembered_attacks_are_preempted_too_on_the_nearest_whole_beat() -> void:
	# A committed tape that swings at beat ~2.4 while passing through (it never stands still).
	var swinger := K.path_tape(2, 1.0, 240, [[0, 3.5, 2.5], [240, 3.5, 9.5]], [[72, ActionKind.LIGHT, 0.0]])
	var mem := BossMemoryLib.build_boss_memory(_mem_level(), [swinger])
	var res := _fight(_mem_level(), [swinger], mem)
	var recalls := K.events_of(res.events, SimEventType.BOSS_RECALL, -1, "b1")
	var rd: Array = []
	for r: SimEvent in recalls:
		rd.append([r.tape, r.detail, r.power])
	assert_eq(rd, [[2, "attack", 2]])
	if recalls.size() > 0:
		assert_near(recalls[0].y, 2.5 + (7.0 * 72) / 240, 5e-5)


func test_BOSS01_identical_memory_gives_an_identical_fight() -> void:
	var one := _fight(_mem_level(), [_tape_a(), _tape_b()], BossMemoryLib.build_boss_memory(_mem_level(), [_tape_a()]))
	var two := _fight(_mem_level(), [_tape_a(), _tape_b()], BossMemory.from_dict(_memory().to_dict()))
	assert_json_eq(two.to_dict(), one.to_dict())


func _idle() -> PlayerInput:
	return PlayerInput.new()


func test_CINE04_a_resolve_a_replay_and_a_recording_never_change_the_memory() -> void:
	var mem := _memory()
	var before: String = ODJson.stringify(mem.to_dict())
	var a := _fight(_mem_level(), [_tape_a(), _tape_b()], mem)
	var b := _fight(_mem_level(), [_tape_a(), _tape_b()], mem)
	assert_json_eq(b.to_dict(), a.to_dict())
	var sim: ODSim = ODSim.create_sim(SimConfig.make(_mem_level(), K.base_loadout(), [_tape_a()], LiveTake.make(1, 1.0, OD.EndMode.STOP), mem))
	var n := 0
	while not sim.done:
		sim.step_local_tick(_idle())
		n += K.events_of(sim.drain_events(), SimEventType.BOSS_RECALL).size()
	assert_eq(n, 1)
	assert_eq(ODJson.stringify(mem.to_dict()), before, "memory untouched")


func test_BOSS02_the_recording_sees_the_same_memory_strikes_as_its_authoritative_resolve() -> void:
	var mem := _memory()
	var sim: ODSim = ODSim.create_sim(SimConfig.make(_mem_level(), K.base_loadout(), [_tape_a()], LiveTake.make(1, 1.0, OD.EndMode.STOP), mem))
	var live: Array = []
	while not sim.done:
		sim.step_local_tick(_idle())
		for e: SimEvent in K.events_of(sim.drain_events(), SimEventType.BOSS_RECALL):
			live.append(e.sub)
	var res := _fight(_mem_level(), [_tape_a(), sim.live_tape()], mem)
	var resolved: Array = []
	for e: SimEvent in K.events_of(res.events, SimEventType.BOSS_RECALL):
		resolved.append(e.sub)
	assert_eq(resolved, live)
	assert_eq(live, [START_SUB])


func test_BOSS02_it_handles_one_memory_at_a_time_a_second_dwell_overlapping_is_skipped() -> void:
	var twin := _tape_a().copy()
	twin.index = 3
	var mem := BossMemoryLib.build_boss_memory(_mem_level(), [_tape_a(), twin])
	var res := _fight(_mem_level(), [_tape_a(), twin], mem)
	assert_eq(_tapes_of(K.events_of(res.events, SimEventType.BOSS_RECALL)), [0])


# ───────────────────────────── port addition: beatSight forecast ─────────────────────────────

func test_beatSight_boss_forecast_lists_its_bar_grid_and_planned_memory_strikes() -> void:
	var sim: ODSim = ODSim.create_sim(SimConfig.make(_mem_level(), K.base_loadout(), [_tape_a()], null, _memory()))
	var e: EnemyState = sim.enemy_by_id("b1")
	var out: Array[int] = []
	assert_true(e.beh.forecast_attack_subs(sim, e, 0, 8 * SPB, out))
	out.sort()
	# The memory strike lands on beat 3; base cleaves on bar lines 4 and 8 would overlap it or not:
	# beat 4's telegraph (from beat 2) overlaps the memory strike (beats 1..3 + 1 recovery) -> skipped.
	assert_has(out, LAND_SUB, "the memory strike")
	assert_false(out.has(4 * SPB), "the bar-4 cleave clashes with the memory strike")
	assert_has(out, 8 * SPB, "the bar-8 cleave")
	# It is what really happens.
	var res := _fight(_mem_level(), [_tape_a()], _memory())
	var landed: Array[int] = []
	for a: SimEvent in K.events_of(res.events, SimEventType.ENEMY_ATTACK, -1, "b1"):
		if a.sub <= 8 * SPB:
			landed.append(a.sub)
	for s: int in landed:
		assert_has(out, s, "landing %d was forecast" % s)


func test_beatSight_phase_3_halves_the_forecast_grid() -> void:
	var sim: ODSim = ODSim.create_sim(SimConfig.make(_phase_level(), K.base_loadout(), [_holder(480)]))
	var e: EnemyState = sim.enemy_by_id("b1")
	e.mem[BossBehaviour.MEM_PHASE] = 3
	var out: Array[int] = []
	e.beh.forecast_attack_subs(sim, e, 0, 8 * SPB, out)
	out.sort()
	assert_eq(out, [2 * SPB, 4 * SPB, 6 * SPB, 8 * SPB])
