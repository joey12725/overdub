extends ODTest
## Traps as puzzle pieces: machines turned against enemies, chained machines, determinism, and the
## guarantee that a level without traps is untouched (docs/TRAPS.md).
## Port of prototype/tests/core/traps/scenarios.test.ts.

const S = preload("res://tests/helpers/script.gd")
const K = preload("res://tests/core/traps/trap_kit.gd")

const D4 := 5e-5
const D5 := 5e-6

const BELT := {"kind": "conveyor", "id": "belt", "cells": [{"c": 3, "r": 5}, {"c": 4, "r": 5}, {"c": 5, "r": 5}, {"c": 6, "r": 5}], "dir": "e", "speed": 2}


func _kill_rows(res: Resolution) -> Array:
	var out: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.KILL):
		out.append([e.id, e.tape, e.detail])
	return out

# ───────────────────────────── machines turned against enemies ─────────────────────────────


func test_a_conveyor_delivers_a_sleeping_grunt_into_a_recorded_swing() -> void:
	# The belt drops the grunt at x = 7 on substep 420. Tape A stands at x = 8 and swings west on
	# local tick 110: hit volume live for ticks [116, 120) = substeps [464, 480).
	var swing: ODTape = S.path_tape(0, 1.0, 240, [[0, 8, 5.5]], [[110, ActionKind.LIGHT, PI]])
	var with_belt: Resolution = S.resolve(K.room([BELT, K.sleeper("g", "grunt", 3.5, 5.5)]), [swing])
	var kill: Array[SimEvent] = S.events_of(with_belt.events, SimEventType.KILL)
	assert_eq(_kill_rows(with_belt), [["g", 0, "light"]])
	if kill.size() == 1:
		assert_eq(kill[0].sub, 464)
		assert_true(kill[0].x >= 7.0, "struck where the belt dropped it")
	assert_true(with_belt.outcome.win, "win with the machine")
	# Without the machine the same recording swings at nothing.
	var without: Resolution = S.resolve(K.room([K.sleeper("g", "grunt", 3.5, 5.5)]), [swing])
	assert_eq(S.events_of(without.events, SimEventType.KILL).size(), 0)
	assert_eq(S.events_of(without.events, SimEventType.WHIFF, 0).size(), 1)
	assert_false(without.outcome.win)


func test_a_dart_launcher_kills_an_enemy_that_a_later_tape_knocked_into_its_lane() -> void:
	# The grunt sleeps just north of the lane along row 5. Tape B, at 0.5x, cannot kill it (momentum
	# 0.6: no damage) but shoves it 0.6 tiles south, into the lane; the next dart does the rest.
	var level: LevelDef = K.room([{"kind": "dart", "id": "dl", "c": 0, "r": 5, "dir": "e", "every": 2}, K.sleeper("g", "grunt", 6.5, 4.75)], {"speeds": [0.5, 1.0]})
	var a: ODTape = K.stand(0, 2.5, 2.5)
	var b: ODTape = S.path_tape(1, 0.5, 240, [[0, 6.5, 3.9]], [[20, ActionKind.LIGHT, PI / 2.0]])
	var alone: Resolution = S.resolve(level, [a])
	assert_eq(S.events_of(alone.events, SimEventType.KILL).size(), 0)
	assert_false(alone.outcome.win)
	var both: Resolution = S.resolve(level, [a, b])
	var clang: Array[SimEvent] = S.events_of(both.events, SimEventType.CLANG, -1, "g")
	assert_eq(clang.size(), 1)
	if clang.size() != 1:
		return
	assert_near(K.enemy_at(both, clang[0].sub + 60, "g").y, 5.35, D4)
	var kill: Array[SimEvent] = S.events_of(both.events, SimEventType.KILL)
	assert_eq(_kill_rows(both), [["g", -1, "dart"]])
	if kill.size() == 1:
		assert_true(kill[0].sub > clang[0].sub, "killed after the shove")
	assert_true(both.outcome.win, "win")
	assert_eq(both.outcome.survivors, [0, 1])


func test_an_awake_grunt_hunting_a_self_walks_onto_raised_spikes() -> void:
	var level: LevelDef = K.room([{"kind": "spikes", "id": "sp", "cells": K.cells([[5, 5], [6, 5]]), "upWhen": K.ALWAYS}, {"kind": "enemy", "id": "g", "type": "grunt", "x": 2.5, "y": 5.5}])
	var res: Resolution = S.resolve(level, [K.stand(0, 9.5, 5.5)])
	var kill: Array[SimEvent] = S.events_of(res.events, SimEventType.KILL)
	var rows: Array = []
	for e: SimEvent in kill:
		rows.append([e.id, e.detail])
	assert_eq(rows, [["g", "spikes"]])
	# 2.5 tiles at 2.2 tiles per second.
	if kill.size() == 1:
		assert_true(kill[0].sub > 260 and kill[0].sub < 290, "walks onto them (%d)" % kill[0].sub)
	assert_true(res.outcome.win, "win")
	assert_eq(res.outcome.survivors, [0])

# ───────────────────────────── chained machines ─────────────────────────────


## belt -> enemies-only tripwire -> (door) and -> relay (next beat + 1) -> crusher.
func _chain(with_grunt: bool = true) -> LevelDef:
	var list: Array = []
	if with_grunt:
		list.append(BELT)
		list.append(K.sleeper("g", "grunt", 3.5, 5.5))
	list.append_array([
		{"kind": "sensor", "id": "trip", "from": {"x": 4.5, "y": 5}, "to": {"x": 4.5, "y": 6}, "detects": "enemies"},
		{"kind": "door", "id": "gate", "cells": K.cells([[9, 8]]), "openWhen": {"sig": "trip"}},
		{"kind": "relay", "id": "slam", "trigger": {"sig": "trip"}, "quantize": 1, "delay": 1, "hold": 1},
		{"kind": "crusher", "id": "cr", "cells": K.cells([[5, 5]]), "extendWhen": {"sig": "slam"}},
	])
	return K.room(list)


func test_an_enemy_riding_a_belt_through_a_sensor_opens_a_door_and_fires_a_crusher_onto_itself() -> void:
	var res: Resolution = S.resolve(_chain(), [K.stand(0, 2.5, 2.5)])
	# The grunt (radius 0.32) breaks the beam at x = 4.5 once its centre passes 4.18: substep 82.
	var trip: Array = K.trap_events(res.events, "trip")
	assert_eq(trip[0] if not trip.is_empty() else [], [82, "sensor:on"])
	# Same substep: the door starts opening (half open 17 substeps later) and the relay arms.
	var door: Array[SimEvent] = S.events_of(res.events, SimEventType.DOOR, -1, "gate")
	assert_true(not door.is_empty() and door[0].sub == 82 + 17 and door[0].detail == "open", "the gate opens off the tripwire")
	assert_eq(K.trap_events(res.events, "slam"), [[82, "relay:armed"], [239, "relay:on"], [359, "relay:off"]])
	# Quantised to beat 1, plus one beat: the stroke lands on beat 2 with the grunt at x = 5.5.
	var slams: Array = []
	for p: Variant in K.trap_events(res.events, "cr"):
		if (p as Array)[1] == "crusher:slam":
			slams.append(p)
	assert_eq(slams, [[239, "crusher:slam"]])
	var kill: Array[SimEvent] = S.events_of(res.events, SimEventType.KILL)
	assert_eq(K.isd(kill), [["g", 239, "crusher"]])
	if kill.size() == 1:
		assert_near(kill[0].x, 5.5, D5)
	assert_true(res.outcome.win, "win")


func test_no_self_can_start_that_chain_the_tripwire_only_sees_enemies() -> void:
	var crosser: ODTape = S.path_tape(0, 1.0, 240, [[0, 3.5, 5.5], [60, 7.5, 5.5]])
	var res: Resolution = S.resolve(_chain(false), [crosser])
	var traps: Array = []
	for e: SimEvent in res.events:
		if e.type == SimEventType.TRAP:
			traps.append(e.to_dict())
	assert_eq(traps, [])
	assert_eq(S.events_of(res.events, SimEventType.DOOR).size(), 0)

# ───────────────────────────── determinism ─────────────────────────────


## One of everything, with awake enemies, so every system interacts.
func _gauntlet() -> LevelDef:
	return K.room(
		[
			{"kind": "switch", "id": "sw", "x": 2.5, "y": 2.5},
			{"kind": "door", "id": "d", "cells": K.cells([[9, 8]]), "openWhen": {"or": [{"sig": "trip"}, {"sig": "bm"}]}},
			{"kind": "spikes", "id": "sp", "cells": K.cells([[5, 2], [6, 2]]), "upWhen": K.beats(2, 1, 2)},
			{"kind": "crusher", "id": "cr", "cells": K.cells([[8, 3], [8, 4]]), "extendWhen": {"sig": "rl"}},
			{"kind": "conveyor", "id": "belt", "cells": K.cells([[3, 5], [4, 5], [5, 5], [6, 5]]), "dir": "e", "reverseWhen": {"sig": "sw"}},
			{"kind": "flame", "id": "fl", "c": 0, "r": 7, "dir": "e", "range": 6, "onWhen": K.beats(4, 2, 3)},
			{"kind": "dart", "id": "dl", "c": 11, "r": 3, "dir": "w", "every": 2, "offset": 1},
			{"kind": "bumper", "id": "bm", "c": 7, "r": 5, "dir": "n", "fireWhen": K.beats(4, 3, 3.5)},
			{"kind": "sensor", "id": "trip", "from": {"x": 4.5, "y": 4}, "to": {"x": 4.5, "y": 7}},
			{"kind": "relay", "id": "rl", "trigger": {"sig": "trip"}, "delay": 1},
			{"kind": "magnet", "id": "mag", "x": 9.5, "y": 6.5, "radius": 3, "onWhen": K.beats(8, 4, 8)},
			{"kind": "enemy", "id": "g1", "type": "grunt", "x": 3.5, "y": 5.5},
			{"kind": "enemy", "id": "g2", "type": "stalker", "x": 9.5, "y": 2.5},
			{"kind": "enemy", "id": "t1", "type": "turret", "x": 10.5, "y": 8.5},
			{"kind": "enemy", "id": "b1", "type": "brute", "x": 6.5, "y": 7.5},
			{"kind": "enemy", "id": "dr", "type": "drone", "x": 8.5, "y": 6.5},
		],
		{"start": Vector2(1.5, 5.5), "speeds": [1.0, 2.0], "bars": 4}
	)


func _wander() -> TestScript.InputScript:
	return (
		S.input_script().run(0, 60, 1, 0).run(60, 110, 0, -1).run(110, 200, 1, 0.4).run(200, 300, -1, 0.2).run(300, 480, 0.3, 1)
		.press(40, ActionKind.LIGHT).press(130, ActionKind.DODGE).press(210, ActionKind.HEAVY).press(330, ActionKind.RANGED).press(400, ActionKind.INTERACT)
	)


func _frames_json(frames: Array[FrameSnapshot]) -> String:
	var out: Array = []
	for f: FrameSnapshot in frames:
		out.append(f.to_dict())
	return JSON.stringify(out)


func _events_json(events: Array[SimEvent]) -> String:
	var out: Array = []
	for e: SimEvent in events:
		out.append(e.to_dict())
	return JSON.stringify(out)


func test_the_same_tapes_in_a_level_with_every_trap_resolve_bit_for_bit_the_same() -> void:
	var level: LevelDef = _gauntlet()
	var a: TestScript.TakeResult = S.record_take(level, 0, 1.0, _wander())
	var b: TestScript.TakeResult = S.record_take(level, 1, 2.0, S.input_script().run(0, 200, 0.5, -1).press(90, ActionKind.HEAVY), [a.tape])
	var r1: Resolution = S.resolve(level, [a.tape, b.tape])
	var r2: Resolution = S.resolve(_gauntlet(), [a.tape, b.tape])
	assert_true(K.trap_details(r1.events, "dart:fire").size() > 0, "the machines ran")
	assert_true(r1.frames.size() > 400, "frames recorded")
	assert_eq(_frames_json(r2.frames), _frames_json(r1.frames), "frames identical")
	assert_eq(_events_json(r2.events), _events_json(r1.events), "events identical")
	assert_eq(r2.outcome.to_dict(), r1.outcome.to_dict())


func test_recording_the_same_inputs_twice_gives_the_same_tape_belts_and_bumpers_included() -> void:
	var a: TestScript.TakeResult = S.record_take(_gauntlet(), 0, 1.0, _wander())
	var b: TestScript.TakeResult = S.record_take(_gauntlet(), 0, 1.0, _wander())
	assert_eq(b.tape.pos, a.tape.pos)
	assert_eq(b.tape.to_dict(), a.tape.to_dict())
	assert_eq(_events_json(b.events), _events_json(a.events))


func test_a_take_that_rode_a_belt_and_a_bumper_plays_back_as_the_same_motion() -> void:
	# No enemies and no hazards on the route: playback must reproduce what the player saw.
	var level: LevelDef = K.room([BELT, {"kind": "bumper", "id": "bm", "c": 7, "r": 5, "dir": "s", "power": 2, "fireWhen": K.beats(8, 6, 6.5)}], {"start": Vector2(2.5, 5.5)})
	var take: TestScript.TakeResult = S.record_take(level, 0, 1.0, S.input_script().run(0, 12, 1, 0).run(200, 230, -1, 0))
	# Walks onto the belt, rides it to x = 7 (the bumper tile), is thrown south on beat 6, walks west.
	assert_eq(K.first_trap(take.events, "bumper:fire").power, 1.0)
	var res: Resolution = S.resolve(level, [take.tape])
	var bad := 0
	for i: int in take.frames.size():
		var live: ActorSnap = take.frames[i].actors[0]
		var played: ActorSnap = res.frames[i + 1].actors[0]
		if res.frames[i + 1].sub != take.frames[i].sub or played.x != live.x or played.y != live.y or not played.synced:
			bad += 1
	assert_eq(bad, 0, "every played-back frame equals the live frame")
	assert_eq(S.events_of(res.events, SimEventType.DESYNC).size(), 0)

# ───────────────────────────── strictly additive ─────────────────────────────


func test_a_level_with_no_traps_has_an_inert_trap_system_and_the_classic_mechanism_snapshot() -> void:
	var level: LevelDef = K.room([
		{"kind": "switch", "id": "sw", "x": 2.5, "y": 2.5},
		{"kind": "door", "id": "d", "cells": K.cells([[6, 5]]), "openWhen": {"sig": "sw"}},
		{"kind": "laser", "id": "lz", "from": {"x": 1, "y": 7.5}, "to": {"x": 11, "y": 7.5}, "onWhen": K.beats(4, 0, 1)},
		K.sleeper("g", "grunt", 8.5, 5.5),
	])
	var tapes: Array[ODTape] = [K.stand(0, 2.5, 3.2)]
	var sim: ODSim = ODSim.create_sim(SimConfig.make(level, TestLoadout.base_loadout(), tapes))
	var any_trap := false
	for i: int in 300:
		sim.step_sub()
		for e: SimEvent in sim.drain_events():
			any_trap = any_trap or e.type == SimEventType.TRAP
	var kinds: Array = []
	for m: MechSnap in sim.snapshot().mechs:
		kinds.append(m.kind)
	assert_eq(kinds, [MechKind.SWITCH, MechKind.DOOR, MechKind.LASER])
	var keys: Array = sim.snapshot().mechs[1].to_dict().keys()
	keys.sort()
	assert_eq(keys, ["id", "kind", "on", "t"])
	assert_false(any_trap)
	assert_eq(sim.traps.count, 0)


func test_trap_snapshots_come_after_the_classic_mechanisms_in_entity_order() -> void:
	var level: LevelDef = K.room([
		{"kind": "spikes", "id": "sp", "cells": K.cells([[5, 2]]), "upWhen": K.ALWAYS},
		{"kind": "switch", "id": "sw", "x": 2.5, "y": 2.5},
		{"kind": "relay", "id": "rl", "trigger": {"sig": "sw"}},
		{"kind": "door", "id": "d", "cells": K.cells([[6, 5]]), "openWhen": {"sig": "rl"}},
		{"kind": "magnet", "id": "mag", "x": 5.5, "y": 5.5, "radius": 2, "onWhen": K.ALWAYS},
	])
	var tapes: Array[ODTape] = [K.stand(0, 2.5, 3.2)]
	var sim: ODSim = ODSim.create_sim(SimConfig.make(level, TestLoadout.base_loadout(), tapes))
	var ids: Array = []
	for m: MechSnap in sim.snapshot().mechs:
		ids.append(m.id)
	assert_eq(ids, ["sw", "d", "sp", "rl", "mag"])


func test_a_self_killed_by_a_machine_is_reported_in_the_games_own_terms() -> void:
	var res: Resolution = S.resolve(K.room([{"kind": "flame", "id": "fl", "c": 0, "r": 5, "dir": "e", "range": 8, "onWhen": K.beats(4, 1, 2)}, K.sleeper("g", "grunt", 9.5, 2.5)]), [K.stand(0, 3.5, 5.5)])
	assert_false(res.outcome.win)
	assert_eq(res.outcome.survivors, [])
	assert_true(K.has_note(res, "burned by flame jet fl"), "the note names the flame jet")
	assert_eq(K.last_frame(res).objective.survivors, 0)

# ───────────────────────────── port additions ─────────────────────────────


## Every trap def survives LevelDef JSON round trips (the shapes in docs/TRAPS.md), optional fields
## stay absent, and parsing reports malformed expressions.
func test_trap_defs_round_trip_through_level_json() -> void:
	var lits: Array = [
		{"kind": "spikes", "id": "sp1", "cells": K.cells([[4, 3], [5, 3]]), "upWhen": K.beats(4, 2, 3)},
		{"kind": "spikes", "id": "sp2", "cells": K.cells([[4, 4]]), "upWhen": K.ALWAYS, "damage": 2},
		{"kind": "crusher", "id": "cr1", "cells": K.cells([[6, 2], [6, 3]]), "dir": "s", "extendWhen": {"sig": "slam"}, "damage": 4},
		{"kind": "conveyor", "id": "belt1", "cells": K.cells([[2, 5]]), "dir": "e", "speed": 2, "runWhen": K.ALWAYS, "reverseWhen": {"sig": "lever"}},
		{"kind": "flame", "id": "fl1", "c": 1, "r": 4, "dir": "e", "range": 5, "onWhen": K.beats(2, 1, 2)},
		{"kind": "dart", "id": "d1", "c": 0, "r": 3, "dir": "e", "every": 2, "offset": 0.5, "enabledWhen": K.NEVER, "speed": 6},
		{"kind": "bumper", "id": "bm1", "c": 7, "r": 4, "dir": "n", "power": 3, "fireWhen": K.beats(4, 3, 3.5)},
		{"kind": "sensor", "id": "trip1", "from": {"x": 3.5, "y": 2.0}, "to": {"x": 3.5, "y": 6.25}, "detects": "enemies", "latch": true},
		{"kind": "relay", "id": "slam", "trigger": {"sig": "trip1"}, "mode": "pulse", "quantize": 1, "delay": 1, "hold": 1, "x": 2, "y": 3},
		{"kind": "magnet", "id": "mag1", "x": 6.5, "y": 4.5, "radius": 4, "pull": 1.5, "onWhen": {"sig": "leverM"}},
		{"kind": "dart", "id": "d2", "c": 0, "r": 6, "dir": "e"},
	]
	for lit: Dictionary in lits:
		var errors: Array[String] = []
		var ent: EntityDef = LevelDef.entity_from_dict(lit, errors)
		assert_eq(errors, [], "%s parses" % lit.id)
		if ent == null:
			continue
		assert_true(ent is TrapDef and EntityKind.is_trap(ent.kind), "%s is a trap" % lit.id)
		assert_json_eq(ent.to_dict(), lit, 0.0, "%s round-trips" % lit.id)
		assert_json_eq(ent.copy().to_dict(), lit, 0.0, "%s copies" % lit.id)
	var bad: Array[String] = []
	LevelDef.entity_from_dict({"kind": "spikes", "id": "x", "cells": [], "upWhen": {"nope": 1}}, bad)
	assert_true(bad.size() > 0, "a malformed expression is reported")
	assert_false(SimEventType.ALL.has(SimEventType.TRAP), "'trap' stays out of ALL until fx routes it (see SimEventType.TRAP)")
	assert_true(EntityKind.has(EntityKind.MAGNET) and not EntityKind.ALL.has(EntityKind.MAGNET), "trap kinds are kinds, listed in EntityKind.TRAPS")


## The live self's belt carry goes through PlayerController.displace, which rounds to float32 and
## leaves velocity alone (docs/TRAPS.md "The live self").
func test_player_displace_rounds_to_float32_and_keeps_velocity() -> void:
	var ctl := PlayerController.new(PlayerController.PlayerStart.make(2.5, 2.5))
	var grid: ODGrid = ODGrid.parse_grid(TestLevels.OPEN_ROOM)
	var lo: ResolvedLoadout = TestLoadout.base_loadout()
	for i: int in 5:
		ctl.step(PlayerInput.make(1, 0, 0), grid, lo, OD.LifeState.ALIVE)
	var before: PlayerController.PlayerPose = ctl.pose
	ctl.displace(3.1, 4.7)
	var after: PlayerController.PlayerPose = ctl.pose
	var f := PackedFloat32Array([3.1, 4.7])
	assert_eq([after.x, after.y], [f[0], f[1]])
	assert_eq([after.vx, after.vy], [before.vx, before.vy])
