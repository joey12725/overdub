class_name ActorClipSampler
extends RefCounted
## Exact, stateless clip sampling for a Skeleton3D. The clips live in the model's AnimationPlayer
## (imported from the .glb, or synthesised for a stand-in), but the player is never advanced: each
## frame the caller asks for a clip at an exact time, blends the results itself and writes the pose.
## That keeps every pose a pure function of the snapshot (scrubbed by local tick, reversible, no
## free-running playback state), and lets a state change cross-fade from the pose actually on screen
## (an AnimationTree cannot blend from an arbitrary frozen pose).
##
## Pose buffers are preallocated (Pose); sampling and blending allocate nothing.

const KIND_POS: int = 0
const KIND_ROT: int = 1
const KIND_SCL: int = 2


## A full skeleton pose: local position / rotation (x, y, z, w) / scale per bone.
class Pose:
	extends RefCounted
	var pos: PackedVector3Array = PackedVector3Array()
	var rot: PackedFloat32Array = PackedFloat32Array()
	var scl: PackedVector3Array = PackedVector3Array()

	func _init(n: int = 0) -> void:
		pos.resize(n)
		rot.resize(n * 4)
		scl.resize(n)

	func copy_from(o: Pose) -> void:
		# Same sizes: element-wise copy (no reallocation).
		for i: int in pos.size():
			pos[i] = o.pos[i]
			scl[i] = o.scl[i]
		for i: int in rot.size():
			rot[i] = o.rot[i]

	func get_rot(i: int) -> Quaternion:
		var k := i * 4
		return Quaternion(rot[k], rot[k + 1], rot[k + 2], rot[k + 3])

	func set_rot(i: int, q: Quaternion) -> void:
		var k := i * 4
		rot[k] = q.x
		rot[k + 1] = q.y
		rot[k + 2] = q.z
		rot[k + 3] = q.w


class Clip:
	extends RefCounted
	var anim: Animation = null
	var length: float = 1.0
	var loop: bool = false
	var tracks: PackedInt32Array = PackedInt32Array()
	var kinds: PackedInt32Array = PackedInt32Array()
	var bones: PackedInt32Array = PackedInt32Array()


var skeleton: Skeleton3D = null
var bone_count: int = 0
var rest: Pose = null
var _clips: Dictionary[StringName, Clip] = {}


func _init(p_skeleton: Skeleton3D, player: AnimationPlayer) -> void:
	skeleton = p_skeleton
	bone_count = skeleton.get_bone_count() if skeleton != null else 0
	rest = Pose.new(bone_count)
	for i: int in bone_count:
		var r := skeleton.get_bone_rest(i)
		rest.pos[i] = r.origin
		rest.set_rot(i, r.basis.get_rotation_quaternion())
		rest.scl[i] = r.basis.get_scale()
	if player != null:
		for full: StringName in player.get_animation_list():
			_bind(full, player.get_animation(full))


## Clip names are matched without their library prefix ("lib/idle" serves "idle").
func _bind(full: StringName, anim: Animation) -> void:
	if anim == null:
		return
	var s := String(full)
	var slash := s.rfind("/")
	var key := StringName(s.substr(slash + 1) if slash >= 0 else s)
	if _clips.has(key):
		return
	var c := Clip.new()
	c.anim = anim
	c.length = maxf(anim.length, 1e-4)
	c.loop = anim.loop_mode != Animation.LOOP_NONE
	for t: int in anim.get_track_count():
		var kind := -1
		match anim.track_get_type(t):
			Animation.TYPE_POSITION_3D:
				kind = KIND_POS
			Animation.TYPE_ROTATION_3D:
				kind = KIND_ROT
			Animation.TYPE_SCALE_3D:
				kind = KIND_SCL
		if kind < 0:
			continue
		var path := anim.track_get_path(t)
		if path.get_subname_count() == 0:
			continue
		var bone := skeleton.find_bone(String(path.get_subname(0)))
		if bone < 0:
			continue
		c.tracks.append(t)
		c.kinds.append(kind)
		c.bones.append(bone)
	_clips[key] = c


## Bind every clip of an AnimationLibrary (matched to this skeleton by bone name, whatever the track
## root). `replace`: its clips override ones already bound (the contract library over the .glb's
## own clips); otherwise only names not bound yet are added.
func add_library(lib: AnimationLibrary, replace: bool) -> void:
	if lib == null or skeleton == null:
		return
	for n: StringName in lib.get_animation_list():
		if replace:
			_clips.erase(n)
		_bind(n, lib.get_animation(n))


## Names of the bound clips.
func clip_names() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_clips.keys())
	return out


## The Animation bound to a clip name (null when missing): e.g. for CombatFeel.update_swing, which
## reads the grip-arc metadata of the combat-feel clips.
func clip_animation(clip: StringName) -> Animation:
	var c: Clip = _clips.get(clip)
	return c.anim if c != null else null


func has_clip(clip: StringName) -> bool:
	return _clips.has(clip)


func clip_length(clip: StringName) -> float:
	var c: Clip = _clips.get(clip)
	return c.length if c != null else 1.0


## Write clip `clip` at normalised position `frac` (0..1 of its length; wrapped for loops) into
## `out`. Bones the clip does not key keep their rest pose. Returns false if the clip is missing.
func sample(clip: StringName, frac: float, out: Pose) -> bool:
	out.copy_from(rest)
	var c: Clip = _clips.get(clip)
	if c == null:
		return false
	var f := frac
	if c.loop:
		f = fmod(f, 1.0)
		if f < 0.0:
			f += 1.0
	else:
		f = ActorMath.clamp01(f)
	var time := f * c.length
	var a := c.anim
	for k: int in c.tracks.size():
		var t := c.tracks[k]
		var b := c.bones[k]
		match c.kinds[k]:
			KIND_POS:
				out.pos[b] = a.position_track_interpolate(t, time)
			KIND_ROT:
				out.set_rot(b, a.rotation_track_interpolate(t, time).normalized())
			KIND_SCL:
				out.scl[b] = a.scale_track_interpolate(t, time)
	return true


## out = a blended toward b by w (0 = a, 1 = b). `out` may alias `a`.
static func blend(a: Pose, b: Pose, w: float, out: Pose) -> void:
	var t := ActorMath.clamp01(w)
	var n := a.pos.size()
	for i: int in n:
		out.pos[i] = a.pos[i].lerp(b.pos[i], t)
		out.scl[i] = a.scl[i].lerp(b.scl[i], t)
		var qa := a.get_rot(i)
		var qb := b.get_rot(i)
		if qa.dot(qb) < 0.0:
			qb = -qb
		out.set_rot(i, qa.slerp(qb, t).normalized())


## Write a pose onto the skeleton.
func apply(p: Pose) -> void:
	if skeleton == null:
		return
	for i: int in bone_count:
		skeleton.set_bone_pose_position(i, p.pos[i])
		skeleton.set_bone_pose_rotation(i, p.get_rot(i))
		skeleton.set_bone_pose_scale(i, p.scl[i])


## Write a pose onto another skeleton with the same bone layout (afterimages).
static func apply_to(skel: Skeleton3D, p: Pose) -> void:
	var n := mini(skel.get_bone_count(), p.pos.size())
	for i: int in n:
		skel.set_bone_pose_position(i, p.pos[i])
		skel.set_bone_pose_rotation(i, p.get_rot(i))
		skel.set_bone_pose_scale(i, p.scl[i])
