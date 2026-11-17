extends SceneTree
## Dumps Godot's SkeletonProfileHumanoid (names, parents, GLOBAL reference-pose axes) to JSON for the Blender rig builder.
##   bash tools/gd script res://art/moxie_d/scripts/dump_profile.gd
func _initialize() -> void:
	var p := SkeletonProfileHumanoid.new()
	var glob := {}
	var out := []
	for i in p.bone_size:
		var n := String(p.get_bone_name(i))
		var par := String(p.get_bone_parent(i))
		var loc := p.get_reference_pose(i)
		var g: Transform3D = (glob[par] * loc) if glob.has(par) else loc
		glob[n] = g
		var b := g.basis
		out.append({"name": n, "parent": par, "required": p.is_required(i), "group": String(p.get_group(i)),
			"origin": [g.origin.x, g.origin.y, g.origin.z],
			"x": [b.x.x, b.x.y, b.x.z], "y": [b.y.x, b.y.y, b.y.z], "z": [b.z.x, b.z.y, b.z.z]})
	var f := FileAccess.open("res://art/moxie_d/data/godot_humanoid_profile.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	print("dumped ", out.size(), " bones")
	quit(0)
