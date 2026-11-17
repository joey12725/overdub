extends ODTest
## Gear abilities that are simulation rules (AbilityId): manualDesync, lowProfile, loudmouth,
## beatSight, laserProof, heavyStep, phaseDodge, slideStrike, parry, killRefresh.
## Port of prototype/tests/core/weapons/abilities.test.ts.

var SLEEP: SignalExpr = SignalExpr.of_const(false)

# ───────────────────────────── helpers ─────────────────────────────


## { kind: 'enemy', id: 't1', type: 'turret', x, y, facing: π, ...extra } (TestScript.enemy options).
func _turret_at(x: float, y: float, extra: Dictionary = {}) -> EnemyDef:
	var o := {"facing": PI}
	o.merge(extra, true)
	return TestScript.enemy("t1", EnemyType.TURRET, x, y, o)


func _abilities(ids: Array[StringName]) -> ResolvedLoadout:
	return TestLoadout.base_loadout({"abilities": ids})


func _ev_pairs(events: Array[SimEvent]) -> Array:
	var out: Array = []
	for e: SimEvent in events:
		out.append([e.sub, e.detail])
	return out


## The actor of tape `tape` in the first frame at or after `sub`.
func _actor(res: Resolution, sub: int, tape: int = 0) -> ActorSnap:
	return TestScript.frame_at(res, sub).actor(tape)


## OPEN_ROOM with the interior of column `col` replaced: `fill` everywhere, `gap` (if not "") on row `gap_row`.
func _column_map(col: int, fill: String, gap_row: int = -1, gap: String = "") -> Array[String]:
	var map: Array[String] = []
	var n := TestLevels.OPEN_ROOM.size()
	for r in n:
		var row: String = TestLevels.OPEN_ROOM[r]
		if r == 0 or r == n - 1:
			map.append(row)
		else:
			map.append(row.substr(0, col) + (gap if r == gap_row else fill) + row.substr(col + 1))
	return map

# ───────────────────────────── manualDesync ─────────────────────────────


func _md_level() -> LevelDef:
	return TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.5, 5.5)})


func _md_take() -> TestScript.TakeResult:
	var sc := TestScript.input_script().run(0, 120, 1, 0).press(20, ActionKind.ABILITY).press(80, ActionKind.ABILITY)
	return TestScript.record_take(_md_level(), 0, 1.0, sc, [], _abilities([AbilityId.MANUAL_DESYNC]), OD.EndMode.STOP, 160)


func test_manual_desync_live_first_press_desyncs_and_holds_the_spark_second_resyncs_in_place() -> void:
	var take := _md_take()
	var des := TestScript.events_of(take.events, SimEventType.DESYNC, 0)
	assert_eq(_ev_pairs(des), [[80, "manual desync"]], "desync")
	var res := TestScript.events_of(take.events, SimEventType.RESYNC, 0)
	assert_eq(_ev_pairs(res), [[320, "manual desync"]], "resync")
	# frames[i] is the snapshot after local tick i (sub 4(i + 1)).
	var first: ActorSnap = take.frames[21].actors[0]
	assert_true(first.has_spark, "spark present")
	var spark: Vector2 = first.spark
	var held := true
	for i in range(21, 80):
		var a: ActorSnap = take.frames[i].actors[0]
		if a.synced or not a.has_spark or a.spark != spark:
			held = false
	assert_true(held, "desynced with the spark held still for frames 21..79")
	# ActorSnap.spark is a Vector2 (float32 components in Godot), so compare within float32 precision.
	if des.size() > 0:
		assert_near(spark.x, des[0].x, 1e-5, "spark where the body was")
	# The body ran on meanwhile; after the second press it is synced exactly where it is.
	var after: ActorSnap = take.frames[80].actors[0]
	assert_true(after.synced, "synced after the second press")
	assert_false(after.has_spark, "no spark after the second press")
	assert_true(after.x > spark.x + 3.0, "body ran on (%f vs %f)" % [after.x, spark.x])


func test_manual_desync_playback_released_spark_catches_up_by_ordinary_spark_rules() -> void:
	var take := _md_take()
	var loadout := _abilities([AbilityId.MANUAL_DESYNC])
	var res := TestScript.resolve(_md_level(), [take.tape], loadout)
	assert_eq(_ev_pairs(TestScript.events_of(res.events, SimEventType.DESYNC, 0)), [[80, "manual desync"]], "desync")
	var s0 := _actor(res, 100)
	var s1 := _actor(res, 300)
	assert_true(s0.has_spark and s1.has_spark and s0.spark == s1.spark, "spark held from sub 100 to 300")
	var resync := TestScript.events_of(res.events, SimEventType.RESYNC, 0)
	assert_eq(resync.size(), 1, "one resync")
	if resync.size() != 1:
		return
	assert_true(resync[0].sub > 320 + 60, "resync well after the release (%d)" % resync[0].sub)
	# The spark only moves after the release, and never faster than spark speed.
	var moving: Array[Vector2] = []
	for f: FrameSnapshot in res.frames:
		if f.sub > 320 and f.sub < resync[0].sub:
			moving.append(f.actors[0].spark)
	assert_true(moving.size() > 5, "spark travels for a while")
	assert_true(moving[moving.size() - 1].x > s0.spark.x + 2.0, "spark moved toward the projection")
	assert_eq(res.outcome.survivors, [0], "survives")


func test_manual_desync_desync07_voluntarily_desynced_self_is_harmless_and_invulnerable() -> void:
	var tlv := TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.5, 5.5), "entities": [_turret_at(8.5, 5.5)]})
	var tape := TestScript.path_tape(0, 1.0, 480, [[0, 2.5, 5.5]], [[0, ActionKind.ABILITY], [30, ActionKind.LIGHT, 0.0]])
	var res := TestScript.resolve(tlv, [tape], _abilities([AbilityId.MANUAL_DESYNC]))
	assert_eq(TestScript.events_of(res.events, SimEventType.ENEMY_SHOT).size(), 0, "turret never shoots")
	assert_eq(TestScript.events_of(res.events, SimEventType.SELF_DEATH).size(), 0, "no death")
	assert_eq(TestScript.events_of(res.events, SimEventType.SWING).size(), 0, "no swing")
	assert_eq(res.outcome.survivors, [0], "survives")
	var control := TestScript.resolve(tlv, [tape], TestLoadout.base_loadout())
	assert_eq(TestScript.events_of(control.events, SimEventType.SELF_DEATH, 0).size(), 1, "without the gear it dies")


func test_manual_desync_an_involuntary_desync_is_held_by_the_next_press_so_presses_stay_paired() -> void:
	# The tape walks through a doorway that is shut in this run (desync at the door), presses at
	# ticks 60 and 300. The first press pins the stalled spark, the second lets it go again.
	var map := _column_map(5, "#", 5, ".")
	# The door is shut for beats [0, 6) and open from beat 6 on.
	var cells: Array[Vector2i] = [Vector2i(5, 5)]
	var dlv := TestLevels.make_level({"speeds": [1.0], "bars": 4, "map": map, "start": Vector2(2.5, 5.5), "entities": [TestScript.door("d1", cells, SignalExpr.of_beat(16, 6, 16))]})
	var tape := TestScript.path_tape(0, 1.0, 480, [[0, 2.5, 5.5], [40, 7.5, 5.5]], [[60, ActionKind.ABILITY], [300, ActionKind.ABILITY]])
	var res := TestScript.resolve(dlv, [tape], _abilities([AbilityId.MANUAL_DESYNC]))
	var des := TestScript.events_of(res.events, SimEventType.DESYNC, 0)
	assert_eq(des.size(), 1, "one desync")
	if des.size() > 0:
		assert_eq(des[0].detail, "blocked by door d1", "cause")
	# The door opens at beat 6 (sub 360), but the spark is pinned from tick 60 to tick 300.
	var pinned: Array[Vector2] = []
	for f: FrameSnapshot in res.frames:
		if f.sub > 60 * 4 + 4 and f.sub <= 300 * 4:
			pinned.append(f.actors[0].spark)
	var still := pinned.size() > 0
	for p: Vector2 in pinned:
		if p != pinned[0]:
			still = false
	assert_true(still, "spark pinned")
	var resync := TestScript.events_of(res.events, SimEventType.RESYNC, 0)
	assert_eq(resync.size(), 1, "one resync")
	if resync.size() > 0:
		assert_true(resync[0].sub > 300 * 4, "resync after the release")
	# Without the gear the same tape resyncs as soon as the door opens.
	var plain := TestScript.resolve(dlv, [tape])
	var pr := TestScript.events_of(plain.events, SimEventType.RESYNC, 0)
	assert_true(pr.size() > 0 and pr[0].sub < 300 * 4, "plain resync once the door opens")

# ───────────────────────────── lowProfile / loudmouth ─────────────────────────────


func test_low_profile_loudmouth_effective_distance_scales_and_both_multiply() -> void:
	var none: Array[StringName] = []
	var lp: Array[StringName] = [AbilityId.LOW_PROFILE]
	var lm: Array[StringName] = [AbilityId.LOUDMOUTH]
	var both: Array[StringName] = [AbilityId.LOW_PROFILE, AbilityId.LOUDMOUTH]
	assert_eq(Abilities.effective_distance(none, 4.0), 4.0, "none")
	assert_eq(Abilities.effective_distance(lp, 4.0), 4.0 * Abilities.LOW_PROFILE_FACTOR, "lowProfile")
	assert_eq(Abilities.effective_distance(lm, 4.0), 4.0 * Abilities.LOUDMOUTH_FACTOR, "loudmouth")
	assert_near(Abilities.effective_distance(both, 4.0), 4.0 * Abilities.LOW_PROFILE_FACTOR * Abilities.LOUDMOUTH_FACTOR, 5e-13, "both")


## A long hall: turret (reach 12) at x 2.5, the self further down the hall.
func _hall_level(self_x: float) -> LevelDef:
	var hall: Array[String] = ["#".repeat(22), "#" + ".".repeat(20) + "#", "#" + ".".repeat(20) + "#", "#" + ".".repeat(20) + "#", "#".repeat(22)]
	return TestLevels.make_level({"speeds": [1.0], "bars": 2, "map": hall, "start": Vector2(self_x, 2.5), "entities": [_turret_at(2.5, 2.5, {"facing": 0.0})]})


func _hall_tape(self_x: float) -> ODTape:
	return TestScript.path_tape(0, 1.0, 240, [[0, self_x, 2.5]])


func test_low_profile_a_self_inside_the_turret_reach_is_read_as_out_of_range() -> void:
	var lv := _hall_level(11.5) # 9 tiles: 13.5 perceived
	var tape := _hall_tape(11.5)
	assert_true(TestScript.events_of(TestScript.resolve(lv, [tape]).events, SimEventType.ENEMY_SHOT).size() > 0, "plain: shot at")
	assert_eq(TestScript.events_of(TestScript.resolve(lv, [tape], _abilities([AbilityId.LOW_PROFILE])).events, SimEventType.ENEMY_SHOT).size(), 0, "lowProfile: ignored")


func test_loudmouth_a_self_beyond_the_turret_reach_is_read_as_in_range() -> void:
	var lv := _hall_level(16.5) # 14 tiles: 10.5 perceived
	var tape := _hall_tape(16.5)
	assert_eq(TestScript.events_of(TestScript.resolve(lv, [tape]).events, SimEventType.ENEMY_SHOT).size(), 0, "plain: ignored")
	assert_true(TestScript.events_of(TestScript.resolve(lv, [tape], _abilities([AbilityId.LOUDMOUTH])).events, SimEventType.ENEMY_SHOT).size() > 0, "loudmouth: shot at")

# ───────────────────────────── beatSight ─────────────────────────────


func _bs_tape() -> ODTape:
	return TestScript.path_tape(0, 1.0, 480, [[0, 2.5, 5.5]])


func _sim(level: LevelDef, loadout: ResolvedLoadout) -> ODSim:
	var errors: Array[String] = []
	var sim := ODSim.create_sim(SimConfig.make(level, loadout, [_bs_tape()]), errors)
	assert_true(sim != null, "create_sim: %s" % ", ".join(errors))
	return sim


func test_beat_sight_lists_upcoming_attack_beats_and_they_are_the_beats_the_attacks_land_on() -> void:
	var lv := TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.5, 5.5), "entities": [_turret_at(8.5, 5.5, {"beat": [2, 0]})]})
	var sim := _sim(lv, _abilities([AbilityId.BEAT_SIGHT]))
	if sim == null:
		return
	assert_eq(sim.threat_beats(5), [2.0, 4.0], "forecast from the start")
	# During the telegraph the committed attack is listed exactly.
	while sim.sub < 180:
		sim.step_sub()
	assert_eq(sim.snapshot().enemies[0].state, EnemyStateName.TELEGRAPH, "telegraphing at sub 180")
	assert_eq(sim.threat_beats(1), [2.0], "committed attack")
	var shots: Array[float] = []
	while not sim.done:
		sim.step_sub()
		for e: SimEvent in sim.drain_events():
			if e.type == SimEventType.ENEMY_SHOT:
				shots.append(e.sub / 120.0)
	assert_true(shots.size() > 0, "the turret shoots")
	if shots.size() > 0:
		assert_eq(shots[0], 2.0, "first shot on beat 2")


func test_beat_sight_is_empty_without_the_gear_and_ignores_sleeping_and_dead_enemies() -> void:
	var lv := TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.5, 5.5), "entities": [_turret_at(8.5, 5.5, {"beat": [2, 0]})]})
	var plain := _sim(lv, TestLoadout.base_loadout())
	if plain != null:
		assert_eq(plain.threat_beats(8), [], "no gear")
	var asleep := TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.5, 5.5), "entities": [_turret_at(8.5, 5.5, {"wake": SLEEP})]})
	var sim := _sim(asleep, _abilities([AbilityId.BEAT_SIGHT]))
	if sim != null:
		assert_eq(sim.threat_beats(8), [], "sleeping turret")


func test_beat_sight_upcoming_attack_beats_falls_back_to_the_grid_rule_without_a_forecast_hook() -> void:
	# Port addition: a behaviour that does not implement forecast_attack_subs gets the prototype's
	# generic rule. The registry is restored afterwards.
	var lv := TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.5, 5.5), "entities": [_turret_at(8.5, 5.5, {"beat": [2, 0]})]})
	var sim := _sim(lv, _abilities([AbilityId.BEAT_SIGHT]))
	if sim == null:
		return
	var e: EnemyState = sim.enemies[0]
	var real: EnemyBehaviour = e.beh
	e.beh = EnemyBehaviour.new()
	# Engaged (the self is 6 tiles away, inside reach in line of sight): every grid instant whose
	# telegraph can still start from sub 0, i.e. beats 2 and 4 of every-2 within 5 beats.
	var generic := Abilities.upcoming_attack_beats(sim, 0, 5.0)
	e.beh = real
	assert_eq(generic, [2.0, 4.0], "generic rule")

# ───────────────────────────── laserProof and heavyStep ─────────────────────────────


func test_laser_proof_a_live_laser_does_not_kill() -> void:
	var lv := TestLevels.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(2.5, 5.5), "entities": [TestScript.laser("beam", Vector2(6.5, 1.5), Vector2(6.5, 8.5), SignalExpr.of_const(true))]})
	var tape := TestScript.path_tape(0, 1.0, 240, [[0, 2.5, 5.5], [120, 9.5, 5.5]])
	assert_eq(TestScript.events_of(TestScript.resolve(lv, [tape]).events, SimEventType.SELF_DEATH).size(), 1, "plain: burned")
	assert_eq(TestScript.events_of(TestScript.resolve(lv, [tape], _abilities([AbilityId.LASER_PROOF])).events, SimEventType.SELF_DEATH).size(), 0, "laserProof: survives")


func test_heavy_step_a_self_holds_a_heavy_plate() -> void:
	var lv := TestLevels.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(5.5, 5.5), "entities": [TestScript.plate("p1", 5, 5, true)]})
	var tape := TestScript.path_tape(0, 1.0, 240, [[0, 5.5, 5.5]])
	assert_eq(TestScript.events_of(TestScript.resolve(lv, [tape]).events, SimEventType.PLATE).size(), 0, "plain: plate stays up")
	var details: Array = []
	for e: SimEvent in TestScript.events_of(TestScript.resolve(lv, [tape], _abilities([AbilityId.HEAVY_STEP])).events, SimEventType.PLATE):
		details.append(e.detail)
	assert_eq(details, ["on"], "heavyStep: plate on")

# ───────────────────────────── phaseDodge ─────────────────────────────


func test_phase_dodge_a_dodge_passes_low_barriers_live_and_replays_without_desync() -> void:
	# A full column of low barriers at x ∈ [6, 7).
	var map := _column_map(6, "=")
	var lv := TestLevels.make_level({"speeds": [1.0], "bars": 2, "map": map, "start": Vector2(5.0, 5.5), "start_facing": 0.0})
	var dodge := TestScript.input_script().aim(0, 240, 0.0).press(0, ActionKind.DODGE)
	var blocked := TestScript.record_take(lv, 0, 1.0, dodge, [], null, OD.EndMode.STOP, 40)
	assert_true(blocked.frames[39].actors[0].x < 6.0, "plain dodge stops at the barrier")
	var loadout := _abilities([AbilityId.PHASE_DODGE])
	var phased := TestScript.record_take(lv, 0, 1.0, dodge, [], loadout, OD.EndMode.STOP, 40)
	assert_true(phased.frames[39].actors[0].x > 7.3, "phaseDodge crosses (x %f)" % phased.frames[39].actors[0].x)
	var res := TestScript.resolve(lv, [phased.tape], loadout)
	assert_eq(TestScript.events_of(res.events, SimEventType.DESYNC).size(), 0, "replays without desync")
	# The same tape replayed without the gear cannot cross: it desyncs at the barrier.
	assert_eq(TestScript.events_of(TestScript.resolve(lv, [phased.tape]).events, SimEventType.DESYNC, 0).size(), 1, "desyncs without the gear")

# ───────────────────────────── slideStrike ─────────────────────────────


func _swing_powers(abilities: Array[StringName]) -> Array[float]:
	var lv := TestLevels.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(2.5, 5.5), "entities": [TestScript.enemy("g1", EnemyType.GRUNT, 3.3, 5.5, {"hp": 20, "wake": SLEEP})]})
	# A dodge at tick 10 ends at tick 24; a light at 24 slides out of it, a light at 60 does not.
	var tape := TestScript.path_tape(0, 1.0, 100, [[0, 2.5, 5.5]], [[10, ActionKind.DODGE, 0.0], [24, ActionKind.LIGHT, 0.0], [60, ActionKind.LIGHT, 0.0]], OD.EndMode.REVERSE)
	var out: Array[float] = []
	for e: SimEvent in TestScript.events_of(TestScript.resolve(lv, [tape], _abilities(abilities)).events, SimEventType.SWING):
		out.append(e.power)
	return out


func test_slide_strike_mom03_a_strike_out_of_a_dodge_carries_extra_momentum_only_on_a_forward_pass() -> void:
	var plain := _swing_powers([])
	var slide := _swing_powers([AbilityId.SLIDE_STRIKE])
	# The prototype compares +power.toFixed(6); 5e-7 is the same tolerance.
	var all_plain := plain.size() > 0
	for p: float in plain:
		if absf(p - 1.2) > 5e-7:
			all_plain = false
	assert_true(all_plain, "plain swings all 1.2: %s" % [plain])
	assert_true(slide.size() >= 5, "at least five swings (%d)" % slide.size())
	if slide.size() < 5:
		return
	# Forward: [24 → slide, 60 → plain]; backward pass: 60 then 24, both plain; forward again …
	assert_array_eq(slide.slice(0, 4), [1.2 * Abilities.SLIDE_STRIKE_MUL, 1.2, 1.2, 1.2], "first four swings", 5e-7)
	assert_near(slide[4], 1.2 * Abilities.SLIDE_STRIKE_MUL, 5e-7, "fifth swing slides again")

# ───────────────────────────── parry ─────────────────────────────


func _parry_level() -> LevelDef:
	return TestLevels.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2.5, 5.5), "entities": [_turret_at(6.5, 5.5, {"beat": [8, 0]})]})


func _parry_death_sub() -> int:
	var still := TestScript.path_tape(0, 1.0, 480, [[0, 2.5, 5.5]])
	return TestScript.events_of(TestScript.resolve(_parry_level(), [still]).events, SimEventType.SELF_DEATH, 0)[0].sub


func _swinger(death_sub: int) -> ODTape:
	# Heavy windup 16 ticks, active 5: put the live window just before the bolt would touch the self.
	# Math.round: JS rounds halves up, so floor(x + 0.5).
	var heavy_tick: int = int(floor((death_sub - 24) / 4.0 + 0.5)) - 16
	return TestScript.path_tape(0, 1.0, 480, [[0, 2.5, 5.5]], [[heavy_tick, ActionKind.HEAVY, 0.0]])


func test_parry_a_heavy_swing_turns_an_enemy_shot_inside_its_arc_back_at_the_shooter() -> void:
	var res := TestScript.resolve(_parry_level(), [_swinger(_parry_death_sub())], _abilities([AbilityId.PARRY]))
	assert_eq(TestScript.events_of(res.events, SimEventType.SELF_DEATH).size(), 0, "no death")
	var parry: Array = []
	for e: SimEvent in TestScript.events_of(res.events, SimEventType.PROJECTILE_HIT):
		if e.detail == "parry":
			parry.append([e.tape, e.id])
	assert_eq(parry, [[0, "t1"]], "parry event")
	# The reflected bolt belongs to the tape and destroys the turret that fired it.
	var kills: Array = []
	for e: SimEvent in TestScript.events_of(res.events, SimEventType.KILL, -1, "t1"):
		kills.append([e.tape, e.detail])
	assert_eq(kills, [[0, "bolt"]], "reflected bolt kills the turret")
	assert_eq(TestScript.events_of(res.events, SimEventType.WHIFF).size(), 0, "no whiff")
	assert_true(res.outcome.win, "win")


func test_parry_without_the_gear_the_same_swing_does_nothing_to_the_shot() -> void:
	var death_sub := _parry_death_sub()
	var res := TestScript.resolve(_parry_level(), [_swinger(death_sub)])
	var deaths: Array = []
	for e: SimEvent in TestScript.events_of(res.events, SimEventType.SELF_DEATH, 0):
		deaths.append(e.sub)
	assert_eq(deaths, [death_sub], "dies as without the swing")
	var parry := 0
	for e: SimEvent in TestScript.events_of(res.events, SimEventType.PROJECTILE_HIT):
		if e.detail == "parry":
			parry += 1
	assert_eq(parry, 0, "no parry")

# ───────────────────────────── killRefresh ─────────────────────────────


func test_kill_refresh_a_melee_kill_by_the_live_self_refunds_its_dodge_cooldown() -> void:
	var lv0 := TestLevels.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(8.5, 5.5), "start_facing": PI})
	var s := TestScript.input_script().aim(0, 240, PI).press(0, ActionKind.DODGE).press(14, ActionKind.LIGHT, PI).press(26, ActionKind.DODGE)
	# Where the self is when the light swing's hit frame comes (tick 20).
	var probe := TestScript.record_take(lv0, 0, 1.0, TestScript.input_script().aim(0, 240, PI).press(0, ActionKind.DODGE).press(14, ActionKind.LIGHT, PI), [], null, OD.EndMode.STOP, 30)
	var at: ActorSnap = probe.frames[20].actors[0]
	var lv := TestLevels.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(8.5, 5.5), "start_facing": PI, "entities": [TestScript.enemy("g1", EnemyType.GRUNT, at.x - 0.8, at.y, {"wake": SLEEP})]})
	var dodges := func(abilities: Array[StringName]) -> Array:
		var take := TestScript.record_take(lv, 0, 1.0, s, [], _abilities(abilities), OD.EndMode.STOP, 60)
		var ticks: Array = []
		for e: TapeEvent in take.tape.events:
			if e.kind == ActionKind.DODGE:
				ticks.append(e.tick)
		return ticks
	var with_gear := TestScript.record_take(lv, 0, 1.0, s, [], _abilities([AbilityId.KILL_REFRESH]), OD.EndMode.STOP, 60)
	assert_eq(TestScript.events_of(with_gear.events, SimEventType.KILL, -1, "g1").size(), 1, "g1 killed")
	var kr: Array[StringName] = [AbilityId.KILL_REFRESH]
	var none: Array[StringName] = []
	assert_eq(dodges.call(kr), [0, 26], "killRefresh: second dodge allowed")
	# Without the gear the second press falls inside the cooldown and is dropped from the buffer.
	assert_eq(dodges.call(none), [0], "plain: second dodge dropped")
