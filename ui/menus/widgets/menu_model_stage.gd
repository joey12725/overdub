class_name MenuModelStage
extends SubViewportContainer
## A small 3D turntable for showing a model inside a menu (the time machine on the ending card, the
## weapon in the loadout details). It renders in its own World3D with a transparent background,
## frames the model's bounds and turns it slowly. Models are loaded by the asset-contract names
## (docs/GODOT-PORT.md); when none exists, try_make() returns null and the caller shows its 2D
## content alone.

const KIT_DIR := "res://assets/models/kit/"
const KIT_MANIFEST := "res://assets/models/kit/manifest.json"
const WEAPON_DIR := "res://assets/models/weapons/"

var _pivot: Node3D
var _spin: float = 0.35


## Candidate path for a weapon's model: assets/models/weapons/<item id>.glb (origin at the grip,
## business end along +Y).
static func weapon_paths(item_id: String) -> Array[String]:
	var out: Array[String] = []
	if not item_id.is_empty():
		out.append(WEAPON_DIR + item_id + ".glb")
	return out


## Candidate paths for the time machine: themed variant first (it sits in the core), then plain.
static func time_machine_paths() -> Array[String]:
	var out: Array[String] = []
	for piece: String in ["time_machine__lower", "time_machine"]:
		var file := _manifest_file(piece)
		if not file.is_empty():
			out.append(KIT_DIR + file)
		out.append(KIT_DIR + piece + ".glb")
	return out


static func _manifest_file(piece: String) -> String:
	if not FileAccess.file_exists(KIT_MANIFEST):
		return ""
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT_MANIFEST))
	if not (data is Dictionary) or not ((data as Dictionary).get("pieces") is Dictionary):
		return ""
	var entry: Variant = (data["pieces"] as Dictionary).get(piece)
	if entry is Dictionary and (entry as Dictionary).get("file") is String:
		return String(entry["file"]).get_file()
	return ""


## The first existing model of `paths` on a turntable, or null when none exists yet. `tilt_deg` leans
## the model about the view axis before it spins (a weapon modelled along +Y reads better on a slant).
static func try_make(paths: Array[String], min_size: Vector2, tilt_deg: float = 0.0) -> MenuModelStage:
	for p in paths:
		if ResourceLoader.exists(p):
			var scene := load(p) as PackedScene
			if scene != null:
				var stage := MenuModelStage.new()
				stage._setup(scene.instantiate() as Node3D, min_size, tilt_deg)
				return stage
	return null


func _setup(model: Node3D, min_size: Vector2, tilt_deg: float = 0.0) -> void:
	custom_minimum_size = min_size
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.size = Vector2i(min_size)
	add_child(vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.75)
	e.ambient_light_energy = 0.8
	e.glow_enabled = true
	e.glow_intensity = 0.9
	env.environment = e
	vp.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.4
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 200, 0)
	rim.light_color = MenuStyle.CYAN
	rim.light_energy = 0.8
	vp.add_child(rim)

	_pivot = Node3D.new()
	vp.add_child(_pivot)
	if model == null:
		return
	var holder := Node3D.new()
	holder.rotation.z = deg_to_rad(tilt_deg)
	holder.add_child(model)
	_pivot.add_child(holder)
	var box := _bounds(holder, Transform3D.IDENTITY)
	if box.size == Vector3.ZERO:
		box = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	holder.position = -box.get_center()

	var cam := Camera3D.new()
	cam.fov = 30.0
	var radius := maxf(box.size.length() * 0.5, 0.25)
	var dist := radius / sin(deg_to_rad(cam.fov * 0.5)) * 1.05
	cam.position = Vector3(0, radius * 0.35, dist)
	cam.look_at_from_position(cam.position, Vector3.ZERO, Vector3.UP)
	vp.add_child(cam)


func _process(delta: float) -> void:
	if _pivot != null and is_visible_in_tree():
		_pivot.rotate_y(_spin * delta)


## Union of every VisualInstance3D's bounds under `n`, in the space of the first call's parent.
static func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var has := false
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is VisualInstance3D:
		var b := here * (n as VisualInstance3D).get_aabb()
		out = b
		has = true
	for c in n.get_children():
		var cb := _bounds(c, here)
		if cb.size != Vector3.ZERO:
			out = out.merge(cb) if has else cb
			has = true
	return out
