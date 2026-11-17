class_name WorldRng
extends RefCounted
## Deterministic randomness for set dressing (port of prototype render/env/rng.ts). The environment
## must look identical every time a level loads (and between record, review and the cinematic), so
## the world never calls randf(): every choice is derived from the level id and tile coordinates.
## All maths is 32-bit unsigned, bit-identical to the prototype's Math.imul versions.

const MASK := 0xFFFFFFFF

var _s: int = 0


func _init(p_seed: int = 0) -> void:
	_s = p_seed & MASK


## Low 32 bits of a * b for 32-bit unsigned a, b (Math.imul without signed overflow).
static func imul(a: int, b: int) -> int:
	a &= MASK
	b &= MASK
	var lo := a * (b & 0xFFFF)
	var hi := (a * (b >> 16)) & 0xFFFF
	return (lo + (hi << 16)) & MASK


## FNV-1a 32-bit hash of a string (UTF-16 code units, like the prototype's charCodeAt).
static func hash_string(s: String) -> int:
	var h := 0x811c9dc5
	for i: int in range(s.length()):
		h ^= s.unicode_at(i) & 0xFFFF
		h = imul(h, 0x01000193)
	return h & MASK


## Integer mix of a seed with two coordinates.
static func hash3(p_seed: int, a: int, b: int) -> int:
	var h := ((p_seed & MASK) ^ imul(a, 0x27d4eb2d) ^ imul(b, 0x165667b1)) & MASK
	h = imul(h ^ (h >> 15), 0x85ebca6b)
	h = imul(h ^ (h >> 13), 0xc2b2ae35)
	return (h ^ (h >> 16)) & MASK


## Uniform 0..1 value for a tile, stable for a given seed.
static func tile_noise(p_seed: int, c: int, r: int) -> float:
	return float(hash3(p_seed, c, r)) / 4294967296.0


## Next value 0..1 (mulberry32).
func next() -> float:
	_s = (_s + 0x6d2b79f5) & MASK
	var t := _s
	t = imul(t ^ (t >> 15), t | 1)
	t ^= (t + imul(t ^ (t >> 7), t | 61)) & MASK
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0


func range_f(a: float, b: float) -> float:
	return a + (b - a) * next()


## Integer in [a, b_inclusive].
func range_i(a: int, b_inclusive: int) -> int:
	return a + int(floor(next() * float(b_inclusive - a + 1)))


func chance(p: float) -> bool:
	return next() < p


func pick_color(items: Array[Color]) -> Color:
	return items[int(floor(next() * items.size())) % items.size()]
