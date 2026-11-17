extends SceneTree
## Builds res://assets/anim/candidates/e/moxie_anims.res (an AnimationLibrary) from the animations
## inside res://assets/models/candidates/e/moxie.glb:
##   bash tools/gd script res://art/moxie_e/godot/build_anim_lib.gd
## Loops (idle, run, stopped) get LOOP_LINEAR; the one-shots are checked to be exactly 1.0 s.
## Only the profile-bone tracks are kept (secondary bones are never driven by gameplay clips).

const GLB := "res://assets/models/candidates/e/moxie.glb"
const OUT := "res://assets/anim/candidates/e/moxie_anims.res"
const LOOPS := ["idle", "run", "stopped"]
const ONE_SHOTS := ["light", "heavy", "dodge", "ranged", "interact", "death"]


func _init() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(GLB), state)
	if err != OK:
		push_error("cannot read %s: %s" % [GLB, error_string(err)])
		quit(1)
		return
	var scene := doc.generate_scene(state)
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_error("no AnimationPlayer in the glb")
		quit(1)
		return
	var player := players[0] as AnimationPlayer
	var skel := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var profile := SkeletonProfileHumanoid.new()
	var lib := AnimationLibrary.new()
	var ok := true
	for want: String in LOOPS + ONE_SHOTS:
		if not player.has_animation(want):
			push_error("missing clip " + want)
			ok = false
			continue
		var a := player.get_animation(want).duplicate(true) as Animation
		for t in range(a.get_track_count() - 1, -1, -1):
			var path := a.track_get_path(t)
			var keep := path.get_subname_count() > 0 and profile.find_bone(path.get_subname(0)) >= 0
			if not keep:
				a.remove_track(t)
		if LOOPS.has(want):
			a.loop_mode = Animation.LOOP_LINEAR
		else:
			a.loop_mode = Animation.LOOP_NONE
			if absf(a.length - 1.0) > 0.002:
				push_error("%s is %.4f s, expected 1.0" % [want, a.length])
				ok = false
			a.length = 1.0
		lib.add_animation(want, a)
		print("clip %-9s length %.3f loop %d tracks %d  first path %s" % [want, a.length, a.loop_mode, a.get_track_count(), a.track_get_path(0)])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	err = ResourceSaver.save(lib, OUT)
	print("saved ", OUT, " ", error_string(err), " bones ", skel.get_bone_count())
	scene.free()
	quit(0 if ok and err == OK else 1)
