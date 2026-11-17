extends ODTest
## The Moxie model integration (docs/GODOT-PORT.md asset contract): humanoid bone names with the
## stand-in's as fallbacks, clip binding (contract library over the .glb's clips, per-weapon
## combat-feel clips added), the per-style clip choice, the ranged weapon's forearm frame, and a
## real-model self wired by the actor layer. Headless; skips the real-model checks only if the model
## file is absent.

const MOXIE: String = "res://assets/models/moxie.glb"


func _real_rig() -> ActorRig:
	var r := ActorRig.new()
	r.setup(MOXIE, MoxieStandin.instance)
	return r


func test_bone_lookup_prefers_humanoid_names_then_standin_names() -> void:
	var st := MoxieStandin.instance()
	var sk := st.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	assert_eq(MoxieModel.find_bone(sk, MoxieModel.RIGHT_HAND), sk.find_bone("hand.R"), "stand-in right hand")
	assert_eq(MoxieModel.find_bone(sk, MoxieModel.LEFT_FOREARM), sk.find_bone("forearm.L"), "stand-in left forearm")
	assert_eq(MoxieModel.find_bone(sk, PackedStringArray(["NoSuchBone"])), -1, "missing bone is -1")
	assert_eq(MoxieModel.find_bone(null, MoxieModel.HEAD), -1, "no skeleton is -1")
	st.free()
	if not ResourceLoader.exists(MOXIE):
		return
	var r := _real_rig()
	assert_false(r.is_standin, "the real model loads")
	for names: PackedStringArray in [MoxieModel.RIGHT_HAND, MoxieModel.LEFT_HAND, MoxieModel.LEFT_FOREARM, MoxieModel.CHEST, MoxieModel.HEAD]:
		var i := MoxieModel.find_bone(r.skeleton, names)
		assert_true(i >= 0, "model has %s" % names[0])
		assert_eq(r.skeleton.get_bone_name(i), names[0], "humanoid name wins")
	r.free()


func _one_bone_lib(clip: StringName, bone: String, angle: float) -> AnimationLibrary:
	var a := Animation.new()
	a.length = 1.0
	var t := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(t, NodePath("Whatever:" + bone))
	a.rotation_track_insert_key(t, 0.0, Quaternion(Vector3.RIGHT, angle))
	a.rotation_track_insert_key(t, 1.0, Quaternion(Vector3.RIGHT, angle))
	var lib := AnimationLibrary.new()
	lib.add_animation(clip, a)
	return lib


func test_add_library_replace_semantics() -> void:
	var st := MoxieStandin.instance()
	var sk := st.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := st.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var s := ActorClipSampler.new(sk, player)
	var before := s.clip_animation(MoxieAnim.CLIP_IDLE)
	assert_true(before != null, "stand-in idle bound")
	var lib := _one_bone_lib(MoxieAnim.CLIP_IDLE, "head", 0.7)
	s.add_library(lib, false)
	assert_true(s.clip_animation(MoxieAnim.CLIP_IDLE) == before, "replace=false keeps the bound clip")
	s.add_library(lib, true)
	assert_true(s.clip_animation(MoxieAnim.CLIP_IDLE) == lib.get_animation(MoxieAnim.CLIP_IDLE), "replace=true overrides it")
	# Matched by bone name whatever the track root.
	var p := ActorClipSampler.Pose.new(s.bone_count)
	s.sample(MoxieAnim.CLIP_IDLE, 0.5, p)
	var head := sk.find_bone("head")
	assert_true(p.get_rot(head).is_equal_approx(Quaternion(Vector3.RIGHT, 0.7)), "the new clip drives the bone")
	s.add_library(_one_bone_lib(&"light_blade", "head", 0.2), false)
	assert_true(s.has_clip(&"light_blade"), "new names are added")
	assert_true(s.clip_names().has(&"light_blade"), "listed")
	s.add_library(null, true)
	assert_true(s.has_clip(&"light_blade"), "a null library is ignored")
	st.free()


func test_melee_and_ranged_clip_choice_falls_back() -> void:
	var st := MoxieStandin.instance()
	var sk := st.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := st.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var s := ActorClipSampler.new(sk, player)
	assert_eq(MoxieModel.melee_clips(s, "blade"), [&"light", &"heavy"] as Array[StringName], "no per-style clips: light / heavy")
	assert_eq(MoxieModel.ranged_clip(s, "missile"), &"ranged", "no per-archetype clip: ranged")
	s.add_library(_one_bone_lib(&"heavy_whip", "head", 0.2), false)
	s.add_library(_one_bone_lib(&"ranged_arc", "head", 0.2), false)
	assert_eq(MoxieModel.melee_clips(s, "whip"), [&"light", &"heavy_whip"] as Array[StringName], "each name falls back on its own")
	assert_eq(MoxieModel.ranged_clip(s, "arc"), &"ranged_arc")
	st.free()


func test_real_model_binds_contract_and_per_weapon_clips() -> void:
	if not ResourceLoader.exists(MOXIE):
		return
	var r := _real_rig()
	var t0 := Time.get_ticks_msec()
	MoxieModel.bind_clips(r.sampler)
	var first := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	MoxieModel.bind_clips(r.sampler)
	var second := Time.get_ticks_msec() - t0
	print("[test_actor_model] clip binding: first %d ms (bakes the combat-feel library), cached %d ms" % [first, second])
	for c: StringName in MoxieAnim.ALL_CLIPS:
		assert_true(r.sampler.has_clip(c), "contract clip %s" % c)
	if ResourceLoader.exists(MoxieModel.CONTRACT_LIBRARY):
		var lib := load(MoxieModel.CONTRACT_LIBRARY) as AnimationLibrary
		if ResourceLoader.exists(FeelRig.LIBRARY_PATH):
			# The animation director's library is the one in use: the contract library only fills in
			# for a clip it lacks.
			assert_true(r.sampler.clip_animation(&"idle") != lib.get_animation(&"idle"), "idle comes from the director's library, not the model's own set")
			assert_true(r.sampler.clip_animation(&"idle").has_meta(&"od_hip_height"), "idle is a director's clip")
		else:
			assert_true(r.sampler.clip_animation(&"idle") == lib.get_animation(&"idle"), "idle comes from the contract library, not the .glb")
		assert_near(r.sampler.clip_length(&"light"), 1.0, 1e-4, "one-shots are 1.0 s")
	if ResourceLoader.exists(FeelRig.LIBRARY_PATH):
		for style: String in FeelRig.STYLES:
			var mc := MoxieModel.melee_clips(r.sampler, style)
			assert_eq(mc[0], StringName("light_" + style), "per-weapon light clip for %s" % style)
			assert_eq(mc[1], StringName("heavy_" + style), "per-weapon heavy clip for %s" % style)
		assert_eq(MoxieModel.ranged_clip(r.sampler, "missile"), &"ranged_missile")
		assert_true(second <= first, "the baked library is cached")
	# Sampling a real clip is exact and reversible (seek, not playback).
	var a := ActorClipSampler.Pose.new(r.sampler.bone_count)
	var b := ActorClipSampler.Pose.new(r.sampler.bone_count)
	var clip := MoxieModel.melee_clips(r.sampler, "blade")[0]
	r.sampler.sample(clip, 0.5, a)
	r.sampler.sample(clip, 0.9, b)
	r.sampler.sample(clip, 0.5, b)
	var arm := r.skeleton.find_bone("RightUpperArm")
	assert_true(a.get_rot(arm).is_equal_approx(b.get_rot(arm)), "same position, same pose")
	r.sampler.sample(clip, 0.1, b)
	assert_false(a.get_rot(arm).is_equal_approx(b.get_rot(arm)), "wind-up differs from the hit")
	r.free()


func test_ranged_weapon_frame_on_the_left_forearm() -> void:
	if not ResourceLoader.exists(MOXIE):
		return
	var r := _real_rig()
	var sk := r.skeleton
	var fl := MoxieModel.find_bone(sk, MoxieModel.LEFT_FOREARM)
	var lh := MoxieModel.find_bone(sk, MoxieModel.LEFT_HAND)
	var local := MoxieModel.ranged_attach_transform(sk, fl, lh)
	var g := sk.get_bone_global_rest(fl) * local
	var to_hand := sk.get_bone_global_rest(lh).origin - sk.get_bone_global_rest(fl).origin
	assert_vec_near(g.basis.z.normalized(), to_hand.normalized(), 1e-4, "+Z (fire) runs along the forearm toward the hand")
	assert_near(g.basis.y.dot(g.basis.z), 0.0, 1e-4, "+Y is perpendicular to the forearm")
	assert_true(g.basis.y.y > 0.9, "+Y is up in the rest pose")
	assert_near(g.basis.determinant(), 1.0, 1e-4, "a proper rotation (no mirror, no scale)")
	var expect := sk.get_bone_global_rest(fl).origin + to_hand * MoxieModel.MOUNT_ALONG + g.basis.y * MoxieModel.MOUNT_LIFT
	assert_vec_near(g.origin, expect, 1e-4, "Mount 60% toward the wrist, on top of the forearm")
	r.free()


func test_ear_cups_are_measured_on_both_sides() -> void:
	if not ResourceLoader.exists(MOXIE):
		return
	var r := _real_rig()
	var cups := MoxieModel.ear_cups(r.skeleton, r.meshes)
	if MoxieModel.headphone_glow_names(r.meshes).is_empty():
		assert_eq(cups.size(), 2, "two cups")
		var head := r.skeleton.get_bone_global_rest(MoxieModel.find_bone(r.skeleton, MoxieModel.HEAD)).origin
		assert_true(cups[0].get_center().x > head.x + 0.05, "first cup on her left (+X)")
		assert_true(cups[1].get_center().x < head.x - 0.05, "second cup on her right (-X)")
		assert_near(cups[0].get_center().y, cups[1].get_center().y, 0.03, "cups level")
	r.free()


func _layer(loadout: ResolvedLoadout) -> ActorLayerBase:
	var layer := Facades.instance_actor_layer()
	tree().root.add_child(layer)
	var ctx := RenderCtx.new()
	ctx.palette = ThemePalette.new()
	ctx.loadout = loadout
	ctx.level = LevelDef.new()
	layer.load_level(ctx)
	return layer


func _loadout(overrides: Dictionary) -> ResolvedLoadout:
	var errors: Array[String] = []
	var cat := ContentData.load_gear(errors)
	var r := ResolvedLoadout.new()
	r.loadout = cat.base_loadout.copy()
	for slot: StringName in overrides:
		r.loadout.set_slot(slot, overrides[slot])
	for slot: StringName in GearSlot.ALL:
		var item := cat.get_item(r.loadout.get_slot(slot))
		if item == null:
			continue
		if item.look != null:
			r.looks[slot] = item.look
		if slot == GearSlot.MELEE and item.melee != null:
			r.melee = item.melee
		if slot == GearSlot.RANGED and item.ranged != null:
			r.ranged = item.ranged
	return r


static func _bone_of(n: Node) -> String:
	var p := n.get_parent()
	while p != null and not (p is BoneAttachment3D):
		p = p.get_parent()
	return (p as BoneAttachment3D).bone_name if p != null else ""


func test_self_view_wires_the_real_model() -> void:
	if not ResourceLoader.exists(MOXIE):
		return
	var layer := _layer(_loadout({GearSlot.MELEE: "speaker_knuckles", GearSlot.RANGED: "needle_rail"}))
	var v: SelfView = layer.get("selves")[0]
	assert_false(v.rig.is_standin, "real model")
	assert_eq(v.style, "gauntlet", "speaker_knuckles are gauntlets")
	if ResourceLoader.exists(FeelRig.LIBRARY_PATH):
		assert_eq(v.clip_for(AnimState.LIGHT_ACTIVE), &"light_gauntlet", "per-weapon light clip")
		assert_eq(v.clip_for(AnimState.HEAVY_WINDUP), &"heavy_gauntlet", "per-weapon heavy clip")
		assert_eq(v.clip_for(AnimState.RANGED), &"ranged_pierce", "per-archetype shot clip")
	assert_eq(v.clip_for(AnimState.DODGE), MoxieAnim.CLIP_DODGE, "other states use the contract clips")
	var hand: Node3D = v.get("_weapon_hand")
	var off: Node3D = v.get("_weapon_off")
	assert_true(hand != null and off != null, "a gauntlet on each fist")
	assert_eq(_bone_of(hand), "RightHand")
	assert_eq(_bone_of(off), "LeftHand")
	assert_true(v.get("_weapon_back") == null, "gauntlets have no stowed copy")
	var gr := hand.find_child("Gauntlet_L", true, false) as Node3D
	if gr != null:
		assert_false(gr.visible, "the right-hand copy hides the left gauntlet")
	var ranged: Node3D = v.get("_ranged_weapon")
	assert_true(ranged != null, "ranged weapon worn")
	assert_eq(_bone_of(ranged), "LeftLowerArm")
	var muzzle := v.get("_muzzle") as Node3D
	assert_eq(muzzle.get_parent().name, &"Muzzle", "flash sits on the weapon's Muzzle marker")
	# The model's own wrist device is hidden under the worn weapon; the rest is drawn.
	var mats: ActorMaterials = layer.get("mats")
	var body := v.rig.meshes[0]
	var hidden_seen := 0
	for i: int in body.mesh.get_surface_count():
		var n := String(ActorRig.surface_material_name(body, i))
		var is_dev := n.begins_with("device") or n.begins_with("screen_glow")
		var m := body.get_surface_override_material(i)
		if is_dev:
			hidden_seen += 1
			assert_true(m == mats.hidden, "%s hidden" % n)
		else:
			assert_true(m != mats.hidden, "%s drawn" % n)
	# A single-texture body has no separate wrist-device material to hide (the device is painted in).
	if not MoxieModel.wrist_device_names(v.rig.meshes).is_empty():
		assert_true(hidden_seen > 0, "the model's own wrist device is hidden")
	if MoxieModel.headphone_glow_names(v.rig.meshes).is_empty():
		assert_true(v.rig.find_children("HeadphoneGlow", "MeshInstance3D", true, false).size() == 1, "fitted headphone glow rings")
	layer.dispose()
	layer.queue_free()


func test_self_pose_is_a_function_of_the_snapshot_on_the_real_model() -> void:
	if not ResourceLoader.exists(MOXIE):
		return
	var lo := _loadout({})
	var layer := _layer(lo)
	var v: SelfView = layer.get("selves")[0]
	var dur := float(MoxieAnim.duration_ticks(AnimState.LIGHT_RECOVER, lo.melee, lo.ranged))
	assert_true(dur >= 2.0, "recover lasts a few ticks")
	var arm := v.rig.skeleton.find_bone("RightUpperArm")
	var poses: Array[Quaternion] = []
	# Light swing entered at tick 100; the same tick reached forwards and on a reverse pass (entered
	# at its recorded end) gives the same progress, hence the same clip position.
	for k: int in 3:
		var dir := 1 if k < 2 else -1
		var entry := 100.0 if dir == 1 else 100.0 + dur
		var tick := entry + dur * 0.5 * float(dir)
		var prev := FrameSnapshot.new()
		var snap := FrameSnapshot.new()
		for s: FrameSnapshot in [prev, snap]:
			var a := ActorSnap.new()
			a.tape = 0
			a.anim = AnimState.IDLE if s == prev else AnimState.LIGHT_RECOVER
			a.phase = TapePhase.make(entry if s == prev else entry, dir, k, false)
			s.actors.append(a)
		var rf := RenderFrame.new()
		rf.prev = prev
		rf.snap = snap
		rf.alpha = 1.0
		rf.dt = 1.0
		layer.update(rf, null)
		# advance within the state
		var snap2 := FrameSnapshot.new()
		var a2 := ActorSnap.new()
		a2.tape = 0
		a2.anim = AnimState.LIGHT_RECOVER
		a2.phase = TapePhase.make(tick, dir, k, false)
		snap2.actors.append(a2)
		var rf2 := RenderFrame.new()
		rf2.prev = snap
		rf2.snap = snap2
		rf2.alpha = 1.0
		rf2.dt = 1.0
		layer.update(rf2, null)
		poses.append(v.rig.skeleton.get_bone_pose_rotation(arm))
		if k < 2:
			assert_near(v.progress, 0.5, 1e-4, "forward pass: half the recover ticks")
		else:
			assert_near(v.progress, 0.5, 1e-4, "reverse pass: entered at the end, half the ticks back")
	assert_true(poses[0].is_equal_approx(poses[1]), "replaying the same ticks gives the same pose")
	assert_true(poses[0].is_equal_approx(poses[2]), "a reverse pass passes through the same pose")
	layer.dispose()
	layer.queue_free()
