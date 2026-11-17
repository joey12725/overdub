class_name AudioBusSetup
extends RefCounted
## The game's audio bus layout (res://default_bus_layout.tres is generated from build(); the audio
## node calls ensure() at startup so the layout is right even if the .tres is missing or stale).
##
##   Layer1..4 ───> Music (or Drums for the drum-role layer; set per level)   one bus per cassette:
##                                                                           state colour lives here
##   Send1..4 ────> Reverb ─> Music                                          reverb send per layer
##   Drums ─> Music ─> Master                                                 kit glue
##   Index order: Master, Music, Reverb, Drums, Layer1..4, Send1..4, Sfx, SfxA..D, Ui, Voice.
##   SfxA..D ─> Sfx ─> Master                                                 per-tape pan, room
##   Ui ─> Master                                                             count-in, menu blips
##   Voice ─> Master                                                          dialogue lines, barks
##   Master: tilt EQ -> tape saturation (soft clip) -> hard limiter
##
## Godot buses have one output each, so the reverb "send" is a second, quieter voice on the
## layer's Send bus (AudioVoiceEngine); the Send bus mirrors the layer's colour filters so a dead
## layer's reverb is hollow too.

const MASTER := &"Master"
const MUSIC := &"Music"
const DRUMS := &"Drums"
const REVERB := &"Reverb"
const SFX := &"Sfx"
const UI := &"Ui"
## Spoken dialogue and barks (docs/VOICE-CAST.md section 6). The music ducks under it.
const VOICE := &"Voice"
const LAYERS: Array[StringName] = [&"Layer1", &"Layer2", &"Layer3", &"Layer4"]
const SENDS: Array[StringName] = [&"Send1", &"Send2", &"Send3", &"Send4"]
const SFX_PAN: Array[StringName] = [&"SfxA", &"SfxB", &"SfxC", &"SfxD"]

# Effect slots.
const MASTER_EQ := 0
const MASTER_SAT := 1
const MASTER_LIMIT := 2
const MUSIC_TONE := 0
const MUSIC_GLUE := 1
const LAYER_HP := 0
const LAYER_LP := 1
const LAYER_EQ := 2
const LAYER_CHORUS := 3
const LAYER_PAN := 4
const SEND_HP := 0
const SEND_LP := 1
const REVERB_FX := 0
const REVERB_LP := 1
const SFX_GLUE := 0
const SFX_ROOM := 1
const SFX_PAN_FX := 0

## EQ6 bands: 32, 100, 320, 1000, 3200, 10000 Hz.
const EQ_PRESENCE_BAND := 3
const EQ_AIR_BAND := 5
const EQ_BRIGHT_BAND := 4

## Master tape-saturation drive (AudioEffectDistortion, MODE_ATAN).
const SAT_DRIVE := 0.3


## Make-up gain (dB) that gives Godot's ATAN distortion unity gain for small signals. Godot computes
## y = atan(x * m) / (atan(m) * (1 + 8 * drive)) with m = 10^(3 * drive^2) - 1 + 0.001
## (servers/audio/effects/audio_effect_distortion.cpp), so its small-signal gain is
## m / (atan(m) * (1 + 8 * drive)): about -9 dB at drive 0.3. A full-scale peak then comes out
## about 1.7 dB softer than it went in, which is the gentle tape squash wanted here.
static func saturation_makeup_db(drive: float) -> float:
	var m := pow(10.0, 3.0 * drive * drive) - 1.0 + 0.001
	var small_signal := m / (atan(m) * (1.0 + 8.0 * drive))
	return -linear_to_db(small_signal)


## Per-tape SFX pan (sfx.ts TAPE_PAN).
const SFX_PAN_VALUES: Array[float] = [-0.28, -0.09, 0.09, 0.28]


## Bus order: [name, send]. Godot mixes buses from the last index to the first and silently
## reroutes a send that targets the same or a later index to Master, so every bus must come after
## the bus it sends to (Reverb before the Send buses, Drums before the layers). is_valid_order()
## checks this.
static func _plan() -> Array:
	var p: Array = [[MASTER, &""], [MUSIC, MASTER], [REVERB, MUSIC], [DRUMS, MUSIC]]
	for i: int in LAYERS.size():
		p.append([LAYERS[i], MUSIC])
	for i: int in SENDS.size():
		p.append([SENDS[i], REVERB])
	p.append([SFX, MASTER])
	for i: int in SFX_PAN.size():
		p.append([SFX_PAN[i], SFX])
	p.append([UI, MASTER])
	p.append([VOICE, MASTER])
	return p


## True when every bus of the plan sends to a bus with a lower index (see _plan()). The layer buses
## are retargeted to Drums or Music per level, both of which precede them.
static func is_valid_order() -> bool:
	var plan := _plan()
	var index := {}
	for i: int in plan.size():
		index[plan[i][0]] = i
	for i: int in range(1, plan.size()):
		var target: StringName = plan[i][1]
		if not index.has(target) or int(index[target]) >= i:
			return false
	for l: StringName in LAYERS:
		if int(index[DRUMS]) >= int(index[l]) or int(index[MUSIC]) >= int(index[l]):
			return false
	return true


## The plan as [name, send] pairs (for tests and tools).
static func plan() -> Array:
	return _plan()


## True when the current AudioServer layout is this one (names, routing, effect slots).
static func is_current() -> bool:
	var plan := _plan()
	if AudioServer.bus_count != plan.size():
		return false
	for i: int in plan.size():
		if AudioServer.get_bus_name(i) != String(plan[i][0]):
			return false
		if i > 0 and not plan[i][0] in LAYERS and AudioServer.get_bus_send(i) != plan[i][1]:
			return false
	var l :=AudioServer.get_bus_index(LAYERS[0])
	return AudioServer.get_bus_effect_count(l) == 5 and AudioServer.get_bus_effect(l, LAYER_CHORUS) is AudioEffectChorus \
		and AudioServer.get_bus_effect_count(AudioServer.get_bus_index(MASTER)) == 3


## Builds the layout unless it is already current. Returns true when it had to build.
static func ensure() -> bool:
	if is_current():
		return false
	build()
	return true


static func build() -> void:
	var plan := _plan()
	# Remove every bus but Master, then reset Master.
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(AudioServer.bus_count - 1)
	while AudioServer.get_bus_effect_count(0) > 0:
		AudioServer.remove_bus_effect(0, 0)
	AudioServer.bus_count = plan.size()
	for i: int in plan.size():
		AudioServer.set_bus_name(i, String(plan[i][0]))
		AudioServer.set_bus_volume_db(i, 0.0)
		AudioServer.set_bus_mute(i, false)
		AudioServer.set_bus_solo(i, false)
		AudioServer.set_bus_bypass_effects(i, false)
	for i: int in plan.size():
		if i > 0:
			AudioServer.set_bus_send(i, String(plan[i][1]))

	var master := AudioServer.get_bus_index(MASTER)
	var eq := AudioEffectEQ6.new()
	eq.set_band_gain_db(EQ_AIR_BAND, -1.5)
	AudioServer.add_bus_effect(master, eq)
	# Tape saturation: an arctangent soft clipper, gain-compensated so small signals pass at unity.
	var sat := AudioEffectDistortion.new()
	sat.mode = AudioEffectDistortion.MODE_ATAN
	sat.drive = SAT_DRIVE
	sat.pre_gain = 0.0
	sat.post_gain = saturation_makeup_db(SAT_DRIVE)
	sat.keep_hf_hz = 16000.0
	AudioServer.add_bus_effect(master, sat)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.8
	lim.pre_gain_db = 0.0
	lim.release = 0.08
	AudioServer.add_bus_effect(master, lim)

	var music := AudioServer.get_bus_index(MUSIC)
	var tone := AudioEffectLowPassFilter.new()
	tone.cutoff_hz = 20000.0
	tone.resonance = 0.5
	AudioServer.add_bus_effect(music, tone)
	AudioServer.set_bus_effect_enabled(music, MUSIC_TONE, false)
	var glue := AudioEffectCompressor.new()
	glue.threshold = -15.0
	glue.ratio = 3.0
	glue.attack_us = 10000.0
	glue.release_ms = 200.0
	glue.gain = 1.0
	AudioServer.add_bus_effect(music, glue)

	var drums := AudioServer.get_bus_index(DRUMS)
	var kit := AudioEffectCompressor.new()
	kit.threshold = -12.0
	kit.ratio = 2.5
	kit.attack_us = 15000.0
	kit.release_ms = 120.0
	AudioServer.add_bus_effect(drums, kit)

	for i: int in LAYERS.size():
		var b := AudioServer.get_bus_index(LAYERS[i])
		var hp := AudioEffectHighPassFilter.new()
		hp.cutoff_hz = 70.0
		hp.resonance = 0.6
		AudioServer.add_bus_effect(b, hp)
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 12500.0
		lp.resonance = 0.5
		AudioServer.add_bus_effect(b, lp)
		AudioServer.add_bus_effect(b, AudioEffectEQ6.new())
		var ch := AudioEffectChorus.new()
		ch.voice_count = 2
		ch.dry = 1.0
		ch.wet = 0.0
		for v: int in 2:
			ch.set_voice_delay_ms(v, 14.0 + 4.0 * v)
			ch.set_voice_rate_hz(v, 0.83 + i * 0.07 + v * 0.31)
			ch.set_voice_depth_ms(v, 0.0)
			ch.set_voice_level_db(v, 0.0)
			ch.set_voice_cutoff_hz(v, 9000.0)
			ch.set_voice_pan(v, -0.4 if v == 0 else 0.4)
		AudioServer.add_bus_effect(b, ch)
		AudioServer.set_bus_effect_enabled(b, LAYER_CHORUS, false)
		AudioServer.add_bus_effect(b, AudioEffectPanner.new())
		AudioServer.set_bus_volume_db(b, -80.0)

		var s := AudioServer.get_bus_index(SENDS[i])
		var shp := AudioEffectHighPassFilter.new()
		shp.cutoff_hz = 180.0
		AudioServer.add_bus_effect(s, shp)
		var slp := AudioEffectLowPassFilter.new()
		slp.cutoff_hz = 9000.0
		AudioServer.add_bus_effect(s, slp)
		AudioServer.set_bus_volume_db(s, -80.0)

	var reverb := AudioServer.get_bus_index(REVERB)
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.62
	rv.damping = 0.55
	rv.spread = 0.85
	rv.hipass = 0.12
	rv.dry = 0.0
	rv.wet = 1.0
	rv.predelay_msec = 18.0
	rv.predelay_feedback = 0.2
	AudioServer.add_bus_effect(reverb, rv)
	var rlp := AudioEffectLowPassFilter.new()
	rlp.cutoff_hz = 6500.0
	AudioServer.add_bus_effect(reverb, rlp)
	AudioServer.set_bus_volume_db(reverb, linear_to_db(0.32))

	var sfx := AudioServer.get_bus_index(SFX)
	var sg := AudioEffectCompressor.new()
	sg.threshold = -10.0
	sg.ratio = 2.0
	sg.attack_us = 3000.0
	sg.release_ms = 120.0
	AudioServer.add_bus_effect(sfx, sg)
	var room := AudioEffectReverb.new()
	room.room_size = 0.45
	room.damping = 0.6
	room.spread = 0.7
	room.hipass = 0.2
	room.dry = 1.0
	room.wet = 0.12
	room.predelay_msec = 12.0
	AudioServer.add_bus_effect(sfx, room)
	for i: int in SFX_PAN.size():
		var pb := AudioServer.get_bus_index(SFX_PAN[i])
		var pan := AudioEffectPanner.new()
		pan.pan = SFX_PAN_VALUES[i]
		AudioServer.add_bus_effect(pb, pan)

	# Voice: lines arrive at -18 LUFS with a -1 dBFS ceiling. A gentle high-pass keeps rumble from the
	# radio treatments out of the music's low end; a soft compressor evens barks against lines.
	var voice := AudioServer.get_bus_index(VOICE)
	var vhp := AudioEffectHighPassFilter.new()
	vhp.cutoff_hz = 90.0
	AudioServer.add_bus_effect(voice, vhp)
	var vc := AudioEffectCompressor.new()
	vc.threshold = -14.0
	vc.ratio = 2.0
	vc.attack_us = 8000.0
	vc.release_ms = 150.0
	AudioServer.add_bus_effect(voice, vc)


## Writes the current layout to res://default_bus_layout.tres (tools/make_bus_layout.gd).
static func save_layout(path: String = "res://default_bus_layout.tres") -> Error:
	build()
	return ResourceSaver.save(AudioServer.generate_bus_layout(), path)
