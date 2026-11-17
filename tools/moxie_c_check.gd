extends SceneTree
## Godot-side acceptance check for Moxie candidate C.
##   bash tools/gd script res://tools/moxie_c_check.gd            headless: report only
##   bash tools/gd shot   res://tools/moxie_c_check.gd -- [dir]   windowed: report + screenshots
## Reports whether the skeleton satisfies SkeletonProfileHumanoid (every profile bone present, same
## parent, rest orientation matching Godot's reference pose), the model's size / facing / materials,
## and every clip of res://assets/anim/candidates/c/moxie_anims.res. Windowed, it plays each clip on
## the model re-materialed with the project's toon shader at the game camera and saves PNGs.

const GLB := "res://assets/models/candidates/c/moxie.glb"
const LIB := "res://assets/anim/candidates/c/moxie_anims.res"
const CLIPS: Array[String] = ["idle", "run", "stopped", "light", "heavy", "dodge", "ranged", "interact", "death"]
const FRACTIONS: Array[float] = [0.1, 0.45, 0.8]

var _out := "res://art/previews/moxie_c/godot"
var _model: Node3D = null
var _player: AnimationPlayer = null
var _camera: Camera3D = null
var _jobs: Array = []
var _wait := 0
var _current: Array = []
var _ok := true


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("-"):
			_out = a
	var packed := load(GLB) as PackedScene
	if packed == null:
		push_error("cannot load " + GLB)
		quit(1)
		return
	_model = packed.instantiate() as Node3D
	_report_skeleton()
	_report_model()
	_report_clips()
	print("RESULT ", "OK" if _ok else "FAIL")
	if DisplayServer.get_name() == "headless":
		quit(0 if _ok else 1)
		return
	_build_stage()


func _fail(msg: String) -> void:
	_ok = false
	print("FAIL: ", msg)


func _skeleton() -> Skeleton3D:
	var skels := _model.find_children("*", "Skeleton3D", true, false)
	return skels[0] as Skeleton3D if skels.size() > 0 else null


func _report_skeleton() -> void:
	var skel := _skeleton()
	if skel == null:
		_fail("no Skeleton3D")
		return
	print("skeleton node path: ", _model.get_path_to(skel), "  bones: ", skel.get_bone_count())
	var profile := SkeletonProfileHumanoid.new()
	var bone_map := BoneMap.new()
	bone_map.profile = profile
	var missing: PackedStringArray = []
	var wrong_parent: PackedStringArray = []
	var worst_angle := 0.0
	var worst_bone := ""
	var mapped := 0
	var ref_global := {}
	for i in profile.bone_size:
		var pname := profile.get_bone_name(i)
		var pparent := profile.get_bone_parent(i)
		var local := profile.get_reference_pose(i)
		ref_global[pname] = (ref_global[pparent] * local) if ref_global.has(pparent) else local
		var idx := skel.find_bone(pname)
		if idx < 0:
			if profile.is_required(i) or not (String(pname) in ["Root", "Jaw", "LeftEye", "RightEye"]):
				missing.append(pname)
			continue
		bone_map.set_skeleton_bone_name(pname, pname)
		mapped += 1
		# the nearest ancestor that is a profile bone must be the profile's parent
		var p := skel.get_bone_parent(idx)
		var want := String(pparent)
		if want == "Root":
			want = ""
		var got := skel.get_bone_name(p) if p >= 0 else ""
		if got != want:
			wrong_parent.append("%s (parent %s, profile wants %s)" % [pname, got, want])
		var rest_g := skel.get_bone_global_rest(idx).basis.orthonormalized()
		var ref_b: Basis = (ref_global[pname] as Transform3D).basis.orthonormalized()
		var ang := rad_to_deg((rest_g.inverse() * ref_b).get_rotation_quaternion().get_angle())
		if ang > worst_angle:
			worst_angle = ang
			worst_bone = pname
	print("humanoid profile bones mapped: %d of %d (optional Root/Jaw/eyes not modelled as bones)" % [mapped, profile.bone_size])
	if not missing.is_empty():
		_fail("profile bones missing: " + ", ".join(missing))
	if not wrong_parent.is_empty():
		_fail("hierarchy differs: " + "; ".join(wrong_parent))
	print("rest orientation vs Godot reference pose: worst %.2f deg (%s)" % [worst_angle, worst_bone])
	var extra: PackedStringArray = []
	for b in skel.get_bone_count():
		if profile.find_bone(skel.get_bone_name(b)) < 0:
			extra.append(skel.get_bone_name(b))
	print("secondary bones (%d): %s" % [extra.size(), ", ".join(extra)])
	for n: String in ["RightHand", "LeftLowerArm"]:
		if skel.find_bone(n) < 0:
			_fail("attachment bone missing: " + n)
	var parent3d := skel.get_parent() as Node3D
	print("armature node '%s' transform is identity: %s" % [parent3d.name, parent3d.transform.is_equal_approx(Transform3D.IDENTITY)])


func _report_model() -> void:
	var aabb := AABB()
	var first := true
	var tris := 0
	var mats: PackedStringArray = []
	for n: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var box := mi.global_transform * mi.get_aabb() if mi.is_inside_tree() else mi.transform * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3
			var m := mi.mesh.surface_get_material(s)
			mats.append(m.resource_name if m else "<none>")
	print("mesh AABB pos %s size %s  (height %.3f)  triangles %d" % [aabb.position, aabb.size, aabb.size.y, tris])
	print("surfaces (%d): %s" % [mats.size(), ", ".join(mats)])
	if absf(aabb.position.y) > 0.02:
		_fail("feet are not on y = 0")
	var skel := _skeleton()
	if skel != null:
		var toe := skel.get_bone_global_rest(skel.find_bone("LeftToes")).origin
		var heel := skel.get_bone_global_rest(skel.find_bone("LeftFoot")).origin
		print("faces +Z: ", toe.z > heel.z, "   left side is +X: ", skel.get_bone_global_rest(skel.find_bone("LeftHand")).origin.x > 0.0)
		if toe.z <= heel.z:
			_fail("model does not face +Z")


func _report_clips() -> void:
	if not ResourceLoader.exists(LIB):
		_fail("animation library missing: " + LIB)
		return
	var lib := load(LIB) as AnimationLibrary
	var skel := _skeleton()
	for clip in CLIPS:
		if not lib.has_animation(clip):
			_fail("clip missing: " + clip)
			continue
		var a := lib.get_animation(clip)
		var unresolved := 0
		for t in a.get_track_count():
			var path := a.track_get_path(t)
			var node := _model.get_node_or_null(NodePath(String(path).get_slice(":", 0)))
			if node == null or skel.find_bone(String(path).get_slice(":", 1)) < 0:
				unresolved += 1
		print("clip %-9s length %.3f loop %d tracks %d unresolved %d" % [clip, a.length, a.loop_mode, a.get_track_count(), unresolved])
		var looping := clip in ["idle", "run", "stopped"]
		if looping != (a.loop_mode != Animation.LOOP_NONE):
			_fail(clip + ": wrong loop mode")
		if not looping and absf(a.length - 1.0) > 0.0005:
			_fail(clip + ": one-shot is not exactly 1.0 s")
		if unresolved > 0:
			_fail(clip + ": tracks do not resolve on the model")


# ───────────────────────────── windowed: screenshots ─────────────────────────────

func _build_stage() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var scene := Node3D.new()
	root.add_child(scene)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#8d8fa0")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b0a8c8")
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-58.0), deg_to_rad(-35.0), 0)
	scene.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	floor_mi.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#6f7082")
	floor_mi.material_override = fm
	scene.add_child(floor_mi)
	scene.add_child(_model)
	if ResourceLoader.exists("res://shaders/toon.gdshader"):
		ToonKit.apply_toon(_model)
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		_player = AnimationPlayer.new()
		_model.add_child(_player)
	else:
		_player = players[0] as AnimationPlayer
	if ResourceLoader.exists(LIB) and not _player.has_animation_library("c"):
		_player.add_animation_library("c", load(LIB) as AnimationLibrary)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	scene.add_child(_camera)
	_jobs.append(["tpose", "", 0.0, 2.6, Vector3(0, 0.85, 0)])
	_jobs.append(["closeup", "c/idle", 0.3, 0.95, Vector3(0, 1.45, 0)])
	for clip in CLIPS:
		for f in FRACTIONS:
			_jobs.append(["%s_%02d" % [clip, int(f * 100)], "c/" + clip, f, 2.9, Vector3(0, 0.8, 0)])


func _aim(size: float, target: Vector3) -> void:
	var yaw := deg_to_rad(45.0)
	var pitch := deg_to_rad(35.0)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	_camera.size = size
	_camera.position = target + dir * 12.0
	_camera.look_at(target, Vector3.UP)


func _process(_delta: float) -> bool:
	if _camera == null:
		return false
	if _current.is_empty():
		if _jobs.is_empty():
			print("[moxie_c_check] screenshots in ", _out)
			quit(0 if _ok else 1)
			return true
		_current = _jobs.pop_front()
		var clip: String = _current[1]
		if clip == "":
			_player.stop()
			var skel := _skeleton()
			skel.reset_bone_poses()
		elif _player.has_animation(clip):
			_player.play(clip)
			_player.seek(_player.get_animation(clip).length * float(_current[2]), true)
			_player.pause()
		_aim(_current[3], _current[4])
		_wait = 0
		return false
	_wait += 1
	if _wait < 4:
		return false
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(_out).path_join("%s.png" % _current[0]))
	_current = []
	return false
