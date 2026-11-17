class_name HGFormulas
extends RefCounted
## The Harmonograph formula catalogue: every formula of prototype/src/vendor/harmonograph.js with
## its parameters, `value`, `normal`, `period`, the memoised sequence streams and the drum-genre
## grooves. Pure and deterministic. Normally reached through `Harmonograph.*`.
##
## Port notes. JS numbers are doubles, so every computation here is in `float` (integers are
## integral doubles), with the same operation order as the engine so results match bit for bit
## where only + - * / sqrt are involved. Spots that depend on JS-specific semantics call HGMath and
## are commented. Transcendentals (sin, cos, exp, pow) come from the platform C library here and
## from V8 there; they can differ in the last bit (see tests/audio/test_harmonograph_goldens.gd).

# Dispatch indices, in catalogue order (the order the engine `add()`s them).
enum {
	F_FIBONACCI, F_LUCAS, F_TRIBONACCI, F_SQUARES, F_TRIANGULAR, F_CUBES, F_LINEAR, F_POWERS,
	F_COLLATZ, F_RECAMAN, F_NORGARD, F_POPCOUNT, F_DIGITSUM, F_THUE, F_RULER, F_STERN, F_KOLAKOSKI,
	F_BEATTY, F_DIGITS, F_PRIMES, F_PRIMEGAPS, F_DIVISORS, F_TOTIENT, F_VDC, F_GRAY, F_BYTEBEAT,
	F_LOGISTIC, F_CIRCLE, F_TENT, F_SINEMAP, F_HENON, F_LORENZ, F_ROSSLER, F_CA, F_LSYSTEM,
	F_SINE, F_TRIANGLE, F_SAW, F_SQUARE, F_LISSAJOUS, F_ROSE, F_SUPERFORMULA, F_SPIROGRAPH,
	F_POLYGON, F_VERTICES, F_POLYNOMIAL, F_TIMES, F_CARDIOID, F_ASTROID, F_SPIRAL, F_BUTTERFLY,
	F_HARMONOGRAPH, F_GROOVE, F_EUCLID, F_MODGATE, F_STAIRCASE, F_BIT, F_POLYMETER, F_ZENO,
	F_CIRCLECHORD, F_EXTENSION, F_VOICELEAD, F_SPREAD, F_PLR, F_ACCENT, F_CRESCENDO,
	F_COUNT,
}

## Drum genres: name -> four lanes (kick, snare, closed hat, open hat) of [k, n, rotation].
## Order matters: the `groove` formula's `genre` parameter indexes GENRE_NAMES.
const GENRE_NAMES: Array[String] = [
	"House", "Lo-fi 80", "Boom bap", "Trap", "Drill", "Jersey club", "Dancehall", "Reggaeton",
	"Jungle", "Rock", "Funk / disco",
]
const GENRES: Dictionary = {
	"House": [[4, 16, 0], [2, 16, 4], [8, 16, 2], [4, 16, 2]],
	"Lo-fi 80": [[3, 16, 0], [2, 16, 4], [7, 16, 0], [3, 16, 2]],
	"Boom bap": [[3, 16, 0], [2, 16, 4], [8, 16, 0], [2, 16, 7]],
	"Trap": [[3, 16, 0], [1, 16, 8], [12, 16, 0], [3, 16, 3]],
	"Drill": [[5, 32, 0], [2, 32, 8], [11, 32, 0], [3, 16, 5]],
	"Jersey club": [[5, 16, 0], [4, 16, 2], [8, 16, 0], [3, 8, 0]],
	"Dancehall": [[3, 8, 0], [2, 16, 4], [8, 16, 0], [5, 16, 3]],
	"Reggaeton": [[4, 16, 0], [5, 16, 2], [8, 16, 0], [3, 8, 0]],
	"Jungle": [[7, 32, 0], [4, 32, 4], [14, 32, 0], [5, 16, 2]],
	"Rock": [[2, 8, 0], [2, 8, 2], [8, 16, 0], [1, 16, 0]],
	"Funk / disco": [[4, 16, 0], [2, 16, 4], [13, 16, 0], [5, 16, 2]],
}

## Fixed-point digit strings (100 decimal places) for the `digits` formula: pi, e, sqrt 2, phi.
const DIGIT_STRINGS: Array[String] = [
	"31415926535897932384626433832795028841971693993751058209749445923078164062862089986280348253421170679",
	"27182818284590452353602874713526624977572470936999595749669676277240766303535475945713821785251664274",
	"14142135623730950488016887242096980785696718753769480731766797379907324784621070388503875343276415727",
	"16180339887498948482045868343656381177203091798057628621354486227052604628189024497072072041893911374",
]

static var _catalogue: Array[HGFormula] = []
static var _by_id: Dictionary[String, HGFormula] = {}
static var _lock: Mutex = Mutex.new()
## sequence(): finite lists (digits, collatz, lsystem) memoised by key (engine `cache`, cleared
## past 256 entries) and endless streams with their generator state (engine `streams`, at most 16,
## oldest evicted first). Eviction never changes values, only cost.
static var _memo: Dictionary[String, PackedFloat64Array] = {}
static var _streams: Dictionary[String, _Stream] = {}


# ───────────────────────────── catalogue ─────────────────────────────

## Every formula, in engine order (66).
static func catalogue() -> Array[HGFormula]:
	_ensure()
	return _catalogue


static func ids() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for f: HGFormula in _catalogue:
		out.append(f.id)
	return out


static func has_formula(id: String) -> bool:
	_ensure()
	return _by_id.has(id)


## The formula with this id, or null.
static func get_formula(id: String) -> HGFormula:
	_ensure()
	return _by_id.get(id, null)


## Engine `byId[id] || byId.fibonacci`: unknown ids fall back to fibonacci everywhere.
static func formula_or_default(id: String) -> HGFormula:
	_ensure()
	var f: HGFormula = _by_id.get(id, null)
	return f if f != null else _by_id["fibonacci"]


## Default parameters of a formula (engine `defaults`).
static func defaults(id: String) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	for p: HGParamDef in formula_or_default(id).params:
		out[p.key] = p.value
	return out


## Engine `cleanParams`: every declared key, missing ones defaulted, clamped to range (non-finite
## -> min, see HGMath.clamp_js), integer (step 1) parameters rounded with JS Math.round. Keys the
## formula does not declare are dropped.
static func clean_params(id: String, params: Dictionary[String, float] = {}) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	for p: HGParamDef in formula_or_default(id).params:
		# `params[p.key] ?? p.value`: only a missing key takes the default.
		var raw: float = params[p.key] if params.has(p.key) else p.value
		var v: float = HGMath.clamp_js(raw, p.min_value, p.max_value)
		out[p.key] = HGMath.js_round(v) if p.step == 1.0 else v
	return out


static func _ensure() -> void:
	if not _catalogue.is_empty():
		return
	_lock.lock()
	if _catalogue.is_empty():
		_build()
	_lock.unlock()


static func _p(key: String, label: String, value: float, lo: float, hi: float, step: float = 1.0, detents: Array = []) -> HGParamDef:
	return HGParamDef.make(key, label, value, lo, hi, step, PackedFloat64Array(detents))


static func _modulus() -> HGParamDef:
	return _p("m", "m", 7, 2, 32, 1, [5, 7, 8, 12, 16])


static func _wave_params() -> Array[HGParamDef]:
	return [
		_p("cycles", "k", 1, 0.25, 16, 0.25, [1, 2, 3, 4, 8]),
		_p("phase", "φ", 0, 0, 1, 0.01, [0, 0.25, 0.5, 0.75]),
		_p("depth", "a", 1, 0, 2, 0.01),
		_p("offset", "c", 0, -1, 1, 0.01),
	]


static func _build() -> void:
	var list: Array[HGFormula] = []
	var num := HGFormula.CATEGORY_NUMBER
	var dyn := HGFormula.CATEGORY_DYNAMICAL
	var geo := HGFormula.CATEGORY_GEOMETRY
	var rhy := HGFormula.CATEGORY_RHYTHM
	var har := HGFormula.CATEGORY_HARMONY
	var exr := HGFormula.CATEGORY_EXPRESSION
	var none: Array[HGParamDef] = []
	_add(list, "fibonacci", "Fibonacci mod m", num, "Fₙ = (Fₙ₋₁ + Fₙ₋₂) mod m", [_modulus()], true, false)
	_add(list, "lucas", "Lucas mod m", num, "Fₙ = (Fₙ₋₁ + Fₙ₋₂) mod m", [_modulus()], true, false)
	_add(list, "tribonacci", "Tribonacci mod m", num, "Tₙ = (Tₙ₋₁ + Tₙ₋₂ + Tₙ₋₃) mod m", [_modulus()], true, false)
	_add(list, "squares", "Squares mod m", num, "n² mod m", [_modulus()], true, true)
	_add(list, "triangular", "Triangular numbers", num, "n(n + 1) / 2 mod m", [_modulus()], true, true)
	_add(list, "cubes", "Cubes mod m", num, "n³ mod m", [_modulus()], true, true)
	_add(list, "linear", "Modular walk", num, "(a·n + c) mod m", [_p("a", "a", 2, 1, 16), _p("c", "c", 0, 0, 31), _modulus()], true, true)
	_add(list, "powers", "Powers mod p", num, "aⁿ mod p", [_p("a", "a", 3, 1, 16), _modulus()], true, false)
	_add(list, "collatz", "Collatz from s", num, "c ↦ c/2 (even), 3c + 1 (odd)", [_p("s", "start s", 22, 1, 9999), _p("after", "after 1", 1, 0, 2)], true, false)
	_add(list, "recaman", "Recamán", num, "aₙ = aₙ₋₁ − n if new ≥ 0; else +n", none, true, false)
	_add(list, "norgard", "Nørgård infinity series", num, "a₂ₙ = −aₙ ; a₂ₙ₊₁ = aₙ + 1", none, true, false)
	_add(list, "popcount", "Binary digit sum", num, "Σ bits(n)", [_p("bits", "bits", 8, 1, 20)], true, true)
	_add(list, "digitsum", "Base-b digit sum", num, "Σ digitsᵦ(n)", [_p("base", "b", 3, 2, 16)], true, false)
	_add(list, "thue", "Thue–Morse", num, "popcount(n) mod 2", none, true, false)
	_add(list, "ruler", "Ruler sequence", num, "ν₂(n + 1)", none, true, false)
	_add(list, "stern", "Stern’s diatomic", num, "s₂ₙ = sₙ ; s₂ₙ₊₁ = sₙ + sₙ₊₁", none, true, false)
	_add(list, "kolakoski", "Kolakoski", num, "1, 2, 2, 1, 1, 2, …", none, true, false)
	_add(list, "beatty", "Beatty / Fibonacci word", num, "⌊(n+1)α⌋ − ⌊nα⌋", [_p("alpha", "α", 1.61803398875, 1, 3, 0.001, [1.5, 1.61803398875, 2.41421356])], true, false)
	_add(list, "digits", "Irrational digit stream", num, "digitsᵦ(π, e, √2, φ) · 96-digit cycle", [_p("constant", "constant", 0, 0, 3), _p("base", "b", 7, 2, 16)], true, true)
	_add(list, "primes", "Primes mod m", num, "pₙ mod m", [_modulus()], true, false)
	_add(list, "primegaps", "Prime gaps", num, "pₙ₊₁ − pₙ", none, true, false)
	_add(list, "divisors", "Divisor count", num, "d(n + 1)", none, true, false)
	_add(list, "totient", "Euler totient", num, "φ(n + 1)", none, true, false)
	_add(list, "vdc", "Van der Corput", num, "radical inverseᵦ(n)", [_p("base", "b", 2, 2, 12)], false, false)
	_add(list, "gray", "Gray-code bit", num, "bitₖ(n ⊕ (n ≫ 1))", [_p("bit", "k", 2, 0, 12)], true, true)
	_add(list, "bytebeat", "Bytebeat", num, "(n·(n≫a | n≫b)) & mask", [_p("a", "a", 3, 0, 12), _p("b", "b", 5, 0, 12), _p("mask", "mask", 31, 1, 255)], true, false)
	_add(list, "logistic", "Logistic map", dyn, "x ↦ r·x(1 − x)", [_p("r", "r", 3.83, 2.5, 3.99, 0.001, [2.9, 3.2, 3.5, 3.55, 3.83, 3.95])], false, false)
	_add(list, "circle", "Circle map", dyn, "θ ↦ θ + Ω − K sin(2πθ) / 2π", [_p("omega", "Ω", 0.333333333, 0, 1, 0.001, [0.25, 1.0 / 3.0, 0.4, 0.5, 0.6666667]), _p("K", "K", 0.8, 0, 2, 0.01)], false, false)
	_add(list, "tent", "Tent map", dyn, "x ↦ r·min(x, 1 − x)", [_p("r", "r", 1.9, 1, 1.999, 0.001)], false, false)
	_add(list, "sinemap", "Sine map", dyn, "x ↦ r sin(πx)", [_p("r", "r", 0.9, 0.5, 1, 0.001)], false, false)
	_add(list, "henon", "Hénon map", dyn, "x ↦ 1 − ax² + y ; y ↦ bx", [_p("a", "a", 1.4, 0.8, 1.4, 0.001), _p("b", "b", 0.3, 0.1, 0.3, 0.001)], false, false)
	_add(list, "lorenz", "Lorenz attractor", dyn, "ẋ = σ(y−x), ẏ = x(ρ−z)−y, ż = xy−βz", [_p("sigma", "σ", 10, 5, 15, 0.1), _p("rho", "ρ", 28, 15, 35, 0.1), _p("beta", "β", 8.0 / 3.0, 2, 4, 0.01)], false, false)
	_add(list, "rossler", "Rössler attractor", dyn, "ẋ = −y−z, ẏ = x+ay, ż = b+z(x−c)", [_p("a", "a", 0.2, 0.1, 0.3, 0.01), _p("b", "b", 0.2, 0.1, 0.3, 0.01), _p("c", "c", 5.7, 4, 7, 0.1)], false, false)
	_add(list, "ca", "Cellular automaton", dyn, "cellᵢ(rule, n)", [_p("rule", "rule", 90, 0, 255, 1, [30, 90, 110]), _p("cell", "cell", 31, 0, 63)], true, false)
	_add(list, "lsystem", "L-system", dyn, "A → AB, B → A", [_p("depth", "depth", 10, 2, 16)], true, true)
	_add(list, "sine", "Sine contour", geo, "a sin(2πkn/P + φ) + c", _wave_params(), false, true)
	_add(list, "triangle", "Triangle contour", geo, "a tri(kn/P + φ) + c", _wave_params(), false, true)
	_add(list, "saw", "Saw contour", geo, "a saw(kn/P + φ) + c", _wave_params(), false, true)
	_add(list, "square", "Square contour", geo, "a sign(sin(2πkn/P + φ)) + c", _wave_params(), false, true)
	_add(list, "lissajous", "Lissajous p:q", geo, "x = sin(pθ), y = sin(qθ + φ)", [_p("p", "p", 3, 1, 12), _p("q", "q", 2, 1, 12), _p("phase", "φ", 0.25, 0, 1, 0.01)], false, true)
	_add(list, "rose", "Rose curve", geo, "r = |cos(kθ)|", [_p("k", "k", 5, 1, 16)], false, true)
	_add(list, "superformula", "Superformula", geo, "r = (|cos(mφ/4)|ⁿ² + |sin(mφ/4)|ⁿ³)⁻¹/ⁿ¹", [_p("m", "m", 5, 2, 16, 0.1), _p("n1", "n₁", 0.4, 0.2, 8, 0.05), _p("n2", "n₂", 1.7, 0.2, 8, 0.05), _p("n3", "n₃", 1.7, 0.2, 8, 0.05)], false, true)
	_add(list, "spirograph", "Spirograph", geo, "(R−r)eⁱᶿ + de⁻ⁱ⁽ᴿ⁻ʳ⁾ᶿ/ʳ", [_p("R", "R", 5, 2, 16), _p("r", "r", 3, 1, 15), _p("d", "d", 2, 0, 10, 0.1)], false, true)
	_add(list, "polygon", "Star polygon", geo, "vertex(nq mod p) · {p/q}", [_p("p", "p", 7, 3, 16), _p("q", "q", 2, 1, 15)], true, true)
	_add(list, "vertices", "Rotating vertices", geo, "cos(2πn·speed / sides)", [_p("sides", "sides", 5, 3, 16), _p("speed", "speed", 1, 1, 8)], false, true)
	_add(list, "polynomial", "Polynomial", geo, "ax³ + bx² + cx", [_p("a", "a", 1, -3, 3, 0.01), _p("b", "b", 0, -3, 3, 0.01), _p("c", "c", -1, -3, 3, 0.01)], false, true)
	_add(list, "times", "Times-table circle", geo, "m·n mod N", [_p("m", "m", 2, 1, 24), _p("N", "N", 12, 2, 64)], true, true)
	_add(list, "cardioid", "Cardioid", geo, "r = 1 − cos θ", none, false, true)
	_add(list, "astroid", "Astroid", geo, "x = cos³θ, y = sin³θ", none, false, true)
	_add(list, "spiral", "Archimedean spiral", geo, "r = θ / 2π", none, false, true)
	_add(list, "butterfly", "Butterfly", geo, "r = eᶜᵒˢᶿ − 2cos(4θ) + sin⁵(θ/12)", none, false, true)
	_add(list, "harmonograph", "Harmonograph", geo, "sin(pθ)e⁻ᵈᶿ + sin(qθ+φ)e⁻ᵈᶿ", [_p("p", "p", 2, 1, 8), _p("q", "q", 3, 1, 8), _p("decay", "d", 0.02, 0, 0.2, 0.005), _p("phase", "φ", 0.25, 0, 1, 0.01)], false, true)
	_add(list, "groove", "Genre groove", rhy, "g(n; genre, voice, density, rotation)", [_p("genre", "Genre", 0, 0, 10), _p("voice", "Drum", 0, 0, 7), _p("density", "Density", 1, 0, 2, 0.05), _p("rotation", "Rotation", 0, 0, 31)], false, true)
	_add(list, "euclid", "Euclidean E(k,n,r)", rhy, "E(k, n, rotation)", [_p("k", "k", 5, 0, 32), _p("n", "n", 16, 1, 32, 1, [8, 12, 16, 24, 32]), _p("rot", "rot", 0, 0, 31)], true, true)
	_add(list, "modgate", "Modulo gate", rhy, "n mod d = 0", [_p("d", "d", 2, 1, 32), _p("rot", "rot", 0, 0, 31)], true, true)
	_add(list, "staircase", "Floor staircase", rhy, "⌊(q+1)k/n⌋ − ⌊qk/n⌋", [_p("k", "k", 5, 0, 32), _p("n", "n", 8, 1, 32)], true, true)
	_add(list, "bit", "Binary-count bit", rhy, "(n ≫ k) & 1", [_p("bit", "k", 2, 0, 12)], true, true)
	_add(list, "polymeter", "Polymeter", rhy, "(n mod a = 0) ∨ (n mod b = 0)", [_p("a", "a", 3, 1, 16), _p("b", "b", 4, 1, 16)], true, true)
	_add(list, "zeno", "Zeno roll", rhy, "tₖ = L(1 − qᵏ)", [_p("q", "q", 0.8, 0.4, 0.95, 0.01, [0.5, 0.8]), _p("L", "L", 16, 4, 64)], true, true)
	_add(list, "circlechord", "Diatonic circle", har, "degree = 3n mod 7", none, true, true)
	_add(list, "extension", "Extension ladder", har, "stack = 3 + n mod 5", none, true, true)
	_add(list, "voicelead", "Voice-leading walk", har, "inversion = n mod voices", [_p("voices", "voices", 3, 3, 7)], true, true)
	_add(list, "spread", "Spread / strum", har, "spread = ½ + ½ sin(2πn/P)", none, false, true)
	_add(list, "plr", "Neo-Riemannian P/L/R", har, "P: parallel · L: leading-tone · R: relative", [_p("move", "move", 0, 0, 2)], true, true)
	_add(list, "accent", "Metric accent mask", exr, "1 on beat, ½ on eighth, ¼ elsewhere", none, false, true)
	_add(list, "crescendo", "Crescendo ramp", exr, "v = (n mod L) / (L − 1)", [_p("length", "L", 32, 2, 128)], false, true)
	assert(list.size() == F_COUNT)
	var by: Dictionary[String, HGFormula] = {}
	for f: HGFormula in list:
		by[f.id] = f
	_by_id = by
	_catalogue = list


static func _add(list: Array[HGFormula], id: String, name: String, category: String, equation: String, params: Array[HGParamDef], integer: bool, has_period: bool) -> void:
	var f := HGFormula.new()
	f.id = id
	f.name = name
	f.category = category
	f.equation = equation
	f.params = params
	f.integer = integer
	f.has_period = has_period
	f.index = list.size()
	list.append(f)


# ───────────────────────────── evaluation ─────────────────────────────

## Engine `value(id, n, params, P)`: the raw formula value at step n. Parameters are cleaned first;
## a negative n is wrapped into [0, P); P (the cycle, for wave formulas) is at least 1. Non-wave
## formulas see floor(n); 'Geometry & waves' formulas that are not integer see the fractional n.
static func value(id: String, n: float, params: Dictionary[String, float] = {}, P: float = 16.0) -> float:
	var f := formula_or_default(id)
	var p := clean_params(f.id, params)
	var at: float = HGMath.mod(n, maxf(1.0, P)) if n < 0.0 else n
	var x: float = at if (f.category == HGFormula.CATEGORY_GEOMETRY and not f.integer) else floorf(at)
	return _eval(f.index, x, p, maxf(1.0, P))


## Engine `normal(id, n, p, P)`: value mapped to 0..1. Integer formulas are reduced modulo m and
## divided by m - 1, where m is the first truthy of the RAW (uncleaned) p.m, p.N, p.p — so normal
## with {} differs from normal with the defaults — else 2 for gates/thue/gray/ca/lsystem, else 8.
static func normal(id: String, n: float, p: Dictionary[String, float] = {}, P: float = 16.0) -> float:
	var f := formula_or_default(id)
	var v := value(f.id, n, p, P)
	if not f.integer:
		return HGMath.clamp_js(v, 0.0, 1.0)
	# `p.m || p.N || p.p || (...)`: JS truthiness, a 0 or NaN entry is skipped.
	var m: float = 0.0
	if HGMath.truthy(p.get("m", 0.0)):
		m = p["m"]
	elif HGMath.truthy(p.get("N", 0.0)):
		m = p["N"]
	elif HGMath.truthy(p.get("p", 0.0)):
		m = p["p"]
	elif f.category == HGFormula.CATEGORY_RHYTHM or f.id == "thue" or f.id == "gray" or f.id == "ca" or f.id == "lsystem":
		m = 2.0
	else:
		m = 8.0
	return HGMath.clamp_js(HGMath.mod(v, m) / maxf(1.0, m - 1.0), 0.0, 1.0)


## Engine `period(id, p, P)`: the formula's period in steps, or 0.0 where the engine returns null
## (no known period). Note the engine quirk kept here: a declared period function that returns null
## (an unsampleable wave ratio) yields 1 through `Math.max(1, null)`.
static func period(id: String, params: Dictionary[String, float] = {}, P: float = 16.0) -> float:
	var f := formula_or_default(id)
	var p := clean_params(f.id, params)
	if id == "fibonacci" or id == "lucas":
		# Pisano period: first return of the state pair (a, b) to its start.
		var m: float = p["m"]
		var a: float = fmod(2.0, m) if id == "lucas" else 0.0
		var b: float = 1.0
		var ia: float = a
		var i: float = 1.0
		while i <= m * m * 6.0:
			var nb: float = fmod(a + b, m)
			a = b
			b = nb
			if a == ia and b == 1.0:
				return i
			i += 1.0
	if id == "collatz":
		return float(sequence("collatz", p).size())
	if id == "logistic":
		var arr := sequence("logistic", p)
		for q: int in [1, 2, 3, 4, 6, 8, 12, 16, 32, 64]:
			var ok: bool = true
			for i: int in range(3000, 3100):
				if absf(arr[i] - arr[i - q]) > 1e-7:
					ok = false
					break
			if ok:
				return float(q)
		return 0.0
	if not f.has_period:
		return 0.0
	var v: float = _period_fn(f.index, p, P)
	# Math.max(1, null) = 1; Math.max(1, NaN) = NaN.
	if is_nan(v):
		return v
	return maxf(1.0, v)


## Declared period functions; NaN never occurs for cleaned params, 0 stands for a null result.
static func _period_fn(idx: int, p: Dictionary[String, float], P: float) -> float:
	match idx:
		F_SQUARES, F_CUBES:
			return p["m"]
		F_TRIANGULAR:
			return 2.0 * p["m"]
		F_LINEAR:
			return p["m"] / HGMath.gcd(p["a"], p["m"])
		F_DIGITS:
			return 96.0
		F_POPCOUNT:
			return pow(2.0, p["bits"])
		F_GRAY:
			return pow(2.0, p["bit"] + 2.0)
		F_LSYSTEM:
			return float(sequence("lsystem", p).size())
		F_SINE, F_TRIANGLE, F_SAW, F_SQUARE:
			return sampled_period(P / p["cycles"])
		F_LISSAJOUS, F_ROSE, F_SUPERFORMULA, F_POLYNOMIAL, F_CARDIOID, F_ASTROID, F_SPIRAL, F_HARMONOGRAPH, F_SPREAD:
			return P
		F_SPIROGRAPH:
			return P * p["r"] / HGMath.gcd(p["R"], p["r"])
		F_POLYGON:
			return p["p"] / HGMath.gcd(p["p"], p["q"])
		F_VERTICES:
			return p["sides"] / HGMath.gcd(p["sides"], p["speed"])
		F_TIMES:
			return p["N"] / HGMath.gcd(p["m"], p["N"])
		F_BUTTERFLY:
			return P * 12.0
		F_GROOVE:
			return groove_pattern(p).n
		F_EUCLID, F_STAIRCASE:
			return p["n"]
		F_MODGATE:
			return p["d"]
		F_BIT:
			return pow(2.0, p["bit"] + 1.0)
		F_POLYMETER:
			return HGMath.lcm(p["a"], p["b"])
		F_ZENO:
			return p["L"]
		F_CIRCLECHORD:
			return 7.0
		F_EXTENSION:
			return 5.0
		F_VOICELEAD:
			return p["voices"]
		F_PLR:
			return 2.0
		F_ACCENT:
			return 4.0
		F_CRESCENDO:
			return p["length"]
	return 0.0


## Engine `sampledPeriod(q)`: smallest d <= 256 with q·d integral (to 1e-7), as round(q·d); 0 = null.
static func sampled_period(q: float) -> float:
	for d: int in range(1, 257):
		var qd: float = q * float(d)
		if absf(qd - HGMath.js_round(qd)) < 1e-7:
			return HGMath.js_round(qd)
	return 0.0


## The formula bodies (`fn(n, p, P)` of each catalogue entry). n is already floored for non-wave
## formulas; p is cleaned; P >= 1.
static func _eval(idx: int, n: float, p: Dictionary[String, float], P: float) -> float:
	match idx:
		F_FIBONACCI:
			return _seq("fibonacci", p, n)
		F_LUCAS:
			return _seq("lucas", p, n)
		F_TRIBONACCI:
			return _seq("tribonacci", p, n)
		F_SQUARES:
			return HGMath.mod(n * n, p["m"])
		F_TRIANGULAR:
			return HGMath.mod(n * (n + 1.0) / 2.0, p["m"])
		F_CUBES:
			return HGMath.mod(n * n * n, p["m"])
		F_LINEAR:
			return HGMath.mod(p["a"] * n + p["c"], p["m"])
		F_POWERS:
			# Square-and-multiply on doubles; `r * b % m` is (r * b) % m (left to right).
			var r: float = 1.0
			var b: float = p["a"]
			var m: float = p["m"]
			var k: float = n
			while k > 0.0:
				if HGMath.truthy(fmod(k, 2.0)):
					r = fmod(r * b, m)
				b = fmod(b * b, m)
				k = floorf(k / 2.0)
			return r
		F_COLLATZ:
			var a := sequence("collatz", p)
			var len: float = float(a.size())
			if n < len:
				return a[int(n)]
			if p["after"] == 0.0:
				return 1.0
			if p["after"] == 1.0:
				return a[int(fmod(n, len))]
			return [4.0, 2.0, 1.0][int(fmod(n - len, 3.0))]
		F_RECAMAN:
			return _seq("recaman", p, n)
		F_NORGARD:
			return _norgard(n)
		F_POPCOUNT:
			return _popcount(fmod(n, pow(2.0, p["bits"])))
		F_DIGITSUM:
			return _digit_sum(n, p["base"])
		F_THUE:
			return fmod(_popcount(n), 2.0)
		F_RULER:
			return _ruler(n + 1.0)
		F_STERN:
			return _seq("stern", p, n)
		F_KOLAKOSKI:
			return _seq("kolakoski", p, n)
		F_BEATTY:
			return floorf((n + 1.0) * p["alpha"]) - floorf(n * p["alpha"])
		F_DIGITS:
			return _seq("digits", p, n)
		F_PRIMES:
			return _seq("primes", p, n)
		F_PRIMEGAPS:
			return _seq("primegaps", p, n)
		F_DIVISORS:
			var c: float = 0.0
			var i: float = 1.0
			while i * i <= n + 1.0:
				if fmod(n + 1.0, i) == 0.0:
					c += 1.0 if i * i == n + 1.0 else 2.0
				i += 1.0
			return c
		F_TOTIENT:
			var v: float = n + 1.0
			var r: float = v
			var q: float = 2.0
			while q * q <= v:
				if fmod(v, q) == 0.0:
					while fmod(v, q) == 0.0:
						v /= q
					r -= r / q
				q += 1.0
			if v > 1.0:
				r -= r / v
			return r
		F_VDC:
			var v: float = 0.0
			var d: float = 1.0
			var base: float = p["base"]
			var k: float = n
			while HGMath.truthy(k):
				d *= base
				v += fmod(k, base) / d
				k = floorf(k / base)
			return v
		F_GRAY:
			# `((n ^ (n >> 1)) >> bit) & 1`: JS 32-bit integer operators.
			return HGMath.band(HGMath.shr(HGMath.bxor(n, HGMath.shr(n, 1.0)), p["bit"]), 1.0)
		F_BYTEBEAT:
			# `(n * (n >> a | n >> b)) & mask`: the shifts and | are int32, the product is a double
			# multiply, then & applies ToInt32 to the (possibly > 2^31) product.
			var inner: float = HGMath.bor(HGMath.shr(n, p["a"]), HGMath.shr(n, p["b"]))
			return HGMath.band(n * inner, p["mask"])
		F_LOGISTIC:
			# The map is read after a 256-step transient.
			return _seq("logistic", p, n + 256.0)
		F_CIRCLE:
			return _seq("circle", p, n)
		F_TENT:
			return _seq("tent", p, n)
		F_SINEMAP:
			return _seq("sinemap", p, n)
		F_HENON:
			return _seq("henon", p, n)
		F_LORENZ:
			return _seq("lorenz", p, n)
		F_ROSSLER:
			return _seq("rossler", p, n)
		F_CA:
			return _seq("ca", p, n)
		F_LSYSTEM:
			return _seq("lsystem", p, n)
		F_SINE, F_TRIANGLE, F_SAW, F_SQUARE:
			var t: float = HGMath.mod(n / P * p["cycles"] + p["phase"], 1.0)
			var w: float
			if idx == F_SINE:
				w = sin(TAU * t)
			elif idx == F_TRIANGLE:
				w = 1.0 - 4.0 * absf(t - 0.5)
			elif idx == F_SAW:
				w = 2.0 * t - 1.0
			else:
				w = 1.0 if t < 0.5 else -1.0
			return HGMath.clamp_js((w * p["depth"] + p["offset"] + 1.0) / 2.0, 0.0, 1.0)
		F_LISSAJOUS:
			return HGMath.hypot(sin(TAU * n / P * p["p"]), sin(TAU * n / P * p["q"] + TAU * p["phase"])) / sqrt(2.0)
		F_ROSE:
			return absf(cos(p["k"] * TAU * n / P))
		F_SUPERFORMULA:
			var ang: float = p["m"] * TAU * n / P / 4.0
			var rr: float = pow(pow(absf(cos(ang)), p["n2"]) + pow(absf(sin(ang)), p["n3"]), -1.0 / p["n1"])
			return HGMath.clamp_js(rr, 0.0, 2.0) / 2.0
		F_SPIROGRAPH:
			var a: float = TAU * n / P
			var d: float = p["R"] - p["r"]
			var x: float = d * cos(a) + p["d"] * cos(d * a / p["r"])
			var y: float = d * sin(a) - p["d"] * sin(d * a / p["r"])
			return HGMath.hypot(x, y) / maxf(1.0, absf(d) + p["d"])
		F_POLYGON:
			return HGMath.mod(n * p["q"], p["p"])
		F_VERTICES:
			return (cos(TAU * n * p["speed"] / p["sides"]) + 1.0) / 2.0
		F_POLYNOMIAL:
			var x: float = 2.0 * HGMath.mod(n, P) / P - 1.0
			return HGMath.clamp_js((p["a"] * pow(x, 3.0) + p["b"] * x * x + p["c"] * x + 1.0) / 2.0, 0.0, 1.0)
		F_TIMES:
			return HGMath.mod(p["m"] * n, p["N"])
		F_CARDIOID:
			return (1.0 - cos(TAU * n / P)) / 2.0
		F_ASTROID:
			return HGMath.hypot(pow(cos(TAU * n / P), 3.0), pow(sin(TAU * n / P), 3.0))
		F_SPIRAL:
			return HGMath.mod(n, P) / P
		F_BUTTERFLY:
			var t: float = TAU * n / P
			return HGMath.clamp_js((exp(cos(t)) - 2.0 * cos(4.0 * t) + pow(sin(t / 12.0), 5.0) + 2.0) / 6.0, 0.0, 1.0)
		F_HARMONOGRAPH:
			var t: float = TAU * HGMath.mod(n, P) / P
			return 0.5 + 0.25 * (sin(p["p"] * t) + sin(p["q"] * t + TAU * p["phase"])) * exp(-p["decay"] * t)
		F_GROOVE:
			return groove_value(n, p)
		F_EUCLID:
			return euclid(n, p["k"], p["n"], p["rot"])
		F_MODGATE:
			return 1.0 if HGMath.mod(n - p["rot"], p["d"]) == 0.0 else 0.0
		F_STAIRCASE:
			return floorf((n + 1.0) * p["k"] / p["n"]) - floorf(n * p["k"] / p["n"])
		F_BIT:
			return HGMath.band(HGMath.shr(n, p["bit"]), 1.0)
		F_POLYMETER:
			return 1.0 if (fmod(n, p["a"]) == 0.0 or fmod(n, p["b"]) == 0.0) else 0.0
		F_ZENO:
			var L: float = p["L"]
			var target: float = HGMath.mod(n, L)
			for k: int in 64:
				if floorf(L * (1.0 - pow(p["q"], float(k)))) == target:
					return 1.0
			return 0.0
		F_CIRCLECHORD:
			return HGMath.mod(3.0 * n, 7.0)
		F_EXTENSION:
			return fmod(n, 5.0)
		F_VOICELEAD:
			return fmod(n, p["voices"])
		F_SPREAD:
			return (sin(TAU * n / P) + 1.0) / 2.0
		F_PLR:
			# `n % 2 ? [0, 4, 9][move] : 0`
			if HGMath.truthy(fmod(n, 2.0)):
				return [0.0, 4.0, 9.0][int(p["move"])]
			return 0.0
		F_ACCENT:
			if fmod(n, 4.0) == 0.0:
				return 1.0
			if fmod(n, 2.0) == 0.0:
				return 0.55
			return 0.25
		F_CRESCENDO:
			return HGMath.mod(n, p["length"]) / (p["length"] - 1.0)
	return 0.0


static func _norgard(k: float) -> float:
	# f(0) = 0; f(2k+1) = f(k) + 1; f(2k) = -f(k). Iterative over the binary digits, applied from
	# the most significant end so the result equals the engine's recursion (including -0).
	var ops: PackedByteArray = PackedByteArray()
	while k != 0.0:
		if HGMath.truthy(fmod(k, 2.0)):
			ops.append(1)
			k = (k - 1.0) / 2.0
		else:
			ops.append(0)
			k = k / 2.0
	var v: float = 0.0
	for i: int in range(ops.size() - 1, -1, -1):
		v = v + 1.0 if ops[i] == 1 else -v
	return v


static func _popcount(n: float) -> float:
	# `for (n = n >>> 0; n; n >>>= 1) c += n & 1`: ToUint32 first.
	var u: int = HGMath.to_uint32(n)
	var c: int = 0
	while u != 0:
		c += u & 1
		u >>= 1
	return float(c)


static func _digit_sum(n: float, b: float) -> float:
	var c: float = 0.0
	while n > 0.0:
		c += fmod(n, b)
		n = floorf(n / b)
	return c


static func _ruler(n: float) -> float:
	var c: float = 0.0
	n = maxf(1.0, floorf(n))
	while fmod(n, 2.0) == 0.0:
		c += 1.0
		n /= 2.0
	return c


# ───────────────────────────── grooves ─────────────────────────────

## Engine `groovePattern(p)` result: Euclidean pulses k over n steps, rotated.
class GroovePattern:
	extends RefCounted
	var k: float = 0.0
	var n: float = 16.0
	var rotation: float = 0.0


## Engine `euclid(step, k, n, rot)`: 1 when step is one of the k evenly spread pulses of n.
static func euclid(step: float, k: float, n: float, rot: float = 0.0) -> float:
	n = maxf(1.0, HGMath.js_round(n))
	k = HGMath.js_round(HGMath.clamp_js(k, 0.0, n))
	return 1.0 if HGMath.mod((step - rot) * k, n) < k else 0.0


## Engine `groovePattern(p)` (p cleaned groove params): voice 0 kick, 1/4 snare/clap, 2 closed hat,
## 5 open hat, 3 [4,16,2], 6 [2,16,5], 7 [1,32,0]; k scaled by density.
static func groove_pattern(p: Dictionary[String, float]) -> GroovePattern:
	var gi: float = HGMath.js_round(p.get("genre", 0.0))
	# `Object.values(GENRES)[i] || GENRES.House`
	var g: Array = GENRES[GENRE_NAMES[int(gi)]] if (gi >= 0.0 and gi < float(GENRE_NAMES.size())) else GENRES["House"]
	var voice: float = HGMath.js_round(p.get("voice", 0.0))
	var spec: Array
	if voice == 0.0:
		spec = g[0]
	elif voice == 1.0 or voice == 4.0:
		spec = g[1]
	elif voice == 2.0:
		spec = g[2]
	elif voice == 5.0:
		spec = g[3]
	elif voice == 3.0:
		spec = [4, 16, 2]
	elif voice == 6.0:
		spec = [2, 16, 5]
	else:
		spec = [1, 32, 0]
	var out := GroovePattern.new()
	out.k = HGMath.js_round(HGMath.clamp_js(float(spec[0]) * p.get("density", 1.0), 0.0, float(spec[1])))
	out.n = float(spec[1])
	out.rotation = float(spec[2]) + p.get("rotation", 0.0)
	return out


## Engine `grooveValue(n, p)`: 0 off the pattern; on it 1 / .88 / .76 / .64 by metric weight.
static func groove_value(n: float, p: Dictionary[String, float]) -> float:
	var pattern := groove_pattern(p)
	var at: float = floorf(n) - pattern.rotation
	if euclid(n, pattern.k, pattern.n, pattern.rotation) == 0.0:
		return 0.0
	if HGMath.mod(at, 16.0) == 0.0:
		return 1.0
	if HGMath.mod(at, 4.0) == 0.0:
		return 0.88
	if HGMath.mod(at, 2.0) == 0.0:
		return 0.76
	return 0.64


# ───────────────────────────── sequences ─────────────────────────────

## Engine `seq(id, p, n)`: element floor(n) (>= 0) of the formula's sequence; finite lists (digits,
## lsystem) cycle. A missing or NaN element reads 0 (`a[i] || 0`).
static func _seq(id: String, p: Dictionary[String, float], n: float) -> float:
	var finite: bool = id == "digits" or id == "lsystem"
	var at: float = maxf(0.0, floorf(n))
	var a := sequence(id, p, 4096 if finite else maxi(256, int(at) + 1))
	var idx: float = HGMath.mod(at, float(a.size())) if finite else at
	var v: float = HGMath.at_or(a, idx, 0.0)
	return 0.0 if is_nan(v) else v


## Engine `sequence(kind, p, len)`: the finite list for digits/collatz/lsystem (len ignored), or
## at least `len` leading elements of an endless stream. p must be cleaned. The returned array is
## a copy-on-write snapshot; do not rely on its length beyond `len`.
static func sequence(kind: String, p: Dictionary[String, float], length: int = 4096) -> PackedFloat64Array:
	var key: String = kind + _params_key(p)
	_lock.lock()
	if kind == "digits" or kind == "collatz" or kind == "lsystem":
		if not _memo.has(key):
			if _memo.size() > 256:
				_memo.clear()
			_memo[key] = _finite_sequence(kind, p)
		var out: PackedFloat64Array = _memo[key]
		_lock.unlock()
		return out
	var entry: _Stream = _streams.get(key, null)
	if entry == null:
		if _streams.size() >= 16:
			_streams.erase(_streams.keys()[0])
		entry = _Stream.new(kind, p)
		_streams[key] = entry
	entry.fill(length)
	var vals: PackedFloat64Array = entry.values
	_lock.unlock()
	return vals


static func _params_key(p: Dictionary[String, float]) -> String:
	var parts := PackedStringArray()
	for k: String in p:
		parts.append(k + "=" + PackedFloat64Array([p[k]]).to_byte_array().hex_encode())
	return "|" + ",".join(parts)


static func _finite_sequence(kind: String, p: Dictionary[String, float]) -> PackedFloat64Array:
	var a := PackedFloat64Array()
	if kind == "lsystem":
		# A -> AB, B -> A, `Math.min(p.depth || 12, 16)` rewrites; A reads 1, B reads 0.
		var depth: float = p.get("depth", 0.0)
		var steps: float = minf(depth if HGMath.truthy(depth) else 12.0, 16.0)
		var word := PackedByteArray([1])
		var i: float = 0.0
		while i < steps:
			var next := PackedByteArray()
			for c: int in word:
				if c == 1:
					next.append(1)
					next.append(0)
				else:
					next.append(1)
			word = next
			i += 1.0
		for c: int in word:
			a.append(float(c))
		return a
	if kind == "digits":
		# Fixed-point digit streams, 100 decimal places; explicit finite cycle, never fake endless
		# precision. The engine uses BigInt: num = fractional digits (BigInt(s) % 10^99), then 96
		# times num *= b, digit = num / 10^99, num %= 10^99. Here num is its decimal digit array
		# (most significant first) and the digit is the carry out of the top of num * b — exact.
		var ci: float = p.get("constant", 0.0)
		var s: String = DIGIT_STRINGS[int(ci) if HGMath.truthy(ci) else 0]
		var b_raw: float = p.get("base", 0.0)
		var b: int = int(b_raw) if HGMath.truthy(b_raw) else 7
		var digits := PackedInt32Array()
		for i: int in range(1, s.length()):
			digits.append(s.unicode_at(i) - 48)
		for _k: int in 96:
			var carry: int = 0
			for j: int in range(digits.size() - 1, -1, -1):
				var t: int = digits[j] * b + carry
				digits[j] = t % 10
				carry = int(t / 10.0)
			a.append(float(carry))
		return a
	# collatz
	var s0: float = p.get("s", 0.0)
	var x: float = s0 if HGMath.truthy(s0) else 22.0
	for _i: int in 8192:
		a.append(x)
		if x == 1.0:
			break
		x = 3.0 * x + 1.0 if HGMath.truthy(fmod(x, 2.0)) else x / 2.0
		# Number.isSafeInteger(x)
		if not (x == floorf(x) and absf(x) <= 9007199254740991.0):
			break
	return a


## One endless sequence with its generator state (engine `function* stream(kind, p)`).
class _Stream:
	extends RefCounted
	var kind: String
	var p: Dictionary[String, float]
	var values: PackedFloat64Array = PackedFloat64Array()
	## The engine's `a` (history; for kolakoski the sequence itself).
	var a: PackedFloat64Array = PackedFloat64Array()
	var seen: Dictionary[int, bool] = {0: true}
	var primes: PackedInt64Array = PackedInt64Array()
	var candidate: int = 2
	var x: float = 0.217
	var y: float = 0.1
	var z: float = 0.1
	## Cellular-automaton row: the engine's 64-bit BigInt `1n << 31n`, held in a signed 64-bit int
	## (bit 63 shows as the sign; `(row >> j) & 1` still reads bit j for 0 <= j <= 63).
	var row: int = 1 << 31
	var i: int = 0
	var kola_k: int = 2

	func _init(p_kind: String, p_params: Dictionary[String, float]) -> void:
		kind = p_kind
		p = p_params.duplicate()
		if kind == "kolakoski":
			a = PackedFloat64Array([1.0, 2.0, 2.0])

	func fill(length: int) -> void:
		while values.size() < length:
			values.append(_next())

	func _next() -> float:
		if kind == "kolakoski":
			# Yields 1, 2, 2, then for k = 2, 3, ...: a[k] copies of the symbol opposite to the last.
			while i >= a.size():
				var v: float = 2.0 if a[a.size() - 1] == 1.0 else 1.0
				var reps: int = int(a[kola_k])
				for _j: int in reps:
					a.append(v)
				kola_k += 1
			var out: float = a[i]
			i += 1
			return out
		var v: float = 0.0
		if kind == "primes" or kind == "primegaps":
			var need: int = i + (2 if kind == "primegaps" else 1)
			while primes.size() < need:
				var ok: bool = true
				for q: int in primes:
					if q * q > candidate:
						break
					if candidate % q == 0:
						ok = false
						break
				if ok:
					primes.append(candidate)
				candidate += 1
			v = fmod(float(primes[i]), p["m"]) if kind == "primes" else float(primes[i + 1] - primes[i])
		elif kind == "fibonacci":
			v = float(i) if i < 2 else fmod(a[i - 1] + a[i - 2], p["m"])
		elif kind == "lucas":
			v = fmod([2.0, 1.0][i], p["m"]) if i < 2 else fmod(a[i - 1] + a[i - 2], p["m"])
		elif kind == "tribonacci":
			v = [0.0, 0.0, 1.0][i] if i < 3 else fmod(a[i - 1] + a[i - 2] + a[i - 3], p["m"])
		elif kind == "recaman":
			v = a[i - 1] - float(i) if i > 0 else 0.0
			if v < 0.0 or seen.has(int(v)):
				v = a[i - 1] + float(i) if i > 0 else 0.0
			seen[int(v)] = true
		elif kind == "stern":
			if i < 2:
				v = float(i)
			elif i % 2 == 1:
				v = a[(i - 1) >> 1] + a[(i + 1) >> 1]
			else:
				v = a[i >> 1]
		elif kind == "logistic":
			x = p["r"] * x * (1.0 - x)
			v = x
		elif kind == "circle":
			# x + Ω − (K / 2π) · sin(2πx), wrapped into [0, 1).
			x = HGMath.mod(x + p["omega"] - p["K"] / TAU * sin(TAU * x), 1.0)
			v = x
		elif kind == "tent":
			x = p["r"] * (x if x < 0.5 else 1.0 - x)
			v = x
		elif kind == "sinemap":
			x = p["r"] * sin(PI * x)
			v = x
		elif kind == "henon":
			var nx: float = 1.0 - p["a"] * x * x + y
			y = p["b"] * x
			x = HGMath.clamp_js(nx, -3.0, 3.0)
			v = HGMath.clamp_js((x + 1.5) / 3.0, 0.0, 1.0)
		elif kind == "lorenz" or kind == "rossler":
			var lorenz: bool = kind == "lorenz"
			for _k: int in 8:
				var dx: float
				var dy: float
				var dz: float
				if lorenz:
					dx = p["sigma"] * (y - x)
					dy = x * (p["rho"] - z) - y
					dz = x * y - p["beta"] * z
				else:
					dx = -y - z
					dy = x + p["a"] * y
					dz = p["b"] + z * (x - p["c"])
				x += dx * 0.005
				y += dy * 0.005
				z += dz * 0.005
				var s: float = x + y + z
				if not is_finite(s) or absf(s) > 1e5:
					x = 0.1
					y = 0.1
					z = 0.1
			v = HGMath.clamp_js((x + 25.0) / 50.0 if lorenz else (x + 15.0) / 30.0, 0.0, 1.0)
		elif kind == "ca":
			# One step of an elementary CA on a 64-cell ring (engine BigInt `row`); reads one cell.
			v = float((row >> int(p["cell"])) & 1)
			var rule: int = HGMath.to_int32(p["rule"])
			var next: int = 0
			for j: int in 64:
				var pat: int = ((row >> ((j + 1) % 64)) & 1) * 4 + ((row >> j) & 1) * 2 + ((row >> ((j + 63) % 64)) & 1)
				# `(p.rule >> pat) & 1` with JS int32 shift.
				if ((rule >> pat) & 1) == 1:
					next |= 1 << j
			row = next
		a.append(v)
		i += 1
		return v
