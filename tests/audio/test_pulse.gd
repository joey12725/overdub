extends ODTest
## MusicPulse from what was actually scheduled, and the audio facade end to end (port of
## prototype/tests/audio/engine.test.ts), plus the bus layout contract. Runs headless: the facade
## is driven on a fake listening clock through its `time_source` hook.

const D := preload("res://tests/audio/test_director.gd")
const AUDIO_SCENE := "res://audio/audio.tscn"

var _fake_now: float = 100.0


func _pulse_sane(p: MusicPulse, where: String) -> bool:
	var ok := true
	var values: Array[float] = [p.beat, p.beat_pulse, p.bar_pulse, float(p.chord)]
	for x: float in p.levels:
		values.append(x)
	for x: float in p.pitches:
		values.append(x)
	for x: float in values:
		if is_nan(x) or is_inf(x):
			ok = false
	var unit: Array[float] = [p.beat_pulse, p.bar_pulse]
	for x: float in p.levels:
		unit.append(x)
	for x: float in p.pitches:
		unit.append(x)
	for x: float in unit:
		if x < 0.0 or x > 1.0:
			ok = false
	if p.levels.size() != 4 or p.pitches.size() != 4:
		ok = false
	return assert_true(ok, "%s: pulse finite and in range (beat %s bp %s bar %s levels %s pitches %s chord %s)" % [where, p.beat, p.beat_pulse, p.bar_pulse, p.levels, p.pitches, p.chord])


func _make_audio() -> AudioBase:
	var scene := load(AUDIO_SCENE) as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate()
	var audio := node as AudioBase
	if audio == null:
		node.free()
		return null
	audio.set("time_source", func() -> float: return _fake_now)
	tree().root.add_child(audio)
	# Suites can run before the main loop starts (inside the runner's _initialize), when nodes
	# added to the root are not readied yet: wait for _ready (bus layout, sample bank, voices).
	var frames := 0
	while not audio.is_node_ready() and frames < 10:
		await tree().process_frame
		frames += 1
	return audio


func _frame(audio: AudioBase, dt: float = 1.0 / 60.0) -> void:
	_fake_now += dt
	audio.call("_process", dt)


func _free_audio(audio: AudioBase) -> void:
	if audio != null and is_instance_valid(audio):
		audio.dispose()
		audio.get_parent().remove_child(audio)
		audio.free()


# ───────────────────────────── PulseMeter ─────────────────────────────

func test_silent_pulse_and_pulse_meter_stay_finite_on_odd_input() -> void:
	_pulse_sane(AudioPulseMeter.silent_pulse(NAN, 0), "silent NaN")
	_pulse_sane(AudioPulseMeter.silent_pulse(INF, -3), "silent inf")
	var m := AudioPulseMeter.new()
	m.add(AudioPlannedNote.make(1, AudioLayerNote.make(0, 0.0, 1.0, 60, 127, 2.0, 0), 1.0, 0.5))
	m.add(AudioPlannedNote.make(2, AudioLayerNote.make(9, 0.0, 1.0, 60, 127, 0.5, 0), 1.0, 0.5))
	_pulse_sane(m.sample(1.01, INF, 2), "inf beat")
	_pulse_sane(m.sample(1.01, NAN, -1), "nan beat")
	m.cancel([1] as Array[int])
	assert_eq(m.sample(1.02, 0, 0).levels[0], 0.0, "a cancelled note shows no level")


func test_pulse_levels_come_only_from_notes_whose_start_has_passed() -> void:
	var m := AudioPulseMeter.new()
	m.add(AudioPlannedNote.make(1, AudioLayerNote.make(1, 4.0, 1.0, 60, 100, 0.8, 0), 2.0, 0.5))
	assert_eq(m.sample(1.99, 3.9, 0).levels[1], 0.0, "not yet heard")
	var at := m.sample(2.0, 4.0, 0)
	assert_near(at.levels[1], 100.0 / 127.0, 1e-6, "full level on the onset")
	assert_near(at.pitches[1], 0.8, 1e-6, "pitch from the note")
	var later := m.sample(2.3, 4.6, 0).levels[1]
	assert_true(later > 0.2 and later < at.levels[1], "decays while held: %s" % later)
	assert_eq(m.sample(5.0, 10.0, 0).levels[1], 0.0, "silent long after")
	# Pitch is held after the note ends (visuals keep their last height).
	assert_near(m.sample(5.0, 10.0, 0).pitches[1], 0.8, 1e-6)


func test_chords_report_their_top_voice() -> void:
	var m := AudioPulseMeter.new()
	for i: int in 3:
		m.add(AudioPlannedNote.make(i + 1, AudioLayerNote.make(3, 0.0, 2.0, 60 + i * 4, 90, 0.3 + i * 0.2, 0), 1.0, 1.0))
	assert_near(m.sample(1.1, 0.2, 0).pitches[3], 0.7, 1e-6)


func test_a_choke_ends_the_sustain_of_sounding_notes() -> void:
	var m := AudioPulseMeter.new()
	m.add(AudioPlannedNote.make(1, AudioLayerNote.make(0, 0.0, 8.0, 60, 127, 0.5, 0), 1.0, 4.0))
	assert_true(m.sample(2.5, 3.0, 0).levels[0] >= 0.34, "held note sustains")
	m.choke(2.5)
	assert_true(m.sample(3.0, 4.0, 0).levels[0] < 0.2, "choked note decays")


func test_beat_and_bar_pulses_peak_on_the_grid() -> void:
	assert_eq(AudioPulseMeter.beat_pulse(3.0), 1.0)
	assert_true(AudioPulseMeter.beat_pulse(3.99) < 0.02)
	assert_eq(AudioPulseMeter.bar_pulse(8.0), 1.0)
	assert_near(AudioPulseMeter.bar_pulse(10.0), 0.5, 1e-9)


# ───────────────────────────── facade ─────────────────────────────

func test_the_audio_scene_root_extends_audio_base() -> void:
	assert_true(ResourceLoader.exists(AUDIO_SCENE))
	var audio: AudioBase = await _make_audio()
	if not assert_true(audio != null, "audio.tscn instantiates an AudioBase"):
		return
	assert_true(Facades.is_provided(Facades.AUDIO_SCENE), "the facade path is provided")
	_free_audio(audio)


func test_every_method_is_safe_before_load_after_load_and_after_dispose() -> void:
	var audio: AudioBase = await _make_audio()
	if not assert_true(audio != null):
		return
	_pulse_sane(audio.pulse(), "fresh")
	audio.unlock()
	audio.ui(AudioBase.UI_SELECT)
	audio.count_in(5)
	audio.on_events([SimEvent.make(0, SimEventType.HIT, 0, 0).with_tape(0).with_power(2.0)] as Array[SimEvent])
	audio.load_level(D.standard_level())
	audio.set_mode(AudioBase.MODE_CINEMATIC)
	audio.set_volumes(0.5, 0.7, 0.9)
	audio.set_volumes(50, 70, 90)
	audio.set_tracks(D.tracks4(D.tas(), D.tas({"speed": 2.0}), D.tas({"life": OD.LifeState.GHOST}), D.tas({"transport": -1})))
	audio.set_tracks([] as Array[TrackAudioState])
	audio.set_transport(0, 1, true)
	audio.set_transport(NAN, INF, true)
	audio.set_transport(0, 1, true)
	audio.on_events([SimEvent.make(10, SimEventType.KILL, 0, 0)] as Array[SimEvent])
	audio.count_in(8)
	audio.count_in(3)
	for kind: StringName in AudioBase.UI_KINDS:
		audio.ui(kind)
	audio.ui(&"no-such-kind")
	audio.load_level(null)
	for i: int in 20:
		_frame(audio)
	_pulse_sane(audio.pulse(), "loaded")
	audio.dispose()
	audio.dispose()
	_pulse_sane(audio.pulse(), "disposed")
	audio.set_transport(1, 1, true)
	audio.on_events([SimEvent.make(10, SimEventType.KILL, 0, 0)] as Array[SimEvent])
	_frame(audio)
	_free_audio(audio)


func test_pulse_follows_the_transport_and_what_was_scheduled() -> void:
	var audio: AudioBase = await _make_audio()
	if not assert_true(audio != null):
		return
	audio.load_level(D.standard_level())
	audio.set_tracks(D.tracks4(D.tas(), D.tas(), D.tas(), D.tas({"present": false})))
	var beat := 0.0
	var saw := [0.0, 0.0, 0.0, 0.0]
	var saw_beat := false
	var saw_bar := false
	var sane := true
	var off_beat := 0
	var off_chord := 0
	for f: int in 600:
		_fake_now += 1.0 / 60.0
		beat += 2.0 / 60.0  # 120 bpm, rate 1
		audio.set_transport(beat, 1, true)
		audio.call("_process", 1.0 / 60.0)
		var p := audio.pulse()
		if sane and not _pulse_sane(p, "frame %d" % f):
			sane = false
		if absf(p.beat - beat) >= 0.1:
			off_beat += 1
		for i: int in 4:
			saw[i] = maxf(saw[i], p.levels[i])
		if p.beat_pulse > 0.9:
			saw_beat = true
		if p.bar_pulse > 0.9:
			saw_bar = true
		if p.chord != int(floorf(beat / 4.0)) % 4:
			off_chord += 1
	assert_eq(off_beat, 0, "pulse beat tracks the transport")
	assert_eq(off_chord, 0, "pulse chord follows the progression")
	for i: int in 3:
		assert_true(saw[i] > 0.2, "layer %d shows level %s" % [i, saw[i]])
	# A cassette that is not present makes no sound and so shows no level.
	assert_eq(saw[3], 0.0)
	assert_true(saw_beat and saw_bar)
	# Notes were handed to sample voices (the library loaded and voices fired).
	var voices: AudioVoiceEngine = audio.call("voices")
	assert_true(voices.fired > 50, "voices fired: %d" % voices.fired)
	var bank: AudioSampleBank = audio.call("sample_bank")
	assert_eq(bank.errors, [] as Array[String], "sample library loaded")
	# Pausing lets the levels decay to silence.
	audio.set_transport(beat, 0, false)
	for i: int in 180:
		_frame(audio)
	var quiet := audio.pulse()
	assert_eq(quiet.levels[0] + quiet.levels[1] + quiet.levels[2] + quiet.levels[3], 0.0, "silent after a pause: %s" % quiet.levels)
	_free_audio(audio)


func test_a_take_restart_replays_from_beat_0_without_doubling() -> void:
	var audio: AudioBase = await _make_audio()
	if not assert_true(audio != null):
		return
	audio.load_level(D.standard_level())
	audio.set_tracks(D.tracks4(D.tas(), D.tas(), D.tas(), D.tas()))
	var planned: Array[AudioPlannedNote] = []
	audio.set("on_note_planned", func(p: AudioPlannedNote) -> void: planned.append(p))
	for take: int in 2:
		var beat := 0.0
		for f: int in 240:
			_fake_now += 1.0 / 60.0
			audio.set_transport(beat, 1, true)
			audio.call("_process", 1.0 / 60.0)
			beat += 2.0 / 60.0
	# Both takes planned the same opening, each once.
	var by_key := {}
	for p: AudioPlannedNote in planned:
		var k := p.note.key()
		by_key[k] = int(by_key.get(k, 0)) + 1
	var too_many := 0
	for k: String in by_key:
		if int(by_key[k]) > 2:
			too_many += 1
	assert_true(planned.size() > 40, "music was planned: %d" % planned.size())
	assert_eq(too_many, 0, "no note more than once per take")
	var at_zero := 0
	for p: AudioPlannedNote in planned:
		if p.note.beat < 1e-9:
			at_zero += 1
	assert_true(at_zero >= 2 and at_zero % 2 == 0, "the downbeat sounds in both takes: %d" % at_zero)
	_free_audio(audio)


func test_set_mode_and_volumes_drive_the_mixer() -> void:
	var audio: AudioBase = await _make_audio()
	if not assert_true(audio != null):
		return
	var mixer: AudioMixer = audio.call("mixer")
	audio.set_mode(AudioBase.MODE_CINEMATIC)
	var cine: Dictionary = mixer.mode_targets()
	audio.set_mode(AudioBase.MODE_RECORD)
	var rec: Dictionary = mixer.mode_targets()
	assert_true(float(cine["width"]) > float(rec["width"]), "cinematic is wider")
	assert_true(float(cine["reverb"]) > float(rec["reverb"]), "and roomier")
	assert_true(float(cine["air"]) > float(rec["air"]), "and brighter")
	audio.set_mode(AudioBase.MODE_MENU)
	assert_true(float(mixer.mode_targets()["tone"]) < 19000.0, "menus sit back")
	# Dead and desynced layers are recoloured on their own bus.
	mixer.set_roles([MusicRole.MELODY, MusicRole.BASS, MusicRole.DRUMS, MusicRole.CHORD] as Array[StringName])
	mixer.set_layer_colour(0, AudioMixer.Colour.make(true, false, 0.0, 1.0))
	var alive: Dictionary = mixer.layer_targets(0)
	mixer.set_layer_colour(0, AudioMixer.Colour.make(true, true, 0.0, 1.0))
	var dead: Dictionary = mixer.layer_targets(0)
	mixer.set_layer_colour(0, AudioMixer.Colour.make(true, false, 1.0, 1.0))
	var desync: Dictionary = mixer.layer_targets(0)
	assert_true(float(dead["lp"]) < float(alive["lp"]) and float(dead["hp"]) > float(alive["hp"]), "dead is band-limited")
	assert_true(float(desync["chorus"]) > 0.5 and float(desync["lp"]) < float(alive["lp"]), "desync is chorused and darker")
	mixer.set_layer_colour(0, AudioMixer.Colour.make(false, false, 0.0, 1.0))
	assert_eq(float(mixer.layer_targets(0)["level"]), 0.0, "an absent cassette is silent")
	for i: int in 60:
		_frame(audio)
	var master := AudioServer.get_bus_index(AudioBusSetup.MASTER)
	audio.set_volumes(0.0, 0.5, 0.5)
	for i: int in 60:
		_frame(audio)
	assert_true(AudioServer.get_bus_volume_db(master) <= -60.0, "master fader reaches silence")
	audio.set_volumes(1.0, 1.0, 1.0)
	for i: int in 60:
		_frame(audio)
	assert_near(AudioServer.get_bus_volume_db(master), 0.0, 0.1, "and unity")
	_free_audio(audio)


# ───────────────────────────── bus layout ─────────────────────────────

func test_every_bus_sends_to_an_earlier_bus() -> void:
	assert_true(AudioBusSetup.is_valid_order(), "plan order")
	var audio: AudioBase = await _make_audio()
	if not assert_true(audio != null):
		return
	assert_true(AudioBusSetup.is_current(), "the live layout is the plan")
	for i: int in range(1, AudioServer.bus_count):
		var send := AudioServer.get_bus_index(AudioServer.get_bus_send(i))
		assert_true(send >= 0 and send < i, "%s sends to %s (index %d < %d)" % [AudioServer.get_bus_name(i), AudioServer.get_bus_send(i), send, i])
	var master := AudioServer.get_bus_index(AudioBusSetup.MASTER)
	assert_true(AudioServer.get_bus_effect(master, AudioBusSetup.MASTER_SAT) is AudioEffectDistortion, "tape saturation on the master")
	assert_true(AudioServer.get_bus_effect(master, AudioBusSetup.MASTER_LIMIT) is AudioEffectHardLimiter, "limiter last on the master")
	for i: int in OD.TAPE_COUNT:
		var l := AudioServer.get_bus_index(AudioBusSetup.LAYERS[i])
		assert_true(l > 0, "layer bus %d" % i)
		assert_true(AudioServer.get_bus_effect(l, AudioBusSetup.LAYER_CHORUS) is AudioEffectChorus)
		assert_true(AudioServer.get_bus_effect(l, AudioBusSetup.LAYER_LP) is AudioEffectLowPassFilter)
	_free_audio(audio)


func test_the_saved_default_bus_layout_matches_the_plan() -> void:
	var path := "res://default_bus_layout.tres"
	if not assert_true(FileAccess.file_exists(path), path):
		return
	var text := FileAccess.get_file_as_string(path)
	var names: Array[String] = []
	var sends: Array[String] = []
	var re := RegEx.create_from_string("bus/(\\d+)/(name|send) = &\"([^\"]*)\"")
	var by_index := {}
	for m: RegExMatch in re.search_all(text):
		var i := int(m.get_string(1))
		if not by_index.has(i):
			by_index[i] = ["Master", ""]
		if m.get_string(2) == "name":
			by_index[i][0] = m.get_string(3)
		else:
			by_index[i][1] = m.get_string(3)
	var plan := AudioBusSetup.plan()
	for i: int in range(1, plan.size()):
		if not assert_true(by_index.has(i), "bus %d saved" % i):
			return
		names.append(String(by_index[i][0]))
		sends.append(String(by_index[i][1]))
	var want_names: Array[String] = []
	for i: int in range(1, plan.size()):
		want_names.append(String(plan[i][0]))
	assert_eq(names, want_names, "saved bus order")
	assert_true(load(path) is AudioBusLayout, "the layout loads")
