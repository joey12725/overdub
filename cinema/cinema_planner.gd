class_name CinemaPlanner
extends RefCounted
## The cinematic director's editor: a pure function from the resolved encounter (Resolution +
## LevelDef, plus optional knowledge of earlier runs) to an edit decision list on the master beat
## timeline (CINE-01..05, MUSIC-13, PILLAR-06).
##
##     var plan := CinemaPlanner.plan(resolution, level, ctx)     # ctx may be null
##
## It edits like the payoff of a heist film: open wide on beat zero with every self, show each link
## of the causal chain cause-then-effect, hold wide enough to see why, build to the objective as
## the climax, end on the survivors. Grammar (docs/CINEMATIC.md):
##   - cuts only on whole beats, preferably bar lines; every shot is at least two beats;
##   - never cut away from an action between its wind-up and impact (plus a quarter beat of
##     follow-through) when the next shot would not show it;
##   - exactly one emphasis per shot (letterbox, time ripple or split), possibly none;
##   - shot count proportional to length (cap = ceil(beats / 3) + 1);
##   - music-linked flourishes are cues, never cuts.
## The timeline is never stretched or re-timed: the plan only decides where to look (CINE-04/05).

const G := preload("res://cinema/cinema_grammar.gd")

var sc: CinemaScene
var an: CinemaAnalyzer
var horizon: int = 0
var cap: int = 2
var shots: Array[CinemaShot] = []
var _new_shot_budget: int = 0
var _orbit_sign: float = 1.0


static func plan(res: Resolution, level: LevelDef, ctx: CinemaTypes.Context = null) -> CinemaPlan:
	var p := CinemaPlanner.new()
	return p._run(res, level, ctx)


func _run(res: Resolution, level: LevelDef, ctx: CinemaTypes.Context) -> CinemaPlan:
	sc = CinemaScene.create(res, level)
	an = CinemaAnalyzer.analyze(sc, ctx)
	horizon = sc.horizon_beats
	cap = maxi(2, int(ceil(float(horizon) / G.BEATS_PER_SHOT)) + 1)
	var out := CinemaPlan.new()
	out.horizon_beats = horizon
	out.subs_per_beat = sc.subs_per_beat
	out.moments = an.moments
	out.actions = an.actions
	out.shot_cap = cap
	shots.clear()
	if an.moments.is_empty():
		shots.append(_graceful_wide())
	else:
		shots.append(_opening())
		_new_shot_budget = cap - 2
		for m: CinemaMoment in an.moments:
			_place_moment(m)
		_add_finale()
		_fill_gaps()
		_legalise_cuts()
		_snap_to_bars()
		_repair()
	_finish_shots()
	out.shots = shots
	for m: CinemaMoment in an.moments:
		m.shot = -1
		for i: int in shots.size():
			for e: int in m.source_events:
				if shots[i].source_events.has(e):
					m.shot = i
					break
			if m.shot >= 0:
				break
	out.cues = _cues()
	return out


# ───────────────────────────── structural shots ─────────────────────────────

func _wide(start: int, end: int, kind: StringName, beat: float) -> CinemaShot:
	var s := CinemaShot.new()
	s.start_beat = start
	s.end_beat = end
	s.core_start = start
	s.core_end = mini(end, start + G.MIN_SHOT_BEATS)
	s.kind = kind
	s.framing = G.FRAMING_WIDE
	s.focus_point = sc.crowd_pos(beat) if not sc.frames.is_empty() else sc.level_centre()
	s.focus_point = s.focus_point.lerp(sc.level_centre(), 0.5)
	s.focus_to = s.focus_point
	s.span = sc.level_span()
	s.score = G.score_of(kind)
	s.key_beat = beat
	s.cause_beat = beat
	s.shows.append(kind)
	for t: int in sc.tapes:
		s.add_tape(t)
		s.add_callout(CinemaTypes.Callout.of_tape(t, G.ROLE_SUBJECT))
	return s


func _graceful_wide() -> CinemaShot:
	var s := _wide(0, horizon, G.KIND_OPENING, 0.0)
	s.move = G.MOVE_ORBIT if horizon >= 8 else G.MOVE_HOLD
	s.reason = "Nothing to single out: hold the whole performance wide, every self in view"
	return s


func _opening() -> CinemaShot:
	var s := _wide(0, mini(horizon, G.OPENING_MIN_BEATS), G.KIND_OPENING, 0.0)
	s.move = G.MOVE_HOLD
	var who := ""
	for t: int in sc.tapes:
		who += OD.tape_letter(t)
	s.reason = "Beat zero, wide: every self at the start (%s)" % who
	return s


func _add_finale() -> void:
	var t := 0
	for s: CinemaShot in shots:
		t = maxi(t, s.end_beat)
	var survivors: Array[int] = []
	if sc.res != null:
		survivors = sc.res.outcome.survivors
	if horizon - t < G.MIN_SHOT_BEATS:
		# The last story beat runs to the end: it doubles as the finale.
		var last := shots[shots.size() - 1]
		for k: int in survivors:
			last.add_callout(CinemaTypes.Callout.of_tape(k, G.ROLE_SURVIVOR))
		return
	var start := maxi(t, horizon - G.OPENING_PREFERRED_BEATS)
	var f := CinemaShot.new()
	f.kind = G.KIND_FINALE
	f.start_beat = start
	f.end_beat = horizon
	f.core_start = start
	f.core_end = horizon
	f.score = G.score_of(G.KIND_FINALE)
	var b := float(horizon) - 0.5
	f.key_beat = b
	f.cause_beat = float(start)
	var who := ""
	for k: int in survivors:
		f.add_tape(k)
		f.add_callout(CinemaTypes.Callout.of_tape(k, G.ROLE_SURVIVOR))
		who += OD.tape_letter(k)
	var pick: Array[int] = survivors if not survivors.is_empty() else sc.tapes
	f.focus_point = sc.crowd_pos(b, pick)
	var r := sc.crowd_radius(b, f.focus_point, pick)
	f.span = clampf(2.0 * r + G.SPAN_TWO_SHOT_MARGIN, G.SPAN_TWO_SHOT_MIN, sc.level_span())
	if pick.size() == 1:
		f.framing = G.FRAMING_CLOSE
		f.span = maxf(G.SPAN_CLOSE, f.span)
		f.focus_tape = pick[0]
	elif f.span >= sc.level_span() * 0.8:
		f.framing = G.FRAMING_WIDE
	else:
		f.framing = G.FRAMING_TWO_SHOT
	f.focus_to = f.focus_point
	f.move = G.MOVE_PULL_OUT
	f.shows.append(G.KIND_FINALE)
	f.reason = "The tape runs out: %s survive%s" % [who if not who.is_empty() else "nobody", "s" if who.length() == 1 else ""]
	_insert(f)


# ───────────────────────────── moments -> shots ─────────────────────────────

## [shot, desired start, desired end] for each piece of a moment (one, or cause + effect).
func _segments(m: CinemaMoment) -> Array:
	var out: Array = []
	var d := m.cause_point.distance_to(m.effect_point)
	var dt := m.key_beat - m.cause_beat
	var post := 2.0 if m.kind == G.KIND_CLIMAX else G.POST_BEATS
	if m.simultaneous_far:
		var s := _base(m, m.cause_beat, m.key_beat)
		s.emphasis = G.EMPHASIS_SPLIT
		s.focus_point = (m.cause_point + m.effect_point) * 0.5
		s.focus_to = s.focus_point
		s.span = clampf(d + G.SPAN_TWO_SHOT_MARGIN, G.SPAN_TWO_SHOT_MIN, sc.level_span())
		s.framing = G.FRAMING_WIDE if s.span >= sc.level_span() * 0.8 else G.FRAMING_TWO_SHOT
		s.panes.append(_pane(m.cause_tape, m.cause_point, m.reason))
		s.panes.append(_pane(m.effect_tape, m.effect_point, m.reason))
		s.move = G.MOVE_HOLD
		out.append([s, floori(m.cause_beat - G.PRE_BEATS), ceili(m.key_beat + post)])
		return out
	if dt > G.SEQUENTIAL_SPLIT_BEATS:
		# Cause, then effect, as two shots (the gap between is someone else's story or coverage).
		var c := _base(m, m.cause_beat, m.cause_beat + 0.5)
		_frame_single(c, m.cause_point, m.cause_tape, m.cause_point)
		c.move = G.MOVE_PUSH_IN
		c.reason = "Cause - " + m.reason
		c.callouts = _callouts_for(m, [G.ROLE_CAUSE, G.ROLE_TARGET, G.ROLE_SUBJECT])
		var e := _base(m, m.key_beat - 0.5, m.key_beat)
		_frame_single(e, m.effect_point, m.effect_tape, m.effect_point)
		e.move = _move_for(m.kind, e.framing)
		e.reason = "Effect - " + m.reason
		e.emphasis = G.EMPHASIS_FOR.get(m.kind, G.EMPHASIS_NONE)
		c.emphasis = G.EMPHASIS_NONE
		# Each half explains the events on its side of the midpoint.
		var mid := (m.cause_beat + m.key_beat) * 0.5
		c.source_events.clear()
		e.source_events.clear()
		for k: int in m.source_events:
			if sc.beat_of(an.ev[k]) < mid:
				c.source_events.append(k)
			else:
				e.source_events.append(k)
		out.append([c, floori(m.cause_beat - G.PRE_BEATS), ceili(m.cause_beat + 0.5 + G.POST_BEATS)])
		out.append([e, floori(m.key_beat - G.PRE_BEATS), ceili(m.key_beat + post)])
		return out
	var s2 := _base(m, m.cause_beat, m.key_beat)
	if d < G.CLOSE_MAX_DIST:
		_frame_single(s2, m.effect_point, m.effect_tape if m.effect_tape >= 0 else m.cause_tape, (m.cause_point + m.effect_point) * 0.5)
	elif d <= G.TWO_SHOT_MAX_DIST:
		s2.framing = G.FRAMING_TWO_SHOT
		s2.focus_point = (m.cause_point + m.effect_point) * 0.5
		s2.focus_to = s2.focus_point
		s2.span = maxf(G.SPAN_TWO_SHOT_MIN, d + G.SPAN_TWO_SHOT_MARGIN)
	elif sc.same_room(m.cause_point, m.effect_point):
		s2.framing = G.FRAMING_ROOM
		s2.focus_point = sc.room_rect_of(m.effect_point).get_center()
		s2.focus_to = s2.focus_point
		s2.span = sc.room_span_of(m.effect_point)
	else:
		s2.framing = G.FRAMING_ROOM
		s2.focus_point = m.cause_point
		s2.focus_to = m.effect_point
		s2.span = maxf(G.SPAN_TWO_SHOT_MIN + 1.0, minf(d * 0.6, sc.room_span_of(m.effect_point)))
		s2.move = G.MOVE_PAN
	if s2.move != G.MOVE_PAN:
		s2.move = _move_for(m.kind, s2.framing)
	out.append([s2, floori(m.cause_beat - G.PRE_BEATS), ceili(m.key_beat + post)])
	return out


func _base(m: CinemaMoment, cause_beat: float, key_beat: float) -> CinemaShot:
	var s := CinemaShot.new()
	s.kind = m.kind
	s.score = m.score
	s.cause_beat = cause_beat
	s.key_beat = key_beat
	s.core_start = clampi(floori(cause_beat), 0, horizon)
	s.core_end = clampi(ceili(key_beat + G.FOLLOW_THROUGH_BEATS), 0, horizon)
	if s.core_end <= s.core_start:
		s.core_end = mini(horizon, s.core_start + 1)
	s.reason = m.reason
	s.emphasis = G.EMPHASIS_FOR.get(m.kind, G.EMPHASIS_NONE)
	for t: int in m.tapes:
		s.add_tape(t)
	for i: String in m.ids:
		s.add_id(i)
	for c: CinemaTypes.Callout in m.callouts:
		s.add_callout(c.copy())
	s.source_events = m.source_events.duplicate()
	s.shows.append(m.kind)
	for k: StringName in m.absorbed:
		if not s.shows.has(k):
			s.shows.append(k)
	s.focus_id = m.ids[0] if not m.ids.is_empty() else ""
	return s


func _frame_single(s: CinemaShot, p: Vector2, tape: int, centre: Vector2) -> void:
	s.framing = G.FRAMING_CLOSE
	s.focus_point = centre
	s.focus_to = centre
	s.span = G.SPAN_CLOSE
	s.focus_tape = tape
	if not p.is_equal_approx(centre):
		s.span = maxf(G.SPAN_CLOSE, p.distance_to(centre) * 2.0 + 3.0)


func _move_for(kind: StringName, framing: StringName) -> StringName:
	if kind == G.KIND_CLIMAX:
		return G.MOVE_PUSH_IN
	if kind == G.KIND_BOSS_PHASE or kind == G.KIND_MULTI_KILL:
		return G.MOVE_ORBIT
	if kind == G.KIND_RESCUE or kind == G.KIND_BOSS_FOOLED:
		return G.MOVE_PULL_OUT
	if kind == G.KIND_KNOCKBACK or kind == G.KIND_DESYNC or kind == G.KIND_PLATE_HOLD or kind == G.KIND_OPENED_FOR:
		return G.MOVE_HOLD
	return G.MOVE_PUSH_IN if framing == G.FRAMING_CLOSE else G.MOVE_HOLD


func _pane(tape: int, p: Vector2, reason: String) -> CinemaTypes.Pane:
	var pane := CinemaTypes.Pane.new()
	pane.tape = tape
	pane.color = OD.tape_color(tape) if tape >= 0 else Color(1, 1, 1)
	pane.focus = p
	pane.span = clampf(sc.room_span_of(p), G.SPAN_ROOM_MIN, 12.0)
	pane.reason = reason
	return pane


func _callouts_for(m: CinemaMoment, roles: Array) -> Array[CinemaTypes.Callout]:
	var out: Array[CinemaTypes.Callout] = []
	for c: CinemaTypes.Callout in m.callouts:
		if roles.has(c.role):
			out.append(c.copy())
	if out.is_empty():
		for c: CinemaTypes.Callout in m.callouts:
			out.append(c.copy())
	return out


func _place_moment(m: CinemaMoment) -> void:
	for seg: Array in _segments(m):
		var s: CinemaShot = seg[0]
		var ds: int = clampi(seg[1], 0, horizon)
		var de: int = clampi(seg[2], 0, horizon)
		if not _try_place(s, ds, de):
			_try_merge(s)


func _overlapping(a: int, b: int) -> Array[CinemaShot]:
	var out: Array[CinemaShot] = []
	for s: CinemaShot in shots:
		if s.start_beat < b and a < s.end_beat:
			out.append(s)
	return out


## Place `s` in free time around its core, as close to [ds, de) as the neighbours allow.
func _try_place(s: CinemaShot, ds: int, de: int) -> bool:
	if _new_shot_budget <= 0:
		return false
	_yield_opening(s)
	var cs := s.core_start
	var ce := maxi(s.core_end, cs + 1)
	if not _overlapping(cs, ce).is_empty():
		return false
	var a := 0
	var b := horizon
	for o: CinemaShot in shots:
		if o.end_beat <= cs:
			a = maxi(a, o.end_beat)
		if o.start_beat >= ce:
			b = mini(b, o.start_beat)
	var st := maxi(mini(ds, cs), a)
	var en := mini(maxi(de, ce), b)
	if en - st < G.MIN_SHOT_BEATS:
		en = mini(b, st + G.MIN_SHOT_BEATS)
	if en - st < G.MIN_SHOT_BEATS:
		st = maxi(a, en - G.MIN_SHOT_BEATS)
	if en - st < G.MIN_SHOT_BEATS:
		return false
	# Prefer bar lines when they are within reach.
	var bar_s := st - st % OD.BEATS_PER_BAR
	if st % OD.BEATS_PER_BAR != 0 and st - bar_s <= G.BAR_SNAP_BEATS and bar_s >= a:
		st = bar_s
	var bar_e := en + (OD.BEATS_PER_BAR - en % OD.BEATS_PER_BAR) % OD.BEATS_PER_BAR
	if en % OD.BEATS_PER_BAR != 0 and bar_e - en <= G.BAR_SNAP_BEATS and bar_e <= b:
		en = bar_e
	# Leave no unusable one-beat slivers next to the neighbours.
	if st - a == 1:
		st = a
	if b - en == 1:
		en = b
	s.start_beat = st
	s.end_beat = en
	_insert(s)
	_new_shot_budget -= 1
	return true


## The opening is wide: a cause that starts inside it is already on screen, so a story beat whose
## key beat comes after the opening may start where the opening ends.
func _yield_opening(s: CinemaShot) -> void:
	var o := shots[0]
	if o.kind != G.KIND_OPENING or o.framing != G.FRAMING_WIDE:
		return
	if s.core_start < o.end_beat and s.key_beat >= float(o.end_beat) and s.core_end > o.end_beat:
		s.core_start = o.end_beat
		s.cause_beat = maxf(s.cause_beat, float(o.end_beat))


## Fold `s` into a shot that already covers its moment's time, widening or splitting that shot when
## needed. Hosts are tried by overlap with the newcomer's core (ties: earlier first); the first that
## can be extended to put the newcomer's key beat on screen takes it.
func _try_merge(s: CinemaShot) -> bool:
	var cands := _overlapping(s.core_start, maxi(s.core_end, s.core_start + 1))
	var near := _overlapping(floori(s.key_beat), floori(s.key_beat) + 1)
	for o: CinemaShot in near:
		if not cands.has(o):
			cands.append(o)
	var overlap := func(o: CinemaShot) -> int: return mini(o.end_beat, s.core_end) - maxi(o.start_beat, s.core_start)
	cands.sort_custom(func(a: CinemaShot, b: CinemaShot) -> bool:
		var oa: int = overlap.call(a)
		var ob: int = overlap.call(b)
		if oa != ob:
			return oa > ob
		return a.start_beat < b.start_beat)
	var pts: Array[Vector2] = [s.focus_point, s.focus_to]
	for pane: CinemaTypes.Pane in s.panes:
		pts.append(pane.focus)
	for host: CinemaShot in cands:
		if _merge_into(host, s, pts):
			return true
	return false


func _merge_into(host: CinemaShot, s: CinemaShot, pts: Array[Vector2]) -> bool:
	# 1. Time: extend the host over the newcomer's core where the neighbours allow; its key beat
	#    must end up on screen.
	var free_lo := 0
	var free_hi := horizon
	for o: CinemaShot in shots:
		if o == host:
			continue
		if o.end_beat <= host.start_beat:
			free_lo = maxi(free_lo, o.end_beat)
		if o.start_beat >= host.end_beat:
			free_hi = mini(free_hi, o.start_beat)
	var ns := clampi(mini(host.start_beat, s.core_start), free_lo, host.start_beat)
	var ne := clampi(maxi(host.end_beat, s.core_end), host.end_beat, free_hi)
	if not (s.key_beat >= float(ns) and s.key_beat < float(ne)):
		return false
	if ns - free_lo == 1:
		ns = free_lo
	if free_hi - ne == 1:
		ne = free_hi
	# 2. Space: the host must show the newcomer's subjects (or be loosened / split to).
	var framed := true
	for p: Vector2 in pts:
		if not host.frames_point(p):
			framed = false
	if not framed:
		if host.kind == G.KIND_OPENING or host.kind == G.KIND_FINALE:
			return false
		var far := not sc.same_room(host.focus_point, s.focus_point) and host.focus_point.distance_to(s.focus_point) > G.TWO_SHOT_MAX_DIST * 0.5
		if far and s.score >= 30.0 and host.score >= 30.0 and host.emphasis != G.EMPHASIS_LETTERBOX:
			# Simultaneous story beats in different rooms: the simultaneity is the point.
			var host_tape := host.focus_tape if host.focus_tape >= 0 else (host.tapes[0] if not host.tapes.is_empty() else -1)
			var pt := s.focus_tape if s.focus_tape >= 0 else (s.tapes[0] if not s.tapes.is_empty() else -1)
			var count := host.panes.size() if not host.panes.is_empty() else 1
			if count >= G.MAX_PANES:
				return false
			for pane: CinemaTypes.Pane in host.panes:
				if pane.tape == pt:
					return false
			if host.panes.is_empty() and host_tape == pt:
				return false
			if host.panes.is_empty():
				host.panes.append(_pane(host_tape, host.focus_point, host.reason))
			host.panes.append(_pane(pt, s.focus_point, s.reason))
			host.emphasis = G.EMPHASIS_SPLIT
		_widen_to_cover(host, pts)
	host.start_beat = ns
	host.end_beat = ne
	host.core_start = mini(host.core_start, maxi(ns, s.core_start))
	host.core_end = maxi(host.core_end, mini(ne, s.core_end))
	_absorb_into(host, s)
	return true


func _absorb_into(host: CinemaShot, s: CinemaShot) -> void:
	host.reason += "; also " + s.reason
	for t: int in s.tapes:
		host.add_tape(t)
	for i: String in s.ids:
		host.add_id(i)
	for c: CinemaTypes.Callout in s.callouts:
		host.add_callout(c.copy())
	for e: int in s.source_events:
		if not host.source_events.has(e):
			host.source_events.append(e)
	host.source_events.sort()
	for k: StringName in s.shows:
		if not host.shows.has(k):
			host.shows.append(k)
	host.score = maxf(host.score, s.score)


## Loosen a shot's framing until every point is in view (two-shot, then wide).
func _widen_to_cover(host: CinemaShot, pts: Array[Vector2]) -> void:
	if host.framing == G.FRAMING_WIDE:
		return
	var all: Array[Vector2] = [host.focus_point]
	if host.move == G.MOVE_PAN:
		all.append(host.focus_to)
	for p: Vector2 in pts:
		all.append(p)
	var mn := all[0]
	var mx := all[0]
	for p: Vector2 in all:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	var centre := (mn + mx) * 0.5
	var span := (mx - mn).length() + G.SPAN_TWO_SHOT_MARGIN
	host.focus_point = centre
	host.focus_to = centre
	if host.move == G.MOVE_PAN:
		host.move = G.MOVE_HOLD
	host.focus_tape = -1
	if span >= sc.level_span() * 0.8:
		host.framing = G.FRAMING_WIDE
		host.span = sc.level_span()
	else:
		host.framing = G.FRAMING_TWO_SHOT
		host.span = maxf(host.span, maxf(G.SPAN_TWO_SHOT_MIN, span))


func _insert(s: CinemaShot) -> void:
	shots.append(s)
	shots.sort_custom(func(x: CinemaShot, y: CinemaShot) -> bool: return x.start_beat < y.start_beat)


# ───────────────────────────── gaps ─────────────────────────────

func _fill_gaps() -> void:
	var guard := 0
	while guard < 1024:
		guard += 1
		var t := 0
		var gap_a := -1
		var gap_b := -1
		for s: CinemaShot in shots:
			if s.start_beat > t:
				gap_a = t
				gap_b = s.start_beat
				break
			t = maxi(t, s.end_beat)
		if gap_a < 0 and t < horizon:
			gap_a = t
			gap_b = horizon
		if gap_a < 0:
			return
		_fill(gap_a, gap_b)


func _fill(a: int, b: int) -> void:
	var prev: CinemaShot = null
	var nxt: CinemaShot = null
	for s: CinemaShot in shots:
		if s.end_beat == a:
			prev = s
		if s.start_beat == b and nxt == null:
			nxt = s
	# Let a short opening breathe to a full bar first.
	if prev != null and prev.kind == G.KIND_OPENING and prev.length() < G.OPENING_PREFERRED_BEATS:
		var grow := mini(b, G.OPENING_PREFERRED_BEATS) - a
		if grow > 0 and (b - (a + grow) == 0 or b - (a + grow) >= G.MIN_SHOT_BEATS):
			prev.end_beat = a + grow
			return
	if b - a < G.MIN_SHOT_BEATS or shots.size() >= cap:
		if prev != null:
			prev.end_beat = b
		elif nxt != null:
			nxt.start_beat = a
		else:
			_insert(_coverage(a, b))
		return
	# Coverage pieces of at most MAX_COVERAGE_BEATS, cut on bar lines.
	var cur := a
	while cur < b:
		var en := mini(b, cur + G.MAX_COVERAGE_BEATS)
		if en < b:
			var bar := en - en % OD.BEATS_PER_BAR
			if bar - cur >= G.MIN_SHOT_BEATS:
				en = bar
			if b - en < G.MIN_SHOT_BEATS:
				en = b
		if shots.size() >= cap:
			if prev != null:
				prev.end_beat = b
			elif nxt != null:
				nxt.start_beat = cur
			return
		var s := _coverage(cur, en)
		_insert(s)
		prev = s
		cur = en


func _coverage(a: int, b: int) -> CinemaShot:
	var mid := (float(a) + float(b)) * 0.5
	var alive: Array[int] = []
	var f := sc.frame_at_beat(mid)
	if f != null:
		for x: ActorSnap in f.actors:
			if x.life != OD.LifeState.GHOST:
				alive.append(x.tape)
	var s := CinemaShot.new()
	s.kind = G.KIND_COVERAGE
	s.start_beat = a
	s.end_beat = b
	s.core_start = a
	s.core_end = mini(b, a + G.MIN_SHOT_BEATS)
	s.score = G.score_of(G.KIND_COVERAGE)
	s.key_beat = mid
	s.cause_beat = float(a)
	s.focus_point = sc.crowd_pos(mid, alive)
	s.focus_to = s.focus_point
	var r := 0.0
	for k: int in [a, int(mid), b - 1]:
		r = maxf(r, sc.crowd_radius(float(k), s.focus_point, alive))
	s.span = clampf(2.0 * r + G.SPAN_TWO_SHOT_MARGIN, G.SPAN_ROOM_MIN, sc.level_span())
	var rooms := {}
	for t: int in alive:
		rooms[sc.room_of(sc.actor_pos(t, mid))] = true
	if s.span >= sc.level_span() * 0.8 or alive.is_empty():
		s.framing = G.FRAMING_WIDE
		s.span = sc.level_span()
	elif rooms.size() <= 1:
		s.framing = G.FRAMING_ROOM
	else:
		s.framing = G.FRAMING_TWO_SHOT
	s.move = G.MOVE_ORBIT if b - a >= 4 else G.MOVE_HOLD
	var who := ""
	for t: int in alive:
		s.add_tape(t)
		who += OD.tape_letter(t)
	s.reason = "Coverage: the performance between story beats (%s)" % (who if not who.is_empty() else "ghosts")
	s.shows.append(G.KIND_COVERAGE)
	return s


# ───────────────────────────── the cut rule ─────────────────────────────

static func featured(a: CinemaTypes.Action, s: CinemaShot) -> bool:
	if s.framing == G.FRAMING_WIDE:
		return true
	for t: int in a.tapes:
		if s.tapes.has(t):
			return true
	for i: String in a.ids:
		if s.ids.has(i):
			return true
	return s.frames_point(a.point)


## Actions a cut at the end of shots[i] would cut away from.
static func blockers(actions: Array[CinemaTypes.Action], out_shot: CinemaShot, in_shot: CinemaShot) -> Array[CinemaTypes.Action]:
	var b := float(out_shot.end_beat)
	var out: Array[CinemaTypes.Action] = []
	for a: CinemaTypes.Action in actions:
		if a.start_beat >= b - 1e-6:
			break
		if b < a.impact_beat + G.FOLLOW_THROUGH_BEATS - 1e-6 and featured(a, out_shot) and not featured(a, in_shot):
			out.append(a)
	return out


func _legalise_cuts() -> void:
	var guard := 0
	var changed := true
	while changed and guard < 256:
		changed = false
		guard += 1
		for i: int in shots.size() - 1:
			var cur := shots[i]
			var nx := shots[i + 1]
			var bl := blockers(an.actions, cur, nx)
			if bl.is_empty():
				continue
			var later := cur.end_beat
			var earlier := cur.end_beat
			for a: CinemaTypes.Action in bl:
				later = maxi(later, ceili(a.impact_beat + G.FOLLOW_THROUGH_BEATS - 1e-6))
				earlier = mini(earlier, floori(a.start_beat + 1e-6))
			var can_later := later <= nx.core_start and nx.end_beat - later >= G.MIN_SHOT_BEATS
			var can_earlier := earlier >= cur.core_end and earlier - cur.start_beat >= G.MIN_SHOT_BEATS
			if can_later and (not can_earlier or later - cur.end_beat <= cur.end_beat - earlier):
				cur.end_beat = later
				nx.start_beat = later
			elif can_earlier:
				cur.end_beat = earlier
				nx.start_beat = earlier
			else:
				_merge_pair(i)
			changed = true
			break


## Merge shots[i] and shots[i+1] into whichever matters more (the opening always hosts).
func _merge_pair(i: int) -> void:
	var a := shots[i]
	var b := shots[i + 1]
	var host := a
	var guest := b
	if b.kind == G.KIND_OPENING or (a.kind != G.KIND_OPENING and b.score > a.score):
		host = b
		guest = a
	var pts: Array[Vector2] = [guest.focus_point, guest.focus_to]
	var framed := true
	for p: Vector2 in pts:
		if not host.frames_point(p):
			framed = false
	if not framed:
		_widen_to_cover(host, pts)
	host.start_beat = a.start_beat
	host.end_beat = b.end_beat
	host.core_start = mini(a.core_start, b.core_start)
	host.core_end = maxi(a.core_end, b.core_end)
	if guest.kind == G.KIND_FINALE:
		for c: CinemaTypes.Callout in guest.callouts:
			host.add_callout(c.copy())
	_absorb_into(host, guest)
	shots.erase(guest)


func _snap_to_bars() -> void:
	for i: int in shots.size() - 1:
		var cur := shots[i]
		var nx := shots[i + 1]
		var b := cur.end_beat
		if b % OD.BEATS_PER_BAR == 0:
			continue
		var down := b - b % OD.BEATS_PER_BAR
		var up := down + OD.BEATS_PER_BAR
		var cands: Array[int] = []
		if b - down <= up - b:
			cands = [down, up]
		else:
			cands = [up, down]
		for c: int in cands:
			if absi(c - b) > G.BAR_SNAP_BEATS:
				continue
			if c - cur.start_beat < G.MIN_SHOT_BEATS or nx.end_beat - c < G.MIN_SHOT_BEATS:
				continue
			if c < cur.core_end or c > nx.core_start:
				continue
			var old := cur.end_beat
			cur.end_beat = c
			nx.start_beat = c
			if not blockers(an.actions, cur, nx).is_empty():
				cur.end_beat = old
				nx.start_beat = old
				continue
			break


## Final safety: contiguous cover of [0, horizon), every shot at least MIN_SHOT_BEATS.
func _repair() -> void:
	shots.sort_custom(func(x: CinemaShot, y: CinemaShot) -> bool: return x.start_beat < y.start_beat)
	if shots.is_empty():
		shots.append(_graceful_wide())
		return
	shots[0].start_beat = 0
	for i: int in range(1, shots.size()):
		shots[i].start_beat = shots[i - 1].end_beat
	shots[shots.size() - 1].end_beat = horizon
	var guard := 0
	var i := 0
	while i < shots.size() and guard < 256:
		guard += 1
		if shots[i].length() < G.MIN_SHOT_BEATS and shots.size() > 1:
			_merge_pair(i if i < shots.size() - 1 else i - 1)
			i = 0
			continue
		i += 1


## Each explained event belongs to the shot on screen at its beat when that shot shows where it
## happens (or is wide); otherwise it stays with the shot that tells its story.
func _attribute_events() -> void:
	var owner: Dictionary[int, CinemaShot] = {}
	for s: CinemaShot in shots:
		for e: int in s.source_events:
			if not owner.has(e):
				owner[e] = s
	for s: CinemaShot in shots:
		s.source_events.clear()
	var keys: Array[int] = []
	for e: int in owner.keys():
		keys.append(e)
	keys.sort()
	for e: int in keys:
		var ev := an.ev[e]
		var b := sc.beat_of(ev)
		var on := _shot_at(minf(b, float(horizon) - 0.001))
		var host: CinemaShot = owner[e]
		if on != null and on != host and on.frames_point(Vector2(ev.x, ev.y)) and (ev.type != SimEventType.OBJECTIVE or on.framing == G.FRAMING_WIDE):
			host = on
		host.source_events.append(e)


func _finish_shots() -> void:
	_attribute_events()
	for i: int in shots.size():
		var s := shots[i]
		if s.emphasis == G.EMPHASIS_SPLIT:
			if s.panes.size() < 2:
				s.panes.clear()
				s.emphasis = G.EMPHASIS_NONE
			else:
				var rects := G.pane_rects(s.panes.size())
				for k: int in s.panes.size():
					s.panes[k].rect = rects[k]
		elif not s.panes.is_empty():
			s.panes.clear()
		s.letterbox = G.LETTERBOX_DEEP if s.emphasis == G.EMPHASIS_LETTERBOX else G.LETTERBOX_BASE
		s.ripple = G.RIPPLE_STRENGTH if s.emphasis == G.EMPHASIS_TIME_RIPPLE else 0.0
		if s.move == G.MOVE_ORBIT:
			s.move_sign = _orbit_sign
			_orbit_sign = -_orbit_sign
		if s.move != G.MOVE_PAN:
			s.focus_to = s.focus_point
		# The key beat must be inside the shot (a merged guest may have moved it out).
		if not s.contains_beat(s.key_beat):
			s.key_beat = clampf(s.key_beat, float(s.start_beat), float(s.end_beat) - 0.01)
		s.cause_beat = clampf(s.cause_beat, float(s.start_beat), s.key_beat)
		s.transition = G.TRANSITION_CUT
		if i > 0:
			var p := shots[i - 1]
			var near := p.focus_point.distance_to(s.focus_point) < 0.25 * minf(p.span, s.span)
			if near and p.panes.is_empty() and s.panes.is_empty() and p.framing != s.framing:
				s.transition = G.TRANSITION_BLEND


# ───────────────────────────── flourish cues (MUSIC-13) ─────────────────────────────

func _cues() -> Array[CinemaTypes.Cue]:
	var out: Array[CinemaTypes.Cue] = []
	var prog: Array[int] = []
	var chord_bars := 1
	if sc.level != null:
		prog = sc.level.music.progression
		chord_bars = maxi(1, sc.level.music.chord_bars)
	var prev_chord := -1
	var bar := 0
	while bar * OD.BEATS_PER_BAR < horizon:
		var beat := bar * OD.BEATS_PER_BAR
		var sweep := CinemaTypes.Cue.new()
		sweep.beat = float(beat)
		sweep.kind = G.CUE_BAR_SWEEP
		sweep.strength = 1.0 if beat == 0 else 0.6
		out.append(sweep)
		if not prog.is_empty():
			var ci := (bar / chord_bars) % prog.size()
			if prev_chord >= 0 and prog[ci] != prog[prev_chord]:
				var s := _shot_at(float(beat))
				# One emphasis at a time: no palette flash over an emphasised shot.
				if s == null or s.emphasis == G.EMPHASIS_NONE:
					var cf := CinemaTypes.Cue.new()
					cf.beat = float(beat)
					cf.kind = G.CUE_CHORD_FLASH
					cf.chord = ci
					cf.strength = 0.8
					out.append(cf)
			prev_chord = ci
		bar += 1
	for m: CinemaMoment in an.moments:
		if m.shot < 0:
			continue
		if m.score < CinemaGrammar.score_of(G.KIND_KILL) - 0.01 and m.kind != G.KIND_RESCUE:
			continue
		var c := CinemaTypes.Cue.new()
		c.beat = m.key_beat
		c.kind = G.CUE_IMPACT
		c.tape = m.cause_tape if m.cause_tape >= 0 else m.effect_tape
		c.strength = clampf(m.score / 100.0, 0.2, 1.0)
		c.point = m.effect_point
		out.append(c)
	out.sort_custom(func(x: CinemaTypes.Cue, y: CinemaTypes.Cue) -> bool:
		if not is_equal_approx(x.beat, y.beat):
			return x.beat < y.beat
		return String(x.kind) < String(y.kind))
	return out


func _shot_at(beat: float) -> CinemaShot:
	for s: CinemaShot in shots:
		if s.contains_beat(beat):
			return s
	return null
