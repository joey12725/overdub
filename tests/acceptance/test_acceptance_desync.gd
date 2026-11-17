extends ODTest
## Acceptance: desynchronisation and recovery (docs/requirements.txt chapter 21: TEST-13..17), on the
## shipped core. Scenario inputs come from the prototype-authored goldens (tests/goldens/desync-*);
## every assertion is made on the port's own resolution.

const K = preload("res://tests/acceptance/acceptance_kit.gd")
const S = preload("res://tests/helpers/script.gd")


func _run(name: String) -> K.GoldenRun:
	var g := K.golden_run(name)
	assert_true(g.resolution != null, "golden %s resolves: %s" % [name, g.errors])
	return g


## Frames between the desync and the resync (or the end) of a tape.
func _desynced_frames(res: Resolution, tape: int) -> Array[FrameSnapshot]:
	var d := K.first_event(res.events, SimEventType.DESYNC, tape)
	var r := K.first_event(res.events, SimEventType.RESYNC, tape)
	var out: Array[FrameSnapshot] = []
	if d == null:
		return out
	var end := r.sub if r != null else res.horizon_subs + 1
	for f: FrameSnapshot in res.frames:
		if f.sub > d.sub + 1 and f.sub <= end:
			out.append(f)
	return out


## TEST-13 - Close a door across a living earlier tape's recorded path.
## Expected: "Its projection stays on the recording; desynchronization and reachable recovery apply."
func test_TEST13_a_door_closed_across_a_living_tape_desyncs_it_while_its_projection_stays_on_the_recording() -> void:
	var g := _run("desync-scenario-i-detour")
	if g.resolution == null:
		return
	var res := g.resolution
	var tape := g.tape(0)
	var d := K.first_event(res.events, SimEventType.DESYNC, 0)
	if not assert_true(d != null, K.say("TEST-13", "the runner desyncs")):
		return
	assert_eq(d.detail, "blocked by door d1", K.say("TEST-13", "the closed door is the cause"))
	assert_true(K.first_event(res.events, SimEventType.DOOR, -1, "d1").sub < d.sub, K.say("TEST-13", "the door closed first"))
	# The projection stays on the recording: the self's drawn position is its tape sample at every
	# frame of the run, desynced or not.
	var off := 0
	for f: FrameSnapshot in res.frames:
		var pose := TapeLib.sample_pose_at_sub(tape, f.sub)
		var a := f.actor(0)
		if absf(a.x - pose.x) > 1e-6 or absf(a.y - pose.y) > 1e-6:
			off += 1
	assert_eq(off, 0, K.say("TEST-13", "frames where the projection left the recording"))
	# Desynchronisation applies (not synced, spark present) and reachable recovery applies (it resyncs).
	var frames := _desynced_frames(res, 0)
	assert_true(frames.size() > 10)
	var bad := 0
	for f: FrameSnapshot in frames:
		if f.actor(0).synced or not f.actor(0).has_spark:
			bad += 1
	assert_eq(bad, 0, K.say("TEST-13", "desynced frames without the desynced state / spark"))
	var r := K.first_event(res.events, SimEventType.RESYNC, 0)
	assert_true(r != null and r.sub > d.sub, K.say("TEST-13", "a reachable recovery resyncs the tape"))
	assert_eq(res.frames[res.frames.size() - 1].actor(0).life, OD.LifeState.ALIVE, K.say("TEST-13", "the door never deletes or kills the self"))
	assert_true(res.outcome.win)


## TEST-14 - Leave an unobstructed detour for the recovery spark.
## Expected: "Finite-speed recovery can navigate toward the moving projection; no instant
## overlap-only recovery."
func test_TEST14_the_spark_navigates_the_detour_at_finite_speed_toward_the_moving_projection() -> void:
	var g := _run("desync-scenario-i-detour")
	if g.resolution == null:
		return
	var res := g.resolution
	var frames := _desynced_frames(res, 0)
	if not assert_true(frames.size() > 10, K.say("TEST-14", "a recovery takes time")):
		return
	var speed := Tuning.BASE.spark_speed * g.loadout.mods.spark_speed
	var max_step := speed * OD.FRAME_SUBS / float(OD.SUB_HZ) + 1e-6
	var prev: Vector2 = frames[0].actor(0).spark
	var worst := 0.0
	var used_detour := false
	var start_gap := Vector2(frames[0].actor(0).x, frames[0].actor(0).y).distance_to(prev)
	var moves := 0
	for i: int in range(1, frames.size()):
		var a := frames[i].actor(0)
		var sp := a.spark
		worst = maxf(worst, sp.distance_to(prev))
		if sp.distance_to(prev) > 1e-9:
			moves += 1
		# The detour is the upper corridor (row 1); the blocked direct route is row 3.
		if sp.y < 2.0:
			used_detour = true
		prev = sp
	assert_true(worst <= max_step, K.say("TEST-14", "spark moved %.4f tiles in one frame; finite speed allows %.4f" % [worst, max_step]))
	assert_true(moves > 10, K.say("TEST-14", "the spark travels"))
	assert_true(used_detour, K.say("TEST-14", "the spark navigated the open detour"))
	# Toward the moving projection: the gap opens while the projection runs on past the blocker
	# (at desync it is ~0, the spark starts where the self was stopped), then the spark closes it
	# until it is inside the resync tolerance. Measured over the frames that carry a spark.
	var widest := start_gap
	var last_gap := -1.0
	for f: FrameSnapshot in frames:
		var a2 := f.actor(0)
		if a2.synced or not a2.has_spark:
			continue
		last_gap = Vector2(a2.x, a2.y).distance_to(a2.spark)
		widest = maxf(widest, last_gap)
	assert_true(last_gap >= 0.0 and last_gap < widest * 0.5, K.say("TEST-14", "it closed on the moving projection (widest gap %.2f, last %.2f)" % [widest, last_gap]))
	assert_true(last_gap <= Tuning.BASE.resync_tolerance + 3.0 * max_step + 0.25, K.say("TEST-14", "the spark reached the projection (last gap %.2f)" % last_gap))
	# No instant / overlap-only recovery: the resync comes no sooner than the spark could travel the
	# detour (lower bound: the straight distance it covered at full speed).
	var d := K.first_event(res.events, SimEventType.DESYNC, 0)
	var r := K.first_event(res.events, SimEventType.RESYNC, 0)
	if assert_true(d != null and r != null, K.say("TEST-14", "desync then resync")):
		var travelled := 0.0
		for i: int in range(1, frames.size()):
			travelled += frames[i].actor(0).spark.distance_to(frames[i - 1].actor(0).spark)
		var min_subs := travelled / speed * OD.SUB_HZ
		assert_true(r.sub - d.sub >= min_subs - OD.FRAME_SUBS * 2, K.say("TEST-14", "resync after %d substeps for a %.2f-tile path" % [r.sub - d.sub, travelled]))
		assert_true(travelled > 6.0, K.say("TEST-14", "the detour is long (%.2f tiles), not an overlap" % travelled))


## TEST-15 - Open a blocked route while a spark is catching up.
## Expected: "The new traversable route can enable recovery."
func test_TEST15_reopening_the_blocked_route_lets_the_spark_recover() -> void:
	var blocked := _run("desync-no-route")
	var reopened := _run("desync-route-reopened-by-other")
	if blocked.resolution == null or reopened.resolution == null:
		return
	# Control: with no route the spark never catches up (and nothing teleports or kills it).
	assert_true(K.first_event(blocked.resolution.events, SimEventType.DESYNC, 0) != null)
	assert_eq(K.events_of(blocked.resolution.events, SimEventType.RESYNC, 0).size(), 0, K.say("TEST-15", "control: no route, no recovery"))
	assert_false(blocked.resolution.frames[blocked.resolution.frames.size() - 1].actor(0).synced)
	assert_eq(K.events_of(blocked.resolution.events, SimEventType.SELF_DEATH, 0).size(), 0, K.say("TEST-15", "never killed for failing to recover"))
	# Another tape reopens the route while the spark is waiting: recovery follows.
	var res := reopened.resolution
	var d := K.first_event(res.events, SimEventType.DESYNC, 0)
	var opened: SimEvent = null
	for e: SimEvent in K.events_of(res.events, SimEventType.DOOR, -1, "d1"):
		if e.detail == "open":
			opened = e
	var r := K.first_event(res.events, SimEventType.RESYNC, 0)
	if not assert_true(d != null and opened != null and r != null, K.say("TEST-15", "desync, reopening, resync")):
		return
	assert_true(d.sub < opened.sub and opened.sub < r.sub, K.say("TEST-15", "the resync follows the reopening"))
	assert_true(res.outcome.win, K.say("TEST-15", "the recovered tape then completes the level"))


## TEST-16 - Attack or receive fire while desynchronized.
## Expected: "No dealt or received damage under the working invulnerable/harmless rule."
func test_TEST16_a_desynced_self_deals_and_receives_no_damage() -> void:
	var g := _run("desync-harmless-invulnerable")
	if g.resolution == null:
		return
	var res := g.resolution
	var d := K.first_event(res.events, SimEventType.DESYNC, 0)
	if not assert_true(d != null, K.say("TEST-16", "tape A desyncs on the low barrier")):
		return
	assert_eq(K.events_of(res.events, SimEventType.RESYNC, 0).size(), 0, "it stays desynced")
	# Its recorded swing comes after the desync: no hit, no damage, the grunt untouched.
	var swing_tick: int = g.tape(0).events[0].tick
	assert_true(swing_tick * OD.subs_per_local_tick(1.0) > d.sub, "the swing is recorded after the desync")
	assert_eq(K.events_of(res.events, SimEventType.HIT, 0).size(), 0, K.say("TEST-16", "no dealt damage (hit)"))
	assert_eq(K.events_of(res.events, SimEventType.KILL, 0).size(), 0, K.say("TEST-16", "no dealt damage (kill)"))
	var grunt := res.frames[res.frames.size() - 1].enemy("g1")
	assert_eq([grunt.alive, grunt.hp], [true, grunt.max_hp], K.say("TEST-16", "the grunt keeps full health"))
	# Received fire: the turret's bolts fly at the self behind it, straight through the projection,
	# and never hurt or kill the desynced self.
	assert_eq(K.events_of(res.events, SimEventType.PROJECTILE_HIT, 0).size(), 0, K.say("TEST-16", "no bolt hit the desynced self"))
	assert_eq(K.events_of(res.events, SimEventType.SELF_DEATH, 0).size(), 0, K.say("TEST-16", "no received damage"))
	assert_true(K.events_of(res.events, SimEventType.SELF_DEATH, 2).size() == 1, K.say("TEST-16", "the bolt passed on and killed the self behind"))
	assert_eq(res.outcome.survivors, [0], K.say("TEST-16", "the desynced self survives"))
	# Enemies never target it while desynced.
	var targeted := 0
	for f: FrameSnapshot in _desynced_frames(res, 0):
		for e: EnemySnap in f.enemies:
			if e.target == 0:
				targeted += 1
	assert_eq(targeted, 0, K.say("TEST-16", "frames where an enemy targeted the desynced self"))


## TEST-17 - Use the wall-and-turret teaching case.
## Expected: "Desync can protect the crossing, but the actor must resync before damaging the turret."
func test_TEST17_desync_protects_the_crossing_but_the_strike_only_counts_after_resync() -> void:
	var control := _run("desync-scenario-j-control")
	var win := _run("desync-scenario-j")
	var stuck := _run("desync-scenario-j-no-detour")
	if control.resolution == null or win.resolution == null or stuck.resolution == null:
		return
	# Without desync the turret kills the crossing tape.
	var died := K.first_event(control.resolution.events, SimEventType.SELF_DEATH, 0)
	assert_true(died != null and died.detail.contains("turret"), K.say("TEST-17", "control: the crossing is deadly"))
	# Desync protects the crossing; the tape resyncs behind the turret and then breaks it.
	var res := win.resolution
	var d := K.first_event(res.events, SimEventType.DESYNC, 0)
	var r := K.first_event(res.events, SimEventType.RESYNC, 0)
	var kill := K.first_event(res.events, SimEventType.KILL, 0, "t1")
	if not assert_true(d != null and r != null and kill != null, K.say("TEST-17", "desync, resync, kill")):
		return
	assert_eq(K.events_of(res.events, SimEventType.SELF_DEATH, 0).size(), 0, K.say("TEST-17", "desync protected the crossing"))
	assert_true(died != null and d.sub < died.sub and r.sub > died.sub, K.say("TEST-17", "desynced through the moment the control run died"))
	assert_true(r.sub < kill.sub, K.say("TEST-17", "resynced before damaging the turret"))
	assert_true(res.outcome.win)
	# If the spark never catches up, the same recorded strike does nothing to the turret.
	var sres := stuck.resolution
	assert_true(K.first_event(sres.events, SimEventType.DESYNC, 0) != null)
	assert_eq(K.events_of(sres.events, SimEventType.RESYNC, 0).size(), 0)
	assert_eq(K.events_of(sres.events, SimEventType.HIT, 0, "t1").size(), 0, K.say("TEST-17", "no damage to the turret without resync"))
	assert_true(sres.frames[sres.frames.size() - 1].enemy("t1").alive, K.say("TEST-17", "the turret survives the desynced strike"))
	assert_false(sres.outcome.win)
