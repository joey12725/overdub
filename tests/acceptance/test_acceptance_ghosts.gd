extends ODTest
## Acceptance: death, ghosts and survival (docs/requirements.txt chapter 21: TEST-07..12, TEST-23,
## TEST-24), on the shipped core (ODSim / ODResolve) and, for the live take, GameSession.

const K = preload("res://tests/acceptance/acceptance_kit.gd")
const S = preload("res://tests/helpers/script.gd")


## TEST-07 - Die while actively recording.
## Expected: "Recording continues with a major ghost visual distinction."
func test_TEST07_dying_while_recording_continues_the_take_as_a_visibly_distinct_ghost() -> void:
	var s := K.new_session(K.rescue_room())
	s.act(SessionAction.RECORD)
	K.advance_until_phase_changes(s, 10.0)
	var sc := K.tape_a_script()
	var tick := 0
	var death_tick := -1
	var accepted_after_death := 0
	while s.phase == SessionPhase.RECORDING and tick < 100000:
		var ok := s.tick_local(sc.input(tick))
		for e: SimEvent in s.drain_events():
			if e.type == SimEventType.SELF_DEATH and e.tape == 0 and death_tick < 0:
				death_tick = tick
		if death_tick >= 0 and tick > death_tick and ok:
			accepted_after_death += 1
		tick += 1
		if tick == 200:
			var me := s.current_frame().snap.actor(0)
			assert_eq(me.life, OD.LifeState.REC_GHOST, K.say("TEST-07", "the live self after death"))
			assert_true(me.live, K.say("TEST-07", "it is still the controlled take"))
			var deck := s.view().decks[0]
			assert_eq(deck.status, DeckStatus.RECORDING, K.say("TEST-07", "the deck is still recording"))
			assert_eq(deck.life, OD.LifeState.REC_GHOST)
	if not assert_true(death_tick >= 0, K.say("TEST-07", "the turret kills the take early")):
		return
	assert_true(death_tick < 100, "died at local tick %d" % death_tick)
	assert_eq(tick, s.tape_ticks, K.say("TEST-07", "the take ran its whole allowance after death"))
	assert_eq(accepted_after_death, s.tape_ticks - death_tick - 1, K.say("TEST-07", "every tick after death was recorded"))
	assert_eq(s.pending_tape.ticks, s.tape_ticks, K.say("TEST-07", "the tape is full length"))
	# Major ghost visual distinction: the recording ghost's style differs from the living self in
	# body, opacity and marker, and its HUD state reads differently (words + icon, not colour only).
	var alive := ActorStyle.params(ActorStyle.select(OD.LifeState.ALIVE, true))
	var ghost := ActorStyle.params(ActorStyle.select(OD.LifeState.REC_GHOST, true))
	assert_ne(ghost.body, alive.body, K.say("TEST-07", "body treatment"))
	assert_true(ghost.opacity < alive.opacity - 0.3, K.say("TEST-07", "the ghost is translucent"))
	assert_ne(ghost.marker, alive.marker, K.say("TEST-07", "the ghost carries a marker"))
	var ba := HudModel.life_badge(OD.LifeState.ALIVE, true)
	var bg := HudModel.life_badge(OD.LifeState.REC_GHOST, true)
	assert_ne(bg.label, ba.label, K.say("TEST-07", "HUD wording"))
	assert_ne(bg.icon, ba.icon, K.say("TEST-07", "HUD icon"))


## TEST-08 - Approach a locked door while actively recording after death.
## Expected: "Normal movement collision still applies; the recording ghost cannot simply phase through."
func test_TEST08_the_recording_ghost_still_collides_with_a_locked_door() -> void:
	var locked := K.rescue_room(4, SignalExpr.of_const(false))
	var take := S.record_take(locked, 0, 1.0, K.tape_a_script())
	var death := K.first_event(take.events, SimEventType.SELF_DEATH, 0)
	if not assert_true(death != null, K.say("TEST-08", "the take dies first")):
		return
	var max_x := -INF
	var pressed_frames := 0
	for f: FrameSnapshot in take.frames:
		var a := f.actor(0)
		if f.sub > death.sub:
			assert_eq(a.life, OD.LifeState.REC_GHOST)
			max_x = maxf(max_x, a.x)
			if a.x > 5.0 and absf(a.y - 3.5) < 0.5:
				pressed_frames += 1
	# The door cell is column 6 ([6, 7) in x); the self's body radius keeps it short of x = 6.
	assert_true(max_x < 6.0 - 0.29, K.say("TEST-08", "the ghost got to x = %.3f, through the locked door" % max_x))
	assert_true(pressed_frames > 10, K.say("TEST-08", "the ghost walked up to the door and was stopped there"))
	# The same input in the open-door room walks through: the door, not the input, stopped it.
	var open_take := S.record_take(K.rescue_room(), 0, 1.0, K.tape_a_script())
	assert_true(open_take.frames[open_take.frames.size() - 1].actor(0).x > 7.0, K.say("TEST-08", "control: with the door open the ghost passes"))


## TEST-09 - Attack and flip a switch as the active recording ghost.
## Expected: "They affect that provisional recording run."
func test_TEST09_the_recording_ghosts_attack_and_switch_affect_its_provisional_run() -> void:
	var take := S.record_take(K.rescue_room(), 0, 1.0, K.tape_a_script())
	var death := K.first_event(take.events, SimEventType.SELF_DEATH, 0)
	var kill := K.first_event(take.events, SimEventType.KILL, -1, "g1")
	if not assert_true(death != null and kill != null, K.say("TEST-09", "death then a kill in the recording")):
		return
	assert_eq(kill.tape, 0, K.say("TEST-09", "the ghost's strike killed the grunt"))
	assert_true(kill.sub > death.sub, K.say("TEST-09", "after the death"))
	var flips := K.events_of(take.events, SimEventType.INTERACT, 0, "lever")
	assert_eq(flips.size(), 1, K.say("TEST-09", "the ghost flipped the lever"))
	if flips.size() == 1:
		assert_true(flips[0].sub > death.sub)
		assert_eq(flips[0].detail, "on")
	assert_eq(K.events_of(take.events, SimEventType.DOOR, -1, "gate").size(), 1, K.say("TEST-09", "the switch opened the door in this run"))
	assert_true(take.frames[take.frames.size() - 1].mech("gate").on, K.say("TEST-09", "the door is open at the end of the take"))
	assert_true(take.frames[take.frames.size() - 1].actor(0).x > 7.0, K.say("TEST-09", "it walked through the door it opened"))
	# Provisional: the live run's own outcome sees the objective done, yet no self is alive.
	assert_true(take.outcome.objective_complete, K.say("TEST-09", "the provisional run latched the objective"))
	assert_eq(take.outcome.survivors, [], K.say("TEST-09", "and it is still a dead take"))


## TEST-10 - Replay the same tape and let it die before those events.
## Expected: "Later attack/switch effects do not occur; its non-interactive ghost continues the path."
func test_TEST10_replayed_the_dead_tapes_later_attack_and_switch_do_not_occur_and_its_ghost_keeps_the_path() -> void:
	var level := K.rescue_room()
	var take := S.record_take(level, 0, 1.0, K.tape_a_script())
	var res := K.resolve(level, [take.tape])
	var death := K.first_event(res.events, SimEventType.SELF_DEATH, 0)
	if not assert_true(death != null, K.say("TEST-10", "it dies again in the replay")):
		return
	assert_eq(K.events_of(res.events, SimEventType.SELF_DEATH, 0).size(), 1)
	assert_eq(K.events_of(res.events, SimEventType.KILL).size(), 0, K.say("TEST-10", "the later attack has no effect"))
	assert_eq(K.events_of(res.events, SimEventType.HIT, 0).size(), 0, K.say("TEST-10", "the later attack lands nothing"))
	assert_eq(K.events_of(res.events, SimEventType.INTERACT).size(), 0, K.say("TEST-10", "the later switch has no effect"))
	var shut := true
	for f: FrameSnapshot in res.frames:
		shut = shut and not f.mech("gate").on
	assert_true(shut, K.say("TEST-10", "the door stays shut for the whole run"))
	assert_true(res.frames[res.frames.size() - 1].enemy("g1").alive, K.say("TEST-10", "the grunt survives"))
	# Its ghost continues the recorded path exactly (through the shut door: a playback ghost passes
	# through everything).
	var off := 0
	var compared := 0
	for f: FrameSnapshot in take.frames:
		var g := S.frame_exact(res.frames, f.sub)
		if g == null:
			continue
		compared += 1
		if g.actor(0).x != f.actor(0).x or g.actor(0).y != f.actor(0).y:
			off += 1
		if g.sub > death.sub:
			assert_eq(g.actor(0).life, OD.LifeState.GHOST, K.say("TEST-10", "non-interactive ghost after death at sub %d" % g.sub))
	assert_true(compared > 100)
	assert_eq(off, 0, K.say("TEST-10", "replay frames off the recorded path"))
	assert_true(res.frames[res.frames.size() - 1].actor(0).x > 7.0, K.say("TEST-10", "the ghost walked on through the closed door"))
	assert_false(res.outcome.win)


## TEST-11 - Prevent the tape's old fatal hit.
## Expected: "Later recorded actions can be effective, subject to current world and sync state."
func test_TEST11_once_the_fatal_hit_is_prevented_the_later_recorded_actions_take_effect() -> void:
	var level := K.rescue_room()
	var tapes := K.rescue_win_tapes(level)
	var alone := K.resolve(level, [tapes[0]])
	var res := K.resolve(level, tapes)
	assert_eq(K.events_of(res.events, SimEventType.KILL, 1, "t1").size(), 1, K.say("TEST-11", "B destroys the turret first"))
	assert_eq(K.events_of(res.events, SimEventType.SELF_DEATH, 0).size(), 0, K.say("TEST-11", "A's old fatal hit is prevented"))
	var kill := K.first_event(res.events, SimEventType.KILL, 0, "g1")
	assert_true(kill != null, K.say("TEST-11", "A's later recorded strike is now effective"))
	assert_eq(K.events_of(res.events, SimEventType.INTERACT, 0, "lever").size(), 1, K.say("TEST-11", "A's later switch is now effective"))
	assert_true(res.frames[res.frames.size() - 1].mech("gate").on, K.say("TEST-11", "the door opens"))
	assert_eq(K.events_of(res.events, SimEventType.DESYNC, 0).size(), 0, K.say("TEST-11", "A stays synced, so its path through the opened door is valid"))
	assert_true(res.outcome.win)
	assert_eq(res.outcome.survivors, [0, 1])
	# Subject to the current world: the same recorded actions did nothing while A was dead (TEST-10),
	# and the swing that now kills fires at its recorded substep against the grunt where it is now.
	assert_eq(K.events_of(alone.events, SimEventType.KILL, 0).size(), 0)
	var swing := K.first_event(res.events, SimEventType.SWING, 0)
	if kill != null and swing != null:
		assert_eq(kill.sub, swing.sub, K.say("TEST-11", "fixed trigger, outcome resolved against the current world"))


## TEST-12 - Kill a previously surviving earlier tape at a new time.
## Expected: "From that moment, it becomes a non-interactive playback ghost."
func test_TEST12_an_earlier_tape_killed_at_a_new_time_is_a_non_interactive_ghost_from_that_moment() -> void:
	var both := K.golden_run("ghost-scenario-d")
	var solo := K.golden_run("ghost-scenario-d", 1)
	if not assert_true(both.resolution != null and solo.resolution != null, "golden ghost-scenario-d runs: %s" % [both.errors]):
		return
	assert_eq(K.events_of(solo.resolution.events, SimEventType.SELF_DEATH, 0).size(), 0, K.say("TEST-12", "alone, tape A survives"))
	assert_eq(K.events_of(solo.resolution.events, SimEventType.INTERACT, 0, "lamp").size(), 1, K.say("TEST-12", "alone, A's lamp switch works"))
	var res := both.resolution
	var deaths := K.events_of(res.events, SimEventType.SELF_DEATH, 0)
	if not assert_eq(deaths.size(), 1, K.say("TEST-12", "B's door exposes A, which dies at a new time")):
		return
	var at := deaths[0].sub
	var life_ok := true
	var path_ok := true
	for i: int in res.frames.size():
		var f := res.frames[i]
		var a := f.actor(0)
		var expect_life := OD.LifeState.GHOST if f.sub > at else OD.LifeState.ALIVE
		life_ok = life_ok and a.life == expect_life
		var g := solo.resolution.frames[i]
		path_ok = path_ok and a.x == g.actor(0).x and a.y == g.actor(0).y
	assert_true(life_ok, K.say("TEST-12", "alive until the death substep %d, ghost from then on" % at))
	assert_true(path_ok, K.say("TEST-12", "the ghost keeps its recorded path exactly"))
	assert_eq(K.events_of(res.events, SimEventType.INTERACT, 0, "lamp").size(), 0, K.say("TEST-12", "its later switch does not count"))
	assert_false(res.frames[res.frames.size() - 1].mech("lamp").on, K.say("TEST-12", "the lamp stays off"))
	var shots_after := 0
	for e: SimEvent in K.events_of(res.events, SimEventType.ENEMY_SHOT, 0):
		if e.sub > at:
			shots_after += 1
	assert_eq(shots_after, 0, K.say("TEST-12", "enemies stop targeting the ghost"))
	assert_eq(K.events_of(res.events, SimEventType.SELF_DEATH, 0).size(), 1, K.say("TEST-12", "never killed twice"))
	assert_true(res.outcome.win, K.say("TEST-12", "B wins alone"))
	assert_eq(res.outcome.survivors, [1])


## TEST-23 - Kill three selves and complete the objective with one survivor.
## Expected: "The survival rule permits success."
func test_TEST23_three_selves_die_and_one_survivor_completing_the_objective_wins() -> void:
	var g := K.golden_run("survivors-one-wins")
	if not assert_true(g.resolution != null, "golden runs: %s" % [g.errors]):
		return
	var res := g.resolution
	var dead: Array = []
	for e: SimEvent in K.events_of(res.events, SimEventType.SELF_DEATH):
		dead.append(e.tape)
	dead.sort()
	assert_eq(dead, [0, 1, 2], K.say("TEST-23", "three selves die"))
	assert_true(res.outcome.objective_complete, K.say("TEST-23", "the objective is complete"))
	assert_eq(res.outcome.survivors, [3], K.say("TEST-23", "one survivor"))
	assert_true(res.outcome.win, K.say("TEST-23"))
	assert_eq(res.outcome.reason, &"")


## TEST-24 - Complete an objective with no survivors.
## Expected: "The survival requirement is not met."
func test_TEST24_an_objective_completed_with_no_survivor_does_not_meet_the_survival_requirement() -> void:
	var g := K.golden_run("survivors-none-fails")
	if not assert_true(g.resolution != null, "golden runs: %s" % [g.errors]):
		return
	var res := g.resolution
	assert_true(res.outcome.objective_complete, K.say("TEST-24", "the objective is complete"))
	assert_eq(res.outcome.survivors, [], K.say("TEST-24", "nobody survives"))
	assert_false(res.outcome.win, K.say("TEST-24"))
	assert_eq(res.outcome.reason, FailReason.NO_SURVIVOR, K.say("TEST-24", "the failure is the survival requirement"))
	var last := res.frames[res.frames.size() - 1].objective
	assert_eq([last.complete, last.survivors], [true, 0])
