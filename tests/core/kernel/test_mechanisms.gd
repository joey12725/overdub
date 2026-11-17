extends ODTest
## Kernel: mechanisms, bodies under closing doors, objectives and the extension hooks.
## Port of prototype/tests/core/kernel/mechanisms.test.ts.
##
## Port note: the prototype's vitest files each got fresh module state, so its extension-hook tests
## could replace the 'pierce' archetype and the 'manualDesync' handler for good. Here every suite
## shares the process, so those tests restore what they replaced.

const S = preload("res://tests/helpers/script.gd")


## A room with a single door cell at (6, 5), closed while switch "sw" is on.
func _door_room(extra: Array[EntityDef] = []) -> LevelDef:
	var ents: Array[EntityDef] = [
		S.switch_def("sw", 2.5, 4.5),
		S.door("d1", [Vector2i(6, 5)], SignalExpr.of_not(SignalExpr.of_sig("sw"))),
	]
	ents.append_array(extra)
	return TestLevels.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(2.5, 5.5), "entities": ents})


## Tape B: closes the door at local tick `at`.
func _closer(at: int) -> ODTape:
	return S.path_tape(1, 1.0, 240, [[0, 2.5, 5.5]], [[at, ActionKind.INTERACT]])


func _details(evs: Array[SimEvent]) -> Array:
	var out: Array = []
	for e: SimEvent in evs:
		out.append(e.detail)
	return out


func _has_note(r: Resolution, pattern: String) -> bool:
	var re := RegEx.create_from_string(pattern)
	for n: String in r.outcome.notes:
		if re.search(n) != null:
			return true
	return false

# ───────────────────────────── doors never delete a body ─────────────────────────────


func test_a_door_closing_on_a_playback_self_desyncs_it_the_projection_stays_on_its_recording() -> void:
	var stand_in: ODTape = S.path_tape(0, 1.0, 240, [[0, 2.5, 5.5], [40, 6.5, 5.5]])
	var res: Resolution = S.resolve(_door_room(), [stand_in, _closer(60)])
	var closed: Array[SimEvent] = []
	for e: SimEvent in S.events_of(res.events, SimEventType.DOOR, -1, "d1"):
		if e.detail == "closed":
			closed.append(e)
	assert_eq(closed.size(), 1)
	if closed.size() != 1:
		return
	# Travel starts on the toggle's substep; the door turns solid once it is less than half open.
	@warning_ignore("integer_division")
	assert_eq(closed[0].sub, 60 * 4 + Mechanisms.DOOR_TRAVEL_SUBS / 2)
	var d: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.DESYNC, 0):
		d.append([e.sub, e.detail])
	assert_eq(d, [[closed[0].sub + 1, "blocked by door d1"]])
	var last: ActorSnap = res.frames[res.frames.size() - 1].actors[0]
	assert_eq([last.x, last.y], [6.5, 5.5])
	assert_eq(last.life, OD.LifeState.ALIVE)
	# The spark starts beside the door, never inside it.
	var sr: float = Tuning.BASE.spark_radius
	assert_true(last.spark.x < 6 - sr or last.spark.x > 7 + sr, "spark at %s" % last.spark)


func test_a_door_closing_on_the_live_self_pushes_it_out_to_the_nearest_free_side() -> void:
	var level: LevelDef = _door_room()
	# The live self walks into the doorway and stands there; tape B closes the door on it.
	var take: TestScript.TakeResult = S.record_take(level, 0, 1.0, S.input_script().run(0, 52, 1, 0), [_closer(60)])
	var closed_sub: int = -1
	for e: SimEvent in S.events_of(take.events, SimEventType.DOOR, -1, "d1"):
		if e.detail == "closed":
			closed_sub = e.sub
			break
	assert_true(closed_sub > 0)
	var before: ActorSnap = _frame_from(take.frames, closed_sub - 4).actors[0]
	assert_eq(int(floor(before.x)), 6)
	var after: ActorSnap = _frame_from(take.frames, closed_sub + 8).actors[0]
	# Out of the door cell, beside it, alive and synced; and it does not fly off from the push.
	var ar: float = Tuning.BASE.actor_radius
	assert_true(after.x <= 6 - ar + 1e-6 or after.x >= 7 + ar - 1e-6, "after x %f" % after.x)
	assert_eq([after.life, after.synced], [OD.LifeState.ALIVE, true])
	var later: ActorSnap = _frame_from(take.frames, closed_sub + 200).actors[0]
	assert_true(absf(later.x - after.x) < 0.05)
	assert_eq(S.events_of(take.events, SimEventType.DESYNC).size(), 0)


func _frame_from(frames: Array[FrameSnapshot], sub: int) -> FrameSnapshot:
	for f: FrameSnapshot in frames:
		if f.sub >= sub:
			return f
	return frames[frames.size() - 1]


func test_a_door_closing_on_an_enemy_pushes_it_out() -> void:
	var extra: Array[EntityDef] = [S.enemy("g1", EnemyType.GRUNT, 6.5, 5.3, {"wake": SignalExpr.of_const(false)})]
	var res: Resolution = S.resolve(_door_room(extra), [_closer(10)])
	var g: EnemySnap = res.frames[res.frames.size() - 1].enemies[0]
	assert_true(g.alive)
	var inside_x: bool = g.x > 6 - 0.32 and g.x < 7 + 0.32
	var inside_y: bool = g.y > 5 - 0.32 and g.y < 6 + 0.32
	assert_false(inside_x and inside_y, "grunt at (%f, %f)" % [g.x, g.y])

# ───────────────────────────── plates, lasers and switches ─────────────────────────────


func _plate_level(heavy: bool) -> LevelDef:
	var ents: Array[EntityDef] = [
		S.plate("p1", 5, 5, heavy),
		S.laser("beam", Vector2(8.5, 1.5), Vector2(8.5, 8.5), SignalExpr.of_not(SignalExpr.of_sig("p1"))),
	]
	return TestLevels.make_level({"speeds": [1.0], "bars": 1, "start": Vector2(2.5, 5.5), "entities": ents})


func _on_plate() -> ODTape:
	return S.path_tape(0, 1.0, 120, [[0, 2.5, 5.5], [30, 5.5, 5.5]])


## C crosses the laser line late.
func _crosser() -> ODTape:
	return S.path_tape(2, 1.0, 120, [[0, 2.5, 5.5], [60, 2.5, 7.5], [100, 10.5, 7.5]])


func test_an_effective_body_holds_a_plate_which_can_switch_a_laser_off_for_another_self() -> void:
	var res: Resolution = S.resolve(_plate_level(false), [_on_plate(), _crosser()])
	assert_eq(_details(S.events_of(res.events, SimEventType.PLATE, -1, "p1")), ["on"])
	assert_eq(_details(S.events_of(res.events, SimEventType.LASER, -1, "beam")), ["off"])
	assert_eq(S.events_of(res.events, SimEventType.SELF_DEATH).size(), 0)


func test_without_the_plate_held_the_laser_kills_laserProof_gear_ignores_it() -> void:
	var res: Resolution = S.resolve(_plate_level(false), [_crosser()])
	assert_eq(_details(S.events_of(res.events, SimEventType.SELF_DEATH)), ["burned by laser beam"])
	var proof: Resolution = S.resolve(_plate_level(false), [_crosser()], TestLoadout.base_loadout({"abilities": [AbilityId.LASER_PROOF]}))
	assert_eq(S.events_of(proof.events, SimEventType.SELF_DEATH).size(), 0)


func test_a_heavy_plate_needs_heavyStep() -> void:
	assert_eq(S.events_of(S.resolve(_plate_level(true), [_on_plate()]).events, SimEventType.PLATE).size(), 0)
	var heavy: Resolution = S.resolve(_plate_level(true), [_on_plate()], TestLoadout.base_loadout({"abilities": [AbilityId.HEAVY_STEP]}))
	assert_eq(S.events_of(heavy.events, SimEventType.PLATE).size(), 1)


func test_a_dead_ghost_does_not_hold_a_plate() -> void:
	# A dies to the laser on the way, then its ghost stands on the plate.
	var ents: Array[EntityDef] = [
		S.laser("beam", Vector2(1.5, 3.5), Vector2(10.5, 3.5), SignalExpr.of_const(true)),
		S.plate("p1", 5, 1),
	]
	var level: LevelDef = TestLevels.make_level({"speeds": [1.0], "bars": 1, "start": Vector2(2.5, 5.5), "entities": ents})
	var t: ODTape = S.path_tape(0, 1.0, 120, [[0, 2.5, 5.5], [40, 5.5, 1.5]])
	var res: Resolution = S.resolve(level, [t])
	assert_eq(S.events_of(res.events, SimEventType.SELF_DEATH).size(), 1)
	assert_eq(S.events_of(res.events, SimEventType.PLATE).size(), 0)


func test_an_interact_with_nothing_in_reach_says_so() -> void:
	var t: ODTape = S.path_tape(0, 1.0, 120, [[0, 8.5, 8.5]], [[10, ActionKind.INTERACT]])
	var res: Resolution = S.resolve(_door_room(), [t])
	assert_eq(_details(S.events_of(res.events, SimEventType.INTERACT_FAIL)), ["nothing in reach"])

# ───────────────────────────── objectives ─────────────────────────────


func test_reach_an_alive_synced_self_must_be_in_the_exit_when_the_horizon_ends() -> void:
	var ents: Array[EntityDef] = [S.exit_def("exit", 9, 4, 2, 2)]
	var level: LevelDef = TestLevels.make_level(
		{
			"speeds": [1.0],
			"bars": 1,
			"start": Vector2(2.5, 5.5),
			"entities": ents,
			"objective": S.objective(ObjectiveType.REACH, "Get out"),
		}
	)
	var go_in: ODTape = S.path_tape(0, 1.0, 120, [[0, 2.5, 5.5], [60, 9.5, 5.0]])
	var ok: Resolution = S.resolve(level, [go_in])
	assert_true(ok.outcome.win)
	var obj: Array[SimEvent] = S.events_of(ok.events, SimEventType.OBJECTIVE)
	assert_eq(obj.size(), 1)
	if obj.size() == 1:
		assert_eq(obj[0].sub, ok.horizon_subs - 1)
	# Passing through and leaving again does not count.
	var pass_by: ODTape = S.path_tape(0, 1.0, 120, [[0, 2.5, 5.5], [50, 9.5, 5.0], [80, 5.5, 5.0]])
	var no: Resolution = S.resolve(level, [pass_by])
	assert_false(no.outcome.objective_complete)
	assert_true(_has_note(no, "No alive, synced self was in the exit"))


func test_activate_a_core_needs_a_strike_with_enough_momentum_and_clangs_otherwise() -> void:
	var ents: Array[EntityDef] = [S.core_def("c1", 6.0, 5.5, 1.0)]
	var level: LevelDef = TestLevels.make_level(
		{
			"speeds": [0.5, 1.0],
			"bars": 1,
			"start": Vector2(5.0, 5.5),
			"entities": ents,
			"objective": S.objective(ObjectiveType.ACTIVATE, "Light the core"),
		}
	)
	var weak: Resolution = S.resolve(level, [S.path_tape(0, 0.5, 120, [[0, 5.0, 5.5]], [[10, ActionKind.LIGHT, 0.0]])])
	assert_eq(S.events_of(weak.events, SimEventType.CLANG, -1, "c1").size(), 1)
	assert_false(weak.outcome.objective_complete)
	assert_true(_has_note(weak, "hit core c1 with momentum 0\\.6; it needs 1\\."), "notes: %s" % [weak.outcome.notes])
	var ok: Resolution = S.resolve(level, [S.path_tape(0, 1.0, 120, [[0, 5.0, 5.5]], [[10, ActionKind.LIGHT, 0.0]])])
	assert_eq(S.events_of(ok.events, SimEventType.CORE, -1, "c1").size(), 1)
	assert_true(ok.outcome.win)
	var o: ObjectiveSnap = ok.frames[ok.frames.size() - 1].objective
	assert_eq([o.complete, o.progress, o.survivors], [true, 1.0, 1])

# ───────────────────────────── extension hooks ─────────────────────────────


## The test archetype of the prototype's "registered archetype" case: a straight 12 t/s shot.
class _RecordingPierce:
	extends ProjectileArchetype
	var launches: Array[int] = []

	func _init() -> void:
		id = RangedArchetype.PIERCE

	func launch(w: ODSim, self_actor: SelfActor, ev: TapeEvent, _pass_dir: int) -> int:
		launches.append(w.s)
		var spec := SpawnSpec.make(self_actor.index, "", RangedArchetype.PIERCE, self_actor.pose.x, self_actor.pose.y, ev.dir, 12.0, 0.15, 20.0)
		spec.momentum = 1.2
		w.projectiles.spawn(w, spec)
		return 1


func _shooter() -> ODTape:
	return S.path_tape(0, 1.0, 120, [[0, 2.5, 5.5]], [[10, ActionKind.RANGED, 0.0]])


func _hook_level() -> LevelDef:
	var ents: Array[EntityDef] = [S.enemy("g1", EnemyType.GRUNT, 8.5, 5.5, {"wake": SignalExpr.of_const(false)})]
	return TestLevels.make_level({"speeds": [1.0], "bars": 1, "start": Vector2(2.5, 5.5), "entities": ents})


func test_a_recorded_ranged_event_with_no_archetype_registered_does_nothing_and_emits_nothing() -> void:
	var res: Resolution = S.resolve(_hook_level(), [_shooter()], TestLoadout.base_loadout({"ranged": {"archetype": &"none"}}))
	assert_eq(S.events_of(res.events, SimEventType.FIRE).size(), 0)
	var empty: bool = true
	for f: FrameSnapshot in res.frames:
		empty = empty and f.projectiles.is_empty()
	assert_true(empty)


func test_a_registered_archetype_is_launched_through_the_single_ranged_hook_at_the_launch_tick() -> void:
	var previous: ProjectileArchetype = ProjectileSystem.get_projectile_archetype(RangedArchetype.PIERCE)
	var arch := _RecordingPierce.new()
	ProjectileSystem.register_projectile_archetype(arch)
	var res: Resolution = S.resolve(
		_hook_level(), [_shooter()], TestLoadout.base_loadout({"ranged": {"archetype": RangedArchetype.PIERCE, "commit": 12}})
	)
	if previous != null:
		ProjectileSystem.register_projectile_archetype(previous)
	# Launch tick = event tick + min(ranged_launch_delay, commit - 1) local ticks.
	assert_eq(arch.launches, [(10 + Tuning.BASE.ranged_launch_delay) * 4])
	var fires: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.FIRE):
		fires.append([e.tape, e.detail])
	assert_eq(fires, [[0, "pierce"]])
	var kills: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.KILL, -1, "g1"):
		kills.append([e.tape, e.detail])
	assert_eq(kills, [[0, "pierce"]])


func test_the_ability_hook_reaches_registered_handlers_which_can_desync_a_self_on_demand() -> void:
	var previous: Callable = ODSim.get_ability_handler(AbilityId.MANUAL_DESYNC)
	ODSim.register_ability_handler(
		AbilityId.MANUAL_DESYNC, func(w: ODSim, self_actor: SelfActor, _ev: TapeEvent, _pd: int) -> void: w.desync(self_actor, "manual desync")
	)
	var t: ODTape = S.path_tape(0, 1.0, 120, [[0, 2.5, 5.5], [60, 6.5, 5.5]], [[20, ActionKind.ABILITY]])
	var res: Resolution = S.resolve(_hook_level(), [t], TestLoadout.base_loadout({"abilities": [AbilityId.MANUAL_DESYNC]}))
	ODSim.register_ability_handler(AbilityId.MANUAL_DESYNC, previous)
	var d: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.DESYNC):
		d.append([e.sub, e.detail])
	assert_eq(d, [[80, "manual desync"]])
	# The spark is right there, so it resyncs as soon as it is allowed to check.
	assert_eq(S.events_of(res.events, SimEventType.RESYNC).size(), 1)


func test_an_enemy_type_without_a_registered_behaviour_fails_loudly() -> void:
	var ents: Array[EntityDef] = [S.enemy("b", &"nope", 5, 5)]
	var bad: LevelDef = TestLevels.make_level({"entities": ents})
	var errors: Array[String] = []
	var sim: ODSim = ODSim.create_sim(SimConfig.make(bad, TestLoadout.base_loadout(), []), errors)
	assert_true(sim == null)
	assert_eq(errors.size(), 1)
	if errors.size() == 1:
		assert_true(errors[0].contains("No enemy behaviour registered for type 'nope'"), errors[0])

# ───────────────────────────── dead:<enemy id> signals ─────────────────────────────


## A sleeping one-hit grunt east of the start; a door that opens once it is dead
## (data/levels/README.md "Signal expressions").
func _dead_level() -> LevelDef:
	var ents: Array[EntityDef] = [
		S.enemy("g1", EnemyType.GRUNT, 6.0, 5.5, {"hp": 1, "wake": SignalExpr.of_const(false)}),
		S.door("gate", [Vector2i(9, 2)], SignalExpr.of_sig("dead:g1")),
	]
	return TestLevels.make_level({"speeds": [1.0], "bars": 1, "start": Vector2(5.0, 5.5), "entities": ents})


func test_a_dead_signal_is_false_while_the_enemy_lives_and_true_from_the_update_after_it_died() -> void:
	var tape: ODTape = S.path_tape(0, 1.0, 120, [[0, 5.0, 5.5]], [[20, ActionKind.LIGHT, 0.0]])
	var res: Resolution = S.resolve(_dead_level(), [tape])
	var kill := S.events_of(res.events, SimEventType.KILL, -1, "g1")
	if not assert_eq(kill.size(), 1):
		return
	var opened: Array[SimEvent] = []
	for e: SimEvent in S.events_of(res.events, SimEventType.DOOR, -1, "gate"):
		if e.detail == "open":
			opened.append(e)
	if not assert_eq(opened.size(), 1):
		return
	assert_true(opened[0].sub > kill[0].sub)
	# Door travel starts on the first mechanisms update after the kill.
	assert_true(opened[0].sub <= kill[0].sub + 1 + Mechanisms.DOOR_TRAVEL_SUBS)


func test_a_dead_signal_never_fires_for_an_enemy_that_survives() -> void:
	var tape: ODTape = S.path_tape(0, 1.0, 120, [[0, 5.0, 5.5]])
	var res: Resolution = S.resolve(_dead_level(), [tape])
	assert_eq(S.events_of(res.events, SimEventType.KILL).size(), 0)
	assert_eq(S.events_of(res.events, SimEventType.DOOR, -1, "gate").size(), 0)
