extends ODTest
## The cinematic director's runtime half (cinema/cinema_director.gd): framing per frame, eased
## transitions, cuts only at shot boundaries, cues once each, the node's signals.

const G := preload("res://cinema/cinema_grammar.gd")


func _plan(name: String) -> CinemaPlan:
	var errors: Array[String] = []
	var g := CinemaGolden.load_named(name, errors)
	for e: String in errors:
		fail(e)
	return g.plan() if g != null else null


func test_sample_is_pure_and_matches_the_plan() -> void:
	var plan := _plan("sandbox-bot-two-cassettes")
	if plan == null:
		return
	var d := CinemaDirector.new()
	d.set_plan(plan)
	var b := 0.0
	while b < float(plan.horizon_beats):
		var a := d.sample(b)
		var c := d.sample(b)
		assert_eq(a.shot_index, c.shot_index, "pure: shot")
		assert_vec_near(a.target, c.target, 1e-9, "pure: target")
		assert_near(a.span, c.span, 1e-9, "pure: span")
		assert_true(plan.shots[a.shot_index].contains_beat(b), "beat %.2f is inside shot %d" % [b, a.shot_index])
		assert_true(a.letterbox >= G.LETTERBOX_BASE - 1e-6 and a.letterbox <= G.LETTERBOX_DEEP + 1e-6, "letterbox in range")
		assert_true(a.span > 0.0, "positive span")
		var sh := plan.shots[a.shot_index]
		if sh.transition == G.TRANSITION_CUT or b >= float(sh.start_beat) + G.BLEND_BEATS:
			assert_eq(a.wide, 1.0 if sh.framing == G.FRAMING_WIDE else 0.0, "wide flag follows the framing")
		b += 0.37
	d.free()


func test_advance_cuts_only_on_boundaries_and_fires_cues_once() -> void:
	var plan := _plan("ghost-rescue")
	if plan == null:
		return
	var d := CinemaDirector.new()
	d.set_plan(plan)
	var started: Array[int] = []
	d.shot_started.connect(func(i: int, _s: CinemaShot) -> void: started.append(i))
	var fired: Array[CinemaTypes.Cue] = []
	var prev_lb := -1.0
	var max_jump := 0.0
	var step := 1.0 / 60.0
	var b := 0.0
	var last_index := -1
	while b < float(plan.horizon_beats):
		var f := d.advance(b)
		for c: CinemaTypes.Cue in f.cues:
			fired.append(c)
		if f.shot_index != last_index:
			assert_true(b - float(f.shot.start_beat) < step + 1e-9, "a new shot appears on its start beat (%.3f vs %d)" % [b, f.shot.start_beat])
			assert_eq(f.cut, f.shot.transition == G.TRANSITION_CUT or last_index < 0, "cut flag on the first frame of a hard-cut shot")
			last_index = f.shot_index
		else:
			assert_false(f.cut, "no cut inside a shot")
		if prev_lb >= 0.0:
			max_jump = maxf(max_jump, absf(f.letterbox - prev_lb))
		prev_lb = f.letterbox
		b += step
	assert_eq(started.size(), plan.shots.size(), "shot_started once per shot")
	assert_eq(fired.size(), plan.cues.size(), "every cue fired exactly once on a forward pass")
	assert_true(max_jump < 0.01, "letterbox eases (max step %.4f)" % max_jump)
	# Seeking back does not refire the cues already behind the playhead.
	var back := d.advance(1.0)
	var refired := 0
	for c: CinemaTypes.Cue in back.cues:
		if c.beat < 1.0 - 1e-6:
			refired += 1
	assert_eq(refired, 0, "seeking back fires nothing behind the playhead")
	d.free()


func test_moves_and_emphasis_shape_the_frame() -> void:
	var plan := CinemaPlan.new()
	plan.horizon_beats = 12
	var push := CinemaShot.new()
	push.start_beat = 0
	push.end_beat = 4
	push.framing = G.FRAMING_CLOSE
	push.span = 8.0
	push.move = G.MOVE_PUSH_IN
	push.focus_point = Vector2(3, 3)
	push.focus_to = push.focus_point
	push.key_beat = 2.0
	var ripple := CinemaShot.new()
	ripple.start_beat = 4
	ripple.end_beat = 8
	ripple.framing = G.FRAMING_TWO_SHOT
	ripple.span = 10.0
	ripple.move = G.MOVE_ORBIT
	ripple.move_sign = 1.0
	ripple.emphasis = G.EMPHASIS_TIME_RIPPLE
	ripple.ripple = 1.0
	ripple.key_beat = 6.0
	ripple.focus_point = Vector2(5, 5)
	ripple.focus_to = ripple.focus_point
	var split := CinemaShot.new()
	split.start_beat = 8
	split.end_beat = 12
	split.emphasis = G.EMPHASIS_SPLIT
	split.key_beat = 10.0
	split.focus_point = Vector2(8, 8)
	split.focus_to = split.focus_point
	for t: int in 2:
		var p := CinemaTypes.Pane.new()
		p.tape = t
		p.focus = Vector2(2 + 10 * t, 3)
		p.rect = G.pane_rects(2)[t]
		split.panes.append(p)
	plan.shots.append(push)
	plan.shots.append(ripple)
	plan.shots.append(split)
	var a := CinemaDirector.sample_plan(plan, 0.2)
	var b := CinemaDirector.sample_plan(plan, 3.8)
	assert_true(b.span < a.span, "push-in tightens over the shot (%.2f -> %.2f)" % [a.span, b.span])
	var r0 := CinemaDirector.sample_plan(plan, 4.5)
	var r1 := CinemaDirector.sample_plan(plan, 6.0)
	assert_true(r1.ripple > 0.95 and r0.ripple < 0.2, "ripple peaks on the key beat (%.2f at 4.5, %.2f at 6)" % [r0.ripple, r1.ripple])
	assert_true(CinemaDirector.sample_plan(plan, 7.5).yaw_offset > 0.0 and r0.yaw_offset < 0.0, "orbit swings through the iso yaw")
	var s0 := CinemaDirector.sample_plan(plan, 8.0)
	var s1 := CinemaDirector.sample_plan(plan, 10.0)
	assert_eq(s1.panes.size(), 2, "two panes")
	assert_true(s0.split_t < 0.05 and s1.split_t > 0.99, "split eases open")
	assert_near(CinemaDirector.sample_plan(plan, 2.0).ripple, 0.0, 1e-9, "no ripple outside its shot")
	# Tracking: with a snapshot the close shot follows its self.
	push.focus_tape = 0
	var snap := FrameSnapshot.new()
	var actor := ActorSnap.new()
	actor.tape = 0
	actor.x = 7.0
	actor.y = 3.0
	snap.actors.append(actor)
	var tr := CinemaDirector.sample_plan(plan, 1.0, snap)
	assert_true(tr.target.x > 6.0, "a tracked close-up follows the live position (%.2f)" % tr.target.x)


func test_camera_bridge_turns_spans_into_view_sizes() -> void:
	var aspect := 16.0 / 9.0
	var fit := 20.0
	# Wider spans need more view; never below the camera's minimum; height covers a standing self.
	var a := CinemaCameraBridge.view_size(6.0, aspect)
	var b := CinemaCameraBridge.view_size(12.0, aspect)
	assert_true(b > a, "a wider span needs a bigger view (%.2f -> %.2f)" % [a, b])
	assert_true(a >= CinemaCameraBridge.MIN_VIEW_SIZE, "never closer than the camera minimum")
	assert_true(CinemaCameraBridge.view_size(30.0, aspect) * aspect >= 30.0 - 1e-6, "the span fits across the screen")
	assert_true(CinemaCameraBridge.view_size(30.0, 0.5) * 0.5 >= 30.0 - 1e-6, "and on a tall pane")
	var plan := _plan("sandbox-bot-two-cassettes")
	if plan == null:
		return
	var b2 := 0.0
	while b2 < float(plan.horizon_beats):
		var cf := CinemaDirector.sample_plan(plan, b2)
		var pose := CinemaCameraBridge.pose(cf, aspect, fit)
		assert_true(pose.view_size > 0.0 and pose.view_size <= fit * 1.05 + 1e-6, "view size within the level fit")
		if cf.wide >= 1.0:
			assert_near(pose.view_size, fit, 1e-6, "wide frames fit the level")
		assert_vec_near(pose.target, cf.target, 1e-9, "the bridge keeps the planned target")
		assert_eq(pose.pane_view_sizes.size(), cf.panes.size(), "one view size per split pane")
		b2 += 0.5
	var none := CinemaCameraBridge.pose(null, aspect, fit, Vector2(4, 5))
	assert_near(none.view_size, fit, 1e-9, "no plan: fit the level")
	assert_vec_near(none.target, Vector2(4, 5), 1e-9, "no plan: the fallback target")
	# A hard cut snaps.
	var d := CinemaDirector.new()
	d.set_plan(plan)
	assert_true(CinemaCameraBridge.pose(d.advance(0.0), aspect, fit).snap, "the first frame snaps")
	assert_false(CinemaCameraBridge.pose(d.advance(0.1), aspect, fit).snap, "inside a shot it eases")
	d.free()


func test_no_plan_is_a_harmless_wide_frame() -> void:
	var d := CinemaDirector.new()
	var f := d.advance(3.0)
	assert_eq(f.shot_index, -1, "no shot")
	assert_eq(f.wide, 1.0, "fit the level")
	d.free()


func test_director_in_the_tree() -> void:
	var plan := _plan("boss-coordinated-win")
	if plan == null:
		return
	var d := CinemaDirector.new()
	tree().root.add_child(d)
	d.set_plan(plan)
	var n: Array[int] = []
	d.shot_started.connect(func(i: int, _s: CinemaShot) -> void: n.append(i))
	var b := 0.0
	while b < float(plan.horizon_beats):
		d.advance(b)
		b += 0.1
	assert_eq(n.size(), plan.shots.size(), "signals fire from a node in the tree")
	d.queue_free()
	await tree().process_frame
