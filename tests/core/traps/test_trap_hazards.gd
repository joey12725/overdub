extends ODTest
## Traps that hurt: spikes, crushers, flame jets (docs/TRAPS.md 1, 2, 4).
## Port of prototype/tests/core/traps/hazards.test.ts.

const S = preload("res://tests/helpers/script.gd")
const K = preload("res://tests/core/traps/trap_kit.gd")

const D5 := 5e-6
const D6 := 5e-7


func _spikes(up_when: Dictionary = K.beats(4, 1, 2), extra: Dictionary = {}) -> Dictionary:
	return K.merged({"kind": "spikes", "id": "sp", "cells": K.cells([[5, 5], [6, 5]]), "upWhen": up_when}, extra)


## A piston across the whole room at column 5 (interior rows 1..8).
func _wall_crusher(extend_when: Dictionary = K.beats(8, 1, 2), extra: Dictionary = {}) -> Dictionary:
	var cl: Array = []
	for r: int in range(1, 9):
		cl.append([5, r])
	return K.merged({"kind": "crusher", "id": "cr", "cells": K.cells(cl), "extendWhen": extend_when}, extra)


func _flame(on_when: Dictionary = K.beats(4, 1, 2), extra: Dictionary = {}) -> Dictionary:
	return K.merged({"kind": "flame", "id": "fl", "c": 0, "r": 5, "dir": "e", "range": 8, "onWhen": on_when}, extra)

# ───────────────────────────── spikes ─────────────────────────────


func test_spikes_raise_and_drop_with_the_signal_publish_their_id_and_telegraph_one_beat_ahead() -> void:
	var res: Resolution = S.resolve(K.room([_spikes(), {"kind": "door", "id": "d", "cells": K.cells([[9, 8]]), "openWhen": {"sig": "sp"}}]), [K.stand(0, 2.5, 2.5)])
	assert_eq(K.trap_events(res.events, "sp"), [
		[0, "spikes:warn"], [119, "spikes:up"], [239, "spikes:down"],
		[479, "spikes:warn"], [599, "spikes:up"], [719, "spikes:down"],
	])
	var m0: MechSnap = K.mech_at(res, 0, "sp")
	assert_eq([m0.kind, m0.on, m0.t, m0.warn], [MechKind.SPIKES, false, 0.0, 0.0])
	assert_near(K.mech_at(res, 60, "sp").warn, 0.5, D5)
	var m1: MechSnap = K.mech_at(res, 120, "sp")
	assert_eq([m1.on, m1.t, m1.warn], [true, 1.0, 0.0])
	var m2: MechSnap = K.mech_at(res, 240, "sp")
	assert_eq([m2.on, m2.t], [false, 0.0])
	# The id is an ordinary signal: spikes rise in substep 119; the door reads the signal from substep
	# 120 and is half open (18 of 36 travel substeps) in substep 137.
	var opened: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.DOOR, -1, "d"):
		if e.detail == "open":
			opened.append(e.sub)
	assert_eq(opened[0] if not opened.is_empty() else -1, 120 + 17)


func test_spikes_kill_a_playback_self_standing_on_a_raised_cell_and_only_there() -> void:
	var res: Resolution = S.resolve(K.room([_spikes()]), [K.stand(0, 5.5, 5.5), K.stand(1, 7.2, 5.5)])
	assert_eq(K.tsd(S.events_of(res.events, SimEventType.SELF_DEATH)), [[0, 119, "skewered by spikes sp"]])
	var lives: Array = []
	for a: ActorSnap in K.last_frame(res).actors:
		lives.append(a.life)
	assert_eq(lives, [OD.LifeState.GHOST, OD.LifeState.ALIVE])
	assert_true(K.has_note(res, "spikes sp"), "the outcome notes name the spikes")


func test_a_recorded_dodge_carries_a_playback_self_across_without_it_the_same_path_dies() -> void:
	# Raised for a quarter beat (30 substeps). The dodge at local tick 28 is invulnerable for ticks
	# [29, 39) = substeps [116, 156), which covers the whole window [119, 149).
	var path: Array = [[0, 4.4, 5.5], [28, 4.4, 5.5], [42, 7.4, 5.5]]
	var level: LevelDef = K.room([_spikes(K.beats(8, 1, 1.25))])
	var dodging: ODTape = S.path_tape(0, 1.0, 240, path, [[28, ActionKind.DODGE]])
	var walking: ODTape = S.path_tape(0, 1.0, 240, path)
	assert_eq(S.events_of(S.resolve(level, [dodging]).events, SimEventType.SELF_DEATH).size(), 0)
	var d: Array[SimEvent] = S.events_of(S.resolve(level, [walking]).events, SimEventType.SELF_DEATH)
	assert_eq(d.size(), 1)
	if d.size() == 1:
		assert_true(d[0].sub >= 119 and d[0].sub < 149, "dies inside the window (%d)" % d[0].sub)


func test_spikes_kill_the_live_self_once_the_recording_ghost_then_walks_over_freely() -> void:
	var level: LevelDef = K.room([_spikes(K.ALWAYS)], {"start": Vector2(3.5, 5.5)})
	var take: TestScript.TakeResult = S.record_take(level, 0, 1.0, S.input_script().run(0, 200, 1, 0))
	var deaths: Array[SimEvent] = S.events_of(take.events, SimEventType.SELF_DEATH)
	assert_eq(K.details(deaths), ["skewered by spikes sp"])
	var end: ActorSnap = take.frames[take.frames.size() - 1].actors[0]
	assert_eq(end.life, OD.LifeState.REC_GHOST)
	assert_true(end.x > 8.0, "the recording ghost walked on (%s)" % end.x)


func test_spikes_never_touch_a_dead_ghost() -> void:
	# Tape 0 dies on the first spike strip at x 2..3, then its ghost walks through the second.
	var level: LevelDef = K.room([{"kind": "spikes", "id": "a", "cells": K.cells([[2, 5]]), "upWhen": K.ALWAYS}, _spikes(K.ALWAYS)])
	var walker: ODTape = S.path_tape(0, 1.0, 240, [[0, 1.5, 5.5], [120, 9.5, 5.5]])
	var res: Resolution = S.resolve(level, [walker])
	assert_eq(K.details(S.events_of(res.events, SimEventType.SELF_DEATH)), ["skewered by spikes a"])
	var a: ActorSnap = K.last_frame(res).actors[0]
	assert_eq([a.life, a.x], [OD.LifeState.GHOST, 9.5])


func test_spikes_kill_a_grunt_on_contact_credit_the_trap_and_hit_a_brute_once_per_beat() -> void:
	var res: Resolution = S.resolve(K.room([_spikes(K.ALWAYS), K.sleeper("g", "grunt", 5.5, 5.5), K.sleeper("b", "brute", 6.5, 5.5)]), [K.stand(0, 2.5, 2.5)])
	var kills: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.KILL):
		kills.append([e.id, e.sub, e.detail, e.tape])
	assert_eq(kills, [["g", 0, "spikes", -1], ["b", 240, "spikes", -1]])
	assert_eq(K.subs(S.events_of(res.events, SimEventType.HIT, -1, "b")), [0, 120, 240])
	assert_eq(K.enemy_at(res, 124, "b").hp, 1)
	assert_true(res.outcome.objective_complete, "trap kills count toward eliminate")


func test_leaving_the_spikes_resets_the_contact_clock_and_a_drone_overhead_is_never_touched() -> void:
	# The brute rides a belt off the spikes after one hit; the drone hovers on a raised cell throughout.
	var res: Resolution = S.resolve(
		K.room([
			_spikes(K.ALWAYS),
			{"kind": "conveyor", "id": "belt", "cells": K.cells([[6, 5]]), "dir": "e", "speed": 2},
			K.sleeper("b", "brute", 6.5, 5.5),
			K.sleeper("dr", "drone", 5.5, 5.5),
		]),
		[K.stand(0, 2.5, 2.5)]
	)
	assert_eq(K.subs(S.events_of(res.events, SimEventType.HIT, -1, "b")), [0])
	assert_eq(S.events_of(res.events, SimEventType.HIT, -1, "dr").size(), 0)
	var dr: EnemySnap = K.enemy_at(res, 900, "dr")
	assert_eq([dr.alive, dr.hp], [true, 2])


func test_a_shielders_shield_absorbs_trap_damage_like_any_other_non_tape_hit() -> void:
	var res: Resolution = S.resolve(K.room([_spikes(K.ALWAYS), K.sleeper("s", "shielder", 5.5, 5.5)]), [K.stand(0, 2.5, 2.5)])
	assert_eq(S.events_of(res.events, SimEventType.KILL).size(), 0)
	assert_true(S.events_of(res.events, SimEventType.CLANG, -1, "s").size() > 0, "the shield clangs")
	var s: EnemySnap = K.enemy_at(res, 900, "s")
	assert_eq([s.alive, s.hp], [true, 2])

# ───────────────────────────── crusher ─────────────────────────────


func test_crusher_strokes_on_the_signal_stays_solid_through_a_fixed_retract_then_opens() -> void:
	var res: Resolution = S.resolve(K.room([_wall_crusher()]), [K.stand(0, 2.5, 2.5)])
	assert_eq(K.trap_events(res.events, "cr"), [
		[0, "crusher:warn"], [119, "crusher:slam"], [239, "crusher:retract"],
		[239 + TrapTuning.CRUSHER_RETRACT_SUBS, "crusher:open"],
	])
	var a: MechSnap = K.mech_at(res, 116, "cr")
	assert_eq([a.kind, a.on, a.t], [MechKind.CRUSHER, false, 0.0])
	var b: MechSnap = K.mech_at(res, 120, "cr")
	assert_eq([b.on, b.t, b.warn], [true, 1.0, 0.0])
	var mid: MechSnap = K.mech_at(res, 272, "cr")
	assert_true(mid.on, "solid while retracting")
	assert_near(mid.t, 1.0 - 32.0 / TrapTuning.CRUSHER_RETRACT_SUBS, D5)
	var c: MechSnap = K.mech_at(res, 300, "cr")
	assert_eq([c.on, c.t], [false, 0.0])
	# Inferred from the first two cells: the piston travels toward higher rows.
	var d0: MechSnap = K.mech_at(res, 0, "cr")
	assert_true(d0.has_dir, "dir inferred")
	assert_near(d0.dir, PI / 2.0, D6)


func test_crusher_kills_a_self_on_a_cell_at_the_stroke_and_only_walls_off_one_beside_it() -> void:
	var res: Resolution = S.resolve(K.room([_wall_crusher()]), [K.stand(0, 5.5, 4.5), K.stand(1, 4.5, 4.5)])
	assert_eq(K.tsd(S.events_of(res.events, SimEventType.SELF_DEATH)), [[0, 119, "crushed by crusher cr"]])
	assert_eq(S.events_of(res.events, SimEventType.DESYNC).size(), 0)
	var a: ActorSnap = K.last_frame(res).actors[1]
	assert_eq([a.life, a.synced], [OD.LifeState.ALIVE, true])
	assert_eq(K.first_trap(res.events, "crusher:slam").power, 1.0)


func test_crusher_is_not_lethal_to_touch_a_walker_desyncs_against_it_and_recovers_after_the_retract() -> void:
	# Extended for beats [0.5, 3). The walker reaches the piston face around substep 176.
	var level: LevelDef = K.room([_wall_crusher(K.beats(8, 0.5, 3))])
	var walker: ODTape = S.path_tape(0, 1.0, 240, [[0, 2.5, 5.5], [120, 8.5, 5.5]])
	var res: Resolution = S.resolve(level, [walker])
	assert_eq(S.events_of(res.events, SimEventType.SELF_DEATH).size(), 0)
	var desync: Array[SimEvent] = S.events_of(res.events, SimEventType.DESYNC, 0)
	assert_eq(desync.size(), 1)
	if desync.size() == 1:
		assert_eq(desync[0].detail, "blocked by crusher cr")
		assert_true(desync[0].sub > 160 and desync[0].sub < 200, "desyncs at the piston face (%d)" % desync[0].sub)
	# While the piston is out the spark waits on the near side: the piston seals the room.
	var waiting: ActorSnap = K.frame_from(res.frames, 340).actors[0]
	assert_false(waiting.synced)
	assert_true(waiting.has_spark and waiting.spark.x < 5.0 - Tuning.BASE.spark_radius + 1e-6, "the spark waits at the piston")
	assert_true(waiting.x > 6.0, "the projection walks on")
	# It opens at 359 + 60; only then can the spark cross and catch the projection.
	var open: int = -1
	for p: Variant in K.trap_events(res.events, "cr"):
		if (p as Array)[1] == "crusher:open":
			open = (p as Array)[0]
			break
	assert_eq(open, 359 + TrapTuning.CRUSHER_RETRACT_SUBS)
	var resync: Array[SimEvent] = S.events_of(res.events, SimEventType.RESYNC, 0)
	assert_eq(resync.size(), 1)
	if resync.size() == 1:
		assert_true(resync[0].sub > open, "resyncs after the piston opens")
	var end: ActorSnap = K.last_frame(res).actors[0]
	assert_eq([end.life, end.synced, end.x, end.has_spark], [OD.LifeState.ALIVE, true, 8.5, false])
	assert_true(K.has_note(res, "crusher cr"), "the outcome notes name the crusher")


func test_a_self_dodging_through_the_stroke_survives_but_is_desynced_by_the_solid_piston() -> void:
	# Standing on the cell, dodging on the spot: i-frames cover the stroke substep 119.
	var dodger: ODTape = S.path_tape(0, 1.0, 240, [[0, 5.5, 4.5]], [[28, ActionKind.DODGE]])
	var res: Resolution = S.resolve(K.room([_wall_crusher()]), [dodger])
	assert_eq(S.events_of(res.events, SimEventType.SELF_DEATH).size(), 0)
	var d: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.DESYNC):
		d.append([e.sub, e.detail])
	assert_eq(d, [[120, "blocked by crusher cr"]])


func test_crusher_crushes_enemies_on_the_stroke_and_pushes_survivors_out() -> void:
	var res: Resolution = S.resolve(
		K.room([
			_wall_crusher(), K.sleeper("g", "grunt", 5.5, 2.5), K.sleeper("b", "brute", 5.5, 4.5),
			K.sleeper("dr", "drone", 5.5, 6.5), K.sleeper("tough", "grunt", 5.4, 7.5, {"hp": 5}),
		]),
		[K.stand(0, 2.5, 2.5)]
	)
	assert_eq(K.isd(S.events_of(res.events, SimEventType.KILL)), [["g", 119, "crusher"], ["b", 119, "crusher"], ["dr", 119, "crusher"]])
	# The tough grunt (5 hp) takes 3 and is shoved out to the nearest side.
	var tough: EnemySnap = K.enemy_at(res, 124, "tough")
	assert_eq([tough.alive, tough.hp], [true, 2])
	assert_true(tough.x <= 5.0 - 0.32 + 1e-6, "pushed out west (%s)" % tough.x)
	# Bodies die where they were crushed.
	var g: EnemySnap = K.enemy_at(res, 124, "g")
	assert_eq([g.x, g.y], [5.5, 2.5])


func test_crusher_kills_the_live_self_on_the_stroke_and_its_body_is_pushed_out_never_deleted() -> void:
	var level: LevelDef = K.room([_wall_crusher()], {"start": Vector2(5.5, 4.5)})
	var take: TestScript.TakeResult = S.record_take(level, 0, 1.0, S.input_script())
	assert_eq(K.details(S.events_of(take.events, SimEventType.SELF_DEATH)), ["crushed by crusher cr"])
	var after: ActorSnap = K.frame_from(take.frames, 140).actors[0]
	assert_eq(after.life, OD.LifeState.REC_GHOST)
	var r: float = Tuning.BASE.actor_radius
	assert_true(after.x <= 5.0 - r + 1e-6 or after.x >= 6.0 + r - 1e-6, "the body is outside the piston (%s)" % after.x)


func test_crusher_starts_extended_with_no_stroke_when_its_signal_is_true_at_beat_zero() -> void:
	var res: Resolution = S.resolve(K.room([_wall_crusher(K.ALWAYS), K.sleeper("g", "grunt", 3.5, 5.5)]), [K.stand(0, 2.5, 2.5)])
	assert_eq(K.trap_events(res.events, "cr"), [])
	var m: MechSnap = K.mech_at(res, 0, "cr")
	assert_eq([m.on, m.t], [true, 1.0])
	assert_eq(S.events_of(res.events, SimEventType.KILL).size(), 0)


func test_crusher_re_extends_without_a_second_stroke_if_the_signal_returns_during_the_retract() -> void:
	# Off for an eighth of a beat (15 substeps): shorter than the retract.
	var level: LevelDef = K.room([_wall_crusher({"or": [K.beats(8, 1, 2), K.beats(8, 2.125, 3)]}), K.sleeper("g", "grunt", 3.5, 5.5)])
	var res: Resolution = S.resolve(level, [K.stand(0, 2.5, 2.5)])
	assert_eq(K.trap_events_except(res.events, "cr", "crusher:warn"), [
		[119, "crusher:slam"], [239, "crusher:retract"], [254, "crusher:hold"], [359, "crusher:retract"],
		[359 + TrapTuning.CRUSHER_RETRACT_SUBS, "crusher:open"],
	])

# ───────────────────────────── flame ─────────────────────────────


func test_flame_burns_selves_on_the_covered_tiles_while_on_and_nothing_off_its_lane() -> void:
	var res: Resolution = S.resolve(K.room([_flame()]), [K.stand(0, 3.5, 5.5), K.stand(1, 3.5, 4.5), K.stand(2, 9.5, 5.5)])
	assert_eq(K.tsd(S.events_of(res.events, SimEventType.SELF_DEATH)), [[0, 119, "burned by flame jet fl"]])
	assert_eq(K.trap_events(res.events, "fl").slice(0, 3), [[0, "flame:warn"], [119, "flame:on"], [239, "flame:off"]])
	var m: MechSnap = K.mech_at(res, 120, "fl")
	assert_eq([m.kind, m.on, m.reach, m.dir], [MechKind.FLAME, true, 8.0, 0.0])
	# Range 8 from the nozzle at column 0 covers columns 1..8; column 9 is out of reach.
	assert_eq(K.last_frame(res).actors[2].life, OD.LifeState.ALIVE)


func test_flame_is_cut_short_by_a_closed_door_and_released_the_moment_it_opens() -> void:
	# The door at column 5 is shut until tape 1 throws the switch at local tick 150 (substep 600).
	var level: LevelDef = K.room([
		_flame(K.ALWAYS),
		{"kind": "switch", "id": "sw", "x": 2.5, "y": 2.5},
		{"kind": "door", "id": "door", "cells": K.cells([[5, 5]]), "openWhen": {"sig": "sw"}},
	])
	var behind: ODTape = K.stand(0, 7.5, 5.5)
	var opener: ODTape = S.path_tape(1, 1.0, 240, [[0, 2.5, 3.2]], [[150, ActionKind.INTERACT]])
	var shut: Resolution = S.resolve(level, [behind])
	assert_eq(S.events_of(shut.events, SimEventType.SELF_DEATH).size(), 0)
	assert_eq(K.mech_at(shut, 400, "fl").reach, 4.0)
	var opened: Resolution = S.resolve(level, [behind, opener])
	var door_open: int = -1
	for e: SimEvent in S.events_of(opened.events, SimEventType.DOOR, -1, "door"):
		if e.detail == "open":
			door_open = e.sub
			break
	var death: Array[SimEvent] = S.events_of(opened.events, SimEventType.SELF_DEATH, 0)
	assert_eq(death.size(), 1)
	# Traps run after mechanisms in the same substep: the fire is through as the door turns passable.
	if death.size() == 1:
		assert_eq(death[0].sub, door_open)
	assert_eq(K.mech_at(opened, door_open + 4, "fl").reach, 8.0)


func test_flame_is_stopped_by_an_extended_crusher_and_passes_over_a_low_barrier() -> void:
	var map: Array[String] = ["############", "#..........#", "#..........#", "#..........#", "#..........#", "#..=.......#", "#..........#", "#..........#", "#..........#", "############"]
	var level: LevelDef = K.room([_flame(K.ALWAYS), {"kind": "crusher", "id": "cr", "cells": K.cells([[7, 5]]), "extendWhen": K.beats(8, 2, 4)}], {"map": map, "start": Vector2(1.5, 1.5)})
	var res: Resolution = S.resolve(level, [K.stand(0, 2.5, 2.5)])
	assert_eq(K.mech_at(res, 60, "fl").reach, 8.0)
	assert_eq(K.mech_at(res, 300, "fl").reach, 6.0)


func test_flame_burns_every_enemy_type_on_contact_and_once_per_beat_drones_included() -> void:
	var res: Resolution = S.resolve(K.room([_flame(K.ALWAYS), K.sleeper("dr", "drone", 2.5, 5.5), K.sleeper("b", "brute", 4.5, 5.5), K.sleeper("t", "turret", 6.5, 5.5)]), [K.stand(0, 2.5, 2.5)])
	assert_eq(K.isd(S.events_of(res.events, SimEventType.KILL)), [["t", 0, "flame"], ["dr", 120, "flame"], ["b", 240, "flame"]])


func test_flame_does_not_hurt_the_recording_ghost() -> void:
	var cl: Array = []
	for r: int in [1, 2, 3, 4, 6, 7, 8]:
		cl.append([2, r])
	var level: LevelDef = K.room([_flame(K.ALWAYS), {"kind": "crusher", "id": "cr", "cells": K.cells(cl), "extendWhen": K.NEVER}], {"start": Vector2(3.5, 3.5)})
	var take: TestScript.TakeResult = S.record_take(level, 0, 1.0, S.input_script().run(0, 60, 0, 1))
	assert_eq(S.events_of(take.events, SimEventType.SELF_DEATH).size(), 1)
	assert_eq(take.frames[take.frames.size() - 1].actors[0].life, OD.LifeState.REC_GHOST)
