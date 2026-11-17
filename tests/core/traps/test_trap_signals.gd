extends ODTest
## Automated machinery that produces signals or fires on the grid: dart launchers, beam sensors,
## relays (docs/TRAPS.md 5, 7, 8). Port of prototype/tests/core/traps/signals.test.ts.

const S = preload("res://tests/helpers/script.gd")
const K = preload("res://tests/core/traps/trap_kit.gd")

const D2 := 5e-3
const D5 := 5e-6
const D6 := 5e-7

const SW := {"kind": "switch", "id": "sw", "x": 2.5, "y": 2.5}


## A launcher in the west wall firing east along row 5 every 2 beats.
func _launcher(extra: Dictionary = {}) -> Dictionary:
	return K.merged({"kind": "dart", "id": "dl", "c": 0, "r": 5, "dir": "e", "every": 2, "offset": 0}, extra)


func _toggler(index: int, at: Array) -> ODTape:
	var evs: Array = []
	for t: Variant in at:
		evs.append([int(t), ActionKind.INTERACT])
	return S.path_tape(index, 1.0, 240, [[0, 2.5, 3.2]], evs)


## A vertical beam across the room at x = 5.5.
func _beam(extra: Dictionary = {}) -> Dictionary:
	return K.merged({"kind": "sensor", "id": "trip", "from": {"x": 5.5, "y": 1}, "to": {"x": 5.5, "y": 9}}, extra)


func _crosser(index: int) -> ODTape:
	return S.path_tape(index, 1.0, 240, [[0, 3.5, 5.5], [60, 7.5, 5.5]])


func _relay(extra: Dictionary = {}) -> Dictionary:
	return K.merged({"kind": "relay", "id": "rl", "trigger": {"sig": "sw"}}, extra)


func _wall_hits(res: Resolution) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in S.events_of(res.events, SimEventType.PROJECTILE_HIT):
		if e.detail == "dart:wall":
			out.append(e)
	return out

# ───────────────────────────── dart launcher ─────────────────────────────


func test_dart_launcher_fires_on_its_beat_grid_never_aims_and_its_darts_stop_at_the_far_wall() -> void:
	var res: Resolution = S.resolve(K.room([_launcher()]), [K.stand(0, 2.5, 2.5)])
	assert_eq(K.trap_events(res.events, "dl"), [[0, "dart:fire"], [240, "dart:fire"], [480, "dart:fire"], [720, "dart:fire"]])
	var p: ProjectileSnap = K.frame_from(res.frames, 60).projectiles[0]
	assert_eq([p.archetype, p.owner_tape, p.owner_enemy, p.y, p.dir], [RangedArchetype.DART, -1, "dl", 5.5, 0.0])
	assert_eq(p.to_dict()["owner"], {"enemy": "dl"})
	# 9.87 tiles at 8 tiles/s is 296 substeps: the dart fired on beat 6 is still flying at the horizon.
	var walls: Array[SimEvent] = _wall_hits(res)
	assert_eq(K.subs(walls), [296, 536, 776])
	if not walls.is_empty():
		assert_near(walls[0].x, 11.0, D6)
	var m: MechSnap = K.mech_at(res, 4, "dl")
	assert_eq([m.kind, m.on, m.firing, m.dir], [MechKind.DART, true, true, 0.0])
	assert_near(K.mech_at(res, 120, "dl").t, 0.5, D2)
	assert_false(K.mech_at(res, 120, "dl").firing)


func test_dart_launcher_honours_offset_and_enabled_when() -> void:
	var res: Resolution = S.resolve(K.room([_launcher({"every": 4, "offset": 1, "enabledWhen": {"not": K.beats(8, 4, 8)}})]), [K.stand(0, 2.5, 2.5)])
	# Grid: beats 1 and 5; the second falls in the disabled half.
	var fires: Array = []
	for p: Variant in K.trap_events(res.events, "dl"):
		if (p as Array)[1] == "dart:fire":
			fires.append(p)
	assert_eq(fires, [[120, "dart:fire"]])


func test_dart_kills_the_first_vulnerable_self_in_its_lane_and_names_the_launcher() -> void:
	var res: Resolution = S.resolve(K.room([_launcher()]), [K.stand(0, 5.5, 5.5), K.stand(1, 8.5, 5.5), K.stand(2, 5.5, 4.5)])
	var deaths: Array[SimEvent] = S.events_of(res.events, SimEventType.SELF_DEATH)
	var td: Array = []
	for e: SimEvent in deaths:
		td.append([e.tape, e.detail])
	assert_eq(td, [[0, "shot by dart launcher dl"], [1, "shot by dart launcher dl"]])
	# The first dart stops in tape 0; the second (two beats later) flies through its ghost to tape 1.
	if deaths.size() == 2:
		assert_true(deaths[0].sub < 240 and deaths[1].sub > 240, "one dart each")
	assert_eq(K.last_frame(res).actors[2].life, OD.LifeState.ALIVE)


func test_dart_passes_through_a_self_inside_dodge_iframes_and_through_the_recording_ghost() -> void:
	# The first dart reaches x ~ 5.08 at substep ~119: a dodge at tick 28 covers substeps [116, 156).
	var dodger: ODTape = S.path_tape(0, 1.0, 240, [[0, 5.5, 5.5], [28, 5.5, 5.5], [42, 5.5, 3.5]], [[28, ActionKind.DODGE]])
	var res: Resolution = S.resolve(K.room([_launcher({"every": 8})]), [dodger])
	assert_eq(S.events_of(res.events, SimEventType.SELF_DEATH).size(), 0)
	var level: LevelDef = K.room([_launcher({"every": 1})], {"start": Vector2(5.5, 5.5)})
	var take: TestScript.TakeResult = S.record_take(level, 0, 1.0, S.input_script())
	assert_eq(S.events_of(take.events, SimEventType.SELF_DEATH).size(), 1)
	assert_eq(take.frames[take.frames.size() - 1].actors[0].life, OD.LifeState.REC_GHOST)


func test_dart_strikes_enemies_in_its_lane_one_damage_a_stagger_no_knockback_credited_to_the_launcher() -> void:
	var res: Resolution = S.resolve(K.room([_launcher(), K.sleeper("g", "grunt", 6.5, 5.5), K.sleeper("b", "brute", 9.5, 5.5)]), [K.stand(0, 2.5, 2.5)])
	var kills: Array = []
	for e: SimEvent in S.events_of(res.events, SimEventType.KILL):
		kills.append([e.id, e.detail, e.tape])
	# The first dart stops in the grunt; the brute behind it takes the next three where it stands.
	assert_eq(kills, [["g", "dart", -1], ["b", "dart", -1]])
	assert_eq(S.events_of(res.events, SimEventType.HIT, -1, "b").size(), 3)
	var b: EnemySnap = K.enemy_at(res, 900, "b")
	assert_eq([b.alive, b.hp, b.x], [true, 1, 9.5])
	var last: EnemySnap = null
	for e: EnemySnap in K.last_frame(res).enemies:
		if e.id == "b":
			last = e
	assert_eq([last.alive, last.x], [false, 9.5])
	assert_true(res.outcome.objective_complete, "dart kills count toward eliminate")


func test_dart_is_blocked_by_an_extended_crusher_and_a_sealed_muzzle_fires_nothing() -> void:
	var level: LevelDef = K.room([
		_launcher({"every": 1}),
		{"kind": "crusher", "id": "cr", "cells": K.cells([[6, 5]]), "extendWhen": K.beats(8, 1.5, 4)},
		{"kind": "crusher", "id": "plug", "cells": K.cells([[1, 5]]), "extendWhen": K.beats(8, 5.5, 6.5)},
	])
	var res: Resolution = S.resolve(level, [K.stand(0, 9.5, 2.5)])
	var stops: Array = []
	for e: SimEvent in _wall_hits(res):
		stops.append(floori(e.x + 0.5))
	# In order of impact: the beat-1 dart meets the piston (which slammed at beat 1.5) before the
	# beat-0 dart reaches the east wall; beats 2 and 3 hit the piston face; beats 4 and 5 fly free.
	assert_eq(stops, [6, 11, 6, 6, 11, 11])
	# Beat 6 is plugged at the muzzle: no dart at all. Beat 7's dart is still flying at the horizon.
	var subs: Array = []
	for p: Variant in K.trap_events(res.events, "dl"):
		subs.append((p as Array)[0])
	assert_eq(subs, [0, 120, 240, 360, 480, 600, 840])


func test_the_parry_ability_turns_a_dart_like_any_enemy_shot() -> void:
	var level: LevelDef = K.room([_launcher({"every": 8})])
	# Heavy swing facing west: windup 16 ticks, active ticks [28, 33) = substeps [112, 132).
	var parry: ODTape = S.path_tape(0, 1.0, 240, [[0, 5.5, 5.5]], [[12, ActionKind.HEAVY, PI]])
	var res: Resolution = S.resolve(level, [parry], TestLoadout.base_loadout({"abilities": [AbilityId.PARRY]}))
	assert_eq(S.events_of(res.events, SimEventType.SELF_DEATH).size(), 0)
	var parried := false
	for e: SimEvent in S.events_of(res.events, SimEventType.PROJECTILE_HIT):
		parried = parried or (e.detail == "parry" and e.id == "dl")
	assert_true(parried, "the dart is parried")

# ───────────────────────────── sensor ─────────────────────────────


func test_sensor_is_true_exactly_while_an_effective_self_breaks_the_beam() -> void:
	var res: Resolution = S.resolve(K.room([_beam()]), [_crosser(0)])
	var ev: Array = K.trap_events(res.events, "trip")
	var ds: Array = []
	for p: Variant in ev:
		ds.append((p as Array)[1])
	assert_eq(ds, ["sensor:on", "sensor:off"])
	# The body (radius 0.3) overlaps x = 5.5 while its centre is in (5.2, 5.8): local ticks 25.5..34.5.
	if ev.size() == 2:
		assert_true(ev[0][0] >= 100 and ev[0][0] <= 104, "trips on entry (%d)" % ev[0][0])
		assert_true(ev[1][0] >= 136 and ev[1][0] <= 140, "clears on exit (%d)" % ev[1][0])
	var m: MechSnap = K.mech_at(res, 120, "trip")
	assert_eq([m.kind, m.on, m.reach], [MechKind.SENSOR, true, 8.0])
	assert_false(K.mech_at(res, 200, "trip").on)


func test_sensor_feeds_mechanisms_the_same_substep() -> void:
	var level: LevelDef = K.room([_beam(), {"kind": "door", "id": "d", "cells": K.cells([[9, 8]]), "openWhen": {"sig": "trip"}}])
	var res: Resolution = S.resolve(level, [_crosser(0)])
	var on: int = K.trap_events(res.events, "trip")[0][0]
	var open: int = -1
	for e: SimEvent in S.events_of(res.events, SimEventType.DOOR, -1, "d"):
		if e.detail == "open":
			open = e.sub
			break
	assert_eq(open, on + 17)


func test_sensor_ignores_dead_ghosts_and_desynced_projections_and_sees_the_recording_ghost() -> void:
	# Tape 0 dies on spikes before the beam: its ghost crosses unseen.
	var spiked := {"kind": "spikes", "id": "sp", "cells": K.cells([[4, 5]]), "upWhen": K.ALWAYS}
	var res: Resolution = S.resolve(K.room([_beam(), spiked]), [_crosser(0)])
	assert_eq(S.events_of(res.events, SimEventType.SELF_DEATH).size(), 1)
	assert_eq(K.trap_events(res.events, "trip"), [])
	# Tape 0 desyncs against a crusher wall before the beam; the projection crosses unseen.
	var cl: Array = []
	for r: int in range(1, 9):
		cl.append([4, r])
	var walled: LevelDef = K.room([_beam(), {"kind": "crusher", "id": "cr", "cells": K.cells(cl), "extendWhen": K.ALWAYS}])
	var res2: Resolution = S.resolve(walled, [_crosser(0)])
	assert_eq(S.events_of(res2.events, SimEventType.DESYNC).size(), 1)
	assert_eq(K.trap_events(res2.events, "trip"), [])
	# The live take: the same death, but the recording ghost still has a body and trips it.
	var take: TestScript.TakeResult = S.record_take(K.room([_beam(), spiked], {"start": Vector2(3.5, 5.5)}), 0, 1.0, S.input_script().run(0, 60, 1, 0))
	assert_eq(take.frames[take.frames.size() - 1].actors[0].life, OD.LifeState.REC_GHOST)
	assert_true(K.first_trap(take.events, "sensor:on") != null, "the recording ghost trips the beam")


func test_sensor_detects_enemies_drones_too_and_detects_narrows_who_counts() -> void:
	var belt := {"kind": "conveyor", "id": "belt", "cells": K.cells([[3, 5], [4, 5], [5, 5], [6, 5]]), "dir": "e", "speed": 2}
	var any: Resolution = S.resolve(K.room([_beam(), belt, K.sleeper("g", "grunt", 3.5, 5.5)]), [K.stand(0, 2.5, 2.5)])
	var ds: Array = []
	for p: Variant in K.trap_events(any.events, "trip"):
		ds.append((p as Array)[1])
	assert_eq(ds, ["sensor:on", "sensor:off"])
	var selves_only: Resolution = S.resolve(K.room([_beam({"detects": "selves"}), belt, K.sleeper("g", "grunt", 3.5, 5.5)]), [K.stand(0, 2.5, 2.5)])
	assert_eq(K.trap_events(selves_only.events, "trip"), [])
	var enemies_only: Resolution = S.resolve(K.room([_beam({"detects": "enemies"})]), [_crosser(0)])
	assert_eq(K.trap_events(enemies_only.events, "trip"), [])
	var drone: Resolution = S.resolve(K.room([_beam({"detects": "enemies"}), K.sleeper("dr", "drone", 5.6, 3.5)]), [K.stand(0, 2.5, 2.5)])
	assert_true(K.mech_at(drone, 0, "trip").on, "a drone trips it")


func test_sensor_is_cut_at_the_first_tile_that_blocks_shots() -> void:
	var door := {"kind": "door", "id": "d", "cells": K.cells([[5, 4]]), "openWhen": K.NEVER}
	var res: Resolution = S.resolve(K.room([_beam(), door, K.sleeper("g", "grunt", 5.5, 6.5), K.sleeper("h", "grunt", 5.5, 2.5, {"wakeWhen": {"sig": "trip"}})]), [K.stand(0, 2.5, 2.5)])
	# The grunt at row 2 (before the door) trips it; reach stops at the door face (y = 4).
	var m: MechSnap = K.mech_at(res, 0, "trip")
	assert_eq([m.on, m.reach], [true, 3.0])
	var blind: Resolution = S.resolve(K.room([_beam(), door, K.sleeper("g", "grunt", 5.5, 6.5)]), [K.stand(0, 2.5, 2.5)])
	var b: MechSnap = K.mech_at(blind, 400, "trip")
	assert_eq([b.on, b.reach], [false, 3.0])


func test_sensor_latches_when_asked_to() -> void:
	var res: Resolution = S.resolve(K.room([_beam({"latch": true})]), [_crosser(0)])
	var ds: Array = []
	for p: Variant in K.trap_events(res.events, "trip"):
		ds.append((p as Array)[1])
	assert_eq(ds, ["sensor:on"])
	assert_true(K.mech_at(res, 900, "trip").on, "stays tripped")

# ───────────────────────────── relay ─────────────────────────────


func test_relay_pulse_arms_on_the_rising_edge_fires_on_the_next_beat_and_holds_one_beat() -> void:
	# The switch goes on at local tick 10 (substep 40).
	var res: Resolution = S.resolve(K.room([SW, _relay()]), [K.stand(0, 9.5, 8.5), _toggler(1, [10])])
	assert_eq(K.trap_events(res.events, "rl"), [[40, "relay:armed"], [119, "relay:on"], [239, "relay:off"]])
	var a: MechSnap = K.mech_at(res, 80, "rl")
	assert_eq([a.kind, a.on, a.warn], [MechKind.RELAY, false, 1.0])
	assert_near(a.t, (80.0 - 41.0) / (120.0 - 41.0), D5)
	var b: MechSnap = K.mech_at(res, 120, "rl")
	assert_eq([b.on, b.warn, b.t], [true, 0.0, 0.0])


func test_relay_quantize_delay_and_hold_are_in_master_beats_and_quantize_0_fires_at_once() -> void:
	var res: Resolution = S.resolve(
		K.room([SW, _relay({"quantize": 2, "delay": 1, "hold": 0.5}), _relay({"id": "now", "quantize": 0, "hold": 0.25})]),
		[K.stand(0, 9.5, 8.5), _toggler(1, [10])]
	)
	assert_eq(K.trap_events_except(res.events, "rl", "relay:armed"), [[359, "relay:on"], [419, "relay:off"]])
	assert_eq(K.trap_events_except(res.events, "now", "relay:armed"), [[40, "relay:on"], [70, "relay:off"]])


func test_relay_ignores_triggers_while_armed_or_pulsing_and_publishes_armed() -> void:
	var level: LevelDef = K.room([SW, _relay({"hold": 2}), {"kind": "door", "id": "d", "cells": K.cells([[9, 8]]), "openWhen": {"sig": "rl.armed"}}])
	var res: Resolution = S.resolve(level, [K.stand(0, 9.5, 2.5), _toggler(1, [10, 21, 32, 43, 54])])
	assert_eq(K.trap_events(res.events, "rl"), [[40, "relay:armed"], [119, "relay:on"], [359, "relay:off"]])
	assert_eq(K.details(S.events_of(res.events, SimEventType.DOOR, -1, "d")), ["open", "closed"])


func test_relay_latch_stays_on_and_toggle_flips_on_each_firing() -> void:
	var latch: Resolution = S.resolve(K.room([SW, _relay({"mode": "latch"})]), [K.stand(0, 9.5, 8.5), _toggler(1, [10, 80, 150])])
	assert_eq(K.trap_events(latch.events, "rl"), [[40, "relay:armed"], [119, "relay:on"]])
	assert_true(K.mech_at(latch, 950, "rl").on, "latched")
	# Rising edges at ticks 10 and 150 (the press at 80 turns the switch off).
	var toggle: Resolution = S.resolve(K.room([SW, _relay({"mode": "toggle"})]), [K.stand(0, 9.5, 8.5), _toggler(1, [10, 80, 150])])
	assert_eq(K.trap_events_except(toggle.events, "rl", "relay:armed"), [[119, "relay:on"], [719, "relay:off"]])


func test_relay_gives_a_signal_driven_hazard_its_telegraph() -> void:
	var level: LevelDef = K.room([SW, _relay({"delay": 1}), {"kind": "crusher", "id": "cr", "cells": K.cells([[6, 5]]), "extendWhen": {"sig": "rl"}}])
	var res: Resolution = S.resolve(level, [K.stand(0, 9.5, 8.5), _toggler(1, [10])])
	# Armed at 40, fires at beat 2 (substep 239): the crusher warns from one beat before the slam.
	var slam: int = -1
	var warn: int = -1
	for p: Variant in K.trap_events(res.events, "cr"):
		if (p as Array)[1] == "crusher:slam" and slam < 0:
			slam = (p as Array)[0]
		if (p as Array)[1] == "crusher:warn" and warn < 0:
			warn = (p as Array)[0]
	assert_eq(slam, 239)
	assert_true(warn >= 119 and warn <= 135, "warns a beat ahead (%d)" % warn)
	assert_near(K.mech_at(res, 180, "cr").warn, 0.5, D2)
	assert_eq(K.mech_at(res, 60, "cr").warn, 0.0)
