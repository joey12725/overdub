class_name MVLayer
extends RefCounted
## One cassette's music layer as the visualisers see it (MUSIC-02, MUSIC-12): the resolved formula,
## its engine-cleaned parameters, the layer-shaping keys and the derived step grid. Node-free and
## deterministic. Mirrors prototype/src/audio/director.ts `prepareLayer` + formulas.ts
## `resolveFormula` / `splitParams`, so what is drawn is the function the audio actually plays.
##
## Time model (director.ts): a layer's step length on the MASTER clock is `local_rate / speed`, so
## the step index at master beat b is `n = b * speed / local_rate` — the LOCAL step. contour(at)
## is the engine's 0..1 formula contour at (fractional) step `at`, cached on a sub-step grid.

## Sub-samples per step of the cached contour table.
const SUB := 4
## The contour table never grows past this many samples (16k steps); beyond it values wrap.
const MAX_SAMPLES := 65536

const CONTOUR_CATEGORIES: Array[String] = [HGFormula.CATEGORY_NUMBER, HGFormula.CATEGORY_DYNAMICAL, HGFormula.CATEGORY_GEOMETRY]
const FALLBACK_FORMULA: Dictionary = {&"melody": "sine", &"bass": "triangle", &"chord": "sine", &"drums": "euclid"}
const LAYER_KEYS: Array[String] = ["rate", "register", "pulses", "steps", "gravity", "contour", "cycle", "phrase", "threshold", "density"]

## formulas.ts ROLE_DEFAULTS merged with director.ts ROLE_SHAPES (palette, floor, span, gate length,
## accent, ghost).
const ROLE_SHAPES: Dictionary = {
	&"melody": {"type": "Melody", "rate": 0.5, "pulses": 5, "steps": 8, "gravity": 0.5, "contour": 0.15, "palette": 2, "floor": 55, "span": 19, "gate_length": 0.8, "accent": 96, "ghost": 50},
	&"bass": {"type": "Bass", "rate": 0.5, "pulses": 3, "steps": 8, "gravity": 0.8, "contour": 0.1, "palette": 0, "floor": 31, "span": 17, "gate_length": 0.85, "accent": 104, "ghost": 64},
	&"chord": {"type": "Chord", "rate": 2.0, "pulses": 1, "steps": 1, "gravity": 0.5, "contour": 0.2, "palette": 2, "floor": 50, "span": 19, "gate_length": 0.92, "accent": 82, "ghost": 58},
	&"drums": {"type": "Drums", "rate": 0.25, "pulses": 1, "steps": 1, "gravity": 0.0, "contour": 0.0, "palette": 2, "floor": 36, "span": 12, "gate_length": 0.5, "accent": 110, "ghost": 40},
}
const DEFAULT_GENRE := "Lo-fi 80"

## Cassette index 0..3.
var track: int = 0
## MusicRole.* (bass / drums / melody / chord).
var role: StringName = &"melody"
## The formula actually played (falls back like the audio does for unknown / unsuitable ids).
var formula: String = "sine"
## Engine-cleaned formula parameters.
var formula_params: Dictionary[String, float] = {}
## Layer-shaping keys from TrackMusicDef.params (rate, register, pulses, ...).
var layer_params: Dictionary[String, float] = {}
## Resolved Harmonograph genre name (drums).
var genre: String = DEFAULT_GENRE
## MIDI range of the layer.
var low: int = 60
var high: int = 79
## Beats per step at 1x tape speed (power of two in 0.25..4).
var local_rate: float = 0.5
## Period P of wave formulas / retrograde reflection, in steps.
var cycle: int = 16
var phrase: int = 16
## Euclidean gate E(pulses, steps) of a pitched layer.
var pulses: int = 5
var steps: int = 8

## Derived data caches owned by visualisers (e.g. epicycle harmonics), keyed by the user.
var cache: Dictionary = {}

var _table: PackedFloat32Array = PackedFloat32Array()
var _filled: int = 0
var _curve: PackedVector2Array = PackedVector2Array()
var _period_signal: PackedFloat32Array = PackedFloat32Array()
var _period: int = 0


static func make(p_track: int, def: TrackMusicDef, root: int) -> MVLayer:
	var l := MVLayer.new()
	l.track = p_track
	l.role = def.role if ROLE_SHAPES.has(def.role) else &"melody"
	l.formula = resolve_formula(l.role, def.formula)
	var raw: Dictionary[String, float] = {}
	for k: String in def.params.keys():
		var v: float = def.params[k]
		if not is_finite(v):
			continue
		if LAYER_KEYS.has(k):
			l.layer_params[k] = v
		else:
			raw[k] = v
	l.formula_params = Harmonograph.clean_params(l.formula, raw)
	l.genre = resolve_genre(def.genre)
	var shape: Dictionary = ROLE_SHAPES[l.role]
	var register := int(HGMath.js_round(clampf(l.lp("register", 0.0), -1.0, 1.0)))
	var floor_note: int = shape["floor"]
	l.low = floor_note + posmod(root - floor_note, 12) + 12 * register
	l.high = l.low + int(shape["span"])
	l.local_rate = snap_rate(l.layer_params.get("rate", NAN), float(shape["rate"]))
	l.cycle = int(HGMath.js_round(clampf(l.lp("cycle", 16.0), 4.0, 64.0)))
	l.phrase = int(HGMath.js_round(clampf(l.lp("phrase", 16.0), 4.0, 32.0)))
	l.pulses = int(HGMath.js_round(clampf(l.lp("pulses", float(shape["pulses"])), 1.0, 16.0)))
	l.steps = int(HGMath.js_round(clampf(l.lp("steps", float(shape["steps"])), 1.0, 16.0)))
	l.pulses = mini(l.pulses, l.steps)
	return l


## A layer parameter or its default.
func lp(key: String, def: float) -> float:
	return layer_params.get(key, def)


func is_drums() -> bool:
	return role == &"drums"


## formulas.ts isMusicFormulaAllowed + resolveFormula.
static func resolve_formula(p_role: StringName, id: String) -> String:
	if Harmonograph.has_formula(id):
		var f := Harmonograph.get_formula(id)
		if id == "groove":
			if p_role == &"drums":
				return id
		elif CONTOUR_CATEGORIES.has(f.category) or (p_role == &"drums" and f.category == HGFormula.CATEGORY_RHYTHM):
			return id
	return FALLBACK_FORMULA.get(p_role, "sine")


## director.ts resolveGenre.
static func resolve_genre(name: String) -> String:
	if name.is_empty():
		return DEFAULT_GENRE
	var want := _norm(name)
	for g: String in Harmonograph.GENRE_NAMES:
		if _norm(g) == want:
			return g
	for g: String in Harmonograph.GENRE_NAMES:
		var ng := _norm(g)
		if ng.begins_with(want) or want.begins_with(ng):
			return g
	return DEFAULT_GENRE


static func _norm(s: String) -> String:
	var out := ""
	for ch: String in s.to_lower():
		var c := ch.unicode_at(0)
		if (c >= 97 and c <= 122) or (c >= 48 and c <= 57):
			out += ch
	return out


## director.ts snapRate: a power of two in [0.25, 4]; NaN / non-positive -> fallback.
static func snap_rate(rate: float, fallback: float) -> float:
	if not is_finite(rate) or rate <= 0.0:
		return fallback
	return pow(2.0, HGMath.js_round(log(clampf(rate, 0.25, 4.0)) / log(2.0)))


## Local step index at master beat `beat` for a tape at `speed` (director.ts time model).
func step_at(beat: float, speed: float) -> float:
	return beat * speed / local_rate


## The engine contour (0..1) at fractional step `at` (at < 0 is wrapped into the cycle, like the
## engine). Cached on a SUB-per-step grid and linearly interpolated.
func contour(at: float) -> float:
	if at < 0.0:
		at = fposmod(at, float(cycle))
	var x := at * SUB
	var i := int(floor(x))
	if i + 1 >= MAX_SAMPLES:
		i = posmod(i, MAX_SAMPLES - 2)
	_fill(i + 2)
	var f := x - floorf(x)
	return lerpf(_table[i], _table[i + 1], f)


## Raw sample of the contour at exact step `at` (no cache; used by tests).
func contour_exact(at: float) -> float:
	return Harmonograph.normal(formula, at, formula_params, float(cycle))


## Makes sure the cached contour covers steps 0..`max_step` (for batch readers like
## MVTrack.sample_values, which index the table directly).
func ensure_steps(max_step: float) -> void:
	_fill(mini(MAX_SAMPLES, int(ceil(maxf(0.0, max_step) * SUB)) + 3))


## The cached contour as points (local step, value) — one per table sample — so a drawer can take a
## slice and map it to the screen with one affine transform (no per-point script work). Rebuilt
## when the table has grown.
func step_curve() -> PackedVector2Array:
	if _curve.size() != _filled:
		var start := _curve.size()
		_curve.resize(_filled)
		for j: int in range(start, _filled):
			_curve[j] = Vector2(float(j) / SUB, _table[j])
	return _curve


## The cached contour table (SUB samples per step) — read-only for batch readers.
func table() -> PackedFloat32Array:
	return _table


func _fill(n: int) -> void:
	if n <= _filled:
		return
	var want := mini(MAX_SAMPLES, maxi(maxi(n, _filled * 2), 256))
	_table.resize(want)
	for j: int in range(_filled, want):
		_table[j] = Harmonograph.normal(formula, float(j) / SUB, formula_params, float(cycle))
	_filled = want


## Period, in steps, that one "turn" of this layer covers (Shape / Epicycles): the engine period
## when it knows a sensible one (2..64), else the layer cycle.
func period_steps() -> int:
	if _period > 0:
		return _period
	var p := Harmonograph.period(formula, formula_params, float(cycle))
	var ip := int(HGMath.js_round(p))
	_period = ip if (ip >= 2 and ip <= 64 and is_equal_approx(p, float(ip))) else cycle
	return _period


## One period of the contour sampled at integer steps 0..period_steps()-1.
func period_signal() -> PackedFloat32Array:
	if _period_signal.is_empty():
		var n := period_steps()
		_period_signal.resize(n)
		for i: int in n:
			_period_signal[i] = contour(float(i))
	return _period_signal


## Whether the Euclidean gate of a pitched layer sounds on local step `step` (drums: always).
func gate_hit(step: int) -> bool:
	if is_drums():
		return true
	return Harmonograph.euclid(float(step), float(pulses), float(steps), 0.0) > 0.0
