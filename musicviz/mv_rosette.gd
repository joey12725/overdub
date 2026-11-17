class_name MVRosette
extends RefCounted
## "Shape" (chapter 15): one period of a layer wrapped around a circle as a radial rosette, plus the
## chord star drawn inside the floor sigils. Pure, static, deterministic. Angles start at the top
## (-90°) and run clockwise on screen (y down), so step 0 is always at twelve o'clock.

const TOP := -PI * 0.5


## Periodic Catmull-Rom sample of `sig` (one period, values at integer steps) at fractional step x.
static func sample(sig: PackedFloat32Array, x: float) -> float:
	var n := sig.size()
	if n == 0:
		return 0.0
	if n == 1:
		return sig[0]
	var i := floori(x)
	var f := x - i
	var p0 := sig[posmod(i - 1, n)]
	var p1 := sig[posmod(i, n)]
	var p2 := sig[posmod(i + 1, n)]
	var p3 := sig[posmod(i + 2, n)]
	var f2 := f * f
	var f3 := f2 * f
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f3)


## Sample of `sig` held per step with a short eased glide into the next step (`glide` = fraction of
## the step spent gliding) — the "stepped" look of an integer sequence.
static func sample_stepped(sig: PackedFloat32Array, x: float, glide: float = 0.3) -> float:
	var n := sig.size()
	if n == 0:
		return 0.0
	var i := floori(x)
	var f := x - i
	var a := sig[posmod(i, n)]
	var b := sig[posmod(i + 1, n)]
	var g := clampf((f - (1.0 - glide)) / maxf(1e-6, glide), 0.0, 1.0)
	return lerpf(a, b, g * g * (3.0 - 2.0 * g))


## Angle of fractional step x in a period of n steps repeated `repeats` times around the circle.
static func angle(x: float, n: int, repeats: int = 1) -> float:
	return TOP + TAU * x / float(maxi(1, n * maxi(1, repeats)))


## Point of the rosette for fractional step x: radius r_in + (r_out - r_in) * value.
static func point(sig: PackedFloat32Array, x: float, r_in: float, r_out: float, repeats: int = 1, stepped: bool = false) -> Vector2:
	var n := sig.size()
	var v := sample_stepped(sig, x) if stepped else sample(sig, x)
	var a := angle(x, n, repeats)
	return Vector2(cos(a), sin(a)) * (r_in + (r_out - r_in) * clampf(v, -0.15, 1.15))


## The closed rosette: `per_step` points per step over `repeats` periods; last point == first.
static func wrap(sig: PackedFloat32Array, r_in: float, r_out: float, per_step: int = 8, repeats: int = 1, stepped: bool = false) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := sig.size()
	if n == 0:
		return out
	var total := n * maxi(1, per_step) * maxi(1, repeats)
	out.resize(total + 1)
	for j: int in total:
		var x := float(j) / float(maxi(1, per_step))
		out[j] = point(sig, x, r_in, r_out, repeats, stepped)
	out[total] = out[0]
	return out


## Fraction of the rosette (0..1) covered by the step at fractional step x.
static func fraction(x: float, n: int, repeats: int = 1) -> float:
	return fposmod(x / float(maxi(1, n * maxi(1, repeats))), 1.0)


## One period re-quantised under a chord: each value is mapped into the MIDI range [low, high],
## snapped to the nearest pitch whose pitch class is in `pcs`, and normalised back to 0..1. This is
## the engine's chord gravity made visible — the sigil changes shape when the chord changes.
static func snap_to_chord(sig: PackedFloat32Array, pcs: Array[int], low: int, high: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(sig.size())
	var span := maxf(1.0, float(high - low))
	for i: int in sig.size():
		var midi := float(low) + clampf(sig[i], 0.0, 1.0) * span
		out[i] = (float(nearest_with_pcs(midi, pcs)) - float(low)) / span
	return out


## The integer MIDI pitch nearest to `midi` whose pitch class is in `pcs` (all pitches if empty).
static func nearest_with_pcs(midi: float, pcs: Array[int]) -> int:
	var c := int(round(midi))
	if pcs.is_empty():
		return c
	var best := c
	var best_d := INF
	for p: int in range(c - 7, c + 8):
		if not pcs.has(posmod(p, 12)):
			continue
		var d := absf(float(p) - midi)
		if d < best_d - 1e-9:
			best_d = d
			best = p
	return best


## Vertices of the chord star: each pitch class of `pcs` on a 12-gon of radius r (pc 0 at the top),
## in pitch-class order, closed.
static func chord_star(pcs: Array[int], r: float, rotate_pc: int = 0) -> PackedVector2Array:
	var sorted: Array[int] = []
	for p: int in pcs:
		var q := posmod(p - rotate_pc, 12)
		if not sorted.has(q):
			sorted.append(q)
	sorted.sort()
	var out := PackedVector2Array()
	for q: int in sorted:
		var a := TOP + TAU * float(q) / 12.0
		out.append(Vector2(cos(a), sin(a)) * r)
	if out.size() > 0:
		out.append(out[0])
	return out
