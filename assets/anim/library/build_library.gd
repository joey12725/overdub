extends SceneTree
## Builds res://assets/anim/library/moxie_anims.res (the shipped humanoid AnimationLibrary) from
## art/anim/baked/moxie_clips.json (written by `python -I art/anim/bake.py`).
##
##     bash tools/gd script res://assets/anim/library/build_library.gd
##
## The JSON holds, per frame and bone, the model-space DELTA rotation from the T-pose. Here each is
## turned into a local rotation in Godot's SkeletonProfileHumanoid REFERENCE pose space (the space
## Godot's own retargeting normalises every humanoid import to), on tracks "Rig:<Bone>". Hips also
## get a position track in profile scale (hips rest height 0.75; Skeleton3D.motion_scale applies).
## A model whose rest axes are not the profile's (a raw Blender export) is served by
## FeelRetarget.bake_library(), which converts this library to that skeleton once at load.
##
## Each Animation also carries metadata for the feel layer (FeelRig reads it):
##   od_grip / od_w / od_e : PackedVector3Array per frame — the weapon hand's grip position, weapon
##                           direction (+Y of the weapon) and edge direction (+Z), model space,
##                           metres on the 1.6-unit reference body (od_hip_height = hips rest height)
##   od_lgrip              : the left palm position per frame
##   od_style, od_melee    : "blade" | "shiv" | ... and "light" | "heavy" (melee clips)
##   od_fire               : clip fraction of the launch tick (ranged clips)

const SRC := "res://art/anim/baked/moxie_clips.json"
const OUT := "res://assets/anim/library/moxie_anims.res"
const PROFILE_HIP_HEIGHT := 0.75


func _init() -> void:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(SRC))
	if text.is_empty():
		push_error("build_library: cannot read " + SRC)
		quit(1)
		return
	var data: Dictionary = JSON.parse_string(text)
	var bones: Array = data["bones"]
	var parents: Array = data["parents"]
	var hip_h: float = data["hip_height"]
	var profile := SkeletonProfileHumanoid.new()
	# Global reference-pose rotation of every profile bone.
	var gref: Dictionary[String, Quaternion] = {}
	for i: int in profile.bone_size:
		var n := String(profile.get_bone_name(i))
		var q := profile.get_reference_pose(i).basis.get_rotation_quaternion()
		var p := String(profile.get_bone_parent(i))
		gref[n] = (gref[p] * q).normalized() if gref.has(p) else q
	var lib := AnimationLibrary.new()
	var total_tracks := 0
	for cd: Dictionary in data["clips"]:
		var anim := Animation.new()
		anim.length = cd["length"]
		anim.loop_mode = Animation.LOOP_LINEAR if cd["loop"] else Animation.LOOP_NONE
		var rot: Array = cd["rot"]
		var n := rot.size()
		var step: float = float(cd["length"]) / float(n - 1)
		var tracks: PackedInt32Array = PackedInt32Array()
		for b: int in bones.size():
			if not gref.has(bones[b]):
				tracks.append(-1)
				continue
			var t := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(t, NodePath("Rig:" + String(bones[b])))
			anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
			tracks.append(t)
		var tp := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(tp, NodePath("Rig:Hips"))
		var hips: Array = cd["hips"]
		var index_of: Dictionary[String, int] = {}
		for b: int in bones.size():
			index_of[bones[b]] = b
		for f: int in n:
			var time := minf(step * f, anim.length)
			var row: Array = rot[f]
			for b: int in bones.size():
				if tracks[b] < 0:
					continue
				var name: String = bones[b]
				var d := _q(row[b])
				var gp := (d * gref[name]).normalized()
				var local := gp
				var pn: String = parents[b]
				if not pn.is_empty():
					local = ((_q(row[index_of[pn]]) * gref[pn]).normalized().inverse() * gp).normalized()
				anim.rotation_track_insert_key(tracks[b], time, local)
			var h: Array = hips[f]
			anim.position_track_insert_key(tp, time, Vector3(h[0], h[1], h[2]) * (PROFILE_HIP_HEIGHT / hip_h))
		anim.set_meta(&"od_hip_height", hip_h)
		anim.set_meta(&"od_grip", _v3s(cd["grip"]))
		anim.set_meta(&"od_w", _v3s(cd["w"]))
		anim.set_meta(&"od_e", _v3s(cd["e"]))
		anim.set_meta(&"od_lgrip", _v3s(cd["lgrip"]))
		var meta: Dictionary = cd["meta"]
		if meta.has("style"):
			anim.set_meta(&"od_style", String(meta["style"]))
			anim.set_meta(&"od_melee", String(meta["melee"]))
		if meta.has("fire"):
			anim.set_meta(&"od_fire", float(meta["fire"]))
		total_tracks += anim.get_track_count()
		lib.add_animation(StringName(String(cd["name"])), anim)
	lib.set_meta(&"od_style_of_item", data["style_of_item"])
	lib.set_meta(&"od_two_handed", data["two_handed"])
	lib.set_meta(&"od_hip_height", hip_h)
	var err := ResourceSaver.save(lib, OUT, ResourceSaver.FLAG_COMPRESS)
	print("build_library: ", lib.get_animation_list().size(), " clips, ", total_tracks, " tracks -> ", OUT, " (", error_string(err), ")")
	quit(0 if err == OK else 1)


static func _q(a: Array) -> Quaternion:
	return Quaternion(a[0], a[1], a[2], a[3]).normalized()


static func _v3s(a: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(a.size())
	for i: int in a.size():
		var v: Array = a[i]
		out[i] = Vector3(v[0], v[1], v[2])
	return out
