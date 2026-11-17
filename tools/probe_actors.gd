extends SceneTree
## Headless numeric probe of the shipping Moxie under the animation library (no rendering):
##   bash tools/gd script res://tools/probe_actors.gd
## Prints, per library clip retargeted onto assets/models/moxie.glb: how far the lowest ankle / toe
## leaves its rest height (foot planting), and how far the clip's authored grip arc is from the
## weapon frame the real right hand produces (the smear must sit on the real striking edge).

var _frames: int = 0


## The probe runs on the second frame: bone poses only propagate once the tree is live.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_probe()
		return true
	return false


func _probe() -> void:
	var rig := ActorRig.new()
	rig.setup(SelfView.MOXIE_PATH, MoxieStandin.instance)
	root.add_child(rig)
	var sk := rig.skeleton
	print("skeleton bones=", sk.get_bone_count(), " matches_profile=", FeelRetarget.matches_profile(sk), " top=", rig.top)
	for n: String in ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightHand", "Head"]:
		var b := sk.find_bone(n)
		print("  rest ", n, " ", sk.get_bone_global_rest(b).origin if b >= 0 else "MISSING")
	var prof := SkeletonProfileHumanoid.new()
	var py := 0.0
	for n: String in ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes"]:
		var i := prof.find_bone(n)
		print("  profile ref ", n, " ", prof.get_reference_pose(i).origin)
	MoxieModel.bind_clips(rig.sampler)
	var s := rig.sampler
	var pose := ActorClipSampler.Pose.new(s.bone_count)
	var feet: Array[int] = [sk.find_bone("LeftFoot"), sk.find_bone("RightFoot")]
	var toes: Array[int] = [sk.find_bone("LeftToes"), sk.find_bone("RightToes")]
	var rest_foot := sk.get_bone_global_rest(feet[0]).origin.y
	var rest_toe := sk.get_bone_global_rest(toes[0]).origin.y
	var names := s.clip_names()
	names.sort()
	print("clips: ", names)
	print("rest ankle y=%.3f toe y=%.3f" % [rest_foot, rest_toe])
	for c: StringName in names:
		var lo_f := INF
		var hi_f := -INF
		var lo_t := INF
		for k: int in 41:
			s.sample(c, float(k) / 40.0, pose)
			s.apply(pose)
			var mf := minf(sk.get_bone_global_pose(feet[0]).origin.y, sk.get_bone_global_pose(feet[1]).origin.y)
			var mt := minf(sk.get_bone_global_pose(toes[0]).origin.y, sk.get_bone_global_pose(toes[1]).origin.y)
			lo_f = minf(lo_f, mf)
			hi_f = maxf(hi_f, mf)
			lo_t = minf(lo_t, mt)
		var a := s.clip_animation(c)
		var line := "%-16s lowest ankle %+.3f .. %+.3f  lowest toe %+.3f" % [c, lo_f - rest_foot, hi_f - rest_foot, lo_t - rest_toe]
		if a != null and a.has_meta(&"od_grip"):
			var rh := sk.find_bone("RightHand")
			var worn := String(c).ends_with("gauntlet")
			if not String(c).begins_with("light") and not String(c).begins_with("heavy"):
				print(line)
				continue
			var at := FeelRig.weapon_attach_transform(sk, rh, true, worn)
			var k := sk.get_bone_global_rest(sk.find_bone("Hips")).origin.y / FeelRig.REF_HIP_HEIGHT
			var worst := 0.0
			var worst_w := 1.0
			var worst_e := 1.0
			for f: float in [0.0, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1.0]:
				s.sample(c, f, pose)
				s.apply(pose)
				var g := sk.get_bone_global_pose(rh) * at
				var arc := FeelRig.arc_at(a, f)
				worst = maxf(worst, (arc[0] * k).distance_to(g.origin))
				worst_w = minf(worst_w, arc[1].dot(g.basis.y.normalized()))
				worst_e = minf(worst_e, arc[2].dot(g.basis.z.normalized()))
			line += "  | arc vs hand: grip off %.3f  w dot %.2f  e dot %.2f  (samples %d)" % [worst, worst_w, worst_e, (a.get_meta(&"od_grip") as PackedVector3Array).size()]
		print(line)
