class_name AudioDirector
extends RefCounted
## Turns a level's music definition into Harmonograph channels and compiles the notes each cassette
## layer plays for a given layer state (prototype src/audio/director.ts; MUSIC-01..04, MUSIC-08,
## MUSIC-09).
##
## Pure and deterministic: no nodes, no clocks. Same level + same layer variant + same bar always
## gives the same notes.
##
## Time model. The engine state runs on the MASTER beat clock (tempo = level.bpm) and its chord
## progression is keyed to the master beat, so every layer maps pitch under the chord active at the
## current master beat. A cassette recorded at speed `s` occupies `1/s` of the master time its local
## timeline does (TIME-03), so its layer's step length on the master clock is `local_rate / s`:
## steps of 0.5x / 1x / 2x / 4x layers nest by powers of two and stay on one grid (MUSIC-03). The
## step index `n = master_beat / (local_rate / s)` is therefore the LOCAL step, so contour, gate and
## accent patterns are the same music, just faster or slower. Retrograde / hold only change how the
## contour is read at the current step; they never rewind the chord clock.

const DRUM_KICK: StringName = &"kick"
const DRUM_SNARE: StringName = &"snare"
const DRUM_CLAP: StringName = &"clap"
const DRUM_HAT_CLOSED: StringName = &"hatClosed"
const DRUM_HAT_OPEN: StringName = &"hatOpen"
const DRUM_TOM: StringName = &"tom"
const DRUM_RIM: StringName = &"rim"
const DRUM_PERC: StringName = &"perc"
const DRUM_KINDS: Array[StringName] = [DRUM_KICK, DRUM_SNARE, DRUM_CLAP, DRUM_HAT_CLOSED, DRUM_HAT_OPEN, DRUM_TOM, DRUM_RIM, DRUM_PERC]

const DRUM_NOTE: Dictionary = {
	&"kick": 36, &"rim": 37, &"snare": 38, &"clap": 39, &"hatClosed": 42, &"tom": 45, &"hatOpen": 46, &"perc": 56,
}
## Rough "height" of each drum for contour visuals: low drums low, cymbals high.
const DRUM_NORM: Dictionary = {
	&"kick": 0.05, &"tom": 0.3, &"snare": 0.45, &"clap": 0.5, &"rim": 0.55, &"perc": 0.65, &"hatClosed": 0.85, &"hatOpen": 0.95,
}

## Per-role starting points (layer-param defaults come from AudioFormulas.ROLE_DEFAULTS), chosen so
## any formula lands somewhere consonant and uncluttered. Bass picks only chord tones (palette 0)
## so it can never rub against the harmony.
const ROLE_SHAPES: Dictionary = {
	&"melody": {"type": "Melody", "palette": 2, "floor": 55, "span": 19, "gate_length": 0.8, "accent": 96, "ghost": 50},
	&"bass": {"type": "Bass", "palette": 0, "floor": 31, "span": 17, "gate_length": 0.85, "accent": 104, "ghost": 64},
	&"chord": {"type": "Chord", "palette": 2, "floor": 50, "span": 19, "gate_length": 0.92, "accent": 82, "ghost": 58},
	&"drums": {"type": "Drums", "palette": 2, "floor": 36, "span": 12, "gate_length": 0.5, "accent": 110, "ghost": 40},
}

const _ENGINE_BASE_INDEX: Dictionary = {"Melody": 0, "Bass": 2, "Chord": 3, "Drums": 4}
## Genres whose backbeat reads better as a clap than a snare.
const _CLAP_GENRES: Array[String] = ["House", "Trap", "Jersey club", "Reggaeton", "Dancehall"]
## Genres whose perc lane is a tom rather than a pitched perc blip.
const _TOM_GENRES: Array[String] = ["Rock", "Funk / disco", "Boom bap", "Lo-fi 80", "Jungle"]
const _SWING_GENRES: Array[String] = ["Lo-fi 80", "Boom bap", "Funk / disco"]
const DEFAULT_GENRE := "Lo-fi 80"
const _MS_PER_MINUTE := 60000.0
const _CACHE_LIMIT := 768

var bpm: float = 120.0
var root: int = 0
var scale: String = "Minor"
## Pitch classes of the level scale.
var scale_pcs: Array[int] = []
var progression: Array[int] = []
## Master beats per chord.
var chord_beats: float = 4.0

var _base: HGState
var _layers: Array[_Layer] = []
var _cache: Dictionary = {}


class _Layer:
	extends RefCounted
	var role: StringName = MusicRole.MELODY
	var formula: String = ""
	var formula_params: Dictionary[String, float] = {}
	var layer_params: Dictionary[String, float] = {}
	var genre: String = ""
	var low: int = 0
	var high: int = 0


class _DrumLane:
	extends RefCounted
	var lane: int = 0
	var kind: StringName = &""
	## Whether this lane carries the cassette's own formula (the "signature" lane).
	var signature: bool = false
	var groove_voice: int = 0
	var accent: float = 0.0
	var ghost: float = 0.0

	static func make(p_lane: int, p_kind: StringName, p_signature: bool, p_voice: int, p_accent: float, p_ghost: float) -> _DrumLane:
		var d := _DrumLane.new()
		d.lane = p_lane
		d.kind = p_kind
		d.signature = p_signature
		d.groove_voice = p_voice
		d.accent = p_accent
		d.ghost = p_ghost
		return d


## Layer summary (director.ts LayerInfo).
class LayerInfo:
	extends RefCounted
	var role: StringName = MusicRole.MELODY
	var formula: String = ""
	var low: int = 0
	var high: int = 0


## `level` provides bpm and music (only those are read).
func _init(level: LevelDef) -> void:
	var m: LevelMusicDef = level.music
	bpm = clampf(level.bpm, 20.0, 999.0)
	root = posmod(int(HGMath.js_round(m.root)), 12)
	scale = resolve_scale(m.scale)
	scale_pcs = []
	for p: int in Harmonograph.scale_intervals(scale):
		scale_pcs.append((p + root) % 12)
	progression = []
	for d: int in m.progression:
		progression.append(d)
	if progression.is_empty():
		progression = [0]
	chord_beats = float(maxi(1, m.chord_bars if m.chord_bars > 0 else 1)) * OD.BEATS_PER_BAR

	var s := Harmonograph.make_state()
	s.channels = []
	s.tempo = bpm
	s.root = root
	s.scale = scale
	s.chord_source = "progression"
	s.progression = progression.duplicate()
	s.chord_rate = chord_beats
	s.extension = 0
	s.inversion = 0
	s.spread = 0.0
	s.chord_octave = 0
	s.quality = "diatonic"
	s.borrowed = ""
	s.shift = false
	# Chromatic escape stays off: every voice is snapped into the level scale (MUSIC-04).
	s.escape = false
	_base = s

	for i: int in OD.TAPE_COUNT:
		var t: TrackMusicDef = m.tracks[i] if i < m.tracks.size() else _silent_track()
		_layers.append(_prepare_layer(t))


static func _silent_track() -> TrackMusicDef:
	var t := TrackMusicDef.new()
	t.role = MusicRole.MELODY
	t.formula = "sine"
	return t


## Best genre name for a level's (possibly loosely spelled) genre; "" -> the default genre.
static func resolve_genre(name: String) -> String:
	if name.is_empty():
		return DEFAULT_GENRE
	var want := _norm_name(name)
	for g: String in Harmonograph.GENRE_NAMES:
		if _norm_name(g) == want:
			return g
	for g: String in Harmonograph.GENRE_NAMES:
		var n := _norm_name(g)
		if n.begins_with(want) or want.begins_with(n):
			return g
	return DEFAULT_GENRE


static func _norm_name(x: String) -> String:
	var out := ""
	for ch: String in x.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


## Harmonograph scale name for a level's scale (case-insensitive); unknown -> "Minor".
static func resolve_scale(name: String) -> String:
	if Harmonograph.SCALES.has(name):
		return name
	var lower := name.to_lower()
	for k: String in Harmonograph.SCALE_NAMES:
		if k.to_lower() == lower:
			return k
	return "Minor"


func layer(track: int) -> LayerInfo:
	var l: _Layer = _layers[track]
	var info := LayerInfo.new()
	info.role = l.role
	info.formula = l.formula
	info.low = l.low
	info.high = l.high
	return info


func role_of(track: int) -> StringName:
	return _layers[track].role


## Chord in force at a master beat; `extension` 0 = triad, 1 = seventh (what the chord layer voices).
func chord_at(beat: float, extension: int = 0) -> AudioChordInfo:
	var b := maxf(0.0, beat)
	var st: HGState = _base.with_extension(extension) if extension != 0 else _base
	var c: HGChord = Harmonograph.chord_at(st, b)
	var index := posmod(int(floorf(b / chord_beats)), progression.size())
	return AudioChordInfo.make(index, c.degree, c.root, c.pcs)


## Progression index at a master beat (cheap; for MusicPulse.chord).
func chord_index(beat: float) -> int:
	if is_nan(beat) or is_inf(beat):
		return 0
	return posmod(int(floorf(maxf(0.0, beat) / chord_beats)), progression.size())


## MIDI note of scale degree `degree` (0-based, may exceed the scale length) in MIDI octave
## `octave` (C4 = 60).
func scale_midi(degree: int, octave: int) -> int:
	return 12 * (octave + 1) + Harmonograph.degree_midi_in(degree, root, scale)


## The MIDI note with pitch class `pc` closest to `around`.
static func nearest_with_pc(pc: int, around: int) -> int:
	var base := around - posmod(around - pc, 12)
	return base if around - base <= 6 else base + 12


## Notes of one layer in one master bar for a variant, sorted by beat. Each note belongs to exactly
## one bar (the bar containing its onset), so concatenating bars never duplicates notes. The
## returned array is shared with the cache: do not modify it.
func bar_notes(track: int, variant: AudioLayerVariant, bar: int) -> Array[AudioLayerNote]:
	if bar < 0:
		return []
	var key := "%d|%s|%d" % [track, variant.key(), bar]
	var hit: Variant = _cache.get(key)
	if hit != null:
		return hit
	var notes := _compile_bar(track, variant, bar)
	if _cache.size() > _CACHE_LIMIT:
		_cache.clear()
	_cache[key] = notes
	return notes


## Notes of one layer with onsets in [from, to).
func notes(track: int, variant: AudioLayerVariant, from: float, to: float) -> Array[AudioLayerNote]:
	var out: Array[AudioLayerNote] = []
	if to <= from:
		return out
	var bar := maxi(0, int(floorf(from / OD.BEATS_PER_BAR)))
	while float(bar * OD.BEATS_PER_BAR) < to:
		for n: AudioLayerNote in bar_notes(track, variant, bar):
			if n.beat >= from - 1e-9 and n.beat < to - 1e-9:
				out.append(n)
		bar += 1
	return out


# ───────────────────────────── construction ─────────────────────────────

func _prepare_layer(def: TrackMusicDef) -> _Layer:
	var l := _Layer.new()
	l.role = def.role if MusicRole.has(def.role) else MusicRole.MELODY
	l.formula = AudioFormulas.resolve_formula(l.role, def.formula)
	var split := AudioFormulas.split_params(l.formula, def.params)
	l.formula_params = split[0]
	l.layer_params = split[1]
	var shape: Dictionary = ROLE_SHAPES[l.role]
	var register := int(HGMath.js_round(clampf(l.layer_params.get("register", 0.0), -1.0, 1.0)))
	# Start the range on a scale root so the contour's midpoint sits on a stable degree.
	var fl: int = shape["floor"]
	l.low = fl + posmod(root - fl, 12) + 12 * register
	l.high = l.low + int(shape["span"])
	l.genre = resolve_genre(def.genre)
	return l


## Snap a step length to a power of two in [0.25, 4] so speed scaling stays on the master grid.
static func snap_rate(rate: float, fallback: float, has_rate: bool) -> float:
	if not has_rate or is_nan(rate) or is_inf(rate) or rate <= 0.0:
		return fallback
	return pow(2.0, HGMath.js_round(log(clampf(rate, 0.25, 4.0)) / log(2.0)))


func _channel_base(type: String) -> HGChannel:
	var c := Harmonograph.channel(_ENGINE_BASE_INDEX[type])
	c.id = 0
	c.active = true
	c.solo = false
	c.sum_enabled = false
	c.sum_gate = false
	c.sum_velocity = false
	c.variation = 0.0
	c.invert = false
	c.octave = 0.0
	c.speed = 1.0
	c.phase = 0.0
	c.micro = 0.0
	c.swing = 0.5
	c.repeated = "retrigger"
	return c


static func _lp(l: _Layer, key: String, fallback: float) -> float:
	return l.layer_params.get(key, fallback)


## The single engine channel for a pitched layer under `v`.
func _pitched_channel(l: _Layer, v: AudioLayerVariant) -> HGChannel:
	var shape: Dictionary = ROLE_SHAPES[l.role]
	var defs: Dictionary = AudioFormulas.ROLE_DEFAULTS[l.role]
	var c := _channel_base(shape["type"])
	var local_rate := snap_rate(_lp(l, "rate", 0.0), defs["rate"], l.layer_params.has("rate"))
	var pulses := int(HGMath.js_round(clampf(_lp(l, "pulses", defs["pulses"]), 1.0, 16.0)))
	var steps := int(HGMath.js_round(clampf(_lp(l, "steps", defs["steps"]), 1.0, 16.0)))
	pulses = mini(pulses, steps)
	var gravity := clampf(_lp(l, "gravity", defs["gravity"]), 0.0, 1.0)
	var contour := clampf(_lp(l, "contour", defs["contour"]), 0.0, 0.8)
	var cycle := HGMath.js_round(clampf(_lp(l, "cycle", 16.0), 4.0, 64.0))
	var phrase := HGMath.js_round(clampf(_lp(l, "phrase", 16.0), 4.0, 32.0))
	var accent: float = shape["accent"]
	var ghost: float = shape["ghost"]
	var palette: int = shape["palette"]
	var rate := local_rate / v.speed
	var gate_length: float = shape["gate_length"]
	var shape_name := "arch"
	var extension := 1
	var cadence := true
	var leap := 2.0

	c.formula = l.formula
	c.params = l.formula_params.duplicate()
	c.low = l.low
	c.high = l.high
	c.mode = "absolute"
	c.fold = "reflect"

	if v.dead:
		# MUSIC-08/09, death: fewer gated steps, softer, chord tones only, a short repetitive cycle.
		if steps == 1:
			steps = 2
		pulses = maxi(1, int(HGMath.js_round(pulses / 2.0)))
		gravity = 1.0
		palette = 0
		contour = maxf(contour, 0.35)
		cycle = maxf(4.0, HGMath.js_round(cycle / 4.0))
		phrase = 8.0
		accent = HGMath.js_round(accent * 0.65)
		ghost = HGMath.js_round(ghost * 0.65)
		extension = 0

	if v.drift > 0.0:
		# MUSIC-08/09, desync: the contour slips ahead of the rhythm and smooths toward the arch.
		# The rhythmic grid itself (gate on step n) is untouched so the layer stays in time.
		c.phase = HGMath.js_round(v.drift * 4.0)
		contour = minf(0.8, contour + 0.45 * v.drift)
		accent = HGMath.js_round(accent * (1.0 - 0.15 * v.drift))
		# A slight lateness (<= 18% of a step) gives the loose, slipping feel without flamming chords.
		c.micro = ((v.drift * 0.18 * rate) * _MS_PER_MINUTE) / bpm

	if v.transport == -1:
		c.retrograde = true

	if v.transport == 0:
		# Stopped tape: a sustained hold figure on a chord tone, re-voiced as the chords move.
		rate = 2.0 if l.role == MusicRole.MELODY else 4.0
		pulses = 1
		steps = 1
		gate_length = 1.0
		contour = 1.0
		shape_name = "flat"
		palette = 0
		gravity = 1.0
		cadence = false
		accent = HGMath.js_round(accent * 0.7)
		ghost = HGMath.js_round(ghost * 0.7)
		c.retrograde = false
		c.phase = 0.0
		c.micro = 0.0
		if l.role == MusicRole.BASS:
			c.root_anchor = true

	c.rate = rate
	c.gate = "euclid"
	c.gate_params = {"k": float(pulses), "n": float(steps), "rot": 0.0}
	c.gate_length = gate_length
	c.gravity = gravity
	c.contour = contour
	c.shape = shape_name
	c.palette = palette
	c.cycle = cycle
	c.phrase = phrase
	c.cadence = cadence
	c.leap = leap
	c.recovery = true
	c.velocity = "accent"
	c.velocity_params = {}
	c.accent = clampf(accent, 1.0, 127.0)
	c.ghost = clampf(minf(ghost, accent), 1.0, 127.0)
	if l.role == MusicRole.BASS:
		if v.transport != 0:
			c.root_anchor = false
		c.octave_pattern = 0.0
	if l.role == MusicRole.CHORD:
		c.extension = extension
		c.voicing_formula = false
		c.follow_contour = true
		c.minimal = true
		c.inversion = 0
		c.spread = 0.0
		c.strum = 0.0 if v.transport == 0 else 10.0
		c.strum_direction = 1.0
	return c


func _drum_lanes(l: _Layer, v: AudioLayerVariant) -> Array[_DrumLane]:
	var clap := _CLAP_GENRES.has(l.genre)
	var back_kind: StringName = DRUM_RIM if v.dead else (DRUM_CLAP if clap else DRUM_SNARE)
	var lanes: Array[_DrumLane] = [
		_DrumLane.make(0, DRUM_KICK, false, 0, 112.0, 76.0),
		_DrumLane.make(4 if clap else 1, back_kind, false, 1, 100.0, 62.0),
		_DrumLane.make(2, DRUM_HAT_CLOSED, true, 2, 84.0, 30.0),
		_DrumLane.make(5, DRUM_TOM if _TOM_GENRES.has(l.genre) else DRUM_PERC, false, 5, 78.0, 40.0),
	]
	if v.transport == 0:
		return lanes.slice(0, 1)
	# Death drops the perc lane entirely: the kit is reduced to its skeleton.
	if v.dead:
		return lanes.slice(0, 3)
	return lanes


func _drum_channel(l: _Layer, v: AudioLayerVariant, spec: _DrumLane) -> HGChannel:
	var c := _channel_base("Drums")
	var genre_index := Harmonograph.GENRE_NAMES.find(l.genre)
	var hold := v.transport == 0
	var density := clampf(_lp(l, "density", 1.0), 0.25, 2.0)
	var threshold := clampf(_lp(l, "threshold", 0.5), 0.15, 0.95)
	var vel_scale := 1.0
	if v.dead:
		density *= 0.5
		threshold = maxf(threshold, 0.8)
		vel_scale = 0.65
	if hold:
		# One soft kick per bar: a heartbeat under the held layers.
		density = 0.34
		vel_scale *= 0.6

	var use_formula := spec.signature and l.formula != "groove"
	var formula := l.formula if use_formula else "groove"
	var params: Dictionary[String, float]
	if use_formula:
		params = l.formula_params.duplicate()
	else:
		var raw: Dictionary[String, float] = {
			"genre": float(genre_index),
			"voice": float(spec.groove_voice),
			"density": density,
			"rotation": HGMath.js_round(v.drift * 2.0) if (spec.kind == DRUM_PERC or spec.kind == DRUM_TOM) else 0.0,
		}
		params = Harmonograph.clean_params("groove", raw)

	c.formula = formula
	c.params = params
	c.drum_lane = spec.lane
	c.drum_formula = true
	c.drum_velocity = "formula"
	c.drum_threshold = threshold if use_formula else 0.5
	# Hold ignores tape speed: a stopped tape has no tempo of its own.
	var drums_rate: float = AudioFormulas.ROLE_DEFAULTS[MusicRole.DRUMS]["rate"]
	c.rate = drums_rate if hold else snap_rate(_lp(l, "rate", 0.0), drums_rate, l.layer_params.has("rate")) / v.speed
	c.cycle = HGMath.js_round(clampf(_lp(l, "cycle", 16.0), 4.0, 64.0))
	c.phrase = 16.0
	c.gate_length = 0.5
	c.swing = 0.56 if _SWING_GENRES.has(l.genre) else 0.5
	var varies := spec.kind != DRUM_KICK and spec.kind != DRUM_SNARE and spec.kind != DRUM_CLAP and spec.kind != DRUM_RIM
	if varies and not hold:
		if v.drift > 0.0:
			c.phase = HGMath.js_round(v.drift * 4.0)
			c.micro = ((v.drift * 0.18 * c.rate) * _MS_PER_MINUTE) / bpm
		if v.transport == -1:
			c.retrograde = true
	var lanes: Array[HGLane] = []
	for j: int in c.lanes.size():
		var lane: HGLane = c.lanes[j].copy()
		lane.mute = j != spec.lane
		lane.gate = formula
		lane.params = params.duplicate()
		lane.accent = HGMath.js_round(clampf(spec.accent * vel_scale, 1.0, 127.0))
		lane.ghost = HGMath.js_round(clampf(spec.ghost * vel_scale, 1.0, 127.0))
		lane.micro = 0.0
		lanes.append(lane)
	c.lanes = lanes
	return c


# ───────────────────────────── compilation ─────────────────────────────

func _state_with(channel: HGChannel) -> HGState:
	var s := _base.with_extension(_base.extension)
	var cs: Array[HGChannel] = [channel]
	s.channels = cs
	return s


func _compile_bar(track: int, v: AudioLayerVariant, bar: int) -> Array[AudioLayerNote]:
	var l: _Layer = _layers[track]
	var start := float(bar * OD.BEATS_PER_BAR)
	var out: Array[AudioLayerNote] = []
	if l.role == MusicRole.DRUMS:
		for spec: _DrumLane in _drum_lanes(l, v):
			var ch := _drum_channel(l, v, spec)
			for e: HGNote in Harmonograph.compile_channel(_state_with(ch), 0, start, 1.0):
				var kind := spec.kind
				# The signature lane opens its hat on contour peaks that fall off the beat.
				var fv := e.formula_value if e.has_formula_value else 0.0
				if kind == DRUM_HAT_CLOSED and fv >= 0.92 and e.step % 2 == 1:
					kind = DRUM_HAT_OPEN
				out.append(AudioLayerNote.make(track, e.beat, minf(e.duration, 1.0), DRUM_NOTE[kind], e.velocity, DRUM_NORM[kind], e.step, kind))
	else:
		var ch := _pitched_channel(l, v)
		for e: HGNote in Harmonograph.compile_channel(_state_with(ch), 0, start, 1.0):
			# Clip at the next chord change: a note chosen under one chord never sustains into the next.
			var next_chord := (floorf(e.beat / chord_beats + 1e-9) + 1.0) * chord_beats
			var duration := maxf(0.02, minf(e.duration, next_chord - e.beat - 0.02))
			var norm := clampf(float(e.pitch - l.low) / float(maxi(1, l.high - l.low)), 0.0, 1.0)
			out.append(AudioLayerNote.make(track, e.beat, duration, e.pitch, e.velocity, norm, e.step))
	if l.role == MusicRole.CHORD:
		_strum_upward(out)
	out.sort_custom(_note_less)
	return out


static func _note_less(a: AudioLayerNote, b: AudioLayerNote) -> bool:
	if a.beat != b.beat:
		return a.beat < b.beat
	if a.pitch != b.pitch:
		return a.pitch < b.pitch
	return a.step < b.step


## The engine strums in voicing order, so a tone folded down below the range top would sound last.
## Re-deal the onsets of each chord so the strum always rises from the lowest tone.
static func _strum_upward(notes: Array[AudioLayerNote]) -> void:
	var by_step: Dictionary = {}
	var order: Array[int] = []
	for n: AudioLayerNote in notes:
		if not by_step.has(n.step):
			by_step[n.step] = []
			order.append(n.step)
		by_step[n.step].append(n)
	for st: int in order:
		var group: Array = by_step[st]
		if group.size() < 2:
			continue
		var beats: Array[float] = []
		var end := INF
		for n: AudioLayerNote in group:
			beats.append(n.beat)
			end = minf(end, n.beat + n.duration)
		beats.sort()
		group.sort_custom(func(a: AudioLayerNote, b: AudioLayerNote) -> bool: return a.pitch < b.pitch)
		for i: int in group.size():
			var n: AudioLayerNote = group[i]
			n.beat = beats[i]
			n.duration = maxf(0.02, end - n.beat)
