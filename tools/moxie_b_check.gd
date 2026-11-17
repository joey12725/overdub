extends SceneTree
## Candidate-B Moxie check:  bash tools/gd shot res://tools/moxie_b_check.gd [-- out_dir]
## (also runs headless with `gd script`, then it only prints the report and skips screenshots)
##
## 1. loads res://assets/models/candidates/b/moxie.glb and reports size, facing, triangle count
## 2. checks the skeleton against Godot's SkeletonProfileHumanoid: every profile bone (required or
##    not, except the optional eyes/jaw) must exist with the profile's parent, and a BoneMap that
##    maps each profile bone to the same-named skeleton bone must be complete; rest pose must be a T-pose
## 3. loads res://assets/anim/candidates/b/moxie_anims.res, checks the clip contract, plays every
##    clip and saves screenshots with the project's toon shader (ToonKit) at the game's isometric camera

const GLB := "res://assets/models/candidates/b/moxie.glb"
const LIB := "res://assets/anim/candidates/b/moxie_anims.res"
const CLIPS: Array[String] = ["idle", "run", "stopped", "light", "heavy", "dodge", "ranged", "interact", "death"]
const LOOPS: Array[String] = ["idle", "run", "stopped"]
const OPTIONAL: Array[String] = ["LeftEye", "RightEye", "Jaw"]

var _out := "res://art/previews/moxie_b"
var _model: Node3D
var _player: AnimationPlayer
var _jobs: Array = []
var _wait := 0
var _ok := true
var _headless := false


func _fail(msg: String) -> void:
	_ok = false
	print("[moxie_b_check] FAIL: ", msg)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("-"):
			_out = a
	_headless = DisplayServer.get_name() == "headless"
	var scene := load(GLB) as PackedScene
	if scene == null:
		_fail("cannot load " + GLB)
		quit(1)
		return
	_model = scene.instantiate() as Node3D
	root.add_child(_model)
	var skel := _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	print("[moxie_b_check] skeleton node '%s' under '%s', %d bones" % [skel.name, skel.get_parent().name, skel.get_bone_count()])
	if not skel.get_parent().name == "Rig" and skel.name != "Rig":
		_fail("armature node is not named Rig")
	if not skel.global_transform.is_equal_approx(Transform3D.IDENTITY):
		_fail("skeleton has a non-identity transform: " + str(skel.global_transform))

	# ---- humanoid profile
	var profile := SkeletonProfileHumanoid.new()
	var bone_map := BoneMap.new()
	bone_map.profile = profile
	var missing: Array[String] = []
	var wrong_parent: Array[String] = []
	var mapped := 0
	for i in range(profile.bone_size):
		var bn := String(profile.get_bone_name(i))
		var idx := skel.find_bone(bn)
		if idx < 0:
			if not OPTIONAL.has(bn):
				missing.append(bn)
			continue
		bone_map.set_skeleton_bone_name(bn, bn)
		mapped += 1
		var want_parent := String(profile.get_bone_parent(i))
		var have_parent := skel.get_bone_name(skel.get_bone_parent(idx)) if skel.get_bone_parent(idx) >= 0 else ""
		if want_parent != have_parent:
			wrong_parent.append("%s (profile parent %s, skeleton parent %s)" % [bn, want_parent, have_parent])
	var required_missing: Array[String] = []
	for i in range(profile.bone_size):
		var bn := String(profile.get_bone_name(i))
		if profile.is_required(i) and bone_map.get_skeleton_bone_name(bn) == &"":
			required_missing.append(bn)
	print("[moxie_b_check] humanoid profile: %d/%d profile bones mapped by name (optional eyes/jaw not modelled)" % [mapped, profile.bone_size])
	if not missing.is_empty():
		_fail("profile bones missing: " + str(missing))
	if not required_missing.is_empty():
		_fail("REQUIRED profile bones unmapped: " + str(required_missing))
	if not wrong_parent.is_empty():
		_fail("hierarchy differs from the profile: " + str(wrong_parent))
	var extras: Array[String] = []
	for b in range(skel.get_bone_count()):
		if profile.find_bone(skel.get_bone_name(b)) < 0:
			extras.append(skel.get_bone_name(b))
	print("[moxie_b_check] secondary (non-profile) bones: ", extras)

	# ---- T-pose
	var dirs := {"LeftUpperArm": Vector3(1, 0, 0), "LeftLowerArm": Vector3(1, 0, 0), "RightUpperArm": Vector3(-1, 0, 0), "RightLowerArm": Vector3(-1, 0, 0),
		"LeftUpperLeg": Vector3(0, -1, 0), "RightUpperLeg": Vector3(0, -1, 0), "LeftLowerLeg": Vector3(0, -1, 0), "Spine": Vector3(0, 1, 0)}
	for bn: String in dirs:
		var idx := skel.find_bone(bn)
		var child := -1
		for c in skel.get_bone_children(idx):
			if profile.find_bone(skel.get_bone_name(c)) >= 0:
				child = c
				break
		var d: Vector3 = (skel.get_bone_global_rest(child).origin - skel.get_bone_global_rest(idx).origin).normalized()
		var dotv := d.dot(dirs[bn])
		if dotv < 0.97:
			_fail("rest pose: %s points %s (dot %.3f with the T-pose direction)" % [bn, str(d), dotv])
	# facing +Z: toes are in front of the ankles; left side is +X
	var fwd := skel.get_bone_global_rest(skel.find_bone("LeftToes")).origin - skel.get_bone_global_rest(skel.find_bone("LeftFoot")).origin
	if fwd.z <= 0.0:
		_fail("model does not face +Z")
	if skel.get_bone_global_rest(skel.find_bone("LeftHand")).origin.x <= 0.0:
		_fail("left hand is not on +X")
	if skel.get_bone_global_rest(skel.find_bone("Root")).origin.length() > 0.001:
		_fail("Root is not at the origin")

	# ---- mesh stats
	var tris := 0
	var box := AABB()
	var first := true
	var mat_names: Array[String] = []
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(s)
			var idxs: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += idxs.size() / 3
			var m := mi.mesh.surface_get_material(s)
			if m != null:
				mat_names.append(m.resource_name)
		var b := mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	print("[moxie_b_check] triangles %d, surfaces/materials %d, AABB %s" % [tris, mat_names.size(), str(box)])
	print("[moxie_b_check] materials: ", mat_names)
	if absf(box.position.y) > 0.02:
		_fail("feet are not on the floor (min y %.3f)" % box.position.y)
	if box.end.y < 1.5 or box.end.y > 1.9:
		_fail("unexpected height %.3f" % box.end.y)

	# ---- animation library
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	_player = players[0] as AnimationPlayer if players.size() > 0 else null
	if _player == null:
		_player = AnimationPlayer.new()
		_model.add_child(_player)
	var lib := load(LIB) as AnimationLibrary
	if lib == null:
		_fail("cannot load " + LIB)
	else:
		if _player.has_animation_library("lib"):
			_player.remove_animation_library("lib")
		_player.add_animation_library("lib", lib)
		for clip in CLIPS:
			if not lib.has_animation(clip):
				_fail("library lacks clip " + clip)
				continue
			var a := lib.get_animation(clip)
			var bad_tracks := 0
			for t in range(a.get_track_count()):
				var node := _player.get_node_or_null(String(_player.root_node) + "/" + String(a.track_get_path(t).get_concatenated_names()))
				var bone := a.track_get_path(t).get_concatenated_subnames()
				if not (node is Skeleton3D) or (node as Skeleton3D).find_bone(bone) < 0 or profile.find_bone(bone) < 0:
					bad_tracks += 1
			var looped := a.loop_mode != Animation.LOOP_NONE
			print("[moxie_b_check] clip %-8s length %.3f s  loop %s  tracks %d  unresolved/non-profile tracks %d" % [clip, a.length, str(looped), a.get_track_count(), bad_tracks])
			if bad_tracks > 0:
				_fail("clip %s has tracks that do not resolve to profile bones" % clip)
			if LOOPS.has(clip) != looped:
				_fail("clip %s loop flag is wrong" % clip)
			if not LOOPS.has(clip) and absf(a.length - 1.0) > 0.0005:
				_fail("one-shot %s is %.4f s, not 1.0" % [clip, a.length])
	if _headless:
		print("[moxie_b_check] headless: skipping screenshots. RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	_setup_stage()
	_jobs.append(["rest", "", 0.0, 3.0, Vector3(0, 0.85, 0)])
	_jobs.append(["face", "", 0.0, 0.62, Vector3(0, 1.47, 0)])
	for clip in CLIPS:
		for f in [0.25, 0.5, 0.75]:
			_jobs.append(["%s_%02d" % [clip, int(f * 100)], clip, f, 3.0, Vector3(0, 0.85, 0)])


var _cam: Camera3D


func _setup_stage() -> void:
	root.size = Vector2i(900, 900)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#cfc7b8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8f86a8")
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 150, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#b9b0a0")
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 3.0
	_cam.near = 0.05
	_cam.far = 60.0
	root.add_child(_cam)
	_cam.current = true
	if ResourceLoader.exists("res://shaders/toon.gdshader"):
		var made := ToonKit.apply_toon(_model)
		print("[moxie_b_check] ToonKit.apply_toon -> %d toon materials" % made.size())
	else:
		print("[moxie_b_check] shaders/toon.gdshader not found: screenshots use the imported materials")


func _aim(target: Vector3, size: float) -> void:
	# The game's camera: orthographic, yaw 45 deg, pitch 35 deg. The model faces +Z, so the camera
	# sits in front-right of her.
	var yaw := deg_to_rad(45.0)
	var pitch := deg_to_rad(35.0)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	_cam.size = size
	_cam.look_at_from_position(target + dir * 12.0, target, Vector3.UP)


func _process(_delta: float) -> bool:
	if _headless:
		return true
	if _jobs.is_empty():
		print("[moxie_b_check] RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return true
	var job: Array = _jobs[0]
	if _wait == 0:
		_aim(job[4], job[3])
		if job[1] != "":
			var a := _player.get_animation("lib/" + String(job[1]))
			_player.play("lib/" + String(job[1]))
			_player.seek(a.length * float(job[2]), true)
			_player.pause()
		else:
			_player.stop()
	_wait += 1
	if _wait < 6:
		return false
	var img := root.get_texture().get_image()
	var dir_abs := ProjectSettings.globalize_path(_out) if _out.begins_with("res://") else _out
	DirAccess.make_dir_recursive_absolute(dir_abs.path_join("godot"))
	var path := dir_abs.path_join("godot").path_join("%s.png" % job[0])
	img.save_png(path)
	print("[moxie_b_check] saved ", path)
	_jobs.pop_front()
	_wait = 0
	return false
