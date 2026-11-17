class_name CinemaDirector
extends Node
## Runtime half of the cinematic director. Given the plan and the current master beat it returns
## the camera target / span / yaw, letterbox, time ripple, split-screen layout and callouts for
## this frame, with eased moves inside a shot, hard cuts (or a one-beat blend) between shots, and
## eased letterbox / split transitions. It changes nothing in the world: the world / camera and fx
## owners apply the CinemaFrame (docs/CINEMATIC.md "Integration").
##
##     var director := CinemaDirector.new()
##     add_child(director)
##     director.set_plan(CinemaPlanner.plan(resolution, level, ctx))
##     # every rendered frame of the cinematic:
##     var cf := director.advance(frame.snap.beat, frame.snap)
##
## sample(beat, snap) is pure (same inputs, same output; safe to scrub); advance() is the
## stateful per-frame call that also reports cuts and the flourish cues crossed since last frame.

signal shot_started(index: int, shot: CinemaShot)
signal cue_fired(cue: CinemaTypes.Cue)

const G := preload("res://cinema/cinema_grammar.gd")
## How strongly a shot follows its tracked self's live position (the rest is the planned point).
const TRACK_CLOSE := 0.8
const TRACK_OTHER := 0.5

var plan: CinemaPlan = null
var _last_beat: float = -INF
var _last_index: int = -1
var _cue_cursor: int = 0


func set_plan(p: CinemaPlan) -> void:
	plan = p
	reset()


func reset() -> void:
	_last_beat = -INF
	_last_index = -1
	_cue_cursor = 0


## Per-frame call: sample, mark a hard cut on the first frame of a new shot, collect crossed cues
## (and emit shot_started / cue_fired). A backwards jump resets the cue cursor.
func advance(beat: float, snap: FrameSnapshot = null) -> CinemaFrame:
	var f := sample(beat, snap)
	if plan == null:
		return f
	if _last_beat == -INF:
		# First frame (possibly mid-way, after a resume): only cues from now on.
		while _cue_cursor < plan.cues.size() and plan.cues[_cue_cursor].beat < beat - 1e-3:
			_cue_cursor += 1
	elif beat < _last_beat - 1e-6:
		_cue_cursor = 0
		while _cue_cursor < plan.cues.size() and plan.cues[_cue_cursor].beat <= beat:
			_cue_cursor += 1
		_last_index = -1
	if f.shot_index != _last_index:
		f.cut = f.shot != null and (f.shot.transition == G.TRANSITION_CUT or _last_index < 0)
		_last_index = f.shot_index
		if f.shot != null:
			shot_started.emit(f.shot_index, f.shot)
	while _cue_cursor < plan.cues.size() and plan.cues[_cue_cursor].beat <= beat:
		var c := plan.cues[_cue_cursor]
		f.cues.append(c)
		cue_fired.emit(c)
		_cue_cursor += 1
	_last_beat = beat
	return f


## Pure: the framing at `beat`. `snap` (optional) lets tracked shots follow the live positions.
func sample(beat: float, snap: FrameSnapshot = null) -> CinemaFrame:
	return CinemaDirector.sample_plan(plan, beat, snap)


static func sample_plan(p: CinemaPlan, beat: float, snap: FrameSnapshot = null) -> CinemaFrame:
	var f := CinemaFrame.new()
	if p == null or p.shots.is_empty():
		f.wide = 1.0
		return f
	var i := p.shot_index_at(beat)
	var s := p.shots[i]
	f.shot_index = i
	f.shot = s
	_state(s, beat, snap, f)
	# Blend transition: ease from where the previous shot ended.
	if i > 0 and s.transition == G.TRANSITION_BLEND and beat < float(s.start_beat) + G.BLEND_BEATS:
		var prev := CinemaFrame.new()
		_state(p.shots[i - 1], float(s.start_beat) - 0.001, snap, prev)
		var k := _smooth((beat - float(s.start_beat)) / G.BLEND_BEATS)
		f.target = prev.target.lerp(f.target, k)
		f.span = lerpf(prev.span, f.span, k)
		f.wide = lerpf(prev.wide, f.wide, k)
		f.yaw_offset = lerpf(prev.yaw_offset, f.yaw_offset, k)
	# Letterbox eases across the boundary on both sides (the plan is known in advance).
	f.letterbox = s.letterbox
	if i > 0 and beat < float(s.start_beat) + G.EASE_BEATS:
		var k2 := _smooth((beat - float(s.start_beat)) / G.EASE_BEATS)
		f.letterbox = lerpf(p.shots[i - 1].letterbox, s.letterbox, 0.5 + 0.5 * k2)
	elif i + 1 < p.shots.size() and beat > float(s.end_beat) - G.EASE_BEATS:
		var k3 := _smooth((beat - (float(s.end_beat) - G.EASE_BEATS)) / G.EASE_BEATS)
		f.letterbox = lerpf(s.letterbox, p.shots[i + 1].letterbox, 0.5 * k3)
	f.emphasis = s.emphasis
	if s.emphasis == G.EMPHASIS_TIME_RIPPLE:
		var x := (beat - s.key_beat) / 0.6
		f.ripple = s.ripple * exp(-x * x)
	# Split panes open over EASE_BEATS and close over the last EASE_BEATS.
	if s.emphasis == G.EMPHASIS_SPLIT and not s.panes.is_empty():
		var open := _smooth((beat - float(s.start_beat)) / G.EASE_BEATS)
		var close := _smooth((float(s.end_beat) - beat) / G.EASE_BEATS)
		f.split_t = minf(open, close)
		for pane: CinemaTypes.Pane in s.panes:
			var q := pane.copy()
			q.focus = _track(pane.tape, pane.focus, snap, TRACK_CLOSE)
			f.panes.append(q)
	# Callouts fade in over a quarter beat and swell on the key beat.
	var fade := _smooth((beat - float(s.start_beat)) / 0.25) * _smooth((float(s.end_beat) - beat) / 0.25)
	var swell := 0.7 + 0.3 * exp(-pow((beat - s.key_beat) / 0.75, 2.0))
	for c: CinemaTypes.Callout in s.callouts:
		var q2 := c.copy()
		q2.strength = clampf(fade * swell, 0.0, 1.0)
		f.callouts.append(q2)
	return f


static func _state(s: CinemaShot, beat: float, snap: FrameSnapshot, f: CinemaFrame) -> void:
	var n := maxf(1.0, float(s.length()))
	var u := clampf((beat - float(s.start_beat)) / n, 0.0, 1.0)
	var e := _smooth(u)
	f.progress = u
	var target := s.focus_point
	if s.move == G.MOVE_PAN:
		var a := float(s.start_beat) + 0.5
		var b := maxf(a + 0.5, s.key_beat)
		target = s.focus_point.lerp(s.focus_to, _smooth((beat - a) / (b - a)))
	elif s.focus_tape >= 0:
		target = _track(s.focus_tape, s.focus_point, snap, TRACK_CLOSE if s.framing == G.FRAMING_CLOSE else TRACK_OTHER)
	f.target = target
	var span := s.span
	if s.move == G.MOVE_PUSH_IN:
		span *= lerpf(G.PUSH_FROM, G.PUSH_TO, e)
	elif s.move == G.MOVE_PULL_OUT:
		span *= lerpf(G.PULL_FROM, G.PULL_TO, e)
	f.span = span
	f.wide = 1.0 if s.framing == G.FRAMING_WIDE else 0.0
	f.yaw_offset = 0.0
	if s.move == G.MOVE_ORBIT:
		f.yaw_offset = deg_to_rad(G.ORBIT_DEGREES) * s.move_sign * (2.0 * e - 1.0)


static func _track(tape: int, planned: Vector2, snap: FrameSnapshot, weight: float) -> Vector2:
	if tape < 0 or snap == null:
		return planned
	var a := snap.actor(tape)
	if a == null:
		return planned
	var live := Vector2(a.x, a.y)
	if not a.synced and a.has_spark:
		live = (live + a.spark) * 0.5
	return planned.lerp(live, weight)


static func _smooth(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
