extends SceneTree
## Wardrobe preview at the game's isometric angle (windowed; needs a GPU):
##   bash tools/gd shot res://art/wardrobe/shot_wardrobe.gd [model=res://path/moxie.glb] [tag=name] [page ...]
## Dresses real Moxie models through the Wardrobe API (the same calls the actor layer makes) and
## saves one PNG per page into art/previews/wardrobe/godot_<tag>_<page>.png:
##   headgear_a / headgear_b   the six headgear pieces close up, three per page
##   headgear                  all six at roughly gameplay scale
##   fit_front_a/_b, fit_side_a/_b, fit_back_a/_b   straight-on head close-ups for checking the fit
##   tops / pants / shoes      every look variant of the slot, the rest of the outfit baseline
##   tops_back                 the tops from behind (back-print decals)
##   mixes                     the full-outfit mixes of art/wardrobe/spec.py (identity check)
## Default model: the Moxie currently in the game (res://assets/models/moxie.glb).

const YAW: float = 45.0
const PITCH: float = 35.0
const SHADER: Shader = preload("res://assets/models/wardrobe/wardrobe_look.gdshader")
const BASELINE: Array[String] = ["lined_bomber", "olive_cargos", "beater_hightops"]

var _model_path: String = "res://assets/models/moxie.glb"
var _tag: String = "ref"
var _pages: Array[String] = []
var _stage: Node3D = null
var _camera: Camera3D = null
var _frame: int = 0
var _told: bool = false
var _figs: Array[Node3D] = []
var _wait: int = 40          # frames before a capture; the first page needs the window to settle
var _px_per_m: float = 200.0
var _mats: Array[ShaderMaterial] = []


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("model="):
			_model_path = a.substr(6)
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		else:
			_pages.append(a)
	if _pages.is_empty():
		_pages = ["headgear_a", "headgear_b", "headgear", "tops", "tops_back", "pants", "shoes", "mixes"]
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#3b3644")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(20.0), 0)
	root.add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(_camera)
	root.msaa_3d = Viewport.MSAA_4X
	_next_page()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:          # once the figures are ready in the tree
		for f: Node3D in _figs:
			_pose(f)
	if _frame == _wait:
		_wait = 8
		var img := root.get_texture().get_image()
		var dir := ProjectSettings.globalize_path("res://art/previews/wardrobe")
		DirAccess.make_dir_recursive_absolute(dir)
		var path := dir.path_join("godot_%s_%s.png" % [_tag, _pages[0]])
		img.save_png(path)
		print("saved ", path)
		_pages.remove_at(0)
		if _pages.is_empty():
			return true
		_next_page()
	return false


func _next_page() -> void:
	_frame = 0
	if _stage != null:
		root.remove_child(_stage)
		_stage.free()
	_stage = Node3D.new()
	root.add_child(_stage)
	_mats.clear()
	_figs.clear()
	var page := _pages[0]
	var items: Dictionary = Wardrobe.data().get("items", {})
	var sets: Array = []          # [label, ids]
	var closeup := false
	match page:
		"headgear_a", "headgear_b", "headgear", "fit_front_a", "fit_front_b", "fit_side_a", "fit_side_b", "fit_back_a", "fit_back_b":
			var ids: Array[String] = []
			for id: String in items:
				if Wardrobe.slot_of(id) == "helmet":
					ids.append(id)
			if page.ends_with("_a"):
				ids = ids.slice(0, 3)
				closeup = true
			elif page.ends_with("_b"):
				ids = ids.slice(3)
				closeup = true
			for id: String in ids:
				sets.append([str((items[id] as Dictionary)["name"]), [id] + BASELINE])
		"tops", "pants", "shoes", "tops_back":
			var slot := "top" if page.begins_with("tops") else page
			if page == "shoes":
				slot = "shoes"
			for id: String in items:
				if Wardrobe.slot_of(id) != slot:
					continue
				var ids: Array = [id]
				for b: String in BASELINE:
					if Wardrobe.slot_of(b) != slot:
						ids.append(b)
				sets.append([str((items[id] as Dictionary)["name"]), ids])
		"mixes":
			var mixes: Dictionary = Wardrobe.data().get("mixes", {})
			for mid: String in mixes:
				sets.append([mid.trim_prefix("mix_"), (mixes[mid] as Dictionary)["items"]])
	var n := sets.size()
	var spacing := 0.62 if closeup else (0.82 if n > 6 else 0.95)
	var yaw := deg_to_rad(YAW)
	var pitch := deg_to_rad(PITCH)
	if page.begins_with("fit_"):          # straight-on fitting views of the head
		pitch = deg_to_rad(4.0)
		yaw = deg_to_rad(0.0 if page.begins_with("fit_front") else (90.0 if page.begins_with("fit_side") else 215.0))
		spacing = 0.5
	if page == "tops_back":               # the back prints
		yaw = deg_to_rad(205.0)
		pitch = deg_to_rad(20.0)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var cam_size := (0.85 if page.begins_with("fit_") else 1.15) if closeup else maxf(2.5, (float(n) * spacing + 0.5) * 900.0 / 1600.0)
	_px_per_m = 900.0 / cam_size
	for i: int in n:
		var fig := _figure(sets[i][1] as Array)
		fig.position = right * (float(i) - float(n - 1) * 0.5) * spacing
		_stage.add_child(fig)
		_figs.append(fig)
		var label := Label3D.new()
		label.text = str(sets[i][0])
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 44 if closeup else 34
		label.pixel_size = cam_size / 900.0 * 0.5
		label.outline_size = 10
		label.position = fig.position + Vector3(0, 1.22 if closeup else -0.1, 0) + right * 0.0
		_stage.add_child(label)
	for m: ShaderMaterial in _mats:
		m.set_shader_parameter(&"pattern_px_per_m", _px_per_m)
	var target := Vector3(0, 1.52 if closeup else 0.84, 0)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	_camera.size = cam_size
	_camera.look_at_from_position(target + dir * 12.0, target, Vector3.UP)
	_camera.current = true


## One dressed Moxie: exactly what the actor layer is asked to do in docs/WARDROBE.md.
func _figure(ids: Array) -> Node3D:
	var model := (load(_model_path) as PackedScene).instantiate() as Node3D
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	var names := Wardrobe.material_names(meshes)
	var tints := Wardrobe.tints_for(ids, names)
	_paint(meshes, tints, ids)
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var sk := skels[0] as Skeleton3D
		var fit := Wardrobe.head_fit(sk, meshes, _model_path)
		if not _told:
			_told = true
			print("fit on ", _model_path, ": ", fit)
		for id: Variant in ids:
			var ba := Wardrobe.attach_headgear(sk, str(id), fit)
			if ba != null:
				_paint(ba.find_children("*", "MeshInstance3D", true, false), {}, [])
		Wardrobe.attach_decals(sk, ids, Callable(), meshes)
	return model


## Rest pose is a T-pose: show her the way she stands in play. Uses the model's own "idle" clip
## when it has one, otherwise just brings the arms down.
func _pose(fig: Node3D) -> void:
	for n: Node in fig.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		if ap.has_animation(&"idle"):
			ap.play(&"idle")
			ap.seek(0.0, true)
			ap.pause()
			return
	var skels := fig.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_lower_arms(skels[0] as Skeleton3D)


func _lower_arms(sk: Skeleton3D) -> void:
	for side: Array in [[["LeftUpperArm", "upper_arm.L"], -58.0], [["RightUpperArm", "upper_arm.R"], 58.0]]:
		var bone := Wardrobe.find_bone(sk, PackedStringArray(side[0] as Array))
		if bone < 0:
			continue
		var rest := sk.get_bone_global_rest(bone).basis.orthonormalized()
		var parent := sk.get_bone_parent(bone)
		var pb := sk.get_bone_global_rest(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
		var turned := Basis(Vector3(0, 0, 1), deg_to_rad(float(side[1]))) * rest
		sk.set_bone_pose_rotation(bone, (pb.inverse() * turned).get_rotation_quaternion())


func _paint(meshes: Array, tints: Dictionary, ids: Array) -> void:
	for m: Variant in meshes:
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var mat_name := Wardrobe.surface_material_name(mi, i)
			var src := mi.get_active_material(i) as BaseMaterial3D
			if src != null and src.albedo_texture != null:
				continue  # textured parts (painted faces) keep their own material
			var col: Color = tints.get(StringName(mat_name), src.albedo_color if src != null else Color(0.8, 0.8, 0.8))
			var sm := ShaderMaterial.new()
			sm.shader = SHADER
			sm.set_shader_parameter(&"albedo", col)
			sm.set_shader_parameter(&"is_glow", 1.0 if mat_name.ends_with("_glow") else 0.0)
			var pat := Wardrobe.pattern_for(ids, mat_name)
			if not pat.is_empty():
				sm.set_shader_parameter(&"pattern_tex", pat["texture"])
				sm.set_shader_parameter(&"pattern_col", pat["color"])
				sm.set_shader_parameter(&"pattern_amt", pat["strength"])
				sm.set_shader_parameter(&"pattern_scale", pat["scale"])
				sm.set_shader_parameter(&"pattern_screen", 1.0)
			_mats.append(sm)
			mi.set_surface_override_material(i, sm)
