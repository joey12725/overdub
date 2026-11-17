extends ODTest
## The sound integration: the composer's score is what plays (per-level music, state maps, SFX pitch
## policy, menu bed), every trap event sounds (warnings on the beat before the stroke), voice (lines
## by story id, barks under their rate limits, the count-in spoken on the beat, ducking, settings),
## and robustness over a full level loop (no doubled or stuck notes, no node leaks).

const D := preload("res://tests/audio/test_director.gd")
const AUDIO_SCENE := "res://audio/audio.tscn"
const LEVEL_IDS: Array[String] = [
	"01-soft-open", "02-hit-harder", "03-hold-the-door", "04-second-opinion", "05-dead-air", "06-crossfire",
	"07-out-of-phase", "08-loop-pedal", "09-rewind", "10-heavy-rotation", "11-the-archivist", "12-master-tape",
]

var _fake_now: float = 500.0
var _bank: AudioSampleBank


func _make_audio() -> AudioBase:
	var scene := load(AUDIO_SCENE) as PackedScene
	if scene == null:
		return null
	var audio := scene.instantiate() as AudioBase
	audio.set("time_source", func() -> float: return _fake_now)
	tree().root.add_child(audio)
	var frames := 0
	while not audio.is_node_ready() and frames < 10:
		await tree().process_frame
		frames += 1
	return audio


func _frame(audio: AudioBase, dt: float = 1.0 / 60.0) -> void:
	_fake_now += dt
	audio.call("step", dt)


func _free_audio(audio: AudioBase) -> void:
	if audio != null and is_instance_valid(audio):
		audio.dispose()
		audio.get_parent().remove_child(audio)
		audio.free()


func _load_bank() -> AudioSampleBank:
	if _bank == null:
		_bank = AudioSampleBank.new()
		_bank.load_manifest(false)
	return _bank


static func _ev(type: StringName, beat: float, bpm: float, tape: int = -1, detail: String = "", power: float = -1.0) -> SimEvent:
	var e := SimEvent.make(int(roundf(beat * 60.0 * OD.SUB_HZ / bpm)), type, 0.0, 0.0)
	if tape >= 0:
		e.with_tape(tape)
	if detail != "":
		e.with_detail(detail)
	if power >= 0.0:
		e.with_power(power)
	return e


static func _evs(list: Array) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in list:
		out.append(e)
	return out


# ───────────────────────────── the composer's score plays ─────────────────────────────

func test_every_level_plays_the_composers_piece_at_the_level_tempo() -> void:
	for id: String in LEVEL_IDS:
		var lv := CampaignData.level(id)
		var score := AudioScore.for_id(id)
		if not assert_true(lv != null and score != null, "%s: level and piece load" % id):
			continue
		assert_near(score.bpm, lv.bpm, 1e-9, "%s: piece bpm = level bpm" % id)
		var heard := preload("res://audio/audio.gd").music_level(lv, score)
		var d := AudioDirector.new(heard)
		assert_eq(heard.music.to_dict(), score.music.to_dict(), "%s: the director gets the composer's block" % id)
		# The cassette roles are the composer's order (docs/MUSIC.md "Cassette order changes").
		for i: int in OD.TAPE_COUNT:
			assert_eq(d.role_of(i), score.music.tracks[i].role, "%s cassette %d role" % [id, i + 1])
	# A level whose own block differs (not merged / edited) still plays the composer's piece.
	var lv1 := CampaignData.level("01-soft-open")
	var stale := LevelDef.new()
	stale.id = lv1.id
	stale.bpm = lv1.bpm
	stale.music = D.standard_level().music
	var fixed := preload("res://audio/audio.gd").music_level(stale, AudioScore.for_id("01-soft-open"))
	assert_eq(fixed.music.to_dict(), AudioScore.for_id("01-soft-open").music.to_dict(), "unmerged block replaced by the piece")


## docs/MUSIC.md state maps, measured on the Godot director with every piece: dead thins to its
## skeleton on chord tones, full desync changes most pitches but stays in key, reverse stays in key,
## stopped is a sparse hold figure.
func test_state_maps_are_applied_as_the_composer_specified() -> void:
	for id: String in LEVEL_IDS + ["menu"] as Array[String]:
		var score := AudioScore.for_id(id)
		if not assert_true(score != null, id):
			continue
		var d := AudioDirector.new(score.level_def())
		var scale := {}
		for pc: int in d.scale_pcs:
			scale[pc] = true
		var alive := AudioLayerVariant.make(1.0, false, 1, 0.0)
		var dead := AudioLayerVariant.make(1.0, true, 1, 0.0)
		var drift := AudioLayerVariant.make(1.0, false, 1, 1.0)
		var rev := AudioLayerVariant.make(1.0, false, -1, 0.0)
		var stop := AudioLayerVariant.make(1.0, false, 0, 0.0)
		var n_alive := 0
		var n_dead := 0
		var dead_tones := 0
		var dead_chord := 0
		var changed := 0
		var compared := 0
		var stopped := 0
		var out_of_key := 0
		for track: int in OD.TAPE_COUNT:
			var pitched := d.role_of(track) != MusicRole.DRUMS
			for bar: int in 8:
				var a := d.bar_notes(track, alive, bar)
				var de := d.bar_notes(track, dead, bar)
				n_alive += a.size()
				n_dead += de.size()
				stopped += d.bar_notes(track, stop, bar).size()
				if not pitched:
					continue
				for n: AudioLayerNote in de:
					dead_tones += 1
					if d.chord_at(n.beat).pcs.has(posmod(n.pitch, 12)):
						dead_chord += 1
				var by_step := {}
				for n: AudioLayerNote in a:
					by_step[n.step] = n.pitch
				for v: AudioLayerVariant in [drift, rev]:
					for n: AudioLayerNote in d.bar_notes(track, v, bar):
						if not scale.has(posmod(n.pitch, 12)):
							out_of_key += 1
				for n: AudioLayerNote in d.bar_notes(track, drift, bar):
					if by_step.has(n.step):
						compared += 1
						if by_step[n.step] != n.pitch:
							changed += 1
		var ratio := float(n_dead) / float(maxi(1, n_alive))
		assert_true(ratio >= 0.4 and ratio <= 0.8, "%s: dead onsets %.2f of alive (composer 0.51-0.69)" % [id, ratio])
		assert_eq(dead_chord, dead_tones, "%s: dead layers play only chord tones (%d/%d)" % [id, dead_chord, dead_tones])
		var share := float(changed) / float(maxi(1, compared))
		assert_true(share >= 0.4, "%s: full desync changes %.0f%% of pitched steps (composer 58-86%%)" % [id, share * 100.0])
		assert_eq(out_of_key, 0, "%s: desynced and reversed notes stay in key" % id)
		var per_bar := float(stopped) / 8.0
		assert_true(per_bar >= 1.0 and per_bar <= 9.0, "%s: stopped hold figure %.1f onsets/bar (composer 5-6)" % [id, per_bar])
	# Drift timing: 0.25 per bar up to full in the fourth bar, back to the baseline within two bars.
	var dr := AudioDesyncDrift.new()
	dr.update(0, true, 0.0)
	assert_eq([dr.at(0, 0), dr.at(0, 1), dr.at(0, 2), dr.at(0, 3), dr.at(0, 9)], [0.25, 0.5, 0.75, 1.0, 1.0])
	dr.update(0, false, 40.0)
	assert_eq([dr.at(0, 10), dr.at(0, 11), dr.at(0, 12)], [1.0, 0.5, 0.0])


## MUSIC-05: every event class sounds the composer's tones for the level's palette.
func test_sfx_pitches_follow_the_composers_policy_per_event_class() -> void:
	var class_events: Dictionary = {
		"step": [&"step", ""], "dodge": [&"dodge", ""], "swingLight": [&"swing", "light"], "swingHeavy": [&"swing", "heavy"],
		"fire": [&"fire", "bolt"], "hit": [&"hit", ""], "projectileHit": [&"projectileHit", ""], "clang": [&"clang", ""],
		"kill": [&"kill", ""], "break": [&"break", ""], "interact": [&"interact", "on"], "interactFail": [&"interactFail", ""],
		"door": [&"door", "open"], "plate": [&"plate", "on"], "laser": [&"laser", "on"], "core": [&"core", ""],
		"objective": [&"objective", ""], "selfDeath": [&"selfDeath", ""], "desync": [&"desync", ""], "resync": [&"resync", ""],
		"tapeWrap": [&"tapeWrap", ""], "tapeTurn": [&"tapeTurn", ""], "tapeEnd": [&"tapeEnd", ""],
		"enemyTelegraph": [&"enemyTelegraph", ""], "enemyAttack": [&"enemyAttack", ""], "enemyShot": [&"enemyShot", ""],
		"enemyStagger": [&"enemyStagger", ""], "bossPhase": [&"bossPhase", ""], "bossRecall": [&"bossRecall", ""],
	}
	var checked := 0
	for id: String in LEVEL_IDS:
		var score := AudioScore.for_id(id)
		var d := AudioDirector.new(score.level_def())
		for cls: String in class_events:
			if not score.has_class(cls):
				fail("%s: no class %s" % [id, cls])
				continue
			var spec: Array = class_events[cls]
			for tape: int in [0, 2]:
				var p := AudioSfx.Planner.new()
				p.policy = score
				var beat := 4.0 * tape + 2.0
				var clock := AudioSfx.Clock.make(10.0, beat, 1.0, true, d.bpm)
				var e := _ev(spec[0], beat, d.bpm, tape, spec[1], 2.0)
				for c: AudioSfx.Cue in p.plan(_evs([e]), clock, d):
					if c.kind == AudioSfx.TRANSIENT:
						continue
					var want := score.pitches(cls, false, 2.0, d.chord_at(beat), d, tape)
					assert_eq(c.pitches, want, "%s %s tape %d" % [id, cls, tape])
					checked += 1
	assert_true(checked >= 12 * 29 * 2, "cues checked: %d" % checked)
	# The boss floor's telegraph is the raised seventh (scale degree 6), as composed.
	var boss := AudioScore.for_id("11-the-archivist")
	var bd := AudioDirector.new(boss.level_def())
	var bp := AudioSfx.Planner.new()
	bp.policy = boss
	var cues := bp.plan(_evs([_ev(&"enemyTelegraph", 2.0, bd.bpm)]), AudioSfx.Clock.make(1.0, 2.0, 1.0, true, bd.bpm), bd)
	assert_eq(cues[0].pitches, [bd.scale_midi(6, 3)] as Array[int], "boss telegraph on the leading tone")


func test_impacts_use_the_32nd_grid_below_116_bpm_other_cues_the_sixteenth() -> void:
	var score := AudioScore.for_id("07-out-of-phase")
	assert_true(score.impact_grid, "the latency data names the 32nd impact grid")
	var d := AudioDirector.new(score.level_def())
	assert_true(d.bpm < 116.0)
	var p := AudioSfx.Planner.new()
	p.policy = score
	var beat := 2.01
	var clock := AudioSfx.Clock.make(10.0, beat, 1.0, true, d.bpm)
	var s16 := 60.0 / d.bpm / 4.0
	for c: AudioSfx.Cue in p.plan(_evs([_ev(&"hit", beat, d.bpm, 0, "", 2.0), _ev(&"step", beat, d.bpm, 1)]), clock, d):
		if c.kind == AudioSfx.HIT:
			assert_true(c.time - 10.0 <= s16 * 0.5 + 1e-6, "hit lands within a 32nd: %.3f s" % (c.time - 10.0))
		elif c.kind == AudioSfx.STEP:
			assert_true(c.time - 10.0 > s16 * 0.5, "a step waits for the sixteenth")
	# At 120 bpm (sixteenth 125 ms) impacts stay on the sixteenth.
	var fast := AudioScore.for_id("12-master-tape")
	var fd := AudioDirector.new(fast.level_def())
	var fp := AudioSfx.Planner.new()
	fp.policy = fast
	assert_eq(fp.grid_for(true, AudioSfx.Clock.make(0.0, 0.0, 1.0, true, fd.bpm)), 0.25)


func test_ui_blips_and_count_in_use_the_composers_pitches() -> void:
	var score := AudioScore.for_id("04-second-opinion")
	var d := AudioDirector.new(score.level_def())
	for kind: StringName in AudioBase.UI_KINDS:
		var pitches := score.ui_pitches(kind, d)
		var trig: Array[AudioTrigger] = []
		AudioCues.ui_tones(kind, pitches, func(deg: int) -> int: return d.scale_midi(deg, 5), trig)
		assert_true(trig.size() > 0, "ui %s sounds" % kind)
		var bank := _load_bank()
		for t: AudioTrigger in trig:
			assert_true(bank.has_family(t.family), "ui %s -> %s" % [kind, t.family])
			if t.pitch >= 0.0:
				assert_has(d.scale_pcs, posmod(int(t.pitch), 12), "ui %s in key" % kind)
	for n: int in [5, 6, 7, 8]:
		assert_true(score.count_pitch(n, d) >= 0, "count %d pitch" % n)
	assert_eq(score.count_pitch(8, d), d.scale_midi(4, 4), "eight on the fifth")


# ───────────────────────────── traps ─────────────────────────────

## Every trap detail core/traps/traps.gd can emit (docs/TRAPS.md table).
const TRAP_DETAILS: Array[String] = [
	"spikes:warn", "crusher:warn", "flame:warn", "spikes:up", "spikes:down", "crusher:slam", "crusher:retract",
	"crusher:hold", "crusher:open", "conveyor:on", "conveyor:off", "conveyor:reverse", "conveyor:forward",
	"flame:on", "flame:off", "dart:fire", "dart:on", "dart:off", "bumper:fire", "sensor:on", "sensor:off",
	"relay:armed", "relay:on", "relay:off", "magnet:on", "magnet:off",
]


func test_every_trap_event_sounds_on_existing_samples_in_the_chord() -> void:
	var bank := _load_bank()
	var d := AudioDirector.new(D.standard_level())
	# The detail list matches what the trap system emits (scan its source for the literals).
	var src := FileAccess.get_file_as_string("res://core/traps/traps.gd")
	for what: String in ["warn", "up", "down", "retract", "hold", "open", "slam", "reverse", "forward", "fire", "armed"]:
		assert_true(src.contains("\"%s\"" % what) or src.contains(":%s\"" % what), "traps.gd emits %s" % what)
	for detail: String in TRAP_DETAILS:
		assert_true(AudioSfx.TRAP_RECIPES.has(detail), "%s has a recipe" % detail)
		var p := AudioSfx.Planner.new()
		var e := _ev(SimEventType.TRAP, 6.0, 120.0, -1, detail, 1.0)
		e.with_id("t1")
		var cues := p.plan(_evs([e]), AudioSfx.Clock.make(3.0, 6.0, 1.0, true, 120.0), d)
		var real := 0
		for c: AudioSfx.Cue in cues:
			var trig: Array[AudioTrigger] = []
			AudioCues.cue(c, trig)
			if not assert_true(trig.size() > 0, "%s makes sound" % detail):
				continue
			real += 1
			for t: AudioTrigger in trig:
				assert_true(bank.has_family(t.family), "%s -> family %s" % [detail, t.family])
				assert_eq(t.dest, AudioTrigger.DEST_SFX)
			if c.kind != AudioSfx.TRANSIENT and c.kind != AudioSfx.TRAP_WARN:
				var chord := d.chord_at(6.0)
				for pitch: int in c.pitches:
					assert_has(chord.pcs, posmod(pitch, 12), "%s pitch %d in the chord" % [detail, pitch])
		assert_true(real > 0, "%s planned" % detail)
	assert_true(bank.has_family(AudioTrapLoops.HUM_FAMILY) and bank.family(AudioTrapLoops.HUM_FAMILY).loop, "conveyor hum loops")
	assert_true(bank.has_family(AudioTrapLoops.ROAR_FAMILY) and bank.family(AudioTrapLoops.ROAR_FAMILY).loop, "flame roar loops")


## A beat-timed hazard warns one beat before it fires, on the grid, with a second tick half a beat
## later: both land before the stroke. Checked at every world rate.
func test_trap_warnings_land_on_the_beat_before_the_stroke() -> void:
	var d := AudioDirector.new(D.standard_level())
	for rate: float in [0.25, 0.5, 1.0, 2.0, 4.0]:
		var bps := rate * 120.0 / 60.0
		# The forecast refreshes 8 times a beat, so the warn arrives up to 1/8 beat late with power
		# = beats until activation: here the activation is master beat 8.
		for ev_beat: float in [7.0, 7.125, 7.25]:
			var e := _ev(SimEventType.TRAP, ev_beat, 120.0, -1, "spikes:warn", 8.0 - ev_beat)
			e.with_id("sp1")
			var now := 20.0
			var clock := AudioSfx.Clock.make(now, ev_beat, rate, true, 120.0)
			var cues := AudioSfx.Planner.new().plan(_evs([e]), clock, d)
			if not assert_eq(cues.size(), 1, "one telegraph at rate %s" % rate):
				continue
			var c := cues[0]
			assert_eq(c.kind, AudioSfx.TRAP_WARN)
			var tick_beat := ev_beat + (c.time - now) * bps
			var trig: Array[AudioTrigger] = []
			AudioCues.cue(c, trig)
			var tock_beat := ev_beat + (c.time + trig[1].offset - now) * bps
			if ev_beat <= 7.0:
				assert_near(tick_beat, 7.0, 1e-6, "tick on the beat before the stroke (rate %s)" % rate)
			else:
				# Already past the beat: as soon as possible, on the grid, still before the stroke.
				assert_true(tick_beat < 8.0 - 0.2, "tick before the stroke: %.3f (rate %s)" % [tick_beat, rate])
				assert_near(fmod(tick_beat, AudioSfx.sfx_grid(rate)), 0.0, 1e-6, "tick on the grid")
			assert_true(tock_beat < 8.0 + 1e-6 and tock_beat > tick_beat, "tock after the tick, by the stroke: %.3f" % tock_beat)
			assert_near(tock_beat - tick_beat, 0.5, 1e-6, "tock half a beat after the tick")
	# The stroke itself is on its beat.
	var slam := _ev(SimEventType.TRAP, 8.0, 120.0, -1, "crusher:slam", 0.0)
	slam.with_id("cr1")
	var cues2 := AudioSfx.Planner.new().plan(_evs([slam]), AudioSfx.Clock.make(20.0, 8.0, 1.0, true, 120.0), d)
	for c: AudioSfx.Cue in cues2:
		assert_near(c.time, 20.0, 1e-6, "the slam is on its beat (%s)" % c.kind)


func test_conveyor_hum_and_flame_roar_follow_the_trap_states() -> void:
	var loops := AudioTrapLoops.new()
	loops.bank = _load_bank()
	var lv := LevelDef.new()
	var belt := ConveyorDef.new()
	belt.id = "belt"
	lv.entities.append(belt)
	var jet := FlameDef.new()
	jet.id = "jet"
	lv.entities.append(jet)
	loops.setup(lv, 7)
	loops.update(true, 0.1)
	assert_eq(loops.conveyors_running(), 1, "an always-on belt runs from beat zero")
	assert_eq(loops.flames_burning(), 0)
	assert_true(loops.hum_target() > 0.0, "and hums while time runs")
	loops.update(false, 0.1)
	assert_eq(loops.hum_target(), 0.0, "silent while time is frozen")
	var on := SimEvent.make(0, SimEventType.TRAP, 0, 0).with_id("jet").with_detail("flame:on")
	var off := SimEvent.make(0, SimEventType.TRAP, 0, 0).with_id("belt").with_detail("conveyor:off")
	loops.on_events(_evs([on, off]))
	loops.update(true, 0.1)
	assert_eq(loops.flames_burning(), 1)
	assert_eq(loops.conveyors_running(), 0)
	assert_true(loops.roar_target() > 0.0 and loops.hum_target() == 0.0)
	loops.restart()
	assert_eq([loops.conveyors_running(), loops.flames_burning()], [1, 0], "a new take starts from the initial states")
	loops.free()


# ───────────────────────────── voice ─────────────────────────────

func test_dialogue_lines_resolve_by_story_id_location_and_text() -> void:
	var v := AudioVoiceLines.new()
	if not assert_eq(v.errors, [] as Array[String], "voice manifest loads"):
		v.free()
		return
	var m: Variant = ODJson.read_file(AudioVoiceLines.MANIFEST_PATH)
	var lines: Dictionary = (m as Dictionary)["lines"]
	var n := 0
	for id: String in lines:
		var l: Dictionary = lines[id]
		assert_eq(v.resolve(id), id)
		assert_eq(v.resolve(str(l["location"])), id, "location %s" % l["location"])
		assert_eq(v.resolve(str(l["text"]), str(l["character"])), id, "text of %s" % id)
		assert_near(v.line_duration(str(l["location"])), float(l["duration"]), 1e-9)
		assert_true(ResourceLoader.exists(AudioVoiceLines.MANIFEST_PATH.get_base_dir() + "/" + str(l["file"])), "file of %s" % id)
		n += 1
	assert_eq(n, 160, "every scripted line")
	assert_eq(v.resolve("levels.99-nowhere.intro[0]"), "", "unknown -> silent")
	assert_eq(v.line_duration("nope"), 0.0)
	# Lines in story.json resolve from the dialogue box's (who, text) alone.
	var story: Variant = ODJson.read_file("res://data/story/story.json")
	var intro: Array = ((story as Dictionary)["levels"]["01-soft-open"]["intro"])
	assert_true(v.has_line(str(intro[0]["line"]), str(intro[0]["who"])), "story.json line found by text")
	v.free()


func test_barks_obey_the_rate_limits() -> void:
	var v := AudioVoiceLines.new()
	var m: Variant = ODJson.read_file(AudioVoiceLines.MANIFEST_PATH)
	var barks: Array[String] = []
	for id: String in (m as Dictionary)["lines"]:
		if str((m as Dictionary)["lines"][id]["kind"]) == "bark" and str((m as Dictionary)["lines"][id]["character"]) == "moxie":
			barks.append(id)
	if not assert_true(barks.size() >= 3, "moxie barks: %d" % barks.size()):
		v.free()
		return
	var t := 100.0
	assert_true(v.play_bark(barks[0], "idle", "moxie", true, t) > 0.0, "first bark plays")
	assert_eq(v.speaking(t + 0.1), AudioVoiceLines.KIND_BARK)
	var d0 := v.line_duration(barks[0])
	assert_eq(v.play_bark(barks[1], "kill", "moxie", true, t + d0 + 1.0), 0.0, "6 s gap between barks")
	assert_true(v.play_bark(barks[1], "kill", "moxie", true, t + 6.5) > 0.0, "after 6 s another key plays")
	assert_eq(v.play_bark(barks[2], "kill", "moxie", true, t + 13.0), 0.0, "20 s before the same key repeats")
	assert_true(v.play_bark(barks[2], "selfDeath", "moxie", true, t + 13.0) > 0.0, "death may skip the 6 s gap")
	assert_eq(v.play_bark(barks[2], "idle", "moxie", true, t + 40.0), 0.0, "never the same line twice running")
	# Never over a line.
	var line_id := "l01_intro_01"
	var dur := v.play_line(line_id, "", false, t + 50.0)
	assert_true(dur > 0.0)
	assert_eq(v.speaking(t + 50.1), AudioVoiceLines.KIND_LINE)
	assert_eq(v.play_bark(barks[0], "win", "moxie", true, t + 50.2), 0.0, "no bark over a line")
	v.stop_line(t + 51.0)
	assert_eq(v.speaking(t + 51.2), AudioVoiceLines.KIND_NONE, "an early advance stops the line")
	# Roughly half of eligible events bark.
	var w := AudioVoiceLines.new()
	var played := 0
	for i: int in 40:
		if w.play_bark(barks[i % barks.size()], "k%d" % i, "moxie", false, 1000.0 + i * 30.0) > 0.0:
			played += 1
	assert_true(played >= 10 and played <= 30, "about half bark: %d of 40" % played)
	# Settings.
	w.barks_enabled = false
	assert_eq(w.play_bark(barks[0], "zz", "moxie", true, 9999.0), 0.0, "barks off")
	w.barks_enabled = true
	w.mode = AudioVoiceLines.MODE_COUNT_ONLY
	assert_eq(w.play_bark(barks[0], "zz", "moxie", true, 9999.0), 0.0, "count-in only: no barks")
	assert_eq(w.play_line(line_id, "", false, 9999.0), 0.0, "count-in only: no lines")
	v.free()
	w.free()


func test_the_count_in_take_fits_the_tempo_and_lands_each_vowel_on_the_beat() -> void:
	var v := AudioVoiceLines.new()
	for bpm: float in [80.0, 90.0, 100.0, 120.0, 150.0, 200.0]:
		for called: bool in [false, true]:
			var take := v.count_take(bpm, called)
			if not assert_false(take.is_empty(), "a take at %s bpm" % bpm):
				continue
			assert_eq((take["files"] as Dictionary).size(), 4, "one take for all four words")
			var beat := 60.0 / bpm
			if bpm <= 150.0:
				assert_true(float(take["longest"]) <= beat - 0.04, "%s bpm: words fit the beat (%.3f <= %.3f)" % [bpm, take["longest"], beat - 0.04])
	# Slow tempo picks the longest-spoken take that fits, fast tempo a shorter one.
	assert_true(float(v.count_take(80.0, false)["longest"]) >= float(v.count_take(150.0, false)["longest"]))
	# Queue: on "five" the four words are queued a beat apart, each early by its vowel onset.
	assert_true(v.count_in(5, 120.0, false, 50.0))
	assert_eq(v.pending_count_words(), 4)
	var files: Dictionary = v.count_take(120.0, false)["files"]
	var starts: Array = []
	for w: Array in v.get("_pending"):
		starts.append(w[0])
	for k: int in 4:
		var e: Dictionary = files[5 + k]
		assert_near(float(starts[k]) + float(e["vowelOnset"]), 50.0 + 0.5 * k, 1e-9, "vowel of word %d on beat %d" % [5 + k, k])
	assert_true(v.count_in(6, 120.0, false, 50.5), "later counts keep the queue")
	assert_eq(v.pending_count_words(), 4)
	v.cancel_count_in()
	assert_eq(v.pending_count_words(), 0, "an abandoned take drops the words")
	v.mode = AudioVoiceLines.MODE_OFF
	assert_false(v.count_in(5, 120.0, false, 60.0), "voices off: synthesised count")
	v.mode = AudioVoiceLines.MODE_COUNT_ONLY
	assert_true(v.count_in(5, 120.0, false, 60.0), "count-in only still speaks the count")
	v.free()


func test_the_facade_speaks_ducks_the_music_and_obeys_the_voice_setting() -> void:
	var audio: AudioBase = await _make_audio()
	if not assert_true(audio != null):
		return
	audio.load_level(CampaignData.level("01-soft-open"))
	var mixer: AudioMixer = audio.call("mixer")
	var dur := audio.play_line("levels.01-soft-open.intro[0]")
	assert_true(dur > 1.0, "line plays: %.2f s" % dur)
	assert_near(audio.line_duration("levels.01-soft-open.intro[0]"), dur, 1e-9)
	for i: int in 12:
		_frame(audio)
	assert_near(mixer.duck_target_db(), AudioMixer.DUCK_LINE_DB, 0.01, "music ducks 6 dB under a line")
	assert_true(mixer.duck_db() < -5.0, "within 200 ms: %.2f dB" % mixer.duck_db())
	var frames := int(ceilf((dur + 0.1) * 60.0))
	for i: int in frames:
		_frame(audio)
	assert_near(mixer.duck_target_db(), 0.0, 0.01, "released after the line + hold")
	for i: int in 60:
		_frame(audio)
	assert_true(mixer.duck_db() > -0.3, "back up within a second: %.2f dB" % mixer.duck_db())
	# Voices off: nothing spoken, the Voice bus muted, the count falls back to the synthesised word.
	audio.set_voice_options(AudioBase.VOICES_OFF, true, 1.0)
	assert_eq(audio.play_line("levels.01-soft-open.intro[0]"), 0.0)
	for i: int in 30:
		_frame(audio)
	assert_true(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioBusSetup.VOICE)) <= -60.0, "Voice bus muted")
	var sp: AudioVoiceLines = audio.call("speech")
	audio.count_in(5)
	assert_eq(sp.pending_count_words(), 0, "no spoken count with voices off")
	audio.set_voice_options(AudioBase.VOICES_ON, true, 0.8)
	audio.count_in(5)
	assert_eq(sp.pending_count_words(), 4, "Moxie counts in")
	audio.cancel_count_in()
	assert_eq(sp.pending_count_words(), 0)
	_free_audio(audio)


func test_dialogue_layer_lines_and_barks_are_spoken() -> void:
	var audio: AudioBase = await _make_audio()
	if not assert_true(audio != null):
		return
	var layer_scene := load("res://ui/dialogue/dialogue_layer.tscn") as PackedScene
	if not assert_true(layer_scene != null, "dialogue layer scene"):
		_free_audio(audio)
		return
	var layer := layer_scene.instantiate()
	tree().root.add_child(layer)
	await tree().process_frame
	audio.connect_dialogue(layer)
	var sp: AudioVoiceLines = audio.call("speech")
	var before := sp.started
	var player: Node = layer.get("player")
	var story: Variant = ODJson.read_file("res://data/story/story.json")
	var l0: Dictionary = (story as Dictionary)["levels"]["01-soft-open"]["intro"][0]
	player.emit_signal("started", &"intro", "01-soft-open")
	player.emit_signal("line_shown", &"intro", 0, DlgLine.from_dict(l0))
	assert_eq(sp.started, before + 1, "the shown line is spoken")
	assert_eq(sp.speaking(_fake_now + 0.05), AudioVoiceLines.KIND_LINE)
	player.emit_signal("finished", &"intro", "01-soft-open", true)
	assert_eq(sp.speaking(_fake_now + 0.2), AudioVoiceLines.KIND_NONE, "a skip stops the line")
	layer.queue_free()
	_free_audio(audio)


# ───────────────────────────── menu bed ─────────────────────────────

func test_the_menu_bed_plays_on_its_own_clock_and_hands_back_to_the_level() -> void:
	var audio: AudioBase = await _make_audio()
	if not assert_true(audio != null):
		return
	var planned: Array[AudioPlannedNote] = []
	audio.set("on_note_planned", func(p: AudioPlannedNote) -> void: planned.append(p))
	audio.set_mode(AudioBase.MODE_MENU)
	assert_true(audio.call("menu_bed_active"), "the bed starts in menus")
	var d: AudioDirector = audio.call("director")
	assert_near(d.bpm, 72.0, 1e-9, "at the bed's 72 bpm")
	# The game keeps telling a stopped transport and silent tracks: the bed ignores them.
	for f: int in 300:
		audio.set_transport(0.0, 0.0, false)
		_frame(audio)
	var tracks := {}
	for p: AudioPlannedNote in planned:
		tracks[p.note.track] = true
		assert_true(d.role_of(p.note.track) != MusicRole.DRUMS, "no drums in the bed")
	assert_true(planned.size() >= 6, "the bed plays: %d notes in 5 s" % planned.size())
	assert_false(tracks.has(3), "cassette 4 is absent")
	assert_true(audio.pulse().beat > 4.0, "pulse follows the bed clock: %.2f" % audio.pulse().beat)
	# A level takes over.
	audio.load_level(CampaignData.level("03-hold-the-door"))
	audio.set_mode(AudioBase.MODE_RECORD)
	assert_false(audio.call("menu_bed_active"))
	assert_near((audio.call("director") as AudioDirector).bpm, 120.0, 1e-9, "the level's tempo")
	planned.clear()
	for f: int in 60:
		audio.set_transport(0.0, 0.0, false)
		_frame(audio)
	assert_eq(planned.size(), 0, "no bed notes once the level owns the music")
	_free_audio(audio)


# ───────────────────────────── robustness ─────────────────────────────

## One full level loop on the real facade: count-in, takes at 1x / 2x / 0.5x restarting at beat 0,
## a rate change mid-take, the resolving pause (transport stopped), review, a menu round trip. No note
## planned twice in a take, nothing sounding after a stop, and the node tree does not grow.
func test_a_level_loop_has_no_doubled_or_stuck_notes_and_no_node_leaks() -> void:
	var audio: AudioBase = await _make_audio()
	if not assert_true(audio != null):
		return
	var lv := CampaignData.level("08-loop-pedal")
	var voices: AudioVoiceEngine = audio.call("voices")
	var planned: Array[AudioPlannedNote] = []
	audio.set("on_note_planned", func(p: AudioPlannedNote) -> void: planned.append(p))
	# A rate or layer change withdraws the notes planned for the old timing and plans them again
	# under new ids, so "planned" alone counts those twice. A withdrawn note must not have started
	# and must leave no voice behind: then planned minus withdrawn is exactly what is heard.
	var withdrawn := {}
	var bad_withdrawals: Array[int] = [0]
	var on_withdrawn := func(p: AudioPlannedNote) -> void:
		withdrawn[p.id] = true
		if not (p.time > _fake_now):
			bad_withdrawals[0] += 1
		for list: String in ["_pending", "_active"]:
			for v: Variant in voices.get(list):
				if int(v.id) == p.id:
					bad_withdrawals[0] += 1
	audio.set("on_note_cancelled", on_withdrawn)
	var nodes_before := -1
	var bpm := lv.bpm
	for loop: int in 2:
		audio.set_mode(AudioBase.MODE_MENU)
		for f: int in 30:
			_frame(audio)
		audio.load_level(lv)
		audio.set_mode(AudioBase.MODE_RECORD)
		var take_rates: Array[float] = [1.0, 0.5, 2.0]
		var doubles := 0
		for take: int in take_rates.size():
			var tracks: Array[TrackAudioState] = []
			for i: int in OD.TAPE_COUNT:
				tracks.append(D.tas({"present": i <= take, "speed": [1.0, 2.0, 0.5, 4.0][i]}))
			audio.set_tracks(tracks)
			for n: int in [5, 6, 7, 8]:
				audio.count_in(n)
				for f: int in int(60.0 * 60.0 / bpm):
					audio.set_transport(0.0, 0.0, false)
					_frame(audio)
			var start := planned.size()
			var beat := 0.0
			var rate: float = take_rates[take]
			for f: int in 360:
				if f == 180:
					rate = rate * 2.0
				var events: Array[SimEvent] = []
				if f % 20 == 0:
					events.append(_ev(&"swing", beat, bpm, take, "light"))
					var w := _ev(SimEventType.TRAP, beat, bpm, -1, "spikes:warn", 1.0)
					w.with_id("sp")
					events.append(w)
				audio.set_transport(beat, rate, true)
				audio.on_events(events)
				_frame(audio)
				beat += rate * bpm / 60.0 / 60.0
			var seen := {}
			var heard := 0
			var first_opening := 0
			for i: int in range(start, planned.size()):
				if withdrawn.has(planned[i].id):
					continue
				heard += 1
				if planned[i].note.track == 0 and planned[i].note.beat < 4.0:
					first_opening += 1
				var k := planned[i].note.key()
				if seen.has(k):
					doubles += 1
				seen[k] = true
			assert_true(heard >= 8, "loop %d take %d: the take plays (%d notes)" % [loop, take, heard])
			# The cassette recorded first sounds from the top of every later take too.
			assert_true(first_opening > 0, "loop %d take %d: cassette 1 plays in the first bar" % [loop, take])
			# The resolving pause: master time stands still for a second.
			for f: int in 60:
				audio.set_transport(beat, 0.0, false)
				_frame(audio)
			var sounding := 0
			for v: Variant in voices.get("_active"):
				if String(v.group).begins_with("layer") and _fake_now < float(v.release_wall):
					sounding += 1
			assert_eq(sounding, 0, "loop %d take %d: no music voice held through the pause" % [loop, take])
		assert_eq(doubles, 0, "loop %d: no note heard twice in a take" % loop)
		assert_eq(bad_withdrawals[0], 0, "loop %d: a re-planned note is withdrawn before it sounds, voices and all" % loop)
		# Review from beat 0 at 1x.
		var rb := 0.0
		for f: int in 240:
			audio.set_transport(rb, 1.0, true)
			_frame(audio)
			rb += bpm / 60.0 / 60.0
		audio.set_transport(0.0, 0.0, false)
		for f: int in 90:
			_frame(audio)
		var count := _count_nodes(audio)
		if loop == 0:
			nodes_before = count
		else:
			assert_eq(count, nodes_before, "no node leaks over a level loop (%d nodes)" % count)
		assert_true(voices.active_count() <= 8, "voices retire after the loop: %d active" % voices.active_count())
	assert_eq((audio.call("trap_loops") as AudioTrapLoops).sounding(), 0, "no trap loop left on")
	_free_audio(audio)


static func _count_nodes(n: Node) -> int:
	var c := 1
	for ch: Node in n.get_children():
		c += _count_nodes(ch)
	return c
