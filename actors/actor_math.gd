class_name ActorMath
extends RefCounted
## Small allocation-free numeric helpers for the actor layer (prototype render/actors/math.ts).
## Pure: no nodes, no clock, so the interpolation and animation logic built on them is unit-tested.

const TAU_F: float = PI * 2.0


static func clamp01(v: float) -> float:
	return 0.0 if v < 0.0 else (1.0 if v > 1.0 else v)


## Wrap an angle into (-PI, PI].
static func wrap_angle(a: float) -> float:
	if is_nan(a) or is_inf(a):
		return 0.0
	var r := fmod(a, TAU_F)
	if r <= -PI:
		r += TAU_F
	elif r > PI:
		r -= TAU_F
	return r


## Signed shortest difference b - a in (-PI, PI].
static func angle_delta(a: float, b: float) -> float:
	return wrap_angle(b - a)


## Interpolate angles along the shortest arc; result wrapped to (-PI, PI].
static func lerp_angle_short(a: float, b: float, t: float) -> float:
	return wrap_angle(a + angle_delta(a, b) * t)


static func smooth(e0: float, e1: float, x: float) -> float:
	var t := clamp01((x - e0) / (e1 - e0))
	return t * t * (3.0 - 2.0 * t)


## Frame-rate independent exponential approach: fraction of the gap to close this frame.
static func damp_factor(rate: float, dt: float) -> float:
	return 1.0 - exp(-rate * maxf(0.0, dt))


static func ease_out_cubic(t: float) -> float:
	var u := 1.0 - clamp01(t)
	return 1.0 - u * u * u


static func ease_in_cubic(t: float) -> float:
	var u := clamp01(t)
	return u * u * u


static func ease_in_out_sine(t: float) -> float:
	return -(cos(PI * clamp01(t)) - 1.0) * 0.5


## 0 -> 1 -> 0 bump over t in [0, 1].
static func bump(t: float) -> float:
	return sin(PI * clamp01(t))


## Cheap deterministic hash -> [0, 1); per-instance visual jitter only (never gameplay).
static func hash01(n: float) -> float:
	var s := sin(n * 127.1 + 311.7) * 43758.5453123
	return s - floorf(s)


## FNV-1a of a string -> [0, 1).
static func hash_string(s: String) -> float:
	var h: int = 2166136261
	for i: int in s.length():
		h = h ^ s.unicode_at(i)
		h = (h * 16777619) & 0xffffffff
	return float(h) / 4294967296.0


## Deterministic hard stutter in [0, 1] for i-frames and desync (style.ts flickerValue): three
## levels (1, 0.55, 0.1), never a smooth pulse.
static func flicker_value(time: float, seed: float) -> float:
	var a := sin(time * 37.0 + seed * 11.0)
	var b := sin(time * 13.7 + seed * 3.1)
	var c := sin(time * 61.3 + seed * 7.7)
	var v := a * 0.5 + b * 0.35 + c * 0.15
	return 1.0 if v > 0.15 else (0.55 if v > -0.35 else 0.1)
