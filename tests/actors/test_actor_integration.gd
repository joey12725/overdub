extends ODTest
## The actor layer's integration of the pieces built around it: the animation director's library on
## the shipping skeleton, combat feel driven by sim events, the wardrobe's looks on a single-texture
## body, the accessibility palette and non-colour identity, and telegraph sizes read from core.

const MOXIE: String = "res://assets/models/moxie.glb"


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


func _layer(loadout: ResolvedLoadout, enemy_id: String = "") -> ActorLayerBase:
	var layer := Facades.instance_actor_layer()
	tree().root.add_child(layer)
	var ctx := RenderCtx.new()
	ctx.palette = ThemePalette.new()
	ctx.loadout = loadout
	ctx.level = LevelDef.new()
	if enemy_id != "":
		var ed := EnemyDef.new()
		ed.kind = EntityKind.ENEMY
		ed.id = enemy_id
		ed.type = EnemyType.GRUNT
		ctx.level.entities.append(ed)
	layer.load_level(ctx)
	return layer


func _frame(anim: StringName, tick: float, enemy_id: String = "", ex: float = 1.0) -> FrameSnapshot:
	var s := FrameSnapshot.new()
	var a := ActorSnap.new()
	a.tape = 0
	a.anim = anim
	a.facing = 0.0
	a.phase = TapePhase.make(tick, 1, 0, false)
	s.actors.append(a)
	if enemy_id != "":
		var e := EnemySnap.new()
		e.id = enemy_id
		e.type = EnemyType.GRUNT
		e.x = ex
		e.max_hp = 3
		e.hp = 2
		e.state = EnemyStateName.STAGGER
		e.state_t = 0.2
		s.enemies.append(e)
	return s


func _step(layer: ActorLayerBase, prev: FrameSnapshot, snap: FrameSnapshot, events: Array[SimEvent] = []) -> void:
	var rf := RenderFrame.new()
	rf.prev = prev
	rf.snap = snap
	rf.alpha = 1.0
	rf.dt = 1.0 / 60.0
	rf.mode = ViewMode.RECORD
	rf.events = events
	layer.update(rf, null)


## Skeleton-space transform of a bone under `pose` (the test tree is not live, so Skeleton3D does
## not propagate global poses: walk the hierarchy by hand).
func _global(sk: Skeleton3D, pose: ActorClipSampler.Pose, bone: int) -> Transform3D:
	var g := Transform3D.IDENTITY
	var b := bone
	while b >= 0:
		g = Transform3D(Basis(pose.get_rot(b)) * Basis.from_scale(pose.scl[b]), pose.pos[b]) * g
		b = sk.get_bone_parent(b)
	return g


# ───────────────────────────── animation library ─────────────────────────────

func test_the_directors_library_is_the_one_bound() -> void:
	if not ResourceLoader.exists(MOXIE) or not ResourceLoader.exists(FeelRig.LIBRARY_PATH):
		return
	var r := ActorRig.new()
	r.setup(MOXIE, MoxieStandin.instance)
	MoxieModel.bind_clips(r.sampler)
	var src := load(FeelRig.LIBRARY_PATH) as AnimationLibrary
	for clip: StringName in src.get_animation_list():
		assert_true(r.sampler.has_clip(clip), "library clip %s is bound" % clip)
		var bound := r.sampler.clip_animation(clip)
		assert_true(bound != null and bound.has_meta(&"od_hip_height"), "%s is the director's clip, retargeted (not the model's own)" % clip)
		assert_true(bound != src.get_animation(clip), "%s is baked onto this skeleton, not the profile-space source" % clip)
	for flavour: StringName in [&"countin", &"win", &"resync"]:
		assert_true(r.sampler.has_clip(flavour), "flavour clip %s" % flavour)
	r.free()


func test_retargeted_clips_keep_the_feet_on_the_floor() -> void:
	if not ResourceLoader.exists(MOXIE) or not ResourceLoader.exists(FeelRig.LIBRARY_PATH):
		return
	var r := ActorRig.new()
	r.setup(MOXIE, MoxieStandin.instance)
	tree().root.add_child(r)
	MoxieModel.bind_clips(r.sampler)
	var sk := r.skeleton
	var feet: Array[int] = [sk.find_bone("LeftFoot"), sk.find_bone("RightFoot")]
	var rest := sk.get_bone_global_rest(feet[0]).origin.y
	var pose := ActorClipSampler.Pose.new(r.sampler.bone_count)
	# No clip sinks a foot into the floor (the retarget alone left them 1-3 cm under whenever the
	# knees bent), and the standing clips do not float either.
	var standing: Array[StringName] = [&"idle", &"stopped", &"ranged", &"interact"]
	for clip: StringName in r.sampler.clip_names():
		var lo := INF
		var hi := -INF
		for k: int in 31:
			r.sampler.sample(clip, float(k) / 30.0, pose)
			var low := minf(_global(sk, pose, feet[0]).origin.y, _global(sk, pose, feet[1]).origin.y)
			lo = minf(lo, low)
			hi = maxf(hi, low)
		assert_true(lo - rest > -0.004, "%s: the planted foot does not sink (%.3f)" % [clip, lo - rest])
		if standing.has(clip):
			assert_true(hi - rest < 0.012, "%s: the planted foot does not float (%.3f)" % [clip, hi - rest])
	r.queue_free()


func test_smear_arcs_follow_the_real_weapon_hand() -> void:
	if not ResourceLoader.exists(MOXIE) or not ResourceLoader.exists(FeelRig.LIBRARY_PATH):
		return
	var r := ActorRig.new()
	r.setup(MOXIE, MoxieStandin.instance)
	tree().root.add_child(r)
	MoxieModel.bind_clips(r.sampler)
	var sk := r.skeleton
	var rh := sk.find_bone("RightHand")
	var at := FeelRig.weapon_attach_transform(sk, rh, true, false)
	var k := sk.get_bone_global_rest(sk.find_bone("Hips")).origin.y / FeelRig.REF_HIP_HEIGHT
	var pose := ActorClipSampler.Pose.new(r.sampler.bone_count)
	for clip: StringName in [&"light_blade", &"heavy_blunt", &"heavy_polearm", &"light_shiv", &"heavy_whip", &"light_gauntlet"]:
		var a := r.sampler.clip_animation(clip)
		if clip == &"light_gauntlet":
			at = FeelRig.weapon_attach_transform(sk, rh, true, true)
		for f: float in [0.3, 0.4, 0.5, 0.6]:
			r.sampler.sample(clip, f, pose)
			var g := _global(sk, pose, rh) * at
			var arc := FeelRig.arc_at(a, f)
			assert_true((arc[0] * k).distance_to(g.origin) < 0.03, "%s @ %.1f: the arc's grip is in the real hand (%.3f off)" % [clip, f, (arc[0] * k).distance_to(g.origin)])
			assert_true(arc[1].dot(g.basis.y.normalized()) > 0.985, "%s @ %.1f: the arc points along the real weapon" % [clip, f])
	r.queue_free()


# ───────────────────────────── combat feel ─────────────────────────────

func test_a_hit_event_holds_the_swing_and_the_enemy() -> void:
	var lo := _loadout({})
	var layer := _layer(lo, "g")
	var feel: CombatFeel = layer.get("feel")
	assert_true(feel != null, "the layer owns a CombatFeel")
	assert_false(feel.auto_flash, "flashes go through the body shader")
	var v: SelfView = layer.get("selves")[0]
	var dur := float(MoxieAnim.duration_ticks(AnimState.LIGHT_ACTIVE, lo.melee, lo.ranged))
	var prev := _frame(AnimState.LIGHT_WINDUP, 100.0, "g")
	_step(layer, prev, prev)
	var snap := _frame(AnimState.LIGHT_ACTIVE, 101.0, "g")
	_step(layer, prev, snap)
	prev = snap
	snap = _frame(AnimState.LIGHT_ACTIVE, 101.0 + dur * 0.5, "g")
	var hit: Array[SimEvent] = [SimEvent.make(0, SimEventType.HIT, 1.0, 0.0).with_id("g").with_tape(0).with_power(5.0).with_dir(0.0)]
	_step(layer, prev, snap, hit)
	var held := v.shown_frac
	assert_true(feel.enemy_fx("g") != null, "the enemy is tracked")
	assert_true(feel.enemy_fx("g").hold.active, "the struck enemy is held")
	assert_true(feel.self_fx(0).hold.active, "the attacker is held")
	assert_eq(v.shown_clip, v.clip_light, "the swing clip is shown")
	if not v.rig.is_standin and ResourceLoader.exists(FeelRig.LIBRARY_PATH):
		assert_true(v.smear_on, "the smear draws during the swing")
	# The sim moves on (the swing recovers, the enemy is knocked back); the drawing stays on the
	# contact frame while the hold lasts.
	prev = snap
	snap = _frame(AnimState.LIGHT_RECOVER, 101.0 + dur + 1.0, "g", 1.4)
	_step(layer, prev, snap)
	assert_true(feel.self_fx(0).lag > 0.0, "still behind the sim")
	assert_eq(v.shown_clip, v.clip_light)
	assert_near(v.shown_frac, held, 0.06, "the drawn swing has barely moved off the contact frame")
	var ev: EnemyView = layer.call("enemy_view", "g")
	var body := ev.get("_body") as Node3D
	assert_true(body.position.x < -0.2, "the enemy body is drawn late: behind its snapshot position (%.2f)" % body.position.x)
	# ... and releases: after the hold and catch-up everything is back on the sim.
	for i: int in 40:
		prev = snap
		snap = _frame(AnimState.IDLE, 140.0 + float(i), "g", 1.4)
		_step(layer, prev, snap)
	assert_eq(feel.self_fx(0).lag, 0.0, "attacker caught up")
	assert_near(body.position.x, 0.0, 1e-4, "enemy drawn where the sim has it")
	assert_false(v.smear_on, "no smear outside a swing")
	layer.dispose()
	layer.queue_free()


func test_reduce_flashing_removes_the_impact_flash() -> void:
	var feel := CombatFeel.new()
	tree().root.add_child(feel)
	var node := Node3D.new()
	tree().root.add_child(node)
	feel.auto_flash = false
	feel.track_self(0, node, Color.WHITE, 1.0, "blade", 0.7)
	feel.track_enemy("g", node, 0.4, 1.2)
	var snap := FrameSnapshot.new()
	var e := EnemySnap.new()
	e.id = "g"
	snap.enemies.append(e)
	var hit: Array[SimEvent] = [SimEvent.make(0, SimEventType.HIT, 0.0, 0.0).with_id("g").with_tape(0).with_power(9.0).with_dir(0.0)]
	feel.update(hit, snap, 1.0 / 60.0)
	var ff := feel.flash_of(feel.enemy_fx("g"))
	assert_near(ff.x, 1.0, 1e-6, "a crush flashes the contact frame")
	assert_near(ff.y, 1.0, 1e-6, "inverted")
	feel.reduce_flashing = true
	assert_eq(feel.flash_of(feel.enemy_fx("g")), Vector2.ZERO, "no body flash under reduce flashing")
	assert_true(feel.bursts.max_size <= 1.0, "bursts are capped small")
	assert_true(feel.enemy_fx("g").hold.active, "the hold itself stays: it carries the hit without a flash")
	feel.reduce_flashing = false
	assert_true(feel.bursts.max_size > 100.0, "and the cap lifts again")
	feel.queue_free()
	node.queue_free()


# ───────────────────────────── identity and accessibility ─────────────────────────────

func test_cassette_identity_comes_from_the_accessibility_data() -> void:
	ActorOptions.cassette_set = AccessKit.SET_DEFAULT
	var layer := _layer(_loadout({}))
	var colors: PackedColorArray = layer.get("tape_colors")
	var want := AccessKit.colors(AccessKit.SET_DEFAULT)
	for i: int in OD.TAPE_COUNT:
		assert_true(colors[i].is_equal_approx(want[i]), "tape %d uses the measured colour" % i)
		var v: SelfView = layer.get("selves")[i]
		assert_true(v.color.is_equal_approx(want[i]))
	# Each floor ring is the cassette's own shape: four different outlines.
	var seen: Dictionary = {}
	for i: int in OD.TAPE_COUNT:
		var v: SelfView = layer.get("selves")[i]
		var ring := (v.get("_ring") as MeshInstance3D).mesh
		var verts: PackedVector3Array = ring.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var sig := "%d|%.3f" % [verts.size(), verts[verts.size() / 3].length()]
		assert_false(seen.has(sig), "ring %d has its own shape" % i)
		seen[sig] = true
		assert_eq((v.get("_letter") as Label3D).text, AccessKit.letter(i), "letter badge")
	layer.dispose()
	layer.queue_free()
	ActorOptions.cassette_set = AccessKit.SET_HIGH_CONTRAST
	assert_true(ActorOptions.tape_colors()[2].is_equal_approx(AccessKit.colors(AccessKit.SET_HIGH_CONTRAST)[2]), "the high-contrast set is selectable")
	ActorOptions.cassette_set = AccessKit.SET_DEFAULT


func test_options_read_settings_by_name() -> void:
	var st := SaveSettings.new()
	st.patterns = true
	ActorOptions.apply_settings(st)
	assert_true(ActorOptions.patterns, "an existing field is read")
	assert_false(ActorOptions.reduce_flashing, "a field SaveSettings does not have yet is left alone")
	ActorOptions.patterns = false


func test_states_stay_readable_without_flicker_or_colour() -> void:
	var r := ActorStyle.Resolved.new()
	# Reduce flashing: nothing flickers; i-frames are a steady translucency.
	for i: int in 50:
		ActorStyle.resolve(OD.LifeState.ALIVE, true, true, false, false, float(i) * 0.017, 0.0, r, true)
		assert_near(r.opacity, ActorStyle.IFRAME_OPACITY_STEADY, 1e-6)
		ActorStyle.resolve(OD.LifeState.ALIVE, false, false, false, false, float(i) * 0.017, 0.0, r, true)
		assert_near(r.flick, 1.0, 1e-6, "desync does not flicker")
	# I-frames differ from desync by the outline, not only by flicker.
	ActorStyle.resolve(OD.LifeState.ALIVE, true, true, false, false, 0.3, 0.0, r)
	var dodge_hull := ActorStyle.hull_color(r, Color.RED)
	ActorStyle.resolve(OD.LifeState.ALIVE, false, false, false, false, 0.3, 0.0, r)
	assert_false(dodge_hull.is_equal_approx(ActorStyle.hull_color(r, Color.RED)), "dodge outline is not the desync outline")
	assert_true(dodge_hull.is_equal_approx(ActorStyle.IFRAME_HULL))
	# A ghost's ring never fades below the floor.
	for id: StringName in ActorStyle.ALL:
		var life := OD.LifeState.GHOST if String(id).begins_with("ghost") else (OD.LifeState.REC_GHOST if String(id).begins_with("recGhost") else OD.LifeState.ALIVE)
		ActorStyle.resolve(life, not String(id).ends_with("esynced"), false, false, false, 0.0, 0.0, r)
		assert_true(r.ring >= ActorStyle.RING_FLOOR, "%s ring opacity" % id)


func test_self_outline_is_two_tier_and_slots_stay_unique() -> void:
	var mats := ActorMaterials.new()
	var pair: Array = mats.body_pair(Color.WHITE, false, false, null, false, true)
	var m: Material = pair[0]
	var shaders: Array[String] = []
	while m != null:
		shaders.append(((m as ShaderMaterial).shader.resource_path).get_file())
		m = m.next_pass
	assert_eq(shaders, ["actor_body.gdshader", "actor_ink.gdshader", "actor_outline.gdshader", "actor_xray.gdshader"] as Array[String], "body, ink line, cassette hull, x-ray")
	var plain: Array = mats.body_pair(Color.WHITE, false, false)
	assert_true((plain[0] as Material).next_pass == mats.outline, "enemies keep the single ink hull")
	# The ink line shares the hull's width slot and declares nothing else per instance.
	var src := FileAccess.get_file_as_string("res://actors/shaders/actor_ink.gdshader")
	assert_true(src.contains("instance uniform float outline_width : instance_index(11)"))
	assert_eq(src.count("instance uniform"), 1)


# ───────────────────────────── wardrobe ─────────────────────────────

func test_looks_recolour_outfit_zones_and_the_base_outfit_stays_painted() -> void:
	if not ResourceLoader.exists(MoxieModel.ZONE_TEX_A):
		return
	var base: Array[String] = []
	base.assign(MoxieModel.base_item_ids())
	assert_true(base.has("olive_cargos"), "the base loadout is read from the catalogue")
	assert_true(MoxieModel.outfit_zones(base) == null, "the base outfit is the painted model: nothing recoloured")
	var ids: Array[String] = ["lined_bomber", "parachute_pants", "beater_hightops"]
	var z := MoxieModel.outfit_zones(ids)
	assert_true(z != null and z.active(), "a non-base item recolours")
	var pants := MoxieModel.ZONE_NAMES.find(&"pants")
	var want := Color("#b14cff").srgb_to_linear()
	assert_near(z.tints[pants].a, 1.0, 1e-6, "pants zone on")
	assert_true(Color(z.tints[pants].r, z.tints[pants].g, z.tints[pants].b).is_equal_approx(Color(want.r, want.g, want.b)), "in the look's colour")
	for name: StringName in [&"top", &"jacket", &"jacket_lining", &"shoes"]:
		assert_near(z.tints[MoxieModel.ZONE_NAMES.find(name)].a, 0.0, 1e-6, "%s (base item) untouched" % name)
	assert_eq(z.lums.size(), 6)
	# Different looks are different materials; the same look is shared.
	var mats := ActorMaterials.new()
	var tex := load(MoxieModel.ZONE_TEX_A) as Texture2D
	var a: Array = mats.body_pair(Color.WHITE, false, false, tex, false, true, z)
	var b: Array = mats.body_pair(Color.WHITE, false, false, tex, false, true, MoxieModel.outfit_zones(ids))
	var c: Array = mats.body_pair(Color.WHITE, false, false, tex, false, true, null)
	assert_true(a[0] == b[0], "same look, same material")
	assert_true(a[0] != c[0], "painted base is its own material")


func test_headgear_rides_the_head_bone() -> void:
	if not ResourceLoader.exists(MOXIE):
		return
	var layer := _layer(_loadout({GearSlot.HELMET: "prism_goggles"}))
	var v: SelfView = layer.get("selves")[0]
	var gear := v.rig.skeleton.find_children("Headgear_*", "BoneAttachment3D", false, false)
	assert_eq(gear.size(), 1, "one headgear attachment")
	assert_eq((gear[0] as BoneAttachment3D).bone_name, "Head")
	assert_true(v.rig.find_children("HeadphoneGlow", "MeshInstance3D", true, false).size() == 1, "the headphone glow stays with headgear on")
	layer.dispose()
	layer.queue_free()


# ───────────────────────────── enemies ─────────────────────────────

func test_telegraph_sizes_are_read_from_core() -> void:
	var ar: float = Tuning.BASE.actor_radius
	for t: StringName in [EnemyType.GRUNT, EnemyType.STALKER, EnemyType.SHIELDER, EnemyType.BRUTE]:
		var st := Tuning.enemy_stats(t)
		assert_near(EnemySpecs.spec(t).reach, st.reach + ar, 1e-6, "%s reach" % t)
		assert_near(EnemySpecs.spec(t).radius, st.radius, 1e-6, "%s radius" % t)
	assert_near(EnemySpecs.spec(EnemyType.GRUNT).arc, GruntBehaviour.GRUNT_ARC, 1e-6)
	assert_near(EnemySpecs.spec(EnemyType.STALKER).arc, StalkerBehaviour.STALKER_ARC, 1e-6)
	assert_near(EnemySpecs.spec(EnemyType.SHIELDER).arc, ShielderBehaviour.SHIELDER_ARC, 1e-6)
	assert_near(EnemySpecs.spec(EnemyType.BRUTE).arc, BruteBehaviour.BRUTE_ARC, 1e-6)
	assert_near(EnemySpecs.spec(EnemyType.TURRET).length, Tuning.enemy_stats(EnemyType.TURRET).reach, 1e-6)
	assert_near(EnemySpecs.spec(EnemyType.DRONE).length, Tuning.enemy_stats(EnemyType.DRONE).reach, 1e-6)
	var boss := Tuning.enemy_stats(EnemyType.BOSS)
	assert_near(EnemySpecs.spec(EnemyType.BOSS).reach, boss.radius + boss.reach + ar, 1e-6)
	assert_near(EnemySpecs.spec(EnemyType.BOSS).arc, BossBehaviour.BOSS_CLEAVE_ARC, 1e-6)
	assert_eq(EnemySpecs.BOSS_SWEEP_RANGE, BossBehaviour.BOSS_SWEEP_RANGE)
	assert_eq(EnemySpecs.BOSS_RECALL_RADIUS, BossBehaviour.BOSS_RECALL_RADIUS)


func test_enemy_models_carry_their_clips() -> void:
	for t: StringName in [EnemyType.GRUNT, EnemyType.STALKER, EnemyType.TURRET, EnemyType.SHIELDER, EnemyType.BRUTE, EnemyType.DRONE, EnemyType.BOSS]:
		var path := EnemyView.MODEL_DIR + String(t) + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var r := ActorRig.new()
		r.setup(path, EnemyStandin.instance.bind(t))
		assert_false(r.is_standin, "%s uses its model" % t)
		for clip: StringName in [&"idle", &"telegraph", &"attack", &"stagger", &"death"]:
			assert_true(r.sampler.has_clip(clip), "%s has clip %s" % [t, clip])
		r.free()


# ───────────────────────────── flavour clips ─────────────────────────────

func test_flavour_clips_play_on_idle_living_selves_only() -> void:
	if not ResourceLoader.exists(MOXIE) or not ResourceLoader.exists(FeelRig.LIBRARY_PATH):
		return
	var layer := _layer(_loadout({}))
	var v: SelfView = layer.get("selves")[0]
	layer.call("set_flavour", SelfView.FLAVOUR_COUNTIN)
	var s := _frame(AnimState.IDLE, 10.0)
	_step(layer, s, s)
	assert_eq(v.get("_mode"), SelfView.FLAVOUR_COUNTIN, "idle + count-in flavour plays countin")
	var run := _frame(AnimState.RUN, 11.0)
	_step(layer, s, run)
	assert_eq(v.get("_mode"), AnimState.RUN, "a moving self is never overridden")
	layer.call("set_flavour", &"")
	# The win pose arrives by itself in the cinematic replay once the objective is complete.
	var won := _frame(AnimState.IDLE, 12.0)
	won.objective.complete = true
	var rf := RenderFrame.new()
	rf.prev = won
	rf.snap = won
	rf.dt = 1.0 / 60.0
	rf.mode = ViewMode.CINEMATIC
	layer.update(rf, null)
	assert_eq(v.get("_mode"), SelfView.FLAVOUR_WIN)
	layer.dispose()
	layer.queue_free()
