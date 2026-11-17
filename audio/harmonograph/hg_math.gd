class_name HGMath
extends RefCounted
## JavaScript number semantics for the Harmonograph port (prototype/src/vendor/harmonograph.js).
##
## The engine is written for JS, where every number is an IEEE double, `%` is a truncating
## remainder (C `fmod`), bitwise operators work on 32-bit integers, `Math.round` rounds halves
## toward +infinity and `clamp` maps non-finite input to the lower bound. GDScript's own `round`,
## `clamp`, `%` (int-only) and shifts (64-bit) differ, so every engine spot that depends on one of
## these goes through a helper here, and each call site says why.


## `clamp(x, lo, hi)` from the engine: `Math.max(lo, Math.min(hi, Number.isFinite(+x) ? +x : lo))`.
## NaN and +/-Infinity become `lo` (so e.g. an infinite superformula radius clamps to 0, not 2).
static func clamp_js(x: float, lo: float, hi: float) -> float:
	var v: float = x if is_finite(x) else lo
	# Math.min / Math.max on finite operands: plain comparisons.
	v = hi if hi < v else v
	return lo if lo > v else v


## `mod(x, m) = ((x % m) + m) % m`, JS `%` being C fmod (sign of the dividend). Result has the sign
## of m (non-negative for m > 0). m = 0 gives NaN, as in JS.
static func mod(x: float, m: float) -> float:
	return fmod(fmod(x, m) + m, m)


## JS `a % b` on doubles.
static func rem(a: float, b: float) -> float:
	return fmod(a, b)


## `gcd = (a, b) => b ? gcd(b, a % b) : a` (truthiness: 0 and NaN end the recursion).
static func gcd(a: float, b: float) -> float:
	while b != 0.0 and not is_nan(b):
		var t: float = fmod(a, b)
		a = b
		b = t
	return a


## `lcm = (a, b) => Math.min(1048576, a / gcd(a, b) * b)`.
static func lcm(a: float, b: float) -> float:
	var v: float = a / gcd(a, b) * b
	if is_nan(v):
		return v
	return minf(1048576.0, v)


## `Math.round`: nearest integer, halves toward +infinity (-2.5 -> -2). GDScript's round() rounds
## halves away from zero, which differs for negative halves. `x - floor(x)` is exact for doubles.
static func js_round(x: float) -> float:
	if not is_finite(x):
		return x
	var f: float = floorf(x)
	return f + 1.0 if x - f >= 0.5 else f


## `Math.trunc`.
static func trunc_js(x: float) -> float:
	if not is_finite(x):
		return x
	return floorf(x) if x >= 0.0 else ceilf(x)


## `Math.sign` (NaN stays NaN; zero stays zero).
static func sign_js(x: float) -> float:
	if is_nan(x):
		return x
	if x > 0.0:
		return 1.0
	if x < 0.0:
		return -1.0
	return x


## ECMAScript ToInt32: truncate, reduce modulo 2^32, reinterpret as signed. NaN/Infinity -> 0.
## Used for every bitwise operator in the engine (`>>`, `&`, `|`, `^`).
static func to_int32(x: float) -> int:
	if not is_finite(x):
		return 0
	var m: float = fmod(trunc_js(x), 4294967296.0)
	if m < 0.0:
		m += 4294967296.0
	var i: int = int(m)
	if i >= 2147483648:
		i -= 4294967296
	return i


## ECMAScript ToUint32 (`x >>> 0`).
static func to_uint32(x: float) -> int:
	if not is_finite(x):
		return 0
	var m: float = fmod(trunc_js(x), 4294967296.0)
	if m < 0.0:
		m += 4294967296.0
	return int(m)


## JS `a >> b`: ToInt32(a) arithmetic-shifted by ToUint32(b) & 31. GDScript ints are 64-bit, so a
## shift of a value already in int32 range is sign-correct; the count is masked like JS.
static func shr(a: float, b: float) -> float:
	return float(to_int32(a) >> (to_uint32(b) & 31))


## JS `a & b` on 32-bit integers (result is a signed int32).
static func band(a: float, b: float) -> float:
	return float(_wrap32(to_int32(a) & to_int32(b)))


## JS `a | b`.
static func bor(a: float, b: float) -> float:
	return float(_wrap32(to_int32(a) | to_int32(b)))


## JS `a ^ b`.
static func bxor(a: float, b: float) -> float:
	return float(_wrap32(to_int32(a) ^ to_int32(b)))


static func _wrap32(i: int) -> int:
	# Two int32 operands combined with & | ^ stay inside int32 when held as sign-extended 64-bit
	# values; this only normalises defensively.
	i = i & 0xFFFFFFFF
	return i - 4294967296 if i >= 2147483648 else i


## `Math.hypot(a, b)` exactly as V8 computes it (builtins/math.tq: normalise by the largest
## magnitude, Kahan-sum the squares, sqrt, rescale). A plain sqrt(a*a + b*b) differs in the last
## bit for some inputs.
static func hypot(a: float, b: float) -> float:
	var one_nan: bool = false
	var max_abs: float = 0.0
	var xa: float = 0.0
	var xb: float = 0.0
	if is_nan(a):
		one_nan = true
	else:
		xa = absf(a)
		if xa > max_abs:
			max_abs = xa
	if is_nan(b):
		one_nan = true
	else:
		xb = absf(b)
		if xb > max_abs:
			max_abs = xb
	if max_abs == INF:
		return INF
	if one_nan:
		return NAN
	if max_abs == 0.0:
		return 0.0
	var sum: float = 0.0
	var compensation: float = 0.0
	var n: float = xa / max_abs
	var summand: float = n * n - compensation
	var preliminary: float = sum + summand
	compensation = (preliminary - sum) - summand
	sum = preliminary
	n = xb / max_abs
	summand = n * n - compensation
	preliminary = sum + summand
	compensation = (preliminary - sum) - summand
	sum = preliminary
	return sqrt(sum) * max_abs


## `Math.max(a, b)`: NaN if either is NaN (GDScript maxf returns the second operand instead).
static func js_max(a: float, b: float) -> float:
	if is_nan(a) or is_nan(b):
		return NAN
	return a if a > b else b


## `Math.min(a, b)` with JS NaN propagation.
static func js_min(a: float, b: float) -> float:
	if is_nan(a) or is_nan(b):
		return NAN
	return a if a < b else b


## JS truthiness of a number (0 and NaN are falsy).
static func truthy(x: float) -> bool:
	return x != 0.0 and not is_nan(x)


## Copy of a parameter map with float values (JSON parsing yields untyped dictionaries).
static func params_from(d: Variant) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	if d is Dictionary:
		var src: Dictionary = d
		for k: Variant in src:
			var v: Variant = src[k]
			if v is float or v is int:
				out[String(k)] = float(v)
			elif v is bool:
				out[String(k)] = 1.0 if v else 0.0
	return out


## Plain dictionary for JSON writing.
static func params_to_dict(p: Dictionary[String, float]) -> Dictionary:
	var out: Dictionary = {}
	for k: String in p:
		out[k] = p[k]
	return out


## Index into `arr` with JS semantics `arr[i]` for a non-negative integral i; `def` when absent
## (JS `undefined`).
static func at_or(arr: PackedFloat64Array, i: float, def: float) -> float:
	if is_nan(i) or i < 0.0 or i != floorf(i) or i >= float(arr.size()):
		return def
	return arr[int(i)]
