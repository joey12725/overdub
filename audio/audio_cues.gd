class_name AudioCues
extends RefCounted
## What every sound is made of (the sample-based counterpart of prototype src/audio/voices.ts):
## the four cassette instruments, the drum kit, every gameplay cue, count-in ticks and UI blips,
## each expressed as AudioTrigger lists over the generated sample families. Pure; no nodes.
##
## Levels are linear amplitudes relative to a family's loudest sample (every family peaks at about
## -1 dBFS, art/audio/make_samples.py). The prototype's oscillator peaks are kept where the voice
## maps one-to-one, so the cue balance matches the reference build.

## Instrument levels at velocity 127 (one voice).
const LEVEL_BASS := 0.62
const LEVEL_LEAD := 0.46
const LEVEL_KEYS := 0.3
const LEVEL_PAD := 0.24
const DRUM_LEVEL: Dictionary = {
	&"kick": 0.95, &"snare": 0.62, &"clap": 0.58, &"hatClosed": 0.34, &"hatOpen": 0.28, &"tom": 0.55, &"rim": 0.42, &"perc": 0.45,
}
const DRUM_FAMILY: Dictionary = {
	&"kick": &"kick", &"snare": &"snare", &"clap": &"clap", &"hatClosed": &"hat_closed", &"hatOpen": &"hat_open",
	&"tom": &"tom", &"rim": &"rim", &"perc": &"perc",
}
## Reverb send per role (mixer.ts ROLE_SEND); bass stays dry so the low end stays tight.
const ROLE_SEND: Dictionary = {&"bass": 0.0, &"drums": 0.1, &"melody": 0.26, &"chord": 0.3}
## Chord notes held at least this long (wall seconds) use the pad; shorter ones the keys.
const PAD_MIN_SECONDS := 0.9

## Count-in: rising scale degrees 1-3-5-8 lead into the downbeat; "eight" is accented.
const COUNT_DEGREES: Dictionary = {5: 0, 6: 2, 7: 4, 8: 7}
const COUNT_WORDS: Dictionary = {5: &"count_five", 6: &"count_six", 7: &"count_seven", 8: &"count_eight"}
## Measured in tools/audio_preview.gd: the count-in sits about 3 dB above the music that follows.
const COUNT_VOICE_GAIN := 0.5


static func _vel(v: int) -> float:
	return maxf(0.05, float(v) / 127.0)


## A pitched blip from the generated blip families. `decay` is the prototype's decay time (the
## level reaches silence at `decay`): short decays use the short family, longer ones the long family
## with a release fade at the right moment.
static func blip(type: String, pitch: float, offset: float, peak: float, decay: float) -> AudioTrigger:
	if decay <= 0.16:
		return AudioTrigger.make(StringName("blip_%s_short" % type), pitch, peak, offset)
	if decay >= 0.85:
		return AudioTrigger.make(StringName("blip_%s_long" % type), pitch, peak, offset)
	return AudioTrigger.make(StringName("blip_%s_long" % type), pitch, peak, offset, decay * 0.45, decay * 0.55)


# ───────────────────────────── cassette instruments ─────────────────────────────

## Triggers for one layer note. `dur` is its wall-clock length in seconds.
static func layer_note(role: StringName, note: AudioLayerNote, dur: float, out: Array[AudioTrigger]) -> void:
	var t: AudioTrigger
	if note.drum != &"":
		t = AudioTrigger.make(DRUM_FAMILY.get(note.drum, &"perc"), -1.0, DRUM_LEVEL.get(note.drum, 0.4) * _vel(note.velocity))
	elif role == MusicRole.BASS:
		t = AudioTrigger.make(&"bass", note.pitch, LEVEL_BASS * _vel(note.velocity), 0.0, dur, 0.09)
	elif role == MusicRole.CHORD:
		if dur > PAD_MIN_SECONDS:
			t = AudioTrigger.make(&"pad", note.pitch, LEVEL_PAD * _vel(note.velocity), 0.0, dur, 0.7)
		else:
			t = AudioTrigger.make(&"keys", note.pitch, LEVEL_KEYS * _vel(note.velocity), 0.0, dur, 0.4)
	else:
		t = AudioTrigger.make(&"lead", note.pitch, LEVEL_LEAD * _vel(note.velocity), 0.0, dur, 0.16)
	t.dest = AudioTrigger.DEST_LAYER
	t.channel = note.track
	t.send = ROLE_SEND.get(role, 0.0)
	out.append(t)


# ───────────────────────────── gameplay cues ─────────────────────────────

static func _impact_family(power: float) -> StringName:
	if power >= 8.0:
		return &"impact_heavy"
	if power >= 3.0:
		return &"impact_medium"
	return &"impact_light"


## Triggers for one planned gameplay cue (offsets relative to cue.time).
static func cue(c: AudioSfx.Cue, out: Array[AudioTrigger]) -> void:
	var g := clampf(c.gain, 0.01, 1.0)
	var p := c.pitches
	var p0: float = p[0] if p.size() > 0 else 60.0
	var p1: float = p[1] if p.size() > 1 else p0
	var s16 := clampf(c.sixteenth, 0.03, 0.12)
	var start := out.size()
	match c.kind:
		AudioSfx.TRANSIENT:
			out.append(AudioTrigger.make(&"transient", -1.0, 0.5 * g))
		AudioSfx.STEP:
			out.append(AudioTrigger.make(&"step", -1.0, 0.5 * g))
			out.append(blip("sine", p0 + 12.0, 0.0, 0.12 * g, 0.03))
		AudioSfx.SWING_LIGHT:
			out.append(AudioTrigger.make(&"whoosh_light", -1.0, 0.5 * g))
			out.append(blip("tri", p0, 0.01, 0.22 * g, 0.07))
		AudioSfx.SWING_HEAVY:
			out.append(AudioTrigger.make(&"whoosh_heavy", -1.0, 0.55 * g))
			out.append(blip("tri", p0, 0.01, 0.22 * g, 0.14))
		AudioSfx.HIT:
			out.append(blip("tri", p0, 0.0, 0.55 * g, 0.16))
			out.append(blip("square", p1, 0.0, 0.12 * g, 0.08))
			out.append(AudioTrigger.make(_impact_family(c.power), -1.0, 0.6 * g))
		AudioSfx.KILL:
			for i: int in p.size():
				out.append(blip("tri", p[i], i * s16 * 0.5, 0.36 * g, 0.18))
			out.append(AudioTrigger.make(&"kill_pop", -1.0, 0.45 * g))
		AudioSfx.BREAK:
			out.append(AudioTrigger.make(&"break_crumble", -1.0, 0.9 * g))
			out.append(AudioTrigger.make(&"break_tone", p0, 0.6 * g))
			out.append(blip("tri", p1, 0.0, 0.25 * g, 0.2))
		AudioSfx.CLANG:
			out.append(AudioTrigger.make(&"clang", p0, 0.6 * g))
		AudioSfx.DODGE:
			out.append(AudioTrigger.make(&"dodge_swish", -1.0, 0.5 * g))
			out.append(AudioTrigger.make(&"dodge_tone", p0, 0.14 * g, 0.02))
		AudioSfx.FIRE:
			match c.detail:
				"missile":
					out.append(AudioTrigger.make(&"shot_missile", p0, 0.32 * g))
				"pierce":
					out.append(AudioTrigger.make(&"shot_pierce", p1, 0.2 * g))
				"phase":
					out.append(AudioTrigger.make(&"shot_phase", p0, 0.3 * g))
				"arc":
					out.append(AudioTrigger.make(&"shot_arc", p0, 0.32 * g))
				"burst":
					for i: int in 3:
						out.append(blip("square", p0 + 12.0, i * s16 * 0.35, 0.14 * g, 0.04))
				_:
					out.append(AudioTrigger.make(&"shot_bolt", p0, 0.3 * g))
		AudioSfx.PROJECTILE_HIT:
			out.append(blip("tri", p0, 0.0, 0.4 * g, 0.1))
			out.append(AudioTrigger.make(&"impact_small", -1.0, 0.4 * g))
		AudioSfx.INTERACT:
			out.append(AudioTrigger.make(&"switch_click", -1.0, 0.35 * g))
			out.append(blip("square", p0, 0.0, 0.14 * g, 0.08))
			out.append(blip("tri", p1, s16 * 0.5, 0.3 * g, 0.14))
		AudioSfx.INTERACT_FAIL:
			out.append(AudioTrigger.make(&"fail_thud", p0, 0.35 * g))
		AudioSfx.DOOR:
			var opening := c.detail != "off" and c.detail != "close" and c.detail != "closed"
			out.append(AudioTrigger.make(&"door_open" if opening else &"door_close", -1.0, 0.5 * g))
			out.append(blip("sine", p0, 0.0, 0.4 * g, 0.4))
			out.append(blip("sine", p1, 0.18, 0.3 * g, 0.4))
		AudioSfx.PLATE:
			out.append(AudioTrigger.make(&"plate_thunk", p0, 0.5 * g))
		AudioSfx.LASER:
			out.append(AudioTrigger.make(&"laser_off" if c.detail == "off" else &"laser_on", p0, 0.35 * g))
		AudioSfx.CORE:
			for i: int in p.size():
				out.append(blip("sine", p[i], i * 0.012, 0.22 * g, 1.1))
			out.append(AudioTrigger.make(&"core_swell", -1.0, 0.35 * g))
		AudioSfx.SELF_DEATH:
			for i: int in p.size():
				out.append(AudioTrigger.make(&"tape_stop", p[i], 0.32 * g, i * s16))
			out.append(AudioTrigger.make(&"death_sweep", -1.0, 0.4 * g))
		AudioSfx.DESYNC:
			out.append(AudioTrigger.make(&"desync_glitch", p0, 0.3 * g))
		AudioSfx.RESYNC:
			out.append(blip("tri", p0, 0.0, 0.3 * g, 0.1))
			out.append(blip("sine", p1, s16 * 0.5, 0.35 * g, 0.22))
			out.append(AudioTrigger.make(&"resync_lock", -1.0, 0.25 * g))
		AudioSfx.TAPE_WRAP:
			out.append(AudioTrigger.make(&"tape_wrap", -1.0, 0.35 * g))
			out.append(blip("sine", p0, 0.1, 0.15 * g, 0.05))
		AudioSfx.TAPE_TURN:
			out.append(AudioTrigger.make(&"tape_turn", p0, 0.26 * g))
		AudioSfx.TAPE_END:
			out.append(AudioTrigger.make(&"tape_end", p0, 0.32 * g))
		AudioSfx.ENEMY_TELEGRAPH:
			out.append(AudioTrigger.make(&"enemy_telegraph", p0, 0.22 * g))
			out.append(AudioTrigger.make(&"enemy_telegraph", p1, 0.11 * g))
		AudioSfx.ENEMY_ATTACK:
			out.append(AudioTrigger.make(&"enemy_attack", p0, 0.6 * g))
		AudioSfx.ENEMY_SHOT:
			out.append(AudioTrigger.make(&"enemy_shock" if c.detail == "shock" else &"enemy_shot", p0, 0.2 * g))
		AudioSfx.ENEMY_STAGGER:
			out.append(AudioTrigger.make(&"enemy_stagger", p0, 0.26 * g))
		AudioSfx.BOSS_PHASE:
			for i: int in p.size():
				out.append(AudioTrigger.make(&"boss_drone", p[i], 0.2 * g))
			out.append(AudioTrigger.make(&"boss_riser", -1.0, 0.45 * g))
		AudioSfx.BOSS_RECALL:
			for i: int in p.size():
				out.append(AudioTrigger.make(&"reverse_swell", p[i], 0.22 * g, i * s16))
		AudioSfx.OBJECTIVE:
			for i: int in p.size():
				out.append(blip("tri", p[i], i * s16 * 0.5, 0.3 * g, 0.5))
				out.append(blip("sine", p[i] + 12.0, i * s16 * 0.5, 0.08 * g, 0.4))
			out.append(AudioTrigger.make(&"objective_shimmer", -1.0, 0.25 * g))
		_:
			_trap_cue(c, g, p0, p1, s16, out)
	for i: int in range(start, out.size()):
		out[i].dest = AudioTrigger.DEST_SFX
		out[i].channel = c.tape


## Trap cues (docs/TRAPS.md "Events for audio and fx"). Families from art/audio/make_samples.py
## ("traps" section). The telegraph is a tick on the beat before the activation and a tock half a
## beat later, so the stroke lands where the count says it will.
static func _trap_cue(c: AudioSfx.Cue, g: float, p0: float, p1: float, s16: float, out: Array[AudioTrigger]) -> void:
	match c.kind:
		AudioSfx.TRAP_WARN:
			out.append(AudioTrigger.make(&"trap_tick", p0, 0.75 * g))
			# Half a master beat later, at the current rate (two sixteenths; not clamped like s16).
			out.append(AudioTrigger.make(&"trap_tick", p1, 0.6 * g, 2.0 * maxf(0.0, c.sixteenth)))
		AudioSfx.SPIKES_UP:
			out.append(AudioTrigger.make(&"spike_up", -1.0, 0.75 * g))
			out.append(blip("tri", p0, 0.0, 0.3 * g, 0.12))
		AudioSfx.SPIKES_DOWN:
			out.append(AudioTrigger.make(&"spike_down", -1.0, 0.55 * g))
		AudioSfx.CRUSHER_SLAM:
			out.append(AudioTrigger.make(&"crusher_slam", -1.0, 0.9 * g))
			out.append(AudioTrigger.make(&"break_tone", p0, 0.35 * g))
			out.append(blip("tri", p1, 0.0, 0.2 * g, 0.2))
		AudioSfx.CRUSHER_RETRACT:
			out.append(AudioTrigger.make(&"crusher_retract", -1.0, 0.55 * g))
			out.append(blip("sine", p0, 0.0, 0.12 * g, 0.3))
		AudioSfx.CRUSHER_HOLD:
			out.append(AudioTrigger.make(&"switch_click", -1.0, 0.45 * g))
		AudioSfx.CRUSHER_OPEN:
			out.append(AudioTrigger.make(&"plate_thunk", p0, 0.45 * g))
		AudioSfx.CONVEYOR:
			out.append(AudioTrigger.make(&"conveyor_clunk", -1.0, 0.65 * g))
			out.append(blip("sine", p0, 0.0, 0.15 * g, 0.2))
		AudioSfx.FLAME_ON:
			out.append(AudioTrigger.make(&"flame_ignite", -1.0, 0.75 * g))
			out.append(blip("tri", p0, 0.0, 0.15 * g, 0.2))
		AudioSfx.FLAME_OFF:
			out.append(AudioTrigger.make(&"flame_out", -1.0, 0.6 * g))
		AudioSfx.DART_FIRE:
			out.append(AudioTrigger.make(&"dart_fire", -1.0, 0.65 * g))
			out.append(blip("square", p0, 0.0, 0.12 * g, 0.05))
		AudioSfx.DART_TOGGLE:
			out.append(AudioTrigger.make(&"switch_click", -1.0, 0.5 * g))
		AudioSfx.BUMPER:
			out.append(AudioTrigger.make(&"bumper_boing", p0, 0.65 * g))
			out.append(blip("tri", p1, s16 * 0.5, 0.25 * g, 0.12))
		AudioSfx.SENSOR:
			out.append(AudioTrigger.make(&"sensor_beep", p0, 0.6 * g))
		AudioSfx.RELAY_ARMED:
			out.append(AudioTrigger.make(&"trap_tick", p0, 0.4 * g))
		AudioSfx.RELAY:
			out.append(AudioTrigger.make(&"switch_click", -1.0, 0.4 * g))
			out.append(blip("sine", p0, 0.0, 0.15 * g, 0.08))
		AudioSfx.MAGNET:
			var off := c.detail.ends_with(":off")
			out.append(AudioTrigger.make(&"laser_off" if off else &"laser_on", p0, 0.25 * g))


# ───────────────────────────── count-in and UI ─────────────────────────────

## The count-in tick for n = 5..8: a clave-like pitched tick plus the spoken number.
static func count_in(n: int, pitch: int, out: Array[AudioTrigger]) -> void:
	if not COUNT_DEGREES.has(n):
		return
	var accent := n == 8
	var g := 0.4 if accent else 0.29
	var start := out.size()
	out.append(blip("sine", pitch, 0.0, g, 0.22 if accent else 0.14))
	out.append(blip("tri", pitch + 12, 0.0, g * 0.35, 0.05))
	out.append(AudioTrigger.make(&"tick_click", -1.0, g * 0.5))
	out.append(AudioTrigger.make(COUNT_WORDS[n], -1.0, COUNT_VOICE_GAIN * (1.1 if accent else 1.0)))
	for i: int in range(start, out.size()):
		out[i].dest = AudioTrigger.DEST_UI


## UI blips; `scale` maps a scale degree to a MIDI note in the current key so menus match the level.
static func ui(kind: StringName, scale: Callable, out: Array[AudioTrigger]) -> void:
	var start := out.size()
	match kind:
		AudioBase.UI_MOVE:
			_seq(out, scale, [4], 0.0, "sine", 0.12, 0.04)
		AudioBase.UI_SELECT:
			_seq(out, scale, [2, 4], 0.05, "tri", 0.2, 0.09)
		AudioBase.UI_BACK:
			_seq(out, scale, [4, 2], 0.05, "tri", 0.18, 0.09)
		AudioBase.UI_COMMIT:
			out.append(AudioTrigger.make(&"ui_click", -1.0, 0.25))
			_seq(out, scale, [0, 2, 4, 7], 0.06, "tri", 0.24, 0.2)
		AudioBase.UI_RETRY:
			out.append(AudioTrigger.make(&"ui_sweep", -1.0, 0.3))
			_seq(out, scale, [4, 2], 0.08, "sine", 0.16, 0.1)
		AudioBase.UI_RESET:
			out.append(AudioTrigger.make(&"ui_sweep_long", -1.0, 0.35))
			_seq(out, scale, [7, 4, 2, 0], 0.07, "sine", 0.14, 0.12)
		AudioBase.UI_WIN:
			_seq(out, scale, [0, 2, 4, 7, 9, 11, 14], 0.07, "tri", 0.26, 0.4)
		AudioBase.UI_FAIL:
			_seq(out, scale, [4, 3, 1, 0], 0.12, "tri", 0.22, 0.3)
		AudioBase.UI_LOOT:
			_seq(out, scale, [7, 9, 11, 14], 0.045, "sine", 0.22, 0.3)
			out.append(blip("tri", scale.call(14), 0.2, 0.1, 0.5))
		AudioBase.UI_SPEED:
			out.append(AudioTrigger.make(&"ui_glide", scale.call(0), 0.16))
	for i: int in range(start, out.size()):
		out[i].dest = AudioTrigger.DEST_UI


## Timbre of each UI kind when its pitches come from the piece (`sfx.ui`): [step s, blip type, peak,
## decay, extra family or "", extra gain]. Same voices as ui(), the composer's notes.
const UI_SHAPE: Dictionary = {
	&"move": [0.0, "sine", 0.12, 0.04, &"", 0.0],
	&"select": [0.05, "tri", 0.2, 0.09, &"", 0.0],
	&"back": [0.05, "tri", 0.18, 0.09, &"", 0.0],
	&"commit": [0.06, "tri", 0.24, 0.2, &"ui_click", 0.25],
	&"retry": [0.08, "sine", 0.16, 0.1, &"ui_sweep", 0.3],
	&"reset": [0.07, "sine", 0.14, 0.12, &"ui_sweep_long", 0.35],
	&"win": [0.07, "tri", 0.26, 0.4, &"", 0.0],
	&"fail": [0.12, "tri", 0.22, 0.3, &"", 0.0],
	&"loot": [0.045, "sine", 0.22, 0.3, &"", 0.0],
	&"speed": [0.06, "tri", 0.16, 0.12, &"ui_glide", 0.16],
}


## UI blips on the composer's pitches (AudioScore.ui_pitches). Falls back to ui() when `pitches` is
## empty or the kind has no shape.
static func ui_tones(kind: StringName, pitches: Array[int], scale: Callable, out: Array[AudioTrigger]) -> void:
	if pitches.is_empty() or not UI_SHAPE.has(kind):
		ui(kind, scale, out)
		return
	var sh: Array = UI_SHAPE[kind]
	var start := out.size()
	var extra: StringName = sh[4]
	if extra != &"":
		# ui_glide is pitched: it glides up from the first note.
		out.append(AudioTrigger.make(extra, float(pitches[0]) if extra == &"ui_glide" else -1.0, float(sh[5])))
	if extra != &"ui_glide":
		for i: int in pitches.size():
			out.append(blip(sh[1], float(pitches[i]), i * float(sh[0]), float(sh[2]), float(sh[3])))
	for i: int in range(start, out.size()):
		out[i].dest = AudioTrigger.DEST_UI


static func _seq(out: Array[AudioTrigger], scale: Callable, degrees: Array, step: float, type: String, peak: float, decay: float) -> void:
	for i: int in degrees.size():
		out.append(blip(type, float(scale.call(degrees[i])), i * step, peak, decay))
