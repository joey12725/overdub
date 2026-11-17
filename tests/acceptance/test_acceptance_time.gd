extends ODTest
## Acceptance: one clock (docs/requirements.txt chapter 21, TEST-01 and TEST-02).

const K = preload("res://tests/acceptance/acceptance_kit.gd")
const S = preload("res://tests/helpers/script.gd")


## TEST-01 - Record the same-duration level at slow, middle and fast settings.
## Expected: "Actual recording allowance remains equal; world pace changes relative to the controlled
## character." Driven through GameSession exactly as a player would: pick the speed, record, count
## the local ticks the take accepts.
func test_TEST01_recording_allowance_is_equal_at_every_speed_and_the_world_pace_changes() -> void:
	var level := TestLevels.make_level({"id": "test01", "speeds": [0.5, 1.0, 2.0, 4.0], "bars": 1})
	var run := S.input_script().run(0, 10000, 1, 0)
	var rows: Array[Dictionary] = []
	for speed: float in [0.5, 1.0, 2.0, 4.0]:
		var s := K.new_session(level)
		if not assert_true(s != null, "session"):
			return
		assert_true(K.set_speed(s, speed), "speed %s offered" % speed)
		assert_true(s.act(SessionAction.RECORD))
		K.advance_until_phase_changes(s, 10.0)
		assert_eq(s.phase, SessionPhase.RECORDING)
		var rate := s.view().world_rate
		var ticks := 0
		var sub_after_ten := -1
		var self_after_ten := Vector2.ZERO
		while s.phase == SessionPhase.RECORDING and ticks < 100000:
			s.tick_local(run.input(ticks))
			ticks += 1
			if ticks == 10:
				var snap := s.current_frame().snap
				sub_after_ten = snap.sub
				var me := snap.actor(0)
				self_after_ten = Vector2(me.x, me.y)
		rows.append({"speed": speed, "ticks": ticks, "rate": rate, "sub10": sub_after_ten, "self10": self_after_ten, "tape": s.pending_tape})
	var allowance: int = rows[0]["ticks"]
	assert_eq(allowance, TestLevels.make_level({"bars": 1}).bars * 4 * 30, K.say("TEST-01", "1 bar at 120 bpm = 120 local ticks"))
	for r: Dictionary in rows:
		var sp: float = r["speed"]
		# Actual recording allowance remains equal ...
		assert_eq(r["ticks"], allowance, K.say("TEST-01", "local ticks recorded at %sx" % sp))
		assert_eq((r["tape"] as ODTape).ticks, allowance, K.say("TEST-01", "tape length at %sx" % sp))
		# ... the controlled character moves the same in its own (local) time at every speed ...
		assert_vec_near(r["self10"], rows[1]["self10"], 1e-9, K.say("TEST-01", "self position after 10 local ticks at %sx" % sp))
		assert_eq((r["tape"] as ODTape).pos, (rows[1]["tape"] as ODTape).pos, K.say("TEST-01", "same input, same local trajectory at %sx" % sp))
		# ... while the world pace changes relative to it: 1/speed master time per local tick.
		assert_near(r["rate"], 1.0 / sp, 1e-12, K.say("TEST-01", "world rate while recording at %sx" % sp))
		assert_eq(r["sub10"], 10 * OD.subs_per_local_tick(sp), K.say("TEST-01", "world substeps after 10 local ticks at %sx" % sp))
	# Slow sees twice the world of middle, fast half of it.
	assert_eq(int(rows[0]["sub10"]), 2 * int(rows[1]["sub10"]), K.say("TEST-01", "0.5x vs 1x"))
	assert_eq(2 * int(rows[2]["sub10"]), int(rows[1]["sub10"]), K.say("TEST-01", "2x vs 1x"))


## TEST-02 - Compare a recording's platform landing with true-speed replay.
## Expected: "The master-beat relationship is preserved; no duration stretching changes the landing."
func test_TEST02_a_2x_plate_landing_happens_at_the_same_master_beat_in_recording_and_replay() -> void:
	var ents: Array[EntityDef] = [S.plate("p1", 7, 5)]
	var level := TestLevels.make_level(
		{
			"speeds": [1.0, 2.0],
			"bars": 1,
			"start": Vector2(2.5, 5.5),
			"entities": ents,
			"objective": S.objective(ObjectiveType.SIGNAL, "Stand on the plate", [], SignalExpr.of_sig("p1")),
		}
	)
	var take := S.record_take(level, 0, 2.0, S.input_script().run(0, 1000, 1, 0))
	var rec := K.first_event(take.events, SimEventType.PLATE, -1, "p1")
	if not assert_true(rec != null, K.say("TEST-02", "the take lands on the plate while recording")):
		return
	var res := K.resolve(level, [take.tape])
	var rep := K.first_event(res.events, SimEventType.PLATE, -1, "p1")
	if not assert_true(rep != null, K.say("TEST-02", "the replay lands on the plate")):
		return
	var spb := ODTime.subs_per_beat(level)
	assert_eq(rep.sub, rec.sub, K.say("TEST-02", "landing substep, recording vs true-speed replay"))
	assert_near((rep.sub + 1) / spb, (rec.sub + 1) / spb, 0.0, K.say("TEST-02", "landing master beat"))
	# No duration stretching: in the replay the 2x tape is at local tick sub * 2 / 4 at every frame
	# of its traversal, i.e. its recording occupies bars / 2 master bars exactly.
	var stretched := 0
	for f: FrameSnapshot in res.frames:
		var a := f.actor(0)
		if f.sub <= ODTime.traversal_subs(take.tape) and absf(a.phase.tick - f.sub * 2.0 / 4.0) > 1e-9:
			stretched += 1
	assert_eq(stretched, 0, K.say("TEST-02", "replay frames whose tape phase is not master sub x speed / 4"))
	assert_eq(ODTime.traversal_subs(take.tape), take.tape.ticks * OD.subs_per_local_tick(2.0), K.say("TEST-02", "traversal length"))
	# The landing frame itself is reproduced exactly.
	var g := S.frame_exact(res.frames, rec.sub + 1 - ((rec.sub + 1) % OD.FRAME_SUBS))
	var f2 := S.frame_exact(take.frames, g.sub) if g != null else null
	if g != null and f2 != null:
		assert_eq([g.actor(0).x, g.actor(0).y], [f2.actor(0).x, f2.actor(0).y], K.say("TEST-02", "position at the landing frame"))
	assert_true(res.outcome.objective_complete, K.say("TEST-02", "the replayed landing still satisfies the plate objective"))
