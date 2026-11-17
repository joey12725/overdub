extends SceneTree
## Godot-side visual check of assets/models/moxie.glb: renders the imported model in Godot itself
## (so the skin binds, the T-pose rest and the clips are seen exactly as the game will see them).
##
##   bash tools/gd shot res://art/moxie/shot_godot.gd [-- <out_dir>]
##
## Writes moxie_godot.png: five copies side by side - the rest pose (no clip: must be the T-pose),
## idle@0, run@0.25, light@0.47 (the hit) and death@1.0 - from the game's isometric angle
## (orthographic, yaw 45, pitch 35). Default out dir: art/previews/moxie.

const PATH := "res://assets/models/moxie.glb"
const POSES := [["", 0.0], ["idle", 0.0], ["run", 0.25], ["light", 0.47], ["death", 1.0]]

var out_dir := ""


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a != "":
			out_dir = a
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://art/previews/moxie")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1500, 560)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.86, 0.86, 0.88)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.1
	world.add_child(sun)
	var packed := load(PATH) as PackedScene
	if packed == null:
		push_error("shot_godot: cannot load " + PATH)
		quit(1)
		return
	for i in POSES.size():
		var inst := packed.instantiate() as Node3D
		world.add_child(inst)
		inst.position = Vector3((i - 2) * 0.95, 0, -(i - 2) * 0.95)
		var clip: String = POSES[i][0]
		var player := _find(inst, "AnimationPlayer") as AnimationPlayer
		if clip != "" and player != null:
			player.play(clip)
			player.seek(float(POSES[i][1]), true)
			player.pause()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.4
	var yaw := deg_to_rad(45.0)
	var pitch := deg_to_rad(35.0)
	var target := Vector3(0, 0.8, 0)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	world.add_child(cam)
	cam.look_at_from_position(target + dir * 10.0, target, Vector3.UP)
	cam.current = true
	for _k in 8:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join("moxie_godot.png")
	img.save_png(path)
	print("wrote ", path)
	quit(0)


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null
