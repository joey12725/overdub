class_name MoxiePose
extends RefCounted
## Procedural poses for Moxie (port of prototype render/actors/pose.ts). In the Godot build the pose
## comes from the clips in assets/models/moxie.glb; these functions synthesise the same clip set for
## the stand-in rig (MoxieStandin) so the runtime path is identical whether or not the model exists.
##
## A pose is a PackedFloat32Array indexed by the K_* constants. Conventions (model space, Moxie faces
## +Z, +Y up, her left side is +X):
##   *_RAISE  forward/up swing of a limb from hanging straight down (+ = forward).
##   *_OUT    sideways swing away from the body (+ = outward on that side).
##   *_TWIST  rotation about the limb's own long axis.
##   ELBOW/KNEE  flexion; hips/spine/head PITCH + leans forward, YAW + turns to her left,
##   ROLL + tilts to her right. PIG_*_SWING trails backward, *_OUT flares, *_TIP bends the tip.

enum {
	K_ROOT_Y, K_ROOT_FWD, K_STRETCH,
	K_HIPS_PITCH, K_HIPS_YAW, K_HIPS_ROLL,
	K_SPINE_PITCH, K_SPINE_YAW, K_SPINE_ROLL,
	K_HEAD_PITCH, K_HEAD_YAW, K_HEAD_ROLL,
	K_PHONES_BOB,
	K_ARM_L_RAISE, K_ARM_L_OUT, K_ARM_L_TWIST, K_ELBOW_L,
	K_ARM_R_RAISE, K_ARM_R_OUT, K_ARM_R_TWIST, K_ELBOW_R,
	K_LEG_L_RAISE, K_LEG_L_OUT, K_KNEE_L, K_FOOT_L,
	K_LEG_R_RAISE, K_LEG_R_OUT, K_KNEE_R, K_FOOT_R,
	K_PIG_L_SWING, K_PIG_L_OUT, K_PIG_L_TIP,
	K_PIG_R_SWING, K_PIG_R_OUT, K_PIG_R_TIP,
	K_JACKET_FLARE, K_SWING, K_WRIST,
	K_COUNT,
}

## Pose states: the timed ones take progress t in 0..1.
const S_IDLE: int = 0
const S_RUN: int = 1
const S_LIGHT_WINDUP: int = 2
const S_LIGHT_ACTIVE: int = 3
const S_LIGHT_RECOVER: int = 4
const S_HEAVY_WINDUP: int = 5
const S_HEAVY_ACTIVE: int = 6
const S_HEAVY_RECOVER: int = 7
const S_DODGE: int = 8
const S_RANGED: int = 9
const S_INTERACT: int = 10
const S_STOPPED: int = 11
const S_DEATH: int = 12


class Params:
	extends RefCounted
	## Seconds of presentation time (breathing, sway).
	var time: float = 0.0
	## Run cycle phase in radians.
	var stride: float = 0.0
	## 0..1 how fast the self moves relative to a full run.
	var speed: float = 1.0
	var beat: float = 0.0
	var lean_f: float = 0.0
	var lean_s: float = 0.0


static func create() -> PackedFloat32Array:
	var p := PackedFloat32Array()
	p.resize(K_COUNT)
	return p


static func blend_into(a: PackedFloat32Array, b: PackedFloat32Array, w: float) -> void:
	for k: int in K_COUNT:
		a[k] = a[k] + (b[k] - a[k]) * w


static func _base(p: Params, o: PackedFloat32Array) -> void:
	o.fill(0.0)
	# Confident wide stance with soft knees (R01: weight on one hip, feet apart).
	o[K_LEG_L_OUT] = 0.1
	o[K_LEG_R_OUT] = 0.1
	o[K_KNEE_L] = 0.08
	o[K_KNEE_R] = 0.08
	o[K_ARM_L_OUT] = 0.18
	o[K_ARM_R_OUT] = 0.18
	o[K_ELBOW_L] = 0.25
	o[K_ELBOW_R] = 0.25
	o[K_PIG_L_OUT] = 0.35
	o[K_PIG_R_OUT] = 0.35
	o[K_PIG_L_TIP] = 0.2
	o[K_PIG_R_TIP] = 0.2
	o[K_PHONES_BOB] = p.beat * 0.025
	o[K_HEAD_PITCH] = -p.beat * 0.06


static func _idle(p: Params, o: PackedFloat32Array, breathe: bool) -> void:
	_base(p, o)
	var tm := p.time if breathe else 0.0
	var br := sin(tm * PI)  # one breath per second: loops cleanly over the 2 s idle clip
	var sway := sin(tm * PI * 0.5)
	o[K_ROOT_Y] = br * 0.006
	o[K_SPINE_PITCH] = -0.04 + br * 0.025
	o[K_HIPS_ROLL] = 0.06 + sway * 0.02
	o[K_SPINE_ROLL] = -0.07 - sway * 0.02
	o[K_HEAD_ROLL] = 0.08 + sway * 0.03
	o[K_HEAD_YAW] = sin(tm * PI * 0.5) * 0.12
	# Right hand on hip (R01 pose language): elbow out, forearm folded back to the waist.
	o[K_ARM_R_OUT] = 0.55
	o[K_ARM_R_RAISE] = -0.25
	o[K_ELBOW_R] = 1.5
	o[K_ARM_R_TWIST] = -0.6
	o[K_ARM_L_RAISE] = 0.05 + br * 0.02
	o[K_PIG_L_SWING] = sin(tm * PI) * 0.08
	o[K_PIG_R_SWING] = sin(tm * PI + 1.2) * 0.08
	o[K_PIG_L_TIP] += sin(tm * PI * 2.0) * 0.06
	o[K_PIG_R_TIP] += sin(tm * PI * 2.0 + 2.0) * 0.06
	o[K_LEG_L_OUT] = 0.13
	o[K_LEG_R_OUT] = 0.08


static func _run(p: Params, o: PackedFloat32Array) -> void:
	_base(p, o)
	var s := p.stride
	var sp := ActorMath.clamp01(p.speed)
	var sn := sin(s)
	var amp := 0.25 + 0.75 * sp
	o[K_LEG_L_RAISE] = sn * 0.85 * amp
	o[K_LEG_R_RAISE] = -sn * 0.85 * amp
	o[K_KNEE_L] = 0.15 + maxf(0.0, -cos(s)) * 1.1 * amp + maxf(0.0, sn) * 0.3
	o[K_KNEE_R] = 0.15 + maxf(0.0, cos(s)) * 1.1 * amp + maxf(0.0, -sn) * 0.3
	o[K_FOOT_L] = -sn * 0.25 * amp
	o[K_FOOT_R] = sn * 0.25 * amp
	o[K_ARM_L_RAISE] = -sn * 0.75 * amp
	o[K_ARM_R_RAISE] = sn * 0.75 * amp
	o[K_ELBOW_L] = 1.1
	o[K_ELBOW_R] = 1.1
	o[K_ARM_L_OUT] = 0.15
	o[K_ARM_R_OUT] = 0.15
	o[K_ROOT_Y] = absf(cos(s)) * 0.035 * amp - 0.015 * sp
	o[K_HIPS_PITCH] = 0.12 * sp + clampf(p.lean_f, -1.0, 1.5) * 0.1
	o[K_SPINE_PITCH] = 0.1 * sp
	o[K_HIPS_ROLL] = clampf(p.lean_s, -1.0, 1.0) * -0.12
	o[K_SPINE_YAW] = sn * 0.18 * amp
	o[K_HIPS_YAW] = -sn * 0.12 * amp
	o[K_HEAD_PITCH] += -0.12 * sp
	var bounce := cos(s * 2.0) * 0.12
	o[K_PIG_L_SWING] = 0.75 * sp + bounce
	o[K_PIG_R_SWING] = 0.75 * sp - bounce
	o[K_PIG_L_TIP] = 0.35 + 0.2 * sp + sin(s * 2.0 + 0.6) * 0.12
	o[K_PIG_R_TIP] = 0.35 + 0.2 * sp + sin(s * 2.0 + 2.1) * 0.12
	o[K_PIG_L_OUT] = 0.45
	o[K_PIG_R_OUT] = 0.45
	o[K_JACKET_FLARE] = 0.55 * sp + absf(sn) * 0.1


static func _guard(p: Params, o: PackedFloat32Array) -> void:
	_base(p, o)
	o[K_LEG_L_RAISE] = 0.25
	o[K_LEG_R_RAISE] = -0.25
	o[K_KNEE_L] = 0.35
	o[K_KNEE_R] = 0.3
	o[K_ROOT_Y] = -0.02
	o[K_HIPS_PITCH] = 0.08
	o[K_ARM_R_RAISE] = 0.5
	o[K_ARM_R_OUT] = 0.35
	o[K_ELBOW_R] = 0.9
	o[K_ARM_L_RAISE] = 0.6
	o[K_ARM_L_OUT] = 0.1
	o[K_ELBOW_L] = 1.3
	o[K_PIG_L_SWING] = 0.15
	o[K_PIG_R_SWING] = 0.15


static func _light_windup(p: Params, t: float, o: PackedFloat32Array) -> void:
	_guard(p, o)
	var e := ActorMath.ease_out_cubic(t)
	# Weapon drawn back across the off side for a forehand slash.
	o[K_ARM_R_RAISE] = lerpf(0.5, 1.0, e)
	o[K_ARM_R_OUT] = lerpf(0.35, 1.25, e)
	o[K_ARM_R_TWIST] = lerpf(0.0, -0.6, e)
	o[K_ELBOW_R] = lerpf(0.9, 1.0, e)
	o[K_SPINE_YAW] = lerpf(0.0, 0.55, e)
	o[K_HIPS_YAW] = o[K_SPINE_YAW] * 0.3


static func _light_active(p: Params, t: float, o: PackedFloat32Array) -> void:
	_guard(p, o)
	var e := ActorMath.ease_out_cubic(t)
	o[K_SWING] = e
	o[K_ROOT_FWD] = 0.06 * e
	o[K_ARM_R_RAISE] = 1.35
	o[K_ARM_R_OUT] = lerpf(1.25, -0.55, e)
	o[K_ARM_R_TWIST] = lerpf(-0.6, 0.4, e)
	o[K_ELBOW_R] = lerpf(1.0, 0.15, e)
	o[K_SPINE_YAW] = lerpf(0.55, -0.6, e)
	o[K_HIPS_YAW] = o[K_SPINE_YAW] * 0.35
	o[K_PIG_L_SWING] = 0.15 + 0.35 * e
	o[K_PIG_R_SWING] = 0.15 + 0.35 * e
	o[K_PIG_L_OUT] = 0.35 + 0.4 * e
	o[K_JACKET_FLARE] = 0.3 * e


static func _light_recover(p: Params, t: float, o: PackedFloat32Array, scratch: PackedFloat32Array) -> void:
	_light_active(p, 1.0, o)
	_guard(p, scratch)
	blend_into(o, scratch, ActorMath.ease_in_out_sine(t))
	o[K_SWING] = 1.0


static func _heavy_windup(p: Params, t: float, o: PackedFloat32Array) -> void:
	_guard(p, o)
	var e := ActorMath.ease_out_cubic(t)
	# Deep coil: low squat, torso leaning back, weapon hauled overhead with both hands.
	o[K_ROOT_Y] = lerpf(-0.02, -0.11, e)
	o[K_LEG_L_RAISE] = lerpf(0.25, 0.75, e)
	o[K_LEG_R_RAISE] = lerpf(-0.25, -0.35, e)
	o[K_KNEE_L] = lerpf(0.35, 1.25, e)
	o[K_KNEE_R] = lerpf(0.3, 0.9, e)
	o[K_HIPS_PITCH] = lerpf(0.08, 0.25, e)
	o[K_SPINE_PITCH] = lerpf(0.0, -0.55, e)
	o[K_HEAD_PITCH] += lerpf(0.0, 0.2, e)
	o[K_ARM_R_RAISE] = lerpf(0.5, 2.85, e)
	o[K_ARM_R_OUT] = lerpf(0.35, 0.15, e)
	o[K_ELBOW_R] = lerpf(0.9, 0.85, e)
	o[K_ARM_L_RAISE] = lerpf(0.6, 2.7, e)
	o[K_ARM_L_OUT] = lerpf(0.1, -0.15, e)
	o[K_ELBOW_L] = lerpf(1.3, 0.95, e)
	o[K_SPINE_YAW] = lerpf(0.0, 0.15, e)
	o[K_PIG_L_SWING] = lerpf(0.15, -0.35, e)
	o[K_PIG_R_SWING] = lerpf(0.15, -0.35, e)
	o[K_JACKET_FLARE] = 0.15 * e


static func _heavy_active(p: Params, t: float, o: PackedFloat32Array) -> void:
	_guard(p, o)
	var e := ActorMath.ease_in_cubic(minf(1.0, t * 1.6)) * 0.35 + ActorMath.ease_out_cubic(t) * 0.65
	o[K_SWING] = e
	# Explosive lunge: front leg drives forward, rear leg extends, torso slams down.
	o[K_ROOT_FWD] = lerpf(0.0, 0.22, e)
	o[K_ROOT_Y] = lerpf(-0.11, -0.13, e)
	o[K_LEG_L_RAISE] = lerpf(0.75, 0.95, e)
	o[K_KNEE_L] = lerpf(1.25, 1.0, e)
	o[K_LEG_R_RAISE] = lerpf(-0.35, -0.75, e)
	o[K_KNEE_R] = lerpf(0.9, 0.35, e)
	o[K_HIPS_PITCH] = lerpf(0.25, 0.4, e)
	o[K_SPINE_PITCH] = lerpf(-0.55, 0.55, e)
	o[K_HEAD_PITCH] += lerpf(0.2, -0.3, e)
	o[K_ARM_R_RAISE] = lerpf(2.85, 0.55, e)
	o[K_ARM_R_OUT] = lerpf(0.15, -0.1, e)
	o[K_ELBOW_R] = lerpf(0.85, 0.05, e)
	o[K_ARM_L_RAISE] = lerpf(2.7, 0.65, e)
	o[K_ARM_L_OUT] = lerpf(-0.15, -0.3, e)
	o[K_ELBOW_L] = lerpf(0.95, 0.2, e)
	o[K_SPINE_YAW] = lerpf(0.15, -0.05, e)
	o[K_PIG_L_SWING] = lerpf(-0.35, 0.9, e)
	o[K_PIG_R_SWING] = lerpf(-0.35, 0.9, e)
	o[K_PIG_L_OUT] = 0.6
	o[K_PIG_R_OUT] = 0.6
	o[K_JACKET_FLARE] = lerpf(0.15, 0.8, e)


static func _heavy_recover(p: Params, t: float, o: PackedFloat32Array, scratch: PackedFloat32Array) -> void:
	_heavy_active(p, 1.0, o)
	_guard(p, scratch)
	# Heavy recovery holds the slam longer before rising: a visible punish window.
	blend_into(o, scratch, ActorMath.smooth(0.35, 1.0, t))
	o[K_SWING] = 1.0


static func _dodge(p: Params, t: float, o: PackedFloat32Array) -> void:
	_base(p, o)
	var b := ActorMath.bump(t)
	var e := ActorMath.ease_out_cubic(t)
	o[K_STRETCH] = 0.28 * b
	o[K_ROOT_Y] = -0.08 * b
	o[K_HIPS_PITCH] = 0.65 * b
	o[K_SPINE_PITCH] = 0.25 * b
	o[K_HEAD_PITCH] += -0.45 * b
	o[K_LEG_L_RAISE] = lerpf(0.2, 0.7, e) * b
	o[K_KNEE_L] = 0.3 + 0.9 * b
	o[K_LEG_R_RAISE] = -0.9 * b
	o[K_KNEE_R] = 0.2 + 0.4 * b
	o[K_ARM_L_RAISE] = -1.1 * b
	o[K_ARM_R_RAISE] = -1.0 * b
	o[K_ARM_L_OUT] = 0.35
	o[K_ARM_R_OUT] = 0.35
	o[K_ELBOW_L] = 0.3
	o[K_ELBOW_R] = 0.3
	o[K_PIG_L_SWING] = 1.2 * b
	o[K_PIG_R_SWING] = 1.2 * b
	o[K_PIG_L_TIP] = 0.5
	o[K_PIG_R_TIP] = 0.5
	o[K_JACKET_FLARE] = 1.0 * b


static func _ranged(p: Params, t: float, o: PackedFloat32Array) -> void:
	_base(p, o)
	var aim := ActorMath.smooth(0.0, 0.2, t) * (1.0 - ActorMath.smooth(0.8, 1.0, t))
	var recoil := exp(-((t - 0.3) * (t - 0.3)) / 0.006)
	# Side-on shooting stance, wrist device thrust at the target, off hand bracing the forearm.
	o[K_LEG_L_RAISE] = 0.3 * aim
	o[K_LEG_R_RAISE] = -0.25 * aim
	o[K_KNEE_L] = 0.2 + 0.2 * aim
	o[K_SPINE_YAW] = -0.4 * aim
	o[K_HIPS_YAW] = -0.2 * aim
	o[K_HEAD_YAW] = 0.4 * aim
	o[K_ARM_L_RAISE] = 1.5 * aim
	o[K_ARM_L_OUT] = lerpf(0.18, -0.15, aim)
	o[K_ARM_L_TWIST] = 0.3 * aim
	o[K_ELBOW_L] = lerpf(0.25, 0.02, aim) + recoil * 0.4
	o[K_ARM_R_RAISE] = 1.15 * aim
	o[K_ARM_R_OUT] = lerpf(0.18, -0.6, aim)
	o[K_ELBOW_R] = lerpf(0.25, 1.1, aim)
	o[K_SPINE_PITCH] = -0.1 * recoil
	o[K_ROOT_FWD] = -0.04 * recoil
	o[K_WRIST] = maxf(aim * 0.6, recoil)


static func _interact(p: Params, t: float, o: PackedFloat32Array) -> void:
	_idle(p, o, false)
	var b := ActorMath.bump(t)
	o[K_HIPS_PITCH] = 0.15 * b
	o[K_SPINE_PITCH] = 0.2 * b
	o[K_HEAD_PITCH] += 0.3 * b
	o[K_ARM_L_RAISE] = 1.25 * b + 0.05
	o[K_ARM_L_OUT] = lerpf(0.18, -0.1, b)
	o[K_ELBOW_L] = lerpf(0.25, 0.15, b)
	o[K_LEG_L_RAISE] = 0.3 * b
	o[K_KNEE_L] = 0.08 + 0.25 * b
	o[K_WRIST] = b * 0.5


static func _death(p: Params, t: float, o: PackedFloat32Array) -> void:
	_base(p, o)
	var hit := ActorMath.ease_out_cubic(minf(1.0, t * 2.5))
	var fall := ActorMath.smooth(0.3, 1.0, t)
	o[K_SPINE_PITCH] = -0.55 * hit + 0.35 * fall
	o[K_HIPS_PITCH] = -0.15 * hit + 0.3 * fall
	o[K_HEAD_PITCH] = -0.5 * hit + 0.5 * fall
	o[K_HEAD_ROLL] = 0.3 * hit
	o[K_ARM_L_OUT] = 0.2 + 1.0 * hit - 0.5 * fall
	o[K_ARM_R_OUT] = 0.2 + 1.1 * hit - 0.5 * fall
	o[K_ARM_L_RAISE] = 0.6 * hit - 0.4 * fall
	o[K_ARM_R_RAISE] = 0.4 * hit - 0.3 * fall
	o[K_ELBOW_L] = 0.4
	o[K_ELBOW_R] = 0.6
	o[K_ROOT_FWD] = -0.12 * hit
	o[K_KNEE_L] = 0.1 + 1.3 * fall
	o[K_KNEE_R] = 0.1 + 1.0 * fall
	o[K_LEG_L_RAISE] = 0.7 * fall
	o[K_LEG_R_RAISE] = 0.45 * fall
	o[K_ROOT_Y] = -0.2 * fall
	o[K_HIPS_ROLL] = 0.25 * fall
	o[K_PIG_L_SWING] = -0.6 * hit + 0.4 * fall
	o[K_PIG_R_SWING] = -0.6 * hit + 0.4 * fall
	o[K_PIG_L_OUT] = 0.8 * hit
	o[K_PIG_R_OUT] = 0.8 * hit
	o[K_JACKET_FLARE] = 0.6 * hit
	o[K_PHONES_BOB] = 0.04 * hit


## Write the pose for `state` at progress t (0..1; ignored by cyclic states) into `o`.
## `scratch` is a second pose buffer used by the recover blends. Always finite.
static func compute(state: int, t: float, p: Params, o: PackedFloat32Array, scratch: PackedFloat32Array) -> void:
	var u := ActorMath.clamp01(t if not is_nan(t) else 0.0)
	match state:
		S_IDLE:
			_idle(p, o, true)
		S_RUN:
			_run(p, o)
		S_LIGHT_WINDUP:
			_light_windup(p, u, o)
		S_LIGHT_ACTIVE:
			_light_active(p, u, o)
		S_LIGHT_RECOVER:
			_light_recover(p, u, o, scratch)
		S_HEAVY_WINDUP:
			_heavy_windup(p, u, o)
		S_HEAVY_ACTIVE:
			_heavy_active(p, u, o)
		S_HEAVY_RECOVER:
			_heavy_recover(p, u, o, scratch)
		S_DODGE:
			_dodge(p, u, o)
		S_RANGED:
			_ranged(p, u, o)
		S_INTERACT:
			_interact(p, u, o)
		S_STOPPED:
			_idle(p, o, false)
		S_DEATH:
			_death(p, u, o)
	for k: int in K_COUNT:
		if is_nan(o[k]) or is_inf(o[k]):
			o[k] = 0.0
