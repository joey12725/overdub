extends SceneTree
## Check of the Moxie candidate E model (art/moxie_e; check script adapted from candidate A so the candidates are judged alike):
##   bash tools/gd script res://tools/moxie_e_check.gd          report only (headless)
##   bash tools/gd shot   res://tools/moxie_e_check.gd          report + screenshots (needs a GPU)
## Report: scale / origin / facing, triangle count, materials (tint hooks, *_glow), whether every
## bone of Godot's SkeletonProfileHumanoid maps onto the skeleton by name (required ones must),
## whether the hierarchy and the rest orientations match the profile's reference pose (so a library
## retargeted to the humanoid profile plays without any rest fixing), and the animation library
## contract (names, loops, 1.0 s one-shots). Screenshots: the model with ToonKit's toon + outline
## materials at the game's isometric camera (orthographic, yaw 45, pitch 35), every library clip
## as a strip, written to art/previews/moxie_e/godot/.

const GLB := "res://assets/models/candidates/e/moxie.glb"
const LIB := "res://assets/anim/candidates/e/moxie_anims.res"
const OUT := "res://art/previews/moxie_e/godot/"
const LOOPS := ["idle", "run", "stopped"]
const ONE_SHOTS := ["light", "heavy", "dodge", "ranged", "interact", "death"]
const CELL := Vector2i(360, 480)
const STRIP := 6

var _vp: SubViewport
var _cam: Camera3D
var _model: Node3D
var _player: AnimationPlayer
var _jobs: Array = []
var _wait: int = 0
var _strip: Image = null
var _ok: bool = true


func _initialize() -> void:
	var packed := load(GLB) as PackedScene
	if packed == null:
		push_error("cannot load " + GLB)
		quit(1)
		return
	_model = packed.instantiate() as Node3D
	_ok = _report(_model)
	print("RESULT ", "OK" if _ok else "FAIL")
	if DisplayServer.get_name() == "headless":
		quit(0 if _ok else 1)
		return
	_build_stage()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_jobs.append({"kind": "still", "file": "toon_iso.png", "clip": "idle", "t": 0.0, "size": 2.1})
	_jobs.append({"kind": "still", "file": "toon_iso_close.png", "clip": "idle", "t": 0.0, "size": 0.9, "y": 1.3})
	_jobs.append({"kind": "still", "file": "toon_front.png", "clip": "", "t": 0.0, "size": 2.1, "yaw": 0.0, "pitch": 5.0})
	_jobs.append({"kind": "still", "file": "toon_face.png", "clip": "", "t": 0.0, "size": 0.62, "yaw": 22.0, "pitch": 6.0, "y": 1.42})
	_jobs.append({"kind": "still", "file": "toon_back.png", "clip": "", "t": 0.0, "size": 2.1, "yaw": 180.0, "pitch": 5.0})
	_jobs.append({"kind": "still", "file": "toon_iso_rest.png", "clip": "", "t": 0.0, "size": 2.1})
	_jobs.append({"kind": "still", "file": "toon_iso_run.png", "clip": "run", "t": 0.25, "size": 2.1})
	for c: String in LOOPS + ONE_SHOTS:
		for i in STRIP:
			_jobs.append({"kind": "strip", "file": "clip_%s.png" % c, "clip": c, "i": i})


func _report(root: Node3D) -> bool:
	var ok := true
	var skels := root.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		print("FAIL no Skeleton3D")
		return false
	var skel := skels[0] as Skeleton3D
	print("skeleton node '%s' parent '%s' bones %d" % [skel.name, skel.get_parent().name, skel.get_bone_count()])
	var p := skel.get_parent()
	while p != null and p != root.get_parent():
		if p is Node3D and not (p as Node3D).transform.is_equal_approx(Transform3D.IDENTITY):
			print("FAIL transform baked on node ", p.name, " ", (p as Node3D).transform)
			ok = false
		p = p.get_parent()
	# ---- humanoid profile mapping
	var profile := SkeletonProfileHumanoid.new()
	var bone_map := BoneMap.new()
	bone_map.profile = profile
	var missing_req: PackedStringArray = []
	var missing_opt: PackedStringArray = []
	var bad_parent: PackedStringArray = []
	var worst := 0.0
	var worst_name := ""
	for i in profile.bone_size:
		var bn := profile.get_bone_name(i)
		var si := skel.find_bone(bn)
		if si < 0:
			if profile.is_required(i):
				missing_req.append(bn)
			else:
				missing_opt.append(bn)
			continue
		bone_map.set_skeleton_bone_name(bn, bn)
		# hierarchy: nearest ancestor that is a profile bone must be the profile parent
		var want := profile.get_bone_parent(i)
		var a := skel.get_bone_parent(si)
		while a >= 0 and profile.find_bone(skel.get_bone_name(a)) < 0:
			a = skel.get_bone_parent(a)
		var got := StringName("") if a < 0 else StringName(skel.get_bone_name(a))
		if want != got and not (want == &"Root" and got == &""):
			# a missing optional parent (e.g. Jaw) cannot happen here; report anything else
			bad_parent.append("%s (parent %s, profile %s)" % [bn, got, want])
		# rest orientation vs the profile's reference pose (global)
		var ref := Basis.IDENTITY
		var j := i
		var chain: Array[Basis] = []
		while j >= 0:
			chain.append(profile.get_reference_pose(j).basis)
			j = profile.find_bone(profile.get_bone_parent(j))
		for k in range(chain.size() - 1, -1, -1):
			ref = ref * chain[k]
		var g := skel.get_bone_global_rest(si).basis.orthonormalized()
		var ang := rad_to_deg((g.inverse() * ref).get_rotation_quaternion().get_angle())
		if ang > worst:
			worst = ang
			worst_name = bn
	print("humanoid profile: %d bones, mapped %d, missing required: %s, missing optional: %s" % [
		profile.bone_size, profile.bone_size - missing_req.size() - missing_opt.size(), missing_req, missing_opt])
	print("hierarchy mismatches: ", bad_parent)
	print("rest orientation vs profile reference pose: worst %.3f deg (%s)" % [worst, worst_name])
	if not missing_req.is_empty() or not bad_parent.is_empty() or worst > 1.0:
		ok = false
	var extra: PackedStringArray = []
	for i in skel.get_bone_count():
		if profile.find_bone(skel.get_bone_name(i)) < 0:
			extra.append(skel.get_bone_name(i))
	print("extra (secondary) bones: ", extra)
	# T-pose: arms along X, legs down
	var lu := skel.get_bone_global_rest(skel.find_bone("LeftUpperArm")).origin
	var lh := skel.get_bone_global_rest(skel.find_bone("LeftHand")).origin
	var ll := skel.get_bone_global_rest(skel.find_bone("LeftUpperLeg")).origin
	var lf := skel.get_bone_global_rest(skel.find_bone("LeftFoot")).origin
	print("T-pose: left arm dir %s, left leg dir %s (left is +X: %s)" % [(lh - lu).normalized(), (lf - ll).normalized(), lu.x > 0])
	# ---- meshes
	var tris := 0
	var box := AABB()
	var first := true
	var mats: Dictionary = {}
	var shapes := 0
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var m := mi.mesh.surface_get_material(s)
			mats[m.resource_name if m else "<none>"] = true
		shapes += mi.mesh.get_blend_shape_count()
		var b := mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	print("triangles %d, blend shapes %d, bounds min %s max %s (height %.3f)" % [tris, shapes, box.position, box.end, box.end.y])
	var names := mats.keys()
	names.sort()
	print("materials (%d): %s" % [names.size(), names])
	var hooks: PackedStringArray = []
	for n2: String in names:
		if n2.ends_with("_glow") or n2 in ["top", "pants", "shoes"]:
			hooks.append(n2)
	print("styling hooks present: ", hooks)
	if box.end.y < 1.5 or box.end.y > 1.85 or absf(box.position.y) > 0.02:
		print("FAIL size / origin")
		ok = false
	# facing +Z: the toes are in front of the ankles
	var toe := skel.get_bone_global_rest(skel.find_bone("LeftToes")).origin
	print("faces +Z: ", toe.z > lf.z)
	ok = ok and toe.z > lf.z
	# ---- animation library
	if ResourceLoader.exists(LIB):
		var lib := load(LIB) as AnimationLibrary
		for c: String in LOOPS + ONE_SHOTS:
			if not lib.has_animation(c):
				print("FAIL missing clip ", c)
				ok = false
				continue
			var a := lib.get_animation(c)
			var bound := 0
			for t in a.get_track_count():
				if skel.find_bone(String(a.track_get_path(t).get_subname(0))) >= 0:
					bound += 1
			var good := (a.loop_mode != Animation.LOOP_NONE) == LOOPS.has(c) and (LOOPS.has(c) or is_equal_approx(a.length, 1.0)) and bound == a.get_track_count()
			print("clip %-9s length %.3f loop %s tracks %d bound %d %s" % [c, a.length, a.loop_mode != Animation.LOOP_NONE, a.get_track_count(), bound, "" if good else "FAIL"])
			ok = ok and good
	else:
		print("FAIL no animation library at ", LIB)
		ok = false
	return ok


func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.size = CELL
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(_vp)
	var world := Node3D.new()
	_vp.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.80, 0.78, 0.74)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.72, 0.85)
	env.environment.ambient_light_energy = 0.6
	env.environment.glow_enabled = true
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 20, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = false
	world.add_child(sun)
	world.add_child(_model)
	if ResourceLoader.exists("res://shaders/toon.gdshader") and ClassDB.class_exists("RefCounted"):
		ToonKit.apply_toon(_model)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.62, 0.60, 0.57)
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor.material_override = fm
	world.add_child(floor)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(_cam)
	_cam.current = true
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	_player = players[0] as AnimationPlayer if not players.is_empty() else null
	if _player == null:
		_player = AnimationPlayer.new()
		_model.add_child(_player)
	_player.add_animation_library("mx", load(LIB) as AnimationLibrary)


func _aim(yaw: float, pitch: float, size: float, y: float) -> void:
	var d := Vector3(sin(deg_to_rad(yaw)) * cos(deg_to_rad(pitch)), sin(deg_to_rad(pitch)), cos(deg_to_rad(yaw)) * cos(deg_to_rad(pitch)))
	var target := Vector3(0, y, 0)
	_cam.size = size
	_cam.look_at_from_position(target + d * 10.0, target, Vector3.UP)


func _process(_delta: float) -> bool:
	if _vp == null:
		return true
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_capture(_jobs.pop_front())
		return false
	if _jobs.is_empty():
		print("screenshots in ", ProjectSettings.globalize_path(OUT))
		quit(0 if _ok else 1)
		return true
	var job: Dictionary = _jobs[0]
	var clip: String = job["clip"]
	if clip == "":
		_player.stop()
		var sk := _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		sk.reset_bone_poses()
	else:
		var a := _player.get_animation("mx/" + clip)
		var t: float = job.get("t", 0.0)
		if job["kind"] == "strip":
			var i: int = job["i"]
			t = a.length * float(i) / float(STRIP - (0 if LOOPS.has(clip) else 1))
		_player.play("mx/" + clip)
		_player.seek(minf(t, a.length - 0.0001), true)
		_player.pause()
	_aim(job.get("yaw", 45.0), job.get("pitch", 35.0), job.get("size", 2.4), job.get("y", 0.85))
	_wait = 4
	return false


func _capture(job: Dictionary) -> void:
	var img := _vp.get_texture().get_image()
	if job["kind"] == "still":
		img.save_png(OUT + job["file"])
		return
	var i: int = job["i"]
	if i == 0:
		_strip = Image.create(CELL.x * STRIP, CELL.y, false, img.get_format())
	_strip.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * i, 0))
	if i == STRIP - 1:
		_strip.save_png(OUT + job["file"])
