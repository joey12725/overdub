class_name FxCurves
extends RefCounted
## Deterministic curve generators for the music-linked environment (MUSIC-12): Lissajous and rose
## floor sigils, the Epicycles-style Fourier hologram and procedural rune glyphs (port of
## prototype/src/render/fx/curves.ts).
##
## Pure math, no nodes. Point lists are PackedVector2Array in the unit square [-1, 1]^2; the
## generators write into a caller-owned array (resized when too small) so per-frame paths reuse it.

const TAU_F := TAU


## Parameters of one floor sigil. Either a Lissajous (a, b, delta) or a rose (p / q).
class SigilParams:
	extends RefCounted
	var rose: bool = false
	var a: float = 1.0
	var b: float = 2.0
	var delta: float = 0.0
	var p: float = 3.0
	var q: float = 1.0

	func equals(o: SigilParams) -> bool:
		return rose == o.rose and a == o.a and b == o.b and delta == o.delta and p == o.p and q == o.q

	func describe() -> String:
		return ("rose %d/%d" % [int(p), int(q)]) if rose else ("lissajous %d:%d d%.3f" % [int(a), int(b), delta])


const LISSAJOUS_RATIOS: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(3, 2), Vector2i(3, 4), Vector2i(5, 4), Vector2i(2, 3), Vector2i(5, 6), Vector2i(4, 5),
]
const ROSE_RATIOS: Array[Vector2i] = [
	Vector2i(3, 1), Vector2i(2, 1), Vector2i(5, 2), Vector2i(5, 3), Vector2i(7, 4), Vector2i(4, 3), Vector2i(3, 2),
]


static func _ensure(out: PackedVector2Array, n: int) -> void:
	if out.size() < n:
		out.resize(n)


## Lissajous figure x = sin(a t + delta), y = sin(b t) over one full period t in [0, 2 pi].
## With integer a, b the figure is closed; `n` points are written and the last equals the first.
static func lissajous(out: PackedVector2Array, n: int, a: float, b: float, delta: float) -> PackedVector2Array:
	_ensure(out, n)
	var last := n - 1
	for i: int in n:
		var t := (0.0 if i == last else float(i) / float(last)) * TAU_F
		out[i] = Vector2(sin(a * t + delta), sin(b * t))
	return out


static func gcd(a: int, b: int) -> int:
	a = absi(a)
	b = absi(b)
	while b != 0:
		var t := a % b
		a = b
		b = t
	return a if a != 0 else 1


## Rose curve r = cos(k theta) with k = p / q (reduced). The curve closes after theta = 2 pi q, so
## sampling over that range always yields a closed figure; the last point is written equal to the first.
static func rose(out: PackedVector2Array, n: int, p: float, q: float) -> PackedVector2Array:
	_ensure(out, n)
	var g := gcd(roundi(p), roundi(q))
	var pp := float(roundi(p)) / float(g)
	var qq := maxf(1.0, float(roundi(q)) / float(g))
	var k := pp / qq
	var span := TAU_F * qq
	var last := n - 1
	for i: int in n:
		var th := (0.0 if i == last else float(i) / float(last)) * span
		var r := cos(k * th)
		out[i] = Vector2(r * cos(th), r * sin(th))
	return out


static func _wrap64(v: float) -> int:
	return ((roundi(v) % 64) + 64) % 64


## Sigil shape for a chord index. The same chord always yields the same figure (so the floor reads as
## a notation of the progression); `variant` lets several sigils in one room differ.
static func sigil_params_for_chord(chord: float, variant: float, out: SigilParams) -> SigilParams:
	var c := _wrap64(chord)
	var v := _wrap64(variant)
	out.rose = (c + v) % 2 == 1
	var lr: Vector2i = LISSAJOUS_RATIOS[(c * 3 + v) % LISSAJOUS_RATIOS.size()]
	var rr: Vector2i = ROSE_RATIOS[(c * 5 + v * 2) % ROSE_RATIOS.size()]
	out.a = lr.x
	out.b = lr.y
	out.delta = (PI / 8.0) * float((c + v * 3) % 8)
	out.p = rr.x
	out.q = rr.y
	return out


## Write the sigil figure for `params` into `out` (n points, closed).
static func sigil_points(out: PackedVector2Array, n: int, params: SigilParams) -> PackedVector2Array:
	return rose(out, n, params.p, params.q) if params.rose else lissajous(out, n, params.a, params.b, params.delta)


## Discrete Fourier transform of a real periodic signal of length n (O(n^2); n is small, ~64).
## Writes bins 0..n-1 into re / im (resized to n).
static func dft(sig: PackedFloat32Array, n: int, re: PackedFloat32Array, im: PackedFloat32Array) -> void:
	if re.size() < n:
		re.resize(n)
	if im.size() < n:
		im.resize(n)
	for k: int in n:
		var sr := 0.0
		var si := 0.0
		for t: int in n:
			var ang := (TAU_F * k * t) / n
			sr += sig[t] * cos(ang)
			si -= sig[t] * sin(ang)
		re[k] = sr
		im[k] = si


## Pick the `count` strongest harmonics (frequencies 1..n/2) of a real signal's DFT, strongest first,
## as epicycles: amplitude and phase such that the signal ~= dc + sum amp cos(freq theta + phase).
## Returns how many were written (<= count). The outputs must hold `count` entries.
static func strongest_harmonics(re: PackedFloat32Array, im: PackedFloat32Array, n: int, count: int, out_freq: PackedFloat32Array, out_amp: PackedFloat32Array, out_phase: PackedFloat32Array) -> int:
	var filled := 0
	var half := n >> 1
	for k: int in range(1, half + 1):
		# Real signal: bins k and n-k are conjugates, so the k-th cosine has amplitude 2|X_k|/n
		# (Nyquist bin counted once).
		var scale := (1.0 / n) if (k == half and n % 2 == 0) else (2.0 / n)
		var amp := Vector2(re[k], im[k]).length() * scale
		if not (amp > 1e-9):
			continue
		var phase := atan2(im[k], re[k])
		var pos := filled if filled < count else count
		while pos > 0 and out_amp[pos - 1] < amp:
			pos -= 1
		if pos >= count:
			continue
		var end := mini(filled, count - 1)
		var j := end
		while j > pos:
			out_freq[j] = out_freq[j - 1]
			out_amp[j] = out_amp[j - 1]
			out_phase[j] = out_phase[j - 1]
			j -= 1
		out_freq[pos] = k
		out_amp[pos] = amp
		out_phase[pos] = phase
		if filled < count:
			filled += 1
	return filled


## Centres of a chain of nested rotating circles at angle theta: point 0 is the origin, point i+1 is
## the tip after circle i. Writes (count + 1) points. Circle i has radius amp[i] and turns at freq[i]
## (integer => the tip's path closes after theta = 2 pi).
static func epicycle_chain(freq: PackedFloat32Array, amp: PackedFloat32Array, phase: PackedFloat32Array, count: int, theta: float, out: PackedVector2Array) -> PackedVector2Array:
	_ensure(out, count + 1)
	var x := 0.0
	var y := 0.0
	out[0] = Vector2.ZERO
	for i: int in count:
		var a := freq[i] * theta + phase[i]
		x += amp[i] * cos(a)
		y += amp[i] * sin(a)
		out[i + 1] = Vector2(x, y)
	return out


## The epicycle tip's full path over theta in [0, 2 pi]: n points, last equals first for integer freqs.
static func epicycle_trace(freq: PackedFloat32Array, amp: PackedFloat32Array, phase: PackedFloat32Array, count: int, n: int, out: PackedVector2Array) -> PackedVector2Array:
	_ensure(out, n)
	var last := n - 1
	for s: int in n:
		var th := (0.0 if s == last else float(s) / float(last)) * TAU_F
		var x := 0.0
		var y := 0.0
		for i: int in count:
			var a := freq[i] * th + phase[i]
			x += amp[i] * cos(a)
			y += amp[i] * sin(a)
		out[s] = Vector2(x, y)
	return out


## Points on a circle (closed: last equals first).
static func circle_points(out: PackedVector2Array, n: int, cx: float, cy: float, r: float) -> PackedVector2Array:
	_ensure(out, n)
	var last := n - 1
	for i: int in n:
		var a := (0.0 if i == last else float(i) / float(last)) * TAU_F
		out[i] = Vector2(cx + r * cos(a), cy + r * sin(a))
	return out


## A procedural rune glyph inside the unit cell [-1, 1]^2: a few angular strokes on a 3x3 lattice, so
## glyphs feel engraved and machine-cut rather than like generic fantasy letters (chapter 18 runes).
## Each stroke is a polyline of 2-3 lattice points. Called at level load only.
static func rune_glyph(p_seed: int) -> Array[PackedVector2Array]:
	var rng := FxRng.new(p_seed)
	var strokes: Array[PackedVector2Array] = []
	# A spine gives every glyph a readable vertical body, like inscribed machine marks.
	var spine_x := 1 if rng.next() < 0.5 else (0 if rng.next() < 0.5 else 2)
	strokes.append(PackedVector2Array([_lattice(spine_x, 0), _lattice(spine_x, 2)]))
	var extra := 1 + int(floor(rng.next() * 3.0))
	for _s: int in extra:
		var pts := 2 + (1 if rng.next() < 0.45 else 0)
		var stroke := PackedVector2Array()
		var cx := int(floor(rng.next() * 3.0))
		var cy := int(floor(rng.next() * 3.0))
		stroke.append(_lattice(cx, cy))
		for _p: int in range(1, pts):
			var nx := cx
			var ny := cy
			# Step to a different lattice point (orthogonal or diagonal), never staying put.
			var guard := 0
			while guard < 8 and nx == cx and ny == cy:
				nx = clampi(cx + int(floor(rng.next() * 3.0)) - 1, 0, 2)
				ny = clampi(cy + int(floor(rng.next() * 3.0)) - 1, 0, 2)
				guard += 1
			if nx == cx and ny == cy:
				nx = 0 if cx == 1 else 1
			stroke.append(_lattice(nx, ny))
			cx = nx
			cy = ny
		strokes.append(stroke)
	return strokes


static func _lattice(ix: int, iy: int) -> Vector2:
	return Vector2((ix - 1) * 0.8, (iy - 1) * 0.8)


## True when every point in the first `count` entries is finite (all when len < 0).
static func all_finite(arr: PackedVector2Array, count: int = -1) -> bool:
	var n := arr.size() if count < 0 else mini(count, arr.size())
	for i: int in n:
		var v := arr[i]
		if not (is_finite(v.x) and is_finite(v.y)):
			return false
	return true


## True when the first and n-th point coincide within eps.
static func is_closed(arr: PackedVector2Array, n: int, eps: float = 1e-5) -> bool:
	return n >= 2 and arr[0].distance_to(arr[n - 1]) < eps
