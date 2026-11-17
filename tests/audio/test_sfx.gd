extends ODTest
## Gameplay sound planning (port of prototype/tests/audio/sfx.test.ts; MUSIC-05..07) and the
## sample mapping of every cue (AudioCues over the generated library, assets/audio/manifest.json).

const D := preload("res://tests/audio/test_director.gd")
const BPM := 120.0

var _d: AudioDirector
var _bank: AudioSampleBank


func before_each() -> void:
	if _d == null:
		_d = AudioDirector.new(D.standard_level())


static func sub_of(beat: float) -> int:
	return int(roundf((beat * 60.0 * OD.SUB_HZ) / BPM))


static func clock_at(beat: float, rate: float, now: float = 5.0) -> AudioSfx.Clock:
	return AudioSfx.Clock.make(now, beat, rate, true, BPM)


static func ev(type: StringName, beat: float, tape: int = -1, power: float = -1.0, detail: String = "") -> SimEvent:
	var e := SimEvent.make(sub_of(beat), type, 0.0, 0.0)
	if tape >= 0:
		e.with_tape(tape)
	if power >= 0.0:
		e.with_power(power)
	if detail != "":
		e.with_detail(detail)
	return e


static func evs(list: Array) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in list:
		out.append(e)
	return out


## Every gameplay event type in the brief (sfx.test.ts ALL).
const ALL: Array[StringName] = [
	&"step", &"swing", &"hit", &"kill", &"break", &"clang", &"dodge", &"fire", &"projectileHit", &"interact", &"interactFail", &"door", &"plate",
	&"laser", &"core", &"selfDeath", &"desync", &"resync", &"tapeWrap", &"tapeTurn", &"tapeEnd", &"enemyTelegraph", &"enemyAttack",
	&"enemyShot", &"enemyStagger", &"bossPhase", &"bossRecall", &"objective",
]


# ───────────────────────────── quantisation ─────────────────────────────

func test_music_05_the_grid_is_the_master_sixteenth_subdivided_by_the_world_slow_down() -> void:
	assert_eq(AudioSfx.sfx_grid(1.0), 0.25)
	assert_eq(AudioSfx.sfx_grid(2.0), 0.25)
	assert_eq(AudioSfx.sfx_grid(4.0), 0.25)
	assert_eq(AudioSfx.sfx_grid(0.5), 0.125)
	assert_eq(AudioSfx.sfx_grid(0.25), 0.0625)


func test_music_07_never_early_and_never_more_than_one_heard_sixteenth_late_at_every_world_rate() -> void:
	var base_sixteenth := 60.0 / BPM / 4.0
	for rate: float in [0.25, 0.5, 1.0, 2.0]:
		var master_sixteenth_wall := 0.25 / (rate * (BPM / 60.0))
		var g := AudioSfx.sfx_grid(rate)
		var bad := 0
		for i: int in 400:
			var event_beat := AudioSfx.sub_to_master_beat(sub_of(i * 0.0371), BPM)
			var q := AudioSfx.quantize_late(event_beat, clock_at(event_beat, rate))
			var ok := q.delay >= 0.0 \
				and q.beat >= event_beat - 1e-9 \
				and q.beat - event_beat <= g + 1e-9 \
				and q.lateness <= minf(base_sixteenth, master_sixteenth_wall) + 1e-9 \
				and absf(q.beat / g - roundf(q.beat / g)) < 1e-6
			if not ok:
				bad += 1
				if bad <= 3:
					fail("rate %s event %s -> beat %s delay %s lateness %s" % [rate, event_beat, q.beat, q.delay, q.lateness])
		assert_eq(bad, 0, "rate %s" % rate)


func test_music_07_an_event_already_late_by_events_arriving_a_frame_later_only_waits_for_the_rest() -> void:
	# Events arrive with the frame after they happened: the accent never waits longer than what is
	# left of its sixteenth, and never more than a sixteenth in total.
	for rate: float in [0.25, 0.5, 1.0, 2.0]:
		var bps := rate * BPM / 60.0
		for i: int in 200:
			var event_beat := i * 0.0437
			var seen_at := event_beat + (1.0 / 60.0) * bps
			var q := AudioSfx.quantize_late(event_beat, clock_at(seen_at, rate))
			assert_true(q.delay >= 0.0)
			assert_true(q.lateness <= 60.0 / BPM / 4.0 + 1.0 / 60.0 + 1e-9, "lateness %s" % q.lateness)
			assert_true(q.beat >= seen_at - 1e-9 or q.delay == 0.0)


func test_an_event_a_frame_in_the_past_only_waits_for_what_is_left_of_its_sixteenth() -> void:
	var q := AudioSfx.quantize_late(1.05, clock_at(1.1, 1.0))
	assert_near(q.beat, 1.25, 1e-12)
	assert_near(q.delay, 0.15 / 2.0, 1e-9)
	assert_near(q.lateness, 0.2 / 2.0, 1e-9)
	var old := AudioSfx.quantize_late(1.05, clock_at(1.4, 1.0))
	assert_eq(old.delay, 0.0)


func test_with_the_transport_stopped_sounds_are_immediate() -> void:
	assert_eq(AudioSfx.quantize_late(3.1, AudioSfx.Clock.make(1.0, 3.1, 0.0, false, BPM)).delay, 0.0)
	assert_eq(AudioSfx.quantize_late(3.1, AudioSfx.Clock.make(1.0, 3.1, 0.0, true, BPM)).delay, 0.0)
	assert_eq(AudioSfx.quantize_late(NAN, clock_at(3.1, 1.0)).delay, 0.0)


func test_music_07_planning_never_touches_the_events() -> void:
	var e := ev(&"hit", 2.03, 1, 3.0, "heavy")
	var before := e.to_dict()
	AudioSfx.Planner.new().plan(evs([e]), clock_at(2.03, 1.0), _d)
	assert_eq(e.to_dict(), before)


# ───────────────────────────── planner ─────────────────────────────

func test_every_gameplay_event_type_is_audible_and_whiff_is_deliberately_silent() -> void:
	var audible := AudioSfx.audible_events()
	for t: StringName in ALL:
		assert_has(audible, t)
	# Every SimEventType the simulation can emit is covered, except whiff.
	for t: StringName in SimEventType.ALL:
		if t == SimEventType.WHIFF:
			assert_false(audible.has(t), "whiff is silent")
		else:
			assert_has(audible, t, "%s is audible" % t)
	var p := AudioSfx.Planner.new()
	assert_eq(p.plan(evs([ev(&"whiff", 1.0, 0)]), clock_at(1.0, 1.0), _d).size(), 0)


func test_music_06_cue_pitches_are_in_the_level_scale_and_drawn_from_the_chord_at_the_accent() -> void:
	var scale := {}
	for x: int in _d.scale_pcs:
		scale[x] = true
	var n := 0
	for t: StringName in ALL:
		var p := AudioSfx.Planner.new()
		for beat: float in [0.1, 4.3, 9.7, 13.2]:
			for cue: AudioSfx.Cue in p.plan(evs([ev(t, beat, 1, 5.0, "heavy")]), clock_at(beat, 1.0), _d):
				for pitch: int in cue.pitches:
					assert_true(scale.has(posmod(pitch, 12)), "%s pitch %d in scale" % [t, pitch])
					n += 1
				if cue.kind != AudioSfx.TRANSIENT:
					var chord := _d.chord_at(ceilf(beat * 4.0) / 4.0)
					for pitch: int in cue.pitches:
						assert_has(chord.pcs, posmod(pitch, 12), "%s pitch %d in the chord at the accent" % [t, pitch])
	assert_true(n > 100, "pitches checked: %d" % n)


func test_impacts_get_an_immediate_soft_transient_when_their_accent_is_delayed() -> void:
	var cues := AudioSfx.Planner.new().plan(evs([ev(&"hit", 2.03, 0, 3.0)]), clock_at(2.03, 1.0), _d)
	var transient: AudioSfx.Cue = null
	var hit: AudioSfx.Cue = null
	for c: AudioSfx.Cue in cues:
		if c.kind == AudioSfx.TRANSIENT:
			transient = c
		elif c.kind == AudioSfx.HIT:
			hit = c
	if not assert_true(transient != null and hit != null, "transient and hit"):
		return
	assert_eq(transient.time, 5.0, "the transient is immediate")
	assert_true(transient.gain < hit.gain, "and softer")
	assert_true(hit.time > 5.0, "the accent is late")
	assert_true(hit.time - 5.0 <= 60.0 / BPM / 4.0 + 1e-9, "by at most a sixteenth")
	# On the grid already: no separate transient.
	var on_grid := AudioSfx.Planner.new().plan(evs([ev(&"hit", 2.0, 0)]), clock_at(2.0, 1.0), _d)
	for c: AudioSfx.Cue in on_grid:
		assert_ne(c.kind, AudioSfx.TRANSIENT)


func test_hits_scale_with_power() -> void:
	var soft := AudioSfx.Planner.new().plan(evs([ev(&"hit", 1.0, 0, 0.5)]), clock_at(1.0, 1.0), _d)[0]
	var hard := AudioSfx.Planner.new().plan(evs([ev(&"hit", 1.0, 0, 20.0)]), clock_at(1.0, 1.0), _d)[0]
	assert_true(hard.gain > soft.gain)
	# ... and pick a heavier impact sample.
	var fam_soft := _families_of(soft)
	var fam_hard := _families_of(hard)
	assert_has(fam_soft, &"impact_light")
	assert_has(fam_hard, &"impact_heavy")


func test_four_selves_stepping_at_once_become_one_step_four_selves_striking_spell_the_chord() -> void:
	var steps: Array[SimEvent] = []
	for tape: int in 4:
		steps.append(ev(&"step", 3.01 + tape * 0.01, tape))
	var step_cues := AudioSfx.Planner.new().plan(steps, clock_at(3.05, 1.0), _d)
	assert_eq(step_cues.size(), 1)
	assert_eq(step_cues[0].count, 4)
	var hits: Array[SimEvent] = []
	for tape: int in 4:
		hits.append(ev(&"hit", 5.01, tape, 2.0))
	var roots := {}
	var count := 0
	for c: AudioSfx.Cue in AudioSfx.Planner.new().plan(hits, clock_at(5.01, 1.0), _d):
		if c.kind == AudioSfx.HIT:
			count += 1
			roots[c.pitches[0]] = true
	assert_eq(count, 4)
	assert_true(roots.size() >= 3, "distinct chord tones: %d" % roots.size())


func test_repeats_across_frames_are_rate_limited() -> void:
	var p := AudioSfx.Planner.new()
	var total := 0
	for f: int in 60:
		var beat := f / 30.0
		total += p.plan(evs([ev(&"step", beat, 0), ev(&"step", beat, 1)]), clock_at(beat, 1.0, 5.0 + f / 60.0), _d).size()
	# 60 frames x 2 selves = 120 step events in one second; the grid + limiter keep it musical.
	assert_true(total <= 15, "total %d <= 15" % total)
	assert_true(total >= 8, "total %d >= 8" % total)


func test_a_crowded_sixteenth_keeps_the_most_important_cues() -> void:
	var list: Array[SimEvent] = []
	for i: int in 12:
		var e := ev(&"door", 2.01, -1)
		e.with_id("door%d" % i)
		list.append(e)
	list.append(ev(&"objective", 2.01))
	var cues := AudioSfx.Planner.new().plan(list, clock_at(2.01, 1.0), _d)
	var kinds: Array[StringName] = []
	for c: AudioSfx.Cue in cues:
		kinds.append(c.kind)
	assert_true(cues.size() <= AudioSfx.MAX_CUES_PER_SLOT, "capped at %d: %d" % [AudioSfx.MAX_CUES_PER_SLOT, cues.size()])
	assert_has(kinds, AudioSfx.OBJECTIVE, "the objective is never dropped")


func test_planning_is_deterministic() -> void:
	var run := func() -> Array:
		var p := AudioSfx.Planner.new()
		var out: Array = []
		for f: int in 120:
			var beat := f / 30.0
			var list: Array[SimEvent] = [ev(ALL[f % ALL.size()], beat, f % 4, float(f % 9), "heavy" if f % 2 == 0 else "")]
			for c: AudioSfx.Cue in p.plan(list, clock_at(beat, 1.0, 5.0 + f / 60.0), _d):
				out.append([c.kind, snappedf(c.time, 1e-9), c.pitches, snappedf(c.gain, 1e-9), c.count])
		return out
	var a: Array = run.call()
	assert_true(a.size() > 40)
	assert_eq(run.call(), a)


func test_chord_tone_stacks_tones_upward_from_the_root() -> void:
	var c := AudioChordInfo.make(0, 0, 9, [9, 0, 4])
	var got: Array = []
	for i: int in 4:
		got.append(AudioSfx.chord_tone(c, i, 4))
	assert_eq(got, [69, 72, 76, 81])


# ───────────────────────────── cue -> samples ─────────────────────────────

func _load_bank() -> AudioSampleBank:
	if _bank == null:
		_bank = AudioSampleBank.new()
		_bank.load_manifest(false)
	return _bank


func _families_of(c: AudioSfx.Cue) -> Array[StringName]:
	var trig: Array[AudioTrigger] = []
	AudioCues.cue(c, trig)
	var out: Array[StringName] = []
	for t: AudioTrigger in trig:
		out.append(t.family)
	return out


func test_the_sample_library_manifest_is_complete() -> void:
	var bank := _load_bank()
	assert_eq(bank.errors, [] as Array[String], "manifest loads cleanly")
	assert_near(bank.pad, 0.1, 1e-9)
	for f: StringName in [&"bass", &"lead", &"keys", &"pad", &"kick", &"snare", &"clap", &"hat_closed", &"hat_open", &"tom", &"rim", &"perc"]:
		assert_true(bank.has_family(f), "family %s" % f)
	# Every sample file the manifest names exists.
	var missing := 0
	for k: StringName in bank.families:
		for s: AudioSampleBank.Sample in (bank.families[k] as AudioSampleBank.Family).samples:
			if not ResourceLoader.exists(AudioSampleBank.ROOT_DIR + s.file):
				missing += 1
				if missing <= 3:
					fail("missing " + s.file)
	assert_eq(missing, 0)


func test_instruments_are_never_pitch_shifted_more_than_three_semitones() -> void:
	var bank := _load_bank()
	for f: StringName in [&"bass", &"lead", &"keys", &"pad"]:
		var fam := bank.family(f)
		if not assert_true(fam != null, String(f)):
			continue
		for midi: int in range(fam.lo - 3, fam.hi + 4):
			var pick := bank.pick(f, midi)
			assert_true(absf(pick.shift) <= AudioSampleBank.MAX_SHIFT + 1e-9, "%s %d shift %s" % [f, midi, pick.shift])
			assert_near(pick.pitch_scale, pow(2.0, pick.shift / 12.0), 1e-9)
	# Far outside a range the octave folds in rather than stretching.
	var far := bank.pick(&"bass", 110.0)
	assert_true(absf(far.shift) <= AudioSampleBank.MAX_SHIFT + 1e-9)


func test_every_cue_kind_and_detail_maps_onto_existing_sample_families() -> void:
	var bank := _load_bank()
	var details: Array[String] = ["", "heavy", "light", "on", "off", "missile", "pierce", "phase", "arc", "burst", "bolt", "shock"]
	var checked := 0
	for t: StringName in ALL:
		for detail: String in details:
			for power: float in [0.5, 4.0, 12.0]:
				for c: AudioSfx.Cue in AudioSfx.Planner.new().plan(evs([ev(t, 2.03, 2, power, detail)]), clock_at(2.03, 1.0), _d):
					var trig: Array[AudioTrigger] = []
					AudioCues.cue(c, trig)
					assert_true(trig.size() > 0, "%s/%s makes sound" % [c.kind, detail])
					for tr: AudioTrigger in trig:
						checked += 1
						assert_true(bank.has_family(tr.family), "%s/%s -> family %s" % [c.kind, detail, tr.family])
						assert_eq(tr.dest, AudioTrigger.DEST_SFX)
						assert_true(tr.gain > 0.0 and tr.gain <= 1.0, "gain %s" % tr.gain)
	assert_true(checked > 500, "triggers checked: %d" % checked)


func test_layer_notes_count_in_and_ui_map_onto_existing_sample_families() -> void:
	var bank := _load_bank()
	var seq := AudioSequencer.new(_d)
	seq.set_tracks(D.tracks4(D.tas(), D.tas(), D.tas(), D.tas()), 0)
	var drums := {}
	for n: AudioLayerNote in seq.collect(0, 32):
		var trig: Array[AudioTrigger] = []
		AudioCues.layer_note(_d.role_of(n.track), n, 0.4, trig)
		for tr: AudioTrigger in trig:
			assert_true(bank.has_family(tr.family), "layer %d -> %s" % [n.track, tr.family])
			assert_eq(tr.dest, AudioTrigger.DEST_LAYER)
			assert_eq(tr.channel, n.track)
		if n.drum != &"":
			drums[n.drum] = true
	assert_true(drums.size() >= 3, "a kit plays: %s" % [drums.keys()])
	for drum: StringName in AudioDirector.DRUM_KINDS:
		assert_true(bank.has_family(AudioCues.DRUM_FAMILY[drum]), "drum %s" % drum)
	for n: int in [5, 6, 7, 8]:
		var trig: Array[AudioTrigger] = []
		AudioCues.count_in(n, _d.scale_midi(AudioCues.COUNT_DEGREES[n], 5), trig)
		assert_true(trig.size() >= 2, "count %d" % n)
		var has_word := false
		for tr: AudioTrigger in trig:
			assert_true(bank.has_family(tr.family), "count %d -> %s" % [n, tr.family])
			assert_eq(tr.dest, AudioTrigger.DEST_UI)
			if tr.family == AudioCues.COUNT_WORDS[n]:
				has_word = true
		assert_true(has_word, "count %d speaks its number" % n)
	var none: Array[AudioTrigger] = []
	AudioCues.count_in(4, 60, none)
	assert_eq(none.size(), 0, "only 5..8 count")
	var d := _d
	for kind: StringName in AudioBase.UI_KINDS:
		var trig: Array[AudioTrigger] = []
		AudioCues.ui(kind, func(degree: int) -> int: return d.scale_midi(degree, 5), trig)
		assert_true(trig.size() > 0, "ui %s sounds" % kind)
		for tr: AudioTrigger in trig:
			assert_true(bank.has_family(tr.family), "ui %s -> %s" % [kind, tr.family])
			if tr.pitch >= 0.0:
				assert_has(_d.scale_pcs, posmod(int(tr.pitch), 12), "ui %s in key" % kind)
