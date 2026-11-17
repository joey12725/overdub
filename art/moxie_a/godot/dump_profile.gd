extends SceneTree
## Dumps Godot's SkeletonProfileHumanoid (names, parents, reference poses, groups, required flags)
## as JSON to art/moxie_a/gen/godot_humanoid_profile.json. The Blender scripts build the export
## skeleton to match these rest orientations exactly.
func _init() -> void:
	var p := SkeletonProfileHumanoid.new()
	var out := []
	for i in p.bone_size:
		var t := p.get_reference_pose(i)
		out.append({
			"name": String(p.get_bone_name(i)), "parent": String(p.get_bone_parent(i)),
			"tail": String(p.get_bone_tail(i)), "tail_dir": p.get_tail_direction(i),
			"group": String(p.get_group(i)), "required": p.is_required(i),
			"origin": [t.origin.x, t.origin.y, t.origin.z],
			"basis": [[t.basis.x.x, t.basis.x.y, t.basis.x.z], [t.basis.y.x, t.basis.y.y, t.basis.y.z], [t.basis.z.x, t.basis.z.y, t.basis.z.z]],
		})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/moxie_a/gen"))
	var f := FileAccess.open("res://art/moxie_a/gen/godot_humanoid_profile.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	print("bones ", p.bone_size, " godot ", Engine.get_version_info()["string"])
	quit(0)
