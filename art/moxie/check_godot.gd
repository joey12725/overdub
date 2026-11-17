extends SceneTree
## Godot-side check of assets/models/moxie.glb (run: bash tools/gd script res://art/moxie/check_godot.gd).
## Loads the imported scene and, independently, the raw file through GLTFDocument, and prints the
## skeleton, materials, animations (with lengths and loop flags) and the mesh AABB in Godot axes.

const PATH := "res://assets/models/moxie.glb"


func _init() -> void:
	var ok := true
	var packed := load(PATH) as PackedScene
	if packed == null:
		push_error("moxie.glb did not import as a PackedScene")
		quit(1)
		return
	var root := packed.instantiate()
	ok = _report(root, "imported") and ok
	root.free()

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(PATH), state)
	if err != OK:
		push_error("GLTFDocument failed: %s" % error_string(err))
		ok = false
	else:
		var scene := doc.generate_scene(state)
		ok = _report(scene, "GLTFDocument") and ok
		scene.free()
	print("RESULT ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)


func _report(root: Node, label: String) -> bool:
	var ok := true
	var skel := _find(root, "Skeleton3D") as Skeleton3D
	var mesh := _find(root, "MeshInstance3D") as MeshInstance3D
	var player := _find(root, "AnimationPlayer") as AnimationPlayer
	print("--- ", label)
	if skel == null or mesh == null or player == null:
		print("missing skeleton/mesh/player")
		return false
	var names: PackedStringArray = []
	for i in skel.get_bone_count():
		names.append(skel.get_bone_name(i))
	print("bones (%d): %s" % [skel.get_bone_count(), ", ".join(names)])
	for b in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
			"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
			"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes", "RightHandGrip", "pigtail.L.003", "jacket.R"]:
		if skel.find_bone(b) < 0:
			print("MISSING bone ", b)
			ok = false
	# the rest pose must be a T-pose: upper arm -> hand runs along +-X
	for side in ["Left", "Right"]:
		var ua := skel.find_bone(side + "UpperArm")
		var hd := skel.find_bone(side + "Hand")
		if ua >= 0 and hd >= 0:
			var d := (skel.get_bone_global_rest(hd).origin - skel.get_bone_global_rest(ua).origin).normalized()
			print("%s arm rest direction %s" % [side, d])
			if absf(d.x) < 0.99:
				print("NOT a T-pose rest")
				ok = false
	var mats: PackedStringArray = []
	for s in mesh.mesh.get_surface_count():
		var m := mesh.mesh.surface_get_material(s)
		mats.append(m.resource_name if m else "<none>")
	print("surfaces (%d): %s" % [mesh.mesh.get_surface_count(), ", ".join(mats)])
	var aabb := mesh.get_aabb()
	print("mesh aabb: pos %s size %s" % [aabb.position, aabb.size])
	for anim_name in player.get_animation_list():
		var a := player.get_animation(anim_name)
		print("anim %-10s length %.3f loop %d tracks %d" % [anim_name, a.length, a.loop_mode, a.get_track_count()])
	return ok


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null
