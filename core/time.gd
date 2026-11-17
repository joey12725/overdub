class_name ODTime
extends RefCounted
## The one clock (TIME-01..07) and fixed-choreography playback geometry (PLAY-05, PLAY-06).
## Port of prototype/src/core/time.ts. Never instantiated.
##
## Coordinates:
##   sub   — master substep index (1/SUB_HZ master s). The world steps one sub at a time.
##   tick  — local tick on a tape (1/LOCAL_HZ local s). Pose sample i sits at tick i.
##   u     — "unwrapped" local time: local ticks elapsed since beat zero, ignoring end behaviour.
##           u = sub · speed / (SUB_HZ / LOCAL_HZ). It only ever increases.
##
## master = local / speed (TIME-03): a tape at speed s covers `subs_per_local_tick(s)` = 4 / s substeps
## per local tick, so its traversal of T ticks spans T · 4 / s substeps. Nothing is ever stretched.
## Because every speed is a power of two dividing 4·2, each integer tick lands on an integer sub, so
## all crossing arithmetic below is exact.
##
## Number types: the prototype's `number` results that are always integral (tape_ticks, horizon_subs,
## traversal_subs, crossing / boundary subs) are `int`; the rest stay `float`. Sub arguments are
## `float` so callers may pass ints.

## Substeps per local tick at 1× (4).
const SUBS_PER_TICK_1X: float = OD.SUB_HZ * 1.0 / OD.LOCAL_HZ

## All end modes, for exhaustive iteration in tools and tests (= OD.ALL_END_MODES).
const ALL_END_MODES: Array[int] = OD.ALL_END_MODES

## TapeBoundary.kind values (time.ts BoundaryKind).
const BOUNDARY_END: StringName = &"end"
const BOUNDARY_WRAP: StringName = &"wrap"
const BOUNDARY_TURN: StringName = &"turn"

# ───────────────────────────── level-level conversions ─────────────────────────────


## Local ticks in one beat at the level tempo. LevelDef requires 3600 / bpm to be an integer.
static func ticks_per_beat(level: LevelDef) -> float:
	return (OD.LOCAL_HZ * 60.0) / level.bpm


## Master substeps in one master beat.
static func subs_per_beat(level: LevelDef) -> float:
	return (OD.SUB_HZ * 60.0) / level.bpm


## Local ticks in one recording: level.bars of the level tempo, identical for every speed (TIME-02, TIME-04).
static func tape_ticks(level: LevelDef) -> int:
	# Math.round on a non-negative value: roundi (half away from zero) agrees for x >= 0.
	return roundi(level.bars * OD.BEATS_PER_BAR * ticks_per_beat(level))


## Total master substeps in the encounter horizon (level-authored, OPEN-02).
static func horizon_subs(level: LevelDef) -> int:
	# Math.round on a non-negative value: roundi agrees for x >= 0.
	return roundi(level.horizon_bars * OD.BEATS_PER_BAR * subs_per_beat(level))


## Master beat (float) at a substep.
static func sub_to_beat(level: LevelDef, sub: float) -> float:
	return sub / subs_per_beat(level)


## Substep (float) at a master beat.
static func beat_to_sub(level: LevelDef, beat: float) -> float:
	return beat * subs_per_beat(level)


## Master seconds at a substep.
static func sub_to_seconds(sub: float) -> float:
	return sub / float(OD.SUB_HZ)


## Re-exported so callers have the whole clock in one module. 8, 4, 2, 1 for 0.5×, 1×, 2×, 4×.
static func subs_per_local_tick(speed: float) -> int:
	return OD.subs_per_local_tick(speed)


## Master substep at which a tape at `speed` reaches unwrapped local tick `tick`.
static func local_tick_to_sub(speed: float, tick: float) -> float:
	return tick * OD.subs_per_local_tick(speed)


## Unwrapped local tick a tape at `speed` has reached at master substep `sub`.
static func sub_to_local_tick(speed: float, sub: float) -> float:
	return (sub * speed) / SUBS_PER_TICK_1X


## Master substeps one full traversal of a tape spans (TIME-03: bars / speed master bars).
static func traversal_subs(tape: ODTape) -> int:
	return tape.ticks * OD.subs_per_local_tick(tape.speed)


## Master bars one traversal spans (DeckView.spanBars).
static func span_bars(level: LevelDef, speed: float) -> float:
	return level.bars / speed

# ───────────────────────────── playhead ─────────────────────────────


## Where a tape's playhead is at master substep `sub` (PLAY-05).
##
##  stop    — forward until tick T, then holds T with dir 0, ended, traversal 1.
##  repeat  — traversal k = floor(u / T), tick = u − kT. At u = kT the playhead has already cut back
##            to tick 0 (it is never reported "at T" on a repeat).
##  reverse — even traversals run forward, odd ones backward (tick = T − (u − kT)). The playhead is
##            continuous; at a turn instant it reports the new traversal and direction.
##
## Negative subs are treated as sub 0. A zero-length tape is permanently at tick 0, ended.
static func tape_phase_at(tape: ODTape, sub: float) -> TapePhase:
	return tape_phase_into(tape, sub, TapePhase.new())


## Allocation-free tape_phase_at. Returns `out`.
static func tape_phase_into(tape: ODTape, sub: float, out: TapePhase) -> TapePhase:
	var T := tape.ticks
	var u := (sub * tape.speed) / SUBS_PER_TICK_1X if sub > 0.0 else 0.0
	if T <= 0:
		out.tick = 0.0
		out.dir = 0
		out.traversal = 0
		out.ended = true
		return out
	var mode := tape.end_mode
	if mode == OD.EndMode.STOP:
		if u < T:
			out.tick = u
			out.dir = 1
			out.traversal = 0
			out.ended = false
		else:
			out.tick = T
			out.dir = 0
			out.traversal = 1
			out.ended = true
		return out
	var k := floori(u / T)
	var f := u - k * T
	out.traversal = k
	out.ended = false
	if mode == OD.EndMode.REPEAT or (k & 1) == 0:
		out.tick = f
		out.dir = 1
	else:
		out.tick = T - f
		out.dir = -1
	return out

# ───────────────────────────── event crossings ─────────────────────────────


## One firing of a recorded event: the playhead reached the event's tick during a query interval.
class EventCrossing:
	extends RefCounted
	var event: TapeEvent
	## Index into tape.events.
	var index: int = 0
	## Exact master substep of the crossing (an integer: event ticks are integers).
	var sub: int = 0
	## Direction of the pass that crossed it: +1 forward, −1 backward (reverse mode).
	var dir: int = 1
	## Traversal number of that pass (0 = first forward pass).
	var traversal: int = 0

	static func make(p_event: TapeEvent, p_index: int, p_sub: int, p_dir: int, p_traversal: int) -> EventCrossing:
		var c := EventCrossing.new()
		c.event = p_event
		c.index = p_index
		c.sub = p_sub
		c.dir = p_dir
		c.traversal = p_traversal
		return c


## Collects the events whose ticks the playhead crosses in master substeps [sub_a, sub_b), ordered by
## crossing sub, then traversal, then event index. Appends to `out` and returns it.
##
## Half-open on purpose: consecutive queries [a, b), [b, c) partition time, so an event is never
## fired twice or skipped at a query boundary; and an event recorded on live tick i (whose substeps
## are [i·m, (i+1)·m)) fires in the first substep of that tick's batch, after the controller has
## produced it. The first query of a run starts at sub 0 and so includes events on tick 0.
##
## Visits (each fires the event once):
##  stop    — the single forward pass, u ∈ [0, T]. An event on tick T fires as the tape ends.
##  repeat  — every pass k covers u ∈ [kT, (k+1)T]. At a wrap instant the event on tick T (end of
##            pass k) and the event on tick 0 (start of pass k+1) both fire; they are different
##            events, so nothing doubles.
##  reverse — the playhead touches a turn tick only once per turn, so the turn instant belongs to the
##            pass that ARRIVES there: pass 0 owns u ∈ [0, T], pass k ≥ 1 owns u ∈ (kT, (k+1)T].
##            An event on tick T fires forward on arrival and does not fire again leaving the turn;
##            an event on tick 0 fires backward on arrival at the next turn (PLAY-06: fresh again).
##
## Events with ticks outside [0, T] never fire. Events need not be sorted.
static func collect_event_crossings(tape: ODTape, sub_a: float, sub_b: float, out: Array[EventCrossing] = []) -> Array[EventCrossing]:
	var events := tape.events
	if not (sub_b > sub_a) or events.is_empty():
		return out
	var T := tape.ticks
	var m := OD.subs_per_local_tick(tape.speed)
	var start := out.size()
	var n := events.size()

	if T <= 0 or tape.end_mode == OD.EndMode.STOP:
		# Single pass. Zero-length tapes fire tick-0 events once at sub 0.
		var t_max := maxi(T, 0)
		for i in n:
			var e := events[i].tick
			if not (e >= 0 and e <= t_max):
				continue
			var s := e * m
			if s >= sub_a and s < sub_b:
				out.append(EventCrossing.make(events[i], i, s, 1, 0))
	else:
		var trav_subs := T * m
		# Passes whose owned spans can intersect [sub_a, sub_b). A pass k spans subs [kT·m, (k+1)T·m].
		var k_first := maxi(0, floori(sub_a / trav_subs) - 1)
		var k_last := floori(sub_b / trav_subs)
		var reverse := tape.end_mode == OD.EndMode.REVERSE
		for k in range(k_first, k_last + 1):
			var base := k * T
			var backward := reverse and (k & 1) == 1
			for i in n:
				var e := events[i].tick
				if not (e >= 0 and e <= T):
					continue
				var u_off := T - e if backward else e
				# Reverse: a pass k ≥ 1 does not own its departure instant (the previous pass arrived there).
				if reverse and k > 0 and u_off == 0:
					continue
				var s := (base + u_off) * m
				if s >= sub_a and s < sub_b:
					out.append(EventCrossing.make(events[i], i, s, -1 if backward else 1, k))

	if out.size() - start > 1:
		_sort_crossings(out, start)
	return out


## Convenience wrapper returning a fresh array.
static func event_crossings(tape: ODTape, sub_a: float, sub_b: float) -> Array[EventCrossing]:
	var out: Array[EventCrossing] = []
	return collect_event_crossings(tape, sub_a, sub_b, out)


static func _sort_crossings(arr: Array[EventCrossing], from: int) -> void:
	# Insertion sort over the appended slice: tiny, stable and allocation-free (Godot's sort is not
	# stable, the prototype's ordering relies on this one).
	for i in range(from + 1, arr.size()):
		var x := arr[i]
		var j := i - 1
		while j >= from and _crossing_after(arr[j], x):
			arr[j + 1] = arr[j]
			j -= 1
		arr[j + 1] = x


static func _crossing_after(a: EventCrossing, b: EventCrossing) -> bool:
	if a.sub != b.sub:
		return a.sub > b.sub
	if a.traversal != b.traversal:
		return a.traversal > b.traversal
	return a.index > b.index

# ───────────────────────────── end-of-tape boundaries ─────────────────────────────


## An end-of-tape boundary (feeds the tapeEnd / tapeWrap / tapeTurn SimEvents).
class TapeBoundary:
	extends RefCounted
	## ODTime.BOUNDARY_END / BOUNDARY_WRAP / BOUNDARY_TURN.
	var kind: StringName = &"end"
	## Master substep of the boundary.
	var sub: int = 0
	## Traversal that begins at this boundary (1 for the first boundary).
	var traversal: int = 0
	## For 'turn': the direction of the pass that begins (−1 after the far end, +1 after tick 0).
	## 1 for 'wrap', 0 for 'end'.
	var dir: int = 0

	static func make(p_kind: StringName, p_sub: int, p_traversal: int, p_dir: int) -> TapeBoundary:
		var b := TapeBoundary.new()
		b.kind = p_kind
		b.sub = p_sub
		b.traversal = p_traversal
		b.dir = p_dir
		return b


## Boundaries the playhead reaches in master substeps [sub_a, sub_b), in order. Appends to `out`.
static func collect_boundaries(tape: ODTape, sub_a: float, sub_b: float, out: Array[TapeBoundary] = []) -> Array[TapeBoundary]:
	if not (sub_b > sub_a) or tape.ticks <= 0:
		return out
	var trav_subs := traversal_subs(tape)
	if tape.end_mode == OD.EndMode.STOP:
		if trav_subs >= sub_a and trav_subs < sub_b:
			out.append(TapeBoundary.make(BOUNDARY_END, trav_subs, 1, 0))
		return out
	var kind := BOUNDARY_WRAP if tape.end_mode == OD.EndMode.REPEAT else BOUNDARY_TURN
	var k := maxi(1, ceili(sub_a / trav_subs))
	while k * trav_subs < sub_b:
		var dir := 1 if kind == BOUNDARY_WRAP else (-1 if (k & 1) == 1 else 1)
		out.append(TapeBoundary.make(kind, k * trav_subs, k, dir))
		k += 1
	return out
