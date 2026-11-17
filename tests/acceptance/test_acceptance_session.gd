extends ODTest
## Acceptance: take management and playback through the shipped GameSession (game/session.gd):
## TEST-03, TEST-04, TEST-05, TEST-06, TEST-31, TEST-32 (docs/requirements.txt chapter 21).

const K = preload("res://tests/acceptance/acceptance_kit.gd")
const S = preload("res://tests/helpers/script.gd")


func _actor_tapes(f: FrameSnapshot) -> Array:
	var out: Array = []
	for a: ActorSnap in f.actors:
		out.append(a.tape)
	return out


# ───────────────────────────── TEST-03 ─────────────────────────────


## TEST-03 - Begin cassette two after finishing cassette one.
## Expected: "The encounter starts at beat zero; cassette one plays from its start."
func test_TEST03_cassette_two_starts_at_beat_zero_with_cassette_one_playing_from_its_start() -> void:
	var level := K.rescue_room()
	var s := K.new_session(level)
	if not assert_true(K.take_a_to_decision(s), "tape A reached the decision"):
		return
	var a := s.pending_tape
	assert_true(s.act(SessionAction.COMMIT))
	assert_true(s.act(SessionAction.RECORD), K.say("TEST-03", "record cassette two"))
	var sim := s.live_sim
	assert_eq(sim.sub, 0, K.say("TEST-03", "live sim substep"))
	var snap := s.current_frame().snap
	assert_eq(snap.sub, 0, K.say("TEST-03"))
	assert_eq(snap.beat, 0.0, K.say("TEST-03", "beat"))
	assert_eq(s.view().beat, 0.0, K.say("TEST-03", "HUD beat"))
	var one := snap.actor(0)
	if not assert_true(one != null, K.say("TEST-03", "cassette one is in the encounter")):
		return
	assert_eq([one.x, one.y], [a.pos[0], a.pos[1]], K.say("TEST-03", "cassette one at its first recorded sample"))
	assert_eq(one.phase.tick, 0.0, K.say("TEST-03", "cassette one's playhead"))
	assert_eq(one.life, OD.LifeState.ALIVE, K.say("TEST-03", "cassette one alive again at beat zero"))
	# The world is rebuilt from its initial state: the turret and the grunt are back.
	assert_true(snap.enemy("t1").alive and snap.enemy("g1").alive, K.say("TEST-03", "enemies reset"))
	# And cassette one really plays from its start: 30 local ticks of B at 1x = A's sample 30.
	K.advance_until_phase_changes(s, 10.0)
	for t: int in 30:
		s.tick_local(K.no_input())
	var later := s.current_frame().snap
	assert_eq([later.actor(0).x, later.actor(0).y], [a.pos[60], a.pos[61]], K.say("TEST-03", "cassette one at local tick 30 after 30 ticks"))


# ───────────────────────────── TEST-04 ─────────────────────────────


## TEST-04 - Record a later tape.
## Expected: "Prior tapes are visible/simulated; unrecorded future tapes do not appear."
func test_TEST04_prior_tapes_are_simulated_while_recording_and_future_tapes_do_not_appear() -> void:
	var level := K.rescue_room()
	var s := K.new_session(level)
	# Cassette one alone: only itself.
	s.act(SessionAction.RECORD)
	assert_eq(_actor_tapes(s.current_frame().snap), [0], K.say("TEST-04", "first take sees only itself"))
	s.abort_take()
	if not assert_true(K.take_a_to_decision(s)):
		return
	var solo := s.resolution
	s.act(SessionAction.COMMIT)
	var events := K.record_with(s, null)
	# While B was recorded, A was in the world and simulated: it died to the turret exactly when it
	# does in its own resolved run (the world reacted to it, it is not a drawing).
	var a_death := K.first_event(events, SimEventType.SELF_DEATH, 0)
	assert_true(a_death != null and K.first_event(solo.events, SimEventType.SELF_DEATH, 0) != null, K.say("TEST-04", "the prior tape is simulated: the turret kills it again while B records"))
	assert_true(K.events_of(events, SimEventType.ENEMY_SHOT, 0).size() > 0, K.say("TEST-04", "the turret targets the prior tape"))
	# Visible: present in every snapshot of the take; future cassettes never appear.
	K.advance_until_phase_changes(s)
	assert_true(s.act(SessionAction.RETRY_TAKE))
	s.act(SessionAction.RECORD)
	K.advance_until_phase_changes(s, 10.0)
	var bad := 0
	var n := 0
	while s.phase == SessionPhase.RECORDING:
		s.tick_local(K.no_input())
		var snap := s.current_frame().snap
		if _actor_tapes(snap) != [0, 1]:
			bad += 1
		n += 1
		if n == 40:
			var v := s.view()
			assert_eq(v.decks[2].status, DeckStatus.EMPTY, K.say("TEST-04", "deck 3 while recording deck 2"))
			assert_eq(v.decks[3].status, DeckStatus.EMPTY, K.say("TEST-04", "deck 4 while recording deck 2"))
			assert_eq(v.decks[2].life, -1, K.say("TEST-04", "no self for deck 3"))
			assert_eq(v.decks[3].life, -1, K.say("TEST-04", "no self for deck 4"))
	assert_true(n > 0)
	assert_eq(bad, 0, K.say("TEST-04", "snapshots whose selves are not exactly [A (prior), B (live)]"))
	assert_eq(s.resolution.frames[0].actors.size(), 2, K.say("TEST-04", "the resolved run has exactly the recorded tapes"))


# ───────────────────────────── TEST-05 ─────────────────────────────


## TEST-05 - Retry the currently active cassette before advancing.
## Expected: "Earlier committed takes remain; the current take can be replaced."
func test_TEST05_retry_replaces_the_current_take_and_keeps_the_committed_ones() -> void:
	var s := K.new_session(K.rescue_room())
	if not assert_true(K.take_a_to_decision(s)):
		return
	s.act(SessionAction.COMMIT)
	var committed_a: ODTape = s.committed_tapes[0]
	var a_copy := committed_a.copy()
	K.record_with(s, null)
	K.advance_until_phase_changes(s)
	var first := s.pending_tape
	assert_true(first != null)
	assert_true(SessionAction.RETRY_TAKE in s.actions(), K.say("TEST-05", "retry is offered at the decision"))
	assert_true(s.act(SessionAction.RETRY_TAKE))
	assert_eq(s.phase, SessionPhase.SETUP)
	assert_true(s.pending_tape == null, K.say("TEST-05", "the retried take is discarded"))
	assert_eq(s.active_index, 1, K.say("TEST-05", "the same cassette is armed again"))
	assert_eq(s.committed_tapes.size(), 1, K.say("TEST-05", "earlier committed takes remain"))
	assert_true(s.committed_tapes[0] == committed_a, K.say("TEST-05", "the committed tape object is untouched"))
	assert_true(TapeLib.tapes_equal(s.committed_tapes[0], a_copy), K.say("TEST-05", "the committed tape data is untouched"))
	assert_true(K.set_speed(s, 2.0))
	K.record_with(s, K.tape_b_script())
	var second := s.pending_tape
	assert_true(second != null and second != first, K.say("TEST-05", "the current take was replaced"))
	assert_eq([second.index, second.speed], [1, 2.0], K.say("TEST-05", "the replacement is cassette two at its new speed"))
	assert_true(TapeLib.tapes_equal(s.committed_tapes[0], a_copy), K.say("TEST-05", "cassette one still untouched"))
	# The replacement counts: A + the new B win (the old B could not).
	assert_true(s.resolution.outcome.win, K.say("TEST-05", "the run is resolved with the replacement take"))


# ───────────────────────────── TEST-06 ─────────────────────────────


## TEST-06 - Change any older tape after advancing.
## Expected: "Every cassette in the attempt is reset, including those before the edited tape."
func test_TEST06_changing_an_older_tape_resets_every_cassette_including_earlier_ones() -> void:
	var s := K.new_session(K.rescue_room())
	if not assert_true(K.take_a_to_decision(s)):
		return
	s.act(SessionAction.COMMIT)
	K.record_with(s, null)
	K.advance_until_phase_changes(s)
	s.act(SessionAction.COMMIT)
	assert_eq(s.committed_tapes.size(), 2)
	assert_eq(s.active_index, 2)
	# There is no way to touch cassette one or two alone after advancing: the only offered action
	# that affects them is resetAll.
	var acts := s.actions()
	for forbidden: StringName in [SessionAction.RETRY_TAKE, SessionAction.COMMIT]:
		assert_false(forbidden in acts, K.say("TEST-06", "%s offered after advancing" % forbidden))
		assert_false(s.act(forbidden), K.say("TEST-06", "%s accepted after advancing" % forbidden))
	assert_true(SessionAction.RESET_ALL in acts, K.say("TEST-06", "resetAll is the way to change an older tape"))
	s.act(SessionAction.RECORD)
	assert_eq(s.live_sim.config.live.index, 2, K.say("TEST-06", "recording can only arm the next cassette"))
	s.abort_take()
	assert_true(s.act(SessionAction.RESET_ALL))
	assert_eq(s.phase, SessionPhase.SETUP)
	assert_eq(s.committed_tapes.size(), 0, K.say("TEST-06", "every committed cassette is reset, including cassette one"))
	assert_true(s.pending_tape == null)
	assert_true(s.resolution == null, K.say("TEST-06", "no resolved run survives the reset"))
	assert_eq(s.active_index, 0, K.say("TEST-06", "cassette one is armed again"))
	assert_eq(s.boss_memory.observed.size(), 0, K.say("TEST-06", "boss memory of the reset tapes is gone"))
	var v := s.view()
	var statuses: Array = []
	for d: DeckView in v.decks:
		statuses.append(d.status)
		assert_eq(d.state_marks.size(), 0, K.say("TEST-06", "deck %d keeps no marks" % d.index))
	assert_eq(statuses, [DeckStatus.ARMED, DeckStatus.EMPTY, DeckStatus.EMPTY, DeckStatus.EMPTY], K.say("TEST-06", "deck statuses after reset"))
	s.act(SessionAction.RECORD)
	assert_eq(s.live_sim.config.tapes.size(), 0, K.say("TEST-06", "the next take plays against no earlier cassette"))
	assert_eq(_actor_tapes(s.current_frame().snap), [0])
	# The pause-menu restart does the same from any phase before the win.
	s.abort_take()
	K.record_with(s, null)
	assert_true(s.restart_attempt())
	assert_eq(s.committed_tapes.size() + (1 if s.pending_tape != null else 0), 0, K.say("TEST-06", "restart wipes the attempt"))


# ───────────────────────────── TEST-31 ─────────────────────────────


## TEST-31 - Finish a failed final encounter.
## Expected: "Playback may finish for observation; the player can reset/end early."
func test_TEST31_a_failed_final_playback_may_finish_and_the_player_can_end_it_early_or_reset() -> void:
	# Left alone: the failed run plays to the horizon at true speed, then waits for a decision.
	var s := K.new_session(K.rescue_room(1))
	K.record_with(s, K.tape_a_script())
	assert_eq(s.phase, SessionPhase.REVIEW, K.say("TEST-31", "a failed final take is played back"))
	assert_false(s.resolution.outcome.win)
	var res := s.resolution
	s.drain_events()
	var events: Array[SimEvent] = []
	var wall := 0.0
	while s.phase == SessionPhase.REVIEW and wall < 600.0:
		s.advance(K.STEP)
		wall += K.STEP
		events.append_array(s.drain_events())
	assert_eq(s.phase, SessionPhase.DECISION, K.say("TEST-31", "after finishing it waits for the player"))
	assert_near(wall, res.horizon_subs / float(OD.SUB_HZ), 0.05, K.say("TEST-31", "it played the whole encounter at true speed"))
	assert_eq(K.event_rows(events), K.event_rows(res.events), K.say("TEST-31", "the whole run was shown"))
	assert_true(s.current_frame().snap == res.frames[res.frames.size() - 1], K.say("TEST-31", "it ends on the final frame"))
	for i: int in 300:
		s.advance(K.STEP)
	assert_eq(s.phase, SessionPhase.DECISION, K.say("TEST-31", "nothing is decided for the player"))
	assert_true(s.committed_tapes.is_empty())
	# End early: the review offers skip / endAttempt at once.
	var e := K.new_session(K.rescue_room(1))
	K.record_with(e, K.tape_a_script())
	assert_true(SessionAction.END_ATTEMPT in e.actions(), K.say("TEST-31", "end early offered during the failed playback"))
	assert_true(SessionAction.SKIP in e.actions())
	e.advance(1.5)
	assert_eq(e.phase, SessionPhase.REVIEW)
	assert_true(e.act(SessionAction.END_ATTEMPT), K.say("TEST-31", "end early"))
	assert_eq(e.phase, SessionPhase.DECISION)
	var acts := e.view().actions
	assert_true(SessionAction.RESET_ALL in acts, K.say("TEST-31", "reset offered"))
	assert_true(SessionAction.RETRY_TAKE in acts)
	assert_false(SessionAction.COMMIT in acts, K.say("TEST-31", "a failed FINAL cassette cannot be committed"))
	assert_false(e.view().outcome.win)
	assert_true(e.act(SessionAction.RESET_ALL), K.say("TEST-31", "reset"))
	assert_eq(e.phase, SessionPhase.SETUP)


# ───────────────────────────── TEST-32 ─────────────────────────────


## TEST-32 - Watch a successful cinematic.
## Expected: "Controls do not alter the result; all tapes use correct master timing and extra
## music-linked visuals." The music-linked visuals are checked here at the data level (the fx
## catalogue keeps a cinematic-only tier); how they look is by eye.
func test_TEST32_the_cinematic_ignores_controls_plays_every_tape_at_master_timing_with_cinematic_fx() -> void:
	var level := K.rescue_room()
	var lo := TestLoadout.base_loadout()
	var s := K.new_session(level, lo)
	if not assert_true(K.take_a_to_decision(s)):
		return
	s.act(SessionAction.COMMIT)
	K.set_speed(s, 2.0)
	K.record_with(s, K.tape_b_script())
	if not assert_eq(s.phase, SessionPhase.CINEMATIC, K.say("TEST-32", "a winning take plays as the cinematic")):
		return
	var res := s.resolution
	var a: ODTape = s.committed_tapes[0]
	var b := s.pending_tape
	var tapes: Array[ODTape] = [a, b]
	var committed_only: Array[ODTape] = [a]
	var independent := K.resolve(level, tapes, lo, BossMemoryLib.build_boss_memory(level, committed_only))
	assert_json_eq(res.to_dict(), independent.to_dict(), 0.0, K.say("TEST-32", "the cinematic is the authoritative resolution"))
	var before := res.to_dict()
	s.drain_events()
	var drawn: Array[FrameSnapshot] = []
	var events: Array[SimEvent] = []
	var steps := 0
	var refused := true
	while s.phase == SessionPhase.CINEMATIC and steps < 100000:
		refused = refused and not s.tick_local(K.all_buttons())
		for act: StringName in [SessionAction.RETRY_TAKE, SessionAction.COMMIT, SessionAction.RESET_ALL, SessionAction.RECORD, SessionAction.END_ATTEMPT, SessionAction.SPEED_UP, SessionAction.SPEED_DOWN, SessionAction.CYCLE_END_MODE, SessionAction.START]:
			refused = refused and not s.act(act)
		refused = refused and not s.restart_attempt()
		s.advance(K.STEP)
		var f := s.current_frame()
		drawn.append(f.prev)
		events.append_array(s.drain_events())
		steps += 1
	assert_true(refused, K.say("TEST-32", "some control was accepted during the cinematic"))
	assert_eq(s.phase, SessionPhase.RESULTS)
	assert_true(s.resolution == res, K.say("TEST-32", "the result object is unchanged"))
	assert_json_eq(s.resolution.to_dict(), before, 0.0, K.say("TEST-32", "controls did not alter the result"))
	assert_true(s.view().outcome.win)
	# Every drawn frame is one of the resolution's own snapshots, in order, ending on the last.
	var last := -1
	var out_of_order := 0
	for f: FrameSnapshot in drawn:
		var i := res.frames.find(f)
		if i < last or i < 0:
			out_of_order += 1
		last = maxi(last, i)
	assert_eq(out_of_order, 0, K.say("TEST-32", "frames not taken verbatim / in order"))
	assert_eq(last, res.frames.size() - 1)
	# True master speed: one wall second per master second.
	var expect_steps := res.horizon_subs / float(OD.SUB_HZ) * 60.0
	assert_true(absf(steps - expect_steps) <= 2.0, K.say("TEST-32", "%d frames for %.1f expected" % [steps, expect_steps]))
	assert_eq(K.event_rows(events), K.event_rows(res.events), K.say("TEST-32", "every resolved event re-emitted once in order"))
	# All tapes use correct master timing: tape j is at local tick k * speed_j / 4 at master substep k
	# on its first traversal (A at 1x, B at 2x), in every stored frame.
	var off := 0
	for f: FrameSnapshot in res.frames:
		for t: ODTape in tapes:
			var act_snap := f.actor(t.index)
			if f.sub <= ODTime.traversal_subs(t) and absf(act_snap.phase.tick - f.sub * t.speed / 4.0) > 1e-9:
				off += 1
	assert_eq(off, 0, K.say("TEST-32", "frames where a tape is off its master timing"))
	# Extra music-linked visuals: the fx catalogue has a cinematic-only tier of flourishes.
	var cine_only: Array[StringName] = []
	for id: StringName in FxCatalog.EFFECT_IDS:
		if FxCatalog.effect_allowed(id, ViewMode.CINEMATIC) and not FxCatalog.effect_allowed(id, ViewMode.REVIEW) and not FxCatalog.effect_allowed(id, ViewMode.RECORD):
			cine_only.append(id)
	assert_true(cine_only.size() >= 3, K.say("TEST-32", "cinematic-only flourishes: %s" % [cine_only]))
	assert_true(FxCatalog.profile(ViewMode.CINEMATIC).max_tier > FxCatalog.profile(ViewMode.RECORD).max_tier, K.say("TEST-32", "cinematic allows more than recording"))
