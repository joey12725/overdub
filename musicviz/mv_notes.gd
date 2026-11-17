class_name MVNotes
extends RefCounted
## The notes each cassette layer plays, compiled from the Harmonograph port exactly the way the
## music director does (port of prototype/src/audio/director.ts `pitchedChannel`, `drumLanes`,
## `drumChannel`, `compileBar`, `strumUpward`; MUSIC-01..04, MUSIC-08/09). The visualisers mark
## these notes; nothing here plays sound. Pure, deterministic, cached per (track, variant, bar).
##
## When the audio module's own director exists, the hub can route note queries to it instead
## (MVMusic.note_source) so the two can never disagree.

const MS_PER_MINUTE := 60000.0
const ENGINE_BASE_INDEX: Dictionary = {"Melody": 0, "Bass": 2, "Chord": 3, "Drums": 4}
const CLAP_GENRES: Array[String] = ["House", "Trap", "Jersey club", "Reggaeton", "Dancehall"]
const TOM_GENRES: Array[String] = ["Rock", "Funk / disco", "Boom bap", "Lo-fi 80", "Jungle"]
const SWING_GENRES: Array[String] = ["Lo-fi 80", "Boom bap", "Funk / disco"]
const CACHE_LIMIT := 768

var bpm: float = 120.0
var chord_beats: float = 8.0
var layers: Array[MVLayer] = []
var base: HGState = null
var _cache: Dictionary = {}


static func make(p_base: HGState, p_layers: Array[MVLayer], p_bpm: float, p_chord_beats: float) -> MVNotes:
	var n := MVNotes.new()
	n.base = p_base
	n.layers = p_layers
	n.bpm = p_bpm
	n.chord_beats = p_chord_beats
	return n


## Notes of layer `track` whose onsets fall in master bar `bar`, sorted by beat then pitch.
func bar_notes(track: int, v: MVVariant, bar: int) -> Array[MVNote]:
	var empty: Array[MVNote] = []
	if bar < 0 or track < 0 or track >= layers.size():
		return empty
	var key := "%d|%s|%d" % [track, v.key(), bar]
	if _cache.has(key):
		return _cache[key]
	var notes := _compile_bar(track, v, bar)
	if _cache.size() > CACHE_LIMIT:
		_cache.clear()
	_cache[key] = notes
	return notes


func clear_cache() -> void:
	_cache.clear()


# ───────────────────────────── channels ─────────────────────────────

func _channel_base(type: String) -> HGChannel:
	var c := Harmonograph.channel(int(ENGINE_BASE_INDEX[type]))
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


func _pitched_channel(l: MVLayer, v: MVVariant) -> HGChannel:
	var shape: Dictionary = MVLayer.ROLE_SHAPES[l.role]
	var c := _channel_base(shape["type"])
	var local_rate := l.local_rate
	var pulses := HGMath.js_round(clampf(l.lp("pulses", float(shape["pulses"])), 1.0, 16.0))
	var steps := HGMath.js_round(clampf(l.lp("steps", float(shape["steps"])), 1.0, 16.0))
	pulses = minf(pulses, steps)
	var gravity := clampf(l.lp("gravity", float(shape["gravity"])), 0.0, 1.0)
	var contour := clampf(l.lp("contour", float(shape["contour"])), 0.0, 0.8)
	var cycle := HGMath.js_round(clampf(l.lp("cycle", 16.0), 4.0, 64.0))
	var phrase := HGMath.js_round(clampf(l.lp("phrase", 16.0), 4.0, 32.0))
	var accent := float(shape["accent"])
	var ghost := float(shape["ghost"])
	var palette := int(shape["palette"])
	var rate := local_rate / v.speed
	var gate_length := float(shape["gate_length"])
	var shape_name := "arch"
	var extension := 1
	var cadence := true
	c.formula = l.formula
	c.params = l.formula_params.duplicate()
	c.low = l.low
	c.high = l.high
	c.mode = "absolute"
	c.fold = "reflect"
	if v.dead:
		if steps == 1.0:
			steps = 2.0
		pulses = maxf(1.0, HGMath.js_round(pulses / 2.0))
		gravity = 1.0
		palette = 0
		contour = maxf(contour, 0.35)
		cycle = maxf(4.0, HGMath.js_round(cycle / 4.0))
		phrase = 8.0
		accent = HGMath.js_round(accent * 0.65)
		ghost = HGMath.js_round(ghost * 0.65)
		extension = 0
	if v.drift > 0.0:
		c.phase = HGMath.js_round(v.drift * 4.0)
		contour = minf(0.8, contour + 0.45 * v.drift)
		accent = HGMath.js_round(accent * (1.0 - 0.15 * v.drift))
		c.micro = ((v.drift * 0.18 * rate) * MS_PER_MINUTE) / bpm
	if v.transport == -1:
		c.retrograde = true
	if v.transport == 0:
		rate = 2.0 if l.role == &"melody" else 4.0
		pulses = 1.0
		steps = 1.0
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
		if l.role == &"bass":
			c.root_anchor = true
	c.rate = rate
	c.gate = "euclid"
	c.gate_params = {"k": pulses, "n": steps, "rot": 0.0}
	c.gate_length = gate_length
	c.gravity = gravity
	c.contour = contour
	c.shape = shape_name
	c.palette = palette
	c.cycle = cycle
	c.phrase = phrase
	c.cadence = cadence
	c.leap = 2.0
	c.recovery = true
	c.velocity = "accent"
	c.velocity_params = {}
	c.accent = clampf(accent, 1.0, 127.0)
	c.ghost = clampf(minf(ghost, accent), 1.0, 127.0)
	if l.role == &"bass":
		if v.transport != 0:
			c.root_anchor = false
		c.octave_pattern = 0.0
	if l.role == &"chord":
		c.extension = extension
		c.voicing_formula = false
		c.follow_contour = true
		c.minimal = true
		c.inversion = 0
		c.spread = 0.0
		c.strum = 0.0 if v.transport == 0 else 10.0
		c.strum_direction = 1.0
	return c


## [lane, kind, signature, groove_voice, accent, ghost] per drum lane (director.ts drumLanes).
func _drum_lanes(l: MVLayer, v: MVVariant) -> Array:
	var clap := CLAP_GENRES.has(l.genre)
	var backbeat: StringName = MVNote.DRUM_RIM if v.dead else (MVNote.DRUM_CLAP if clap else MVNote.DRUM_SNARE)
	var lanes: Array = [
		[0, MVNote.DRUM_KICK, false, 0, 112.0, 76.0],
		[4 if clap else 1, backbeat, false, 1, 100.0, 62.0],
		[2, MVNote.DRUM_HAT_CLOSED, true, 2, 84.0, 30.0],
		[5, MVNote.DRUM_TOM if TOM_GENRES.has(l.genre) else MVNote.DRUM_PERC, false, 5, 78.0, 40.0],
	]
	if v.transport == 0:
		return lanes.slice(0, 1)
	if v.dead:
		return lanes.slice(0, 3)
	return lanes


func _drum_channel(l: MVLayer, v: MVVariant, spec: Array) -> HGChannel:
	var c := _channel_base("Drums")
	var kind: StringName = spec[1]
	var genre_index := Harmonograph.GENRE_NAMES.find(l.genre)
	var hold := v.transport == 0
	var density := clampf(l.lp("density", 1.0), 0.25, 2.0)
	var threshold := clampf(l.lp("threshold", 0.5), 0.15, 0.95)
	var vel_scale := 1.0
	if v.dead:
		density *= 0.5
		threshold = maxf(threshold, 0.8)
		vel_scale = 0.65
	if hold:
		density = 0.34
		vel_scale *= 0.6
	var use_formula: bool = spec[2] and l.formula != "groove"
	var formula := l.formula if use_formula else "groove"
	var params: Dictionary[String, float]
	if use_formula:
		params = l.formula_params.duplicate()
	else:
		var rot := HGMath.js_round(v.drift * 2.0) if (kind == MVNote.DRUM_PERC or kind == MVNote.DRUM_TOM) else 0.0
		var gp: Dictionary[String, float] = {"genre": float(genre_index), "voice": float(spec[3]), "density": density, "rotation": rot}
		params = Harmonograph.clean_params("groove", gp)
	c.formula = formula
	c.params = params
	c.drum_lane = int(spec[0])
	c.drum_formula = true
	c.drum_velocity = "formula"
	c.drum_threshold = threshold if use_formula else 0.5
	var drum_rate := float(MVLayer.ROLE_SHAPES[&"drums"]["rate"])
	c.rate = drum_rate if hold else l.local_rate / v.speed
	c.cycle = HGMath.js_round(clampf(l.lp("cycle", 16.0), 4.0, 64.0))
	c.phrase = 16.0
	c.gate_length = 0.5
	c.swing = 0.56 if SWING_GENRES.has(l.genre) else 0.5
	var varies := kind != MVNote.DRUM_KICK and kind != MVNote.DRUM_SNARE and kind != MVNote.DRUM_CLAP and kind != MVNote.DRUM_RIM
	if varies and not hold:
		if v.drift > 0.0:
			c.phase = HGMath.js_round(v.drift * 4.0)
			c.micro = ((v.drift * 0.18 * c.rate) * MS_PER_MINUTE) / bpm
		if v.transport == -1:
			c.retrograde = true
	for j: int in c.lanes.size():
		var lane := c.lanes[j]
		lane.mute = j != int(spec[0])
		lane.gate = formula
		lane.params = params.duplicate()
		lane.accent = HGMath.js_round(clampf(float(spec[4]) * vel_scale, 1.0, 127.0))
		lane.ghost = HGMath.js_round(clampf(float(spec[5]) * vel_scale, 1.0, 127.0))
		lane.micro = 0.0
	return c


# ───────────────────────────── compilation ─────────────────────────────

func _compile(channel: HGChannel, start: float) -> Array[HGNote]:
	var chs: Array[HGChannel] = [channel]
	base.channels = chs
	var out := Harmonograph.compile_channel(base, 0, start, 1.0)
	base.channels = []
	return out


func _compile_bar(track: int, v: MVVariant, bar: int) -> Array[MVNote]:
	var l := layers[track]
	var start := float(bar * OD.BEATS_PER_BAR)
	var out: Array[MVNote] = []
	if l.is_drums():
		for spec: Array in _drum_lanes(l, v):
			var ch := _drum_channel(l, v, spec)
			for e: HGNote in _compile(ch, start):
				var kind: StringName = spec[1]
				if kind == MVNote.DRUM_HAT_CLOSED and e.has_formula_value and e.formula_value >= 0.92 and posmod(e.step, 2) == 1:
					kind = MVNote.DRUM_HAT_OPEN
				var n := MVNote.new()
				n.track = track
				n.beat = e.beat
				n.duration = minf(e.duration, 1.0)
				n.pitch = int(MVNote.DRUM_NOTE[kind])
				n.velocity = e.velocity
				n.drum = kind
				n.norm = float(MVNote.DRUM_NORM[kind])
				n.step = e.step
				out.append(n)
	else:
		var ch := _pitched_channel(l, v)
		for e: HGNote in _compile(ch, start):
			var next_chord := (floorf(e.beat / chord_beats + 1e-9) + 1.0) * chord_beats
			var n := MVNote.new()
			n.track = track
			n.beat = e.beat
			n.duration = maxf(0.02, minf(e.duration, next_chord - e.beat - 0.02))
			n.pitch = e.pitch
			n.velocity = e.velocity
			n.norm = clampf(float(e.pitch - l.low) / maxf(1.0, float(l.high - l.low)), 0.0, 1.0)
			n.step = e.step
			out.append(n)
	if l.role == &"chord":
		_strum_upward(out)
	out.sort_custom(func(a: MVNote, b: MVNote) -> bool: return a.beat < b.beat or (a.beat == b.beat and a.pitch < b.pitch))
	return out


## director.ts strumUpward: re-deal each chord's onsets so the strum rises from the lowest tone.
static func _strum_upward(notes: Array[MVNote]) -> void:
	var by_step: Dictionary = {}
	var order: Array[int] = []
	for n: MVNote in notes:
		if not by_step.has(n.step):
			by_step[n.step] = []
			order.append(n.step)
		(by_step[n.step] as Array).append(n)
	for s: int in order:
		var group: Array = by_step[s]
		if group.size() < 2:
			continue
		var beats: Array[float] = []
		var end := INF
		for n: MVNote in group:
			beats.append(n.beat)
			end = minf(end, n.beat + n.duration)
		beats.sort()
		group.sort_custom(func(a: MVNote, b: MVNote) -> bool: return a.pitch < b.pitch)
		for i: int in group.size():
			var n: MVNote = group[i]
			n.beat = beats[i]
			n.duration = maxf(0.02, end - n.beat)
