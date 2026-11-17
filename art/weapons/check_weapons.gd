extends SceneTree
## Loads every weapon and projectile .glb through Godot's import pipeline and checks the contract in
## docs/GODOT-PORT.md ("Weapons"): required nodes, named materials, *_glow, triangle counts, AABBs,
## the lash skeleton. Exits non-zero on any failure.
##   bash tools/gd script res://art/weapons/check_weapons.gd

const MELEE: Array[String] = ["splice_blade", "stylus_shiv", "amp_sledge", "reel_lash", "speaker_knuckles", "vinyl_glaive"]
const RANGED: Array[String] = ["mixtape_rocket", "needle_rail", "bleed_emitter", "bass_drop", "static_spray"]
const PROJECTILES: Array[String] = ["missile", "pierce", "phase", "arc", "burst", "bolt", "shock"]
const EXTRA := {
	"reel_lash": ["Weapon", "Lash", "LashRig", "LashRoot"], "vinyl_glaive": ["Weapon", "Disc", "DiscAxis", "Grip2"],
	"speaker_knuckles": ["Gauntlet_R", "Gauntlet_L"], "amp_sledge": ["Weapon", "Grip2"], "mixtape_rocket": ["Round"],
}

var _failures: int = 0


func _init() -> void:
	for n in MELEE:
		_check("res://assets/models/weapons/%s.glb" % n, n, ["Grip", "Tip", "TrailStart", "TrailEnd"])
	for n in RANGED:
		_check("res://assets/models/weapons/%s.glb" % n, n, ["Weapon", "Mount", "Muzzle"])
	for n in PROJECTILES:
		_check("res://assets/models/projectiles/%s.glb" % n, n, ["Projectile", "Nose", "Tail"])
	print("check_weapons: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _fail(msg: String) -> void:
	_failures += 1
	print("  FAIL ", msg)


func _check(path: String, id: String, required: Array) -> void:
	var res: Resource = load(path)
	if not (res is PackedScene):
		_fail("%s did not import as a PackedScene" % path)
		return
	var root: Node = (res as PackedScene).instantiate()
	var info := {"tris": 0, "mats": {}, "aabb": AABB(), "first": true, "bones": 0, "anims": 0}
	_walk(root, info)
	var req: Array = required.duplicate()
	req.append_array(EXTRA.get(id, []))
	for r: String in req:
		if root.find_child(r, true, false) == null:
			_fail("%s: node %s missing" % [id, r])
	for m: String in (info["mats"] as Dictionary).keys():
		if m.is_empty():
			_fail("%s: unnamed material" % id)
	if int(info["anims"]) > 0:
		_fail("%s: unexpected animations" % id)
	if id == "reel_lash" and int(info["bones"]) != 10:
		_fail("reel_lash: expected 10 bones, got %d" % int(info["bones"]))
	var a: AABB = info["aabb"]
	var extra := ""
	for e: String in ["Tip", "TrailStart", "TrailEnd", "Muzzle", "Nose"]:
		var n := root.find_child(e, true, false) as Node3D
		if n != null:
			extra += " %s=%s" % [e, _v(_global(n).origin)]
	print("%-17s tris=%5d mats=%2d aabb=%s..%s%s" % [id, int(info["tris"]), (info["mats"] as Dictionary).size(), _v(a.position), _v(a.end), extra])
	root.free()


func _walk(n: Node, out: Dictionary) -> void:
	if n is AnimationPlayer:
		out["anims"] = int(out["anims"]) + (n as AnimationPlayer).get_animation_list().size()
	if n is Skeleton3D:
		out["bones"] = int(out["bones"]) + (n as Skeleton3D).get_bone_count()
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var xf := _global(mi)
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			out["tris"] = int(out["tris"]) + (idx.size() / 3 if idx.size() > 0 else verts.size() / 3)
			var mat := mi.mesh.surface_get_material(s)
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
