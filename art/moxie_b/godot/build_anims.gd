extends SceneTree
## Builds res://assets/anim/candidates/b/moxie_anims.res (an AnimationLibrary) from the clips inside
## res://assets/models/candidates/b/moxie.glb:
##   bash tools/gd script res://art/moxie_b/godot/build_anims.gd
## - keeps only tracks of SkeletonProfileHumanoid bones (secondary bones are never keyed)
## - loops: idle, run, stopped;  one-shots: exactly 1.0 s, no loop

const GLB := "res://assets/models/candidates/b/moxie.glb"
const OUT_DIR := "res://assets/anim/candidates/b"
const LOOPS: Array[String] = ["idle", "run", "stopped"]
const CLIPS: Array[String] = ["idle", "run", "stopped", "light", "heavy", "dodge", "ranged", "interact", "death"]


func _initialize() -> void:
	var scene := load(GLB) as PackedScene
	if scene == null:
		push_error("cannot load " + GLB)
		quit(1)
		return
	var model := scene.instantiate()
	var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var profile := SkeletonProfileHumanoid.new()
	var allowed := {}
	for i in range(profile.bone_size):
		allowed[String(profile.get_bone_name(i))] = true
	var lib := AnimationLibrary.new()
	for clip in CLIPS:
		var src := player.get_animation(clip)
		if src == null:
			push_error("missing clip " + clip)
			continue
		var a := src.duplicate(true) as Animation
		for t in range(a.get_track_count() - 1, -1, -1):
			var path := a.track_get_path(t)
			var bone := path.get_concatenated_subnames()
			if not allowed.has(bone) or bone == "Root":
				a.remove_track(t)
		if LOOPS.has(clip):
			a.loop_mode = Animation.LOOP_LINEAR
		else:
			a.loop_mode = Animation.LOOP_NONE
			a.length = 1.0
		a.resource_name = clip
		lib.add_animation(clip, a)
		print("[build_anims] %s  length %.3f  tracks %d  loop %s" % [clip, a.length, a.get_track_count(), str(a.loop_mode != Animation.LOOP_NONE)])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var err := ResourceSaver.save(lib, OUT_DIR + "/moxie_anims.res")
	print("[build_anims] saved ", OUT_DIR, "/moxie_anims.res  err=", err)
	model.free()
	quit(0 if err == OK else 1)
