class_name ReplayPlayback
extends RefCounted
## Plays a verified replay as the locked cinematic (CINE-01..05, TEST-32): true master speed (one
## wall second per master second), every resolved event re-emitted once in order for audio and fx,
## frames taken verbatim from the Resolution, and no input path at all, so nothing the player does
## can alter the result. The only control is skip() (CINE-02: stop watching), which changes no state
## of the performance. Node-free; the game drives it like GameSession's cinematic phase:
##
##     var pb := ReplayPlayback.new(check.resolution, level, check.record)
##     # each frame:
##     pb.advance(dt)
##     var f := pb.current_frame()          # f.snap / f.prev / f.alpha -> WorldViewBase.render
##     audio.on_events(pb.drain_events())
##     ui.update_hud(pb.view(), pulse)
##     if pb.done: back to the campaign screen

## The snapshot pair to draw.
class Frame:
	extends RefCounted
	var snap: FrameSnapshot = null
	var prev: FrameSnapshot = null
	var alpha: float = 1.0

	static func make(p_snap: FrameSnapshot, p_prev: FrameSnapshot, p_alpha: float) -> Frame:
		var f := Frame.new()
		f.snap = p_snap
		f.prev = p_prev
		f.alpha = p_alpha
		return f


var resolution: Resolution = null
var level: LevelDef = null
var record: ReplayRecord = null
## Master substeps (float) into the playback.
var play_sub: float = 0.0
var _event_cursor: int = 0
var _events: Array[SimEvent] = []

## True once the playhead reached the horizon (or skip() was called).
var done: bool:
	get:
		return play_sub >= float(resolution.horizon_subs)


func _init(p_resolution: Resolution, p_level: LevelDef, p_record: ReplayRecord = null) -> void:
	resolution = p_resolution
	level = p_level
	record = p_record


## Advance by wall seconds at true master speed (OD.SUB_HZ substeps per second).
func advance(dt_wall_seconds: float) -> void:
	var dt := dt_wall_seconds if not is_nan(dt_wall_seconds) and not is_inf(dt_wall_seconds) and dt_wall_seconds > 0.0 else 0.0
	if dt == 0.0 or done:
		return
	play_sub = minf(float(resolution.horizon_subs), play_sub + dt * OD.SUB_HZ)
	while _event_cursor < resolution.events.size() and resolution.events[_event_cursor].sub + 1 <= play_sub:
		_events.append(resolution.events[_event_cursor])
		_event_cursor += 1


## Stop watching: jump to the end. Events not yet reached are dropped (they are not "replayed").
func skip() -> void:
	play_sub = float(resolution.horizon_subs)
	_event_cursor = resolution.events.size()


## Events reached since the last drain, in order.
func drain_events() -> Array[SimEvent]:
	var out := _events
	_events = []
	return out


## Master beat of the playhead.
func beat() -> float:
	return play_sub / ODTime.subs_per_beat(level)


## The pair of stored frames around the playhead (shifted by the settings A/V offset when given).
func current_frame(visual_delay_seconds: float = 0.0) -> Frame:
	var frames := resolution.frames
	var delay := visual_delay_seconds * OD.SUB_HZ
	if is_nan(delay) or is_inf(delay):
		delay = 0.0
	var at := minf(float(resolution.horizon_subs), maxf(0.0, play_sub - delay))
	var last := frames.size() - 1
	var step := frames[1].sub if frames.size() > 1 and frames[1].sub > 0 else 1
	var k := clampi(int(floorf(at / step)), 0, last)
	while k > 0 and frames[k].sub > at:
		k -= 1
	while k < last and frames[k + 1].sub <= at:
		k += 1
	if k >= last:
		return Frame.make(frames[last], frames[last], 1.0)
	var prev := frames[k]
	var snap := frames[k + 1]
	return Frame.make(snap, prev, clampf((at - prev.sub) / float(snap.sub - prev.sub), 0.0, 1.0))


## A HUD view of the replay: phase CINEMATIC, every recorded cassette COMMITTED with its speed, end
## mode, progress and the self's state, the outcome, and SKIP as the only action.
func view() -> SessionView:
	var v := SessionView.new()
	var snap := current_frame().snap
	v.phase = SessionPhase.CINEMATIC
	v.level = level
	v.active = -1
	v.beat = snap.beat
	v.horizon_beats = float(resolution.horizon_subs) / ODTime.subs_per_beat(level)
	v.world_rate = 0.0 if done else 1.0
	v.speeds = level.speeds.duplicate()
	v.end_modes = level.end_modes.duplicate()
	v.objective = ObjectiveView.new()
	v.objective.complete = snap.objective.complete
	v.objective.progress = snap.objective.progress
	v.objective.survivors = snap.objective.survivors
	v.objective.text = level.objective.text
	v.outcome = resolution.outcome
	v.actions.assign([SessionAction.SKIP])
	var tapes: Array[ODTape] = []
	if record != null:
		tapes = record.tapes
	for i: int in OD.TAPE_COUNT:
		var d := v.decks[i]
		d.index = i
		if i >= level.max_tapes:
			d.status = DeckStatus.UNAVAILABLE
			continue
		var tape: ODTape = null
		for t: ODTape in tapes:
			if t.index == i:
				tape = t
		var actor := snap.actor(i)
		if tape == null and actor == null:
			d.status = DeckStatus.EMPTY
			continue
		d.status = DeckStatus.COMMITTED
		if tape != null:
			d.speed = tape.speed
			d.end_mode = tape.end_mode
			d.span_bars = ODTime.span_bars(level, tape.speed)
			for e: TapeEvent in tape.events:
				var m := DeckMark.new()
				m.tick = e.tick
				m.kind = e.kind
				d.marks.append(m)
		if actor != null:
			d.life = actor.life
			d.synced = actor.synced
			d.transport = 0 if done else actor.phase.dir
			var ticks := tape.ticks if tape != null else 0
			d.local_progress = clampf(actor.phase.tick / ticks, 0.0, 1.0) if ticks > 0 else 0.0
			d.reel_rate = d.speed * v.world_rate * absf(d.transport)
	return v
