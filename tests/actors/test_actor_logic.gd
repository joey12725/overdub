extends ODTest
## Actor layer logic (headless): interpolation helpers, the state -> style table, animation
## progress mapping (UI-03, GHOST-01, DESYNC-06, TIME-03).


func _actor(tape: int, x: float, y: float, facing: float, tick: float, traversal: int = 0) -> ActorSnap:
	var a := ActorSnap.new()
	a.tape = tape
	a.x = x
	a.y = y
	a.facing = facing
	a.phase = TapePhase.make(tick, 1, traversal, false)
	return a


func _melee() -> MeleeWeaponDef:
	var m := MeleeWeaponDef.new()
	m.light.windup = 6.0
	m.light.active = 3.4
	m.light.recover = 8.0
	m.heavy.windup = 14.0
	m.heavy.active = 0.2
	m.heavy.recover = 16.0
	return m


# ───────────────────────────── math ─────────────────────────────

func test_wrap_and_shortest_arc() -> void:
	assert_near(ActorMath.wrap_angle(3.0 * PI), PI, 1e-5, "3pi wraps to pi")
	assert_near(ActorMath.wrap_angle(-PI), PI, 1e-5, "-pi wraps to +pi (half-open)")
	assert_near(ActorMath.wrap_angle(0.25), 0.25, 1e-6)
	# Across the +-pi seam the short way is 0.2 rad, not 2pi - 0.2.
	var a := PI - 0.1
	var b := -PI + 0.1
	assert_near(ActorMath.angle_delta(a, b), 0.2, 1e-5, "delta across the seam")
	var mid := ActorMath.lerp_angle_short(a, b, 0.5)
	assert_near(absf(mid), PI, 1e-5, "midpoint across the seam is pi, not 0")
	assert_near(ActorMath.lerp_angle_short(0.0, 1.0, 0.25), 0.25, 1e-6)
	assert_eq(ActorMath.wrap_angle(INF), 0.0, "non-finite angles wrap to 0")


func test_flicker_is_three_level_and_deterministic() -> void:
	var seen := {}
	for i: int in 400:
		var v := ActorMath.flicker_value(float(i) * 0.013, 2.5)
		seen[v] = true
		assert_eq(v, ActorMath.flicker_value(float(i) * 0.013, 2.5), "same inputs, same value")
	assert_true(seen.has(1.0) and seen.has(0.55) and seen.has(0.1), "hard stutter uses all three levels")
	assert_eq(seen.size(), 3, "never a smooth pulse")


func test_hash_is_stable() -> void:
	assert_eq(ActorMath.hash_string("grunt_1"), ActorMath.hash_string("grunt_1"))
	assert_ne(ActorMath.hash_string("grunt_1"), ActorMath.hash_string("grunt_2"))
	var h := ActorMath.hash01(17.0)
	assert_true(h >= 0.0 and h < 1.0)


# ───────────────────────────── interpolation ─────────────────────────────

func test_interp_actor_lerps_position_tick_and_shortest_facing() -> void:
	var p := _actor(1, 2.0, 3.0, PI - 0.1, 10.0)
	var c := _actor(1, 3.0, 5.0, -PI + 0.1, 12.0)
	var out := ActorInterp.SelfFrame.new()
	ActorInterp.interp_actor(p, c, 0.5, out)
	assert_near(out.x, 2.5, 1e-6)
	assert_near(out.y, 4.0, 1e-6)
	assert_near(out.tick, 11.0, 1e-6)
	assert_near(absf(out.facing), PI, 1e-5, "facing takes the short way through pi")
	assert_false(out.teleported)
	# alpha is clamped.
	ActorInterp.interp_actor(p, c, 7.0, out)
	assert_near(out.x, 3.0, 1e-6)
	ActorInterp.interp_actor(p, c, -1.0, out)
	assert_near(out.x, 2.0, 1e-6)


func test_interp_actor_discrete_fields_come_from_newer_snapshot() -> void:
	var p := _actor(0, 0, 0, 0, 0)
	p.anim = AnimState.RUN
	var c := _actor(0, 0.1, 0, 0, 1)
	c.anim = AnimState.LIGHT_WINDUP
	c.life = OD.LifeState.GHOST
	c.synced = false
	c.iframes = true
	c.live = true
	var out := ActorInterp.SelfFrame.new()
	ActorInterp.interp_actor(p, c, 0.1, out)
	assert_eq(out.anim, AnimState.LIGHT_WINDUP)
	assert_eq(out.life, OD.LifeState.GHOST)
	assert_false(out.synced)
	assert_true(out.iframes)
	assert_true(out.live)


func test_interp_actor_repeat_cut_teleports() -> void:
	# A 'repeat' tape cuts back to sample 0: traversal changes, so the projection snaps.
	var p := _actor(2, 9.0, 9.0, 1.0, 95.0, 0)
	var c := _actor(2, 9.2, 9.0, 0.0, 1.0, 1)
	var out := ActorInterp.SelfFrame.new()
	ActorInterp.interp_actor(p, c, 0.3, out)
	assert_true(out.teleported, "traversal change is a cut")
	assert_near(out.x, 9.2, 1e-6, "snapped to the new position")
	assert_near(out.tick, 1.0, 1e-6, "tick is not blended across the cut")
	assert_near(out.facing, 0.0, 1e-6)
	# A long jump within one traversal is a cut too.
	var far := _actor(2, 9.0 + ActorInterp.TELEPORT_DIST + 0.5, 9.0, 0.0, 96.0, 0)
	ActorInterp.interp_actor(p, far, 0.5, out)
	assert_true(out.teleported, "a jump beyond TELEPORT_DIST is a cut")
	# A normal step is not.
	var near := _actor(2, 9.3, 9.0, 0.0, 96.0, 0)
	ActorInterp.interp_actor(p, near, 0.5, out)
	assert_false(out.teleported)
	# No previous snapshot: draw the current one.
	ActorInterp.interp_actor(null, near, 0.5, out)
	assert_false(out.teleported)
	assert_near(out.x, 9.3, 1e-6)


func test_interp_spark_never_teleports() -> void:
	var p := _actor(3, 1.0, 1.0, 0.0, 50.0, 0)
	p.synced = false
	p.has_spark = true
	p.spark = Vector2(4.0, 4.0)
	var c := _actor(3, 8.0, 1.0, 0.0, 2.0, 1)
	c.synced = false
	c.has_spark = true
	c.spark = Vector2(5.0, 4.0)
	var out := ActorInterp.SelfFrame.new()
	ActorInterp.interp_actor(p, c, 0.5, out)
	assert_true(out.teleported, "the projection cut")
	assert_true(out.has_spark)
	assert_near(out.spark_x, 4.5, 1e-6, "the spark still travels (interpolated)")
	# Spark appearing: no blend from nowhere.
	p.has_spark = false
	ActorInterp.interp_actor(p, c, 0.5, out)
	assert_near(out.spark_x, 5.0, 1e-6)
	c.has_spark = false
	ActorInterp.interp_actor(p, c, 0.5, out)
	assert_false(out.has_spark)


func test_interp_enemy_state_t_and_cut() -> void:
	var p := EnemySnap.new()
	p.id = "g"
	p.state = EnemyStateName.TELEGRAPH
	p.state_t = 0.2
	var c := p.copy()
	c.state_t = 0.6
	c.x = 1.0
	var out := ActorInterp.EnemyFrame.new()
	ActorInterp.interp_enemy(p, c, 0.5, out)
	assert_near(out.state_t, 0.4, 1e-6, "state_t blends within one state")
	assert_near(out.x, 0.5, 1e-6)
	c.state = EnemyStateName.ATTACK
	c.state_t = 0.05
	ActorInterp.interp_enemy(p, c, 0.5, out)
	assert_near(out.state_t, 0.05, 1e-6, "across a state change take the new value")
	# Knockback is continuous; only a far larger jump is a cut.
	c.x = ActorInterp.TELEPORT_DIST * 1.5
	ActorInterp.interp_enemy(p, c, 0.5, out)
	assert_false(out.teleported, "knockback-sized jumps blend")
	c.x = ActorInterp.ENEMY_TELEPORT_DIST + 1.0
	ActorInterp.interp_enemy(p, c, 0.5, out)
	assert_true(out.teleported)
	# Boss recall fields only while recalling.
	c.boss_recall = false
	c.boss_recall_tape = 2
	ActorInterp.interp_enemy(p, c, 0.5, out)
	assert_eq(out.recall_tape, -1)
	c.boss_recall = true
	c.has_boss_recall_at = true
	c.boss_recall_at = Vector2(3, 4)
	ActorInterp.interp_enemy(p, c, 0.5, out)
	assert_eq(out.recall_tape, 2)
	assert_true(out.has_recall_at)
	assert_near(out.recall_y, 4.0, 1e-6)


func test_interp_projectile_and_lookups() -> void:
	var p := ProjectileSnap.new()
	p.id = 7
	p.dir = PI - 0.05
	var c := p.copy()
	c.x = 2.0
	c.z = 1.0
	c.dir = -PI + 0.05
	var out := ActorInterp.ShotFrame.new()
	ActorInterp.interp_projectile(p, c, 0.5, out)
	assert_near(out.x, 1.0, 1e-6)
	assert_near(out.z, 0.5, 1e-6)
	assert_near(absf(out.dir), PI, 1e-5)
	assert_false(out.fresh)
	ActorInterp.interp_projectile(null, c, 0.5, out)
	assert_true(out.fresh, "first sample is fresh")
	var list: Array[ProjectileSnap] = [ProjectileSnap.new(), c]
	assert_eq(ActorInterp.find_projectile(list, 7, 1), c, "hinted hit")
	assert_eq(ActorInterp.find_projectile(list, 7, 0), c, "hint miss falls back to a scan")
	assert_eq(ActorInterp.find_projectile(list, 99, 0), null)
	var actors: Array[ActorSnap] = [_actor(2, 0, 0, 0, 0), _actor(0, 0, 0, 0, 0)]
	assert_eq(ActorInterp.find_actor(actors, 0, 0), actors[1])
	assert_eq(ActorInterp.find_actor(actors, 3, 0), null)


# ───────────────────────────── style table ─────────────────────────────

func test_ui_03_every_life_sync_combination_is_distinct() -> void:
	var ids: Array[StringName] = []
	var sigs: Array = []
	for life: int in [OD.LifeState.ALIVE, OD.LifeState.REC_GHOST, OD.LifeState.GHOST]:
		for synced: bool in [true, false]:
			var id := ActorStyle.select(life, synced)
			assert_false(ids.has(id), "style id %s is unique" % id)
			ids.append(id)
			var sig := ActorStyle.params(id).signature()
			for other: Array in sigs:
				assert_false(other == sig, "style %s differs from every other style" % id)
			sigs.append(sig)
	assert_eq(ids.size(), 6)
	assert_eq(ActorStyle.ALL.size(), 6)


func test_ghost_01_readings_are_the_intended_treatments() -> void:
	var rec := ActorStyle.params(ActorStyle.REC_GHOST)
	assert_eq(rec.body, ActorStyle.Body.HOLO, "recording ghost: hologram")
	assert_eq(rec.marker, ActorStyle.Marker.BROKEN_HALO, "recording ghost: broken halo")
	assert_true(rec.hull_tape_color, "recording ghost keeps the cassette colour")
	var ghost := ActorStyle.params(ActorStyle.GHOST)
	assert_eq(ghost.body, ActorStyle.Body.HOLLOW, "playback ghost: hollow")
	assert_false(ghost.hull_tape_color, "playback ghost: grey outline")
	assert_near(ghost.opacity, 0.0, 1e-6, "outline only")
	var des := ActorStyle.params(ActorStyle.DESYNCED)
	assert_eq(des.body, ActorStyle.Body.PHASED, "desynced: phased projection")
	assert_true(des.chroma > 0.0, "desynced: chromatic split")
	assert_true(des.flicker > 0.0, "desynced: flicker")
	assert_true(des.tether, "desynced: tether to the spark")
	assert_false(ActorStyle.params(ActorStyle.ALIVE).tether)
	# Desync layered on a death reading keeps the death body, adds the tether.
	assert_eq(ActorStyle.params(ActorStyle.GHOST_DESYNCED).body, ActorStyle.Body.HOLLOW)
	assert_true(ActorStyle.params(ActorStyle.GHOST_DESYNCED).tether)
	assert_eq(ActorStyle.params(ActorStyle.REC_GHOST_DESYNCED).body, ActorStyle.Body.HOLO)
	assert_true(ActorStyle.params(ActorStyle.REC_GHOST_DESYNCED).tether)


func test_resolve_layers_iframes_stopped_and_dying() -> void:
	var r := ActorStyle.Resolved.new()
	ActorStyle.resolve(OD.LifeState.ALIVE, true, false, false, false, 1.0, 0.0, r)
	assert_false(r.translucent, "a living synced self is solid")
	assert_near(r.opacity, 1.0, 1e-6)
	# Dodge i-frames: translucent, flickering between the two levels, never fully solid.
	var levels := {}
	for i: int in 200:
		ActorStyle.resolve(OD.LifeState.ALIVE, true, true, false, false, float(i) * 0.017, 0.0, r)
		assert_true(r.translucent and r.dodging)
		levels[r.opacity] = true
	assert_true(levels.has(ActorStyle.IFRAME_OPACITY_LOW) and levels.has(ActorStyle.IFRAME_OPACITY_HIGH))
	assert_eq(levels.size(), 2)
	# Stopped: desaturated, outline greyed.
	ActorStyle.resolve(OD.LifeState.ALIVE, true, false, true, false, 1.0, 0.0, r)
	assert_near(r.desat, ActorStyle.STOPPED_DESAT, 1e-6)
	assert_true(r.stopped)
	var hc := ActorStyle.hull_color(r, Color(1, 0, 0))
	assert_true(hc.g > 0.05 and hc.r < 1.0, "stopped outline is greyed")
	# The death transition shows the solid reading even if the snapshot already says ghost.
	ActorStyle.resolve(OD.LifeState.GHOST, true, false, false, true, 1.0, 0.0, r)
	assert_eq(r.style, ActorStyle.ALIVE)
	ActorStyle.resolve(OD.LifeState.GHOST, true, false, false, false, 1.0, 0.0, r)
	assert_eq(r.style, ActorStyle.GHOST)
	assert_true(r.translucent)
	assert_eq(ActorStyle.hull_color(r, Color(1, 0, 0)), ActorStyle.GHOST_GREY, "playback ghost outline is grey")


# ───────────────────────────── animation progress ─────────────────────────────

func test_time_03_progress_is_scrubbed_by_local_ticks() -> void:
	var m := _melee()
	var r := RangedWeaponDef.new()
	r.commit = 9.6
	assert_eq(MoxieAnim.duration_ticks(AnimState.LIGHT_WINDUP, m, r), 6)
	assert_eq(MoxieAnim.duration_ticks(AnimState.LIGHT_ACTIVE, m, r), 3, "ticksOf rounds")
	assert_eq(MoxieAnim.duration_ticks(AnimState.HEAVY_ACTIVE, m, r), 1, "at least one tick")
	assert_eq(MoxieAnim.duration_ticks(AnimState.RANGED, m, r), 10)
	assert_eq(MoxieAnim.duration_ticks(AnimState.DODGE, m, r), MoxieAnim.DODGE_TICKS)
	assert_eq(MoxieAnim.duration_ticks(AnimState.INTERACT, m, r), MoxieAnim.INTERACT_TICKS)
	assert_eq(MoxieAnim.duration_ticks(AnimState.IDLE, m, r), 0)
	assert_eq(MoxieAnim.duration_ticks(AnimState.STOPPED, m, r), 0)
	# Same local ticks, same shape - whatever the tape speed (master time is not an input).
	assert_near(MoxieAnim.progress(100.0, 103.0, 1, 6), 0.5, 1e-6)
	assert_near(MoxieAnim.progress(100.0, 106.0, 1, 6), 1.0, 1e-6)
	assert_near(MoxieAnim.progress(100.0, 120.0, 1, 6), 1.0, 1e-6, "clamped")
	assert_eq(MoxieAnim.progress(100.0, 103.0, 1, 0), 0.0, "untimed states have no progress")


func test_reverse_pass_rewinds() -> void:
	# On a reverse pass the state is entered at its recorded end: progress runs 1 -> 0.
	assert_near(MoxieAnim.progress(106.0, 106.0, -1, 6), 1.0, 1e-6)
	assert_near(MoxieAnim.progress(106.0, 104.5, -1, 6), 0.75, 1e-6)
	assert_near(MoxieAnim.progress(106.0, 100.0, -1, 6), 0.0, 1e-6)
	# The clip position follows, so the swing visibly rewinds.
	var fwd := MoxieAnim.clip_fraction(AnimState.LIGHT_ACTIVE, MoxieAnim.progress(100.0, 101.5, 1, 3))
	var rev := MoxieAnim.clip_fraction(AnimState.LIGHT_ACTIVE, MoxieAnim.progress(103.0, 101.5, -1, 3))
	assert_near(fwd, rev, 1e-6, "the same recorded tick shows the same pose either way")


func test_clip_mapping_uses_the_40_20_40_split() -> void:
	assert_eq(MoxieAnim.clip_for(AnimState.LIGHT_WINDUP), MoxieAnim.CLIP_LIGHT)
	assert_eq(MoxieAnim.clip_for(AnimState.HEAVY_RECOVER), MoxieAnim.CLIP_HEAVY)
	assert_eq(MoxieAnim.clip_for(AnimState.DODGE), MoxieAnim.CLIP_DODGE)
	assert_eq(MoxieAnim.clip_for(AnimState.STOPPED), MoxieAnim.CLIP_STOPPED)
	assert_eq(MoxieAnim.clip_for(AnimState.RUN), MoxieAnim.CLIP_RUN)
	assert_eq(MoxieAnim.clip_for(AnimState.IDLE), MoxieAnim.CLIP_IDLE)
	for a: StringName in AnimState.ALL:
		assert_true(MoxieAnim.ALL_CLIPS.has(MoxieAnim.clip_for(a)), "%s maps to a contract clip" % a)
	assert_near(MoxieAnim.clip_fraction(AnimState.LIGHT_WINDUP, 0.0), 0.0, 1e-6)
	assert_near(MoxieAnim.clip_fraction(AnimState.LIGHT_WINDUP, 1.0), 0.4, 1e-6)
	assert_near(MoxieAnim.clip_fraction(AnimState.HEAVY_ACTIVE, 0.0), 0.4, 1e-6)
	assert_near(MoxieAnim.clip_fraction(AnimState.HEAVY_ACTIVE, 0.5), 0.5, 1e-6)
	assert_near(MoxieAnim.clip_fraction(AnimState.HEAVY_ACTIVE, 1.0), 0.6, 1e-6)
	assert_near(MoxieAnim.clip_fraction(AnimState.LIGHT_RECOVER, 1.0), 1.0, 1e-6)
	assert_near(MoxieAnim.clip_fraction(AnimState.DODGE, 0.3), 0.3, 1e-6)
	assert_near(MoxieAnim.clip_fraction(AnimState.RANGED, 2.0), 1.0, 1e-6, "clamped")
	# Melee phases chain without gaps: the end of one phase is the start of the next.
	assert_near(MoxieAnim.clip_fraction(AnimState.LIGHT_WINDUP, 1.0), MoxieAnim.clip_fraction(AnimState.LIGHT_ACTIVE, 0.0), 1e-6)
	assert_near(MoxieAnim.clip_fraction(AnimState.LIGHT_ACTIVE, 1.0), MoxieAnim.clip_fraction(AnimState.LIGHT_RECOVER, 0.0), 1e-6)


func test_run_cycle_and_blend_weight() -> void:
	assert_near(MoxieAnim.run_fraction(0.0), 0.0, 1e-6)
	assert_near(MoxieAnim.run_fraction(MoxieAnim.STRIDE_TILES * 0.25), 0.25, 1e-5)
	assert_near(MoxieAnim.run_fraction(MoxieAnim.STRIDE_TILES * 3.5), 0.5, 1e-5)
	assert_near(MoxieAnim.run_fraction(-MoxieAnim.STRIDE_TILES * 0.25), 0.75, 1e-5, "running backwards wraps")
	assert_near(MoxieAnim.run_weight(0.0), 0.0, 1e-6, "standing: all idle")
	assert_near(MoxieAnim.run_weight(MoxieAnim.RUN_SPEED), 1.0, 1e-6, "full run: all run")
	var w := MoxieAnim.run_weight(MoxieAnim.RUN_SPEED * 0.3)
	assert_true(w > 0.0 and w < 1.0, "in between blends")


func test_clip_sampler_is_exact_and_reversible() -> void:
	# The stand-in rig has the contract clips; sampling is a pure function of the clip position.
	var rig := MoxieStandin.instance()
	var skel := rig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := rig.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var s := ActorClipSampler.new(skel, player)
	for clip: StringName in MoxieAnim.ALL_CLIPS:
		assert_true(s.has_clip(clip), "stand-in has clip %s" % clip)
	assert_near(s.clip_length(MoxieAnim.CLIP_IDLE), 2.0, 1e-6)
	assert_near(s.clip_length(MoxieAnim.CLIP_RUN), 0.6, 1e-6)
	assert_near(s.clip_length(MoxieAnim.CLIP_LIGHT), 1.0, 1e-6)
	var a := ActorClipSampler.Pose.new(s.bone_count)
	var b := ActorClipSampler.Pose.new(s.bone_count)
	s.sample(MoxieAnim.CLIP_HEAVY, 0.45, a)
	s.sample(MoxieAnim.CLIP_HEAVY, 0.9, b)
	s.sample(MoxieAnim.CLIP_HEAVY, 0.45, b)
	var arm := skel.find_bone("upper_arm.R")
	assert_true(a.get_rot(arm).is_equal_approx(b.get_rot(arm)), "re-sampling the same time gives the same pose")
	s.sample(MoxieAnim.CLIP_HEAVY, 0.1, b)
	assert_false(a.get_rot(arm).is_equal_approx(b.get_rot(arm)), "wind-up and hit poses differ")
	# Blend endpoints.
	var o := ActorClipSampler.Pose.new(s.bone_count)
	ActorClipSampler.blend(a, b, 0.0, o)
	assert_true(absf(o.get_rot(arm).dot(a.get_rot(arm))) > 0.9999, "blend 0 = a (same rotation)")
	ActorClipSampler.blend(a, b, 1.0, o)
	assert_true(absf(o.get_rot(arm).dot(b.get_rot(arm))) > 0.9999, "blend 1 = b (same rotation)")
	ActorClipSampler.blend(a, b, 0.5, o)
	var half := absf(o.get_rot(arm).dot(a.get_rot(arm)))
	assert_true(half < 0.9999, "blend 0.5 is between")
	assert_false(s.sample(&"no_such_clip", 0.5, o), "missing clip reports false")
	rig.free()


func test_enemy_specs_match_sim_reaches() -> void:
	var g := EnemySpecs.spec(EnemyType.GRUNT)
	assert_eq(g.shape, EnemySpecs.SHAPE_CONE)
	assert_near(g.reach, 1.2, 1e-6, "grunt reach 0.9 + actor radius 0.3")
	assert_near(rad_to_deg(g.arc), 120.0, 1e-4)
	assert_near(rad_to_deg(EnemySpecs.spec(EnemyType.STALKER).arc), 90.0, 1e-4)
	assert_near(rad_to_deg(EnemySpecs.spec(EnemyType.BRUTE).arc), 240.0, 1e-4)
	assert_near(EnemySpecs.spec(EnemyType.BRUTE).reach, 1.7, 1e-6)
	assert_eq(EnemySpecs.spec(EnemyType.TURRET).shape, EnemySpecs.SHAPE_LINE)
	assert_near(EnemySpecs.spec(EnemyType.TURRET).length, 12.0, 1e-6)
	assert_near(EnemySpecs.spec(EnemyType.DRONE).length, 8.0, 1e-6)
	assert_near(EnemySpecs.spec(EnemyType.BOSS).reach, 3.4, 1e-6, "cleave: radius + reach + actor radius")
	var e := ActorInterp.EnemyFrame.new()
	assert_eq(EnemySpecs.boss_mode(e, &"", 1.0), EnemySpecs.BOSS_CLEAVE)
	assert_eq(EnemySpecs.boss_mode(e, &"", 9.0), EnemySpecs.BOSS_VOLLEY, "out of cleave reach")
	assert_eq(EnemySpecs.boss_mode(e, EnemySpecs.BOSS_SWEEP, 1.0), EnemySpecs.BOSS_SWEEP, "event detail wins")
	e.boss_recall = true
	assert_eq(EnemySpecs.boss_mode(e, EnemySpecs.BOSS_SWEEP, 1.0), EnemySpecs.BOSS_RECALL, "memory strikes always read as memory")


# ───────────────────────────── shaders ─────────────────────────────

## Instance uniforms of a shader file plus its #includes: name -> explicit instance_index (-1 when
## the declaration has none).
func _instance_slots(path: String, out: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_true(f != null, "readable: " + path)
	if f == null:
		return
	var code := f.get_as_text()
	var inc := RegEx.create_from_string("#include \"([^\"]+)\"")
	for m: RegExMatch in inc.search_all(code):
		_instance_slots(m.get_string(1), out)
	var decl := RegEx.create_from_string(r"instance uniform \w+ (\w+)([^;]*);")
	var idx := RegEx.create_from_string(r"instance_index\((\d+)\)")
	for m: RegExMatch in decl.search_all(code):
		var hit := idx.search(m.get_string(2))
		out[m.get_string(1)] = int(hit.get_string(1)) if hit != null else -1


## Godot numbers instance uniforms per shader in declaration order unless instance_index() is given;
## on a next_pass chain the body's accent, the outline colour and the echo shift would then share a
## slot and overwrite each other (the desync projection rendered as a cyan cloud). Every pass chain
## the actor bodies use must give each instance uniform its own explicit slot in 0..15.
func test_body_pass_chains_have_unique_instance_slots() -> void:
	var mats := ActorMaterials.new()
	var pair: Array = mats.body_pair(Color.WHITE, false, false)
	for start: Material in [pair[0], pair[1]]:
		var by_name: Dictionary = {}
		var m: Material = start
		var passes := 0
		while m != null:
			var sm := m as ShaderMaterial
			assert_true(sm != null and sm.shader != null, "every pass is a shader material")
			_instance_slots(sm.shader.resource_path, by_name)
			m = m.next_pass
			passes += 1
		assert_true(passes >= 3, "body, outline and x-ray passes at least")
		var used: Dictionary = {}
		for n: String in by_name:
			var slot: int = by_name[n]
			assert_true(slot >= 0 and slot <= 15, "%s has an explicit instance_index in 0..15 (got %d)" % [n, slot])
			assert_false(used.has(slot), "slot %d shared by %s and %s" % [slot, n, used.get(slot, "")])
			used[slot] = n
