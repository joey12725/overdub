class_name AudioScheduler
extends RefCounted
## Look-ahead scheduler that follows the simulation's master transport (prototype
## src/audio/scheduler.ts). Pure: it is driven with an explicit clock (`now`, seconds on whatever
## clock the caller plays notes on) and returns what to start and what to cancel, so it is testable
## without audio.
##
## The caller reports `(master_beat, rate, playing)` every frame, where `rate` is master seconds per
## wall second. Master beats therefore advance at `rate · bpm / 60` per wall second and a note at
## master beat `b` is due `(b − master_beat) / (rate · bpm / 60)` seconds from now; its length
## scales the same way. While recording at tape speed `s` the world runs at `rate = 1/s` and the
## active layer's step length is `local_rate / s` master beats (see AudioDirector), so its steps
## last `local_rate / (bpm/60)` wall seconds: the active cassette is heard at the level's base tempo
## and the others at `speed_j / s` of it, with no special case needed here.
##
## Rules that keep notes from sticking or doubling:
##   - only notes not yet started (`time > now`) are ever cancelled; started notes are left to end;
##   - every planned note is remembered by identity, so re-planning a window never plays it twice;
##   - a backwards jump (every take restarts at beat 0), a seek, a pause or a rate change cancels the
##     unstarted notes and re-plans from the current beat; jumps and pauses also ask the caller to
##     choke sounding notes (`choke`). A re-planned note is returned again in `start` under a new id
##     after its old id was returned in `cancel`: it sounds once.

## Result of update(): notes to start, unstarted notes to cancel, and whether sounding notes belong
## to a timeline position that no longer exists (release them quickly).
class Update:
	extends RefCounted
	var start: Array[AudioPlannedNote] = []
	var cancel: Array[AudioPlannedNote] = []
	var choke: bool = false


## Seconds of notes kept planned ahead of `now`.
var lookahead: float = 0.12
## A discrepancy between the reported and the predicted beat larger than this (seconds) is a seek.
var jump_tolerance: float = 0.1
## Notes up to this many seconds late are still played (immediately); older ones are skipped.
var late_tolerance: float = 0.03
## Longest wall-time note (seconds); keeps very slow world rates from producing endless drones.
var max_duration: float = 8.0

var _source: Callable
var _bps: float = 2.0
var _pending: Array[AudioPlannedNote] = []
var _planned: Dictionary = {}
var _cursor: float = 0.0
var _next_id: int = 1
var _has_last: bool = false
var _last_now: float = 0.0
var _last_beat: float = 0.0
var _last_rate: float = 0.0
var _last_playing: bool = false


## `source(from_beat, to_beat) -> Array[AudioLayerNote]` returns notes with onsets in [from, to).
func _init(source: Callable, bpm: float, p_lookahead: float = 0.12) -> void:
	_source = source
	_bps = bpm / 60.0
	lookahead = p_lookahead


## Master beats per second of the caller's clock at `rate`.
func beats_per_second(rate: float) -> float:
	return rate * _bps


## Where the transport is predicted to be at `now`, from the last update; NAN before any update.
func predict_beat(now: float) -> float:
	if not _has_last:
		return NAN
	return _last_beat + (now - _last_now) * _last_rate * _bps if _last_playing else _last_beat


## Planned but not yet started notes (for inspection / tests).
func upcoming() -> Array[AudioPlannedNote]:
	return _pending


## Forget everything (e.g. the note clock changed); returns the notes the caller must cancel.
func reset() -> Array[AudioPlannedNote]:
	var cancelled := _pending
	_pending = []
	_planned.clear()
	_has_last = false
	return cancelled


## The music from the current position on has changed (layer states changed): cancel unstarted
## notes and re-plan them on the next update. Started notes keep their identity, so nothing that
## already sounded is played again.
##
## `commit` (seconds) keeps notes due within that long of `now`: they are already committed to the
## output (inside the next mix plus the output latency) and a replacement could only sound late,
## so they play as planned and the new composition takes over right after them. With commit = 0
## every unstarted note is re-planned (the prototype's behaviour).
func invalidate(now: float, commit: float = 0.0) -> Array[AudioPlannedNote]:
	var keep_until := now + maxf(0.0, commit)
	var cancelled := _cancel_unstarted(keep_until)
	var at := predict_beat(now)
	if not is_nan(at):
		var resume := at
		if commit > 0.0 and _last_playing:
			# Just past the last kept onset, so a new note on that same beat cannot double it.
			resume = at + commit * _last_rate * _bps + 1e-9
		_cursor = minf(_cursor, resume)
	return cancelled


func update(now: float, beat: float, rate: float, playing: bool) -> Update:
	var result := Update.new()
	var finite_beat := not (is_nan(beat) or is_inf(beat))
	var running := playing and rate > 0.0 and not is_inf(rate) and not is_nan(rate) and finite_beat
	var had_prev := _has_last
	var prev_playing := _last_playing
	var prev_beat := _last_beat
	var prev_now := _last_now
	var prev_rate := _last_rate
	_retire_started(now)

	if not running:
		if had_prev and prev_playing:
			result.cancel = _cancel_unstarted(now)
			result.choke = true
		var held := beat if finite_beat else 0.0
		# A seek while stopped (every take is counted in at beat 0 with the transport stopped, after
		# the last take stopped somewhere later): the same beats must be playable again. Without
		# this the move is invisible by the time the transport starts, and the new take would skip
		# every note the previous one already played.
		if had_prev and (held < prev_beat - 1e-6 or held - prev_beat > jump_tolerance * maxf(1.0, prev_rate) * _bps):
			_forget_planned()
		_set_last(now, held, 0.0, false)
		_cursor = _last_beat
		return result

	var bps_now := rate * _bps
	var late_beats := late_tolerance * bps_now
	if not had_prev or not prev_playing:
		# Starting (or resuming): a downbeat that is a few milliseconds behind still sounds.
		_cursor = beat - late_beats
		# Resuming where we paused keeps the record of what already sounded; only a seek while
		# paused (or a restart at 0) makes the same beats playable again.
		if had_prev and (beat < prev_beat - 1e-6 or beat - prev_beat > jump_tolerance * bps_now):
			_forget_planned()
	else:
		var predicted := prev_beat + (now - prev_now) * prev_rate * _bps
		var error_seconds := absf(beat - predicted) / bps_now
		if error_seconds > jump_tolerance:
			# A seek: every take jumps back to beat 0, reviews can be skipped.
			result.cancel = _cancel_unstarted(now)
			result.choke = true
			_forget_planned()
			_cursor = beat - late_beats
		elif absf(rate - prev_rate) > 1e-6 * maxf(1.0, prev_rate):
			# Unstarted notes were timed for the old rate; re-plan them for the new one.
			result.cancel = _cancel_unstarted(now)
			_cursor = minf(_cursor, beat)

	# Fell behind (a long frame): skip what is too late rather than playing a burst of old notes.
	if _cursor < beat - late_beats:
		_cursor = beat - late_beats
	var horizon := beat + lookahead * bps_now
	if horizon > _cursor:
		var notes: Array[AudioLayerNote] = _source.call(_cursor, horizon)
		for note: AudioLayerNote in notes:
			var key := note.key()
			if _planned.has(key):
				continue
			var time := maxf(now, now + (note.beat - beat) / bps_now)
			var dur := minf(max_duration, maxf(0.01, note.duration / bps_now))
			var p := AudioPlannedNote.make(_next_id, note, time, dur)
			_next_id += 1
			_planned[key] = p
			_pending.append(p)
			result.start.append(p)
		_cursor = horizon
	_prune_planned(beat)
	_set_last(now, beat, rate, true)
	return result


func _set_last(now: float, beat: float, rate: float, playing: bool) -> void:
	_has_last = true
	_last_now = now
	_last_beat = beat
	_last_rate = rate
	_last_playing = playing


func _retire_started(now: float) -> void:
	var any := false
	for p: AudioPlannedNote in _pending:
		if p.time <= now:
			any = true
			break
	if not any:
		return
	var kept: Array[AudioPlannedNote] = []
	for p: AudioPlannedNote in _pending:
		if p.time > now:
			kept.append(p)
	_pending = kept


func _cancel_unstarted(now: float) -> Array[AudioPlannedNote]:
	var cancelled: Array[AudioPlannedNote] = []
	var kept: Array[AudioPlannedNote] = []
	for p: AudioPlannedNote in _pending:
		if p.time > now:
			cancelled.append(p)
		else:
			kept.append(p)
	_pending = kept
	for p: AudioPlannedNote in cancelled:
		_planned.erase(p.note.key())
	return cancelled


## After a seek the same beats can legitimately play again.
func _forget_planned() -> void:
	_planned.clear()
	for p: AudioPlannedNote in _pending:
		_planned[p.note.key()] = p


func _prune_planned(beat: float) -> void:
	if _planned.size() < 512:
		return
	for k: String in _planned.keys():
		var p: AudioPlannedNote = _planned[k]
		if p.note.beat < beat - 8.0:
			_planned.erase(k)
