extends ODTest
## Pure logic of the combat-feel layer: momentum tiers, tape-speed tables, the visual hit-hold
## maths, smear ranges, clip naming, and the guarantee that feel/ cannot alter simulation time.


func test_tier_mapping_follows_momentum() -> void:
	assert_eq(FeelTune.tier_of(0.0), FeelTune.TIER_CLANG, "no momentum is a clang")
	assert_eq(FeelTune.tier_of(0.5), FeelTune.TIER_CLANG, "a 0.5x standing light (m = 0.5) is a clang")
	assert_eq(FeelTune.tier_of(0.999), FeelTune.TIER_CLANG, "just under one damage point")
	assert_eq(FeelTune.tier_of(1.0), FeelTune.TIER_LIGHT, "a 1x standing light")
	assert_eq(FeelTune.tier_of(1.99), FeelTune.TIER_LIGHT, "under 2")
	assert_eq(FeelTune.tier_of(2.0), FeelTune.TIER_SOLID, "a 2x light")
	assert_eq(FeelTune.tier_of(4.0), FeelTune.TIER_HEAVY, "a 4x light")
	assert_eq(FeelTune.tier_of(7.99), FeelTune.TIER_HEAVY, "under 8")
	assert_eq(FeelTune.tier_of(8.0), FeelTune.TIER_CRUSH, "8 and up")
	assert_eq(FeelTune.tier_of(16.8), FeelTune.TIER_CRUSH, "a running 4x sledge heavy")
	assert_eq(FeelTune.tier_of(16.8, true), FeelTune.TIER_CLANG, "a CLANG event is tier 0 whatever the momentum")
	assert_eq(FeelTune.tier_of(NAN), FeelTune.TIER_CLANG, "NaN momentum is a clang, not a crash")


func test_a_damaging_hit_is_never_presented_as_a_clang() -> void:
	# stylus_shiv light at 1x: momentum 0.85 but damageEff 1.3 -> one damage point, no CLANG event.
	assert_eq(FeelTune.hit_tier(0.85, false), FeelTune.TIER_LIGHT, "a HIT without a CLANG is at least light")
	assert_eq(FeelTune.hit_tier(0.85, true), FeelTune.TIER_CLANG, "the same swing that did nothing is a clang")
	assert_eq(FeelTune.hit_tier(5.0, false), FeelTune.TIER_HEAVY, "above 1 the momentum decides")
	assert_eq(FeelTune.hit_tier(12.0, true), FeelTune.TIER_CLANG, "a blocked crush is still a clang")


func test_tiers_are_monotonic_in_momentum() -> void:
	var prev := 0
	var m := 0.0
	while m < 20.0:
		var t := FeelTune.tier_of(m)
		assert_true(t >= prev, "tier never drops as momentum rises (m = %s)" % m)
		prev = t
		m += 0.05


func test_real_weapon_momenta_span_the_tiers() -> void:
	# Standing swings of the baseline blade at each tape speed, from the real tuning formula.
	var light := [0.5, 1.0, 2.0, 4.0]
	var want := [FeelTune.TIER_CLANG, FeelTune.TIER_LIGHT, FeelTune.TIER_SOLID, FeelTune.TIER_HEAVY]
	for i: int in 4:
		var m := Tuning.strike_momentum(1.0, 1.0, light[i], 0.0)
		assert_eq(FeelTune.tier_of(m), want[i], "blade light at %sx" % light[i])
	assert_eq(FeelTune.tier_of(Tuning.strike_momentum(2.8, 1.0, 4.0, 1.0)), FeelTune.TIER_CRUSH, "running 4x sledge heavy")


func test_tables_have_one_entry_per_tier_and_speed() -> void:
	for table: Array in [FeelTune.HOLD_VICTIM, FeelTune.HOLD_ATTACKER, FeelTune.CATCH_UP, FeelTune.SHAKE, FeelTune.PUNCH,
			FeelTune.FLASH_FRAMES, FeelTune.BURST_SIZE, FeelTune.BURST_LINES, FeelTune.BURST_LIFE, FeelTune.SQUASH,
			FeelTune.TILT, FeelTune.DUST_PER_TILE, FeelTune.TIER_NAMES]:
		assert_eq(table.size(), FeelTune.TIER_COUNT, "per-tier table size")
	for table: Array in [FeelTune.SPEED_HOLD, FeelTune.SPEED_SHAKE, FeelTune.SPEED_SMEAR_SPAN, FeelTune.SPEED_SMEAR_WEIGHT,
			FeelTune.SPEED_ECHOES, FeelTune.SPEED_BODY_GHOSTS, FeelTune.SPEED_DRAG]:
		assert_eq(table.size(), FeelTune.SPEEDS.size(), "per-speed table size")
	for style: String in FeelRig.STYLES:
		assert_true(FeelTune.STYLE_SMEAR_SPAN.has(style), "smear span for " + style)
		assert_true(FeelTune.STYLE_SMEAR_INNER.has(style), "smear inner for " + style)
		assert_true(FeelTune.STYLE_SMEAR_LOOK.has(style), "smear look for " + style)


func test_damaging_tiers_escalate_and_the_clang_is_dull() -> void:
	for t: int in range(2, FeelTune.TIER_COUNT):
		assert_true(FeelTune.HOLD_VICTIM[t] > FeelTune.HOLD_VICTIM[t - 1], "victim hold grows with tier")
		assert_true(FeelTune.SHAKE[t] > FeelTune.SHAKE[t - 1], "shake grows with tier")
		assert_true(FeelTune.BURST_SIZE[t] > FeelTune.BURST_SIZE[t - 1], "burst grows with tier")
		assert_true(FeelTune.SQUASH[t] > FeelTune.SQUASH[t - 1], "squash grows with tier")
	# The clang: smaller, weaker and quieter than the lightest real hit, but it jars the ATTACKER more.
	assert_true(FeelTune.SHAKE[0] < FeelTune.SHAKE[1], "a clang shakes less than a light hit")
	assert_true(FeelTune.BURST_SIZE[0] < FeelTune.BURST_SIZE[1], "a clang bursts smaller")
	assert_true(FeelTune.SQUASH[0] < FeelTune.SQUASH[1], "a clang barely deforms the target")
	assert_eq(FeelTune.PUNCH[0], 0.0, "a clang does not punch the camera")
	assert_true(FeelTune.HOLD_ATTACKER[0] > FeelTune.HOLD_ATTACKER[1], "a clang stops the weapon dead: longer attacker hold")


func test_speed_index_picks_the_nearest_offered_speed() -> void:
	assert_eq(FeelTune.speed_index(0.5), 0)
	assert_eq(FeelTune.speed_index(1.0), 1)
	assert_eq(FeelTune.speed_index(2.0), 2)
	assert_eq(FeelTune.speed_index(4.0), 3)
	assert_eq(FeelTune.speed_index(0.25), 0, "below the slowest clamps")
	assert_eq(FeelTune.speed_index(9.0), 3, "above the fastest clamps")
	assert_eq(FeelTune.speed_index(1.3), 1, "nearest in ratio")
	assert_eq(FeelTune.speed_index(0.0), 1, "a nonsense speed reads as 1x")


func test_tape_speeds_feel_different() -> void:
	# Slow tapes hold longer and smear deeper; fast tapes hold shorter and multi-ghost.
	assert_true(FeelTune.hold_victim(2, 0.5) > FeelTune.hold_victim(2, 1.0), "0.5x holds longer")
	assert_true(FeelTune.hold_victim(2, 4.0) < FeelTune.hold_victim(2, 2.0), "4x holds shortest")
	assert_true(FeelTune.smear_span("blade", false, 0.5) > FeelTune.smear_span("blade", false, 1.0), "0.5x smears longer")
	assert_true(FeelTune.smear_span("blade", true, 1.0) > FeelTune.smear_span("blade", false, 1.0), "heavies smear longer")
	assert_eq(FeelTune.SPEED_ECHOES[0], 0, "no echo blades at 0.5x")
	assert_eq(FeelTune.SPEED_ECHOES[1], 0, "no echo blades at 1x")
	assert_true(FeelTune.SPEED_ECHOES[3] > FeelTune.SPEED_ECHOES[2] and FeelTune.SPEED_ECHOES[2] > 0, "2x and 4x multi-ghost")
	assert_true(FeelTune.shake(3, 4.0) > FeelTune.shake(3, 1.0), "the same tier shakes harder on a fast tape")
	assert_true(FeelTune.shake(4, 4.0) <= 1.0, "shake is capped at 1")


func test_hold_lag_is_bounded_continuous_and_returns_to_zero() -> void:
	var hold := 0.11
	var catch := 0.12
	assert_eq(FeelHold.lag_at(-1.0, hold, catch), 0.0, "no lag before contact")
	assert_eq(FeelHold.lag_at(0.0, hold, catch), 0.0, "no lag at contact")
	assert_near(FeelHold.lag_at(0.05, hold, catch), 0.05, 1e-6, "frozen: the lag grows as fast as time")
	assert_near(FeelHold.lag_at(hold, hold, catch), hold, 1e-6, "full lag at the end of the hold")
	assert_eq(FeelHold.lag_at(hold + catch, hold, catch), 0.0, "caught up exactly")
	assert_eq(FeelHold.lag_at(5.0, hold, catch), 0.0, "and stays caught up")
	var prev := 0.0
	var t := 0.0
	while t < hold + catch + 0.05:
		var l := FeelHold.lag_at(t, hold, catch)
		assert_true(l >= 0.0, "the drawing never runs ahead of the sim (t = %s)" % t)
		assert_true(l <= hold + 1e-6, "the lag never exceeds the hold (t = %s)" % t)
		assert_true(absf(l - prev) <= 0.004, "continuous: no pop (t = %s, step %s)" % [t, absf(l - prev)])
		# Drawn time (t - lag) never goes backwards: a held actor freezes, it does not rewind.
		assert_true((t - l) >= (t - 0.001 - prev) - 1e-6, "drawn time is monotonic (t = %s)" % t)
		prev = l
		t += 0.001


func test_hold_object_freezes_then_releases() -> void:
	var h := FeelHold.new()
	assert_eq(h.lag(), 0.0, "idle hold has no lag")
	h.start(0.1, 0.1)
	h.advance(0.05)
	assert_true(h.frozen(), "frozen during the hold")
	assert_near(h.lag(), 0.05, 1e-6, "lag equals elapsed while frozen")
	h.advance(0.06)
	assert_false(h.frozen(), "released")
	assert_true(h.lag() > 0.0 and h.lag() < 0.1, "catching up")
	h.advance(0.2)
	assert_eq(h.lag(), 0.0, "caught up")
	assert_false(h.active, "finished")


func test_rehit_during_a_hold_never_rewinds_the_drawing() -> void:
	var h := FeelHold.new()
	h.start(0.15, 0.1)
	h.advance(0.1)
	var before := h.lag()
	h.start(0.05, 0.05)      # a weaker second hit must not shorten what is left of a longer hold
	assert_near(h.lag(), before, 1e-6, "a weaker re-hit leaves the hold alone")
	h.start(0.2, 0.1)        # a stronger one extends it from the lag already accumulated
	assert_near(h.lag(), before, 1e-6, "a stronger re-hit continues from the current lag")
	h.advance(0.05)
	assert_true(h.lag() > before, "and keeps holding")


func test_lag_ticks_scales_with_the_tape_rate() -> void:
	assert_near(FeelHold.lag_ticks(0.1, 60.0), 6.0, 1e-6, "0.1 s while recording is six local ticks")
	assert_near(FeelHold.lag_ticks(0.1, 240.0), 24.0, 1e-6, "0.1 s of a 4x tape in review is 24 local ticks")
	assert_eq(FeelHold.lag_ticks(-1.0, 60.0), 0.0, "never negative")


func test_smear_envelope_and_range() -> void:
	assert_eq(FeelTune.smear_envelope(0.1), 0.0, "no smear in the wind-up")
	assert_eq(FeelTune.smear_envelope(0.45), 1.0, "full smear through the hit window")
	assert_eq(FeelTune.smear_envelope(0.9), 0.0, "no smear late in the recovery")
	var fwd := FeelTune.smear_range(0.5, 0.1, 1)
	assert_near(fwd.x, 0.4, 1e-6, "forward: the tail trails behind")
	assert_near(fwd.y, 0.5, 1e-6, "forward: the head is the weapon")
	var rev := FeelTune.smear_range(0.5, 0.1, -1)
	assert_near(rev.x, 0.6, 1e-6, "reversed tape: the tail lies on the other side")
	assert_near(rev.y, 0.5, 1e-6, "reversed tape: the head is still the weapon")
	assert_near(FeelTune.smear_range(0.32, 0.2, 1).x, FeelTune.SMEAR_FROM, 1e-6, "the tail never reaches into the wind-up")


func test_clip_names_and_styles() -> void:
	assert_eq(FeelRig.style_for("splice_blade"), "blade")
	assert_eq(FeelRig.style_for("stylus_shiv"), "shiv")
	assert_eq(FeelRig.style_for("amp_sledge"), "blunt")
	assert_eq(FeelRig.style_for("reel_lash"), "whip")
	assert_eq(FeelRig.style_for("speaker_knuckles"), "gauntlet")
	assert_eq(FeelRig.style_for("vinyl_glaive"), "polearm")
	assert_eq(FeelRig.style_for("mystery", "blade", "glaive"), "polearm", "unknown item: by look variant")
	assert_eq(FeelRig.style_for("mystery", "whip", ""), "whip", "unknown item: by catalogue style")
	assert_eq(FeelRig.style_for("mystery"), "blade", "unknown item: blade")
	assert_eq(FeelRig.melee_clip(false, "blunt"), &"light_blunt")
	assert_eq(FeelRig.melee_clip(true, "polearm"), &"heavy_polearm")
	var none := func(_c: StringName) -> bool: return false
	assert_eq(FeelRig.melee_clip(true, "polearm", none), &"heavy", "falls back to the generic clip")
	assert_eq(FeelRig.ranged_clip("arc"), &"ranged_arc")
	assert_eq(FeelRig.ranged_clip("arc", none), &"ranged", "falls back to the generic clip")
	assert_true(FeelRig.is_two_handed("blunt") and FeelRig.is_two_handed("polearm") and not FeelRig.is_two_handed("blade"), "two-handed styles")


func test_gear_catalogue_styles_are_all_covered() -> void:
	var data: Dictionary = load_json("res://data/gear.json")
	for it: Dictionary in data["items"]:
		if it["slot"] == "melee":
			assert_true(FeelRig.STYLE_OF_ITEM.has(it["id"]), "melee item %s has a style" % it["id"])
		elif it["slot"] == "ranged":
			assert_true(FeelRig.ARCHETYPES.has(it["ranged"]["archetype"]), "ranged archetype %s has a clip" % it["ranged"]["archetype"])


func test_grip_basis_is_a_proper_rotation() -> void:
	for right: bool in [true, false]:
		for worn: bool in [true, false]:
			var b := FeelRig.grip_basis_model(right, worn)
			assert_near(b.determinant(), 1.0, 1e-5, "right-handed frame (right=%s worn=%s)" % [right, worn])
	# Held: the business end (+Y) leaves the fist forward, the edge (+Z) points along the knuckles.
	var held := FeelRig.grip_basis_model(true, false)
	assert_vec_near(held.y, Vector3(0, 0, 1), 1e-6, "weapon +Y is forward in the T-pose")
	assert_vec_near(held.z, Vector3(-1, 0, 0), 1e-6, "weapon +Z points out along the right arm")


func test_feel_scripts_cannot_touch_simulation_time() -> void:
	# The sim is deterministic and the music is locked to it: nothing under feel/ may pause the
	# tree, scale engine time, read a clock, use randomness, or reach into the simulation classes.
	var banned: Array[String] = ["Engine.time_scale", "get_tree().paused", ".paused =", "Engine.physics_ticks", "Time.get_",
		"OS.get_ticks", "randf", "randi", "ODSim", "ODTape", "resolve_encounter", "TapeRecorder", "process_mode", "OS.delay"]
	var dir := DirAccess.open("res://feel")
	assert_true(dir != null, "feel/ exists")
	var checked := 0
	for f: String in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		checked += 1
		var text := FileAccess.get_file_as_string("res://feel/" + f)
		var code := ""
		for line: String in text.split("\n"):
			var hash_at := line.find("#")
			code += (line.substr(0, hash_at) if hash_at >= 0 else line) + "\n"
		for b: String in banned:
			assert_false(code.contains(b), "feel/%s must not use %s" % [f, b])
	assert_true(checked >= 6, "scanned the feel scripts (%d)" % checked)


func test_combat_feel_never_mutates_events_or_snapshots() -> void:
	var feel := CombatFeel.new()
	tree().root.add_child(feel)
	var node := Node3D.new()
	tree().root.add_child(node)
	feel.track_self(0, node, Color.WHITE, 2.0, "blade", 0.7)
	feel.track_enemy("e1", node, 0.4, 1.2)
	var snap := FrameSnapshot.new()
	snap.sub = 480
	snap.beat = 2.0
	var a := ActorSnap.new()
	a.tape = 0
	a.x = 1.0
	a.y = 2.0
	a.anim = AnimState.LIGHT_ACTIVE
	snap.actors.append(a)
	var e := EnemySnap.new()
	e.id = "e1"
	e.x = 2.0
	e.y = 2.0
	e.hp = 3
	snap.enemies.append(e)
	var ev := SimEvent.make(480, SimEventType.HIT, 2.0, 2.0).with_id("e1").with_tape(0).with_power(4.0).with_dir(0.0).with_detail("light")
	var events: Array[SimEvent] = [ev]
	var ev_before := ev.to_dict()
	for i: int in 30:
		feel.update(events if i == 0 else ([] as Array[SimEvent]), snap, 1.0 / 60.0)
	assert_json_eq(ev.to_dict(), ev_before, 0.0, "the event is untouched")
	assert_eq(snap.sub, 480, "snapshot substep untouched")
	assert_eq(snap.beat, 2.0, "snapshot beat untouched")
	assert_eq(a.x, 1.0, "actor position untouched")
	assert_eq(e.x, 2.0, "enemy position untouched")
	assert_eq(e.hp, 3, "enemy hp untouched")
	assert_eq(Engine.time_scale, 1.0, "engine time scale untouched")
	assert_false(tree().paused, "tree not paused")
	feel.queue_free()
	node.queue_free()


func test_hit_holds_both_bodies_then_releases_them() -> void:
	var feel := CombatFeel.new()
	tree().root.add_child(feel)
	var node := Node3D.new()
	tree().root.add_child(node)
	feel.auto_flash = false
	feel.track_self(1, node, Color.WHITE, 1.0, "blunt", 0.9)
	feel.track_enemy("g", node, 0.4, 1.2)
	var snap := FrameSnapshot.new()
	var a := ActorSnap.new()
	a.tape = 1
	snap.actors.append(a)
	var e := EnemySnap.new()
	e.id = "g"
	e.x = 1.0
	snap.enemies.append(e)
	var none: Array[SimEvent] = []
	feel.update(none, snap, 1.0 / 60.0)
	assert_eq(feel.enemy_fx("g").lag, 0.0, "no lag before a hit")
	var hit: Array[SimEvent] = [SimEvent.make(0, SimEventType.HIT, 1.0, 0.0).with_id("g").with_tape(1).with_power(5.0).with_dir(0.0)]
	feel.update(hit, snap, 1.0 / 60.0)
	assert_eq(feel.enemy_fx("g").tier, FeelTune.TIER_HEAVY, "momentum 5 is a heavy hit")
	assert_true(feel.frame_shake > 0.0, "the hit asks for shake")
	# The enemy now slides away in the sim; the drawing must stay at the contact point while frozen.
	e.x = 1.6
	feel.update(none, snap, 1.0 / 60.0)
	var fx := feel.enemy_fx("g")
	assert_true(fx.frozen, "victim frozen on the frame after contact")
	assert_true(fx.lag > 0.0, "victim lags")
	assert_near(fx.pos.x, 1.0, 0.05, "victim is still drawn at the contact position")
	assert_true(feel.self_fx(1).lag > 0.0, "attacker lags too")
	assert_true(fx.is_deformed(), "victim is squashed")
	for i: int in 60:
		feel.update(none, snap, 1.0 / 60.0)
	assert_eq(fx.lag, 0.0, "victim caught up")
	assert_near(fx.pos.x, 1.6, 1e-4, "and is drawn where the sim has it")
	assert_eq(feel.self_fx(1).lag, 0.0, "attacker caught up")
	feel.queue_free()
	node.queue_free()


func test_clang_is_presented_as_tier_zero() -> void:
	var feel := CombatFeel.new()
	tree().root.add_child(feel)
	var node := Node3D.new()
	tree().root.add_child(node)
	feel.auto_flash = false
	feel.track_self(0, node, Color.WHITE, 0.5, "blade", 0.7)
	feel.track_enemy("g", node, 0.4, 1.2)
	var got: Array[int] = []
	feel.impact.connect(func(t: int, _at: Vector3, _d: Vector3) -> void: got.append(t))
	var snap := FrameSnapshot.new()
	var e := EnemySnap.new()
	e.id = "g"
	snap.enemies.append(e)
	var evs: Array[SimEvent] = [
		SimEvent.make(0, SimEventType.HIT, 0.0, 0.0).with_id("g").with_tape(0).with_power(0.5).with_dir(0.0),
		SimEvent.make(0, SimEventType.CLANG, 0.0, 0.0).with_id("g").with_tape(0).with_power(0.5).with_dir(0.0).with_detail("momentum"),
	]
	feel.update(evs, snap, 1.0 / 60.0)
	assert_eq(got.size(), 1, "HIT + CLANG is presented once")
	assert_eq(got[0], FeelTune.TIER_CLANG, "as a clang")
	assert_eq(feel.enemy_fx("g").flash, 0.0, "a clang does not flash the target white")
	# A blocked hit arrives as a lone CLANG and must still be presented.
	got.clear()
	var blocked: Array[SimEvent] = [SimEvent.make(4, SimEventType.CLANG, 0.0, 0.0).with_id("g").with_tape(0).with_power(6.0).with_dir(0.0).with_detail("shield")]
	feel.update(blocked, snap, 1.0 / 60.0)
	assert_eq(got.size(), 1, "a lone CLANG is presented")
	assert_eq(got[0], FeelTune.TIER_CLANG, "as tier 0 however hard it was swung")
	feel.queue_free()
	node.queue_free()


func test_ghosts_freeze_the_shipping_model_at_its_pose() -> void:
	# The afterimage of the real skinned Moxie: baked at the current pose under any renderer (the
	# headless one has no skeleton RIDs, so the engine bake is unavailable there) with no engine error.
	var scene := load("res://assets/models/moxie.glb") as PackedScene
	assert_true(scene != null, "moxie.glb")
	var body := scene.instantiate() as Node3D
	var ghosts := FeelGhosts.new()
	tree().root.add_child(body)
	tree().root.add_child(ghosts)
	if not body.is_inside_tree():
		await tree().process_frame
	var skel := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skinned: MeshInstance3D = null
	for n: Node in body.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).skin != null:
			skinned = n
			break
	assert_true(skinned != null, "a skinned mesh")
	assert_true(FeelGhosts.skeleton_of(skinned) == skel, "its skeleton is resolved")
	var rest := FeelGhosts.bake_pose(skinned)
	assert_true(rest != null and rest != skinned.mesh, "a baked copy, not the shared rest mesh")
	assert_eq(rest.get_surface_count(), skinned.mesh.get_surface_count(), "every surface baked")
	var hips := skel.find_bone("Hips")
	assert_true(hips >= 0, "Hips bone")
	skel.set_bone_pose_position(hips, skel.get_bone_pose_position(hips) + Vector3(0.0, 0.5, 0.0))
	var moved := FeelGhosts.bake_pose(skinned)
	var dy := moved.get_aabb().get_center().y - rest.get_aabb().get_center().y
	assert_true(dy > 0.05, "the ghost follows the pose (moved %.3f)" % dy)
	assert_near(moved.get_aabb().size.x, rest.get_aabb().size.x, 0.02, "and keeps its shape")
	# A detached copy (no resolvable skeleton path) still finds the rig above it.
	var copy := skinned.duplicate() as MeshInstance3D
	copy.skeleton = NodePath("")
	skel.add_child(copy)
	assert_true(FeelGhosts.skeleton_of(copy) == skel, "nearest skeleton ancestor")
	assert_true(FeelGhosts.bake_pose(copy).get_aabb().is_equal_approx(moved.get_aabb()), "same pose from the copy")
	copy.free()
	var count := ghosts.spawn(body, Color.WHITE)
	assert_true(count > 0, "ghosts spawned")
	assert_eq(ghosts.active(), count, "and visible")
	ghosts.advance(10.0)
	assert_eq(ghosts.active(), 0, "then gone")
	body.queue_free()
	ghosts.queue_free()
