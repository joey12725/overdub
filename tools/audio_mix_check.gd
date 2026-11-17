extends SceneTree
## Mix check: plays one full take of a level through the real audio facade (count-in, every cassette
## present, a dense stream of gameplay and trap events, two dialogue lines and a bark) and records
## the Music, Sfx, Ui, Voice and Master buses separately, with the fader / duck gains per mix chunk,
## so art/audio/mix_check.py can measure loudness per bus, master headroom, clipping and dialogue
## intelligibility over the ducked music.
##
##   bash tools/gd shot res://tools/audio_mix_check.gd [-- level=<id>] [bars=<n>] [out=<dir>]
##   python -I art/audio/mix_check.py <dir>
##
## Writes <dir>/<bus>.wav (16-bit stereo) and <dir>/mix.json. Default dir: %TEMP%/overdub_mix.
## Dev tool only; exit 0 when it played and recorded.

const COUNT_BEATS := 4
const TAIL_SECONDS := 1.0
const BUSES: Array[StringName] = [&"Master", &"Music", &"Sfx", &"Ui", &"Voice"]

var _audio: AudioBase
var _level: LevelDef
var _bpm := 120.0
var _bars := 0
var _out := ""
var _frames := 0
var _start_usec := 0
var _counted := 0
var _done := false
var _end_usec := 0
var _caps: Dictionary = {}
var _pcm: Dictionary = {}
## [frame index into the Master capture, {bus: gain}] per process frame.
var _gains: Array = []
## Speech windows [start s, end s, kind, id] relative to the start of the capture.
var _speech: Array = []
var _events_fired := 0
var _next_event_beat := 0.0
var _lines_due: Array = []
var _errors: Array[String] = []


func _initialize() -> void:
	var id := "12-master-tape"
	_out = OS.get_environment("TEMP").path_join("overdub_mix")
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("level="):
			id = a.substr(6)
		elif a.begins_with("bars="):
			_bars = int(a.substr(5))
		elif a.begins_with("out="):
			_out = a.substr(4)
	_level = CampaignData.level(id)
	if _level == null:
		push_error("mix check: no level " + id)
		quit(1)
		return
	_bpm = _level.bpm
	if _bars <= 0:
		_bars = maxi(4, _level.bars)
	var scene := load(Facades.AUDIO_SCENE) as PackedScene
	_audio = scene.instantiate() as AudioBase
	root.add_child(_audio)
	print("mix check: level %s, %s bpm, %d bars, out %s" % [_level.id, _bpm, _bars, _out])


func _start() -> void:
	_audio.unlock()
	_audio.set_volumes(0.8, 0.8, 0.8)
	_audio.set_voice_options(AudioBase.VOICES_ON, true, 1.0)
	_audio.load_level(_level)
	_audio.set_mode(AudioBase.MODE_RECORD)
	var speeds: Array[float] = [2.0, 4.0, 2.0, 2.0] if _level.speeds.has(4.0) else [1.0, 2.0, 1.0, 0.5]
	var tracks: Array[TrackAudioState] = []
	for i: int in OD.TAPE_COUNT:
		var s: float = speeds[i] if _level.speeds.has(speeds[i]) else 1.0
		tracks.append(TrackAudioState.make(i < maxi(1, _level.max_tapes), s, OD.LifeState.ALIVE, true, 1))
	_audio.set_tracks(tracks)
	for b: StringName in BUSES:
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 2.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(b), cap)
		_caps[b] = cap
		_pcm[b] = PackedVector2Array()
	# Speech: a Moxie line in bar 2, the Archivist (the lowest voice) in bar 4, a bark in bar 6.
	var beat_s := 60.0 / _bpm
	_lines_due = [
		[(COUNT_BEATS + 4.5) * beat_s, "line", "levels.%s.intro[0]" % _level.id, ""],
		[(COUNT_BEATS + 12.5) * beat_s, "line", _archivist_line(), ""],
		[(COUNT_BEATS + 20.5) * beat_s, "bark", _moxie_bark(), "mixcheck"],
	]
	_start_usec = Time.get_ticks_usec()


func _archivist_line() -> String:
	var m: Variant = ODJson.read_file(AudioVoiceLines.MANIFEST_PATH)
	for id: String in (m as Dictionary)["lines"]:
		var l: Dictionary = (m as Dictionary)["lines"][id]
		if str(l["character"]) == "archivist" and str(l["kind"]) == "line" and float(l["duration"]) > 3.0:
			return id
	return ""


func _moxie_bark() -> String:
	var m: Variant = ODJson.read_file(AudioVoiceLines.MANIFEST_PATH)
	for id: String in (m as Dictionary)["lines"]:
		var l: Dictionary = (m as Dictionary)["lines"][id]
		if str(l["character"]) == "moxie" and str(l["kind"]) == "bark" and float(l["duration"]) > 1.2:
			return id
	return ""


func _process(_delta: float) -> bool:
	if _audio == null:
		return true
	_frames += 1
	if _frames == 3:
		_start()
	if _frames < 3:
		return false
	_drain()
	var now_usec := Time.get_ticks_usec()
	var t := (now_usec - _start_usec) / 1000000.0
	var mixer: AudioMixer = _audio.call("mixer")
	_gains.append([(_pcm[&"Master"] as PackedVector2Array).size(), mixer.bus_gains()])
	if _done:
		if (now_usec - _end_usec) / 1000000.0 >= TAIL_SECONDS:
			_finish()
			return true
		return false
	while not _lines_due.is_empty() and t >= float(_lines_due[0][0]):
		var l: Array = _lines_due.pop_front()
		var dur := 0.0
		if l[1] == "line":
			dur = _audio.play_line(l[2])
		else:
			var sp: AudioVoiceLines = _audio.call("speech")
			dur = sp.play_bark(l[2], l[3], "moxie", true, Time.get_ticks_usec() / 1000000.0)
		if dur <= 0.0:
			_errors.append("speech %s %s did not play" % [l[1], l[2]])
		_speech.append([t, t + dur, l[1], l[2]])
		print("[speech] %s %s at %.2f s for %.2f s" % [l[1], l[2], t, dur])
	var beats := t * _bpm / 60.0
	if beats < COUNT_BEATS:
		var n := int(floorf(beats))
		if n >= _counted:
			_audio.count_in(5 + n)
			_counted = n + 1
		_audio.set_transport(0.0, 0.0, false)
		return false
	var beat := beats - COUNT_BEATS
	if beat >= _bars * OD.BEATS_PER_BAR:
		_audio.set_transport(_bars * OD.BEATS_PER_BAR, 0.0, false)
		_done = true
		_end_usec = now_usec
		return false
	_audio.set_transport(beat, 1.0, true)
	var events: Array[SimEvent] = []
	while _next_event_beat <= beat:
		_add_events(_next_event_beat, events)
		_next_event_beat += 0.5
	if not events.is_empty():
		_events_fired += events.size()
		_audio.on_events(events)
	return false


## A busy fight: steps from every self, swings and hits, enemy attacks, and the level's machines.
func _add_events(b: float, out: Array[SimEvent]) -> void:
	var sub := int(roundf(b * 60.0 / _bpm * OD.SUB_HZ)) + 7
	var step := int(roundf(b * 2.0))
	for tape: int in mini(4, _level.max_tapes):
		out.append(SimEvent.make(sub + tape, SimEventType.STEP, 0, 0).with_tape(tape))
		if (step + tape) % 4 == 1:
			out.append(SimEvent.make(sub, SimEventType.SWING, 0, 0).with_tape(tape).with_detail("heavy" if tape == 1 else "light"))
		if (step + tape) % 4 == 2:
			out.append(SimEvent.make(sub, SimEventType.HIT, 0, 0).with_tape(tape).with_power(2.0 + 3.0 * tape))
	if step % 8 == 3:
		out.append(SimEvent.make(sub, SimEventType.ENEMY_TELEGRAPH, 0, 0))
	if step % 8 == 5:
		out.append(SimEvent.make(sub, SimEventType.ENEMY_ATTACK, 0, 0).with_power(4.0))
	if step % 16 == 11:
		out.append(SimEvent.make(sub, SimEventType.KILL, 0, 0))
	if step % 8 == 6:
		out.append(SimEvent.make(sub, SimEventType.TRAP, 0, 0).with_id("sp").with_detail("spikes:warn").with_power(1.0))
	if step % 8 == 0 and step > 0:
		out.append(SimEvent.make(sub, SimEventType.TRAP, 0, 0).with_id("sp").with_detail("spikes:up"))
	if step % 16 == 14:
		out.append(SimEvent.make(sub, SimEventType.TRAP, 0, 0).with_id("cr").with_detail("crusher:warn").with_power(1.0))
	if step % 16 == 0 and step > 0:
		out.append(SimEvent.make(sub, SimEventType.TRAP, 0, 0).with_id("cr").with_detail("crusher:slam").with_power(1.0))
	if step % 6 == 4:
		out.append(SimEvent.make(sub, SimEventType.TRAP, 0, 0).with_id("dt").with_detail("dart:fire"))
	if step == 2:
		out.append(SimEvent.make(sub, SimEventType.TRAP, 0, 0).with_id("belt").with_detail("conveyor:on"))


func _drain() -> void:
	for b: StringName in BUSES:
		var cap: AudioEffectCapture = _caps.get(b)
		if cap == null:
			continue
		var n := cap.get_frames_available()
		if n > 0:
			(_pcm[b] as PackedVector2Array).append_array(cap.get_buffer(n))
		if cap.get_discarded_frames() > 0 and not _errors.has("overflow " + b):
			_errors.append("overflow " + b)


func _finish() -> void:
	_drain()
	DirAccess.make_dir_recursive_absolute(_out)
	var elapsed := (Time.get_ticks_usec() - _start_usec) / 1000000.0
	var master: PackedVector2Array = _pcm[&"Master"]
	var measured := master.size() / maxf(0.001, elapsed)
	var rate := int(AudioServer.get_mix_rate())
	for r: int in [44100, 48000, 88200, 96000]:
		if absf(measured - r) < absf(measured - rate):
			rate = r
	var sizes := {}
	for b: StringName in BUSES:
		var pcm: PackedVector2Array = _pcm[b]
		sizes[String(b)] = pcm.size()
		_write_wav(_out.path_join("%s.wav" % String(b).to_lower()), pcm, rate)
	var meta := {
		"level": _level.id, "bpm": _bpm, "bars": _bars, "rate": rate, "measuredRate": measured, "mixRate": AudioServer.get_mix_rate(),
		"countBeats": COUNT_BEATS, "elapsed": elapsed, "sizes": sizes, "speech": _speech, "gains": _gains,
		"events": _events_fired, "errors": _errors,
		"voices": {"fired": (_audio.call("voices") as AudioVoiceEngine).fired, "dropped": (_audio.call("voices") as AudioVoiceEngine).dropped,
			"stolen": (_audio.call("voices") as AudioVoiceEngine).stolen},
	}
	var f := FileAccess.open(_out.path_join("mix.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	f.close()
	print("mix check: recorded %.1f s at %d Hz (measured %.0f), %d events, buses %s, errors %s" % [elapsed, rate, measured, _events_fired, sizes, _errors])
	_audio.dispose()
	quit(0 if _errors.is_empty() else 1)


static func _write_wav(path: String, frames: PackedVector2Array, rate: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
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
