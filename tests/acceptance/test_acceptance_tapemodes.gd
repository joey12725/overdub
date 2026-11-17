extends ODTest
## Acceptance: end behaviours (docs/requirements.txt chapter 21: TEST-25, TEST-26), on the shipped
## core. Fixtures: tests/goldens/tapemode-repeat / tapemode-reverse (a 2x, 1-bar tape on a 2-bar
## horizon that flips a switch and strikes a 4-hp turret, so it runs out twice... three times).

const K = preload("res://tests/acceptance/acceptance_kit.gd")
const S = preload("res://tests/helpers/script.gd")


func _details(evs: Array[SimEvent]) -> Array:
	var out: Array = []
	for e: SimEvent in evs:
		out.append(e.detail)
	return out


## TEST-25 - Trigger repeat on a short tape.
## Expected: "It cuts to its starting position and repeats without resetting the entire encounter."
func test_TEST25_repeat_cuts_to_the_start_and_repeats_without_resetting_the_encounter() -> void:
	var g := K.golden_run("tapemode-repeat")
	if not assert_true(g.resolution != null, "golden runs: %s" % [g.errors]):
		return
	var res := g.resolution
	var tape := g.tape(0)
	assert_eq(tape.end_mode, OD.EndMode.REPEAT)
	var span := ODTime.traversal_subs(tape)
	var wraps := K.events_of(res.events, SimEventType.TAPE_WRAP, 0)
	assert_eq(wraps.size(), res.horizon_subs / span - 1, K.say("TEST-25", "it repeats every time it runs out"))
	if wraps.is_empty():
		return
	# Cuts to its starting position: the frame after the wrap is at sample 0, a jump, not a walk.
	var before := S.frame_exact(res.frames, span - OD.FRAME_SUBS).actor(0)
	var after := S.frame_exact(res.frames, span).actor(0)
	assert_eq([after.x, after.y], [tape.pos[0], tape.pos[1]], K.say("TEST-25", "cut to the start position"))
	assert_true(Vector2(before.x, before.y).distance_to(Vector2(after.x, after.y)) > 2.0, K.say("TEST-25", "a cut, not travel"))
	assert_eq(after.phase.traversal, 1, K.say("TEST-25", "second traversal"))
	# Repeats: its recorded actions fire again on every traversal.
	var flips := K.events_of(res.events, SimEventType.INTERACT, 0, "sw")
	assert_eq(flips.size(), wraps.size() + 1, K.say("TEST-25", "the switch action fires every traversal"))
	if flips.size() >= 2:
		assert_eq(flips[1].sub - flips[0].sub, span, K.say("TEST-25", "at the same point of each traversal"))
	# Without resetting the encounter: world state carries across the cut.
	var at_cut := S.frame_exact(res.frames, span)
	var just_before := S.frame_exact(res.frames, span - OD.FRAME_SUBS)
	assert_eq(at_cut.mech("sw").on, just_before.mech("sw").on, K.say("TEST-25", "the switch keeps its state across the cut"))
	assert_true(at_cut.mech("sw").on, "the first traversal left the switch on")
	var t_before := just_before.enemy("t1")
	assert_true(t_before.hp < t_before.max_hp, "the first traversal damaged the turret")
	assert_eq(at_cut.enemy("t1").hp, t_before.hp, K.say("TEST-25", "the turret is not healed by the cut"))
	assert_true(at_cut.beat > just_before.beat, K.say("TEST-25", "master time keeps running"))
	var kill := K.first_event(res.events, SimEventType.KILL, 0, "t1")
	if assert_true(kill != null and kill.sub > span, K.say("TEST-25", "the second traversal finishes the damaged turret")):
		var revived := false
		for f: FrameSnapshot in res.frames:
			if f.sub > kill.sub and f.enemy("t1").alive:
				revived = true
		assert_false(revived, K.say("TEST-25", "later cuts do not respawn it"))
	assert_true(res.outcome.win)


## TEST-26 - Trigger reverse.
## Expected: "Recorded actions run backward without globally restoring world history; specific event
## inverses require policy." (The policy shipped: a re-crossed switch toggles again, a swing is a
## fresh swing that can hurt again and never heals; ARCHITECTURE "What a tape is".)
func test_TEST26_reverse_runs_recorded_actions_backward_without_restoring_world_history() -> void:
	var g := K.golden_run("tapemode-reverse")
	if not assert_true(g.resolution != null, "golden runs: %s" % [g.errors]):
		return
	var res := g.resolution
	var tape := g.tape(0)
	assert_eq(tape.end_mode, OD.EndMode.REVERSE)
	var span := ODTime.traversal_subs(tape)
	var turn := K.first_event(res.events, SimEventType.TAPE_TURN, 0)
	if not assert_true(turn != null, K.say("TEST-26", "the tape turns at its end")):
		return
	assert_eq(turn.detail, "backward")
	# The motion runs backward: on the backward pass the self retraces the forward pass mirrored.
	var mirrored := 0
	var checked := 0
	for k: int in range(OD.FRAME_SUBS, span, OD.FRAME_SUBS):
		var fwd := S.frame_exact(res.frames, span - k)
		var bwd := S.frame_exact(res.frames, span + k)
		if fwd == null or bwd == null:
			continue
		checked += 1
		assert_eq(bwd.actor(0).phase.dir, -1)
		if absf(fwd.actor(0).x - bwd.actor(0).x) < 1e-6 and absf(fwd.actor(0).y - bwd.actor(0).y) < 1e-6:
			mirrored += 1
	assert_true(checked > 20)
	assert_eq(mirrored, checked, K.say("TEST-26", "backward pass positions mirror the forward pass"))
	# Recorded actions run backward: the swing (recorded after the switch) fires BEFORE it on the way back.
	var interacts := K.events_of(res.events, SimEventType.INTERACT, 0, "sw")
	var swings := K.events_of(res.events, SimEventType.SWING, 0)
	if assert_true(interacts.size() >= 2 and swings.size() >= 2, K.say("TEST-26", "actions re-fire on the backward pass")):
		assert_true(interacts[0].sub < swings[0].sub, "forward: switch then swing")
		assert_true(swings[1].sub < interacts[1].sub and swings[1].sub > span, K.say("TEST-26", "backward: swing then switch"))
		# The recorded action re-fires where the playhead re-crosses its tick; the SWING event is the
		# hit window opening, which the shipped policy (docs/DECISIONS.md OPEN-06, side effect P-1)
		# places the same wind-up AFTER the crossing on both passes.
		var light: TapeEvent = null
		for te: TapeEvent in tape.events:
			if te.kind == ActionKind.LIGHT:
				light = te
				break
		if assert_true(light != null, "the tape recorded a light swing"):
			var spt := OD.subs_per_local_tick(tape.speed)
			var fwd_cross := light.tick * spt
			var back_cross := 2 * span - light.tick * spt
			assert_true(swings[0].sub >= fwd_cross and swings[1].sub >= back_cross, K.say("TEST-26", "swings fire at or after their crossings (%d/%d, %d/%d)" % [swings[0].sub, fwd_cross, swings[1].sub, back_cross]))
			assert_eq(swings[1].sub - back_cross, swings[0].sub - fwd_cross, K.say("TEST-26", "the swing fires where the playhead re-crosses its tick (same wind-up on both passes)"))
		# The instantaneous switch interact mirrors exactly about the turn.
		assert_eq(span - interacts[0].sub, interacts[1].sub - span, K.say("TEST-26", "the switch re-fires where the playhead re-crosses its tick"))
	# Without globally restoring world history: master time and the world move forward.
	var beats_forward := true
	for i: int in range(1, res.frames.size()):
		beats_forward = beats_forward and res.frames[i].beat > res.frames[i - 1].beat
	assert_true(beats_forward, K.say("TEST-26", "master time never runs backward"))
	var hit_fwd := K.first_event(res.events, SimEventType.HIT, 0, "t1")
	var after_hit := S.frame_at(res, hit_fwd.sub + OD.FRAME_SUBS).enemy("t1").hp if hit_fwd != null else -1
	var at_turn := S.frame_exact(res.frames, span + OD.FRAME_SUBS).enemy("t1")
	assert_eq(at_turn.hp, after_hit, K.say("TEST-26", "re-crossing the hit's tick does not restore the turret's health"))
	var kill := K.first_event(res.events, SimEventType.KILL, 0, "t1")
	if assert_true(kill != null and kill.sub > span, K.say("TEST-26", "the backward swing is a fresh swing that hurts again")):
		var revived := false
		for f: FrameSnapshot in res.frames:
			revived = revived or (f.sub > kill.sub and f.enemy("t1").alive)
		assert_false(revived, K.say("TEST-26", "the forward pass after the next turn does not undo the kill"))
	# Specific event inverses follow the shipped policy: the switch toggles again each time its tick
	# is crossed (on, off, on, off), it is never restored to a remembered state.
	assert_eq(_details(interacts), ["on", "off", "on", "off"], K.say("TEST-26", "switch policy on re-crossing"))
	assert_true(res.outcome.win)
