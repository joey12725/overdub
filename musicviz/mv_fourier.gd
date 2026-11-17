class_name MVFourier
extends RefCounted
## Discrete Fourier decomposition of a closed curve into epicycles (chapter 15 "Epicycles": a contour
## rebuilt from its sixteen strongest Fourier harmonics as nested rotating circles). Pure, static,
## deterministic. Samples are complex numbers z_n = re_n + i·im_n, n = 0..N-1, one full period.
##
##   X_k = (1/N) Σ z_n e^{-2πi k n / N},   k signed in (-N/2, N/2]
##   z(t) = Σ_k X_k e^{2πi k t},  t ∈ [0, 1)
##
## Each harmonic is a circle of radius |X_k| turning k times per period; chained tip to tail (largest
## first) the last tip traces the curve. Keeping all N harmonics reproduces the samples exactly
## (up to rounding); keeping the K strongest leaves a residual whose energy is exactly the energy of
## the discarded harmonics (Parseval), so the error falls monotonically with K.

const DEFAULT_COUNT := 16


class Harmonic:
	extends RefCounted
	## Signed frequency: turns per period.
	var freq: int = 0
	var amp: float = 0.0
	var phase: float = 0.0
	var re: float = 0.0
	var im: float = 0.0


## Every harmonic of the samples, in frequency order 0, 1, ..., N/2, -(N/2-1), ..., -1.
static func dft(re: PackedFloat64Array, im: PackedFloat64Array) -> Array[Harmonic]:
	var n := re.size()
	var out: Array[Harmonic] = []
	if n == 0:
		return out
	for k: int in n:
		var sr := 0.0
		var si := 0.0
		for j: int in n:
			var a := -TAU * float(k * j % n) / float(n)
			var c := cos(a)
			var s := sin(a)
			var xr := re[j]
			var xi := im[j] if j < im.size() else 0.0
			sr += xr * c - xi * s
			si += xr * s + xi * c
		var h := Harmonic.new()
		h.freq = k if k <= n / 2 else k - n
		h.re = sr / n
		h.im = si / n
		h.amp = sqrt(h.re * h.re + h.im * h.im)
		h.phase = atan2(h.im, h.re)
		out.append(h)
	return out


## The DC term (freq 0) of a harmonic list, or null.
static func dc(hs: Array[Harmonic]) -> Harmonic:
	for h: Harmonic in hs:
		if h.freq == 0:
			return h
	return null


## The `count` strongest non-DC harmonics, largest first (ties: lower |freq|, then positive first),
## preceded by the DC term when `with_dc`. This order is the epicycle chain.
static func strongest(hs: Array[Harmonic], count: int = DEFAULT_COUNT, with_dc: bool = true) -> Array[Harmonic]:
	var rest: Array[Harmonic] = []
	for h: Harmonic in hs:
		if h.freq != 0:
			rest.append(h)
	rest.sort_custom(_stronger)
	var out: Array[Harmonic] = []
	if with_dc:
		var d := dc(hs)
		if d != null:
			out.append(d)
	for i: int in mini(count, rest.size()):
		out.append(rest[i])
	return out


static func _stronger(a: Harmonic, b: Harmonic) -> bool:
	# Exact comparison keeps the order a strict weak ordering (an approximate tie test is not
	# transitive and can let a smaller circle precede a larger one); the DFT is deterministic, so
	# exact ties are reproducible.
	if a.amp != b.amp:
		return a.amp > b.amp
	if absi(a.freq) != absi(b.freq):
		return absi(a.freq) < absi(b.freq)
	return a.freq > b.freq


## The curve point at t ∈ [0, 1) from the given harmonics.
static func evaluate(hs: Array[Harmonic], t: float) -> Vector2:
	var p := Vector2.ZERO
	for h: Harmonic in hs:
		var a := TAU * h.freq * t + h.phase
		p += Vector2(cos(a), sin(a)) * h.amp
	return p


## The epicycle chain at t: [centre of the first circle, tip after each harmonic...]. The last point
## is the traced point; point i is the centre of circle i (radius hs[i].amp).
static func chain(hs: Array[Harmonic], t: float, origin: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	var p := origin
	out.append(p)
	for h: Harmonic in hs:
		var a := TAU * h.freq * t + h.phase
		p += Vector2(cos(a), sin(a)) * h.amp
		out.append(p)
	return out


## `count` points of the reconstructed curve over t ∈ [t0, t1] (inclusive ends).
static func trace(hs: Array[Harmonic], t0: float, t1: float, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(maxi(2, count))
	var n := out.size()
	for i: int in n:
		out[i] = evaluate(hs, lerpf(t0, t1, float(i) / float(n - 1)))
	return out


## evaluate() in double precision (Vector2 is single precision): [x, y].
static func evaluate64(hs: Array[Harmonic], t: float) -> PackedFloat64Array:
	var x := 0.0
	var y := 0.0
	for h: Harmonic in hs:
		var a := TAU * h.freq * t + h.phase
		x += cos(a) * h.amp
		y += sin(a) * h.amp
	return PackedFloat64Array([x, y])


## Squared distance (double precision) between sample j and the reconstruction at t = j / N.
static func _err2(re: PackedFloat64Array, im: PackedFloat64Array, hs: Array[Harmonic], j: int) -> float:
	var p := evaluate64(hs, float(j) / float(re.size()))
	var dx := p[0] - re[j]
	var dy := p[1] - (im[j] if j < im.size() else 0.0)
	return dx * dx + dy * dy


## The reconstructed curve as a closed table: `count` + 1 points at t = j / count (last == first).
## Drawers precompute it once per layer and read arcs from it instead of re-evaluating the series.
static func table(hs: Array[Harmonic], count: int = 512) -> PackedVector2Array:
	var out := trace(hs, 0.0, 1.0, maxi(4, count) + 1)
	out[out.size() - 1] = out[0]
	return out


## The point of a closed table() at curve parameter t (any real; wraps), linearly interpolated.
static func table_at(tab: PackedVector2Array, t: float) -> Vector2:
	var n := tab.size() - 1
	if n < 1:
		return Vector2.ZERO
	var x := fposmod(t, 1.0) * n
	var i := floori(x)
	return tab[i].lerp(tab[mini(i + 1, n)], x - i)


## The arc of a closed table() from parameter t0 to t1 (either order, wrapping; at most one full
## turn), as a polyline running from t0 to t1.
static func arc(tab: PackedVector2Array, t0: float, t1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := tab.size() - 1
	if n < 1:
		return out
	var lo := minf(t0, t1)
	var hi := minf(maxf(t0, t1), lo + 1.0)
	out.append(table_at(tab, lo))
	var k := floori(lo * n) + 1
	while float(k) < hi * n:
		out.append(tab[posmod(k, n)])
		k += 1
	out.append(table_at(tab, hi))
	if t1 < t0:
		out.reverse()
	return out


## Root-mean-square distance between the samples and the reconstruction at t = n / N.
static func rms_error(re: PackedFloat64Array, im: PackedFloat64Array, hs: Array[Harmonic]) -> float:
	var n := re.size()
	if n == 0:
		return 0.0
	var e := 0.0
	for j: int in n:
		e += _err2(re, im, hs, j)
	return sqrt(e / n)


## Largest distance between the samples and the reconstruction.
static func max_error(re: PackedFloat64Array, im: PackedFloat64Array, hs: Array[Harmonic]) -> float:
	var m := 0.0
	for j: int in re.size():
		m = maxf(m, _err2(re, im, hs, j))
	return sqrt(m)


## Sum of |X_k|^2 over the given harmonics (Parseval: equals the mean of |z_n|^2 over all of them).
static func energy(hs: Array[Harmonic]) -> float:
	var e := 0.0
	for h: Harmonic in hs:
		e += h.amp * h.amp
	return e


## Complex samples from points (x -> re, y -> im).
static func split(points: PackedVector2Array) -> Array[PackedFloat64Array]:
	var re := PackedFloat64Array()
	var im := PackedFloat64Array()
	re.resize(points.size())
	im.resize(points.size())
	for i: int in points.size():
		re[i] = points[i].x
		im[i] = points[i].y
	return [re, im]
