class_name TapeLib
extends RefCounted
## Tapes: sampling, velocity estimation, cloning and serialisation (PLAY-01..06). Port of the free
## functions of prototype/src/core/tape.ts (the TapeRecorder class is core/tape_recorder.gd, the Tape
## data class is ODTape). Never instantiated.
##
## A Tape is a fixed trajectory (pose sample per local tick, sample 0 = start pose) plus action
## events. Playback samples it by fractional local tick; it never re-runs physics.


## A 2D value that functions can write into (the prototype's `{ x, y }` out-parameters). Vector2 is
## a 32-bit value type and cannot be an out-parameter, so samplers write into this instead.
class XY:
	extends RefCounted
	var x: float = 0.0
	var y: float = 0.0

	static func make(p_x: float = 0.0, p_y: float = 0.0) -> XY:
		var o := XY.new()
		o.x = p_x
		o.y = p_y
		return o


## One interpolated pose.
class PoseSample:
	extends XY
	var facing: float = 0.0
	## AnimState.*
	var anim: StringName = &"idle"

	static func make_pose(p_x: float, p_y: float, p_facing: float, p_anim: StringName) -> PoseSample:
		var o := PoseSample.new()
		o.x = p_x
		o.y = p_y
		o.facing = p_facing
		o.anim = p_anim
		return o

	func equals(o: PoseSample) -> bool:
		return x == o.x and y == o.y and facing == o.facing and anim == o.anim

	func copy() -> PoseSample:
		return make_pose(x, y, facing, anim)


## Constructor argument of TapeRecorder (tape.ts TapeRecorderInit).
class TapeRecorderInit:
	extends RefCounted
	## TapeIndex 0..3.
	var index: int = 0
	## TapeSpeed.
	var speed: float = 1.0
	## OD.EndMode.
	var end_mode: int = OD.EndMode.STOP
	## Local ticks the take will last (level allowance).
	var ticks: int = 0
	## Start pose = sample 0 (REC-02: every tape starts at the level start at beat zero).
	var start_x: float = 0.0
	var start_y: float = 0.0
	var start_facing: float = 0.0
	## AnimState.* of sample 0 (prototype `start.anim ?? 'idle'`).
	var start_anim: StringName = &"idle"

	static func make(p_index: int, p_speed: float, p_end_mode: int, p_ticks: int, p_x: float, p_y: float, p_facing: float, p_anim: StringName = &"idle") -> TapeRecorderInit:
		var o := TapeRecorderInit.new()
		o.index = p_index
		o.speed = p_speed
		o.end_mode = p_end_mode
		o.ticks = p_ticks
		o.start_x = p_x
		o.start_y = p_y
		o.start_facing = p_facing
		o.start_anim = p_anim
		return o


## AnimState -> index stored in ODTape.anim (-1 for a value that is not an AnimState; the
## prototype's typed map has no such case).
static func anim_index(anim: StringName) -> int:
	return OD.ANIM_STATES.find(anim)


## Index stored in ODTape.anim -> AnimState (unknown indices read as idle).
static func anim_from_index(i: int) -> StringName:
	return OD.ANIM_STATES[i] if i >= 0 and i < OD.ANIM_STATES.size() else AnimState.IDLE


## Wrap an angle into (-π, π].
static func wrap_angle(a: float) -> float:
	# JS `%` on doubles is fmod (sign follows the dividend), as here.
	var r := fmod(a, TAU)
	if r <= -PI:
		r += TAU
	elif r > PI:
		r -= TAU
	return r


## Signed shortest angular difference b − a, in (-π, π].
static func angle_delta(a: float, b: float) -> float:
	return wrap_angle(b - a)


## Interpolate angles along the shortest arc. (Shadows the global lerp_angle: call it as
## TapeLib.lerp_angle; the result is wrapped to (-π, π], unlike the built-in.)
static func lerp_angle(a: float, b: float, t: float) -> float:
	return wrap_angle(a + wrap_angle(b - a) * t)

# ───────────────────────────── sampling ─────────────────────────────


## Pose at a fractional local tick (clamped to [0, ticks]). Position is linearly interpolated,
## facing along the shortest arc, and anim is the sample at floor(tick) (state of the tick in progress).
static func sample_pose(tape: ODTape, tick: float) -> PoseSample:
	return sample_pose_into(tape, tick, PoseSample.new())


## Allocation-free sample_pose.
static func sample_pose_into(tape: ODTape, tick: float, out: PoseSample) -> PoseSample:
	var T := tape.ticks
	var t: float = (tick if tick < T else float(T)) if tick > 0.0 else 0.0
	var i := floori(t)
	var f := t - i
	var p := tape.pos
	if f == 0.0 or i >= T:
		out.x = p[i * 2]
		out.y = p[i * 2 + 1]
		out.facing = tape.facing[i]
	else:
		var x0 := p[i * 2]
		var y0 := p[i * 2 + 1]
		out.x = x0 + (p[i * 2 + 2] - x0) * f
		out.y = y0 + (p[i * 2 + 3] - y0) * f
		var fa := tape.facing[i]
		out.facing = wrap_angle(fa + wrap_angle(tape.facing[i + 1] - fa) * f)
	out.anim = anim_from_index(tape.anim[i])
	return out


## Pose of a tape at a master substep: the playhead from ODTime.tape_phase_into (end behaviour
## applied), then sample_pose. `phase_out`, if given, receives the phase. Allocation-free when both
## outs are passed.
static func sample_pose_at_sub(tape: ODTape, sub: float, out: PoseSample = null, phase_out: TapePhase = null) -> PoseSample:
	var o := out if out != null else PoseSample.new()
	var ph := phase_out if phase_out != null else TapePhase.new()
	ODTime.tape_phase_into(tape, sub, ph)
	return sample_pose_into(tape, ph.tick, o)


## Position only, allocation-free (hot path for collision and desync checks).
static func sample_pos_into(tape: ODTape, tick: float, out: XY) -> XY:
	var T := tape.ticks
	var t: float = (tick if tick < T else float(T)) if tick > 0.0 else 0.0
	var i := floori(t)
	var f := t - i
	var p := tape.pos
	if f == 0.0 or i >= T:
		out.x = p[i * 2]
		out.y = p[i * 2 + 1]
	else:
		out.x = p[i * 2] + (p[i * 2 + 2] - p[i * 2]) * f
		out.y = p[i * 2 + 1] + (p[i * 2 + 3] - p[i * 2 + 1]) * f
	return out


## Local-space velocity (tiles per local second) of the recorded motion at a fractional tick:
## the slope of the segment containing it (the last segment at t = ticks). Zero for empty tapes.
static func local_velocity_at(tape: ODTape, tick: float, out: XY = null) -> XY:
	var o := out if out != null else XY.new()
	var T := tape.ticks
	if T <= 0:
		o.x = 0.0
		o.y = 0.0
		return o
	var t: float = (tick if tick < T else float(T)) if tick > 0.0 else 0.0
	var i := mini(floori(t), T - 1)
	var p := tape.pos
	o.x = (p[i * 2 + 2] - p[i * 2]) * OD.LOCAL_HZ
	o.y = (p[i * 2 + 3] - p[i * 2 + 1]) * OD.LOCAL_HZ
	return o


## Master-space velocity (tiles per master second) of the visible motion: local velocity × speed ×
## playhead direction (1, -1 or 0). A reversing tape moves backward along its path; a stopped one is still.
static func master_velocity_at(tape: ODTape, tick: float, dir: int, out: XY = null) -> XY:
	var o := local_velocity_at(tape, tick, out)
	var k := tape.speed * dir
	o.x *= k
	o.y *= k
	# Normalise -0 so snapshots compare cleanly.
	if o.x == 0.0:
		o.x = 0.0
	if o.y == 0.0:
		o.y = 0.0
	return o


## Deep copy (= tape.copy()).
static func clone_tape(tape: ODTape) -> ODTape:
	return tape.copy()


## Same trajectory and events with a different end mode (setup can change end behaviour; the recording is untouched).
static func with_end_mode(tape: ODTape, end_mode: int) -> ODTape:
	var t := tape.copy()
	t.end_mode = end_mode
	return t


## Bit-exact equality of two tapes (determinism tests, replay verification).
static func tapes_equal(a: ODTape, b: ODTape) -> bool:
	if a.index != b.index or a.speed != b.speed or a.end_mode != b.end_mode or a.ticks != b.ticks:
		return false
	if not _floats_equal(a.pos, b.pos) or not _floats_equal(a.facing, b.facing) or a.anim != b.anim:
		return false
	if a.events.size() != b.events.size():
		return false
	for i in a.events.size():
		var x := a.events[i]
		var y := b.events[i]
		if x.tick != y.tick or x.kind != y.kind or not _same(x.dir, y.dir) or not _same(x.x, y.x) or not _same(x.y, y.y) or not _same(x.vx, y.vx) or not _same(x.vy, y.vy):
			return false
	return true


## Object.is(a, b) || a === b: equal, or both NaN.
static func _same(a: float, b: float) -> bool:
	return a == b or (is_nan(a) and is_nan(b))


static func _floats_equal(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not (a[i] == b[i] or (is_nan(a[i]) and is_nan(b[i]))):
			return false
	return true

# ───────────────────────────── serialisation ─────────────────────────────


## JSON-safe tape (SerializedTape, = tape.to_dict()). Pose arrays are little-endian bytes in base64
## (lossless and ~4× smaller than number arrays). Events are tuples [tick, kindIndex, dir, x, y, vx,
## vy]; doubles round-trip exactly through JSON written with ODJson.stringify.
static func serialize_tape(tape: ODTape) -> Dictionary:
	return tape.to_dict()


## Inverse of serialize_tape (= ODTape.from_dict). Returns null and appends the reason to `errors`
## on malformed input (wrong version, lengths or kinds).
static func deserialize_tape(s: Variant, errors: Array[String] = []) -> ODTape:
	return ODTape.from_dict(s, errors)


const _B64: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


## Standard padded base64 (pure, so core stays free of engine encoders; byte-identical to Marshalls).
static func base64_from_bytes(b: PackedByteArray) -> String:
	var parts := PackedStringArray()
	var i := 0
	var size := b.size()
	while i + 2 < size:
		var n := (b[i] << 16) | (b[i + 1] << 8) | b[i + 2]
		parts.append(_B64[n >> 18] + _B64[(n >> 12) & 63] + _B64[(n >> 6) & 63] + _B64[n & 63])
		i += 3
	var rem := size - i
	if rem == 1:
		var n := b[i] << 16
		parts.append(_B64[n >> 18] + _B64[(n >> 12) & 63] + "==")
	elif rem == 2:
		var n := (b[i] << 16) | (b[i + 1] << 8)
		parts.append(_B64[n >> 18] + _B64[(n >> 12) & 63] + _B64[(n >> 6) & 63] + "=")
	return "".join(parts)


## Inverse of base64_from_bytes. On malformed input appends the prototype's message to `errors` and
## returns an empty array (check `errors` to tell it from a valid empty string).
static func bytes_from_base64(s: String, errors: Array[String] = []) -> PackedByteArray:
	var out := PackedByteArray()
	var length := s.length()
	if length % 4 != 0:
		errors.append("base64: length not a multiple of 4")
		return out
	var pad := 0
	if s.ends_with("=="):
		pad = 2
	elif s.ends_with("="):
		pad = 1
	out.resize((length / 4) * 3 - pad)
	var total := out.size()
	var o := 0
	var i := 0
	while i < length:
		var a := _dec(s, i)
		var b := _dec(s, i + 1)
		var c := 0 if s[i + 2] == "=" else _dec(s, i + 2)
		var d := 0 if s[i + 3] == "=" else _dec(s, i + 3)
		if a < 0 or b < 0 or c < 0 or d < 0:
			var bad := i if a < 0 else (i + 1 if b < 0 else (i + 2 if c < 0 else i + 3))
			errors.append("base64: bad character at %d" % bad)
			return PackedByteArray()
		var n := (a << 18) | (b << 12) | (c << 6) | d
		if o < total:
			out[o] = (n >> 16) & 255
			o += 1
		if o < total:
			out[o] = (n >> 8) & 255
			o += 1
		if o < total:
			out[o] = n & 255
			o += 1
		i += 4
	return out


## Value of the base64 digit at s[i], or -1.
static func _dec(s: String, i: int) -> int:
	var code := s.unicode_at(i)
	if code >= 128:
		return -1
	return _B64.find(char(code)) if code != 61 else -1
