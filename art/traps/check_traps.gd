extends SceneTree
## Loads every trap .glb through Godot's import pipeline and checks it against its entry in
## assets/models/kit/manifest.json (the "Traps" contract in docs/GODOT-PORT.md): every listed object
## is a MeshInstance3D directly under the scene root, nothing else is there, every surface has a
## named material, and the conveyor Belt has UVs. Exits non-zero on any failure.
##   bash tools/gd script res://art/traps/check_traps.gd

var _failures: int = 0


func _fail(msg: String) -> void:
	_failures += 1
	print("FAIL ", msg)


func _init() -> void:
	var text := FileAccess.get_file_as_string("res://assets/models/kit/manifest.json")
	var pieces: Dictionary = JSON.parse_string(text)["pieces"]
	var seen := {}
	var count := 0
	for key: String in pieces:
		if not key.begins_with("trap_"):
			continue
		var entry: Dictionary = pieces[key]
		var file: String = entry["file"]
		if seen.has(file):
			continue
		seen[file] = true
		count += 1
		_check("res://assets/models/kit/" + file, entry["objects"])
	print("check_traps: %d files, %d failure(s)" % [count, _failures])
	quit(1 if _failures > 0 else 0)


func _check(path: String, objects: Array) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		_fail("%s: does not load" % path)
		return
	var root := ps.instantiate()
	var names: Array = []
	var tris := 0
	for child in root.get_children():
		names.append(String(child.name))
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			_fail("%s/%s: not a MeshInstance3D" % [path, child.name])
			continue
		if child.get_child_count() > 0:
			_fail("%s/%s: has children" % [path, child.name])
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat == null or mat.resource_name == "":
				_fail("%s/%s: surface %d has no named material" % [path, child.name, s])
			var arrays := mi.mesh.surface_get_arrays(s)
			tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			if child.name == "Belt" and (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty():
				_fail("%s/Belt: no UVs" % path)
	var want: Array = objects.duplicate()
	want.sort()
	names.sort()
	if names != want:
		_fail("%s: objects %s != %s" % [path, names, want])
	print("%s  %d objects  %d tris" % [path.get_file(), names.size(), tris])
	root.free()
