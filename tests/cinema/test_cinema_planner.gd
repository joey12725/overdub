extends ODTest
## The cinematic director's editor (cinema/cinema_planner.gd; CINE-01..05, MUSIC-13, PILLAR-06):
## determinism, the editorial rules, that key events get shots, graceful degradation.

const G := preload("res://cinema/cinema_grammar.gd")
const FX := preload("res://tests/cinema/cinema_fixtures.gd")

var _all_cache: Array = []


# ───────────────────────────── helpers ─────────────────────────────

func _golden(name: String) -> CinemaGolden:
	var errors: Array[String] = []
	var g := CinemaGolden.load_named(name, errors)
	for e: String in errors:
		fail(name + ": " + e)
	return g


## Every golden scenario, loaded once: [[name, golden, plan], ...].
func _all() -> Array:
	if not _all_cache.is_empty():
		return _all_cache
	var idx: Variant = load_json("res://tests/goldens/index.json")
	if not (idx is Dictionary):
		return _all_cache
	for e: Variant in ODJson.array(idx, "scenarios"):
		var n := ODJson.string(e, "name") if e is Dictionary else str(e)
		var g := _golden(n)
		if g != null:
			_all_cache.append([n, g, g.plan()])
	return _all_cache


func _showing(plan: CinemaPlan, kind: StringName) -> CinemaShot:
	for s: CinemaShot in plan.shots:
		if s.shows.has(kind):
			return s
	return null


func _event_index(res: Resolution, type: StringName, nth: int = 0) -> int:
	var k := 0
	for i: int in res.events.size():
		if res.events[i].type == type:
			if k == nth:
				return i
			k += 1
	return -1


## The event at `idx` is explained by a shot that is on screen at its beat.
func _assert_event_shot(plan: CinemaPlan, res: Resolution, idx: int, label: String) -> void:
	if not assert_true(idx >= 0, label + ": event exists"):
		return
	var s := plan.shot_for_event(idx)
	if not assert_true(s != null, label + ": some shot explains event %d (%s)" % [idx, res.events[idx].type]):
		return
	var b := float(res.events[idx].sub) / plan.subs_per_beat
	assert_true(s.contains_beat(b) or (b >= float(plan.horizon_beats) - 0.02 and s.end_beat == plan.horizon_beats), label + ": the shot [%d, %d) is on screen at beat %.2f" % [s.start_beat, s.end_beat, b])


func _check_rules(label: String, plan: CinemaPlan, res: Resolution) -> void:
	var shots := plan.shots
	if not assert_true(not shots.is_empty(), label + ": has shots"):
		return
	assert_eq(shots[0].start_beat, 0, label + ": starts on beat 0")
	assert_eq(shots[shots.size() - 1].end_beat, plan.horizon_beats, label + ": ends on the horizon (CINE-05)")
	for i: int in shots.size():
		var s := shots[i]
		assert_true(s.length() >= G.MIN_SHOT_BEATS or plan.horizon_beats < G.MIN_SHOT_BEATS, label + ": shot %d is %d beats (min %d)" % [i, s.length(), G.MIN_SHOT_BEATS])
		if i > 0:
			assert_eq(s.start_beat, shots[i - 1].end_beat, label + ": shot %d follows shot %d without gap or overlap" % [i, i - 1])
		assert_true([G.EMPHASIS_NONE, G.EMPHASIS_LETTERBOX, G.EMPHASIS_TIME_RIPPLE, G.EMPHASIS_SPLIT].has(s.emphasis), label + ": one known emphasis")
		if s.emphasis == G.EMPHASIS_SPLIT:
			assert_true(s.panes.size() >= 2 and s.panes.size() <= 4, label + ": a split has 2..4 panes")
		else:
			assert_true(s.panes.is_empty(), label + ": panes only on a split")
		assert_eq(s.letterbox > G.LETTERBOX_BASE + 1e-6, s.emphasis == G.EMPHASIS_LETTERBOX, label + ": deep letterbox only as the shot's emphasis")
		assert_eq(s.ripple > 0.0, s.emphasis == G.EMPHASIS_TIME_RIPPLE, label + ": ripple only as the shot's emphasis")
		assert_true(s.contains_beat(s.key_beat), label + ": shot %d's key beat is on screen" % i)
		# The cut rule, by the planner's own definition and by an independent narrow one.
		if i + 1 < shots.size():
			var bl := CinemaPlanner.blockers(plan.actions, s, shots[i + 1])
			assert_true(bl.is_empty(), label + ": cut at beat %d does not cut away mid-action (%s)" % [s.end_beat, _actions_text(bl)])
			var b := float(s.end_beat)
			for a: CinemaTypes.Action in plan.actions:
				if a.what != "swing" or a.tapes.is_empty() or a.tapes[0] != s.focus_tape:
					continue
				if shots[i + 1].framing == G.FRAMING_WIDE or shots[i + 1].tapes.has(a.tapes[0]):
					continue
				assert_false(b > a.start_beat + 1e-6 and b < a.impact_beat - 1e-6, label + ": no cut away from the tracked self between wind-up %.2f and impact %.2f" % [a.start_beat, a.impact_beat])
	assert_true(shots.size() <= plan.shot_cap, label + ": %d shots within the proportional cap %d" % [shots.size(), plan.shot_cap])
	# Cues: never cuts; sweeps on bar lines; chord flashes only over un-emphasised shots.
	for c: CinemaTypes.Cue in plan.cues:
		if c.kind == G.CUE_BAR_SWEEP or c.kind == G.CUE_CHORD_FLASH:
			assert_eq(int(c.beat) % OD.BEATS_PER_BAR, 0, label + ": %s on a bar line" % c.kind)
			assert_near(c.beat, roundf(c.beat), 1e-9, label + ": on a whole beat")
		if c.kind == G.CUE_CHORD_FLASH:
			assert_eq(plan.shot_at(c.beat).emphasis, G.EMPHASIS_NONE, label + ": no chord flash over another emphasis")


func _actions_text(bl: Array[CinemaTypes.Action]) -> String:
	var t := ""
	for a: CinemaTypes.Action in bl:
		t += "%s %.2f-%.2f " % [a.what, a.start_beat, a.impact_beat]
	return t


# ───────────────────────────── determinism ─────────────────────────────

func test_determinism_same_input_same_plan() -> void:
	for n: String in ["ghost-rescue", "sandbox-bot-two-cassettes", "boss-coordinated-win", "desync-route-reopened-by-other"]:
		var g := _golden(n)
		if g == null:
			continue
		var a := JSON.stringify(CinemaPlanner.plan(g.resolution, g.level, g.ctx).to_dict())
		var b := JSON.stringify(CinemaPlanner.plan(g.resolution.copy(), g.level.copy(), g.ctx).to_dict())
		var c := JSON.stringify(g.plan().to_dict())
		assert_eq(a, b, n + ": a copy of the resolution plans identically")
		assert_eq(a, c, n + ": planning twice gives the same plan")


func test_planning_does_not_touch_the_resolution_cine_04() -> void:
	var g := _golden("sandbox-bot-two-cassettes")
	if g == null:
		return
	var before := JSON.stringify(g.resolution.to_dict())
	g.plan()
	assert_eq(JSON.stringify(g.resolution.to_dict()), before, "the resolved frames and events are presented, never altered")


# ───────────────────────────── the editorial rules on every golden ─────────────────────────────

func test_rules_hold_on_every_golden() -> void:
	var all := _all()
	assert_true(all.size() >= 100, "loaded the golden scenarios (%d)" % all.size())
	for row: Array in all:
		_check_rules(row[0], row[2], (row[1] as CinemaGolden).resolution)


func test_opens_wide_on_beat_zero_with_every_self() -> void:
	for row: Array in _all():
		var plan: CinemaPlan = row[2]
		var g: CinemaGolden = row[1]
		var s := plan.shots[0]
		assert_eq(s.framing, G.FRAMING_WIDE, row[0] + ": opening is wide")
		assert_eq(s.start_beat, 0, row[0] + ": opening on beat 0")
		var f := g.resolution.frames[0] if not g.resolution.frames.is_empty() else null
		if f == null:
			continue
		for a: ActorSnap in f.actors:
			var found := false
			for c: CinemaTypes.Callout in s.callouts:
				if c.tape == a.tape:
					found = true
			assert_true(found, row[0] + ": the opening calls out self %s" % OD.tape_letter(a.tape))


func test_ends_on_the_survivors() -> void:
	for row: Array in _all():
		var plan: CinemaPlan = row[2]
		var g: CinemaGolden = row[1]
		if not g.resolution.outcome.win or plan.shots.size() < 2:
			continue
		var last := plan.shots[plan.shots.size() - 1]
		for t: int in g.resolution.outcome.survivors:
			var found := false
			for c: CinemaTypes.Callout in last.callouts:
				if c.tape == t and c.role == G.ROLE_SURVIVOR:
					found = true
			assert_true(found, row[0] + ": the last shot calls out survivor %s" % OD.tape_letter(t))


func test_shot_count_is_proportional_to_length() -> void:
	var g := _golden("sandbox-bot-two-cassettes")
	if g == null:
		return
	var plan := g.plan()
	assert_eq(plan.horizon_beats, 64, "sandbox runs 16 bars")
	assert_eq(plan.shot_cap, 23, "cap = ceil(64 / 3) + 1")
	assert_true(plan.shots.size() >= 5, "a 64-beat performance gets several shots (%d)" % plan.shots.size())
	var short := _golden("combat-knockback-changes-later-hit")
	if short != null:
		var p2 := short.plan()
		assert_true(p2.shots.size() <= 3, "a one-bar run gets at most three shots (%d)" % p2.shots.size())


# ───────────────────────────── key events get shots ─────────────────────────────

func test_rescue_from_an_earlier_take_ghost_06() -> void:
	var g := _golden("ghost-rescue")
	if g == null:
		return
	assert_true(not g.ctx.prior_events.is_empty(), "the recording of take 1 had A's death")
	var plan := g.plan()
	var s := _showing(plan, G.KIND_RESCUE)
	if assert_true(s != null, "a shot shows the rescue"):
		assert_true(s.tapes.has(0) and s.tapes.has(1), "both A (rescued) and B (rescuer) are in it")
		assert_true(s.reason.contains("Last take A died"), "reason names the earlier death: " + s.reason)
	_assert_event_shot(plan, g.resolution, _event_index(g.resolution, SimEventType.KILL, 0), "B kills the turret")
	_assert_event_shot(plan, g.resolution, _event_index(g.resolution, SimEventType.OBJECTIVE), "objective")
	# Without the context it is still a valid plan, just without the rescue.
	var bare := CinemaPlanner.plan(g.resolution, g.level, null)
	assert_true(_showing(bare, G.KIND_RESCUE) == null, "no prior runs, no rescue")
	_check_rules("ghost-rescue bare", bare, g.resolution)


func test_shielder_pincer_is_the_climax() -> void:
	var g := _golden("enemy-shielder-two-pairs-kill")
	if g == null:
		return
	var plan := g.plan()
	var s := _showing(plan, G.KIND_CLIMAX)
	if assert_true(s != null, "climax shown"):
		assert_true(s.shows.has(G.KIND_MULTI_KILL), "the climax is the multi-self kill: %s" % [s.shows])
		assert_true(s.emphasis == G.EMPHASIS_LETTERBOX, "climax gets the letterbox emphasis")
		assert_true(s.contains_beat(2.3), "on screen at the kill")
	_assert_event_shot(plan, g.resolution, _event_index(g.resolution, SimEventType.KILL), "the kill")


func test_knockback_delivery() -> void:
	var g := _golden("combat-knockback-changes-later-hit")
	if g == null:
		return
	var plan := g.plan()
	var s := _showing(plan, G.KIND_KNOCKBACK)
	if assert_true(s != null, "knockback link shown"):
		assert_true(s.reason.contains("knocks"), s.reason)
		# Cause first: B's hit is on screen, framed, in this shot or an earlier one (in a one-bar run
		# the two-beat wide opening is where the shove happens; the knockback shot takes the effect).
		var hi := _event_index(g.resolution, SimEventType.HIT, 0)
		if assert_true(hi >= 0, "the knockback hit exists"):
			var hb := float(g.resolution.events[hi].sub) / plan.subs_per_beat
			var on := plan.shot_at(hb)
			var hp := Vector2(g.resolution.events[hi].x, g.resolution.events[hi].y)
			assert_true(on != null and on.start_beat <= s.start_beat, "the hit at %.2f is on screen no later than the knockback shot" % hb)
			if on != null:
				assert_true(on.framing == G.FRAMING_WIDE or on.frames_point(hp), "the shot on screen at the hit frames it")
	_assert_event_shot(plan, g.resolution, _event_index(g.resolution, SimEventType.KILL), "the kill")
	_assert_event_shot(plan, g.resolution, _event_index(g.resolution, SimEventType.HIT, 0), "the knockback hit")


func test_desync_and_resync_with_the_reopener() -> void:
	var g := _golden("desync-route-reopened-by-other")
	if g == null:
		return
	var plan := g.plan()
	var s := _showing(plan, G.KIND_DESYNC)
	if assert_true(s != null, "desync shown"):
		assert_true(s.reason.contains("B reopens"), "names the self that reopened the route: " + s.reason)
	_assert_event_shot(plan, g.resolution, _event_index(g.resolution, SimEventType.DESYNC), "desync")
	_assert_event_shot(plan, g.resolution, _event_index(g.resolution, SimEventType.RESYNC), "resync")


func test_plate_hold_while_another_crosses() -> void:
	var g := _golden("mech-plate-holds-laser-off")
	if g == null:
		return
	var plan := g.plan()
	var s := _showing(plan, G.KIND_PLATE_HOLD)
	if assert_true(s != null, "plate hold shown"):
		assert_true(s.reason.contains("holds the plate"), s.reason)
	_assert_event_shot(plan, g.resolution, _event_index(g.resolution, SimEventType.LASER), "laser off")


func test_boss_phases_and_climax() -> void:
	var g := _golden("boss-coordinated-win")
	if g == null:
		return
	var plan := g.plan()
	assert_true(_showing(plan, G.KIND_BOSS_PHASE) != null, "a boss phase break is shown")
	assert_true(_showing(plan, G.KIND_CLIMAX) != null, "the boss kill is the climax")
	_assert_event_shot(plan, g.resolution, _event_index(g.resolution, SimEventType.KILL), "boss kill")


func test_boss_memory_moment() -> void:
	var g := _golden("boss-memory-exploited")
	if g == null:
		return
	var plan := g.plan()
	assert_true(_showing(plan, G.KIND_BOSS_RECALL) != null, "the memory strike that lands is shown")
	_assert_event_shot(plan, g.resolution, _event_index(g.resolution, SimEventType.BOSS_RECALL), "recall")


func test_sandbox_kills_and_mechanisms() -> void:
	var g := _golden("sandbox-bot-two-cassettes")
	if g == null:
		return
	var plan := g.plan()
	for k: int in 3:
		_assert_event_shot(plan, g.resolution, _event_index(g.resolution, SimEventType.KILL, k), "kill %d" % k)
	_assert_event_shot(plan, g.resolution, _event_index(g.resolution, SimEventType.DOOR), "the gate opens")
	var climax := _showing(plan, G.KIND_CLIMAX)
	if assert_true(climax != null, "climax"):
		assert_true(climax.contains_beat(5.8), "climax on screen at the last kill")


# ───────────────────────────── synthetic resolutions ─────────────────────────────

func test_event_free_run_is_one_graceful_wide_shot() -> void:
	var level := FX.make_level(FX.TWO_ROOMS)
	var fx := FX.new(level, 16)
	fx.path(0, [Vector2(2.5, 2.5), Vector2(4.5, 4.5)])
	fx.path(1, [Vector2(9.5, 2.5), Vector2(10.5, 4.5)])
	var res := fx.build()
	res.events.append(SimEvent.make(1600, SimEventType.STEP, 3, 3).with_tape(0).with_detail("alive"))
	res.events.append(SimEvent.make(1900, SimEventType.TAPE_END, 3, 3).with_tape(0))
	var plan := CinemaPlanner.plan(res, level)
	assert_eq(plan.shots.size(), 1, "one shot")
	var s := plan.shots[0]
	assert_eq(s.framing, G.FRAMING_WIDE, "wide")
	assert_eq([s.start_beat, s.end_beat], [0, 16], "the whole timeline")
	assert_eq(s.emphasis, G.EMPHASIS_NONE, "no emphasis")
	assert_eq(s.move, G.MOVE_ORBIT, "a gentle orbit over a long hold")
	assert_eq(s.callouts.size(), 2, "both selves called out")
	_check_rules("event-free", plan, res)
	# Truly empty input (no frames, no events) still plans.
	var empty := Resolution.new()
	empty.horizon_subs = 0
	var p2 := CinemaPlanner.plan(empty, level)
	assert_eq(p2.shots.size(), 1, "an empty resolution: one wide shot")
	assert_eq(p2.shots[0].end_beat, level.horizon_bars * OD.BEATS_PER_BAR, "over the level's horizon")


func _door_level() -> LevelDef:
	return FX.make_level(FX.TWO_ROOMS, [
		{"kind": "switch", "id": "sw", "x": 2.5, "y": 1.5},
		{"kind": "door", "id": "d1", "cells": [{"c": 6, "r": 3}], "openWhen": {"sig": "sw"}},
		{"kind": "exit", "id": "exit", "c": 11, "r": 3},
	], {"type": "reach", "text": "Out"})


func test_switch_opens_the_door_for_another_self() -> void:
	var level := _door_level()
	var fx := FX.new(level, 16)
	fx.path(0, [Vector2(2.5, 2.5), Vector2(2.5, 1.8), Vector2(2.5, 1.8), Vector2(2.5, 1.8)])
	# B waits west of the door and walks through after it opens (door at x 6.5, beat ~8).
	fx.path(1, [Vector2(4.5, 3.5), Vector2(4.5, 3.5), Vector2(6.5, 3.5), Vector2(11.5, 3.5)])
	fx.ev(4.0, SimEventType.INTERACT, Vector2(2.5, 1.5), 0, "sw", "on")
	fx.ev(4.1, SimEventType.DOOR, Vector2(6.5, 3.5), -1, "d1", "open")
	fx.ev(15.99, SimEventType.OBJECTIVE, Vector2.ZERO, -1, "", "reach")
	var res := fx.build()
	var plan := CinemaPlanner.plan(res, level)
	var s := _showing(plan, G.KIND_OPENED_FOR)
	if assert_true(s != null, "who opened what for whom"):
		assert_true(s.reason.contains("A throws") and s.reason.contains("B goes through"), s.reason)
		assert_true(s.tapes.has(0) and s.tapes.has(1), "both selves")
	_check_rules("door-for", plan, res)
	assert_true(_showing(plan, G.KIND_CLIMAX) != null, "reaching the exit is the climax")


func test_simultaneous_far_rooms_request_a_split_in_cassette_colours() -> void:
	var level := FX.make_level(FX.FAR_ROOMS, [
		{"kind": "plate", "id": "p1", "c": 2, "r": 2},
		{"kind": "laser", "id": "beam", "from": {"x": 19.5, "y": 1.0}, "to": {"x": 19.5, "y": 6.0}, "onWhen": {"not": {"sig": "p1"}}},
	])
	var fx := FX.new(level, 16)
	fx.path(0, [Vector2(2.5, 2.5)])
	# C crosses the beam (x 19.5) around beat 6 in the far room.
	fx.path(2, [Vector2(17.5, 3.5), Vector2(17.5, 3.5), Vector2(21.5, 3.5), Vector2(21.5, 3.5)])
	fx.ev(5.0, SimEventType.PLATE, Vector2(2.5, 2.5), -1, "p1", "on")
	fx.ev(5.0, SimEventType.LASER, Vector2(19.5, 3.5), -1, "beam", "off")
	var res := fx.build()
	var plan := CinemaPlanner.plan(res, level)
	var s := _showing(plan, G.KIND_PLATE_HOLD)
	if assert_true(s != null, "plate hold shown"):
		assert_eq(s.emphasis, G.EMPHASIS_SPLIT, "the simultaneity is the point: split")
		assert_eq(s.panes.size(), 2, "two panes")
		var tapes: Array[int] = []
		for p: CinemaTypes.Pane in s.panes:
			tapes.append(p.tape)
			assert_eq(p.color, OD.tape_color(p.tape), "pane in its cassette colour")
		tapes.sort()
		assert_eq(tapes, [0, 2], "A (holding) and C (crossing)")
	_check_rules("split", plan, res)


func test_boss_memory_fooled_gets_a_time_ripple() -> void:
	var level := FX.make_level(FX.TWO_ROOMS, [{"kind": "enemy", "id": "b1", "type": "boss", "x": 9.5, "y": 3.5}], {"type": "boss", "text": "Boss"})
	var fx := FX.new(level, 16)
	fx.enemy("b1", EnemyType.BOSS, Vector2(9.5, 3.5))
	fx.path(0, [Vector2(8.5, 2.5), Vector2(8.5, 2.5), Vector2(10.5, 4.5), Vector2(10.5, 4.5)])
	var rec := fx.ev(6.0, SimEventType.BOSS_RECALL, Vector2(8.5, 2.5), 0, "b1", "dwell")
	rec.with_power(8.0)
	fx.ev(6.0, SimEventType.ENEMY_TELEGRAPH, Vector2(8.5, 2.5), 0, "b1", "recall")
	fx.ev(8.0, SimEventType.ENEMY_ATTACK, Vector2(8.5, 2.5), 0, "b1", "recall")
	var res := fx.build()
	var plan := CinemaPlanner.plan(res, level)
	var s := _showing(plan, G.KIND_BOSS_FOOLED)
	if assert_true(s != null, "the fooled memory is shown"):
		assert_eq(s.emphasis, G.EMPHASIS_TIME_RIPPLE, "time ripple")
		assert_true(s.contains_beat(8.0), "on screen when the remembered strike lands")
		assert_true(s.start_beat <= 6, "from the moment it remembers")
	_check_rules("boss-fooled", plan, res)


func test_trap_sprung_on_an_enemy() -> void:
	var level := FX.make_level(FX.TWO_ROOMS, [{"kind": "enemy", "id": "g1", "type": "grunt", "x": 9.5, "y": 3.5}])
	var fx := FX.new(level, 16)
	fx.path(0, [Vector2(2.5, 2.5), Vector2(4.5, 3.5)])
	fx.enemy("g1", EnemyType.GRUNT, Vector2(9.5, 3.5))
	fx.ev(7.6, SimEventType.TRAP, Vector2(9.5, 3.5), -1, "spikes", "spring")
	var k := fx.ev(8.0, SimEventType.KILL, Vector2(9.5, 3.5), -1, "g1", "trap")
	k.with_power(1.0)
	fx._enemies["g1"][2] = 8.0
	var res := fx.build()
	var plan := CinemaPlanner.plan(res, level)
	var s := _showing(plan, G.KIND_TRAP_KILL)
	if assert_true(s != null, "the trap kill is shown"):
		assert_true(s.reason.contains("springs on"), s.reason)
		assert_true(s.contains_beat(7.6) or plan.shot_at(7.6).frames_point(Vector2(9.5, 3.5)), "the trap springing is on screen")
	_assert_event_shot(plan, res, _event_index(res, SimEventType.KILL), "the kill")
	_check_rules("trap", plan, res)


func test_save_and_sacrifice() -> void:
	# C (tape 2) is cut down at beat 6 while A saves B from a grunt winding up on B at beat 10.
	var level := FX.make_level(FX.TWO_ROOMS)
	var fx := FX.new(level, 16)
	fx.path(0, [Vector2(8.5, 2.5), Vector2(9.5, 3.5)])
	fx.path(1, [Vector2(10.5, 3.5)])
	fx.path(2, [Vector2(2.5, 4.5)])
	fx.enemy("g1", EnemyType.GRUNT, Vector2(10.5, 2.5))
	fx.ev(9.0, SimEventType.ENEMY_TELEGRAPH, Vector2(10.5, 2.5), 1, "g1", "swing")
	fx.swing(0, 10.0, "g1", true)
	fx.death(2, 6.0, "struck")
	var res := fx.build()
	var plan := CinemaPlanner.plan(res, level)
	var sv := _showing(plan, G.KIND_SAVE)
	if assert_true(sv != null, "the save is shown"):
		assert_true(sv.reason.contains("winding up on B"), sv.reason)
		assert_true(sv.tapes.has(0) and sv.tapes.has(1), "saver and saved")
	_assert_event_shot(plan, res, _event_index(res, SimEventType.SELF_DEATH), "the sacrifice")
	var last := plan.shots[plan.shots.size() - 1]
	for c: CinemaTypes.Callout in last.callouts:
		if c.role == G.ROLE_SURVIVOR:
			assert_ne(c.tape, 2, "the fallen self is not called out as a survivor")
	_check_rules("save", plan, res)


func test_busy_fight_respects_every_rule() -> void:
	# Two selves trading kills every 1.5 beats for 8 bars: many candidates, few slots.
	var level := FX.make_level(FX.TWO_ROOMS, [], {}, 8)
	var fx := FX.new(level, 32)
	fx.path(0, [Vector2(2.5, 2.5), Vector2(4.5, 4.5), Vector2(2.5, 2.5)])
	fx.path(1, [Vector2(9.5, 2.5), Vector2(11.5, 4.5), Vector2(9.5, 2.5)])
	var b := 1.3
	var n := 0
	while b < 30.0:
		var id := "g%d" % n
		var t := n % 2
		fx.enemy(id, EnemyType.GRUNT, fx.pos(t, b) + Vector2(1, 0))
		fx.swing(t, b, id, true)
		n += 1
		b += 1.55
	var res := fx.build()
	var plan := CinemaPlanner.plan(res, level)
	_check_rules("busy", plan, res)
	assert_true(plan.shots.size() >= 4, "a busy fight is cut (%d shots)" % plan.shots.size())
	var shown := 0
	for m: CinemaMoment in plan.moments:
		if m.shot >= 0:
			shown += 1
	assert_true(shown >= 6, "most kills are shown or folded into shots (%d of %d)" % [shown, plan.moments.size()])
	# Deterministic under the same input.
	assert_eq(JSON.stringify(CinemaPlanner.plan(res, level).to_dict()), JSON.stringify(plan.to_dict()), "deterministic")


func test_cut_never_lands_inside_a_featured_swing() -> void:
	# A swing whose wind-up straddles the natural cut point (beat 4): the cut must move.
	var level := FX.make_level(FX.FAR_ROOMS, [], {}, 4)
	var fx := FX.new(level, 16)
	fx.path(0, [Vector2(2.5, 2.5)])
	fx.path(1, [Vector2(20.5, 3.5)])
	fx.enemy("g1", EnemyType.GRUNT, Vector2(3.5, 2.5))
	fx.enemy("g2", EnemyType.GRUNT, Vector2(21.5, 3.5))
	fx.swing(0, 2.5, "g1", true)
	fx.anim(1, 5.7, 6.4, AnimState.HEAVY_WINDUP)
	fx.swing(1, 6.4, "g2", true, "heavy")
	fx.swing(0, 9.0, "", false)
	var res := fx.build()
	var plan := CinemaPlanner.plan(res, level)
	_check_rules("windup", plan, res)
	for i: int in plan.shots.size() - 1:
		var e := plan.shots[i].end_beat
		assert_false(e == 6 and plan.shots[i].tapes.has(1) and not plan.shots[i + 1].tapes.has(1), "no cut on beat 6, between B's wind-up (5.7) and impact (6.4)")
