class_name MVTrack
extends RefCounted
## Visual state of one cassette layer (MUSIC-08/09, DESYNC, PLAY-05): where its contour is being read
## and how its drawing is treated. Node-free and deterministic: the state is a function of the
## sequence of update() calls, and jumping backwards in time (a new take, a cinematic restart) resets
## it.
##
##   alive        full colour, full width, full glow
##   dead         the line thins and greys over one beat; it never recovers this run (MUSIC-08)
##   desynced     the read phase slips forward (a quarter step per beat, full drift = 4 steps after
##                a bar), wavers and flickers; on resync it SNAPS back within half a beat with a flash
##   reversing    the contour is read retrograde inside its cycle, exactly like the audio, so the
##                drawing visibly runs backwards
##   stopped      the read position freezes (the audio holds a sustained figure)
##   not present  drawers show only a faint empty lane

## Full drift (1.0) displaces the read position by this many steps (director: phase = drift * 4).
const DRIFT_STEPS := 4.0
## Visual drift rise per beat while desynced (reaches 1 after one bar).
const DRIFT_RISE_PER_BEAT := 0.25
## Exponential snap-back rate (1/beats) after resync.
const SNAP_RATE := 9.0
const DEAD_FADE_BEATS := 1.0
const FLASH_BEATS := 1.0
const GREY := Color(0.56, 0.56, 0.6)

var layer: MVLayer = null
var present: bool = false
var speed: float = 1.0
var life: int = OD.LifeState.ALIVE
var synced: bool = true
## 1 forward, -1 reversing, 0 stopped.
var transport: int = 1
## 0..1, eased toward 1 when the self is dead.
var dead_mix: float = 0.0
## 0..1 visual desync drift.
var drift: float = 0.0
## 1 right after a resync, decaying to 0.
var snap_flash: float = 0.0
## Local step frozen while stopped.
var hold_step: float = 0.0
var last_beat: float = -INF


static func make(p_layer: MVLayer) -> MVTrack:
	var t := MVTrack.new()
	t.layer = p_layer
	return t


func is_dead() -> bool:
	return life != OD.LifeState.ALIVE


func is_desynced() -> bool:
	return present and not is_dead() and not synced


func reset() -> void:
	dead_mix = 1.0 if is_dead() else 0.0
	drift = 0.0
	snap_flash = 0.0
	last_beat = -INF


## Advances the visual state to master `beat` with the cassette's current audio state (null = absent).
func update(beat: float, s: TrackAudioState) -> void:
	var was_desynced := is_desynced()
	var was_transport := transport
	var p_present := s != null and s.present
	var restart := last_beat == -INF or beat < last_beat - 1.0 or beat > last_beat + 64.0
	present = p_present
	if s != null:
		speed = s.speed if s.speed > 0.0 else 1.0
		life = s.life
		synced = s.synced
		transport = s.transport
	else:
		life = OD.LifeState.ALIVE
		synced = true
		transport = 1
	if restart:
		dead_mix = 1.0 if is_dead() else 0.0
		drift = 0.0
		snap_flash = 0.0
		hold_step = layer.step_at(maxf(0.0, beat), speed)
		last_beat = beat
		return
	var db := maxf(0.0, beat - last_beat)
	last_beat = beat
	var dead_target := 1.0 if is_dead() else 0.0
	dead_mix = move_toward(dead_mix, dead_target, db / DEAD_FADE_BEATS)
	if is_desynced():
		if not was_desynced:
			drift = maxf(drift, 0.12)
		drift = minf(1.0, drift + DRIFT_RISE_PER_BEAT * db)
	else:
		if was_desynced and not is_dead() and drift > 0.05:
			snap_flash = 1.0
		drift *= exp(-SNAP_RATE * db)
		if drift < 0.002:
			drift = 0.0
	snap_flash = maxf(0.0, snap_flash - db / FLASH_BEATS)
	if transport == 0 and was_transport != 0:
		hold_step = _raw_step(beat)


func _raw_step(at_beat: float) -> float:
	return layer.step_at(at_beat, speed)


## Phase displacement (steps) of the reading at master beat `at_beat`: the drift plus a waver.
func phase_offset(at_beat: float) -> float:
	if drift <= 0.0:
		return 0.0
	var waver := sin(at_beat * 1.7) * 0.45 + sin(at_beat * 4.3 + 1.1) * 0.18
	return drift * (DRIFT_STEPS + waver)


## The contour index (local step) this layer reads at master beat `at_beat`, under the current state.
## Forward: n = beat * speed / rate (+ drift). Reversing: reflected inside the cycle like the engine's
## retrograde, so the drawing runs backwards. Stopped: frozen.
func read_step(at_beat: float) -> float:
	var n := hold_step if transport == 0 else _raw_step(at_beat)
	var at := n + phase_offset(at_beat)
	if transport == -1:
		var c := float(layer.cycle)
		at = c - 1.0 - fposmod(at, c)
	return at


## Contour value (0..1) this layer shows at master beat `at_beat`.
func value_at(at_beat: float) -> float:
	return layer.contour(maxf(0.0, read_step(at_beat)))


## value_at() for `n` master beats evenly spaced from `b0` to `b1` (inclusive), in one pass —
## identical results, a fraction of the call overhead (the strips sample hundreds of points per
## redraw). Beats below 0 read beat 0.
func sample_values(b0: float, b1: float, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	n = maxi(2, n)
	out.resize(n)
	var l := layer
	var c := float(l.cycle)
	var k := speed / l.local_rate
	var hi := c
	if transport != -1:
		hi = maxf(hold_step, maxf(maxf(b0, b1), 0.0) * k) + drift * (DRIFT_STEPS + 1.0) + 1.0
	l.ensure_steps(hi)
	var tab := l.table()
	var last := tab.size() - 2
	var sub := float(MVLayer.SUB)
	var db := (b1 - b0) / float(n - 1)
	for j: int in n:
		var b := maxf(0.0, b0 + db * j)
		var at := hold_step if transport == 0 else b * k
		if drift > 0.0:
			at += drift * (DRIFT_STEPS + sin(b * 1.7) * 0.45 + sin(b * 4.3 + 1.1) * 0.18)
		if transport == -1:
			at = c - 1.0 - fposmod(at, c)
		var x := maxf(0.0, at) * sub
		var i := int(x)
		var f := x - float(i)
		if i > last:
			i = posmod(i, MVLayer.MAX_SAMPLES - 2) if last >= MVLayer.MAX_SAMPLES - 3 else last
		out[j] = tab[i] + (tab[i + 1] - tab[i]) * f
	return out


## Position inside one period (0..1) at master beat `at_beat`, for the radial visualisers.
func period_phase(at_beat: float) -> float:
	var l := float(layer.period_steps())
	return fposmod(read_step(at_beat), l) / l


# ───────────────────────────── drawing treatment ─────────────────────────────

func grey() -> float:
	return dead_mix * 0.85


func width_scale() -> float:
	return lerpf(1.0, 0.4, dead_mix)


func glow() -> float:
	return lerpf(1.0, 0.15, dead_mix) * (1.0 + 0.8 * snap_flash)


## Overall opacity; a desynced layer flickers (deterministically, from the beat).
func alpha(at_beat: float) -> float:
	if not present:
		return 0.0
	var a := lerpf(1.0, 0.5, dead_mix)
	if drift > 0.0:
		var f := 0.5 + 0.5 * sin(at_beat * 23.0) * sin(at_beat * 7.0 + 0.4)
		a *= 1.0 - 0.35 * drift * f
	return a


## The layer colour after state treatment (grey when dead, white-hot right after a resync).
func tint(base: Color) -> Color:
	var c := base.lerp(GREY, grey())
	if snap_flash > 0.0:
		c = c.lerp(Color.WHITE, 0.6 * snap_flash)
	return c
