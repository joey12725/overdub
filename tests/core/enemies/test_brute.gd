extends ODTest
## Brute (HEALTH-02, MOM-01..05, AI-04, AI-07): 3 hit points, poise against weak hits, a
## high-momentum hit still shoves it, and a slow, wide slam on its beat grid.
## Port of prototype/tests/core/enemies/brute.test.ts.

const K = preload("res://tests/core/enemies/test_enemy_kit.gd")
const SPB: int = 120


func _sleeper(type: StringName, hp: int = -1, x: float = 6, y: float = 5) -> EnemyDef:
	var o := {"asleep": true}
	if hp >= 0:
		o["hp"] = hp
	return K.enemy("b1", type, x, y, o)


func _level(type: StringName, hp: int = -1) -> LevelDef:
	return K.make_level({"speeds": [1.0, 2.0], "bars": 2, "start": Vector2(4.9, 5), "entities": [_sleeper(type, hp)]})


## A self standing west of the enemy, swinging east on the given ticks.
func _swings(ticks: Array, kind: StringName = ActionKind.LIGHT, speed: float = 1.0) -> ODTape:
	var evs: Array = []
	for t: Variant in ticks:
		evs.append([int(t), kind, 0.0])
	return K.path_tape(0, speed, 240, [[0, 4.9, 5]], evs)


func test_HEALTH02_three_standing_lights_kill_it_the_first_two_do_not_move_or_stagger_it() -> void:
	var res := K.resolve(_level(EnemyType.BRUTE), [_swings([20, 60, 100])])
	var hits := K.events_of(res.events, SimEventType.HIT, -1, "b1")
	assert_eq(hits.size(), 3)
	var kills := K.events_of(res.events, SimEventType.KILL, -1, "b1")
	assert_eq(kills.size(), 1)
	if hits.size() == 3 and kills.size() == 1:
		assert_eq(kills[0].sub, hits[2].sub)
		var before := K.frame_at(res, hits[2].sub - 4).enemies[0]
		assert_eq([before.x, before.y, before.hp], [6, 5, 1])
	assert_eq(K.events_of(res.events, SimEventType.ENEMY_STAGGER, -1, "b1").size(), 0)


func test_MOM05_the_same_light_shoves_a_grunt_but_not_a_brute() -> void:
	var grunt := K.resolve(_level(EnemyType.GRUNT, 3), [_swings([20])])
	var brute := K.resolve(_level(EnemyType.BRUTE), [_swings([20])])
	assert_true(K.frame_at(grunt, 200).enemies[0].x > 7.0, "grunt shoved")
	assert_eq(K.frame_at(brute, 200).enemies[0].x, 6.0)


func test_MOM05_a_hit_at_or_above_its_poise_threshold_really_moves_and_staggers_it() -> void:
	# 2x standing heavy: momentum 2 x 2 = 4 >= BRUTE_POISE_MOMENTUM. hp raised so it survives.
	assert_true(4.0 >= BruteBehaviour.BRUTE_POISE_MOMENTUM)
	var res := K.resolve(_level(EnemyType.BRUTE, 10), [_swings([20], ActionKind.HEAVY, 2.0)])
	var hit: SimEvent = K.events_of(res.events, SimEventType.HIT, -1, "b1")[0]
	assert_near(hit.power, 4.0, 1e-6)
	assert_eq(K.events_of(res.events, SimEventType.ENEMY_STAGGER, -1, "b1").size(), 1)
	var after := K.frame_at(res, hit.sub + 120).enemies[0]
	# knockback = momentum / mass = 4 / 3 tiles, straight along the swing.
	assert_near(after.x, 6.0 + 4.0 / Tuning.enemy_stats(EnemyType.BRUTE).mass, 5e-4)
	assert_eq(after.hp, 10 - 4)


func test_MOM01_one_running_heavy_is_the_momentum_lesson_it_kills_outright() -> void:
	# Running east at (slightly over) full run speed when the heavy starts: approach clamps to 1, so
	# momentum 2 x (1 + 0.5) = 3 = 3 damage (tuning tests assert the same arithmetic).
	var lvl := K.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(1.5, 5), "entities": [_sleeper(EnemyType.BRUTE, -1, 5.9)]})
	var run_in := K.path_tape(0, 1.0, 240, [[0, 1.5, 5], [40, 4.8, 5]], [[39, ActionKind.HEAVY, 0.0]])
	var res := K.resolve(lvl, [run_in])
	assert_near(K.events_of(res.events, SimEventType.HIT, -1, "b1")[0].power, 3.0, 5e-5)
	assert_eq(K.events_of(res.events, SimEventType.KILL, -1, "b1").size(), 1)


func _slam_level() -> LevelDef:
	return K.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(4.9, 5), "entities": [K.enemy("b1", EnemyType.BRUTE, 6, 5)]})


# A stands in front (nearest: its target). B stands off its flank, 90 deg from where it will face.
func _a() -> ODTape:
	return K.path_tape(0, 1.0, 240, [[0, 4.9, 5]])


func _b() -> ODTape:
	return K.path_tape(1, 1.0, 240, [[0, 6, 3.6]])


func test_AI07_telegraphs_for_telegraphBeats_and_lands_on_its_grid_beat() -> void:
	var res := K.resolve(_slam_level(), [_a()])
	var attacks := K.events_of(res.events, SimEventType.ENEMY_ATTACK, -1, "b1")
	assert_true(attacks.size() > 0, "it slams")
	for at: SimEvent in attacks:
		assert_eq((at.sub - 2 * SPB) % (4 * SPB), 0, "every 4, offset 2")
	var tel := K.events_of(res.events, SimEventType.ENEMY_TELEGRAPH, -1, "b1")
	assert_eq(float(tel[0].sub), attacks[0].sub - Tuning.enemy_stats(EnemyType.BRUTE).telegraph_beats * SPB)
	assert_eq(tel[0].detail, "slam")
	var death: SimEvent = K.events_of(res.events, SimEventType.SELF_DEATH, 0)[0]
	assert_eq(death.sub, attacks[0].sub)
	assert_eq(death.detail, "struck by brute b1")


func test_AI04_the_slam_is_wide_it_also_catches_a_self_standing_at_its_side() -> void:
	var res := K.resolve(_slam_level(), [_a(), _b()])
	var attack: SimEvent = K.events_of(res.events, SimEventType.ENEMY_ATTACK, -1, "b1")[0]
	var deaths: Array = []
	for d: SimEvent in K.events_of(res.events, SimEventType.SELF_DEATH):
		deaths.append([d.tape, d.sub])
	assert_eq(deaths, [[0, attack.sub], [1, attack.sub]])


func test_its_body_holds_a_heavy_plate() -> void:
	var lvl := K.make_level({
		"speeds": [1.0],
		"bars": 1,
		"start": Vector2(2, 2),
		"entities": [_sleeper(EnemyType.BRUTE, -1, 6.5, 5.5), K.plate("p1", 6, 5, true)],
	})
	var res := K.resolve(lvl, [K.path_tape(0, 1.0, 120, [[0, 2, 2]])])
	assert_true(res.frames[2].mech("p1").on, "plate held")


# ───────────────────────────── port addition: beatSight forecast ─────────────────────────────

func test_beatSight_chaser_forecast_lists_its_reachable_grid_instants() -> void:
	var sim: ODSim = ODSim.create_sim(SimConfig.make(_slam_level(), K.base_loadout(), [_a()]))
	var e: EnemyState = sim.enemy_by_id("b1")
	var out: Array[int] = []
	assert_true(e.beh.forecast_attack_subs(sim, e, 0, 8 * SPB, out), "the brute forecasts itself")
	out.sort()
	assert_eq(out, [2 * SPB, 6 * SPB], "its grid (every 4, offset 2), self already in reach")
	var res := K.resolve(_slam_level(), [_a()])
	assert_eq(K.events_of(res.events, SimEventType.ENEMY_ATTACK, -1, "b1")[0].sub, out[0], "the first is real")
	# A quarry 6 tiles away cannot be reached (1.4 tiles/s) before the beat-2 telegraph must start.
	var far := K.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(1.5, 5), "entities": [K.enemy("b1", EnemyType.BRUTE, 8, 5)]})
	var sim2: ODSim = ODSim.create_sim(SimConfig.make(far, K.base_loadout(), [K.still(0, 1.5, 5, 240)]))
	var e2: EnemyState = sim2.enemy_by_id("b1")
	var out2: Array[int] = []
	e2.beh.forecast_attack_subs(sim2, e2, 0, 8 * SPB, out2)
	assert_false(out2.has(2 * SPB), "too far for beat 2")
