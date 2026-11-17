extends SceneTree
## Loads every decor prop and melee weapon .glb in Godot, both through the import pipeline
## (load() -> PackedScene) and raw through GLTFDocument, and prints nodes, materials, triangle
## counts, AABBs and animations. Exits non-zero on any failure.
##   bash tools/gd script res://art/weapons/check_models.gd

const DECOR: Array[String] = [
	"vines", "bush", "rubble__upper", "rubble__lower", "crate__upper", "crate__lower",
	"barrel__upper", "barrel__lower", "chest__upper", "chest__lower", "pipe__upper", "pipe__lower",
	"console__upper", "console__lower", "generator__upper", "generator__lower", "vent__upper",
	"vent__lower", "lamp__upper", "lamp__lower", "neon", "cable", "wave_screen", "arch__upper",
	"arch__lower", "rune_panel", "time_machine",
]
const WEAPONS: Array[String] = [
	"splice_blade", "stylus_shiv", "amp_sledge", "reel_lash", "speaker_knuckles", "vinyl_glaive",
]
const REQUIRED := {
	"chest__upper": ["Lid"], "chest__lower": ["Lid"], "console__upper": ["Screen"],
	"console__lower": ["Screen"], "wave_screen": ["Screen"], "generator__upper": ["Fan"],
	"vent__upper": ["Fan"], "vent__lower": ["Fan"], "reel_lash": ["Lash"], "vinyl_glaive": ["Disc"],
	"time_machine": ["Ring_Outer", "Ring_Mid", "Ring_Inner", "Heart", "Reel_L", "Reel_R"],
}

var _failures: int = 0


func _init() -> void:
	for n in DECOR:
		_check("res://assets/models/kit/%s.glb" % n, n, true)
	for n in WEAPONS:
		_check("res://assets/models/weapons/%s.glb" % n, n, false)
	print("check_models: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _fail(msg: String) -> void:
	_failures += 1
	print("  FAIL ", msg)


func _check(path: String, name: String, is_prop: bool) -> void:
	# 1) the imported scene
	var res: Resource = load(path)
	if not (res is PackedScene):
		_fail("%s did not import as a PackedScene" % path)
		return
	var root: Node = (res as PackedScene).instantiate()
	var info := _walk_root(root)
	# 2) the raw file through GLTFDocument
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(path), state)
	if err != OK:
		_fail("%s GLTFDocument error %d" % [path, err])
	else:
		var raw: Node = doc.generate_scene(state)
		var raw_info := _walk_root(raw)
		if raw_info["tris"] != info["tris"]:
			_fail("%s imported tris %d != raw tris %d" % [name, info["tris"], raw_info["tris"]])
		raw.free()
	var aabb: AABB = info["aabb"]
	var names: PackedStringArray = info["names"]
	print("%-18s tris=%5d meshes=%s aabb=%s..%s mats=%d anims=%s" % [name, info["tris"], ",".join(names),
		_v(aabb.position), _v(aabb.end), (info["mats"] as Dictionary).size(), info["anims"]])
	for req: String in REQUIRED.get(name, []):
		if not names.has(req):
			_fail("%s: missing mesh object %s" % [name, req])
	if (info["anims"] as PackedStringArray).size() > 0:
		_fail("%s: unexpected animations" % name)
	for m: String in (info["mats"] as Dictionary).keys():
		if m.is_empty():
			_fail("%s: unnamed material" % name)
	if is_prop:
		if absf(aabb.position.y) > 0.003:
			_fail("%s: not on the floor (min y %.4f)" % [name, aabb.position.y])
	else:
		if not (aabb.position.y < 0.0 and aabb.end.y > 0.05):
			_fail("%s: origin not at the grip" % name)
	root.free()


func _walk_root(root: Node) -> Dictionary:
	var out := {"tris": 0, "names": PackedStringArray(), "mats": {}, "aabb": AABB(), "first": true,
		"anims": PackedStringArray()}
	_walk(root, out)
	return out


func _walk(n: Node, out: Dictionary) -> void:
	if n is AnimationPlayer:
		# Packed arrays are values: append to a local copy and store it back.
		var anims: PackedStringArray = out["anims"]
		for a: StringName in (n as AnimationPlayer).get_animation_list():
			anims.append(String(a))
		out["anims"] = anims
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		var names: PackedStringArray = out["names"]
		names.append(String(mi.name))
		out["names"] = names
		var xf := _global(mi)
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			out["tris"] = int(out["tris"]) + (idx.size() / 3 if idx.size() > 0 else verts.size() / 3)
			var mat := mesh.surface_get_material(s)
			(out["mats"] as Dictionary)[mat.resource_name if mat else ""] = true
			for v in verts:
				var p := xf * v
				if out["first"]:
					out["aabb"] = AABB(p, Vector3.ZERO)
					out["first"] = false
				else:
					out["aabb"] = (out["aabb"] as AABB).expand(p)
	for c in n.get_children():
		_walk(c, out)


func _global(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]
