class_name AudioTrapLoops
extends Node
## Sustained trap sounds: a motor hum while any conveyor runs and a roar while any flame jet burns
## (docs/TRAPS.md). The one-shot trap sounds (strokes, warnings, darts...) are cues (AudioSfx); these
## two are states, so they follow `conveyor:on/off` and `flame:on/off` events and the level's initial
## state, and they only sound while the master transport runs (a belt does not move while time is
## frozen). The hum is tuned to the level's key root so it sits under the music.

const HUM_FAMILY: StringName = &"conveyor_hum"
const ROAR_FAMILY: StringName = &"flame_roar"
## Linear levels (the families peak at -1 dBFS): beds, well under the music.
const HUM_GAIN := 0.16
const ROAR_GAIN := 0.3
## Glide time constant (s): fades in and out without clicks.
const TAU := 0.06

var bank: AudioSampleBank
## Live states, by trap id.
var _conveyor_on: Dictionary = {}
var _flame_on: Dictionary = {}
var _conveyor_init: Dictionary = {}
var _flame_init: Dictionary = {}
var _hum: AudioStreamPlayer
var _roar: AudioStreamPlayer
var _hum_pick: AudioSampleBank.Pick
var _roar_pick: AudioSampleBank.Pick
var _hum_level := 0.0
var _roar_level := 0.0
var _running := false


func _ready() -> void:
	_hum = _make("Hum")
	_roar = _make("Roar")


func _make(n: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = n
	p.bus = AudioBusSetup.SFX
	p.volume_db = -80.0
	add_child(p)
	return p


## Reads the level's conveyors and flame jets and their state at beat zero. `root` is the key's pitch
## class (the hum plays on it, two octaves under middle C).
func setup(level: LevelDef, root: int) -> void:
	stop_all()
	_conveyor_init.clear()
	_flame_init.clear()
	var none: Dictionary[String, bool] = {}
	if level != null:
		for e: EntityDef in level.entities:
			if e is ConveyorDef:
				var c := e as ConveyorDef
				_conveyor_init[c.id] = ODSignals.eval_signal(c.run_when, none, 0.0) if c.run_when != null else true
			elif e is FlameDef:
				var f := e as FlameDef
				_flame_init[f.id] = ODSignals.eval_signal(f.on_when, none, 0.0) if f.on_when != null else false
	_hum_pick = bank.pick(HUM_FAMILY, 36 + posmod(root, 12)) if bank != null and bank.has_family(HUM_FAMILY) else null
	_roar_pick = bank.pick(ROAR_FAMILY, -1.0) if bank != null and bank.has_family(ROAR_FAMILY) else null
	restart()


## A new take / review from beat zero: back to the initial states.
func restart() -> void:
	_conveyor_on = _conveyor_init.duplicate()
	_flame_on = _flame_init.duplicate()


func has_traps() -> bool:
	return not _conveyor_init.is_empty() or not _flame_init.is_empty()


func on_events(events: Array[SimEvent]) -> void:
	for e: SimEvent in events:
		if e == null or e.type != SimEventType.TRAP:
			continue
		match e.detail:
			"conveyor:on":
				_conveyor_on[e.id] = true
			"conveyor:off":
				_conveyor_on[e.id] = false
			"flame:on":
				_flame_on[e.id] = true
			"flame:off":
				_flame_on[e.id] = false


static func _count_on(d: Dictionary) -> int:
	var n := 0
	for k: Variant in d:
		if d[k]:
			n += 1
	return n


## Number of running conveyors / burning jets (for tests and tools).
func conveyors_running() -> int:
	return _count_on(_conveyor_on)


func flames_burning() -> int:
	return _count_on(_flame_on)


## Target linear level of the hum / roar now.
func hum_target() -> float:
	var n := conveyors_running()
	return HUM_GAIN * (1.0 + 0.25 * float(maxi(0, n - 1))) if _running and n > 0 else 0.0


func roar_target() -> float:
	var n := flames_burning()
	return ROAR_GAIN * (1.0 + 0.25 * float(maxi(0, n - 1))) if _running and n > 0 else 0.0


## Per frame. `running` = the master transport is moving.
func update(running: bool, dt: float) -> void:
	_running = running
	var k := 1.0 - exp(-maxf(0.0, dt) / TAU)
	_hum_level += (hum_target() - _hum_level) * k
	_roar_level += (roar_target() - _roar_level) * k
	_drive(_hum, _hum_pick, _hum_level)
	_drive(_roar, _roar_pick, _roar_level)


func _drive(p: AudioStreamPlayer, pick: AudioSampleBank.Pick, level: float) -> void:
	if p == null:
		return
	if level < 0.0015:
		if p.playing:
			p.stop()
		return
	if not p.playing and pick != null and pick.sample != null and pick.sample.stream != null:
		p.stream = pick.sample.stream
		p.pitch_scale = pick.pitch_scale
		p.play(bank.pad if bank != null else 0.0)
	p.volume_db = linear_to_db(level)


func stop_all() -> void:
	_hum_level = 0.0
	_roar_level = 0.0
	_running = false
	for p: AudioStreamPlayer in [_hum, _roar]:
		if p != null and p.playing:
			p.stop()


## Players currently sounding (tests: nothing stuck after a stop).
func sounding() -> int:
	var n := 0
	for p: AudioStreamPlayer in [_hum, _roar]:
		if p != null and p.playing:
			n += 1
	return n
