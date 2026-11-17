extends ODTest
## Port of prototype/tests/core/foundation/time.test.ts: the level clock, tape_phase_at, event
## crossings (against an independent substep oracle) and end-of-tape boundaries.

const STOP := OD.EndMode.STOP
const REPEAT := OD.EndMode.REPEAT
const REVERSE := OD.EndMode.REVERSE


func _ev(tick: int, kind: StringName = ActionKind.LIGHT) -> TapeEvent:
	return TapeEvent.make(tick, kind, 0, 0, 0, 0, 0)


func _mk_tape(speed: float, end_mode: int, ticks: int, events: Array[TapeEvent] = []) -> ODTape:
	var t := ODTape.create(0, speed, end_mode, ticks)
	t.events = events
	return t


func _phase_eq(p: TapePhase, tick: float, dir: int, traversal: int, ended: bool, msg: String = "") -> bool:
	return assert_true(p.equals(TapePhase.make(tick, dir, traversal, ended)),
		"%s: expected %s, got %s" % [msg, TapePhase.make(tick, dir, traversal, ended).to_dict(), p.to_dict()])

# ── level clock ──


func test_converts_beats_ticks_and_substeps_at_bpm_120() -> void:
	var level := TestLevels.make_level({"bpm": 120, "bars": 4, "horizonBars": 8})
	assert_eq(ODTime.ticks_per_beat(level), 30)
	assert_eq(ODTime.subs_per_beat(level), 120)
	assert_eq(ODTime.tape_ticks(level), 480)
	assert_eq(ODTime.horizon_subs(level), 8 * 4 * 120)
	assert_eq(ODTime.sub_to_beat(level, 240), 2)
	assert_eq(ODTime.beat_to_sub(level, 2.5), 300)
	assert_eq(ODTime.sub_to_beat(level, ODTime.beat_to_sub(level, 7.25)), 7.25)
	assert_eq(ODTime.sub_to_seconds(480), 2)


func test_maps_local_ticks_to_substeps_for_every_speed() -> void:
	var per: Array[int] = []
	for s: float in OD.ALL_SPEEDS:
		per.append(ODTime.subs_per_local_tick(s))
	assert_eq(per, [8, 4, 2, 1])
	for s: float in OD.ALL_SPEEDS:
		assert_eq(ODTime.local_tick_to_sub(s, 60), 60 * ODTime.subs_per_local_tick(s))
		assert_eq(ODTime.sub_to_local_tick(s, ODTime.local_tick_to_sub(s, 37)), 37)


func test_test_01_the_local_recording_allowance_is_identical_at_every_speed() -> void:
	var level := TestLevels.make_level({"bpm": 80, "bars": 5})
	# 5 bars at 80 bpm = 20 beats = 15 local seconds = 900 ticks, regardless of speed.
	assert_eq(ODTime.tape_ticks(level), 900)
	for s: float in OD.ALL_SPEEDS:
		var t := _mk_tape(s, STOP, ODTime.tape_ticks(level))
		assert_eq(t.ticks, 900)


func test_test_02_groundwork_a_2x_tapes_15_local_seconds_occupy_7_5_master_seconds() -> void:
	var level := TestLevels.make_level({"bpm": 80, "bars": 5, "horizonBars": 10})
	var T := ODTime.tape_ticks(level)
	var expect_seconds := {0.5: 30.0, 1.0: 15.0, 2.0: 7.5, 4.0: 3.75}
	for s: float in OD.ALL_SPEEDS:
		var subs := ODTime.traversal_subs(_mk_tape(s, STOP, T))
		assert_eq(float(subs) / OD.SUB_HZ, expect_seconds[s])
		assert_eq(ODTime.span_bars(level, s), 5 / s)
		# The horizon does not change a traversal's length.
		assert_eq(ODTime.traversal_subs(_mk_tape(s, REPEAT, T)), subs)
	# A 2x tape's tick k lands at master time k / 60 / 2 seconds: the landing keeps its master beat.
	assert_eq(ODTime.local_tick_to_sub(2, 450) / OD.SUB_HZ, 3.75)

# ── tape_phase_at ──

const T_PHASE := 100


func test_stop_forward_then_holds_the_last_tick_ended() -> void:
	var T := T_PHASE
	for s: float in OD.ALL_SPEEDS:
		var tape := _mk_tape(s, STOP, T)
		var m := ODTime.subs_per_local_tick(s)
		_phase_eq(ODTime.tape_phase_at(tape, 0), 0, 1, 0, false, "sub 0")
		_phase_eq(ODTime.tape_phase_at(tape, 50 * m), 50, 1, 0, false, "tick 50")
		assert_near(ODTime.tape_phase_at(tape, T * m - 1).tick, T - s / 4, 5e-13)
		_phase_eq(ODTime.tape_phase_at(tape, T * m), T, 0, 1, true, "end")
		_phase_eq(ODTime.tape_phase_at(tape, 10 * T * m), T, 0, 1, true, "long after")


func test_repeat_cuts_straight_back_to_tick_0_each_traversal() -> void:
	var T := T_PHASE
	for s: float in OD.ALL_SPEEDS:
		var tape := _mk_tape(s, REPEAT, T)
		var m := ODTime.subs_per_local_tick(s)
		_phase_eq(ODTime.tape_phase_at(tape, T * m), 0, 1, 1, false, "wrap")
		_phase_eq(ODTime.tape_phase_at(tape, (2 * T + 30) * m), 30, 1, 2, false, "third pass")
		assert_near(ODTime.tape_phase_at(tape, 2 * T * m - 1).tick, T - s / 4, 5e-13)


func test_reverse_ping_pongs_continuously() -> void:
	var T := T_PHASE
	var scratch := TapePhase.new()
	for s: float in OD.ALL_SPEEDS:
		var tape := _mk_tape(s, REVERSE, T)
		var m := ODTime.subs_per_local_tick(s)
		_phase_eq(ODTime.tape_phase_at(tape, T * m), T, -1, 1, false, "turn")
		_phase_eq(ODTime.tape_phase_at(tape, (T + 30) * m), 70, -1, 1, false, "backward")
		_phase_eq(ODTime.tape_phase_at(tape, 2 * T * m), 0, 1, 2, false, "back at 0")
		_phase_eq(ODTime.tape_phase_at(tape, (3 * T + 1) * m), T - 1, -1, 3, false, "fourth pass")
		# Continuity: consecutive substeps never move the playhead more than one sub's worth of ticks.
		var prev := ODTime.tape_phase_at(tape, 0).tick
		var worst := 0.0
		for sub in range(1, 5 * T * m):
			var p := ODTime.tape_phase_into(tape, sub, scratch).tick
			worst = maxf(worst, absf(p - prev))
			prev = p
		assert_true(worst <= s / 4 + 1e-12, "max step %s at %sx" % [worst, s])


func test_treats_negative_subs_as_sub_0_and_zero_length_tapes_as_ended() -> void:
	_phase_eq(ODTime.tape_phase_at(_mk_tape(1, REPEAT, 10), -5), 0, 1, 0, false, "negative")
	_phase_eq(ODTime.tape_phase_at(_mk_tape(1, REVERSE, 0), 50), 0, 0, 0, true, "zero length")

# ── event crossings ──


## Independent oracle for event crossings: walk every substep, read the playhead with tape_phase_at and
## record which integer ticks it visits (with the direction of arrival). Repeat wraps visit both the
## end (tick T) and the start (tick 0) of the next traversal at the cut instant.
## Each entry is [sub, index, dir, traversal].
func _oracle(tape: ODTape, horizon: int) -> Array:
	var T := tape.ticks
	var out: Array = []
	var prev: TapePhase = null
	for s in horizon:
		var p := ODTime.tape_phase_at(tape, s)
		if tape.end_mode == REPEAT and prev != null and p.traversal > prev.traversal:
			_visit(tape, out, s, T, 1, prev.traversal)
			_visit(tape, out, s, 0, 1, p.traversal)
		elif tape.end_mode == STOP and p.ended:
			if prev != null and not prev.ended:
				_visit(tape, out, s, T, 1, 0)
		elif p.tick == floorf(p.tick):
			var dir := (1 if p.tick - prev.tick >= 0 else -1) if prev != null else 1
			_visit(tape, out, s, int(p.tick), dir, prev.traversal if prev != null else 0)
		prev = p
	# Stable sort by (sub, traversal, index): entries are unique per key, so sort_custom's instability is moot.
	out.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[3] != b[3]:
			return a[3] < b[3]
		return a[1] < b[1])
	return out


func _visit(tape: ODTape, out: Array, sub: int, tick: int, dir: int, traversal: int) -> void:
	for index in tape.events.size():
		if tape.events[index].tick == tick:
			out.append([sub, index, dir, traversal])


func _simplify(c: Array[ODTime.EventCrossing]) -> Array:
	var out: Array = []
	for x: ODTime.EventCrossing in c:
		out.append([x.sub, x.index, x.dir, x.traversal])
	return out


const T_EV := 12


func _crossing_events() -> Array[TapeEvent]:
	# Events on tick 0, interior ticks, the last recorded tick (T-1), the end sample (T), and a duplicate tick.
	return [_ev(0), _ev(1, ActionKind.DODGE), _ev(5, ActionKind.INTERACT), _ev(5, ActionKind.RANGED), _ev(T_EV - 1, ActionKind.HEAVY), _ev(T_EV, ActionKind.ABILITY)]


func test_every_speed_and_end_mode_matches_the_substep_oracle_for_any_partition_of_time() -> void:
	for speed: float in OD.ALL_SPEEDS:
		for mode: int in ODTime.ALL_END_MODES:
			var label := "%sx %s" % [speed, OD.end_mode_name(mode)]
			var tape := _mk_tape(speed, mode, T_EV, _crossing_events())
			var horizon := ODTime.traversal_subs(tape) * 5 + 3
			var expected := _oracle(tape, horizon)
			# Sanity: the oracle sees every in-range event at least once (more on repeat / reverse).
			assert_true(expected.size() >= 6 if mode == STOP else expected.size() > 6, label + ": oracle coverage")

			# Whole range in one query.
			assert_eq(_simplify(ODTime.event_crossings(tape, 0, horizon)), expected, label + " whole range")

			# Every fixed step size, including 1-substep stepping as the kernel does.
			for step: int in [1, 2, 3, 4, 7, 8, 13, 48]:
				var acc: Array[ODTime.EventCrossing] = []
				var a := 0
				while a < horizon:
					ODTime.collect_event_crossings(tape, a, mini(horizon, a + step), acc)
					a += step
				assert_eq(_simplify(acc), expected, "%s step %d" % [label, step])

			# Irregular partition from a fixed LCG (deterministic).
			var seed := 12345
			var acc2: Array[ODTime.EventCrossing] = []
			var a2 := 0
			while a2 < horizon:
				seed = (seed * 1103515245 + 12345) & 0x7fffffff
				var b := mini(horizon, a2 + 1 + (seed % 17))
				ODTime.collect_event_crossings(tape, a2, b, acc2)
				a2 = b
			assert_eq(_simplify(acc2), expected, label + " irregular")


func test_fires_a_stop_tapes_events_exactly_once_including_tick_0_and_the_end_tick() -> void:
	for speed: float in OD.ALL_SPEEDS:
		var tape := _mk_tape(speed, STOP, T_EV, _crossing_events())
		var all := ODTime.event_crossings(tape, 0, ODTime.traversal_subs(tape) * 10)
		var idx: Array[int] = []
		var all_forward := true
		for c: ODTime.EventCrossing in all:
			idx.append(c.index)
			all_forward = all_forward and c.dir == 1 and c.traversal == 0
		assert_eq(idx, [0, 1, 2, 3, 4, 5])
		assert_true(all_forward)
		assert_eq(all[5].sub, ODTime.traversal_subs(tape))


func test_repeat_tick_0_events_fire_again_each_traversal_the_cut_fires_end_then_start() -> void:
	var T := T_EV
	var tape := _mk_tape(1, REPEAT, T, [_ev(0), _ev(T)])
	var m := ODTime.subs_per_local_tick(1)
	var got: Array = []
	for c: ODTime.EventCrossing in ODTime.event_crossings(tape, 0, 3 * T * m + 1):
		got.append([c.sub, c.index, c.traversal])
	assert_eq(got, [
		[0, 0, 0],
		[T * m, 1, 0],
		[T * m, 0, 1],
		[2 * T * m, 1, 1],
		[2 * T * m, 0, 2],
		[3 * T * m, 1, 2],
		[3 * T * m, 0, 3],
	])


func test_reverse_events_fire_again_backward_with_dir_minus_1_turn_ticks_fire_once_per_turn() -> void:
	var T := T_EV
	var tape := _mk_tape(2, REVERSE, T, [_ev(0), _ev(4), _ev(T)])
	var m := ODTime.subs_per_local_tick(2)
	var got: Array = []
	for c: ODTime.EventCrossing in ODTime.event_crossings(tape, 0, 4 * T * m + 1):
		got.append([c.sub / m, c.index, c.dir, c.traversal])
	assert_eq(got, [
		[0, 0, 1, 0],
		[4, 1, 1, 0],
		[T, 2, 1, 0], # arrives at the far end going forward: fires once
		[2 * T - 4, 1, -1, 1], # backward pass
		[2 * T, 0, -1, 1], # arrives back at tick 0 going backward: fires once
		[2 * T + 4, 1, 1, 2],
		[3 * T, 2, 1, 2],
		[4 * T - 4, 1, -1, 3],
		[4 * T, 0, -1, 3],
	])


func test_ignores_events_outside_the_tape_and_empty_or_inverted_intervals() -> void:
	var tape := _mk_tape(1, REPEAT, T_EV, [_ev(-1), _ev(T_EV + 1), _ev(3)])
	var all := ODTime.event_crossings(tape, 0, 1000)
	assert_true(all.size() > 0)
	for c: ODTime.EventCrossing in all:
		assert_eq(c.index, 2)
	assert_eq(ODTime.event_crossings(tape, 12, 12).size(), 0)
	assert_eq(ODTime.event_crossings(tape, 20, 10).size(), 0)


func test_a_live_tick_i_event_fires_in_the_first_substep_of_tick_i() -> void:
	for speed: float in OD.ALL_SPEEDS:
		var tape := _mk_tape(speed, STOP, T_EV, [_ev(7)])
		var m := ODTime.subs_per_local_tick(speed)
		assert_eq(ODTime.event_crossings(tape, 7 * m, 7 * m + 1).size(), 1)
		assert_eq(ODTime.event_crossings(tape, 6 * m, 7 * m).size(), 0)


func test_handles_unsorted_events_and_keeps_a_deterministic_order() -> void:
	var tape := _mk_tape(1, STOP, T_EV, [_ev(9), _ev(2), _ev(2)])
	var idx: Array[int] = []
	for c: ODTime.EventCrossing in ODTime.event_crossings(tape, 0, 100):
		idx.append(c.index)
	assert_eq(idx, [1, 2, 0])


func test_zero_length_tapes_fire_tick_0_events_once() -> void:
	for mode: int in ODTime.ALL_END_MODES:
		var tape := _mk_tape(1, mode, 0, [_ev(0)])
		assert_eq(ODTime.event_crossings(tape, 0, 1000).size(), 1, OD.end_mode_name(mode))

# ── boundaries ──


func test_stop_ends_once_repeat_wraps_reverse_turns_with_alternating_direction() -> void:
	var T := 10
	for speed: float in OD.ALL_SPEEDS:
		var m := ODTime.subs_per_local_tick(speed)
		var H := 4 * T * m + 1
		var stop := ODTime.collect_boundaries(_mk_tape(speed, STOP, T), 0, H)
		assert_eq(stop.size(), 1)
		if stop.size() == 1:
			assert_eq([stop[0].kind, stop[0].sub, stop[0].traversal, stop[0].dir], [ODTime.BOUNDARY_END, T * m, 1, 0])
		var wraps: Array = []
		for b: ODTime.TapeBoundary in ODTime.collect_boundaries(_mk_tape(speed, REPEAT, T), 0, H):
			wraps.append([b.kind, b.sub, b.traversal])
		assert_eq(wraps, [
			[ODTime.BOUNDARY_WRAP, T * m, 1],
			[ODTime.BOUNDARY_WRAP, 2 * T * m, 2],
			[ODTime.BOUNDARY_WRAP, 3 * T * m, 3],
			[ODTime.BOUNDARY_WRAP, 4 * T * m, 4],
		])
		var dirs: Array[int] = []
		for b: ODTime.TapeBoundary in ODTime.collect_boundaries(_mk_tape(speed, REVERSE, T), 0, H):
			dirs.append(b.dir)
		assert_eq(dirs, [-1, 1, -1, 1])
		# Partitioned queries find each boundary once.
		var acc: Array[ODTime.TapeBoundary] = []
		var a := 0
		while a < H:
			ODTime.collect_boundaries(_mk_tape(speed, REPEAT, T), a, mini(H, a + 3), acc)
			a += 3
		assert_eq(acc.size(), 4)
		assert_eq(ODTime.collect_boundaries(_mk_tape(speed, REPEAT, T), 0, T * m).size(), 0)
