extends ODTest
## Pure maths of the music visualisers (MUSIC-12, chapter 15): DFT / epicycle decomposition
## (reconstruction error bounds, Parseval, closure, determinism), rosette wrapping, chord snapping,
## pitch-class helix projection and procedural rune glyphs. Run: `bash tools/gd test musicviz`.


func _points(n: int, seed_f: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for j: int in n:
		var t := float(j) / n
		pts.append(Vector2(cos(TAU * t) + 0.3 * sin(TAU * 5.0 * t + seed_f), sin(TAU * t) * 0.8 + 0.2 * cos(TAU * 3.0 * t) + 0.05 * sin(j * 1.7 + seed_f)))
	return pts


func test_music12_dft_all_harmonics_reconstruct_samples_exactly() -> void:
	var pts := _points(64, 0.3)
	var parts := MVFourier.split(pts)
	var hs := MVFourier.dft(parts[0], parts[1])
	assert_eq(hs.size(), 64, "one harmonic per sample")
	assert_near(MVFourier.max_error(parts[0], parts[1], hs), 0.0, 1e-9, "full reconstruction")


func test_music12_dft_parseval_and_monotone_truncation_error() -> void:
	var pts := _points(96, 1.1)
	var parts := MVFourier.split(pts)
	var all := MVFourier.dft(parts[0], parts[1])
	var mean_sq := 0.0
	for j: int in pts.size():
		mean_sq += parts[0][j] * parts[0][j] + parts[1][j] * parts[1][j]
	mean_sq /= pts.size()
	assert_near(MVFourier.energy(all), mean_sq, 1e-9, "Parseval")
	var prev := INF
	for k: int in [1, 2, 4, 8, 16, 32]:
		var top := MVFourier.strongest(all, k, true)
		var rms := MVFourier.rms_error(parts[0], parts[1], top)
		# The residual energy is exactly the discarded harmonics' energy.
		assert_near(rms * rms, MVFourier.energy(all) - MVFourier.energy(top), 1e-9, "residual = discarded energy (k=%d)" % k)
		assert_true(rms <= prev + 1e-12, "error non-increasing with k (k=%d)" % k)
		prev = rms


func test_music12_sixteen_harmonics_exact_for_band_limited_curve() -> void:
	# A curve made of 9 harmonics is rebuilt exactly by its 16 strongest.
	var pts := PackedVector2Array()
	for j: int in 80:
		var t := float(j) / 80.0
		var z := Vector2.ZERO
		for f: int in [-4, -2, -1, 1, 2, 3, 5, 7, 0]:
			var a := TAU * f * t + f * 0.7
			z += Vector2(cos(a), sin(a)) * (1.0 / (1.0 + absf(f)))
		pts.append(z)
	var parts := MVFourier.split(pts)
	var top := MVFourier.strongest(MVFourier.dft(parts[0], parts[1]), 16, true)
	# The samples went through single-precision Vector2, so "exact" is up to float32 rounding.
	assert_near(MVFourier.max_error(parts[0], parts[1], top), 0.0, 1e-6)


func test_music12_strongest_order_and_closure() -> void:
	var pts := _points(48, 2.0)
	var parts := MVFourier.split(pts)
	var top := MVFourier.strongest(MVFourier.dft(parts[0], parts[1]), 16, true)
	assert_eq(top.size(), 17, "DC anchor + 16")
	assert_eq(top[0].freq, 0, "DC first")
	for i: int in range(2, top.size()):
		assert_true(top[i - 1].amp >= top[i].amp - 1e-12, "largest circles first")
	assert_vec_near(MVFourier.evaluate(top, 0.0), MVFourier.evaluate(top, 1.0), 1e-9, "closed curve")
	var ch := MVFourier.chain(top, 0.37, Vector2.ZERO)
	assert_eq(ch.size(), top.size() + 1)
	assert_vec_near(ch[ch.size() - 1], MVFourier.evaluate(top, 0.37), 1e-9, "chain tip traces the curve")
	var tr := MVFourier.trace(top, 0.0, 1.0, 50)
	assert_vec_near(tr[0], tr[tr.size() - 1], 1e-9)


func test_music12_epicycles_of_sandbox_layers_bounded_and_deterministic() -> void:
	var level := ContentData.load_level("sandbox")
	if not assert_true(level != null, "sandbox loads"):
		return
	var m := MVMusic.from_level(level)
	var m2 := MVMusic.from_level(level)
	for i: int in 4:
		for mode: int in [MVEpicycleHologram.MODE_ROSETTE, MVEpicycleHologram.MODE_WAVE]:
			var pts := MVEpicycleHologram.curve_samples(m.layers[i], mode)
			var parts := MVFourier.split(pts)
			var hs := MVEpicycleHologram.harmonics_for(m.layers[i], mode)
			assert_true(hs.size() <= 17)
			var rms := MVFourier.rms_error(parts[0], parts[1], hs)
			# Both curves span about one unit (rosette radius 1, wave -1..1).
			print('[musicviz] layer %d mode %d: 16-harmonic rms %.4f' % [i, mode, rms])
			assert_true(rms < 0.25, "layer %d mode %d: 16-harmonic rms %.4f within bound" % [i, mode, rms])
			assert_true(hs == MVEpicycleHologram.harmonics_for(m.layers[i], mode), "cached per layer")
			var hs2 := MVEpicycleHologram.harmonics_for(m2.layers[i], mode)
			for k: int in hs.size():
				assert_eq(hs2[k].freq, hs[k].freq, "deterministic freq")
				assert_near(hs2[k].amp, hs[k].amp, 0.0, "deterministic amp")


func test_music12_rosette_closure_radius_and_interpolation() -> void:
	var sig := PackedFloat32Array([0.0, 0.5, 1.0, 0.25, 0.75, 0.1, 0.9, 0.4])
	var pts := MVRosette.wrap(sig, 0.4, 1.0, 8, 1, false)
	assert_eq(pts.size(), sig.size() * 8 + 1)
	assert_vec_near(pts[0], pts[pts.size() - 1], 0.0, "closed")
	for p: Vector2 in pts:
		var r := p.length()
		assert_true(r >= 0.4 - 0.15 * 0.6 - 1e-6 and r <= 1.0 + 0.15 * 0.6 + 1e-6, "radius in band")
	for i: int in sig.size():
		assert_near(MVRosette.sample(sig, float(i)), sig[i], 1e-6, "interpolates the samples")
		assert_near(MVRosette.sample_stepped(sig, float(i)), sig[i], 1e-6, "stepped holds the step")
		var p := MVRosette.point(sig, float(i), 0.4, 1.0)
		assert_near(p.length(), 0.4 + 0.6 * sig[i], 1e-5)
	# Step 0 at twelve o'clock.
	assert_vec_near(MVRosette.point(PackedFloat32Array([1.0, 1.0]), 0.0, 0.0, 1.0), Vector2(0, -1), 1e-6)
	var rep := MVRosette.wrap(sig, 0.4, 1.0, 4, 3, true)
	assert_eq(rep.size(), sig.size() * 4 * 3 + 1)
	assert_vec_near(rep[0], rep[rep.size() - 1], 1e-6)


func test_music12_rosette_snaps_to_chord_tones() -> void:
	var sig := PackedFloat32Array()
	for i: int in 32:
		sig.append(fposmod(i * 0.137, 1.0))
	var pcs: Array[int] = [9, 0, 4]
	var out := MVRosette.snap_to_chord(sig, pcs, 45, 62)
	for v: float in out:
		var midi := 45.0 + v * 17.0
		assert_near(midi, roundf(midi), 1e-4, "integer pitch")
		assert_has(pcs, posmod(int(roundf(midi)), 12), "chord tone")
	assert_eq(MVRosette.nearest_with_pcs(61.0, [0, 4, 7]), 60)
	assert_eq(MVRosette.nearest_with_pcs(62.0, [0, 4, 7]), 60, "tie goes low")
	assert_eq(MVRosette.nearest_with_pcs(65.6, [0, 4, 7]), 67)
	var star := MVRosette.chord_star([7, 0, 4], 2.0)
	assert_eq(star.size(), 4)
	assert_vec_near(star[0], star[3], 0.0)
	assert_vec_near(star[0], Vector2(0, -2), 1e-6, "pc 0 at the top")


func test_music12_helix_octaves_stack_and_projection() -> void:
	var tilt := 0.3
	for yaw: float in [0.0, 0.7, 2.5]:
		var a := MVHelix.screen(60.0, yaw, tilt, 1.0, 1.0, 60.0)
		var b := MVHelix.screen(72.0, yaw, tilt, 1.0, 1.0, 60.0)
		assert_near(a.x, b.x, 1e-6, "octave above shares the screen x")
		assert_near(b.y - a.y, -cos(tilt), 1e-6, "one turn = one rise, drawn upward")
		assert_near(a.z, b.z - sin(tilt), 1e-6)
	var front := MVHelix.screen(60.0, 0.0, 0.0)
	assert_vec_near(front, Vector3(0, 0, 1), 1e-6, "C in front at yaw 0")
	var tritone := MVHelix.screen(66.0, 0.0, 0.0)
	assert_near(tritone.z, -1.0, 1e-6, "F# at the back")
	var s := MVHelix.strand(48.0, 72.0, 0.4, tilt, 1.0, 1.0, 60.0, 24)
	assert_eq(s.size(), 49)
	assert_vec_near(s[0], MVHelix.screen(48.0, 0.4, tilt), 1e-6)
	assert_vec_near(s[s.size() - 1], MVHelix.screen(72.0, 0.4, tilt), 1e-6)


func test_music12_rune_glyphs_deterministic_distinct_in_box() -> void:
	var seen := {}
	for i: int in MVGlyphs.GLYPH_COUNT:
		var g := MVGlyphs.glyph(i)
		assert_true(g.size() >= 3, "a stave and branches")
		for st: PackedVector2Array in g:
			for p: Vector2 in st:
				assert_true(p.x >= 0.0 and p.x <= 1.0 and p.y >= 0.0 and p.y <= 1.0, "inside the unit box")
		var sig := MVGlyphs.signature(i)
		assert_false(seen.has(sig), "glyph %d differs from glyph %s" % [i, seen.get(sig, -1)])
		seen[sig] = i
		assert_eq(MVGlyphs.signature(i + MVGlyphs.GLYPH_COUNT), sig, "wraps")


func test_music12_helix_batch_projection_matches_single() -> void:
	var pts := MVHelix.strand3(40.0, 80.0, 1.3, 0.7, 60.0, 24)
	for yaw: float in [0.0, 0.9, 4.0]:
		var all := MVHelix.project_all(pts, yaw, 0.34)
		for i: int in pts.size():
			assert_vec_near(all[i], MVHelix.project(pts[i], yaw, 0.34), 1e-5)
