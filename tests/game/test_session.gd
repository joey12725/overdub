extends ODTest
## Session state machine (ARCHITECTURE "Session flow"; REC-01..08, OPEN-07, OPEN-21; TEST-03..06,
## TEST-31, TEST-32), driven headlessly. Port of prototype/tests/game/session.test.ts, plus the port's
## resolving beat (async resolve on a worker thread).

const F = preload("res://tests/game/game_fixtures.gd")
const STEP := F.STEP


func _sandbox_loadout() -> ResolvedLoadout:
	return LoadoutRules.resolve_loadout(CampaignData.base_loadout())


## Record take A on the rescue room and play its review through to the decision.
func _take_a_to_decision(s: GameSession) -> bool:
	F.record_with(s, F.tape_a())
	if not assert_eq(s.phase, SessionPhase.REVIEW, "take A ends in review"):
		return false
	F.advance_until_phase_changes(s)
	return assert_eq(s.phase, SessionPhase.DECISION, "review ends in decision")


## Compare the listed DeckView fields (prototype toMatchObject).
func _deck_matches(d: DeckView, want: Dictionary, msg: String) -> void:
	for k: String in want:
		var got: Variant = d.get(k)
		if got is Array:
			assert_eq(F.dicts(got), want[k], "%s.%s" % [msg, k])
		else:
			assert_eq(got, want[k], "%s.%s" % [msg, k])


# ───────────────────────────── phase order (sandbox) ─────────────────────────────


func test_briefing_setup_countin_recording_review_decision_with_a_four_beat_count_in() -> void:
	var errors: Array[String] = []
	var s := GameSession.create(CampaignData.sandbox(), _sandbox_loadout(), false, false, errors)
	if not assert_true(s != null, ", ".join(errors)):
		return
	assert_eq(s.phase, SessionPhase.BRIEFING)
	assert_eq(s.view().actions, [SessionAction.START, SessionAction.QUIT])
	assert_false(s.act(SessionAction.RECORD))
	assert_true(s.act(SessionAction.START))
	assert_eq(s.phase, SessionPhase.SETUP)
	assert_true(s.act(SessionAction.RECORD))
	assert_eq(s.phase, SessionPhase.COUNTIN)
	assert_eq(s.view().count, 5)
	assert_false(s.tick_local(F.no_input()))
	assert_eq(s.live_sim.local_tick, 0)

	# 120 bpm: one count per 0.5 s of wall time (UI-04), at the base tempo regardless of speed.
	var counts: Array[int] = []
	var t := 0.0
	while t < 1.99:
		s.advance(0.01)
		var c := s.view().count
		if not counts.has(c):
			counts.append(c)
		t += 0.01
	assert_eq(s.phase, SessionPhase.COUNTIN)
	assert_eq(counts, [5, 6, 7, 8])
	assert_eq(s.live_sim.local_tick, 0)
	s.advance(0.02)
	assert_eq(s.phase, SessionPhase.RECORDING)
	assert_eq(s.view().count, 0)

	var ticks := 0
	while s.phase == SessionPhase.RECORDING:
		s.tick_local(F.no_input())
		ticks += 1
	assert_eq(ticks, s.tape_ticks)
	assert_eq(s.phase, SessionPhase.REVIEW)
	F.advance_until_phase_changes(s)
	assert_eq(s.phase, SessionPhase.DECISION)
	assert_eq(s.view().actions, [SessionAction.RETRY_TAKE, SessionAction.COMMIT, SessionAction.RESET_ALL, SessionAction.QUIT])

	var cues := s.drain_cues()
	assert_eq(F.phases_of(cues), [SessionPhase.SETUP, SessionPhase.COUNTIN, SessionPhase.RECORDING, SessionPhase.REVIEW, SessionPhase.DECISION])
	var ns: Array[int] = []
	for c: GameSession.Cue in cues:
		if c.kind == GameSession.CUE_COUNT:
			ns.append(c.n)
	assert_eq(ns, [5, 6, 7, 8])


func test_nothing_auto_commits_the_decision_waits_for_the_player() -> void:
	var s := F.new_session(CampaignData.sandbox(), _sandbox_loadout())
	F.record_with(s, F.no_input)
	F.advance_until_phase_changes(s)
	for i in 600:
		s.advance(STEP)
	assert_eq(s.phase, SessionPhase.DECISION)
	assert_eq(s.committed_tapes.size(), 0)
	assert_true(s.pending_tape != null)


func test_speed_and_end_mode_are_constrained_to_what_the_level_offers() -> void:
	var s := F.new_session(F.rescue_room())
	assert_eq(s.speed, 1.0)
	assert_eq(s.view().speeds, [1.0, 2.0])
	assert_false(s.act(SessionAction.SPEED_DOWN))
	assert_true(s.act(SessionAction.SPEED_UP))
	assert_eq(s.speed, 2.0)
	assert_false(s.act(SessionAction.SPEED_UP))
	assert_eq(s.end_mode, OD.EndMode.STOP)
	var modes: Array[int] = [s.end_mode]
	for i in 3:
		s.act(SessionAction.CYCLE_END_MODE)
		modes.append(s.end_mode)
	assert_eq(modes, [OD.EndMode.STOP, OD.EndMode.REPEAT, OD.EndMode.REVERSE, OD.EndMode.STOP])

	var hall := F.new_session(F.laser_hall())
	assert_false(hall.view().actions.has(SessionAction.CYCLE_END_MODE))
	assert_false(hall.act(SessionAction.CYCLE_END_MODE))
	assert_false(hall.act(SessionAction.SPEED_UP))


func test_a_level_the_kernel_cannot_run_fails_at_creation_with_a_reason() -> void:
	var lv := F.rescue_room()
	lv.speeds = []
	var errors: Array[String] = []
	assert_true(GameSession.create(lv, TestLoadout.base_loadout(), true, false, errors) == null)
	assert_true(errors.size() == 1 and errors[0].contains("offers no tape speeds"), str(errors))
	var lv2 := F.rescue_room()
	lv2.end_modes = []
	errors.clear()
	assert_true(GameSession.create(lv2, TestLoadout.base_loadout(), true, false, errors) == null)
	assert_true(errors.size() == 1 and errors[0].contains("offers no end modes"), str(errors))

# ───────────────────────────── takes, retries and resets (REC-02..05) ─────────────────────────────


func test_03_next_cassette_starts_at_beat_zero_with_the_committed_tape_from_its_start() -> void:
	var s := F.new_session(F.rescue_room())
	if not _take_a_to_decision(s):
		return
	var a := s.pending_tape
	assert_true(s.act(SessionAction.COMMIT))
	assert_eq(s.phase, SessionPhase.SETUP)
	assert_true(s.act(SessionAction.RECORD))
	assert_eq(s.live_sim.sub, 0)
	var snap := s.current_frame().snap
	assert_eq(snap.sub, 0)
	assert_eq(snap.beat, 0.0)
	var actor_a := snap.actor(0)
	assert_eq([actor_a.x, actor_a.y], [a.pos[0], a.pos[1]])
	assert_eq(actor_a.phase.tick, 0.0)
	assert_eq(actor_a.life, OD.LifeState.ALIVE)


func test_04_only_recorded_tapes_are_present_while_recording_future_cassettes_do_not_exist() -> void:
	var s := F.new_session(F.rescue_room())
	s.act(SessionAction.RECORD)
	assert_eq(s.live_sim.config.tapes.size(), 0)
	assert_eq(F.actor_tapes(s.current_frame().snap), [0])
	s.abort_take()
	if not _take_a_to_decision(s):
		return
	s.act(SessionAction.COMMIT)
	s.act(SessionAction.RECORD)
	var committed := s.committed_tapes
	assert_eq(s.live_sim.config.tapes.size(), 1)
	assert_true(s.live_sim.config.tapes[0] == committed[0], "the committed tape object itself plays")
	F.advance_until_phase_changes(s, 10.0)
	s.tick_local(F.no_input())
	assert_eq(F.actor_tapes(s.current_frame().snap), [0, 1])
	var decks := s.view().decks
	assert_eq(decks[2].status, DeckStatus.EMPTY)
	assert_eq(decks[3].status, DeckStatus.EMPTY)


func test_05_retry_take_replaces_only_the_current_take_committed_tapes_are_untouched() -> void:
	var s := F.new_session(F.rescue_room())
	if not _take_a_to_decision(s):
		return
	s.act(SessionAction.COMMIT)
	var committed_before := s.committed_tapes
	F.record_with(s, F.no_input)
	F.advance_until_phase_changes(s)
	var first := s.pending_tape
	assert_true(s.act(SessionAction.RETRY_TAKE))
	assert_eq(s.phase, SessionPhase.SETUP)
	assert_true(s.pending_tape == null)
	assert_eq(s.active_index, 1)
	assert_eq(s.committed_tapes.size(), 1)
	assert_true(s.committed_tapes[0] == committed_before[0])
	assert_true(F.set_speed(s, 2.0))
	F.record_with(s, F.tape_b())
	var second := s.pending_tape
	assert_true(second != first)
	assert_eq(second.index, 1)
	assert_eq(second.speed, 2.0)
	assert_true(s.committed_tapes[0] == committed_before[0])


func test_retry_reuses_the_committed_run_and_matches_a_fresh_resolve() -> void:
	# Port deviation: retry keeps the committed-only run instead of re-resolving; it must equal what
	# the prototype would have recomputed.
	var lv := F.rescue_room()
	var s := F.new_session(lv)
	if not _take_a_to_decision(s):
		return
	s.act(SessionAction.COMMIT)
	F.record_with(s, F.no_input)
	F.advance_until_phase_changes(s)
	s.act(SessionAction.RETRY_TAKE)
	var fresh := ODResolve.resolve_encounter(SimConfig.make(lv, TestLoadout.base_loadout(), s.committed_tapes, null, s.boss_memory))
	assert_true(s.resolution != null)
	assert_json_eq(s.resolution.outcome.to_dict(), fresh.outcome.to_dict())
	assert_json_eq(F.dicts(s.resolution.events), F.dicts(fresh.events))
	assert_eq(s.resolution.frames.size(), fresh.frames.size())
	assert_json_eq(s.resolution.frames[s.resolution.frames.size() - 1].to_dict(), fresh.frames[fresh.frames.size() - 1].to_dict())


func test_06_an_older_cassette_cannot_be_rerecorded_except_by_reset_all_which_wipes_every_cassette() -> void:
	var s := F.new_session(F.rescue_room())
	if not _take_a_to_decision(s):
		return
	s.act(SessionAction.COMMIT)
	F.record_with(s, F.no_input)
	F.advance_until_phase_changes(s)
	s.act(SessionAction.COMMIT)
	assert_eq(s.committed_tapes.size(), 2)
	assert_eq(s.active_index, 2)
	# No offered action touches cassette A or B.
	assert_eq(s.view().actions, [SessionAction.SPEED_UP, SessionAction.CYCLE_END_MODE, SessionAction.RECORD, SessionAction.RESET_ALL, SessionAction.QUIT])
	assert_false(s.act(SessionAction.RETRY_TAKE))
	assert_false(s.act(SessionAction.COMMIT))
	s.act(SessionAction.RECORD)
	assert_eq(s.live_sim.config.live.index, 2)
	s.abort_take()

	assert_true(s.act(SessionAction.RESET_ALL))
	assert_eq(s.phase, SessionPhase.SETUP)
	assert_eq(s.committed_tapes.size(), 0)
	assert_true(s.pending_tape == null)
	assert_true(s.resolution == null)
	assert_eq(s.active_index, 0)
	assert_eq(s.boss_memory.observed.size(), 0)
	var v := s.view()
	assert_eq(F.statuses(v), [DeckStatus.ARMED, DeckStatus.EMPTY, DeckStatus.EMPTY, DeckStatus.EMPTY])
	for d: DeckView in v.decks:
		assert_eq(d.state_marks.size(), 0)
	s.act(SessionAction.RECORD)
	assert_eq(s.live_sim.config.tapes.size(), 0)


func test_reset_all_from_the_decision_wipes_the_pending_take_and_every_committed_one() -> void:
	var s := F.new_session(F.rescue_room())
	if not _take_a_to_decision(s):
		return
	s.act(SessionAction.COMMIT)
	F.record_with(s, F.no_input)
	F.advance_until_phase_changes(s)
	assert_true(s.act(SessionAction.RESET_ALL))
	assert_eq(s.committed_tapes.size(), 0)
	assert_true(s.pending_tape == null)
	assert_eq(s.active_index, 0)


func test_open_21_pausing_mid_take_aborts_the_take_back_to_setup() -> void:
	var s := F.new_session(F.rescue_room())
	if not _take_a_to_decision(s):
		return
	s.act(SessionAction.COMMIT)
	var committed := s.committed_tapes
	s.act(SessionAction.RECORD)
	assert_true(s.abort_take())
	assert_eq(s.phase, SessionPhase.SETUP)
	s.act(SessionAction.RECORD)
	F.advance_until_phase_changes(s, 10.0)
	for i in 50:
		s.tick_local(F.no_input())
	s.drain_cues()
	assert_true(s.abort_take())
	var kinds: Array[StringName] = []
	for c: GameSession.Cue in s.drain_cues():
		kinds.append(c.kind)
	assert_eq(kinds, [GameSession.CUE_TAKE_ABORTED, GameSession.CUE_PHASE])
	assert_eq(s.phase, SessionPhase.SETUP)
	assert_true(s.live_sim == null)
	assert_true(s.pending_tape == null)
	assert_eq(s.committed_tapes, committed)
	assert_eq(s.active_index, 1)
	assert_false(s.abort_take())


func test_pause_menu_restart_wipes_the_attempt_from_any_phase_before_the_win() -> void:
	var s := F.new_session(F.rescue_room())
	if not _take_a_to_decision(s):
		return
	s.act(SessionAction.COMMIT)
	F.record_with(s, F.no_input)
	assert_eq(s.phase, SessionPhase.REVIEW)
	assert_true(s.restart_attempt())
	assert_eq(s.phase, SessionPhase.SETUP)
	assert_eq(s.committed_tapes.size(), 0)

# ───────────────────────────── authoritative result, review and cinematic ─────────────────────────────


func test_32_a_win_plays_the_locked_cinematic_whose_frames_are_exactly_the_resolution_frames() -> void:
	var level := F.rescue_room()
	var loadout := TestLoadout.base_loadout()
	var s := F.new_session(level, loadout)
	if not _take_a_to_decision(s):
		return
	s.act(SessionAction.COMMIT)
	F.set_speed(s, 2.0)
	F.record_with(s, F.tape_b())
	if not assert_eq(s.phase, SessionPhase.CINEMATIC):
		return
	assert_true(s.outcome.win)
	assert_eq(s.tapes_used, 2)

	var a := s.committed_tapes[0]
	var b := s.pending_tape
	var both: Array[ODTape] = [a, b]
	var only_a: Array[ODTape] = [a]
	var expected := ODResolve.resolve_encounter(SimConfig.make(level, loadout, both, null, BossMemoryLib.build_boss_memory(level, only_a)))
	var res := s.resolution
	assert_json_eq(F.dicts(res.frames), F.dicts(expected.frames), 0.0, "frames")
	assert_json_eq(F.dicts(res.events), F.dicts(expected.events), 0.0, "events")
	assert_json_eq(res.outcome.to_dict(), expected.outcome.to_dict(), 0.0, "outcome")

	s.drain_events()
	var drawn: Array[FrameSnapshot] = []
	var events: Array[SimEvent] = []
	var k := 0
	var locked := true
	var alpha_ok := true
	while s.phase == SessionPhase.CINEMATIC:
		# TEST-32 / CINE-02: gameplay input does nothing during the cinematic.
		if s.tick_local(F.all_buttons()):
			locked = false
		for act: StringName in [SessionAction.RETRY_TAKE, SessionAction.COMMIT, SessionAction.RESET_ALL, SessionAction.RECORD, SessionAction.END_ATTEMPT, SessionAction.SPEED_UP, SessionAction.CYCLE_END_MODE, SessionAction.START]:
			if s.act(act):
				locked = false
		s.advance(STEP)
		var f := s.current_frame()
		drawn.append(f.prev)
		events.append_array(s.drain_events())
		if f.alpha < 0.0 or f.alpha > 1.0:
			alpha_ok = false
		k += 1
		if k > 100000:
			fail("cinematic never ended")
			return
	assert_true(locked, "no gameplay input or decision is accepted during the cinematic")
	assert_true(alpha_ok, "alpha stays in 0..1")
	assert_eq(s.phase, SessionPhase.RESULTS)
	assert_true(s.resolution == res)
	assert_eq(s.committed_tapes, [a])
	# Every drawn frame is one of the resolution's own snapshots, in order, ending on the last.
	var last := -1
	var ordered := true
	for f: FrameSnapshot in drawn:
		var i := res.frames.find(f)
		if i < last:
			ordered = false
		last = i
	assert_true(ordered, "drawn frames are resolution frames in order")
	assert_eq(last, res.frames.size() - 1)
	# True master speed: one wall second per master second (CINE-01, CINE-04).
	assert_true(k >= floori(res.horizon_subs / 240.0 * 60.0) - 1, "k=%d" % k)
	assert_true(k <= ceili(res.horizon_subs / 240.0 * 60.0) + 1, "k=%d" % k)
	# Every resolved event is re-emitted once, in order, for audio / fx.
	assert_eq(events, res.events)
	assert_true(s.view().outcome.win)
	assert_eq(s.view().actions, [SessionAction.CONTINUE, SessionAction.QUIT])


func test_the_cinematic_can_be_skipped_to_results_without_changing_the_result() -> void:
	var s := F.new_session(F.rescue_room())
	if not _take_a_to_decision(s):
		return
	s.act(SessionAction.COMMIT)
	F.set_speed(s, 2.0)
	F.record_with(s, F.tape_b())
	var res := s.resolution
	s.advance(1.0)
	assert_true(s.act(SessionAction.SKIP))
	assert_eq(s.phase, SessionPhase.RESULTS)
	assert_true(s.resolution == res)
	assert_true(s.outcome.win)


func test_a_level_can_be_won_with_fewer_cassettes_than_it_offers() -> void:
	var s := F.new_session(F.rescue_room(4))
	if not _take_a_to_decision(s):
		return
	s.act(SessionAction.COMMIT)
	F.set_speed(s, 2.0)
	F.record_with(s, F.tape_b())
	assert_eq(s.phase, SessionPhase.CINEMATIC)
	assert_eq(s.tapes_used, 2)
	assert_eq(F.statuses(s.view()), [DeckStatus.COMMITTED, DeckStatus.COMMITTED, DeckStatus.EMPTY, DeckStatus.EMPTY])


func test_open_07_objectives_completed_only_by_the_recording_ghost_do_not_win() -> void:
	var s := F.new_session(F.laser_hall(2))
	F.record_with(s, F.no_input)
	F.advance_until_phase_changes(s)
	s.act(SessionAction.COMMIT)
	s.drain_events()
	# Tape B walks through the permanent laser (dies), then as a recording ghost kills the grunt.
	var steps: Array[GameBot.PlanStep] = [GameBot.PlanStep.goto_point(7.6, 5.5), GameBot.PlanStep.hold(7.6, 5.5)]
	var b := GameBot.plan_take(1.0, OD.EndMode.STOP, steps)
	var live_events: Array[SimEvent] = []
	var fn := F.plan_inputs(s, b)
	s.act(SessionAction.RECORD)
	F.advance_until_phase_changes(s, 10.0)
	var tick := 0
	while s.phase == SessionPhase.RECORDING:
		s.tick_local(fn.call(tick))
		tick += 1
		live_events.append_array(s.drain_events())
	var deaths := TestScript.events_of(live_events, SimEventType.SELF_DEATH, 1)
	var kills := TestScript.events_of(live_events, SimEventType.KILL, -1, "g1")
	assert_eq(deaths.size(), 1)
	assert_eq(kills.size(), 1)
	if deaths.size() == 1 and kills.size() == 1:
		assert_true(kills[0].sub > deaths[0].sub)
	# The provisional live run latched the objective with tape A alive…
	assert_true(TestScript.events_of(live_events, SimEventType.OBJECTIVE).size() > 0)
	# …but the authoritative playback run does not: tape B dies again and its strike never lands.
	assert_eq(s.phase, SessionPhase.REVIEW)
	var out := s.resolution.outcome
	assert_false(out.win)
	assert_false(out.objective_complete)
	assert_eq(out.reason, FailReason.OBJECTIVE)
	assert_eq(out.survivors, [0])
	assert_eq(TestScript.events_of(s.resolution.events, SimEventType.KILL).size(), 0)


func test_31_a_failed_final_cassette_can_be_ended_early_and_then_offers_only_retry_and_reset() -> void:
	var s := F.new_session(F.rescue_room(1))
	F.record_with(s, F.tape_a())
	assert_eq(s.phase, SessionPhase.REVIEW)
	assert_eq(s.view().actions, [SessionAction.SKIP, SessionAction.END_ATTEMPT])
	s.advance(1.5)
	assert_eq(s.phase, SessionPhase.REVIEW)
	assert_true(s.act(SessionAction.END_ATTEMPT))
	assert_eq(s.phase, SessionPhase.DECISION)
	var v := s.view()
	assert_eq(v.actions, [SessionAction.RETRY_TAKE, SessionAction.RESET_ALL, SessionAction.QUIT])
	assert_false(v.outcome.win)
	assert_false(s.act(SessionAction.COMMIT))
	assert_eq(s.committed_tapes.size(), 0)
	assert_true(s.act(SessionAction.RETRY_TAKE))
	assert_eq(s.phase, SessionPhase.SETUP)


func test_31_left_alone_a_failed_playback_runs_to_the_horizon_and_then_waits_for_a_decision() -> void:
	var s := F.new_session(F.rescue_room(1))
	F.record_with(s, F.tape_a())
	var res := s.resolution
	s.drain_events()
	var events: Array[SimEvent] = []
	var wall := 0.0
	while s.phase == SessionPhase.REVIEW:
		s.advance(STEP)
		wall += STEP
		events.append_array(s.drain_events())
	assert_eq(s.phase, SessionPhase.DECISION)
	assert_near(wall, res.horizon_subs / 240.0, 0.05)
	assert_eq(events, res.events)
	assert_true(s.current_frame().snap == res.frames[res.frames.size() - 1])


func test_skipping_a_review_drops_the_rest_of_its_playback_events() -> void:
	var s := F.new_session(F.rescue_room(1))
	F.record_with(s, F.tape_a())
	s.drain_events()
	s.advance(0.5)
	var early := s.drain_events()
	s.act(SessionAction.SKIP)
	assert_eq(s.drain_events().size(), 0)
	assert_true(early.size() < s.resolution.events.size())

# ───────────────────────────── boss memory (BOSS-01/02) ─────────────────────────────


func test_boss_memory_is_rebuilt_only_from_committed_tapes_on_commit_and_reset() -> void:
	var level := F.rescue_room()
	var s := F.new_session(level)
	assert_eq(s.boss_memory_builds, 1)
	assert_eq(s.boss_memory.observed.size(), 0)
	var m0 := s.boss_memory

	s.act(SessionAction.RECORD)
	assert_true(s.live_sim.config.boss_memory == m0)
	s.abort_take()
	if not _take_a_to_decision(s):
		return
	assert_true(s.boss_memory == m0)
	s.act(SessionAction.RETRY_TAKE)
	assert_true(s.boss_memory == m0)
	if not _take_a_to_decision(s):
		return
	s.act(SessionAction.COMMIT)
	assert_eq(s.boss_memory_builds, 2)
	var m1 := s.boss_memory
	assert_json_eq(m1.to_dict(), BossMemoryLib.build_boss_memory(level, s.committed_tapes).to_dict())
	var obs_tapes: Array[int] = []
	for o: BossObservation in m1.observed:
		obs_tapes.append(o.tape)
	assert_eq(obs_tapes, [0])

	F.set_speed(s, 2.0)
	s.act(SessionAction.RECORD)
	assert_true(s.live_sim.config.boss_memory == m1)
	s.abort_take()
	F.record_with(s, F.tape_b())
	assert_eq(s.phase, SessionPhase.CINEMATIC)
	assert_true(s.boss_memory == m1)
	while s.phase == SessionPhase.CINEMATIC:
		s.advance(0.25)
	assert_eq(s.phase, SessionPhase.RESULTS)
	assert_true(s.boss_memory == m1)
	assert_eq(s.boss_memory_builds, 2)


func test_reset_all_rebuilds_boss_memory_empty() -> void:
	var s := F.new_session(F.rescue_room())
	if not _take_a_to_decision(s):
		return
	s.act(SessionAction.COMMIT)
	assert_eq(s.boss_memory.observed.size(), 1)
	s.act(SessionAction.RESET_ALL)
	assert_eq(s.boss_memory.observed.size(), 0)
	assert_eq(s.boss_memory_builds, 3)

# ───────────────────────────── SessionView decks (UI-06, UI-07, NEW-07..11) ─────────────────────────────


func test_view_reports_every_deck_status_with_its_fields() -> void:
	var level := F.rescue_room(3)
	var s := F.new_session(level)
	var v := s.view()
	assert_eq(v.phase, SessionPhase.SETUP)
	assert_eq(v.active, 0)
	assert_eq(v.world_rate, 0.0)
	assert_eq(v.horizon_beats, level.horizon_bars * 4.0)
	assert_eq(F.statuses(v), [DeckStatus.ARMED, DeckStatus.EMPTY, DeckStatus.EMPTY, DeckStatus.UNAVAILABLE])
	_deck_matches(v.decks[0], {"index": 0, "speed": 1.0, "end_mode": OD.EndMode.STOP, "transport": 0, "reel_rate": 0.0, "life": OD.LifeState.ALIVE, "synced": true, "span_bars": 4.0, "marks": []}, "setup deck 0")
	_deck_matches(v.decks[1], {"speed": 0.0, "end_mode": -1, "life": -1, "span_bars": 0.0, "reel_rate": 0.0, "marks": [], "state_marks": []}, "setup deck 1")
	_deck_matches(v.decks[3], {"status": DeckStatus.UNAVAILABLE, "speed": 0.0, "life": -1}, "setup deck 3")

	s.act(SessionAction.SPEED_UP)
	v = s.view()
	_deck_matches(v.decks[0], {"speed": 2.0, "span_bars": 2.0}, "2x deck 0")
	s.act(SessionAction.SPEED_DOWN)

	# recording
	s.act(SessionAction.RECORD)
	assert_eq(s.view().decks[0].status, DeckStatus.ARMED)
	F.advance_until_phase_changes(s, 10.0)
	var sc := F.tape_a()
	for t in 120:
		s.tick_local(sc.input(t))
	v = s.view()
	assert_eq(v.world_rate, 1.0)
	_deck_matches(v.decks[0], {"status": DeckStatus.RECORDING, "transport": 1, "reel_rate": 1.0}, "recording deck 0")
	assert_near(v.decks[0].local_progress, 120.0 / s.tape_ticks, 1e-5)
	assert_json_eq(F.dicts(v.decks[0].marks), [{"tick": 100, "kind": "light"}])
	var kinds: Array[StringName] = []
	for m: DeckStateMark in v.decks[0].state_marks:
		kinds.append(m.kind)
	assert_eq(kinds, [StateMarkKind.DEATH])
	assert_eq(v.decks[0].life, OD.LifeState.REC_GHOST)
	var tick := 120
	while s.phase == SessionPhase.RECORDING:
		s.tick_local(sc.input(tick))
		tick += 1

	# review (pending)
	s.advance(0.5)
	v = s.view()
	_deck_matches(v.decks[0], {"status": DeckStatus.PENDING, "speed": 1.0, "transport": 1, "reel_rate": 1.0}, "review deck 0")
	assert_true(v.outcome == null)
	kinds.clear()
	for m: DeckStateMark in v.decks[0].state_marks:
		kinds.append(m.kind)
	assert_eq(kinds, [StateMarkKind.DEATH])
	var mk: Array[StringName] = []
	for m: DeckMark in v.decks[0].marks:
		mk.append(m.kind)
	assert_eq(mk, [ActionKind.LIGHT, ActionKind.INTERACT])

	# decision
	s.act(SessionAction.SKIP)
	v = s.view()
	_deck_matches(v.decks[0], {"status": DeckStatus.PENDING, "transport": 0, "reel_rate": 0.0, "life": OD.LifeState.GHOST}, "decision deck 0")
	assert_false(v.outcome.win)

	# committed, next deck armed
	var a := s.pending_tape
	s.act(SessionAction.COMMIT)
	v = s.view()
	assert_eq(F.statuses(v), [DeckStatus.COMMITTED, DeckStatus.ARMED, DeckStatus.EMPTY, DeckStatus.UNAVAILABLE])
	var want: Array = []
	for e: TapeEvent in a.events:
		want.append({"tick": e.tick, "kind": String(e.kind)})
	assert_json_eq(F.dicts(v.decks[0].marks), want)
	assert_eq(v.decks[0].state_marks.size(), 1)
	if v.decks[0].state_marks.size() == 1:
		assert_true(v.decks[0].state_marks[0].beat > 0.0)
	assert_eq(v.decks[0].life, OD.LifeState.ALIVE)
	assert_eq(v.hint, "")

	# A 2x take: the world runs at half speed, so the 1x committed reel spins at half the viewer's rate.
	F.set_speed(s, 2.0)
	s.act(SessionAction.RECORD)
	F.advance_until_phase_changes(s, 10.0)
	for t in 10:
		s.tick_local(F.no_input())
	v = s.view()
	assert_eq(v.world_rate, 0.5)
	_deck_matches(v.decks[1], {"status": DeckStatus.RECORDING, "speed": 2.0, "reel_rate": 1.0, "span_bars": 2.0}, "2x deck 1")
	_deck_matches(v.decks[0], {"status": DeckStatus.COMMITTED, "transport": 1, "reel_rate": 0.5}, "2x deck 0")
	assert_near(v.beat, s.current_frame().snap.sub / 120.0, 1e-9)


func test_view_shows_the_setup_hint_for_the_armed_cassette_and_the_objective_text() -> void:
	var sb := CampaignData.sandbox()
	var s := GameSession.create(sb, _sandbox_loadout())
	assert_eq(s.view().hint, "")
	s.act(SessionAction.START)
	var v := s.view()
	assert_eq(v.hint, sb.hints.get(1, ""))
	assert_true(v.hint != "", "the sandbox has a hint for tape 1")
	assert_eq(v.objective.text, sb.objective.text)
	assert_false(v.objective.complete)


func test_beat_sight_lists_upcoming_enemy_attack_beats_without_it_the_list_is_empty() -> void:
	var level := F.rescue_room(1)
	var plain := F.new_session(level)
	F.record_with(plain, F.tape_a())
	var saw_plain := false
	while plain.phase == SessionPhase.REVIEW:
		plain.advance(STEP)
		if not plain.view().threat_beats.is_empty():
			saw_plain = true
	assert_false(saw_plain)

	var sighted := F.new_session(level, TestLoadout.base_loadout({"abilities": [AbilityId.BEAT_SIGHT]}))
	F.record_with(sighted, F.tape_a())
	var shots: Array[float] = []
	for e: SimEvent in TestScript.events_of(sighted.resolution.events, SimEventType.ENEMY_SHOT):
		shots.append((e.sub + 1) / 120.0)
	assert_true(shots.size() > 0)
	var seen: Dictionary[float, bool] = {}
	var in_future := true
	while sighted.phase == SessionPhase.REVIEW:
		sighted.advance(STEP)
		var v := sighted.view()
		for b: float in v.threat_beats:
			if b < v.beat - 1e-6:
				in_future = false
			seen[floorf(b * 1000.0 + 0.5) / 1000.0] = true
	assert_true(in_future, "threat beats are never in the past")
	for b: float in shots:
		assert_true(seen.has(floorf(b * 1000.0 + 0.5) / 1000.0), "shot at beat %s was forecast" % b)


func test_track_audio_states_follow_the_decks() -> void:
	var s := F.new_session(F.rescue_room())
	var tracks := s.track_audio_states()
	var present: Array[bool] = []
	for t: TrackAudioState in tracks:
		present.append(t.present)
	assert_eq(present, [true, false, false, false])
	assert_eq(tracks[0].transport, 0)
	F.record_with(s, F.tape_a())
	s.advance(0.1)
	tracks = s.track_audio_states()
	assert_true(tracks[0].present)
	assert_eq(tracks[0].speed, 1.0)
	assert_eq(tracks[0].transport, 1)
	assert_eq(tracks[0].life, OD.LifeState.ALIVE)
	s.act(SessionAction.SKIP)
	tracks = s.track_audio_states()
	assert_true(tracks[0].present)
	assert_eq(tracks[0].transport, 0)
	assert_eq(tracks[0].life, OD.LifeState.GHOST)

# ───────────────────────────── the resolving beat (port addition) ─────────────────────────────


func _record_async(s: GameSession, input: Variant) -> void:
	F.record_with(s, input)


func _wait_resolved(s: GameSession, max_seconds: float = 30.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while s.resolving and Time.get_ticks_msec() - t0 < max_seconds * 1000.0:
		OS.delay_msec(5)
		s.advance(STEP)
	return not s.resolving


func test_async_resolve_enters_a_resolving_review_then_proceeds_exactly_as_the_synchronous_session() -> void:
	var level := F.rescue_room(1)
	var errors: Array[String] = []
	var s := GameSession.create(level, TestLoadout.base_loadout(), true, true, errors)
	if not assert_true(s != null, ", ".join(errors)):
		return
	s.drain_cues()
	F.record_with(s, F.tape_a())
	# The take is over: review, resolving, nothing offered, master time still.
	assert_eq(s.phase, SessionPhase.REVIEW)
	assert_true(s.resolving)
	var v := s.view()
	assert_true(v.resolving)
	assert_eq(v.status_text, GameSessionView.RESOLVING_TEXT)
	assert_true(v.resolve_progress >= 0.0 and v.resolve_progress <= 1.0)
	assert_eq(v.actions.size(), 0)
	assert_eq(v.world_rate, 0.0)
	assert_true(v.outcome == null)
	assert_false(s.act(SessionAction.SKIP))
	assert_eq(v.decks[0].status, DeckStatus.PENDING)
	var frozen := s.current_frame().snap
	assert_true(frozen != null and frozen.sub > 0, "the picture holds the take's last frame")
	assert_true(_wait_resolved(s), "the worker finished")
	assert_false(s.view().resolving)
	assert_eq(s.phase, SessionPhase.REVIEW)
	assert_eq(s.view().actions, [SessionAction.SKIP, SessionAction.END_ATTEMPT])

	# Cue order matches the prototype (plus the resolving cue): ... recording, resolving, resolved,
	# phase review (from recording).
	var kinds: Array[StringName] = []
	var review_from: StringName = &""
	for c: GameSession.Cue in s.drain_cues():
		kinds.append(c.kind)
		if c.kind == GameSession.CUE_PHASE and c.phase == SessionPhase.REVIEW:
			review_from = c.from
	var tail := kinds.slice(kinds.size() - 3)
	assert_eq(tail, [GameSession.CUE_RESOLVING, GameSession.CUE_RESOLVED, GameSession.CUE_PHASE])
	assert_eq(review_from, SessionPhase.RECORDING)

	# Same authoritative result as the synchronous session.
	var sync := F.new_session(level)
	F.record_with(sync, F.tape_a())
	assert_json_eq(s.resolution.outcome.to_dict(), sync.resolution.outcome.to_dict())
	assert_json_eq(F.dicts(s.resolution.events), F.dicts(sync.resolution.events))
	assert_eq(s.resolution.frames.size(), sync.resolution.frames.size())
	s.dispose()


func test_async_resolve_of_a_win_goes_to_the_cinematic_and_reset_cancels_a_running_worker() -> void:
	var errors: Array[String] = []
	var s := GameSession.create(F.rescue_room(), TestLoadout.base_loadout(), true, true, errors)
	if not assert_true(s != null, ", ".join(errors)):
		return
	F.record_with(s, F.tape_a())
	assert_true(_wait_resolved(s))
	F.advance_until_phase_changes(s)
	assert_eq(s.phase, SessionPhase.DECISION)
	s.act(SessionAction.COMMIT)
	F.set_speed(s, 2.0)
	F.record_with(s, F.tape_b())
	assert_true(s.resolving)
	assert_true(_wait_resolved(s))
	assert_eq(s.phase, SessionPhase.CINEMATIC)
	assert_true(s.outcome.win)

	# A reset while the worker runs cancels it; the session is usable straight away.
	s.restart_attempt()
	var s2 := GameSession.create(CampaignData.sandbox(), _sandbox_loadout(), true, true, errors)
	F.record_with(s2, F.no_input)
	assert_true(s2.resolving)
	assert_true(s2.act(SessionAction.RESET_ALL) == false, "nothing is offered while resolving")
	assert_true(s2.restart_attempt())
	assert_false(s2.resolving)
	assert_eq(s2.phase, SessionPhase.SETUP)
	assert_true(s2.pending_tape == null)
	s.dispose()
	s2.dispose()
