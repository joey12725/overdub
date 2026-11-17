extends SceneTree
## Builds res://assets/anim/candidates/c/moxie_anims.res (an AnimationLibrary) from the clips baked
## into assets/models/candidates/c/moxie.glb:
##   bash tools/gd script res://art/moxie_c/gd_build_anims.gd
## Only SkeletonProfileHumanoid bones keep tracks (secondary bones stay free for spring motion),
## scale tracks are dropped, loops are flagged and lengths are snapped to the contract.

const GLB := "res://assets/models/candidates/c/moxie.glb"
const OUT_DIR := "res://assets/anim/candidates/c"
const OUT := OUT_DIR + "/moxie_anims.res"
const LOOPS := {"idle": 2.0, "run": 0.6, "stopped": 1.0}
const ONESHOTS := ["light", "heavy", "dodge", "ranged", "interact", "death"]


func _init() -> void:
	var packed := load(GLB) as PackedScene
	if packed == null:
		push_error("cannot load " + GLB)
		quit(1)
		return
	var scene := packed.instantiate()
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_error("no AnimationPlayer in the glb")
		quit(1)
		return
	var player := players[0] as AnimationPlayer
	var profile := SkeletonProfileHumanoid.new()
	var keep := {}
	for i in profile.bone_size:
		keep[String(profile.get_bone_name(i))] = true
	var lib := AnimationLibrary.new()
	var ok := true
	for clip: String in LOOPS.keys() + ONESHOTS:
		if not player.has_animation(clip):
			push_error("missing clip " + clip)
			ok = false
			continue
		var a := player.get_animation(clip).duplicate(true) as Animation
		for t in range(a.get_track_count() - 1, -1, -1):
			var path := String(a.track_get_path(t))
			var bone := path.get_slice(":", 1)
			if a.track_get_type(t) == Animation.TYPE_SCALE_3D or not keep.has(bone):
				a.remove_track(t)
			elif a.track_get_type(t) == Animation.TYPE_POSITION_3D and bone != "Hips":
				a.remove_track(t)
		var want: float = LOOPS[clip] if LOOPS.has(clip) else 1.0
		if absf(a.length - want) > 0.02:
			push_error("%s: length %.3f, expected %.3f" % [clip, a.length, want])
			ok = false
		a.length = want
		a.loop_mode = Animation.LOOP_LINEAR if LOOPS.has(clip) else Animation.LOOP_NONE
		lib.add_animation(clip, a)
		print("clip %-9s length %.3f loop %d tracks %d" % [clip, a.length, a.loop_mode, a.get_track_count()])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var err := ResourceSaver.save(lib, OUT)
	print("saved ", OUT, " -> ", error_string(err), "  root_node of the glb player: ", player.root_node)
	scene.free()
	quit(0 if ok and err == OK else 1)
