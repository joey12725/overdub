class_name MVMusic
extends RefCounted
## The music model every visualiser reads (MUSIC-01..04, MUSIC-12): a level's four cassette layers
## (MVLayer), their compiled notes (MVNotes), the shared chord clock, and the per-layer visual state
## (MVTrack) advanced by update(). Node-free; one per loaded level, shared by every visualiser.
##
##   var m := MVMusic.from_level(level)
##   m.update(master_beat, tracks)          # tracks: Array[TrackAudioState] (4), as sent to audio
##   m.tracks[i].value_at(m.beat)           # contour value of layer i at the playhead
##   m.notes_in(i, m.beat - 4.0, m.beat)    # notes layer i played in the last bar

var bpm: float = 120.0
var root: int = 0
var scale: String = "Minor"
var progression: Array[int] = [0]
## Master beats per chord.
var chord_beats: float = 4.0
var horizon_bars: int = 16
var layers: Array[MVLayer] = []
var tracks: Array[MVTrack] = []
var notes: MVNotes = null
var drift: MVDesyncDrift = MVDesyncDrift.new()
## Current master beat (last update()).
var beat: float = 0.0
## Optional override for note queries, e.g. the audio module's own director once it exists:
## func(track: int, variant: MVVariant, bar: int) -> Array[MVNote].
var note_source: Callable = Callable()
## Keeps the object behind note_source alive (a Callable does not hold a reference).
var note_source_owner: RefCounted = null

var _base: HGState = null
var _prefetch_track: int = 0
var _chords: Dictionary = {}


static func from_level(level: LevelDef) -> MVMusic:
	return make(level.music, level.bpm, level.horizon_bars)


static func make(music: LevelMusicDef, p_bpm: float, p_horizon_bars: int = 16) -> MVMusic:
	var m := MVMusic.new()
	m.bpm = clampf(p_bpm, 20.0, 999.0)
	m.horizon_bars = maxi(1, p_horizon_bars)
	m.root = posmod(int(HGMath.js_round(float(music.root))), 12)
	m.scale = resolve_scale(music.scale)
	var prog: Array[int] = []
	for d: int in music.progression:
		prog.append(d)
	if prog.is_empty():
		prog = [0]
	m.progression = prog
	m.chord_beats = float(maxi(1, music.chord_bars if music.chord_bars > 0 else 1) * OD.BEATS_PER_BAR)
	var s := Harmonograph.make_state()
	s.channels = []
	s.tempo = m.bpm
	s.root = m.root
	s.scale = m.scale
	s.chord_source = "progression"
	s.progression = prog.duplicate()
	s.chord_rate = m.chord_beats
	s.extension = 0
	s.inversion = 0
	s.spread = 0.0
	s.chord_octave = 0
	s.quality = "diatonic"
	s.borrowed = ""
	s.shift = false
	s.escape = false
	m._base = s
	for i: int in OD.TAPE_COUNT:
		var def: TrackMusicDef = music.tracks[i] if i < music.tracks.size() else TrackMusicDef.new()
		var l := MVLayer.make(i, def, m.root)
		m.layers.append(l)
		m.tracks.append(MVTrack.make(l))
	m.notes = MVNotes.make(s, m.layers, m.bpm, m.chord_beats)
	# Precompute the contour tables for the whole horizon at the fastest tape speed (plus the
	# visualisers' look-ahead), so no table grows during play.
	var max_speed: float = OD.ALL_SPEEDS[OD.ALL_SPEEDS.size() - 1]
	var beats := float(m.horizon_bars * OD.BEATS_PER_BAR) + 16.0
	for l: MVLayer in m.layers:
		l.ensure_steps(maxf(float(l.cycle) + 8.0, beats * max_speed / l.local_rate))
	return m


## director.ts resolveScale.
static func resolve_scale(name: String) -> String:
	if Harmonograph.SCALES.has(name):
		return name
	for k: String in Harmonograph.SCALE_NAMES:
		if k.to_lower() == name.to_lower():
			return k
	return "Minor"


## Advances to master `p_beat` with the four cassettes' states (null / missing = absent).
func update(p_beat: float, states: Array) -> void:
	if p_beat < beat - 1.0:
		drift.reset()
	beat = p_beat
	for i: int in OD.TAPE_COUNT:
		var s: TrackAudioState = states[i] if i < states.size() else null
		tracks[i].update(p_beat, s)
		var desynced := s != null and s.present and s.life == OD.LifeState.ALIVE and not s.synced
		drift.update(i, desynced, p_beat)


# ───────────────────────────── harmony ─────────────────────────────

## Index into the progression of the chord in force at master `at_beat`.
func chord_index(at_beat: float) -> int:
	return posmod(floori(maxf(0.0, at_beat) / chord_beats), progression.size())


## Master beat at which the chord in force at `at_beat` began.
func chord_start(at_beat: float) -> float:
	return floorf(maxf(0.0, at_beat) / chord_beats) * chord_beats


## The chord in force at master `at_beat` (engine chordAt; cached per progression slot).
func chord_at(at_beat: float) -> HGChord:
	var i := chord_index(at_beat)
	if not _chords.has(i):
		_chords[i] = Harmonograph.chord_at(_base, float(i) * chord_beats)
	return _chords[i]


# ───────────────────────────── notes ─────────────────────────────

## The note variant of layer `track` during master bar `bar` under its current state (null: absent).
func variant(track: int, bar: int) -> MVVariant:
	var t := tracks[track]
	if not t.present:
		return null
	var dead := t.is_dead()
	return MVVariant.make(t.speed, dead, t.transport, 0.0 if dead else drift.at(track, bar))


## Compiles (and caches) the notes of the bar containing master `at_beat` for ONE layer, rotating
## through the layers on successive calls. The hub calls it once per frame a little ahead of the
## playhead so drawing never pays for a compile.
func prefetch(at_beat: float) -> void:
	var i := _prefetch_track
	_prefetch_track = (_prefetch_track + 1) % OD.TAPE_COUNT
	if at_beat < 0.0 or i >= layers.size():
		return
	var bar := floori(at_beat / OD.BEATS_PER_BAR)
	var v := variant(i, bar)
	if v == null:
		return
	if note_source.is_valid():
		note_source.call(i, v, bar)
	else:
		notes.bar_notes(i, v, bar)


## Notes of layer `track` with onsets in master [from, to), sorted by beat.
func notes_in(track: int, from: float, to: float) -> Array[MVNote]:
	var out: Array[MVNote] = []
	if to <= from or track < 0 or track >= layers.size():
		return out
	for bar: int in range(maxi(0, floori(from / OD.BEATS_PER_BAR)), ceili(to / OD.BEATS_PER_BAR)):
		var v := variant(track, bar)
		if v == null:
			break
		var src: Array = note_source.call(track, v, bar) if note_source.is_valid() else notes.bar_notes(track, v, bar)
		for n: MVNote in src:
			if n.beat >= from - 1e-9 and n.beat < to - 1e-9:
				out.append(n)
	return out
