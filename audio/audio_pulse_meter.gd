class_name AudioPulseMeter
extends RefCounted
## MusicPulse from what was actually scheduled (prototype src/audio/pulse.ts; MUSIC-12, MUSIC-13
## visuals). Pure.
##
## Levels and pitches come from planned notes whose start time has passed on the listening clock,
## not from the composition, so visuals never show a note that was cancelled or never played.

## Seconds for a layer level to decay to 1/e after a note.
const LEVEL_DECAY := 0.22
## Notes older than this no longer contribute to levels.
const HISTORY := 1.5
## Levels below this read as silence (an exponential tail never reaches 0 by itself).
const FLOOR := 0.001

var _notes: Array = [[], [], [], []]
var _last_pitch: PackedFloat32Array = PackedFloat32Array([0.5, 0.5, 0.5, 0.5])
var _last_onset: PackedFloat64Array = PackedFloat64Array([-INF, -INF, -INF, -INF])


static func _finite(x: float) -> bool:
	return not (is_nan(x) or is_inf(x))


## Safe pulse when nothing is playing.
static func silent_pulse(beat: float = 0.0, chord: int = 0) -> MusicPulse:
	var p := MusicPulse.new()
	p.beat = beat if _finite(beat) else 0.0
	p.beat_pulse = beat_pulse(beat)
	p.bar_pulse = bar_pulse(beat)
	p.levels = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	p.pitches = PackedFloat32Array([0.5, 0.5, 0.5, 0.5])
	p.chord = chord
	return p


static func _frac(x: float) -> float:
	return x - floorf(x)


## Saw that is 1 exactly on each beat and falls to 0 just before the next.
static func beat_pulse(beat: float) -> float:
	if not _finite(beat):
		return 0.0
	return clampf(1.0 - _frac(beat), 0.0, 1.0)


static func bar_pulse(beat: float) -> float:
	if not _finite(beat):
		return 0.0
	return clampf(1.0 - _frac(beat / OD.BEATS_PER_BAR), 0.0, 1.0)


func add(p: AudioPlannedNote) -> void:
	var t := p.note.track
	if t < 0 or t >= OD.TAPE_COUNT:
		return
	var list: Array = _notes[t]
	list.append(p)
	if list.size() > 256:
		_notes[t] = list.slice(list.size() - 192)


func cancel(ids: Array[int]) -> void:
	if ids.is_empty():
		return
	var gone := {}
	for id: int in ids:
		gone[id] = true
	for t: int in OD.TAPE_COUNT:
		var kept: Array = []
		for p: AudioPlannedNote in _notes[t]:
			if not gone.has(p.id):
				kept.append(p)
		_notes[t] = kept


## Sounding music was choked at `now` (seek, pause, take restart): notes that started before it
## stop sustaining there, so the meter shows what is actually heard.
func choke(now: float) -> void:
	for t: int in OD.TAPE_COUNT:
		for p: AudioPlannedNote in _notes[t]:
			if p.time <= now and p.time + p.dur > now:
				p.dur = maxf(0.0, now - p.time)


func clear() -> void:
	_notes = [[], [], [], []]
	_last_pitch = PackedFloat32Array([0.5, 0.5, 0.5, 0.5])
	_last_onset = PackedFloat64Array([-INF, -INF, -INF, -INF])


## `now`: listening time on the clock notes were planned on; `beat`: master beat to report;
## `chord`: progression index at that beat.
func sample(now: float, beat: float, chord: int) -> MusicPulse:
	var levels := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var pitches := PackedFloat32Array([0.5, 0.5, 0.5, 0.5])
	for t: int in OD.TAPE_COUNT:
		var list: Array = _notes[t]
		var keep_from := 0
		var level := 0.0
		var onset := _last_onset[t]
		var pitch: float = _last_pitch[t]
		for i: int in list.size():
			var p: AudioPlannedNote = list[i]
			if p.time + p.dur < now - HISTORY:
				keep_from = i + 1
				continue
			if p.time > now:
				continue
			var age := maxf(0.0, now - p.time)
			var sustain := 0.35 if age < p.dur else 0.0
			var energy := (p.note.velocity / 127.0) * maxf(exp(-age / LEVEL_DECAY), sustain)
			if energy < FLOOR:
				energy = 0.0
			if energy > level:
				level = energy
			# Chords start together: report the top voice of the latest onset.
			if p.time > onset + 1e-6 or (absf(p.time - onset) <= 1e-6 and p.note.norm > pitch):
				onset = p.time
				pitch = p.note.norm
		if keep_from > 0:
			_notes[t] = list.slice(keep_from)
		_last_onset[t] = onset
		_last_pitch[t] = pitch
		levels[t] = clampf(level, 0.0, 1.0)
		pitches[t] = clampf(pitch if _finite(pitch) else 0.5, 0.0, 1.0)
	var out := MusicPulse.new()
	var safe_beat := beat if _finite(beat) else 0.0
	out.beat = safe_beat
	out.beat_pulse = beat_pulse(safe_beat)
	out.bar_pulse = bar_pulse(safe_beat)
	out.levels = levels
	out.pitches = pitches
	out.chord = chord if chord >= 0 else 0
	return out
