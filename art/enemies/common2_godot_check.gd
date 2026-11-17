extends SceneTree
## Godot-side check of the turret/brute/boss enemy models as imported by the engine.
##   bash tools/gd script res://art/enemies/common2_godot_check.gd [-- turret brute boss]
## Loads each res://assets/models/enemies/<type>.glb (the imported scene), instantiates it and
## prints its skeleton, mesh nodes, AnimationPlayer animations with lengths and loop modes, and the
## combined AABB. Fails (exit 1) when the contract is not met.

const ACTIONS := {"idle": 0.0, "move": 0.0, "telegraph": 1.0, "attack": 1.0, "stagger": 1.0, "death": 1.0}
const EXTRA_MESHES := {"boss": ["Armor_1", "Armor_2", "Armor_3"]}
const EXTRA_BONES := {"turret": ["aim"]}


func _init() -> void:
	var types: Array = []
	for a in OS.get_cmdline_user_args():
		types.append(a)
	if types.is_empty():
		types = ["turret", "brute", "boss"]
	var failures := 0
	for t in types:
		failures += _check(str(t))
	print("RESULT: %s" % ("OK" if failures == 0 else "%d failure(s)" % failures))
	quit(1 if failures > 0 else 0)


func _check(type_name: String) -> int:
	var path := "res://assets/models/enemies/%s.glb" % type_name
	print("== ", path)
	var packed := load(path) as PackedScene
	if packed == null:
		print("  FAIL: could not load")
		return 1
	var root := packed.instantiate()
	var fails := 0
	var skel := root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		print("  FAIL: no Skeleton3D")
		fails += 1
	else:
		var bones: Array = []
		for i in skel.get_bone_count():
			bones.append(skel.get_bone_name(i))
		print("  bones (%d): %s" % [bones.size(), ", ".join(bones)])
		# The game spins reel.L/R about their local X (enemy_view.gd): print that axle in model space.
		for rn in ["reel.L", "reel.R"]:
			var ri := skel.find_bone(rn)
			if ri >= 0:
				var ax := skel.get_bone_global_rest(ri).basis.x.normalized()
				print("  %s axle (local X, model space): (%.2f, %.2f, %.2f)" % [rn, ax.x, ax.y, ax.z])
		for b in EXTRA_BONES.get(type_name, []):
			if not bones.has(b):
				print("  FAIL: missing bone ", b)
				fails += 1
	var meshes: Array = []
	var aabb := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		meshes.append(mi.name)
		var box: AABB = mi.global_transform * mi.get_aabb() if mi.is_inside_tree() else mi.transform * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	print("  meshes: %s" % ", ".join(meshes))
	for m in EXTRA_MESHES.get(type_name, []):
		if not meshes.has(m):
			print("  FAIL: missing mesh ", m)
			fails += 1
	print("  aabb: pos %s size %s" % [aabb.position, aabb.size])
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		print("  FAIL: no AnimationPlayer")
		return fails + 1
	for anim_name in ACTIONS:
		if not ap.has_animation(anim_name):
			print("  FAIL: missing animation ", anim_name)
			fails += 1
			continue
		var anim := ap.get_animation(anim_name)
		var want: float = ACTIONS[anim_name]
		print("  anim %-10s %.3f s  %d tracks" % [anim_name, anim.length, anim.get_track_count()])
		if want > 0.0 and absf(anim.length - want) > 0.02:
			print("  FAIL: %s length %.3f != %.1f" % [anim_name, anim.length, want])
			fails += 1
		for ti in anim.get_track_count():
			if str(anim.track_get_path(ti)).ends_with(":aim"):
				print("  FAIL: %s animates the game-driven aim bone" % anim_name)
				fails += 1
	root.free()
	return fails
