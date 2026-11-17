extends ODTest
## Traps that move bodies: conveyors, bumpers, magnets (docs/TRAPS.md 3, 6, 9).
## Port of prototype/tests/core/traps/movers.test.ts.

const S = preload("res://tests/helpers/script.gd")
const K = preload("res://tests/core/traps/trap_kit.gd")

const D4 := 5e-5
const D5 := 5e-6
const D6 := 5e-7


## A belt along row 5, columns 3..6, running east at 2 tiles per master second.
func _belt(extra: Dictionary = {}) -> Dictionary:
	return K.merged({"kind": "conveyor", "id": "belt", "cells": K.cells([[3, 5], [4, 5], [5, 5], [6, 5]]), "dir": "e", "speed": 2}, extra)


## Tape that toggles switch "sw" (at 2.5, 2.5) on local tick `at`.
func _toggler(index: int, at: int) -> ODTape:
	return S.path_tape(index, 1.0, 240, [[0, 2.5, 3.2]], [[at, ActionKind.INTERACT]])


func _bumper(extra: Dictionary = {}) -> Dictionary:
	return K.merged({"kind": "bumper", "id": "bm", "c": 4, "r": 5, "dir": "e", "power": 3, "fireWhen": K.beats(8, 1, 2)}, extra)


func _magnet(on_when: Dictionary = K.ALWAYS) -> Dictionary:
	return {"kind": "magnet", "id": "mag", "x": 8.5, "y": 5.5, "radius": 4, "pull": 1.5, "onWhen": on_when}

# ───────────────────────────── conveyor ─────────────────────────────


func test_conveyor_carries_a_grounded_enemy_at_its_speed_in_master_time_and_lets_go_at_the_end() -> void:
	var res: Resolution = S.resolve(K.room([_belt(), K.sleeper("g", "grunt", 3.5, 5.5)]), [K.stand(0, 2.5, 2.5)])
	# 2 tiles per master second = 1/120 tile per substep.
	assert_near(K.enemy_at(res, 120, "g").x, 4.5, D6)
	assert_near(K.enemy_at(res, 240, "g").x, 5.5, D6)
	# Its centre leaves the last cell at x = 7 (substep 420) and it stays where the belt dropped it.
	var end: EnemySnap = K.last_frame(res).enemies[0]
	assert_true(end.x >= 7.0 and end.x < 7.01, "dropped at the belt's end (%s)" % end.x)
	assert_eq(end.y, 5.5)
	var m: MechSnap = K.mech_at(res, 0, "belt")
	assert_eq([m.kind, m.on, m.dir], [MechKind.CONVEYOR, true, 0.0])


func test_conveyor_does_not_carry_turrets_drones_or_playback_selves() -> void:
	var res: Resolution = S.resolve(K.room([_belt(), K.sleeper("t", "turret", 3.5, 5.5), K.sleeper("dr", "drone", 4.5, 5.5)]), [K.stand(0, 5.5, 5.5)])
	var t: EnemySnap = K.enemy_at(res, 900, "t")
	assert_eq([t.x, t.y], [3.5, 5.5])
	var dr: EnemySnap = K.enemy_at(res, 900, "dr")
	assert_eq([dr.x, dr.y], [4.5, 5.5])
	var a: ActorSnap = K.last_frame(res).actors[0]
	assert_eq([a.x, a.y, a.synced, a.life], [5.5, 5.5, true, OD.LifeState.ALIVE])
	assert_eq(S.events_of(res.events, SimEventType.DESYNC).size(), 0)


func test_conveyor_stops_against_a_wall_instead_of_pushing_a_body_through_it() -> void:
	var wall_belt := {"kind": "conveyor", "id": "belt", "cells": K.cells([[8, 5], [9, 5], [10, 5]]), "dir": "e", "speed": 2}
	var res: Resolution = S.resolve(K.room([wall_belt, K.sleeper("g", "grunt", 8.5, 5.5)]), [K.stand(0, 2.5, 2.5)])
	var end: EnemySnap = K.last_frame(res).enemies[0]
	assert_true(end.x <= 11.0 - 0.32 + 1e-6 and end.x > 10.6, "rests against the wall (%s)" % end.x)


func test_conveyor_reverses_on_its_signal_the_substep_it_changes_and_publishes_id_and_rev() -> void:
	var level: LevelDef = K.room([
		_belt({"reverseWhen": {"sig": "sw"}}),
		{"kind": "switch", "id": "sw", "x": 2.5, "y": 2.5},
		{"kind": "door", "id": "d", "cells": K.cells([[9, 8]]), "openWhen": {"sig": "belt.rev"}},
		K.sleeper("g", "grunt", 3.5, 5.5),
	])
	# The switch flips at local tick 30 = substep 120: one beat east, then west.
	var res: Resolution = S.resolve(level, [K.stand(0, 9.5, 2.5), _toggler(1, 30)])
	assert_eq(K.trap_events(res.events, "belt"), [[120, "conveyor:reverse"]])
	assert_near(K.enemy_at(res, 120, "g").x, 4.5, D6)
	assert_near(K.enemy_at(res, 240, "g").x, 3.5, D5)
	assert_near(absf(K.mech_at(res, 240, "belt").dir), PI, D6)
	var opened := false
	for e: SimEvent in S.events_of(res.events, SimEventType.DOOR, -1, "d"):
		opened = opened or e.detail == "open"
	assert_true(opened, "a door reads belt.rev")


func test_conveyor_stops_while_run_when_is_false() -> void:
	var res: Resolution = S.resolve(K.room([_belt({"runWhen": K.beats(4, 0, 1)}), K.sleeper("g", "grunt", 3.5, 5.5)]), [K.stand(0, 2.5, 2.5)])
	assert_eq(K.trap_events(res.events, "belt").slice(0, 2), [[119, "conveyor:off"], [479, "conveyor:on"]])
	# Runs for substeps 0..118 of the first beat only.
	assert_near(K.enemy_at(res, 400, "g").x, 3.5 + 119.0 / 120.0, D5)
	assert_false(K.mech_at(res, 240, "belt").on)


func test_conveyor_carries_the_live_self_by_what_the_world_moves_per_local_tick() -> void:
	var level: LevelDef = K.room([_belt()], {"start": Vector2(3.5, 5.5), "speeds": [1.0, 2.0]})
	var at1: TestScript.TakeResult = S.record_take(level, 0, 1.0, S.input_script(), [], null, OD.EndMode.STOP, 30)
	# 30 local ticks at 1x = 120 substeps = one tile.
	assert_near(at1.tape.pos[30 * 2], 4.5, D4)
	assert_near(at1.tape.pos[30 * 2 + 1], 5.5, D6)
	# At 2x the world moves half as far per local tick: the belt feels half as fast to the hands.
	var at2: TestScript.TakeResult = S.record_take(level, 0, 2.0, S.input_script(), [], null, OD.EndMode.STOP, 30)
	assert_near(at2.tape.pos[30 * 2], 4.0, D4)
	# The live self is read back through its own tape: the world saw it where the belt put it.
	assert_near(at1.frames[29].actors[0].x, 4.5, D4)


func test_a_recorded_ride_replays_unchanged_when_a_later_tape_reverses_the_belt() -> void:
	var level: LevelDef = K.room([_belt({"reverseWhen": {"sig": "sw"}}), {"kind": "switch", "id": "sw", "x": 2.5, "y": 2.5}], {"start": Vector2(3.5, 5.5)})
	var ride: TestScript.TakeResult = S.record_take(level, 0, 1.0, S.input_script())
	var ride_end: float = ride.tape.pos[240 * 2]
	assert_true(ride_end >= 7.0, "the ride reaches the belt's end (%s)" % ride_end)
	var res: Resolution = S.resolve(level, [ride.tape, _toggler(1, 10)])
	assert_eq(S.events_of(res.events, SimEventType.DESYNC).size(), 0)
	var worst := 0.0
	for f: FrameSnapshot in res.frames:
		@warning_ignore("integer_division")
		var tick: int = mini(240, f.sub / 4)
		worst = maxf(worst, absf(f.actors[0].x - ride.tape.pos[tick * 2]))
	assert_true(worst < D5, "playback follows the recorded ride (worst %s)" % worst)
	var a: ActorSnap = K.last_frame(res).actors[0]
	assert_eq([a.life, a.synced], [OD.LifeState.ALIVE, true])


func test_conveyor_carries_the_recording_ghost_too() -> void:
	var level: LevelDef = K.room([_belt(), {"kind": "spikes", "id": "sp", "cells": K.cells([[3, 5]]), "upWhen": K.ALWAYS}], {"start": Vector2(3.5, 5.5)})
	var take: TestScript.TakeResult = S.record_take(level, 0, 1.0, S.input_script(), [], null, OD.EndMode.STOP, 60)
	assert_eq(take.frames[59].actors[0].life, OD.LifeState.REC_GHOST)
	assert_near(take.tape.pos[60 * 2], 5.5, D4)


func test_conveyor_drifts_a_floor_height_projectile_sideways_without_turning_it() -> void:
	# A dart flies east along row 5 and crosses a belt running south.
	var south := {"kind": "conveyor", "id": "belt", "cells": K.cells([[4, 5], [5, 5], [6, 5], [7, 5]]), "dir": "s", "speed": 2}
	var level: LevelDef = K.room([south, {"kind": "dart", "id": "dl", "c": 0, "r": 5, "dir": "e", "every": 8, "speed": 4}])
	var res: Resolution = S.resolve(level, [K.stand(0, 2.5, 2.5)])
	var before: ProjectileSnap = K.frame_from(res.frames, 160).projectiles[0]
	assert_eq(before.y, 5.5)
	# Over the belt for x in [4, 8) or until it drifts off row 5: 4 tiles/s east, 2 tiles/s south.
	var after: ProjectileSnap = K.frame_from(res.frames, 320).projectiles[0]
	assert_true(after.y > 5.9, "drifted south (%s)" % after.y)
	assert_eq(after.dir, 0.0)

# ───────────────────────────── bumper ─────────────────────────────


func test_bumper_fires_once_on_each_rising_edge_and_launches_a_grounded_enemy_with_real_knockback() -> void:
	var res: Resolution = S.resolve(K.room([_bumper(), K.sleeper("g", "grunt", 4.5, 5.5)], {"bars": 4}), [K.stand(0, 2.5, 2.5, 480)])
	var fires: Array = []
	for e: SimEvent in K.trap_details(res.events, "bumper:fire"):
		fires.append([e.sub, e.power, e.dir])
	assert_eq(fires, [[119, 1.0, 0.0], [1079, 0.0, 0.0]])
	# Mass 1: thrown the full 3 tiles over the knockback slide, then it stays where it landed.
	assert_eq(K.enemy_at(res, 116, "g").x, 4.5)
	assert_near(K.enemy_at(res, 200, "g").x, 7.5, D5)
	assert_near(K.last_frame(res).enemies[0].x, 7.5, D5)
	assert_eq(S.events_of(res.events, SimEventType.HIT).size(), 0)


func test_bumper_scales_the_throw_by_mass_and_never_moves_turrets_drones_or_a_recorded_self() -> void:
	var level: LevelDef = K.room([
		_bumper(),
		K.sleeper("b", "brute", 4.5, 5.5),
		{"kind": "bumper", "id": "bm2", "c": 4, "r": 3, "dir": "e", "fireWhen": K.beats(8, 1, 2)},
		K.sleeper("t", "turret", 4.5, 3.5),
		{"kind": "bumper", "id": "bm3", "c": 4, "r": 7, "dir": "e", "fireWhen": K.beats(8, 1, 2)},
		K.sleeper("dr", "drone", 4.5, 7.5),
		{"kind": "bumper", "id": "bm4", "c": 2, "r": 8, "dir": "e", "fireWhen": K.beats(8, 1, 2)},
	])
	var res: Resolution = S.resolve(level, [K.stand(0, 2.5, 8.5)])
	assert_near(K.enemy_at(res, 400, "b").x, 5.5, D5)
	assert_eq(K.enemy_at(res, 400, "t").x, 4.5)
	assert_eq(K.enemy_at(res, 400, "dr").x, 4.5)
	var a: ActorSnap = K.last_frame(res).actors[0]
	assert_eq([a.x, a.y, a.synced], [2.5, 8.5, true])
	var bm4: SimEvent = null
	for e: SimEvent in res.events:
		if e.type == SimEventType.TRAP and e.id == "bm4":
			bm4 = e
			break
	assert_true(bm4 != null and bm4.power == 0.0, "bm4 fires empty")


func test_bumper_slams_a_launched_enemy_into_a_wall_and_the_rest_of_the_throw_becomes_stagger() -> void:
	var res: Resolution = S.resolve(K.room([_bumper({"c": 9, "power": 3}), K.sleeper("g", "grunt", 9.5, 5.5)]), [K.stand(0, 2.5, 2.5)])
	assert_true(K.last_frame(res).enemies[0].x <= 11.0 - 0.32 + 1e-6, "stopped by the wall")
	assert_true(S.events_of(res.events, SimEventType.ENEMY_STAGGER, -1, "g").size() > 0, "wall slam staggers")


func test_bumper_throws_the_live_self_and_playback_repeats_the_flight_without_the_plate() -> void:
	var level: LevelDef = K.room([_bumper()], {"start": Vector2(4.5, 5.5)})
	var take: TestScript.TakeResult = S.record_take(level, 0, 1.0, S.input_script())
	assert_near(take.tape.pos[29 * 2], 4.5, D6)
	# Fired in substep 119; the 3 tiles are spread over 43 substeps = the next 11 local ticks.
	assert_near(take.tape.pos[45 * 2], 7.5, D4)
	assert_near(take.tape.pos[240 * 2], 7.5, D4)
	assert_eq(K.first_trap(take.events, "bumper:fire").power, 1.0)
	# Played back, the plate fires under nobody (the self is no longer live) and the path is the tape.
	var res: Resolution = S.resolve(level, [take.tape])
	assert_eq(K.first_trap(res.events, "bumper:fire").power, 0.0)
	assert_near(K.last_frame(res).actors[0].x, 7.5, D4)
	assert_eq(S.events_of(res.events, SimEventType.DESYNC).size(), 0)


func test_bumper_publishes_a_short_pulse_on_its_id_after_firing() -> void:
	var res: Resolution = S.resolve(K.room([_bumper()]), [K.stand(0, 2.5, 2.5)])
	var a: MechSnap = K.mech_at(res, 116, "bm")
	assert_eq([a.kind, a.on, a.firing, a.t], [MechKind.BUMPER, false, false, 0.0])
	var b: MechSnap = K.mech_at(res, 120, "bm")
	assert_eq([b.on, b.firing, b.t], [true, true, 1.0])
	var c: MechSnap = K.mech_at(res, 120 + TrapTuning.BUMPER_PULSE_SUBS + 4, "bm")
	assert_eq([c.on, c.firing, c.t], [false, false, 0.0])

# ───────────────────────────── magnet ─────────────────────────────


func test_magnet_drags_enemies_in_range_toward_its_centre_and_holds_them_just_short_of_it() -> void:
	var res: Resolution = S.resolve(
		K.room([_magnet(), K.sleeper("g", "grunt", 5.5, 5.5), K.sleeper("b", "brute", 8.5, 2.5), K.sleeper("far", "grunt", 2.5, 5.5), K.sleeper("t", "turret", 8.5, 7.5)]),
		[K.stand(0, 7.5, 5.5)]
	)
	# 1.5 tiles per second for mass 1; a third of that for the brute.
	assert_near(K.enemy_at(res, 240, "g").x, 7.0, D5)
	assert_near(K.enemy_at(res, 240, "b").y, 3.0, D5)
	assert_near(K.enemy_at(res, 900, "g").x, 8.5 - 0.6, D5)
	assert_eq(K.enemy_at(res, 900, "far").x, 2.5)
	var t: EnemySnap = K.enemy_at(res, 900, "t")
	assert_eq([t.x, t.y], [8.5, 7.5])
	# Selves are never pulled.
	var a: ActorSnap = K.last_frame(res).actors[0]
	assert_eq([a.x, a.y], [7.5, 5.5])


func test_magnet_pulls_drones_and_only_while_its_signal_is_on() -> void:
	var res: Resolution = S.resolve(K.room([_magnet(K.beats(8, 1, 2)), K.sleeper("dr", "drone", 5.5, 5.5)]), [K.stand(0, 2.5, 2.5)])
	assert_eq(K.trap_events(res.events, "mag"), [[119, "magnet:on"], [239, "magnet:off"]])
	# One beat (0.5 s) at 1.5 / 0.7 tiles per second.
	assert_near(K.last_frame(res).enemies[0].x, 5.5 + (1.5 / 0.7) * 0.5, D4)
