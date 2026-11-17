class_name FeelSubject
extends RefCounted
## Presentation state of one tracked body (a self or an enemy): its visual hit-hold, the lagged
## position that goes with it, squash-and-stretch, recoil tilt, hold jitter and impact flash.
## CombatFeel owns and advances these; the actor layer READS them when it poses the body:
##
##     var fx := feel.enemy_fx(id)                      # or feel.self_fx(tape)
##     var p := fx.pos if fx.has_pos else Vector2(snap.x, snap.y)     # lagged sim position
##     node.transform = fx.apply(base_transform_at(p))                # squash, tilt, jitter
##     clip_time -= fx.lag                                            # scrub the pose late
##
## Nothing here feeds back into the simulation.

const HISTORY: int = 48
## Seconds the impact flash takes to fade once its full frames are over.
const FLASH_FADE: float = 0.04

## Seconds the drawing is behind the sim (0 when not held).
var lag: float = 0.0
## True during the frozen part of a hold.
var frozen: bool = false
## Lagged sim position (valid when has_pos).
var pos: Vector2 = Vector2.ZERO
var has_pos: bool = false
## Flash 0..1 and whether this frame is the inverted "negative" frame.
var flash: float = 0.0
var invert: bool = false
## Last hit: tier and scene-space direction.
var tier: int = 0
var hit_dir: Vector3 = Vector3.FORWARD

var node: Node3D = null
var tint: Color = Color.WHITE
var speed: float = 1.0
var radius: float = 0.4
var height: float = 1.2
var style: String = "blade"
var weapon_len: float = 0.8
var body_scale: float = 1.0

var hold: FeelHold = FeelHold.new()
# Squash spring (x < 0 squashed along the hit, > 0 stretched), tilt spring (degrees), landing spring.
var _sq: float = 0.0
var _sq_v: float = 0.0
var _tilt: float = 0.0
var _tilt_v: float = 0.0
var _land: float = 0.0
var _land_v: float = 0.0
var _jitter: Vector3 = Vector3.ZERO
var _jitter_flip: float = 1.0
var _flash_left: float = 0.0
var _flashing: bool = false
# Position history ring (time, position).
var _ht: PackedFloat32Array = PackedFloat32Array()
var _hp: PackedVector2Array = PackedVector2Array()
var _hn: int = 0
var _hi: int = 0
var _clock: float = 0.0
# Knockback slide tracking (enemies).
var slide_left: float = 0.0
var slide_dist: float = 0.0
var slide_dust: float = 0.0
var slide_from: Vector2 = Vector2.ZERO
var slide_speed: float = 0.0
var prev_pos: Vector2 = Vector2.ZERO
var has_prev: bool = false
# Afterimage pacing (selves).
var ghost_timer: float = 0.0
var last_frac: float = -1.0
# Flash overlay bookkeeping (CombatFeel).
var flash_material: ShaderMaterial = null
var flash_meshes: Array[MeshInstance3D] = []
var flash_on: bool = false


func _init() -> void:
	_ht.resize(HISTORY)
	_hp.resize(HISTORY)


## A hit landed on this body.
func struck(p_tier: int, dir: Vector3, p_speed: float, with_flash: bool = true) -> void:
	tier = p_tier
	hit_dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	hold.start(FeelTune.hold_victim(p_tier, p_speed), FeelTune.catch_up(p_tier, p_speed))
	_sq = -FeelTune.SQUASH[p_tier]
	_sq_v = 0.0
	_tilt = FeelTune.TILT[p_tier]
	_tilt_v = 0.0
	if with_flash:
		# The contact frame itself is the first flash frame (and, on heavy tiers, the negative frame).
		_flash_left = float(FeelTune.FLASH_FRAMES[p_tier] - 1) / 60.0
		_flashing = true
		flash = 1.0
		invert = p_tier >= FeelTune.TIER_HEAVY


## This body's own attack connected (attacker-side hold).
func connected(p_tier: int, p_speed: float) -> void:
	hold.start(FeelTune.hold_attacker(p_tier, p_speed), FeelTune.catch_up(p_tier, p_speed))
	tier = p_tier


## Landing (end of a knockback slide) or a wall slam: a vertical squash pulse.
func landed(amount: float) -> void:
	_land = -amount
	_land_v = 0.0


func advance(dt: float, sim_pos: Vector2, valid_pos: bool) -> void:
	_clock += dt
	hold.advance(dt)
	lag = hold.lag()
	frozen = hold.frozen()
	if valid_pos:
		_hi = (_hi + 1) % HISTORY
		_ht[_hi] = _clock
		_hp[_hi] = sim_pos
		_hn = mini(_hn + 1, HISTORY)
		pos = _sample(_clock - lag)
		has_pos = true
	if frozen:
		# Hit-stop vibration: the held frame shudders across the hit, hard, one flip per frame.
		_jitter_flip = -_jitter_flip
		var side := Vector3.UP.cross(hit_dir)
		_jitter = side * (0.012 + 0.012 * float(tier)) * _jitter_flip
	else:
		_jitter = Vector3.ZERO
		# Springs run only once the hold releases, so the held frame IS the squashed extreme.
		var r := _spring(_sq, _sq_v, 520.0, 17.0, dt)
		_sq = r.x
		_sq_v = r.y
		r = _spring(_tilt, _tilt_v, 300.0, 16.0, dt)
		_tilt = r.x
		_tilt_v = r.y
	var l := _spring(_land, _land_v, 420.0, 18.0, dt)
	_land = l.x
	_land_v = l.y
	if _flashing:
		# Full for FLASH_FRAMES frames, then a two-frame fade; only the contact frame is inverted.
		invert = false
		_flash_left -= dt
		flash = clampf((_flash_left + FLASH_FADE) / FLASH_FADE, 0.0, 1.0) if _flash_left < -1e-5 else 1.0
		if flash <= 0.0:
			_flashing = false
	else:
		flash = 0.0
		invert = false


static func _spring(x: float, v: float, k: float, c: float, dt: float) -> Vector2:
	# Semi-implicit Euler in small steps: stable at any frame time.
	var left := minf(dt, 0.1)
	while left > 0.0:
		var h := minf(left, 1.0 / 240.0)
		v += (-k * x - c * v) * h
		x += v * h
		left -= h
	return Vector2(x, v)


func _sample(t: float) -> Vector2:
	if _hn == 0:
		return pos
	var newer_t := _ht[_hi]
	var newer_p := _hp[_hi]
	for k: int in _hn:
		var j := (_hi - k + HISTORY) % HISTORY
		if _ht[j] <= t:
			var span := newer_t - _ht[j]
			if span <= 1e-6:
				return _hp[j]
			return _hp[j].lerp(newer_p, clampf((t - _ht[j]) / span, 0.0, 1.0))
		newer_t = _ht[j]
		newer_p = _hp[j]
	return newer_p


## How far the lagged position is behind the newest one (zero when not held): add it to the
## interpolated position the actor layer already draws.
func lag_offset() -> Vector2:
	if not has_pos or _hn == 0 or lag <= 0.0:
		return Vector2.ZERO
	return pos - _hp[_hi]


## The deformation in scene space: squash/stretch along the hit, landing squash, recoil tilt.
func deform() -> Basis:
	var b := Basis.IDENTITY
	if absf(_sq) > 1e-4:
		var d := hit_dir
		var k := 1.0 + _sq
		var side := 1.0 / sqrt(maxf(0.2, k))
		# Scale k along d and `side` across it: S = side * I + (k - side) * d d^T.
		var m := k - side
		b = Basis(
			Vector3(side + m * d.x * d.x, m * d.x * d.y, m * d.x * d.z),
			Vector3(m * d.y * d.x, side + m * d.y * d.y, m * d.y * d.z),
			Vector3(m * d.z * d.x, m * d.z * d.y, side + m * d.z * d.z))
	if absf(_land) > 1e-4:
		var ky := 1.0 + _land
		var kx := 1.0 / sqrt(maxf(0.2, ky))
		b = Basis.from_scale(Vector3(kx, ky, kx)) * b
	if absf(_tilt) > 0.01:
		var axis := Vector3.UP.cross(hit_dir)
		if axis.length_squared() > 1e-6:
			b = Basis(axis.normalized(), deg_to_rad(_tilt)) * b
	return b


## `base` (the undeformed scene transform of the body) with the feel deformation and jitter
## applied, pivoting on the origin of the body (its feet).
func apply(base: Transform3D) -> Transform3D:
	return Transform3D(deform() * base.basis, base.origin + _jitter)


## True when apply() would change anything (lets callers skip work).
func is_deformed() -> bool:
	return absf(_sq) > 1e-4 or absf(_land) > 1e-4 or absf(_tilt) > 0.01 or frozen
