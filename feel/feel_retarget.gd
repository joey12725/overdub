class_name FeelRetarget
extends RefCounted
## Fits the shipped humanoid library (res://assets/anim/library/moxie_anims.res, authored in Godot's
## SkeletonProfileHumanoid reference-pose space) onto ANY humanoid Skeleton3D, whatever its bone
## axes, proportions or rest pose (T or A), and whether or not it has every profile bone.
##
##     var lib := FeelRetarget.bake_library(load(FeelRig.LIBRARY_PATH), skeleton)   # once, at load
##     player.add_animation_library(&"", lib)     # or hand it to ActorClipSampler via a player
##
## A skeleton imported through Godot's own retarget (BoneMap + "overwrite axis") already matches the
## profile and can use the library as-is (`matches_profile()` says so); baking is still harmless.
##
## How: a library key is a local rotation in profile space. Walking the profile hierarchy gives each
## bone's posed GLOBAL rotation, hence its model-space delta from the T-pose, D. On the target the
## posed global rotation is D * A * (target global rest), where A straightens a limb whose rest
## direction differs from the profile's (A-pose arms). Locals follow from the target's hierarchy.
## Bone names may be remapped with `alias` (profile name -> target bone name).

const PROFILE_HIP_HEIGHT: float = 0.75
## Limb bones whose rest direction is straightened to the profile's: bone -> the child that defines it.
const DIRECTION_CHILD: Dictionary[String, String] = {
	"LeftUpperArm": "LeftLowerArm", "LeftLowerArm": "LeftHand", "RightUpperArm": "RightLowerArm", "RightLowerArm": "RightHand",
	"LeftUpperLeg": "LeftLowerLeg", "LeftLowerLeg": "LeftFoot", "RightUpperLeg": "RightLowerLeg", "RightLowerLeg": "RightFoot",
}
## Names used by the pre-contract placeholder (assets/models/moxie.glb).
const PLACEHOLDER_ALIAS: Dictionary[String, String] = {
	"Hips": "hips", "Spine": "spine", "UpperChest": "chest", "Neck": "neck", "Head": "head",
	"LeftShoulder": "shoulder.L", "LeftUpperArm": "upper_arm.L", "LeftLowerArm": "forearm.L", "LeftHand": "hand.L",
	"RightShoulder": "shoulder.R", "RightUpperArm": "upper_arm.R", "RightLowerArm": "forearm.R", "RightHand": "hand.R",
	"LeftUpperLeg": "thigh.L", "LeftLowerLeg": "shin.L", "LeftFoot": "foot.L", "LeftToes": "toe.L",
	"RightUpperLeg": "thigh.R", "RightLowerLeg": "shin.R", "RightFoot": "foot.R", "RightToes": "toe.R",
}


## The alias map a skeleton needs: {} when it uses the profile names, PLACEHOLDER_ALIAS for the old rig.
static func alias_for(skel: Skeleton3D) -> Dictionary[String, String]:
	if skel.find_bone("Hips") >= 0:
		return {}
	if skel.find_bone("hips") >= 0 or skel.find_bone("upper_arm.L") >= 0 or skel.find_bone("upper_arm_L") >= 0:
		# Godot's importer may rewrite "." in bone names; map whichever spelling is present.
		var out: Dictionary[String, String] = {}
		for k: String in PLACEHOLDER_ALIAS:
			var v: String = PLACEHOLDER_ALIAS[k]
			if skel.find_bone(v) < 0 and skel.find_bone(v.replace(".", "_")) >= 0:
				v = v.replace(".", "_")
			out[k] = v
		return out
	return {}


## True when the skeleton's rest rotations already equal the profile reference pose (within ~1 degree).
static func matches_profile(skel: Skeleton3D) -> bool:
	var profile := SkeletonProfileHumanoid.new()
	var found := 0
	for i: int in profile.bone_size:
		var b := skel.find_bone(String(profile.get_bone_name(i)))
		if b < 0:
			continue
		found += 1
		var a := skel.get_bone_rest(b).basis.get_rotation_quaternion()
		var r := profile.get_reference_pose(i).basis.get_rotation_quaternion()
		if absf(a.dot(r)) < 0.99985:
			return false
	return found > 0


static func _global_rest(skel: Skeleton3D, bone: int) -> Transform3D:
	var t := skel.get_bone_rest(bone)
	var p := skel.get_bone_parent(bone)
	while p >= 0:
		t = skel.get_bone_rest(p) * t
		p = skel.get_bone_parent(p)
	return t


## A copy of `lib` whose tracks drive `skel` directly (paths "<track_root>:<target bone>";
## track_root defaults to the skeleton's node name).
static func bake_library(lib: AnimationLibrary, skel: Skeleton3D, alias: Dictionary[String, String] = {}, track_root: String = "") -> AnimationLibrary:
	var profile := SkeletonProfileHumanoid.new()
	var n := profile.bone_size
	var names: Array[String] = []
	var sparent: PackedInt32Array = PackedInt32Array()
	var ref_rot: Array[Quaternion] = []
	var gs: Array[Quaternion] = []          # source (profile) global rest rotation
	var gs_pos: Array[Vector3] = []
	for i: int in n:
		names.append(String(profile.get_bone_name(i)))
		sparent.append(profile.find_bone(profile.get_bone_parent(i)))
		var ref := profile.get_reference_pose(i)
		var q := ref.basis.get_rotation_quaternion()
		ref_rot.append(q)
		if sparent[i] >= 0:
			gs.append((gs[sparent[i]] * q).normalized())
			gs_pos.append(gs_pos[sparent[i]] + gs[sparent[i]] * ref.origin)
		else:
			gs.append(q)
			gs_pos.append(ref.origin)
	# Target side: bone index, global rest, straightening rotation A.
	var tbone: PackedInt32Array = PackedInt32Array()
	var gt: Array[Quaternion] = []
	var a_fix: Array[Quaternion] = []
	for i: int in n:
		var tn: String = alias.get(names[i], names[i])
		var b := skel.find_bone(tn)
		tbone.append(b)
		gt.append(_global_rest(skel, b).basis.get_rotation_quaternion() if b >= 0 else Quaternion.IDENTITY)
		a_fix.append(Quaternion.IDENTITY)
	for i: int in n:
		if tbone[i] < 0 or not DIRECTION_CHILD.has(names[i]):
			continue
		var ci := names.find(DIRECTION_CHILD[names[i]])
		if ci < 0 or tbone[ci] < 0:
			continue
		var want := (gs_pos[ci] - gs_pos[i]).normalized()
		var have := (_global_rest(skel, tbone[ci]).origin - _global_rest(skel, tbone[i]).origin).normalized()
		if want.length_squared() > 0.5 and have.length_squared() > 0.5 and have.dot(want) < 0.9986 and have.dot(want) > -0.99:
			a_fix[i] = Quaternion(have, want)
	# Nearest mapped profile ancestor of each mapped bone; the target bone's actual parent then poses
	# as D(anc) * A(anc) * Grest(actual parent).
	var anc: PackedInt32Array = PackedInt32Array()
	var gt_parent: Array[Quaternion] = []
	for i: int in n:
		var a := sparent[i]
		while a >= 0 and tbone[a] < 0:
			a = sparent[a]
		anc.append(a)
		var pb := skel.get_bone_parent(tbone[i]) if tbone[i] >= 0 else -1
		gt_parent.append(_global_rest(skel, pb).basis.get_rotation_quaternion() if pb >= 0 else Quaternion.IDENTITY)
	var hips_i := names.find("Hips")
	var hip_scale := 1.0
	var hips_parent_inv := Transform3D.IDENTITY
	if hips_i >= 0 and tbone[hips_i] >= 0:
		hip_scale = _global_rest(skel, tbone[hips_i]).origin.y / PROFILE_HIP_HEIGHT
		var hp := skel.get_bone_parent(tbone[hips_i])
		if hp >= 0:
			hips_parent_inv = _global_rest(skel, hp).affine_inverse()
	var prefix := track_root if not track_root.is_empty() else String(skel.name)
	var out := AnimationLibrary.new()
	var gpose: Array[Quaternion] = []
	gpose.resize(n)
	var dq: Array[Quaternion] = []
	dq.resize(n)
	for clip: StringName in lib.get_animation_list():
		var src := lib.get_animation(clip)
		var dst := Animation.new()
		dst.length = src.length
		dst.loop_mode = src.loop_mode
		for m: StringName in src.get_meta_list():
			dst.set_meta(m, src.get_meta(m))
		var strack: PackedInt32Array = PackedInt32Array()
		strack.resize(n)
		strack.fill(-1)
		var pos_track := -1
		var key_track := -1
		for t: int in src.get_track_count():
			var path := src.track_get_path(t)
			if path.get_subname_count() == 0:
				continue
			var bi := names.find(String(path.get_subname(0)))
			if bi < 0:
				continue
			if src.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				strack[bi] = t
				if key_track < 0:
					key_track = t
			elif src.track_get_type(t) == Animation.TYPE_POSITION_3D and bi == hips_i:
				pos_track = t
		if key_track < 0:
			continue
		var dtrack: PackedInt32Array = PackedInt32Array()
		dtrack.resize(n)
		dtrack.fill(-1)
		for i: int in n:
			if tbone[i] >= 0 and strack[i] >= 0:
				var t := dst.add_track(Animation.TYPE_ROTATION_3D)
				dst.track_set_path(t, NodePath(prefix + ":" + skel.get_bone_name(tbone[i])))
				dtrack[i] = t
		var dpos := -1
		if pos_track >= 0 and tbone[hips_i] >= 0:
			dpos = dst.add_track(Animation.TYPE_POSITION_3D)
			dst.track_set_path(dpos, NodePath(prefix + ":" + skel.get_bone_name(tbone[hips_i])))
		for k: int in src.track_get_key_count(key_track):
			var time := src.track_get_key_time(key_track, k)
			for i: int in n:
				var loc := ref_rot[i]
				if strack[i] >= 0:
					loc = src.rotation_track_interpolate(strack[i], time)
				var q := loc if sparent[i] < 0 else (gpose[sparent[i]] * loc).normalized()
				gpose[i] = q
				dq[i] = (q * gs[i].inverse()).normalized()
			for i: int in n:
				if dtrack[i] < 0:
					continue
				var g := dq[i] * a_fix[i] * gt[i]
				var parent_pose := gt_parent[i]
				if anc[i] >= 0:
					parent_pose = dq[anc[i]] * a_fix[anc[i]] * gt_parent[i]
				dst.rotation_track_insert_key(dtrack[i], time, (parent_pose.inverse() * g).normalized())
			if dpos >= 0:
				var p := src.position_track_interpolate(pos_track, time) * hip_scale
				dst.position_track_insert_key(dpos, time, hips_parent_inv * p)
		out.add_animation(clip, dst)
	for m: StringName in lib.get_meta_list():
		out.set_meta(m, lib.get_meta(m))
	return out
