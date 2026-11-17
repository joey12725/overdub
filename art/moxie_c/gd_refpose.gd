extends SceneTree
## Prints Godot's SkeletonProfileHumanoid reference pose (global bases) as JSON, used by mc_rig.py
## to give Moxie's bones the same rest orientations as Godot's humanoid profile.

func _init() -> void:
	var p := SkeletonProfileHumanoid.new()
	var globals := {}
	var out := {}
	for i in p.bone_size:
		var name := p.get_bone_name(i)
		var parent := p.get_bone_parent(i)
		var local: Transform3D = p.get_reference_pose(i)
		var g: Transform3D = local
		if parent != &"" and globals.has(parent):
			g = globals[parent] * local
		globals[name] = g
		var b := g.basis
		out[name] = {"parent": String(parent), "x": [b.x.x, b.x.y, b.x.z], "y": [b.y.x, b.y.y, b.y.z],
			"z": [b.z.x, b.z.y, b.z.z], "o": [g.origin.x, g.origin.y, g.origin.z], "required": p.is_required(i)}
	var f := FileAccess.open("res://art/moxie_c/godot_humanoid_ref.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("wrote ", out.size(), " bones")
	quit(0)
