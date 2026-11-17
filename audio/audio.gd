extends AudioBase
## The audio facade (res://audio/audio.tscn root; prototype src/audio/engine.ts). Wires the pure
## music logic (AudioDirector, AudioSequencer, AudioScheduler, AudioSfx, AudioPulseMeter) to sample
## playback (AudioVoiceEngine over AudioSampleBank), the bus layout (AudioBusSetup, AudioMixer), the
## composer's data (AudioScore: data/music/<level>.json), spoken voice (AudioVoiceLines) and the
## sustained trap sounds (AudioTrapLoops).
##
## Clock: everything is planned on one listening clock, Time.get_ticks_usec(), in seconds. A
## planned time means "heard at"; AudioVoiceEngine compensates for mix scheduling and output
## latency, so pulse() — computed from what was planned, at `now` — matches what is heard.
##
## Menu bed (docs/MUSIC.md integration step 4): in MODE_MENU the facade plays data/music/menu.json on
## its own clock (72 bpm, cassettes 1-3 at half speed, no drums) and ignores the game's transport;
## load_level() or any other mode hands the music back to the level.
##
## Safe everywhere: every method works before a level is loaded (a calm A-minor fallback key for UI
## and count-in sounds), headless, and after dispose().

## After this long without set_transport the frame loop has stalled: stop the music.
const STALE_TRANSPORT := 0.25
## Seconds the music stays ducked after a line ends (VOICE-CAST 6.3).
const DUCK_HOLD := 0.15

var _director: AudioDirector
var _loaded := false
var _level: LevelDef = null
var _score: AudioScore = null
var _seq: AudioSequencer
var _sched: AudioScheduler
var _planner := AudioSfx.Planner.new()
var _meter := AudioPulseMeter.new()
var _bank := AudioSampleBank.new()
var _voices: AudioVoiceEngine
var _speech: AudioVoiceLines
var _loops: AudioTrapLoops
var _mixer := AudioMixer.new()
var _tracks: Array[TrackAudioState] = []
var _t_beat := 0.0
var _t_rate := 0.0
var _t_playing := false
var _t_at := 0.0
var _volumes := Vector3(0.8, 0.8, 0.8)
var _mode: StringName = AudioBase.MODE_RECORD
var _colour_key := ""
var _disposed := false
var _lookahead := 0.15
## Menu bed state: the level director is parked while the bed plays.
var _menu_active := false
var _menu_started_at := 0.0
var _level_director: AudioDirector = null
var _level_tracks: Array[TrackAudioState] = []
## Speech that has ended but still holds the duck (until this time).
var _duck_until := -INF
var _duck_kind := 0
## Dialogue wiring (connect_dialogue).
var _dlg_kind: StringName = &""
var _dlg_key: String = ""
## Optional observer for tools: called with (planned: AudioPlannedNote) for every started note.
var on_note_planned: Callable = Callable()
## Optional observer for tools: called with (planned: AudioPlannedNote) for every planned note that
## was withdrawn before it sounded (a rate or layer change re-plans it: it is then reported to
## on_note_planned again under a new id). Planned minus cancelled = what is heard.
var on_note_cancelled: Callable = Callable()
## Optional clock override for tests (returns seconds); the default is Time.get_ticks_usec().
var time_source: Callable = Callable()
## Which music block the last load_level used: "level" (merged in data/levels) or "score"
## (data/music, because the level's block differed). For tools and tests.
var music_source: String = ""


func _init() -> void:
	for i: int in OD.TAPE_COUNT:
		_tracks.append(AudioSequencer.silent_track())
	_director = AudioDirector.new(_fallback_level())
	_seq = AudioSequencer.new(_director)
	_sched = _make_scheduler()


func _ready() -> void:
	AudioBusSetup.ensure()
	if not _bank.load_manifest(true):
		push_error("Audio: sample library incomplete: %s" % "; ".join(_bank.errors))
	_voices = AudioVoiceEngine.new(_bank)
	_voices.name = "Voices"
	add_child(_voices)
	_speech = AudioVoiceLines.new()
	_speech.name = "Speech"
	if not _speech.errors.is_empty():
		push_warning("Audio: voice manifest: %s" % "; ".join(_speech.errors))
	add_child(_speech)
	_loops = AudioTrapLoops.new()
	_loops.name = "TrapLoops"
	_loops.bank = _bank
	add_child(_loops)
	if _level != null:
		_loops.setup(_level, _director.root)
	_mixer.attach()
	_mixer.set_roles(_roles())
	_mixer.set_mode(_mode)
	_mixer.set_volumes(_volumes.x, _volumes.y, _volumes.z)
	# Plan far enough ahead to cover the device latency and the voice engine's fire window.
	_lookahead = clampf(AudioServer.get_output_latency() + 0.11, 0.15, 0.5)
	_sched = _make_scheduler()
	set_process(true)


func _exit_tree() -> void:
	if _voices != null and not _disposed:
		_voices.stop_all(_now())
	if _speech != null:
		_speech.stop_all()
	if _loops != null:
		_loops.stop_all()


## Harmony for UI / count-in sounds before any level is loaded: A minor, calm tempo.
static func _fallback_level() -> LevelDef:
	var l := LevelDef.new()
	l.bpm = 100.0
	var m := LevelMusicDef.new()
	m.root = 9
	m.scale = "Minor"
	m.progression = [0]
	var specs: Array = [[MusicRole.MELODY, "sine"], [MusicRole.BASS, "triangle"], [MusicRole.DRUMS, "euclid"], [MusicRole.CHORD, "sine"]]
	for s: Array in specs:
		var t := TrackMusicDef.new()
		t.role = s[0]
		t.formula = s[1]
		m.tracks.append(t)
	l.music = m
	return l


## The level as the director should hear it: the composer's piece (data/music/<id>.json) when the
## level's own block differs from it at the same tempo (not merged yet, or edited by hand).
static func music_level(level: LevelDef, score: AudioScore) -> LevelDef:
	if score == null or score.music == null or level == null:
		return level
	if not is_equal_approx(score.bpm, level.bpm):
		push_warning("Audio: %s: the composer's piece is at %s bpm, the level at %s; playing the level's block" % [level.id, score.bpm, level.bpm])
		return level
	if ODJson.deep_equal(level.music.to_dict(), score.music.to_dict(), 1e-9):
		return level
	var l := LevelDef.new()
	l.id = level.id
	l.bpm = level.bpm
	l.music = score.music.copy()
	return l


# ───────────────────────────── AudioBase ─────────────────────────────

func unlock() -> void:
	# Godot's audio output is always running; nothing to resume. Kept for the contract.
	if _disposed:
		return
	_tick(_now())


func load_level(level: LevelDef) -> void:
	if _disposed or level == null:
		return
	var now := _now()
	_end_menu_bed(now, false)
	_stop_all_music(now)
	_level = level
	_score = AudioScore.for_id(level.id)
	var heard := music_level(level, _score)
	music_source = "level" if heard == level else "score"
	if music_source == "score":
		print("[audio] %s: playing the composer's piece from data/music (the level's music block differs)" % level.id)
	_director = AudioDirector.new(heard)
	_loaded = true
	_seq = AudioSequencer.new(_director)
	_sched = _make_scheduler()
	_meter.clear()
	_planner.reset()
	_planner.policy = _score
	_seq.set_tracks(_tracks, _current_beat(now))
	_mixer.set_roles(_roles())
	_colour_key = ""
	if _loops != null:
		_loops.setup(level, _director.root)
	if _speech != null:
		_speech.cancel_count_in()
	_tick(now)


func set_transport(master_beat: float, rate: float, playing: bool) -> void:
	if _disposed or _menu_active:
		return
	_set_transport(master_beat, rate, playing, _now())


func _set_transport(master_beat: float, rate: float, playing: bool, now: float) -> void:
	var beat := maxf(0.0, master_beat) if _finite(master_beat) else 0.0
	# Every take (and every review) restarts at beat 0 with fresh selves.
	if beat + 0.5 < _t_beat or (beat < 1e-6 and _t_beat > 1e-6):
		_seq.restart()
		if _loops != null:
			_loops.restart()
	_t_beat = beat
	_t_rate = maxf(0.0, rate) if _finite(rate) else 0.0
	_t_playing = playing
	_t_at = now
	_tick(now)


func set_tracks(tracks: Array[TrackAudioState]) -> void:
	if _disposed:
		return
	var copy: Array[TrackAudioState] = []
	for i: int in OD.TAPE_COUNT:
		var t: TrackAudioState = tracks[i] if i < tracks.size() and tracks[i] != null else AudioSequencer.silent_track()
		copy.append(t.copy())
	if _menu_active:
		# The bed owns the layers; remember the level's tracks for when it ends.
		_level_tracks = copy
		return
	_apply_tracks(copy, _now())


func _apply_tracks(copy: Array[TrackAudioState], now: float) -> void:
	_tracks = copy
	if _seq.set_tracks(_tracks, _current_beat(now)):
		_apply_cancel(_sched.invalidate(now, _commit_window()), now)
		_tick(now)


func on_events(events: Array[SimEvent]) -> void:
	if _disposed or events.is_empty() or not _loaded or _menu_active:
		return
	var now := _now()
	if _loops != null:
		_loops.on_events(events)
	var clock := AudioSfx.Clock.make(now, _current_beat(now), _t_rate, _is_running(now), _director.bpm)
	var cues := _planner.plan(events, clock, _director)
	if _voices != null:
		for c: AudioSfx.Cue in cues:
			var trig: Array[AudioTrigger] = []
			AudioCues.cue(c, trig)
			_voices.schedule(trig, c.time)
	if _speech != null:
		for e: SimEvent in events:
			_effort_for(e, now)


## Moxie's efforts on her selves' actions (VOICE-CAST 6.5).
func _effort_for(e: SimEvent, now: float) -> void:
	if e == null or e.tape < 0:
		return
	match e.type:
		SimEventType.SWING:
			_speech.effort("attack_heavy" if e.detail == "heavy" else "attack_light", e.tape, now)
		SimEventType.DODGE:
			_speech.effort("dodge", e.tape, now)
		SimEventType.SELF_DEATH:
			_speech.effort("death", e.tape, now)


func count_in(n: int) -> void:
	if _disposed or not AudioCues.COUNT_DEGREES.has(n) or _voices == null:
		return
	var now := _now()
	var bpm := _level.bpm if _level != null else _director.bpm
	var spoken := _speech != null and _speech.count_in(n, bpm, _count_called(), now)
	var pitch := _score.count_pitch(n, _director) if _score != null else -1
	if pitch < 0:
		pitch = _director.scale_midi(AudioCues.COUNT_DEGREES[n], 5)
	var trig: Array[AudioTrigger] = []
	AudioCues.count_in(n, pitch, trig)
	if spoken:
		# Moxie says the number; the synthesised word stays as the fallback only.
		var keep: Array[AudioTrigger] = []
		for t: AudioTrigger in trig:
			if t.family != AudioCues.COUNT_WORDS[n]:
				keep.append(t)
		trig = keep
	_voices.schedule(trig, now)


## `called` count-in (VOICE-CAST 6.4): the boss floor, the finale, and the last tape of a level.
func _count_called() -> bool:
	if _level == null:
		return false
	if _level.id.begins_with("11") or _level.id.begins_with("12"):
		return true
	var present := 0
	for t: TrackAudioState in _tracks:
		if t.present:
			present += 1
	return _level.max_tapes > 1 and present >= _level.max_tapes


func cancel_count_in() -> void:
	if _speech != null:
		_speech.cancel_count_in()


func ui(kind: StringName) -> void:
	if _disposed or _voices == null:
		return
	var trig: Array[AudioTrigger] = []
	var d := _director
	var score := AudioScore.menu() if _menu_active else _score
	var pitches: Array[int] = []
	if score != null:
		pitches = score.ui_pitches(kind, d)
	AudioCues.ui_tones(kind, pitches, func(degree: int) -> int: return d.scale_midi(degree, 5), trig)
	_voices.schedule(trig, _now())


func set_mode(mode: StringName) -> void:
	_mode = mode
	_mixer.set_mode(mode)
	if _disposed:
		return
	if mode == AudioBase.MODE_MENU:
		_begin_menu_bed(_now())
	else:
		_end_menu_bed(_now(), true)


func set_volumes(master: float, music: float, sfx: float) -> void:
	_volumes = Vector3(_unit_volume(master), _unit_volume(music), _unit_volume(sfx))
	_mixer.set_volumes(_volumes.x, _volumes.y, _volumes.z)


func set_voice_options(voices: StringName, barks: bool, voice_volume: float) -> void:
	if _speech != null:
		match voices:
			AudioBase.VOICES_OFF:
				_speech.mode = AudioVoiceLines.MODE_OFF
			AudioBase.VOICES_COUNT_ONLY:
				_speech.mode = AudioVoiceLines.MODE_COUNT_ONLY
			_:
				_speech.mode = AudioVoiceLines.MODE_ON
		_speech.barks_enabled = barks
		if _speech.mode != AudioVoiceLines.MODE_ON:
			_speech.stop_line(_now())
	_mixer.set_voice_volume(0.0 if voices == AudioBase.VOICES_OFF else _unit_volume(voice_volume))


func play_line(key: String, who: String = "", radio: bool = false) -> float:
	if _disposed or _speech == null:
		return 0.0
	return _speech.play_line(key, who, radio, _now())


func line_duration(key: String, who: String = "", radio: bool = false) -> float:
	return _speech.line_duration(key, who, radio) if _speech != null else 0.0


func stop_line() -> void:
	if _speech != null:
		_speech.stop_line(_now())


func play_bark(key: String, event_key: String, who: String = "moxie") -> float:
	if _disposed or _speech == null:
		return 0.0
	return _speech.play_bark(key, event_key, who, false, _now())


func connect_dialogue(layer: Node) -> void:
	if layer == null:
		return
	var player: Variant = layer.get("player")
	if player is Node:
		var p: Node = player
		if p.has_signal("started") and not p.is_connected("started", _on_dlg_started):
			p.connect("started", _on_dlg_started)
		if p.has_signal("line_shown") and not p.is_connected("line_shown", _on_dlg_line):
			p.connect("line_shown", _on_dlg_line)
		if p.has_signal("finished") and not p.is_connected("finished", _on_dlg_finished):
			p.connect("finished", _on_dlg_finished)
	if layer.has_signal("bark_shown") and not layer.is_connected("bark_shown", _on_dlg_bark):
		layer.connect("bark_shown", _on_dlg_bark)


func _on_dlg_started(kind: StringName, key: String) -> void:
	_dlg_kind = kind
	_dlg_key = key


## Story location of the index-th line of the current sequence (docs/VOICE-CAST.md 6, dialogue 1).
func _dlg_location(kind: StringName, index: int) -> String:
	match String(kind):
		"intro", "outro":
			return "levels.%s.%s[%d]" % [_dlg_key, kind, index]
		"first":
			return "once.%s[%d]" % [_dlg_key, index]
		"ending":
			return "ending[%d]" % index
		"stinger":
			return "stinger[%d]" % index
	return ""


func _on_dlg_line(kind: StringName, index: int, line: Object) -> void:
	if line == null or _speech == null:
		return
	var who := str(line.get("who"))
	var text := str(line.get("line"))
	# Exact text first (it cannot point at the wrong line), then the location.
	var key := text if _speech.has_line(text, who) else _dlg_location(kind, index)
	# Tolliver is met in person; only the post-credits stinger reaches Moxie over comms.
	play_line(key, who, String(kind) == "stinger")


func _on_dlg_finished(_kind: StringName, _key: String, _skipped: bool) -> void:
	stop_line()


func _on_dlg_bark(key: String, line: Object) -> void:
	if line == null:
		return
	play_bark(str(line.get("line")), key, str(line.get("who")))


func pulse() -> MusicPulse:
	var now := _now()
	var beat := _current_beat(now)
	if not _loaded and not _menu_active:
		return AudioPulseMeter.silent_pulse(beat, 0)
	return _meter.sample(now, beat, _director.chord_index(beat))


func dispose() -> void:
	if _disposed:
		return
	var now := _now()
	_stop_all_music(now)
	if _voices != null:
		_voices.stop_all(now)
	if _speech != null:
		_speech.stop_all()
	if _loops != null:
		_loops.stop_all()
	_disposed = true
	set_process(false)


# ───────────────────────────── tools / tests ─────────────────────────────

## The director in use (fallback before load_level; the bed's in the menu).
func director() -> AudioDirector:
	return _director


func voices() -> AudioVoiceEngine:
	return _voices


func speech() -> AudioVoiceLines:
	return _speech


func trap_loops() -> AudioTrapLoops:
	return _loops


func mixer() -> AudioMixer:
	return _mixer


func sample_bank() -> AudioSampleBank:
	return _bank


func score() -> AudioScore:
	return _score


func menu_bed_active() -> bool:
	return _menu_active


func planner() -> AudioSfx.Planner:
	return _planner


## Advance one frame on the facade's clock (tools / tests that drive time themselves).
func step(dt: float) -> void:
	_frame(dt)


# ───────────────────────────── menu bed ─────────────────────────────

func _begin_menu_bed(now: float) -> void:
	if _menu_active:
		return
	var bed := AudioScore.menu()
	if bed == null or bed.music == null:
		return
	_stop_all_music(now)
	_level_director = _director if _loaded else null
	_level_tracks = _tracks
	_menu_active = true
	_menu_started_at = now
	_director = AudioDirector.new(bed.level_def())
	_seq = AudioSequencer.new(_director)
	_sched = _make_scheduler()
	_meter.clear()
	var tracks: Array[TrackAudioState] = []
	for i: int in OD.TAPE_COUNT:
		tracks.append(bed.bed[i].copy() if i < bed.bed.size() else AudioSequencer.silent_track())
	_tracks = tracks
	_seq.set_tracks(_tracks, 0.0)
	_mixer.set_roles(_roles())
	_colour_key = ""
	if _loops != null:
		_loops.stop_all()
	_t_beat = 0.0
	_t_rate = 1.0
	_t_playing = true
	_t_at = now
	_tick(now)


## Leaves the bed. `restore` puts the level's director back (a mode change inside a level); a
## load_level() builds its own.
func _end_menu_bed(now: float, restore: bool) -> void:
	if not _menu_active:
		return
	_menu_active = false
	_stop_all_music(now)
	_meter.clear()
	_t_beat = 0.0
	_t_rate = 0.0
	_t_playing = false
	_t_at = now
	var silent: Array[TrackAudioState] = []
	for i: int in OD.TAPE_COUNT:
		silent.append(AudioSequencer.silent_track())
	_tracks = _level_tracks if _level_tracks.size() == OD.TAPE_COUNT else silent
	if restore:
		_director = _level_director if _level_director != null else AudioDirector.new(_fallback_level())
		_seq = AudioSequencer.new(_director)
		_sched = _make_scheduler()
		_seq.set_tracks(_tracks, 0.0)
		_mixer.set_roles(_roles())
		_colour_key = ""
	_level_director = null


## The bed runs on its own clock: one master beat per beat of its tempo, forever.
func _advance_menu_clock(now: float) -> void:
	if not _menu_active:
		return
	_t_beat = maxf(0.0, now - _menu_started_at) * (_director.bpm / 60.0)
	_t_rate = 1.0
	_t_playing = true
	_t_at = now


# ───────────────────────────── internals ─────────────────────────────

func _process(delta: float) -> void:
	_frame(delta)


func _frame(delta: float) -> void:
	if _disposed:
		return
	var now := _now()
	_advance_menu_clock(now)
	_tick(now)
	_update_duck(now)
	_mixer.process(delta)
	if _voices != null:
		_voices.process(now)
	if _speech != null:
		_speech.process(now)
	if _loops != null:
		_loops.update(_is_running(now) and not _menu_active, delta)


func _update_duck(now: float) -> void:
	var kind := _speech.speaking(now) if _speech != null else AudioVoiceLines.KIND_NONE
	if kind != AudioVoiceLines.KIND_NONE:
		# The hold restarts while speech continues; after it ends the duck lasts DUCK_HOLD more.
		_duck_kind = kind
		_duck_until = now + DUCK_HOLD
	elif now >= _duck_until:
		_duck_kind = AudioVoiceLines.KIND_NONE
	match _duck_kind:
		AudioVoiceLines.KIND_LINE:
			_mixer.set_duck(AudioMixer.DUCK_LINE_DB)
		AudioVoiceLines.KIND_BARK:
			_mixer.set_duck(AudioMixer.DUCK_BARK_DB)
		_:
			_mixer.set_duck(0.0)


func _now() -> float:
	if time_source.is_valid():
		return time_source.call()
	return Time.get_ticks_usec() / 1000000.0


static func _finite(x: float) -> bool:
	return not (is_nan(x) or is_inf(x))


## Volumes arrive as 0..1; a 0..100 slider value is accepted too.
static func _unit_volume(v: float) -> float:
	if not _finite(v):
		return 0.0
	var x := v / 100.0 if v > 1.0 else v
	return clampf(x, 0.0, 1.0)


## Seconds of planned music already committed to the output: the next mix plus the device latency
## and a small margin. A layer-state change keeps those notes rather than replacing them late.
func _commit_window() -> float:
	if not is_inside_tree():
		return 0.0
	return AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency() + 0.005


func _make_scheduler() -> AudioScheduler:
	var seq := _seq
	return AudioScheduler.new(func(a: float, b: float) -> Array[AudioLayerNote]: return seq.collect(a, b), _director.bpm, _lookahead)


func _roles() -> Array[StringName]:
	var out: Array[StringName] = []
	for i: int in OD.TAPE_COUNT:
		out.append(_director.role_of(i))
	return out


func _is_running(now: float) -> bool:
	return _t_playing and _t_rate > 0.0 and now - _t_at <= STALE_TRANSPORT


func _current_beat(now: float) -> float:
	if not _t_playing or not (_t_rate > 0.0):
		return _t_beat
	var dt := minf(maxf(0.0, now - _t_at), STALE_TRANSPORT)
	return _t_beat + dt * _t_rate * (_director.bpm / 60.0)


func _tick(now: float) -> void:
	if _disposed:
		return
	var running := _is_running(now)
	var beat := _current_beat(now)
	_apply_update(_sched.update(now, beat, _t_rate, running), now)
	_update_colours(beat)


func _apply_update(u: AudioScheduler.Update, now: float) -> void:
	_apply_cancel(u.cancel, now)
	if u.choke:
		_meter.choke(now)
		if _voices != null:
			_voices.choke_music(now)
	for p: AudioPlannedNote in u.start:
		_meter.add(p)
		if on_note_planned.is_valid():
			on_note_planned.call(p)
		if _voices == null:
			continue
		var trig: Array[AudioTrigger] = []
		AudioCues.layer_note(_director.role_of(p.note.track), p.note, p.dur, trig)
		_voices.schedule(trig, p.time, p.id)


func _apply_cancel(cancelled: Array[AudioPlannedNote], now: float) -> void:
	if cancelled.is_empty():
		return
	var ids: Array[int] = []
	for p: AudioPlannedNote in cancelled:
		ids.append(p.id)
		if _voices != null:
			_voices.cancel(p.id, now)
		if on_note_cancelled.is_valid():
			on_note_cancelled.call(p)
	_meter.cancel(ids)


func _stop_all_music(now: float) -> void:
	_apply_cancel(_sched.reset(), now)
	_meter.choke(now)
	if _voices != null:
		_voices.choke_music(now)


## Bus colour follows the same variant the notes were composed with (MUSIC-08).
func _update_colours(beat: float) -> void:
	var bar := maxi(0, int(floorf(beat / OD.BEATS_PER_BAR)))
	var cols: Array[AudioMixer.Colour] = []
	var key := ""
	for i: int in OD.TAPE_COUNT:
		var v := _seq.variant_at(i, bar)
		var c := AudioMixer.Colour.make(true, v.dead, v.drift, v.speed) if v != null else AudioMixer.Colour.make(false, false, 0.0, 1.0)
		cols.append(c)
		key += c.key() + ";"
	if key == _colour_key:
		return
	_colour_key = key
	for i: int in OD.TAPE_COUNT:
		_mixer.set_layer_colour(i, cols[i])
