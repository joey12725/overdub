extends ODTest
## AudioDirector + AudioSequencer (port of prototype/tests/audio/director.test.ts and fixtures.ts):
## state from LevelDef.music, determinism, always in key, master-grid alignment across tape speeds,
## and state-driven composition (MUSIC-01..04, MUSIC-08, MUSIC-09, MUSIC-11).


# ───────────────────────────── fixtures (shared with the other audio suites) ─────────────────────────────

## The parts of a LevelDef the audio module reads. opts: root, scale, progression, chord_bars, bpm.
static func music_level(tracks: Array, opts: Dictionary = {}) -> LevelDef:
	var l := LevelDef.new()
	l.id = "audio-test"
	l.bpm = float(opts.get("bpm", 120.0))
	var m := LevelMusicDef.new()
	m.root = int(opts.get("root", 9))
	m.scale = str(opts.get("scale", "Minor"))
	var prog: Array[int] = []
	for d: Variant in opts.get("progression", [0, 5, 2, 6]):
		prog.append(int(d))
	m.progression = prog
	m.chord_bars = int(opts.get("chord_bars", 1))
	for t: Variant in tracks:
		m.tracks.append((t as TrackMusicDef).copy())
	l.music = m
	return l


static func track(role: StringName, formula: String, params: Dictionary = {}, genre: String = "") -> TrackMusicDef:
	var t := TrackMusicDef.new()
	t.role = role
	t.formula = formula
	for k: Variant in params:
		t.params[str(k)] = float(params[k])
	t.genre = genre
	return t


static func standard_tracks() -> Array:
	return [
		track(MusicRole.MELODY, "fibonacci", {"m": 7}),
		track(MusicRole.BASS, "sine"),
		track(MusicRole.DRUMS, "thue", {}, "Lo-fi 80"),
		track(MusicRole.CHORD, "rose", {"k": 3}),
	]


static func standard_level(opts: Dictionary = {}) -> LevelDef:
	return music_level(standard_tracks(), opts)


static func tas(o: Dictionary = {}) -> TrackAudioState:
	return TrackAudioState.make(o.get("present", true), float(o.get("speed", 1.0)), int(o.get("life", OD.LifeState.ALIVE)), o.get("synced", true), int(o.get("transport", 1)))


static func tracks4(a: TrackAudioState, b: TrackAudioState, c: TrackAudioState, d: TrackAudioState) -> Array[TrackAudioState]:
	return [a, b, c, d]


## [name, dead, transport, drift] (director.test.ts VARIANTS).
const VARIANTS: Array = [
	["baseline", false, 1, 0.0],
	["dead", true, 1, 0.0],
	["desync", false, 1, 0.5],
	["full drift", false, 1, 1.0],
	["reverse", false, -1, 0.0],
	["stopped", false, 0, 0.0],
	["dead reverse", true, -1, 0.0],
	["desync reverse", false, -1, 0.75],
]


static func v(speed: float, spec: Array = []) -> AudioLayerVariant:
	if spec.is_empty():
		return AudioLayerVariant.baseline(speed)
	return AudioLayerVariant.make(speed, spec[1], spec[2], spec[3])


static func strip(ns: Array[AudioLayerNote]) -> Array:
	var out: Array = []
	for n: AudioLayerNote in ns:
		out.append(n.strip())
	return out


static func pc(p: int) -> int:
	return posmod(p, 12)


# ───────────────────────────── state from LevelDef.music ─────────────────────────────

func test_music_01_key_scale_progression_and_tempo_come_from_the_level() -> void:
	var d := AudioDirector.new(standard_level({"root": 2, "scale": "Dorian", "progression": [0, 3, 4], "chord_bars": 2, "bpm": 90}))
	assert_eq(d.bpm, 90.0)
	assert_eq(d.scale, "Dorian")
	var want: Array = []
	for x: int in Harmonograph.SCALES["Dorian"]:
		want.append((x + 2) % 12)
	assert_eq(d.scale_pcs, want)
	assert_eq(d.chord_beats, 8.0)
	assert_eq(d.chord_at(0).index, 0)
	assert_eq(d.chord_at(8).index, 1)
	assert_eq(d.chord_at(16).index, 2)
	assert_eq(d.chord_at(24).index, 0)
	assert_eq(d.chord_at(8).degree, 3)


func test_unknown_scale_formula_genre_fall_back_instead_of_failing() -> void:
	var d := AudioDirector.new(music_level([
		track(MusicRole.MELODY, "not-a-formula"),
		track(MusicRole.BASS, "groove"),
		track(MusicRole.DRUMS, "fibonacci", {}, "polka"),
		track(MusicRole.CHORD, "plr"),
	], {"scale": "nonsense"}))
	assert_eq(d.scale, "Minor")
	assert_eq(d.layer(0).formula, "sine")
	assert_eq(d.layer(1).formula, "triangle")
	assert_eq(d.layer(3).formula, "sine")
	assert_true(d.notes(2, v(1.0), 0, 8).size() > 0, "drums still play")
	assert_eq(AudioDirector.resolve_genre("lofi"), "Lo-fi 80")
	assert_eq(AudioDirector.resolve_genre("funk"), "Funk / disco")


func test_music_02_every_level_formula_is_offered_per_role() -> void:
	var infos := AudioFormulas.list_music_formulas()
	var roles := {}
	for info: AudioFormulas.Info in infos:
		for r: StringName in info.roles:
			roles[r] = int(roles.get(r, 0)) + 1
	assert_true(infos.size() >= 40, "most of the 66 engine formulas are usable: %d" % infos.size())
	for r: StringName in MusicRole.ALL:
		assert_true(int(roles.get(r, 0)) >= 20, "role %s has a broad palette (%d)" % [r, int(roles.get(r, 0))])
	assert_true(AudioFormulas.is_music_formula_allowed(MusicRole.DRUMS, "groove"))
	assert_false(AudioFormulas.is_music_formula_allowed(MusicRole.MELODY, "groove"))
	# Harmony formulas are not contours (formulas.ts; harmonograph.test.ts lists them as excluded).
	for id: String in ["circlechord", "extension", "voicelead", "spread", "plr", "accent", "crescendo"]:
		for r: StringName in MusicRole.ALL:
			assert_false(AudioFormulas.is_music_formula_allowed(r, id), "%s not offered for %s" % [id, r])
	assert_true(AudioFormulas.is_music_formula_allowed(MusicRole.DRUMS, "euclid"))
	assert_false(AudioFormulas.is_music_formula_allowed(MusicRole.BASS, "euclid"))
	# Every sandbox track resolves to a formula allowed for its role. (Its chord track names
	# "voicelead", a Harmony formula, exactly as the prototype's sandbox does; both builds play the
	# role fallback for it.)
	var errors: Array[String] = []
	var sandbox := ContentData.load_level("sandbox", errors)
	if not assert_true(sandbox != null, "sandbox loads: %s" % [errors]):
		return
	for t: TrackMusicDef in sandbox.music.tracks:
		var used := AudioFormulas.resolve_formula(t.role, t.formula)
		assert_true(AudioFormulas.is_music_formula_allowed(t.role, used), "%s/%s -> %s" % [t.role, t.formula, used])
		if t.formula != "voicelead":
			assert_eq(used, t.formula, "%s/%s is used as written" % [t.role, t.formula])


# ───────────────────────────── determinism ─────────────────────────────

func test_same_level_and_layer_states_give_the_same_notes_independent_of_compile_order() -> void:
	var a := AudioDirector.new(standard_level())
	var b := AudioDirector.new(standard_level())
	for t: int in 4:
		for spec: Array in VARIANTS:
			var forward := a.notes(t, v(2.0, spec), 0, 32)
			# b compiles bars backwards and in odd windows: results must not depend on history.
			var pieces: Array = []
			var bar := 7
			while bar >= 0:
				var chunk := strip(b.notes(t, v(2.0, spec), bar * 4, bar * 4 + 4))
				chunk.append_array(pieces)
				pieces = chunk
				bar -= 1
			assert_eq(pieces, strip(forward), "track %d %s" % [t, spec[0]])


func _sequencer_run() -> Array:
	var s := AudioSequencer.new(AudioDirector.new(standard_level()))
	var out: Array[AudioLayerNote] = []
	s.set_tracks(tracks4(tas({"speed": 2.0}), tas(), tas({"speed": 0.5}), tas({"speed": 4.0})), 0)
	out.append_array(s.collect(0, 6))
	s.set_tracks(tracks4(tas({"speed": 2.0, "synced": false}), tas(), tas({"speed": 0.5}), tas({"speed": 4.0, "life": OD.LifeState.GHOST})), 6)
	out.append_array(s.collect(6, 20))
	s.set_tracks(tracks4(tas({"speed": 2.0}), tas({"transport": -1}), tas({"speed": 0.5}), tas({"speed": 4.0, "life": OD.LifeState.GHOST})), 20)
	out.append_array(s.collect(20, 40))
	return strip(out)


func test_the_full_sequencer_output_is_reproducible_from_the_same_track_state_history() -> void:
	var a := _sequencer_run()
	assert_true(a.size() > 100, "a real amount of music: %d notes" % a.size())
	assert_eq(_sequencer_run(), a)


# ───────────────────────────── always in key ─────────────────────────────

## Every allowed formula of a role, at every tape speed and every layer state, sounds only pitches
## of the level scale. The scale rotates per formula across three keys (Minor, Dorian, Major
## Pentatonic) to keep the run short; over all formulas every key is covered many times.
func _check_in_scale(role: StringName) -> void:
	var scales: Array = [[9, "Minor"], [2, "Dorian"], [7, "Major Pentatonic"]]
	var checked := 0
	var formulas := 0
	var bad := 0
	var fi := 0
	for f: AudioFormulas.Info in AudioFormulas.list_music_formulas():
		if not f.roles.has(role):
			continue
		var sc: Array = scales[fi % scales.size()]
		fi += 1
		formulas += 1
		var tr := track(role, f.id)
		var d := AudioDirector.new(music_level([tr, tr, tr, tr], {"root": sc[0], "scale": sc[1], "progression": [0, 3, 4, 5]}))
		var in_scale := {}
		for p: int in d.scale_pcs:
			in_scale[p] = true
		for speed: float in OD.ALL_SPEEDS:
			for spec: Array in VARIANTS:
				for n: AudioLayerNote in d.notes(0, v(speed, spec), 0, 8):
					checked += 1
					if not in_scale.has(pc(n.pitch)):
						bad += 1
						if bad <= 5:
							fail("%s %s %sx %s: pitch %d out of %s" % [f.id, role, speed, spec[0], n.pitch, sc[1]])
	assert_true(formulas >= 20, "%s formulas checked: %d" % [role, formulas])
	assert_true(checked > 1000, "%s pitches checked: %d" % [role, checked])
	assert_eq(bad, 0, "%s: out-of-scale pitches" % role)


func test_music_04_every_melody_pitch_is_in_the_scale_for_every_allowed_formula_speed_and_state() -> void:
	_check_in_scale(MusicRole.MELODY)


func test_music_04_every_bass_pitch_is_in_the_scale_for_every_allowed_formula_speed_and_state() -> void:
	_check_in_scale(MusicRole.BASS)


func test_music_04_every_chord_pitch_is_in_the_scale_for_every_allowed_formula_speed_and_state() -> void:
	_check_in_scale(MusicRole.CHORD)


func test_bass_and_chord_layers_only_sound_tones_of_the_chord_at_their_master_beat() -> void:
	var d := AudioDirector.new(standard_level())
	for speed: float in OD.ALL_SPEEDS:
		for spec: Array in VARIANTS:
			# Bass: triad tones only. Chord layer: its seventh chord (a dead layer drops to the triad).
			for pair: Array in [[1, 0], [3, 0 if spec[1] else 1]]:
				var notes := d.notes(pair[0], v(speed, spec), 0, 32)
				assert_true(notes.size() > 0, "track %d %sx %s plays" % [pair[0], speed, spec[0]])
				for n: AudioLayerNote in notes:
					# Strummed tones start a few ms late; the chord is the one at the step's onset.
					var at := 0.0 if n.beat - 0.1 < 0.0 else floorf(n.beat * 2.0) / 2.0
					var chord := d.chord_at(at, pair[1])
					if not chord.pcs.has(pc(n.pitch)):
						fail("track %d %sx %s: %d at beat %s not in chord %s" % [pair[0], speed, spec[0], n.pitch, n.beat, chord.pcs])
						return
	assert_true(true)


func test_no_pitched_note_sustains_across_a_chord_change() -> void:
	var d := AudioDirector.new(standard_level())
	for t: int in [0, 1, 3]:
		for speed: float in OD.ALL_SPEEDS:
			for spec: Array in VARIANTS:
				for n: AudioLayerNote in d.notes(t, v(speed, spec), 0, 32):
					var next := (floorf(n.beat / d.chord_beats + 1e-9) + 1.0) * d.chord_beats
					if n.beat + n.duration > next + 1e-9:
						fail("track %d %sx %s: note at %s lasts %s past the chord change at %s" % [t, speed, spec[0], n.beat, n.duration, next])
						return
	assert_true(true)


# ───────────────────────────── master-grid alignment (MUSIC-03) ─────────────────────────────

static func _first_per_step(ns: Array[AudioLayerNote]) -> Array[AudioLayerNote]:
	var m := {}
	for n: AudioLayerNote in ns:
		if not m.has(n.step) or (m[n.step] as AudioLayerNote).beat > n.beat:
			m[n.step] = n
	var out: Array[AudioLayerNote] = []
	for k: Variant in m:
		out.append(m[k])
	out.sort_custom(func(a: AudioLayerNote, b: AudioLayerNote) -> bool: return a.beat < b.beat)
	return out


func test_music_03_pitched_onsets_fall_on_the_layer_step_grid_which_nests_by_powers_of_two() -> void:
	var d := AudioDirector.new(standard_level())
	var local := {0: 0.5, 1: 0.5, 3: 2.0}
	for t: int in [0, 1, 3]:
		for speed: float in OD.ALL_SPEEDS:
			var grid: float = local[t] / speed
			var notes := _first_per_step(d.notes(t, v(speed), 0, 32))
			assert_true(notes.size() > 0)
			for n: AudioLayerNote in notes:
				assert_true(absf(n.beat / grid - roundf(n.beat / grid)) < 1e-6, "track %d %sx onset %s on its step grid %s" % [t, speed, n.beat, grid])
				# Even the fastest layer (4x eighths) lands on a 64th of the master grid.
				assert_true(absf(n.beat * 16.0 - roundf(n.beat * 16.0)) < 1e-6, "track %d %sx onset %s on the 1/64 grid" % [t, speed, n.beat])


func test_music_03_a_layer_at_2s_plays_the_same_rhythm_as_at_s_exactly_twice_as_fast() -> void:
	var d := AudioDirector.new(standard_level())
	for t: int in 4:
		for pair: Array in [[0.5, 1.0], [1.0, 2.0], [2.0, 4.0]]:
			var slow: float = pair[0]
			var fast: float = pair[1]
			if t == 2:
				# Drums: every hit (kit lanes are step-locked, swing scales with the step).
				var all_fast: Array = []
				for n: AudioLayerNote in d.notes(t, v(fast), 0, 16):
					all_fast.append([snappedf(n.beat * 2.0, 0.000001), String(n.drum), n.velocity])
				var all_slow: Array = []
				for n: AudioLayerNote in d.notes(t, v(slow), 0, 32):
					all_slow.append([snappedf(n.beat, 0.000001), String(n.drum), n.velocity])
				all_fast.sort()
				all_slow.sort()
				assert_eq(all_fast, all_slow, "drums %s vs %s" % [slow, fast])
			else:
				var a := _first_per_step(d.notes(t, v(slow), 0, 32))
				var b := _first_per_step(d.notes(t, v(fast), 0, 16))
				var sa: Array = []
				for n: AudioLayerNote in a:
					sa.append([n.step, snappedf(n.beat, 0.000001)])
				var sb: Array = []
				for n: AudioLayerNote in b:
					sb.append([n.step, snappedf(n.beat * 2.0, 0.000001)])
				assert_eq(sb, sa, "track %d %s vs %s" % [t, slow, fast])


# ───────────────────────────── state-driven composition ─────────────────────────────

func test_music_09_dead_desync_reverse_and_stopped_each_change_the_generated_notes() -> void:
	var d := AudioDirector.new(standard_level())
	for t: int in 4:
		var base := strip(d.notes(t, v(1.0), 0, 32))
		for i: int in range(1, VARIANTS.size()):
			assert_ne(strip(d.notes(t, v(1.0, VARIANTS[i]), 0, 32)), base, "track %d %s" % [t, VARIANTS[i][0]])


static func _avg_velocity(ns: Array[AudioLayerNote]) -> float:
	var s := 0.0
	for n: AudioLayerNote in ns:
		s += n.velocity
	return s / maxf(1.0, ns.size())


func test_music_08_death_thins_the_layer_and_softens_it() -> void:
	var d := AudioDirector.new(standard_level())
	for t: int in 4:
		var base := d.notes(t, v(1.0), 0, 32)
		var dead := d.notes(t, v(1.0, VARIANTS[1]), 0, 32)
		assert_true(dead.size() < base.size(), "track %d: %d dead notes < %d" % [t, dead.size(), base.size()])
		assert_true(_avg_velocity(dead) < _avg_velocity(base), "track %d softer" % t)


func test_music_08_a_dead_melody_falls_onto_chord_tones() -> void:
	var d := AudioDirector.new(standard_level())
	for n: AudioLayerNote in d.notes(0, v(1.0, VARIANTS[1]), 0, 32):
		assert_has(d.chord_at(n.beat).pcs, pc(n.pitch), "dead melody note %d at %s" % [n.pitch, n.beat])


func test_music_09_reverse_is_a_retrograde_contour_on_the_same_rhythm() -> void:
	var d := AudioDirector.new(standard_level())
	var base := d.notes(0, v(1.0), 0, 32)
	var rev := d.notes(0, v(1.0, VARIANTS[4]), 0, 32)
	var bb: Array = []
	var rb: Array = []
	var bp: Array = []
	var rp: Array = []
	for n: AudioLayerNote in base:
		bb.append(n.beat)
		bp.append(n.pitch)
	for n: AudioLayerNote in rev:
		rb.append(n.beat)
		rp.append(n.pitch)
	assert_eq(rb, bb)
	assert_ne(rp, bp)


func test_music_09_stopped_plays_a_sustained_hold_figure() -> void:
	var d := AudioDirector.new(standard_level())
	var hold := d.notes(0, v(1.0, VARIANTS[5]), 0, 32)
	var base := d.notes(0, v(1.0), 0, 32)
	assert_true(hold.size() > 0)
	assert_true(hold.size() < base.size() / 2.0, "%d hold notes vs %d" % [hold.size(), base.size()])
	var shortest := INF
	for n: AudioLayerNote in hold:
		shortest = minf(shortest, n.duration)
	assert_true(shortest > 1.0, "shortest held note %s beats" % shortest)


func test_music_09_desync_drift_pushes_notes_late_by_less_than_a_step_never_early() -> void:
	var d := AudioDirector.new(standard_level())
	var base := d.notes(0, v(2.0), 0, 32)
	var drift := d.notes(0, v(2.0, VARIANTS[3]), 0, 32)
	var step := 0.5 / 2.0
	if not assert_eq(drift.size(), base.size()):
		return
	for i: int in base.size():
		assert_eq(drift[i].step, base[i].step)
		assert_true(drift[i].beat > base[i].beat, "late")
		assert_true(drift[i].beat - base[i].beat < step * 0.25, "by less than a quarter step")


func test_music_09_desync_drifts_over_bars_and_resync_converges_back_to_the_exact_baseline() -> void:
	var tr := func(synced: bool) -> Array[TrackAudioState]:
		return tracks4(tas({"synced": synced}), tas(), tas({"synced": synced}), tas())
	var base := AudioSequencer.new(AudioDirector.new(standard_level()))
	base.set_tracks(tr.call(true), 0)
	var s := AudioSequencer.new(AudioDirector.new(standard_level()))
	s.set_tracks(tr.call(true), 0)
	assert_true(s.set_tracks(tr.call(false), 8.5), "desync is a change")
	var drifts: Array = []
	for bar: int in [2, 3, 4, 5, 6]:
		drifts.append(s.variant_at(0, bar).drift)
	assert_eq(drifts, [0.25, 0.5, 0.75, 1.0, 1.0])
	s.set_tracks(tr.call(true), 24.2)
	var back: Array = []
	for bar: int in [6, 7, 8, 9]:
		back.append(s.variant_at(0, bar).drift)
	assert_eq(back, [1.0, 0.5, 0.0, 0.0])
	# While drifting, the composition differs ...
	assert_ne(strip(s.collect(12, 24)), strip(base.collect(12, 24)))
	# ... and from bar 8 on (two bars after resync) it is the baseline again, note for note.
	assert_eq(strip(s.collect(32, 64)), strip(base.collect(32, 64)))


func test_music_08_death_is_not_desync_a_ghost_never_drifts() -> void:
	var s := AudioSequencer.new(AudioDirector.new(standard_level()))
	var st := TrackAudioState.make(true, 1.0, OD.LifeState.GHOST, false, 1)
	s.set_tracks(tracks4(st, st, st, st), 0)
	var va := s.variant_at(0, 3)
	assert_eq([va.speed, va.dead, va.transport, va.drift], [1.0, true, 1, 0.0])


func test_a_layer_is_silent_until_its_cassette_is_present() -> void:
	var s := AudioSequencer.new(AudioDirector.new(standard_level()))
	assert_eq(s.collect(0, 16).size(), 0)
	var off := TrackAudioState.make(false, 1.0, OD.LifeState.ALIVE, true, 1)
	var on := TrackAudioState.make(true, 1.0, OD.LifeState.ALIVE, true, 1)
	s.set_tracks(tracks4(on, off, off, off), 0)
	var notes := s.collect(0, 16)
	assert_true(notes.size() > 0)
	var tracks := {}
	for n: AudioLayerNote in notes:
		tracks[n.track] = true
	assert_eq(tracks.keys(), [0])


func test_music_11_layers_depend_only_on_their_own_cassette_state() -> void:
	var a := AudioSequencer.new(AudioDirector.new(standard_level()))
	var b := AudioSequencer.new(AudioDirector.new(standard_level()))
	var alive := tas()
	a.set_tracks(tracks4(alive, alive, alive, alive), 0)
	b.set_tracks(tracks4(alive, tas({"life": OD.LifeState.GHOST}), alive, alive), 0)
	var na := a.collect(0, 32)
	var nb := b.collect(0, 32)
	for t: int in [0, 2, 3]:
		var fa: Array[AudioLayerNote] = []
		var fb: Array[AudioLayerNote] = []
		for n: AudioLayerNote in na:
			if n.track == t:
				fa.append(n)
		for n: AudioLayerNote in nb:
			if n.track == t:
				fb.append(n)
		assert_eq(strip(fb), strip(fa), "track %d unaffected by track 1's death" % t)


func test_the_sandbox_level_compiles_all_four_layers() -> void:
	var errors: Array[String] = []
	var level := ContentData.load_level("sandbox", errors)
	if not assert_true(level != null, str(errors)):
		return
	var d := AudioDirector.new(level)
	for t: int in 4:
		for speed: float in OD.ALL_SPEEDS:
			assert_true(d.notes(t, v(speed), 0, 16).size() > 0, "sandbox layer %d (%s) at %sx" % [t, d.layer(t).role, speed])
