extends ODTest
## Curve generators and momentum tiers (port of prototype/tests/render-fx/curves.test.ts).


func test_lissajous_finite_bounded_closed() -> void:
	for ab: Vector2i in [Vector2i(1, 2), Vector2i(3, 2), Vector2i(5, 4), Vector2i(7, 6)]:
		var n := 200
		var out := FxCurves.lissajous(PackedVector2Array(), n, ab.x, ab.y, PI / 5.0)
		assert_true(FxCurves.all_finite(out), "finite %s" % ab)
		assert_true(FxCurves.is_closed(out, n), "closed %s" % ab)
		var bounded := true
		for p: Vector2 in out:
			if absf(p.x) > 1.0 + 1e-6 or absf(p.y) > 1.0 + 1e-6:
				bounded = false
		assert_true(bounded, "bounded %s" % ab)


func test_rose_closes_for_rational_k() -> void:
	for pq: Vector2i in [Vector2i(3, 1), Vector2i(2, 1), Vector2i(5, 2), Vector2i(5, 3), Vector2i(7, 4), Vector2i(6, 4)]:
		var n := 300
		var out := FxCurves.rose(PackedVector2Array(), n, pq.x, pq.y)
		assert_true(FxCurves.all_finite(out), "finite %s" % pq)
		assert_true(FxCurves.is_closed(out, n), "closed %s" % pq)
		var bounded := true
		for p: Vector2 in out:
			if p.length() > 1.0 + 1e-6:
				bounded = false
		assert_true(bounded, "bounded %s" % pq)


func test_sigil_params_deterministic_and_varied() -> void:
	var shapes := {}
	for chord: int in 8:
		var a := FxCurves.sigil_params_for_chord(chord, 1, FxCurves.SigilParams.new())
		var b := FxCurves.sigil_params_for_chord(chord, 1, FxCurves.SigilParams.new())
		assert_true(a.equals(b), "deterministic for chord %d" % chord)
		shapes[a.describe()] = true
		var pts := FxCurves.sigil_points(PackedVector2Array(), 160, a)
		assert_true(FxCurves.all_finite(pts), "finite sigil %d" % chord)
		assert_true(FxCurves.is_closed(pts, 160), "closed sigil %d (%s)" % [chord, a.describe()])
	assert_true(shapes.size() > 3, "the progression yields varied figures (%d)" % shapes.size())
	# Negative / non-integer chord indices are tolerated.
	var neg := FxCurves.sigil_params_for_chord(-3.4, 0, FxCurves.SigilParams.new())
	assert_true(FxCurves.all_finite(FxCurves.sigil_points(PackedVector2Array(), 64, neg)), "negative chord ok")


func test_epicycle_trace_finite_and_closed() -> void:
	var freq := PackedFloat32Array([1, 2, 3, 5, 8])
	var amp := PackedFloat32Array([0.5, 0.25, 0.12, 0.06, 0.03])
	var phase := PackedFloat32Array([0, 1, 2, 0.5, 3])
	var n := 256
	var out := FxCurves.epicycle_trace(freq, amp, phase, 5, n, PackedVector2Array())
	assert_true(FxCurves.all_finite(out), "finite")
	assert_true(FxCurves.is_closed(out, n, 1e-5), "closed")
	var chain := FxCurves.epicycle_chain(freq, amp, phase, 5, 0.0, PackedVector2Array())
	assert_eq(chain[0], Vector2.ZERO, "chain starts at the origin")
	assert_vec_near(chain[5], out[0], 1e-5, "chain tip = trace start")


func test_strongest_harmonics_recovers_known_signal() -> void:
	var n := 64
	var sig := PackedFloat32Array()
	sig.resize(n)
	for t: int in n:
		var th := TAU * t / n
		sig[t] = 0.2 + 0.7 * cos(3.0 * th + 0.4) + 0.3 * cos(7.0 * th - 1.1) + 0.1 * cos(12.0 * th)
	var re := PackedFloat32Array()
	var im := PackedFloat32Array()
	FxCurves.dft(sig, n, re, im)
	var f := PackedFloat32Array()
	var a := PackedFloat32Array()
	var p := PackedFloat32Array()
	f.resize(16)
	a.resize(16)
	p.resize(16)
	var cnt := FxCurves.strongest_harmonics(re, im, n, 16, f, a, p)
	assert_true(cnt >= 3, "found the components")
	assert_eq([f[0], f[1], f[2]], [3.0, 7.0, 12.0], "strongest first")
	assert_near(a[0], 0.7, 1e-3, "amp 0")
	assert_near(a[1], 0.3, 1e-3, "amp 1")
	assert_near(p[0], 0.4, 1e-3, "phase 0")
	for i: int in range(1, cnt):
		assert_true(a[i] <= a[i - 1], "sorted by amplitude")
	for t: int in range(0, n, 5):
		var th := TAU * t / n
		var v := re[0] / n
		for i: int in cnt:
			v += a[i] * cos(f[i] * th + p[i])
		assert_near(v, sig[t], 1e-3, "reconstruction at %d" % t)


func test_rune_glyphs_deterministic_and_inside_cell() -> void:
	for s: int in 50:
		var g1 := FxCurves.rune_glyph(s * 7919)
		var g2 := FxCurves.rune_glyph(s * 7919)
		assert_eq(g1.size(), g2.size(), "deterministic stroke count")
		assert_true(g1.size() >= 2, "spine plus at least one stroke")
		for k: int in g1.size():
			assert_eq(g1[k], g2[k], "deterministic stroke")
			assert_true(g1[k].size() >= 2, "a stroke has at least two points")
			for v: Vector2 in g1[k]:
				if absf(v.x) > 0.8 + 1e-6 or absf(v.y) > 0.8 + 1e-6:
					fail("glyph point outside the cell: %s" % v)


func test_rng_is_deterministic_and_in_range() -> void:
	var a := FxRng.new(12345)
	var b := FxRng.new(12345)
	var ok := true
	for _i: int in 200:
		var x := a.next()
		if x != b.next() or x < 0.0 or x >= 1.0:
			ok = false
	assert_true(ok, "same seed, same stream in [0,1)")
	# Matches the prototype's mulberry32 for seed 1 (first value 0.6270739405881613).
	assert_near(FxRng.new(1).next(), 0.6270739405881613, 1e-12, "mulberry32 parity")
	assert_eq(FxRng.hash4(1, 2, 3, 4), FxRng.hash4(1, 2, 3, 4), "hash deterministic")
	assert_ne(FxRng.hash4(1, 2, 3, 4), FxRng.hash4(1, 2, 3, 5), "hash varies")


func test_momentum_tiers() -> void:
	assert_eq(FxWords.momentum_tier(10.0, 10.0), 1, "1x = HIT")
	assert_eq(FxWords.momentum_tier(4.0, 10.0), 0, "weak = TAP")
	assert_eq(FxWords.momentum_tier(20.0, 10.0), 2, "2x")
	assert_eq(FxWords.momentum_tier(30.0, 10.0), 3, "3x")
	assert_eq(FxWords.momentum_tier(100.0, 10.0), 4, "OVERDUB")
	assert_eq(FxWords.momentum_tier(-5.0, 10.0), 0, "negative")
	assert_eq(FxWords.momentum_tier(5.0, 0.0), 4, "zero reference")
	assert_eq(FxWords.TIER_THRESHOLDS.size(), 5, "five tiers")
	assert_eq(FxWords.WORDS.size(), 17, "word list")
