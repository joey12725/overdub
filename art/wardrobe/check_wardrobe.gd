extends SceneTree
## Headless verification of the wardrobe from inside Godot:
##   bash tools/gd script res://art/wardrobe/check_wardrobe.gd
## - data/wardrobe.json covers exactly the helmet / top / pants / shoes items of data/gear.json
## - every headgear glb loads both through the import pipeline and raw through GLTFDocument, has
##   500-2500 triangles, flat materials, an emissive *_glow where named, and sane bounds
## - every referenced texture loads and is 512 px
## - looks only ever touch outfit materials, on the reference model and on every candidate
## - headgear attaches to the Head bone of each model and reports its fit
## Exits non-zero on any failure.

const SLOTS: Array[String] = ["helmet", "top", "pants", "shoes"]
const IDENTITY: Array[String] = ["headphones", "phones", "walkman", "hair", "skin", "belt", "face", "eye"]
const MODELS: Array[String] = [
	"res://assets/models/moxie.glb",
	"res://assets/models/candidates/a/moxie.glb",
	"res://assets/models/candidates/b/moxie.glb",
	"res://assets/models/candidates/c/moxie.glb",
	"res://assets/models/candidates/d/moxie.glb",
	"res://assets/models/candidates/e/moxie.glb",
]

var _failures: int = 0


func _initialize() -> void:
	_check_data()
	_check_headgear()
	_check_textures()
	for m: String in MODELS:
		if ResourceLoader.exists(m):
			_check_on_model(m)
		else:
			print("model ", m, ": not present (skipped)")
	print("check_wardrobe: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _fail(msg: String) -> void:
	_failures += 1
	print("  FAIL ", msg)


func _check_data() -> void:
	var gear: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/gear.json"))
	var want: Dictionary = {}
	for it: Dictionary in (gear as Dictionary)["items"]:
		if SLOTS.has(str(it["slot"])):
			want[str(it["id"])] = str(it["slot"])
	var items: Dictionary = Wardrobe.data().get("items", {})
	for id: String in want:
		if not items.has(id):
			_fail("gear item %s has no wardrobe entry" % id)
		elif Wardrobe.slot_of(id) != want[id]:
			_fail("%s: slot %s != gear slot %s" % [id, Wardrobe.slot_of(id), want[id]])
	for id: String in items:
		if not want.has(id):
			_fail("wardrobe entry %s is not a gear item" % id)
		var it: Dictionary = items[id]
		if str(it["slot"]) == "helmet":
			if not it.has("attach"):
				_fail("%s: helmet without attach" % id)
		elif not (it.get("look", {}) as Dictionary).has("colors"):
			_fail("%s: look without colors" % id)
		if Wardrobe.palette(id).size() != 3:
			_fail("%s: palette needs base, trim, accent" % id)
		if not it.has("concept"):
			_fail("%s: no concept sheet" % id)
		elif not ResourceLoader.exists(str(it["concept"])):
			_fail("%s: concept %s does not load" % [id, it["concept"]])
	print("data: %d items, %d gear items covered" % [items.size(), want.size()])


func _mesh_stats(node: Node) -> Dictionary:
	var tris := 0
	var box := AABB()
	var first := true
	var mats: Dictionary = {}
	var list: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		list.append(node)
	for n: Node in list:
		var mi := n as MeshInstance3D
		for i: int in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(i)
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var count: int = (idx as PackedInt32Array).size() if idx != null else verts.size()
			tris += count / 3
			for v: Vector3 in verts:
				if first:
					box = AABB(v, Vector3.ZERO)
					first = false
				else:
					box = box.expand(v)
			mats[Wardrobe.surface_material_name(mi, i)] = mi.get_active_material(i)
	return {"tris": tris, "box": box, "mats": mats}


func _check_headgear() -> void:
	var items: Dictionary = Wardrobe.data().get("items", {})
	for id: String in items:
		var it: Dictionary = items[id]
		if str(it["slot"]) != "helmet" or not it.has("attach"):
			continue
		var path := str((it["attach"] as Dictionary)["model"])
		var node := Wardrobe.headgear_scene(id)
		if node == null:
			_fail("%s: %s did not load as a scene" % [id, path])
			continue
		var st := _mesh_stats(node)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
			_fail("%s: GLTFDocument could not read the file" % id)
		else:
			var raw := doc.generate_scene(state)
			var rs := _mesh_stats(raw)
			if rs["tris"] != st["tris"]:
				_fail("%s: imported tris %d != raw tris %d" % [id, st["tris"], rs["tris"]])
			raw.free()
		var tris: int = st["tris"]
		var box: AABB = st["box"]
		if tris < 500 or tris > 2500:
			_fail("%s: %d triangles (want 500-2500)" % [id, tris])
		if absf(box.position.x + box.end.x) > 0.03:
			_fail("%s: not centred in x" % id)
		if box.position.y < -0.3 or box.end.y > 0.6 or absf(box.position.x) > 0.45 or box.end.z > 0.3 or box.position.z < -0.3:
			_fail("%s: bounds %s are not head-sized around the origin" % [id, box])
		var mats: Dictionary = st["mats"]
		var glow := 0
		for mn: String in mats:
			var m := mats[mn] as BaseMaterial3D
			if m == null:
				_fail("%s: material %s is not a plain material" % [id, mn])
				continue
			if not mn.begins_with("helmet"):
				_fail("%s: material %s does not start with helmet" % [id, mn])
			if m.albedo_texture != null:
				_fail("%s: material %s carries a texture" % [id, mn])
			if mn.ends_with("_glow"):
				glow += 1
				if not m.emission_enabled:
					_fail("%s: %s is not emissive" % [id, mn])
		print("headgear %-15s %4d tris  %d materials (%d glow)  y %.3f..%.3f  x +-%.3f  z %.3f..%.3f" % [
			id, tris, mats.size(), glow, box.position.y, box.end.y, box.end.x, box.position.z, box.end.z])
		node.free()


func _check_textures() -> void:
	var seen: Dictionary = {}
	var items: Dictionary = Wardrobe.data().get("items", {})
	for id: String in items:
		var look: Dictionary = (items[id] as Dictionary).get("look", {})
		var paths: Array[String] = []
		if look.has("pattern"):
			paths.append(str((look["pattern"] as Dictionary)["texture"]))
		for d: Dictionary in look.get("decals", []):
			paths.append(str(d["texture"]))
		for p: String in paths:
			if seen.has(p):
				continue
			seen[p] = true
			var t: Texture2D = null
			if ResourceLoader.exists(p):
				t = load(p) as Texture2D
			if t == null:
				_fail("%s: texture %s does not load" % [id, p])
			elif t.get_width() != 512 or t.get_height() != 512:
				_fail("%s is %dx%d, want 512" % [p, t.get_width(), t.get_height()])
	print("textures: %d checked" % seen.size())


func _check_on_model(path: String) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		_fail("%s does not load" % path)
		return
	var model := ps.instantiate() as Node3D
	root.add_child(model)
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	var skels := model.find_children("*", "Skeleton3D", true, false)
	var names := Wardrobe.material_names(meshes)
	var items: Dictionary = Wardrobe.data().get("items", {})
	var all_ids: Array = items.keys()
	var touched: Dictionary = {}
	for id: String in all_ids:
		var tints := Wardrobe.tints_for([id], names)
		for mn: StringName in tints:
			touched[String(mn)] = true
			for ident: String in IDENTITY:
				if String(mn).begins_with(ident):
					_fail("%s: %s recolours identity material %s" % [path, id, mn])
		if str((items[id] as Dictionary)["slot"]) != "helmet" and tints.is_empty():
			print("  note: %s recolours nothing on %s" % [id, path])
	var untouched: Array[String] = []
	for n: StringName in names:
		if not touched.has(String(n)):
			untouched.append(String(n))
	print("model %s" % path)
	print("  outfit materials recoloured: ", touched.keys())
	print("  left alone: ", untouched)
	if skels.is_empty():
		_fail("%s has no Skeleton3D" % path)
	else:
		var sk := skels[0] as Skeleton3D
		var fit := Wardrobe.head_fit(sk, meshes, path)
		print("  head bone %d, headphones box %s" % [Wardrobe.find_bone(sk, Wardrobe.HEAD_BONES), Wardrobe.headphones_box(sk, meshes)])
		print("  head fit: offset %s scale %.3f (%s)" % [fit["offset"], fit["scale"], fit["source"]])
		for id: String in all_ids:
			if str((items[id] as Dictionary)["slot"]) != "helmet":
				continue
			var ba := Wardrobe.attach_headgear(sk, id, fit)
			if ba == null:
				_fail("%s: %s did not attach" % [path, id])
		Wardrobe.clear_headgear(sk)
		var dn := Wardrobe.attach_decals(sk, all_ids, Callable(), meshes).size()
		print("  decals attached: %d, jacket back at %s" % [dn, str(Wardrobe.measure_place("jacket_back", sk, meshes))])
	root.remove_child(model)
	model.free()
