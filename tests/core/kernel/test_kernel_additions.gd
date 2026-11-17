extends ODTest
## Kernel behaviour the Godot port adds beyond the prototype (the prototype engineers' reported gaps):
##   1. a self's projectile strikes breakables and cores with its momentum under the threshold rule
##      ('clang' when too weak); a 'phase' shot passes an unbroken breakable without striking it;
##   2. EnemyBehaviour.forecast_attack_subs (grunt, turret) feeding the 'beatSight' forecast;
##   3. ODResolve.resolve_encounter on a worker thread, with progress and cooperative cancel.

const S = preload("res://tests/helpers/script.gd")


func _has_note(r: Resolution, pattern: String) -> bool:
	var re := RegEx.create_from_string(pattern)
	for n: String in r.outcome.notes:
		if re.search(n) != null:
			return true
	return false


## A straight 'pierce' weapon (no pierce count) of the given impact: 12 tiles/s, 20 tiles of range.
func _gun(archetype: StringName, impact: float) -> ResolvedLoadout:
	return TestLoadout.base_loadout({"ranged": {"archetype": archetype, "speed": 12.0, "range": 20.0, "impact": impact, "pierce": 0, "commit": 12}})


## Tape A stands at (2.5, 5.5) and fires east on local tick 10.
func _shooter() -> ODTape:
	return S.path_tape(0, 1.0, 120, [[0, 2.5, 5.5]], [[10, ActionKind.RANGED, 0.0]])


## A breakable wall at tile (6, 5) (threshold 5) across the shot's line, a sleeping grunt behind it.
func _wall_level() -> LevelDef:
	var ents: Array[EntityDef] = [
		S.breakable("w1", 6, 5, Tuning.TUTORIAL_WALL_THRESHOLD),
		S.enemy("g1", EnemyType.GRUNT, 9.5, 5.5, {"wake": SignalExpr.of_const(false)}),
	]
	return TestLevels.make_level(
		{
			"speeds": [1.0],
			"bars": 1,
			"start": Vector2(2.5, 5.5),
			"entities": ents,
			"objective": S.objective(ObjectiveType.SIGNAL, "Break the wall", [], SignalExpr.of_sig("w1")),
		}
	)

# ───────────────────────────── 1. projectiles strike objects ─────────────────────────────


func test_ScenarioK_a_weak_self_projectile_clangs_on_a_breakable_and_the_outcome_names_the_missing_momentum() -> void:
	var res: Resolution = S.resolve(_wall_level(), [_shooter()], _gun(RangedArchetype.PIERCE, 1.2))
	var clang: Array[SimEvent] = S.events_of(res.events, SimEventType.CLANG, 0, "w1")
	assert_eq(clang.size(), 1)
	if clang.size() == 1:
		assert_near(clang[0].power, 1.2, 1e-9)
		assert_eq(clang[0].detail, "needs 5")
	assert_eq(S.events_of(res.events, SimEventType.BREAK).size(), 0)
	assert_false(res.frames[res.frames.size() - 1].mech("w1").on)
	# The shot stopped at the wall; the grunt behind it was never touched.
	var walls: Array[SimEvent] = []
	for e: SimEvent in S.events_of(res.events, SimEventType.PROJECTILE_HIT):
		if e.detail == "pierce:wall":
			walls.append(e)
	assert_eq(walls.size(), 1)
	if walls.size() == 1:
		# Like every wall stop (prototype flyStraight), the shot's centre stops at the tile face.
		assert_near(walls[0].x, 6.0, 1e-6, "stops at the wall face")
	assert_eq(S.events_of(res.events, SimEventType.HIT, -1, "g1").size(), 0)
	assert_false(res.outcome.win)
	assert_true(
		_has_note(res, "Tape A's pierce at beat [\\d.]+ hit breakable wall w1 with momentum 1\\.2; it needs 5\\."),
		"notes: %s" % [res.outcome.notes]
	)


func test_ScenarioK_a_self_projectile_with_enough_momentum_breaks_the_breakable_and_stops_there() -> void:
	var res: Resolution = S.resolve(_wall_level(), [_shooter()], _gun(RangedArchetype.PIERCE, 6.0))
	var brk: Array[SimEvent] = S.events_of(res.events, SimEventType.BREAK, 0, "w1")
	assert_eq(brk.size(), 1)
	if brk.size() == 1:
		assert_near(brk[0].power, 6.0, 1e-9)
		assert_eq(brk[0].detail, "pierce")
	assert_eq(S.events_of(res.events, SimEventType.HIT, 0, "w1").size(), 1)
	assert_eq(S.events_of(res.events, SimEventType.CLANG).size(), 0)
	assert_true(res.frames[res.frames.size() - 1].mech("w1").on)
	assert_true(res.outcome.win)
	# The shot spent itself on the wall: the grunt behind it is untouched.
	assert_eq(S.events_of(res.events, SimEventType.HIT, -1, "g1").size(), 0)
	assert_true(res.frames[res.frames.size() - 1].enemy("g1").alive)


func test_ScenarioK_a_phase_shot_passes_an_unbroken_breakable_without_striking_it() -> void:
	var res: Resolution = S.resolve(_wall_level(), [_shooter()], _gun(RangedArchetype.PHASE, 6.0))
	assert_eq(S.events_of(res.events, SimEventType.FIRE).size(), 1)
	assert_eq(S.events_of(res.events, SimEventType.CLANG).size(), 0)
	assert_eq(S.events_of(res.events, SimEventType.BREAK).size(), 0)
	assert_false(res.frames[res.frames.size() - 1].mech("w1").on)
	# It flew through the wall and struck the grunt behind it.
	assert_eq(S.events_of(res.events, SimEventType.KILL, 0, "g1").size(), 1)


func test_enemy_bolts_never_strike_breakables() -> void:
	# A weak breakable (threshold 0.5, below a bolt's momentum 1) between a turret and the west wall.
	var ents: Array[EntityDef] = [
		S.breakable("w1", 6, 5, 0.5),
		S.enemy("t1", EnemyType.TURRET, 9.5, 5.5, {"facing": PI}),
	]
	var level: LevelDef = TestLevels.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(2.5, 5.5), "entities": ents})
	var sim: ODSim = ODSim.create_sim(SimConfig.make(level, TestLoadout.base_loadout(), []))
	# Fire a bolt from the turret straight at the breakable.
	ProjectileSystem.spawn_bolt(sim, sim.enemy_by_id("t1"), PI)
	while sim.sub < 240:
		sim.step_sub()
	var evs: Array[SimEvent] = sim.drain_events()
	assert_eq(S.events_of(evs, SimEventType.CLANG).size(), 0)
	assert_eq(S.events_of(evs, SimEventType.BREAK).size(), 0)
	var walls: Array[SimEvent] = []
	for e: SimEvent in S.events_of(evs, SimEventType.PROJECTILE_HIT):
		if e.detail == "bolt:wall":
			walls.append(e)
	assert_eq(walls.size(), 1)
	if walls.size() == 1:
		assert_near(walls[0].x, 7.0, 1e-6, "stopped on the breakable's east face")
	assert_false(sim.snapshot().mech("w1").on)


func _core_level(threshold: float) -> LevelDef:
	var ents: Array[EntityDef] = [S.core_def("c1", 7.0, 5.5, threshold)]
	return TestLevels.make_level(
		{
			"speeds": [1.0],
			"bars": 1,
			"start": Vector2(2.5, 5.5),
			"entities": ents,
			"objective": S.objective(ObjectiveType.ACTIVATE, "Light the core"),
		}
	)


func test_a_self_projectile_activates_a_core_with_enough_momentum_and_stops_on_it() -> void:
	var res: Resolution = S.resolve(_core_level(1.0), [_shooter()], _gun(RangedArchetype.PIERCE, 1.2))
	assert_eq(S.events_of(res.events, SimEventType.CORE, 0, "c1").size(), 1)
	assert_eq(S.events_of(res.events, SimEventType.HIT, 0, "c1").size(), 1)
	var stops: Array[SimEvent] = S.events_of(res.events, SimEventType.PROJECTILE_HIT, -1, "c1")
	assert_eq(stops.size(), 1)
	if stops.size() == 1:
		assert_near(stops[0].x, 7.0 - Combat.CORE_RADIUS - Tuning.SELF_SHOT_RADIUS, 1e-6, "stops on the core's body")
	assert_true(res.outcome.win)


func test_a_weak_self_projectile_clangs_on_a_core_and_is_noted() -> void:
	var res: Resolution = S.resolve(_core_level(3.0), [_shooter()], _gun(RangedArchetype.PIERCE, 1.2))
	var clang: Array[SimEvent] = S.events_of(res.events, SimEventType.CLANG, 0, "c1")
	assert_eq(clang.size(), 1)
	if clang.size() == 1:
		assert_eq(clang[0].detail, "needs 3")
	assert_eq(S.events_of(res.events, SimEventType.CORE).size(), 0)
	assert_false(res.outcome.objective_complete)
	assert_true(_has_note(res, "Tape A's pierce at beat [\\d.]+ hit core c1 with momentum 1\\.2; it needs 3\\."), "notes: %s" % [res.outcome.notes])


func test_an_already_active_core_lets_later_shots_pass() -> void:
	var t: ODTape = S.path_tape(0, 1.0, 120, [[0, 2.5, 5.5]], [[10, ActionKind.RANGED, 0.0], [40, ActionKind.RANGED, 0.0]])
	var res: Resolution = S.resolve(_core_level(1.0), [t], _gun(RangedArchetype.PIERCE, 1.2))
	assert_eq(S.events_of(res.events, SimEventType.FIRE).size(), 2)
	assert_eq(S.events_of(res.events, SimEventType.HIT, 0, "c1").size(), 1)
	assert_eq(S.events_of(res.events, SimEventType.PROJECTILE_HIT, -1, "c1").size(), 1)

# ───────────────────────────── 2. behaviour attack forecasts (beatSight) ─────────────────────────────


func _forecast(sim: ODSim, id: String, look_beats: float = 8.0) -> Array[int]:
	var e: EnemyState = sim.enemy_by_id(id)
	var out: Array[int] = []
	var end_sub: int = sim.sub + int(look_beats * sim.spb)
	assert_true(e.beh.forecast_attack_subs(sim, e, sim.sub, end_sub, out), "%s has its own forecast" % e.type)
	out.sort()
	return out


func _playback(level: LevelDef, tapes: Array[ODTape], abilities: Array = []) -> ODSim:
	return ODSim.create_sim(SimConfig.make(level, TestLoadout.base_loadout({"abilities": abilities}), tapes))


func test_AI07_beatSight_a_grunt_in_reach_forecasts_every_grid_beat_it_can_still_telegraph_for() -> void:
	var ents: Array[EntityDef] = [S.enemy("g1", EnemyType.GRUNT, 6.0, 5.5)]
	var level: LevelDef = TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(5.4, 5.5), "entities": ents})
	var sim: ODSim = _playback(level, [S.path_tape(0, 1.0, 480, [[0, 5.4, 5.5]])])
	# At sub 0: grid every 2 beats (240 subs), telegraph 60 subs. The beat-0 instant cannot be
	# telegraphed for any more; 240, 480, ... up to 8 beats (960) can.
	assert_eq(_forecast(sim, "g1"), [240, 480, 720, 960])
	# It really strikes on the first of them.
	while sim.sub < 241:
		sim.step_sub()
	var attacks: Array[SimEvent] = S.events_of(sim.drain_events(), SimEventType.ENEMY_ATTACK, -1, "g1")
	assert_eq(attacks.size(), 1)
	if attacks.size() == 1:
		assert_eq(attacks[0].sub, 240)


func test_AI07_beatSight_a_telegraphing_grunt_forecasts_its_committed_strike_and_the_recovery_gap() -> void:
	var ents: Array[EntityDef] = [S.enemy("g1", EnemyType.GRUNT, 6.0, 5.5)]
	var level: LevelDef = TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(5.4, 5.5), "entities": ents})
	var sim: ODSim = _playback(level, [S.path_tape(0, 1.0, 480, [[0, 5.4, 5.5]])])
	while sim.sub < 200:
		sim.step_sub()
	assert_eq(sim.enemy_by_id("g1").state, EnemyStateName.TELEGRAPH)
	# Window [200, 680]: the committed strike at 240, then the grid instant 480 (240 subs later, past
	# telegraph 60 + recovery 30); 720 is outside the window.
	assert_eq(_forecast(sim, "g1", 4.0), [240, 480])


func test_AI07_beatSight_a_far_grunt_forecasts_only_the_grid_beats_it_can_walk_into_reach_for() -> void:
	var ents: Array[EntityDef] = [S.enemy("g1", EnemyType.GRUNT, 10.0, 5.5)]
	var level: LevelDef = TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.0, 5.5), "entities": ents})
	var sim: ODSim = _playback(level, [S.path_tape(0, 1.0, 480, [[0, 2.0, 5.5]])])
	# 8 tiles away, reach 0.9, walk 2.2 t/s: it needs (8 - 0.9) / 2.2 = 3.23 s = 775 subs before it
	# can plant, so the first possible strike is the grid instant 960 (telegraph from 900).
	assert_eq(_forecast(sim, "g1", 10.0), [960, 1200])


func test_AI07_beatSight_a_grunt_with_nobody_to_target_forecasts_nothing() -> void:
	var ents: Array[EntityDef] = [S.enemy("g1", EnemyType.GRUNT, 6.0, 5.5)]
	var level: LevelDef = TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(5.4, 5.5), "entities": ents})
	var sim: ODSim = _playback(level, [])
	assert_eq(_forecast(sim, "g1"), [])


func test_AI07_beatSight_a_turret_forecasts_its_grid_only_while_someone_is_shootable() -> void:
	var ents: Array[EntityDef] = [S.enemy("t1", EnemyType.TURRET, 10.5, 5.5, {"facing": PI, "arc": PI})]
	var level: LevelDef = TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(3.0, 5.5), "entities": ents})
	var sim: ODSim = _playback(level, [S.path_tape(0, 1.0, 480, [[0, 3.0, 5.5]])])
	# Grid every 2 beats, telegraph 1 beat: from sub 0 the instants 240 .. 960.
	assert_eq(_forecast(sim, "t1"), [240, 480, 720, 960])
	# Behind its aim arc nobody is shootable: no forecast.
	var behind: LevelDef = TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(3.0, 5.5), "entities": ents})
	var sim2: ODSim = _playback(behind, [S.path_tape(0, 1.0, 480, [[0, 10.9, 7.5]])])
	assert_eq(_forecast(sim2, "t1"), [])


func test_beatSight_threat_beats_uses_the_behaviour_forecasts() -> void:
	var ents: Array[EntityDef] = [S.enemy("g1", EnemyType.GRUNT, 10.0, 5.5)]
	var level: LevelDef = TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.0, 5.5), "entities": ents})
	var tapes: Array[ODTape] = [S.path_tape(0, 1.0, 480, [[0, 2.0, 5.5]])]
	var with_sight: ODSim = _playback(level, tapes, [AbilityId.BEAT_SIGHT])
	assert_eq(with_sight.threat_beats(10.0), [8.0, 10.0])
	var without: ODSim = _playback(level, tapes)
	assert_eq(without.threat_beats(10.0), [])

# ───────────────────────────── 3. worker thread, progress, cancel ─────────────────────────────


func _busy_config() -> SimConfig:
	var ents: Array[EntityDef] = [
		S.enemy("g1", EnemyType.GRUNT, 9.5, 2.5),
		S.enemy("t1", EnemyType.TURRET, 10.5, 8.5, {"facing": PI}),
		S.switch_def("sw", 4.5, 2.5),
		S.door("d1", [Vector2i(7, 5)], SignalExpr.of_sig("sw")),
	]
	var level: LevelDef = TestLevels.make_level({"speeds": [0.5, 1.0, 2.0], "bars": 2, "start": Vector2(2.5, 5.5), "entities": ents})
	var tapes: Array[ODTape] = [
		S.path_tape(0, 1.0, 240, [[0, 2.5, 5.5], [60, 4.5, 3.0], [200, 9.0, 3.0]], [[70, ActionKind.INTERACT], [210, ActionKind.LIGHT, 0.0]]),
		S.path_tape(1, 2.0, 240, [[0, 2.5, 5.5], [120, 9.5, 7.5]], [[130, ActionKind.HEAVY, 0.0]], OD.EndMode.REPEAT),
	]
	return SimConfig.make(level, TestLoadout.base_loadout(), tapes)


func test_REC06_resolve_encounter_on_a_worker_thread_matches_the_main_thread_and_reports_progress() -> void:
	ODCore.ensure_registered()
	var cfg: SimConfig = _busy_config()
	var main: Resolution = ODResolve.resolve_encounter(cfg)
	var reports: Array[float] = []
	var mutex := Mutex.new()
	var progress := func(f: float) -> void:
		mutex.lock()
		reports.append(f)
		mutex.unlock()
	var thread := Thread.new()
	thread.start(ODResolve.resolve_encounter.bind(cfg.deep_copy(), progress))
	var res: Resolution = thread.wait_to_finish()
	assert_true(res != null)
	if res == null:
		return
	assert_json_eq(res.to_dict(), main.to_dict())
	assert_true(reports.size() >= 3, "progress reports: %s" % [reports])
	assert_eq(reports[0], 0.0)
	assert_eq(reports[reports.size() - 1], 1.0)
	var monotone: bool = true
	for i: int in range(1, reports.size()):
		monotone = monotone and reports[i] >= reports[i - 1]
	assert_true(monotone)


func test_REC06_a_cancelled_resolve_stops_early_and_returns_null() -> void:
	ODCore.ensure_registered()
	var token := ODResolve.CancelToken.new()
	var seen: Array[float] = []
	# Cancel from the progress callback at the first report past the start.
	var progress := func(f: float) -> void:
		seen.append(f)
		if f > 0.0:
			token.cancel()
	var errors: Array[String] = []
	var res: Resolution = ODResolve.resolve_encounter(_busy_config(), progress, token, errors)
	assert_true(res == null)
	assert_eq(errors, ["resolve cancelled"])
	assert_true(seen.size() == 2, "stopped at the next check: %s" % [seen])


func test_resolve_encounter_with_an_invalid_config_returns_null_with_the_reason() -> void:
	var cfg: SimConfig = _busy_config()
	cfg.tapes.append(cfg.tapes[0].copy())
	var errors: Array[String] = []
	assert_true(ODResolve.resolve_encounter(cfg, Callable(), null, errors) == null)
	assert_eq(errors, ["Two tapes share cassette index 0"])
