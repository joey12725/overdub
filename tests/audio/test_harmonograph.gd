extends ODTest
## Behaviour of the GDScript Harmonograph port beyond the JS goldens (test_harmonograph_goldens.gd):
## the public API, determinism, deterministic seeking, the power-of-two speed grid (MUSIC-03),
## every formula in every role, thread safety and cost. Run with `bash tools/gd test harmonograph`.


func _band(formula: String = "lorenz") -> HGState:
	var s := Harmonograph.make_state()
	s.root = 2
	s.scale = "Dorian"
	s.tempo = 120.0
	s.progression = [0, 3, 4, 0]
	s.chord_rate = 8.0
	var mel := Harmonograph.channel(0)
	mel.set_formula(formula)
	mel.rate = 0.5
	mel.set_gate("euclid", {"k": 5.0, "n": 8.0, "rot": 0.0})
	var bass := Harmonograph.channel(2)
	bass.id = 1
	bass.rate = 0.5
	bass.palette = 0
	var keys := Harmonograph.channel(3)
	keys.id = 2
	keys.rate = 2.0
	var kit := Harmonograph.channel(4)
	kit.id = 3
	Harmonograph.apply_genre(_tmp_state(kit), 0, "Boom bap")
	s.channels = [mel, bass, keys, kit]
	return s


func _tmp_state(c: HGChannel) -> HGState:
	var s := Harmonograph.make_state()
	s.channels = [c]
	return s


func _sig(notes: Array[HGNote]) -> Array:
	var out: Array = []
	for n: HGNote in notes:
		out.append([n.pitch, n.velocity, n.beat, n.duration, n.step, n.lane])
	return out


func test_catalogue_is_complete_and_consistent() -> void:
	var ids := Harmonograph.formula_ids()
	assert_eq(ids.size(), 66, "all 66 engine formulas are ported")
	var seen: Dictionary = {}
	for f: HGFormula in Harmonograph.catalogue():
		assert_false(seen.has(f.id), "unique id " + f.id)
		seen[f.id] = true
		assert_true(HGFormula.CATEGORIES.has(f.category), f.id + " category")
		assert_true(f.equation != "" and f.name != "", f.id + " has a name and equation")
		for p: HGParamDef in f.params:
			assert_true(p.value >= p.min_value and p.value <= p.max_value, "%s.%s default in range" % [f.id, p.key])
		assert_eq(Harmonograph.defaults(f.id).size(), f.params.size(), f.id + " defaults")
	assert_true(Harmonograph.has_formula("lorenz"), "has_formula")
	assert_false(Harmonograph.has_formula("nope"), "unknown id")
	assert_eq(Harmonograph.get_formula("nope"), null, "get_formula of an unknown id is null")
	# The engine's fallback: an unknown id evaluates as fibonacci.
	assert_eq(Harmonograph.value("nope", 9.0), Harmonograph.value("fibonacci", 9.0), "unknown id falls back to fibonacci")


func test_clean_params_clamps_rounds_and_fills() -> void:
	var p := Harmonograph.clean_params("euclid", {"k": 40.0, "n": 7.5, "junk": 3.0})
	assert_eq(p, {"k": 32.0, "n": 8.0, "rot": 0.0}, "clamped, rounded (JS Math.round), defaulted, unknown key dropped")
	var q := Harmonograph.clean_params("logistic", {"r": NAN})
	assert_eq(q["r"], 2.5, "non-finite becomes the minimum (engine clamp)")
	assert_eq(HGMath.js_round(-2.5), -2.0, "JS Math.round rounds halves up")
	assert_eq(HGMath.js_round(2.5), 3.0, "JS Math.round")
	assert_eq(HGMath.mod(-7.0, 3.0), 2.0, "mod of a negative")
	assert_eq(HGMath.to_int32(4294967301.0), 5, "ToInt32 wraps")
	assert_eq(HGMath.to_int32(2147483648.0), -2147483648, "ToInt32 sign")
	assert_eq(HGMath.shr(-8.0, 1.0), -4.0, "arithmetic >>")


func test_every_formula_is_finite_and_bounded() -> void:
	# value() is finite and normal() in 0..1 for every formula at three parameter points, at
	# integer, fractional and negative steps.
	var bad: PackedStringArray = []
	for f: HGFormula in Harmonograph.catalogue():
		for frac: float in [0.0, 0.5, 1.0]:
			var p: Dictionary[String, float] = {}
			for d: HGParamDef in f.params:
				p[d.key] = d.min_value + (d.max_value - d.min_value) * frac
			for i: int in range(-8, 200, 3):
				var n: float = float(i) * 0.75
				var v := Harmonograph.value(f.id, n, p, 16.0)
				var nv := Harmonograph.normal(f.id, n, p, 16.0)
				if not is_finite(v) or not (nv >= 0.0 and nv <= 1.0):
					bad.append("%s %s n=%s: %s / %s" % [f.id, JSON.stringify(p), n, v, nv])
					break
	assert_true(bad.is_empty(), "\n  ".join(bad))


func test_every_formula_compiles_in_every_role() -> void:
	# MUSIC-02: level designers may pick any formula; each must give valid notes as a melody, bass,
	# chord or drum-formula contour.
	var problems: PackedStringArray = []
	var silent: PackedStringArray = []
	var produced: int = 0
	for id: String in Harmonograph.formula_ids():
		var s := _band(id)
		s.channels[1].set_formula(id)
		s.channels[2].set_formula(id)
		var kit: HGChannel = s.channels[3]
		kit.set_formula(id)
		kit.drum_lane = 2
		kit.drum_formula = true
		kit.drum_velocity = "formula"
		for i: int in s.channels.size():
			var c: HGChannel = s.channels[i]
			var notes := Harmonograph.compile_channel(s, i, 0.0, 2.0)
			if notes.is_empty():
				# A drum lane triggered by the formula fires only where normal() reaches the lane
				# threshold. Some formulas at their defaults never do (kolakoski/beatty top out at
				# 2/7, times/plr sit at 0, voicelead at 2/7) -- the JS engine is silent there too.
				# Only unexplained silence is a failure.
				var explained := false
				if c.type == "Drums" and c.drum_formula:
					explained = true
					for k: int in 64:
						if Harmonograph.normal(id, float(k), c.params, c.cycle) >= c.drum_threshold:
							explained = false
							break
				if not explained:
					silent.append("%s %s" % [id, c.type])
			for e: HGNote in notes:
				produced += 1
				var range_ok: bool = c.type == "Drums" or (e.pitch >= int(c.low) and e.pitch <= int(c.high))
				if not range_ok or e.velocity < 1 or e.velocity > 127 or e.duration < 0.01 or e.beat < 0.0 or e.beat >= 8.0:
					problems.append("%s %s: %s" % [id, c.type, JSON.stringify(e.to_dict())])
					break
	# Every formula must sound in every role over the two bars (not merely in aggregate).
	assert_true(silent.is_empty(), "silent channels: " + ", ".join(silent))
	assert_true(produced >= Harmonograph.formula_ids().size() * 4, "notes were produced (%d)" % produced)
	assert_true(problems.is_empty(), "\n  ".join(problems))


func test_compile_is_deterministic_and_seekable() -> void:
	var s := _band()
	for i: int in s.channels.size():
		var whole := Harmonograph.compile_channel(s, i, 0.0, 8.0)
		assert_eq(_sig(whole), _sig(Harmonograph.compile_channel(s, i, 0.0, 8.0)), "channel %d compiles identically twice" % i)
		# Seeking: bar 5 compiled alone has the same onsets / pitches / velocities as bar 5 of the
		# 8-bar compile (durations can differ only where a retrigger shortens across the cut).
		var bar := Harmonograph.compile_channel(s, i, 20.0, 1.0)
		var slice: Array = []
		for e: HGNote in whole:
			if e.beat >= 20.0 - 1e-8 and e.beat < 24.0 - 1e-8:
				slice.append([e.pitch, e.velocity, e.beat, e.step])
		var alone: Array = []
		for e: HGNote in bar:
			alone.append([e.pitch, e.velocity, e.beat, e.step])
		assert_eq(alone, slice, "channel %d: bar 5 alone equals bar 5 of the whole" % i)


func test_speed_layers_share_one_grid() -> void:
	# MUSIC-03: a layer at 2^k speed (rate / speed) puts every onset on a power-of-two subdivision
	# of the beat, so layers at 0.5x / 1x / 2x / 4x nest rhythmically.
	for speed: float in [0.5, 1.0, 2.0, 4.0]:
		var s := _band("sine")
		for c: HGChannel in s.channels:
			c.rate = c.rate / speed
			c.swing = 0.5
			c.micro = 0.0
			c.strum = 0.0
		for i: int in s.channels.size():
			var grid: float = HGMath.clamp_js(s.channels[i].rate, 0.0625, 16.0)
			for e: HGNote in Harmonograph.compile_channel(s, i, 0.0, 4.0):
				var k: float = e.beat / grid
				assert_near(k, roundf(k), 1e-9, "speed %s channel %d onset %s on its grid %s" % [speed, i, e.beat, grid])


func test_chords_stay_in_scale_without_escape() -> void:
	for scale: String in Harmonograph.SCALE_NAMES:
		var s := Harmonograph.make_state()
		s.root = 5
		s.scale = scale
		s.chord_source = "formula"
		s.chord_formula = "fibonacci"
		s.quality = "dominant"
		var pcs: Array[int] = []
		for v: Variant in Harmonograph.scale_intervals(scale):
			pcs.append((5 + int(v)) % 12)
		for b: int in 32:
			var c := Harmonograph.chord_at(s, float(b))
			for pc: int in c.pcs:
				assert_true(pcs.has(pc), "%s chord tone %d in scale" % [scale, pc])
	var s2 := Harmonograph.make_state()
	assert_eq(Harmonograph.chord_at(s2, 0.0).name, "Am", "A minor i")
	assert_eq(Harmonograph.chord_at(s2, 4.0).name, "F", "VI on bar 2")
	assert_eq(Harmonograph.degree_midi(7, s2), 21, "degree 7 is the octave")
	assert_eq(Harmonograph.degree_midi(-1, s2), 7, "degree -1 wraps below")


func test_drum_lanes_and_genres() -> void:
	var s := _band()
	var kit: HGChannel = s.channels[3]
	for genre: String in Harmonograph.GENRE_NAMES:
		assert_true(Harmonograph.apply_genre(s, 3, genre), genre)
		var notes := Harmonograph.compile_channel(s, 3, 0.0, 1.0)
		var kicks: int = 0
		for e: HGNote in notes:
			assert_true(e.lane >= 0 and e.lane <= 3, "only the four genre lanes play")
			assert_eq(e.pitch, kit.lanes[e.lane].note, "a drum note is its lane's note")
			assert_eq(e.sound, kit.lanes[e.lane].name, "lane name")
			if e.lane == 0:
				kicks += 1
		var g: Array = Harmonograph.GENRES[genre]
		var want: int = 0
		for step: int in 16:
			want += int(Harmonograph.euclid(float(step), float(g[0][0]), float(g[0][1]), float(g[0][2])))
		assert_true(want > 0, genre + " has kicks")
		assert_eq(kicks, want, genre + " kicks per bar follow E(k, n, rot)")
	assert_false(Harmonograph.apply_genre(s, 3, "Polka"), "unknown genre")


func test_state_round_trip_and_timeline_does_not_mutate() -> void:
	var s := _band()
	s.channels[1].has_queued = true
	s.channels[1].queued_active = false
	s.channels[1].queued_beat = 6.0
	var before := s.to_dict()
	var copy := HGState.from_dict(before)
	assert_true(ODJson.first_difference(copy.to_dict(), before) == "", "from_dict(to_dict()) is lossless")
	var tl := Harmonograph.compile_timeline(s, 1, 0.0, 4.0)
	assert_true(ODJson.first_difference(s.to_dict(), before) == "", "compile_timeline leaves the state untouched")
	for e: HGNote in tl:
		assert_true(e.beat < 6.0, "the channel stops at its queued toggle")
		assert_true(e.beat + e.duration <= 6.0 + 1e-9, "notes are clipped at the cut")


func test_threads_get_identical_results() -> void:
	var s := _band("rossler")
	var want: Array = []
	for i: int in s.channels.size():
		want.append(_sig(Harmonograph.compile_channel(s, i, 32.0, 4.0)))
	var results: Array = [null, null]
	var threads: Array[Thread] = [Thread.new(), Thread.new()]
	for t: int in 2:
		var st := _band("rossler")
		threads[t].start(func() -> void:
			var out: Array = []
			for i: int in st.channels.size():
				out.append(_sig(Harmonograph.compile_channel(st, i, 32.0, 4.0)))
			results[t] = out)
	for t: Thread in threads:
		t.wait_to_finish()
	assert_eq(results[0], want, "thread 1 matches the main thread")
	assert_eq(results[1], want, "thread 2 matches the main thread")


func test_compile_cost() -> void:
	# The director compiles one bar per layer ahead of time; four layers must be cheap.
	var s := _band("henon")
	var t0 := Time.get_ticks_usec()
	var bars: int = 16
	for b: int in bars:
		for i: int in s.channels.size():
			Harmonograph.compile_channel(s, i, float(b) * 4.0, 1.0)
	var per_bar_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / float(bars)
	print("    harmonograph: compiling one bar of a four-layer band takes %.2f ms" % per_bar_ms)
	assert_true(per_bar_ms < 40.0, "one bar of four layers compiles in under 40 ms (%.2f ms)" % per_bar_ms)
