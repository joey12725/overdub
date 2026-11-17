extends ODTest
## The music model behind the visualisers (MUSIC-01..04, MUSIC-08/09, MUSIC-12): layers resolved like
## the director, speed-scaled step grid, cached contours, compiled notes, the chord clock, and the
## per-layer visual state (dead / desynced / reversing / stopped). Run: `bash tools/gd test musicviz`.

var level: LevelDef = null


func before_each() -> void:
	level = ContentData.load_level("sandbox")


func _states(present: Array, speeds: Array = [1.0, 1.0, 1.0, 1.0]) -> Array:
	var out: Array = []
	for i: int in 4:
		out.append(TrackAudioState.make(bool(present[i]), float(speeds[i]), OD.LifeState.ALIVE, true, 1))
	return out


func test_music02_sandbox_layers_resolve_like_the_director() -> void:
	var m := MVMusic.from_level(level)
	assert_eq(m.layers.size(), 4)
	assert_eq(m.layers[0].role, &"bass")
	assert_eq(m.layers[0].formula, "fibonacci")
	assert_eq(m.layers[1].role, &"drums")
	assert_eq(m.layers[2].formula, "lissajous")
	assert_eq(m.layers[3].role, &"chord")
	assert_eq(m.layers[0].local_rate, 0.5)
	assert_eq(m.layers[1].local_rate, 0.25)
	assert_eq(m.layers[3].local_rate, 2.0)
	assert_eq(m.layers[0].period_steps(), 16, "Pisano period of Fibonacci mod 7")
	assert_eq(m.chord_beats, 8.0)
	assert_eq(m.root, 9)
	# Unknown formula falls back exactly like the audio.
	assert_eq(MVLayer.resolve_formula(&"melody", "no_such_formula"), "sine")
	assert_eq(MVLayer.resolve_formula(&"melody", "groove"), "sine", "groove is drums-only")
	assert_eq(MVLayer.resolve_genre("boom-bap"), "Boom bap")
	assert_eq(MVLayer.snap_rate(0.3, 1.0), 0.25)
	assert_eq(MVLayer.snap_rate(NAN, 1.0), 1.0)


func test_music03_step_grid_scales_with_tape_speed() -> void:
	var m := MVMusic.from_level(level)
	var l := m.layers[2]
	assert_near(l.step_at(4.0, 1.0), 8.0, 1e-9)
	assert_near(l.step_at(4.0, 2.0), 16.0, 1e-9)
	assert_near(l.step_at(4.0, 0.5), 4.0, 1e-9)


func test_music12_contour_cache_matches_engine() -> void:
	var m := MVMusic.from_level(level)
	for l: MVLayer in m.layers:
		for k: int in 40:
			var at := k * 0.75
			if is_equal_approx(at * MVLayer.SUB, roundf(at * MVLayer.SUB)):
				assert_near(l.contour(at), l.contour_exact(at), 1e-6, "%s at %s" % [l.formula, at])
		var sig := l.period_signal()
		assert_eq(sig.size(), l.period_steps())
		for v: float in sig:
			assert_true(v >= 0.0 and v <= 1.0)


func test_music12_notes_deterministic_and_in_range() -> void:
	var m := MVMusic.from_level(level)
	var m2 := MVMusic.from_level(level)
	m.update(0.0, _states([true, true, true, true]))
	m2.update(0.0, _states([true, true, true, true]))
	for i: int in 4:
		var a := m.notes_in(i, 0.0, 8.0)
		var b := m2.notes_in(i, 0.0, 8.0)
		assert_true(a.size() > 0, "layer %d plays" % i)
		assert_eq(a.size(), b.size())
		for k: int in mini(a.size(), b.size()):
			assert_eq(a[k].pitch, b[k].pitch)
			assert_near(a[k].beat, b[k].beat, 0.0)
		for n: MVNote in a:
			assert_true(n.beat >= 0.0 and n.beat < 8.0)
			assert_true(n.norm >= 0.0 and n.norm <= 1.0)
			if m.layers[i].is_drums():
				assert_ne(n.drum, &"", "drum kind")
			else:
				assert_true(n.pitch >= m.layers[i].low - 12 and n.pitch <= m.layers[i].high + 12, "pitch near range")
	# Seeking: bar 1 alone equals bar 1 of a longer query.
	var bar1 := m.notes_in(2, 4.0, 8.0)
	var both := m.notes_in(2, 0.0, 8.0).filter(func(n: MVNote) -> bool: return n.beat >= 4.0)
	assert_eq(bar1.size(), both.size())


func test_music03_faster_tape_plays_denser() -> void:
	var m := MVMusic.from_level(level)
	m.update(0.0, _states([true, true, true, true]))
	var slow := m.notes_in(2, 0.0, 8.0).size()
	m.update(0.01, _states([true, true, true, true], [1.0, 1.0, 2.0, 1.0]))
	var fast := m.notes_in(2, 0.0, 8.0).size()
	assert_true(fast > slow, "2x melody plays more notes per master bar (%d > %d)" % [fast, slow])


func test_music12_absent_layer_has_no_notes() -> void:
	var m := MVMusic.from_level(level)
	m.update(0.0, _states([false, true, true, true]))
	assert_eq(m.notes_in(0, 0.0, 8.0).size(), 0)
	assert_eq(m.tracks[0].alpha(0.0), 0.0)


func test_music12_chord_clock_matches_engine() -> void:
	var m := MVMusic.from_level(level)
	for b: float in [0.0, 7.9, 8.0, 17.0, 31.0, 40.0]:
		var c := m.chord_at(b)
		var s := Harmonograph.make_state()
		s.root = 9
		s.scale = "Dorian"
		s.chord_source = "progression"
		s.progression = [0, 3, 0, 4]
		s.chord_rate = 8.0
		var e := Harmonograph.chord_at(s, b)
		assert_eq(c.pcs, e.pcs, "chord at %s" % b)
	assert_eq(m.chord_index(9.0), 1)
	assert_eq(m.chord_start(9.0), 8.0)


func test_play05_reversing_layer_reads_retrograde() -> void:
	var m := MVMusic.from_level(level)
	var fwd := MVTrack.make(m.layers[2])
	var rev := MVTrack.make(m.layers[2])
	fwd.update(5.0, TrackAudioState.make(true, 1.0, OD.LifeState.ALIVE, true, 1))
	rev.update(5.0, TrackAudioState.make(true, 1.0, OD.LifeState.ALIVE, true, -1))
	var c := float(m.layers[2].cycle)
	for b: float in [5.0, 5.5, 6.25, 9.0]:
		assert_near(rev.read_step(b), c - 1.0 - fposmod(fwd.read_step(b), c), 1e-9)
	# The reading runs backwards as master time runs forwards (within a cycle).
	assert_true(rev.read_step(5.5) < rev.read_step(5.25))


func test_desync_drift_grows_then_snaps_back_on_resync() -> void:
	var m := MVMusic.from_level(level)
	var t := m.tracks[0]
	var b := 0.0
	var st := TrackAudioState.make(true, 1.0, OD.LifeState.ALIVE, true, 1)
	while b < 2.0:
		t.update(b, st)
		b += 0.05
	assert_eq(t.drift, 0.0)
	st.synced = false
	var at_start := b
	while b < at_start + 4.0:
		t.update(b, st)
		b += 0.05
	assert_true(t.drift > 0.9, "full drift after a bar desynced (%.3f)" % t.drift)
	assert_true(absf(t.phase_offset(b)) > 2.0, "visibly out of phase")
	st.synced = true
	t.update(b, st)
	assert_true(t.snap_flash > 0.9, "resync flash")
	var resync := b
	while b < resync + 0.6:
		b += 0.05
		t.update(b, st)
	assert_true(t.drift < 0.01, "snapped back within ~half a beat (%.4f)" % t.drift)
	assert_near(t.phase_offset(b), 0.0, 0.05)


func test_music08_dead_layer_thins_and_greys_and_stays_dead() -> void:
	var m := MVMusic.from_level(level)
	var t := m.tracks[2]
	var st := TrackAudioState.make(true, 1.0, OD.LifeState.ALIVE, true, 1)
	t.update(0.0, st)
	t.update(1.0, st)
	var alive_col := t.tint(OD.tape_color(2))
	st.life = OD.LifeState.GHOST
	var b := 1.0
	while b < 3.0:
		b += 0.1
		t.update(b, st)
	assert_near(t.dead_mix, 1.0, 1e-6)
	assert_true(t.width_scale() < 0.5, "thinner")
	var dead_col := t.tint(OD.tape_color(2))
	assert_true(dead_col.s < alive_col.s * 0.4, "greyed")
	assert_true(t.alpha(b) < 0.7)
	# Death is not desync: a ghost never drifts.
	st.synced = false
	t.update(b + 1.0, st)
	assert_eq(t.drift, 0.0)
	assert_false(t.is_desynced())


func test_stopped_layer_freezes() -> void:
	var m := MVMusic.from_level(level)
	var t := m.tracks[0]
	var st := TrackAudioState.make(true, 1.0, OD.LifeState.ALIVE, true, 1)
	t.update(0.0, st)
	t.update(3.0, st)
	st.transport = 0
	t.update(3.1, st)
	var r := t.read_step(3.1)
	t.update(6.0, st)
	assert_near(t.read_step(6.0), r, 1e-6)


func test_restart_resets_visual_memory() -> void:
	var m := MVMusic.from_level(level)
	var st := _states([true, true, true, true])
	(st[1] as TrackAudioState).synced = false
	var b := 0.0
	while b < 6.0:
		m.update(b, st)
		b += 0.25
	assert_true(m.tracks[1].drift > 0.5)
	assert_true(m.drift.at(1, 1) > 0.0, "audio drift memory too")
	m.update(0.0, _states([true, true, true, true]))
	assert_eq(m.tracks[1].drift, 0.0, "new take: fresh state")
	assert_eq(m.drift.at(1, 0), 0.0)


func test_note_source_override_is_used() -> void:
	var m := MVMusic.from_level(level)
	m.update(0.0, _states([true, true, true, true]))
	var calls := [0]
	m.note_source = func(track: int, v: MVVariant, bar: int) -> Array[MVNote]:
		calls[0] += 1
		var n := MVNote.new()
		n.track = track
		n.beat = bar * 4.0 + 1.0
		var out: Array[MVNote] = [n]
		return out
	var got := m.notes_in(0, 0.0, 8.0)
	assert_eq(got.size(), 2)
	assert_eq(calls[0], 2)


func test_music12_batch_sampling_equals_value_at_in_every_state() -> void:
	var m := MVMusic.from_level(level)
	for i: int in 4:
		for transport: int in [1, -1, 0]:
			for desync: bool in [false, true]:
				var t := MVTrack.make(m.layers[i])
				var st := TrackAudioState.make(true, [1.0, 2.0, 0.5, 4.0][i], OD.LifeState.ALIVE, true, 1)
				var b := 0.0
				while b < 6.0:
					t.update(b, st)
					b += 0.05
				st.transport = transport
				st.synced = not desync
				while b < 9.0:
					t.update(b, st)
					b += 0.05
				var b0 := b - 7.3
				var b1 := b + 4.1
				var n := 97
				var vals := t.sample_values(b0, b1, n)
				assert_eq(vals.size(), n)
				for j: int in n:
					var at := maxf(0.0, lerpf(b0, b1, float(j) / float(n - 1)))
					assert_near(vals[j], t.value_at(at), 1e-5, "layer %d transport %d desync %s sample %d" % [i, transport, desync, j])


func test_music12_contour_tables_precomputed_for_the_horizon() -> void:
	var m := MVMusic.from_level(level)
	for l: MVLayer in m.layers:
		var need := float(m.horizon_bars * OD.BEATS_PER_BAR) * 4.0 / l.local_rate
		assert_true(l.table().size() >= int(need * MVLayer.SUB), "layer %d table covers the horizon at 4x" % l.track)


func test_music12_step_curve_is_the_contour_table() -> void:
	var m := MVMusic.from_level(level)
	for l: MVLayer in m.layers:
		var c := l.step_curve()
		assert_eq(c.size(), l.table().size())
		for j: int in [0, 1, 7, 33, c.size() - 1]:
			assert_near(c[j].x, float(j) / MVLayer.SUB, 1e-6)
			assert_near(c[j].y, l.contour(float(j) / MVLayer.SUB), 1e-6)


func test_music12_strip_lines_follow_the_reading_in_every_state() -> void:
	var m := MVMusic.from_level(level)
	var strip := MVStackStrip.frieze_preset()
	strip.music = m
	var ppb := 128.0
	var top := 10.0
	var hh := 100.0
	for transport: int in [1, -1, 0]:
		for desync: bool in [false, true]:
			var states: Array = []
			for i: int in 4:
				states.append(TrackAudioState.make(true, [1.0, 2.0, 0.5, 4.0][i], OD.LifeState.ALIVE, true, 1))
			var b := 0.0
			while b < 20.0:
				m.update(b, states)
				b += 0.05
			for s: TrackAudioState in states:
				s.transport = transport
				s.synced = not desync
			while b < 23.0:
				m.update(b, states)
				b += 0.05
			for i: int in 4:
				var t := m.tracks[i]
				var l := m.layers[i]
				var b0 := m.beat - 10.0
				var line := strip._line(t, l, b0, m.beat + 6.0, b0, ppb, top, hh)
				assert_true(line.size() >= 2, "a line")
				# The strip reads the whole view at the CURRENT phase offset (a desynced line slides
				# as one piece; its waver moves in time, not along the strip).
				var off := t.phase_offset(m.beat)
				var k := t.speed / l.local_rate
				var c := float(l.cycle)
				var bad := 0
				for j: int in line.size():
					if j > 0:
						assert_true(line[j].x >= line[j - 1].x - 1e-3, "x runs left to right")
					var at := maxf(0.0, b0 + line[j].x / ppb)
					var v := 1.0 - (line[j].y - top) / hh
					var expect := t.value_at(m.beat)
					if transport != 0:
						var x := at * k + off
						if transport == -1:
							x = c - 1.0 - fposmod(x, c)
						expect = l.contour(maxf(0.0, x))
					if absf(v - expect) > 1e-3:
						bad += 1
				var cycles := int(16.0 * t.speed / l.local_rate / l.cycle) + 2
				assert_true(bad <= 2 * cycles, "layer %d transport %d desync %s: %d off-curve points" % [i, transport, desync, bad])
	strip.free()
