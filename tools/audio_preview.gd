extends SceneTree
## Audio preview: plays the sandbox level's music through the real audio facade
## (res://audio/audio.tscn) with all four cassette layers: the "five, six, seven, eight" count-in,
## then 8 bars, while a scripted timeline walks the layers through their states (desync, death,
## resync, reverse, stopped) and fires gameplay events. Every scheduled note and cue is logged, the
## master output is recorded to a WAV for numeric checks, and the run ends with timing statistics.
##
##   bash tools/gd shot res://tools/audio_preview.gd [-- [speeds=1,2,0.5,4] [static] [out=<dir>]]
##
##   speeds=a,b,c,d   tape speed per layer (default 1,1,1,1)
##   static           keep every layer alive and synced (no state timeline)
##   solo=<0..3>      only that cassette is present (e.g. the drum layer, for onset-timing checks)
##   nosfx            no gameplay events
##   out=<dir>        where the WAV and log go (default res://art/previews/audio/, git-ignored)
##
## Exit code 0 when it booted, played and nothing went wrong; 1 on any error. Dev tool only.

const LEVEL_ID := "sandbox"
const COUNT_BEATS := 4
const BARS := 8
const TAIL_SECONDS := 1.5

## [master beat (after the count-in), tape, what] — the state timeline (bars 1-4 untouched).
const TIMELINE: Array = [
	[16.0, 1, "desync"],
	[20.0, 3, "dead"],
	[24.0, 1, "resync"],
	[24.0, 2, "reverse"],
	[28.0, 2, "stopped"],
]
## [master beat, event type, tape, power, detail] — gameplay sounds over the music.
const EVENTS: Array = [
	[1.03, &"swing", 0, 2.0, "light"], [1.1, &"hit", 0, 2.0, ""], [3.0, &"step", 1, -1.0, ""],
	[4.55, &"swing", 1, 6.0, "heavy"], [4.62, &"hit", 1, 9.0, ""], [6.07, &"fire", 2, -1.0, "bolt"],
	[6.4, &"projectileHit", 2, 1.0, ""], [7.2, &"dodge", 0, -1.0, ""], [8.1, &"door", -1, -1.0, "on"],
	[9.3, &"plate", -1, -1.0, "on"], [10.0, &"interact", 3, -1.0, "on"], [11.6, &"enemyTelegraph", -1, -1.0, ""],
	[12.0, &"enemyAttack", -1, 4.0, ""], [12.5, &"clang", 0, 1.0, ""], [13.1, &"kill", 0, -1.0, ""],
	[14.2, &"laser", -1, -1.0, "on"], [16.0, &"desync", 1, -1.0, ""], [18.3, &"enemyShot", -1, -1.0, "shock"],
	[19.1, &"enemyStagger", -1, -1.0, ""], [20.0, &"selfDeath", 3, -1.0, ""], [21.4, &"break", 0, 10.0, ""],
	[22.2, &"tapeWrap", 0, -1.0, ""], [24.0, &"resync", 1, -1.0, ""], [24.0, &"tapeTurn", 2, -1.0, ""],
	[26.1, &"bossPhase", -1, -1.0, ""], [27.0, &"bossRecall", -1, -1.0, ""], [28.0, &"tapeEnd", 2, -1.0, ""],
	[29.3, &"core", -1, -1.0, ""], [31.0, &"objective", -1, -1.0, ""],
]

var _audio: AudioBase
var _level: LevelDef
var _speeds: Array[float] = [1.0, 1.0, 1.0, 1.0]
var _static := false
var _solo := -1
var _sfx := true
var _out_dir := "res://art/previews/audio/"
var _bpm := 120.0
var _start_usec := 0
var _counted := 0
var _beat := 0.0
var _states: Array[TrackAudioState] = []
var _timeline_i := 0
var _event_i := 0
var _done := false
var _end_usec := 0
var _log: PackedStringArray = PackedStringArray()
var _notes_by_layer: Array[int] = [0, 0, 0, 0]
var _drums := 0
var _capture: AudioEffectCapture
var _pcm: PackedVector2Array = PackedVector2Array()
var _errors: Array[String] = []
var _frames := 0
var _worst_frame := 0.0
var _last_usec := 0
## Loudest peak seen per bus (dBFS), from AudioServer's meters.
var _bus_peak: Dictionary = {}


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a == "static":
			_static = true
		elif a == "nosfx":
			_sfx = false
		elif a.begins_with("solo="):
			_solo = clampi(int(a.substr(5)), 0, OD.TAPE_COUNT - 1)
		elif a.begins_with("speeds="):
			var parts := a.substr(7).split(",")
			for i: int in mini(parts.size(), 4):
				var s := float(parts[i])
				_speeds[i] = s if OD.is_speed(s) else 1.0
		elif a.begins_with("out="):
			_out_dir = a.substr(4)
	if not _out_dir.ends_with("/"):
		_out_dir += "/"
	var errors: Array[String] = []
	_level = ContentData.load_level(LEVEL_ID, errors)
	if _level == null:
		_fail("cannot load level %s: %s" % [LEVEL_ID, errors])
		return
	_bpm = _level.bpm
	var scene := load(Facades.AUDIO_SCENE) as PackedScene
	if scene == null:
		_fail("cannot load " + Facades.AUDIO_SCENE)
		return
	_audio = scene.instantiate() as AudioBase
	if _audio == null:
		_fail("audio.tscn root does not extend AudioBase")
		return
	root.add_child(_audio)
	_audio.set("on_note_planned", _on_note)
	_say("OVERDUB audio preview: level %s, %s bpm, key root %d %s, progression %s, chordBars %d" % [
		_level.id, _bpm, _level.music.root, _level.music.scale, _level.music.progression, _level.music.chord_bars])


func _start() -> void:
	_audio.unlock()
	_audio.set_mode(AudioBase.MODE_RECORD)
	_audio.set_volumes(0.9, 0.85, 0.85)
	_audio.load_level(_level)
	var director: AudioDirector = _audio.call("director")
	for i: int in OD.TAPE_COUNT:
		var t: TrackMusicDef = _level.music.tracks[i] if i < _level.music.tracks.size() else null
		var info := director.layer(i)
		_say("  layer %s: %s / %s (level asks %s) range %d..%d at %sx%s" % [OD.tape_letter(i), info.role, info.formula,
			t.formula if t != null else "-", info.low, info.high, _speeds[i], "" if _solo < 0 or _solo == i else " (muted: solo)"])
	_say("  timeline: %s; sfx %s" % ["static (all alive, synced)" if _static else str(TIMELINE), "on" if _sfx else "off"])
	for i: int in OD.TAPE_COUNT:
		_states.append(TrackAudioState.make(_solo < 0 or _solo == i, _speeds[i], OD.LifeState.ALIVE, true, 1))
	_audio.set_tracks(_states)
	var master := AudioServer.get_bus_index(AudioBusSetup.MASTER)
	# Tap the master output after the limiter (drained every frame, written as a WAV at the end).
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 1.0
	AudioServer.add_bus_effect(master, _capture)
	var lat := AudioServer.get_output_latency()
	_say("audio: driver %s, mix rate %d Hz, output latency %.1f ms, time to next mix %.2f ms, speaker mode %d" % [
		AudioServer.get_driver_name(), int(AudioServer.get_mix_rate()), lat * 1000.0, AudioServer.get_time_to_next_mix() * 1000.0, AudioServer.get_speaker_mode()])
	var engine: AudioVoiceEngine = _audio.call("voices")
	engine.measure = true
	var bank: AudioSampleBank = _audio.call("sample_bank")
	_say("samples: %d families, pad %.0f ms, errors: %s" % [bank.families.size(), bank.pad * 1000.0, bank.errors])
	_start_usec = Time.get_ticks_usec()
	_last_usec = _start_usec


func _process(_delta: float) -> bool:
	if _audio == null:
		return true
	_frames += 1
	if _frames == 3:
		_start()
	if _frames < 3:
		return false
	var now_usec := Time.get_ticks_usec()
	if _frames > 4:
		var frame_ms := (now_usec - _last_usec) / 1000.0
		_worst_frame = maxf(_worst_frame, frame_ms)
		if frame_ms > 40.0:
			_say("[hitch] %.1f ms frame at +%.3f s" % [frame_ms, (now_usec - _start_usec) / 1000000.0])
	_last_usec = now_usec
	_drain()
	for b: int in AudioServer.bus_count:
		var n := AudioServer.get_bus_name(b)
		var pk := maxf(AudioServer.get_bus_peak_volume_left_db(b, 0), AudioServer.get_bus_peak_volume_right_db(b, 0))
		_bus_peak[n] = maxf(float(_bus_peak.get(n, -200.0)), pk)
	var t := (now_usec - _start_usec) / 1000000.0
	var beats_total := t * _bpm / 60.0
	if _done:
		if (now_usec - _end_usec) / 1000000.0 >= TAIL_SECONDS:
			_finish()
			return true
		return false
	# Count-in: four beats at the level tempo, transport stopped at 0.
	if beats_total < COUNT_BEATS:
		var n := int(floorf(beats_total))
		if n >= _counted:
			_audio.count_in(5 + n)
			_say("[count] %d at %.3f s" % [5 + n, t])
			_counted = n + 1
		_audio.set_transport(0.0, 0.0, false)
		return false
	_beat = beats_total - COUNT_BEATS
	if _beat >= BARS * OD.BEATS_PER_BAR:
		_audio.set_transport(BARS * OD.BEATS_PER_BAR, 0.0, false)
		_done = true
		_end_usec = now_usec
		_say("[end] transport stopped at bar %d" % (BARS + 1))
		return false
	if not _static:
		while _timeline_i < TIMELINE.size() and _beat >= float(TIMELINE[_timeline_i][0]):
			_apply_state(TIMELINE[_timeline_i])
			_timeline_i += 1
	_audio.set_transport(_beat, 1.0, true)
	var events: Array[SimEvent] = []
	while _sfx and _event_i < EVENTS.size() and _beat >= float(EVENTS[_event_i][0]):
		var e: Array = EVENTS[_event_i]
		var ev := SimEvent.make(int(roundf(float(e[0]) * 60.0 / _bpm * OD.SUB_HZ)), e[1], 0.0, 0.0)
		if int(e[2]) >= 0:
			ev.with_tape(int(e[2]))
		if float(e[3]) >= 0.0:
			ev.with_power(float(e[3]))
		if String(e[4]) != "":
			ev.with_detail(String(e[4]))
		events.append(ev)
		_say("[sfx] beat %6.3f  %s%s" % [float(e[0]), e[1], (" (%s)" % e[4]) if String(e[4]) != "" else ""])
		_event_i += 1
	if not events.is_empty():
		_audio.on_events(events)
	var p := _audio.pulse()
	if is_nan(p.beat) or absf(p.beat - _beat) > 0.15:
		_errors.append("pulse beat %s off transport %s" % [p.beat, _beat])
	return false


func _apply_state(step: Array) -> void:
	var tape: int = step[1]
	var what: String = step[2]
	var s := _states[tape].copy()
	match what:
		"desync":
			s.synced = false
		"resync":
			s.synced = true
		"dead":
			s.life = OD.LifeState.GHOST
		"reverse":
			s.transport = -1
		"stopped":
			s.transport = 0
	_states[tape] = s
	_audio.set_tracks(_states)
	_say("[state] beat %.2f (+%.3f s) layer %s -> %s" % [_beat, (Time.get_ticks_usec() - _start_usec) / 1000000.0, OD.tape_letter(tape), what])


func _on_note(p: AudioPlannedNote) -> void:
	var n := p.note
	_notes_by_layer[n.track] += 1
	if n.drum != &"":
		_drums += 1
	if _log.size() < 4000:
		_log.append("[note] %s beat %7.3f  %s  vel %3d  dur %.3f s  at +%.3f s" % [
			OD.tape_letter(n.track), n.beat, String(n.drum) if n.drum != &"" else "midi %d" % n.pitch, n.velocity, p.dur,
			p.time - _start_usec / 1000000.0])


func _finish() -> void:
	var voices: AudioVoiceEngine = _audio.call("voices")
	_drain()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var wav_path := _out_dir + "audio_preview%s%s.wav" % ["_static" if _static else "", "_solo%d" % _solo if _solo >= 0 else ""]
	if _pcm.is_empty():
		_errors.append("nothing was captured from the master bus")
	else:
		# The capture's frame rate is measured against wall time rather than assumed: on this
		# machine (WASAPI, Godot 4.4.1) it delivers twice the reported mix rate.
		var elapsed := (Time.get_ticks_usec() - _start_usec) / 1000000.0
		var measured := _pcm.size() / maxf(0.001, elapsed)
		var rate := int(AudioServer.get_mix_rate())
		for r: int in [22050, 32000, 44100, 48000, 88200, 96000, 176400, 192000]:
			if absf(measured - r) < absf(measured - rate):
				rate = r
		if rate != int(AudioServer.get_mix_rate()):
			_say("note: the master capture runs at %d frames/s (measured %.0f), not the reported mix rate %d" % [rate, measured, int(AudioServer.get_mix_rate())])
		var ok := _write_wav(ProjectSettings.globalize_path(wav_path), _pcm, rate)
		_say("recorded master output: %s (%.1f s at %d Hz, %s)" % [ProjectSettings.globalize_path(wav_path), float(_pcm.size()) / rate, rate, "ok" if ok else "write failed"])
		if not ok:
			_errors.append("could not write " + wav_path)
	var peaks: Array[String] = []
	for b: int in AudioServer.bus_count:
		var n := AudioServer.get_bus_name(b)
		peaks.append("%s %.1f" % [n, float(_bus_peak.get(n, -200.0))])
	_say("bus peaks (dBFS): " + ", ".join(peaks))
	if float(_bus_peak.get("Master", -200.0)) < -40.0:
		_errors.append("the master bus stayed silent")
	var total := 0
	for i: int in OD.TAPE_COUNT:
		total += _notes_by_layer[i]
	_say("scheduled notes: %d (A %d, B %d, C %d, D %d; drum hits %d)" % [total, _notes_by_layer[0], _notes_by_layer[1], _notes_by_layer[2], _notes_by_layer[3], _drums])
	_say("voices: fired %d, late %d, dropped %d, stolen %d; max late %.2f ms (immediate SFX/UI sounds included); worst frame %.1f ms" % [
		voices.fired, voices.late, voices.dropped, voices.stolen, voices.max_late * 1000.0, _worst_frame])
	_say("music voices: fired %d, late %d (max %.2f ms), on-time max |predicted error| %.2f ms" % [
		voices.music_fired, voices.music_late, voices.music_max_late * 1000.0, voices.music_max_error * 1000.0])
	var ms := voices.measured_stats()
	_say("measured music attacks (Godot playback position): %d, mean %+.2f ms, sd %.2f ms, max |error| %.2f ms" % [
		voices.measured, ms[0] * 1000.0, ms[1] * 1000.0, ms[2] * 1000.0])
	var t0 := _start_usec / 1000000.0
	for e: Array in voices.late_log:
		_say("  late music voice: due +%.3f s, %.1f ms late, %s, fired at +%.3f s" % [float(e[0]) - t0, float(e[1]) * 1000.0, e[2], float(e[3]) - t0])
	for i: int in OD.TAPE_COUNT:
		if _notes_by_layer[i] == 0 and (_solo < 0 or _solo == i):
			_errors.append("layer %s scheduled nothing" % OD.tape_letter(i))
	if voices.fired == 0:
		_errors.append("no voice fired")
	if _counted != COUNT_BEATS:
		_errors.append("count-in played %d of %d" % [_counted, COUNT_BEATS])
	var log_path := _out_dir + "audio_preview.log"
	var f := FileAccess.open(log_path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log) + "\n")
		f.close()
		_say("event log: %s (%d lines)" % [ProjectSettings.globalize_path(log_path), _log.size()])
	for i: int in mini(24, _log.size()):
		if _log[i].begins_with("[note]"):
			print(_log[i])
	for e: String in _errors:
		push_error("audio preview: " + e)
	print("[audio preview] %s" % ("OK" if _errors.is_empty() else "FAILED: %d problem(s)" % _errors.size()))
	_audio.dispose()
	quit(0 if _errors.is_empty() else 1)


func _drain() -> void:
	if _capture == null:
		return
	var n := _capture.get_frames_available()
	if n > 0:
		_pcm.append_array(_capture.get_buffer(n))
	if _capture.get_discarded_frames() > 0 and not _errors.has("capture overflow"):
		_errors.append("capture overflow")


## 16-bit stereo PCM WAV.
static func _write_wav(path: String, frames: PackedVector2Array, rate: int) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var data := PackedByteArray()
	data.resize(frames.size() * 4)
	for i: int in frames.size():
		data.encode_s16(i * 4, clampi(int(roundf(frames[i].x * 32767.0)), -32768, 32767))
		data.encode_s16(i * 4 + 2, clampi(int(roundf(frames[i].y * 32767.0)), -32768, 32767))
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(2)
	f.store_32(rate)
	f.store_32(rate * 4)
	f.store_16(4)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
	return true


func _say(s: String) -> void:
	_log.append(s)
	print(s)


func _fail(msg: String) -> void:
	push_error("audio preview: " + msg)
	quit(1)
