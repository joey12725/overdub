class_name AudioMixer
extends RefCounted
## Drives the bus layout (AudioBusSetup) at runtime (the Godot counterpart of prototype
## src/audio/mixer.ts): per-layer state colour, the mix mode and the volume faders. Every change
## glides (GLIDE seconds) so nothing clicks.
##
## State colour (MUSIC-08) is applied here on top of the note changes made in AudioDirector: a dead
## self's layer goes hollow (band-limited, a nasal presence bump, quieter, wetter); a desynced layer
## gets a detuned chorus and a darker top, both easing back as the drift converges.

## Layer pan per tape, scaled by role width (mixer.ts TAPE_PAN / ROLE_WIDTH).
const TAPE_PAN: Array[float] = [-0.34, -0.12, 0.12, 0.34]
const ROLE_WIDTH: Dictionary = {&"bass": 0.2, &"drums": 0.3, &"melody": 1.0, &"chord": 1.0}
const ROLE_LEVEL: Dictionary = {&"bass": 0.72, &"drums": 0.8, &"melody": 0.85, &"chord": 0.72}
## Time constant (s) for colour changes: quick enough to read, slow enough to never click.
const GLIDE := 0.12
const MODE_GLIDE := 0.4
## Music ducking under speech (docs/VOICE-CAST.md section 6): about 80 ms down, 400 ms back up.
const DUCK_DOWN_TAU := 0.027
const DUCK_UP_TAU := 0.13
## Duck depths (dB): a dialogue line, a bark.
const DUCK_LINE_DB := -6.0
const DUCK_BARK_DB := -3.0

## One layer's colour inputs (mixer.ts LayerColour).
class Colour:
	extends RefCounted
	var present: bool = false
	var dead: bool = false
	## 0..1 desync drift.
	var drift: float = 0.0
	var speed: float = 1.0

	static func make(p_present: bool, p_dead: bool, p_drift: float, p_speed: float) -> Colour:
		var c := Colour.new()
		c.present = p_present
		c.dead = p_dead
		c.drift = p_drift
		c.speed = p_speed
		return c

	func key() -> String:
		return "%s|%s|%s|%s" % [present, dead, drift, speed]


## Smoothed parameter: current value glides toward target.
class _Glide:
	extends RefCounted
	var value: float = 0.0
	var target: float = 0.0
	var tau: float = 0.12
	var log_scale: bool = false

	static func make(v: float, p_tau: float, p_log: bool = false) -> _Glide:
		var g := _Glide.new()
		g.value = v
		g.target = v
		g.tau = p_tau
		g.log_scale = p_log
		return g

	## Advances; returns true when the value moved enough to be worth applying.
	func step(dt: float) -> bool:
		if value == target:
			return false
		var k := 1.0 - exp(-dt / maxf(0.001, tau))
		var before := value
		if log_scale:
			value = exp(log(maxf(1.0, value)) + (log(maxf(1.0, target)) - log(maxf(1.0, value))) * k)
		else:
			value += (target - value) * k
		if absf(value - target) <= absf(target) * 0.002 + 0.0005:
			value = target
		return value != before


var roles: Array[StringName] = [MusicRole.MELODY, MusicRole.BASS, MusicRole.DRUMS, MusicRole.CHORD]
var mode: StringName = AudioBase.MODE_RECORD
var _colours: Array[Colour] = []
var _send_scale: float = 1.0
var _width: float = 1.0
# Per layer: level (linear), hp, lp (Hz), presence (dB), chorus wet, chorus depth (ms), send (linear), pan.
var _level: Array[_Glide] = []
var _hp: Array[_Glide] = []
var _lp: Array[_Glide] = []
var _presence: Array[_Glide] = []
var _chorus: Array[_Glide] = []
var _send: Array[_Glide] = []
var _pan: Array[_Glide] = []
var _tone := _Glide.make(20000.0, MODE_GLIDE, true)
var _air := _Glide.make(-1.5, MODE_GLIDE)
var _reverb := _Glide.make(0.32, MODE_GLIDE)
var _master := _Glide.make(0.8, 0.03)
var _music := _Glide.make(0.8, 0.03)
var _sfx := _Glide.make(0.8, 0.03)
var _ui := _Glide.make(0.72, 0.03)
## Voice fader (linear) and the music duck gain (linear, 1 = no duck).
var _voice := _Glide.make(1.0, 0.03)
var _duck := _Glide.make(1.0, DUCK_UP_TAU)
var _live: bool = false


func _init() -> void:
	for i: int in OD.TAPE_COUNT:
		_colours.append(Colour.make(false, false, 0.0, 1.0))
		_level.append(_Glide.make(0.0, GLIDE))
		_hp.append(_Glide.make(70.0, GLIDE, true))
		_lp.append(_Glide.make(12500.0, GLIDE, true))
		_presence.append(_Glide.make(0.0, GLIDE))
		_chorus.append(_Glide.make(0.0, GLIDE))
		_send.append(_Glide.make(0.0, GLIDE))
		_pan.append(_Glide.make(0.0, 0.3))


## Connects to the real buses (call once the layout exists). Until then everything is computed
## but nothing is applied, so the mixer is usable headless and in tests.
func attach() -> void:
	_live = true
	_apply_all()


func set_roles(p_roles: Array[StringName]) -> void:
	roles = p_roles.duplicate()
	for i: int in OD.TAPE_COUNT:
		_retarget(i)
		# A new level: jump straight to the new targets (nothing is sounding yet).
		for g: _Glide in [_level[i], _hp[i], _lp[i], _presence[i], _chorus[i], _send[i], _pan[i]]:
			g.value = g.target
	if _live:
		for i: int in OD.TAPE_COUNT:
			var bus := AudioServer.get_bus_index(AudioBusSetup.LAYERS[i])
			AudioServer.set_bus_send(bus, String(AudioBusSetup.DRUMS if roles[i] == MusicRole.DRUMS else AudioBusSetup.MUSIC))
		_apply_all()


func set_layer_colour(i: int, c: Colour) -> void:
	if i < 0 or i >= OD.TAPE_COUNT:
		return
	_colours[i] = c
	_retarget(i)


func colour(i: int) -> Colour:
	return _colours[i]


func _retarget(i: int) -> void:
	var c: Colour = _colours[i]
	var role: StringName = roles[i]
	var d := clampf(c.drift, 0.0, 1.0)
	var low_role := role == MusicRole.BASS or role == MusicRole.DRUMS
	# Faster layers carry more notes per second; trim them so a 4x layer does not dominate.
	var speed_trim := 1.0 / (1.0 + 0.18 * log(c.speed) / log(2.0)) if c.speed > 1.0 else 1.0
	_level[i].target = float(ROLE_LEVEL.get(role, 0.8)) * speed_trim * (0.8 if c.dead else 1.0) if c.present else 0.0
	_lp[i].target = 2600.0 if c.dead else 12500.0 - 5500.0 * d
	# A hollow ghost keeps some body: bass and drums are thinned, not removed.
	_hp[i].target = (140.0 if low_role else 320.0) if c.dead else (25.0 if low_role else 70.0)
	_presence[i].target = 5.0 if c.dead else 0.0
	_chorus[i].target = d
	_send[i].target = _send_scale * (2.2 if c.dead else 1.0 + 0.6 * d)
	_pan[i].target = clampf(TAPE_PAN[i] * float(ROLE_WIDTH.get(role, 1.0)) * _width, -0.85, 0.85)


## Cinematic opens the mix (wider, brighter, more room); menus sit back. Notes are untouched.
func set_mode(p_mode: StringName) -> void:
	mode = p_mode
	var cine := mode == AudioBase.MODE_CINEMATIC
	_air.target = 3.0 if cine else -1.5
	_tone.target = 3200.0 if mode == AudioBase.MODE_MENU else 20000.0
	_reverb.target = 0.46 if cine else 0.32
	_send_scale = 1.35 if cine else 1.0
	_width = 1.6 if cine else 1.0
	for i: int in OD.TAPE_COUNT:
		_retarget(i)


## Linear 0..1 faders. The UI bus (count-in, menu blips) follows the SFX fader but stays audible.
func set_volumes(master: float, music: float, sfx: float) -> void:
	_master.target = master
	_music.target = music
	_sfx.target = sfx
	_ui.target = sqrt(maxf(sfx, 0.0001)) * 0.9


## Linear 0..1 voice fader (0 mutes dialogue and barks).
func set_voice_volume(v: float) -> void:
	_voice.target = clampf(v, 0.0, 1.0)


## Ducks the music by `db` (<= 0; 0 releases). Going down is fast, coming back slow.
func set_duck(db: float) -> void:
	var t := db_to_linear(minf(0.0, db))
	if absf(t - _duck.target) < 1e-6:
		return
	_duck.tau = DUCK_DOWN_TAU if t < _duck.value else DUCK_UP_TAU
	_duck.target = t


## Current duck gain in dB (for tools and tests).
func duck_db() -> float:
	return linear_to_db(maxf(1e-5, _duck.value))


func duck_target_db() -> float:
	return linear_to_db(maxf(1e-5, _duck.target))


## Target values, for tests and diagnostics: {level, hp, lp, presence, chorus, send, pan} of a layer.
func layer_targets(i: int) -> Dictionary:
	return {
		"level": _level[i].target, "hp": _hp[i].target, "lp": _lp[i].target, "presence": _presence[i].target,
		"chorus": _chorus[i].target, "send": _send[i].target, "pan": _pan[i].target,
	}


## Current fader gains (linear) per output bus, duck included on music: what the bus volumes apply
## after each bus's effects (a capture effect on a bus hears the signal before them).
func bus_gains() -> Dictionary:
	return {
		"Master": _master.value, "Music": _music.value * _duck.value, "Sfx": _sfx.value, "Ui": _ui.value, "Voice": _voice.value,
	}


func mode_targets() -> Dictionary:
	return {"air": _air.target, "tone": _tone.target, "reverb": _reverb.target, "width": _width, "send_scale": _send_scale}


## Advance glides and push changes to the buses. Call every frame.
func process(dt: float) -> void:
	for i: int in OD.TAPE_COUNT:
		var level_moved := _level[i].step(dt)
		var send_moved := _send[i].step(dt)
		if (level_moved or send_moved) and _live:
			_apply_levels(i)
		if _hp[i].step(dt) and _live:
			_layer_hp(i).cutoff_hz = _hp[i].value
			_send_hp(i).cutoff_hz = maxf(180.0, _hp[i].value)
		if _lp[i].step(dt) and _live:
			_layer_lp(i).cutoff_hz = _lp[i].value
			_send_lp(i).cutoff_hz = minf(9000.0, _lp[i].value)
		if _presence[i].step(dt) and _live:
			_layer_eq(i).set_band_gain_db(AudioBusSetup.EQ_PRESENCE_BAND, _presence[i].value)
		if _chorus[i].step(dt) and _live:
			_apply_chorus(i)
		if _pan[i].step(dt) and _live:
			_layer_pan(i).pan = _pan[i].value
	if not _live:
		for g: _Glide in [_tone, _air, _reverb, _master, _music, _sfx, _ui, _voice, _duck]:
			g.step(dt)
		return
	if _tone.step(dt):
		_apply_tone()
	if _air.step(dt):
		var eq := AudioServer.get_bus_effect(AudioServer.get_bus_index(AudioBusSetup.MASTER), AudioBusSetup.MASTER_EQ) as AudioEffectEQ6
		eq.set_band_gain_db(AudioBusSetup.EQ_AIR_BAND, _air.value)
		eq.set_band_gain_db(AudioBusSetup.EQ_BRIGHT_BAND, maxf(0.0, _air.value) * 0.5)
	if _reverb.step(dt):
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AudioBusSetup.REVERB), linear_to_db(_reverb.value))
	if _master.step(dt):
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AudioBusSetup.MASTER), _db(_master.value))
	var music_moved := _music.step(dt)
	if _duck.step(dt) or music_moved:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AudioBusSetup.MUSIC), _db(_music.value * _duck.value))
	if _sfx.step(dt):
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AudioBusSetup.SFX), _db(_sfx.value))
	if _ui.step(dt):
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AudioBusSetup.UI), _db(_ui.value))
	if _voice.step(dt):
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AudioBusSetup.VOICE), _db(_voice.value))


static func _db(v: float) -> float:
	return -80.0 if v <= 0.0001 else maxf(-80.0, linear_to_db(v))


func _layer_bus(i: int) -> int:
	return AudioServer.get_bus_index(AudioBusSetup.LAYERS[i])


func _send_bus(i: int) -> int:
	return AudioServer.get_bus_index(AudioBusSetup.SENDS[i])


func _layer_hp(i: int) -> AudioEffectHighPassFilter:
	return AudioServer.get_bus_effect(_layer_bus(i), AudioBusSetup.LAYER_HP) as AudioEffectHighPassFilter


func _layer_lp(i: int) -> AudioEffectLowPassFilter:
	return AudioServer.get_bus_effect(_layer_bus(i), AudioBusSetup.LAYER_LP) as AudioEffectLowPassFilter


func _layer_eq(i: int) -> AudioEffectEQ6:
	return AudioServer.get_bus_effect(_layer_bus(i), AudioBusSetup.LAYER_EQ) as AudioEffectEQ6


func _layer_pan(i: int) -> AudioEffectPanner:
	return AudioServer.get_bus_effect(_layer_bus(i), AudioBusSetup.LAYER_PAN) as AudioEffectPanner


func _send_hp(i: int) -> AudioEffectHighPassFilter:
	return AudioServer.get_bus_effect(_send_bus(i), AudioBusSetup.SEND_HP) as AudioEffectHighPassFilter


func _send_lp(i: int) -> AudioEffectLowPassFilter:
	return AudioServer.get_bus_effect(_send_bus(i), AudioBusSetup.SEND_LP) as AudioEffectLowPassFilter


func _apply_levels(i: int) -> void:
	AudioServer.set_bus_volume_db(_layer_bus(i), _db(_level[i].value))
	# The send follows the layer level so a silent layer has a silent reverb.
	AudioServer.set_bus_volume_db(_send_bus(i), _db(_level[i].value * _send[i].value))


func _apply_chorus(i: int) -> void:
	var d := _chorus[i].value
	var bus := _layer_bus(i)
	var ch := AudioServer.get_bus_effect(bus, AudioBusSetup.LAYER_CHORUS) as AudioEffectChorus
	ch.wet = 0.5 * d
	for v: int in 2:
		ch.set_voice_depth_ms(v, 4.0 * d)
	AudioServer.set_bus_effect_enabled(bus, AudioBusSetup.LAYER_CHORUS, d > 0.001)


func _apply_tone() -> void:
	var music := AudioServer.get_bus_index(AudioBusSetup.MUSIC)
	var lp := AudioServer.get_bus_effect(music, AudioBusSetup.MUSIC_TONE) as AudioEffectLowPassFilter
	lp.cutoff_hz = _tone.value
	AudioServer.set_bus_effect_enabled(music, AudioBusSetup.MUSIC_TONE, _tone.value < 19000.0)


func _apply_all() -> void:
	if not _live:
		return
	for i: int in OD.TAPE_COUNT:
		_apply_levels(i)
		_layer_hp(i).cutoff_hz = _hp[i].value
		_layer_lp(i).cutoff_hz = _lp[i].value
		_send_hp(i).cutoff_hz = maxf(180.0, _hp[i].value)
		_send_lp(i).cutoff_hz = minf(9000.0, _lp[i].value)
		_layer_eq(i).set_band_gain_db(AudioBusSetup.EQ_PRESENCE_BAND, _presence[i].value)
		_apply_chorus(i)
		_layer_pan(i).pan = _pan[i].value
	_apply_tone()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AudioBusSetup.REVERB), linear_to_db(_reverb.value))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AudioBusSetup.MASTER), _db(_master.value))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AudioBusSetup.MUSIC), _db(_music.value * _duck.value))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AudioBusSetup.SFX), _db(_sfx.value))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AudioBusSetup.UI), _db(_ui.value))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AudioBusSetup.VOICE), _db(_voice.value))
