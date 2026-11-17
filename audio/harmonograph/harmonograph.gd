class_name Harmonograph
extends RefCounted
## GDScript port of the Harmonograph generative music engine (prototype/src/vendor/harmonograph.js,
## the game creator's own engine; MUSIC-01..03). Pure and deterministic: no clock, no randomness,
## safe on any thread (the sequence caches are mutex-guarded).
##
## Typical use (what the music director does):
##   var s := Harmonograph.make_state()           # key/scale/progression defaults, no channels
##   s.root = 9; s.scale = "Dorian"; s.progression = [0, 5, 3, 4]; s.chord_rate = 8.0
##   var c := Harmonograph.channel(0)              # a preset voice (0 Lead .. 7 Pad)
##   c.set_formula("lorenz"); c.rate = 0.5; s.channels = [c]
##   var notes := Harmonograph.compile_channel(s, 0, 0.0, 1.0)   # one bar of HGNote
##
## Ported: the formula catalogue (HGFormulas: all 66 formulas, value / normal / period), scales and
## scale-degree mapping with chord gravity and palettes, fold modes and leap recovery, chord
## progressions / formula chords / qualities / borrowed chords / PLR (chord_at), gate and velocity
## formulas, Sum terms with every operator, speed / phase / retrograde / variation / invert
## transforms, drum lanes (Euclidean and genre grooves, Boolean lane logic, drum-formula lanes),
## the build roll, compile_channel and compile_timeline (queued channel toggles, build release).
## Not ported (host / editor features): section snapshots and recall, the live `command` set (except
## `validate`, `apply_genre`), presets, playPads, clip writing, the control catalogue, importState
## migration.
##
## Fidelity: tests/audio/test_harmonograph_goldens.gd replays goldens written by the JS engine
## (prototype/scripts/export-hg-goldens.cjs).

const NOTES: Array[String] = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
const COLORS: Array[String] = ["#F2D16B", "#A992E8", "#58C4DD", "#E07FC4", "#9BCB6E", "#F0A15E", "#EE7D6E", "#3FB8A6"]
## Scale name -> semitone offsets from the root (engine SCALES, same order).
const SCALE_NAMES: Array[String] = [
	"Major", "Minor", "Dorian", "Mixolydian", "Lydian", "Phrygian", "Locrian", "Harmonic Minor",
	"Melodic Minor", "Minor Pentatonic", "Major Pentatonic", "Whole Tone", "Chromatic",
]
const SCALES: Dictionary = {
	"Major": [0, 2, 4, 5, 7, 9, 11], "Minor": [0, 2, 3, 5, 7, 8, 10], "Dorian": [0, 2, 3, 5, 7, 9, 10],
	"Mixolydian": [0, 2, 4, 5, 7, 9, 10], "Lydian": [0, 2, 4, 6, 7, 9, 11], "Phrygian": [0, 1, 3, 5, 7, 8, 10],
	"Locrian": [0, 1, 3, 5, 6, 8, 10], "Harmonic Minor": [0, 2, 3, 5, 7, 8, 11],
	"Melodic Minor": [0, 2, 3, 5, 7, 9, 11], "Minor Pentatonic": [0, 3, 5, 7, 10],
	"Major Pentatonic": [0, 2, 4, 7, 9], "Whole Tone": [0, 2, 4, 6, 8, 10],
	"Chromatic": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
}
const GENRE_NAMES: Array[String] = HGFormulas.GENRE_NAMES
const GENRES: Dictionary = HGFormulas.GENRES

const _PRESET_TYPES: Array[String] = ["Melody", "Melody", "Bass", "Chord", "Drums", "Melody", "Melody", "Melody"]
const _PRESET_FORMULAS: Array[String] = ["fibonacci", "collatz", "sine", "extension", "euclid", "thue", "rose", "lorenz"]
const _PRESET_NAMES: Array[String] = ["Lead", "Fall", "808", "Keys", "Kit", "Counter", "Arp", "Pad"]
const _CHORD_TONES: Array[int] = [0, 2, 4, 6, 8, 10, 12]
const _EXT_NAMES: Array[String] = ["", "7", "9", "11", "13"]
const _QUALITY_INTERVALS: Dictionary = {
	"major": [0, 4, 7, 11, 14, 17, 21], "minor": [0, 3, 7, 10, 14, 17, 21],
	"dominant": [0, 4, 7, 10, 14, 17, 21], "diminished": [0, 3, 6, 9, 14, 17, 20],
}
const _MAJOR_EXT: Array[int] = [0, 4, 7, 11, 14, 17, 21]
const _MINOR_EXT: Array[int] = [0, 3, 7, 10, 14, 17, 21]
const _DOM_EXT: Array[int] = [0, 4, 7, 10, 14, 17, 21]
## Borrowed chords: name -> [semitones above the key root, intervals] ("sus" is degree-relative).
const _BORROW: Dictionary = {
	"♭II": [1, [0, 4, 7]], "♭III": [3, [0, 4, 7]], "♭VI": [8, [0, 4, 7]], "♭VII": [10, [0, 4, 7]],
	"iv": [5, [0, 3, 7]], "V/V": [2, [0, 4, 7, 10]], "V/vi": [4, [0, 4, 7, 10]], "TT": [1, [0, 4, 7, 10]],
}


# ───────────────────────────── formulas ─────────────────────────────

## Every formula (66), in engine order, with parameter metadata.
static func catalogue() -> Array[HGFormula]:
	return HGFormulas.catalogue()


static func formula_ids() -> Array[String]:
	return HGFormulas.ids()


static func get_formula(id: String) -> HGFormula:
	return HGFormulas.get_formula(id)


static func has_formula(id: String) -> bool:
	return HGFormulas.has_formula(id)


static func defaults(id: String) -> Dictionary[String, float]:
	return HGFormulas.defaults(id)


static func clean_params(id: String, params: Dictionary[String, float] = {}) -> Dictionary[String, float]:
	return HGFormulas.clean_params(id, params)


## Raw formula value at step n (pure; for visualisations). See HGFormulas.value.
static func value(id: String, n: float, params: Dictionary[String, float] = {}, P: float = 16.0) -> float:
	return HGFormulas.value(id, n, params, P)


## Formula value mapped to 0..1. See HGFormulas.normal.
static func normal(id: String, n: float, params: Dictionary[String, float] = {}, P: float = 16.0) -> float:
	return HGFormulas.normal(id, n, params, P)


## Period in steps, 0.0 when the engine knows none (null). See HGFormulas.period.
static func period(id: String, params: Dictionary[String, float] = {}, P: float = 16.0) -> float:
	return HGFormulas.period(id, params, P)


static func euclid(step: float, k: float, n: float, rot: float = 0.0) -> float:
	return HGFormulas.euclid(step, k, n, rot)


static func groove_pattern(p: Dictionary[String, float]) -> HGFormulas.GroovePattern:
	return HGFormulas.groove_pattern(HGFormulas.clean_params("groove", p))


# ───────────────────────────── state ─────────────────────────────

## Engine `channel(i)`: preset voice i (0 Lead/fibonacci, 1 Fall/collatz step mode, 2 808 bass/sine,
## 3 Keys chord/extension, 4 Kit drums/euclid, 5 Counter/thue, 6 Arp/rose, 7 Pad/lorenz). Indices
## outside 0..7 reuse preset i mod 8 but keep id = i.
static func channel(i: int) -> HGChannel:
	var pi: int = posmod(i, 8)
	var c := HGChannel.new()
	var type: String = _PRESET_TYPES[pi]
	var formula: String = _PRESET_FORMULAS[pi]
	c.id = i
	c.name = _PRESET_NAMES[pi]
	c.color = COLORS[pi]
	c.type = type
	c.formula = formula
	c.params = defaults(formula)
	c.active = pi < 5
	c.has_queued = false
	c.solo = false
	c.rate = 1.0 if type == "Bass" else (4.0 if type == "Chord" else 0.25)
	c.cycle = 16.0
	c.phase = 0.0
	c.swing = 0.5
	c.micro = 0.0
	c.gate = "euclid"
	c.gate_params = {"k": 16.0, "n": 16.0, "rot": 0.0}
	c.gate_length = 0.72
	c.velocity = "accent"
	c.velocity_params = {}
	c.accent = 100.0
	c.ghost = 45.0
	c.repeated = "retrigger"
	c.low = 33.0 if type == "Bass" else 57.0
	c.high = 57.0 if type == "Bass" else 81.0
	c.gravity = 0.4
	c.palette = 2
	c.mode = "step" if pi == 1 else "absolute"
	c.fold = "reflect"
	c.leap = 2.0
	c.recovery = true
	c.contour = 0.0
	c.shape = "arch"
	c.phrase = 16.0
	c.cadence = true
	c.variation = 0.0
	c.variation_param = "m"
	c.octave = 0.0
	c.glide = 0.0
	c.glide_method = "cc"
	c.root_anchor = true
	c.octave_pattern = 0.0
	c.invert = false
	c.retrograde = false
	c.speed = 1.0
	c.sum_enabled = false
	c.sum_gate = false
	c.sum_velocity = false
	c.sum_threshold = 0.5
	c.sum_mode = "contour"
	c.sum_mod = 7.0
	c.ratio_snap = true
	var terms: Array[HGTerm] = []
	for j: int in 8:
		var t := HGTerm.new()
		t.amplitude = 1.0 if j == 0 else (0.5 if j == 1 else 0.0)
		t.formula = "sine"
		t.params = defaults("sine")
		t.ratio = float(j * 2 + 1)
		t.phase = 0.0
		t.operator = "+"
		t.source = -1
		terms.append(t)
	c.terms = terms
	c.extension = 0
	c.inversion = 0
	c.minimal = true
	c.spread = 0.0
	c.strum = 0.0
	c.strum_direction = 1.0
	c.voicing_formula = true
	c.follow_contour = false
	c.drum_lane = -1
	c.drum_formula = false
	c.drum_threshold = 0.5
	c.drum_velocity = "legacy"
	c.has_pitch_root = false
	c.has_octave_radius = false
	var lanes: Array[HGLane] = [
		HGLane.make("Kick", 36, 4), HGLane.make("Snare", 38, 2, 16, 4), HGLane.make("Closed hat", 42, 8),
		HGLane.make("Open hat", 46, 3, 16, 2), HGLane.make("Clap", 39, 2, 16, 4), HGLane.make("Perc", 45, 5, 8),
		HGLane.make("Rim", 37, 3, 16, 1), HGLane.make("Crash", 49, 1, 32),
	]
	for j: int in lanes.size():
		lanes[j].mute = j > 3
	c.lanes = lanes
	c.destination = "Live track " + str(i + 1)
	c.cc_enabled = false
	c.cc_number = 74.0
	c.cc_low = 0.0
	c.cc_high = 127.0
	c.cc_formula = "sine"
	return c


## Engine `initialState()` with its eight preset channels (sections are not modelled).
static func initial_state() -> HGState:
	var s := make_state()
	var cs: Array[HGChannel] = []
	for i: int in 8:
		cs.append(channel(i))
	s.channels = cs
	return s


## The engine's initial global state with no channels: A minor, progression i–VI–III–VII
## ([0, 5, 2, 6]) one chord per bar, 132 bpm.
static func make_state() -> HGState:
	return HGState.new()


## Engine `genre` command: lanes 0..3 (kick, snare, closed hat, open hat) of channel `index` become
## the genre's Euclidean patterns and are unmuted. Returns false for an unknown genre.
static func apply_genre(s: HGState, index: int, genre: String) -> bool:
	if not GENRES.has(genre) or index < 0 or index >= s.channels.size():
		return false
	var g: Array = GENRES[genre]
	var c: HGChannel = s.channels[index]
	for i: int in mini(4, c.lanes.size()):
		var l: HGLane = c.lanes[i]
		l.gate = "euclid"
		l.params = {"k": float(g[i][0]), "n": float(g[i][1]), "rot": float(g[i][2])}
		l.mute = false
	return true


## The engine's state validation (tail of `command`): clamps every global and channel setting into
## range and cleans formula parameters, in place. Compiling does not require it; use it on states
## built from untrusted data.
static func validate(s: HGState) -> HGState:
	s.root = int(HGMath.js_round(HGMath.clamp_js(s.root, 0, 11)))
	s.tempo = HGMath.clamp_js(s.tempo, 20, 999)
	s.extension = int(HGMath.js_round(HGMath.clamp_js(s.extension, 0, 4)))
	s.selected = int(HGMath.js_round(HGMath.clamp_js(s.selected, 0, maxi(0, s.channels.size() - 1))))
	s.chord_rate = HGMath.clamp_js(s.chord_rate, 0.25, 64)
	s.degree = int(HGMath.js_round(HGMath.clamp_js(s.degree, 0, 6)))
	if not SCALES.has(s.scale):
		s.scale = "Minor"
	s.build.q = HGMath.clamp_js(s.build.q, 0.05, 0.99)
	s.build.bars = HGMath.clamp_js(s.build.bars, 1, 64)
	s.build.hits = HGMath.js_round(HGMath.clamp_js(s.build.hits, 1, 256))
	s.build.gap = HGMath.clamp_js(s.build.gap, 0.0625, 16)
	for c: HGChannel in s.channels:
		if c.type == "Drums" and c.drum_lane >= 0 and c.drum_lane < c.lanes.size():
			c.formula = c.lanes[c.drum_lane].gate
			c.params = c.lanes[c.drum_lane].params.duplicate()
	for c: HGChannel in s.channels:
		c.low = HGMath.js_round(HGMath.clamp_js(c.low, 0, 126))
		c.high = HGMath.js_round(HGMath.clamp_js(c.high, c.low + 1.0, 127))
		c.params = clean_params(c.formula, c.params)
		c.cycle = HGMath.js_round(HGMath.clamp_js(c.cycle, 1, 4096))
		c.rate = HGMath.clamp_js(c.rate, 0.0625, 16)
		c.phrase = HGMath.js_round(HGMath.clamp_js(c.phrase, 1, 256))
		c.gravity = HGMath.clamp_js(c.gravity, 0, 1)
		c.contour = HGMath.clamp_js(c.contour, 0, 1)
		c.gate_length = HGMath.clamp_js(c.gate_length, 0.05, 4)
		c.swing = HGMath.clamp_js(c.swing, 0.5, 0.75)
		c.strum = HGMath.clamp_js(c.strum, 0, 200)
		c.speed = HGMath.clamp_js(c.speed, 1.0 / 64.0, 64)
		c.sum_threshold = HGMath.clamp_js(c.sum_threshold, 0, 1)
		c.sum_mod = HGMath.js_round(HGMath.clamp_js(c.sum_mod, 2, 128))
		c.accent = HGMath.clamp_js(c.accent, 1, 127)
		c.ghost = HGMath.clamp_js(c.ghost, 1, 127)
		if c.terms.size() > 8:
			c.terms.resize(8)
		for t: HGTerm in c.terms:
			t.amplitude = HGMath.clamp_js(t.amplitude, -2, 2)
			t.ratio = HGMath.clamp_js(t.ratio, 0.125, 16)
			t.phase = HGMath.clamp_js(t.phase, 0, 1)
			t.source = int(HGMath.js_round(HGMath.clamp_js(t.source, -1, s.channels.size() - 1)))
	return s


# ───────────────────────────── scales and harmony ─────────────────────────────

## Semitone offsets of a scale (`SCALES[name] || SCALES.Minor`).
static func scale_intervals(scale_name: String) -> Array:
	return SCALES.get(scale_name, SCALES["Minor"])


## Engine `degreeMidi(d, s)`: pitch (in octave 0, root at 0..11) of scale degree d (0-based, any
## integer; each scale length up is an octave).
static func degree_midi(d: int, s: HGState) -> int:
	return degree_midi_in(d, s.root, s.scale)


static func degree_midi_in(d: int, root: int, scale_name: String) -> int:
	var sc: Array = scale_intervals(scale_name)
	var n: int = sc.size()
	# Math.floor(d / len) and mod(d, len) for possibly negative d.
	return root + 12 * floori(float(d) / float(n)) + int(sc[posmod(d, n)])


## Engine `nearestPC(p, pcs)`: the pitch class of `pcs` circularly nearest p (first wins ties).
static func nearest_pc(p: int, pcs: Array[int]) -> int:
	var best: int = pcs[0]
	for i: int in range(1, pcs.size()):
		var b: int = pcs[i]
		var da: int = mini(posmod(p - best, 12), posmod(best - p, 12))
		var db: int = mini(posmod(p - b, 12), posmod(b - p, 12))
		if not (da <= db):
			best = b
	return best


## Engine `chordAt(s, beat)`: the chord in force at `beat` on the state's clock.
## chord_source "progression": progression[floor(beat / chord_rate) mod len] (an empty progression
## keeps `degree`; the engine would produce NaN pitch classes); "formula": chord_formula's value at
## floor(beat / chord_rate) indexes `allowed` ("plr" alternates Neo-Riemannian moves on the degree
## chord); "pads": `degree` (or chord_root with escape). Then quality, borrowed (escape only),
## shift, and — without escape — every tone snapped into the scale.
static func chord_at(s: HGState, beat: float) -> HGChord:
	var sc: Array = scale_intervals(s.scale)
	var L: int = sc.size()
	var degree: int = s.degree
	if s.chord_source == "progression" and not s.progression.is_empty():
		degree = s.progression[int(HGMath.mod(floorf(beat / s.chord_rate), float(s.progression.size())))]
	if s.chord_source == "formula" and s.chord_formula != "plr":
		var n: float = floorf(beat / s.chord_rate)
		var a: Array[int] = s.allowed if not s.allowed.is_empty() else ([0] as Array[int])
		var pick: float = HGMath.mod(floorf(value(s.chord_formula, n, s.chord_params)), float(a.size()))
		degree = a[int(pick)] if is_finite(pick) else a[0]
	var count: int = clampi(3 + s.extension, 0, _CHORD_TONES.size())
	var pcs: Array[int] = []
	for i: int in count:
		pcs.append(posmod(degree_midi(degree + _CHORD_TONES[i], s), 12))
	var root: int = posmod(degree_midi(degree, s), 12)
	if s.borrowed != "" and s.escape and (_BORROW.has(s.borrowed) or s.borrowed == "sus"):
		var shift_root: int
		var ints: Array
		if s.borrowed == "sus":
			shift_root = int(sc[posmod(degree, L)])
			ints = [0, 5, 7]
		else:
			shift_root = int(_BORROW[s.borrowed][0])
			ints = _BORROW[s.borrowed][1]
		root = posmod(s.root + shift_root, 12)
		pcs = []
		for p: Variant in ints:
			pcs.append(posmod(root + int(p), 12))
	if s.quality != "diatonic":
		var qi: Array = _QUALITY_INTERVALS.get(s.quality, [0, 4, 7])
		pcs = []
		for i: int in mini(count, qi.size()):
			pcs.append(posmod(root + int(qi[i]), 12))
	if s.chord_source == "formula" and s.chord_formula == "plr" and HGMath.truthy(fmod(floorf(beat / s.chord_rate), 2.0)):
		var minor: bool = posmod(pcs[1] - root, 12) == 3
		var move: int = int(clean_params("plr", s.chord_params)["move"])
		root = posmod(root + ([0, -4, 3] if minor else [0, 4, -3])[move], 12)
		var src: Array[int] = _MAJOR_EXT if minor else _MINOR_EXT
		pcs = []
		for i: int in count:
			pcs.append(posmod(root + src[i], 12))
	if s.chord_source == "pads" and s.has_chord_root and s.escape:
		root = posmod(s.chord_root, 12)
		var src: Array[int] = _MINOR_EXT if s.quality == "minor" else _DOM_EXT
		pcs = []
		for i: int in count:
			pcs.append(posmod(root + src[i], 12))
	if s.shift:
		if pcs.size() > 1:
			pcs[1] = posmod(root + 5, 12)
		if pcs.size() > 3:
			pcs[3] = posmod(root + 10, 12)
	# Explicit chromatic escape controls whether requested borrowed/altered voices may leave the scale.
	if not s.escape:
		var scale_pcs: Array[int] = []
		for v: Variant in sc:
			scale_pcs.append(posmod(s.root + int(v), 12))
		for i: int in pcs.size():
			pcs[i] = nearest_pc(pcs[i], scale_pcs)
	var out := HGChord.new()
	out.degree = degree
	out.root = root
	var unique: Array[int] = []
	for p: int in pcs:
		if not unique.has(p):
			unique.append(p)
	out.pcs = unique
	var minor_name: bool = pcs.size() > 1 and posmod(pcs[1] - root, 12) == 3
	out.name = NOTES[root] + ("m" if minor_name else "") + (_EXT_NAMES[s.extension] if s.extension >= 0 and s.extension < _EXT_NAMES.size() else "")
	return out


## Engine `scaleNotes(c, s)`: every MIDI note of the scale inside the channel range (with octave).
static func scale_notes(c: HGChannel, s: HGState) -> Array[int]:
	var out: Array[int] = []
	for v: float in _scale_notes(c, s):
		out.append(int(v))
	return out


static func _scale_notes(c: HGChannel, s: HGState) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var sc: Array = scale_intervals(s.scale)
	var top: float = HGMath.clamp_js(c.high + c.octave * 12.0, 0.0, 127.0)
	var n: float = ceilf(HGMath.clamp_js(c.low + c.octave * 12.0, 0.0, 127.0))
	while n <= top:
		if sc.has(int(HGMath.mod(n - float(s.root), 12.0))):
			out.append(n)
		n += 1.0
	return out


## Engine `fold(d, len, mode, previous, octaveSize)`: brings degree d back into [0, len).
## "wrap" modulo; "nearest" the same scale step (d mod octave_size) closest to previous; anything
## else reflects off both ends.
static func fold(d: float, length: int, mode: String, previous: float, octave_size: int = 7) -> float:
	if length <= 1:
		return 0.0
	var len: float = float(length)
	if mode == "wrap":
		return HGMath.mod(d, len)
	if mode == "nearest":
		var k: float = HGMath.mod(d, float(octave_size))
		var best: float = NAN
		var found: bool = false
		for i: int in length:
			if float(i % octave_size) == k:
				if not found:
					best = float(i)
					found = true
				elif not (absf(best - previous) <= absf(float(i) - previous)):
					best = float(i)
		return best if found else HGMath.clamp_js(d, 0.0, len - 1.0)
	var t: float = HGMath.mod(d, 2.0 * (len - 1.0))
	return t if t < len else 2.0 * (len - 1.0) - t


# ───────────────────────────── contour, sum, gates ─────────────────────────────

## Engine `rawValue(c, n, s)`: the channel's 0..1 contour at step n after its transforms
## (at = n·speed + phase; retrograde reflects inside the cycle; phrase variation; Sum; invert).
static func raw_value(c: HGChannel, n: float, s: HGState, visited: Array[int] = []) -> float:
	var at: float = n * c.speed + c.phase
	if c.retrograde:
		at = c.cycle - 1.0 - HGMath.mod(at, c.cycle)
	var p: Dictionary[String, float] = c.params.duplicate()
	var vi: float = HGMath.mod(floorf(n / c.phrase), 4.0)
	var variant: float = [0.0, 1.0, 0.0, 2.0][int(vi)] if is_finite(vi) else NAN
	if HGMath.truthy(c.variation) and p.has(c.variation_param):
		p[c.variation_param] += variant * c.variation
	var v: float = sum_value(c, at, s, visited) if c.sum_enabled else normal(c.formula, at, p, c.cycle)
	return 1.0 - v if c.invert else v


## Engine `sumValue(c, n, s)`: the channel's Sum of terms at step n, 0..1. "contour" mode: terms are
## bipolar normals combined by their operators and averaged by |amplitude|; "integer" mode: integer
## term values combined, reduced mod sum_mod. A channel reached again through term sources falls
## back to its plain formula.
static func sum_value(c: HGChannel, n: float, s: HGState, visited: Array[int] = []) -> float:
	if visited.has(c.id):
		return normal(c.formula, n, c.params, c.cycle)
	visited = visited.duplicate()
	visited.append(c.id)
	var out: float = 0.0
	var weight: float = 0.0
	var first: bool = true
	var integer: bool = c.sum_mode == "integer"
	for j: int in mini(8, c.terms.size()):
		var t: HGTerm = c.terms[j]
		if not HGMath.truthy(t.amplitude):
			continue
		var at: float = n * t.ratio + t.phase * c.cycle
		var source: HGChannel = s.channels[t.source] if (t.source >= 0 and t.source < s.channels.size()) else null
		var v: float = _term_sample(c, t, source, at, s, visited, integer)
		if not integer:
			v = v * 2.0 - 1.0
		var a: float = t.amplitude
		var op: String = t.operator
		if first or op == "+":
			out += a * v
		elif op == "×":
			out *= a * v
		elif op == "∘":
			if integer:
				out = a * _term_sample(c, t, source, out, s, visited, integer)
			else:
				out = a * (_term_sample(c, t, source, (out + 1.0) * c.cycle / 2.0, s, visited, integer) * 2.0 - 1.0)
		elif op == "mod":
			out = HGMath.mod(out + a * v, c.sum_mod)
		elif op == "interleave":
			if HGMath.truthy(fmod(n, 2.0)):
				out = a * v
		elif op == "mask":
			out = out if _term_sample(c, t, source, at, s, visited, integer) > (0.0 if integer else 0.5) else 0.0
		elif op == "max":
			out = HGMath.js_max(out, a * v)
		elif op == "min":
			out = HGMath.js_min(out, a * v)
		elif op == "AND":
			out = 1.0 if (out > 0.0 and v > 0.0) else (0.0 if integer else -1.0)
		elif op == "OR":
			out = 1.0 if (out > 0.0 or v > 0.0) else (0.0 if integer else -1.0)
		elif op == "XOR":
			out = 1.0 if ((out > 0.0) != (v > 0.0)) else (0.0 if integer else -1.0)
		weight += absf(a)
		first = false
	if not HGMath.truthy(weight):
		return 0.5
	if c.sum_mode == "integer":
		return HGMath.mod(HGMath.js_round(out), c.sum_mod) / maxf(1.0, c.sum_mod - 1.0)
	return HGMath.clamp_js((out / weight + 1.0) / 2.0, 0.0, 1.0)


## The engine's `sample(q)` closure inside sumValue.
static func _term_sample(c: HGChannel, t: HGTerm, source: HGChannel, q: float, s: HGState, visited: Array[int], integer: bool) -> float:
	if not integer:
		return raw_value(source, q, s, visited) if source != null else normal(t.formula, q, t.params, c.cycle)
	if source != null and source.sum_enabled:
		return HGMath.js_round(raw_value(source, q, s, visited) * (c.sum_mod - 1.0))
	# `source?.formula || t.formula`, `source?.params || t.params`, `source?.cycle || c.cycle`
	var id: String = source.formula if (source != null and source.formula != "") else t.formula
	var p: Dictionary[String, float] = source.params if source != null else t.params
	var cycle: float = source.cycle if (source != null and HGMath.truthy(source.cycle)) else c.cycle
	if HGFormulas.formula_or_default(id).integer:
		return value(id, q, p, cycle)
	return HGMath.js_round(normal(id, q, p, cycle) * (c.sum_mod - 1.0))


## Engine `gateValue(id, n, p)`: 1 where the formula value (P = 16) is positive.
static func gate_value(id: String, n: float, p: Dictionary[String, float]) -> float:
	return 1.0 if value(id, n, p) > 0.0 else 0.0


## Engine `laneHit(l, n, lanes)`: the lane's gate at n (anticipation reads 2 steps ahead, approach
## also fires a step early), combined with lane `other` by AND / OR / XOR / NOT.
static func lane_hit(l: HGLane, n: float, lanes: Array[HGLane]) -> bool:
	var at: float = n + (2.0 if l.anticipation else 0.0)
	var hit: bool = gate_value(l.gate, at, l.params) > 0.0
	if l.approach:
		hit = hit or gate_value(l.gate, at + 1.0, l.params) > 0.0
	if l.logic != "none":
		var b: HGLane = lanes[int(HGMath.clamp_js(l.other, 0.0, float(lanes.size() - 1)))]
		var other: bool = gate_value(b.gate, at, b.params) > 0.0
		if l.logic == "AND":
			hit = hit and other
		if l.logic == "OR":
			hit = hit or other
		if l.logic == "XOR":
			hit = hit != other
		if l.logic == "NOT":
			hit = hit and not other
	return hit


## Engine `vel(c, n)` for anything with ghost/accent/velocity formula/params/phrase (channel or
## lane; a lane has no phrase, so P = 16).
static func velocity_at(ghost: float, accent: float, formula: String, params: Dictionary[String, float], phrase: float, n: float) -> float:
	var P: float = phrase if HGMath.truthy(phrase) else 16.0
	return HGMath.js_round(HGMath.clamp_js(ghost + (accent - ghost) * normal(formula, n, params, P), 1.0, 127.0))


## Engine `buildProgress(s, beat)`: 0..1 through a held or released build.
static func build_progress(s: HGState, beat: float) -> float:
	if not s.build.active():
		return 0.0
	return HGMath.clamp_js((beat - s.build.start) / (s.build.bars * 4.0), 0.0, 1.0)


# ───────────────────────────── compile ─────────────────────────────

## Engine `compileChannel(s, index, startBeat, bars)`: the notes of channel `index` with onsets in
## [start_beat, start_beat + 4·bars), sorted by beat then pitch. Deterministic seeking: the
## step-mode walk restarts at each phrase boundary, so compiling bar k alone equals compiling bars
## 0..k and keeping bar k. Inactive (or soloed-out) channels compile to nothing.
static func compile_channel(s: HGState, index: int, start_beat: float = 0.0, bars: float = 4.0) -> Array[HGNote]:
	var c: HGChannel = s.channels[index]
	var end_beat: float = start_beat + bars * 4.0
	var events: Array[HGNote] = []
	var notes: PackedFloat64Array = _scale_notes(c, s)
	var rate: float = HGMath.clamp_js(c.rate, 0.0625, 16.0)
	var start_n: float = maxf(0.0, floorf(start_beat / rate))
	var end_n: float = ceilf(end_beat / rate)
	var drums: bool = c.type == "Drums"
	if not drums and notes.is_empty():
		return events
	# Phrase-local integration provides deterministic seeking without a hidden random-walk state.
	var previous: float = 0.0
	var prev_leap: float = 0.0
	var last_chord := PackedFloat64Array()
	var begin_n: float = floorf(start_n / maxf(1.0, c.phrase)) * c.phrase
	var solo: bool = false
	for ch: HGChannel in s.channels:
		if ch.solo:
			solo = true
	var enabled: bool = c.active and (not solo or c.solo)
	var scale_len: int = scale_intervals(s.scale).size()
	var len_notes: float = float(notes.size())
	var ms_to_beats: float = s.tempo / 60000.0
	var build: HGBuild = s.build
	var n: float = begin_n - 1.0
	while true:
		n += 1.0
		if not (n < end_n):
			break
		if fmod(n, c.phrase) == 0.0:
			last_chord = PackedFloat64Array()
		var beat: float = n * rate
		var now: HGChord = chord_at(s, beat)
		var ph: float = HGMath.mod(n, c.phrase) / maxf(1.0, c.phrase - 1.0)
		var shape: float = sin(PI * ph) if c.shape == "arch" else (ph if c.shape == "ramp" else 0.5)
		var v: float = raw_value(c, n, s) * (1.0 - c.contour) + shape * c.contour
		var degree: float
		if c.mode == "step":
			if fmod(n, c.phrase) == 0.0:
				previous = floorf(len_notes / 2.0)
				prev_leap = 0.0
			var jump: float = HGMath.js_round((v * 2.0 - 1.0) * c.leap)
			if c.recovery and absf(prev_leap) > 2.0:
				jump = -HGMath.sign_js(prev_leap)
			degree = previous + jump
			prev_leap = jump
		else:
			degree = HGMath.js_round(v * (len_notes - 1.0))
		if c.fold == "drift":
			degree += HGMath.js_round(sin(n / c.phrase / 4.0 * TAU) * 3.0)
		degree = fold(degree, notes.size(), c.fold, previous, scale_len)
		previous = degree
		var weight: float = 1.0 if fmod(n, 16.0) == 0.0 else (0.75 if fmod(n, 4.0) == 0.0 else (0.5 if fmod(n, 2.0) == 0.0 else 0.25))
		var allowed: PackedFloat64Array = notes
		if c.palette == 0 or (c.gravity > 0.0 and weight >= 1.0 - c.gravity * 0.75):
			allowed = PackedFloat64Array()
			for p: float in notes:
				if now.pcs.has(int(fmod(p, 12.0))):
					allowed.append(p)
		elif c.palette == 1:
			var pent: Array[int] = [0, 2, 4, 7, 9]
			if s.scale.to_lower().contains("minor"):
				pent = [0, 3, 5, 7, 10]
			allowed = PackedFloat64Array()
			for p: float in notes:
				if pent.has(int(HGMath.mod(p - float(s.root), 12.0))):
					allowed.append(p)
		# `notes[degree]`: undefined (NaN here) only for a drum channel with an empty range.
		var pitch: float = HGMath.at_or(notes, degree, NAN)
		if not allowed.is_empty():
			pitch = _nearest(allowed, pitch)
		if c.palette == 3 and s.escape and fmod(n, 2.0) == 1.0:
			pitch = HGMath.clamp_js(pitch + (1.0 if fmod(n, 4.0) == 1.0 else -1.0), c.low, c.high)
		if c.cadence and fmod(n, c.phrase) == c.phrase - 1.0:
			var roots := _with_pc(notes, now.root)
			if not roots.is_empty():
				pitch = _nearest(roots, pitch)
		var delay: float = ((c.swing - 0.5) * rate * 2.0 if HGMath.truthy(fmod(n, 2.0)) else 0.0) + c.micro * s.tempo / 60000.0
		var building: bool = build.active() and beat >= build.start and (not build.has_end or beat < build.end)
		if drums:
			for li: int in c.lanes.size():
				var l: HGLane = c.lanes[li]
				if (c.drum_lane >= 0 and li != c.drum_lane) or l.mute or (building and build.mute_kick and li == 0):
					continue
				var ll: HGLane = l
				if building and build.density and li == 2 and l.gate == "euclid":
					ll = l.copy()
					var k0: float = l.params.get("k", NAN)
					ll.params["k"] = HGMath.js_round(k0 + (l.params.get("n", NAN) - k0) * build_progress(s, beat))
				var onset: float = beat + delay + l.micro * s.tempo / 60000.0
				if c.drum_formula and c.drum_lane >= 0:
					var fv: float = raw_value(c, n, s)
					var hit: bool = fv > 0.0 and fv >= HGMath.clamp_js(c.drum_threshold, 0.0, 1.0)
					if hit:
						var dvel: float
						if c.drum_velocity == "formula":
							dvel = HGMath.js_round(HGMath.clamp_js(ll.ghost + (ll.accent - ll.ghost) * fv, 1.0, 127.0))
						elif c.drum_velocity == "fixed":
							dvel = HGMath.js_round(HGMath.clamp_js(ll.accent, 1.0, 127.0))
						else:
							dvel = velocity_at(ll.ghost, ll.accent, ll.velocity, ll.velocity_params, 0.0, n)
						var e := _append(events, enabled, start_beat, end_beat, index, float(l.note), n, onset, rate * c.gate_length, dvel)
						if e != null:
							e.lane = li
							e.sound = l.name
							e.formula_value = fv
							e.has_formula_value = true
					continue
				if lane_hit(ll, n, c.lanes) and (not c.sum_gate or sum_value(c, n, s) >= c.sum_threshold):
					var lvel: float = (l.ghost + (l.accent - l.ghost) * sum_value(c, n, s)) if c.sum_velocity else velocity_at(l.ghost, l.accent, l.velocity, l.velocity_params, 0.0, n)
					var e := _append(events, enabled, start_beat, end_beat, index, float(l.note), n, onset, rate * c.gate_length, lvel)
					if e != null:
						e.lane = li
						e.sound = l.name
		elif (sum_value(c, n, s) >= c.sum_threshold) if c.sum_gate else (gate_value(c.gate, n, c.gate_params) > 0.0):
			if c.type == "Bass":
				if building and build.mute_bass:
					continue
				if c.root_anchor:
					var roots := _with_pc(notes, now.root)
					if not roots.is_empty():
						pitch = roots[0]
				if HGMath.truthy(c.octave_pattern) and euclid(n, c.octave_pattern, 8.0) > 0.0 and notes.has(pitch + 12.0):
					pitch += 12.0
			var nvel: float
			if c.type == "Chord":
				var ext: int = int(floorf(v * 4.0)) if c.voicing_formula else c.extension
				var cs: HGChord = chord_at(s.with_extension(ext), beat)
				var ps := PackedFloat64Array()
				for pc: int in cs.pcs:
					ps.append(c.low + HGMath.mod(float(pc) - c.low, 12.0))
				ps.sort()
				if c.follow_contour:
					var shift: float = 12.0 * HGMath.js_round((pitch - ps[0]) / 12.0)
					for i: int in ps.size():
						ps[i] = ps[i] + shift
				var inv: float = HGMath.mod(float(c.inversion + s.inversion) + (floorf(v * 3.0) if c.voicing_formula else 0.0), maxf(1.0, float(ps.size())))
				var r: float = 0.0
				while r < inv:
					var lowest: float = ps[0]
					ps.remove_at(0)
					ps.append(lowest + 12.0)
					r += 1.0
				for i: int in ps.size():
					ps[i] = HGMath.clamp_js(ps[i] + (HGMath.js_round(c.spread) * 12.0 if i % 2 == 1 else 0.0) + 12.0 * float(s.chord_octave), 0.0, 127.0)
				if c.minimal and not c.follow_contour and not last_chord.is_empty():
					for i: int in ps.size():
						var p: float = ps[i]
						var target: float = last_chord[i % last_chord.size()]
						var cand := PackedFloat64Array()
						for q: float in [p - 12.0, p, p + 12.0]:
							if q >= c.low and q <= c.high:
								cand.append(q)
						if not cand.is_empty():
							ps[i] = _nearest(cand, target)
				for i: int in ps.size():
					var p: float = ps[i]
					while p > c.high and p - 12.0 >= c.low:
						p -= 12.0
					while p < c.low and p + 12.0 <= c.high:
						p += 12.0
					var bounded: float = HGMath.clamp_js(p, c.low, c.high)
					if not s.escape and not notes.has(bounded):
						bounded = _nearest(notes, bounded)
					ps[i] = bounded
				var uniq := PackedFloat64Array()
				for p: float in ps:
					if not uniq.has(p):
						uniq.append(p)
				ps = uniq
				last_chord = ps
				if c.strum_direction < 0.0:
					ps.reverse()
				nvel = HGMath.js_round(c.ghost + (c.accent - c.ghost) * sum_value(c, n, s)) if c.sum_velocity else velocity_at(c.ghost, c.accent, c.velocity, c.velocity_params, c.phrase, n)
				for i: int in ps.size():
					_append(events, enabled, start_beat, end_beat, index, ps[i], n, beat + delay + float(i) * c.strum * s.tempo / 60000.0, rate * c.gate_length, nvel)
			else:
				nvel = HGMath.js_round(c.ghost + (c.accent - c.ghost) * sum_value(c, n, s)) if c.sum_velocity else velocity_at(c.ghost, c.accent, c.velocity, c.velocity_params, c.phrase, n)
				_append(events, enabled, start_beat, end_beat, index, pitch, n, beat + delay, rate * c.gate_length, nvel)
	if drums and (c.drum_lane < 0 or c.drum_lane == 1) and build.active():
		# The build's Zeno snare roll: hit k at start + min(L, gap·(1 − q^k) / (1 − q)).
		var L: float = build.bars * 4.0
		var k: float = 0.0
		while k < build.hits:
			var t: float = build.start + minf(L, build.gap * (1.0 - pow(build.q, k)) / (1.0 - build.q))
			if build.has_end and t >= build.end:
				break
			var e := _append(events, enabled, start_beat, end_beat, index, 38.0, k, t, 0.04, 70.0 + HGMath.js_round(50.0 * HGMath.clamp_js((t - build.start) / L, 0.0, 1.0)))
			if e != null:
				e.lane = 1
				e.sound = c.lanes[1].name if c.lanes.size() > 1 else "Snare"
				e.roll = true
			k += 1.0
	# `events.sort((a, b) => a.beat - b.beat || a.pitch - b.pitch)`: JS sort is stable, Godot's is
	# not, so equal (beat, pitch) keep their generation order through an explicit index tie-break.
	var order: Array[int] = []
	for i: int in events.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ea: HGNote = events[a]
		var eb: HGNote = events[b]
		if ea.beat != eb.beat:
			return ea.beat < eb.beat
		if ea.pitch != eb.pitch:
			return ea.pitch < eb.pitch
		return a < b)
	var out: Array[HGNote] = []
	var last_by_pitch: Dictionary[int, HGNote] = {}
	for i: int in order:
		var e: HGNote = events[i]
		var prev: HGNote = last_by_pitch.get(e.pitch, null)
		if not drums and prev != null and e.beat <= prev.beat + prev.duration + rate * (1.0 - c.gate_length) + 1e-6:
			if c.repeated == "tie":
				prev.duration = e.beat + e.duration - prev.beat
				continue
			if c.repeated == "suppress":
				continue
			prev.duration = minf(prev.duration, maxf(0.01, e.beat - prev.beat - 0.002))
		out.append(e)
		last_by_pitch[e.pitch] = e
	return out


## The engine's `append`: keeps the event when its onset is in [start, end) (1e-8 slack) and the
## channel is enabled; pitch and velocity are rounded and clamped, duration at least 0.01.
static func _append(events: Array[HGNote], enabled: bool, start_beat: float, end_beat: float, index: int, pitch: float, n: float, beat: float, duration: float, velocity: float) -> HGNote:
	if not (beat >= start_beat - 1e-8 and beat < end_beat - 1e-8 and enabled):
		return null
	var e := HGNote.new()
	e.channel = index
	e.pitch = int(HGMath.js_round(HGMath.clamp_js(pitch, 0.0, 127.0)))
	e.velocity = int(HGMath.js_round(HGMath.clamp_js(velocity, 1.0, 127.0)))
	e.beat = beat
	e.duration = maxf(0.01, duration)
	e.step = int(n)
	events.append(e)
	return e


## `arr.reduce((a, b) => Math.abs(a - x) <= Math.abs(b - x) ? a : b)`: first nearest (a NaN x
## makes every comparison false, so the last element wins, as in JS).
static func _nearest(arr: PackedFloat64Array, x: float) -> float:
	var best: float = arr[0]
	for i: int in range(1, arr.size()):
		var b: float = arr[i]
		if not (absf(best - x) <= absf(b - x)):
			best = b
	return best


static func _with_pc(notes: PackedFloat64Array, pc: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for p: float in notes:
		if fmod(p, 12.0) == float(pc):
			out.append(p)
	return out


## Engine `boundary(s, beat)`: the next launch point after `beat` for the state's quantize.
static func boundary(s: HGState, beat: float) -> float:
	var q: float = 1.0 if s.quantize == "beat" else (s.phrase / 4.0 if s.quantize == "phrase" else 4.0)
	return (floorf(beat / q + 1e-6) + 1.0) * q


## Engine `applyPending(s, beat)` without section recall: applies queued channel toggles due at
## `beat` and ends a released build whose end has passed. Mutates and returns s.
static func apply_pending(s: HGState, beat: float) -> HGState:
	for c: HGChannel in s.channels:
		if c.has_queued and beat >= c.queued_beat:
			c.active = c.queued_active
			c.has_queued = false
	# `beat >= s.build.end` with end null compares against 0, as in JS.
	if s.build.released and beat >= (s.build.end if s.build.has_end else 0.0):
		s.build.held = false
		s.build.released = false
		s.build.has_end = false
		s.build.end = 0.0
	return s


## Engine `compileTimeline(s, index, start, bars)`: like compile_channel, but resolves queued
## channel toggles and a build release that fall inside the window first, compiling each segment
## with the state in force and clipping notes at the segment end. `s` is not modified.
static func compile_timeline(s: HGState, index: int, start: float = 0.0, bars: float = 4.0) -> Array[HGNote]:
	var end_beat: float = start + bars * 4.0
	var work: HGState = s.copy()
	var cuts := PackedFloat64Array([start, end_beat])
	for c: HGChannel in work.channels:
		if c.has_queued and c.queued_beat > start and c.queued_beat < end_beat:
			cuts.append(c.queued_beat)
	var build_end: float = work.build.end if work.build.has_end else 0.0
	if work.build.released and build_end > start and build_end < end_beat:
		cuts.append(build_end)
	var points := PackedFloat64Array()
	for v: float in cuts:
		if not points.has(v):
			points.append(v)
	points.sort()
	var out: Array[HGNote] = []
	for i: int in points.size() - 1:
		apply_pending(work, points[i])
		for e: HGNote in compile_channel(work, index, points[i], (points[i + 1] - points[i]) / 4.0):
			var x := e.copy()
			x.duration = minf(e.duration, points[i + 1] - e.beat)
			out.append(x)
	return out


# ───────────────────────────── periods of sums ─────────────────────────────

## Engine `sumPeriod(c, s)`: the period of the channel's Sum in steps, 0.0 when unknown (null).
static func sum_period(c: HGChannel, s: HGState, seen: Array[int] = []) -> float:
	if seen.has(c.id):
		return 0.0
	seen = seen.duplicate()
	seen.append(c.id)
	var result: float = 1.0
	for t: HGTerm in c.terms:
		if not HGMath.truthy(t.amplitude):
			continue
		var source: HGChannel = s.channels[t.source] if (t.source >= 0 and t.source < s.channels.size()) else null
		var p: float
		if source != null:
			p = sum_period(source, s, seen) if source.sum_enabled else period(source.formula, source.params, source.cycle)
		else:
			p = period(t.formula, t.params, c.cycle)
		if not HGMath.truthy(p) or not is_finite(t.ratio) or not HGMath.truthy(t.ratio):
			return 0.0
		var q: float = p / absf(t.ratio)
		var den: float = 1.0
		while den <= 64.0 and absf(q * den - HGMath.js_round(q * den)) > 1e-6:
			den += 1.0
		if den > 64.0:
			return 0.0
		result = HGMath.lcm(result, HGMath.js_round(q * den))
		if result >= 1048576.0:
			return 0.0
	return result


## Engine `ratioChoices(c, t, s)`: term ratios 1..16 whose period divides the channel phrase.
static func ratio_choices(c: HGChannel, t: HGTerm, s: HGState) -> Array[int]:
	var all: Array[int] = []
	for k: int in range(1, 17):
		all.append(k)
	var source: HGChannel = s.channels[t.source] if (t.source >= 0 and t.source < s.channels.size()) else null
	var p: float
	if source != null:
		p = sum_period(source, s) if source.sum_enabled else period(source.formula, source.params, source.cycle)
	else:
		p = period(t.formula, t.params, c.cycle)
	if not HGMath.truthy(p) or p != floorf(p):
		return all
	var choices: Array[int] = []
	for k: int in all:
		if fmod(c.phrase, p / HGMath.gcd(p, float(k))) == 0.0:
			choices.append(k)
	return choices if not choices.is_empty() else all
