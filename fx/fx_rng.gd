class_name FxRng
extends RefCounted
## Small, fast, deterministic PRNG for effects (mulberry32, as prototype/src/render/fx/curves.ts Rng).
## Effects never use randf(): each event reseeds from its own fields, so a replay looks the same every
## time and screenshots are reproducible. 32-bit unsigned arithmetic is emulated on GDScript's 64-bit
## ints with explicit masking.

const MASK := 0xFFFFFFFF

var _s: int = 1


func _init(p_seed: int = 1) -> void:
	_s = p_seed & MASK


func reseed(p_seed: int) -> void:
	_s = p_seed & MASK


## Uniform in [0, 1).
func next() -> float:
	_s = (_s + 0x6D2B79F5) & MASK
	var t := _s
	t = imul(t ^ (t >> 15), t | 1)
	t ^= (t + imul(t ^ (t >> 7), t | 61)) & MASK
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0


func range_f(a: float, b: float) -> float:
	return a + (b - a) * next()


## Symmetric in [-a, a).
func sym(a: float) -> float:
	return (next() * 2.0 - 1.0) * a


## Math.imul for unsigned 32-bit inputs: the low 32 bits of a * b.
static func imul(a: int, b: int) -> int:
	a &= MASK
	b &= MASK
	var lo := (a & 0xFFFF) * b
	var hi := ((a >> 16) & 0xFFFF) * b
	return (lo + ((hi & 0xFFFF) << 16)) & MASK


## Integer hash of a few numbers, for seeding per-event / per-tile randomness (curves.ts hash4).
static func hash4(a: int, b: int, c: int, d: int) -> int:
	var h := 0x811C9DC5
	h = imul(h ^ (a & MASK), 0x01000193)
	h = imul(h ^ (b & MASK), 0x01000193)
	h = imul(h ^ (c & MASK), 0x01000193)
	h = imul(h ^ (d & MASK), 0x01000193)
	h ^= h >> 13
	h = imul(h, 0x5BD1E995)
	h ^= h >> 15
	return h & MASK
